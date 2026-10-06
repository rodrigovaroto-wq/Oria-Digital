// REPETIÇÃO DE BLOCO POR FALHA TRANSITÓRIA (05/10/2026).
//
// Execução 8433 (Fw Valtra, 15 documentos): de 5 pendências `extracao_falhou`, 3
// eram transitórias — 2 de `limite_cadencia` (bloco 24 do balanço de 2.541 pares,
// bloco 11 do balancete de 2.040) e 1 de resposta vazia (bloco 4 da DRE) — e cada
// uma deixou um documento INCOMPLETO no banco porque o bloco foi chamado uma vez
// só: `IA Extrair` roda com `neverError` (a resposta 429 chega como item, não como
// exceção), então o `retryOnFail` do nó nunca tinha o que reexecutar.
//
// ESTES TESTES AFIRMAM COMPORTAMENTO (regra 3 do CLAUDE.md): quantas vezes o
// provedor é chamado, quanto se espera entre as chamadas, o que o bloco vira no fim.
// Não afirmam como o nó faz. O percurso é o do GRAFO REAL — o driver segue as
// `connections` do JSON gerado, executa o código REAL de cada nó Code e avalia o
// mesmo teste do IF — então remover um estágio ou trocar uma ligação reprova aqui.
//
// O QUE ELES NÃO PROVAM: que o motor do n8n executa esse grafo como o driver (um
// Merge de 4 entradas com 3 delas vazias; o pareamento `$('Esperar Retry k').item`
// depois do HTTP). Isso só o editor do n8n diz — ver o relatório da fatia.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { decidirRepeticao, diagnosticarErroApi } from '../lib/extract.mjs';
import { provedor } from '../lib/provedor.mjs';

const wf = JSON.parse(readFileSync(new URL('../workflow.e1-ingestao.json', import.meta.url)));
const porNome = Object.fromEntries(wf.nodes.map((n) => [n.name, n]));
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor;
const GEMINI = provedor().dialeto === 'gemini';

// --- respostas do provedor -----------------------------------------------------
const okJson = (chave) => JSON.stringify({
  moeda: 'BRL', unidade: 'R$ mil',
  diagnostico: {
    entidade: 'Moto Agricola Ltda.', tipo_confirma: true, tipo_sugerido: 'BALANCO',
    periodo_tipo: 'anual', periodo_referencia: '2023', legibilidade: 'ok', nota_legibilidade: null,
    resumo: 'BP.', justificativa: 'Uma coluna.',
  },
  grupos: [{ s: 'Ativo Circulante', sc: 'ativo_circulante', op: 1, cols: [{ ec: null, pc: '31/12/2023' }],
    l: [{ k: chave, vt: ['380'], vn: [380], cf: 0.98 }, { k: `${chave} 2`, vt: ['10'], vn: [10], cf: 0.98 }] }],
});
const resp = (texto, { cortada = false } = {}) => (GEMINI
  ? { candidates: [{ content: { parts: [{ text: texto }] }, finishReason: cortada ? 'MAX_TOKENS' : 'STOP' }] }
  : { choices: [{ message: { content: texto }, finish_reason: cortada ? 'length' : 'stop' }] });

const OK = (chave = 'Caixa') => resp(okJson(chave));
const RATE = (dica = 'Please try again in 6.8s.') => ({ error: {
  message: `Rate limit reached for model in organization on tokens per min (TPM): Limit 500000. ${dica}`,
  type: 'tokens', code: 'rate_limit_exceeded' } });
const VAZIA = () => resp('');
const RECUSA_400 = () => ({ error: { message: 'Invalid schema for response_format', type: 'invalid_request_error', code: 'invalid_json_schema' } });
const SEM_CREDITO = () => ({ error: { message: 'You exceeded your current quota', type: 'insufficient_quota', code: 'insufficient_quota' } });

// --- o driver ------------------------------------------------------------------
async function rodarNo(nome, { item, items, refs, esperas }) {
  const $ = (ref) => {
    if (!(ref in refs)) throw new Error(`Referência não mockada: $('${ref}') — o nó "${nome}" depende dela`);
    return { item: refs[ref], first: () => refs[ref], all: () => [refs[ref]] };
  };
  const $input = { item, first: () => (items ? items[0] : item), all: () => items || [item] };
  const falsoSetTimeout = (fn, ms) => { esperas.push(ms); fn(); return 0; };
  const fn = new AsyncFunction('$input', '$', '$json', 'setTimeout', porNome[nome].parameters.jsCode);
  return fn.call({}, $input, $, item ? item.json : undefined, falsoSetTimeout);
}
const seguinte = (nome, saida = 0) => wf.connections[nome].main[saida].map((c) => c.node);
const avaliaIf = (nomeIf, json) => {
  assert.equal(porNome[nomeIf].parameters.conditions.conditions[0].leftValue, '={{ $json.repetir }}');
  return json.repetir === true;
};

