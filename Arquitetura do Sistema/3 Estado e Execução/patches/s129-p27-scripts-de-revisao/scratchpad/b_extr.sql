select pg_temp.doc('11111111-1111-1111-1111-111111111111', 'VERTENTES METALÚRGICA LTDA.', '2025', 'DRE', 'rev4janela',
  jsonb_build_array(pg_temp.l('Receita de vendas','1000','receita_bruta'), pg_temp.l('Custo dos produtos','-400','custos'))) as v \gset
select :'v' as versao, clock_timestamp();
