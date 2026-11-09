// O XLSX LIDO ABA POR ABA (09/11/2026). O `Extract From File` sem `sheetName` lia SO a primeira
// aba; as outras sumiam. Aqui roda o CODIGO REAL dos nos novos (`Copiar Como ZIP`, `Expandir
// Abas`), do `Agrupar Linhas XLSX` e do `Recompor Conteudo Extraido`, encadeados como o n8n os
// encadeia, sobre .xlsx de verdade.
//
// O QUE NAO E' REAL AQUI, declarado (regra 4): os dois nos NATIVOS (`Ler Abas do XLSX` =
// Compression e `Extrair XLSX` = Extract From File) nao rodam fora do n8n, entao ha um
// EMULADOR de cada um (jszip e exceljs, que ja estao no lock do portal). Eles seguem o fonte
// de n8n-nodes-base 2.46.6 (Compression: so aceita fileExtension zip/gz/tar, devolve uma
// entrada por binario, um item por entrada mesmo em erro; Extract From File: `sheetName` vazio
// = 1a aba, aba inexistente = item {error}, aba sem linha = nenhum item), mas emulador nao e'
// o no': o que SO se prova depois de republicar esta na lista do relatorio da fatia.
//
// Os .xlsx de `Dados de Teste/book-espelho/pdf/` sao gerados por `gerar.py` e ficam fora do git;
// quando nao existem o teste PULA dizendo o porque (o CI de hoje nao gera o book-espelho).
// Os demais usam workbooks escritos pelo exceljs (biblioteca real, nao zip montado a mao): o
// que provam e' o PAREAMENTO e as pendencias, que nao dependem de ser planilha de cliente.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const AQUI = dirname(fileURLToPath(import.meta.url));
const requirePortal = createRequire(resolve(AQUI, '../../portal/package.json'));
const ExcelJS = requirePortal('exceljs');
const JSZip = requirePortal('jszip');

const wf = JSON.parse(readFileSync(new URL('../workflow.e1-ingestao.json', import.meta.url)));
const byName = Object.fromEntries(wf.nodes.map((n) => [n.name, n]));
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;

// --- o executor de nos Code (mesmo contrato do `run` de workflow-sim.test.mjs) ------------
function executar(name, { item, items, refs = {}, itemIndex = 0, binaryStore } = {}) {
  const $input = { item, first: () => (items ? items[0] : item), all: () => items || (item ? [item] : []) };
  const $ = (ref) => {
    if (!(ref in refs)) throw new Error(`Referência não mockada: $('${ref}') — "${name}" depende dela`);
    const lista = refs[ref];
    return { all: () => lista, itemMatching: (i) => lista[i], first: () => lista[0] };
  };
  const helpers = {
    getBinaryDataBuffer: async (idx, prop) => {
      const fonte = (binaryStore || [item])[idx];
      return Buffer.from(((fonte && fonte.binary && fonte.binary[prop]) || {}).data || '', 'base64');
    },
  };
  const fn = new AsyncFunction('$input', '$', '$json', '$itemIndex', 'Buffer', byName[name].parameters.jsCode);
  return fn.call({ helpers }, $input, $, item ? item.json : undefined, itemIndex, Buffer);
}

// --- emulador do nó nativo Compression (decompress) ---------------------------------------
// `fileNameEmBinario`: como o fileName de cada entrada fica no binario. O fonte do
// `prepareBinaryData` esta no n8n-core (fora do repositorio): o no Expandir aceita as duas
// formas, e o teste as exerce.
async function emularCompression(item, i, fileNameEmBinario = (n) => n.split('/').pop()) {
  const bin = item.binary?.zip;
  if (!bin?.fileExtension || bin.fileExtension.toLowerCase() !== 'zip') {
    return { json: { error: `Unsupported archive format ".${bin?.fileExtension}" for binary data zip` }, pairedItem: { item: i } };
  }
  const z = await JSZip.loadAsync(Buffer.from(bin.data, 'base64'));
  const binary = {};
  let n = 0;
  for (const nome of Object.keys(z.files)) {
    if (z.files[nome].dir) continue;
    const dados = await z.files[nome].async('nodebuffer');
    binary[`file_${n++}`] = { fileName: fileNameEmBinario(nome), data: dados.toString('base64'), mimeType: 'application/octet-stream' };
  }
  return { json: item.json, binary, pairedItem: { item: i } };
}

