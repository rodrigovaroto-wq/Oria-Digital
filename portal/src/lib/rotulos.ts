// RÓTULOS LEGÍVEIS — a tradução do vocabulário interno para o que se lê na tela.
//
// POR QUE ESTE ARQUIVO EXISTE. O banco guarda chave canônica (`ativo_circulante`,
// `precondicao_nao_satisfeita`), que é o certo para o banco: chave estável, sem
// acento, sem espaço, comparável. O erro era publicar essa chave na TELA. Quem lê
// não é o banco — é o analista, e "passivo_nao_circulante" num cabeçalho é ao mesmo
// tempo mais feio e menos informativo que "Passivo Não Circulante".
//
// O pedido do dono (07/08/2026) foi explícito: nada de `_`, título em maiúscula
// quando é título, e ACENTO em todo lugar. O acento não é estética — "divida" e
// "dívida" são palavras diferentes em português, e a primeira não é a que se quer.
//
// A regra é: mapa explícito para o que tem nome próprio, e um humanizador genérico
// como rede de segurança — chave nova aparece legível mesmo antes de alguém a
// mapear, em vez de vazar `snake_case` para o cliente.
import { BALANCO_SECOES, DRE_SECOES, FLUXO_CAIXA_SECOES } from "./statement-templates";

/** Siglas: ficam MAIÚSCULAS, sempre. */
const SIGLAS = new Set([
  "dre", "dfc", "dmpl", "ebit", "ebitda", "cnpj", "cpf", "icms", "ipi", "pis",
  "cofins", "iss", "irpj", "csll", "irrf", "inss", "fgts", "cdi", "ipca", "igpm",
  "igp", "inpc", "selic", "pib", "usd", "brl", "sac", "dscr", "sga", "capex",
  "bndes", "finame", "tjlp", "cpc", "ncg", "pl", "bp", "id", "ok",
]);

/** Palavras que o vocabulário interno guarda sem acento e que a tela precisa com. */
const ACENTOS: Record<string, string> = {
  nao: "não", divida: "dívida", dividas: "dívidas", patrimonio: "patrimônio",
  liquido: "líquido", liquida: "líquida", tributario: "tributário",
  tributaria: "tributária", tributarios: "tributários", precondicao: "pré-condição",
  extracao: "extração", secao: "seção", secoes: "seções", orgao: "órgão",
  periodo: "período", credito: "crédito", debito: "débito", saldo: "saldo",
  imposto: "imposto", impostos: "impostos", exercicio: "exercício",
  provisao: "provisão", provisoes: "provisões", obrigacao: "obrigação",
  obrigacoes: "obrigações", operacao: "operação", operacoes: "operações",
  reconciliacao: "reconciliação", divergencia: "divergência",
  aprovacao: "aprovação", ressalva: "ressalva", intragrupo: "intragrupo",
  mutuo: "mútuo", mutuos: "mútuos", cambio: "câmbio", juros: "juros",
  amortizacao: "amortização", captacao: "captação", pagamento: "pagamento",
  emprestimo: "empréstimo", emprestimos: "empréstimos", debenture: "debênture",
  debentures: "debêntures", arrendamento: "arrendamento", garantia: "garantia",
  sazonalidade: "sazonalidade", premissa: "premissa", premissas: "premissas",
  faturamento: "faturamento", balancete: "balancete", balanco: "balanço",
  combinado: "combinado", mensal: "mensal", anual: "anual",
  classificacao: "classificação", entidade: "entidade", conta: "conta",
  reestruturacao: "reestruturação", certidao: "certidão", certidoes: "certidões",
  razao: "razão", organograma: "organograma", contingencia: "contingência",
  contingencias: "contingências", situacao: "situação", imobilizado: "imobilizado",
  contas: "contas", valor: "valor", material: "material", suspeito: "suspeito",
  padrao: "padrão", confianca: "confiança", ilegivel: "ilegível",
  satisfeita: "satisfeita", aritmetica: "aritmética", serie: "série",
  numerico: "numérico", numerica: "numérica", unico: "único", ultimo: "último",
  proximo: "próximo", minimo: "mínimo", maximo: "máximo", medio: "médio",
  media: "média", indice: "índice", indices: "índices", macro: "macro",
};

/** Palavras que ficam minúsculas no meio de um título. */
const MINUSCULAS = new Set(["de", "da", "do", "das", "dos", "e", "em", "no", "na", "por", "para", "sobre", "a", "o"]);

/**
 * Humanizador genérico: `passivo_nao_circulante` → "Passivo Não Circulante".
 * Rede de segurança para chave que ninguém mapeou ainda.
 */
export function humanizar(chave: string): string {
  const palavras = chave.trim().replace(/[_:]+/g, " ").replace(/\s+/g, " ").split(" ");
  return palavras
    .map((p, i) => {
      const bruta = p.toLowerCase();
      if (SIGLAS.has(bruta)) return bruta.toUpperCase();
      const comAcento = ACENTOS[bruta] ?? bruta;
      if (i > 0 && MINUSCULAS.has(bruta)) return comAcento;
      return comAcento.charAt(0).toUpperCase() + comAcento.slice(1);
    })
    .join(" ");
}

