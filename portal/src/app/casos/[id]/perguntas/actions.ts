"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { textoDeFalhaDaAcao } from "@/lib/acesso";

// A AÇÃO HUMANA SOBRE UMA PERGUNTA SUGERIDA — `fn_registrar_pergunta_acao`
// (Supabase/migrations/0120). O portal não decide nada aqui: ele encaminha o que o
// analista clicou e devolve a recusa do banco quando há uma.
//
// O TEXTO VAI JUNTO, E ISSO NÃO É DETALHE. A função EXIGE o texto renderizado
// para registrar um envio, e a coluna o congela: a pergunta é um template com
// marcadores ({data_base}, {saldo_mutuos}) resolvidos na hora da leitura, e o
// template pode mudar depois. Sem o texto, a trilha diria QUE se perguntou sem
// dizer O QUE foi perguntado a um cliente — e isso é fato histórico, não estado
// atual. É por isso que o formulário carrega o texto inteiro num campo oculto,
// em vez de o servidor rerrenderizar a pergunta na hora de gravar: o que se
// grava tem de ser exatamente o que estava na tela de quem clicou.
export async function registrarAcaoDaPergunta(casoId: string, formData: FormData) {
  const supabase = await createClient();

  const codigo = String(formData.get("codigo") || "").trim();
  const acao = String(formData.get("acao") || "").trim();
  const texto = String(formData.get("texto") || "");
  // Campo oculto vem como string SEMPRE: uma pergunta da espécie `sempre` não
  // tem empresa, e mandar a string vazia como uuid faz o Postgres recusar por
  // sintaxe — que apareceria na tela como "falha ao registrar", sem dizer que a
  // culpa é de um campo que deveria ser nulo.
  const entidadeId = String(formData.get("entidade_id") || "").trim() || null;

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data, error } = await supabase.rpc("fn_registrar_pergunta_acao", {
    p_caso_id: casoId,
    p_codigo: codigo,
    p_acao: acao,
    p_texto: texto,
    p_autor: user?.email ?? "portal:desconhecido",
    p_entidade_id: entidadeId,
  });

  if (error) {
    throw new Error(textoDeFalhaDaAcao("Falha ao registrar a pergunta", error));
  }

  // RECUSA no payload, não como erro de Postgres — o padrão da casa (0036,
  // 0037, 0106, 0111). Ler este campo é obrigatório: sem isto, `error` nulo
  // faria a recusa passar por sucesso e a tela recarregaria como se a pergunta
  // tivesse sido registrada.
  const r = data as { recusado?: boolean; motivo_recusa?: string } | null;
  if (r?.recusado) {
    throw new Error(r.motivo_recusa ?? "Registro recusado.");
  }

  revalidatePath(`/casos/${casoId}/perguntas`);
}

// O MESMO REGISTRO, PARA O LOTE — e por que não é a função acima chamada direto do cliente.
// Em produção o Next troca a mensagem de um erro lançado por uma server action por um texto
// genérico e sem a recusa do banco; no lote o analista precisa saber QUAL pergunta falhou e
// POR QUÊ. Então o lote chama esta, que devolve o motivo como dado, e a que lança segue a
// mesma de antes (os formulários dos cartões não mudam).
export async function registrarAcaoSemExcecao(
  casoId: string,
  formData: FormData,
): Promise<{ ok: true } | { ok: false; erro: string }> {
  try {
    await registrarAcaoDaPergunta(casoId, formData);
    return { ok: true };
  } catch (e) {
    return { ok: false, erro: e instanceof Error ? e.message : "falha desconhecida" };
  }
}
