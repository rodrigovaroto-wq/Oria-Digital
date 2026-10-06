// Extração + DIAGNÓSTICO do documento (E2) via IA — modo SOMBRA (N0/N1).
//
// QUEM é a IA está em `lib/provedor.mjs` e este arquivo não sabe: ele monta a
// chamada e lê a resposta pelas funções de lá. O que muda com o provedor é
// endereço, formato de corpo e forma da resposta; o que NÃO muda — o prompt, o
// schema, a normalização de escala e moeda, o diagnóstico de erro — é tudo o que
// está escrito aqui.
//
// Antes, esta chamada só extraía linhas financeiras (chave+valor). Ela já
// rodava SEMPRE (para todo documento, independente da confiança da
// classificação por nome) — então virou o lugar natural para resolver 3
// lacunas encontradas em produção:
//   1. Entidade nunca era extraída quando o nome do arquivo já dava confiança
//      alta no tipo/período (o fallback de classificação por conteúdo nunca
//      rodava para esses casos, e SÓ ele buscava entidade).
//   2. Não havia diagnóstico de conteúdo nenhum nesses casos: nada conferia
//      se o tipo/período do nome batem com o que está escrito dentro, nem
//      sinalizava qualidade/legibilidade real do arquivo.
//   3. As linhas extraídas vinham em lista achatada, sem agrupamento — difícil
//      de ler como uma "planilha" organizada (Ativo Circulante, Passivo
//      Circulante, PL, etc.).
//
// Uma ÚNICA chamada agora faz as duas coisas (não aumenta o número de
// chamadas à OpenAI): extrai linhas com `secao` (o agrupador IMEDIATO, espelha a
// estrutura do documento original) E devolve um bloco `diagnostico` (entidade,
// confere tipo/período, legibilidade, resumo, justificativa).
//
// Doutrina (Arquitetura do Sistema/1 Visão e Doutrina/01): tudo aqui continua SUGESTÃO. Nada decide sozinho —
// diagnóstico gera pendência tipada para revisão humana (ver
// Supabase/migrations/0010_diagnostico_e1e2.sql → fn_registrar_diagnostico);
// linhas continuam em N0 (sombra), sem entrar em base sem aceite humano.

import { codigosConhecidos } from './ia.mjs';
import {
  provedor, urlDaChamada, montarCorpoIA, parteDeTexto, conteudoDaResposta, cortadoPorLimite,
} from './provedor.mjs';
import { MODELO_EXTRACAO, esforcosDoProvedor } from './custo.mjs';

const DEFAULT_MODEL = MODELO_EXTRACAO;

// O esforço de raciocínio da EXTRAÇÃO, pela regra do dono (ver `escolherEsforco`
// em `custo.mjs`). É `null` em provedor que não raciocina, e `montarCorpoIA` só
// escreve o campo quando o modelo o aceita.
const DEFAULT_ESFORCO = esforcosDoProvedor().extracao?.esforco ?? null;

const PERIODO_TIPO_ENUM = ['anual', 'trimestre', 'multi', 'data-base', 'outro', 'desconhecido'];

// Seção CANÔNICA sugerida pela IA por linha (N1 — sugestão, não fato). É o
// mesmo conjunto de chaves internas do classificador do export
// (portal/src/lib/statement-templates.ts) — mantê-los IDÊNTICOS: se um lado
// mudar, o outro precisa acompanhar (não há import cruzado entre .mjs e o
// portal TS). Serve para o classificador determinístico do export ter um
// sinal interpretativo forte QUANDO ele mesmo não consegue classificar por
// regra — reduz o bloco "Contas Não Classificadas" sem virar fato (a linha
// continua pendente/âmbar até o aceite humano). "NAO_CLASSIFICAVEL" é o
// escape (a IA não força um palpite ruim — deixa cair no bloco de revisão).
export const SECAO_CANONICA_ENUM = [
  'ativo_circulante', 'ativo_nao_circulante',
  'passivo_circulante', 'passivo_nao_circulante', 'patrimonio_liquido',
  'receita_bruta', 'custos', 'despesas_operacionais', 'resultado_financeiro', 'impostos_lucro',
  'atividades_operacionais', 'atividades_investimento', 'atividades_financiamento',
  // DMPL e DVA (Supabase/migrations/0024). Não são seções de outra demonstração: são
  // demonstrações INTEIRAS, e é por isso que precisam de valor próprio aqui.
  // Sem elas, a linha de uma DMPL embutida num PDF composto só tinha dois
  // destinos ruins — "patrimonio_liquido" (o saldo de fechamento REPETE o total
  // do PL, então somá-lo INFLA o balanço: bug real do export do dono) ou
  // "NAO_CLASSIFICAVEL". Com o valor próprio, a linha é roteada para a aba da
  // sua demonstração, do mesmo jeito que Balanço/DRE/Fluxo já são.
  'dmpl', 'dva',
  'NAO_CLASSIFICAVEL',
];

// OS TIPOS DE FATO MATERIAL — espelho de `fato_tipo_catalogo` (Supabase/migrations/0148).
//
// POR QUE HÁ DUAS CÓPIAS, e por que isso é aceitável aqui: o enum precisa ir no
// `responseSchema` da chamada de IA (onde o banco não alcança) e a SEVERIDADE
// precisa morar no banco (onde a tela alcança). São dois consumidores em dois
// mundos, sem import cruzado — o mesmo arranjo de `SECAO_CANONICA_ENUM` acima.
//
// O que impede as duas cópias de divergirem em silêncio é um teste, não a boa
// vontade: `Supabase/test/fato_material.test.sql` compara esta lista com o catálogo do
// banco e reprova na primeira diferença. Um tipo que exista só aqui é recusado
// por `fn_registrar_fatos` como "tipo desconhecido" — o fato seria lido do
// documento e jogado fora, que é o pior desfecho possível para esta fatia.
export const FATO_TIPO_ENUM = [
  'continuidade_operacional',
  'ressalva_auditoria',
  'covenant_rompido',
  'reclassificacao_divida',
  'litigio_relevante',
  'garantia_dada',
  'evento_subsequente',
  'parte_relacionada',
  'mudanca_criterio_contabil',
];

