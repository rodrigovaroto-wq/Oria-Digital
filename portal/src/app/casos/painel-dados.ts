import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import { paginar } from "@/lib/supabase/paginar";
import { contarLinhasPorVersao } from "@/lib/supabase/linhas-por-versao";
import { ESTADOS_EM_ABERTO } from "@/lib/pendencia";
import type { Caso, Pendencia } from "@/lib/types";

// AS LEITURAS DO PAINEL, UMA VEZ POR REQUISIÇÃO E COMPARTILHADAS ENTRE OS BLOCOS.
//
// O painel chega por streaming: cada bloco é um componente assíncrono dentro de um `<Suspense>` e pede
// o que precisa. `cache` do React faz o pedido repetido devolver a MESMA promessa, então a lista de
// pendências, lida para o veredito, a fila, os indicadores e "Seus mandatos", vai ao banco UMA vez —
// e a lista de documentos, para os indicadores e "O que chegou", também. Nenhuma consulta mudou: as
// mesmas colunas, os mesmos filtros, o mesmo `paginar`. O que mudou é ONDE elas começam.
//
// MEDIDO (mandato do dono, 81 mandatos, 2.165 documentos, 2.088 pendências em aberto): lidas em
// sequência — casos, depois documentos e pendências em paralelo, DEPOIS `lote_execucao`, DEPOIS a
// contagem de linhas — somavam 2.899 ms; as duas listas paginadas (4 idas de ~0,35 s cada, uma após a
// outra) respondem por 1.344 e 1.688 ms. `lote_execucao` (371 ms) só precisa dos ids dos casos, não
// de documentos nem de pendências: aqui ela parte junto com elas.

export type DocumentoNoPainel = {
  id: string;
  caso_id: string;
  tipo_taxonomia: string | null;
  status: string;
  criado_em: string;
  documento_versao: Array<{ id: string }> | null;
};

export type UsoDoLote = {
  contas_nos_documentos: number | null;
  contas_extraidas: number | null;
};

type Lida<T> = { data: T[]; error: { message: string } | null; truncado: boolean };
const vazia = <T>(): Lida<T> => ({ data: [], error: null, truncado: false });

// `fechado_em` é filtrado em JavaScript, não no `where`: num banco sem a 0114 a coluna não existe, e
// o filtro derrubaria a tela inteira em vez de degradar.
export const lerCasos = cache(async () => {
  const supabase = await createClient();
  return paginar<Caso>((de, ate) =>
    supabase
      .from("caso")
      .select("id, nome, status, criado_em, fechado_em")
      .order("criado_em", { ascending: false })
      .range(de, ate),
  );
});

/** Os mandatos, já separados em ativos e com o nome por id. Sem consulta própria. */
export const lerCarteira = cache(async () => {
  const casosRes = await lerCasos();
  const casos = casosRes.data;
  const ativos = casos.filter((c) => !c.fechado_em);
  return {
    casosRes,
    casos,
    ativos,
    ids: casos.map((c) => c.id),
    idsAtivos: ativos.map((c) => c.id),
    nomePorCaso: new Map(casos.map((c) => [c.id, c.nome] as const)),
  };
});

// Todos os mandatos, não só os ativos: mandato encerrado com sucesso é justamente o que se quer no
// denominador de uma média de tempo. Paginada por CORREÇÃO (alimenta cálculo por linha).
export const lerDocumentos = cache(async (): Promise<Lida<DocumentoNoPainel>> => {
  const { ids } = await lerCarteira();
  if (!ids.length) return vazia();
  const supabase = await createClient();
  return paginar<DocumentoNoPainel>((de, ate) =>
    supabase
      .from("documento")
      .select("id, caso_id, tipo_taxonomia, status, criado_em, documento_versao(id)")
      .in("caso_id", ids)
      .order("criado_em", { ascending: false })
      .range(de, ate),
  );
});

// A fila é só dos ativos: pendência de mandato encerrado não é trabalho de hoje.
export const lerPendencias = cache(async (): Promise<Lida<Pendencia>> => {
  const { idsAtivos } = await lerCarteira();
  if (!idsAtivos.length) return vazia();
  const supabase = await createClient();
  return paginar<Pendencia>((de, ate) =>
    supabase
      .from("pendencia")
      .select("id, caso_id, tipo, severidade, estado, descricao, documento_id, criada_em, motivo")
      .in("caso_id", idsAtivos)
      .in("estado", [...ESTADOS_EM_ABERTO])
      .order("criada_em", { ascending: false })
      .range(de, ate),
  );
});

// A cobertura (0115), tolerante a falha: sem a migration a tabela não existe, e `error` vira "sem
// medição" em vez de uma tela vermelha. Só as duas colunas da razão.
export const lerUso = cache(async (): Promise<Lida<UsoDoLote>> => {
  const { ids } = await lerCarteira();
  if (!ids.length) return vazia();
  const supabase = await createClient();
  return paginar<UsoDoLote>((de, ate) =>
    supabase
      .from("lote_execucao")
      .select("contas_nos_documentos, contas_extraidas")
      .in("caso_id", ids)
      .order("id", { ascending: true })
      .range(de, ate),
  );
});

// A contagem por documento serve só aos 10 itens visíveis em "O que chegou", então é escopada a eles.
export const lerRecentes = cache(async () => {
  const documentosRes = await lerDocumentos();
  const recentes = documentosRes.data.slice(0, 10);
  const versoes = recentes
    .flatMap((d) => (d.documento_versao ?? []).map((v) => v.id))
    .filter(Boolean);
  const supabase = await createClient();
  // Paginada: uma consulta só era cortada em 1000 linhas pelo PostgREST, em silêncio.
  const { porVersao, incompleto } = await contarLinhasPorVersao(supabase, versoes);
  return { recentes, linhasPorVersao: porVersao, linhasIncompletas: incompleto };
});

/**
 * O que a fila de pendências diz, em números, para quem precisa dele. Falha de leitura NÃO é "nada em
 * aberto": com `error`, `pendencias` é [] e tudo o que deriva dela (veredito, "travados", fila, chip
 * "travado") diria que nada trava. `pendenciasLidas` é a única fonte do "não sei" nestes blocos.
 */
export const lerTrava = cache(async () => {
  const pendenciasRes = await lerPendencias();
  const pendencias = pendenciasRes.data;
  const bloqueantes = pendencias.filter((p) => p.severidade === "bloqueante");
  const travadasPorCaso = new Map<string, number>();
  for (const p of bloqueantes) travadasPorCaso.set(p.caso_id, (travadasPorCaso.get(p.caso_id) ?? 0) + 1);
  return {
    pendenciasRes,
    pendencias,
    pendenciasLidas: !pendenciasRes.error,
    nBloqueantes: bloqueantes.length,
    casosTravados: travadasPorCaso.size,
    travadasPorCaso,
  };
});
