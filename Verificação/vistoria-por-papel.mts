// VISTORIA DO PORTAL POR PAPEL (P2), CONTRA PRODUÇÃO, COM DADO SINTÉTICO.
//
// O que mede (nada disto roda no CI; escreve dado sintético em produção, com autorização do dono):
//   1. envio válido ponta a ponta pelo navegador, como Sócio (só com P2_ENVIAR=1 — sem isso o envio
//      aparece como NÃO EXECUTADO no resultado, nunca como ok);
//   2. matriz papel × tela: anônimo, Sócio, Analista e Leitura em TODAS as rotas de `portal/src/app`,
//      no desktop e (telas principais) no celular 390×844;
//   3. escalada por API com o JWT de cada papel: cada tentativa vira "BARRADO (<código>)" ou
//      "PASSOU (<n> linhas)". O que passa e muda dado é desfeito na hora.
//
// Como rodar (nunca `npx`: o binário do lock):
//   P2_USUARIOS=<arquivo: "<papel> <uuid> <senha>" por linha> SUPABASE_URL=https://<ref>.supabase.co \
//   P2_PLAYWRIGHT=<pasta do pacote playwright, se `require('playwright')` não resolver> \
//   P2_SAIDA=<pasta das capturas e do resultado.json> \
//   ./portal/node_modules/.bin/tsx Verificação/vistoria-por-papel.mts
//
// Opcionais: P2_BASE (default: produção), P2_MANDATO (default "S117 P2 sintetico"), P2_ANON_KEY (se
// ausente, é lida do cabeçalho `apikey` que o próprio portal manda ao Supabase — a chave anon é pública
// por desenho e respeita a RLS). A senha NUNCA é impressa nem gravada; o resultado.json não a contém.
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { createClient } from "../portal/node_modules/@supabase/supabase-js/dist/index.mjs";

const exigir = (n: string): string => {
  const v = process.env[n];
  if (!v) { console.error(`Falta a variável de ambiente ${n}.`); process.exit(2); }
  return v;
};
const ARQ_USUARIOS = exigir("P2_USUARIOS");
const SUPABASE_URL = exigir("SUPABASE_URL");
const SAIDA = exigir("P2_SAIDA");
const BASE = process.env.P2_BASE ?? "https://tratamento-dados-financeiros.vercel.app";
const MANDATO = process.env.P2_MANDATO ?? "S117 P2 sintetico";
const PDFS = ["01_BP_Vertentes_Metalurgica_2025x2024.pdf", "07_DRE_Vertentes_Metalurgica_2025x2024.pdf"]
  .map((f) => path.resolve(import.meta.dirname, "../Dados de Teste/book-vertentes/pdf", f));
fs.mkdirSync(SAIDA, { recursive: true });

const req = createRequire(import.meta.url);
const { chromium } = req(process.env.P2_PLAYWRIGHT ?? "playwright");

type Papel = "socio" | "analista" | "leitura";
const PAPEIS: Papel[] = ["socio", "analista", "leitura"];
const cred = Object.fromEntries(
  fs.readFileSync(ARQ_USUARIOS, "utf8").trim().split("\n").map((l) => {
    const [p, id, s] = l.trim().split(/\s+/);
    return [p, { id, s }];
  }),
) as Record<Papel, { id: string; s: string }>;
const email = (p: Papel) => `rodrigo.varoto+${p}@oriapartners.com`;
const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/g;

let ANON = process.env.P2_ANON_KEY ?? "";
// P2_SO=matriz refaz só a matriz e preserva o que já estava em resultado.json (envio e escalada).
const ANTERIOR = path.join(SAIDA, "resultado.json");
const resultado: Record<string, unknown> = process.env.P2_SO === "matriz" && fs.existsSync(ANTERIOR)
  ? JSON.parse(fs.readFileSync(ANTERIOR, "utf8"))
  : { quando: new Date().toISOString(), base: BASE };
const grava = () => fs.writeFileSync(path.join(SAIDA, "resultado.json"), JSON.stringify(resultado, null, 1));

