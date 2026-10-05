// As três camadas contra o truncamento e a extração pela metade.
//
// O QUE ACONTECEU, com os números que motivaram este arquivo (rodada do
// `book-canastra`, 13/08/2026, 35 documentos): das 2.893 células de valor que
// os PDFs contêm, chegaram ao banco **1.139 — 39%**. Duas famílias distintas:
//
//   • TRUNCAMENTO (5 documentos, zero linhas). O gpt-4o tem teto de 16.384
//     tokens de SAÍDA. `01_Balanco_Patrimonial_..._2025x2024x2023` tem 326
//     células; no formato plano da época isso são ~20.900 tokens. Não cabia por
//     construção — e nenhum prompt conserta um teto físico. Ao menos falhou
//     ALTO: `finish_reason=length` virou `extracao_falhou` com a causa escrita.
//
//   • SUB-EXTRAÇÃO SILENCIOSA (o resto). `17_Livro_Razao_Fornecedores` devolveu
//     **99 de 461** linhas, sem estourar teto nenhum e sem abrir uma única
//     pendência. O sistema registrou sucesso. Esse é o modo de falha que este
//     projeto passa o tempo corrigindo: ausência com cara de normalidade.
//
// A resposta tem três camadas, e o desenho importa mais que cada uma:
//
//   1. SABER ANTES DE CHAMAR — o texto do PDF é extraído na própria instância
//      (nó `Extrair Texto`), o que dá de graça e sem IA a contagem de linhas com
//      número. É o insumo das outras duas; sem ela, elas não existem.
//   2. FATIAR POR TAMANHO — se a saída projetada passa do teto com folga, o
//      documento vai em blocos, um por chamada. Não é "tentar de novo quando
//      falhar": é nunca fazer o pedido que não cabe.
//   3. GUARDA DE COBERTURA — comparar o que voltou com o que o documento tem.
//      Ela não impede o modelo de pular uma linha; impede que isso seja
//      SILENCIOSO, que é a única promessa honesta de "nunca mais".
//
// O QUE ESTE ARQUIVO DELIBERADAMENTE NÃO FAZ: mandar o texto extraído para a
// OpenAI no lugar do PDF. A tentação é grande (o texto é mais barato que a
// imagem), e seria uma troca ruim AGORA: o texto de uma tabela perde o
// alinhamento das colunas, e foi exatamente a leitura de coluna que acabou de
// funcionar bem — o balanço combinado saiu com as 8 colunas de empresa certas.
// O texto aqui serve para MEDIR, não para LER.
//
// Todas as funções são AUTO-CONTIDAS: os nós Code do n8n não importam arquivo, e
// elas são embutidas lá por `toString()`. Nenhuma pode referenciar constante do
// módulo — se referenciar, o nó quebra com ReferenceError na primeira execução
// real e nenhum teste daqui pega isso.

// Teto de saída do modelo (espelha MAX_OUTPUT_TOKENS de lib/extract.mjs).
export const TETO_SAIDA_TOKENS = 16384;

// Tokens de saída por célula de valor, no formato agrupado. Medido em 13/08:
// ~39 por linha extraída (era ~64 no formato plano). Arredondado para cima.
export const TOKENS_POR_CELULA = 42;

// Fração do teto que um bloco pode ocupar. 0,6 e não 0,9 porque a contagem de
// linhas é uma ESTIMATIVA do que a saída vai custar: documento com rótulos
// longos gasta mais por linha, e o custo de errar para baixo é o truncamento
// que este arquivo existe para eliminar. Uma chamada a mais custa ~US$ 0,03 e
// 33 segundos; um documento truncado custa o dado.
export const FRACAO_DO_TETO = 0.6;

// Quantas células de valor cabem, com folga, numa chamada.
// 16.384 × 0,6 ÷ 42 ≈ 234.
export const MAX_CELULAS_POR_BLOCO = Math.floor((TETO_SAIDA_TOKENS * FRACAO_DO_TETO) / TOKENS_POR_CELULA);

// Limiar de cobertura abaixo do qual a extração é considerada incompleta.
//
// CALIBRADO NA RODADA REAL, e a calibração é apertada de propósito. Nos
// documentos que vieram sadios a cobertura ficou em 68%-90% (`02_DRE` 104 de
// 115; `22_Aging` 91 de 114; `06_Balanco` 74 de 109) — a diferença é linha com
// número que não é dado financeiro: CNPJ, data, número de página, rodapé. Nos
// documentos que vieram pela metade ficou em 21%-48% (`17_Livro_Razao` 99 de
// 461; `15_Balancete` 77 de 162).
//
// 0,60 era o limiar da régua ANTIGA (linhas com dígito × pares conta-coluna),
// e ele foi calibrado sobre uma razão que não fazia sentido dimensional. Com a
// régua na unidade certa — LINHAS DE CONTA contra CONTAS DISTINTAS — o mesmo
// `02_DRE` sai de "198%" para **77%**, que é a cobertura real dele.
//
// O limiar sobe para **0,85** porque o alvo declarado pelo dono é cobertura
// TOTAL. Isso vai abrir pendência em documentos que antes passavam — é o
// objetivo, não efeito colateral: o `02_DRE` a 77% está mesmo deixando ~9 contas
// para trás, e ninguém sabia.
//
// CALIBRADO CONTRA A VERDADE EM 17/08, e o número FICA em 0,85. Deixou de ter um
// ponto de medição e passou a ter 38: `node N8N/medir-regua-cobertura.mjs`
// confronta a régua com a contagem que o gerador do book declara. O resultado
// (com a régua v2, abaixo):
//
//   • erro mediano da régua: +3% — ela conta uma linha a mais por tabela, quase
//     sempre o cabeçalho de faixas/colunas, que tem rótulo E número;
//   • pior caso do book com extração PERFEITA: 96% de cobertura aparente.
//
// Ou seja, sobram 11 pontos entre o pior documento honesto (96%) e o limiar
// (85%). Subir para 0,90 caberia na medição e ainda assim NÃO se sobe: a folga
// existe para o documento real, que é mais sujo que o sintético — rodapé colado
// no número, coluna encavalada, rótulo quebrado em duas linhas. Quando a próxima
// rodada trouxer 35 documentos reais medidos, aí o número tem base para apertar.
//
// O QUE A MESMA MEDIÇÃO ACHOU E NÃO SE CONSERTAVA COM LIMIAR: onde o rótulo se
// repete (livro razão: 99 linhas, 66 históricos distintos), extração PERFEITA se
// reportava em 66% e a pendência era falsa — as duas pontas não estavam na mesma
// unidade. CORRIGIDO no mesmo dia: a extração passa a informar quantas LINHAS
// devolveu (`linha_origem` em `achatarGrupos`, contado em `juntarBlocos`), e é
// isso que a guarda compara. Nenhum limiar consertaria aquilo.
export const LIMIAR_COBERTURA = 0.85;

// Abaixo de quantas células a guarda se cala. Num documento de 6 linhas a razão
// é ruído: uma linha a menos derruba a cobertura em 17%.
export const MINIMO_PARA_AVALIAR = 20;

/**
 * Reúne os FRAGMENTOS de uma mesma linha visual que o extrator de PDF quebrou.
 *
 * O DEFEITO QUE ISTO CORRIGE, medido no texto REAL DE PRODUÇÃO (execução 7276 do
 * n8n, rodada do Canastra de 31/08, nó `Extrair Texto`, capturado em
 * `Dados de Teste/capturas/2026-08-31-texto-extraido-n8n/`). O denominador da guarda
 * de cobertura vinha inflado em documentos de TABELA LARGA, e o efeito era
 * pendência FALSA sobre extração completa:
 *
 *     17_Livro_Razao ....... 99 linhas de conta (verdade do gerador)
 *                            258 pela régua  → "102 de 258 = 40%", pendência ABERTA
 *     20_Mapa_de_Divida .... 12 linhas de conta
 *                             25 pela régua  → "12 de 25 = 48%", pendência ABERTA
 *
 * Nos dois a extração estava COMPLETA (102 de 99 e 12 de 12, com os lançamentos
 * `LC-2025-4000` a `4095` contíguos no export). O que estava errado era a régua.
 *
 * A CAUSA, visível no texto capturado. O extrator emite uma quebra de linha a
 * cada mudança de linha de base do PDF, e numa tabela larga UMA linha visual cai
 * em duas ou três:
 *
 *     "01/12/2025 LC-2025-4000 "                                   <- fragmento
 *     "NF 010000 - Papéis e Celulose Aracati S.A. - bobina 180g "  <- fragmento
 *     "- 150 16.839 C"                                             <- fecha a linha
 *
 * `linhasDeConta` conta o primeiro e o segundo como duas contas onde há uma —
 * daí os ~2,6x do livro razão. O balanço patrimonial não sofre nada disso: lá a
 * régua acerta a verdade no dígito (114 de 114).
 *
 * O SINAL, e por que ele é este. Todo fragmento que NÃO fecha a linha visual
 * termina em espaço — é o separador que o extrator emitiu antes de trocar de
 * linha. Medido nos 20 documentos capturados: 0% de linhas com essa marca nos
 * treze documentos que a régua já acertava, e 44% a 63% nos quatro que ela
 * errava. Não é um sinal fraco que precisa de limiar: é presença contra
 * ausência.
 *
 * O TETO DE FRAGMENTOS existe porque a falha sem ele seria a perigosa. Se um dia
 * um documento vier com TODA linha terminando em espaço, a emenda sem limite o
 * colapsaria em uma linha só, o denominador iria a 1 e a guarda ficaria MUDA —
 * exatamente o modo de falha que ela existe para eliminar. Com o teto, o excesso
 * de fragmentos vira linha a mais, que é o lado barato do erro (a guarda tem 15%
 * de folga para contar a mais, e zero para contar a menos — ver
 * `medir-regua-cobertura.mjs`). O valor 4 é a maior sequência medida (3, no
 * `20_Mapa_de_Divida`) mais uma.
 *
 * Ela normaliza a régua da COBERTURA, e só ela. A régua do FATIAMENTO
 * (`linhasComNumero`) fica como está: nada nesta rodada mediu defeito lá — o
 * `17_Livro_Razao` foi fatiado em 4 blocos e os 4 chegaram.
 */
