// Classificação por CONTEÚDO — o fallback de quando o NOME não basta.
//
// Usada quando o classificador por nome não tem confiança (nome genérico).
// Modelo multimodal + saída presa a um JSON Schema, então não há parsing frágil
// de texto livre.
//
// ESTE ARQUIVO CHAMAVA-SE `openai.mjs` até 24/08/2026, e o nome era metade do
// problema que a troca de provedor encontrou: o que ele sempre teve dentro é a
// TAXONOMIA e o PROMPT da classificação — coisas do domínio, que não mudam com
// o provedor —, e junto morava o endereço da OpenAI, o formato do corpo dela e o
// jeito dela de devolver resposta. O que era do provedor mudou-se para
// `provedor.mjs`; o que é da Oria ficou aqui, e o arquivo passou a se chamar
// pelo que faz.
//
// Autonomia: continua N1 — a saída é SUGESTÃO para a fila de revisão, com
// confiança e justificativa. Nada é aceito sem humano (anti-ancoragem, Arquitetura do Sistema/1 Visão e Doutrina/01).
//
// LGPD: API direta está fora do perímetro Azure, e isso vale para QUALQUER
// provedor daqui. Antes de dado real em produção, zero-retention/DPA acertado
// com quem estiver ativo (ver Arquitetura do Sistema/2 Especificação/f0/02 e Arquitetura do Sistema/2 Especificação/10) — trocar de provedor não herda o
// acordo do anterior.

import { ALIASES, KIT_BASICO } from './taxonomia.mjs';
import {
  provedor, urlDaChamada, montarCorpoIA, parteDeArquivo, parteDeTexto, conteudoDaResposta,
} from './provedor.mjs';
import { MODELO_CLASSIFICACAO, esforcosDoProvedor } from './custo.mjs';

// O modelo padrão é o do PROVEDOR ATIVO, e sai de `lib/custo.mjs` — que é onde
// ele mora desde 13/08/2026, porque o orçamento depende do preço dele. Um
// `DEFAULT_MODEL` próprio aqui seria a terceira cópia do mesmo fato.
const DEFAULT_MODEL = MODELO_CLASSIFICACAO;

// O esforço de raciocínio da CLASSIFICAÇÃO, pela regra do dono. A entrada aqui é
// o PDF inteiro e a saída são ~120 tokens, então quase não há saída sobre a qual
// a folga de 25% incida — ver `limiarDeRaciocinio` em `custo.mjs`.
const DEFAULT_ESFORCO = esforcosDoProvedor().classificacao?.esforco ?? null;

// Enum de códigos possíveis para a classificação (taxonomia conhecida + escape).
export function codigosConhecidos() {
  const set = new Set([...KIT_BASICO, ...ALIASES.map((a) => a.codigo)]);
  return [...set, 'DESCONHECIDO'];
}

const SYSTEM_PROMPT = [
  'Você classifica documentos financeiros de mandatos de Reestruturação (contexto Brasil).',
  'Dado o conteúdo de UM documento, identifique o tipo (código da taxonomia), a entidade',
  '(empresa/razão social, se visível), o período de competência e se é versão assinada.',
  'Convenções de período: "12M25"=ano 2025; "1T25"=1º trimestre/2025; "L24M"=últimos 24 meses;',
  'listas de anos como "23,24,25" para múltiplos exercícios; um ano isolado como "2025" também é válido.',
  'Documento que cobre MENOS de 12 meses (acumulado no ano: "janeiro a agosto de 2026") NÃO é o',
  'exercício: use N meses + "M" + ano ("8M26"), periodo_tipo "multi" — nunca "12M26", "2026" ou',
  '"anual". Olhe o cabeçalho do período, não só o ano.',
  '',
  'IMPORTANTE sobre incerteza: você DEVE sempre tentar identificar o tipo mais provável dentre',
  'os códigos conhecidos, mesmo com confiança baixa — analise cabeçalhos, rótulos de linhas,',
  'estrutura de colunas e demais pistas visuais do documento. "DESCONHECIDO" é reservado',
  'SOMENTE para os casos em que o documento está genuinamente ilegível/corrompido ou',
  'claramente não é nenhum documento financeiro reconhecível. Baixa confiança não é motivo',
  'para deixar de dar um palpite — é motivo para REGISTRAR o palpite com uma confiança baixa',
  'correspondente e uma justificativa objetiva. NUNCA invente valores que não estão no',
  'documento (números, entidade, período) — mas SEMPRE ofereça sua melhor hipótese de tipo.',
  '',
  'O campo "justificativa" é obrigatório e deve ser uma explicação objetiva e específica',
  '(1-2 frases) do que te levou à classificação e à confiança escolhida — cite o que você viu',
  '(ou não viu) no documento. Exemplos: "Cabeçalho traz \'Balanço Patrimonial\' e colunas',
  'Ativo/Passivo, confianca alta." ou "Nome do arquivo sugere Balanço, mas o conteúdo mostra',
  'um relatório de saldos acumulados sem a estrutura formal de Ativo/Passivo/PL — confiança',
  'reduzida." Evite respostas genéricas como "não foi possível determinar".',
  '',
  'Responda SOMENTE conforme o schema.',
].join(' ');

