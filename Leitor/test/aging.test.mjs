// O AGING (MB3a): a carteira numa data-base, positivos separados dos negativos.
//
// Parte 1, contra os sintéticos de `Dados de Teste/volume` (o gabarito que o
// `conferir_volume.py` prova contra o book-distress): MB1 → MB2 → aging dá as 7 faixas, as
// contrapartes e a concentração do gabarito, no AR e no AP.
// Parte 2, as regras: negativo separado, liquidado fora, emitido depois da data-base contado,
// fronteiras de faixa, homônimo com CNPJ diferente, nada some no "demais".
// Sem python3 a parte 1 REPROVA (não pula).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, openAsBlob, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { lerTabela } from '../lib/tabela.mjs';
import { proporMapeamento, aplicadorDeMapeamento } from '../lib/mapeamento.mjs';
import { agregadorDeAging, dataBaseDoTitulo, faixaDoAtraso, FAIXAS } from '../lib/aging.mjs';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const N = 3000;

/** O caminho inteiro: MB1 (amostra) → MB2 (proposta confirmada como está) → MB1 de novo → aging. */
async function aging(blob, { dataBase } = {}) {
  const r1 = await lerTabela(blob, { soAmostra: true });
  const p = proporMapeamento(r1.cabecalho.celulas, r1.amostra, { tipos: r1.amostra_tipos });
  const ap = aplicadorDeMapeamento({ mapa: p.mapa, formato: p.formato, cabecalho: r1.cabecalho.celulas, confirmado_por: 'x', confirmado_em: 'y' });
  const antes = [], titulos = [];
  await lerTabela(blob, { aoLinha: (l) => { if (l.destino === 'antes_do_cabecalho') antes.push(l); const x = ap.linha(l); if (x.titulo) titulos.push(x.titulo); } });
  const proposta = dataBaseDoTitulo(antes, p.formato.datas);
  const ag = agregadorDeAging({ dataBase: dataBase ?? proposta.data });
  for (const t of titulos) ag.titulo(t);
  return { resumo: ag.resumo(), proposta, aplicador: ap.resumo() };
}

const dir = mkdtempSync(join(tmpdir(), 'aging-'));
const gerado = spawnSync('python3', [join(RAIZ, 'Dados de Teste/volume/gerar_volume.py'), '--linhas', String(N), '--saida', dir, '--sem-xlsx'], { encoding: 'utf8' });
const gab = gerado.status === 0 ? JSON.parse(readFileSync(join(dir, `GABARITO_${N}.json`), 'utf8')) : null;
process.on('exit', () => rmSync(dir, { recursive: true, force: true }));

test('o gerador das bases sintéticas rodou (sem ele a parte 1 não prova nada)', () => {
  assert.equal(gerado.status, 0, `python3 gerar_volume.py falhou: ${gerado.stderr || gerado.error}`);
});

// As faixas do gabarito têm outro nome; os valores são os mesmos.
const FAIXA_DO_GABARITO = { 'a vencer': 'a_vencer', '1-30': '1_30', '31-60': '31_60', '61-90': '61_90', '91-180': '91_180', '181-360': '181_360', '>360': 'acima_360' };

for (const chave of ['contas_a_receber', 'contas_a_pagar']) {
  test(`${chave}: data-base do título, as 7 faixas, as contrapartes e a concentração do gabarito`, { skip: !gab && 'sem gabarito' }, async () => {
    const { resumo, proposta } = await aging(await openAsBlob(join(dir, `${chave}_${N}.csv`)));
    const g = gab[chave];
    assert.equal(proposta.data, '2025-12-31');
    assert.match(proposta.evidencia, /Posição em 31\/12\/2025/);
    assert.equal(resumo.positivos.saldo, String(g.saldo_em_aberto_centavos));
    assert.equal(BigInt(resumo.positivos.saldo), BigInt(g.bp_rs_mil) * 100000n, 'Σ = o balanço do book');
    for (const [fg, v] of Object.entries(g.saldo_por_faixa_fina_centavos)) assert.equal(resumo.positivos.por_faixa[FAIXA_DO_GABARITO[fg]], String(v), fg);
    assert.equal(resumo.contrapartes_com_saldo, g.contrapartes_em_aberto);
    assert.equal(resumo.concentracao_top10_pct, Math.round(g.concentracao_top10 * 1000000) / 10000);
    assert.equal(resumo.liquidados, g.titulos.liquidados);
    assert.equal(resumo.positivos.titulos, g.titulos.abertos + g.titulos.parciais);
    // Por contraparte: o saldo de cada uma = o do gabarito (que = o aging do book por cliente).
    const porDoc = Object.fromEntries(resumo.maiores.map((c) => [c.documento, c.saldo]));
    assert.equal(Object.keys(porDoc).length, g.contrapartes_em_aberto);
    assert.equal(Object.values(porDoc).reduce((a, b) => a + BigInt(b), 0n), BigInt(g.saldo_em_aberto_centavos));
  });
}

