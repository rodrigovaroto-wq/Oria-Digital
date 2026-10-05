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
 *     Verdana (Prompt Padrão Oria), só cores da paleta (nenhum `000000`), EMU inteiro, nenhum
 *     `p:style`, `<a:effectLst/>` em todo `spPr`, `<a:buNone/>` ou bullet em todo parágrafo,
 *     nenhum placeholder além de "[a preencher]", título ≤ 70 caracteres, tag de natureza em toda coluna de período.
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
import { montarBaseCredito, correnteDoBalancete } from "../src/lib/apresentacao/montar-base.ts";
import { amarracoes, dividaDoMapa, type BaseCredito } from "../src/lib/apresentacao/base-credito.ts";
import type { GrandezaCredito, HistoricoCredito } from "../src/lib/modelo-institucional.ts";
import { construirDeckCredito, SemDadoParaApresentar } from "../src/lib/apresentacao/deck-credito.ts";
import type { LinhaModelo } from "../src/lib/modelo-institucional.ts";
import { projecaoDoModelo } from "../src/lib/apresentacao/projecao.ts";
import { CHAVES_APRESENTACAO } from "../src/lib/apresentacao/campos.ts";
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
  // 11 pt no corpo; abaixo disso só os dois tamanhos que o Prompt Padrão fixa no rodapé.
  "corpo ≥ 11 pt (8,5 e 7,5 só no rodapé)": (x) => [...x.matchAll(/<a:(?:rPr|endParaRPr|defRPr)[^>]*\ssz="(\d+)"/g)]
    .filter((m) => Number(m[1]) < 1100 && m[1] !== "850" && m[1] !== "750").map((m) => `sz=${m[1]}`),
  "só Verdana": (x) => [...x.matchAll(/<a:(?:latin|cs|ea|buFont) typeface="([^"]*)"/g)]
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
  // "[a preencher]" é a lacuna DECLARADA (Prompt Padrão, item 3); qualquer outro colchete é sobra.
  "nenhum placeholder": (x) => textos(x).map((t) => t.replace(/\[a preencher\]/g, ""))
    .filter((t) => /\[[^\]]*\]|⚠|CONFIRMAR|undefined|NaN|\bnull\b|Infinity/.test(t)),
  "título ≤ 70 caracteres": (x) => [...x.matchAll(/<a:r><a:rPr[^>]*sz="2100"[^>]*>[\s\S]*?<a:t>([^<]*)<\/a:t>/g)]
    .map((m) => m[1].replace(/&amp;/g, "&")).filter((t) => t.length > 70),
};

console.log("--- 4. controle positivo: cada varredura ACUSA o defeito plantado ---");
{
  const plantado: Record<string, string> = {
    "corpo ≥ 11 pt (8,5 e 7,5 só no rodapé)": `<a:rPr lang="pt-BR" sz="1000"/>`,
    "só Verdana": `<a:latin typeface="Calibri"/>`,
    "só cores da paleta": `<a:srgbClr val="000000"/>`,
    "EMU inteiro": `<a:off x="12.5" y="0"/>`,
    "sem p:style (sem sombra herdada)": `<p:style></p:style>`,
    "effectLst vazio em todo spPr": `<p:spPr><a:xfrm/></p:spPr>`,
    "buNone ou bullet em todo parágrafo": `<a:pPr algn="l"><a:lnSpc/></a:pPr>`,
    "endParaRPr pt-BR em todo parágrafo": `<a:p><a:r><a:t>x</a:t></a:r></a:p>`,
    "nenhum placeholder": `<a:t>[NOME_EMPRESA]</a:t>`,
    "título ≤ 70 caracteres": `<a:r><a:rPr lang="pt-BR" sz="2100"><a:latin typeface="Verdana"/></a:rPr><a:t>${"x".repeat(80)}</a:t></a:r>`,
  };
  for (const [nome, f] of Object.entries(varreduras)) {
    ok(f(plantado[nome]).length > 0, `a varredura "${nome}" acusa o defeito plantado`);
  }
  let lancou = false;
  try { const sl = new DeckOria("x").novo(); sl.texto(0, 0, 1, 1, [p("x", { sz: 10 })]); sl.xml(); } catch { lancou = true; }
  ok(lancou, "a biblioteca RECUSA corpo abaixo de 11 pt (o prompt: reduza o texto, nunca o corpo)");
  lancou = false;
  try {
    tabela(new DeckOria("x").novo(), 0, 0, [{ titulo: "a", w: 1 }], Array.from({ length: 9 }, () => ({ celulas: ["x"] })));
  } catch { lancou = true; }
  ok(lancou, "a biblioteca RECUSA tabela com mais de 8 linhas");
  ok(PALETA.has(COR.laranja) && PALETA.has(COR.eixo) && !PALETA.has("000000") && !PALETA.has("B6482F"), "a paleta é a do Prompt Padrão (com o 888888 do eixo, sem preto nem vermelho)");
}

