// ENVIA UM BOOK DE TESTE INTEIRO PELO PORTAL DE PRODUÇÃO, COMO SÓCIO (P4: corpus de regressão).
//
// Por que pelo portal e não direto no n8n: o envio de verdade passa pelo token assinado do portal
// (v2, por caso_id), pelo roteamento de tamanho (proxy × direto) e pelo Form do n8n. Mandar direto
// ao webhook pularia exatamente os estágios que a P3 mudou. Este script faz o que o Sócio faz na tela.
//
// O que ele NÃO faz: medir a leitura. Ele só cria o mandato, sobe os arquivos e espera o lote
// FECHAR no banco (lote_execucao.fechado_em). A medição é `Verificação/linha-de-base.mts`.
// Escreve em produção e gasta a rodada da OpenAI: só com autorização do dono (D6, teto US$ 5/book).
//
// Uso (nunca `npx`):
//   ENVIO_USUARIOS=<arquivo "papel uuid senha" por linha> ENVIO_PASTA=<pasta com os arquivos> \
//   ENVIO_MANDATO="<nome do mandato novo>" SUPABASE_URL=https://<ref>.supabase.co ENVIO_SAIDA=<pasta> \
//   ENVIO_PLAYWRIGHT=<pasta do pacote playwright, se require('playwright') não resolver> \
//   ENVIO_LOTE_MAX=<arquivos por envio, padrão 20> \
//   ./portal/node_modules/.bin/tsx Verificação/enviar-book.mts
//
// Lotes: o orçamento do n8n RECUSA o lote inteiro que passa do teto (não existe "roda metade"),
// então a pasta é mandada em envios de até ENVIO_LOTE_MAX arquivos, um depois do outro, cada um
// esperando o anterior fechar. Um envio recusado pelo orçamento é registrado como recusado, não
// como lido (regra 7).
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";

const exigir = (n: string): string => {
  const v = process.env[n];
  if (!v) { console.error(`Falta a variável de ambiente ${n}.`); process.exit(2); }
  return v;
};
const PASTA = exigir("ENVIO_PASTA");
const MANDATO = exigir("ENVIO_MANDATO");
const SAIDA = exigir("ENVIO_SAIDA");
const ARQ_USUARIOS = exigir("ENVIO_USUARIOS");
const BASE = process.env.ENVIO_BASE ?? "https://tratamento-dados-financeiros.vercel.app";
const LOTE_MAX = Number(process.env.ENVIO_LOTE_MAX ?? "20");
// Mesmo teto de espera para todo envio: o lote real de 15 documentos do Valtra levou ~20 min.
const ESPERA_MAX_MS = Number(process.env.ENVIO_ESPERA_MIN ?? "45") * 60_000;
fs.mkdirSync(SAIDA, { recursive: true });

const req = createRequire(import.meta.url);
const { chromium } = req(process.env.ENVIO_PLAYWRIGHT ?? "playwright");
const { createClient } = createRequire(path.resolve(import.meta.dirname, "../portal/package.json"))("@supabase/supabase-js");

// Só os formatos que o cliente manda; os JSON de gabarito/métrica e o guia ficam de fora.
const EXT = /\.(pdf|xlsx|xls|csv|png|jpe?g)$/i;
const arquivos = fs.readdirSync(PASTA).filter((f) => EXT.test(f)).sort().map((f) => path.join(PASTA, f));
if (arquivos.length === 0) { console.error(`Nenhum arquivo de cliente em ${PASTA}.`); process.exit(2); }

const senha = fs.readFileSync(ARQ_USUARIOS, "utf8").trim().split("\n")
  .map((l) => l.trim().split(/\s+/)).find(([p]) => p === "socio")?.[2];
if (!senha) { console.error("Sem a linha do Sócio no arquivo de usuários."); process.exit(2); }
const EMAIL = "rodrigo.varoto+socio@oriapartners.com";

let ANON = process.env.ENVIO_ANON_KEY ?? "";
// LOCALE UTF-8 NO CHROMIUM. Medido em 09/11: com locale POSIX (o do container) o `setInputFiles` descarta
// CALADO todo caminho com acento — 3 de 11 arquivos do book-espelho chegavam ao input, e a tela dizia
// "3 arquivo(s) enviado(s)". Era esse o "arquivo com acento some entre o portal e o n8n" de 07/11: nunca
// foi o portal nem o n8n (o encaminhamento, reproduzido à parte, entrega 11 de 11). Com C.UTF-8, 11 de 11.
const browser = await chromium.launch({ env: { ...process.env, LC_ALL: "C.UTF-8" } });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
await ctx.addInitScript("window.__name = (f) => f;");
const page = await ctx.newPage();
page.on("request", (r: any) => { const k = r.headers()["apikey"]; if (k && !ANON) ANON = k; });
await page.goto(BASE + "/login");
await page.fill("input[name=email]", EMAIL);
await page.fill("input[name=password]", senha);
await Promise.all([page.waitForURL((x: URL) => !x.pathname.startsWith("/login"), { timeout: 30000 }), page.click("button[type=submit]")]);

