-- Testes da 0191 (Supabase/migrations/0191_o_mapa_de_um_ano_contra_a_dre_de_dois.sql).
-- Rodar via Supabase/test/run.sh.
--
-- O QUE ESTE ARQUIVO TRAVA, em COMPORTAMENTO (nunca mecanismo — regra 3):
--
--   1. Numa DRE de dois anos e um Mapa de Dívida de um ano só, o ano que o
--      mapa COBRE ainda é comparado — divergência real nele ainda sai
--      zona_cinzenta, e ausência de divergência ainda sai ok.
--   2. O ano que o mapa NÃO cobre NUNCA entra na comparação, mesmo quando a
--      despesa financeira daquele ano é absurdamente diferente dos juros do
--      mapa: o resultado (ok/zona_cinzenta) e `anos_checados` só refletem o
--      ano coberto — nunca os dois.
--   3. Quando NENHUM ano da DRE é coberto pelo mapa, a checagem não conclui:
--      precondicao_nao_satisfeita com motivo sem_periodo_par, e o texto diz
--      o ano do documento e a data do Mapa de Dívida (regra 1: o efeito, não
--      um zero mudo).
--   4. Mapa de Dívida SEM período atribuído: comportamento de ANTES desta
--      migration — compara todo ano da DRE contra a soma do documento
--      inteiro, sem filtro (não há como afirmar que o ano não é coberto).
--
-- Os valores de zona_cinzenta/ok reaproveitam o par medido pela 0188 (bloco 5
-- de motivo_especifico.test.sql): DRE em milhar 8.194 × mapa 5.308 diverge
-- (R$ 2.886.000, acima de greatest(R$ 50.000, 5%)); 5.308 × 5.309 confere
-- (R$ 1.000 de arredondamento). Não são números de produção (regra 4): o que
-- se afirma é só o comportamento do corte por ano.
--
-- O ASSERT NÃO PARA NO PRIMEIRO ERRO: anota e segue, e o bloco final reprova
-- com a CONTAGEM (regra 2 — medir quantos asserts a guarda desligada derruba).

begin;

create temp sequence _falhas_0191;

