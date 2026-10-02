// Gerador do workflow de ÍNDICES MACROECONÔMICOS (Supabase/migrations/0025).
//
// Workflow separado do de ingestão de propósito: ele não tem nada a ver com
// documento de mandato. Roda no relógio (mensal), não no upload; falha dele não
// pode derrubar a ingestão; e o dono pode reimportar/desligar um sem tocar no
// outro.
//
// Mesma disciplina do `build-workflow.mjs`: a lógica de verdade vive em
// `lib/macro.mjs` (testada por `test/macro.test.mjs`) e os nós Code EMBUTEM
// aquele código — aqui as constantes são importadas de `lib/`, não copiadas à
// mão, que é a origem conhecida de mirror desatualizado neste repositório.

import { posicionar } from './layout.mjs';
import { renameSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SERIES_MACRO, INDICADORES_FOCUS, urlSgs, urlFocus, urlSidraIpca, numeroMacro } from './lib/macro.mjs';

// `numeroMacro` EMBUTIDA do fonte, não copiada à mão. É o padrão que o gerador da
// ingestão já usa cinco vezes (prompt, ALIASES, diagnosticarErroApi, parseEntidade,
// orçamento) exatamente porque a cópia à mão deste repositório já divergiu — e este
// arquivo era o último mirror manual que restava.
const FONTE_NUMERO_MACRO = `const numeroMacro = ${numeroMacro.toString()};`;

const __dirname = dirname(fileURLToPath(import.meta.url));

// Sem `position` à mão: o canvas sai de `posicionar()` (N8N/layout.mjs) a partir
// das `connections`, depois que a lista existe inteira.
const node = (name, type, typeVersion, parameters, opts = {}) => ({
  parameters, id: name.toLowerCase().replace(/[^a-z0-9]+/g, '-'), name, type, typeVersion,
  position: [0, 0],
  ...(opts.credentials ? { credentials: opts.credentials } : {}),
  ...(opts.onError ? { onError: opts.onError } : {}),
  ...(opts.retryOnFail ? { retryOnFail: true, maxTries: opts.maxTries ?? 3, waitBetweenTries: 5000 } : {}),
});

// As APIs do BCB e do IBGE são públicas e sem chave, mas caem. `onError:
// continueRegularOutput` + retry: uma série indisponível não pode derrubar a
// coleta das outras — o mês volta na execução seguinte (a ingestão é
// idempotente por (serie, fonte, data_ref)).
const HTTP_TOLERANTE = { onError: 'continueRegularOutput', retryOnFail: true, maxTries: 3 };

// 132 meses = 11 anos: cobre a média de 10 anos com folga para o ano corrente
// incompleto. Rebaixar a janela inteira todo mês é de propósito — é assim que
// uma REVISÃO de série feita pela fonte chega até nós.
const MESES_HISTORICO = 132;

// DATA DE REFERÊNCIA FIXA para a janela do SGS, e o motivo é que o gerador tem
// de ser DETERMINÍSTICO.
//
// Achado ao rodar o passo `git diff --exit-code` do CI num dia diferente do da
// última geração: a URL saía com `dataInicial=01/09/2015` em vez de
// `01/08/2015`, porque a janela era contada a partir de `new Date()`. O CI
// ficaria VERMELHO todo mês, sem nenhuma mudança de código — e um CI que fica
// vermelho por não-motivo é pior que CI nenhuma, porque ensina a ignorá-lo.
//
// Fixar não muda o comportamento em produção: o JSON é ESTÁTICO, então a
// janela já ficava congelada no instante da geração de qualquer jeito. O que
// muda é que agora ela é congelada num valor ESCOLHIDO e visível, não no dia
// em que alguém rodou o gerador. Para ampliar o histórico, mova esta data —
// e o diff dirá exatamente isso.
const INICIO_HISTORICO_REF = new Date(Date.UTC(2026, 6, 1)); // 2026-07 → janela a partir de 2015-08

