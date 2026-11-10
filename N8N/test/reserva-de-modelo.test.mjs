// P8 — RETENTATIVA CLASSIFICADA E RESERVA DE MODELO (10/11/2026).
//
// Critério de pronto do plano: "uma falha simulada do provedor principal termina no
// alternativo, e fica registrada". O percurso é o do GRAFO REAL (mesmo driver de
// `repeticao-de-bloco.test.mjs`): segue as `connections` do JSON gerado e executa o
// código REAL de cada nó Code. Afirma COMPORTAMENTO: quem foi chamado, com que corpo,
// quanto custou, o que ficou registrado.
//
// O QUE ESTE ARQUIVO NÃO PROVA: que o `gpt-4o` da conta do dono aceita o corpo trocado
// (`trocarModeloDoCorpo` segue `CAPACIDADES_POR_MODELO`, que é declaração nossa, não
// medição da API), que o limite por minuto do 4o da conta comporta um bloco, nem que o
// motor do n8n executa o grafo como o driver. Só uma chamada real diz — ver o relatório.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { decidirRepeticao } from '../lib/extract.mjs';
import { provedor, PROVEDORES, montarCorpoIA, trocarModeloDoCorpo } from '../lib/provedor.mjs';
import {
  MODELO_EXTRACAO, MODELO_EXTRACAO_RESERVA, MODELOS_POR_PROVEDOR, PRECOS_POR_PROVEDOR, custoDaChamada,
} from '../lib/custo.mjs';

const wf = JSON.parse(readFileSync(new URL('../workflow.e1-ingestao.json', import.meta.url)));
const porNome = Object.fromEntries(wf.nodes.map((n) => [n.name, n]));
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor;
const PROV = provedor();
const RESERVA = MODELO_EXTRACAO_RESERVA;
// NÃO é `&& RESERVA`: reserva desligada tem de REPROVAR aqui, não pular (regra 7: estágio que não rodou
// parece estágio limpo). Só o Google (sem reserva por desenho, ver custo.mjs) dispensa os testes de grafo.
const aplicavel = PROV.dialeto === 'openai';

// --- função pura: trocarModeloDoCorpo ---------------------------------------------
const base = { sistema: 'S', partes: [{ type: 'text', text: 'doc' }], schema: { name: 'x', strict: true, schema: { type: 'object' } }, maxTokens: 16384 };

test('trocarModeloDoCorpo: GPT-5 -> 4o tira temperature-proibida/raciocínio e usa o teto antigo', () => {
  const luna = montarCorpoIA(PROVEDORES.openai, { ...base, modelo: 'gpt-5.6-luna', esforco: 'low' });
  assert.equal(luna.max_completion_tokens, 16384);
  assert.equal(luna.reasoning_effort, 'low');
  assert.equal('temperature' in luna, false);
  const quatro = trocarModeloDoCorpo(PROVEDORES.openai, luna, 'gpt-4o');
  // o mesmo que montar do zero para o 4o: é a definição de "respeitar as capacidades"
  assert.deepEqual(quatro, montarCorpoIA(PROVEDORES.openai, { ...base, modelo: 'gpt-4o' }));
  assert.equal(quatro.max_tokens, 16384);
  assert.equal(quatro.temperature, 0);
  assert.equal('max_completion_tokens' in quatro, false);
  assert.equal('reasoning_effort' in quatro, false, 'campo que o 4o não conhece é 400 na chamada inteira');
  assert.notEqual(luna.model, quatro.model, 'o original não é mutado');
  assert.equal(luna.model, 'gpt-5.6-luna');
});

test('trocarModeloDoCorpo: 4o -> GPT-5 faz o caminho inverso (e o esforço só entra se pedido)', () => {
  const quatro = montarCorpoIA(PROVEDORES.openai, { ...base, modelo: 'gpt-4o' });
  const luna = trocarModeloDoCorpo(PROVEDORES.openai, quatro, 'gpt-5.6-luna', 'low');
  assert.deepEqual(luna, montarCorpoIA(PROVEDORES.openai, { ...base, modelo: 'gpt-5.6-luna', esforco: 'low' }));
  assert.equal('temperature' in luna, false, 'GPT-5 recusa temperature');
  assert.equal('max_tokens' in luna, false);
  const semEsforco = trocarModeloDoCorpo(PROVEDORES.openai, quatro, 'gpt-5.6-luna');
  assert.equal('reasoning_effort' in semEsforco, false);
});

