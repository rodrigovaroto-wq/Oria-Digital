const { chromium } = require('/opt/node-tools/node_modules/playwright');
const OUT = '/tmp/claude-0/-home-user-Oria-Digital/1bde83df-8b1b-57fa-a9fd-ed552032ca1e/scratchpad/item2/';
const EMAIL = process.env.PORTAL_EMAIL, SENHA = process.env.PORTAL_SENHA;
const ID = '5469db1d-4862-4d16-9041-8bcd872d1505';
const ROTAS = { casos: '/casos', visao: '/casos/' + ID };
const SERV = { antes: 'http://localhost:3101', depois: 'http://localhost:3102' };

const INIT = () => {
  window.__cls = 0; window.__t = {};
  new PerformanceObserver((l) => { for (const e of l.getEntries()) if (!e.hadRecentInput) window.__cls += e.value; })
    .observe({ type: 'layout-shift', buffered: true });
  const pendente = () => document.querySelectorAll('[role="status"]').length &&
    [...document.querySelectorAll('[role="status"]')].some((n) => n.querySelector('.bg-tinta-100'));
  let viuEsqueleto = false;
  const tick = () => {
    const p = !!pendente();
    if (p) { viuEsqueleto = true; window.__t.ultimo = null; }
    else if (viuEsqueleto && window.__t.ultimo == null) window.__t.ultimo = performance.now();
    if (!window.__t.h1 && document.querySelector('h1')) window.__t.h1 = performance.now();
  };
  new MutationObserver(tick).observe(document, { childList: true, subtree: true });
  document.addEventListener('DOMContentLoaded', tick);
};

async function logar(browser, base) {
  const ctx = await browser.newContext();
  const p = await ctx.newPage();
  await p.goto(base + '/login');
  await p.fill('input[name=email]', EMAIL);
  await p.fill('input[name=password]', SENHA);
  await Promise.all([p.waitForURL((u) => !u.pathname.startsWith('/login'), { timeout: 60000 }), p.click('button[type=submit]')]);
  const st = await ctx.storageState();
  await ctx.close();
  return st;
}

(async () => {
  const modo = process.argv[2];
  const browser = await chromium.launch();
  const estado = {};
  for (const k of Object.keys(SERV)) estado[k] = await logar(browser, SERV[k]);
  if (modo === 'medir') {
    const res = [];
    for (let i = 0; i < 3; i++) for (const rota of Object.keys(ROTAS)) for (const k of ['antes', 'depois']) {
      const ctx = await browser.newContext({ storageState: estado[k], viewport: { width: 1440, height: 900 } });
      await ctx.addInitScript(INIT);
      const p = await ctx.newPage();
      await p.goto(SERV[k] + ROTAS[rota], { waitUntil: 'load', timeout: 90000 });
      await p.waitForTimeout(1500);
      const m = await p.evaluate(() => {
        const n = performance.getEntriesByType('navigation')[0];
        const fcp = performance.getEntriesByType('paint').find((e) => e.name === 'first-contentful-paint');
        return { ttfb: n.responseStart, dcl: n.domContentLoadedEventEnd, load: n.loadEventEnd, fcp: fcp ? fcp.startTime : null,
          h1: window.__t.h1 ?? null, ultimo: window.__t.ultimo ?? null, cls: window.__cls,
          pendentes: [...document.querySelectorAll('[role="status"]')].filter((x) => x.querySelector('.bg-tinta-100')).length };
      });
      res.push({ rota, k, ...m });
      await ctx.close();
    }
    console.log(JSON.stringify(res));
  } else {
    // capturas, só do DEPOIS
    for (const [nome, rota] of Object.entries(ROTAS)) {
      const ctx = await browser.newContext({ storageState: estado.depois, viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
      const p = await ctx.newPage();
      await p.goto(SERV.depois + rota, { waitUntil: 'commit' });
      await p.waitForTimeout(250);
      await p.screenshot({ path: OUT + nome + '-250ms.png' });
      await p.waitForFunction(() => ![...document.querySelectorAll('[role="status"]')].some((n) => n.querySelector('.bg-tinta-100')), null, { timeout: 90000 });
      await p.waitForTimeout(900);
      await p.screenshot({ path: OUT + nome + '-final.png' });
      await ctx.close();
    }
    const ctx = await browser.newContext({ storageState: estado.depois, viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
    const p = await ctx.newPage();
    await p.goto(SERV.depois + '/casos', { waitUntil: 'commit' });
    await p.waitForFunction(() => document.querySelector('h1') && ![...document.querySelectorAll('[role="status"]')].some((n) => n.querySelector('.bg-tinta-100')), null, { timeout: 90000 });
    await p.waitForTimeout(900);
    await p.screenshot({ path: OUT + 'casos-390-final.png' });
    await ctx.close();
  }
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
