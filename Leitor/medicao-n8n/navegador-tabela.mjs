// O LEITOR TABULAR (`Leitor/lib/tabela.mjs`, MB1) e o MAPEAMENTO (`mapeamento.mjs`, MB2) num
// Chromium de verdade, contra o Node. Com `--mapear`, cada arquivo é lido duas vezes como na
// tela: a 1ª só até o cabeçalho e a amostra (`soAmostra`), a 2ª aplicando o mapeamento proposto (confirmado
// aqui como está) a toda linha; o que se compara é o resumo do aplicador.
// Serve a raiz do repositório por HTTP, importa o módulo no navegador (não uma cópia), lê o
// arquivo com `File` e compara o resumo inteiro com o do Node (`openAsBlob`). Mede o tempo
// e o pico de heap JS da página. O portal roda o leitor num Web Worker; aqui ele roda na
// página porque é dela que o CDP dá o heap. O código é o mesmo.
// Uso: node Leitor/medicao-n8n/navegador-tabela.mjs [--mapear] <arquivo>...
import http from 'node:http';
import { createReadStream, openAsBlob, statSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { caminhoDaUrl } from './caminho.mjs';
import { lerTabela } from '../lib/tabela.mjs';
import { proporMapeamento, aplicadorDeMapeamento } from '../lib/mapeamento.mjs';

const mapear = process.argv.includes('--mapear');
const arquivos = process.argv.slice(2).filter((a) => a !== '--mapear');

/** O mesmo caminho nos dois lados: ler, propor, "confirmar", aplicar. Recebe as funções para rodar igual no navegador. */
async function caminho(blob, lerTabela, proporMapeamento, aplicadorDeMapeamento) {
  const r1 = await lerTabela(blob, { soAmostra: true });
  const p = proporMapeamento(r1.cabecalho.celulas, r1.amostra, { tipos: r1.amostra_tipos });
  const ap = aplicadorDeMapeamento({ mapa: p.mapa, formato: p.formato, cabecalho: r1.cabecalho.celulas, confirmado_por: 'medicao', confirmado_em: 'agora' });
  await lerTabela(blob, { aoLinha: (l) => ap.linha(l) });
  return ap.resumo();
}

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
for (const arquivo of arquivos) {
  await pagina.setInputFiles('#f', arquivo);
  const cdp = await pagina.context().newCDPSession(pagina);
  await cdp.send('Performance.enable');
  let picoHeap = 0;
  const amostrar = setInterval(async () => {
    try { const { metrics } = await cdp.send('Performance.getMetrics'); picoHeap = Math.max(picoHeap, metrics.find((m) => m.name === 'JSHeapUsedSize').value); } catch { /* fim */ }
  }, 250);
  const t0 = Date.now();
  const noNavegador = await pagina.evaluate(async ([url, urlMap, mapear, fonte]) => {
    const { lerTabela } = await import(url);
    const f = document.getElementById('f').files[0];
    if (mapear) {
      const { proporMapeamento, aplicadorDeMapeamento } = await import(urlMap);
      return (0, eval)(`(${fonte})`)(f, lerTabela, proporMapeamento, aplicadorDeMapeamento);
    }
    let dados = 0;
    const r = await lerTabela(f, { aoLinha: (l) => { if (l.destino === 'corpo') dados++; } });
    return { ...r, corpo_pelo_callback: dados };
  }, [base + '/Leitor/lib/tabela.mjs', base + '/Leitor/lib/mapeamento.mjs', mapear, caminho.toString()]);
  const msNavegador = Date.now() - t0;
  clearInterval(amostrar);
  await cdp.detach();
  const t1 = Date.now();
  let dados = 0;
  const noNode = mapear
    ? await caminho(await openAsBlob(arquivo), lerTabela, proporMapeamento, aplicadorDeMapeamento)
    : { ...(await lerTabela(await openAsBlob(arquivo), { aoLinha: (l) => { if (l.destino === 'corpo') dados++; } })), corpo_pelo_callback: dados };
  const msNode = Date.now() - t1;
  const igual = isDeepStrictEqual(noNavegador, noNode);
  if (!igual) falhou = true;
  console.log(JSON.stringify({
    arquivo: arquivo.split('/').pop(), igual_ao_node: igual, formato: noNavegador.formato,
    bytes: noNavegador.bytes, linhas: noNavegador.linhas, por_destino: noNavegador.por_destino,
    ...(mapear ? { titulos: noNavegador.titulo, subtotais: noNavegador.subtotal, rejeitadas: noNavegador.rejeitada, saldo_titulos: noNavegador.saldo_titulos, conferencia: noNavegador.conferencia_com_o_total_do_arquivo?.estado } : {}),
    ms_navegador: msNavegador, pico_heap_js_mb: Math.round(picoHeap / 1048576), ms_node: msNode,
    avisos: noNavegador.avisos,
  }));
}
await navegador.close();
servidor.close();
process.exit(falhou ? 1 : 0);