// Exportado de propósito: `build-workflow.mjs` embute ESTE texto no nó Code do
// workflow (via JSON.stringify), em vez de manter uma paráfrase manual. Antes
// havia três cópias do prompt (aqui, no gerador e no JSON gerado) e elas já
// tinham divergido de fato — uma melhoria aplicada aqui não chegava à produção
// até alguém reescrever o mirror à mão. Fonte única agora.
export const SYSTEM_PROMPT = [
  'Você analisa UM documento financeiro de um mandato de Reestruturação (contexto Brasil) e',
  'devolve DUAS coisas: um diagnóstico do documento e a extração linha a linha de TODOS os',
  'dados financeiros nele contidos, organizados como uma planilha.',
  '',
  '== DIAGNÓSTICO ==',
  'entidade: razão social da empresa dona do documento, se aparecer no conteúdo (null se não',
  '  visível — NUNCA invente). NÃO use o nome de quem ASSINOU o documento (contador, administrador,',
  '  sócio) — o bloco de assinatura (com CRC, CPF, "Contador", "Administrador") é o SIGNATÁRIO, não',
  '  a entidade. Se o documento combina VÁRIAS empresas (colunas por empresa — ver LINHAS abaixo),',
  '  use o nome do GRUPO se houver um; senão deixe null (não escolha uma das empresas ao acaso).',
  'cnpj: o CNPJ da MESMA empresa que você indicou em "entidade" — 14 dígitos, com ou sem',
  '  pontuação; null se não estiver visível (NUNCA invente, e NUNCA derive de outro documento).',
  '  ATENÇÃO, e este é o erro mais caro deste campo: documento contábil brasileiro costuma trazer',
  '  VÁRIOS CNPJs na mesma página — o do ESCRITÓRIO DE CONTABILIDADE que emitiu o relatório (perto',
  '  de "CRC", "Contador", "responsável técnico", normalmente no RODAPÉ), o do AUDITOR, e o da',
  '  EMPRESA (normalmente no cabeçalho, junto do nome dela). Só o da empresa dona serve. É o mesmo',
  '  critério do campo "entidade": quem ASSINA não é quem o documento descreve.',
  '  NA DÚVIDA ENTRE DOIS CNPJs, responda null. Um CNPJ errado não deixa o dado incompleto — ele',
  '  FUNDE esta empresa com outra do mesmo mandato, em silêncio, porque o CNPJ tem prioridade',
  '  sobre o nome na identificação. Null é a resposta segura; um palpite não é.',
  'tipo_confirma / tipo_sugerido: você recebe uma DICA de tipo (vinda do nome do arquivo).',
  '  Leia o conteúdo e diga se ele bate (tipo_confirma=true) com a dica. tipo_sugerido é o',
  '  código da taxonomia que o CONTEÚDO sugere (pode ser igual ou diferente da dica — use',
  '  "DESCONHECIDO" só se o documento estiver genuinamente ilegível/não-financeiro).',
  '  BALANCO vs COMBINADO (confusão comum): COMBINADO = demonstrações de um GRUPO de VÁRIAS',
  '  empresas juntas (colunas por empresa: "Empresa A | Empresa B | Total"). Um único arquivo com',
  '  VÁRIAS demonstrações (Balanço + DRE + Fluxo de Caixa + DMPL) de UMA entidade só NÃO é',
  '  COMBINADO — classifique pela demonstração principal (normalmente BALANCO). Regra prática: se',
  '  as linhas têm entidade_coluna preenchido (várias empresas) → COMBINADO; se é uma entidade só',
  '  (mesmo com várias demonstrações no arquivo) → o tipo da demonstração principal.',
  '  DMPL e DVA são códigos próprios: use "DMPL" quando o documento É a Demonstração das Mutações',
  '  do Patrimônio Líquido (linhas de movimentação do PL — saldos de abertura/fechamento, lucro ou',
  '  prejuízo do exercício, dividendos, aumento de capital — com colunas por componente do PL) e',
  '  "DVA" quando é a Demonstração do Valor Adicionado (CPC 09: receitas, insumos adquiridos de',
  '  terceiros, valor adicionado a distribuir e sua distribuição). Se a DMPL/DVA é só UMA das',
  '  demonstrações dentro de um arquivo que traz várias, o tipo do DOCUMENTO continua sendo o da',
  '  demonstração principal — a separação por demonstração acontece linha a linha (secao_canonica).',
  'periodo_tipo / periodo_referencia: o período de competência real do conteúdo. É o período ATUAL',
  '  do documento — NÃO use a data de um SALDO DE ABERTURA/exercício anterior (ex.: uma DMPL que',
  '  mostra "Saldos em 31/12/2023" e "Saldos em 31/12/2024" é um documento de 2024; 2023 é só o',
  '  saldo inicial, não o período). EMITA periodo_referencia SEMPRE numa destas formas exatas',
  '  (notação canônica do sistema — não invente outro formato):',
  '  - exercício anual completo → "12M" + ano de 2 dígitos. Ex.: 2025 → "12M25".',
  '  - trimestre → dígito do trimestre + "T" + ano de 2 dígitos. Ex.: 1º tri/2025 → "1T25".',
  '  - período de N meses corridos (últimos N meses) → "L" + N + "M". Ex.: últimos 24 meses → "L24M".',
  '  - vários exercícios no mesmo documento → anos de 2 dígitos separados por vírgula, em ordem',
  '    crescente. Ex.: 2023, 2024 e 2025 → "23,24,25".',
  '  - data-base (posição numa data específica) → ISO "AAAA-MM-DD". Ex.: 15/01/2025 → "2025-01-15".',
  '  - período de N meses de um ano específico (parcial) → N + "M" + ano de 2 dígitos. Ex.: 9 meses',
  '    de 2024 → "9M24".',
  '  - ACUMULADO NO ANO (YTD): cabeçalho "de janeiro a agosto de 2026", "jan-ago/26", "acumulado até',
  '    agosto" → número de meses + "M" + ano ("8M26") com periodo_tipo "multi". É ERRO emitir "12M26",',
  '    "2026" ou periodo_tipo "anual" para um documento que cobre MENOS de 12 meses: 8 meses',
  '    registrados como o exercício de 2026 fazem a modelagem comparar receita de 8 meses com um ano',
  '    cheio (caso real: DRE jan-ago/2026 saiu "anual 2026"). Olhe o CABEÇALHO do período, não só o ano.',
  '  Use o periodo_tipo coerente com a forma escolhida ("anual", "trimestre", "multi", "data-base").',
  'legibilidade: "ok" | "degradado" | "ilegivel" — avaliação real do ARQUIVO em si (não da',
  '  classificação): páginas faltando, tabela cortada, digitalização ruim, texto ilegível,',
  '  arquivo aparentemente incompleto. nota_legibilidade explica objetivamente QUANDO != "ok"',
  '  (null quando "ok").',
  'tem_dado_financeiro: false SOMENTE quando o documento, por NATUREZA, não tem NENHUM valor',
  '  monetário a extrair — certidões negativas, organograma societário, ata, procuração,',
  '  parecer/relatório de auditoria independente (texto de opinião, sem tabela de valores),',
  '  contrato sem cifra, correspondência. Nesse caso "grupos" vem VAZIO, e isso é o resultado',
  '  CORRETO da extração, não uma falha — não gere pendência de "extração vazia" para estes.',
  '  true em todos os outros casos, inclusive quando você não encontrou nenhuma linha aproveitável',
  '  num documento que deveria ter (aí sim é sinal de falha real, e uma extração com "grupos"',
  '  vazio e tem_dado_financeiro=true dispara revisão humana).',
  'resumo: 2-3 frases objetivas do que o documento contém (para alguém decidir sem abrir o',
  '  arquivo).',
  'justificativa: 1-2 frases explicando o diagnóstico acima (o que você viu ou não viu).',
  '',
  '== FATOS MATERIAIS ("fatos") — o que o documento diz em TEXTO ==',
  'Alguns documentos não têm tabela nenhuma e mesmo assim carregam o fato mais importante do',
  'trabalho: uma nota explicativa que declara covenant rompido, um parecer com ressalva, uma',
  'incerteza sobre continuidade operacional. Eles são o motivo real por trás de números que, sozinhos,',
  'parecem apenas ruins — e quem decide precisa vê-los ANTES da planilha.',
  'Percorra o texto corrido do documento e declare em "fatos" um item para cada ocorrência de:',
  '- continuidade_operacional: dúvida relevante sobre a empresa seguir operando.',
  '- ressalva_auditoria: opinião COM RESSALVA, adversa, ou abstenção de opinião.',
  '- covenant_rompido: índice/cláusula contratada NÃO atingida no período.',
  '- reclassificacao_divida: saldo movido do passivo não circulante para o circulante.',
  '- litigio_relevante: processo ou contingência com valor material declarado.',
  '- garantia_dada: ativo dado em garantia, alienação fiduciária, penhor, ônus.',
  '- evento_subsequente: fato posterior à data do balanço que muda a leitura dele.',
  '- parte_relacionada: operação relevante com controlada, controladora ou sócio.',
  '- mudanca_criterio_contabil: critério que mudou entre exercícios.',
  '',
  'REGRA DA EVIDÊNCIA, e ela é obrigatória: "tr" tem de ser o TRECHO LITERAL do documento —',
  'copiado, não reescrito, não resumido, com no mínimo 20 caracteres. Quem lê o alerta precisa',
  'poder abrir a página e encontrar aquela frase. Um item cujo "tr" seja um resumo seu, ou uma',
  'paráfrase, é DESCARTADO na gravação e o fato se perde. Em "le" vai a leitura — o que aquilo',
  'significa para quem decide, em UMA frase; ela complementa a evidência e nunca a substitui.',
  '',
  'NA DÚVIDA, NÃO DECLARE. Uma nota que menciona a existência de covenants sem dizer que algum foi',
  'rompido NÃO é covenant_rompido; um parecer LIMPO não é ressalva. Alerta falso nesta lista é mais',
  'caro que fato ausente, porque esta lista é curta e é lida primeiro — e uma lista curta com um',
  'item errado é a que ensina o leitor a desconfiar dela inteira.',
  'A resposta comum e CERTA é lista vazia: quase todo documento é tabela e não declara nada disso.',
  '',
  '== MOEDA E ESCALA (nível do documento) ==',
  'moeda: código ISO da moeda em que os valores estão expressos — "BRL" para Real, "USD" para',
  '  dólar, "EUR" para euro. Use o código, não o símbolo. null se não houver indicação nenhuma.',
  'unidade: o FATOR DE ESCALA dos valores, declarado no cabeçalho/título das demonstrações',
  '  ("Em R$ mil", "valores expressos em milhares de reais", "R$ milhões", "em unidades"). Responda',
  '  com UMA destas três palavras exatas, e nada mais:',
  '  - "unidade" → os valores estão em reais inteiros (o caso mais comum; use também quando o',
  '    documento não declara escala nenhuma).',
  '  - "milhar" → os valores estão em milhares (multiplicar por 1.000 para ter o valor real).',
  '  - "milhao" → os valores estão em milhões (multiplicar por 1.000.000).',
  '  NÃO converta os valores você mesmo: extraia os números COMO ESTÃO impressos no documento e',
  '  declare a escala aqui — a conversão é feita depois, de forma auditável. A escala é crítica:',
  '  errá-la altera o valor em 1000x.',
  '  Atenção: a escala vale para os valores MONETÁRIOS. Linhas que não são dinheiro (percentuais,',
  '  margens em %, lucro POR AÇÃO, quantidades, índices, prazos em dias) não estão nessa escala —',
  '  extraia o número como impresso e mantenha o "%"/unidade no valor_texto para ficar evidente.',
  '',
  '== GRUPOS E LINHAS (planilha) ==',
  'A saída é uma lista de GRUPOS, na ordem em que aparecem no documento. Um grupo é uma SEÇÃO do',
  'documento com as COLUNAS de valor que ela tem, e dentro dele uma linha por CONTA. Chaves curtas',
  '(cada caractere é gasto de novo em cada conta): no grupo s=secao, sc=secao_canonica,',
  'op=origem_pagina, cols=colunas, l=linhas; na linha k=chave, vt=valor_texto, vn=valor_num,',
  'cf=confianca. O texto abaixo usa os nomes completos (mais claro de explicar) — sempre',
  'correspondendo à chave curta do schema.',
  'Extraia TODAS as linhas financeiras do documento (rótulo + valor), preservando a estrutura',
  'original como a "secao" do grupo — ex.: "Ativo Circulante", "Ativo Não Circulante",',
  '"Passivo Circulante", "Passivo Não Circulante", "Patrimônio Líquido", "Receita Operacional",',
  '"Custos", "Despesas Operacionais", "Atividades Operacionais", "Atividades de Investimento",',
  '"Atividades de Financiamento" — use os agrupadores que o PRÓPRIO documento usa; null quando as',
  'linhas não pertencerem a nenhuma seção clara (ex.: um total geral solto).',
  '',
  '"secao" É O AGRUPADOR IMEDIATO, NÃO O TÍTULO DA PÁGINA — e esta é a regra mais importante deste',
  'bloco, porque é a que decide se as contas do documento podem ser CONFERIDAS.',
  'Quando o documento tem TRÊS alturas — a seção, um subgrupo dentro dela, e as contas do subgrupo —',
  'cada linha tem de apontar para o agrupador IMEDIATAMENTE acima dela, e não para o de cima de tudo:',
  '',
  '    ATIVO CIRCULANTE ............ 44.022     ← linha; "secao" = null ou a seção maior',
  '      Disponível ................    825     ← linha; "secao" = "Ativo Circulante"',
  '        Caixa ...................    800     ← linha; "secao" = "Disponível"   (NÃO "Ativo Circulante")',
  '        Bancos ..................     25     ← linha; "secao" = "Disponível"   (NÃO "Ativo Circulante")',
  '      Contas a receber .......... 12.795     ← linha; "secao" = "Ativo Circulante"',
  '      Estoques .................. 15.605     ← linha; "secao" = "Ativo Circulante"',
  '',
  'POR QUE ISSO IMPORTA, em uma conta: quem lê esta saída soma os filhos de cada agrupador e compara',
  'com o valor dele — é assim que o documento confere a si mesmo, sem ninguém digitar nada. Se',
  '"Caixa" e "Bancos" apontarem para "Ativo Circulante" em vez de "Disponível", eles entram na soma',
  'do circulante JUNTO com o "Disponível" que já os contém: 44.022 vira 44.847, e o documento passa',
  'a acusar um erro que não existe. Numa hierarquia inteiramente achatada a soma dá exatamente o',
  'DOBRO do agrupador. Aconteceu com dado real, e produziu 12 pendências falsas numa rodada só —',
  'todas apontando para contas corretas.',
  'A profundidade não tem limite: se o subgrupo tiver subgrupo, a regra é a mesma em cada altura.',
  'E ela NÃO muda nada do que já vale: cada altura continua saindo como LINHA com o seu valor',
  '(ver "O TOTAL IMPRESSO É LINHA" abaixo), e "secao_canonica" continua sendo do GRUPO.',
  'Na dúvida sobre quem é o pai, use a INDENTAÇÃO e a ordem de leitura do documento — o agrupador',
  'imediato é o rótulo mais próximo ACIMA com recuo MENOR. Quando não há recuo e não dá para saber,',
  'aponte para o agrupador que você tem certeza: errar para CIMA (apontar para a seção maior) é o',
  'estado de hoje e é preferível a inventar um pai que o documento não tem.',
  'FRONTEIRA ENTRE DUAS SEÇÕES IRMÃS (ex.: "Reservas" terminando e "Outras Contas do Patrimônio',
  'Líquido" começando logo abaixo): é o ponto de MAIOR risco de anexar uma linha ao grupo errado,',
  'porque as duas letras de rótulo ficam próximas e o recuo pode ser igual. Uma linha de',
  'AJUSTE/DEDUÇÃO perto dessa fronteira (ex.: "Distribuição de Lucros" logo após o fim de um',
  'subgrupo) pertence ao grupo que a ANTECEDE no documento, salvo indentação clara em contrário —',
  'e, na dúvida, teste as duas hipóteses: o TOTAL IMPRESSO do grupo bate com a soma incluindo essa',
  'linha, ou sem ela? Use o que fecha. Aconteceu com dado real: uma linha de dedução anexada ao',
  'subgrupo vizinho deslocou R$300.000 entre duas contas que, cada uma sozinha, fecham exatamente.',
  'TABELA DENSA EM IMAGEM ESCANEADA (sem camada de texto selecionável): o risco maior não é o',
  'número em si, é o ALINHAMENTO linha↔valor — confirme visualmente que cada valor está na MESMA',
  'LINHA HORIZONTAL do rótulo antes de emitir. Um total impresso (ex.: "PASSIVO") repetindo o',
  'MESMO valor de uma linha vizinha (ex.: "PASSIVO CIRCULANTE") que deveria ser menor é o sinal',
  'mais forte de desalinhamento — releia a região com atenção redobrada; se a incerteza persistir',
  'mesmo assim, é preferível emitir a linha com confiança ("cf") BAIXA a aceitar um valor que você',
  'não tem certeza de ter lido na linha certa.',
  'REGRA DAS COLUNAS (é o coração do formato): "cols" descreve, UMA VEZ por grupo, TODAS as colunas',
  'de valor daquela seção — não só período e empresa. Cada coluna tem entidade_coluna (nome da',
  'EMPRESA no cabeçalho, quando há várias empresas lado a lado) e periodo_coluna (o RÓTULO da',
  'coluna); use null no que não se aplica.',
  'ATENÇÃO — COLUNA DE VALOR QUE NÃO É PERÍODO NEM EMPRESA. Muito documento contábil tem colunas de',
  'valor de outra natureza, e elas TAMBÉM vão em "cols", com o rótulo em periodo_coluna:',
  '- LIVRO RAZÃO e RAZÃO ANALÍTICA: "Débito", "Crédito", "Saldo" (três colunas por lançamento).',
  '- BALANCETE: "Saldo anterior", "Débito", "Crédito", "Saldo atual".',
  '- AGING de recebíveis/pagáveis: "A vencer", "1 a 30", "31 a 60", "61 a 90", "Acima de 90", "Total".',
  '- POSIÇÃO DE ESTOQUES: "Quantidade", "Custo unitário", "Valor total".',
  '- MAPA DE DÍVIDA: "Saldo devedor", "Curto prazo", "Longo prazo", "Juros do período" — e TAMBÉM as',
  '  colunas de TEXTO de cada operação, quando impressas: "Modalidade", "Taxa", "Indexador",',
  '  "Vencimento", "Garantia". Elas vão em "cols" como as outras; o texto da célula vai em valor_texto',
  '  ("CDI + 6,80% a.a.", "15/03/2026", "Aval dos sócios") e valor_num fica null. Sem elas o mapa',
  '  chega só com saldo e juros, e a apresentação de crédito não sabe quando nem com que garantia vence.',
  'Declará-las é obrigatório: uma linha com TRÊS valores num grupo que declarou ZERO colunas é',
  'DESCARTADA inteira, porque não se sabe a que coluna cada número pertence — foi o que aconteceu com',
  'um livro razão real, e 98 de 99 lançamentos foram perdidos. O número de valores de cada linha tem',
  'de bater EXATAMENTE com o número de colunas declaradas.',
  'Só devolva "cols" como lista VAZIA quando o documento tem MESMO uma única coluna de valor. Cada',
  'linha traz então "valor_texto" e "valor_num" como',
  'LISTAS com exatamente UM valor POR COLUNA de "cols", NA MESMA ORDEM (e exatamente um valor',
  'quando "cols" é vazia). Célula em branco, com traço ("-") ou ilegível vira null NAQUELA POSIÇÃO —',
  'nunca desloque os valores para a esquerda: a posição é o que diz a que coluna o número pertence,',
  'e deslocar troca o valor de 2025 pelo de 2024. Se você não consegue ler NENHUMA coluna daquela',
  'conta, omita a conta inteira.',
  'Assim o rótulo da conta é escrito UMA vez para todas as colunas dela, em vez de repetido em cada',
  'combinação — é o que permite um balanço comparativo caber na resposta sem truncar.',
  'valor_texto = o valor COMO APARECE no documento (com os separadores e sinais originais).',
  'valor_num = o mesmo valor como número puro, ou null quando não houver número. Regras de',
  'conversão (documentos brasileiros — siga à risca, é fonte comum de erro):',
  '- NOTAÇÃO DECIMAL BR: o ponto é separador de MILHAR e a vírgula é o separador DECIMAL.',
  '  "1.234,56" → 1234.56 ; "12.080.078,23" → 12080078.23 ; "1.000" → 1000 (mil, não 1,0).',
  '- SINAL NEGATIVO: valores entre PARÊNTESES são NEGATIVOS — "(6.000,00)" → -6000.00. Idem sinal',
  '  de menos antes ou DEPOIS do número ("6.000-" → -6000). Em demonstrações, deduções da receita,',
  '  custos, despesas e saídas de caixa costumam vir entre parênteses: preserve o sinal negativo.',
  '- BALANCETE COM COLUNAS DEVEDOR/CREDOR (ou sufixo "D"/"C"): use o sinal conforme a natureza do',
  '  saldo — saldo devedor (D) positivo em contas de ativo/despesa; saldo credor (C) positivo em',
  '  contas de passivo/PL/receita. Não misture: mantenha a mesma convenção em todo o documento.',
  '- Não aplique a escala de "unidade" aqui: o número vai como impresso (ver MOEDA E ESCALA).',
  'Informe a página de origem.',
  'NÃO invente linhas nem valores. Se algo não estiver legível, omita — é melhor extrair de',
  'menos com confiança do que inventar.',
  '',
  'DOCUMENTO COM VÁRIAS ENTIDADES/COLUNAS LADO A LADO (ex.: um balanço combinado com colunas',
  '"Empresa A | Empresa B | Total"): isto é comum e NÃO deve ser resumido num valor só por conta —',
  'declare UMA COLUNA em "cols" para cada uma, com "entidade_coluna" = o nome EXATO do cabeçalho',
  '("Empresa A", "Empresa B", "Total", etc.), e cada conta traz um valor por coluna. Nunca some,',
  'escolha ou estime um valor único representando várias colunas. Quando o documento é de uma',
  'entidade só (o caso comum), "entidade_coluna" é null.',
  '',
  'DOCUMENTO COMPARATIVO — VÁRIAS COLUNAS DE PERÍODO LADO A LADO (ex.: um balanço ou DRE com',
  'colunas "2023 | 2024", ou "31/12/2023 | 31/12/2024", ou "Exercício atual | Exercício anterior"):',
  'isto é o padrão em demonstrações contábeis e NÃO deve ser resumido num valor só por conta —',
  'declare UMA COLUNA em "cols" para cada período, com "periodo_coluna" = o rótulo EXATO da coluna',
  '("2023", "2024", "31/12/2024", etc.). Isto é ortogonal a "entidade_coluna": um documento pode ter',
  'as duas dimensões (várias empresas E vários anos), e então "cols" tem uma entrada por CRUZAMENTO,',
  'com entidade_coluna E periodo_coluna preenchidos — na ordem em que as colunas aparecem impressas.',
  'Nunca some nem escolha um valor único cobrindo vários períodos.',
  '',
  'DMPL — DEMONSTRAÇÃO DAS MUTAÇÕES DO PATRIMÔNIO LÍQUIDO (formato de MATRIZ, trate assim SEMPRE,',
  'inclusive quando ela é só uma parte de um arquivo com várias demonstrações): as linhas são',
  'MOVIMENTOS do exercício ("SALDOS EM 31 DE DEZEMBRO DE 2024", "Prejuízo líquido do exercício",',
  '"Aumento de capital", "Dividendos distribuídos", "SALDOS EM 31 DE DEZEMBRO DE 2025") e as',
  'COLUNAS são os componentes do PL ("Capital social", "Capital a integralizar", "Reserva legal",',
  '"Ajuste de avaliação patrimonial", "Prejuízos acumulados", "Total"). Aqui os COMPONENTES do PL',
  'NÃO vão em "cols": um GRUPO por MOVIMENTO, com "secao" = o rótulo do movimento (a linha da',
  'tabela), "cols" VAZIA, e uma linha por componente, com "chave" = o rótulo do COMPONENTE (o',
  'cabeçalho da coluna) — é o componente que é a CONTA. Não use entidade_coluna para os componentes',
  'do PL: ela é só para colunas de EMPRESAS diferentes. Células vazias ou com traço ("-") não geram',
  'linha nenhuma. Não some nem recalcule a coluna "Total": se o documento a traz, extraia como veio;',
  'se não traz, não invente.',
  '',
  'secao_canonica: além da "secao" livre acima, classifique CADA GRUPO em UMA seção canônica',
  'padronizada (para a planilha final organizar as contas na estrutura de mercado). Use o',
  'julgamento contábil (o significado da conta, não só o nome literal — cada empresa nomeia',
  'diferente). Valores possíveis e seu significado:',
  '- Balanço/Balancete: "ativo_circulante", "ativo_nao_circulante", "passivo_circulante",',
  '  "passivo_nao_circulante", "patrimonio_liquido" (ex.: um mútuo A RECEBER é ativo; um mútuo',
  '  A PAGAR/tomado é passivo — decida pelo sentido).',
  '- DRE: "receita_bruta" (receita e deduções), "custos" (CPV/CMV/custo de serviço),',
  '  "despesas_operacionais" (vendas/administrativas/gerais), "resultado_financeiro"',
  '  (receitas/despesas financeiras, juros), "impostos_lucro" (IRPJ/CSLL).',
  '- Fluxo de Caixa: "atividades_operacionais", "atividades_investimento", "atividades_financiamento".',
  '- DMPL: "dmpl" para TODA linha da Demonstração das Mutações do Patrimônio Líquido (inclusive os',
  '  saldos de abertura/fechamento). Nunca marque uma linha de DMPL como "patrimonio_liquido": o',
  '  saldo de fechamento da DMPL REPETE o total do PL do balanço, e classificá-lo como conta do PL',
  '  faz o patrimônio ser contado duas vezes.',
  '- DVA: "dva" para toda linha da Demonstração do Valor Adicionado (tanto a geração — receitas,',
  '  insumos, depreciação, valor adicionado recebido em transferência — quanto a distribuição —',
  '  pessoal, impostos, remuneração de capitais de terceiros e próprios).',
  'Use "NAO_CLASSIFICAVEL" quando o grupo for de TOTAIS/subtotais gerais, ou quando você não tiver',
  'segurança de qual seção é — NÃO force um palpite ruim (as linhas vão para revisão manual, o que',
  'é preferível a classificar errado). Isto é uma SUGESTÃO revisável por humano, nunca um fato.',
  'COMO A SEÇÃO CANÔNICA CONVIVE COM OS TOTAIS, e isto é obrigatório: a seção canônica é do GRUPO,',
  'então uma linha de TOTAL/subtotal impressa dentro de uma seção NÃO pode entrar no grupo daquela',
  'seção — abra para ela um grupo PRÓPRIO, no lugar em que ela aparece na leitura, com',
  '"secao_canonica" = "NAO_CLASSIFICAVEL" (a "secao" livre pode continuar sendo a do documento).',
  'Totais consecutivos podem dividir o mesmo grupo. O motivo é aritmético: um subtotal misturado às',
  'contas que ele soma faz a seção ser contada duas vezes na planilha.',
  '',
  'O TOTAL IMPRESSO É LINHA, E NÃO SÓ NOME DE SEÇÃO — isto é obrigatório, e é o erro mais comum',
  'nesta tarefa. Quando o documento imprime um valor NA MESMA LINHA do nome do agrupamento',
  '("ATIVO CIRCULANTE ......... 3.961", "PASSIVO E PATRIMÔNIO LÍQUIDO 11.400", "RECEITA OPERACIONAL',
  'BRUTA 82.400"), esse número é DADO do documento e tem de sair como LINHA — em grupo próprio de',
  '"secao_canonica" = "NAO_CLASSIFICAVEL", com "chave" = o rótulo EXATO como impresso. Usar aquele',
  'rótulo como a "secao" dos itens que vêm abaixo é certo e continua valendo; o que NÃO se pode é',
  'usá-lo SÓ como "secao" e deixar o valor de fora — "secao" é o nome do agrupamento, não guarda',
  'número nenhum, e o valor simplesmente desaparece. Já aconteceu com dado real: um balanço saiu com',
  'todas as contas e NENHUM dos totais de topo, e o total do grupo teve de ser recalculado por soma —',
  'que é exatamente o que a conferência existe para NÃO precisar fazer.',
  'Vale para as três alturas, e as três têm de vir: o TOTAL GERAL ("TOTAL DO ATIVO", "ATIVO", "TOTAL',
  'DO PASSIVO E DO PATRIMÔNIO LÍQUIDO"), o total de SEÇÃO ("Ativo Circulante", "Passivo Não',
  'Circulante", "Patrimônio Líquido", "Despesas Operacionais") e o de SUBGRUPO ("Disponível",',
  '"Contas a Receber", "Estoques"). Na DRE isso inclui as linhas de resultado impressas ("Receita',
  'Operacional Bruta", "Receita Líquida", "Lucro Bruto", "Lucro Líquido do Exercício"); no Fluxo de',
  'Caixa, os "Caixa líquido gerado/aplicado nas atividades ..." e a variação do caixa; na DVA, o',
  '"Valor adicionado total a distribuir".',
  'Um total NÃO é dupla contagem: quem lê a saída sabe distinguir total de conta pelo rótulo e pelo',
  'grupo NAO_CLASSIFICAVEL, e usa o total impresso para CONFERIR a soma das contas. Extrair de menos',
  'aqui é que tira a conferência do sistema. A única coisa que continua proibida é INVENTAR: se o',
  'documento não imprime o total, não calcule — deixe fora.',
].join(' ');

