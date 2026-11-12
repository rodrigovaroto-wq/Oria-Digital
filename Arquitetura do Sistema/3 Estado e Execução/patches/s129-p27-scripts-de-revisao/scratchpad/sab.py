import subprocess,sys,re,json
R='/home/user/Oria-Digital'
S='/tmp/claude-0/-home-user-Oria-Digital/2ec90589-c004-5ebb-8574-7d4fde161a1d/scratchpad'
def psql(sql=None,f=None,env=''):
    cmd=f"cd {R}; {env} psql -v ON_ERROR_STOP=1 -h /tmp -p 5432 -U postgres -d tdf_p27 " + ("" if f else "-c \"$SQL\"")
    p=subprocess.run(['sudo','-u','postgres','env','SQL='+(sql or ''),'bash','-c',cmd],capture_output=True,text=True,stdin=(open(f) if f else None))
    return p.stdout+p.stderr
def fn_replace(fn, a, b, many=False):
    # reemite a função com replace e CONFERE que a troca aplicou
    return f"""do $$ declare d text := pg_get_functiondef('{fn}'::regprocedure); n text; begin
      n := replace(d, $a${a}$a$, $b${b}$b$); if n = d then raise exception 'SABOTAGEM NAO APLICOU'; end if; execute n; end $$;"""
def multi(fn, pares):
    body="d := pg_get_functiondef('%s'::regprocedure); n := d;" % fn
    for a,b in pares:
        body+=" if position($a$%s$a$ in n) = 0 then raise exception 'SABOTAGEM NAO APLICOU: %%', $a$%s$a$; end if; n := replace(n, $a$%s$a$, $b$%s$b$);" % (a,a.replace("'","''")[:40],a,b)
    return "do $$ declare d text; n text; begin "+body+" execute n; end $$;"
