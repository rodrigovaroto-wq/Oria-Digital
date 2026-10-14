// Roda navegador-leitor.js num Chromium de verdade sobre um arquivo do disco e mede
// tempo, pico de memória do JS (CDP) e pico de RSS dos processos do navegador.
// Uso: node navegador-medir.mjs <arquivo>   (playwright global, Chromium em /opt/pw-browsers)
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
const require = createRequire(import.meta.url);
// O playwright global mora em <prefixo do node>/lib/node_modules: achado pelo executável do
// próprio node, e não por `npm root -g` (um comando resolvido pelo PATH).
let pw; try { pw = require('playwright'); } catch { pw = require(join(dirname(dirname(process.execPath)), 'lib', 'node_modules', 'playwright')); }
const arquivo = process.argv[2];
const navegador = await pw.chromium.launch();
const pagina = await navegador.newPage();
await pagina.setContent('<input type="file" id="f">');
await pagina.addScriptTag({ content: readFileSync(new URL('./navegador-leitor.js', import.meta.url), 'utf8') });
await pagina.setInputFiles('#f', arquivo);
const cdp = await pagina.context().newCDPSession(pagina);
await cdp.send('Performance.enable');
let picoHeap = 0, picoRss = 0;
const amostrar = setInterval(async () => {
  try {
    const { metrics } = await cdp.send('Performance.getMetrics');
    picoHeap = Math.max(picoHeap, metrics.find(m => m.name === 'JSHeapUsedSize').value);
    // RSS dos processos do Chromium lido em /proc, e não por `ps` pelo PATH.
    let rss = 0;
    for (const pid of readdirSync('/proc').filter((p) => /^\d+$/.test(p))) {
      try {
        if (!/chrom/i.test(readFileSync(`/proc/${pid}/cmdline`, 'latin1'))) continue;
        const m = /VmRSS:\s+(\d+)/.exec(readFileSync(`/proc/${pid}/status`, 'latin1'));
        if (m) rss += Number(m[1]);
      } catch { /* o processo terminou entre a lista e a leitura */ }
    }
    picoRss = Math.max(picoRss, rss);
  } catch { /* fim da sessão */ }
}, 500);
const r = await pagina.evaluate(async () => {
  const x = await window.lerSped(document.getElementById('f').files[0]);
  const g = {}; for (const [, l] of x.resumo.guardadas) { const k = l.slice(1, 5); g[k] = (g[k] || 0) + 1; }
  return { ms: x.ms, resumo_bytes: x.resumo_bytes, resumo_gzip_bytes: x.resumo_gzip_bytes, hash: x.resumo.hash_sha256,
    linhas: x.resumo.linhas, controle_declarado: x.resumo.controle_declarado, bate9999: x.resumo.bate9999, bate9900: x.resumo.bate9900,
    guardadas_por_registro: g, linhas_guardadas: x.resumo.guardadas.length, grupos_i250: x.resumo.i250_por_conta_mes.length,
    soma_i250_n: x.resumo.i250_por_conta_mes.reduce((s, a) => s + a.n, 0), amostra_acento: x.resumo.guardadas.find(([, l]) => l.startsWith('|I050|'))?.[1] };
});
clearInterval(amostrar);
console.log(JSON.stringify({ ...r, pico_heap_js_mb: Math.round(picoHeap / 1048576), pico_rss_navegador_mb: Math.round(picoRss / 1024) }, null, 1));
await navegador.close();
