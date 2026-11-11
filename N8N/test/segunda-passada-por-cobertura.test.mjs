// SEGUNDA PASSADA POR COBERTURA — o bloco que volta pela metade é refeito UMA vez.
//
// O DEFEITO (Fw Valtra, 05/10/2026): "36 ALTERAÇÃO E CONSOLIDAÇÃO CONTRATUAL - MOTO
// AGRICOLA.pdf" saiu com 59 linhas devolvidas para 101 no texto (58% de cobertura).
// `Juntar Blocos` já acusava, abrindo pendência; ninguém tentava de novo.
//
// ESTES TESTES AFIRMAM COMPORTAMENTO (regra 3): quantas vezes o provedor é chamado,
// o que o bloco vira, quanto custa, o que a pendência diz. O percurso é o do GRAFO
// REAL — o driver segue as `connections` do JSON gerado e executa o código REAL de
// `Medir Documento`, `Fatiar Extracao`, `Parse Extracao` (e os estágios de repetição)
// e `Juntar Blocos`.
//
// O QUE ELES NÃO PROVAM, e é a metade que importa: que o modelo, ao ler a instrução
// reforçada, devolve MAIS linhas. Isso só uma rodada real diz — o item de cada bloco
// grava `cobertura_bloco_primeira` e `cobertura_bloco` para que a primeira rodada
// meça o ganho em vez de supô-lo (regra 4: nenhum teste aqui finge a resposta do
// modelo como prova de que ele a dará). Também não provam o pareamento
// `$('Esperar Retry k').item` do motor do n8n, que só o editor confirma.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { provedor } from '../lib/provedor.mjs';
import { decidirRepeticao } from '../lib/extract.mjs';
import { linhasDeConta, linhasComNumero, contasPorLinhaComNumero, planejarFatias, celulasEstimadas } from '../lib/cobertura.mjs';

const wf = JSON.parse(readFileSync(new URL('../workflow.e1-ingestao.json', import.meta.url)));
const porNome = Object.fromEntries(wf.nodes.map((n) => [n.name, n]));
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor;
const GEMINI = provedor().dialeto === 'gemini';
const MAX = decidirRepeticao().maxTentativas;

// --- o corpo da chamada e as respostas ------------------------------------------
const corpoBase = () => (GEMINI
  ? { contents: [{ parts: [{ text: 'BASE' }] }] }
  : { messages: [{ role: 'user', content: [{ type: 'text', text: 'BASE' }] }] });
const textoDoCorpo = (b) => (GEMINI ? b.contents[b.contents.length - 1].parts[0].text : b.messages[b.messages.length - 1].content[0].text);

const USO = { prompt_tokens: 1000, completion_tokens: 500, prompt_tokens_details: { cached_tokens: 0 } };
const resposta = (texto, { cortada = false } = {}) => {
  if (GEMINI) {
    return { candidates: [{ content: { parts: [{ text: texto }] }, finishReason: cortada ? 'MAX_TOKENS' : 'STOP' }],
      usageMetadata: { promptTokenCount: USO.prompt_tokens, candidatesTokenCount: USO.completion_tokens, cachedContentTokenCount: 0 } };
  }
  return { choices: [{ message: { content: texto }, finish_reason: cortada ? 'length' : 'stop' }], usage: USO };
};
// Uma resposta com `n` LINHAS do documento, rotuladas com `rotulo` — o rótulo é como
// se sabe, depois, de qual passada cada linha veio.
const linhasN = (n, rotulo = 'Conta', { tem = true, cortada = false } = {}) => resposta(JSON.stringify({
  moeda: 'BRL', unidade: 'R$',
  diagnostico: { entidade: 'Moto Agricola Ltda.', tipo_confirma: true, tipo_sugerido: 'BALANCO', periodo_tipo: 'anual',
    periodo_referencia: '2023', legibilidade: 'ok', nota_legibilidade: null, resumo: 'x', justificativa: 'y', tem_dado_financeiro: tem },
  grupos: n === 0 ? [] : [{ s: 'Ativo', sc: 'ativo_circulante', op: 1, cols: [{ ec: null, pc: '31/12/2023' }],
    l: Array.from({ length: n }, (_, i) => ({ k: `${rotulo} ${i}`, vt: [String(i + 1)], vn: [i + 1], cf: 0.95 })) }],
}), { cortada });
const RATE = () => ({ error: { message: 'Rate limit reached on tokens per min (TPM): Limit 500000. Please try again in 6.8s.', type: 'tokens', code: 'rate_limit_exceeded' } });
const RECUSA = () => ({ error: { message: 'Invalid schema for response_format', type: 'invalid_request_error', code: 'invalid_json_schema' } });
const VAZIA = () => resposta('');

