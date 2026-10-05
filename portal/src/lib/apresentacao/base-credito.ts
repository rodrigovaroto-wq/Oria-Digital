// A BASE FINANCEIRA DA APRESENTAÇÃO DE CRÉDITO — indicadores, tags de natureza e amarrações.
//
// É o `data.py` que o Prompt-Mestre v3 pede ("base de dados financeira, com as amarrações
// executáveis"), sem I/O: recebe o realizado já classificado (`historicoParaCredito`, o mesmo do
// modelo institucional) e a lista de documentos, e devolve número, nota e veredito. O gerador do
// deck só desenha o que sai daqui.
//
// AS DUAS REGRAS QUE ESTE ARQUIVO IMPÕE, e que são as do módulo de crédito do prompt:
//   • ZERO EXTRAPOLAÇÃO. Todo número é do documento ou sai dele por fórmula que a nota escreve.
//     Faltou um termo, o resultado é `null` — a tabela imprime `n/d` e a nota diz qual termo faltou
//     e o que isso impede (regra 1 do projeto: ausência nunca vira zero).
//   • AMARRAÇÃO QUE NÃO RODOU NÃO É AMARRAÇÃO QUE PASSOU. Cada uma devolve `ok`, `diverge` ou
//     `nao_conferivel` com o motivo — e as três aparecem no slide de notas. Uma lista só com as que
//     fecharam teria a mesma cara de "tudo amarrado" num caso em que metade não pôde ser conferida
//     (regra 7).
import type { ProjecaoDoModelo } from "./projecao";
import type { GrandezaCredito, HistoricoCredito, OperacaoDivida, ValorHistorico } from "../modelo-institucional";

/** `(A)` auditada · `(R)` revisão limitada · `(B)` não auditada/balancete · `(G)` gerencial. */
export type Natureza = "A" | "R" | "B" | "G";

export interface DocumentoDaBase {
  tipo: string | null;
  arquivo: string | null;
  /** rótulo do período como o export já formata ("2024", "2024 e 2025", …) */
  periodo: string;
  /** exercícios que o documento cobre */
  anos: number[];
}

export interface PeriodoCredito {
  ano: number;
  natureza: Natureza;
  /** por que essa natureza — vai para a linha de fontes */
  motivoNatureza: string;
}

/**
 * `ns` = NÃO SIGNIFICATIVO: o documento trouxe os termos, mas a conta não tem leitura (denominador
 * zero ou negativo, sinal trocado). É diferente de `n/d` (termo ausente) e o deck imprime os dois de
 * forma distinta — NCG negativa não é "linha que o documento não traz".
 */
export interface Valor { v: number | null; nota: string; ns?: boolean }

export interface BaseCredito {
  cliente: string;
  entidade: string;
  /** unidade do histórico (a do modelo: "R$ mil" ou "R$") */
  unidade: string;
  periodos: PeriodoCredito[];
  documentos: DocumentoDaBase[];
  historico: HistoricoCredito;
  /**
   * Os campos "[a preencher]" que alguém já preencheu (`caso_apresentacao_campo`, 0201), por chave
   * estável ("ii2.cartao1", "xvii.nota.rentabilidade"…). Ausente ou sem a chave = a lacuna continua
   * "[a preencher]" — nunca um texto inventado no lugar.
   */
  campos?: Record<string, { valor: string; fonte: string | null }>;
  /**
   * O que chegou e o que faltou dos documentos obrigatórios (kit básico), com a MESMA regra da tela
   * do caso (`itensDoKitBasicoAtendidos`, que pergunta ao banco pelo combinado estrutural). Ausente =
   * a rota não leu; o slide diz isso em vez de afirmar que nada faltou.
   */
  informacao?: Array<{ codigo: string; documento: string; status: "recebido" | "sem_conteudo" | "faltante" }>;
  /** As empresas cadastradas no caso — o perímetro — e qual delas o deck analisa. */
  /**
   * O ANO EM CURSO (balancete): o mesmo realizado, classificado pelo mesmo `historicoParaCredito`, para
   * o exercício posterior ao último fechado. `meses` = quantos meses o balancete cobre (n/d quando o
   * período do documento não diz) — resultado parcial nunca é comparado com exercício cheio.
   */
  corrente?: { ano: number; meses: number | null; historico: HistoricoCredito } | null;
  /** A DRE projetada que o modelo institucional calcula (`projecao.ts`), com a cobertura de premissas. */
  projecao?: ProjecaoDoModelo | null;
  /** Entidades do caso cujo MAPA DA DÍVIDA chegou, quando não é a analisada (ex.: o do "GRUPO"). */
  mapasDeOutrasEntidades?: string[];
  perimetro?: Array<{ razaoSocial: string; cnpj: string | null; papel: string | null; documentos: number; analisada: boolean }>;
}

