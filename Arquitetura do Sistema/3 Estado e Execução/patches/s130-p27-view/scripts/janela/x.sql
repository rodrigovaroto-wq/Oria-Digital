\timing on
select fn_upsert_caso('janela')::uuid as caso \gset
select fn_upsert_entidade(:'caso'::uuid, 'JANELA LTDA')\gset
select fn_upsert_periodo(:'caso'::uuid, 'anual', '2025')\gset
select (fn_registrar_documento(:'caso'::uuid, 'JANELA LTDA', 'anual', '2025', 'DRE', 0.97, 'nome_arquivo', 'supabase_storage', 'j/a.pdf', 'ja.pdf', true, 'jhash', 'ok')->>'documento_versao_id')::uuid as v \gset
select now() as x_inicio;
select fn_registrar_campos_extraidos(:'v'::uuid, '[{"chave":"Receita de vendas","valor_num":"100","secao":"RECEITA","periodo_coluna":"2025","confianca":"0.97"},{"chave":"Custo","valor_num":"-40","secao_canonica":"custos","periodo_coluna":"2025","confianca":"0.97"}]'::jsonb);
select now() as x_fim;
