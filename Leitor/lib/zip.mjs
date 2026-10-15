// ABRIR O ZIP DO CONTADOR, em fluxo e por posição, com limites (Espec. 12, G5).
//
// O pacote do contador (canal C) chega como um zip com dezenas de SPEDs e milhares
// de XMLs, e o do dono (outubro/2026) passa de 3 GB. A versão anterior exigia o
// zip INTEIRO num Buffer, recusava ZIP64 e inflava com `inflateRawSync` — o que
// só roda no Node e limitava o pacote à memória. Esta lê o zip como um `Blob`:
//
//   - o diretório central é lido por `blob.slice` a partir do fim (EOCD nos
//     últimos 22 + 65535 bytes; ZIP64 pelo localizador e pelo EOCD64);
//   - cada entrada é um `ReadableStream`: `blob.slice(dados).stream()` e, se for
//     deflate (método 8), `DecompressionStream('deflate-raw')`. Nada do zip, nem
//     da entrada, é carregado inteiro: o pico de memória não depende do tamanho.
//
// UMA IMPLEMENTAÇÃO PARA OS DOIS LADOS (escada, degrau 2): `Blob`, `slice`, `stream()`
// e `DecompressionStream` são as mesmas no navegador (`File` é um `Blob`) e no Node
// 22 (`openAsBlob(caminho)` devolve um Blob que lê do disco por posição). Por isso
// a "leitura de bytes e o inflar injetados" é o próprio Blob: não há um segundo
// parser para divergir. Duas implementações do mesmo formato divergem sem erro.
//
// Os LIMITES são a parte que não pode faltar, porque o zip vem de fora:
//   - zip-bomb: razão de compressão por entrada e tamanho por entrada, e total;
//   - zip dentro de zip NÃO é aberto (vira item recusado, com motivo);
//   - tamanho declarado mentiroso: o fluxo da entrada ERRA no byte seguinte ao
//     declarado — nunca se infla além do que o próprio zip declarou — e erra se
//     terminar com menos. O CRC-32 também é conferido (um byte trocado numa
//     entrada sem compressão não derruba nenhum outro portão);
//   - entradas que apontam para os mesmos dados (zip sobreposto) são recusadas;
//   - entrada cifrada, método que não é 0/8 e zip em vários volumes: recusados
//     com motivo, nunca lidos pela metade.
// Toda entrada recusada volta na lista com `recusado` preenchido: um arquivo que
// ficou de fora aparece (regra 7), em vez de sumir do pacote.

import { saborDoZip } from '../../N8N/lib/formato.mjs';
import { latin1 } from './campos.mjs';

const KiB = 1024, MiB = 1024 * KiB, GiB = 1024 * MiB;

// OS NÚMEROS, E POR QUE MUDARAM. `bytesPorEntrada` (512 MiB) e `bytesTotal` (4 GiB)
// protegiam a MEMÓRIA, porque a versão antiga tinha a entrada inflada num Buffer.
// No fluxo a memória não depende deles (medido S108: ECD de 929 MB = 61 MB de heap),
// e um teto de 512 MiB recusaria um SPED legítimo — o ECD medido tem 929 MB. O que
// eles protegem agora é o TEMPO da aba aberta: 929 MB levaram 37,5 s no Chromium
// (~25 MB/s, leitura + sha256 + resumo).
//   - por entrada, 4 GiB (~3 min a 25 MB/s): é também o que o campo de 32 bits do
//     zip comum declara, então acima disso só ZIP64 e só com motivo explícito;
//   - total, 32 GiB (~22 min a 25 MB/s): mais que isso é um pacote para fatiar,
//     e o motivo diz "envie em mais de um zip".
// A defesa que NÃO mudou é a razão: 200x. SPED e XML fiscal comprimem 5–20x;
// 200x já é 10 vezes o normal e o deflate nunca passa de ~1032x. A zip-bomb
// clássica (razão ~1000x) é recusada ANTES de inflar um byte. [A CONFIRMAR] os 25 MB/s
// num computador de analista e os 4/32 GiB com o pacote real.
export const LIMITES = {
  entradas: 20000,
  bytesPorEntrada: 4 * GiB,
  bytesTotal: 32 * GiB,
  razaoMaxima: 200,
  // O diretório central é lido INTEIRO na memória (é o único trecho que é). 20.000
  // entradas de nome comum ocupam ~2 MB; 32 MiB cobre nomes de 1,5 KB e fecha a
  // porta de um diretório que declara 64 KB de nome em cada uma.
  bytesDiretorio: 32 * MiB,
};

