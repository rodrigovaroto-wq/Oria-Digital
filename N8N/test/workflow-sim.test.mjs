// Simulação do workflow gerado: executa os códigos REAIS dos nós Code de
// workflow.e1-ingestao.json com dados mock, reproduzindo como o N8N passa
// dados entre nós (incluindo: Postgres não repassa binário; HTTP Request
// substitui o item pela resposta; $('Node').item volta o contexto; binário
// só é lido via this.helpers.getBinaryDataBuffer, nunca direto do campo .data).
//
// Se este teste passa, os nós Code estão coerentes entre si de ponta a ponta.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { codigosConhecidos } from '../lib/ia.mjs';
import { SYSTEM_PROMPT, diagnosticarErroApi, MAX_OUTPUT_TOKENS, TPM_CONTA, RPM_CONTA, PISO_BATCHING_MS, normalizarUnidade, extractionSchema, achatarGrupos } from '../lib/extract.mjs';
import { ALIASES } from '../lib/taxonomia.mjs';
import { parseEntidade, classifyByFilename } from '../lib/classifier.mjs';
import { orcamentoDoLote, vereditoDeTamanhoPorArquivo, TETO_BYTES_POR_ARQUIVO, MODELO_CLASSIFICACAO, MODELO_EXTRACAO, VERSAO_ORCAMENTO, PRECO_USD_POR_MILHAO, CUSTO_ESTIMADO_DOC_USD, TETO_EXECUCAO_USD, PAGINAS_MAX_MEDIDO, TOKENS_POR_PAGINA_IMAGEM } from '../lib/custo.mjs';

// O PIOR CASO DE ENTRADA (tokens de imagem), a MESMA conta que
// `build-workflow.mjs` usa para dimensionar a cadência (`ENTRADA_MAX_MEDIDA_TOKENS`).
// Os dois testes de cadência abaixo mediam a reserva de TPM só pela SAÍDA
// (`MAX_OUTPUT_TOKENS`) — o MESMO defeito que uma revisão adversarial achou no
// gerador em 11/09/2026 ("a reserva cobre a chamada inteira" era falso: a
// OpenAI reserva o MAIOR entre `max_tokens` e o tamanho REAL do request, e a
// entrada nunca entrava na conta). Sem esta correção, os dois testes ficavam
// VERDES sobre uma cadência que deixava um PDF de 20 páginas estourar o balde
// sozinho — o mesmo "estágio desligado parece limpo" que a suíte existe para
// não deixar passar.
const RESERVA_ENTRADA_TOKENS_TESTE = PAGINAS_MAX_MEDIDO * TOKENS_POR_PAGINA_IMAGEM;
import { provedor, schemaDoProvedor, capacidadesDoModelo } from '../lib/provedor.mjs';

// ---------------------------------------------------------------------------
// O DIALETO DO PROVEDOR ATIVO — os acessos que este arquivo fazia à mão
// ---------------------------------------------------------------------------
//
// Estas asserções liam `body.messages[1].content` e `resp.choices[0].message`
// direto, ou seja: elas testavam o workflow E o dialeto da OpenAI ao mesmo
// tempo, sem distinguir os dois. Com o provedor virando escolha, o que este
// arquivo tem de provar é o WORKFLOW — que o conteúdo do arquivo chega à
// chamada, que o schema trava o enum, que a resposta vira campo no banco —, e
// isso não muda com o dialeto.
//
// Os acessadores abaixo são a fronteira. Trocar `IA_PROVEDOR` e rodar a suíte
// de novo exercita os mesmos ~90 testes contra o outro dialeto, o que é
// exatamente a garantia que se quer ao manter dois provedores vivos.
const PROV = provedor();
const GEMINI = PROV.dialeto === 'gemini';

/** As partes da mensagem de USUÁRIO do corpo montado. */
const partesDaReq = (body) => (GEMINI
  ? body.contents[body.contents.length - 1].parts
  : body.messages[body.messages.length - 1].content);

/** O prompt de SISTEMA — em campo próprio nos dois dialetos (condição do cache). */
const sistemaDaReq = (body) => (GEMINI ? body.systemInstruction.parts[0].text : body.messages[0].content);

/** O schema que prende a saída. */
const schemaDaReq = (body) => (GEMINI
  ? body.generationConfig.responseSchema
  : body.response_format.json_schema.schema);

/** O teto de tokens de saída. */
// O nome do campo de teto é do MODELO (a família GPT-5 recusa `max_tokens` e
// exige `max_completion_tokens`), então lê-se pela capacidade declarada — a
// mesma fonte que `montarCorpoIA` usa para escrever. Travar o nome fixo aqui
// seria travar o mecanismo, e mecanismo travado protege o bug (regra 3).
const tetoDaReq = (body) => (GEMINI
  ? body.generationConfig.maxOutputTokens
  : body[capacidadesDoModelo(body.model).tetoDeSaida]);

/** Esta parte carrega o ARQUIVO (e não texto)? */
const ehParteDeArquivo = (parte) => (GEMINI
  ? !!(parte && parte.inlineData)
  : !!(parte && (parte.type === 'file' || parte.type === 'image_url')));

/**
 * Um corpo de chamada FALSO, no dialeto ativo, para os testes do `Fatiar
 * Extracao` — que trabalha em cima de um corpo já montado e não precisa que ele
 * seja de verdade. Escrito à mão em `messages` como estava, ele testava o
 * fatiamento no dialeto errado e passava por acidente (o nó não achava
 * `contents`, não acrescentava instrução nenhuma, e o assert de "sem instrução"
 * do documento pequeno passava por omissão).
 */
function corpoFalso({ sistema, texto }) {
  return GEMINI
    ? {
      systemInstruction: { parts: [{ text: sistema }] },
      contents: [{ role: 'user', parts: [{ text: texto }, { inlineData: { mimeType: 'application/pdf', data: 'QUJD' } }] }],
      generationConfig: { temperature: 0 },
    }
    : {
      model: 'modelo-de-teste',
      messages: [
        { role: 'system', content: sistema },
        { role: 'user', content: [{ type: 'text', text: texto }, { type: 'file' }] },
      ],
    };
}

/** Os bytes (base64) que uma parte de arquivo carrega. */
const base64DaParte = (parte) => {
  if (!parte) return null;
  if (parte.inlineData) return parte.inlineData.data;
  if (parte.file) return String(parte.file.file_data).split('base64,')[1];
  if (parte.image_url) return String(parte.image_url.url).split('base64,')[1];
  return null;
};

/** O texto da primeira parte da mensagem de usuário. */
const textoDaReq = (body) => partesDaReq(body)[0].text;

/**
 * A resposta da IA como o provedor ativo a devolveria.
 *
 * `conteudo` é string (o JSON que o modelo escreveu — pode vir cortado de
 * propósito, para simular truncamento). `cortada` marca o corte por teto de
 * tokens, que é o mesmo fato com dois nomes: `finish_reason:'length'` na
 * OpenAI, `finishReason:'MAX_TOKENS'` no Google.
 */
function respostaIA(conteudo, { cortada = false, uso = null } = {}) {
  const texto = typeof conteudo === 'string' ? conteudo : JSON.stringify(conteudo);
  if (GEMINI) {
    const r = {
      candidates: [{ content: { parts: [{ text: texto }] }, finishReason: cortada ? 'MAX_TOKENS' : 'STOP' }],
    };
    if (uso) {
      r.usageMetadata = {
        promptTokenCount: uso.prompt_tokens,
        candidatesTokenCount: uso.completion_tokens,
        cachedContentTokenCount: uso.prompt_tokens_details ? uso.prompt_tokens_details.cached_tokens : 0,
      };
    }
    return r;
  }
  const r = { choices: [{ message: { content: texto }, finish_reason: cortada ? 'length' : 'stop' }] };
  if (uso) r.usage = uso;
  return r;
}

const wf = JSON.parse(readFileSync(new URL('../workflow.e1-ingestao.json', import.meta.url)));
const byName = Object.fromEntries(wf.nodes.map((n) => [n.name, n]));
const code = (name) => byName[name].parameters.jsCode;
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;

// Executa um jsCode como o N8N: $input, $ (referência a nós), $env, $json,
// $itemIndex e this.helpers (binário — NÃO o global $helpers: no runtime de
// Task Runner do N8N (padrão em instalações self-hosted recentes), $helpers
// não existe; o jeito certo é this.helpers.getBinaryDataBuffer, confirmado
// testando ao vivo e na doc oficial do n8n). O código real usa `await`,
// então o mock roda como função async, com `this` vinculado via .call().
//
// getBinaryDataBuffer resolve o buffer pelo `itemIndex` DENTRO DO LOTE
// inteiro do node — não pelo `item` específico passado nesta chamada de
// `run()`. Por isso o mock busca em `binaryStore` (o lote completo, quando
// fornecido) usando o itemIndex recebido pelo CÓDIGO (não um valor fixo do
// teste) — é o que teria pego o bug real (2026-07-22): getBinaryDataBuffer(0,
// ...) sempre lia o item 0 do lote, mesmo processando o item 1. Sem
// binaryStore, cai pro item único (`item`) — comportamento de antes, para
// nodes que não dependem de itemIndex.
// `semCrypto` reproduz o sandbox do n8n do dono, MEDIDO em 2026-07-31: o Code
// node não expõe o global `crypto`, e por isso o campo `hash` de
// `Preparar Conteudo` vinha null em produção enquanto passava verde aqui — o
// Node local expõe `crypto.subtle`, então o teste exercitava um caminho que a
// produção nunca toma. Passar `crypto` como PARÂMETRO (valor `undefined`)
// sombreia o global dentro do corpo do nó, que é exatamente o que o sandbox faz.
async function run(name, { item, items, refs = {}, env = {}, itemIndex = 0, binaryStore, semCrypto = false } = {}) {
  const $input = {
    item,
    first: () => (items ? items[0] : item),
    all: () => items || (item ? [item] : []),
  };
  const $ = (ref) => {
    if (!(ref in refs)) throw new Error(`Referência não mockada no teste: $('${ref}') — o node "${name}" depende dela`);
    // `.all()` existe porque um nó pode olhar TODOS os itens que passaram por
    // outro nó — é assim que o `Resumo de Custo` soma o lote. Mock em array
    // significa "vários itens"; mock em objeto continua sendo um item só.
    const v = refs[ref];
    // `{ naoExecutado: true }` simula um nó que AINDA NÃO RODOU: `isExecuted` é false
    // e ler os itens lança, como no n8n.
    if (v && v.naoExecutado) {
      return { isExecuted: false, first: () => { throw new Error('nó não executado'); },
        all: () => { throw new Error('nó não executado'); }, item: undefined };
    }
    // `{ runs: [[...], [...]] }` simula um nó que EXECUTOU MAIS DE UMA VEZ — o que
    // acontece com toda a cadeia depois do IF `Precisa Fallback?`, porque o n8n
    // roda o grafo uma vez por ramo. `.all(branch, run)` estoura quando a
    // execução não existe, e é assim que o código sabe onde parar.
    if (v && !Array.isArray(v) && Array.isArray(v.runs)) {
      return {
        isExecuted: true,
        first: () => v.runs[0][0],
        item: v.runs[0][itemIndex],
        all: (_b, run = 0) => {
          if (run >= v.runs.length) throw new Error(`execução ${run} não existe`);
          return v.runs[run];
        },
      };
    }
    const lista = Array.isArray(v) ? v : [v];
    return {
      isExecuted: true,
      first: () => lista[0],
      item: Array.isArray(v) ? lista[itemIndex] : v,
      all: (_b, run = 0) => { if (run > 0) throw new Error(`execução ${run} não existe`); return lista; },
      // `itemMatching(i)`: o item de ENTRADA no nó referenciado que produziu o
      // item de índice `i` na entrada do nó ATUAL — a API do n8n para reatar
      // contexto depois de um nó que muda a quantidade de itens (1 documento
      // → N linhas de planilha). Aqui, mockado por índice direto na lista: o
      // teste decide o mapeamento passando a lista já na ORDEM esperada.
      itemMatching: (i) => (Array.isArray(v) ? lista[i] : v),
    };
  };
  const $json = item ? item.json : undefined;
  const thisContext = {
    helpers: {
      getBinaryDataBuffer: async (idx, propertyName) => {
        const lote = binaryStore || (item ? [item] : []);
        const fonte = lote[idx];
        const bin = (fonte && fonte.binary && fonte.binary[propertyName]) || {};
        return Buffer.from(bin.data || '', 'base64');
      },
    },
  };
  const nomes = ['$input', '$', '$env', '$json', '$itemIndex', 'Buffer'];
  const valores = [$input, $, env, $json, itemIndex, Buffer];
  if (semCrypto) {
    nomes.push('crypto');
    valores.push(undefined);
  }
  const fn = new AsyncFunction(...nomes, code(name));
  return fn.call(thisContext, ...valores);
}

// ---------------------------------------------------------------------------
// Dados mock: o Form entrega binários; o Postgres do Upsert só entrega caso_id.
// Nome com espaço+acento de propósito (caso real: "BALANÇO ACUMULADO 2025.pdf").
// ---------------------------------------------------------------------------
// OS BYTES DESTAS FIXTURES SÃO DE UM PDF DE VERDADE, e a troca tem data e causa.
// Até 12/09/2026 eram a base64 de "ABC" e "DEF" DECLARADAS como
// `application/pdf`. Elas passaram a reprovar quando `Preparar Conteudo` começou
// a decidir o formato pelos BYTES (`lib/formato.mjs`) em vez de acreditar no
// mimetype do upload — e reprovaram CERTO: "ABC" não é um PDF, e o detector novo
// diz exatamente isso. Quem descrevia um arquivo impossível era a fixture.
//
// É a regra 4 do CLAUDE.md no caso menos óbvio dela: a fixture inventada aqui não
// estava provando um bug inexistente, estava ESCONDENDO que a decisão de formato
// nunca tinha sido exercitada contra bytes reais. Um PDF começa com `%PDF-`
// (ISO 32000 §7.5.2); o marcador ABC/DEF continua no corpo, que é o que os
// asserts de "cada item lê o SEU PRÓPRIO binário" precisam distinguir.
// As fixtures das linhas ~2616/2649 já usavam `%PDF-1.4` — estas ficaram para trás.
const PDF_A = Buffer.from('%PDF-1.7\nABC').toString('base64');
const PDF_B = Buffer.from('%PDF-1.7\nDEF').toString('base64');

const FORM_ITEM = {
  json: { 'Mandato (nome do caso)': 'Mandato Teste' },
  binary: {
    Arquivos_0: { fileName: 'BALANÇO ACUMULADO 2025.pdf', mimeType: 'application/pdf', data: PDF_A },
    Arquivos_1: { fileName: '12M25 DRE (Assinado).pdf', mimeType: 'application/pdf', data: PDF_B },
  },
};
const UPSERT_ITEM = { json: { caso_id: 'caso-uuid-1' } }; // sem binário (Postgres não repassa)
const REFS_BASE = { 'Intake (Form)': FORM_ITEM, 'Upsert Caso (Postgres)': UPSERT_ITEM };

test('Listar Arquivos: fan-out lê binário do FORM (não do Postgres) e normaliza a chave', async () => {
  const out = await run('Listar Arquivos', { item: UPSERT_ITEM, items: [UPSERT_ITEM], refs: REFS_BASE });
  assert.ok(Array.isArray(out), 'all-items deve retornar array');
  assert.equal(out.length, 2);
  for (const it of out) {
    assert.equal(it.json.caso_id, 'caso-uuid-1');
    assert.equal(it.json.binary_key, 'data');
    assert.ok(it.binary.data, 'binário deve estar sob a chave normalizada "data"');
  }
  assert.equal(out[0].json.nome_original, 'BALANÇO ACUMULADO 2025.pdf');
});

test('Listar Arquivos: sem arquivos → erro explícito (não saída vazia silenciosa)', async () => {
  const semArquivos = { ...UPSERT_ITEM };
  await assert.rejects(
    () => run('Listar Arquivos', {
      item: semArquivos, items: [semArquivos],
      refs: { ...REFS_BASE, 'Intake (Form)': { json: {}, binary: {} } },
    }),
    /Nenhum arquivo recebido/
  );
});

// Encadeia os dois arquivos pela cadeia principal e guarda os intermediários.
// `lote` guarda os DOIS itens fan-out (mesmo processando só um pelo resto da
// cadeia) — é o que permite `Preparar Conteudo` simular getBinaryDataBuffer
// resolvendo pelo itemIndex dentro do lote inteiro, não só pelo item único.
async function chainFile(idx) {
  const lote = await run('Listar Arquivos', { item: UPSERT_ITEM, items: [UPSERT_ITEM], refs: REFS_BASE });
  const listado = lote[idx];
  const classificado = await run('Classificar Nome', { item: listado, refs: REFS_BASE, itemIndex: idx, binaryStore: lote });
  const preparado = await run('Preparar Conteudo', { item: classificado, refs: REFS_BASE, itemIndex: idx, binaryStore: lote });
  return { listado, classificado, preparado };
}

// Emula `Registrar Documento` (Postgres, que SUBSTITUI o item) + `Recompor Contexto`
// (que devolve o contexto por ÍNDICE contra a saída do `Juntar Ramos`). Passa pelo
// nó de recomposição DE VERDADE: é ele que reencontra o `content_part` sem
// pareamento, e testar a cadeia sem ele deixaria de fora justamente o passo que o
// Teste V45 provou faltar.
async function recomporPara(preparado, documento_id, documento_versao_id) {
  const registrado = { json: { r: { documento_id, documento_versao_id } } };
  const out = await run('Recompor Contexto', {
    items: [registrado], refs: { 'Juntar Ramos': preparado },
  });
  return out[0];
}

test('Classificar Nome: objeto único, classifica o caso real e PRESERVA o binário', async () => {
  const { classificado } = await chainFile(0); // BALANÇO ACUMULADO 2025.pdf
  assert.ok(!Array.isArray(classificado), 'each-item deve retornar objeto único');
  assert.equal(classificado.json.tipo_taxonomia, 'BALANCO');
  assert.equal(classificado.json.precisa_fallback_ia, true, 'sem período no nome → confiança 0.6 → fallback');
  assert.ok(classificado.binary?.data, 'binário preservado para os nós seguintes');

  const { classificado: dre } = await chainFile(1); // 12M25 DRE (Assinado).pdf
  assert.equal(dre.json.tipo_taxonomia, 'DRE');
  assert.equal(dre.json.periodo_ref, '12M25');
  assert.equal(dre.json.assinado, true);
  assert.equal(dre.json.precisa_fallback_ia, false, 'nome completo → alta confiança → direto');
});

test('Classificar Nome: o limiar do fallback vem do DIAL, e o nó obedece', async () => {
  // O `Upsert Caso` passou a devolver `limiar_auto_clear` do estágio
  // `classificacao_doc_checklist` na MESMA consulta que cria o caso, e o
  // `Listar Arquivos` carrega o número em cada item. Este teste roda os NÓS DE
  // VERDADE — é o que separa "a lib obedece ao dial" de "o WORKFLOW obedece ao
  // dial", e é a segunda metade que roda em produção.
  //
  // Sem ele, o espelho inline poderia voltar ao 0.7 fixo com a lib corrigida e a
  // suíte continuaria verde: o `espelho-inline` não consegue extrair a
  // classificação inline (são statements soltos, não uma função nomeada), então
  // esta é a ÚNICA guarda que liga as duas pontas aqui.
  //
  // A DIREÇÃO DEMONSTRADA AQUI é a do dial FROUXO, porque os dois arquivos
  // simulados caem em 0,65 e 1,0 e não há confiança intermediária para apertar
  // contra. A direção apertada — a que importa, porque é a que manda a IA ler —
  // está trancada no `classifier.test.mjs` (dial 0,85 e 0,95 sobre 0,75 e 0,9).
  const comDial = (limiar) => ({ json: { caso_id: 'caso-uuid-1', limiar_classificacao: limiar } });
  const classificarCom = async (upsert, idx) => {
    const refs = { ...REFS_BASE, 'Upsert Caso (Postgres)': upsert };
    const lote = await run('Listar Arquivos', { item: upsert, items: [upsert], refs });
    return run('Classificar Nome', { item: lote[idx], refs, itemIndex: idx, binaryStore: lote });
  };

  // BALANÇO ACUMULADO 2025 → confiança 0,65 (tipo 0,6 + ano isolado, sinal fraco).
  // Na queda de 0,70 ela NÃO basta, e a IA é chamada.
  const semDial = await classificarCom(comDial(null), 0);
  assert.equal(semDial.json.confianca, 0.65);
  assert.equal(semDial.json.limiar_aplicado, 0.7, 'banco sem a linha do dial cai na queda 0,70');
  assert.equal(semDial.json.precisa_fallback_ia, true);

  // MESMO ARQUIVO, dial afrouxado para 0,60: a mesma confiança passa a bastar e
  // a chamada de IA deixa de acontecer. É o dial mandando, medido no nó.
  const frouxo = await classificarCom(comDial(0.60), 0);
  assert.equal(frouxo.json.confianca, 0.65, 'a confiança não muda — quem muda é o limiar');
  assert.equal(frouxo.json.limiar_aplicado, 0.6, 'o nó DECLARA contra o que decidiu');
  assert.equal(frouxo.json.precisa_fallback_ia, false, 'dial 0,60 < confiança 0,65 → dispensa a IA');

  // Limiar inválido nunca vira zero: zero faria CADA documento passar sem a IA
  // ler nenhum, que é a falha silenciosa mais cara possível aqui.
  const zerado = await classificarCom(comDial(0), 0);
  assert.equal(zerado.json.limiar_aplicado, 0.7, 'limiar 0 é inválido e cai na queda');
  assert.equal(zerado.json.precisa_fallback_ia, true);
});

test('Preparar Conteudo: lê o binário via $helpers.getBinaryDataBuffer (não do campo .data direto)', async () => {
  // Bug real (2026-07-20): ler binary.data.data direto funciona só por acaso
  // no modo de binário em memória do N8N; no modo filesystem/S3 esse campo
  // vira uma referência interna (ex.: "filesystem-v2"), não a base64 — e a
  // OpenAI acaba recebendo um PDF inválido sem nenhum erro (achado quando a
  // IA só "leu" o nome do arquivo, porque o conteúdo enviado era lixo).
  const { preparado } = await chainFile(0);
  assert.ok(!Array.isArray(preparado));
  assert.ok(ehParteDeArquivo(preparado.json.content_part), 'o PDF vai como ARQUIVO, não como texto');
  assert.ok(JSON.stringify(preparado.json.content_part).includes(PDF_A), 'e os bytes do arquivo vão junto');
  assert.equal(preparado.json.caso_id, 'caso-uuid-1', 'contexto (caso_id) atravessa a cadeia');
  assert.ok(preparado.binary?.data, 'binário preservado (Upload é ramo a partir daqui)');
});

test('Preparar Conteudo: com 2+ arquivos no MESMO lote, cada item lê o SEU PRÓPRIO binário', async () => {
  // Bug real (2026-07-22, achado testando com 2 documentos reais no mesmo
  // upload): getBinaryDataBuffer(0, 'data') fixo lia sempre o binário do
  // ITEM 0 do lote, mesmo processando o item 1 — o nome/mimeType do item 1
  // batiam (vêm do JSON, correto), mas os BYTES enviados pra IA eram os do
  // item 0. Com upload de 1 arquivo por vez isso nunca aparecia (o único
  // item É o item 0). Resultado real: um documento foi extraído com o
  // CONTEÚDO de outro (diagnóstico/entidade/valores de um arquivo diferente
  // do que o nome dizia). Fix: usar $itemIndex em vez do literal 0.
  const { preparado: item0 } = await chainFile(0); // BALANÇO ACUMULADO 2025.pdf
  const { preparado: item1 } = await chainFile(1); // 12M25 DRE (Assinado).pdf
  assert.equal(base64DaParte(item0.json.content_part), PDF_A, 'item 0 deve ler o PRÓPRIO binário');
  assert.equal(base64DaParte(item1.json.content_part), PDF_B, 'item 1 deve ler o PRÓPRIO binário, não o do item 0');
  assert.notEqual(base64DaParte(item0.json.content_part), base64DaParte(item1.json.content_part));
});

// O ORIGINAL TEM DE FICAR GUARDADO, E `arquivo_ref` TEM DE APONTAR PARA ELE.
//
// Medido em producao em 07/10/2026 (requisicao identica a do `Upload Storage`): o
// Storage devolve 400 InvalidKey para chave com acento — `sonda teste ç.pdf` — mesmo
// com encodeURIComponent, e 200 para `sonda teste.pdf`. Nomes reais tem "BALANÇO".
// Este teste afirma o COMPORTAMENTO: dado um nome com acento, (1) a chave que vai
// na URL do upload e' so' ASCII imprimivel e sem caractere que o Storage recusa, e
// (2) e' IDENTICA ao arquivo_ref que o Registrar Documento grava. Duas contas para a
// mesma chave divergem sem erro nenhum — arquivo_ref apontando para objeto
// inexistente era o estado de producao (bucket com zero objetos).
const avaliarExpr = (expr, json) =>
  new Function('$json', 'return (' + expr.replace(/^=\{\{/, '').replace(/\}\}$/, '') + ')')(json);

const avaliarTemplate = (tpl, json) =>
  tpl.slice(1).replace(/\{\{\s*(.*?)\s*\}\}/g, (_, e) => avaliarExpr('={{' + e + '}}', json));

test('Upload Storage: nome com acento vira chave ASCII, e a URL e o arquivo_ref coincidem', async () => {
  const conteudo = Buffer.from('%PDF-1.4 balanco com acento');
  const nomes = ['BALANÇO PATRIMONIAL 2025 (versão final).PDF', 'DRE — 12M25.pdf', 'sem extensao'];
  for (const nome of nomes) {
    const item = {
      json: { caso_id: 'c0a80101-0000-4000-8000-000000000001', nome_original: nome },
      binary: { data: { fileName: nome, mimeType: 'application/pdf', data: conteudo.toString('base64') } },
    };
    const prep = await run('Preparar Conteudo', { item });
    const url = avaliarTemplate(byName['Upload Storage'].parameters.url, prep.json);
    const chave = url.split('/object/documentos/')[1];
    assert.ok(chave, `a URL do upload tem o bucket e a chave: ${url}`);
    assert.match(chave, /^[A-Za-z0-9._\/-]+$/, `chave só ASCII seguro (o Storage recusa o resto): ${chave}`);
    const params = avaliarExpr(
      wf.nodes.find((n) => n.name === 'Registrar Documento').parameters.options.queryReplacement, prep.json);
    assert.equal(params[8], chave, 'o arquivo_ref gravado é a MESMA chave do objeto enviado');
    assert.equal(params[9], nome, 'o nome original continua inteiro, com acento, na coluna própria');
    // identidade da 0026: mesma chave para o mesmo conteúdo, qualquer que seja o nome
    assert.ok(chave.includes(prep.json.hash), 'a chave carrega o hash do conteúdo');
  }
  // Mesmo nome, conteúdo DIFERENTE => chave diferente: com chave por nome o x-upsert
  // sobrescreveria o original anterior (perda de dado).
  const mk = (txt) => ({
    json: { caso_id: 'c0a80101-0000-4000-8000-000000000001', nome_original: 'BALANÇO.pdf' },
    binary: { data: { fileName: 'BALANÇO.pdf', mimeType: 'application/pdf', data: Buffer.from(txt).toString('base64') } },
  });
  const a = await run('Preparar Conteudo', { item: mk('%PDF-1.4 um') });
  const b = await run('Preparar Conteudo', { item: mk('%PDF-1.4 outro') });
  assert.notEqual(a.json.arquivo_ref, b.json.arquivo_ref, 'arquivos diferentes de mesmo nome não podem dividir a chave');
});

test('Upload Storage: ligado, com credencial httpCustomAuth e sem service_role em texto', () => {
  const n = byName['Upload Storage'];
  assert.equal(n.disabled, undefined, 'religado em 07/10/2026 (o bug do binário não reproduziu — ver o gerador)');
  assert.equal(n.parameters.inputDataFieldName, 'data');
  assert.equal(n.parameters.genericAuthType, 'httpCustomAuth');
  assert.equal(n.credentials.httpCustomAuth.name, 'Supabase Storage (service_role)');
  assert.equal(n.credentials.httpCustomAuth.id, 'REPLACE', 'o id real da instalação não entra no repositório');
  const headers = n.parameters.headerParameters.parameters;
  assert.ok(!JSON.stringify(n).includes('COLE_A_SERVICE_ROLE_KEY_AQUI'), 'segredo/placeholder em texto no nó');
  assert.ok(headers.some((h) => h.name === 'x-upsert'));
  // O ramo lateral NÃO PODE derrubar a ingestão: sem onError o 4xx do Storage lançaria
  // e a execução morreria antes de classificar (regra do c).
  assert.equal(n.onError, 'continueRegularOutput');
});

test('Resumo de Custo: o upload que falhou NÃO passa por lote em que tudo foi guardado', async () => {
  // O sinal positivo do ramo lateral (regra 7): sem ele, falha de upload e sucesso
  // têm a mesma aparência, porque o nó nunca lança.
  const prep = (r) => ({ json: { caso_id: 'c', arquivo_ref: r } });
  const refs = (upload) => ({
    'Orcamento do Lote': { json: { orcamento_estimado_usd: 0.1, orcamento_versao: 'v' } },
    'Juntar Blocos': [{ json: { custo_usd: 0.01, campos: [] } }],
    'Parse Classif': [],
    'Preparar Conteudo': [prep('c/h1.pdf'), prep('c/h2.pdf')],
    'Upload Storage': upload,
  });
  const rodar = (upload) => run('Resumo de Custo', { items: [{ json: {} }], refs: refs(upload) });

  const tudoBem = await rodar([{ json: { Key: 'documentos/c/h1.pdf' } }, { json: { Key: 'documentos/c/h2.pdf' } }]);
  assert.equal(tudoBem[0].json.originais_guardados, 2);
  assert.equal(tudoBem[0].json.originais_sem_guarda, 0);

  const comFalha = await rodar([{ json: { Key: 'documentos/c/h1.pdf' } }, { json: { error: { message: 'InvalidKey' } } }]);
  assert.equal(comFalha[0].json.originais_guardados, 1);
  assert.equal(comFalha[0].json.originais_sem_guarda, 1);
  assert.equal(comFalha[0].json.originais_primeiro_erro, 'InvalidKey');
  assert.match(comFalha[0].json.resumo, /1 SEM GUARDA.*InvalidKey/);

  // O ITEM DE ENTRADA REPASSADO INTACTO (nó inteiro falhou, p.ex. credencial apagada):
  // sem `error`, com caso_id/arquivo_ref. NÃO é guardado.
  const repassado = await rodar([{ json: { caso_id: 'c', arquivo_ref: 'c/h1.pdf', nome_original: 'a.pdf' } }]);
  assert.equal(repassado[0].json.originais_guardados, 0, 'item de entrada repassado não é original guardado');
  assert.equal(repassado[0].json.originais_sem_guarda, 1);
  // Key de outro objeto também não prova o NOSSO original.
  const keyAlheia = await rodar([{ json: { Key: 'documentos/outro/x.pdf' } }]);
  assert.equal(keyAlheia[0].json.originais_sem_guarda, 1);

  // AINDA NÃO RODOU (executionOrder v1 não garante a ordem dos ramos): null e texto
  // honesto — nunca "0 guardados" nem "nenhum guardado".
  const antes = await rodar({ naoExecutado: true });
  assert.equal(antes[0].json.originais_upload_executou, false);
  assert.equal(antes[0].json.originais_guardados, null);
  assert.equal(antes[0].json.originais_sem_guarda, null);
  assert.match(antes[0].json.resumo, /ainda nao tinha rodado.*bucket/);
  assert.doesNotMatch(antes[0].json.resumo, /NENHUM|SEM GUARDA|0 de/);
  assert.equal(tudoBem[0].json.originais_upload_executou, true);
});

test('Ramo fallback: Montar Req → (HTTP substitui item) → Parse recompõe pelo contexto', async () => {
  const { preparado } = await chainFile(0);
  const req = await run('Montar Req Classif', { item: preparado, refs: REFS_BASE, env: {} });
  // O modelo vem da FONTE (`lib/custo.mjs`), não de um literal repetido aqui: um
  // teste que espelha o valor à mão passa a reprovar a mudança em vez de conferir
  // a ligação, e foi o que aconteceu quando a classificação virou `gpt-4o-mini`.
  // O que este assert trava de verdade é que o nó usa o modelo de CLASSIFICAÇÃO,
  // não o de extração — trocar os dois é o erro caro, e ele é invisível a olho.
  // O MODELO vai no CORPO na OpenAI e na URL no Google — o que este assert trava
  // é o mesmo dos dois lados: que este nó usa o modelo de CLASSIFICAÇÃO e não o
  // de extração. Trocar os dois é o erro caro, e ele é invisível a olho.
  assert.notEqual(MODELO_CLASSIFICACAO, undefined);
  if (GEMINI) {
    assert.equal(req.json.ia_body.model, undefined, 'no Google o modelo vai na URL do nó, não no corpo');
    assert.match(byName['IA Classificar'].parameters.url, new RegExp(`models/${MODELO_CLASSIFICACAO}:`));
  } else {
    assert.equal(req.json.ia_body.model, MODELO_CLASSIFICACAO);
  }
  assert.ok(partesDaReq(req.json.ia_body).some(ehParteDeArquivo), 'conteúdo do arquivo vai na chamada');

  // O N8N substitui o item pela resposta da OpenAI:
  const respostaOpenAI = { json: respostaIA(JSON.stringify({
    tipo_taxonomia: 'BALANCO', entidade: 'Empresa X Ltda', periodo_tipo: 'anual',
    periodo_referencia: '12M25', assinado: true, confianca: 0.91, justificativa: 'cabeçalho',
  })) };
  const parsed = await run('Parse Classif', { item: respostaOpenAI, refs: { 'Montar Req Classif': req } });
  assert.ok(!Array.isArray(parsed));
  assert.equal(parsed.json.tipo_taxonomia, 'BALANCO');
  assert.equal(parsed.json.entidade, 'Empresa X Ltda');
  assert.equal(parsed.json.confianca, 0.91);
  assert.equal(parsed.json.caso_id, 'caso-uuid-1', 'contexto recomposto');
  assert.equal(parsed.json.ia_body, undefined, 'o corpo da chamada de classificação sai');
  // O `content_part` FICA, e a mudança é deliberada: era o descarte dele aqui que
  // obrigava o `Montar Req Extracao` a reencontrar o PDF por pareamento, através
  // da convergência dos dois ramos — o caminho que perdeu 19 dos 35 documentos no
  // Teste V45. O peso volta a sair no `Fatiar Extracao`, depois de o base64 já ter
  // sido copiado para dentro do corpo da chamada de extração.
  assert.ok(parsed.json.content_part, 'o conteúdo continua no item, para a extração não precisar parear');
});

