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
import type { GrandezaCredito, HistoricoCredito, ValorHistorico } from "../modelo-institucional";

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

export interface Valor { v: number | null; nota: string }

export interface BaseCredito {
  cliente: string;
  entidade: string;
  /** unidade do histórico (a do modelo: "R$ mil" ou "R$") */
  unidade: string;
  periodos: PeriodoCredito[];
  documentos: DocumentoDaBase[];
  historico: HistoricoCredito;
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
export function kickerDeNatureza(base: BaseCredito): string {
  const ns = new Set(base.periodos.map((p) => p.natureza));
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
    return nd(`${nome}: n.s. — denominador ${den.v === 0 ? "zero" : "negativo"} (${den.nota})`);
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
export type Veredito = "ok" | "diverge" | "nao_conferivel";
export interface Amarracao { numero: number; nome: string; ano: number | null; veredito: Veredito; detalhe: string }

/** Folga de arredondamento: meia unidade por termo da série (o documento arredonda cada linha). */
const FOLGA = 1;

export function amarracoes(base: BaseCredito): Amarracao[] {
  const out: Amarracao[] = [];
  for (const { ano } of base.periodos) {
    // 2. Ativo = Passivo + PL — contra os totais que o próprio documento imprime.
    const ativo = g(base, "ativo_total", ano);
    const pc = g(base, "passivo_circulante", ano);
    const pnc = g(base, "passivo_nao_circulante", ano);
    const pl = g(base, "patrimonio_liquido", ano);
    if (ativo.v === null || pc.v === null || pnc.v === null || pl.v === null) {
      const falta = [["ativo total", ativo], ["passivo circulante", pc], ["passivo não circulante", pnc], ["PL", pl]]
        .filter(([, x]) => (x as ValorHistorico).v === null).map(([n]) => n as string);
      out.push({ numero: 2, nome: "Ativo = Passivo + PL", ano, veredito: "nao_conferivel",
        detalhe: `o documento não imprime ${falta.join(", ")} — a identidade não pôde ser testada` });
    } else {
      const dif = ativo.v - (pc.v + pnc.v + pl.v);
      out.push({ numero: 2, nome: "Ativo = Passivo + PL", ano, veredito: Math.abs(dif) <= FOLGA * 3 ? "ok" : "diverge",
        detalhe: Math.abs(dif) <= FOLGA * 3 ? "fecha com os totais informados"
          : `diferença de ${dif.toLocaleString("pt-BR", { maximumFractionDigits: 0 })} ${base.unidade} entre o ativo e passivo + PL informados` });
    }
    // 1. EBITDA = EBIT + D&A — o EBITDA daqui é construído assim; o que se confere é se HÁ D&A.
    const d = g(base, "depreciacao", ano);
    out.push({ numero: 1, nome: "EBITDA = EBIT + D&A", ano,
      veredito: d.v === null || g(base, "ebit", ano).v === null ? "nao_conferivel" : "ok",
      detalhe: d.v === null ? "a DRE não traz D&A — EBITDA publicado como n/d"
        : g(base, "ebit", ano).v === null ? "o documento não imprime o EBIT" : "por construção, com a D&A da DRE" });
    // 5. CCL = AC − PC: por construção, desde que os dois totais existam.
    const ac = g(base, "ativo_circulante", ano);
    out.push({ numero: 5, nome: "CCL = AC − PC", ano, veredito: ac.v === null || pc.v === null ? "nao_conferivel" : "ok",
      detalhe: ac.v === null || pc.v === null ? "o documento não imprime AC ou PC" : "por construção, com os totais informados" });
  }
  // As que esta versão ainda não tem como rodar — DITAS, não omitidas.
  out.push({ numero: 3, nome: "Caixa final = inicial + variação", ano: null, veredito: "nao_conferivel",
    detalhe: "o fluxo de caixa (X.3) ainda não é gerado" });
  out.push({ numero: 4, nome: "Dívida bruta = bancos + outras; DFL", ano: null, veredito: "ok",
    detalhe: "por construção, das mesmas contas do balanço" });
  out.push({ numero: 6, nome: "Prazos reconciliam com saldos e receita/CMV", ano: null, veredito: "ok",
    detalhe: `por construção, base de ${DIAS_DO_EXERCICIO} dias` });
  out.push({ numero: 7, nome: "Abertura por credor = dívida do balanço", ano: null, veredito: "nao_conferivel",
    detalhe: "a dívida por credor (XIII) ainda não é gerada" });
  out.push({ numero: 8, nome: "Análise vertical soma 100% por bloco", ano: null, veredito: "nao_conferivel",
    detalhe: "a abertura com AV% (XI.1) ainda não é gerada" });
  return out.sort((a, b) => a.numero - b.numero || (a.ano ?? 0) - (b.ano ?? 0));
}

// -----------------------------------------------------------------------------
// Formatação (padrão do prompt: negativo entre parênteses, unidade no cabeçalho)
// -----------------------------------------------------------------------------
/** Fator do histórico para R$ MM, ou `null` se a unidade não é reconhecida (aí não se converte). */
export function fatorParaMM(unidade: string): number | null {
  const u = unidade.toLowerCase();
  if (/mil/.test(u) && !/milh/.test(u)) return 1 / 1000;
  if (/milh/.test(u)) return 1;
  if (u.trim() === "r$" || /unidade|reais/.test(u)) return 1 / 1_000_000;
  return null;
}

export interface Numero { t: string; negativo: boolean }
const fmt = (v: number, casas: number) =>
  Math.abs(v).toLocaleString("pt-BR", { minimumFractionDigits: casas, maximumFractionDigits: casas });
export const ND: Numero = { t: "n/d", negativo: false };

export function fmtMM(x: Valor, unidade: string): Numero {
  const f = fatorParaMM(unidade);
  if (x.v === null || f === null) return ND;
  const v = x.v * f;
  return { t: v < 0 ? `(${fmt(v, 1)})` : fmt(v, 1), negativo: v < 0 };
}
export function fmtPct(x: Valor | { v: number | null }, casas = 1): Numero {
  if (x.v === null) return ND;
  return { t: x.v < 0 ? `(${fmt(x.v, casas)}%)` : `${fmt(x.v, casas)}%`, negativo: x.v < 0 };
}
export function fmtX(x: Valor): Numero {
  if (x.v === null) return x.nota.includes("n.s.") ? { t: "n.s.", negativo: false } : ND;
  return { t: x.v < 0 ? `(${fmt(x.v, 1)}x)` : `${fmt(x.v, 1)}x`, negativo: x.v < 0 };
}
export function fmtDias(x: Valor): Numero {
  if (x.v === null) return x.nota.includes("n.s.") ? { t: "n.s.", negativo: false } : ND;
  return { t: x.v < 0 ? `(${fmt(x.v, 0)})` : fmt(x.v, 0), negativo: x.v < 0 };
}
