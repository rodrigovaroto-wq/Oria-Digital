// O MÓDULO DE CRÉDITO DA APRESENTAÇÃO INICIAL — FASE 4 do Prompt-Mestre Oria v3, versão de base.
//
// O QUE ESTA VERSÃO GERA, e por que é só isto. O prompt tem duas metades de natureza diferente:
//   • a que SAI DOS NÚMEROS — base de informação (IX), evolução (X.1, X.2), capital de giro
//     (XI.2), comparativo (XII) e as amarrações. É o que o banco deste sistema tem, com
//     proveniência, e é o que este arquivo gera inteiro, sem uma frase escrita à mão;
//   • a que EXIGE JULGAMENTO OU INSUMO QUE O SISTEMA AINDA NÃO TEM — pesquisa de setor e
//     societário (FASES 1–3), dívida por credor e muro de vencimentos (XIII, precisa do mapa da
//     dívida estruturado), normalização do EBITDA (XIV, ajuste com confiança), dívida sustentável
//     (XV), garantias (XVI), scorecard (XVII) e síntese (XVIII).
// A segunda metade NÃO vira slide com espaço em branco nem nota fabricada: ela é listada no slide
// "Notas e fontes" como não gerada, com o que falta para gerá-la. Um scorecard com nota inventada
// teria a mesma cara de um scorecard calibrado (regra 7) — e o prompt diz "nunca apresente a nota
// final sem as notas por eixo".
//
// AS MANCHETES E IMPLICAÇÕES SÃO REGRAS, NÃO REDAÇÃO. O prompt pede manchete que é conclusão
// ("47% da NCG está financiada por dívida bancária de curto prazo"). Aqui cada uma é escolhida por
// um teste explícito sobre o número, e os limiares citados são os do próprio prompt (múltiplo-alvo
// de 2,5x–3,5x no XV). Quando o número que a regra precisa é `n/d`, a manchete DIZ que não dá para
// concluir — nunca escolhe a frase mais confortável.
import {
  DeckOria, COR, GRADE, capa, card, chrome, contracapa, divisoria, kpi, p, tabela,
  type ColunaTabela, type LinhaTabela, type Paragrafo, type SlideOria, type Celula,
} from "./pptx-oria";
import {
  LEGENDA_NATUREZA, TAG_NATUREZA, amarracoes, fmtDias, fmtMM, fmtPct, fmtX, indicadores, kickerDeNatureza,
  variacao, type Amarracao, type BaseCredito, type Indicadores, type Numero, type Valor,
} from "./base-credito";

const MESES = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro",
  "outubro", "novembro", "dezembro"];
/** Múltiplo-alvo de DFL/EBITDA do Cap. XV do prompt ("tipicamente 2,5x–3,5x"). */
export const MULTIPLO_ALVO = { min: 2.5, max: 3.5 } as const;
/** Até 4 colunas de período por slide (Cap. X do prompt). */
const MAX_PERIODOS = 4;

const cel = (n: Numero, extra: Partial<Celula> = {}): Celula => ({ t: n.t, negativo: n.negativo, ...extra });
/** Percentual em prosa: sinal explícito em vez de parênteses ("−91,7%"), que dentro de uma frase
 * entre parênteses viraria "((91,7%))". */
const pctTexto = (v: number, casas = 1) => `${v < 0 ? "−" : ""}${fmtPct({ v: Math.abs(v) }, casas).t}`;
const mm1 = (v: number) => (v / 1).toLocaleString("pt-BR", { minimumFractionDigits: 1, maximumFractionDigits: 1 });

export interface SaidaDeck {
  deck: DeckOria;
  /** o que NÃO foi gerado e por quê — também vai para o slide de notas */
  naoGerado: string[];
  amarracoes: Amarracao[];
}