test('Montar Req Classif: schema da OpenAI TRAVA tipo_taxonomia/periodo_tipo num enum (caso real: virou "BAL" sem isso)', async () => {
  // Bug real (2026-07-20): o mirror manual do schema em build-workflow.mjs
  // não tinha `enum`, então a OpenAI inventou "BAL" como tipo_taxonomia (não
  // é um código válido) e "12M25" como periodo_tipo (é a REFERENCIA, não o
  // tipo). Sem enum, nada no request impedia isso — Structured Outputs só
  // restringe de fato quando o schema declara o enum explicitamente.
  const { preparado } = await chainFile(0);
  const req = await run('Montar Req Classif', { item: preparado, refs: REFS_BASE, env: {} });
  const schema = schemaDaReq(req.json.ia_body);
  const tipoEnum = schema.properties.tipo_taxonomia.enum;
  const periodoEnum = schema.properties.periodo_tipo.enum;
  assert.ok(Array.isArray(tipoEnum), 'tipo_taxonomia precisa de enum (senão a IA pode inventar código)');
  assert.deepEqual([...tipoEnum].sort(), [...codigosConhecidos()].sort(), 'enum deve ser exatamente os códigos conhecidos + DESCONHECIDO');
  assert.ok(tipoEnum.includes('BALANCO') && !tipoEnum.includes('BAL'), 'código correto é BALANCO, não uma abreviação inventada');
  assert.deepEqual(periodoEnum, ['anual', 'trimestre', 'multi', 'data-base', 'outro', 'desconhecido']);
});

test('Ramo fallback: falha da OpenAI (onError continue) → mantém o que o nome já sabia, sem quebrar', async () => {
  const { preparado } = await chainFile(0); // BALANÇO ACUMULADO 2025.pdf: nome já dava BALANCO @ 0.65
  const req = await run('Montar Req Classif', { item: preparado, refs: REFS_BASE, env: {} });
  const erro = { json: { error: 'timeout' } }; // resposta de erro qualquer (sem content)
  const parsed = await run('Parse Classif', { item: erro, refs: { 'Montar Req Classif': req } });
  // Merge: falha técnica da IA não deve descartar um sinal que o nome já dava.
  assert.equal(parsed.json.tipo_taxonomia, 'BALANCO');
  assert.equal(parsed.json.confianca, 0.65, 'mantém a confiança do nome, não zera por falha técnica da IA');
  assert.equal(parsed.json.fonte, 'nome_arquivo');
  // A justificativa tem de dizer as DUAS coisas: que valeu o nome, e QUAL foi a
  // falha. No "teste v30" os 14 documentos ficaram com uma justificativa genérica
  // ("falha de rede/API") enquanto a causa real era a OpenAI recusando toda
  // chamada — o dono não tinha como ligar uma coisa à outra.
  assert.match(parsed.json.justificativa, /valeu o nome do arquivo/);
  assert.match(parsed.json.justificativa, /timeout/, 'a falha real aparece, não uma frase genérica');
  assert.equal(byName['IA Classificar'].onError, 'continueRegularOutput');
  assert.equal(byName['IA Extrair'].onError, 'continueRegularOutput');
});

test('Parse Classif: 429 da OpenAI nomeia a CAUSA na justificativa do documento', async () => {
  // O sintoma real do v30: o n8n devolve a própria dica ("Try spacing your
  // requests out...") e nada mais. Antes isso virava "falha de rede/API"; agora
  // vira "limite atingido, e não sabemos qual — confira crédito", que é
  // acionável e não afirma cadência sem evidência.
  const { preparado } = await chainFile(0);
  const req = await run('Montar Req Classif', { item: preparado, refs: REFS_BASE, env: {} });
  const erro = { json: { error: { message: "Try spacing your requests out using the batching settings under 'Options'" } } };
  const parsed = await run('Parse Classif', { item: erro, refs: { 'Montar Req Classif': req } });
  assert.match(parsed.json.justificativa, /LIMITE DO PROVEDOR ATINGIDO \(HTTP 429\)/);
  assert.match(parsed.json.justificativa, /crédito/i, 'diz que pode ser crédito — a causa que espaçar NÃO resolve');
  assert.equal(parsed.json.tipo_taxonomia, 'BALANCO', 'e o nome do arquivo continua valendo');
});

test('Ramo E2: Registrar → Montar Req Extracao → Parse → payload de diagnóstico+extração', async () => {
  const { preparado } = await chainFile(1);
  // Saída do Registrar Documento (Postgres): linha {r: {ids}} — e o item de
  // ENTRADA dele (que o Postgres substituiu) volta pelo `Recompor Contexto`, por
  // ÍNDICE contra a saída do `Juntar Ramos`. É esse passo que devolve o
  // `content_part` à cadeia sem depender de pareamento.
  const registrado = { json: { r: { documento_id: 'doc-1', documento_versao_id: 'ver-1' } } };
  const recompostoLista = await run('Recompor Contexto', {
    items: [registrado], refs: { 'Juntar Ramos': preparado },
  });
  const recomposto = recompostoLista[0];
  assert.equal(recomposto.json.documento_versao_id, 'ver-1');
  assert.equal(recomposto.json.recompor_motivo, null, 'contagens batem: sem motivo de falha');
  assert.ok(recomposto.json.content_part, 'o conteúdo voltou para o item');

  const req = await run('Montar Req Extracao', { item: recomposto, env: {} });
  assert.equal(req.json.documento_versao_id, 'ver-1');
  assert.equal(req.json.tipo, 'DRE');
  assert.ok(partesDaReq(req.json.ia_body).some(ehParteDeArquivo));
  assert.equal(extractionSchema().name, 'diagnostico_e_extracao');
  // O schema do nó é o `extractionSchema()` da fonte, serializado — não mais um
  // espelho à mão de 2.400 caracteres. Conferir a IGUALDADE é o que impede a
  // divergência voltar; conferir `pc` dentro de `cols` é o que garante que a
  // coluna de período (Supabase/migrations/0017) continua sendo pedida.
  assert.deepEqual(schemaDaReq(req.json.ia_body), schemaDoProvedor(PROV, extractionSchema()));
  assert.ok(
    schemaDaReq(req.json.ia_body).properties.grupos
      .items.properties.cols.items.required.includes('pc'),
    'schema gerado pede pc/periodo_coluna na coluna (Supabase/migrations/0017)',
  );
  assert.equal(tetoDaReq(req.json.ia_body), 16384, 'teto de tokens de saída explícito (sessão 7 cont.⁷: sem isso, documentos combinados grandes truncavam a resposta silenciosamente)');
  assert.match(textoDaReq(req.json.ia_body), /12M25 DRE \(Assinado\)\.pdf/, 'nome do arquivo vai no prompt (base do diagnóstico de tipo/período)');

  const respostaOpenAI = { json: respostaIA(JSON.stringify({
    moeda: 'BRL', unidade: 'R$ mil',
    diagnostico: {
      entidade: 'Empresa Teste Ltda', tipo_confirma: false, tipo_sugerido: 'BALANCO',
      periodo_tipo: 'anual', periodo_referencia: '12M25',
      legibilidade: 'degradado', nota_legibilidade: 'Última página cortada.',
      resumo: 'Balanço patrimonial de 2025.', justificativa: 'Conteúdo é Balanço, não DRE (dica do nome estava errada).',
    },
    linhas: [
      { s: 'Ativo Circulante', sc: 'ativo_circulante', k: 'Caixa e equivalentes', vt: '10.000', vn: 10000, op: 1, cf: 0.8 },
      { s: 'Passivo Circulante', sc: 'NAO_CLASSIFICAVEL', k: 'Fornecedores', vt: '2.500', vn: 2500, op: 2, cf: 0.7 },
    ],
  })) };
  const parsed = await run('Parse Extracao', { item: respostaOpenAI, refs: { 'Montar Req Extracao': req } });
  assert.equal(parsed.json.documento_versao_id, 'ver-1');
  assert.equal(parsed.json.campos.length, 2);
  assert.equal(parsed.json.campos[0].secao, 'Ativo Circulante');
  assert.equal(parsed.json.campos[0].secao_canonica, 'ativo_circulante', 'secao_canonica mapeada no mirror do Code node');
  assert.equal(parsed.json.campos[1].secao_canonica, null, 'NAO_CLASSIFICAVEL vira null no mirror');
  assert.equal(parsed.json.campos[0].unidade, 'milhar', 'unidade herdada por linha E normalizada na escala canônica pelo Code node real');
  assert.equal(parsed.json.diagnostico.entidade, 'Empresa Teste Ltda');
  assert.equal(parsed.json.diagnostico.tipo_confirma, false);
  assert.equal(parsed.json.diagnostico.tipo_sugerido, 'BALANCO');
  assert.equal(parsed.json.diagnostico.legibilidade, 'degradado');
  assert.equal(parsed.json.falha_motivo, null, 'extração ok não gera motivo de falha');
  assert.ok('periodo_coluna' in parsed.json.campos[0], 'mirror do Code node propaga periodo_coluna (Supabase/migrations/0017)');

  // Registrar Diagnostico lê $('Parse Extracao').item.json.diagnostico.* — a
  // mesma simulação do node real garante que o encadeamento produz os campos
  // que a query Postgres espera (sem rodar Postgres de verdade aqui).
  const diagNode = byName['Registrar Diagnostico'];
  const refsUsadas = [...diagNode.parameters.options.queryReplacement.matchAll(/\$\('Parse Extracao'\)\.item\.json\.diagnostico\.(\w+)/g)].map((m) => m[1]);
  for (const campo of refsUsadas) {
    assert.ok(campo in parsed.json.diagnostico, `Registrar Diagnostico espera diagnostico.${campo}, que Parse Extracao não produz`);
  }
});

test('o CNPJ chega ao banco pelo caminho que roda para TODO documento, não só no fallback', () => {
  // O PORTÃO QUE FALTAVA, e ele nasceu de um defeito real: a primeira fiação do
  // CNPJ leu o campo só na chamada de CLASSIFICAÇÃO, que roda apenas quando
  // `precisa_fallback_ia` é verdadeiro (o nome do arquivo não resolveu
  // tipo+período com confiança ≥ 0,70). MEDIDO no book que este repositório
  // versiona, por `medir-custo-book.mjs`: 19 de 38 documentos do book-canastra
  // passam por ela. Os outros 19 chegariam ao banco com `cnpj` NULO — e sem
  // sintoma nenhum, porque a identidade simplesmente continuaria sendo o nome,
  // na metade do lote, exatamente como antes da 0169.
  //
  // Este teste afirma o COMPORTAMENTO ("o CNPJ chega sempre"), não o mecanismo:
  // ele não exige que seja o `Registrar Diagnostico` a fazê-lo — exige que ALGUM
  // nó que grava CNPJ esteja fora do ramo condicional.
  const porNome = new Map(wf.nodes.map((n) => [n.name, n]));

  // Quem é alcançável APENAS atravessando a saída "true" do `Precisa Fallback?`.
  const soNoFallback = new Set();
  const fila = (wf.connections['Precisa Fallback?']?.main?.[0] ?? []).map((c) => c.node);
  const paraForaDoRamo = new Set(
    (wf.connections['Precisa Fallback?']?.main?.[1] ?? []).map((c) => c.node));
  while (fila.length > 0) {
    const atual = fila.pop();
    if (soNoFallback.has(atual) || paraForaDoRamo.has(atual)) continue;
    soNoFallback.add(atual);
    for (const saida of wf.connections[atual]?.main ?? []) {
      for (const c of saida) if (!paraForaDoRamo.has(c.node)) fila.push(c.node);
    }
  }

  assert.ok(soNoFallback.has('Montar Req Classif'),
    'PRÉ-CONDIÇÃO: a classificação por conteúdo é mesmo condicional — se ela virar incondicional '
    + 'um dia, este teste vira decoração e precisa ser revisto, não apagado');

  // Todo nó Postgres que passa um CNPJ para o banco.
  const gravamCnpj = wf.nodes.filter((n) => n.type === 'n8n-nodes-base.postgres'
    && /cnpj/i.test(JSON.stringify(n.parameters ?? {})));
  assert.ok(gravamCnpj.length > 0, 'nenhum nó Postgres passa CNPJ ao banco');

  const semprerodam = gravamCnpj.filter((n) => !soNoFallback.has(n.name));
  assert.ok(semprerodam.length > 0,
    'TODO nó que grava CNPJ está atrás do ramo de fallback — metade do lote chegaria com cnpj '
    + `null e sem sintoma. Nós que gravam: ${gravamCnpj.map((n) => n.name).join(', ')}`);

  // E o nó do diagnóstico — o único que lê conteúdo de TODO documento — tem de
  // ser um deles, senão o campo existe no schema da IA e morre no caminho.
  const diag = porNome.get('Registrar Diagnostico');
  assert.match(JSON.stringify(diag.parameters.options.queryReplacement), /diagnostico\?\.cnpj/,
    'o Registrar Diagnostico não passa o CNPJ lido do conteúdo — é a única leitura garantida '
    + 'para todo documento, e é por ela que os nomes contaminados nascem');
  assert.match(diag.parameters.query, /p_cnpj=>/,
    'o CNPJ tem de entrar por NOME na query do diagnóstico: o $12 já é dos FATOS, e reordenar os '
    + 'binds para encaixá-lo posicionalmente quebraria fn_registrar_fatos em silêncio');
});

test('Parse Extracao (nó real): resposta AGRUPADA vira uma linha por (conta × coluna)', async () => {
  const req = { json: { documento_versao_id: 'ver-9', tipo: 'BALANCO', ia_body: {} } };
  const resposta = { json: respostaIA(JSON.stringify({
    moeda: 'BRL', unidade: 'R$ mil',
    diagnostico: {
      entidade: 'Vertentes Metalúrgica Ltda.', tipo_confirma: true, tipo_sugerido: 'BALANCO',
      periodo_tipo: 'multi', periodo_referencia: '24,25', legibilidade: 'ok',
      nota_legibilidade: null, resumo: 'BP comparativo.', justificativa: 'Duas colunas de ano.',
    },
    grupos: [
      {
        s: 'Ativo Circulante', sc: 'ativo_circulante', op: 1,
        cols: [{ ec: null, pc: '31/12/2025' }, { ec: null, pc: '31/12/2024' }],
        l: [{ k: 'Caixa e bancos', vt: ['380', '1.240'], vn: [380, 1240], cf: 0.98 }],
      },
      // O subtotal em grupo PRÓPRIO, que é o que a seção canônica por grupo exige.
      {
        s: 'Ativo Circulante', sc: 'NAO_CLASSIFICAVEL', op: 1,
        cols: [{ ec: null, pc: '31/12/2025' }, { ec: null, pc: '31/12/2024' }],
        l: [{ k: 'Total do Ativo Circulante', vt: ['45.440', '67.878'], vn: [45440, 67878], cf: 0.99 }],
      },
    ],
  }), { uso: { prompt_tokens: 12_000, completion_tokens: 3_000 } }) };
  const out = await run('Parse Extracao', { item: resposta, refs: { 'Montar Req Extracao': req } });
  assert.equal(out.json.campos.length, 4);
  assert.deepEqual(out.json.campos.map((c) => [c.chave, c.periodo_coluna, c.valor_num, c.secao_canonica]), [
    ['Caixa e bancos', '31/12/2025', 380, 'ativo_circulante'],
    ['Caixa e bancos', '31/12/2024', 1240, 'ativo_circulante'],
    ['Total do Ativo Circulante', '31/12/2025', 45440, null],
    ['Total do Ativo Circulante', '31/12/2024', 67878, null],
  ]);
  // A escala do documento continua descendo por linha, normalizada.
  assert.ok(out.json.campos.every((c) => c.unidade === 'milhar' && c.moeda === 'BRL'));
  assert.deepEqual(out.json.campos.map((c) => c.ordem), [0, 1, 2, 3]);
  assert.equal(out.json.falha_motivo, null);
});

test('Parse Extracao (nó real): desalinhamento de coluna vira falha_motivo, não linha adivinhada', async () => {
  const req = { json: { documento_versao_id: 'ver-10', tipo: 'BALANCO', ia_body: {} } };
  const resposta = { json: respostaIA(JSON.stringify({
    moeda: 'BRL', unidade: 'unidade',
    diagnostico: {
      entidade: null, tipo_confirma: true, tipo_sugerido: 'BALANCO', periodo_tipo: 'multi',
      periodo_referencia: '24,25', legibilidade: 'ok', nota_legibilidade: null,
      resumo: 'x', justificativa: 'y',
    },
    grupos: [{
      s: 'Ativo Circulante', sc: 'ativo_circulante', op: 1,
      cols: [{ ec: null, pc: '2025' }, { ec: null, pc: '2024' }],
      l: [{ k: 'Caixa', vt: ['380'], vn: [380], cf: 0.9 }],
    }],
  })) };
  const out = await run('Parse Extracao', { item: resposta, refs: { 'Montar Req Extracao': req } });
  assert.equal(out.json.campos.length, 0, 'não grava meia linha nem inventa null');
  assert.match(out.json.falha_motivo, /desalinhamento entre colunas e valores/);
  assert.match(out.json.falha_motivo, /"Caixa"/);
});

test('Diagnóstico com resposta DESCONHECIDO/ilegível vira null (não "DESCONHECIDO" literal na pendência)', async () => {
  const req = { json: { documento_versao_id: 'ver-2', tipo: 'BALANCO', ia_body: {} } };
  const respostaOpenAI = { json: respostaIA(JSON.stringify({
    moeda: null, unidade: null,
    diagnostico: {
      entidade: null, tipo_confirma: false, tipo_sugerido: 'DESCONHECIDO',
      periodo_tipo: 'desconhecido', periodo_referencia: null,
      legibilidade: 'ilegivel', nota_legibilidade: 'Arquivo corrompido.',
      resumo: 'Não foi possível ler.', justificativa: 'Ilegível.',
    },
    linhas: [],
  })) };
  const parsed = await run('Parse Extracao', { item: respostaOpenAI, refs: { 'Montar Req Extracao': req } });
  assert.equal(parsed.json.diagnostico.tipo_sugerido, null);
  assert.equal(parsed.json.diagnostico.legibilidade, 'ilegivel');
});

test('Parse Extracao: resposta truncada (finish_reason=length, JSON incompleto) vira falha_motivo, não 0 campos silencioso', async () => {
  const req = { json: { documento_versao_id: 'ver-3', tipo: 'COMBINADO', ia_body: {} } };
  // JSON deliberadamente cortado no meio (simula o corte real de um output
  // que estourou o teto de tokens antes de fechar o array `linhas`).
  const respostaOpenAI = { json: respostaIA('{"moeda":"BRL","unidade":null,"diagnostico":{"entidade":"Grupo X"', { cortada: true }) };
  const parsed = await run('Parse Extracao', { item: respostaOpenAI, refs: { 'Montar Req Extracao': req } });
  assert.equal(parsed.json.campos.length, 0);
  assert.match(parsed.json.falha_motivo, /truncada por limite de tokens de saida/i);
});

test('Parse Extracao: erro da API OpenAI vira falha_motivo (não silencioso)', async () => {
  const req = { json: { documento_versao_id: 'ver-4', tipo: 'BALANCO', ia_body: {} } };
  const respostaOpenAI = { json: { error: { message: 'Rate limit reached', code: 'rate_limit_exceeded' } } };
  // Estágio TERMINAL: nas tentativas anteriores o 429 de cadência é repetido, e só
  // ao esgotar o teto o motivo vira pendência (ver os testes de repetição).
  const parsed = await run('Parse Extracao (tentativa 4)', { item: respostaOpenAI, refs: { 'Esperar Retry 3': req } });
  assert.equal(parsed.json.campos.length, 0);
  assert.match(parsed.json.falha_motivo, /Rate limit reached/);
});

test('Gravar Campos (Sombra): passa falha_motivo para fn_registrar_campos_extraidos', () => {
  const node = byName['Gravar Campos (Sombra)'];
  assert.match(node.parameters.query, /p_falha_motivo\s*=>\s*\$3::text/);
  assert.match(node.parameters.options.queryReplacement, /\$json\.falha_motivo\s*\|\|\s*null/);
});

test('Nós OpenAI têm batching + retry (evita o 429 de rate limit num upload em lote)', () => {
  // Achado em produção (sessão 7 cont.⁸, "teste v15"): 16 documentos → 16
  // chamadas OpenAI quase simultâneas → 429 em TODAS ("Try spacing your
  // requests out"). Batching espaça no tempo; retry cobre o 429 residual.
  for (const nm of ['IA Classificar', 'IA Extrair']) {
    const n = byName[nm];
    assert.equal(n.parameters.options?.batching?.batch?.batchSize, 1, `${nm}: 1 chamada por vez`);
    assert.ok(n.parameters.options?.batching?.batch?.batchInterval >= 1000, `${nm}: intervalo entre chamadas`);
    assert.equal(n.retryOnFail, true, `${nm}: reexecuta antes de cair no onError`);
    assert.ok(n.maxTries >= 2, `${nm}: mais de uma tentativa`);
  }
});

test('Batching endurecido após "teste v18" (3 de 16 docs ainda deram 429 com 3s/4 tentativas)', () => {
  // Achado em produção (sessão 7 cont.¹¹): os 3 documentos que ainda deram 429
  // com o batching da cont.⁸ (3s, 4 tentativas) eram justamente os
  // consolidados comparativos multi-ano — mais tokens de entrada E saída que
  // os demais. 6s + 6 tentativas dão mais folga pro balde de TPM da conta.
  // O piso de 6s vale para as DUAS chamadas; a extração subiu para 12s depois do
  // v28 (teste próprio abaixo), então aqui a asserção é o PISO, não a igualdade —
  // travar 6000 exato reprovaria justamente o endurecimento seguinte.
  //
  // E o piso continua sendo 6s DEPOIS da troca de provedor: ele não veio da
  // OpenAI, veio do n8n do dono com documento real. O que a troca acrescentou foi
  // um segundo piso — o limite de CHAMADAS por minuto do provedor, quando ele
  // existe —, e o intervalo é o maior dos dois. Nunca menor que 6s.
  for (const nm of ['IA Classificar', 'IA Extrair']) {
    const n = byName[nm];
    assert.ok(n.parameters.options?.batching?.batch?.batchInterval >= 6000, `${nm}: intervalo endurecido`);
    assert.equal(n.maxTries, 6, `${nm}: mais tentativas`);
  }
});

test('Os dois nós OpenAI pedem o CORPO da resposta de erro (`neverError`)', () => {
  // Sem isto, o item que chega ao parse num 429 é só o AxiosError — foi
  // literalmente o que o dono colou depois do v30: `name: AxiosError`,
  // `code: ERR_BAD_REQUEST`, `status: 429`, `message` = a dica genérica que o
  // n8n escreve em cima de QUALQUER 429, e NENHUM corpo da OpenAI em lugar
  // nenhum do item. Sem corpo, `error.code` (o campo que a doc da OpenAI manda
  // inspecionar) não existe, e as causas que pedem ações OPOSTAS — crédito,
  // teto de gasto, cota diária, cadência — ficam indistinguíveis. Com
  // `neverError`, a resposta 429 vem como item normal E COM CORPO, e o
  // diagnóstico deixa de precisar adivinhar.
  for (const nm of ['IA Classificar', 'IA Extrair']) {
    const n = byName[nm];
    assert.equal(n.parameters.options?.response?.response?.neverError, true,
      `${nm}: sem neverError o corpo do erro da OpenAI é descartado antes do parse`);
  }
});

test('A cadência da extração é DERIVADA do TPM, não escolhida a olho', () => {
  // A rodada anterior subiu o intervalo de 6s para 12s por chute e o 429
  // continuou — erro meu, registrado aqui para não repetir. A OpenAI cobra do
  // balde de TPM o MÁXIMO entre `max_tokens` e os tokens ESTIMADOS DO REQUEST
  // (entrada + saída) — não só `max_tokens`. Este teste chegou a assumir só a
  // saída (achado numa revisão adversarial, 11/09/2026: "a reserva cobre a
  // chamada inteira" era falso, e um PDF de 20 páginas somado aos 16.384 de
  // saída passa do teto do Tier 1 sozinho). Isso torna o intervalo mínimo uma
  // conta, não uma opinião: TPM / (entrada + max_tokens) = chamadas por minuto.
  // E DESDE 24/08/2026 SÃO DOIS BALDES, não um. A reserva de tokens é o gargalo
  // da OpenAI; provedor que limita por CHAMADA (o Google, 15/min no patamar de
  // entrada) tem o balde de tokens folgado e o de chamadas apertado. A cadência
  // tem de caber nos DOIS, e é isso que este teste passou a exigir.
  const intervalo = byName['IA Extrair'].parameters.options.batching.batch.batchInterval;
  const chamadasPorMinuto = 60000 / intervalo;
  // A RESERVA É ENTRADA + SAÍDA, não só `MAX_OUTPUT_TOKENS` — ver
  // `RESERVA_ENTRADA_TOKENS_TESTE` no topo do arquivo.
  const tpmReservado = chamadasPorMinuto * (RESERVA_ENTRADA_TOKENS_TESTE + MAX_OUTPUT_TOKENS);
  assert.ok(tpmReservado <= TPM_CONTA + 1,
    `a cadência reserva ${Math.round(tpmReservado)} TPM, acima do teto da conta (${TPM_CONTA}) — o 429 é matemático`);
  if (RPM_CONTA) {
    // Um documento mal nomeado faz DUAS chamadas, em dois nós, no mesmo minuto —
    // e os dois baldes são o mesmo. Contar só a extração é o jeito aritmeticamente
    // garantido de tomar 429 no meio do lote.
    const chamadasDeClassificacao = 60000
      / byName['IA Classificar'].parameters.options.batching.batch.batchInterval;
    assert.ok(chamadasPorMinuto + chamadasDeClassificacao <= RPM_CONTA + 0.001,
      `os dois nós somam ${(chamadasPorMinuto + chamadasDeClassificacao).toFixed(1)} chamadas/min, `
      + `acima do limite do provedor (${RPM_CONTA}/min)`);
  }
  // E não pode ser lenta a ponto de não usar a conta: pelo menos metade do balde
  // QUE MANDA. Qual dos dois manda depende do provedor, e travar o de tokens
  // quando o gargalo é o de chamadas exigiria uma cadência que toma 429.
  const mandaOTpm = !RPM_CONTA
    || (TPM_CONTA / (RESERVA_ENTRADA_TOKENS_TESTE + MAX_OUTPUT_TOKENS)) <= RPM_CONTA / 2;
  if (mandaOTpm) {
    assert.ok(tpmReservado >= TPM_CONTA / 2,
      `${Math.round(tpmReservado)} TPM desperdiça mais da metade do limite disponível (${TPM_CONTA})`);
  } else {
    assert.ok(chamadasPorMinuto >= RPM_CONTA / 4,
      `${chamadasPorMinuto.toFixed(1)} chamadas/min desperdiça o limite de ${RPM_CONTA}/min`);
  }
});

test('Nós Postgres têm onError+retry — um erro num item não derruba o resto do lote em silêncio', () => {
  // Achado em produção (sessão 7 cont.¹³, "teste v19"): 9 arquivos pequenos
  // enviados, só 6 apareceram no dashboard — os outros 3 nunca chegaram a ter
  // uma linha `documento` criada. Sem onError, um erro transitório de conexão
  // num ÚNICO node Postgres (mais provável sob a carga do lote, com o rate
  // limit da OpenAI já no teto) PARA A EXECUÇÃO INTEIRA — todo item ainda na
  // fila some sem nenhum rastro. Com onError:continueRegularOutput +
  // retryOnFail, o pior caso vira "esse item específico fica incompleto"
  // (nunca vira fato, doutrina Arquitetura do Sistema/1 Visão e Doutrina/01), não "o lote inteiro desaparece".
  const nomesPostgres = [
    'Upsert Caso (Postgres)', 'Registrar Documento', 'Recomputar Completude',
    'Gravar Campos (Sombra)', 'Registrar Diagnostico', 'Reconciliar (Classe A)',
  ];
  for (const nm of nomesPostgres) {
    const n = byName[nm];
    assert.equal(n.type, 'n8n-nodes-base.postgres', `${nm}: é um node Postgres de verdade (checagem do teste)`);
    assert.equal(n.onError, 'continueRegularOutput', `${nm}: onError ausente — um erro aqui derruba todo o lote`);
    assert.equal(n.retryOnFail, true, `${nm}: sem retry — erro transitório de conexão não se recupera sozinho`);
    assert.ok(n.maxTries >= 2, `${nm}: mais de uma tentativa`);
  }
});

test('O AGRUPAMENTO corta a saída onde as chaves curtas não chegaram (a metade que faltava)', () => {
  // As chaves curtas (abaixo) encurtaram o NOME do contexto repetido; o formato
  // agrupado para de REPETI-LO. Medido no book de 14 documentos do dono: 64
  // tokens por linha, dos quais ~30 eram contexto idêntico à linha anterior.
  const cols = [{ ec: null, pc: '2025' }, { ec: null, pc: '2024' }];
  const contas = ['Caixa e equivalentes de caixa', 'Duplicatas a receber de clientes',
    '(-) Provisão para créditos de liquidação duvidosa', 'Estoques', 'Tributos a recuperar'];

  // Formato plano: uma entrada por (conta × coluna), cada uma reescrevendo os
  // cinco campos de contexto E o rótulo da conta.
  const plano = contas.flatMap((k) => cols.map((c) => ({
    s: 'Ativo Circulante', sc: 'ativo_circulante', ec: c.ec, pc: c.pc, k,
    vt: '1.234.567,89', vn: 1234567.89, op: 3, cf: 0.95,
  })));
  // Formato agrupado: contexto uma vez, colunas uma vez, conta uma vez.
  const agrupado = [{
    s: 'Ativo Circulante', sc: 'ativo_circulante', op: 3, cols,
    l: contas.map((k) => ({ k, vt: ['1.234.567,89', '1.234.567,89'], vn: [1234567.89, 1234567.89], cf: 0.95 })),
  }];

  const antes = JSON.stringify(plano).length;
  const depois = JSON.stringify(agrupado).length;
  const reducao = (1 - depois / antes) * 100;
  assert.ok(reducao >= 45, `esperava >=45% de redução no documento comparativo, obteve ${reducao.toFixed(1)}%`);

  // E os dois formatos têm de produzir EXATAMENTE as mesmas linhas no banco —
  // economia que muda o dado gravado não é economia, é perda.
  const doAgrupado = achatarGrupos(agrupado).linhas;
  assert.equal(doAgrupado.length, plano.length);
  assert.deepEqual(
    doAgrupado.map((l) => [l.secao, l.secao_canonica, l.periodo_coluna, l.chave, l.valor_num, l.origem_pagina, l.confianca]),
    plano.map((l) => [l.s, l.sc, l.pc, l.k, l.vn, l.op, l.cf]));
});

test('Chaves curtas de linhas cortam o overhead de tokens de saída (documentos densos truncavam antes)', () => {
  // Achado em produção (sessão 7 cont.¹¹): os 3 documentos que truncaram
  // (finish_reason=length) no "teste v18" eram consolidados comparativos
  // multi-ano — cada conta vira 2-3 linhas via periodo_coluna. Prova que a
  // representação por linha ficou objetivamente mais compacta (menos
  // caracteres de CHAVE repetidos centenas de vezes por documento).
  const linhaAntiga = {
    secao: 'Ativo Circulante', secao_canonica: 'ativo_circulante', entidade_coluna: null,
    periodo_coluna: '2023', chave: 'Caixa e equivalentes de caixa', valor_texto: '1.234.567,89',
    valor_num: 1234567.89, origem_pagina: 3, confianca: 0.95,
  };
  const linhaNova = {
    s: 'Ativo Circulante', sc: 'ativo_circulante', ec: null,
    pc: '2023', k: 'Caixa e equivalentes de caixa', vt: '1.234.567,89',
    vn: 1234567.89, op: 3, cf: 0.95,
  };
  const bytesAntigos = JSON.stringify(linhaAntiga).length;
  const bytesNovos = JSON.stringify(linhaNova).length;
  assert.ok(bytesNovos < bytesAntigos, `esperava reduzir; antigo=${bytesAntigos} novo=${bytesNovos}`);
  const reducaoPct = (1 - bytesNovos / bytesAntigos) * 100;
  assert.ok(reducaoPct >= 15, `esperava >=15% de redução por linha, obteve ${reducaoPct.toFixed(1)}%`);
});