// Cria o mandato uma vez; os envios seguintes entram pela tela "adicionar" do mesmo caso_id.
await page.goto(BASE + "/casos/novo");
await page.fill("#mandato", MANDATO);
await Promise.all([page.waitForURL(/\/casos\/[0-9a-f-]{36}\/adicionar/, { timeout: 30000 }), page.click("button[type=submit]")]);
const casoId = page.url().match(/\/casos\/([0-9a-f-]{36})\//)![1];
if (!ANON) { await page.goto(BASE + "/casos/todos"); await page.waitForTimeout(2500); }
if (!ANON) { console.error("Chave anon não obtida: defina ENVIO_ANON_KEY."); process.exit(2); }

const sb = createClient(exigir("SUPABASE_URL"), ANON, { auth: { persistSession: false, autoRefreshToken: false } });
const { error: erroLogin } = await sb.auth.signInWithPassword({ email: EMAIL, password: senha });
if (erroLogin) { console.error("login por API falhou: " + erroLogin.message); process.exit(2); }

const lotesDoCaso = async () => ((await sb.from("lote_execucao").select("id,criado_em,fechado_em,documentos,documentos_com_falha,custo_total_usd").eq("caso_id", casoId)).data ?? []) as any[];
const espera = (ms: number) => new Promise((r) => setTimeout(r, ms));

const grupos: string[][] = [];
for (let i = 0; i < arquivos.length; i += LOTE_MAX) grupos.push(arquivos.slice(i, i + LOTE_MAX));
const envios: any[] = [];

// A ORDEM É SEMÂNTICA: um envio só começa quando o anterior fechou (cota por minuto do provedor e
// o orçamento por lote são medidos por envio). Por isso o laço espera, em vez de disparar tudo.
for (const [n, grupo] of grupos.entries()) {
  const antes = new Set((await lotesDoCaso()).map((l) => l.id));
  await page.goto(`${BASE}/casos/${casoId}/adicionar`);
  await page.waitForTimeout(1500);
  await page.setInputFiles("input[type=file]", grupo);
  const t0 = Date.now();
  await page.click('form button[type=submit]:has-text("Enviar")');
  await page.waitForTimeout(15000);
  await page.screenshot({ path: path.join(SAIDA, `envio-${n + 1}.png`), fullPage: true });
  let lote: any = null;
  while (Date.now() - t0 < ESPERA_MAX_MS) {
    lote = (await lotesDoCaso()).find((l) => !antes.has(l.id)) ?? null;
    if (lote?.fechado_em) break;
    await espera(30_000);
  }
  // Fechar não basta: o lote pode fechar com MENOS documentos do que os arquivos enviados (medido em 07/11:
  // 11 enviados, 3 registrados, e o estado dizia "fechado" — regra 7). Confere arquivos × documentos do lote.
  const estado = !lote ? "SEM LOTE (recusado antes do orçamento, ou o envio não chegou)"
    : !lote.fechado_em ? `NÃO FECHOU em ${ESPERA_MAX_MS / 60000} min`
    : Number(lote.documentos) !== grupo.length ? `fechado INCOMPLETO: ${lote.documentos} de ${grupo.length} arquivo(s) viraram documento`
    : "fechado";
  envios.push({ envio: n + 1, arquivos: grupo.map((g) => path.basename(g)), estado, lote, minutos: Math.round((Date.now() - t0) / 6000) / 10 });
  fs.writeFileSync(path.join(SAIDA, "envios.json"), JSON.stringify({ mandato: MANDATO, caso_id: casoId, envios }, null, 2));
  console.log(`envio ${n + 1}/${grupos.length}: ${grupo.length} arquivo(s) — ${estado}`);
}
await browser.close();
const incompletos = envios.filter((e) => e.estado !== "fechado").length;
if (incompletos > 0) { console.error(`${incompletos} envio(s) NÃO fecharam completos.`); process.exitCode = 1; }
console.log(`caso_id ${casoId}; resultado em ${path.join(SAIDA, "envios.json")}`);