create or replace function pg_temp.teste_assert_0191(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  else
    raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
    perform nextval('pg_temp._falhas_0191');
  end if;
end $$;

-- =============================================================================
-- 1 e 2. DRE multi "24,25" + Mapa data-base "2025-12-31": 2025 (coberto)
-- ainda compara — ok e zona_cinzenta, nos dois sentidos — e 2024 (não
-- coberto) nunca entra, mesmo com despesa absurdamente diferente.
-- =============================================================================
do $$
declare
  v_caso uuid;
  v_ent  uuid;
  v_per  uuid;
  v_doc  uuid;
  v_r    jsonb;
  v_ok   boolean;
  v_res  text;
  v_motivo text;
  v_anos   text;
  v_ano_a  text;
begin
  raise notice '--- 1/2. ano coberto pelo mapa ainda compara; ano fora nunca entra ---';
  v_caso := (fn_upsert_caso('0191: ano coberto compara, ano fora não'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'PAR DO MAPA LTDA.', 'multi', '24,25', 'DRE', 0.95,
    'nome_arquivo', 'supabase_storage', '0191/dre-par.pdf', 'DRE PAR.pdf', true, 'HASH-0191-1', 'ok');
  v_doc := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    -- 2024: absurdamente diferente de QUALQUER juros de mapa plausível — se
    -- entrasse na comparação, seria zona_cinzenta na certa.
    jsonb_build_object('ordem',0,'chave','DESPESAS FINANCEIRAS','valor_num','-1','periodo_coluna','2024','unidade','milhar','confianca','0.97'),
    -- 2025: o par que confere (5.308 x 5.309, arredondamento de R$ 1.000).
    jsonb_build_object('ordem',1,'chave','DESPESAS FINANCEIRAS','valor_num','-5309','periodo_coluna','2025','unidade','milhar','confianca','0.97')
  ), 'N2');
  v_r := fn_registrar_documento(v_caso, 'PAR DO MAPA LTDA.', 'data-base', '2025-12-31', 'MAPA_DIVIDA', 0.95,
    'nome_arquivo', 'supabase_storage', '0191/mapa-par.pdf', 'MAPA PAR.pdf', true, 'HASH-0191-2', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Banco X - capital de giro - juros do exercício','valor_num','5308','unidade','milhar','confianca','0.97')
  ), 'N2');
  select entidade_id, periodo_id into v_ent, v_per from documento where id = v_doc;

  -- 1a. 2025 confere (5.309 x 5.308) => ok, e SÓ 1 ano checado (não 2).
  v_r := fn_reconciliar_despfin_dre_vs_divida(v_caso, v_ent, v_per);
  select precondicoes_ok, resultado, motivo_precondicao,
         materialidade->>'anos_checados', fonte_a->>'ano'
    into v_ok, v_res, v_motivo, v_anos, v_ano_a
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0191(v_ok and v_res = 'ok' and v_motivo is null,
    'o ano coberto (2025) confere: a checagem CONCLUI ok, apesar do ano 2024 '
    'ter uma despesa absurdamente diferente de qualquer juros plausível',
    format('precondicoes_ok=%s resultado=%s motivo=%s', v_ok, v_res, v_motivo));
  perform pg_temp.teste_assert_0191(v_anos = '1',
    'e SÓ o ano coberto entra na conta: anos_checados=1, nunca 2', format('anos_checados=%s', v_anos));
  perform pg_temp.teste_assert_0191(v_ano_a = '2025',
    'e o ano que de fato foi comparado é o coberto pelo mapa (2025), não o outro',
    format('fonte_a.ano=%s', v_ano_a));

  -- 1b. 2025 diverge de verdade (8.194 x 5.308) => zona_cinzenta — a checagem
  -- ainda PEGA divergência real no ano coberto; não virou "sempre ok".
  update campo_extraido ce set valor_num = -8194
    from documento_versao dv
   where dv.documento_id = v_doc and ce.documento_versao_id = dv.id
     and ce.chave = 'DESPESAS FINANCEIRAS' and ce.periodo_coluna = '2025';
  v_r := fn_reconciliar_despfin_dre_vs_divida(v_caso, v_ent, v_per);
  select precondicoes_ok, resultado, motivo_precondicao, materialidade->>'anos_checados'
    into v_ok, v_res, v_motivo, v_anos
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0191(v_ok and v_res = 'zona_cinzenta' and v_motivo is null,
    'divergência REAL no ano coberto (2025: 8.194 x 5.308, R$ 2.886.000) ainda sai zona_cinzenta — '
    'o corte por ano não vira "nunca mais acusa"',
    format('precondicoes_ok=%s resultado=%s motivo=%s', v_ok, v_res, v_motivo));
  perform pg_temp.teste_assert_0191(v_anos = '1',
    'e continua sendo SÓ o ano coberto (2024 nunca entrou na conta, nem para o lado ruim)',
    format('anos_checados=%s', v_anos));
end $$;

-- =============================================================================
-- 3. NENHUM ano da DRE é coberto pelo mapa: não conclui, sem_periodo_par, com
-- o texto dizendo o ano do documento e o do Mapa de Dívida.
-- =============================================================================
do $$
declare
  v_caso    uuid;
  v_ent     uuid;
  v_doc_dre uuid;
  v_per_consulta uuid;
  v_r       jsonb;
  v_ok      boolean;
  v_motivo  text;
  v_desc    text;
begin
  raise notice '--- 3. mapa não cobre NENHUM ano da DRE: sem_periodo_par, não ok nem zona_cinzenta ---';
  v_caso := (fn_upsert_caso('0191: DRE de um ano contra mapa de outro'))::uuid;

  v_r := fn_registrar_documento(v_caso, 'SO 2024 LTDA.', 'anual', '2024', 'DRE', 0.95,
    'nome_arquivo', 'supabase_storage', '0191/dre-2024.pdf', 'DRE 2024.pdf', true, 'HASH-0191-3', 'ok');
  v_doc_dre := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','DESPESAS FINANCEIRAS','valor_num','-8000','periodo_coluna','2024','unidade','unidade','confianca','0.97')
  ), 'N2');
  v_r := fn_registrar_documento(v_caso, 'SO 2024 LTDA.', 'anual', '2025', 'MAPA_DIVIDA', 0.95,
    'nome_arquivo', 'supabase_storage', '0191/mapa-2025.pdf', 'MAPA 2025.pdf', true, 'HASH-0191-4', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Banco Y - capital de giro - juros do exercício','valor_num','8000','unidade','unidade','confianca','0.97')
  ), 'N2');
  select entidade_id into v_ent from documento where id = v_doc_dre;

  -- Nem a DRE (período próprio 'anual:2024') nem o Mapa (período próprio
  -- 'anual:2025') são usados como período de CONSULTA — um exato de qualquer
  -- um dos dois faria fn_documento_por_tipo não achar o outro documento
  -- (fn_periodos_compativeis entre 2024 e 2025 sozinhos é falso: anos
  -- disjuntos). Um período 'multi:24,25' É compatível com os dois
  -- (intersecção não vazia em cada par) — assim os DOIS documentos são
  -- achados, e é o corte por ano desta migration, não a busca do documento,
  -- que decide que não há comparação.
  v_per_consulta := fn_upsert_periodo(v_caso, 'multi', '24,25');

  v_r := fn_reconciliar_despfin_dre_vs_divida(v_caso, v_ent, v_per_consulta);
  select precondicoes_ok, motivo_precondicao into v_ok, v_motivo
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0191(not v_ok and v_motivo = 'sem_periodo_par',
    'nenhum ano da DRE (2024) é coberto pelo Mapa (2025): a checagem NÃO conclui, '
    'com o motivo sem_periodo_par — nem ok nem zona_cinzenta',
    format('precondicoes_ok=%s motivo=%s', v_ok, v_motivo));

  select descricao into v_desc from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:despfin_dre_vs_divida' and estado <> 'resolvida';
  perform pg_temp.teste_assert_0191(
    v_desc like 'MOTIVO: sem período par%'
      and v_desc like '%2024%' and v_desc like '%2025%'
      and v_desc like '%não há juros deste exercício para comparar%',
    'e o texto diz QUAL ano da DRE ficou sem comparar e a QUE data o Mapa de Dívida se refere '
    '(regra 1: o efeito, não um zero mudo)', left(v_desc, 400));