/** @typedef {{nome: string, recusado: string, indice?: number, total?: number}} EntradaRecusada */
/** @typedef {{nome: string, tamanho: number, indice: number, total: number, fluxo: () => ReadableStream<Uint8Array>, recusado?: undefined}} EntradaAberta */

/** Falha de uma entrada com a frase pronta para ir ao analista. */
export class ErroDeEntrada extends Error {}

/** O motivo de uma falha lendo o fluxo de uma entrada, em português. */
export function motivoDoErro(e) {
  if (e instanceof ErroDeEntrada) return e.message;
  return `o conteúdo está corrompido ou truncado (${e?.message || e})`;
}

// ---------------------------------------------------------------- CRC-32

const TABELA_CRC = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

/** CRC-32 incremental: passe o retorno anterior como `crc` (começa em 0xffffffff; feche com `^ 0xffffffff`). */
export function crc32Atualizar(crc, bytes) {
  for (let i = 0; i < bytes.length; i++) crc = TABELA_CRC[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8);
  return crc;
}

// ---------------------------------------------------------------- leitura por posição

async function bytes(blob, ini, fim) {
  return new Uint8Array(await blob.slice(ini, fim).arrayBuffer());
}
const visao = (b) => new DataView(b.buffer, b.byteOffset, b.byteLength);
// Um inteiro de 64 bits que não cabe com exatidão num número vira Infinity: a
// comparação com qualquer limite dá "acima do limite" e a entrada é recusada.
const u64 = (v, o) => { const n = v.getBigUint64(o, true); return n > BigInt(Number.MAX_SAFE_INTEGER) ? Infinity : Number(n); };

/** Os primeiros `n` bytes de um fluxo (e cancela o resto). Serve ao zip-em-zip e à família da entrada. */
export async function lerCabeca(fluxo, n = 64 * KiB) {
  const r = fluxo.getReader();
  const partes = [];
  let total = 0;
  try {
    while (total < n) {
      const { done, value } = await r.read();
      if (done) break;
      partes.push(value);
      total += value.length;
    }
  } finally { await r.cancel().catch(() => {}); }
  const saida = new Uint8Array(Math.min(total, n));
  let o = 0;
  for (const p of partes) { const t = Math.min(p.length, saida.length - o); saida.set(p.subarray(0, t), o); o += t; }
  return saida;
}

