import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SERIES_MACRO, INDICADORES_FOCUS, numeroMacro } from '../lib/macro.mjs';

// Executa os códigos REAIS dos nós Code do workflow gerado, com a semântica do
// N8N ($input/$json/$()). O mesmo padrão de `workflow-sim.test.mjs`: o mirror
// dentro do JSON é o que roda em produção, então é ELE que precisa ser testado
// — testar só a lib deixaria o mirror livre para divergir, que é exatamente o
// bug que este repositório já teve.
const __dirname = dirname(fileURLToPath(import.meta.url));
const workflow = JSON.parse(readFileSync(join(__dirname, '..', 'workflow.macro.json'), 'utf8'));
const nodeDe = (nome) => workflow.nodes.find((n) => n.name === nome);

function rodarCode(nome, { itens = [], porNome = {}, todosPorNome = {} } = {}) {
  const n = nodeDe(nome);
  assert.ok(n, `nó ${nome} não existe no workflow gerado`);
  const $input = { all: () => itens.map((json) => ({ json })) };
  const $ = (outro) => ({
    item: { json: porNome[outro] },
    all: () => (todosPorNome[outro] ?? []).map((json) => ({ json })),
  });
  const fn = new Function('$input', '$', '$json', `${n.parameters.jsCode}`);
  if (n.parameters.mode === 'runOnceForEachItem') {
    return itens.map((json) => fn($input, $, json));
  }
  return fn($input, $, itens[0]);
}

test('workflow macro: agenda DIÁRIA, na mesma hora de antes (06h)', () => {
  // Decisão do dono (25/11/2026): era mensal no dia 12. Medido no mesmo dia: o IPCA de
  // outubro já estava no SGS e só entraria em 12/12. Diário também é o que faz a ausência
  // de uma consulta no banco significar "não rodou" (regra 7).
  const t = nodeDe('Agenda Diária');
  assert.ok(t, 'o gatilho tem de existir com o nome novo');
  assert.equal(nodeDe('Agenda Mensal'), undefined, 'sobrou o gatilho mensal');
  const regra = t.parameters.rule.interval;
  assert.equal(regra.length, 1);
  assert.equal(regra[0].field, 'days');
  assert.equal(regra[0].daysInterval, 1);
  assert.equal(regra[0].triggerAtHour, 6);
  assert.equal(regra[0].triggerAtDayOfMonth, undefined, 'dia do mês fixo faria a agenda voltar a mensal');
});

test('workflow macro: toda série do catálogo entra na coleta', () => {
  const gerado = rodarCode('Séries a Coletar');
  assert.equal(gerado.length, SERIES_MACRO.length);
  for (const s of SERIES_MACRO) {
    const item = gerado.find((g) => g.json.__serie === s.codigo);
    assert.ok(item, `série ${s.codigo} ficou de fora da coleta`);
    assert.match(item.json.__url, new RegExp(`bcdata\\.sgs\\.${s.sgs}/`));
  }
  const focus = rodarCode('Indicadores Focus');
  assert.equal(focus.length, INDICADORES_FOCUS.length);
  // O filtro tem de ir codificado, senão o OData recusa a query.
  assert.ok(focus.every((f) => f.json.__url.includes('Indicador%20eq%20')));
});

test('workflow macro: normaliza SGS e SIDRA no MESMO formato de gravação', () => {
  // Respostas reais das duas APIs (2026-07-28), reduzidas.
  const saida = rodarCode('Normalizar Observações', {
    itens: [
      { __serie: 'IPCA', __fonte: 'BCB/SGS', __corpo: [
        { data: '01/01/2026', valor: '0.33' },
        { data: '01/02/2026', valor: '0.70' },
      ] },
      { __serie: 'IPCA', __fonte: 'IBGE/SIDRA', __corpo: [
        { NC: 'Nível Territorial (Código)', V: 'Valor', D3C: 'Mês (Código)' }, // cabeçalho
        { NC: '1', V: '0.33', D3C: '202601' },
      ] },
      { __serie: 'CAMBIO_USD', __fonte: 'BCB/SGS', __corpo: [{ data: '30/06/2026', valor: '5,4321' }] },
    ],
  });
  const obs = saida[0].json.observacoes;
  assert.equal(obs.length, 4);

  const sgs = obs.find((o) => o.fonte === 'BCB/SGS' && o.data_ref === '2026-01-01');
  assert.deepEqual(sgs, { serie: 'IPCA', fonte: 'BCB/SGS', data_ref: '2026-01-01', valor: 0.33 });

  // A linha de cabeçalho do SIDRA não pode virar observação.
  const ibge = obs.filter((o) => o.fonte === 'IBGE/SIDRA');
  assert.equal(ibge.length, 1);
  assert.equal(ibge[0].data_ref, '2026-01-01');
  assert.equal(ibge[0].valor, 0.33);

  // As duas fontes coexistem no mesmo mês — é isso que permite conferir.
  assert.equal(obs.filter((o) => o.serie === 'IPCA' && o.data_ref === '2026-01-01').length, 2);

  // Vírgula decimal (aparece em série antiga) não pode virar NaN e sumir.
  assert.equal(obs.find((o) => o.serie === 'CAMBIO_USD').valor, 5.4321);
});

