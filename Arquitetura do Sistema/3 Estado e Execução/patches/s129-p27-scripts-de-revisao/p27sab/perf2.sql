begin;
do $$
declare v_caso uuid; v_ver uuid; v_campos jsonb; t0 timestamptz; v_n int;
begin
  select id into v_caso from caso where nome = 'perf mandato grande' limit 1;
  if v_caso is null then select caso_id into v_caso from documento order by criado_em desc limit 1; end if;
  select jsonb_agg(jsonb_build_object('chave', 'Conta nova numero ' || g, 'valor_num', g::text, 'secao_canonica', case when g % 10 = 0 then null else 'ativo_circulante' end, 'secao', 'ATIVO CIRCULANTE', 'periodo_coluna', 'Saldo Atual', 'confianca', '0.97', 'ln', g)) into v_campos from generate_series(1, 4000) g;
  for i in 1..3 loop
    if i = 3 then alter table evento_auditoria disable trigger trg_fato_extracao_nova; end if;
    v_ver := (fn_registrar_documento(v_caso, 'PERF LTDA', 'anual', '2025', 'BALANCETE', 0.97, 'nome_arquivo', 'supabase_storage', 'px/' || i || '.pdf', 'px' || i || '.pdf', true, 'pxh' || i, 'ok')->>'documento_versao_id')::uuid;
    t0 := clock_timestamp(); v_n := fn_registrar_campos_extraidos(v_ver, v_campos);
    raise notice 'EXTRACAO 4000 linhas (400 sem secao) %: % ms', case when i = 3 then 'SEM o gatilho da pendencia' else 'COM o gatilho da pendencia' end, round(extract(epoch from clock_timestamp()-t0)*1000);
  end loop;
end $$;
rollback;
