import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildExtractionRequest, parseExtractionResponse, extractionSchema, SECAO_CANONICA_ENUM,
  normalizarUnidade, normalizarMoeda, SYSTEM_PROMPT, ehLinhaNaoMonetaria, diagnosticarErroApi,
  achatarGrupos,
} from '../lib/extract.mjs';
import {
  spreadsheetToText, parseCsv, avisoTruncamentoPlanilha, colunasDaPlanilha,
  MAX_LINHAS_PLANILHA, MAX_COLUNAS_PLANILHA,
} from '../lib/spreadsheet.mjs';
import { contentPartFromFile } from '../lib/ia.mjs';
import {
  PROVEDORES, provedor, conteudoDaResposta, cortadoPorLimite, usoDaChamada,
  capacidadesDoModelo,
} from '../lib/provedor.mjs';

// AS FIXTURAS DESTE ARQUIVO SÃO ESCRITAS NA FORMA DA OPENAI, E ISSO É ESCOLHA.
//
// O que se testa aqui é DOMÍNIO — achatar grupos, herdar escala e moeda, não
// engolir uma conta desalinhada, transformar erro de API em pendência nomeada.
// Nada disso muda com o provedor, e reescrever as ~30 fixturas no dialeto do
// provedor da vez tornaria cada uma ilegível para provar a mesma coisa.
//
// `resposta()` traduz a fixtura para o dialeto do provedor ATIVO antes de
// entregá-la ao parser. Ou seja: o mesmo corpo de teste roda contra quem estiver
// configurado, e trocar `IA_PROVEDOR` reexecuta a suíte inteira no outro
// dialeto. O que é específico de dialeto tem testes próprios, no fim do arquivo.
function resposta(apiOpenAI) {
  const prov = provedor();
  if (prov.dialeto !== 'gemini') return apiOpenAI;
  if (!apiOpenAI || !Array.isArray(apiOpenAI.choices)) return apiOpenAI;
  const c = apiOpenAI.choices[0] || {};
  const fora = {
    candidates: [{
      content: { parts: [{ text: c.message ? c.message.content : '' }] },
      finishReason: c.finish_reason === 'length' ? 'MAX_TOKENS' : 'STOP',
    }],
  };
  if (apiOpenAI.usage) {
    fora.usageMetadata = {
      promptTokenCount: apiOpenAI.usage.prompt_tokens,
      candidatesTokenCount: apiOpenAI.usage.completion_tokens,
      cachedContentTokenCount: apiOpenAI.usage.prompt_tokens_details
        ? apiOpenAI.usage.prompt_tokens_details.cached_tokens : 0,
    };
  }
  return fora;
}

/** O parser, sempre pela porta do provedor ativo. */
function parseExtracao(api, opts = {}) {
  return parseExtractionResponse(resposta(api), opts);
}

test('extractionSchema é estrito, agrupa por seção e declara as colunas UMA vez', () => {
  // O contexto (s/sc/op) mora no GRUPO e as colunas em `cols`; a conta traz só
  // o rótulo e um valor POR COLUNA. É o que tirou 63% da saída — antes cada
  // (conta × coluna) reescrevia os cinco campos de contexto e o rótulo.
  const s = extractionSchema();
  assert.equal(s.strict, true);
  const g = s.schema.properties.grupos;
  assert.equal(g.type, 'array');
  assert.equal(g.items.additionalProperties, false);
  assert.deepEqual(g.items.required, ['s', 'sc', 'op', 'cols', 'l']);
  assert.deepEqual(g.items.properties.sc.enum, SECAO_CANONICA_ENUM);
  assert.ok(g.items.properties.sc.enum.includes('NAO_CLASSIFICAVEL'));

  // As duas dimensões de coluna (empresa e período) num mecanismo só.
  const cols = g.items.properties.cols;
  assert.deepEqual(cols.items.required, ['ec', 'pc']);
  assert.deepEqual(cols.items.properties.ec.type, ['string', 'null']);
  assert.deepEqual(cols.items.properties.pc.type, ['string', 'null']);

  // A linha: rótulo + LISTAS de valor. Se `vt`/`vn` deixarem de ser array, a
  // associação valor↔coluna acaba, e é ela que impede trocar 2025 por 2024.
  const l = g.items.properties.l;
  assert.deepEqual(l.items.required, ['k', 'vt', 'vn', 'cf']);
  assert.equal(l.items.properties.vt.type, 'array');
  assert.equal(l.items.properties.vn.type, 'array');
  assert.deepEqual(l.items.properties.vn.items.type, ['number', 'null']);

  // Toda chave curta carrega description: nome cifrado sem explicação faz o
  // modelo adivinhar o que preencher.
  for (const k of ['s', 'sc', 'op', 'cols', 'l']) {
    assert.ok(g.items.properties[k].description, `campo ${k} do grupo sem description`);
  }
  for (const k of ['k', 'vt', 'vn', 'cf']) {
    assert.ok(l.items.properties[k].description, `campo ${k} da linha sem description`);
  }
  assert.equal(s.schema.properties.diagnostico.type, 'object');
  assert.ok(s.schema.properties.diagnostico.required.includes('legibilidade'));
  assert.ok(s.schema.properties.diagnostico.properties.tipo_sugerido.enum.includes('DESCONHECIDO'));
});

test('buildExtractionRequest inclui o conteúdo, o nome do arquivo e o schema de diagnóstico+extração', () => {
  for (const prov of Object.values(PROVEDORES)) {
    const parte = contentPartFromFile({ mimeType: 'application/pdf', base64: 'QUJD', filename: 'dre.pdf' }, prov);
    const req = buildExtractionRequest({ tipo: 'DRE', nomeOriginal: 'dre.pdf', conteudo: parte, prov });
    const partes = prov.dialeto === 'gemini'
      ? req.body.contents[0].parts
      : req.body.messages[1].content;
    // O SCHEMA TEM DE CHEGAR, seja qual for o dialeto: sem ele a saída é texto
    // livre e o achatamento recebe qualquer coisa.
    const schema = prov.dialeto === 'gemini'
      ? req.body.generationConfig.responseSchema
      : req.body.response_format.json_schema.schema;
    assert.deepEqual(Object.keys(schema.properties), ['moeda', 'unidade', 'diagnostico', 'grupos'], prov.id);
    assert.deepEqual(partes[1], parte, prov.id);
    assert.match(partes[0].text, /dre\.pdf/, prov.id);
  }
});

test('parseExtractionResponse normaliza linhas (com seção) e diagnóstico', () => {
  const api = { choices: [{ message: { content: JSON.stringify({
    moeda: 'BRL', unidade: 'R$ mil',
    diagnostico: {
      entidade: 'Empresa X Ltda', tipo_confirma: true, tipo_sugerido: 'DRE',
      periodo_tipo: 'anual', periodo_referencia: '12M25',
      legibilidade: 'ok', nota_legibilidade: null,
      resumo: 'DRE anual de 2025 com receita e custos detalhados.',
      justificativa: 'Cabeçalho e estrutura batem com DRE.',
    },
    linhas: [
      { s: 'Receita Operacional', sc: 'receita_bruta', k: 'Receita líquida', vt: '10.000', vn: 10000, op: 1, cf: 0.8 },
      { s: 'Custos', sc: 'custos', k: 'Custo', vt: '(6.000)', vn: -6000, op: 1, cf: 0.7 },
      { s: null, sc: 'NAO_CLASSIFICAVEL', k: 'Total geral', vt: '4.000', vn: 4000, op: 1, cf: 0.9 },
    ],
  }) } }] };
  const r = parseExtracao(api);
  assert.equal(r.unidade, 'milhar', '"R$ mil" é normalizado para a escala canônica');
  assert.equal(r.campos.length, 3);
  assert.equal(r.campos[0].secao, 'Receita Operacional');
  assert.equal(r.campos[0].secao_canonica, 'receita_bruta');
  assert.equal(r.campos[0].chave, 'Receita líquida');
  assert.equal(r.campos[0].valor_num, 10000);
  assert.equal(r.campos[0].unidade, 'milhar'); // herda a unidade (normalizada) do documento
  assert.equal(r.campos[1].secao_canonica, 'custos');
  assert.equal(r.campos[2].secao_canonica, null); // NAO_CLASSIFICAVEL vira null
  assert.equal(r.campos[0].entidade_coluna, null); // documento de 1 entidade só (caso comum)
  assert.equal(r.diagnostico.entidade, 'Empresa X Ltda');
  assert.equal(r.diagnostico.tipo_confirma, true);
  assert.equal(r.diagnostico.legibilidade, 'ok');
});

test('parseExtractionResponse: documento com várias entidades/colunas lado a lado (entidade_coluna por linha)', () => {
  // Achado real (sessão 7, HANDOFF.md): um balanço combinado de 3 entidades
  // (Certsys Tecn/Part/Com + Total) fazia a IA fabricar um valor único por
  // conta em vez de reportar as 3 colunas — o schema não tinha como
  // representar isso. Agora uma mesma "chave" pode aparecer em várias linhas,
  // uma por coluna, com entidade_coluna preenchido.
  const api = { choices: [{ message: { content: JSON.stringify({
    moeda: 'BRL', unidade: null,
    diagnostico: {
      entidade: null, tipo_confirma: true, tipo_sugerido: 'COMBINADO',
      periodo_tipo: 'anual', periodo_referencia: '2025',
      legibilidade: 'ok', nota_legibilidade: null,
      resumo: 'Balanço combinado de 3 entidades do grupo.',
      justificativa: 'Colunas Certsys Tecn/Part/Com + Total.',
    },
    linhas: [
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: 'Certsys Tecn', k: 'Bens Numerários', vt: '51,29', vn: 51.29, op: 1, cf: 0.95 },
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: 'Certsys Part', k: 'Bens Numerários', vt: '0,00', vn: 0, op: 1, cf: 0.95 },
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: 'Certsys Com', k: 'Bens Numerários', vt: '0,00', vn: 0, op: 1, cf: 0.95 },
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: 'Total', k: 'Bens Numerários', vt: '51,29', vn: 51.29, op: 1, cf: 0.95 },
    ],
  }) } }] };
  const r = parseExtracao(api);
  assert.equal(r.campos.length, 4, 'uma linha por (conta x coluna), não uma linha só');
  assert.deepEqual(r.campos.map((c) => c.entidade_coluna), ['Certsys Tecn', 'Certsys Part', 'Certsys Com', 'Total']);
  assert.ok(r.campos.every((c) => c.chave === 'Bens Numerários'), 'mesma chave, colunas diferentes');
});

