import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SERIES_MACRO, INDICADORES_FOCUS, numeroMacro, JUROS_PJ_SGS, JANELA_JUROS_MESES, SGS_EXTRA, JANELA_SGS_EXTRA, SIDRA_SETORIAL, JANELA_SIDRA_SETORIAL } from '../lib/macro.mjs';

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
// FIXTURE com a forma que o n8n REALMENTE produz para a configuração do nó (regra 4: a
// anterior inventava { statusCode, body } e por isso um leitor de "body" passava verde).
// Fonte: HttpRequestV3.node.ts do n8n (cópia lida em 25/11/2026; o arquivo declara
// versions 3 a 4.5, e o gerador usa typeVersion 4.2; produção: n8n 2.30.7 segundo o
// N8N/README.md, versão do arquivo lido NÃO identificada), ramo `responseFormat === 'text'`
// com `fullResponse`: para cada propriedade de ['body','headers','statusCode','statusMessage'],
// `body` vai para returnItem[outputPropertyName] (texto) e as demais copiam-se com o próprio
// nome; default de outputPropertyName = 'data'. Chamada sem resposta com continueOnFail
// vira { error: <mensagem em texto> } (mesmo arquivo). NÃO é captura de execução real: não há
// captura de HTTP Request neste repositório; o que se afirma é só o que o código-fonte prova.
// O campo do corpo é LIDO DA OPÇÃO DO NÓ no JSON gerado, não escrito aqui: quem mudar o nó ou o
// leitor sem o outro faz os testes reprovarem.
const CAMPO_CORPO_NO = nodeDe('BCB SGS').parameters.options.response.response.outputPropertyName;
const resp = (statusCode, body) => ({ headers: {}, statusCode, statusMessage: 'x', [CAMPO_CORPO_NO]: body });

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
    assert.ok(nodeDe(retoma), `${retoma} (retoma os dados) tem de existir`);
    assert.deepEqual(alvo('Retomar Dados').includes(retoma), true, `${retoma} só parte depois de TODOS os registros`);
    const n = nodeDe(reg);
    assert.match(n.parameters.query, /fn_registrar_consulta_externa/);
    assert.equal(n.onError, 'continueRegularOutput', `${reg}: erro do registro não pode parar os dados`);
    assert.equal(n.alwaysOutputData, true, `${reg}: sem saída os dados não seguiriam`);
    assert.equal(n.parameters.options.queryBatching, 'independently', `${reg}: uma consulta recusada não leva as outras`);
    assert.equal(n.credentials.postgres.id, 'REPLACE');
    const h = nodeDe(http).parameters.options.response.response;
    assert.equal(h.outputPropertyName, CAMPO_CORPO_NO, `${http}: o campo do corpo tem de ser o mesmo em todos os HTTP`);
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


// --- A3 fatia 1: juros por modalidade PJ (SGS) -> fonte bcb_juros_modalidade, 1 consulta por série ---
const JUROS_OK = JSON.stringify([{ data: '01/08/2026', valor: '24.10' }, { data: '01/09/2026', valor: '23.87' }]);
const jurosDe = (sgs, httpJson) => rodarCode('Ler Juros', {
  itens: [httpJson], porNome: { 'Séries Juros': { __sgs: sgs, __nome: `serie ${sgs}` } },
})[0].json.__consulta;

test('A3.1: as séries de juros saem com a janela fixa e SEM os totais redundantes', () => {
  const gerado = rodarCode('Séries Juros').map((i) => i.json);
  assert.equal(gerado.length, JUROS_PJ_SGS.length);
  assert.equal(new Set(gerado.map((g) => g.__sgs)).size, gerado.length, 'código repetido dobra linhas por dia');
  for (const g of gerado) {
    assert.match(g.__url, new RegExp(`bcdata\\.sgs\\.${g.__sgs}/dados/ultimos/${JANELA_JUROS_MESES}\\?formato=json$`));
  }
  assert.ok(JANELA_JUROS_MESES <= 3, 'janela maior que 3 meses multiplica as linhas do fato_externo imutável');
  for (const total of [20718, 20725, 20730, 20733, 20757]) {
    assert.ok(!gerado.some((g) => g.__sgs === total), `o total ${total} é soma de folhas já incluídas`);
  }
  assert.ok(gerado.some((g) => g.__sgs === 20715), 'o total PJ fica como referência');
});

