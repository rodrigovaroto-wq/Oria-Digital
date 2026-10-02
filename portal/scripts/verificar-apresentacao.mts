/**
 * Verificação da APRESENTAÇÃO DE CRÉDITO (.pptx) — roda com
 * `./node_modules/.bin/tsx scripts/verificar-apresentacao.mts`.
 *
 * O deck vai ao cliente e ao credor. Os modos de falha que este arquivo cobre são os do
 * Prompt-Mestre Oria v3 (FASE 5, QA) e os deste projeto, e TODOS são silenciosos — o PowerPoint
 * abre o arquivo e ele parece certo:
 *
 *  1. NÚMERO: o deck mostra o número que o DOCUMENTO imprime (gabarito do book Vertentes: receita
 *     143.380/106.580, ativo 121.198/95.780) e, nas contas de giro, a soma SEM o cabeçalho de grupo.
 *     Sem os subtotais informados que o export detecta, "Clientes" de 2024 sai 62,0 num ativo
 *     circulante de 67,9 (medido ao construir esta fatia) — o assert 1c é o que pega isso.
 *  2. AUSÊNCIA: DRE sem linha de depreciação faz o EBITDA sair `n/d`, nunca igual ao EBIT e nunca
 *     zero (regra 1). E a amarração que não fecha APARECE como "NÃO FECHA".
 *  3. PADRÃO VISUAL, por varredura do XML gerado: corpo ≥ 11 pt em todo run e `endParaRPr`, só
 *     Bodoni MT e Source Sans Pro, só cores da paleta (nenhum `000000`), EMU inteiro, nenhum
 *     `p:style`, `<a:effectLst/>` em todo `spPr`, `<a:buNone/>` ou bullet em todo parágrafo,
 *     nenhum placeholder, manchete ≤ 75 caracteres, tag de natureza em toda coluna de período.
 *  4. CONTROLE POSITIVO DAS VARREDURAS (`.claude/memory/verificador-sem-controle-positivo.md`): cada
 *     varredura do item 3 é rodada contra um XML com o defeito plantado, e TEM de acusar. Uma
 *     varredura que "não achou nada" só vale se provadamente acha o que procura.
 */
import { readFileSync } from "node:fs";
import JSZip from "jszip";
import { buildExportWorkbook, entradaDoModeloDoWorkbook, type DocumentoParaExport } from "../src/lib/export.ts";
import type { CampoExtraido } from "../src/lib/types.ts";
import type { EntradaModeloInstitucional } from "../src/lib/modelo-institucional.ts";
import { entradaModeloDaFixture } from "./lib/modelo-da-fixture.mts";
import { montarBaseCredito } from "../src/lib/apresentacao/montar-base.ts";
import { construirDeckCredito } from "../src/lib/apresentacao/deck-credito.ts";
import { DeckOria, PALETA, FONTES_PERMITIDAS, p, tabela, COR } from "../src/lib/apresentacao/pptx-oria.ts";

let falhas = 0;
let passou = 0;
function ok(cond: boolean, nome: string, detalhe?: string) {
  if (cond) { passou += 1; console.log(`  ok    ${nome}`); return; }
  falhas += 1;
  console.error(`  FALHOU: ${nome}${detalhe ? ` — ${detalhe}` : ""}`);
}

const fixture = JSON.parse(readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8")) as {
  documentos: DocumentoParaExport[]; campos: CampoExtraido[];
};
const agora = new Date("2026-10-02T12:00:00Z");

