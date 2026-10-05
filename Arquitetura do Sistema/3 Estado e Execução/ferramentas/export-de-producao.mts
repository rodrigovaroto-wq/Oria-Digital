// Réplica da rota /casos/[id]/export (modo completo) lendo produção pela API de gerenciamento (só SELECT).
// Pula SÓ o Portão 2, a pedido do dono (05/10/2026: "qualquer inconsistência ou bloqueante deve ser ignorado").
import { writeFile } from "node:fs/promises";
import { buildExportWorkbook, finalizarBufferDoExport, type DocumentoParaExport, type ConfigModelagem, type MacroAnual, type MacroExpectativa } from "../../../portal/src/lib/export.ts";
import type { EntradaModeloInstitucional, LinhaModelo } from "../../../portal/src/lib/modelo-institucional.ts";
import type { CampoExtraido } from "../../../portal/src/lib/types.ts";
import { casarVinculosComLinhas, seriesPorLinha, serieDaLinha, provenienciaPorLinha, provenienciaDaLinha } from "../../../portal/src/lib/modelagem-linha.ts";

const REF = process.env.SUPABASE_URL!.replace(/^https:\/\/([^.]+)\..*/, "$1");
const NUM = new Set(["valor","valor_num","valor_ultimo","fracao","retorno","mediana","confianca","meses","ano","ano_ref","exercicio","ultimo_exercicio_real","anos_projetados","origem_pagina","ordem","mes","n_versao"]);
const numerar = (rows: any[]) => rows.map((r) => { if (r && typeof r === "object") for (const k of Object.keys(r)) if (NUM.has(k) && typeof r[k] === "string" && r[k] !== "" && Number.isFinite(Number(r[k]))) r[k] = Number(r[k]); return r; });
async function q<T>(sql: string): Promise<T[]> {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: "POST", headers: { Authorization: `Bearer ${process.env.SUPABASE_ACCESS_TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify({ query: sql }) });
  const j = await r.json();
  if (!Array.isArray(j)) throw new Error(JSON.stringify(j).slice(0, 500));
  return numerar(j) as T[];
}
const CASO = process.argv[2]; if (!/^[0-9a-f-]{36}$/.test(CASO)) throw new Error("caso_id");
const caso = (await q<{ id: string; nome: string; produto: string }>(`select id, nome, produto from caso where id='${CASO}'`))[0];
const documentos = await q<DocumentoParaExport>(`
  select d.id, d.tipo_taxonomia, json_build_object('razao_social', e.razao_social) as entidade,
         json_build_object('tipo', p.tipo, 'referencia', p.referencia) as periodo,
         (select coalesce(json_agg(json_build_object('id', dv.id, 'nome_original', dv.nome_original, 'n_versao', dv.n_versao)), '[]'::json)
            from documento_versao dv where dv.documento_id = d.id) as documento_versao
  from documento d left join entidade e on e.id=d.entidade_id left join periodo p on p.id=d.periodo_id
  where d.caso_id='${CASO}'`);
const campos = await q<CampoExtraido>(`
  select ce.id, ce.documento_versao_id, ce.secao, ce.secao_canonica, ce.entidade_coluna, ce.periodo_coluna, ce.chave,
         ce.valor_texto, ce.valor_num, ce.unidade, ce.confianca, ce.origem_pagina, ce.ordem, ce.status_aceite, ce.aceito_por, ce.aceito_em
  from campo_extraido ce join documento_versao dv on dv.id=ce.documento_versao_id join documento d on d.id=dv.documento_id
  where d.caso_id='${CASO}' order by ce.documento_versao_id, ce.ordem nulls last, ce.id`);
const falhas = await q<{ descricao: string | null }>(`select descricao from pendencia where caso_id='${CASO}' and tipo='extracao_falhou' and estado<>'resolvida'`);
const causasDeFalha = [...new Set(falhas.map((p) => (p.descricao ?? "").split(/Motivo:\s*/)[1]?.trim()).filter((c): c is string => !!c))];
const ano0 = new Date().getFullYear();
const anuais = await q<MacroAnual>(`select * from fn_indice_macro_anual(${ano0 - 11})`);
const vistos = new Set<string>();
const expectativas = (await q<MacroExpectativa>(`select serie, ano_ref, mediana, coletado_em from indice_macro_expectativa where ano_ref >= ${ano0 - 1} order by coletado_em desc, serie, ano_ref`))
  .filter((e) => { const k = `${e.serie}/${e.ano_ref}`; if (vistos.has(k)) return false; vistos.add(k); return true; });
const nomes = Object.fromEntries((await q<{ codigo: string; nome: string }>("select codigo, nome from indice_macro_serie")).map((s) => [s.codigo, s.nome]));
const macro = anuais.length || expectativas.length ? { anuais, expectativas, nomes } : undefined;
const natureza = new Map<string, "taxa" | "nivel">(); for (const a of anuais) if (a.natureza === "nivel" || a.natureza === "taxa") natureza.set(a.serie, a.natureza);
const nivel = new Map<string, { valor: number; data: string }>();
for (const o of await q<{ serie: string; data_ref: string; valor: number }>("select serie, data_ref::text, valor from indice_macro_obs order by data_ref, serie"))
  nivel.set(`${o.serie}|${Number(o.data_ref.slice(0, 4))}`, { valor: Number(o.valor), data: o.data_ref });

const par = (await q<{ entidade: string | null; ultimo_exercicio_real: number | null; anos_projetados: number; setor: string | null }>(
  `select entidade, ultimo_exercicio_real, anos_projetados, setor from caso_modelagem where caso_id='${CASO}'`))[0] ?? null;
const premissas = await q<{ codigo: string; nome: string; formula: string; unidade: string | null; natureza: string; origem: string | null; valores: Record<string, number> }>(`
  select cp.premissa_codigo as codigo, pc.nome, pc.formula::text as formula, pc.unidade, pc.natureza::text as natureza, cp.origem, cp.valores
  from caso_premissa cp join premissa_catalogo pc on pc.codigo=cp.premissa_codigo where cp.caso_id='${CASO}' and cp.ativo`);
const vinculos = await q<{ rotulo_norm: string; secao_canonica: string | null; premissa_codigo: string | null; sazonalidade_codigo: string | null }>(
  `select rotulo_norm, secao_canonica, premissa_codigo, sazonalidade_codigo from caso_linha_premissa where caso_id='${CASO}' order by rotulo_norm, secao_canonica nulls first`);
const linhasRpc = await q<any>(`select * from fn_linhas_para_modelagem('${CASO}') order by secao_canonica nulls last, rotulo_norm`);
const curva = (await q<{ mes: number; fracao: number }>(`select mes, fracao from fn_sazonalidade_do_caso('${CASO}') order by mes`)).map((x) => Number(x.fracao));
const modelagemConfig: ConfigModelagem = { entidade: par?.entidade ?? null, sazonalidade: curva.length === 12 ? curva : undefined,
  ultimoExercicioReal: par?.ultimo_exercicio_real ?? null, anosProjetados: par?.anos_projetados ?? 5, premissas, linhas: casarVinculosComLinhas(vinculos as any, linhasRpc) };
let modeloInstitucional: EntradaModeloInstitucional | undefined;
const ent = par?.entidade?.trim() || null; const ultimo = par?.ultimo_exercicio_real ?? null;
if (ent && ultimo) {
  const entSql = ent.replace(/'/g, "''");
  // CORREÇÃO LOCAL (S105, caso Fw Valtra): fn_valores_por_ano escolhe o MAIOR |valor| entre todas as colunas do ano,
  // e trata "Saldo Inicial/anterior" como o próprio ano e "Débito/Crédito" de balancete semestral como saldo.
  const valores = process.env.VALORES_CORRIGIDOS !== "1"
    ? await q<any>(`select * from fn_valores_por_ano('${CASO}', '${entSql}') order by rotulo_norm, ano, secao_canonica nulls first`)
    : await q<any>(`
    with oc as (
      select fn_normalizar_texto(ce.chave) rotulo_norm, ce.secao_canonica,
             fn_ano_da_coluna(ce.periodo_coluna, p.referencia)
               - case when ce.periodo_coluna ~* '^\\s*saldo\\s+(inicial|anterior)\\s*$' then 1 else 0 end as ano,
             case when ce.periodo_coluna ~* '^\\s*saldo\\s+(inicial|anterior)\\s*$' then 1 else 0 end as prio,
             ce.valor_num valor, dv.nome_original arquivo, ce.origem_pagina, ce.confianca, ce.status_aceite, ce.aceito_por, ce.ordem
      from campo_extraido ce join documento_versao dv on dv.id=ce.documento_versao_id join documento d on d.id=dv.documento_id
      left join periodo p on p.id=d.periodo_id left join entidade e on e.id=d.entidade_id
      where d.caso_id='${CASO}' and ce.valor_num is not null and dv.id = fn_versao_com_extracao(d.id)
        and d.tipo_taxonomia not in ('BALANCETE','CONTRATO_SOCIAL')
        and coalesce(ce.periodo_coluna,'') !~* '^\\s*(d[ée]bito|cr[ée]dito)s?\\s*$'
        and fn_mesma_entidade(coalesce(ce.entidade_coluna, e.razao_social, ''), '${entSql}'))
    select distinct on (rotulo_norm, secao_canonica, ano) rotulo_norm, secao_canonica, ano, valor,
           count(*) over (partition by rotulo_norm, secao_canonica, ano) n_ocorrencias, arquivo, origem_pagina, confianca, status_aceite, aceito_por
    from oc where ano is not null
    order by rotulo_norm, secao_canonica, ano, prio, abs(valor) desc, origem_pagina nulls last, ordem nulls last`);
  const anosHistoricos = [...new Set(valores.map((v: any) => Number(v.ano)))].filter((a) => a <= ultimo).sort((a, b) => a - b);
  const anosProjetados = Array.from({ length: par?.anos_projetados ?? 5 }, (_, i) => ultimo + 1 + i);
  const series = seriesPorLinha(valores, anosHistoricos); const prov = provenienciaPorLinha(valores, anosHistoricos);
  const linhasModelo: LinhaModelo[] = linhasRpc.map((l: any) => ({ secao_canonica: l.secao_canonica, chave: l.chave, rotulo_norm: l.rotulo_norm,
    papel: l.papel, unidade: l.unidade, moeda: l.moeda, documentos: l.documentos,
    valores: serieDaLinha(series, l.secao_canonica, l.rotulo_norm), proveniencia: provenienciaDaLinha(prov, l.secao_canonica, l.rotulo_norm) }));
  const macroModelo = [
    ...anuais.flatMap((a: any) => a.natureza === "nivel"
      ? (nivel.get(`${a.serie}|${a.ano}`) ? [{ serie: a.serie, ano: a.ano, valor: nivel.get(`${a.serie}|${a.ano}`)!.valor, natureza: "nivel" as const, fonte: `realizado — fechamento de ${nivel.get(`${a.serie}|${a.ano}`)!.data}`, origem: "realizado" as const }] : [])
      : [{ serie: a.serie, ano: a.ano, valor: Number(a.retorno), natureza: "taxa" as const, fonte: `realizado (${a.meses} meses)`, meses: Number(a.meses), origem: "realizado" as const }]),
    ...expectativas.map((e) => ({ serie: e.serie, ano: e.ano_ref, valor: Number(e.mediana), natureza: natureza.get(e.serie) ?? ("taxa" as const), fonte: `Focus, coleta ${e.coletado_em}`, origem: "focus" as const })),
  ];
  const cont = new Map<string, number>(); for (const l of linhasModelo) if (l.unidade) cont.set(l.unidade, (cont.get(l.unidade) ?? 0) + 1);
  const dom = [...cont.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
  modeloInstitucional = { caso: { nome: caso.nome, produto: caso.produto }, agora: new Date(), entidade: ent, setor: par?.setor ?? null,
    anosHistoricos, anosProjetados, stressPct: 0.2, caixaMinimo: 0, aliquotaTributos: 0.34, linhas: linhasModelo, premissas,
    vinculos: vinculos.map((v) => ({ rotulo_norm: v.rotulo_norm, premissa_codigo: v.premissa_codigo, sazonalidade_codigo: v.sazonalidade_codigo })),
    macro: macroModelo as any, unidade: dom === "milhar" ? "R$ mil" : dom === "unidade" ? "R$" : (dom ?? "R$") };
}
console.log(`caso=${caso.nome} docs=${documentos.length} campos=${campos.length} premissas=${premissas.length} vinculos=${vinculos.length} linhas=${linhasRpc.length} modelo=${!!modeloInstitucional}`);
const wb = buildExportWorkbook({ caso, documentos, campos, macro, causasDeFalha, modo: "completo", modelagemConfig, modeloInstitucional } as any);
await writeFile(process.argv[3], await finalizarBufferDoExport(wb));
console.log("OK", process.argv[3], wb.worksheets.map((w) => w.name).join(" · "));
