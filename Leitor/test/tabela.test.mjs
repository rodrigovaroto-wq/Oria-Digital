// O LEITOR TABULAR (MB1): CSV e XLSX em fluxo, toda linha com destino.
//
// Duas partes:
//   1. Contra as bases sintéticas de `Dados de Teste/volume` (geradas aqui, 3.000 linhas):
//      o que o leitor conta e soma tem de bater com o GABARITO, que o `conferir_volume.py`
//      prova contra o book-distress. O .xlsx tem de dizer, linha a linha, o mesmo que o CSV.
//   2. Os casos de formato que o sintético não tem e um arquivo real traz: cada um é um
//      jeito de o leitor errar SEM erro (acento trocado, coluna deslocada, data 4 anos fora).
//
// Sem python3 a parte 1 REPROVA (não pula): estágio que não rodou não pode parecer limpo.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, openAsBlob, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { lerTabela, celulasDoCsv, codificacaoDe } from '../lib/tabela.mjs';
import { crc32Atualizar } from '../lib/zip.mjs';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const N = 3000;

// ------------------------------------------------------------------ apoio --
function centavosBR(s) {
  assert.match(s, /^\d{1,3}(\.\d{3})*,\d{2}$/, `valor BR fora do formato: ${s}`);
  return BigInt(s.replace(/\./g, '').replace(',', ''));
}
function centavosXml(s) {
  assert.match(s, /^\d+\.\d{2}$/, `número do XLSX fora do formato: ${s}`);
  return BigInt(s.replace('.', ''));
}
function isoParaBR(s) { return s ? `${s.slice(8, 10)}/${s.slice(5, 7)}/${s.slice(0, 4)}` : ''; }

async function ler(blob) {
  const linhas = [];
  const resumo = await lerTabela(blob, { aoLinha: (l) => { if (l.reinicio) linhas.length = 0; else linhas.push(l); } });
  return { resumo, linhas };
}

/** Um Blob cujo fluxo entrega EXATAMENTE as fatias dadas (para cortar \r\n e UTF-8 ao meio). */
function blobEmFatias(fatias) {
  const tudo = new Uint8Array(fatias.reduce((n, f) => n + f.length, 0));
  let o = 0;
  for (const f of fatias) { tudo.set(f, o); o += f.length; }
  return {
    size: tudo.length,
    slice: (a, b) => new Blob([tudo.slice(a, b)]),
    stream: () => new ReadableStream({ start(c) { for (const f of fatias) c.enqueue(f); c.close(); } }),
  };
}

const cp = (s) => Uint8Array.from(Buffer.from(s, 'latin1')); // os testes escrevem só latin1 + bytes à mão

/** Um .xlsx mínimo, sem compressão, montado aqui: as partes que cada caso quer variar. */
function xlsx(partes) {
  const base = {
    '[Content_Types].xml': '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>',
    'xl/_rels/workbook.xml.rels': '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Target="worksheets/sheet2.xml"/></Relationships>',
    ...partes,
  };
  const enc = new TextEncoder();
  const locais = [], central = [];
  let off = 0;
  for (const [nome, texto] of Object.entries(base)) {
    const n = enc.encode(nome), d = enc.encode(texto);
    const crc = (crc32Atualizar(0xffffffff, d) ^ 0xffffffff) >>> 0;
    const h = new DataView(new ArrayBuffer(30));
    h.setUint32(0, 0x04034b50, true); h.setUint16(4, 20, true); h.setUint32(14, crc, true);
    h.setUint32(18, d.length, true); h.setUint32(22, d.length, true); h.setUint16(26, n.length, true);
    const c = new DataView(new ArrayBuffer(46));
    c.setUint32(0, 0x02014b50, true); c.setUint16(4, 20, true); c.setUint16(6, 20, true); c.setUint32(16, crc, true);
    c.setUint32(20, d.length, true); c.setUint32(24, d.length, true); c.setUint16(28, n.length, true); c.setUint32(42, off, true);
    locais.push(new Uint8Array(h.buffer), n, d);
    central.push(new Uint8Array(c.buffer), n);
    off += 30 + n.length + d.length;
  }
  const tamCentral = central.reduce((s, x) => s + x.length, 0);
  const e = new DataView(new ArrayBuffer(22));
  e.setUint32(0, 0x06054b50, true); e.setUint16(8, Object.keys(base).length, true); e.setUint16(10, Object.keys(base).length, true);
  e.setUint32(12, tamCentral, true); e.setUint32(16, off, true);
  return new Blob([...locais, ...central, new Uint8Array(e.buffer)]);
}
const WB = (extra = '', abas = '<sheet name="Plan1" sheetId="1" r:id="rId1"/>') =>
  `<workbook xmlns:r="r">${extra}<sheets>${abas}</sheets></workbook>`;