// O guarda de orçamento tem de estar DEPOIS da medição do documento e ANTES de
// qualquer gasto. As duas metades são igualmente obrigatórias:
//
//   • depois do `Medir Documento`, porque é de lá que vêm as linhas com número e
//     o número de blocos — sem isso o guarda volta a estimar por byte, com a
//     margem de 1,8× que recusava lote que cabia;
//   • antes do `Precisa Fallback?`, porque a primeira chamada à OpenAI sai dali
//     (`IA Classificar`). Entre o `Medir Documento` e esse IF não há gasto
//     nenhum: o `Extrair Texto` é local, o `Upload Storage` é ramo lateral, e
//     nenhum documento foi registrado ainda.
//
// Este teste é o que impede alguém de "arrumar" o grafo movendo o guarda de
// volta para antes do conteúdo — ou, pior, para depois da primeira chamada.
test('Topologia: o teto de gasto fica entre a medição do documento e a primeira chamada', () => {
  assert.deepEqual(wf.connections['Classificar Nome'].main[0].map((c) => c.node), ['Preparar Conteudo']);
  assert.deepEqual(wf.connections['Medir Documento'].main[0].map((c) => c.node), ['Orcamento do Lote']);
  // O orçamento não segue direto: entre ele e a cadeia há o IF que separa "cabe"
  // de "não cabe". O ramo do NÃO existe porque a recusa precisava chegar ao
  // portal — lançando ali mesmo, a mensagem ficava só no log do n8n e a tela
  // seguia dizendo "estamos organizando tudo com cuidado" para sempre.
  assert.deepEqual(wf.connections['Orcamento do Lote'].main[0].map((c) => c.node), ['Lote cabe?']);
  // O RAMO DO "CABE" ABRE O LOTE **AO LADO**, e segue inteiro (0156).
  //
  // A PRIMEIRA VERSÃO DESTE ASSERT CODIFICAVA O BUG: ela exigia
  // `Lote cabe? -> Abrir Lote -> Precisa Fallback?`, que põe um nó Postgres
  // INLINE no fluxo por documento. Nó Postgres substitui o item; o `caso_id`
  // sumiu e o `Registrar Documento` gravou ZERO de 38 com a execução verde.
  // Invariante que descreve o mecanismo protege o mecanismo, inclusive quando ele
  // está errado — a regra da casa, cobrada aqui contra o próprio teste.
  //
  // O que se afirma agora é o COMPORTAMENTO: o lote é aberto antes de a extração
  // começar, E o item chega inteiro na cadeia. As duas coisas, juntas.
  const doCabe = wf.connections['Lote cabe?'].main[0].map((c) => c.node);
  assert.deepEqual(doCabe, ['Abrir Lote', 'Precisa Fallback?'],
    'o "cabe" abre o lote (ramo terminal, primeiro) e segue com o item inteiro');
  assert.equal(wf.connections['Abrir Lote'], undefined,
    'o Abrir Lote é ramo TERMINAL — inline ele substituiria o item de todo documento');
  assert.equal(wf.nodes.find((n) => n.name === 'Abrir Lote').executeOnce, true,
    'a pergunta é do LOTE, não do documento — sem executeOnce ele abriria uma vez por item');
  // Desde 13/10/2026 a recusa do orcamento entra no `Registrar Recusa` por um
  // Merge (`Juntar Recusas`), junto com a do tamanho do arquivo: um caminho so.
  assert.deepEqual(wf.connections['Lote cabe?'].main[1].map((c) => c.node), ['Juntar Recusas']);
  assert.deepEqual(wf.connections['Juntar Recusas'].main[0].map((c) => c.node), ['Registrar Recusa']);
  // GRAVA e só então ABORTA: a ordem é o ponto. Abortar antes de gravar deixaria
  // o portal sem a causa, que é exatamente o defeito que este ramo corrige.
  assert.deepEqual(wf.connections['Registrar Recusa'].main[0].map((c) => c.node), ['Abortar Lote']);
  assert.equal(wf.connections['Abortar Lote'], undefined, 'abortar é o fim do ramo');

  // E A PROPRIEDADE QUE NÃO PODE CAIR, escrita como caminho e não como nome de
  // nó: nenhum nó que fale com a OpenAI é alcançável a partir do `Intake` sem
  // passar pelo `Lote cabe?`. É isso que "barrar de graça" significa.
  const alcancaveisSemOGuarda = new Set(['Intake (Form)']);
  let mudou = true;
  while (mudou) {
    mudou = false;
    for (const [origem, conf] of Object.entries(wf.connections)) {
      if (!alcancaveisSemOGuarda.has(origem) || origem === 'Lote cabe?') continue;
      for (const ramo of conf.main || []) {
        for (const c of ramo || []) {
          if (!alcancaveisSemOGuarda.has(c.node)) { alcancaveisSemOGuarda.add(c.node); mudou = true; }
        }
      }
    }
  }
  for (const nome of ['IA Classificar', 'IA Extrair']) {
    assert.ok(!alcancaveisSemOGuarda.has(nome),
      `${nome} é alcançável sem passar pelo "Lote cabe?" — o teto deixou de barrar antes de gastar`);
  }
});

// A TOPOLOGIA ANTIGA (até esta rodada) mandava TODO item, de qualquer
// mimetype, para um `Extrair Texto` único (operação PDF) — CSV era parseado à
// mão dentro de `Preparar Conteudo`, e XLSX/XLS/XML nunca eram extraídos. O
// dono editou o n8n VIVO pendurando 5 nós "Extract from..." (CSV/XML/PDF/
// XLSX/XLS) em PARALELO depois de `Preparar Conteudo`, todos para o mesmo
// destino — fan-out CEGO: cada documento virava 5 itens (1 certo, 4 lixo), e
// a mudança nunca existiu no repositório (some na próxima republicação). Este
// teste trava o oposto: um `Roteador de Formato` que manda CADA documento a
// EXATAMENTE UM extrator, e um Merge que reconverge tudo antes de `Medir
// Documento` — nunca dois nós crus na mesma saída, nunca um extrator recebendo
// o formato errado.
test('Topologia: Upload é ramo lateral; o Roteador manda cada formato a UM extrator só', () => {
  const destinosDePreparar = wf.connections['Preparar Conteudo'].main[0].map((c) => c.node);
  assert.deepEqual(destinosDePreparar.sort(), ['Roteador de Formato', 'Upload Storage'].sort());
  assert.equal(wf.connections['Upload Storage'], undefined, 'Upload não alimenta nenhum node');
  // O ramo lateral não pode derrubar a ingestão (regra do c): uma falha do Storage
  // vira item de erro e a execução segue. É o que o onError garante; sem ele o 4xx
  // lança e os dois ramos que saem de Preparar Conteudo morrem juntos.
  assert.equal(byName['Upload Storage'].onError, 'continueRegularOutput');

  const roteador = wf.nodes.find((n) => n.name === 'Roteador de Formato');
  assert.ok(roteador, 'existe o nó que decide o formato ANTES de qualquer extrator');
  assert.equal(roteador.type, 'n8n-nodes-base.switch', 'decisão por Switch nativo, não por Code');
  // CADA FORMATO CONHECIDO TEM A SUA PRÓPRIA SAÍDA — é o comportamento que
  // falta descrever para não virar "5 nós soltos": o roteador DECIDE, não
  // apenas existe.
  const chaves = roteador.parameters.rules.values.map((r) => r.outputKey);
  // SÓ OS FORMATOS QUE PRECISAM DE DECODIFICADOR BINÁRIO TÊM SAÍDA PRÓPRIA.
  // Eram seis (pdf/imagem/csv/xlsx/xls/xml) até 12/09/2026; `imagem`, `texto` e
  // `xml` saem de `Preparar Conteudo` já com o `content_part` definitivo e vão
  // pelo fallback direto ao Merge. `csv` deixou de existir como ramo: era ele
  // que mandava `text/plain` ao `Extract From File`, que o rejeita.
  assert.deepEqual(new Set(chaves), new Set(['pdf', 'xlsx', 'xls']),
    'só pdf/xlsx/xls precisam de extrator; o resto já chega resolvido');

  // ==========================================================================
  // O PORTÃO QUE A AMO PAGOU PARA EXISTIR.
  // ==========================================================================
  //
  // O defeito de 12/09/2026 não foi um padrão de regex errado: foi uma regra de
  // roteamento SOBREVIVER ao destino dela. `csv: 'csv|^text/plain$'` estava certo
  // enquanto o destino era um `parseCsv` nosso (que aceita qualquer texto); ficou
  // errado no instante em que o destino virou o `Extract From File` nativo, que
  // valida o mimeType e recusa `text/plain`. A regex não mudou — a CAPACIDADE do
  // destino mudou, e nada ligava as duas pontas. 60 documentos, zero linhas.
  //
  // Este invariante liga as pontas: nenhum formato que `Preparar Conteudo` já
  // resolve sozinho pode ser roteado para um nó nativo. Um `outputKey` novo
  // apontando para um `extractFromFile` que não sabe recebê-lo reprova AQUI, no
  // gerador, antes de virar execução.
  const RESOLVIDOS_NO_NO = new Set(['texto', 'xml', 'imagem', 'csv', 'desconhecido']);
  const nomePorTipo = new Map(wf.nodes.map((n) => [n.name, n.type]));
  for (const [i, chave] of chaves.entries()) {
    const destino = (wf.connections['Roteador de Formato'].main[i] || [])[0];
    assert.ok(destino, `a saída "${chave}" do roteador não vai a lugar nenhum`);
    assert.ok(!RESOLVIDOS_NO_NO.has(chave),
      `"${chave}" já é resolvido em Preparar Conteudo e NÃO pode ser roteado a um nó nativo `
      + '— foi exatamente assim que os 60 documentos da AMO viraram mensagem de erro');
  }
  // E o recíproco: nenhum `extractFromFile` do workflow pode receber algo que
  // não veio de uma saída de formato binário do roteador.
  const extratores = wf.nodes.filter((n) => n.type === 'n8n-nodes-base.extractFromFile').map((n) => n.name);
  assert.deepEqual(extratores.sort(), ['Extrair Texto', 'Extrair XLS', 'Extrair XLSX'].sort(),
    'os extratores nativos são só os de formato binário — `Extrair CSV`/`Extrair XML` pediam ao n8n '
    + 'que devolvesse o texto que os bytes já são, e era o `Extrair CSV` que recusava `text/plain`');
  assert.ok(!nomePorTipo.has('Extrair CSV'), 'o nó que quebrou a AMO não pode voltar');
  assert.ok(roteador.parameters.options?.fallbackOutput,
    'formato desconhecido cai num fallback explícito (mantém a pendência), nunca é descartado');
  // NENHUMA SAÍDA MANDA PARA MAIS DE UM DESTINO — o oposto exato do fan-out
  // cego que a auditoria descreveu (5 nós recebendo o MESMO item).
  const saidasDoRoteador = wf.connections['Roteador de Formato'].main;
  for (const [i, ramo] of saidasDoRoteador.entries()) {
    assert.equal(ramo.length, 1, `saída ${i} do Roteador de Formato manda para mais de um destino`);
  }
  // TODOS OS RAMOS CONVERGEM NUM MERGE SÓ, e dali para `Recompor Conteudo
  // Extraido` → `Medir Documento`. Nenhum caminho pula direto para `Medir
  // Documento` — é isso que garante 1 item por documento chegando lá, mesmo
  // quando um extrator de planilha devolveu várias linhas (ver os testes do
  // `Recompor Conteudo Extraido` mais abaixo).
  const alcancaMedirDireto = Object.entries(wf.connections)
    .filter(([, conf]) => (conf.main || []).flat().some((c) => c.node === 'Medir Documento'))
    .map(([origem]) => origem);
  assert.deepEqual(alcancaMedirDireto, ['Recompor Conteudo Extraido'],
    'só o nó que reagrupa por documento pode alimentar Medir Documento — nenhum atalho de formato');
  assert.deepEqual(wf.connections['Juntar Extracao de Conteudo'].main[0].map((c) => c.node),
    ['Recompor Conteudo Extraido']);
  assert.deepEqual(wf.connections['Medir Documento'].main[0].map((c) => c.node), ['Orcamento do Lote']);
  const destinosDeRegistrar = wf.connections['Registrar Documento'].main[0].map((c) => c.node);
  assert.deepEqual(destinosDeRegistrar.sort(), ['Recompor Contexto', 'Recomputar Completude'].sort());
});

// ---------------------------------------------------------------------------
// O `Recompor Conteudo Extraido` — o nó que faz o roteamento por formato
// TERMINAR em UM item por documento, nunca em fan-out (regra 6 do CLAUDE.md:
// invariante novo tem de ser MEDIDO não-vazio). Os testes abaixo rodam o
// CÓDIGO REAL do nó, não uma descrição dele.
// ---------------------------------------------------------------------------
const ctxCsv = {
  caso_id: 'caso-uuid-1', hash: 'hash-a-csv', arquivo_ref: 'caso-uuid-1/hash-a-csv.csv', nome_original: 'faturamento.csv',
  content_mime: 'text/csv',
  content_part: { type: 'text', text: '(extracao de CSV pendente do no nativo Extrair CSV)' },
  aviso_conteudo: 'Arquivo CSV ainda nao foi extraido pelo no nativo (Extrair CSV).',
};
const ctxXlsx = {
  caso_id: 'caso-uuid-1', hash: 'hash-b-xlsx', arquivo_ref: 'caso-uuid-1/hash-b-xlsx.xlsx', nome_original: 'balancete.xlsx',
  content_mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  content_part: { type: 'text', text: '(extracao de XLSX pendente do no nativo Extrair XLSX)' },
  aviso_conteudo: 'Arquivo .xlsx ainda nao foi extraido pelo no nativo (Extrair XLSX).',
};
const textoDaParte = (parte) => parte.text;

test('Recompor Conteudo Extraido: linhas de DOIS documentos (CSV e XLSX) NUNCA se misturam', async () => {
  // O extrator nativo devolve UMA LINHA POR ITEM (o comportamento documentado
  // do `Extract From File` para planilha) — 2 linhas do CSV, 3 do XLSX,
  // intercaladas de propósito para provar que o agrupamento é por
  // ORIGEM, não por posição na lista.
  const entradas = [
    { json: { Conta: 'Caixa', Valor: '100' } }, // csv, linha 1
    { json: { Produto: 'X', Qtd: '10' } }, // xlsx, linha 1
    { json: { Conta: 'Bancos', Valor: '50' } }, // csv, linha 2
    { json: { Produto: 'Y', Qtd: '20' } }, // xlsx, linha 2
    { json: { Produto: 'Z', Qtd: '30' } }, // xlsx, linha 3
  ];
  const ctxPorIndice = [ctxCsv, ctxXlsx, ctxCsv, ctxXlsx, ctxXlsx].map((j) => ({ json: j }));
  const out = await run('Recompor Conteudo Extraido', {
    items: entradas, refs: { 'Preparar Conteudo': ctxPorIndice },
  });

  // A MEDIDA CENTRAL: 5 linhas de planilha viram 2 documentos, nunca 5 e nunca 1.
  assert.equal(out.length, 2, '2 linhas de um documento + 3 de outro têm de virar DOIS itens');
  const doCsv = out.find((i) => i.json.hash === 'hash-a-csv');
  const doXlsx = out.find((i) => i.json.hash === 'hash-b-xlsx');
  assert.ok(doCsv && doXlsx, 'cada documento de origem aparece exatamente uma vez na saída');
  // A CHAVE DO ORIGINAL ATRAVESSA O RECOMPOR: o `Registrar Documento` a le' do item
  // que sai daqui, e se ela se perdesse o arquivo_ref gravado viraria o literal
  // 'undefined' (o defeito dos onze dias do `documento_id`, em outro campo).
  assert.equal(doCsv.json.arquivo_ref, 'caso-uuid-1/hash-a-csv.csv');
  assert.equal(doXlsx.json.arquivo_ref, 'caso-uuid-1/hash-b-xlsx.xlsx');

  const textoCsv = textoDaParte(doCsv.json.content_part);
  assert.match(textoCsv, /Caixa/);
  assert.match(textoCsv, /Bancos/);
  assert.doesNotMatch(textoCsv, /Produto/, 'linha do XLSX vazou para dentro do CSV');

  const textoXlsx = textoDaParte(doXlsx.json.content_part);
  assert.match(textoXlsx, /Produto/);
  assert.doesNotMatch(textoXlsx, /Caixa|Bancos/, 'linha do CSV vazou para dentro do XLSX');

  // A PENDÊNCIA SE FECHA: extração bem-sucedida não pode continuar dizendo
  // "não foi extraído" (regra 1 — mas ao contrário: sucesso real também não
  // pode ficar disfarçado de ausência).
  assert.equal(doCsv.json.aviso_conteudo, null);
  assert.equal(doXlsx.json.aviso_conteudo, null);
});

test('6164 de novo: Recompor Conteudo Extraido declara pairedItem em TODO item que devolve', async () => {
  // POR QUE ESTE TESTE EXISTE, e por que ele não estava aqui quando precisou:
  // o nó de fan-out original (`Fatiar Extracao`/`Juntar Blocos`) tem guarda de
  // `pairedItem` desde o 6164, mas a guarda foi escrita como uma LISTA DE NOMES
  // de nó. `Recompor Conteudo Extraido` muda a quantidade de itens exatamente
  // como eles (N linhas de planilha → 1 documento) e não estava na lista, então
  // nasceu SEM `pairedItem` e nenhuma suíte reprovou.
  //
  // O EFEITO, se tivesse ido para produção: `Medir Documento` resolve o
  // contexto por `$('Preparar Conteudo').item`, que depende do pareamento. Sem
  // ele a expressão devolve vazio, o `catch` cai para `{}` e TODO documento
  // CSV/XLSX/XLS/XML chega ao `Registrar Documento` sem `caso_id`,
  // `nome_original`, `hash` nem `tipo_taxonomia` — ou seja, o roteamento por
  // formato quebraria justamente os formatos que ele existe para consertar.
  //
  // Este teste afirma COMPORTAMENTO (todo item devolvido é rastreável até a
  // entrada que o gerou), não a lista de nós que alguém lembrou de escrever.
  const entradas = [
    { json: { Conta: 'Caixa', Valor: '100' } },
    { json: { Produto: 'X', Qtd: '10' } },
    { json: { Conta: 'Bancos', Valor: '50' } },
  ];
  const ctxPorIndice = [ctxCsv, ctxXlsx, ctxCsv].map((j) => ({ json: j }));
  const out = await run('Recompor Conteudo Extraido', {
    items: entradas, refs: { 'Preparar Conteudo': ctxPorIndice },
  });
  assert.ok(out.length > 0, 'o nó devolveu itens (senão o teste não mede nada)');
  for (const it of out) {
    assert.ok(it.pairedItem && Number.isInteger(it.pairedItem.item),
      `item sem pairedItem: ${JSON.stringify(it.json).slice(0, 120)}`);
    assert.ok(it.pairedItem.item >= 0 && it.pairedItem.item < entradas.length,
      'o pairedItem aponta para um índice que existe na entrada');
  }
});

test('Recompor Conteudo Extraido: PDF e imagem atravessam sem reconstrução', async () => {
  // Caso 1: PDF — o item É a saída do `Extrair Texto` ({text,numpages}), sem
  // `caso_id` nenhum. Não pode ser tratado como linha de planilha. O
  // ANCESTRAL (`Preparar Conteudo`) é quem tem `formato_detectado='pdf'`.
  const ctxPdf = { caso_id: 'caso-uuid-1', formato_detectado: 'pdf', content_part: { type: 'text', text: '(arquivo pdf)' } };
  const doPdf = { json: { text: 'Caixa 100', numpages: 1 } };
  // Caso 2: imagem — passou pelo fallback do Switch, chega como o próprio item
  // de `Preparar Conteudo` (com `caso_id`).
  const doImagem = { json: { caso_id: 'caso-uuid-1', formato_detectado: 'imagem', content_part: { type: 'image_url', image_url: { url: 'data:...' } } } };

  const out = await run('Recompor Conteudo Extraido', {
    items: [doPdf, doImagem], refs: { 'Preparar Conteudo': [{ json: ctxPdf }, doImagem] },
  });
  assert.equal(out.length, 2, 'nenhum dos dois precisa de reconstrução — 1 item entra, 1 sai');
  assert.equal(out[0].json.text, 'Caixa 100', 'PDF: Medir Documento lê text/numpages direto, sem mexer');
  assert.deepEqual(out[1].json.content_part, doImagem.json.content_part, 'imagem não é reconstruída');
});

// ===========================================================================
// MEDIDO NÃO-VAZIO (regra 2) — O INVARIANTE QUE A AMO COMPROU, e o que ele
// substitui é tão importante quanto o que ele afirma.
// ===========================================================================
//
// O TESTE QUE ESTAVA AQUI INVENTAVA A FIXTURE, e com isso BLINDOU o defeito em
// vez de pegá-lo. Ele montava o item de extrator-que-falhou assim:
//
//     // "`onError: continueRegularOutput` devolve o item de ENTRADA sem tocar"
//     const doFalha = { json: { ...ctxCsv, hash: 'hash-c-falhou' } };   // COM caso_id
//     assert.equal(out[2].json.aviso_conteudo, ctxCsv.aviso_conteudo,
//       'extrator que falhou preserva o aviso — nunca vira sucesso fingido');
//
// A premissa é FALSA e nunca foi medida. Quando o `Extract From File` lança por
// item, o n8n NÃO repassa o item de entrada: emite `{error: "<mensagem>"}`, SEM
// `caso_id`. Medido na instância do dono em 12/09/2026, 60 itens idênticos:
// `{error: "The file selected in 'Input Binary Field' is not in csv format"}`.
//
// Com `caso_id` na fixture, o item saía pelo Caso 1 (passa direto) e o assert
// passava. Sem ele — a realidade — o item caía no ramo de PLANILHA e a mensagem
// de erro virava LINHA: `content_part` e `text` passavam a ser "error\nThe file
// selected...", e `aviso_conteudo` era SOBRESCRITO por null. A falha virava
// sucesso fingido, a IA recebia a mensagem técnica no lugar do balanço, e o
// banco gravou 60 documentos como `ilegivel` com 84–98% de confiança sobre
// arquivos íntegros. É a regra 4 do CLAUDE.md cobrada ao contrário: a fixture
// inventada não provou um bug que não existia — escondeu um que existia.
//
// DESLIGAR A CORREÇÃO (remover o ramo `if(!('caso_id' in raw) && ('error' in raw))`
// de `CODE_RECOMPOR_EXTRACAO`, em `build-workflow.mjs`) FAZ ESTE TESTE REPROVAR
// EM 5 ASSERTS — medido, e o número está na mensagem do commit.
test('MEDIDO: extrator que FALHA não vira linha de planilha — a forma real do erro do n8n', async () => {
  const ctxPlan = {
    caso_id: 'caso-uuid-1', hash: 'hash-amo', nome_original: 'AMOBELEZA - BALANÇO 2025.xlsx',
    formato_detectado: 'xlsx',
    content_part: { type: 'text', text: '(extracao de XLSX pendente do no nativo Extrair XLSX)' },
    aviso_conteudo: 'Arquivo .xlsx ainda nao foi extraido pelo no nativo (Extrair XLSX).',
  };
  // A FORMA MEDIDA, não a suposta: o que o n8n de verdade emite.
  const doErro = { json: { error: "The file selected in 'Input Binary Field' is not in csv format" } };

  const out = await run('Recompor Conteudo Extraido', {
    items: [doErro], refs: { 'Preparar Conteudo': [{ json: ctxPlan }] },
  });

  assert.equal(out.length, 1, 'o documento não some nem se multiplica');
  const j = out[0].json;
  // 1. O CONTEÚDO NUNCA É A MENSAGEM DE ERRO. Este é o assert que a AMO comprou:
  //    sem ele, "error | The file selected..." foi o que a IA recebeu 60 vezes.
  const enviado = JSON.stringify(j.content_part);
  assert.ok(!/not in csv format/.test(enviado),
    'a mensagem de erro do n8n NUNCA pode virar o conteúdo mandado à IA');
  assert.ok(!/^error\b/m.test(String(j.text || '')),
    '`text` (o que a régua de cobertura mede) não pode ser a mensagem de erro');
  // 2. `text` nulo, não string vazia nem lixo: ausência declarada, não fingida.
  assert.equal(j.text, null, 'sem extração não há texto — e null é diferente de ""');
  // 3. A PENDÊNCIA SOBREVIVE. Era ela que `avisoTruncamentoPlanilha([1 linha])`
  //    apagava ao devolver null.
  assert.ok(j.aviso_conteudo && /FALHOU/.test(j.aviso_conteudo),
    'a falha de extração continua declarada como pendência');
  // 4. E DIZ QUE A CULPA É DO PIPELINE, não do arquivo. O banco gravou 60
  //    documentos como `ilegivel` porque o modelo, recebendo a mensagem
  //    técnica, concluiu que o ARQUIVO estava ilegível. Os arquivos estavam
  //    íntegros.
  assert.ok(/nao registre este documento como ilegivel|falha do PIPELINE/i.test(j.aviso_conteudo),
    'a pendência tem de dizer que a falha é do pipeline, não do arquivo');
  // 5. O contexto do documento sobrevive — sem isto o documento perde o dono.
  assert.equal(j.caso_id, 'caso-uuid-1', 'o documento continua ligado ao caso');
});

test('Recompor Conteudo Extraido: XML vira texto corrido, não linhas de planilha', async () => {
  const ctxXml = {
    caso_id: 'caso-uuid-1', hash: 'hash-d-xml', nome_original: 'extrato.xml', content_mime: 'application/xml',
    content_part: { type: 'text', text: '(extracao de XML pendente do no nativo Extrair XML)' },
    aviso_conteudo: 'Arquivo XML ainda nao foi extraido pelo no nativo (Extrair XML).',
  };
  const out = await run('Recompor Conteudo Extraido', {
    items: [{ json: { data: '<extrato><lancamento valor="100"/></extrato>' } }],
    refs: { 'Preparar Conteudo': [{ json: ctxXml }] },
  });
  assert.equal(out.length, 1);
  assert.match(textoDaParte(out[0].json.content_part), /<lancamento/);
  assert.equal(out[0].json.aviso_conteudo, null);
});

// MEDIDO NÃO-VAZIO (regra 2 do CLAUDE.md), achado numa revisão adversarial
// (11/09/2026): `Recompor Conteudo Extraido` sempre escreveu `content_part` (o
// que vai para a IA) mas NUNCA `text` — e `Medir Documento`, o nó seguinte na
// cadeia real, só lê `doExtrator.text`/`texto_pdf`. Para TODO documento
// CSV/XLSX/XLS/XML, `temTexto` saía falso, `celulas_no_documento` e
// `contas_no_documento` saíam `null`, e `avaliarCobertura` (lib/cobertura.mjs)
// se cala quando `esperadas` é `null` — a régua de cobertura estava DESLIGADA
// para estes DOIS formatos desde que ela existe (a 0154 só a acendeu para
// PDF), sem NENHUMA pendência acusando. Um `balancete.xlsx` de centenas de
// linhas podia nunca fatiar (`Fatiar Extracao` cai no bloco único por falta de
// `linhas_do_texto`) e nunca acusar cobertura baixa, com `Conferir Lote` VERDE.
//
// DESLIGAR A CORREÇÃO (reverter as duas linhas `text:` em
// `CODE_RECOMPOR_EXTRACAO`, `build-workflow.mjs`) FAZ ESTE TESTE REPROVAR — 4
// asserts (as duas asserções de "não é null" e as duas de tamanho mínimo),
// medido antes de escrever a correção.
test('MEDIDO: XLSX e XML alimentam a régua de cobertura depois de Recompor Conteudo Extraido — sem `text`, ela ficava calada', async () => {
  const reconstruidoXlsx = await run('Recompor Conteudo Extraido', {
    items: [{ json: { Conta: 'Caixa', Valor: '380' } }, { json: { Conta: 'Duplicatas', Valor: '22310' } }],
    refs: { 'Preparar Conteudo': [{ json: ctxXlsx }, { json: ctxXlsx }] },
  });
  assert.equal(reconstruidoXlsx.length, 1);
  assert.equal(typeof reconstruidoXlsx[0].json.text, 'string',
    'a planilha reconstruída tem de carregar `text` — é o que Medir Documento lê');
  assert.match(reconstruidoXlsx[0].json.text, /Caixa/);

  const medidoXlsx = await run('Medir Documento', {
    item: reconstruidoXlsx[0], refs: { 'Preparar Conteudo': reconstruidoXlsx[0] },
  });
  assert.notEqual(medidoXlsx.json.celulas_no_documento, null,
    'régua de cobertura calada para XLSX — a mesma falha que a 0154 fechou só para PDF');
  assert.ok(medidoXlsx.json.celulas_no_documento >= 2, 'as duas linhas da planilha têm de contar como células');
  assert.ok(Array.isArray(medidoXlsx.json.linhas_do_texto) && medidoXlsx.json.linhas_do_texto.length >= 2);

  const ctxXml2 = {
    caso_id: 'caso-uuid-1', hash: 'hash-g-xml', nome_original: 'extrato2.xml', content_mime: 'application/xml',
    content_part: { type: 'text', text: '(pendente)' }, aviso_conteudo: 'pendente',
  };
  const reconstruidoXml = await run('Recompor Conteudo Extraido', {
    items: [{ json: { data: '<extrato><lancamento valor="380"/></extrato>' } }],
    refs: { 'Preparar Conteudo': [{ json: ctxXml2 }] },
  });
  assert.equal(typeof reconstruidoXml[0].json.text, 'string',
    'o XML reconstruído tem de carregar `text` — é o que Medir Documento lê');

  const medidoXml = await run('Medir Documento', {
    item: reconstruidoXml[0], refs: { 'Preparar Conteudo': reconstruidoXml[0] },
  });
  assert.notEqual(medidoXml.json.celulas_no_documento, null, 'régua de cobertura calada para XML');
});

test('Recompor Conteudo Extraido: sem rastro (itemMatching falha) isola a linha, nunca funde com outro documento', async () => {
  // $('Preparar Conteudo') SEM a referência: itemMatching lança para todo
  // índice. O nó NÃO PODE tratar isso como "documento sem chave" e juntar tudo
  // numa única pilha — seria misturar documentos genuinamente diferentes, "o
  // erro mais caro possível" nas palavras da 0026.
  const out = await run('Recompor Conteudo Extraido', {
    items: [{ json: { Conta: 'Caixa', Valor: '1' } }, { json: { Conta: 'Bancos', Valor: '2' } }],
    refs: {},
  });
  assert.equal(out.length, 2, 'sem rastro, cada linha fica isolada — nunca agrupada às cegas');
  for (const it of out) {
    assert.match(it.json.aviso_conteudo, /nao foi possivel religar/);
  }
});

test('Recompor Conteudo Extraido: MEDIDO — desligar o roteamento (voltar à topologia antiga) faz este teste reprovar', () => {
  // Este teste não roda o nó — ele registra a MEDIÇÃO da regra 2 do CLAUDE.md
  // (todo invariante novo tem de ser medido NÃO-VAZIO), feita à mão nesta
  // rodada: gerado o JSON com o roteamento por formato REVERTIDO para a
  // topologia antiga (o único `Extrair Texto` fixo em PDF, sem `Roteador de
  // Formato`, sem `Extrair CSV`/`XLSX`/`XLS`/`XML`, sem `Juntar Extracao de
  // Conteudo` nem `Recompor Conteudo Extraido`), a MESMA suíte (com estes
  // testes novos já escritos) foi rodada contra ele.
  //
  // MEDIDO nesta sessão: 436 testes, 10 reprovando — as 5 asserções deste
  // arquivo sobre `Recompor Conteudo Extraido` (inclusive esta), a nova
  // topologia (`Topologia: Upload é ramo lateral...`), e as 4 do
  // `espelho-inline.test.mjs` (`colunasDaPlanilha`/`spreadsheetToText`/
  // `avisoTruncamentoPlanilha`/cobertura) — porque o nó e as três funções que
  // ele embute deixam de existir no JSON. Religado o roteamento (o estado
  // deste commit), os 436 voltam a passar. O número fica aqui, não numa
  // mensagem de commit que ninguém relê: é o que prova que estes testes
  // pegam a ausência da correção, não só descrevem a presença dela.
  assert.ok(code('Recompor Conteudo Extraido'), 'o nó que reagrupa por documento tem de existir no workflow');
});

// O teste que o "Teste V45 - Canastra" pagou para existir: 19 dos 35 documentos
// desapareceram entre `Registrar Documento` e `Gravar Campos`, e a causa era
// topológica — `Precisa Fallback?`[false] e `Parse Classif` apontavam
// AMBOS para o `Registrar Documento`, duas conexões CRUAS no mesmo input. O n8n
// não garante uma execução por conexão nesse arranjo, e só o ramo do fallback
// propagou. Nada mediu isso: extração nunca chamada não deixa rastro em
// `campo_extraido`, nem em `evento_auditoria`, nem em `pendencia`.
test('Convergência: nenhum node recebe DUAS conexões cruas no mesmo input', () => {
  const chegadas = new Map(); // "node:index" → [origens]
  for (const [origem, conf] of Object.entries(wf.connections)) {
    for (const ramo of conf.main || []) {
      for (const c of ramo || []) {
        const chave = `${c.node}:${c.index ?? 0}`;
        if (!chegadas.has(chave)) chegadas.set(chave, []);
        chegadas.get(chave).push(origem);
      }
    }
  }
  for (const [chave, origens] of chegadas) {
    assert.equal(origens.length, 1,
      `"${chave}" recebe ${origens.length} conexões (${origens.join(', ')}) — use um Merge: `
      + 'convergência crua no mesmo input perdeu 19 de 35 documentos no Teste V45');
  }
});

test('Dedup (0118): o curto-circuito existe, e junta por Merge — nunca convergência crua', () => {
  // A segunda metade da 0026, que ela mesma deixou escrita como fatia própria:
  // não PAGAR a extração quando o arquivo é idêntico e o prompt não mudou.
  // Quem responde isso é o banco (`reaproveitou_extracao`); quem age é este IF.
  const iff = wf.nodes.find((n) => n.name === 'Extracao ja feita?');
  assert.ok(iff, 'existe o IF do dedup');
  assert.equal(iff.type, 'n8n-nodes-base.if');
  assert.match(JSON.stringify(iff.parameters), /reaproveitou_extracao/);

  // O IF vem DEPOIS do registro (é de lá que sai a resposta) e ANTES de montar a
  // requisição — o `Montar Req Extracao` é runOnceForEachItem e não pode devolver
  // zero itens, restrição que a 0026 já havia mapeado.
  assert.deepEqual(wf.connections['Recompor Contexto'].main[0].map((c) => c.node), ['Extracao ja feita?']);
  assert.deepEqual(wf.connections['Extracao ja feita?'].main[1].map((c) => c.node), ['Montar Req Extracao']);

  // O ramo do "já extraído" NÃO pode passar por nenhum nó que fale com a OpenAI.
  const reaproveitado = wf.connections['Extracao ja feita?'].main[0];
  assert.deepEqual(reaproveitado.map((c) => c.node), ['Juntar Extraidos']);
  assert.equal(reaproveitado[0].index, 1, 'o ramo do dedup entra no input 1 do Merge');

  const merge = wf.nodes.find((n) => n.name === 'Juntar Extraidos');
  assert.ok(merge, 'existe o Merge que junta os dois ramos');
  assert.equal(merge.type, 'n8n-nodes-base.merge');
  assert.equal(merge.parameters.mode, 'append');
  assert.equal(merge.parameters.numberInputs, 2);
  const viaExtracao = wf.connections['Registrar Diagnostico'].main[0];
  assert.deepEqual(viaExtracao.map((c) => c.node), ['Juntar Extraidos']);
  assert.equal(viaExtracao[0].index ?? 0, 0, 'quem extraiu entra no input 0');
  assert.deepEqual(wf.connections['Juntar Extraidos'].main[0].map((c) => c.node), ['Reconciliar (Classe A)']);

  // E a cauda do lote continua rodando para os dois: reconciliação por documento,
  // reconciliação do CASO, custo, gravação do uso e a conferência do lote.
  //
  // A ORDEM É O CONTEÚDO DA 0152, e por isso está travada aqui. `Reconciliar
  // (Classe A)` roda por documento e faz só a árvore (que é intra-documento);
  // `Reconciliar Lote` roda UMA vez e faz as oito checagens que leem (caso,
  // entidade, período). Medido no book-araucaria: 82 chaves para 190 documentos,
  // e a Araucária Serraria sozinha tem 80 documentos disparando as mesmas
  // checagens 80 vezes — foi isso que deixou a execução 1h52 de pé sem gravar
  // uma reconciliação.
  assert.deepEqual(wf.connections['Reconciliar (Classe A)'].main[0].map((c) => c.node), ['Reconciliar Lote']);
  assert.deepEqual(wf.connections['Reconciliar Lote'].main[0].map((c) => c.node), ['Resumo de Custo']);

  const porDoc = wf.nodes.find((n) => n.name === 'Reconciliar (Classe A)');
  assert.match(porDoc.parameters.query, /fn_reconciliar_por_documento\(\$1::uuid, 'documento'\)/,
    'o nó por documento declara o escopo `documento` — sem isso ele volta a rodar as oito');

  const doLote = wf.nodes.find((n) => n.name === 'Reconciliar Lote');
  assert.ok(doLote, 'existe o nó que reconcilia o CASO');
  assert.match(doLote.parameters.query, /fn_reconciliar_caso\(\$1::uuid\)/);
  assert.equal(doLote.executeOnce, true,
    '`executeOnce`: sem ele o nó do LOTE roda uma vez por item e a 0152 não serve para nada');
});

