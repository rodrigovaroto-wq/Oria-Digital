import { ehCliente, ehEstoque, ehFornecedor } from "../../../portal/src/lib/modelo-institucional.ts";
const REF = process.env.SUPABASE_URL!.replace(/^https:\/\/([^.]+)\..*/, "$1");
async function q(sql: string): Promise<any[]> {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, { method: "POST",
    headers: { Authorization: `Bearer ${process.env.SUPABASE_ACCESS_TOKEN}`, "Content-Type": "application/json" }, body: JSON.stringify({ query: sql }) });
  const j = await r.json(); if (!Array.isArray(j)) throw new Error(JSON.stringify(j)); return j;
}
const C = "03a66ab6-f0c1-45df-8c37-257c42298fc4", ENT = "MOTO AGRICOLA VOLKWEIS LTDA", AUT = "claude:s105 (a pedido do dono)";
const lit = (s: string | null) => s === null ? "null" : `'${s.replace(/'/g, "''")}'`;
const anos = (v: number[]) => JSON.stringify(Object.fromEntries(v.map((x, i) => [String(2026 + i), x])));
const PREMISSAS: Array<[string, number[], string]> = [
  ["IPCA", [5, 4.288, 3.8, 3.5, 3.5], "focus"],
  ["CRESC_NOMINAL", [0, 5, 8, 8, 6], "digitado"],
  ["CUSTO_VARIAVEL", [85, 82, 80, 79, 78], "digitado"],
  ["SGA_PCT", [20, 17, 15, 14, 13], "digitado"],
  ["PMR", [200, 150, 110, 90, 75], "digitado"],
  ["PME", [400, 300, 220, 180, 160], "digitado"],
  ["PMP", [150, 120, 100, 90, 85], "digitado"],
  ["ALIQUOTA", [34, 34, 34, 34, 34], "digitado"],
  ["TAXA_DIVIDA", [18, 16, 15, 14, 14], "digitado"],
  ["CAPEX_PCT", [1.5, 1.5, 1.5, 1.5, 1.5], "digitado"],
];
for (const [cod, v, orig] of PREMISSAS) {
  const r = await q(`select fn_ativar_premissa('${C}', '${cod}', '${anos(v)}'::jsonb, '${orig}', ${lit(AUT)}) r`);
  console.log("premissa", cod, JSON.stringify(r[0].r).slice(0, 120));
}
for (const [secao, cod] of [["receita_bruta", "CRESC_NOMINAL"], ["custos", "CUSTO_VARIAVEL"], ["despesas_operacionais", "SGA_PCT"],
  ["impostos_lucro", "ALIQUOTA"], ["resultado_financeiro", "TAXA_DIVIDA"]]) {
  const r = await q(`select fn_aplicar_premissa_em_lote('${C}', '${secao}', '${cod}', ${lit(AUT)}, null) r`);
  console.log("lote", secao, cod, JSON.stringify(r[0].r).slice(0, 160));
}
const linhas = await q(`select * from fn_linhas_para_modelagem('${C}')`);
const giro: Array<[string, string, (c: string) => boolean]> = [["ativo_circulante", "PMR", ehCliente], ["ativo_circulante", "PME", ehEstoque], ["passivo_circulante", "PMP", ehFornecedor]];
for (const [secao, cod, f] of giro) {
  const alvo = linhas.filter((l) => l.secao_canonica === secao && l.papel === "conta" && f(l.chave));
  let ok = 0;
  for (const l of alvo) {
    const r = await q(`select fn_vincular_linha_premissa('${C}', '${secao}', ${lit(l.chave)}, ${lit(ENT)}, '${cod}', ${lit(AUT)}, null) r`);
    if (r[0].r?.ok !== false) ok++; else console.log("recusa", l.chave, JSON.stringify(r[0].r));
  }
  console.log("giro", cod, alvo.length, "linhas;", ok, "ok;", alvo.slice(0, 6).map((l) => l.chave).join(" | "));
}
console.log((await q(`select fn_conferir_modelagem('${C}') r`))[0].r);
