#!/usr/bin/env python3
"""Protocolo de NAO-VAZIO da 0243 (versao VIEW), regra 2: desliga cada parte, roda o teste, conta os asserts que reprovam, religa.

Uso (como root; o banco precisa ter sido montado pelo run.sh, com as fixtures e os testes anteriores):
    python3 sab.py <banco> [prefixo-da-sabotagem ...]
Cada sabotagem: (1) aplica a troca CONFERIDA (se o texto nao existe a medicao ABORTA: um replace que nao troca nada daria 0 reprovacoes
e pareceria "teste vazio"), (2) roda uma COPIA do fato_financeiro.test.sql sem o bloco do topo (senao a migration desfaria a sabotagem)
com ff.medindo=on (o assert vira contagem, nao aborta), (3) le o log atras de FALHOU:, (4) reaplica a migration para restaurar.
As sabotagens de MIGRATION (sem revoke, sem a cadeia, sem a trava) rodam o teste COM o topo, apontando para a copia da migration sabotada.
O controle (migration intacta) tem de dar 0 reprovacoes.
"""
import subprocess, sys, re, os, tempfile

R = '/home/user/Oria-Digital'
MIG = R + '/Supabase/migrations/0243_a_linha_que_nao_tinha_identidade.sql'
TESTE = R + '/Supabase/test/fato_financeiro.test.sql'
CORR = R + '/Supabase/test/fato_financeiro_corridas.test.sql'
DB = sys.argv[1]
SEL = sys.argv[2:]
TMP = '/tmp/p27/sab_' + DB
os.makedirs(TMP, exist_ok=True)
os.chmod(TMP, 0o777)

def psql(args, env=''):
    cmd = f"cd {R}; {env} psql -X -h /tmp -p 5432 -U postgres -d {DB} " + args
    p = subprocess.run(['sudo', '-u', 'postgres', 'bash', '-c', cmd], capture_output=True, text=True)
    return p.stdout + p.stderr

def sql(s, env=''):
    f = f'{TMP}/cmd.sql'
    open(f, 'w').write(s)
    os.chmod(f, 0o644)
    return psql(f'-v ON_ERROR_STOP=1 -f {f}', env)

def fn_replace(fn, a, b):
    return f"""do $$ declare d text := pg_get_functiondef('{fn}'::regprocedure); n text; begin
      n := replace(d, $a${a}$a$, $b${b}$b$); if n = d then raise exception 'SABOTAGEM NAO APLICOU'; end if; execute n; end $$;"""

def multi(fn, pares):
    body = "d := pg_get_functiondef('%s'::regprocedure); n := d;" % fn
    for a, b in pares:
        body += " if position($a$%s$a$ in n) = 0 then raise exception 'SABOTAGEM NAO APLICOU'; end if; n := replace(n, $a$%s$a$, $b$%s$b$);" % (a, a, b)
    return "do $$ declare d text; n text; begin " + body + " execute n; end $$;"

# o teste SEM o topo (as 3 chaves do topo ficam fixas: as asserts de idempotencia/ACL do topo NAO sao medidas nas sabotagens de funcao)
t = open(TESTE).read()
i = t.index('-- TOPO (fora da transação).')
j = t.index('\nbegin;\n', i)
topo = t[i:j]
sem_topo = t[:i] + "select set_config('ff.h0', 'x', false) as g0, set_config('ff.h1', 'x', false) as g1, set_config('ff.h2', 'x', false) as g2, set_config('ff.default_acl', 'f,f,f,f,f', false) as g3 \\gset\n" + t[j:]
open(f'{TMP}/teste_sem_topo.sql', 'w').write(sem_topo); os.chmod(f'{TMP}/teste_sem_topo.sql', 0o644)

def roda_teste(com_topo_mig=None):
    if com_topo_mig:
        tt = t.replace('\\i Supabase/migrations/0243_a_linha_que_nao_tinha_identidade.sql', '\\i ' + com_topo_mig)
        arq = f'{TMP}/teste_com_topo.sql'
        open(arq, 'w').write(tt); os.chmod(arq, 0o644)
    else:
        arq = f'{TMP}/teste_sem_topo.sql'
    return psql(f'-v ON_ERROR_STOP=1 -f {arq}', env="PGOPTIONS='-c ff.medindo=on'")

