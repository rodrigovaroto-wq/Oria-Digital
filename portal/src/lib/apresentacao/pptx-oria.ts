// O PADRÃO VISUAL ORIA 2026 EM .PPTX — a biblioteca que os geradores de apresentação usam.
//
// POR QUE OOXML ESCRITO À MÃO, e não `python-pptx` como o Prompt-Mestre v3 manda. O prompt pede
// `python-pptx` (e veta `pptxgenjs`) por três razões que ele mesmo declara: coordenada EMU sempre
// inteira, nenhuma sombra herdada de `p:style`, e controle de cada `bodyPr`/`endParaRPr`. Python
// não roda na função da Vercel onde o portal vive, e uma dependência nova para gerar slide é o
// degrau 5 da escada que este repositório recusa. O caminho é o MESMO de `xlsx-graficos.ts`: um
// .pptx é um ZIP de XML, e o JSZip já está no lock. Escrevendo o XML, as três razões viram
// garantia por construção em vez de cuidado:
//
//   • `emu()` arredonda TODA coordenada para inteiro (float dispara o reparo do PowerPoint);
//   • nenhum shape tem `p:style`, e todo `spPr` leva `<a:effectLst/>` vazio (sem sombra);
//   • todo parágrafo leva `<a:buNone/>` ou o bullet laranja, e `endParaRPr` em pt-BR com a fonte
//     do parágrafo — digitação posterior não volta a Calibri.
//
// E DUAS REGRAS DO PROMPT QUE AQUI SÃO TIPO, NÃO REVISÃO:
//   • a PALETA: `Cor` é a lista fechada da tabela "Paleta" do prompt. Cor fora dela não compila.
//   • o CORPO MÍNIMO DE 11 pt: `run()` LANÇA abaixo de 11. O prompt diz "se não couber em 11 pt,
//     reduza o texto ou divida o slide; nunca reduza o corpo" — então quem tenta reduzir quebra.
// O `verificar-apresentacao.mts` varre o XML gerado pelas duas de novo, porque tipo protege quem
// chama esta biblioteca e a varredura protege contra quem um dia escrever XML por fora dela.
import JSZip from "jszip";
import { LOGO_ORIA_PNG_BASE64, LOGO_ORIA_PX } from "./logo-oria";

// -----------------------------------------------------------------------------
// Paleta — exatamente a do Prompt-Mestre v3, seção "Paleta". Nada fora daqui.
// -----------------------------------------------------------------------------
export const COR = {
  laranja: "F04600",
  verdeEscuro: "2E5B45",
  verdeClaro: "EEF3EE",
  sage: "E7EEE8",
  grafite: "404040",
  grafiteMedio: "4A4A4A",
  cinza: "707070",
  navy: "16263B",
  regua: "D6DED6",
  branco: "FFFFFF",
  corpoSobreVerde: "E8EFE9",
  secundarioSobreVerde: "CFE0D4",
  rotuloSobreVerde: "FFB38A",
  destaqueLinha: "FCEADF",
  neutroGrafico: "B7C4BA",
  negativo: "B6482F",
  negativoSobreVerde: "FFC9B5",
} as const;
export type Cor = (typeof COR)[keyof typeof COR];
export const PALETA: ReadonlySet<string> = new Set(Object.values(COR));

export const FONTE_SERIFA = "Bodoni MT";
export const FONTE_SANS = "Source Sans Pro";
export const FONTES_PERMITIDAS: ReadonlySet<string> = new Set([FONTE_SERIFA, FONTE_SANS]);
/** O piso do prompt, em pontos. Abaixo disso `run()` lança. */
export const CORPO_MINIMO_PT = 11;

// -----------------------------------------------------------------------------
// Geometria. Polegadas na API (é a unidade do prompt); EMU inteiro no XML.
// -----------------------------------------------------------------------------
const EMU_POR_POL = 914400;
export const emu = (pol: number): number => Math.round(pol * EMU_POR_POL);
export const SLIDE = { w: 13.333, h: 7.5 } as const;
/** A grade vertical dos slides de conteúdo (tabela "Grade vertical" do prompt). */
export const GRADE = {
  margem: 0.85,
  util: 11.63,
  conteudoTopo: 1.5,
  conteudoBase: 6.52,
  gapCard: 0.2,
  gapPainel: 0.3,
  gapLinha: 0.15,
} as const;