/** O fim do diretório central — com ZIP64 quando o zip o usa. Devolve `{ n, tamanho, inicio }` ou `{ recusado }`. */
async function fimDoDiretorio(blob) {
  const tam = blob.size;
  const cauda = await bytes(blob, Math.max(0, tam - 22 - 65535), tam);
  const v = visao(cauda);
  let achado = -1, qualquer = -1;
  for (let i = cauda.length - 22; i >= 0; i--) {
    if (v.getUint32(i, true) !== 0x06054b50) continue;
    // O comentário declarado tem de ir até o fim do arquivo: um "EOCD" dentro do
    // comentário de um zip válido (ou de um zip hostil) não passa por este teste.
    if (i + 22 + v.getUint16(i + 20, true) === cauda.length) { achado = i; break; }
    if (qualquer < 0) qualquer = i;
  }
  if (achado < 0) achado = qualquer; // lixo depois do EOCD (comum em zip transmitido): aceita o último
  if (achado < 0) return { recusado: 'diretório central não encontrado: zip truncado ou corrompido' };
  const posAbs = tam - cauda.length + achado;
  if (v.getUint16(achado + 4, true) !== 0 || v.getUint16(achado + 6, true) !== 0) {
    return { recusado: 'zip em vários volumes (disco) não é aberto: junte os volumes num zip só' };
  }
  let n = v.getUint16(achado + 10, true), tamanho = v.getUint32(achado + 12, true), inicio = v.getUint32(achado + 16, true);
  if (n === 0xffff || tamanho === 0xffffffff || inicio === 0xffffffff) {
    // ZIP64: o localizador (20 bytes) fica logo antes do EOCD e aponta o EOCD64.
    if (posAbs < 20) return { recusado: 'ZIP64 sem localizador: zip corrompido' };
    const loc = await bytes(blob, posAbs - 20, posAbs);
    const lv = visao(loc);
    if (lv.getUint32(0, true) !== 0x07064b50) return { recusado: 'ZIP64 sem localizador: zip corrompido' };
    const pos64 = u64(lv, 8);
    if (!(pos64 + 56 <= tam)) return { recusado: 'ZIP64: o registro de fim do diretório está fora do arquivo' };
    const e64 = await bytes(blob, pos64, pos64 + 56);
    const ev = visao(e64);
    if (ev.getUint32(0, true) !== 0x06064b50) return { recusado: 'ZIP64: registro de fim do diretório inválido' };
    if (ev.getUint32(16, true) !== 0 || ev.getUint32(20, true) !== 0) {
      return { recusado: 'zip em vários volumes (disco) não é aberto: junte os volumes num zip só' };
    }
    n = u64(ev, 32); tamanho = u64(ev, 40); inicio = u64(ev, 48);
  }
  return { n, tamanho, inicio };
}

/** Os campos 0x0001 (ZIP64) do extra de uma entrada, na ordem que o formato fixa. */
function extraZip64(v, ini, nExtra) {
  for (let p = ini; p + 4 <= ini + nExtra;) {
    const id = v.getUint16(p, true), tam = v.getUint16(p + 2, true);
    if (id === 1) return { p: p + 4, fim: Math.min(p + 4 + tam, ini + nExtra) };
    p += 4 + tam;
  }
  return null;
}

// Os intervalos de dados já usados, ordenados por início, com busca binária: com
// 20.000 entradas a busca linear de antes era 2×10^8 comparações no pior caso.
function sobrepoe(usados, a, b) {
  let lo = 0, hi = usados.length;
  while (lo < hi) { const m = (lo + hi) >> 1; if (usados[m][0] < a) lo = m + 1; else hi = m; }
  return { lo, bate: (lo > 0 && usados[lo - 1][1] > a) || (lo < usados.length && usados[lo][0] < b) };
}

// O fluxo de UMA entrada, com a guarda do tamanho declarado e o CRC. A guarda é o
// último elo: o que o consumidor lê já passou por ela.
function fluxoDaEntrada(blob, ini, fim, metodo, tamOrig, crcEsperado) {
  let s = blob.slice(ini, fim).stream();
  if (metodo === 8) s = s.pipeThrough(new DecompressionStream('deflate-raw'));
  let n = 0, crc = 0xffffffff;
  return s.pipeThrough(new TransformStream({
    transform(fatia, c) {
      n += fatia.length;
      // Para no PRIMEIRO byte acima do declarado, antes de repassá-lo: uma entrada
      // que diz 1 KB e infla 500 MB nunca entrega mais que 1 KB + a fatia em curso.
      if (n > tamOrig) throw new ErroDeEntrada(`o conteúdo passa do tamanho declarado (${tamOrig} bytes): suspeita de zip-bomb`);
      crc = crc32Atualizar(crc, fatia);
      c.enqueue(fatia);
    },
    flush() {
      if (n !== tamOrig) throw new ErroDeEntrada(`o conteúdo termina com ${n} bytes, e o zip declara ${tamOrig}: zip truncado ou corrompido`);
      if (((crc ^ 0xffffffff) >>> 0) !== crcEsperado) throw new ErroDeEntrada('o CRC-32 não confere: o conteúdo foi alterado ou corrompido');
    },
  }));
}

