\set ON_ERROR_STOP on
select (fn_registrar_documento('11111111-1111-1111-1111-111111111111', 'VERTENTES METALÚRGICA LTDA.', 'anual', '2025', 'DRE', 0.97, 'nome_arquivo', 'supabase_storage', 'r3/a.pdf', 'r3a.pdf', true, 'r3hash', 'ok')->>'documento_versao_id')::uuid as v \gset
select fn_registrar_campos_extraidos(:'v'::uuid, jsonb_build_array(
  jsonb_build_object('chave','Receita de vendas','valor_num','100','secao_canonica','receita_bruta','confianca','0.97'),
  jsonb_build_object('chave','Custo','valor_num','-40','secao_canonica','custos','confianca','0.97')));
update documento set entidade_id = null where id = (select documento_id from documento_versao where id = :'v');
select f.entidade_id, f.entidade_motivo from fato_financeiro f where f.documento_versao_id = :'v';