// --- emulador do nó nativo Extract From File (xlsx) ---------------------------------------
const texto = (v) => {
  if (v === null || v === undefined) return null;
  if (typeof v === 'object') return v.result !== undefined ? String(v.result) : (v.text !== undefined ? String(v.text) : (v instanceof Date ? v.toISOString() : null));
  return String(v);
};
// Linha 1 = cabeçalho (chave = texto, ou __EMPTY_n), resto = uma linha por item, sem linha vazia.
function linhasDaAba(ws) {
  const matriz = [];
  ws.eachRow({ includeEmpty: false }, (row) => {
    const cel = [];
    row.eachCell({ includeEmpty: true }, (c, col) => { cel[col] = c.isMerged && c.master !== c ? null : texto(c.value); });
    matriz.push(cel);
  });
  if (matriz.length === 0) return { cabecalho: [], linhas: [] };
  const largura = Math.max(...matriz.map((m) => m.length));
  const cabecalho = Array.from({ length: largura }, (_, c) => matriz[0][c] ?? `__EMPTY_${c}`).slice(1);
  const linhas = matriz.slice(1).map((m) => Object.fromEntries(cabecalho.map((k, c) => [k, m[c + 1]]).filter(([, v]) => v !== null && v !== undefined)))
    .filter((o) => Object.keys(o).length > 0);
  return { cabecalho, linhas };
}
async function emularExtrator(item, j, { ignorarSheetName = false } = {}) {
  // A expressão é a REAL do nó, avaliada contra o item: um erro de digitação nela reprova aqui.
  const expr = byName['Extrair XLSX'].parameters.options.sheetName.replace(/^=\{\{/, '').replace(/\}\}$/, '');
  const sheetName = ignorarSheetName ? '' : new Function('$json', `return (${expr});`)(item.json);
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(Buffer.from(item.binary.data.data, 'base64'));
  const ws = sheetName ? wb.getWorksheet(sheetName) : wb.worksheets[0];
  if (!ws) return [{ json: { error: `Spreadsheet does not contain sheet called "${sheetName}"!` }, pairedItem: { item: j } }];
  return linhasDaAba(ws).linhas.map((json) => ({ json, pairedItem: { item: j } }));
}

// --- a cadeia: Preparar -> Copiar -> Compression -> Expandir -> Extrair -> Agrupar -> Recompor ----
const MIME_XLSX = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
async function cadeia(arquivos, { comprimir = emularCompression, extrator = emularExtrator, ctxCruzado = false } = {}) {
  const lote = arquivos.map((a) => ({
    json: { caso_id: 'caso-1', nome_original: a.nome, binary_key: 'data' },
    binary: { data: { fileName: a.nome, mimeType: MIME_XLSX, data: a.buf.toString('base64') } },
  }));
  const preps = [];
  for (let i = 0; i < lote.length; i += 1) preps.push(await executar('Preparar Conteudo', { item: lote[i], itemIndex: i, binaryStore: lote }));
  const copiados = [];
  for (let i = 0; i < preps.length; i += 1) copiados.push(await executar('Copiar Como ZIP', { item: preps[i], itemIndex: i }));
  const descomprimidos = [];
  for (let i = 0; i < copiados.length; i += 1) descomprimidos.push(await comprimir(copiados[i], i));
  const exp = await executar('Expandir Abas', { items: descomprimidos, refs: { 'Copiar Como ZIP': copiados }, binaryStore: descomprimidos });
  const rundata = [];
  for (let j = 0; j < exp.length; j += 1) rundata.push(...await extrator(exp[j], j));
  // o que o Code recebe: pairedItem = índice da própria entrada (o motor reescreve)
  const entradas = rundata.map((it, i) => ({ json: it.json, pairedItem: { item: i } }));
  // a cadeia do motor: linha -> item de aba (rundata do extrator) -> documento (pairedItem do Expandir)
  const docDaLinha = (i) => exp[rundata[i].pairedItem.item].pairedItem.item;
  let ctxPorLinha = entradas.map((_, i) => ({ json: preps[docDaLinha(i)].json }));
  if (ctxCruzado) ctxPorLinha = ctxPorLinha.map((_, i) => ({ json: preps[(docDaLinha(i) + 1) % preps.length].json }));
  const agrupados = await executar('Agrupar Linhas XLSX', {
    items: entradas, refs: { 'Extrair XLSX': rundata, 'Expandir Abas': exp, 'Preparar Conteudo': ctxPorLinha },
  });
  const ctxDoAgrupado = agrupados.map((it) => ({ json: preps[docDaLinha(it.pairedItem.item)].json }));
  const saida = await executar('Recompor Conteudo Extraido', { items: agrupados, refs: { 'Preparar Conteudo': ctxDoAgrupado } });
  return { preps, exp, agrupados, saida };
}
const doDocumento = (r, nome) => r.saida.find((s) => s.json.nome_original === nome)?.json;

