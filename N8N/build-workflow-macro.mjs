// Gerador do workflow de ÍNDICES MACROECONÔMICOS (Supabase/migrations/0025).
//
// Workflow separado do de ingestão de propósito: ele não tem nada a ver com
// documento de mandato. Roda no relógio (diário), não no upload; falha dele não
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
import {
  SERIES_MACRO, INDICADORES_FOCUS, urlSgs, urlFocus, urlSidraIpca, numeroMacro,
  lerRespostaHttp, consultaSgs, consultaFocus, consultaSidra,
  JUROS_PJ_SGS, urlSgsUltimos, itensJuros,
  SGS_EXTRA, JANELA_SGS_EXTRA, itensSgsExtra,
  SIDRA_SETORIAL, urlSidraSetorial, consultaSidraSetorial, mesFinalSidra,
} from './lib/macro.mjs';

// `numeroMacro` EMBUTIDA do fonte, não copiada à mão. É o padrão que o gerador da
// ingestão já usa cinco vezes (prompt, ALIASES, diagnosticarErroApi, parseEntidade,
// orçamento) exatamente porque a cópia à mão deste repositório já divergiu — e este
// arquivo era o último mirror manual que restava.
const FONTE_NUMERO_MACRO = `const numeroMacro = ${numeroMacro.toString()};`;

// Idem para o registro da consulta (A3 fatia 0): as funções que montam o desfecho
// cru de cada chamada HTTP moram em lib/macro.mjs e são embutidas por toString.
const FONTE_CONSULTA = [numeroMacro, lerRespostaHttp].map((f) => f.toString()).join('\n');
const embutir = (...fns) => [FONTE_CONSULTA, ...fns.map((f) => f.toString())].join('\n');

const __dirname = dirname(fileURLToPath(import.meta.url));

// Sem `position` à mão: o canvas sai de `posicionar()` (N8N/layout.mjs) a partir
// das `connections`, depois que a lista existe inteira.
const node = (name, type, typeVersion, parameters, opts = {}) => ({
  parameters, id: name.toLowerCase().replace(/[^a-z0-9]+/g, '-'), name, type, typeVersion,
  position: [0, 0],
  ...(opts.credentials ? { credentials: opts.credentials } : {}),
  ...(opts.onError ? { onError: opts.onError } : {}),
  ...(opts.alwaysOutputData ? { alwaysOutputData: true } : {}),
  ...(opts.retryOnFail ? { retryOnFail: true, maxTries: opts.maxTries ?? 3, waitBetweenTries: 5000 } : {}),
});

// As APIs do BCB e do IBGE são públicas e sem chave, mas caem. `onError:
// continueRegularOutput` + retry: uma série indisponível não pode derrubar a
// coleta das outras — o mês volta na execução seguinte (a ingestão é
// idempotente por (serie, fonte, data_ref)).
const HTTP_TOLERANTE = { onError: 'continueRegularOutput', retryOnFail: true, maxTries: 3 };

// O nó HTTP entrega UM item por chamada com { statusCode, body: TEXTO CRU }:
//   - fullResponse: o status real chega (sem ele um 500 virava "corpo de erro" anônimo);
//   - responseFormat text: o corpo exato é a prova de leitura (o banco grava o sha256
//     dele) e o array do SGS deixa de ser explodido em ~132 itens por série (o que
//     obrigava o parse a adivinhar de qual chamada cada item veio);
//   - neverError: 4xx/5xx chegam como statusCode em vez de exceção;
//   - timeout 60 s: chamada que nunca responde vira { error } (status nulo -> falhou)
//     em vez de pendurar a execução.
//   - outputPropertyName EXPLÍCITO: com text + fullResponse o corpo NÃO vai em "body", vai
//     neste campo (default "data" no HttpRequestV3, typeVersion 4.2). Fixar aqui e passar o
//     mesmo nome aos nós Ler (CAMPO) impede que uma troca de default quebre a leitura em
//     silêncio: o teste lê o campo DESTA opção no JSON gerado.
const CAMPO_CORPO = 'corpo_cru';
const CAMPO = JSON.stringify(CAMPO_CORPO);
const HTTP_OPCOES = {
  response: { response: { fullResponse: true, neverError: true, responseFormat: 'text', outputPropertyName: CAMPO_CORPO } },
  timeout: 60000,
};

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