// Espelho do parse (lib/macro.mjs). Comprimido porque nó Code do N8N não
// importa arquivo; a fonte da verdade continua sendo a lib, e os testes de
// `macro.test.mjs` cobrem o comportamento.
const CODE_NORMALIZAR = `
const SERIES = ${JSON.stringify(SERIES_MACRO.map((s) => ({ codigo: s.codigo, sgs: s.sgs })))};
function num(b){ if(typeof b==='number') return isFinite(b)?b:null;
  const t=String(b==null?'':b).trim(); if(!t) return null;
  const n=Number(t.includes(',')?t.replace(/\\./g,'').replace(',','.'):t); return isFinite(n)?n:null; }
function dataSgs(b){ const m=String(b==null?'':b).match(/^(\\d{2})\\/(\\d{2})\\/(\\d{4})$/);
  return m? m[3]+'-'+m[2]+'-'+m[1] : null; }
// O no' HTTP Request do n8n EXPLODE resposta JSON que e' array em N itens. O SGS
// devolve [{data,valor}, ...x132], entao 'Manter Contexto SGS' (runOnceForEachItem)
// recebe UM objeto por item e gravava __corpo = {data,valor} -- nao um array. O
// '!Array.isArray(corpo) continue' abaixo descartava TODOS os ~792 itens das 6
// series mensais, em silencio. Sobrevivia so' o ramo IBGE/SIDRA, que ja' remontava
// o array ($input.all().map(...)) porque e' UMA requisicao so'.
//
// Nao se remonta aqui de proposito: cada item ja' carrega o __serie CERTO, pelo
// pareamento de itens do n8n ($('Series a Coletar').item). Agrupar de novo por
// serie seria refazer, com risco, um trabalho que o n8n ja' fez.
//
// A distincao importa: corpo de ERRO da API tambem e' um objeto unico. Envolver
// qualquer objeto num array faria a falha virar "zero observacoes" -- o mesmo
// silencio, por outra porta. So' o que TEM CARA DE OBSERVACAO e' aceito; o resto
// e' contado em 'descartados', e e' esse numero que torna a falha visivel.
function ehObsSgs(o){ return !!o && typeof o==='object' && !Array.isArray(o) && ('data' in o) && ('valor' in o); }
function comoArray(c){ return Array.isArray(c) ? c : (ehObsSgs(c) ? [c] : null); }
const obs=[];
let descartados=0;
for (const item of $input.all()) {
  const j=item.json||{};
  const serie=j.__serie, corpo=comoArray(j.__corpo);
  if(!serie||!corpo){ descartados++; continue; }
  if(j.__fonte==='IBGE/SIDRA'){
    for(const o of corpo.slice(1)){
      const m=String(o&&o.D3C||'').match(/^(\\d{4})(\\d{2})$/);
      const v=num(o&&o.V);
      if(m&&v!==null) obs.push({serie:'IPCA',fonte:'IBGE/SIDRA',data_ref:m[1]+'-'+m[2]+'-01',valor:v});
    }
  } else {
    for(const o of corpo){
      const d=dataSgs(o&&o.data), v=num(o&&o.valor);
      if(d&&v!==null) obs.push({serie:serie,fonte:'BCB/SGS',data_ref:d,valor:v});
    }
  }
}
// FALHAR ALTO. Antes isto terminava em return com n:0 e NUNCA lancava: com
// neverError nos HTTP, falha de API virava corpo de erro, o continue engolia, a
// funcao do banco recebia '[]' e devolvia 0,0 -- e a execucao agendada fechava
// VERDE. O workflow roda dia 12; ninguem olha uma execucao verde.
//
// Zero observacao NUNCA e' resultado legitimo aqui: o SGS devolve os ultimos 132
// meses em toda chamada, entao "coletei e nada veio" significa que a resposta nao
// era o que se esperava. O padrao certo ja' existia no repositorio -- CODE_LISTAR
// do gerador da ingestao lanca quando o formulario vem sem arquivo -- e estava
// aplicado so' la'.
//
// A mensagem carrega o que foi VISTO, nao so' o que faltou: quantos itens
// chegaram, quantos foram descartados e uma amostra do corpo. Sem isso o proximo
// diagnostico recomeca do zero, que foi o custo do v30.
if (obs.length === 0) {
  const amostra = JSON.stringify(($input.all()[0] || {}).json || {}).slice(0, 400);
  throw new Error('Coleta de indices macro NAO trouxe observacao nenhuma. Itens recebidos: '
    + $input.all().length + ', descartados: ' + descartados
    + '. Zero nunca e resultado legitimo aqui (o SGS devolve 132 meses por chamada), '
    + 'entao a resposta nao era o esperado. Primeiro item recebido: ' + amostra);
}
// 'descartados' sai no payload de proposito: e' o unico numero que distingue
// "coletou e nao mudou nada" de "a API respondeu outra coisa e nada foi lido".
return [{ json: { observacoes: obs, n: obs.length, descartados } }];
`.trim();

