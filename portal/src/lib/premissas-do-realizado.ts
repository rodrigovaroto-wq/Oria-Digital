import {
  blocoDaLinha, ehCliente, ehEstoque, ehFornecedor, ehDividaFinanceira,
  ehDespesaFinanceira, type LinhaModelo,
} from "./modelo-institucional";

// SUGERIR A PREMISSA A PARTIR DO QUE A EMPRESA JÁ FEZ.
//
// O QUE ISTO RESOLVE. A tela de Modelagem pede oito números que o próprio caso já
// responde: quanto o custo consome da receita, quanto o SG&A consome, em quantos
// dias a empresa recebe, estoca e paga, qual a alíquota efetiva, quanto do passivo
// cobra juro e a que taxa. Hoje todos entram em campo vazio, digitados de cabeça
// ou copiados de outro mandato — e campo vazio numa premissa é o começo de um
// modelo que não reproduz o balanço de onde saiu.
//
// A REGRA QUE GOVERNA ESTE ARQUIVO INTEIRO: ZERO NÃO É RESPOSTA. Sem a conta que
// serve de numerador, ou sem a base que serve de denominador, a sugestão não sai —
// sai o motivo. Zero dias de recebimento não é "não sei": é a afirmação de que a
// empresa vende à vista, e é uma afirmação sobre o negócio que ninguém fez. É a
// mesma doutrina do `Arquitetura do Sistema/2 Especificação/f0/08` e a que o `Output` já aplica ao ciclo de caixa.
//
// A BASE DE CADA RAZÃO É A MESMA QUE O MODELO APLICA, e isso não é detalhe. O
// `modelo-institucional` projeta saldo de giro como `dias ÷ 360 × base`, com base
// = CUSTOS para fornecedor e RECEITA LÍQUIDA para o resto. Medir num denominador e
// aplicar noutro é o defeito que o próprio modelo denuncia no Modelo Base (lá o
// prazo do fornecedor é medido contra custo e aplicado sobre receita, inflando o
// passivo projetado em ~1,27×). Aqui a ponta que mede e a ponta que aplica usam a
// mesma base, e é por isso que os classificadores de cliente, estoque e fornecedor
// são importados de lá em vez de reescritos.
//
// SINAL. O documento publica despesa ora positiva, ora negativa, conforme a
// convenção de quem o emitiu. Toda razão daqui usa MAGNITUDE — o que se quer saber
// é o tamanho do custo contra a receita, e o sinal é convenção de partida dobrada,
// não informação econômica.
//
// SUBTOTAL NÃO ENTRA EM SOMA. Somar "Total do Ativo Circulante" junto das contas
// dele conta tudo duas vezes. Só `papel = 'conta'` soma; o subtotal impresso serve
// para conferir, e quem confere é a reconciliação.

/**
 * Uma linha do caso NUM EXERCÍCIO — o que `fn_linhas_do_realizado` (0150) devolve.
 *
 * O `exercicio` é a mudança que permite a média: antes isto recebia um número
 * por rótulo, "a ocorrência de maior módulo" (0042), que numa empresa que encolhe
 * é o ano mais ANTIGO — e a razão calculada dele descrevia um regime que já
 * passou. A `0150` também é quem tira daqui a abertura analítica, o combinado e
 * as outras entidades; este arquivo confia nisso e não refaz o filtro.
 */
export interface LinhaRealizada {
  secao_canonica: string | null;
  chave: string;
  rotulo_norm: string;
  papel: "conta" | "subtotal" | "derivado" | "serie_mensal";
  exercicio?: number;
  valor?: number;
  documentos: string[] | null;
  /**
   * COMPATIBILIDADE COM A CHAMADA ANTIGA. A tela passava `valor_ultimo` sem
   * exercício; enquanto ela não migrar, uma linha sem `exercicio` é tratada como
   * um exercício único e anônimo — o comportamento de antes, declarado em vez de
   * suposto.
   */
  valor_ultimo?: number;
}

export interface PremissaSugerida {
  codigo: string;
  nome: string;
  /**
   * A MÉDIA DOS EXERCÍCIOS, na escala da RAZÃO (fração para `pct_de_linha`, dias
   * para `dias_de_giro`). ATENÇÃO: NÃO é a escala que se grava. A premissa em %
   * é gravada em PONTOS PERCENTUAIS (34 = 34%), que é o que a pessoa digita e o
   * que o modelo divide por 100 (`modelo-institucional.ts`, `v / 100`). Para gravar,
   * use `valorParaGravar`. Era o valor de UM exercício; virou
   * média porque projetar cinco anos a partir do pior ano de uma empresa em
   * reestruturação é projetar a crise como se fosse o regime.
   */
  valor: number | null;
  /** a razão em cada exercício, que é o que torna a média conferível */
  serie?: Array<{ exercicio: number; valor: number }>;
  unidade: "%" | "dias";
  /** como o número foi feito, em uma linha, para quem for discordar dele */
  conta: string;
  numerador: { rotulo: string; valor: number } | null;
  denominador: { rotulo: string; valor: number } | null;
  /** preenchido quando NÃO deu para calcular — e aí `valor` é null */
  porQueNao: string | null;
}

