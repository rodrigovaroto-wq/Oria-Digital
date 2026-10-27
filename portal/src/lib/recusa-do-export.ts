import { NextResponse } from "next/server";

// RECUSA DO EXPORT: JSON PARA PROGRAMA, PÁGINA PARA PESSOA.
//
// POR QUE EXISTE. Os cinco links para `/casos/{id}/export` (visão geral,
// modelagem x3, apresentação) são `<a href>` simples: o navegador NAVEGA até a
// rota. Quando o export recusa (409 portão 2, 503 portão não conferido, 500
// leitura abortada) o analista via `{"error":"...","motivos":[...],"dica":"..."}`
// como texto cru, sem a marca, sem caminho de volta — e o JSON é a única coisa
// que a rota emitia, em 8 pontos de saída de erro.
//
// POR QUE HTML EM LINHA, E NÃO REDIRECT PARA UMA PÁGINA `/export/recusado`. Um
// redirect teria de carregar os motivos na query string: texto arbitrário na URL
// vira conteúdo forjável (qualquer link pode afirmar "o export foi recusado por
// X" dentro do portal) e a lista de motivos do Portão 2 não tem teto de tamanho.
// Inline, o texto vem do servidor e nunca da URL, o status HTTP original
// (409/503/500) é preservado e não há rota nova para manter. O custo — sem o
// casco do portal em volta — é compensado pelo link para a Visão geral.
//
// O CONTRATO PARA PROGRAMA NÃO MUDA: só quem pede `Accept: text/html` (toda
// navegação de navegador manda isso; `fetch`/curl mandam `*/*` ou JSON) recebe a
// página. Nenhum script de `portal/scripts/` importa a rota nem asserta sobre o
// corpo (medido com grep antes desta mudança).

export type CorpoDaRecusa = {
  error: string;
  motivos?: string[];
  dica?: string;
  detalhe?: string;
};

// Texto vindo do banco/da extração (razão social, mensagem do Postgres) entra
// na página: escapa SEMPRE. É a mesma superfície que já produziu byte de
// controle em rótulo — nunca interpolar sem escapar.
function esc(s: string): string {
  return s
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

export function paginaDeRecusa(id: string, corpo: CorpoDaRecusa): string {
  const motivos = (corpo.motivos ?? []).filter((m) => m.trim() !== "");
  const tecnico = [corpo.detalhe, corpo.dica].filter((t): t is string => Boolean(t));
  // `id` vem da URL: escapado também. O link vai à Visão geral, onde moram a
  // Revisão e o "Exportar dados" que não depende do portão.
  const volta = `/casos/${encodeURIComponent(id)}`;
  // Os dois blocos opcionais são montados antes, e não como template dentro
  // de template (Sonar S4624): a página fica legível e cada pedaço escapa uma vez.
  const itens = motivos.map((m) => "<li>" + esc(m) + "</li>").join("");
  const blocoMotivos = motivos.length ? "<p>O que impede:</p><ul>" + itens + "</ul>" : "";
  const blocoTecnico = tecnico.length
    ? "<details><summary>Detalhes técnicos</summary><pre>" + tecnico.map(esc).join("\n\n") + "</pre></details>"
    : "";
  return `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Arquivo não gerado — Oria Partners</title>
<style>
  body{margin:0;background:#f6f4ef;color:#11161d;font:15px/1.55 system-ui,sans-serif}
  main{max-width:40rem;margin:0 auto;padding:3rem 1.5rem}
  .cartao{background:#fcfbf8;border:1px solid #d2cdc1;border-left:4px solid #78223a;border-radius:6px;padding:1.5rem}
  h1{font:500 1.35rem/1.3 Georgia,serif;margin:0 0 .75rem}
  ul{margin:.5rem 0 0;padding-left:1.25rem}
  .nota{color:#6e6a62;font-size:.875rem;margin-top:1rem}
  a.btn{display:inline-block;margin-top:1.25rem;background:#11161d;color:#f6f4ef;text-decoration:none;
    padding:.5rem .9rem;border-radius:6px;font-weight:500;font-size:.875rem}
  details{margin-top:1.25rem;font-size:.8125rem;color:#3a4048}
  summary{cursor:pointer;color:#6e6a62}
  pre{white-space:pre-wrap;word-break:break-word;background:#f1eee6;padding:.75rem;border-radius:4px}
</style></head>
<body><main><div class="cartao" role="alert">
<h1>O arquivo não foi gerado</h1>
<p>${esc(corpo.error)}</p>
${blocoMotivos}
<p class="nota">Nenhum arquivo foi baixado. Resolva o que está acima na Visão geral do mandato e tente de novo.</p>
<a class="btn" href="${esc(volta)}">Voltar à Visão geral do mandato</a>
${blocoTecnico}
</div></main></body></html>`;
}

// Mesma assinatura de `NextResponse.json(corpo, { status })`, para a troca nos 8
// pontos de saída ser mecânica e não tocar na semântica de nenhuma recusa.
export function recusar(
  request: Request, id: string, corpo: CorpoDaRecusa, init: { status: number },
): NextResponse {
  const querHtml = (request.headers.get("accept") ?? "").includes("text/html");
  if (!querHtml) return NextResponse.json(corpo, init);
  return new NextResponse(paginaDeRecusa(id, corpo), {
    status: init.status,
    headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" },
  });
}
