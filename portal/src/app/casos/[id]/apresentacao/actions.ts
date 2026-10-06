"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { CHAVES_APRESENTACAO } from "@/lib/apresentacao/campos";

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
    if (error) return { tom: "erro", texto: `Não foi possível salvar: ${error.message}. Se a tabela não existe, a migration 0205 ainda não foi aplicada.` };
  }
  if (vazios.length) {
    const { error } = await supabase.from("caso_apresentacao_campo").delete().eq("caso_id", casoId).in("chave", vazios);
    if (error) return { tom: "erro", texto: `Os campos preenchidos foram salvos, mas limpar os vazios falhou: ${error.message}.` };
  }
  revalidatePath(`/casos/${casoId}/apresentacao`);
  return { tom: "ok", texto: `${preenchidos.length} campo(s) salvo(s); ${vazios.length} em branco ficam "[a preencher]".` };
}