test('trocarModeloDoCorpo: dialeto Gemini e entrada inválida são RECUSADOS com null (o modelo mora na URL)', () => {
  const g = montarCorpoIA(PROVEDORES.google, { ...base, modelo: 'gemini-3.5-flash-lite' });
  assert.equal(trocarModeloDoCorpo(PROVEDORES.google, g, 'gemini-2.5-flash-lite'), null);
  assert.equal(trocarModeloDoCorpo(PROVEDORES.openai, null, 'gpt-4o'), null);
  assert.equal(trocarModeloDoCorpo(PROVEDORES.openai, { a: 1 }, ''), null);
});

test('trocarModeloDoCorpo: corpo sem teto continua sem teto (não inventa limite)', () => {
  const sem = { model: 'gpt-5.6-luna', messages: [] };
  const out = trocarModeloDoCorpo(PROVEDORES.openai, sem, 'gpt-4o');
  assert.equal('max_tokens' in out || 'max_completion_tokens' in out, false);
});

// --- declaração: a reserva tem preço e capacidade, e o Google não tem reserva -------
test('a reserva declarada tem preço e capacidade declarados; provedor sem reserva declara null', () => {
  for (const [id, m] of Object.entries(MODELOS_POR_PROVEDOR)) {
    assert.ok('extracao_reserva' in m, `${id}: declare extracao_reserva (null = sem reserva)`);
    if (m.extracao_reserva === null) continue;
    assert.ok(PRECOS_POR_PROVEDOR[id][m.extracao_reserva], `${id}: reserva sem preço custearia null e o custo sumiria`);
    assert.ok(!String(PROVEDORES[id].url).includes('{modelo}'), `${id}: URL com {modelo} não admite reserva por troca de corpo`);
  }
  assert.equal(MODELOS_POR_PROVEDOR.google.extracao_reserva, null);
  assert.equal(MODELOS_POR_PROVEDOR.openai.extracao_reserva, 'gpt-4o');
});

test('decidirRepeticao: reserva só após esgotar a transitória; permanente não cai nela, exceto modelo indisponível', () => {
  const d = (o) => decidirRepeticao({ temReserva: true, ...o });
  assert.equal(d({ transitoria: true, tentativa: 3 }).repetir, true);
  assert.equal(d({ transitoria: true, tentativa: 3 }).usarReserva, false, 'sobra tentativa: repete o principal');
  const r4 = d({ transitoria: true, tentativa: 4 });
  assert.deepEqual([r4.repetir, r4.usarReserva, r4.esgotou, r4.esperaS], [false, true, false, 60]);
  const r5 = d({ transitoria: true, tentativa: 5, emReserva: true });
  assert.deepEqual([r5.repetir, r5.usarReserva, r5.esgotou], [false, false, true], 'a reserva é UMA só');
  for (const tentativa of [1, 4]) {
    const p = d({ transitoria: false, tentativa });
    assert.equal(p.usarReserva, false, 'crédito/chave/400 são iguais para o outro modelo');
    assert.equal(p.esgotou, false);
  }
  const m404 = d({ transitoria: false, tentativa: 1, modeloIndisponivel: true });
  assert.deepEqual([m404.usarReserva, m404.esperaS], [true, 0], '404 do modelo: a reserva conserta, sem espera');
  assert.equal(d({ transitoria: false, tentativa: 2, modeloIndisponivel: true, emReserva: true }).usarReserva, false);
  assert.equal(decidirRepeticao({ transitoria: true, tentativa: 4 }).usarReserva, false, 'sem reserva: o comportamento antigo');
  assert.equal(decidirRepeticao({ transitoria: true, tentativa: 4 }).esgotou, true);
});

