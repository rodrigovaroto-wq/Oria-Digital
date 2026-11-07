// VARREDURA DE TODOS OS MANDATOS, TELA A TELA E ARQUIVO A ARQUIVO, CONTRA UM PORTAL NO AR.
//
// Por que existe: a vistoria por papel (`vistoria-por-papel.mts`) mede QUEM vê o quê em UM mandato sintético.
// Ela não diz se algum mandato REAL quebra. Em 06/11/2026, depois do #274, a pergunta do dono foi essa:
// "quando colocarmos em produção, nenhum mandato falha de forma nenhuma". A resposta só vem abrindo cada um.
//
// O que mede, por mandato visível ao login:
//   1. as 11 abas (desktop 1280 px): status do documento, resposta 5xx de qualquer chamada do próprio portal,
//      painel de erro ("Esta tela não carregou" e afins), exceção de JavaScript não tratada, erro de console,
//      tela que não termina de carregar, estouro horizontal;
//   2. as telas principais no celular (390 px): estouro horizontal;
//   3. os três arquivos entregues ao cliente (`/export?modo=dados`, o modelo completo e a apresentação):
//      - a BASE DE DADOS tem de sair sempre (é "disponível desde a ingestão"): qualquer não-200 é FALHA;
//      - modelo e apresentação: 409/422 com mensagem é RECUSA legítima do portão (caso não aprovado);
//        qualquer outro não-200 (401/403/404/5xx, redirecionamento) é FALHA;
//      - 200 tem de ser o formato certo: .xlsx com ≥1 aba com conteúdo, .pptx com `ppt/presentation.xml`;
//      - com VM_RECALCULAR=1 (precisa do `soffice`), cada .xlsx é RECALCULADO pelo LibreOffice e toda célula
//        que der #REF!/#NAME?/#DIV/0!/#VALUE!/#N/A é FALHA. Sem recalcular, o export grava só a fórmula
//        (sem resultado, `fullCalcOnLoad`) e o erro só apareceria ao abrir no Excel — por isso, sem
//        VM_RECALCULAR, o resumo diz "fórmulas NÃO recalculadas" em vez de afirmar que não há erro;
//   4. com VM_DOCUMENTOS=1, a página de CADA documento; lista que diz ter documento e não expõe nenhum
//      link é FALHA (senão "0 documentos abertos" pareceria verde).
// Mandatos ATIVOS e FECHADOS (as duas abas de /casos/todos). VM_ESPERADO=<n> confere a contagem contra o banco.
//
// SÓ LEITURA. Nenhum botão é clicado. A gravação que uma tela faz ao abrir (cache de fatos) é a mesma de
// qualquer pessoa abrindo o mandato. Para provar "nada mudou", fotografe antes e depois (ver o fim do arquivo).
//
// Saída: VM_SAIDA/resultado.json e um resumo no stdout. Código de saída: 0 = nenhuma FALHA; 1 = achou FALHA;
// 2 = não conseguiu rodar (sem credencial, login recusado, nenhum mandato visível — NÃO é verde, regra 7).
//
// Como rodar (nunca `npx`):
//   VM_CREDENCIAL=<arquivo com e-mail na 1ª linha e senha na 2ª> VM_SAIDA=<pasta> \
//   [VM_BASE=https://tratamento-dados-financeiros.vercel.app] [VM_DOCUMENTOS=1] [VM_PARALELO=3] \
//   [VM_SO=<id,id>] ./portal/node_modules/.bin/tsx Verificação/varredura-dos-mandatos.mts
// A senha nunca é impressa nem gravada.
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { execFileSync } from "node:child_process";

