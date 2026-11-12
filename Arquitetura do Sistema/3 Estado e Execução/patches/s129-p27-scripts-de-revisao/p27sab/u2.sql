begin;
do $$ declare v_caso uuid; v_e1 uuid; v_e2 uuid; v_ver uuid; v_doc uuid; v_n int; t0 timestamptz; v_campos jsonb;
begin
  v_caso := fn_upsert_caso('u')::uuid; v_e1 := fn_upsert_entidade(v_caso,'U UM LTDA'); v_e2 := fn_upsert_entidade(v_caso,'U DOIS SA'); perform fn_upsert_periodo(v_caso,'anual','2025');
  select jsonb_agg(jsonb_build_object('chave','Conta '||g,'valor_num',g::text,'secao_canonica','ativo_circulante','periodo_coluna','Saldo Atual','confianca','0.97')) into v_campos from generate_series(1,4000) g;
  v_ver := (fn_registrar_documento(v_caso,'U UM LTDA','anual','2025','BALANCETE',0.97,'nome_arquivo','supabase_storage','u/1.pdf','u1.pdf',true,'uh1','ok')->>'documento_versao_id')::uuid;
  t0 := clock_timestamp(); perform fn_registrar_campos_extraidos(v_ver, v_campos); raise notice 'EXTRACAO 4000 linhas: % ms', round(extract(epoch from clock_timestamp()-t0)*1000);
  select documento_id into v_doc from documento_versao where id=v_ver;
  select count(*) into v_n from fato_financeiro where documento_versao_id=v_ver and entidade_id=v_e1; raise notice 'fatos na entidade 1: %', v_n;
  t0 := clock_timestamp(); update documento set entidade_id = v_e2 where id=v_doc; raise notice 'UPDATE entidade_id: % ms', round(extract(epoch from clock_timestamp()-t0)*1000);
  select count(*) into v_n from fato_financeiro where documento_versao_id=v_ver and entidade_id=v_e2; raise notice 'fatos na entidade 2: %', v_n;
end $$; rollback;
