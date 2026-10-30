"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { CHAVES_APRESENTACAO } from "@/lib/apresentacao/campos";
import { MENSAGEM_SEM_PERMISSAO, ehNegacaoDePermissao } from "@/lib/acesso";

// GRAVA UM CAPÍTULO DE CAMPOS DA APRESENTAÇÃO (`caso_apresentacao_campo`, 0205).
//
// Só chaves do catálogo são aceitas: uma chave fora dele seria gravada e nunca lida pelo gerador
// (o assert 9a prova que o catálogo inteiro chega ao deck). Campo deixado VAZIO apaga a linha — o
// slide volta a "[a preencher]" —, porque o banco recusa valor vazio (regra 1: vazio não é valor).
// O resultado volta como objeto, nunca como exceção nem redirect (mesmo padrão da Modelagem).
export type ResultadoCampos = { tom: "ok" | "erro"; texto: string } | null;

// O `casoId` é AMARRADO no servidor (`.bind` na página), não lido de campo oculto: um POST com outro
// uuid gravaria no caso alheio, e a RLS da 0205 (mesma de caso_premissa) não restringe por caso.
export async function salvarCamposApresentacao(casoId: string, _anterior: ResultadoCampos, form: FormData): Promise<ResultadoCampos> {
  const supabase = await createClient();
  const caso = await supabase.from("caso").select("id").eq("id", casoId).maybeSingle();
  if (caso.error || !caso.data) return { tom: "erro", texto: "Caso não encontrado — nada foi salvo." };
  const { data: { user } } = await supabase.auth.getUser();
  const autor = user?.email ?? "portal:desconhecido";
  const preenchidos: Array<{ caso_id: string; chave: string; valor: string; fonte: string; preenchido_por: string; preenchido_em: string }> = [];
  const vazios: string[] = [];
  for (const [k, v] of form.entries()) {
    if (!k.startsWith("campo:")) continue;
    const chave = k.slice("campo:".length);
    if (!CHAVES_APRESENTACAO.has(chave)) return { tom: "erro", texto: `Chave desconhecida: ${chave}.` };
    if (typeof v !== "string") return { tom: "erro", texto: `O campo ${chave} não veio como texto.` };
    const valor = v.trim();
    if (valor) {
      preenchidos.push({ caso_id: casoId, chave, valor, fonte: "tela de campos da apresentação",
        preenchido_por: autor, preenchido_em: new Date().toISOString() });
    } else vazios.push(chave);
  }
  if (preenchidos.length) {
    const { error } = await supabase.from("caso_apresentacao_campo").upsert(preenchidos, { onConflict: "caso_id,chave" });
    if (error) return { tom: "erro", texto: ehNegacaoDePermissao(error) ? MENSAGEM_SEM_PERMISSAO : `Não foi possível salvar: ${error.message}. Se a tabela não existe, a migration 0205 ainda não foi aplicada.` };
  }
  if (vazios.length) {
    // DELETE NEGADO PELA RLS NÃO É ERRO: a policy filtra a linha e o Postgres devolve "0 linhas", sem
    // código. Sem contar, a tela afirmaria "campo(s) em branco" para um campo que continua preenchido no
    // banco (e no deck). Então se conta o que EXISTE entre os vazios (o select vê as linhas sob RLS) e se
    // compara com o que o delete devolveu: menos que o existente = alguma linha não foi apagada. Comparar
    // com `vazios.length` reprovaria o campo que nunca foi preenchido (nada a apagar), que é o caso comum.
    const existentes = await supabase.from("caso_apresentacao_campo").select("chave").eq("caso_id", casoId).in("chave", vazios);
    if (existentes.error) return { tom: "erro", texto: `Os campos preenchidos foram salvos, mas não foi possível conferir os vazios: ${existentes.error.message}.` };
    const aApagar = existentes.data?.length ?? 0;
    if (aApagar > 0) {
      const { data: apagados, error } = await supabase.from("caso_apresentacao_campo").delete().eq("caso_id", casoId).in("chave", vazios).select("chave");
      if (error) return { tom: "erro", texto: `Os campos preenchidos foram salvos, mas limpar os vazios falhou: ${ehNegacaoDePermissao(error) ? MENSAGEM_SEM_PERMISSAO : error.message}.` };
      if ((apagados?.length ?? 0) < aApagar) {
        return { tom: "erro", texto: `Os campos preenchidos foram salvos, mas ${aApagar - (apagados?.length ?? 0)} campo(s) deixado(s) em branco continua(m) preenchido(s): ${MENSAGEM_SEM_PERMISSAO}` };
      }
    }
  }
  // A tela dos campos mora em Entregáveis desde a fase 2; `/apresentacao` só redireciona para lá,
  // mas revalida as duas para o redirect não servir cache de antes da gravação.
  revalidatePath(`/casos/${casoId}/entregaveis`);
  revalidatePath(`/casos/${casoId}/apresentacao`);
  return { tom: "ok", texto: `${preenchidos.length} campo(s) salvo(s); ${vazios.length} em branco ficam "[a preencher]".` };
}
