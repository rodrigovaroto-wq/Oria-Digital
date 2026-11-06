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
