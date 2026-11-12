\set QUIET on
insert into caso (id, nome) values ('a4a4a4a4-0000-0000-0000-000000000001', 'rev4 fusao') ;
insert into entidade (id, caso_id, razao_social) values ('a4a4a4a4-0000-0000-0000-0000000000a1','a4a4a4a4-0000-0000-0000-000000000001','ALFA COMERCIO LTDA'), ('a4a4a4a4-0000-0000-0000-0000000000a2','a4a4a4a4-0000-0000-0000-000000000001','ATACADO ALFA LTDA');
select pg_temp.doc('a4a4a4a4-0000-0000-0000-000000000001', 'ALFA COMERCIO LTDA', '2025', 'DRE', 'rev4fus',
  jsonb_build_array(pg_temp.l('Receita de vendas','100','receita_bruta',null,null,'Alfa Comércio'), pg_temp.l('Receita de vendas','70','receita_bruta',null,null,'Atacado Alfa'))) as v \gset
\unset QUIET
select valor, ecol, ent, eorig, emot from pg_temp.fv where v = :'v' order by valor;
select fn_fundir_entidade('a4a4a4a4-0000-0000-0000-000000000001','a4a4a4a4-0000-0000-0000-0000000000a2','a4a4a4a4-0000-0000-0000-0000000000a1') is not null as fundiu;
select valor, ecol, ent, eorig, emot from pg_temp.fv where v = :'v' order by valor;
-- o que a mesma versao daria do zero, agora: re-resolve por um gatilho de cadastro qualquer
insert into entidade (caso_id, razao_social) values ('a4a4a4a4-0000-0000-0000-000000000001','OMEGA QUALQUER LTDA');
select valor, ecol, ent, eorig, emot from pg_temp.fv where v = :'v' order by valor;