// Schema estrito da resposta (Structured Outputs).
export function classificationSchema() {
  return {
    name: 'classificacao_documento',
    strict: true,
    schema: {
      type: 'object',
      additionalProperties: false,
      required: ['tipo_taxonomia', 'entidade', 'cnpj', 'periodo_tipo', 'periodo_referencia', 'assinado', 'confianca', 'justificativa'],
      properties: {
        tipo_taxonomia: { type: 'string', enum: codigosConhecidos() },
        entidade: { type: ['string', 'null'] },
        // 0170: MESMA forma do `SCHEMA_CLASSIF` do gerador, e o comentário de lá
        // afirma que as duas são iguais. Esta ficou para trás quando o campo
        // entrou — achado na revisão: latente hoje (só os testes usam esta lib),
        // silencioso no dia em que deixar de ser.
        cnpj: { type: ['string', 'null'] },
        periodo_tipo: { type: 'string', enum: ['anual', 'trimestre', 'multi', 'data-base', 'outro', 'desconhecido'] },
        periodo_referencia: { type: ['string', 'null'] },
        assinado: { type: ['boolean', 'null'] },
        confianca: { type: 'number', minimum: 0, maximum: 1 },
        justificativa: { type: 'string' },
      },
    },
  };
}

// Monta a chamada inteira — URL, método e corpo — no dialeto do provedor.
// `conteudo` é uma parte (ou lista de partes) já pronta, vinda de
// `contentPartFromFile`, e por isso já está no dialeto certo.
export function buildClassificationRequest({
  nomeOriginal, conteudo, model = DEFAULT_MODEL, prov = provedor(),
  esforco = DEFAULT_ESFORCO,
}) {
  return {
    url: urlDaChamada(prov, model),
    method: 'POST',
    body: montarCorpoIA(prov, {
      modelo: model,
      sistema: SYSTEM_PROMPT,
      esforco,
      partes: [
        parteDeTexto(prov, `Nome do arquivo (pista fraca): ${nomeOriginal || '(sem nome)'}`),
        ...(Array.isArray(conteudo) ? conteudo : [conteudo]),
      ],
      schema: classificationSchema(),
    }),
  };
}

// Detecta planilhas (precisam de extração de texto antes de enviar).
export function isSpreadsheet(mimeType) {
  return /spreadsheetml|ms-excel|excel|csv/i.test(mimeType || '');
}

// A "parte de conteúdo" multimodal a partir de um arquivo — a forma exata é do
// provedor (`lib/provedor.mjs`), inclusive a garantia de nunca lançar: tipo não
// suportado vira parte de TEXTO declarando o caso, para o workflow não dar
// dead-end (fail-safe). Fica reexportado com o nome antigo porque metade do
// sistema o chama assim, e renomear função não era o assunto desta troca.
export function contentPartFromFile(arquivo = {}, prov = provedor()) {
  return parteDeArquivo(prov, arquivo);
}

// Extrai e valida o JSON da resposta, seja qual for o dialeto.
export function parseClassificationResponse(apiJson, prov = provedor()) {
  const content = conteudoDaResposta(prov, apiJson);
  if (!content) throw new Error(`Resposta do provedor (${prov.rotulo}) sem conteúdo`);
  let parsed;
  try {
    parsed = typeof content === 'string' ? JSON.parse(content) : content;
  } catch (e) {
    throw new Error(`Conteúdo do provedor (${prov.rotulo}) não é JSON válido: ${e.message}`);
  }
  // Normaliza para o mesmo formato do classificador por nome.
  return {
    tipo_taxonomia: parsed.tipo_taxonomia === 'DESCONHECIDO' ? null : parsed.tipo_taxonomia,
    entidade: parsed.entidade ?? null,
    periodo: parsed.periodo_referencia
      ? { tipo: parsed.periodo_tipo, referencia: parsed.periodo_referencia }
      : null,
    assinado: parsed.assinado ?? null,
    confianca: typeof parsed.confianca === 'number' ? parsed.confianca : 0,
    // `fonte` é valor de DADO — ele está gravado em linha de banco de produção e
    // em CHECK de migration (0033), então trocá-lo por "ia_conteudo" seria
    // reescrever histórico para arrumar um nome. Fica como está, e o que ele
    // significa é "veio da leitura do conteúdo", não "veio da OpenAI".
    fonte: 'openai_conteudo',
    justificativa: parsed.justificativa || '',
  };
}

export { DEFAULT_MODEL };
