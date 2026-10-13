// Gera o workflow N8N da Fatia 1 (E1 ingestão + E2 extração em sombra).
// Rodar: node N8N/build-workflow.mjs  → escreve N8N/workflow.e1-ingestao.json
//
// A lógica dos nós Code ESPELHA os módulos testados em N8N/lib/ (fonte da verdade
// dos testes). Ao mudar a lógica: mude lib/, rode `npm test`, e regenere.
// O teste N8N/test/workflow-sim.test.mjs executa os códigos REAIS deste JSON
// com dados mock, simulando a passagem de dados node a node.
//
// REGRAS DE FLUXO (aprendidas testando no N8N real — não violar):
// 1. Node Postgres NÃO repassa binário: a saída são as linhas da query.
//    → Quem precisa dos arquivos lê do Form por referência: $('Intake (Form)').
// 2. Node HTTP Request SUBSTITUI o item pela resposta da API (perde json+binário).
//    → Upload Storage é RAMO LATERAL (nada depende da saída dele).
//    → Após chamadas OpenAI, o contexto volta por $('Nome do Node').item.
// 3. Code em 'runOnceForEachItem' retorna UM OBJETO {json,binary?}; em
//    'runOnceForAllItems' retorna ARRAY (único modo que permite fan-out).
// 4. Code que repassa arquivos deve devolver `binary` explicitamente
//    (retornar só {json} descarta o binário).
// 5. Posição de nó no canvas NÃO se escreve aqui: quem desenha é `posicionar()`
//    (N8N/layout.mjs), a partir das `connections`. Nó novo declara só a conexão.

import { posicionar } from './layout.mjs';
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { codigosConhecidos } from './lib/ia.mjs';
import {
  provedor, urlDaChamada, montarCorpoIA, schemaDoProvedor, parteDeArquivo, parteDeTexto,
  conteudoDaResposta, cortadoPorLimite, usoDaChamada, usoGemini, acrescentarInstrucao,
  capacidadesDoModelo, CAPACIDADES_POR_MODELO, CAPACIDADES_PADRAO,
} from './lib/provedor.mjs';
import { createHash } from 'node:crypto';
import { SYSTEM_PROMPT, diagnosticarErroApi, decidirRepeticao, MAX_OUTPUT_TOKENS, TPM_CONTA, RPM_CONTA, PISO_BATCHING_MS, normalizarUnidade, normalizarMoeda, extractionSchema, achatarGrupos, limparRotuloColado, ehLinhaNaoMonetaria, escalaDeclaradaNaColuna } from './lib/extract.mjs';
import { ALIASES } from './lib/taxonomia.mjs';
import { classifyByFilename, parseTipo, parsePeriodo, periodoAcumuladoNoAno, periodoDeIntervaloDeAnos, parseAssinado, parseEntidade, THRESHOLD_AUTO } from './lib/classifier.mjs';
import { normalize } from './lib/normalize.mjs';
import { mergeClassification } from './lib/merge.mjs';
import { orcamentoDoLote, orcamentoDoLotePorConteudo, instrucaoDeLevasDoLote, vereditoDaCotaDiaria, FRACAO_AVISO_RPD, custoEstimadoPorConteudo, tokensDeSaida, TETO_EXECUCAO_USD, CUSTO_ESTIMADO_DOC_USD, CUSTO_POR_MB_USD, CUSTO_MINIMO_CHAMADA_USD, bytesDoBinario, vereditoDeTamanhoPorArquivo, TETO_BYTES_POR_ARQUIVO, custoDaChamada, PRECO_USD_POR_MILHAO, MODELO_CLASSIFICACAO, MODELO_EXTRACAO, PARCELA_ENTRADA_NA_CHAMADA, PESO_MINIMO_CLASSIFICACAO, VERSAO_ORCAMENTO, pesoDaChamadaDeClassificacao, TOKENS_POR_PAGINA_IMAGEM, TOKENS_CABECALHO_GRUPO, TOKENS_CONTA_BASE, TOKENS_POR_VALOR, CONTAS_POR_GRUPO, TOKENS_SAIDA_CLASSIFICACAO, MARGEM_ORCAMENTO_CONTEUDO, CARACTERES_POR_TOKEN, PAGINAS_MAX_MEDIDO, custoEstimadoPorTamanho, custoPorMbDeTextoUSD, CELULAS_POR_PAGINA_ESTIMADAS, CARACTERES_POR_CELULA_ESTIMADA, estimativaDoDocumento, esforcosDoProvedor, FORMATOS_DE_TEXTO, ehFormatoDeTexto } from './lib/custo.mjs';
import { sha256Hex, chaveDoOriginal } from './lib/hash.mjs';
import {
  ASSINATURAS, SEPARADORES, byteEm, casaAssinatura, saborDoZip, trechoLatin1,
  pareceTexto, contarFora, formaDoTexto, detectarFormato, abasDoXlsx,
} from './lib/formato.mjs';
import {
  spreadsheetToText, colunasDaPlanilha, avisoTruncamentoPlanilha,
  MAX_LINHAS_PLANILHA, MAX_COLUNAS_PLANILHA,
} from './lib/spreadsheet.mjs';
import {
  linhasComNumero, linhasDeConta, ehLinhaDeConta, juntarFragmentosDeLinha, ehLinhaSemValor,
  juntarFragmentosComOrigem, contasComOrigem, contasPorLinhaComNumero,
  linhasDaPassada, decidirSegundaPassada, melhorPassada, instrucaoDeSegundaPassada,
  camadaDeTextoDoPdf, CARACTERES_MINIMOS_POR_PAGINA, MINIMO_LINHAS_COM_NUMERO_PDF,
  fracaoDePalavrasDobradas, MAX_FRACAO_PALAVRAS_DOBRADAS,
  celulasDaLinha, celulasEstimadas,
  planejarFatias, instrucaoDaFatia, juntarBlocos, avaliarCobertura,
  MAX_CELULAS_POR_BLOCO, LIMIAR_COBERTURA, MINIMO_PARA_AVALIAR,
} from './lib/cobertura.mjs';
import { conferirIdentidadeDeLinha, conferirTotalDaSerie, conferirBalanceteLinhaALinha, conferirHierarquiaDeCodigos, blocosDeLinha, linhasDaHierarquia, fechaComDeslocamento, blocoDaSintetica, filhasDiretas, classificarHierarquia, papelDeColunaDeBalancete, agruparContasDeBalancete, classificarContasDeBalancete, mensagemDoBalancete } from './lib/aritmetica.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Enums da classificação — IMPORTADOS de lib/ia.mjs (fonte única), não
// copiados à mão: um mirror manual desses códigos já ficou desatualizado uma
// vez (permitindo a OpenAI inventar "BAL" em vez de "BALANCO", sem nenhum
// enum travando a saída) e só foi pego testando com documento real no N8N.
const TIPO_TAXONOMIA_ENUM = JSON.stringify(codigosConhecidos());
const PERIODO_TIPO_ENUM = JSON.stringify(['anual', 'trimestre', 'multi', 'data-base', 'outro', 'desconhecido']);

// Apelidos por código da taxonomia — IMPORTADOS de lib/taxonomia.mjs pelo mesmo
// motivo dos enums acima, e aqui o mirror manual JÁ TINHA DIVERGIDO: a cópia à
// mão parava em BALANCETE e o nó real do workflow não conhecia DF_AUDITADA,
// MAPA_DIVIDA, EXTRATO_BANCARIO, AGING_AR/AP, ESTOQUE, CERTIDOES, CONTINGENCIAS,
// SITUACAO_FISCAL, ORGANOGRAMA, RAZAO nem NOTAS_EXPL. Em produção esses arquivos
// saíam do passe de nome SEM TIPO — a classificação por nome existe justamente
// para não gastar uma chamada de IA com o que o nome já diz. `N8N/test/
// workflow-sim.test.mjs` agora compara as duas listas e falha se voltarem a
// divergir. A ORDEM da lista é significativa (regra específica antes da genérica)
// e serializar preserva ela.
const ALIASES_JSON = JSON.stringify(ALIASES);

// Modelos das DUAS chamadas. Eles MORAVAM aqui e passaram a morar em
// `lib/custo.mjs` (13/08/2026), porque o orçamento do lote passou a precisar do
// preço da classificação para pesar a segunda chamada — e preço derivado de um
// modelo declarado noutro arquivo é a cópia à mão que este repositório já viu
// divergir. Aqui ficam só os apelidos, para os nós não mudarem de forma.
//
// Hoje: classificação em `gpt-4o-mini`, extração em `gpt-4o`. O porquê (e a rede
// que torna isso seguro) está no comentário da fonte e em docs/CUSTO_OPENAI.md.
const MODEL_CLASSIFICACAO = MODELO_CLASSIFICACAO;
const MODEL_EXTRACAO = MODELO_EXTRACAO;

// Schemas estritos (mesma forma dos módulos lib/ia.mjs e lib/extract.mjs).
const SCHEMA_CLASSIF = `{name:'classificacao_documento',strict:true,schema:{type:'object',additionalProperties:false,required:['tipo_taxonomia','entidade','cnpj','periodo_tipo','periodo_referencia','assinado','confianca','justificativa'],properties:{tipo_taxonomia:{type:'string',enum:${TIPO_TAXONOMIA_ENUM}},entidade:{type:['string','null']},cnpj:{type:['string','null']},periodo_tipo:{type:'string',enum:${PERIODO_TIPO_ENUM}},periodo_referencia:{type:['string','null']},assinado:{type:['boolean','null']},confianca:{type:'number',minimum:0,maximum:1},justificativa:{type:'string'}}}}`;
// 0170: `cnpj` no schema ESTRITO (strict:true → precisa estar em `required`,
// mesmo aceitando null — é assim que os outros campos opcionais já fazem
// aqui, `entidade` e `periodo_referencia` inclusive). É o CNPJ do EMITENTE,
// não de quem assina nem do escritório de contabilidade — ver o aviso no
// prompt de sistema logo abaixo, escrito depois de a revisão da 0169 achar
// esse cenário concreto: o rodapé do relatório às vezes traz o CNPJ do
// contador, e lê-lo como identidade da empresa fundiria clientes diferentes.
// Diagnóstico (entidade/confere tipo+período/legibilidade/resumo) + linhas
// com `secao` (agrupador de planilha) — mesma chamada que já rodava sempre
// para extrair linhas (não aumenta o nº de chamadas à OpenAI); espelha
// N8N/lib/extract.mjs (fonte da verdade).
// O SCHEMA DA EXTRAÇÃO SAI DA FONTE, NÃO DE UM ESPELHO À MÃO.
//
// Ele era uma linha de 2.400 caracteres copiada de `lib/extract.mjs` e mantida
// em paralelo — e este repositório já tem a lista dos espelhos manuais que
// divergiram (o `ALIASES` que parava em BALANCETE, o `normUnid` que perdeu a
// última cláusula, o schema de classificação que ficou sem `enum` e fez a
// OpenAI inventar "BAL"). O schema é JSON puro, então serializar a função da
// fonte é exato e a divergência deixa de ser possível: mudar o formato da saída
// num arquivo só passa a bastar. `extractionSchema()` já traz `strict`,
// `diagnostico`, `grupos` e os enums (taxonomia, seção canônica, legibilidade).
const SCHEMA_EXTRACAO = JSON.stringify(extractionSchema());

// `diagnosticarErroApi` é EMBUTIDA a partir do fonte de lib/extract.mjs (fonte
// única — o nó Code do n8n não importa arquivo, e cópia à mão neste repositório
// já divergiu duas vezes). A função é auto-contida justamente para o toString()
// bastar; `workflow-sim.test.mjs` confere que o nó carrega este mesmo código.
const FONTE_DIAGNOSTICO_ERRO = `const diagnosticarErroApi = ${diagnosticarErroApi.toString()};`;
// `decidirRepeticao` idem: o teto de tentativas e as esperas moram numa função só,
// embutida no Parse (que decide repetir) e lida aqui (que decide QUANTOS estágios
// de repetição o grafo tem). Duas fontes do mesmo teto divergem sem erro nenhum.
const FONTE_DECIDIR_REPETICAO = `const decidirRepeticao = ${decidirRepeticao.toString()};`;
const TENTATIVAS_MAX_EXTRACAO = decidirRepeticao().maxTentativas;

// `parseEntidade` idem — embutida do fonte, não espelhada à mão. Ela é a correção
// do achado do "teste v31" (entidade "—" nos 14 documentos porque o nome do
// arquivo nunca era lido para isso); ver o comentário longo em lib/classifier.mjs
// para por que ela NÃO mexe na confiança.
const FONTE_PARSE_ENTIDADE = `const parseEntidade = ${parseEntidade.toString()};`;

// `mergeClassification` idem — embutida do fonte para o CNPJ (0170/0171) não
// nascer divergente entre a lib e o nó: era cópia à mão antes desta fatia, e o
// achado do teste v31 (Math.max da confiança) veio exatamente desse padrão.
const FONTE_MERGE_CLASSIF = `const mergeClassification = ${mergeClassification.toString()};`;

// `normalizarUnidade` — o mirror manual que ficou de fora quando todos os outros
// passaram a ser embutidos, e que JÁ DIVERGIU. A cópia à mão em `normUnid` perdeu
// a última cláusula da fonte:
//
//     if (t === '1' || t === '1.000' || t === '1000') return t === '1' ? 'unidade' : 'milhar';
//
// Divergência MEDIDA (não estimada): em 13 redações de escala testadas, 3 diferem —
// quando a célula é EXATAMENTE o multiplicador (`1.000`, `1000`, `1`), que é como
// um cabeçalho de coluna costuma declarar a escala. A lib devolve
// `milhar`/`milhar`/`unidade`; o nó em produção devolvia `null` nos três.
//
// Por que `null` é caro aqui: escala nula não é neutra. `fn_valor_em_base`
// (0023:127) multiplica por `coalesce(fn_fator_escala(...), 1)`, então escala
// desconhecida é tratada como UNIDADE — e comparar milhar com unidade erra por
// 1000x. O comentário da própria fonte diz "errar em 1000x é pior que não saber";
// perder a escala silenciosamente entrega exatamente esse 1000x.
const FONTE_NORMALIZAR_UNIDADE = `const normUnid = ${normalizarUnidade.toString()};`;

// `naoMonet` ERA CÓPIA À MÃO, e a lógica dela mudou na v47 (a coluna passou a
// decidir). Cópia à mão neste repositório já divergiu duas vezes, e esta seria a
// terceira: a lib teria a regra nova e o nó Code do n8n — que é o que roda —
// continuaria com a antiga, gravando escala de milhão em coluna de pessoas sem
// que nenhum teste notasse. Agora as duas saem do MESMO `toString()`, e o
// `espelho-inline.test.mjs` confere.
const FONTE_NAO_MONETARIA = `const naoMonet = ${ehLinhaNaoMonetaria.toString()};`;
const FONTE_ESCALA_COLUNA = `const escalaCol = ${escalaDeclaradaNaColuna.toString()};`;
// Idem para a moeda: embutida do fonte, nunca copiada à mão — é o que garante
// que o nó e a lib normalizem "US$"/"dolar"/"usd" para o MESMO 'USD'. Divergir
// aqui reintroduziria exatamente a soma de moedas diferentes que a coluna
// `campo_extraido.moeda` existe para impedir.
// O FINGERPRINT DA EXTRAÇÃO — o que autoriza NÃO pagar a mesma extração duas
// vezes (Supabase/migrations/0118).
//
// Ele responde a uma pergunta só: "a extração que já está no banco foi feita
// com as MESMAS regras que eu usaria agora?". As regras são três — o prompt de
// sistema, o modelo e o esquema de resposta —, e todas as três mudam neste
// repositório com frequência (a 0116 acabou de mexer no prompt). Calculado aqui,
// no BUILD, e embutido como literal na chamada de registro: assim o valor muda
// junto com o workflow, e um workflow importado em julho nunca casa com a
// extração de hoje.
//
// Os 16 primeiros hex bastam: é identidade, não segurança — colisão acidental
// em 64 bits de conteúdo controlado não é um risco que valha uma coluna maior.
const FINGERPRINT_EXTRACAO = createHash('sha256')
  .update([SYSTEM_PROMPT, MODELO_EXTRACAO, JSON.stringify(extractionSchema())].join('\u0000'))
  .digest('hex')
  .slice(0, 16);

const FONTE_NORMALIZAR_MOEDA = `const normMoeda = ${normalizarMoeda.toString()};`;

// O TAMANHO DO PROMPT DE SISTEMA, calculado UMA VEZ aqui no BUILD (não dentro
// do nó — ele não importa `extract.mjs`) para dois consumidores: a linha
// `TOKENS_PROMPT_SISTEMA` embutida no nó Code (abaixo) e a CADÊNCIA
// entre chamadas (`INTERVALO_EXTRACAO_MS`), que precisa do MESMO número no
// lado do gerador. Duas contas separadas da mesma expressão já divergiram
// nesta casa (é a doença que este arquivo existe para não repetir) — uma só,
// usada nos dois lugares.
const TOKENS_PROMPT_SISTEMA_BUILD = Math.ceil(SYSTEM_PROMPT.length / CARACTERES_POR_TOKEN);

// Idem para o orçamento e para o custo real — embutidos do fonte, nunca copiados.
// O corpo de `orcamentoDoLote` referencia constantes do módulo, e `toString()`
// NÃO as leva junto — dentro do nó elas seriam `ReferenceError`. Embutir as
// quatro é o que mantém o espelho fiel; o teste que compara o nó com a fonte
// continua valendo sobre a função.
const FONTE_ORCAMENTO_LOTE = [
  `const FRACAO_AVISO_RPD = ${FRACAO_AVISO_RPD};`,
  // `provedor()` e nao `PROV`: esta lista e montada ANTES da linha que define
  // PROV, e a ordem de avaliacao de um template literal nao perdoa. O valor e o
  // mesmo — `provedor()` sem argumento devolve o provedor ativo.
  `const RPD_DO_PROVEDOR = ${provedor().rpd === null ? 'null' : provedor().rpd};`,
  vereditoDaCotaDiaria.toString(),
  `const TETO_EXECUCAO_USD = ${TETO_EXECUCAO_USD};`,
  `const CUSTO_ESTIMADO_DOC_USD = ${CUSTO_ESTIMADO_DOC_USD};`,
  `const CUSTO_POR_MB_USD = ${CUSTO_POR_MB_USD};`,
  `const CUSTO_MINIMO_CHAMADA_USD = ${CUSTO_MINIMO_CHAMADA_USD};`,
  `const BYTES_POR_MB = 1024 * 1024;`,
  // O peso da segunda chamada entrou no corpo de `orcamentoDoLote` (via
  // parâmetro com valor padrão), então a função e as CINCO constantes que ela
  // usa têm de vir junto — `toString()` não leva o escopo do módulo, e sem elas
  // o nó quebraria com ReferenceError na primeira execução.
  `const PRECO_USD_POR_MILHAO = ${JSON.stringify(PRECO_USD_POR_MILHAO)};`,
  `const MODELO_CLASSIFICACAO = ${JSON.stringify(MODELO_CLASSIFICACAO)};`,
  `const MODELO_EXTRACAO = ${JSON.stringify(MODELO_EXTRACAO)};`,
  `const PARCELA_ENTRADA_NA_CHAMADA = ${PARCELA_ENTRADA_NA_CHAMADA};`,
  `const PESO_MINIMO_CLASSIFICACAO = ${PESO_MINIMO_CLASSIFICACAO};`,
  `const VERSAO_ORCAMENTO = ${JSON.stringify(VERSAO_ORCAMENTO)};`,
  `const pesoDaChamadaDeClassificacao = ${pesoDaChamadaDeClassificacao.toString()};`,
  `const orcamentoDoLote = ${orcamentoDoLote.toString()};`,
  // A estimativa POR CONTEÚDO e as seis constantes dela. Mesma regra de
  // sempre: `toString()` não leva o escopo do módulo, então tudo o que o
  // corpo referencia é declarado aqui — inclusive o tamanho do prompt de
  // sistema, que é calculado no BUILD a partir do texto real (o nó não tem
  // como importar `extract.mjs` para medi-lo em execução).
  `const TOKENS_POR_PAGINA_IMAGEM = ${TOKENS_POR_PAGINA_IMAGEM};`,
  `const TOKENS_CABECALHO_GRUPO = ${TOKENS_CABECALHO_GRUPO};`,
  `const TOKENS_CONTA_BASE = ${TOKENS_CONTA_BASE};`,
  `const TOKENS_POR_VALOR = ${TOKENS_POR_VALOR};`,
  `const CONTAS_POR_GRUPO = ${CONTAS_POR_GRUPO};`,
  `const TOKENS_SAIDA_CLASSIFICACAO = ${TOKENS_SAIDA_CLASSIFICACAO};`,
  `const MARGEM_ORCAMENTO_CONTEUDO = ${MARGEM_ORCAMENTO_CONTEUDO};`,
  `const TOKENS_PROMPT_SISTEMA = ${TOKENS_PROMPT_SISTEMA_BUILD};`,
  // `custoDaChamada` é o que converte tokens em dólares, e ela também não vem
  // de graça: sem esta linha o nó estoura `ReferenceError` na primeira
  // execução REAL — que é o modo de falha mais caro possível, porque a suíte
  // fica verde e o lote morre no cliente.
  `const custoDaChamada = ${custoDaChamada.toString()};`,
  `const tokensDeSaida = ${tokensDeSaida.toString()};`,
  // O FORMATO ENTROU NA CONTA, então `ehFormatoDeTexto` e a lista dela têm de
  // atravessar junto — e esta linha é literalmente o `ReferenceError` que o
  // comentário de `custoDaChamada` oito linhas acima já descreve como "o modo de
  // falha mais caro possível, porque a suíte fica verde e o lote morre no
  // cliente". Foi medido nesta rodada, não suposto: executar o `jsCode` gerado
  // sem estas linhas estoura `ehFormatoDeTexto is not defined` em QUALQUER
  // chamada — inclusive a de PDF, porque a checagem de formato roda antes de
  // qualquer ramo.
  //
  // `CARACTERES_POR_TOKEN` entra pelo mesmo motivo e é novo aqui:
  // `custoEstimadoPorConteudo` passou a dividir bytes por ele para o documento
  // de TEXTO, e até agora esse nome só existia em tempo de build.
  `const FORMATOS_DE_TEXTO = ${JSON.stringify(FORMATOS_DE_TEXTO)};`,
  `const ehFormatoDeTexto = ${ehFormatoDeTexto.toString()};`,
  `const CARACTERES_POR_TOKEN = ${CARACTERES_POR_TOKEN};`,
  `const custoEstimadoPorConteudo = ${custoEstimadoPorConteudo.toString()};`,
  // O ORÇAMENTO PASSOU A SER DOCUMENTO A DOCUMENTO (13/09/2026), e as quatro
  // linhas abaixo são o que `estimativaDoDocumento` referencia. Sem elas o nó
  // estoura `ReferenceError` na primeira execução REAL com a suíte verde — o
  // modo de falha que o comentário de `custoDaChamada` acima já descreve como o
  // mais caro possível. `custoEstimadoPorTamanho` nunca tinha atravessado:
  // até aqui o caminho por byte era decidido DENTRO de `orcamentoDoLote`, e
  // agora ele é um dos quatro caminhos por documento.
  `const custoPorMbDeTextoUSD = ${custoPorMbDeTextoUSD.toString()};`,
  `const custoEstimadoPorTamanho = ${custoEstimadoPorTamanho.toString()};`,
  `const CELULAS_POR_PAGINA_ESTIMADAS = ${CELULAS_POR_PAGINA_ESTIMADAS};`,
  // E `CARACTERES_POR_CELULA_ESTIMADA` junto: o ramo de TEXTO de
  // `estimativaDoDocumento` a referencia, e a falta dela foi MEDIDA nesta
  // rodada como `ReferenceError: CARACTERES_POR_CELULA_ESTIMADA is not
  // defined` dentro do `jsCode` gerado -- com a suite INTEIRA verde, porque
  // nenhum caso do espelho exercitava o ramo de texto. O caso entrou junto.
  `const CARACTERES_POR_CELULA_ESTIMADA = ${CARACTERES_POR_CELULA_ESTIMADA};`,
  `const estimativaDoDocumento = ${estimativaDoDocumento.toString()};`,
  `const instrucaoDeLevasDoLote = ${instrucaoDeLevasDoLote.toString()};`,
  `const orcamentoDoLotePorConteudo = ${orcamentoDoLotePorConteudo.toString()};`,
].join('\n');
const FONTE_BYTES_BINARIO = `const bytesDoBinario = ${bytesDoBinario.toString()};`;
const FONTE_TAMANHO_POR_ARQUIVO = `const TETO_BYTES_POR_ARQUIVO = ${TETO_BYTES_POR_ARQUIVO};\nconst vereditoDeTamanhoPorArquivo = ${vereditoDeTamanhoPorArquivo.toString()};`;

// `achatarGrupos` idem — embutida do fonte. Ela é a tradução do formato agrupado
// (o que cortou 63% da saída) para as linhas que o banco grava, e é o ÚNICO
// lugar onde valor e coluna são associados. Espelhá-la à mão seria escolher o
// erro mais caro possível: uma divergência aqui grava o número de 2024 na coluna
// de 2025, sem sintoma nenhum.
const FONTE_ACHATAR_GRUPOS = `const limparRotuloColado = ${limparRotuloColado.toString()};\nconst achatarGrupos = ${achatarGrupos.toString()};`;

// As três camadas contra o truncamento e a extração pela metade (lib/cobertura.mjs),
// embutidas do fonte como todo o resto. O comentário do topo daquele arquivo tem
// os números que as motivaram — 1.139 de 2.893 células numa rodada real.
const FONTE_COBERTURA = [
  `const MAX_CELULAS_POR_BLOCO = ${MAX_CELULAS_POR_BLOCO};`,
  `const LIMIAR_COBERTURA = ${LIMIAR_COBERTURA};`,
  `const MINIMO_PARA_AVALIAR = ${MINIMO_PARA_AVALIAR};`,
  `const linhasComNumero = ${linhasComNumero.toString()};`,
  // ANTES de `linhasDeConta`, que a chama: no Code do n8n não há hoisting de
  // `const`, e a ordem aqui é a ordem do arquivo que roda.
  // A emenda COM origem vem ANTES da que a usa, e `contasComOrigem` antes de
  // `linhasDeConta` e de `contasPorLinhaComNumero`: sem hoisting de `const`.
  `const juntarFragmentosComOrigem = ${juntarFragmentosComOrigem.toString()};`,
  `const juntarFragmentosDeLinha = ${juntarFragmentosDeLinha.toString()};`,
  `const ehLinhaSemValor = ${ehLinhaSemValor.toString()};`,
  `const ehLinhaDeConta = ${ehLinhaDeConta.toString()};`,
  `const contasComOrigem = ${contasComOrigem.toString()};`,
  `const linhasDeConta = ${linhasDeConta.toString()};`,
  `const contasPorLinhaComNumero = ${contasPorLinhaComNumero.toString()};`,
  `const celulasDaLinha = ${celulasDaLinha.toString()};`,
  `const celulasEstimadas = ${celulasEstimadas.toString()};`,
  `const planejarFatias = ${planejarFatias.toString()};`,
  `const instrucaoDaFatia = ${instrucaoDaFatia.toString()};`,
  `const juntarBlocos = ${juntarBlocos.toString()};`,
  `const avaliarCobertura = ${avaliarCobertura.toString()};`,
  // DEPOIS de `linhasComNumero`, que ela chama — mesma regra de ordem do
  // comentário acima: o Code do n8n não hoista `const`.
  `const CARACTERES_MINIMOS_POR_PAGINA = ${CARACTERES_MINIMOS_POR_PAGINA};`,
  `const MINIMO_LINHAS_COM_NUMERO_PDF = ${MINIMO_LINHAS_COM_NUMERO_PDF};`,
  `const MAX_FRACAO_PALAVRAS_DOBRADAS = ${MAX_FRACAO_PALAVRAS_DOBRADAS};`,
  // ANTES de `camadaDeTextoDoPdf`, que a chama. O portão do espelho pegou a
  // ausência dela nesta lista antes de virar `ReferenceError` em produção —
  // `toString()` não leva o escopo do módulo, e é o terceiro caso desta família
  // nesta sessão.
  `const fracaoDePalavrasDobradas = ${fracaoDePalavrasDobradas.toString()};`,
  `const camadaDeTextoDoPdf = ${camadaDeTextoDoPdf.toString()};`,
].join('\n');

// A SEGUNDA PASSADA POR COBERTURA (lib/cobertura.mjs), só o que o `Parse Extracao`
// precisa: decide, escolhe a melhor das duas e escreve a instrução. NÃO leva a
// régua inteira (`FONTE_COBERTURA`) — o Parse existe em quatro cópias, e a régua
// pesa dezenas de KB cada.
const FONTE_SEGUNDA_PASSADA = [
  `const LIMIAR_COBERTURA = ${LIMIAR_COBERTURA};`,
  `const MINIMO_PARA_AVALIAR = ${MINIMO_PARA_AVALIAR};`,
  `const avaliarCobertura = ${avaliarCobertura.toString()};`,
  `const linhasDaPassada = ${linhasDaPassada.toString()};`,
  `const decidirSegundaPassada = ${decidirSegundaPassada.toString()};`,
  `const melhorPassada = ${melhorPassada.toString()};`,
  `const instrucaoDeSegundaPassada = ${instrucaoDeSegundaPassada.toString()};`,
].join('\n');