// ================================================================ 2. as regras =====
const t = (contraparte, vencimento, saldo, extra = {}) => ({ contraparte, vencimento, saldo: BigInt(saldo), ...extra });

test('sem data-base, o aging recusa (ele é a posição numa data)', () => {
  assert.throws(() => agregadorDeAging({}), /sem data-base/);
  assert.throws(() => agregadorDeAging({ dataBase: '31/12/2025' }), /sem data-base/);
});

test('fronteiras: vencer NA data-base é a vencer; 1, 30, 31, 90, 91, 360 e 361 dias caem onde dizem', () => {
  const casos = { 0: 'a_vencer', '-5': 'a_vencer', 1: '1_30', 30: '1_30', 31: '31_60', 60: '31_60', 61: '61_90', 90: '61_90', 91: '91_180', 180: '91_180', 181: '181_360', 360: '181_360', 361: 'acima_360' };
  for (const [a, f] of Object.entries(casos)) assert.equal(faixaDoAtraso(Number(a)), f, `atraso ${a}`);
  const ag = agregadorDeAging({ dataBase: '2025-12-31' });
  ag.titulo(t('A', '2025-12-31', 100));
  ag.titulo(t('A', '2025-12-30', 200));
  ag.titulo(t('A', '2024-12-30', 300)); // 366 dias
  const r = ag.resumo();
  assert.deepEqual([r.positivos.por_faixa.a_vencer, r.positivos.por_faixa['1_30'], r.positivos.por_faixa.acima_360], ['100', '200', '300']);
  assert.equal(r.positivos.vencido, '500');
  assert.equal(FAIXAS.length, 7);
});

test('saldo NEGATIVO fica separado: não entra nas faixas nem reduz a carteira', () => {
  const ag = agregadorDeAging({ dataBase: '2025-12-31' });
  ag.titulo(t('A', '2025-12-01', 100000));
  ag.titulo(t('B', '2026-01-10', 50000));
  ag.titulo(t('D', '2025-11-01', -5000));
  ag.titulo(t('D', '2025-10-01', -2000));
  const r = ag.resumo();
  assert.equal(r.positivos.saldo, '150000');
  assert.equal(r.negativos.saldo, '-7000');
  assert.equal(r.negativos.titulos, 2);
  assert.deepEqual(r.negativos.maiores, [{ contraparte: 'D', documento: null, saldo: '-7000', titulos: 2 }]);
  assert.deepEqual(r.negativos.demais, { contrapartes: 0, saldo: '0', titulos: 0 });
  assert.equal(Object.values(r.positivos.por_faixa).reduce((a, b) => a + BigInt(b), 0n), 150000n);
  assert.match(r.negativos.efeito, /Adiantamentos/);
});

test('liquidado (saldo zero) é contado e não entra em faixa nenhuma', () => {
  const ag = agregadorDeAging({ dataBase: '2025-12-31' });
  ag.titulo(t('A', '2025-01-01', 0));
  ag.titulo(t('A', '2025-12-01', 10));
  const r = ag.resumo();
  assert.equal(r.liquidados, 1);
  assert.equal(r.positivos.titulos, 1);
  assert.equal(r.positivos.por_faixa.acima_360, '0');
});

test('emitido depois da data-base entra e é contado com o saldo e o efeito', () => {
  const ag = agregadorDeAging({ dataBase: '2025-12-31' });
  ag.titulo(t('A', '2026-02-01', 700, { emissao: '2026-01-05' }));
  ag.titulo(t('B', '2026-01-01', 300, { emissao: '2025-12-20' }));
  const r = ag.resumo();
  assert.deepEqual([r.emitidos_depois_da_data_base.titulos, r.emitidos_depois_da_data_base.saldo_positivos], [1, '700']);
  assert.match(r.emitidos_depois_da_data_base.efeito, /data-base errada/);
  assert.equal(r.positivos.saldo, '1000');
});

