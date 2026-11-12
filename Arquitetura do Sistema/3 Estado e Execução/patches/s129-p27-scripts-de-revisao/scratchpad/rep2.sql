\set QUIET on
select pg_temp.doc('11111111-1111-1111-1111-111111111111', 'VERTENTES METALÚRGICA LTDA.', '2025', 'DRE', 'rev4bloco',
  jsonb_build_array(pg_temp.l('Receita de vendas','100','receita_bruta'))) as v \gset
select fn_registrar_campos_extraidos(:'v'::uuid, jsonb_build_array(pg_temp.l('Receita de vendas','100','receita_bruta',null,null,'Consolidado'), pg_temp.l('Receita de vendas','40','receita_bruta',null,null,'Vertentes Componentes'))) is not null as ok \gset
\unset QUIET
select chave, valor, ecol, ent, eorig, emot, per from pg_temp.fv where v = :'v' order by valor;
select ent, per, conta_id, sum(valor) from pg_temp.fv where v = :'v' and ent is not null and per is not null group by 1,2,3;
select count(*) from instalacao_sonda_fato_financeiro_recentes;
select fn_materializar_fatos() ->> 'reresolvidos';
select chave, valor, ecol, ent, eorig, emot from pg_temp.fv where v = :'v' order by valor;