/**
 * NÚMERO COLADO NO RÓTULO. Balanço 2025 real (Krauspenhar): o total do passivo
 * veio com a chave "2 113.860.002,40PASSIVO" e a reconciliação acusou
 * "Passivo+PL não localizado" — o valor da linha (113.860.002,40) vazou para o
 * rótulo. CONSERVADOR: só se limpa quando o número colado é IGUAL a um dos
 * valores da PRÓPRIA linha (prova de que é o valor vazado); qualquer outro
 * número colado é declarado em `rotulosSuspeitos` com a chave crua e nada é
 * apagado — "Empréstimo 2.500,00parcelas" pode ser texto legítimo. "Colado" =
 * encostado em letra ou parêntese, sem espaço (frase com o número no meio, com
 * espaços — "PREJUÍZO DE 10.058,20" — não é mexida). O prefixo de código de conta ("2 ") NÃO é
 * mexido aqui: a chave fica "2 PASSIVO" e o casamento da reconciliação é por
 * palavra (0042: regexp_replace não-alfanumérico por espaço), mas isso NÃO foi
 * medido contra o banco.
 *
 * Devolve { chave, suspeitos }: a chave (limpa só quando provado) e as mensagens de
 * rótulo suspeito (chave crua). AUTO-CONTIDA, embutida por toString() ao lado de
 * `achatarGrupos` (FONTE_ACHATAR_GRUPOS) — extraída dela pelo Sonar S3776.
 */