test('workflow macro: observação sem data ou sem valor é descartada, não gravada torta', () => {
  const saida = rodarCode('Normalizar Observações', {
    itens: [{ __serie: 'IPCA', __fonte: 'BCB/SGS', __corpo: [
      { data: 'jan/26', valor: '1.0' },   // data ilegível
      { data: '01/03/2026', valor: '' },  // valor ausente
      { data: '01/04/2026', valor: '0.42' },
    ] }],
  });
  const obs = saida[0].json.observacoes;
  assert.equal(obs.length, 1, 'só a observação íntegra deveria passar');
  assert.equal(obs[0].data_ref, '2026-04-01');
});

test('workflow macro: Focus fica só na coleta mais recente (uma linha por ano)', () => {
  const saida = rodarCode('Normalizar Focus', {
    itens: [{ __serie: 'IPCA', __corpo: { value: [
      { Data: '2026-07-24', DataReferencia: '2026', Mediana: 5.1209, Media: 5.13, numeroRespondentes: 151 },
      { Data: '2026-07-24', DataReferencia: '2027', Mediana: 4.5, Media: 4.51, numeroRespondentes: 148 },
      { Data: '2026-07-17', DataReferencia: '2026', Mediana: 5.28, Media: 5.3, numeroRespondentes: 149 },
    ] } }],
  });
  const exp = saida[0].json.expectativas;
  assert.equal(exp.length, 2);
  const y26 = exp.find((e) => e.ano_ref === 2026);
  assert.equal(y26.mediana, 5.1209, 'pegou a coleta antiga em vez da mais recente');
  assert.equal(y26.coletado_em, '2026-07-24');
  // Sem a data de coleta a projeção deixa de ser reproduzível.
  assert.ok(exp.every((e) => e.coletado_em));
});

test('workflow macro: grava pelas funções da 0025 e confere as fontes', () => {
  assert.match(nodeDe('Gravar Índices').parameters.query, /fn_registrar_indice_macro/);
  assert.match(nodeDe('Gravar Expectativas').parameters.query, /fn_registrar_expectativa_macro/);
  assert.match(nodeDe('Conferir Fontes').parameters.query, /fn_divergencias_indice_macro/);
});

test('workflow macro: uma fonte fora do ar não derruba as outras', () => {
  // As três APIs são públicas e caem. Sem tolerância a erro, a queda de uma
  // interrompe a execução e o mês inteiro se perde — sendo que a ingestão é
  // idempotente e o mês voltaria sozinho na coleta seguinte.
  for (const nome of ['BCB SGS', 'IBGE SIDRA (IPCA)', 'BCB Focus']) {
    const n = nodeDe(nome);
    assert.equal(n.onError, 'continueRegularOutput', `${nome} sem tolerância a erro`);
    assert.equal(n.retryOnFail, true, `${nome} sem retry`);
  }
});