def relata(nome, out):
    m = re.search(r'(\d+) asserts executados, (\d+) reprovados', out)
    falhas = [l.split('FALHOU: ')[1][:120] for l in out.splitlines() if 'FALHOU: ' in l and 'assert(s)' not in l]
    err = [l[:160] for l in out.splitlines() if 'ERROR' in l][:2]
    print(f"{nome}: {m.group(2) if m else '?'} dos {m.group(1) if m else '?'} reprovam" + (f"  | ABORTOU: {err}" if err else ''))
    for f in falhas[:5]:
        print('     -', f)
    sys.stdout.flush()

def restaura():
    o = sql(open(MIG).read())
    if 'ERROR' in o:
        print('   RESTAURAR FALHOU', o[:300])

# --- as sabotagens de FUNCAO/ESTADO (rodam o teste sem o topo) ---
RES = 'fn_fato_resolver(uuid)'
SAB = {
 'S01 coluna que nao e saldo herda o periodo do documento (1.310, 500, 435, 342)': fn_replace(RES, "when p.pcol = e.escolhida then i.doc_periodo", "when p.pcol = e.escolhida or (not p.abertura and p.ano_puro is null) then i.doc_periodo"),
 'S02 coluna escolhida sem exigir ser UNICA (>= 1 em vez de = 1)': fn_replace(RES, "(saldo or e_ano_do_doc)) = 1", "(saldo or e_ano_do_doc)) >= 1"),
 'S03 documento PARCIAL da o ano a coluna 2025': fn_replace(RES, "(c.ano_puro is not null and not c.parcial and c.ano_puro = c.y)", "(c.ano_puro is not null and c.ano_puro = c.y)"),
 'S04 total sem exigir ser unico (duas colunas total)': multi(RES, [("(m.por_nome or coalesce(t.n, 0) <= 1)", "true"), ("when m.n = 1 then 'coluna_total_ambigua'", "when m.n = 1 then null")]),
 'S05 linha sem coluna de entidade num documento com colunas vai para o dono': multi(RES, [("when k.ecol is null then (case when not k.tem_ecols then k.doc_entidade end)", "when k.ecol is null then k.doc_entidade"), ("when k.ecol is null then (case when k.doc_entidade is not null and not k.tem_ecols then 'documento' end)", "when k.ecol is null then (case when k.doc_entidade is not null then 'documento' end)"), ("when k.tem_ecols then 'linha_sem_coluna_em_documento_com_colunas_de_entidade' end)", "end)")]),
 'S06 duas colunas da mesma entidade SEM a unicidade por (versao, entidade)': multi(RES, [("and not exists (select 1 from enome_n n where n.documento_versao_id = x.documento_versao_id and n.entidade_id = x.entidade_id and n.n > 1)", " ")]),
 'S07 casamento de nome proprio no lugar de fn_coluna_entidade ("Alfa Comercio" x razao social)': "do $$ declare d text := pg_get_functiondef('fn_fato_resolver(uuid)'::regprocedure); n text; begin n := replace(d, 'nullif(btrim(fn_coluna_entidade(v.documento_versao_id, e.id)), '''')', '(select nullif(btrim(c.col), '''') from ecols c where c.documento_versao_id = v.documento_versao_id and fn_entidade_canonica(c.col) = fn_entidade_canonica(e.razao_social) limit 1)'); if n = d then raise exception 'SABOTAGEM NAO APLICOU'; end if; execute n; end $$;",
 'S08 conta achada pelo TIPO do documento em vez da secao': fn_replace(RES, "left join conta_canonica c on c.secao_canonica = a.secao", "left join conta_canonica c on c.codigo = a.tipo"),
 'S09 coluna de abertura (Saldo Inicial) recebe o periodo do documento': fn_replace(RES, "when p.abertura then null", "when p.abertura then i.doc_periodo"),
 'S10 periodo de OUTRO ano procurado em qualquer mandato (sem o filtro de caso)': multi(RES, [("select q.id from periodo q where q.caso_id = i.caso_id\n", "select q.id from periodo q where true\n")]),
 'S11 elegibilidade so "tem valor" (sem tipo e sem papel)': multi('fn_linha_vira_fato(text,text,text,numeric)', [("p_valor is not null and fn_tipo_gera_fato(p_tipo) and fn_papel_linha(p_chave, p_tipo, p_unidade) = 'conta'", "p_valor is not null")]),
 'S12 elegibilidade sem o papel conta (subtotal vira fato)': multi('fn_linha_vira_fato(text,text,text,numeric)', [(" and fn_papel_linha(p_chave, p_tipo, p_unidade) = 'conta'", " ")]),
 'S13 BALANCO fora da lista de tipos': multi('fn_tipo_gera_fato(text)', [("'BALANCO', ", " ")]),
 'S14 resolver sem o filtro de papel (a lista de rotulos que viram fato ignorada)': fn_replace(RES, "select x.tipo, x.chave, x.unidade from rotulos x where fn_linha_vira_fato(x.tipo, x.chave, x.unidade, 1)", "select x.tipo, x.chave, x.unidade from rotulos x"),
 'S15 resolver ignora a linha sem valor (valor nulo vira fato)': fn_replace(RES, "and ce.valor_num is not null and fn_tipo_gera_fato(d.tipo_taxonomia)", "and fn_tipo_gera_fato(d.tipo_taxonomia)"),
 'V01 SECURITY_INVOKER desligado (a view roda com o privilegio do dono)': "alter view fato_financeiro set (security_invoker = off);",
 'V02 resolver como SECURITY DEFINER': "alter function fn_fato_resolver(uuid) security definer;",
 'V03 authenticated com INSERT/UPDATE/DELETE na view': "grant insert, update, delete on fato_financeiro to authenticated;",
 'V04 anon lendo a view': "grant select on fato_financeiro to anon;",
 'V05 anon executando o resolver': "grant execute on function fn_fato_resolver(uuid) to anon;",
 'V07 as DUAS camadas desligadas (view sem security_invoker E resolver SECURITY DEFINER): o vazamento de verdade': "alter view fato_financeiro set (security_invoker = off); alter function fn_fato_resolver(uuid) security definer;",
 'V06 poda desligada (a view resolve TODAS as versoes e filtra depois)': "create or replace view fato_financeiro with (security_invoker = true) as select * from (select r.campo_id as id, r.campo_id as campo_extraido_id, dv.id as documento_versao_id, d.caso_id, r.conta_id, r.resolucao_metodo, r.sem_conta_motivo, r.entidade_id, r.entidade_origem, r.entidade_motivo, r.entidade_coluna, r.periodo_id, r.periodo_origem, r.periodo_motivo, r.periodo_coluna, r.valor, r.unidade, r.moeda from documento d join documento_versao dv on dv.documento_id = d.id cross join lateral fn_fato_resolver(dv.id) r where fn_tipo_gera_fato(d.tipo_taxonomia) offset 0) z;",
 'P01 gatilho da pendencia removido': "drop trigger trg_fato_pendencia_da_extracao on evento_auditoria;",
 'P02 funcao do gatilho sem chamar a avaliacao': multi('fn_fato_pendencia_da_extracao()', [("v_pend := fn_fato_pendencia_da_versao(v_versao);", "v_pend := null;")]),
 'P03 versao superada nao baixa a pendencia': multi('fn_fato_pendencia_da_extracao()', [("if v_vigente = v_versao then", "if false then")]),
 'P04 query_canceled engolido': multi('fn_fato_pendencia_da_extracao()', [("when query_canceled then raise;", "when query_canceled then null;")]),
 'P05 pendencia aberta para o que ja estava gravado (o que um backfill que abrisse fila faria)': "select fn_fato_pendencia_da_versao(f.documento_versao_id) from (select distinct documento_versao_id from fato_financeiro where resolucao_metodo <> 'declarada' and caso_id in ('11111111-1111-1111-1111-111111111111', '11111111-3333-3333-3333-111111111111')) f;",
 'P06 transcricao humana abre pendencia (gatilho em campo_extraido)': "create function fn_sab_transcricao() returns trigger language plpgsql as $f$ begin if new.origem_valor = 'transcricao_humana' then perform fn_fato_pendencia_da_versao(new.documento_versao_id); end if; return null; end $f$; create trigger trg_sab_transcricao after insert on campo_extraido for each row execute function fn_sab_transcricao();",
 'P07 troca de tipo do documento abre pendencia (gatilho em documento)': "create function fn_sab_tipo() returns trigger language plpgsql as $f$ declare v uuid; begin for v in select id from documento_versao where documento_id = new.id loop perform fn_fato_pendencia_da_versao(v); end loop; return null; end $f$; create trigger trg_sab_tipo after update of tipo_taxonomia on documento for each row when (old.tipo_taxonomia is distinct from new.tipo_taxonomia) execute function fn_sab_tipo();",
 'P08 pendencia sem a guarda de escrita (fn_fato_pode_escrever sempre verdadeira)': "create or replace function fn_fato_pode_escrever(p_caso uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $q$ select true $q$;",
 'P09 fn_registrar_campos_extraidos sem gravar o ln (o que reemitir do corpo antigo apagaria)': fn_replace('fn_registrar_campos_extraidos(uuid,jsonb,nivel_autonomia,text,boolean,jsonb)', "        v_ln,\n", "        null,\n"),
 'N01 sonda "recentes" fixa em ok': "create or replace view instalacao_sonda_fato_financeiro_recentes as select 1 as ok;",
 'N02 sonda "view_invoker" fixa em ok': "create or replace view instalacao_sonda_fato_financeiro_view_invoker as select 1 as ok;",
 'N03 sonda "so_le" fixa em ok': "create or replace view instalacao_sonda_fato_financeiro_so_le as select 1 as ok;",
 'N04 sonda "cadeia" fixa em 17': "create or replace view instalacao_sonda_fato_financeiro_cadeia as select generate_series(1, 17)::text as funcao;",
}