export function limparRotuloColado(chaveCrua, vn, vt, secao) {
  const suspeitos = [];
  const onde = secao ? ` (${secao})` : '';
  let chave = chaveCrua;
  // PADRÃO 2 (balancete real, 8 linhas de 72): a chave é SÓ o número
  // ("21.493.237,90"), igual ao Saldo anterior da linha — o nome da conta se
  // perdeu. Não há texto para recuperar: a conta fica e a chave crua é declarada.
  if (/^\s*-?\d{1,3}(?:\.\d{3})*,\d{2}\s*$/.test(chave)) {
    suspeitos.push(`"${chaveCrua}"${onde}: o rótulo é SÓ um número — o nome da conta se perdeu e a conta foi mantida sem nome`);
    return { chave, suspeitos };
  }
  const padrao = /(?:(?<=^|\s)-)?\d{1,3}(?:\.\d{3})*,\d{2}/g;
  const vizinho = /[A-Za-z\u00C0-\u00FF()]/;
  let achado = padrao.exec(chave);
  while (achado !== null) {
    const ini = achado.index;
    const fim = ini + achado[0].length;
    const colado = vizinho.test(chave[ini - 1] ?? '') || vizinho.test(chave[fim] ?? '');
    if (colado) {
      const numero = Math.abs(Number(achado[0].replace(/\./g, '').replace(',', '.')));
      const digitos = achado[0].replace(/\D/g, '');
      const eValorDaLinha = vn.some((v) => typeof v === 'number' && Math.abs(Math.abs(v) - numero) < 0.005)
        || vt.some((t) => typeof t === 'string' && t.replace(/\D/g, '') === digitos);
      if (eValorDaLinha) {
        chave = `${chave.slice(0, ini)} ${chave.slice(fim)}`.replace(/\s+/g, ' ').trim();
        padrao.lastIndex = 0;
        achado = padrao.exec(chave);
        continue;
      }
      suspeitos.push(`"${chaveCrua}"${onde}: o rótulo traz o número ${achado[0]} colado ao texto, e ele NÃO é igual a nenhum valor da própria linha — o rótulo foi mantido como veio`);
    }
    achado = padrao.exec(chave);
  }
  return { chave, suspeitos };
}

/**
 * Achata os GRUPOS da resposta de volta para uma linha por (conta × coluna) —
 * a forma que `campo_extraido` sempre teve. Nada rio abaixo sabe que a conversa
 * com a OpenAI passou a ser agrupada.
 *
 * AUTO-CONTIDA de propósito: o nó Code do n8n não importa arquivo, então ela é
 * embutida lá por `toString()`. Só referencia `limparRotuloColado`, que VAI JUNTO (FONTE_ACHATAR_GRUPOS) — e nada mais do módulo — se alguém puser
 * uma constante daqui dentro dela, o nó quebra com ReferenceError na primeira
 * execução real e nenhum teste daqui pega isso.
 *
 * A ORDEM é conta-maior, coluna-menor (a conta e depois as colunas dela), que é
 * a ordem de leitura do documento e é o que `ordem` significa para o export —
 * é assim que ele reconhece um subtotal impresso ACIMA dos seus componentes.
 *
 * O DESALINHAMENTO É TRATADO COMO FALHA, NUNCA ADIVINHADO. O modelo tem de
 * devolver um valor por coluna; se devolver menos (ou mais), a associação
 * valor↔coluna deixou de ser conhecida. Preencher o que falta com null ou
 * encostar os valores à esquerda trocaria o número de 2025 pelo de 2024 em
 * silêncio — o pior erro possível aqui. Então a conta é DESCARTADA e o motivo
 * volta nomeado, com rótulo e contagens, para virar pendência.
 */
export function achatarGrupos(grupos) {
  const linhas = [];
  const problemas = [];
  // Rótulos com número monetário COLADO que não deu para provar ser o valor da
  // linha: a linha NÃO é descartada nem reescrita, só declarada (ver abaixo).
  const rotulosSuspeitos = [];
  if (!Array.isArray(grupos)) return { linhas, problemas, rotulosSuspeitos };
  // Índice da LINHA DO DOCUMENTO que originou cada entrada. Uma conta com três
  // colunas vira três entradas com o MESMO `linha_origem`, e é isso que permite
  // contar de volta quantas linhas o modelo devolveu — a unidade em que a guarda
  // de cobertura compara. Sem ele só sobrava "contas distintas", que num livro
  // razão (o mesmo histórico em vários lançamentos) é MENOR que o número de
  // linhas: extração perfeita se reportava em 66% e abria pendência falsa.
  // O campo não chega ao banco: `juntarBlocos` o remove depois de contar.
  let indiceDaLinha = -1;
  for (const g of grupos) {
    if (!g || typeof g !== 'object') continue;
    const cols = Array.isArray(g.cols) && g.cols.length > 0
      ? g.cols.map((c) => ({ ec: c?.ec ?? null, pc: c?.pc ?? null }))
      // Documento de coluna única: o grupo não declara coluna nenhuma e a linha
      // traz um valor só. É o caso comum, e é o que mantém a resposta enxuta.
      : [{ ec: null, pc: null }];
    for (const l of Array.isArray(g.l) ? g.l : []) {
      if (!l || typeof l !== 'object' || typeof l.k !== 'string') continue;
      // Conta a linha ANTES de qualquer descarte: uma linha desalinhada é linha
      // que o modelo leu, e o índice tem de continuar identificando a MESMA
      // linha do documento se um dia o descarte mudar.
      indiceDaLinha += 1;
      const vt = Array.isArray(l.vt) ? l.vt : [l.vt ?? null];
      const vn = Array.isArray(l.vn) ? l.vn : [l.vn ?? null];
      if (vn.length !== cols.length || vt.length !== cols.length) {
        problemas.push(
          `"${l.k}"${g.s ? ` (${g.s})` : ''}: ${cols.length} coluna(s) declarada(s), `
          + `${vn.length} valor(es) numérico(s) e ${vt.length} texto(s)`
          // A causa quase sempre é a mesma, e dizê-la poupa a investigação: o
          // documento TEM colunas de valor que o modelo não declarou. Num livro
          // razão real isso descartou 98 de 99 lançamentos — Débito, Crédito e
          // Saldo vieram na linha, e `cols` veio vazia.
          + (cols.length === 1 && vn.length > 1
            ? ' — provavelmente o documento tem colunas de valor (Débito/Crédito/Saldo, faixas de aging)'
              + ' que não foram declaradas em "cols"'
            : ''));
        continue;
      }
      // NÚMERO COLADO NO RÓTULO — ver `limparRotuloColado` (a regra e o porquê moram lá).
      const rotulo = limparRotuloColado(l.k, vn, vt, g.s);
      const chave = rotulo.chave;
      rotulo.suspeitos.forEach((m) => rotulosSuspeitos.push(m));
      for (let j = 0; j < cols.length; j += 1) {
        const valorTexto = typeof vt[j] === 'string' ? vt[j] : null;
        const valorNum = typeof vn[j] === 'number' ? vn[j] : null;
        // Célula em branco não vira linha — a mesma regra que a DMPL já tinha
        // ("células vazias ou com traço não geram linha nenhuma"), agora válida
        // para qualquer documento, porque no formato de colunas a célula vazia
        // TEM de ocupar posição para não deslocar as outras.
        if (valorTexto === null && valorNum === null) continue;
        linhas.push({
          linha_origem: indiceDaLinha,
          secao: g.s ?? null,
          secao_canonica: g.sc && g.sc !== 'NAO_CLASSIFICAVEL' ? g.sc : null,
          entidade_coluna: cols[j].ec,
          periodo_coluna: cols[j].pc,
          chave,
          valor_texto: valorTexto,
          valor_num: valorNum,
          confianca: typeof l.cf === 'number' ? l.cf : null,
          origem_pagina: Number.isInteger(g.op) ? g.op : null,
        });
      }
    }
  }
  return { linhas, problemas, rotulosSuspeitos };
}

export function extractionSchema() {
  return {
    name: 'diagnostico_e_extracao',
    strict: true,
    schema: {
      type: 'object',
      additionalProperties: false,
      required: ['moeda', 'unidade', 'diagnostico', 'grupos'],
      properties: {
        moeda: { type: ['string', 'null'] },
        unidade: { type: ['string', 'null'] },
        diagnostico: {
          type: 'object',
          additionalProperties: false,
          required: [
            'entidade', 'cnpj', 'tipo_confirma', 'tipo_sugerido', 'periodo_tipo',
            'periodo_referencia', 'legibilidade', 'nota_legibilidade', 'tem_dado_financeiro',
            'resumo', 'justificativa', 'fatos',
          ],
          properties: {
            entidade: { type: ['string', 'null'] },
            // 0172: o CNPJ do EMITENTE. Este é o caminho que roda para TODO
            // documento — a classificação por conteúdo só roda no fallback (19
            // de 38 no book-canastra), então é aqui que a identidade fiscal
            // cobre o lote inteiro. Aceita null e MESMO ASSIM entra em
            // `required`: o schema é `strict`, e é como `entidade` já faz.
            cnpj: { type: ['string', 'null'] },
            tipo_confirma: { type: 'boolean' },
            tipo_sugerido: { type: 'string', enum: codigosConhecidos() },
            periodo_tipo: { type: 'string', enum: PERIODO_TIPO_ENUM },
            periodo_referencia: { type: ['string', 'null'] },
            legibilidade: { type: 'string', enum: ['ok', 'degradado', 'ilegivel'] },
            nota_legibilidade: { type: ['string', 'null'] },
            tem_dado_financeiro: { type: 'boolean' },
            resumo: { type: 'string' },
            justificativa: { type: 'string' },
            // O FATO QUE O DOCUMENTO DIZ EM TEXTO, e não em tabela.
            //
            // Nasceu do ANEXO A.2 da v48: as Notas Explicativas e o Parecer do
            // Auditor não têm tabela nenhuma, extraem ZERO linha corretamente —
            // e carregam o rompimento de covenant e a ressalva, que é o que um
            // comitê de crédito lê primeiro. Eles entravam, eram classificados e
            // ficavam mudos.
            //
            // `tr` é o TRECHO LITERAL e o banco o exige (`fn_registrar_fatos`
            // recusa entrada sem ele): um resumo escrito pelo modelo é
            // afirmação, a frase copiada é evidência — e este alerta é o que vai
            // ao comitê. `le` é a leitura em uma frase, COMPLEMENTO da evidência
            // e nunca substituto.
            //
            // Vazio é a resposta comum e certa: quase todo documento é tabela.
            fatos: {
              type: 'array',
              description: 'fatos materiais declarados EM TEXTO por este documento; [] na maioria (documento de tabela não declara nada)',
              items: {
                type: 'object',
                additionalProperties: false,
                required: ['ft', 'tr', 'le', 'pg'],
                properties: {
                  ft: { type: 'string', enum: FATO_TIPO_ENUM, description: 'tipo do fato' },
                  tr: { type: 'string', description: 'trecho LITERAL do documento, copiado sem reescrever, com no mínimo 20 caracteres; é a evidência e sem ele o fato é descartado' },
                  le: { type: 'string', description: 'leitura: o que o trecho significa para quem decide, em UMA frase' },
                  pg: { type: ['integer', 'null'], description: 'página em que o trecho aparece' },
                },
              },
            },
          },
        },
        // A SAÍDA É AGRUPADA, E O MOTIVO É A CONTA DE LUZ.
        //
        // O formato antigo era uma lista plana: uma entrada por (conta × coluna),
        // cada uma repetindo `s`, `sc`, `ec`, `pc` e `op` — cinco campos de
        // CONTEXTO idênticos em dezenas de entradas consecutivas — e repetindo o
        // rótulo da conta uma vez por coluna. Medido no book de 14 documentos do
        // dono: **~64 tokens por linha**, dos quais só ~30 eram carga útil, e
        // 84% da fatura de US$ 0,90 era saída de extração.
        //
        // Aqui o contexto sobe UMA vez para o grupo, as colunas são declaradas
        // UMA vez em `cols`, e a conta aparece UMA vez com um valor por coluna.
        // Medido nos mesmos 14 documentos: **−63% de saída** (−79% no balanço
        // combinado, que tem 7 colunas de empresa; −39% nos de coluna única).
        //
        // E o formato responde a um defeito antigo, não só ao custo: documentos
        // comparativos truncavam (`finish_reason=length`) antes de terminar de
        // listar as contas — 6 de 16 no "teste v18" (sessão 7 cont.¹¹). A
        // resposta na época foi encurtar os NOMES das chaves; foi meia correção,
        // porque continuava repetindo o contexto. O maior documento deste book
        // usava 83% do teto de saída; agora usa ~30%.
        //
        // O que NÃO muda: nada rio abaixo. `parseExtractionResponse` achata os
        // grupos de volta para uma linha por (conta × coluna) com os nomes
        // completos — `campo_extraido` continua idêntico, coluna por coluna.
        grupos: {
          type: 'array',
          description: 'seções do documento, na ordem de leitura; cada uma com suas colunas e contas',
          items: {
            type: 'object',
            additionalProperties: false,
            required: ['s', 'sc', 'op', 'cols', 'l'],
            properties: {
              s: { type: ['string', 'null'], description: 'secao: o agrupador IMEDIATAMENTE acima destas contas (rótulo do próprio documento). Numa hierarquia de três alturas, as contas de "Disponível" têm secao = "Disponível", e não "Ativo Circulante" — apontar para o topo faz o subgrupo ser somado duas vezes' },
              sc: { type: 'string', enum: SECAO_CANONICA_ENUM, description: 'secao_canonica: seção padronizada pelo significado contábil; NAO_CLASSIFICAVEL num grupo só de totais/subtotais' },
              op: { type: ['integer', 'null'], description: 'origem_pagina: página onde esta seção aparece' },
              cols: {
                type: 'array',
                description: 'colunas de valor desta seção, na ordem impressa; VAZIA quando há uma só coluna',
                items: {
                  type: 'object',
                  additionalProperties: false,
                  required: ['ec', 'pc'],
                  properties: {
                    ec: { type: ['string', 'null'], description: 'entidade_coluna: empresa do cabeçalho da coluna' },
                    // O nome da chave é histórico (`0017`, quando só havia coluna de
                    // período), mas o SIGNIFICADO é mais largo: é o RÓTULO da coluna,
                    // seja ele um período ("2024"), uma faixa de aging ("31 a 60") ou a
                    // natureza do saldo ("Débito"). Ficou assim em vez de virar campo
                    // novo porque `campo_extraido.periodo_coluna` é texto livre e ninguém
                    // rio abaixo o interpreta como data: a reconciliação casa por ANO
                    // (`fn_anos_texto`), então um rótulo sem ano simplesmente não
                    // participa — que é o certo, já que "Débito" não é um exercício.
                    pc: { type: ['string', 'null'], description: 'periodo_coluna: rótulo da coluna — o período ("2024", "31/12/2025") quando é comparativo, ou a natureza da coluna quando não é ("Débito", "Crédito", "Saldo", "31 a 60 dias", "Quantidade")' },
                  },
                },
              },
              l: {
                type: 'array',
                description: 'contas desta seção',
                items: {
                  type: 'object',
                  additionalProperties: false,
                  required: ['k', 'vt', 'vn', 'cf'],
                  properties: {
                    k: { type: 'string', description: 'chave: rótulo da conta' },
                    vt: {
                      type: 'array',
                      description: 'valor_texto por coluna, como aparece no documento; um item por coluna de cols (um item quando cols é vazia); null na posição da célula em branco',
                      items: { type: ['string', 'null'] },
                    },
                    vn: {
                      type: 'array',
                      description: 'valor_num por coluna, número puro, na MESMA ordem de vt e de cols',
                      items: { type: ['number', 'null'] },
                    },
                    cf: { type: 'number', description: 'confianca: confiança 0-1 na leitura desta conta' },
                  },
                },
              },
            },
          },
        },
      },
    },
  };
}