export function juntarFragmentosDeLinha(texto) {
  return juntarFragmentosComOrigem(texto).map((g) => g.texto).join('\n');
}

/**
 * A MESMA emenda de `juntarFragmentosDeLinha`, devolvendo de ONDE cada linha
 * emendada veio: `de` é o índice (no texto cru, linha a linha) do primeiro
 * fragmento e `n`, quantos fragmentos entraram. `juntarFragmentosDeLinha` é só
 * isto com `texto` juntado por `\n` — UMA implementação da emenda, de propósito:
 * a contagem de contas POR BLOCO (`contasPorLinhaComNumero`) precisa da mesma
 * emenda da contagem do documento, e duas cópias dela divergem sem erro nenhum.
 *
 * AUTO-CONTIDA (nós Code a embutem por `toString()`).
 */
export function juntarFragmentosComOrigem(texto) {
  if (typeof texto !== 'string' || texto.length === 0) return [];
  const MAX_FRAGMENTOS = 4;
  const saida = [];
  const cruas = texto.split('\n');
  let emenda = '';
  let quantos = 0;
  let deEmenda = 0;
  for (let i = 0; i < cruas.length; i += 1) {
    const bruta = cruas[i];
    // Linha em branco NÃO emenda e não some: ela separa bloco. Emendar através
    // dela colaria o rodapé de uma página no cabeçalho da seguinte; engoli-la
    // mudaria o texto para quem só passa por aqui.
    if (bruta.trim().length === 0) {
      if (emenda.length > 0) saida.push({ texto: emenda, de: deEmenda, n: quantos });
      saida.push({ texto: bruta, de: i, n: 1 });
      emenda = '';
      quantos = 0;
      continue;
    }
    // O espaço no fim é a marca do fragmento que NÃO fecha a linha visual.
    if (/[ \t]$/.test(bruta) && quantos < MAX_FRAGMENTOS) {
      if (quantos === 0) deEmenda = i;
      emenda += bruta;
      quantos += 1;
      continue;
    }
    saida.push({ texto: emenda + bruta, de: quantos > 0 ? deEmenda : i, n: quantos + 1 });
    emenda = '';
    quantos = 0;
  }
  if (emenda.length > 0) saida.push({ texto: emenda, de: deEmenda, n: quantos });
  return saida;
}

/**
 * A linha NÃO MEDE NADA — todo número dela é data, período ou código.
 *
 * O RESÍDUO QUE ISTO TIRA, medido sobre os 20 documentos capturados de produção
 * depois que `juntarFragmentosDeLinha` entrou. Sobrava +1 a +2 linhas por
 * documento, e o resíduo era de uma família só: **linha de cabeçalho que tem
 * número sem medir número.** Três formas, todas literais da captura:
 *
 *   PERÍODO   "Posição em 31 de dezembro de 2025"        (20_Mapa_de_Divida)
 *             "Movimento de dezembro de 2025"            (17_Livro_Razao)
 *             "Encerramento do exercício de 2025"        (15_Balancete)
 *             "Exercícios de 2023, 2024 e 2025"          (19_Faturamento_Intragrupo)
 *             "Janeiro de 2023 a dezembro de 2025"       (18_Faturamento_36_meses)
 *   DURAÇÃO   "RELATÓRIO DE FATURAMENTO — ÚLTIMOS 36 MESES"   (18)
 *   CÓDIGO    "LIVRO RAZÃO — CONTA 2.1.01.001 FORNECEDORES"   (17)
 *
 * Todas têm dígito e têm letra, então passavam pelos dois testes de
 * `linhasDeConta`. Nenhuma é conta.
 *
 * O CRITÉRIO NÃO É LEXICAL, E ISSO É O PONTO. Casar "Posição em" e "LIVRO RAZÃO"
 * seria ajustar a régua às frases DESTE book — o cliente escreve outras, e a
 * régua voltaria a errar parecendo calibrada. O critério é uma pergunta só:
 * **retire da linha os números que NÃO MEDEM — a data, a duração e o código de
 * conta. Se não sobrar dígito, a linha não tem valor.** Cada um dos três é
 * identificação ou recorte de tempo; nenhum é quantia.
 *
 * A DIREÇÃO PERIGOSA É EXCLUIR DE MAIS, e é por isso que a conta sobrevive: o
 * valor dela nunca é data, duração nem código.
 *
 *     "Total de 2023 7.120"                -> sobra 7.120   -> É CONTA
 *     "01/12/2025 SALDO ANTERIOR 16.689 C" -> sobra 16.689  -> É CONTA
 *     "1.1.01.002 181 D"                   -> sobra 181     -> É CONTA
 *     "Posição em 31 de dezembro de 2025"  -> não sobra nada -> não mede
 *
 * MEDIDO nos 20 documentos de produção, junto com a nota de rodapé que quebra em
 * duas linhas (tratada em `linhasDeConta`): documentos EXATOS **12 -> 20 de 20**,
 * erro absoluto médio **2,5% -> 0,0%**, e **nenhum documento passou a contar A
 * MENOS** — a única direção que faria mal, porque é ela que deixa passar extração
 * pela metade. O portão segura essa exatidão: erro acima de 0,5% em qualquer
 * documento capturado reprova.
 */
export function ehLinhaSemValor(linha) {
  if (typeof linha !== 'string' || linha.length === 0) return false;
  // O CASO PERIGOSO, achado de lado na Fase 0 (09/09) no `11_Mapa_Divida_
  // Vertentes_Metalurgica_2025` — documento em REAIS, não em milhares. A linha
  // "TOTAL 51.300.000 12.400.000" sumia do denominador: `\b\d+(?:\.\d+){2,}\b`
  // via em "51.300.000" a MESMA forma de "1.1.01.002" (dígitos separados por
  // ponto, dois ou mais pontos) e apagava os dois valores como se fossem
  // código de conta — sobrava "TOTAL", sem dígito, e a linha de TOTAL virava
  // invisível. Verdade 10, régua 9 (-10%): contar A MENOS é o lado que a Fase 0
  // existe para vigiar, porque encolhe o denominador e deixa a extração pela
  // metade parecer sadia.
  //
  // O CRITÉRIO NÃO É LISTA, É FORMA — a mesma disciplina do resto deste
  // arquivo. Separador de milhar brasileiro tem uma regra fixa: CADA grupo
  // depois do primeiro tem EXATAMENTE 3 dígitos ("51.300.000" -> 300, 000;
  // "9.420.000" -> 420, 000; "10.412.600" -> 412, 600). Código de conta não
  // segue essa regra — a hierarquia classe.grupo.subgrupo.sequência escreve
  // grupos de tamanho variável ("1.1.01.002" -> 1, 01, 002; "2.1.01.001" ->
  // 1, 01, 001; o segundo grupo nunca chega a 3 dígitos). A pergunta que
  // decide, então, não é "quantos pontos tem" — é "todo grupo depois do
  // primeiro tem 3 dígitos?": se sim, é dinheiro; se não, é identidade.
  // `separadorDeMilhar`, abaixo, é essa pergunta.
  const separadorDeMilhar = /^\d{1,3}(?:\.\d{3})+$/;
  // As alternativas vêm de LITERAIS de regex, lidas por `.source`. Escritas como
  // string comum elas exigiriam '\\b\\d{1,2}' — barra dobrada em toda a expressão,
  // que é onde erro de escape se esconde e onde o Sonar (S7780) acusou quatro
  // vezes. Literal não tem essa camada.
  const meses = /janeiro|fevereiro|mar[çc]o|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro/
    .source;
  const duracao = /meses|m[êe]s|anos|ano|exerc[íi]cios|exerc[íi]cio|dias|dia|semanas|trimestres|trimestre|bimestres|semestres/
    .source;
  // NÃO EXISTE AQUI UM CORTE DE "MÊS + ANO" ("Janeiro/2023"), e a ausência é
  // deliberada — ele existiu e foi MEDIDO MORTO. O corte do ano solto, na última
  // linha do encadeamento, já apaga o "2023" de "Janeiro/2023" e deixa "Janeiro/",
  // que não tem dígito: a regra de mês+ano nunca decidiu nada. Removida a régua
  // continua exata nos 20 documentos e nenhum assert reprova — foi assim que se
  // descobriu, e o teste que a "protegia" passava com ela sabotada.
  //
  // Ela cobrava caro pelo nada: era `(mês)\s*[\/ ]\s*\d{4}`, com o espaço nos
  // TRÊS pedaços, então uma corrida de N espaços podia ser dividida de N jeitos e
  // o motor tentava todos (Sonar S8786). Medido: 2.000 espaços custavam 1,62 ms e
  // 4.000 custavam 6,16 ms — quadrático, num texto de PDF que vem cheio de corrida
  // de espaço.
  const diaDeMes = new RegExp(/\b\d{1,2}\s+de\s+/.source + '(' + meses + ')', 'gi');
  const quantosDeDuracao = new RegExp(/\b\d{1,3}\s*/.source + '(' + duracao + ')' + /\b/.source, 'gi');
  const resto = linha
    // CÓDIGO DE CONTA ("2.1.01.001") — identifica, não mede. Sai primeiro, senão
    // o regex de ano acha "2025" dentro de um código que o contenha. O que TEM
    // a forma de separador de milhar (`separadorDeMilhar`, acima) fica: é
    // valor, não identidade, e apagá-lo é o defeito do `11_Mapa_Divida`.
    .replace(/\b\d+(?:\.\d+){2,}\b/g, (m) => (separadorDeMilhar.test(m) ? m : ' '))
    .replace(/\b\d{1,2}\/\d{1,2}\/\d{2,4}\b/g, ' ')   // 31/12/2025
    .replace(diaDeMes, ' ')                             // 31 de dezembro
    .replace(quantosDeDuracao, ' ')                     // 36 MESES
    .replace(/\b(19|20)\d{2}\b/g, ' ');                // 2025
  return !/\d/.test(resto);
}