type Bolsa = { rotulo: string; valor: number; n: number };

/** O valor da linha, aceitando a forma antiga (`valor_ultimo`) enquanto ela existir. */
const valorDa = (l: LinhaRealizada): number =>
  Number.isFinite(l.valor) ? Number(l.valor) : Number(l.valor_ultimo ?? 0);

/** Soma as contas (nunca subtotais) que casam com o filtro, em magnitude. */
function somar(linhas: LinhaRealizada[], rotulo: string, filtro: (l: LinhaRealizada) => boolean): Bolsa {
  const escolhidas = linhas.filter((l) => l.papel === "conta" && filtro(l));
  return {
    rotulo,
    valor: escolhidas.reduce((s, l) => s + Math.abs(valorDa(l)), 0),
    n: escolhidas.length,
  };
}

/** `blocoDaLinha` pede um `LinhaModelo`; a tela tem menos campos, e só estes importam. */
const comoModelo = (l: LinhaRealizada): LinhaModelo => ({
  secao_canonica: l.secao_canonica,
  chave: l.chave,
  rotulo_norm: l.rotulo_norm,
  papel: l.papel,
  unidade: null,
  moeda: null,
  documentos: l.documentos,
  valores: {},
});

function razao(
  codigo: string, nome: string, unidade: "%" | "dias", conta: string,
  num: Bolsa, den: Bolsa, fator = 1,
  /**
   * Quando a base só faz sentido POSITIVA, o texto do porquê. Existe porque
   * `den.valor === 0` não é a única base impossível: base NEGATIVA produz uma
   * razão negativa, e uma razão negativa publicada como premissa é pior que a
   * ausência dela — ela entra no modelo e projeta o contrário do que aconteceu.
   */
  basePositivaPorque?: string,
): PremissaSugerida {
  const base: PremissaSugerida = {
    codigo, nome, unidade, conta, valor: null, porQueNao: null,
    numerador: num.n > 0 ? { rotulo: num.rotulo, valor: num.valor } : null,
    denominador: den.n > 0 ? { rotulo: den.rotulo, valor: den.valor } : null,
  };
  if (num.n === 0) {
    return { ...base, porQueNao: `o caso não tem nenhuma linha de ${num.rotulo}` };
  }
  if (den.n === 0 || den.valor === 0) {
    return { ...base, porQueNao: `o caso não tem ${den.rotulo} com valor, e é a base desta conta` };
  }
  if (basePositivaPorque !== undefined && den.valor < 0) {
    return { ...base, porQueNao: basePositivaPorque };
  }
  // NUMERADOR ZERO COM CONTA EXISTENTE é diferente de conta ausente, e passa: uma
  // empresa pode de fato não ter estoque no fechamento. O que não passa é inventar
  // a base.
  return { ...base, valor: Number(((num.valor / den.valor) * fator).toFixed(4)) };
}

/**
 * As oito razões de UM exercício. É o miolo; quem faz a média é
 * `sugerirDoRealizado`, abaixo.
 */
