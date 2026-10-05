import type { AgregadosDoExercicio, BolsaDoExercicio } from "./modelo-institucional";

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
// DE ONDE SAEM OS NÚMEROS. Das MESMAS agregações históricas que o modelo e o export calculam
// (`agregadosDoRealizado`, em `modelo-institucional.ts`): subtotal e cabeçalho de grupo fora da
// soma pela ORDEM impressa do documento, sinal de despesa normalizado, escala única. Este
// arquivo não classifica linha nenhuma — só divide. A versão anterior somava as linhas por
// seção e não enxergava a hierarquia (total do grupo + filhas + netos): medido em produção
// (Fw Valtra, 2025) deu PMR 120 dias onde o documento dá ~40 e SG&A 34,9% onde dá 17,9%.

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

type Bolsa = BolsaDoExercicio & { rotulo: string };

const bolsa = (rotulo: string, b: BolsaDoExercicio): Bolsa => ({ rotulo, ...b });

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
  /**
   * Guarda de MATERIALIDADE do denominador: quando a base é minúscula contra a régua (dívida
   * contra o ativo), a razão explode e vira premissa — medido em produção (Fw Valtra, 2023):
   * despesa financeira 331.329 sobre dívida ~0 devolveu taxa de 8.283.320%. Base imaterial sai
   * sem valor, com o motivo e o efeito.
   */
  imaterial?: string | null,
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
  if (imaterial) return { ...base, porQueNao: imaterial };
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
function razoesDeUmExercicio(a: AgregadosDoExercicio | null): PremissaSugerida[] {
  const zero: BolsaDoExercicio = { valor: 0, n: 0 };
  const g = a ?? {
    receitaBruta: zero, deducoes: zero, custos: zero, sga: zero, tributos: zero,
    despesaFinanceira: zero, financeiroComSinal: 0, clientes: zero, estoques: zero,
    fornecedores: zero, divida: zero, passivoTotal: zero, ativoTotal: zero,
  };
  // A CASCATA DO REALIZADO. Receita líquida é bruta menos deduções, como no
  // modelo — e não a linha "Receita Líquida" impressa, que pode não existir no
  // documento e, quando existe, é subtotal (não soma).
  const receitaBruta = bolsa("receita bruta", g.receitaBruta);
  const receitaLiquida: Bolsa = {
    rotulo: "receita líquida",
    valor: g.receitaBruta.valor - g.deducoes.valor,
    n: g.receitaBruta.n,
  };
  const custos = bolsa("custos", g.custos);
  const sga = bolsa("SG&A", g.sga);
  const tributos = bolsa("tributos sobre o lucro", g.tributos);
  // A TAXA DA DÍVIDA SE MEDE COM O QUE A DÍVIDA CUSTA, e o bloco
  // `resultado_financeiro` tem as DUAS pontas: o juro pago e o rendimento da
  // aplicação. Somar as duas em magnitude INFLA a taxa pelo rendimento. Medido:
  // despesa 9.000 e receita 1.500 sobre dívida de 30.000 devolviam 35% onde o
  // custo é 30%. Cinco pontos de custo de dívida, entrando no modelo como
  // premissa. Por isso `despesaFinanceira` já vem só da despesa.
  const despesaFinanceira = bolsa("despesa financeira", g.despesaFinanceira);

  // O resultado antes dos tributos, pela mesma cascata: RL − custos − SG&A ± financeiro.
  // O sinal do financeiro volta a importar aqui, então ele vem COM sinal.
  const lair: Bolsa = {
    rotulo: "resultado antes dos tributos",
    valor: receitaLiquida.valor - custos.valor - sga.valor + g.financeiroComSinal,
    n: receitaBruta.n > 0 ? 1 : 0,
  };

  const clientes = bolsa("clientes", g.clientes);
  const estoques = bolsa("estoques", g.estoques);
  const fornecedores = bolsa("fornecedores", g.fornecedores);
  // A DÍVIDA ONEROSA atravessa os dois passivos e o mapa de dívida, e é o mesmo
  // `ehDividaFinanceira` que a aba de dívida usa para não deixar empréstimo virar giro.
  const divida = bolsa("dívida financeira", g.divida);
  const passivoTotal = bolsa("passivo total", g.passivoTotal);
  // MATERIALIDADE DA DÍVIDA: abaixo de 1% do ativo total ela não sustenta uma taxa. A régua só
  // vale quando há ativo para comparar — sem ele não se sabe se é imaterial, e ausência de régua
  // não é imaterialidade.
  const motivoSemTaxa = (): string | null => {
    if (divida.n > 0 && g.ativoTotal.valor > 0 && divida.valor < g.ativoTotal.valor * 0.01) {
      return `a dívida financeira deste exercício (${divida.valor.toLocaleString("pt-BR")}) é menor que 1% do ativo `
        + `(${g.ativoTotal.valor.toLocaleString("pt-BR")}): dividir a despesa financeira por ela produz uma taxa `
        + "sem sentido. Efeito: o exercício fica FORA da média da taxa; se nenhum exercício tiver dívida "
        + "material, digite a taxa que o caso vai usar";
    }
    // TAXA ACIMA DE 100% A.A. NÃO É TAXA DA DÍVIDA, é estoque contra fluxo descasado: a despesa
    // do ano veio de dívida que não sobreviveu até o fechamento, ou carrega encargo que não é
    // juro. Medido em produção (Fw Valtra, 2022): despesa 356.567 sobre dívida de fechamento
    // 208.264 (1,44% do ativo, logo ACIMA da régua de 1%) deu 171% e puxou a média de três
    // exercícios de 18% para 69%.
    if (divida.n > 0 && divida.valor > 0 && despesaFinanceira.n > 0 && despesaFinanceira.valor > divida.valor) {
      return `a despesa financeira deste exercício (${despesaFinanceira.valor.toLocaleString("pt-BR")}) é maior que `
        + `a dívida financeira do fechamento (${divida.valor.toLocaleString("pt-BR")}): a taxa passaria de 100% `
        + "ao ano, o que diz que a dívida do ano não é a do fechamento, não qual é o juro. Efeito: o "
        + "exercício fica FORA da média da taxa; se nenhum exercício sobrar, digite a taxa que o caso vai usar";
    }
    return null;
  };

  return [
    razao("CUSTO_VARIAVEL", "Custo variável (% da receita)", "%",
      "custos ÷ receita líquida", custos, receitaLiquida),
    razao("SGA_PCT", "SG&A (% da receita)", "%",
      "SG&A ÷ receita líquida", sga, receitaLiquida),
    razao("PMR", "Prazo médio de recebimento", "dias",
      "clientes ÷ receita líquida × 360", clientes, receitaLiquida, 360),
    // ESTOQUE GIRA CONTRA CUSTO (PME de manual) desde 05/10/2026, decisão do dono. Antes girava
    // contra receita líquida para reproduzir o `Working Capital`; agora o modelo projeta o
    // saldo por `dias/360 × CUSTOS` (`giraContraCusto`) e a aba Output já media CC_PME contra
    // COGS desde a 0116 — projeção e indicador discordavam. A base aqui TEM de ser a do modelo,
    // senão o dia sugerido não reproduz o saldo de onde saiu.
    razao("PME", "Prazo médio de estoque", "dias",
      "estoques ÷ custos × 360", estoques, custos, 360),
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
      "despesa financeira ÷ dívida financeira", despesaFinanceira, divida, 1, undefined, motivoSemTaxa()),
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

export function sugerirDoRealizado(
  agregados: AgregadosDoExercicio[],
  /**
   * Quando NÃO há de onde calcular (sem entidade modelada, por exemplo), o motivo — que
   * substitui o genérico "o caso não tem nenhuma linha de …". Ausência de base e ausência de
   * conta não são a mesma afirmação.
   */
  motivoSemBase?: string,
): PremissaSugerida[] {
  const anos = [...agregados].sort((a, b) => a.ano - b.ano);
  if (anos.length === 0) {
    const vazias = razoesDeUmExercicio(null);
    return motivoSemBase ? vazias.map((p) => ({ ...p, porQueNao: motivoSemBase })) : vazias;
  }

  const porAno = anos.map((a) => ({ ano: a.ano, razoes: razoesDeUmExercicio(a) }));
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
