import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { prepararRepublicacao, credenciaisPendentes, idsDeCredencialDoAmbiente,
  idsDeCredencialDoPublicado, arquivoDoRepo } from '../preparar-republicacao.mjs';

// A FUSÃO QUE DEVOLVE O COMPORTAMENTO SEM PISAR NA INSTALAÇÃO.
//
// Duas republicações seguidas perderam o mesmo tipo de coisa, e a segunda
// perdeu a pior: o `multipleFiles: true` do campo de arquivo do formulário —
// sem ele, o intake aceita UM documento por vez, e os dois books que faltam têm
// 38 e 190. Cada caso abaixo é uma dessas perdas, ou uma coisa da instalação
// que a correção não pode atropelar.

const REPO = {
  name: 'Oria — E1',
  nodes: [
    { name: 'Intake (Form)', type: 'n8n-nodes-base.formTrigger', typeVersion: 2.2,
      parameters: { formTitle: 'Intake', formFields: { values: [
        { fieldLabel: 'Arquivos', fieldType: 'file', multipleFiles: true, requiredField: true },
      ] } } },
    { name: 'IA Extrair', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
      parameters: { method: 'POST' }, onError: 'continueRegularOutput', retryOnFail: true, maxTries: 6,
      credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'Google AI (Gemini)' } } },
    { name: 'Upload Storage', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
      parameters: { method: 'POST' }, disabled: true,
      credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'Supabase Service (Header Auth)' } } },
  ],
  connections: { 'Intake (Form)': { main: [[{ node: 'IA Extrair', type: 'main', index: 0 }]] } },
  settings: { executionOrder: 'v1' },
};

// O publicado como ele voltou da republicação de 27/08: sem os campos de
// comportamento, sem o `multipleFiles`, mas com os ids e o `path` da instalação
// e com o `errorWorkflow` que o dono ligou à mão.
const VIVO = {
  name: 'Oria — E1',
  nodes: [
    { id: 'no-1', name: 'Intake (Form)', type: 'n8n-nodes-base.formTrigger', typeVersion: 2.2,
      webhookId: 'wh-1',
      parameters: { formTitle: 'Intake', path: 'bea41a5a-3c43-4fc6-915f-0d74d3bcf25e', formFields: { values: [
        { fieldLabel: 'Arquivos', fieldType: 'file', requiredField: true },
      ] } } },
    { id: 'no-2', name: 'IA Extrair', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
      parameters: { method: 'POST' },
      credentials: { httpHeaderAuth: { id: 'FVVausmZHGZNICDP', name: 'Gemini da conta' } } },
    { id: 'no-3', name: 'Upload Storage', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
      parameters: { method: 'POST' }, disabled: true,
      credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'Supabase Service (Header Auth)' } } },
  ],
  connections: {},
  settings: { executionOrder: 'v1', errorWorkflow: '59DPz4s2d3DHSR9M', callerPolicy: 'workflowsFromSameOwner' },
};

const porNome = (w) => Object.fromEntries(w.nodes.map((n) => [n.name, n]));

test('o COMPORTAMENTO volta do repositório — é o que as duas republicações perderam', () => {
  const n = porNome(prepararRepublicacao(VIVO, REPO))['IA Extrair'];
  assert.equal(n.onError, 'continueRegularOutput');
  assert.equal(n.retryOnFail, true);
  assert.equal(n.maxTries, 6);
});

test('o `multipleFiles` do campo de arquivo volta — sem ele o intake aceita UM documento', () => {
  const n = porNome(prepararRepublicacao(VIVO, REPO))['Intake (Form)'];
  assert.equal(n.parameters.formFields.values[0].multipleFiles, true,
    'o formulário voltaria a aceitar um arquivo por vez, e os books têm 38 e 190');
});

test('o `path` do formulário é DA INSTALAÇÃO e não pode ser sobrescrito', () => {
  const n = porNome(prepararRepublicacao(VIVO, REPO))['Intake (Form)'];
  assert.equal(n.parameters.path, 'bea41a5a-3c43-4fc6-915f-0d74d3bcf25e',
    'sobrescrever o path troca a URL pública do intake — já se perdeu uma vez assim');
  assert.equal(n.webhookId, 'wh-1');
  assert.equal(n.id, 'no-1', 'o id do nó vem do vivo, senão o n8n trata o nó como novo');
});

