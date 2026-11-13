\timing on
\set ca '121ec4b0-2888-40d8-9573-2d560b88a7bb'
select dv.id as v1 from documento_versao dv join documento d on d.id=dv.documento_id where d.caso_id=:'ca' order by dv.criada_em limit 1 \gset
\echo == ANTES (jit=on na sessao, resolver inlinado)
select count(*) from fato_financeiro where caso_id = '11111111-3333-3333-3333-111111111111';
select count(*) from fato_financeiro where caso_id = '11111111-1111-1111-1111-111111111111';
select count(*) from fato_financeiro where documento_versao_id = :'v1';
select count(*) from fato_financeiro where caso_id = :'ca';
alter function fn_fato_resolver(uuid) set jit = off;
\echo == DEPOIS (SET jit = off na funcao: nao e mais inlinada)
select count(*) from fato_financeiro where caso_id = '11111111-3333-3333-3333-111111111111';
select count(*) from fato_financeiro where caso_id = '11111111-1111-1111-1111-111111111111';
select count(*) from fato_financeiro where documento_versao_id = :'v1';
select count(*) from fato_financeiro where caso_id = :'ca';
set track_functions='all';
select count(*) from fato_financeiro where caso_id = '11111111-3333-3333-3333-111111111111';
select funcname, calls from pg_stat_user_functions where funcname = 'fn_fato_resolver';
alter function fn_fato_resolver(uuid) reset jit;
