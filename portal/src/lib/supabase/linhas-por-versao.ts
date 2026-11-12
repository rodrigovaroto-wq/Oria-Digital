import { paginar } from "./paginar";
import type { createClient } from "./server";

/**
 * Quantas linhas de `campo_extraido` cada versão de documento rendeu.
 *
 * UMA função, não duas cópias. Até 24/09/2026 esta conta morava inline no
 * painel (`casos/page.tsx`) e no detalhe do caso (`casos/[id]/page.tsx`), e as
 * duas já tinham divergido: o detalhe passava por `paginar`, o painel fazia uma
 * consulta só — e o PostgREST corta em 1000 linhas **sem erro nenhum**.
 * `verificar-linhas-por-versao.mts` prova, contra um servidor que corta em 1000,
 * que a contagem passa do teto.
 *
 * CAMINHO PRINCIPAL (0276): `fn_linhas_por_versao(p_versoes)` conta no banco, em UMA ida por
 * fatia (10.231 linhas: 12 idas paginadas, 5,2 s -> 1 ida, 0,2 s, soma idêntica). A função devolve
 * UMA linha por versão DISTINTA pedida, com 0 explícito; o teto de 1.000 do PostgREST continua
 * valendo para o NÚMERO DE VERSÕES na resposta, então o pedido é fatiado em lotes de 1.000 versões
 * distintas e cada resposta é conferida: "linhas devolvidas = versões distintas pedidas" é o sinal
 * POSITIVO de leitura completa. Resposta com menos versões que o pedido = cortada em silêncio =
 * `incompleto` (regra 1), nunca zero fabricado para a versão que faltou.
 *
 * CAMINHO DE RESERVA: banco sem a 0276 (função ausente: PGRST202/42883) cai na leitura paginada de
 * antes. O `.order("id")` não é enfeite: sem ordem estável, duas janelas de `range` podem devolver
 * a mesma linha duas vezes e pular outra. Qualquer OUTRO erro do RPC vira `incompleto`, sem cair
 * no paginado (um timeout do banco não se resolve repetindo a leitura mais pesada).
 *
 * `incompleto` é a contagem se declarando parcial (regra 1): verdadeiro quando o teto de
 * segurança de `paginar` cortou a leitura, uma página/fatia falhou, ou a resposta veio com menos
 * versões que o pedido. Achado da revisão do PR #244; a suíte prova.
 */
type Supabase = Awaited<ReturnType<typeof createClient>>;

/** O teto de linhas por resposta do PostgREST (`db-max-rows`, 1000 no Supabase). */
const FATIA = 1000;

type Resultado = { porVersao: Map<string, number>; incompleto: boolean };

async function contarPaginado(supabase: Supabase, versoes: string[]): Promise<Resultado> {
  const porVersao = new Map<string, number>();
  const { data, truncado, error } = await paginar<{ documento_versao_id: string }>((de, ate) =>
    supabase.from("campo_extraido").select("documento_versao_id")
      .in("documento_versao_id", versoes).order("id", { ascending: true }).range(de, ate));
  for (const l of data) porVersao.set(l.documento_versao_id, (porVersao.get(l.documento_versao_id) ?? 0) + 1);
  return { porVersao, incompleto: truncado || error !== null };
}

export async function contarLinhasPorVersao(supabase: Supabase, versoes: string[]): Promise<Resultado> {
  const porVersao = new Map<string, number>();
  if (versoes.length === 0) return { porVersao, incompleto: false };

  const distintas = [...new Set(versoes)];
  const fatias: string[][] = [];
  for (let i = 0; i < distintas.length; i += FATIA) fatias.push(distintas.slice(i, i + FATIA));

  const respostas = await Promise.all(fatias.map((f) => supabase.rpc("fn_linhas_por_versao", { p_versoes: f })));
  const ausente = respostas.find((r) => r.error && (r.error.code === "PGRST202" || r.error.code === "42883"));
  if (ausente) return contarPaginado(supabase, versoes);

  let incompleto = false;
  respostas.forEach((r, i) => {
    const linhas = (r.data as Array<{ documento_versao_id: string; linhas: number | string }> | null) ?? [];
    if (r.error || linhas.length !== fatias[i].length) incompleto = true;
    for (const l of linhas) porVersao.set(l.documento_versao_id, (porVersao.get(l.documento_versao_id) ?? 0) + Number(l.linhas));
  });
  return { porVersao, incompleto };
}
