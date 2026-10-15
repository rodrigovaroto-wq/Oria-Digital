// O ZIP EM FLUXO E POR POSIÇÃO (Espec. 12, G5; sessão 109).
//
// O pacote do dono passa de 3 GB. O que estes testes travam, e cada item é uma forma
// de errar que não dá erro nenhum:
//   - o zip NÃO é carregado inteiro: só o diretório e a entrada em curso (o espião
//     conta os bytes que o leitor de fato pediu ao Blob);
//   - ZIP64 (localizador, EOCD64 e extra 0x0001) abre — o Windows e o macOS o usam
//     com muito menos de 4 GB quando passam de 65.535 entradas ou escrevem em fluxo;
//   - cada recusa tem o seu motivo e NENHUMA some da lista (regra 7): bomba, zip
//     sobreposto, aninhado, cifrado, truncado, tamanho mentiroso, CRC errado,
//     método desconhecido, vários volumes e cada limite;
//   - uma entrada recusada não derruba as outras.
// ZIPS GERADOS AQUI, NÃO REAIS (regra 4): não dá para reproduzir num teste um zip de
// 3 GB. O ZIP64 daqui é o formato (extra 0x0001, EOCD64, localizador) com dados
// pequenos; o que ele NÃO prova é um arquivo de mais de 4 GiB — isso é medido à parte
// no Chromium (ver o commit).
import test from 'node:test';
import assert from 'node:assert/strict';
import { entradasDoZip, abrirZip, lerCabeca, crc32Atualizar, LIMITES } from '../lib/zip.mjs';
import { lerEnvelopeDeFluxo } from '../lib/envelope.mjs';
import { gerarZip, gerarSped, gerarXmlFiscal } from '../../Dados de Teste/fontes-oficiais/gerar.mjs';
import { crc32 } from 'node:zlib';
import { openAsBlob, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const blob = (b) => new Blob([b]);
const E = (nome, buf, extra = {}) => ({ nome, buf: Buffer.isBuffer(buf) ? buf : Buffer.from(buf), ...extra });
const doNome = (lista, nome) => lista.find((x) => x.nome === nome);

test('crc32 do leitor é o do zlib (a conferência de integridade não pode divergir do zip)', () => {
  const b = Buffer.from('SPED |0000|LECD| é um teste de CRC 0123456789'.repeat(200));
  assert.equal(((crc32Atualizar(0xffffffff, b) ^ 0xffffffff) >>> 0), crc32(b) >>> 0);
});

test('armazenado e deflate: o conteúdo de cada entrada sai idêntico, byte a byte', async () => {
  const sped = gerarSped('ECD');
  for (const deflate of [false, true]) {
    const l = await abrirZip(blob(await gerarZip([E('a/ecd.txt', sped), E('b.xml', gerarXmlFiscal('nfe')), E('vazio.txt', '')], { deflate })));
    assert.equal(l.length, 3, `deflate=${deflate}`);
    assert.ok(Buffer.from(doNome(l, 'a/ecd.txt').buf).equals(sped), `deflate=${deflate}: o ECD saiu diferente`);
    assert.equal(doNome(l, 'vazio.txt').buf.length, 0, 'a entrada vazia é uma entrada, não sumiu nem foi recusada');
  }
});

test('ZIP64: localizador, EOCD64 e extra 0x0001 nas entradas — armazenado e deflate', async () => {
  const sped = gerarSped('ECD');
  for (const deflate of [false, true]) {
    const z = await gerarZip([E('ecd.txt', sped), E('n.xml', gerarXmlFiscal('nfe'))], { deflate, zip64: true });
    // O controle positivo: o zip gerado É zip64 (os campos de 32 bits estão em 0xFFFFFFFF). Sem isto o teste passaria com um zip comum.
    assert.equal(z.readUInt32LE(z.length - 22 + 12), 0xffffffff, 'o gerador não produziu ZIP64');
    const l = await abrirZip(blob(z));
    assert.equal(l.length, 2, `deflate=${deflate}: ${JSON.stringify(l.map((x) => x.recusado))}`);
    assert.ok(Buffer.from(doNome(l, 'ecd.txt').buf).equals(sped), `deflate=${deflate}: ECD diferente`);
  }
});

test('ZIP64 quebrado é recusado com motivo: sem localizador e com extra incompleto', async () => {
  const z = await gerarZip([E('a.xml', gerarXmlFiscal('nfe'))], { zip64: true });
  const semLocalizador = Buffer.from(z);
  semLocalizador.writeUInt32LE(0, semLocalizador.length - 22 - 20); // apaga a assinatura do localizador
  assert.match((await abrirZip(blob(semLocalizador)))[0].recusado, /ZIP64 sem localizador/);
  const semExtra = Buffer.from(z);
  const cd = semExtra.indexOf(Buffer.from([0x50, 0x4b, 0x01, 0x02]));
  semExtra.writeUInt16LE(2, cd + 46 + 'a.xml'.length); // o extra deixa de ser o 0x0001
  const l = await abrirZip(blob(semExtra));
  assert.equal(l.length, 1);
  assert.match(l[0].recusado, /ZIP64 incompleto/);
});

test('o comentário do zip não esconde o diretório, nem um "EOCD" dentro dele engana', async () => {
  const falso = 'comentário PK\x05\x06' + 'A'.repeat(30);
  const l = await abrirZip(blob(await gerarZip([E('a.xml', gerarXmlFiscal('nfe'))], { comentario: falso })));
  assert.equal(l.length, 1);
  assert.ok(l[0].buf?.length > 0, JSON.stringify(l[0].recusado));
});

test('o zip NÃO é carregado inteiro: abrir o diretório e olhar as entradas pede só uma fração dos bytes', async () => {
  const grande = Buffer.alloc(20 * 1024 * 1024);
  for (let i = 0; i < grande.length; i += 4) grande.writeUInt32LE((i * 2654435761) >>> 0, i); // quase incompressível
  const z = await gerarZip([E('grande.bin', grande), E('b.xml', gerarXmlFiscal('nfe'))], { deflate: false });
  const lidos = { n: 0 };
  const conta = (s) => ({
    async arrayBuffer() { const ab = await s.arrayBuffer(); lidos.n += ab.byteLength; return ab; },
    stream() { return s.stream().pipeThrough(new TransformStream({ transform(c, k) { lidos.n += c.length; k.enqueue(c); } })); },
  });
  // Do DISCO, como o CLI: um Blob em memória entrega o conteúdo todo num pedaço só (medido: 1 fatia de 20 MB),
  // e o espião mediria o Blob, não o leitor. O de disco entrega fatias de 64 KB, como o `File.stream()`.
  const dir = mkdtempSync(join(tmpdir(), 'zip-'));
  writeFileSync(join(dir, 'g.zip'), z);
  const real = await openAsBlob(join(dir, 'g.zip'));
  const espiao = { size: real.size, stream: () => real.stream(), slice: (a, b) => conta(real.slice(a, b)) };
  const entradas = [];
  for await (const e of entradasDoZip(espiao)) entradas.push(e);
  assert.equal(entradas.length, 2);
  assert.ok(entradas.every((e) => typeof e.fluxo === 'function'), JSON.stringify(entradas.map((e) => e.recusado)));
  // Só o diretório, os cabeçalhos locais e os primeiros 8 KB de cada entrada (a espiada do zip-em-zip).
  assert.ok(lidos.n < 1024 * 1024, `abrir pediu ${lidos.n} bytes de um zip de ${z.length}: leu o conteúdo`);
  // E ao CONSUMIR a entrada, o conteúdo todo passa — a espiada de cima não substitui a leitura.
  const antes = lidos.n;
  const r = entradas[0].fluxo().getReader();
  let total = 0;
  for (;;) { const { done, value } = await r.read(); if (done) break; total += value.length; }
  assert.equal(total, grande.length);
  assert.ok(lidos.n - antes >= grande.length);
  rmSync(dir, { recursive: true });
});

test('zip-bomb por razão de compressão: recusada ANTES de inflar um byte', async () => {
  const bomba = Buffer.alloc(5 * 1024 * 1024, 0x41);
  const z = await gerarZip([E('bomba.txt', bomba), E('ok.xml', gerarXmlFiscal('nfe'))]);
  const l = await abrirZip(blob(z));
  assert.match(doNome(l, 'bomba.txt').recusado, /razão de compressão \d+x.*zip-bomb/);
  assert.ok(doNome(l, 'ok.xml').buf, 'a entrada boa foi levada junto com a bomba');
  assert.equal(l.length, 2, 'a bomba sumiu da lista');
});

test('tamanho declarado mentiroso: o fluxo PARA no declarado, em vez de inflar até o fim', async () => {
  const z = await gerarZip([E('grande.xml', Buffer.alloc(20000, 0x20), { mentirTamanho: true })]);
  assert.match((await abrirZip(blob(z)))[0].recusado, /passa do tamanho declarado/);
  // Sem o portão de razão, quem recusa é o próprio fluxo: nunca entrega mais que o declarado + a fatia em curso.
  const itens = [];
  for await (const x of entradasDoZip(blob(z), { ...LIMITES, razaoMaxima: 1e9 })) itens.push(x);
  assert.equal(itens.length, 1);
  assert.match(itens[0].recusado, /passa do tamanho declarado/);
});

test('tamanho declarado MAIOR que o real: o fluxo termina com menos e a entrada é recusada com os dois números', async () => {
  // Deflate válido de 50 bytes, com o diretório declarando 60: a razão e o CRC estão certos, só o tamanho mente.
  const z = Buffer.from(await gerarZip([E('a.txt', 'x'.repeat(50))]));
  const cd = z.indexOf(Buffer.from([0x50, 0x4b, 0x01, 0x02]));
  z.writeUInt32LE(60, cd + 24);
  const l = await abrirZip(blob(z));
  assert.match(l[0].recusado, /termina com 50 bytes, e o zip declara 60/);
});

test('armazenado com tamanho comprimido diferente do original, e dados que passam do fim do arquivo: cada um com o seu motivo', async () => {
  const z = Buffer.from(await gerarZip([E('a.txt', 'x'.repeat(50))], { deflate: false }));
  const cd = z.indexOf(Buffer.from([0x50, 0x4b, 0x01, 0x02]));
  const diferente = Buffer.from(z);
  diferente.writeUInt32LE(40, cd + 24);
  assert.match((await abrirZip(blob(diferente)))[0].recusado, /sem compressão com tamanhos diferentes/);
  const passa = Buffer.from(z);
  passa.writeUInt32LE(10 * 1024 * 1024, cd + 24);
  passa.writeUInt32LE(10 * 1024 * 1024, cd + 20);
  assert.match((await abrirZip(blob(passa)))[0].recusado, /passam do fim do arquivo/);
});

test('CRC-32 errado é recusado, mesmo sem compressão (nenhum outro portão pega um byte trocado)', async () => {
  const l = await abrirZip(blob(await gerarZip([E('a.xml', gerarXmlFiscal('nfe'), { crcErrado: true }), E('b.xml', gerarXmlFiscal('nfe'))], { deflate: false })));
  assert.match(doNome(l, 'a.xml').recusado, /CRC-32/);
  assert.ok(doNome(l, 'b.xml').buf);
});

test('zip sobreposto, zip dentro de zip, cifrado e método desconhecido: cada um com o seu motivo', async () => {
  const nota = gerarXmlFiscal('nfe');
  const sobre = await abrirZip(blob(await gerarZip([E('a.xml', nota)], { sobrepor: true })));
  assert.equal(sobre.length, 2);
  assert.ok(sobre[0].buf);
  assert.match(sobre[1].recusado, /sobreposto/);
  const dentro = await gerarZip([E('a.txt', 'x')]);
  const aninhado = await abrirZip(blob(await gerarZip([E('interno.zip', dentro), E('ok.xml', nota)])));
  assert.match(doNome(aninhado, 'interno.zip').recusado, /zip dentro de zip/);
  assert.ok(doNome(aninhado, 'ok.xml').buf);
  assert.match((await abrirZip(blob(await gerarZip([E('s.xml', nota, { cifrado: true })]))))[0].recusado, /cifrada/);
  assert.match((await abrirZip(blob(await gerarZip([E('b.xml', nota, { metodo: 12 })]))))[0].recusado, /método de compressão 12/);
});

test('planilha (xlsx) dentro do zip NÃO é "zip dentro de zip": ela segue como entrada normal', async () => {
  // Um xlsx é um zip com `xl/` nos nomes: `saborDoZip` o separa do zip comum.
  const xlsx = await gerarZip([E('[Content_Types].xml', '<Types spreadsheetml/>'), E('xl/workbook.xml', '<workbook/>')]);
  const l = await abrirZip(blob(await gerarZip([E('contas-a-receber.xlsx', xlsx)])));
  assert.equal(l.length, 1);
  assert.ok(l[0].buf?.length > 0, `${l[0].recusado}`);
});

test('zip truncado, vazio e em vários volumes: recusados com motivo', async () => {
  const z = await gerarZip([E('a.xml', gerarXmlFiscal('nfe'))]);
  assert.match((await abrirZip(blob(z.subarray(0, z.length - 30))))[0].recusado, /diretório central não encontrado|corrompido|fora do arquivo/);
  assert.match((await abrirZip(blob(z.subarray(0, 40))))[0].recusado, /truncado/);
  assert.match((await abrirZip(blob(Buffer.alloc(0))))[0].recusado, /truncado/);
  const volumes = Buffer.from(z);
  volumes.writeUInt16LE(1, volumes.length - 22 + 4); // número do disco
  assert.match((await abrirZip(blob(volumes)))[0].recusado, /vários volumes/);
  // Diretório que aponta para fora do arquivo: o corte no meio dos dados mantém o EOCD, mas não o que ele aponta.
  const cortado = Buffer.concat([z.subarray(0, 10), z.subarray(z.length - 22)]);
  assert.match((await abrirZip(blob(cortado)))[0].recusado, /diretório central fora do arquivo/);
});

test('entrada estragada no MEIO dos dados: o resto do pacote segue e ela é recusada', async () => {
  const cru = Buffer.alloc(30000);
  for (let i = 0; i < cru.length; i++) cru[i] = (i * 7919) & 0xff;
  const z = Buffer.from(await gerarZip([E('a.bin', cru), E('b.xml', gerarXmlFiscal('nfe'))]));
  const ini = 30 + 'a.bin'.length + 100;
  z.fill(0xff, ini, ini + 200); // estraga o deflate no meio da primeira entrada
  const l = await abrirZip(blob(z));
  assert.equal(l.length, 2);
  assert.match(doNome(l, 'a.bin').recusado, /corrompido|CRC|termina com|tamanho/);
  assert.ok(doNome(l, 'b.xml').buf);
});

test('os limites cobram, cada um com o seu motivo: entradas, tamanho por entrada, total e diretório', async () => {
  const nota = gerarXmlFiscal('nfe');
  const z = await gerarZip([E('a.xml', nota), E('b.xml', nota), E('c.xml', nota)]);
  const B = { ...LIMITES };
  assert.match((await abrirZip(blob(z), { ...B, entradas: 2 }))[0].recusado, /3 entradas, acima do limite de 2/);
  assert.match((await abrirZip(blob(z), { ...B, bytesPorEntrada: 100 }))[0].recusado, /acima do limite por entrada/);
  const total = await abrirZip(blob(z), { ...B, bytesTotal: 2 * nota.length + 10 });
  assert.equal(total.filter((e) => e.buf).length, 2);
  assert.match(total.find((e) => e.recusado).recusado, /limite total descompactado.*mais de um zip/);
  assert.match((await abrirZip(blob(z), { ...B, bytesDiretorio: 50 }))[0].recusado, /diretório central de \d+ bytes/);
});

test('a entrada oficial lida em fluxo do zip dá o MESMO envelope que o arquivo avulso (hash incluído)', async () => {
  const sped = gerarSped('ECD');
  const avulso = await lerEnvelopeDeFluxo(blob(sped).stream(), { resumir: true });
  let n = 0;
  for await (const e of entradasDoZip(blob(await gerarZip([E('ecd.txt', sped)])))) {
    n++;
    const dentro = await lerEnvelopeDeFluxo(e.fluxo(), { resumir: true });
    assert.ok(dentro.envelope.hash_sha256);
    assert.deepEqual(dentro.envelope, avulso.envelope);
    assert.deepEqual(dentro.resumo, avulso.resumo);
  }
  assert.equal(n, 1);
});

test('lerCabeca devolve no máximo n bytes e aceita fluxo menor que n', async () => {
  const s = () => blob(Buffer.from('0123456789')).stream();
  assert.equal(Buffer.from(await lerCabeca(s(), 4)).toString(), '0123');
  assert.equal(Buffer.from(await lerCabeca(s(), 100)).toString(), '0123456789');
});
