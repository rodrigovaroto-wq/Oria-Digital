// Monta os quatro workflows da medição a partir dos nós desta pasta.
// Uso: node Leitor/medicao-n8n/montar.mjs <pasta de saída>
// Os JSON NÃO são versionados: são derivados destes arquivos.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const aqui = dirname(fileURLToPath(import.meta.url));
const saida = process.argv[2];
if (!saida) { console.error('uso: node montar.mjs <pasta de saída>'); process.exit(2); }
mkdirSync(saida, { recursive: true });
const ler = f => readFileSync(join(aqui, f), 'utf8');
const pos = (i) => [i * 220, 0];
const webhook = (path) => ({ parameters: { path, responseMode: 'lastNode', options: {} }, id: path + '-w', name: 'Webhook', type: 'n8n-nodes-base.webhook', typeVersion: 2, position: pos(0), webhookId: path });
const code = (name, js, mode = 'runOnceForEachItem', i = 2) => ({ parameters: { mode, jsCode: js }, id: name, name, type: 'n8n-nodes-base.code', typeVersion: 2, position: pos(i) });
const liga = (...nomes) => Object.fromEntries(nomes.slice(0, -1).map((n, i) => [n, { main: [[{ node: nomes[i + 1], type: 'main', index: 0 }]] }]));
const wf = (id, name, nodes, connections, save = 'all', active = true) => writeFileSync(join(saida, id + '.json'), JSON.stringify({ id, name, active, settings: { saveDataSuccessExecution: save, callerPolicy: 'any' }, nodes, connections }));

// 1. O caminho de hoje: HTTP Request baixa o arquivo inteiro como binário, o Code pega o Buffer.
wf('medirBinario001', 'medir-binario-inteiro', [
  webhook('binario'),
  { parameters: { url: "={{ 'http://127.0.0.1:8099/' + $json.query.arq }}", options: { response: { response: { responseFormat: 'file' } } } }, id: 'baixar', name: 'Baixar', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2, position: pos(1) },
  code('Envelope', ler('no-binario-inteiro.js')),
], liga('Webhook', 'Baixar', 'Envelope'));

// 2. O envelope por fatias de Range.
wf('medirFatias0001', 'medir-fatias', [webhook('fatias'), code('Envelope', ler('no-fatias-envelope.js'), 'runOnceForEachItem', 1)], liga('Webhook', 'Envelope'));

// 3. A carga no Postgres: o pai planeja as fatias, o sub-workflow lê e grava cada uma.
// Sub-workflow porque os dados de uma execução filha são soltos quando ela termina;
// num laço dentro da mesma execução, o runData de cada volta ficaria na memória.
wf('subFatia0000001', 'sub-fatia', [
  { parameters: { inputSource: 'passthrough' }, id: 'gatilho', name: 'Gatilho', type: 'n8n-nodes-base.executeWorkflowTrigger', typeVersion: 1.1, position: pos(0) },
  code('Ler Fatia', ler('no-ler-fatia.js'), 'runOnceForEachItem', 1),
  { parameters: { operation: 'executeQuery', query: 'select fn_carregar($1::bigint, $2::text) as linhas', options: { queryReplacement: '={{ [$json.ini, $json.texto] }}' } }, id: 'gravar', name: 'Gravar', type: 'n8n-nodes-base.postgres', typeVersion: 2.5, position: pos(2), credentials: { postgres: { id: 'pgMedir0000001', name: 'pg medir' } } },
], liga('Gatilho', 'Ler Fatia', 'Gravar'), 'none', false);
wf('carregar0000001', 'carregar', [
  webhook('carregar'),
  code('Planejar', ler('no-planejar.js'), 'runOnceForAllItems', 1),
  { parameters: { workflowId: { __rl: true, value: 'subFatia0000001', mode: 'id' }, mode: 'each', options: { waitForSubWorkflow: true } }, id: 'fatia', name: 'Fatia', type: 'n8n-nodes-base.executeWorkflow', typeVersion: 1.2, position: pos(2) },
  code('Somar', 'const n = $input.all().reduce((s, i) => s + Number(i.json.linhas), 0);\nreturn [{ json: { fatias: $input.all().length, linhas_gravadas: n } }];', 'runOnceForAllItems', 3),
], liga('Webhook', 'Planejar', 'Fatia', 'Somar'));
console.log('4 workflows em', saida);
