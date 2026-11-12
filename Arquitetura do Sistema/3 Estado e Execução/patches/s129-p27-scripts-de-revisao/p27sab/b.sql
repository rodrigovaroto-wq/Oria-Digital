\set ON_ERROR_STOP on
create or replace function pg_temp.l(p_chave text, p_valor text, p_secao_canonica text default null) returns jsonb language sql as $$
  select jsonb_build_object('chave', p_chave, 'valor_num', p_valor, 'secao_canonica', p_secao_canonica, 'confianca', '0.97') $$;
-- B1: uma extração DRE de 2 linhas comitada NA JANELA
select (fn_registrar_documento('11111111-1111-1111-1111-111111111111', 'VERTENTES METALÚRGICA LTDA.', 'anual', '2025', 'DRE', 0.97, 'nome_arquivo', 'supabase_storage', 'j/janela.pdf', 'janela.pdf', true, 'janelaj1', 'ok')->>'documento_versao_id')::uuid as v \gset
select fn_registrar_campos_extraidos(:'v'::uuid, jsonb_build_array(pg_temp.l('Receita de vendas','1000','receita_bruta'), pg_temp.l('Custo dos produtos','-400','custos'))) as n;
-- B2: um update de documento.entidade_id NA JANELA (o documento com mais linhas elegíveis)
select d.id as doc, (select e.id from entidade e where e.caso_id = d.caso_id and e.id <> d.entidade_id order by e.id limit 1) as nova from documento d join documento_versao dv on dv.documento_id = d.id join campo_extraido ce on ce.documento_versao_id = dv.id
 where d.caso_id = '11111111-1111-1111-1111-111111111111' and d.entidade_id is not null and d.tipo_taxonomia in ('BALANCO','BALANCETE','DRE','COMBINADO') and d.id <> (select documento_id from documento_versao where id = :'v')
 group by d.id, d.caso_id, d.entidade_id order by count(*) desc limit 1 \gset
update documento set entidade_id = :'nova' where id = :'doc';
select :'v' as versao_dre, :'doc' as doc_atualizado;