test('A3.1: resposta boa vira UM fato por mês, na fonte bcb_juros_modalidade', () => {
  const c = jurosDe(20722, resp(200, JUROS_OK));
  assert.equal(c.fonte, 'bcb_juros_modalidade');
  assert.equal(c.http_status, 200);
  assert.equal(c.erro, null);
  assert.equal(c.corpo, JUROS_OK);
  assert.deepEqual(c.itens, [
    { chave: 'sgs:20722', valor: { data_ref: '2026-08-01', taxa_aa: 24.1, serie: 'serie 20722' }, referencia: 'sgs.20722:2026-08' },
    { chave: 'sgs:20722', valor: { data_ref: '2026-09-01', taxa_aa: 23.87, serie: 'serie 20722' }, referencia: 'sgs.20722:2026-09' },
  ]);
  afirmarContrato(c, 'juros ok');
});

test('A3.1: juros derrubado - 500, sem resposta, vazio, não-JSON, [] : NUNCA 2xx com itens []', () => {
  // 200 com [] é FALHOU, não nada_encontrado: o SGS responde ultimos/N com as últimas
  // observações de toda série existente (inclusive descontinuada), então lista vazia é
  // resposta inesperada. Série descontinuada aparece pela data_ref velha no fato, não por [].
  for (const [rotulo, h] of Object.entries({
    '500': resp(500, 'x'), 'sem resposta': { error: { message: 'timeout' } }, 'vazio': resp(200, ''),
    'não-JSON': resp(200, '<html/>'), 'lista vazia': resp(200, '[]'), 'objeto de erro': resp(200, '{"error":"x"}'),
    'só observações inválidas': resp(200, '[{"data":"jan/26","valor":"1"}]'),
  })) {
    const c = jurosDe(20722, h);
    afirmarContrato(c, `juros ${rotulo}`);
    assert.equal(c.fonte, 'bcb_juros_modalidade');
    const dois = c.http_status >= 200 && c.http_status <= 299;
    assert.ok(!dois || c.erro, `juros ${rotulo}: chegaria ao banco como 2xx limpo`);
  }
  assert.equal(jurosDe(20722, resp(500, 'x')).http_status, 500);
  assert.equal(jurosDe(20722, { error: 'x' }).http_status, null);
});

test('A3.1: a falha de UMA série de juros não é escondida pelas outras', () => {
  const cs = JUROS_PJ_SGS.map((s) => jurosDe(s.sgs, s.sgs === 20726 ? resp(500, 'boom') : resp(200, JUROS_OK)));
  assert.equal(cs.length, 19);
  assert.equal(cs.filter((c) => c.http_status === 500).length, 1);
  const boas = cs.filter((c) => c.http_status === 200);
  assert.equal(boas.length, 18);
  boas.forEach((c) => afirmarContrato(c, 'juros'));
  // linhas por dia no fato_externo: 19 consultas + 2 meses x 19 séries = 57 (a falha não gera fato)
  assert.equal(cs.length + boas.reduce((n, c) => n + c.itens.length, 0), 19 + 36);
});

test('A3.1: topologia - juros só REGISTRA, não toca indice_macro_obs, e o registro não derruba nada', () => {
  const c = workflow.connections;
  const alvo = (n) => c[n].main[0].map((x) => x.node);
  assert.ok(alvo('Agenda Diária').includes('Séries Juros'));
  assert.deepEqual(alvo('Séries Juros'), ['BCB Juros']);
  assert.deepEqual(alvo('BCB Juros'), ['Ler Juros']);
  assert.deepEqual(alvo('Ler Juros'), ['Registrar Consulta Juros']);
  // Os dados dos juros NUNCA chegam a indice_macro_obs: nenhum nó além do registro lê o Ler Juros.
  const leitores = workflow.nodes.filter((n) => /Ler Juros|BCB Juros/.test(n.parameters.jsCode ?? '') && n.name !== 'Ler Juros');
  assert.deepEqual(leitores.map((n) => n.name), [], 'só o registro consome a corrente de juros');
  assert.ok(!/__consulta|Ler Juros/.test(nodeDe('Normalizar Observações').parameters.jsCode));
  const reg = nodeDe('Registrar Consulta Juros');
  assert.equal(reg.onError, 'continueRegularOutput');
  assert.equal(reg.alwaysOutputData, true);
  assert.equal(reg.parameters.options.queryBatching, 'independently');
  const h = nodeDe('BCB Juros');
  assert.equal(h.parameters.options.response.response.outputPropertyName, CAMPO_CORPO_NO);
  assert.equal(h.onError, 'continueRegularOutput');
});