/** O caminho da ROTA: workbook completo → entrada do modelo COM subtotais → base → deck. */
async function deckDe(entrada: EntradaModeloInstitucional) {
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos, agora, modeloInstitucional: entrada,
  });
  const ent = entradaDoModeloDoWorkbook(wb);
  if (!ent) throw new Error("o workbook não montou o modelo institucional — a fixture mudou?");
  const saida = construirDeckCredito(montarBaseCredito(ent, fixture.documentos), agora);
  const buf = await saida.deck.gerar(agora);
  const zip = await JSZip.loadAsync(buf);
  const nomes = Object.keys(zip.files).filter((n) => /^ppt\/slides\/slide\d+\.xml$/.test(n))
    .sort((a, b) => Number(/\d+/.exec(a)![0]) - Number(/\d+/.exec(b)![0]));
  const slides = await Promise.all(nomes.map((n) => zip.file(n)!.async("string")));
  return { saida, zip, slides };
}
const textos = (xml: string) => [...xml.matchAll(/<a:t>([^<]*)<\/a:t>/g)].map((m) => m[1]);
const slideCom = (slides: string[], marca: string) => slides.find((x) => textos(x).some((t) => t.includes(marca))) ?? "";
/** A linha da tabela cujo rótulo é `rotulo`: os textos que vêm depois dele no slide. */
function linha(xml: string, rotulo: string, n: number): string[] {
  const t = textos(xml);
  const i = t.indexOf(rotulo);
  return i < 0 ? [] : t.slice(i + 1, i + 1 + n);
}

// ---- As varreduras (item 3). Cada uma devolve a lista de violações. ----------------------------
const varreduras: Record<string, (xml: string) => string[]> = {
  "corpo ≥ 11 pt": (x) => [...x.matchAll(/<a:(?:rPr|endParaRPr|defRPr)[^>]*\ssz="(\d+)"/g)]
    .filter((m) => Number(m[1]) < 1100).map((m) => `sz=${m[1]}`),
  "só Bodoni MT e Source Sans Pro": (x) => [...x.matchAll(/<a:(?:latin|cs|ea|buFont) typeface="([^"]*)"/g)]
    .filter((m) => !FONTES_PERMITIDAS.has(m[1])).map((m) => m[1]),
  "só cores da paleta": (x) => [...x.matchAll(/<a:srgbClr val="([0-9A-Fa-f]{6})"/g)]
    .filter((m) => !PALETA.has(m[1].toUpperCase())).map((m) => m[1]),
  "EMU inteiro": (x) => [...x.matchAll(/\s(?:x|y|cx|cy)="([^"]*)"/g)]
    .filter((m) => !/^-?\d+$/.test(m[1])).map((m) => m[1]),
  "sem p:style (sem sombra herdada)": (x) => (x.includes("<p:style") ? ["p:style"] : []),
  "effectLst vazio em todo spPr": (x) => [...x.matchAll(/<p:spPr>[\s\S]*?<\/p:spPr>/g)]
    .filter((m) => !m[0].includes("<a:effectLst/>")).map(() => "spPr sem effectLst"),
  "buNone ou bullet em todo parágrafo": (x) => [...x.matchAll(/<a:pPr[^>]*>[\s\S]*?<\/a:pPr>|<a:pPr[^>]*\/>/g)]
    .filter((m) => !m[0].includes("<a:buNone/>") && !m[0].includes("<a:buChar")).map(() => "pPr sem bullet declarado"),
  "endParaRPr pt-BR em todo parágrafo": (x) => [...x.matchAll(/<a:p>[\s\S]*?<\/a:p>/g)]
    .filter((m) => !/<a:endParaRPr lang="pt-BR"/.test(m[0])).map(() => "parágrafo sem endParaRPr pt-BR"),
  "nenhum placeholder": (x) => textos(x).filter((t) => /\[[^\]]*\]|⚠|CONFIRMAR|undefined|NaN|\bnull\b|Infinity/.test(t)),
  "manchete ≤ 75 caracteres": (x) => [...x.matchAll(/<a:r><a:rPr[^>]*sz="2200"[^>]*>[\s\S]*?<a:latin typeface="Bodoni MT"\/>[\s\S]*?<a:t>([^<]*)<\/a:t>/g)]
    .map((m) => m[1].replace(/&amp;/g, "&")).filter((t) => t.length > 75 && !/^\d{2}$/.test(t)),
};