test('o id da credencial vem do VIVO; o REPLACE do repositório só fica no nó LIGADO sem outro id', () => {
  const nos = porNome(prepararRepublicacao(VIVO, REPO));
  assert.deepEqual(nos['IA Extrair'].credentials.httpHeaderAuth,
    { id: 'FVVausmZHGZNICDP', name: 'Gemini da conta' },
    'publicar o REPLACE derruba o nó com "Credential with ID REPLACE does not exist"');
  assert.equal(nos['Upload Storage'].credentials, undefined,
    'nó DESABILITADO sem id na instalação sai SEM credencial — o REPLACE barraria o arquivo inteiro sem impedir falha nenhuma');
});

test('as `settings` da instalação sobrevivem — é onde mora o errorWorkflow ligado à mão', () => {
  const p = prepararRepublicacao(VIVO, REPO);
  assert.equal(p.settings.errorWorkflow, '59DPz4s2d3DHSR9M',
    'sobrescrever as settings desligaria o Error Workflow em silêncio — o mesmo defeito, em outro campo');
  assert.equal(p.settings.executionOrder, 'v1');
});

test('as CONEXÕES vêm do repositório — um nó certo ligado errado não aparece em nó nenhum', () => {
  const p = prepararRepublicacao(VIVO, REPO);
  assert.deepEqual(p.connections, REPO.connections);
});

test('o relatório só aponta credencial REPLACE em nó LIGADO — o desligado nem pendente fica', () => {
  const pend = credenciaisPendentes(prepararRepublicacao(VIVO, REPO));
  assert.equal(pend.length, 0,
    'a única credencial sem id é de um nó desabilitado — ela some do JSON em vez de travar a rodada');

  // Com o mesmo nó HABILITADO, o REPLACE volta a existir — e é o portão que
  // derruba a publicação, não este relatório.
  const ligado = JSON.parse(JSON.stringify(REPO));
  delete ligado.nodes[2].disabled;
  const pend2 = credenciaisPendentes(prepararRepublicacao(VIVO, ligado));
  assert.equal(pend2.length, 1);
  assert.equal(pend2[0].no, 'Upload Storage');
  assert.equal(pend2[0].desabilitado, false, 'nó ligado com REPLACE é o que a trava do republicar.sh segura');
});

// O `Upload Storage` REAL, religado em 07/10/2026 (antes desabilitado desde 17/07).
// A exceção do nó DESABILITADO deixou de se aplicar a ele: agora ele é LIGADO, e
// ligado com `REPLACE` e sem id na instalação tem de continuar BARRADO — é a trava
// que o republicar.sh segura. A credencial `Supabase Storage (service_role)` é nova
// (httpCustomAuth): o vivo ainda não a conhece, então só o N8N_CRED_IDS a resolve.
test('Upload Storage REAL, ligado: sem id na instalação o REPLACE aparece (trava); com N8N_CRED_IDS resolve', () => {
  const repo = JSON.parse(readFileSync(join(dirname(fileURLToPath(import.meta.url)), '..', 'workflow.e1-ingestao.json'), 'utf8'));
  const up = repo.nodes.find((n) => n.name === 'Upload Storage');
  assert.equal(up.disabled, undefined, 'a premissa do teste: o nó está ligado no repositório');
  const vivo = { name: repo.name, nodes: [{ id: 'no-up', name: 'Upload Storage', type: up.type,
    typeVersion: up.typeVersion, parameters: {}, disabled: true }], connections: {}, settings: {} };

  const semId = credenciaisPendentes(prepararRepublicacao(vivo, repo));
  const pend = semId.find((p) => p.no === 'Upload Storage');
  assert.ok(pend, 'nó LIGADO com credencial desconhecida tem de sair pendente — senão o REPLACE vai para produção calado');
  assert.equal(pend.desabilitado, false);
  assert.equal(pend.nome, 'Supabase Storage (service_role)');

  const comId = prepararRepublicacao(vivo, repo,
    { idsPorNome: { 'Supabase Storage (service_role)': 'Z8T67xTWMxinqxGx' } });
  const no = comId.nodes.find((n) => n.name === 'Upload Storage');
  assert.equal(no.credentials.httpCustomAuth.id, 'Z8T67xTWMxinqxGx');
  assert.equal(no.disabled, undefined, 'a republicação não pode devolver o disabled que o vivo ainda tem');
  assert.equal(no.onError, 'continueRegularOutput', 'o ramo lateral não derruba a ingestão');
});

