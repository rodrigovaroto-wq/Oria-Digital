-- gera D versões de balancete de 4000 linhas (rótulos distintos até 6800) no mandato :caso; mede a extração com o gatilho
\set ON_ERROR_STOP on
\timing off
create or replace function pg_temp.gen(p_caso uuid, p_ent text, p_n int, p_tag text, p_linhas int default 4000) returns void language plpgsql as $$
declare v_campos jsonb; v_ver uuid; t0 timestamptz; d int;
begin
  for d in 1..p_n loop
    select jsonb_agg(jsonb_build_object('chave', 'Conta de balancete numero ' || (((d*p_linhas + g) % 6800)), 'valor_num', g::text, 'secao_canonica', case when g % 17 = 0 then null else 'ativo_circulante' end, 'secao', 'ATIVO CIRCULANTE', 'periodo_coluna', 'Saldo Atual', 'confianca', '0.97', 'ln', g))
      into v_campos from generate_series(1, p_linhas) g;
    v_ver := (fn_registrar_documento(p_caso, p_ent, 'anual', '2025', 'BALANCETE', 0.97, 'nome_arquivo', 'supabase_storage', p_tag || '/' || d || '.pdf', p_tag || d || '.pdf', true, p_tag || 'h' || d, 'ok')->>'documento_versao_id')::uuid;
    t0 := clock_timestamp();
    perform fn_registrar_campos_extraidos(v_ver, v_campos);
    raise notice 'extração % (% linhas): % ms', d, p_linhas, round(extract(epoch from clock_timestamp()-t0)*1000);
  end loop;
end $$;