// A TRANSAÇÃO QUE APAGAVA O LOTE INTEIRO (medida na execução 7172, 27/08/2026).
//
// O modo `single` do nó Postgres — que é o DEFAULT — junta as queries de todos
// os itens numa transação implícita só. Observado em `pg_stat_activity`: um
// backend com 11 `fn_reconciliar_por_documento` num statement, `xact_start` =
// `query_start`, ativo há 13min25 segurando RowExclusiveLock em `reconciliacao`
// — e sete minutos depois o backend tinha sumido com ZERO linhas commitadas.
//
// Em 38 documentos isso nunca apareceu, porque a transação durava segundos.
test('os nós Postgres POR ITEM commitam item a item (`independently`), não num bloco só', () => {
  const porItem = ['Registrar Documento', 'Gravar Campos (Sombra)', 'Registrar Diagnostico',
                   'Reconciliar (Classe A)'];
  for (const nome of porItem) {
    const n = wf.nodes.find((x) => x.name === nome);
    assert.ok(n, `existe o nó ${nome}`);
    assert.equal(n.parameters.options?.queryBatching, 'independently',
      `${nome} tem de commitar por item: no modo padrão (\`single\`) as queries de todos os `
      + 'itens entram numa transação só, e a morte de uma apaga o lote inteiro — foi o que '
      + 'aconteceu com os 190 documentos do araucária');
  }
});

test('Dedup (0118): o fingerprint sai do prompt+modelo+esquema, e viaja no registro', () => {
  const q = wf.nodes.find((n) => n.name === 'Registrar Documento').parameters;
  assert.match(q.query, /p_fingerprint_extracao=>\$15::text/,
    'o registro tem de MANDAR o fingerprint — sem ele a 0118 nunca reaproveita nada');

  // O valor é calculado no BUILD a partir do prompt real. Recalculá-lo aqui, do
  // mesmo jeito, é o que garante que ele acompanhe a mudança do prompt: a `0116`
  // mexeu no prompt, e uma extração feita com o prompt de ontem NÃO vale como a
  // de hoje (foi assim que a DMPL classificada como MUTUOS ficou presa no código
  // errado antes da 0024).
  const esperado = createHash('sha256')
    .update([SYSTEM_PROMPT, MODELO_EXTRACAO, JSON.stringify(extractionSchema())].join('\u0000'))
    .digest('hex')
    .slice(0, 16);
  assert.ok(q.options.queryReplacement.includes(`'${esperado}'`),
    'o fingerprint embutido no nó divergiu do prompt/modelo/esquema em uso');

  // E a prova de que ele MUDA quando o prompt muda — se não mudasse, o dedup
  // reaproveitaria extração feita com regra velha, que é pior que não deduplicar.
  const comOutroPrompt = createHash('sha256')
    .update([`${SYSTEM_PROMPT} nota nova`, MODELO_EXTRACAO, JSON.stringify(extractionSchema())].join('\u0000'))
    .digest('hex')
    .slice(0, 16);
  assert.notEqual(esperado, comOutroPrompt);
});

test('Os dois ramos do fallback se juntam num Merge, em inputs DIFERENTES', () => {
  const merge = wf.nodes.find((n) => n.name === 'Juntar Ramos');
  assert.ok(merge, 'existe o node Juntar Ramos');
  assert.equal(merge.type, 'n8n-nodes-base.merge');
  assert.equal(merge.parameters.mode, 'append',
    'append: o lote é a UNIÃO dos dois ramos, não um casamento entre eles');
  assert.equal(merge.parameters.numberInputs, 2);

  // true → classifica por conteúdo; false → direto. Cada um no SEU input.
  assert.deepEqual(wf.connections['Precisa Fallback?'].main[0].map((c) => c.node), ['Montar Req Classif']);
  const direto = wf.connections['Precisa Fallback?'].main[1];
  assert.deepEqual(direto.map((c) => c.node), ['Juntar Ramos']);
  assert.equal(direto[0].index, 1, 'o ramo direto entra no input 1');
  const viaIA = wf.connections['Parse Classif'].main[0];
  assert.deepEqual(viaIA.map((c) => c.node), ['Juntar Ramos']);
  assert.equal(viaIA[0].index ?? 0, 0, 'o ramo da IA entra no input 0');

  assert.deepEqual(wf.connections['Juntar Ramos'].main[0].map((c) => c.node), ['Registrar Documento']);
});

// A extração não pode depender de pareamento para achar o PDF: o nó Postgres
// SUBSTITUI o item, e o `$('Preparar Conteudo').item` que devolvia o conteúdo
// atravessava a convergência dos dois ramos. Agora o `Recompor Contexto` junta
// por ÍNDICE (com `.all()`, que não usa pairedItem) e o conteúdo viaja no item.
test('Montar Req Extracao lê o conteúdo do PRÓPRIO item, sem parear com outro nó', () => {
  const c = code('Montar Req Extracao');
  assert.ok(c.includes('const prep=$json'), 'o conteúdo vem do próprio item');
  assert.ok(!c.includes("$('Preparar Conteudo')"),
    'não pareia com o Preparar Conteudo — foi esse pareamento que perdeu 19 documentos');
  assert.ok(c.includes('content_part'), 'e recusa montar a chamada sem o arquivo');

  const r = code('Recompor Contexto');
  assert.ok(r.includes("$('Juntar Ramos').all()"),
    'a junção usa .all() (lista inteira, sem pairedItem), não .item');
  // Divergência de contagem tem de ser FALHA DECLARADA: associar o arquivo de um
  // documento ao id de outro é pior que falhar.
  assert.ok(r.includes('desalinhado'), 'e declara desalinhamento em vez de adivinhar');
});