/** Seções canônicas com nome próprio, das três estruturas que o sistema conhece. */
const SECOES = new Map<string, string>([
  ...[...BALANCO_SECOES, ...DRE_SECOES, ...FLUXO_CAIXA_SECOES].map(
    (s) => [s.key, s.label] as [string, string],
  ),
  // As que não vêm de uma estrutura de demonstração — dívida, tributos e afins.
  ["divida", "Mapa de Dívida"],
  ["tributos", "Tributos a Recolher"],
  ["intragrupo", "Mútuos e Intragrupo"],
  ["faturamento", "Faturamento Mensal"],
  ["outros", "Outros"],
]);

/**
 * O nome de uma seção canônica na TELA. `null`/vazio devolve a frase que explica a
 * ausência — a seção sem classificação é uma informação, não um buraco.
 */
export function rotuloDaSecao(chave: string | null | undefined): string {
  if (!chave || chave === "(sem seção canônica)") return "Linhas sem seção identificada";
  return SECOES.get(chave) ?? humanizar(chave);
}

/** Tipos de pendência, com o nome que o analista usa. */
const PENDENCIAS = new Map<string, string>([
  ["precondicao_nao_satisfeita", "falta um lado da conta"],
  ["divergencia_aritmetica", "os números não fecham"],
  ["divergencia_classe_b", "divergência entre documentos"],
  ["arquivo_ilegivel", "arquivo ilegível"],
  ["extracao_falhou", "a extração falhou"],
  ["extracao_padrao_suspeito", "conferir contra o original"],
  ["extracao_confianca_baixa", "conferir contra o original"],
  ["classificacao_incerta", "classificação a confirmar"],
  ["entidade_incerta", "entidade a confirmar"],
  ["periodo_incerto", "período a confirmar"],
  ["divergencia_reconciliacao", "os documentos não batem"],
]);

export function rotuloDaPendencia(tipo: string): string {
  return PENDENCIAS.get(tipo) ?? humanizar(tipo);
}

/**
 * QUAL checagem de reconciliação abriu a pendência.
 *
 * O TIPO da pendência responde "que espécie de problema é este" e várias
 * checagens diferentes respondem a mesma coisa: `divergencia_reconciliacao`.
 * Na fila do painel, várias linhas iguais dizendo "os documentos não batem" não
 * dão para triar — e triagem é a única coisa que aquela fila faz. O `motivo`
 * (`reconciliacao:<tipo>`) é quem sabe qual foi, e este mapa o põe em português.
 *
 * Devolve null para pendência que não veio de reconciliação — a tela então não
 * escreve nada, em vez de escrever um nome técnico só porque existe um campo.
 */
const CHECAGENS = new Map<string, string>([
  ["ativo_passivo_pl", "ativo × passivo + PL"],
  ["caixa_bp_fluxo", "caixa: balanço × fluxo"],
  ["duplicidade_de_rotulo", "mesma conta, dois rótulos"],
  ["receita_dre_vs_faturamento", "receita: DRE × faturamento"],
  ["despfin_dre_vs_divida", "despesa financeira × dívida"],
  ["mutuos_planilha_vs_balanco", "mútuos: planilha × balanço"],
  ["conflito_entre_documentos", "dois documentos, dois números"],
]);

export function nomeDaChecagem(motivo: string | null): string | null {
  if (!motivo?.startsWith("reconciliacao:")) return null;
  const tipo = motivo.slice("reconciliacao:".length);
  return CHECAGENS.get(tipo) ?? humanizar(tipo);
}

/**
 * Quebra a descrição de uma pendência em PARTES LEGÍVEIS.
 *
 * As mensagens são geradas no banco e emendam vários fatos com `;` — o que numa
 * tela vira um parágrafo em que ninguém acha o que importa. Aqui elas voltam a ser
 * uma lista, para a tela pôr uma por linha.
 *
 * O `;` DENTRO DE PARÊNTESES OU COLCHETES NÃO SEPARA NADA: ele está lá justamente
 * para qualificar o item (`[entidade: —; período: 31/12/2024]`). Quebrar ali
 * partiria o qualificador do fato que ele qualifica — foi o primeiro desenho, e
 * produzia linhas órfãs do tipo "período: 31/12/2024]".
 */
export function partesDaDescricao(texto: string): string[] {
  const partes: string[] = [];
  let atual = "";
  let profundidade = 0;
  for (let i = 0; i < texto.length; i++) {
    const ch = texto[i];
    if (ch === "(" || ch === "[") profundidade++;
    else if (ch === ")" || ch === "]") profundidade = Math.max(0, profundidade - 1);
    if (ch === ";" && profundidade === 0) { partes.push(atual.trim()); atual = ""; continue; }
    // FIM DE FRASE também separa fato: as mensagens emendam "achei o Balanço" com
    // "2024 está assim" e "2025 está assim" usando ponto, não só `;`. O ponto só
    // separa quando vem SEGUIDO DE ESPAÇO — assim `14529.00` e `R$ 1.234` seguem
    // inteiros, que é o defeito óbvio de quebrar por `.`.
    if (ch === "." && profundidade === 0 && /\s/.test(texto[i + 1] ?? "")) {
      partes.push((atual + ch).trim()); atual = ""; i++; continue;
    }
    atual += ch;
  }
  if (atual.trim()) partes.push(atual.trim());
  return partes.filter(Boolean);
}

/**
 * Troca o vocabulário interno que sobra nas mensagens do banco pelo de tela.
 * Conservador de propósito: só o que é claramente jargão de campo, para não
 * reescrever o conteúdo da mensagem — que é medição, e medição não se edita.
 */
