const { chromium } = require("/opt/node-tools/node_modules/playwright");
(async () => {
  const b = await chromium.launch({ executablePath: "/usr/bin/google-chrome", args: ["--no-sandbox"] });
  const ctx = await b.newContext({ viewport: { width: 1440, height: 900 } });
  const p = await ctx.newPage();
  await p.goto("http://localhost:3111/login");
  await p.fill("#email", process.env.PORTAL_EMAIL);
  await p.fill("input[name=password]", process.env.PORTAL_SENHA);
  await Promise.all([p.waitForURL(/\/casos/, { timeout: 30000 }), p.click("button[type=submit]")]);
  await p.goto("http://localhost:3111/casos/todos", { waitUntil: "networkidle" });
  const ids = await p.$$eval("a[href^='/casos/']", (as) => [...new Set(as.map((a) => a.getAttribute("href")).filter((h) => /^\/casos\/[0-9a-f-]{36}$/.test(h)))]);
  console.log("mandatos:", ids.length);
  const out = [];
  for (const href of ids.slice(0, 25)) {
    const q = await ctx.newPage();
    await q.addInitScript(() => {
      window.__cls = 0; window.__shifts = [];
      new PerformanceObserver((l) => { for (const e of l.getEntries()) if (!e.hadRecentInput) { window.__cls += e.value; window.__shifts.push(e.value.toFixed(4)); } }).observe({ type: "layout-shift", buffered: true });
    });
    await q.goto("http://localhost:3111" + href, { waitUntil: "networkidle" });
    await q.waitForTimeout(1500);
    const r = await q.evaluate(() => ({ cls: window.__cls, shifts: window.__shifts, fatos: document.body.innerText.includes("O que os documentos dizem") ? "com-secao" : "sem-secao", falha: document.body.innerText.includes("Fatos dos documentos não lidos") }));
    out.push(href.slice(-8) + " " + JSON.stringify(r));
    await q.close();
  }
  console.log(out.join("\n"));
  await b.close();
})();