SAB={
 'S1 coluna nao-saldo herda o periodo do documento': fn_replace('fn_fato_resolver(uuid)', "when p.pcol = e.escolhida then i.doc_periodo", "when p.pcol = e.escolhida or (not p.abertura and p.ano_puro is null) then i.doc_periodo"),
 'S2 coluna escolhida sem exigir ser unica (>=1, min)': fn_replace('fn_fato_resolver(uuid)', "(saldo or e_ano_do_doc)) = 1", "(saldo or e_ano_do_doc)) >= 1"),
 'S3 parcial vai para o ano': fn_replace('fn_fato_resolver(uuid)', "(c.ano_puro is not null and not c.parcial and c.ano_puro = c.y)", "(c.ano_puro is not null and c.ano_puro = c.y)"),
 'S4 total sem exigir unicidade (duas colunas total)': multi('fn_fato_resolver(uuid)', [("(m.por_nome or coalesce(t.n, 0) <= 1)", "true"), ("when m.n = 1 then 'coluna_total_ambigua'", "when m.n = 1 then null")]),
 'S5 linha sem coluna de entidade em doc com colunas vai para o dono': multi('fn_fato_resolver(uuid)', [("when k.ecol is null then (case when not k.tem_ecols then k.doc_entidade end)", "when k.ecol is null then k.doc_entidade"), ("when k.ecol is null then (case when k.doc_entidade is not null and not k.tem_ecols then 'documento' end)", "when k.ecol is null then (case when k.doc_entidade is not null then 'documento' end)"), ("when k.tem_ecols then 'linha_sem_coluna_em_documento_com_colunas_de_entidade' end)", "end)")]),
 'S6 casamento de entidade ignora fn_coluna_entidade (so igualdade de nome)': fn_replace('fn_fato_fn','x','y') if False else "do $$ declare d text := pg_get_functiondef('fn_fato_resolver(uuid)'::regprocedure); n text; begin n := replace(d, 'nullif(btrim(fn_coluna_entidade(v.documento_versao_id, e.id)), '''')', '(select nullif(btrim(ce.entidade_coluna), '''') from campo_extraido ce where ce.documento_versao_id = v.documento_versao_id and fn_normalizar_texto(ce.entidade_coluna) = fn_normalizar_texto(e.razao_social) limit 1)'); if n = d then raise exception 'SABOTAGEM NAO APLICOU'; end if; execute n; end $$;",
 'S7 gatilho em periodo e entidade removidos': "drop trigger trg_fato_cadastro_periodo on periodo; drop trigger trg_fato_cadastro_entidade on entidade;",
 'S8 fn_materializar_fatos nao re-resolve o nulo (reparo)': fn_replace('fn_materializar_fatos(uuid,text)', "if p_documento_versao_id is null or (v_r->>'fatos_criados')::int = 0 then", "if false then"),
 'S9 gatilho do documento removido': "drop trigger trg_fato_segue_o_documento on documento;",
 'S10 gatilho da extracao nova removido': "drop trigger trg_fato_extracao_nova on evento_auditoria;",
 'S11 repontar sem a guarda de entidade apagada': fn_replace('fn_fato_repontar_entidade(uuid,uuid,uuid)', "if exists (select 1 from entidade where id = p_de) then", "if false then"),
 'S12 evento negada sem o ator real': fn_replace('fn_materializar_fatos_da_extracao(uuid,text)', "coalesce(fn_fato_ator(), p_ator), 'fatos_materializacao_negada'", "p_ator, 'fatos_materializacao_negada'"),
 'S13 authenticated com INSERT em fato_financeiro': "grant insert, update on fato_financeiro to authenticated;",
 'S14 fn_fato_pode_escrever sempre verdadeira': "create or replace function fn_fato_pode_escrever(p_caso uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $q$ select true $q$;",
 'S15 fn_registrar_campos_extraidos reemitida do corpo da 0231 (o bloqueio da 0270): ln some': "do $$ declare d text := pg_get_functiondef('fn_registrar_campos_extraidos(uuid,jsonb,nivel_autonomia,text,boolean,jsonb)'::regprocedure); n text; begin n := replace(replace(d, 'v_ln := case when jsonb_typeof(v_item->''ln'') = ''number''', 'v_ln := case when false and jsonb_typeof(v_item->''ln'') = ''number''') , 'x','x'); if n = d then raise exception 'SABOTAGEM NAO APLICOU'; end if; execute n; end $$;",
 'E1 elegibilidade so tem valor (sem tipo e sem papel)': multi('fn_linha_vira_fato(text,text,text,numeric)', [("p_valor is not null and fn_tipo_gera_fato(p_tipo) and fn_papel_linha(p_chave, p_tipo, p_unidade) = 'conta'", "p_valor is not null")]),
 'E2 elegibilidade sem o papel conta (subtotal vira fato)': multi('fn_linha_vira_fato(text,text,text,numeric)', [(" and fn_papel_linha(p_chave, p_tipo, p_unidade) = 'conta'", " ")]),
 'E3 BALANCO fora da lista de tipos': multi('fn_tipo_gera_fato(text)', [("'BALANCO', ", " ")]),
 'E4 conta pela raiz/tipo em vez da secao': multi('fn_fato_resolver(uuid)', [("left join conta_canonica c on c.secao_canonica = a.secao", "left join conta_canonica c on c.codigo = a.tipo")]),
 'E5 gatilho do documento ignora tipo_taxonomia': multi('fn_fato_segue_o_documento()', [("if new.tipo_taxonomia is distinct from old.tipo_taxonomia then", "if false then")]),
 'E6 versao superada nao baixa a pendencia': multi('fn_materializar_fatos_da_extracao(uuid,text)', [("if v_vigente = p_documento_versao_id then", "if false then")]),
 'E7 query_canceled engolido': multi('fn_materializar_fatos_da_extracao(uuid,text)', [("when query_canceled then raise;", "when query_canceled then null;")]),
 'E8 fn_fundir_entidade sem repor os fatos': multi('fn_fundir_entidade(uuid,uuid,uuid,text)', [("perform fn_materializar_fatos_do_caso(p_caso_id, 'entidade', 'fusao_de_entidade');", "null;")]),
 'S17 funcao do gatilho da extracao nova nao chama a materializacao': multi('fn_fato_extracao_nova()', [("perform fn_materializar_fatos_da_extracao(v_versao);", "null;")]),
 'S18 guarda de mesmo mandato desabilitada': "alter table fato_financeiro disable trigger trg_fato_mesmo_caso;",
 'N1 duas colunas da mesma entidade: sem a unicidade por (versao, entidade)': multi('fn_fato_resolver(uuid)', [("and not exists (select 1 from enome_n n where n.documento_versao_id = x.documento_versao_id and n.entidade_id = x.entidade_id and n.n > 1)", " ")]),
 'N2 gatilho do documento sem o tipo mudou na re-resolucao': multi('fn_fato_segue_o_documento()', [(" or new.tipo_taxonomia is distinct from old.tipo_taxonomia) then", ") then")]),
 'N4 re-resolucao do cadastro so dos nulos (sem origem coluna)': multi('fn_fato_reresolver_caso(uuid,text)', [("or f.entidade_origem in ('coluna', 'coluna_total')", " or false ")]),
 'N3a sonda recentes antiga (amostra pelo evento extracao_sombra)': "create or replace view instalacao_sonda_fato_financeiro_recentes as select 1 as ok where not exists (select 1 from (select dv.id, d.tipo_taxonomia from documento_versao dv join documento d on d.id = dv.documento_id where fn_tipo_gera_fato(d.tipo_taxonomia) and exists (select 1 from evento_auditoria e where e.entidade_ref = 'documento_versao:' || dv.id and e.acao = 'extracao_sombra') order by dv.criada_em desc, dv.id limit 20) v join campo_extraido ce on ce.documento_versao_id = v.id and ce.origem_valor = 'extracao' where fn_linha_vira_fato(v.tipo_taxonomia, ce.chave, ce.unidade, ce.valor_num) and not exists (select 1 from fato_financeiro f where f.campo_extraido_id = ce.id));",
 'N3b sonda recentes sem a concordancia conta/metodo': "create or replace view instalacao_sonda_fato_financeiro_recentes as select 1 as ok where not exists (select 1 from (select dv.id, d.tipo_taxonomia from documento_versao dv join documento d on d.id = dv.documento_id where fn_tipo_gera_fato(d.tipo_taxonomia) and exists (select 1 from campo_extraido x where x.documento_versao_id = dv.id and x.origem_valor = 'extracao' and x.valor_num is not null) order by dv.criada_em desc, dv.id limit 20) v join campo_extraido ce on ce.documento_versao_id = v.id and ce.origem_valor = 'extracao' where fn_linha_vira_fato(v.tipo_taxonomia, ce.chave, ce.unidade, ce.valor_num) and not exists (select 1 from fato_financeiro f where f.campo_extraido_id = ce.id));",
 'R1 recalculo sem atualizar o que existe (so cria): upsert que nunca atualiza': multi('fn_fato_recalcular(uuid,text,text)', [("where (f.conta_id, f.resolucao_metodo,", "where false and (f.conta_id, f.resolucao_metodo,")]),
 'R2 recalculo sem remover o que nao e mais elegivel': multi('fn_fato_recalcular(uuid,text,text)', [("and not exists (select 1 from r where r.campo_id = f.campo_extraido_id)", "and false")]),
 'R3 gatilho do documento nao recalcula (entidade, periodo, tipo na lista)': multi('fn_fato_segue_o_documento()', [("perform fn_fato_recalcular(v_v, 'extracao', 'documento_alterado');", "null;")]),
 'R4 cadastro de entidade/periodo nao recalcula': multi('fn_fato_recalcular_caso(uuid,text,text)', [("v_r := fn_fato_recalcular(v_v, 'extracao', p_motivo);", "v_r := '{\"atualizados\":0,\"fatos_criados\":0,\"removidos\":0}'::jsonb;")]),
 'R5 fusao nao recalcula (sem reponta, sem nada)': multi('fn_fundir_entidade(uuid,uuid,uuid,text)', [("perform fn_materializar_fatos_do_caso(p_caso_id, 'entidade', 'fusao_de_entidade');", "null;")]),
 'R7 recalculo que mexe na pendencia (chama fn_fato_pendencia_da_versao)': multi('fn_fato_recalcular(uuid,text,text)', [("  return v_r;\nend", "  if p_documento_versao_id is not null then perform fn_fato_pendencia_da_versao(p_documento_versao_id); end if;\n  return v_r;\nend")]),
 'R8 evento fatos_recalculados sem o ator real': multi('fn_fato_recalcular(uuid,text,text)', [("values (fn_fato_ator(), 'fatos_recalculados'", "values ('sistema:0243', 'fatos_recalculados'")]),
 'R9 sonda do unico escritor fixa em ok': "create or replace view instalacao_sonda_fato_financeiro_um_escritor as select 1 as ok;",
 'S16 fn_registrar chama a materializacao ao mesmo tempo que o gatilho (dupla) nao conta; materializacao fora do gatilho: so a funcao, sem gatilho = S10': None,
}
sel=sys.argv[1:] 
for nome,sql in SAB.items():
    if sql is None: continue
    if sel and not any(nome.startswith(x+' ') for x in sel): continue
    # S15: fn_registrar original precisa ser restaurada depois: guardo a def
    saved=None
    if nome.startswith('S15'):
        out=subprocess.run(['sudo','-u','postgres','psql','-h','/tmp','-p','5432','-U','postgres','-d','tdf_p27','-At','-c',"select pg_get_functiondef('fn_registrar_campos_extraidos(uuid,jsonb,nivel_autonomia,text,boolean,jsonb)'::regprocedure)"],capture_output=True,text=True).stdout
        saved=out
    o=psql(sql)
    if 'SABOTAGEM NAO APLICOU' in o or 'ERROR' in o: print(nome,'-> FALHA AO SABOTAR',o[:300]); psql(f=R+'/Supabase/migrations/0243_a_linha_que_nao_tinha_identidade.sql'); continue
    t=psql(f=S+'/ft_semreaplicar.sql',env="PGOPTIONS='-c ff.medindo=on'")
    m=re.search(r'(\d+) asserts executados, (\d+) reprovados',t)
    falhas=[l.split('FALHOU: ')[1][:110] for l in t.splitlines() if 'FALHOU: ' in l and 'asserts' not in l and 'assert(s)' not in l]
    err=[l for l in t.splitlines() if 'ERROR' in l][:2]
    print(f"{nome}: {m.group(2) if m else '?'} dos {m.group(1) if m else '?'} reprovam" + (f" | ABORTOU: {err}" if err else ''))
    if '-v' in sys.argv or True:
        for f in falhas[:6]: print('     -',f)
    # restaurar
    if saved:
        open('/tmp/claude-0/-home-user-Oria-Digital/2ec90589-c004-5ebb-8574-7d4fde161a1d/scratchpad/saved.sql','w').write(saved+';\n')
        print('   restaurar fn_registrar:', subprocess.run(['sudo','-u','postgres','psql','-v','ON_ERROR_STOP=1','-h','/tmp','-p','5432','-U','postgres','-d','tdf_p27'],stdin=open('/tmp/claude-0/-home-user-Oria-Digital/2ec90589-c004-5ebb-8574-7d4fde161a1d/scratchpad/saved.sql'),capture_output=True,text=True).stderr[:200])
    o=psql(f=R+'/Supabase/migrations/0243_a_linha_que_nao_tinha_identidade.sql')
    if 'ERROR' in o: print('   RESTAURAR FALHOU', o[:300])