export function construirDeckCredito(base: BaseCredito, agora: Date): SaidaDeck {
  const deck = new DeckOria(`${base.cliente} — Apresentação de crédito`);
  const periodos = base.periodos.slice(-MAX_PERIODOS);
  if (periodos.length === 0) {
    throw new Error("apresentação de crédito: nenhum exercício fechado com valor — não há o que apresentar. "
      + "Confira o último exercício real na tela de Modelagem e a extração dos balanços.");
  }
  const anos = periodos.map((x) => x.ano);
  const ind = new Map(anos.map((a) => [a, indicadores(base, a)]));
  const ultimo = anos[anos.length - 1];
  const anterior = anos.length >= 2 ? anos[anos.length - 2] : null;
  const I = ind.get(ultimo)!;
  const Iant = anterior !== null ? ind.get(anterior)! : null;
  const kDir = kickerDeNatureza(base);
  const fontes = fontesFinanceiras(base, anos);
  const am = amarracoes({ ...base, periodos });
  const mm = (x: Valor) => fmtMM(x, base.unidade);
  const colsPeriodo = (w: number): ColunaTabela[] => periodos.map((x) => ({ titulo: String(x.ano), tag: TAG_NATUREZA[x.natureza], w }));
  const unidadeCab = "R$ MM";

  const naoGerado = [
    "Caps. I–VIII (setor, societário, empresa, cadeia de valor, concorrência, SWOT): exigem a pesquisa das FASES 1–3",
    "X.3 Fluxo de caixa reconstruído: a ponte entre dois balanços ainda não é montada",
    "XI.1 Composição do CCL com AV%: a abertura conta a conta ainda não é publicada",
    "XIII Endividamento por credor e muro de vencimentos: o mapa da dívida ainda não chega por operação",
    "XIV–XVIII Normalização, dívida sustentável, garantias, scorecard e síntese: exigem julgamento do analista",
    "YTD/LTM: só exercícios fechados entram; o balancete do ano corrente fica de fora desta versão",
  ];

  // ---- 1. Capa ---------------------------------------------------------------
  capa(deck.novo(COR.sage), {
    kicker: "Apresentação inicial · Módulo de crédito",
    titulo: "Levantamento e Diagnóstico",
    subtitulo: "Financeiro e crédito",
    meta: `${encurtar(`${base.cliente} — ${base.entidade}`, 60)}  ·  Confidencial  ·  ${capitalizar(MESES[agora.getMonth()])} de ${agora.getFullYear()}`,
  });

  // ---- 2. Sumário ------------------------------------------------------------
  const capitulos = [
    ["Base de informação e evolução financeira", "Qualidade dos dados · resultado · estrutura de capital e prazos"],
    ["Capital de giro e comparativo", "NCG e seu financiamento · exercícios homogêneos lado a lado"],
    ["Notas e fontes", "Amarrações conferidas e o que esta versão ainda não gera"],
  ];
  {
    const s = deck.novo();
    chrome(s, { kickerEsq: "Sumário", kickerDir: base.cliente, manchete: "Sumário",
      fontes: "Módulo de crédito gerado a partir das demonstrações extraídas e conferidas no portal Oria." });
    capitulos.forEach(([t, d], i) => {
      const x = GRADE.margem + (i % 2) * (GRADE.util / 2 + 0.15);
      const y = GRADE.conteudoTopo + 0.2 + Math.floor(i / 2) * 1.0;
      s.texto(x, y, 0.8, 0.6, [p(String(i + 1).padStart(2, "0"), { serifa: true, sz: 22, cor: COR.laranja })], "t");
      s.texto(x + 0.8, y, GRADE.util / 2 - 1.0, 0.3, [p(t, { b: true, sz: 13, cor: COR.grafite })], "t");
      s.texto(x + 0.8, y + 0.34, GRADE.util / 2 - 1.0, 0.5, [p(d)], "t");
      s.fio(x, y + 0.85, GRADE.util / 2 - 0.15, 0);
    });
  }

  // ---- 3. Sumário executivo (Layout B) ---------------------------------------
  {
    const s = deck.novo();
    chrome(s, { kickerEsq: "Sumário executivo", kickerDir: kDir, manchete: mancheteExecutiva(I), fontes });
    const varRec = Iant ? variacao(Iant.receita.v, I.receita.v) : { v: null, ns: false };
    const kpis = [
      { valor: valorMM(I.receita, base.unidade), label: `Receita líquida ${ultimo}`,
        descritor: anterior === null ? "exercício único no histórico" : varRec.ns ? `n.s. vs ${anterior}` : varRec.v === null ? `variação vs ${anterior}: n/d` : `${pctTexto(varRec.v)} vs ${anterior}` },
      { valor: valorMM(I.ebitda, base.unidade), label: `EBITDA ${ultimo}`,
        descritor: I.margemEbitda.v === null ? "margem n/d" : `margem ${fmtPct(I.margemEbitda).t}` },
      { valor: fmtX(I.dflEbitda).t, label: "DFL / EBITDA",
        descritor: `alvo de ${mm1(MULTIPLO_ALVO.min)}x–${mm1(MULTIPLO_ALVO.max)}x (Cap. XV)`,
        destaque: I.dflEbitda.v !== null && I.dflEbitda.v > MULTIPLO_ALVO.max },
      { valor: fmtX(I.liquidezCorrente).t, label: "Liquidez corrente", descritor: `AC ÷ PC em ${ultimo}` },
    ];
    const wK = 2.6;
    const gapK = (GRADE.util - 4 * wK) / 3;
    kpis.forEach((k, i) => kpi(s, GRADE.margem + i * (wK + gapK), GRADE.conteudoTopo + 0.1, wK, k));
    const wP = (GRADE.util - GRADE.gapPainel) / 2;
    const yP = 3.15;
    card(s, GRADE.margem, yP, wP, GRADE.conteudoBase - yP, { rotulo: "Diagnóstico",
      corpo: diagnostico(I, Iant, anterior, base.unidade).map((t) => p(t, { bullet: true })) });
    card(s, GRADE.margem + wP + GRADE.gapPainel, yP, wP, GRADE.conteudoBase - yP, { rotulo: "Implicação para o mandato",
      destaque: true, corpo: implicacoes(I).map((t) => p(t, { bullet: true })) });
  }

  // ---- 4. Divisória 01 -------------------------------------------------------
  divisoria(deck.novo(COR.sage), { numero: 1, titulo: capitulos[0][0], subtitulo: capitulos[0][1] });

  // ---- 5. IX — Base de informação (Layout H) ---------------------------------
  {
    const s = deck.novo();
    const temAuditada = base.periodos.some((x) => x.natureza === "A");
    chrome(s, { kickerEsq: "IX · Base de informação", kickerDir: kDir,
      manchete: temAuditada ? "Há demonstração auditada na base; ela calibra as conclusões"
        : "Nenhuma demonstração auditada: as conclusões indicam direção",
      fontes: `Fontes: documentos recebidos da companhia, extraídos no portal Oria. ${LEGENDA_NATUREZA}.` });
    const docs = base.documentos.slice(0, 7);
    const linhas: LinhaTabela[] = docs.map((d) => ({ celulas: [
      d.periodo, d.tipo ? rotuloTipo(d.tipo) : "não classificado",
      d.tipo === "DF_AUDITADA" ? "(A) auditada" : d.tipo === "BALANCETE" ? "(B) balancete" : "(B) sem parecer",
      encurtar(d.arquivo ?? "—", 46),
    ] }));
    if (base.documentos.length > docs.length) {
      linhas.push({ celulas: [`+ ${base.documentos.length - docs.length} documento(s)`, "ver aba Documentos do export", "", ""] });
    }
    const yFim = tabela(s, GRADE.margem, GRADE.conteudoTopo, [
      { titulo: "Data-base", w: 2.0 }, { titulo: "Documento", w: 3.0, algn: "l" },
      { titulo: "Natureza", w: 2.0, algn: "l" }, { titulo: "Arquivo", w: 4.63, algn: "l" },
    ], linhas);
    const yC = Math.min(yFim + 0.25, 4.3);
    const wC = (GRADE.util - GRADE.gapPainel) / 2;
    card(s, GRADE.margem, yC, wC, GRADE.conteudoBase - yC, { rotulo: "Limitações da análise", destaque: true, corpo: [
      p("O parecer do auditor não é lido pelo sistema: opinião, ressalvas e ênfases precisam ser conferidas no documento.", { bullet: true }),
      p(`Só exercícios fechados entram (${anos.join(", ")}); balancete do ano corrente fica fora desta versão.`, { bullet: true }),
      p(contarND(ind) === 0 ? "Nenhum indicador saiu n/d nos exercícios apresentados."
        : `${contarND(ind)} indicador(es) saíram n/d por falta de linha no documento; o motivo está nas notas.`, { bullet: true }),
    ] });
    card(s, GRADE.margem + wC + GRADE.gapPainel, yC, wC, GRADE.conteudoBase - yC, { rotulo: "Pontos de atenção contábil",
      corpo: pontosDeAtencao(base, ind, am).map((t) => p(t, { bullet: true })) });
  }

  // ---- 6. X.1 — Resultado (Layout I) -----------------------------------------
  // Layout I: a tabela ocupa ≈7,9 in; com poucos períodos a coluna alarga até 1,6 in, não mais.
  const wPer = Math.min(1.6, 4.8 / periodos.length);
  const xLat = GRADE.margem + 7.9 + 0.23;
  const wLat = GRADE.margem + GRADE.util - xLat;
  {
    const s = deck.novo();
    chrome(s, { kickerEsq: "X.1 · Resultado", kickerDir: kDir, manchete: mancheteResultado(I, Iant, ultimo, anterior), fontes });
    const L = (rot: string, f: (x: Indicadores) => Numero, extra: Partial<Celula> = {}, tipo?: LinhaTabela["tipo"]): LinhaTabela =>
      ({ celulas: [{ t: rot, ...extra }, ...anos.map((a) => cel(f(ind.get(a)!), extra))], tipo });
    tabela(s, GRADE.margem, GRADE.conteudoTopo, [{ titulo: unidadeCab, w: 3.1 }, ...colsPeriodo(wPer)], [
      L("Receita líquida", (x) => mm(x.receita)),
      L("Lucro bruto", (x) => mm(x.lucroBruto)),
      L("EBITDA", (x) => mm(x.ebitda), { b: true }),
      L("Margem EBITDA", (x) => fmtPct(x.margemEbitda), { i: true }),
      L("EBIT", (x) => mm(x.ebit)),
      L("Margem EBIT", (x) => fmtPct(x.margemEbit), { i: true }),
      L("Lucro líquido", (x) => mm(x.lucroLiquido), { b: true }, "total"),
      L("Margem líquida", (x) => fmtPct(x.margemLiquida), { i: true }),
    ]);
    card(s, xLat, GRADE.conteudoTopo, wLat, GRADE.conteudoBase - GRADE.conteudoTopo, { rotulo: "Leitura", destaque: true,
      corpo: leituraResultado(ind, anos, base.unidade).map((t) => p(t, { bullet: true })) });
  }

  // ---- 7. X.2 — Estrutura de capital e prazos (Layout I) ---------------------
  {
    const s = deck.novo();
    chrome(s, { kickerEsq: "X.2 · Estrutura de capital e prazos", kickerDir: kDir, manchete: mancheteAlavancagem(I, ultimo),
      fontes });
    const L = (rot: string, f: (x: Indicadores) => Numero, extra: Partial<Celula> = {}, tipo?: LinhaTabela["tipo"]): LinhaTabela =>
      ({ celulas: [{ t: rot, ...extra }, ...anos.map((a) => cel(f(ind.get(a)!), extra))], tipo });
    const y0 = GRADE.conteudoTopo;
    tabela(s, GRADE.margem, y0, [{ titulo: unidadeCab, w: 3.1 }, ...colsPeriodo(wPer)], [
      L("Patrimônio líquido", (x) => mm(x.pl)),
      L("Dívida financeira bruta", (x) => mm(x.dividaBruta), { b: true }),
      L("— Bancos", (x) => mm(x.bancos)),
      L("— Outras dívidas", (x) => mm(x.outras)),
      L("Caixa e aplicações", (x) => mm(x.caixa)),
      L("Ativo total", (x) => mm(x.ativo)),
      L("DFL/EBITDA", (x) => fmtX(x.dflEbitda), { b: true }),
      L("DFL/EBITDA (ex-outras)", (x) => fmtX(x.dflEbitdaExOutras)),
      L("Liquidez corrente", (x) => fmtX(x.liquidezCorrente)),
      L("Alavancagem (ativo/PL)", (x) => fmtX(x.alavancagem)),
      L("PME (dias)", (x) => fmtDias(x.pme)),
      L("PMR (dias)", (x) => fmtDias(x.pmr)),
      L("PMP (dias)", (x) => fmtDias(x.pmp)),
      L("Ciclo financeiro (dias)", (x) => fmtDias(x.ciclo), { b: true }),
    ]);
    // O contorno laranja de 1,25 pt agrupando DFL/EBITDA–Alavancagem (linhas 7 a 10).
    s.forma(GRADE.margem, y0 + 0.5 + 6 * 0.3, 3.1 + periodos.length * wPer, 4 * 0.3, undefined,
      { contorno: { cor: COR.laranja, pt: 1.25 } });
    card(s, xLat, GRADE.conteudoTopo, wLat, GRADE.conteudoBase - GRADE.conteudoTopo, { rotulo: "Leitura", destaque: true,
      corpo: leituraEstrutura(I, ultimo, base.unidade).map((t) => p(t, { bullet: true })) });
  }

  // ---- 8. Divisória 02 -------------------------------------------------------
  divisoria(deck.novo(COR.sage), { numero: 2, titulo: capitulos[1][0], subtitulo: capitulos[1][1] });

  // ---- 9. XI.2 — NCG e prazos (Layout J) -------------------------------------
  {
    const s = deck.novo();
    const fin = I.ncgFinanciadaCP;
    chrome(s, { kickerEsq: "XI.2 · NCG e prazos", kickerDir: kDir,
      manchete: fin.v === null ? `NCG de ${ultimo}: o financiamento por dívida de CP não pôde ser medido`
        : fin.v > 100 ? `Dívida bancária de CP equivale a ${fmtPct({ v: fin.v }, 0).t} da NCG de ${ultimo}`
        : `${fmtPct({ v: fin.v }, 0).t} da NCG de ${ultimo} está financiada por dívida bancária de CP`,
      fontes });
    const L = (rot: string, f: (x: Indicadores) => Numero, extra: Partial<Celula> = {}, tipo?: LinhaTabela["tipo"]): LinhaTabela =>
      ({ celulas: [{ t: rot, ...extra }, ...anos.map((a) => cel(f(ind.get(a)!), extra))], tipo });
    const anos3 = periodos.slice(-3);
    const colunas: ColunaTabela[] = [{ titulo: unidadeCab, w: 3.2 }, ...anos3.map((x) => ({ titulo: String(x.ano), tag: TAG_NATUREZA[x.natureza], w: 1.2 }))];
    const L3 = (l: LinhaTabela): LinhaTabela => ({ ...l, celulas: [l.celulas[0], ...l.celulas.slice(1).slice(-anos3.length)] });
    tabela(s, GRADE.margem, GRADE.conteudoTopo, colunas, [
      L("CCL", (x) => mm(x.ccl)),
      L("Clientes", (x) => mm(x.clientes)),
      L("Estoques", (x) => mm(x.estoques)),
      L("(−) Fornecedores", (x) => mm(x.fornecedores)),
      L("NCG", (x) => mm(x.ncg), { b: true }, "total"),
      L("Dívida bancária CP", (x) => mm(x.bancosCP)),
      L("Dívida bancária CP / NCG", (x) => fmtPct(x.ncgFinanciadaCP, 0)),
      L("PMR (dias)", (x) => fmtDias(x.pmr)),
      L("PME (dias)", (x) => fmtDias(x.pme)),
      L("PMP (dias)", (x) => fmtDias(x.pmp)),
      L("Ciclo financeiro (dias)", (x) => fmtDias(x.ciclo), { b: true }),
      L("Receita líquida", (x) => mm(x.receita)),
    ].map(L3));
    const xJ = GRADE.margem + 3.2 + anos3.length * 1.2 + 0.3;
    card(s, xJ, GRADE.conteudoTopo, GRADE.margem + GRADE.util - xJ, GRADE.conteudoBase - GRADE.conteudoTopo, {
      rotulo: "A conta central da reestruturação", destaque: true, corpo: leituraNcg(I, ultimo, base.unidade).map((t) => p(t, { bullet: true })) });
  }

  // ---- 10. XII — Comparativo entre exercícios (Layout H) ---------------------
  if (anterior !== null && Iant) {
    const s = deck.novo();
    chrome(s, { kickerEsq: "XII · Comparativo entre exercícios", kickerDir: kDir,
      manchete: mancheteComparativo(I, Iant, ultimo, anterior),
      fontes });
    const pa = periodos[periodos.length - 2];
    const pu = periodos[periodos.length - 1];
    const V = (rot: string, f: (x: Indicadores) => Valor, fmtv: (x: Valor) => Numero, extra: Partial<Celula> = {}): LinhaTabela => {
      const a = f(Iant); const u = f(I);
      // Prazo compara em DIAS, não em %: "PMR +2,0%" esconde que são 2 dias de giro.
      if (fmtv === fmtDias) {
        const d = a.v === null || u.v === null ? null : u.v - a.v;
        return { celulas: [{ t: rot, ...extra }, cel(fmtv(a), extra), cel(fmtv(u), extra),
          d === null ? "n/d" : { t: d < 0 ? `(${Math.abs(Math.round(d))} d)` : `+${Math.round(d)} d`, negativo: d < 0 }] };
      }
      const vr = variacao(a.v, u.v);
      return { celulas: [{ t: rot, ...extra }, cel(fmtv(a), extra), cel(fmtv(u), extra),
        vr.ns ? "n.s." : vr.v === null ? "n/d" : cel(fmtPct({ v: vr.v }))] };
    };
    tabela(s, GRADE.margem, GRADE.conteudoTopo, [
      { titulo: unidadeCab, w: 3.2 }, { titulo: String(pa.ano), tag: TAG_NATUREZA[pa.natureza], w: 1.3 },
      { titulo: String(pu.ano), tag: TAG_NATUREZA[pu.natureza], w: 1.3 }, { titulo: "Var.", w: 1.2 },
    ], [
      V("Receita líquida", (x) => x.receita, mm),
      V("Lucro bruto", (x) => x.lucroBruto, mm),
      V("EBITDA", (x) => x.ebitda, mm, { b: true }),
      V("EBIT", (x) => x.ebit, mm),
      V("Lucro líquido", (x) => x.lucroLiquido, mm, { b: true }),
      V("Dívida financeira bruta", (x) => x.dividaBruta, mm),
      V("Caixa e aplicações", (x) => x.caixa, mm),
      V("DFL", (x) => x.dfl, mm, { b: true }),
      V("Patrimônio líquido", (x) => x.pl, mm),
      V("PMR (dias)", (x) => x.pmr, fmtDias),
      V("PME (dias)", (x) => x.pme, fmtDias),
      V("PMP (dias)", (x) => x.pmp, fmtDias),
    ]);
    const xC = GRADE.margem + 7.0 + 0.3;
    card(s, xC, GRADE.conteudoTopo, GRADE.margem + GRADE.util - xC, GRADE.conteudoBase - GRADE.conteudoTopo, {
      rotulo: "Implicação", destaque: true, corpo: leituraComparativo(I, Iant, ultimo, anterior).map((t) => p(t, { bullet: true })) });
  } else {
    naoGerado.push("XII Comparativo entre exercícios: só há um exercício fechado no histórico");
  }

  // ---- 11. Notas e fontes (Layout H) — amarrações e o que não foi gerado -----
  notasEFontes(deck, base, am, naoGerado, ind, anos);

  // ---- 12. Contracapa --------------------------------------------------------
  contracapa(deck.novo(COR.sage));

  return { deck, naoGerado, amarracoes: am };
}

