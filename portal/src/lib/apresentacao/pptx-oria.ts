// O PADRÃO INSTITUCIONAL ORIA EM .PPTX — a biblioteca que os geradores de apresentação usam.
//
// A FONTE DA VERDADE VISUAL é o "Prompt Padrão Oria" (Teaser "Home Equity — R$ 15 milhões",
// set/2026, medido elemento por elemento), cópia em
// `Arquitetura do Sistema/6 Referência/apresentacao-credito/PROMPT_PADRAO_ORIA.md`. Ele substituiu,
// por decisão do dono (02/10/2026), a seção visual do Prompt-Mestre v3: fonte Verdana, medidas em
// pt na tela de 960 × 540, rodapé em 8,5/7,5 pt, e SÓ os componentes da seção 4.7 (KPI, cartão
// numerado, faixa de conclusão, cartão de leitura, lista campo/valor, tabela, gráfico, bloco de
// texto, notas). Dois acréscimos pedidos pelo dono, fora do Teaser: as divisórias de capítulo e o
// gráfico de rosca do endividamento — ambos desenhados com a mesma paleta e a mesma tipografia.
//
// POR QUE OOXML ESCRITO À MÃO, e não pptxgenjs como o Prompt Padrão sugere (aprovado pelo dono):
// o portal roda numa função da Vercel e o JSZip já está no lock (degrau 5 da escada). Escrever o
// XML transforma em garantia o que o prompt pede como cuidado:
//   • `emu()` arredonda toda coordenada para inteiro (float dispara o reparo do PowerPoint);
//   • nenhum shape tem `p:style`, todo `spPr` leva `<a:effectLst/>` (sem sombra);
//   • todo parágrafo declara `<a:buNone/>` e `endParaRPr` em pt-BR com a fonte.
// E DUAS REGRAS DO PROMPT VIRAM TIPO: `Cor` é a paleta fechada da seção 4.2; `run()` LANÇA em
// corpo abaixo de 11 pt, salvo os dois tamanhos que o próprio prompt fixa (nota de fonte 8,5 e
// confidencialidade 7,5) — "nunca reduza para caber".
import JSZip from "jszip";
import { LOGO_ORIA_PNG_BASE64, LOGO_ORIA_PX } from "./logo-oria";

// -----------------------------------------------------------------------------
// Paleta — exatamente a da seção 4.2 do Prompt Padrão.
// -----------------------------------------------------------------------------
export const COR = {
  fundoCapa: "E7EEE8",
  branco: "FFFFFF",
  cartao: "EEF3EE",
  linha: "D6DED6",
  verde: "2E5B45",
  laranja: "F04600",
  texto: "404040",
  rotuloKpi: "4A4A4A",
  apoio: "707070",
  marinho: "16263B",
  eixo: "888888",
} as const;
export type Cor = (typeof COR)[keyof typeof COR];
export const PALETA: ReadonlySet<string> = new Set(Object.values(COR));
/** Ordem das fatias da rosca: as duas cores de acento primeiro, depois os neutros da paleta. */
export const CORES_DE_FATIA: readonly Cor[] = [COR.verde, COR.laranja, COR.eixo, COR.linha, COR.texto, COR.cartao];

export const FONTE = "Verdana";
export const FONTES_PERMITIDAS: ReadonlySet<string> = new Set([FONTE]);
export const CORPO_MINIMO_PT = 11;
/** Os únicos corpos abaixo de 11 pt que o prompt fixa: nota de fonte e confidencialidade. */
export const CORPOS_DE_RODAPE: ReadonlySet<number> = new Set([8.5, 7.5]);

// -----------------------------------------------------------------------------
// Geometria: pt na API (a unidade do prompt, 960 × 540), EMU inteiro no XML.
// -----------------------------------------------------------------------------
export const emu = (pt: number): number => Math.round(pt * 12700);
export const TELA = { w: 960, h: 540 } as const;
export const GRADE = {
  x: 61, w: 837, fim: 898,
  /** início do conteúdo sem e com subtítulo */
  topo: 110, topoComSub: 136,
  /** o conteúdo termina antes disto */
  base: 488,
  col3: { w: 262.8, x: [61.2, 348.5, 635.8] },
  col4: { w: 200, x: [61.2, 277.7, 494.3, 710.8] },
  /** duas colunas de conteúdo misto */
  col2: { w: 404, x: [61, 494] },
} as const;

export const RODAPE_CONFIDENCIAL =
  "CONFIDENCIAL – Para uso exclusivo do destinatário. Não reproduzir ou distribuir sem autorização.";
export const A_PREENCHER = "[a preencher]";

const esc = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
    // Byte de controle em rótulo vindo de PDF já quebrou o export (8d378b0); XML 1.0 não o aceita.
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "");

// -----------------------------------------------------------------------------
// Texto
// -----------------------------------------------------------------------------
export interface Run {
  t: string;
  /** corpo em pt; padrão 11 */
  sz?: number;
  b?: boolean;
  i?: boolean;
  cor?: Cor;
  /** espaçamento entre letras em centésimos de pt (o "≈ 3" do prompt = 300) */
  spc?: number;
}
export interface Paragrafo {
  runs: Run[];
  algn?: "l" | "ctr" | "r";
  /** entrelinha em pt (13,9 nos cartões, 14,8 no texto corrido) */
  entrelinha?: number;
  /** espaço depois, em pt */
  depois?: number;
}