end $$;

-- =============================================================================
-- 4. Mapa de Dívida SEM período atribuído: comportamento de ANTES da 0191 —
-- compara mesmo assim (sem período do mapa, não há como afirmar que o ano
-- não é coberto).
-- =============================================================================
do $$
declare
  v_caso uuid;
  v_ent  uuid;
  v_per  uuid;
  v_doc  uuid;
  v_r    jsonb;
  v_ok   boolean;
  v_res  text;
  v_motivo text;
begin
  raise notice '--- 4. mapa SEM período: comportamento antigo, sem filtro por ano ---';
  v_caso := (fn_upsert_caso('0191: mapa sem período mantém o comportamento antigo'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'SEM PERIODO LTDA.', 'anual', '2025', 'DRE', 0.95,
    'nome_arquivo', 'supabase_storage', '0191/dre-semper.pdf', 'DRE SEMPER.pdf', true, 'HASH-0191-5', 'ok');
  v_doc := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','DESPESAS FINANCEIRAS','valor_num','-8194','periodo_coluna','2025','unidade','milhar','confianca','0.97')
  ), 'N2');
  -- periodo_tipo/periodo_ref NULOS: fn_upsert_periodo devolve NULL, o
  -- documento nasce com periodo_id NULL.
  v_r := fn_registrar_documento(v_caso, 'SEM PERIODO LTDA.', null, null, 'MAPA_DIVIDA', 0.95,
    'nome_arquivo', 'supabase_storage', '0191/mapa-semper.pdf', 'MAPA SEMPER.pdf', true, 'HASH-0191-6', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Banco Z - capital de giro - juros do exercício','valor_num','5308','unidade','milhar','confianca','0.97')
  ), 'N2');
  select entidade_id, periodo_id into v_ent, v_per from documento where id = v_doc;

  perform pg_temp.teste_assert_0191(
    exists (select 1 from documento where caso_id = v_caso and tipo_taxonomia = 'MAPA_DIVIDA' and periodo_id is null),
    'o Mapa de Dívida nasceu de fato SEM período (a precondição deste bloco)');

  v_r := fn_reconciliar_despfin_dre_vs_divida(v_caso, v_ent, v_per);
  select precondicoes_ok, resultado, motivo_precondicao into v_ok, v_res, v_motivo
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0191(v_ok and v_res = 'zona_cinzenta' and v_motivo is null,
    'mapa sem período: a checagem compara mesmo assim (comportamento de ANTES da 0191) — '
    '2025: 8.194 x 5.308 ainda sai zona_cinzenta',
    format('precondicoes_ok=%s resultado=%s motivo=%s', v_ok, v_res, v_motivo));
end $$;

-- =============================================================================
do $$
declare
  v_n int;
begin
  select case when is_called then last_value else 0 end into v_n from pg_temp._falhas_0191;
  if v_n > 0 then
    raise exception 'FALHOU: % assert(s) da 0191 reprovaram — ver as linhas FALHOU acima', v_n;
  end if;
  raise notice 'TODOS OS TESTES DA 0191 PASSARAM';
end $$;

rollback;