/**
 * A natureza de um exercício, pelos TIPOS de documento que o cobrem.
 *
 * Só `DF_AUDITADA` vira `(A)`: o sistema não lê o parecer, então um balanço avulso pode até ser
 * auditado, mas nada nos documentos recebidos diz isso. Marcar `(A)` sem parecer seria apresentar
 * suposição como dado; `(B)` com o motivo escrito é o que se sabe. `(R)` não é atribuído
 * automaticamente pela mesma razão.
 */
export function naturezaDoAno(ano: number, documentos: DocumentoDaBase[]): PeriodoCredito {
  const tipos = new Set(documentos.filter((d) => d.anos.includes(ano)).map((d) => d.tipo ?? ""));
  if (tipos.has("DF_AUDITADA")) {
    return { ano, natureza: "A", motivoNatureza: `${ano}: demonstrações auditadas entre os documentos recebidos` };
  }
  if (tipos.has("BALANCETE") && !tipos.has("BALANCO") && !tipos.has("COMBINADO")) {
    return { ano, natureza: "B", motivoNatureza: `${ano}: balancete` };
  }
  return { ano, natureza: "B", motivoNatureza: `${ano}: sem parecer de auditoria entre os documentos recebidos` };
}

export const TAG_NATUREZA: Record<Natureza, string> = { A: "(A)", R: "(R)", B: "(B)", G: "(G)" };
export const LEGENDA_NATUREZA = "(A) auditada · (R) revisão limitada · (B) não auditada / balancete · (G) gerencial";

/** O kicker direito dos slides financeiros: "[CLIENTE] · NÃO AUDITADO" / "· AUDITADO" / misto. */
export function kickerDeNatureza(base: BaseCredito, periodos: PeriodoCredito[] = base.periodos): string {
  const ns = new Set(periodos.map((p) => p.natureza));
  const rotulo = ns.size === 1 && ns.has("A") ? "AUDITADO" : ns.has("A") ? "AUDITADO + NÃO AUDITADO" : "NÃO AUDITADO";
  return `${base.cliente} · ${rotulo}`;
}

// -----------------------------------------------------------------------------
// Aritmética com ausência
// -----------------------------------------------------------------------------
const g = (base: BaseCredito, k: GrandezaCredito, ano: number): ValorHistorico =>
  base.historico.grandezas[k][ano] ?? { v: null, origem: `${k}: exercício ${ano} fora do histórico` };

const nd = (nota: string): Valor => ({ v: null, nota });

/** Razão com o denominador nomeado: zero ou negativo onde não faz sentido não vira número. */
function razao(num: Valor, den: Valor, nome: string, fator = 1, exigePositivo = false): Valor {
  if (num.v === null) return nd(`${nome}: n/d porque ${num.nota}`);
  if (den.v === null) return nd(`${nome}: n/d porque ${den.nota}`);
  if (den.v === 0 || (exigePositivo && den.v < 0)) {
    return { v: null, ns: true, nota: `${nome}: n.s. — denominador ${den.v === 0 ? "zero" : "negativo"} (${den.nota})` };
  }
  return { v: (num.v / den.v) * fator, nota: `${nome} = ${num.nota} ÷ ${den.nota}` };
}