/**
 * Um bloco atravessa o grafo real: `Parse Extracao` -> IF -> `Esperar Retry` ->
 * `IA Extrair (tentativa k)` -> `Parse Extracao (tentativa k)` ... até sair para
 * `Juntar Tentativas`. `respostas[i]` é o que o provedor devolve na chamada i+1;
 * além do fim da lista, devolve a ÚLTIMA de novo (provedor que não melhora).
 */
async function atravessar(respostas, { ctx = {} } = {}) {
  const base = { documento_id: 'doc-1', documento_versao_id: 'ver-1', bloco: 24, blocos: 30,
    contas_no_documento: 2, ia_body: { corpo: 'x' }, ...ctx };
  const refs = { 'Fatiar Extracao': { json: base } };
  const esperas = [];
  let chamadas = 0;
  let nomeParse = 'Parse Extracao';
  for (;;) {
    const r = respostas[Math.min(chamadas, respostas.length - 1)];
    chamadas += 1;
    const saida = await rodarNo(nomeParse, { item: { json: r }, refs, esperas });
    const [proximo] = seguinte(nomeParse);
    if (proximo === 'Juntar Tentativas') return { saida, chamadas, esperas, ultimoNo: nomeParse };
    // proximo é o IF do estágio
    if (!avaliaIf(proximo, saida.json)) {
      assert.ok(seguinte(proximo, 1).includes('Juntar Tentativas'), 'o ramo false do IF vai ao Merge');
      return { saida, chamadas, esperas, ultimoNo: nomeParse };
    }
    const [esperar] = seguinte(proximo, 0);
    const aposEsperar = await rodarNo(esperar, { items: [saida], refs, esperas });
    refs[esperar] = { json: aposEsperar[0].json };
    const [ia] = seguinte(esperar);
    [nomeParse] = seguinte(ia);
  }
}

// --- comportamento -------------------------------------------------------------

test('bloco que toma 429 DUAS vezes e depois 200 termina COM as linhas — a perda do bloco 24', async () => {
  const r = await atravessar([RATE(), RATE(), OK()]);
  assert.equal(r.chamadas, 3, 'foi chamado 3 vezes');
  assert.deepEqual(r.esperas, [30_000, 60_000], 'esperou 30 s e depois 60 s antes de repetir');
  assert.equal(r.saida.json.campos.length, 2, 'as linhas chegaram');
  assert.equal(r.saida.json.falha_motivo, null, 'sucesso depois da repetição NÃO abre pendência');
  assert.equal(r.saida.json.tentativas, 3);
  assert.equal(r.saida.json.documento_id, 'doc-1', 'o contexto do bloco sobreviveu às repetições');
  assert.equal(r.saida.json.bloco, 24);
});

test('resposta VAZIA (a DRE da execução 8433) é repetida e recupera', async () => {
  const r = await atravessar([VAZIA(), OK()]);
  assert.equal(r.chamadas, 2);
  assert.equal(r.saida.json.campos.length, 2);
  assert.equal(r.saida.json.falha_motivo, null);
});

test('resposta vazia SEMPRE: 4 tentativas, e a pendência diz quantas', async () => {
  const r = await atravessar([VAZIA()]);
  assert.equal(r.chamadas, decidirRepeticao().maxTentativas);
  assert.equal(r.saida.json.campos.length, 0);
  assert.match(r.saida.json.falha_motivo, /sem conteudo/);
  assert.match(r.saida.json.falha_motivo, /Bloco chamado 4 vez/);
});

test('400 (pedido recusado) NÃO é repetido: uma chamada, nenhuma espera', async () => {
  const r = await atravessar([RECUSA_400(), OK()]);
  assert.equal(r.chamadas, 1);
  assert.deepEqual(r.esperas, []);
  assert.equal(r.saida.json.campos.length, 0);
  assert.ok(r.saida.json.falha_motivo, 'a recusa continua sendo pendência');
  assert.doesNotMatch(r.saida.json.falha_motivo, /Bloco chamado/, 'primeira e única tentativa não leva nota de repetição');
});

test('crédito esgotado e conteúdo truncado NÃO são repetidos (repetir não muda o desfecho)', async () => {
  const semCredito = await atravessar([SEM_CREDITO(), OK()]);
  assert.equal(semCredito.chamadas, 1);
  assert.match(semCredito.saida.json.falha_motivo, /SEM CRÉDITO/);
  const truncado = await atravessar([resp('{"grupos":[{"s":"Ati', { cortada: true }), OK()]);
  assert.equal(truncado.chamadas, 1);
  assert.match(truncado.saida.json.falha_motivo, /truncada/);
});

test('teto esgotado em cadência: gera a pendência com a CONTAGEM e as esperas somadas', async () => {
  const r = await atravessar([RATE()]);
  assert.equal(r.chamadas, 4);
  assert.deepEqual(r.esperas, [30_000, 60_000, 60_000]);
  assert.equal(r.saida.json.campos.length, 0);
  const m = r.saida.json.falha_motivo;
  assert.match(m, /LIMITE DE CADÊNCIA DO PROVEDOR/, 'a causa do provedor continua nomeada');
  assert.match(m, /Bloco chamado 4 vez\(es\), esperas somadas 150s/);
  assert.match(m, /teto de 4 tentativas ESGOTADO/);
  assert.equal(r.saida.json.tentativas, 4);
});

