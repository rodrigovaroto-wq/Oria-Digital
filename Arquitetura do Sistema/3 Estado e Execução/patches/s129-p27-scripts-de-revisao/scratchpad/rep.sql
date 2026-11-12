\set QUIET on
select pg_temp.doc('11111111-1111-1111-1111-111111111111', 'VERTENTES METALÚRGICA LTDA.', '2025', 'DRE', 'rev4dup',
  jsonb_build_array(pg_temp.l('Receita de vendas','100','receita_bruta'))) as v1 \gset
select pg_temp.doc('11111111-1111-1111-1111-111111111111', 'VERTENTES METALÚRGICA LTDA.', '2025', 'DRE', 'rev4dup',
  jsonb_build_array(pg_temp.l('Receita de vendas','100','receita_bruta',null,null,'Consolidado'), pg_temp.l('Receita de vendas','40','receita_bruta',null,null,'Vertentes Componentes'))) as v2 \gset
\unset QUIET
select :'v1' = :'v2' as mesma_versao;
select chave, valor, ecol, ent, eorig, emot, per, pmot from pg_temp.fv where v = :'v2' order by valor;
-- do zero
select pg_temp.doc('11111111-1111-1111-1111-111111111111', 'VERTENTES METALÚRGICA LTDA.', '2025', 'DRE', 'rev4dupz',
  jsonb_build_array(pg_temp.l('Receita de vendas','100','receita_bruta'), pg_temp.l('Receita de vendas','100','receita_bruta',null,null,'Consolidado'), pg_temp.l('Receita de vendas','40','receita_bruta',null,null,'Vertentes Componentes'))) as v3 \gset
select chave, valor, ecol, ent, eorig, emot, per from pg_temp.fv where v = :'v3' order by valor;