/** Soma em que componente AUSENTE é declarado, e só tudo ausente vira `n/d`. */
function somaDeclarada(partes: Array<[string, ValorHistorico]>, nome: string): Valor {
  const presentes = partes.filter(([, x]) => x.v !== null);
  if (presentes.length === 0) return nd(`${nome}: n/d — ${partes.map(([, x]) => x.origem).join("; ")}`);
  const ausentes = partes.filter(([, x]) => x.v === null).map(([n]) => n);
  return {
    v: presentes.reduce((t, [, x]) => t + (x.v as number), 0),
    nota: `${nome} = ${presentes.map(([n]) => n).join(" + ")}`
      + (ausentes.length ? ` (sem conta de ${ausentes.join(", ")} no balanço deste exercício)` : ""),
  };
}

const deHistorico = (x: ValorHistorico): Valor => ({ v: x.v, nota: x.origem });

/** Base de dias: exercício anual fechado = 360. O histórico do modelo só tem exercício fechado. */
export const DIAS_DO_EXERCICIO = 360;

export interface Indicadores {
  receita: Valor; lucroBruto: Valor; ebit: Valor; da: Valor; ebitda: Valor; lucroLiquido: Valor;
  margemEbitda: Valor; margemEbit: Valor; margemLiquida: Valor;
  pl: Valor; ativo: Valor; ac: Valor; pc: Valor; ccl: Valor;
  caixa: Valor; bancos: Valor; outras: Valor; dividaBruta: Valor; dfl: Valor;
  dflEbitda: Valor; dflEbitdaExOutras: Valor; liquidezCorrente: Valor; alavancagem: Valor;
  clientes: Valor; estoques: Valor; fornecedores: Valor; custos: Valor;
  pmr: Valor; pme: Valor; pmp: Valor; ciclo: Valor;
  /** dívida bancária de curto prazo — o numerador da "conta central" do XI.2 */
  bancosCP: Valor;
  /** NCG = clientes + estoques − fornecedores */
  ncg: Valor;
  /** % da NCG financiada por dívida bancária de CP */
  ncgFinanciadaCP: Valor;
}