// AS DUAS IDENTIDADES ARITMÉTICAS (lib/aritmetica.mjs), embutidas do fonte
// como todo o resto — cada uma é AUTO-CONTIDA (declara seu próprio
// normalizador de rótulo por dentro), então não há ordem de dependência entre
// elas. Rodam em `Juntar Blocos`, sobre os `campos` já juntados do
// documento — antes do `Gravar Campos (Sombra)`, no mesmo canal de
// `falha_motivo` que já converte em pendência tipada (ver o comentário de
// `CODE_JUNTAR_BLOCOS` abaixo para o porquê de não ser um nó novo).
const FONTE_ARITMETICA = [
  `const conferirIdentidadeDeLinha = ${conferirIdentidadeDeLinha.toString()};`,
  `const conferirTotalDaSerie = ${conferirTotalDaSerie.toString()};`,
  `const papelDeColunaDeBalancete = ${papelDeColunaDeBalancete.toString()};`,
  `const agruparContasDeBalancete = ${agruparContasDeBalancete.toString()};`,
  `const classificarContasDeBalancete = ${classificarContasDeBalancete.toString()};`,
  `const mensagemDoBalancete = ${mensagemDoBalancete.toString()};`,
  `const blocosDeLinha = ${blocosDeLinha.toString()};`,
  `const linhasDaHierarquia = ${linhasDaHierarquia.toString()};`,
  `const blocoDaSintetica = ${blocoDaSintetica.toString()};`,
  `const filhasDiretas = ${filhasDiretas.toString()};`,
  `const fechaComDeslocamento = ${fechaComDeslocamento.toString()};`,
  `const classificarHierarquia = ${classificarHierarquia.toString()};`,
  `const conferirHierarquiaDeCodigos = ${conferirHierarquiaDeCodigos.toString()};`,
  `const conferirBalanceteLinhaALinha = ${conferirBalanceteLinhaALinha.toString()};`,
].join('\n');

// `sha256Hex` idem — embutida do fonte. Ela substituiu a dependência de
// `crypto.subtle`, que o dono MEDIU vindo ausente no sandbox do n8n dele
// (campo `hash` = null na saída de `Preparar Conteudo`, 2026-07-31); ver o
// cabeçalho de lib/hash.mjs.
const FONTE_SHA256 = `const sha256Hex = ${sha256Hex.toString()};
const chaveDoOriginal = ${chaveDoOriginal.toString()};`;
const FONTE_CUSTO_CHAMADA = `const PRECO_USD_POR_MILHAO = ${JSON.stringify(PRECO_USD_POR_MILHAO)};
const custoDaChamada = ${custoDaChamada.toString()};`;

// `spreadsheetToText`/`colunasDaPlanilha`/`avisoTruncamentoPlanilha` — embutidas
// do fonte (lib/spreadsheet.mjs), como todo o resto. ANTES desta rodada elas não
// entravam aqui: CSV era parseado por um `parseCsv` copiado à mão dentro do
// `Preparar Conteudo`, com nome IGUAL ao da lib mas NUNCA verificado contra ela
// pelo `espelho-inline.test.mjs` até essa suíte existir — coincidência de nome,
// não garantia. Ele sai de cena porque quem parseia CSV agora é o nó nativo
// `Extrair CSV`; o que sobra para o Code node é só formatar as linhas já
// parseadas (por CSV, XLSX ou XLS) em texto — a MESMA função para os três
// formatos, porque a partir daqui todos são "linhas de planilha".
// AS CONSTANTES PRECISAM VIR JUNTO, na mesma ordem do arquivo-fonte: são o
// `maxRows`/`maxCols` PADRÃO dos dois parâmetros de `spreadsheetToText` e
// `avisoTruncamentoPlanilha`, e `toString()` não leva o escopo do módulo —
// sem elas o nó morre com `ReferenceError` na primeira planilha grande.
const FONTE_SPREADSHEET = [
  `const MAX_LINHAS_PLANILHA = ${MAX_LINHAS_PLANILHA};`,
  `const MAX_COLUNAS_PLANILHA = ${MAX_COLUNAS_PLANILHA};`,
  `const colunasDaPlanilha = ${colunasDaPlanilha.toString()};`,
  `const spreadsheetToText = ${spreadsheetToText.toString()};`,
  `const avisoTruncamentoPlanilha = ${avisoTruncamentoPlanilha.toString()};`,
].join('\n');

// O DETECTOR DE FORMATO dentro do nó — a MESMA `lib/formato.mjs` que a suíte
// exercita, atravessando por `toString()` como todas as outras. Nenhuma segunda
// implementação: um detector no nó e outro na lib divergindo é exatamente o
// defeito que `PADRAO_MIME` já teve de consertar uma vez (três lugares decidindo
// por formato com três cópias do padrão).
const FONTE_FORMATO = [
  `const ASSINATURAS = ${JSON.stringify(ASSINATURAS)};`,
  `const SEPARADORES = ${JSON.stringify(SEPARADORES)};`,
  `const byteEm = ${byteEm.toString()};`,
  `const casaAssinatura = ${casaAssinatura.toString()};`,
  `const trechoLatin1 = ${trechoLatin1.toString()};`,
  `const saborDoZip = ${saborDoZip.toString()};`,
  `const abasDoXlsx = ${abasDoXlsx.toString()};`,
  `const pareceTexto = ${pareceTexto.toString()};`,
  `const contarFora = ${contarFora.toString()};`,
  `const formaDoTexto = ${formaDoTexto.toString()};`,
  `const detectarFormato = ${detectarFormato.toString()};`,
].join('\n');

// ---------------------------------------------------------------------------
// PADRÕES DE MIMETYPE — FONTE ÚNICA para os TRÊS lugares que decidem por
// formato: o `Roteador de Formato` (Switch nativo, condições declarativas), o
// `Preparar Conteudo` (JS, decide o que mandar à IA por padrão/enquanto a
// extração nativa não chega) e o `Recompor Conteudo Extraido` (JS, decide como
// interpretar o que cada extrator devolveu). As STRINGS de regex são as MESMAS
// nos três: divergirem aqui é o defeito que a auditoria dos 5 nós "Extract
// from..." descreveu (`Extract From XML` recebendo um `.pdf`) só que por
// descuido de gerador em vez de fan-out cego — o roteador manda o item para UM
// extrator e o Code node classifica o mesmo mimetype como outro.
// MUTUAMENTE EXCLUSIVOS DE PROPÓSITO — não por ordem de avaliação. O Switch
// nativo pode rodar em modo "primeira regra que bate" ou "todas as que
// baterem" (não confirmado contra a instância do dono), e um documento que
// batesse em DOIS padrões reintroduziria fan-out — o mesmo defeito da
// auditoria, por um mecanismo diferente. ACONTECEU AQUI, medido nesta
// rodada: `xml: 'xml'` casava com "vnd.openxml**formats**-officedocument.
// spreadsheetml.sheet" (o mimetype do XLSX contém "xml" como substring), então
// CADA .xlsx seria tratado como XML também. Corrigido ancorando no FIM da
// string (`/xml$`), que só bate no mimetype que É xml.
const PADRAO_MIME = {
  pdf: 'pdf',
  imagem: '^image/',
  csv: 'csv|^text/plain$',
  xlsx: 'spreadsheetml',
  xls: 'ms-excel|excel',
  xml: '/xml$',
};

// ---------------------------------------------------------------------------
// O PROVEDOR DENTRO DOS NÓS
// ---------------------------------------------------------------------------
//
// O provedor ativo entra nos nós Code como um LITERAL (`const PROVEDOR = {...}`)
// e as funções que falam com ele entram por `toString()`, como todas as outras
// funções espelhadas. É por isso que `lib/provedor.mjs` descreve cada provedor
// como dado puro e não como objeto com métodos: dado atravessa a fronteira do nó
// Code, método não.
//
// O QUE ISSO COMPRA, e é o ponto da troca inteira: trocar de provedor deixa de
// ser achar cada literal `choices[0].message.content` espalhado pelo gerador e
// passa a ser uma variável de ambiente mais um rebuild. As funções abaixo são as
// MESMAS que a lib usa e que as suítes exercitam — não há uma segunda
// implementação minificada do dialeto vivendo aqui dentro.
const PROV = provedor();
// O ESFORÇO DE RACIOCÍNIO É RESOLVIDO NO BUILD e vai como LITERAL para o nó.
// Mesma razão de `PROVEDOR` ser JSON: o nó Code não importa módulo, então a
// decisão tem de chegar como dado. `null` (provedor que não raciocina) faz
// `montarCorpoIA` não escrever o campo — e campo desconhecido é 400.
const ESFORCOS_ATIVOS = esforcosDoProvedor();
const ESFORCO_EXTRACAO = ESFORCOS_ATIVOS.extracao ? ESFORCOS_ATIVOS.extracao.esforco : null;
const ESFORCO_CLASSIFICACAO = ESFORCOS_ATIVOS.classificacao
  ? ESFORCOS_ATIVOS.classificacao.esforco : null;
const FONTE_PROVEDOR = [
  `const PROVEDOR = ${JSON.stringify(PROV)};`,
  // AS CAPACIDADES TÊM DE ATRAVESSAR JUNTO, e este é o motivo exato pelo qual
  // elas são um MAPA de dados e não um `if` sobre o id do modelo dentro de
  // `montarCorpoIA`: `toString()` não leva o escopo do módulo, então tudo o que
  // a função referencia precisa existir aqui como literal. Sem estas duas
  // linhas, `montarCorpoIA` chama `capacidadesDoModelo` dentro do nó Code e
  // morre com `ReferenceError` — a chamada de IA nunca sai. Foi o
  // `workflow-sim.test.mjs` que pegou isso, e é literalmente o que ele existe
  // para pegar.
  `const CAPACIDADES_POR_MODELO = ${JSON.stringify(CAPACIDADES_POR_MODELO)};`,
  `const CAPACIDADES_PADRAO = ${JSON.stringify(CAPACIDADES_PADRAO)};`,
  `const capacidadesDoModelo = ${capacidadesDoModelo.toString()};`,
  `const parteDeTexto = ${parteDeTexto.toString()};`,
  `const parteDeArquivo = ${parteDeArquivo.toString()};`,
  `const schemaDoProvedor = ${schemaDoProvedor.toString()};`,
  `const montarCorpoIA = ${montarCorpoIA.toString()};`,
  `const conteudoDaResposta = ${conteudoDaResposta.toString()};`,
  `const cortadoPorLimite = ${cortadoPorLimite.toString()};`,
  // `usoDaChamada` chama `usoGemini`, então ela atravessa junto — `toString()`
  // não leva o escopo do módulo (o mesmo motivo de `capacidadesDoModelo`).
  `const usoGemini = ${usoGemini.toString()};`,
  `const usoDaChamada = ${usoDaChamada.toString()};`,
  `const acrescentarInstrucao = ${acrescentarInstrucao.toString()};`,
].join('\n');

// --- Code (ALL ITEMS): o TETO DE GASTO POR EXECUÇÃO -------------------------
// RODA DEPOIS DO `Medir Documento`, e a mudança de lugar É a correção.
//
// Onde ele ficava: entre `Classificar Nome` e `Preparar Conteudo`. Ali o guarda
// tem o nome do arquivo e os bytes, e mais nada — então estimava por TAMANHO,
// com uma margem de 1,8× que superestima o lote típico em ~50%, e não tinha
// como saber quantos BLOCOS a extração ia gastar (documento acima de
// `MAX_CELULAS_POR_BLOCO` é fatiado, e cada fatia reenvia o PDF inteiro). Errava
// para cima no lote comum e para baixo no documento grande, que é o caro.
//
// Onde ele fica: logo depois de o texto do PDF ter sido lido e medido. Aqui as
// duas coisas que mandam no custo são EXATAS — as linhas com número saem do
// próprio documento, e o número de blocos sai de `planejarFatias`, a mesma
// função que o `Fatiar Extracao` vai executar adiante.
//
// E CONTINUA SENDO ANTES DE GASTAR, que é a propriedade inegociável: entre o
// `Medir Documento` e a primeira chamada à OpenAI (`IA Classificar`) não há
// gasto nenhum. O `Extrair Texto` é local, o `Upload Storage` é ramo lateral
// (religado em 07/10/2026; fala com o Storage, não com a IA, então não entra no
// gasto nem no RPD — e sai de `Preparar Conteudo`; NÃO foi medido se ele roda antes ou depois deste
// guarda: a evidência de 27/08 (ESTADO.md) sugere que o ramo irmão anda primeiro, e como
// o `Abortar Lote` lança, um lote recusado talvez nunca chegue a guardar original), e
// nenhum documento foi registrado — `Registrar Documento` vem
// depois do `Juntar Ramos`. Barrar aqui continua custando zero.
//
// A ESTIMATIVA POR BYTE NÃO FOI EMBORA: ela é o caminho de quando o conteúdo não
// pôde ser medido. O QUE MUDOU EM 13/09/2026 É QUE ELA DEIXOU DE SER CONTAGIOSA —
// a conta é documento a documento, e um PDF escaneado não derruba mais a medição
// dos outros 43. PDF sem camada de texto tem `paginas` (o `pdf-parse` conta sem
// depender de texto) e passa a ser estimado POR PÁGINA; só o arquivo do qual não
// se sabe nada cai no proxy por byte. Ver o comentário grande de
// `estimativaDoDocumento` em lib/custo.mjs — inclusive o porquê de o híbrido,
// diferente do tudo-ou-nada, nunca subestimar.
const CODE_ORCAMENTO = `
${FONTE_ORCAMENTO_LOTE}
${FONTE_COBERTURA}
const itens = $input.all();
const docs = itens.map((i) => {
  const j = i.json || {};
  // Blocos: a MESMA conta que o \`Fatiar Extracao\` fará. Documento sem camada de
  // texto vai inteiro (uma chamada), como sempre foi.
  const linhas = Array.isArray(j.linhas_do_texto) ? j.linhas_do_texto : [];
  // A MESMA CONTA DO \`Fatiar Extracao\`, com os MESMOS pesos. Duas estimativas da
  // mesma quantidade e' como elas divergem: se o orcamento previsse 1 bloco e o
  // fatiamento fizesse 4, o guarda de gasto mediria um lote que nao e' o que vai
  // rodar.
  const pesos = linhas.length > 0 ? celulasEstimadas(linhas) : [];
  const blocos = linhas.length > 0 ? planejarFatias(linhas, MAX_CELULAS_POR_BLOCO, pesos).length : 1;
  // CELULAS E COLUNAS, as duas MEDIDAS no texto.
  //
  // Antes as colunas vinham do NOME do arquivo ("25,24,23" são três; "12M25" é
  // uma), e o comentário de então declarava esse limite: coluna de EMPRESA não
  // aparece no nome. O que ele NÃO dizia é que \`celulas\` recebia a contagem de
  // LINHAS — e \`tokensDeSaida\` usa \`colunas\` para DIVIDIR células em contas, de
  // modo que passar linha onde ele espera célula fazia \`contas = linhas / colunas\`
  // num lugar em que a linha JÁ É a conta. As duas pontas erradas de uma vez, e o
  // erro se somava com o do fatiamento em vez de cancelar.
  //
  // Agora as duas saem do próprio texto (\`Medir Documento\`), e a razão
  // células/linhas conta a coluna de empresa junto — sem ler nome de arquivo.
  const celulas = Number.isFinite(Number(j.celulas_estimadas)) ? Number(j.celulas_estimadas)
    : Number(j.celulas_no_documento);
  const colunas = Number.isFinite(Number(j.colunas_estimadas)) && Number(j.colunas_estimadas) > 0
    ? Number(j.colunas_estimadas) : 1;
  return {
    // O NOME VIAJA PORQUE A RECUSA PASSOU A NOMEAR. Ate' 13/09/2026 a mensagem
    // dizia so' "a conta saiu de 14737 KB de arquivo": o dono nao tinha como
    // saber QUAL documento derrubou a medicao nem por que, e sobrava reenviar
    // as cegas em 22 levas. E' a regra 1 (nunca apresentar ausencia como dado)
    // aplicada ao proprio diagnostico do orcamento.
    nome: j.nome_original || null,
    celulas,
    paginas: Number(j.paginas_do_documento),
    colunas,
    blocos,
    precisaFallback: !!j.precisa_fallback_ia,
    // O FORMATO MEDIDO viaja ate' aqui porque a conta de custo depende dele, e
    // depender dele nao e' refinamento: \`CUSTO_POR_MB_USD\` (2,80) foi calibrado
    // sobre PDF, que vai ao modelo como IMAGEM (~1000 tokens/pagina). Aplicado a
    // TEXTO ele erra 53x para CIMA -- medido: 2 MB de texto estimam US$ 5,60
    // contra US$ 0,105 de entrada real. Foi esse numero que fez o dono concluir
    // que os arquivos da AMO eram impossiveis de processar neste sistema, e
    // mudar o proprio processo de trabalho por causa de um guarda errado.
    // Recusar lote que cabe e' o v31 pelo outro lado (ver o cabecalho de
    // lib/custo.mjs).
    // O FORMATO QUE A CONTA USA E' O DA LEITURA, nao o do arquivo. Um PDF lido
    // como TEXTO (\`leitura_pdf === 'texto'\`) manda caracteres, nao paginas de
    // imagem -- cobrar imagem dele superestima a entrada em ~4x num balanco
    // tipico e recusa lote que cabe.
    formato: (j.leitura_pdf==='texto' || j.leitura_planilha==='texto') ? 'texto' : (j.formato_detectado || null),
    // E O TAMANHO TAMBEM: para o PDF lido como texto, o que vai na chamada e' o
    // TEXTO (\`caracteres_do_texto\`), nao os bytes do PDF. Sem esta linha a conta
    // por texto dividiria os BYTES DO PDF por 4 -- um PDF de 2 MB viraria 500 mil
    // tokens onde ha 1.700 caracteres. Trocar um exagero por outro maior nao e'
    // correcao.
    bytes: (j.leitura_pdf==='texto' || j.leitura_planilha==='texto') && Number.isFinite(Number(j.caracteres_do_texto))
      ? Number(j.caracteres_do_texto) : Number(j.bytes),
  };
});
const r = orcamentoDoLotePorConteudo({ documentos: docs, teto: ${TETO_EXECUCAO_USD}, custoPorChamada: ${CUSTO_ESTIMADO_DOC_USD}, tokensPromptSistema: TOKENS_PROMPT_SISTEMA });
// A COTA DO DIA, ao lado do teto de gasto. Os dois medem grandezas diferentes e
// o lote so passa nos DOIS: o dolar diz quanto custa, o RPD diz se cabe no dia.
// Medido em 31/08: o araucaria (190 documentos) passava no teto de US$ 3 com
// folga e consumia 88% da cota -- o guarda aprovava o lote que a cota mataria.
const cota = vereditoDaCotaDiaria({ chamadas: r.chamadas, rpd: RPD_DO_PROVEDOR, fracaoAviso: FRACAO_AVISO_RPD });
// A recusa da cota entra pelo MESMO caminho da recusa de gasto (o IF manda para
// o \`Registrar Recusa\`), porque o efeito para quem enviou e' o mesmo e ter dois
// caminhos de recusa e' ter um deles sem tela. As duas mensagens somam quando as
// duas reprovam -- saber so metade do motivo faz reenviar errado.
const cabeTudo = r.cabe && cota.cabe;
const motivos = [r.mensagem, cota.cabe ? null : cota.mensagem].filter(Boolean);
const mensagemFinal = motivos.length > 0 ? motivos.join(' ') : null;
// Recusa o lote INTEIRO. Não existe "roda os que cabem" de propósito: metade
// registrada sem extração e metade sem registro nenhum é estado que dá mais
// trabalho para desfazer do que o reenvio que esta mensagem pede.
//
// E A RECUSA NÃO LANÇA AQUI: ela marca. Lançar punha a mensagem certa no lugar
// errado — ficava só no log do n8n, e o portal, que deduz progresso da ausência
// de documentos, seguia dizendo "estamos organizando tudo com cuidado" para
// sempre. Agora o item segue marcado, o IF manda a recusa para o nó que a GRAVA
// no banco, e só depois o lote é abortado.
//
// \`orcamento_versao\` viaja com o item mesmo quando o lote PASSA. É o que
// responde, da tela do n8n, a pergunta que custou uma rodada em 12/08: "este
// workflow é o que está no repositório ou é o que foi importado em julho?".
return itens.map(i => ({ json: { ...i.json, orcamento_cabe: cabeTudo, orcamento_mensagem: mensagemFinal, orcamento_estimado_usd: r.estimadoUSD, orcamento_teto_usd: r.teto, orcamento_chamadas: r.chamadas, orcamento_versao: r.versao, orcamento_por_conteudo: !!r.porConteudo, orcamento_aviso_medicao: r.aviso || null, orcamento_por_caminho: r.porCaminho || null, cota_cabe: cota.cabe, cota_conhecida: cota.conhecido, cota_fracao: cota.fracao, cota_rpd: cota.rpd, cota_aviso: cota.cabe ? cota.mensagem : null }, binary: i.binary }));
`.trim();

// --- Code (ALL ITEMS): O CUSTO DO LOTE, NUM PAINEL SÓ -----------------------
// Nasceu de uma pergunta do dono que não tinha resposta boa: "como acesso isso?"
// — sobre os tokens por documento. Eles existiam desde sempre, um por item do
// `Parse Extracao`: para saber o custo do lote era preciso abrir 14 painéis e
// somar à mão. Custo que só se conhece somando à mão é custo que ninguém mede,
// e este projeto passou meses decidindo teto de gasto por estimativa porque a
// medição estava espalhada.
//
// É um nó TERMINAL (nada depende dele), então ele não pode quebrar o lote: se
// não achar as referências, devolve o que achou e diz que achou pouco. E é o
// último da cadeia de propósito — quando ele aparece, o lote acabou.
const CODE_RESUMO_CUSTO = `
// Soma por NÓ, nunca por índice do lote. A tentação é casar item a item com
// \`$input\`, e estaria errado: só os documentos cujo nome não resolve o tipo
// passam pelo Parse Classif (8 de 14, no book do dono), então o índice i
// da cadeia principal NÃO é o índice i daquele nó. Casar por índice atribuiria o
// custo da classificação ao documento errado — e num relatório de custo isso é
// pior que não ter o relatório.
// O LOTE SE PARTE EM DOIS, E O RESUMO TEM DE SOMAR OS DOIS.
//
// O IF \`Precisa Fallback?\` manda os documentos por dois caminhos (com e sem
// classificacao por conteudo), e o n8n executa a cadeia inteira UMA VEZ POR
// RAMO. Na rodada de 14/08 isso deu 16 documentos numa execucao do
// \`Juntar Blocos\` e 19 na outra -- 35 no total, nada perdido -- mas o painel
// reportava so' a ultima, e o custo do lote saiu pela METADE. Pior: \`.all()\` sem
// indice de execucao devolve, para um no' do OUTRO ramo, tudo o que ele
// produziu; a classificacao entrava DUAS vezes na conta.
//
// Aqui as execucoes sao percorridas uma a uma. O painel sai duas vezes (uma por
// ramo), agora com o total INTEIRO nas duas -- somar dois paineis parciais a mao
// e' exatamente o trabalho que este no' existe para acabar.
const itensDe = (nome) => {
  const out = [];
  for (let run = 0; run < 50; run += 1) {
    let itens = null;
    try { itens = $(nome).all(0, run); } catch (err) { break; }
    if (!itens || itens.length === 0) break;
    for (const it of itens) out.push(it);
  }
  return out;
};
// \`Juntar Blocos\` e nao \`Parse Extracao\`: desde o fatiamento, o Parse tem um item
// por BLOCO, e contar blocos como documentos diria "48 documentos" para um lote
// de 35. O Juntar ja' devolve um item por documento, com o custo dos blocos
// somado. O fallback existe para o caso de alguem religar o grafo sem fatiamento.
const extracoes = itensDe('Juntar Blocos').length > 0 ? itensDe('Juntar Blocos') : itensDe('Parse Extracao');
const classificacoes = itensDe('Parse Classif');

// OS ORIGINAIS FICARAM GUARDADOS? O \`Upload Storage\` e' ramo lateral com
// onError=continueRegularOutput: ele NUNCA derruba o lote, e por isso uma falha dele
// tem a mesma aparencia de um lote em que tudo foi guardado (regra 7). Este e' o
// sinal positivo, e ele tem DUAS armadilhas medidas na revisao de 07/10/2026:
//
// (1) SUCESSO NAO SE DEDUZ DA AUSENCIA DE ERRO. Com continueRegularOutput o n8n
// devolve tambem o ITEM DE ENTRADA INTACTO quando o no' inteiro falha (credencial
// apagada ou trocada, item sem binario) -- a mesma forma que o Recompor Conteudo
// Extraido ja' conhece. Esse item nao tem \`error\` e traz caso_id/arquivo_ref. Por
// isso so' conta como guardado o item cuja resposta traz a \`Key\` do Storage e essa
// Key e' \`documentos/\` + um arquivo_ref que o Preparar Conteudo produziu neste lote.
//
// (2) A ORDEM DOS RAMOS NAO E' GARANTIDA. Em executionOrder v1 o upload pode rodar
// DEPOIS deste resumo (ESTADO.md, 27/08: o ramo irmao gravou documentos antes de a
// execucao morrer no Upload Storage). Zero itens aqui nao prova que nada foi
// guardado. \`isExecuted\` decide: se o no' ainda nao rodou, o sinal e' null e o
// texto manda conferir o bucket -- nunca "nenhum guardado" nem "0 falhas".
let uploadExecutou = false;
try { uploadExecutou = $('Upload Storage').isExecuted === true; } catch (err) { uploadExecutou = false; }
const uploads = uploadExecutou ? itensDe('Upload Storage') : [];
const esperados = new Set();
try { for (const p of $('Preparar Conteudo').all()) { if (p?.json?.arquivo_ref) esperados.add('documentos/' + p.json.arquivo_ref); } } catch (err) { /* sem Preparar: cai na regra fraca abaixo */ }
let guardados = 0, semGuarda = 0, primeiroErroUpload = null;
for (const it of uploads) {
  const u = it?.json || {};
  const keyOk = typeof u.Key === 'string' && !u.error
    && (esperados.size > 0 ? esperados.has(u.Key) : !('caso_id' in u) && !('arquivo_ref' in u));
  if (keyOk) { guardados += 1; continue; }
  semGuarda += 1;
  if (primeiroErroUpload === null) {
    primeiroErroUpload = u.error
      ? String(typeof u.error === 'object' ? (u.error.message || JSON.stringify(u.error)) : u.error).slice(0, 300)
      : 'resposta sem a Key do Storage (o no devolveu o item de entrada, ou uma Key inesperada)';
  }
}
const textoOriginais = !uploadExecutou
  ? '. Originais: o Upload Storage ainda nao tinha rodado quando este resumo fechou -- a conferencia e o bucket'
  : uploads.length === 0
    ? '. Originais: o Upload Storage rodou mas nao devolveu itens -- a conferencia e o bucket'
    : '. Originais guardados no Storage: ' + guardados + ' de ' + uploads.length
      + (semGuarda > 0 ? ' (' + semGuarda + ' SEM GUARDA; primeiro erro: ' + primeiroErroUpload + ')' : '');

let extracao = 0, entrada = 0, saida = 0, cache = 0, linhas = 0, comFalha = 0, semMedicao = 0;
let celulas = 0, contas = 0, fatiados = 0;
for (const it of extracoes) {
  const e = it?.json || {};
  if (typeof e.custo_usd === 'number') extracao += e.custo_usd; else semMedicao += 1;
  if (e.tokens) { entrada += e.tokens.entrada || 0; saida += e.tokens.saida || 0; cache += e.tokens.cache || 0; }
  if (e.falha_motivo) comFalha += 1;
  linhas += Array.isArray(e.campos) ? e.campos.length : 0;
  if (Number.isFinite(Number(e.contas_no_documento))) celulas += Number(e.contas_no_documento);
  // O painel do lote soma a MESMA unidade da guarda: linhas devolvidas contra
  // linhas de conta do texto. \`contas_distintas\` continua saindo por documento,
  // porque e' ela que diz se o documento tem rotulo repetido.
  if (Number.isFinite(Number(e.linhas_devolvidas))) contas += Number(e.linhas_devolvidas);
  else if (Number.isFinite(Number(e.contas_distintas))) contas += Number(e.contas_distintas);
  if (Number(e.blocos) > 1) fatiados += 1;
}
let classificacao = 0;
for (const it of classificacoes) {
  const c = it?.json || {};
  if (typeof c.custo_classificacao_usd === 'number') classificacao += c.custo_classificacao_usd;
}
const total = extracao + classificacao;
const arred = (x) => Number(x.toFixed(4));

// A comparação com o que o ORÇAMENTO estimou fecha o ciclo: é ela que diz se o
// estimador está calibrado, e é ela que este repositório nunca teve à mão.
let estimado = null, versao = null;
try {
  const o = $('Orcamento do Lote').first().json;
  estimado = o.orcamento_estimado_usd ?? null;
  versao = o.orcamento_versao ?? null;
} catch (err) { estimado = null; }

return [{ json: {
  resumo: 'Custo REAL deste lote: US$ ' + total.toFixed(4) + ' em ' + extracoes.length + ' documento(s)'
    + ' (' + classificacoes.length + ' pagaram o PDF duas vezes)'
    + (estimado !== null ? '. O orçamento havia estimado US$ ' + Number(estimado).toFixed(2) : '')
    + textoOriginais
    + '. Saída: ' + saida + ' tokens; entrada: ' + entrada + ' (' + cache + ' em cache).'
    + (celulas > 0 ? ' Cobertura: ' + contas + ' contas gravadas de ' + celulas + ' linhas de conta nos PDFs ('
      + (contas / celulas * 100).toFixed(0) + '%), em ' + linhas + ' pares conta-coluna. '
      + fatiados + ' documento(s) precisaram de mais de uma chamada.' : ''),
  orcamento_versao: versao,
  documentos: extracoes.length,
  originais_upload_executou: uploadExecutou,
  originais_guardados: uploads.length === 0 ? null : guardados,
  originais_sem_guarda: uploads.length === 0 ? null : semGuarda,
  originais_primeiro_erro: primeiroErroUpload,
  documentos_com_classificacao: classificacoes.length,
  custo_total_usd: arred(total),
  custo_extracao_usd: arred(extracao),
  custo_classificacao_usd: arred(classificacao),
  custo_estimado_usd: estimado,
  tokens: { entrada: entrada, saida: saida, cache: cache },
  // Tokens de SAÍDA POR LINHA extraída — o número que recalibra o estimador, e o
  // que estava errado por 45%: o repositório supunha 35 e a fatura do dono disse
  // 64. Ele é o insumo da próxima calibração, e por isso sai medido, não suposto.
  tokens_saida_por_linha: linhas > 0 ? Number((saida / linhas).toFixed(1)) : null,
  linhas_extraidas: linhas,
  // Cobertura: quantas linhas o documento TINHA (medidas no texto do PDF, sem
  // IA) contra quantas chegaram. E' a resposta para "o custo caiu porque ficou
  // eficiente ou porque deixou de extrair?" — a pergunta que custou uma rodada.
  // Na unidade de CONTAS dos dois lados: contas distintas gravadas contra linhas
  // de conta do texto. \`linhas_extraidas\` continua sendo pares (conta x coluna),
  // que e' o que o banco guarda -- as duas coisas sao uteis e nao se misturam.
  contas_nos_documentos: celulas,
  contas_extraidas: contas,
  cobertura_do_lote: celulas > 0 ? Number((contas / celulas).toFixed(3)) : null,
  documentos_fatiados: fatiados,
  documentos_com_falha: comFalha,
  documentos_sem_medicao: semMedicao,
} }];
`.trim();

