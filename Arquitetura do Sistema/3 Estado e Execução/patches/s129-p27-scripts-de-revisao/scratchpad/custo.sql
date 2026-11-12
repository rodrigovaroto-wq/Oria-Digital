\set ON_ERROR_STOP on
\timing on
begin;
-- reaplica o 0270 body? o corpo vigente já é o da 0270 (teste 0270 rodou)
do $$
declare v_caso uuid; v_ver uuid; v_campos jsonb; t0 timestamptz; t1 timestamptz; v_n int;
begin
  v_caso := fn_upsert_caso('custo 0243')::uuid;
  perform fn_upsert_entidade(v_caso, 'CUSTO LTDA'); perform fn_upsert_periodo(v_caso, 'anual', '2025');
  select jsonb_agg(jsonb_build_object('chave', 'Conta de balancete numero ' || g, 'valor_num', g::text, 'secao_canonica', 'ativo_circulante', 'secao', 'ATIVO CIRCULANTE', 'periodo_coluna', 'Saldo Atual', 'confianca', '0.97', 'ln', g))
    into v_campos from generate_series(1, 4000) g;
  for i in 1..2 loop
    v_ver := (fn_registrar_documento(v_caso, 'CUSTO LTDA', 'anual', '2025', 'BALANCETE', 0.97, 'nome_arquivo', 'supabase_storage', '0243/custo' || i || '.pdf', 'custo' || i || '.pdf', true, 'custo' || i, 'ok')->>'documento_versao_id')::uuid;
    if i = 2 then alter table evento_auditoria disable trigger trg_fato_extracao_nova; end if;
    t0 := clock_timestamp();
    v_n := fn_registrar_campos_extraidos(v_ver, v_campos);
    t1 := clock_timestamp();
    raise notice 'variante % (%): % linhas em % ms; fatos %', i, case when i = 1 then 'COM o gatilho' else 'gatilho DESLIGADO' end, v_n, round(extract(epoch from t1 - t0) * 1000), (select count(*) from fato_financeiro where documento_versao_id = v_ver);
  end loop;
end $$;
rollback;