const CODE_FOCUS = `
${FONTE_NUMERO_MACRO}
const obs=[];
for (const item of $input.all()) {
  const j=item.json||{};
  const serie=j.__serie;
  const linhas=(j.__corpo&&j.__corpo.value)||[];
  if(!serie||linhas.length===0) continue;
  // Só a coleta MAIS RECENTE: a API devolve o histórico inteiro de boletins e
  // misturar duas semanas daria dois números para o mesmo ano.
  let recente=''; for(const l of linhas){ if(l&&l.Data>recente) recente=l.Data; }
  const vistos={};
  for(const l of linhas){
    if(!l||l.Data!==recente) continue;
    const ano=Number(l.DataReferencia);
    // MIRROR que JA' DIVERGIU: o no' fazia typeof l.Mediana==='number' ? ... : null,
    // rejeitando QUALQUER string -- inclusive "4.50". A lib usa numeroMacro, que
    // aceita string e vírgula decimal. Medido: no' devolvia {n:0} onde a lib
    // devolvia 2 expectativas.
    //
    // Hoje o Olinda entrega numero (o seed versionado nao tem um null de
    // respondentes), entao isto era fragilidade LATENTE, nao a causa atual. Mas se
    // a API passar a serializar decimal como string, todo o ramo Focus zera em
    // silencio e as premissas de inflacao/juro da Modelagem vao a 0%.
    const mediana=numeroMacro(l.Mediana);
    if(!Number.isInteger(ano)||mediana===null||vistos[ano]) continue;
    vistos[ano]=1;
    obs.push({serie:serie,ano_ref:ano,mediana:mediana,
      media:numeroMacro(l.Media),
      respondentes:numeroMacro(l.numeroRespondentes),
      coletado_em:recente});
  }
}
// Mesmo motivo do lado das observacoes: o Focus publica boletim toda semana, e
// zero expectativa significa resposta inesperada, nao "nada novo". Sem o throw,
// as premissas de inflacao e juro da aba Modelagem vao a 0% com nota afirmando que
// vieram do Boletim Focus -- mentira que fecha o EBITDA bonito.
if (obs.length === 0) {
  const amostra = JSON.stringify(($input.all()[0] || {}).json || {}).slice(0, 400);
  throw new Error('Coleta de expectativas Focus NAO trouxe nada. Itens recebidos: '
    + $input.all().length + '. Zero nunca e resultado legitimo aqui (o Focus publica '
    + 'boletim semanal), entao a resposta nao era o esperado. Primeiro item: ' + amostra);
}
return [{ json: { expectativas: obs, n: obs.length } }];
`.trim();

