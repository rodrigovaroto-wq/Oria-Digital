// LINHA DE BASE DA LEITURA, DOCUMENTO POR DOCUMENTO, CONTRA A VERDADE DO GERADOR (P4).
//
// Lê `fn_linha_de_base_extracao` (migration 0229) de um mandato de produção, como Sócio, e cruza cada
// documento com o METRICAS.json do book que o gerou. São três números por documento, e eles medem coisas
// diferentes:
//   • verdade  = linhas de conta que o gerador ESCREVEU (comum/contagem.py, sobre os flowables);
//   • régua    = contas_no_documento, o que o n8n CONTOU no texto do PDF (o denominador de produção);
//   • lidas    = linhas_devolvidas, o que a IA devolveu.
// "lidas / verdade" é a completude real; "régua / verdade" diz se a régua conta certo (cobertura > 1 em
// produção = régua contando a menos ou leitura duplicando — é aqui que se separa uma coisa da outra).
// Documento sem número de cobertura NÃO entra como zero: aparece com o motivo (regra 1 e 7).
//
// Uso (nunca `npx`):
//   LB_USUARIOS=<arquivo "papel uuid senha"> LB_MANDATO="<nome exato>" LB_METRICAS=<METRICAS.json do book> \
//   SUPABASE_URL=https://<ref>.supabase.co LB_ANON_KEY=<chave anon> LB_SAIDA=<pasta> \
//   ./portal/node_modules/.bin/tsx Verificação/linha-de-base.mts
// Somente leitura.
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";

const exigir = (n: string): string => {
  const v = process.env[n];
  if (!v) { console.error(`Falta a variável de ambiente ${n}.`); process.exit(2); }
  return v;
};
const MANDATO = exigir("LB_MANDATO");
const SAIDA = exigir("LB_SAIDA");
const metricas = JSON.parse(fs.readFileSync(exigir("LB_METRICAS"), "utf8"));
const senha = fs.readFileSync(exigir("LB_USUARIOS"), "utf8").trim().split("\n")
  .map((l) => l.trim().split(/\s+/)).find(([p]) => p === "socio")?.[2];
if (!senha) { console.error("Sem a linha do Sócio no arquivo de usuários."); process.exit(2); }
fs.mkdirSync(SAIDA, { recursive: true });

const { createClient } = createRequire(path.resolve(import.meta.dirname, "../portal/package.json"))("@supabase/supabase-js");
const sb = createClient(exigir("SUPABASE_URL"), exigir("LB_ANON_KEY"), { auth: { persistSession: false, autoRefreshToken: false } });
const { error: erroLogin } = await sb.auth.signInWithPassword({ email: "rodrigo.varoto+socio@oriapartners.com", password: senha });
if (erroLogin) { console.error("login falhou: " + erroLogin.message); process.exit(2); }

const caso = (await sb.from("caso").select("id").eq("nome", MANDATO).single()).data as any;
if (!caso) { console.error(`Mandato não encontrado: ${MANDATO}`); process.exit(2); }
const { data: linhas, error } = await sb.rpc("fn_linha_de_base_extracao", { p_caso_id: caso.id });
if (error) { console.error("fn_linha_de_base_extracao: " + error.message); process.exit(2); }

// Verdade por nome de arquivo: documentos (PDF) e planilhas (xlsx, book-espelho) entram igual.
const verdade = new Map<string, any>();
// Casa por nome em NFC: o mesmo nome com acento pode chegar decomposto (NFD) e não pode virar "sem verdade" calado.
const chave = (n: string) => String(n ?? "").normalize("NFC").replace(/\s+/g, " ").trim();
for (const d of [...(metricas.documentos ?? []), ...(metricas.planilhas ?? [])]) verdade.set(chave(d.arquivo), d);

