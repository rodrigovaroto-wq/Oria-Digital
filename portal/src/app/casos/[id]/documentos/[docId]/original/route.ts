import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import {
  destinoDoOriginal, ehPdf, escolherVersaoDoOriginal, paginaDeOriginalIndisponivel, paginaValida,
  type TipoDeMotivo, type VersaoDoOriginal,
} from "@/lib/original-do-documento";

// "Ver original": assina NO CLIQUE uma URL de 120 s do bucket privado `documentos` e redireciona.
// Cliente autenticado com RLS (0003), nunca service role. Ver `src/lib/original-do-documento.ts`.
const VALIDADE_S = 120;

export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ id: string; docId: string }> },
) {
  const { id, docId } = await params;
  const volta = `/casos/${encodeURIComponent(id)}/documentos/${encodeURIComponent(docId)}`;
  const indisponivel = (motivo: string, tipo: TipoDeMotivo, status = 404) =>
    new NextResponse(paginaDeOriginalIndisponivel(volta, motivo, tipo), {
      status,
      headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" },
    });

  const supabase = await createClient();

  // O documento TEM de ser deste caso: o docId vem da URL.
  const docRes = await supabase
    .from("documento")
    .select("id, documento_versao(id, n_versao, nome_original, arquivo_ref, origem_arquivo)")
    .eq("caso_id", id)
    .eq("id", docId)
    .maybeSingle();
  if (docRes.error) return indisponivel(`Leitura do documento falhou: ${docRes.error.message}`, "falha_tecnica", 500);
  if (!docRes.data) return indisponivel("Documento não encontrado neste mandato.", "fora_do_caso");

  const versoes = (docRes.data.documento_versao as unknown as VersaoDoOriginal[] | null) ?? [];
  // `?versao=` é a versão que a TELA citou (fatos e linhas do detalhe a passam): manda sobre a
  // função. Só sem ele (botão do cabeçalho de link antigo) a função decide, e só então é chamada.
  const pedida = req.nextUrl.searchParams.get("versao");
  let vigenteId: string | null = null;
  if (!pedida) {
    const vigenteRes = await supabase.rpc("fn_versao_com_extracao", { p_documento_id: docId });
    // Falha da função NÃO cai na mais recente: abriria um arquivo diferente do que a tela mostra,
    // e a página citada apontaria para outro documento sem aviso nenhum (regra 1).
    if (vigenteRes.error) {
      return indisponivel(`Escolha da versão falhou (fn_versao_com_extracao): ${vigenteRes.error.message}`, "falha_tecnica", 500);
    }
    vigenteId = vigenteRes.data as string | null;
  }
  const escolha = escolherVersaoDoOriginal(versoes, pedida, vigenteId);
  if (!("versao" in escolha)) return indisponivel(escolha.motivo, escolha.tipo);
  const versao = escolha.versao;

  if (!versao.arquivo_ref) return indisponivel("A versão do documento não tem referência de arquivo (arquivo_ref vazio).", "sem_arquivo");
  if (versao.origem_arquivo && versao.origem_arquivo !== "supabase_storage") {
    return indisponivel(`O arquivo está em "${versao.origem_arquivo}", fora do bucket do portal.`, "origem_externa");
  }

  const { data, error } = await supabase.storage
    .from("documentos")
    .createSignedUrl(versao.arquivo_ref, VALIDADE_S);
  if (error || !data?.signedUrl) {
    return indisponivel(
      `Objeto "${versao.arquivo_ref}" não pôde ser assinado no bucket documentos: ${error?.message ?? "sem URL devolvida"}.`,
      "nao_assinavel",
    );
  }

  const pagina = paginaValida(req.nextUrl.searchParams.get("pagina"));
  const res = NextResponse.redirect(
    destinoDoOriginal(data.signedUrl, ehPdf(versao.nome_original, versao.arquivo_ref), pagina),
    302,
  );
  res.headers.set("cache-control", "no-store");
  return res;
}