console.log("--- 4. controle positivo: cada varredura ACUSA o defeito plantado ---");
{
  const plantado: Record<string, string> = {
    "corpo ≥ 11 pt": `<a:rPr lang="pt-BR" sz="1000"/>`,
    "só Bodoni MT e Source Sans Pro": `<a:latin typeface="Calibri"/>`,
    "só cores da paleta": `<a:srgbClr val="000000"/>`,
    "EMU inteiro": `<a:off x="12.5" y="0"/>`,
    "sem p:style (sem sombra herdada)": `<p:style></p:style>`,
    "effectLst vazio em todo spPr": `<p:spPr><a:xfrm/></p:spPr>`,
    "buNone ou bullet em todo parágrafo": `<a:pPr algn="l"><a:lnSpc/></a:pPr>`,
    "endParaRPr pt-BR em todo parágrafo": `<a:p><a:r><a:t>x</a:t></a:r></a:p>`,
    "nenhum placeholder": `<a:t>[NOME_EMPRESA]</a:t>`,
    "manchete ≤ 75 caracteres": `<a:r><a:rPr lang="pt-BR" sz="2200"><a:latin typeface="Bodoni MT"/></a:rPr><a:t>${"x".repeat(80)}</a:t></a:r>`,
  };
  for (const [nome, f] of Object.entries(varreduras)) {
    ok(f(plantado[nome]).length > 0, `a varredura "${nome}" acusa o defeito plantado`);
  }
  let lancou = false;
  try { p("corpo pequeno", { sz: 10 }); new DeckOria("x").novo().texto(0, 0, 1, 1, [p("x", { sz: 10 })]); } catch { lancou = true; }
  ok(lancou, "a biblioteca RECUSA corpo abaixo de 11 pt (o prompt: reduza o texto, nunca o corpo)");
  lancou = false;
  try {
    tabela(new DeckOria("x").novo(), 0, 0, [{ titulo: "a", w: 1 }], Array.from({ length: 15 }, () => ({ celulas: ["x"] })));
  } catch { lancou = true; }
  ok(lancou, "a biblioteca RECUSA tabela com mais de 14 linhas de corpo");
  ok(PALETA.has(COR.laranja) && !PALETA.has("000000"), "a paleta é a do prompt e não contém preto puro");
}

console.log("--- 1. o deck mostra o número do documento (book Vertentes) ---");
const base = await deckDe(entradaModeloDaFixture(fixture, agora));
{
  const { slides, zip } = base;
  ok(slides.length >= 12, `o deck tem os slides do módulo (${slides.length})`);
  const x1 = slideCom(slides, "X.1 · RESULTADO");
  ok(JSON.stringify(linha(x1, "Receita líquida", 2)) === JSON.stringify(["143,4", "106,6"]),
    "(1a) X.1: receita líquida 143,4 / 106,6 — o total impresso na DRE", JSON.stringify(linha(x1, "Receita líquida", 2)));
  const x2 = slideCom(slides, "X.2 · ESTRUTURA DE CAPITAL E PRAZOS");
  ok(JSON.stringify(linha(x2, "Ativo total", 2)) === JSON.stringify(["121,2", "95,8"]),
    "(1b) X.2: ativo total 121,2 / 95,8 — o total impresso no balanço", JSON.stringify(linha(x2, "Ativo total", 2)));
  const xi = slideCom(slides, "XI.2 · NCG E PRAZOS");
  ok(JSON.stringify(linha(xi, "Clientes", 2)) === JSON.stringify(["32,0", "24,3"]),
    "(1c) XI.2: clientes SEM o cabeçalho de grupo \"Contas a Receber\" (32,0, não 62,0)", JSON.stringify(linha(xi, "Clientes", 2)));
  ok(JSON.stringify(linha(x1, "Lucro líquido", 2)) === JSON.stringify(["(3,0)", "(17,9)"]),
    "(1d) X.1: prejuízo entre parênteses, como o prompt manda", JSON.stringify(linha(x1, "Lucro líquido", 2)));
  ok(/<a:t>\(17,9\)<\/a:t>/.test(x1) && x1.includes(`val="${COR.negativoSobreVerde}"`),
    "(1e) negativo na linha de total sai em FFC9B5 (B6482F não tem contraste sobre o verde-escuro)");

  console.log("--- 3. padrão visual, varrendo o XML gerado ---");
  for (const [nome, f] of Object.entries(varreduras)) {
    const v = slides.flatMap((x, i) => f(x).map((e) => `slide ${i + 1}: ${e}`));
    ok(v.length === 0, `todos os slides: ${nome}`, v.slice(0, 3).join("; "));
  }
  const tema = await zip.file("ppt/theme/theme1.xml")!.async("string");
  ok(varreduras["só cores da paleta"](tema).length === 0 && varreduras["só Bodoni MT e Source Sans Pro"](tema.replace(/typeface=""/g, "")).length === 0,
    "o tema também só tem paleta e as duas fontes");
  const financeiros = slides.filter((x) => textos(x).some((t) => /NÃO AUDITADO|AUDITADO/.test(t)) && x.includes(">R$ MM<"));
  const semTag = financeiros.filter((x) => {
    const t = textos(x);
    return t.some((s, i) => /^(19|20)\d{2}$/.test(s) && !/^\((A|R|B|G)\)$/.test(t[i + 1] ?? ""));
  });
  ok(financeiros.length >= 4 && semTag.length === 0,
    `toda coluna de período carrega a tag de natureza (${financeiros.length} slides financeiros)`);
  const ct = await zip.file("[Content_Types].xml")!.async("string");
  ok(slides.every((_, i) => ct.includes(`/ppt/slides/slide${i + 1}.xml`)) && zip.file("ppt/media/logo-oria.png") !== null,
    "o pacote declara todo slide e leva o logo oficial");
  ok(base.saida.amarracoes.some((a) => a.veredito === "nao_conferivel")
    && slideCom(slides, "NOTAS E FONTES").includes("Não conferível"),
    "amarração que não pôde rodar aparece como \"Não conferível\", não some da lista (regra 7)");
}

