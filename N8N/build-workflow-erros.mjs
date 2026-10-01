// Gera `workflow.erros.json` — o workflow que transforma QUALQUER falha do
// pipeline em linha no banco, para o portal poder mostrá-la.
//
// POR QUE ELE EXISTE, e por que é um workflow SEPARADO.
//
// O ramo de recusa do orçamento (no `workflow.e1-ingestao.json`) cobre UMA
// falha: a que o próprio código decide provocar. As outras — Postgres fora do
// ar, credencial da OpenAI vencida, binário que o n8n não consegue ler, um nó
// que lança por um caso que ninguém previu — não passam por lá. E o pedido do
// dono foi explícito: "quando der erro no processamento do sistema no n8n, seja
// por qualquer razão, ele reporte qual erro deu".
//
// "Qualquer razão" não se cobre nó a nó: cada `try/catch` novo cobre o erro que
// alguém imaginou, e o próximo erro é sempre o que ninguém imaginou. O n8n tem o
// mecanismo certo para isso — o **Error Workflow**: um workflow que ele executa
// AUTOMATICAMENTE quando outro falha, recebendo o que quebrou, em qual nó, e a
// mensagem. É a única forma de cobrir o erro que ainda não aconteceu.
//
// COMO LIGAR (uma vez, e o passo é do dono — ver `N8N/README.md`):
//   1. importar `workflow.erros.json` no n8n;
//   2. abrir o `Intake Oria — E1`, menu ⋯ → Settings → **Error Workflow** →
//      escolher "Oria SARF — Reportar Erros";
//   3. salvar. A partir daí toda falha daquele workflow cai aqui.
//
// O QUE ELE FAZ, e o que deliberadamente NÃO faz: grava a falha e para. Não
// tenta reprocessar, não notifica, não decide nada. Reprocessar automaticamente
// um lote que falhou por causa desconhecida é a receita para gastar duas vezes
// e registrar metade — a doutrina deste projeto (Arquitetura do Sistema/1 Visão e Doutrina/01) manda o humano
// decidir, e para decidir ele precisa primeiro SABER, que é o que faltava.

import { posicionar } from './layout.mjs';
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const AQUI = dirname(fileURLToPath(import.meta.url));

const PG_CRED = { postgres: { id: 'REPLACE', name: 'Supabase Postgres' } };

// O NOME DO CASO SAI DO QUE O ERRO CARREGA, e pode não estar lá.
//
// O `Error Trigger` do n8n entrega a execução que falhou, e dentro dela o que
// tiver sobrado: em falha logo no começo (o formulário nem chegou ao banco), não
// há `caso_id` nenhum. Por isso a função de registro aceita id nulo e casa
// TAMBÉM pelo nome do mandato — falha órfã é falha invisível, e invisível é
// exatamente o que este workflow existe para acabar.
const CODE_EXTRAIR = `
const e = $input.first().json;
const exec = e.execution || {};
const wf = e.workflow || {};

// O n8n põe o dado do último nó que rodou em lugares diferentes conforme o modo
// de falha. Procurar em todos os caminhos plausíveis é mais robusto que apostar
// num — é a mesma decisão que \`diagnosticarErroApi\` já toma em lib/extract.mjs.
const dados = exec.lastNodeExecuted && exec.data && exec.data.resultData
  ? (exec.data.resultData.runData || {})
  : {};
let caso_id = null, mandato = null;
for (const nome of Object.keys(dados)) {
  for (const rodada of (dados[nome] || [])) {
    const itens = ((rodada.data || {}).main || [])[0] || [];
    for (const it of itens) {
      const j = (it || {}).json || {};
      if (!caso_id && j.caso_id) caso_id = j.caso_id;
      if (!mandato && j['Mandato (nome do caso)']) mandato = j['Mandato (nome do caso)'];
    }
  }
}

const etapa = exec.lastNodeExecuted || 'desconhecida';
const mensagem = (exec.error && (exec.error.message || exec.error.description))
  || 'O processamento parou sem mensagem de erro.';

return [{ json: {
  caso_id,
  mandato,
  etapa,
  mensagem,
  detalhe: {
    workflow: wf.name || null,
    execucao_id: exec.id || null,
    url: exec.url || null,
    modo: exec.mode || null,
  },
} }];
`.trim();

// `position` é [0, 0] em todos: quem desenha o canvas é `posicionar()`
// (N8N/layout.mjs), a partir das conexões, logo abaixo.
const nodes = [
  {
    parameters: {},
    id: 'erro-trigger',
    name: 'Quando algo falha',
    type: 'n8n-nodes-base.errorTrigger',
    typeVersion: 1,
    position: [0, 0],
  },
  {
    parameters: { mode: 'runOnceForAllItems', jsCode: CODE_EXTRAIR },
    id: 'erro-extrair',
    name: 'Extrair Causa',
    type: 'n8n-nodes-base.code',
    typeVersion: 2,
    position: [0, 0],
  },
  {
    parameters: {
      operation: 'executeQuery',
      query: 'select fn_registrar_falha_execucao($1::uuid, $2::text, $3::text, $4::text, $5::jsonb) as r',
      options: {
        queryReplacement:
          '={{ [$json.caso_id, $json.mandato, $json.etapa, $json.mensagem, JSON.stringify($json.detalhe)] }}',
      },
    },
    id: 'erro-gravar',
    name: 'Registrar Falha',
    type: 'n8n-nodes-base.postgres',
    typeVersion: 2.5,
    position: [0, 0],
    credentials: PG_CRED,
    // Sem retry: se o banco também estiver fora, insistir aqui só atrasa. A
    // falha continua visível no n8n, que é o degrau de baixo desta escada.
  },
];

const connections = {
  'Quando algo falha': { main: [[{ node: 'Extrair Causa', type: 'main', index: 0 }]] },
  'Extrair Causa': { main: [[{ node: 'Registrar Falha', type: 'main', index: 0 }]] },
};

posicionar(nodes, connections);

const workflow = {
  // O NOME É O QUE ESTÁ PUBLICADO (medido em 01/10/2026 pela API do n8n): o dono
  // renomeou no editor para "Oria SARF — …", e o repositório seguiu com o nome
  // antigo. O custo era duplo: `conferir-publicado.mjs` escolhe o arquivo pelo
  // nome e devolvia "não sei contra qual conferir" (o workflow nunca era
  // conferido), e o PUT da republicação leva o `name` — republicar desfaria o
  // nome que o dono deu.
  name: 'Oria SARF — Reportar Erros',
  nodes,
  connections,
  settings: { executionOrder: 'v1' },
};

const destino = join(AQUI, 'workflow.erros.json');
writeFileSync(destino, `${JSON.stringify(workflow, null, 2)}\n`);
console.log(`workflow.erros.json gravado (${workflow.nodes.length} nós).`);
