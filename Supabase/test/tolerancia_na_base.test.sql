-- Testes da 0193 (Supabase/migrations/0193_a_tolerancia_que_crescia_com_a_escala.sql).
-- Rodar via Supabase/test/run.sh.
--
-- O QUE ESTE ARQUIVO TRAVA, em COMPORTAMENTO (regra 3 — não o mecanismo):
--
--   1. fn_reconciliar_caixa_bp_fluxo: um caso com Caixa do Balanço e Saldo
--      final do Fluxo de Caixa em 'milhar', divergindo o bastante para passar
--      do piso NA BASE (R$ 5.000, pois greatest(100, 0,5% de R$ 1.000.000)) e
--      não passar do piso ANTIGO × escala (R$ 100.000), sai 'divergente' — e
--      um par dentro da tolerância verdadeira (arredondamento de R$ 1.000)
--      continua 'ok'.
--   2. fn_reconciliar_receita_dre_vs_faturamento: o mesmo arranjo, com os
--      defaults da checagem (abs 50.000, pct 5%) — uma DRE em 'milhar' com
--      Receita Bruta de R$ 74 mi cuja soma de faturamento difere 30% sai
--      'zona_cinzenta' (não 'ok', que é o que o piso × escala de R$ 50
--      MILHÕES daria); e uma diferença de ~2% continua 'ok'.
--
--   3. fn_reconciliar_caixa_bp_fluxo: REVISÃO DE FIDELIDADE (28/09/2026) — a
--      tolerância na base, sozinha, ainda sai 'divergente' por puro
--      arredondamento do documento quando o caixa é pequeno: Caixa do
--      Balanço R$ 12.000 (12 'milhar') × Saldo final R$ 11.000 (11 'milhar')
--      — diferença de R$ 1.000, exatamente 1 unidade da escala, sem que nada
--      esteja errado — continua 'ok' com o piso de arredondamento (greatest
--      chega a R$ 1.000); sem o piso (só `greatest(100, 0,5% de 12.000 =
--      60)` = R$ 100), sairia 'divergente'.
--
-- OS CASOS SÃO MONTADOS AQUI, NÃO SÃO FIXTURE DE PRODUÇÃO (regra 4): a
-- correção é LATENTE em produção hoje (0 de 33 caixa_bp_fluxo e 0 de 30
-- receita_dre_vs_faturamento 'ok' mudam de resultado, medido 25/09/2026 —
-- ver o cabeçalho da 0193; e 0 casos de arredondamento com caixa abaixo de
-- R$ 200 mil, medido 28/09/2026). O que se afirma aqui é só o comportamento
-- da tolerância, com os números redondos que bastam para exercitá-lo.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): com o `× fn_fator_escala(...)` de volta em
-- cada função SEPARADAMENTE (no lugar da tolerância na base), o assert
-- correspondente reprova — contado sem parar no primeiro `raise`. E com o
-- piso de arredondamento removido de `fn_reconciliar_caixa_bp_fluxo` (volta
-- a `greatest(p_tolerancia_abs, abs(v_a) * p_tolerancia_pct)`), o assert do
-- bloco 3 reprova.

begin;

create temp sequence _falhas_0193;