// Teto de tokens de SAÍDA por chamada (16384) — explícito porque documentos
// combinados grandes (grupo com várias entidades × várias demonstrações no
// mesmo PDF) exigem um array `linhas` extenso; sem isso fica sujeito a um
// default menor de max_tokens dependendo da conta/API, que corta a resposta
// no meio do JSON sem erro nenhum (ver parseExtractionResponse: finish_reason
// 'length' → JSON incompleto → falha silenciosa, achado em produção
// reprocessando "teste v14", sessão 7 cont.⁷).
export const MAX_OUTPUT_TOKENS = 16384;

// TPM (tokens por minuto) e RPM (chamadas por minuto) DA CONTA — os dois limites
// que decidem a cadência, e agora eles vêm do provedor ativo (`lib/provedor.mjs`).
//
// Continuam sendo lidos daqui, e não do gerador, porque TRÊS lugares dependem do
// mesmo número e precisam concordar: o gerador (calcula o batchInterval a partir
// deles), o teste que trava a cadência, e `diagnosticar-ia.mjs` (compara o
// configurado com o que a API informa). Duplicado, o dono ajustaria um e os
// outros dois passariam a mentir.
//
// POR QUE DOIS NÚMEROS AGORA, e não só o TPM. Na OpenAI o gargalo é sempre o
// balde de tokens, porque `max_tokens` é RESERVA — toda extração reserva 16.384
// tokens do minuto, para um PDF de 2 KB ou de 40 páginas. Já a linha Flash-Lite
// do Google entra com um balde de tokens folgado e um limite de CHAMADAS
// apertado (15 por minuto no patamar de entrada): pelo TPM sozinho o intervalo
// daria ~1 segundo, e o lote tomaria 429 na terceira chamada. Quem manda é o
// mais restritivo dos dois, e `RPM_CONTA` null significa "este provedor não
// limita por chamada" (o caso da OpenAI).
export const TPM_CONTA = provedor().tpm;
export const RPM_CONTA = provedor().rpm;

// O PISO HISTÓRICO DE BATCHING — movido para cá em 14/09/2026 pelo MESMO motivo
// que TPM_CONTA/RPM_CONTA moram aqui: o gerador e o teste que trava a cadência
// precisam do MESMO número, e duplicá-lo é o que já fez os "três espelhos do
// portal" ficarem para trás uma vez (ver `espera-do-lote.ts`).
//
// O PISO DE 6s É HISTÓRICO E FICA: veio do "teste v18", em que 3 de 16
// documentos ainda tomaram 429 com 3s. Ele não depende de provedor — é a folga
// mínima que a experiência com o n8n do dono mostrou ser necessária.
//
// O NÚMERO É 6000, NÃO 12000, E A DIFERENÇA IMPORTA. O "v28" (comentário
// grande, mais abaixo neste arquivo, sobre `diagnosticarErroApi`) já confessa
// que subir de 6s para 12s foi um CHUTE sem evidência de que a causa daquela
// falha fosse cadência — e nenhuma medição posterior justificou o 12s. O piso
// que sobreviveu à correção do v30 (a cadência virar aritmética de TPM) é
// este: 6s, medido no v18, por duas razões que CONTINUAM valendo em qualquer
// tier — o campo do n8n é preenchido em segundos por um humano, e abaixo de 6s
// o intervalo vira frágil a qualquer variação de latência da rede.
//
// SUBIR O TPM DA CONTA (14/09/2026: 30.000 → 500.000, a conta real do dono)
// fez a aritmética do TPM cair para ~4,4s — abaixo deste piso, que agora é
// quem decide o intervalo. É exatamente o caso que o comentário de
// `INTERVALO_EXTRACAO_MS` em build-workflow.mjs já previa ("no Tier 2, 450.000
// TPM, o intervalo cai bem abaixo do piso histórico de 6s"): o piso passou a
// SER o intervalo, e não é regressão — é o desenho funcionando.
export const PISO_BATCHING_MS = 6000;

// conteudo: parte multimodal (arquivo/imagem/texto) — reaproveita contentPartFromFile.
export function buildExtractionRequest({
  tipo, nomeOriginal, conteudo, model = DEFAULT_MODEL, prov = provedor(),
  esforco = DEFAULT_ESFORCO,
}) {
  return {
    url: urlDaChamada(prov, model),
    method: 'POST',
    body: montarCorpoIA(prov, {
      modelo: model,
      sistema: SYSTEM_PROMPT,
      maxTokens: MAX_OUTPUT_TOKENS,
      esforco,
      schema: extractionSchema(),
      partes: [
        parteDeTexto(
          prov,
          `Nome do arquivo: ${nomeOriginal || '(sem nome)'}. Dica de tipo (do nome, pode estar `
          + `errada): ${tipo || 'desconhecido'}. Diagnostique e extraia as linhas financeiras.`,
        ),
        ...(Array.isArray(conteudo) ? conteudo : [conteudo]),
      ],
    }),
  };
}

// Normaliza a resposta para { moeda, unidade, campos[], diagnostico, falhaMotivo }.
// campos já vem no formato de fn_registrar_campos_extraidos (inclui secao).
// falhaMotivo é null quando a extração veio ok; motivo textual (para virar
// pendência tipada 'extracao_falhou') quando a chamada errou, veio truncada
// (finish_reason 'length' — teto de tokens de saída estourado) ou o conteúdo
// não é JSON válido. Sem isso, uma falha silenciosa gera 0 campos e ninguém
// nunca fica sabendo (achado em produção, sessão 7 cont.⁷ — "teste v14").
// Normalização de ESCALA na fronteira. O prompt pede "unidade"|"milhar"|"milhao",
// mas o campo é texto livre no schema (fechá-lo em enum exigiria validar contra a
// API real, que não temos aqui) e documentos já processados trazem variedade
// ("R$ mil", "milhares de reais", "em milhões"). Como a `unidade` é herdada por
// TODA linha e a reconciliação Classe A compara a unidade de DOIS documentos
// diferentes (0009: divergência aborta a checagem), texto livre inconsistente
// gera "precondição não satisfeita" falsa — normalizar aqui torna a comparação
// confiável, sem depender do humor do modelo. Desconhecido → null (nunca chuta
// uma escala: errar em 1000x é pior que não saber).
export function normalizarUnidade(bruto) {
  if (bruto == null) return null;
  const t = String(bruto)
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .toLowerCase().trim();
  if (!t) return null;
  if (/\bmilhao|milhoes|\bmm\b|r\$\s*mi\b|\bmi\b/.test(t)) return 'milhao';
  if (/\bmilhar|milhares|\bmil\b|r\$\s*mil|\bm\$\b/.test(t)) return 'milhar';
  if (/\bunidade|\breal\b|reais|inteiro|r\$$|^r\$$/.test(t)) return 'unidade';
  if (t === '1' || t === '1.000' || t === '1000') return t === '1' ? 'unidade' : 'milhar';
  return null;
}

// Moeda para código ISO — mesmo espírito da escala: "R$"/"reais" e "BRL" devem
// virar a MESMA coisa para qualquer comparação/exibição a jusante.
export function normalizarMoeda(bruto) {
  if (bruto == null) return null;
  const t = String(bruto)
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .toLowerCase().trim();
  if (!t) return null;
  if (/\bbrl\b|r\$|real|reais/.test(t)) return 'BRL';
  if (/\busd\b|us\$|dolar|dollar/.test(t)) return 'USD';
  if (/\beur\b|€|euro/.test(t)) return 'EUR';
  return /^[a-z]{3}$/.test(t) ? t.toUpperCase() : null;
}