export const RODAPE_CONFIDENCIAL =
  "CONFIDENCIAL – Para uso exclusivo do destinatário. Não reproduzir ou distribuir sem autorização.";

const esc = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
    // Byte de controle em rótulo vindo de PDF já quebrou o export (8d378b0); XML 1.0 não o aceita.
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "");

// -----------------------------------------------------------------------------
// Texto
// -----------------------------------------------------------------------------
export interface Run {
  t: string;
  /** corpo em pontos; padrão 11 */
  sz?: number;
  b?: boolean;
  i?: boolean;
  cor?: Cor;
  serifa?: boolean;
  /** espaçamento entre letras em centésimos de ponto (o `spc` do prompt: 220 = 2,2 pt) */
  spc?: number;
}

export interface Paragrafo {
  runs: Run[];
  algn?: "l" | "ctr" | "r";
  bullet?: boolean;
  /** espaço depois, em pontos */
  spcAft?: number;
  /** entrelinha em % (115 = 1,15) */
  lnSpc?: number;
}

/** Atalho: um parágrafo de um run só. */
export const p = (t: string, estilo: Omit<Run, "t"> & Omit<Paragrafo, "runs"> = {}): Paragrafo => {
  const { algn, bullet, spcAft, lnSpc, ...run } = estilo;
  return { runs: [{ t, ...run }], algn, bullet, spcAft, lnSpc };
};

function rPr(r: Run, tag: "a:rPr" | "a:endParaRPr"): string {
  const sz = r.sz ?? CORPO_MINIMO_PT;
  if (sz < CORPO_MINIMO_PT) {
    throw new Error(`pptx-oria: corpo ${sz} pt abaixo do mínimo de ${CORPO_MINIMO_PT} pt em "${r.t.slice(0, 40)}" `
      + "— o Prompt-Mestre manda reduzir o texto ou dividir o slide, nunca o corpo.");
  }
  const fonte = r.serifa ? FONTE_SERIFA : FONTE_SANS;
  const attrs = [`lang="pt-BR"`, `sz="${Math.round(sz * 100)}"`, `b="${r.b ? 1 : 0}"`, `i="${r.i ? 1 : 0}"`,
    ...(r.spc ? [`spc="${Math.round(r.spc)}"`] : []), `dirty="0"`].join(" ");
  return `<${tag} ${attrs}><a:solidFill><a:srgbClr val="${r.cor ?? COR.cinza}"/></a:solidFill>`
    + `<a:latin typeface="${fonte}"/><a:cs typeface="${fonte}"/></${tag}>`;
}

function paragrafoXml(par: Paragrafo): string {
  const lnSpc = par.lnSpc ?? 100;
  const marL = par.bullet ? ` marL="171450" indent="-171450"` : "";
  const bullet = par.bullet
    ? `<a:buClr><a:srgbClr val="${COR.laranja}"/></a:buClr><a:buFont typeface="${FONTE_SANS}"/><a:buChar char="•"/>`
    : "<a:buNone/>";
  const pPr = `<a:pPr algn="${par.algn ?? "l"}"${marL}><a:lnSpc><a:spcPct val="${lnSpc * 1000}"/></a:lnSpc>`
    + `<a:spcBef><a:spcPts val="0"/></a:spcBef><a:spcAft><a:spcPts val="${Math.round((par.spcAft ?? 0) * 100)}"/></a:spcAft>`
    + `${bullet}</a:pPr>`;
  const runs = par.runs.map((r) => `<a:r>${rPr(r, "a:rPr")}<a:t>${esc(r.t)}</a:t></a:r>`).join("");
  const ultimo = par.runs[par.runs.length - 1] ?? { t: "" };
  return `<a:p>${pPr}${runs}${rPr({ ...ultimo, t: "" }, "a:endParaRPr")}</a:p>`;
}

// -----------------------------------------------------------------------------
// Slide
// -----------------------------------------------------------------------------
type Ancora = "t" | "ctr" | "b";

export class SlideOria {
  private shapes: string[] = [];
  private proximoId = 2;
  usaLogo = false;

  constructor(readonly fundo: Cor = COR.branco) {}

  private id() { return this.proximoId++; }