if not SEL or any(x == 'CONTROLE' for x in SEL):
    print('CONTROLE (migration intacta, teste sem o topo):'); relata('controle', roda_teste())

for nome, s in SAB.items():
    if SEL and not any(nome.startswith(x + ' ') for x in SEL):
        continue
    o = sql(s)
    if 'SABOTAGEM NAO APLICOU' in o or 'ERROR' in o:
        print(nome, '-> FALHA AO SABOTAR:', o[:300].replace('\n', ' ')); restaura(); continue
    relata(nome, roda_teste())
    # limpeza do que so existe na sabotagem
    sql("drop trigger if exists trg_sab_transcricao on campo_extraido; drop function if exists fn_sab_transcricao(); drop trigger if exists trg_sab_tipo on documento; drop function if exists fn_sab_tipo();")
    restaura()

# --- as sabotagens de MIGRATION (rodam o teste COM o topo, apontando para a copia sabotada) ---
def variante(nome, pares):
    txt = open(MIG).read()
    for a, b in pares:
        if a not in txt:
            print(nome, '-> FALHA AO SABOTAR (texto nao existe):', a[:80]); return None
        txt = txt.replace(a, b)
    arq = f'{TMP}/mig_' + re.sub(r'\W+', '_', nome[:12]) + '.sql'
    open(arq, 'w').write(txt); os.chmod(arq, 0o644)
    return arq

