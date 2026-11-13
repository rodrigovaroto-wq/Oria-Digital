\i /tmp/p27/perf/gen.sql
select fn_upsert_caso('perf: pequenas')::uuid as caso \gset
select fn_upsert_entidade(:'caso'::uuid, 'SMALL LTDA')\gset
select fn_upsert_periodo(:'caso'::uuid, 'anual', '2025')\gset
-- 3 documentos pequenos (100 linhas) com o gatilho; depois sem
select pg_temp.gen(:'caso'::uuid, 'SMALL LTDA', 3, 'sm', 100);
alter table evento_auditoria disable trigger trg_fato_pendencia_da_extracao;
select pg_temp.gen(:'caso'::uuid, 'SMALL LTDA', 3, 'sn', 100);
alter table evento_auditoria enable trigger trg_fato_pendencia_da_extracao;