/**
 * As linhas do texto que são LINHA DE CONTA — rótulo seguido de valor.
 *
 * A RÉGUA ESTAVA NA UNIDADE ERRADA, e isso importa mais que a precisão dela.
 * A primeira versão contava toda linha com algum dígito e comparava com os
 * PARES (conta × coluna) que a extração grava. Medido no `02_DRE` do
 * book-canastra: o texto tem 46 linhas com dígito, a extração gravou 91 pares —
 * a razão dá 198%, e a guarda de cobertura nunca dispararia. Pior: ela ficava
 * cega justamente nos documentos COMPARATIVOS, que são os que mais têm a perder.
 *
 * Agora a régua conta LINHAS DE CONTA e é comparada com CONTAS DISTINTAS
 * extraídas — as duas na mesma unidade. No mesmo DRE: 39 linhas de conta contra
 * ~30 contas extraídas = 77%, que é a cobertura de verdade.
 *
 * O que sai da contagem, e é 15% do total naquele documento: cabeçalho de ano
 * ("2025 2024 2023"), CNPJ, data por extenso, número de página, CRC e CPF do
 * bloco de assinatura. Nada disso é dado financeiro, e contá-los inflava o
 * denominador — a régua "grosseira mas honesta" era grosseira de mais.
 *
 * ┌─ v2 (17/08), medida contra as 38 verdades do `book-canastra` ──────────────
 * │ `node N8N/medir-regua-cobertura.mjs` confrontou esta função com a contagem
 * │ que o GERADOR do book declara (ele sabe quantas linhas escreveu, não é outra
 * │ leitura do PDF). A régua acertava os documentos de demonstração — balanço,
 * │ DRE, DFC, faturamento: erro de +2% a +4% — e DESABAVA justamente nos
 * │ analíticos, que são os que perdem dado:
 * │
 * │   livro razão   99 linhas → a régua via  3   (−97%)
 * │   balancete     78 linhas → a régua via  3   (−96%)
 * │   aging         14 linhas → a régua via  2   (−86%)
 * │   imobilizado    9 linhas → a régua via  2   (−78%)
 * │
 * │ E como `MINIMO_PARA_AVALIAR` cala a guarda abaixo de 20 linhas, a cegueira
 * │ virava SILÊNCIO: nesses documentos a guarda nunca chegava a opinar. O livro
 * │ razão da rodada de 14/08 — o caso que motivou as três camadas — era invisível
 * │ para a guarda que existe para vigiá-lo.
 * │
 * │ A CAUSA: "termina em valor" pressupõe que rótulo e valor caem na MESMA linha
 * │ do texto extraído. Num documento de sistema contábil isso é falso de três
 * │ jeitos, e os três foram conferidos no artefato (e num segundo leitor de PDF,
 * │ o `pdf-parse` que o n8n usa, para não calibrar contra um extrator só):
 * │   • a linha termina na NATUREZA, não no valor — `1.1.01.002  181  D`;
 * │   • o rótulo é CÓDIGO de conta, sem letra nenhuma — o mesmo `1.1.01.002`;
 * │   • o histórico é parágrafo que quebra, e o leitor o deixa numa linha só
 * │     dele: os valores do lançamento ficam órfãos de rótulo.
 * │
 * │ A v2 troca "termina em valor" por "TEM valor E tem identidade", e aceita como
 * │ identidade três formas: rótulo em letras, código de conta, ou — quando o
 * │ leitor separou o rótulo — a própria linha de tabela numérica (dois valores ou
 * │ mais). Erro absoluto médio: 29% → 9%, sem piorar um único documento.
 * └───────────────────────────────────────────────────────────────────────────
 */
/**
 * A linha, sozinha, é uma LINHA DE CONTA? — rótulo (ou código) mais valor.
 *
 * Separada de `linhasDeConta` porque são duas perguntas diferentes: esta olha UMA
 * linha; aquela percorre o documento e carrega o único estado que existe (a nota
 * de rodapé que continua na linha seguinte). Misturadas, a função passava de 15
 * pontos de complexidade cognitiva (Sonar S3776) — e o custo real não é a métrica,
 * é que o leitor tinha de segurar as duas na cabeça ao mesmo tempo.
 */