// ---------------------------------------------------------------------------
// IDs DE CREDENCIAL VINDOS DE FORA — o desbloqueio da action do GitHub.
// ---------------------------------------------------------------------------
//
// MEDIDO EM PRODUÇÃO, três execuções seguidas (11/09/2026, runs 1-3 de
// `.github/workflows/republicar.yml`): a action abortou no passo 4 com
// "sobraram 2 ocorrência(s) de REPLACE" — `IA Classificar` e `IA Extrair`.
//
// A divisão é por TIPO de credencial, não por nó, e é o que aponta a causa:
// as ONZE credenciais `postgres` do workflow resolveram TODAS pelo vivo; as
// TRÊS `httpHeaderAuth` não resolveram NENHUMA. A API pública do n8n não
// devolve a `httpHeaderAuth` desses nós, então não existe id a ler.
//
// A trava que abortou estava certa (publicar REPLACE em nó ligado quebra a
// credencial em produção). O que faltava era o id chegar sem passar pelo vivo.

const REPO_OPENAI = {
  ...REPO,
  nodes: [
    { name: 'IA Classificar', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
      parameters: { method: 'POST' },
      credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'OpenAI API' } } },
    { name: 'IA Extrair', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
      parameters: { method: 'POST' },
      credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'OpenAI API' } } },
  ],
};
// O vivo como a API o devolve: os nós existem, mas SEM a httpHeaderAuth.
const VIVO_SEM_HEADER_AUTH = {
  ...VIVO,
  nodes: [
    { id: 'no-c', name: 'IA Classificar', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2, parameters: {} },
    { id: 'no-e', name: 'IA Extrair', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2, parameters: {} },
  ],
};

test('MEDIDO: o cenário das 3 falhas da action — id de fora resolve o que o vivo não conta', () => {
  const semMapa = prepararRepublicacao(VIVO_SEM_HEADER_AUTH, REPO_OPENAI);
  assert.equal(credenciaisPendentes(semMapa).length, 2,
    'sem o mapa, os DOIS nós ficam em REPLACE — é exatamente o que abortou a action 3 vezes');

  const comMapa = prepararRepublicacao(VIVO_SEM_HEADER_AUTH, REPO_OPENAI,
    { idsPorNome: { 'OpenAI API': 'aBc123' } });
  assert.deepEqual(credenciaisPendentes(comMapa), [], 'com o mapa, nada fica pendente');
  const n = porNome(comMapa);
  assert.equal(n['IA Classificar'].credentials.httpHeaderAuth.id, 'aBc123');
  assert.equal(n['IA Extrair'].credentials.httpHeaderAuth.id, 'aBc123',
    'UMA entrada no mapa serve os dois nós — a chave é o nome da credencial, não o nó');
  assert.equal(n['IA Extrair'].credentials.httpHeaderAuth.name, 'OpenAI API');
});

test('o VIVO ganha do mapa — um mapa velho não pode sobrescrever a credencial publicada', () => {
  // A precedência importa: ao contrário, um id desatualizado no secret trocaria
  // em silêncio a credencial certa por uma que não existe mais, e o sintoma
  // apareceria só na próxima rodada.
  const pronto = prepararRepublicacao(VIVO, REPO, { idsPorNome: { 'Google AI (Gemini)': 'id-velho-do-secret' } });
  assert.equal(porNome(pronto)['IA Extrair'].credentials.httpHeaderAuth.id, 'FVVausmZHGZNICDP',
    'quem está publicado é a verdade sobre a instalação; o mapa é só a queda');
});