const FOLHA = (linhas) => `<worksheet><sheetData>${linhas}</sheetData></worksheet>`;
const CAB = '<row r="1"><c r="A1" t="inlineStr"><is><t>Cliente</t></is></c><c r="B1" t="inlineStr"><is><t>Vencimento</t></is></c><c r="C1" t="inlineStr"><is><t>Saldo</t></is></c></row>';

// ============================================== 1. contra os sintéticos =====
const dir = mkdtempSync(join(tmpdir(), 'tabela-'));
const gerado = spawnSync('python3', [join(RAIZ, 'Dados de Teste/volume/gerar_volume.py'), '--linhas', String(N), '--saida', dir], { encoding: 'utf8' });
const gab = gerado.status === 0 ? JSON.parse(readFileSync(join(dir, `GABARITO_${N}.json`), 'utf8')) : null;
process.on('exit', () => rmSync(dir, { recursive: true, force: true }));

const DESTINO_DO_GABARITO = { cabecalho_relatorio: 'antes_do_cabecalho', em_branco: 'em_branco', cabecalho_colunas: 'cabecalho', titulo: 'dado', total: 'total' };

test('o gerador das bases sintéticas rodou (sem ele a parte 1 não prova nada)', () => {
  assert.equal(gerado.status, 0, `python3 gerar_volume.py falhou: ${gerado.stderr || gerado.error}`);
});

for (const [chave, arquivo] of [['contas_a_receber', `contas_a_receber_${N}.csv`], ['contas_a_pagar', `contas_a_pagar_${N}.csv`]]) {
  test(`${arquivo}: toda linha com destino, as contagens e o saldo do gabarito`, { skip: !gab && 'sem gabarito' }, async () => {
    const caminho = join(dir, arquivo);
    const { resumo, linhas } = await ler(await openAsBlob(caminho));
    const g = gab[chave];
    assert.equal(resumo.formato, 'csv');
    assert.equal(resumo.codificacao, 'windows-1252');
    assert.equal(resumo.separador, ';');
    assert.equal(resumo.linhas_fisicas, g.csv.linhas_arquivo);
    assert.equal(resumo.linhas, g.csv.linhas_arquivo);
    assert.equal(Object.values(resumo.por_destino).reduce((a, b) => a + b, 0), resumo.linhas);
    const esperado = Object.fromEntries(Object.entries(g.linhas_por_destino).map(([k, v]) => [DESTINO_DO_GABARITO[k], v]));
    for (const [d, v] of Object.entries(resumo.por_destino)) assert.equal(v, esperado[d] ?? 0, `destino ${d}`);
    assert.equal(resumo.bytes, g.csv.bytes);
    assert.equal(resumo.sha256, createHash('sha256').update(readFileSync(caminho)).digest('hex'));
    // O VALOR lido: Σ da coluna Saldo das linhas de dado = o saldo em aberto do gabarito.
    const iSaldo = resumo.cabecalho.celulas.indexOf('Saldo');
    assert.ok(iSaldo >= 0, 'cabeçalho sem a coluna Saldo');
    const dados = linhas.filter((l) => l.destino === 'dado');
    assert.equal(dados.reduce((s, l) => s + centavosBR(l.celulas[iSaldo]), 0n), BigInt(g.saldo_em_aberto_centavos));
    assert.equal(new Set(dados.map((l) => l.celulas[0])).size, g.contrapartes_no_arquivo);
    assert.equal(resumo.amostra.length, 30);
  });
}

test('contas_a_receber .csv: o acento do cp1252 sai certo (Ç, Ã, Ú)', { skip: !gab && 'sem gabarito' }, async () => {
  const { linhas } = await ler(await openAsBlob(join(dir, `contas_a_receber_${N}.csv`)));
  assert.ok(linhas.some((l) => l.celulas[1] === 'CONSTRUTORA ALTO PARAOPEBA LTDA. (EM RECUPERAÇÃO JUDICIAL)'));
  assert.equal(linhas[0].celulas[0].slice(0, 12), 'RELATÓRIO DE');
});