const sair = (codigo: number, msg: string): never => { console.error(msg); process.exit(codigo); };
const CRED = process.env.VM_CREDENCIAL ?? sair(2, "NÃO RODOU: falta VM_CREDENCIAL.");
const SAIDA = process.env.VM_SAIDA ?? sair(2, "NÃO RODOU: falta VM_SAIDA.");
const BASE = (process.env.VM_BASE ?? "https://tratamento-dados-financeiros.vercel.app").replace(/\/$/, "");
const DOCS = process.env.VM_DOCUMENTOS === "1";
const PARALELO = Math.max(1, Number(process.env.VM_PARALELO ?? 3));
const SO = (process.env.VM_SO ?? "").split(",").filter(Boolean);
const RECALC = process.env.VM_RECALCULAR === "1";
// Caminho ABSOLUTO (Sonar S4036): resolver "soffice" pelo PATH deixaria um diretório gravável escolher o binário.
const SOFFICE = process.env.VM_SOFFICE ?? "/usr/bin/soffice";
const ESPERADO = process.env.VM_ESPERADO ? Number(process.env.VM_ESPERADO) : null;
const [EMAIL, SENHA] = fs.readFileSync(CRED, "utf8").trim().split("\n").map((s) => s.trim());
if (!EMAIL || !SENHA) sair(2, "NÃO RODOU: o arquivo de credencial precisa de e-mail e senha em duas linhas.");
fs.mkdirSync(SAIDA, { recursive: true });

const req = createRequire(path.resolve(import.meta.dirname, "../portal/package.json"));
const { chromium } = createRequire(import.meta.url)(process.env.VM_PLAYWRIGHT ?? "playwright");
const ExcelJS = req("exceljs");

const ROTAS = ["", "/documentos", "/pendencias", "/revisao", "/modelagem", "/entregaveis", "/apresentacao",
  "/perguntas", "/perimetro", "/historico", "/adicionar"];
const ROTAS_CELULAR = ["", "/documentos", "/pendencias", "/modelagem"];
// Os títulos dos painéis de erro do próprio portal (`components/painel-de-erro.tsx` e os `error.tsx`) e o
// texto padrão do Next quando a exceção escapa de tudo.
const ERRO_NA_TELA = /Esta tela não carregou|Algo não deu certo|Application error|server-side exception|Internal Server Error/i;
const ERRO_NA_FORMULA = /#REF!|#NAME\?|#DIV\/0!|#VALUE!|#N\/A/;
const TEMPO = 90_000;

type Achado = { onde: string; nivel: "FALHA" | "AVISO" | "RECUSA" | "ok"; o_que: string; ms?: number };
const achados: Achado[] = [];
const anota = (a: Achado) => { achados.push(a); if (a.nivel !== "ok") console.log(`${a.nivel.padEnd(6)} ${a.onde} — ${a.o_que}`); };

async function emPool<T>(itens: T[], n: number, passo: (item: T, i: number) => Promise<void>) {
  let prox = 0;
  await Promise.all(Array.from({ length: Math.min(n, itens.length) }, async () => {
    while (prox < itens.length) { const i = prox++; await passo(itens[i], i); }
  }));
}

