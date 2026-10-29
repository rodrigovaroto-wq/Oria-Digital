import { cache } from "react";
import { createClient } from "./server";
import { decidirEnvioAoMandato, interpretarPapel, permissoes, type AcessoLido, type Permissoes } from "../acesso";

// O PAPEL DE QUEM ESTÁ NA REQUISIÇÃO, lido UMA vez e entregue a todas as telas.
//
// `cache` do React memoiza dentro de UMA renderização do servidor: o layout do mandato, a página e
// o casco chamam estas funções e só a primeira vai ao banco (`fn_meu_papel`; e, dentro de um
// mandato, `fn_pode_escrever_caso`). Layout e página do App Router renderizam em paralelo e não se
// passam props, então o `cache` é o jeito de "ler uma vez" sem o componente de baixo reperguntar.
// Fora de uma renderização (route handler, server action) a memória não existe e cada chamada
// pergunta de novo — por isso as rotas chamam uma vez só, e só quando precisam.
//
// A RLS é a autoridade, e estas respostas só servem para a tela não oferecer o clique que o banco
// recusaria. Falha de leitura NÃO vira "sem papel" nem "sem permissão": ver `acesso.ts`.
export const lerAcesso = cache(async (): Promise<AcessoLido> => {
  const supabase = await createClient();
  try {
    return interpretarPapel(await supabase.rpc("fn_meu_papel"));
  } catch (e) {
    return { estado: "falha", detalhe: e instanceof Error ? e.message : String(e) };
  }
});

export const lerPermissoes = cache(async (): Promise<Permissoes> => permissoes(await lerAcesso()));

/** As permissões DENTRO de um mandato: o papel (já lido) + `fn_pode_escrever_caso(caso)`, que só o Analista precisa. */
export const lerPermissoesDoMandato = cache(async (casoId: string): Promise<Permissoes> => {
  const acesso = await lerAcesso();
  // Sócio e Leitura se resolvem pelo papel; só o Analista depende da alocação neste mandato.
  if (acesso.estado !== "ok" || acesso.papel !== "analista") return permissoes(acesso);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("fn_pode_escrever_caso", { p_caso: casoId });
  return permissoes(acesso, error || typeof data !== "boolean" ? null : data);
});

/**
 * `decidirEnvioAoMandato` com as consultas feitas: o mandato pelo NOME sob a RLS do usuário (limit 2,
 * para enxergar duplicata) e `fn_pode_escrever_caso`. Só o Analista precisa delas. Para rotas (sem
 * memória de renderização): chame uma vez por requisição.
 */
export async function conferirEnvioAoMandato(nome: string) {
  const acesso = await lerAcesso();
  if (acesso.estado !== "ok" || acesso.papel !== "analista") return decidirEnvioAoMandato(acesso, null);
  const supabase = await createClient();
  const { data, error } = await supabase.from("caso").select("id").eq("nome", nome).limit(2);
  if (error) return decidirEnvioAoMandato(acesso, null);
  const linhas = (data as Array<{ id: string }> | null) ?? [];
  if (linhas.length !== 1) return decidirEnvioAoMandato(acesso, { n: linhas.length, podeEscrever: null });
  const r = await supabase.rpc("fn_pode_escrever_caso", { p_caso: linhas[0].id });
  return decidirEnvioAoMandato(acesso, { n: 1, podeEscrever: r.error || typeof r.data !== "boolean" ? null : r.data });
}
