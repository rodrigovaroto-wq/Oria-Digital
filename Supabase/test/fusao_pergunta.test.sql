-- =============================================================================
-- 0213 — A FUSÃO LEVA A PERGUNTA JÁ AGIDA, E caso_pergunta CONTINUA APPEND-ONLY PARA O RESTO
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md) — Supabase/test/fusao_pergunta.test.sql: 23 asserts; o número por
-- guarda desligada está no cabeçalho de Supabase/migrations/0213_a_fusao_que_falhava_na_pergunta_ja_enviada.sql.
--
-- O ARRANJO É O DE PRODUÇÃO (regra 4): duas empresas com balanço sem caixa (a pergunta A3 dispara para cada uma),
-- o analista envia a A3 sobre a que vai ser absorvida e DESCARTA outra, e a tela funde as duas COMO authenticated.
-- Antes da 0213 a fusão morria em caso_pergunta_entidade_id_fkey (23503).
--
-- O QUE ESTE ARQUIVO AFIRMA (comportamento):
--   1. fundir como authenticated, com perguntas já agidas sobre a absorvida, funciona;
--   2. as linhas passam para a sobrevivente com TUDO o mais intacto (ação, texto congelado, autor, data);
--   3. `ja_enviada` vale para a sobrevivente depois (a pergunta enviada sobre a absorvida não é sugerida de novo)
--      e não valia antes; a sugestão não foi carregada (nenhuma linha nova);
--   4. o evento da fusão lista o que foi repontado (codigo, acao, criado_em) e o retorno traz a contagem;
--   5. append-only para o resto: o authenticated não reescreve texto, ação nem autor (42501), não apaga (42501),
--      não repõe para entidade de outro caso nem para nulo, e não repõe linha sem entidade;
--   6. o reponte direto deixa o evento caso_pergunta_reapontada.
-- =============================================================================

