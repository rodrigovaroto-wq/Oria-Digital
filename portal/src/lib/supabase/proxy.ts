import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { hasEnvVars } from "./env";
import { rotaPublica } from "../recuperar-senha";

// Renova a sessão a cada requisição e redireciona quem não está autenticado
// para /login. Chamado pelo src/proxy.ts (Next.js 16 renomeou middleware →
// proxy — ver https://nextjs.org/docs/messages/middleware-to-proxy).
export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request });

  if (!hasEnvVars) {
    // Sem .env.local ainda configurado (ver README) — não trava em loop de
    // redirect pro /login antes do projeto estar configurado.
    return supabaseResponse;
  }

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          supabaseResponse = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options),
          );
        },
      },
    },
  );

  // Não rodar nada entre createServerClient e getClaims() — verificação
  // local do JWT (mais rápida que getUser(), que faz round-trip à rede).
  const { data } = await supabase.auth.getClaims();
  const user = data?.claims;

  // /api/* sem sessão responde 401 JSON, NÃO redireciona: o `fetch` do navegador seguia o
  // redirect para /login, recebia HTML com status 200 e `r.json()` estourava — a busca global
  // mostrava falha genérica para sempre e o 401 da própria rota nunca era alcançado. Quem chama
  // /api/* TEM de tratar o 401: o envio (`/api/intake`, `/destino`) lê `error` quando `!resp.ok`, e
  // o acompanhamento (`/api/intake/status`) trata `resp.status === 401` à parte (antes só agia com
  // `resp.ok` e ficava "aguardando" até o fim da janela). A rota continua protegida, só deixa de mentir com 200.
  if (!user && request.nextUrl.pathname.startsWith("/api/")) {
    return NextResponse.json(
      { erro: "Sessão expirada. Entre de novo.", error: "Sua sessão expirou. Atualize a página, entre de novo e reenvie — nada foi processado." },
      { status: 401 },
    );
  }

  if (!user && !rotaPublica(request.nextUrl.pathname)) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    return NextResponse.redirect(url);
  }

  return supabaseResponse;
}
