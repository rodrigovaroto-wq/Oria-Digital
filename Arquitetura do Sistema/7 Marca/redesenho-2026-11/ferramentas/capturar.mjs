// Captura de linha de base: telas em 3 larguras + peso e tempo de cada página.
// Uso: PORTAL_EMAIL=.. PORTAL_SENHA=.. node capturar.mjs <saida> [base]
import pw from '/opt/node-tools/node_modules/playwright/index.js'; const { chromium } = pw;
import fs from 'node:fs';

const out = process.argv[2];
const base = process.argv[3] || 'http://localhost:3100';
fs.mkdirSync(out, { recursive: true });
const larguras = [[1440, 900], [768, 1024], [390, 844]];
const browser = await chromium.launch();

async function medir(page, url) {
  let bytes = 0, reqs = 0;
  const onResp = async (r) => { reqs++; try { const b = await r.body(); bytes += b.length; } catch {} };
  page.on('response', onResp);
  const t0 = Date.now();
  await page.goto(url, { waitUntil: 'networkidle' });
  const total = Date.now() - t0;
  const nav = await page.evaluate(() => {
    const n = performance.getEntriesByType('navigation')[0];
    const lcp = performance.getEntriesByType('largest-contentful-paint').at(-1);
    return { ttfb: Math.round(n.responseStart), dcl: Math.round(n.domContentLoadedEventEnd), lcp: lcp ? Math.round(lcp.startTime) : null };
  });
  page.off('response', onResp);
  return { url: page.url(), ms_ate_rede_parada: total, ...nav, requisicoes: reqs, kb: Math.round(bytes / 1024) };
}

const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
const page = await ctx.newPage();
const metricas = {};

// login (deslogado)
for (const [w, h] of larguras) {
  await page.setViewportSize({ width: w, height: h });
  const m = await medir(page, base + '/login');
  if (w === 1440) metricas.login = m;
  await page.screenshot({ path: `${out}/login-${w}.png`, fullPage: true });
}
await page.setViewportSize({ width: 1440, height: 900 });
await page.fill('input[name=email]', process.env.PORTAL_EMAIL);
await page.fill('input[name=password]', process.env.PORTAL_SENHA);
await Promise.all([page.waitForURL((u) => !u.pathname.startsWith('/login'), { timeout: 30000 }), page.click('button[type=submit]')]);
await page.waitForLoadState('networkidle');
const entrada = new URL(page.url()).pathname;

// achar o primeiro mandato a partir da lista
await page.goto(base + '/casos', { waitUntil: 'networkidle' });
const href = await page.evaluate(() => [...document.querySelectorAll('a[href^="/casos/"]')].map((a) => a.getAttribute('href')).find((h) => /^\/casos\/[0-9a-f-]{8,}/i.test(h)));
const caso = href ? href.split('/').slice(0, 3).join('/') : null;

const telas = { entrada: entrada === '/login' ? '/' : entrada, casos: '/casos' };
if (caso) telas.detalhe = caso;
for (const [nome, rota] of Object.entries(telas)) {
  for (const [w, h] of larguras) {
    await page.setViewportSize({ width: w, height: h });
    const m = await medir(page, base + rota);
    if (w === 1440) metricas[nome] = m;
    await page.screenshot({ path: `${out}/${nome}-${w}.png`, fullPage: true });
  }
}
fs.writeFileSync(`${out}/metricas.json`, JSON.stringify({ entrada_pos_login: entrada, caso, metricas }, null, 2));
console.log(JSON.stringify({ entrada_pos_login: entrada, caso, metricas }, null, 2));
await browser.close();
