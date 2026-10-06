// O ESPELHO ENTRE A LIB E O QUE RODA EM PRODUÇÃO — as 26 funções, não duas.
//
// POR QUE ESTE ARQUIVO EXISTE. Toda função de `N8N/lib/*.mjs` que a ingestão usa
// mora em DOIS lugares: a lib, que as outras suítes exercitam, e uma cópia
// LITERAL dentro do `build-workflow.mjs`, que vai para o JSON e é **a única que o
// n8n executa**. Nós de Code do n8n não importam módulo, então a duplicação é
// estrutural e não dá para remover.
//
// O que dava para remover era o SILÊNCIO: até aqui, corrigir a lib e esquecer a
// cópia deixava a suíte VERDE e a produção errada. Aconteceu duas vezes na mesma
// sessão — no `Math.max` da confiança de classificação (documento que a IA
// declarou ilegível entrava sem revisão) e no `parseCsv` sem aspas (o valor da
// última coluna virava pedaço de nome).
//
// A ESTRATÉGIA, e por que não é comparar o texto. As cópias são MINIFICADAS de
// propósito (`const L=String(t||'')...`), com nomes de variável próprios: comparar
// fonte reprovaria por formatação e convidaria a "consertar" formatando, que é o
// pior desfecho possível para um teste. Compara-se COMPORTAMENTO — a mesma
// entrada nas duas implementações, saída idêntica.
//
// E O ASSERT QUE FAZ ESTE ARQUIVO DURAR é o último: ele varre o workflow, lista
// TODA função duplicada e exige que cada uma esteja coberta aqui ou declarada em
// `SEM_CASO` com motivo. A 27ª função duplicada não entra em silêncio.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { normalize } from '../lib/normalize.mjs';
import { mergeClassification } from '../lib/merge.mjs';
import { spreadsheetToText, colunasDaPlanilha, avisoTruncamentoPlanilha } from '../lib/spreadsheet.mjs';
import { sha256Hex } from '../lib/hash.mjs';
import {
  byteEm, casaAssinatura, trechoLatin1, saborDoZip, abasDoXlsx, pareceTexto, contarFora,
  formaDoTexto, detectarFormato,
} from '../lib/formato.mjs';
import { xlsxMinimo } from './zip-minimo.mjs';
import { parseTipo, parsePeriodo, periodoAcumuladoNoAno, periodoDeIntervaloDeAnos, parseEntidade, parseAssinado, classifyByFilename } from '../lib/classifier.mjs';
import {
  avaliarCobertura, celulasDaLinha, celulasEstimadas, linhasComNumero, linhasDeConta,
  juntarFragmentosDeLinha, ehLinhaSemValor, ehLinhaDeConta,
  juntarFragmentosComOrigem, contasComOrigem, contasPorLinhaComNumero,
  linhasDaPassada, decidirSegundaPassada, melhorPassada, instrucaoDeSegundaPassada,
  planejarFatias, instrucaoDaFatia, juntarBlocos, camadaDeTextoDoPdf, fracaoDePalavrasDobradas,
} from '../lib/cobertura.mjs';
import {
  custoDaChamada, tokensDeSaida, bytesDoBinario, orcamentoDoLote,
  pesoDaChamadaDeClassificacao, custoEstimadoPorConteudo, orcamentoDoLotePorConteudo, instrucaoDeLevasDoLote,
  custoEstimadoPorTamanho, custoPorMbDeTextoUSD, estimativaDoDocumento,
  vereditoDaCotaDiaria,
  ehFormatoDeTexto,
} from '../lib/custo.mjs';
import {
  normalizarUnidade, normalizarMoeda, diagnosticarErroApi, decidirRepeticao, achatarGrupos,
  ehLinhaNaoMonetaria, escalaDeclaradaNaColuna, limparRotuloColado,
} from '../lib/extract.mjs';
import { ALIASES } from '../lib/taxonomia.mjs';

const WORKFLOW = JSON.parse(
  readFileSync(new URL('../workflow.e1-ingestao.json', import.meta.url), 'utf8'),
);

/**
 * Varredura léxica do JS: devolve, para cada posição, se ela está em código de
 * verdade ou dentro de string / template / regex / comentário.
 *
 * POR QUE PRECISA DISSO. A primeira versão casava chaves contando `{` e `}` no
 * texto cru, e quebrava na primeira regex com quantificador — `/\d{2,4}/` tem uma
 * chave que não fecha bloco nenhum. O resultado eram corpos truncados e
 * `SyntaxError` em metade das funções. Contar chave em JS exige saber onde o
 * código termina e o literal começa; não há atalho honesto.
 */