// --- INVARIANTE DE ORDEM: nenhum nó capaz de lançar roda antes de algum "Registrar Consulta*" ---
// Defeito (apontado na revisão da fatia 1): os ramos SGS/Focus/SIDRA/Juros saíam do gatilho em
// PARALELO, e o Normalizar lança de propósito (zero observação). A ordem entre ramos do n8n
// (executionOrder v1) depende da posição no canvas, não do grafo: num dia de queda geral, o
// throw de um ramo podia abortar a execução ANTES de outro ramo registrar a sua consulta, e
// "não rodou" ficava igual a "rodou" justo quando "falhou" mais importa (regra 7).
// Afirma COMPORTAMENTO (todo caminho do gatilho até um nó que lança passa por TODOS os
// registros), não a forma do desenho: qualquer arranjo que cumpra a ordem passa.
test('ordem: todo nó capaz de lançar só roda DEPOIS de todos os Registrar Consulta', () => {
  const c = workflow.connections;
  const filhos = (n) => (c[n]?.main ?? []).flat().map((x) => x.node);
  const gatilho = workflow.nodes.find((n) => n.type.endsWith('scheduleTrigger')).name;
  const registrar = workflow.nodes.filter((n) => n.name.startsWith('Registrar Consulta')).map((n) => n.name);
  // "Capaz de lançar": Code com throw explícito, ou qualquer HTTP/Postgres SEM continueRegularOutput.
  const lanca = workflow.nodes.filter((n) =>
    (n.type.endsWith('.code') && /\bthrow\b/.test(n.parameters.jsCode ?? ''))
    || (/httpRequest|postgres/.test(n.type) && n.onError !== 'continueRegularOutput')).map((n) => n.name);
  assert.equal(registrar.length, 6, 'um registro por corrente: SGS, Focus, SIDRA, Juros, SGS Extra e SIDRA Setorial');
  assert.ok(registrar.includes('Registrar Consulta SIDRA Setorial'));
  assert.ok(registrar.includes('Registrar Consulta SGS Extra'));
  assert.ok(lanca.includes('Normalizar Observações') && lanca.includes('Normalizar Focus'), 'os dois que lançam de propósito');

  // Há caminho do gatilho até T que NÃO passa por R? (busca no grafo sem atravessar R)
  const alcancaSem = (alvo, proibido) => {
    const visto = new Set([proibido]); const pilha = [gatilho];
    while (pilha.length) {
      const n = pilha.pop();
      if (n === alvo) return true;
      if (visto.has(n)) continue;
      visto.add(n); filhos(n).forEach((f) => pilha.push(f));
    }
    return false;
  };
  for (const t of lanca) {
    for (const r of registrar) {
      assert.ok(!alcancaSem(t, r), `"${t}" pode rodar sem que "${r}" tenha registrado antes`);
    }
  }
});


// --- A3 fatia 4: IBGE/SIDRA setorial (ibge_sidra -> fato_externo) ---
// Os corpos são as respostas REAIS da API do SIDRA de 25/11/2026 (fixtures versionadas), e
// entram SÓ na forma real do nó HTTP do n8n: texto cru no campo da opção outputPropertyName.
const fixSidra = (nome) => JSON.parse(readFileSync(join(__dirname, 'fixtures', 'sidra-setorial', nome + '.json'), 'utf8'));
const FIX = ['pib', 'pim', 'pmc', 'pmcat', 'pms', 'emp'];
const setorialDe = (i, corpoOuResp, { cru = false } = {}) => {
  const s = SIDRA_SETORIAL[i];
  const http = cru ? corpoOuResp : resp(200, typeof corpoOuResp === 'string' ? corpoOuResp : JSON.stringify(corpoOuResp));
  return rodarCode('Ler SIDRA Setorial', {
    itens: [http],
    porNome: { 'Séries SIDRA Setorial': rodarCode('Séries SIDRA Setorial')[i].json },
  })[0].json.__consulta;
};
// DERIVAÇÃO (não é resposta real): troca o V de linhas da fixture real por um símbolo de
// ausência do SIDRA. Os símbolos são os documentados pelo IBGE; a API de 25/11/2026 não
// devolveu nenhum nestas 6 consultas, então não há corpo real com ausência para citar.
const comAusencia = (nome, indices, simbolo) => {
  const a = fixSidra(nome);
  indices.forEach((k) => { a[k] = { ...a[k], V: simbolo }; });
  return a;
};