export function suavizarMensagem(texto: string): string {
  return texto
    .replace(/\bcoluna de entidade:\s*\(qualquer\)/gi, "qualquer entidade")
    .replace(/\bcoluna de per[ií]odo:\s*/gi, "coluna ")
    .replace(/\bentidade:\s*—/gi, "sem entidade")
    .replace(/\bper[ií]odo:\s*/gi, "")
    .replace(/\bsecao_canonica\b/g, "seção")
    .replace(/\brotulo_norm\b/g, "rótulo")
    .replace(/\bf0\/\d+\b/g, "")
    // "4 pendência(s) BLOQUEANTE(s) sem decisão" → "4 pendências bloqueantes
    // sem decisão". O plural entre parênteses e a caixa alta vêm de mensagem de
    // banco, escrita para caber nos dois casos; na tela isso lê como rascunho.
    //
    // A regra mexe SÓ na palavra colada ao "(s)". A tentação é baixar toda
    // palavra em caixa alta, e isso destrói o que a mensagem tem de mais útil:
    // CNPJ, ICMS, PIS, COFINS e os códigos da taxonomia aparecem nas descrições
    // de pendência, e "cnpj" lê como erro de digitação.
    .replace(
      // O adjetivo vem colado no substantivo ("4 pendência(s) BLOQUEANTE(s)"), e
      // os dois têm de concordar com o MESMO número — por isso a segunda palavra
      // entra na mesma regra, e não numa passada solta que pluralizaria sozinha.
      /(\d+)\s+([\wà-úÀ-Ú]+)\((s|es)\)(\s+([\wà-úÀ-Ú]+)\((?:s|es)\))?/gi,
      (_m: string, n: string, p1: string, sufixo: string, _todo: string, p2: string | undefined) => {
        const caixa = (w: string) => (w === w.toUpperCase() ? w.toLowerCase() : w);
        const plural = (w: string, suf = sufixo) => (Number(n) === 1 ? caixa(w) : `${caixa(w)}${suf}`);
        return `${n} ${plural(p1)}${p2 ? ` ${plural(p2, "s")}` : ""}`;
      },
    )
    .replace(/([\wà-úÀ-Ú]+)\((s|es)\)/gi, (_m: string, palavra: string, suf: string) =>
      `${palavra === palavra.toUpperCase() ? palavra.toLowerCase() : palavra}${suf}`)
    .replace(/\s{2,}/g, " ")
    .trim();
}

/**
 * O ÚNICO trecho em que "separar as aspas numa lista" é LEITURA da descrição,
 * não adivinhação sobre ela: a lista que `fn_rotulos_candidatos` (0033/0034,
 * `Supabase/migrations/0033_precondicao_que_nomeia_o_rotulo.sql`) escreve
 * depois do marcador "Rótulos que a extração TROUXE ... :". Cada item dali é,
 * por construção da função no banco, `campo_extraido.chave` — o rótulo de UMA
 * LINHA do documento, exatamente o que se quer destacar como "onde conferir
 * no arquivo". Foi o caso real que pediu esta separação (teste "(0112) a
 * mensagem real vira 4 fatos", acima).
 *
 * FORA desse marcador, aspas na descrição não têm essa garantia — o achado 6
 * da revisão do PR #203: a pendência de hierarquia de entidade (0160,
 * `Supabase/migrations/0160_a_hierarquia_que_o_diagnostico_chama_de_erro.sql`)
 * cita NOME DE EMPRESA entre aspas na mesma frase, e nada no texto da
 * descrição diz "isto é conta do documento, aquilo é nome próprio" — são as
 * duas formas de citar algo entre aspas em português. Adivinhar essa
 * distinção pela pontuação seria inventar um dado que a descrição não afirma,
 * e a regra 1 do projeto proíbe isso: célula (aqui, a lista "onde conferir")
 * sem dado por trás é ausência apresentada como medição. A saída honesta é
 * não separar nada fora do marcador — a descrição aparece inteira, e quem lê
 * decide sozinho, pelo CONTEÚDO da frase, o que é conta e o que é empresa.
 */
const MARCADOR_LISTA_DE_ROTULOS = /Rótulos que a extração TROUXE[^.]*?:\s*/i;

/**
 * A LISTA propriamente dita — marcador + a sequência de itens entre aspas que
 * ele introduz, capturada no grupo 1 (só os itens, sem o marcador). Uma única
 * fonte, usada tanto por `rotulosCitados` (que lê o grupo 1) quanto por
 * `semALista` (que apaga o casamento inteiro, grupo 0). As DUAS PRECISAM
 * CONCORDAR sobre onde a lista começa e termina; tê-las como dois regexes
 * separados foi o defeito real (achado da revisão do PR #204, sobre o PR
 * #204): `rotulosCitados` limitava cada item a `{2,80}` caracteres —
 * plausivelmente uma guarda contra casar frase inteira — enquanto `semALista`
 * usava `[^"]+`, sem limite. `campo_extraido.chave` (`Supabase/schema.sql`) é
 * `text`, sem tamanho máximo — um rótulo de linha extraído de um documento
 * real passa de 80 caracteres com facilidade (descrição de conta longa,
 * "Provisão para créditos de liquidação duvidosa de longo prazo sobre
 * duplicatas..."). Não existe coluna nem contrato que justifique 80: é um
 * número solto. Diante disso, a saída correta não é subir o número dos dois
 * lados — isso só move o buraco para 81+ caracteres, e a próxima sessão
 * herdaria a mesma pergunta sem resposta. É fazer os dois lados lerem a
 * MESMA definição de "onde a lista acaba", sem limite de tamanho — que é o
 * que `semALista` já fazia de correto.
 *
 * Capturar o SPAN da lista (e não varrer o resto do texto inteiro, como a
 * versão anterior de `rotulosCitados` fazia) também fecha uma segunda
 * assimetria: aspas que apareçam DEPOIS da lista, na mesma frase, não podem
 * virar "rótulo citado" por acidente — só o que está dentro do span que o
 * marcador introduz.
 */