// --- Code (ALL ITEMS — fan-out): um item por arquivo enviado no Form ---
// Binário vem do FORM (o Postgres anterior não o repassa). Chave normalizada
// para 'data' (o Upload Storage usa esse nome fixo).
const CODE_LISTAR = `
${FONTE_BYTES_BINARIO}
${FONTE_TAMANHO_POR_ARQUIVO}
const caso_id = $('Upsert Caso (Postgres)').first().json.caso_id;
// O LIMIAR DO DIAL VIAJA COM O ITEM, como o caso_id. Nulo quando o banco não tem
// a linha do dial — e null cai na queda do classificador, nunca em zero (limiar
// zero faria todo documento passar sem a IA ler nenhum).
const limiar_classificacao = $('Upsert Caso (Postgres)').first().json.limiar_classificacao;
const form = $('Intake (Form)').first();
const bin = form.binary || {};
const out = [];
for (const key of Object.keys(bin)) {
  // O TAMANHO VIAJA COM O ITEM. É o insumo do orçamento: sem ele o lote é
  // estimado por um número plano que já recusou um lote de US$ 1,41 dizendo
  // US$ 7,65. \`null\` quando o metadado não permite medir — e null cai no
  // plano lá na frente, nunca em zero.
  out.push({ json: { caso_id, limiar_classificacao, nome_original: bin[key].fileName || key, binary_key: 'data', bytes: bytesDoBinario(bin[key]) }, binary: { data: bin[key] } });
}
if (out.length === 0) {
  throw new Error('Nenhum arquivo recebido do formulario (binario vazio). Confira o campo "Arquivos" do Form.');
}
// O TETO DE TAMANHO POR ARQUIVO, o primeiro guarda do lote e o unico que roda
// ANTES de getBinaryDataBuffer (que o Preparar Conteudo chama em todo
// arquivo). Medido 13/10/2026: a memoria do n8n sobe ~50x o tamanho do arquivo
// (29 MB -> 2,0 GB, e o pod tem 2 GB; 355 MB derruba a instancia inteira). O
// Orcamento do Lote nao serve para isto: ele roda DEPOIS do preparo, quando
// o estrago ja foi feito. A recusa entra pelo MESMO caminho da do orcamento
// (Tamanho cabe? -> Registrar Recusa -> Abortar Lote), que le
// orcamento_mensagem; por isso o campo tem esse nome aqui.
const tam = vereditoDeTamanhoPorArquivo({ arquivos: out.map((o) => ({ nome: o.json.nome_original, bytes: o.json.bytes })), teto: TETO_BYTES_POR_ARQUIVO });
// Recusado, o lote vira UM item, como a saida do Orcamento do Lote: com um item
// por arquivo, o Registrar Recusa gravaria a mesma falha N vezes.
if (!tam.cabe) return [{ json: { caso_id, tamanho_cabe: false, orcamento_mensagem: tam.mensagem } }];
return out.map((o) => ({ json: { ...o.json, tamanho_cabe: true }, binary: o.binary }));
`.trim();

// --- Code (EACH ITEM): classificação por nome = lib/classifier.mjs, embutida ---
// Preserva o binário (Preparar Conteudo e Upload precisam dele adiante).
//
// A COMPOSIÇÃO TAMBÉM VEM DA LIB, não só as peças. Até 24/09/2026 este nó
// embutia `parseEntidade` por `toString()` mas montava a classificação com uma
// cópia à mão de `normalize`/`parsePeriodo`/`parseTipo` e da conta de
// confiança — e a cópia perdeu a guarda `entidade = tipo ? parseEntidade(...) :
// null` de `classifyByFilename`. Medido executando o jsCode commitado:
// `ANEXO IV - planilha final REV3.pdf` gravava a entidade "Iv Rev3" (a lib:
// null). O espelho-inline não via porque confere função por função, e as peças
// batiam; o defeito estava na montagem. Agora o nó chama a MESMA
// `classifyByFilename`, e o que sobra aqui é só o mapeamento para os campos
// que o resto do workflow lê.
const FONTE_CLASSIFICADOR = [
  `const THRESHOLD_AUTO=${JSON.stringify(THRESHOLD_AUTO)};`,
  `const normalize = ${normalize.toString()};`,
  `const periodoAcumuladoNoAno = ${periodoAcumuladoNoAno.toString()};`,
  `const periodoDeIntervaloDeAnos = ${periodoDeIntervaloDeAnos.toString()};`,
  `const parsePeriodo = ${parsePeriodo.toString()};`,
  `const parseTipo = ${parseTipo.toString()};`,
  `const parseAssinado = ${parseAssinado.toString()};`,
  FONTE_PARSE_ENTIDADE,
  `const classifyByFilename = ${classifyByFilename.toString()};`,
].join('\n');
const CODE_CLASSIFICAR = `
const ALIASES=${ALIASES_JSON};
${FONTE_CLASSIFICADOR}
const item=$input.item.json;
// O limiar do dial viaja no item; a queda (so numero finito em (0,1]) e a de
// classifyByFilename, a mesma da lib -- limiar zero faria CADA documento passar
// sem a IA ler nenhum.
// SEM CRASE NESTE BLOCO: ele mora dentro de um template literal, e crase aqui
// quebra o jsCode -- ja aconteceu duas vezes (memoria backtick-quebra-jscode).
const r=classifyByFilename(item.nome_original, item.limiar_classificacao);
return {json:{...item, tipo_taxonomia:r.tipo_taxonomia, periodo_tipo:r.periodo?r.periodo.tipo:null, periodo_ref:r.periodo?r.periodo.referencia:null, assinado:r.assinado, entidade:r.entidade, confianca:r.confianca, fonte:r.fonte, precisa_fallback_ia:r.precisa_fallback_ia, limiar_aplicado:r.limiar_aplicado}, binary: $input.item.binary};
`.trim();

// --- Code (EACH ITEM): prepara a parte de CONTEUDO (para todos os docs) ---
// pdf/imagem→conteúdo real (parteDeArquivo); csv/xlsx/xls/xml→PLACEHOLDER que
// o roteador por formato substitui adiante (ver `Roteador de Formato` e
// `Recompor Conteudo Extraido`, logo depois de `Preparar Conteudo` no grafo).
// Preserva o binário (o Upload Storage roda como ramo a partir deste node).
const CODE_PREPARAR_CONTEUDO = `
${FONTE_SHA256}
${FONTE_PROVEDOR}
${FONTE_FORMATO}
const item=$input.item.json;
const binMeta=($input.item.binary||{})['data']||{};
const mt=(binMeta.mimeType||'').toLowerCase();
// NUNCA ler binMeta.data direto: se o N8N estiver em modo de binario "filesystem"
// (ou S3), esse campo NAO e' a base64 -- e' so' uma referencia interna (ex.:
// "filesystem-v2"), e a IA acaba recebendo um PDF invalido sem avisar (achado
// testando com documento real: a OpenAI so' "leu" o nome do arquivo, porque o
// file_data enviado era lixo). O helper resolve os dois modos corretamente.
// No runtime de Task Runner (padrao a partir do N8N 1.x/2.x self-hosted) o
// global $helpers NAO existe -- e' this.helpers (doc oficial n8n, cookbook
// "Get the binary data buffer").
// BUG REAL (achado testando com 2 arquivos no mesmo lote, 2026-07-22): o
// indice NAO e' sempre 0. Mesmo em each-item mode, getBinaryDataBuffer
// resolve o buffer pelo indice do item DENTRO DO LOTE inteiro do node (e' a
// forma como a referencia interna de binario vira bytes de verdade) -- nao
// pelo item que o closure do JS acha que esta processando. Com 0 fixo, todo
// item != 0 lia o BINARIO DO ITEM 0 (mimeType/nome do proprio item batiam,
// mas o CONTEUDO enviado pra IA era de outro arquivo) -- so' nao aparecia
// com upload de 1 arquivo por vez, onde o unico item e' sempre indice 0. Usa
// $itemIndex (global do N8N em each-item mode: indice do item corrente no
// lote) em vez do literal 0.
const buf=await this.helpers.getBinaryDataBuffer($itemIndex,'data');
const b64=buf.toString('base64');
// A FORMA DA PARTE E' DO PROVEDOR, e por isso ela sai de \`parteDeArquivo\`, a
// mesma funcao que a lib usa -- nao de tres literais escritos aqui. Eram eles
// que faziam a troca de provedor ser "achar cada lugar": um PDF montado na forma
// da OpenAI e' 400 no Google, e o 400 chega como falha da chamada, sem dizer que
// o defeito estava no PREPARO.
//
// CSV/XLSX/XLS/XML: o que entra aqui e' so' PLACEHOLDER, por desenho -- quem
// decide o conteudo de verdade e' o extrator NATIVO do formato certo (\`Extrair
// CSV\`/\`Extrair XLSX\`/\`Extrair XLS\`/\`Extrair XML\`), que o \`Roteador de
// Formato\` alcanca logo depois deste no', e o \`Recompor Conteudo Extraido\`
// escreve por cima (ver o comentario daquele no' para o mecanismo). O aviso
// aqui e' a REGRA 1 do CLAUDE.md (nunca apresentar ausencia como dado): por
// PADRAO este documento NAO tem conteudo extraido, e so' deixa de ser pendencia
// se o extrator confirmar sucesso mais adiante. Se o extrator falhar (arquivo
// corrompido, por exemplo), o \`onError\` dele devolve ESTE MESMO item sem
// tocar -- e o aviso abaixo e' exatamente o que sobrevive.
// O FORMATO SAI DOS BYTES, NUNCA DO MIMETYPE DECLARADO -- e esta linha e' a
// correcao do defeito que custou os 60 documentos da AMO em 12/09/2026. Ate'
// aqui a decisao saia de \`content_mime\`, que vem da EXTENSAO que o upload
// declarou; o dono converteu planilhas de PDF para \`.txt\`, os 60 chegaram como
// \`text/plain\`, o padrao \`csv\` casou, e os 60 foram para o \`Extract From File\`
// em modo CSV -- que VALIDA o mimeType do binario e rejeita \`text/plain\`. 60 de
// 60 falharam e a mensagem de erro foi mandada a' IA no lugar do balanco.
// \`detectarFormato\` le a assinatura dos bytes (ver lib/formato.mjs).
const det=detectarFormato(buf,{mimeDeclarado:mt,nome:item.nome_original||''});
const formato=det.formato;
let part; let aviso=null;
if(formato==='pdf'||formato==='imagem') part=parteDeArquivo(PROVEDOR,{mimeType:mt,base64:b64,filename:item.nome_original||'documento.pdf'});
// TEXTO E XML SAO LIDOS AQUI, e nao por no' nativo. O buffer ja' esta na mao --
// mandar o arquivo a um \`Extract From File\` para receber de volta o texto que
// estes bytes JA SAO acrescenta um modo de falha (o no' nativo recusa mimetypes
// que este pipeline aceita) sem acrescentar capacidade nenhuma. Era assim ate'
// 11/09 e funcionava; o roteamento por formato trocou por um no' nativo e foi
// exatamente essa troca que quebrou a AMO. \`parseCsv\` continua existindo para
// quando o texto for DELIMITADO -- so' que agora quem decide isso e'
// \`formaDoTexto\`, medindo consistencia de separador, em vez da extensao.
else if(formato==='texto'||formato==='xml'){
  const txt=buf.toString('utf-8');
  if(txt.trim()===''){
    part=parteDeTexto(PROVEDOR,'(arquivo de texto vazio)');
    aviso='O arquivo chegou VAZIO (zero bytes de texto): NENHUM dado deste documento chegou a extracao.';
  } else {
    part=parteDeTexto(PROVEDOR,txt);
  }
}
else if(formato==='xlsx'){part=parteDeTexto(PROVEDOR,'(extracao de XLSX pendente do no nativo Extrair XLSX)');aviso='Arquivo .xlsx ainda nao foi extraido pelo no nativo (Extrair XLSX). Se este aviso sobreviver ao Recompor Conteudo Extraido, a extracao FALHOU e nenhum dado deste documento chegou ao banco.';}
else if(formato==='xls'){part=parteDeTexto(PROVEDOR,'(extracao de XLS pendente do no nativo Extrair XLS)');aviso='Arquivo .xls ainda nao foi extraido pelo no nativo (Extrair XLS). Se este aviso sobreviver ao Recompor Conteudo Extraido, a extracao FALHOU e nenhum dado deste documento chegou ao banco.';}
// NAO SUPORTADO diz agora O QUE O ARQUIVO E' (medido), nao so' o mimetype que
// ele alegou ser. \`det.detalhe\` e' a diferenca entre "formato nao suportado
// (application/octet-stream)" -- que nao ajuda ninguem -- e "container ZIP do
// tipo docx", que diz ao analista o que reenviar.
else {part=parteDeTexto(PROVEDOR,'(conteudo nao suportado: '+det.detalhe+')');aviso='Formato nao suportado pelo preparo de conteudo: '+det.detalhe+'. NENHUM dado deste documento chegou a extracao.';}
// HASH DO CONTEUDO -- a idempotencia da 0026 dependia disto e nunca recebeu nada.
// A 0026 existe para reenvio do MESMO arquivo virar uma documento_versao nova sob
// o MESMO documento, em vez de documento novo. Como o pipeline mandava null no
// 12o elemento do queryReplacement de Registrar Documento, a condicao
// "p_hash is not null" nunca era verdade: todo reenvio duplicava o documento,
// inflava a completude e duplicava colunas no export -- o "15 colunas para 5
// empresas" do teste v27. O reextracao.test.sql provava a FUNCAO passando o hash
// a mao, e e' por isso que o gap ficou invisivel para a suite.
//
// Calculado AQUI porque este e' o unico no' que tem os bytes de verdade (o buffer
// acima, resolvido pelo helper).
//
// A primeira versao usava crypto.subtle e se ABSTINHA (hash null) se ele nao
// existisse. O dono conferiu a saida deste no' no n8n dele e o campo veio NULL:
// o Code node nao expoe crypto. A abstencao funcionou como projetada -- nao
// inventou hash fraco -- mas deixava a idempotencia da 0026 adormecida na
// pratica. Agora o SHA-256 vem de sha256Hex (JS puro, lib/hash.mjs), que nao
// depende de nada do ambiente; o caminho nativo fica so' como atalho de
// velocidade quando existe. MESMO algoritmo nos dois: nada de hash mais fraco,
// porque colisao aqui FUNDIRIA documentos diferentes -- "o erro mais caro
// possivel", nas palavras do cabecalho da 0026.
let hash=null;
try{
  if(typeof crypto!=='undefined'&&crypto&&crypto.subtle){
    const d=await crypto.subtle.digest('SHA-256',buf);
    hash=Array.from(new Uint8Array(d)).map(x=>x.toString(16).padStart(2,'0')).join('');
  }else{
    hash=sha256Hex(buf);
  }
}catch(e){
  // Ultimo recurso: se ate' o caminho nativo falhar (por qualquer motivo do
  // sandbox), tenta o JS puro antes de desistir. So' devolve null se os DOIS
  // falharem -- ai' sim nao saber e' melhor que errar.
  try{hash=sha256Hex(buf);}catch(e2){hash=null;}
}
// O binario segue: quem precisa dele depois daqui e' o \`Upload Storage\` (ramo
// lateral) e o \`Extrair Texto\`, que le a camada de texto do PDF. Da\u00ed para a
// frente ninguem mais precisa -- o \`content_part\` ja' carrega o arquivo em
// base64 DENTRO do json, e e' ele que vai para a OpenAI.
// QUANTAS ABAS O XLSX TEM, medido nos bytes (lib/formato.mjs, abasDoXlsx). O
// extrator nativo le UMA aba so'; o Recompor usa este numero para nao deixar o
// resto do arquivo sumir sem pendencia. null fora de xlsx: ausencia, nao zero.
let abasXlsx=null;
if(formato==='xlsx'){ try{ abasXlsx=abasDoXlsx(buf); }catch(e){ abasXlsx=null; } }
// A CHAVE DO ORIGINAL NO STORAGE, calculada UMA vez e aqui, onde o hash nasce. O
// \`Upload Storage\` (URL) e o \`Registrar Documento\` (arquivo_ref) leem este MESMO
// campo: duas contas para a mesma chave divergem sem erro nenhum, e o resultado e'
// arquivo_ref apontando para objeto que nao existe (o defeito de julho a outubro/2026,
// com o bucket em ZERO objetos). Ver chaveDoOriginal em lib/hash.mjs.
const arquivo_ref=chaveDoOriginal(item.caso_id,hash,item.nome_original);
return {json:{...item, content_part: part, content_mime: mt, hash, arquivo_ref, aviso_conteudo: aviso, abas_xlsx: abasXlsx,
  // O QUE FOI MEDIDO viaja com o item: o roteador decide por
  // \`formato_detectado\`, e \`formato_confiavel\`/\`formato_evidencia\` deixam
  // quem le' distinguir medicao de suposicao (regra 1 do CLAUDE.md aplicada
  // ao proprio detector -- um palpite apresentado como medicao e' ausencia
  // apresentada como dado).
  formato_detectado: formato, formato_evidencia: det.evidencia,
  formato_confiavel: det.confiavel, formato_detalhe: det.detalhe,
  formato_forma_texto: det.texto ? det.texto.forma : null,
}, binary: $input.item.binary};
`.trim();

// --- Code (ALL ITEMS): AGRUPA as linhas de UMA planilha ANTES do Merge ---------
//
// POR QUE ESTE NÓ EXISTE (17/09/2026, produção). O `Extract From File` de XLSX/XLS
// emite UMA LINHA POR ITEM, e o Merge (modo append, n8n-nodes-base Merge/v3
// actions/mode/append.js:17) junta com `returnData.push.apply(returnData, itens)`.
// `push.apply` passa cada item como ARGUMENTO, e acima de ~120 mil argumentos a
// pilha estoura: "Maximum call stack size exceeded" em `Juntar Extracao de
// Conteudo`. Três execuções (7883, 7886 e a das 00:16) morreram ali com as CP/CR
// "liquidadas" de 1 a 5,7 MB — dezenas de milhares de linhas —, e essas linhas
// eram JOGADAS FORA logo depois: `spreadsheetToText` corta em
// MAX_LINHAS_PLANILHA (2000). Planilha grande de mandato real NUNCA entrava.
//
// O QUE ELE FAZ: um item por DOCUMENTO (mesma chave do `Recompor Conteudo
// Extraido`: o hash do contexto de `Preparar Conteudo`), com só as primeiras
// MAX_LINHAS_PLANILHA linhas e os TOTAIS medidos sobre todas (nº de linhas, união
// de colunas). Os totais existem para o aviso de truncamento continuar dizendo o
// número verdadeiro — sem eles a planilha de 150.000 linhas chegaria ao Recompor
// como uma de 2.000 e o corte sumiria (regra 1: ausência apresentada como dado).
// Sem spread nem `push.apply` de array grande em lugar nenhum: só laço.
//
// O QUE PASSA INTACTO: item de erro do extrator (`{error}`), item que já traz
// `caso_id` e item sem rastro (itemMatching falhou) — com `pairedItem` do próprio
// índice, como o Recompor faz. NUNCA agrupa às cegas.
//
// ORIGEM POR LINHA, SEM `itemMatching` POR LINHA (18/09/2026, revisão independente).
// `$input.all()[i].pairedItem` NÃO serve: o motor REESCREVE o pairedItem de toda
// entrada para `{item: itemIndex, input}` antes de o nó rodar (n8n-core 2.16.1,
// `execution-engine/workflow-execute.js:790-812`), então ali `pi.item === i` sempre e
// um cache por origem nunca acerta. O que sobrevive é o RUNDATA do extrator, que
// guarda a saída como o nó a emitiu: `fromFile.operation.js:191-206` (n8n-nodes-base
// 2.15.1, SpreadsheetFile/v2) carimba `pairedItem: {item: <índice no input do
// extrator>}` em cada linha, e é esse campo que `getPairedItem` de
// `n8n-workflow/workflow-data-proxy.js:784-830` lê (`outputData[pairedItem.item]
// .pairedItem`) para subir a cadeia do `itemMatching`. `$('<extrator>').all()` devolve
// esse rundata (`workflow-data-proxy.js` get 'all' -> getNodeExecutionData). Linha i
// da entrada deste nó = linha i do extrator (conexão direta, mesma ordem), e o código
// confere o tamanho antes de confiar. Cada origem resolve o contexto UMA vez
// (`itemMatching` da primeira linha dela); as demais reusam.
// Sem origem (rundata sem pairedItem, p.ex. `binaryMode` combinado, que devolve só o
// json; tamanho diferente; `$()` que lança) cai em `itemMatching(i)` POR LINHA: correto,
// só mais lento. TEMPO MEDIDO LOCAL (Node, 150.000 linhas, 2 documentos, 2000 linhas
// mantidas; `itemMatching` replicando o algoritmo de getPairedItem com 3 saltos, não o
// n8n inteiro): COM origem 8-15 ms (2 resoluções), SEM origem 158-245 ms (150.000
// resoluções). Com `itemMatching` O(1) de mock as duas dão ~15-35 ms, então o ganho
// real depende do custo da chamada no motor -- por isso o número acima e não esse.
// Nenhum dos dois chega perto de um teto de task runner; o que não se mediu é a cópia
// de `$('<extrator>').all()` de 150 mil itens dentro do runner.
//
// ⚠️ NÃO CONFIRMADO CONTRA O N8N DO DONO (mesma categoria do Recompor): (a) que o
// item agrupado, com `pairedItem: {item: primeiro}`, encadeia até `Preparar
// Conteudo` através do Merge de 4 entradas quando o `Recompor` chama
// `itemMatching(i)` — na simulação do repositório encadeia, na instância real
// ninguém viu; (b) que o `$('Extrair ...').all()` do TASK RUNNER traz `pairedItem`
// (o fonte do runner não está no repositório; o motor e o nó, sim, como citado
// acima) -- se não trouxer, o fallback por linha entra sozinho; (c) o custo real de
// `itemMatching` por linha em 100 mil+ linhas contra o teto do task runner. Conferir
// depois de republicar: subir 2+ planilhas grandes no MESMO lote e checar que cada
// uma virou o SEU documento, com as SUAS linhas e o aviso "N de TOTAL linhas não
// foram enviadas", e o tempo do nó na execução.
const codeAgruparPlanilha = (extrator) => `
${FONTE_SPREADSHEET}
const entradas=$input.all();
const passam=[];
const grupos=new Map();
const ctxPorOrigem=new Map();
let extr=null;
try{ extr=$(${JSON.stringify(extrator)}).all(); }catch(e){ extr=null; }
if(!Array.isArray(extr)||extr.length!==entradas.length) extr=null;
for(let i=0;i<entradas.length;i+=1){
  const raw=entradas[i].json||{};
  if('caso_id' in raw||('error' in raw)){ passam.push({json:raw, pairedItem:{item:i}}); continue; }
  // origem = indice no INPUT do extrator, lido do rundata dele (nao de $input, que o
  // motor reescreve). Linhas da mesma origem tem o mesmo contexto.
  const pi=extr?extr[i].pairedItem:undefined;
  const origem=(pi!==undefined&&pi!==null&&typeof pi==='object'&&!Array.isArray(pi)&&Number.isInteger(pi.item))?pi.item
    :(Number.isInteger(pi)?pi:null);
  let ctx;
  if(origem!==null&&ctxPorOrigem.has(origem)) ctx=ctxPorOrigem.get(origem);
  else{
    ctx=null;
    try{ ctx=$('Preparar Conteudo').itemMatching(i).json||null; }catch(e){ ctx=null; }
    if(origem!==null) ctxPorOrigem.set(origem,ctx);
  }
  if(!ctx){ passam.push({json:raw, pairedItem:{item:i}}); continue; }
  const chave=ctx.hash||ctx.nome_original||('__sem_chave_'+i);
  if(!grupos.has(chave)) grupos.set(chave,{ctx,linhas:[],colunas:new Set(),total:0,primeiro:i});
  const g=grupos.get(chave);
  const lote=Array.isArray(raw.data)?raw.data:[raw];
  for(let k=0;k<lote.length;k+=1){
    const linha=lote[k];
    g.total+=1;
    if(linha&&typeof linha==='object'){ const ks=Object.keys(linha); for(let c=0;c<ks.length;c+=1) g.colunas.add(ks[c]); }
    if(g.linhas.length<MAX_LINHAS_PLANILHA) g.linhas.push(linha);
  }
}
const agrupados=[];
for(const g of grupos.values()){
  agrupados.push({json:{planilha_agrupada:true, linhas:g.linhas, total_linhas:g.total, colunas:Array.from(g.colunas)}, pairedItem:{item:g.primeiro}});
}
return passam.concat(agrupados);
`.trim();

