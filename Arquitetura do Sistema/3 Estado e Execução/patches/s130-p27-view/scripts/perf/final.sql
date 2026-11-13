\timing on
\set ca '121ec4b0-2888-40d8-9573-2d560b88a7bb'
\set cb '200b9cbb-6035-47e4-be97-c949d14be661'
select count(*) as total_linhas_campo_extraido from campo_extraido \gset
\echo == linhas no banco: :total_linhas_campo_extraido
select dv.id as v1 from documento_versao dv join documento d on d.id=dv.documento_id where d.caso_id=:'ca' order by dv.criada_em limit 1 \gset
\echo == 1. uma versao de 4.000 linhas (superusuario), 3 leituras
select count(*) from fato_financeiro where documento_versao_id = :'v1';
select count(*) from fato_financeiro where documento_versao_id = :'v1';
select count(*) from fato_financeiro where documento_versao_id = :'v1';
\echo == 2. o maior mandato das fixtures (1.264 linhas) e o segundo (767)
select count(*) from fato_financeiro where caso_id = '11111111-3333-3333-3333-111111111111';
select count(*) from fato_financeiro where caso_id = '11111111-1111-1111-1111-111111111111';
\echo == 3. mandato sintetico 10 x 4.000 (40.000 linhas), 3 leituras
select count(*) from fato_financeiro where caso_id = :'ca';
select count(*) from fato_financeiro where caso_id = :'ca';
select count(*) from fato_financeiro where caso_id = :'ca';
\echo == 3b. o mesmo mandato lido linha a linha com soma (o uso tipico: somar por conta e periodo)
select conta_id, periodo_id is not null as com_periodo, count(*), sum(valor) from fato_financeiro where caso_id = :'ca' group by 1,2;
\echo == 4. a view INTEIRA
select count(*) from fato_financeiro;
select count(*) from fato_financeiro;
\echo == 5. como AUTHENTICATED (Analista alocada so no mandato A): RLS por mandato por linha
begin;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000bb01","role":"authenticated"}', true);
set local role authenticated;
select count(*) from fato_financeiro where caso_id = :'ca';
select count(*) from fato_financeiro where caso_id = :'ca';
select count(*) from fato_financeiro where documento_versao_id = :'v1';
select count(*) from fato_financeiro;
rollback;
\echo == 6. a sonda inteira e a amostra da sonda (3 versoes mais novas de demonstração: aqui sao 3 de 4.000 linhas)
select count(*) from fn_instalacao_conferir();
select fn_fato_sonda_recentes();
\echo == 7. a APLICACAO da migration sobre esse banco (reaplicar)