test('A3.4: as 6 séries do SIDRA setorial, janela de 2 períodos, URL pelo catálogo', () => {
  assert.deepEqual(SIDRA_SETORIAL.map((s) => s.tabela), [5932, 8888, 8880, 8882, 8688, 6323]);
  const gerado = rodarCode('Séries SIDRA Setorial').map((i) => i.json);
  assert.equal(gerado.length, 6);
  assert.equal(JANELA_SIDRA_SETORIAL, 2);
  gerado.forEach((g, i) => assert.match(g.__url, new RegExp(`/values/t/${SIDRA_SETORIAL[i].tabela}/n1/all/v/${SIDRA_SETORIAL[i].variavel}/p/last%202/`)));
  assert.match(gerado[0].__url, /\/c11255\/all$/);
});

test('A3.4: a resposta REAL de cada tabela vira fatos (categoria = última dimensão) e 202 fatos no total', () => {
  const esperado = [44, 54, 2, 22, 58, 22];
  let total = 0;
  FIX.forEach((nome, i) => {
    const c = setorialDe(i, fixSidra(nome));
    afirmarContrato(c, `sidra setorial ${nome}`);
    assert.equal(c.fonte, 'ibge_sidra');
    assert.equal(c.erro, null);
    assert.equal(c.itens.length, esperado[i], `${nome}: nº de fatos`);
    const s = SIDRA_SETORIAL[i];
    for (const f of c.itens) {
      assert.equal(f.chave, `sidra:${s.tabela}/${s.variavel}`);
      assert.equal(f.valor.compoe, false);
      assert.equal(f.valor.periodicidade, s.periodicidade);
      assert.ok(typeof f.valor.valor === 'number' && f.valor.categoria_codigo && f.valor.categoria && f.valor.unidade && f.valor.serie);
      assert.ok(f.referencia.startsWith(`sidra.${s.tabela}.${s.variavel}:`) && f.referencia.endsWith(`:${f.valor.categoria_codigo}:${f.valor.periodo}`));
      assert.equal(f.valor.ausentes_na_consulta, 0);
    }
    total += c.itens.length;
  });
  assert.equal(total, 202);
  // cada fato identifica um número só: nenhuma referência se repete dentro da série
  FIX.forEach((nome, i) => {
    const refs = setorialDe(i, fixSidra(nome)).itens.map((f) => f.referencia);
    assert.equal(new Set(refs).size, refs.length, `${nome}: referência repetida`);
  });
  // categoria é a ÚLTIMA dimensão: no PMC por atividade é Atividades (D5), não Tipos de índice (D4)
  const cat = setorialDe(3, fixSidra('pmcat')).itens[0].valor;
  assert.equal(cat.categoria_codigo, '90671');
  assert.match(cat.categoria, /^Combust/);
  // trimestre móvel carrega o rótulo do IBGE, e a unidade é a da linha
  const emp = setorialDe(5, fixSidra('emp')).itens[0].valor;
  assert.equal(emp.unidade, 'Mil pessoas');
  assert.match(emp.periodo_nome, /jun-jul-ago 2026/);
  // o cabeçalho (posição 0) nunca vira fato
  assert.ok(FIX.every((n, i) => setorialDe(i, fixSidra(n)).itens.every((f) => f.valor.categoria !== 'Brasil' && f.valor.valor !== 'Valor')));
});

test('A3.4: valor ausente ou sigiloso (-, .., ..., X) NÃO vira fato nem zero, e a ausência é CONTADA no fato', () => {
  for (const simbolo of ['-', '..', '...', 'X']) {
    const base = fixSidra('pim');
    const c = setorialDe(1, comAusencia('pim', [1, 2], simbolo));
    assert.equal(c.erro, null, simbolo);
    assert.equal(c.itens.length, 54 - 2, `${simbolo}: as 2 linhas ausentes não podem virar fato`);
    const ausentesCods = [1, 2].map((k) => `${base[k].D4C}:${base[k].D3C}`);
    for (const f of c.itens) {
      assert.equal(f.valor.ausentes_na_consulta, 2, 'o leitor tem de ver que a série tem buraco');
      assert.deepEqual(f.valor.ausentes_em, ausentesCods);
    }
    for (const k of [1, 2]) {
      assert.ok(!c.itens.some((f) => f.referencia === `sidra.8888.11602:${base[k].D4C}:${base[k].D3C}`), `${simbolo}: a categoria ausente virou fato`);
    }
    assert.ok(!c.itens.some((f) => f.valor.valor === 0 && base.slice(1).every((r) => Number(r.V) !== 0)), `${simbolo}: ausência virou zero`);
  }
  // zero MEDIDO é fato: "0" é valor, não ausência
  const z = fixSidra('pmc'); z[1] = { ...z[1], V: '0' };
  const cz = setorialDe(2, z);
  assert.equal(cz.itens.length, 2);
  assert.equal(cz.itens.find((f) => f.valor.valor === 0).valor.ausentes_na_consulta, 0);
});