// -----------------------------------------------------------------------------
// Manchetes e leituras — regras explícitas sobre o número
// -----------------------------------------------------------------------------
const valorMM = (x: Valor, unidade: string) => {
  const n = fmtMM(x, unidade);
  return n.t === "n/d" ? "n/d" : `R$ ${n.t} MM`;
};

function mancheteExecutiva(I: Indicadores): string {
  const m = I.dflEbitda;
  if (I.ebitda.v !== null && I.ebitda.v <= 0) return "EBITDA não positivo: a dívida não tem geração que a sirva";
  if (m.v === null) return "Alavancagem não mensurável com o que o documento informa";
  if (m.v > MULTIPLO_ALVO.max) return `DFL/EBITDA de ${fmtX(m).t}, acima do teto de ${mm1(MULTIPLO_ALVO.max)}x sustentável`;
  if (m.v < 0) return "Caixa supera a dívida: o tema é liquidez e rentabilidade, não solvência";
  return `DFL/EBITDA de ${fmtX(m).t}, dentro da faixa de ${mm1(MULTIPLO_ALVO.min)}x–${mm1(MULTIPLO_ALVO.max)}x`;
}

function diagnostico(I: Indicadores, Iant: Indicadores | null, anterior: number | null, unidade: string): string[] {
  const out: string[] = [];
  if (Iant && anterior !== null) {
    const v = variacao(Iant.receita.v, I.receita.v);
    out.push(v.v === null ? `Receita líquida ${valorMM(I.receita, unidade)}; variação vs ${anterior} ${v.ns ? "n.s." : "n/d"}.`
      : `Receita líquida de ${valorMM(I.receita, unidade)}, ${pctTexto(v.v)} vs ${anterior}.`);
  } else out.push(`Receita líquida de ${valorMM(I.receita, unidade)}.`);
  out.push(I.margemEbitda.v === null ? "Margem EBITDA n/d — ver notas para o termo que falta."
    : `Margem EBITDA de ${fmtPct(I.margemEbitda).t}; margem líquida de ${fmtPct(I.margemLiquida).t}.`);
  out.push(I.dividaBruta.v === null ? "Dívida financeira não identificada no balanço."
    : `Dívida bruta de ${valorMM(I.dividaBruta, unidade)} contra caixa de ${valorMM(I.caixa, unidade)}.`);
  out.push(I.ciclo.v === null ? "Ciclo financeiro n/d — falta saldo de giro ou custo na DRE."
    : `Ciclo financeiro de ${fmtDias(I.ciclo).t} dias (PMR ${fmtDias(I.pmr).t} · PME ${fmtDias(I.pme).t} · PMP ${fmtDias(I.pmp).t}).`);
  return out;
}

