"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { executarMembro, type ResultadoMembro } from "@/lib/membros";

// As escritas dos membros (0215). Mesmo padrão do perímetro: o `casoId` é amarrado no servidor (`.bind`
// na página), o resultado volta como objeto — nunca exceção —, e NÃO há service role: quem escreve é o
// usuário logado, e é o banco (fn_eh_admin dentro das funções + RLS de caso_membro) que recusa o resto.
// A regra de resposta mora em `lib/membros.ts`, onde a suíte a exercita com um cliente falso.
async function agir(operacao: "adicionar" | "remover", casoId: string, form: FormData): Promise<ResultadoMembro> {
  const supabase = await createClient();
  const r = await executarMembro(supabase, operacao, casoId, form);
  if (r?.tom === "ok") revalidatePath(`/casos/${casoId}/membros`);
  return r;
}

export async function adicionarMembro(casoId: string, _anterior: ResultadoMembro, form: FormData) {
  return agir("adicionar", casoId, form);
}
export async function removerMembro(casoId: string, _anterior: ResultadoMembro, form: FormData) {
  return agir("remover", casoId, form);
}
