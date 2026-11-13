\i /tmp/p27/perf/gen.sql
select fn_upsert_caso('perf: extracao com e sem gatilho')::uuid as caso \gset
select fn_upsert_entidade(:'caso'::uuid, 'EXT LTDA')\gset
select fn_upsert_periodo(:'caso'::uuid, 'anual', '2025')\gset
\echo == COM o gatilho (balancete de 4.000 rotulos distintos, 1 linha em 17 sem secao)
select pg_temp.gen(:'caso'::uuid, 'EXT LTDA', 4, 'ea', 4000);
alter table evento_auditoria disable trigger trg_fato_pendencia_da_extracao;
\echo == SEM o gatilho
select pg_temp.gen(:'caso'::uuid, 'EXT LTDA', 4, 'eb', 4000);
alter table evento_auditoria enable trigger trg_fato_pendencia_da_extracao;