test('parseExtractionResponse: documento comparativo (várias colunas de período) — periodo_coluna por linha', () => {
  // Lacuna real (sessão 7 cont.⁹): "Balanço consolidado 2023 x 2024.pdf" traz
  // 2023 e 2024 lado a lado da MESMA entidade. Sem periodo_coluna, as duas
  // linhas "Caixa" colapsavam numa coluna só no export (perda de dado). Agora
  // uma linha por (conta × período), ortogonal a entidade_coluna.
  const api = { choices: [{ message: { content: JSON.stringify({
    moeda: 'BRL', unidade: 'R$ mil',
    diagnostico: {
      entidade: 'Grupo X', tipo_confirma: true, tipo_sugerido: 'BALANCO',
      periodo_tipo: 'multi', periodo_referencia: '23,24',
      legibilidade: 'ok', nota_legibilidade: null, resumo: 'Balanço comparativo 2023×2024.', justificativa: 'Duas colunas de ano.',
    },
    linhas: [
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: null, pc: '2023', k: 'Caixa', vt: '100', vn: 100, op: 1, cf: 0.9 },
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: null, pc: '2024', k: 'Caixa', vt: '120', vn: 120, op: 1, cf: 0.9 },
    ],
  }) } }] };
  const r = parseExtracao(api);
  assert.equal(r.campos.length, 2, 'uma linha por (conta × período), não colapsada');
  assert.deepEqual(r.campos.map((c) => c.periodo_coluna), ['2023', '2024']);
  assert.ok(r.campos.every((c) => c.chave === 'Caixa'), 'mesma chave, períodos diferentes');
  assert.ok(r.campos.every((c) => c.entidade_coluna === null), 'periodo_coluna é ortogonal a entidade_coluna');
});

test('extractionSchema inclui pc/periodo_coluna (required + string|null) na COLUNA', () => {
  const s = extractionSchema();
  const cols = s.schema.properties.grupos.items.properties.cols;
  assert.ok(cols.items.required.includes('pc'));
  assert.deepEqual(cols.items.properties.pc.type, ['string', 'null']);
});

test('parseExtractionResponse normaliza tipo_sugerido=DESCONHECIDO para null', () => {
  const api = { choices: [{ message: { content: JSON.stringify({
    moeda: null, unidade: null,
    diagnostico: {
      entidade: null, tipo_confirma: false, tipo_sugerido: 'DESCONHECIDO',
      periodo_tipo: 'desconhecido', periodo_referencia: null,
      legibilidade: 'ilegivel', nota_legibilidade: 'Digitalização ilegível, páginas em branco.',
      resumo: 'Não foi possível ler o conteúdo.', justificativa: 'Arquivo corrompido/ilegível.',
    },
    linhas: [],
  }) } }] };
  const r = parseExtracao(api);
  assert.equal(r.diagnostico.tipo_sugerido, null);
  assert.equal(r.diagnostico.legibilidade, 'ilegivel');
  assert.equal(r.diagnostico.nota_legibilidade, 'Digitalização ilegível, páginas em branco.');
});

test('parseExtractionResponse tolera resposta vazia/ruim', () => {
  assert.deepEqual(parseExtracao({}).campos, []);
  assert.deepEqual(parseExtracao({ choices: [{ message: { content: 'nao-json' } }] }).campos, []);
  assert.equal(parseExtracao({}).diagnostico.entidade, null);
});

// 0111: certidão/organograma/parecer de auditoria não têm valor monetário por
// natureza — a IA diz isso no diagnóstico, e o Sinal 3 (banco) deixa de tratar
// "zero linhas" como falha de extração quando o campo é `false`.
test('extractionSchema exige tem_dado_financeiro no diagnóstico', () => {
  const s = extractionSchema();
  assert.ok(s.schema.properties.diagnostico.required.includes('tem_dado_financeiro'));
  assert.equal(s.schema.properties.diagnostico.properties.tem_dado_financeiro.type, 'boolean');
});

test('parseExtractionResponse: documento sem valor monetário por natureza devolve tem_dado_financeiro=false com grupos vazio', () => {
  const api = { choices: [{ message: { content: JSON.stringify({
    moeda: null, unidade: null,
    diagnostico: {
      entidade: 'Grupo Canastra', tipo_confirma: true, tipo_sugerido: 'CERTIDOES',
      periodo_tipo: 'data-base', periodo_referencia: '2025-08-01',
      legibilidade: 'ok', nota_legibilidade: null, tem_dado_financeiro: false,
      resumo: 'Certidões negativas de débito, protesto e falência — sem valor monetário.',
      justificativa: 'Documento é só texto de certidão; nenhuma tabela de valores.',
    },
    grupos: [],
  }) } }] };
  const r = parseExtracao(api);
  assert.equal(r.diagnostico.tem_dado_financeiro, false);
  assert.deepEqual(r.campos, []);
  // zero linhas aqui não é falha: falhaMotivo tem de ficar null.
  assert.equal(r.falhaMotivo, null);
});

test('parseExtractionResponse: diagnostico sem tem_dado_financeiro (workflow velho) cai para null, nunca false', () => {
  const api = { choices: [{ message: { content: JSON.stringify({
    moeda: null, unidade: null,
    diagnostico: {
      entidade: null, tipo_confirma: true, tipo_sugerido: 'BALANCO',
      periodo_tipo: 'anual', periodo_referencia: '12M25',
      legibilidade: 'ok', nota_legibilidade: null,
      resumo: 'r', justificativa: 'j',
    },
    grupos: [],
  }) } }] };
  const r = parseExtracao(api);
  assert.equal(r.diagnostico.tem_dado_financeiro, null);
});

test('buildExtractionRequest define max_tokens explícito (sem isso, documentos combinados grandes truncam a resposta silenciosamente)', () => {
  for (const prov of Object.values(PROVEDORES)) {
    const parte = contentPartFromFile({ mimeType: 'application/pdf', base64: 'QUJD', filename: 'balanco.pdf' }, prov);
    const req = buildExtractionRequest({ tipo: 'COMBINADO', nomeOriginal: 'balanco.pdf', conteudo: parte, prov });
    // O NOME DO CAMPO É DO MODELO, não do dialeto: a família GPT-5 recusa
    // `max_tokens` e exige `max_completion_tokens`. O INVARIANTE é o teto
    // existir e valer 16.384 — o campo em que ele mora é mecanismo, e travar
    // mecanismo protege o bug (regra 3 do CLAUDE.md).
    const teto = prov.dialeto === 'gemini'
      ? req.body.generationConfig.maxOutputTokens
      : req.body[capacidadesDoModelo(req.body.model).tetoDeSaida];
    assert.equal(teto, 16384, prov.id);
  }
});

test('parseExtractionResponse: resposta ok não tem falhaMotivo', () => {
  const api = { choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({
    moeda: null, unidade: null,
    diagnostico: {
      entidade: null, tipo_confirma: true, tipo_sugerido: 'DRE',
      periodo_tipo: 'anual', periodo_referencia: '2025',
      legibilidade: 'ok', nota_legibilidade: null, resumo: 'x', justificativa: 'x',
    },
    linhas: [],
  }) } }] };
  assert.equal(parseExtracao(api).falhaMotivo, null);
});

test('parseExtractionResponse: JSON truncado (limite de tokens de saída) vira falhaMotivo explicativo, não 0 campos silencioso', () => {
  // Achado em produção (sessão 7 cont.⁷, "teste v14"): 16 documentos combinados
  // grandes classificados com sucesso mas extraídos com 0 linhas — a chamada
  // de extração vinha truncada e o parse falhava silenciosamente, sem
  // sinalizar nada. Isso é o que passou a detectar.
  const api = { choices: [{ finish_reason: 'length', message: { content: '{"moeda":"BRL","diagnostico":{"entidade":"Grupo Y"' } }] };
  const r = parseExtracao(api);
  assert.deepEqual(r.campos, []);
  assert.match(r.falhaMotivo, /truncada/i);
  assert.match(r.falhaMotivo, /limite de tokens de saída/);
});

test('diagnosticarErroApi: separa TETO DE GASTO de falta de crédito (a conta "está OK" e recusa)', () => {
  // O relato do dono depois do v30: "o limite da OpenAI está OK". E podia estar
  // mesmo — teto de gasto de PROJETO devolve 429 com saldo em caixa, tier normal
  // e as páginas de Billing e Limits sem nada de errado. São causas diferentes com
  // ações diferentes: recarregar crédito não conserta um teto configurado.
  const tetoProjeto = { statusCode: 429, error: { error: { code: 'project_spend_limit_exceeded',
    message: 'You have exceeded the spend limit set for this project.' } } };
  const d = diagnosticarErroApi(tetoProjeto);
  assert.equal(d.causa, 'limite_de_gasto');
  assert.match(d.motivo, /NÃO é falta de crédito/);
  assert.match(d.motivo, /Projects/, 'diz ONDE olhar — o teto do projeto não aparece na tela de Billing');

  // Orçamento mensal da ORG: mesma família, mesma ação.
  assert.equal(diagnosticarErroApi({ statusCode: 429,
    error: { error: { code: 'organization_usage_limit_exceeded', message: 'Monthly budget exceeded' } } }).causa,
    'limite_de_gasto');

  // Já sem saldo de verdade é OUTRA causa, com outra ação.
  for (const codigo of ['insufficient_quota', 'credit_balance_exhausted']) {
    assert.equal(diagnosticarErroApi({ statusCode: 429, error: { error: { code: codigo } } }).causa,
      'sem_credito', codigo);
  }

  // E cadência continua sendo reconhecida como cadência (o único caso em que
  // espaçar resolve) — sem isso a correção acima teria roubado o caso legítimo.
  const cadencia = diagnosticarErroApi({ statusCode: 429, error: { error: { code: 'rate_limit_exceeded',
    message: 'Rate limit reached for gpt-4o on tokens per min (TPM): Limit 30000, Used 28000' } } });
  assert.equal(cadencia.causa, 'limite_cadencia');
  assert.match(cadencia.motivo, /espaçar as chamadas ajuda/i);
});