function mapaDeCodigo(src) {
  const codigo = new Uint8Array(src.length); // 1 = código, 0 = literal/comentário
  let i = 0;
  // O último caractere significativo decide se `/` abre regex ou é divisão.
  let anterior = '';
  while (i < src.length) {
    const c = src[i];
    const prox = src[i + 1];
    if (c === '/' && prox === '/') { while (i < src.length && src[i] !== '\n') i++; continue; }
    if (c === '/' && prox === '*') { i += 2; while (i < src.length && !(src[i] === '*' && src[i + 1] === '/')) i++; i += 2; continue; }
    if (c === '"' || c === "'" || c === '`') {
      const aspa = c; i++;
      while (i < src.length) {
        if (src[i] === '\\') { i += 2; continue; }
        if (src[i] === aspa) { i++; break; }
        i++;
      }
      anterior = aspa; continue;
    }
    if (c === '/' && /[(,=:[!&|?{};+\-*%~^<>]|^$/.test(anterior)) {
      i++; let emClasse = false;
      while (i < src.length) {
        if (src[i] === '\\') { i += 2; continue; }
        if (src[i] === '[') emClasse = true;
        else if (src[i] === ']') emClasse = false;
        else if (src[i] === '/' && !emClasse) { i++; break; }
        i++;
      }
      while (i < src.length && /[a-z]/.test(src[i])) i++; // flags
      anterior = '/'; continue;
    }
    codigo[i] = 1;
    if (!/\s/.test(c)) anterior = c;
    i++;
  }
  return codigo;
}

/** Fim do bloco `{...}` que começa em `abre`, contando só chaves de CÓDIGO. */
function fimDoBloco(src, codigo, abre) {
  let prof = 0;
  for (let i = abre; i < src.length; i++) {
    if (!codigo[i]) continue;
    if (src[i] === '{') prof++;
    else if (src[i] === '}') { prof--; if (prof === 0) return i + 1; }
  }
  return -1;
}

/**
 * As DECLARAÇÕES de topo de um nó: o TEXTO delas, em ordem, e os nomes que são
 * função.
 *
 * DUAS FORMAS, e ignorar a segunda custou uma volta. O `build-workflow.mjs`
 * embute a maioria das funções como `const nome = function nome(...) {...};` —
 * expressão nomeada atribuída a uma constante, não declaração. Um extrator que
 * só reconhece `function nome(` acha 11 das 32 e conclui, errado, que as outras
 * "não estão no workflow".
 *
 * As constantes entram junto porque várias funções as usam — `parseTipo` lê a
 * tabela de tipos declarada acima dela. O que fica DE FORA é toda declaração que
 * toca `$(...)`, `$input`, `item` ou `items`: essas são o corpo do nó, existem só
 * dentro do n8n, e avaliá-las aqui derrubaria o teste por um motivo que não é
 * divergência.
 */
function declaracoesDeTopo(src) {
  const codigo = mapaDeCodigo(src);
  const nomes = new Map(); // nome da lib -> como chamá-lo no sandbox
  const partes = [];
  let i = 0, prof = 0;
  while (i < src.length) {
    if (!codigo[i]) { i++; continue; }
    const c = src[i];
    if (c === '{') { prof++; i++; continue; }
    if (c === '}') { prof--; i++; continue; }
    if (prof === 0) {
      const resto = src.slice(i);
      const mFn = /^(?:async\s+)?function\s+([A-Za-z_$][\w$]*)\s*\(/.exec(resto);
      if (mFn) {
        const fim = fimDoBloco(src, codigo, src.indexOf('{', i + mFn[0].length - 1));
        if (fim > 0) {
          partes.push({ nome: mFn[1], texto: src.slice(i, fim) });
          nomes.set(mFn[1], mFn[1]);
          i = fim; continue;
        }
      }
      const mDecl = /^(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=/.exec(resto);
      if (mDecl) {
        let j = i, p2 = 0;
        for (; j < src.length; j++) {
          if (!codigo[j]) continue;
          if ('{(['.includes(src[j])) p2++;
          else if ('})]'.includes(src[j])) p2--;
          else if (src[j] === ';' && p2 === 0) break;
        }
        const texto = src.slice(i, j + 1);
        // SÓ TABELA LITERAL ENTRA como constante.
        //
        // As funções embutidas precisam de tabelas — `ALIASES`, o preço por
        // modelo, a lista de ruído. O que elas NUNCA precisam é das variáveis de
        // trabalho do nó (`const t = normalize(nome);`), e arrastá-las custou
        // duas voltas: além de estourarem ao avaliar, os nomes delas COLIDEM com
        // parâmetros — `parseTipo(t)` cita `t`, e o fecho transitivo puxava a
        // variável do nó por causa do parâmetro. Literal não tem esse problema:
        // é dado, não depende de nada, e é exatamente o que uma tabela é.
        const ehLiteral = /^(?:const|let|var)\s+[A-Za-z_$][\w$]*\s*=\s*(?:\[|\{|'|"|`|\d|\/|new (?:Set|Map)\(|Object\.freeze\()/
          .test(texto);
        // `= (` NÃO BASTA PARA SER FUNÇÃO, e a folga custou uma investigação.
        // `const mt=(binMeta.mimeType||'').toLowerCase();` casava com o padrão
        // antigo e entrava no inventário como se fosse arrow — aí qualquer
        // função cujo corpo cite `mt` (e `detectarFormato` tem uma `mt` LOCAL)
        // arrastava a variável de trabalho do nó e estourava em `binMeta`.
        // Agora exige a seta de verdade, ou a palavra `function`.
        const ehFuncao = /^(?:const|let|var)\s+[A-Za-z_$][\w$]*\s*=\s*(?:async\s*)?(?:function\b|\([^)]*\)\s*=>|[A-Za-z_$][\w$]*\s*=>)/
          .test(texto);
        // O filtro de runtime vale para o INICIALIZADOR de constante comum, não
        // para o corpo de função: `diagnosticarErroApi` cita "item" numa frase de
        // comentário, e checar o texto inteiro a excluía do inventário.
        const usaRuntime = /\$\(|\$input|\$json|\bitems?\b|\bthis\b/.test(texto);
        if ((ehFuncao && !/\$\(|\$input|\$json/.test(texto)) || (ehLiteral && !usaRuntime)) {
          // `literal` marca TABELA (dado puro, sem dependência). A queda lá
          // embaixo precisa distinguir tabela de variável de trabalho.
          partes.push({ nome: mDecl[1], texto, literal: ehLiteral && !ehFuncao });
          // `const f = function f(){}` e `const f = (x) => …` são função para o
          // que este teste faz com elas: dá para chamar.
          if (ehFuncao) {
            nomes.set(mDecl[1], mDecl[1]);
            // `const normUnid = function normalizarUnidade(...)`: o nome da
            // CONSTANTE e o da FUNÇÃO diferem, e o segundo só existe dentro do
            // corpo dela. Quem procura pelo nome da lib tem de achar — pelo
            // acessor que funciona aqui fora, que é a constante.
            const mExpr = /=\s*(?:async\s*)?function\s+([A-Za-z_$][\w$]*)\s*\(/.exec(texto);
            if (mExpr && mExpr[1] !== mDecl[1]) nomes.set(mExpr[1], mDecl[1]);
          }
        }
        i = j + 1; continue;
      }
    }
    i++;
  }
  return { nomes, partes };
}

/** Toda função duplicada do workflow, com o nó em que ela vive. */
function inventarioDoWorkflow() {
  const inv = new Map();
  for (const no of WORKFLOW.nodes ?? []) {
    const src = no.parameters?.jsCode;
    if (typeof src !== 'string') continue;
    const { nomes, partes } = declaracoesDeTopo(src);
    for (const [nome, acessor] of nomes) if (!inv.has(nome)) inv.set(nome, { no: no.name, acessor, partes });
  }
  return inv;
}
const INVENTARIO = inventarioDoWorkflow();

/**
 * A implementação que o n8n executa, extraída do JSON COMMITADO.
 *
 * Leva TODAS as funções do mesmo nó junto — é mais barato que mapear dependência
 * a dependência à mão, e o custo de carregar uma função a mais é zero. O que NÃO
 * se leva é o corpo do nó fora das funções: lá há `$('Nó').item`, que não existe
 * fora do n8n e derrubaria a avaliação.
 */
function doWorkflow(nome) {
  const alvo = INVENTARIO.get(nome);
  assert.ok(alvo, `a função ${nome} não está em nenhum nó do workflow commitado`);
  // O FECHO TRANSITIVO, e não "junta tudo do nó e torce".
  //
  // Um nó declara, além das funções, constantes que dependem do CORPO dele
  // (`const aviso = binMeta.aviso_conteudo;`). Arrastá-las para o sandbox faz a
  // avaliação estourar por um motivo que não é divergência — e remendar isso com
  // uma lista de identificadores proibidos envelheceria a cada nó novo. Aqui só
  // entra o que a função ALVO alcança: começa nela e puxa, transitivamente, as
  // declarações cujos nomes ela cita. O resto do nó não é executado.
  const porNome = new Map(alvo.partes.map((p) => [p.nome, p]));
  const escolhidas = new Set();
  const fila = [alvo.acessor];
  while (fila.length > 0) {
    const atual = fila.pop();
    if (escolhidas.has(atual) || !porNome.has(atual)) continue;
    escolhidas.add(atual);
    const texto = porNome.get(atual).texto;
    for (const m of texto.matchAll(/[A-Za-z_$][\w$]*/g)) {
      if (porNome.has(m[0]) && !escolhidas.has(m[0])) fila.push(m[0]);
    }
  }
  const corpo = alvo.partes.filter((x) => escolhidas.has(x.nome)).map((x) => x.texto).join('\n');
  try {
    return new Function(`${corpo}\nreturn ${alvo.acessor};`)();
  } catch {
    // QUEDA PARA A FUNÇÃO SOZINHA. Boa parte delas é autossuficiente — não lê
    // tabela nenhuma —, e aí o fecho só pode atrapalhar: um parâmetro com nome
    // curto (`t`, `p`) coincide com uma variável de trabalho do nó e puxa junto
    // uma declaração que não compila fora do n8n. Se sozinha ela monta, é porque
    // dependência não havia.
    const soEla = alvo.partes.find((x) => x.nome === alvo.acessor);
    assert.ok(soEla, `não achei o texto de ${nome} no nó ${alvo.no}`);
    // MAS AS TABELAS VÃO JUNTO, e esta linha foi paga em 12/09/2026.
    //
    // A queda dizia "se sozinha ela monta, é porque dependência não havia". É
    // FALSO para quem lê tabela: em JS o nome só é resolvido na CHAMADA, então
    // `detectarFormato` monta sozinha e estoura `ASSINATURAS is not defined` ao
    // ser chamada — e o teste acusava divergência onde o nó de produção está
    // correto (lá `ASSINATURAS` é declarada, por `FONTE_FORMATO`).
    //
    // A causa de cair aqui é a colisão que o comentário acima já descreve: a
    // `mt` local de `detectarFormato` tem o mesmo nome de uma variável de
    // trabalho do `Preparar Conteudo`, o fecho a arrasta, e a avaliação morre.
    // Tabela literal é dado puro — não depende de nada, não colide com nada, e
    // sem ela a queda testa uma função que não roda.
    // UM FECHO PRÓPRIO, sobre o que é SEGURO levar.
    //
    // `função sozinha` não basta: em JS o nome só é resolvido na CHAMADA, então
    // `detectarFormato` MONTA sozinha e só estoura ao ser chamada — primeiro em
    // `ASSINATURAS` (tabela), depois em `casaAssinatura` (função). O teste
    // acusava divergência onde o nó de produção está correto: lá as duas são
    // declaradas, por `FONTE_FORMATO`.
    //
    // SEGURO = função, ou tabela em CAIXA_ALTA. O que fica de fora é a variável
    // de trabalho minúscula do corpo do nó (`const mt = binMeta.mimeType...`),
    // que é justamente quem derruba o fecho principal: a `mt` LOCAL de
    // `detectarFormato` colide com ela pelo nome. Injetar literal minúsculo
    // também sombreia parâmetro — medido, quebrou `parseEntidade`,
    // `mergeClassification` e `juntarBlocos` na primeira tentativa.
    const seguro = (x) => (x.literal ? /^[A-Z][A-Z0-9_]*$/.test(x.nome) : true);
    const porNomeSeguro = new Map(alvo.partes.filter(seguro).map((x) => [x.nome, x]));
    const levar = new Set();
    const pilha = [alvo.acessor];
    while (pilha.length > 0) {
      const atual = pilha.pop();
      if (levar.has(atual) || !porNomeSeguro.has(atual)) continue;
      levar.add(atual);
      for (const m of porNomeSeguro.get(atual).texto.matchAll(/[A-Za-z_$][\w$]*/g)) {
        if (porNomeSeguro.has(m[0]) && !levar.has(m[0])) pilha.push(m[0]);
      }
    }
    const corpoSeguro = alvo.partes.filter((x) => levar.has(x.nome)).map((x) => x.texto).join('\n');
    return new Function(`${corpoSeguro}\nreturn ${alvo.acessor};`)();
  }
}

// -----------------------------------------------------------------------------
// A TABELA. Cada entrada: a função da lib e as chamadas que a exercitam.
//
// Os casos não precisam ser exaustivos — as suítes próprias de cada lib já fazem
// isso. Aqui basta EXERCITAR os ramos: o que se mede é se as duas implementações
// concordam, e duas implementações que concordam em cinco entradas diferentes
// dificilmente divergem em silêncio na sexta.
// -----------------------------------------------------------------------------
const TABELA = [
  { nome: 'normalize', lib: normalize, casos: [['Balanço_2025.PDF'], ['a  b'], [null], ['']] },

  // A diferença de contrato que morava aqui (a cópia do workflow devolvia só o
  // `codigo`) acabou em 24/09/2026: o nó passou a embutir a `parseTipo` da lib
  // por `toString()`, junto com `classifyByFilename` — ver o comentário de
  // `FONTE_CLASSIFICADOR` em build-workflow.mjs.
  { nome: 'parseTipo', lib: parseTipo,
    casos: [['balanco patrimonial 2025'], ['dre 2025'], ['mapa de divida'], ['arquivo qualquer']] },
  { nome: 'periodoAcumuladoNoAno', lib: periodoAcumuladoNoAno, casos: [
    ['dre janaago26'], ['dre janeiro a agosto de 2026'], ['dre mar a ago 2026'], ['balanco 12m25'],
  ] },
  { nome: 'periodoDeIntervaloDeAnos', lib: periodoDeIntervaloDeAnos, casos: [
    ['balanco 2021-2025'], ['balanco 21 a 25'], ['balanco 2025'], ['balanco 2030-2025'],
  ] },
  { nome: 'parsePeriodo', lib: parsePeriodo,
    // O CRUZAMENTO DE SÉCULO ENTROU AQUI PORQUE A GUARDA JÁ DEIXOU PASSAR UMA
    // DIVERGÊNCIA REAL. A lib foi corrigida para ordenar o ano de QUATRO dígitos
    // antes de truncar (1999/2001 saíam como "01,99"), e o espelho inline em
    // `build-workflow.mjs` ficou com o `.sort()` antigo. Este espelho CONFERE
    // `parsePeriodo` desde sempre — e passou verde, porque nenhum dos cinco
    // casos tinha dois anos de séculos diferentes. Guarda que roda e não acha
    // tem a mesma aparência de guarda que não CONSEGUE achar
    // (`.claude/memory/estagio-desligado-parece-limpo.md`), e o que separa as
    // duas é a lista de casos exercitar o ramo que diverge.
    //
    // MEDIDO: com o espelho inline no `.sort()` antigo e a lib corrigida, este
    // caso reprova nomeando `parsePeriodo`. Sem ele, os outros cinco passam e a
    // divergência viaja para produção.
    casos: [['balanco 12m25'], ['dre 1t25'], ['fat l24m'], ['x 2023x2024x2025'],
      ['balanco comparativo 1999 2001'], ['dre 2025 2023 2024'], ['sem periodo']] },
  { nome: 'parseEntidade', lib: parseEntidade,
    casos: [['balanco vertentes metalurgica 2025', ALIASES], ['relatorio auditor independente', ALIASES]] },
  { nome: 'parseAssinado', lib: parseAssinado, casos: [['dre 2025 assinado'], ['bp assinadas'], ['bp 2025']] },
  // A COMPOSIÇÃO, e não só as peças: a cópia à mão dela no nó perdeu a guarda
  // `entidade = tipo ? ... : null` enquanto as quatro peças acima batiam
  // (24/09/2026, "ANEXO IV - planilha final REV3.pdf" → entidade "Iv Rev3" no
  // nó, null na lib). Os casos sem tipo no nome são os que exercitam essa guarda.
  { nome: 'classifyByFilename', lib: classifyByFilename, casos: [
    ['ANEXO IV - planilha final REV3.pdf'], ['34_Relatorio_do_Auditor_Independente_2025.pdf'],
    ['01_BP_Vertentes_Metalurgica_2025x2024.pdf'], ['DRE_1T25_assinado.pdf', 0.85], ['x.pdf', 0]] },

  { nome: 'mergeClassification', lib: mergeClassification, casos: [
    [{ tipo_taxonomia: 'BALANCO', confianca: 0.6 }, { tipo_taxonomia: 'DRE', confianca: 0.9, justificativa: 'x' }],
    [{ tipo_taxonomia: 'BALANCO', confianca: 0.5 }, { tipo_taxonomia: null, confianca: 0.9, justificativa: 'ilegível' }],
    [{ tipo_taxonomia: null, confianca: 0.3 }, { tipo_taxonomia: 'DRE', confianca: 0.8, justificativa: 'x' }],
    [{ tipo_taxonomia: null, confianca: 0.2 }, { tipo_taxonomia: null, confianca: 0.1, justificativa: '' }],
    // 0170/0171: o CNPJ só pode vir do CONTEÚDO — sem fallback para fromName,
    // ao contrário de entidade. Este caso é o que pegaria a divergência se
    // alguém reintroduzisse a cópia à mão sem a linha do cnpj.
    [{ tipo_taxonomia: 'BALANCO', confianca: 0.5 }, { tipo_taxonomia: 'BALANCO', confianca: 0.7, cnpj: '11.222.333/0001-81', justificativa: 'x' }],
    [{ tipo_taxonomia: 'BALANCO', confianca: 0.5 }, { tipo_taxonomia: 'BALANCO', confianca: 0.7, justificativa: 'sem cnpj' }],
  ] },

  // `parseCsv` SAIU DESTA TABELA (e do workflow): CSV deixou de ser parseado à
  // mão dentro de `Preparar Conteudo` — quem parseia agora é o nó nativo
  // `Extrair CSV` (roteamento por formato), e o que sobra para o Code node é
  // só formatar linhas já parseadas em texto, o mesmo para CSV/XLSX/XLS. Essas
  // três funções são as que ficaram, e são NOVAS no workflow — por isso
  // entram aqui pela primeira vez.
  { nome: 'colunasDaPlanilha', lib: colunasDaPlanilha, casos: [
    [[{ a: '1', b: '2' }, { a: '3', c: '4' }]], [[]], [[null, { a: '1' }]],
  ] },
  { nome: 'spreadsheetToText', lib: spreadsheetToText, casos: [
    [[{ Conta: 'Caixa', Valor: '100' }, { Conta: 'Estoques', Valor: '200' }]],
    [[]],
    // O TETO em ação: 5 linhas, teto 2 — o texto tem de vir truncado igual
    // nos dois lados, senão a IA de um lado lê mais planilha que a do outro.
    [Array.from({ length: 5 }, (_, i) => ({ v: String(i) })), { maxRows: 2 }],
  ] },
  { nome: 'avisoTruncamentoPlanilha', lib: avisoTruncamentoPlanilha, casos: [
    [[]], [[{ a: '1' }]],
    [Array.from({ length: 5 }, (_, i) => ({ v: String(i) })), { maxRows: 2 }],
  ] },
  { nome: 'sha256Hex', lib: sha256Hex,
    casos: [[Buffer.from('abc')], [Buffer.from('')], [Buffer.from('Ação — çãé')]] },

  { nome: 'linhasDeConta', lib: linhasDeConta, casos: [
    ['Caixa 1.000\nCNPJ 12.345.678/0001-99\nEstoques 2.500\nPágina 1'],
    ['1.1.01.002  181  D\n2025 2024 2023\nReceita bruta 10.000,50'],
    // A linha visual fragmentada, literal da captura de produção. Se a cópia
    // inline ficar sem a emenda, é aqui que ela reprova — e era a divergência
    // que deixava a lib certa e produção contando 258 onde há 99.
    ['01/12/2025 LC-2025-4000 \nNF 010000 - Papéis e Celulose Aracati S.A. \n- 150 16.839 C'],
    [''], [null],
  ] },
  { nome: 'juntarFragmentosDeLinha', lib: juntarFragmentosDeLinha, casos: [
    // Literais da captura de produção (execução 7276): o espaço no fim do
    // fragmento é o dado real, e é o que a cópia inline precisa respeitar.
    ['01/12/2025 LC-2025-4000 \nNF 010000 - Papéis e Celulose Aracati S.A. \n- 150 16.839 C'],
    ['Banco Meridional S.A. Capital de giro CG-2021-884.117 \n15/03/2026 CDI + 4,80% a.a. 10.412.600,00 '],
    ['ATIVO 137.624 163.941\nAtivo Circulante 44.022'],
    ['a 1 \n\nb 2'], ['a 1 \nb 2 \nc 3 \nd 4 \ne 5 \nf 6'], [''], [null],
  ] },
  // As três da contagem POR BLOCO e as quatro da segunda passada: o que o Parse e o
  // Fatiar RODAM tem de decidir igual ao que `cobertura-por-bloco.test.mjs` prova.
  { nome: 'juntarFragmentosComOrigem', lib: juntarFragmentosComOrigem, casos: [
    ['01/12/2025 LC-2025-4000 \nNF 010000 - Papéis e Celulose Aracati S.A. \n- 150 16.839 C\nTotal 5'],
    ['a 1 \n\nb 2'], ['a 1 \nb 2 \nc 3 \nd 4 \ne 5 \nf 6'], [''], [null],
  ] },
  { nome: 'contasComOrigem', lib: contasComOrigem, casos: [
    ['Caixa 1.000\nCNPJ 12.345.678/0001-99\nEstoques 2.500\nPágina 1'],
    ['01/12/2025 LC-2025-4000 \nNF 010000 - Papéis e Celulose Aracati S.A. \n- 150 16.839 C\nSaldo 9.999'],
    ['Nota — texto que quebra \ncom 35% na continuação.\nCaixa 10'], [''], [null],
  ] },
  { nome: 'contasPorLinhaComNumero', lib: contasPorLinhaComNumero, casos: [
    ['Caixa 1.000\nCNPJ 12.345.678/0001-99\nEstoques 2.500\nPágina 1'],
    ['01/12/2025 LC-2025-4000 \nNF 010000 - Papéis e Celulose Aracati S.A. \n- 150 16.839 C\nSaldo 9.999'],
    ['Ativo\nCaixa 10\n\nBancos 20'], [''], [null],
  ] },
  { nome: 'linhasDaPassada', lib: linhasDaPassada, casos: [
    [[{ linha_origem: 0 }, { linha_origem: 0 }, { linha_origem: 3 }]], [[{ chave: 'plano' }]], [[]], [null],
  ] },
  { nome: 'decidirSegundaPassada', lib: decidirSegundaPassada, casos: [
    [{ linhas: 59, esperadas: 101, tentativa: 1 }], [{ linhas: 101, esperadas: 101, tentativa: 1 }],
    [{ linhas: 59, esperadas: 101, tentativa: 4 }], [{ linhas: 59, esperadas: 101, tentativa: 2, jaRefeita: true }],
    [{ linhas: 0, esperadas: 101, tentativa: 1, temDadoFinanceiro: false }], [{ linhas: 0, esperadas: 101, tentativa: 1 }],
    [{ linhas: 5, esperadas: 10, tentativa: 1 }], [{ linhas: null, esperadas: 101 }], [{}], [undefined],
  ] },
  { nome: 'melhorPassada', lib: melhorPassada, casos: [[59, 80], [80, 59], [59, 59], [59, 0], [null, 3], [3, null]] },
  { nome: 'instrucaoDeSegundaPassada', lib: instrucaoDeSegundaPassada, casos: [
    [{ linhas: 59, esperadas: 101, blocos: 1 }], [{ linhas: 30, esperadas: 80, blocos: 3 }], [{ linhas: 0, esperadas: 0 }],
  ] },
  { nome: 'ehLinhaDeConta', lib: ehLinhaDeConta, casos: [
    ['Ativo Circulante 44.022 68.103'], ['1.1.01.002 181 D'], ['ATIVO CIRCULANTE'],
    ['Posição em 31 de dezembro de 2025'], ['CNPJ 44.555.667/0001-59'],
    ['- 150 16.839 C'], ['2025 2024 2023'], [''], [null],
  ] },
  { nome: 'ehLinhaSemValor', lib: ehLinhaSemValor, casos: [
    // As cinco frases reais da captura, e as três contas que precisam sobreviver.
    ['Posição em 31 de dezembro de 2025'], ['Movimento de dezembro de 2025'],
    ['Encerramento do exercício de 2025'], ['Exercícios de 2023, 2024 e 2025'],
    ['Janeiro de 2023 a dezembro de 2025'],
    ['Total de 2023 7.120'], ['01/12/2025 SALDO ANTERIOR 16.689 C'], ['Ativo Circulante 44.022'],
    [''], [null],
  ] },
  { nome: 'linhasComNumero', lib: linhasComNumero,
    casos: [['a 1\nb\nc 3'], [''], [null]] },
  { nome: 'celulasDaLinha', lib: celulasDaLinha,
    casos: [['Caixa 1.000 2.000 3.000'], ['Só rótulo'], ['']] },
  { nome: 'celulasEstimadas', lib: celulasEstimadas,
    casos: [[['a 1 2', 'b 3']], [[]]] },
  // ==========================================================================
  // `lib/formato.mjs` — as OITO que decidem o destino de cada documento.
  // ==========================================================================
  //
  // ELE ESTAVA FORA DESTE PORTÃO até 12/09/2026, e a lacuna era de auditoria,
  // não de comportamento: as oito atravessam para o nó por `toString()` VERBATIM,
  // então divergir era estruturalmente impossível — ao contrário de uma cópia
  // retipada à mão, que é o que este portão nasceu para pegar.
  //
  // Entram assim mesmo, e a razão é o que aconteceu DUAS VEZES nesta sessão: o
  // risco real não é o corpo divergir, é a função chamar uma vizinha que NÃO foi
  // serializada junto (`toString()` não leva o escopo do módulo) e morrer com
  // `ReferenceError` na primeira execução real. Estes casos EXECUTAM o código
  // embutido, então uma dependência faltando reprova aqui, no gerador, e não no
  // cliente. Foi exatamente assim que `fracaoDePalavrasDobradas` foi pega.
  { nome: 'byteEm', lib: byteEm, casos: [
    [Buffer.from([0x25, 0x50]), 0], [Buffer.from([0x25, 0x50]), 1],
    [Buffer.from([0x25]), 9], [null, 0],
  ] },
  { nome: 'casaAssinatura', lib: casaAssinatura, casos: [
    [Buffer.from([0x25, 0x50, 0x44, 0x46]), [0x25, 0x50, 0x44, 0x46]],
    [Buffer.from([0x25, 0x50, 0x44, 0x46]), [0x50, 0x4b, 0x03, 0x04]],
    [Buffer.alloc(0), [0x25]],
  ] },
  { nome: 'trechoLatin1', lib: trechoLatin1, casos: [
    [Buffer.from('PK\u0003\u0004xl/workbook.xml', 'latin1'), 0, 64],
    [Buffer.from('abc', 'latin1'), 0, 2], [Buffer.alloc(0), 0, 8],
  ] },
  { nome: 'saborDoZip', lib: saborDoZip, casos: [
    [Buffer.from('PK\u0003\u0004...xl/workbook.xml...', 'latin1')],
    [Buffer.from('PK\u0003\u0004...word/document.xml...', 'latin1')],
    [Buffer.from('PK\u0003\u0004...ppt/presentation.xml...', 'latin1')],
    [Buffer.from('PK\u0003\u0004...fotos/a.jpg...', 'latin1')],
  ] },
  { nome: 'abasDoXlsx', lib: abasDoXlsx, casos: [
    [xlsxMinimo([['A', [['x']]], ['B', [['y']]]])], [xlsxMinimo([['A', [['x']]]])],
    [Buffer.alloc(0)], [Buffer.from('texto')],
  ] },
  { nome: 'pareceTexto', lib: pareceTexto, casos: [
    [Buffer.from('CONTA 2025\nATIVO 137.624\n', 'utf-8')],
    [Buffer.from([0x01, 0x00, 0x02, 0x00])], [Buffer.alloc(0)],
    // form-feed: TODA conversão de PDF para texto usa, e não pode reprovar
    [Buffer.from('pagina 1\u000Cpagina 2', 'utf-8')],
  ] },
  { nome: 'contarFora', lib: contarFora, casos: [
    ['Nome;"a,b,c";1', ','], ['Nome;"a,b,c";1', ';'],
    ['a,b,c', ','], ['"x""y",z', ','], ['', ','],
  ] },
  { nome: 'formaDoTexto', lib: formaDoTexto, casos: [
    ['Conta;2025;2024\nCaixa;825;3621\nEstoque;20887;32598\n'],
    ['CONTA                31/12/2025   31/12/2024\nATIVO                   137.624      163.941\nCaixa                       825        3.621\n'],
    ['Pelo presente instrumento, as partes resolvem constituir uma sociedade.\n'],
    [''], [null],
  ] },
  { nome: 'detectarFormato', lib: detectarFormato, casos: [
    [Buffer.from('%PDF-1.7\nABC', 'latin1'), { mimeDeclarado: 'text/plain', nome: 'falso.txt' }],
    [Buffer.concat([Buffer.from([0x50, 0x4b, 0x03, 0x04]), Buffer.from('xl/workbook.xml')]), { mimeDeclarado: 'text/plain' }],
    [Buffer.from('CONTA   2025\nATIVO   137.624\nCaixa       825\n', 'utf-8'), { mimeDeclarado: 'text/plain' }],
    [Buffer.from('<?xml version="1.0"?><a/>', 'utf-8'), { mimeDeclarado: 'text/plain' }],
    [Buffer.from([0x01, 0x00, 0x02]), { mimeDeclarado: 'application/pdf' }],
    [Buffer.alloc(0), { mimeDeclarado: '' }],
  ] },

  // O detector de glifo dobrado, que `camadaDeTextoDoPdf` chama. Divergir aqui
  // é o limiar de 20% medindo coisa diferente na lib e no nó — e o efeito é
  // silencioso nos dois sentidos.
  { nome: 'fracaoDePalavrasDobradas', lib: fracaoDePalavrasDobradas, casos: [
    ['Empprreessaa:: AMOBBELEZA COMEERRCCIIO DIGITAL'], ['Empresa: AMOBELEZA COMERCIO DIGITAL'],
    ['Exercicios encerrados em dezembro'], [''], [null], ['123 456'],
  ] },
  // `camadaDeTextoDoPdf` decide se o PDF vai à IA como TEXTO (barato) ou como
  // IMAGEM/OCR (caro, e necessário quando é escaneado). Lib e cópia inline
  // divergirem aqui é dinheiro nos DOIS sentidos: um escaneado tratado como
  // texto manda um documento VAZIO à IA (a AMO de novo), e um PDF com camada de
  // texto tratado como imagem paga ~4x a entrada por página que não precisava.
  { nome: 'camadaDeTextoDoPdf', lib: camadaDeTextoDoPdf, casos: [
    // o caso bom: balanço com camada de texto e números
    ['CANASTRA LTDA\nATIVO 137.624 163.941\nCaixa 825 3.621\nClientes 22.310 31.884\nEstoque 20.887 32.598\n', { paginas: 1 }],
    ['', { paginas: 3 }],                                   // escaneado puro
    ['BALANCO PATRIMONIAL 2025', { paginas: 20 }],           // capa OCRzada num escaneado
    ['EMPRESA LTDA\nNotas explicativas em anexo\n'.repeat(12), { paginas: 1 }], // texto sem número
    // camada corrompida por glifo dobrado — a forma REAL, medida nos documentos
    // do dono (AMOBELEZA 73%, GENERAL TABACO 37,9% de palavras dobradas)
    ['Empprreessaa:: AMOBBELEZA COMEERRCCIIO\nDISSPONIIBILLIIDDAADDES 2.2272.055,77\nEsttooqquueess 26.893.325,14\nCllieentes 22.414.091,17\n', { paginas: 1 }],
    [null, {}], [undefined, { paginas: 0 }],                 // entradas degeneradas
  ] },
  { nome: 'avaliarCobertura', lib: avaliarCobertura, casos: [
    [{ extraidas: 90, esperadas: 100 }], [{ extraidas: 30, esperadas: 100 }],
    [{ extraidas: 5, esperadas: 6 }], [{ extraidas: 0, esperadas: 0 }],
  ] },
  { nome: 'planejarFatias', lib: planejarFatias,
    casos: [[500, 234, null], [10, 234, null], [0, 234, null]] },
  { nome: 'instrucaoDaFatia', lib: instrucaoDaFatia, casos: [
    [{ bloco: 1, blocos: 3, de: 0, ate: 100, ancoraInicio: null, ancoraFim: 'Estoques' }],
    [{ bloco: 1, blocos: 1, de: 0, ate: 0, ancoraInicio: null, ancoraFim: null }],
  ] },
  { nome: 'juntarBlocos', lib: juntarBlocos, casos: [
    [[]],
    [[{ campos: [{ chave: 'Caixa', valor_num: 1 }], linhas: 1 },
      { campos: [{ chave: 'Caixa', valor_num: 1 }, { chave: 'Estoques', valor_num: 2 }], linhas: 2 }]],
  ] },

  { nome: 'custoDaChamada', lib: custoDaChamada, casos: [
    [{ prompt_tokens: 1000, completion_tokens: 500 }, 'gpt-4o'],
    [{ prompt_tokens: 1000, completion_tokens: 500, prompt_tokens_details: { cached_tokens: 800 } }, 'gpt-4o-mini'],
    [null, 'gpt-4o'], [{}, 'modelo-desconhecido'],
  ] },
  { nome: 'tokensDeSaida', lib: tokensDeSaida, casos: [[100, 1], [100, 3], [0, 0]] },
  // `ehFormatoDeTexto` decide se a entrada de um documento é contada como TEXTO
  // (bytes/CARACTERES_POR_TOKEN) ou como PÁGINA DE IMAGEM (páginas×1000). A lib
  // e a cópia inline divergirem aqui é um lote inteiro estimado 53× para cima
  // (texto lido como PDF) ou 167× para baixo (PDF lido como texto) — os dois
  // lados do mesmo defeito, e nenhum deles estoura.
  { nome: 'ehFormatoDeTexto', lib: ehFormatoDeTexto, casos: [
    ['texto'], ['csv'], ['xml'], ['text/plain'], ['application/xml'],
    ['pdf'], ['imagem'], ['xlsx'], ['xls'], [null], [undefined], [''],
  ] },
  { nome: 'bytesDoBinario', lib: bytesDoBinario,
    casos: [[{ fileSize: '1.2 MB' }], [{ data: 'YWJj' }], [null], [{}]] },
  { nome: 'pesoDaChamadaDeClassificacao', lib: pesoDaChamadaDeClassificacao,
    casos: [[1_000_000], [0], [50_000_000]] },
  { nome: 'custoEstimadoPorConteudo', lib: custoEstimadoPorConteudo,
    casos: [[{ paginas: 3, celulas: 200, colunas: 2 }], [{ paginas: 0, celulas: 0, colunas: 1 }]] },
  { nome: 'orcamentoDoLote', lib: orcamentoDoLote,
    casos: [[{ documentos: [] }], [{ documentos: [{ bytes: 1_000_000 }, { bytes: 2_000_000 }] }]] },
  // OS TRÊS NOMES NOVOS DE 13/09/2026, e eles entram aqui porque o orçamento
  // deixou de ser tudo-ou-nada: `estimativaDoDocumento` escolhe um dos QUATRO
  // caminhos por documento, e dois deles (`tamanho`, e o de texto dentro dele)
  // passam por `custoEstimadoPorTamanho`/`custoPorMbDeTextoUSD`, que até agora
  // nunca tinham atravessado para o nó. Os casos exercitam os quatro ramos —
  // um espelho que só testasse o caminho medido deixaria passar exatamente a
  // divergência que a correção introduz.
  { nome: 'custoPorMbDeTextoUSD', lib: custoPorMbDeTextoUSD, casos: [[], [{}, 'modelo-que-nao-existe']] },
  { nome: 'custoEstimadoPorTamanho', lib: custoEstimadoPorTamanho, casos: [
    [1024 * 1024], [1024 * 1024, 'texto'], [10], [null],
  ] },
  { nome: 'estimativaDoDocumento', lib: estimativaDoDocumento, casos: [
    [{ celulas: 100, paginas: 2, colunas: 1, blocos: 1, bytes: 50_000 }],
    [{ celulas: 0, paginas: 20, colunas: 1, blocos: 1, bytes: 335_000, formato: 'pdf' }],
    [{ celulas: 0, paginas: 0, bytes: 335_000, formato: 'pdf', precisaFallback: true }],
    // O RAMO DE TEXTO SEM CONTAGEM, que faltava aqui e cujo buraco foi medido:
    // sem este caso, `CARACTERES_POR_CELULA_ESTIMADA` podia não atravessar para
    // o nó e a suíte INTEIRA ficava verde enquanto o `jsCode` gerado estourava
    // `ReferenceError` em produção. Aconteceu nesta rodada, e o caso é a prova.
    [{ celulas: 0, paginas: 0, bytes: 1024 * 1024, formato: 'csv' }],
    [{ celulas: 0, paginas: 30, bytes: 600_000, formato: 'texto' }],
    [{ celulas: 0, paginas: 0, bytes: 0 }],
  ] },
  // Os DOIS ramos da instrução de levas: lote que cabe em levas, e documento que
  // sozinho passa do teto (a recusa "envie no máximo 0" da execução 7888).
  { nome: 'instrucaoDeLevasDoLote', lib: instrucaoDeLevasDoLote, casos: [
    [{ partes: [{ usd: 1 }, { usd: 2 }], docs: [{ nome: 'a' }, { nome: 'b' }], teto: 3, maxDocumentos: 2, maxNomes: 5 }],
    [{ partes: [{ usd: 10.81 }, { usd: 0.2 }], docs: [{ nome: 'CR.xlsx' }, { nome: 'b' }], teto: 3, maxDocumentos: 0, maxNomes: 5 }],
  ] },
  { nome: 'orcamentoDoLotePorConteudo', lib: orcamentoDoLotePorConteudo, casos: [
    [{ documentos: [] }],
    [{ documentos: [{ paginas: 2, celulas: 100, colunas: 1 }, { paginas: 5, celulas: 400, colunas: 3 }] }],
    // O LOTE HÍBRIDO — um medido, um escaneado (só páginas), um só com bytes e
    // um cego. É o caso que a regra antiga jogava inteiro no proxy por byte.
    [{ documentos: [
      { nome: 'a.pdf', paginas: 2, celulas: 100, colunas: 1, blocos: 1, bytes: 40_000 },
      { nome: 'b.pdf', paginas: 20, celulas: 0, colunas: 1, blocos: 1, bytes: 335_000, formato: 'pdf' },
      { nome: 'c.xlsx', paginas: 0, celulas: 0, bytes: 90_000, formato: 'xlsx', precisaFallback: true },
      { nome: 'd.bin', paginas: 0, celulas: 0, bytes: 0 },
    ] }],
  ] },
  // Os três vereditos, e o quarto que é "não sei": abaixo do aviso (silencioso),
  // acima do aviso mas cabendo, estourando o dia, e `rpd` nulo — a OpenAI não
  // publica um número único para o Tier 1, e nulo NÃO pode virar "cabe".
  { nome: 'vereditoDaCotaDiaria', lib: vereditoDaCotaDiaria, casos: [
    [{ chamadas: 63, rpd: 500 }],
    [{ chamadas: 440, rpd: 500 }],
    [{ chamadas: 501, rpd: 500 }],
    [{ chamadas: 900, rpd: null }],
  ] },

  { nome: 'normalizarUnidade', lib: normalizarUnidade,
    casos: [['mil'], ['R$ mil'], ['milhões'], ['unidade'], ['sacas'], [null], ['']] },
  { nome: 'normalizarMoeda', lib: normalizarMoeda,
    casos: [['R$'], ['US$'], ['EUR'], ['reais'], ['iene'], [null], ['']] },

  // Os casos da v47 estão aqui de propósito: são os que a versão ANTERIOR desta
  // função errava, com a coluna ignorada. `Quantidade` e `Efetivo (pessoas)`
  // herdavam escala e moeda do documento — 1.240 bobinas e 96 pessoas prontas
  // para virar bilhão e milhão de pessoas.
  { nome: 'ehLinhaNaoMonetaria', lib: ehLinhaNaoMonetaria, casos: [
    ['Bobina kraft 180 g/m²', '2.513', 'Valor (R$ mil)'],
    ['Bobina kraft 180 g/m²', '1.240', 'Quantidade'],
    ['Produção - turno A', '96', 'Efetivo (pessoas)'],
    ['2023 - Agro para Indústria', '2023', 'Exercício'],
    ['Margem de contribuição', '12%', null],
    ['Ativo Circulante', '44.022', '31/12/2025'],
    [null, null, null], ['', '', ''],
  ] },
  // E aqui os dois documentos que declaravam "R$ mil" em cada coluna e vieram
  // com `milhao` no cabeçalho do documento.
  { nome: 'escalaDeclaradaNaColuna', lib: escalaDeclaradaNaColuna, casos: [
    ['Valor (R$ mil)'], ['Custo anual com encargos (R$ mil)'], ['Saldo (R$ milhões)'],
    ['31/12/2025'], ['Saldo devedor (R$)'], [null], [''],
  ] },
  { nome: 'diagnosticarErroApi', lib: diagnosticarErroApi, casos: [
    [{ error: { message: 'rate limit', code: 'rate_limit_exceeded' } }],
    [{ choices: [{ finish_reason: 'length' }] }],
    [null], [{}],
    // transitória x permanente e a espera que o provedor pede (repetição de bloco)
    [{ error: { message: 'Rate limit reached. Please try again in 1m3.2s.', type: 'tokens', code: 'rate_limit_exceeded' } }],
    [{ status: 503, message: 'upstream' }],
    [{ error: { message: 'bad schema', type: 'invalid_request_error', code: 'invalid_schema' } }],
    [{ error: { message: 'You exceeded your current quota', type: 'insufficient_quota' } }],
  ] },
  { nome: 'decidirRepeticao', lib: decidirRepeticao, casos: [
    [{ transitoria: true, tentativa: 1 }], [{ transitoria: true, tentativa: 3, esperaSugeridaS: 200 }],
    [{ transitoria: true, tentativa: 4 }], [{ transitoria: false, tentativa: 1 }], [{}], [undefined],
  ] },
  { nome: 'achatarGrupos', lib: achatarGrupos, casos: [
    [[]], [null],
    [[{ s: 'ATIVO', sc: 'ativo_circulante', pc: '2025', linhas: [
      { k: 'Caixa', vn: 100 }, { k: 'Estoques', vn: 200 }] }]],
    // rótulo com o valor colado: o espelho executa o achatarGrupos EMBUTIDO, que
    // chama limparRotuloColado — sem ela no nó, ReferenceError aqui.
    [[{ s: 'Passivo', sc: 'passivo_circulante', op: 1, cols: [{ ec: null, pc: '2025' }],
      l: [{ k: '2 113.860.002,40PASSIVO', vt: ['113.860.002,40'], vn: [113860002.4], cf: 0.9 }] }]],
  ] },
  { nome: 'limparRotuloColado', lib: limparRotuloColado, casos: [
    ['2 113.860.002,40PASSIVO', [113860002.4], ['113.860.002,40'], 'Passivo'],
    ['Emprestimo 2.500,00parcelas', [9000], ['9.000,00'], null],
    ['21.493.237,90', [21493237.9], ['21.493.237,90'], 'Balancete'],
    ['PREJUÍZO DE 10.058,20', [10058.2], ['10.058,20'], null],
  ] },
];

// FUNÇÕES DUPLICADAS QUE NÃO TÊM CASO AQUI, cada uma com o motivo. Não é lista de
// perdão: é o que impede o assert final de virar decoração.
const SEM_CASO = new Map([
  // Nenhuma hoje. Quando houver, o motivo entra aqui e o assert final passa a
  // aceitá-la — deliberadamente, não por esquecimento.
]);

// -----------------------------------------------------------------------------
for (const { nome, lib, casos, projLib = (x) => x, projWf = (x) => x, porque } of TABELA) {
  test(`espelho: ${nome} — a lib e o workflow decidem IGUAL${porque ? ' (contrato reduzido)' : ''}`, () => {
    const noWorkflow = doWorkflow(nome);
    for (const args of casos) {
      const esperado = projLib(lib(...args));
      const obtido = projWf(noWorkflow(...args));
      assert.deepEqual(obtido, esperado,
        `${nome}(${JSON.stringify(args).slice(0, 90)}) diverge — o workflow é o que RODA`);
    }
  });
}

test('TODA função duplicada está coberta, ou declarada com motivo', () => {
  const naLib = new Set(TABELA.map((t) => t.nome));
  const faltando = [];
  for (const [nome] of INVENTARIO) {
    // Só interessa o que EXISTE nos dois lados. Função que só vive inline (helper
    // de um nó, sem par na lib) não tem espelho a manter.
    const temPar = ['normalize', 'merge', 'spreadsheet', 'hash', 'classifier', 'cobertura', 'custo', 'extract', 'formato']
      .some((m) => {
        try {
          return new RegExp(`(export )?(async )?function ${nome}\\b`)
            .test(readFileSync(new URL(`../lib/${m}.mjs`, import.meta.url), 'utf8'));
        } catch { return false; }
      });
    if (!temPar) continue;
    if (naLib.has(nome) || SEM_CASO.has(nome)) continue;
    faltando.push(nome);
  }
  assert.deepEqual(faltando, [],
    'função duplicada entre a lib e o workflow SEM caso de espelho: '
    + `${faltando.join(', ')}. Acrescente à TABELA, ou a SEM_CASO com o motivo. `
    + 'Sem isso, corrigir a lib e esquecer a cópia inline volta a deixar a suíte '
    + 'verde e a produção errada.');
});

test('o inventário do workflow não encolheu sem alguém notar', () => {
  // Contador, no idioma do CLAUDE.md: se cair, alguém apagou cobertura — ou o
  // workflow deixou de embutir uma função e ninguém disse.
  assert.ok(INVENTARIO.size >= 30,
    `o workflow declara ${INVENTARIO.size} funções embutidas; eram 32 quando este `
    + 'assert foi escrito. Queda significa função removida do workflow.');
});
