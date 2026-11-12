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
