import sys
P=eval(open('/tmp/p27sab/pieces.py').read())
VARIANTE=sys.argv[1] if len(sys.argv)>1 else 'B'
out=sys.argv[2] if len(sys.argv)>2 else '/home/user/Oria-Digital/Supabase/migrations/0243_a_linha_que_nao_tinha_identidade.sql'
header=open('/tmp/p27sab/header.txt').read() if len(sys.argv)>3 else "-- (cabeçalho provisório)\n"
tipo=P['tipo']; ator=P['ator']; res=P['res']; pend=P['pend']
_x="when fn_normalizar_texto(k.ecol) ~ '^(combinad|consolidad|total|soma)' then 'coluna_total_nao_escolhida'"
assert _x in res
res=res.replace(_x,"when fn_normalizar_texto(k.ecol) ~ '^(combinad|consolidad|total|soma)' then (case when coalesce(t.n, 0) > 1 and exists (select 1 from emap e2 where e2.documento_versao_id = k.documento_versao_id and not e2.por_nome) then 'coluna_total_ambigua' else 'coluna_total_nao_escolhida' end)")

# pendência lê o resolver
a="""            from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id
           where f.documento_versao_id = p_documento_versao_id and f.origem = 'extracao' and f.resolucao_metodo <> 'declarada') x;"""
assert a in pend
pend=pend.replace(a,"""            from fn_fato_resolver(p_documento_versao_id) f join campo_extraido ce on ce.id = f.campo_id
           where f.origem = 'extracao' and f.resolucao_metodo <> 'declarada') x;""")
view_b="""create or replace view fato_financeiro with (security_invoker = true) as
  select r.campo_id as id, r.campo_id as campo_extraido_id, dv.id as documento_versao_id, r.conta_id, r.resolucao_metodo, r.sem_conta_motivo,
         r.entidade_id, r.entidade_origem, r.entidade_motivo, r.entidade_coluna, r.periodo_id, r.periodo_origem, r.periodo_motivo, r.periodo_coluna,
         r.valor, r.unidade, r.moeda, r.origem, r.criado_em
    from documento_versao dv
    cross join lateral fn_fato_resolver(dv.id) r;
"""
view_a="""create or replace view fato_financeiro with (security_invoker = true) as
  select r.campo_id as id, r.campo_id as campo_extraido_id, r.documento_versao_id, r.conta_id, r.resolucao_metodo, r.sem_conta_motivo,
         r.entidade_id, r.entidade_origem, r.entidade_motivo, r.entidade_coluna, r.periodo_id, r.periodo_origem, r.periodo_motivo, r.periodo_coluna,
         r.valor, r.unidade, r.moeda, r.origem, r.criado_em
    from fn_fato_resolver(null) r;
"""
view=view_b if VARIANTE=='B' else view_a

def R(a,b):
    global res
    assert res.count(a)==1,(a[:70],res.count(a))
    res=res.replace(a,b)
R("    select c.*, (c.ano_puro is not null and not c.parcial and c.ano_puro = c.y) as e_ano_do_doc,\n","    select c.*, (c.ano_puro is not null and not c.parcial and c.ano_puro = c.y) as e_ano_do_doc,\n           (c.y is not null and (c.saldo or (c.ano_puro is not null and not c.parcial and c.ano_puro = c.y))) as cand,\n")
R("                then min(pcol) filter (where y is not null and (saldo or e_ano_do_doc)) end as escolhida\n","                then min(pcol) filter (where y is not null and (saldo or e_ano_do_doc)) end as escolhida,\n           count(*) filter (where cand) as n_cand\n")
R("select documento_versao_id, pcol, abertura, parcial, ano_puro, e_ano_do_doc, n_mesmo_ano from vcol2\n    union all\n    select documento_versao_id, null, false, false, null::int, false, 0 from vinfo","select documento_versao_id, pcol, abertura, parcial, ano_puro, e_ano_do_doc, n_mesmo_ano, cand from vcol2\n    union all\n    select documento_versao_id, null, false, false, null::int, false, 0, false from vinfo")
R("                when z.n_mesmo_ano > 1 then 'mais_de_uma_coluna_para_o_mesmo_periodo'\n","                when z.n_mesmo_ano > 1 then 'mais_de_uma_coluna_para_o_mesmo_periodo'\n                when z.cand and z.n_cand > 1 then 'mais_de_uma_coluna_para_o_mesmo_periodo'\n")
R("      from (select p.documento_versao_id, p.pcol, p.abertura, p.parcial, p.ano_puro, p.e_ano_do_doc, p.n_mesmo_ano,\n                   i.doc_periodo, coalesce(e.n_cols, 0) as n_cols, e.escolhida,","      from (select p.documento_versao_id, p.pcol, p.abertura, p.parcial, p.ano_puro, p.e_ano_do_doc, p.n_mesmo_ano, p.cand,\n                   i.doc_periodo, coalesce(e.n_cols, 0) as n_cols, e.escolhida, e.n_cand,")
open(out,'w').write(header+open('/tmp/p27sab/body_tpl.sql').read().replace('@@TIPO@@',tipo).replace('@@ATOR@@',ator).replace('@@RES@@',res).replace('@@PEND@@',pend).replace('@@VIEW@@',view))