// --- o grafo real -----------------------------------------------------------------
const okJson = JSON.stringify({
  moeda: 'BRL', unidade: 'R$ mil',
  diagnostico: { entidade: 'Moto Agricola Ltda.', tipo_confirma: true, tipo_sugerido: 'BALANCO', periodo_tipo: 'anual',
    periodo_referencia: '2023', legibilidade: 'ok', nota_legibilidade: null, resumo: 'BP.', justificativa: 'Uma coluna.' },
  grupos: [{ s: 'Ativo Circulante', sc: 'ativo_circulante', op: 1, cols: [{ ec: null, pc: '31/12/2023' }],
    l: [{ k: 'Caixa', vt: ['380'], vn: [380], cf: 0.98 }, { k: 'Estoques', vt: ['10'], vn: [10], cf: 0.98 }] }],
});
const USO = { prompt_tokens: 10_000, completion_tokens: 2_000, prompt_tokens_details: { cached_tokens: 0 } };
const OK = () => ({ choices: [{ message: { content: okJson }, finish_reason: 'stop' }], usage: USO });
const RATE = () => ({ error: { message: 'Rate limit reached for model on tokens per min (TPM): Limit 500000. Please try again in 6.8s.', type: 'tokens', code: 'rate_limit_exceeded' } });
const SERVIDOR = () => ({ error: { message: 'The server had an error while processing your request', type: 'server_error' } });
const SEM_CREDITO = () => ({ error: { message: 'You exceeded your current quota', type: 'insufficient_quota', code: 'insufficient_quota' } });
const SEM_MODELO = () => ({ error: { message: 'The model `gpt-5.6-luna` does not exist or you do not have access to it.', type: 'invalid_request_error', code: 'model_not_found' } });

async function rodarNo(nome, { item, items, refs, esperas }) {
  const $ = (ref) => {
    if (!(ref in refs)) throw new Error(`Referência não mockada: $('${ref}')`);
    return { item: refs[ref], first: () => refs[ref], all: () => [refs[ref]] };
  };
  const $input = { item, first: () => (items ? items[0] : item), all: () => items || [item] };
  const fn = new AsyncFunction('$input', '$', '$json', 'setTimeout', porNome[nome].parameters.jsCode);
  return fn.call({}, $input, $, item ? item.json : undefined, (f, ms) => { esperas.push(ms); f(); return 0; });
}
const seguinte = (nome, saida = 0) => wf.connections[nome].main[saida].map((c) => c.node);

/** `respostas[i]` é o que o provedor devolve na chamada i+1 (além do fim, repete a última). Devolve também os corpos enviados. */
async function atravessar(respostas, { ctx = {} } = {}) {
  const corpo = montarCorpoIA(PROV, { ...base, modelo: MODELO_EXTRACAO, esforco: null });
  const refs = { 'Fatiar Extracao': { json: { documento_id: 'doc-1', documento_versao_id: 'ver-1', bloco: 3, blocos: 4,
    contas_no_documento: 2, ia_body: corpo, ...ctx } } };
  const esperas = [];
  const enviados = [];
  let chamadas = 0;
  let nomeParse = 'Parse Extracao';
  let corpoDaVez = refs['Fatiar Extracao'].json.ia_body;
  for (;;) {
    const r = respostas[Math.min(chamadas, respostas.length - 1)];
    enviados.push(corpoDaVez);
    chamadas += 1;
    const saida = await rodarNo(nomeParse, { item: { json: r }, refs, esperas });
    const [proximo] = seguinte(nomeParse);
    if (proximo === 'Juntar Tentativas' || saida.json.repetir !== true) return { saida, chamadas, esperas, enviados };
    const [esperar] = seguinte(proximo, 0);
    const aposEsperar = await rodarNo(esperar, { items: [saida], refs, esperas });
    refs[esperar] = { json: aposEsperar[0].json };
    corpoDaVez = aposEsperar[0].json.ia_body;
    [nomeParse] = seguinte(seguinte(esperar)[0]);
  }
}
const precoDe = (modelo) => custoDaChamada(USO, modelo);