// O Parse da classificação PRESERVA o content_part: era ele que o descartava, e
// por isso o ramo do fallback dependia de pareamento para reencontrar o PDF.
test('Parse Classif preserva o content_part no item', () => {
  const c = code('Parse Classif');
  assert.ok(c.includes('const {ia_body, ...item}=src'),
    'só o ia_body da classificação sai; o content_part fica');
  assert.ok(!/const \{ia_body, content_part/.test(c),
    'content_part não pode voltar a ser descartado aqui');
});

test('Modos e referências: cada node Code no modo certo; toda $(ref) existe no canvas', () => {
  const nomes = wf.nodes.map((n) => n.name);
  for (const n of wf.nodes) {
    if (n.type === 'n8n-nodes-base.code') {
      // Quatro nós legitimamente veem o LOTE inteiro, por motivos diferentes:
      // `Listar Arquivos` faz fan-out (1 item → N); `Orcamento do Lote` é N→N
      // mas precisa contar o lote para decidir se ele cabe no teto de gasto —
      // uma decisão que por definição não existe olhando um item por vez; e
      // `Resumo de Custo` responde "quanto custou ESTE LOTE", que é a mesma
      // classe de pergunta na outra ponta da cadeia.
      // `Fatiar Extracao` e `Juntar Blocos` são as duas pontas do fatiamento: um
      // documento vira N chamadas e N respostas voltam a ser um documento. Nenhum
      // dos dois é 1:1 por definição.
      // `Recompor Contexto` entra nessa lista porque a junção dele é POR ÍNDICE
      // contra a saída inteira do `Juntar Ramos` (`.all()`) — ele precisa das duas
      // listas completas para saber se elas têm o mesmo tamanho, e essa é
      // justamente a conferência que impede associar o PDF de um documento ao id
      // de outro. Em `runOnceForEachItem` não haveria lista para conferir.
      // `Recompor Conteudo Extraido` é outra fan-in: os extratores de planilha
      // devolvem uma LINHA por item (não um documento), e só vendo o lote
      // inteiro (`.all()`) dá para reagrupar as linhas de cada documento antes
      // de `Medir Documento` — o mesmo motivo de `Juntar Blocos`, um nível acima.
      if (['Listar Arquivos', 'Orcamento do Lote', 'Abortar Lote', 'Resumo de Custo',
        'Fatiar Extracao', 'Juntar Blocos', 'Recompor Contexto',
        'Recompor Conteudo Extraido', 'Agrupar Linhas XLSX', 'Agrupar Linhas XLS'].includes(n.name)
        // A espera entre tentativas é UMA para todos os blocos que falharam.
        || /^Esperar Retry \d+$/.test(n.name)) {
        assert.equal(n.parameters.mode, 'runOnceForAllItems', `${n.name} enxerga o lote inteiro`);
      } else {
        assert.equal(n.parameters.mode, 'runOnceForEachItem', `${n.name} é transformação 1:1`);
      }
      // toda referência $('X') aponta para um node que existe (pega renomeações)
      for (const m of n.parameters.jsCode.matchAll(/\$\('([^']+)'\)/g)) {
        assert.ok(nomes.includes(m[1]), `node "${n.name}" referencia "${m[1]}" que não existe no workflow`);
      }
    }
    // nós Postgres referenciam outros nós pelo nome na expressão de Query
    // Parameters (queryReplacement) — mesma pegadinha de renomeação se aplica.
    const queryReplacement = n.parameters?.options?.queryReplacement;
    if (typeof queryReplacement === 'string') {
      for (const m of queryReplacement.matchAll(/\$\('([^']+)'\)/g)) {
        assert.ok(nomes.includes(m[1]), `node "${n.name}" referencia "${m[1]}" que não existe no workflow`);
      }
    }
  }
});

// --- Anti-drift: o diagnóstico de erro do workflow É o de lib/extract.mjs -----
// Terceiro mirror deste repositório (depois do prompt e dos apelidos), e os dois
// anteriores JÁ divergiram na prática. Aqui a função é auto-contida de propósito
// e o gerador embute o `toString()` dela — este teste trava que os DOIS nós que
// diagnosticam erro carregam exatamente o mesmo código da lib.
test('os nós de parse carregam o MESMO diagnosticarErroApi de lib/extract.mjs', () => {
  const fonte = diagnosticarErroApi.toString();
  for (const nome of ['Parse Extracao', 'Parse Classif']) {
    assert.ok(code(nome).includes(fonte),
      `${nome}: o diagnóstico embutido divergiu da fonte em lib/extract.mjs`);
  }
});

// E o comportamento de verdade, executando o código REAL do nó: o sintoma exato
// do "teste v30" (o n8n devolve só a própria dica de 429) tem de virar causa
// nomeada, e uma causa que espaçar NÃO resolve tem de dizer isso.
test('Parse Extracao: 429 sem corpo vira causa nomeada; quota diz que espaçar não resolve', async () => {
  const req = { json: { documento_versao_id: 'ver-9', tipo: 'BALANCO', ia_body: {} } };
  const soDica = { json: { error: { message: "Try spacing your requests out using the batching settings under 'Options'" } } };
  const p1 = await run('Parse Extracao (tentativa 4)', { item: soDica, refs: { 'Esperar Retry 3': req } });
  assert.equal(p1.json.campos.length, 0);
  assert.match(p1.json.falha_motivo, /HTTP 429/);
  assert.match(p1.json.falha_motivo, /não disse QUAL/, 'não afirma cadência sem evidência');

  const comQuota = { json: { error: { httpCode: '429', cause: { error: { type: 'insufficient_quota', message: 'You exceeded your current quota' } } } } };
  const p2 = await run('Parse Extracao', { item: comQuota, refs: { 'Fatiar Extracao': req } });
  assert.match(p2.json.falha_motivo, /SEM CRÉDITO OU SEM COBRANÇA ATIVA/);
  assert.match(p2.json.falha_motivo, /NÃO resolve/, 'diz explicitamente o que não resolve');
  assert.match(p2.json.falha_motivo, /insufficient_quota/, 'o detalhe técnico vai junto');
});

// --- Anti-drift: os apelidos do workflow SÃO os de lib/taxonomia.mjs ---------
// Mesmo defeito do prompt, e este já estava acontecendo: a cópia à mão dentro de
// build-workflow.mjs parava em BALANCETE, então o nó que roda em produção não
// conhecia DF_AUDITADA, MAPA_DIVIDA, EXTRATO_BANCARIO, AGING_AR/AP, ESTOQUE,
// CERTIDOES, CONTINGENCIAS, SITUACAO_FISCAL, ORGANOGRAMA, RAZAO nem NOTAS_EXPL —
// arquivos com esses nomes saíam do passe de nome SEM TIPO, que é exatamente o
// gasto de chamada de IA que a classificação por nome existe para evitar.
test('os ALIASES do workflow gerado são IDÊNTICOS aos de lib/taxonomia.mjs (ordem inclusa)', () => {
  const m = code('Classificar Nome').match(/const ALIASES=(\[[\s\S]*?\]);/);
  assert.ok(m, 'ALIASES embutido como literal JSON no nó');
  // Ordem importa: a lista é avaliada de cima para baixo e a regra específica
  // ("faturamento intragrupo") tem de ser testada antes da genérica
  // ("faturamento"). deepEqual sem sort é intencional.
  assert.deepEqual(JSON.parse(m[1]), ALIASES, 'apelidos do workflow == fonte única, na mesma ordem');
});

// --- Cadência da OpenAI: a extração é mais lenta que a classificação ---------
// Teste v28 (14 documentos): DOIS caíram por 429 — e eram dois dos documentos
// MENORES do book. Não foi o tamanho deles; foi o balde de TPM já esvaziado pelos
// pesados que passaram antes. Quem esvazia o balde não é quem cai, então o que
// espalha as chamadas da extração no tempo é o que resolve; retry não (o
// `waitBetweenTries` do N8N tem teto de 5s, e 6 tentativas cabem na MESMA janela
// de TPM que acabou de recusar).
test('a cadência da extração É a aritmética do TPM, não um número escolhido', () => {
  // A correção do v30. A OpenAI calcula o consumo de rate limit como o MÁXIMO
  // entre `max_tokens` e os tokens ESTIMADOS DO REQUEST (entrada + saída) —
  // não só `max_tokens`. Logo o intervalo entre chamadas não é gosto: é
  // 60s ÷ (TPM ÷ (entrada + max_tokens)).
  //
  // A ENTRADA ENTROU NA CONTA EM 11/09/2026, achado numa revisão adversarial:
  // até então este teste (e o gerador) tratavam `max_tokens` como se cobrisse
  // "a chamada inteira" — falso. Um PDF de 20 páginas (`PAGINAS_MAX_MEDIDO`)
  // manda ~20.000 tokens de ENTRADA que a conta anterior ignorava por
  // completo, e MAIS os 16.384 de saída passa do teto de 30.000 do Tier 1
  // numa chamada SÓ — nenhum espaçamento entre chamadas evita isso.
  //
  // Este teste trava a RELAÇÃO, não o valor: se alguém mexer em max_tokens, no
  // pior caso de páginas ou no TPM da conta sem recalcular a cadência, ele
  // reprova. Era exatamente esse acoplamento que faltava — eu subi 6s→12s sem
  // olhar o max_tokens, e 12s suportava 5 chamadas/min = 81.920 TPM, quase 3x
  // o teto do Tier 1.
  //
  // O NÚMERO DO TIER SAI DO PROVEDOR, e não mais de uma constante escrita aqui.
  // `TPM_TIER1_GPT4O = 30000` era a mesma verdade dita num segundo lugar, e no
  // dia em que o provedor mudou ela virou uma afirmação sobre uma conta que o
  // sistema não usa mais.
  const intervalo = byName['IA Extrair'].parameters.options?.batching?.batch?.batchInterval;
  const chamadasPorMinuto = 60000 / intervalo;
  const tpmDemandado = chamadasPorMinuto * (RESERVA_ENTRADA_TOKENS_TESTE + MAX_OUTPUT_TOKENS);
  assert.ok(tpmDemandado <= TPM_CONTA,
    `a cadência demanda ${Math.round(tpmDemandado)} TPM, acima do limite da conta (${TPM_CONTA}) — `
    + `com intervalo de ${intervalo}ms e max_tokens de ${MAX_OUTPUT_TOKENS}`);
  // …e não folgado ao ponto de ser lentidão gratuita — quando é o balde de
  // TOKENS que manda. Quando o gargalo é o de CHAMADAS, exigir 80% do balde de
  // tokens seria exigir uma cadência que toma 429 na terceira chamada.
  //
  // E QUANDO O GARGALO É O PISO HISTÓRICO (`PISO_BATCHING_MS`), A MESMA LÓGICA
  // VALE PELO MESMO MOTIVO. Achado na troca de TPM de 14/09/2026 (30.000 →
  // 500.000, a conta real do dono): a matemática pura do TPM passou a pedir um
  // intervalo abaixo do piso medido no "teste v18" (3 de 16 documentos tomando
  // 429 com 3s), e o piso venceu — por desenho, é o maior dos três
  // (`INTERVALO_EXTRACAO_MS` em build-workflow.mjs). Uma conta com TPM alto o
  // bastante SEMPRE vai usar menos de 80% do próprio balde quando o piso
  // manda, e isso não é a "lentidão sem ganho" que este assert existe para
  // pegar — é o piso de segurança fazendo o trabalho dele. Exigir 80% aqui
  // seria pedir para o piso ser furado assim que a conta melhorar de tier.
  const intervaloTeoricoMs = 60000 / (TPM_CONTA / (RESERVA_ENTRADA_TOKENS_TESTE + MAX_OUTPUT_TOKENS));
  if (!RPM_CONTA && intervaloTeoricoMs >= PISO_BATCHING_MS) {
    assert.ok(tpmDemandado > TPM_CONTA * 0.8,
      `a cadência usa só ${Math.round(tpmDemandado)} de ${TPM_CONTA} TPM — lentidão sem ganho`);
  }
});

test('IA Extrair nunca espaça MENOS que IA Classificar, e as duas têm retry', () => {
  // ERA "espaça MAIS", e a mudança para "nunca menos" é a leitura certa do que o
  // teste sempre quis dizer. A extração espaçava mais na OpenAI por um motivo
  // específico: `max_tokens` reserva TPM, então cada extração pesa 16.384 tokens
  // do balde e a classificação pesa quase nada. Onde o gargalo é o número de
  // CHAMADAS, as duas pesam IGUAL — uma chamada é uma chamada — e as duas caem
  // no mesmo intervalo. Exigir estritamente mais ali seria exigir uma lentidão
  // que não compra nada.
  const extrair = byName['IA Extrair'];
  const classificar = byName['IA Classificar'];
  const intervalo = (n) => n.parameters.options?.batching?.batch?.batchInterval;
  assert.equal(n8nBatchSize(extrair), 1, 'extração: um documento por vez');
  assert.ok(
    intervalo(extrair) >= intervalo(classificar),
    `extração (${intervalo(extrair)}ms) não pode espaçar menos que classificação (${intervalo(classificar)}ms)`,
  );
  // ERA `>= 12000`, um número que a troca de TPM de 14/09/2026 (30.000 →
  // 500.000, a conta real do dono) expôs como o que sempre foi: o "v28"
  // (comentário em `lib/extract.mjs`, junto de `diagnosticarErroApi`) confessa
  // que subir de 6s para 12s foi um CHUTE sem evidência de que a causa daquela
  // falha fosse cadência. Com o TPM real, `INTERVALO_EXTRACAO_MS` passou a ser
  // decidido pelo PISO — exatamente o caso que o comentário dele já previa
  // ("no Tier 2, o intervalo cai bem abaixo do piso histórico de 6s") — e o
  // piso que tem evidência por trás (o "teste v18", 3 de 16 documentos
  // tomando 429 com 3s) é `PISO_BATCHING_MS`, não 12000. Travar em 12000 aqui
  // seria travar o CHUTE do v28, não o piso medido do v18.
  if (!RPM_CONTA) {
    assert.ok(intervalo(extrair) >= PISO_BATCHING_MS,
      `intervalo da extração = ${intervalo(extrair)}ms (abaixo do piso medido de ${PISO_BATCHING_MS}ms)`);
  }
  for (const n of [extrair, classificar]) {
    assert.equal(n.retryOnFail, true, `${n.name}: retry no nível do node`);
    assert.ok(n.maxTries >= 4, `${n.name}: maxTries=${n.maxTries}`);
    assert.equal(n.onError, 'continueRegularOutput',
      `${n.name}: falha da IA não derruba a execução (vira pendência)`);
  }
});

function n8nBatchSize(node) {
  return node.parameters.options?.batching?.batch?.batchSize;
}

// --- Anti-drift: o prompt do workflow É a fonte única de lib/extract.mjs -----
// Antes o prompt existia em TRÊS lugares (lib/extract.mjs, a paráfrase manual em
// build-workflow.mjs, e o JSON gerado) e eles já tinham divergido de fato: uma
// melhoria aplicada na fonte não chegava à produção até alguém reescrever o
// mirror à mão. Agora o gerador embute o SYSTEM_PROMPT literal — este teste
// trava essa propriedade (se alguém voltar a parafrasear, o teste quebra).
test('o promptSistema do workflow gerado é IDÊNTICO ao SYSTEM_PROMPT de lib/extract.mjs', () => {
  const node = wf.nodes.find((n) => n.name === 'Montar Req Extração' || n.name === 'Montar Req Extracao');
  assert.ok(node, 'nó de montagem da requisição de extração encontrado');
  const code = node.parameters.jsCode;
  const m = code.match(/const promptSistema=("(?:[^"\\]|\\.)*");/);
  assert.ok(m, 'promptSistema embutido como literal JSON no nó');
  assert.equal(JSON.parse(m[1]), SYSTEM_PROMPT, 'prompt do workflow == fonte única (sem paráfrase manual)');
});

test('o prompt em produção carrega as instruções de escala, sinal e período canônico', () => {
  // Garante que as melhorias de blindagem a variação de contrato chegaram ao
  // JSON que o dono importa no N8N (não só à fonte).
  const node = wf.nodes.find((n) => n.name === 'Montar Req Extração' || n.name === 'Montar Req Extracao');
  // O prompt é embutido como literal JSON (aspas internas escapadas), então a
  // verificação é sobre o texto DECODIFICADO — o que a OpenAI vai receber.
  const prompt = JSON.parse(node.parameters.jsCode.match(/const promptSistema=("(?:[^"\\]|\\.)*");/)[1]);
  for (const marca of ['MOEDA E ESCALA', '"milhar"', 'PARÊNTESES são NEGATIVOS', 'notação canônica', '12M25']) {
    assert.ok(prompt.includes(marca), `prompt em produção contém ${marca}`);
  }
});

test('Parse Extracao (nó real): escala não contamina linha não-monetária', async () => {
  // Mesma proteção de lib/extract.mjs (ehLinhaNaoMonetaria), verificada no
  // CÓDIGO QUE RODA EM PRODUÇÃO: um documento em "R$ mil" com margem em % e
  // lucro por ação não pode marcar essas linhas como "milhar" (mis-escala de
  // 1000x quando o fator for aplicado).
  const { preparado } = await chainFile(1);
  const req = await run('Montar Req Extracao', {
    item: await recomporPara(preparado, 'doc-9', 'ver-9'), env: {},
  });
  const resposta = { json: respostaIA(JSON.stringify({
    moeda: 'R$', unidade: 'Em milhares de reais',
    diagnostico: {
      entidade: 'Empresa Teste Ltda', tipo_confirma: true, tipo_sugerido: 'DRE',
      periodo_tipo: 'anual', periodo_referencia: '12M25', legibilidade: 'ok',
      nota_legibilidade: null, resumo: 'DRE 2025.', justificativa: 'ok',
    },
    linhas: [
      { s: 'Receita', sc: 'receita_bruta', ec: null, pc: null, k: 'Receita Líquida', vt: '10.000', vn: 10000, op: 1, cf: 0.9 },
      { s: null, sc: 'NAO_CLASSIFICAVEL', ec: null, pc: null, k: 'Margem Líquida %', vt: '12,5%', vn: 12.5, op: 1, cf: 0.9 },
      { s: null, sc: 'NAO_CLASSIFICAVEL', ec: null, pc: null, k: 'Lucro por Ação', vt: '1,25', vn: 1.25, op: 1, cf: 0.9 },
    ],
  })) };
  const parsed = await run('Parse Extracao', { item: resposta, refs: { 'Montar Req Extracao': req } });
  assert.equal(parsed.json.campos[0].unidade, 'milhar', 'conta monetária herda a escala normalizada');
  assert.equal(parsed.json.campos[1].unidade, null, 'linha em % não herda escala');
  assert.equal(parsed.json.campos[2].unidade, null, 'lucro por ação não herda escala');
  assert.equal(parsed.json.campos[1].valor_num, 12.5, 'valor preservado');
});

test('prefixo cacheável: o system prompt é IDÊNTICO entre documentos (e vem primeiro)', async () => {
  // A OpenAI cacheia automaticamente o PREFIXO do prompt (a partir de ~1024
  // tokens) e cobra ~metade pelos tokens em cache. Nosso system prompt tem
  // ~2,5k tokens e é o mesmo para TODO documento — desde que (a) venha como
  // primeira mensagem e (b) NÃO tenha nada interpolado por documento. É o que
  // paga a maior parte do custo de tê-lo completo. Este teste trava as duas
  // condições: se alguém interpolar nome de arquivo/tipo no system prompt, o
  // cache passa a falhar em cada chamada (custo silenciosamente maior) e o
  // teste quebra. O que varia por documento vive na mensagem de USER.
  const a = await run('Montar Req Extracao', {
    item: await recomporPara((await chainFile(0)).preparado, 'd0', 'v0'), env: {},
  });
  const b = await run('Montar Req Extracao', {
    item: await recomporPara((await chainFile(1)).preparado, 'd1', 'v1'), env: {},
  });
  const sistemaA = sistemaDaReq(a.json.ia_body);
  const sistemaB = sistemaDaReq(b.json.ia_body);
  // O prompt de sistema tem CASA PRÓPRIA nos dois dialetos (`role:'system'` na
  // OpenAI, `systemInstruction` no Google) — é o que permite ao provedor
  // reconhecer o prefixo. Concatená-lo na mensagem do usuário funcionaria e
  // custaria ~40% a mais em toda chamada.
  if (GEMINI) {
    assert.ok(a.json.ia_body.systemInstruction, 'o prompt de sistema tem campo próprio');
    assert.equal(a.json.ia_body.contents.length, 1, 'e não vira mais uma mensagem de conversa');
  } else {
    assert.equal(a.json.ia_body.messages[0].role, 'system', 'system prompt é a PRIMEIRA mensagem (prefixo)');
  }
  assert.equal(sistemaA, sistemaB, 'system prompt idêntico entre documentos diferentes');
  assert.ok(sistemaA.length > 3000, 'prefixo grande o suficiente para o cache valer');
  // E o que varia (nome do arquivo) está na mensagem de user, não no prefixo.
  assert.notEqual(textoDaReq(a.json.ia_body), textoDaReq(b.json.ia_body), 'o que varia por documento fica no user');
  assert.ok(!sistemaA.includes('BALANÇO ACUMULADO'), 'nada de nome de arquivo no system prompt');
});

test('Parse Extracao (nó real): propaga a ORDEM da linha (Supabase/migrations/0027)', () => {
  // O mirror dentro do JSON é o que roda em produção. Sem `ordem` aqui, a
  // migration e o export existem e o dado real chega sem o sinal — o defeito do
  // v28 continuaria acontecendo em silêncio.
  const parse = wf.nodes.find((n) => n.name === 'Parse Extracao');
  assert.ok(parse, 'nó Parse Extracao não existe');
  assert.match(parse.parameters.jsCode, /ach\.linhas\.map\(\(l,i\)=>\(\{ordem:i,/,
    'o nó não está numerando as linhas pela posição de leitura');
  // O achatamento vem EMBUTIDO da fonte. É o único lugar onde valor e coluna são
  // associados: um espelho à mão que divergisse aqui gravaria o número de 2024
  // na coluna de 2025, sem sintoma nenhum.
  assert.ok(parse.parameters.jsCode.includes(achatarGrupos.toString()),
    'o achatamento embutido no nó divergiu da fonte em lib/extract.mjs');
  // E o caminho do formato plano continua no nó, para um JSON velho importado
  // não virar "zero linhas extraídas" sem explicação.
  assert.match(parse.parameters.jsCode, /Array\.isArray\(p\.linhas\)/);
});

// --- Anti-drift: a entidade do nome no nó É a de lib/classifier.mjs -----------
// QUARTO mirror do repositório. Nasceu já embutido por `toString()` (como o
// diagnóstico de erro) em vez de copiado à mão, porque dos três anteriores DOIS
// divergiram na prática — o mirror manual é o defeito, não o descuido de quem
// mexeu depois.
test('Classificar Nome carrega o MESMO parseEntidade de lib/classifier.mjs', () => {
  assert.ok(code('Classificar Nome').includes(parseEntidade.toString()),
    'a entidade embutida no nó divergiu da fonte em lib/classifier.mjs');
});

// E o comportamento, executando o código REAL do nó — não a lib. É o que prova
// que a correção do v31 chega ao workflow que o dono importa: no v31 estes 14
// documentos gravaram entidade nula, e 8 deles perderam a única outra chance de
// tê-la quando a extração morreu no teto de gasto da OpenAI.
test('Classificar Nome: entidade sai do nome do arquivo, e a confiança não muda', async () => {
  const casos = [
    ['01_BP_Vertentes_Metalurgica_2025x2024.pdf', 'Vertentes Metalurgica', 0.9, false],
    ['06_BP_COMBINADO_Grupo_Vertentes_2025.pdf', 'Grupo Vertentes', 0.65, true],
    ['10_Faturamento_24M_Vertentes_Metalurgica.pdf', 'Vertentes Metalurgica', 0.6, true],
  ];
  for (const [nome, entidade, conf, fallback] of casos) {
    const out = await run('Classificar Nome', { item: { json: { caso_id: 'c-1', nome_original: nome } } });
    assert.equal(out.json.entidade, entidade, `entidade de ${nome} no nó`);
    assert.equal(out.json.confianca, conf, `confiança de ${nome} no nó`);
    assert.equal(out.json.precisa_fallback_ia, fallback, `fallback de ${nome} no nó`);
    // o nó e a lib têm de concordar — é o ponto de existir um mirror testado
    assert.equal(out.json.entidade, classifyByFilename(nome).entidade, `nó × lib para ${nome}`);
  }
});

// E A COMPOSIÇÃO, não só as peças. O espelho-inline confere `parseTipo`,
// `parsePeriodo` e `parseEntidade` uma a uma — e as três batiam — enquanto o nó
// montava a classificação com uma cópia à mão de `classifyByFilename` que tinha
// perdido a guarda `entidade = tipo ? parseEntidade(...) : null`. Medido em
// 24/09/2026 executando o `jsCode` commitado: `ANEXO IV - planilha final
// REV3.pdf` gravava a entidade "Iv Rev3" (a lib: null), exatamente a
// entidade-lixo que o comentário da lib diz ter corrigido. O teste acima não via
// porque todos os seus nomes TÊM tipo. Aqui entram os dois lados, e o nó tem de
// concordar com a lib em TODOS os campos que grava.
test('Classificar Nome concorda com classifyByFilename em todo campo, com e sem tipo no nome', async () => {
  const nomes = [
    'ANEXO IV - planilha final REV3.pdf',            // sem tipo: entidade-lixo "Iv Rev3"
    '34_Relatorio_do_Auditor_Independente_2025.pdf', // sem tipo: "Relatorio Auditor Independente"
    'Relatorio Grupo Alfa REV2.pdf',                 // sem tipo nem período
    '01_BP_Vertentes_Metalurgica_2025x2024.pdf',
    '06_BP_COMBINADO_Grupo_Vertentes_2025.pdf',
    'DRE_1T25_assinado.pdf',
  ];
  for (const limiar of [undefined, 0.85]) {
    for (const nome of nomes) {
      const out = await run('Classificar Nome', { item: { json: { caso_id: 'c-1', nome_original: nome, limiar_classificacao: limiar } } });
      const lib = classifyByFilename(nome, limiar);
      const campos = {
        tipo_taxonomia: lib.tipo_taxonomia,
        periodo_tipo: lib.periodo ? lib.periodo.tipo : null,
        periodo_ref: lib.periodo ? lib.periodo.referencia : null,
        assinado: lib.assinado,
        entidade: lib.entidade,
        confianca: lib.confianca,
        fonte: lib.fonte,
        precisa_fallback_ia: lib.precisa_fallback_ia,
        limiar_aplicado: lib.limiar_aplicado,
      };
      for (const [k, v] of Object.entries(campos)) {
        assert.deepEqual(out.json[k], v, `nó × lib em ${k} para ${nome} (limiar ${limiar})`);
      }
    }
  }
});

// --- O teto de gasto por execução, executando o nó REAL ----------------------
// Pedido do dono depois do v31: no máximo US$ 3 por execução completa, com o teto
// da OpenAI em US$ 5. As duas defesas são de camadas diferentes e nenhuma
// substitui a outra — ver o comentário do topo de lib/custo.mjs. Este teste cobre
// a de dentro: recusar o lote ANTES da primeira chamada.
const itemDoc = (nome, precisaFallback) => ({
  json: { caso_id: 'c-1', nome_original: nome, precisa_fallback_ia: precisaFallback },
  binary: { data: { fileName: nome, mimeType: 'application/pdf', data: '' } },
});

test('Orcamento do Lote: o lote que NÃO cabe é recusado antes de gastar', async () => {
  // ERA "o lote do v31 é RECUSADO", com 14 documentos e 22 chamadas — e com o
  // preço do provedor novo esses 14 documentos custam ~US$ 0,30 e PASSAM. O
  // teste passou a montar o lote a partir da própria constante de custo, e não
  // de um tamanho que só era grande no preço de agosto: o que ele prova é o
  // GUARDA (recusa antes de gastar, com mensagem acionável), e o guarda não tem
  // opinião sobre quantos documentos são muitos — ele tem uma sobre dinheiro.
  //
  // O lote do v31 continua no teste, uma etapa abaixo, agora do outro lado: ele
  // PASSA, e é a medição da troca de provedor num assert.
  const chamadasQueNaoCabem = Math.ceil(TETO_EXECUCAO_USD / CUSTO_ESTIMADO_DOC_USD) + 1;
  const items = Array.from({ length: chamadasQueNaoCabem }, (_, i) => itemDoc(`${i + 1}_BP_X_2025x2024.pdf`, false));
  // O nó não LANÇA mais: ele marca. A diferença existe para a recusa poder ser
  // GRAVADA no banco antes de a execução morrer — lançando aqui, a mensagem
  // ficava só no log do n8n e o portal seguia num "aguarde" eterno.
  const out = await run('Orcamento do Lote', { items });
  assert.equal(out[0].json.orcamento_cabe, false, 'o lote é recusado');
  assert.match(out[0].json.orcamento_mensagem, /Lote recusado ANTES de gastar/);
  assert.match(out[0].json.orcamento_mensagem, new RegExp(`${chamadasQueNaoCabem} chamada`),
    'a mensagem conta as CHAMADAS, não os documentos');
  assert.match(out[0].json.orcamento_mensagem, /Nada foi enviado ao provedor de IA e nada foi gravado/,
    'quem lê o erro precisa saber que reenviar é seguro');
  // Estes 14 documentos não trazem tamanho (o fixture tem binário vazio), então
  // quem decidiu foi o estimador PLANO — e a mensagem tem de dizer isso, senão
  // ninguém sabe qual das duas contas produziu a recusa.
  assert.match(out[0].json.orcamento_mensagem, /estimativa plana/);

  // E o aborto continua acontecendo, uma etapa depois.
  await assert.rejects(
    () => run('Abortar Lote', { items: out }),
    (e) => {
      assert.match(e.message, /Lote recusado ANTES de gastar/);
      return true;
    },
  );

  // O LOTE DO v31, QUE ERA O CASO DESTE TESTE, AGORA PASSA — 14 documentos, 8
  // deles pagando o PDF duas vezes = 22 chamadas. É o que a troca de provedor
  // comprou, escrito como assert e não como afirmação: o mesmo lote que estourou
  // o teto de US$ 5 no meio da execução em 31/07 cabe com folga.
  const v31 = [
    ...Array.from({ length: 6 }, (_, i) => itemDoc(`0${i + 1}_BP_X_2025x2024.pdf`, false)),
    ...Array.from({ length: 8 }, (_, i) => itemDoc(`1${i}_DFC_X_2025.pdf`, true)),
  ];
  const outV31 = await run('Orcamento do Lote', { items: v31 });
  assert.equal(outV31[0].json.orcamento_cabe, true, 'o lote do v31 cabe no preço de hoje');
  assert.equal(outV31[0].json.orcamento_chamadas, 22);
});

test('Orcamento do Lote: depois do renome o mesmo lote passa, e o binário sobrevive', async () => {
  // Mesmos 14 documentos, agora todos resolvidos pelo nome (12M25/L24M) = 14 chamadas.
  const items = Array.from({ length: 14 }, (_, i) => itemDoc(`${i + 1}_BP_X_12M25.pdf`, false));
  const out = await run('Orcamento do Lote', { items });
  assert.equal(out.length, 14, 'passa os 14 adiante');
  // 14 × CUSTO_ESTIMADO_DOC_USD, e o valor sai da CONSTANTE em vez de estar
  // escrito à mão. O literal já foi 2.10, depois 2.80, e agora seria 0.77 — três
  // vezes o mesmo teste reprovando por causa de um número que ele não estava
  // testando. O que importa é a MARGEM contra o teto, e é ela que fica travada.
  assert.equal(out[0].json.orcamento_estimado_usd, Number((14 * CUSTO_ESTIMADO_DOC_USD).toFixed(2)));
  assert.ok(out[0].json.orcamento_estimado_usd <= TETO_EXECUCAO_USD,
    'um lote de 14 documentos bem nomeados tem de caber — é o tamanho de lote que o dono usa');
  assert.equal(out[0].json.orcamento_chamadas, 14);
  // Regra 4 do topo do gerador: Code que repassa arquivo DEVE devolver `binary`.
  // Perder isso aqui deixaria `Preparar Conteudo` sem arquivo — e o sintoma seria
  // "conteudo nao suportado" em todo documento, longe da causa.
  assert.ok(out[13].binary?.data, 'o binário do último item sobreviveu ao nó');
  assert.equal(out[13].binary.data.fileName, '14_BP_X_12M25.pdf');
});

test('Orcamento do Lote decide POR CONTEÚDO quando o documento já foi medido', async () => {
  // O ponto do trabalho de 18/08: com o texto do PDF já lido, o guarda para de
  // estimar por byte. Estes 14 documentos trazem a medida que o `Medir
  // Documento` produz — linhas com número e páginas —, e o lote inteiro custa
  // uma fração do que a conta por byte dizia.
  const items = Array.from({ length: 14 }, (_, i) => ({
    json: {
      caso_id: 'c-1', nome_original: `${i + 1}_BP_X_12M25.pdf`, precisa_fallback_ia: false,
      bytes: 90_000, periodo_ref: '12M25',
      celulas_no_documento: 80, paginas_do_documento: 2,
      linhas_do_texto: Array.from({ length: 80 }, (_, l) => `Conta ${l} 1.234,00`),
    },
    binary: { data: { fileName: `${i + 1}_BP_X_12M25.pdf`, mimeType: 'application/pdf', data: '' } },
  }));
  const out = await run('Orcamento do Lote', { items });
  assert.equal(out.length, 14);
  assert.equal(out[0].json.orcamento_por_conteudo, true, 'decidiu pela medida, não pelo tamanho');
  assert.equal(out[0].json.orcamento_cabe, true);
  // 14 documentos de 2 páginas e 80 linhas custam centavos — e a estimativa por
  // byte dos MESMOS arquivos (14 × 90 KB = 1,2 MB × US$ 10,5/MB) daria US$ 12,9
  // e RECUSARIA o lote. É essa diferença que o trabalho corrige.
  assert.ok(out[0].json.orcamento_estimado_usd < 1,
    `esperava menos de US$ 1, veio ${out[0].json.orcamento_estimado_usd}`);
  assert.ok(out[13].binary?.data, 'o binário do último item sobreviveu ao nó');
});

test('Orcamento do Lote conta os BLOCOS do fatiamento, não os documentos', async () => {
  // Um documento denso é FATIADO, e cada fatia é uma chamada nova que reenvia o
  // PDF inteiro. A conta por byte não tinha como saber disso e subestimava
  // justamente o documento caro. Aqui o número de blocos sai de `planejarFatias`
  // — a mesma função que o `Fatiar Extracao` vai executar adiante.
  const linhas = Array.from({ length: 900 }, (_, l) => `Conta analitica ${l} 1.234,00`);
  const items = [{
    json: {
      caso_id: 'c-1', nome_original: '01_Razao_X_12M25.pdf', precisa_fallback_ia: false,
      bytes: 400_000, periodo_ref: '12M25',
      celulas_no_documento: linhas.length, paginas_do_documento: 30, linhas_do_texto: linhas,
    },
    binary: { data: { fileName: '01_Razao_X_12M25.pdf', mimeType: 'application/pdf', data: '' } },
  }];
  const out = await run('Orcamento do Lote', { items });
  assert.equal(out[0].json.orcamento_por_conteudo, true);
  assert.ok(out[0].json.orcamento_chamadas > 1,
    `um documento de ${linhas.length} linhas gasta mais de uma chamada; veio ${out[0].json.orcamento_chamadas}`);
});

test('Orcamento do Lote cai para a conta por BYTE quando falta medida', async () => {
  // PDF escaneado não tem camada de texto: `celulas_no_documento` vem nulo. O
  // lote inteiro cai no caminho antigo de propósito — medir só os documentos que
  // dá subestimaria o lote na exata proporção do que não se sabe.
  const items = [
    { json: { caso_id: 'c-1', nome_original: '1_BP_X_12M25.pdf', bytes: 90_000, celulas_no_documento: 80, paginas_do_documento: 2, linhas_do_texto: ['Caixa 1,00'] }, binary: {} },
    { json: { caso_id: 'c-1', nome_original: '2_BP_Y_12M25.pdf', bytes: 90_000, celulas_no_documento: null, paginas_do_documento: null, linhas_do_texto: null }, binary: {} },
  ];
  const out = await run('Orcamento do Lote', { items });
  assert.equal(out[0].json.orcamento_por_conteudo, false,
    'um documento sem medida joga o lote inteiro para a conta por byte');
});

test('Orcamento do Lote carrega o MESMO orcamentoDoLote de lib/custo.mjs', () => {
  assert.ok(code('Orcamento do Lote').includes(orcamentoDoLote.toString()),
    'o orçamento embutido no nó divergiu da fonte em lib/custo.mjs');
});

// O nó Code do n8n não importa arquivo: tudo o que a função referencia tem de
// estar DECLARADO dentro do nó. `orcamentoDoLote` passou a chamar
// `pesoDaChamadaDeClassificacao`, que lê a tabela de preço e os dois modelos —
// esquecer qualquer uma dessas declarações não quebra teste nenhum aqui, quebra
// a PRIMEIRA execução real, com ReferenceError e o lote inteiro perdido.
test('Orcamento do Lote declara tudo o que o corpo do orçamento referencia', () => {
  const c = code('Orcamento do Lote');
  for (const nome of ['PRECO_USD_POR_MILHAO', 'MODELO_CLASSIFICACAO', 'MODELO_EXTRACAO',
    'PARCELA_ENTRADA_NA_CHAMADA', 'PESO_MINIMO_CLASSIFICACAO', 'VERSAO_ORCAMENTO',
    'pesoDaChamadaDeClassificacao', 'TETO_EXECUCAO_USD', 'CUSTO_POR_MB_USD',
    'CUSTO_MINIMO_CHAMADA_USD', 'BYTES_POR_MB']) {
    assert.ok(new RegExp(`const ${nome}\\s*=`).test(c), `${nome} não está declarado no nó`);
  }
  // E o nó tem de RODAR de verdade — a conferência acima é textual, esta não.
  // Só o preâmbulo (tudo antes de `$input`, que não existe fora do n8n) e uma
  // chamada de verdade em cima dele.
  const preambulo = c.slice(0, c.indexOf('const itens = $input'));
  const r = new Function(`${preambulo}\nreturn orcamentoDoLote({documentos: 2, chamadasPorDocumento: 2, bytes: 2048});`)();
  assert.equal(r.versao, VERSAO_ORCAMENTO, 'o nó decide com a MESMA versão da fonte');
  assert.ok(r.fatorCusto < 2, 'a 2ª chamada pesa menos que a 1ª dentro do nó, não só na lib');

  // ==========================================================================
  // E AS OUTRAS DUAS FUNÇÕES TAMBÉM TÊM DE RODAR — a lacuna que este teste
  // tinha, com o nome dele afirmando o contrário.
  // ==========================================================================
  //
  // O nome diz "declara tudo o que o corpo do orçamento referencia", mas até
  // 12/09/2026 o teste EXECUTAVA só `orcamentoDoLote`. Quem o nó de verdade
  // chama é `orcamentoDoLotePorConteudo` (que chama `custoEstimadoPorConteudo`),
  // e essas duas nunca eram executadas aqui — a conferência delas era só
  // TEXTUAL, pela lista de nomes acima, que ninguém atualizava junto.
  //
  // MEDIDO nesta rodada: quando `custoEstimadoPorConteudo` passou a chamar
  // `ehFormatoDeTexto`, o `jsCode` gerado estourava `ReferenceError:
  // ehFormatoDeTexto is not defined` em QUALQUER chamada (inclusive PDF), e
  // ESTE teste continuava verde. É o defeito central do projeto dentro do
  // próprio portão que existe para pegá-lo: um portão que mede um terço do que
  // o nome dele promete tem a mesma aparência de um portão que mede tudo.
  //
  // Os DOIS formatos, porque o ramo de texto e o de PDF são caminhos
  // diferentes dentro da função e um verde no outro não prova nada.
  const porConteudo = new Function(`${preambulo}
    return orcamentoDoLotePorConteudo({ documentos: [
      { celulas: 80, paginas: 2, colunas: 3, blocos: 1, bytes: 90000, formato: 'pdf' },
      { celulas: 900, paginas: null, colunas: 2, blocos: 1, bytes: 670_000, formato: 'texto' },
    ], tokensPromptSistema: 100 });`)();
  assert.equal(porConteudo.porConteudo, true,
    'um lote com PDF e TEXTO medidos decide POR CONTEÚDO dentro do nó — se `paginas` voltar a ser '
    + 'exigida de todo documento, o de texto reprova e o lote inteiro cai no proxy por byte');
  // 670 KB é o tamanho REAL de um `.txt` do lote da AMO, e não é escolha
  // estética: com documentos minúsculos o `.toFixed(2)` de `estimadoUSD`
  // arredonda para 0,00 e o assert passaria a não medir nada.
  assert.ok(porConteudo.estimadoUSD > 0, 'a conta roda de verdade dentro do nó, não só na lib');
  assert.equal(porConteudo.versao, VERSAO_ORCAMENTO);
});

// A VERSÃO NA MENSAGEM. Em 12/08/2026 o dono reexecutou o lote depois da
// correção e recebeu a recusa ANTIGA, palavra por palavra — porque o n8n roda o
// JSON importado, e o merge no repositório não reimporta nada. Da tela, código
// novo e código velho recusam igual. Com a versão na mensagem e no item, "o
// workflow importado é velho" deixa de ser hipótese e vira leitura.
test('a recusa do orçamento CARIMBA a versão — é como se vê que o n8n está com o workflow velho', () => {
  const r = orcamentoDoLote({ documentos: 400, chamadasPorDocumento: 1, bytes: 400 * 1024 * 1024 });
  assert.equal(r.cabe, false);
  assert.ok(r.mensagem.startsWith(`[orçamento ${VERSAO_ORCAMENTO}]`), r.mensagem);
  assert.ok(code('Orcamento do Lote').includes('orcamento_versao: r.versao'),
    'a versão tem de viajar com o item também quando o lote PASSA');
});

// A extração é a tarefa sem rede: se ela errar, ninguém confere depois. A
// classificação tem rede (o `diagnostico` da própria extração confere
// tipo/entidade/período e abre pendência). É essa assimetria que autoriza o
// modelo barato de um lado e proíbe do outro — e é ela que este teste trava.
test('cada nó pede o SEU modelo, e a extração nunca pede o mais barato', () => {
  // ERA `assert.equal(MODELO_EXTRACAO, 'gpt-4o')`, e travar o nome do modelo era
  // travar o fornecedor: o teste reprovava a troca de provedor sem ter opinião
  // nenhuma sobre o que a troca fazia de errado. O que ele sempre quis provar é
  // a ASSIMETRIA — a extração não tem rede depois dela, a classificação tem — e
  // isso se prova comparando os dois, não citando um nome.
  assert.ok(code('Montar Req Extracao').includes(`modelo:'${MODELO_EXTRACAO}'`));
  assert.ok(code('Montar Req Classif').includes(`modelo:'${MODELO_CLASSIFICACAO}'`));
  const precoExtracao = PRECO_USD_POR_MILHAO[MODELO_EXTRACAO];
  const precoClassificacao = PRECO_USD_POR_MILHAO[MODELO_CLASSIFICACAO];
  assert.ok(precoExtracao && precoClassificacao, 'modelo sem preço não entra em produção');
  assert.ok(precoExtracao.entrada >= precoClassificacao.entrada,
    'a extração nunca pode rodar no modelo MAIS BARATO que a classificação — seria a troca ao contrário');
});

test('Parse Classif mede o custo da SEGUNDA chamada (a metade da conta que ninguém olhava)', async () => {
  const { preparado } = await chainFile(0);
  const req = await run('Montar Req Classif', { item: preparado, refs: REFS_BASE, env: {} });
  const resp = { json: respostaIA(JSON.stringify({
      tipo_taxonomia: 'BALANCO', entidade: 'Empresa X Ltda', periodo_tipo: 'anual',
      periodo_referencia: '12M25', assinado: true, confianca: 0.91, justificativa: 'cabeçalho',
    }), { uso: { prompt_tokens: 10_000, completion_tokens: 120 } }) };
  const ok = await run('Parse Classif', { item: resp, refs: { 'Montar Req Classif': req } });
  // O VALOR SAI DA TABELA, não de um literal: o que este teste prova é que o nó
  // MEDE (e mede com o modelo certo, o de classificação), não quanto custa o
  // modelo da vez. Travar 0,001572 aqui foi o que fez este teste reprovar a troca
  // de provedor sem ter nada a dizer sobre ela.
  const pc = PRECO_USD_POR_MILHAO[MODELO_CLASSIFICACAO];
  assert.equal(ok.json.custo_classificacao_usd,
    Number(((10_000 * pc.entrada + 120 * pc.saida) / 1e6).toFixed(6)));

  // E o caminho da FALHA também declara o custo: a chamada que voltou sem
  // conteúdo depois de consumir tokens foi paga do mesmo jeito.
  const falha = await run('Parse Classif', {
    // O `usage` vem NA FORMA DO PROVEDOR: a chamada que falhou depois de
    // consumir tokens também foi paga, e um custo que só aparece no caminho feliz
    // é um custo subdeclarado.
    item: { json: { error: { message: 'timeout' }, ...respostaIA('', { uso: { prompt_tokens: 10_000, completion_tokens: 0 } }) } },
    refs: { 'Montar Req Classif': req },
  });
  assert.equal(falha.json.custo_classificacao_usd, Number(((10_000 * pc.entrada) / 1e6).toFixed(6)));
});

test('Parse Extracao mede o custo real da chamada a partir do usage', async () => {
  const req = { json: { documento_versao_id: 'ver-1', tipo: 'BALANCO', ia_body: {} } };
  const resp = {
    json: respostaIA(JSON.stringify({
        moeda: 'BRL', unidade: 'milhar',
        diagnostico: { entidade: 'Vertentes Metalurgica', tipo_confirma: true, tipo_sugerido: 'BALANCO', periodo_tipo: 'anual', periodo_referencia: '12M25', legibilidade: 'ok', nota_legibilidade: null, resumo: 'ok', justificativa: 'ok' },
        linhas: [{ s: 'Ativo', sc: 'ativo_circulante', ec: null, pc: null, k: 'Caixa', vt: '1.000', vn: 1000, op: 1, cf: 0.9 }],
      }), { uso: { prompt_tokens: 10_000, completion_tokens: 8_000 } }),
  };
  const out = await run('Parse Extracao', { item: resp, refs: { 'Montar Req Extracao': req } });
  const pe = PRECO_USD_POR_MILHAO[MODELO_EXTRACAO];
  assert.equal(out.json.custo_usd,
    Number(((10_000 * pe.entrada + 8_000 * pe.saida) / 1e6).toFixed(6)), 'custo medido, não estimado');
  assert.deepEqual(out.json.tokens, { entrada: 10_000, saida: 8_000, cache: 0 });
});

test('Resumo de Custo: soma o lote por NÓ, não por índice (a classificação é de um subconjunto)', async () => {
  // Só os documentos cujo nome não resolve o tipo passam pela classificação — 8
  // de 14 no book do dono. Casar item a item por índice atribuiria o custo da
  // classificação ao documento errado, que num relatório de custo é pior que
  // não ter relatório.
  const extracoes = [
    { json: { custo_usd: 0.06, tokens: { entrada: 12_000, saida: 5_000, cache: 2_900 }, campos: new Array(80).fill({}), falha_motivo: null, contas_no_documento: 100, contas_distintas: 40, blocos: 1 } },
    { json: { custo_usd: 0.04, tokens: { entrada: 8_000, saida: 3_000, cache: 2_900 }, campos: new Array(40).fill({}), falha_motivo: 'truncou', contas_no_documento: 200, contas_distintas: 80, blocos: 3 } },
    // Documento sem `usage`: conta como SEM MEDIÇÃO, nunca como custo zero.
    { json: { custo_usd: null, tokens: null, campos: [], falha_motivo: null } },
  ];
  const classificacoes = [{ json: { custo_classificacao_usd: 0.0016 } }];
  const out = await run('Resumo de Custo', {
    items: extracoes,
    refs: {
      // Desde o fatiamento o resumo lê o `Juntar Blocos` (um item por DOCUMENTO)
      // e não o `Parse Extracao` (um item por BLOCO) — contar blocos como
      // documentos diria "48 documentos" para um lote de 35.
      'Juntar Blocos': extracoes,
      'Parse Extracao': extracoes,
      'Parse Classif': classificacoes,
      'Orcamento do Lote': { json: { orcamento_estimado_usd: 0.42, orcamento_versao: 'v3 (2026-08-13)' } },
    },
  });
  const r = Array.isArray(out) ? out[0].json : out.json;
  assert.equal(r.documentos, 3);
  assert.equal(r.documentos_com_classificacao, 1, 'a classificação é de um SUBCONJUNTO');
  assert.equal(r.custo_extracao_usd, 0.1);
  assert.equal(r.custo_classificacao_usd, 0.0016);
  assert.equal(r.custo_total_usd, 0.1016);
  assert.deepEqual(r.tokens, { entrada: 20_000, saida: 8_000, cache: 5_800 });
  // 8.000 tokens de saída / 120 linhas — o número que recalibra o estimador.
  assert.equal(r.tokens_saida_por_linha, 66.7);
  assert.equal(r.documentos_com_falha, 1);
  assert.equal(r.documentos_sem_medicao, 1, 'sem usage é sem medição, nunca custo zero');
  // A cobertura do LOTE no mesmo painel: é a resposta para "o custo caiu porque
  // ficou eficiente ou porque deixou de extrair?".
  assert.equal(r.contas_nos_documentos, 300);
  assert.equal(r.contas_extraidas, 120);
  assert.equal(r.cobertura_do_lote, 0.4);
  assert.equal(r.documentos_fatiados, 1);
  assert.equal(r.custo_estimado_usd, 0.42, 'o estimado vem junto: é a única forma de calibrar');
  assert.match(r.resumo, /Custo REAL deste lote: US\$ 0\.1016 em 3 documento\(s\)/);
});

test('Resumo de Custo soma TODAS as execuções do nó — o lote se parte em dois ramos', async () => {
  // Achado na rodada de 14/08: o IF `Precisa Fallback?` manda os documentos por
  // dois caminhos, e o n8n executa a cadeia inteira UMA VEZ POR RAMO. O
  // `Juntar Blocos` rodou duas vezes — 16 documentos numa, 19 na outra, 35 no
  // total — e o painel reportava só a última. O custo do lote saiu pela METADE.
  const doc = (custo, saida, campos, celulas) => ({ json: {
    custo_usd: custo, tokens: { entrada: 100, saida, cache: 50 },
    campos: new Array(campos).fill({}), falha_motivo: null,
    contas_no_documento: celulas, contas_distintas: campos, blocos: 1,
  } });
  const out = await run('Resumo de Custo', {
    items: [doc(0.1, 10, 5, 10)],
    refs: {
      'Juntar Blocos': { runs: [
        [doc(0.1, 10, 5, 10), doc(0.2, 20, 10, 20)],   // ramo 1: 2 documentos
        [doc(0.3, 30, 15, 30)],                         // ramo 2: 1 documento
      ] },
      // E a classificação, que é de UM ramo só: `.all()` sem índice devolveria
      // tudo em CADA execução, e o custo dela entraria duas vezes na conta.
      'Parse Classif': { runs: [[{ json: { custo_classificacao_usd: 0.001 } }]] },
      'Orcamento do Lote': { json: { orcamento_estimado_usd: 1.79, orcamento_versao: 'v3 (2026-08-13)' } },
    },
  });
  const r = Array.isArray(out) ? out[0].json : out.json;
  assert.equal(r.documentos, 3, 'os dois ramos somados, não o último');
  assert.equal(r.custo_extracao_usd, 0.6);
  assert.equal(r.custo_classificacao_usd, 0.001, 'a classificação entra UMA vez');
  assert.equal(r.linhas_extraidas, 30);
  assert.equal(r.contas_nos_documentos, 60);
  assert.equal(r.cobertura_do_lote, 0.5);
  assert.deepEqual(r.tokens, { entrada: 300, saida: 60, cache: 150 });
});

test('Resumo de Custo não derruba o lote que ele resume, e o Conferir Lote fecha a cadeia', async () => {
  const resumo = wf.nodes.find((n) => n.name === 'Resumo de Custo');
  assert.ok(resumo, 'nó Resumo de Custo não existe');
  assert.equal(resumo.onError, 'continueRegularOutput');
  const saidas = Object.values(wf.connections).flatMap((c) => (c.main || []).flat().map((x) => x.node));
  assert.ok(saidas.includes('Resumo de Custo'), 'alguém tem de alimentá-lo');
  // O TERMINAL agora é o `Conferir Lote` (0112): a última pergunta do lote não é
  // "quanto custou", é "o pipeline passou por TODOS os documentos?". No Teste V45
  // o resumo de custo fechou a cadeia com 16 de 35 documentos extraídos e nada
  // reclamou — a conferência de fora existe para essa rodada não se repetir.
  // Entre os dois entrou a GRAVAÇÃO do custo (0115) — o resumo passa a durar em
  // tabela antes de a conferência dar o veredito. A ordem importa: o custo é
  // fato do lote, e o `Conferir Lote` continua sendo o último a falar.
  assert.deepEqual(wf.connections['Resumo de Custo'].main[0].map((c) => c.node), ['Gravar Uso do Lote']);
  assert.deepEqual(wf.connections['Gravar Uso do Lote'].main[0].map((c) => c.node), ['Conferir Lote']);
  assert.equal(wf.connections['Conferir Lote'], undefined, 'o Conferir Lote é o fim da cadeia');
  const conferir = wf.nodes.find((n) => n.name === 'Conferir Lote');
  assert.ok(conferir.parameters.query.includes('fn_conferir_lote'));
  // E sem NENHUMA referência resolvível ele devolve zero em vez de estourar — um
  // resumo que explode é um lote inteiro perdido no último passo.
  const out = await run('Resumo de Custo', { items: [{ json: {} }], refs: {} });
  const r = Array.isArray(out) ? out[0].json : out.json;
  assert.equal(r.custo_total_usd, 0);
  assert.equal(r.custo_estimado_usd, null);
});

test('Gravar Uso do Lote é idempotente POR EXECUÇÃO — sem isso todo custo sai dobrado', () => {
  const n = wf.nodes.find((x) => x.name === 'Gravar Uso do Lote');
  assert.ok(n, 'o nó não existe');
  assert.equal(n.type, 'n8n-nodes-base.postgres');
  assert.ok(n.parameters.query.includes('fn_registrar_uso_lote'), 'chama a função da 0115');

  const repl = n.parameters.options.queryReplacement;
  // O DEFEITO QUE ESTE TESTE EXISTE PARA BARRAR, e ele é o mais caro que esta
  // gravação poderia ter: o nó roda DUAS VEZES por lote (uma por ramo do
  // `Precisa Fallback?`) e as duas passadas trazem o total INTEIRO. Sem uma
  // chave por execução seriam duas linhas, e o custo de todo mandato sairia
  // 2× — um número errado PARA CIMA, que passa por prudência e ninguém
  // questiona. A idempotência mora na 0115 (`unique (caso_id, execucao_ref)`),
  // e ela só funciona se o nó mandar a referência.
  assert.match(repl, /\$execution\.id/,
    'sem $execution.id não há chave de idempotência, e as duas passadas do lote viram duas linhas');
  // O caso vem do nó de origem, não de `$json`: o item que chega aqui é o painel
  // de custo, e ele não carrega o caso_id.
  assert.match(repl, /\$\('Upsert Caso \(Postgres\)'\)/, 'o caso_id tem de vir do nó que o criou');
  assert.match(repl, /JSON\.stringify\(\$json\)/, 'o resumo inteiro vai como jsonb');

  // Uma gravação de RELATÓRIO nunca pode derrubar o lote que ela relata — é a
  // mesma razão do `onError` do `Resumo de Custo`, um nó antes.
  assert.equal(n.onError, 'continueRegularOutput');
  assert.ok(n.credentials?.postgres, 'nó Postgres sem credencial não roda');
});

test('o que o Resumo de Custo publica é o que a 0115 grava — os nomes têm de bater', async () => {
  // O ACOPLAMENTO É REAL E INVISÍVEL: a função lê o jsonb por NOME de campo
  // (`p_resumo->>'custo_total_usd'`). Renomear um campo do resumo não quebraria
  // teste nenhum — só faria a coluna virar NULL em silêncio, que é a forma mais
  // cara de errar num número de dinheiro. Este teste liga as duas pontas.
  const out = await run('Resumo de Custo', {
    items: [{ json: {} }],
    refs: {
      'Juntar Blocos': [[{ json: {
        custo_usd: 0.02, tokens: { entrada: 100, saida: 20, cache: 50 },
        campos: [{}, {}], contas_no_documento: 10, linhas_devolvidas: 8,
      } }]],
      'Parse Classif': [[{ json: { custo_classificacao_usd: 0.001 } }]],
    },
  });
  const r = Array.isArray(out) ? out[0].json : out.json;

  const sql = readFileSync(new URL('../../Supabase/migrations/0115_custo_do_lote.sql', import.meta.url), 'utf8');
  for (const campo of [
    'documentos', 'documentos_com_classificacao', 'documentos_fatiados',
    'documentos_com_falha', 'documentos_sem_medicao',
    'custo_total_usd', 'custo_extracao_usd', 'custo_classificacao_usd', 'custo_estimado_usd',
    'linhas_extraidas', 'contas_nos_documentos', 'contas_extraidas', 'orcamento_versao',
  ]) {
    assert.ok(campo in r, `o Resumo de Custo deixou de publicar "${campo}"`);
    assert.ok(sql.includes(`'${campo}'`), `a 0115 não lê "${campo}" do resumo`);
  }
  // Os tokens são aninhados, e a função os lê por caminho (`#>>`).
  assert.ok(r.tokens && 'entrada' in r.tokens && 'saida' in r.tokens && 'cache' in r.tokens);
  for (const t of ['entrada', 'saida', 'cache']) {
    assert.ok(sql.includes(`{tokens,${t}}`), `a 0115 não lê tokens.${t}`);
  }
});

// ---------------------------------------------------------------------------
// AS TRÊS CAMADAS CONTRA O TRUNCAMENTO E A EXTRAÇÃO PELA METADE (13/08/2026)
// ---------------------------------------------------------------------------

test('Camada 1: Extrair Texto é NATIVO, roda depois do teto de gasto e não derruba o lote', () => {
  const n = wf.nodes.find((x) => x.name === 'Extrair Texto');
  assert.ok(n, 'o nó não existe');
  assert.equal(n.type, 'n8n-nodes-base.extractFromFile');
  assert.equal(n.parameters.operation, 'pdf');
  assert.equal(n.parameters.binaryPropertyName, 'data');
  // PDF escaneado não tem camada de texto e este nó falha nele. `continue` é o
  // que faz o pior caso desta adição ser "o comportamento de ontem" em vez de
  // "lote perdido".
  assert.equal(n.onError, 'continueRegularOutput');
});

test('Camada 1: Medir Documento mede, e ausência de texto vira null (nunca zero)', async () => {
  const lote = await run('Listar Arquivos', { item: UPSERT_ITEM, items: [UPSERT_ITEM], refs: REFS_BASE });
  const classificado = await run('Classificar Nome', { item: lote[0], refs: REFS_BASE, itemIndex: 0, binaryStore: lote });
  const preparado = await run('Preparar Conteudo', { item: classificado, refs: REFS_BASE, itemIndex: 0, binaryStore: lote });
  // O preparo entrega o arquivo em base64 DENTRO do json — é por isso que perder
  // o binário depois daqui não custa nada, e é o que permite o `Extrair Texto`
  // (que descarta binário) entrar na corrente neste ponto.
  assert.ok(ehParteDeArquivo(preparado.json.content_part));
  assert.ok(preparado.binary?.data, 'o binário ainda segue: o Extrair Texto precisa dele');

  // O texto vem do PRÓPRIO input (o `Extrair Texto` é o nó anterior) e o
  // contexto, do `Preparar Conteudo`, que é ANCESTRAL — não de um irmão.
  const texto = ['CNPJ 44.555.667/0001-59', 'ATIVO', 'Caixa   380', 'Duplicatas   22.310'].join('\n');
  const medido = await run('Medir Documento', {
    item: { json: { text: texto, numpages: 1 } },
    refs: { 'Preparar Conteudo': preparado },
  });
  assert.equal(medido.json.caso_id, 'caso-uuid-1', 'o contexto da corrente é recomposto inteiro');
  assert.ok(ehParteDeArquivo(medido.json.content_part), 'e o conteúdo da chamada sobrevive');
  assert.equal(medido.json.celulas_no_documento, 3);
  assert.equal(medido.json.linhas_do_texto.length, 3);

  // Sem camada de texto (escaneado, ou nó que falhou): `null` é "não sei", nunca
  // "zero" — zero ligaria a guarda de cobertura com régua inventada justamente
  // no documento onde o modelo mais erra.
  const semTexto = await run('Medir Documento', {
    item: { json: { error: 'não foi possível extrair texto' } },
    refs: { 'Preparar Conteudo': preparado },
  });
  assert.equal(semTexto.json.celulas_no_documento, null);
  assert.equal(semTexto.json.linhas_do_texto, null);
  assert.equal(semTexto.json.caso_id, 'caso-uuid-1', 'e o contexto segue mesmo assim');
});

// A REGRA 2 DO README, AGORA TRAVADA POR TESTE.
//
// "Nó que SUBSTITUI o item não entra na corrente." Ela estava escrita desde o
// `Upload Storage`, e eu a violei mesmo assim ao pôr o `Extrair Texto` entre o
// `Lote cabe?` e o `Preparar Conteudo`. O `Extract From File` escreve o
// resultado do PDF no `json` e NÃO repassa o binário: o `caso_id` sumiu, e o
// banco recusou 35 documentos com "null value in column caso_id violates
// not-null constraint". Regra escrita em prosa é regra que volta a ser
// quebrada.
test('quem consome nó que SUBSTITUI o item tem de recompor o contexto por referência', () => {
  // A regra 2 do README, na forma exata que as duas falhas de 13/08 ensinaram.
  // Não é "esses nós não podem ter consumidor" — é que o consumidor não pode
  // simplesmente ler `$json`, porque o item que chega nele não tem mais o
  // contexto da corrente. `Upload Storage` resolve sendo lateral (ninguém lê);
  // `Extrair Texto` e os HTTP da OpenAI resolvem com um consumidor que recompõe.
  //
  // DESDE O ROTEAMENTO POR FORMATO, o consumidor DIRETO de um extrator pode
  // ser um Merge (`Juntar Extracao de Conteudo`) — um nó ESTRUTURAL, que só
  // combina ramos e não sabe nada de contexto. Exigir dele um `$('Nó').item`
  // seria travar MECANISMO (regra 3 do CLAUDE.md): o que importa é que, no
  // fim da cadeia de nós estruturais (Merge/Switch/IF, que só roteiam ou
  // combinam), exista um Code que recompõe — por isso a busca anda PARA
  // FRENTE atravessando esses nós até achar o consumidor de verdade.
  const ESTRUTURAIS = ['n8n-nodes-base.merge', 'n8n-nodes-base.switch', 'n8n-nodes-base.if'];
  const consumidoresReais = (nomeDoNo) => {
    const vistos = new Set();
    const reais = new Set();
    const fila = [nomeDoNo];
    while (fila.length) {
      const atual = fila.pop();
      for (const c of (wf.connections[atual]?.main || []).flat()) {
        if (vistos.has(c.node)) continue;
        vistos.add(c.node);
        const alvo = wf.nodes.find((x) => x.name === c.node);
        if (alvo && ESTRUTURAIS.includes(alvo.type)) fila.push(c.node);
        else reais.add(c.node);
      }
    }
    return [...reais];
  };

  const SUBSTITUEM_O_ITEM = ['n8n-nodes-base.extractFromFile', 'n8n-nodes-base.httpRequest'];
  for (const n of wf.nodes.filter((x) => SUBSTITUEM_O_ITEM.includes(x.type))) {
    const consumidores = consumidoresReais(n.name);
    if (consumidores.length === 0) continue;   // ramo lateral: ninguém lê, nada a conferir
    for (const nome of consumidores) {
      const c = code(nome);
      assert.ok(c, `${nome} consome "${n.name}" (por trás de Merge/Switch/IF) mas não é um nó Code — não tem como recompor`);
      assert.match(c, /\$\('[^']+'\)\.item/,
        `"${nome}" consome a saída de "${n.name}", que substitui o item: ele TEM de recompor o `
        + 'contexto por referência a um nó ANCESTRAL, nunca ler $json direto');
    }
  }
});

test('a referência que recompõe o contexto aponta para um ANCESTRAL, nunca para um irmão', () => {
  // `$('Nó').item` só resolve para nós ancestrais do item atual. Pendurado como
  // ramo IRMÃO, o `Extrair Texto` parou de derrubar o lote e parou também de ser
  // LIDO: a medição voltou vazia em 35 documentos (`celulas_nos_documentos: 0`) e
  // as camadas 2 e 3 ficaram desligadas sem ninguém notar.
  const ancestrais = (alvo) => {
    const vistos = new Set();
    const fila = [alvo];
    while (fila.length) {
      const atual = fila.pop();
      for (const [origem, conn] of Object.entries(wf.connections)) {
        if (!(conn.main || []).flat().some((c) => c.node === atual)) continue;
        if (vistos.has(origem)) continue;
        vistos.add(origem);
        fila.push(origem);
      }
    }
    return vistos;
  };
  for (const n of wf.nodes.filter((x) => x.type === 'n8n-nodes-base.code')) {
    const meus = ancestrais(n.name);
    for (const m of n.parameters.jsCode.matchAll(/\$\('([^']+)'\)\.item/g)) {
      assert.ok(meus.has(m[1]),
        `"${n.name}" lê $('${m[1]}').item, mas "${m[1]}" NÃO é ancestral dele — `
        + 'referência a ramo irmão não resolve, e o sintoma é o dado voltar vazio em silêncio');
    }
  }
});

test('a corrente inteira preserva caso_id e binário até o Registrar Documento', async () => {
  // O teste que faltava: os anteriores exercitavam cada nó ISOLADO e passavam
  // enquanto a produção morria no primeiro documento. Aqui a expressão REAL do
  // nó que quebrou é avaliada contra o item que a corrente REAL produz.
  const lote = await run('Listar Arquivos', { item: UPSERT_ITEM, items: [UPSERT_ITEM], refs: REFS_BASE });
  const classificado = await run('Classificar Nome', { item: lote[1], refs: REFS_BASE, itemIndex: 1, binaryStore: lote });
  const preparado = await run('Preparar Conteudo', {
    item: classificado,
    refs: { ...REFS_BASE, 'Extrair Texto': { json: { text: 'Caixa 380\nDuplicatas 22.310' } } },
    itemIndex: 1, binaryStore: lote,
  });

  const q = wf.nodes.find((n) => n.name === 'Registrar Documento').parameters.options.queryReplacement;
  const params = new Function('$json', 'return (' + q.replace(/^=\{\{/, '').replace(/\}\}$/, '') + ')')(preparado.json);
  // 16 desde a 0170: o 15º é o fingerprint de prompt+modelo+esquema (0118),
  // calculado no BUILD e embutido como literal — autoriza não pagar a mesma
  // extração duas vezes. O 16º é o CNPJ lido do conteúdo (0170/0171 no banco,
  // esta fatia no n8n) — chega null quando a IA não achou um, e o banco usa
  // fn_upsert_entidade(..., p_cnpj) como identidade em vez do nome sozinho.
  assert.equal(params.length, 16);
  assert.equal(params[0], 'caso-uuid-1', 'caso_id NÃO pode chegar null — é not-null no banco');
  assert.match(params[14], /^[0-9a-f]{16}$/,
    'o fingerprint tem de ser um valor fixo e não vazio — nulo aqui desliga o dedup em silêncio');
  assert.equal(params[9], '12M25 DRE (Assinado).pdf', 'nome_original sobrevive');
  assert.equal(params[4], 'DRE', 'a classificação sobrevive');
  assert.ok(typeof params[8] === 'string' && params[8].startsWith('caso-uuid-1/'), 'arquivo_ref montado');
  assert.ok(!/undefined|null/.test(params[8]), 'arquivo_ref não pode virar o literal undefined/null');
  assert.equal(params[15], null,
    'sem chamada de conteúdo nesta corrente (só "Classificar Nome" rodou), o CNPJ chega null — '
    + 'nunca undefined, que o driver do Postgres trataria diferente');
  assert.ok(preparado.binary?.data, 'o binário sobrevive — sem ele não há chamada à IA');
});

test('Camada 2: Fatiar Extracao parte o documento grande e deixa o pequeno intacto', async () => {
  const grande = {
    json: {
      documento_versao_id: 'ver-grande', aviso_conteudo: null, celulas_no_documento: 461,
      linhas_do_texto: Array.from({ length: 461 }, (_, i) => `PAGTO ${i}  ${1000 + i},00`),
      ia_body: corpoFalso({ sistema: 'PROMPT DE SISTEMA', texto: 'Nome do arquivo: razao.pdf.' }),
    },
  };
  const pequeno = {
    json: {
      documento_versao_id: 'ver-pequeno', aviso_conteudo: null, celulas_no_documento: 30,
      linhas_do_texto: Array.from({ length: 30 }, (_, i) => `conta ${i}  ${i}`),
      ia_body: corpoFalso({ sistema: 'PROMPT DE SISTEMA', texto: 'Nome do arquivo: dre.pdf.' }),
    },
  };
  const out = await run('Fatiar Extracao', { items: [grande, pequeno] });
  const doGrande = out.filter((i) => i.json.documento_versao_id === 'ver-grande');
  const doPequeno = out.filter((i) => i.json.documento_versao_id === 'ver-pequeno');
  assert.ok(doGrande.length >= 2, 'o documento que não cabe tem de virar mais de uma chamada');
  assert.equal(doPequeno.length, 1, 'o que cabe continua sendo UMA chamada');

  // A instrução da faixa vai na mensagem de USER. O prompt de SISTEMA tem de
  // ficar idêntico em toda chamada, senão o cache de prefixo da OpenAI para de
  // valer e o fatiamento fica pagando o dobro pelo prompt (docs/CUSTO_OPENAI.md).
  for (const i of out) {
    assert.equal(sistemaDaReq(i.json.ia_body), 'PROMPT DE SISTEMA');
  }
  assert.match(textoDaReq(doGrande[0].json.ia_body), /BLOCO 1 DE/);
  assert.ok(textoDaReq(doGrande[0].json.ia_body).includes('PAGTO 0'),
    'a âncora de início é o TEXTO da linha, que o modelo consegue localizar no PDF');
  // O documento pequeno não ganha instrução nenhuma: a requisição dele fica
  // igual à de antes do fatiamento existir.
  assert.equal(textoDaReq(doPequeno[0].json.ia_body), 'Nome do arquivo: dre.pdf.');
  // E o texto do documento fica para trás — ele já virou âncora.
  assert.equal(doGrande[0].json.linhas_do_texto, undefined);
  assert.equal(doGrande[0].json.celulas_no_documento, 461, 'a régua da camada 3 segue viajando');
});

test('Camada 2: o COMPARATIVO é fatiado pelas CÉLULAS, não pelas linhas', async () => {
  // O DEFEITO QUE ISTO TRAVA. `MAX_CELULAS_POR_BLOCO` são 234 CÉLULAS (60% do teto
  // de saída ÷ 42 tokens por célula), e o nó aplicava esse número a uma contagem
  // de LINHAS. O `Extract From File` entrega o texto agrupado por linha, e uma
  // linha de comparativo de três exercícios produz TRÊS células — o corte ficava
  // 3× mais frouxo do que o nome dele diz. Medido nos 38 documentos do
  // book-canastra: NENHUM era fatiado, e o livro razão ia inteiro numa chamada
  // pedindo 101% do teto de saída.
  //
  // 180 linhas de TRÊS colunas são 540 células: cabiam pela conta de linhas
  // (180 < 234) e não cabem pela de células.
  const comparativo = {
    json: {
      documento_versao_id: 'ver-comparativo',
      linhas_do_texto: Array.from({ length: 180 },
        (_, i) => `conta ${'x'.repeat(1 + (i % 4))}  1.000  2.000  3.000`),
      ia_body: corpoFalso({ sistema: 'PROMPT DE SISTEMA', texto: 'Nome do arquivo: bp.pdf.' }),
    },
  };
  const out = await run('Fatiar Extracao', { items: [comparativo] });
  assert.ok(out.length >= 3, `540 células não cabem em 234: viraram ${out.length} bloco(s)`);
  // Todo bloco declara o MESMO total, e é o total REAL — "bloco 2 de 3" num plano
  // de 2 manda o modelo procurar um terço que não existe.
  for (const i of out) assert.equal(i.json.blocos, out.length);
  assert.match(textoDaReq(out[0].json.ia_body),
    new RegExp(`BLOCO 1 DE ${out.length}`));
  // E as faixas cobrem o documento inteiro, sem buraco.
  assert.equal(out[0].json.bloco_de, 0);
  assert.equal(out[out.length - 1].json.bloco_ate, 179);
});

test('Camada 2: documento SEM medida (escaneado) vai inteiro, nunca fatiado às cegas', async () => {
  const out = await run('Fatiar Extracao', { items: [{ json: {
    documento_versao_id: 'ver-escaneado', celulas_no_documento: null, linhas_do_texto: null,
    ia_body: corpoFalso({ sistema: 'S', texto: 'x' }),
  } }] });
  assert.equal(out.length, 1);
  assert.equal(out[0].json.blocos, 1);
  // Sem âncora, "bloco 2 de 3" seria um pedido para o modelo adivinhar onde a
  // faixa começa — e adivinhar faixa é como se perde linha em silêncio.
  assert.equal(textoDaReq(out[0].json.ia_body), 'x');
});

test('Camada 3: Juntar Blocos remonta o documento e ABRE PENDÊNCIA quando falta dado', async () => {
  const linha = (k, v) => ({ ordem: 0, chave: k, valor_num: v, valor_texto: String(v), entidade_coluna: null, periodo_coluna: null });
  const out = await run('Juntar Blocos', { items: [
    { json: { documento_versao_id: 'ver-1', bloco: 1, blocos: 2, celulas_no_documento: 461, contas_no_documento: 154,
      campos: [linha('A', 1), linha('B', 2)], diagnostico: { entidade: 'Canastra' }, falha_motivo: null,
      custo_usd: 0.03, tokens: { entrada: 10, saida: 20, cache: 5 } } },
    { json: { documento_versao_id: 'ver-1', bloco: 2, blocos: 2, celulas_no_documento: 461, contas_no_documento: 154,
      campos: [linha('B', 2), linha('C', 3)], diagnostico: { entidade: 'Canastra' }, falha_motivo: null,
      custo_usd: 0.02, tokens: { entrada: 5, saida: 10, cache: 5 } } },
    // 39 contas distintas para 39 linhas de conta: 100%, nada a dizer. Antes
    // este item tinha 104 campos contra 115 "linhas com número" — números de
    // unidades diferentes que davam 90% por coincidência.
    { json: { documento_versao_id: 'ver-2', bloco: 1, blocos: 1, celulas_no_documento: 46, contas_no_documento: 39,
      campos: Array.from({ length: 39 }, (_, i) => linha(`k${i}`, i)), diagnostico: { entidade: 'X' },
      falha_motivo: null, custo_usd: 0.05, tokens: { entrada: 1, saida: 2, cache: 0 } } },
  ] });
  assert.equal(out.length, 2, 'volta UM item por documento — daqui para a frente o grafo é o de sempre');

  const doc1 = out.find((i) => i.json.documento_versao_id === 'ver-1').json;
  // A linha repetida na emenda (o modelo repetiu a âncora) some; o resto fica.
  assert.deepEqual(doc1.campos.map((c) => c.chave), ['A', 'B', 'C']);
  assert.deepEqual(doc1.campos.map((c) => c.ordem), [0, 1, 2], 'ordem renumerada no conjunto');
  // 3 contas distintas para 154 linhas de conta — a guarda tem de falar.
  // Estes blocos NÃO trazem `linha_origem` (é o formato plano antigo, de um
  // workflow importado meses atrás): a guarda cai para contas distintas e se
  // comporta exatamente como antes da correção de unidade, em vez de medir zero.
  assert.match(doc1.falha_motivo, /Extração INCOMPLETA: 3 linha\(s\) devolvida\(s\).*154 linha\(s\)/);
  // A emenda NÃO entra em `falha_motivo` mesmo aqui, onde há um motivo real
  // (extração incompleta) ao lado dela — ela vira nota própria nos dois casos,
  // com ou sem motivo real (ver o teste do lote 7377 abaixo).
  assert.doesNotMatch(doc1.falha_motivo, /emenda/);
  assert.equal(doc1.emendas_limpas, 1);
  assert.match(doc1.nota_emenda, /repetida\(s\) na emenda/);
  assert.equal(doc1.cobertura, 0.019, '3 de 154, na unidade de CONTAS');
  assert.equal(doc1.contas_distintas, 3);
  // O custo dos blocos SOMA: um documento fatiado custou o que os pedaços dele
  // custaram, e o `Resumo de Custo` lê daqui.
  assert.equal(doc1.custo_usd, 0.05);
  assert.deepEqual(doc1.tokens, { entrada: 15, saida: 30, cache: 10 });

  // 39 de 39 é documento completo: nada de pendência. Uma guarda que grita em
  // toda extração é uma guarda que ninguém lê.
  const doc2 = out.find((i) => i.json.documento_versao_id === 'ver-2').json;
  assert.equal(doc2.falha_motivo, null);
  assert.equal(doc2.campos.length, 39);
  assert.equal(doc2.cobertura, 1);
  // Nenhuma emenda agiu neste documento — a contagem e a nota dizem isso, em
  // vez de simplesmente não aparecerem (regra 1: ausência não é dado).
  assert.equal(doc2.emendas_limpas, 0);
  assert.equal(doc2.nota_emenda, null);
});

// A GUARDA DE COBERTURA IGNORAVA `tem_dado_financeiro=false` — achado na
// rodada real do "AMO teste 00" (17/09/2026). A migration 0111 já resolveu
// exatamente este problema para o Sinal 3 ("veio vazia"): "documento sem
// valor monetário por natureza (certidão, organograma, parecer de auditoria)
// não é falha de extração". Mas essa proteção só chegou ao lado SQL
// (fn_registrar_campos_extraidos, Sinal 3). O sinal de COBERTURA PARCIAL
// (`avaliarCobertura`, aqui em `Juntar Blocos`) é um código diferente, escrito
// depois, e nunca foi ligado à mesma bandeira.
//
// MEDIDO em produção: 4 documentos desta rodada — 3 certidões da JUCESP e 1
// planilha de controle de extratos — vieram com `tem_dado_financeiro=false`
// (a IA correta, dizendo que o documento não tem valor financeiro) e MESMO
// ASSIM abriram `extracao_falhou` por cobertura, porque a régua de texto
// conta datas, CNPJs e percentuais como "linha de conta" sem saber que o
// documento é, por natureza, sem número financeiro.
test('Camada 3: tem_dado_financeiro=false também cala a guarda de COBERTURA PARCIAL, não só a de "veio vazia"', async () => {
  const linha = (k, v) => ({ ordem: 0, chave: k, valor_num: v, valor_texto: String(v), entidade_coluna: null, periodo_coluna: null });
  const out = await run('Juntar Blocos', { items: [
    // Espelha a Certidão de inteiro teor da JUCESP real: 0 campos financeiros
    // (não há valor monetário no documento), mas a régua de texto conta 30
    // "linhas de conta" (datas de registro, números de processo, percentuais
    // de participação societária) — sem a guarda, isso abre falha_motivo.
    { json: {
      documento_versao_id: 'ver-certidao', bloco: 1, blocos: 1, celulas_no_documento: 30, contas_no_documento: 30,
      campos: [], diagnostico: { entidade: 'Amobeleza', tem_dado_financeiro: false }, falha_motivo: null,
      custo_usd: 0.01, tokens: { entrada: 5, saida: 5, cache: 0 },
    } },
    // Contraprova no MESMO teste: um documento comum (tem_dado_financeiro
    // ausente, o caso de sempre) com a MESMA cobertura baixa continua abrindo
    // a pendência — a guarda não pode desligar sozinha para todo mundo.
    { json: {
      documento_versao_id: 'ver-balanco-comum', bloco: 1, blocos: 1, celulas_no_documento: 30, contas_no_documento: 30,
      campos: [], diagnostico: { entidade: 'Amobeleza' }, falha_motivo: null,
      custo_usd: 0.01, tokens: { entrada: 5, saida: 5, cache: 0 },
    } },
  ] });

  const certidao = out.find((i) => i.json.documento_versao_id === 'ver-certidao').json;
  assert.equal(certidao.falha_motivo, null,
    'documento sem dado financeiro por natureza não pode abrir extracao_falhou por cobertura');

  const comum = out.find((i) => i.json.documento_versao_id === 'ver-balanco-comum').json;
  assert.match(comum.falha_motivo, /Extração INCOMPLETA/,
    'sem o sinal explícito tem_dado_financeiro=false, a guarda continua falando — regra 1, ausência não é dado');
});

// A PRIMEIRA VERSÃO DESTA CORREÇÃO (378f23a) CALAVA A GUARDA PARA QUALQUER
// tem_dado_financeiro=false, SEM EXIGIR "nada foi extraído" — ao contrário da
// própria 0111, que só se cala quando `v_count = 0`. Achado na revisão
// multilente do PR #234 (17/09/2026): documento com 30 contas esperadas, o
// modelo devolve 5 linhas COM valor monetário e MESMO ASSIM marca
// tem_dado_financeiro=false (documento misto, ou erro do modelo) — a versão
// anterior silenciava a cobertura e gravava os 5 campos sem pendência
// nenhuma, PIOR que o defeito original (antes abria "Extração INCOMPLETA: 5
// de 30"). `semDadoExtraido` (linhasDevolvidas===0) reproduz a condição
// `v_count = 0` da 0111 no lado JS.
test('Camada 3: tem_dado_financeiro=false só cala a guarda de cobertura quando NADA foi extraído, igual à 0111', async () => {
  const linha = (k, v) => ({ ordem: 0, chave: k, valor_num: v, valor_texto: String(v), entidade_coluna: null, periodo_coluna: null });
  const out = await run('Juntar Blocos', { items: [
    { json: {
      documento_versao_id: 'ver-misto', bloco: 1, blocos: 1, celulas_no_documento: 30, contas_no_documento: 30,
      campos: [linha('a', 1), linha('b', 2), linha('c', 3), linha('d', 4), linha('e', 5)],
      diagnostico: { entidade: 'Amobeleza', tem_dado_financeiro: false }, falha_motivo: null,
      custo_usd: 0.01, tokens: { entrada: 5, saida: 5, cache: 0 },
    } },
  ] });

  const misto = out.find((i) => i.json.documento_versao_id === 'ver-misto').json;
  assert.match(misto.falha_motivo, /Extração INCOMPLETA/,
    'tem_dado_financeiro=false não pode calar a cobertura quando o documento devolveu linhas com valor — a guarda existe exatamente para este caso, e calar aqui perde dado em silêncio');
});

test('Camada 3: emenda limpa SOZINHA não é falha — lote 7377, "teste Canastra" (02/09)', async () => {
  // A rodada real: 17_Livro_Razao_Fornecedores_Canastra_Industria_12M25.pdf foi
  // lido INTEIRO em 2 blocos (302 pares conta×coluna, 95 contas distintas,
  // cobertura do lote 0,987). A ÚNICA coisa que aconteceu na costura foi 3
  // linhas repetidas na âncora entre os blocos, descartadas — exatamente o que
  // a emenda existe para fazer. Antes desta correção isso sozinho virava
  // `falha_motivo` não-nulo, contava em `documentos_com_falha` do lote e abria
  // `extracao_falhou` — a ÚNICA "falha" do lote era, na verdade, sucesso.
  {
    const linha = (k, v) => ({
      ordem: 0, chave: k, valor_num: v, valor_texto: String(v), entidade_coluna: null, periodo_coluna: null,
    });
    // 2 blocos de 50 linhas cada, com 3 linhas de emenda repetidas no início
    // do bloco 2 (a cauda do bloco 1): 100 linhas no documento, 97 pares únicos.
    const bloco1 = Array.from({ length: 50 }, (_, i) => ({ ...linha(`CONTA ${i}`, i), linha_origem: i }));
    const cauda = bloco1.slice(-3).map((c, i) => ({ ...linha(c.chave, c.valor_num), linha_origem: i }));
    const restoBloco2 = Array.from({ length: 47 }, (_, i) => ({ ...linha(`CONTA ${50 + i}`, 50 + i), linha_origem: 3 + i }));
    const out = await run('Juntar Blocos', { items: [
      { json: {
        documento_versao_id: 'ver-7377', bloco: 1, blocos: 2, celulas_no_documento: 300, contas_no_documento: 97,
        campos: bloco1, diagnostico: { entidade: 'Canastra Industria' }, falha_motivo: null,
        custo_usd: 0.05, tokens: { entrada: 10, saida: 20, cache: 0 },
      } },
      { json: {
        documento_versao_id: 'ver-7377', bloco: 2, blocos: 2, celulas_no_documento: 300, contas_no_documento: 97,
        campos: [...cauda, ...restoBloco2], diagnostico: { entidade: 'Canastra Industria' }, falha_motivo: null,
        custo_usd: 0.04, tokens: { entrada: 8, saida: 15, cache: 0 },
      } },
    ] });
    const doc = out.find((i) => i.json.documento_versao_id === 'ver-7377').json;
    assert.equal(doc.campos.length, 97, 'as 3 repetidas da emenda saem; as 97 reais ficam');
    // O COMPORTAMENTO QUE ESTE TESTE PROTEGE: emenda limpa sozinha, sem nenhum
    // outro problema, NÃO produz `falha_motivo` — nem `documentos_com_falha`
    // nem `extracao_falhou` devem nascer de uma costura que funcionou.
    assert.equal(doc.falha_motivo, null, 'com_falha=1 sobre zero problema real era o próprio defeito');
    // E a informação não desaparece: ela muda de endereço, não de existência.
    assert.equal(doc.emendas_limpas, 3);
    assert.match(doc.nota_emenda, /3 linha\(s\) repetida\(s\) na emenda entre blocos foram descartadas/);

    // O MESMO documento, mas agora com um motivo REAL ao lado (cobertura abaixo
    // do limiar): `falha_motivo` tem de existir e trazer o motivo real — a
    // emenda continua virando nota, nunca falha_motivo, mas o problema
    // verdadeiro não pode ficar mudo por causa dela.
    const outIncompleto = await run('Juntar Blocos', { items: [
      { json: {
        documento_versao_id: 'ver-7377b', bloco: 1, blocos: 2, celulas_no_documento: 300, contas_no_documento: 970,
        campos: bloco1, diagnostico: { entidade: 'Canastra Industria' }, falha_motivo: null,
        custo_usd: 0.05, tokens: { entrada: 10, saida: 20, cache: 0 },
      } },
      { json: {
        documento_versao_id: 'ver-7377b', bloco: 2, blocos: 2, celulas_no_documento: 300, contas_no_documento: 970,
        campos: [...cauda, ...restoBloco2], diagnostico: { entidade: 'Canastra Industria' }, falha_motivo: null,
        custo_usd: 0.04, tokens: { entrada: 8, saida: 15, cache: 0 },
      } },
    ] });
    const docIncompleto = outIncompleto.find((i) => i.json.documento_versao_id === 'ver-7377b').json;
    assert.match(docIncompleto.falha_motivo, /Extração INCOMPLETA/, 'o motivo real continua produzindo falha_motivo');
    assert.doesNotMatch(docIncompleto.falha_motivo, /emenda/, 'a emenda nunca entra em falha_motivo, mesmo ao lado de um motivo real');
    assert.equal(docIncompleto.emendas_limpas, 3);
    assert.match(docIncompleto.nota_emenda, /3 linha\(s\) repetida\(s\) na emenda entre blocos foram descartadas/);
  }
});

test('Camada 3: o livro razão PERFEITO não vira pendência — a unidade é linha, não conta distinta', async () => {
  // O caso medido no book: 99 lançamentos, 66 históricos distintos (o mesmo
  // fornecedor pago várias vezes). Com a régua vendo 100 linhas, a contagem por
  // conta distinta dava 66% e abria pendência numa extração que não perdeu nada.
  // Aqui o documento é o mesmo em miniatura: 24 lançamentos, 8 históricos.
  const campos = Array.from({ length: 24 }, (_, i) => ({
    linha_origem: i,
    ordem: i,
    chave: `PAGTO FORNECEDOR ${i % 8}`,   // 8 históricos distintos em 24 lançamentos
    valor_num: 100 + i,
    valor_texto: String(100 + i),
    entidade_coluna: null,
    periodo_coluna: null,
  }));
  const out = await run('Juntar Blocos', { items: [
    { json: { documento_versao_id: 'razao-1', bloco: 1, blocos: 1, celulas_no_documento: 30, contas_no_documento: 24,
      campos, diagnostico: { entidade: 'Canastra' }, falha_motivo: null,
      custo_usd: 0.04, tokens: { entrada: 10, saida: 20, cache: 0 } } },
  ] });
  const doc = out[0].json;
  assert.equal(doc.linhas_devolvidas, 24, 'as 24 linhas do documento');
  assert.equal(doc.contas_distintas, 8, 'e apenas 8 históricos distintos');
  assert.equal(doc.cobertura, 1, '24 de 24 é extração completa');
  assert.equal(doc.falha_motivo, null, 'extração perfeita NÃO pode virar pendência');
  // E o campo de contagem não vaza para o banco: `campo_extraido` recebe o que
  // sempre recebeu.
  assert.equal(Object.hasOwn(doc.campos[0], 'linha_origem'), false);
});

test('Camada 3: sem régua (escaneado) a guarda se CALA, em vez de absolver ou acusar', async () => {
  const out = await run('Juntar Blocos', { items: [{ json: {
    documento_versao_id: 'ver-3', bloco: 1, blocos: 1, celulas_no_documento: null,
    campos: [{ ordem: 0, chave: 'A' }], diagnostico: {}, falha_motivo: null,
  } }] });
  assert.equal(out[0].json.falha_motivo, null);
  assert.equal(out[0].json.cobertura, null);
});

// ---------------------------------------------------------------------------
// O DEFEITO DA EXECUÇÃO 6164 — fan-out quebra o pareamento de itens do n8n
// ---------------------------------------------------------------------------
//
// Um nó que muda a QUANTIDADE de itens (1 documento → N blocos → 1 documento)
// corta a cadeia de `pairedItem`, e TODA expressão `$('Outro Nó').item` rio
// abaixo passa a devolver undefined. Em produção isso apareceu como:
//   • `Registrar Diagnostico` e `Reconciliar`: "Query Parameters must be a
//     string of comma-separated values or an array of values" (a expressão
//     inteira virou `undefined`);
//   • `Gravar Campos`: `invalid input syntax for type uuid: "sem-versao-0"` —
//     o `Juntar Blocos` FABRICAVA uma chave quando o id faltava, e o texto
//     inventado foi direto para um parâmetro `::uuid`.
//
// Os dois testes abaixo travam as duas metades da correção.

test('6164: os nós de fan-out declaram pairedItem — sem isso o grafo inteiro perde o contexto', async () => {
  const doc = (id, celulas) => ({ json: {
    documento_id: 'doc-' + id, documento_versao_id: 'ver-' + id, celulas_no_documento: celulas,
    linhas_do_texto: Array.from({ length: celulas }, (_, i) => `linha ${i}  ${i},00`),
    ia_body: corpoFalso({ sistema: 'S', texto: 'x' }),
  } });
  const fatiado = await run('Fatiar Extracao', { items: [doc(1, 500), doc(2, 10)] });
  assert.ok(fatiado.length > 2, 'o documento grande virou mais de um bloco');
  for (const it of fatiado) {
    assert.ok(it.pairedItem && Number.isInteger(it.pairedItem.item),
      'todo bloco tem de apontar para o item de entrada que o gerou');
  }
  // Os blocos do documento 1 apontam para a entrada 0; o do documento 2, para a 1.
  const doDoc2 = fatiado.filter((i) => i.json.documento_versao_id === 'ver-2');
  assert.equal(doDoc2.length, 1);
  assert.equal(doDoc2[0].pairedItem.item, 1);

  const juntado = await run('Juntar Blocos', { items: fatiado.map((i) => ({ json: {
    ...i.json, campos: [{ ordem: 0, chave: 'A', valor_num: 1 }], diagnostico: {}, falha_motivo: null,
  } })) });
  for (const it of juntado) {
    assert.ok(it.pairedItem && Number.isInteger(it.pairedItem.item),
      'o documento remontado tem de apontar para um dos blocos que o formaram');
  }
});

test('6164: id ausente vira FALHA declarada, nunca um uuid inventado', async () => {
  // `'sem-versao-0'` foi direto para `fn_registrar_campos_extraidos($1::uuid)`.
  // Um id que não existe é uma falha a declarar — inventar um texto no formato
  // errado transforma "não sei onde gravar" em erro de banco três nós à frente.
  const out = await run('Juntar Blocos', { items: [{ json: {
    documento_versao_id: undefined, bloco: 1, blocos: 1, celulas_no_documento: null,
    campos: [{ ordem: 0, chave: 'A' }], diagnostico: {}, falha_motivo: null,
  } }] });
  assert.equal(out.length, 1);
  assert.equal(out[0].json.documento_versao_id, null, 'null, nunca uma string inventada');
  assert.match(out[0].json.falha_motivo, /SEM documento_versao_id/);
});

test('6164: os nós Postgres depois do fatiamento leem do PRÓPRIO item', () => {
  // Nenhum deles pode depender de `$('...').item`: através do fan-out essa
  // resolução não existe mais, e o sintoma é "undefined" em Query Parameters.
  for (const nome of ['Gravar Campos (Sombra)', 'Registrar Diagnostico', 'Reconciliar (Classe A)']) {
    const q = wf.nodes.find((n) => n.name === nome).parameters.options.queryReplacement;
    assert.ok(!/\$\('[^']+'\)\.item/.test(q),
      `${nome} ainda lê outro nó por .item — isso quebra depois do fatiamento: ${q}`);
    assert.match(q, /\$json\./, `${nome} tem de ler do próprio item`);
  }
  // E o item que chega até eles carrega os dois ids, que é o que torna isso
  // possível: `Montar Req Extracao` passou a levar o `documento_id` junto.
  assert.match(code('Montar Req Extracao'), /documento_id:docId/);
});

test('Topologia das três camadas: fan-out e volta, com o resto do grafo intacto', () => {
  assert.deepEqual(wf.connections['Montar Req Extracao'].main[0].map((c) => c.node), ['Fatiar Extracao']);
  assert.deepEqual(wf.connections['Fatiar Extracao'].main[0].map((c) => c.node), ['IA Extrair']);
  // O Parse não vai mais direto ao Juntar Blocos: passa pelos estágios de repetição
  // e TODOS os caminhos convergem num Merge que alimenta o Juntar UMA vez.
  assert.deepEqual(wf.connections['Parse Extracao'].main[0].map((c) => c.node), ['Repetir Extracao 1?']);
  assert.deepEqual(wf.connections['Juntar Tentativas'].main[0].map((c) => c.node), ['Juntar Blocos']);
  // O ponto do desenho: de `Gravar Campos` em diante nada muda. O contrato do
  // banco (um item por documento, com `campos` e `falha_motivo`) é o mesmo.
  assert.deepEqual(wf.connections['Juntar Blocos'].main[0].map((c) => c.node), ['Gravar Campos (Sombra)']);
  const gravar = wf.nodes.find((n) => n.name === 'Gravar Campos (Sombra)');
  assert.match(gravar.parameters.options.queryReplacement, /\$json\.documento_versao_id/);
  assert.match(gravar.parameters.options.queryReplacement, /\$json\.falha_motivo/);
});

// --- Anti-drift: todo nó Code declara o que faz quando UM item falha ----------
// O invariante antigo ("Nós Postgres têm onError+retry") tem lista de nomes
// hardcoded, e foi por isso que os 7 nós Code passaram anos sem `onError` sem
// ninguém notar. Aqui a regra é por EXCLUSÃO: todo nó Code precisa continuar o
// lote, salvo os que estão na lista de aborto deliberado — e cada exclusão carrega
// o motivo, para a próxima pessoa não "consertar" um throw que existe de propósito.
const CODE_QUE_DEVE_ABORTAR = {
  // Formulário sem arquivo: não há lote para continuar.
  'Listar Arquivos': 'lote vazio',
  // O orçamento não LANÇA mais a recusa (ela virou marca, para o ramo do IF
  // poder gravá-la no banco antes de a execução morrer) — mas continua sem
  // `onError`, e por um motivo diferente do de antes: se ESTE nó falhar por um
  // bug, continuar significa seguir para as chamadas da OpenAI sem nenhuma
  // decisão de orçamento tomada. Um teto que se desliga sozinho quando quebra
  // não é teto.
  'Orcamento do Lote': 'falha aqui = lote sem decisão de orçamento',
  // E o aborto do lote recusado, que é onde a exceção passou a morar.
  'Abortar Lote': 'orçamento excedido',
  // (A autorização do envio deixou de ser Code: é Postgres `fn_conferir_envio`, fail closed por não ter
  // `onError` — provado em assinatura-do-envio.test.mjs.)
  // Roteamento por formato: se ele falhar, `continueRegularOutput` devolveria
  // o LOTE INTEIRO sem reagrupar as linhas de planilha que ele existe para
  // juntar — o MESMO fan-out (N itens por documento) que o roteamento inteiro
  // existe para evitar, só que via falha silenciosa em vez de fio solto no
  // editor.
  'Recompor Conteudo Extraido': 'falha aqui = linhas de planilha voltam soltas, sem reagrupar',
  // Mesma razao do Recompor: continuar devolveria as 150 mil linhas soltas ao Merge,
  // que e' exatamente o que estoura a pilha (17/09/2026).
  'Agrupar Linhas XLSX': 'falha aqui = linhas soltas chegam ao Merge e estouram a pilha',
  'Agrupar Linhas XLS': 'falha aqui = linhas soltas chegam ao Merge e estouram a pilha',
};

test('todo nó Code continua o lote quando um item falha (exceto os que devem abortar)', () => {
  for (const n of wf.nodes.filter((x) => x.type === 'n8n-nodes-base.code')) {
    if (n.name in CODE_QUE_DEVE_ABORTAR) {
      assert.equal(n.onError, undefined,
        `${n.name} tem de ABORTAR (${CODE_QUE_DEVE_ABORTAR[n.name]}) — onError aqui é um bug`);
    } else {
      assert.equal(n.onError, 'continueRegularOutput',
        `${n.name}: sem onError, um item ruim mata a execução e os itens da fila somem sem rastro`);
    }
  }
});

// O caso concreto que motivou tudo: `Preparar Conteudo` lê o binário e é o nó com
// mais formas de falhar por arquivo individual.
test('Preparar Conteudo não derruba o lote — é o nó que toca o binário', () => {
  const n = wf.nodes.find((x) => x.name === 'Preparar Conteudo');
  assert.equal(n.onError, 'continueRegularOutput');
});

// --- Anti-drift: a escala do nó É a de lib/extract.mjs ------------------------
// QUINTO mirror. Este ficou de fora quando os outros passaram a ser embutidos, e
// JÁ HAVIA DIVERGIDO: a cópia à mão perdeu a cláusula final de `normalizarUnidade`
// (célula que é exatamente o multiplicador: '1.000' / '1000' / '1').
test('Parse Extracao carrega o MESMO normalizarUnidade de lib/extract.mjs', () => {
  assert.ok(code('Parse Extracao').includes(normalizarUnidade.toString()),
    'a normalização de escala embutida divergiu da fonte em lib/extract.mjs');
});

test('a escala do nó concorda com a lib nos casos que ANTES divergiam', async () => {
  // Rodando o normUnid REAL extraído do JSON gerado, não a lib.
  // A fonte embutida é MULTI-LINHA (é o `toString()` da função formatada da lib),
  // então recorta-se pela própria fonte, não por fim de linha.
  const src = code('Parse Extracao');
  const decl = `const normUnid = ${normalizarUnidade.toString()};`;
  assert.ok(src.includes(decl), 'a declaração embutida não é a da lib');
  const normUnidDoNo = await new AsyncFunction(`${decl} return normUnid;`)();

  // Os três casos da divergência medida. Escala nula NÃO é neutra: fn_valor_em_base
  // (0023:127) multiplica por coalesce(fator, 1), então "não sei" é tratado como
  // UNIDADE — e comparar milhar com unidade erra por 1000x.
  for (const [bruto, esperado] of [['1.000', 'milhar'], ['1000', 'milhar'], ['1', 'unidade']]) {
    assert.equal(normUnidDoNo(bruto), esperado, `nó: escala de ${JSON.stringify(bruto)}`);
    assert.equal(normalizarUnidade(bruto), esperado, `lib: escala de ${JSON.stringify(bruto)}`);
  }
  // E segue concordando no que já funcionava.
  for (const bruto of ['R$ mil', 'milhares de reais', 'em milhões', 'reais', 'Em R$ 1.000', null, '']) {
    assert.equal(normUnidDoNo(bruto), normalizarUnidade(bruto), `nó × lib para ${JSON.stringify(bruto)}`);
  }
});

// --- Hash do conteúdo: a idempotência da 0026 recebe dado de verdade ----------
// A 0026 casa reenvio por (caso_id, hash) para virar VERSÃO nova em vez de
// documento novo. O pipeline mandava `null` no 12º parâmetro, então
// `p_hash is not null` nunca era verdade e todo reenvio duplicava o documento —
// o "15 colunas para 5 empresas" do teste v27. reextracao.test.sql provava a
// função passando o hash à mão; o gap era do pipeline, e invisível.
test('Registrar Documento passa o hash, não o literal null', () => {
  const q = wf.nodes.find((x) => x.name === 'Registrar Documento').parameters.options.queryReplacement;
  assert.match(q, /\$json\.hash/, 'o 12º parâmetro tem de ser o hash do conteúdo');
  assert.ok(!/assinado, null,/.test(q), 'o literal null que matava a idempotência da 0026 saiu');
});

test('Preparar Conteudo calcula SHA-256 do conteúdo e se abstém se não puder', async () => {
  const conteudo = Buffer.from('%PDF-1.4 conteudo de teste');
  const item = {
    json: { caso_id: 'c-1', nome_original: 'BP.pdf' },
    binary: { data: { fileName: 'BP.pdf', mimeType: 'application/pdf', data: conteudo.toString('base64') } },
  };
  const out = await run('Preparar Conteudo', { item });
  const esperado = createHash('sha256').update(conteudo).digest('hex');
  assert.equal(out.json.hash, esperado, 'hash do CONTEÚDO, não do nome');

  // Mesmo conteúdo com nome diferente → MESMO hash (é o que faz reenvio virar
  // versão em vez de documento novo, mesmo que o dono renomeie o arquivo).
  const outro = await run('Preparar Conteudo', {
    item: { ...item, json: { ...item.json, nome_original: 'BP_v2.pdf' } },
  });
  assert.equal(outro.json.hash, esperado);

  // Conteúdo diferente → hash diferente. Sem isto o "hash" fundiria documentos
  // distintos, que a 0026 chama de o erro mais caro possível.
  const diff = await run('Preparar Conteudo', {
    item: { ...item, binary: { data: { ...item.binary.data, data: Buffer.from('outro').toString('base64') } } },
  });
  assert.notEqual(diff.json.hash, esperado);
});

// O invariante que FALTAVA — e a ausência dele custou uma rodada inteira de
// produção. O teste acima passa verde no Node local, onde `crypto.subtle`
// existe; o sandbox do n8n do dono NÃO o expõe, e lá o campo vinha null. Um
// teste que só exercita o caminho feliz do ambiente de desenvolvimento não diz
// nada sobre o ambiente que roda de verdade.
//
// Aqui o hash tem de sair CERTO — não "não-nulo": um hash errado é pior que
// hash nenhum, porque a 0026 fundiria documentos diferentes numa versão só.
test('Preparar Conteudo calcula o MESMO SHA-256 quando o sandbox não expõe crypto', async () => {
  const conteudo = Buffer.from('%PDF-1.4 conteudo de teste');
  const esperado = createHash('sha256').update(conteudo).digest('hex');
  const item = {
    json: { caso_id: 'c-1', nome_original: 'BP.pdf' },
    binary: { data: { fileName: 'BP.pdf', mimeType: 'application/pdf', data: conteudo.toString('base64') } },
  };

  const out = await run('Preparar Conteudo', { item, semCrypto: true });
  assert.equal(out.json.hash, esperado, 'sem crypto no sandbox, o SHA-256 em JS puro tem de dar o mesmo hexadecimal');

  // Os dois caminhos (nativo e JS puro) concordando é o que autoriza manter o
  // atalho nativo por velocidade sem virar duas verdades.
  const nativo = await run('Preparar Conteudo', { item });
  assert.equal(nativo.json.hash, out.json.hash, 'caminho nativo × JS puro não podem divergir');

  // E continua DISCRIMINANDO conteúdo sem o crypto: se o fallback devolvesse
  // constante, os dois asserts acima ainda passariam com um hash fixo.
  const diff = await run('Preparar Conteudo', {
    item: { ...item, binary: { data: { ...item.binary.data, data: Buffer.from('outro').toString('base64') } } },
    semCrypto: true,
  });
  assert.equal(diff.json.hash, createHash('sha256').update(Buffer.from('outro')).digest('hex'));
});

// --- Não pagar extração de documento que não existe --------------------------
// Com `onError: continueRegularOutput` nos nós Postgres, uma falha em
// `Registrar Documento` empurra o item de erro adiante. Antes, `versaoId` virava
// null em silêncio, a extração era EXECUTADA (dinheiro gasto) e
// `fn_registrar_campos_extraidos(null, …)` retornava 0 descartando o
// `falha_motivo`. A 0029 fecha o lado do banco; esta guarda fecha o do dinheiro.
test('Montar Req Extracao recusa montar requisição sem documento_versao_id', async () => {
  const conteudo = { type: 'text', text: 'x' };
  // Item de erro típico do que o nó Postgres empurra quando falha: o
  // `Recompor Contexto` o repassa com os ids nulos, e a guarda pega aqui.
  await assert.rejects(
    () => run('Montar Req Extracao', {
      item: { json: { nome_original: 'BP.pdf', content_part: conteudo, documento_versao_id: null } },
    }),
    (e) => {
      assert.match(e.message, /a extracao NAO foi chamada/, 'a mensagem tem de dizer que não gastou');
      assert.match(e.message, /Registrar Documento/, 'e apontar a causa provável');
      return true;
    },
  );
  // E com versão presente, segue montando normalmente.
  const ok = await run('Montar Req Extracao', {
    item: { json: { nome_original: 'BP.pdf', tipo_taxonomia: 'BALANCO', content_part: conteudo, documento_versao_id: 'ver-1' } },
  });
  assert.equal(ok.json.documento_versao_id, 'ver-1');
  assert.equal(partesDaReq(ok.json.ia_body).length, 2, 'a dica do nome e o conteúdo');
});

// A OUTRA metade da guarda, e a que o Teste V45 pagou: sem o arquivo, a chamada
// volta "sem nenhuma linha" SEM erro de API — extração vazia que passa por
// sucesso. Recusar montar é o que transforma esse silêncio em motivo escrito.
test('Montar Req Extracao recusa montar requisição SEM O ARQUIVO (content_part ausente)', async () => {
  await assert.rejects(
    () => run('Montar Req Extracao', {
      item: { json: { nome_original: 'BP.pdf', documento_versao_id: 'ver-1' } },
    }),
    (e) => {
      assert.match(e.message, /content_part ausente/);
      assert.match(e.message, /NAO foi feita/, 'e diz que não pagou pela chamada');
      return true;
    },
  );
});

// Desalinhamento de contagem no `Recompor Contexto`: associar o PDF de um
// documento ao id de outro é pior que falhar, então ele DECLARA em vez de adivinhar.
test('Recompor Contexto declara desalinhamento em vez de associar arquivo errado', async () => {
  const regs = [
    { json: { r: { documento_id: 'doc-1', documento_versao_id: 'ver-1' } } },
    { json: { r: { documento_id: 'doc-2', documento_versao_id: 'ver-2' } } },
  ];
  // O Juntar Ramos devolveu UM item só — as listas não correspondem mais.
  const out = await run('Recompor Contexto', {
    items: regs,
    refs: { 'Juntar Ramos': { json: { nome_original: 'A.pdf', content_part: { type: 'text', text: 'a' } } } },
  });
  assert.equal(out.length, 2, 'nenhum item é descartado — cada um sai com o motivo');
  for (const it of out) {
    assert.match(it.json.recompor_motivo, /correspondencia por indice deixou de ser verdadeira/);
    assert.equal(it.json.content_part, undefined, 'e NENHUM conteúdo é associado por palpite');
  }
  // Os ids continuam vindo do Postgres: eles são do próprio item, não pareados.
  assert.equal(out[0].json.documento_versao_id, 'ver-1');
  assert.equal(out[1].json.documento_versao_id, 'ver-2');
});

test('a estimativa que o PORTAL mostra é coerente com a cadência REAL do workflow', () => {
  // O DEFEITO QUE ISTO FECHA, achado com o dono olhando a tela em 24/08/2026: o
  // portal dizia "cerca de 29 minutos" para um lote de 38 documentos que leva
  // ~8. O número (45s por documento) vinha dos ~33s da cadência do gpt-4o, e a
  // troca de provedor derrubou a cadência para 8s sem que nada avisasse.
  //
  // Não quebrou coisa nenhuma — e é por isso que sobreviveria: uma estimativa
  // não tem quem a desminta. O analista espera um trabalho que já acabou, ou
  // desiste de acompanhar.
  //
  // O portal é TypeScript e não importa `N8N/lib/*.mjs`; a fronteira de build
  // não permite. Então o espelho é por TESTE, como as 26 funções do
  // `espelho-inline.test.mjs` — lê a constante do fonte do portal e confronta
  // com o `batchInterval` que o gerador REALMENTE escreveu no nó.
  const fonte = readFileSync(new URL('../../portal/src/lib/espera-do-lote.ts', import.meta.url), 'utf8');
  const m = /const SEGUNDOS_POR_DOCUMENTO = (\d+);/.exec(fonte);
  assert.ok(m, 'SEGUNDOS_POR_DOCUMENTO sumiu do portal — o espelho perdeu o outro lado');
  const segundosPorDocumento = Number(m[1]);

  const cadenciaS = byName['IA Extrair'].parameters.options.batching.batch.batchInterval / 1000;

  // PISO: um documento nunca custa menos que UMA chamada de extração. Abaixo
  // disso a tela promete um tempo que a cadência não consegue cumprir, e o
  // analista fecha a página achando que travou.
  assert.ok(segundosPorDocumento >= cadenciaS,
    `a tela promete ${segundosPorDocumento}s por documento, e uma chamada sozinha já leva ${cadenciaS}s`);

  // TETO: um documento faz, no pior caso realista, uma classificação por
  // conteúdo mais alguns blocos de extração — quatro chamadas cobrem isso —,
  // MAIS o preparo, que não é chamada nenhuma.
  //
  // O TETO ERA `cadenciaS * 4` PURO, E ISSO ESTAVA ERRADO POR ESTRUTURA — medido
  // em 16/09/2026. Parte do custo de um documento NÃO escala com a cadência:
  // `PREPARO_POR_ARQUIVO_S` (upload ao Storage, leitura do texto, medição) é
  // ADITIVO e fixo. Com a cadência em 73s ele sumia no ruído; com ela em 6s ele
  // é um quinto do total, e a razão medida contra a cadência subiu para 4,2x
  // (rodada #7851: 49 documentos em 1237s = 25,2s por documento, contra 6s de
  // cadência). Um teto que multiplica só a cadência declara defeituosa uma
  // estimativa que está CERTA — e força a tela a mentir para o rápido, que é
  // o defeito que este arquivo inteiro existe para impedir.
  //
  // Somar o termo aditivo em vez de inflar o multiplicador mantém o teto
  // apertado onde ele importa: o defeito histórico que este assert pegou (45s
  // de estimativa contra 8s de cadência, 24/08) continua reprovando, porque
  // 8*4+5 = 37 < 45.
  const mPreparo = /const PREPARO_POR_ARQUIVO_S = (\d+);/.exec(fonte);
  assert.ok(mPreparo, 'PREPARO_POR_ARQUIVO_S sumiu do portal — o teto perdeu o termo aditivo');
  const preparoS = Number(mPreparo[1]);

  assert.ok(segundosPorDocumento <= cadenciaS * 4 + preparoS,
    `a tela promete ${segundosPorDocumento}s por documento contra uma cadência de ${cadenciaS}s `
    + `mais ${preparoS}s de preparo — a estimativa ficou para trás de uma mudança de cadência`);
});

// O LOTE DE 190 DOCUMENTOS — a espera da tela contra a BARREIRA do merge.
//
// Achado ao preparar o teste do `book-araucaria` (190 documentos), medindo em
// vez de supor: até o primeiro `Registrar Documento` o workflow passa por
// `Upload Storage` -> `Extrair Texto` -> `Medir Documento` -> `Orcamento do
// Lote` -> `IA Classificar` -> `Juntar Ramos`, e o merge (`mode: append`) é uma
// BARREIRA — nenhum documento é registrado enquanto a ÚLTIMA classificação não
// voltar, uma a cada `batchInterval`. A tela media esse silêncio contra um
// limite de 8 minutos FIXOS, calibrado no lote de 38.
//
// No pior caso (nenhum nome de arquivo resolvendo tipo+período) 190 documentos
// silenciam 190 x 8s = 25 min, e mesmo na proporção medida do `book-canastra`
// (19 de 38) são ~13 min. Os dois passam de 8, e o efeito não é cosmético: a
// tela declara "o processamento parou" sobre um lote vivo e o analista reenvia
// um lote que está rodando — pagando a IA duas vezes.
//
// ESTE TESTE GUARDA O LADO DO WORKFLOW: a cadência que a tela supõe é a que o
// nó realmente tem, e o merge continua sendo barreira. O lado da CONTA —
// `semPrimeiroSinalMs` e `janelaPara` cobrindo o lote de 190 — é chamado de
// verdade, como função, em `portal/scripts/verificar-mensagem-de-falha.mts`;
// refazer a fórmula aqui seria o espelho sem guarda que esta sessão desfez.
test('a tela supõe a cadência REAL da classificação, e o merge continua sendo barreira', () => {
  const fonte = readFileSync(new URL('../../portal/src/lib/espera-do-lote.ts', import.meta.url), 'utf8');
  const m = /const CADENCIA_IA_S = (\d+);/.exec(fonte);
  assert.ok(m, 'CADENCIA_IA_S sumiu do portal — o espelho perdeu o outro lado');

  const cadenciaNoS = byName['IA Classificar'].parameters.options.batching.batch.batchInterval / 1000;
  assert.equal(Number(m[1]), cadenciaNoS,
    `a tela conta ${m[1]}s por classificação e o nó espaça ${cadenciaNoS}s`);

  // Se o merge deixar de ser barreira, o silêncio inicial passa a ser outro
  // fenômeno e a conta da tela fica conservadora demais — melhor saber por
  // reprovação do que por uma espera de 40 minutos sem motivo.
  assert.equal(byName['Juntar Ramos'].parameters.mode, 'append',
    'Juntar Ramos deixou de ser append — reveja o silêncio inicial da tela');
});

test('O nó Postgres devolve o contexto que o próximo nó lê (a reconciliação que ficou 11 dias desligada)', () => {
  // ACHADO EM PRODUÇÃO, execução 7030 (rodada v47, 24/08). O nó Postgres do n8n
  // SUBSTITUI o item pelo resultado da query. O `Gravar Campos (Sombra)`
  // devolvia só `{n_campos}`, e os dois nós seguintes leem `$json.documento_id`:
  // recebiam `undefined`, chamavam as funções com NULL e recebiam de volta
  // "documento não encontrado" — retorno VÁLIDO, nó VERDE, zero linha gravada.
  //
  // Custou onze dias de silêncio: as rodadas v42, v4x, v45 e v47 gravaram ZERO
  // reconciliações (a v41, antes da quebra, gravou 73) e a v45 chegou a
  // `aprovado` assim.
  //
  // E ACONTECEU DE NOVO EM 31/08, PELA MESMA CAUSA E NUM NÓ NOVO — porque esta
  // trava dizia no comentário "é genérica de propósito" e era, no código, um
  // MAPA FIXO DE DOIS PARES. O `Abrir Lote` (0156) entrou inline entre
  // `Lote cabe?` e `Precisa Fallback?`, substituiu o item que carregava
  // `caso_id`, e o `Registrar Documento` morreu com `Failing row contains (uuid,
  // null, null, ...)`: ZERO de 38 documentos, execução VERDE em 37s. Uma guarda
  // que se declara genérica e é uma lista de dois é pior que uma honesta — ela
  // compra a confiança sem dar a cobertura.
  //
  // AGORA ELA É GENÉRICA DE VERDADE: varre TODO nó que lê `$json.X`, caminha para
  // trás pelos nós que apenas REPASSAM o item (IF, Merge, NoOp) e para no
  // primeiro que o SUBSTITUI. Se esse for um nó Postgres, ele tem de devolver X
  // como coluna.
  const REPASSA = new Set(['n8n-nodes-base.if', 'n8n-nodes-base.merge', 'n8n-nodes-base.noOp']);

  // Quem entrega item a quem (aresta invertida).
  const origensDe = new Map();
  for (const [origem, conf] of Object.entries(wf.connections)) {
    for (const ramo of conf.main || []) {
      for (const c of ramo || []) {
        if (!origensDe.has(c.node)) origensDe.set(c.node, []);
        origensDe.get(c.node).push(origem);
      }
    }
  }

  /** As fontes EFETIVAS do item de um nó: sobe por quem só repassa. */
  const fontesEfetivas = (nome) => {
    const out = new Set();
    const vistos = new Set([nome]);
    const fila = [...(origensDe.get(nome) || [])];
    while (fila.length > 0) {
      const atual = fila.pop();
      if (vistos.has(atual)) continue;
      vistos.add(atual);
      const no = byName[atual];
      if (no && REPASSA.has(no.type)) {
        for (const a of origensDe.get(atual) || []) fila.push(a);
      } else {
        out.add(atual);
      }
    }
    return [...out];
  };

  let paresConferidos = 0;
  for (const no of wf.nodes) {
    const qr = no.parameters?.options?.queryReplacement;
    if (typeof qr !== 'string') continue;
    const lidos = [...new Set([...qr.matchAll(/\$json\.(\w+)/g)].map((m) => m[1]))];
    if (lidos.length === 0) continue;

    for (const fonte of fontesEfetivas(no.name)) {
      const upstream = byName[fonte];
      if (!upstream || upstream.type !== 'n8n-nodes-base.postgres') continue;
      // As colunas que o nó anterior REALMENTE devolve: `... as nome`.
      const devolvidas = [...upstream.parameters.query.matchAll(/\bas\s+(\w+)/g)].map((m) => m[1]);
      for (const campo of lidos) {
        paresConferidos += 1;
        assert.ok(devolvidas.includes(campo),
          `${no.name} lê $json.${campo}, e o item dele vem de ${fonte} (nó Postgres, que SUBSTITUI `
          + `o item) — que devolve apenas [${devolvidas.join(', ')}]. O campo chega undefined e a `
          + 'função é chamada com NULL, em silêncio. Foi assim na v47 (11 dias) e na 0156 (0 de 38).');
      }
    }
  }

  // NÃO-VACUIDADE DA PRÓPRIA TRAVA. Sem isto ela viraria verde no dia em que o
  // seletor deixasse de casar — e uma trava que não olha nada tem exatamente a
  // aparência de uma trava que olhou e não achou nada, que é o defeito central
  // deste projeto aplicado ao próprio teste.
  assert.ok(paresConferidos > 0,
    'a trava não conferiu par nenhum — o seletor perdeu o alvo e ela virou decoração');
});

test('Nenhum nó Postgres fica INLINE no caminho por documento (0156: 0 de 38)', () => {
  // A trava acima pega o campo que some. Esta pega a CAUSA um nível acima: um nó
  // Postgres colocado no meio do fluxo por documento. Ele substitui o item de
  // TODO mundo rio abaixo, e quando ainda tem `executeOnce` colapsa 38 itens em 1
  // antes disso.
  //
  // O jeito certo de gravar algo do LOTE no meio do fluxo é um RAMO TERMINAL, ao
  // lado do caminho — como o `Upload Storage` sempre foi, e como o `Abrir Lote`
  // passou a ser depois de 31/08.
  const terminal = (nome) => !wf.connections[nome] || (wf.connections[nome].main || [])
    .every((ramo) => (ramo || []).length === 0);

  const executeOnceInline = wf.nodes
    .filter((n) => n.executeOnce === true && n.type === 'n8n-nodes-base.postgres')
    .filter((n) => !terminal(n.name))
    // A cauda do lote é legítima: de `Reconciliar Lote` em diante não há mais
    // fluxo por documento, e o próprio Merge já reduziu a um item.
    .filter((n) => !['Reconciliar Lote'].includes(n.name))
    .map((n) => n.name);

  assert.deepEqual(executeOnceInline, [],
    'nó Postgres com executeOnce no meio do fluxo por documento: ele substitui o item de todos os '
    + 'documentos seguintes e colapsa o lote em 1. Ponha-o como ramo terminal, ao lado do caminho.');

  // E o `Abrir Lote` especificamente: terminal, e o item segue INTEIRO.
  assert.ok(terminal('Abrir Lote'), 'o Abrir Lote tem de ser ramo terminal');
  const doCabe = wf.connections['Lote cabe?'].main[0].map((c) => c.node);
  assert.ok(doCabe.includes('Abrir Lote'), 'o ramo do "cabe" abre o lote');
  assert.ok(doCabe.includes('Precisa Fallback?'),
    'e o item SEGUE inteiro para a cadeia — sem passar pelo nó Postgres');
  assert.equal(doCabe.indexOf('Abrir Lote'), 0,
    'o Abrir Lote vem primeiro: a linha do lote tem de existir antes de a extração começar');
});

// =============================================================================
// O FATO MATERIAL (Supabase/migrations/0148) ATRAVESSA OS DOIS ESPELHOS.
//
// POR QUE ESTE BLOCO EXISTE. O objeto `diagnostico` é montado DUAS vezes por
// código escrito à mão: em `parseExtractionResponse` (lib) e no `jsCode` que o
// gerador embute no nó `Parse Extracao`. O `espelho-inline.test.mjs` cobre as 26
// FUNÇÕES embutidas por `toString()` — este bloco não é função, é literal, e por
// isso escapa daquele portão.
//
// Divergir aqui não quebra nada visivelmente: o nó continua rodando, o
// diagnóstico continua sendo gravado, e o campo novo simplesmente não chega —
// que é a forma de falha que este projeto passa o tempo corrigindo. Foi assim
// que a reconciliação ficou onze dias parada em silêncio.
//
// A guarda é comparar os dois sobre a MESMA resposta e exigir igualdade.
test('fato material: a lib e o nó real produzem o MESMO diagnostico (os dois espelhos)', async () => {
  const { parseExtractionResponse } = await import('../lib/extract.mjs');
  const TRECHO = 'o índice apurado em 31/12/2025 não atingiu o mínimo contratado, e os saldos '
    + 'foram reclassificados para o passivo circulante';

  const corpo = {
    moeda: 'BRL', unidade: 'R$ mil',
    diagnostico: {
      entidade: 'Canastra Indústria Ltda.', tipo_confirma: true, tipo_sugerido: 'NOTAS_EXPL',
      periodo_tipo: 'anual', periodo_referencia: '2025', legibilidade: 'ok',
      nota_legibilidade: null, tem_dado_financeiro: false,
      resumo: 'Notas explicativas.', justificativa: 'Texto corrido, sem tabela.',
      fatos: [
        { ft: 'covenant_rompido', tr: TRECHO, le: 'A dívida virou curto prazo.', pg: 4 },
        // SEM PROVA: o trecho é um resumo, não uma frase do documento. Tem de
        // cair nos DOIS espelhos, e cair igual.
        { ft: 'ressalva_auditoria', tr: 'tem ressalva', le: 'O parecer não é limpo.', pg: 1 },
      ],
    },
    grupos: [],
  };

  const req = { json: { documento_versao_id: 'ver-fato', tipo: 'NOTAS_EXPL', ia_body: {} } };
  const doNo = await run('Parse Extracao', {
    item: { json: respostaIA(JSON.stringify(corpo)) },
    refs: { 'Montar Req Extracao': req },
  });
  // A lib recebe a resposta NO FORMATO DO PROVEDOR, igual ao nó — passar o
  // conteúdo cru aqui compararia dois caminhos diferentes e o teste mediria
  // a própria chamada em vez do espelho.
  const daLib = parseExtractionResponse(respostaIA(JSON.stringify(corpo)));

  assert.deepEqual(
    doNo.json.diagnostico, daLib.diagnostico,
    'o diagnostico do nó e o da lib divergiram — o bloco é duplicado à mão e escapa do espelho-inline',
  );

  // E as propriedades, nomeadas, para o teste dizer O QUE quebrou quando quebrar.
  assert.equal(doNo.json.diagnostico.fatos.length, 1, 'só o fato COM trecho literal atravessa');
  assert.equal(doNo.json.diagnostico.fatos[0].tipo, 'covenant_rompido');
  assert.equal(doNo.json.diagnostico.fatos[0].trecho, TRECHO, 'o trecho vai literal, sem reescrita');
  assert.equal(doNo.json.diagnostico.fatos[0].pagina, 4);
  assert.equal(doNo.json.diagnostico.fatos[0].leitura, 'A dívida virou curto prazo.');
});

test('fato material: sem a chave "fatos" o diagnostico traz null — e null NÃO é lista vazia', async () => {
  // A DISTINÇÃO É O ASSERT. `null` (workflow antigo, chave ausente) manda
  // `fn_registrar_fatos` NÃO TOCAR nos fatos já gravados; `[]` (o modelo leu e
  // não achou nada) manda apagar. Colapsar os dois em `[]` faria um n8n
  // desatualizado destruir trilha em silêncio — que é exatamente o que o
  // `Gravar Campos` fez por onze dias na v47.
  const req = { json: { documento_versao_id: 'ver-sem-fatos', tipo: 'BALANCO', ia_body: {} } };
  const semChave = await run('Parse Extracao', {
    item: { json: respostaIA(JSON.stringify({
      moeda: 'BRL', unidade: 'R$ mil',
      diagnostico: {
        entidade: 'X', tipo_confirma: true, tipo_sugerido: 'BALANCO', periodo_tipo: 'anual',
        periodo_referencia: '2025', legibilidade: 'ok', nota_legibilidade: null,
        resumo: 'r', justificativa: 'j',
      },
      grupos: [],
    })) },
    refs: { 'Montar Req Extracao': req },
  });
  assert.equal(semChave.json.diagnostico.fatos, null,
    'chave ausente vira null, para o banco saber que não houve leitura');

  const listaVazia = await run('Parse Extracao', {
    item: { json: respostaIA(JSON.stringify({
      moeda: 'BRL', unidade: 'R$ mil',
      diagnostico: {
        entidade: 'X', tipo_confirma: true, tipo_sugerido: 'BALANCO', periodo_tipo: 'anual',
        periodo_referencia: '2025', legibilidade: 'ok', nota_legibilidade: null,
        resumo: 'r', justificativa: 'j', fatos: [],
      },
      grupos: [],
    })) },
    refs: { 'Montar Req Extracao': req },
  });
  assert.deepEqual(listaVazia.json.diagnostico.fatos, [],
    'lista vazia continua lista vazia — é uma leitura de verdade, e ela apaga');
});

test('fato material: o nó que grava PASSA os fatos, e o schema os PEDE', () => {
  // As duas pontas do canal, conferidas no arquivo commitado (que é o que o
  // dono importa no n8n), e não numa reconstrução.
  const diag = byName['Registrar Diagnostico'];
  assert.match(diag.parameters.query, /fn_registrar_fatos\(\$2::uuid,\$12::jsonb\)/,
    'a query chama fn_registrar_fatos com a versão e o jsonb dos fatos');
  assert.match(diag.parameters.options.queryReplacement, /diagnostico\?\.fatos/,
    'o 12º parâmetro sai do diagnostico do Parse Extracao');

  const fatos = extractionSchema().schema.properties.diagnostico.properties.fatos;
  assert.ok(fatos, 'o schema da resposta pede "fatos" — sem isso o modelo nunca os devolve');
  assert.deepEqual(fatos.items.required, ['ft', 'tr', 'le', 'pg']);
  assert.ok(fatos.items.properties.ft.enum.includes('covenant_rompido'));
  assert.ok(
    extractionSchema().schema.properties.diagnostico.required.includes('fatos'),
    'e "fatos" é required: campo opcional em strict mode é campo que o modelo omite',
  );
  assert.match(SYSTEM_PROMPT, /TRECHO LITERAL do documento/,
    'o prompt exige a evidência — o schema sozinho não ensina a copiar em vez de resumir');
});

// =============================================================================
// O NÓ `Juntar Blocos` REAL, com fatos vindos de blocos diferentes.
//
// POR QUE ESTE TESTE EXISTE, e ele nasceu de um religamento que FALHOU em
// acusar: o `cobertura.test.mjs` cobre `juntarBlocos` (a função da lib), e ele
// pega a perda dos fatos. Mas o nó `Juntar Blocos` monta o diagnóstico com
// código escrito à mão DENTRO do gerador — `diagnostico: {...base.diagnostico,
// fatos: r.fatos}` — e essa linha não é a função. Ao desfazê-la e rodar a suíte,
// os 92 testes do workflow-sim passaram com nota máxima.
//
// Ou seja: a lib estava testada e a PRODUÇÃO não. É a mesma deriva de espelho
// que já custou caro nesta casa, e o que a fecha é exercitar o nó COMMITADO —
// o que o dono importa no n8n — em vez da função que ele deveria espelhar.
test('Juntar Blocos (nó real): os fatos de TODOS os blocos chegam ao diagnóstico', async () => {
  const versao = 'ver-fatiado';
  const bloco = (n, fatos) => ({ json: {
    documento_versao_id: versao, documento_id: 'doc-1', bloco: n, blocos: 3,
    campos: [], celulas_no_documento: null,
    diagnostico: { entidade: 'Canastra', tem_dado_financeiro: true, fatos },
  } });

  const r = await run('Juntar Blocos', { items: [
    bloco(1, [{ tipo: 'covenant_rompido', trecho: 'o indice apurado nao atingiu o minimo contratado', pagina: 4 }]),
    bloco(2, [{ tipo: 'ressalva_auditoria', trecho: 'opiniao com ressalva em razao da limitacao de escopo', pagina: 41 }]),
    bloco(3, []),
  ] });

  assert.equal(r.length, 1, 'os três blocos viram UM documento');
  const fatos = r[0].json.diagnostico.fatos;
  assert.ok(Array.isArray(fatos), 'o diagnóstico do documento carrega a lista de fatos');
  assert.equal(fatos.length, 2, 'o fato do bloco 2 não pode se perder na junção');
  assert.deepEqual(fatos.map((f) => f.tipo).sort(), ['covenant_rompido', 'ressalva_auditoria']);
  assert.equal(r[0].json.diagnostico.entidade, 'Canastra',
    'e o resto do diagnóstico continua vindo do bloco 1, que é o certo');
});

test('Juntar Blocos (nó real): nenhum bloco com a chave "fatos" devolve null', async () => {
  // `null` manda `fn_registrar_fatos` NÃO TOCAR nos fatos já gravados; `[]`
  // manda apagar. Um n8n com o JSON antigo não pode destruir trilha.
  const r = await run('Juntar Blocos', { items: [
    { json: { documento_versao_id: 'v1', documento_id: 'd1', bloco: 1, campos: [], diagnostico: { entidade: 'X' } } },
    { json: { documento_versao_id: 'v1', documento_id: 'd1', bloco: 2, campos: [], diagnostico: { entidade: 'X' } } },
  ] });
  assert.equal(r[0].json.diagnostico.fatos, null);
});

// O CONTEXTO DA MEDIÇÃO ATRAVESSA A CADEIA DE EXTRAÇÃO — e não atravessava.
//
// ACHADO NA RODADA COMPARATIVA DO CANASTRA (27/08/2026), pelo sintoma mais
// discreto possível: `lote_execucao.cobertura` nula e `contas_nos_documentos`
// zero, com o `Conferir Lote` VERDE e nenhum erro no n8n.
//
// A causa era `Montar Req Extracao` montar um item NOVO com cinco campos,
// jogando fora tudo o que o `Medir Documento` tinha medido. Três consequências,
// e nenhuma delas dá erro:
//
//   1. sem `linhas_do_texto`, o `Fatiar Extracao` cai no fallback de UM bloco e
//      o fatiamento NUNCA LIGA — o medidor previa 4 documentos fatiados no
//      book e a rodada gravou zero;
//   2. sem `contas_no_documento`, `avaliarCobertura` no `Juntar Blocos` nunca
//      dispara: a guarda de extração incompleta fica DESLIGADA, e ela é a régua
//      que mede alucinação por omissão;
//   3. e o painel do lote grava cobertura nula.
//
// A GUARDA É SOBRE O CAMINHO, não sobre um campo. Ela pega os campos que os nós
// de baixo LEEM do contexto e exige que o nó que os produz os entregue — que é
// a lição da v47 (um nó lendo o que o anterior não entrega) aplicada a nó Code,
// e não só a nó Postgres.
test('a medição do documento sobrevive até o Juntar Blocos (fatiamento e cobertura)', async () => {
  // Os campos que o `Medir Documento` produz e que alguém adiante consome. Cada
  // um está aqui porque um nó de baixo o lê pelo nome.
  const MEDIDOS = ['linhas_do_texto', 'celulas_no_documento', 'contas_no_documento'];

  const medido = {
    json: {
      documento_id: 'doc-1',
      documento_versao_id: 'ver-1',
      nome_original: 'balanco.pdf',
      tipo_taxonomia: 'BALANCO',
      content_part: { type: 'text', text: 'x' },
      linhas_do_texto: ['Caixa 1.000', 'Clientes 2.000', 'Estoques 3.000'],
      celulas_no_documento: 3,
      contas_no_documento: 3,
    },
  };

  // 1. O `Montar Req Extracao` tem de ENTREGAR o que recebeu. Antes desta
  //    correção ele devolvia cinco campos e o resto morria aqui.
  const req = await run('Montar Req Extracao', { item: medido, refs: {} });
  const doReq = Array.isArray(req) ? req[0].json : req.json;
  for (const campo of MEDIDOS) {
    assert.ok(doReq[campo] !== undefined,
      `Montar Req Extracao descartou "${campo}" — e é ele que faz o fatiamento e a cobertura `
      + 'funcionarem. Sem ele nada dá erro: o documento roda inteiro e a guarda cala');
  }
  // E o PDF em base64 NÃO viaja de novo: ele já está dentro do corpo montado.
  assert.equal(doReq.content_part, undefined,
    'o content_part voltou a viajar junto do ia_body — é o PDF inteiro, duas vezes na memória');

  // 2. O `Fatiar Extracao` só fatia se receber as linhas. Com elas, um documento
  //    grande vira mais de um bloco; sem elas, ele silenciosamente vira um.
  const muitasLinhas = { json: { ...doReq, linhas_do_texto: Array.from({ length: 400 }, (_, i) => `Conta ${i} 1.000,00`) } };
  const fatias = await run('Fatiar Extracao', { items: [muitasLinhas], refs: {} });
  assert.ok(fatias.length > 1,
    `um documento de 400 linhas saiu em ${fatias.length} bloco(s) — o fatiamento não ligou, e é `
    + 'assim que o 17_Livro_Razao foi a uma chamada só em vez de quatro');
  assert.ok(fatias.every((f) => f.json.contas_no_documento !== undefined),
    'o Fatiar perdeu a medição no caminho — o Juntar Blocos não terá com o que comparar');
});

// ===========================================================================
// PDF: TEXTO quando ele existe, IMAGEM (OCR) quando não existe.
// ===========================================================================
//
// O DESPERDÍCIO QUE ISTO FECHA. Até 12/09/2026 todo PDF ia à IA como arquivo em
// base64, cobrado como IMAGEM (~1.000 tokens/página) — enquanto o `Extrair
// Texto`, que roda de graça na própria instância, já lia a camada de texto do
// mesmo documento e a usava só para MEDIR cobertura. O conteúdo estava na mão e
// a chamada pagava imagem por ele.
//
// E A METADE QUE NÃO SE PODE PERDER: PDF escaneado não tem camada de texto.
// Mandar o vazio no lugar do documento seria a AMO de novo — ausência
// apresentada como dado. Esse continua indo como imagem, para o modelo ler com
// a visão.
//
// DESLIGAR A CORREÇÃO (fazer o ramo `formato==='pdf'` de `CODE_RECOMPOR_EXTRACAO`
// voltar a `completos.push(entradas[i])`) FAZ ESTES TESTES REPROVAREM EM 4
// ASSERTS DE 6 — medido, um a um, contra o `jsCode` gerado.
//
// OS OUTROS DOIS PASSAM VAZIOS com a correção desligada, e dizer isso vale mais
// que o número: são "não é mais parte de arquivo" e "o escaneado não escreve
// `content_part`". O código antigo os satisfaz sem fazer nada — ele nunca
// escrevia `content_part` para PDF nenhum. Eles não medem a correção; medem que
// o caminho do ESCANEADO não regrediu, que é a metade que não se pode perder.

const ctxPdfBase = {
  caso_id: 'caso-uuid-1', hash: 'hash-pdf', nome_original: 'BALANÇO 2025.pdf',
  formato_detectado: 'pdf', bytes: 2_000_000,
  content_part: { type: 'file', file: { filename: 'BALANÇO 2025.pdf', file_data: 'data:application/pdf;base64,JVBERi0x' } },
};
const TEXTO_DE_BALANCO = [
  'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA', 'CNPJ 44.555.667/0001-59',
  'BALANÇO PATRIMONIAL', '31/12/2025 31/12/2024',
  'ATIVO 137.624 163.941', 'Ativo Circulante 44.022 68.103',
  'Caixa e bancos 825 3.621', 'Contas a receber 22.310 31.884',
].join('\n');

test('MEDIDO: PDF COM camada de texto vai à IA como TEXTO — para de pagar imagem', async () => {
  const out = await run('Recompor Conteudo Extraido', {
    items: [{ json: { text: TEXTO_DE_BALANCO, numpages: 1 } }],
    refs: { 'Preparar Conteudo': [{ json: ctxPdfBase }] },
  });
  assert.equal(out.length, 1);
  const j = out[0].json;
  assert.equal(j.leitura_pdf, 'texto', 'o veredito é DECLARADO, não suposto');
  assert.ok(j.content_part, 'o nó tem de ESCREVER content_part — é isso que faz Medir Documento trocar o base64');
  assert.match(textoDaParte(j.content_part), /ATIVO 137\.624/,
    'o que vai à IA é o texto do PDF, não o PDF em base64');
  assert.ok(!ehParteDeArquivo(j.content_part), 'e NÃO pode continuar sendo parte de arquivo');
});

test('MEDIDO: PDF escaneado continua indo como IMAGEM — o vazio NUNCA substitui o documento', async () => {
  const out = await run('Recompor Conteudo Extraido', {
    items: [{ json: { text: '', numpages: 4 } }],
    refs: { 'Preparar Conteudo': [{ json: ctxPdfBase }] },
  });
  const j = out[0].json;
  assert.equal(j.leitura_pdf, 'ocr');
  assert.equal(j.leitura_pdf_motivo, 'sem-camada-de-texto');
  assert.ok(!('content_part' in j),
    'sem a chave `content_part`, Medir Documento mantém o base64 de Preparar Conteudo — é assim que o PDF chega à visão do modelo');
});

test('camada de texto SEM NÚMERO vai para OCR — numa demonstração o número é a carga', async () => {
  // O caso que passa nos critérios de tamanho e ainda assim é inútil: cabeçalho,
  // CNPJ e rodapé do contador na camada de texto, valores só na imagem.
  const soMobilia = 'CANASTRA INDÚSTRIA LTDA\nBALANÇO PATRIMONIAL\nNotas explicativas em anexo\n'.repeat(8);
  const out = await run('Recompor Conteudo Extraido', {
    items: [{ json: { text: soMobilia, numpages: 1 } }],
    refs: { 'Preparar Conteudo': [{ json: ctxPdfBase }] },
  });
  assert.equal(out[0].json.leitura_pdf, 'ocr');
  assert.equal(out[0].json.leitura_pdf_motivo, 'texto-sem-numeros');
});

test('o veredito do PDF sobrevive a Medir Documento e chega ao orçamento', async () => {
  // `Medir Documento` reconstrói o item a partir de `Preparar Conteudo`
  // (`{...item}`), não do item do extrator — sem carregar por nome, o veredito
  // morria ali e o orçamento voltaria a cobrar imagem de um PDF lido como texto.
  const recomposto = await run('Recompor Conteudo Extraido', {
    items: [{ json: { text: TEXTO_DE_BALANCO, numpages: 1 } }],
    refs: { 'Preparar Conteudo': [{ json: ctxPdfBase }] },
  });
  const medido = await run('Medir Documento', {
    item: recomposto[0], refs: { 'Preparar Conteudo': recomposto[0] },
  });
  assert.equal(medido.json.leitura_pdf, 'texto', 'o veredito atravessa Medir Documento');
  assert.ok(medido.json.caracteres_do_texto > 100, 'e o TAMANHO do texto atravessa junto — é o que o orçamento cobra');
  assert.match(textoDaParte(medido.json.content_part), /ATIVO 137\.624/,
    'Medir Documento entrega o TEXTO adiante, não o base64');
});

test('o orçamento cobra o PDF lido como texto por CARACTERE, não por página de imagem', () => {
  const c = code('Orcamento do Lote');
  const preambulo = c.slice(0, c.indexOf('const itens = $input'));
  // O MESMO documento, lido dos dois jeitos. A diferença é toda a economia.
  const comoTexto = new Function(`${preambulo}
    return orcamentoDoLotePorConteudo({ documentos: [
      { celulas: 80, paginas: 2, colunas: 3, blocos: 1, bytes: 1700, formato: 'texto' },
    ], tokensPromptSistema: 100 });`)();
  const comoImagem = new Function(`${preambulo}
    return orcamentoDoLotePorConteudo({ documentos: [
      { celulas: 80, paginas: 2, colunas: 3, blocos: 1, bytes: 2000000, formato: 'pdf' },
    ], tokensPromptSistema: 100 });`)();
  assert.ok(comoTexto.estimadoUSD <= comoImagem.estimadoUSD,
    'ler como texto nunca pode custar MAIS que ler como imagem — se custar, a conta está invertida');
});

test('MEDIDO: camada de texto CORROMPIDA por glifo dobrado vai para OCR — senão a otimização piora o dado', async () => {
  // A FORMA REAL, não inventada (regra 4): este é o texto que a conversão dos
  // PDFs do dono produziu, medido em 12/09/2026. Dois dos quatro documentos
  // dele têm a camada de texto corrompida por negrito falso (o glifo é desenhado
  // duas vezes e o extrator lê as duas cópias) — AMOBELEZA a 73% e GENERAL
  // TABACO a 37,9% de palavras com letra repetida, contra 3,6% de um texto
  // limpo.
  //
  // O ESTRAGO CHEGA AOS NÚMEROS: `2.2272.055,77` onde o documento diz
  // `2.272.055,77`. A visão do modelo lê a PÁGINA e enxerga o número certo; a
  // camada de texto entrega o errado, com a mesma aparência de um número certo.
  // Sem este ramo, a economia de entrada que este commit traz seria paga com
  // dado corrompido no banco — e isso é pior que o custo que ela poupa.
  const corrompido = [
    'Empprreessaa:: AMOBBELEZA COMEERRCCIIO DIGITAL E OFFLLINE LTDA',
    'CNPPJJ:: 30.893.4496/00001-30',
    'DISSPONIIBILLIIDDAADDES 2.2272.055,77',
    'Bancos Conntta Moovviimeenntto 1.5532.9901,35',
    'Cllieentes 22.414.091,17',
    'Esttooqquueess IInniicciiaall 26.893.325,14',
  ].join('\n');
  const out = await run('Recompor Conteudo Extraido', {
    items: [{ json: { text: corrompido, numpages: 1 } }],
    refs: { 'Preparar Conteudo': [{ json: ctxPdfBase }] },
  });
  assert.equal(out[0].json.leitura_pdf, 'ocr',
    'camada corrompida NÃO pode virar o conteúdo — a imagem é a versão correta do documento');
  assert.equal(out[0].json.leitura_pdf_motivo, 'camada-de-texto-corrompida');
  assert.ok(!('content_part' in out[0].json), 'e o base64 de Preparar Conteudo tem de sobreviver');
});

// ---------------------------------------------------------------------------
// PLANILHA GRANDE (17/09/2026): o `Extract From File` emite UMA LINHA POR ITEM e o
// Merge junta com `push.apply` -- acima de ~120 mil itens a pilha estoura
// ("Maximum call stack size exceeded" em `Juntar Extracao de Conteudo`, execucoes
// 7883, 7886 e a das 00:16). `Agrupar Linhas` reduz a UM item por documento ANTES
// do Merge. Os testes rodam o CODIGO REAL dos nos. Nao confirmado: o encadeamento
// de pairedItem atraves do Merge na instancia real (so' na simulacao).
// ---------------------------------------------------------------------------
// Duas formas, porque o motor do n8n entrega DUAS coisas diferentes (n8n-core 2.16.1,
// `workflow-execute.js:790-812`): o que o nó RECEBE em `$input.all()` tem o pairedItem
// REESCRITO para `{item: <índice na entrada>}` -- ou seja, `{item: i}` em toda linha --,
// e o RUNDATA do extrator (`$('Extrair XLSX').all()`) guarda o que o extrator emitiu:
// `{item: <índice no INPUT do extrator>}` (`fromFile.operation.js:191-206`).
const linhasDaPlanilha = (n, prefixo) => Array.from({ length: n }, (_, k) => ({
  json: { Conta: `${prefixo}-${k}`, Valor: String(k) }, pairedItem: { item: prefixo === 'B' ? 1 : 0 },
}));
// O que o nó Code recebe: pairedItem = índice da própria entrada.
const comoEntradaDoNo = (itens) => itens.map((it, i) => ({ json: it.json, pairedItem: { item: i } }));
// Conta quantas vezes o nó LEU o contexto de um item (`itemMatching(i).json`): o mock de `$()`
// também toca `lista[itemIndex]` a cada chamada, então contar acesso ao índice contaria em dobro.
const listaContada = (lista) => {
  const c = { chamadas: 0 };
  c.lista = lista.map((it) => (it ? { get json() { c.chamadas += 1; return it.json; } } : it));
  return c;
};
const ctxPlanGrande = (hash, nome) => ({
  caso_id: 'caso-uuid-1', hash, nome_original: nome, formato_detectado: 'xlsx', bytes: 5_755_000,
  content_mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  content_part: { type: 'text', text: '(pendente)' }, aviso_conteudo: 'pendente',
});

test('controle positivo: push.apply com 150.000 argumentos ESTOURA a pilha neste Node', () => {
  // Sem isto, os testes abaixo poderiam passar porque o Node do container
  // aguenta 150 mil -- e a correcao nao estaria sendo medida (regra 2).
  const alvo = [];
  const itens = new Array(150_000).fill({});
  assert.throws(() => alvo.push.apply(alvo, itens), RangeError);
});

test('MEDIDO: Agrupar Linhas + Recompor -- planilha de 150.000 linhas e outra no MESMO lote, um item por documento, total verdadeiro, sem estouro', async () => {
  const A = linhasDaPlanilha(150_000, 'A');
  const B = linhasDaPlanilha(30, 'B');
  const rundata = [...A, ...B]; // o que o extrator emitiu (origem 0 e 1)
  const entradas = comoEntradaDoNo(rundata); // o que o Code recebe (pairedItem = i)
  const ctxA = ctxPlanGrande('hash-a', 'CR_Liquidado.xlsx');
  const ctxB = ctxPlanGrande('hash-b', 'Outra.xlsx');
  const ctxPorLinha = entradas.map((_, i) => ({ json: i < A.length ? ctxA : ctxB }));
  const cont = listaContada(ctxPorLinha);
  const agrupado = await run('Agrupar Linhas XLSX', {
    items: entradas, refs: { 'Preparar Conteudo': cont.lista, 'Extrair XLSX': rundata },
  });
  // COMPORTAMENTO medido: 2 documentos resolvem o contexto 2 vezes, nao 150.030.
  assert.equal(cont.chamadas, 2, 'uma resolucao de contexto por ORIGEM, nao por linha');
  assert.equal(agrupado.length, 2, 'duas planilhas => dois itens, nunca 150.030');
  const gA = agrupado.find((i) => i.json.linhas[0].Conta === 'A-0');
  const gB = agrupado.find((i) => i.json.linhas[0].Conta === 'B-0');
  assert.ok(gA && gB);
  assert.equal(gA.json.total_linhas, 150_000);
  assert.equal(gA.json.linhas.length, 2000);
  assert.equal(gB.json.total_linhas, 30);
  assert.ok(gB.json.linhas.every((l) => l.Conta.startsWith('B-')), 'linhas de B nao vazam para A nem ao contrario');
  assert.ok(gA.json.linhas.every((l) => l.Conta.startsWith('A-')));
  for (const it of agrupado) assert.ok(Number.isInteger(it.pairedItem.item));

  // O Merge real empilha estes itens; aqui o Recompor recebe o resultado.
  const ctxDoAgrupado = agrupado.map((it) => ({ json: it === gA ? ctxA : ctxB }));
  const out = await run('Recompor Conteudo Extraido', {
    items: agrupado, refs: { 'Preparar Conteudo': ctxDoAgrupado },
  });
  assert.equal(out.length, 2);
  const oA = out.find((i) => i.json.hash === 'hash-a');
  const oB = out.find((i) => i.json.hash === 'hash-b');
  assert.match(oA.json.content_part.text, /A-0/);
  assert.doesNotMatch(oA.json.content_part.text, /B-0/);
  assert.match(oB.json.content_part.text, /B-29/);
  assert.match(oA.json.aviso_conteudo, /150000/, 'o aviso diz o total VERDADEIRO, nao 2000 de 2000');
  assert.equal(oB.json.aviso_conteudo, null, 'planilha pequena nao abre aviso de truncamento');
  assert.equal(oA.json.leitura_planilha, 'texto');
  assert.ok(oA.json.caracteres_do_texto > 0 && oA.json.caracteres_do_texto === oA.json.content_part.text.length);
});

test('Agrupar Linhas: sem a origem no rundata do extrator, cai em itemMatching por linha e o RESULTADO e o mesmo', async () => {
  // Fallback (binaryMode combinado devolve so' o json; tamanho diferente; `$()` que lanca).
  // Custo declarado no comentario de codeAgruparPlanilha: uma resolucao por linha.
  const A = linhasDaPlanilha(3000, 'A');
  const B = linhasDaPlanilha(30, 'B');
  const entradas = comoEntradaDoNo([...A, ...B]);
  const ctxA = ctxPlanGrande('hash-a', 'CR.xlsx');
  const ctxB = ctxPlanGrande('hash-b', 'Outra.xlsx');
  const ctxPorLinha = entradas.map((_, i) => ({ json: i < A.length ? ctxA : ctxB }));
  const variantes = {
    'sem a referencia ($() lanca)': {},
    'so json (binaryMode combinado)': { 'Extrair XLSX': [...A, ...B].map((it) => ({ json: it.json })) },
    'tamanho diferente': { 'Extrair XLSX': A },
  };
  for (const [nome, extra] of Object.entries(variantes)) {
    const cont = listaContada(ctxPorLinha);
    const out = await run('Agrupar Linhas XLSX', { items: entradas, refs: { 'Preparar Conteudo': cont.lista, ...extra } });
    assert.equal(cont.chamadas, entradas.length, `${nome}: uma resolucao por linha`);
    assert.equal(out.length, 2, nome);
    assert.deepEqual(out.map((i) => i.json.total_linhas).sort((a, b) => a - b), [30, 3000], nome);
  }
});

test('Agrupar Linhas: o extrator do ramo XLS e lido pelo nome do PROPRIO ramo', () => {
  assert.match(code('Agrupar Linhas XLSX'), /\$\("Extrair XLSX"\)\.all\(\)/);
  assert.match(code('Agrupar Linhas XLS'), /\$\("Extrair XLS"\)\.all\(\)/);
});

test('Agrupar Linhas: item de erro e item sem rastro passam intactos, com pairedItem', async () => {
  const ctx = ctxPlanGrande('hash-a', 'a.xlsx');
  const entradas = [
    { json: { Conta: 'x', Valor: '1' }, pairedItem: { item: 0 } },
    { json: { error: 'arquivo corrompido' }, pairedItem: { item: 1 } },
    { json: { Conta: 'orfa', Valor: '2' }, pairedItem: { item: 2 } },
  ];
  // itemMatching do mock devolve lista[i]; para i=2 simulamos ausencia com undefined.
  const out = await run('Agrupar Linhas XLSX', {
    items: entradas, refs: { 'Preparar Conteudo': [{ json: ctx }, { json: ctx }, undefined] },
  });
  assert.equal(out.length, 3);
  assert.ok(out.some((i) => i.json.error === 'arquivo corrompido'));
  assert.ok(out.some((i) => i.json.Conta === 'orfa'), 'sem rastro: isolada, nunca fundida');
  assert.ok(out.some((i) => i.json.planilha_agrupada === true && i.json.total_linhas === 1));
  for (const it of out) assert.ok(it.pairedItem && Number.isInteger(it.pairedItem.item));
});

test('MEDIDO: o orcamento trata a planilha recomposta como TEXTO e ela cabe no teto', async () => {
  const ctx = ctxPlanGrande('hash-a', 'CR_Liquidado_Generalcorporate.xlsx');
  const grande = { planilha_agrupada: true, linhas: linhasDaPlanilha(2000, 'A').map((i) => i.json),
    total_linhas: 150_000, colunas: ['Conta', 'Valor'] };
  const rec = await run('Recompor Conteudo Extraido', {
    items: [{ json: grande }], refs: { 'Preparar Conteudo': [{ json: ctx }] },
  });
  const medido = await run('Medir Documento', { item: rec[0], refs: { 'Preparar Conteudo': rec[0] } });
  assert.equal(medido.json.leitura_planilha, 'texto', 'o veredito sobrevive a Medir Documento');
  const c = code('Orcamento do Lote');
  const preambulo = c.slice(0, c.indexOf('const itens = $input'));
  const j = medido.json;
  const comoTexto = new Function('j', `${preambulo}
    return orcamentoDoLotePorConteudo({ documentos: [
      { celulas: 0, paginas: null, colunas: 2, blocos: 1, formato: 'texto', bytes: Number(j.caracteres_do_texto), nome: 'CR.xlsx' },
    ], tokensPromptSistema: 100 });`)(j);
  const comoArquivo = new Function(`${preambulo}
    return orcamentoDoLotePorConteudo({ documentos: [
      { celulas: 0, paginas: null, colunas: 2, blocos: 1, formato: 'xlsx', bytes: 5_755_000, nome: 'CR.xlsx' },
    ], tokensPromptSistema: 100 });`)();
  assert.equal(comoArquivo.cabe, false, 'controle: pelo tamanho do arquivo o orcamento recusava (US$ 10,81)');
  assert.equal(comoTexto.cabe, true, 'pelo texto enviado cabe');
  // e o no real de orcamento le o veredito do item:
  assert.match(c, /leitura_planilha==='texto'/);
});

test('MEDIDO: documento que sozinho passa do teto e NOMEADO -- nunca "no maximo 0"', () => {
  const c = code('Orcamento do Lote');
  const preambulo = c.slice(0, c.indexOf('const itens = $input'));
  const r = new Function(`${preambulo}
    return orcamentoDoLotePorConteudo({ documentos: [
      { celulas: 0, paginas: null, colunas: 2, blocos: 1, formato: 'xlsx', bytes: 5_755_000, nome: 'CR_Gigante.xlsx' },
      { celulas: 40, paginas: 1, colunas: 3, blocos: 1, formato: 'texto', bytes: 2000, nome: 'pequeno.pdf' },
    ], tokensPromptSistema: 100 });`)();
  assert.equal(r.cabe, false);
  assert.doesNotMatch(r.mensagem, /no máximo 0/);
  assert.match(r.mensagem, /CR_Gigante\.xlsx/);
  assert.match(r.mensagem, /sozinhos MAIS que o teto/);
});

// --- XLSX com mais de uma aba: o extrator nativo leu SO a primeira -----------
// `Endividamento Krauspenhar.xlsx` (mandato real) gravou 0 linhas sem pendência
// nenhuma: 1ª aba = índice, tabela na 2ª. Sem fixture real no repositório, o xlsx
// é MÍNIMO e gerado aqui (`zip-minimo.mjs` declara isso): índice + tabela.
test('xlsx de 2 abas: Preparar Conteudo MEDE as abas e Recompor as declara na pendência', async () => {
  const { xlsxMinimo } = await import('./zip-minimo.mjs');
  const buf = xlsxMinimo([['Índice', [['Abas']]], ['Abertura endividamento', [['Conta', 'Saldo'], ['Banco A', '1000']]]]);
  const item = {
    json: { caso_id: 'c-1', nome_original: 'Endividamento.xlsx' },
    binary: { data: { fileName: 'Endividamento.xlsx', mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', data: buf.toString('base64') } },
  };
  const prep = await run('Preparar Conteudo', { item });
  assert.equal(prep.json.formato_detectado, 'xlsx');
  assert.equal(prep.json.abas_xlsx, 2);

  // a 1ª aba (índice) devolveu 1 linha; é tudo o que o extrator entrega
  const out = await run('Recompor Conteudo Extraido', {
    items: [{ json: { Abas: 'Abertura endividamento' } }], refs: { 'Preparar Conteudo': [{ json: prep.json }] },
  });
  assert.equal(out.length, 1);
  assert.match(out[0].json.aviso_conteudo, /tem 2 abas e o extrator nativo leu SO a primeira \(1 linha/);
  assert.match(out[0].json.aviso_conteudo, /1 aba\(s\) NAO foram lidas/);
  assert.match(out[0].json.aviso_conteudo, /nomes das abas nao estao disponiveis/);
  assert.match(out[0].json.text, /Abertura endividamento/, 'o que foi lido NÃO é descartado');
});

test('xlsx de UMA aba não abre a pendência de abas', async () => {
  const { xlsxMinimo } = await import('./zip-minimo.mjs');
  const buf = xlsxMinimo([['Única', [['Conta', 'Saldo'], ['Banco A', '1000']]]]);
  const item = {
    json: { caso_id: 'c-1', nome_original: 'Um.xlsx' },
    binary: { data: { fileName: 'Um.xlsx', mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', data: buf.toString('base64') } },
  };
  const prep = await run('Preparar Conteudo', { item });
  assert.equal(prep.json.abas_xlsx, 1);
  const out = await run('Recompor Conteudo Extraido', {
    items: [{ json: { Conta: 'Banco A', Saldo: '1000' } }], refs: { 'Preparar Conteudo': [{ json: prep.json }] },
  });
  assert.equal(out[0].json.aviso_conteudo, null);
});

// ---------------------------------------------------------------------------
// O TETO DE TAMANHO POR ARQUIVO (13/10/2026). Medido no n8n 2.30.7: a memoria
// sobe ~50x o tamanho do arquivo (29 MB -> 2,0 GB; 355 MB derruba a instancia),
// e o `Preparar Conteudo` le o binario inteiro. O guarda roda em `Listar
// Arquivos`, antes de qualquer leitura, e recusa pelo MESMO caminho do orcamento.
// ---------------------------------------------------------------------------
const QUINZE_MIB = 15 * 1024 * 1024;
const formComArquivos = (arqs) => ({
  json: { 'Mandato (nome do caso)': 'Mandato Teste' },
  binary: Object.fromEntries(arqs.map((a, i) => [`Arquivos_${i}`,
    { fileName: a.nome, mimeType: 'application/octet-stream', id: `f${i}`, data: 'filesystem-v2', ...(a.bytes === null ? {} : { fileSize: a.bytes }) }])),
});
const listarComTamanhos = (arqs) => run('Listar Arquivos', {
  item: UPSERT_ITEM, items: [UPSERT_ITEM], refs: { ...REFS_BASE, 'Intake (Form)': formComArquivos(arqs) },
});

test('Tamanho: 15 MiB + 1 byte recusa o LOTE inteiro e NOMEIA o arquivo, o tamanho e o teto', async () => {
  const out = await listarComTamanhos([
    { nome: 'balanco.pdf', bytes: 1024 },
    { nome: 'ECD-2025.txt', bytes: QUINZE_MIB + 1 },
  ]);
  // UM item, como a saida do Orcamento do Lote: com um por arquivo, o Registrar
  // Recusa gravaria a mesma falha N vezes.
  assert.equal(out.length, 1);
  assert.equal(out[0].json.caso_id, UPSERT_ITEM.json.caso_id);
  assert.equal(out[0].binary, undefined, 'a recusa nao carrega binario adiante');
  for (const it of out) {
    assert.equal(it.json.tamanho_cabe, false, 'o lote e recusado inteiro, inclusive o arquivo pequeno');
    assert.match(it.json.orcamento_mensagem, /ECD-2025\.txt/);
    assert.match(it.json.orcamento_mensagem, /15\.728\.641 bytes/);
    assert.match(it.json.orcamento_mensagem, /15\.728\.640 bytes/);
    assert.match(it.json.orcamento_mensagem, /tela de\s+arquivos oficiais do portal/);
    assert.match(it.json.orcamento_mensagem, /divida o arquivo/);
    assert.doesNotMatch(it.json.orcamento_mensagem, /balanco\.pdf/, 'so o que passou do teto e nomeado');
  }
});

test('Tamanho: 15 MiB EXATOS passam, sem mensagem', async () => {
  const out = await listarComTamanhos([{ nome: 'ECD-2025.txt', bytes: QUINZE_MIB }]);
  assert.equal(out[0].json.tamanho_cabe, true);
  assert.equal(out[0].json.orcamento_mensagem, undefined);
});

test('Tamanho: arquivo de tamanho DESCONHECIDO (bytes null) NAO passa calado — e recusado dizendo que nao foi medido', async () => {
  const out = await listarComTamanhos([{ nome: 'misterio.xml', bytes: null }, { nome: 'ok.pdf', bytes: 10 }]);
  assert.equal(out.length, 1);
  assert.equal(out[0].json.tamanho_cabe, false);
  assert.match(out[0].json.orcamento_mensagem, /misterio\.xml/);
  assert.match(out[0].json.orcamento_mensagem, /tamanho que o n8n nao informou/);
  assert.match(out[0].json.orcamento_mensagem, /recusado por precaucao/);
});

test('Tamanho: a recusa sai pelo MESMO caminho do orcamento (Registrar Recusa -> Abortar Lote), e o Abortar lanca a mensagem', async () => {
  const dest = (n, ramo) => (wf.connections[n].main[ramo] || []).map((c) => c.node);
  assert.deepEqual(dest('Listar Arquivos', 0), ['Tamanho cabe?']);
  assert.deepEqual(dest('Tamanho cabe?', 0), ['Classificar Nome']);
  assert.deepEqual(dest('Tamanho cabe?', 1), ['Juntar Recusas']);
  assert.deepEqual(dest('Lote cabe?', 1), ['Juntar Recusas']);
  assert.deepEqual(dest('Juntar Recusas', 0), ['Registrar Recusa']);
  assert.deepEqual(dest('Registrar Recusa', 0), ['Abortar Lote']);
  const out = await listarComTamanhos([{ nome: 'ECD-2025.txt', bytes: QUINZE_MIB + 1 }]);
  await assert.rejects(() => run('Abortar Lote', { item: out[0], items: out }), /ECD-2025\.txt/);
});

test('Tamanho: o Preparar Conteudo (getBinaryDataBuffer) so e alcancavel DEPOIS do guarda de tamanho', () => {
  const alcanca = (semNo) => {
    const visto = new Set(['Listar Arquivos']); const fila = ['Listar Arquivos'];
    while (fila.length) {
      const n = fila.shift();
      for (const ramo of wf.connections[n]?.main || []) for (const c of ramo || []) {
        if (c.node === semNo || visto.has(c.node)) continue;
        visto.add(c.node); fila.push(c.node);
      }
    }
    return visto;
  };
  assert.ok(alcanca(null).has('Preparar Conteudo'), 'premissa: o preparo e alcancavel');
  assert.ok(!alcanca('Tamanho cabe?').has('Preparar Conteudo'),
    'sem passar por `Tamanho cabe?`, nenhum caminho chega ao Preparar Conteudo');
});

test('Listar Arquivos carrega o MESMO vereditoDeTamanhoPorArquivo e o MESMO teto de lib/custo.mjs', () => {
  assert.ok(code('Listar Arquivos').includes(vereditoDeTamanhoPorArquivo.toString()));
  assert.ok(code('Listar Arquivos').includes(`const TETO_BYTES_POR_ARQUIVO = ${TETO_BYTES_POR_ARQUIVO};`));
  assert.equal(TETO_BYTES_POR_ARQUIVO, 15 * 1024 * 1024);
});
