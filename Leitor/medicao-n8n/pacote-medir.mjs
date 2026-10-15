// Mede o worker de zip DO PORTAL (o mesmo `leitor-zip-worker.ts`, empacotado com esbuild do
// `portal/node_modules`) num Chromium de verdade, sobre um zip do disco: tempo, pico de heap JS do
// WORKER (CDP `Runtime.getHeapUsage` no alvo do worker) e pico de RSS dos processos do navegador.
// Uso (da pasta onde estão os dois arquivos; só NOMES, sem barra, como os outros scripts desta pasta):
//   node <repo>/Leitor/medicao-n8n/pacote-medir.mjs <nome-do-zip> <nome-da-ecd-de-referencia>
//   (o zip sai de `pacote-montar.py`; a ECD de referência dá o `sha256` que o hash lido tem de igualar)
// Cada entrada oficial é "gravada" com um atraso proporcional ao resumo (2 s para ~4,7 MB, o que a
// tela espera do banco): o worker só segue depois do `continuar`, como no portal.
import { createRequire } from 'node:module';
import { readFileSync, readdirSync, writeFileSync, createReadStream } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { nomeDaLinhaDeComando } from './caminho.mjs';
const R = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SC = tmpdir();
const require = createRequire(import.meta.url);
const esbuild = require(`${R}/portal/node_modules/esbuild`);
let pw; try { pw = require('playwright'); } catch { pw = require(join(dirname(dirname(process.execPath)), 'lib', 'node_modules', 'playwright')); }

writeFileSync(`${SC}/entrada-worker.ts`, `
import "${R}/portal/src/lib/leitor-zip-worker.ts";
`);
const out = await esbuild.build({ entryPoints: [`${SC}/entrada-worker.ts`], bundle: true, write: false, format: 'iife', platform: 'browser', target: 'es2022', logLevel: 'error' });
const codigo = out.outputFiles[0].text;
console.log('worker empacotado:', Math.round(codigo.length / 1024), 'KB');

const zip = nomeDaLinhaDeComando(process.argv[2], 'zip'), referencia = nomeDaLinhaDeComando(process.argv[3], 'ECD de referência');
const sha = await new Promise((ok, erro) => { const h = createHash('sha256'); createReadStream(referencia).on('data', (d) => h.update(d)).on('end', () => ok(h.digest('hex'))).on('error', erro); });

const navegador = await pw.chromium.launch({ args: ['--remote-debugging-port=9333'] });
const pagina = await navegador.newPage();
await pagina.setContent('<input type="file" id="f">');
await pagina.setInputFiles('#f', zip);

let picoRss = 0, picoHeapWorker = 0;
// O heap do WORKER: CDP cru no endpoint do navegador (o CDPSession do Playwright não fala com worker).
// O endereço vem da resposta do navegador (entrada): só o CAMINHO é aproveitado, e só se tiver a forma
// de um alvo de navegador; host e porta são os que NÓS abrimos (127.0.0.1:9333), nunca os da resposta.
const { webSocketDebuggerUrl } = await (await fetch('http://127.0.0.1:9333/json/version')).json();
const caminhoWs = new URL(webSocketDebuggerUrl).pathname;
if (!/^\/devtools\/browser\/[0-9a-f-]+$/i.test(caminhoWs)) throw new Error(`endereço de depuração inesperado: ${caminhoWs}`);
const ws = new WebSocket(`ws://127.0.0.1:9333${caminhoWs}`);
await new Promise((ok) => ws.addEventListener('open', ok));
let idMsg = 0; const pend = new Map(); const sessoes = new Set();
ws.addEventListener('message', (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); }
  if (m.method === 'Target.attachedToTarget' && m.params.targetInfo.type === 'worker') sessoes.add(m.params.sessionId);
});
const cdp = (method, params, sessionId) => new Promise((ok) => { const id = ++idMsg; pend.set(id, ok); ws.send(JSON.stringify({ id, method, params: params ?? {}, ...(sessionId ? { sessionId } : {}) })); });
await cdp('Target.setAutoAttach', { autoAttach: true, waitForDebuggerOnStart: false, flatten: true });
const alvos = (await cdp('Target.getTargets')).result.targetInfos.filter((t) => t.type === 'page');
for (const a of alvos) await cdp('Target.setAutoAttach', { autoAttach: true, waitForDebuggerOnStart: false, flatten: true }, (await cdp('Target.attachToTarget', { targetId: a.targetId, flatten: true })).result.sessionId);
const amostraHeap = setInterval(async () => {
  for (const s of sessoes) { const h = await cdp('Runtime.getHeapUsage', {}, s); if (h.result) picoHeapWorker = Math.max(picoHeapWorker, h.result.usedSize); }
}, 250);
const amostra = setInterval(() => {
  let rss = 0;
  for (const pid of readdirSync('/proc').filter((p) => /^\d+$/.test(p))) {
    try {
      if (!/chrom/i.test(readFileSync(`/proc/${pid}/cmdline`, 'latin1'))) continue;
      const m = /VmRSS:\s+(\d+)/.exec(readFileSync(`/proc/${pid}/status`, 'latin1'));
      if (m) rss += Number(m[1]);
    } catch { /* o processo terminou */ }
  }
  picoRss = Math.max(picoRss, rss);
}, 500);

