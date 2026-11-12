create or replace function public.r5_div() returns table(lado text, n bigint) language sql as $$
  with r as (select campo_id, documento_versao_id, conta_id, resolucao_metodo, sem_conta_motivo, entidade_id, entidade_origem, entidade_motivo, entidade_coluna, periodo_id, periodo_origem, periodo_motivo, periodo_coluna, valor, unidade, moeda from fn_fato_resolver(null)),
       f as (select campo_extraido_id, documento_versao_id, conta_id, resolucao_metodo, sem_conta_motivo, entidade_id, entidade_origem, entidade_motivo, entidade_coluna, periodo_id, periodo_origem, periodo_motivo, periodo_coluna, valor, unidade, moeda from fato_financeiro)
  select 'so_no_resolver', count(*) from (select * from r except select * from f) x
  union all select 'so_no_fato', count(*) from (select * from f except select * from r) y
$$;