test('diagnosticarErroApi: o AxiosError REAL do v30 não é lido como código da OpenAI', () => {
  // Este é o item que o dono colou do nó, copiado sem inventar campo nenhum. É o
  // fato que refutou a previsão de que o corpo da OpenAI estaria em
  // `error.error`: NÃO existe corpo aninhado, nem `cause`, nem headers. Só o
  // AxiosError, com a dica genérica que o n8n escreve sobre QUALQUER 429.
  const doNo = {
    message: "Try spacing your requests out using the batching settings under 'Options'",
    name: 'AxiosError',
    stack: 'AxiosError: Request failed with status code 429\n    at settle (...)',
    code: 'ERR_BAD_REQUEST',
    status: 429,
  };
  const d = diagnosticarErroApi(doNo);
  assert.equal(d.causa, 'limite_indeterminado',
    'sem corpo da OpenAI, a causa honesta é "não sei qual limite" — nunca um chute em cadência');
  assert.equal(d.status, 429, 'o status precisa sobreviver — é a única coisa que o item afirma');
  assert.equal(d.codigo, null,
    'ERR_BAD_REQUEST é código de TRANSPORTE do axios; reportá-lo como código da OpenAI manda a próxima sessão investigar o campo errado');
  assert.equal(d.tipo, null);

  // A guarda não pode cegar o caminho legítimo: quando o item É o corpo da
  // OpenAI (o que `neverError` passa a entregar), o código real tem de aparecer.
  const corpoDireto = { status: 429, type: 'insufficient_quota', code: 'insufficient_quota',
    message: 'You exceeded your current quota' };
  const c = diagnosticarErroApi(corpoDireto);
  assert.equal(c.causa, 'sem_credito');
  assert.equal(c.codigo, 'insufficient_quota', 'o corpo real chega inteiro ao diagnóstico');
});

test('parseExtractionResponse: erro da API OpenAI vira falhaMotivo com a mensagem original', () => {
  const api = { error: { message: 'You exceeded your current quota', code: 'insufficient_quota' } };
  const r = parseExtracao(api);
  assert.deepEqual(r.campos, []);
  assert.match(r.falhaMotivo, /You exceeded your current quota/);
});

test('parseExtractionResponse: sem conteúdo (falha de rede/API) vira falhaMotivo, não só diagnóstico genérico', () => {
  const r = parseExtracao({});
  assert.deepEqual(r.campos, []);
  assert.ok(r.falhaMotivo, 'deve haver um motivo textual, não silêncio');
});

test('spreadsheetToText resume linhas com cabeçalho', () => {
  const rows = [ { Conta: 'Receita', Valor: '100' }, { Conta: 'Custo', Valor: '-60' } ];
  const t = spreadsheetToText(rows);
  assert.match(t, /Conta \| Valor/);
  assert.match(t, /Receita \| 100/);
});

test('spreadsheetToText trunca e sinaliza linhas omitidas', () => {
  const rows = Array.from({ length: 120 }, (_, i) => ({ A: i }));
  const t = spreadsheetToText(rows, { maxRows: 10 });
  assert.match(t, /\+110 linhas omitidas/);
});

// --- Item 1 do §7.4 do Onboarding: truncamento de planilha ------------------
// O teto ERA 50 linhas, e 50 é menos do que documento real tem. Estes testes
// fixam as duas metades da correção: o teto cobre documento real, e o que
// eventualmente sobrar do teto vira PENDÊNCIA em vez de nota no prompt.

test('faturamento de 24 meses × 5 entidades (120 linhas) cabe INTEIRO no envio', () => {
  // O caso do §7.4: "um faturamento de 24 a 36 meses perde o resto em silêncio".
  // Com o teto antigo de 50, 70 das 120 linhas não chegavam à IA.
  const rows = [];
  for (const emp of ['Metalurgica', 'Componentes', 'Logistica', 'SPE', 'Holding']) {
    for (let m = 1; m <= 24; m++) rows.push({ Empresa: emp, Mes: `${m}/2025`, Receita: 1000 + m });
  }
  assert.equal(rows.length, 120);
  const t = spreadsheetToText(rows);
  assert.doesNotMatch(t, /linhas omitidas/, 'não deve truncar documento de tamanho real');
  assert.match(t, /Holding \| 24\/2025/, 'a última linha da última entidade tem de estar no texto');
  assert.equal(avisoTruncamentoPlanilha(rows), null, 'nada cortado ⇒ nenhuma pendência');
});

test('acima do teto, o corte vira aviso que nomeia o tamanho — não silêncio', () => {
  const rows = Array.from({ length: MAX_LINHAS_PLANILHA + 137 }, (_, i) => ({ A: i }));
  const aviso = avisoTruncamentoPlanilha(rows);
  assert.ok(aviso, 'linha cortada SEM aviso é o defeito que estamos fechando');
  assert.match(aviso, /137 de 2137 linhas/);
  assert.match(aviso, /INCOMPLETA/);
});

test('coluna acima do teto também vira aviso (não só linha)', () => {
  const larga = {};
  for (let c = 0; c < MAX_COLUNAS_PLANILHA + 3; c++) larga[`col${c}`] = c;
  const aviso = avisoTruncamentoPlanilha([larga]);
  assert.ok(aviso);
  assert.match(aviso, /3 de 63 colunas/);
});

test('colunas saem da UNIÃO das linhas: célula vazia na linha 0 não apaga a coluna', () => {
  // O "Extract From File" do N8N devolve objeto esparso — sem a união, uma
  // planilha cuja primeira linha não tem 2024 preenchido perdia a coluna 2024
  // do documento inteiro, que é perda silenciosa da mesma família.
  const rows = [{ Conta: 'Receita', '2025': '100' }, { Conta: 'Custo', '2025': '-60', '2024': '-55' }];
  // ORDEM: chave que parece inteiro ('2025') é reordenada pelo próprio JS para a
  // frente das chaves textuais — não é escolha nossa e não se corrige aqui. Não
  // causa desalinhamento porque cabeçalho e corpo usam a MESMA lista de colunas;
  // o que este teste garante é a PRESENÇA das três, que é o que se perdia.
  assert.deepEqual([...colunasDaPlanilha(rows)].sort(), ['2024', '2025', 'Conta']);
  const t = spreadsheetToText(rows);
  const [cabecalho, ...corpo] = t.split('\n');
  assert.match(cabecalho, /2024/, 'a coluna ausente na linha 0 tem de aparecer no cabeçalho');
  const iCol2024 = cabecalho.split(' | ').indexOf('2024');
  assert.equal(corpo[1].split(' | ')[iCol2024], '-55', 'e o valor cai sob a própria coluna');
});

test('avisoConteudo entra em falhaMotivo mesmo quando a extração volta impecável', () => {
  // A chamada pode voltar perfeita e o documento ainda estar incompleto, porque
  // o pedaço que falta nunca chegou à IA. Sem isto, extração "ok" + planilha
  // cortada = dashboard verde sobre dado parcial.
  const boa = {
    choices: [{
      finish_reason: 'stop',
      message: { content: JSON.stringify({
        moeda: 'BRL', unidade: 'milhar',
        diagnostico: { entidade: 'X', tipo_confirma: true, tipo_sugerido: 'BALANCO', periodo_tipo: 'anual', periodo_referencia: '2025', legibilidade: 'ok', nota_legibilidade: null, resumo: 'r', justificativa: 'j' },
        linhas: [{ s: null, sc: 'ATIVO_CIRCULANTE', ec: null, pc: null, k: 'Caixa', vt: '10', vn: 10, op: 1, cf: 0.9 }],
      }) },
    }],
  };
  const semAviso = parseExtracao(boa);
  assert.equal(semAviso.falhaMotivo, null, 'sem aviso e sem erro ⇒ nada a relatar');

  const comAviso = parseExtracao(boa, { avisoConteudo: 'Planilha maior que o teto de envio: 70 de 120 linhas não foram enviadas.' });
  assert.equal(comAviso.campos.length, 1, 'as linhas que vieram continuam valendo');
  assert.match(comAviso.falhaMotivo, /70 de 120 linhas/, 'o aviso tem de virar pendência');
});

test('avisoConteudo SOMA-SE ao motivo da chamada, não o substitui', () => {
  // Planilha cortada E resposta truncada cabem no mesmo documento; esconder um
  // dos dois é a falha que esta mudança fecha.
  const truncada = { choices: [{ finish_reason: 'length', message: { content: '{"linhas":[' } }] };
  const r = parseExtracao(truncada, { avisoConteudo: 'XLSX nao foi lido' });
  assert.match(r.falhaMotivo, /XLSX nao foi lido/);
  assert.match(r.falhaMotivo, /limite de tokens de saída/);
});

test('parseCsv detecta separador e monta objetos', () => {
  const csv = 'Conta;Valor\nReceita;100\nCusto;-60';
  const rows = parseCsv(csv);
  assert.equal(rows.length, 2);
  assert.deepEqual(rows[0], { Conta: 'Receita', Valor: '100' });
});

// --- Escala/moeda: normalização de fronteira (variação entre documentos) -----
// A `unidade` é herdada por TODA linha e a reconciliação Classe A compara a
// unidade de DOIS documentos diferentes (0009: divergência aborta a checagem),
// então texto livre inconsistente entre arquivos gerava precondição falsa.
test('normalizarUnidade colapsa as redações reais de escala num vocabulário fechado', () => {
  for (const bruto of ['R$ mil', 'milhares de reais', 'Em R$ mil', 'MILHAR', 'valores em milhares', 'R$ Mil']) {
    assert.equal(normalizarUnidade(bruto), 'milhar', `"${bruto}" → milhar`);
  }
  for (const bruto of ['R$ milhões', 'milhoes', 'em milhões de reais', 'MILHAO']) {
    assert.equal(normalizarUnidade(bruto), 'milhao', `"${bruto}" → milhao`);
  }
  for (const bruto of ['unidade', 'reais', 'R$', 'valores inteiros']) {
    assert.equal(normalizarUnidade(bruto), 'unidade', `"${bruto}" → unidade`);
  }
  // Desconhecido/ausente NUNCA chuta uma escala (errar em 1000x é pior que não saber).
  for (const bruto of [null, undefined, '', '   ', 'sei lá', 'xyz']) {
    assert.equal(normalizarUnidade(bruto), null, `${JSON.stringify(bruto)} → null`);
  }
});

test('normalizarMoeda devolve código ISO', () => {
  for (const bruto of ['R$', 'reais', 'BRL', 'Real']) assert.equal(normalizarMoeda(bruto), 'BRL');
  assert.equal(normalizarMoeda('US$'), 'USD');
  assert.equal(normalizarMoeda('dólar'), 'USD');
  assert.equal(normalizarMoeda('EUR'), 'EUR');
  assert.equal(normalizarMoeda(null), null);
  assert.equal(normalizarMoeda('qualquer coisa'), null);
});