create or replace function teste_assert_0213(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_cond then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

delete from caso where nome in ('0213 — fusão e pergunta', '0213 — outro caso');

do $$
declare
  v_caso uuid; v_outro uuid; v_r jsonb; v_ver uuid;
  v_abs uuid; v_sob uuid; v_alheia uuid; v_txt text; v_err text; v_n int;
  v_ret jsonb; v_ev record; v_cp_enviada uuid; v_cp_descartada uuid; v_criado timestamptz; v_texto text;
begin
  v_caso  := fn_upsert_caso('0213 — fusão e pergunta');
  v_outro := fn_upsert_caso('0213 — outro caso');

  -- duas empresas, cada uma com um balanço SEM caixa: A3 dispara por empresa
  v_r := fn_registrar_documento(v_caso, 'VEGA ALPHA SA', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-vega-0213.pdf', 'BP Vega.pdf', true, 'HASH-VEGA-0213', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "TOTAL DO ATIVO", "valor_num": "900", "confianca": "0.9"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "900", "confianca": "0.9"},
    {"chave": "Estoques", "valor_num": "900", "confianca": "0.9"}]'::jsonb, 'N0');
  v_r := fn_registrar_documento(v_caso, 'ORION KAPPA LTDA', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-orion-0213.pdf', 'BP Orion.pdf', true, 'HASH-ORION-0213', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "TOTAL DO ATIVO", "valor_num": "800", "confianca": "0.9"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "800", "confianca": "0.9"},
    {"chave": "Estoques", "valor_num": "800", "confianca": "0.9"}]'::jsonb, 'N0');
  select id into v_abs from entidade where caso_id = v_caso and razao_social = 'VEGA ALPHA SA';
  select id into v_sob from entidade where caso_id = v_caso and razao_social = 'ORION KAPPA LTDA';
  perform teste_assert_0213(v_abs is not null and v_sob is not null, 'controle: as duas entidades existem', 'a/s');

  select s.pergunta into v_txt from fn_sugerir_perguntas(v_caso) s where s.codigo = 'A3' and s.entidade_id = v_abs;
  perform teste_assert_0213(v_txt is not null, 'controle: A3 é sugerida para a absorvida');
  perform teste_assert_0213(exists (select 1 from fn_sugerir_perguntas(v_caso) s where s.codigo = 'A3' and s.entidade_id = v_sob and not s.ja_enviada),
    'controle: A3 é sugerida para a sobrevivente e AINDA não está enviada');
  v_r := fn_registrar_pergunta_acao(v_caso, 'A3', 'enviada', v_txt, 'analista@0213', v_abs);
  v_cp_enviada := (v_r->>'caso_pergunta_id')::uuid;
  v_r := fn_registrar_pergunta_acao(v_caso, '7.1', 'descartada', null, 'analista@0213', v_abs);
  v_cp_descartada := (v_r->>'caso_pergunta_id')::uuid;
  perform teste_assert_0213(v_cp_enviada is not null and v_cp_descartada is not null, 'controle: as duas ações foram gravadas sobre a absorvida', v_r::text);
  perform teste_assert_0213(exists (select 1 from fn_sugerir_perguntas(v_caso) s where s.codigo = 'A3' and s.entidade_id = v_abs and s.ja_enviada)
    and exists (select 1 from fn_sugerir_perguntas(v_caso) s where s.codigo = 'A3' and s.entidade_id = v_sob and not s.ja_enviada),
    'controle: A3 está ja_enviada só para a absorvida');
  select criado_em, texto_enviado into v_criado, v_texto from caso_pergunta where id = v_cp_enviada;
  select count(*) into v_n from caso_pergunta where caso_id = v_caso;

  raise notice '--- 1. fundir como authenticated ---';
  set local role authenticated;
  v_err := null;
  begin v_ret := fn_fundir_entidade(v_caso, v_abs, v_sob, 'portal@0213');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  reset role;
  perform teste_assert_0213(v_err is null, 'a fusão com perguntas já agidas FUNCIONA como authenticated (antes: 23503)', v_err);
  perform teste_assert_0213(not exists (select 1 from entidade where id = v_abs), 'a absorvida sumiu');

  raise notice '--- 2. as linhas passam para a sobrevivente, intactas ---';
  perform teste_assert_0213((select count(*) from caso_pergunta where caso_id = v_caso and entidade_id = v_sob) = 2
    and (select count(*) from caso_pergunta where caso_id = v_caso) = v_n,
    'as 2 linhas agora são da sobrevivente e não nasceu nem sumiu nenhuma');
  perform teste_assert_0213(exists (select 1 from caso_pergunta where id = v_cp_enviada and acao = 'enviada'
        and texto_enviado = v_texto and autor = 'analista@0213' and criado_em = v_criado and pergunta_codigo = 'A3')
    and exists (select 1 from caso_pergunta where id = v_cp_descartada and acao = 'descartada' and pergunta_codigo = '7.1'),
    'ação, texto congelado, autor e data intactos');

  raise notice '--- 3. ja_enviada vale para a sobrevivente ---';
  perform teste_assert_0213(exists (select 1 from fn_sugerir_perguntas(v_caso) s where s.codigo = 'A3' and s.entidade_id = v_sob and s.ja_enviada),
    'A3 da sobrevivente passa a ja_enviada (a enviada sobre a absorvida não é sugerida de novo)');

  raise notice '--- 4. o evento da fusão lista o que foi repontado ---';
  select * into v_ev from evento_auditoria where acao = 'entidade_fundida' and entidade_ref = 'entidade:' || v_sob;
  perform teste_assert_0213(jsonb_array_length(v_ev.depois->'perguntas_repontadas') = 2
    and exists (select 1 from jsonb_array_elements(v_ev.depois->'perguntas_repontadas') e
                 where e->>'codigo' = 'A3' and e->>'acao' = 'enviada' and (e->>'criado_em') is not null
                   and (e->>'caso_pergunta_id')::uuid = v_cp_enviada)
    and exists (select 1 from jsonb_array_elements(v_ev.depois->'perguntas_repontadas') e
                 where e->>'codigo' = '7.1' and e->>'acao' = 'descartada'),
    'o evento traz as 2 perguntas com codigo, acao, criado_em e id', v_ev.depois::text);
  perform teste_assert_0213((v_ret->>'perguntas_repontadas')::int = 2, 'o retorno conta 2', v_ret::text);

  raise notice '--- 5. append-only para o resto, COMO authenticated ---';
  set local role authenticated;
  v_err := null; begin update caso_pergunta set texto_enviado = 'reescrito' where id = v_cp_enviada;
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0213(v_err = '42501', 'não reescreve o texto enviado (privilégio de coluna)', v_err);
  v_err := null; begin update caso_pergunta set acao = 'descartada' where id = v_cp_enviada;
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0213(v_err = '42501', 'não troca a ação', v_err);
  v_err := null; begin update caso_pergunta set autor = 'outro' where id = v_cp_enviada;
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0213(v_err = '42501', 'não troca o autor', v_err);
  v_err := null; begin delete from caso_pergunta where id = v_cp_enviada;
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0213(v_err = '42501', 'não apaga (permission denied, não 0 linhas calado)', v_err);
  reset role;
  v_err := null; begin update caso_pergunta set texto_enviado = 'reescrito pelo dono' where id = v_cp_enviada;
  exception when others then v_err := sqlerrm; end;
  perform teste_assert_0213(v_err like '%append-only%', 'nem o dono da tabela reescreve o texto (gatilho, além do privilégio)', v_err);
  v_alheia := fn_upsert_entidade(v_outro, 'ENTIDADE DE OUTRO CASO (0213)');
  set local role authenticated;
  v_err := null; begin update caso_pergunta set entidade_id = v_alheia where id = v_cp_enviada;
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0213(v_err = '42501', 'não repõe para entidade de OUTRO caso (policy with check)', v_err);
  v_err := null; begin update caso_pergunta set entidade_id = null where id = v_cp_enviada;
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0213(v_err is not null, 'não repõe para nenhuma entidade', v_err);
  reset role;
  perform teste_assert_0213(exists (select 1 from caso_pergunta where id = v_cp_enviada and entidade_id = v_sob
        and texto_enviado = v_texto and acao = 'enviada' and autor = 'analista@0213'),
    'e a linha continua exatamente como a fusão a deixou');
  insert into caso_pergunta (caso_id, pergunta_codigo, entidade_id, acao, autor)
    values (v_caso, '7.1', null, 'descartada', 'analista@0213') returning id into v_cp_descartada;
  set local role authenticated;
  v_err := null; begin update caso_pergunta set entidade_id = v_sob where id = v_cp_descartada;
  exception when others then v_err := sqlerrm; end;
  reset role;
  perform teste_assert_0213(v_err like '%de ou para%', 'pergunta sem entidade (do caso inteiro) não é repontada para uma', v_err);

  raise notice '--- 6. o reponte direto deixa evento ---';
  perform teste_assert_0213(exists (select 1 from evento_auditoria where acao = 'caso_pergunta_reapontada'
        and (depois->>'caso_pergunta_id')::uuid = v_cp_enviada and (depois->>'para')::uuid = v_sob),
    'a fusão repontou a pergunta e o gatilho gravou caso_pergunta_reapontada');

  raise notice '--- 7. a sonda enxerga o que a 0213 instalou ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0213' and not presente;
  perform teste_assert_0213(v_n = 0, 'nenhum requisito da 0213 está ausente na sonda', v_n::text);

  raise notice 'FUSÃO E PERGUNTA OK — a ação já tomada acompanha a sobrevivente, ja_enviada vale, e caso_pergunta segue append-only';
end $$;