// --- fábricas de workbook (exceljs de verdade) ---------------------------------------------
async function workbookDe(abas) {
  const wb = new ExcelJS.Workbook();
  for (const a of abas) {
    const ws = wb.addWorksheet(a.nome);
    if (a.oculta) ws.state = 'hidden';
    for (const l of a.linhas) ws.addRow(l);
  }
  return Buffer.from(await wb.xlsx.writeBuffer());
}
const linhasMarcadas = (marca, n) => [['Conta', 'Saldo'], ...Array.from({ length: n }, (_, k) => [`${marca}-${k}`, 100 + k])];

// =============================================================================================
// 1. OS .xlsx DO BOOK-ESPELHO: as duas abas chegam ao texto
// =============================================================================================
const PASTA_ESPELHO = resolve(AQUI, '../../Dados de Teste/book-espelho/pdf');
const REAIS = existsSync(PASTA_ESPELHO) ? readdirSync(PASTA_ESPELHO).filter((f) => f.endsWith('.xlsx')).sort() : [];

// A VERDADE vem do próprio arquivo, lido por outro caminho (exceljs): todo texto de célula das
// duas abas tem de estar no texto que vai à IA. Número fica de fora: o formato dele depende do
// extrator, e o que se mede aqui é "a aba foi lida", não "como o número foi escrito".
async function verdadeDoArquivo(buf) {
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(buf);
  return wb.worksheets.map((ws) => {
    const textos = new Set();
    ws.eachRow((row) => row.eachCell((c) => {
      if (c.isMerged && c.master !== c) return;
      const t = typeof c.value === 'string' ? c.value.trim() : '';
      if (t.length >= 3) textos.add(t);
    }));
    return { nome: ws.name, oculta: ws.state !== 'visible', textos: [...textos] };
  });
}

test('book-espelho: o book tem xlsx, e nenhum é de 1 aba só (senão este teste não prova nada)', { skip: REAIS.length === 0 && `sem ${PASTA_ESPELHO} — rode "Dados de Teste/book-espelho/gerar.py" (o CI de hoje não gera o book-espelho)` }, async () => {
  assert.equal(REAIS.length, 4, `esperava 4 planilhas no book-espelho, achei ${REAIS.length}`);
  for (const f of REAIS) assert.ok((await verdadeDoArquivo(readFileSync(resolve(PASTA_ESPELHO, f)))).length >= 2, `${f} tem menos de 2 abas`);
});

for (const f of REAIS) {
  test(`book-espelho: "${f}" — as duas abas são lidas, e nenhuma pendência de aba aberta`, async () => {
    const buf = readFileSync(resolve(PASTA_ESPELHO, f));
    const verdade = await verdadeDoArquivo(buf);
    const r = await cadeia([{ nome: f, buf }]);
    const doc = doDocumento(r, f);
    assert.ok(doc, 'o documento sumiu da cadeia');
    // os nomes das abas, NA ORDEM do workbook, são os do arquivo
    assert.deepEqual(doc.abas_lidas.map((a) => a.nome), verdade.map((a) => a.nome));
    assert.ok(doc.abas_lidas.every((a) => a.lida));
    for (const aba of verdade) {
      assert.ok(doc.text.includes(`=== ABA: ${aba.nome}`), `falta o cabeçalho da aba "${aba.nome}"`);
      const ausentes = aba.textos.filter((t) => !doc.text.includes(t));
      assert.deepEqual(ausentes, [], `texto da aba "${aba.nome}" ausente do que vai à IA`);
    }
    assert.ok(!/leu SO a primeira/.test(doc.aviso_conteudo || ''), `pendência de 1 aba aberta à toa: ${doc.aviso_conteudo}`);
    assert.equal(doc.content_part.text, doc.text, 'a IA recebe o mesmo texto que a régua mede');
  });

  test(`book-espelho: "${f}" — REGRA 2: lendo só a 1a aba (o defeito), a 2a some do texto e a pendência abre`, async () => {
    const buf = readFileSync(resolve(PASTA_ESPELHO, f));
    const verdade = await verdadeDoArquivo(buf);
    // o defeito, reproduzido: extrator sem sheetName e sem o nó de abas (um item, workbook ilegível)
    const r = await cadeia([{ nome: f, buf }], {
      comprimir: async (_it, i) => ({ json: { error: 'sem Compression' }, pairedItem: { item: i } }),
      extrator: (it, j) => emularExtrator(it, j, { ignorarSheetName: true }),
    });
    const doc = doDocumento(r, f);
    const daSegunda = verdade[1].textos.filter((t) => !verdade[0].textos.some((x) => x.includes(t)));
    assert.ok(daSegunda.length > 0 && daSegunda.every((t) => !doc.text.includes(t)), 'o controle positivo falhou: a 2a aba aparece mesmo lendo só a 1a');
    assert.match(doc.aviso_conteudo, /leu SO a primeira/, 'a pendência TEM de abrir quando as abas não foram lidas');
  });
}