test('A3.4: falhou nunca vira "nada encontrado" - 500, sem resposta, 200 só cabeçalho, tudo ausente', () => {
  const soCab = [fixSidra('pib')[0]];
  const tudoAus = fixSidra('pmc'); tudoAus.slice(1).forEach((r, k) => { tudoAus[k + 1] = { ...r, V: '...' }; });
  const casos = {
    '500': resp(500, 'x'), 'sem resposta': { error: { message: 'timeout' } }, 'vazio': resp(200, ''),
    'não-JSON': resp(200, '<html/>'), 'lista vazia': resp(200, '[]'), 'objeto de erro': resp(200, '{"error":"x"}'),
    '200 só cabeçalho (DERIVADO da fixture pib)': resp(200, JSON.stringify(soCab)),
    '200 todos ausentes (DERIVADO da fixture pmc)': resp(200, JSON.stringify(tudoAus)),
    'corpo em body em vez de no campo': { headers: {}, statusCode: 200, body: JSON.stringify(fixSidra('pib')) },
  };
  for (const [rotulo, h] of Object.entries(casos)) {
    for (let i = 0; i < 6; i++) {
      const c = setorialDe(i, h, { cru: true });
      afirmarContrato(c, `sidra setorial ${i} ${rotulo}`);
      assert.ok(!(c.http_status >= 200 && c.http_status <= 299) || c.erro, `${i} ${rotulo}: chegaria como 2xx limpo`);
      assert.equal(c.itens, null, `${i} ${rotulo}: não pode ter fatos`);
    }
  }
  assert.equal(setorialDe(0, resp(500, 'x'), { cru: true }).http_status, 500);
  assert.equal(setorialDe(0, { error: 'x' }, { cru: true }).http_status, null);
  // a falha de UMA série não é escondida pelas outras
  const cs = FIX.map((n, i) => setorialDe(i, i === 4 ? resp(500, 'boom') : JSON.stringify(fixSidra(n)), { cru: i === 4 }));
  assert.equal(cs.filter((c) => c.http_status === 500).length, 1);
  assert.equal(cs.filter((c) => c.itens && c.itens.length > 0).length, 5);
});

test('A3.4: topologia - só registra, antes de qualquer nó que lança, e nunca chega a indice_macro_obs', () => {
  const c = workflow.connections;
  const alvo = (n) => c[n].main[0].map((x) => x.node);
  assert.deepEqual(alvo('Registrar Consulta SGS Extra'), ['Séries SIDRA Setorial']);
  assert.deepEqual(alvo('Séries SIDRA Setorial'), ['IBGE SIDRA Setorial']);
  assert.deepEqual(alvo('IBGE SIDRA Setorial'), ['Ler SIDRA Setorial']);
  assert.deepEqual(alvo('Ler SIDRA Setorial'), ['Registrar Consulta SIDRA Setorial']);
  assert.deepEqual(alvo('Registrar Consulta SIDRA Setorial'), ['Séries a Coletar']);
  const leitores = workflow.nodes.filter((n) => /SIDRA Setorial/.test(n.parameters.jsCode ?? '') && !/Setorial/.test(n.name));
  assert.deepEqual(leitores.map((n) => n.name), [], 'só a corrente setorial consome a setorial');
  const reg = nodeDe('Registrar Consulta SIDRA Setorial');
  assert.equal(reg.onError, 'continueRegularOutput');
  assert.equal(reg.alwaysOutputData, true);
  assert.equal(reg.parameters.options.queryBatching, 'independently');
  const h = nodeDe('IBGE SIDRA Setorial');
  assert.equal(h.onError, 'continueRegularOutput');
  assert.equal(h.parameters.options.response.response.outputPropertyName, CAMPO_CORPO_NO);
  assert.equal(workflow.nodes.length, 34);
});

// --- A3 fatia 2: IBC-Br, crédito/inadimplência PJ e euro (bcb_sgs -> fato_externo) ---
const extraDe = (sgs, httpJson) => {
  const m = SGS_EXTRA.find((x) => x.sgs === sgs);
  return rodarCode('Ler SGS Extra', {
    itens: [httpJson],
    porNome: { 'Séries SGS Extra': { __sgs: sgs, __meta: { nome: m.nome, natureza: m.natureza, unidade: m.unidade, periodicidade: m.periodicidade } } },
  })[0].json.__consulta;
};
const DIARIA_OK = JSON.stringify([
  { data: '24/11/2026', valor: '6.4260000' }, { data: '25/11/2026', valor: '6.4413000' }]);

