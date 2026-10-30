import type { SupabaseClient } from "@supabase/supabase-js";
import { ehPapel } from "../acesso";
import {
  interpretarMembros, membrosDoModoAntigo, type Alocacao, type Membro, type MembroDaEquipe,
} from "../equipe";
import { paginar } from "./paginar";

// A LEITURA DA EQUIPE para as duas telas que a mostram (Administração › Equipe e a Visão geral do
// mandato). Tenta `fn_membros_da_equipe` (e-mail + quem espera liberação); se o banco não a tem, cai no
// MODO ANTIGO (`membro` + `alocacao`) e DIZ que caiu. Qualquer outro erro é `falha` — nunca uma lista
// vazia: "ninguém na equipe" seria uma afirmação que ninguém mediu.
export type EquipeLida =
  | { estado: "ok"; modo: "funcao" | "antigo"; membros: MembroDaEquipe[]; incompleta: boolean }
  | { estado: "falha"; code: string | null; message: string };

/** `casoId`: no modo antigo só as alocações desse mandato são lidas (a Visão geral não precisa das outras). */
export async function lerEquipe(supabase: SupabaseClient, casoId?: string): Promise<EquipeLida> {
  let lida;
  try {
    lida = interpretarMembros(await supabase.rpc("fn_membros_da_equipe"));
  } catch (e) {
    return { estado: "falha", code: null, message: e instanceof Error ? e.message : String(e) };
  }
  if (lida.estado === "falha") return lida;
  // Linha ignorada (forma inesperada) conta como "incompleta": a tela avisa, não finge a lista inteira.
  if (lida.estado === "ok") return { estado: "ok", modo: "funcao", membros: lida.membros, incompleta: lida.ignorados > 0 };

  const [membrosRes, alocacoesRes] = await Promise.all([
    supabase.from("membro").select("usuario_id, papel").order("criado_em", { ascending: true }),
    paginar<Alocacao>((de, ate) => {
      const q = supabase.from("alocacao").select("caso_id, usuario_id");
      return (casoId ? q.eq("caso_id", casoId) : q)
        .order("caso_id", { ascending: true }).order("usuario_id", { ascending: true }).range(de, ate);
    }),
  ]);
  const erro = membrosRes.error ?? alocacoesRes.error;
  if (erro) return { estado: "falha", code: ("code" in erro ? (erro.code as string | null) : null) ?? null, message: erro.message };
  const linhas = (membrosRes.data as Array<{ usuario_id: string; papel: unknown }> | null) ?? [];
  const membros = linhas.filter((m): m is Membro => ehPapel(m.papel));
  return {
    estado: "ok", modo: "antigo",
    membros: membrosDoModoAntigo(membros, alocacoesRes.data),
    incompleta: alocacoesRes.truncado || membros.length !== linhas.length,
  };
}
