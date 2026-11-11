import type { createClient } from "./server";
import { paginar } from "./paginar";

type Supabase = Awaited<ReturnType<typeof createClient>>;

/**
 * As versões dos documentos criadas a partir de `desdeIso` e quais delas JÁ têm o evento de extração
 * (`extracao_sombra`, gravado por `fn_registrar_campos_extraidos` com sucesso ou falha — 0016; o
 * `evento_auditoria_read` da 0003 deixa o usuário autenticado ler). Usada pela rota que recusa o que já
 * está em leitura e pela que acompanha: a mesma pergunta, uma implementação. Erro devolve `erro`, nunca
 * "nenhuma versão" (regra 1).
 */
export async function versoesDesde(supabase: Supabase, documentoIds: string[], desdeIso: string) {
  const vs = await paginar<{ id: string; documento_id: string }>((de, ate) =>
    supabase.from("documento_versao").select("id, documento_id")
      .in("documento_id", documentoIds).gte("criada_em", desdeIso)
      .order("id", { ascending: true }).range(de, ate),
  );
  if (vs.error) return { erro: vs.error.message };
  const versoes = vs.data;
  if (versoes.length === 0) return { versoes, comExtracao: new Set<string>() };
  const ev = await paginar<{ entidade_ref: string }>((de, ate) =>
    supabase.from("evento_auditoria").select("entidade_ref")
      .eq("acao", "extracao_sombra").gte("criado_em", desdeIso)
      .in("entidade_ref", versoes.map((v) => `documento_versao:${v.id}`))
      .order("id", { ascending: true }).range(de, ate),
  );
  if (ev.error) return { erro: ev.error.message };
  return { versoes, comExtracao: new Set(ev.data.map((e) => e.entidade_ref.replace("documento_versao:", ""))) };
}