const LISTA_DE_ROTULOS = new RegExp(
  String.raw`${MARCADOR_LISTA_DE_ROTULOS.source}((?:"[^"]+"(?:\s*\[[^\]]*\])?[\s,]*)+)`,
  "i",
);

/**
 * Rótulos entre aspas que a mensagem cita como contas a conferir no
 * original — só os que vêm depois do marcador acima, e só dentro do span da
 * lista (ver `LISTA_DE_ROTULOS`). Sem marcador, devolve vazio: ver o
 * comentário de `MARCADOR_LISTA_DE_ROTULOS`.
 */
export function rotulosCitados(texto: string): string[] {
  const marca = LISTA_DE_ROTULOS.exec(texto);
  if (!marca) return [];
  return [...new Set([...marca[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]))];
}

/**
 * Tira do texto o marcador e a lista que ele introduz, para a tela não
 * repetir o que já vai aparecer destacado como "onde conferir". Só corta
 * quando o marcador de fato introduz uma lista entre aspas — sem ele, o
 * texto volta INTOCADO: qualquer aspas fora dali é conteúdo da frase (nome de
 * empresa, de arquivo…), e cortar por aspas sozinho furaria a frase sem dizer
 * o motivo, que é exatamente o que a regra 1 do projeto proíbe.
 */
export function semALista(texto: string): string {
  // O `\s*` do separador vive DENTRO do grupo opcional do colchete, e o que
  // vem depois é UMA classe (`[\s,]*`) em vez de `\s*,?\s*`. A forma anterior
  // punha dois quantificadores de espaço adjacentes, que é a ambiguidade que o
  // Sonar aponta como backtracking super-linear (`typescript:S8786`, PR #204):
  // uma corrida de espaços pode ser dividida entre eles de muitas maneiras.
  //
  // HONESTIDADE SOBRE A MEDIÇÃO: eu TENTEI reproduzir o custo e NÃO CONSEGUI —
  // marcador casado, lista aberta e corridas de 2.000 a 16.000 espaços seguidas
  // de um caractere que não fecha a lista rodam em 0,0-0,1 ms nas duas formas
  // (V8 não backtrackeia aqui). Então esta troca é DEFENSIVA, não a correção de
  // uma lentidão medida: a forma nova não tem a ambiguidade, custa nada, e a
  // entrada vem do banco alimentada por documento extraído — mas quem ler isto
  // depois não deve acreditar que havia um travamento observado, porque não
  // havia. Se algum dia houver, o número entra aqui.
  // `LISTA_DE_ROTULOS` — a MESMA definição que `rotulosCitados` usa — decide
  // onde a lista começa e termina. As duas concordarem é o ponto: antes desta
  // correção, `semALista` cortava por `[^"]+` (sem limite) enquanto
  // `rotulosCitados` extraía por `{2,80}`, e um rótulo de mais de 80
  // caracteres saía cortado do texto (aqui, corretamente) mas não aparecia
  // na lista "onde conferir" (por causa do limite, lá) — a informação sumia
  // dos dois lugares. Ver o comentário de `LISTA_DE_ROTULOS`.
  const marca = LISTA_DE_ROTULOS.exec(texto);
  if (!marca) return texto;
  // A ORDEM aqui é a correção, não enfeite. Antes vinha `/\s*\.\s*\./g` ANTES
  // do colapso de espaços, e esse é quadrático MEDIDO (Sonar S8786, PR #204):
  // numa corrida de espaços sem o par de pontos, cada posição inicial consome
  // a corrida inteira e volta atrás procurando o `.`. Medido neste repositório
  // — 20k espaços: 168 ms · 40k: 609 ms · 80k: 2,5 s · 160k: 9,9 s. Dobrar a
  // entrada quadruplica o tempo, e isso roda na renderização da página do caso
  // sobre texto que vem do banco.
  //
  // Colapsando os espaços PRIMEIRO, o padrão seguinte só precisa de espaço
  // simples opcional (`/ ?\. ?\./`) — quantificadores limitados, sem corrida
  // para reconsumir, sem backtracking. Mesmo resultado visível.
  const cortado = texto.replace(marca[0], "")
    .replace(/\s+/g, " ")
    .replace(/ ?\. ?\./g, ".")
    .trim();
  return cortado.length > 20 ? cortado : texto;
}

// ──────────────────────────────────────────────────────────────────────────────
// QUEM ACEITOU A LINHA (P16, vistoria P2 de 04/11, ALTA 3).
//
// O banco grava o aceite automático com autor `sistema:auto_aceite (dial N2, limiar 0.95, …)`
// (0019 e seguintes). A tela dizia "Todas as linhas foram aceitas" e "por sistema:auto_aceite
// (dial N2, limiar 0.95…)": com 283 linhas aceitas pela máquina e nenhuma por uma pessoa, a
// frase soava como conferência humana, e o autor era jargão de engenharia.
/** `true` quando o aceite foi da automação (`sistema:*`), não de uma pessoa. */
export function aceiteAutomatico(aceitoPor: string | null | undefined): boolean {
  return (aceitoPor ?? "").startsWith("sistema:");
}