function implicacoes(I: Indicadores): string[] {
  const out: string[] = [];
  const m = I.dflEbitda.v;
  if (I.ebitda.v !== null && I.ebitda.v <= 0) {
    out.push("Sem EBITDA positivo, qualquer alongamento só adia: o plano precisa começar pela operação.");
  } else if (m !== null && m > MULTIPLO_ALVO.max) {
    out.push(`Acima de ${mm1(MULTIPLO_ALVO.max)}x, alongar não basta: o dimensionamento do Cap. XV define o esforço.`);
  } else if (m !== null) {
    out.push("Alavancagem na faixa-alvo: o mandato tende a reperfilamento e otimização de capital.");
  } else {
    out.push("Alavancagem não mensurada: obter D&A e a abertura da dívida antes de dimensionar.");
  }
  if (I.liquidezCorrente.v !== null && I.liquidezCorrente.v < 1) {
    out.push(`Liquidez corrente de ${fmtX(I.liquidezCorrente).t}: o passivo de curto prazo excede o ativo circulante.`);
  }
  if (I.ciclo.v !== null && I.ciclo.v > 90) {
    out.push(`Ciclo de ${fmtDias(I.ciclo).t} dias: o giro é alavanca de caixa antes de qualquer deságio.`);
  }
  out.push("Conclusões calibradas por documentos sem parecer lido pelo sistema; confirmar na diligência.");
  return out.slice(0, 4);
}