const fmt = (x: number | null | undefined, casas = 2) => (x === null || x === undefined ? "—" : Number(x).toFixed(casas));
const razao = (a: any, b: any) => (a === null || a === undefined || !b ? null : Number(a) / Number(b));
const tabela = (linhas as any[]).sort((a, b) => String(a.nome_original).localeCompare(String(b.nome_original))).map((l) => {
  const v = verdade.get(chave(l.nome_original));
  const vl = v ? v.linhas_de_conta_verdade : null;
  // DMPL: o prompt manda UMA linha por componente do PL (a conta é a coluna), então a IA devolve
  // movimentos × componentes — não os movimentos que a régua e `linhas_de_conta_verdade` contam
  // (Vertentes 14 lidas = 14 células de valor, verdade 3 linhas; Canastra 29 contra 28 células, 9
  // linhas). Comparar lidas com linhas dava 4,67 e 3,22 e parecia leitura inflada.
  const vlLidas = l.tipo_taxonomia === "DMPL" && v?.celulas_de_valor_verdade ? v.celulas_de_valor_verdade : vl;
  return {
    documento: l.nome_original,
    tipo: l.tipo_taxonomia,
    espelha: v?.espelha ?? null,
    verdade: vl,
    regua: l.contas_no_documento,
    lidas: l.linhas_devolvidas,
    completude_real: razao(l.linhas_devolvidas, vlLidas),
    regua_sobre_verdade: razao(l.contas_no_documento, vl),
    cobertura_do_sistema: l.cobertura,
    motivo: l.cobertura_motivo ?? (v && vl === 0 ? (Number(l.linhas_devolvidas) > 0 ? `verdade 0: ${l.linhas_devolvidas} linha(s) a mais` : "verdade 0: ok") : (v ? null : "arquivo fora do METRICAS.json")),
    blocos: l.blocos, respondidos: l.blocos_com_resposta, planejados: l.blocos_planejados,
    falha: l.falha_motivo, pend_falhou: l.pendencias_extracao_falhou, pend_suspeito: l.pendencias_extracao_padrao_suspeito,
    rodou: l.extracao_rodou, versao_medicao: l.versao_medicao,
    sem_verdade: v ? null : "arquivo fora do METRICAS.json",
  };
});

// Junção COMPLETA: arquivo do book que nunca virou documento entra como linha, não some (regra 1).
const presentes = new Set((linhas as any[]).map((l) => chave(l.nome_original)));
for (const [k, v] of verdade) if (!presentes.has(k)) tabela.push({ documento: v.arquivo, tipo: null, espelha: v.espelha ?? null, verdade: v.linhas_de_conta_verdade, regua: null, lidas: null, completude_real: null, regua_sobre_verdade: null, cobertura_do_sistema: null, motivo: "arquivo do book NÃO chegou ao banco", blocos: null, respondidos: null, planejados: null, falha: null, pend_falhou: null, pend_suspeito: null, rodou: false, versao_medicao: null, sem_verdade: null } as any);
fs.writeFileSync(path.join(SAIDA, "linha-de-base.json"), JSON.stringify({ mandato: MANDATO, caso_id: caso.id, documentos: tabela }, null, 2));
const md = [
  `# Linha de base — ${MANDATO}`, "",
  "| Documento | Verdade | Régua | Lidas | Lidas/verdade | Régua/verdade | Motivo | Blocos (resp./total) | Falha |",
  "|---|---|---|---|---|---|---|---|---|",
  ...tabela.map((t) => `| ${t.documento} | ${t.verdade ?? "—"} | ${t.regua ?? "—"} | ${t.lidas ?? "—"} | ${fmt(t.completude_real)} | ${fmt(t.regua_sobre_verdade)} | ${t.motivo ?? ""} | ${t.respondidos ?? "—"}/${t.blocos ?? "—"} | ${t.falha ? String(t.falha).slice(0, 80) : ""} |`),
];
fs.writeFileSync(path.join(SAIDA, "linha-de-base.md"), md.join("\n") + "\n");
const comNumero = tabela.filter((t) => t.completude_real !== null);
const semMedicao = tabela.filter((t) => t.versao_medicao === null && t.motivo !== "arquivo do book NÃO chegou ao banco");
const ausentes = tabela.filter((t) => t.motivo === "arquivo do book NÃO chegou ao banco").length;
if (ausentes > 0) process.exitCode = 1;
console.log(`${verdade.size - ausentes} de ${verdade.size} arquivo(s) do book chegaram ao banco (${ausentes} ausente(s)); ${tabela.length} linha(s); ${comNumero.length} com completude real medida; ${tabela.length - comNumero.length} com motivo em vez de número; ${semMedicao.length} sem medição do n8n (anterior à 0229). Resultado em ${SAIDA}`);
