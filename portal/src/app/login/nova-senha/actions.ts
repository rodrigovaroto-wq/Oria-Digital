"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { validarNovaSenha } from "@/lib/recuperar-senha";

export async function definirNovaSenha(formData: FormData) {
  const senha = String(formData.get("senha") || "");
  const confirmacao = String(formData.get("confirmacao") || "");

  const problema = validarNovaSenha(senha, confirmacao);
  if (problema) redirect(`/login/nova-senha?error=${problema}`);

  const supabase = await createClient();
  const { error } = await supabase.auth.updateUser({ password: senha });
  if (error) {
    redirect(`/login/nova-senha?error=${encodeURIComponent(`${error.status ?? ""} ${error.code ?? ""} ${error.message}`.trim())}`);
  }
  redirect("/casos?aviso=senha-atualizada");
}