// --- Code (ALL ITEMS): RECOMPÕE o que os 5 extratores por formato devolveram --
//
// POR QUE ESTE NÓ EXISTE. `Preparar Conteudo` classifica o mimetype e manda o
// item para o `Roteador de Formato` (Switch nativo), que entrega CADA
// documento a EXATAMENTE UM extrator — nunca aos cinco (essa era a auditoria
// do print do dono: 5 nós "Extract from..." pendurados em PARALELO no MESMO
// `Preparar Conteudo`, todos recebendo o MESMO item, sem roteamento nenhum —
// fan-out cego, `Medir Documento` processando 5 itens por documento, 1 certo e
// 4 lixo). Com o Switch, cada documento chega aqui vindo de UM ramo só; este
// nó decide o que fazer com o que aquele ramo devolveu e converge tudo em UM
// item por documento outra vez, antes de `Medir Documento`.
//
// TRÊS FORMAS DE CHEGAR AQUI, e as três são tratadas:
//   1. imagem / formato sem extrator ('outros', ainda "conteudo nao
//      suportado") / QUALQUER extrator que FALHOU: o item chega EXATAMENTE
//      como saiu de \`Preparar Conteudo\` — \`onError: continueRegularOutput\`
//      no extrator devolve o item de ENTRADA sem tocar quando ele lança, e
//      \`caso_id\` só sobrevive nesse caso (o \`Extract From File\` SUBSTITUI o
//      item quando funciona — nunca devolve \`caso_id\`). Nada a reconstruir:
//      o \`content_part\`/\`aviso_conteudo\` que sobrevivem já são os corretos
//      (o real, para imagem; o placeholder com o aviso, para o resto).
//   2. PDF: \`Extrair Texto\` (Camada 1, já existia) devolve \`{text,numpages}\`
//      — sem \`content_part\`. Não se reconstrói nada aqui: \`Medir Documento\`
//      já lê \`text\`/\`numpages\` DIRETO do nó anterior, mecanismo que este nó
//      não pode atrapalhar.
//   3. CSV/XLSX/XLS/XML: o extrator SUBSTITUIU o item pelo que extraiu. Para
//      texto (XML), é um item só; para planilha, o comportamento documentado
//      do \`Extract From File\` é UMA LINHA POR ITEM — o MESMO tipo de fan-out
//      do print do dono, só que nativo do n8n em vez de um engano de quem
//      pendurou o nó. Sem reagrupar, \`Medir Documento\` voltaria a processar
//      N itens por documento.
//
// COMO SE SABE DE QUAL DOCUMENTO CADA LINHA VEIO, já que o \`Extract From
// File\` não repassa \`caso_id\`: por \`itemMatching\`, a API do n8n para
// exatamente isto — reatar um item pós-fan-out ao item de entrada que o
// gerou. \`$('Nó').item\` (usado no resto deste workflow) NÃO serve aqui: ele
// resolve por um pareamento AMBÍGUO depois de convergência (foi o que perdeu
// 19 de 35 documentos no "Teste V45", com \`Juntar Ramos\`, e por isso
// \`Recompor Contexto\` reconcilia por ÍNDICE contra \`.all()\` em vez de
// \`.item\`); \`itemMatching(i)\` NOMEIA o índice de entrada, sem essa
// ambiguidade, e é o que a documentação do n8n recomenda para 1-para-N.
//
// ⚠️ NÃO CONFIRMADO CONTRA O N8N DO DONO — mesma categoria do comentário de
// \`retryOnFail\` mais abaixo neste arquivo: o comportamento em 1-linha-por-item
// do \`Extract From File\` e a propagação de \`itemMatching\` através do Merge de
// 7 ramos são o que a documentação do n8n descreve, não o que foi visto rodar
// aqui. NUNCA agrupa às cegas quando o pareamento falha (juntaria documentos
// DIFERENTES numa linha só — o erro mais caro possível nesta base): uma linha
// sem rastro vira um item isolado, com aviso próprio, nunca lixo dentro do
// grupo de outro documento. O que conferir depois de republicar: subir 2+
// planilhas no MESMO lote e checar no banco que cada uma virou o SEU PRÓPRIO
// documento, com as próprias linhas — não uma mistura.
const CODE_RECOMPOR_EXTRACAO = `
${FONTE_PROVEDOR}
${FONTE_SPREADSHEET}
${FONTE_COBERTURA}
const entradas=$input.all();
const completos=[];
const porDocumento=new Map();
for(let i=0;i<entradas.length;i+=1){
  const raw=entradas[i].json||{};
  // Caso 1: ja chegou pronto (imagem/outros/qualquer extrator que falhou).
  if('caso_id' in raw){ completos.push(entradas[i]); continue; }
  let ctx=null;
  try{ ctx=$('Preparar Conteudo').itemMatching(i).json||null; }catch(e){ ctx=null; }
  if(!ctx){
    // SEM RASTRO -- nunca agrupa as cegas. Isola como item proprio (degrada,
    // nao corrompe) e declara o motivo, no espirito do 'recompor_motivo' que
    // 'Recompor Contexto' ja usa para o mesmo tipo de falha declarada.
    completos.push({json:{...raw, aviso_conteudo:'Recompor Conteudo Extraido: nao foi possivel religar esta linha ao documento de origem (itemMatching falhou). Conteudo NAO chegou a extracao.'}, pairedItem:{item:i}});
    continue;
  }
  const formato=ctx.formato_detectado;
  // ==========================================================================
  // Caso 2: PDF -- TEXTO quando ele existe, IMAGEM (OCR) quando nao existe.
  // ==========================================================================
  //
  // O QUE MUDOU EM 12/09/2026, e e' dinheiro. Ate' aqui CADA PDF ia a' IA como
  // ARQUIVO em base64, que o provedor cobra como IMAGEM (~1.000 tokens por
  // pagina). E o \`Extrair Texto\` -- que roda na propria instancia, de graca --
  // ja' vinha lendo a camada de texto do mesmo PDF, so' que o texto era usado
  // APENAS para MEDIR cobertura e depois jogado fora. O conteudo estava na mao
  // e a chamada pagava imagem por ele.
  //
  // Agora o texto VIRA o conteudo quando ele existe de verdade. Um balanco de 2
  // paginas com camada de texto deixa de custar ~2.000 tokens de entrada e passa
  // a custar os caracteres que ele tem (~440 num documento de 1,7 KB).
  //
  // E O ESCANEADO CONTINUA INDO COMO IMAGEM, que e' a metade que nao se pode
  // perder: PDF sem camada de texto devolve vazio (ou um punhado de lixo), e
  // mandar ISSO no lugar do documento seria a AMO de novo -- ausencia
  // apresentada como dado. \`camadaDeTextoDoPdf\` decide por DOIS criterios
  // medidos (densidade por pagina e linhas COM NUMERO); ver lib/cobertura.mjs
  // para por que o segundo e' o que importa numa demonstracao financeira.
  //
  // O VEREDITO VIAJA COM O ITEM (\`leitura_pdf\`/\`leitura_pdf_motivo\`), e nao e'
  // enfeite: quem olhar um documento sem linhas precisa distinguir "foi lido por
  // OCR e o modelo nao achou nada" de "foi lido como texto e o texto nao tinha
  // numeros". Sem isso as duas falhas tem a mesma aparencia.
  if(formato==='pdf'){
    const textoPdf=typeof raw.text==='string'?raw.text:'';
    const paginas=Number.isFinite(Number(raw.numpages))?Number(raw.numpages)
      :(Number.isFinite(Number(raw.numPages))?Number(raw.numPages):null);
    const v=camadaDeTextoDoPdf(textoPdf,{paginas});
    if(v.usarTexto){
      // \`content_part\` ESCRITO aqui e' o que faz \`Medir Documento\` usar o texto
      // em vez do base64 de \`Preparar Conteudo\` -- ele so' troca quando a chave
      // EXISTE no item do extrator (ver o comentario daquele no').
      completos.push({json:{...raw,
        content_part: parteDeTexto(PROVEDOR,textoPdf),
        leitura_pdf:'texto', leitura_pdf_motivo:v.motivo, leitura_pdf_explicacao:v.explicacao,
        caracteres_do_texto:v.caracteres,
      }, pairedItem:{item:i}});
    } else {
      // SEM \`content_part\`: o item segue sem a chave e \`Medir Documento\` mantem
      // o base64 que \`Preparar Conteudo\` montou -- o PDF vai a' visao do modelo.
      completos.push({json:{...raw,
        leitura_pdf:'ocr', leitura_pdf_motivo:v.motivo, leitura_pdf_explicacao:v.explicacao,
        caracteres_do_texto:v.caracteres,
      }, pairedItem:{item:i}});
    }
    continue;
  }
  // ==========================================================================
  // Caso 3: O EXTRATOR FALHOU -- e este ramo e' a correcao do defeito que
  // apagou 60 documentos da AMO em 12/09/2026.
  // ==========================================================================
  //
  // O QUE ESTE NO' ACREDITAVA, e estava escrito num comentario logo acima:
  // "\`onError: continueRegularOutput\` devolve o item de ENTRADA sem tocar, e
  // \`caso_id\` so' sobrevive nesse caso". E FALSO. Quando o \`Extract From File\`
  // lanca por item, o n8n NAO repassa o item de entrada: ele emite um item NOVO
  // com a forma \`{error: "<mensagem>"}\` -- sem \`caso_id\`, sem \`content_part\`,
  // sem \`aviso_conteudo\`. Medido na instancia do dono: 60 itens, todos
  // \`{error: "The file selected in 'Input Binary Field' is not in csv format"}\`.
  //
  // O ESTRAGO, e ele e' de uma ordem acima de "o documento falhou". Sem este
  // ramo, o item de erro escapava do teste \`'caso_id' in raw\` (falso), caia no
  // Caso 3b, e a MENSAGEM DE ERRO era empurrada como LINHA DE PLANILHA:
  // \`spreadsheetToText([{error:"..."}])\` devolve "error\\nThe file selected...",
  // que virava \`content_part\` (mandado a' IA no lugar do balanco) E \`text\`
  // (lido pela regua de cobertura como se fosse o documento). Pior: o
  // \`aviso_conteudo\` que \`Preparar Conteudo\` tinha aberto -- "a extracao FALHOU
  // e nenhum dado deste documento chegou ao banco" -- era SOBRESCRITO por
  // \`avisoTruncamentoPlanilha([1 linha])\`, que devolve null. A falha virava
  // sucesso fingido, e o modelo, recebendo a mensagem tecnica, respondia que o
  // ARQUIVO estava ilegivel. O banco gravou 60 documentos como \`ilegivel\` com
  // 84-98% de confianca, sobre arquivos integros. E a regra 1 do CLAUDE.md
  // ("nunca apresentar ausencia como dado") violada pelo caminho mais caro que
  // existe: a ausencia nao ficou em branco, ela ficou com a CARA de medicao.
  //
  // POR QUE O TESTE NAO PEGOU, e vale mais que a correcao: o invariante que
  // cobria este caminho INVENTOU a fixture. Ele montava o item de falha como
  // \`{...ctxCsv}\` -- COM \`caso_id\` -- e entao afirmava "extrator que falhou
  // preserva o aviso". Passava, sobre uma forma que o n8n nunca produz. E a
  // regra 4 do CLAUDE.md ("nunca inventar fixture para provar bug de producao")
  // cobrada ao contrario: a fixture inventada nao provou um bug, ela BLINDOU um.
  // O teste que substitui aquele usa a forma MEDIDA, \`{error: "..."}\`.
  if(!('caso_id' in raw) && ('error' in raw)){
    const motivo=typeof raw.error==='string'?raw.error
      :(raw.error&&(raw.error.message||raw.error.description))||'sem mensagem';
    completos.push({json:{...ctx,
      // O \`content_part\` e o aviso de \`Preparar Conteudo\` SOBREVIVEM intactos:
      // eles ja' dizem "pendente do no' nativo / a extracao FALHOU". Nada aqui
      // escreve conteudo -- nao ha conteudo.
      text: null,
      aviso_conteudo: 'A extracao NATIVA deste arquivo FALHOU no n8n ('
        + (ctx.formato_detectado||'formato nao identificado') + '): ' + motivo
        + '. NENHUM dado deste documento chegou ao banco nem ao book -- o que o'
        + ' arquivo contem NAO foi lido. Isto e uma falha do PIPELINE, nao do'
        + ' arquivo: nao registre este documento como ilegivel sem conferir.',
      extracao_falhou: true,
      extracao_falha_motivo: motivo,
    }, pairedItem:{item:i}});
    continue;
  }
  // Caso 3a: XML -- item de texto unico, nao planilha. So' chega aqui por
  // compatibilidade: desde 12/09 o XML e' lido em \`Preparar Conteudo\` e nem
  // passa por extrator. Mantido porque custa duas linhas e some sozinho.
  if(formato==='xml'){
    const texto=[raw.data,raw.text,raw.content].find((v)=>typeof v==='string'&&v.trim()!=='');
    completos.push({json:{...ctx,
      content_part: texto?parteDeTexto(PROVEDOR,texto):ctx.content_part,
      text: texto||null,
      aviso_conteudo: texto?null:ctx.aviso_conteudo,
    }, pairedItem:{item:i}});
    continue;
  }
  // Caso 3b: CSV/XLSX/XLS -- uma ou mais linhas de planilha deste documento.
  // \`hash\` (SHA-256 do arquivo, calculado em Preparar Conteudo) e' a chave:
  // unica por conteudo, e e' a MESMA que a 0026 usa para dedup -- reaproveitar
  // em vez de inventar uma chave nova.
  // A CHAVE E' O HASH, e isso foi CONFERIDO contra a doutrina do banco em vez de
  // trocado por intuicao. Uma revisao apontou que dois arquivos byte a byte
  // iguais no mesmo lote colidiriam num grupo so'. Colidem -- e e' o certo: pela
  // migration 0026 (reextracao por hash), o mesmo par caso_id+hash E' O MESMO
  // DOCUMENTO, e o reenvio vira nova versao sob o MESMO documento. Agrupar por
  // posicao criaria dois documentos que o banco depois fundiria, e a identidade
  // do sistema passaria a ter duas definicoes diferentes.
  const chave=ctx.hash||ctx.nome_original||('__sem_chave_'+i);
  if(!porDocumento.has(chave)) porDocumento.set(chave,{ctx,linhas:[],colunas:new Set(),total:0,primeiro:i});
  const grupo=porDocumento.get(chave);
  // SEM SPREAD (17/09/2026): \`push(...array)\` passa cada elemento como argumento
  // e estoura a pilha acima de ~120 mil linhas -- o mesmo defeito do Merge. O
  // caminho normal agora e' o item ja AGRUPADO por \`Agrupar Linhas\` (so' as
  // primeiras linhas + os totais medidos sobre todas); os outros dois formatos
  // continuam aceitos, so' que em laco.
  if(raw.planilha_agrupada===true){
    for(let k=0;k<raw.linhas.length;k+=1) grupo.linhas.push(raw.linhas[k]);
    grupo.total+=Number(raw.total_linhas)||raw.linhas.length;
    for(let k=0;k<raw.colunas.length;k+=1) grupo.colunas.add(raw.colunas[k]);
    continue;
  }
  // Defensivo aos DOIS formatos possiveis do extrator: um item com o array
  // inteiro sob '.data', ou uma linha por item (o comportamento documentado).
  const lote=Array.isArray(raw.data)?raw.data:[raw];
  for(let k=0;k<lote.length;k+=1){
    const linha=lote[k];
    grupo.total+=1;
    if(linha&&typeof linha==='object'){ const ks=Object.keys(linha); for(let c=0;c<ks.length;c+=1) grupo.colunas.add(ks[c]); }
    grupo.linhas.push(linha);
  }
}
const reconstruidos=[...porDocumento.values()].map(({ctx,linhas,colunas,total,primeiro})=>{
  // Os TOTAIS vem da medicao sobre a planilha inteira (nao do que sobrou depois do
  // corte): o texto e o aviso dizem o numero verdadeiro de linhas e colunas.
  const uniaoColunas=Array.from(colunas);
  const textoPlanilha=spreadsheetToText(linhas,{colunas:uniaoColunas,totalLinhas:total});
  return {pairedItem:{item:primeiro},json:{...ctx,
    content_part: parteDeTexto(PROVEDOR, textoPlanilha),
    // \`text\`: A MESMA CORRECAO DO CASO XML, e o mesmo achado (revisao
    // adversarial, 11/09) -- so' que aqui o efeito e' PIOR, porque planilha e'
    // exatamente o formato com mais linha por documento. Sem isto, um
    // \`balancete.xlsx\` de 800 linhas nunca fatiava (\`Fatiar Extracao\` cai no
    // bloco unico por falta de \`linhas_do_texto\`) E nunca acusava cobertura
    // baixa (\`avaliarCobertura\` calada por \`esperadas=null\`) -- 500 linhas
    // podiam sumir com o \`Conferir Lote\` inteiro VERDE. \`textoPlanilha\` e' o
    // MESMO texto que \`spreadsheetToText\` ja' produzia para \`content_part\`
    // (calculado uma unica vez aqui, nao duas): a regua passa a medir
    // exatamente o que foi mandado a' IA.
    text: textoPlanilha||null,
    // COMO A PLANILHA FOI LIDA, e o orcamento cobra por isto: o que vai a' IA e'
    // este TEXTO (<= 2000 linhas), nao os bytes do arquivo. Sem estas duas chaves
    // o orcamento caia no proxy por byte calibrado em PDF-imagem e recusava, para
    // sempre, o CR_Liquidado de 5,7 MB (US$ 10,81 estimados) -- o mesmo erro que
    // ja' foi corrigido para o PDF lido como texto.
    leitura_planilha:'texto',
    caracteres_do_texto:textoPlanilha.length,
    // Planilha extraida com sucesso NAO abre mais a pendencia de 'nao lida' --
    // so' abre a de TRUNCAMENTO, se a planilha estourar o teto (regra 1: so'
    // declara ausencia onde ela e' real).
    aviso_conteudo: [
      avisoTruncamentoPlanilha(linhas,{totais:{linhas:total,colunas:uniaoColunas.length}}),
      // XLSX COM MAIS DE UMA ABA: o \`Extract From File\` leu so' a primeira. O
      // que estava nas outras sumia sem pendencia -- \`Endividamento
      // Krauspenhar.xlsx\` gravou 0 linhas porque a 1a aba e' um indice e a
      // tabela esta na 2a. O numero de abas vem dos bytes (Preparar Conteudo); o
      // NOME delas nao, porque mora no workbook.xml comprimido e o no' Code nao
      // tem zip. O conteudo lido NAO e' descartado: so' deixa de ser apresentado
      // como o arquivo inteiro.
      (ctx.formato_detectado==='xlsx'&&Number.isFinite(ctx.abas_xlsx)&&ctx.abas_xlsx>1)
        ? 'O arquivo .xlsx tem '+ctx.abas_xlsx+' abas e o extrator nativo leu SO a primeira ('+total+' linha(s)); as outras '+(ctx.abas_xlsx-1)+' aba(s) NAO foram lidas e a tabela financeira pode estar em qualquer uma delas. Os nomes das abas nao estao disponiveis (ficam no workbook.xml, comprimido). Abra o arquivo e reenvie a aba certa, ou confirme que a primeira e a unica com dado.'
        : null,
    ].filter(Boolean).join(' | ')||null,
  }};
});
// O QUE ESTE NO' NAO FECHA, e fica DITO em vez de escondido: um extrator que
// devolve ZERO item (planilha vazia, CSV so' com cabecalho) faz o documento
// sumir do lote sem pendencia. A correcao obvia -- sintetizar aqui o item que
// faltou -- foi ESCRITA E DESCARTADA: o no' Medir Documento resolve o contexto
// por referencia ao Preparar Conteudo, que depende de pairedItem, e um item
// sintetico nao tem input a que se parear; pareado a qualquer indice ele
// receberia o contexto do documento ERRADO. Trocar um documento que some por um
// documento com o caso_id de outro e' piorar. Fica como lacuna declarada, a
// fechar com uma medicao na instancia real (o extrator devolve zero item ou um
// item vazio? a doc do n8n nao responde) -- ver ESTADO.md.
return [...completos, ...reconstruidos];
`.trim();

// --- Code (EACH ITEM): monta corpo da chamada de CLASSIFICAÇÃO (fallback) ---
const CODE_REQ_CLASSIF = `
${FONTE_PROVEDOR}
const item=$input.item.json;
const schema=${SCHEMA_CLASSIF};
const body=montarCorpoIA(PROVEDOR,{modelo:'${MODEL_CLASSIFICACAO}',schema,esforco:${JSON.stringify(ESFORCO_CLASSIFICACAO)},partes:[parteDeTexto(PROVEDOR,'Nome (pista fraca): '+(item.nome_original||'')), item.content_part],sistema:'Classifique o documento financeiro na taxonomia da Oria (Reestruturacao, Brasil). Periodos: 12M25=ano 2025; 1T25=1o tri/2025; L24M=ultimos 24 meses; 23,24,25=multiplos exercicios; ano isolado como 2025 tambem e valido. IMPORTANTE: sempre tente identificar o tipo mais provavel dentre os codigos conhecidos, mesmo com confianca baixa -- analise cabecalhos, rotulos de linhas, estrutura de colunas e demais pistas visuais. DESCONHECIDO e reservado somente para documentos genuinamente ilegiveis/corrompidos ou que claramente nao sao documentos financeiros. Baixa confianca nao e motivo para deixar de dar um palpite -- e motivo para registrar o palpite com confianca baixa correspondente e uma justificativa objetiva. Nunca invente valores (numeros, entidade, periodo) que nao estao no documento, mas sempre ofereca sua melhor hipotese de tipo. O campo justificativa e obrigatorio: explicacao objetiva e especifica (1-2 frases) do que voce viu (ou nao viu) no documento que sustenta a classificacao e a confianca escolhida -- evite respostas genericas como nao foi possivel determinar. CNPJ: extraia o CNPJ (14 digitos, com ou sem pontuacao) da EMPRESA DONA do documento, se aparecer no conteudo -- null se nao visivel. ATENCAO: documentos brasileiros de contabilidade costumam trazer VARIOS CNPJs na mesma pagina -- o do ESCRITORIO DE CONTABILIDADE que emitiu o relatorio (procure perto de "CRC", "Contador", rodape com responsavel tecnico), o do AUDITOR, e o da EMPRESA em si (normalmente no cabecalho, perto do nome dela). Extraia SOMENTE o da empresa dona do documento -- o mesmo criterio que ja vale para o campo entidade. Na duvida entre dois CNPJs, prefira null a arriscar o errado: um CNPJ errado funde esta empresa com OUTRA no sistema, silenciosamente.'});
return {json:{...item, ia_body: body}};
`.trim();

// --- Code (EACH ITEM): parse da classificação -----------------------------
// Contexto vem do node anterior por referência (a resposta HTTP substituiu o
// item). Remove os campos pesados (ia_body/content_part) do que segue.
// Espelha N8N/lib/merge.mjs: fica com a MAIOR confiança entre nome-do-arquivo
// e IA (não sobrescreve cegamente); entidade/assinado da IA sempre aproveitados.
// E ele passou a MEDIR o custo desta chamada (13/08/2026). Até aqui só a
// extração media o seu — a classificação era a metade da conta que ninguém
// olhava, e é exatamente a metade cujo preço acabou de mudar (gpt-4o →
// gpt-4o-mini). Sem `custo_classificacao_usd` na saída do nó, a economia
// prometida por este repositório seria verificável só na fatura da OpenAI, no
// fim do mês, misturada com todo o resto.
const CODE_PARSE_CLASSIF = `
${FONTE_DIAGNOSTICO_ERRO}
${FONTE_CUSTO_CHAMADA}
${FONTE_PROVEDOR}
${FONTE_MERGE_CLASSIF}
const src=$('Montar Req Classif').item.json;
// \`content_part\` FICA no item (antes era descartado aqui junto do ia_body).
// Motivo: o \`Montar Req Extracao\` precisa do PDF, e ele o buscava em
// \`$('Preparar Conteudo').item\` -- pareamento que atravessa a convergencia dos
// dois ramos e por isso nao e' confiavel. Dado que o item CARREGA nao depende de
// pareamento nenhum. Só o \`ia_body\` da CLASSIFICACAO sai (aquele ja' foi
// usado, e levá-lo adiante incharia cada item com o base64 duas vezes).
const {ia_body, ...item}=src;
const resp=$json;
const content=conteudoDaResposta(PROVEDOR,resp);
const fromName={tipo_taxonomia:item.tipo_taxonomia, periodo_tipo:item.periodo_tipo, periodo_ref:item.periodo_ref, assinado:item.assinado, entidade:item.entidade, confianca:item.confianca};
// Custo REAL desta chamada, pelo mesmo \`custoDaChamada\` da extracao e pelo
// modelo que ESTE no' pediu. Vai em TODOS os caminhos de saida: a chamada que
// falhou depois de consumir tokens tambem foi paga, e um custo que so' aparece
// no caminho feliz e' um custo subdeclarado.
const custo_classificacao_usd=custoDaChamada(usoDaChamada(PROVEDOR,resp), '${MODEL_CLASSIFICACAO}');
if(!content){
  // A classificação DEGRADA para o nome do arquivo quando a IA falha — e isso é
  // o certo (fail-safe). O que não pode é a justificativa dizer só "falha de
  // rede/API": no "teste v30" os 14 documentos ficaram classificados pelo nome
  // com essa frase genérica, enquanto a causa real era a OpenAI recusando TODA
  // chamada. A causa vai junto, com o mesmo diagnóstico da extração.
  const motivo=resp?.error?diagnosticarErroApi(resp.error).motivo:'A chamada a OpenAI nao retornou conteudo (falha de rede/API).';
  return {json:{...item, custo_classificacao_usd, ...mergeClassification(fromName, {tipo_taxonomia:null, confianca:0, justificativa:'Classificacao por conteudo indisponivel, valeu o nome do arquivo. '+motivo})}};
}
let p; try{p=typeof content==='string'?JSON.parse(content):content;}catch(e){
  return {json:{...item, custo_classificacao_usd, ...mergeClassification(fromName, {tipo_taxonomia:null, confianca:0, justificativa:'Resposta da OpenAI nao veio em JSON valido.'})}};
}
const fromAI={
  tipo_taxonomia:p.tipo_taxonomia==='DESCONHECIDO'?null:p.tipo_taxonomia,
  entidade:p.entidade??null,
  cnpj:p.cnpj??null,
  periodo_tipo:p.periodo_referencia?p.periodo_tipo:null,
  periodo_ref:p.periodo_referencia??null,
  assinado:p.assinado??null,
  confianca:typeof p.confianca==='number'?p.confianca:0,
  justificativa:p.justificativa||'',
};
return {json:{...item, custo_classificacao_usd, ...mergeClassification(fromName, fromAI)}};
`.trim();

// --- Code (EACH ITEM): monta corpo da chamada de DIAGNÓSTICO+EXTRAÇÃO (E2) -
// $json vem do Registrar Documento (linha {r:{documento_id, documento_versao_id}}).
// O conteúdo do arquivo volta por referência ao Preparar Conteudo. Espelha
// N8N/lib/extract.mjs: SEMPRE roda (não só no fallback de baixa confiança) —
// é a ÚNICA leitura de conteúdo garantida para todo documento, por isso
// também busca entidade e faz o diagnóstico (confere tipo/período/legibilidade).
const CODE_REQ_EXTRACAO = `
${FONTE_PROVEDOR}
const reg=$json;
const versaoId=reg.documento_versao_id||null;
// SEM VERSAO, NAO SE MONTA REQUISICAO -- e' o que impede pagar por uma extracao
// que nao tem onde ser gravada.
//
// O caminho era real e caro: com PG_RETRY (onError: continueRegularOutput), quando
// "Registrar Documento" falha o item de erro segue adiante, versaoId virava null
// SEM sinalizar nada, a extracao era EXECUTADA (dinheiro gasto) e
// fn_registrar_campos_extraidos(null, ...) retornava 0 jogando fora o
// falha_motivo antes do Sinal 3. Documento inexistente, chamada paga, zero
// pendencia -- so' o log do n8n sabia. A 0029 fecha o lado do banco (registra em
// evento_auditoria em vez de descartar); esta guarda fecha o lado do DINHEIRO.
//
// Lancar aqui e' seguro porque este no' tem onError: o item vira item de erro, o
// lote CONTINUA, e nenhum token e' cobrado (o corpo nunca e' montado). O modo
// runOnceForEachItem nao permite devolver zero itens -- por isso guarda, nao filtro.
if(!versaoId){
  throw new Error('Documento nao registrado no banco (documento_versao_id ausente): a extracao NAO foi chamada, para nao gastar credito com um documento que nao existe. Causa provavel: falha no no "Registrar Documento" -- ver o log desta execucao.');
}
// O CONTEUDO VEM DO PROPRIO ITEM. O \`Recompor Contexto\` (no' anterior) ja' juntou
// o resultado do Postgres com o contexto do preparo POR INDICE, entao aqui nao se
// pareia com no' nenhum -- era a leitura pareada do no' de preparo, feita daqui,
// que atravessava a convergencia dos dois ramos e perdeu 19 dos 35 no V45.
const prep=$json;
// SEM CONTEUDO, NAO SE CHAMA A OPENAI. Uma requisicao montada sem o documento
// volta "sem nenhuma linha" SEM erro de API -- extracao vazia que parece sucesso,
// que e' exatamente o silencio que este projeto passa o tempo fechando. Lancar
// aqui vira item de erro (onError: continue), o lote segue, e o motivo aparece.
if(!prep.content_part){
  throw new Error('Conteudo do documento indisponivel ao montar a extracao (content_part ausente): a chamada NAO foi feita, para nao pagar por uma extracao sem o arquivo. Causa provavel: o Recompor Contexto nao encontrou o item de origem -- ver o log desta execucao.');
}
const schema=${SCHEMA_EXTRACAO};
const promptSistema=${JSON.stringify(SYSTEM_PROMPT)};
const body=montarCorpoIA(PROVEDOR,{modelo:'${MODEL_EXTRACAO}',sistema:promptSistema,schema,maxTokens:${MAX_OUTPUT_TOKENS},esforco:${JSON.stringify(ESFORCO_EXTRACAO)},partes:[
  parteDeTexto(PROVEDOR,'Nome do arquivo: '+(prep.nome_original||'(sem nome)')+'. Dica de tipo (do nome, pode estar errada): '+(prep.tipo_taxonomia||'desconhecido')+'. Diagnostique e extraia as linhas financeiras.'),
  prep.content_part]});
// aviso_conteudo viaja junto: o que o preparo ja sabia estar faltando ANTES da
// chamada (planilha acima do teto, XLSX nao lido) tem de virar pendencia mesmo
// quando a extracao volta impecavel -- o pedaco que falta nunca chegou a IA.
// documento_id VIAJA COM O ITEM, e nao e' luxo: depois do fatiamento os nos
// seguintes nao conseguem mais resolver \`$('Registrar Documento').item\` -- um
// no' que muda a QUANTIDADE de itens (1 documento -> N blocos -> 1 documento)
// quebra a cadeia de pareamento do n8n, e a expressao volta \`undefined\`. Foi
// exatamente isso que derrubou a execucao 6164: "Query Parameters must be a
// string of comma-separated values" no Registrar Diagnostico e no Reconciliar.
// Dado que o item CARREGA nao depende de pareamento nenhum.
const docId=reg.documento_id||null;
// O CONTEXTO DA MEDICAO VIAJA JUNTO, e nao viajava.
//
// ACHADO NA RODADA COMPARATIVA DO CANASTRA (27/08/2026), com o Conferir Lote
// VERDE e sem erro nenhum no n8n. Este no' montava um item NOVO com cinco
// campos e descartava tudo o que o \`Medir Documento\` tinha medido. Um defeito
// de omissao, com tres sintomas silenciosos:
//
//   1. \`linhas_do_texto\` nao chegava ao \`Fatiar Extracao\`, que sem ele cai no
//      fallback de UM bloco -- o FATIAMENTO NUNCA LIGOU. O medidor previa 4
//      documentos fatiados no book; a rodada gravou \`documentos_fatiados: 0\`,
//      e o 17_Livro_Razao foi a UMA chamada em vez de quatro;
//   2. \`contas_no_documento\` nao chegava ao \`Juntar Blocos\`, e sem o esperado
//      \`avaliarCobertura\` nunca dispara: A GUARDA DE EXTRACAO INCOMPLETA ESTAVA
//      DESLIGADA. E' a regua que mede alucinacao por omissao -- a que mais
//      importa num lote de 190;
//   3. e o painel do lote gravava \`contas_nos_documentos: 0\` e
//      \`cobertura_do_lote: null\`, que foi o sintoma pelo qual isto apareceu.
//
// Nenhum dos tres da erro: um documento nao fatiado roda, uma cobertura nao
// avaliada nao acusa, e um campo nulo no painel parece "ainda nao medido". E'
// a mesma familia do defeito da v47 -- um no' lendo o que o anterior nao
// entrega --, e a guarda daquela vez so' cobria no' Postgres.
//
// \`content_part\` e \`ia_body\` ficam de fora do espalhamento de proposito: o
// primeiro e' o PDF inteiro em base64 e ja' esta' dentro do corpo montado; o
// segundo e' substituido logo abaixo.
const {content_part:_cpDescartado, ia_body:_obDescartado, ...contextoDaMedicao}=prep;
return {json:{...contextoDaMedicao, documento_id:docId, documento_versao_id:versaoId, tipo:prep.tipo_taxonomia||null, aviso_conteudo:prep.aviso_conteudo??null, ia_body:body}};
`.trim();

