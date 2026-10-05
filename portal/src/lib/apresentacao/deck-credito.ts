// A APRESENTAÇÃO INICIAL DE CRÉDITO — todos os capítulos do deck de referência (Centro Oeste,
// out/2026) no padrão institucional do Teaser (Prompt Padrão Oria).
//
// DUAS FONTES, cada uma com o seu papel (decisão do dono, 02/10/2026):
//   • o deck do Centro Oeste é a referência de CONSTRUÇÃO: a ordem dos capítulos, quais slides
//     existem, que tabela/gráfico cada um tem e o que ele conclui;
//   • o Prompt Padrão é a referência de FORMATAÇÃO: componentes da seção 4.7, Verdana, grade em
//     pt, rodapé, títulos que afirmam. Onde os dois discordam, vale o Prompt Padrão — com dois
//     acréscimos que o dono pediu: as divisórias de capítulo e o sumário ficam, e o endividamento
//     usa rosca.
//
// O QUE É DO SISTEMA E O QUE É "[a preencher]". Os capítulos IX a XIII saem inteiros do realizado
// extraído (o mesmo do modelo institucional). Os de pesquisa (I a VIII) e os de julgamento (XIV a
// XVIII) saem com a ESTRUTURA do slide e o que o sistema já sabe (o ciclo financeiro na dinâmica
// do segmento, o EBITDA reportado na normalização, os saldos do balanço nas garantias), e o resto
// marcado "[a preencher]" — nunca texto inventado (regra 1 do projeto, item 3 do Prompt Padrão).
// Número de tabela que falta é `n/d`, com o motivo nas notas; campo de texto é "[a preencher]".
//
// MANCHETES SÃO REGRAS SOBRE O NÚMERO, não redação: cada título é escolhido por um teste
// explícito, com os limiares do próprio Prompt-Mestre (múltiplo-alvo de 2,5x a 3,5x).
import {
  A_PREENCHER, COR, DeckOria, GRADE, blocoDeTexto, campoValor, cabecalho, capa, cartao, contracapa, divisoria,
  faixa, kpi, notas, p, rodape, tabela, tituloSecao,
  type ColunaTabela, type LinhaTabela, type Paragrafo, type SlideOria, type Celula,
} from "./pptx-oria";
import {
  LEGENDA_NATUREZA, MULTIPLO_ALVO, TAG_NATUREZA, amarracoes, faixaDeAlavancagem, fatorParaMM, fmtDias, fmtMM, fmtPct, fmtX,
  indicadores, variacao, dividaDoMapa, ativosReais, type Amarracao, type BaseCredito, type Indicadores, type Numero, type PeriodoCredito, type Valor,
} from "./base-credito";

type Escala = "milhar" | "reais";
const MESES = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro",
  "outubro", "novembro", "dezembro"];
/** Até 4 colunas de período por slide (Cap. X do Prompt-Mestre). */
const MAX_PERIODOS = 4;
const AP = A_PREENCHER;
const FONTE_AP = `Fonte: ${AP}.`;

