// "VER NO ORIGINAL": a lógica pura do link para o arquivo guardado no bucket privado `documentos`.
//
// POR QUE O LINK APONTA PARA UMA ROTA E NÃO PARA A URL ASSINADA. O bucket é privado (0003) e a
// URL assinada expira (120 s) e custa egress se for gerada para cada linha no render: uma tela com
// 400 linhas assinaria 400 URLs para o analista abrir uma. A rota assina NO CLIQUE.
//
// POR QUE HÁ UM CAMINHO "INDISPONÍVEL". Entre julho e outubro de 2026 um defeito gravou
// `arquivo_ref` apontando para objetos que não existem. Link quebrado ou aba em branco seriam
// ausência apresentada como arquivo (regra 1): a rota diz que o arquivo não está disponível, por
// quê, e o que isso NÃO afeta (as linhas extraídas continuam válidas).

/** `?pagina=` só vale como inteiro positivo em dígitos puros. "3abc", "0", "-2", "1.5" → null. */
export function paginaValida(bruto: string | null | undefined): number | null {
  if (bruto == null || !/^[0-9]{1,6}$/.test(bruto)) return null;
  const n = Number(bruto);
  return n >= 1 ? n : null;
}

/** PDF pela extensão do nome original, ou, na falta dele, da chave no bucket. */
export function ehPdf(nomeOriginal: string | null, arquivoRef: string | null): boolean {
  const nome = nomeOriginal ?? arquivoRef ?? "";
  return /\.pdf$/i.test(nome.trim());
}

/** Âncora de página só para PDF: `#page=N` é do visualizador de PDF; em xlsx/imagem é ruído. */
export function destinoDoOriginal(urlAssinada: string, pdf: boolean, pagina: number | null): string {
  return pdf && pagina != null ? `${urlAssinada.split("#")[0]}#page=${pagina}` : urlAssinada;
}

/** O que o link promete — e só promete a página quando ela vai de fato ser aplicada. */
export function rotuloDoLink(pdf: boolean, pagina: number | null): string {
  return pdf && pagina != null ? `abre na página ${pagina}` : "abre o arquivo";
}

export function hrefDoOriginal(casoId: string, docId: string, pagina?: number | null): string {
  const base = `/casos/${encodeURIComponent(casoId)}/documentos/${encodeURIComponent(docId)}/original`;
  return pagina != null && pagina >= 1 ? `${base}?pagina=${pagina}` : base;
}

function esc(s: string): string {
  return s
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

/** Mesma superfície visual de `recusa-do-export.ts`; texto do banco/Storage entra escapado. */
export function paginaDeOriginalIndisponivel(volta: string, motivoTecnico: string): string {
  return `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Arquivo original indisponível — Oria Partners</title>
<style>
  body{margin:0;background:#f6f4ef;color:#11161d;font:15px/1.55 system-ui,sans-serif}
  main{max-width:40rem;margin:0 auto;padding:3rem 1.5rem}
  .cartao{background:#fcfbf8;border:1px solid #d2cdc1;border-left:4px solid #78223a;border-radius:6px;padding:1.5rem}
  h1{font:500 1.35rem/1.3 Georgia,serif;margin:0 0 .75rem}
  .nota{color:#6e6a62;font-size:.875rem;margin-top:1rem}
  a.btn{display:inline-block;margin-top:1.25rem;background:#11161d;color:#f6f4ef;text-decoration:none;
    padding:.5rem .9rem;border-radius:6px;font-weight:500;font-size:.875rem}
  details{margin-top:1.25rem;font-size:.8125rem;color:#3a4048}
  summary{cursor:pointer;color:#6e6a62}
  pre{white-space:pre-wrap;word-break:break-word;background:#f1eee6;padding:.75rem;border-radius:4px}
</style></head>
<body><main><div class="cartao" role="alert">
<h1>O arquivo original deste documento não está disponível</h1>
<p>O sistema não encontrou o arquivo guardado para este documento. Isso não altera as linhas já extraídas dele; só impede conferi-las contra o original por aqui.</p>
<p class="nota">Se precisar do arquivo, peça ao administrador do sistema ou reenvie-o ao mandato.</p>
<a class="btn" href="${esc(volta)}">Voltar</a>
<details><summary>Detalhes técnicos</summary><pre>${esc(motivoTecnico)}</pre></details>
</div></main></body></html>`;
}
