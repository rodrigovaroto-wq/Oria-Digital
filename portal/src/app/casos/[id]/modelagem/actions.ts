"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { MENSAGEM_SEM_PERMISSAO, ehNegacaoDePermissao, textoDeFalhaDaAcao } from "@/lib/acesso";

// As ações da seção Modelagem (Supabase/migrations/0038).
//
// TODA a regra vive no Postgres — este arquivo só encaminha e mostra o resultado.
// Não é preferência de estilo: `fn_aplicar_premissa_em_lote` precisa das linhas de
// `campo_extraido` para saber quais existem, e `fn_vincular_linha_premissa` recusa
// premissa que o caso não ativou. Reimplementar qualquer uma dessas duas coisas
// aqui criaria uma segunda verdade sobre a mesma pergunta.
//
// PADRÃO DE RECUSA (0036/0037/0038): as funções devolvem `recusado: true` no
// payload em vez de levantar exceção — exceção em plpgsql desfaz o registro da
// própria tentativa. Ler esse campo é OBRIGATÓRIO em cada ação: sem isso, `error`
// nulo faria a recusa passar por sucesso, e a tela recarregaria como se algo
// tivesse sido salvo.
//
// -----------------------------------------------------------------------------
// TODA AÇÃO DAQUI DEVOLVE `Resultado`. NENHUMA levanta exceção, NENHUMA navega.
//
// Foram três tentativas até chegar aqui, e vale registrar por que as duas
// primeiras estavam erradas:
//
//   1. `throw new Error(motivo)` — sem `error.tsx` na rota, o React DESMONTA a
//      subárvore: a seção 3 sumia da página. E em produção o Next REDIGE a
//      mensagem de erro de servidor, então nem com fronteira o analista leria
//      "esta linha é um subtotal": leria "an error occurred".
//   2. `redirect(...?aviso=...)` — resolveu a mensagem e trocou o defeito de
//      lugar. Redirect é NAVEGAÇÃO: remonta a árvore inteira, joga o scroll para
//      o topo e apaga tudo que estava sendo editado e ainda não foi salvo. Quem
//      estava no meio da seção 3 via, de novo, a seção "fechar sozinha".
//   3. RETORNAR o resultado, que é o que está aqui. `useActionState` no cliente
//      recebe o objeto, mostra a mensagem NO LUGAR onde o clique aconteceu, e o
//      `revalidatePath` atualiza os dados do servidor SEM desmontar nada: os
//      componentes de cliente ficam na mesma posição da árvore e o estado local
//      (as escolhas ainda não salvas das outras seções) sobrevive.
//
// A regra que fica: recusa esperada NÃO é exceção, e feedback de ação NÃO é
// navegação. As duas coisas custaram uma rodada de teste do dono cada.
// -----------------------------------------------------------------------------

type Recusavel = { recusado?: boolean; motivo_recusa?: string } | null;

/** O que toda ação desta tela devolve. `null` = ainda não rodou nesta sessão. */
export type Resultado = { tom: "ok" | "erro"; texto: string } | null;

const erro = (texto: string): Resultado => ({ tom: "erro", texto });
const ok = (texto: string): Resultado => ({ tom: "ok", texto });

async function autor() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  return user?.email ?? "portal:desconhecido";
}

/** Recusa do banco → mensagem. `null` quando não houve recusa. */
function recusa(data: unknown, fallback: string): Resultado {
  const r = data as Recusavel;
  return r?.recusado ? erro(r.motivo_recusa ?? fallback) : null;
}

export async function definirParametros(
  casoId: string, _prev: Resultado, formData: FormData,
): Promise<Resultado> {
  const supabase = await createClient();
  const ultimo = Number(formData.get("ultimo_exercicio_real"));
  const { data, error } = await supabase.rpc("fn_definir_modelagem", {
    p_caso_id: casoId,
    p_entidade: String(formData.get("entidade") || "").trim() || null,
    p_ultimo_exercicio_real: Number.isFinite(ultimo) && ultimo > 0 ? ultimo : null,
    p_indice_macro: String(formData.get("indice_macro") || "").trim() || null,
    p_setor: String(formData.get("setor") || "").trim() || null,
    p_autor: await autor(),
    p_anos_projetados: Number(formData.get("anos_projetados")) || 5,
  });
  if (error) return erro(textoDeFalhaDaAcao("Falha ao salvar os parâmetros", error));
  const r = recusa(data, "Parâmetros recusados.");
  if (r) return r;
  revalidatePath(`/casos/${casoId}/modelagem`);
  return ok("Parâmetros do mandato salvos.");
}