export function indicadores(base: BaseCredito, ano: number): Indicadores {
  const H = (k: GrandezaCredito) => deHistorico(g(base, k, ano));
  const receita = H("receita_liquida");
  const ebit = H("ebit");
  const daBruta = g(base, "depreciacao", ano);
  // EBITDA SÓ COM D&A INFORMADA. Sem a linha de depreciação na DRE, `EBITDA = EBIT` subestimaria a
  // geração de caixa por exatamente a D&A — e é do EBITDA que sai a alavancagem. O modelo
  // institucional faz EBITDA = EBIT nesse caso e DIZ isso na nota; aqui, onde não há nota de célula
  // e o número vai para manchete, o certo é `n/d`.
  const da: Valor = deHistorico(daBruta);
  const ebitda: Valor = ebit.v === null ? nd(`EBITDA: n/d porque ${ebit.nota}`)
    : da.v === null ? nd(`EBITDA: n/d porque a DRE de ${ano} não traz linha de depreciação/amortização — `
      + "EBITDA = EBIT a subestimaria pela D&A")
    : { v: ebit.v + da.v, nota: `EBITDA = EBIT + D&A (${da.nota})` };
  const lucroLiquido = H("lucro_liquido");
  const caixa = H("caixa");
  const bancos = somaDeclarada([["dívida bancária CP", g(base, "divida_bancos_cp", ano)],
    ["dívida bancária LP", g(base, "divida_bancos_lp", ano)]], "Bancos");
  const outras = somaDeclarada([["outras dívidas CP", g(base, "divida_outras_cp", ano)],
    ["outras dívidas LP", g(base, "divida_outras_lp", ano)]], "Outras dívidas");
  const dividaBruta = bancos.v === null && outras.v === null
    ? nd(`Dívida financeira bruta: n/d — nenhuma conta de dívida classificada no balanço de ${ano}`)
    : { v: (bancos.v ?? 0) + (outras.v ?? 0),
        nota: `Dívida financeira bruta = bancos + outras dívidas${bancos.v === null ? " (sem dívida bancária no balanço)" : ""}`
          + `${outras.v === null ? " (sem outras dívidas no balanço)" : ""}` };
  const dfl: Valor = dividaBruta.v === null ? nd(dividaBruta.nota)
    : caixa.v === null ? nd(`DFL: n/d porque ${caixa.nota}`)
    : { v: dividaBruta.v - caixa.v, nota: "DFL = dívida bruta − caixa e aplicações" };
  const ac = H("ativo_circulante");
  const pc = H("passivo_circulante");
  const ccl: Valor = ac.v === null || pc.v === null ? nd(`CCL: n/d porque ${(ac.v === null ? ac : pc).nota}`)
    : { v: ac.v - pc.v, nota: "CCL = ativo circulante − passivo circulante" };
  const custos = H("custos");
  const clientes = H("clientes");
  const estoques = H("estoques");
  const fornecedores = H("fornecedores");
  const pmr = razao(clientes, receita, "PMR", DIAS_DO_EXERCICIO, true);
  const pme = razao(estoques, custos, "PME", DIAS_DO_EXERCICIO, true);
  const pmp = razao(fornecedores, custos, "PMP", DIAS_DO_EXERCICIO, true);
  const ciclo: Valor = pmr.v === null || pme.v === null || pmp.v === null
    ? nd(`Ciclo financeiro: n/d porque ${[pmr, pme, pmp].find((x) => x.v === null)!.nota}`)
    : { v: pmr.v + pme.v - pmp.v, nota: "Ciclo financeiro = PMR + PME − PMP" };
  const pl = H("patrimonio_liquido");
  const ativo = H("ativo_total");
  const exOutras: Valor = bancos.v === null ? nd("DFL ex-outras: n/d — sem dívida bancária no balanço")
    : caixa.v === null ? nd(`DFL ex-outras: n/d porque ${caixa.nota}`)
    : { v: bancos.v - caixa.v, nota: "DFL ex-outras = bancos − caixa" };
  const bancosCP = H("divida_bancos_cp");
  const faltaGiro = [clientes, estoques, fornecedores].find((x) => x.v === null);
  const ncg: Valor = faltaGiro ? nd(`NCG: n/d porque ${faltaGiro.nota}`)
    : { v: (clientes.v as number) + (estoques.v as number) - (fornecedores.v as number),
        nota: "NCG = clientes + estoques − fornecedores" };
  // "Quanto da NCG está financiada por dívida bancária de CP" (XI.2 do prompt). NCG zero ou
  // negativa não é financiada por ninguém: n.s., não 0% nem um percentual negativo.
  const ncgFinanciadaCP = razao(bancosCP, ncg, "Dívida bancária CP / NCG", 100, true);
  return {
    receita, lucroBruto: H("lucro_bruto"), ebit, da, ebitda, lucroLiquido, bancosCP, ncg, ncgFinanciadaCP,
    margemEbitda: razao(ebitda, receita, "Margem EBITDA", 100, true),
    margemEbit: razao(ebit, receita, "Margem EBIT", 100, true),
    margemLiquida: razao(lucroLiquido, receita, "Margem líquida", 100, true),
    pl, ativo, ac, pc, ccl, caixa, bancos, outras, dividaBruta, dfl,
    dflEbitda: razao(dfl, ebitda, "DFL/EBITDA", 1, true),
    dflEbitdaExOutras: razao(exOutras, ebitda, "DFL/EBITDA (ex-outras)", 1, true),
    liquidezCorrente: razao(ac, pc, "Liquidez corrente", 1, true),
    alavancagem: razao(ativo, pl, "Alavancagem (ativo/PL)", 1, true),
    clientes, estoques, fornecedores, custos, pmr, pme, pmp, ciclo,
  };
}

/**
 * Variação % entre dois períodos HOMOGÊNEOS. Base negativa ou zero, ou sinal trocado = "n.s."
 * (Cap. XII do prompt): −10 → +5 não é "−150%" de coisa nenhuma.
 */