// Registro da consulta pelo ponto ÚNICO de escrita (0303). O parâmetro é UM jsonb (o
// mesmo padrão de Gravar Índices): o corpo cru tem vírgula e o n8n separaria um
// queryReplacement com vírgula em vários parâmetros. p_caso e p_alvo_cnpj nulos e
// p_custo 0: fonte de mercado, gratuita. O nullif devolve SQL NULL para itens JSON
// null (p->'itens' de um null JSON seria o jsonb 'null', não NULL).
const SQL_CONSULTA = "select fn_registrar_consulta_externa(q.p->>'fonte', null, null, (q.p->>'http_status')::int, q.p->>'erro', q.p->>'corpo', "
  + "nullif(q.p->'itens', 'null'::jsonb), (q.p->>'registros_lidos')::int, 0) as consulta from (select $1::jsonb as p) q";

// Registrar a consulta NUNCA derruba o caminho dos dados: erro vira item (continueRegularOutput),
// e alwaysOutputData garante saída mesmo sem linha, para o fluxo seguir.
const PG_CONSULTA = { ...PG, alwaysOutputData: true };

const nodes = [
  node('Agenda Diária', 'n8n-nodes-base.scheduleTrigger', 1.2, {
    rule: { interval: [{ field: 'days', daysInterval: 1, triggerAtHour: 6 }] },
  }),

  // DIÁRIO (decisão do dono, 25/11/2026), era mensal no dia 12. Medido em 25/11: o
  // IPCA de outubro já estava na API do SGS (0,14) e só entraria em 12/12 — até 17
  // dias de atraso. Diário também faz cada execução ser um sinal de vida: o banco
  // passa a ter 12 consultas por dia (consulta_externa), e a ausência de uma delas
  // é o que distingue "não rodou" de "rodou e não achou nada" (regra 7).
  // O motivo do dia 12 (esperar o IBGE publicar o IPCA para a conferência entre
  // fontes não acusar atraso) não some: fn_divergencias_indice_macro só compara
  // meses presentes nas DUAS fontes, então mês só numa delas não é divergência.

  node('Séries a Coletar', 'n8n-nodes-base.code', 2, {
    jsCode: `return ${JSON.stringify(
      SERIES_MACRO.map((s) => ({ json: { __serie: s.codigo, __url: urlSgs(s.sgs, { hoje: INICIO_HISTORICO_REF }) } })),
    )};`,
  }),

  node('BCB SGS', 'n8n-nodes-base.httpRequest', 4.2, {
    url: '={{ $json.__url }}', options: HTTP_OPCOES,
  }, HTTP_TOLERANTE),

  // UMA consulta por SÉRIE chamada (6 por execução), não uma por execução: com uma só,
  // o 200 das cinco séries boas esconderia o 500 da sexta. Cada série tem o seu
  // desfecho, e a que caiu aparece como falhou com o status dela.
  node('Ler SGS', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForEachItem',
    jsCode: embutir(consultaSgs) + `
let serie = null;
try { serie = $('Séries a Coletar').item.json.__serie; } catch (e) { serie = null; }
const c = consultaSgs($json, serie || 'SGS', { campo: ${CAMPO} });
return { json: { __serie: serie, __fonte: 'BCB/SGS', __corpo: c.dado, __consulta: c.consulta } };`,
  }),

  node('Registrar Consulta SGS', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery', query: SQL_CONSULTA,
    options: { queryBatching: 'independently', queryReplacement: '={{ JSON.stringify($json.__consulta) }}' },
  }, PG_CONSULTA),

  // Retoma o caminho dos DADOS depois do registro. Lê o 'Ler SGS' pelo nome e não o
  // que o registro devolveu: assim a gravação não depende do resultado do registro
  // (que continua mesmo se o banco recusar a consulta), e a falha do Normalizar,
  // que lança de propósito, só acontece DEPOIS de a consulta já estar gravada.
  node('Manter Contexto SGS', 'n8n-nodes-base.code', 2, {
    jsCode: "return $('Ler SGS').all().map((i) => ({ json: { __serie: i.json.__serie, __fonte: i.json.__fonte, __corpo: i.json.__corpo } }));",
  }),

  node('IBGE SIDRA (IPCA)', 'n8n-nodes-base.httpRequest', 4.2, {
    url: urlSidraIpca({ ultimos: MESES_HISTORICO }),
    options: HTTP_OPCOES,
  }, HTTP_TOLERANTE),

  node('Ler SIDRA', 'n8n-nodes-base.code', 2, {
    jsCode: embutir(consultaSidra) + `
const c = consultaSidra(($input.all()[0] || {}).json, { campo: ${CAMPO} });
return [{ json: { __serie: 'IPCA', __fonte: 'IBGE/SIDRA', __corpo: c.dado, __consulta: c.consulta } }];`,
  }),

  node('Registrar Consulta SIDRA', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery', query: SQL_CONSULTA,
    options: { queryBatching: 'independently', queryReplacement: '={{ JSON.stringify($json.__consulta) }}' },
  }, PG_CONSULTA),

  node('Marcar Fonte IBGE', 'n8n-nodes-base.code', 2, {
    jsCode: "return $('Ler SIDRA').all().map((i) => ({ json: { __serie: i.json.__serie, __fonte: i.json.__fonte, __corpo: i.json.__corpo } }));",
  }),

  // A3 fatia 1: taxa média de juros por modalidade PJ (BCB/SGS), fonte bcb_juros_modalidade.
  // No MESMO workflow diário (um gatilho, uma credencial, um lugar para o dono olhar), mas
  // numa corrente PRÓPRIA e só de registro: os dados vão para fato_externo, não para
  // indice_macro_obs (a aba Macro do cliente não muda; é a A5). Uma consulta por série, e a
  // lista (19 de 24 códigos) e a janela de 2 meses estão justificadas em lib/macro.mjs.
  node('Séries Juros', 'n8n-nodes-base.code', 2, {
    jsCode: `return ${JSON.stringify(
      JUROS_PJ_SGS.map((s) => ({ json: { __sgs: s.sgs, __nome: s.nome, __url: urlSgsUltimos(s.sgs) } })),
    )};`,
  }),

  node('BCB Juros', 'n8n-nodes-base.httpRequest', 4.2, {
    url: '={{ $json.__url }}', options: HTTP_OPCOES,
  }, HTTP_TOLERANTE),

  node('Ler Juros', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForEachItem',
    jsCode: embutir(consultaSgs, itensJuros) + `
let ctx = {};
try { ctx = $('Séries Juros').item.json; } catch (e) { ctx = {}; }
const c = consultaSgs($json, 'sgs:' + ctx.__sgs, { campo: ${CAMPO}, fonte: 'bcb_juros_modalidade', itens: itensJuros(ctx.__sgs, ctx.__nome) });
if (!ctx.__sgs && !c.consulta.erro) c.consulta.erro = 'não foi possível identificar a série desta chamada';
return { json: { __consulta: c.consulta } };`,
  }),

  node('Registrar Consulta Juros', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery', query: SQL_CONSULTA,
    options: { queryBatching: 'independently', queryReplacement: '={{ JSON.stringify($json.__consulta) }}' },
  }, PG_CONSULTA),

  node('Chamar SIDRA', 'n8n-nodes-base.code', 2, { jsCode: 'return [{ json: {} }];' }),

  node('Retomar Dados', 'n8n-nodes-base.code', 2, { jsCode: 'return [{ json: {} }];' }),

  // A3 fatia 2: IBC-Br, crédito/inadimplência PJ e euro (BCB/SGS, fonte bcb_sgs) -> fato_externo.
  // Mesmo desenho dos juros: uma consulta por série, só registro, na corrente linear ANTES de
  // qualquer nó que lance. A lista (só série com nome confirmado), a janela por periodicidade
  // e a unidade de cada uma estão justificadas em lib/macro.mjs.
  node('Séries SGS Extra', 'n8n-nodes-base.code', 2, {
    jsCode: `return ${JSON.stringify(
      SGS_EXTRA.map((s) => ({ json: {
        __sgs: s.sgs, __meta: { nome: s.nome, natureza: s.natureza, unidade: s.unidade, periodicidade: s.periodicidade },
        __url: urlSgsUltimos(s.sgs, JANELA_SGS_EXTRA[s.periodicidade]),
      } })),
    )};`,
  }),

  node('BCB SGS Extra', 'n8n-nodes-base.httpRequest', 4.2, {
    url: '={{ $json.__url }}', options: HTTP_OPCOES,
  }, HTTP_TOLERANTE),

  node('Ler SGS Extra', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForEachItem',
    jsCode: embutir(consultaSgs, itensSgsExtra) + `
let ctx = {};
try { ctx = $('Séries SGS Extra').item.json; } catch (e) { ctx = {}; }
const c = consultaSgs($json, 'sgs:' + ctx.__sgs, { campo: ${CAMPO}, itens: itensSgsExtra(ctx.__sgs, ctx.__meta || {}) });
if (!ctx.__sgs && !c.consulta.erro) c.consulta.erro = 'não foi possível identificar a série desta chamada';
return { json: { __consulta: c.consulta } };`,
  }),

  node('Registrar Consulta SGS Extra', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery', query: SQL_CONSULTA,
    options: { queryBatching: 'independently', queryReplacement: '={{ JSON.stringify($json.__consulta) }}' },
  }, PG_CONSULTA),

  // A3 fatia 4: IBGE/SIDRA setorial (PIB, indústria, varejo, serviços, emprego) -> fato_externo.
  // Mesmo desenho: uma consulta por série (6), só registro, ANTES de qualquer nó que lance.
  // Fica logo depois do SGS Extra e antes de 'Séries a Coletar': é a continuação natural da
  // corrente de registro e todo nó que lança (Normalizar*) vem depois dela.
  node('Séries SIDRA Setorial', 'n8n-nodes-base.code', 2, {
    jsCode: `return ${JSON.stringify(
      SIDRA_SETORIAL.map((s) => ({ json: {
        __tabela: s.tabela, __variavel: s.variavel, __periodicidade: s.periodicidade, __agregados: s.agregados, __otica: s.otica || null, __url: urlSidraSetorial(s),
      } })),
    )};`,
  }),

  node('IBGE SIDRA Setorial', 'n8n-nodes-base.httpRequest', 4.2, {
    url: '={{ $json.__url }}', options: HTTP_OPCOES,
  }, HTTP_TOLERANTE),

  node('Ler SIDRA Setorial', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForEachItem',
    jsCode: embutir(consultaSidraSetorial, mesFinalSidra) + `
let ctx = {};
try { ctx = $('Séries SIDRA Setorial').item.json; } catch (e) { ctx = {}; }
const c = consultaSidraSetorial($json, { tabela: ctx.__tabela, variavel: ctx.__variavel, periodicidade: ctx.__periodicidade, agregados: ctx.__agregados, otica: ctx.__otica }, { campo: ${CAMPO} });
// Série não identificada: diz isso SEMPRE, inclusive quando a chamada também falhou (achado BAIXO
// da revisão de f5147ab: no não-2xx o motivo virava "SIDRA undefined/undefined: HTTP 500").
// Sem série, nenhum fato se grava: um fato sem tabela não diz o que mede.
if (!ctx.__tabela) {
  c.consulta.erro = 'não foi possível identificar a série desta chamada' + (c.consulta.erro ? ' (' + c.consulta.erro + ')' : '');
  c.consulta.itens = null;
}
return { json: { __consulta: c.consulta } };`,
  }),

  node('Registrar Consulta SIDRA Setorial', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery', query: SQL_CONSULTA,
    options: { queryBatching: 'independently', queryReplacement: '={{ JSON.stringify($json.__consulta) }}' },
  }, PG_CONSULTA),

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
    url: '={{ $json.__url }}', options: HTTP_OPCOES,
  }, HTTP_TOLERANTE),

  // Uma consulta por INDICADOR (5 por execução), pelo mesmo motivo do SGS.
  node('Ler Focus', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForEachItem',
    jsCode: embutir(consultaFocus) + `
let serie = null;
try { serie = $('Indicadores Focus').item.json.__serie; } catch (e) { serie = null; }
const c = consultaFocus($json, serie || 'Focus', { campo: ${CAMPO} });
return { json: { __serie: serie, __corpo: c.dado, __consulta: c.consulta } };`,
  }),

  node('Registrar Consulta Focus', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery', query: SQL_CONSULTA,
    options: { queryBatching: 'independently', queryReplacement: '={{ JSON.stringify($json.__consulta) }}' },
  }, PG_CONSULTA),

  node('Manter Contexto Focus', 'n8n-nodes-base.code', 2, {
    jsCode: "return $('Ler Focus').all().map((i) => ({ json: { __serie: i.json.__serie, __corpo: i.json.__corpo } }));",
  }),

  node('Normalizar Focus', 'n8n-nodes-base.code', 2, { jsCode: CODE_FOCUS }),

  node('Gravar Expectativas', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_registrar_expectativa_macro($1::jsonb) as n',
    options: { queryReplacement: '={{ JSON.stringify($json.expectativas) }}' },
  }, PG),
];