// `REPLACE`, como nos outros três geradores: é a única marca que a trava 2 do
// `republicar.sh` procura. Com `SUPABASE_PG` aqui (até 24/09/2026), o macro
// republicado numa instância sem essa credencial saía com um id inexistente e
// passava pela trava, porque `ehIdUtilizavel` o aceita como real.
const PG = { credentials: { postgres: { id: 'REPLACE', name: 'Supabase Postgres' } },
  onError: 'continueRegularOutput', retryOnFail: true, maxTries: 3 };

const nodes = [
  node('Agenda Mensal', 'n8n-nodes-base.scheduleTrigger', 1.2, {
    rule: { interval: [{ field: 'months', triggerAtDayOfMonth: 12, triggerAtHour: 6 }] },
  }),

  // Dia 12 e não dia 1: o IPCA do mês anterior é divulgado pelo IBGE por volta
  // do dia 10. Coletar antes disso traria o mês sempre incompleto e faria a
  // conferência entre fontes acusar divergência todo mês por atraso de
  // publicação, não por erro.

  node('Séries a Coletar', 'n8n-nodes-base.code', 2, {
    jsCode: `return ${JSON.stringify(
      SERIES_MACRO.map((s) => ({ json: { __serie: s.codigo, __url: urlSgs(s.sgs, { hoje: INICIO_HISTORICO_REF }) } })),
    )};`,
  }),

  node('BCB SGS', 'n8n-nodes-base.httpRequest', 4.2, {
    url: '={{ $json.__url }}', options: { response: { response: { neverError: true } } },
  }, HTTP_TOLERANTE),

  node('Manter Contexto SGS', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForEachItem',
    jsCode: "return { json: { __serie: $('Séries a Coletar').item.json.__serie, __fonte: 'BCB/SGS', __corpo: $json } };",
  }),

  node('IBGE SIDRA (IPCA)', 'n8n-nodes-base.httpRequest', 4.2, {
    url: urlSidraIpca({ ultimos: MESES_HISTORICO }),
    options: { response: { response: { neverError: true } } },
  }, HTTP_TOLERANTE),

  node('Marcar Fonte IBGE', 'n8n-nodes-base.code', 2, {
    jsCode: "return [{ json: { __serie: 'IPCA', __fonte: 'IBGE/SIDRA', __corpo: $input.all().map(i => i.json) } }];",
  }),

  node('Normalizar Observações', 'n8n-nodes-base.code', 2, { jsCode: CODE_NORMALIZAR }),

  node('Gravar Índices', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select * from fn_registrar_indice_macro($1::jsonb)',
    options: { queryReplacement: '={{ JSON.stringify($json.observacoes) }}' },
  }, PG),

  node('Conferir Fontes', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    // A conferência é o que autoriza chamar o dado de validado. Ela não corrige
    // nada: registra a divergência para um humano decidir qual fonte vale.
    query: 'select * from fn_divergencias_indice_macro()',
  }, PG),

  node('Indicadores Focus', 'n8n-nodes-base.code', 2, {
    jsCode: `return ${JSON.stringify(
      // Sem `top` explícito: o número vive em `FOCUS_TOP` na lib, junto do
      // `baseCalculo`. Era 80 aqui e 40 no default da lib, e o seed (que usa o
      // default) truncava antes da produção — duas verdades para o mesmo número.
      INDICADORES_FOCUS.map((i) => ({ json: { __serie: i.codigo, __url: urlFocus(i.indicador) } })),
    )};`,
  }),

  node('BCB Focus', 'n8n-nodes-base.httpRequest', 4.2, {
    url: '={{ $json.__url }}', options: { response: { response: { neverError: true } } },
  }, HTTP_TOLERANTE),

  node('Manter Contexto Focus', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForEachItem',
    jsCode: "return { json: { __serie: $('Indicadores Focus').item.json.__serie, __corpo: $json } };",
  }),

  node('Normalizar Focus', 'n8n-nodes-base.code', 2, { jsCode: CODE_FOCUS }),

  node('Gravar Expectativas', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_registrar_expectativa_macro($1::jsonb) as n',
    options: { queryReplacement: '={{ JSON.stringify($json.expectativas) }}' },
  }, PG),
];