async function abrir(ctx: any, url: string, rotulo: string, opcoes: { celular?: boolean } = {}) {
  const page = await ctx.newPage();
  const consoleErros: string[] = []; const excecoes: string[] = []; const http5xx: string[] = []; const http4xx: string[] = [];
  page.on("console", (m: any) => { if (m.type() === "error") consoleErros.push(m.text().slice(0, 200)); });
  page.on("pageerror", (e: any) => excecoes.push(String(e?.message ?? e).slice(0, 200)));
  page.on("response", (r: any) => {
    const u = r.url(); if (!u.startsWith(BASE)) return;
    if (r.status() >= 500) http5xx.push(`${r.status()} ${u.replace(BASE, "").slice(0, 120)}`);
    else if (r.status() >= 400 && !/(?:favicon|\.map$)/.test(u)) http4xx.push(`${r.status()} ${u.replace(BASE, "").slice(0, 120)}`);
  });
  const t0 = Date.now();
  try {
    const resp = await page.goto(url, { waitUntil: "networkidle", timeout: TEMPO });
    const ms = Date.now() - t0;
    const status = resp?.status() ?? 0;
    const final = page.url();
    const texto: string = await page.locator("body").innerText({ timeout: 10_000 }).catch(() => "");
    const largura = await page.evaluate(() => [document.documentElement.scrollWidth, window.innerWidth]);
    const carregando = await page.locator('[aria-busy="true"]').count().catch(() => 0);
    const falhas: string[] = []; const avisos: string[] = [];
    if (status >= 500) falhas.push(`HTTP ${status}`);
    if (final.includes("/login")) falhas.push("caiu no login (sessão perdida ou sem acesso)");
    if (ERRO_NA_TELA.test(texto)) falhas.push(`painel de erro: "${(texto.match(ERRO_NA_TELA) ?? [""])[0]}"`);
    if (excecoes.length) falhas.push(`exceção JS: ${excecoes[0]}`);
    if (http5xx.length) falhas.push(`${http5xx.length} resposta(s) 5xx: ${http5xx[0]}`);
    if (status >= 400) falhas.push(`HTTP ${status}`);
    // PISO DE CONTEÚDO: uma tela que renderizou só a moldura (barra lateral, cabeçalho) passaria como ok.
    // O <main> tem de trazer texto de verdade; 40 caracteres é menos que qualquer estado vazio do portal.
    const principal: string = await page.locator("main").innerText({ timeout: 5_000 }).catch(() => "");
    if (principal.trim().length < 40) falhas.push(`tela sem conteúdo (${principal.trim().length} caracteres no <main>)`);
    if (carregando) avisos.push(`${carregando} elemento(s) ainda aria-busy depois do networkidle`);
    if (largura[0] > largura[1] + 1) avisos.push(`estouro horizontal ${largura[0]} > ${largura[1]} px${opcoes.celular ? "" : " (desktop)"}`);
    if (consoleErros.length) avisos.push(`${consoleErros.length} erro(s) de console: ${consoleErros[0]}`);
    if (http4xx.length) avisos.push(`${http4xx.length} resposta(s) 4xx: ${http4xx[0]}`);
    if (ms > 20_000) avisos.push(`lenta: ${ms} ms`);
    if (falhas.length) anota({ onde: rotulo, nivel: "FALHA", o_que: [...falhas, ...avisos].join(" · "), ms });
    else if (avisos.length) anota({ onde: rotulo, nivel: "AVISO", o_que: avisos.join(" · "), ms });
    else anota({ onde: rotulo, nivel: "ok", o_que: "", ms });
    return { page, texto };
  } catch (e: any) {
    anota({ onde: rotulo, nivel: "FALHA", o_que: `não abriu: ${String(e?.message ?? e).split("\n")[0].slice(0, 200)}`, ms: Date.now() - t0 });
    return { page, texto: "" };
  }
}

