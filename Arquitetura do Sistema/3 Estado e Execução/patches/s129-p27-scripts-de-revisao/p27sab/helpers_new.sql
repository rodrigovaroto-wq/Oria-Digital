create or replace function pg_temp.doc(p_caso uuid, p_ent text, p_per text, p_tipo text, p_hash text, p_campos jsonb, p_ptipo text default 'anual') returns uuid
language plpgsql as $$
declare v uuid;
begin
  v := (fn_registrar_documento(p_caso, p_ent, p_ptipo, p_per, p_tipo, 0.97, 'nome_arquivo', 'supabase_storage', '0243/' || p_hash || '.pdf', p_hash || '.pdf', true, p_hash, 'ok')->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v, p_campos);
  return v;
end $$;
create or replace function pg_temp.l(p_chave text, p_valor text, p_secao_canonica text default null, p_secao text default null, p_pcol text default null, p_ecol text default null) returns jsonb
language sql as $$
  select jsonb_strip_nulls(jsonb_build_object('chave', p_chave, 'valor_num', p_valor, 'secao_canonica', p_secao_canonica, 'secao', p_secao, 'periodo_coluna', p_pcol, 'entidade_coluna', p_ecol, 'confianca', '0.97'))
$$;
create or replace function pg_temp.linhas(p_versao uuid) returns text[] language sql as $$
  select coalesce(array_agg(x order by x), '{}') from (
    select format('%s|%s|%s|%s|E=%s|Em=%s|P=%s|Pm=%s|C=%s|M=%s', ce.chave, f.valor::text, coalesce(f.periodo_coluna, '-'), coalesce(f.entidade_coluna, '-'),
                  coalesce(e.razao_social, '-'), coalesce(f.entidade_motivo, '-'),
                  case when f.periodo_id is null then '-' when f.periodo_id = d.periodo_id then 'DOC' else p.referencia end, coalesce(f.periodo_motivo, '-'),
                  coalesce(f.conta_id, '-'), f.resolucao_metodo) as x
      from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id
      join documento_versao dv on dv.id = f.documento_versao_id join documento d on d.id = dv.documento_id
      left join entidade e on e.id = f.entidade_id left join periodo p on p.id = f.periodo_id
     where f.documento_versao_id = p_versao) t
$$;