export async function ativarPremissa(
  casoId: string, _prev: Resultado, formData: FormData,
): Promise<Resultado> {
  const supabase = await createClient();
  const codigo = String(formData.get("codigo") || "");

  // Valores por ano vêm como campos `valor_2026`, `valor_2027`… O ano SEM valor
  // fica FORA do jsonb de propósito: ausência é ausência, e a 0038 trata premissa
  // sem valor como "não projeta aquele ano" em vez de projetar com zero. Escrever
  // 0 aqui seria inventar a premissa mais perigosa que existe.
  const valores: Record<string, number> = {};
  for (const [k, v] of formData.entries()) {
    if (!k.startsWith("valor_")) continue;
    const texto = String(v).trim().replace(",", ".");
    if (texto === "") continue;
    const n = Number(texto);
    if (Number.isFinite(n)) valores[k.slice("valor_".length)] = n;
  }

  const { data, error } = await supabase.rpc("fn_ativar_premissa", {
    p_caso_id: casoId,
    p_codigo: codigo,
    p_valores: valores,
    p_origem: String(formData.get("origem") || "digitado"),
    p_autor: await autor(),
  });
  if (error) return erro(textoDeFalhaDaAcao("Falha ao ativar a premissa", error));
  const r = recusa(data, "Premissa recusada.");
  if (r) return r;
  revalidatePath(`/casos/${casoId}/modelagem`);
  const n = Object.keys(valores).length;
  return ok(n === 0
    ? "Premissa ativada SEM valor — se for macro, o Focus preenche; senão ela não projeta ano nenhum."
    : `Premissa ativada com valor em ${n} ano(s).`);
}

// Remover a premissa do caso.
//
// POR QUE O BOTÃO PRECISOU EXISTIR: a tela tinha "Ativar" e "Atualizar", e nada
// que desfizesse. Premissa ativada por engano ficava no caso para sempre — e uma
// premissa ativa SEM valor é o que segura o "pronto" da conferência, então o
// engano travava o export do mandato inteiro.
//
// A CONFIRMAÇÃO É DAQUI, e não do `confirm()` do navegador: remover uma premissa
// aplicada em lote desfaz o vínculo de dezenas de linhas, e esse número só o
// banco conhece. O texto de volta diz quantas — é a única forma de quem clicou
// saber o tamanho do que desfez.
export async function desativarPremissa(
  casoId: string, _prev: Resultado, formData: FormData,
): Promise<Resultado> {
  const supabase = await createClient();
  const codigo = String(formData.get("codigo") || "");
  const { data, error } = await supabase.rpc("fn_desativar_premissa", {
    p_caso_id: casoId,
    p_codigo: codigo,
    p_autor: await autor(),
  });
  if (error) return erro(textoDeFalhaDaAcao("Falha ao remover a premissa", error));
  const r = recusa(data, "Remoção recusada.");
  if (r) return r;

  const d = data as {
    n_vinculos_desfeitos?: number; n_sazonalidades_desfeitas?: number;
  } | null;
  revalidatePath(`/casos/${casoId}/modelagem`);

  // O que foi desfeito, NOMEADO. "Premissa removida" sozinho esconderia que 44
  // linhas de uma seção deixaram de ser projetadas no mesmo clique.
  const partes = [
    d?.n_vinculos_desfeitos ? `${d.n_vinculos_desfeitos} linha(s) deixaram de ser projetadas por ela` : "",
    d?.n_sazonalidades_desfeitas ? `${d.n_sazonalidades_desfeitas} linha(s) perderam a curva mensal` : "",
  ].filter(Boolean);
  return ok(`Premissa removida${partes.length ? ` — ${partes.join(" e ")}` : ""}. `
    + "Os valores digitados ficam guardados: reativar devolve o que estava lá.");
}

