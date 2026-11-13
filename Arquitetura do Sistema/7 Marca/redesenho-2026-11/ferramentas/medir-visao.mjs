import pw from '/opt/node-tools/node_modules/playwright/index.js'; const { chromium } = pw;
const base = process.argv[2];
const browser = await chromium.launch();
const page = await (await browser.newContext({ viewport: { width: 1440, height: 900 } })).newPage();
await page.goto(base + '/login', { waitUntil: 'networkidle' });
await page.fill('input[name=email]', process.env.PORTAL_EMAIL);
await page.fill('input[name=senha], input[type=password]', process.env.PORTAL_SENHA);
await page.click('button[type=submit]');
await page.waitForURL((u) => !u.pathname.startsWith('/login'), { timeout: 30000 });
for (let i = 0; i < 3; i++) {
  const t0 = Date.now();
  await page.goto(base + '/casos/5469db1d-4862-4d16-9041-8bcd872d1505', { waitUntil: 'networkidle' });
  const nav = await page.evaluate(() => { const n = performance.getEntriesByType('navigation')[0]; return { ttfb: Math.round(n.responseStart), dcl: Math.round(n.domContentLoadedEventEnd) }; });
  console.log(JSON.stringify({ url: page.url().replace(base, ''), total_ms: Date.now() - t0, ...nav }));
}
await browser.close();