test('A3.2: só entra série de nome CONFIRMADO; 192 (INCC suposto) e 7458 ficam fora', () => {
  const codigos = SGS_EXTRA.map((s) => s.sgs).sort();
  assert.deepEqual(codigos, [20540, 21083, 21086, 21619, 24363, 24364]);
  assert.ok(!codigos.includes(192), 'rótulo por suposição (regra 1)');
  assert.ok(!codigos.includes(7458), 'parou em 2025');
  const gerado = rodarCode('Séries SGS Extra').map((i) => i.json);
  assert.equal(gerado.length, SGS_EXTRA.length);
  for (const g of gerado) {
    const n = JANELA_SGS_EXTRA[g.__meta.periodicidade];
    assert.match(g.__url, new RegExp(`bcdata\\.sgs\\.${g.__sgs}/dados/ultimos/${n}\\?formato=json$`));
  }
  assert.equal(JANELA_SGS_EXTRA.mensal, 2);
  assert.ok(JANELA_SGS_EXTRA.diaria <= 5, 'janela diária maior multiplica as linhas do fato imutável');
});

test('A3.2: fato mensal e diário carregam unidade, natureza e que NÃO compõem; fonte bcb_sgs', () => {
  const m = extraDe(21083, resp(200, JUROS_OK));
  assert.equal(m.fonte, 'bcb_sgs');
  assert.deepEqual(m.itens[1], {
    chave: 'sgs:21083',
    valor: { data_ref: '2026-09-01', valor: 23.87, unidade: '% da carteira', natureza: 'proporcao', compoe: false,
      periodicidade: 'mensal', serie: SGS_EXTRA.find((x) => x.sgs === 21083).nome },
    referencia: 'sgs.21083:2026-09',
  });
  const d = extraDe(21619, resp(200, DIARIA_OK));
  assert.equal(d.itens.length, 2);
  assert.equal(d.itens[1].valor.data_ref, '2026-11-25', 'diária: a data é a do dia, não do mês');
  assert.equal(d.itens[1].valor.unidade, 'R$/EUR');
  assert.equal(d.itens[1].valor.periodicidade, 'diaria');
  assert.equal(d.itens[1].referencia, 'sgs.21619:2026-11-25');
  assert.ok(SGS_EXTRA.every((s) => s.natureza && s.periodicidade));
  assert.ok(d.itens.concat(m.itens).every((i) => i.valor.compoe === false));
  // unidade desconhecida fica NULA e dita, nunca inventada
  assert.equal(extraDe(20540, resp(200, JUROS_OK)).itens[0].valor.unidade, null);
});

test('A3.2: SGS extra derrubado - nunca 2xx com itens []; a falha de uma série não some', () => {
  for (const [rotulo, h] of Object.entries({
    '500': resp(500, 'x'), 'sem resposta': { error: { message: 'timeout' } }, 'vazio': resp(200, ''),
    'não-JSON': resp(200, '<html/>'), 'lista vazia': resp(200, '[]'), 'objeto de erro': resp(200, '{"error":"x"}'),
  })) {
    for (const s of SGS_EXTRA) {
      const c = extraDe(s.sgs, h);
      afirmarContrato(c, `extra ${s.sgs} ${rotulo}`);
      assert.ok(!(c.http_status >= 200 && c.http_status <= 299) || c.erro, `${s.sgs} ${rotulo}: chegaria como 2xx limpo`);
    }
  }
  const cs = SGS_EXTRA.map((s) => extraDe(s.sgs, s.sgs === 21619 ? resp(500, 'boom') : resp(200, JUROS_OK)));
  assert.equal(cs.filter((c) => c.http_status === 500).length, 1);
  assert.equal(cs.filter((c) => c.http_status === 200 && c.itens.length === 2).length, 5);
});