const liga = (...nomes) => ({ main: [nomes.map((node) => ({ node, type: 'main', index: 0 }))] });
// ORDEM DETERMINÍSTICA, por CORRENTE ÚNICA: todas as consultas (Juros, SGS, Focus, SIDRA) são
// registradas uma depois da outra, e SÓ ENTÃO os dados seguem para os normalizadores. Era o
// risco da fatia 1: com os ramos em paralelo a partir do gatilho, o throw do Normalizar (zero
// observação, de propósito) podia abortar a execução antes de outro ramo registrar a sua
// consulta, e a ordem entre ramos do n8n (executionOrder v1) vem da POSIÇÃO no canvas, não
// do grafo. Em corrente linear não há ramo concorrente: a ordem é a das arestas. Os dados
// são lidos pelo NOME do nó Ler (não pelo que o registro devolveu), então a corrente não os
// altera; o registro (onError continue + alwaysOutputData) nunca interrompe a corrente.
// Cada passo que alimenta um HTTP de chamada única passa por um nó Code (roda UMA vez,
// qualquer que seja o nº de itens que chegou), senão o HTTP rodaria uma vez por item.
const connections = {
  'Agenda Diária': liga('Séries Juros'),
  'Séries Juros': liga('BCB Juros'),
  'BCB Juros': liga('Ler Juros'),
  'Ler Juros': liga('Registrar Consulta Juros'),
  'Registrar Consulta Juros': liga('Séries SGS Extra'),
  'Séries SGS Extra': liga('BCB SGS Extra'),
  'BCB SGS Extra': liga('Ler SGS Extra'),
  'Ler SGS Extra': liga('Registrar Consulta SGS Extra'),
  'Registrar Consulta SGS Extra': liga('Séries SIDRA Setorial'),
  'Séries SIDRA Setorial': liga('IBGE SIDRA Setorial'),
  'IBGE SIDRA Setorial': liga('Ler SIDRA Setorial'),
  'Ler SIDRA Setorial': liga('Registrar Consulta SIDRA Setorial'),
  'Registrar Consulta SIDRA Setorial': liga('Séries a Coletar'),
  'Séries a Coletar': liga('BCB SGS'),
  'BCB SGS': liga('Ler SGS'),
  'Ler SGS': liga('Registrar Consulta SGS'),
  'Registrar Consulta SGS': liga('Indicadores Focus'),
  'Indicadores Focus': liga('BCB Focus'),
  'BCB Focus': liga('Ler Focus'),
  'Ler Focus': liga('Registrar Consulta Focus'),
  'Registrar Consulta Focus': liga('Chamar SIDRA'),
  'Chamar SIDRA': liga('IBGE SIDRA (IPCA)'),
  'IBGE SIDRA (IPCA)': liga('Ler SIDRA'),
  'Ler SIDRA': liga('Registrar Consulta SIDRA'),
  // Aqui TODAS as consultas já foram gravadas. Daqui em diante pode lançar.
  'Registrar Consulta SIDRA': liga('Retomar Dados'),
  'Retomar Dados': liga('Manter Contexto SGS', 'Marcar Fonte IBGE', 'Manter Contexto Focus'),
  'Manter Contexto SGS': liga('Normalizar Observações'),
  'Marcar Fonte IBGE': liga('Normalizar Observações'),
  'Normalizar Observações': liga('Gravar Índices'),
  'Gravar Índices': liga('Conferir Fontes'),
  'Manter Contexto Focus': liga('Normalizar Focus'),
  'Normalizar Focus': liga('Gravar Expectativas'),
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
    note: 'Gerado por N8N/build-workflow-macro.mjs. Coleta diária de IPCA/IGP-M/INPC/Selic/CDI/câmbio '
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
