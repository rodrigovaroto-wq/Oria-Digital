import { test } from 'node:test';
import assert from 'node:assert/strict';
import { conferir, escolherDoRepo, WORKFLOWS_DO_REPO } from '../conferir-publicado.mjs';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ_REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

// O CONFERIDOR DO QUE ESTÁ PUBLICADO — e por que ele precisa de teste próprio.
//
// Ele nasceu de uma conferência que passou verde estando errada: em 26/08/2026
// a republicação foi declarada "33 de 33 nós byte a byte iguais" comparando
// `parameters`, e o que tinha se perdido morava fora de `parameters` —
// `onError` em 22 nós, `retryOnFail`/`maxTries` em 10, e o `disabled` do
// `Upload Storage`, que voltou a executar com credencial `REPLACE` e derrubou o
// primeiro lote no primeiro nó.
//
// Um conferidor com ponto cego é pior que nenhum: ele produz a frase "está
// igual" com autoridade. Então cada coisa que ele tem de ver, e cada coisa que
// ele tem de IGNORAR, é um teste.

const REPO = {
  nodes: [
    { name: 'Intake (Form)', type: 'n8n-nodes-base.formTrigger', typeVersion: 2.2,
      parameters: { formTitle: 'Intake' } },
    { name: 'IA Extrair', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
      parameters: { method: 'POST' }, onError: 'continueRegularOutput', retryOnFail: true, maxTries: 6,
      credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'Google AI (Gemini)' } } },
    { name: 'Upload Storage', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
      parameters: { method: 'POST' }, disabled: true,
      credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'Supabase Service (Header Auth)' } } },
  ],
  connections: { 'Intake (Form)': { main: [[{ node: 'IA Extrair', type: 'main', index: 0 }]] } },
};

// O publicado de um sistema SAUDÁVEL: mesmos nós, com os ids e nomes de
// credencial DA INSTALAÇÃO, e com o `path` que o n8n atribuiu ao formulário.
function publicadoSaudavel() {
  return {
    nodes: [
      { name: 'Intake (Form)', type: 'n8n-nodes-base.formTrigger', typeVersion: 2.2,
        parameters: { formTitle: 'Intake', path: 'bea41a5a-3c43-4fc6-915f-0d74d3bcf25e' } },
      { name: 'IA Extrair', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
        parameters: { method: 'POST' }, onError: 'continueRegularOutput', retryOnFail: true, maxTries: 6,
        credentials: { httpHeaderAuth: { id: 'FVVausmZHGZNICDP', name: 'Google AI (Gemini)' } } },
      { name: 'Upload Storage', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
        parameters: { method: 'POST' }, disabled: true,
        credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'Supabase Service (Header Auth)' } } },
    ],
    connections: JSON.parse(JSON.stringify(REPO.connections)),
  };
}

const campos = (achados) => achados.map((a) => `${a.no}.${a.campo}`);

test('publicação saudável: nenhuma divergência', () => {
  assert.deepEqual(conferir(publicadoSaudavel(), REPO), []);
});

test('o id e o nome da credencial são DA INSTALAÇÃO e não viram divergência', () => {
  const vivo = publicadoSaudavel();
  vivo.nodes[1].credentials.httpHeaderAuth = { id: 'outro-id-qualquer', name: 'Gemini da conta nova' };
  assert.deepEqual(conferir(vivo, REPO), [],
    'o conferidor passou a cobrar um dado que não pertence ao repositório');
});

test('o `path` do formulário é atribuído pelo n8n e não vira divergência', () => {
  const vivo = publicadoSaudavel();
  vivo.nodes[0].parameters.path = 'outro-uuid-porque-o-n8n-quis';
  assert.deepEqual(conferir(vivo, REPO), [],
    'sobrescrever o path troca a URL pública do intake — o conferidor não pode empurrar para isso');
});

// ---------------------------------------------------------------------------
// O QUE ELE TEM DE PEGAR — cada caso é uma perda real da republicação de 26/08
// ---------------------------------------------------------------------------

test('perder o onError vira divergência — a rede de proteção some em silêncio', () => {
  const vivo = publicadoSaudavel();
  delete vivo.nodes[1].onError;
  assert.deepEqual(campos(conferir(vivo, REPO)), ['IA Extrair.onError']);
});

test('perder retryOnFail/maxTries vira divergência', () => {
  const vivo = publicadoSaudavel();
  delete vivo.nodes[1].retryOnFail;
  delete vivo.nodes[1].maxTries;
  assert.deepEqual(campos(conferir(vivo, REPO)), ['IA Extrair.retryOnFail', 'IA Extrair.maxTries']);
});

test('perder o `disabled` vira divergência — foi assim que o Upload Storage voltou a rodar', () => {
  const vivo = publicadoSaudavel();
  delete vivo.nodes[2].disabled;
  // Duas coisas ao mesmo tempo, e as duas verdadeiras: o nó deixou de estar
  // desabilitado, E agora ele é um nó HABILITADO com o placeholder do
  // repositório na credencial — que é a falha que o dono viu na tela.
  assert.deepEqual(campos(conferir(vivo, REPO)),
    ['Upload Storage.disabled', 'Upload Storage.credentials.httpHeaderAuth.id']);
});