export const p = (t: string, estilo: Omit<Run, "t"> & Omit<Paragrafo, "runs"> = {}): Paragrafo => {
  const { algn, entrelinha, depois, ...run } = estilo;
  return { runs: [{ t, ...run }], algn, entrelinha, depois };
};

function validarCorpo(sz: number, t: string) {
  if (sz < CORPO_MINIMO_PT && !CORPOS_DE_RODAPE.has(sz)) {
    throw new Error(`pptx-oria: corpo ${sz} pt em "${t.slice(0, 40)}" — o Prompt Padrão fixa 11 pt no corpo `
      + "(8,5 só na nota de fonte e 7,5 só na confidencialidade). Reescreva mais curto ou divida o slide.");
  }
}

function rPr(r: Run, tag: "a:rPr" | "a:endParaRPr"): string {
  const sz = r.sz ?? CORPO_MINIMO_PT;
  validarCorpo(sz, r.t);
  const attrs = [`lang="pt-BR"`, `sz="${Math.round(sz * 100)}"`, `b="${r.b ? 1 : 0}"`, `i="${r.i ? 1 : 0}"`,
    ...(r.spc ? [`spc="${Math.round(r.spc)}"`] : []), `dirty="0"`].join(" ");
  return `<${tag} ${attrs}><a:solidFill><a:srgbClr val="${r.cor ?? COR.apoio}"/></a:solidFill>`
    + `<a:latin typeface="${FONTE}"/><a:cs typeface="${FONTE}"/></${tag}>`;
}

function paragrafoXml(par: Paragrafo): string {
  const ln = par.entrelinha
    ? `<a:lnSpc><a:spcPts val="${Math.round(par.entrelinha * 100)}"/></a:lnSpc>`
    : `<a:lnSpc><a:spcPct val="100000"/></a:lnSpc>`;
  const pPr = `<a:pPr algn="${par.algn ?? "l"}">${ln}<a:spcBef><a:spcPts val="0"/></a:spcBef>`
    + `<a:spcAft><a:spcPts val="${Math.round((par.depois ?? 0) * 100)}"/></a:spcAft><a:buNone/></a:pPr>`;
  const runs = par.runs.map((r) => `<a:r>${rPr(r, "a:rPr")}<a:t>${esc(r.t)}</a:t></a:r>`).join("");
  const ultimo = par.runs[par.runs.length - 1] ?? { t: "" };
  return `<a:p>${pPr}${runs}${rPr({ ...ultimo, t: "" }, "a:endParaRPr")}</a:p>`;
}

const txtPr = (sz: number, cor: Cor, b = false) =>
  `<c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz="${Math.round(sz * 100)}" b="${b ? 1 : 0}">`
  + `<a:solidFill><a:srgbClr val="${cor}"/></a:solidFill><a:latin typeface="${FONTE}"/><a:cs typeface="${FONTE}"/>`
  + `</a:defRPr></a:pPr><a:endParaRPr lang="pt-BR"/></a:p></c:txPr>`;

// -----------------------------------------------------------------------------
// Gráficos nativos (componente G do prompt, e a rosca pedida pelo dono)
// -----------------------------------------------------------------------------
export interface SerieColunas { nome: string; valores: (number | null)[]; cor: Cor }
export type EspecGrafico =
  | { tipo: "colunas"; categorias: string[]; series: SerieColunas[]; formato?: string }
  | { tipo: "rosca"; categorias: string[]; valores: number[] };

const numLit = (vals: (number | null)[], fmt: string) =>
  `<c:numLit><c:formatCode>${esc(fmt)}</c:formatCode><c:ptCount val="${vals.length}"/>`
  + vals.map((v, i) => (v === null ? "" : `<c:pt idx="${i}"><c:v>${v}</c:v></c:pt>`)).join("") + `</c:numLit>`;
const strLit = (cats: string[]) =>
  `<c:strLit><c:ptCount val="${cats.length}"/>` + cats.map((c, i) => `<c:pt idx="${i}"><c:v>${esc(c)}</c:v></c:pt>`).join("") + `</c:strLit>`;
const semLinha = `<c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr>`;

