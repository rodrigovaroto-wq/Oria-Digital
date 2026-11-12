begin;
do $$
declare v_caso uuid; v_ver uuid; v_campos jsonb; t0 timestamptz; v_n int;
begin
  v_caso := fn_upsert_caso('custo trg')::uuid; perform fn_upsert_entidade(v_caso, 'TRG LTDA'); perform fn_upsert_periodo(v_caso, 'anual', '2025');
  alter table evento_auditoria disable trigger trg_fato_extracao_nova;
  for d in 1..20 loop
    select jsonb_agg(jsonb_build_object('chave', 'Conta ' || (((d*4000 + g) % 6800)), 'valor_num', g::text, 'secao_canonica', 'ativo_circulante', 'confianca', '0.97')) into v_campos from generate_series(1, 4000) g;
    v_ver := (fn_registrar_documento(v_caso, 'TRG LTDA', 'anual', '2025', 'BALANCETE', 0.97, 'nome_arquivo', 'supabase_storage', 't/' || d || '.pdf', 't' || d || '.pdf', true, 'th' || d, 'ok')->>'documento_versao_id')::uuid;
    perform fn_registrar_campos_extraidos(v_ver, v_campos);
  end loop;
  select count(*) into v_n from campo_extraido; raise notice 'linhas: %', v_n;
  for i in 1..2 loop
    t0 := clock_timestamp(); update campo_extraido set secao_canonica = secao_canonica where documento_versao_id in (select id from documento_versao where nome_original like 't%.pdf'); raise notice 'UPDATE de secao em 80000 linhas SEM gatilho: % ms', round(extract(epoch from clock_timestamp()-t0)*1000);
  end loop;
  create function pg_temp.noop() returns trigger language plpgsql as $f$ begin return null; end $f$;
  create trigger trg_teste after update on campo_extraido referencing old table as o new table as n for each statement execute function pg_temp.noop();
  for i in 1..2 loop
    t0 := clock_timestamp(); update campo_extraido set secao_canonica = secao_canonica where documento_versao_id in (select id from documento_versao where nome_original like 't%.pdf'); raise notice 'UPDATE de secao em 80000 linhas COM gatilho de instrucao com tabelas de transicao (corpo vazio): % ms', round(extract(epoch from clock_timestamp()-t0)*1000);
  end loop;
  drop trigger trg_teste on campo_extraido;
  t0 := clock_timestamp(); update campo_extraido set status_aceite = status_aceite where documento_versao_id in (select id from documento_versao where nome_original like 't%.pdf'); raise notice 'UPDATE de status_aceite (outra coluna) SEM gatilho: % ms', round(extract(epoch from clock_timestamp()-t0)*1000);
end $$;
rollback;