create or replace function pg_temp.teste_assert_0193(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  else
    perform nextval('pg_temp._falhas_0193');
    raise notice 'FALHOU: % — %', p_nome, coalesce(p_detalhe, '(sem detalhe)');
  end if;
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid;
  v_r    jsonb;
  v_doc_bp uuid;
  v_ent  uuid;
  v_per  uuid;
  v_ok   boolean;
  v_res  text;
  v_div  text;
begin
  raise notice '--- 1. caixa_bp_fluxo: tolerância absoluta NA BASE, não × fn_fator_escala ---';
  -- Caixa do Balanço R$ 1.000.000 (1000 milhar), Saldo final da DFC
  -- R$ 940.000 (940 milhar) — diferença de R$ 60.000. Piso ANTIGO
  -- (100 × 1000 = R$ 100.000) diria "confere"; piso NA BASE
  -- (greatest(100, 0,5% de 1.000.000) = R$ 5.000) não.
  v_caso := (fn_upsert_caso('0193: tolerância do caixa em milhar'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'CAIXA MILHAR LTDA.', 'anual', '2025', 'BALANCO', 0.95,
    'nome_arquivo', 'supabase_storage', '0193/bp-tol.pdf', 'BP TOL.pdf', true, 'HASH-0193-1', 'ok');
  v_doc_bp := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Caixa e equivalentes de caixa','valor_num','1000',
      'periodo_coluna','2025','unidade','milhar','confianca','0.97')
  ), 'N2');
  v_r := fn_registrar_documento(v_caso, 'CAIXA MILHAR LTDA.', 'anual', '2025', 'FLUXO_CAIXA', 0.95,
    'nome_arquivo', 'supabase_storage', '0193/fx-tol.pdf', 'FX TOL.pdf', true, 'HASH-0193-2', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Saldo final de caixa','valor_num','940',
      'periodo_coluna','2025','unidade','milhar','confianca','0.97')
  ), 'N2');
  select entidade_id, periodo_id into v_ent, v_per from documento where id = v_doc_bp;

  v_r := fn_reconciliar_caixa_bp_fluxo(v_caso, v_ent, v_per);
  select precondicoes_ok, resultado, divergencia_abs::text into v_ok, v_res, v_div
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0193(v_ok and v_res = 'divergente',
    'Caixa 1.000 × Saldo 940 em milhar (R$ 60.000 de diferença) sai divergente, não "confere"',
    format('precondicoes_ok=%s resultado=%s divergencia_abs=%s', v_ok, v_res, v_div));

  -- O LADO QUE NÃO PODE QUEBRAR: arredondamento de UMA unidade da escala
  -- (R$ 1.000) continua dentro da tolerância verdadeira e sai ok. A chave
  -- pertence à versão do FLUXO_CAIXA (não a v_doc_bp, que é o Balanço) —
  -- localiza pela entidade/período.
  update campo_extraido ce set valor_num = 999
    from documento_versao dv join documento d on d.id = dv.documento_id
   where d.entidade_id = v_ent and d.periodo_id = v_per and d.tipo_taxonomia = 'FLUXO_CAIXA'
     and ce.documento_versao_id = dv.id and ce.chave = 'Saldo final de caixa';
  v_r := fn_reconciliar_caixa_bp_fluxo(v_caso, v_ent, v_per);
  select precondicoes_ok, resultado into v_ok, v_res
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0193(v_ok and v_res = 'ok',
    'arredondamento de R$ 1.000 (1.000 × 999 em milhar) continua ok',
    format('precondicoes_ok=%s resultado=%s', v_ok, v_res));
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid;
  v_r    jsonb;
  v_doc_dre uuid;
  v_ent  uuid;
  v_per  uuid;
  v_ok   boolean;
  v_res  text;
  v_div  text;
begin
  raise notice '--- 2. receita_dre_vs_faturamento: tolerância absoluta NA BASE, não × fn_fator_escala ---';
  -- Receita Bruta da DRE R$ 74.000.000 (74.000 milhar); Faturamento mensal
  -- somando R$ 51.800.000 (2 meses de 25.900 milhar) — diferença de
  -- R$ 22.200.000 (30%). Piso ANTIGO (50.000 × 1.000 = R$ 50 MILHÕES) diria
  -- "confere"; piso NA BASE (greatest(50.000, 5% de 74.000.000) =
  -- R$ 3.700.000) não.
  v_caso := (fn_upsert_caso('0193: tolerância da receita em milhar'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'RECEITA MILHAR LTDA.', 'anual', '2025', 'DRE', 0.95,
    'nome_arquivo', 'supabase_storage', '0193/dre-tol.pdf', 'DRE TOL.pdf', true, 'HASH-0193-3', 'ok');
  v_doc_dre := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','RECEITA OPERACIONAL BRUTA','valor_num','74000',
      'periodo_coluna','2025','unidade','milhar','confianca','0.97')
  ), 'N2');
  v_r := fn_registrar_documento(v_caso, 'RECEITA MILHAR LTDA.', 'anual', '2025', 'FATURAMENTO_24M', 0.95,
    'nome_arquivo', 'supabase_storage', '0193/fat-tol.pdf', 'FAT TOL.pdf', true, 'HASH-0193-4', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Faturamento Janeiro 2025','valor_num','25900',
      'unidade','milhar','moeda','BRL','confianca','0.97'),
    jsonb_build_object('ordem',1,'chave','Faturamento Fevereiro 2025','valor_num','25900',
      'unidade','milhar','moeda','BRL','confianca','0.97')
  ), 'N2');
  select entidade_id, periodo_id into v_ent, v_per from documento where id = v_doc_dre;

  v_r := fn_reconciliar_receita_dre_vs_faturamento(v_caso, v_ent, v_per);
  select precondicoes_ok, resultado, divergencia_abs::text into v_ok, v_res, v_div
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0193(v_ok and v_res = 'zona_cinzenta',
    'Receita Bruta 74.000 × faturamento 51.800 em milhar (30% de diferença) sai zona_cinzenta, não "confere"',
    format('precondicoes_ok=%s resultado=%s divergencia_abs=%s', v_ok, v_res, v_div));

  -- O LADO QUE NÃO PODE QUEBRAR: diferença de ~2% (dentro do piso na base,
  -- R$ 3.700.000) continua ok.
  update campo_extraido ce set valor_num = 36250
    from documento_versao dv join documento d on d.id = dv.documento_id
   where d.entidade_id = v_ent and d.periodo_id = v_per and d.tipo_taxonomia = 'FATURAMENTO_24M'
     and ce.documento_versao_id = dv.id and ce.chave = 'Faturamento Janeiro 2025';
  update campo_extraido ce set valor_num = 36250
    from documento_versao dv join documento d on d.id = dv.documento_id
   where d.entidade_id = v_ent and d.periodo_id = v_per and d.tipo_taxonomia = 'FATURAMENTO_24M'
     and ce.documento_versao_id = dv.id and ce.chave = 'Faturamento Fevereiro 2025';
  v_r := fn_reconciliar_receita_dre_vs_faturamento(v_caso, v_ent, v_per);
  select precondicoes_ok, resultado into v_ok, v_res
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0193(v_ok and v_res = 'ok',
    'diferença de ~2% (74.000 × 72.500 em milhar) continua dentro do piso na base e sai ok',
    format('precondicoes_ok=%s resultado=%s', v_ok, v_res));
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid;
  v_r    jsonb;
  v_doc_bp uuid;
  v_ent  uuid;
  v_per  uuid;
  v_ok   boolean;
  v_res  text;
  v_div  text;