// =============================================================================================
// 2. PAREAMENTO ITEM <-> DOCUMENTO: 3 planilhas no MESMO lote, com 1, 3 e 2 abas
// =============================================================================================
async function loteDeTres() {
  return [
    { nome: 'um.xlsx', buf: await workbookDe([{ nome: 'Unica', linhas: linhasMarcadas('UM-U', 4) }]) },
    { nome: 'tres.xlsx', buf: await workbookDe([
      { nome: 'Indice', linhas: [['Aba'], ['TRES-indice']] },
      { nome: 'Divida & Cia <2026>', linhas: linhasMarcadas('TRES-D', 5) },
      { nome: 'Premissas', oculta: true, linhas: linhasMarcadas('TRES-P', 3) },
    ]) },
    { nome: 'dois.xlsx', buf: await workbookDe([
      { nome: 'Posicao', linhas: linhasMarcadas('DOIS-P', 6) },
      { nome: 'Plan2', linhas: linhasMarcadas('DOIS-Q', 2) },
    ]) },
  ];
}
const MARCAS = { 'um.xlsx': 'UM-', 'tres.xlsx': 'TRES-', 'dois.xlsx': 'DOIS-' };

test('pareamento: 3 planilhas (1, 3 e 2 abas) no mesmo lote — cada aba cai no SEU documento, na ordem do workbook', async () => {
  const r = await cadeia(await loteDeTres());
  assert.equal(r.saida.length, 3, 'um item por documento, nunca um por aba');
  for (const [nome, marca] of Object.entries(MARCAS)) {
    const t = doDocumento(r, nome).text;
    const estranhas = Object.values(MARCAS).filter((m) => m !== marca).filter((m) => t.includes(m));
    assert.deepEqual(estranhas, [], `${nome} recebeu linhas de outro documento`);
    assert.ok(t.includes(marca), `${nome} ficou sem as próprias linhas`);
  }
  assert.deepEqual(doDocumento(r, 'um.xlsx').abas_lidas.map((a) => a.nome), ['Unica']);
  assert.deepEqual(doDocumento(r, 'tres.xlsx').abas_lidas.map((a) => a.nome), ['Indice', 'Divida & Cia <2026>', 'Premissas']);
  assert.deepEqual(doDocumento(r, 'dois.xlsx').abas_lidas.map((a) => a.nome), ['Posicao', 'Plan2']);
  // por aba: as linhas da aba certa sob o cabeçalho certo
  const t3 = doDocumento(r, 'tres.xlsx').text;
  assert.ok(t3.indexOf('=== ABA: Divida & Cia <2026> ===') < t3.indexOf('TRES-D-4'));
  assert.ok(t3.indexOf('TRES-D-4') < t3.indexOf('=== ABA: Premissas (oculta) ==='), 'oculta marcada, na ordem, e LIDA');
  assert.ok(t3.includes('TRES-P-2'), 'a aba oculta foi lida');
  // 1 aba só: texto como sempre foi, sem cabeçalho
  assert.ok(!doDocumento(r, 'um.xlsx').text.includes('=== ABA'));
  for (const nome of Object.keys(MARCAS)) assert.equal(doDocumento(r, nome).aviso_conteudo, null, `${nome}: nenhuma pendência esperada`);
});

