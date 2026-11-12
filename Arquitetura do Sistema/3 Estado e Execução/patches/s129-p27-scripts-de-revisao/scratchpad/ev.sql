begin;
do $$ declare t0 timestamptz; t1 timestamptz; begin
 for i in 1..3 loop
  if i = 3 then alter table evento_auditoria disable trigger trg_fato_extracao_nova; end if;
  t0 := clock_timestamp();
  insert into evento_auditoria (ator, acao, entidade_ref, depois) select 'teste', 'outro_evento', 'x:' || g, '{}'::jsonb from generate_series(1, 100000) g;
  t1 := clock_timestamp();
  raise notice 'rodada % (%): 100000 eventos em % ms', i, case when i = 3 then 'sem gatilho' else 'com gatilho' end, round(extract(epoch from t1 - t0) * 1000);
 end loop; end $$;
rollback;