test('parseExtractionResponse normaliza escala e moeda do documento', () => {
  const api = { choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({
    moeda: 'R$', unidade: 'Em milhares de reais',
    diagnostico: {
      entidade: 'X Ltda', tipo_confirma: true, tipo_sugerido: 'BALANCO', periodo_tipo: 'anual',
      periodo_referencia: '12M25', legibilidade: 'ok', nota_legibilidade: null, resumo: 'r', justificativa: 'j',
    },
    linhas: [{ s: 'Ativo Circulante', sc: 'ativo_circulante', ec: null, pc: null, k: 'Caixa', vt: '1.000', vn: 1000, op: 1, cf: 0.9 }],
  }) } }] };
  const r = parseExtracao(api);
  assert.equal(r.moeda, 'BRL');
  assert.equal(r.unidade, 'milhar');
  assert.equal(r.campos[0].unidade, 'milhar', 'a escala normalizada é a herdada por linha');
  assert.equal(r.campos[0].moeda, 'BRL', 'a moeda também desce para a linha (0035)');
});

// --- Item 2 do §7.4 do Onboarding: moeda capturada e descartada -------------
// `normalizarMoeda` sempre existiu e o schema sempre pediu `moeda` à IA; o valor
// morria no cabeçalho do retorno, porque NENHUM campo o levava ao banco. Com a
// escala de ~496× já corrigida, era o último fator multiplicativo invisível: uma
// linha em dólar somada a reais erra pelo câmbio inteiro, num book que fecha.

test('cada linha carrega a moeda do documento — é o que chega ao banco', () => {
  const doc = (moeda) => ({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({
    moeda, unidade: 'milhar',
    diagnostico: {
      entidade: 'Export Co', tipo_confirma: true, tipo_sugerido: 'DRE', periodo_tipo: 'anual',
      periodo_referencia: '12M25', legibilidade: 'ok', nota_legibilidade: null, resumo: 'r', justificativa: 'j',
    },
    linhas: [
      { s: null, sc: 'RECEITA_LIQUIDA', ec: null, pc: null, k: 'Receita de exportação', vt: '2.400', vn: 2400, op: 1, cf: 0.97 },
      { s: null, sc: 'RECEITA_LIQUIDA', ec: null, pc: null, k: 'Receita interna', vt: '600', vn: 600, op: 1, cf: 0.97 },
    ],
  }) } }] });

  const emDolar = parseExtracao(doc('US$'));
  assert.deepEqual(emDolar.campos.map((c) => c.moeda), ['USD', 'USD']);

  const emReal = parseExtracao(doc('R$'));
  assert.deepEqual(emReal.campos.map((c) => c.moeda), ['BRL', 'BRL']);

  // Duas linhas de MESMO valor numérico e moedas diferentes: sem a coluna, são
  // indistinguíveis — que é exatamente como o book somava USD com BRL.
  assert.equal(emDolar.campos[0].valor_num, emReal.campos[0].valor_num);
  assert.notEqual(emDolar.campos[0].moeda, emReal.campos[0].moeda);
});

test('moeda desconhecida fica null — nunca BRL presumido', () => {
  // Presumir a moeda da maioria é o mesmo erro com outra roupa: um documento de
  // subsidiária em USD entraria como real e ninguém veria.
  const api = { choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({
    moeda: null, unidade: 'milhar',
    diagnostico: {
      entidade: 'X', tipo_confirma: true, tipo_sugerido: 'BALANCO', periodo_tipo: 'anual',
      periodo_referencia: '12M25', legibilidade: 'ok', nota_legibilidade: null, resumo: 'r', justificativa: 'j',
    },
    linhas: [{ s: null, sc: 'ATIVO_CIRCULANTE', ec: null, pc: null, k: 'Caixa', vt: '10', vn: 10, op: 1, cf: 0.9 }],
  }) } }] };
  const r = parseExtracao(api);
  assert.equal(r.moeda, null);
  assert.equal(r.campos[0].moeda, null, 'sem moeda declarada, a linha fica sem moeda');
});

test('linha não-monetária não herda moeda (mesma regra da escala)', () => {
  // "Margem 12%" com moeda BRL faria o export tratar doze por cento como doze
  // reais — o motivo pelo qual a escala já era bloqueada nessas linhas.
  const api = { choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({
    moeda: 'R$', unidade: 'milhar',
    diagnostico: {
      entidade: 'X', tipo_confirma: true, tipo_sugerido: 'DRE', periodo_tipo: 'anual',
      periodo_referencia: '12M25', legibilidade: 'ok', nota_legibilidade: null, resumo: 'r', justificativa: 'j',
    },
    linhas: [
      { s: null, sc: 'RECEITA_LIQUIDA', ec: null, pc: null, k: 'Receita líquida', vt: '1.000', vn: 1000, op: 1, cf: 0.9 },
      { s: null, sc: null, ec: null, pc: null, k: 'Margem bruta (%)', vt: '12%', vn: 12, op: 1, cf: 0.9 },
      { s: null, sc: null, ec: null, pc: null, k: 'Lucro por ação', vt: '1,25', vn: 1.25, op: 1, cf: 0.9 },
    ],
  }) } }] };
  const r = parseExtracao(api);
  assert.equal(r.campos[0].moeda, 'BRL', 'conta monetária herda');
  assert.equal(r.campos[1].moeda, null, 'percentual não herda moeda');
  assert.equal(r.campos[2].moeda, null, 'LPA não herda moeda');
  // E a escala continua bloqueada nas mesmas linhas — os dois andam juntos.
  assert.equal(r.campos[1].unidade, null);
  assert.equal(r.campos[2].unidade, null);
});

// --- Prompt: instruções que blindam a variação entre contratos --------------
test('SYSTEM_PROMPT exige o TOTAL IMPRESSO como linha, e não só como nome de seção', () => {
  // O defeito medido na auditoria da rodada v46 (17/08): o balanço chegou com
  // todas as contas e NENHUM dos totais de topo. "ATIVO CIRCULANTE",
  // "TOTAL DO ATIVO", "RECEITA OPERACIONAL BRUTA" viraram `secao` — que é um
  // NOME, não guarda número — e o valor impresso ao lado deles sumiu. Sem o
  // total impresso, a conferência do export não tem contra o que conferir: a
  // soma das contas vira a única verdade disponível, que é exatamente o que a
  // conferência existe para evitar.
  assert.match(SYSTEM_PROMPT, /O TOTAL IMPRESSO É LINHA, E NÃO SÓ NOME DE SEÇÃO/);
  assert.match(SYSTEM_PROMPT, /"secao" é o nome do agrupamento, não guarda\s+número nenhum/);
  // As três alturas têm de estar nomeadas: total geral, seção e subgrupo. Um
  // prompt que só cita "total" deixa passar o cabeçalho de seção com valor,
  // que foi o caso real.
  for (const altura of ['TOTAL DO ATIVO', 'Passivo Não', 'Disponível']) {
    assert.ok(SYSTEM_PROMPT.includes(altura), `o prompt não exemplifica "${altura}"`);
  }
  // E a fronteira: o total que o documento NÃO imprime continua proibido —
  // extrair total calculado seria inventar dado, e o sistema inteiro depende de
  // o extraído ser só o que está escrito.
  assert.match(SYSTEM_PROMPT, /se a\s+documento não imprime o total, não calcule|documento não imprime o total, não calcule/);
});

test('SYSTEM_PROMPT instrui a notação CANÔNICA de período na emissão', () => {
  // Sem isto, a IA emitia o período em notação livre ("2025", "31/12/2024",
  // "12M25") — inconsistente com o lado do nome (lib/classifier.mjs).
  assert.match(SYSTEM_PROMPT, /notação canônica/i);
  for (const forma of ['12M25', '1T25', 'L24M', '23,24,25', 'AAAA-MM-DD']) {
    assert.ok(SYSTEM_PROMPT.includes(forma), `prompt exemplifica a forma "${forma}"`);
  }
});

test('SYSTEM_PROMPT define moeda e o vocabulário FECHADO de escala', () => {
  // moeda/unidade eram `required` no schema mas o prompt não dizia nada sobre
  // elas — o modelo escolhia o formato sozinho, documento a documento.
  assert.match(SYSTEM_PROMPT, /MOEDA E ESCALA/);
  assert.match(SYSTEM_PROMPT, /BRL/);
  for (const v of ['"unidade"', '"milhar"', '"milhao"']) {
    assert.ok(SYSTEM_PROMPT.includes(v), `prompt fecha o vocabulário em ${v}`);
  }
  // Não converter na origem: o número vai como impresso, a escala é declarada.
  assert.match(SYSTEM_PROMPT, /NÃO converta os valores/i);
});

test('SYSTEM_PROMPT define convenção de SINAL e decimal brasileiro', () => {
  // O prompt só dizia "número puro"; parênteses/decimal BR ficavam por conta
  // do palpite do modelo (fonte de erro de sinal e de 1.000 → 1,0).
  assert.match(SYSTEM_PROMPT, /PARÊNTESES são NEGATIVOS/i);
  assert.ok(SYSTEM_PROMPT.includes('"1.234,56" → 1234.56'), 'exemplifica o decimal BR');
  assert.ok(SYSTEM_PROMPT.includes('"1.000" → 1000'), 'exemplifica milhar sem decimal');
  assert.match(SYSTEM_PROMPT, /DEVEDOR\/CREDOR/i, 'cobre balancete com coluna D/C');
});

// --- Escala por linha: não herdar a escala do documento onde ela não vale ----
test('ehLinhaNaoMonetaria reconhece linhas fora da escala monetária', () => {
  for (const [chave, vt] of [
    ['Margem Bruta %', null], ['Lucro por Ação', '1,25'], ['LPA', '1,25'],
    ['Participação percentual', null], ['Quantidade de itens', '120'],
    ['Número de Ações', '1.000.000'], ['Índice de liquidez', '1,5 %'],
  ]) {
    assert.equal(ehLinhaNaoMonetaria(chave, vt), true, `"${chave}" é não-monetária`);
  }
  // Conservador de propósito: conta monetária legítima NÃO pode ser confundida
  // (um falso positivo aqui esconderia a escala de uma conta de verdade).
  for (const [chave, vt] of [
    ['Margem de Contribuição', '1.500,00'], ['Caixa e Equivalentes', '100'],
    ['Receita Operacional Bruta', '10.000'], ['Fornecedores', '(2.000)'],
  ]) {
    assert.equal(ehLinhaNaoMonetaria(chave, vt), false, `"${chave}" é monetária`);
  }
});