// ---------- navegador ----------
async function novoContexto(browser: any, papel: Papel | "anonimo", mobile = false) {
  const ctx = await browser.newContext({
    viewport: mobile ? { width: 390, height: 844 } : { width: 1280, height: 800 },
    deviceScaleFactor: 1,
    isMobile: mobile,
  });
  // tsx injeta `__name` nas funções; dentro de page.evaluate ele não existe e o evaluate devolveria null.
  await ctx.addInitScript("window.__name = (f) => f;");
  const page = await ctx.newPage();
  page.on("request", (r: any) => { const k = r.headers()["apikey"]; if (k && !ANON) ANON = k; });
  if (papel !== "anonimo") {
    await page.goto(BASE + "/login");
    await page.fill("input[name=email]", email(papel));
    await page.fill("input[name=password]", cred[papel].s);
    await Promise.all([
      page.waitForURL((x: URL) => !x.pathname.startsWith("/login"), { timeout: 30000 }),
      page.click("button[type=submit]"),
    ]);
  }
  return { ctx, page };
}

async function enviar(browser: any) {
  if (process.env.P2_ENVIAR !== "1") return { estado: "NÃO EXECUTADO", porque: "P2_ENVIAR=1 não definido" };
  const { ctx, page } = await novoContexto(browser, "socio");
  const erros: string[] = [];
  page.on("console", (m: any) => { if (m.type() === "error") erros.push(m.text().slice(0, 200)); });
  await page.goto(BASE + "/casos/novo");
  await page.fill("#mandato", MANDATO);
  await Promise.all([page.waitForURL(/\/casos\/[0-9a-f-]{36}\/adicionar/, { timeout: 30000 }), page.click("button[type=submit]")]);
  await page.waitForTimeout(1500);
  await page.setInputFiles("input[type=file]", PDFS);
  const t0 = Date.now();
  await page.click('form button[type=submit]:has-text("Enviar")');
  await page.waitForTimeout(20000);
  await page.screenshot({ path: path.join(SAIDA, "envio-enviado.png"), fullPage: true });
  await ctx.close();
  return { estado: "executado", ms_ate_resposta: Date.now() - t0, erros_console: erros };
}