test('pareamento: o fileName do workbook no binário pode ser "workbook.xml" ou "xl/workbook.xml"', async () => {
  for (const forma of [(n) => n.split('/').pop(), (n) => n]) {
    const r = await cadeia(await loteDeTres(), { comprimir: (it, i) => emularCompression(it, i, forma) });
    assert.deepEqual(doDocumento(r, 'tres.xlsx').abas_lidas.map((a) => a.nome), ['Indice', 'Divida & Cia <2026>', 'Premissas']);
  }
});

test('pareamento: contexto trocado entre documentos PARA a execução (nunca grava a tabela sob o nome do vizinho)', async () => {
  await assert.rejects(async () => cadeia(await loteDeTres(), { ctxCruzado: true }), /pareamento aba\/documento quebrado/);
});

test('Expandir Abas: tamanho diferente entre o original e a descompressão PARA a execução', async () => {
  const lote = await loteDeTres();
  const prep = lote.map((a) => ({ json: { nome_original: a.nome, hash: a.nome }, binary: { data: { data: a.buf.toString('base64') } } }));
  await assert.rejects(
    () => executar('Expandir Abas', { items: [{ json: {}, binary: {} }], refs: { 'Copiar Como ZIP': prep } }),
    /nao da para parear cada planilha ao seu original/,
  );
});

// =============================================================================================
// 3. NUNCA SILENCIO: workbook ilegível, aba com erro, aba vazia, teto por aba
// =============================================================================================
test('workbook ilegível (descompressão recusada): cai em 1 aba e a pendência "leu SO a primeira" ABRE, com o motivo', async () => {
  const arq = (await loteDeTres())[1];
  const r = await cadeia([arq], { comprimir: async (_it, i) => ({ json: { error: 'Decompressed size exceeds limit' }, pairedItem: { item: i } }) });
  const doc = doDocumento(r, 'tres.xlsx');
  assert.equal(r.exp.length, 1, 'um item só, sem sheetName');
  assert.equal(r.exp[0].json.abas_nomes_lidos, false);
  assert.match(doc.text, /TRES-indice/, 'o que a 1a aba tem continua chegando');
  assert.ok(!doc.text.includes('TRES-D-'), 'a 2a aba NAO foi lida');
  assert.match(doc.aviso_conteudo, /tem 3 abas e o extrator nativo leu SO a primeira/);
  assert.match(doc.aviso_conteudo, /a leitura dele falhou: a descompressao falhou: Decompressed size exceeds limit/);
  assert.equal(doc.abas_lidas, null, 'ausência, não lista vazia');
});

test('workbook sem xl/workbook.xml legível: mesmo fallback, motivo diferente', async () => {
  const arq = (await loteDeTres())[2];
  const semWorkbook = async (it, i) => {
    const d = await emularCompression(it, i);
    for (const k of Object.keys(d.binary)) if (d.binary[k].fileName === 'workbook.xml') delete d.binary[k];
    return d;
  };
  const r = await cadeia([arq], { comprimir: semWorkbook });
  assert.match(doDocumento(r, 'dois.xlsx').aviso_conteudo, /xl\/workbook\.xml nao veio da descompressao/);
});

test('aba que o extrator recusa: as outras seguem, e a pendência NOMEIA a aba que não foi lida', async () => {
  const arq = (await loteDeTres())[2];
  const r = await cadeia([arq], {
    extrator: async (it, j) => (it.json.aba_nome === 'Plan2'
      ? [{ json: { error: 'Spreadsheet does not contain sheet called "Plan2"!' }, pairedItem: { item: j } }]
      : emularExtrator(it, j)),
  });
  const doc = doDocumento(r, 'dois.xlsx');
  assert.ok(doc.text.includes('DOIS-P-5'), 'a aba boa chegou');
  assert.match(doc.text, /=== ABA: Plan2 \(NAO LIDA\) ===/);
  assert.match(doc.aviso_conteudo, /A aba "Plan2" NAO foi lida pelo extrator/);
  assert.deepEqual(doc.abas_lidas.map((a) => a.lida), [true, false]);
});

test('todas as abas com erro: o item de erro passa, e o Recompor abre a falha do documento como sempre', async () => {
  const arq = (await loteDeTres())[2];
  const r = await cadeia([arq], { extrator: async (_it, j) => [{ json: { error: 'arquivo corrompido' }, pairedItem: { item: j } }] });
  const doc = doDocumento(r, 'dois.xlsx');
  assert.equal(doc.extracao_falhou, true);
  assert.match(doc.aviso_conteudo, /FALHOU/);
});

