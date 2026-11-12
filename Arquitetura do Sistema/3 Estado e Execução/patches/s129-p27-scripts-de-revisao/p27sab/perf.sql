\timing off
begin;
create temp table _m(k text, ms numeric);
create or replace function pg_temp.t(p_k text, p_sql text) returns void language plpgsql as $$
declare t0 timestamptz := clock_timestamp(); n bigint;
begin execute p_sql into n; insert into _m values (p_k || ' (n=' || n || ')', round(extract(epoch from clock_timestamp()-t0)*1000)); end $$;
do $$
declare v_caso uuid; v_caso2 uuid; v_ver uuid; v_campos jsonb; v_n int;
begin
  alter table evento_auditoria disable trigger trg_fato_extracao_nova;
  v_caso := fn_upsert_caso('perf mandato grande')::uuid; perform fn_upsert_entidade(v_caso, 'PERF LTDA'); perform fn_upsert_periodo(v_caso, 'anual', '2025');
  for d in 1..10 loop
    select jsonb_agg(jsonb_build_object('chave', 'Conta de balancete numero ' || (((d*4000 + g) % 6800)), 'valor_num', g::text, 'secao_canonica', 'ativo_circulante', 'secao', 'ATIVO CIRCULANTE', 'periodo_coluna', 'Saldo Atual', 'confianca', '0.97')) into v_campos from generate_series(1, 4000) g;
    v_ver := (fn_registrar_documento(v_caso, 'PERF LTDA', 'anual', '2025', 'BALANCETE', 0.97, 'nome_arquivo', 'supabase_storage', 'pf/' || d || '.pdf', 'pf' || d || '.pdf', true, 'pfh' || d, 'ok')->>'documento_versao_id')::uuid;
    perform fn_registrar_campos_extraidos(v_ver, v_campos);
    if d = 1 then perform set_config('pf.v1', v_ver::text, true); end if;
  end loop;
  perform set_config('pf.caso', v_caso::text, true);
  -- mais 10 documentos de OUTRO mandato, para o total ficar perto de 85 mil
  v_caso2 := fn_upsert_caso('perf outro mandato')::uuid; perform fn_upsert_entidade(v_caso2, 'PERF2 LTDA'); perform fn_upsert_periodo(v_caso2, 'anual', '2025');
  for d in 1..10 loop
    select jsonb_agg(jsonb_build_object('chave', 'Conta de balancete numero ' || (((d*4000 + g) % 6800)), 'valor_num', g::text, 'secao_canonica', 'ativo_circulante', 'secao', 'ATIVO CIRCULANTE', 'periodo_coluna', 'Saldo Atual', 'confianca', '0.97')) into v_campos from generate_series(1, 4000) g;
    v_ver := (fn_registrar_documento(v_caso2, 'PERF2 LTDA', 'anual', '2025', 'BALANCETE', 0.97, 'nome_arquivo', 'supabase_storage', 'pg/' || d || '.pdf', 'pg' || d || '.pdf', true, 'pgh' || d, 'ok')->>'documento_versao_id')::uuid;
    perform fn_registrar_campos_extraidos(v_ver, v_campos);
  end loop;
  alter table evento_auditoria enable trigger trg_fato_extracao_nova;
  select count(*) into v_n from campo_extraido; raise notice 'campo_extraido: %', v_n;
end $$;
select pg_temp.t('1 resolver de UMA versao de 4000 linhas', format('select count(*) from fn_fato_resolver(%L)', current_setting('pf.v1')));
select pg_temp.t('2 view filtrada por UMA versao', format('select count(*) from fato_financeiro where documento_versao_id = %L', current_setting('pf.v1')));
select pg_temp.t('3 view do maior mandato das fixtures (join documento por caso)', $q$select count(*) from fato_financeiro f join documento_versao dv on dv.id = f.documento_versao_id join documento d on d.id = dv.documento_id where d.caso_id = (select d2.caso_id from documento d2 join documento_versao v2 on v2.documento_id = d2.id join campo_extraido c on c.documento_versao_id = v2.id and c.id::text < 'g' where d2.caso_id not in (current_setting('pf.caso')::uuid) group by d2.caso_id order by count(*) desc limit 1)$q$);
select pg_temp.t('4 view de um mandato sintetico 10x4000 (join por caso)', format('select count(*) from fato_financeiro f join documento_versao dv on dv.id = f.documento_versao_id join documento d on d.id = dv.documento_id where d.caso_id = %L', current_setting('pf.caso')));
select pg_temp.t('5 view INTEIRA', 'select count(*) from fato_financeiro');
select pg_temp.t('6 sonda responde', 'select count(*) from instalacao_sonda_fato_financeiro_responde');
select pg_temp.t('7 fn_instalacao_conferir() inteira', 'select count(*) from fn_instalacao_conferir()');
select * from _m order by k;
rollback;
