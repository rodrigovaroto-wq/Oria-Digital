import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { versoesDesde } from "@/lib/supabase/reprocesso";
import { ehUuid } from "@/lib/equipe";
import { TETO_DE_DOCUMENTOS_POR_PEDIDO, veredictoDoReprocesso } from "@/lib/fila-de-reprocesso";

// Acompanha um reprocesso POR DOCUMENTO enviado (`api/intake/status` só vê documento novo). Ver
// `veredictoDoReprocesso`. A recusa do lote pelo n8n vem de `fn_falhas_abertas`, o mesmo que o status do intake usa.
export const runtime = "nodejs";

export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id: casoId } = await params;
  const q = new URL(request.url).searchParams;
  const desde = q.get("desde");
  const ids = (q.get("ids") ?? "").split(",").filter(Boolean);
  if (!ehUuid(casoId) || !desde || Number.isNaN(Date.parse(desde)) || ids.length === 0
    || ids.length > TETO_DE_DOCUMENTOS_POR_PEDIDO || !ids.every(ehUuid)) {
    return NextResponse.json({ error: "Parâmetros inválidos (desde, ids)." }, { status: 400 });
  }
  const supabase = await createClient();
  const { data: casos, error: casoErr } = await supabase.from("caso").select("id, nome").eq("id", casoId).limit(1);
  if (casoErr) return NextResponse.json({ error: casoErr.message }, { status: 500 });
  if (!casos?.[0]) {
    return NextResponse.json({ error: "Este mandato não existe mais ou não está no seu acesso, então não dá para acompanhar o reprocesso." }, { status: 404 });
  }
  const lidas = await versoesDesde(supabase, ids, desde);
  if ("erro" in lidas) return NextResponse.json({ error: lidas.erro }, { status: 500 });
  const falhas = await supabase.rpc("fn_falhas_abertas", { p_caso_nome: casos[0].nome, p_desde: desde });
  // Erro ao perguntar pela falha não vira "sem falha" nem "recusado": o veredito segue como `lendo` e a tela, no teto, diz que parou.
  const falha = (falhas.data as Array<{ mensagem: string }> | null)?.[0]?.mensagem ?? null;
  const porDoc = new Map<string, string[]>();
  for (const v of lidas.versoes) porDoc.set(v.documento_id, [...(porDoc.get(v.documento_id) ?? []), v.id]);
  return NextResponse.json(veredictoDoReprocesso(ids, porDoc, lidas.comExtracao, falha));
}