test('aba vazia NAO e falha: aparece como "sem linhas" e nao abre pendência', async () => {
  const buf = await workbookDe([
    { nome: 'Dados', linhas: linhasMarcadas('VAZ-D', 3) },
    { nome: 'Vazia', linhas: [] },
    { nome: 'So cabecalho', linhas: [['Conta', 'Saldo']] },
  ]);
  const doc = doDocumento(await cadeia([{ nome: 'vazia.xlsx', buf }]), 'vazia.xlsx');
  assert.match(doc.text, /=== ABA: Vazia \(sem linhas\) ===/);
  assert.match(doc.text, /=== ABA: So cabecalho \(sem linhas\) ===/);
  assert.ok(doc.text.includes('VAZ-D-2'));
  assert.equal(doc.aviso_conteudo, null);
  assert.deepEqual(doc.abas_lidas.map((a) => a.linhas), [3, 0, 0]);
});

test('teto por aba: a aba que estoura diz QUAL aba cortou e quanto; a outra segue inteira', async () => {
  const buf = await workbookDe([
    { nome: 'Razao', linhas: linhasMarcadas('RZ', 2100) },
    { nome: 'Resumo', linhas: linhasMarcadas('RS', 10) },
  ]);
  const doc = doDocumento(await cadeia([{ nome: 'teto.xlsx', buf }]), 'teto.xlsx');
  assert.match(doc.aviso_conteudo, /Aba "Razao": Planilha maior que o teto de envio: 100 de 2100 linhas/);
  assert.ok(!/Aba "Resumo"/.test(doc.aviso_conteudo), 'a aba pequena não abre aviso');
  assert.ok(doc.text.includes('RS-9'));
  assert.ok(!doc.text.includes('RZ-2050'), 'o corte existe');
});

// =============================================================================================
// 4. A TOPOLOGIA do repositório (o que a suíte pode afirmar; o publicado só se confere ao vivo)
// =============================================================================================
test('topologia: Roteador(xlsx) -> Copiar Como ZIP -> Ler Abas -> Expandir Abas -> Extrair XLSX -> Agrupar -> Merge', () => {
  const c = wf.connections;
  const destino = (n, saida = 0) => (c[n].main[saida] || []).map((x) => x.node);
  assert.deepEqual(destino('Roteador de Formato', 1), ['Copiar Como ZIP']);
  assert.deepEqual(destino('Copiar Como ZIP'), ['Ler Abas do XLSX']);
  assert.deepEqual(destino('Ler Abas do XLSX'), ['Expandir Abas']);
  assert.deepEqual(destino('Expandir Abas'), ['Extrair XLSX']);
  assert.deepEqual(destino('Extrair XLSX'), ['Agrupar Linhas XLSX']);
  assert.equal(byName['Ler Abas do XLSX'].type, 'n8n-nodes-base.compression');
  assert.equal(byName['Ler Abas do XLSX'].parameters.operation, 'decompress');
  assert.equal(byName['Ler Abas do XLSX'].parameters.binaryPropertyName, 'zip');
  assert.equal(byName['Ler Abas do XLSX'].onError, 'continueRegularOutput', 'descompressão recusada cai no fallback, não derruba o lote');
  assert.match(byName['Extrair XLSX'].parameters.options.sheetName, /^=\{\{.*\$json\.aba_nome/);
  assert.match(byName['Agrupar Linhas XLSX'].parameters.jsCode, /\$\("Expandir Abas"\)\.all\(\)/);
});

test('o original NAO é tocado: o binário sob data sai de Copiar Como ZIP idêntico, a cópia é só a extensão', async () => {
  const [arq] = await loteDeTres();
  const item = { json: { nome_original: 'x' }, binary: { data: { fileName: 'x.xlsx', fileExtension: 'xlsx', mimeType: MIME_XLSX, data: arq.buf.toString('base64') } } };
  const out = await executar('Copiar Como ZIP', { item });
  assert.deepEqual(out.binary.data, item.binary.data);
  assert.equal(out.binary.zip.fileExtension, 'zip');
  assert.equal(out.binary.zip.data, item.binary.data.data);
  await assert.rejects(() => executar('Copiar Como ZIP', { item: { json: {}, binary: {} } }), /nao tem binario/);
});