// A escala do documento ("R$ mil") é herdada por TODA linha — mas demonstrações
// reais MISTURAM naturezas no mesmo arquivo: junto do balanço em milhares vêm
// linhas que NÃO estão nessa escala (percentuais, lucro por ação, quantidades,
// índices). Herdar a escala nessas linhas é uma mis-escala silenciosa: um "LPA
// 1,25" viraria 1.250 quando alguém aplicasse o fator. Aqui a herança é
// BLOQUEADA para as linhas claramente não-monetárias (unidade fica null =
// escala desconhecida, nunca uma escala errada).
//
// Sinais deliberadamente CONSERVADORES (falso positivo aqui esconderia a escala
// de uma conta monetária legítima): "%" no valor ou no rótulo, "por ação"/LPA,
// "percentual", "quantidade", "número de ações". Note que "margem" NÃO entra —
// "margem de contribuição" é conta monetária de verdade.
// A COLUNA TAMBÉM DECIDE, e ignorar isso custou o achado da rodada v47.
//
// A regra acima olha o RÓTULO DA LINHA — e num documento tabular o rótulo é o
// mesmo nas quatro colunas. No `24_Posicao_de_Estoques`, "Bobina kraft 180 g/m²"
// aparece em `Quantidade`, `Custo unitário (R$)` e `Valor (R$ mil)`: a linha é
// idêntica, e só a COLUNA diz o que aquele número é. Resultado medido: 1.240
// unidades de bobina e 96 pessoas de efetivo foram gravadas com a escala e a
// moeda do documento, prontas para virar 1,24 bilhão e 96 milhões de pessoas.
//
// Terceiro parâmetro, e não uma função nova, porque a pergunta é a mesma —
// "este número é dinheiro na escala do documento?" — e ter duas respostas para
// ela em lugares diferentes é como este repositório descreve seus piores
// defeitos.
//
// AUTO-CONTIDA, como `diagnosticarErroApi` e pelo mesmo motivo: o gerador embute
// o `toString()` desta função no nó Code do n8n, e nó Code não enxerga constante
// de módulo. Referenciar as regex de fora daria `ReferenceError` na primeira
// linha de todo documento — em produção, não no teste.
export function ehLinhaNaoMonetaria(chave, valorTexto, coluna) {
  const norm = (s) => String(s ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim();
  const reLinha = /%|\bpercentual|\bpor acao\b|\blpa\b|\bquantidade\b|numero de acoes/;
  // UMA alternância ancorada, grupos não-capturantes e `String.raw`: as três
  // coisas que o Sonar pediu, e as três deixam o padrão mais legível do que
  // estava. O rótulo TEM de casar inteiro (`^…$`) — "valor" não pode virar
  // dimensão porque contém "valor unitario" —, exceto na segunda alternância,
  // que casa por palavra dentro do rótulo.
  const reColuna = new RegExp(String.raw`^(?:qtde?|quantidade|unidade|efetivo(?: \(pessoas\))?|pessoas`
    + `|headcount|dias|prazo|exercicio|ano|natureza|tipo|classe|categoria|situacao|status`
    + `|moeda|indexador|contraparte|banco|contrato|historico|documento|empresa.*)$`
    + String.raw`|(?:^|\s)(?:%|percentual|participacao|(?:custo|preco|valor) unitario|taxa)(?:$|\s)`);
  if (reLinha.test(norm(chave))) return true;
  if (String(valorTexto ?? '').includes('%')) return true;
  return coluna != null && coluna !== '' && reColuna.test(norm(coluna));
}

// A ESCALA QUE A COLUNA DECLARA MANDA NA QUE O DOCUMENTO DECLARA.
//
// Também da v47: o `24_Posicao_de_Estoques` e o `28_Folha_de_Pagamento` têm
// "(R$ mil)" escrito em CADA cabeçalho de coluna, e mesmo assim a escala do
// documento voltou `milhao` — em todas as 84 linhas. Os VALORES estavam certos
// (TOTAL DOS ESTOQUES = 15.605, igual ao gabarito); o multiplicador é que estava
// mil vezes errado.
//
// A coluna é mais específica que o cabeçalho do documento e é onde a escala
// costuma estar escrita por extenso, então quando ela declara uma escala de
// forma inequívoca, é ela que vale. Só nesse caso: sem declaração explícita
// devolve null e a escala do documento continua valendo, porque adivinhar aqui
// seria trocar um erro de 1.000× por outro.
export function escalaDeclaradaNaColuna(coluna) {
  const t = String(coluna ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  if (/\bmilhao|\bmilhoes|\bmi\b|r\$\s*mm\b/.test(t)) return 'milhao';
  if (/\bmil\b|\bmilhar|\bmilhares/.test(t)) return 'milhar';
  return null;
}

// ---------------------------------------------------------------------------
// DIAGNÓSTICO DE ERRO DA API — separar causas que pedem ações OPOSTAS
//
// O "teste v30" custou uma rodada inteira por causa disto: 14 de 14 documentos
// falharam e a única coisa que a pendência dizia era
//
//     "Erro da API OpenAI: Try spacing your requests out using the batching
//      settings under 'Options'"
//
// Essa frase é do **N8N**, não da OpenAI: o nó HTTP Request a acrescenta a
// QUALQUER resposta 429. E 429 na OpenAI cobre causas que pedem ações opostas:
//
//   • `insufficient_quota` / limite de faturamento → acabou o CRÉDITO.
//     Espaçar as chamadas NÃO resolve; só recarregar/subir o limite resolve.
//   • `rate_limit_exceeded` (RPM/TPM) → cadência alta. Espaçar resolve.
//   • limite DIÁRIO (TPD) → cota do dia esgotada. Espaçar não resolve hoje;
//     resolve amanhã (ou subindo o tier).
//
// Lendo só a frase do n8n, as três são indistinguíveis — e eu mesmo tratei o
// v28 como cadência e subi o intervalo de 6s para 12s sem ter evidência de que
// a causa fosse cadência. Este diagnóstico existe para que ninguém (dono ou
// sessão futura) volte a chutar isso.
//
// A busca é DEFENSIVA por desenho: dependendo da versão do n8n e do modo de
// erro, o corpo real da OpenAI aparece em lugares diferentes do objeto de erro
// (`cause`, `context.data`, `response.data`, `error.error`…), e não há como
// fixar uma forma só sem o n8n vivo do dono para conferir. Procurar em todos os
// caminhos plausíveis é mais robusto que acertar um e falhar calado nos outros.
/**
 * Classifica um erro de chamada à OpenAI numa CAUSA acionável.
 *
 * Devolve `{ causa, status, tipo, codigo, mensagem, motivo }` — `motivo` é o
 * texto que vai para a pendência: diz a causa, o que fazer, e (quando é o caso)
 * diz explicitamente o que NÃO resolve. `causa` é o código estável para teste.
 *
 * AUTO-CONTIDA de propósito: os helpers ficam DENTRO da função porque o gerador
 * do workflow embute o `toString()` dela no nó Code (nó Code do n8n não importa
 * arquivo). Com dependência de escopo externo, o mirror voltaria a ser cópia à
 * mão — e cópia à mão neste repositório já divergiu duas vezes (o prompt de
 * extração e a lista de apelidos da taxonomia). Aqui a fonte é UMA, e
 * `N8N/test/workflow-sim.test.mjs` confere que o nó carrega exatamente este
 * código. O custo (recriar helpers por chamada) é irrelevante: roda uma vez por
 * documento que FALHOU.
 */
export function diagnosticarErroApi(erro) {
  // Dependendo da versão do n8n e do modo de erro, o corpo real da OpenAI
  // aparece em lugares diferentes (`cause`, `context.data`, `response.data`,
  // `error.error`…). Sem o n8n vivo do dono não há como fixar uma forma só;
  // procurar em todos os caminhos plausíveis é mais robusto que acertar um e
  // falhar calado nos outros.
  const CAMINHOS = [
    // A FORMA REAL DO N8N, confirmada no fonte dele (não suposta):
    // `packages/@N8N/backend-network/src/http/legacy-request.ts` anexa ao erro
    // `error: responseData` — o JSON da OpenAI JÁ PARSEADO, que por sua vez é
    // `{ error: { type, code, message } }`. O item que chega ao nó Code é
    // `{ json: { error: <reason inteiro> } }`, então o corpo da OpenAI fica em
    // `error.error.error` a partir da raiz do item. Este caminho vem PRIMEIRO
    // porque é o que acontece em produção.
    (e) => e && e.error && e.error.error,
    (e) => e && e.error,                                  // corpo da OpenAI direto (ou responseData já desembrulhado)
    (e) => e && e.cause && e.cause.error,                 // NodeApiError embrulhando a resposta
    (e) => e && e.cause && e.cause.response && e.cause.response.data && e.cause.response.data.error,
    (e) => e && e.cause && e.cause.data && e.cause.data.error,
    (e) => e && e.context && e.context.data && e.context.data.error,
    (e) => e && e.response && e.response.data && e.response.data.error,
    (e) => e && e.data && e.data.error,
    (e) => e && e.cause,                                  // o cause pode já ser o corpo
    // O PRÓPRIO objeto é o corpo — é o que chega quando o nó roda com
    // `neverError` (a resposta 429 vem como item normal, e o item É
    // `{error:{type,code,message}}`). Aceito só com sinal de que é corpo da
    // OpenAI: `type`, ou um `code` que não seja de TRANSPORTE. Sem essa guarda,
    // um AxiosError entraria aqui e `ERR_BAD_REQUEST` seria reportado como se
    // fosse o código da OpenAI — pista falsa, pior que pista nenhuma.
    // `status` textual entra aqui pelo Google: o corpo de erro dele é
    // `{error:{code:429, message, status:'RESOURCE_EXHAUSTED'}}` — sem `type`, e
    // com um `code` que é NÚMERO. Sem reconhecer o `status`, esse corpo não era
    // aceito como corpo e o diagnóstico caía em "desconhecida" com a frase do
    // n8n, que é exatamente o cego que esta função existe para não ser.
    (e) => (e && (e.type || e.status || (e.code && !/^ERR_/i.test(String(e.code))))) ? e : null,
  ];
  const corpoDeErroOpenAI = (e) => {
    if (!e || typeof e !== 'object') return null;
    for (const caminho of CAMINHOS) {
      let c;
      try { c = caminho(e); } catch { continue; }
      if (c && typeof c === 'object' && (c.type || c.code || c.status || c.message)) return c;
    }
    return null;
  };
  // A FRASE do n8n como sinal de status. O n8n só acrescenta "Try spacing your
  // requests out using the batching settings under 'Options'" em resposta 429 —
  // então, quando ele entrega só a frase (sem httpCode em campo nenhum, que é
  // exatamente o caso que chegou na pendência do v30), a frase é a única
  // evidência de que houve 429. Reconhecê-la separa "sei que é limite, não sei
  // qual" de "não sei nada" — e a primeira já dá um passo concreto ao dono.
  const RE_DICA_429_N8N = /spacing your requests out|too many requests from you/i;
  // Recebe o CORPO já extraído como segundo argumento, e não é detalhe: o
  // Google põe o HTTP em `code` DENTRO do corpo, e o corpo pode estar embrulhado
  // em uma ou duas camadas pelo n8n. Procurar `code` por caminho fixo seria
  // acertar um embrulho e falhar calado nos outros; o corpo já foi achado pelos
  // CAMINHOS acima, então usá-lo cobre todos de uma vez.
  const statusHttpDoErro = (e, corpoDoErro) => {
    const candidatos = [
      e && e.httpCode, e && e.status, e && e.statusCode,
      // Só NÚMERO entra: o `code` de transporte do axios é string
      // ('ERR_BAD_REQUEST'), e aceitá-lo faria o diagnóstico reportar um status
      // que não existiu — a pista falsa que o v30 ensinou a não dar.
      (e && typeof e.code === 'number') ? e.code : null,
      (corpoDoErro && typeof corpoDoErro.code === 'number') ? corpoDoErro.code : null,
      e && e.cause && e.cause.status, e && e.cause && e.cause.statusCode,
      e && e.response && e.response.status, e && e.context && e.context.httpCode,
    ];
    for (const v of candidatos) {
      const n = Number(v);
      if (Number.isFinite(n) && n >= 100 && n < 600) return n;
    }
    const texto = typeof e === 'string' ? e : ((e && e.message) || '');
    return RE_DICA_429_N8N.test(String(texto)) ? 429 : null;
  };
  // Serializar tudo é o que permite reconhecer "insufficient_quota" mesmo quando
  // ele não vem num campo estruturado (o n8n às vezes entrega só string).
  const textoDoErro = (e) => {
    if (typeof e === 'string') return e;
    try { return JSON.stringify(e); } catch { return String(e === undefined ? '' : e); }
  };

  const corpo = corpoDeErroOpenAI(erro);
  const status = statusHttpDoErro(erro, corpo);
  const tipo = corpo?.type ?? null;
  // `code` de TRANSPORTE (axios: ERR_BAD_REQUEST, ECONNRESET...) não é o código
  // da OpenAI — a doc dela manda inspecionar `error.code`, e confundir os dois
  // mandaria a sessão seguinte investigar o código errado.
  //
  // MEDIDO, para não superestimar a cobertura: esta guarda e a do último caminho
  // de CAMINHOS são REDUNDANTES para o payload do v30 — removendo UMA só, o teste
  // "o AxiosError REAL do v30 não é lido como código da OpenAI" continua passando;
  // ele só reprova com as DUAS removidas. É proteção em profundidade de propósito
  // (dois pontos de entrada possíveis para um code de transporte), mas quem mexer
  // em uma delas não vai ser avisado pelo teste. Mexa nas duas juntas.
  const codigoBruto = corpo?.code ?? null;
  const codigo = (codigoBruto && /^ERR_/i.test(String(codigoBruto))) ? null : codigoBruto;
  const mensagemOpenAI = corpo?.message ?? null;
  const mensagemBruta = typeof erro === 'string' ? erro : (erro?.message ?? null);
  // O texto completo inclui a mensagem do n8n E o corpo da OpenAI, quando os
  // dois vieram — é nele que a busca por assinatura procura.
  const alvo = `${tipo ?? ''} ${codigo ?? ''} ${mensagemOpenAI ?? ''} ${textoDoErro(erro)}`.toLowerCase();

  const tem = (...frases) => frases.some((f) => alvo.includes(f));

  let causa = 'desconhecida';
  let motivo;

  // TETO DE GASTO vem ANTES de "sem crédito" de propósito: são coisas
  // diferentes com ações diferentes, e esta é a que engana. Um teto de gasto de
  // PROJETO (ou o orçamento mensal da organização) devolve 429 com a conta
  // perfeitamente saudável — há saldo, o tier está normal, e as páginas de
  // Billing e de Limits não mostram nada de errado. Foi exatamente o relato do
  // dono depois do v30: "o limite da OpenAI está OK". Estes códigos estão na doc
  // oficial de erros da OpenAI e nenhum deles é falta de dinheiro.
  if (tem('spend_limit_exceeded', 'spend limit', 'usage_limit_exceeded',
    'usage limit', 'budget')) {
    causa = 'limite_de_gasto';
    motivo = 'TETO DE GASTO ATINGIDO no provedor de IA — e isto NÃO é falta de crédito: há saldo, o '
      + 'tier está normal, e é por isso que as páginas de cobrança e de limites parecem em ordem. O '
      + 'que estourou é um LIMITE CONFIGURADO: teto do PROJETO a que a chave pertence, ou orçamento '
      + 'mensal da organização. Onde olhar — na OpenAI: Settings → Limits (orçamento da org) E '
      + 'Settings → Projects → o projeto da chave → Limits; no Google: o orçamento do projeto no '
      + 'Cloud Billing. Espaçar as chamadas não resolve; subir o teto resolve na hora.';
  } else if (tem('insufficient_quota', 'exceeded your current quota', 'billing_hard_limit',
    'billing hard limit', 'check your plan and billing', 'account is not active',
    'credit_balance_exhausted', 'no prepaid credits',
    // O Google não diz "sem crédito": ele diz que o projeto não tem cobrança
    // ligada, e o efeito é o mesmo — nenhuma chamada passa até alguém entrar na
    // conta. Sem estas assinaturas o caso caía em "limite indeterminado" e o
    // dono ia procurar cadência onde o problema era cadastro.
    'billing_disabled', 'billing account', 'billing to be enabled', 'consumer_suspended')) {
    causa = 'sem_credito';
    motivo = 'CONTA DO PROVEDOR SEM CRÉDITO OU SEM COBRANÇA ATIVA. A conta não tem como pagar a '
      + 'chamada — na OpenAI é saldo pré-pago esgotado (insufficient_quota), no Google é o projeto '
      + 'sem billing habilitado. Espaçar as chamadas NÃO resolve: é preciso recarregar crédito '
      + '(platform.openai.com/settings/organization/billing) ou ligar a cobrança do projeto.';
  } else if (tem('tokens per day', 'requests per day', 'tpd', 'rpd', 'daily limit', 'per-day',
    'perday', 'generate_content_free_tier_requests')) {
    causa = 'limite_diario';
    motivo = 'COTA DIÁRIA DO PROVEDOR ESGOTADA (limite por DIA de tokens/requisições do tier da '
      + 'conta). Espaçar as chamadas não resolve hoje: a cota reabre na virada da janela diária, ou '
      + 'sobe junto com o tier da conta.';
  } else if (tem('rate_limit_exceeded', 'rate limit', 'too many requests', 'tokens per min',
    'requests per min', 'tpm', 'rpm', 'resource_exhausted', 'perminute')) {
    causa = 'limite_cadencia';
    motivo = 'LIMITE DE CADÊNCIA DO PROVEDOR (rate limit por minuto). Aqui espaçar as chamadas ajuda '
      + 'de fato — é o único caso em que ajuda. E o número a mexer é TPM_CONTA/RPM_CONTA do provedor '
      + 'ativo (N8N/lib/provedor.mjs): é dele que sai o intervalo entre chamadas, e ajustá-lo no nó '
      + 'à mão faz o teste da cadência e o workflow discordarem no primeiro rebuild.';
  } else if (status === 401 || status === 403
    || tem('invalid_api_key', 'incorrect api key', 'invalid authentication',
      'api key not valid', 'api_key_invalid', 'permission_denied', 'permission denied')) {
    causa = 'chave_invalida';
    motivo = 'CHAVE DO PROVEDOR INVÁLIDA, AUSENTE OU SEM PERMISSÃO (401/403). Nada a ver com '
      + 'cadência ou crédito: a credencial do nó HTTP no N8N precisa ser corrigida — na OpenAI é o '
      + 'header "Authorization: Bearer sk-...", no Google é "x-goog-api-key: ...". O nome da '
      + 'credencial que o workflow espera está em N8N/lib/provedor.mjs (campo `credencial`).';
  } else if (status === 404 || tem('model_not_found', 'does not exist or you do not have access',
    'is not found for api version', 'not_found')) {
    causa = 'modelo_indisponivel';
    motivo = 'MODELO INDISPONÍVEL PARA ESTA CONTA (404). O modelo configurado no workflow não existe '
      + 'ou a conta não tem acesso a ele — conferir MODELOS_POR_PROVEDOR em N8N/lib/custo.mjs contra '
      + 'os modelos que a conta lista. No Google o nome do modelo vai na URL, então um id errado é '
      + '404 no endereço, não erro de corpo.';
  } else if (status === 429) {
    // 429 sem assinatura reconhecível: NÃO afirmar cadência. Foi exatamente o
    // palpite errado do v28→v30, e afirmar causa sem evidência é o defeito que
    // este diagnóstico existe para não repetir.
    causa = 'limite_indeterminado';
    motivo = 'LIMITE DO PROVEDOR ATINGIDO (HTTP 429), mas a resposta não disse QUAL: pode ser '
      + 'crédito esgotado, cota diária, ou cadência por minuto — e cada um pede ação diferente. '
      + 'Confira no console do provedor: se houver saldo/limite disponível, é cadência; se não '
      + 'houver, é crédito. Espaçar as chamadas só resolve o caso de cadência.';
  } else {
    motivo = `ERRO NA CHAMADA AO PROVEDOR DE IA${status ? ` (HTTP ${status})` : ''}: `
      + `${mensagemOpenAI || mensagemBruta || textoDoErro(erro).slice(0, 300)}`;
  }

  // OS HEADERS DE RATE LIMIT são o número que o repositório inteiro só chutava:
  // `x-ratelimit-limit-tokens` é o TPM REAL da conta para aquele modelo, e
  // `retry-after` é quanto a própria OpenAI diz para esperar. O n8n preserva os
  // headers em `error.response.headers` (legacy-request.ts) — eles estavam ali no
  // v30, intactos, e o pipeline os descartava junto com o resto.
  const headers = (erro && erro.response && erro.response.headers)
    || (erro && erro.headers)
    || (erro && erro.cause && erro.cause.response && erro.cause.response.headers)
    || null;
  const h = (nome) => {
    if (!headers) return null;
    const v = typeof headers.get === 'function' ? headers.get(nome) : headers[nome];
    return v == null || v === '' ? null : String(v);
  };
  const limiteTokens = h('x-ratelimit-limit-tokens');
  const restamTokens = h('x-ratelimit-remaining-tokens');
  const esperar = h('retry-after') || h('x-ratelimit-reset-tokens');

  // Detalhe técnico junto do motivo: sem isto a sessão seguinte fica no mesmo
  // escuro em que esta ficou. Só o que é útil para decidir — não o objeto todo.
  const detalhes = [
    status ? `http=${status}` : null,
    tipo ? `type=${tipo}` : null,
    codigo ? `code=${codigo}` : null,
    limiteTokens ? `limite_tokens_min=${limiteTokens}` : null,
    restamTokens ? `restavam=${restamTokens}` : null,
    esperar ? `esperar=${esperar}` : null,
    mensagemOpenAI ? `provedor="${String(mensagemOpenAI).slice(0, 200)}"` : null,
    // A mensagem do n8n entra por último e IDENTIFICADA como dele: ela é a que
    // enganou a rodada passada, então fica claro de quem é a frase.
    (mensagemBruta && mensagemBruta !== mensagemOpenAI)
      ? `n8n="${String(mensagemBruta).slice(0, 200)}"` : null,
  ].filter(Boolean).join(' ');

  // TRANSITÓRIA = repetir a MESMA chamada, depois de esperar, pode dar certo.
  // Execução 8433 (Fw Valtra, 05/10/2026): de 5 pendências `extracao_falhou`, 3 eram
  // desta natureza (2 de `limite_cadencia`, 1 de resposta vazia) e cada uma deixou
  // um documento incompleto no banco (2.541, 2.040 e 798 pares gravados) porque o
  // bloco foi chamado UMA vez só. Transitório: cadência por minuto, 429 sem causa
  // reconhecível (pode ser cadência; esgotar o teto de tentativas custa ~150 s, e
  // dar o bloco por perdido custa o documento), 408/5xx, e erro SEM status (queda
  // de rede). Permanente: crédito, cota do DIA, teto de gasto, chave, modelo e
  // qualquer outro 4xx (400 = pedido recusado; repetir manda o mesmo pedido).
  const CAUSAS_TRANSITORIAS = ['limite_cadencia', 'limite_indeterminado'];
  // `neverError` entrega o corpo de um 400 SEM status em campo nenhum (só
  // `{error:{type:'invalid_request_error',...}}`), então "sem status" sozinho não
  // quer dizer rede: só vale quando também não há `type`/`code` do provedor.
  // Assinaturas de servidor/rede cobrem o corpo de 5xx que também chega sem status.
  const assinaturaDeServidorOuRede = tem('server_error', 'overloaded', 'service unavailable',
    'unavailable', 'internal error', 'deadline_exceeded', 'timed out', 'timeout', 'econnreset',
    'etimedout', 'econnrefused', 'socket hang up', 'bad gateway', 'gateway time-out', 'enotfound');
  const transitoria = CAUSAS_TRANSITORIAS.includes(causa)
    || (causa === 'desconhecida'
      && !(status >= 400 && status < 500 && status !== 408)
      && (status === 408 || status >= 500 || assinaturaDeServidorOuRede
        || (status === null && !tipo && !codigo)));
  // QUANTO O PROVEDOR MANDA ESPERAR. O header (`retry-after`, em segundos) quase
  // nunca chega com `neverError` (o corpo chega, os headers não — ver acima), mas a
  // OpenAI escreve o mesmo número na mensagem ("Please try again in 6.8s",
  // "in 1m3.2s", "in 250ms") e o Google em "Please retry in 24.5s". Em segundos,
  // arredondado para cima; null quando não diz.
  const esperaDoTexto = (t) => {
    const trecho = /(?:try again|retry) in\s+([\d.ms]+)/i.exec(String(t || ''));
    if (!trecho) return null;
    const token = trecho[1].toLowerCase();
    const minutos = /^(\d+(?:\.\d+)?)m(?!s)/.exec(token);
    const depois = minutos ? token.slice(minutos[0].length) : token;
    const unidade = /^(\d+(?:\.\d+)?)(ms|s)/.exec(depois);
    if (!minutos && !unidade) return null;
    let segundos = minutos ? Number(minutos[1]) * 60 : 0;
    if (unidade) segundos += unidade[2] === 'ms' ? Number(unidade[1]) / 1000 : Number(unidade[1]);
    return Math.ceil(segundos);
  };
  const esperaDoHeader = (v) => (v !== null && /^\d+(\.\d+)?$/.test(String(v)) ? Math.ceil(Number(v)) : esperaDoTexto(`retry in ${v}`));
  const esperaSugeridaS = (esperar !== null ? esperaDoHeader(esperar) : null)
    ?? esperaDoTexto(`${mensagemOpenAI ?? ''} ${mensagemBruta ?? ''}`);

  return {
    causa,
    status,
    tipo,
    codigo,
    transitoria,
    esperaSugeridaS,
    mensagem: mensagemOpenAI ?? mensagemBruta ?? null,
    motivo: detalhes ? `${motivo} [${detalhes}]` : motivo,
  };
}

// O TETO DE TENTATIVAS POR BLOCO, e a conta que o sustenta. Auto-contida (o nó
// Code embute o `toString()`), como `diagnosticarErroApi`.
//
//   4 tentativas = a original + 3 repetições, com espera ANTES de cada repetição
//   de 30 s, 60 s e 60 s (150 s no pior bloco).
//
// Por que 60 s de teto por espera: o limite que mais aparece é o de TOKENS POR
// MINUTO, e o balde se recompõe em 60 s — esperar menos que isso repete o 429 e
// esperar mais não ganha nada. Também é o que mantém o `Esperar Retry` dentro do
// tempo de uma tarefa do Code node (300 s por padrão no task runner).
// O custo no relógio: cada estágio espera UMA vez para todos os blocos que falharam
// nele (não uma por bloco) e depois refaz as chamadas na cadência normal da
// extração. Execução 7851 (49 documentos) levou 1.237 s; um lote em que NENHUM bloco
// falha não gasta um segundo a mais, e um em que todos falham o tempo todo ganha no
// máximo 3 × (60 s + blocos × 6 s) — só quando o provedor está de fato fora.
//
// Devolve { repetir, esperaS, maxTentativas, esgotou }. `tentativa` é a que ACABOU
// de falhar (1 = a original). `esgotou` = era transitória e não há mais tentativa:
// é o único caso em que a pendência `extracao_falhou` por causa transitória é honesta.
export function decidirRepeticao({ transitoria = false, tentativa = 1, esperaSugeridaS = null } = {}) {
  const MAX_TENTATIVAS = 4;
  const ESPERAS_S = [30, 60, 60];
  const TETO_ESPERA_S = 60;
  const n = Number.isInteger(tentativa) && tentativa >= 1 ? tentativa : 1;
  const sobra = n < MAX_TENTATIVAS;
  const piso = ESPERAS_S[Math.min(n, ESPERAS_S.length) - 1];
  const pedida = Number.isFinite(esperaSugeridaS) && esperaSugeridaS > 0 ? esperaSugeridaS : 0;
  return {
    repetir: Boolean(transitoria) && sobra,
    esperaS: Math.min(TETO_ESPERA_S, Math.max(piso, pedida)),
    maxTentativas: MAX_TENTATIVAS,
    esgotou: Boolean(transitoria) && !sobra,
  };
}

// AVISO DO CONTEÚDO ENVIADO (`avisoConteudo`): o que o preparo do conteúdo já
// sabia estar faltando ANTES da chamada — planilha acima do teto de linhas/
// colunas (`avisoTruncamentoPlanilha`) ou formato que nem foi extraído (XLSX sem
// o "Extract From File" ligado). A extração pode voltar impecável e ainda assim
// estar incompleta, porque o pedaço que falta nunca chegou à IA. Ele entra em
// `falhaMotivo` — que a 0016 converte em pendência visível — SOMANDO-SE ao motivo
// da própria chamada em vez de competir com ele: os dois cabem no mesmo
// documento (planilha cortada E resposta truncada), e esconder um dos dois já é
// a falha que estamos fechando.
export function parseExtractionResponse(apiJson, { avisoConteudo = null, prov = provedor() } = {}) {
  const cortado = cortadoPorLimite(prov, apiJson);
  const comAviso = (motivo) => [avisoConteudo, motivo].filter(Boolean).join(' | ') || null;
  const vazio = (falhaMotivo) => ({
    moeda: null, unidade: null, campos: [], falhaMotivo: comAviso(falhaMotivo),
    diagnostico: {
      entidade: null, tipo_confirma: null, tipo_sugerido: null, periodo_tipo: null,
      periodo_referencia: null, legibilidade: null, nota_legibilidade: null,
      // null (não false): a chamada falhou, então não há diagnóstico algum — e
      // "null" no Sinal 3 (0111) se comporta como "documento deveria ter dado",
      // que é o padrão seguro quando não se sabe.
      tem_dado_financeiro: null,
      resumo: null, justificativa: '(sem diagnóstico: falha de rede/API ou resposta inválida)',
    },
  });
  if (apiJson?.error) {
    // Diagnostica a CAUSA em vez de repassar a frase do n8n: ver
    // `diagnosticarErroApi` acima e o que o "teste v30" custou sem isto.
    return vazio(diagnosticarErroApi(apiJson.error).motivo);
  }
  const content = conteudoDaResposta(prov, apiJson);
  if (!content) {
    return vazio(`Resposta do provedor de IA (${prov.rotulo}) sem conteúdo (falha de rede/API).`);
  }
  let p;
  try {
    p = typeof content === 'string' ? JSON.parse(content) : content;
  } catch {
    if (cortado) {
      return vazio(
        'Resposta do provedor de IA truncada por limite de tokens de saída — o JSON ficou '
        + 'incompleto e não pôde ser interpretado. Documento provavelmente grande/denso demais '
        + '(muitas contas/entidades) para uma única chamada.',
      );
    }
    return vazio('Resposta do provedor de IA não veio em JSON válido.');
  }
  const unidade = normalizarUnidade(p.unidade);
  // MOEDA DO DOCUMENTO, HERDADA POR LINHA — item 2 do §7.4 do Onboarding.
  //
  // `normalizarMoeda` existe desde sempre e o schema já pede `moeda` à IA, mas o
  // valor morria AQUI: só o cabeçalho do retorno o carregava, nenhum campo o
  // levava ao banco (não havia coluna), e o book somava USD com BRL como se
  // fossem a mesma grandeza. Com o erro de escala de ~496× corrigido, era o
  // último fator multiplicativo invisível que sobrava.
  //
  // Herança pela MESMA regra da escala, e pelo mesmo motivo: linha não-monetária
  // (percentual, LPA, quantidade) não tem moeda, e marcá-la como BRL faria o
  // export tratar "margem 12%" como doze reais.
  const moedaDoc = normalizarMoeda(p.moeda);
  // Remapeia as chaves curtas do fio para os nomes completos usados em todo o
  // resto do sistema (campo_extraido e por diante) — a compactação é só na
  // conversa com a IA, nada rio abaixo muda.
  //
  // DOIS FORMATOS ACEITOS, e o antigo não é gentileza: é a defesa contra o
  // incidente de 12/08/2026, quando o n8n rodou por dias um workflow importado
  // meses antes. Enquanto existir um JSON velho em alguma instância, ele vai
  // responder no formato plano — e responder em formato plano tem de continuar
  // funcionando, em vez de virar "zero linhas extraídas" sem explicação.
  const { linhas: linhasAgrupadas, problemas, rotulosSuspeitos } = achatarGrupos(p.grupos);
  const camposAgrupados = linhasAgrupadas.map((l, i) => ({
    ordem: i,
    ...l,
    // A coluna manda: bloqueia a herança quando ela não é de dinheiro, e troca a
    // escala quando ela própria declara uma (ver v47, docs 24 e 28).
    unidade: ehLinhaNaoMonetaria(l.chave, l.valor_texto, l.periodo_coluna)
      ? null
      : (escalaDeclaradaNaColuna(l.periodo_coluna) ?? unidade),
    moeda: ehLinhaNaoMonetaria(l.chave, l.valor_texto, l.periodo_coluna) ? null : moedaDoc,
  }));
  const camposPlanos = Array.isArray(p.linhas)
    ? p.linhas.map((l, i) => ({
        // ORDEM da linha no documento (Supabase/migrations/0027). NÃO é pedida ao
        // modelo: é a posição no array que ele devolveu, que já é a ordem de
        // leitura do documento. Pedir um campo de ordem gastaria token de saída
        // por linha e daria ao modelo uma chance de errar algo que nós já
        // sabemos com certeza. É o que permite ao export reconhecer um subtotal
        // impresso ACIMA dos seus componentes (teste v28: Ativo Circulante da
        // VT Logística saiu 7.254 onde o documento diz 3.961).
        ordem: i,
        secao: l.s ?? null,
        secao_canonica: l.sc && l.sc !== 'NAO_CLASSIFICAVEL' ? l.sc : null,
        entidade_coluna: l.ec ?? null,
        periodo_coluna: l.pc ?? null,
        chave: l.k,
        valor_texto: l.vt ?? null,
        valor_num: typeof l.vn === 'number' ? l.vn : null,
        // escala e moeda do documento, EXCETO em linha não-monetária (ver acima)
        unidade: ehLinhaNaoMonetaria(l.k, l.vt, l.pc)
          ? null
          : (escalaDeclaradaNaColuna(l.pc) ?? unidade),
        moeda: ehLinhaNaoMonetaria(l.k, l.vt, l.pc) ? null : moedaDoc,
        confianca: typeof l.cf === 'number' ? l.cf : null,
        origem_pagina: Number.isInteger(l.op) ? l.op : null,
      }))
    : [];
  // O agrupado manda quando veio; o plano é o caminho do JSON velho.
  const campos = camposAgrupados.length > 0 || Array.isArray(p.grupos)
    ? camposAgrupados
    : camposPlanos;
  const d = p.diagnostico || {};
  const diagnostico = {
    entidade: d.entidade ?? null,
    cnpj: d.cnpj ?? null,
    tipo_confirma: typeof d.tipo_confirma === 'boolean' ? d.tipo_confirma : null,
    tipo_sugerido: d.tipo_sugerido === 'DESCONHECIDO' ? null : (d.tipo_sugerido ?? null),
    periodo_tipo: d.periodo_referencia ? d.periodo_tipo : null,
    periodo_referencia: d.periodo_referencia ?? null,
    legibilidade: d.legibilidade ?? null,
    nota_legibilidade: d.nota_legibilidade ?? null,
    tem_dado_financeiro: typeof d.tem_dado_financeiro === 'boolean' ? d.tem_dado_financeiro : null,
    resumo: d.resumo ?? null,
    justificativa: d.justificativa ?? '',
    // Os fatos viajam para `fn_registrar_fatos` no MESMO nó que grava o
    // diagnóstico. `null` quando a chave não veio (workflow antigo) é diferente
    // de `[]` (o modelo leu e não achou nada): o banco NÃO apaga os fatos de uma
    // versão quando recebe null, porque apagar trilha por causa de um workflow
    // desatualizado é o defeito do `Gravar Campos` que desligou a reconciliação
    // por onze dias.
    fatos: Array.isArray(d.fatos)
      ? d.fatos
        .filter((f) => f && typeof f === 'object' && typeof f.ft === 'string'
                       && typeof f.tr === 'string' && f.tr.trim().length >= 20)
        .map((f) => ({
          tipo: f.ft,
          trecho: f.tr.trim(),
          leitura: typeof f.le === 'string' && f.le.trim() !== '' ? f.le.trim() : null,
          pagina: Number.isInteger(f.pg) ? f.pg : null,
        }))
      : null,
  };
  // Corte por teto COM JSON válido é raro (o corte quase sempre cai
  // no meio de uma string/array e quebra o parse acima), mas se acontecer o
  // conteúdo pode estar incompleto de forma "silenciosa" (JSON bem formado,
  // faltando linhas do fim do documento) — sinaliza mesmo assim.
  //
  // E o desalinhamento de coluna entra no MESMO campo, porque é da mesma
  // família: dado que o documento tem e o banco não recebeu. Sem isto a conta
  // descartada por `achatarGrupos` sumiria em silêncio — e "silêncio" é o modo
  // de falha que este projeto passa o tempo corrigindo.
  const motivos = [
    cortado
      ? 'Resposta do provedor de IA atingiu o limite de tokens de saída; o JSON veio válido, mas o '
        + 'conteúdo pode estar incompleto (faltando linhas do fim do documento).'
      : null,
    problemas.length > 0
      ? `${problemas.length} conta(s) descartada(s) por desalinhamento entre colunas e valores `
        + `(a associação valor↔coluna ficou desconhecida, e adivinhá-la trocaria um período pelo `
        + `outro): ${problemas.slice(0, 5).join('; ')}${problemas.length > 5 ? '; …' : ''}`
      : null,
    rotulosSuspeitos.length > 0
      ? `${rotulosSuspeitos.length} rótulo(s) com número colado que não é o valor da linha (a conta foi `
        + `mantida, o rótulo NÃO foi limpo e pode não casar na reconciliação): `
        + `${rotulosSuspeitos.slice(0, 5).join('; ')}${rotulosSuspeitos.length > 5 ? '; …' : ''}`
      : null,
  ].filter(Boolean);
  const falhaMotivo = comAviso(motivos.length > 0 ? motivos.join(' | ') : null);
  return { moeda: moedaDoc, unidade, campos, diagnostico, falhaMotivo };
}

export { DEFAULT_MODEL, PERIODO_TIPO_ENUM };
