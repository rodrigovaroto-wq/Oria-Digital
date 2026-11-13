select 'requisitos 0243: ' || count(*) || ' md5 ' || md5(string_agg(r::text, '|' order by chave)) from instalacao_requisito r where migration = '0243';
select 'requisitos total: ' || count(*) || ' md5 ' || md5(string_agg(r::text, '|' order by chave)) from instalacao_requisito r;
select 'cobertura: ' || ate_migration from instalacao_cobertura;
select 'sonda: ' || count(*) filter (where not presente) || ' ausentes de ' || count(*) || ' ' || coalesce(string_agg(chave, ',') filter (where not presente), '') from fn_instalacao_conferir();
begin;
select fn_upsert_caso('ordem')::uuid as caso \gset
select fn_upsert_entidade(:'caso'::uuid, 'ORDEM Z LTDA')\gset
select fn_upsert_periodo(:'caso'::uuid, 'anual', '2025')\gset
select (fn_registrar_documento(:'caso'::uuid, 'ORDEM Z LTDA', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage', 'o/a.pdf', 'oa.pdf', true, 'ohash', 'ok')->>'documento_versao_id')::uuid as v \gset
select fn_registrar_campos_extraidos(:'v'::uuid, '[{"chave":"Caixa LN","valor_num":"5","secao_canonica":"ativo_circulante","periodo_coluna":"2025","ln":7,"confianca":"0.97"},{"chave":"Clientes LN","valor_num":"6","secao":"ATIVO CIRCULANTE","periodo_coluna":"2025","ln":9,"confianca":"0.97"}]'::jsonb);
select 'ln gravado: ' || string_agg(chave || '=' || coalesce(ln::text, 'NULO'), ', ' order by chave) from campo_extraido where documento_versao_id = :'v'::uuid;
select 'fatos: ' || count(*) || ', pendencia aberta: ' || (select count(*) from pendencia where motivo = 'fato:conta_incerta:' || :'v') from fato_financeiro where documento_versao_id = :'v'::uuid;
rollback;
