\set ON_ERROR_STOP on
begin;
select (fn_registrar_documento('11111111-1111-1111-1111-111111111111', 'VERTENTES METALÚRGICA LTDA.', 'anual', '2025', 'DRE', 0.97, 'nome_arquivo', 'supabase_storage', 'r2/a.pdf', 'r2a.pdf', true, 'r2hash', 'ok')->>'documento_versao_id')::uuid as v \gset
select fn_registrar_campos_extraidos(:'v'::uuid, jsonb_build_array(
  jsonb_build_object('chave','Receita de vendas','valor_num','100','secao_canonica','receita_bruta','entidade_coluna','Gama Forjados','confianca','0.97'),
  jsonb_build_object('chave','Receita de vendas','valor_num','200','secao_canonica','receita_bruta','entidade_coluna','Vertentes Metalúrgica','confianca','0.97')));
select now() as a_materializou;
select pg_sleep(6);
commit;