test('ACEITE: principal falha transitório 4x e a reserva responde ok -> campos, usou_reserva, 5 tentativas, custo da 5a pelo preço do 4o', { skip: !aplicavel }, async () => {
  const r = await atravessar([RATE(), RATE(), SERVIDOR(), RATE(), OK()]);
  const j = r.saida.json;
  assert.equal(r.chamadas, 5);
  assert.equal(j.campos.length, 2, 'o bloco termina COM as linhas');
  assert.equal(j.falha_motivo, null, 'leitura recuperada pela reserva não abre pendência');
  assert.equal(j.usou_reserva, true);
  assert.equal(j.falha_transitoria, false);
  assert.deepEqual(j.registro_tentativas, [
    { tentativa: 1, modelo: MODELO_EXTRACAO, resultado: 'falhou_transitoria', reserva: false },
    { tentativa: 2, modelo: MODELO_EXTRACAO, resultado: 'falhou_transitoria', reserva: false },
    { tentativa: 3, modelo: MODELO_EXTRACAO, resultado: 'falhou_transitoria', reserva: false },
    { tentativa: 4, modelo: MODELO_EXTRACAO, resultado: 'falhou_transitoria', reserva: false },
    { tentativa: 5, modelo: RESERVA, resultado: 'ok', reserva: true },
  ]);
  // o corpo que FOI ao provedor: 4 com o principal, a 5a com o da reserva no dialeto dela
  assert.deepEqual(r.enviados.slice(0, 4).map((c) => c.model), Array(4).fill(MODELO_EXTRACAO));
  assert.equal(r.enviados[4].model, RESERVA);
  assert.deepEqual(r.enviados[4], trocarModeloDoCorpo(PROV, r.enviados[0], RESERVA));
  assert.deepEqual(r.esperas, [30_000, 60_000, 60_000, 60_000]);
  // CUSTO: só a 5a respondeu com usage, e vale o preço do modelo que RESPONDEU
  assert.equal(j.custo_usd, precoDe(RESERVA));
  assert.ok(j.custo_usd > precoDe(MODELO_EXTRACAO) * 5, 'cobrar como o principal subestimaria a chamada');
  assert.equal(j.modelo_efetivo, RESERVA);
});

test('ACEITE (o oposto): a reserva TAMBÉM falha -> falha_transitoria, e o motivo diz que a reserva rodou e o que deu', { skip: !aplicavel }, async () => {
  const r = await atravessar([RATE()]);
  const j = r.saida.json;
  assert.equal(r.chamadas, 5);
  assert.equal(j.campos.length, 0);
  assert.equal(j.falha_transitoria, true);
  assert.equal(j.usou_reserva, true);
  assert.equal(j.registro_tentativas.at(-1).resultado, 'falhou_transitoria');
  assert.equal(j.registro_tentativas.at(-1).reserva, true);
  assert.match(j.falha_motivo, new RegExp(`Reserva ${RESERVA} rodou na tentativa 5`));
  assert.match(j.falha_motivo, /falhou_transitoria/);
  assert.match(j.falha_motivo, /Ultima falha do principal/, 'a causa do principal não some atrás da da reserva');
  assert.match(j.falha_motivo, /teto de 4 tentativas do principal \+ 1 da reserva ESGOTADO/);
  assert.equal(j.custo_usd, 0, 'chamada que falhou sem usage não tem custo medido');
});

test('permanente (crédito) NÃO cai na reserva: 1 chamada, registro permanente, sem falha_transitoria', { skip: !aplicavel }, async () => {
  const r = await atravessar([SEM_CREDITO(), OK()]);
  const j = r.saida.json;
  assert.equal(r.chamadas, 1);
  assert.equal(j.usou_reserva, false);
  assert.equal(j.falha_transitoria, false);
  assert.deepEqual(j.registro_tentativas, [{ tentativa: 1, modelo: MODELO_EXTRACAO, resultado: 'falhou_permanente', reserva: false }]);
});

test('modelo indisponível (404 do principal) VAI à reserva sem esperar, e a reserva lê', { skip: !aplicavel }, async () => {
  const r = await atravessar([SEM_MODELO(), OK()]);
  const j = r.saida.json;
  assert.equal(r.chamadas, 2);
  assert.deepEqual(r.esperas, [], 'a causa é determinística: esperar não muda');
  assert.equal(j.campos.length, 2);
  assert.equal(j.usou_reserva, true);
  assert.deepEqual(j.registro_tentativas.map((x) => [x.modelo, x.resultado, x.reserva]),
    [[MODELO_EXTRACAO, 'falhou_permanente', false], [RESERVA, 'ok', true]]);
  assert.equal(j.custo_usd, precoDe(RESERVA));
});