function recalcular(buf: Buffer): Buffer {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vm-recalc-"));
  try {
    fs.writeFileSync(path.join(dir, "in.xlsx"), buf);
    execFileSync(SOFFICE, ["--headless", "--calc", "--convert-to", "xlsx:Calc MS Excel 2007 XML", "--outdir", path.join(dir, "out"),
      path.join(dir, "in.xlsx")], { timeout: 300_000, stdio: "ignore", env: { ...process.env, HOME: dir } });
    return fs.readFileSync(path.join(dir, "out", "in.xlsx"));
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
}

async function baixar(ctx: any, casoId: string, modo: "dados" | "completo" | "apresentacao", rotulo: string) {
  const url = `${BASE}/casos/${casoId}/export${modo === "completo" ? "" : `?modo=${modo}`}`;
  const t0 = Date.now();
  try {
    const r = await ctx.request.get(url, { timeout: 180_000, maxRedirects: 0 });
    const ms = Date.now() - t0; const st = r.status(); const tipo = r.headers()["content-type"] ?? "";
    if (st !== 200) {
      const corpo = (await r.text().catch(() => "")).replace(/\s+/g, " ").slice(0, 200);
      // Só a recusa do PORTÃO é legítima: 409/422 com mensagem, e nunca na base de dados.
      const recusaDoPortao = modo !== "dados" && (st === 409 || st === 422) && /recusad|aprovad|bloque/i.test(corpo);
      return anota({ onde: rotulo, nivel: recusaDoPortao ? "RECUSA" : "FALHA",
        o_que: `HTTP ${st}${st >= 300 && st < 400 ? ` → ${r.headers().location}` : ""}: ${corpo || "(sem corpo)"}`, ms });
    }
    const buf: Buffer = await r.body();
    if (buf.length < 100 || buf[0] !== 0x50 || buf[1] !== 0x4b) return anota({ onde: rotulo, nivel: "FALHA", o_que: `200 mas não é ZIP (${tipo}, ${buf.length} bytes)`, ms });
    if (modo === "apresentacao") {
      const JSZip = req("jszip");
      const zip = await JSZip.loadAsync(buf);
      const ok = Boolean(zip.file("ppt/presentation.xml")) && /presentationml/.test(tipo);
      const slides = Object.keys(zip.files).filter((n) => /^ppt\/slides\/slide\d+\.xml$/.test(n)).length;
      return anota({ onde: rotulo, nivel: ok && slides > 0 ? "ok" : "FALHA",
        o_que: ok && slides > 0 ? `${slides} slides, ${buf.length} bytes` : `não é .pptx com slides (${tipo}, ${slides} slides)`, ms });
    }
    if (!/spreadsheetml/.test(tipo)) return anota({ onde: rotulo, nivel: "FALHA", o_que: `200 com content-type ${tipo || "(vazio)"}`, ms });
    const wb = new ExcelJS.Workbook();
    await wb.xlsx.load(RECALC ? recalcular(buf) : buf);
    const ruins: string[] = []; let formulas = 0; let comResultado = 0; let celulas = 0;
    wb.eachSheet((ws: any) => ws.eachRow((row: any) => row.eachCell((c: any) => {
      celulas++;
      const v = c.value;
      const ehFormula = v && typeof v === "object" && ("formula" in v || "sharedFormula" in v);
      if (ehFormula) { formulas++; if (v.result !== undefined && v.result !== null) comResultado++; }
      const res = ehFormula ? v.result : v;
      const erro = res && typeof res === "object" && "error" in res ? String(res.error) : (typeof res === "string" ? res : "");
      const textoFormula = ehFormula ? String(v.formula ?? v.sharedFormula ?? "") : "";
      if (ERRO_NA_FORMULA.test(erro) || ERRO_NA_FORMULA.test(textoFormula)) ruins.push(`${ws.name}!${c.address}${erro ? " " + erro : ""}`);
    })));
    if (celulas === 0) return anota({ onde: rotulo, nivel: "FALHA", o_que: `.xlsx sem nenhuma célula (${wb.worksheets.length} abas)`, ms });
    if (ruins.length) return anota({ onde: rotulo, nivel: "FALHA", o_que: `${ruins.length} célula(s) com erro: ${ruins.slice(0, 5).join(", ")}`, ms });
    const calc = RECALC ? `${comResultado}/${formulas} fórmulas recalculadas` : `${formulas} fórmulas NÃO recalculadas`;
    return anota({ onde: rotulo, nivel: "ok", o_que: `${wb.worksheets.length} abas, ${celulas} células, ${calc}, ${buf.length} bytes`, ms });
  } catch (e: any) {
    return anota({ onde: rotulo, nivel: "FALHA", o_que: `download falhou: ${String(e?.message ?? e).split("\n")[0].slice(0, 200)}`, ms: Date.now() - t0 });
  }
}

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1 });
const login = await ctx.newPage();
await login.goto(`${BASE}/login`, { timeout: TEMPO });
await login.fill("#email", EMAIL);
await login.fill("input[type=password]", SENHA);
await Promise.all([
  login.waitForURL((u: URL) => !u.pathname.startsWith("/login"), { timeout: 45_000 }).catch(() => null),
  login.click("button[type=submit]"),
]);
if (new URL(login.url()).pathname.startsWith("/login")) sair(2, "NÃO RODOU: o login foi recusado.");
const hrefs: string[] = [];
for (const aba of ["/casos/todos", "/casos/todos?aba=fechados"]) {
  await login.goto(`${BASE}${aba}`, { waitUntil: "networkidle", timeout: TEMPO });
  hrefs.push(...await login.$$eval("main a[href^='/casos/']", (as: any[]) => as.map((a) => a.getAttribute("href"))));
}
const ids: string[] = [...new Set<string>(hrefs.map((h: string) => (h.match(/^\/casos\/([0-9a-f-]{36})(?:$|[/?#])/) ?? [])[1]).filter(Boolean))];
if (ESPERADO != null && ids.length !== ESPERADO && !SO.length)
  sair(2, `NÃO RODOU: o portal lista ${ids.length} mandato(s) e o banco diz ${ESPERADO}. Uma varredura parcial não é verde.`);
const mandatos = SO.length ? ids.filter((i) => SO.includes(i)) : ids;
await login.close();
if (!mandatos.length) sair(2, "NÃO RODOU: nenhum mandato visível em /casos/todos.");
console.log(`${mandatos.length} mandato(s) em ${BASE}${DOCS ? ", com cada documento" : ""}; ${PARALELO} em paralelo.`);

const celular = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, storageState: await ctx.storageState() });
const t0 = Date.now();
const docsPorMandato: Record<string, number> = {};
await emPool(mandatos, PARALELO, async (id, i) => {
  const curto = id.slice(0, 8);
  for (const r of ROTAS) {
    const { page } = await abrir(ctx, `${BASE}/casos/${id}${r}`, `${curto}${r || "/"}`);
    if (r === "/documentos" && DOCS) {
      const docIds: string[] = [...new Set<string>((await page.$$eval(`a[href*='/casos/${id}/documentos/']`, (as: any[]) => as.map((a) => a.getAttribute("href"))))
        .map((h: string) => (h.match(/\/documentos\/([0-9a-f-]{36})/) ?? [])[1]).filter(Boolean))];
      docsPorMandato[id] = docIds.length;
      const semDocumento = /Nenhum documento recebido ainda/.test(await page.locator("main").innerText().catch(() => ""));
      if (!docIds.length && !semDocumento)
        anota({ onde: `${curto}/documentos`, nivel: "FALHA", o_que: "a lista não diz que está vazia e não expõe nenhum link de documento" });
      for (const d of docIds) { const p = await abrir(ctx, `${BASE}/casos/${id}/documentos/${d}`, `${curto}/documentos/${d.slice(0, 8)}`); await p.page.close(); }
    }
    await page.close();
  }
  for (const r of ROTAS_CELULAR) { const { page } = await abrir(celular, `${BASE}/casos/${id}${r}`, `${curto}${r || "/"} [390px]`, { celular: true }); await page.close(); }
  for (const modo of ["dados", "completo", "apresentacao"] as const) await baixar(ctx, id, modo, `${curto}/export?${modo}`);
  console.log(`— ${i + 1}/${mandatos.length} ${curto} (${Math.round((Date.now() - t0) / 1000)} s)`);
});
await browser.close();

const conta = (n: Achado["nivel"]) => achados.filter((a) => a.nivel === n).length;
const exportsOk = achados.filter((a) => a.nivel === "ok" && a.onde.includes("/export?")).length;
const resumo = { quando: new Date().toISOString(), base: BASE, mandatos: mandatos.length, esperado: ESPERADO,
  formulas_recalculadas: RECALC, exports_baixados: exportsOk, documentos: docsPorMandato,
  verificacoes: achados.length, ok: conta("ok"), recusas: conta("RECUSA"), avisos: conta("AVISO"), falhas: conta("FALHA"),
  segundos: Math.round((Date.now() - t0) / 1000) };
fs.writeFileSync(path.join(SAIDA, "resultado.json"), JSON.stringify({ resumo, achados }, null, 1));
console.log(JSON.stringify(resumo));
// Regra 7: sem nenhum export baixado não houve verificação de arquivo — isso não é verde.
if (!resumo.falhas && exportsOk === 0) sair(2, "NÃO CONFERIDO: nenhum export foi baixado com sucesso.");
process.exit(resumo.falhas ? 1 : 0);

// FOTO DO BANCO antes e depois (somente leitura), para afirmar que a varredura não gravou decisão:
//   select (select count(*) from evento_auditoria) eventos, (select count(*) from decisao) decisoes,
//          (select md5(string_agg(id::text||estado::text, ',' order by id)) from pendencia) pendencias;
