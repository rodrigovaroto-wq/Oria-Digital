import { NextResponse } from "next/server";
import { conferirEnvioAoCaso, emitirTokenDoEnvio } from "@/lib/supabase/acesso";
import { createClient } from "@/lib/supabase/server";
import { versoesDesde } from "@/lib/supabase/reprocesso";
import { ehUuid } from "@/lib/equipe";
import { descobrirNomesDeCampo } from "@/lib/n8n-form";
import { TETO_POR_ARQUIVO_BYTES, formatarBytes } from "@/lib/limite-de-envio";
import {
  FRASE_NENHUM_REPROCESSAVEL, JANELA_EM_LEITURA_MS, cortarPeloOrcamento, decidirPedido, documentosEmLeitura,
  motivoDeArquivoGrande, motivoDoDownload, nomeParaEnvio, validarCorpo,
  type ItemDaFila, type Recusado,
} from "@/lib/fila-de-reprocesso";

// "Reprocessar": pega o ORIGINAL guardado no bucket `documentos` e o reenvia ao Form do n8n — o mesmo
// destino de `api/intake`, na MESMA ordem de segurança (Form configurado → entrada → papel → token →
// só então ler a fila e o Storage). O reenvio do MESMO arquivo retoma só o que falhou
// (`fn_registrar_documento`); quem decide o que é reprocessável é `fn_fila_de_reprocesso` (0232).
//
// O 413 de 4,5 MB da Vercel é do corpo de ENTRADA, e aqui ele é um JSON de uuids. O multipart ao Form
// sai do servidor, que não passa por esse limite: o teto é o por-arquivo do n8n e a memória
// (`TETO_DE_DOCUMENTOS_POR_PEDIDO`, em `fila-de-reprocesso.ts`).
export const runtime = "nodejs";

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const url = process.env.N8N_INTAKE_FORM_URL;
  if (!url) {
    return NextResponse.json(
      { error: "Reprocesso pelo portal não configurado: defina N8N_INTAKE_FORM_URL (URL de produção do Form do N8N) nas variáveis de ambiente da Vercel." },
      { status: 503 },
    );
  }

  const { id: casoId } = await params;
  if (!ehUuid(casoId)) return NextResponse.json({ error: "Identificador do mandato inválido (uuid esperado)." }, { status: 400 });
  let corpo: unknown;
  try {
    corpo = await request.json();
  } catch {
    return NextResponse.json({ error: "Requisição inválida (JSON esperado)." }, { status: 400 });
  }
  const pedido = validarCorpo(corpo);
  if (!pedido.ok) return NextResponse.json({ error: pedido.mensagem }, { status: 400 });

  // O PAPEL, DEPOIS O TOKEN, ANTES DE LER A FILA E O STORAGE (ver `api/intake/route.ts`).
  const permissao = await conferirEnvioAoCaso(casoId);
  if (!permissao.ok) return NextResponse.json({ error: permissao.mensagem }, { status: permissao.status });
  const autorizacao = await emitirTokenDoEnvio(casoId);
  if (!autorizacao.ok) return NextResponse.json({ error: autorizacao.mensagem }, { status: autorizacao.status });

  // Cliente autenticado (RLS do usuário), nunca service role: a fila e o bucket respondem ao papel de quem clicou.
  const supabase = await createClient();
  const filaRes = await supabase.rpc("fn_fila_de_reprocesso", { p_caso_id: casoId });
  if (filaRes.error) {
    return NextResponse.json({ error: `Não foi possível ler a fila de reprocesso: ${filaRes.error.message}` }, { status: 500 });
  }
  // Versão criada na janela e ainda sem extração = o n8n está lendo: reenviar pagaria duas vezes.
  const recentes = await versoesDesde(supabase, pedido.documentoIds, new Date(Date.now() - JANELA_EM_LEITURA_MS).toISOString());
  if ("erro" in recentes) {
    return NextResponse.json({ error: `Não foi possível conferir se os documentos já estão em leitura: ${recentes.erro}` }, { status: 500 });
  }
  const { seguem, recusados } = decidirPedido(
    pedido.documentoIds, (filaRes.data as ItemDaFila[] | null) ?? [], documentosEmLeitura(recentes.versoes, recentes.comExtracao),
  );

  const baixados: Array<{ item: ItemDaFila; blob: Blob; nome: string; documentoId: string; bytes: number }> = [];
  const recusadosNoDownload: Recusado[] = [];
  for (const item of seguem) {
    const { data, error } = await supabase.storage.from("documentos").download(item.arquivo_ref as string);
    if (error || !data) {
      recusadosNoDownload.push({ documentoId: item.documento_id, motivo: motivoDoDownload(error?.message ?? "sem conteúdo devolvido") });
    } else if (data.size > TETO_POR_ARQUIVO_BYTES) {
      recusadosNoDownload.push({ documentoId: item.documento_id, motivo: motivoDeArquivoGrande(formatarBytes(data.size), formatarBytes(TETO_POR_ARQUIVO_BYTES)) });
    } else {
      baixados.push({ item, blob: data, nome: nomeParaEnvio(item), documentoId: item.documento_id, bytes: data.size });
    }
  }
  // O Form responde 200 ao receber e o n8n recusa DEPOIS o lote acima do orçamento: corta-se aqui, com a mesma conta.
  const { cabem: arquivos, recusados: recusadosPeloOrcamento } = cortarPeloOrcamento(baixados);
  const todosRecusados = [...recusados, ...recusadosNoDownload, ...recusadosPeloOrcamento];

  if (arquivos.length === 0) {
    return NextResponse.json({ ok: false, error: FRASE_NENHUM_REPROCESSAVEL, enviados: [], recusados: todosRecusados }, { status: 409 });
  }

  const campos = await descobrirNomesDeCampo(url);
  const fwd = new FormData();
  fwd.append(campos.mandato, permissao.nome ?? "");
  fwd.append(campos.token, autorizacao.token);
  for (const a of arquivos) fwd.append(campos.arquivos, a.blob, a.nome);

  let resp: Response;
  try {
    resp = await fetch(url, { method: "POST", body: fwd });
  } catch (e) {
    return NextResponse.json({ error: `Não foi possível contatar o N8N: ${(e as Error).message}` }, { status: 502 });
  }
  if (!resp.ok) {
    const detalhe = await resp.text().catch(() => "");
    return NextResponse.json(
      { error: `O N8N recusou o reenvio (HTTP ${resp.status}). ${detalhe.slice(0, 300)}`, recusados: todosRecusados },
      { status: 502 },
    );
  }

  return NextResponse.json({
    ok: true,
    enviados: arquivos.map((a) => ({ documentoId: a.item.documento_id, nome: a.nome })),
    recusados: todosRecusados,
    desde: new Date().toISOString(),
  });
}