// --- Code (ALL ITEMS): recompõe contexto + resultado do Postgres, POR ÍNDICE --
//
// Existe porque o nó Postgres SUBSTITUI o item: depois do `Registrar Documento` o
// item é só `{r:{documento_id, documento_versao_id, ...}}`, e o `content_part`
// (o PDF) morre ali. O `Montar Req Extracao` buscava o conteúdo de volta em
// `$('Preparar Conteudo').item` — pareamento que atravessa a convergência dos
// dois ramos do `Precisa Fallback?`, e foi ele que perdeu 19 dos 35 documentos do
// "Teste V45 - Canastra" (zero linha, zero evento, zero pendência).
//
// A junção é por ÍNDICE, e isso é sólido: `Registrar Documento` roda
// `executeQuery` uma vez por item de entrada e devolve uma linha por item, na
// MESMA ordem — 1:1, inclusive quando um item falha (PG_RETRY tem
// `continueRegularOutput`, então o item de erro ocupa a posição dele). E
// `$('Juntar Ramos').all()` devolve a saída INTEIRA daquele nó, sem depender de
// `pairedItem` nenhum: é a diferença entre "me dê o item pareado com este" (que
// falhou) e "me dê a lista, eu sei minha posição nela".
//
// DIVERGÊNCIA DE CONTAGEM É FALHA DECLARADA, nunca ajuste silencioso: se as duas
// listas tiverem tamanhos diferentes, a correspondência por índice deixou de ser
// verdadeira, e continuar associaria o PDF de um documento ao id de outro — o
// pior erro possível aqui. Cada item sem par sai com o motivo escrito, e a guarda
// do `Gravar Campos` (0016/0043) o converte em pendência visível.
const CODE_RECOMPOR_CONTEXTO = `
const regs=$input.all();
let ctx=[];
try{ ctx=$('Juntar Ramos').all(); }catch(e){ ctx=[]; }
const desalinhado=ctx.length!==regs.length;
const saida=[];
for(let i=0;i<regs.length;i+=1){
  const r=regs[i].json||{};
  const res=r.r||r;
  const base=(!desalinhado&&ctx[i]&&ctx[i].json)?ctx[i].json:{};
  const {ia_body:_ob, ...limpo}=base;
  const motivos=[];
  if(desalinhado){
    motivos.push('Recompor Contexto: o Registrar Documento devolveu '+regs.length+' item(ns) e o Juntar Ramos '+ctx.length+' -- a correspondencia por indice deixou de ser verdadeira, e associar o arquivo de um documento ao id de outro seria pior que falhar. Contexto NAO recomposto.');
  }
  saida.push({pairedItem:{item:i}, json:{...limpo,
    documento_id:res.documento_id??null,
    documento_versao_id:res.documento_versao_id??null,
    // 0118: o banco JA' SABE se esta extracao foi feita antes com o mesmo prompt.
    // O flag viaja daqui para o IF \`Extracao ja feita?\`, que e' quem pula a
    // chamada a' OpenAI. Ausente (workflow contra banco sem a 0118) vira false --
    // pular por omissao seria deixar de extrair de graca.
    reaproveitou_extracao:res.reaproveitou_extracao===true,
    recompor_motivo:motivos.length>0?motivos.join(' | '):null,
  }});
}
return saida;
`.trim();

// --- Code (EACH ITEM): CAMADA 1 — a régua do documento ----------------------
//
// Roda logo depois do `Recompor Conteudo Extraido` (que converge os 5
// extratores por formato de volta a um item por documento) e existe por um
// motivo de MECÂNICA do n8n que custou duas execuções para ser entendido:
//
//   • `Extract From File` SUBSTITUI o item (escreve o resultado do PDF no `json`
//     e não repassa o binário). Posto entre `Lote cabe?` e `Preparar Conteudo`,
//     ele levou junto caso_id, classificação e arquivo — 35 documentos recusados
//     pelo banco com "null value in column caso_id".
//   • Pendurado como ramo LATERAL, ele parou de derrubar o lote — e parou também
//     de ser LIDO: `$('Nó').item` só resolve para nós ANCESTRAIS do item atual, e
//     um ramo irmão não é ancestral. A medição voltou vazia em todos os
//     documentos (`celulas_nos_documentos: 0`), e com ela as camadas 2 e 3
//     ficaram desligadas sem ninguém notar.
//
// A saída é pôr o `Extrair Texto` na corrente DEPOIS do `Preparar Conteudo`:
// nesse ponto o binário ainda existe (o preparo o repassa), o `content_part` já
// carrega o arquivo em base64 dentro do json — então perder o binário daqui para
// a frente não custa nada — e este nó recompõe o contexto lendo o
// `Preparar Conteudo`, que agora É ancestral.
const CODE_MEDIR_DOCUMENTO = `
${FONTE_COBERTURA}
// O texto vem do PROPRIO input (o \`Recompor Conteudo Extraido\` e' o no'
// anterior): nao depende de pareamento nenhum. O contexto vem do
// \`Preparar Conteudo\`, ancestral.
const doExtrator=$input.item.json||{};
const textoPdf=(typeof doExtrator.text==='string'&&doExtrator.text)||(typeof doExtrator.texto_pdf==='string'&&doExtrator.texto_pdf)||'';
let item={};
try{ item=$('Preparar Conteudo').item.json||{}; }catch(e){ item={}; }
// O CONTEUDO EXTRAIDO POR FORMATO CHEGA AQUI, NAO SE INVENTA UM CAMINHO NOVO.
// \`Recompor Conteudo Extraido\` SEMPRE escreve \`content_part\`/\`aviso_conteudo\`
// explicitamente no item que devolve -- inclusive quando o valor e' identico
// ao placeholder de \`Preparar Conteudo\` (extrator falhou, ou formato sem
// extrator). Por isso a chave so' precisa EXISTIR em \`doExtrator\` para valer:
// quando ela nao existe (o \`Extrair Texto\` do PDF, que devolve \`{text,
// numpages}\` e nao sabe nada do nosso \`content_part\`), \`item\` (o placeholder
// de \`Preparar Conteudo\`, que para PDF/imagem JA e' o conteudo real) segue
// valendo sem mudanca nenhuma.
const contentPart='content_part' in doExtrator ? doExtrator.content_part : item.content_part;
const avisoConteudo='content_part' in doExtrator ? (doExtrator.aviso_conteudo??null) : item.aviso_conteudo;
const linhasDoTexto=linhasComNumero(textoPdf);
const temTexto=linhasDoTexto.length>0;
// AS CELULAS, contadas linha a linha. O \`Extract From File\` entrega o texto
// AGRUPADO POR LINHA, e uma linha de comparativo de tres exercicios produz TRES
// celulas -- contar linha como celula deixava o fatiamento de 1,7x a 6,8x mais
// frouxo do que o nome dele diz, e na pratica DESLIGADO: medido, nenhum dos 38
// documentos do book-canastra era fatiado. Ver o comentario de \`celulasDaLinha\`.
const pesosDaLinha=temTexto?celulasEstimadas(linhasDoTexto):[];
const celulasEstim=pesosDaLinha.reduce((a,b)=>a+b,0);
// AUSENCIA DE TEXTO NAO E' ERRO: PDF escaneado nao tem camada de texto, e o
// documento segue como imagem exatamente como antes -- so' as camadas 2 e 3 se
// calam para ele. \`null\` e' "nao sei", nunca "zero": zero ligaria a guarda de
// cobertura com regua inventada justamente no documento onde o modelo mais erra.
return {json:{...item,
  content_part: contentPart,
  aviso_conteudo: avisoConteudo,
  // DUAS reguas, e a distincao e' o que fez a guarda voltar a enxergar:
  //   celulas -> toda linha com digito. E' o tamanho da RESPOSTA, e e' o que o
  //     fatiamento precisa saber (cabecalho tambem gasta token).
  //   contas  -> so' linha de conta (rotulo + valor), sem cabecalho de ano, CNPJ,
  //     data nem assinatura. E' a unidade da COBERTURA, comparavel com as contas
  //     distintas que a extracao grava. Medido no 02_DRE: 46 contra 39.
  celulas_no_documento: temTexto?linhasDoTexto.length:null,
  contas_no_documento: temTexto?linhasDeConta(textoPdf).length:null,
  // As MESMAS contas, repartidas pelas linhas de \`linhas_do_texto\` (a soma e'
  // \`contas_no_documento\`). E' o denominador da cobertura POR BLOCO: o
  // \`Fatiar Extracao\` soma a fatia de cada bloco. Recontar a fatia no
  // \`Fatiar\` daria 256 contra 99 no livro razao -- ver \`contasPorLinhaComNumero\`.
  // \`null\` quando alguma conta nao achou linha com digito: bloco sem medida
  // declarada, nunca vetor que nao soma.
  contas_por_linha: temTexto?contasPorLinhaComNumero(textoPdf):null,
  linhas_do_texto: temTexto?linhasDoTexto:null,
  // A TERCEIRA regua, e e' ela que decide o FATIAMENTO e o custo de SAIDA:
  // celulas de valor estimadas do proprio texto. \`colunas_estimadas\` sai da
  // razao celulas/linhas -- e substitui a leitura do NOME do arquivo, que so'
  // via coluna de PERIODO ("2025x2024x2023") e era cega a coluna de EMPRESA
  // (um combinado de seis empresas contava como uma coluna).
  celulas_estimadas: temTexto?celulasEstim:null,
  colunas_estimadas: temTexto?Math.max(1,Math.round(celulasEstim/linhasDoTexto.length)):null,
  // PAGINAS: quem paga a entrada da chamada e' a IMAGEM do PDF (~1.000 tokens
  // por pagina), entao o teto de gasto precisa deste numero -- e ele so' existe
  // aqui, na saida do \`Extrair Texto\` (o \`pdf-parse\` publica \`numpages\`).
  // \`null\` quando o extrator nao disse: o orcamento entao cai para a conta por
  // BYTE, que e' a saida conservadora, em vez de supor uma pagina.
  paginas_do_documento: Number.isFinite(Number(doExtrator.numpages))?Number(doExtrator.numpages)
    :(Number.isFinite(Number(doExtrator.numPages))?Number(doExtrator.numPages):null),
  // COMO O PDF FOI LIDO, decidido em \`Recompor Conteudo Extraido\`. Tem de
  // atravessar por NOME porque este no' reconstroi o item a partir do
  // \`Preparar Conteudo\` (\`{...item}\`), e nao do item do extrator -- sem estas
  // tres linhas o veredito morria aqui.
  //
  // E ele nao e' so' rastro: \`Orcamento do Lote\`, o proximo no', cobra IMAGEM
  // (paginas x 1.000 tokens) de todo \`formato: 'pdf'\`. Um PDF lido como TEXTO
  // pagaria imagem na ESTIMATIVA por um custo que a chamada nao vai ter -- o
  // guarda recusaria lote que cabe, que e' o v31 pelo outro lado.
  leitura_pdf: doExtrator.leitura_pdf??null,
  leitura_pdf_motivo: doExtrator.leitura_pdf_motivo??null,
  leitura_planilha: doExtrator.leitura_planilha??null,
  caracteres_do_texto: Number.isFinite(Number(doExtrator.caracteres_do_texto))
    ?Number(doExtrator.caracteres_do_texto):(temTexto?textoPdf.length:null),
}};
`.trim();

// --- Code (ALL ITEMS): CAMADA 2 — FATIAR O QUE NÃO CABE NUMA CHAMADA ---------
//
// O gpt-4o tem teto de 16.384 tokens de SAÍDA. Um documento cuja extração passa
// disso é cortado no meio (`finish_reason=length`) e volta sem nada de
// aproveitável — foi o que aconteceu com dois documentos do book-canastra, um
// com 326 e outro com 308 células de valor.
//
// Este nó não conserta truncamento: ele o torna IMPOSSÍVEL. Com a contagem da
// camada 1, projeta a saída e, quando ela passa de 60% do teto, emite um item
// por BLOCO — cada um com a mesma requisição, mais uma instrução de faixa.
//
// Por que ele existe separado do `Montar Req Extracao` em vez de virar um
// fan-out lá: aquele nó roda em `runOnceForEachItem` e depende de
// `$('Preparar Conteudo').item` para achar o contexto do SEU item. Trocar o modo
// quebraria esse pareamento — e os itens chegam ali por dois caminhos (com e sem
// classificação por conteúdo), então a ordem não é a de `Preparar Conteudo`.
// Fatiar DEPOIS, sobre itens que já carregam tudo, não tem esse problema.
const CODE_FATIAR_EXTRACAO = `
${FONTE_COBERTURA}
${FONTE_PROVEDOR}
const saida=[];
const entradas=$input.all();
for(let idx=0; idx<entradas.length; idx+=1){
  const it=entradas[idx];
  const j=it.json||{};
  // Documento sem medida (PDF escaneado, sem camada de texto) vai inteiro, como
  // sempre foi. Fatiar as cegas seria pior: sem ancora, "bloco 2 de 3" e' um
  // pedido para o modelo adivinhar onde a faixa comeca.
  const linhas=Array.isArray(j.linhas_do_texto)?j.linhas_do_texto:[];
  // OS PESOS EM CELULAS, e nao a contagem de linhas: \`MAX_CELULAS_POR_BLOCO\` e'
  // derivado de quantas CELULAS cabem em 60% do teto de saida, e aplica-lo a
  // linhas era o erro de unidade que desligava este no' na pratica.
  const fatias=linhas.length>0?planejarFatias(linhas, MAX_CELULAS_POR_BLOCO, celulasEstimadas(linhas)):[{bloco:1,blocos:1,de:0,ate:0,ancoraInicio:null,ancoraFim:null,celulas:0,linhas:0,acimaDoTeto:false}];
  for(const f of fatias){
    // A instrucao da faixa vai na mensagem de USER, nunca no prompt de sistema:
    // o prefixo tem de continuar identico em toda chamada para o cache de
    // prefixo da OpenAI valer (docs/CUSTO_OPENAI.md, alavanca 3).
    const corpo=JSON.parse(JSON.stringify(j.ia_body||{}));
    // ONDE a instrucao entra e' do provedor (\`contents\` no Google, \`messages\`
    // na OpenAI); QUE ela nao entra no prompt de sistema e' invariante nosso.
    acrescentarInstrucao(PROVEDOR,corpo,instrucaoDaFatia(f));
    // \`linhas_do_texto\` fica para tras: ele ja' virou ancora, e levar o
    // documento inteiro em texto por todo o grafo incharia cada item a' toa.
    // \`content_part\` sai pelo mesmo motivo, e agora ele PRECISA sair: desde que o
    // conteudo passou a viajar com o item (para nao depender de pareamento), o
    // base64 do PDF esta no json -- e ele ja' foi copiado para dentro do \`corpo\`.
    // Levar as duas copias por todo o resto do grafo dobraria a memoria do lote.
    const {linhas_do_texto:_l, contas_por_linha:_cpl, ia_body:_b, content_part:_cp, ...resto}=j;
    // CONTAS DO TEXTO NESTA FAIXA, para a segunda passada por cobertura do
    // \`Parse Extracao\`. \`null\` = nao medivel (sem texto, ou vetor que nao casa com
    // as linhas): sem denominador o bloco nao e' avaliado -- nunca um zero de mentira.
    const contasDoBloco=(Array.isArray(j.contas_por_linha)&&j.contas_por_linha.length===linhas.length&&linhas.length>0)
      ?j.contas_por_linha.slice(f.de,f.ate+1).reduce((a,b)=>a+(Number(b)||0),0):null;
    // \`pairedItem\` E' OBRIGATORIO num no' que muda a quantidade de itens. Sem
    // ele o n8n perde a cadeia e toda referencia a OUTRO no' por \`.item\` rio
    // abaixo volta undefined -- os nos Postgres recebem "undefined" em Query
    // Parameters e a execucao morre. Cada bloco aponta para o documento que o gerou.
    // A FAIXA VIAJA COM O ITEM. Sem \`bloco_de\`/\`bloco_ate\` a unica forma de
    // saber qual pedaco do documento uma chamada cobriu e' reler o texto que o
    // item nem leva mais -- e quando um bloco volta vazio, e' isso que se
    // pergunta primeiro. \`bloco_acima_do_teto\` e' a promessa de
    // \`planejarFatias\` chegando a quem le a execucao: linha que sozinha nao cabe
    // no teto nao tem corte mais fino, e o caso nao pode ficar em silencio.
    saida.push({json:{...resto, ia_body:corpo, bloco:f.bloco, blocos:f.blocos,
      celulas_do_bloco:f.celulas, linhas_do_bloco:f.linhas??null, contas_do_bloco:contasDoBloco,
      bloco_de:f.de, bloco_ate:f.ate, bloco_acima_do_teto:!!f.acimaDoTeto}, pairedItem:{item:idx}});
  }
}
return saida;
`.trim();

// --- Code (ALL ITEMS): junta os blocos e APLICA A GUARDA DE COBERTURA --------
//
// CAMADA 3. Depois de reunir os blocos de cada documento, compara o que voltou
// com o que a camada 1 mediu. Abaixo do limiar, escreve o motivo em
// `falha_motivo` — que `fn_registrar_campos_extraidos` já converte em pendência.
// Não precisa de migration: o caminho de "extração que não trouxe o que devia"
// já existe desde a `0016`; o que faltava era alguém CONFERIR.
//
// É esta camada que responde ao pedido do dono ("que nunca mais apareça"): ela
// não impede o modelo de pular uma linha — impede que isso seja silencioso. O
// livro razão devolveu 99 de 461 e passou como sucesso; com isto ele para na
// fila de revisão com os dois números na descrição.
const CODE_JUNTAR_BLOCOS = `
${FONTE_COBERTURA}
${FONTE_ARITMETICA}
const porDocumento=new Map();
const primeiroIndice=new Map();
const entradas=$input.all();
for(let idx=0; idx<entradas.length; idx+=1){
  const j=entradas[idx].json||{};
  // A CHAVE NAO PODE SER INVENTADA. A primeira versao usava
  // \`'sem-versao-'+tamanho\` quando o id faltava, e esse texto ia direto para
  // \`fn_registrar_campos_extraidos($1::uuid)\`: "invalid input syntax for type
  // uuid: sem-versao-0", execucao 6164. Um id ausente e' uma FALHA a declarar,
  // nunca um id de mentira -- agrupa-se sob null e o motivo vai junto.
  const chave=(typeof j.documento_versao_id==='string'&&j.documento_versao_id)?j.documento_versao_id:'__sem_versao__';
  if(!porDocumento.has(chave)){ porDocumento.set(chave,[]); primeiroIndice.set(chave,idx); }
  porDocumento.get(chave).push(j);
}
const saida=[];
for(const [chave, blocos] of porDocumento){
  const r=juntarBlocos(blocos);
  const base=blocos[0]||{};
  const documento_versao_id=chave==='__sem_versao__'?null:chave;
  const motivos=r.motivos.slice();
  if(documento_versao_id===null){
    motivos.push('Bloco(s) de extracao voltaram SEM documento_versao_id: as linhas nao tem onde ser gravadas. Causa provavel: falha no no "Registrar Documento" ou perda de contexto entre os blocos -- ver o log desta execucao.');
  }
  // A guarda. \`celulas_no_documento\` e' null no PDF sem camada de texto: nesse
  // caso ela se cala, e o silencio e' declarado (nao ha regua, entao nao ha
  // veredito) em vez de fabricado.
  // CONTAS DISTINTAS, nao pares (conta x coluna): num documento de 3 colunas os
  // pares sao 3x as contas, e comparar par com linha dava 198% de "cobertura" --
  // a guarda ficava cega justamente no comparativo. \`chave\` repetida (livro razao
  // com o mesmo historico) conta uma vez so', e a descricao da pendencia diz isso.
  const contasDistintas=new Set(r.campos.map(c=>c.chave)).size;
  // LINHAS devolvidas, nao contas distintas: num livro razao o mesmo historico
  // aparece em varios lancamentos (99 linhas, 66 historicos no book), e comparar
  // contas distintas com LINHAS do texto acusava de incompleta uma extracao
  // PERFEITA -- 66%, abaixo do limiar, pendencia falsa por construcao. As duas
  // pontas agora sao linha. O fallback para contas distintas cobre o bloco vindo
  // no formato plano antigo, que nao tem \`linha_origem\`: comportamento identico
  // ao de antes desta correcao, em vez de cobertura zero.
  const linhasDevolvidas=r.linhasRetornadas>0?r.linhasRetornadas:contasDistintas;
  const cobertura=avaliarCobertura({extraidas:linhasDevolvidas, esperadas:base.contas_no_documento});
  // EM QUANTOS BLOCOS O DOCUMENTO FOI LIDO — e este numero so' entrou aqui
  // porque eu mesmo precisei dele e nao tinha.
  //
  // Investigando as 23 pendencias de cobertura do araucaria, a pergunta que
  // decidia tudo era: o modelo leu pela metade, ou o FATIAMENTO nao rodou? Cinco
  // livros razao de 258 linhas devolveram 102, 101, 104, 102 e 102 — constancia
  // e' assinatura de TETO, nao de leitura. Mas um documento lido em UM bloco e
  // outro lido em QUATRO tinham exatamente a mesma aparencia na pendencia, e a
  // execucao ja' tinha sido cancelada (o n8n descarta os dados) e o lote nunca
  // fechou (a linha de \`lote_execucao\`, que carrega \`documentos_fatiados\`, nao
  // foi escrita). A investigacao parou por falta de instrumento.
  //
  // O numero existe, viaja no item, e custa uma frase.
  //
  // E ELE ERA O NUMERO ERRADO ate 31/08: \`r.blocos\` e quantos blocos CHEGARAM. O
  // que o \`Fatiar Extracao\` PLANEJOU viaja no mesmo item (\`blocos\`) e ninguem
  // lia. Com o recebido, "plano era 1" e "plano era 4 e chegou 1" escrevem a
  // MESMA frase -- e sao as duas hipoteses que esta frase existe para separar.
  // Agora os dois aparecem, e a divergencia entre eles ja saiu como motivo
  // proprio em \`juntarBlocos\` (FALTOU BLOCO).
  // TEM_DADO_FINANCEIRO=FALSE CALA ESTA GUARDA TAMBEM, NAO SO' O SINAL 3 --
  // MAS SO' QUANDO NADA FOI EXTRAIDO, IGUAL A 0111.
  //
  // A 0111 ja resolveu isto para o Sinal 3 ("veio vazia", em
  // fn_registrar_campos_extraidos): documento sem valor monetario por
  // natureza (certidao, organograma, parecer de auditoria) nao e' falha. Mas
  // aquela protecao mora no SQL e so cobre "veio vazia" -- esta guarda de
  // COBERTURA PARCIAL e' outro codigo, escrito depois, e nunca foi ligada a
  // mesma bandeira. MEDIDO na rodada real do "AMO teste 00" (17/09/2026): 3
  // certidoes da JUCESP e 1 planilha de controle de extratos vieram com
  // tem_dado_financeiro=false (a IA correta) e MESMO ASSIM abriram
  // extracao_falhou, porque a regua de texto conta data/CNPJ/percentual como
  // "linha de conta" sem saber que o documento e', por natureza, sem numero
  // financeiro.
  //
  // PRIMEIRA VERSAO DESTA CORRECAO (378f23a) CALAVA A GUARDA PARA QUALQUER
  // tem_dado_financeiro=false, SEM EXIGIR linhasDevolvidas===0 -- ao contrario
  // da propria 0111, que so' se cala quando \`v_count = 0\`. Revisao multilente
  // (17/09/2026) mediu o cenario: documento com 200 contas esperadas, o
  // modelo devolve 40 linhas COM valor monetario e marca tem_dado_financeiro
  // = false (documento misto, ou erro do modelo) -- a versao anterior gravava
  // os 40 campos SEM pendencia nenhuma, pior que o defeito original (antes
  // abria "Extracao INCOMPLETA: 40 de 200"). \`semDadoExtraido\` reproduz a
  // condicao \`v_count = 0\` da 0111 no lado JS.
  //
  // "===false" DENTRO da negacao (nao "!==false" isolado) continua de
  // proposito: ausencia do sinal (null/undefined) faz a comparacao dar
  // false, o "!" vira true, e a guarda continua acusando -- regra 1,
  // ausencia nao e' dado. CUIDADO para quem for mexer aqui: trocar por
  // "!==false" isolado (sem o semDadoExtraido) volta a abrir o CRITICO
  // que este bloco existe para fechar -- ver o teste 'ver-misto'.
  const semDadoExtraido=linhasDevolvidas===0;
  if(cobertura && !(semDadoExtraido && base.diagnostico?.tem_dado_financeiro===false)) motivos.push(cobertura.motivo
    + ' O documento foi lido em ' + r.blocos + ' de ' + r.blocosPlanejados + ' bloco(s) planejado(s)'
    + (r.blocosPlanejados>r.blocos
       ? '. Falta bloco: a cobertura acima mede o documento SEM esse trecho, entao ela NAO diz nada sobre a leitura do modelo.'
       : (r.blocosPlanejados===1
          ? '. Num documento longo, UM bloco so e o formato de quem bateu no teto de saida do modelo: vale conferir se o fatiamento devia ter dividido.'
          : ' (fatiado, e todos chegaram), entao o que falta nao e teto de uma chamada so nem bloco perdido -- e leitura parcial do modelo.')));
  // AS DUAS IDENTIDADES ARITMETICAS (Arquitetura do Sistema/2 Especificacao/04, identidade (c)): o texto ja chegou
  // (cobertura acima) e agora o NUMERO e conferido contra ele mesmo -- soma das
  // colunas de uma linha contra a coluna "Total" da mesma linha, e soma das
  // linhas de uma serie contra o "Totais" que a declara. Nao cobre (a)/(b)
  // (Ativo=Passivo+PL, subtotal=soma dos filhos): essas ja rodam no Postgres
  // (fn_reconciliar_ativo_passivo_pl, fn_reconciliar_arvore) via "Reconciliar
  // (Classe A)", mais adiante no grafo -- reimplementar aqui com um dicionario
  // de rotulo mais pobre arriscaria divergir da checagem que ja e a autoridade.
  const problemasLinha=conferirIdentidadeDeLinha(r.campos);
  if(problemasLinha.length>0) motivos.push(problemasLinha.slice(0,5).join(' | ')+(problemasLinha.length>5?' | ...':''));
  const problemasSerie=conferirTotalDaSerie(r.campos);
  if(problemasSerie.length>0) motivos.push(problemasSerie.slice(0,5).join(' | ')+(problemasSerie.length>5?' | ...':''));
  const problemasBalancete=conferirBalanceteLinhaALinha(r.campos);
  if(problemasBalancete.length>0) motivos.push(problemasBalancete.join(' | '));
  const problemasHierarquia=conferirHierarquiaDeCodigos(r.campos);
  if(problemasHierarquia.length>0) motivos.push(problemasHierarquia.join(' | '));
  // A EMENDA LIMPA NAO E' FALHA -- e' a costura fazendo exatamente o que ela
  // existe para fazer. Ate a rodada do lote 7377 (02/09, "teste Canastra"),
  // \`r.emendasLimpas>0\` sozinho virava \`motivos.push(...)\`, e qualquer motivo
  // em \`motivos\` produz \`falha_motivo\` nao-nulo (abaixo) -- que por sua vez conta
  // em \`documentos_com_falha\` do resumo do lote. O documento em questao foi lido
  // INTEIRO em 2 blocos (302 pares conta x coluna, cobertura 0,987): a unica
  // "falha" era a costura ter descartado 3 linhas repetidas na ancora, que e' o
  // comportamento CORRETO. \`com_falha=1\` sobre zero problema real -- e
  // \`documentos_com_falha\` deixa de ser sinal no momento em que passa a incluir
  // sucesso.
  //
  // A informacao nao pode sumir (regra 1 do CLAUDE.md: ausencia nao e' dado) --
  // so' muda de endereco. \`diagnostico\` foi descartado como destino: cada campo
  // dele e' lido por NOME em \`Registrar Diagnostico\`
  // (\`$json.diagnostico?.entidade\`, \`?.tipo_confirma\`, ... \`?.fatos\`) e nenhuma
  // query repassa o objeto inteiro para o banco -- e' contrato fechado, campo
  // por campo, e esticar significaria um campo que ninguem le OU mexer na
  // query (proibido: SQL e' do outro agente). O lugar e' aqui no item, ao lado
  // de \`blocos\`/\`blocos_planejados\`/\`contas_distintas\` -- os outros numeros que
  // tambem so' viajam para instrumentar a proxima investigacao e nunca tocam o
  // Postgres.
  const notaEmenda=r.emendasLimpas>0
    ? r.emendasLimpas+' linha(s) repetida(s) na emenda entre blocos foram descartadas (o modelo repetiu a ancora).'
    : null;
  saida.push({pairedItem:{item:primeiroIndice.get(chave)??0}, json:{
    documento_versao_id,
    // Levado adiante pelo mesmo motivo do documento_versao_id: o Registrar
    // Diagnostico e o Reconciliar liam o no' de registro por \`.item\`, que nao
    // pareia mais atraves do fatiamento. Agora leem do proprio item.
    documento_id:base.documento_id??null,
    campos:r.campos,
    // O DIAGNOSTICO VEM DO BLOCO 1, MAS OS FATOS VEM DE TODOS.
    //
    // Entidade, tipo e periodo sao do DOCUMENTO -- todo bloco responde a mesma
    // coisa. Os fatos nao: cada bloco le um PEDACO diferente do texto, e a nota
    // que declara o covenant pode estar no bloco 2. Antes desta correcao ela
    // sumia em silencio, e os documentos fatiados sao justamente os grandes.
    //
    // r.fatos e' null quando nenhum bloco trouxe a chave (workflow antigo) e
    // lista vazia quando algum leu e nao achou nada -- e a diferenca chega ao
    // banco: null manda NAO TOCAR nos fatos gravados, vazia manda apagar.
    diagnostico:base.diagnostico?{...base.diagnostico, fatos:r.fatos}:null,
    falha_motivo:motivos.length>0?motivos.join(' | '):null,
    blocos:r.blocos,
    // Quantos blocos precisaram de SEGUNDA passada por cobertura (so' instrumenta; ver
    // \`Parse Extracao\`). Sem isto a rodada real nao diz quanto a cota gastou nisso.
    blocos_refeitos:blocos.filter(b=>b.passadas>1).length,
    // O plano viaja junto do recebido ate o banco. Sem ele, \`documentos_fatiados\`
    // do painel do lote conta o que chegou e chama isso de fatiamento -- que e o
    // mesmo defeito da pendencia, um nivel acima.
    blocos_planejados:r.blocosPlanejados,
    // Contagem e nota da emenda, sempre presentes quando ela agiu -- mesmo
    // junto de um motivo real (restricao: so' a emenda limpa sai de
    // \`motivos\`; os outros continuam produzindo \`falha_motivo\`).
    emendas_limpas:r.emendasLimpas,
    nota_emenda:notaEmenda,
    celulas_no_documento:base.celulas_no_documento??null,
    contas_no_documento:base.contas_no_documento??null,
    contas_distintas:contasDistintas,
    linhas_devolvidas:linhasDevolvidas,
    cobertura:cobertura?cobertura.razao:(base.contas_no_documento>0?Number((linhasDevolvidas/base.contas_no_documento).toFixed(3)):null),
    custo_usd:blocos.reduce((soma,b)=>soma+(typeof b.custo_usd==='number'?b.custo_usd:0),0),
    tokens:blocos.reduce((acc,b)=>b.tokens?{entrada:acc.entrada+(b.tokens.entrada||0), saida:acc.saida+(b.tokens.saida||0), cache:acc.cache+(b.tokens.cache||0)}:acc,{entrada:0,saida:0,cache:0}),
  }});
}
return saida;
`.trim();

