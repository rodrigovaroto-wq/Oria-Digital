// O LEITOR DO REPOSITÓRIO num Chromium de verdade (não uma cópia): serve a raiz do
// repositório por HTTP, importa `Leitor/lib/envelope.mjs` no navegador, lê o arquivo
// com `File.stream()` e compara o envelope e o resumo com os do CLI (`arquivo.mjs`).
// Uso: node Leitor/medicao-n8n/navegador-igual-ao-cli.mjs <arquivo>...
import http from 'node:http';
import { createReadStream, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { caminhoDaUrl } from './caminho.mjs';
import { join, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { isDeepStrictEqual } from 'node:util';
import { lerEnvelopeDeArquivo } from '../lib/arquivo.mjs';

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const servidor = http.createServer((q, s) => {
  const f = caminhoDaUrl(raiz, q.url);
  if (!f) { s.writeHead(403); return s.end(); }
  try { statSync(f); } catch { s.writeHead(404); return s.end(); }
  s.writeHead(200, { 'content-type': extname(f) === '.mjs' ? 'text/javascript' : 'text/html' });
  createReadStream(f).pipe(s);
}).listen(0, '127.0.0.1');
await new Promise(r => servidor.once('listening', r));
const base = `http://127.0.0.1:${servidor.address().port}`;

const require = createRequire(import.meta.url);
// O playwright global mora em <prefixo do node>/lib/node_modules: achado pelo executável do
// próprio node, e não por `npm root -g` (um comando resolvido pelo PATH).
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
    try { const { metrics } = await cdp.send('Performance.getMetrics'); picoHeap = Math.max(picoHeap, metrics.find(m => m.name === 'JSHeapUsedSize').value); } catch { /* fim */ }
  }, 250);
  const t0 = Date.now();
  const noNavegador = await pagina.evaluate(async (url) => {
    const { lerEnvelopeDeFluxo } = await import(url);
    const f = document.getElementById('f').files[0];
    return lerEnvelopeDeFluxo(f.stream(), { resumir: true });
  }, base + '/Leitor/lib/envelope.mjs');
  const msNavegador = Date.now() - t0;
  clearInterval(amostrar);
  await cdp.detach();
  const t1 = Date.now();
  const noCli = await lerEnvelopeDeArquivo(arquivo, { resumir: true });
  const msCli = Date.now() - t1;
  // O hash de conferência sai do node:crypto (independente do Sha256 do leitor), e não do
  // `sha256sum` pelo PATH.
  const sha = await new Promise((ok, erro) => { const h = createHash('sha256'); createReadStream(arquivo).on('data', (d) => h.update(d)).on('end', () => ok(h.digest('hex'))).on('error', erro); });
  const igual = isDeepStrictEqual(noNavegador, noCli);
  if (!igual || noCli.envelope.hash_sha256 !== sha) falhou = true;
  console.log(JSON.stringify({
    arquivo: arquivo.split('/').pop(), igual_ao_cli: igual, hash_igual_sha256sum: noCli.envelope.hash_sha256 === sha,
    status: noNavegador.envelope.status, linhas: noNavegador.envelope.controle_lido, declarado: noNavegador.envelope.controle_declarado,
    nome: noNavegador.envelope.detalhe.nome, ms_navegador: msNavegador, pico_heap_js_mb: Math.round(picoHeap / 1048576),
    grupos: noNavegador.resumo.lancamentos_por_conta_mes?.length, registros_integra: noNavegador.resumo.registros?.length, resumo_ausente: noNavegador.resumo.ausente, ms_cli: msCli,
    resumo_bytes: JSON.stringify(noNavegador.resumo).length,
  }));
}
await navegador.close();
servidor.close();
process.exit(falhou ? 1 : 0);