test('parseExtractionResponse: escala do documento NÃO contamina linha não-monetária', () => {
  // Demonstrações reais misturam naturezas no mesmo arquivo: balanço/DRE em
  // "R$ mil" junto de LPA e margens em %. Herdar "milhar" nessas linhas é uma
  // mis-escala silenciosa de 1000x quando o fator for aplicado.
  const api = { choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({
    moeda: 'BRL', unidade: 'R$ mil',
    diagnostico: {
      entidade: 'X', tipo_confirma: true, tipo_sugerido: 'DRE', periodo_tipo: 'anual',
      periodo_referencia: '12M25', legibilidade: 'ok', nota_legibilidade: null, resumo: 'r', justificativa: 'j',
    },
    linhas: [
      { s: 'Receita', sc: 'receita_bruta', ec: null, pc: null, k: 'Receita Líquida', vt: '10.000', vn: 10000, op: 1, cf: 0.9 },
      { s: null, sc: 'NAO_CLASSIFICAVEL', ec: null, pc: null, k: 'Margem Líquida %', vt: '12,5%', vn: 12.5, op: 1, cf: 0.9 },
      { s: null, sc: 'NAO_CLASSIFICAVEL', ec: null, pc: null, k: 'Lucro por Ação', vt: '1,25', vn: 1.25, op: 1, cf: 0.9 },
    ],
  }) } }] };
  const r = parseExtracao(api);
  assert.equal(r.unidade, 'milhar', 'escala do documento');
  assert.equal(r.campos[0].unidade, 'milhar', 'conta monetária herda a escala');
  assert.equal(r.campos[1].unidade, null, 'linha em % não herda escala (null = desconhecida)');
  assert.equal(r.campos[2].unidade, null, 'lucro por ação não herda escala');
  assert.equal(r.campos[1].valor_num, 12.5, 'o valor em si é preservado');
});

test('SYSTEM_PROMPT avisa que a escala vale só para valores monetários', () => {
  assert.match(SYSTEM_PROMPT, /escala vale para os valores MONETÁRIOS/i);
  assert.match(SYSTEM_PROMPT, /POR AÇÃO/);
});

test('DMPL/DVA: enum de seção canônica, códigos do diagnóstico e contrato da matriz (Supabase/migrations/0024)', () => {
  // 1. A IA passa a ter como dizer "esta linha é da DMPL/DVA". Sem isso, a
  //    linha de uma DMPL embutida num PDF composto só tinha dois destinos, os
  //    dois ruins: 'patrimonio_liquido' (o saldo de fechamento REPETE o total do
  //    PL — somá-lo infla o balanço, bug real do export do dono) ou
  //    'NAO_CLASSIFICAVEL'.
  assert.ok(SECAO_CANONICA_ENUM.includes('dmpl'));
  assert.ok(SECAO_CANONICA_ENUM.includes('dva'));

  // 2. …e como classificar o DOCUMENTO inteiro como DMPL/DVA. `tipo_sugerido` é
  //    um enum fechado nos códigos da taxonomia: enquanto DMPL não existia lá, o
  //    modelo escolhia o vizinho mais próximo (a DMPL do book saiu como MUTUOS).
  const tipos = extractionSchema().schema.properties.diagnostico.properties.tipo_sugerido.enum;
  assert.ok(tipos.includes('DMPL'));
  assert.ok(tipos.includes('DVA'));

  // 3. O contrato da MATRIZ da DMPL — `secao` = movimento (a linha da tabela),
  //    `chave` = componente do PL (o cabeçalho da coluna). É o que permite ao
  //    export reconstruir a matriz; se o prompt parar de pedir isso, a aba DMPL
  //    vira uma listagem sem sentido.
  assert.match(SYSTEM_PROMPT, /um GRUPO por MOVIMENTO, com "secao" = o rótulo do movimento/);
  assert.match(SYSTEM_PROMPT, /"chave" = o rótulo do COMPONENTE/);
  // …e que os componentes do PL NÃO viram colunas: no formato agrupado a
  // tentação é declarar cada componente como uma `col`, o que jogaria o
  // componente para `periodo_coluna`/`entidade_coluna` e desmontaria a matriz
  // que o export reconstrói.
  assert.match(SYSTEM_PROMPT, /os COMPONENTES do PL\s+NÃO vão em "cols"/);
  // e a proibição explícita de reaproveitar entidade_coluna para os componentes
  assert.match(SYSTEM_PROMPT, /Não use\s+entidade_coluna para os componentes do PL/);
  // …e de marcar linha de DMPL como conta do PL (a dupla contagem)
  assert.match(SYSTEM_PROMPT, /Nunca marque uma linha de DMPL como "patrimonio_liquido"/);
});

test('DMPL: parse mapeia a matriz para linhas (movimento × componente)', () => {
  const api = {
    choices: [{
      finish_reason: 'stop',
      message: {
        content: JSON.stringify({
          moeda: 'BRL', unidade: 'milhar',
          diagnostico: { entidade: 'VERTENTES METALÚRGICA LTDA.', tipo_confirma: true, tipo_sugerido: 'DMPL',
            periodo_tipo: 'anual', periodo_referencia: '12M25', legibilidade: 'ok', nota_legibilidade: null,
            resumo: 'Mutações do PL', justificativa: 'Matriz de movimentos por componente.' },
          linhas: [
            { s: 'SALDOS EM 31 DE DEZEMBRO DE 2024', sc: 'dmpl', ec: null, pc: null,
              k: 'Capital social', vt: '45.000', vn: 45000, op: 1, cf: 0.98 },
            { s: 'SALDOS EM 31 DE DEZEMBRO DE 2024', sc: 'dmpl', ec: null, pc: null,
              k: 'Total', vt: '24.801', vn: 24801, op: 1, cf: 0.98 },
            { s: 'Prejuízo líquido do exercício', sc: 'dmpl', ec: null, pc: null,
              k: 'Prejuízos acumulados', vt: '(17.901)', vn: -17901, op: 1, cf: 0.97 },
          ],
        }),
      },
    }],
  };
  const r = parseExtracao(api);
  assert.equal(r.falhaMotivo, null);
  assert.equal(r.campos.length, 3);
  // o movimento vai em `secao` e o componente em `chave` — é assim que o export
  // remonta a matriz (linhas = movimentos, colunas = componentes)
  assert.equal(r.campos[0].secao, 'SALDOS EM 31 DE DEZEMBRO DE 2024');
  assert.equal(r.campos[0].chave, 'Capital social');
  assert.equal(r.campos[0].secao_canonica, 'dmpl');
  assert.equal(r.campos[2].valor_num, -17901);
  // nenhum componente do PL pode ter virado "entidade" (isso criaria empresas
  // fantasmas no export, uma por componente)
  assert.ok(r.campos.every((c) => c.entidade_coluna === null));
});

test('ORDEM da linha vem da posição no array, não do modelo (Supabase/migrations/0027)', () => {
  // Por que a ordem não é pedida ao modelo: a posição no array JÁ é a ordem de
  // leitura do documento. Pedir um campo gastaria token de saída por linha (e
  // `linhas` é o único bloco que se repete centenas de vezes) e daria ao modelo
  // uma chance de errar algo que nós sabemos com certeza.
  const api = { choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({
    moeda: 'BRL', unidade: 'milhar',
    diagnostico: { entidade: 'VT LOGÍSTICA E TRANSPORTES LTDA.', tipo_confirma: true,
      tipo_sugerido: 'BALANCO', periodo_tipo: 'anual', periodo_referencia: '12M24',
      legibilidade: 'ok', nota_legibilidade: null, resumo: 'BP', justificativa: 'ok' },
    // Sequência REAL do arquivo que causou o defeito do teste v28: o subtotal
    // "Contas a Receber" (3.293) impresso ACIMA dos seus dois componentes.
    linhas: [
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: null, pc: null, k: 'Caixa e bancos', vt: '399', vn: 399, op: 1, cf: 0.98 },
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: null, pc: null, k: 'Contas a Receber', vt: '3.293', vn: 3293, op: 1, cf: 0.98 },
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: null, pc: null, k: 'Fretes a receber', vt: '3.562', vn: 3562, op: 1, cf: 0.97 },
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: null, pc: null, k: '(-) PECLD', vt: '(269)', vn: -269, op: 1, cf: 0.97 },
    ],
  }) } }] };
  const r = parseExtracao(api);
  assert.deepEqual(r.campos.map((c) => c.ordem), [0, 1, 2, 3]);
  // A ordem tem de acompanhar o rótulo — se elas se descolarem, o export
  // reconhece o subtotal errado e tira da soma uma conta legítima.
  assert.equal(r.campos[1].chave, 'Contas a Receber');
  assert.equal(r.campos[1].ordem, 1);
  // O subtotal é a soma dos DOIS seguintes: é esse padrão que o export procura.
  assert.equal(r.campos[2].valor_num + r.campos[3].valor_num, r.campos[1].valor_num);
});

// ---------------------------------------------------------------------------
// O FORMATO AGRUPADO — o que tirou 63% da saída (2026-08-13)
// ---------------------------------------------------------------------------
//
// A medição que motivou tudo: o dono rodou 14 documentos e pagou US$ 0,90, dos
// quais ~84% era saída de extração, a ~64 tokens por linha. Metade disso era
// contexto repetido — `s`/`sc`/`ec`/`pc`/`op` idênticos em dezenas de linhas
// seguidas — e o rótulo da conta reescrito uma vez por coluna de período.

test('agrupado: uma conta com duas colunas de período vira DUAS linhas, na ordem das colunas', () => {
  const api = { choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({
    moeda: 'BRL', unidade: 'milhar',
    diagnostico: {
      entidade: 'Vertentes Metalúrgica Ltda.', tipo_confirma: true, tipo_sugerido: 'BALANCO',
      periodo_tipo: 'multi', periodo_referencia: '24,25', legibilidade: 'ok',
      nota_legibilidade: null, resumo: 'BP comparativo.', justificativa: 'Cabeçalho bate.',
    },
    grupos: [{
      s: 'Ativo Circulante', sc: 'ativo_circulante', op: 1,
      cols: [{ ec: null, pc: '31/12/2025' }, { ec: null, pc: '31/12/2024' }],
      l: [
        { k: 'Caixa e bancos', vt: ['380', '1.240'], vn: [380, 1240], cf: 0.98 },
        { k: '(-) PCLD', vt: ['(1.900)', '(1.100)'], vn: [-1900, -1100], cf: 0.95 },
      ],
    }],
  }) } }] };
  const r = parseExtracao(api);
  assert.equal(r.campos.length, 4);
  // Conta-maior, coluna-menor: é a ordem de LEITURA do documento, e `ordem` é o
  // que permite ao export reconhecer subtotal impresso acima dos componentes.
  assert.deepEqual(r.campos.map((c) => [c.chave, c.periodo_coluna, c.valor_num]), [
    ['Caixa e bancos', '31/12/2025', 380],
    ['Caixa e bancos', '31/12/2024', 1240],
    ['(-) PCLD', '31/12/2025', -1900],
    ['(-) PCLD', '31/12/2024', -1100],
  ]);
  assert.deepEqual(r.campos.map((c) => c.ordem), [0, 1, 2, 3]);
  // O contexto do grupo desce para TODAS as linhas dele.
  assert.ok(r.campos.every((c) => c.secao === 'Ativo Circulante'
    && c.secao_canonica === 'ativo_circulante' && c.origem_pagina === 1 && c.unidade === 'milhar'
    && c.moeda === 'BRL' && c.entidade_coluna === null));
  assert.equal(r.falhaMotivo, null);
});