// --- O runtime REAL do n8n: o nó HTTP explode array em N itens ----------------
// Este é o teste que faltava, e a razão pela qual a perda total de 6 séries
// passava verde. O nó HTTP Request do n8n, ao receber uma resposta JSON que é um
// ARRAY, devolve um item por elemento. O SGS responde `[{data,valor}, …×132]`,
// então `Manter Contexto SGS` (que é `runOnceForEachItem`) recebe UM OBJETO por
// item — nunca o array inteiro.
//
// O teste antigo injetava `__corpo` já como array, um modelo que não corresponde
// ao runtime. Com isso, `if (!Array.isArray(corpo)) continue` parecia inofensivo
// aqui e descartava ~792 itens em produção, calado. O ramo IBGE/SIDRA sobrevivia
// porque é UMA requisição e o nó anterior remonta o array explicitamente — a
// assimetria entre os dois ramos era o sintoma à vista.
test('SGS: o split do nó HTTP (um item por observação) NÃO perde dado', () => {
  // É assim que os itens chegam de verdade: 6 séries × N observações, cada item
  // com `__corpo` sendo UMA observação e o `__serie` correto vindo do pareamento.
  const itens = [];
  for (const s of ['IPCA', 'SELIC', 'CDI']) {
    for (const [data, valor] of [['01/01/2026', '0.33'], ['01/02/2026', '0.70'], ['01/03/2026', '0.51']]) {
      itens.push({ __serie: s, __fonte: 'BCB/SGS', __corpo: { data, valor } });
    }
  }
  const saida = rodarCode('Normalizar Observações', { itens });
  const obs = saida[0].json.observacoes;
  assert.equal(obs.length, 9, 'as 9 observações do split foram normalizadas');
  assert.equal(saida[0].json.descartados, 0, 'nenhum item foi descartado');
  // Cada observação mantém a SÉRIE do seu item — é por isso que não se remonta o
  // array aqui: o pareamento do n8n já resolveu de qual requisição o item veio.
  for (const s of ['IPCA', 'SELIC', 'CDI']) {
    assert.equal(obs.filter((o) => o.serie === s).length, 3, `série ${s} preservada no split`);
  }
  assert.deepEqual(obs[0], { serie: 'IPCA', fonte: 'BCB/SGS', data_ref: '2026-01-01', valor: 0.33 });
});

// Corpo de ERRO da API também é um objeto único. Envolvê-lo num array faria a
// falha virar "zero observações" — o mesmo silêncio, por outra porta. Só o que tem
// CARA de observação é aceito, e o resto é CONTADO.
test('SGS: corpo de erro da API não é confundido com observação, e é contado', () => {
  const saida = rodarCode('Normalizar Observações', {
    itens: [
      { __serie: 'IPCA', __fonte: 'BCB/SGS', __corpo: { data: '01/01/2026', valor: '0.33' } },
      // com `neverError`, uma falha da API chega como CORPO, não como exceção
      { __serie: 'SELIC', __fonte: 'BCB/SGS', __corpo: { error: 'Bad Request', status: 400 } },
      { __serie: 'CDI', __fonte: 'BCB/SGS', __corpo: 'erro em texto puro' },
      { __serie: 'IGPM', __fonte: 'BCB/SGS', __corpo: null },
    ],
  });
  assert.equal(saida[0].json.observacoes.length, 1, 'só a observação de verdade entra');
  assert.equal(saida[0].json.descartados, 3, 'os três corpos inválidos são contados, não engolidos');
});

test('SGS: array inteiro (caso do SIDRA e de instância sem split) continua funcionando', () => {
  const saida = rodarCode('Normalizar Observações', {
    itens: [{ __serie: 'IPCA', __fonte: 'BCB/SGS', __corpo: [
      { data: '01/01/2026', valor: '0.33' }, { data: '01/02/2026', valor: '0.70' },
    ] }],
  });
  assert.equal(saida[0].json.observacoes.length, 2, 'a forma de array não regrediu');
  assert.equal(saida[0].json.descartados, 0);
});

// --- Anti-drift: o Focus usa o MESMO numeroMacro da lib ----------------------
// Era o último mirror manual do repositório, e tinha divergido: o nó fazia
// `typeof l.Mediana === 'number'`, rejeitando qualquer string — inclusive "4.50".
test('Normalizar Focus carrega o MESMO numeroMacro de lib/macro.mjs', () => {
  const codigo = nodeDe('Normalizar Focus').parameters.jsCode;
  assert.ok(codigo.includes(numeroMacro.toString()),
    'a conversão numérica embutida no nó divergiu da fonte em lib/macro.mjs');
});