test('o mapa NÃO desarma a trava: REPLACE ou vazio no mapa é ausência, não resposta', () => {
  for (const idRuim of ['REPLACE', '', '   ']) {
    const pronto = prepararRepublicacao(VIVO_SEM_HEADER_AUTH, REPO_OPENAI,
      { idsPorNome: idsDeCredencialDoAmbiente({ N8N_CRED_IDS: JSON.stringify({ 'OpenAI API': idRuim }) }) });
    assert.equal(credenciaisPendentes(pronto).length, 2,
      `id "${idRuim}" no mapa não pode passar por resolvido — desarmaria o portão do republicar.sh`);
  }
});

test('idsDeCredencialDoAmbiente: ausente é {}, JSON quebrado FALA o que fazer', () => {
  assert.deepEqual(idsDeCredencialDoAmbiente({}), {}, 'sem o secret, segue o comportamento de sempre');
  assert.deepEqual(idsDeCredencialDoAmbiente({ N8N_CRED_IDS: '   ' }), {});
  assert.deepEqual(idsDeCredencialDoAmbiente({ N8N_CRED_IDS: '{"OpenAI API":"x1"}' }), { 'OpenAI API': 'x1' });
  // Secret mal colado é o erro mais provável deste caminho, e ele tem de dizer
  // o formato esperado em vez de estourar um SyntaxError cru do JSON.
  assert.throws(() => idsDeCredencialDoAmbiente({ N8N_CRED_IDS: 'OpenAI API=x1' }), /não é JSON válido/);
  assert.throws(() => idsDeCredencialDoAmbiente({ N8N_CRED_IDS: '["x1"]' }), /precisa ser um OBJETO/);
});

// ---------------------------------------------------------------------------
// O NÓ NOVO QUE USA UMA CREDENCIAL VELHA — a action de 12/09/2026.
//
// O arranjo é o real, reduzido: três nós `postgres` dividindo UMA credencial,
// dois já publicados e UM que a instalação ainda não conhece. No workflow de
// verdade são onze nós na mesma credencial, nove resolvendo pelo publicado e
// dois — `Gravar Uso do Lote` e `Conferir Lote` — abortando o arquivo inteiro.
// O id que faltava estava na resposta o tempo todo, em nó irmão.
//
// MEDIDO com o ramo do irmão desligado: 3 asserts reprovam, em 2 testes. Os
// outros 5 testes daqui PASSAM desligados de propósito — eles não medem a
// correção, medem o que ela não pode quebrar: a precedência do id do próprio
// nó, a ambiguidade que se cala, o casamento por tipo, e a queda para o
// N8N_CRED_IDS que destravou a action de 11/09.

const PG = 'Supabase Postgres (Session Pooler)';

const REPO_LOTE = {
  name: 'Oria — E1',
  nodes: [
    { name: 'Abrir Lote', type: 'n8n-nodes-base.postgres',
      credentials: { postgres: { id: 'REPLACE', name: PG } } },
    { name: 'Registrar Documento', type: 'n8n-nodes-base.postgres',
      credentials: { postgres: { id: 'REPLACE', name: PG } } },
    { name: 'Conferir Lote', type: 'n8n-nodes-base.postgres',
      credentials: { postgres: { id: 'REPLACE', name: PG } } },
  ],
  connections: {},
  settings: {},
};

// `Conferir Lote` não está aqui: é o nó novo, o que o publicado não tem.
const VIVO_LOTE = {
  name: 'Oria — E1',
  nodes: [
    { id: 'no-1', name: 'Abrir Lote', type: 'n8n-nodes-base.postgres',
      credentials: { postgres: { id: 'pg-da-instalacao', name: PG } } },
    { id: 'no-2', name: 'Registrar Documento', type: 'n8n-nodes-base.postgres',
      credentials: { postgres: { id: 'pg-da-instalacao', name: PG } } },
  ],
  connections: {},
  settings: {},
};

test('MEDIDO: o nó NOVO herda o id do nó IRMÃO já publicado — era o que travava a action', () => {
  const nos = porNome(prepararRepublicacao(VIVO_LOTE, REPO_LOTE));
  assert.deepEqual(nos['Conferir Lote'].credentials.postgres, { id: 'pg-da-instalacao', name: PG },
    'o id estava na resposta, a dois nós de distância — publicar REPLACE aqui derruba o nó');
  assert.equal(credenciaisPendentes(prepararRepublicacao(VIVO_LOTE, REPO_LOTE)).length, 0,
    'sobrando REPLACE, o portão do republicar.sh aborta o arquivo INTEIRO e a correção não chega à produção');
});