test('modelo indisponível também na reserva: para (sem laço), permanente, sem falha_transitoria', { skip: !aplicavel }, async () => {
  const r = await atravessar([SEM_MODELO()]);
  assert.equal(r.chamadas, 2, 'principal + reserva, nada mais');
  assert.equal(r.saida.json.falha_transitoria, false);
  assert.match(r.saida.json.falha_motivo, /MODELO INDISPONÍVEL/);
});

test('sucesso na 1a tentativa: uma entrada ok, sem reserva, custo do principal', { skip: !aplicavel }, async () => {
  const r = await atravessar([OK()]);
  const j = r.saida.json;
  assert.equal(r.chamadas, 1);
  assert.equal(j.usou_reserva, false);
  assert.deepEqual(j.registro_tentativas.map((x) => x.resultado), ['ok']);
  assert.equal(j.custo_usd, precoDe(MODELO_EXTRACAO));
});

// --- da medição do bloco à medição do documento (o que chega em p_medicao) ----------
async function medicaoDoDocumento(blocos) {
  const out = await rodarNo('Juntar Blocos', { items: blocos.map((b) => ({ json: { documento_versao_id: 'v1', blocos: blocos.length, contas_no_documento: null, diagnostico: {}, ...b } })), refs: {}, esperas: [] });
  const q = porNome['Gravar Campos (Sombra)'].parameters.options.queryReplacement;
  const params = new Function('$json', 'return (' + q.replace(/^=\{\{/, '').replace(/\}\}$/, '') + ')')(out[0].json);
  return { medicao: JSON.parse(params[6]), doc: out[0].json };
}
const bloco = (n, extra = {}) => ({ bloco: n, campos: [{ ordem: 0, chave: `C${n}`, valor_num: 1, valor_texto: '1', entidade_coluna: null, periodo_coluna: null }],
  falha_motivo: null, custo_usd: 0.01, tokens: { entrada: 1, saida: 1, cache: 0 }, ...extra });
const reg = (...e) => e.map(([tentativa, modelo, resultado, reserva = false]) => ({ tentativa, modelo, resultado, reserva }));

test('medicao_documento leva modelos_usados, usou_reserva e falha_transitoria_esgotada ATÉ o p_medicao do Gravar Campos', async () => {
  const { medicao } = await medicaoDoDocumento([
    bloco(1, { registro_tentativas: reg([1, 'A', 'ok']), falha_transitoria: false }),
    bloco(2, { registro_tentativas: reg([1, 'A', 'falhou_transitoria'], [2, 'A', 'falhou_transitoria'], [3, 'A', 'falhou_transitoria'], [4, 'A', 'falhou_transitoria'], [5, 'B', 'ok', true]), falha_transitoria: false }),
  ]);
  assert.equal(medicao.versao_medicao, 'p4-2');
  assert.deepEqual(medicao.modelos_usados, ['A', 'B']);
  assert.equal(medicao.usou_reserva, true);
  assert.equal(medicao.falha_transitoria_esgotada, false);
  assert.equal(medicao.registro_tentativas.length, 5, 'só o bloco que repetiu entra no detalhe; o bloco de 1 chamada ok não');
  assert.ok(medicao.registro_tentativas.every((x) => x.bloco === 2));
});

test('falha_transitoria_esgotada = algum bloco terminou transitório mesmo depois da reserva', async () => {
  const { medicao } = await medicaoDoDocumento([
    bloco(1, { registro_tentativas: reg([1, 'A', 'ok']), falha_transitoria: false }),
    bloco(2, { campos: [], tokens: null, custo_usd: 0, falha_motivo: 'x',
      registro_tentativas: reg([4, 'A', 'falhou_transitoria'], [5, 'B', 'falhou_transitoria', true]), falha_transitoria: true }),
  ]);
  assert.equal(medicao.falha_transitoria_esgotada, true);
  assert.equal(medicao.usou_reserva, true);
});