test('homônimo com CNPJ diferente não se soma; o mesmo nome sem documento se soma', () => {
  const ag = agregadorDeAging({ dataBase: '2025-12-31' });
  ag.titulo(t('ACME LTDA', '2025-12-01', 100, { documento_contraparte: '11.222.333/0001-81' }));
  ag.titulo(t('ACME LTDA', '2025-12-01', 200, { documento_contraparte: '33.000.001/0001-95' }));
  ag.titulo(t('BETA', '2025-12-01', 10));
  ag.titulo(t(' BETA ', '2025-12-01', 20));
  const r = ag.resumo();
  assert.equal(r.contrapartes_com_saldo, 3);
  assert.deepEqual(r.maiores.map((c) => [c.contraparte, c.documento, c.saldo]), [['ACME LTDA', '33000001000195', '200'], ['ACME LTDA', '11222333000181', '100'], ['BETA', null, '30']]);
});

test('top e demais: nada some — nominais + demais = total, com a contagem', () => {
  const ag = agregadorDeAging({ dataBase: '2025-12-31', top: 3 });
  for (let i = 1; i <= 8; i++) ag.titulo(t(`C${i}`, '2025-12-01', i * 100));
  const r = ag.resumo();
  assert.deepEqual(r.maiores.map((c) => c.contraparte), ['C8', 'C7', 'C6']);
  assert.deepEqual(r.demais, { contrapartes: 5, saldo: '1500', vencido: '1500', titulos: 5 });
  assert.equal(r.maiores.reduce((a, c) => a + BigInt(c.saldo), 0n) + BigInt(r.demais.saldo), BigInt(r.positivos.saldo));
});

test('concentração e % vencido sem float: 1/3 dá 33,3333', () => {
  const ag = agregadorDeAging({ dataBase: '2025-12-31' });
  ag.titulo(t('A', '2025-12-01', 1));
  ag.titulo(t('B', '2026-01-10', 2));
  const r = ag.resumo();
  assert.equal(r.positivos.vencido_pct, 33.3333);
  assert.equal(r.concentracao_top10_pct, 100);
});

test('data-base do título: as frases do ERP, e sem frase nenhuma o motivo (nunca a data de hoje)', () => {
  const l = (c, n = 0) => ({ n, celulas: [c] });
  assert.equal(dataBaseDoTitulo([l('Posição em 31/12/2025')]).data, '2025-12-31');
  assert.equal(dataBaseDoTitulo([l('RELATÓRIO'), l('Data-base: 30/06/2025', 1)]).data, '2025-06-30');
  assert.equal(dataBaseDoTitulo([l('Títulos vencidos até 2025-03-31')]).data, '2025-03-31');
  assert.equal(dataBaseDoTitulo([l('Posição em 03/04/2025')], 'mes_dia_ano').data, '2025-03-04');
  const nada = dataBaseDoTitulo([l('CONTAS A RECEBER')]);
  assert.equal(nada.data, null);
  assert.match(nada.evidencia, /o analista informa/);
});

// ============================ 3. achados da revisão independente (12/11/2026) =====
test('data-base: a data de impressão, geração ou emissão NUNCA vence a da posição', () => {
  const l = (c, n = 0) => ({ n, celulas: [c] });
  assert.equal(dataBaseDoTitulo([l('Impresso em 12/11/2026 10:32'), l('Posição em 31/12/2025', 1)]).data, '2025-12-31');
  assert.equal(dataBaseDoTitulo([l('Gerado em 05/01/2026'), l('Data-base: 31/12/2025', 1)]).data, '2025-12-31');
  assert.equal(dataBaseDoTitulo([l('Emitido em 05/01/2026')]).data, null, 'só emissão: nenhuma proposta');
  assert.equal(dataBaseDoTitulo([l('Item 05/01/2026')]).data, null, '"em" dentro de "Item" não é a palavra "em"');
  assert.equal(dataBaseDoTitulo([l('Período de 01/01/2025 até 31/12/2025')]).data, '2025-12-31');
  assert.equal(dataBaseDoTitulo([l('Relatório de Clientes em 30/06/2025')]).data, '2025-06-30', '"em" fraco vale sem frase forte');
});

test('CNPJ/CPF de preenchimento ou com DV errado não junta contrapartes diferentes', () => {
  const ag = agregadorDeAging({ dataBase: '2025-12-31' });
  ag.titulo(t('ACME', '2025-12-01', 100, { documento_contraparte: '00.000.000/0000-00' }));
  ag.titulo(t('BETA', '2025-12-01', 200, { documento_contraparte: '00.000.000/0000-00' }));
  ag.titulo(t('GAMA', '2025-12-01', 300, { documento_contraparte: '000.000.000-00' }));
  ag.titulo(t('DELTA', '2025-12-01', 400, { documento_contraparte: '11.222.333/0001-99' }));
  const r = ag.resumo();
  assert.equal(r.contrapartes_com_saldo, 4);
  assert.equal(r.documentos_invalidos.titulos, 4);
  assert.match(r.documentos_invalidos.efeito, /agrupados pelo nome/);
  assert.ok(r.maiores.every((c) => c.documento === null));
});

