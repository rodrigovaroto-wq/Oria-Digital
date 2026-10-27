-- =============================================================================
-- 0211 — A FUSÃO DE ENTIDADES LEVA O PERÍMETRO DA ABSORVIDA (e o que não leva fica no evento)
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md) — Supabase/test/fusao_perimetro.test.sql: 20 asserts; o número por
-- guarda desligada está no cabeçalho de Supabase/migrations/0211_a_fusao_que_apagava_o_perimetro_da_absorvida.sql.
--
-- O ARRANJO É O DE PRODUÇÃO (regra 4): a tela de perímetro manda fundir a fantasma na empresa real, e quem
-- chama é o analista (authenticated). O teste chama `fn_fundir_entidade` direto porque a guarda de nome/CNPJ
-- decide SE a fusão acontece, e aqui a pergunta é o que ela faz QUANDO acontece.
--
-- O QUE ESTE ARQUIVO AFIRMA (comportamento):
--   1. intervalo da absorvida sem sobreposição passa para a sobrevivente (inclusive o que apenas encosta);
--   2. intervalo vigente da absorvida contra vigente da sobrevivente (mesmo escopo): não duplica, não viola
--      perimetro_atual_unico, o da sobrevivente fica como estava e o da absorvida vai para o evento;
--   3. sobreposição parcial com intervalo fechado da sobrevivente também fica no evento; escopo DIFERENTE passa;
--   4. quem era controlada pela absorvida passa a ser controlada pela sobrevivente (a fusão antes falhava);
--   5. sobrevivente controlada pela absorvida: recusa em português e nada muda;
--   6. o papel, a controladora e o percentual da absorvida ficam no evento;
--   7. tudo isso como authenticated, o papel que a tela usa.
-- =============================================================================