// --- Code (EACH ITEM): parse do diagnóstico+extração → payload p/ Postgres -
// falha_motivo: espelha N8N/lib/extract.mjs parseExtractionResponse — null
// quando ok; motivo textual (vira pendencia 'extracao_falhou') quando a
// chamada errou, veio truncada (finish_reason 'length') ou o JSON é inválido.
// Sem isso, uma falha silenciosa grava 0 campos e ninguém fica sabendo
// (achado em produção, sessão 7 cont.⁷ — "teste v14").
//
// REPETIÇÃO DE BLOCO POR FALHA TRANSITÓRIA (05/10/2026, execução 8433, Fw Valtra).
// Este mesmo código roda em CADA estágio de tentativa (`codeParseExtracao(k)`):
// o estágio 1 lê o contexto do `Fatiar Extracao`; os seguintes, do `Esperar Retry`
// que os alimentou. Falha TRANSITÓRIA com tentativa sobrando devolve o item do
// bloco marcado `repetir:true` (o IF seguinte o manda esperar e chamar de novo);
// o que sobra é permanente, ou transitório de teto esgotado, e segue para o
// `Juntar Blocos` com `falha_motivo` dizendo quantas tentativas foram feitas.
const codeParseExtracao = (estagio, refCtx) => `
${FONTE_DIAGNOSTICO_ERRO}
${FONTE_DECIDIR_REPETICAO}
${FONTE_SEGUNDA_PASSADA}
${FONTE_CUSTO_CHAMADA}
${FONTE_PROVEDOR}
const TENTATIVA=${estagio};
// O contexto vem do FATIAMENTO, nao mais do \`Montar Req Extracao\`: e' ele que
// sabe qual bloco este item e', e um item por bloco significa que o pareamento
// com o no' anterior a ele deixou de ser 1:1. O fallback existe para o caso de
// alguem religar o grafo sem o fatiamento.
let ctx=null;
try{ ctx=$('${refCtx}').item.json; }catch(e){ ctx=null; }
if(!ctx&&TENTATIVA>1){ try{ ctx=$('Fatiar Extracao').item.json; }catch(e){ ctx=null; } }
if(!ctx){ try{ ctx=$('Montar Req Extracao').item.json; }catch(e){ ctx=null; } }
// NENHUMA das duas leituras pode DERRUBAR o item: se o pareamento se perder, o
// que se perde e' o contexto, e perder contexto tem de virar falha declarada --
// nao uma excecao que manda o item inteiro para o ramo de erro sem dizer o que
// aconteceu (execucao 6164).
if(!ctx){ ctx={}; }
// O aviso do preparo e o motivo do Recompor Contexto entram JUNTOS: os dois sao
// "dado que o documento tem e o banco nao recebeu", e cabem no mesmo documento.
const avisoConteudo=[ctx.aviso_conteudo??null, ctx.recompor_motivo??null].filter(Boolean).join(' | ')||null;
const resp=$json;
const cortado=cortadoPorLimite(PROVEDOR,resp);
const content=conteudoDaResposta(PROVEDOR,resp);
let p={}; let falhaMotivo=null;
let transitoria=false; let esperaSugerida=null; let respostaLida=false;
if(resp?.error){
  const dg=diagnosticarErroApi(resp.error);
  falhaMotivo=dg.motivo; transitoria=dg.transitoria; esperaSugerida=dg.esperaSugeridaS;
}else if(!content){
  falhaMotivo='Resposta do provedor de IA ('+PROVEDOR.rotulo+') sem conteudo (falha de rede/API).';
  transitoria=true;
}else{
  try{p=typeof content==='string'?JSON.parse(content):content; respostaLida=true;}catch(e){
    falhaMotivo=cortado
      ?'Resposta do provedor de IA truncada por limite de tokens de saida -- o JSON ficou incompleto e nao pode ser interpretado. Documento provavelmente grande/denso demais (muitas contas/entidades) para uma unica chamada.'
      :'Resposta do provedor de IA nao veio em JSON valido.';
    p={};
  }
}
// REPETIR OU DESISTIR. So' repete o que pode dar certo na segunda vez (transitorio)
// E o que da' para refazer (o corpo da chamada viaja no ctx; sem ele o proximo
// estagio mandaria \`undefined\` ao provedor, entao e' falha declarada e nao repeticao).
const dec=decidirRepeticao({transitoria, tentativa:TENTATIVA, esperaSugeridaS:esperaSugerida});
if(dec.repetir&&ctx.ia_body){
  return {json:{...ctx, repetir:true, tentativa:TENTATIVA, espera_s:dec.esperaS, ultima_falha:falhaMotivo}};
}
if(!falhaMotivo&&cortado){
  falhaMotivo='Resposta do provedor de IA atingiu o limite de tokens de saida; o JSON veio valido, mas o conteudo pode estar incompleto (faltando linhas do fim do documento).';
}
${FONTE_NORMALIZAR_UNIDADE}
${FONTE_NORMALIZAR_MOEDA}
const unidade=normUnid(p.unidade);
// Moeda do documento herdada por linha, mesma regra da escala (item 2 do 7.4):
// era normalizada e jogada fora aqui, e o book somava USD com BRL.
const moedaDoc=normMoeda(p.moeda);
${FONTE_NAO_MONETARIA}
${FONTE_ESCALA_COLUNA}
${FONTE_ACHATAR_GRUPOS}
// A saida da IA vem AGRUPADA (uma secao, suas colunas, e uma conta com um
// valor por coluna) e e' achatada aqui de volta para uma linha por
// (conta x coluna) -- a forma que \`campo_extraido\` sempre teve. O achatamento
// vem EMBUTIDO da fonte, nao copiado: se este no' e a lib discordarem sobre como
// associar valor a coluna, o banco recebe o numero de 2024 no lugar do de 2025.
const ach=achatarGrupos(p.grupos);
let campos=ach.linhas.length>0||Array.isArray(p.grupos)
  ? ach.linhas.map((l,i)=>({ordem:i, ...l, unidade:naoMonet(l.chave,l.valor_texto,l.periodo_coluna)?null:(escalaCol(l.periodo_coluna)??unidade), moeda:naoMonet(l.chave,l.valor_texto,l.periodo_coluna)?null:moedaDoc}))
  // FORMATO PLANO ANTIGO -- o caminho de um workflow importado velho responder
  // no formato de julho. Em 12/08/2026 o n8n do dono rodou dias assim, e "zero
  // linhas extraidas" sem explicacao seria a pior forma de descobrir.
  : (Array.isArray(p.linhas)?p.linhas.map((l,i)=>({ordem:i, secao:l.s??null, secao_canonica:(l.sc&&l.sc!=='NAO_CLASSIFICAVEL')?l.sc:null, entidade_coluna:l.ec??null, periodo_coluna:l.pc??null, chave:l.k, valor_texto:l.vt??null, valor_num:(typeof l.vn==='number')?l.vn:null, unidade:naoMonet(l.k,l.vt,l.pc)?null:(escalaCol(l.pc)??unidade), moeda:naoMonet(l.k,l.vt,l.pc)?null:moedaDoc, confianca:(typeof l.cf==='number')?l.cf:null, origem_pagina:Number.isInteger(l.op)?l.op:null})):[]);
// Conta descartada por desalinhamento de coluna nao pode sumir em silencio: e'
// dado que o documento tem e o banco nao recebeu.
if(ach.problemas.length>0){
  const dizer=ach.problemas.length+' conta(s) descartada(s) por desalinhamento entre colunas e valores (a associacao valor-coluna ficou desconhecida, e adivinha-la trocaria um periodo pelo outro): '+ach.problemas.slice(0,5).join('; ')+(ach.problemas.length>5?'; ...':'');
  falhaMotivo=falhaMotivo?falhaMotivo+' | '+dizer:dizer;
}
// Rotulo com numero monetario colado que NAO e' o valor da linha: a conta ficou,
// o rotulo nao foi limpo (so' se limpa o que e' provadamente o valor vazado).
if(ach.rotulosSuspeitos.length>0){
  const dizer2=ach.rotulosSuspeitos.length+' rotulo(s) com numero colado que nao e o valor da linha (a conta foi mantida, o rotulo NAO foi limpo e pode nao casar na reconciliacao): '+ach.rotulosSuspeitos.slice(0,5).join('; ')+(ach.rotulosSuspeitos.length>5?'; ...':'');
  falhaMotivo=falhaMotivo?falhaMotivo+' | '+dizer2:dizer2;
}
const d=p.diagnostico||{};
const diagnostico={
  entidade: d.entidade??null,
  cnpj: d.cnpj??null,
  tipo_confirma: (typeof d.tipo_confirma==='boolean')?d.tipo_confirma:null,
  tipo_sugerido: d.tipo_sugerido==='DESCONHECIDO'?null:(d.tipo_sugerido??null),
  periodo_tipo: d.periodo_referencia?d.periodo_tipo:null,
  periodo_referencia: d.periodo_referencia??null,
  legibilidade: d.legibilidade??null,
  nota_legibilidade: d.nota_legibilidade??null,
  tem_dado_financeiro: (typeof d.tem_dado_financeiro==='boolean')?d.tem_dado_financeiro:null,
  resumo: d.resumo??null,
  justificativa: d.justificativa??'',
  // Os fatos viajam para fn_registrar_fatos no MESMO no' que grava o
  // diagnostico. null quando a chave nao veio (workflow antigo) e' DIFERENTE de
  // [] (o modelo leu e nao achou nada): o banco nao apaga os fatos de uma versao
  // ao receber null, porque apagar trilha por causa de workflow desatualizado e'
  // o defeito do Gravar Campos que desligou a reconciliacao por onze dias.
  fatos: Array.isArray(d.fatos)
    ? d.fatos.filter((f)=>f&&typeof f==='object'&&typeof f.ft==='string'&&typeof f.tr==='string'&&f.tr.trim().length>=20)
             .map((f)=>({tipo:f.ft, trecho:f.tr.trim(), leitura:(typeof f.le==='string'&&f.le.trim()!=='')?f.le.trim():null, pagina:Number.isInteger(f.pg)?f.pg:null}))
    : null,
};
// Custo REAL desta chamada, do bloco \`usage\` que a OpenAI devolve. Não vai
// para o banco (exigiria migration) — vai para a saída do nó, visível na
// execução do n8n. É com ele que CUSTO_ESTIMADO_DOC_USD deve ser recalibrado:
// hoje o teto de US$ 3 por execução decide em cima de uma ESTIMATIVA declarada,
// e trocar estimativa por medição é o único jeito honesto de apertar o teto.
const uso=usoDaChamada(PROVEDOR,resp);
const custo_usd=custoDaChamada(uso, '${MODEL_EXTRACAO}');
// A SEGUNDA PASSADA POR COBERTURA (05/10/2026, Fw Valtra: "36 ALTERACAO E
// CONSOLIDACAO CONTRATUAL" voltou com 59 linhas para 101 no texto, 58%). O bloco que
// volta ABAIXO do limiar de cobertura e' refeito UMA vez, com a instrucao reforcada
// (\`instrucaoDeSegundaPassada\`: o numero que faltou, e que a resposta SUBSTITUI a
// anterior), antes de a falha ser declarada. Fica a passada com MAIS linhas e as duas
// NUNCA se somam -- descrevem as mesmas linhas, e somar duplicaria cada conta que as
// duas acharam. A primeira viaja dentro do item (\`passada_anterior\`) ate' o estagio
// seguinte, que e' quem escolhe; por isso o teto de 4 chamadas por bloco e' UM SO' para
// falha transitoria e cobertura juntas -- a cota do dia (RPD 500) nao cresce alem de
// 4 por bloco, e o estagio de repetição e' o mesmo da fatia 1.
const ant=ctx.passada_anterior||null;
const esperadasBloco=(ctx.contas_do_bloco!==null&&ctx.contas_do_bloco!==undefined&&Number.isFinite(Number(ctx.contas_do_bloco)))?Number(ctx.contas_do_bloco):null;
const tokensDestaChamada=uso?{entrada:uso.prompt_tokens??null, saida:uso.completion_tokens??null, cache:uso.prompt_tokens_details?.cached_tokens??0}:null;
const esta={campos, diagnostico, falha:falhaMotivo, linhas:linhasDaPassada(campos), custo_usd, tokens:tokensDestaChamada};
const razaoDe=(n)=>(esperadasBloco>0&&n!==null)?Number((n/esperadasBloco).toFixed(3)):null;
const pctDe=(r)=>(r===null?'?':Math.round(r*100)+'%');
let final=esta; let passadas=1; let notaCobertura=null;
// So' avalia cobertura quando a resposta foi LIDA e nao veio cortada por limite (o
// truncamento ja' tem motivo proprio, e refaze-lo cortaria igual), ou quando esta e' a
// segunda passada (que tem de escolher entre duas respostas, lida a segunda ou nao).
if(ant||(respostaLida&&!cortado)){
  if(ant){
    passadas=2;
    final=melhorPassada(ant.linhas, esta.linhas)==='segunda'?esta:ant;
  }
  const dec2=decidirSegundaPassada({linhas:final.linhas, esperadas:esperadasBloco, tentativa:TENTATIVA, maxTentativas:dec.maxTentativas, temDadoFinanceiro:final.diagnostico?.tem_dado_financeiro??null, jaRefeita:!!ant});
  if(!ant&&dec2.refazer&&ctx.ia_body){
    const corpo2=JSON.parse(JSON.stringify(ctx.ia_body));
    acrescentarInstrucao(PROVEDOR,corpo2,instrucaoDeSegundaPassada({linhas:esta.linhas, esperadas:esperadasBloco, blocos:ctx.blocos??1}));
    // Espera ZERO: nao e' limite de cadencia, e a cadencia do no' HTTP (lote de 1,
    // intervalo fixo) ja' separa as chamadas. Se o provedor responder 429, o Parse
    // seguinte trata como qualquer transitoria, com a propria espera.
    return {json:{...ctx, ia_body:corpo2, repetir:true, tentativa:TENTATIVA, espera_s:0, ultima_falha:null, motivo_repeticao:'cobertura',
      passada_anterior:{campos, diagnostico, falha:falhaMotivo, linhas:esta.linhas, razao:razaoDe(esta.linhas), custo_usd, tokens:tokensDestaChamada}}};
  }
  if(dec2.abaixo){
    const rFinal=razaoDe(final.linhas);
    if(ant){
      notaCobertura='Cobertura do bloco '+(ctx.bloco??1)+' de '+(ctx.blocos??1)+' abaixo do minimo de '+Math.round(LIMIAR_COBERTURA*100)+'% mesmo apos 2 tentativas: a 1a devolveu '+ant.linhas+' de ~'+esperadasBloco+' linha(s) de conta ('+pctDe(ant.razao)+') e a 2a, '
        +(esta.falha&&esta.linhas===0?'FALHOU ('+esta.falha+')':esta.linhas+' ('+pctDe(razaoDe(esta.linhas))+')')
        +'; ficou a de mais linhas, '+final.linhas+' ('+pctDe(rFinal)+'). As duas respostas NAO se somam (duplicaria linha): o que falta continua faltando no banco.';
    }else{
      const porque=!ctx.ia_body?'o corpo da chamada nao viajou no contexto'
        :(dec2.porque==='sem-tentativa'?'o teto de '+dec.maxTentativas+' chamadas por bloco ja foi consumido por falha transitoria':'sem motivo declarado');
      notaCobertura='Cobertura do bloco '+(ctx.bloco??1)+' de '+(ctx.blocos??1)+' abaixo do minimo de '+Math.round(LIMIAR_COBERTURA*100)+'% ('+final.linhas+' de ~'+esperadasBloco+' linha(s) de conta, '+pctDe(rFinal)+') e a segunda passada NAO foi feita: '+porque+'.';
    }
  }
}
campos=final.campos;
const diagnosticoFinal=final.diagnostico;
// O CUSTO E' O DAS DUAS CHAMADAS, ganhe a que ganhar: a segunda passada e' paga mesmo
// quando a primeira fica.
const custoTotal=(ant&&typeof ant.custo_usd==='number'?ant.custo_usd:0)+(typeof custo_usd==='number'?custo_usd:0);
const tokensTotais=ant&&ant.tokens&&tokensDestaChamada
  ?{entrada:(ant.tokens.entrada||0)+(tokensDestaChamada.entrada||0), saida:(ant.tokens.saida||0)+(tokensDestaChamada.saida||0), cache:(ant.tokens.cache||0)+(tokensDestaChamada.cache||0)}
  :(tokensDestaChamada||(ant?ant.tokens:null));
// O motivo e' o da passada que FICOU (problemas de alinhamento da primeira nao somem se
// ela ganhou), e a segunda que falhou nao pode ficar muda atras de uma primeira boa.
falhaMotivo=final.falha;
if(ant&&final===ant&&esta.falha) falhaMotivo=[falhaMotivo,'segunda passada por cobertura falhou: '+esta.falha].filter(Boolean).join(' | ');
if(notaCobertura) falhaMotivo=falhaMotivo?falhaMotivo+' | '+notaCobertura:notaCobertura;
// O aviso do preparo SOMA-SE ao motivo da chamada em vez de competir com ele:
// planilha cortada E resposta truncada cabem no mesmo documento, e esconder um
// dos dois e' a falha que esta mudanca fecha.
// QUANTAS TENTATIVAS ESTA FALHA JA' TEVE. Sem isto a pendencia de um bloco que
// foi chamado 4 vezes e a de um chamado uma so' sao identicas, e quem le acha que
// bastava repetir (ou que ja' repetiram, quando nao repetiram).
const esperaTotal=Number(ctx.espera_total_s)||0;
const notaTentativas=(falhaMotivo&&TENTATIVA>1)
  ?'[Bloco chamado '+TENTATIVA+' vez(es), esperas somadas '+esperaTotal+'s'+(dec.esgotou?'; teto de '+dec.maxTentativas+' tentativas ESGOTADO, a falha era transitoria e persistiu':'')+']'
  :null;
const falhaFinal=[avisoConteudo,falhaMotivo,notaTentativas].filter(Boolean).join(' | ')||null;
// \`bloco\`/\`blocos\`/\`celulas_no_documento\`/\`contas_no_documento\` viajam para o
// \`Juntar Blocos\`: sem
// eles a juncao nao sabe a ordem dos pedacos nem tem regua para a cobertura.
// \`passadas\` e as duas coberturas do bloco so' instrumentam a execucao (nao tocam o
// Postgres): e' por elas que se mede, na primeira rodada real, quanto a segunda
// passada recupera -- coisa que nenhum teste sem chamar o modelo consegue dizer.
return {json:{documento_id:ctx.documento_id??null, documento_versao_id:ctx.documento_versao_id??null, bloco:ctx.bloco??1, blocos:ctx.blocos??1, celulas_no_documento:ctx.celulas_no_documento??null, contas_no_documento:ctx.contas_no_documento??null, campos, diagnostico:diagnosticoFinal, falha_motivo:falhaFinal, tentativas:TENTATIVA, passadas, contas_do_bloco:esperadasBloco, cobertura_bloco:razaoDe(final.linhas), cobertura_bloco_primeira:ant?ant.razao:null, custo_usd:custoTotal, tokens:tokensTotais}};
`.trim();
const CODE_PARSE_EXTRACAO = codeParseExtracao(1, 'Fatiar Extracao');

// O ESTAGIO DE ESPERA entre duas tentativas. Um nó para TODOS os blocos que
// falharam no estágio anterior: espera UMA vez (o maior pedido entre eles, já
// limitado a 60 s por `decidirRepeticao`) em vez de uma vez por bloco, e devolve os
// itens intactos com `tentativa` pronta para o Parse seguinte e a espera somada.
// `setTimeout` é global no sandbox do Code node; se um dia não for, a repetição
// acontece SEM espera e `espera_total_s` diz 0 — a pendência conta a verdade em vez
// de afirmar uma espera que não houve.
const CODE_ESPERAR_RETRY = `
const itens=$input.all();
let espera=0;
for(const it of itens){ espera=Math.max(espera, Number(it.json?.espera_s)||0); }
let esperou=0;
if(espera>0&&typeof setTimeout==='function'){
  await new Promise((resolve)=>setTimeout(resolve, espera*1000));
  esperou=espera;
}
return itens.map((it,i)=>({json:{...it.json, repetir:false, espera_s:0, espera_total_s:(Number(it.json?.espera_total_s)||0)+esperou}, pairedItem:{item:i}}));
`.trim();


const PG_CRED = { postgres: { id: 'REPLACE', name: 'Supabase Postgres (Session Pooler)' } };
// `position` NÃO entra aqui: quem posiciona é `posicionar()` (N8N/layout.mjs), a
// partir das `connections`, depois que a lista inteira existe. Coordenada
// escolhida à mão nó a nó foi o que embaralhou o canvas (rótulo em cima de
// rótulo, linha atravessando nó), e ela não tem como saber do vizinho que ainda
// nem foi declarado.
const node = (name, type, typeVersion, parameters, opts = {}) => ({
  parameters, id: name.toLowerCase().replace(/[^a-z0-9]+/g, '-'), name, type, typeVersion,
  position: [0, 0],
  ...(opts.credentials ? { credentials: opts.credentials } : {}),
  ...(opts.onError ? { onError: opts.onError } : {}),
  ...(opts.disabled ? { disabled: true } : {}),
  // `executeOnce`: o nó roda UMA vez para o lote inteiro, com o primeiro item.
  // É o que a 0152 precisa no `Reconciliar Lote` — a pergunta é do caso, e
  // rodá-la por documento é o defeito que ela corrige.
  ...(opts.executeOnce ? { executeOnce: true } : {}),
  // Retry no nível do node (N8N): reexecuta o item que falhou antes de cair no
  // onError. waitBetweenTries tem teto de 5000ms no N8N. maxTries 6 (era 4,
  // cont.⁸): o "teste v18" mostrou que 4 tentativas não bastavam pros documentos
  // mais pesados (cont.¹¹).
  //
  // ⚠️ SUSPEITA FORTE, NÃO CONFIRMADA (achado ao investigar o v30, lendo o fonte
  // do n8n): com `onError: 'continueRegularOutput'` o nó NUNCA LANÇA — ele empurra
  // o item de erro adiante —, e se o retry do n8n depende do lançamento, então
  // `retryOnFail` nunca dispara nos nós OpenAI e as "6 tentativas" em que este
  // comentário confiava são ficção. Não confirmei contra o n8n do dono, e por isso
  // NÃO mexi na configuração: trocar `onError` para o retry funcionar traria de
  // volta o bug da sessão 7 cont.¹³ (um erro num item matando o lote inteiro em
  // silêncio), o que é pior que não ter retry. A verificação é de 1 minuto no n8n
  // vivo: a duração da execução diz se houve 1 passada ou 6 (ver HANDOFF).
  //
  // O que NÃO depende dessa dúvida: a cadência derivada do TPM (abaixo). Ela
  // dimensiona o lote para não estourar o balde na PRIMEIRA tentativa — que é a
  // única em que dá para confiar hoje.
  ...(opts.retryOnFail ? { retryOnFail: true, maxTries: opts.maxTries ?? 6, waitBetweenTries: opts.waitBetweenTries ?? 5000 } : {}),
});

// Batching do HTTP Request (N8N): processa `batchSize` itens, espera
// `batchInterval` ms, processa os próximos. Com um upload em lote de N
// documentos, sem isso o node dispara N chamadas à OpenAI praticamente
// simultâneas → estoura o rate limit (RPM/TPM), a API responde 429 e TODAS as
// extrações falham (achado em produção, sessão 7 cont.⁸ — "teste v15", 16
// documentos, 16 erros idênticos "Try spacing your requests out"). 1 por vez
// com intervalo espalha as chamadas no tempo (RPM e TPM).
//
// 3s (cont.⁸) reduziu bastante mas NÃO eliminou o 429: no "teste v18" (16
// documentos reais), os 3 que ainda deram 429 eram justamente os consolidados
// comparativos multi-ano (mais tokens de ENTRADA — o PDF é mais denso — e de
// SAÍDA — cada conta vira 2-3 linhas via periodo_coluna), que consomem TPM
// desproporcionalmente mais que os demais mesmo com a mesma cadência de
// requisições. 6s de intervalo + mais tentativas de retry dão mais folga pro
// balde de TPM da conta se recompor entre chamadas pesadas (achado em
// produção, sessão 7 cont.¹¹). Trade-off consciente: processa mais devagar.
// `neverError`: A CORREÇÃO QUE O DADO DO DONO EXIGIU.
//
// A saída real do nó no v30, colada por ele:
//
//     error.message = "Try spacing your requests out using the batching settings…"
//     error.name    = "AxiosError"
//     error.code    = "ERR_BAD_REQUEST"      ← código de TRANSPORTE, não da OpenAI
//     error.status  = 429
//
// Não há `error.error`, não há `cause`, não há headers: o corpo da resposta da
// OpenAI — que é o único lugar onde `insufficient_quota` / `rate_limit_exceeded` /
// `project_spend_limit_exceeded` aparecem — **não chega ao item**. A investigação
// tinha previsto que ele estaria em `error.error.error`; o dado do dono refutou
// isso nesta versão do n8n. Tratar 429 sem corpo é o melhor que dá para fazer com
// esse item, e é honestamente o que o diagnóstico faz ("não disse QUAL").
//
// Com `neverError`, o nó deixa de tratar 4xx/5xx como exceção e entrega a
// RESPOSTA — cujo corpo é exatamente `{error:{type,code,message}}`. Aí o
// diagnóstico nomeia a causa em vez de dizer "indeterminado", e a mensagem da
// OpenAI para rate limit traz os números do balde ("Limit 30000, Used …").
//
// TRADE-OFF, explícito: sem exceção, o `retryOnFail` do nó não tem o que
// reexecutar. Aceito por duas razões — (a) a investigação indica que ele já não
// disparava, porque `onError: continueRegularOutput` também impede o lançamento;
// (b) uma tentativa que sabe a causa vale mais que seis que não sabem. Falha de
// REDE (sem resposta) continua sendo exceção, então retry/onError seguem valendo
// para ela. Se em produção aparecer sinal de que o retry era real e fazia falta,
// o caminho é reverter esta opção — não empilhar as duas.
const RESPOSTA_COM_CORPO_NO_ERRO = { response: { response: { neverError: true } } };

// `PISO_BATCHING_MS` mora em `lib/extract.mjs` desde 14/09/2026, junto de
// `TPM_CONTA`/`RPM_CONTA` — o histórico dele (o "teste v18", 3 de 16
// documentos tomando 429 com 3s) está lá, no mesmo comentário.
// O QUE DEPENDE DO PROVEDOR É O LIMITE POR CHAMADA. Quando ele existe (RPM), o
// intervalo tem de respeitá-lo contando que um documento mal nomeado faz DUAS
// chamadas — a de classificação e a de extração, em nós diferentes, no mesmo
// minuto. Dividir o minuto pelo RPM e esquecer a segunda chamada é o jeito
// aritmeticamente garantido de tomar 429 no meio do lote: os dois nós somam.
const CHAMADAS_MAX_POR_DOCUMENTO = 2;
const INTERVALO_POR_RPM_MS = RPM_CONTA
  ? Math.ceil((60000 / RPM_CONTA) * CHAMADAS_MAX_POR_DOCUMENTO)
  : 0;

// O PIOR CASO DE ENTRADA, em tokens de imagem — ver o comentário de
// `PAGINAS_MAX_MEDIDO` em `lib/custo.mjs`. Compartilhado pelas DUAS cadências
// abaixo (extração e classificação): as duas chamadas mandam o MESMO PDF.
const ENTRADA_MAX_MEDIDA_TOKENS = PAGINAS_MAX_MEDIDO * TOKENS_POR_PAGINA_IMAGEM;

// A RESERVA DE TPM DA CLASSIFICAÇÃO — ACHADO NUMA REVISÃO ADVERSARIAL (11/09),
// no MESMO defeito que `INTERVALO_EXTRACAO_MS` tinha antes da correção abaixo,
// só que aqui não havia sequer uma PRIMEIRA tentativa: `IA_BATCHING` espaçava
// só pelo piso de 6s e pelo RPM, sem nenhum termo de TPM. Uma classificação
// manda o MESMO PDF de imagem que a extração (~20.000 tokens no pior caso) e
// devolve uma saída pequena (`TOKENS_SAIDA_CLASSIFICACAO`) — mas a reserva de
// TPM da OpenAI conta a ENTRADA inteira, não só a saída. A 6s de intervalo,
// 10 chamadas/min × ~20.000 tokens = 200.000 tokens/min: 6,7× o teto de 30.000
// do Tier 1, e nenhum espaçamento por CONTAGEM de chamada evita isso — só o
// TPM evita. `+400` é o mesmo placeholder que `custoEstimadoPorConteudo`
// (`lib/custo.mjs`) já usa para o prompt de sistema da classificação (ele não
// tem nome próprio como `SYSTEM_PROMPT` da extração).
// ARREDONDA PARA CIMA, EM SEGUNDO CHEIO. Duas razões, as duas reais: (a) o
// campo do n8n é preenchido em segundos por um humano, e um `batchInterval` de
// "41.04s" não é algo que o editor mostra nem que alguém digitaria; (b) o
// espelho do portal (`espera-do-lote.ts`, `CADENCIA_IA_S`) é comparado por
// IGUALDADE EXATA contra este número em `workflow-sim.test.mjs` — sem
// arredondar aqui, a divisão de TPM por uma reserva que não é múltipla de 500
// produziria uma fração, e a igualdade exata nunca bateria. Arredondar para
// CIMA (nunca para baixo) é o lado seguro: o intervalo real fica IGUAL ou
// MAIOR que o mínimo aritmético, nunca menor.
const arredondarParaSegundoCheio = (ms) => Math.ceil(ms / 1000) * 1000;