test('A3.2: o registro novo é um Registrar Consulta, em série e só de registro', () => {
  const c = workflow.connections;
  const alvo = (n) => c[n].main[0].map((x) => x.node);
  assert.deepEqual(alvo('Séries SGS Extra'), ['BCB SGS Extra']);
  assert.deepEqual(alvo('BCB SGS Extra'), ['Ler SGS Extra']);
  assert.deepEqual(alvo('Ler SGS Extra'), ['Registrar Consulta SGS Extra']);
  const reg = nodeDe('Registrar Consulta SGS Extra');
  assert.equal(reg.onError, 'continueRegularOutput');
  assert.equal(reg.alwaysOutputData, true);
  assert.equal(reg.parameters.options.queryBatching, 'independently');
  assert.ok(!/Ler SGS Extra|BCB SGS Extra/.test(nodeDe('Normalizar Observações').parameters.jsCode), 'não vai para indice_macro_obs');
  assert.equal(nodeDe('BCB SGS Extra').parameters.options.response.response.outputPropertyName, CAMPO_CORPO_NO);
});


// --- CONTRATO nó HTTP -> nó Ler: a forma que o n8n entrega para ESTA configuração é LIDA ---
// Defeito (revisão, achado crítico): o leitor lia "body" e o n8n entrega o corpo em
// outputPropertyName (default "data"). Em produção as 45 consultas virariam "falhou" com motivo
// falso e o Normalizar lançaria "zero observação". Aqui, para CADA par HTTP -> Ler, o campo do
// corpo é derivado da opção do nó HTTP no JSON gerado e a resposta boa tem de virar consulta
// lida (sem erro, com itens e o corpo cru intacto).
test('contrato HTTP -> Ler: a resposta boa, na forma do n8n para o nó gerado, é LIDA em todas as fontes', () => {
  const sidra = JSON.stringify([{ D3C: 'h', V: 'v' }, { D3C: '202609', V: '0.14' }]);
  const focus = JSON.stringify({ value: [{ Data: '2026-11-21', DataReferencia: '2026', Mediana: 4.5 }] });
  const pares = [
    ['BCB SGS', 'Ler SGS', { 'Séries a Coletar': { __serie: 'IPCA' } }, SGS_OK],
    ['BCB Focus', 'Ler Focus', { 'Indicadores Focus': { __serie: 'IPCA' } }, focus],
    ['IBGE SIDRA (IPCA)', 'Ler SIDRA', {}, sidra],
    ['BCB Juros', 'Ler Juros', { 'Séries Juros': { __sgs: 20722, __nome: 'x' } }, JUROS_OK],
    ['IBGE SIDRA Setorial', 'Ler SIDRA Setorial', { 'Séries SIDRA Setorial': { __tabela: 8880, __variavel: 11709, __periodicidade: 'mensal' } }, JSON.stringify(fixSidra('pmc'))],
    ['BCB SGS Extra', 'Ler SGS Extra', { 'Séries SGS Extra': { __sgs: 24363, __meta: { nome: 'x', natureza: 'indice', unidade: 'índice', periodicidade: 'mensal' } } }, JUROS_OK],
  ];
  for (const [http, ler, porNome, corpo] of pares) {
    const campo = nodeDe(http).parameters.options.response.response.outputPropertyName;
    assert.ok(typeof campo === 'string' && campo.length > 0, `${http}: o campo do corpo tem de ser EXPLÍCITO (o default do n8n é "data", e mudar o default quebraria a leitura)`);
    const entrega = { headers: {}, statusCode: 200, statusMessage: 'OK', [campo]: corpo };
    const saida = rodarCode(ler, { itens: [entrega], porNome })[0].json.__consulta;
    assert.equal(saida.erro, null, `${ler}: a resposta boa foi lida como falha (${saida.erro})`);
    assert.equal(saida.http_status, 200);
    assert.ok(Array.isArray(saida.itens) && saida.itens.length > 0, `${ler}: sem itens`);
    assert.equal(saida.corpo, corpo, `${ler}: o corpo cru tem de chegar intacto (é o que o banco hasheia)`);
  }
});

// Revisão de 7e2b1f8 (MÉDIO 1): na PMC e na PMS o número é de VOLUME, e isso só está na dimensão
// "Tipos de índice" (D4), entre o período e a atividade. O fato tem de dizê-lo, e o mesmo ponto em
// receita nominal (56725) não pode ganhar a mesma referência. A linha de receita nominal é DERIVADA
// da fixture real trocando só D4C/D4N e o valor (não foi capturada: a série pedida é a de volume).
test('A3.4: o fato da PMS diz que é volume, e volume e receita nominal nunca dividem a referência', () => {
  const linhas = fixSidra('pms');
  const vol = setorialDe(4, linhas).itens[0];
  assert.match(vol.valor.dimensoes['Tipos de índice'], /volume/i);
  const nominal = { ...linhas[1], D4C: '56725', D4N: 'Índice de receita nominal de serviços', V: '9.9' };
  const itens = setorialDe(4, [linhas[0], linhas[1], nominal]).itens;
  assert.equal(itens.length, 2);
  assert.notEqual(itens[0].referencia, itens[1].referencia);
  assert.match(itens[1].valor.dimensoes['Tipos de índice'], /receita nominal/i);
});