function mancheteResultado(I: Indicadores, Iant: Indicadores | null, ultimo: number, anterior: number | null): string {
  if (Iant && anterior !== null) {
    const v = variacao(Iant.ebitda.v, I.ebitda.v);
    if (I.ebitda.v !== null && I.ebitda.v <= 0) return `EBITDA não positivo em ${ultimo}`;
    if (v.v !== null && v.v <= -20) return `EBITDA caiu ${fmtPct({ v: -v.v }, 0).t} entre ${anterior} e ${ultimo}`;
    if (v.v !== null && v.v >= 20) return `EBITDA cresceu ${fmtPct({ v: v.v }, 0).t} entre ${anterior} e ${ultimo}`;
    const r = variacao(Iant.receita.v, I.receita.v);
    if (r.v !== null) return `Receita ${r.v < 0 ? "recuou" : "avançou"} ${fmtPct({ v: Math.abs(r.v) }, 0).t} em ${ultimo}, margem EBITDA ${I.margemEbitda.v === null ? "n/d" : fmtPct(I.margemEbitda).t}`;
  }
  return I.margemEbitda.v === null ? `Resultado de ${ultimo}: EBITDA não mensurável pela DRE` : `Margem EBITDA de ${fmtPct(I.margemEbitda).t} em ${ultimo}`;
}