const RESERVA_CLASSIFICACAO_TOKENS = ENTRADA_MAX_MEDIDA_TOKENS + 400 + TOKENS_SAIDA_CLASSIFICACAO;
const CHAMADAS_POR_MINUTO_CLASSIFICACAO = TPM_CONTA / RESERVA_CLASSIFICACAO_TOKENS;
const INTERVALO_CLASSIFICACAO_MS = arredondarParaSegundoCheio(Math.max(
  Math.ceil(60000 / CHAMADAS_POR_MINUTO_CLASSIFICACAO),
  INTERVALO_POR_RPM_MS,
  PISO_BATCHING_MS,
));

const IA_BATCHING = {
  batching: { batch: { batchSize: 1, batchInterval: INTERVALO_CLASSIFICACAO_MS } },
  ...RESPOSTA_COM_CORPO_NO_ERRO,
};

// A CADÊNCIA DA EXTRAÇÃO É ARITMÉTICA, NÃO CHUTE — e isto é a correção do v30.
//
// O que eu não sabia quando escolhi 6s e depois 12s: a OpenAI documenta que
// "your rate limit is calculated as the MAXIMUM of max_tokens and the estimated
// number of tokens based on the character count of your request". Ou seja,
// `max_tokens` é RESERVA de TPM: toda extração reserva 16.384
// tokens do balde por minuto, para um PDF de 2 KB ou de 40 páginas — os dois
// pagam igual. Isso explica o fato que mais incomodava no v30: as notas
// explicativas minúsculas também tomaram 429.
//
// Com isso, a cadência deixa de ser opinião:
//
//     chamadas por minuto suportadas = TPM_DA_CONTA / (entrada + max_tokens)
//     intervalo mínimo entre chamadas = 60.000ms / chamadas por minuto
//
// Nos números de hoje (Tier 1 = 30.000 TPM, max_tokens = 16.384): ~2,7
// chamada/min → intervalo de ~22s.
//
// A LINHA `TPM_DA_CONTA / max_tokens`, SEM A ENTRADA, FICOU AQUI DE 27/08 A
// 11/09 — ACHADO NUMA REVISÃO ADVERSARIAL, NÃO POR ESTE COMENTÁRIO. O parágrafo
// acima ("`max_tokens` é RESERVA de TPM... os dois pagam igual") estava CERTO
// sobre o FATO e ERRADO na CONCLUSÃO: a reserva de `max_tokens` cobre a SAÍDA,
// não "a chamada inteira" como este comentário chegou a afirmar. Um PDF de 20
// páginas (o maior já medido, `PAGINAS_MAX_MEDIDO`) manda ~20.000 tokens de
// ENTRADA — MAIS os 16.384 reservados de saída, 36.384 numa chamada só, 21%
// ACIMA do teto de 30.000 do Tier 1. Nenhum espaçamento entre chamadas evita
// isso: é UMA chamada estourando o balde sozinha, o mesmo desfecho das 72
// falhas do "Teste 00" (`HANDOFF.md`) por um caminho que ninguém tinha somado.
// Documento típico (`PERFIL_MEDIDO.entradaPorDocumento`, 3.500 tokens) nunca
// bateu nisso — e foi por isso que o defeito passou disfarçado de correção.
//
// TPM_CONTA/RPM_CONTA são os ÚNICOS números de conta a ajustar, e eles moram no
// provedor (`lib/provedor.mjs`), lidos por `lib/extract.mjs` junto de
// MAX_OUTPUT_TOKENS, porque o teste de cadência e o `diagnosticar-ia.mjs` leem
// os MESMOS valores — duplicar aqui faria os três discordarem no primeiro
// ajuste. `PAGINAS_MAX_MEDIDO` mora em `lib/custo.mjs` pela mesma razão: é o
// número que muda quando um documento maior aparecer medido. Subir de tier é
// mexer numa linha lá: no Tier 2 da OpenAI (450.000 TPM) o intervalo cai bem
// abaixo do piso histórico de 6s.
// E O RPM ENTRA NA CONTA, porque nem todo provedor tem o mesmo gargalo. Na
// OpenAI o balde de TOKENS aperta mais que o de chamadas; na linha Flash-Lite
// do Google o balde de tokens é folgado e o limite é de CHAMADAS — só pelo TPM
// o intervalo daria menos de 1 segundo, e o lote tomaria 429 na terceira.
//
// O intervalo é o MAIOR dos três — o do balde de tokens, o do limite de
// chamadas, e o piso histórico de 6s. É o mesmo princípio de sempre: errar para
// o lento atrasa; errar para o rápido FALHA, e falha custa a rodada inteira.
const CHAMADAS_POR_MINUTO = TPM_CONTA / (ENTRADA_MAX_MEDIDA_TOKENS + MAX_OUTPUT_TOKENS);
const INTERVALO_EXTRACAO_MS = arredondarParaSegundoCheio(Math.max(
  Math.ceil(60000 / CHAMADAS_POR_MINUTO),
  INTERVALO_POR_RPM_MS,
  PISO_BATCHING_MS,
));

const IA_BATCHING_EXTRACAO = { batching: { batch: { batchSize: 1, batchInterval: INTERVALO_EXTRACAO_MS } }, ...RESPOSTA_COM_CORPO_NO_ERRO };

// Retry para os nós Postgres: SEM onError, um erro transitório (conexão sob
// carga, timeout pontual) num ÚNICO item PARA A EXECUÇÃO INTEIRA — todos os
// itens ainda na fila somem sem nenhum rastro (achado em produção, sessão 7
// cont.¹³, "teste v19": 9 arquivos pequenos enviados, só 6 apareceram no
// dashboard; os outros 3 nunca chegaram nem a ter uma linha `documento`
// criada — consistente com a execução ter sido interrompida por um erro de
// node Postgres no meio do lote, não com falha de extração, que já é
// tolerante a erro). `continueRegularOutput` (como os nós OpenAI já têm)
// impede esse efeito cascata: o item que falhou fica com dado incompleto
// (nunca vira fato — segue N0/pendente, doutrina Arquitetura do Sistema/1 Visão e Doutrina/01), mas os itens
// SEGUINTES no lote continuam sendo processados normalmente.
const PG_RETRY = { onError: 'continueRegularOutput', retryOnFail: true, maxTries: 3, waitBetweenTries: 3000 };

// CADA ITEM COMMITA SOZINHO — e este é o defeito que custou a rodada de 190.
//
// MEDIDO AO VIVO em 27/08/2026, na execução 7172, com `pg_stat_activity`:
//
//   backend 81532, ativo há 13min25, RowExclusiveLock em reconciliacao
//   query: select fn_reconciliar_por_documento('661f…'); select … (11 statements)
//   xact_start = query_start   → batch multi-statement = UMA transação implícita
//
// e sete minutos depois o backend tinha sumido e `reconciliacao` do caso estava
// em ZERO. Nada commitou. **1h52 de execução, 13.942 linhas extraídas e pagas,
// e nenhuma reconciliação.**
//
// (Um backend novo apareceu logo depois, com 2 statements em vez de 11. Se é
// retentativa ou o lote seguinte, não sei — e por isso não está afirmado aqui.
// O que foi medido é a transação implícita, os locks de escrita e o zero
// commitado.)
//
// O modo `single` do nó Postgres — que é o DEFAULT, e por isso ninguém escolheu
// — junta as queries de todos os itens numa transação só. Num lote de 38
// documentos isso nunca apareceu: a transação durava segundos. Em 190 ela dura
// dezenas de minutos, e qualquer coisa que a interrompa apaga o lote inteiro.
//
// `independently` commita item a item. A troca é explícita: perde-se a
// atomicidade do lote, ganha-se que um documento ruim não descarte os 189 bons.
// Num pipeline em que refazer o lote custa uma cota diária de IA e dois dólares,
// e em que a falha por documento JÁ é registrada e mostrada na tela, não há
// dúvida sobre qual dos dois lados vale mais.
const PG_POR_ITEM = { queryBatching: 'independently' };

// Todo nó Code POR ITEM continua o lote quando um item falha.
//
// Antes desta correção o JSON tinha 8 `onError` — os 6 Postgres e os 2 OpenAI — e
// ZERO nos Code. `Preparar Conteudo` chama `getBinaryDataBuffer` (binário
// corrompido, referência de filesystem expirada, arquivo grande demais): um throw
// ali **mata a execução inteira** e todos os itens ainda na fila desaparecem sem
// rastro. É exatamente o bug do "teste v19" (9 arquivos enviados, 6 no dashboard)
// por outra causa, e foi para ele que os nós Postgres ganharam `onError` na
// sessão 7 cont.¹³ — os Code ficaram de fora e ninguém notou porque o invariante
// que confere isso tem lista de nomes hardcoded.
//
// TRÊS nós Code NÃO entram aqui, e a exclusão é o ponto:
//   • `Listar Arquivos` lança quando o formulário vem sem arquivo — abortar é a
//     resposta certa, não há lote para continuar.
//   • `Orcamento do Lote` lança para RECUSAR o lote acima de US$ 3. Pôr `onError`
//     nele desativaria o teto de gasto, que é o oposto do que ele existe para fazer.
//   • `Recompor Conteudo Extraido` (roteamento por formato, ver o nó): se ele
//     lançar, `continueRegularOutput` devolveria o LOTE INTEIRO sem reagrupar
//     — as linhas de planilha que ele existe para juntar voltariam soltas, uma
//     por item, e `Medir Documento` processaria N itens por documento outra
//     vez. É o MESMO fan-out que o roteamento inteiro existe para evitar, só
//     que via falha silenciosa em vez de fio solto no editor. Lote inteiro
//     caindo aqui e aparecendo VERMELHO é o comportamento certo.
const CODE_CONTINUA = { onError: 'continueRegularOutput' };

// Condição do `Roteador de Formato` (Switch) para um formato DETECTADO.
//
// MUDOU DE REGEX SOBRE MIMETYPE PARA IGUALDADE SOBRE FORMATO MEDIDO, e a troca
// é a correção da AMO no roteador. Antes: `regex` contra `$json.content_mime` —
// o mimetype DECLARADO no upload, com os padrões de `PADRAO_MIME`. Um `.txt`
// casava com `csv|^text/plain$` e ia para um extrator que o rejeitava. Agora:
// igualdade contra `$json.formato_detectado`, que `Preparar Conteudo` MEDIU nos
// bytes. Some junto toda a classe de defeito "dois padrões de regex divergindo
// entre o roteador e o nó" — não há mais padrão nenhum para divergir, só um
// nome de formato decidido num lugar só.
const condFormato = (formato) => ({
  options: { caseSensitive: true, typeValidation: 'strict' }, combinator: 'and',
  conditions: [{ leftValue: '={{ $json.formato_detectado }}', rightValue: formato, operator: { type: 'string', operation: 'equals' } }],
});

// Estágio k (k = 1..N-1) repete o que o Parse da tentativa k deixou marcado:
//   IF `Repetir Extracao k?` --true--> `Esperar Retry k` -> `IA Extrair (tentativa k+1)`
//   -> `Parse Extracao (tentativa k+1)`. O IF `false` vai direto ao `Juntar Tentativas`.
const estagiosDeRepeticao = Array.from({ length: TENTATIVAS_MAX_EXTRACAO - 1 }, (_, i) => {
  const k = i + 1;
  const proxima = k + 1;
  const nomeIf = `Repetir Extracao ${k}?`;
  const nomeEsperar = `Esperar Retry ${k}`;
  const nomeIA = `IA Extrair (tentativa ${proxima})`;
  const nomeParse = `Parse Extracao (tentativa ${proxima})`;
  return {
    k, nomeIf, nomeEsperar, nomeIA, nomeParse,
    nos: [
      node(nomeIf, 'n8n-nodes-base.if', 2, {
        conditions: { options: { caseSensitive: true, typeValidation: 'strict' }, combinator: 'and', conditions: [
          { leftValue: '={{ $json.repetir }}', rightValue: true, operator: { type: 'boolean', operation: 'true', singleValue: true } },
        ] },
      }),
      node(nomeEsperar, 'n8n-nodes-base.code', 2, { mode: 'runOnceForAllItems', jsCode: CODE_ESPERAR_RETRY }, CODE_CONTINUA),
      node(nomeIA, 'n8n-nodes-base.httpRequest', 4.2, {
        method: 'POST', url: urlDaChamada(PROV, MODEL_EXTRACAO),
        authentication: 'genericCredentialType',
        genericAuthType: 'httpHeaderAuth',
        sendBody: true, specifyBody: 'json', jsonBody: '={{ JSON.stringify($json.ia_body) }}',
        options: IA_BATCHING_EXTRACAO,
      }, { onError: 'continueRegularOutput', retryOnFail: true, credentials: { httpHeaderAuth: { id: 'REPLACE', name: PROV.credencial } } }),
      node(nomeParse, 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: codeParseExtracao(proxima, nomeEsperar) }, CODE_CONTINUA),
    ],
  };
});