export function variacao(de: number | null, para: number | null): { v: number | null; ns: boolean } {
  if (de === null || para === null) return { v: null, ns: false };
  if (de <= 0 || (para !== 0 && Math.sign(de) !== Math.sign(para))) return { v: null, ns: true };
  return { v: (para / de - 1) * 100, ns: false };
}

// -----------------------------------------------------------------------------
// Amarrações (seção "Amarrações obrigatórias antes de exportar o módulo")
// -----------------------------------------------------------------------------
/**
 * `ok`/`diverge` são CONFERÊNCIA: duas pontas independentes comparadas. `por_construcao` é
 * DEFINIÇÃO (o deck calcula a grandeza assim, então ela "fecha" por tautologia) e é impressa como
 * tal, nunca como "Fecha" — imprimir "Fecha" para uma definição dava ao slide de notas a cara de
 * uma conferência que não aconteceu (regra 7). `nao_conferivel` = faltou insumo.
 */
export type Veredito = "ok" | "diverge" | "por_construcao" | "nao_conferivel";
export interface Amarracao { numero: number; nome: string; ano: number | null; veredito: Veredito; detalhe: string }

/** Folga de arredondamento por termo: o documento arredonda cada linha à unidade da série. */
const FOLGA_POR_TERMO = 1;
const fmtDif = (v: number, unidade: string) => `${v.toLocaleString("pt-BR", { maximumFractionDigits: 0 })} ${unidade}`;