function graficoXml(g: EspecGrafico): string {
  const cab = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><c:chartSpace xmlns:c="${NS.c}" xmlns:a="${NS.a}" xmlns:r="${NS.r}">`
    + `<c:roundedCorners val="0"/><c:chart><c:autoTitleDeleted val="1"/><c:plotArea><c:layout/>`;
  const rotulos = (extra: string) => `<c:dLbls>${extra}${semLinha}${txtPr(11, COR.texto)}`;
  const legenda = (n: number) => (n > 1
    ? `<c:legend><c:legendPos val="b"/><c:overlay val="0"/>${txtPr(11, COR.apoio)}</c:legend>` : "");
  const fim = (nLegenda: number) => `${semLinha}</c:plotArea>${legenda(nLegenda)}<c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart>`
    + `${semLinha}${txtPr(11, COR.apoio)}</c:chartSpace>`;
  if (g.tipo === "colunas") {
    const fmt = g.formato ?? "#,##0.0";
    const series = g.series.map((s, i) => `<c:ser><c:idx val="${i}"/><c:order val="${i}"/><c:tx><c:v>${esc(s.nome)}</c:v></c:tx>`
      + `<c:spPr><a:solidFill><a:srgbClr val="${s.cor}"/></a:solidFill><a:ln><a:noFill/></a:ln></c:spPr><c:invertIfNegative val="0"/>`
      + rotulos(`<c:numFmt formatCode="${esc(fmt)}" sourceLinked="0"/>`)
      + `<c:dLblPos val="outEnd"/><c:showLegendKey val="0"/><c:showVal val="1"/><c:showCatName val="0"/><c:showSerName val="0"/>`
      + `<c:showPercent val="0"/><c:showBubbleSize val="0"/></c:dLbls>`
      + `<c:cat>${strLit(g.categorias)}</c:cat><c:val>${numLit(s.valores, fmt)}</c:val></c:ser>`).join("");
    return cab + `<c:barChart><c:barDir val="col"/><c:grouping val="clustered"/><c:varyColors val="0"/>${series}`
      + `<c:gapWidth val="80"/><c:overlap val="-10"/><c:axId val="1"/><c:axId val="2"/></c:barChart>`
      // Eixo X em 888888 com marcas curtas; sem eixo Y e sem linha de grade (componente G).
      + `<c:catAx><c:axId val="1"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="b"/>`
      + `<c:numFmt formatCode="General" sourceLinked="0"/><c:majorTickMark val="out"/><c:minorTickMark val="none"/>`
      + `<c:tickLblPos val="low"/><c:spPr><a:ln w="6350"><a:solidFill><a:srgbClr val="${COR.eixo}"/></a:solidFill></a:ln></c:spPr>`
      + `${txtPr(11, COR.apoio)}<c:crossAx val="2"/><c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/>`
      + `<c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/></c:catAx>`
      + `<c:valAx><c:axId val="2"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="1"/><c:axPos val="l"/>`
      + `<c:numFmt formatCode="General" sourceLinked="0"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/>`
      + `<c:tickLblPos val="nextTo"/><c:crossAx val="1"/><c:crosses val="autoZero"/><c:crossBetween val="between"/></c:valAx>`
      + fim(g.series.length);
  }
  const fatias = g.valores.map((_, i) => `<c:dPt><c:idx val="${i}"/><c:bubble3D val="0"/><c:spPr><a:solidFill>`
    + `<a:srgbClr val="${CORES_DE_FATIA[i % CORES_DE_FATIA.length]}"/></a:solidFill><a:ln w="12700"><a:solidFill>`
    + `<a:srgbClr val="${COR.branco}"/></a:solidFill></a:ln></c:spPr></c:dPt>`).join("");
  return cab + `<c:doughnutChart><c:varyColors val="1"/><c:ser><c:idx val="0"/><c:order val="0"/><c:tx><c:v>s</c:v></c:tx>`
    + fatias + rotulos(`<c:numFmt formatCode="0%" sourceLinked="0"/>`)
    + `<c:showLegendKey val="0"/><c:showVal val="0"/><c:showCatName val="0"/><c:showSerName val="0"/><c:showPercent val="1"/>`
    + `<c:showBubbleSize val="0"/><c:showLeaderLines val="0"/></c:dLbls>`
    + `<c:cat>${strLit(g.categorias)}</c:cat><c:val>${numLit(g.valores, "General")}</c:val></c:ser>`
    + `<c:firstSliceAng val="0"/><c:holeSize val="60"/></c:doughnutChart>` + fim(2);
}

// -----------------------------------------------------------------------------
// Slide
// -----------------------------------------------------------------------------
type Ancora = "t" | "ctr" | "b";

export class SlideOria {
  private shapes: string[] = [];
  private proximoId = 2;
  usaLogo = false;
  readonly graficos: EspecGrafico[] = [];

  constructor(readonly fundo: Cor = COR.branco) {}

  private id() { return this.proximoId++; }

  private spPr(x: number, y: number, w: number, h: number, geom: string, fill?: Cor) {
    const preenchimento = fill ? `<a:solidFill><a:srgbClr val="${fill}"/></a:solidFill>` : "<a:noFill/>";
    return `<p:spPr><a:xfrm><a:off x="${emu(x)}" y="${emu(y)}"/><a:ext cx="${emu(w)}" cy="${emu(h)}"/></a:xfrm>`
      + `<a:prstGeom prst="${geom}"><a:avLst/></a:prstGeom>${preenchimento}<a:ln><a:noFill/></a:ln><a:effectLst/></p:spPr>`;
  }

  /** Retângulo sólido de cantos retos, sem borda e sem sombra (o único tipo de forma do prompt). */
  forma(x: number, y: number, w: number, h: number, fill: Cor) {
    const id = this.id();
    this.shapes.push(`<p:sp><p:nvSpPr><p:cNvPr id="${id}" name="Forma ${id}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>`
      + this.spPr(x, y, w, h, "rect", fill) + `</p:sp>`);
  }

  /** Caixa de texto: margem zero (o prompt), âncora explícita, sem autoajuste. */
  texto(x: number, y: number, w: number, h: number, pars: Paragrafo[], ancora: Ancora = "t", recuo = 0) {
    const id = this.id();
    const ins = emu(recuo);
    this.shapes.push(`<p:sp><p:nvSpPr><p:cNvPr id="${id}" name="Texto ${id}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>`
      + this.spPr(x, y, w, h, "rect")
      + `<p:txBody><a:bodyPr wrap="square" lIns="${ins}" tIns="0" rIns="${ins}" bIns="0" anchor="${ancora}" rtlCol="0">`
      + `<a:noAutofit/></a:bodyPr><a:lstStyle/>${pars.map(paragrafoXml).join("")}</p:txBody></p:sp>`);
  }

  /** Régua ou fio de grade, em pt. */
  fio(x: number, y: number, w: number, h: number, cor: Cor = COR.linha, pt = 0.75) {
    const id = this.id();
    this.shapes.push(`<p:cxnSp><p:nvCxnSpPr><p:cNvPr id="${id}" name="Fio ${id}"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr>`
      + `<p:spPr><a:xfrm><a:off x="${emu(x)}" y="${emu(y)}"/><a:ext cx="${emu(w)}" cy="${emu(h)}"/></a:xfrm>`
      + `<a:prstGeom prst="line"><a:avLst/></a:prstGeom><a:ln w="${Math.round(pt * 12700)}"><a:solidFill>`
      + `<a:srgbClr val="${cor}"/></a:solidFill></a:ln><a:effectLst/></p:spPr></p:cxnSp>`);
  }

  /** O logo oficial (arquivo, nunca redesenhado), `lado` pt de largura. */
  logo(x: number, y: number, lado: number) {
    this.usaLogo = true;
    const id = this.id();
    const h = lado * (LOGO_ORIA_PX.altura / LOGO_ORIA_PX.largura);
    this.shapes.push(`<p:pic><p:nvPicPr><p:cNvPr id="${id}" name="Logo Oria"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/>`
      + `</p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed="rIdLogo"/><a:stretch><a:fillRect/></a:stretch>`
      + `</p:blipFill><p:spPr><a:xfrm><a:off x="${emu(x)}" y="${emu(y)}"/><a:ext cx="${emu(lado)}" cy="${emu(h)}"/></a:xfrm>`
      + `<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:effectLst/></p:spPr></p:pic>`);
  }

  /** Gráfico nativo do PowerPoint (editável), nunca imagem. */
  grafico(x: number, y: number, w: number, h: number, g: EspecGrafico) {
    const id = this.id();
    this.graficos.push(g);
    this.shapes.push(`<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="${id}" name="Gráfico ${id}"/><p:cNvGraphicFramePr/><p:nvPr/>`
      + `</p:nvGraphicFramePr><p:xfrm><a:off x="${emu(x)}" y="${emu(y)}"/><a:ext cx="${emu(w)}" cy="${emu(h)}"/></p:xfrm>`
      + `<a:graphic><a:graphicData uri="${NS.c}"><c:chart xmlns:c="${NS.c}" r:id="rIdGraf${this.graficos.length}"/>`
      + `</a:graphicData></a:graphic></p:graphicFrame>`);
  }

  xml(): string {
    return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>`
      + `<p:sld xmlns:a="${NS.a}" xmlns:r="${NS.r}" xmlns:p="${NS.p}"><p:cSld>`
      + `<p:bg><p:bgPr><a:solidFill><a:srgbClr val="${this.fundo}"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>`
      + `<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>`
      + `<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>`
      + this.shapes.join("")
      + `</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>`;
  }
}

// -----------------------------------------------------------------------------
// Cabeçalho e rodapé (seções 4.5 e 4.6)
// -----------------------------------------------------------------------------
const rotuloLaranja = (t: string, algn: "l" | "r" = "l"): Paragrafo =>
  p(t.toUpperCase(), { b: true, cor: COR.laranja, spc: 300, algn });

export function cabecalho(s: SlideOria, c: { rotulo: string; titulo: string; subtitulo?: string; confidencial?: string }) {
  s.texto(GRADE.x, 38, 560, 16, [rotuloLaranja(c.rotulo)], "t");
  if (c.confidencial) s.texto(GRADE.fim - 300, 38, 300, 16, [rotuloLaranja(c.confidencial, "r")], "t");
  s.fio(GRADE.x, 59, GRADE.w, 0, COR.linha, 0.75);
  s.texto(GRADE.x, 66, GRADE.w, 26, [p(c.titulo, { sz: 21, cor: COR.texto })], "t");
  if (c.subtitulo) s.texto(GRADE.x, 94, GRADE.w, 16, [p(c.subtitulo)], "t");
}

/** Rodapé: régua, nota de fonte (8,5 pt, uma linha), confidencialidade (7,5 pt), assinatura. */
export function rodape(s: SlideOria, fonte?: string) {
  if (fonte !== undefined) {
    s.fio(GRADE.x, 494, GRADE.w, 0, COR.linha, 0.5);
    s.texto(GRADE.x, 497, GRADE.w, 14, [p(fonte, { sz: 8.5 })], "t");
  }
  s.texto(GRADE.x, 518, 640, 12, [p(RODAPE_CONFIDENCIAL, { sz: 7.5 })], "t");
  s.texto(GRADE.fim - 200, 517, 200, 12, [p("ORIA PARTNERS", { sz: 8.5, b: true, cor: COR.marinho, spc: 400, algn: "r" })], "t");
}

// -----------------------------------------------------------------------------
// Componentes (seção 4.7)
// -----------------------------------------------------------------------------
/** Título de seção dentro do slide: 11 pt, negrito, laranja, caixa alta, espaçado. */
export function tituloSecao(s: SlideOria, x: number, y: number, w: number, t: string) {
  s.texto(x, y, w, 16, [rotuloLaranja(t)], "t");
}

/** A. KPI: barra laranja 111,6 × 2,9, número 26 pt, rótulo em caixa alta, explicação até 2 linhas. */
export function kpi(s: SlideOria, x: number, y: number, w: number, k: { valor: string; rotulo: string; explicacao: string }) {
  s.forma(x, y, 111.6, 2.9, COR.laranja);
  s.texto(x, y + 12.9, w, 32, [p(k.valor, { sz: 26, cor: COR.texto })], "t");
  s.texto(x, y + 51.9, w, 16, [p(k.rotulo.toUpperCase(), { b: true, cor: COR.rotuloKpi, spc: 200 })], "t");
  s.texto(x, y + 69, w, 30, [p(k.explicacao, { entrelinha: 13.9 })], "t");
  return y + 99;
}

/** B/D. Cartão (numerado ou de leitura): EEF3EE, barra laranja de 4,3 pt, conteúdo a 20 pt da borda. */
export function cartao(s: SlideOria, x: number, y: number, w: number, h: number,
  c: { numeral?: number; titulo: string; corpo: string | Paragrafo[] }) {
  s.forma(x, y, w, h, COR.cartao);
  s.forma(x, y, 4.3, h, COR.laranja);
  const dx = x + 20;
  const dw = w - 34;
  let ty = y + 12;
  if (c.numeral !== undefined) {
    s.texto(dx, y + 12, dw, 26, [p(String(c.numeral).padStart(2, "0"), { sz: 21, cor: COR.laranja })], "t");
    ty = y + 37;
  } else {
    ty = y + 14;
  }
  s.texto(dx, ty, dw, 16, [p(c.titulo, { sz: 12, b: true, cor: COR.texto })], "t");
  const corpo = typeof c.corpo === "string" ? [p(c.corpo, { entrelinha: 13.9 })] : c.corpo;
  const cy = ty + 26;
  s.texto(dx, cy, dw, Math.max(10, y + h - cy - 10), corpo.map((x2) => ({ ...x2, entrelinha: x2.entrelinha ?? 13.9 })), "t");
}

/** C. Faixa de conclusão: verde na largura útil, barra laranja, 12 pt negrito branco, até 2 linhas. */
export function faixa(s: SlideOria, y: number, texto: string, o: { x?: number; w?: number; h?: number } = {}) {
  const x = o.x ?? GRADE.x;
  const w = o.w ?? GRADE.w;
  const h = o.h ?? 63;
  s.forma(x, y, w, h, COR.verde);
  s.forma(x, y, 4.3, h, COR.laranja);
  s.texto(x + 22, y, w - 40, h, [p(texto, { sz: 12, b: true, cor: COR.branco, entrelinha: 15 })], "ctr");
}

/** E. Lista campo/valor: linhas zebradas (a 1ª sem fundo), campo negrito, valor a `colValor` pt. */
export function campoValor(s: SlideOria, x: number, y: number, w: number, linhas: Array<[string, string]>,
  o: { colValor?: number; h?: number } = {}) {
  const h = o.h ?? 23;
  const cv = o.colValor ?? 140;
  linhas.forEach(([campo, valor], i) => {
    const ly = y + i * h;
    if (i % 2 === 1) s.forma(x, ly, w, h, COR.cartao);
    s.texto(x + 8.6, ly, cv - 12, h, [p(campo, { b: true, cor: COR.texto })], "ctr");
    s.texto(x + cv, ly, w - cv - 8, h, [p(valor)], "ctr");
  });
  return y + linhas.length * h;
}

// ---- F. Tabela ------------------------------------------------------------------
export interface Celula { t: string; b?: boolean }
export interface LinhaTabela { celulas: (Celula | string)[]; destaque?: boolean }
export interface ColunaTabela { titulo: string; w: number; algn?: "l" | "r" | "ctr" }
/** O prompt diz "no máximo ~6 linhas de dados"; o teto duro aqui é 8, para os blocos do crédito. */
export const LIMITE_LINHAS_TABELA = 8;
const ALTURA_LINHA = 28.8;

/** Desenha a tabela e devolve o y final. Lança acima do limite — divida o slide em vez de apertar. */
export function tabela(s: SlideOria, x: number, y: number, colunas: ColunaTabela[], linhas: LinhaTabela[]): number {
  if (linhas.length > LIMITE_LINHAS_TABELA) {
    throw new Error(`pptx-oria: tabela com ${linhas.length} linhas; o limite é ${LIMITE_LINHAS_TABELA} — divida o slide.`);
  }
  const largura = colunas.reduce((t, c) => t + c.w, 0);
  const h = ALTURA_LINHA;
  const pad = 7;
  s.forma(x, y, largura, h, COR.verde);
  let cx = x;
  for (const [i, c] of colunas.entries()) {
    s.texto(cx, y, c.w, h, [p(c.titulo, { b: true, cor: COR.branco, algn: c.algn ?? (i === 0 ? "l" : "r") })], "ctr", pad);
    cx += c.w;
  }
  let cy = y + h;
  for (const [n, l] of linhas.entries()) {
    const fundo: Cor = l.destaque ? COR.verde : n % 2 === 1 ? COR.cartao : COR.branco;
    s.forma(x, cy, largura, h, fundo);
    cx = x;
    for (const [i, c] of colunas.entries()) {
      const bruta = l.celulas[i] ?? "";
      const cel: Celula = typeof bruta === "string" ? { t: bruta } : bruta;
      const cor: Cor = l.destaque ? COR.branco : i === 0 ? COR.texto : COR.apoio;
      s.texto(cx, cy, c.w, h, [p(cel.t, { cor, b: l.destaque || i === 0 || cel.b, algn: c.algn ?? (i === 0 ? "l" : "r") })], "ctr", pad);
      cx += c.w;
    }
    cy += h;
  }
  // Grade fina D6DED6 de 0,45 pt: horizontais e verticais.
  for (let i = 0; i <= linhas.length + 1; i++) s.fio(x, y + i * h, largura, 0, COR.linha, 0.45);
  cx = x;
  for (let i = 0; i <= colunas.length; i++) {
    s.fio(cx, y, 0, cy - y, COR.linha, 0.45);
    cx += colunas[i]?.w ?? 0;
  }
  return cy;
}

/** H. Bloco de texto com subtítulos: pares título 12 pt + corpo 11 pt, ~20 pt entre pares. */
export function blocoDeTexto(s: SlideOria, x: number, y: number, w: number, secao: string, pares: Array<[string, string]>, alturaPar = 62) {
  tituloSecao(s, x, y, w, secao);
  pares.forEach(([t, corpo], i) => {
    const py = y + 26 + i * alturaPar;
    s.texto(x, py, w, 16, [p(t, { sz: 12, b: true, cor: COR.texto })], "t");
    s.texto(x, py + 19, w, alturaPar - 24, [p(corpo, { entrelinha: 13.9 })], "t");
  });
}

/** I. Notas e avisos: abertura em negrito laranja e texto na mesma linha. */
export function notas(s: SlideOria, x: number, y: number, w: number, h: number, itens: Array<{ abertura: string; texto: string }>) {
  s.texto(x, y, w, h, itens.map((n) => ({
    runs: [{ t: `${n.abertura} `, b: true, cor: COR.laranja }, { t: n.texto }], entrelinha: 14.8, depois: 7,
  })), "t");
}

// ---- Capa, divisória, contracapa ---------------------------------------------------
/** Capa (seção 4.8). */
export function capa(s: SlideOria, c: { rotulo: string; titulo: string; descritiva: string; apoio: string; assinatura: string }) {
  s.logo(90, 167, 187);
  s.forma(340, 167, 2, 189, COR.laranja);
  s.texto(374, 180, 540, 16, [rotuloLaranja(c.rotulo)], "t");
  s.texto(374, 204, 540, 40, [p(c.titulo, { sz: 30, cor: COR.texto })], "t");
  s.texto(374, 262, 540, 20, [p(c.descritiva, { sz: 12.5, cor: COR.verde })], "t");
  s.fio(374, 298, 446, 0, COR.linha, 0.75);
  s.texto(374, 309, 540, 16, [p(c.apoio)], "t");
  s.texto(374, 338, 540, 16, [p(c.assinatura.toUpperCase(), { b: true, cor: COR.marinho, spc: 300 })], "t");
  rodape(s);
}

/**
 * Divisória de capítulo — acréscimo do dono ao Teaser (que não as tem). Mesma geometria da capa
 * (barra vertical em x 340), para a abertura de capítulo ler como parte do mesmo sistema.
 */
export function divisoria(s: SlideOria, c: { numero: number; titulo: string; subtitulo: string }) {
  const nn = String(c.numero).padStart(2, "0");
  s.texto(90, 190, 220, 120, [p(nn, { sz: 96, cor: COR.laranja, algn: "ctr" })], "ctr");
  s.forma(340, 167, 2, 189, COR.laranja);
  s.texto(374, 190, 540, 16, [rotuloLaranja(`CAPÍTULO ${nn}`)], "t");
  // Título de capítulo pode ter duas linhas ("Garantias, scorecard e síntese de crédito"): a caixa
  // reserva as duas e a régua fica abaixo delas, para a quebra não riscar o texto.
  s.texto(374, 212, 520, 80, [p(c.titulo, { sz: 30, cor: COR.texto, entrelinha: 36 })], "t");
  s.fio(374, 298, 446, 0, COR.linha, 0.75);
  s.texto(374, 309, 520, 40, [p(c.subtitulo, { sz: 12.5, cor: COR.verde, entrelinha: 16 })], "t");
  rodape(s);
}

export interface Contato { nome: string; telefone: string; email: string }
/** Contracapa (seção 4.9). Contato sem dado fica "[a preencher]". */
export function contracapa(s: SlideOria, contatos: [Contato, Contato]) {
  s.logo(401, 108, 158);
  s.forma(462, 289, 36, 2.5, COR.laranja);
  for (const [i, cx] of [332, 627].entries()) {
    const c = contatos[i];
    s.texto(cx - 140, 324, 280, 22, [p(c.nome, { sz: 16, cor: COR.texto, algn: "ctr" })], "t");
    s.texto(cx - 140, 351, 280, 16, [p(c.telefone, { algn: "ctr" })], "t");
    s.texto(cx - 140, 370, 280, 16, [p(c.email, { algn: "ctr" })], "t");
  }
  s.fio(480, 325, 0, 63, COR.linha, 0.75);
  s.texto(GRADE.x, 442, GRADE.w, 16, [p("SÃO PAULO · DOCUMENTO CONFIDENCIAL", { b: true, cor: COR.marinho, spc: 300, algn: "ctr" })], "t");
  rodape(s);
}

// -----------------------------------------------------------------------------
// O pacote
// -----------------------------------------------------------------------------
const NS = {
  a: "http://schemas.openxmlformats.org/drawingml/2006/main",
  r: "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
  p: "http://schemas.openxmlformats.org/presentationml/2006/main",
  c: "http://schemas.openxmlformats.org/drawingml/2006/chart",
  rel: "http://schemas.openxmlformats.org/package/2006/relationships",
} as const;
const TR = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
const CT = "application/vnd.openxmlformats-officedocument";
const XML_DECL = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>`;
const GRUPO_VAZIO = `<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>`;

/** O tema leva a paleta e a Verdana — é o que o PowerPoint oferece a quem editar depois. */
function temaXml(): string {
  const cor = (n: string, v: string) => `<a:${n}><a:srgbClr val="${v}"/></a:${n}>`;
  const fill = `<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>`;
  const ln = `<a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>`;
  const fonte = `<a:latin typeface="${FONTE}"/><a:ea typeface="${FONTE}"/><a:cs typeface="${FONTE}"/>`;
  return XML_DECL + `<a:theme xmlns:a="${NS.a}" name="Oria"><a:themeElements><a:clrScheme name="Oria">`
    + cor("dk1", COR.texto) + cor("lt1", COR.branco) + cor("dk2", COR.marinho) + cor("lt2", COR.fundoCapa)
    + cor("accent1", COR.verde) + cor("accent2", COR.laranja) + cor("accent3", COR.eixo)
    + cor("accent4", COR.apoio) + cor("accent5", COR.linha) + cor("accent6", COR.cartao)
    + cor("hlink", COR.verde) + cor("folHlink", COR.apoio) + `</a:clrScheme>`
    + `<a:fontScheme name="Oria"><a:majorFont>${fonte}</a:majorFont><a:minorFont>${fonte}</a:minorFont></a:fontScheme>`
    + `<a:fmtScheme name="Oria"><a:fillStyleLst>${fill}${fill}${fill}</a:fillStyleLst>`
    + `<a:lnStyleLst>${ln}${ln}${ln}</a:lnStyleLst>`
    + `<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle>`
    + `<a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>`
    + `<a:bgFillStyleLst>${fill}${fill}${fill}</a:bgFillStyleLst></a:fmtScheme></a:themeElements>`
    + `<a:objectDefaults/><a:extraClrSchemeLst/></a:theme>`;
}

function mestreXml(): string {
  const nivel = `<a:lvl1pPr><a:defRPr sz="1100"><a:latin typeface="${FONTE}"/></a:defRPr></a:lvl1pPr>`;
  return XML_DECL + `<p:sldMaster xmlns:a="${NS.a}" xmlns:r="${NS.r}" xmlns:p="${NS.p}"><p:cSld>`
    + `<p:bg><p:bgPr><a:solidFill><a:srgbClr val="${COR.branco}"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>`
    + `<p:spTree>${GRUPO_VAZIO}</p:spTree></p:cSld>`
    + `<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" `
    + `accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>`
    + `<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>`
    + `<p:txStyles><p:titleStyle>${nivel}</p:titleStyle><p:bodyStyle>${nivel}</p:bodyStyle><p:otherStyle>${nivel}</p:otherStyle></p:txStyles>`
    + `</p:sldMaster>`;
}

const layoutXml = () => XML_DECL
  + `<p:sldLayout xmlns:a="${NS.a}" xmlns:r="${NS.r}" xmlns:p="${NS.p}" type="blank" preserve="1">`
  + `<p:cSld name="Em branco"><p:spTree>${GRUPO_VAZIO}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>`;

const rels = (itens: Array<[string, string, string]>) => XML_DECL + `<Relationships xmlns="${NS.rel}">`
  + itens.map(([id, tipo, alvo]) => `<Relationship Id="${id}" Type="${tipo}" Target="${alvo}"/>`).join("")
  + `</Relationships>`;

export class DeckOria {
  readonly slides: SlideOria[] = [];

  constructor(readonly titulo: string) {}

  novo(fundo: Cor = COR.branco): SlideOria {
    const s = new SlideOria(fundo);
    this.slides.push(s);
    return s;
  }

  async gerar(agora: Date = new Date()): Promise<Buffer> {
    if (this.slides.length === 0) throw new Error("pptx-oria: deck sem slides.");
    const zip = new JSZip();
    const n = this.slides.length;
    // Gráficos numerados no deck inteiro: chart1.xml, chart2.xml…
    const graficosPorSlide: number[][] = [];
    let nGraf = 0;
    for (const s of this.slides) graficosPorSlide.push(s.graficos.map(() => ++nGraf));
    zip.file("[Content_Types].xml", XML_DECL
      + `<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">`
      + `<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>`
      + `<Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/>`
      + `<Override PartName="/ppt/presentation.xml" ContentType="${CT}.presentationml.presentation.main+xml"/>`
      + `<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="${CT}.presentationml.slideMaster+xml"/>`
      + `<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="${CT}.presentationml.slideLayout+xml"/>`
      + `<Override PartName="/ppt/theme/theme1.xml" ContentType="${CT}.theme+xml"/>`
      + `<Override PartName="/ppt/presProps.xml" ContentType="${CT}.presentationml.presProps+xml"/>`
      + `<Override PartName="/ppt/tableStyles.xml" ContentType="${CT}.presentationml.tableStyles+xml"/>`
      + `<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>`
      + `<Override PartName="/docProps/app.xml" ContentType="${CT}.extended-properties+xml"/>`
      + this.slides.map((_, i) => `<Override PartName="/ppt/slides/slide${i + 1}.xml" ContentType="${CT}.presentationml.slide+xml"/>`).join("")
      + Array.from({ length: nGraf }, (_, i) => `<Override PartName="/ppt/charts/chart${i + 1}.xml" ContentType="${CT}.drawingml.chart+xml"/>`).join("")
      + `</Types>`);
    zip.file("_rels/.rels", rels([
      ["rId1", `${TR}/officeDocument`, "ppt/presentation.xml"],
      ["rId2", "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties", "docProps/core.xml"],
      ["rId3", `${TR}/extended-properties`, "docProps/app.xml"],
    ]));
    zip.file("docProps/core.xml", XML_DECL
      + `<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" `
      + `xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" `
      + `xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>${esc(this.titulo)}</dc:title>`
      + `<dc:creator>Oria Partners</dc:creator><dcterms:created xsi:type="dcterms:W3CDTF">${agora.toISOString().slice(0, 19)}Z</dcterms:created>`
      + `</cp:coreProperties>`);
    zip.file("docProps/app.xml", XML_DECL
      + `<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">`
      + `<Application>Oria Partners — portal</Application><Slides>${n}</Slides></Properties>`);
    zip.file("ppt/presentation.xml", XML_DECL
      + `<p:presentation xmlns:a="${NS.a}" xmlns:r="${NS.r}" xmlns:p="${NS.p}" saveSubsetFonts="1">`
      + `<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>`
      + this.slides.map((_, i) => `<p:sldId id="${256 + i}" r:id="rId${10 + i}"/>`).join("")
      + `</p:sldIdLst><p:sldSz cx="${emu(TELA.w)}" cy="${emu(TELA.h)}"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>`);
    zip.file("ppt/_rels/presentation.xml.rels", rels([
      ["rId1", `${TR}/slideMaster`, "slideMasters/slideMaster1.xml"],
      ["rId2", `${TR}/theme`, "theme/theme1.xml"],
      ["rId3", `${TR}/presProps`, "presProps.xml"],
      ["rId4", `${TR}/tableStyles`, "tableStyles.xml"],
      ...this.slides.map((_, i): [string, string, string] => [`rId${10 + i}`, `${TR}/slide`, `slides/slide${i + 1}.xml`]),
    ]));
    zip.file("ppt/presProps.xml", XML_DECL + `<p:presentationPr xmlns:a="${NS.a}" xmlns:r="${NS.r}" xmlns:p="${NS.p}"/>`);
    zip.file("ppt/tableStyles.xml", XML_DECL
      + `<a:tblStyleLst xmlns:a="${NS.a}" def="{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"/>`);
    zip.file("ppt/theme/theme1.xml", temaXml());
    zip.file("ppt/slideMasters/slideMaster1.xml", mestreXml());
    zip.file("ppt/slideMasters/_rels/slideMaster1.xml.rels", rels([
      ["rId1", `${TR}/slideLayout`, "../slideLayouts/slideLayout1.xml"],
      ["rId2", `${TR}/theme`, "../theme/theme1.xml"],
    ]));
    zip.file("ppt/slideLayouts/slideLayout1.xml", layoutXml());
    zip.file("ppt/slideLayouts/_rels/slideLayout1.xml.rels", rels([
      ["rId1", `${TR}/slideMaster`, "../slideMasters/slideMaster1.xml"],
    ]));
    if (this.slides.some((s) => s.usaLogo)) {
      zip.file("ppt/media/logo-oria.png", LOGO_ORIA_PNG_BASE64, { base64: true });
    }
    for (const [i, s] of this.slides.entries()) {
      zip.file(`ppt/slides/slide${i + 1}.xml`, s.xml());
      const nums = graficosPorSlide[i];
      zip.file(`ppt/slides/_rels/slide${i + 1}.xml.rels`, rels([
        ["rId1", `${TR}/slideLayout`, "../slideLayouts/slideLayout1.xml"],
        ...(s.usaLogo ? [["rIdLogo", `${TR}/image`, "../media/logo-oria.png"] as [string, string, string]] : []),
        ...nums.map((g, k): [string, string, string] => [`rIdGraf${k + 1}`, `${TR}/chart`, `../charts/chart${g}.xml`]),
      ]));
      s.graficos.forEach((g, k) => zip.file(`ppt/charts/chart${nums[k]}.xml`, graficoXml(g)));
    }
    return zip.generateAsync({ type: "nodebuffer", compression: "DEFLATE" });
  }
}