  private spPr(x: number, y: number, w: number, h: number, geom: string, fill?: Cor, linha?: { cor: Cor; pt: number }) {
    const preenchimento = fill ? `<a:solidFill><a:srgbClr val="${fill}"/></a:solidFill>` : "<a:noFill/>";
    const ln = linha
      ? `<a:ln w="${Math.round(linha.pt * 12700)}"><a:solidFill><a:srgbClr val="${linha.cor}"/></a:solidFill></a:ln>`
      : "<a:ln><a:noFill/></a:ln>";
    return `<p:spPr><a:xfrm><a:off x="${emu(x)}" y="${emu(y)}"/><a:ext cx="${emu(w)}" cy="${emu(h)}"/></a:xfrm>`
      + `<a:prstGeom prst="${geom}"><a:avLst/></a:prstGeom>${preenchimento}${ln}<a:effectLst/></p:spPr>`;
  }

  /** Retângulo (ou elipse) sólido, sem borda e sem sombra. */
  forma(x: number, y: number, w: number, h: number, fill: Cor | undefined,
    opts: { geom?: "rect" | "ellipse"; contorno?: { cor: Cor; pt: number }; texto?: Paragrafo[]; ancora?: Ancora } = {}) {
    const id = this.id();
    const corpo = opts.texto ? this.txBody(opts.texto, opts.ancora ?? "ctr", 0) : "";
    this.shapes.push(`<p:sp><p:nvSpPr><p:cNvPr id="${id}" name="Forma ${id}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>`
      + this.spPr(x, y, w, h, opts.geom ?? "rect", fill, opts.contorno) + corpo + `</p:sp>`);
  }

  private txBody(pars: Paragrafo[], ancora: Ancora, insPol: number) {
    const ins = emu(insPol);
    return `<p:txBody><a:bodyPr wrap="square" lIns="${ins}" tIns="0" rIns="${ins}" bIns="0" anchor="${ancora}" rtlCol="0">`
      + `<a:noAutofit/></a:bodyPr><a:lstStyle/>${pars.map(paragrafoXml).join("")}</p:txBody>`;
  }

  /** Caixa de texto: inset zero (o prompt), âncora explícita, sem autoajuste. */
  texto(x: number, y: number, w: number, h: number, pars: Paragrafo[], ancora: Ancora = "t", insPol = 0) {
    const id = this.id();
    this.shapes.push(`<p:sp><p:nvSpPr><p:cNvPr id="${id}" name="Texto ${id}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>`
      + this.spPr(x, y, w, h, "rect") + this.txBody(pars, ancora, insPol) + `</p:sp>`);
  }

  /** Fio horizontal ou vertical. */
  fio(x: number, y: number, w: number, h: number, cor: Cor = COR.regua, pt = 0.75) {
    const id = this.id();
    this.shapes.push(`<p:cxnSp><p:nvCxnSpPr><p:cNvPr id="${id}" name="Fio ${id}"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr>`
      + `<p:spPr><a:xfrm><a:off x="${emu(x)}" y="${emu(y)}"/><a:ext cx="${emu(w)}" cy="${emu(h)}"/></a:xfrm>`
      + `<a:prstGeom prst="line"><a:avLst/></a:prstGeom><a:ln w="${Math.round(pt * 12700)}"><a:solidFill>`
      + `<a:srgbClr val="${cor}"/></a:solidFill></a:ln><a:effectLst/></p:spPr></p:cxnSp>`);
  }