const connections = {
  'Agenda Mensal': { main: [[
    { node: 'Séries a Coletar', type: 'main', index: 0 },
    { node: 'IBGE SIDRA (IPCA)', type: 'main', index: 0 },
    { node: 'Indicadores Focus', type: 'main', index: 0 },
  ]] },
  'Séries a Coletar': { main: [[{ node: 'BCB SGS', type: 'main', index: 0 }]] },
  'BCB SGS': { main: [[{ node: 'Manter Contexto SGS', type: 'main', index: 0 }]] },
  'Manter Contexto SGS': { main: [[{ node: 'Normalizar Observações', type: 'main', index: 0 }]] },
  'IBGE SIDRA (IPCA)': { main: [[{ node: 'Marcar Fonte IBGE', type: 'main', index: 0 }]] },
  'Marcar Fonte IBGE': { main: [[{ node: 'Normalizar Observações', type: 'main', index: 0 }]] },
  'Normalizar Observações': { main: [[{ node: 'Gravar Índices', type: 'main', index: 0 }]] },
  'Gravar Índices': { main: [[{ node: 'Conferir Fontes', type: 'main', index: 0 }]] },
  'Indicadores Focus': { main: [[{ node: 'BCB Focus', type: 'main', index: 0 }]] },
  'BCB Focus': { main: [[{ node: 'Manter Contexto Focus', type: 'main', index: 0 }]] },
  'Manter Contexto Focus': { main: [[{ node: 'Normalizar Focus', type: 'main', index: 0 }]] },
  'Normalizar Focus': { main: [[{ node: 'Gravar Expectativas', type: 'main', index: 0 }]] },
};

// O canvas é desenhado a partir do grafo, nunca à mão (ver N8N/layout.mjs).
posicionar(nodes, connections);

const workflow = {
  // O nome publicado (medido em 01/10/2026; ver build-workflow-erros.mjs): o
  // dono renomeou no editor, e sem este alinhamento o conferidor não achava o
  // arquivo e a republicação desfaria o nome.
  name: 'Oria SARF — Índices Macroeconômicos',
  nodes, connections, settings: { executionOrder: 'v1' },
  meta: {
    note: 'Gerado por N8N/build-workflow-macro.mjs. Coleta mensal de IPCA/IGP-M/INPC/Selic/CDI/câmbio '
      + '(BCB/SGS), da expectativa Focus por ano e do IPCA no IBGE/SIDRA para conferência cruzada. '
      + 'A ingestão é idempotente por (serie, fonte, data_ref): rebaixar a janela toda vez é '
      + 'intencional — é assim que uma revisão de série feita pela fonte chega até nós.',
  },
};

// GRAVAÇÃO ATÔMICA (arquivo temporário + `rename`). `N8N/test/macro.test.mjs` roda
// ESTE gerador no meio da suíte, e o `node --test` executa os arquivos de teste em
// processos paralelos: `preparar-republicacao.test.mjs` lia o `workflow.macro.json`
// no instante em que o `writeFileSync` o tinha truncado e morria em "Unexpected end
// of JSON input" — 1 de 566 reprovado, medido no CI (PR #242) e de novo em
// 30/09/2026 numa passada local. `rename` no mesmo diretório troca o arquivo de uma
// vez: o leitor vê o antigo inteiro ou o novo inteiro, nunca a metade. O nome
// temporário começa com `.` para não casar `/^workflow\..+\.json$/` de quem lista a pasta.
const destino = join(__dirname, 'workflow.macro.json');
const temporario = join(__dirname, `.workflow.macro.json.${process.pid}.tmp`);
writeFileSync(temporario, JSON.stringify(workflow, null, 2) + '\n');
renameSync(temporario, destino);
console.log('Escrito workflow macro —', nodes.length, 'nós,', Object.keys(connections).length, 'conexões');