// Salvar a seção inteira de uma vez.
//
// POR QUE ISTO EXISTE: no v35 a tela listou 236 linhas, cada uma com o seu botão
// `salvar`. Configurar as exceções depois do lote significava 236 idas ao
// servidor, uma por clique — e trabalho que dá 236 cliques é trabalho que não se
// faz. Aqui cada seção é UM formulário e UMA submissão.
//
// Só chama o banco para a linha que MUDOU (`orig__i` traz o valor que a tela
// carregou). Reenviar as 45 linhas de uma seção a cada salvamento gravaria
// `caso_linha_premissa` para linha que ninguém tocou — inclusive para a linha
// deliberadamente "não projetar" —, e a trilha de decisão passaria a registrar
// escolhas que o analista não fez.
export async function salvarSecao(
  casoId: string, _prev: Resultado, formData: FormData,
): Promise<Resultado> {
  const supabase = await createClient();
  const autorNome = await autor();

  const indices = new Set<string>();
  for (const k of formData.keys()) {
    const m = k.match(/^(?:premissa|sazonalidade|rotulo|entidade|orig|origSaz)__(\d+)$/);
    if (m) indices.add(m[1]);
  }

  const erros: string[] = [];
  let n = 0;
  for (const i of [...indices].sort((a, b) => Number(a) - Number(b))) {
    const premissa = String(formData.get(`premissa__${i}`) ?? "");
    const sazonalidade = String(formData.get(`sazonalidade__${i}`) ?? "");
    const orig = String(formData.get(`orig__${i}`) ?? "");
    const origSaz = String(formData.get(`origSaz__${i}`) ?? "");
    if (premissa === orig && sazonalidade === origSaz) continue;

    const rotulo = String(formData.get(`rotulo__${i}`) ?? "");
    const { data, error } = await supabase.rpc("fn_vincular_linha_premissa", {
      p_caso_id: casoId,
      p_secao_canonica: String(formData.get("secao_canonica") || "") || null,
      p_rotulo: rotulo,
      p_entidade: String(formData.get(`entidade__${i}`) || "") || null,
      p_premissa: premissa || null,
      p_autor: autorNome,
      p_sazonalidade: sazonalidade || null,
    });
    if (error) { erros.push(`${rotulo}: ${ehNegacaoDePermissao(error) ? MENSAGEM_SEM_PERMISSAO : error.message}`); continue; }
    // Recusa por linha NÃO aborta as outras: numa submissão de 45 linhas, parar
    // na primeira perderia as 44 decisões seguintes. Junta e relata.
    const r = data as Recusavel;
    if (r?.recusado) { erros.push(`${rotulo}: ${r.motivo_recusa ?? "recusado"}`); continue; }
    n++;
  }

  revalidatePath(`/casos/${casoId}/modelagem`);
  if (erros.length > 0) {
    return erro(`${n} linha(s) salva(s); ${erros.length} recusada(s). `
      + erros.slice(0, 4).join(" | "));
  }
  // Silêncio depois de salvar 30 linhas é indistinguível de não ter salvado.
  return ok(n === 0 ? "Nada mudou nesta seção — nada foi gravado."
    : `${n} linha(s) salva(s) nesta seção.`);
}

export async function aplicarEmLote(
  casoId: string, _prev: Resultado, formData: FormData,
): Promise<Resultado> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("fn_aplicar_premissa_em_lote", {
    p_caso_id: casoId,
    p_secao_canonica: String(formData.get("secao_canonica") || ""),
    p_premissa: String(formData.get("premissa") || ""),
    p_autor: await autor(),
    p_sazonalidade: String(formData.get("sazonalidade") || "") || null,
  });
  if (error) return erro(textoDeFalhaDaAcao("Falha ao aplicar em lote", error));
  const r0 = recusa(data, "Lote recusado.");
  if (r0) return r0;

  const r = data as { n_linhas?: number; n_ignoradas?: number } | null;
  revalidatePath(`/casos/${casoId}/modelagem`);

  // Lote que pega ZERO linha não é erro, mas também não pode passar por sucesso:
  // significa que a seção escolhida não tem CONTA nenhuma neste caso (só subtotal,
  // série mensal ou indicador), e quem clicou precisa saber disso agora — não ao
  // abrir o Excel.
  if (r && r.n_linhas === 0) {
    return erro("O lote não vinculou NENHUMA linha nessa seção. "
      + (r.n_ignoradas
        ? `As ${r.n_ignoradas} linha(s) da seção não são contas projetáveis (subtotal, série mensal `
          + "ou indicador derivado) — subtotal sai como soma dos componentes no Excel, e por isso "
          + "não recebe premissa."
        : "Confira a seção escolhida na lista de linhas abaixo."));
  }
  // E o lote que DEU certo também precisa dizer o que fez: quantas entraram e
  // quantas ficaram de fora. Antes ele não dizia nada, e "não aconteceu nada" e
  // "aconteceu tudo" tinham exatamente a mesma aparência na tela.
  return ok(`${r?.n_linhas ?? 0} conta(s) vinculada(s)`
    + (r?.n_ignoradas
      ? `; ${r.n_ignoradas} linha(s) ficaram de fora por não serem contas projetáveis `
        + "(subtotal, série mensal ou indicador)."
      : "."));
}
