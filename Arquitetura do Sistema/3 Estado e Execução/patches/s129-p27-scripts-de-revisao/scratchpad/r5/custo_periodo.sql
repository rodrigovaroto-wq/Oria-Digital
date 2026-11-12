begin;
do $$
declare v_caso uuid; v_ver uuid; v_campos jsonb; t0 timestamptz; v_r jsonb; v_n int;
begin
  v_caso := fn_upsert_caso('custo r5')::uuid;
  perform fn_upsert_entidade(v_caso, 'CUSTO5 LTDA'); perform fn_upsert_periodo(v_caso, 'anual', '2025');
  for d in 1..10 loop
    select jsonb_agg(jsonb_build_object('chave', 'Conta de balancete numero ' || (((d*4000 + g) % 6800)), 'valor_num', g::text, 'secao_canonica', 'ativo_circulante', 'secao', 'ATIVO CIRCULANTE', 'periodo_coluna', 'Débito', 'confianca', '0.97', 'ln', g))
      into v_campos from generate_series(1, 4000) g;
    v_ver := (fn_registrar_documento(v_caso, 'CUSTO5 LTDA', 'anual', '2025', 'BALANCETE', 0.97, 'nome_arquivo', 'supabase_storage', 'c5/' || d || '.pdf', 'c5' || d || '.pdf', true, 'c5h' || d, 'ok')->>'documento_versao_id')::uuid;
    perform fn_registrar_campos_extraidos(v_ver, v_campos);
  end loop;
  select count(*) into v_n from fato_financeiro f join documento_versao dv on dv.id=f.documento_versao_id join documento d on d.id=dv.documento_id where d.caso_id=v_caso and f.periodo_id is null;
  raise notice 'fatos sem periodo no mandato: %', v_n;
  t0 := clock_timestamp(); perform fn_upsert_periodo(v_caso, 'anual', '2024'); raise notice 'fn_upsert_periodo(2024) num mandato de 10 versoes de 4000 linhas: % ms', round(extract(epoch from clock_timestamp()-t0)*1000);
  t0 := clock_timestamp(); perform fn_upsert_periodo(v_caso, 'mensal', '2025-06'); raise notice 'fn_upsert_periodo(2025-06): % ms', round(extract(epoch from clock_timestamp()-t0)*1000);
  t0 := clock_timestamp(); v_ver := (fn_registrar_documento(v_caso, 'CUSTO5 LTDA', 'anual', '2023', 'DRE', 0.97, 'nome_arquivo', 'supabase_storage', 'c5/n.pdf', 'c5n.pdf', true, 'c5hn', 'ok')->>'documento_versao_id')::uuid;
  raise notice 'fn_registrar_documento de um documento NOVO de 2023 (cria o periodo): % ms', round(extract(epoch from clock_timestamp()-t0)*1000);
end $$;
rollback;