function leituraResultado(ind: Map<number, Indicadores>, anos: number[], unidade: string): string[] {
  const u = ind.get(anos[anos.length - 1])!;
  const a = anos.length >= 2 ? ind.get(anos[anos.length - 2])! : null;
  const out: string[] = [];
  if (a) {
    const dr = u.receita.v !== null && a.receita.v !== null ? u.receita.v - a.receita.v : null;
    out.push(dr === null ? "Variação da receita n/d." : `Receita ${dr < 0 ? "perdeu" : "ganhou"} ${valorMM({ v: Math.abs(dr), nota: "" }, unidade)} no último exercício.`);
    const de = u.ebitda.v !== null && a.ebitda.v !== null ? u.ebitda.v - a.ebitda.v : null;
    out.push(de === null ? "Variação do EBITDA n/d — ver notas." : `EBITDA ${de < 0 ? "recuou" : "avançou"} ${valorMM({ v: Math.abs(de), nota: "" }, unidade)}.`);
  }
  out.push(u.lucroLiquido.v === null ? "Lucro líquido n/d." : u.lucroLiquido.v < 0
    ? `Prejuízo de ${valorMM({ v: -u.lucroLiquido.v, nota: "" }, unidade)}: o PL absorve a perda.`
    : `Lucro líquido de ${valorMM(u.lucroLiquido, unidade)}.`);
  if (u.da.v === null) out.push("A DRE não traz D&A: EBITDA publicado como n/d em vez de igualado ao EBIT.");
  return out.slice(0, 4);
}

function mancheteAlavancagem(I: Indicadores, ultimo: number): string {
  if (I.dflEbitda.v === null) return I.dfl.v === null ? `Dívida líquida de ${ultimo} não mensurável pelo balanço` : `DFL/EBITDA de ${ultimo} sem referência: EBITDA ${I.ebitda.v === null ? "n/d" : "não positivo"}`;
  return `DFL/EBITDA de ${fmtX(I.dflEbitda).t} em ${ultimo}, com ciclo de ${fmtDias(I.ciclo).t} dias`;
}

function leituraEstrutura(I: Indicadores, ultimo: number, unidade: string): string[] {
  const out: string[] = [];
  if (I.dflEbitda.v !== null) {
    out.push(I.dflEbitda.v > MULTIPLO_ALVO.max
      ? `A ${fmtX(I.dflEbitda).t}, a dívida líquida excede o teto de ${mm1(MULTIPLO_ALVO.max)}x do EBITDA de ${ultimo}.`
      : `A ${fmtX(I.dflEbitda).t}, a dívida líquida cabe na faixa-alvo de ${mm1(MULTIPLO_ALVO.min)}x–${mm1(MULTIPLO_ALVO.max)}x.`);
  } else out.push("DFL/EBITDA n/d: a alavancagem não pode ser dimensionada com estes documentos.");
  if (I.outras.v !== null && I.outras.v !== 0) out.push(`Outras dívidas (mútuos/partes relacionadas) de ${valorMM(I.outras, unidade)}: classe a tratar à parte.`);
  if (I.liquidezCorrente.v !== null) out.push(`Liquidez corrente de ${fmtX(I.liquidezCorrente).t}${I.liquidezCorrente.v < 1 ? ": curto prazo descoberto." : "."}`);
  if (I.ciclo.v !== null) out.push(`Ciclo de ${fmtDias(I.ciclo).t} dias: cada 10 dias equivalem a ${valorMM({ v: (I.receita.v ?? 0) * 10 / 360, nota: "" }, unidade)} de giro.`);
  return out.slice(0, 4);
}