test('o `REPLACE` do repositório num nó HABILITADO é divergência; num desabilitado, não', () => {
  const vivo = publicadoSaudavel();
  vivo.nodes[1].credentials.httpHeaderAuth = { id: 'REPLACE', name: 'Google AI (Gemini)' };
  assert.deepEqual(campos(conferir(vivo, REPO)), ['IA Extrair.credentials.httpHeaderAuth.id']);
  // e o Upload Storage, desabilitado com REPLACE, continua sem acusar nada.
});

test('nó a mais, nó a menos e conexão diferente também são divergência', () => {
  const semNo = publicadoSaudavel();
  semNo.nodes.splice(1, 1);
  assert.ok(campos(conferir(semNo, REPO)).includes('IA Extrair.(o nó)'));

  const aMais = publicadoSaudavel();
  aMais.nodes.push({ name: 'Alguém Mexeu Aqui', type: 'n8n-nodes-base.noOp', typeVersion: 1, parameters: {} });
  assert.ok(campos(conferir(aMais, REPO)).includes('Alguém Mexeu Aqui.(o nó)'));

  const religado = publicadoSaudavel();
  religado.connections['Intake (Form)'].main[0][0].node = 'Upload Storage';
  assert.ok(campos(conferir(religado, REPO)).includes('(o workflow).connections'),
    'um nó certo ligado errado não aparece em nenhuma comparação de nó');
});

test('parâmetro diferente continua sendo divergência — o conferidor de 26/08 não regrediu', () => {
  const vivo = publicadoSaudavel();
  vivo.nodes[1].parameters.method = 'GET';
  assert.deepEqual(campos(conferir(vivo, REPO)), ['IA Extrair.parameters']);
});

// ---------------------------------------------------------------------------
// A OUTRA METADE DA REGRA DO NÓ DESABILITADO — MEDIDO EM PRODUÇÃO (12/09/2026).
// ---------------------------------------------------------------------------
//
// Em 11/09 (`7b84086`) `preparar-republicacao.mjs` passou a REMOVER a credencial
// de um nó DESABILITADO sem id na instalação. A mensagem daquele commit
// afirmava: "O conferidor não muda: ele ignora id e nome de credencial por
// design e só pune REPLACE em nó ligado."
//
// A afirmação estava ERRADA, e o preço apareceu na primeira republicação que
// chegou ao passo 5. O conferidor também pune AUSÊNCIA — e ausência é
// exatamente o que a regra nova produz. A publicação FUNCIONOU (o PUT subiu, os
// 40 nós bateram, o `path` do formulário sobreviveu) e mesmo assim a action
// saiu com código 1 mandando "republicar a partir do repositório" sobre uma
// publicação já correta.
//
// Duas cópias da mesma regra, e só uma foi escrita. É o defeito que este
// projeto persegue, dentro do par de ferramentas que existe para persegui-lo.
test('MEDIDO: credencial removida de nó DESABILITADO não é divergência — o preparador a remove de propósito', () => {
  const publicado = publicadoSaudavel();
  const upload = publicado.nodes.find((n) => n.name === 'Upload Storage');
  delete upload.credentials; // exatamente o que `prepararRepublicacao` publica

  assert.deepEqual(conferir(publicado, REPO), [],
    'nó desabilitado NÃO executa, então credencial ausente nele não pode falhar');
});

test('a metade que NÃO se perdoa: credencial ausente em nó LIGADO continua sendo divergência', () => {
  // O critério é COMPORTAMENTO, não simetria. Este é o caso que quebra a
  // rodada — e perdoá-lo junto seria trocar um falso alarme por um silêncio
  // caro, que é a troca que este projeto não faz.
  const publicado = publicadoSaudavel();
  const ia = publicado.nodes.find((n) => n.name === 'IA Extrair');
  delete ia.credentials;

  assert.deepEqual(campos(conferir(publicado, REPO)), ['IA Extrair.credentials.httpHeaderAuth'],
    'nó LIGADO sem credencial falha na primeira execução — tem de acusar');
});

test('e o nó desabilitado volta a acusar se alguém o LIGAR no editor sem credencial', () => {
  // O perdão vale pelo estado PUBLICADO, não pelo do repositório: quem decide
  // se o nó executa em produção é o publicado.
  const publicado = publicadoSaudavel();
  const upload = publicado.nodes.find((n) => n.name === 'Upload Storage');
  delete upload.credentials;
  upload.disabled = false; // alguém ligou o nó à mão

  const achados = campos(conferir(publicado, REPO));
  assert.ok(achados.includes('Upload Storage.credentials.httpHeaderAuth'),
    'ligado e sem credencial: o perdão não vale mais');
  assert.ok(achados.includes('Upload Storage.disabled'),
    'e o próprio `disabled` divergente continua sendo acusado');
});