test('agrupado: cols VAZIA é o caso de coluna única — um valor por conta', () => {
  const { linhas, problemas } = achatarGrupos([{
    s: 'Passivo Circulante', sc: 'passivo_circulante', op: 2, cols: [],
    l: [{ k: 'Fornecedores', vt: ['12.500'], vn: [12500], cf: 0.9 }],
  }]);
  assert.deepEqual(problemas, []);
  assert.equal(linhas.length, 1);
  assert.equal(linhas[0].periodo_coluna, null);
  assert.equal(linhas[0].entidade_coluna, null);
  assert.equal(linhas[0].valor_num, 12500);
});

test('agrupado: coluna de EMPRESA e de PERÍODO no mesmo mecanismo', () => {
  // O balanço combinado do book tem 7 colunas de empresa. Antes, cada conta era
  // reescrita 7 vezes; agora uma vez, com 7 valores — é onde a economia chega a
  // −79% num documento só.
  const { linhas } = achatarGrupos([{
    s: 'Ativo Circulante', sc: 'ativo_circulante', op: 1,
    cols: [
      { ec: 'Metalúrgica', pc: '2025' }, { ec: 'Componentes', pc: '2025' },
      { ec: 'Eliminações', pc: '2025' }, { ec: 'Combinado', pc: '2025' },
    ],
    l: [{ k: 'Caixa', vt: ['380', '210', '(50)', '540'], vn: [380, 210, -50, 540], cf: 0.9 }],
  }]);
  assert.deepEqual(linhas.map((l) => [l.entidade_coluna, l.valor_num]), [
    ['Metalúrgica', 380], ['Componentes', 210], ['Eliminações', -50], ['Combinado', 540],
  ]);
  assert.ok(linhas.every((l) => l.periodo_coluna === '2025'));
});

test('agrupado: célula em branco ocupa POSIÇÃO e não gera linha', () => {
  // Se o modelo encostasse os valores à esquerda em vez de pôr null na posição,
  // o número de 2024 entraria como se fosse de 2025 — o erro mais caro possível
  // aqui, porque é silencioso e plausível.
  const { linhas, problemas } = achatarGrupos([{
    s: null, sc: 'patrimonio_liquido', op: 1,
    cols: [{ ec: null, pc: '2025' }, { ec: null, pc: '2024' }],
    l: [{ k: 'Reserva legal', vt: [null, '900'], vn: [null, 900], cf: 0.9 }],
  }]);
  assert.deepEqual(problemas, []);
  assert.equal(linhas.length, 1, 'a célula vazia não vira linha');
  assert.deepEqual([linhas[0].periodo_coluna, linhas[0].valor_num], ['2024', 900]);
});

test('o prompt manda declarar COLUNA DE VALOR que não é período nem empresa', () => {
  // O caso real que custou 98 de 99 lançamentos: o `17_Livro_Razao` tem Débito,
  // Crédito e Saldo por linha, o modelo devolveu 3 valores e declarou `cols`
  // VAZIA — o guarda de desalinhamento descartou o documento inteiro. O guarda
  // agiu certo; o que faltava era o prompt dizer que essas colunas existem.
  for (const caso of ['Débito', 'Crédito', 'Saldo', 'A vencer', 'Quantidade']) {
    assert.ok(SYSTEM_PROMPT.includes(caso), `o prompt não nomeia a coluna "${caso}"`);
  }
  assert.match(SYSTEM_PROMPT, /LIVRO RAZÃO/);
  assert.match(SYSTEM_PROMPT, /BALANCETE/);
  assert.match(SYSTEM_PROMPT, /AGING/);
  // E diz a CONSEQUÊNCIA de não declarar, com o número real: instrução sem
  // consequência é instrução que o modelo negocia.
  assert.match(SYSTEM_PROMPT, /98 de 99 lançamentos foram perdidos/);
  // O schema também precisa dizer, senão a `description` do campo contradiz o
  // prompt — e o modelo tende a seguir a que está mais perto do dado.
  const pc = extractionSchema().schema.properties.grupos.items.properties.cols.items.properties.pc;
  assert.match(pc.description, /Débito/);
});

test('o motivo do desalinhamento NOMEIA a causa provável (coluna não declarada)', () => {
  const { problemas } = achatarGrupos([{
    s: 'LIVRO RAZÃO — CONTA 2.1.01.001', sc: 'passivo_circulante', op: 1, cols: [],
    l: [{ k: 'LC-2025-4000 NF 010000', vt: ['12.000', '0', '12.000'], vn: [12000, 0, 12000], cf: 0.9 }],
  }]);
  assert.equal(problemas.length, 1);
  assert.match(problemas[0], /1 coluna\(s\) declarada\(s\), 3 valor\(es\)/);
  assert.match(problemas[0], /Débito\/Crédito\/Saldo, faixas de aging/);
});

test('agrupado: DESALINHAMENTO descarta a conta e VOLTA NOMEADO — nunca adivinha', () => {
  const api = { choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({
    moeda: 'BRL', unidade: 'unidade',
    diagnostico: {
      entidade: null, tipo_confirma: true, tipo_sugerido: 'BALANCO', periodo_tipo: 'multi',
      periodo_referencia: '24,25', legibilidade: 'ok', nota_legibilidade: null,
      resumo: 'x', justificativa: 'y',
    },
    grupos: [{
      s: 'Ativo Circulante', sc: 'ativo_circulante', op: 1,
      cols: [{ ec: null, pc: '2025' }, { ec: null, pc: '2024' }],
      l: [
        { k: 'Caixa', vt: ['380'], vn: [380], cf: 0.9 },                    // falta uma coluna
        { k: 'Estoques', vt: ['1.000', '900'], vn: [1000, 900], cf: 0.9 },  // essa está certa
      ],
    }],
  }) } }] };
  const r = parseExtracao(api);
  // A boa passa; a torta NÃO entra pela metade nem com null inventado.
  assert.deepEqual(r.campos.map((c) => c.chave), ['Estoques', 'Estoques']);
  assert.match(r.falhaMotivo, /1 conta\(s\) descartada\(s\) por desalinhamento/);
  assert.match(r.falhaMotivo, /"Caixa" \(Ativo Circulante\): 2 coluna\(s\) declarada\(s\), 1 valor/);
});

test('agrupado: grupo de TOTAIS chega como NAO_CLASSIFICAVEL → secao_canonica null', () => {
  // A seção canônica é do grupo, então o subtotal impresso dentro de uma seção
  // precisa de grupo próprio — misturá-lo às contas que ele soma faria a seção
  // ser contada duas vezes na planilha. O prompt exige isso explicitamente.
  assert.match(SYSTEM_PROMPT, /abra para ela um grupo PRÓPRIO/);
  const { linhas } = achatarGrupos([{
    s: 'Ativo Circulante', sc: 'NAO_CLASSIFICAVEL', op: 1, cols: [],
    l: [{ k: 'Total do Ativo Circulante', vt: ['45.440'], vn: [45440], cf: 0.99 }],
  }]);
  assert.equal(linhas[0].secao_canonica, null);
  assert.equal(linhas[0].secao, 'Ativo Circulante', 'a seção LIVRE continua sendo a do documento');
});

test('o formato PLANO antigo continua sendo aceito (workflow importado velho)', () => {
  // Em 12/08/2026 o n8n do dono rodou por dias um JSON importado em julho. Um
  // workflow velho responde no formato plano, e "zero linhas extraídas sem
  // explicação" seria a pior forma de descobrir isso.
  const api = { choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({
    moeda: 'BRL', unidade: 'milhar',
    diagnostico: {
      entidade: null, tipo_confirma: true, tipo_sugerido: 'DRE', periodo_tipo: 'anual',
      periodo_referencia: '12M25', legibilidade: 'ok', nota_legibilidade: null,
      resumo: 'x', justificativa: 'y',
    },
    linhas: [{ s: 'Custos', sc: 'custos', ec: null, pc: null, k: 'CPV', vt: '(6.000)', vn: -6000, op: 1, cf: 0.9 }],
  }) } }] };
  const r = parseExtracao(api);
  assert.equal(r.campos.length, 1);
  assert.deepEqual(
    [r.campos[0].chave, r.campos[0].valor_num, r.campos[0].secao_canonica, r.campos[0].unidade],
    ['CPV', -6000, 'custos', 'milhar']);
});

test('achatarGrupos é AUTO-CONTIDA (o nó Code do n8n a embute por toString)', () => {
  // Se ela passar a referenciar constante do módulo, o nó quebra com
  // ReferenceError na primeira execução real e nenhum teste daqui pega.
  const isolada = new Function(`return (${achatarGrupos.toString()})`)();
  const { linhas } = isolada([{ s: 'x', sc: 'custos', op: 1, cols: [], l: [{ k: 'a', vt: ['1'], vn: [1], cf: 1 }] }]);
  assert.equal(linhas.length, 1);
  // E resiste a lixo em vez de estourar: resposta malformada vira "nada
  // extraído com motivo", nunca uma exceção que derruba o item inteiro.
  for (const entrada of [null, undefined, 42, 'x', [null], [{}], [{ l: 'nao-e-array' }]]) {
    assert.deepEqual(isolada(entrada).linhas, [], `entrada ${JSON.stringify(entrada)}`);
  }
});

// ===========================================================================
// O QUE É ESPECÍFICO DE DIALETO — a metade que a tradução das fixturas não cobre
// ===========================================================================
//
// Os testes acima provam que o DOMÍNIO não muda com o provedor. Estes provam a
// fronteira: que a resposta de cada um é lida como ela realmente vem, e que um
// erro do provedor novo é diagnosticado com a mesma precisão que o do antigo —
// que era, literalmente, o que custou o "teste v30".