export function amarracoes(base: BaseCredito, periodos: PeriodoCredito[] = base.periodos): Amarracao[] {
  const out: Amarracao[] = [];
  /** Conferência de duas pontas: `esquerda` contra a soma de `termos`, com folga por termo. */
  const conferir = (numero: number, nome: string, ano: number, esquerda: [string, ValorHistorico],
    termos: Array<[string, ValorHistorico, 1 | -1]>, okTxt: string) => {
    const falta = [esquerda, ...termos].filter(([, x]) => x.v === null).map(([n]) => n);
    if (falta.length) {
      out.push({ numero, nome, ano, veredito: "nao_conferivel", detalhe: `falta ${falta.join(", ")} no documento` });
      return;
    }
    if (esquerda[1].calculado) {
      // O total não veio impresso: ele SAIU desta mesma conta, então compará-la consigo é tautologia.
      out.push({ numero, nome, ano, veredito: "por_construcao", detalhe: `${esquerda[0]} calculado pela Oria (o documento não imprime o total)` });
      return;
    }
    const dif = (esquerda[1].v as number) - termos.reduce((t, [, x, sinal]) => t + sinal * (x.v as number), 0);
    const fecha = Math.abs(dif) <= FOLGA_POR_TERMO * (termos.length + 1);
    out.push({ numero, nome, ano, veredito: fecha ? "ok" : "diverge",
      detalhe: fecha ? okTxt : `diferença de ${fmtDif(dif, base.unidade)}` });
  };
  for (const { ano } of periodos) {
    const G = (k: GrandezaCredito) => g(base, k, ano);
    // 2. Ativo = Passivo + PL — contra os totais que o próprio documento imprime.
    conferir(2, "Ativo = Passivo + PL", ano, ["ativo total", G("ativo_total")],
      [["passivo circulante", G("passivo_circulante"), 1], ["passivo não circulante", G("passivo_nao_circulante"), 1],
        ["PL", G("patrimonio_liquido"), 1]], "fecha com os totais informados");
    // 9. Lucro bruto informado = receita líquida informada − custos somados das contas.
    conferir(9, "Lucro bruto = receita − custos", ano, ["lucro bruto", G("lucro_bruto")],
      [["receita líquida", G("receita_liquida"), 1], ["custos", G("custos"), -1]], "as contas de custo reproduzem o total");
    // 10. EBIT informado = lucro bruto − SG&A. É o que pega o "resultado operacional" da DRE no
    // formato antigo (já depois do resultado financeiro): o deck soma D&A a esse EBIT, e um EBIT
    // que já desconta juro subestimaria o EBITDA e inflaria a alavancagem sem aviso nenhum.
    conferir(10, "EBIT = lucro bruto − despesas operacionais", ano, ["EBIT", G("ebit")],
      [["lucro bruto", G("lucro_bruto"), 1], ["despesas operacionais", G("sga"), -1]], "a cascata reproduz o EBIT informado");
    // 1 e 5 são DEFINIÇÃO: dizem só se os insumos existem.
    const d = G("depreciacao");
    out.push({ numero: 1, nome: "EBITDA = EBIT + D&A", ano,
      veredito: d.v === null || G("ebit").v === null ? "nao_conferivel" : "por_construcao",
      detalhe: d.v === null ? "a DRE não traz D&A — EBITDA publicado como n/d"
        : G("ebit").v === null ? "o documento não imprime o EBIT" : "definição, com a D&A da DRE" });
    const semCirc = G("ativo_circulante").v === null || G("passivo_circulante").v === null;
    out.push({ numero: 5, nome: "CCL = AC − PC", ano, veredito: semCirc ? "nao_conferivel" : "por_construcao",
      detalhe: semCirc ? "o documento não imprime AC ou PC" : "definição, com os totais informados" });
    const ind = indicadores(base, ano);
    out.push({ numero: 4, nome: "Dívida bruta = bancos + outras; DFL", ano,
      veredito: ind.dfl.v === null ? "nao_conferivel" : "por_construcao",
      detalhe: ind.dfl.v === null ? limpar(ind.dfl.nota) : "definição, das mesmas contas do balanço" });
    const prazos = [ind.pmr, ind.pme, ind.pmp];
    out.push({ numero: 6, nome: "Prazos reconciliam com saldos e receita/CMV", ano,
      veredito: prazos.every((x) => x.v === null) ? "nao_conferivel" : "por_construcao",
      detalhe: prazos.every((x) => x.v === null) ? "nenhum prazo calculável neste exercício"
        : `definição, base de ${DIAS_DO_EXERCICIO} dias` });
  }
  // As que esta versão ainda não tem como rodar — DITAS, não omitidas.
  out.push({ numero: 3, nome: "Caixa final = inicial + variação", ano: null, veredito: "nao_conferivel",
    detalhe: "o fluxo de caixa (X.3) ainda não é gerado" });
  // 7. A abertura por credor contra o TOTAL do próprio mapa e contra a dívida do balanço. Divergência
  // acima de 2% entre mapa e balanço é o que o Prompt-Mestre manda explicar (data-base diferente,
  // juros a apropriar, mútuo de sócio que o balanço classifica fora da dívida bancária).
  for (const { ano } of periodos) {
    const ops = base.historico.operacoes.filter((o) => o.saldo[ano] != null);
    if (ops.length === 0) continue;
    const soma = ops.reduce((t, o) => t + (o.saldo[ano] as number), 0);
    const total = base.historico.totalDoMapa[ano];
    if (total != null) {
      const fecha = Math.abs(soma - total) <= FOLGA_POR_TERMO * (ops.length + 1);
      out.push({ numero: 7, nome: "Abertura por credor = total do mapa", ano, veredito: fecha ? "ok" : "diverge",
        detalhe: fecha ? `${ops.length} operações somam o total impresso` : `diferença de ${fmtDif(soma - total, base.unidade)}` });
    }
    const bruta = indicadores(base, ano).dividaBruta.v;
    if (bruta !== null && bruta > 0) {
      const dif = (soma - bruta) / bruta;
      out.push({ numero: 7, nome: "Mapa da dívida = dívida do balanço (±2%)", ano, veredito: Math.abs(dif) <= 0.02 ? "ok" : "diverge",
        detalhe: Math.abs(dif) <= 0.02 ? "o mapa reproduz o balanço"
          : `mapa ${dif > 0 ? "acima" : "abaixo"} do balanço em ${fmtDif(soma - bruta, base.unidade)}; explicar` });
    }
  }
  if (!out.some((a) => a.numero === 7)) {
    out.push({ numero: 7, nome: "Abertura por credor = dívida do balanço", ano: null, veredito: "nao_conferivel",
      detalhe: "nenhum mapa da dívida entre os documentos recebidos" });
  }
  out.push({ numero: 8, nome: "Análise vertical soma 100% por bloco", ano: null, veredito: "nao_conferivel",
    detalhe: "a abertura com AV% (XI.1) ainda não é gerada" });
  return out.sort((a, b) => a.numero - b.numero || (a.ano ?? 0) - (b.ano ?? 0));
}
const limpar = (nota: string) => nota.replace(/^.*?n\/d (porque|—) /, "");