console.log("--- 1. o deck mostra o número do documento (book Vertentes) ---");
const base = await deckDe(entradaModeloDaFixture(fixture, agora));
{
  const { slides, zip } = base;
  ok(slides.length >= 12, `o deck tem os slides do módulo (${slides.length})`);
  const x1 = slideCom(slides, "X.1 · RESULTADO");
  const xii = slideCom(slides, "XII · COMPARATIVO ENTRE EXERCÍCIOS");
  ok(JSON.stringify(linha(xii, "Receita líquida", 2)) === JSON.stringify(["143,4", "106,6"]),
    "(1a) XII: receita líquida 143,4 / 106,6 — o total impresso na DRE", JSON.stringify(linha(xii, "Receita líquida", 2)));
  const x2 = slideCom(slides, "X.2 · ESTRUTURA DE CAPITAL");
  ok(JSON.stringify(linha(x2, "Ativo total", 2)) === JSON.stringify(["121,2", "95,8"]),
    "(1b) X.2: ativo total 121,2 / 95,8 — o total impresso no balanço", JSON.stringify(linha(x2, "Ativo total", 2)));
  const xi = slideCom(slides, "XI · CAPITAL DE GIRO");
  ok(JSON.stringify(linha(xi, "Clientes", 2)) === JSON.stringify(["32,0", "24,3"]),
    "(1c) XI: clientes SEM o cabeçalho de grupo \"Contas a Receber\" (32,0, não 62,0)", JSON.stringify(linha(xi, "Clientes", 2)));
  ok(JSON.stringify(linha(x1, "Lucro líquido", 2)) === JSON.stringify(["(3,0)", "(17,9)"]),
    "(1d) X.1: prejuízo entre parênteses, como o prompt manda", JSON.stringify(linha(x1, "Lucro líquido", 2)));
  const graficos = await Promise.all(Object.keys(zip.files).filter((n) => /^ppt\/charts\/chart\d+\.xml$/.test(n))
    .map((n) => zip.file(n)!.async("string")));
  ok(graficos.some((g) => g.includes("<c:barChart>") && g.includes("<c:v>143.4</c:v>") && g.includes("<c:v>106.6</c:v>"))
    && graficos.some((g) => g.includes("<c:doughnutChart>")),
    "(1e) os gráficos são nativos: colunas de receita com os números do documento, e a rosca da dívida");
  const vGraf = graficos.flatMap((g) => [...varreduras["corpo ≥ 11 pt (8,5 e 7,5 só no rodapé)"](g), ...varreduras["só cores da paleta"](g),
    ...varreduras["só Verdana"](g), ...(g.includes("<c:majorGridlines") ? ["linha de grade"] : [])]);
  ok(graficos.length > 0 && vGraf.length === 0, `gráficos: 11 pt, paleta, Verdana e sem linha de grade (${graficos.length})`, vGraf.slice(0, 3).join("; "));

  console.log("--- 3. padrão visual, varrendo o XML gerado ---");
  for (const [nome, f] of Object.entries(varreduras)) {
    const v = slides.flatMap((x, i) => f(x).map((e) => `slide ${i + 1}: ${e}`));
    ok(v.length === 0, `todos os slides: ${nome}`, v.slice(0, 3).join("; "));
  }
  const tema = await zip.file("ppt/theme/theme1.xml")!.async("string");
  ok(varreduras["só cores da paleta"](tema).length === 0 && varreduras["só Verdana"](tema).length === 0,
    "o tema também só tem paleta e Verdana");
  // Cabeçalho de período é "2024 (B)": todo ano sozinho num cabeçalho de tabela financeira é falha.
  const financeiros = slides.filter((x) => x.includes(">R$ mi<"));
  const semTag = financeiros.filter((x) => textos(x).some((t) => /^(19|20)\d{2}$/.test(t)));
  ok(financeiros.length >= 4 && semTag.length === 0,
    `toda coluna de período carrega a tag de natureza (${financeiros.length} slides financeiros)`);
  const ct = await zip.file("[Content_Types].xml")!.async("string");
  ok(slides.every((_, i) => ct.includes(`/ppt/slides/slide${i + 1}.xml`)) && zip.file("ppt/media/logo-oria.png") !== null,
    "o pacote declara todo slide e leva o logo oficial");
  ok(base.saida.amarracoes.some((a) => a.veredito === "nao_conferivel")
    && slideCom(slides, "NOTAS E AVISOS · AMARRAÇÕES").includes("Não conferível"),
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
  ok(textos(slideCom(slides, "O que ficou a preencher e o motivo de cada n/d")).some((t) => /depreciação/.test(t)),
    "(2b) o slide de notas diz o motivo do n/d (a DRE não traz depreciação)");

  // Ativo informado adulterado em 2025: Ativo ≠ Passivo + PL tem de aparecer.
  const adulterada = {
    ...entrada,
    linhas: entrada.linhas.map((l) => /^total do ativo$/i.test(l.chave.trim()) || /^ativo total$/i.test(l.chave.trim())
      ? { ...l, valores: { ...l.valores, "2025": (l.valores["2025"] ?? 0) + 5000 } } : l),
  };
  const div = await deckDe(adulterada);
  const nota = div.slides.filter((x) => textos(x).some((t) => t.startsWith("NOTAS E AVISOS · AMARRAÇÕES"))).join("");
  ok(div.saida.amarracoes.some((a) => a.numero === 2 && a.ano === 2025 && a.veredito === "diverge") && nota.includes("NÃO FECHA"),
    "(2c) ativo ≠ passivo + PL: a amarração aparece como \"NÃO FECHA\" no slide de notas");
}

console.log("--- 5. o que a revisão independente achou (cada um reproduzido antes da correção) ---");
{
  // (5a) Caso com unidade dominante "milhao": o modelo converte tudo para REAIS (`fatorDeEscala`), e
  // o deck tem de dividir por 1.000.000 — antes ele dividia por 1 e a receita saía 143.380.000.000,0.
  const entrada = entradaModeloDaFixture(fixture, agora);
  const { slides } = await deckDe({ ...entrada, unidade: "milhao" });
  ok(JSON.stringify(linha(slideCom(slides, "XII · COMPARATIVO ENTRE EXERCÍCIOS"), "Receita líquida", 2)) === JSON.stringify(["143,4", "106,6"]),
    "(5a) unidade \"milhao\": a receita continua 143,4 / 106,6 em R$ MM",
    JSON.stringify(linha(slideCom(slides, "XII · COMPARATIVO ENTRE EXERCÍCIOS"), "Receita líquida", 2)));
}
/** Uma base à mão, de um ou dois exercícios — para os casos que o book Vertentes não tem. */
function baseSintetica(valores: Partial<Record<GrandezaCredito, number[]>>): BaseCredito {
  const anos = [2024, 2025];
  const todas: GrandezaCredito[] = ["receita_liquida", "lucro_bruto", "ebit", "depreciacao", "lucro_liquido", "custos", "sga",
    "ativo_total", "ativo_circulante", "passivo_circulante", "passivo_nao_circulante", "patrimonio_liquido", "caixa",
    "clientes", "estoques", "fornecedores", "divida_bancos_cp", "divida_bancos_lp", "divida_outras_cp", "divida_outras_lp", "imobilizado"];
  const grandezas = Object.fromEntries(todas.map((k) => [k, Object.fromEntries(anos.map((a, i) => {
    const v = valores[k]?.[i];
    return [a, v === undefined ? { v: null, origem: `${k}: ausente` } : { v, origem: `${k} sintético` }];
  }))])) as HistoricoCredito["grandezas"];
  return {
    cliente: "Sintético", entidade: "SINTÉTICA LTDA", unidade: "R$ mil",
    periodos: anos.map((ano) => ({ ano, natureza: "B" as const, motivoNatureza: "sintético" })),
    documentos: [], historico: { unidade: "R$ mil", escala: "milhar", anos, avisosDeEscala: [], grandezas, operacoes: [], totalDoMapa: {} },
  };
}
async function slidesDe(b: BaseCredito) {
  const zip = await JSZip.loadAsync(await construirDeckCredito(b, agora).deck.gerar(agora));
  const nomes = Object.keys(zip.files).filter((n) => /^ppt\/slides\/slide\d+\.xml$/.test(n));
  return Promise.all(nomes.map((n) => zip.file(n)!.async("string")));
}
const executivo = (slides: string[]) => textos(slideCom(slides, "SUMÁRIO EXECUTIVO")).join(" | ");
{
  // DFL/EBITDA = 1,0x (dívida 20.000, caixa 10.000, EBITDA 10.000): ABAIXO da faixa, não "dentro".
  const comum = { receita_liquida: [100000, 100000], ebit: [8000, 8000], depreciacao: [2000, 2000] };
  const baixa = executivo(await slidesDe(baseSintetica({ ...comum, divida_bancos_cp: [20000, 20000], caixa: [10000, 10000] })));
  ok(/abaixo da faixa/.test(baixa) && !/dentro da faixa|faixa-alvo:/.test(baixa),
    "(5b) DFL/EBITDA de 1,0x sai \"abaixo da faixa\", nunca \"dentro da faixa\"", baixa.slice(0, 200));
  const liquida = executivo(await slidesDe(baseSintetica({ ...comum, divida_bancos_cp: [5000, 5000], caixa: [20000, 20000] })));
  ok(/Caixa supera a dívida/.test(liquida) && !/faixa-alvo/.test(liquida),
    "(5c) com caixa líquido o slide não se contradiz com \"faixa-alvo\"", liquida.slice(0, 200));
}
{
  // (5d) NCG negativa (clientes + estoques < fornecedores): a razão é n.s., não n/d.
  const sl = await slidesDe(baseSintetica({ receita_liquida: [100000, 100000], custos: [80000, 80000],
    clientes: [5000, 5000], estoques: [5000, 5000], fornecedores: [20000, 20000], divida_bancos_cp: [8000, 8000] }));
  const xi = slideCom(sl, "XI · CAPITAL DE GIRO");
  ok(JSON.stringify(linha(xi, "Dívida bancária CP / NCG", 2)) === JSON.stringify(["n.s.", "n.s."]) && /não positiva/.test(textos(xi).join(" ")),
    "(5d) NCG negativa: \"Dívida bancária CP / NCG\" é n.s. e a manchete diz NCG não positiva",
    JSON.stringify(linha(xi, "Dívida bancária CP / NCG", 2)));
}
{
  // (5e) amarração sem insumo não "fecha": base só com receita.
  const am = amarracoes(baseSintetica({ receita_liquida: [100000, 100000] }));
  const falsoOk = am.filter((a) => a.veredito === "ok" || a.veredito === "por_construcao");
  ok(falsoOk.length === 0, "(5e) sem insumo, nenhuma amarração sai \"Fecha\" nem \"Por definição\"",
    falsoOk.map((a) => `${a.numero}/${a.ano}`).join(", "));
}
{
  // (5f) receita +30%, EBITDA +10%: "cresceu menos", não "piorou".
  const sl = await slidesDe(baseSintetica({ receita_liquida: [100000, 130000], ebit: [8000, 8800], depreciacao: [2000, 2200] }));
  const xii = textos(slideCom(sl, "XII · COMPARATIVO ENTRE EXERCÍCIOS")).join(" ");
  ok(/cresceu menos que a receita/.test(xii) && !/piorou/.test(xii), "(5f) EBITDA +10% com receita +30%: \"cresceu menos\", não \"piorou\"");
}
{
  // (5g) EBIT da âncora que já desconta o resultado financeiro (DRE no formato antigo): a cascata não
  // o reproduz, e a amarração 10 tem de dizer "NÃO FECHA" — senão o EBITDA sai subestimado calado.
  const am = amarracoes(baseSintetica({ receita_liquida: [100000, 100000], custos: [70000, 70000], lucro_bruto: [30000, 30000],
    sga: [20000, 20000], ebit: [4000, 4000] }));
  ok(am.filter((a) => a.numero === 10 && a.veredito === "diverge").length === 2,
    "(5g) EBIT informado ≠ lucro bruto − despesas operacionais: a amarração 10 diverge");
}

console.log("--- 6. setores e formatos diferentes (testes com mandatos de outro perfil, 02/10/2026) ---");
{
  // Empresa de SERVIÇOS: DRE só com contas (sem "Receita líquida" nem "EBIT" impressos) e balanço
  // sem estoque. É o formato de DRE de balancete; antes desta fatia o deck inteiro saía sem
  // resultado, com todas as contas extraídas. Os números são sintéticos e só afirmam a aritmética.
  const L = (secao: string, chave: string, v: Record<string, number>, papel: LinhaModelo["papel"] = "conta", doc = "DRE"): LinhaModelo =>
    ({ secao_canonica: secao, chave, rotulo_norm: chave.toLowerCase(), papel, unidade: "milhar", moeda: "BRL", documentos: [doc], valores: v });
  const balanco = [
    L("ativo_circulante", "Caixa e bancos", { 2024: 5000, 2025: 3000 }, "conta", "BALANCO"),
    L("ativo_circulante", "Clientes", { 2024: 20000, 2025: 22000 }, "conta", "BALANCO"),
    L("ativo_circulante", "Total do ativo", { 2024: 55000, 2025: 54000 }, "subtotal", "BALANCO"),
    L("passivo_circulante", "Fornecedores", { 2024: 8000, 2025: 9000 }, "conta", "BALANCO"),
    L("patrimonio_liquido", "Patrimônio líquido", { 2024: 37000, 2025: 33000 }, "subtotal", "BALANCO"),
  ];
  const dre = [
    L("receita_bruta", "Receita de prestação de serviços", { 2024: 100000, 2025: 110000 }),
    L("receita_bruta", "ISS sobre serviços", { 2024: -5000, 2025: -5500 }),
    L("custos", "Custo dos serviços prestados", { 2024: -60000, 2025: -66000 }),
    L("despesas_operacionais", "Despesas administrativas", { 2024: -20000, 2025: -22000 }),
    L("despesas_operacionais", "Depreciação e amortização", { 2024: -3000, 2025: -3000 }),
  ];
  const ent = (linhas: LinhaModelo[]) => ({
    caso: { nome: "Serviços", produto: "reestruturacao" }, agora, entidade: "SERVIÇOS LTDA", setor: null,
    anosHistoricos: [2024, 2025], anosProjetados: [2026], stressPct: 0.2, caixaMinimo: 0, aliquotaTributos: 0.34,
    linhas, premissas: [], vinculos: [], macro: [], unidade: "R$ mil" }) as EntradaModeloInstitucional;
  const b = montarBaseCredito(ent([...balanco, ...dre]), []);
  const sl = await slidesDe(b);
  ok(JSON.stringify(linha(slideCom(sl, "XII · COMPARATIVO ENTRE EXERCÍCIOS"), "Receita líquida", 2)) === JSON.stringify(["95,0", "104,5"])
    && JSON.stringify(linha(slideCom(sl, "XII · COMPARATIVO ENTRE EXERCÍCIOS"), "EBIT", 2)) === JSON.stringify(["12,0", "13,5"]),
  "(6a) DRE sem totais impressos: receita e EBIT saem da cascata (receita − ISS; − custo − despesas)",
  JSON.stringify(linha(slideCom(sl, "XII · COMPARATIVO ENTRE EXERCÍCIOS"), "Receita líquida", 2)));
  const am = amarracoes(b).filter((a) => a.numero === 9 || a.numero === 10);
  ok(am.length > 0 && am.every((a) => a.veredito !== "ok"),
    "(6b) total calculado não conta como conferência: as amarrações 9 e 10 não dizem \"Fecha\" contra si mesmas");
  ok(textos(slideCom(sl, "X.3 · PRAZOS E CICLO FINANCEIRO")).some((t) => /balanço sem conta de estoque/.test(t)),
    "(6c) balanço sem estoque: o título diz PMR e PMP e que não há estoque, em vez de \"não mensurável\"");
  const semDed = montarBaseCredito(ent([...balanco, ...dre.filter((l) => !/ISS/.test(l.chave))]), []);
  ok(semDed.historico.grandezas.receita_liquida[2025].v === null,
    "(6f) sem dedução classificada, a receita bruta NÃO é publicada como líquida (n/d)");
  ok(textos(slideCom(sl, "X.1 · RESULTADO")).some((t) => /calculados pela Oria \(sem total no documento\)/.test(t)),
    "(6g) total calculado pela cascata vem marcado na nota de fonte do slide");
  const holding = montarBaseCredito(ent([...balanco,
    L("resultado_financeiro", "Resultado de equivalência patrimonial", { 2024: 900, 2025: 1200 }),
    L("receita_bruta", "x", {}), L("custos", "Lucro líquido do exercício", { 2024: 900, 2025: 1200 }, "subtotal")]), []);
  const slH = await slidesDe(holding);
  ok(slH.some((x) => textos(x).some((t) => t.startsWith("X.1 · RESULTADO"))),
    "(6h) holding com DRE de equivalência (lucro líquido, sem receita) mantém o capítulo de resultado");
  // #251 (decisão do dono): "capital de giro" no passivo é dívida financeira, com ou sem credor no
  // rótulo. A apresentação herda pelo classificador único — e este assert prova que herdou.
  const comCG = montarBaseCredito(ent([...balanco, ...dre,
    L("passivo_circulante", "CAPITAL DE GIRO - CP", { 2024: 4000, 2025: 6000 }, "conta", "BALANCO")]), []);
  ok(comCG.historico.grandezas.divida_bancos_cp[2025].v === 6000,
    "(6i) \"CAPITAL DE GIRO - CP\" no passivo entra como dívida bancária de curto prazo (decisão do #251)",
    String(comCG.historico.grandezas.divida_bancos_cp[2025].v));
  let recusou = false;
  try { construirDeckCredito(montarBaseCredito(ent([L("passivo_circulante", "Fornecedores", { 2025: 1 }, "conta", "BALANCO")]), []), agora); }
  catch (e) { recusou = e instanceof SemDadoParaApresentar; }
  ok(recusou, "(6d) entidade sem receita, ativo nem PL (o \"GRUPO\" consolidado sem demonstração): o deck é RECUSADO, não sai vazio");
}
{
  const entrada = entradaModeloDaFixture(fixture, agora);
  const adulterada = { ...entrada, linhas: entrada.linhas.map((l) => /^total do ativo$/i.test(l.chave.trim()) || /^ativo total$/i.test(l.chave.trim())
    ? { ...l, valores: { ...l.valores, "2025": (l.valores["2025"] ?? 0) + 5000 } } : l) };
  const { slides } = await deckDe(adulterada);
  ok(/amarração\(ões\) não fecham/.test(executivo(slides)),
    "(6e) amarração que não fecha aparece na faixa do sumário executivo, não só nas notas");
}

console.log("--- 7. os campos preenchidos (0205) substituem o \"[a preencher]\" — e só eles ---");
{
  const entrada = entradaModeloDaFixture(fixture, agora);
  const wb = buildExportWorkbook({ caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos, agora, modeloInstitucional: entrada });
  const notas = ["7", "6", "5", "4", "5", "3"];
  const base7 = montarBaseCredito(entradaDoModeloDoWorkbook(wb)!, fixture.documentos, [
    { chave: "ii2.cartao1", valor: "Norma XYZ de 2026 muda o licenciamento", fonte: "analista" },
    { chave: "contracapa.contato1.nome", valor: "Fulano de Tal", fonte: null },
    ...notas.map((n, i) => ({ chave: `xvii.nota${i + 1}`, valor: n, fonte: "analista" })),
  ]);
  const zip = await JSZip.loadAsync(await construirDeckCredito(base7, agora).deck.gerar(agora));
  const nomes = Object.keys(zip.files).filter((n) => /^ppt\/slides\/slide\d+\.xml$/.test(n));
  const sl = await Promise.all(nomes.map((n) => zip.file(n)!.async("string")));
  const ii2 = textos(slideCom(sl, "II.2 · TENDÊNCIAS ESTRUTURAIS"));
  ok(ii2.includes("Norma XYZ de 2026 muda o licenciamento") && ii2.filter((t) => t === "[a preencher]").length >= 5,
    "(7a) o campo preenchido entra no cartão dele; os outros cartões do slide continuam \"[a preencher]\"");
  ok(sl.some((x) => textos(x).includes("Fulano de Tal")), "(7b) contato preenchido entra na contracapa");
  // 7·0,15 + 6·0,20 + 5·0,15 + 4·0,15 + 5·0,20 + 3·0,15 = 5,05 → "5,1" (estresse)
  ok(JSON.stringify(linha(slideCom(sl, "XVII · SCORECARD DE RISCO ORIA"), "Nota final ponderada", 3)) === JSON.stringify(["100%", "5,1", "estresse"]),
    "(7c) com as seis notas, a nota final é a média ponderada pelos pesos do Prompt-Mestre, com a faixa",
    JSON.stringify(linha(slideCom(sl, "XVII · SCORECARD DE RISCO ORIA"), "Nota final ponderada", 3)));
  const base5 = montarBaseCredito(entradaDoModeloDoWorkbook(wb)!, fixture.documentos,
    notas.slice(0, 5).map((n, i) => ({ chave: `xvii.nota${i + 1}`, valor: n, fonte: "analista" })));
  const z5 = await JSZip.loadAsync(await construirDeckCredito(base5, agora).deck.gerar(agora));
  const s5 = await Promise.all(Object.keys(z5.files).filter((n) => /^ppt\/slides\/slide\d+\.xml$/.test(n)).map((n) => z5.file(n)!.async("string")));
  ok(linha(slideCom(s5, "XVII · SCORECARD DE RISCO ORIA"), "Nota final ponderada", 2)[1] === "n/d",
    "(7d) com uma nota faltando, a nota final é n/d — nunca a média das que existem (o prompt: nunca a nota final sem as notas por eixo)");
}

console.log("--- 8. holding só com balanço: o deck se adapta ---");
{
  // VERTENTES PARTICIPAÇÕES S.A. no book: só BALANÇO, nenhuma DRE. Antes, 75 n/d no deck.
  const { slides } = await deckDe(entradaModeloDaFixture(fixture, agora, { entidade: "VERTENTES PARTICIPAÇÕES S.A." }));
  const temX1 = slides.some((x) => textos(x).some((t) => t.startsWith("X.1 · RESULTADO")));
  const notaOmitidos = slides.some((x) => textos(x).some((t) => /não tem DRE em nenhum exercício/.test(t)));
  const x2 = slideCom(slides, "X.2 · ESTRUTURA DE CAPITAL");
  ok(!temX1 && notaOmitidos && linha(x2, "Patrimônio líquido", 2).every((t) => /\d/.test(t)),
    "(8a) sem DRE: X.1 e os capítulos de resultado saem, a nota diz quais e por quê, e o balanço continua");
}

console.log("--- 9. o catálogo da tela e o gerador falam das mesmas chaves ---");
{
  // Toda chave que a tela oferece, preenchida com um valor único, TEM de aparecer no deck. Uma chave
  // que o gerador não lê seria um campo que o analista salva e que nunca chega ao slide.
  const entrada = entradaModeloDaFixture(fixture, agora);
  const wb = buildExportWorkbook({ caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos, agora, modeloInstitucional: entrada });
  const chaves = [...CHAVES_APRESENTACAO];
  const numerica = (c: string) => c.includes(".nota") || c.includes(".realizacao.");
  const valor = (i: number) => (numerica(chaves[i]) ? String(50 + (i % 3)) : `Q${String(i).padStart(3, "0")}Z`);
  const base9 = montarBaseCredito(entradaDoModeloDoWorkbook(wb)!, fixture.documentos,
    chaves.map((chave, i) => ({ chave, valor: valor(i), fonte: "analista" })),
    { perimetro: [{ razaoSocial: "VERTENTES METALÚRGICA LTDA.", cnpj: null, papel: "operacional", documentos: 9, analisada: true },
      { razaoSocial: "VERTENTES PARTICIPAÇÕES S.A.", cnpj: null, papel: "holding", documentos: 1, analisada: false }] });
  const zip = await JSZip.loadAsync(await construirDeckCredito(base9, agora).deck.gerar(agora));
  const tudo = (await Promise.all(Object.keys(zip.files).filter((x) => /^ppt\/slides\/slide\d+\.xml$/.test(x))
    .map((x) => zip.file(x)!.async("string")))).map((x) => textos(x).join(" ")).join(" ");
  // Vencimento/garantia existem só para as operações que o mapa tem (9 no book Vertentes).
  const nOps = dividaDoMapa(base9, [2024, 2025])?.operacoes.length ?? 0;
  const perdidas = chaves.filter((c, i) => !numerica(c) && !tudo.includes(valor(i))
    && !(/^xiii2\.op(\d+)\./.test(c) && Number(/^xiii2\.op(\d+)/.exec(c)![1]) > nOps));
  ok(chaves.length > 50 && perdidas.length === 0, `(9a) as ${chaves.length} chaves do catálogo chegam ao deck`, perdidas.slice(0, 8).join(", "));
}

console.log("--- 10. endividamento pelo mapa, ativos reais, o que faltou e o perímetro ---");
{
  const entrada = entradaModeloDaFixture(fixture, agora);
  const wb = buildExportWorkbook({ caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos, agora, modeloInstitucional: entrada });
  const ent10 = entradaDoModeloDoWorkbook(wb)!;
  const info = [{ codigo: "BALANCO", documento: "Balanço Patrimonial", status: "recebido" as const },
    { codigo: "CONTRATO_SOCIAL", documento: "Contrato social", status: "faltante" as const },
    { codigo: "DRE", documento: "DRE", status: "sem_conteudo" as const }];
  const b10 = montarBaseCredito(ent10, fixture.documentos,
    [{ chave: "xvi.realizacao.clientes", valor: "70", fonte: null }, { chave: "xvi.realizacao.estoques", valor: "50", fonte: null },
      { chave: "xvi.realizacao.imobilizado", valor: "60", fonte: null }],
    { informacao: info, perimetro: [{ razaoSocial: "VERTENTES METALÚRGICA LTDA.", cnpj: "00.000.000/0001-00", papel: "operacional", documentos: 7, analisada: true }] });
  const sl = await slidesDe(b10);
  const tx = (m: string) => textos(slideCom(sl, m)).join(" | ");
  // Mapa do book: 9 operações, 7 credores, Banco Atlântico Sul 12.360 de 51.300 (24%), total 51,3.
  ok(/7 credores; o maior, Banco Atlântico Sul, tem 24%/.test(tx("XIII.1 · ENDIVIDAMENTO")),
    "(10a) XIII.1 abre por credor a partir do mapa da dívida (7 credores, o maior com 24%)", tx("XIII.1 · ENDIVIDAMENTO").slice(0, 160));
  ok(/9 operações somam R\$ 51,3 mi/.test(tx("XIII.2 · POSIÇÃO OPERAÇÃO A OPERAÇÃO")) && /74,9%/.test(sl.map((x) => textos(x).join(" ")).join(" ")),
    "(10b) XIII.2 lista as operações com a taxa implícita (antecipação: 4.630 ÷ 6.180 = 74,9%)");
  const am10 = amarracoes(b10).filter((a) => a.numero === 7);
  ok(am10.some((a) => a.nome.startsWith("Abertura por credor = total") && a.veredito === "ok")
    && am10.some((a) => a.nome.startsWith("Mapa da dívida = dívida do balanço") && a.veredito === "diverge"),
    "(10c) amarração 7: as operações fecham com o TOTAL do mapa, e o mapa (51,3) diverge do balanço (46,3) — dito, não calado");
  // 24,3·0,7 + 7,2·0,5 + 92,8·0,6 = 17,0 + 3,6 + 55,7 = 76,3 (os contábeis do book em R$ mi, arredondados)
  const xvi = tx("XVI · ATIVOS REAIS E GARANTIAS");
  ok(/Ativos reais cobrem 2,7x a dívida bruta/.test(xvi) && /76,[23]/.test(xvi),
    "(10d) XVI: cobertura contábil 2,7x e valor estimado SÓ com a realização informada", xvi.slice(0, 200));
  const ix2 = tx("IX.2 · O QUE CHEGOU E O QUE FALTOU");
  ok(/1 de 3 documentos obrigatórios chegaram; 2 pendentes/.test(ix2) && /não recebido/.test(ix2) && /chegou sem conteúdo extraído/.test(ix2),
    "(10e) IX.2: o que chegou, o que faltou e o que chegou sem conteúdo", ix2.slice(0, 160));
  const semInfo = await slidesDe(montarBaseCredito(ent10, fixture.documentos));
  ok(/não lida nesta geração/.test(textos(slideCom(semInfo, "IX.2 · O QUE CHEGOU E O QUE FALTOU")).join(" ")),
    "(10f) sem a lista do kit, o IX.2 diz que não leu — nunca \"nada faltou\"");
  // Mapa de OUTRA entidade (o "GRUPO" no Canastra): dito, não somado nem calado.
  const outra = { ...b10, historico: { ...b10.historico, operacoes: [], totalDoMapa: {} }, mapasDeOutrasEntidades: ["GRUPO X"] };
  ok(/O mapa da dívida recebido é de GRUPO X, não desta entidade/.test(textos(slideCom(await slidesDe(outra), "XIII.1 · ENDIVIDAMENTO")).join(" ")),
    "(10g) mapa da dívida de outra entidade do caso: o slide diz de quem é, em vez de \"nenhum mapa\"");
  ok(/Perímetro de 1 empresa/.test(tx("III.3 · ECOSSISTEMA E PERÍMETRO")) && /00\.000\.000\/0001-00/.test(tx("III.3 · ECOSSISTEMA E PERÍMETRO")),
    "(10h) III.3: o perímetro vem do cadastro de entidades do caso, com CNPJ");
}

console.log("--- 11. resultado futuro (projeção guardada pela cobertura) e atual (balancete) ---");
{
  const entrada = entradaModeloDaFixture(fixture, agora);
  const wb = buildExportWorkbook({ caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos, agora, modeloInstitucional: entrada });
  const ent11 = entradaDoModeloDoWorkbook(wb)!;
  const pj = projecaoDoModelo(wb, ent11);
  const x4De = async (e: EntradaModeloInstitucional, p: typeof pj) =>
    textos(slideCom(await slidesDe(montarBaseCredito(e, fixture.documentos, [], { projecao: p })), "X.4 · RESULTADO PROJETADO")).join(" ");
  // Sem vínculo nos custos, o modelo os zera no futuro: a cobertura cai e o X.4 não projeta.
  const semCusto = { ...ent11, vinculos: ent11.vinculos.filter((v) => v.premissa_codigo !== "CUSTO_VARIAVEL") };
  const x4a = await x4De(semCusto, projecaoDoModelo(wb, semCusto));
  ok(/Projeção não apresentada: só \d+% do resultado tem premissa/.test(x4a) && !/EBITDA projetado de/.test(x4a),
    "(11a) custos sem premissa: o X.4 diz que não projeta, em vez de publicar custo zero", x4a.slice(0, 160));
  // O book, 100% vinculado, com "custo variável 60%": margem 0,9% → 48,6% (medido 05/10/2026).
  const x4b = await x4De(ent11, pj);
  ok(pj?.cobertura === 1 && /Premissas levam a margem EBITDA de 0,9% para 48,6% em 2026/.test(x4b) && /Revisar premissas/.test(x4b),
    "(11b) premissa incoerente com o histórico: o X.4 diz o salto de margem em vez de manchetear o EBITDA", x4b.slice(0, 200));
  // Mesma projeção com EBITDA na margem histórica (~1%): publica.
  const coerente = { ...pj!, ebitda: pj!.receita.map((r) => (r === null ? null : r * 0.01)) };
  const x4c = await x4De(ent11, coerente);
  ok(/EBITDA projetado de/.test(x4c) && !/Revisar premissas/.test(x4c), "(11c) premissa coerente: o X.4 publica o EBITDA projetado", x4c.slice(0, 160));
  // Ano corrente: as linhas de 2025 reapresentadas como 2026, com balancete "8M26" → coluna parcial.
  const linhas26 = ent11.linhas.map((l) => ({ ...l, valores: { "2026": l.valores["2025"] } }));
  const docs26 = [...fixture.documentos, { ...fixture.documentos[0], tipo_taxonomia: "BALANCETE",
    periodo: { tipo: "ano_fiscal", referencia: "8M26" } } as unknown as DocumentoParaExport];
  const cor = correnteDoBalancete(ent11, linhas26, 2026, docs26);
  const x1 = textos(slideCom(await slidesDe(montarBaseCredito(ent11, fixture.documentos, [], { corrente: cor })), "X.1 · RESULTADO")).join(" | ");
  ok(cor?.meses === 8 && /8M\/2026 \(B\)/.test(x1), "(11d) o ano corrente entra no X.1 como coluna parcial \"8M/2026 (B)\"", x1.slice(0, 200));
}

console.log("--- 12. o mapa da dívida MATRICIAL (forma de produção, 0145) com taxa, vencimento e garantia ---");
{
  // A tabela do PDF do book (render.py: Credor | Modalidade | Saldo devedor (R$) | Taxa | Vencimento
  // | Garantia | Juros do exercício (R$)), na forma em que a extração de produção a grava: a chave é a
  // linha, o conceito mora na coluna (0145). Os contratos são os de `demonstracoes.py`, com o ajuste
  // de juros do 4º que amarra a DRE — só saldo e textos são afirmados aqui.
  const contratos: Array<[string, string, number, string, string, string, number]> = [
    ["Banco Meridional S.A.", "Capital de giro", 9420, "CDI + 6,80% a.a.", "15/03/2026", "Recebíveis + aval dos sócios", 2180],
    ["Banco Meridional S.A.", "Conta garantida", 2380, "CDI + 9,20% a.a.", "Rotativo", "Aval dos sócios", 640],
    ["Banco Atlântico Sul", "Capital de giro", 6180, "CDI + 7,40% a.a.", "20/08/2026", "Alienação fiduciária de máquinas", 1490],
    ["Banco Atlântico Sul", "Antecipação de recebíveis", 6180, "2,45% a.m.", "Rotativo", "Duplicatas cedidas", 4630],
    ["BNDES / FINAME (agente: Banco Meridional)", "Financiamento de máquinas", 9080, "TLP + 4,10% a.a.", "10/07/2029", "Alienação fiduciária dos bens financiados", 1080],
    ["Cooperativa de Crédito Vale", "Capital de giro", 3140, "1,95% a.m.", "05/02/2026", "Aval dos sócios", 820],
    ["Fomento Mercantil Paulista Ltda.", "Factoring", 2440, "3,10% a.m.", "Rotativo", "Duplicatas cedidas com coobrigação", 1180],
    ["Arrendadora Sigma", "Arrendamento mercantil (CPC 06)", 2680, "CDI + 8,00% a.a.", "30/11/2027", "Bem arrendado", 380],
    ["Sócios pessoas físicas", "Empréstimo subordinado", 9800, "Sem remuneração", "Sem vencimento definido", "Sem garantia", 0],
  ];
  const VER = "55555555-0000-0000-0000-000000000011";
  const outros = fixture.campos.filter((c) => c.documento_versao_id !== VER);
  const modelo = fixture.campos.find((c) => c.documento_versao_id === VER)!;
  let ordem = 0;
  const campo = (chave: string, coluna: string, num: number | null, texto: string | null): CampoExtraido =>
    ({ ...modelo, id: `m-${ordem}`, ordem: ordem++, chave, periodo_coluna: coluna, valor_num: num, valor_texto: texto,
      unidade: num === null ? null : "unidade" });
  // Forma A: chave = credor, modalidade numa coluna de texto (o mesmo credor em duas linhas).
  const formaA = contratos.flatMap(([cr, mod, saldo, taxa, venc, gar, juros]) => [
    campo(cr, "Modalidade", null, mod), campo(cr, "Saldo devedor (R$)", saldo * 1000, null), campo(cr, "Taxa", null, taxa),
    campo(cr, "Vencimento", null, venc), campo(cr, "Garantia", null, gar), campo(cr, "Juros do exercício (R$)", juros * 1000, null)]);
  // Forma B: chave = "Credor - Modalidade" (o exemplo literal da 0145), sem coluna de modalidade.
  const formaB = contratos.flatMap(([cr, mod, saldo, taxa, venc, gar, juros]) => [
    campo(`${cr} - ${mod}`, "Saldo devedor (R$)", saldo * 1000, null), campo(`${cr} - ${mod}`, "Taxa", null, taxa),
    campo(`${cr} - ${mod}`, "Vencimento", null, venc), campo(`${cr} - ${mod}`, "Garantia", null, gar),
    campo(`${cr} - ${mod}`, "Juros do exercício (R$)", juros * 1000, null)]);
  const entrada = entradaModeloDaFixture(fixture, agora);
  const wb = buildExportWorkbook({ caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos, agora, modeloInstitucional: entrada });
  const ent12 = entradaDoModeloDoWorkbook(wb)!;
  for (const [nome, forma] of [["A (credor + coluna de modalidade)", formaA], ["B (\"Credor - Modalidade\")", formaB]] as const) {
    const b = montarBaseCredito(ent12, fixture.documentos, [], {}, [...outros, ...forma]);
    const m = dividaDoMapa(b, [2024, 2025]);
    ok(m?.operacoes.length === 9 && Math.round(m.total / 100) === 513 && m.credores.length === 7,
      `(12a) forma ${nome}: 9 operações, 7 credores, saldo 51,3 mi`, `${m?.operacoes.length} ops, total ${m?.total}`);
    const sl = await slidesDe(b);
    if (process.env.SALVAR_DECK) (await import("node:fs")).writeFileSync(`${process.env.SALVAR_DECK}-${nome[0]}.pptx`, await construirDeckCredito(b, agora).deck.gerar(agora));
    const xiii2 = sl.filter((x) => textos(x).some((t) => t.startsWith("XIII.2"))).map((x) => textos(x).join(" | ")).join(" | ");
    ok(/CDI \+ 6,80% a\.a\./.test(xiii2) && /15\/03\/2026/.test(xiii2) && /Aval dos sócios/.test(xiii2) && !/\[a preencher\]/.test(xiii2.split("Garantia")[1] ?? ""),
      `(12b) forma ${nome}: XIII.2 mostra a taxa contratual, o vencimento e a garantia DO MAPA`, xiii2.slice(0, 240));
    const xiii3 = textos(slideCom(sl, "XIII.3 · MURO DE VENCIMENTOS")).join(" ");
    ok(/5 de 9 operações têm vencimento impresso/.test(xiii3),
      `(12c) forma ${nome}: XIII.3 monta o muro pelo vencimento (rotativo e sem prazo à parte)`, xiii3.slice(0, 200));
  }
}

console.log(`\n${passou} asserts passaram, ${falhas} falharam`);
if (falhas > 0) process.exit(1);
console.log("APRESENTAÇÃO OK — número do documento, ausência dita, padrão visual varrido com controle positivo");