function razoesDeUmExercicio(linhas: LinhaRealizada[]): PremissaSugerida[] {
  const bloco = new Map<string, LinhaRealizada[]>();
  for (const l of linhas) {
    const b = blocoDaLinha(comoModelo(l));
    const lista = bloco.get(b) ?? [];
    lista.push(l);
    bloco.set(b, lista);
  }
  const de = (b: string) => bloco.get(b) ?? [];

  // A CASCATA DO REALIZADO. Receita líquida é bruta menos deduções, como no
  // modelo — e não a linha "Receita Líquida" impressa, que pode não existir no
  // documento e, quando existe, é subtotal (não soma).
  const receitaBruta = somar(de("receita"), "receita bruta", () => true);
  const deducoes = somar(de("deducao"), "deduções da receita", () => true);
  const receitaLiquida: Bolsa = {
    rotulo: "receita líquida",
    valor: receitaBruta.valor - deducoes.valor,
    n: receitaBruta.n,
  };
  const custos = somar(de("custo"), "custos", () => true);
  const sga = somar(de("sga"), "SG&A", () => true);
  const tributos = somar(de("tributos"), "tributos sobre o lucro", () => true);
  // A TAXA DA DÍVIDA SE MEDE COM O QUE A DÍVIDA CUSTA, e o bloco
  // `resultado_financeiro` tem as DUAS pontas: o juro pago e o rendimento da
  // aplicação. Somar as duas em magnitude — que era o que estava aqui — INFLA a
  // taxa pelo rendimento. Medido: despesa 9.000 e receita 1.500 sobre dívida de
  // 30.000 devolviam 35% onde o custo é 30%. Cinco pontos de custo de dívida,
  // entrando no modelo como premissa.
  const despesaFinanceira = somar(de("resultado_financeiro"), "despesa financeira",
    (l) => ehDespesaFinanceira(l.chave));

  // O resultado antes dos tributos, pela mesma cascata: RL − custos − SG&A ± financeiro.
  // O sinal do financeiro volta a importar aqui, então ele é lido da linha e não da
  // magnitude.
  const financeiroComSinal = de("resultado_financeiro")
    .filter((l) => l.papel === "conta")
    .reduce((s, l) => s + valorDa(l), 0);
  const lair: Bolsa = {
    rotulo: "resultado antes dos tributos",
    valor: receitaLiquida.valor - custos.valor - sga.valor + financeiroComSinal,
    n: receitaBruta.n > 0 ? 1 : 0,
  };

  const clientes = somar(de("ativo_circulante"), "clientes", (l) => ehCliente(l.chave));
  const estoques = somar(de("ativo_circulante"), "estoques", (l) => ehEstoque(l.chave));
  const fornecedores = somar(de("passivo_circulante"), "fornecedores", (l) => ehFornecedor(l.chave));

  // A DÍVIDA ONEROSA atravessa os dois passivos e o mapa de dívida, e é o mesmo
  // `ehDividaFinanceira` que a aba de dívida usa para não deixar empréstimo virar
  // giro.
  const passivosTodos = [...de("passivo_circulante"), ...de("passivo_nao_circulante")];
  const divida = somar([...passivosTodos, ...de("divida")], "dívida financeira",
    (l) => ehDividaFinanceira(l.chave) || l.documentos?.includes("MAPA_DIVIDA") === true);
  const passivoTotal = somar(passivosTodos, "passivo total", () => true);

  return [
    razao("CUSTO_VARIAVEL", "Custo variável (% da receita)", "%",
      "custos ÷ receita líquida", custos, receitaLiquida),
    razao("SGA_PCT", "SG&A (% da receita)", "%",
      "SG&A ÷ receita líquida", sga, receitaLiquida),
    razao("PMR", "Prazo médio de recebimento", "dias",
      "clientes ÷ receita líquida × 360", clientes, receitaLiquida, 360),
    // ESTOQUE GIRA CONTRA RECEITA LÍQUIDA e não contra custo, e isso contraria o
    // PME de manual de propósito: é a base que o `Working Capital` aplica ao
    // projetar a conta (só fornecedor gira contra custo). Medir contra custo aqui
    // faria o dia sugerido não reproduzir o saldo de onde ele saiu.
    razao("PME", "Prazo médio de estoque", "dias",
      "estoques ÷ receita líquida × 360", estoques, receitaLiquida, 360),
    razao("PMP", "Prazo médio de pagamento", "dias",
      "fornecedores ÷ custos × 360", fornecedores, custos, 360),
    // ALÍQUOTA COM PREJUÍZO NÃO É ALÍQUOTA NEGATIVA. Este produto atende mandato
    // de REESTRUTURAÇÃO, então LAIR negativo é o caso normal e não a exceção —
    // e tributo dividido por prejuízo devolvia, medido, −5,85%. Uma alíquota
    // negativa aplicada à projeção faz o fisco PAGAR a empresa sobre o lucro
    // futuro: o modelo passa a inventar caixa exatamente na direção que lisonjeia
    // o caso. É a mesma doutrina do `Output`, que se recusa a publicar ROE com PL
    // negativo em vez de imprimir um retorno positivo enganoso.
    razao("ALIQUOTA", "Alíquota efetiva de tributos", "%",
      "tributos sobre o lucro ÷ resultado antes dos tributos", tributos, lair, 1,
      "o resultado antes dos tributos é NEGATIVO neste caso, e alíquota efetiva sobre prejuízo "
      + "não é uma taxa: aplicada à projeção ela devolveria crédito onde há lucro. Digite a "
      + "alíquota que o caso vai usar daqui para frente"),
    razao("PARCELA_ONEROSA", "Parcela onerosa do passivo", "%",
      "dívida financeira ÷ passivo total", divida, passivoTotal),
    razao("TAXA_DIVIDA", "Taxa média da dívida", "%",
      "despesa financeira ÷ dívida financeira", despesaFinanceira, divida),
  ];
}