test('a espera respeita o que o provedor pede, com teto de 60 s', async () => {
  const pede45 = await atravessar([RATE('Please try again in 45s.'), OK()]);
  assert.deepEqual(pede45.esperas, [45_000], 'pediu 45 s: acima do piso de 30 s, vale o pedido');
  const pede200 = await atravessar([RATE('Please try again in 3m20s.'), OK()]);
  assert.deepEqual(pede200.esperas, [60_000], 'pediu 200 s: o teto de 60 s manda (o balde se recompõe em 1 min)');
  const pede2 = await atravessar([RATE('Please try again in 2s.'), OK()]);
  assert.deepEqual(pede2.esperas, [30_000], 'pediu 2 s: o piso de 30 s manda (não repetir no mesmo balde)');
});

test('Esperar Retry espera UMA vez para todos os blocos que falharam, não uma por bloco', async () => {
  const esperas = [];
  const itens = [20, 45, 30].map((s, i) => ({ json: { repetir: true, espera_s: s, bloco: i + 1, ia_body: {} } }));
  const out = await rodarNo('Esperar Retry 1', { items: itens, refs: {}, esperas });
  assert.deepEqual(esperas, [45_000], 'uma espera, a maior pedida');
  assert.equal(out.length, 3);
  assert.ok(out.every((o, i) => o.pairedItem.item === i && o.json.repetir === false && o.json.espera_total_s === 45));
});

test('bloco SEM o corpo da chamada (contexto perdido) vira falha declarada, nunca repetição às cegas', async () => {
  const r = await atravessar([RATE(), OK()], { ctx: { ia_body: undefined } });
  assert.equal(r.chamadas, 1, 'sem corpo não há o que reenviar ao provedor');
  assert.ok(r.saida.json.falha_motivo);
  assert.equal(r.saida.json.repetir, undefined);
});

test('erro SEM status e SEM corpo de provedor (queda de rede) é transitório; 400 com corpo não é', () => {
  assert.equal(diagnosticarErroApi({ message: 'socket hang up' }).transitoria, true);
  assert.equal(diagnosticarErroApi({ status: 503 }).transitoria, true);
  assert.equal(diagnosticarErroApi({ status: 408 }).transitoria, true);
  assert.equal(diagnosticarErroApi({ error: { type: 'invalid_request_error', message: 'x' } }).transitoria, false);
  assert.equal(diagnosticarErroApi({ status: 400, message: 'timeout na validação do schema' }).transitoria, false,
    'um 4xx nunca é transitório, mesmo que o texto cite "timeout"');
  assert.equal(diagnosticarErroApi({ error: { message: 'tokens per day (TPD) limit', code: 'rate_limit_exceeded' } }).transitoria, false,
    'cota do DIA não volta em 60 s');
});

// --- topologia -----------------------------------------------------------------

test('topologia: todo estágio converge no Merge, que alimenta o Juntar Blocos UMA vez', () => {
  const max = decidirRepeticao().maxTentativas;
  assert.equal(porNome['Juntar Tentativas'].parameters.numberInputs, max);
  assert.deepEqual(seguinte('Juntar Tentativas'), ['Juntar Blocos']);
  const paraOMerge = Object.entries(wf.connections).flatMap(([de, c]) => c.main.flatMap((saida, s) =>
    saida.filter((x) => x.node === 'Juntar Tentativas').map((x) => ({ de, s, idx: x.index }))));
  assert.deepEqual(paraOMerge.map((x) => x.idx).sort(), Array.from({ length: max }, (_, i) => i),
    'cada entrada do Merge recebe exatamente UM caminho (nunca duas conexões cruas no mesmo input)');
  const paraOJuntar = Object.entries(wf.connections).filter(([, c]) => c.main.flat().some((x) => x.node === 'Juntar Blocos'));
  assert.deepEqual(paraOJuntar.map(([de]) => de), ['Juntar Tentativas'],
    'nenhum Parse chega ao Juntar Blocos por fora do Merge — senão o documento sai duas vezes, a primeira incompleta');
});

test('as repetições passam pela MESMA cadência da primeira chamada (nunca em rajada)', () => {
  const primeira = porNome['IA Extrair'].parameters.options.batching.batch;
  for (let k = 2; k <= decidirRepeticao().maxTentativas; k += 1) {
    assert.deepEqual(porNome[`IA Extrair (tentativa ${k})`].parameters.options.batching.batch, primeira);
    assert.equal(porNome[`IA Extrair (tentativa ${k})`].parameters.options.response.response.neverError, true,
      'o corpo do erro chega ao Parse, que é quem decide se repete');
  }
});