// --- o driver --------------------------------------------------------------------
async function rodarNo(nome, { item, items, refs = {}, esperas = [] }) {
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

/**
 * UM bloco atravessa o grafo real, do primeiro `Parse Extracao` até sair para o
 * `Juntar Tentativas`. `respostas[i]` é o que o provedor devolve na chamada i+1;
 * além do fim da lista, devolve a ÚLTIMA de novo. Devolve também os CORPOS enviados
 * em cada chamada (o que o `IA Extrair` mandaria): é neles que se vê a instrução.
 */
async function atravessar(respostas, { ctx = {} } = {}) {
  const base = { documento_id: 'doc-1', documento_versao_id: 'ver-1', bloco: 1, blocos: 1,
    contas_no_documento: 101, contas_do_bloco: 101, ia_body: corpoBase(), ...ctx };
  const refs = { 'Fatiar Extracao': { json: base } };
  const esperas = [];
  const corpos = [base.ia_body];
  let chamadas = 0;
  let nomeParse = 'Parse Extracao';
  for (;;) {
    const r = respostas[Math.min(chamadas, respostas.length - 1)];
    chamadas += 1;
    const saida = await rodarNo(nomeParse, { item: { json: r }, refs, esperas });
    const [proximo] = seguinte(nomeParse);
    if (proximo === 'Juntar Tentativas') return { saida, chamadas, esperas, corpos };
    if (saida.json.repetir !== true) return { saida, chamadas, esperas, corpos };
    const [esperar] = seguinte(proximo, 0);
    const aposEsperar = await rodarNo(esperar, { items: [saida], refs, esperas });
    refs[esperar] = { json: aposEsperar[0].json };
    corpos.push(aposEsperar[0].json.ia_body);
    const [ia] = seguinte(esperar);
    [nomeParse] = seguinte(ia);
  }
}
const linhasDistintas = (campos) => new Set(campos.map((c) => c.linha_origem)).size;
const rotulos = (campos) => new Set(campos.map((c) => c.chave.split(' ')[0]));
const custoDe = (r) => r.saida.json.custo_usd;

// --- comportamento ----------------------------------------------------------------

test('bloco com 58% de cobertura é REFEITO e fica com a segunda, que veio completa (o 36 ALTERAÇÃO)', async () => {
  const r = await atravessar([linhasN(59, 'Primeira'), linhasN(100, 'Segunda')]);
  assert.equal(r.chamadas, 2, 'foi chamado duas vezes');
  assert.equal(linhasDistintas(r.saida.json.campos), 100, 'ficou a passada de 100 linhas');
  assert.deepEqual([...rotulos(r.saida.json.campos)], ['Segunda'], 'nenhuma linha da primeira passada sobrou');
  assert.equal(r.saida.json.falha_motivo, null, 'a segunda passada recuperou: NÃO há pendência');
  assert.equal(r.saida.json.passadas, 2);
  assert.equal(r.saida.json.cobertura_bloco_primeira, 0.584, 'a rodada real lê aqui o que a primeira passada fez');
  assert.equal(r.saida.json.cobertura_bloco, 0.99);
  assert.deepEqual(r.esperas, [], 'cobertura não é limite de cadência: não se espera 30 s por ela');
});

test('a segunda chamada leva a instrução reforçada COM OS NÚMEROS; a primeira não', async () => {
  const r = await atravessar([linhasN(59), linhasN(100)]);
  assert.equal(r.corpos.length, 2);
  assert.equal(textoDoCorpo(r.corpos[0]), 'BASE', 'a primeira chamada vai sem a instrução');
  const t = textoDoCorpo(r.corpos[1]);
  assert.match(t, /^BASE/, 'a instrução é ACRESCENTADA à mensagem de usuário, o resto fica');
  assert.match(t, /SEGUNDA PASSADA POR COBERTURA/);
  assert.match(t, /59 linha\(s\)/, 'diz quantas linhas ele devolveu');
  assert.match(t, /101 linhas de conta/, 'e quantas o texto tem');
  assert.match(t, /SUBSTITUI a anterior/, 'a resposta substitui — devolver só o que faltou perderia o trabalho');
});

test('bloco com 100% de cobertura NÃO é refeito: uma chamada, nenhuma instrução', async () => {
  const r = await atravessar([linhasN(101, 'Unica'), linhasN(101, 'Outra')]);
  assert.equal(r.chamadas, 1);
  assert.equal(r.corpos.length, 1);
  assert.equal(r.saida.json.passadas, 1);
  assert.equal(r.saida.json.falha_motivo, null);
  assert.deepEqual([...rotulos(r.saida.json.campos)], ['Unica']);
  assert.equal(r.saida.json.cobertura_bloco_primeira, null);
});

test('no limiar exato NÃO refaz; um pouco abaixo refaz (o limiar é o do documento: 85%)', async () => {
  const noLimiar = await atravessar([linhasN(86), linhasN(101)]);      // 86/101 = 85,1%
  assert.equal(noLimiar.chamadas, 1, '85,1% está acima do limiar');
  const abaixo = await atravessar([linhasN(85), linhasN(101)]);        // 85/101 = 84,2%
  assert.equal(abaixo.chamadas, 2, '84,2% está abaixo');
});

test('NUNCA soma as duas respostas: a segunda melhor SUBSTITUI, não complementa', async () => {
  const r = await atravessar([linhasN(59, 'Primeira'), linhasN(80, 'Segunda')]);
  assert.equal(r.saida.json.campos.length, 80, '80, não 59 + 80');
  assert.deepEqual([...rotulos(r.saida.json.campos)], ['Segunda']);
});

test('segunda passada PIOR ou IGUAL: fica a primeira (a que já estava paga)', async () => {
  const pior = await atravessar([linhasN(59, 'Primeira'), linhasN(40, 'Segunda')]);
  assert.equal(pior.saida.json.campos.length, 59);
  assert.deepEqual([...rotulos(pior.saida.json.campos)], ['Primeira']);
  const igual = await atravessar([linhasN(59, 'Primeira'), linhasN(59, 'Segunda')]);
  assert.deepEqual([...rotulos(igual.saida.json.campos)], ['Primeira'], 'empate fica com a primeira');
  assert.equal(igual.saida.json.campos.length, 59);
});

test('segunda passada TAMBÉM abaixo do limiar: a pendência diz "2 tentativas" e os dois números', async () => {
  const r = await atravessar([linhasN(59, 'Primeira'), linhasN(61, 'Segunda')]);
  assert.equal(r.chamadas, 2, 'só UMA segunda passada, nunca uma terceira por cobertura');
  assert.equal(r.saida.json.campos.length, 61, 'ficou a melhor, 61');
  const m = r.saida.json.falha_motivo;
  assert.match(m, /mesmo apos 2 tentativas/);
  assert.match(m, /1a devolveu 59 de ~101/);
  assert.match(m, /2a, 61/);
  assert.match(m, /NAO se somam/, 'diz que o que falta continua faltando');
  assert.equal(r.saida.json.passadas, 2);
});

test('segunda passada que FALHA (400): fica a primeira e a falha da segunda não some em silêncio', async () => {
  const r = await atravessar([linhasN(59, 'Primeira'), RECUSA()]);
  assert.equal(r.chamadas, 2, 'a recusa 400 não é repetida');
  assert.equal(r.saida.json.campos.length, 59);
  assert.deepEqual([...rotulos(r.saida.json.campos)], ['Primeira']);
  assert.match(r.saida.json.falha_motivo, /segunda passada por cobertura falhou/);
  assert.match(r.saida.json.falha_motivo, /mesmo apos 2 tentativas/);
});

test('segunda passada que toma 429 espera, repete e NÃO perde a primeira', async () => {
  const r = await atravessar([linhasN(59, 'Primeira'), RATE(), linhasN(100, 'Segunda')]);
  assert.equal(r.chamadas, 3);
  assert.deepEqual(r.esperas, [60_000], 'só a espera do 429 (60 s: o piso da 2ª tentativa); a da cobertura foi zero');
  assert.equal(r.saida.json.campos.length, 100);
  assert.equal(r.saida.json.falha_motivo, null);
  assert.match(textoDoCorpo(r.corpos[2]), /SEGUNDA PASSADA/, 'a repetição do 429 reenvia a instrução reforçada, não a original');
  assert.equal((textoDoCorpo(r.corpos[2]).match(/SEGUNDA PASSADA/g) || []).length, 1, 'e só uma vez');
});

test('429 persistente na segunda passada: o teto de 4 chamadas por bloco vale, e fica a primeira', async () => {
  const r = await atravessar([linhasN(59, 'Primeira'), RATE()]);
  assert.equal(r.chamadas, MAX, 'nunca mais que o teto por bloco, somando cobertura e transitória');
  assert.deepEqual([...rotulos(r.saida.json.campos)], ['Primeira']);
  assert.match(r.saida.json.falha_motivo, /segunda passada por cobertura falhou/);
});

test('o teto é UM SÓ: bloco que gastou 3 chamadas em 429 e voltou baixo na 4ª não é refeito — e DIZ por quê', async () => {
  const r = await atravessar([RATE(), RATE(), RATE(), linhasN(59)]);
  assert.equal(r.chamadas, MAX);
  assert.equal(r.saida.json.campos.length, 59);
  assert.match(r.saida.json.falha_motivo, /segunda passada NAO foi feita/);
  assert.match(r.saida.json.falha_motivo, /teto de 4 chamadas/);
});

test('documento SEM dado financeiro e zero linhas NÃO é refeito (a exceção da 0111, a mesma do documento)', async () => {
  const r = await atravessar([linhasN(0, 'Certidao', { tem: false }), linhasN(100)]);
  assert.equal(r.chamadas, 1, 'pagar uma segunda chamada por uma certidão seria desperdício');
  assert.equal(r.saida.json.falha_motivo, null);
});

test('mas zero linhas SEM essa declaração É refeito (ausência não é dado)', async () => {
  const r = await atravessar([linhasN(0, 'Vazia', { tem: true }), linhasN(100, 'Cheia')]);
  assert.equal(r.chamadas, 2);
  assert.equal(r.saida.json.campos.length, 100);
});

test('bloco que o guarda não avalia (denominador pequeno ou desconhecido) NÃO é refeito', async () => {
  const pequeno = await atravessar([linhasN(5), linhasN(10)], { ctx: { contas_do_bloco: 10 } });
  assert.equal(pequeno.chamadas, 1, 'abaixo do mínimo de 20 linhas a razão é ruído');
  const semMedida = await atravessar([linhasN(5), linhasN(100)], { ctx: { contas_do_bloco: null } });
  assert.equal(semMedida.chamadas, 1, 'sem texto (PDF escaneado) não há denominador: não se inventa zero');
});

test('resposta TRUNCADA por limite de tokens não é refeita por cobertura (cortaria igual)', async () => {
  const r = await atravessar([resposta('{"grupos":[{"s":"Ati', { cortada: true }), linhasN(100)]);
  assert.equal(r.chamadas, 1);
  assert.match(r.saida.json.falha_motivo, /truncada/);
});

test('resposta cortada por limite mas com JSON VÁLIDO também não é refeita por cobertura', async () => {
  const r = await atravessar([linhasN(59, 'Cortada', { cortada: true }), linhasN(100)]);
  assert.equal(r.chamadas, 1, 'o corte é o teto de saída: pedir de novo cortaria no mesmo ponto');
  assert.match(r.saida.json.falha_motivo, /limite de tokens/);
});

test('o CUSTO é o das duas chamadas, ganhe a que ganhar', async () => {
  const uma = await atravessar([linhasN(101)]);
  const duasGanhaSegunda = await atravessar([linhasN(59), linhasN(100)]);
  const duasGanhaPrimeira = await atravessar([linhasN(59), linhasN(40)]);
  assert.ok(custoDe(uma) > 0, 'a medição do custo de uma chamada não é vazia');
  assert.ok(Math.abs(custoDe(duasGanhaSegunda) - 2 * custoDe(uma)) < 1e-9);
  assert.ok(Math.abs(custoDe(duasGanhaPrimeira) - 2 * custoDe(uma)) < 1e-9, 'a segunda foi paga mesmo tendo perdido');
  assert.equal(duasGanhaSegunda.saida.json.tokens.entrada, 2 * USO.prompt_tokens);
});

// --- de ponta a ponta com o texto REAL de produção ---------------------------------
const CAPTURA = JSON.parse(readFileSync(new URL('../../Dados de Teste/capturas/2026-08-31-texto-extraido-n8n/textos.json', import.meta.url), 'utf8'));
const LIVRO = Object.entries(CAPTURA.documentos).find(([nome]) => nome.startsWith('17_Livro_Razao'));

test('PONTA A PONTA no livro razão de produção (99 contas, 4 blocos): só o bloco que veio pela metade é refeito', async () => {
  assert.ok(LIVRO, 'a captura de produção traz o livro razão');
  const texto = LIVRO[1].texto;
  const medido = await rodarNo('Medir Documento', { item: { json: { text: texto } }, refs: { 'Preparar Conteudo': { json: { ia_body: corpoBase(), documento_id: 'doc-1', documento_versao_id: 'ver-1' } } } });
  assert.equal(medido.json.contas_no_documento, 99);
  const fatiado = await rodarNo('Fatiar Extracao', { items: [medido] });
  assert.equal(fatiado.length, 4, 'o livro razão sai em 4 blocos');
  const doBloco = fatiado.map((f) => f.json.contas_do_bloco);
  assert.equal(doBloco.reduce((a, b) => a + b, 0), 99, 'a soma dos denominadores dos blocos É o do documento');
  assert.ok(doBloco.every((n) => n >= 20), `todo bloco é avaliável (>= 20 contas): ${doBloco}`);

  // Bloco 2 volta com 40% das linhas na primeira vez e completo na segunda.
  let chamadas = 0;
  const saidas = [];
  for (const f of fatiado) {
    const n = f.json.contas_do_bloco;
    const respostas = f.json.bloco === 2 ? [linhasN(Math.round(n * 0.4), 'P'), linhasN(n, 'S')] : [linhasN(n, 'P')];
    const r = await atravessar(respostas, { ctx: f.json });
    chamadas += r.chamadas;
    saidas.push(r.saida);
  }
  assert.equal(chamadas, 5, '4 blocos + 1 segunda passada (só o bloco 2)');
  const juntado = await rodarNo('Juntar Blocos', { items: saidas });
  assert.equal(juntado.length, 1);
  assert.equal(juntado[0].json.linhas_devolvidas, 99, 'o documento fechou inteiro');
  assert.equal(juntado[0].json.cobertura, 1);
  assert.equal(juntado[0].json.falha_motivo, null, 'recuperado: nenhuma pendência');
  assert.equal(juntado[0].json.blocos_refeitos, 1);
});

test('PONTA A PONTA: sem a segunda passada o MESMO documento abre pendência de cobertura (o que existia)', async () => {
  const texto = LIVRO[1].texto;
  const medido = await rodarNo('Medir Documento', { item: { json: { text: texto } }, refs: { 'Preparar Conteudo': { json: { ia_body: corpoBase(), documento_id: 'doc-1', documento_versao_id: 'ver-1' } } } });
  const fatiado = await rodarNo('Fatiar Extracao', { items: [medido] });
  const saidas = [];
  for (const f of fatiado) {
    const n = f.json.contas_do_bloco;
    // todos os blocos a 50%, sempre: nem a segunda passada recupera
    const r = await atravessar([linhasN(Math.round(n * 0.5), 'P')], { ctx: f.json });
    saidas.push(r.saida);
  }
  const juntado = await rodarNo('Juntar Blocos', { items: saidas });
  assert.match(juntado[0].json.falha_motivo, /Extração INCOMPLETA/, 'a guarda do documento continua acusando');
  assert.match(juntado[0].json.falha_motivo, /mesmo apos 2 tentativas/, 'e a pendência agora diz que houve 2 tentativas por bloco');
  assert.equal(juntado[0].json.blocos_refeitos, 4);
});

// --- a contagem por bloco ----------------------------------------------------------
test('os denominadores por bloco SOMAM o do documento em todos os 20 documentos de produção, em qualquer fatiamento', () => {
  let comConta = 0;
  for (const [nome, d] of Object.entries(CAPTURA.documentos)) {
    const total = linhasDeConta(d.texto).length;
    const porLinha = contasPorLinhaComNumero(d.texto);
    const linhas = linhasComNumero(d.texto);
    if (total > 0) comConta += 1;
    if (linhas.length === 0) continue;
    assert.ok(Array.isArray(porLinha), `${nome}: a contagem por linha é medível`);
    assert.equal(porLinha.length, linhas.length, `${nome}: uma posição por linha de linhasComNumero`);
    assert.equal(porLinha.reduce((a, b) => a + b, 0), total, `${nome}: a soma é a contagem do documento`);
    for (const max of [234, 60, 30]) {
      const fatias = planejarFatias(linhas, max, celulasEstimadas(linhas));
      const soma = fatias.reduce((s, f) => s + porLinha.slice(f.de, f.ate + 1).reduce((a, b) => a + b, 0), 0);
      assert.equal(soma, total, `${nome}: fatiado com teto ${max} em ${fatias.length} bloco(s), os blocos somam o documento`);
    }
  }
  assert.ok(comConta >= 15, `a medição não é vazia: ${comConta} documentos com conta`);
});

test('recontar a FATIA erra onde a tabela é larga — é por isso que a contagem é feita no texto inteiro', () => {
  // Regra 4: o arranjo é o REAL (livro razão capturado de produção), não fixture.
  const texto = LIVRO[1].texto;
  const linhas = linhasComNumero(texto);
  const fatias = planejarFatias(linhas, 234, celulasEstimadas(linhas));
  const porRecontagem = fatias.reduce((s, f) => s + linhasDeConta(linhas.slice(f.de, f.ate + 1).join('\n')).length, 0);
  assert.equal(linhasDeConta(texto).length, 99);
  assert.notEqual(porRecontagem, 99, `recontar a fatia dá ${porRecontagem} onde o documento tem 99: refaria todo bloco perfeito`);
});

test('Fatiar Extracao: sem o vetor de contas (documento antigo) o bloco fica SEM medida, não com zero', async () => {
  const linhas = ['Caixa 100', 'Bancos 200'];
  const f = await rodarNo('Fatiar Extracao', { items: [{ json: { linhas_do_texto: linhas, ia_body: corpoBase(), documento_versao_id: 'v' } }] });
  assert.equal(f[0].json.contas_do_bloco, null);
  const desalinhado = await rodarNo('Fatiar Extracao', { items: [{ json: { linhas_do_texto: linhas, contas_por_linha: [1], ia_body: corpoBase(), documento_versao_id: 'v' } }] });
  assert.equal(desalinhado[0].json.contas_do_bloco, null, 'vetor que não casa com as linhas não é usado');
});