test('o nó irmão NÃO atropela o nó que tem id próprio — o mesmo nome pode ter id diferente', () => {
  const vivo = { ...VIVO_LOTE, nodes: [
    ...VIVO_LOTE.nodes,
    { id: 'no-3', name: 'Conferir Lote', type: 'n8n-nodes-base.postgres',
      credentials: { postgres: { id: 'id-proprio-do-no', name: PG } } },
  ] };
  const nos = porNome(prepararRepublicacao(vivo, REPO_LOTE));
  assert.equal(nos['Conferir Lote'].credentials.postgres.id, 'id-proprio-do-no',
    'a credencial do PRÓPRIO nó é mais específica que a do irmão e continua ganhando');
});

test('AMBIGUIDADE não responde: mesmo (tipo, nome) com ids diferentes deixa o REPLACE de pé', () => {
  const vivo = { ...VIVO_LOTE, nodes: [
    VIVO_LOTE.nodes[0],
    { ...VIVO_LOTE.nodes[1], credentials: { postgres: { id: 'OUTRO-id', name: PG } } },
  ] };
  const nos = porNome(prepararRepublicacao(vivo, REPO_LOTE));
  assert.equal(nos['Conferir Lote'].credentials.postgres.id, 'REPLACE',
    'escolher um dos dois apontaria metade dos nós para a credencial errada — falha silenciosa');
});

test('o índice casa por TIPO também — nome igual em tipos diferentes não se cruza', () => {
  const indice = idsDeCredencialDoPublicado({ nodes: [
    { credentials: { postgres: { id: 'pg-1', name: 'Mesma Coisa' } } },
    { credentials: { httpHeaderAuth: { id: 'http-1', name: 'Mesma Coisa' } } },
  ] });
  assert.equal(indice.get('postgres').get('Mesma Coisa'), 'pg-1');
  assert.equal(indice.get('httpHeaderAuth').get('Mesma Coisa'), 'http-1',
    'o nome de credencial é único POR TIPO no n8n, não globalmente');
});

test('REPLACE e vazio no publicado são ausência, não resposta — senão a trava se desarma', () => {
  const indice = idsDeCredencialDoPublicado({ nodes: [
    { credentials: { postgres: { id: 'REPLACE', name: PG } } },
    { credentials: { httpHeaderAuth: { id: '   ', name: 'OpenAI API' } } },
  ] });
  assert.equal(indice.get('postgres'), undefined);
  assert.equal(indice.get('httpHeaderAuth'), undefined);
});

test('o irmão ganha do mapa do ambiente — o publicado é a verdade, o secret é a queda', () => {
  const nos = porNome(prepararRepublicacao(VIVO_LOTE, REPO_LOTE,
    { idsPorNome: { [PG]: 'id-velho-do-secret' } }));
  assert.equal(nos['Conferir Lote'].credentials.postgres.id, 'pg-da-instalacao',
    'um secret desatualizado sobrescreveria a credencial certa por uma que não existe mais');
});

test('sem irmão, o mapa do ambiente continua resolvendo — a queda de 11/09 segue de pé', () => {
  const nos = porNome(prepararRepublicacao({ nodes: [], connections: {}, settings: {} }, REPO_LOTE,
    { idsPorNome: { [PG]: 'id-do-secret' } }));
  assert.equal(nos['Conferir Lote'].credentials.postgres.id, 'id-do-secret');
});


// ---------------------------------------------------------------------------
// QUAL ARQUIVO PREPARAR — até 16/09/2026 (F0, fatia 0.3) era fixo na ingestão,
// e os outros três workflows deste repositório não tinham como usar esta
// fusão. MEDIDO com a escolha desligada (arquivoDoRepo() sempre devolvendo o
// mesmo valor, como antes desta fatia): os dois primeiros testes abaixo
// reprovam, porque nada muda quando N8N_ARQUIVO_REPO pede outro workflow.