create or replace function teste_assert_0211(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_cond then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

delete from caso where nome = '0211 — fusão e perímetro';

do $$
declare
  v_caso uuid;
  d0 constant date := current_date - 200;
  v_de uuid; v_para uuid; v_x uuid; v_h uuid;
  v_n int; v_err text; v_ret jsonb; v_ev record;
begin
  v_caso := fn_upsert_caso('0211 — fusão e perímetro');

  raise notice '--- 1. sem sobreposição: o intervalo da absorvida passa para a sobrevivente ---';
  v_de   := fn_upsert_entidade(v_caso, 'ABSORVIDA UM SA (0211)');
  v_para := fn_upsert_entidade(v_caso, 'SOBREVIVENTE UM SA (0211)');
  insert into perimetro (caso_id, entidade_id, escopo, desde, ate) values (v_caso, v_de, 'combinado', d0, d0 + 9);
  insert into perimetro (caso_id, entidade_id, escopo, desde, ate) values (v_caso, v_para, 'combinado', d0 + 10, null);
  v_ret := fn_fundir_entidade(v_caso, v_de, v_para, 'teste@0211');
  select count(*) into v_n from perimetro where entidade_id = v_para;
  perform teste_assert_0211(v_n = 2, 'a sobrevivente fica com os 2 intervalos (o que ENCOSTA não é sobreposição)', v_n::text);
  perform teste_assert_0211(exists (select 1 from perimetro where entidade_id = v_para and desde = d0 and ate = d0 + 9),
    'e o intervalo movido guardou as datas da absorvida');
  perform teste_assert_0211((v_ret->>'perimetro_movido')::int = 1 and (v_ret->>'perimetro_descartado')::int = 0,
    'o retorno conta 1 movido e 0 descartado', v_ret::text);
  select * into v_ev from evento_auditoria where acao = 'entidade_fundida' and entidade_ref = 'entidade:' || v_para;
  perform teste_assert_0211((v_ev.depois->>'perimetro_movido')::int = 1 and v_ev.depois->'perimetro_descartado' = '[]'::jsonb,
    'e o evento registra perimetro_movido = 1 e nada descartado', v_ev.depois::text);

  raise notice '--- 2. vigente contra vigente do mesmo escopo: não duplica e o descartado fica no evento ---';
  v_de   := fn_upsert_entidade(v_caso, 'ABSORVIDA DOIS SA (0211)');
  v_para := fn_upsert_entidade(v_caso, 'SOBREVIVENTE DOIS SA (0211)');
  perform fn_perimetro_definir_escopo(v_caso, v_de, 'combinado', d0, 'teste@0211');
  perform fn_perimetro_definir_escopo(v_caso, v_para, 'combinado', d0 + 50, 'teste@0211');
  v_err := null;
  begin v_ret := fn_fundir_entidade(v_caso, v_de, v_para, 'teste@0211');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  perform teste_assert_0211(v_err is null, 'a fusão NÃO viola perimetro_atual_unico', v_err);
  select count(*) into v_n from perimetro where entidade_id = v_para and escopo = 'combinado';
  perform teste_assert_0211(v_n = 1 and exists (select 1 from perimetro where entidade_id = v_para and desde = d0 + 50 and ate is null),
    'a sobrevivente fica com UM intervalo, o dela, intacto', v_n::text);
  select * into v_ev from evento_auditoria where acao = 'entidade_fundida' and entidade_ref = 'entidade:' || v_para;
  perform teste_assert_0211(jsonb_array_length(v_ev.depois->'perimetro_descartado') = 1
    and v_ev.depois->'perimetro_descartado'->0->>'escopo' = 'combinado'
    and (v_ev.depois->'perimetro_descartado'->0->>'desde')::date = d0
    and (v_ev.depois->'perimetro_descartado'->0->>'sobrevivente_desde')::date = d0 + 50
    and v_ev.depois->'perimetro_descartado'->0->>'motivo' like '%sobrepõe%',
    'o intervalo descartado vai ao evento com escopo, desde, motivo e o intervalo que o cobriu', v_ev.depois::text);
  perform teste_assert_0211((v_ev.depois->>'perimetro_movido')::int = 0, 'e nenhum foi movido', v_ev.depois::text);

  raise notice '--- 3. sobreposição parcial com intervalo fechado; escopo diferente passa ---';
  v_de   := fn_upsert_entidade(v_caso, 'ABSORVIDA TRES SA (0211)');
  v_para := fn_upsert_entidade(v_caso, 'SOBREVIVENTE TRES SA (0211)');
  insert into perimetro (caso_id, entidade_id, escopo, desde, ate) values (v_caso, v_de, 'combinado', d0, d0 + 60);
  insert into perimetro (caso_id, entidade_id, escopo, desde, ate) values (v_caso, v_para, 'combinado', d0 + 50, d0 + 80);
  insert into perimetro (caso_id, entidade_id, escopo, desde, ate) values (v_caso, v_de, 'outro escopo', d0, null);
  v_ret := fn_fundir_entidade(v_caso, v_de, v_para, 'teste@0211');
  perform teste_assert_0211((v_ret->>'perimetro_descartado')::int = 1 and (v_ret->>'perimetro_movido')::int = 1,
    'sobreposição parcial descarta (1) e o escopo diferente é movido (1)', v_ret::text);
  perform teste_assert_0211(exists (select 1 from perimetro where entidade_id = v_para and escopo = 'outro escopo' and ate is null)
    and (select count(*) from perimetro where entidade_id = v_para and escopo = 'combinado') = 1,
    'a sobrevivente tem o outro escopo e continua com um só intervalo de combinado');

  raise notice '--- 4/5/6. controladas, sobrevivente controlada, papel e controladora no evento ---';
  v_de   := fn_upsert_entidade(v_caso, 'ABSORVIDA QUATRO SA (0211)');
  v_para := fn_upsert_entidade(v_caso, 'SOBREVIVENTE QUATRO SA (0211)');
  v_x    := fn_upsert_entidade(v_caso, 'FILHA QUATRO LTDA. (0211)');
  v_h    := fn_upsert_entidade(v_caso, 'MATRIZ QUATRO SA (0211)');
  perform fn_entidade_definir_participacao(v_x, v_de, 50, 'teste@0211');
  perform fn_entidade_definir_participacao(v_de, v_h, 70, 'teste@0211');
  perform fn_entidade_definir_papel_no_grupo(v_de, 'veiculo', 'teste@0211');
  v_err := null;
  begin v_ret := fn_fundir_entidade(v_caso, v_de, v_para, 'teste@0211');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  perform teste_assert_0211(v_err is null, 'fundir uma entidade que CONTROLA outra não falha mais na FK', v_err);
  perform teste_assert_0211((select controladora_id from entidade where id = v_x) = v_para,
    'a controlada passou a ser controlada pela sobrevivente');
  perform teste_assert_0211((v_ret->>'controladas_repontadas')::int = 1, 'o retorno conta 1 controlada repontada', v_ret::text);
  select * into v_ev from evento_auditoria where acao = 'entidade_fundida' and entidade_ref = 'entidade:' || v_para
    order by criado_em desc limit 1;
  perform teste_assert_0211(v_ev.depois->'controladas_repontadas'->0->>'razao_social' = 'FILHA QUATRO LTDA. (0211)',
    'e o evento nomeia quem foi repontada', v_ev.depois::text);
  perform teste_assert_0211(v_ev.antes->>'papel_no_grupo' = 'veiculo'
    and (v_ev.antes->>'controladora_id')::uuid = v_h and (v_ev.antes->>'percentual_participacao')::numeric = 70,
    'o papel, a controladora e o percentual da absorvida ficam no evento', v_ev.antes::text);

  v_de   := fn_upsert_entidade(v_caso, 'ABSORVIDA CINCO SA (0211)');
  v_para := fn_upsert_entidade(v_caso, 'SOBREVIVENTE CINCO SA (0211)');
  perform fn_entidade_definir_participacao(v_para, v_de, 80, 'teste@0211');
  v_err := null;
  begin perform fn_fundir_entidade(v_caso, v_de, v_para, 'teste@0211');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  perform teste_assert_0211(v_err like 'P0001%' and v_err like '%controlada por%', 'sobrevivente controlada pela absorvida: recusa em português', v_err);
  perform teste_assert_0211(exists (select 1 from entidade where id = v_de) and (select controladora_id from entidade where id = v_para) = v_de,
    'e nada mudou (a absorvida continua existindo e a participação também)');

  raise notice '--- 7. COMO authenticated ---';
  v_de   := fn_upsert_entidade(v_caso, 'ABSORVIDA SEIS SA (0211)');
  v_para := fn_upsert_entidade(v_caso, 'SOBREVIVENTE SEIS SA (0211)');
  insert into perimetro (caso_id, entidade_id, escopo, desde, ate) values (v_caso, v_de, 'combinado', d0, d0 + 9);
  insert into perimetro (caso_id, entidade_id, escopo, desde, ate) values (v_caso, v_de, 'combinado', d0 + 100, null);
  insert into perimetro (caso_id, entidade_id, escopo, desde, ate) values (v_caso, v_para, 'combinado', d0 + 90, null);
  v_x := fn_upsert_entidade(v_caso, 'FILHA SEIS LTDA. (0211)');
  perform fn_entidade_definir_participacao(v_x, v_de, 50, 'teste@0211');
  perform teste_como_admin_0216();
  set local role authenticated;
  v_err := null;
  begin v_ret := fn_fundir_entidade(v_caso, v_de, v_para, 'portal@0211');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  reset role;
  perform teste_fim_admin_0216();
  perform teste_assert_0211(v_err is null, 'fundir como authenticated, com perímetro e controlada, funciona', v_err);
  perform teste_assert_0211((v_ret->>'perimetro_movido')::int = 1 and (v_ret->>'perimetro_descartado')::int = 1
    and (select count(*) from perimetro where entidade_id = v_para) = 2,
    'como authenticated: 1 intervalo movido, 1 descartado, sobrevivente com 2', v_ret::text);
  perform teste_assert_0211((select controladora_id from entidade where id = v_x) = v_para,
    'como authenticated: a controlada foi repontada (UPDATE em entidade)');

  raise notice 'FUSÃO E PERÍMETRO OK — o intervalo da absorvida passa, o que sobrepõe fica no evento, as controladas migram e o papel da absorvida fica registrado';
end $$;