test('Focus: decimal como STRING é aceito (era o que zerava o ramo inteiro)', () => {
  // Se o Olinda passar a serializar decimal como string — hoje ele devolve número —
  // o nó antigo descartaria TODA linha e as premissas de inflação/juro da aba
  // Modelagem iriam a 0%, sem erro em lugar nenhum.
  const saida = rodarCode('Normalizar Focus', {
    itens: [{ __serie: 'IPCA', __corpo: { value: [
      { Data: '2026-07-24', DataReferencia: '2026', Mediana: '4.50', Media: '4,52', numeroRespondentes: '151' },
      { Data: '2026-07-24', DataReferencia: '2027', Mediana: 3.9, Media: 3.88, numeroRespondentes: 148 },
      { Data: '2026-07-17', DataReferencia: '2026', Mediana: '9.99', Media: '9.99', numeroRespondentes: '10' },
    ] } }],
  });
  const exp = saida[0].json.expectativas;
  assert.equal(exp.length, 2, 'só o boletim mais recente entra, e as duas linhas dele passam');
  const y2026 = exp.find((e) => e.ano_ref === 2026);
  assert.equal(y2026.mediana, 4.5, 'decimal com ponto vindo como string');
  assert.equal(y2026.media, 4.52, 'decimal com VÍRGULA vindo como string');
  assert.equal(y2026.respondentes, 151, 'inteiro como string');
  assert.equal(exp.find((e) => e.ano_ref === 2027).mediana, 3.9, 'número continua funcionando');
});

// --- A coleta falha ALTO em vez de gravar zero --------------------------------
// Antes, os dois normalizadores terminavam em `return {n: 0}` e NUNCA lançavam:
// com `neverError` nos HTTP, falha de API virava corpo de erro, o `continue`
// engolia, a função do banco recebia `'[]'` e devolvia `0,0` — e a execução
// AGENDADA fechava verde. O workflow roda dia 12; ninguém olha execução verde.
test('coleta de observações LANÇA quando nada foi lido, e diz o que viu', () => {
  assert.throws(
    () => rodarCode('Normalizar Observações', {
      itens: [
        { __serie: 'IPCA', __fonte: 'BCB/SGS', __corpo: { error: 'Bad Request', status: 400 } },
        { __serie: 'SELIC', __fonte: 'BCB/SGS', __corpo: { error: 'Bad Request', status: 400 } },
      ],
    }),
    (e) => {
      assert.match(e.message, /NAO trouxe observacao nenhuma/);
      // A mensagem tem de carregar o que foi VISTO, não só o que faltou — sem isso
      // o próximo diagnóstico recomeça do zero, que foi o custo do teste v30.
      assert.match(e.message, /Itens recebidos: 2/, 'diz quantos itens chegaram');
      assert.match(e.message, /descartados: 2/, 'diz quantos foram descartados');
      assert.match(e.message, /Bad Request/, 'inclui amostra do corpo recebido');
      assert.match(e.message, /SGS devolve 132 meses/, 'explica por que zero não é legítimo');
      return true;
    },
  );
});

test('coleta do Focus LANÇA quando nada foi lido', () => {
  assert.throws(
    () => rodarCode('Normalizar Focus', {
      itens: [{ __serie: 'IPCA', __corpo: { error: 'service unavailable' } }],
    }),
    (e) => {
      assert.match(e.message, /Focus NAO trouxe nada/);
      assert.match(e.message, /service unavailable/, 'inclui amostra do corpo');
      assert.match(e.message, /boletim semanal/, 'explica por que zero não é legítimo');
      return true;
    },
  );
});

// E o caminho normal NÃO lança — um throw que dispara em operação normal seria
// pior que o silêncio, porque treina quem opera a ignorar o alarme.
test('coleta com dado válido não lança', () => {
  const obs = rodarCode('Normalizar Observações', {
    itens: [{ __serie: 'IPCA', __fonte: 'BCB/SGS', __corpo: { data: '01/01/2026', valor: '0.33' } }],
  });
  assert.equal(obs[0].json.n, 1);
  const foc = rodarCode('Normalizar Focus', {
    itens: [{ __serie: 'IPCA', __corpo: { value: [
      { Data: '2026-07-24', DataReferencia: '2026', Mediana: 4.5, Media: 4.5, numeroRespondentes: 151 },
    ] } }],
  });
  assert.equal(foc[0].json.n, 1);
});