/** A frase de quando todas as linhas estão aceitas, dizendo QUEM aceitou. */
export function fraseDoAceiteTotal(aceitosPor: Array<string | null | undefined>): string {
  const auto = aceitosPor.filter(aceiteAutomatico).length;
  const pessoa = aceitosPor.length - auto;
  if (auto === 0) return "Todas as linhas foram aceitas por uma pessoa — já entram no export como fato.";
  if (pessoa === 0) {
    return "Todas as linhas foram aceitas AUTOMATICAMENTE, pela confiança da leitura; nenhuma foi conferida "
      + "por uma pessoa. Já entram no export como fato.";
  }
  return `Todas as linhas foram aceitas: ${pessoa} por uma pessoa e ${auto} automaticamente, pela confiança `
    + "da leitura. Já entram no export como fato.";
}

// ──────────────────────────────────────────────────────────────────────────────
// A EXTRAÇÃO QUE FALHOU, EM PORTUGUÊS (P16, vistoria P2 de 04/11, ALTA 2).
//
// O banco escreve `Extração de "<arquivo>" falhou ou veio incompleta (N par(es) …). Motivo: <m>`
// (`fn_descricao_extracao_falhou`, 0154). Quando <m> é a mensagem do provedor de IA, ela chega
// em inglês e crua: um PDF corrompido de 14 bytes mostrou o erro do provedor na tela, sem dizer
// o que fazer. O texto exato daquele erro não foi guardado na vistoria.
/** O que a pessoa faz depois — a ação segue a CAUSA, não é a mesma para toda falha. */
export type AcaoDeFalha =
  | "servico_de_ia" | "falha_do_sistema" | "chamada_incerta" | "resposta_invalida" | "resposta_truncada"
  | "planilha_cortada" | "xlsx_varias_abas" | "sem_linhas" | "declarado_sem_dado" | "conferir_na_revisao" | "nao_classificada";

export interface FalhaDeExtracaoNaTela {
  /** a frase do banco até "Motivo:", que já é português e nomeia o arquivo */
  frase: string;
  /** a causa em português, uma frase por causa distinta — o único texto do motivo que vai à vista */
  aVista: string[];
  /** o motivo INTEIRO, como o banco gravou (nada se perde); null só quando não há motivo */
  tecnico: string | null;
  /** o que fazer, uma ação por tipo de causa presente */
  acoes: Array<{ tipo: AcaoDeFalha; texto: string; reenvio: boolean }>;
}

// Textos de "o que fazer". O caminho de reprocessar é REENVIAR o mesmo arquivo em "Adicionar
// documentos": mesmo hash no mesmo caso vira versão nova do MESMO documento, sem duplicar
// (Supabase/migrations/0026_reextracao_por_hash.sql), e a extração boa resolve a pendência da
// versão anterior (0029, chave por documento_id). Não existe botão de reprocessar — não prometer um.
const ACAO: Record<AcaoDeFalha, { texto: string; reenvio: boolean }> = {
  servico_de_ia: {
    texto: "o arquivo não é o problema: a leitura por IA falhou, no todo ou em parte, por causa do serviço de IA. "
      + "Avise quem cuida do sistema para corrigi-lo. Depois, reenvie o mesmo arquivo: ele não duplica o "
      + "documento, vira uma nova leitura dele, e a leitura que der certo resolve esta pendência. "
      + "Não há botão de reprocessar.",
    reenvio: true,
  },
  // 4xx sem causa reconhecida (ex. 400 invalid_request_error): pode ser o arquivo recusado pelo
  // provedor (PDF corrompido — o caso de origem da P16) OU o serviço. Não afirma nenhum dos dois.
  chamada_incerta: {
    texto: "a chamada à IA foi recusada sem causa identificada: pode ser o arquivo (corrompido, protegido por "
      + "senha ou em formato que o provedor não aceita) ou o serviço de IA. Abra o arquivo original: se ele "
      + "não abrir, peça outro ao cliente e reenvie; se abrir normalmente, avise quem cuida do sistema e "
      + "depois reenvie o mesmo arquivo.",
    reenvio: true,
  },
  // falha do n8n ao ler/religar o arquivo: do pipeline, não do arquivo (texto do próprio emissor).
  falha_do_sistema: {
    texto: "a falha foi do sistema, não do arquivo: nenhum dado deste documento chegou ao banco. Avise quem "
      + "cuida do sistema; depois reenvie o mesmo arquivo. Não registre o documento como ilegível sem conferir.",
    reenvio: true,
  },
  resposta_invalida: {
    texto: "a IA devolveu uma resposta que o sistema não conseguiu ler. Pode ser falha pontual do serviço: "
      + "reenvie o arquivo uma vez; se repetir, avise quem cuida do sistema.",
    reenvio: true,
  },
  // Planilha: reenviar o MESMO arquivo repete o corte (teto de linhas/colunas, ou só a 1ª aba).
  planilha_cortada: {
    texto: "só parte da planilha foi enviada à leitura; o que ficou de fora não está no banco nem no book. "
      + "Reenvie o arquivo fatiado (menos linhas e colunas por arquivo) — reenviar o mesmo arquivo repete o corte.",
    reenvio: true,
  },
  xlsx_varias_abas: {
    texto: "só a primeira aba da planilha foi lida e a tabela financeira pode estar em outra. Abra o arquivo, "
      + "salve a aba certa como arquivo próprio e reenvie-a — reenviar o mesmo arquivo lê de novo só a primeira aba.",
    reenvio: true,
  },
  resposta_truncada: {
    texto: "o arquivo está legível, mas é grande ou denso demais para a IA ler numa chamada só. Reenviá-lo "
      + "do mesmo jeito tende a repetir a falha. Confira na revisão do documento o que foi lido e avise quem "
      + "cuida do sistema.",
    reenvio: false,
  },
  sem_linhas: {
    texto: "abra o arquivo original. Se for planilha ou documento de texto, o sistema ainda não converte esse "
      + "formato; se estiver corrompido, vazio ou protegido por senha, peça outro ao cliente e reenvie-o.",
    reenvio: true,
  },
  // 0231: zero linha + a IA declarou "sem dado financeiro" num tipo que traz valores (balanço, DRE,
  // mapa de dívida). Medido em produção em 09/11/2026: 41 documentos assim, sem pendência nenhuma.
  // Não afirma falha: o parecer do auditor e a nota só de texto caem aqui legitimamente.
  declarado_sem_dado: {
    texto: "abra o arquivo original. Se ele de fato não traz números (parecer, nota só de texto), resolva "
      + "esta pendência. Se traz, a leitura falhou: reenvie o mesmo arquivo, que vira uma nova leitura do "
      + "mesmo documento.",
    reenvio: true,
  },
  conferir_na_revisao: {
    texto: "o arquivo foi lido, mas parte dele ficou de fora ou não fecha. Confira o documento na fila de "
      + "revisão antes de usar o book.",
    reenvio: false,
  },
  nao_classificada: { texto: "", reenvio: false }, // o texto depende de haver ou não motivo gravado
};