// ---------------------------------------------------------------------------
// A ESCOLHA DO ARQUIVO DO REPOSITÓRIO — a metade que não era testada.
//
// O `conferir()` acima sempre teve suíte. O que NÃO tinha era a pergunta anterior a ele:
// contra QUAL dos quatro workflows o publicado está sendo comparado? Até 16/09/2026 a resposta
// era "contra a ingestão, sempre", fixa no código — e o efeito, MEDIDO antes da correção,
// alimentando o próprio JSON commitado de cada workflow no script:
//
//     macro       55 divergências        erros          44 divergências
//     diagnóstico 46 divergências        ingestão       13 (estas legítimas: `REPLACE` em nó ligado)
//
// As 145 primeiras eram FALSAS: o conferidor comparava dois workflows diferentes e relatava a
// diferença entre eles como se fosse deriva da publicação. Três dos quatro workflows não tinham
// conferência nenhuma; o quarto tinha uma que mentia quando apontada para o alvo errado.
// Pior que não conferir, porque parece trabalho a fazer.

test('cada workflow publicado escolhe o SEU arquivo do repositório, pelo `name`', () => {
  for (const caminho of WORKFLOWS_DO_REPO) {
    const doRepo = JSON.parse(readFileSync(resolve(RAIZ_REPO, caminho), 'utf8'));
    const escolhido = escolherDoRepo({ name: doRepo.name, nodes: [], connections: {} });
    assert.equal(escolhido?.caminho, caminho, `o workflow "${doRepo.name}" foi parar em ${escolhido?.caminho}`);
  }
});

test('MEDIDO em produção (01/10/2026): o nome PUBLICADO de cada workflow acha o seu arquivo', () => {
  // Os nomes abaixo são os que `GET /api/v1/workflows` devolveu da instância real. O dono
  // renomeou dois deles no editor ("Oria SARF — …") e o repositório ficou com o nome antigo:
  // o conferidor respondia "não sei contra qual conferir" e esses dois nunca eram conferidos.
  const publicados = {
    'Oria SARF — Reportar Erros': 'N8N/workflow.erros.json',
    'Oria SARF — Índices Macroeconômicos': 'N8N/workflow.macro.json',
    'Oria — SARF (Sistema Automático de Reestruturação Financeira)': 'N8N/workflow.e1-ingestao.json',
    'Oria — Diagnostico da conta OpenAI (1 token, custo ~zero)': 'N8N/workflow.diagnostico-ia.json',
  };
  for (const [nome, caminho] of Object.entries(publicados)) {
    assert.equal(escolherDoRepo({ name: nome })?.caminho, caminho, `"${nome}" não achou ${caminho}`);
  }
});

test('nome desconhecido devolve null — o conferidor NUNCA escolhe um alvo por padrão', () => {
  // É esta asserção que impede o retorno do defeito: um palpite produz uma lista de achados que
  // parece deriva da publicação e é só a diferença entre dois workflows distintos.
  assert.equal(escolherDoRepo({ name: 'Oria — um workflow que não existe aqui' }), null);
  assert.equal(escolherDoRepo({}), null);
  assert.equal(escolherDoRepo(null), null);
});

test('MEDIDO: o macro contra o arquivo ERRADO acusa dezenas; contra o seu, nenhuma', () => {
  const macro = JSON.parse(readFileSync(resolve(RAIZ_REPO, 'N8N/workflow.macro.json'), 'utf8'));
  const ingestao = JSON.parse(readFileSync(resolve(RAIZ_REPO, 'N8N/workflow.e1-ingestao.json'), 'utf8'));

  // O "publicado" é o do repositório com as credenciais já resolvidas, como a
  // republicação o deixa: o repositório grava `REPLACE`, e `REPLACE` em nó ligado
  // é divergência de verdade no publicado. Até 24/09/2026 este teste não precisava
  // disto porque o macro gravava `SUPABASE_PG`, um id que a trava não pegava.
  const publicado = structuredClone(macro);
  for (const n of publicado.nodes) for (const c of Object.values(n.credentials ?? {})) c.id = 'id-real-da-instancia';

  const contraOErrado = conferir(publicado, ingestao);
  const contraOSeu = conferir(publicado, escolherDoRepo(publicado).doRepo);

  assert.equal(contraOSeu.length, 0, 'o macro tem de bater consigo mesmo');
  assert.ok(contraOErrado.length > 20, `alvo errado deveria acusar dezenas, acusou ${contraOErrado.length}`);
});

// O `SUPABASE_PG` JÁ PUBLICADO. Até 24/09/2026 o gerador do macro gravava esse id
// nas três credenciais Postgres; se ele chegou à instalação (o n8n não casou a
// credencial pelo nome), o publicado o carrega e este conferidor não acusava nada,
// porque só punia `REPLACE`. Achado da revisão do PR #244: o conserto do
// repositório não alcança o que já está no ar.
test('o `SUPABASE_PG` antigo do macro num nó HABILITADO é divergência, como o REPLACE', () => {
  const vivo = publicadoSaudavel();
  vivo.nodes[1].credentials.httpHeaderAuth = { id: 'SUPABASE_PG', name: 'Google AI (Gemini)' };
  assert.deepEqual(campos(conferir(vivo, REPO)), ['IA Extrair.credentials.httpHeaderAuth.id']);
});
