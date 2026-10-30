import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { caminhoInternoSeguro, ERRO_LINK } from "@/lib/recuperar-senha";

// O RETORNO DO LINK DO E-MAIL. Dois formatos chegam aqui, conforme o template do
// Supabase (ver o relatório da fase 5):
//   - `?code=` — fluxo PKCE do link padrão ({{ .ConfirmationURL }}): o @supabase/ssr 0.12
//     usa PKCE, o verificador mora no cookie do navegador que pediu o link, então só abre
//     no MESMO navegador;
//   - `?token_hash=&type=recovery` — template com {{ .TokenHash }}: abre em qualquer
//     aparelho.
// Só o tipo `recovery` entra aqui: este endpoint não confirma cadastro nem troca de e-mail.
export async function GET(request: NextRequest) {
  const q = request.nextUrl.searchParams;
  const destino = caminhoInternoSeguro(q.get("next"), "/login/nova-senha");

  const falha = (detalhe: string) => {
    const url = request.nextUrl.clone();
    url.pathname = "/login/recuperar";
    url.search = `?erro=${ERRO_LINK}&detalhe=${encodeURIComponent(detalhe)}`;
    return NextResponse.redirect(url);
  };

  // O Supabase devolve o motivo na própria URL quando o link já venceu.
  const recusado = q.get("error_code") ?? q.get("error");
  if (recusado) return falha(`${recusado}: ${q.get("error_description") ?? ""}`.trim());

  const supabase = await createClient();
  const tokenHash = q.get("token_hash");
  const code = q.get("code");

  let erro: { message: string } | null = null;
  if (tokenHash && q.get("type") === "recovery") {
    ({ error: erro } = await supabase.auth.verifyOtp({ type: "recovery", token_hash: tokenHash }));
  } else if (code) {
    ({ error: erro } = await supabase.auth.exchangeCodeForSession(code));
  } else {
    return falha("sem code nem token_hash na URL");
  }
  if (erro) return falha(erro.message);

  // `destino` já é caminho interno (pode trazer query): resolve contra a origem, nunca concatena.
  return NextResponse.redirect(new URL(destino, request.nextUrl.origin));
}