function leituraNcg(I: Indicadores, ultimo: number, unidade: string): string[] {
  const n = I.ncg;
  const f = I.ncgFinanciadaCP;
  const out: string[] = [];
  out.push(n.v === null ? `NCG de ${ultimo} n/d: ${n.nota.replace(/^NCG: n\/d porque /, "")}.` : `NCG de ${valorMM(n, unidade)} em ${ultimo}.`);
  out.push(f.v === null ? `Financiamento da NCG por dívida de CP não mensurável (${limparMotivo(f.nota)}).`
    : f.v > 100 ? `A dívida bancária de CP é ${fmtPct({ v: f.v }, 0).t} da NCG: financia o giro e mais — tudo o que precisa ser alongado.`
    : `${fmtPct({ v: f.v }, 0).t} dela está financiada por dívida bancária de CP — é o que precisa ser alongado.`);
  if (I.ccl.v !== null) out.push(`CCL de ${valorMM(I.ccl, unidade)}${I.ccl.v < 0 ? ": o circulante não cobre o passivo de curto prazo." : "."}`);
  return out;
}

function mancheteComparativo(I: Indicadores, Iant: Indicadores, ultimo: number, anterior: number): string {
  const r = variacao(Iant.receita.v, I.receita.v);
  const d = variacao(Iant.dfl.v, I.dfl.v);
  if (r.v !== null && d.v !== null) {
    return `${ultimo} × ${anterior}: receita ${r.v >= 0 ? "+" : "−"}${fmtPct({ v: Math.abs(r.v) }, 0).t}, dívida líquida ${d.v >= 0 ? "+" : "−"}${fmtPct({ v: Math.abs(d.v) }, 0).t}`;
  }
  return `${ultimo} × ${anterior}: exercícios fechados lado a lado`;
}

function leituraComparativo(I: Indicadores, Iant: Indicadores, ultimo: number, anterior: number): string[] {
  const out: string[] = [];
  const r = variacao(Iant.receita.v, I.receita.v);
  const e = variacao(Iant.ebitda.v, I.ebitda.v);
  if (r.v !== null && e.v !== null) {
    out.push(e.v < r.v ? `O EBITDA (${pctTexto(e.v)}) piorou mais que a receita (${pctTexto(r.v)}): perda de margem, não só de volume.`
      : `O EBITDA (${pctTexto(e.v)}) acompanhou ou superou a receita (${pctTexto(r.v)}).`);
  } else out.push(`Variação de receita ou EBITDA entre ${anterior} e ${ultimo} não mensurável (n/d ou n.s.).`);
  const d = variacao(Iant.dfl.v, I.dfl.v);
  if (d.v !== null) out.push(`Dívida líquida ${d.v >= 0 ? "subiu" : "caiu"} ${fmtPct({ v: Math.abs(d.v) }).t} no período.`);
  if (I.ciclo.v !== null && Iant.ciclo.v !== null) {
    const dc = I.ciclo.v - Iant.ciclo.v;
    out.push(`Ciclo financeiro ${dc >= 0 ? "alongou" : "encurtou"} ${Math.abs(Math.round(dc))} dias.`);
  }
  return out;
}

function pontosDeAtencao(base: BaseCredito, ind: Map<number, Indicadores>, am: Amarracao[]): string[] {
  const out: string[] = [];
  const diverge = am.filter((a) => a.veredito === "diverge");
  if (diverge.length) out.push(`Amarração que não fecha: ${diverge.map((a) => `${a.nome}${a.ano ? ` (${a.ano})` : ""}`).join("; ")}.`);
  const comOutras = [...ind.entries()].filter(([, x]) => x.outras.v !== null && x.outras.v !== 0).map(([a]) => a);
  if (comOutras.length) out.push(`Dívida com mútuos ou partes relacionadas em ${comOutras.join(", ")}: verificar condições de mercado.`);
  const semDA = [...ind.entries()].filter(([, x]) => x.da.v === null).map(([a]) => a);
  if (semDA.length) out.push(`DRE sem D&A em ${semDA.join(", ")}: EBITDA não mensurável nesses exercícios.`);
  if (out.length === 0) {
    out.push("Nenhum ponto detectado pelas regras automáticas desta versão — isso não atesta a qualidade contábil.");
  }
  void base;
  return out.slice(0, 4);
}

function contarND(ind: Map<number, Indicadores>): number {
  let n = 0;
  for (const x of ind.values()) for (const v of Object.values(x) as Valor[]) if (v.v === null) n++;
  return n;
}

// -----------------------------------------------------------------------------
// Notas e fontes
// -----------------------------------------------------------------------------
const ROTULO_VEREDITO = { ok: "Fecha", diverge: "NÃO FECHA", nao_conferivel: "Não conferível" } as const;