test('contas_a_receber .xlsx: diz, linha a linha, o mesmo que o .csv', { skip: !gab && 'sem gabarito' }, async () => {
  const csv = await ler(await openAsBlob(join(dir, `contas_a_receber_${N}.csv`)));
  const xl = await ler(await openAsBlob(join(dir, `contas_a_receber_${N}.xlsx`)));
  assert.equal(xl.resumo.formato, 'xlsx');
  assert.deepEqual(xl.resumo.por_destino, csv.resumo.por_destino);
  assert.deepEqual(xl.resumo.cabecalho, csv.resumo.cabecalho);
  assert.equal(xl.resumo.linhas_ausentes_no_xml, 1, 'a linha 3 em branco não está no XML e tem de ser contada');
  assert.equal(xl.resumo.strings_compartilhadas, gab.contas_a_receber.xlsx.strings_unicas);
  const dc = csv.linhas.filter((l) => l.destino === 'dado'), dx = xl.linhas.filter((l) => l.destino === 'dado');
  assert.equal(dx.length, dc.length);
  for (let i = 0; i < dc.length; i++) {
    const c = dc[i].celulas, x = dx[i].celulas, t = dx[i].tipos;
    assert.deepEqual([x[0], x[1], x[2], x[3], x[4], x[11]], [c[0], c[1], c[2], c[3], c[4], c[11]], `linha ${dc[i].n}: texto`);
    assert.deepEqual([isoParaBR(x[5]), isoParaBR(x[6]), isoParaBR(x[10] || '')], [c[5], c[6], c[10]], `linha ${dc[i].n}: datas`);
    assert.deepEqual([t[5], t[6], t[7]], ['d', 'd', 'n'], `linha ${dc[i].n}: tipos`);
    assert.deepEqual([7, 8, 9].map((k) => centavosXml(x[k])), [7, 8, 9].map((k) => centavosBR(c[k])), `linha ${dc[i].n}: valores`);
  }
});

// ================================================== 2. casos de formato =====
test('cp1252: 0x96 vira "–" e 0xC7 vira "Ç" no Node como no navegador', async () => {
  const b = cp('Nome;Valor;Obs\r\nA;1;x\r\n');
  const bytes = new Uint8Array([...b, ...cp('JO'), 0xc3, ...cp('O '), 0x96, ...cp(' A;2;'), 0xc7, 0x0d, 0x0a]);
  const { resumo, linhas } = await ler(new Blob([bytes]));
  assert.equal(resumo.codificacao, 'windows-1252');
  assert.equal(linhas[2].celulas[0], 'JOÃO – A');
  assert.equal(linhas[2].celulas[2], 'Ç');
});

test('UTF-8 com BOM: o BOM não entra na primeira célula', async () => {
  const { resumo, linhas } = await ler(new Blob(['﻿Código;Nome;Saldo\n1;JOSÉ;10,00\n']));
  assert.equal(resumo.codificacao, 'utf-8');
  assert.equal(linhas[0].celulas[0], 'Código');
  assert.equal(linhas[1].celulas[1], 'JOSÉ');
});

test('UTF-8 sem BOM é reconhecido pelos bytes', async () => {
  assert.equal(codificacaoDe(new TextEncoder().encode('Ação;Preço')).codificacao, 'utf-8');
  assert.equal(codificacaoDe(cp('A\xe7\xe3o;Pre\xe7o')).codificacao, 'windows-1252');
});

test('64 KB de ASCII e um byte cp1252 depois: relê como windows-1252, avisa e zera quem agrega', async () => {
  const linha = 'Codigo;Nome;Saldo\r\n';
  const corpo = Array.from({ length: 5000 }, (_, i) => `${i};CLIENTE ${i};1,00\r\n`).join('');
  const bytes = new Uint8Array([...cp(linha + corpo), ...cp('9;JO'), 0xc3, ...cp('O;2,00\r\n')]);
  let reinicios = 0;
  const linhas = [];
  const resumo = await lerTabela(new Blob([bytes]), { aoLinha: (l) => { if (l.reinicio) { reinicios++; linhas.length = 0; } else linhas.push(l); } });
  assert.equal(resumo.codificacao, 'windows-1252');
  assert.equal(reinicios, 1);
  assert.equal(linhas.length, 5002, 'cada linha uma vez só, depois do reinício');
  assert.equal(linhas.at(-1).celulas[1], 'JOÃO');
  assert.ok(resumo.avisos.some((a) => a.includes('relido como windows-1252')));
});

