import type { createClient } from "./supabase/server";
import { paginar } from "./supabase/paginar";
import { estruturaDoCaso, type DocumentoParaExport } from "./export";
import { historicoDoModelo } from "./modelagem-linha";
import type { EntradaModeloInstitucional } from "./modelo-institucional";
import type { CampoExtraido } from "./types";

// AS LEITURAS DO CASO QUE O EXPORT E A TELA DE MODELAGEM FAZEM IGUAIS.
//
// As sugestões do realizado da tela passaram a sair das mesmas agregações históricas do
// arquivo exportado. Isso só é verdade se as duas pontas LEEM o caso do mesmo jeito — mesmas
// colunas, mesma ordem, mesma paginação —, então a consulta mora aqui e as duas a chamam. A
// ordem de `campo_extraido` (documento_versao_id, ordem, id) é o que dá sentido à detecção de
// subtotal por sequência impressa e o que torna a paginação correta (ver a rota do export).

type Cliente = Awaited<ReturnType<typeof createClient>>;

export function lerDocumentosDoCaso(supabase: Cliente, casoId: string) {
  return paginar<DocumentoParaExport>((de, ate) =>
    supabase
      .from("documento")
      .select(
        // `n_versao` é o que permite saber qual extração é a VIGENTE quando o mesmo arquivo
        // foi reextraído (Supabase/migrations/0026): sem ela as duas extrações entrariam
        // juntas e a soma da seção contaria as duas.
        `id, tipo_taxonomia,
           entidade:entidade_id(razao_social), periodo:periodo_id(tipo, referencia),
           documento_versao(id, nome_original, n_versao)`,
      )
      .eq("caso_id", casoId)
      .order("id", { ascending: true })
      .range(de, ate),
  );
}

export function lerCamposDasVersoes(supabase: Cliente, versaoIds: string[]) {
  return versaoIds.length
    ? paginar<CampoExtraido>((de, ate) =>
        supabase
          .from("campo_extraido")
          .select(
            "id, documento_versao_id, secao, secao_canonica, entidade_coluna, periodo_coluna, chave, valor_texto, valor_num, unidade, confianca, origem_pagina, ordem, status_aceite, aceito_por, aceito_em",
          )
          .in("documento_versao_id", versaoIds)
          // ORDEM DO DOCUMENTO (Supabase/migrations/0027). Sem ela a detecção de "subtotal
          // impresso acima dos seus componentes" não tem sinal. `nullsFirst: false` mantém a
          // extração ANTIGA (ordem nula) no fim; `id` fecha o desempate e torna a ordem
          // TOTAL, que é o que faz a paginação não repetir nem omitir linha.
          .order("documento_versao_id", { ascending: true })
          .order("ordem", { ascending: true, nullsFirst: false })
          .order("id", { ascending: true })
          .range(de, ate),
      )
    : Promise.resolve({ data: [] as CampoExtraido[], error: null, truncado: false });
}

/** Uma linha de `fn_valores_por_ano` com a proveniência da célula (0125). */
export interface ValorPorAnoDoCaso {
  rotulo_norm: string; secao_canonica: string | null; ano: number; valor: number;
  arquivo: string | null; origem_pagina: number | null; confianca: number | null;
  status_aceite: string | null; aceito_por: string | null;
}

export function lerValoresPorAno(supabase: Cliente, casoId: string, entidade: string) {
  // A ordem da função é (rótulo, ano); a seção entra como desempate final porque o mesmo
  // rótulo existe em seções diferentes — é o trio que a função agrupa, ou seja, o que torna a
  // ordem TOTAL.
  return paginar<ValorPorAnoDoCaso>((de, ate) =>
    supabase.rpc("fn_valores_por_ano", { p_caso_id: casoId, p_entidade: entidade })
      .order("rotulo_norm", { ascending: true })
      .order("ano", { ascending: true })
      .order("secao_canonica", { ascending: true, nullsFirst: true })
      .range(de, ate));
}

/** Tudo o que o realizado precisa do banco: o que o export lê, pelas mesmas funções. */
export interface LeituraDoRealizado {
  documentos: DocumentoParaExport[];
  campos: CampoExtraido[];
  valores: ValorPorAnoDoCaso[];
  /** a primeira consulta que falhou ou foi cortada pelo teto — `null` quando leu tudo */
  problema: string | null;
}

export async function lerRealizadoDoCaso(
  supabase: Cliente, casoId: string, entidade: string,
): Promise<LeituraDoRealizado> {
  const lerCampos = async () => {
    const docs = await lerDocumentosDoCaso(supabase, casoId);
    if (docs.error) return { docs, campos: null };
    const ids = docs.data.flatMap((d) => (d.documento_versao ?? []).map((v) => v.id));
    return { docs, campos: await lerCamposDasVersoes(supabase, ids) };
  };
  const [{ docs, campos }, valores] = await Promise.all([lerCampos(), lerValoresPorAno(supabase, casoId, entidade)]);
  // A primeira consulta que falhou, nesta ordem; depois o corte pelo teto.
  const falhas: Array<[unknown, string]> = [
    [docs.error, `documentos: ${docs.error?.message}`],
    [campos?.error, `linhas extraídas: ${campos?.error?.message}`],
    [valores.error, `valores por ano (fn_valores_por_ano): ${valores.error?.message}`],
    [docs.truncado || campos?.truncado || valores.truncado, "a leitura bateu o teto de segurança e foi cortada"],
  ];
  const problema = falhas.find(([houve]) => houve)?.[1] ?? null;
  return { documentos: docs.data, campos: campos?.data ?? [], valores: valores.data, problema };
}

/**
 * A entrada do modelo institucional, mínima: só o histórico. É o que `agregadosDoRealizado`
 * precisa — as MESMAS linhas, os mesmos subtotais por ordem impressa e a mesma escala que o
 * export entrega ao modelo —, sem premissas, vínculos nem macro, que não entram em soma
 * histórica nenhuma.
 */
export function entradaDoRealizado(
  entidade: string, ultimoReal: number,
  linhasDoBanco: Parameters<typeof historicoDoModelo>[0],
  leitura: Pick<LeituraDoRealizado, "documentos" | "campos" | "valores">,
): EntradaModeloInstitucional {
  const h = historicoDoModelo(linhasDoBanco, leitura.valores, ultimoReal);
  return {
    caso: { nome: "", produto: "" }, agora: new Date(), entidade, setor: null,
    anosHistoricos: h.anosHistoricos, anosProjetados: [],
    stressPct: 0, caixaMinimo: 0, aliquotaTributos: 0,
    linhas: h.linhas, premissas: [], vinculos: [], macro: [], unidade: h.unidade,
    ...estruturaDoCaso(leitura.documentos, leitura.campos, entidade),
  };
}