// Cada família de motivo tem UMA regra: reconhece o início do trecho, devolve a frase em português
// que vai à vista e a ação. A gramática vem de N8N/lib/extract.mjs (~1040–1110, motivos do
// provedor; ~1252 e ~1406, trechos juntados com " | ") e N8N/lib/cobertura.mjs (~957). Medida
// contra os 130 motivos distintos de produção de 06/11/2026 (portal/scripts/fixtures/).
interface RegraDeMotivo { inicio: RegExp; acao: AcaoDeFalha | ((trecho: string) => AcaoDeFalha); vista: (trecho: string) => string }
const fixa = (frase: string) => () => frase;
const primeiro = (m: RegExpMatchArray | null, quando: (m: RegExpMatchArray) => string, senao: string) => (m ? quando(m) : senao);
const maiuscula = (t: string) => t.charAt(0).toUpperCase() + t.slice(1);

function erroDeServidorOuRede(trecho: string): boolean {
  const http = /\(HTTP (\d{3})\)/.exec(trecho) ?? /\[http=(\d{3})/.exec(trecho);
  if (http) return Number(http[1]) >= 500 || Number(http[1]) === 408;
  return /timed? ?out|timeout|econnreset|etimedout|econnrefused|socket hang up|enotfound|bad gateway|service unavailable/i.test(trecho);
}

const REGRAS: RegraDeMotivo[] = [
  { inicio: /^CHAVE DO PROVEDOR/, acao: "servico_de_ia", vista: fixa("Chave do provedor de IA inválida, ausente ou sem permissão.") },
  { inicio: /^CONTA DO PROVEDOR/, acao: "servico_de_ia", vista: fixa("Conta do provedor de IA sem crédito ou sem cobrança ativa.") },
  { inicio: /^COTA DI[ÁA]RIA/, acao: "servico_de_ia", vista: fixa("Cota diária do provedor de IA esgotada.") },
  { inicio: /^LIMITE DE CAD[ÊE]NCIA/, acao: "servico_de_ia", vista: fixa("Limite de chamadas por minuto do provedor de IA atingido.") },
  { inicio: /^LIMITE DO PROVEDOR/, acao: "servico_de_ia", vista: fixa("Limite do provedor de IA atingido (a resposta não disse qual).") },
  { inicio: /^TETO DE GASTO/, acao: "servico_de_ia", vista: fixa("Teto de gasto do provedor de IA atingido.") },
  { inicio: /^MODELO INDISPON[ÍI]VEL/, acao: "servico_de_ia", vista: fixa("Modelo de IA indisponível para esta conta.") },
  // ERRO NA CHAMADA é a SOBRA de `diagnosticarErroApi`: inclui o 400 invalid_request_error (PDF
  // corrompido, o caso de origem da P16). Só afirma culpa do serviço com 5xx/408 ou queda de
  // rede/timeout; 4xx e erro sem causa viram "chamada_incerta" (arquivo OU serviço).
  { inicio: /^ERRO NA CHAMADA/, acao: (t) => (erroDeServidorOuRede(t) ? "servico_de_ia" : "chamada_incerta"),
    vista: (t) => (erroDeServidorOuRede(t) ? "Erro na chamada ao provedor de IA (falha do serviço ou da rede)."
      : "A chamada ao provedor de IA falhou sem causa identificada: pode ser o arquivo ou o serviço.") },
  // O n8n só acrescenta "Try spacing your requests…" em 429 (cadência); outro "Erro da API" é incerto.
  { inicio: /^Erro da API/, acao: (t) => (/spacing your requests|too many requests/i.test(t) ? "servico_de_ia" : "chamada_incerta"),
    vista: (t) => (/spacing your requests|too many requests/i.test(t) ? "Limite de chamadas do provedor de IA atingido."
      : "A chamada ao provedor de IA falhou sem causa identificada: pode ser o arquivo ou o serviço.") },
  { inicio: /^Resposta d[ao].*? sem conte[uú]do/, acao: "servico_de_ia", vista: fixa("O provedor de IA respondeu sem conteúdo (falha de rede ou da API).") },
  { inicio: /^Resposta d[ao].*? truncada/, acao: "resposta_truncada", vista: fixa("A resposta da IA foi cortada por limite de tamanho; o documento é grande ou denso demais para uma chamada só.") },
  { inicio: /^Resposta d[ao].*? atingiu o limite de tokens/, acao: "resposta_truncada", vista: fixa("A resposta da IA atingiu o limite de tamanho; podem faltar linhas do fim do documento.") },
  { inicio: /^Resposta d[ao].*? n[ãa]o veio em JSON v[áa]lido/, acao: "resposta_invalida", vista: fixa("A resposta da IA não veio em formato legível.") },
  { inicio: /^uma linha sozinha j[áa] passa do teto de sa[íi]da/, acao: "resposta_truncada", vista: fixa("Uma linha sozinha já passa do teto de saída do modelo; a resposta deste bloco pode ter vindo cortada.") },
  { inicio: /^Planilha maior que o teto de envio/, acao: "planilha_cortada",
    vista: (t) => primeiro(/^Planilha maior que o teto de envio: (.*?)\. /.exec(t), (m) => `Planilha maior que o teto de envio: ${m[1]}; a extração está incompleta.`, "Planilha maior que o teto de envio; a extração está incompleta.") },
  // As três frases do Agrupar Linhas XLSX desde que ele lê TODAS as abas (3075c8d, 09/11/2026). Sem
  // estas regras as três caíam em "não foi possível classificar a causa" (medido pela revisão).
  { inicio: /^Aba ".*?": Planilha maior que o teto de envio/, acao: "planilha_cortada",
    vista: (t) => primeiro(/^Aba "(.*?)": Planilha maior que o teto de envio/.exec(t), (m) => `A aba "${m[1]}" é maior que o teto de envio; a extração dela está incompleta.`, "Uma aba é maior que o teto de envio; a extração está incompleta.") },
  { inicio: /^A aba ".*?" NAO foi lida pelo extrator/, acao: "xlsx_varias_abas",
    vista: (t) => primeiro(/^A aba "(.*?)" NAO foi lida/.exec(t), (m) => `A aba "${m[1]}" não foi lida; o que ela contém não chegou ao banco.`, "Uma aba não foi lida; o que ela contém não chegou ao banco.") },
  { inicio: /^Os bytes do \.xlsx mostram \d+ planilha\(s\)/, acao: "xlsx_varias_abas",
    vista: (t) => primeiro(/^Os bytes do \.xlsx mostram (\d+) planilha\(s\) e so (\d+) foram listadas/.exec(t), (m) => `A planilha tem ${m[1]} abas e só ${m[2]} foram lidas.`, "Algumas abas da planilha não foram lidas.") },
  { inicio: /^O arquivo \.xlsx teve \d+ aba\(s\) lida\(s\)/, acao: "conferir_na_revisao",
    vista: (t) => primeiro(/^O arquivo \.xlsx teve (\d+) aba\(s\) lida\(s\)/.exec(t), (m) => `As ${m[1]} abas da planilha foram lidas, mas vieram juntas, sem separação por aba.`, "As abas da planilha vieram juntas, sem separação por aba.") },
  { inicio: /^O arquivo \.xlsx tem \d+ planilha\(s\) nos bytes/, acao: "xlsx_varias_abas",
    vista: (t) => primeiro(/^O arquivo \.xlsx tem (\d+) planilha\(s\) nos bytes, mas o workbook listou so (\d+)/.exec(t), (m) => `A planilha tem ${m[1]} abas e só ${m[2]} foram lidas.`, "Algumas abas da planilha não foram lidas.") },
  { inicio: /^O arquivo \.xlsx tem \d+ abas/, acao: "xlsx_varias_abas",
    vista: (t) => primeiro(/^O arquivo \.xlsx tem (\d+) abas/.exec(t), (m) => `A planilha tem ${m[1]} abas e só a primeira foi lida.`, "A planilha tem várias abas e só a primeira foi lida.") },
  { inicio: /^A extra[çc]ao NATIVA/, acao: "falha_do_sistema", vista: fixa("A leitura nativa do arquivo falhou no sistema; nenhum dado deste documento chegou ao banco.") },
  { inicio: /^Recompor Conteudo Extraido/, acao: "falha_do_sistema", vista: fixa("O sistema não conseguiu religar o conteúdo ao documento de origem; nada deste arquivo chegou à extração.") },
  { inicio: /^a leitura declarou que este documento n[ãa]o tem dado financeiro, mas /, acao: "declarado_sem_dado",
    vista: fixa("A leitura não gravou nenhuma linha e declarou que este documento não tem dado financeiro, mas o tipo dele costuma trazer valores.") },
  { inicio: /^a chamada respondeu sem erro, mas n[ãa]o trouxe NENHUMA linha/, acao: "sem_linhas", vista: fixa("A leitura respondeu sem erro, mas não trouxe nenhuma linha deste arquivo.") },
  {
    inicio: /^Extra[çc][ãa]o INCOMPLETA/, acao: "conferir_na_revisao",
    vista: (t) => primeiro(/^Extra[çc][ãa]o INCOMPLETA: (.*?\(\d+% de cobertura[^)]*\))/.exec(t),
      (m) => `Extração incompleta: ${m[1]}.`, "Extração incompleta."),
  },
  {
    inicio: /^identidade de linha não fecha/, acao: "conferir_na_revisao",
    vista: (t) => primeiro(/^identidade de linha não fecha em (".*?"): .*?, mas a coluna (".*?") declara (\S+) — diferença de ([-\d.,]+)/.exec(t),
      (m) => `Uma linha não fecha com o total declarado: ${m[1]}, a coluna ${m[2]} declara ${m[3]} (diferença de ${m[4]}).`,
      "Uma linha não fecha com o total declarado."),
  },
  {
    inicio: /^total da série não fecha/, acao: "conferir_na_revisao",
    vista: (t) => primeiro(/^total da série não fecha em .*? — diferença de [-\d.,]+/.exec(t), (m) => `${maiuscula(m[0])}.`,
      "O total de uma série não fecha com a soma das linhas."),
  },
  {
    inicio: /^\d+ conta\(s\) descartada\(s\) por desalinhamento/, acao: "conferir_na_revisao",
    vista: (t) => primeiro(/^(\d+ conta\(s\) descartada\(s\) por desalinhamento entre colunas e valores)/.exec(t), (m) => `${m[1]}.`,
      "Contas descartadas por desalinhamento entre colunas e valores."),
  },
  {
    inicio: /^\d+ linha\(s\) repetida\(s\) na emenda/, acao: "conferir_na_revisao",
    vista: (t) => primeiro(/^(\d+ linha\(s\) repetida\(s\) na emenda entre blocos foram descartadas)/.exec(t), (m) => `${m[1]}.`,
      "Linhas repetidas na emenda entre blocos foram descartadas."),
  },
  {
    inicio: /^\d+ r[oó]tulo\(s\) com n[uú]mero colado/, acao: "conferir_na_revisao",
    vista: (t) => primeiro(/^(\d+) r[oó]tulo\(s\)/.exec(t),
      (m) => `${m[1]} rótulo(s) com número colado que não é o valor da linha (a conta foi mantida e o rótulo pode não casar na reconciliação).`,
      "Rótulos com número colado."),
  },
];