/**
 * As oito premissas que o próprio realizado responde, na MÉDIA dos exercícios.
 *
 * POR QUE MÉDIA E NÃO O ÚLTIMO ANO. Este produto atende mandato de
 * reestruturação, então o último exercício é, por construção, o pior da série —
 * é o ano que trouxe a empresa até aqui. Projetar cinco anos a partir dele é
 * projetar a crise como se fosse o regime: a margem deprimida vira margem
 * estrutural, o prazo de recebimento esticado pela inadimplência vira política de
 * crédito, e o modelo devolve, com cara de conta, a hipótese de que nada
 * melhora.
 *
 * A MÉDIA É DAS RAZÕES, NÃO A RAZÃO DAS MÉDIAS, e a diferença não é acadêmica:
 * somar três anos de custo e dividir pela soma de três anos de receita deixa o
 * ano de maior faturamento mandar na média — é uma média ponderada pelo tamanho
 * do ano, e ninguém pediu essa ponderação. Média simples das razões dá o mesmo
 * peso a cada exercício, que é o que "como esta empresa costuma operar"
 * significa.
 *
 * E EXERCÍCIO SEM RESPOSTA NÃO ENTRA COMO ZERO. Um ano em que a conta não existe
 * (ou a base é zero) fica FORA da média, com o motivo preservado — a mesma regra
 * que governa cada razão isolada. Se nenhum exercício responder, a premissa sai
 * sem valor e com o porquê do primeiro que falhou, que é o mais informativo.
 */
/**
 * O VALOR QUE O "USAR" GRAVA — na escala do catálogo, não na da razão.
 *
 * O DEFEITO QUE ISTO CORRIGE, medido em 30/09/2026 num mandato de teste em
 * produção (caso bb37f726): o botão "Usar" gravava a fração crua. O Custo
 * variável de 88% ia como `0,8797`, e o modelo, que divide premissa em % por
 * 100, projetou 0,9%. O SG&A de 23,6% virou 0,2%, e o lucro projetado ficou
 * inflado sem erro nenhum. A mesma premissa DIGITADA (88) saía certa, porque
 * a pessoa digita pontos percentuais. As premissas em dias não tinham o
 * problema.
 *
 * Arredondado a 4 casas: `0,8797 × 100` em ponto flutuante é
 * `87,97000000000001`, e esse ruído iria para o banco e para a célula do Excel.
 */
export function valorParaGravar(p: Pick<PremissaSugerida, "valor" | "unidade">): number | null {
  if (p.valor === null) return null;
  if (p.unidade === "%") return Math.round(p.valor * 100 * 10_000) / 10_000;
  return p.valor;
}

export function sugerirDoRealizado(linhas: LinhaRealizada[]): PremissaSugerida[] {
  const porExercicio = new Map<number, LinhaRealizada[]>();
  for (const l of linhas) {
    // Linha sem exercício (a forma antiga) cai num balde só, e aí a "média" é o
    // valor único — o comportamento de antes, sem fingir uma série que não há.
    const ano = Number.isFinite(l.exercicio) ? Number(l.exercicio) : 0;
    const lista = porExercicio.get(ano) ?? [];
    lista.push(l);
    porExercicio.set(ano, lista);
  }

  const anos = [...porExercicio.keys()].sort((a, b) => a - b);
  if (anos.length === 0) return razoesDeUmExercicio([]);

  const porAno = anos.map((ano) => ({ ano, razoes: razoesDeUmExercicio(porExercicio.get(ano)!) }));
  const modelo = porAno[porAno.length - 1].razoes;

  return modelo.map((ref, i) => {
    const serie = porAno
      .map(({ ano, razoes }) => ({ exercicio: ano, valor: razoes[i]?.valor }))
      .filter((x): x is { exercicio: number; valor: number } => typeof x.valor === "number");

    if (serie.length === 0) {
      // Nenhum exercício respondeu: devolve a resposta do mais recente, que já
      // traz o `porQueNao` com o nome da conta que faltou.
      return { ...ref, serie: [] };
    }
    const media = serie.reduce((s, x) => s + x.valor, 0) / serie.length;
    return {
      ...ref,
      valor: Number(media.toFixed(4)),
      serie,
      conta: serie.length === 1
        ? `${ref.conta} (exercício ${serie[0].exercicio})`
        : `${ref.conta} — média simples de ${serie.length} exercícios `
          + `(${serie.map((x) => x.exercicio).join(", ")})`,
      porQueNao: null,
    };
  });
}