test('aspas: separador e quebra de linha dentro da célula são UMA célula', async () => {
  const resto = Array.from({ length: 10 }, (_, i) => `C${i};CIDADE;1,00\n`).join('');
  const { resumo, linhas } = await ler(new Blob([`Nome;Cidade;Saldo\n"SILVA; JOÃO";"SÃO\nPAULO";10,00\n${resto}`]));
  assert.deepEqual(linhas[1].celulas, ['SILVA; JOÃO', 'SÃO\nPAULO', '10,00']);
  assert.equal(resumo.linhas, 12);
  assert.equal(resumo.linhas_fisicas, 13);
  assert.equal(resumo.por_destino.dado, 11);
  assert.deepEqual(celulasDoCsv('a;"b""c";d', ';'), ['a', 'b"c', 'd']);
});

test('separador sem aspas dentro do nome: largura divergente, nunca dado com a coluna deslocada', async () => {
  const { resumo, linhas } = await ler(new Blob(['Nome;Vencimento;Saldo\nA;01/01/2025;1,00\nSILVA; JOAO;01/01/2025;2,00\nB;02/01/2025;3,00\n']));
  assert.equal(resumo.por_destino.largura_divergente, 1);
  assert.equal(resumo.por_destino.dado, 2);
  assert.equal(linhas[2].destino, 'largura_divergente');
});

test('total × cliente chamado TOTAL: o total tem poucas células, o cliente tem a linha cheia', async () => {
  const { linhas } = await ler(new Blob(['Nome;Vencimento;Valor;Saldo\nTOTAL DISTRIBUIDORA LTDA;01/01/2025;5,00;5,00\nTOTAL GERAL;;;5,00\n']));
  assert.deepEqual(linhas.map((l) => l.destino), ['cabecalho', 'dado', 'total']);
});

test('sem cabeçalho: nada vira dado, e o resumo diz por quê', async () => {
  const { resumo } = await ler(new Blob(['1;2;3\n4;5;6\n7;8;9\n']));
  assert.equal(resumo.cabecalho, null);
  assert.equal(resumo.por_destino.dado, 0);
  assert.equal(resumo.por_destino.fora_da_tabela, 3);
  assert.match(resumo.sem_cabecalho, /nenhuma linha de cabeçalho/);
});

test('fatias: \\r\\n e caractere UTF-8 cortados ao meio não criam linha nem trocam letra', async () => {
  const t = new TextEncoder().encode('Nome;Cidade;Saldo\r\nJOSÉ;SÃO PAULO;1,00\r\nB;C;2,00');
  const meio = t.indexOf(0x0a) ; // corta entre \r e \n
  const e = [...t].indexOf(0xc3); // corta dentro do "É"
  const { resumo, linhas } = await ler(blobEmFatias([t.slice(0, meio), t.slice(meio, e + 1), t.slice(e + 1)]));
  assert.equal(resumo.linhas, 3, 'sem linha em branco fantasma e com a última linha sem quebra no fim');
  assert.equal(resumo.por_destino.em_branco, 0);
  assert.equal(linhas[1].celulas[0], 'JOSÉ');
});

test('UTF-16LE com BOM ("Texto Unicode" do Excel), separado por tab', async () => {
  const s = '﻿Nome\tVencimento\tSaldo\r\nJOSÉ\t01/01/2025\t1,00\r\n';
  const b = new Uint8Array(s.length * 2);
  for (let i = 0; i < s.length; i++) { b[2 * i] = s.charCodeAt(i) & 0xff; b[2 * i + 1] = s.charCodeAt(i) >> 8; }
  const { resumo, linhas } = await ler(new Blob([b]));
  assert.equal(resumo.codificacao, 'utf-16le');
  assert.equal(resumo.separador, '\t');
  assert.equal(linhas[1].celulas[0], 'JOSÉ');
});