// Onde um trecho NOVO começa. " | " também aparece DENTRO de um trecho (lista de rótulos de conta
// do cliente: `"15410 | GRADE … | PAGO | MATRIZ"`, 6 dos 130 motivos medidos), então dividir
// cegamente criaria "títulos" que são pedaço de rótulo. Só abre trecho novo quem começa como uma
// família conhecida (ou com "bloco N: "); o resto cola no trecho anterior. TETO conhecido: uma
// família nova, escrita depois de 06/11, que vier após " | " fica colada no trecho anterior e só
// aparece em Detalhes técnicos — nunca some, mas também não é classificada à vista.
const PREFIXO_DE_BLOCO = /^bloco (\d+): /;
function comecaTrecho(pedaco: string): boolean {
  return PREFIXO_DE_BLOCO.test(pedaco) || REGRAS.some((r) => r.inicio.test(pedaco));
}

export function falhaDeExtracaoNaTela(texto: string): FalhaDeExtracaoNaTela {
  const i = texto.indexOf(" Motivo: ");
  const naoClassificada = (tecnico: string | null) => ({
    tipo: "nao_classificada" as const, reenvio: false,
    texto: tecnico
      ? "não foi possível classificar a causa desta falha; o detalhe completo está em Detalhes técnicos, logo abaixo."
      : "não foi possível classificar a causa: o banco não registrou o motivo desta falha.",
  });
  if (i < 0) return { frase: texto, aVista: [], tecnico: null, acoes: [naoClassificada(null)] };
  const motivo = texto.slice(i + " Motivo: ".length).trim();

  const trechos: string[] = [];
  for (const pedaco of motivo.split(" | ")) {
    if (trechos.length === 0 || comecaTrecho(pedaco)) trechos.push(pedaco);
    else trechos[trechos.length - 1] += ` | ${pedaco}`;
  }

  const vistas = new Map<string, { n: number; acao: AcaoDeFalha }>();
  let naoReconhecido = false;
  for (const trecho of trechos) {
    const corpo = trecho.replace(PREFIXO_DE_BLOCO, "");
    const regra = REGRAS.find((r) => r.inicio.test(corpo));
    if (!regra) { naoReconhecido = true; continue; }
    const frase = regra.vista(corpo);
    const antes = vistas.get(frase);
    vistas.set(frase, { n: (antes?.n ?? 0) + 1, acao: typeof regra.acao === "function" ? regra.acao(corpo) : regra.acao });
  }
  const aVista = [...vistas].map(([frase, { n }]) => (n > 1 ? `${frase.replace(/\.$/, "")} (em ${n} trechos).` : frase));
  if (naoReconhecido) aVista.push("Há uma causa que não foi possível classificar; o detalhe está em Detalhes técnicos.");

  const tipos = new Set<AcaoDeFalha>([...vistas.values()].map((v) => v.acao));
  if (naoReconhecido || tipos.size === 0) tipos.add("nao_classificada");
  const acoes = [...tipos].map((tipo) => (tipo === "nao_classificada" ? naoClassificada(motivo) : { tipo, ...ACAO[tipo] }));
  return { frase: texto.slice(0, i).trim(), aVista, tecnico: motivo, acoes };
}