const nodes = [
  node('Intake (Form)', 'n8n-nodes-base.formTrigger', 2, {
    formTitle: 'Intake Oria — Reestruturação',
    formDescription: 'Suba TODOS os arquivos brutos do mandato de uma vez.',
    formFields: { values: [
      { fieldLabel: 'Mandato (nome do caso)', fieldType: 'text', requiredField: true },
      { fieldLabel: 'Arquivos', fieldType: 'file', multipleFiles: true, requiredField: true },
    ] },
  }),

  node('Upsert Caso (Postgres)', 'n8n-nodes-base.postgres', 2.5, {
    // O LIMIAR VEM JUNTO, e de propósito não num nó novo. É a MESMA ida ao
    // banco que já acontece: um nó a mais custaria uma republicação com risco de
    // toggle perdido (`.claude/memory/republicacao-do-n8n-perde-toggles.md`) e
    // uma volta de rede por lote, para buscar um número. `left join lateral` não
    // é preciosismo: sem ele, banco sem a linha do dial devolveria ZERO linha e o
    // `caso_id` sumiria junto — a consulta que lê a configuração não pode
    // derrubar a que cria o caso.
    operation: 'executeQuery', query: "select fn_upsert_caso($1::text) as caso_id, "
      + "(select limiar_auto_clear from estagio_autonomia "
      + "where estagio = 'classificacao_doc_checklist') as limiar_classificacao",
    options: { queryReplacement: "={{ [$json['Mandato (nome do caso)']] }}" },
  }, { credentials: PG_CRED, ...PG_RETRY }),

  node('Listar Arquivos', 'n8n-nodes-base.code', 2, { mode: 'runOnceForAllItems', jsCode: CODE_LISTAR }),

  // O guarda de TAMANHO, antes de qualquer leitura de binario. A recusa vai pelo
  // MESMO `Registrar Recusa` -> `Abortar Lote` da recusa do orcamento (dois
  // caminhos de recusa e' ter um sem tela).
  node('Tamanho cabe?', 'n8n-nodes-base.if', 2, {
    conditions: { options: { caseSensitive: true, typeValidation: 'strict' }, combinator: 'and', conditions: [
      { leftValue: '={{ $json.tamanho_cabe }}', rightValue: true, operator: { type: 'boolean', operation: 'true', singleValue: true } },
    ] },
  }),

  node('Classificar Nome', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_CLASSIFICAR }, CODE_CONTINUA),

  node('Orcamento do Lote', 'n8n-nodes-base.code', 2, { mode: 'runOnceForAllItems', jsCode: CODE_ORCAMENTO }),

  // O CAMINHO DA RECUSA — três nós, e cada um existe por um motivo.
  //
  // `Lote cabe?` decide; `Registrar Recusa` GRAVA a causa no banco (é o que faz
  // a tela do portal parar de dizer "aguarde" sobre um processo morto); e
  // `Abortar Lote` lança, para a execução aparecer VERMELHA no n8n. Sem o
  // último, a execução ficaria verde tendo recusado o lote — e "deu certo" é a
  // última coisa que ela deve dizer.
  node('Lote cabe?', 'n8n-nodes-base.if', 2, {
    conditions: { options: { caseSensitive: true, typeValidation: 'strict' }, combinator: 'and', conditions: [
      { leftValue: '={{ $json.orcamento_cabe }}', rightValue: true, operator: { type: 'boolean', operation: 'true', singleValue: true } },
    ] },
  }),

  // As DUAS recusas (tamanho e orcamento) convergem aqui por um Merge em `append`,
  // nunca por duas conexoes cruas no mesmo input (a regra do Teste V45). Elas sao
  // mutuamente exclusivas: o tamanho recusa ANTES de o orcamento existir.
  node('Juntar Recusas', 'n8n-nodes-base.merge', 3, {
    mode: 'append', numberInputs: 2,
  }),

  node('Registrar Recusa', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_registrar_falha_execucao($1::uuid, $2::text, $3::text, $4::text, null) as r',
    options: { queryReplacement: "={{ [$json.caso_id, $('Intake (Form)').first().json['Mandato (nome do caso)'], 'orcamento', $json.orcamento_mensagem] }}" },
  }, { credentials: PG_CRED, ...PG_RETRY }),

  node('Abortar Lote', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForAllItems',
    jsCode: `throw new Error($input.first().json.orcamento_mensagem || 'Lote recusado pelo orcamento.');`,
  }),
  // CAMADA 1 — o texto do PDF lido na própria instância, antes de qualquer
  // chamada. Nó NATIVO do n8n; não manda nada para fora e não custa nada.
  //
  // `onError: continueRegularOutput` é o que torna a adição segura: PDF sem
  // camada de texto (escaneado, que é o caso em que este nó falha) segue o
  // caminho de sempre — o documento vai como imagem e as camadas 2 e 3 se calam
  // para ele. O pior caso desta mudança é o comportamento de ontem, nunca um
  // lote perdido.
  node('Extrair Texto', 'n8n-nodes-base.extractFromFile', 1, {
    operation: 'pdf', binaryPropertyName: 'data', options: { joinPages: true },
  }, { onError: 'continueRegularOutput' }),
  node('Preparar Conteudo', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_PREPARAR_CONTEUDO }, CODE_CONTINUA),

  // O ROTEADOR DE FORMATO — a correção do fan-out cego que o dono pendurou no
  // editor (5 nós "Extract from..." em paralelo, todos recebendo o MESMO
  // item). Aqui cada documento vai para EXATAMENTE UM extrator, por
  // `content_mime` (decidido em `Preparar Conteudo`, logo atrás). As MESMAS
  // strings de `PADRAO_MIME` que `Preparar Conteudo` usa — nunca uma segunda
  // cópia dos padrões, que é como um item passaria a ser roteado para um
  // extrator e classificado como outro sem nenhum teste notar.
  //
  // FALLBACK ('outros'): mimetype que não bate com PDF/imagem/CSV/XLSX/XLS/XML
  // — hoje isso é o "conteudo nao suportado" que `Preparar Conteudo` já
  // declarava. Sem extrator, vai direto para o Merge (regra 1: continua
  // abrindo a pendência, nunca inventa suporte que não existe).
  node('Roteador de Formato', 'n8n-nodes-base.switch', 3, {
    mode: 'rules',
    rules: { values: [
      { outputKey: 'pdf', conditions: condFormato('pdf') },
      { outputKey: 'xlsx', conditions: condFormato('xlsx') },
      { outputKey: 'xls', conditions: condFormato('xls') },
    ] },
    options: { fallbackOutput: 'extra' },
  }),

  // OS DOIS EXTRATORES BINÁRIOS — e "dois" é o número depois da correção da
  // AMO. Eram quatro: `Extrair CSV` e `Extrair XML` foram REMOVIDOS, porque
  // pediam ao n8n que devolvesse o texto que os bytes já são.
  //
  // POR QUE REMOVER EM VEZ DE CORRIGIR O ROTEAMENTO ATÉ ELES. O `Extract From
  // File` valida o mimeType do binário e recusa o que não está na lista dele —
  // é dele a mensagem `The file selected in 'Input Binary Field' is not in csv
  // format` que apareceu 60 vezes no lote da AMO. Essa lista é do n8n, não
  // deste projeto, e não há padrão de roteamento que a torne conhecida daqui:
  // acertar hoje não impede que o próximo mimetype legítimo (`text/tab-separated
  // -values`, um `.txt` de outra origem) caia na mesma recusa. Texto, este
  // pipeline lê sozinho — `parseCsv`/`formaDoTexto` em `Preparar Conteudo`, que
  // é o que ele fazia até 11/09 e funcionava. Sobram aqui só os formatos que
  // REALMENTE precisam de um decodificador binário: XLSX (ZIP+XML) e XLS (OLE2).
  //
  // `onError: continueRegularOutput` nos dois: um XLSX corrompido é falha de
  // CONTEÚDO legítima e não pode derrubar os outros documentos do lote. O que
  // MUDOU é o que acontece depois — `Recompor Conteudo Extraido` agora
  // RECONHECE o item de erro que o n8n emite (`{error: "..."}`, sem `caso_id`) e
  // preserva a pendência. Até 12/09 ele tratava esse item como LINHA DE
  // PLANILHA, e a mensagem de erro virava o conteúdo do documento.
  node('Extrair XLSX', 'n8n-nodes-base.extractFromFile', 1, {
    operation: 'xlsx', binaryPropertyName: 'data',
  }, { onError: 'continueRegularOutput' }),
  node('Extrair XLS', 'n8n-nodes-base.extractFromFile', 1, {
    operation: 'xls', binaryPropertyName: 'data',
  }, { onError: 'continueRegularOutput' }),
  // UM ITEM POR PLANILHA ANTES DO MERGE -- ver o comentário de codeAgruparPlanilha.
  // SEM `onError`, como o Recompor: falhar aqui tem de ser visível, não virar
  // planilha vazia. Nó Code, não Postgres: não substitui o contexto do lote.
  node('Agrupar Linhas XLSX', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForAllItems', jsCode: codeAgruparPlanilha('Extrair XLSX'),
  }),
  node('Agrupar Linhas XLS', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForAllItems', jsCode: codeAgruparPlanilha('Extrair XLS'),
  }),

  // O MERGE QUE CONVERGE OS 7 RAMOS DO ROTEADOR — a resposta canônica do n8n
  // para "vários caminhos, um documento por vez", a MESMA que `Juntar Ramos` e
  // `Juntar Extraidos` já usam nesta cadeia (nunca convergência crua: foi ela
  // que perdeu 19 de 35 documentos no "Teste V45"). 7 entradas: pdf (via
  // `Extrair Texto`), imagem (direto), csv/xlsx/xls/xml (via cada extrator) e
  // o fallback 'outros' (direto).
  node('Juntar Extracao de Conteudo', 'n8n-nodes-base.merge', 3, {
    mode: 'append', numberInputs: 4,
  }),
  // SEM `onError`, de propósito — ver o comentário de `CODE_CONTINUA` acima.
  node('Recompor Conteudo Extraido', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForAllItems', jsCode: CODE_RECOMPOR_EXTRACAO,
  }),

  node('Medir Documento', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_MEDIR_DOCUMENTO }, CODE_CONTINUA),

  // RAMO LATERAL: nada depende da saída deste node (HTTP substitui o item).
  //
  // RELIGADO EM 07/10/2026, desligado desde 17/07. O motivo do desligamento era o
  // bug "Converting circular structure to JSON" do HTTP Request com binário
  // (n8n-io/n8n#3089, #10096). MEDIDO em 07/10 num workflow descartável (já apagado):
  // webhook -> Code (binário renomeado para data, caso_id/nome_original como em
  // Preparar Conteudo) -> HTTP Request 4.2 com EXATAMENTE estes parâmetros — rodou com
  // binário e a execução foi salva (saveDataSuccessExecution=all); o bug NÃO
  // reproduziu. NÃO testado: o editor rodando o workflow inteiro manualmente (o
  // sintoma de julho era no editor) — conferir depois da republicação.
  //
  // O custo de ficar desligado: o bucket `documentos` de produção tinha ZERO objetos
  // enquanto `documento_versao.arquivo_ref` gravava caso_id/nome como se o arquivo
  // estivesse lá (regra 1 e 7), e não foi possível reextrair os mapas da dívida dos
  // mandatos reais por falta de original para baixar.
  //
  // A CHAVE vem de `$json.arquivo_ref` (calculado em Preparar Conteudo, o mesmo campo
  // que o Registrar Documento grava) e NAO do nome: o Storage devolve 400 InvalidKey
  // para não-ASCII mesmo com encodeURIComponent (medido: `sonda teste ç.pdf` 400,
  // `sonda teste.pdf` 200, 193 bytes). Ver chaveDoOriginal em lib/hash.mjs. Por ser
  // ASCII por construção (hex + [a-z0-9]), a URL não precisa de encodeURIComponent.
  //
  // AUTENTICAÇÃO: credencial `httpCustomAuth` com os DOIS cabeçalhos (apikey e
  // Authorization: Bearer) restrita ao domínio do Supabase — medida funcionando em
  // 07/10. Sai o `apikey: COLE_A_SERVICE_ROLE_KEY_AQUI` em texto no nó: era segredo
  // colado em lugar de leitura. O id real NÃO entra no repositório (REPLACE, resolvido
  // na republicação por nome / N8N_CRED_IDS).
  //
  // `onError: continueRegularOutput` É O QUE IMPEDE O RAMO LATERAL DE DERRUBAR A
  // INGESTÃO: sem ele, um 4xx/5xx do Storage lança e a execução morre. Medido em
  // 27/08 (ESTADO.md): a execução morreu no Upload Storage DEPOIS de o ramo irmão
  // gravar documentos e extrações, e não fechou o lote (o portal acusa lote_nao_fechou)
  // — não "antes de classificar/extrair"; a ordem dos dois ramos não é garantida. Falha engolida em silêncio seria a regra 7, então o
  // sinal positivo está no `Resumo de Custo`: quantos originais ficaram guardados e
  // quantos não (e quais). O sinal vive no painel da execução do n8n; persistir no
  // banco (coluna em lote_execucao) pede migration e ficou de fora de propósito.
  // SEM retryOnFail: com continueRegularOutput o nó nunca lança, e a suspeita registrada
  // em `node()` é que o retry do n8n depende do lançamento.
  //
  // COTA: zero chamadas de IA. O RPD 500 é dos provedores de IA; o Storage não entra.
  node('Upload Storage', 'n8n-nodes-base.httpRequest', 4.2, {
    method: 'POST',
    // A REF DO PROJETO É DADO DE CONFIGURAÇÃO, NÃO SEGREDO: é a URL pública da
    // API do Supabase, a mesma que o portal usa em `NEXT_PUBLIC_SUPABASE_URL`.
    url: '=https://mrcabcaotblleojxnsxc.supabase.co/storage/v1/object/documentos/{{ $json.arquivo_ref }}',
    authentication: 'genericCredentialType',
    genericAuthType: 'httpCustomAuth',
    sendHeaders: true, headerParameters: { parameters: [
      { name: 'x-upsert', value: 'true' },
    ] },
    sendBody: true, contentType: 'binaryData', inputDataFieldName: 'data',
  }, { credentials: { httpCustomAuth: { id: 'REPLACE', name: 'Supabase Storage (service_role)' } }, onError: 'continueRegularOutput' }),

  node('Precisa Fallback?', 'n8n-nodes-base.if', 2, {
    conditions: { options: { caseSensitive: true, typeValidation: 'strict' }, combinator: 'and', conditions: [
      { leftValue: '={{ $json.precisa_fallback_ia }}', rightValue: true, operator: { type: 'boolean', operation: 'true', singleValue: true } },
    ] },
  }),

  node('Montar Req Classif', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_REQ_CLASSIF }, CODE_CONTINUA),

  // Falha do provedor NÃO derruba o workflow: segue com a resposta de erro, o
  // Parse produz confiança 0 → pendência de classificação (fail-safe).
  //
  // Auth via credencial Header Auth do n8n — sem `$env`, que é bloqueado por
  // padrão. O NOME da credencial e o header que ela preenche saem do provedor
  // ativo (`lib/provedor.mjs`): na OpenAI é "Authorization: Bearer sk-...", no
  // Google é "x-goog-api-key: ...". A chave NUNCA vai na URL como `?key=`: a URL
  // do nó aparece na tela de execução e no log, e isso é segredo em lugar de
  // leitura.
  node('IA Classificar', 'n8n-nodes-base.httpRequest', 4.2, {
    method: 'POST', url: urlDaChamada(PROV, MODEL_CLASSIFICACAO),
    authentication: 'genericCredentialType',
    genericAuthType: 'httpHeaderAuth',
    sendBody: true, specifyBody: 'json', jsonBody: '={{ JSON.stringify($json.ia_body) }}',
    options: IA_BATCHING,
  }, { onError: 'continueRegularOutput', retryOnFail: true, credentials: { httpHeaderAuth: { id: 'REPLACE', name: PROV.credencial } } }),

  node('Parse Classif', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_PARSE_CLASSIF }, CODE_CONTINUA),

  // JUNTA OS DOIS RAMOS DO `Precisa Fallback?` — e existe porque a ausência dele
  // custou 19 dos 35 documentos do "Teste V45 - Canastra".
  //
  // Antes, `Precisa Fallback?`[false] e `Parse Classif` apontavam AMBOS
  // para o `Registrar Documento`: duas conexões CRUAS no MESMO input. O n8n não
  // garante uma execução por conexão nesse arranjo — no V45 só o ramo do fallback
  // propagou, e os 19 documentos do ramo direto (justamente os centrais: Balanço,
  // DRE, DFC, DMPL, DVA, balancetes, razão, faturamento) desapareceram ENTRE
  // `Registrar Documento` e `Gravar Campos`. Zero linha, zero evento de extração,
  // zero pendência — o dado não foi extraído errado, ele nunca foi pedido.
  //
  // O Merge em `append` é a resposta canônica do n8n para convergência: uma
  // execução, um lote com os itens dos dois ramos, uma cadeia linear de
  // `pairedItem` rio abaixo. É o que devolve a corrente única que o grafo
  // presumia ter.
  node('Juntar Ramos', 'n8n-nodes-base.merge', 3, {
    mode: 'append', numberInputs: 2,
  }),

  // $14/$15/$16 usam notação nomeada (p_justificativa=>, p_fingerprint_extracao=>,
  // p_cnpj=>) para pular o p_threshold (14º parâmetro posicional, mantém o
  // default 0.7) sem precisar repeti-lo explicitamente. `p_cnpj` é da 0170 —
  // o parâmetro existe no banco desde então; esta é a fatia que finalmente o
  // preenche, lendo `$json.cnpj` (0169/0170/0171 no banco, este nó no n8n).
  node('Registrar Documento', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_registrar_documento($1::uuid,$2::text,$3::text,$4::text,$5::text,$6::numeric,$7::text,$8::origem_arquivo,$9::text,$10::text,$11::boolean,$12::text,$13::legibilidade, p_justificativa=>$14::text, p_fingerprint_extracao=>$15::text, p_cnpj=>$16::text) as r',
    options: { ...PG_POR_ITEM, queryReplacement: `={{ [$json.caso_id, $json.entidade || null, $json.periodo_tipo || null, $json.periodo_ref || null, $json.tipo_taxonomia || null, $json.confianca, $json.fonte, 'supabase_storage', $json.arquivo_ref, $json.nome_original, $json.assinado, $json.hash || null, 'ok', $json.justificativa || null, '${FINGERPRINT_EXTRACAO}', $json.cnpj || null] }}` },
  }, { credentials: PG_CRED, ...PG_RETRY }),

  node('Recomputar Completude', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery', query: 'select fn_recomputar_completude($1::uuid) as resultado',
    options: { queryReplacement: "={{ $('Upsert Caso (Postgres)').first().json.caso_id }}" },
  }, { credentials: PG_CRED, ...PG_RETRY }),

  node('Recompor Contexto', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForAllItems', jsCode: CODE_RECOMPOR_CONTEXTO,
  }, CODE_CONTINUA),

  // O CURTO-CIRCUITO DO DEDUP (0118). A `fn_registrar_documento` já respondeu se
  // este arquivo foi extraído antes com o MESMO prompt+modelo+esquema e se aquela
  // extração tem linha no banco. Quando sim, não há nada a pedir à OpenAI: o dado
  // já está lá, sob a mesma versão, e o item pula direto para a reconciliação.
  //
  // O IF fica AQUI, e não dentro do `Montar Req Extracao`, por uma restrição do
  // n8n que a 0026 já tinha mapeado: aquele nó é `runOnceForEachItem` e não pode
  // devolver zero itens. Filtrar com um IF é o jeito que o motor oferece.
  node('Extracao ja feita?', 'n8n-nodes-base.if', 2, {
    conditions: { options: { caseSensitive: true, typeValidation: 'strict' }, combinator: 'and', conditions: [
      { leftValue: '={{ $json.reaproveitou_extracao }}', rightValue: true, operator: { type: 'boolean', operation: 'true', singleValue: true } },
    ] },
  }),

  // E o Merge que junta quem extraiu com quem não precisou. Merge, e não duas
  // conexões cruas no mesmo input: foi convergência crua que fez 19 de 35
  // documentos desaparecerem no Teste V45 (ver `Juntar Ramos`).
  node('Juntar Extraidos', 'n8n-nodes-base.merge', 3, {
    mode: 'append', numberInputs: 2,
  }),

  node('Montar Req Extracao', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_REQ_EXTRACAO }, CODE_CONTINUA),

  // CAMADA 2 — um item por BLOCO. Vê o lote inteiro porque é fan-out (N → M).
  node('Fatiar Extracao', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForAllItems', jsCode: CODE_FATIAR_EXTRACAO,
  }, CODE_CONTINUA),
  node('IA Extrair', 'n8n-nodes-base.httpRequest', 4.2, {
    method: 'POST', url: urlDaChamada(PROV, MODEL_EXTRACAO),
    authentication: 'genericCredentialType',
    genericAuthType: 'httpHeaderAuth',
    sendBody: true, specifyBody: 'json', jsonBody: '={{ JSON.stringify($json.ia_body) }}',
    options: IA_BATCHING_EXTRACAO,
  }, { onError: 'continueRegularOutput', retryOnFail: true, credentials: { httpHeaderAuth: { id: 'REPLACE', name: PROV.credencial } } }),

  node('Parse Extracao', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_PARSE_EXTRACAO }, CODE_CONTINUA),

  // OS ESTÁGIOS DE REPETIÇÃO (`TENTATIVAS_MAX_EXTRACAO - 1` deles), DESENROLADOS e
  // não em laço, por uma razão do motor e não de gosto: com um laço de volta ao
  // `IA Extrair`, o `Juntar Blocos` (runOnceForAllItems) rodaria uma vez com os
  // blocos que deram certo e outra com os repetidos — o documento sairia duas vezes,
  // a primeira incompleta, e o banco gravaria as duas. Desenrolado, TODOS os
  // caminhos convergem no `Juntar Tentativas` (Merge, a mesma resposta que o
  // projeto já deu a `Juntar Ramos` e `Juntar Extraidos`) e o Juntar Blocos roda UMA
  // vez. Estágio sem bloco a repetir não executa: lote sem falha transitória não
  // gasta um nó nem um segundo a mais.
  ...estagiosDeRepeticao.flatMap((e) => e.nos),

  node('Juntar Tentativas', 'n8n-nodes-base.merge', 3, {
    mode: 'append', numberInputs: TENTATIVAS_MAX_EXTRACAO,
  }),

  // CAMADA 3 — junta os blocos de volta em UM item por documento e confere a
  // cobertura. Daqui para a frente o grafo é idêntico ao de sempre: um item por
  // documento, com `campos` e `falha_motivo`.
  node('Juntar Blocos', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForAllItems', jsCode: CODE_JUNTAR_BLOCOS,
  }, CODE_CONTINUA),
  // O NÓ POSTGRES SUBSTITUI O ITEM PELO RESULTADO DA QUERY, e foi assim que a
  // reconciliação passou 11 dias desligada em silêncio (rodadas v42 a v47).
  // Este nó devolvia só `{n_campos}`; os DOIS nós seguintes leem
  // `$json.documento_id` e passaram a receber `undefined`, então
  // `fn_registrar_diagnostico` e `fn_reconciliar_por_documento` eram chamadas
  // com NULL e respondiam "documento não encontrado" — retorno válido, nó
  // VERDE, zero linha gravada. Nada na tela dizia que as checagens não rodaram.
  //
  // Por isso o que o item precisa adiante viaja de volta COMO COLUNA da própria
  // query, em vez de ser buscado com `$('nó').item`: pareamento por item já
  // quebrou aqui uma vez (o fan-out do fatiamento, 13/08) e a doutrina desde
  // então é que o item carrega o próprio contexto.
  node('Gravar Campos (Sombra)', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: [
      'select fn_registrar_campos_extraidos($1::uuid, $2::jsonb, p_falha_motivo=>$3::text, p_tem_dado_financeiro=>$4::boolean) as n_campos,',
      '       $5::uuid as documento_id, $1::uuid as documento_versao_id, $6::jsonb as diagnostico',
    ].join('\n'),
    options: { ...PG_POR_ITEM, queryReplacement: "={{ [$json.documento_versao_id, JSON.stringify($json.campos), $json.falha_motivo || null, $json.diagnostico?.tem_dado_financeiro ?? null, $json.documento_id, JSON.stringify($json.diagnostico ?? null)] }}" },
  }, { credentials: PG_CRED, ...PG_RETRY }),

  // Diagnóstico (E1/E2, N1): entidade preenche a lacuna quando ainda vazia;
  // tipo/período/legibilidade só CONFEREM contra o que já está registrado —
  // divergência vira pendência tipada (tipo_incorreto/periodo_incorreto/
  // entidade_incorreta/arquivo_ilegivel), nunca corrige sozinho (anti-
  // ancoragem, Arquitetura do Sistema/1 Visão e Doutrina/01). Roda ANTES da reconciliação para que ela já veja a
  // entidade recém-preenchida, se for o caso.
  // Mesma razão do nó anterior: o `documento_id` volta como coluna para que o
  // `Reconciliar (Classe A)` tenha o que passar. Sem isso ele recebe `{resultado}`
  // e a cadeia inteira de checagens morre calada.
  // 0172: o `p_cnpj` entra por NOME (`p_cnpj=>$13`) e não posicionalmente, porque
  // o $12 já é dos FATOS na segunda linha da mesma query — trocar a ordem dos
  // binds para encaixar o CNPJ no 12º moveria os fatos e quebraria a chamada de
  // `fn_registrar_fatos` em silêncio. É o mesmo motivo de o `Registrar Documento`
  // usar notação nomeada para os três últimos.
  node('Registrar Diagnostico', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: [
      'select fn_registrar_diagnostico($1::uuid,$2::uuid,$3::text,$4::boolean,$5::text,$6::text,$7::text,$8::legibilidade,$9::text,$10::text,$11::text, p_cnpj=>$13::text) as resultado,',
      // OS FATOS ENTRAM NA MESMA QUERY, e não em nó novo. Dois motivos, os dois
      // medidos nesta casa: nó a mais é aresta a mais no canvas (o layout.test
      // existe porque o canvas ficou ilegível), e principalmente — o nó Postgres
      // SUBSTITUI o item pelo resultado da query, então cada nó novo é mais uma
      // chance de perder `documento_id` pelo caminho. Foi assim que a
      // reconciliação passou onze dias parada em silêncio (v47).
      '       fn_registrar_fatos($2::uuid,$12::jsonb) as fatos,',
      '       $1::uuid as documento_id',
    ].join('\n'),
    options: { ...PG_POR_ITEM, queryReplacement: "={{ [$json.documento_id, $json.documento_versao_id, $json.diagnostico?.entidade ?? null, $json.diagnostico?.tipo_confirma ?? null, $json.diagnostico?.tipo_sugerido ?? null, $json.diagnostico?.periodo_tipo ?? null, $json.diagnostico?.periodo_referencia ?? null, $json.diagnostico?.legibilidade ?? null, $json.diagnostico?.nota_legibilidade ?? null, $json.diagnostico?.resumo ?? null, $json.diagnostico?.justificativa ?? null, $json.diagnostico?.fatos ? JSON.stringify($json.diagnostico.fatos) : null, $json.diagnostico?.cnpj ?? null] }}" },
  }, { credentials: PG_CRED, ...PG_RETRY }),

  // E3 (Classe A, N1): roda as checagens aritméticas relevantes ao tipo do
  // documento recém-extraído (Arquitetura do Sistema/2 Especificação/04). Só precisa do documento_id — a função
  // resolve caso/entidade/período sozinha (N8N continua stateless). Gera
  // pendência tipada quando diverge ou quando falta pré-condição; nunca
  // escreve "fato" numa base viva (anti-ancoragem, Arquitetura do Sistema/1 Visão e Doutrina/01).
  // O ESCOPO PASSA A SER DECLARADO (0152). As outras oito checagens leem
  // (caso, entidade, período) e NÃO o documento — o documento só entrega a
  // chave —, então rodá-las por documento é repetir trabalho idêntico: no
  // araucária, 190 execuções para 82 chaves, e a Araucária Serraria sozinha tem
  // 80 documentos. Aqui fica só a árvore, que é de fato intra-documento; as
  // outras rodam UMA vez, no `Reconciliar Lote`.
  node('Reconciliar (Classe A)', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: "select fn_reconciliar_por_documento($1::uuid, 'documento') as resultado",
    options: { queryReplacement: '={{ [$json.documento_id] }}', ...PG_POR_ITEM },
  }, { credentials: PG_CRED, ...PG_RETRY }),

  // AS CHECAGENS DO CASO, UMA VEZ (0152).
  //
  // `executeOnce` porque a pergunta é do LOTE: `fn_reconciliar_caso` descobre
  // sozinha quais (entidade, período, tipo) existem e roda cada checagem uma vez
  // por chave. É o nó que substitui as ~8.500 invocações que o araucária pedia.
  //
  // Ele vem DEPOIS do `Reconciliar (Classe A)` e não em paralelo: a árvore
  // intra-documento tem de falar primeiro (0133) — com totais impressos dos dois
  // lados, Ativo = Passivo + PL fecha mesmo faltando contas no meio.
  node('Reconciliar Lote', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_reconciliar_caso($1::uuid) as resultado',
    options: {
      queryReplacement: "={{ [$('Upsert Caso (Postgres)').first().json.caso_id] }}",
    },
  }, { credentials: PG_CRED, ...PG_RETRY, executeOnce: true }),

  // O custo do lote em UM painel, no fim da cadeia. `runOnceForAllItems` porque
  // a pergunta é do LOTE, não do documento — e `onError` porque um resumo que
  // derruba o lote que ele resume seria a pior troca possível.
  node('Resumo de Custo', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForAllItems', jsCode: CODE_RESUMO_CUSTO,
  }, { onError: 'continueRegularOutput' }),

  // O CUSTO PASSA A DURAR (0115). O `Resumo de Custo` sempre soube quanto o lote
  // custou; o número morria na saída da execução do n8n, e responder "quanto
  // gastamos neste mandato" exigia abrir o n8n e ler um JSON. Aqui ele vira
  // linha de tabela, e o painel do portal passa a somar.
  //
  // `$execution.id` NÃO É DETALHE — É O QUE IMPEDE O CUSTO DE DOBRAR. Este nó
  // roda DUAS VEZES por lote (uma por ramo do `Precisa Fallback?`) e, desde a
  // correção de 14/08, as duas passadas trazem o total INTEIRO. Sem uma chave
  // por execução, seriam duas linhas e todo custo sairia 2×. A `0115` tem
  // `unique (caso_id, execucao_ref)` e faz `on conflict do update`: a segunda
  // passada reescreve a primeira com o mesmo valor.
  //
  // O resumo vai INTEIRO, como jsonb — a função escolhe o que conhece. Assim um
  // campo novo no relatório não pede migration de assinatura, e não existe
  // ordem de argumentos para alguém trocar sem querer.
  node('Gravar Uso do Lote', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_registrar_uso_lote($1::uuid,$2::text,$3::jsonb) as resultado',
    options: {
      queryReplacement:
        "={{ [$('Upsert Caso (Postgres)').first().json.caso_id, String($execution.id), JSON.stringify($json)] }}",
    },
  }, { credentials: PG_CRED, ...PG_RETRY }),

  // A EXECUÇÃO PASSA A EXISTIR NO BANCO ANTES DE TERMINAR (0156).
  //
  // POR QUE ELE FICA AQUI, logo depois de `Lote cabe?` aprovar. `lote_execucao`
  // só era escrita pelo `Gravar Uso do Lote`, que é o penúltimo nó da cadeia:
  // a rodada só deixava rastro se a rodada desse certo. Quando o araucária (190
  // documentos) foi cancelado à mão depois de 1h52, a tabela ficou VAZIA — e com
  // ela foi embora `documentos_fatiados`, que era o número de que a investigação
  // da sub-extração precisava. O n8n descarta os dados de uma execução cancelada,
  // então não havia segunda via.
  //
  // `executeOnce` porque a pergunta é do LOTE. E ele grava o PLANO, não medição:
  // quantos documentos entraram, quantas chamadas o orçamento previu (contando os
  // blocos do fatiamento) e que fração da cota do dia isso reserva. O fechamento
  // continua sendo do `Gravar Uso do Lote`, que agora carimba `fechado_em`.
  //
  // PG_RETRY, e ele NÃO pode derrubar o lote: instrumentação que vira ponto de
  // falha é o oposto do que ela existe para fazer. A função também é tolerante
  // por dentro (devolve motivo em vez de lançar).
  node('Abrir Lote', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery', query: 'select fn_abrir_lote_execucao($1::uuid, $2::text, $3::jsonb) as resultado',
    options: {
      queryReplacement:
        "={{ [$('Upsert Caso (Postgres)').first().json.caso_id, String($execution.id), JSON.stringify({ documentos_planejados: $items().length, chamadas_planejadas: $json.orcamento_chamadas ?? null, cota_fracao_planejada: $json.cota_fracao ?? null, custo_estimado_usd: $json.orcamento_estimado_usd ?? null, orcamento_versao: $json.orcamento_versao ?? null })] }}",
    },
  }, { executeOnce: true, credentials: PG_CRED, ...PG_RETRY }),

  // A CONFERÊNCIA DE FORA (0112), o último nó do canvas de propósito: ela pergunta
  // se TODO documento registrado passou pela extração. As três camadas de
  // cobertura medem o que voltou de uma chamada FEITA; nenhuma delas vê a chamada
  // que não aconteceu — e foi assim que o V45 entregou 16 de 35 documentos com o
  // checklist verde. Roda uma vez por lote, não gasta IA, e a saída (`lote_integro`)
  // é o número que decide se a rodada vale.
  node('Conferir Lote', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery', query: 'select fn_conferir_lote($1::uuid) as resultado',
    options: { queryReplacement: "={{ $('Upsert Caso (Postgres)').first().json.caso_id }}" },
  }, { credentials: PG_CRED, ...PG_RETRY }),
];

const connections = {
  'Intake (Form)': { main: [[{ node: 'Upsert Caso (Postgres)', type: 'main', index: 0 }]] },
  'Upsert Caso (Postgres)': { main: [[{ node: 'Listar Arquivos', type: 'main', index: 0 }]] },
  'Listar Arquivos': { main: [[{ node: 'Tamanho cabe?', type: 'main', index: 0 }]] },
  'Tamanho cabe?': { main: [
    [{ node: 'Classificar Nome', type: 'main', index: 0 }],     // true — segue
    [{ node: 'Juntar Recusas', type: 'main', index: 0 }],       // false — grava e aborta (o MESMO caminho do orcamento)
  ] },
  'Juntar Recusas': { main: [[{ node: 'Registrar Recusa', type: 'main', index: 0 }]] },
  'Classificar Nome': { main: [[{ node: 'Preparar Conteudo', type: 'main', index: 0 }]] },
  'Registrar Recusa': { main: [[{ node: 'Abortar Lote', type: 'main', index: 0 }]] },
  // fan-out: upload (lateral) + roteador por formato (cadeia principal)
  // O `Roteador de Formato` entra AQUI, e não antes do preparo: neste ponto o
  // binário ainda existe (o preparo o repassa) e o `content_part` já carrega
  // ALGO (real, para pdf/imagem; placeholder, para o resto) dentro do json —
  // então o fato de os extratores descartarem o binário deixa de ter
  // consequência. `Recompor Conteudo Extraido`, depois do Merge, recompõe o
  // contexto lendo o `Preparar Conteudo`, que É ancestral dele (um ramo irmão
  // não seria — ver o teste "aponta para um ANCESTRAL, nunca para um irmão").
  'Preparar Conteudo': { main: [[
    { node: 'Upload Storage', type: 'main', index: 0 },
    { node: 'Roteador de Formato', type: 'main', index: 0 },
  ]] },
  // CADA SAÍDA VAI PARA EXATAMENTE UM DESTINO — nunca fan-out cego (a auditoria
  // dos 5 nós "Extract from..." do dono era exatamente o oposto disto: os 5
  // recebiam o MESMO item, sem Switch nenhum decidindo). A ORDEM das saídas
  // aqui é a ORDEM de `rules.values` no nó (pdf/xlsx/xls), com o fallback por
  // último.
  //
  // O FALLBACK AGORA CARREGA TRÊS FORMATOS RESOLVIDOS, e isso é o desenho, não
  // uma sobra: `imagem`, `texto` e `xml` já saem de `Preparar Conteudo` com o
  // `content_part` DEFINITIVO (a imagem em base64, o texto lido do buffer).
  // Eles não têm o que extrair — vão direto ao Merge. Junto vai `desconhecido`,
  // que também já tem o seu (a pendência de formato não suportado, agora
  // dizendo o que o arquivo É e não só o que ele alegava ser).
  'Roteador de Formato': { main: [
    [{ node: 'Extrair Texto', type: 'main', index: 0 }],
    [{ node: 'Extrair XLSX', type: 'main', index: 0 }],
    [{ node: 'Extrair XLS', type: 'main', index: 0 }],
    [{ node: 'Juntar Extracao de Conteudo', type: 'main', index: 3 }],
  ] },
  'Extrair Texto': { main: [[{ node: 'Juntar Extracao de Conteudo', type: 'main', index: 0 }]] },
  'Extrair XLSX': { main: [[{ node: 'Agrupar Linhas XLSX', type: 'main', index: 0 }]] },
  'Extrair XLS': { main: [[{ node: 'Agrupar Linhas XLS', type: 'main', index: 0 }]] },
  'Agrupar Linhas XLSX': { main: [[{ node: 'Juntar Extracao de Conteudo', type: 'main', index: 1 }]] },
  'Agrupar Linhas XLS': { main: [[{ node: 'Juntar Extracao de Conteudo', type: 'main', index: 2 }]] },
  'Juntar Extracao de Conteudo': { main: [[{ node: 'Recompor Conteudo Extraido', type: 'main', index: 0 }]] },
  'Recompor Conteudo Extraido': { main: [[{ node: 'Medir Documento', type: 'main', index: 0 }]] },
  // O ORÇAMENTO ENTRA AQUI, e não antes do preparo do conteúdo (onde ficava até
  // a rodada de 18/08). Este é o primeiro ponto em que o lote inteiro está
  // visível de uma vez COM o documento já medido — linhas com número e número de
  // blocos —, e ainda é o último ponto antes de qualquer gasto: a primeira
  // chamada à OpenAI é o `IA Classificar`, logo depois do `Precisa
  // Fallback?`, e nenhum documento foi registrado no banco até o `Registrar
  // Documento`, muito mais adiante.
  'Medir Documento': { main: [[{ node: 'Orcamento do Lote', type: 'main', index: 0 }]] },
  'Orcamento do Lote': { main: [[{ node: 'Lote cabe?', type: 'main', index: 0 }]] },
  // O `Abrir Lote` é um RAMO TERMINAL, e isso não é estilo — é a correção de um
  // defeito que chegou à produção em 31/08, na primeira rodada com ele.
  //
  // Ele nasceu INLINE (`Lote cabe?` -> `Abrir Lote` -> `Precisa Fallback?`), e nó
  // Postgres SUBSTITUI o item pelo resultado da query. O item que carregava
  // `caso_id`, `nome_original` e o binário virou `{resultado:{aberto,
  // lote_execucao_id}}`; o `Registrar Documento`, rio abaixo, leu `$json.caso_id`
  // como `undefined` e o insert morreu com `Failing row contains (uuid, null,
  // null, ...)`. ZERO de 38 documentos registrados, com a execução VERDE em 37s.
  // E `executeOnce` piorava: 38 itens viravam 1 antes mesmo disso.
  //
  // É a MESMA falha da v47 (`Gravar Campos` substituindo o item e a reconciliação
  // parando onze dias em silêncio) — a lição estava escrita na memória do
  // repositório e foi reintroduzida por um nó novo no lugar errado.
  //
  // Como ramo terminal ele não toca o fluxo: o `Lote cabe?` continua entregando
  // o item INTEIRO ao `Precisa Fallback?`, e a abertura do lote acontece ao lado.
  // É o mesmo arranjo do `Upload Storage`, e pela mesma razão.
  //
  // A ORDEM DAS DUAS CONEXÕES IMPORTA: o `Abrir Lote` vem primeiro para a linha
  // do lote existir antes de a extração começar — que é a única coisa que a 0156
  // promete.
  'Lote cabe?': { main: [
    [
      { node: 'Abrir Lote', type: 'main', index: 0 },           // true — abre o lote (ramo terminal)
      { node: 'Precisa Fallback?', type: 'main', index: 0 },    // ...e o item SEGUE inteiro
    ],
    [{ node: 'Juntar Recusas', type: 'main', index: 1 }],       // false — grava e aborta
  ] },
  // Os dois ramos entram em INPUTS DIFERENTES do Merge (0 e 1) — nunca mais duas
  // conexões cruas no mesmo input, que é o que comeu 19 documentos no V45.
  'Precisa Fallback?': { main: [
    [{ node: 'Montar Req Classif', type: 'main', index: 0 }],  // true  → classifica por conteúdo
    [{ node: 'Juntar Ramos', type: 'main', index: 1 }],        // false → direto para o Merge
  ] },
  'Montar Req Classif': { main: [[{ node: 'IA Classificar', type: 'main', index: 0 }]] },
  'IA Classificar': { main: [[{ node: 'Parse Classif', type: 'main', index: 0 }]] },
  'Parse Classif': { main: [[{ node: 'Juntar Ramos', type: 'main', index: 0 }]] },
  'Juntar Ramos': { main: [[{ node: 'Registrar Documento', type: 'main', index: 0 }]] },
  'Registrar Documento': { main: [[
    { node: 'Recomputar Completude', type: 'main', index: 0 },
    { node: 'Recompor Contexto', type: 'main', index: 0 },
  ]] },
  'Recompor Contexto': { main: [[{ node: 'Extracao ja feita?', type: 'main', index: 0 }]] },
  'Extracao ja feita?': { main: [
    [{ node: 'Juntar Extraidos', type: 'main', index: 1 }],     // true  → já extraído: pula a OpenAI
    [{ node: 'Montar Req Extracao', type: 'main', index: 0 }],  // false → extrai
  ] },
  'Montar Req Extracao': { main: [[{ node: 'Fatiar Extracao', type: 'main', index: 0 }]] },
  'Fatiar Extracao': { main: [[{ node: 'IA Extrair', type: 'main', index: 0 }]] },
  'IA Extrair': { main: [[{ node: 'Parse Extracao', type: 'main', index: 0 }]] },
  // `Parse Extracao` -> IF do 1º estágio -> (false) Juntar Tentativas | (true) espera e repete.
  // O último estágio não tem IF: o que sobra dele é definitivo e vai direto ao Merge.
  ...Object.fromEntries(estagiosDeRepeticao.flatMap((e, i) => {
    const ultimo = i === estagiosDeRepeticao.length - 1;
    const origem = i === 0 ? 'Parse Extracao' : estagiosDeRepeticao[i - 1].nomeParse;
    return [
      [origem, { main: [[{ node: e.nomeIf, type: 'main', index: 0 }]] }],
      [e.nomeIf, { main: [
        [{ node: e.nomeEsperar, type: 'main', index: 0 }],                 // true  -> espera e repete
        [{ node: 'Juntar Tentativas', type: 'main', index: i }],           // false -> definitivo
      ] }],
      [e.nomeEsperar, { main: [[{ node: e.nomeIA, type: 'main', index: 0 }]] }],
      [e.nomeIA, { main: [[{ node: e.nomeParse, type: 'main', index: 0 }]] }],
      ...(ultimo ? [[e.nomeParse, { main: [[{ node: 'Juntar Tentativas', type: 'main', index: i + 1 }]] }]] : []),
    ];
  })),
  'Juntar Tentativas': { main: [[{ node: 'Juntar Blocos', type: 'main', index: 0 }]] },
  'Juntar Blocos': { main: [[{ node: 'Gravar Campos (Sombra)', type: 'main', index: 0 }]] },
  'Gravar Campos (Sombra)': { main: [[{ node: 'Registrar Diagnostico', type: 'main', index: 0 }]] },
  'Registrar Diagnostico': { main: [[{ node: 'Juntar Extraidos', type: 'main', index: 0 }]] },
  'Juntar Extraidos': { main: [[{ node: 'Reconciliar (Classe A)', type: 'main', index: 0 }]] },
  'Reconciliar (Classe A)': { main: [[{ node: 'Reconciliar Lote', type: 'main', index: 0 }]] },
  'Reconciliar Lote': { main: [[{ node: 'Resumo de Custo', type: 'main', index: 0 }]] },
  'Resumo de Custo': { main: [[{ node: 'Gravar Uso do Lote', type: 'main', index: 0 }]] },
  'Gravar Uso do Lote': { main: [[{ node: 'Conferir Lote', type: 'main', index: 0 }]] },
};

// O canvas é desenhado a partir do grafo, nunca à mão (ver N8N/layout.mjs).
posicionar(nodes, connections);

const workflow = {
  // O NOME MUDOU EM PRODUÇÃO, E O REPOSITÓRIO PASSOU A ACOMPANHAR, NÃO A
  // BRIGAR. `conferir-publicado.mjs` casa repositório↔publicado pelo `name`
  // (é a chave — "renomear o workflow no editor quebra esta ligação"), e
  // `preparar-republicacao.mjs` sobrescreve o nome do publicado com o daqui
  // (`repo.name ?? vivo.name`). Até 17/09/2026 este campo trazia o nome
  // técnico de fatia ("E1 Ingestão + Diagnóstico + E2 Extração-Sombra + E3
  // Reconciliação Classe A (Fatia 1)"), e o dono já tinha renomeado o
  // publicado para o nome de marca abaixo — republicar sem perceber teria
  // revertido a rebranding em silêncio. O nome de marca fica aqui agora.
  name: 'Oria — SARF (Sistema Automático de Reestruturação Financeira)',
  nodes, connections, settings: { executionOrder: 'v1' },
  meta: { note: 'Gerado por N8N/build-workflow.mjs. Nós Code espelham N8N/lib/ (testado). Diagnóstico de conteúdo roda SEMPRE (entidade/tipo/período/legibilidade); E2 em N0/sombra; E3 Classe A em N1 (gera pendência, nunca fato). Fluxo interno: E1 Ingestão + Diagnóstico + E2 Extração-Sombra + E3 Reconciliação Classe A (Fatia 1).' },
};

writeFileSync(join(__dirname, 'workflow.e1-ingestao.json'), JSON.stringify(workflow, null, 2) + '\n');
console.log('Escrito workflow —', nodes.length, 'nós,', Object.keys(connections).length, 'conexões');