function notasEFontes(deck: DeckOria, base: BaseCredito, am: Amarracao[], naoGerado: string[], ind: Map<number, Indicadores>, anos: number[]) {
  const kDir = kickerDeNatureza(base);
  const POR_SLIDE = 12;
  const paginas = Math.max(1, Math.ceil(am.length / POR_SLIDE));
  for (let pg = 0; pg < paginas; pg++) {
    const s = deck.novo();
    const fatia = am.slice(pg * POR_SLIDE, (pg + 1) * POR_SLIDE);
    const nDiverge = am.filter((a) => a.veredito === "diverge").length;
    const nNao = am.filter((a) => a.veredito === "nao_conferivel").length;
    chrome(s, { kickerEsq: `Notas e fontes${paginas > 1 ? ` (${pg + 1}/${paginas})` : ""}`, kickerDir: kDir,
      manchete: nDiverge > 0 ? `${nDiverge} amarração(ões) não fecham — ler antes de usar os números`
        : `Nenhuma amarração diverge; ${nNao} não puderam ser conferidas`,
      fontes: `Amarrações do Prompt-Mestre Oria v3 · ${LEGENDA_NATUREZA}` });
    const y = tabela(s, GRADE.margem, GRADE.conteudoTopo, [
      { titulo: "Nº", w: 0.5, algn: "ctr" }, { titulo: "Amarração", w: 3.6, algn: "l" }, { titulo: "Ano", w: 0.8, algn: "ctr" },
      { titulo: "Veredito", w: 1.5, algn: "l" }, { titulo: "Detalhe", w: 5.23, algn: "l" },
    ], fatia.map((a) => ({
      tipo: a.veredito === "diverge" ? "destaque" as const : undefined,
      celulas: [String(a.numero), a.nome, a.ano === null ? "—" : String(a.ano),
        { t: ROTULO_VEREDITO[a.veredito], negativo: a.veredito === "diverge", b: a.veredito !== "ok" }, encurtar(a.detalhe, 62)],
    })));
    void y;
  }
  // O que esta versão NÃO gera — e as notas de n/d, que são o "motivo e efeito" de cada branco.
  const s = deck.novo();
  chrome(s, { kickerEsq: "Notas e fontes · escopo desta versão", kickerDir: kDir,
    manchete: "O que esta versão não gera, e o motivo de cada n/d",
    fontes: "n/d não é zero: é linha que o documento não traz. Definições: NCG = clientes + estoques − fornecedores; prazos em 360 dias." });
  const w = (GRADE.util - GRADE.gapPainel) / 2;
  card(s, GRADE.margem, GRADE.conteudoTopo, w, GRADE.conteudoBase - GRADE.conteudoTopo, { rotulo: "Capítulos não gerados", destaque: true,
    corpo: naoGerado.slice(0, 7).map((t) => p(encurtar(t, 150), { bullet: true, spcAft: 4 })) });
  const motivos = [...new Set(anos.flatMap((a) => (Object.entries(ind.get(a)!) as Array<[string, Valor]>)
    .filter(([, v]) => v.v === null).map(([, v]) => limparMotivo(v.nota))))].slice(0, 7);
  card(s, GRADE.margem + w + GRADE.gapPainel, GRADE.conteudoTopo, w, GRADE.conteudoBase - GRADE.conteudoTopo, { rotulo: "Por que há n/d",
    corpo: (motivos.length ? motivos : ["Nenhum indicador saiu n/d nos exercícios apresentados."]).map((t) => p(encurtar(t, 150), { bullet: true, spcAft: 4 })) });
}

function limparMotivo(nota: string): string {
  // "Margem EBITDA: n/d porque EBITDA: n/d porque X" → a causa primeira, que é a que se conserta.
  const partes = nota.split(/n\/d porque |n\/d — /);
  return partes[partes.length - 1].replace(/^[A-Za-zÀ-ú/ ()-]+: /, (m) => m).trim();
}

// -----------------------------------------------------------------------------
// Utilidades
// -----------------------------------------------------------------------------
const ROTULO_TIPO: Record<string, string> = {
  BALANCO: "Balanço patrimonial", DRE: "DRE", BALANCETE: "Balancete", DF_AUDITADA: "Demonstrações auditadas",
  COMBINADO: "Demonstrações combinadas", FLUXO_CAIXA: "Fluxo de caixa", DMPL: "DMPL", NOTAS_EXPL: "Notas explicativas",
  MAPA_DIVIDA: "Mapa da dívida", FATURAMENTO_24M: "Faturamento 24 meses",
};
const rotuloTipo = (t: string) => ROTULO_TIPO[t] ?? t.toLowerCase().replace(/_/g, " ");
const capitalizar = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
export const encurtar = (s: string, n: number) => (s.length <= n ? s : `${s.slice(0, n - 1).trimEnd()}…`);

/** A linha de fontes dos slides financeiros: ≤ ~140 caracteres (o prompt). */
export function fontesFinanceiras(base: BaseCredito, anos: number[]): string {
  const tipos = new Set(base.documentos.filter((d) => d.anos.some((a) => anos.includes(a))).map((d) => d.tipo ?? ""));
  const nomes = [tipos.has("DF_AUDITADA") && "DFs auditadas", tipos.has("BALANCO") && "balanços", tipos.has("DRE") && "DREs",
    tipos.has("COMBINADO") && "demonstrações", tipos.has("BALANCETE") && "balancetes"].filter(Boolean).join(", ");
  const faixa = anos.length > 1 ? `${anos[0]}–${anos[anos.length - 1]}` : String(anos[0]);
  const ns = new Set(base.periodos.filter((x) => anos.includes(x.ano)).map((x) => x.natureza));
  const legenda = [...ns].map((n) => n === "A" ? "(A) auditada" : n === "B" ? "(B) não auditada" : n === "R" ? "(R) revisão limitada" : "(G) gerencial").join(" · ");
  return encurtar(`Fonte: ${nomes || "demonstrações"} ${faixa} da ${encurtar(base.entidade, 40).replace(/\.$/, "")}. Cálculos Oria. ${legenda}.`, 125);
}

export type { Paragrafo, SlideOria };