begin
  raise notice '--- 3. caixa_bp_fluxo: piso de arredondamento (1 unidade da escala), caixa pequeno ---';
  -- Caixa do Balanço R$ 12.000 (12 'milhar'), Saldo final da DFC R$ 11.000
  -- (11 'milhar') — diferença de R$ 1.000, exatamente o arredondamento de 1
  -- unidade da escala do documento, sem nada errado. SEM o piso de
  -- arredondamento, greatest(100, 0,5% de 12.000 = 60) = R$ 100 — a
  -- diferença de R$ 1.000 sairia 'divergente'. COM o piso (greatest(100,
  -- 1.000, 60) = R$ 1.000), a diferença (R$ 1.000) não passa do piso e sai
  -- 'ok'.
  v_caso := (fn_upsert_caso('0193: piso de arredondamento com caixa pequeno em milhar'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'CAIXA PEQUENO MILHAR LTDA.', 'anual', '2025', 'BALANCO',
    0.95, 'nome_arquivo', 'supabase_storage', '0193/bp-tol-pequeno.pdf', 'BP TOL PEQUENO.pdf',
    true, 'HASH-0193-5', 'ok');
  v_doc_bp := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Caixa e equivalentes de caixa','valor_num','12',
      'periodo_coluna','2025','unidade','milhar','confianca','0.97')
  ), 'N2');
  v_r := fn_registrar_documento(v_caso, 'CAIXA PEQUENO MILHAR LTDA.', 'anual', '2025',
    'FLUXO_CAIXA', 0.95, 'nome_arquivo', 'supabase_storage', '0193/fx-tol-pequeno.pdf',
    'FX TOL PEQUENO.pdf', true, 'HASH-0193-6', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Saldo final de caixa','valor_num','11',
      'periodo_coluna','2025','unidade','milhar','confianca','0.97')
  ), 'N2');
  select entidade_id, periodo_id into v_ent, v_per from documento where id = v_doc_bp;

  v_r := fn_reconciliar_caixa_bp_fluxo(v_caso, v_ent, v_per);
  select precondicoes_ok, resultado, divergencia_abs::text into v_ok, v_res, v_div
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0193(v_ok and v_res = 'ok',
    'Caixa 12 × Saldo 11 em milhar (R$ 1.000 de arredondamento, caixa pequeno) continua ok, não "divergente"',
    format('precondicoes_ok=%s resultado=%s divergencia_abs=%s', v_ok, v_res, v_div));
end $$;

-- =============================================================================
do $$
declare
  v_n int;
begin
  select case when is_called then last_value else 0 end into v_n from pg_temp._falhas_0193;
  if v_n > 0 then
    raise exception 'FALHOU: % assert(s) da 0193 reprovaram — ver as linhas FALHOU acima', v_n;
  end if;
  raise notice 'TODOS OS TESTES DA 0193 (tolerância absoluta na base) PASSARAM';
end $$;

rollback;