// -----------------------------------------------------------------------------
// Alavancagem contra o múltiplo-alvo do Cap. XV
// -----------------------------------------------------------------------------
/** Múltiplo-alvo de DFL/EBITDA do Cap. XV do prompt ("tipicamente 2,5x–3,5x"). */
export const MULTIPLO_ALVO = { min: 2.5, max: 3.5 } as const;
export type FaixaAlavancagem = "ebitda_nao_positivo" | "caixa_liquido" | "abaixo" | "faixa" | "acima" | "nd";
/** UMA classificação para manchete, implicação e leitura — três testes soltos já se contradisseram
 * no mesmo slide ("caixa supera a dívida" ao lado de "cabe na faixa-alvo"). */
export function faixaDeAlavancagem(x: Indicadores): FaixaAlavancagem {
  if (x.ebitda.v !== null && x.ebitda.v <= 0) return "ebitda_nao_positivo";
  const m = x.dflEbitda.v;
  if (m === null) return "nd";
  if (m < 0) return "caixa_liquido";
  if (m < MULTIPLO_ALVO.min) return "abaixo";
  return m <= MULTIPLO_ALVO.max ? "faixa" : "acima";
}

// -----------------------------------------------------------------------------
// Formatação (padrão do prompt: negativo entre parênteses, unidade no cabeçalho)
// -----------------------------------------------------------------------------
/** Fator do histórico para R$ MM, pela escala em que o MODELO deixou os valores (`escalaDoModelo`). */
export const fatorParaMM = (escala: "milhar" | "reais"): number => (escala === "milhar" ? 1 / 1000 : 1 / 1_000_000);

export interface Numero { t: string; negativo: boolean }
const fmt = (v: number, casas: number) =>
  Math.abs(v).toLocaleString("pt-BR", { minimumFractionDigits: casas, maximumFractionDigits: casas });
export const ND: Numero = { t: "n/d", negativo: false };

const NS: Numero = { t: "n.s.", negativo: false };
export function fmtMM(x: Valor, escala: "milhar" | "reais"): Numero {
  if (x.v === null) return x.ns ? NS : ND;
  const v = x.v * fatorParaMM(escala);
  return { t: v < 0 ? `(${fmt(v, 1)})` : fmt(v, 1), negativo: v < 0 };
}
export function fmtPct(x: Valor | { v: number | null; ns?: boolean }, casas = 1): Numero {
  if (x.v === null) return x.ns ? NS : ND;
  return { t: x.v < 0 ? `(${fmt(x.v, casas)}%)` : `${fmt(x.v, casas)}%`, negativo: x.v < 0 };
}
export function fmtX(x: Valor): Numero {
  if (x.v === null) return x.ns ? NS : ND;
  return { t: x.v < 0 ? `(${fmt(x.v, 1)}x)` : `${fmt(x.v, 1)}x`, negativo: x.v < 0 };
}
export function fmtDias(x: Valor): Numero {
  if (x.v === null) return x.ns ? NS : ND;
  return { t: x.v < 0 ? `(${fmt(x.v, 0)})` : fmt(x.v, 0), negativo: x.v < 0 };
}