  /** O logo oficial, quadrado de `lado` polegadas, preservando a proporção do arquivo. */
  logo(x: number, y: number, lado: number) {
    this.usaLogo = true;
    const id = this.id();
    const h = lado * (LOGO_ORIA_PX.altura / LOGO_ORIA_PX.largura);
    this.shapes.push(`<p:pic><p:nvPicPr><p:cNvPr id="${id}" name="Logo Oria"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/>`
      + `</p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed="rIdLogo"/><a:stretch><a:fillRect/></a:stretch>`
      + `</p:blipFill><p:spPr><a:xfrm><a:off x="${emu(x)}" y="${emu(y)}"/><a:ext cx="${emu(lado)}" cy="${emu(h)}"/></a:xfrm>`
      + `<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:effectLst/></p:spPr></p:pic>`);
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
// Componentes do padrão (seções "Componentes" e "Biblioteca de layouts" do prompt)
// -----------------------------------------------------------------------------
const kicker = (t: string, algn: "l" | "r" = "l", cor: Cor = COR.laranja): Paragrafo =>
  p(t.toUpperCase(), { b: true, cor, spc: 220, algn });

/** Chrome dos slides de conteúdo: kickers, fio, manchete, fio e linha de fontes, rodapé, assinatura. */
export function chrome(s: SlideOria, c: { kickerEsq: string; kickerDir: string; manchete: string; fontes: string }) {
  const { margem, util } = GRADE;
  s.texto(margem, 0.4, 6.6, 0.3, [kicker(c.kickerEsq)], "b");
  s.texto(6.9, 0.4, 5.58, 0.3, [kicker(c.kickerDir, "r")], "b");
  s.fio(margem, 0.76, util, 0);
  s.texto(margem, 0.86, util, 0.5, [p(c.manchete, { serifa: true, sz: 22, cor: COR.grafite })], "ctr");
  s.fio(margem, 6.62, util, 0);
  s.texto(margem, 6.68, util, 0.26, [p(c.fontes)], "t");
  assinatura(s);
}

function assinatura(s: SlideOria) {
  s.texto(GRADE.margem, 7.02, 8.6, 0.26, [p(RODAPE_CONFIDENCIAL)], "t");
  s.texto(10.13, 7.02, 2.35, 0.26, [p("ORIA PARTNERS", { b: true, cor: COR.navy, spc: 250, algn: "r" })], "t");
}

/** Card padrão (verde-claro + barra laranja) ou de destaque (verde-escuro, sem barra). */
export function card(s: SlideOria, x: number, y: number, w: number, h: number,
  c: { rotulo: string; titulo?: string; corpo: Paragrafo[]; destaque?: boolean }) {
  const destaque = !!c.destaque;
  s.forma(x, y, w, h, destaque ? COR.verdeEscuro : COR.verdeClaro);
  const esq = destaque ? 0.2 : 0.26;
  if (!destaque) s.forma(x, y, 0.06, h, COR.laranja);
  const pars: Paragrafo[] = [
    p(c.rotulo.toUpperCase(), { b: true, spc: 120, cor: destaque ? COR.rotuloSobreVerde : COR.laranja, spcAft: 6 }),
    ...(c.titulo ? [p(c.titulo, { b: true, sz: 13, cor: destaque ? COR.branco : COR.grafite, spcAft: 6 })] : []),
    ...c.corpo.map((par) => ({
      ...par, lnSpc: par.lnSpc ?? 115, spcAft: par.spcAft ?? 6,
      runs: par.runs.map((r) => ({ ...r, cor: r.cor ?? (destaque ? COR.corpoSobreVerde : COR.cinza) })),
    })),
  ];
  s.texto(x + esq, y + 0.2, w - esq - 0.2, h - 0.4, pars, "t");
}

/** KPI do Layout B: régua laranja, valor Bodoni 26, label e descritor. Sem caixa de fundo. */
export function kpi(s: SlideOria, x: number, y: number, w: number,
  k: { valor: string; label: string; descritor: string; destaque?: boolean }) {
  s.forma(x, y, 1.55, 0.04, COR.laranja);
  s.texto(x, y + 0.12, w, 0.48, [p(k.valor, { serifa: true, sz: 26, cor: k.destaque ? COR.laranja : COR.grafite })], "t");
  s.texto(x, y + 0.62, w, 0.26, [p(k.label.toUpperCase(), { b: true, cor: COR.grafiteMedio, spc: 80 })], "t");
  s.texto(x, y + 0.88, w, 0.5, [p(k.descritor, { lnSpc: 115 })], "t");
}

// ---- Tabela por retângulos (Regras técnicas, item 6) --------------------------
export interface Celula {
  t: string;
  /** valor negativo: vai em `B6482F` (ou `FFC9B5` na linha de total) */
  negativo?: boolean;
  b?: boolean;
  i?: boolean;
}
export interface LinhaTabela {
  celulas: (Celula | string)[];
  tipo?: "normal" | "total" | "destaque";
  /** linha de duas alturas (0,46 in) */
  dupla?: boolean;
}
export interface ColunaTabela {
  titulo: string;
  /** segunda linha do cabeçalho — a tag de natureza `(A)`/`(B)`/`(G)`, em `FFB38A` */
  tag?: string;
  w: number;
  algn?: "l" | "r" | "ctr";
}
export const LIMITE_LINHAS_TABELA = 14;

/** Desenha a tabela e devolve o y onde ela termina. Lança acima de 14 linhas de corpo (o prompt). */
export function tabela(s: SlideOria, x: number, y: number, colunas: ColunaTabela[], linhas: LinhaTabela[]): number {
  if (linhas.length > LIMITE_LINHAS_TABELA) {
    throw new Error(`pptx-oria: tabela com ${linhas.length} linhas de corpo; o limite é ${LIMITE_LINHAS_TABELA} — divida em (1/2), (2/2).`);
  }
  const largura = colunas.reduce((t, c) => t + c.w, 0);
  const temTag = colunas.some((c) => c.tag);
  const hCab = temTag ? 0.5 : 0.36;
  const pad = 0.06;
  s.forma(x, y, largura, hCab, COR.verdeEscuro);
  let cx = x;
  for (const [i, c] of colunas.entries()) {
    const algn = c.algn ?? (i === 0 ? "l" : "r");
    const pars = [p(c.titulo.toUpperCase(), { b: true, cor: COR.branco, algn })];
    if (c.tag) pars.push(p(c.tag, { b: true, cor: COR.rotuloSobreVerde, algn }));
    s.texto(cx, y, c.w, hCab, pars, "ctr", pad);
    cx += c.w;
  }
  let cy = y + hCab;
  for (const [n, l] of linhas.entries()) {
    const h = l.dupla ? 0.46 : 0.3;
    const total = l.tipo === "total";
    const fundo: Cor = total ? COR.verdeEscuro : l.tipo === "destaque" ? COR.destaqueLinha
      : n % 2 === 0 ? COR.branco : COR.verdeClaro;
    s.forma(x, cy, largura, h, fundo);
    cx = x;
    for (const [i, c] of colunas.entries()) {
      const bruta = l.celulas[i] ?? "";
      const cel: Celula = typeof bruta === "string" ? { t: bruta } : bruta;
      const algn = c.algn ?? (i === 0 ? "l" : "r");
      const cor: Cor = total
        ? (cel.negativo ? COR.negativoSobreVerde : COR.branco)
        : cel.negativo ? COR.negativo : i === 0 ? COR.grafite : COR.cinza;
      s.texto(cx, cy, c.w, h, [p(cel.t, { cor, b: total || cel.b, i: cel.i, algn })], "ctr", pad);
      cx += c.w;
    }
    s.fio(x, cy + h, largura, 0, COR.regua, 0.5);
    cy += h;
  }
  return cy;
}

// ---- Layouts de abertura e fechamento -----------------------------------------
/** Layout A — capa. */
export function capa(s: SlideOria, c: { kicker: string; titulo: string; subtitulo: string; meta: string }) {
  s.logo(1.25, 2.32, 2.6);
  s.forma(4.72, 2.32, 0.03, 2.62, COR.laranja);
  s.texto(5.2, 2.4, 7.3, 0.3, [kicker(c.kicker)], "b");
  s.texto(5.2, 2.8, 7.3, 0.9, [p(c.titulo, { serifa: true, sz: 32, cor: COR.grafite })], "ctr");
  s.texto(5.2, 3.75, 7.3, 0.5, [p(c.subtitulo, { sz: 15, cor: COR.verdeEscuro })], "t");
  s.fio(5.2, 4.35, 7.0, 0);
  // A linha de meta leva o nome do cliente E da entidade, que vêm do banco com qualquer tamanho:
  // reserva duas linhas em vez de deixar a segunda colar na assinatura.
  s.texto(5.2, 4.45, 7.3, 0.42, [p(c.meta, { lnSpc: 110 })], "t");
  s.texto(5.2, 4.92, 7.3, 0.26, [p("ASSESSORIA EM REESTRUTURAÇÃO E FINANÇAS CORPORATIVAS", { b: true, cor: COR.navy })], "t");
}

/** Layout G — divisória de capítulo. */
export function divisoria(s: SlideOria, c: { numero: number; titulo: string; subtitulo: string }) {
  const nn = String(c.numero).padStart(2, "0");
  s.texto(1.0, 2.0, 3.4, 2.6, [p(nn, { serifa: true, sz: 120, cor: COR.laranja, algn: "ctr" })], "ctr");
  s.forma(4.72, 2.32, 0.03, 2.62, COR.laranja);
  s.texto(5.2, 2.5, 7.3, 0.3, [kicker(`CAPÍTULO ${nn}`)], "b");
  s.texto(5.2, 2.9, 7.3, 0.9, [p(c.titulo, { serifa: true, sz: 32, cor: COR.grafite })], "ctr");
  s.fio(5.2, 3.9, 7.0, 0);
  s.texto(5.2, 4.0, 7.3, 0.7, [p(c.subtitulo, { sz: 15, cor: COR.verdeEscuro, lnSpc: 115 })], "t");
  assinatura(s);
}

/** Layout A′ — contracapa. Os contatos são os do prompt (seção da FASE 2, slide 9). */
export function contracapa(s: SlideOria) {
  s.logo((SLIDE.w - 2.2) / 2, 1.75, 2.2);
  s.forma((SLIDE.w - 1.1) / 2, 4.22, 1.1, 0.03, COR.laranja);
  const meio = SLIDE.w / 2;
  s.texto(meio - 3.2, 4.5, 3.0, 0.4, [p("Enzo Pierobom", { serifa: true, sz: 15, cor: COR.grafite, algn: "r" })], "b");
  s.texto(meio - 3.2, 4.9, 3.0, 0.3, [p("11 99250-0682", { algn: "r" })], "t");
  s.fio(meio, 4.5, 0, 0.75);
  s.texto(meio + 0.2, 4.5, 3.0, 0.4, [p("Luis Felipe Farina", { serifa: true, sz: 15, cor: COR.grafite })], "b");
  s.texto(meio + 0.2, 4.9, 3.0, 0.3, [p("11 96310-5011")], "t");
  s.texto(GRADE.margem, 5.7, GRADE.util, 0.3,
    [p("SÃO PAULO  ·  DOCUMENTO CONFIDENCIAL", { b: true, cor: COR.navy, spc: 220, algn: "ctr" })], "t");
  assinatura(s);
}

// -----------------------------------------------------------------------------
// O pacote
// -----------------------------------------------------------------------------
const NS = {
  a: "http://schemas.openxmlformats.org/drawingml/2006/main",
  r: "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
  p: "http://schemas.openxmlformats.org/presentationml/2006/main",
  rel: "http://schemas.openxmlformats.org/package/2006/relationships",
} as const;
const TR = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
const CT = "application/vnd.openxmlformats-officedocument";
const XML_DECL = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>`;
const GRUPO_VAZIO = `<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>`;

/** O tema leva a paleta Oria e as duas fontes — é o que o PowerPoint oferece a quem editar depois. */
function temaXml(): string {
  const cor = (n: string, v: string) => `<a:${n}><a:srgbClr val="${v}"/></a:${n}>`;
  const fill = `<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>`;
  const ln = `<a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>`;
  return XML_DECL + `<a:theme xmlns:a="${NS.a}" name="Oria 2026"><a:themeElements><a:clrScheme name="Oria 2026">`
    + cor("dk1", COR.grafite) + cor("lt1", COR.branco) + cor("dk2", COR.navy) + cor("lt2", COR.sage)
    + cor("accent1", COR.laranja) + cor("accent2", COR.verdeEscuro) + cor("accent3", COR.neutroGrafico)
    + cor("accent4", COR.cinza) + cor("accent5", COR.negativo) + cor("accent6", COR.verdeClaro)
    + cor("hlink", COR.verdeEscuro) + cor("folHlink", COR.cinza) + `</a:clrScheme>`
    + `<a:fontScheme name="Oria 2026"><a:majorFont><a:latin typeface="${FONTE_SERIFA}"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>`
    + `<a:minorFont><a:latin typeface="${FONTE_SANS}"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme>`
    + `<a:fmtScheme name="Oria 2026"><a:fillStyleLst>${fill}${fill}${fill}</a:fillStyleLst>`
    + `<a:lnStyleLst>${ln}${ln}${ln}</a:lnStyleLst>`
    + `<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle>`
    + `<a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>`
    + `<a:bgFillStyleLst>${fill}${fill}${fill}</a:bgFillStyleLst></a:fmtScheme></a:themeElements>`
    + `<a:objectDefaults/><a:extraClrSchemeLst/></a:theme>`;
}

function mestreXml(): string {
  const nivel = `<a:lvl1pPr><a:defRPr sz="1100"><a:latin typeface="${FONTE_SANS}"/></a:defRPr></a:lvl1pPr>`;
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
      + `</p:sldIdLst><p:sldSz cx="12192000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>`);
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
      zip.file(`ppt/slides/_rels/slide${i + 1}.xml.rels`, rels([
        ["rId1", `${TR}/slideLayout`, "../slideLayouts/slideLayout1.xml"],
        ...(s.usaLogo ? [["rIdLogo", `${TR}/image`, "../media/logo-oria.png"] as [string, string, string]] : []),
      ]));
    }
    return zip.generateAsync({ type: "nodebuffer", compression: "DEFLATE" });
  }
}
