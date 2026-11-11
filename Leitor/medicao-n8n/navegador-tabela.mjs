// O LEITOR TABULAR (`Leitor/lib/tabela.mjs`, MB1) num Chromium de verdade, contra o Node.
// Serve a raiz do repositório por HTTP, importa o módulo no navegador (não uma cópia), lê o
// arquivo com `File` e compara o resumo inteiro com o do Node (`openAsBlob`). Mede o tempo
// e o pico de heap JS da página. O portal roda o leitor num Web Worker; aqui ele roda na
// página porque é dela que o CDP dá o heap. O código é o mesmo.
// Uso: node Leitor/medicao-n8n/navegador-tabela.mjs <arquivo>...
import http from 'node:http';
import { createReadStream, openAsBlob, statSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { caminhoDaUrl } from './caminho.mjs';
import { lerTabela } from '../lib/tabela.mjs';

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const servidor = http.createServer((q, s) => {
  const f = caminhoDaUrl(raiz, q.url);
  if (!f) { s.writeHead(403); return s.end(); }
  try { statSync(f); } catch { s.writeHead(404); return s.end(); }
  s.writeHead(200, { 'content-type': extname(f) === '.mjs' ? 'text/javascript' : 'text/html' });
  createReadStream(f).pipe(s);
}).listen(0, '127.0.0.1');
await new Promise((r) => servidor.once('listening', r));
const base = `http://127.0.0.1:${servidor.address().port}`;

const require = createRequire(import.meta.url);
let pw; try { pw = require('playwright'); } catch { pw = require(join(dirname(dirname(process.execPath)), 'lib', 'node_modules', 'playwright')); }
const navegador = await pw.chromium.launch();
const pagina = await navegador.newPage();
await pagina.goto(base + '/Leitor/medicao-n8n/README.md');
await pagina.setContent('<input type="file" id="f">');
let falhou = false;
for (const arquivo of process.argv.slice(2)) {
  await pagina.setInputFiles('#f', arquivo);
  const cdp = await pagina.context().newCDPSession(pagina);
  await cdp.send('Performance.enable');
  let picoHeap = 0;
  const amostrar = setInterval(async () => {
    try { const { metrics } = await cdp.send('Performance.getMetrics'); picoHeap = Math.max(picoHeap, metrics.find((m) => m.name === 'JSHeapUsedSize').value); } catch { /* fim */ }
  }, 250);
  const t0 = Date.now();
  const noNavegador = await pagina.evaluate(async (url) => {
    const { lerTabela } = await import(url);
    let dados = 0;
    const r = await lerTabela(document.getElementById('f').files[0], { aoLinha: (l) => { if (l.destino === 'dado') dados++; } });
    return { ...r, dados_pelo_callback: dados };
  }, base + '/Leitor/lib/tabela.mjs');
  const msNavegador = Date.now() - t0;
  clearInterval(amostrar);
  await cdp.detach();
  const t1 = Date.now();
  let dados = 0;
  const noNode = { ...(await lerTabela(await openAsBlob(arquivo), { aoLinha: (l) => { if (l.destino === 'dado') dados++; } })), dados_pelo_callback: dados };
  const msNode = Date.now() - t1;
  const igual = isDeepStrictEqual(noNavegador, noNode);
  if (!igual) falhou = true;
  console.log(JSON.stringify({
    arquivo: arquivo.split('/').pop(), igual_ao_node: igual, formato: noNavegador.formato,
    bytes: noNavegador.bytes, linhas: noNavegador.linhas, por_destino: noNavegador.por_destino,
    ms_navegador: msNavegador, pico_heap_js_mb: Math.round(picoHeap / 1048576), ms_node: msNode,
    avisos: noNavegador.avisos,
  }));
}
await navegador.close();
servidor.close();
process.exit(falhou ? 1 : 0);