test('a resposta é lida no dialeto de cada provedor, e o corte por teto é o MESMO fato', () => {
  const conteudo = '{"ok":true}';
  const casos = [
    {
      prov: PROVEDORES.openai,
      ok: { choices: [{ message: { content: conteudo }, finish_reason: 'stop' }] },
      cortada: { choices: [{ message: { content: conteudo }, finish_reason: 'length' }] },
    },
    {
      prov: PROVEDORES.google,
      ok: { candidates: [{ content: { parts: [{ text: conteudo }] }, finishReason: 'STOP' }] },
      cortada: { candidates: [{ content: { parts: [{ text: conteudo }] }, finishReason: 'MAX_TOKENS' }] },
    },
  ];
  for (const { prov, ok, cortada } of casos) {
    assert.equal(conteudoDaResposta(prov, ok), conteudo, prov.id);
    assert.equal(cortadoPorLimite(prov, ok), false, prov.id);
    assert.equal(cortadoPorLimite(prov, cortada), true, prov.id);
    // Resposta vazia é `null`, nunca string vazia: quem lê rio abaixo trata
    // null como "não veio nada" e abre pendência; '' passaria pelo `if` e
    // morreria no JSON.parse, com a mensagem errada.
    assert.equal(conteudoDaResposta(prov, {}), null, prov.id);
  }
});

test('o token de RACIOCÍNIO conta como saída — ele é cobrado como saída', () => {
  // Achado na primeira chamada real (24/08): o catálogo declara `thinking: true`
  // para toda a linha 3.x. Um modelo que pensa gasta orçamento de saída antes de
  // escrever a primeira chave do JSON, e esses tokens vêm em campo próprio.
  //
  // Contar só o `candidates` subdeclarava a conta pela parte que não se vê — e
  // subdeclarar POR CIMA de um teto de gasto é o pior lado para errar.
  const u = usoDaChamada(PROVEDORES.google, {
    usageMetadata: { promptTokenCount: 12000, candidatesTokenCount: 3000, thoughtsTokenCount: 2500 },
  });
  assert.equal(u.completion_tokens, 5500, 'JSON + raciocínio, porque a fatura soma os dois');
  assert.equal(u.thoughts_tokens, 2500, 'e a parcela fica declarada, para se poder decidir sobre ela');

  // A RESPOSTA REAL da chamada de 1 token não traz `candidatesTokenCount` NENHUM
  // (o modelo não chegou a escrever nada). Ausência não pode virar NaN: o custo
  // iria para null e uma chamada paga sumiria do relatório.
  const minima = usoDaChamada(PROVEDORES.google, {
    usageMetadata: { promptTokenCount: 2, totalTokenCount: 2 },
  });
  assert.equal(minima.completion_tokens, 0);
  assert.equal(minima.thoughts_tokens, 0);
  assert.equal(typeof minima.prompt_tokens, 'number');
});

test('o `usage` do Google é traduzido para a forma que a conta de custo já sabia ler', () => {
  // `custoDaChamada` é o único lugar do sistema que faz conta de dinheiro, e ele
  // lê `prompt_tokens`/`completion_tokens`/`cached_tokens`. Traduzir na fronteira
  // é o que impede um segundo formato de `usage` de se espalhar — e é o que faz o
  // relatório de custo continuar comparável entre provedores.
  const u = usoDaChamada(PROVEDORES.google, {
    usageMetadata: { promptTokenCount: 12000, candidatesTokenCount: 3000, cachedContentTokenCount: 2500 },
  });
  assert.equal(u.prompt_tokens, 12000);
  assert.equal(u.completion_tokens, 3000);
  assert.equal(u.prompt_tokens_details.cached_tokens, 2500);
  // Sem bloco de uso, `null` — e não zero. Um custo de zero num relatório de
  // custo é um número INVENTADO, que é pior que um campo vazio.
  assert.equal(usoDaChamada(PROVEDORES.google, {}), null);
  assert.equal(usoDaChamada(PROVEDORES.openai, {}), null);
});

test('diagnosticarErroApi nomeia a causa também no corpo de erro do Google', () => {
  // O corpo do Google não tem `type` e o `code` dele é NÚMERO — antes de
  // 24/08/2026 nada disso era reconhecido como corpo de erro, e um 429 dele
  // teria caído em "desconhecida" com a frase do n8n. É exatamente o cego que
  // custou o v30, agora do outro lado.
  const cadencia = diagnosticarErroApi({
    error: { error: { code: 429, message: 'Quota exceeded for quota metric ... PerMinute', status: 'RESOURCE_EXHAUSTED' } },
  });
  assert.equal(cadencia.causa, 'limite_cadencia');
  assert.equal(cadencia.status, 429, 'o HTTP do Google vem em error.code, e é número');

  const chave = diagnosticarErroApi({
    error: { error: { code: 400, message: 'API key not valid. Please pass a valid API key.', status: 'INVALID_ARGUMENT' } },
  });
  assert.equal(chave.causa, 'chave_invalida');

  const modelo = diagnosticarErroApi({
    error: { error: { code: 404, message: 'models/gemini-x is not found for API version v1beta', status: 'NOT_FOUND' } },
  });
  assert.equal(modelo.causa, 'modelo_indisponivel');

  const cobranca = diagnosticarErroApi({
    error: { error: { code: 403, message: 'This API method requires billing to be enabled', status: 'PERMISSION_DENIED' } },
  });
  assert.equal(cobranca.causa, 'sem_credito',
    'cobrança desligada é falta de dinheiro, não falta de permissão — e a ação é outra');
});

test('a cadência sai do limite MAIS restritivo do provedor, e o Google limita por CHAMADA', () => {
  // Pelo balde de tokens sozinho, 250.000 TPM com reserva de 16.384 dariam ~15
  // chamadas por minuto — que é, por coincidência, o mesmo número. A coincidência
  // não é o ponto: o ponto é que o RPM existe declarado, porque num tier acima o
  // TPM sobe e o RPM pode não subir junto, e aí é ele que manda.
  assert.equal(PROVEDORES.google.rpm, 15);
  assert.equal(PROVEDORES.openai.rpm, null, 'na OpenAI o gargalo é o balde de tokens, não a contagem de chamadas');
});

// O TERCEIRO LIMITE, e é o único que decide se o book de 190 CABE.
//
// TPM e RPM decidem a CADÊNCIA — de quanto em quanto tempo sai a próxima
// chamada. O RPD decide quantos documentos cabem no DIA, somando todos os
// lotes, e ele não estava declarado em lugar nenhum: `diagnosticarErroApi` sabia
// NOMEAR a cota diária estourada depois do estrago, e nada sabia PREVER.
//
// Medido em 27/08/2026 contra o nível gratuito da linha Flash-Lite: o
// `book-canastra` pede 63 chamadas (13% do dia) e o `book-araucaria`, 190
// documentos com metade dos nomes sem tipo+período resolvido, pede ~285 (57%).
// Os dois no mesmo dia passam de 70% da cota antes de qualquer retentativa — e
// o nó de extração tem até 6.
test('o RPD está declarado, porque é ele que decide se o lote cabe no DIA', () => {
  assert.equal(PROVEDORES.google.rpd, 500);
  assert.equal(PROVEDORES.openai.rpd, null,
    'a OpenAI não publica um RPD único para o Tier 1 — `null` diz "não sei", que não é "não tem"');

  // A cadência não protege do RPD, e confundir os dois leva à conclusão errada
  // de que espaçar mais as chamadas resolveria: espaçar resolve 429 por MINUTO;
  // a cota do dia só reabre na virada da janela.
  const porMinuto = 60 / 8; // o batchInterval dos dois nós de IA
  const minutosParaEsgotarODia = PROVEDORES.google.rpd / porMinuto;
  assert.ok(minutosParaEsgotarODia < 8 * 60,
    `a ${porMinuto}/min a cota do dia acaba em ${Math.round(minutosParaEsgotarODia)} min — `
    + 'se este número passar de um dia de trabalho, o RPD deixou de ser o gargalo e este teste envelheceu');
});

// --- Número colado no rótulo (Balanço 2025 real, Krauspenhar) ---------------
// A chave real gravada foi "2 113.860.002,40PASSIVO": o valor da linha
// (113.860.002,40) vazou para o rótulo e a reconciliação acusou "Passivo+PL não
// localizado". A chave e o valor vêm da produção; a estrutura do grupo em volta
// (seção, coluna "2025") é a mínima, não a extração inteira.
const grupoComChave = (k, vn, vt) => [{
  s: 'Passivo', sc: 'passivo_circulante', op: 1, cols: [{ ec: null, pc: '2025' }],
  l: [{ k, vt: [vt], vn: [vn], cf: 0.9 }],
}];

test('rótulo com o VALOR DA LINHA colado: o número sai do rótulo e a conta fica', () => {
  const r = achatarGrupos(grupoComChave('2 113.860.002,40PASSIVO', 113860002.4, '113.860.002,40'));
  assert.equal(r.linhas.length, 1);
  assert.equal(r.linhas[0].chave, '2 PASSIVO');
  assert.equal(r.linhas[0].valor_num, 113860002.4, 'o valor não muda');
  assert.deepEqual(r.rotulosSuspeitos, []);
  assert.deepEqual(r.problemas, []);
});

test('rótulo com número colado que NÃO é o valor da linha: nada é apagado, e é declarado com a chave crua', () => {
  const r = achatarGrupos(grupoComChave('Emprestimo 2.500,00parcelas', 9000, '9.000,00'));
  assert.equal(r.linhas.length, 1, 'a conta não é descartada');
  assert.equal(r.linhas[0].chave, 'Emprestimo 2.500,00parcelas', 'o rótulo NÃO é reescrito por palpite');
  assert.equal(r.rotulosSuspeitos.length, 1);
  assert.match(r.rotulosSuspeitos[0], /"Emprestimo 2\.500,00parcelas"/);
  assert.match(r.rotulosSuspeitos[0], /2\.500,00/);
});

test('número monetário com ESPAÇO no rótulo não é "colado" e passa intacto', () => {
  const r = achatarGrupos(grupoComChave('Saldo em 31/12 1.234,56 reais', 50, '50'));
  assert.equal(r.linhas[0].chave, 'Saldo em 31/12 1.234,56 reais');
  assert.deepEqual(r.rotulosSuspeitos, []);
});