// -----------------------------------------------------------------------------
// O endividamento pelo MAPA DA DÍVIDA (XIII) e a cobertura por ativos reais (XVI)
// -----------------------------------------------------------------------------
export interface CredorAgregado { credor: string; saldo: number; juros: number | null }
export interface DividaDoMapa {
  ano: number;
  operacoes: Array<OperacaoDivida & { saldoAno: number; jurosAno: number | null; taxa: number | null }>;
  credores: CredorAgregado[];
  modalidades: Array<{ modalidade: string; saldo: number }>;
  total: number;
  /** juros do exercício ÷ saldo final, ponderado — calculado pela Oria; n/d sem juros no mapa */
  custoMedio: number | null;
}

/** O mapa do exercício mais recente que tem operação; `null` sem mapa da dívida. */
export function dividaDoMapa(base: BaseCredito, anos: number[]): DividaDoMapa | null {
  const ano = [...anos].reverse().find((a) => base.historico.operacoes.some((o) => o.saldo[a] != null));
  if (ano === undefined) return null;
  const ops = base.historico.operacoes.filter((o) => o.saldo[ano] != null).map((o) => {
    const saldoAno = o.saldo[ano] as number;
    const jurosAno = o.juros[ano] ?? null;
    // TAXA IMPLÍCITA = juros do exercício ÷ saldo FINAL. É aproximação (o saldo médio não vem no
    // mapa) e sai marcada como calculada; operação amortizada no ano sai com taxa superestimada.
    return { ...o, saldoAno, jurosAno, taxa: jurosAno !== null && saldoAno > 0 ? (jurosAno / saldoAno) * 100 : null };
  }).sort((a, b) => b.saldoAno - a.saldoAno);
  const agrega = <K extends string>(chave: (o: (typeof ops)[number]) => K) => {
    const m = new Map<K, { saldo: number; juros: number | null }>();
    for (const o of ops) {
      const k = chave(o);
      const atual = m.get(k) ?? { saldo: 0, juros: 0 };
      m.set(k, { saldo: atual.saldo + o.saldoAno, juros: atual.juros === null || o.jurosAno === null ? null : atual.juros + o.jurosAno });
    }
    return [...m.entries()].sort((a, b) => b[1].saldo - a[1].saldo);
  };
  const total = ops.reduce((t, o) => t + o.saldoAno, 0);
  const comJuros = ops.filter((o) => o.jurosAno !== null);
  const saldoComJuros = comJuros.reduce((t, o) => t + o.saldoAno, 0);
  return {
    ano, operacoes: ops, total,
    credores: agrega((o) => o.credor).map(([credor, v]) => ({ credor, ...v })),
    modalidades: agrega((o) => o.modalidade).map(([modalidade, v]) => ({ modalidade, saldo: v.saldo })),
    custoMedio: saldoComJuros > 0 ? (comJuros.reduce((t, o) => t + (o.jurosAno as number), 0) / saldoComJuros) * 100 : null,
  };
}

export interface AtivoReal { nome: string; contabil: number | null; realizacao: number | null; estimado: number | null }
/**
 * Os ativos reais possíveis de garantia — recebíveis, estoques e imobilizado tangível — e a
 * realização (%) que o analista informou (`xvi.realizacao.*`). Sem realização, `estimado` é null:
 * nenhum haircut é inventado (sem laudo, o Prompt-Mestre exige a premissa declarada).
 */
export function ativosReais(base: BaseCredito, ano: number): AtivoReal[] {
  const I = indicadores(base, ano);
  const real = (k: string) => {
    const v = Number((base.campos?.[`xvi.realizacao.${k}`]?.valor ?? "").replace("%", "").replace(",", "."));
    return Number.isFinite(v) && v > 0 && v <= 100 ? v : null;
  };
  return ([["Recebíveis (clientes)", "clientes", I.clientes.v], ["Estoques", "estoques", I.estoques.v],
    ["Imobilizado tangível (imóveis, máquinas, veículos)", "imobilizado", base.historico.grandezas.imobilizado[ano]?.v ?? null]] as const)
    .map(([nome, k, contabil]) => {
      const r = real(k);
      return { nome, contabil, realizacao: r, estimado: contabil !== null && r !== null ? contabil * r / 100 : null };
    });
}
