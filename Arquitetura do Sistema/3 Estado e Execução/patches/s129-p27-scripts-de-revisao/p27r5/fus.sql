\set ON_ERROR_STOP on
select (fn_registrar_documento('11111111-1111-1111-1111-111111111111', 'GRUPO VERTENTES', 'anual', '2025', 'COMBINADO', 0.97, 'nome_arquivo', 'supabase_storage', 'fu/a.pdf', 'fua.pdf', true, 'fuhash', 'ok')->>'documento_versao_id')::uuid as v \gset
select fn_registrar_campos_extraidos(:'v'::uuid, jsonb_build_array(
  jsonb_build_object('chave','Receita de vendas','valor_num','100','secao_canonica','receita_bruta','entidade_coluna','Vertentes Metalúrgica','confianca','0.97'),
  jsonb_build_object('chave','Receita de vendas','valor_num','70','secao_canonica','receita_bruta','entidade_coluna','Vertentes Imóveis','confianca','0.97')));
select f.entidade_coluna, f.valor, (select razao_social from entidade where id=f.entidade_id) ent, f.entidade_motivo from fato_financeiro f where f.documento_versao_id=:'v' order by 1;
select fn_fundir_entidade('11111111-1111-1111-1111-111111111111', (select id from entidade where razao_social='VERTENTES IMÓVEIS SPE LTDA.'), (select id from entidade where razao_social='VERTENTES METALÚRGICA LTDA.'), 'usuario:teste')->>'fatos_repontados' as fatos_repontados_no_retorno;
select f.entidade_coluna, f.valor, (select razao_social from entidade where id=f.entidade_id) ent, f.entidade_motivo from fato_financeiro f where f.documento_versao_id=:'v' order by 1;
select depois->>'fatos_repontados' from evento_auditoria where acao='entidade_fundida' order by criado_em desc limit 1;
select count(*) as fatos_sem_dono_mandato from fato_financeiro f join documento_versao dv on dv.id=f.documento_versao_id join documento d on d.id=dv.documento_id where d.caso_id='11111111-1111-1111-1111-111111111111' and f.entidade_motivo='coluna_sem_entidade_no_mandato';
select * from r5_div();