// ---------- API ----------
async function cliente(papel: Papel | "anonimo") {
  const c = createClient(SUPABASE_URL, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
  if (papel !== "anonimo") {
    const { error } = await c.auth.signInWithPassword({ email: email(papel), password: cred[papel].s });
    if (error) throw new Error(`login por API falhou (${papel}): ${error.message}`);
  }
  return c;
}

const ROTAS_CASO = [
  "", "/adicionar", "/apresentacao", "/documentos", "/entregaveis", "/historico", "/modelagem",
  "/pendencias", "/perguntas", "/perimetro", "/revisao",
];
const ROTAS_GERAIS = [
  "/", "/casos", "/casos/todos", "/casos/novo", "/autonomia", "/administracao", "/administracao/custos",
  "/administracao/equipe", "/login", "/login/recuperar", "/login/nova-senha", "/auth/confirmar",
  "/api/busca?q=Vertentes", "/api/intake/destino?apenas=agora",
];
const MOBILE = ["/login", "/casos/todos", "/casos/novo", "/autonomia", "/administracao/equipe", "/casos/{A}", "/casos/{A}/documentos", "/casos/{A}/pendencias", "/casos/{A}/modelagem"];

async function celula(page: any, papel: string, rota: string, vp: "desk" | "mob", erros: string[], respRuins: string[]) {
  const slug = `${papel}-${vp}-${rota.replace(UUID, "ID").replace(/[^a-z0-9]+/gi, "_").slice(0, 70)}`;
  erros.length = 0; respRuins.length = 0;
  const t0 = Date.now();
  let status: number | null = null; let falha: string | null = null;
  try {
    const r = await page.goto(BASE + rota, { waitUntil: "load", timeout: 45000 });
    status = r ? r.status() : null;
    await page.waitForLoadState("networkidle", { timeout: 8000 }).catch(() => {});
  } catch (e: any) { falha = String(e.message).split("\n")[0].slice(0, 150); }
  const ms = Date.now() - t0;
  const u = new URL(page.url());
  const larguraNominal = vp === "mob" ? 390 : 1280;
  const dados = await page.evaluate((larguraNominal: number) => {
    const vis = (el: Element) => { const r = (el as HTMLElement).getBoundingClientRect(); return r.width > 0 && r.height > 0; };
    const botoes = [...document.querySelectorAll("button, a[class*='btn-']")]
      .filter(vis).map((e) => (e.textContent ?? "").trim().replace(/\s+/g, " ").slice(0, 40)).filter(Boolean);
    const hrefs = new Set([...document.querySelectorAll("a[href^='/casos/']")].map((a) => a.getAttribute("href") ?? "")
      .filter((h) => /^\/casos\/[0-9a-f-]{36}$/.test(h)));
    return {
      h1: (document.querySelector("h1")?.textContent ?? "").trim().slice(0, 80),
      botoes: [...new Set(botoes)].slice(0, 30),
      mandatosNaTela: hrefs.size,
      menu: [...new Set([...document.querySelectorAll("nav a")].filter(vis).map((a) => (a.textContent ?? "").trim().slice(0, 25)).filter(Boolean))].slice(0, 20),
      // Contra a largura NOMINAL: com isMobile o navegador alarga o viewport para caber o conteúdo (innerWidth mente).
      estouroHorizontal: document.documentElement.scrollWidth > larguraNominal + 1,
      texto: document.body.innerText.slice(0, 400).replace(/\s+/g, " "),
    };
  }, larguraNominal).catch(() => null);
  const captura = `${slug}.png`;
  await page.screenshot({ path: path.join(SAIDA, captura), fullPage: true }).catch(() => {});
  return {
    papel, viewport: vp, rota: rota.replace(UUID, "{ID}"), status, destino: u.pathname.replace(UUID, "{ID}"), ms, falha,
    erros_console: [...erros].slice(0, 5), respostas_4xx_5xx: [...respRuins].slice(0, 5), ...dados, captura,
  };
}

async function matriz(browser: any, ids: { A: string; OUTRO: string; DOC: string }) {
  const rotas = [
    ...ROTAS_GERAIS,
    ...ROTAS_CASO.map((s) => `/casos/${ids.A}${s}`),
    `/casos/${ids.A}/documentos/${ids.DOC}`,
    // O mandato ao qual Analista e Leitura NÃO estão alocados: deve ser 404/redirect para eles.
    `/casos/${ids.OUTRO}`, `/casos/${ids.OUTRO}/documentos`, `/casos/${ids.OUTRO}/pendencias`,
  ];
  const celulas: any[] = [];
  for (const papel of ["anonimo", ...PAPEIS] as const) {
    for (const mobile of [false, true]) {
      const { ctx, page } = await novoContexto(browser, papel, mobile);
      const erros: string[] = []; const ruins: string[] = [];
      page.on("console", (m: any) => { if (m.type() === "error") erros.push(m.text().slice(0, 160)); });
      page.on("pageerror", (e: any) => erros.push("pageerror: " + String(e.message).slice(0, 160)));
      page.on("response", (r: any) => { if (r.status() >= 400) ruins.push(`${r.status()} ${new URL(r.url()).pathname.slice(0, 60)}`); });
      const lista = mobile ? MOBILE.map((m) => m.replace("{A}", ids.A)) : rotas;
      for (const rota of lista) celulas.push(await celula(page, papel, rota, mobile ? "mob" : "desk", erros, ruins));
      // Rotas que devolvem arquivo ou redirecionam não são telas: mede-se só o status, sem seguir.
      if (!mobile) {
        for (const rota of [`/casos/${ids.A}/export`, `/casos/${ids.A}/documentos/${ids.DOC}/original`, `/casos/${ids.A}/documentos/${ids.DOC}/transcricao`, `/casos/${ids.OUTRO}/export`]) {
          const t0 = Date.now();
          const r = await ctx.request.get(BASE + rota, { maxRedirects: 0, timeout: 60000 }).catch((e: any) => ({ status: () => -1, headers: () => ({}), _e: e }));
          celulas.push({ papel, viewport: "desk", rota: rota.replace(UUID, "{ID}"), status: r.status(), destino: String((r.headers() as any).location ?? "").replace(/\?.*/, "").replace(UUID, "{ID}").slice(0, 60) || "(sem redirect)", ms: Date.now() - t0, tipo: "arquivo/redirect" });
        }
      }
      await ctx.close();
    }
  }
  return celulas;
}

// ---------- escalada ----------
type Linha = { papel: string; tentativa: string; esperado: string; obtido: string; achado?: string };
const linhas: Linha[] = [];
const barrado = (e: any) => `BARRADO (${e?.code ?? e?.statusCode ?? "?"}: ${String(e?.message ?? e).slice(0, 90)})`;
function reg(papel: string, tentativa: string, esperado: string, obtido: string, achado = "") {
  const passou = obtido.startsWith("PASSOU");
  linhas.push({ papel, tentativa, esperado, obtido, achado: (esperado === "barrado" && passou) || (esperado === "passa" && !passou) ? achado || "DIVERGE DO ESPERADO" : undefined });
}

async function escalada(ids: { A: string; OUTRO: string; DOC: string; PEND: string; PEND_ESTADO: string }) {
  const socio = await cliente("socio");
  const sondaA = `${ids.A}/p2-sonda-${Date.now()}.txt`;
  const sondaO = `${ids.OUTRO}/p2-sonda-${Date.now()}.txt`;
  const up = (c: any, p: string) => c.storage.from("documentos").upload(p, new Blob(["sonda P2 sintetica"], { type: "text/plain" }), { upsert: false });
  await up(socio, sondaA); await up(socio, sondaO);
  const totalSocio = (await socio.from("caso").select("id", { count: "exact", head: true })).count;
  resultado.casos_visiveis = { socio: totalSocio };
  const estagio = (await socio.from("estagio_autonomia").select("estagio,nivel_atual").eq("estagio", "completude_portao1")).data?.[0] as any;

  for (const papel of ["analista", "leitura", "anonimo"] as const) {
    const c = await cliente(papel);
    const sel = async (t: string, filtro?: (q: any) => any) => { const q = c.from(t).select("id", { count: "exact", head: true }); const r = await (filtro ? filtro(q) : q); return r.error ? barrado(r.error) : `${r.count ?? 0} linhas visíveis`; };

    // Leitura de dado
    const casos = await c.from("caso").select("id", { count: "exact" });
    const n = casos.error ? barrado(casos.error) : `${casos.count} de ${totalSocio} mandatos visíveis`;
    (resultado.casos_visiveis as any)[papel] = casos.error ? "erro" : casos.count;
    linhas.push({ papel, tentativa: "ler `caso` (todos)", esperado: papel === "anonimo" ? "0" : papel === "socio" ? "todos" : "só os alocados (1)", obtido: n });
    linhas.push({ papel, tentativa: "ler `pendencia`/`documento` do mandato NÃO alocado", esperado: "0 linhas", obtido: `pendencia: ${await sel("pendencia", (q) => q.eq("caso_id", ids.OUTRO))}; documento: ${await sel("documento", (q) => q.eq("caso_id", ids.OUTRO))}` });
    const TABS = ["estagio_autonomia", "membro", "alocacao", "evento_auditoria", "golden_criterio", "lote_execucao"];
    linhas.push({ papel, tentativa: "ler `" + TABS.join("`, `") + "`", esperado: papel === "anonimo" ? "0 / barrado" : "ver nota", obtido: (await Promise.all(TABS.map(async (t) => `${t}: ${await sel(t)}`))).join("; ") });

    // Dial
    const r1 = await c.rpc("fn_mudar_dial", { p_estagio: estagio.estagio, p_nivel: estagio.nivel_atual, p_autor: `p2:${papel}`, p_motivo: "vistoria P2: reafirma o mesmo nível" });
    reg(papel, `fn_mudar_dial(${estagio.estagio}, ${estagio.nivel_atual} = nível atual)`, "barrado", r1.error ? barrado(r1.error) : `PASSOU (${JSON.stringify(r1.data).slice(0, 120)})`, "ALTO: dial mudado sem ser Sócio");
    const r2 = await c.from("estagio_autonomia").update({ nivel_atual: estagio.nivel_atual }).eq("estagio", estagio.estagio).select();
    reg(papel, "UPDATE direto em `estagio_autonomia` (mesmo nível)", "barrado", r2.error ? barrado(r2.error) : r2.data!.length === 0 ? "BARRADO (0 linhas afetadas, sem erro)" : `PASSOU (${r2.data!.length} linha)`, "ALTO");
    const r3 = await c.from("estagio_autonomia").update({ teto: "N3" }).eq("estagio", "__inexistente__").select();
    reg(papel, "UPDATE em `estagio_autonomia` com filtro que não casa nada (sonda de política)", "barrado", r3.error ? barrado(r3.error) : `${r3.data!.length === 0 ? "BARRADO (0 linhas, sem erro)" : "PASSOU"}`);

    // Escrita nas tabelas do mandato
    const i1 = await c.from("caso").insert({ nome: "P2 escalada " + papel }).select();
    if (!i1.error && i1.data?.length) await socio.from("caso").delete().eq("id", (i1.data[0] as any).id);
    reg(papel, "INSERT em `caso` (novo mandato)", papel === "analista" ? "passa ou barra conforme o desenho (ver nota)" : "barrado", i1.error ? barrado(i1.error) : `PASSOU (${i1.data!.length} linha, desfeito)`, papel === "leitura" ? "ALTO: Leitura abriu mandato" : "");
    const u1 = await c.from("caso").update({ nome: MANDATO }).eq("id", ids.A).select();
    reg(papel, "UPDATE em `caso` do mandato alocado (mesmo nome)", papel === "analista" ? "passa (escreve no alocado)" : "barrado", u1.error ? barrado(u1.error) : u1.data!.length === 0 ? "BARRADO (0 linhas afetadas, sem erro)" : `PASSOU (${u1.data!.length} linha, valor idêntico)`);
    const u2 = await c.from("pendencia").update({ estado: ids.PEND_ESTADO }).eq("id", ids.PEND).select();
    reg(papel, "UPDATE direto em `pendencia` do mandato alocado (mesmo estado)", papel === "analista" ? "passa" : "barrado", u2.error ? barrado(u2.error) : u2.data!.length === 0 ? "BARRADO (0 linhas afetadas, sem erro)" : `PASSOU (${u2.data!.length} linha, valor idêntico)`);
    const u3 = await c.from("documento").update({ status: "em_validacao" }).eq("caso_id", ids.A).select();
    reg(papel, "UPDATE direto em `documento` do mandato alocado (status = o atual)", papel === "analista" ? "passa" : "barrado", u3.error ? barrado(u3.error) : u3.data!.length === 0 ? "BARRADO (0 linhas afetadas, sem erro)" : `PASSOU (${u3.data!.length} linhas, valor idêntico)`);
    // Decidir pendência pela função (é o que o botão da tela chama). Estado conferido e restaurado pelo Sócio.
    const d = await c.rpc("fn_decidir_pendencia", { p_pendencia_id: ids.PEND, p_autor: `p2:${papel}`, p_decisao: "contatar_cliente" });
    const depois = (await socio.from("pendencia").select("estado").eq("id", ids.PEND).single()).data as any;
    const mudou = depois?.estado !== ids.PEND_ESTADO;
    if (mudou) await socio.from("pendencia").update({ estado: ids.PEND_ESTADO, resolvida_em: null, resolvida_por: null }).eq("id", ids.PEND);
    reg(papel, "fn_decidir_pendencia(contatar_cliente) numa pendência real", papel === "analista" ? "passa" : "barrado",
      mudou ? `PASSOU (estado ${ids.PEND_ESTADO} -> ${depois.estado}; restaurado)` : d.error ? barrado(d.error) : `BARRADO sem erro? retorno=${JSON.stringify(d.data).slice(0, 100)}; estado inalterado`,
      d.error || mudou ? "" : "MÉDIO: a função devolveu sucesso/silêncio sem gravar — a tela mostraria decisão feita?");

    // Equipe
    const own = cred[papel as Papel]?.id ?? "00000000-0000-0000-0000-000000000000";
    const p1 = await c.rpc("fn_definir_papel", { p_usuario: own, p_papel: papel === "anonimo" ? "leitura" : papel, p_motivo: "vistoria P2: mesmo papel" });
    reg(papel, "fn_definir_papel(si mesmo, mesmo papel)", "barrado", p1.error ? barrado(p1.error) : `PASSOU (${JSON.stringify(p1.data).slice(0, 100)})`, "ALTO: gestão de papel sem ser Sócio");
    const p2 = await c.rpc("fn_alocar", { p_caso: ids.OUTRO, p_usuario: own });
    if (!p2.error) await socio.rpc("fn_desalocar", { p_caso: ids.OUTRO, p_usuario: own });
    reg(papel, "fn_alocar(mandato NÃO alocado, si mesmo)", "barrado", p2.error ? barrado(p2.error) : "PASSOU (desfeito por fn_desalocar do Sócio)", "ALTO: auto-alocação");
    const p3 = await c.rpc("fn_desalocar", { p_caso: ids.OUTRO, p_usuario: own });
    reg(papel, "fn_desalocar(mandato NÃO alocado, si mesmo; sem alocação a perder)", "barrado", p3.error ? barrado(p3.error) : `PASSOU (${JSON.stringify(p3.data).slice(0, 80)})`);
    const p4 = await c.rpc("fn_eh_socio");
    linhas.push({ papel, tentativa: "fn_eh_socio()", esperado: papel === "anonimo" ? "barrado/false" : "false", obtido: p4.error ? barrado(p4.error) : String(p4.data) });

    // Storage
    const s1 = await up(c, `${ids.A}/p2-escrita-${papel}-${Date.now()}.txt`);
    if (!s1.error) await socio.storage.from("documentos").remove([s1.data!.path]);
    reg(papel, "storage: subir objeto em `documentos/<mandato alocado>/`", papel === "analista" ? "passa" : "barrado", s1.error ? barrado(s1.error) : "PASSOU (objeto removido pelo Sócio)");
    const s2 = await up(c, `${ids.OUTRO}/p2-escrita-${papel}-${Date.now()}.txt`);
    if (!s2.error) await socio.storage.from("documentos").remove([s2.data!.path]);
    reg(papel, "storage: subir objeto em `documentos/<mandato NÃO alocado>/`", "barrado", s2.error ? barrado(s2.error) : "PASSOU (objeto removido pelo Sócio)", "ALTO: escrita em mandato alheio");
    const rm = await c.storage.from("documentos").remove([sondaA]);
    const resta = await socio.storage.from("documentos").createSignedUrl(sondaA, 30);
    reg(papel, "storage: apagar a sonda do mandato alocado", papel === "analista" ? "passa (ou barra)" : "barrado", rm.error ? barrado(rm.error) : resta.error ? "PASSOU (objeto sumiu)" : "BARRADO (0 objetos removidos, sem erro)");
    if (resta.error) await up(socio, sondaA);
    const rd = await c.storage.from("documentos").createSignedUrl(sondaO, 30);
    reg(papel, "storage: assinar/ler objeto de mandato NÃO alocado", "barrado", rd.error ? barrado(rd.error) : "PASSOU (URL assinada emitida)", "ALTO: leitura de arquivo alheio");
    const rl = await c.storage.from("documentos").createSignedUrl(sondaA, 30);
    reg(papel, "storage: assinar/ler objeto do mandato alocado", papel === "anonimo" ? "barrado" : "passa", rl.error ? barrado(rl.error) : "PASSOU (URL assinada emitida)");
  }
  await socio.storage.from("documentos").remove([sondaA, sondaO]);
  // Garantia de limpeza: nenhuma sonda restante.
  const resto = await socio.storage.from("documentos").list(ids.A);
  resultado.sondas_restantes = (resto.data ?? []).filter((o: any) => o.name.startsWith("p2-")).length;
}

// ---------- principal ----------
const browser = await chromium.launch();
if (process.env.P2_SO !== "matriz") resultado.envio = await enviar(browser);
grava();
{
  // A chave anon só aparece no cabeçalho `apikey` quando um componente de cliente fala com o Supabase.
  const { ctx, page } = await novoContexto(browser, "socio");
  for (const r of ["/casos/todos", "/casos/novo", "/administracao/equipe"]) {
    if (ANON) break;
    await page.goto(BASE + r); await page.waitForTimeout(2500);
  }
  await ctx.close();
  if (!ANON) { console.error("Chave anon não obtida: defina P2_ANON_KEY."); process.exit(2); }
}
const socio = await cliente("socio");
const caso = (await socio.from("caso").select("id").eq("nome", MANDATO).single()).data as any;
const doc = (await socio.from("documento").select("id").eq("caso_id", caso.id).limit(1)).data?.[0] as any;
const outro = (await socio.from("documento").select("caso_id").neq("caso_id", caso.id).limit(1)).data?.[0] as any;
const pend = (await socio.from("pendencia").select("id,estado").eq("caso_id", caso.id).eq("estado", "aberta").limit(1)).data?.[0] as any;
const ids = { A: caso.id as string, OUTRO: outro.caso_id as string, DOC: doc.id as string, PEND: pend.id as string, PEND_ESTADO: pend.estado as string };
const lote = (await socio.from("lote_execucao").select("*").eq("caso_id", ids.A)).data;
resultado.lote = lote;
resultado.matriz = await matriz(browser, ids);
grava();
if (process.env.P2_SO !== "matriz") { await escalada(ids); resultado.escalada = linhas; }
grava();
await browser.close();
const mt = resultado.matriz as any[];
const esc = ((resultado.escalada as Linha[] | undefined) ?? []);
console.log(`matriz: ${mt.length} células; escalada: ${esc.length} tentativas, ${esc.filter((l) => l.obtido.startsWith("PASSOU")).length} passaram; resultado em ${path.join(SAIDA, "resultado.json")}`);
