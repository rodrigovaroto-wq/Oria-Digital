"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { textoDeFalhaDaAcao } from "@/lib/acesso";

// Chama a RPC fn_revisar_documento (Supabase/migrations/0008_portal_revisao.sql) — o
// humano confirma ou corrige a classificação sugerida (N1: anti-ancoragem,
// Arquitetura do Sistema/1 Visão e Doutrina/01). Toda a lógica (resolver pendência, decisao+evento_auditoria,
// checklist, recomputar completude) fica no Postgres, não aqui.
export async function revisarDocumento(casoId: string, formData: FormData) {
  const supabase = await createClient();

  const documentoId = String(formData.get("documento_id") || "");
  const novoTipo = String(formData.get("novo_tipo_taxonomia") || "").trim() || null;
  const novaEntidade = String(formData.get("nova_entidade_nome") || "").trim() || null;
  const novoPeriodoTipo = String(formData.get("novo_periodo_tipo") || "").trim() || null;
  const novoPeriodoRef = String(formData.get("novo_periodo_ref") || "").trim() || null;
  const motivo = String(formData.get("motivo") || "").trim() || null;

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { error } = await supabase.rpc("fn_revisar_documento", {
    p_documento_id: documentoId,
    p_autor: user?.email ?? "portal:desconhecido",
    p_novo_tipo_taxonomia: novoTipo,
    p_nova_entidade_nome: novaEntidade,
    p_novo_periodo_tipo: novoPeriodoTipo,
    p_novo_periodo_ref: novoPeriodoRef,
    p_motivo: motivo,
  });

  if (error) {
    throw new Error(textoDeFalhaDaAcao("Falha ao revisar documento", error));
  }

  // "layout": os números das abas (Pendências, Documentos) moram no layout do mandato, e
  // `revalidatePath(<rota>)` sozinho não o refaz — a aba seguiria dizendo o número velho.
  revalidatePath(`/casos/${casoId}`, "layout");
}