// --- A3 fatia 0: cada chamada HTTP registra o desfecho CRU na fn_registrar_consulta_externa ---
// INVARIANTE (comportamento, não mecanismo): uma fonte derrubada NUNCA chega ao banco como
// "2xx com lista vazia" (que a função grava como nada_encontrado). Queda de HTTP, timeout e
// corpo vazio têm de chegar com o status/erro reais, e a falha de UMA série não pode ser
// escondida pelo sucesso das outras.
const SGS_OK = JSON.stringify([{ data: '01/08/2026', valor: '0.10' }, { data: '01/09/2026', valor: '0.14' }]);
const resp = (statusCode, body) => ({ statusCode, statusMessage: '', headers: {}, body });

// O que o banco receberia de 'Ler SGS' para uma série, dada a resposta do nó HTTP.
const consultaSgsDe = (serie, httpJson) => rodarCode('Ler SGS', {
  itens: [httpJson], porNome: { 'Séries a Coletar': { __serie: serie } },
})[0].json.__consulta;

// Contrato de TODA consulta que o macro manda ao banco, de qualquer fonte.
function afirmarContrato(c, rotulo) {
  const dois = c.http_status >= 200 && c.http_status <= 299;
  if (dois && !c.erro) {
    assert.ok(Array.isArray(c.itens) && c.itens.length > 0, `${rotulo}: 2xx sem erro tem de trazer itens, nunca lista vazia`);
    assert.ok(typeof c.corpo === 'string' && c.corpo.trim() !== '', `${rotulo}: 2xx sem erro tem de trazer o corpo cru`);
  }
  if (c.http_status === null) assert.ok(c.erro, `${rotulo}: sem status HTTP tem de levar o erro`);
}

test('A3: Ler SGS - resposta boa vira consulta com RESUMO pequeno (1 item) e o corpo cru', () => {
  const c = consultaSgsDe('IPCA', resp(200, SGS_OK));
  assert.equal(c.fonte, 'bcb_sgs');
  assert.equal(c.http_status, 200);
  assert.equal(c.erro, null);
  assert.equal(c.corpo, SGS_OK, 'o hash é do texto exato');
  assert.deepEqual(c.itens, [{ chave: 'IPCA', valor: { ultimo_mes: '2026-09', n: 2 } }]);
  assert.equal(c.registros_lidos, 2);
  afirmarContrato(c, 'ok');
});

test('A3: SGS derrubado - 500, sem resposta, corpo vazio, não-JSON, lista vazia: NUNCA 2xx com itens []', () => {
  const casos = {
    'HTTP 500': [resp(500, '{"error":"x"}'), (c) => assert.equal(c.http_status, 500)],
    'HTTP 429': [resp(429, 'slow down'), (c) => assert.equal(c.http_status, 429)],
    'timeout / sem resposta': [{ error: { message: 'timeout of 60000ms exceeded' } },
      (c) => { assert.equal(c.http_status, null); assert.match(c.erro, /timeout of 60000ms/); }],
    '200 com corpo vazio': [resp(200, ''), (c) => assert.match(c.erro, /corpo vazio/)],
    '200 só com espaço': [resp(200, ' \n'), (c) => assert.match(c.erro, /corpo vazio/)],
    '200 que não é JSON': [resp(200, '<html>manutencao</html>'), (c) => assert.match(c.erro, /não é JSON/)],
    '200 com lista vazia': [resp(200, '[]'), (c) => assert.match(c.erro, /nenhuma observação válida/)],
    '200 com objeto de erro': [resp(200, '{"error":"Bad Request"}'), (c) => assert.match(c.erro, /não é a lista/)],
  };
  for (const [rotulo, [httpJson, extra]] of Object.entries(casos)) {
    const c = consultaSgsDe('SELIC', httpJson);
    afirmarContrato(c, rotulo);
    extra(c);
    const dois = c.http_status >= 200 && c.http_status <= 299;
    assert.ok(!(dois && !c.erro), `${rotulo}: chegaria ao banco como 2xx limpo`);
    assert.ok(!(dois && Array.isArray(c.itens) && c.itens.length === 0), `${rotulo}: 2xx com itens [] vira nada_encontrado`);
  }
});