test('bloco vindo de n8n anterior (sem registro) NÃO vira usou_reserva:false — os três campos ficam ausentes (regra 1)', async () => {
  const { medicao } = await medicaoDoDocumento([bloco(1)]);
  for (const k of ['modelos_usados', 'usou_reserva', 'falha_transitoria_esgotada', 'registro_tentativas']) {
    assert.equal(k in medicao, false, k);
  }
});

test('o JSON gerado: estágio extra da reserva existe, converge no Merge e o corpo de cada estágio é o que o Parse devolve', { skip: !aplicavel }, () => {
  assert.ok(porNome['IA Extrair (tentativa 5)'] && porNome['Parse Extracao (tentativa 5)'] && porNome['Esperar Retry 4']);
  assert.equal(porNome['Juntar Tentativas'].parameters.numberInputs, 5);
  assert.equal(porNome['IA Extrair (tentativa 5)'].parameters.url, PROV.url, 'mesmo endereço: a troca é no corpo');
  assert.equal(porNome['IA Extrair (tentativa 5)'].parameters.jsonBody, '={{ JSON.stringify($json.ia_body) }}');
});

// --- revisão independente: correções ALTO 1/2, MÉDIO 3/4, BAIXO 5 ---------------------
const BAD400 = () => ({ error: { message: 'maximum context length is 128000 tokens', type: 'invalid_request_error', code: 'context_length_exceeded' } });
const BAIXA = () => ({ choices: [{ message: { content: JSON.stringify({ moeda: 'BRL', unidade: 'R$ mil', diagnostico: { entidade: 'X', tipo_confirma: true, tipo_sugerido: 'BALANCO', periodo_tipo: 'anual', periodo_referencia: '2023', legibilidade: 'ok', resumo: 'x', justificativa: 'x' },
  grupos: [{ s: 'Ativo', sc: 'ativo_circulante', op: 1, cols: [{ ec: null, pc: '2023' }], l: Array.from({ length: 59 }, (_, i) => ({ k: `C${i}`, vt: ['1'], vn: [1], cf: 0.9 })) }] }) }, finish_reason: 'stop' }], usage: USO });

test('ALTO 1: principal 4x transitório + reserva 400 permanente -> falha_transitoria (o principal leria no reenvio)', { skip: !aplicavel }, async () => {
  const r = await atravessar([RATE(), RATE(), RATE(), RATE(), BAD400()]);
  const j = r.saida.json;
  assert.equal(r.chamadas, 5);
  assert.equal(j.registro_tentativas.at(-1).resultado, 'falhou_permanente');
  assert.equal(j.falha_transitoria, true);
  const { medicao } = await medicaoDoDocumento([bloco(1, { campos: [], tokens: null, custo_usd: 0, falha_motivo: 'x', registro_tentativas: j.registro_tentativas, falha_transitoria: j.falha_transitoria })]);
  assert.equal(medicao.falha_transitoria_esgotada, true);
});

test('ALTO 1 (contraprova): 404 no principal + reserva 400 NÃO é transitório (nenhuma chamada foi do provedor-fora)', { skip: !aplicavel }, async () => {
  const r = await atravessar([SEM_MODELO(), BAD400()]);
  assert.equal(r.saida.json.falha_transitoria, false);
});