test('xlsx: sharedStrings com texto rico e leitura fonética, entidade e célula sem r', async () => {
  const blob = xlsx({
    'xl/workbook.xml': WB(),
    'xl/sharedStrings.xml': '<sst><si><t>Cliente</t></si><si><r><t>A &amp; </t></r><r><t>B</t></r><rPh><t>ei</t></rPh></si></sst>',
    'xl/worksheets/sheet1.xml': FOLHA(`${CAB}<row r="2"><c t="s"><v>1</v></c><c><v>45000</v></c><c><v>10.5</v></c></row>`),
  });
  const { resumo, linhas } = await ler(blob);
  assert.deepEqual(linhas[1].celulas, ['A & B', '45000', '10.5']);
  assert.deepEqual(linhas[1].tipos, ['s', 'n', 'n']);
  assert.equal(resumo.por_destino.dado, 1);
});

test('xlsx: data por formato embutido (14) e por formato próprio dd/mm/aaaa; número continua número', async () => {
  const blob = xlsx({
    'xl/workbook.xml': WB(),
    'xl/styles.xml': '<styleSheet><numFmts><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/><numFmt numFmtId="165" formatCode="#,##0.00 &quot;dias&quot;"/></numFmts><cellXfs><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="164"/><xf numFmtId="165"/></cellXfs></styleSheet>',
    'xl/worksheets/sheet1.xml': FOLHA(`${CAB}<row r="2"><c r="A2" s="1"><v>46022</v></c><c r="B2" s="2"><v>46023</v></c><c r="C2" s="3"><v>12</v></c></row>`),
  });
  const { linhas } = await ler(blob);
  assert.deepEqual(linhas[1].celulas, ['2025-12-31', '2026-01-01', '12']);
  assert.deepEqual(linhas[1].tipos, ['d', 'd', 'n']);
});

test('xlsx: calendário de 1904 (Mac) não desloca a data em 4 anos', async () => {
  const blob = xlsx({
    'xl/workbook.xml': WB('<workbookPr date1904="1"/>'),
    'xl/styles.xml': '<styleSheet><cellXfs><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs></styleSheet>',
    'xl/worksheets/sheet1.xml': FOLHA(`${CAB}<row r="2"><c r="A2" t="inlineStr"><is><t>X</t></is></c><c r="B2" s="1"><v>44560</v></c><c r="C2"><v>1</v></c></row>`),
  });
  const { resumo, linhas } = await ler(blob);
  assert.equal(resumo.data_1904, true);
  assert.equal(linhas[1].celulas[1], '2025-12-31');
});

test('xlsx: lê a primeira aba VISÍVEL e diz quais não leu', async () => {
  const blob = xlsx({
    'xl/workbook.xml': WB('', '<sheet name="Oculta" sheetId="1" state="hidden" r:id="rId1"/><sheet name="Títulos" sheetId="2" r:id="rId2"/>'),
    'xl/worksheets/sheet1.xml': FOLHA('<row r="1"><c r="A1" t="inlineStr"><is><t>lixo</t></is></c></row>'),
    'xl/worksheets/sheet2.xml': FOLHA(`${CAB}<row r="2"><c r="A2" t="inlineStr"><is><t>X</t></is></c><c r="B2"><v>1</v></c><c r="C2"><v>2</v></c></row>`),
  });
  const { resumo } = await ler(blob);
  assert.equal(resumo.aba, 'Títulos');
  assert.ok(resumo.avisos.some((a) => a.includes('"Oculta"')));
  assert.ok(resumo.avisos.some((a) => a.includes('texto em linha')));
});

test('xlsx: linha ausente do XML é linha em branco contada, não linha que some', async () => {
  const blob = xlsx({
    'xl/workbook.xml': WB(),
    'xl/worksheets/sheet1.xml': FOLHA(`${CAB}<row r="5"><c r="A5" t="inlineStr"><is><t>X</t></is></c><c r="B5"><v>1</v></c><c r="C5"><v>2</v></c></row>`),
  });
  const { resumo, linhas } = await ler(blob);
  assert.equal(resumo.linhas, 5);
  assert.equal(resumo.linhas_ausentes_no_xml, 3);
  assert.equal(resumo.por_destino.em_branco, 3);
  assert.equal(linhas.at(-1).n, 4);
});

test('nem CSV nem XLSX: erro que diz o formato, nunca tabela vazia', async () => {
  await assert.rejects(lerTabela(new Blob([new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31])])), /não é CSV nem XLSX/);
  await assert.rejects(lerTabela(new Blob(['um contrato\nsem tabela nenhuma\n'])), /não é uma tabela delimitada/);
});