console.log("--- 2. ausência e divergência aparecem como tal ---");
{
  const entrada = entradaModeloDaFixture(fixture, agora);
  const semDA = { ...entrada, linhas: entrada.linhas.filter((l) => !/deprecia|amortiza|exaust/i.test(l.chave)) };
  const { slides } = await deckDe(semDA);
  const x1 = slideCom(slides, "X.1 · RESULTADO");
  const ebitda = linha(x1, "EBITDA", 2);
  const ebit = linha(x1, "EBIT", 2);
  ok(JSON.stringify(ebitda) === JSON.stringify(["n/d", "n/d"]),
    "(2a) DRE sem D&A: EBITDA sai n/d — nem zero, nem igual ao EBIT", `EBITDA ${JSON.stringify(ebitda)} · EBIT ${JSON.stringify(ebit)}`);
  ok(textos(slideCom(slides, "POR QUE HÁ N/D")).some((t) => /depreciação/.test(t)),
    "(2b) o slide de notas diz o motivo do n/d (a DRE não traz depreciação)");

  // Ativo informado adulterado em 2025: Ativo ≠ Passivo + PL tem de aparecer.
  const adulterada = {
    ...entrada,
    linhas: entrada.linhas.map((l) => /^total do ativo$/i.test(l.chave.trim()) || /^ativo total$/i.test(l.chave.trim())
      ? { ...l, valores: { ...l.valores, "2025": (l.valores["2025"] ?? 0) + 5000 } } : l),
  };
  const div = await deckDe(adulterada);
  const nota = slideCom(div.slides, "NOTAS E FONTES");
  ok(div.saida.amarracoes.some((a) => a.numero === 2 && a.ano === 2025 && a.veredito === "diverge") && nota.includes("NÃO FECHA"),
    "(2c) ativo ≠ passivo + PL: a amarração aparece como \"NÃO FECHA\" no slide de notas");
}

console.log(`\n${passou} asserts passaram, ${falhas} falharam`);
if (falhas > 0) process.exit(1);
console.log("APRESENTAÇÃO OK — número do documento, ausência dita, padrão visual varrido com controle positivo");