test('o motivo da falha nomeia o rótulo suspeito (falhaMotivo)', () => {
  const api = { choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({
    moeda: 'BRL', unidade: 'unidade',
    diagnostico: {
      entidade: null, tipo_confirma: true, tipo_sugerido: 'BALANCO', periodo_tipo: 'anual',
      periodo_referencia: '25', legibilidade: 'ok', nota_legibilidade: null,
      resumo: 'x', justificativa: 'y',
    },
    grupos: grupoComChave('Emprestimo 2.500,00parcelas', 9000, '9.000,00'),
  }) } }] };
  const r = parseExtracao(api);
  assert.match(r.falhaMotivo, /1 rótulo\(s\) com número colado que não é o valor da linha/);
  assert.match(r.falhaMotivo, /Emprestimo 2\.500,00parcelas/);
});

// AS 72 LINHAS REAIS do caso Krauspenhar (consulta de produção, 30/09/2026, só
// leitura): 64 do Balanço 2025, em que o valor da linha vazou para o rótulo, e 8
// do balancete, em que a chave é SÓ o número. [chave, valor_num] copiados.
const BALANCO_COLADO = [
  ['849 -3.630,00(-) INSTALAÇÕES', -3630],
  ['853 -163.412,25(-) COMPUTADORES E PERIFÉRICOS', -163412.25],
  ['850 -325.460,82(-) FERRAMENTAS', -325460.82],
  ['843 -241.862,11(-) MAQUINAS E EQUIPAMENTOS', -241862.11],
  ['851 -266.484,53(-) MOVEIS E UTENSILIOS', -266484.53],
  ['841 -715.148,30(-) PRÉDIOS E CONSTRUÇÕES', -715148.3],
  ['852 -1.592.900,65(-) VEÍCULOS', -1592900.65],
  ['1.02.02.05 1.275,00INTANGIVEL', 1275],
  ['656 1.275,00MARCAS, DIREITOS E PATENTES', 1275],
  ['1.80 0,00CONTAS TEMPORARIAS', 0],
  ['1.80.01 0,00CONTAS TEMPORARIAS', 0],
  ['350000 0,00COMPRAS A DISTRIBUIR', 0],
  ['350003 0,00DEVOLUÇÃO DE COMPRAS A DISTRIBUIR', 0],
  ['350002 0,00DEVOLUÇÃO DE VENDAS A DISTRIBUIR', 0],
  ['6650 0,00FORMACAO DE KIT', 0],
  ['350005 0,00FRETES A DISTRIBUIR', 0],
  ['5748 0,00TRANSITORIA DO FINANCEIRO', 0],
  ['350001 0,00VENDAS A DISTRIBUIR', 0],
  ['2 113.860.002,40PASSIVO', 113860002.4],
  ['2.01 59.064.131,02CIRCULANTE', 59064131.02],
  ['2.01.01 13.123.466,79EMPRESTIMOS', 13123466.79],
  ['2.01.01.01 15.563.518,86EMPRESTIMOS BANCÁRIOS', 15563518.86],
  ['8241 2.213.181,84CAPITAL DE GIRO BANCO BRADESCO 23702524980 - C', 2213181.84],
  ['6345 1.758.642,42CAPITAL DE GIRO BANCO BRADESCO 23702525000 - C', 1758642.42],
  ['7614 0,00CAPITAL DE GIRO BANCO BRADESCO 570942203 - CP', 0],
  ['3635 0,00CAPITAL DE GIRO BANCO BRADESCO AVAL- FGI/PEA', 0],
  ['6036 0,00CAPITAL DE GIRO BANCO DO BRASIL 328318885 - CP', 0],
  ['6338 0,00CAPITAL DE GIRO BANCO DO BRASIL 420502766 - CP', 0],
  ['7286 0,00CAPITAL DE GIRO BANCO DO BRASIL 650326 - CP', 0],
  ['7747 0,00CAPITAL DE GIRO BANCO DO BRASIL 697056 - CP', 0],
  ['7833 444.444,46CAPITAL DE GIRO BANCO DO BRASIL 707679 - CP', 444444.46],
  ['8286 1.323.529,42CAPITAL DE GIRO BANCO DO BRASIL 747979 - CP', 1323529.42],
  ['8295 1.000.000,00CAPITAL DE GIRO BANCO DO BRASIL 751291 - CP', 1000000],
  ['8438 175.000,00CAPITAL DE GIRO BANCO DO BRASIL 763771 - CP', 175000],
  ['8921 2.000.000,00CAPITAL DE GIRO BANCO DO BRASIL 790051 - CP', 2000000],
  ['8950 1.500.000,00CAPITAL DE GIRO BANCO DO BRASIL 790721 - CP', 1500000],
  ['8922 500.000,00CAPITAL DE GIRO BANCO DO BRASIL 790800 - CP', 500000],
  ['8923 500.000,00CAPITAL DE GIRO BANCO DO BRASIL 792652 - CP', 500000],
  ['8920 500.000,00CAPITAL DE GIRO BANCO DO BRASIL 792663 - CP', 500000],
  ['7832 1.200.000,00CAPITAL DE GIRO BANCO SICREDI 40627207-3 - CP', 1200000],
  ['7745 866.666,67CAPITAL DE GIRO BANCO SICREDI 40636095-9 - CP', 866666.67],
  ['8924 1.582.054,05CAPITAL DE GIRO BANCO SICREDI 50626263-0 - CP', 1582054.05],
  ['2.01.01.02 -2.440.052,07(-) JUROS S/EMPRESTIMOS E FINANCIAMENTOS', -2440052.07],
  ['9131 -962.002,83(-) JUROS A APROPRIAR', -962002.83],
  ['8246 -969.406,84(-) JUROS CAPITAL DE GIRO BRADESCO 23702524980', -969406.84],
  ['6557 -508.642,40(-) JUROS CAPITAL DE GIRO BRADESCO 23702525000', -508642.4],
  ['2.01.03 39.827.828,28FORNECEDORES', 39827828.28],
  ['2.01.03.01 39.827.828,28FORNECEDORES', 39827828.28],
  ['2.01.04 16.494,33CONTAS A PAGAR', 16494.33],
  ['2.01.04.01 16.494,33OBRIGAÇÕES DE CURTO PRAZO', 16494.33],
  ['2362 0,00IPTU A PAGAR', 0],
  ['1920 0,00IPVA/DPVAT A PAGAR', 0],
  ['1921 16.494,33SEGUROS A PAGAR', 16494.33],
  ['2.01.05 403.156,29TRIBUTOS A RECOLHER', 403156.29],
  ['2.01.05.01 403.156,29TRIBUTOS E RETENÇÕES A RECOLHER', 403156.29],
  ['180 12.562,79COFINS A RECOLHER', 12562.79],
  ['513 268.247,34ICMS A RECOLHER', 268247.34],
  ['2185 0,00ICMS DIFERENCIAL DE ALIQUOTA', 0],
  ['2712 118.033,83ICMS ST', 118033.83],
  ['173 1.439,86ISS A RECOLHER', 1439.86],
  ['179 2.497,16PIS A RECOLHER', 2497.16],
  ['2121 375,31PIS/COFINS/CSLL/IR RETIDO A RECOLHER', 375.31],
  ['2.01.05.02 0,00PARCELAMENTOS FISCAIS - CP', 0],
  ['8512 0,00(-) JUROS S/ PARCELAMENTO ICMS 11361027', 0],
];
const BALANCETE_SO_NUMERO = [
  ['21.493.237,90', 'Saldo anterior', 21493237.9],
  ['21.493.237,90', 'Saldo atual', 0],
  ['21.493.237,90', 'Crédito', 3030000.08],
  ['21.493.237,90', 'Débito', 24523237.98],
  ['-3.308.898,66', 'Saldo atual', -359507.62],
  ['-3.308.898,66', 'Saldo anterior', -3308898.66],
  ['-3.308.898,66', 'Débito', -3389319.44],
  ['-3.308.898,66', 'Crédito', 279086.84],
];

test('REAL: as 64 chaves do Balanço 2025 com o valor colado saem limpas, e o valor não muda', () => {
  assert.equal(BALANCO_COLADO.length, 64);
  for (const [chave, valor] of BALANCO_COLADO) {
    const r = achatarGrupos(grupoComChave(chave, valor, String(valor)));
    assert.equal(r.linhas.length, 1, chave);
    assert.equal(r.linhas[0].valor_num, valor, chave);
    assert.doesNotMatch(r.linhas[0].chave, /\d{1,3}(\.\d{3})*,\d{2}/, `sobrou número em ${chave}`);
    assert.match(r.linhas[0].chave, /[A-Za-z]/, `o rótulo virou vazio em ${chave}`);
    assert.deepEqual(r.rotulosSuspeitos, [], chave);
  }
  const exato = achatarGrupos(grupoComChave('849 -3.630,00(-) INSTALAÇÕES', -3630, '-3.630,00'));
  assert.equal(exato.linhas[0].chave, '849 (-) INSTALAÇÕES');
});

test('REAL: balancete com a chave SÓ número — a conta fica, o rótulo não é inventado, e é declarado', () => {
  const porChave = new Map();
  for (const [chave, pc, v] of BALANCETE_SO_NUMERO) {
    if (!porChave.has(chave)) porChave.set(chave, []);
    porChave.get(chave).push([pc, v]);
  }
  let declarados = 0;
  for (const [chave, colunas] of porChave) {
    const r = achatarGrupos([{
      s: 'Balancete', sc: 'NAO_CLASSIFICAVEL', op: 1,
      cols: colunas.map(([pc]) => ({ ec: null, pc })),
      l: [{ k: chave, vt: colunas.map(([, v]) => String(v)), vn: colunas.map(([, v]) => v), cf: 0.9 }],
    }]);
    assert.equal(r.linhas.length, colunas.length, 'nenhum valor é descartado');
    assert.ok(r.linhas.every((l) => l.chave === chave), 'o rótulo NÃO é reescrito');
    assert.equal(r.rotulosSuspeitos.length, 1, chave);
    assert.match(r.rotulosSuspeitos[0], /SÓ um número/);
    declarados += 1;
  }
  assert.ok(declarados >= 1);
});

test('frases legítimas com valor no meio do texto NÃO são mexidas (contrato social, DRE)', () => {
  for (const k of ['O Capital Social será de R$ 100.000,00 (cem mil reais)', 'PREJUÍZO DE 10.058,20']) {
    const r = achatarGrupos(grupoComChave(k, 100000, '100.000,00'));
    assert.equal(r.linhas[0].chave, k);
    assert.deepEqual(r.rotulosSuspeitos, [], k);
  }
});
