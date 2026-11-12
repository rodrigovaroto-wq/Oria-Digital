\timing off
begin;
create temp table _t as select 1;
do $$
declare v_caso uuid; v_ent uuid; v_ent2 uuid; v_ver uuid; v_campos jsonb; t0 timestamptz; v_r jsonb; v_n int; v_doc uuid;
begin
  v_caso := fn_upsert_caso('custo 4a revisao')::uuid;
  v_ent := fn_upsert_entidade(v_caso, 'CUSTO4 LTDA'); v_ent2 := fn_upsert_entidade(v_caso, 'CUSTO4 OUTRA SA'); perform fn_upsert_periodo(v_caso, 'anual', '2025');
  alter table evento_auditoria disable trigger trg_fato_extracao_nova;
  for d in 1..20 loop
    select jsonb_agg(jsonb_build_object('chave', 'Conta de balancete numero ' || (((d*4000 + g) % 6800)), 'valor_num', g::text, 'secao_canonica', 'ativo_circulante', 'secao', 'ATIVO CIRCULANTE', 'periodo_coluna', 'Saldo Atual', 'confianca', '0.97', 'ln', g))
      into v_campos from generate_series(1, 4000) g;
    v_ver := (fn_registrar_documento(v_caso, 'CUSTO4 LTDA', 'anual', '2025', 'BALANCETE', 0.97, 'nome_arquivo', 'supabase_storage', 'c4/' || d || '.pdf', 'c4' || d || '.pdf', true, 'c4h' || d, 'ok')->>'documento_versao_id')::uuid;
    perform fn_registrar_campos_extraidos(v_ver, v_campos);
  end loop;
  alter table evento_auditoria enable trigger trg_fato_extracao_nova;
  select count(*) into v_n from campo_extraido; raise notice 'campo_extraido total: %', v_n;
  t0 := clock_timestamp(); v_r := fn_fato_recalcular(null, 'backfill_0243'); raise notice 'recalculo COMPLETO com % linhas elegiveis a criar: % ms (criados %)', v_n, round(extract(epoch from clock_timestamp()-t0)*1000), v_r->>'fatos_criados';
  select count(*) into v_n from fato_financeiro; raise notice 'fatos: %', v_n;
  t0 := clock_timestamp(); v_r := fn_fato_recalcular(null, 'backfill_0243'); raise notice 'recalculo FINAL (tudo ja existe, nada a mudar): % ms (atualizados %, criados %)', round(extract(epoch from clock_timestamp()-t0)*1000), v_r->>'atualizados', v_r->>'fatos_criados';
  -- uma extracao nova de 4000 linhas COM o gatilho
  select jsonb_agg(jsonb_build_object('chave', 'Conta nova numero ' || g, 'valor_num', g::text, 'secao_canonica', 'ativo_circulante', 'secao', 'ATIVO CIRCULANTE', 'periodo_coluna', 'Saldo Atual', 'confianca', '0.97', 'ln', g)) into v_campos from generate_series(1, 4000) g;
  v_ver := (fn_registrar_documento(v_caso, 'CUSTO4 LTDA', 'anual', '2025', 'BALANCETE', 0.97, 'nome_arquivo', 'supabase_storage', 'c4/x.pdf', 'c4x.pdf', true, 'c4hx', 'ok')->>'documento_versao_id')::uuid;
  t0 := clock_timestamp(); v_n := fn_registrar_campos_extraidos(v_ver, v_campos); raise notice 'EXTRACAO de 4000 linhas (COM o recalculo): % ms', round(extract(epoch from clock_timestamp()-t0)*1000);
  select documento_id into v_doc from documento_versao where id = v_ver;
  t0 := clock_timestamp(); update documento set entidade_id = v_ent2 where id = v_doc; raise notice 'UPDATE de documento.entidade_id (4000 linhas): % ms', round(extract(epoch from clock_timestamp()-t0)*1000);
  t0 := clock_timestamp(); update documento set entidade_id = v_ent where id = v_doc; raise notice 'UPDATE de volta: % ms', round(extract(epoch from clock_timestamp()-t0)*1000);
  t0 := clock_timestamp(); insert into entidade (caso_id, razao_social) values (v_caso, 'CUSTO4 TERCEIRA LTDA'); raise notice 'CADASTRO de entidade no mandato (21 versoes de 4000, so as que dependem): % ms', round(extract(epoch from clock_timestamp()-t0)*1000);
  t0 := clock_timestamp(); v_r := fn_materializar_fatos(v_ver); raise notice 'reparo de UMA versao: % ms', round(extract(epoch from clock_timestamp()-t0)*1000);
end $$;
rollback;
