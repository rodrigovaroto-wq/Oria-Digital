import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import {
  destinoDoOriginal, ehPdf, paginaDeOriginalIndisponivel, paginaValida,
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
  const indisponivel = (motivo: string, status = 404) =>
    new NextResponse(paginaDeOriginalIndisponivel(volta, motivo), {
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
  if (docRes.error) return indisponivel(`Leitura do documento falhou: ${docRes.error.message}`, 500);
  if (!docRes.data) return indisponivel("Documento não encontrado neste mandato.");

  type V = {
    id: string; n_versao: number | null; nome_original: string | null;
    arquivo_ref: string | null; origem_arquivo: string | null;
  };
  const versoes = [...((docRes.data.documento_versao as unknown as V[] | null) ?? [])]
    .sort((a, b) => (b.n_versao ?? 0) - (a.n_versao ?? 0));
  // Mesma versão que o detalhe mostra (0102): a mais recente COM linha; sem ela, a mais recente.
  const vigenteRes = await supabase.rpc("fn_versao_com_extracao", { p_documento_id: docId });
  // Falha da função NÃO cai na mais recente: abriria um arquivo diferente do que a tela mostra,
  // e a página citada apontaria para outro documento sem aviso nenhum (regra 1).
  if (vigenteRes.error) {
    return indisponivel(`Escolha da versão falhou (fn_versao_com_extracao): ${vigenteRes.error.message}`, 500);
  }
  const versao = versoes.find((v) => v.id === (vigenteRes.data as string | null)) ?? versoes[0];

  if (!versao) return indisponivel("O documento não tem versão registrada.");
  if (!versao.arquivo_ref) return indisponivel("A versão do documento não tem referência de arquivo (arquivo_ref vazio).");
  if (versao.origem_arquivo && versao.origem_arquivo !== "supabase_storage") {
    return indisponivel(`O arquivo está em "${versao.origem_arquivo}", fora do bucket do portal.`);
  }

  const { data, error } = await supabase.storage
    .from("documentos")
    .createSignedUrl(versao.arquivo_ref, VALIDADE_S);
  if (error || !data?.signedUrl) {
    return indisponivel(
      `Objeto "${versao.arquivo_ref}" não pôde ser assinado no bucket documentos: ${error?.message ?? "sem URL devolvida"}.`,
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
