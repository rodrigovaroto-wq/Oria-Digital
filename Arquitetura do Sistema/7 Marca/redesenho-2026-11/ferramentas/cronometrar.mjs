// Cronometra cada consulta da visão geral do mandato, isolada, com a sessão do usuário.
// Uso: PORTAL_EMAIL=.. PORTAL_SENHA=.. node cronometrar.mjs <caso_id>
import { createRequire } from 'node:module';
const require = createRequire('/home/user/Oria-Digital/portal/package.json');
const { createClient } = require('@supabase/supabase-js');
import fs from 'node:fs';

const env = Object.fromEntries(fs.readFileSync('/home/user/Oria-Digital/portal/.env.local', 'utf8')
  .split('\n').filter(Boolean).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));
const sb = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
const { error: e } = await sb.auth.signInWithPassword({ email: process.env.PORTAL_EMAIL, password: process.env.PORTAL_SENHA });
if (e) throw e;
const id = process.argv[2];
const t = async (nome, fn) => { const t0 = performance.now(); const r = await fn(); console.log(nome.padEnd(42), Math.round(performance.now() - t0), 'ms'); return r; };

await t('caso', () => sb.from('caso').select('id').eq('id', id).single());
await t('fn_avaliar_portao2', () => sb.rpc('fn_avaliar_portao2', { p_caso_id: id }));
await t('fn_fatos_do_caso', () => sb.rpc('fn_fatos_do_caso', { p_caso_id: id }));
await t('checklist_item_status', () => sb.from('checklist_item_status').select('tipo_taxonomia, status').eq('caso_id', id));
const kit = (await t('taxonomia (kit)', () => sb.from('taxonomia_tipo_documento').select('codigo').eq('obrigatoriedade', 'obrigatorio'))).data;
const docs = (await t('documento + versões', () => sb.from('documento').select('id, tipo_taxonomia, documento_versao(id)').eq('caso_id', id).order('id').range(0, 999))).data;
const versoes = docs.flatMap((d) => (d.documento_versao ?? []).map((v) => v.id));

let paginas = 0, linhas = 0;
await t(`campo_extraido paginado (${versoes.length} versões)`, async () => {
  for (;;) { const { data } = await sb.from('campo_extraido').select('documento_versao_id').in('documento_versao_id', versoes).order('id').range(linhas, linhas + 999); paginas++; if (!data?.length) break; linhas += data.length; }
});
console.log(`   -> ${linhas} linhas em ${paginas} idas sequenciais`);

const porRotulo = new Set(docs.map((d) => d.tipo_taxonomia).filter(Boolean));
const faltam = kit.filter((k) => !porRotulo.has(k.codigo));
const chamadas = faltam.length * docs.length;
await t(`kit básico: ${faltam.length} itens x ${docs.length} docs = ${chamadas} rpc`, () =>
  Promise.all(faltam.flatMap((k) => docs.map((d) => sb.rpc('fn_documento_serve_como', { p_documento_id: d.id, p_tipo_taxonomia: k.codigo })))));

// ---- depois da 0276: as mesmas perguntas, em lote ----
const lote = await t('fn_linhas_por_versao (1 ida)', () => sb.rpc('fn_linhas_por_versao', { p_versoes: versoes }));
const somaLote = (lote.data ?? []).reduce((a, r) => a + Number(r.linhas), 0);
console.log(`   -> ${lote.data?.length} versões devolvidas de ${new Set(versoes).size} pedidas; soma ${somaLote} (paginado: ${linhas}) ${somaLote === linhas ? 'IGUAL' : 'DIFERENTE'}`);
const ids = docs.map((d) => d.id);
const r2 = await t(`kit em lote: ${faltam.length} chamadas`, () => Promise.all(faltam.map((k) => sb.rpc('fn_algum_documento_serve_como', { p_documento_ids: ids, p_tipo_taxonomia: k.codigo }))));
console.log('   -> erros:', r2.filter((r) => r.error).length, ' respostas:', r2.map((r) => r.data));