test('ALTO 2/MÉDIO 4: reserva por 404 que LÊ fica visível no Resumo de Custo (sem abrir pendência)', { skip: !aplicavel }, async () => {
  const r = await atravessar([SEM_MODELO(), OK()]);
  assert.equal(r.saida.json.falha_motivo, null, 'não abre pendência de extração falha');
  assert.equal(r.saida.json.reserva_motivo, 'modelo_indisponivel');
  const { medicao, doc } = await medicaoDoDocumento([bloco(1, { registro_tentativas: r.saida.json.registro_tentativas, falha_transitoria: false, reserva_motivo: 'modelo_indisponivel' })]);
  assert.equal(medicao.reserva_por_modelo_indisponivel, true);
  const out = await resumir([{ ...doc }]);
  assert.equal(out.documentos_com_reserva, 1);
  assert.equal(out.documentos_com_reserva_por_modelo_indisponivel, 1);
  assert.match(out.resumo, /RESERVA DE MODELO \(gpt-4o/);
  assert.match(out.resumo, /MODELO PRINCIPAL INDISPONIVEL \(404\): conferir MODELOS_POR_PROVEDOR/);
});

test('MÉDIO 4: reserva por transitória conta em documentos_com_reserva mas NÃO como modelo indisponível; sem reserva, resumo sem o trecho', { skip: !aplicavel }, async () => {
  const comR = await medicaoDoDocumento([bloco(1, { registro_tentativas: reg([4, 'A', 'falhou_transitoria'], [5, 'B', 'ok', true]), falha_transitoria: false, reserva_motivo: 'transitoria' })]);
  const o = await resumir([comR.doc]);
  assert.equal(o.documentos_com_reserva, 1);
  assert.equal(o.documentos_com_reserva_por_modelo_indisponivel, 0);
  assert.doesNotMatch(o.resumo, /MODELO PRINCIPAL INDISPONIVEL/);
  const sem = await medicaoDoDocumento([bloco(1, { registro_tentativas: reg([1, 'A', 'ok']), falha_transitoria: false })]);
  const o2 = await resumir([sem.doc]);
  assert.equal(o2.documentos_com_reserva, 0);
  assert.doesNotMatch(o2.resumo, /RESERVA DE MODELO/);
});

test('MÉDIO 3: reserva (por 404) que lê com cobertura baixa NÃO é refeita — a reserva roda uma vez só', { skip: !aplicavel }, async () => {
  const r = await atravessar([SEM_MODELO(), BAIXA(), BAIXA()], { ctx: { contas_do_bloco: 100 } });
  assert.equal(r.chamadas, 2, 'principal 404 + reserva; nenhuma segunda passada');
  assert.equal(r.enviados.filter((c) => c.model === RESERVA).length, 1);
  assert.match(r.saida.json.falha_motivo, /ja foi lido pela reserva/);
});

test('BAIXO 5: modelo_efetivo é o da passada que FICOU (a 2a passada pior perde para a 1a)', { skip: !aplicavel }, async () => {
  // 1a (principal): 59 de 100 linhas -> refaz; a 2a devolve menos e a 1a fica
  const menos = () => ({ choices: [{ message: { content: JSON.stringify({ moeda: 'BRL', unidade: 'R$ mil', diagnostico: { entidade: 'X', tipo_confirma: true, tipo_sugerido: 'BALANCO', periodo_tipo: 'anual', periodo_referencia: '2023', legibilidade: 'ok', resumo: 'x', justificativa: 'x' },
    grupos: [{ s: 'Ativo', sc: 'ativo_circulante', op: 1, cols: [{ ec: null, pc: '2023' }], l: [{ k: 'Z', vt: ['1'], vn: [1], cf: 0.9 }] }] }) }, finish_reason: 'stop' }], usage: USO });
  const r = await atravessar([BAIXA(), RATE(), RATE(), RATE(), menos()], { ctx: { contas_do_bloco: 100 } });
  assert.equal(r.saida.json.registro_tentativas.at(-1).modelo, RESERVA, 'a última chamada foi do 4o');
  assert.equal(r.saida.json.campos.length, 59, 'ficou a 1a passada');
  assert.equal(r.saida.json.modelo_efetivo, MODELO_EXTRACAO, 'quem leu o que ficou foi o principal');
});

/** Roda o `Resumo de Custo` real com os itens de `Juntar Blocos` fornecidos. */
async function resumir(docs) {
  const ref = (nome) => ({
    all: (_i, run) => (nome === 'Juntar Blocos' && run === 0 ? docs.map((d) => ({ json: d })) : (run === 0 && nome === 'Orcamento do Lote' ? [{ json: {} }] : [])),
    first: () => ({ json: {} }), isExecuted: false, item: { json: {} },
  });
  const fn = new AsyncFunction('$input', '$', porNome['Resumo de Custo'].parameters.jsCode);
  const out = await fn({ all: () => [] }, ref);
  return out[0].json;
}
