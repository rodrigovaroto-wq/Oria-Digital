create or replace function pg_temp.doc(p_caso uuid, p_ent text, p_per text, p_tipo text, p_hash text, p_campos jsonb, p_ptipo text default 'anual') returns uuid
language plpgsql as $$
declare v uuid;
begin
  v := (fn_registrar_documento(p_caso, p_ent, p_ptipo, p_per, p_tipo, 0.97, 'nome_arquivo', 'supabase_storage', 'rev3/' || p_hash || '.pdf', p_hash || '.pdf', true, p_hash, 'ok')->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v, p_campos);
  return v;
end $$;
create or replace function pg_temp.l(p_chave text, p_valor text, p_secao_canonica text default null, p_secao text default null, p_pcol text default null, p_ecol text default null) returns jsonb
language sql as $$
  select jsonb_strip_nulls(jsonb_build_object('chave', p_chave, 'valor_num', p_valor, 'secao_canonica', p_secao_canonica, 'secao', p_secao, 'periodo_coluna', p_pcol, 'entidade_coluna', p_ecol, 'confianca', '0.97'))
$$;
create or replace view pg_temp.fv as
 select f.documento_versao_id v, ce.chave, f.valor, f.entidade_coluna ecol, e.razao_social ent, f.entidade_origem eorig, f.entidade_motivo emot, f.periodo_coluna pcol, p.referencia per, f.periodo_origem porig, f.periodo_motivo pmot, f.conta_id
   from fato_financeiro f join campo_extraido ce on ce.id=f.campo_extraido_id left join entidade e on e.id=f.entidade_id left join periodo p on p.id=f.periodo_id;
