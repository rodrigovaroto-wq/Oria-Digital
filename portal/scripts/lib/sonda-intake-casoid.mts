// Sonda de `verificar-mensagem-de-falha.mts`: executa o POST de /api/intake com `casoId` vindo como ARQUIVO e
// imprime {status, error} em JSON. Vive em processo próprio porque a rota importa por `@/...` e o `tsx` só resolve
// esse alias com o tsconfig do portal (o CI roda as suítes a partir da raiz do repositório).
process.env.N8N_INTAKE_FORM_URL = "https://127.0.0.1:9/form";
const { POST } = await import("../../src/app/api/intake/route.ts");
const fd = new FormData();
fd.append("casoId", new File(["x"], "a.txt"));
fd.append("arquivos", new File(["x"], "b.txt"));
const r = await POST(new Request("https://x/api/intake", { method: "POST", body: fd }));
const corpo = await r.json();
console.log(JSON.stringify({ status: r.status, error: corpo.error }));