MIGSAB = {
 'M01 migration SEM o revoke da view (o default de privilegio do Supabase deixa o anon e o authenticated escreverem)': [("revoke all on fato_financeiro from public, anon, authenticated, service_role;\n", "")],
 'M02 migration SEM os grants da cadeia (o ACL estrito deixa a view ilegivel)': [("      execute format('grant execute on function %s to %I', v_f, v_p);", "      null;")],
 'M03 migration SEM o revoke do resolver do anon/authenticated (default de funcao)': [("revoke all on function fn_fato_resolver(uuid), fn_tipo_gera_fato(text), fn_linha_vira_fato(text, text, text, numeric) from public, anon, authenticated, service_role;\n", "")],
 'M04 migration SEM o revoke das funcoes internas (default de funcao)': [("revoke all on function fn_fato_ator(), fn_fato_pode_escrever(uuid) from public, anon, authenticated, service_role;", ""), ("revoke all on function fn_fato_pendencia_da_versao(uuid), fn_fato_pendencia_da_extracao() from public, anon, authenticated, service_role;", "")],
 'M05 view SEM security_invoker na migration': [("create or replace view fato_financeiro with (security_invoker = true) as", "create or replace view fato_financeiro as")],
 'M06 migration SEM a lista de cadeia no catalogo da sonda (17 vira 5)': [("('fn_tokens_estruturais(text)'), ('fn_mes_do_rotulo(text)'), ('fn_ano4(text)'), ('fn_anos_periodo(text, text)'), ('fn_coluna_e_abertura(text)'), ('fn_coluna_e_saldo(text)'),\n                 ('fn_coluna_entidade(uuid, uuid)'), ('fn_entidade_canonica(text)'), ('fn_mesma_entidade(text, text)'), ('fn_normalizar_texto(text)'), ('fn_periodo_canonico(text, text)'),\n                 ('fn_periodo_e_parcial(text, text, text, text)')", "('fn_ano4(text)')")],
}
for nome, pares in MIGSAB.items():
    if SEL and not any(nome.startswith(x + ' ') for x in SEL):
        continue
    arq = variante(nome, pares)
    if not arq:
        continue
    o = psql(f'-v ON_ERROR_STOP=1 -f {arq}')
    if 'ERROR' in o:
        print(nome, '-> a migration sabotada nao aplicou:', o[:300].replace('\n', ' ')); restaura(); continue
    relata(nome, roda_teste(com_topo_mig=arq))
    restaura()

print('FIM')