await pagina.exposeFunction('registrar', (t) => console.error(t));
const r = await pagina.evaluate(async ({ codigo, atrasoGravacaoMs }) => {
  const url = URL.createObjectURL(new Blob([codigo], { type: 'text/javascript' }));
  const worker = new Worker(url);
  const f = document.getElementById('f').files[0];
  const t0 = performance.now();
  const eventos = [];
  let entradas = 0;
  const resultado = await new Promise((resolver, rejeitar) => {
    worker.onerror = (e) => rejeitar(new Error(e.message));
    worker.onmessage = async (e) => {
      const m = e.data;
      if (m.tipo === 'progresso') return;
      const t = Math.round(performance.now() - t0);
      if (m.tipo !== 'fim') window.registrar(`${t} ms ${m.tipo} ${m.nome ?? ''} ${m.motivo ?? ''}`.slice(0, 200));
      if (m.tipo === 'oficial') {
        eventos.push({ t, tipo: m.tipo, nome: m.nome, status: m.envelope.status, hash: m.envelope.hash_sha256, lidas: m.envelope.controle_lido, declaradas: m.envelope.controle_declarado,
          resumo_bytes: JSON.stringify(m.resumo).length, ausente: m.resumo.ausente ?? null });
        entradas++;
        // a gravação no banco, proporcional ao resumo: 2 s para os ~4,7 MB de um ECD de 10M de linhas (S108: 1,6 s para 300 mil linhas)
        await new Promise((r) => setTimeout(r, Math.max(20, atrasoGravacaoMs * JSON.stringify(m.resumo).length / 4.7e6)));
        worker.postMessage({ tipo: 'continuar' });
        return;
      }
      if (m.tipo === 'nao_oficial') eventos.push({ t, tipo: m.tipo, nome: m.nome, bytes: m.bytes, vai: !!m.arquivo, situacao: m.situacao ?? null, motivo: m.motivo ?? null });
      else if (m.tipo === 'oficial_inicio') eventos.push({ t, tipo: m.tipo, nome: m.nome, bytes: m.bytes, familia: m.familia });
      else if (m.tipo === 'recusada') eventos.push({ t, tipo: m.tipo, nome: m.nome, motivo: m.motivo });
      else eventos.push({ t, ...m });
      if (m.tipo === 'fim' || m.tipo === 'erro') { worker.terminate(); resolver(m); }
    };
    worker.postMessage({ tipo: 'abrir', zip: f });
  });
  return { ms: Math.round(performance.now() - t0), tamanho_zip: f.size, resultado, eventos };
}, { codigo, atrasoGravacaoMs: 2000 });
clearInterval(amostra); clearInterval(amostraHeap);
await navegador.close();

const resumo = {
  ms_total: r.ms, segundos_total: Math.round(r.ms / 100) / 10, tamanho_zip_bytes: r.tamanho_zip, resultado: r.resultado,
  pico_heap_js_worker_mb: Math.round(picoHeapWorker / 1048576), workers_vistos: sessoes.size, pico_rss_chromium_mb: Math.round(picoRss / 1024),
  sha256_de_referencia: sha,
  oficiais: r.eventos.filter((e) => e.tipo === 'oficial').map((e) => ({ ...e, hash_igual_ao_sha256: e.hash === sha })).filter((e) => e.nome.startsWith('sped/ecd')),
  contagem_por_tipo: Object.fromEntries(['oficial', 'nao_oficial', 'recusada', 'oficial_inicio'].map((t) => [t, r.eventos.filter((e) => e.tipo === t).length])),
  nao_oficiais_que_vao_ao_n8n: r.eventos.filter((e) => e.tipo === 'nao_oficial' && e.vai).length,
  nao_oficiais_de_fora_ou_ignoradas: r.eventos.filter((e) => e.tipo === 'nao_oficial' && !e.vai).map((e) => ({ nome: e.nome, bytes: e.bytes, situacao: e.situacao, motivo: (e.motivo || '').slice(0, 90) })),
  recusadas: r.eventos.filter((e) => e.tipo === 'recusada'),
  linha_do_tempo_ms: r.eventos.filter((e) => e.tipo === 'oficial_inicio' || (e.tipo === 'oficial' && e.nome.startsWith('sped/'))).map((e) => `${e.t} ${e.tipo} ${e.nome}`),
};
console.log(JSON.stringify(resumo, null, 1));
ws.close();