// Revisão de 7e2b1f8 (MÉDIO 2): ibge_sidra tem 7 consultas por dia; o falhou tem de dizer QUAL
// tabela caiu, inclusive no não-2xx sem texto de erro (a 0303 gravaria só "HTTP 400").
test('A3.4: a consulta que falhou diz qual tabela do SIDRA caiu', () => {
  const s = SIDRA_SETORIAL[4];
  const casos = [resp(400, 'Tabela inexistente'), { error: { message: 'ETIMEDOUT' } }, resp(200, JSON.stringify([fixSidra('pms')[0]]))];
  for (const r of casos) {
    const c = setorialDe(4, r, { cru: true });
    assert.equal(c.itens, null);
    assert.ok(c.erro && c.erro.includes(s.tabela + '/' + s.variavel), 'erro sem a tabela: ' + c.erro);
  }
});

// Achado MÉDIO da revisão de 7e2b1f8: no emprego (Mil pessoas, grandeza que SE SOMA) o Total vinha
// junto das componentes sem marca; somar os fatos de um período dava o dobro. Resposta REAL.
test('A3.4: o total vem marcado como agregado, e somar só os não agregados não conta duas vezes', () => {
  const itens = setorialDe(5, fixSidra('emp')).itens;
  for (const per of new Set(itens.map((f) => f.valor.periodo))) {
    const doPer = itens.filter((f) => f.valor.periodo === per);
    const tot = doPer.filter((f) => f.valor.agregado);
    assert.equal(tot.length, 1, per + ': um agregado só');
    assert.equal(tot[0].valor.categoria, 'Total');
    const soma = doPer.filter((f) => !f.valor.agregado).reduce((a, f) => a + f.valor.valor, 0);
    // As componentes NÃO fecham exatamente no Total (202608: 103439 x 103477, arredondamento do
    // IBGE): a afirmação é "da ordem do Total", não "igual"; com o Total junto daria ~2x.
    assert.ok(Math.abs(soma / tot[0].valor.valor - 1) < 0.01, per + ': componentes somam ' + soma);
  }
});

// A lista de agregados não pode citar código que a resposta REAL não traz (envelhece em silêncio se o
// IBGE renumerar): todo código da lista aparece como fato agregado na resposta real.
test('A3.4: todo agregado da lista existe na resposta real do IBGE', () => {
  FIX.forEach((nome, i) => {
    const marcados = new Set(setorialDe(i, fixSidra(nome)).itens.filter((f) => f.valor.agregado).map((f) => f.valor.categoria_codigo));
    for (const cod of SIDRA_SETORIAL[i].agregados) assert.ok(marcados.has(cod), nome + ': agregado ' + cod + ' ausente da resposta');
  });
});

// Achado BAIXO da revisão de 7e2b1f8: "202602" é fevereiro na PIM e o 2º trimestre no PIB.
// mes_final é o último mês coberto, e é por ele que séries de periodicidades diferentes se comparam.
test('A3.4: mes_final põe mês, trimestre e trimestre móvel na mesma régua', () => {
  const mf = (i, nome) => [...new Set(setorialDe(i, fixSidra(nome)).itens.map((f) => f.valor.periodo + '>' + f.valor.mes_final))].sort();
  assert.deepEqual(mf(0, 'pib'), ['202601>2026-03', '202602>2026-06']);
  assert.deepEqual(mf(1, 'pim'), ['202608>2026-08', '202609>2026-09']);
  assert.deepEqual(mf(5, 'emp'), ['202608>2026-08', '202609>2026-09']);
});

// Achado BAIXO da revisão de f5147ab: sem a série identificada, o motivo de um não-2xx virava
// "SIDRA undefined/undefined: HTTP 500" e a guarda não dizia o que de fato aconteceu.
test('A3.4: chamada sem série identificada diz isso, falhe a chamada ou não, e não grava fato', () => {
  for (const r of [resp(500, 'erro'), resp(200, JSON.stringify(fixSidra('pms')))]) {
    const c = rodarCode('Ler SIDRA Setorial', { itens: [r], porNome: { 'Séries SIDRA Setorial': {} } })[0].json.__consulta;
    assert.match(c.erro, /^não foi possível identificar a série/);
    assert.equal(c.itens, null);
  }
});