test('A3: a falha de UMA série não é escondida pelo sucesso das outras (uma consulta por série)', () => {
  const series = SERIES_MACRO.map((s) => s.codigo);
  const consultas = series.map((s) => consultaSgsDe(s, s === 'CDI' ? resp(500, 'boom') : resp(200, SGS_OK)));
  assert.equal(consultas.length, 6);
  const falhas = consultas.filter((c) => c.http_status !== 200);
  assert.equal(falhas.length, 1);
  assert.equal(falhas[0].http_status, 500);
  consultas.forEach((c, i) => afirmarContrato(c, series[i]));
  assert.deepEqual(consultas.filter((c) => c.http_status === 200).map((c) => c.itens[0].chave).sort(),
    series.filter((s) => s !== 'CDI').sort());
});

test('A3: Focus - uma consulta por indicador, resumo da coleta mais recente; queda nunca vira 2xx vazio', () => {
  const rodar = (httpJson) => rodarCode('Ler Focus', {
    itens: [httpJson], porNome: { 'Indicadores Focus': { __serie: 'IPCA' } },
  })[0].json.__consulta;
  const corpo = JSON.stringify({ value: [
    { Data: '2026-11-21', DataReferencia: '2026', Mediana: 4.5 }, { Data: '2026-11-21', DataReferencia: '2027', Mediana: 4.0 },
    { Data: '2026-11-14', DataReferencia: '2026', Mediana: 4.6 },
  ] });
  const ok = rodar(resp(200, corpo));
  assert.equal(ok.fonte, 'bcb_focus');
  assert.deepEqual(ok.itens, [{ chave: 'IPCA', valor: { coletado_em: '2026-11-21', n_anos: 2 } }]);
  assert.equal(ok.corpo, corpo);
  for (const [rotulo, h] of Object.entries({
    '500': resp(500, 'x'), 'sem resposta': { error: 'ECONNRESET' }, 'vazio': resp(200, ''),
    'value vazio': resp(200, '{"value":[]}'), 'sem value': resp(200, '{"odata":1}'),
  })) afirmarContrato(rodar(h), `focus ${rotulo}`);
  assert.equal(rodar(resp(500, 'x')).http_status, 500);
  assert.equal(rodar({ error: 'ECONNRESET' }).http_status, null);
  assert.ok(rodar(resp(200, '')).erro);
  assert.ok(rodar(resp(200, '{"value":[]}')).erro, 'value vazio não é nada_encontrado');
});

test('A3: SIDRA - cabeçalho não conta; queda nunca vira 2xx vazio', () => {
  const rodar = (h) => rodarCode('Ler SIDRA', { itens: [h] })[0].json;
  const corpo = JSON.stringify([{ D3C: 'Mês (Código)', V: 'Valor' }, { D3C: '202608', V: '0.10' }, { D3C: '202609', V: '0.14' }]);
  const ok = rodar(resp(200, corpo)).__consulta;
  assert.equal(ok.fonte, 'ibge_sidra');
  assert.deepEqual(ok.itens, [{ chave: 'IPCA', valor: { ultimo_mes: '2026-09', n: 2 } }]);
  for (const h of [resp(503, 'x'), { error: 'ENOTFOUND' }, resp(200, ''), resp(200, '[]'),
    resp(200, JSON.stringify([{ D3C: 'Mês (Código)', V: 'Valor' }]))]) {
    afirmarContrato(rodar(h).__consulta, 'sidra');
  }
  assert.equal(rodar(resp(503, 'x')).__consulta.http_status, 503);
});