/**
 * As entradas do zip, UMA DE CADA VEZ (gerador assíncrono): quem consome processa e
 * descarta. `blob` é um `Blob`/`File` (ou `openAsBlob` no Node); `Uint8Array` também
 * serve (vira Blob). Cada item é `{ nome, tamanho, indice, total, fluxo }` — `fluxo()`
 * abre um `ReadableStream<Uint8Array>` NOVO do conteúdo, que erra se o tamanho ou o
 * CRC não bater (use `motivoDoErro`) — ou `{ nome, recusado }` com o motivo.
 * `total` é o número de registros do diretório (inclui as pastas, que não saem).
 * @returns {AsyncGenerator<EntradaRecusada | EntradaAberta>}
 */
export async function* entradasDoZip(blob, limites = LIMITES) {
  // Um objeto com `slice` + `stream` (Blob, File, ou o espião dos testes) é usado como está.
  if (typeof blob?.stream !== 'function' || typeof blob?.slice !== 'function') blob = new Blob([blob]);
  const fim = await fimDoDiretorio(blob);
  if (fim.recusado) { yield { nome: '(zip)', recusado: fim.recusado }; return; }
  if (fim.n > limites.entradas) { yield { nome: '(zip)', recusado: `${fim.n} entradas, acima do limite de ${limites.entradas}` }; return; }
  if (fim.tamanho > limites.bytesDiretorio) { yield { nome: '(zip)', recusado: `diretório central de ${fim.tamanho} bytes, acima do limite de ${limites.bytesDiretorio}` }; return; }
  if (!(fim.inicio + fim.tamanho <= blob.size)) { yield { nome: '(zip)', recusado: 'diretório central fora do arquivo: zip truncado ou corrompido' }; return; }
  const dir = await bytes(blob, fim.inicio, fim.inicio + fim.tamanho);
  const v = visao(dir);
  let p = 0, total = 0;
  const usados = [];
  for (let i = 0; i < fim.n; i++) {
    if (p + 46 > dir.length || v.getUint32(p, true) !== 0x02014b50) { yield { nome: '(zip)', recusado: 'diretório central corrompido' }; return; }
    const flags = v.getUint16(p + 8, true), metodo = v.getUint16(p + 10, true);
    const crcEsperado = v.getUint32(p + 16, true);
    let tamComp = v.getUint32(p + 20, true), tamOrig = v.getUint32(p + 24, true);
    const nNome = v.getUint16(p + 28, true), nExtra = v.getUint16(p + 30, true), nComent = v.getUint16(p + 32, true);
    let local = v.getUint32(p + 42, true);
    if (p + 46 + nNome + nExtra + nComent > dir.length) { yield { nome: '(zip)', recusado: 'diretório central corrompido' }; return; }
    const nomeBytes = dir.subarray(p + 46, p + 46 + nNome);
    const nome = flags & 0x800 ? new TextDecoder('utf-8').decode(nomeBytes) : latin1(nomeBytes);
    const extraIni = p + 46 + nNome;
    p += 46 + nNome + nExtra + nComent;
    const ref = { nome, indice: i + 1, total: fim.n };
    if (nome.endsWith('/')) continue; // diretório
    // ZIP64 nas entradas: o extra 0x0001 traz, NESTA ordem, só os campos cujo valor
    // de 32 bits é 0xFFFFFFFF.
    if (tamOrig === 0xffffffff || tamComp === 0xffffffff || local === 0xffffffff) {
      const z = extraZip64(v, extraIni, nExtra);
      let q = z?.p ?? 0;
      const ler = () => { if (!z || q + 8 > z.fim) return NaN; const x = u64(v, q); q += 8; return x; };
      if (tamOrig === 0xffffffff) tamOrig = ler();
      if (tamComp === 0xffffffff) tamComp = ler();
      if (local === 0xffffffff) local = ler();
      if (Number.isNaN(tamOrig) || Number.isNaN(tamComp) || Number.isNaN(local)) { yield { ...ref, recusado: 'ZIP64 incompleto: o extra da entrada não traz os tamanhos' }; continue; }
    }
    if (flags & 0x41 || metodo === 99) { yield { ...ref, recusado: 'entrada cifrada (zip com senha)' }; continue; }
    if (metodo !== 0 && metodo !== 8) { yield { ...ref, recusado: `método de compressão ${metodo} não suportado (só armazenado e deflate)` }; continue; }
    if (tamOrig > limites.bytesPorEntrada) { yield { ...ref, recusado: `${tamOrig} bytes descompactados, acima do limite por entrada de ${limites.bytesPorEntrada}` }; continue; }
    if (metodo === 0 && tamComp !== tamOrig) { yield { ...ref, recusado: 'entrada sem compressão com tamanhos diferentes: zip corrompido' }; continue; }
    if (tamComp > 0 && tamOrig / tamComp > limites.razaoMaxima) { yield { ...ref, recusado: `razão de compressão ${Math.round(tamOrig / tamComp)}x, acima de ${limites.razaoMaxima}x (suspeita de zip-bomb)` }; continue; }
    // O total é cobrado ANTES de descompactar, pelo tamanho declarado: uma entrada
    // que falha depois também gastou o que inflou.
    if (total + tamOrig > limites.bytesTotal) { yield { ...ref, recusado: `o pacote passa do limite total descompactado de ${limites.bytesTotal} bytes: envie em mais de um zip` }; continue; }
    total += tamOrig;
    if (!(local + 30 <= blob.size)) { yield { ...ref, recusado: 'cabeçalho local fora do arquivo: zip truncado ou corrompido' }; continue; }
    const lh = await bytes(blob, local, local + 30);
    const lv = visao(lh);
    if (lv.getUint32(0, true) !== 0x04034b50) { yield { ...ref, recusado: 'cabeçalho local ausente: zip corrompido' }; continue; }
    const ini = local + 30 + lv.getUint16(26, true) + lv.getUint16(28, true);
    const fimDados = ini + tamComp;
    if (!(fimDados <= blob.size)) { yield { ...ref, recusado: 'os dados da entrada passam do fim do arquivo: zip truncado' }; continue; }
    // Os trechos de dados já usados. O diretório central pode apontar VÁRIAS entradas
    // para o mesmo bloco comprimido (a "better zip bomb"): cada uma infla o mesmo
    // bloco de novo, e o total explode sem nenhum arquivo grande no pacote.
    const s = sobrepoe(usados, ini, fimDados);
    if (s.bate) { yield { ...ref, recusado: 'entrada aponta para dados de outra entrada (zip sobreposto, suspeita de zip-bomb)' }; continue; }
    if (fimDados > ini) usados.splice(s.lo, 0, [ini, fimDados]);
    const fluxo = () => fluxoDaEntrada(blob, ini, fimDados, metodo, tamOrig, crcEsperado);
    // Zip dentro de zip: pela assinatura, não pelo nome (planilha e documento Office
    // também são zip; quem os separa é `saborDoZip`). Olha só os primeiros 8 KB
    // inflados; se a entrada tem menos que isso, ela é lida inteira e as guardas de
    // tamanho e CRC já rodam aqui.
    let cabeca;
    try { cabeca = await lerCabeca(fluxo(), 8192); } catch (e) { yield { ...ref, recusado: motivoDoErro(e) }; continue; }
    if (cabeca.length >= 4 && visao(cabeca).getUint32(0, true) === 0x04034b50 && saborDoZip(cabeca) === 'zip') {
      yield { ...ref, recusado: 'zip dentro de zip não é aberto: envie os arquivos num zip só' }; continue;
    }
    yield { ...ref, tamanho: tamOrig, fluxo };
  }
}

/** Todas as entradas na memória, com `buf` (testes e pacotes pequenos: o conteúdo inteiro de cada uma). */
export async function abrirZip(blob, limites = LIMITES) {
  const saida = [];
  for await (const e of entradasDoZip(blob, limites)) {
    if (e.recusado) { saida.push({ nome: e.nome, recusado: e.recusado }); continue; }
    try {
      const partes = [];
      const r = e.fluxo().getReader();
      for (;;) { const { done, value } = await r.read(); if (done) break; partes.push(value); }
      saida.push({ nome: e.nome, buf: new Uint8Array(await new Blob(partes).arrayBuffer()) });
    } catch (err) { saida.push({ nome: e.nome, recusado: motivoDoErro(err) }); }
  }
  return saida;
}