test('N8N_ARQUIVO_REPO escolhe QUAL workflow preparar', () => {
  assert.equal(arquivoDoRepo({ N8N_ARQUIVO_REPO: 'N8N/workflow.macro.json' }), 'N8N/workflow.macro.json');
  assert.equal(arquivoDoRepo({ N8N_ARQUIVO_REPO: 'N8N/workflow.erros.json' }), 'N8N/workflow.erros.json');
});

test('sem a variável, o padrão continua a ingestão — quem já automatizou isso não muda de alvo', () => {
  assert.equal(arquivoDoRepo({}), 'N8N/workflow.e1-ingestao.json');
  assert.equal(arquivoDoRepo({ N8N_ARQUIVO_REPO: '' }), 'N8N/workflow.e1-ingestao.json');
  assert.equal(arquivoDoRepo({ N8N_ARQUIVO_REPO: '   ' }), 'N8N/workflow.e1-ingestao.json');
});

// --- O repositório nunca grava id de credencial que a trava deixe passar ------
// A trava 2 do `republicar.sh` só procura `REPLACE`, e `ehIdUtilizavel` aceita
// qualquer outro id como real. Até 24/09/2026 o `workflow.macro.json` gravava
// `SUPABASE_PG` nas três credenciais Postgres: republicado numa instância sem essa
// credencial, o macro saía com um id inexistente e passava pela trava — e a
// republicação foi generalizada para os quatro workflows em 16/09. O que se afirma
// é o contrato, nos quatro arquivos commitados: toda credencial ou é `REPLACE`
// (a trava a cobre) ou não existe.
const PASTA_N8N = join(dirname(fileURLToPath(import.meta.url)), '..');
const WORKFLOWS = readdirSync(PASTA_N8N).filter((f) => /^workflow\..+\.json$/.test(f));

test('os quatro workflows commitados existem (controle positivo do teste abaixo)', () => {
  assert.equal(WORKFLOWS.length, 4, `achei ${WORKFLOWS.join(', ')}`);
});

for (const arq of WORKFLOWS) {
  test(`${arq}: toda credencial grava REPLACE, que é o que a trava do republicar.sh procura`, () => {
    const wf = JSON.parse(readFileSync(join(PASTA_N8N, arq), 'utf8'));
    const fora = [];
    let credenciais = 0;
    for (const n of wf.nodes) {
      for (const [tipo, c] of Object.entries(n.credentials ?? {})) {
        credenciais++;
        if (c?.id !== 'REPLACE') fora.push(`${n.name} (${tipo}): id ${JSON.stringify(c?.id)}`);
      }
    }
    assert.ok(credenciais > 0, `${arq} não tem credencial nenhuma — o teste não mediu nada`);
    assert.deepEqual(fora, [], `credencial com id que a trava não pega: ${fora.join('; ')}`);
  });
}

// E o que JÁ ESTÁ NO AR. Se o `SUPABASE_PG` chegou à instalação, o publicado o
// traz como se fosse id real; a republicação o preservava (o VIVO ganha) e a trava
// não o via. Placeholder publicado é ausência, não resposta: cai para o irmão, o
// mapa do ambiente, ou o `REPLACE` que trava o portão.
test('o `SUPABASE_PG` publicado não sobrevive à republicação: vira REPLACE, ou o id do mapa', () => {
  const repo = structuredClone(REPO);
  repo.nodes[1].credentials = { postgres: { id: 'REPLACE', name: 'Supabase Postgres' } };
  const vivo = structuredClone(VIVO);
  vivo.nodes[1].credentials = { postgres: { id: 'SUPABASE_PG', name: 'Supabase Postgres' } };
  const semMapa = porNome(prepararRepublicacao(vivo, repo))['IA Extrair'].credentials.postgres;
  assert.equal(semMapa.id, 'REPLACE', 'sem mapa, sai REPLACE — e a trava do republicar.sh aborta');
  const comMapa = porNome(prepararRepublicacao(vivo, repo, { idsPorNome: { 'Supabase Postgres': 'pgReal123' } }))['IA Extrair'].credentials.postgres;
  assert.equal(comMapa.id, 'pgReal123', 'com o mapa, sai o id real');
});