export function ehLinhaDeConta(linha) {
  if (typeof linha !== 'string' || linha.length === 0) return false;
  // Um valor: número solto, com separador de milhar, decimal, percentual, ou
  // negativo entre parênteses — as quatro formas que o book usa.
  const valores = /\(?-?\d[\d.]*(?:,\d+)?\)?%?/g;
  // Código de conta contábil ("1.1.01.002"): identidade sem uma letra sequer.
  //
  // ESTA PROVA DE IDENTIDADE não aceita mais a forma de separador de milhar
  // como código de conta — achado na revisão do PR #204. Antes, o regex puro
  // `\b\d+(?:\.\d+){2,}\b` também casava "51.300.000"; quando uma linha SEM
  // rótulo e SEM segundo valor (`quantos < 2`, abaixo) trazia só um número
  // desses, ele virava "prova de identidade" de código de conta — quando é
  // valor. `separadorDeMilhar` (a mesma régua que `ehLinhaSemValor` já usa)
  // resolve isso: só conta como código quem NÃO tiver essa forma.
  const separadorDeMilhar = /^\d{1,3}(?:\.\d{3})+$/;
  const codigoDeConta = {
    test: (l) => (l.match(/\b\d+(?:\.\d+){2,}\b/g) ?? []).some((m) => !separadorDeMilhar.test(m)),
  };
  // Ruído conhecido de documento contábil brasileiro. Cada padrão saiu de uma
  // linha real do book, e o comentário evita que alguém "melhore" tirando um.
  const ruido = [
    /^p[áa]gina\b/i,                       // "Página 1"
    // Os grupos NÃO são estilo: `|` tem a MENOR precedência de todo o regex, e
    // `^` liga só na alternativa em que aparece. Sem o grupo, `^cnpj\b|\bcnpj…`
    // se lê `(^cnpj\b)|(\bcnpj…)` — que por acaso É o que se quer aqui, mas
    // ninguém consegue afirmar isso lendo, e a próxima pessoa que acrescentar
    // uma terceira alternativa vai herdar a âncora sem perceber. Explicitar o
    // agrupamento trava a leitura no que o código já faz. É a mesma correção que
    // a `fn_documento_preliminar` da 0151 documenta do lado do Postgres, onde a
    // precedência de `~` sobre `||` fazia a função devolver TEXTO em vez de
    // booleano — lá o descuido custou uma função quebrada, aqui ainda não custou.
    /(?:^cnpj\b)|(?:\bcnpj\s*[\d.])/i,     // "CNPJ 44.555.667/0001-59"
    /(?:^cpf\b)|(?:\bcpf\s*[\d.])/i,       // assinatura
    /\bcrc\s*\d|\bcrc\s*[a-z]{2}/i,        // "CRC 1MG-198.442/O-7"
    /^\(?valores expressos/i,              // "(Valores expressos em milhares…)"
    /^exerc[íi]cios? encerrados?/i,        // "Exercícios encerrados em 31 de dezembro…"
    /^(nota|obs)\b|^_{3,}/i,               // nota de rodapé, linha de assinatura
    // Cabeçalho de coluna: só anos/datas, sem rótulo de conta antes.
    /^[\s|]*((19|20)\d{2}|\d{2}\/\d{2}\/\d{4})([\s|]+((19|20)\d{2}|\d{2}\/\d{2}\/\d{4}))*[\s|]*$/,
  ];
  if (ruido.some((r) => r.test(linha))) return false;
  const quantos = (linha.match(valores) ?? []).filter((t) => /\d/.test(t)).length;
  // Sem valor não é conta: é título, é seção, é prosa. O modelo também não gera
  // linha para ela.
  if (quantos === 0) return false;
  // Identidade da conta, em qualquer uma das três formas. A terceira — "linha de
  // tabela numérica" — é a que recupera o razão e o aging, onde o leitor de PDF
  // põe o rótulo numa linha e os valores na seguinte: contar a linha dos valores
  // é contar a conta UMA vez, que é a unidade certa.
  const temRotulo = /[a-zà-ú]{3}/i.test(linha);
  if (!temRotulo && !codigoDeConta.test(linha) && quantos < 2) return false;

  // A REGRESSÃO DE VERDADE DO PR #204, achada na revisão e medida comparando
  // `main` antes (668b6fe) e depois (b86d6cf):
  //
  //                                 ANTES    DEPOIS
  //   "Protocolo 1.234.567"          false  →  true
  //   "Processo 0.001.234"           false  →  true
  //   "Caixa 1.000 2.000"            true      true   (inalterado, correto)
  //   "1.1.01.002 Numerário 2.880"   true      true   (inalterado, correto)
  //
  // NÃO É o `codigoDeConta` acima — ele só decide quando NÃO HÁ rótulo, e as
  // duas linhas que regrediram TÊM rótulo ("Protocolo", "Processo"): o `!
  // temRotulo` do `if` acima já é `false` e o `codigoDeConta` nunca chega a
  // ser avaliado. A causa é o `ehLinhaSemValor` chamado no final desta
  // função: ele passou a PRESERVAR forma de separador de milhar (correto —
  // é o que resolve o `11_Mapa_Divida`), e "1.234.567"/"0.001.234" TÊM
  // EXATAMENTE A MESMA FORMA que "51.300.000" — três grupos de exatamente
  // três dígitos. Nenhuma regra de FORMA PURA separa "número de protocolo"
  // de "valor monetário" quando os dois são o ÚNICO número da linha — a
  // forma é idêntica por definição.
  //
  // O QUE SOBRA, E AINDA É FORMA (não léxico, não lista de palavra): QUANTOS
  // números com essa forma ambígua a linha tem. `TOTAL 51.300.000
  // 12.400.000` tem DOIS — é assim que toda linha de valor comparativo do
  // book aparece, com duas colunas/exercícios; `Protocolo 1.234.567` e
  // `Processo 0.001.234` têm só UM. Uma linha cujo ÚNICO valor tem forma
  // ambígua (poderia ser identidade, poderia ser dinheiro) precisa de uma
  // SEGUNDA ocorrência para ser aceita — o mesmo raciocínio do `quantos < 2`
  // linhas acima, aplicado à forma que sozinha não decide.
  //
  // MEDIDO nos dois books (46 documentos, `node N8N/medir-fase0-
  // denominador.mjs --book canastra|vertentes`, antes e depois desta linha):
  // nenhum documento piorou — `linhasDeConta` continua com erro absoluto
  // médio 4,6% (canastra) / 0,5% (vertentes) e conta A MENOS em 3 de 46, e o
  // `11_Mapa_Divida` (verdade 10) continua em 10/10.
  const formaIdentidadeOuMilhar = /\b\d+(?:\.\d+){2,}\b/g;
  const unicoValorAmbiguo = quantos < 2
    && (linha.match(formaIdentidadeOuMilhar) ?? []).some((m) => separadorDeMilhar.test(m));
  if (unicoValorAmbiguo) return false;

  // Cabeçalho que tem número sem medir número — período, duração, código de
  // conta. Tem dígito e tem letra, então passava pelos dois testes acima.
  return !ehLinhaSemValor(linha);
}

export function linhasDeConta(texto) {
  return contasComOrigem(texto).map((c) => c.linha);
}

/**
 * O corpo de `linhasDeConta`, devolvendo também de onde cada conta veio (`de` e
 * `n`, como em `juntarFragmentosComOrigem`). Existe para uma pergunta só: a
 * contagem POR BLOCO. `linhasDeConta` é `contasComOrigem(...).map(linha)` — a
 * regra de "o que é conta" mora aqui e em `ehLinhaDeConta`, em lugar nenhum mais.
 *
 * AUTO-CONTIDA (nós Code a embutem por `toString()`).
 */
export function contasComOrigem(texto) {
  if (typeof texto !== 'string' || texto.length === 0) return [];
  // O texto chega FRAGMENTADO em documento de tabela larga — ver
  // `juntarFragmentosDeLinha`, que tem os 258 contra 99 que motivaram isto.
  const grupos = juntarFragmentosComOrigem(texto);
  // A NOTA DE RODAPÉ QUEBRA EM DUAS LINHAS, e só a primeira dizia "Nota —".
  // Medido no `13_Balanco_COMBINADO`: o ruído cortava a primeira e contava
  // "aos 35% do capital da CN Transportes ... detidos por terceiros." como conta.
  // A continuação se reconhece por DUAS coisas juntas, nunca por uma: a linha
  // anterior foi cortada como PROSA, e esta começa em minúscula. Só a minúscula
  // não serve — no `20_Mapa_de_Divida`, "conversão FIN-2019-336.070 28/09/2029…"
  // começa em minúscula E É uma linha de contrato de verdade; o que a salva é
  // que a linha antes dela é uma linha da tabela, não prosa cortada.
  //
  // É O ÚNICO ESTADO desta função, e é por isso que a decisão por linha mora em
  // `ehLinhaDeConta`: aqui fica o que depende da linha ANTERIOR, e só isso.
  const prosa = /^(nota|obs)\b|^\(?valores expressos|^exerc[íi]cios? encerrados?/i;
  let anteriorEraProsa = false;
  const out = [];
  for (const g of grupos) {
    const linha = g.texto.trim();
    if (linha.length === 0) { anteriorEraProsa = false; continue; }
    if (anteriorEraProsa && /^[a-zà-ú]/.test(linha)) continue;
    anteriorEraProsa = prosa.test(linha);
    if (ehLinhaDeConta(linha)) out.push({ linha, de: g.de, n: g.n });
  }
  return out;
}

/**
 * Quantas CONTAS cada linha de `linhasComNumero(texto)` carrega — o denominador
 * da cobertura POR BLOCO.
 *
 * POR QUE NÃO BASTA RECONTAR A FATIA. Medido nos 20 documentos de produção
 * (`N8N/test/segunda-passada-por-cobertura.test.mjs`): recontar `linhasDeConta` sobre as
 * linhas de uma fatia fecha EXATO nos balanços e DRE, e erra feio onde a tabela é
 * larga — livro razão 256 contra 99 (a fatia já perdeu o espaço do fim que marca o
 * fragmento), balancete 2 contra 78 (as linhas sem dígito, que são o rótulo,
 * saíram da lista). Um denominador 2,6 vezes maior refaria TODO bloco perfeito do
 * livro razão. Aqui a contagem é feita UMA vez, sobre o texto inteiro e com a
 * mesma emenda do documento, e cada conta é creditada à primeira linha COM DÍGITO
 * do seu grupo de fragmentos — então a soma dos blocos é, por construção, a
 * contagem do documento.
 *
 * Devolve `null` (não medível) se alguma conta não achar linha com dígito onde
 * pousar — nunca um vetor que não some. Cada posição do vetor casa com a mesma
 * posição de `linhasComNumero(texto)`.
 *
 * AUTO-CONTIDA (nós Code a embutem por `toString()`).
 */
export function contasPorLinhaComNumero(texto) {
  if (typeof texto !== 'string' || texto.length === 0) return [];
  const cruas = texto.split('\n');
  const posicao = new Map();
  for (let i = 0; i < cruas.length; i += 1) {
    const l = cruas[i].trim();
    if (l.length === 0 || !/\d/.test(l)) continue;
    posicao.set(i, posicao.size);
  }
  const porLinha = new Array(posicao.size).fill(0);
  for (const c of contasComOrigem(texto)) {
    let alvo = null;
    for (let k = c.de; k < c.de + c.n; k += 1) {
      if (posicao.has(k)) { alvo = posicao.get(k); break; }
    }
    if (alvo === null) return null;
    porLinha[alvo] += 1;
  }
  return porLinha;
}

/**
 * Toda linha com algum dígito. Continua existindo porque é a régua do
 * FATIAMENTO — ali o que importa é o tamanho da resposta, e cada célula pesa,
 * inclusive as do cabeçalho. Para COBERTURA use `linhasDeConta`.
 */
export function linhasComNumero(texto) {
  if (typeof texto !== 'string' || texto.length === 0) return [];
  const out = [];
  for (const bruta of texto.split('\n')) {
    const linha = bruta.trim();
    if (linha.length === 0) continue;
    if (!/\d/.test(linha)) continue;
    out.push(linha);
  }
  return out;
}

/**
 * Quantas CÉLULAS DE VALOR uma linha do texto vai produzir na extração.
 *
 * ISTO CONSERTA UM ERRO DE UNIDADE QUE DESLIGAVA O FATIAMENTO INTEIRO, e o erro
 * é o terceiro da mesma família neste arquivo (os dois primeiros estão nos
 * comentários de `linhasDeConta` e de `LIMIAR_COBERTURA`). `MAX_CELULAS_POR_BLOCO`
 * é derivado como "quantas CÉLULAS cabem em 60% do teto de saída" — 234 — e vinha
 * sendo aplicado a uma contagem de LINHAS. Não é a mesma coisa: o nó `Extract From
 * File` entrega o texto agrupado por linha (pela coordenada Y), e uma linha de
 * balanço comparativo de três exercícios produz TRÊS células.
 *
 * MEDIDO NOS 38 DOCUMENTOS DO `book-canastra`, com o texto real que o nó entrega
 * (`pdf/TEXTO_EXTRAIDO.json`): a razão células/linha vai de **1,67 a 6,81** (o
 * aging tem seis faixas por linha). Consequência, também medida: **NENHUM
 * documento do book era fatiado** — todos davam `blocos = 1`, porque nem o mais
 * denso passava de 234 LINHAS. E o `17_Livro_Razao_Fornecedores`, com 393 células
 * em 102 linhas, ia inteiro numa chamada: **16.506 tokens de saída, 101% do teto**
 * — truncamento certo, no documento que motivou as três camadas.
 *
 * A CORREÇÃO ANOTADA NO `ESTADO.md` ERA OUTRA, e era a errada: "extrair por faixa
 * de PÁGINA — mudança de topologia". Não é preciso mudar topologia nenhuma. Com o
 * peso em células, o fatiamento por ÂNCORA que já existe corta o razão em blocos
 * que cabem, e um bloco pode chegar a UMA linha. Página nunca foi o eixo do
 * problema; a unidade era.
 *
 * A CONTAGEM ERRA PARA CIMA DE PROPÓSITO, e o número está medido: somando todo
 * token numérico da linha, o estimador dá **+64% agregado** sobre a verdade
 * declarada pelo gerador do book (pior caso +187%, no razão — data, número de
 * lançamento e código de conta são números que não viram célula). Errar para cima
 * fatia mais fino que o necessário: no book inteiro são ~4 chamadas a mais, ~US$
 * 0,12 sobre US$ 1,29 (+9%). Errar para BAIXO trunca, e truncar custa o dado —
 * é a mesma escolha que `FRACAO_DO_TETO` já documenta.
 *
 * MEDI A VERSÃO REFINADA E ELA FOI REJEITADA: tirando data, CNPJ, código de conta
 * (`1.1.01.001`) e percentual, o erro agregado cai de +64% para +23% — mas
 * **quatro documentos passam a SUBESTIMAR**, e o balancete analítico subestima em
 * 43%. Menos erro médio pelo preço de errar para o lado que trunca é troca ruim.
 * Fica registrado para quem for tentar de novo: o ganho existe, o risco também.
 */
export function celulasDaLinha(linha) {
  const texto = typeof linha === 'string' ? linha : String(linha ?? '');
  // Número com separador de milhar/decimal OU número simples, com o parêntese
  // contábil de negativo tolerado nas duas pontas.
  const achados = texto.match(/-?\d{1,3}(?:\.\d{3})+(?:,\d+)?|-?\d+(?:[.,]\d+)?/g);
  // MÍNIMO 1: a linha veio de `linhasComNumero`, então ela TEM dígito. Devolver
  // zero faria o acumulador do fatiamento não avançar e um bloco crescer sem fim.
  return achados && achados.length > 0 ? achados.length : 1;
}

/**
 * O peso, em células, de cada linha — paralelo à lista de linhas.
 *
 * Existe como função própria porque `planejarFatias` tem de continuar
 * AUTO-CONTIDA (os nós Code a embutem por `toString()`, e uma referência a outra
 * função do módulo vira `ReferenceError` na primeira execução real). Então quem
 * chama calcula os pesos e passa; a expressão do que é uma célula fica em UM
 * lugar só.
 */
export function celulasEstimadas(linhas) {
  return (Array.isArray(linhas) ? linhas : []).map((l) => celulasDaLinha(l));
}

/**
 * O plano de fatiamento de UM documento.
 *
 * Devolve sempre pelo menos um bloco — documento pequeno é "um bloco só", não
 * um caso especial, e tratar os dois pelo mesmo caminho é o que impede o
 * fatiamento de ser um modo raro que ninguém exercita.
 *
 * AS ÂNCORAS SÃO O CORAÇÃO DISTO. O modelo continua vendo o PDF INTEIRO (é onde
 * está o alinhamento das colunas), então dizer "extraia o bloco 2 de 3" seria
 * pedir para ele adivinhar onde o bloco começa. Em vez disso cada bloco carrega
 * o TEXTO EXATO da primeira e da última linha da faixa, lidos do PDF pelo
 * extrator: "comece em «Duplicatas a receber ... 22.310» e termine em «(-) PCLD
 * ... (1.900)»". Vira uma instrução verificável em vez de uma proporção.
 */
export function planejarFatias(linhas, maxPorBloco, pesos) {
  const lista = Array.isArray(linhas) ? linhas : [];
  const max = Number.isFinite(Number(maxPorBloco)) && Number(maxPorBloco) > 0
    ? Math.floor(Number(maxPorBloco))
    : 234;
  const total = lista.length;
  // O PESO É EM CÉLULAS, e sem ele cada linha vale 1 — que é o comportamento
  // antigo e continua correto para documento de uma coluna. Quem tem o texto
  // calcula os pesos com `celulasEstimadas` e passa; esta função não pode
  // chamá-la (tem de ficar auto-contida para os nós Code).
  const peso = (i) => {
    const p = Array.isArray(pesos) ? Number(pesos[i]) : 1;
    return Number.isFinite(p) && p > 0 ? p : 1;
  };
  let soma = 0;
  for (let i = 0; i < total; i += 1) soma += peso(i);
  if (soma <= max) {
    return [{
      bloco: 1, blocos: 1, de: 0, ate: Math.max(0, total - 1),
      ancoraInicio: null, ancoraFim: null, celulas: soma, linhas: total, acimaDoTeto: false,
    }];
  }

  // DUAS PASSADAS, e a primeira existe porque `ceil(soma / max)` MENTE. Ela
  // supõe que o corte cai onde se quiser; ele cai entre LINHAS, e a linha nunca
  // é partida (ela é a âncora, e meia âncora não localiza nada no PDF). Com
  // linhas de peso 4 e teto 10, `ceil` prevê 4 blocos e o alvo de 10 produz
  // blocos de 12 — acima do teto que a função existe para respeitar. Medido
  // assim, escrevendo esta função: [12, 12, 12, 4].
  //
  // Passada 1: guloso com o TETO como restrição dura, para saber de quantos
  // blocos o documento precisa DE FATO.
  const cortarCom = (alvo) => {
    const out = [];
    let de = 0;
    let acumulado = 0;
    for (let i = 0; i < total; i += 1) {
      const p = peso(i);
      // Estourou o teto ao incluir esta linha? Fecha ANTES dela — a menos que o
      // bloco esteja vazio, e aí a linha sozinha já passa do teto e não há o que
      // fazer além de declarar (`acimaDoTeto`).
      if (acumulado > 0 && acumulado + p > max) {
        out.push({ de, ate: i - 1, celulas: acumulado });
        de = i;
        acumulado = 0;
      }
      acumulado += p;
      const ultima = i === total - 1;
      // Cumpriu o alvo de equilíbrio? Fecha, desde que sobre linha para os
      // blocos que faltam.
      const podeFechar = alvo > 0 && acumulado >= alvo && !ultima;
      if (ultima || podeFechar) {
        out.push({ de, ate: i, celulas: acumulado });
        de = i + 1;
        acumulado = 0;
      }
    }
    return out;
  };

  const semAlvo = cortarCom(0);
  // Passada 2: agora que o número REAL de blocos é conhecido, reparte parejo.
  // Sem isto o último bloco vira um toco de uma linha, curto demais para ancorar.
  const alvo = soma / semAlvo.length;
  const cortes = cortarCom(alvo);
  const reais = cortes.length;
  return cortes.map((c, k) => ({
    bloco: k + 1,
    // O DECLARADO TEM DE SER O REAL: se a instrução diz "bloco 2 de 3" num plano
    // de 2, o modelo procura um terço que não existe.
    blocos: reais,
    de: c.de,
    ate: c.ate,
    ancoraInicio: lista[c.de],
    ancoraFim: lista[c.ate],
    celulas: c.celulas,
    linhas: c.ate - c.de + 1,
    // UMA LINHA SÓ QUE JÁ PASSA DO TETO. Não há corte mais fino que a linha, e o
    // caso não pode ficar em silêncio: é o único resíduo de truncamento que
    // sobra depois desta correção, e ele tem de aparecer para quem lê a execução.
    acimaDoTeto: c.celulas > max,
  }));
}

/**
 * A instrução que vai na mensagem de USER do bloco (nunca no prompt de sistema:
 * o prefixo tem de continuar idêntico em toda chamada para o cache valer).
 */
export function instrucaoDaFatia(fatia) {
  if (!fatia || !(fatia.blocos > 1)) return '';
  return ' ATENCAO -- EXTRACAO EM BLOCOS: este documento e' + ' grande demais para uma resposta so, '
    + 'entao voce esta extraindo o BLOCO ' + fatia.bloco + ' DE ' + fatia.blocos + '. '
    + 'Extraia SOMENTE as linhas de valor a partir da linha que aparece no documento como "'
    + String(fatia.ancoraInicio || '').slice(0, 160) + '" ate a linha "'
    + String(fatia.ancoraFim || '').slice(0, 160) + '", ambas INCLUSIVE, na ordem de leitura. '
    + 'Nao extraia nada antes da primeira nem depois da ultima: os outros blocos cobrem o resto, '
    + 'e linha repetida entre blocos vira dado duplicado. O diagnostico do documento (entidade, '
    + 'tipo, periodo, moeda, escala) deve descrever o DOCUMENTO INTEIRO, nao so este bloco.';
}

/**
 * Junta os blocos de um documento em um conjunto único de campos.
 *
 * A EMENDA É O PONTO DELICADO. As âncoras dizem ao modelo onde começar e onde
 * parar, mas o limite entre dois blocos é o lugar onde ele pode repetir uma
 * linha — e linha repetida vira valor contado duas vezes no book, que é
 * exatamente a classe de erro que o invariante "uma conta, um lugar" persegue.
 *
 * A limpeza é deliberadamente ESTREITA: só remove, do começo do bloco seguinte,
 * linhas idênticas (mesma chave, mesma coluna, mesmo valor) às do FIM do bloco
 * anterior. Não é dedupe global — num livro razão a mesma conta com o mesmo
 * valor aparece legitimamente várias vezes ao longo do documento, e apagá-las
 * seria destruir dado real para consertar um problema de costura.
 */
export function juntarBlocos(blocos) {
  const lista = (Array.isArray(blocos) ? blocos : [])
    .filter((b) => b && typeof b === 'object')
    .slice()
    .sort((a, b) => (Number(a.bloco) || 0) - (Number(b.bloco) || 0));

  const campos = [];
  const motivos = [];
  let emendasLimpas = 0;

  // O BLOCO QUE NÃO CHEGOU, e por que ele precisava de um assert próprio.
  //
  // Até 31/08 esta função devolvia `blocos: lista.length` — quantos blocos
  // CHEGARAM — e nada mais. O número que o `Fatiar Extracao` PLANEJOU viaja em
  // cada bloco (`b.blocos`) e não era lido por ninguém. Consequência medida: um
  // documento fatiado em 4 que perde o bloco 2 devolve `blocos: 3`, `motivos:
  // []`, e cobertura 0,75 — a pendência de `extracao_falhou` diz "lido em 3
  // bloco(s)", indistinguível de um documento cujo plano era 3.
  //
  // Isso importa mais do que um motivo a mais na fila: a `0154` existe para
  // responder a pergunta que a rodada de 190 deixou aberta — sub-extração é
  // TETO do modelo ou fatiamento? —, e o instrumento dela é justamente esta
  // contagem. Reportando o recebido, ela não separa "o plano era 1" de "o plano
  // era 4 e chegou 1", que são as duas hipóteses que ela deveria distinguir.
  //
  // O PLANO É O MÁXIMO DECLARADO, e não o do primeiro bloco: se o bloco 1 for
  // justamente o que se perdeu, o primeiro que chega continua carregando o
  // total. Bloco no formato antigo (sem `blocos`) não declara plano nenhum, e aí
  // não há o que afirmar — cai no recebido, sem inventar divergência.
  // Sem `b &&`: `lista` já saiu do filtro de objeto no topo da função, então a
  // guarda era morta — e a linha do `chegaram`, cinco abaixo, já lia `b.bloco`
  // direto. Duas formas para a mesma garantia na mesma função ensinam a
  // desconfiar da que não tem guarda, que é justamente a correta.
  const planoDeclarado = lista
    .map((b) => Number(b.blocos))
    .filter((n) => Number.isFinite(n) && n > 0);
  const blocosPlanejados = planoDeclarado.length > 0
    ? Math.max(lista.length, ...planoDeclarado)
    : lista.length;
  if (blocosPlanejados > lista.length) {
    const chegaram = new Set(lista.map((b) => Number(b.bloco)).filter((n) => Number.isFinite(n)));
    const faltando = [];
    for (let n = 1; n <= blocosPlanejados; n += 1) if (!chegaram.has(n)) faltando.push(n);
    // A frase nomeia o bloco porque é o que se pergunta primeiro ao investigar, e
    // diz o EFEITO — sem isso, "faltou bloco" parece um aviso de infraestrutura
    // em vez do que é: um pedaço do documento que não está no banco.
    motivos.push(
      `FALTOU BLOCO: o fatiamento planejou ${blocosPlanejados} bloco(s) e chegaram ${lista.length}`
      + (faltando.length > 0 ? ` — ausente(s): ${faltando.join(', ')}` : '')
      + '. As linhas desse trecho do documento NÃO foram gravadas, e a cobertura abaixo mede o'
      + ' documento SEM elas: a sub-extração aqui é perda de bloco, não leitura parcial do modelo.',
    );
  }
  // OS FATOS MATERIAIS SÃO ADITIVOS ENTRE BLOCOS, e o resto do diagnóstico não.
  //
  // Entidade, tipo e período são propriedades do DOCUMENTO: todo bloco responde
  // a mesma coisa, e quem chama pega a do primeiro — está certo. Os fatos não:
  // cada bloco vê um PEDAÇO diferente do texto, então o covenant declarado na
  // página 40 chega no bloco 2 e some se só o bloco 1 for lido.
  //
  // Era o defeito: `diagnostico: blocos[0].diagnostico` descartava em silêncio
  // os fatos de todos os blocos seguintes — e os documentos fatiados são
  // justamente os grandes, que são onde nota explicativa mora (no book, o
  // `35_Demonstracoes_Contabeis` e o `01_Balanco` saem em 2 blocos cada).
  const fatos = [];
  const vistos = new Set();
  let algumBlocoLeuFatos = false;
  const linhas = new Set();
  const chaveDaLinha = [];   // paralelo a `campos`: qual linha do documento originou cada par
  const assinatura = (c) => [c.chave, c.entidade_coluna, c.periodo_coluna, c.valor_texto, c.valor_num].join('\u0001');

  for (const b of lista) {
    const doBloco = Array.isArray(b.campos) ? b.campos.slice() : [];
    if (campos.length > 0 && doBloco.length > 0) {
      // Janela de 3: a repetição de emenda é de uma ou duas linhas na prática, e
      // uma janela grande começaria a comer dado legítimo.
      const cauda = campos.slice(-3).map(assinatura);
      while (doBloco.length > 0 && cauda.includes(assinatura(doBloco[0]))) {
        doBloco.shift();
        emendasLimpas += 1;
      }
    }
    for (const c of doBloco) {
      campos.push(c);
      // LINHAS do documento devolvidas, contadas DEPOIS da limpeza da emenda.
      // Cada bloco numera as suas a partir de zero, então a chave leva o bloco.
      const chave = Number.isInteger(c.linha_origem) ? `${b.bloco}:${c.linha_origem}` : null;
      chaveDaLinha.push(chave);
      if (chave !== null) linhas.add(chave);
    }
    // A DEDUPLICAÇÃO É NECESSÁRIA porque os blocos se SOBREPÕEM de propósito (a
    // emenda repete a âncora, ver a limpeza acima): um fato que caia na região
    // de emenda é declarado duas vezes, e dois alertas idênticos numa lista
    // curta ensinam a desconfiar dela.
    //
    // A chave é (tipo + trecho normalizado), não o objeto inteiro: o mesmo
    // trecho pode voltar com a página do bloco 1 e a do bloco 2, e continua
    // sendo o mesmo fato. `null` (bloco que não leu fatos) é diferente de `[]`,
    // e a distinção sobe até o banco.
    if (Array.isArray(b.diagnostico?.fatos)) {
      algumBlocoLeuFatos = true;
      for (const f of b.diagnostico.fatos) {
        if (!f || typeof f !== 'object') continue;
        const chave = `${f.tipo}\u0000${String(f.trecho ?? '').toLowerCase().replace(/\s+/g, ' ').trim()}`;
        if (vistos.has(chave)) continue;
        vistos.add(chave);
        fatos.push(f);
      }
    }
    if (b.falha_motivo) motivos.push(`bloco ${b.bloco}: ${b.falha_motivo}`);
    // O RESÍDUO DE TRUNCAMENTO QUE O FATIAMENTO NÃO RESOLVE. Uma linha que
    // sozinha já passa do teto de saída não tem corte mais fino — ela é a
    // âncora, e meia âncora não localiza nada no PDF. Isso tem de chegar à fila
    // de revisão: é a diferença entre "não deu" e a perda silenciosa que as três
    // camadas existem para acabar.
    if (b.bloco_acima_do_teto) {
      motivos.push(`bloco ${b.bloco}: uma linha sozinha já passa do teto de saída do modelo — `
        + 'não há corte mais fino que a linha, e a resposta deste bloco pode ter vindo cortada');
    }
  }

  // `ordem` é renumerada no conjunto: ela significa "posição na leitura do
  // documento" e é o que permite ao export reconhecer subtotal impresso acima
  // dos componentes. Cada bloco numera a partir de zero, então manter a
  // numeração do bloco faria o documento ter três linhas de `ordem` 0.
  //
  // `linha_origem` SAI aqui: ele serviu para contar as linhas e não tem lugar em
  // `campo_extraido`. O que vai ao banco continua sendo exatamente o que sempre
  // foi — acrescentar coluna a uma tabela de dado por causa de uma contagem
  // interna seria pagar migration por uma variável de laço.
  // …e `ordem` é a ordem da LINHA, não do par (conta × coluna).
  //
  // O DEFEITO QUE ISTO CORRIGE, medido no export da rodada v46 (17/08): a mesma
  // conta de um balanço comparativo saía em TRÊS linhas do Excel, uma por
  // exercício, com as outras colunas vazias — "Caixa e bancos conta movimento"
  // aparecia em 2023, de novo em 2024 e de novo em 2025. O comparativo não
  // comparava.
  //
  // A causa é de unidade, outra vez. A `0027` define `ordem` como "posição na
  // leitura do DOCUMENTO", e o export conta com isso: ele desempata rótulo
  // repetido (dois "Outros" num balancete) pelo rank de `ordem` dentro da versão,
  // supondo que o mesmo rótulo só se repete quando são linhas diferentes. Quando
  // a saída passou a ser AGRUPADA (uma conta com um valor por coluna), o
  // achatamento numerou PARES, então uma conta com três colunas virou três
  // `ordem` distintas — e o export, corretamente segundo a regra dele, entendeu
  // três linhas diferentes.
  //
  // Agora os três pares de uma conta compartilham a `ordem` da linha que os
  // originou. Rótulo genuinamente repetido continua com `ordem` diferente e
  // continua em linhas separadas — que é o que a `0027` sempre quis dizer.
  const ordemDaLinha = new Map();
  let proxima = 0;
  const renumerados = campos.map((c, i) => {
    const { linha_origem, ...resto } = c;
    const chave = chaveDaLinha[i];
    // Bloco no formato plano antigo (sem `linha_origem`): cada campo é uma linha,
    // que é exatamente o que ele era antes desta correção.
    if (chave === null) return { ...resto, ordem: proxima++ };
    if (!ordemDaLinha.has(chave)) ordemDaLinha.set(chave, proxima++);
    return { ...resto, ordem: ordemDaLinha.get(chave) };
  });
  return {
    campos: renumerados,
    motivos,
    emendasLimpas,
    blocos: lista.length,
    // O PLANO, ao lado do recebido. Os dois viajam juntos de propósito: quem lê
    // um número de blocos precisa saber se ele é o que se queria ou o que sobrou.
    blocosPlanejados,
    // Zero significa "não dá para saber" (bloco no formato plano antigo, sem
    // `linha_origem`), e quem chama trata isso caindo para as contas distintas —
    // o comportamento de antes desta correção.
    linhasRetornadas: linhas.size,
    // `null` quando NENHUM bloco trouxe a chave `fatos` (workflow antigo), `[]`
    // quando algum leu e não achou nada. A distinção não é estética: no banco,
    // `null` manda NÃO TOCAR nos fatos já gravados e `[]` manda apagá-los.
    fatos: algumBlocoLeuFatos ? fatos : null,
  };
}

/**
 * A guarda de cobertura. Devolve `null` quando não há o que dizer — e "não há o
 * que dizer" é o caso comum, então ela não polui a fila de revisão.
 */
export function avaliarCobertura({ extraidas, esperadas, limiar = LIMIAR_COBERTURA, minimo = MINIMO_PARA_AVALIAR }) {
  // `extraidas` = LINHAS que a extração devolveu; `esperadas` = LINHAS DE CONTA
  // do texto. As duas na mesma unidade, e foi preciso errar isso DUAS vezes para
  // chegar aqui:
  //   • pares (conta × coluna) contra linhas → 198% num documento incompleto, a
  //     guarda cega justamente no comparativo;
  //   • contas DISTINTAS contra linhas → 66% num livro razão PERFEITO, porque o
  //     mesmo histórico se repete em lançamentos diferentes e some na contagem.
  // Linha contra linha não tem nenhum dos dois vieses: uma conta com três colunas
  // conta uma vez, e dois lançamentos do mesmo fornecedor contam dois.
  const e = Number(extraidas);
  const t = Number(esperadas);
  if (!Number.isFinite(e) || !Number.isFinite(t) || t < minimo) return null;
  const razao = t > 0 ? e / t : 1;
  if (razao >= limiar) return null;
  return {
    razao: Number(razao.toFixed(3)),
    extraidas: e,
    esperadas: t,
    motivo:
      `Extração INCOMPLETA: ${e} linha(s) devolvida(s) para um documento com ${t} linha(s) `
      + `de conta no texto (${(razao * 100).toFixed(0)}% de cobertura, abaixo do mínimo de `
      + `${(limiar * 100).toFixed(0)}%). A contagem do documento é feita sobre o texto do PDF, sem IA: `
      + `linha que tem valor e tem identidade — rótulo, código de conta, ou linha de tabela numérica —, `
      + `descontados cabeçalho de ano, CNPJ, data, número de página e bloco de assinatura. As duas `
      + `medidas estão na MESMA unidade (LINHAS do documento: uma conta com três colunas conta uma vez, `
      + `e dois lançamentos com o mesmo histórico contam dois), então a diferença é dado que o modelo `
      + `deixou de ler — conferir o documento na fila de revisão antes de usar o book. A régua erra para `
      + `cima em cerca de 3% (costuma contar o cabeçalho de colunas como linha), o que já está `
      + `descontado na folga do limiar.`,
  };
}

// ===========================================================================
// SEGUNDA PASSADA POR COBERTURA — o bloco que volta pela metade é refeito UMA vez.
// ===========================================================================
//
// O DEFEITO. Caso real Fw Valtra: "36 ALTERAÇÃO E CONSOLIDAÇÃO CONTRATUAL - MOTO
// AGRICOLA.pdf" saiu com "59 linha(s) devolvida(s) para um documento com 101
// linha(s) de conta no texto (58% de cobertura)". A guarda de cobertura (acima) já
// tornava isso VISÍVEL; ela nunca o corrigia, e a correção possível custa uma
// chamada. O modelo, sem `temperature` (família GPT-5 recusa), não é determinístico:
// a mesma pergunta dita de novo, agora com o número que faltou, tem chance real de
// vir completa — e o pior caso é pagar uma chamada e ficar com a primeira.
//
// O QUE ISTO NÃO FAZ. Não SOMA as duas respostas: as duas descrevem as MESMAS
// linhas, e somar duplicaria cada conta que as duas acharam — o erro que o
// invariante "uma conta, um lugar" persegue. Fica a que devolveu MAIS linhas
// (`melhorPassada`), e a empate fica a primeira, que já estava paga e já passou
// por tudo o que o fluxo faz com ela.
//
// O LIMIAR É O DO DOCUMENTO (`LIMIAR_COBERTURA`), de propósito um número só: "o
// bloco que, sozinho, abriria a pendência de cobertura". A régua que o sustenta
// está medida em `medir-regua-cobertura.mjs` — exata (erro 0,0%) nos 20 documentos
// capturados de produção, extração perfeita a 100%. Errar para refazer à toa custa
// uma chamada e nenhum dado (fica a melhor); errar para NÃO refazer deixa a falha
// onde estava. Por bloco a soma dos denominadores fecha com a do documento por
// construção (`contasPorLinhaComNumero`); o que não dá para medir sem chamar o
// modelo é o quanto ele respeita as âncoras de corte, e é por isso que o mínimo
// para avaliar (`MINIMO_PARA_AVALIAR`) vale por bloco também.

/**
 * Quantas LINHAS do documento uma passada devolveu — a unidade da cobertura.
 * `null` quando a resposta veio no formato plano antigo (sem `linha_origem`):
 * aí não há como medir, e quem chama não refaz nem acusa. Auto-contida.
 */
export function linhasDaPassada(campos) {
  const vistas = new Set();
  let semOrigem = false;
  for (const c of Array.isArray(campos) ? campos : []) {
    if (c && Number.isInteger(c.linha_origem)) vistas.add(c.linha_origem);
    else semOrigem = true;
  }
  return vistas.size === 0 && semOrigem ? null : vistas.size;
}

/**
 * O bloco deve ser refeito? `linhas` = linhas devolvidas por ele; `esperadas` =
 * contas do TEXTO naquela faixa (`contas_do_bloco`). Devolve sempre o veredito
 * inteiro, porque o `Parse Extracao` precisa dos dois: refazer ou, se não puder,
 * DIZER por que não (`porque`) — bloco abaixo do limiar que não foi refeito sem
 * explicação é o silêncio que a regra 1 proíbe.
 *
 *   abaixo  — a cobertura do bloco é medível e está abaixo do limiar.
 *   refazer — abaixo, ainda não foi refeito e sobra tentativa no teto do bloco.
 *   porque  — 'ja-refeita' | 'sem-tentativa' | null.
 *
 * Mesma exceção da guarda do documento (a `0111`): zero linhas devolvidas por um
 * documento que o modelo declarou SEM dado financeiro (certidão, organograma) não
 * é falha, e refazê-lo seria pagar por nada. Zero linhas SEM essa declaração
 * continua sendo falha. Auto-contida (usa `avaliarCobertura`, embutida antes).
 */
export function decidirSegundaPassada({
  linhas, esperadas, tentativa = 1, maxTentativas = 4, temDadoFinanceiro = null, jaRefeita = false,
} = {}) {
  const nada = { abaixo: false, refazer: false, razao: null, esperadas: null, porque: null };
  if (linhas === null || linhas === undefined || !Number.isFinite(Number(linhas))) return nada;
  const cob = avaliarCobertura({ extraidas: Number(linhas), esperadas });
  if (cob === null) return nada;
  if (Number(linhas) === 0 && temDadoFinanceiro === false) return nada;
  const sobra = Number(tentativa) < Number(maxTentativas);
  const refazer = !jaRefeita && sobra;
  return {
    abaixo: true,
    refazer,
    razao: cob.razao,
    esperadas: cob.esperadas,
    porque: refazer ? null : (jaRefeita ? 'ja-refeita' : 'sem-tentativa'),
  };
}

/** Qual das duas passadas fica: a que devolveu MAIS linhas; empate, a primeira. */
export function melhorPassada(linhasDaPrimeira, linhasDaSegunda) {
  const a = Number.isFinite(Number(linhasDaPrimeira)) ? Number(linhasDaPrimeira) : 0;
  const b = Number.isFinite(Number(linhasDaSegunda)) ? Number(linhasDaSegunda) : 0;
  return b > a ? 'segunda' : 'primeira';
}

/**
 * A instrução da segunda passada, na mensagem de USER (nunca no prompt de
 * sistema: o prefixo tem de continuar idêntico para o cache de prefixo valer). Dá
 * ao modelo o NÚMERO — quantas linhas ele devolveu e quantas o texto tem — porque
 * "seja completo" sem número é o pedido que a primeira chamada já recebeu. E diz
 * que a resposta SUBSTITUI a anterior: se ele devolvesse só as linhas que faltaram,
 * `melhorPassada` ficaria com a primeira e o trabalho se perderia.
 * ASCII de propósito (vai dentro de um template literal do gerador).
 */
export function instrucaoDeSegundaPassada({ linhas, esperadas, blocos = 1 }) {
  const e = Number(esperadas) > 0 ? Number(esperadas) : 0;
  const pct = e > 0 ? Math.round((100 * Number(linhas)) / e) : 0;
  const onde = blocos > 1 ? 'deste bloco' : 'deste documento';
  return ' ATENCAO -- SEGUNDA PASSADA POR COBERTURA: a leitura anterior ' + onde + ' devolveu '
    + Number(linhas) + ' linha(s) para cerca de ' + e + ' linhas de conta que o texto do PDF contem ('
    + pct + '%), ou seja, deixou linhas para tras. Releia ' + (blocos > 1 ? 'a faixa deste bloco' : 'o documento')
    + ' e devolva TODAS as linhas que tem rotulo e valor, uma a uma, na ordem de leitura, sem pular, '
    + 'sem resumir e sem agrupar; subtotais e totais impressos tambem sao linhas. Nao omita uma linha '
    + 'por ela parecer repetida (o mesmo rotulo ocorre em lancamentos diferentes). Esta resposta '
    + 'SUBSTITUI a anterior em vez de complementa-la: devolva a faixa completa, nao so o que faltou.';
}

// ===========================================================================
// PDF COM CAMADA DE TEXTO x PDF ESCANEADO — qual dos dois vai à IA.
// ===========================================================================
//
// O DESPERDÍCIO QUE ISTO FECHA. Até 12/09/2026 CADA PDF ia à IA como ARQUIVO
// (base64), que o provedor cobra como IMAGEM: ~1.000 tokens por página, contra
// ~250 tokens por mil caracteres do mesmo conteúdo em texto. Um balanço de 2
// páginas com camada de texto de 7 KB custava 2.000 tokens de entrada onde
// 1.750 CARACTERES bastariam — e o `Extrair Texto` já lia esse texto de graça,
// na própria instância, só para MEDIR cobertura. O conteúdo estava na mão e era
// jogado fora.
//
// MAS NEM SEMPRE DÁ PARA LER ASSIM, e é isso que esta função decide. PDF
// escaneado não tem camada de texto: o `Extrair Texto` devolve vazio ou um
// punhado de lixo, e mandar ISSO à IA no lugar do documento é o defeito da AMO
// de novo — ausência apresentada como dado (regra 1). Esse precisa ir como
// imagem, para o modelo ler com a visão. A escolha é por documento e é MEDIDA,
// não suposta.
//
// OS DOIS CRITÉRIOS, e o segundo é o que importa nesta base:
//
//   1. DENSIDADE POR PÁGINA. Um PDF de 20 páginas escaneadas em que só a capa
//      tem texto não é "um PDF com camada de texto" — é um escaneado com uma
//      página a mais. Medir o total de caracteres esconderia isso; medir por
//      página, não.
//   2. LINHAS COM NÚMERO. Numa demonstração financeira o NÚMERO é a carga.
//      Uma camada de texto que traz o cabeçalho, o CNPJ e o rodapé do contador
//      mas nenhum valor é pior que inútil: passa nos critérios de tamanho e
//      entrega à IA um documento sem os dados. Aqui isso reprova e o documento
//      vai para a visão, que é onde os números estão.
//
// Devolve SEMPRE o motivo junto, porque `leitura_pdf`/`leitura_pdf_motivo`
// viajam com o item até o banco: quem olhar um documento sem linhas precisa
// conseguir distinguir "foi lido por OCR e o modelo não achou nada" de "foi
// lido como texto e o texto não tinha números".

/** Abaixo disto, o que veio é mobília de página (cabeçalho, rodapé), não conteúdo. */
export const CARACTERES_MINIMOS_POR_PAGINA = 120;

/** Demonstração financeira sem número na camada de texto tem os números na IMAGEM. */
export const MINIMO_LINHAS_COM_NUMERO_PDF = 3;

// CAMADA DE TEXTO CORROMPIDA POR GLIFO DOBRADO — o terceiro critério, e o que
// impede esta otimização de PIORAR o dado.
//
// MEDIDO nos documentos reais do dono (12/09/2026). Quando o PDF simula negrito
// desenhando o mesmo glifo duas vezes com deslocamento, o extrator de texto lê
// as DUAS cópias e devolve `Empprreessaa::` no lugar de `Empresa:`. O estrago
// não para no rótulo: chega aos NÚMEROS — `2.2272.055,77` por `2.272.055,77`,
// `12.3330.33994,7799D` por `12.330.394,79`.
//
// A fração de palavras com letra repetida separa os dois mundos com folga:
//
//     texto limpo (referência)........  3,6%   (português tem "ss", "rr", "ll")
//     OMNIBEAUTY DRE / Faturamento....  3,8% e 5,3%
//     GENERAL TABACO Balanço.......... 37,9%   <- camada corrompida
//     AMOBELEZA Balanço............... 73,0%   <- camada corrompida
//
// SEM ESTE CRITÉRIO a leitura por texto seria uma REGRESSÃO nesses dois
// documentos: a visão do modelo lê a página renderizada e enxerga `2.272.055,77`;
// a camada de texto entrega `2.2272.055,77`, e o número entra no banco errado,
// com a mesma aparência de um número certo. Economizar entrada mandando dado
// corrompido é a troca que este projeto não faz — e seria a regra 1 violada
// pelo caminho mais caro: não a ausência apresentada como dado, mas o ERRO.
//
// O LIMIAR É 20% porque é o meio da terra de ninguém entre 5,3% e 37,9%. Não é
// calibração fina: é uma linha no vazio entre duas populações que não se tocam.
export const MAX_FRACAO_PALAVRAS_DOBRADAS = 0.20;

/** Palavras (4+ letras) com alguma letra imediatamente repetida, sobre o total. */
export function fracaoDePalavrasDobradas(texto) {
  const palavras = String(texto || '').match(/[A-Za-zÀ-ÿ]{4,}/g);
  if (!palavras || palavras.length === 0) return 0;
  const dobradas = palavras.filter((p) => /(.)\1/i.test(p)).length;
  return dobradas / palavras.length;
}

export function camadaDeTextoDoPdf(texto, {
  paginas = 1,
  minPorPagina = CARACTERES_MINIMOS_POR_PAGINA,
  minLinhasComNumero = MINIMO_LINHAS_COM_NUMERO_PDF,
  maxDobradas = MAX_FRACAO_PALAVRAS_DOBRADAS,
} = {}) {
  const t = typeof texto === 'string' ? texto.trim() : '';
  // `paginas` ausente vira 1, e o efeito é o conservador: exige a densidade de
  // UMA página inteira do texto que chegou. Nunca vira 0 — divisão por zero
  // devolveria Infinity e aprovaria qualquer lixo.
  const pags = Math.max(1, Number(paginas) || 1);
  const porPagina = t.length / pags;
  const comNumero = t === '' ? 0 : linhasComNumero(t).length;
  const base = { caracteres: t.length, paginas: pags, porPagina: Math.round(porPagina), linhasComNumero: comNumero };

  if (t === '') {
    return { ...base, usarTexto: false, motivo: 'sem-camada-de-texto',
      explicacao: 'o PDF não trouxe texto nenhum — é escaneado, e vai à IA como imagem' };
  }
  if (porPagina < minPorPagina) {
    return { ...base, usarTexto: false, motivo: 'texto-ralo',
      explicacao: `o texto extraído dá ${Math.round(porPagina)} caractere(s) por página `
        + `(mínimo ${minPorPagina}): é mobília de página, não o documento — vai à IA como imagem` };
  }
  if (comNumero < minLinhasComNumero) {
    return { ...base, usarTexto: false, motivo: 'texto-sem-numeros',
      explicacao: `a camada de texto tem ${comNumero} linha(s) com número (mínimo ${minLinhasComNumero}): `
        + 'os valores estão na imagem, não no texto — vai à IA como imagem' };
  }
  const dobradas = fracaoDePalavrasDobradas(t);
  if (dobradas > maxDobradas) {
    return { ...base, usarTexto: false, motivo: 'camada-de-texto-corrompida', fracaoDobradas: dobradas,
      explicacao: `${Math.round(dobradas * 100)}% das palavras têm letra repetida (teto ${Math.round(maxDobradas * 100)}%): `
        + 'a camada de texto deste PDF está corrompida por glifo dobrado e os NÚMEROS saem errados — '
        + 'vai à IA como imagem, que é onde o documento está correto' };
  }
  return { ...base, usarTexto: true, motivo: 'camada-de-texto', fracaoDobradas: dobradas,
    explicacao: `camada de texto com ${t.length} caractere(s) e ${comNumero} linha(s) com número — `
      + 'vai à IA como TEXTO, sem custo de imagem' };
}