test('A3: os dados seguem para o Normalizar do jeito de antes (o registro não os toca)', () => {
  // Ler SGS -> Manter Contexto SGS devolve __corpo como o ARRAY inteiro (o "array inteiro" já testado)
  // e a série que caiu como __corpo null, que o Normalizar CONTA em descartados.
  const lidos = ['IPCA', 'CDI'].map((s) => rodarCode('Ler SGS', {
    itens: [s === 'CDI' ? resp(500, 'x') : resp(200, SGS_OK)], porNome: { 'Séries a Coletar': { __serie: s } },
  })[0].json);
  const mantidos = rodarCode('Manter Contexto SGS', { todosPorNome: { 'Ler SGS': lidos } });
  assert.equal(mantidos.length, 2);
  assert.ok(mantidos.every((m) => m.json.__consulta === undefined), 'a consulta não segue para o Normalizar');
  const saida = rodarCode('Normalizar Observações', { itens: mantidos.map((m) => m.json) });
  assert.equal(saida[0].json.observacoes.length, 2);
  assert.equal(saida[0].json.descartados, 1, 'a série que caiu é contada, não engolida');
  assert.ok(saida[0].json.observacoes.every((o) => o.serie === 'IPCA'));

  const focus = rodarCode('Ler Focus', { itens: [resp(200, JSON.stringify({ value: [
    { Data: '2026-11-21', DataReferencia: '2026', Mediana: 4.5, Media: 4.5, numeroRespondentes: 100 }] }))],
  porNome: { 'Indicadores Focus': { __serie: 'IPCA' } } })[0].json;
  const f = rodarCode('Manter Contexto Focus', { todosPorNome: { 'Ler Focus': [focus] } });
  assert.equal(rodarCode('Normalizar Focus', { itens: f.map((x) => x.json) })[0].json.expectativas.length, 1);

  const sid = rodarCode('Ler SIDRA', { itens: [resp(200, JSON.stringify([{ D3C: 'h', V: 'v' }, { D3C: '202609', V: '0.14' }]))] })[0].json;
  const m = rodarCode('Marcar Fonte IBGE', { todosPorNome: { 'Ler SIDRA': [sid] } });
  assert.equal(m[0].json.__fonte, 'IBGE/SIDRA');
  assert.equal(rodarCode('Normalizar Observações', { itens: m.map((x) => x.json) })[0].json.observacoes[0].data_ref, '2026-09-01');
});

test('A3: topologia - registro ANTES dos dados, em série, e sem poder derrubá-los', () => {
  const c = workflow.connections;
  const alvo = (n) => c[n].main[0].map((x) => x.node);
  for (const [http, ler, reg, retoma] of [
    ['BCB SGS', 'Ler SGS', 'Registrar Consulta SGS', 'Manter Contexto SGS'],
    ['BCB Focus', 'Ler Focus', 'Registrar Consulta Focus', 'Manter Contexto Focus'],
    ['IBGE SIDRA (IPCA)', 'Ler SIDRA', 'Registrar Consulta SIDRA', 'Marcar Fonte IBGE'],
  ]) {
    assert.deepEqual(alvo(http), [ler]);
    assert.deepEqual(alvo(ler), [reg], 'o registro vem logo depois da leitura, antes dos dados');
    assert.deepEqual(alvo(reg), [retoma]);
    const n = nodeDe(reg);
    assert.match(n.parameters.query, /fn_registrar_consulta_externa/);
    assert.equal(n.onError, 'continueRegularOutput', `${reg}: erro do registro não pode parar os dados`);
    assert.equal(n.alwaysOutputData, true, `${reg}: sem saída os dados não seguiriam`);
    assert.equal(n.parameters.options.queryBatching, 'independently', `${reg}: uma consulta recusada não leva as outras`);
    assert.equal(n.credentials.postgres.id, 'REPLACE');
    const h = nodeDe(http).parameters.options.response.response;
    assert.equal(h.fullResponse, true, `${http}: sem o status real a falha vira corpo anônimo`);
    assert.equal(h.responseFormat, 'text', `${http}: o hash é do corpo cru`);
    assert.equal(h.neverError, true);
  }
  // a função recebe 10 parâmetros, o último com default; o nó passa os 9 primeiros (mercado: caso/cnpj nulos, custo 0)
  assert.match(nodeDe('Registrar Consulta SGS').parameters.query, /null, null, \(q\.p->>'http_status'\)::int/);
  assert.match(nodeDe('Registrar Consulta SGS').parameters.query, /, 0\) as consulta/);
});

test('A3: o export não muda - nenhuma série nova entra na gravação de índices', () => {
  // As séries novas da A3 NÃO vão para indice_macro_obs (a aba Macro do cliente é a A5).
  const nomes = rodarCode('Séries a Coletar').map((i) => i.json.__serie).sort();
  assert.deepEqual(nomes, SERIES_MACRO.map((s) => s.codigo).sort());
});