test('o mesmo cliente com e sem documento é UMA contraparte; com dois documentos para o nome, fica à parte e contado', () => {
  const ag = agregadorDeAging({ dataBase: '2025-12-31' });
  ag.titulo(t('ACME', '2025-12-01', 100, { documento_contraparte: '11.222.333/0001-81' }));
  ag.titulo(t('ACME', '2025-12-01', 200));
  ag.titulo(t('BETA', '2025-12-01', 10, { documento_contraparte: '33.000.001/0001-95' }));
  ag.titulo(t('BETA', '2025-12-01', 20, { documento_contraparte: '33.000.002/0001-30' }));
  ag.titulo(t('BETA', '2025-12-01', 5));
  const r = ag.resumo();
  const acme = r.maiores.filter((c) => c.contraparte === 'ACME');
  assert.deepEqual(acme.map((c) => [c.documento, c.saldo, c.titulos]), [['11222333000181', '300', 2]]);
  assert.equal(r.maiores.filter((c) => c.contraparte === 'BETA').length, 3, 'homônimos: o sem documento não é fundido');
  assert.equal(r.sem_documento_ambiguo.titulos, 1);
});

test('CNPJ do XLSX que perdeu o zero à esquerda (13 dígitos) é o mesmo CNPJ', () => {
  const ag = agregadorDeAging({ dataBase: '2025-12-31' });
  ag.titulo(t('ACME', '2025-12-01', 100, { documento_contraparte: '1222333000128' }));
  ag.titulo(t('ACME', '2025-12-01', 200, { documento_contraparte: '01.222.333/0001-28' }));
  ag.titulo(t('OUTRA', '2025-12-01', 50, { documento_contraparte: '1222333000128' }));
  const r = ag.resumo();
  assert.equal(r.documentos_invalidos.titulos, 0);
  assert.deepEqual(r.maiores.map((c) => [c.contraparte, c.documento, c.saldo]), [['ACME', '01222333000128', '350']],
    'o CNPJ identifica: o mesmo CNPJ com outro nome é a mesma contraparte (nome da primeira linha)');
});

test('data-base impossível (30/02) é recusada, não rolada para março', () => {
  assert.throws(() => agregadorDeAging({ dataBase: '2025-02-30' }), /sem data-base válida/);
  assert.throws(() => agregadorDeAging({ dataBase: '2025-04-31' }), /sem data-base válida/);
  assert.doesNotThrow(() => agregadorDeAging({ dataBase: '2024-02-29' }));
});

test('créditos: nada some — maiores + demais = negativos, com a contagem', () => {
  const ag = agregadorDeAging({ dataBase: '2025-12-31', top: 10 });
  for (let i = 1; i <= 12; i++) ag.titulo(t(`C${i}`, '2025-12-01', -i));
  const r = ag.resumo();
  assert.equal(r.negativos.saldo, '-78');
  assert.equal(r.negativos.maiores.reduce((a, c) => a + BigInt(c.saldo), 0n) + BigInt(r.negativos.demais.saldo), -78n);
  assert.deepEqual(r.negativos.demais, { contrapartes: 2, saldo: '-3', titulos: 2 });
});

test('maiores[].titulos conta só os positivos; Σ maiores + demais = positivos.titulos', () => {
  const ag = agregadorDeAging({ dataBase: '2025-12-31', top: 1 });
  ag.titulo(t('A', '2025-12-01', 100));
  for (let i = 0; i < 5; i++) ag.titulo(t('A', '2025-12-01', -1));
  ag.titulo(t('B', '2025-12-01', 50));
  const r = ag.resumo();
  assert.equal(r.maiores[0].titulos, 1);
  assert.equal(r.maiores[0].titulos + r.demais.titulos, r.positivos.titulos);
});

test('emitidos depois da data-base: +700 e −700 não se anulam', () => {
  const ag = agregadorDeAging({ dataBase: '2025-12-31' });
  ag.titulo(t('A', '2026-02-01', 700, { emissao: '2026-01-05' }));
  ag.titulo(t('B', '2026-02-01', -700, { emissao: '2026-01-05' }));
  const r = ag.resumo();
  assert.deepEqual([r.emitidos_depois_da_data_base.saldo_positivos, r.emitidos_depois_da_data_base.saldo_negativos], ['700', '-700']);
});

