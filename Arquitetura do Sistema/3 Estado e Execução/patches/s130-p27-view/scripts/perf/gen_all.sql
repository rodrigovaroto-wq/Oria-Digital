\i /tmp/p27/perf/gen.sql
\set ON_ERROR_STOP on
select fn_upsert_caso('perf: mandato 10x4000 (A)')::uuid as c1 \gset
select fn_upsert_entidade(:'c1'::uuid, 'PERF A LTDA')\gset
select fn_upsert_periodo(:'c1'::uuid, 'anual', '2025')\gset
select pg_temp.gen(:'c1'::uuid, 'PERF A LTDA', 10, 'pa', 4000);
select fn_upsert_caso('perf: mandato 10x4000 (B)')::uuid as c2 \gset
select fn_upsert_entidade(:'c2'::uuid, 'PERF B LTDA')\gset
select fn_upsert_periodo(:'c2'::uuid, 'anual', '2025')\gset
select pg_temp.gen(:'c2'::uuid, 'PERF B LTDA', 10, 'pb', 4000);
-- um analista alocado só no mandato A
insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000bb01', 'perf.ana@teste.local');
insert into membro (usuario_id, papel) values ('00000000-0000-0000-0000-00000000bb01', 'analista');
insert into alocacao (caso_id, usuario_id) values (:'c1'::uuid, '00000000-0000-0000-0000-00000000bb01');
analyze;
select :'c1' as caso_a, :'c2' as caso_b;