const pctTexto = (v: number, casas = 1) => `${v < 0 ? "−" : "+"}${fmtPct({ v: Math.abs(v) }, casas).t}`;
const mm1 = (v: number) => v.toLocaleString("pt-BR", { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const cel = (n: Numero): Celula => ({ t: n.t });

/** Recusa conhecida: a rota a devolve como 409 com a mensagem, não como falha inesperada. */
export class SemDadoParaApresentar extends Error {
  constructor(entidade: string) {
    super(`A entidade "${entidade}" não tem receita, ativo nem patrimônio líquido em nenhum exercício fechado `
      + "— o deck sairia sem número nenhum. Confira a entidade escolhida na Modelagem (um \"GRUPO\" consolidado "
      + "só existe se o documento combinado trouxer as demonstrações dele) e a extração dos balanços e DREs.");
  }
}

export interface SaidaDeck {
  deck: DeckOria;
  /** o que ficou "[a preencher]" e por quê — também vai para o slide de notas */
  aPreencher: string[];
  amarracoes: Amarracao[];
  /** quantos campos preenchidos (0201) entraram — para a rota/verificador saberem que o canal funciona */
  camposUsados?: number;
}

export function construirDeckCredito(base: BaseCredito, agora: Date): SaidaDeck {
  const deck = new DeckOria(`${base.cliente} — Apresentação inicial`);
  const periodos = base.periodos.slice(-MAX_PERIODOS);
  if (periodos.length === 0) {
    throw new Error("apresentação de crédito: nenhum exercício fechado com valor — não há o que apresentar. "
      + "Confira o último exercício real na tela de Modelagem e a extração dos balanços.");
  }
  // DECK SEM NÚMERO NENHUM NÃO SAI. Medido nos mandatos locais (02/10/2026): escolher a entidade
  // "GRUPO CANASTRA" — o consolidado que só existe como coluna de demonstração combinada — gerava 56
  // slides com 134 n/d e nenhum número: um arquivo que abre e parece um resultado. Sem receita, ativo
  // nem PL em exercício algum, a recusa diz o que fazer.
  const temAlgum = periodos.some(({ ano }) => (["receita_liquida", "ativo_total", "patrimonio_liquido"] as const)
    .some((k) => base.historico.grandezas[k][ano]?.v != null));
  if (!temAlgum) throw new SemDadoParaApresentar(base.entidade);
  const esc: Escala = base.historico.escala;
  // SEM DRE EM EXERCÍCIO ALGUM (holding, SPE, empresa que só mandou balanço): os capítulos que só
  // existem com resultado — dinâmica do ciclo, margem, X.1, prazos, normalização, capacidade de
  // pagamento — saem do deck, e a nota diz por quê. Medido nos mandatos locais: 9 de 14 entidades
  // eram assim, com 40 a 77 n/d por deck, a maioria nesses seis slides.
  // Receita, EBIT OU lucro líquido: holding com DRE de equivalência patrimonial não tem receita e TEM
  // DRE — tratá-la como "sem DRE" omitiria o resultado dela (achado da revisão de 03/10/2026).
  const temDRE = periodos.some(({ ano }) => (["receita_liquida", "ebit", "lucro_liquido"] as const)
    .some((k) => base.historico.grandezas[k][ano]?.v != null));
  const anos = periodos.map((x) => x.ano);
  const ind = new Map(anos.map((a) => [a, indicadores(base, a)]));
  const mapa = dividaDoMapa(base, anos);
  const ultimo = anos[anos.length - 1];
  const anterior = anos.length >= 2 ? anos[anos.length - 2] : null;
  const I = ind.get(ultimo)!;
  const Iant = anterior !== null ? ind.get(anterior)! : null;
  const fontes = fontesFinanceiras(base, periodos);
  const am = amarracoes(base, periodos);
  const mm = (x: Valor) => fmtMM(x, esc);
  const vmi = (x: Valor) => valorMi(x, esc);
  const mes = `${MESES[agora.getMonth()]} de ${agora.getFullYear()}`;
  const aPreencher = [
    "Caps. I a VIII (setor, mercado, societário, empresa, cadeia de valor, concorrência): dependem da pesquisa das FASES 1 a 3.",
    "XIII por credor e muro de vencimentos: o mapa da dívida ainda não chega estruturado por operação.",
    "XIV a XVIII (ajustes do EBITDA, alavancas, realização das garantias, notas do scorecard): julgamento do analista.",
    "YTD/LTM: só exercícios fechados entram; o balancete do ano corrente fica fora desta versão.",
  ];
  if (!temDRE) {
    aPreencher.unshift("A entidade não tem DRE em nenhum exercício recebido: os slides II.3, V.2, X.1, X.3, XIV e XV foram omitidos.");
  }

  // OS CAMPOS PREENCHIDOS (0201). A chave do slide sai do rótulo ("II.2 · Tendências" → "ii2"), e
  // cada lacuna do slide é `<slide>.<sufixo>`. É o que permite preencher a apresentação por
  // capítulo sem o gerador conhecer o texto — e sem nunca trocar "[a preencher]" por suposição.
  const campos = base.campos ?? {};
  let prefixo = "";
  const chaveDoRotulo = (r: string) => r.split("·")[0].trim().toLowerCase().replace(/[^a-z0-9]/g, "");
  // A chave depende do número do slide no rótulo: RENUMERAR um slide ("XV.2" → "XV.3") órfã os
  // valores já gravados. Renumerar exige migrar as chaves em caso_apresentacao_campo.
  const usados: string[] = [];
  const ap = (sufixo: string) => {
    const c = campos[`${prefixo}.${sufixo}`];
    if (c && !usados.includes(`${prefixo}.${sufixo}`)) usados.push(`${prefixo}.${sufixo}`);
    return c?.valor ?? AP;
  };
  let primeiro = true;
  /** Slide de conteúdo: cabeçalho, rodapé e, só no primeiro, o "CONFIDENCIAL · <MÊS> <ANO>". */
  const slide = (rotulo: string, titulo: string, fonte: string, subtitulo?: string): SlideOria => {
    prefixo = chaveDoRotulo(rotulo);
    if (titulo === AP) titulo = ap("titulo");
    if (fonte === FONTE_AP) fonte = ap("fonte") === AP ? FONTE_AP : `Fonte: ${ap("fonte")}.`;
    const s = deck.novo();
    cabecalho(s, { rotulo, titulo, subtitulo,
      confidencial: primeiro ? `CONFIDENCIAL · ${MESES[agora.getMonth()].toUpperCase()} ${agora.getFullYear()}` : undefined });
    primeiro = false;
    rodape(s, fonte);
    return s;
  };
  const div = (numero: number, titulo: string, subtitulo: string) =>
    divisoria(deck.novo(COR.fundoCapa), { numero, titulo, subtitulo });
  const colsAnos = (w: number, ps: PeriodoCredito[] = periodos): ColunaTabela[] =>
    ps.map((x) => ({ titulo: `${x.ano} ${TAG_NATUREZA[x.natureza]}`, w }));
  /** Linha de tabela com um valor por período mostrado. */
  const L = (rot: string, f: (x: Indicadores) => Numero, destaque = false, ps: PeriodoCredito[] = periodos): LinhaTabela =>
    ({ celulas: [rot, ...ps.map((x) => cel(f(ind.get(x.ano)!)))], destaque });
  const serie = (f: (x: Indicadores) => Valor) =>
    anos.map((a) => { const v = f(ind.get(a)!).v; return v === null ? null : Math.round(v * fatorParaMM(esc) * 10) / 10; });

  // ======================================================================== capa
  capa(deck.novo(COR.fundoCapa), {
    rotulo: "Apresentação inicial · Levantamento e diagnóstico",
    titulo: encurtar(`${base.cliente}`, 40),
    descritiva: encurtar(`${base.entidade} · exercícios ${anos[0]}${anos.length > 1 ? ` a ${ultimo}` : ""} · ${naturezaCurta(periodos)}`, 70),
    apoio: `Material confidencial para diagnóstico financeiro e de crédito · ${capitalizar(mes)}`,
    assinatura: "Oria Partners Capital Serviços",
  });

  // ===================================================================== sumário
  const CAPITULOS: Array<[string, string]> = [
    ["Panorama do setor macro", "Volumes, juros e crédito do setor"],
    ["Mercado específico", "Tamanho, tendências e dinâmica do modelo de negócio"],
    ["Estrutura societária", "Quadro de sócios, ecossistema do grupo e stakeholders"],
    ["A empresa", "Ficha institucional, portfólio, fornecedores e localização"],
    ["Cadeia de valor", "Onde a companhia captura e perde margem"],
    ["Cenário competitivo", "Concorrentes e posicionamento"],
    ["Base de informação e evolução financeira", "Qualidade dos dados, resultado, estrutura de capital e prazos"],
    ["Capital de giro e endividamento", "NCG, comparativo entre exercícios, dívida e vencimentos"],
    ["EBITDA normalizado e dívida sustentável", "Qualidade do resultado e capacidade de pagamento"],
    ["Garantias, scorecard e síntese de crédito", "Recuperação por classe, nota de risco e implicações"],
    ["Análise SWOT", "Achados operacionais e financeiros integrados"],
    ["Fatores críticos e próximos passos", "Condições de sucesso e agenda do mandato"],
  ];
  {
    const s = slide("Sumário", "Doze capítulos, do setor à síntese de crédito", fontes);
    CAPITULOS.forEach(([t, d], i) => {
      const x = GRADE.col2.x[i % 2];
      const y = GRADE.topo + Math.floor(i / 2) * 60;
      s.texto(x, y, 34, 26, [p(String(i + 1).padStart(2, "0"), { sz: 21, cor: COR.laranja })], "t");
      s.texto(x + 42, y + 2, GRADE.col2.w - 42, 16, [p(t, { sz: 12, b: true, cor: COR.texto })], "t");
      s.texto(x + 42, y + 21, GRADE.col2.w - 42, 16, [p(d)], "t");
      s.fio(x, y + 48, GRADE.col2.w, 0, COR.linha, 0.5);
    });
  }

  // ========================================================== sumário executivo
  {
    const s = slide("Sumário executivo", mancheteExecutiva(I), fontes);
    const varRec = Iant ? variacao(Iant.receita.v, I.receita.v) : { v: null, ns: false };
    const kpis = [
      { valor: vmi(I.receita), rotulo: `Receita líquida ${ultimo}`,
        explicacao: anterior === null ? "exercício único no histórico" : varRec.ns ? `n.s. contra ${anterior}`
          : varRec.v === null ? `variação contra ${anterior}: n/d` : `${pctTexto(varRec.v)} contra ${anterior}` },
      { valor: vmi(I.ebitda), rotulo: `EBITDA ${ultimo}`,
        explicacao: I.margemEbitda.v === null ? "margem n/d (ver notas)" : `margem de ${fmtPct(I.margemEbitda).t}, reportado` },
      { valor: fmtX(I.dflEbitda).t, rotulo: "DFL / EBITDA",
        explicacao: `múltiplo-alvo de ${mm1(MULTIPLO_ALVO.min)}x a ${mm1(MULTIPLO_ALVO.max)}x` },
      { valor: fmtX(I.liquidezCorrente).t, rotulo: "Liquidez corrente", explicacao: `AC sobre PC, ${ultimo}` },
    ];
    kpis.forEach((k, i) => kpi(s, GRADE.col4.x[i], GRADE.topo, GRADE.col4.w, k));
    const d = diagnostico(I, Iant, anterior, esc);
    d.slice(0, 3).forEach(([t, c], i) => cartao(s, GRADE.col3.x[i], 228, GRADE.col3.w, 150, { numeral: i + 1, titulo: t, corpo: c }));
    // Amarração que não fecha muda o peso de TODOS os números deste slide: o aviso vem na faixa, que
    // é o que o leitor leva, e não só no slide de notas (medido na captura real v35: EBIT do
    // documento 8.309 mil acima da cascata, e o sumário dizia "DFL/EBITDA de 12,3x" sem ressalva).
    const nDiv = am.filter((a) => a.veredito === "diverge").length;
    faixa(s, 400, nDiv > 0 ? `${nDiv} amarração(ões) não fecham (ver notas): ler os números com ressalva. ${implicacaoPrincipal(I)}`
      : implicacaoPrincipal(I));
  }

  // ============================================================ I — setor macro
  div(1, CAPITULOS[0][0], CAPITULOS[0][1]);
  {
    const s = slide("I.1 · Panorama do setor macro", AP, FONTE_AP);
    ["Tamanho do setor", "Crescimento recente", "Juro de referência", "Crédito ao setor"].forEach((r, i) =>
      kpi(s, GRADE.col4.x[i], GRADE.topo, GRADE.col4.w, { valor: ap(`kpi${i + 1}`), rotulo: r, explicacao: `fonte: ${ap(`kpi${i + 1}.fonte`)}` }));
    blocoDeTexto(s, GRADE.x, 228, GRADE.w, "Contexto estrutural",
      [["Demanda e ciclo", ap("contexto1")], ["Juros e crédito", ap("contexto2")], ["Regulação e câmbio", ap("contexto3")]], 62);
  }

  // ======================================================== II — mercado específico
  div(2, CAPITULOS[1][0], CAPITULOS[1][1]);
  {
    const s = slide("II.1 · Tamanho e crescimento", AP, FONTE_AP);
    tituloSecao(s, GRADE.col2.x[0], GRADE.topo, GRADE.col2.w, "Mercado do nicho (unidade a definir)");
    cartao(s, GRADE.col2.x[0], GRADE.topo + 24, GRADE.col2.w, 230, { titulo: "Série histórica do mercado", corpo: `Gráfico de colunas: ${AP} (série e fonte da pesquisa).` });
    blocoDeTexto(s, GRADE.col2.x[1], GRADE.topo, GRADE.col2.w, "Destaques", [[AP, AP], [AP, AP], [AP, AP], [AP, AP]], 62);
  }
  {
    const s = slide("II.2 · Tendências estruturais", AP, FONTE_AP);
    ["Regulação", "Tecnologia", "Consolidação", "Mercado global", "Importação e câmbio", "Crédito"].forEach((t, i) =>
      cartao(s, GRADE.col3.x[i % 3], GRADE.topo + Math.floor(i / 3) * 175, GRADE.col3.w, 150, { numeral: i + 1, titulo: t, corpo: ap(`cartao${i + 1}`) }));
  }
  if (temDRE) {
    // A ponte analítica para o mandato: a coluna da companhia SAI DO SISTEMA (prazos e margem).
    const s = slide("II.3 · Dinâmica do modelo de negócio", mancheteCiclo(I, ultimo), fontes);
    tabela(s, GRADE.x, GRADE.topo, [
      { titulo: "Etapa", w: 170 }, { titulo: `Na companhia, ${ultimo}`, w: 200, algn: "r" },
      { titulo: "Referência do segmento", w: 200, algn: "r" }, { titulo: "Leitura", w: 267, algn: "l" },
    ], [
      { celulas: ["Compra (PMP)", `${fmtDias(I.pmp).t} dias`, AP, AP] },
      { celulas: ["Estoque (PME)", `${fmtDias(I.pme).t} dias`, AP, AP] },
      { celulas: ["Venda (PMR)", `${fmtDias(I.pmr).t} dias`, AP, AP] },
      { celulas: ["Margem bruta", fmtPct(margemBruta(I)).t, AP, AP] },
      { celulas: ["Ciclo financeiro", `${fmtDias(I.ciclo).t} dias`, AP, AP], destaque: true },
    ]);
    faixa(s, 400, I.ciclo.v === null ? "O ciclo financeiro da companhia não é mensurável com os documentos recebidos."
      : `Cada 10 dias de ciclo equivalem a ${valorMi({ v: (I.receita.v ?? 0) * 10 / 360, nota: "" }, esc)} de capital de giro (calculado pela Oria).`);
  }

  // ======================================================== III — societário
  div(3, CAPITULOS[2][0], CAPITULOS[2][1]);
  {
    const s = slide("III.1 · Quadro societário", AP, FONTE_AP);
    tabela(s, GRADE.x, GRADE.topo, [
      { titulo: "Sócio", w: 220 }, { titulo: "Qualificação", w: 170, algn: "l" }, { titulo: "Entrada", w: 110, algn: "l" },
      { titulo: "Participação", w: 110, algn: "r" }, { titulo: "Outras empresas", w: 227, algn: "l" },
    ], [1, 2, 3].map(() => ({ celulas: [AP, AP, AP, AP, AP] })));
    campoValor(s, GRADE.x, 250, GRADE.w, [["Razão social", base.entidade], ["CNPJ", AP], ["Fundação", AP],
      ["Sede", AP], ["CNAE principal", AP], ["Capital social", AP]], { colValor: 150 });
  }
  {
    const s = slide("III.2 · Perfil dos sócios", AP, FONTE_AP);
    [1, 2, 3].forEach((n, i) => cartao(s, GRADE.col3.x[i], GRADE.topo, GRADE.col3.w, 250, { titulo: `Sócio ${n}: ${ap(`socio${n}.nome`)}`, corpo: `Histórico, outras empresas e presença pública: ${ap(`socio${n}`)}` }));
  }
  {
    // III.3 — O PERÍMETRO: as empresas cadastradas no caso, quantos documentos cada uma tem e qual
    // delas o deck analisa. Sem a lista (a rota não leu), o slide continua a preencher.
    const per = base.perimetro ?? [];
    const s = slide("III.3 · Ecossistema e perímetro", per.length
      ? `Perímetro de ${per.length} ${per.length === 1 ? "empresa" : "empresas"}; esta análise cobre a destacada` : AP,
      per.length ? "Fonte: cadastro de entidades do caso e documentos recebidos." : FONTE_AP);
    if (per.length) {
      tabela(s, GRADE.x, GRADE.topo, [{ titulo: "Empresa", w: 330 }, { titulo: "CNPJ", w: 150, algn: "l" },
        { titulo: "Papel no grupo", w: 140, algn: "l" }, { titulo: "Docs.", w: 70 }, { titulo: "Nesta análise", w: 147, algn: "l" }],
      per.slice(0, 7).map((e): LinhaTabela => ({ destaque: e.analisada, celulas: [encurtar(e.razaoSocial, 40), e.cnpj ?? AP,
        e.papel ?? AP, String(e.documentos), e.analisada ? "analisada" : ap(`considerar.${chaveDe(e.razaoSocial)}`)] })));
      faixa(s, 400, per.length > 1 ? `Grupo com ${per.length} empresas: avais cruzados e mútuos exigem a análise das avalizadas (${ap("avais")}).`
        : "Empresa única no caso: o perímetro é a própria entidade analisada.");
    } else {
      faixa(s, GRADE.topo, `${base.entidade} · entidade central do perímetro analisado`, { h: 50 });
      ["Empresa relacionada", "Empresa relacionada", "Contraparte relacionada"].forEach((t, i2) =>
        cartao(s, GRADE.col3.x[i2], 185, GRADE.col3.w, 150, { numeral: i2 + 1, titulo: t, corpo: `Nome, CNPJ, vínculo e situação: ${AP}` }));
    }
  }
  {
    const s = slide("III.4 · Avaliação de stakeholders", AP, FONTE_AP);
    ["Concentração de controle", "Força das garantias pessoais", "Alertas e pontos de atenção"].forEach((t, i) =>
      cartao(s, GRADE.col3.x[i], GRADE.topo, GRADE.col3.w, 250, { numeral: i + 1, titulo: t, corpo: ap(`cartao${i + 1}`) }));
  }

  // ======================================================== IV — a empresa
  div(4, CAPITULOS[3][0], CAPITULOS[3][1]);
  {
    const s = slide("IV.1 · Ficha institucional", AP, FONTE_AP);
    campoValor(s, GRADE.x, GRADE.topo, GRADE.w, [["Atividade", AP], ["CNAE principal", AP], ["Fundação", AP], ["Sede e filiais", AP],
      ["Unidades", AP], ["Colaboradores", AP], ["Receita líquida", `${vmi(I.receita)} em ${ultimo}`], ["Marcas", AP], ["Site", AP]], { colValor: 160 });
  }
  {
    const s = slide("IV.2 · Portfólio por linha", AP, `${fontes}`);
    tabela(s, GRADE.x, GRADE.topo, [{ titulo: "Linha (R$ mi)", w: 337 }, ...colsAnos(500 / periodos.length)],
      [{ celulas: [`Linha 1: ${AP}`, ...periodos.map(() => AP)] }, { celulas: [`Linha 2: ${AP}`, ...periodos.map(() => AP)] },
        { celulas: [`Linha 3: ${AP}`, ...periodos.map(() => AP)] }, L("Receita líquida total", (x) => mm(x.receita), true)]);
  }
  {
    const s = slide("IV.3 · Fornecedores e exposição cambial", AP, FONTE_AP);
    tabela(s, GRADE.x, GRADE.topo, [{ titulo: "Fornecedor", w: 230 }, { titulo: "Produtos", w: 250, algn: "l" },
      { titulo: "Peso", w: 110 }, { titulo: "Exposição cambial", w: 247, algn: "l" }], [1, 2, 3].map(() => ({ celulas: [AP, AP, AP, AP] })));
    cartao(s, GRADE.x, 260, GRADE.w, 110, { titulo: "Fornecedores no balanço",
      corpo: `Saldo de fornecedores em ${ultimo}: ${vmi(I.fornecedores)}; prazo médio de pagamento de ${fmtDias(I.pmp).t} dias (sistema).` });
  }
  {
    const s = slide("IV.4 · Localização", AP, FONTE_AP);
    cartao(s, GRADE.col2.x[0], GRADE.topo, GRADE.col2.w, 250, { titulo: "Vantagens", corpo: ap("vantagens") });
    cartao(s, GRADE.col2.x[1], GRADE.topo, GRADE.col2.w, 250, { titulo: "Desvantagens", corpo: ap("desvantagens") });
  }

  // ======================================================== V — cadeia de valor
  div(5, CAPITULOS[4][0], CAPITULOS[4][1]);
  {
    const s = slide("V.1 · Cadeia de valor", AP, FONTE_AP);
    tabela(s, GRADE.x, GRADE.topo, [{ titulo: "Elo", w: 200 }, { titulo: "Quem", w: 320, algn: "l" }, { titulo: "Onde a margem fica", w: 317, algn: "l" }],
      ["Fornecedores", "Companhia", "Canais", "Cliente final"].map((e) => ({ celulas: [e, AP, AP] })));
  }
  if (temDRE) {
    const s = slide("V.2 · Onde a companhia captura margem", mancheteMargem(ind, anos), fontes);
    tituloSecao(s, GRADE.col2.x[0], GRADE.topo, GRADE.col2.w, "Lucro bruto e EBITDA (R$ mi)");
    s.grafico(GRADE.col2.x[0], GRADE.topo + 22, GRADE.col2.w, 250, { tipo: "colunas", categorias: anos.map(String), series: [
      { nome: "Lucro bruto", valores: serie((x) => x.lucroBruto), cor: COR.verde },
      { nome: "EBITDA", valores: serie((x) => x.ebitda), cor: COR.laranja }] });
    cartao(s, GRADE.col2.x[1], GRADE.topo, GRADE.col2.w, 140, { titulo: "Margem bruta total",
      corpo: anos.map((a) => `${a}: ${fmtPct(margemBruta(ind.get(a)!)).t}`).join(" · ") });
    cartao(s, GRADE.col2.x[1], GRADE.topo + 160, GRADE.col2.w, 120, { titulo: "Margem por linha de negócio", corpo: AP });
  }
  {
    const s = slide("V.3 · Comparativo com benchmarks públicos", AP, fontes);
    tabela(s, GRADE.x, GRADE.topo, [{ titulo: "Indicador", w: 237 }, { titulo: "Benchmark 1", w: 200 }, { titulo: "Benchmark 2", w: 200 },
      { titulo: `Companhia ${ultimo}`, w: 200 }], [
      { celulas: ["Receita líquida", AP, AP, vmi(I.receita)] },
      { celulas: ["Margem bruta", AP, AP, fmtPct(margemBruta(I)).t] },
      { celulas: ["Margem EBITDA", AP, AP, fmtPct(I.margemEbitda).t] },
      { celulas: ["Prazo de estoque", AP, AP, `${fmtDias(I.pme).t} dias`] },
      { celulas: ["DFL / EBITDA", AP, AP, fmtX(I.dflEbitda).t] },
    ]);
  }
  {
    const s = slide("V.4 · Diagnóstico integrado", AP, FONTE_AP);
    cartao(s, GRADE.col2.x[0], GRADE.topo, GRADE.col2.w, 260, { titulo: "O que funciona", corpo: ap("funciona") });
    cartao(s, GRADE.col2.x[1], GRADE.topo, GRADE.col2.w, 260, { titulo: "O que não funciona", corpo: ap("naofunciona") });
  }

  // ======================================================== VI — competitivo
  div(6, CAPITULOS[5][0], CAPITULOS[5][1]);
  {
    const s = slide("VI.1 · Concorrentes", AP, FONTE_AP);
    [0, 1, 2, 3].forEach((i) => cartao(s, GRADE.col2.x[i % 2], GRADE.topo + Math.floor(i / 2) * 180, GRADE.col2.w, 160,
      { numeral: i + 1, titulo: `Concorrente: ${ap(`concorrente${i + 1}.nome`)}`, corpo: `Localização e alcance, ponto forte e ponto fraco: ${ap(`concorrente${i + 1}`)}` }));
  }
  {
    const s = slide("VI.2 · Posicionamento competitivo", AP, FONTE_AP);
    tabela(s, GRADE.x, GRADE.topo, [{ titulo: "Dimensão", w: 237 }, { titulo: "Companhia", w: 150, algn: "l" },
      { titulo: "Concorrente 1", w: 150, algn: "l" }, { titulo: "Concorrente 2", w: 150, algn: "l" }, { titulo: "Concorrente 3", w: 150, algn: "l" }],
    ["Marca", "Lojas na região", "Alcance geográfico", "Escala", "Ponto forte"].map((d) => ({ celulas: [d, AP, AP, AP, AP] })));
  }

  // ======================================== VII (cap. 07) — base de informação e evolução
  div(7, CAPITULOS[6][0], CAPITULOS[6][1]);
  {
    const temAuditada = periodos.some((x) => x.natureza === "A");
    const s = slide("IX · Base de informação", temAuditada ? "Há demonstração auditada na base; ela calibra as conclusões"
      : "Nenhuma demonstração auditada: as conclusões indicam direção", `Fonte: documentos recebidos da companhia. ${LEGENDA_NATUREZA}.`);
    const docs = base.documentos.slice(0, 6);
    const linhas = docs.map((d): [string, string] => [d.periodo,
      `${d.tipo ? rotuloTipo(d.tipo) : "não classificado"} · ${d.tipo === "DF_AUDITADA" ? "(A) auditada" : d.tipo === "BALANCETE" ? "(B) balancete" : "(B) sem parecer"} · ${encurtar(d.arquivo ?? "sem arquivo", 34)}`]);
    if (base.documentos.length > docs.length) linhas.push([`+ ${base.documentos.length - docs.length}`, "documento(s) na aba Documentos do export"]);
    tituloSecao(s, GRADE.col2.x[0], GRADE.topo, 520, "Documentos financeiros recebidos");
    campoValor(s, GRADE.col2.x[0], GRADE.topo + 22, 520, linhas.length ? linhas : [["n/d", "nenhum documento financeiro da entidade"]], { colValor: 110 });
    const xL = 605;
    cartao(s, xL, GRADE.topo, GRADE.fim - xL, 180, { titulo: "Limitações da análise",
      corpo: `O parecer do auditor não é lido pelo sistema. Só exercícios fechados entram (${anos.join(", ")}). `
        + (contarND(ind) === 0 ? "Nenhum indicador saiu n/d." : `${contarND(ind)} indicador(es) saíram n/d, com o motivo nas notas.`) });
    cartao(s, xL, GRADE.topo + 195, GRADE.fim - xL, 180, { titulo: "Pontos de atenção contábil", corpo: pontosDeAtencao(base, ind, am).join(" ") });
  }
  {
    // IX.2 — O QUE CHEGOU E O QUE FALTOU dos documentos obrigatórios, pela regra do kit básico.
    const info = base.informacao;
    const recebidos = (info ?? []).filter((d) => d.status === "recebido").length;
    const faltam = (info ?? []).filter((d) => d.status !== "recebido");
    const s = slide("IX.2 · O que chegou e o que faltou", !info ? "Lista de documentos obrigatórios não lida nesta geração"
      : faltam.length === 0 ? `Os ${info.length} documentos obrigatórios chegaram com conteúdo`
      : `${recebidos} de ${info.length} documentos obrigatórios chegaram; ${faltam.length} pendentes`,
    "Fonte: kit básico do mandato e documentos recebidos no portal.");
    if (info) {
      const rot = { recebido: "recebido", sem_conteudo: "chegou sem conteúdo extraído", faltante: "não recebido" } as const;
      const ordenada = [...faltam, ...info.filter((d) => d.status === "recebido")];
      const meio = Math.ceil(Math.min(ordenada.length, 28) / 2);
      campoValor(s, GRADE.col2.x[0], GRADE.topo, GRADE.col2.w, ordenada.slice(0, Math.min(meio, 14)).map((d) => [encurtar(d.documento, 34), rot[d.status]]), { colValor: 215 });
      campoValor(s, GRADE.col2.x[1], GRADE.topo, GRADE.col2.w, ordenada.slice(meio, Math.min(meio * 2, 28)).map((d) => [encurtar(d.documento, 34), rot[d.status]]), { colValor: 215 });
    } else {
      cartao(s, GRADE.x, GRADE.topo, GRADE.w, 90, { titulo: "Kit básico", corpo: "A lista de documentos obrigatórios não foi lida nesta geração: confira a tela do caso." });
    }
  }
  if (temDRE) {
    const s = slide("X.1 · Resultado", mancheteResultado(I, Iant, ultimo, anterior), fontes);
    tituloSecao(s, GRADE.col2.x[0], GRADE.topo, GRADE.col2.w, "Receita líquida e EBITDA (R$ mi)");
    s.grafico(GRADE.col2.x[0], GRADE.topo + 22, GRADE.col2.w, 270, { tipo: "colunas", categorias: anos.map(String), series: [
      { nome: "Receita líquida", valores: serie((x) => x.receita), cor: COR.verde },
      { nome: "EBITDA", valores: serie((x) => x.ebitda), cor: COR.laranja }] });
    const wc = GRADE.col2.w;
    const wa = Math.min(90, (wc - 150) / periodos.length);
    tabela(s, GRADE.col2.x[1], GRADE.topo, [{ titulo: "R$ mi", w: wc - wa * periodos.length }, ...colsAnos(wa)], [
      L("Lucro bruto", (x) => mm(x.lucroBruto)),
      L("EBITDA", (x) => mm(x.ebitda)),
      L("Margem EBITDA", (x) => fmtPct(x.margemEbitda)),
      L("EBIT", (x) => mm(x.ebit)),
      L("Margem EBIT", (x) => fmtPct(x.margemEbit)),
      L("Lucro líquido", (x) => mm(x.lucroLiquido), true),
      L("Margem líquida", (x) => fmtPct(x.margemLiquida)),
    ]);
    faixa(s, 410, leituraResultado(ind, anos, esc), { x: GRADE.col2.x[1], w: GRADE.col2.w, h: 70 });
  }
  {
    const s = slide("X.2 · Estrutura de capital", mancheteAlavancagem(I, ultimo), fontes);
    const wa = Math.min(120, 437 / periodos.length);
    tabela(s, GRADE.x, GRADE.topo, [{ titulo: "R$ mi", w: 520 - wa * periodos.length }, ...colsAnos(wa)], [
      L("Patrimônio líquido", (x) => mm(x.pl)),
      L("Dívida financeira bruta", (x) => mm(x.dividaBruta)),
      L("Bancos", (x) => mm(x.bancos)),
      L("Outras dívidas (mútuos, partes relacionadas)", (x) => mm(x.outras)),
      L("Caixa e aplicações", (x) => mm(x.caixa)),
      L("Dívida financeira líquida", (x) => mm(x.dfl), true),
      L("DFL / EBITDA", (x) => fmtX(x.dflEbitda)),
      L("Ativo total", (x) => mm(x.ativo)),
    ]);
    const xL = 605;
    cartao(s, xL, GRADE.topo, GRADE.fim - xL, 190, { titulo: "Leitura", corpo: leituraEstrutura(I, ultimo, esc).join(" ") });
    kpi(s, xL, GRADE.topo + 215, GRADE.fim - xL, { valor: fmtX(I.alavancagem).t, rotulo: "Ativo / PL", explicacao: `alavancagem patrimonial em ${ultimo}` });
  }
  if (temDRE) {
    const s = slide("X.3 · Prazos e ciclo financeiro", mancheteCiclo(I, ultimo), `${fontes.replace(/\.$/, "")} · base de 360 dias.`);
    tituloSecao(s, GRADE.col2.x[0], GRADE.topo, GRADE.col2.w, "Prazos médios (dias)");
    s.grafico(GRADE.col2.x[0], GRADE.topo + 22, GRADE.col2.w, 270, { tipo: "colunas", formato: "0", categorias: ["PMR", "PME", "PMP"],
      series: [anterior, ultimo].filter((a): a is number => a !== null).map((a, k) => ({
        nome: String(a), cor: k === 0 && anterior !== null ? COR.verde : COR.laranja,
        valores: [ind.get(a)!.pmr, ind.get(a)!.pme, ind.get(a)!.pmp].map((v) => (v.v === null ? null : Math.round(v.v))) })) });
    const wa = Math.min(90, (GRADE.col2.w - 150) / periodos.length);
    tabela(s, GRADE.col2.x[1], GRADE.topo, [{ titulo: "Dias", w: GRADE.col2.w - wa * periodos.length }, ...colsAnos(wa)], [
      L("Prazo de recebimento (PMR)", (x) => fmtDias(x.pmr)),
      L("Prazo de estoque (PME)", (x) => fmtDias(x.pme)),
      L("Prazo de pagamento (PMP)", (x) => fmtDias(x.pmp)),
      L("Ciclo financeiro", (x) => fmtDias(x.ciclo), true),
    ]);
  }

  // ======================================== cap. 08 — giro e endividamento
  div(8, CAPITULOS[7][0], CAPITULOS[7][1]);
  {
    const fin = I.ncgFinanciadaCP;
    const s = slide("XI · Capital de giro", I.ncg.v !== null && I.ncg.v <= 0 ? `NCG de ${ultimo} não positiva: o giro se financia com fornecedores`
      : fin.v === null ? `NCG de ${ultimo}: o financiamento por dívida de CP não pôde ser medido`
      : fin.v > 100 ? `Dívida bancária de CP equivale a ${fmtPct({ v: fin.v }, 0).t} da NCG de ${ultimo}`
      : `${fmtPct({ v: fin.v }, 0).t} da NCG de ${ultimo} está financiada por dívida bancária de CP`,
    `${fontes.replace(/\.$/, "")} · NCG = clientes + estoques − fornecedores.`);
    const ps3 = periodos.slice(-3);
    const wa = Math.min(110, 380 / ps3.length);
    tabela(s, GRADE.x, GRADE.topo, [{ titulo: "R$ mi", w: 560 - wa * ps3.length }, ...colsAnos(wa, ps3)], [
      L("Clientes", (x) => mm(x.clientes), false, ps3),
      L("Estoques", (x) => mm(x.estoques), false, ps3),
      L("(−) Fornecedores", (x) => mm(x.fornecedores), false, ps3),
      L("Necessidade de capital de giro", (x) => mm(x.ncg), true, ps3),
      L("Dívida bancária de curto prazo", (x) => mm(x.bancosCP), false, ps3),
      L("Dívida bancária CP / NCG", (x) => fmtPct(x.ncgFinanciadaCP, 0), false, ps3),
      L("Capital circulante líquido", (x) => mm(x.ccl), false, ps3),
    ]);
    const xK = 650;
    kpi(s, xK, GRADE.topo, GRADE.fim - xK, { valor: vmi(I.ncg), rotulo: `NCG ${ultimo}`, explicacao: "clientes + estoques − fornecedores" });
    kpi(s, xK, GRADE.topo + 115, GRADE.fim - xK, { valor: vmi(I.bancosCP), rotulo: "Dívida bancária CP", explicacao: `balanço de ${ultimo}` });
    faixa(s, 400, leituraNcg(I, ultimo, esc));
  }
  if (anterior !== null && Iant) {
    const pa = periodos[periodos.length - 2];
    const pu = periodos[periodos.length - 1];
    const s = slide("XII · Comparativo entre exercícios", mancheteComparativo(I, Iant, ultimo, anterior),
      `${fontes.replace(/\.$/, "")} · 12M × 12M; base negativa ou sinal trocado = n.s.`);
    const V = (rot: string, f: (x: Indicadores) => Valor, fmtv: (x: Valor) => Numero, destaque = false): LinhaTabela => {
      const a = f(Iant); const u = f(I);
      if (fmtv === fmtDias) {
        const d = a.v === null || u.v === null ? null : Math.round(u.v) - Math.round(a.v);
        return { celulas: [rot, fmtv(a).t, fmtv(u).t, d === null ? "n/d" : d < 0 ? `(${Math.abs(d)} d)` : `+${d} d`], destaque };
      }
      const vr = variacao(a.v, u.v);
      return { celulas: [rot, fmtv(a).t, fmtv(u).t, vr.ns ? "n.s." : vr.v === null ? "n/d" : fmtPct({ v: vr.v }).t], destaque };
    };
    const cols: ColunaTabela[] = [{ titulo: "R$ mi", w: 230 }, { titulo: `${pa.ano} ${TAG_NATUREZA[pa.natureza]}`, w: 100 },
      { titulo: `${pu.ano} ${TAG_NATUREZA[pu.natureza]}`, w: 100 }, { titulo: "Var.", w: 90 }];
    tabela(s, GRADE.x, GRADE.topo, cols, [
      V("Receita líquida", (x) => x.receita, mm), V("Lucro bruto", (x) => x.lucroBruto, mm),
      V("EBITDA", (x) => x.ebitda, mm, true), V("EBIT", (x) => x.ebit, mm), V("Lucro líquido", (x) => x.lucroLiquido, mm),
      V("Dívida financeira líquida", (x) => x.dfl, mm), V("Patrimônio líquido", (x) => x.pl, mm), V("Ciclo financeiro (dias)", (x) => x.ciclo, fmtDias),
    ]);
    const xL = 605;
    cartao(s, xL, GRADE.topo, GRADE.fim - xL, 260, { titulo: "Leitura", corpo: leituraComparativo(I, Iant, ultimo, anterior).join(" ") });
  }
  {
    // XIII.1 — POR CREDOR quando há mapa da dívida (o detalhe por contrato); senão, o que o balanço
    // diz (prazo e natureza). Mapa e balanço nunca somados: são a mesma dívida vista de dois lados.
    const temDivida = I.dividaBruta.v !== null && I.dividaBruta.v > 0;
    const w3 = GRADE.col3.w;
    const rosca = (x: number, titulo: string, cats: string[], vals: number[]) => {
      tituloSecao(s, x, GRADE.topo, w3, titulo);
      s.grafico(x, GRADE.topo + 22, w3, 230, { tipo: "rosca", categorias: cats,
        valores: vals.map((v) => Math.max(0, Math.round(v * fatorParaMM(esc) * 10) / 10)) });
    };
    const s = slide("XIII.1 · Endividamento", mapa
      ? `${mapa.credores.length} credores; o maior, ${encurtar(mapa.credores[0].credor, 22)}, tem ${fmtPct({ v: mapa.credores[0].saldo / mapa.total * 100 }, 0).t}`
      : temDivida ? `Dívida bruta de ${vmi(I.dividaBruta)} em ${ultimo}, ${pctCP(I)}`
      : `Nenhuma dívida financeira classificada no balanço de ${ultimo}`,
    mapa ? `${fontes.replace(/\.$/, "")} · mapa da dívida de ${mapa.ano}.` : fontes);
    if (mapa) {
      const top = mapa.credores.slice(0, 7);
      tituloSecao(s, GRADE.col2.x[0], GRADE.topo, 520, `Saldo por credor, ${mapa.ano} (R$ mi)`);
      s.grafico(GRADE.col2.x[0], GRADE.topo + 22, 520, 270, { tipo: "colunas", categorias: top.map((c) => encurtar(c.credor, 14)),
        series: [{ nome: "Saldo", valores: top.map((c) => Math.round(c.saldo * fatorParaMM(esc) * 10) / 10), cor: COR.verde }] });
      const mods = mapa.modalidades.slice(0, 4);
      const resto = mapa.modalidades.slice(4).reduce((t, m) => t + m.saldo, 0);
      const xR = 605;
      tituloSecao(s, xR, GRADE.topo, GRADE.fim - xR, "Por modalidade");
      s.grafico(xR, GRADE.topo + 22, GRADE.fim - xR, 270, { tipo: "rosca",
        categorias: [...mods.map((m) => encurtar(m.modalidade, 18)), ...(resto > 0 ? ["Outras"] : [])],
        valores: [...mods.map((m) => m.saldo), ...(resto > 0 ? [resto] : [])].map((v) => Math.round(v * fatorParaMM(esc) * 10) / 10) });
      faixa(s, 410, `Custo médio implícito de ${mapa.custoMedio === null ? "n/d" : fmtPct({ v: mapa.custoMedio }).t} ao ano (juros do exercício ÷ saldo, calculado pela Oria).`);
    } else if (temDivida) {
      const cp = (I.bancosCP.v ?? 0) + (outrasCP(base, ultimo) ?? 0);
      rosca(GRADE.col3.x[0], "Por prazo", ["Curto prazo", "Longo prazo"], [cp, (I.dividaBruta.v ?? 0) - cp]);
      rosca(GRADE.col3.x[1], "Por natureza", ["Bancos", "Outras dívidas"], [I.bancos.v ?? 0, I.outras.v ?? 0]);
      cartao(s, GRADE.col3.x[2], GRADE.topo, w3, 252, { titulo: "Saldo por credor",
        corpo: base.mapasDeOutrasEntidades?.length
          ? `O mapa da dívida recebido é de ${base.mapasDeOutrasEntidades.join(", ")}, não desta entidade: a abertura por credor, a taxa e o custo médio dela dependem de um mapa próprio.`
          : "Nenhum mapa da dívida entre os documentos recebidos: a abertura por credor, a taxa e o custo médio dependem dele." });
    } else {
      cartao(s, GRADE.x, GRADE.topo, GRADE.w, 120, { titulo: "Sem dívida no balanço", corpo: "O balanço não traz conta de empréstimo, financiamento ou mútuo classificada como dívida." });
    }
  }
  {
    // XIII.2 — operação a operação, 8 por slide. Vencimento e garantia NÃO vêm no mapa: são campos
    // da apresentação, pela ordem da operação (`xiii2.op<n>.vencimento`).
    const ops = mapa?.operacoes ?? [];
    const POR = 8;
    const paginas = Math.max(1, Math.ceil(ops.length / POR));
    for (let pg = 0; pg < paginas; pg++) {
      const s = slide(`XIII.2 · Posição operação a operação${paginas > 1 ? ` (${pg + 1}/${paginas})` : ""}`,
        ops.length ? `${ops.length} operações somam ${valorMi({ v: mapa!.total, nota: "" }, esc)} no mapa de ${mapa!.ano}` : AP,
        ops.length ? `${fontes.replace(/\.$/, "")} · taxa = juros do exercício ÷ saldo final (calculado pela Oria).` : FONTE_AP);
      const linhas: LinhaTabela[] = ops.length
        ? ops.slice(pg * POR, (pg + 1) * POR).map((o, k) => {
          const n = pg * POR + k + 1;
          return { celulas: [encurtar(o.credor, 22), encurtar(o.modalidade, 18), mm({ v: o.saldoAno, nota: "" }).t,
            o.taxa === null ? "n/d" : fmtPct({ v: o.taxa }).t, ap(`op${n}.vencimento`), ap(`op${n}.garantia`)] };
        })
        : [1, 2, 3, 4].map(() => ({ celulas: [AP, AP, AP, AP, AP, AP] }));
      tabela(s, GRADE.x, GRADE.topo, [{ titulo: "Credor", w: 200 }, { titulo: "Modalidade", w: 160, algn: "l" },
        { titulo: "Saldo (R$ mi)", w: 100 }, { titulo: "Taxa a.a.", w: 107 }, { titulo: "Vencimento", w: 130, algn: "l" },
        { titulo: "Garantia", w: 140, algn: "l" }], linhas);
    }
  }
  {
    const s = slide("XIII.3 · Muro de vencimentos", ap("titulo") === AP && mapa?.custoMedio != null
      ? `Dívida de curto prazo de ${vmi({ v: (I.bancosCP.v ?? 0) + (outrasCP(base, ultimo) ?? 0), nota: "" })}, custo médio de ${fmtPct({ v: mapa.custoMedio }).t}` : AP, fontes);
    kpi(s, GRADE.col4.x[0], GRADE.topo, GRADE.col4.w, { valor: vmi({ v: (I.bancosCP.v ?? null) === null ? null : (I.bancosCP.v ?? 0) + (outrasCP(base, ultimo) ?? 0), nota: "" }),
      rotulo: "Vence em 12 meses", explicacao: `dívida de curto prazo no balanço de ${ultimo}` });
    kpi(s, GRADE.col4.x[1], GRADE.topo, GRADE.col4.w, { valor: vmi(I.caixa), rotulo: "Caixa disponível", explicacao: `balanço de ${ultimo}` });
    kpi(s, GRADE.col4.x[2], GRADE.topo, GRADE.col4.w, { valor: mapa?.custoMedio == null ? "n/d" : fmtPct({ v: mapa.custoMedio }).t,
      rotulo: "Custo médio", explicacao: mapa ? "juros ÷ saldo do mapa, calculado pela Oria" : "sem mapa da dívida" });
    kpi(s, GRADE.col4.x[3], GRADE.topo, GRADE.col4.w, { valor: ap("ruptura"), rotulo: "Primeira ruptura", explicacao: "data do primeiro ponto de ruptura de caixa" });
    cartao(s, GRADE.x, 228, GRADE.w, 150, { titulo: "Principal por trimestre, próximos 24 meses",
      corpo: `O mapa recebido traz saldo e juros, não o cronograma: ${ap("cronograma")}` });
  }

  // ======================================== cap. 09 — EBITDA normalizado e dívida sustentável
  div(9, CAPITULOS[8][0], CAPITULOS[8][1]);
  if (temDRE) {
    const s = slide("XIV · Normalização do EBITDA", `EBITDA reportado de ${vmi(I.ebitda)} em ${ultimo}; normalização ${AP}`, fontes);
    tabela(s, GRADE.x, GRADE.topo, [{ titulo: "Ajuste", w: 300 }, { titulo: "R$ mi", w: 100 }, { titulo: "Confiança", w: 180, algn: "l" }], [
      { celulas: ["EBITDA reportado", mm(I.ebitda).t, "verificado (sistema)"] },
      { celulas: ["Eventos não recorrentes", AP, AP] },
      { celulas: ["PDD e provisões atípicas", AP, AP] },
      { celulas: ["Partes relacionadas fora de mercado", AP, AP] },
      { celulas: ["Despesas capitalizadas e estoque obsoleto", AP, AP] },
      { celulas: ["EBITDA normalizado", "n/d", AP], destaque: true },
    ]);
    cartao(s, 680, GRADE.topo, GRADE.fim - 680, 200, { titulo: "Regra", corpo: "Cada ajuste leva confiança: verificado, informado ou estimado pela Oria. O EBITDA normalizado é a única base dos capítulos de dívida sustentável e garantias." });
  }
  if (temDRE) {
    const s = slide("XV · Capacidade de pagamento", mancheteSustentavel(I, esc), `${fontes.replace(/\.$/, "")} · dívida suportada ilustrativa, sobre EBITDA reportado.`);
    const suport = (m: number) => (I.ebitda.v === null || I.ebitda.v <= 0 ? "n/d" : valorMi({ v: I.ebitda.v * m, nota: "" }, esc));
    tabela(s, GRADE.col2.x[0], GRADE.topo, [{ titulo: "Geração de caixa (R$ mi)", w: 194 }, { titulo: "Base", w: 105 }, { titulo: "Estresse", w: 105 }], [
      { celulas: ["EBITDA (reportado)", mm(I.ebitda).t, AP] },
      { celulas: ["(−) Capex de manutenção", AP, AP] },
      { celulas: ["(−) IR caixa", AP, AP] },
      { celulas: ["(−) Variação da NCG", deltaNcg(ind, anos, esc), AP] },
      { celulas: ["Caixa livre", "n/d", "n/d"], destaque: true },
    ]);
    tabela(s, GRADE.col2.x[1], GRADE.topo, [{ titulo: "Dimensionamento (R$ mi)", w: 254 }, { titulo: "Valor", w: 150 }], [
      { celulas: ["Dívida financeira líquida", mm(I.dfl).t] },
      { celulas: ["Múltiplo-alvo", `${mm1(MULTIPLO_ALVO.min)}x a ${mm1(MULTIPLO_ALVO.max)}x`] },
      { celulas: [`Dívida suportada a ${mm1(MULTIPLO_ALVO.min)}x`, suport(MULTIPLO_ALVO.min)] },
      { celulas: [`Dívida suportada a ${mm1(MULTIPLO_ALVO.max)}x`, suport(MULTIPLO_ALVO.max)] },
      { celulas: ["Gap de sustentabilidade", gap(I, esc)], destaque: true },
    ]);
    faixa(s, 400, "Ilustrativo: calculado pela Oria sobre o EBITDA reportado. O dimensionamento final usa o EBITDA normalizado do capítulo XIV.");
  }
  {
    const s = slide("XV.2 · Alavancas e ruptura", AP, FONTE_AP);
    ["Alongamento", "Redução de custo", "Conversão ou capitalização", "Desinvestimentos", "Giro de capital", "Deságio"].forEach((t, i) =>
      cartao(s, GRADE.col3.x[i % 3], GRADE.topo + Math.floor(i / 3) * 175, GRADE.col3.w, 150,
        { numeral: i + 1, titulo: t, corpo: `Magnitude indicativa: ${ap(`alavanca${i + 1}`)}${t === "Deságio" ? " (só se o resto não fechar)" : ""}` }));
  }

  // ======================================== cap. 10 — garantias, scorecard, síntese
  div(10, CAPITULOS[9][0], CAPITULOS[9][1]);
  {
    // XVI — ATIVOS REAIS × DÍVIDA. Contábil do balanço; realização (%) só a que o analista informar
    // (`xvi.realizacao.*`): sem laudo, nenhum haircut é inventado.
    const ativos = ativosReais(base, ultimo);
    const contabil = ativos.reduce<number | null>((t, a) => (a.contabil === null ? t : (t ?? 0) + a.contabil), null);
    const estimado = ativos.every((a) => a.estimado !== null) ? ativos.reduce((t, a) => t + (a.estimado as number), 0) : null;
    const bruta = I.dividaBruta.v;
    const cobertura = (v: number | null) => (v === null || bruta === null || bruta <= 0 ? "n/d" : `${mm1(v / bruta)}x`);
    const s = slide("XVI · Ativos reais e garantias",
      contabil === null || bruta === null || bruta <= 0 ? "Cobertura da dívida por ativos reais não mensurável"
        : `Ativos reais cobrem ${cobertura(contabil)} a dívida bruta pelo valor contábil`,
      `${fontes.replace(/\.$/, "")} · realização: ${estimado === null ? "a preencher (sem laudo)" : "informada pelo analista"}.`);
    tabela(s, GRADE.x, GRADE.topo, [{ titulo: `Ativo real (R$ mi, ${ultimo})`, w: 337 }, { titulo: "Contábil", w: 150 },
      { titulo: "Realização (%)", w: 150 }, { titulo: "Valor estimado", w: 200 }], [
      ...ativos.map((a): LinhaTabela => ({ celulas: [a.nome, mm({ v: a.contabil, nota: "" }).t,
        a.realizacao === null ? AP : `${mm1(a.realizacao)}%`, a.estimado === null ? AP : mm({ v: a.estimado, nota: "" }).t] })),
      { celulas: ["Total de ativos reais", mm({ v: contabil, nota: "" }).t, "", estimado === null ? AP : mm({ v: estimado, nota: "" }).t], destaque: true },
      { celulas: ["Dívida financeira bruta", mm(I.dividaBruta).t, "", ""] },
      { celulas: ["Cobertura (ativos ÷ dívida)", cobertura(contabil), "", estimado === null ? AP : cobertura(estimado)] },
    ]);
    cartao(s, GRADE.x, 340, GRADE.w, 70, { titulo: "Recuperação por classe e aval dos sócios", corpo: ap("recuperacao") });
  }
  {
    const s = slide("XVII · Scorecard de risco Oria", AP, "Fonte: capítulos IX a XVI. Pesos do Prompt-Mestre Oria v3.");
    tabela(s, GRADE.x, GRADE.topo, [{ titulo: "Eixo", w: 300 }, { titulo: "Peso", w: 80 }, { titulo: "Nota", w: 115 }, { titulo: "Justificativa", w: 342, algn: "l" }], [
      ["Produto, demanda e mercado", "15%"], ["Acionistas e gestão", "20%"], ["Acesso a crédito e passivo", "15%"],
      ["Rentabilidade", "15%"], ["Geração de caixa", "20%"], ["Solvência e estrutura de capital", "15%"],
    ].map(([e, w], i): LinhaTabela => ({ celulas: [e, w, ap(`nota${i + 1}`), ap(`justificativa${i + 1}`)] }))
      .concat([{ celulas: ["Nota final ponderada", "100%", notaFinal(campos, prefixo), faixaDaNota(notaFinal(campos, prefixo))], destaque: true }]));
    s.texto(GRADE.x, 352, GRADE.w, 40, [p("Faixas: 6,5 ou mais, preventivo · de 4,5 a 6,4, estresse · abaixo de 4,5, crítico.", { entrelinha: 14.8 })], "t");
  }
  {
    const s = slide("XVIII · Síntese de crédito", mancheteExecutiva(I), fontes);
    const d = diagnostico(I, Iant, anterior, esc).map(([t, c]) => `${t}: ${c}`).join(" ");
    cartao(s, GRADE.col3.x[0], GRADE.topo, GRADE.col3.w, 280, { titulo: "Diagnóstico", corpo: d });
    cartao(s, GRADE.col3.x[1], GRADE.topo, GRADE.col3.w, 280, { titulo: "Hipótese de solução", corpo: ap("hipotese") });
    cartao(s, GRADE.col3.x[2], GRADE.topo, GRADE.col3.w, 280, { titulo: "Riscos e pontos de diligência", corpo: ap("riscos") });
  }

  // ======================================== cap. 11 — SWOT
  div(11, CAPITULOS[10][0], CAPITULOS[10][1]);
  {
    const s = slide("VII · Análise SWOT", AP, FONTE_AP);
    ["Forças", "Fraquezas", "Oportunidades", "Ameaças"].forEach((t, i) =>
      cartao(s, GRADE.col2.x[i % 2], GRADE.topo + Math.floor(i / 2) * 180, GRADE.col2.w, 160, { titulo: t, corpo: ap(["forcas", "fraquezas", "oportunidades", "ameacas"][i]) }));
  }

  // ======================================== cap. 12 — fatores críticos e próximos passos
  div(12, CAPITULOS[11][0], CAPITULOS[11][1]);
  {
    const s = slide("VIII.1 · Fatores críticos de sucesso", AP, FONTE_AP);
    [0, 1, 2, 3, 4].forEach((i) => cartao(s, GRADE.col3.x[i % 3], GRADE.topo + Math.floor(i / 3) * 175, GRADE.col3.w, 150,
      { numeral: i + 1, titulo: ap(`fator${i + 1}.titulo`), corpo: ap(`fator${i + 1}`) }));
  }
  {
    const s = slide("VIII.2 · Próximos passos", AP, "Fonte: prazos a partir da assinatura do mandato (D+0); ilustrativo.");
    tabela(s, GRADE.x, GRADE.topo, [{ titulo: "Marco", w: 120 }, { titulo: "Etapa", w: 260, algn: "l" }, { titulo: "Entregável", w: 457, algn: "l" }],
      ["D+0", "D+15", "D+30", "D+45", "D+60", "D+120"].map((m) => ({ celulas: [m, AP, AP] })));
  }

  // ===================================================== notas e avisos
  notasEAvisos(slide, am, aPreencher, ind, anos);

  // ===================================================== contracapa
  // Contatos da contracapa: "[a preencher]" por decisão do dono (02/10/2026), até alguém gravar
  // `contracapa.contato1.nome` etc.
  const contato = (n: number) => ({ nome: campos[`contracapa.contato${n}.nome`]?.valor ?? AP,
    telefone: campos[`contracapa.contato${n}.telefone`]?.valor ?? AP, email: campos[`contracapa.contato${n}.email`]?.valor ?? AP });
  contracapa(deck.novo(COR.fundoCapa), [contato(1), contato(2)]);

  return { deck, aPreencher, amarracoes: am, camposUsados: usados.length };
}

/** Nota final do scorecard: média ponderada pelos pesos do Prompt-Mestre, SÓ com as seis notas. */
const PESOS_SCORECARD = [0.15, 0.2, 0.15, 0.15, 0.2, 0.15];
function notaFinal(campos: Record<string, { valor: string }>, prefixo: string): string {
  const notas = PESOS_SCORECARD.map((_, i) => Number((campos[`${prefixo}.nota${i + 1}`]?.valor ?? "").replace(",", ".")));
  if (notas.some((n) => !Number.isFinite(n) || n < 1 || n > 10)) return "n/d";
  return notas.reduce((t, n, i) => t + n * PESOS_SCORECARD[i], 0).toLocaleString("pt-BR", { minimumFractionDigits: 1, maximumFractionDigits: 1 });
}
function faixaDaNota(t: string): string {
  if (t === "n/d") return AP;
  const n = Number(t.replace(",", "."));
  return n >= 6.5 ? "preventivo" : n >= 4.5 ? "estresse" : "crítico";
}

// -----------------------------------------------------------------------------
// Números e manchetes — regras explícitas sobre o número
// -----------------------------------------------------------------------------
/** "R$ 15,0 mi" (Prompt Padrão, item 7). */
export function valorMi(x: Valor, esc: Escala): string {
  const n = fmtMM(x, esc);
  return n.t === "n/d" || n.t === "n.s." ? n.t : `R$ ${n.t} mi`;
}
const margemBruta = (x: Indicadores): Valor => (x.lucroBruto.v === null || x.receita.v === null || x.receita.v <= 0
  ? { v: null, nota: "margem bruta: n/d", ns: x.receita.v !== null && x.receita.v <= 0 }
  : { v: (x.lucroBruto.v / x.receita.v) * 100, nota: "lucro bruto ÷ receita líquida" });
const outrasCP = (base: BaseCredito, ano: number) => base.historico.grandezas.divida_outras_cp[ano]?.v ?? null;
function pctCP(I: Indicadores): string {
  if (I.dividaBruta.v === null || I.dividaBruta.v <= 0 || I.bancosCP.v === null) return "prazo n/d";
  return `${fmtPct({ v: (I.bancosCP.v / I.dividaBruta.v) * 100 }, 0).t} bancária de curto prazo`;
}
function deltaNcg(ind: Map<number, Indicadores>, anos: number[], esc: Escala): string {
  if (anos.length < 2) return "n/d";
  const a = ind.get(anos[anos.length - 2])!.ncg.v;
  const u = ind.get(anos[anos.length - 1])!.ncg.v;
  return a === null || u === null ? "n/d" : fmtMM({ v: u - a, nota: "" }, esc).t;
}
function gap(I: Indicadores, esc: Escala): string {
  if (I.dfl.v === null || I.ebitda.v === null || I.ebitda.v <= 0) return "n/d";
  const g = I.dfl.v - I.ebitda.v * MULTIPLO_ALVO.max;
  return g <= 0 ? "sem gap a 3,5x" : valorMi({ v: g, nota: "" }, esc);
}
function mancheteSustentavel(I: Indicadores, esc: Escala): string {
  const g = gap(I, esc);
  if (g === "n/d") return "Capacidade de pagamento não mensurável sem EBITDA positivo";
  return g.startsWith("sem") ? `A dívida líquida cabe em ${mm1(MULTIPLO_ALVO.max)}x o EBITDA reportado`
    : `Gap de ${g} acima de ${mm1(MULTIPLO_ALVO.max)}x o EBITDA reportado (ilustrativo)`;
}

function naturezaCurta(ps: PeriodoCredito[]): string {
  const ns = new Set(ps.map((x) => x.natureza));
  return ns.size === 1 && ns.has("A") ? "demonstrações auditadas" : ns.has("A") ? "auditadas e não auditadas" : "demonstrações não auditadas";
}

function mancheteExecutiva(I: Indicadores): string {
  const m = fmtX(I.dflEbitda).t;
  switch (faixaDeAlavancagem(I)) {
    case "ebitda_nao_positivo": return "EBITDA não positivo: a dívida não tem geração que a sirva";
    case "nd": return "Alavancagem não mensurável com o que o documento informa";
    case "caixa_liquido": return "Caixa supera a dívida: o tema é liquidez e rentabilidade, não solvência";
    case "abaixo": return `DFL/EBITDA de ${m}, abaixo da faixa de ${mm1(MULTIPLO_ALVO.min)}x a ${mm1(MULTIPLO_ALVO.max)}x`;
    case "faixa": return `DFL/EBITDA de ${m}, dentro da faixa de ${mm1(MULTIPLO_ALVO.min)}x a ${mm1(MULTIPLO_ALVO.max)}x`;
    case "acima": return `DFL/EBITDA de ${m}, acima do teto de ${mm1(MULTIPLO_ALVO.max)}x sustentável`;
  }
}

/** Os três cartões do sumário: [título, corpo]. */
function diagnostico(I: Indicadores, Iant: Indicadores | null, anterior: number | null, esc: Escala): Array<[string, string]> {
  const v = Iant ? variacao(Iant.receita.v, I.receita.v) : { v: null, ns: false };
  return [
    ["Receita e margem", `Receita líquida de ${valorMi(I.receita, esc)}`
      + (anterior !== null ? (v.v === null ? `, variação contra ${anterior} ${v.ns ? "n.s." : "n/d"}` : `, ${pctTexto(v.v)} contra ${anterior}`) : "")
      + (I.margemEbitda.v === null ? "; margem EBITDA n/d." : `; margem EBITDA de ${fmtPct(I.margemEbitda).t}.`)],
    ["Dívida e caixa", I.dividaBruta.v === null ? "Dívida financeira não identificada no balanço."
      : `Dívida bruta de ${valorMi(I.dividaBruta, esc)} contra caixa de ${valorMi(I.caixa, esc)}; liquidez corrente de ${fmtX(I.liquidezCorrente).t}.`],
    ["Capital de giro", I.ciclo.v === null ? "Ciclo financeiro n/d: falta saldo de giro ou custo na DRE."
      : `Ciclo financeiro de ${fmtDias(I.ciclo).t} dias: PMR ${fmtDias(I.pmr).t}, PME ${fmtDias(I.pme).t} e PMP ${fmtDias(I.pmp).t}.`],
  ];
}

function implicacaoPrincipal(I: Indicadores): string {
  return {
    ebitda_nao_positivo: "Sem EBITDA positivo, qualquer alongamento só adia: o plano começa pela operação.",
    acima: `Acima de ${mm1(MULTIPLO_ALVO.max)}x, alongar não basta: o dimensionamento do capítulo XV define o esforço.`,
    faixa: "Alavancagem na faixa-alvo: o mandato tende a reperfilamento e otimização da estrutura de capital.",
    abaixo: `Alavancagem abaixo de ${mm1(MULTIPLO_ALVO.min)}x: o tema é liquidez e prazo, não o tamanho da dívida.`,
    caixa_liquido: "Caixa acima da dívida: o tema é rentabilidade e liquidez, não solvência.",
    nd: "Alavancagem não mensurada: obter D&A e a abertura da dívida antes de dimensionar.",
  }[faixaDeAlavancagem(I)];
}

function mancheteCiclo(I: Indicadores, ultimo: number): string {
  // SEM ESTOQUE NO BALANÇO (serviços, holding operacional): o ciclo fica n/d — estoque ausente não
  // vira zero —, mas o título diz o que SE mede, em vez de "não mensurável" para uma empresa cujos
  // prazos de recebimento e pagamento estão no documento.
  if (I.ciclo.v === null && I.pme.v === null && I.pmr.v !== null && I.pmp.v !== null) {
    return `PMR de ${fmtDias(I.pmr).t} e PMP de ${fmtDias(I.pmp).t} dias em ${ultimo}; balanço sem conta de estoque`;
  }
  return I.ciclo.v === null ? `Ciclo financeiro de ${ultimo} não mensurável pelos documentos`
    : `Ciclo financeiro de ${fmtDias(I.ciclo).t} dias em ${ultimo}: PMR ${fmtDias(I.pmr).t}, PME ${fmtDias(I.pme).t}, PMP ${fmtDias(I.pmp).t}`;
}

function mancheteMargem(ind: Map<number, Indicadores>, anos: number[]): string {
  const u = margemBruta(ind.get(anos[anos.length - 1])!);
  if (u.v === null) return "Margem bruta não mensurável pelos documentos recebidos";
  if (anos.length >= 2) {
    const a = margemBruta(ind.get(anos[anos.length - 2])!);
    if (a.v !== null) {
      const d = u.v - a.v;
      return `Margem bruta ${d < 0 ? "caiu" : "subiu"} de ${fmtPct(a).t} para ${fmtPct(u).t} entre ${anos[anos.length - 2]} e ${anos[anos.length - 1]}`;
    }
  }
  return `Margem bruta de ${fmtPct(u).t} em ${anos[anos.length - 1]}`;
}

function mancheteResultado(I: Indicadores, Iant: Indicadores | null, ultimo: number, anterior: number | null): string {
  if (Iant && anterior !== null) {
    const v = variacao(Iant.ebitda.v, I.ebitda.v);
    if (I.ebitda.v !== null && I.ebitda.v <= 0) return `EBITDA não positivo em ${ultimo}`;
    if (v.v !== null && v.v <= -20) return `EBITDA caiu ${fmtPct({ v: -v.v }, 0).t} entre ${anterior} e ${ultimo}`;
    if (v.v !== null && v.v >= 20) return `EBITDA cresceu ${fmtPct({ v: v.v }, 0).t} entre ${anterior} e ${ultimo}`;
    const r = variacao(Iant.receita.v, I.receita.v);
    if (r.v !== null) return `Receita ${r.v < 0 ? "recuou" : "avançou"} ${fmtPct({ v: Math.abs(r.v) }, 0).t} em ${ultimo}, margem EBITDA de ${fmtPct(I.margemEbitda).t}`;
  }
  return I.margemEbitda.v === null ? `Resultado de ${ultimo}: EBITDA não mensurável pela DRE` : `Margem EBITDA de ${fmtPct(I.margemEbitda).t} em ${ultimo}`;
}

/** A faixa do X.1: uma frase, até 2 linhas na meia largura. */
function leituraResultado(ind: Map<number, Indicadores>, anos: number[], esc: Escala): string {
  const u = ind.get(anos[anos.length - 1])!;
  if (u.da.v === null) return "A DRE não traz D&A: o EBITDA sai n/d em vez de igualado ao EBIT.";
  if (u.lucroLiquido.v !== null && u.lucroLiquido.v < 0) return `Prejuízo de ${valorMi({ v: -u.lucroLiquido.v, nota: "" }, esc)} em ${anos[anos.length - 1]}: o patrimônio líquido absorve a perda.`;
  return u.lucroLiquido.v === null ? "Lucro líquido n/d no último exercício." : `Lucro líquido de ${valorMi(u.lucroLiquido, esc)} no último exercício.`;
}

function mancheteAlavancagem(I: Indicadores, ultimo: number): string {
  if (I.dflEbitda.v === null) return I.dfl.v === null ? `Dívida líquida de ${ultimo} não mensurável pelo balanço` : `DFL/EBITDA de ${ultimo} sem leitura: EBITDA ${I.ebitda.v === null ? "n/d" : "não positivo"}`;
  return `DFL/EBITDA de ${fmtX(I.dflEbitda).t} em ${ultimo}, liquidez corrente de ${fmtX(I.liquidezCorrente).t}`;
}

function leituraEstrutura(I: Indicadores, ultimo: number, esc: Escala): string[] {
  const out: string[] = [];
  const m = fmtX(I.dflEbitda).t;
  out.push({
    acima: `A ${m}, a dívida líquida excede o teto de ${mm1(MULTIPLO_ALVO.max)}x do EBITDA de ${ultimo}.`,
    faixa: `A ${m}, a dívida líquida cabe na faixa-alvo de ${mm1(MULTIPLO_ALVO.min)}x a ${mm1(MULTIPLO_ALVO.max)}x.`,
    abaixo: `A ${m}, a dívida líquida fica abaixo da faixa-alvo de ${mm1(MULTIPLO_ALVO.min)}x a ${mm1(MULTIPLO_ALVO.max)}x.`,
    caixa_liquido: `O caixa supera a dívida bruta em ${ultimo}: não há dívida líquida a dimensionar.`,
    ebitda_nao_positivo: `EBITDA de ${ultimo} não positivo: DFL/EBITDA sem leitura (n.s.).`,
    nd: "DFL/EBITDA n/d: a alavancagem não pode ser dimensionada com estes documentos.",
  }[faixaDeAlavancagem(I)]);
  if (I.outras.v !== null && I.outras.v !== 0) out.push(`Outras dívidas (mútuos e partes relacionadas) de ${valorMi(I.outras, esc)} formam classe à parte.`);
  if (I.liquidezCorrente.v !== null && I.liquidezCorrente.v < 1) out.push("O passivo de curto prazo excede o ativo circulante.");
  return out.slice(0, 3);
}

function leituraNcg(I: Indicadores, ultimo: number, esc: Escala): string {
  const n = I.ncg;
  const f = I.ncgFinanciadaCP;
  if (n.v === null) return `NCG de ${ultimo} n/d: ${limparMotivo(n.nota)}.`;
  if (n.v <= 0) return "Com NCG não positiva, a dívida bancária de CP não financia giro: identificar o que ela financia.";
  if (f.v === null) return `NCG de ${valorMi(n, esc)}; financiamento por dívida de CP não mensurável.`;
  return f.v > 100 ? `A dívida bancária de CP é ${fmtPct({ v: f.v }, 0).t} da NCG: financia o giro e mais, e é o que precisa ser alongado.`
    : `${fmtPct({ v: f.v }, 0).t} da NCG de ${valorMi(n, esc)} está financiada por dívida bancária de CP, que é o que precisa ser alongado.`;
}

function mancheteComparativo(I: Indicadores, Iant: Indicadores, ultimo: number, anterior: number): string {
  const r = variacao(Iant.receita.v, I.receita.v);
  const d = variacao(Iant.dfl.v, I.dfl.v);
  if (r.v !== null && d.v !== null) {
    return `${ultimo} contra ${anterior}: receita ${pctTexto(r.v, 0)}, dívida líquida ${pctTexto(d.v, 0)}`;
  }
  return `${ultimo} contra ${anterior}: exercícios fechados lado a lado`;
}

function leituraComparativo(I: Indicadores, Iant: Indicadores, ultimo: number, anterior: number): string[] {
  const out: string[] = [];
  const r = variacao(Iant.receita.v, I.receita.v);
  const e = variacao(Iant.ebitda.v, I.ebitda.v);
  if (r.v !== null && e.v !== null) {
    out.push(e.v < r.v ? (e.v < 0
      ? `O EBITDA (${pctTexto(e.v)}) piorou mais que a receita (${pctTexto(r.v)}): perda de margem, não só de volume.`
      : `O EBITDA (${pctTexto(e.v)}) cresceu menos que a receita (${pctTexto(r.v)}): a margem encolheu.`)
      : `O EBITDA (${pctTexto(e.v)}) acompanhou ou superou a receita (${pctTexto(r.v)}).`);
  } else out.push(`Variação de receita ou EBITDA entre ${anterior} e ${ultimo} não mensurável (n/d ou n.s.).`);
  const d = variacao(Iant.dfl.v, I.dfl.v);
  if (d.v !== null) out.push(`A dívida líquida ${d.v >= 0 ? "subiu" : "caiu"} ${fmtPct({ v: Math.abs(d.v) }).t} no período.`);
  if (I.ciclo.v !== null && Iant.ciclo.v !== null) {
    const dc = Math.round(I.ciclo.v) - Math.round(Iant.ciclo.v);
    out.push(`O ciclo financeiro ${dc >= 0 ? "alongou" : "encurtou"} ${Math.abs(dc)} dias.`);
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
  const escala = base.historico.avisosDeEscala;
  if (escala.length) out.push(`Unidade não reconhecida em ${escala.length} linha(s), sem conversão de escala.`);
  if (out.length === 0) out.push("Nenhum ponto detectado pelas regras automáticas, o que não atesta a qualidade contábil.");
  return out.slice(0, 3);
}

function contarND(ind: Map<number, Indicadores>): number {
  // Só AUSÊNCIA conta aqui: n.s. (denominador negativo) não é "falta de linha no documento".
  let n = 0;
  for (const x of ind.values()) for (const v of Object.values(x) as Valor[]) if (v.v === null && !v.ns) n++;
  return n;
}

// -----------------------------------------------------------------------------
// Notas e avisos (componente I) — amarrações com veredito, o que ficou a preencher, os n/d
// -----------------------------------------------------------------------------
const ROTULO_VEREDITO = { ok: "Fecha", diverge: "NÃO FECHA", por_construcao: "Por definição", nao_conferivel: "Não conferível" } as const;

function notasEAvisos(slide: (r: string, t: string, f: string, sub?: string) => SlideOria,
  am: Amarracao[], aPreencher: string[], ind: Map<number, Indicadores>, anos: number[]) {
  const nDiverge = am.filter((a) => a.veredito === "diverge").length;
  const nNao = am.filter((a) => a.veredito === "nao_conferivel").length;
  const nOk = am.filter((a) => a.veredito === "ok").length;
  const titulo = nDiverge > 0 ? `${nDiverge} amarração(ões) não fecham: ler antes de usar os números`
    : nOk === 0 ? `Nenhuma conferência pôde rodar; ${nNao} amarrações sem insumo`
    : `${nOk} conferências fecham; ${nNao} não puderam ser conferidas`;
  const POR_SLIDE = 8;
  const paginas = Math.max(1, Math.ceil(am.length / POR_SLIDE));
  for (let pg = 0; pg < paginas; pg++) {
    const s = slide(`Notas e avisos · amarrações${paginas > 1 ? ` (${pg + 1}/${paginas})` : ""}`, titulo,
      `Fonte: amarrações do Prompt-Mestre Oria v3. ${LEGENDA_NATUREZA}.`);
    tabela(s, GRADE.x, GRADE.topo, [
      { titulo: "Nº", w: 40, algn: "ctr" }, { titulo: "Amarração", w: 290, algn: "l" }, { titulo: "Ano", w: 55, algn: "ctr" },
      { titulo: "Veredito", w: 120, algn: "l" }, { titulo: "Detalhe", w: 332, algn: "l" },
    ], am.slice(pg * POR_SLIDE, (pg + 1) * POR_SLIDE).map((a) => ({
      destaque: a.veredito === "diverge",
      celulas: [String(a.numero), a.nome, a.ano === null ? "—" : String(a.ano), ROTULO_VEREDITO[a.veredito], encurtar(a.detalhe, 48)],
    })));
  }
  const s = slide("Notas e avisos", "O que ficou a preencher e o motivo de cada n/d", "Fonte: elaboração Oria a partir dos documentos recebidos.");
  const motivos = [...new Set(anos.flatMap((a) => (Object.values(ind.get(a)!) as Valor[])
    .filter((v) => v.v === null).map((v) => (v.ns ? v.nota : limparMotivo(v.nota)))))].slice(0, 2);
  notas(s, GRADE.x, GRADE.topo, GRADE.w, 370, [
    ...aPreencher.map((t, i) => ({ abertura: `Nota ${i + 1} — a preencher.`, texto: t })),
    { abertura: `Nota ${aPreencher.length + 1} — n/d e n.s.`, texto: `n/d é linha que o documento não traz; n.s. é conta sem leitura (base negativa). ${motivos.length ? `Neste caso: ${motivos.map((m) => encurtar(m, 90)).join("; ")}.` : "Nenhum indicador saiu n/d."}` },
    { abertura: `Nota ${aPreencher.length + 2} — definições.`, texto: "NCG = clientes + estoques − fornecedores; prazos em base de 360 dias; DFL = dívida bruta − caixa e aplicações." },
    { abertura: "Aviso.", texto: "Material elaborado pela Oria Partners a partir de documentos fornecidos pela companhia, sem auditoria independente. Não constitui oferta nem recomendação." },
  ]);
}

function limparMotivo(nota: string): string {
  // "Margem EBITDA: n/d porque EBITDA: n/d porque X" → a causa primeira, que é a que se conserta.
  const partes = nota.split(/n\/d porque |n\/d — /);
  return partes[partes.length - 1].trim();
}

// -----------------------------------------------------------------------------
// Utilidades
// -----------------------------------------------------------------------------
const ROTULO_TIPO: Record<string, string> = {
  BALANCO: "Balanço patrimonial", DRE: "DRE", BALANCETE: "Balancete", DF_AUDITADA: "Demonstrações auditadas",
  COMBINADO: "Demonstrações combinadas", FLUXO_CAIXA: "Fluxo de caixa", DMPL: "DMPL", NOTAS_EXPL: "Notas explicativas",
  MAPA_DIVIDA: "Mapa da dívida", FATURAMENTO_24M: "Faturamento 24 meses",
};
/** Chave de campo a partir de um nome ("CANASTRA PARTICIPAÇÕES S.A." → "canastraparticipacoessa"). */
const chaveDe = (nome: string) => nome.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 40);
const rotuloTipo = (t: string) => ROTULO_TIPO[t] ?? t.toLowerCase().replace(/_/g, " ");
const capitalizar = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
export const encurtar = (s: string, n: number) => (s.length <= n ? s : `${s.slice(0, n - 1).trimEnd()}…`);

/** A nota de fonte dos slides financeiros: uma linha de 8,5 pt, com a natureza dos dados. */
export function fontesFinanceiras(base: BaseCredito, periodos: PeriodoCredito[]): string {
  const anos = periodos.map((x) => x.ano);
  const tipos = new Set(base.documentos.filter((d) => d.anos.some((a) => anos.includes(a))).map((d) => d.tipo ?? ""));
  const nomes = [tipos.has("DF_AUDITADA") && "DFs auditadas", tipos.has("BALANCO") && "balanços", tipos.has("DRE") && "DREs",
    tipos.has("COMBINADO") && "demonstrações", tipos.has("BALANCETE") && "balancetes"].filter(Boolean).join(", ");
  const faixaAnos = anos.length > 1 ? `${anos[0]} a ${anos[anos.length - 1]}` : String(anos[0]);
  const ns = new Set(periodos.map((x) => x.natureza));
  const legenda = [...ns].map((n) => n === "A" ? "(A) auditada" : n === "B" ? "(B) não auditada" : n === "R" ? "(R) revisão limitada" : "(G) gerencial").join(" · ");
  // Total que o documento NÃO imprime e saiu da cascata vai marcado em todo slide financeiro: o
  // número na célula é o mesmo, mas quem lê precisa saber que ele foi derivado (revisão 03/10).
  const calc = (["receita_liquida", "lucro_bruto", "ebit"] as const).filter((k) =>
    anos.some((a) => base.historico.grandezas[k][a]?.calculado));
  const marca = calc.length ? ` ${calc.map((k) => ({ receita_liquida: "receita", lucro_bruto: "lucro bruto", ebit: "EBIT" })[k]).join(", ")} calculados pela Oria (sem total no documento).` : "";
  return encurtar(`Fonte: ${nomes || "demonstrações"} ${faixaAnos} da ${encurtar(base.entidade, 40).replace(/\.$/, "")}. Cálculos Oria.${marca} ${legenda}.`, 170);
}

export type { Paragrafo, SlideOria };
