"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { montarRedirectTo, origemDaRequisicao } from "@/lib/recuperar-senha";

// Pede o e-mail de recuperação. A tela responde `?enviado=1` SEMPRE que o Auth não
// reclamou de limite ou de falha — o Supabase também não diz se a conta existe, e esta
// action não pode dizer mais do que ele (ver lib/recuperar-senha.ts, item 1).
export async function pedirRecuperacao(formData: FormData) {
  const email = String(formData.get("email") || "").trim();
  if (!email) redirect("/login/recuperar?erro=email_vazio");

  const h = await headers();
  const origem = origemDaRequisicao(h.get("origin"), h.get("x-forwarded-host") ?? h.get("host"), h.get("x-forwarded-proto"));
  if (!origem) redirect("/login/recuperar?erro=origem_desconhecida");

  const supabase = await createClient();
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: montarRedirectTo(origem, "/login/nova-senha"),
  });

  if (error) {
    redirect(`/login/recuperar?erro=${encodeURIComponent(`${error.status ?? ""} ${error.code ?? ""} ${error.message}`.trim())}`);
  }
  redirect("/login/recuperar?enviado=1");
}
