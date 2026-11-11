// `textos_perdidos`: CONTRATO com o portal. Por VERSÃO, as chaves COMPLETAS (iguais a
// campo_extraido.chave) das contas que ficaram só com os números porque os textos vieram
// desalinhados (achatarGrupos). Ausente quando não houve perda (regra 1: nunca [] de mentira).
// Fixture: a FORMA da execução 9637 (Piraquara 08) em 5 colunas — sintética (regra 4). A
// resposta real foi conferida à mão em 11/11/2026: 6 contas, 4 chaves distintas (um credor com
// dois contratos repete a chave), todas presentes em campo_extraido.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { achatarGrupos } from '../lib/extract.mjs';

const wf = JSON.parse(readFileSync(new URL('../workflow.e1-ingestao.json', import.meta.url)));
const code = (n) => wf.nodes.find((x) => x.name === n).parameters.jsCode;
const AF = Object.getPrototypeOf(async function () {}).constructor;
const run = (name, { item, items, refs = {} }) => {
  const $ = (r) => ({ item: refs[r], first: () => refs[r], all: () => [refs[r]], itemMatching: () => refs[r], isExecuted: true });
  return new AF('$input', '$', '$env', '$json', '$itemIndex', 'Buffer', code(name))
    .call({ helpers: {} }, { item, first: () => item, all: () => items || [item] }, $, {}, item?.json, 0, Buffer);
};

const cols = ['A', 'B', 'C', 'D', 'E'].map((pc) => ({ ec: null, pc }));
// perde texto: 2 livres para 3 colunas sem número. Rótulo com o valor colado (limparRotuloColado muda a chave).
const PERDE = (k) => ({ k, vn: [null, null, null, 1000, 20], vt: ['x', 'y', '1.000', '20'] });
const FECHA = { k: 'Fecha', vn: [null, null, null, 10, 20], vt: ['x', 'y', 'z', '10', '20'] };
const respostaDe = (l) => ({ json: { choices: [{ message: { content: JSON.stringify({
  moeda: 'BRL', unidade: 'R$ mil', diagnostico: { entidade: 'E', tem_dado_financeiro: true, justificativa: 'j' },
  grupos: [{ s: 'S', sc: null, op: 1, cols, l }] }) } }] } });
const ctxDe = (bloco, blocos) => ({ json: { documento_versao_id: 'ver-1', documento_id: 'doc-1', bloco, blocos, contas_do_bloco: null } });

test('lib: a chave de textos perdidos é a MESMA de linhas[].chave (depois de limparRotuloColado), inteira e sem repetir', () => {
  const longa = 'Banco com um nome muito longo '.repeat(8).trim();
  const r = achatarGrupos([{ s: 'S', sc: null, op: 1, cols, l: [PERDE('Banco X1.000,00'), PERDE(longa), PERDE(longa), FECHA] }]);
  assert.equal(r.textosPerdidos.length, 3);
  assert.deepEqual(r.chavesTextosPerdidos, ['Banco X', longa]);
  const gravadas = new Set(r.linhas.map((l) => l.chave));
  for (const c of r.chavesTextosPerdidos) assert.ok(gravadas.has(c), `"${c}" não é chave gravada`);
  assert.ok(!r.chavesTextosPerdidos.includes('Fecha'), 'conta reatribuída não é perda');
});

test('lib: sem perda, a lista é vazia (a AUSÊNCIA do campo é decidida no Juntar Blocos)', () => {
  assert.deepEqual(achatarGrupos([{ s: 'S', sc: null, op: 1, cols, l: [FECHA] }]).chavesTextosPerdidos, []);
});

test('Parse Extracao -> Juntar Blocos: vários blocos, segunda passada, e ausente quando não houve perda', async () => {
  const b1 = await run('Parse Extracao', { item: respostaDe([PERDE('Ctr A')]), refs: { 'Fatiar Extracao': ctxDe(1, 2) } });
  const b2 = await run('Parse Extracao', { item: respostaDe([PERDE('Ctr A'), PERDE('Ctr B')]), refs: { 'Fatiar Extracao': ctxDe(2, 2) } });
  assert.deepEqual(b1.json.textos_perdidos_chaves, ['Ctr A']);
  const [jb] = await run('Juntar Blocos', { item: b1, items: [b1, b2] });
  const m = jb.json.medicao_documento;
  assert.deepEqual(m.textos_perdidos, ['Ctr A', 'Ctr B'], 'união dos blocos, sem duplicar');
  assert.equal(m.textos_perdidos_n, 2);
  const gravadas = new Set(jb.json.campos.map((c) => c.chave));
  for (const c of m.textos_perdidos) assert.ok(gravadas.has(c));
  assert.match(jb.json.falha_motivo, /TEXTOS sem coluna/, 'falha_motivo continua como estava');

  // segunda passada: a 1a (cobertura baixa, com perda) viaja em passada_anterior; a 2a devolve menos
  // linhas, a anterior FICA, e a perda dela tem de sobreviver
  const ctx1 = { json: { ...ctxDe(1, 1).json, contas_do_bloco: 100, ia_body: { messages: [], model: 'm' } } };
  const p1 = await run('Parse Extracao', { item: respostaDe([PERDE('Ctr A'), PERDE('Ctr B'), PERDE('Ctr C')]), refs: { 'Fatiar Extracao': ctx1 } });
  assert.equal(p1.json.repetir, true, 'a 1a passada tem de pedir a 2a (senão o teste não prova nada)');
  const ctx2 = { json: { ...ctx1.json, ...p1.json, repetir: undefined } };
  const p2 = await run('Parse Extracao', { item: respostaDe([FECHA]), refs: { 'Fatiar Extracao': ctx2 } });
  assert.equal(p2.json.passadas, 2);
  assert.deepEqual(p2.json.textos_perdidos_chaves, ['Ctr A', 'Ctr B', 'Ctr C'], 'ficou a passada anterior, com a perda dela');

  const limpo = await run('Parse Extracao', { item: respostaDe([FECHA]), refs: { 'Fatiar Extracao': ctxDe(1, 1) } });
  const [jl] = await run('Juntar Blocos', { item: limpo, items: [limpo] });
  assert.ok(!('textos_perdidos' in jl.json.medicao_documento) && !('textos_perdidos_n' in jl.json.medicao_documento));
});

test('versao_medicao é p4-4 (p4-3 + a coordenada): sem ela, "textos_perdidos ausente" não distingue n8n novo sem perda de n8n antigo que não mediu', async () => {
  const b = await run('Parse Extracao', { item: respostaDe([FECHA]), refs: { 'Fatiar Extracao': ctxDe(1, 1) } });
  const [jb] = await run('Juntar Blocos', { item: b, items: [b] });
  assert.equal(jb.json.medicao_documento.versao_medicao, 'p4-4');
});
