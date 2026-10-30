"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { ehPapel, textoDeFalhaDaAcao } from "@/lib/acesso";
import { ehUuid } from "@/lib/equipe";

// A GESTÃO DA EQUIPE: papel e alocação. Três chamadas, três funções do banco (0216), e NENHUMA regra
// de quem pode aqui: `fn_definir_papel`, `fn_alocar` e `fn_desalocar` começam por `fn_exige_socio`, e
// um não-Sócio leva 42501 — que a tela traduz. O que este arquivo valida é a FORMA do que chega do
// formulário (uuid, papel do vocabulário), porque um POST forjado não passa pela tela.
//
// O resultado volta como VALOR (`{tom, texto}`), nunca como exceção: em produção o Next redige a
// mensagem de um erro lançado por Server Action, e "o banco recusou tirar o último Sócio" precisa
// chegar inteiro a quem clicou. Mesmo padrão da Modelagem e do Grupo econômico.
export type ResultadoEquipe = { tom: "ok" | "erro"; texto: string } | null;

const erro = (texto: string): ResultadoEquipe => ({ tom: "erro", texto });
const ok = (texto: string): ResultadoEquipe => ({ tom: "ok", texto });
const campo = (f: FormData, k: string) => (typeof f.get(k) === "string" ? (f.get(k) as string).trim() : "");

/** `papel = "nenhum"` retira o acesso (`fn_definir_papel(u, NULL)`); o resto é um dos três papéis. */
export async function definirPapel(_anterior: ResultadoEquipe, form: FormData): Promise<ResultadoEquipe> {
  const usuario = campo(form, "usuario_id");
  const papel = campo(form, "papel");
  const motivo = campo(form, "motivo");
  if (!ehUuid(usuario)) return erro("O código do usuário não tem a forma de um UUID (o que o Supabase mostra em Authentication › Users).");
  if (papel !== "nenhum" && !ehPapel(papel)) return erro("Escolha um papel.");

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("fn_definir_papel", {
    p_usuario: usuario, p_papel: papel === "nenhum" ? null : papel, p_motivo: motivo || null,
  });
  if (error) return erro(textoDeFalhaDaAcao("Não foi possível definir o papel", error));
  revalidatePath("/administracao/equipe");
  const r = data as { mudou?: boolean } | null;
  if (r?.mudou === false) return ok("Esse já era o papel — nada mudou.");
  return ok(papel === "nenhum" ? "Acesso retirado." : "Papel salvo.");
}

export async function alocar(_anterior: ResultadoEquipe, form: FormData): Promise<ResultadoEquipe> {
  const caso = campo(form, "caso_id");
  const usuario = campo(form, "usuario_id");
  if (!ehUuid(caso)) return erro("Escolha o mandato.");
  if (!ehUuid(usuario)) return erro("Escolha a pessoa.");

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("fn_alocar", { p_caso: caso, p_usuario: usuario });
  if (error) return erro(textoDeFalhaDaAcao("Não foi possível alocar", error));
  // "layout": a equipe do mandato mora na Visão geral, e a lista de quem vê o quê muda nas demais telas.
  revalidatePath("/administracao/equipe");
  revalidatePath(`/casos/${caso}`, "layout");
  const r = data as { mudou?: boolean } | null;
  return ok(r?.mudou === false ? "Já estava alocado — nada mudou." : "Alocado.");
}

export async function desalocar(_anterior: ResultadoEquipe, form: FormData): Promise<ResultadoEquipe> {
  const caso = campo(form, "caso_id");
  const usuario = campo(form, "usuario_id");
  if (!ehUuid(caso) || !ehUuid(usuario)) return erro("Pedido inválido.");

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("fn_desalocar", { p_caso: caso, p_usuario: usuario });
  if (error) return erro(textoDeFalhaDaAcao("Não foi possível retirar da equipe", error));
  revalidatePath("/administracao/equipe");
  revalidatePath(`/casos/${caso}`, "layout");
  const r = data as { mudou?: boolean } | null;
  return ok(r?.mudou === false ? "Já não estava alocado — nada mudou." : "Retirado da equipe.");
}
