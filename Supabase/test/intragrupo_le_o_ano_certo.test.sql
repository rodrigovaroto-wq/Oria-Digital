-- Testes da 0195 (Supabase/migrations/0195_o_espelho_que_lia_o_balanco_de_outro_ano.sql).
-- Rodar via Supabase/test/run.sh.
--
-- O ARRANJO É O REAL, MEDIDO EM PRODUÇÃO (regra 4) — não os dois fixtures
-- existentes (Vertentes, Canastra), que não têm o formato que exercita o
-- defeito: lá cada entidade só tem UM documento BALANCO, e todo
-- `periodo_coluna` é o ANO em texto (nunca nulo) — ver o cabeçalho da 0195.
-- Este arquivo reproduz o par que produção tem:
--
--   • entidade A: um balanço "anual 2025" SEM `periodo_coluna` (retrato de
--     um ano só, como "Teste 00"/"teste alto volume" em produção) trazendo
--     "Contas a receber intragrupo - B".
--   • entidade B: DOIS balanços, "anual 2023" e "anual 2025" (cada um sem
--     `periodo_coluna` também — são peças de exercícios diferentes, não um
--     documento comparativo), trazendo "Fornecedores intragrupo - A" nos
--     dois anos, com valores DIFERENTES (o real: a dívida cresce).
--
-- O QUE ESTE ARQUIVO TRAVA, em COMPORTAMENTO (nunca mecanismo — regra 3):
--
--   1. Consultado em 2023: a linha de A (que só tem balanço de 2025) NÃO
--      pode entrar — o par fica incompleto (só B tem balanço em 2023), e a
--      checagem não conta par nenhum para este ano (não "ok" por vazamento,
--      não "zona_cinzenta" por comparar o balanço errado).
--   2. Consultado em 2025: os dois lados se espelham — UM par conferido,
--      fechando (ou divergindo, no cenário negativo) com o número de 2025.
--   3. NEGATIVO — mexendo no lado de 2025 de B, a divergência aparece SÓ em
--      2025, nunca em 2023 (que continua sem par).
--
-- O ASSERT NÃO PARA NO PRIMEIRO ERRO: anota e segue, e o bloco final reprova
-- com a CONTAGEM (regra 2 — medir quantos asserts a guarda desligada
-- derruba).

begin;

create temp sequence _falhas_0195;

create or replace function pg_temp.teste_assert_0195(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  else
    raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
    perform nextval('pg_temp._falhas_0195');
  end if;
end $$;

-- =============================================================================
-- MONTAGEM DO CASO (usada pelos três blocos abaixo).
--
--   ESPELHO PARTICIPAÇÕES S.A. ("A"): ÚNICO balanço, "anual 2025", SEM
--     periodo_coluna — "Contas a receber intragrupo - ESPELHO INDÚSTRIA" =
--     9.000.
--   ESPELHO INDÚSTRIA LTDA. ("B"): DOIS balanços, "anual 2023" (passivo
--     3.000) e "anual 2025" (passivo 9.000, espelha A) — "Fornecedores
--     intragrupo - ESPELHO PARTICIPAÇÕES" em cada um, SEM periodo_coluna.
-- =============================================================================
do $$
declare
  v_caso uuid;
  v_r    jsonb;
  v_per_consulta uuid;
  v_ok   boolean;
  v_res  text;
  v_txt  text;
  v_json jsonb;
begin
  raise notice '--- 1/2/3. entidade com balanço de um ano só não empresta linha para o ano da irmã ---';
  v_caso := (fn_upsert_caso('0195: balanço de um ano só não empresta linha para o ano da irmã'))::uuid;

  -- A: só tem balanço de 2025.
  v_r := fn_registrar_documento(v_caso, 'ESPELHO PARTICIPAÇÕES S.A.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0195/bp-espelho-part-2025.pdf', 'BP ESPELHO PART 2025.pdf', true, 'HASH-0195-1', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Contas a receber intragrupo - ESPELHO INDÚSTRIA','valor_num','9000','unidade','milhar','confianca','0.97')
  ), 'N2');

  -- B: um balanço de 2023 (passivo 3.000, ano em que A não tem par) e outro
  -- de 2025 (passivo 9.000, espelha A).
  v_r := fn_registrar_documento(v_caso, 'ESPELHO INDÚSTRIA LTDA.', 'anual', '2023', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0195/bp-espelho-ind-2023.pdf', 'BP ESPELHO IND 2023.pdf', true, 'HASH-0195-2', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Fornecedores intragrupo - ESPELHO PARTICIPAÇÕES','valor_num','3000','unidade','milhar','confianca','0.97')
  ), 'N2');
  v_r := fn_registrar_documento(v_caso, 'ESPELHO INDÚSTRIA LTDA.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0195/bp-espelho-ind-2025.pdf', 'BP ESPELHO IND 2025.pdf', true, 'HASH-0195-3', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Fornecedores intragrupo - ESPELHO PARTICIPAÇÕES','valor_num','9000','unidade','milhar','confianca','0.97')
  ), 'N2');

  v_per_consulta := fn_upsert_periodo(v_caso, 'multi', '23,25');

  -- ---------------------------------------------------------------------
  -- 1. Consultado em 2023 E 2025 juntos (o período multi cobre os dois).
  --    Antes desta migration: o balanço "anual 2025" de A (sem
  --    periodo_coluna) contava também para 2023 (o vício 2), formando um
  --    par PARA CADA um dos dois anos — 2 pares conferidos, ambos fechando
  --    por coincidência (o mesmo número de A comparado contra o número de B
  --    de CADA ano). Corrigido: só o ano em que A TEM balanço (2025) forma
  --    par — 2023 fica sem o lado de A, e `count(distinct dona) = 2` já
  --    existente (0124) exclui o par incompleto. UM par conferido, não dois.
  -- ---------------------------------------------------------------------
  select fn_reconciliar_intragrupo(v_caso, v_per_consulta) into v_json;
  select resultado into v_res from reconciliacao where id = (v_json->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0195(v_res = 'ok', 'os dois anos consultados juntos: a checagem CONCLUI ok',
    format('resultado=%s', v_res));

  select r.materialidade->>'pares_conferidos' into v_txt from reconciliacao r
    where r.id = (v_json->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0195(v_txt = '1',
    'e é UM par só — o balanço de A (sem periodo_coluna) NÃO empresta a linha de 2025 para 2023',
    format('pares_conferidos=%s', v_txt));

  -- A fonte tem de nomear o ANO 2025 (o único par formado), nunca 2023.
  perform pg_temp.teste_assert_0195(
    (select bool_and((elem->>'ano')::int = 2025)
       from reconciliacao r, jsonb_array_elements(r.fonte_a) elem
      where r.id = (v_json->>'reconciliacao_id')::uuid),
    'e o único par registrado é do ano 2025, nunca 2023',
    (select string_agg(elem->>'ano', ', ') from reconciliacao r, jsonb_array_elements(r.fonte_a) elem
      where r.id = (v_json->>'reconciliacao_id')::uuid));

  -- ---------------------------------------------------------------------
  -- 2. Consultado só em 2023 (período que NÃO alcança 2025): sem par
  --    nenhum — A não tem balanço de 2023, B tem só o passivo (n_lados=1,
  --    sem contraparte do outro lado), e `count(distinct dona)=2` exclui.
  --    `documento_ausente`, sem pendência (comportamento desenhado da
  --    0124, preservado).
  -- ---------------------------------------------------------------------
  select fn_reconciliar_intragrupo(v_caso, (select id from periodo where caso_id = v_caso and tipo = 'anual' and referencia = '2023'))
    into v_json;
  select resultado into v_res from reconciliacao where id = (v_json->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0195(v_res = 'precondicao_nao_satisfeita',
    'consultado só em 2023 (A sem balanço nesse ano): sem par, documento_ausente — nunca zona_cinzenta fabricada',
    format('resultado=%s', v_res));

  select count(*) into v_txt from pendencia
    where caso_id = v_caso and estado <> 'resolvida' and motivo = 'reconciliacao:intragrupo_espelho';
  perform pg_temp.teste_assert_0195(v_txt = '0',
    'e não abre pendência (documento_ausente é o único motivo que não abre — 0124, preservado)',
    format('%s pendência(s)', v_txt));
end $$;

-- =============================================================================
-- 4. NEGATIVO — divergência PLANTADA só em 2025: o par de 2025 deixa de
-- fechar (A registra 9.000, B passa a registrar 9.900), e a checagem tem de
-- acusar — só em 2025, sem contaminar 2023 (que já não tem par).
-- =============================================================================
do $$
declare
  v_caso uuid;
  v_r    jsonb;
  v_per_consulta uuid;
  v_json jsonb;
  v_res  text;
  v_txt  text;
  v_desc text;
begin
  raise notice '--- 4. NEGATIVO: divergência plantada só em 2025 é acusada só em 2025 ---';
  v_caso := (fn_upsert_caso('0195: divergência plantada só no ano que TEM par'))::uuid;

  v_r := fn_registrar_documento(v_caso, 'DIVERGE PARTICIPAÇÕES S.A.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0195/bp-diverge-part-2025.pdf', 'BP DIVERGE PART 2025.pdf', true, 'HASH-0195-4', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Contas a receber intragrupo - DIVERGE INDÚSTRIA','valor_num','9000','unidade','milhar','confianca','0.97')
  ), 'N2');

  v_r := fn_registrar_documento(v_caso, 'DIVERGE INDÚSTRIA LTDA.', 'anual', '2023', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0195/bp-diverge-ind-2023.pdf', 'BP DIVERGE IND 2023.pdf', true, 'HASH-0195-5', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Fornecedores intragrupo - DIVERGE PARTICIPAÇÕES','valor_num','3000','unidade','milhar','confianca','0.97')
  ), 'N2');
  -- 2025: B registra 9.900, contra os 9.000 de A — diferença de 900 mil.
  v_r := fn_registrar_documento(v_caso, 'DIVERGE INDÚSTRIA LTDA.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0195/bp-diverge-ind-2025.pdf', 'BP DIVERGE IND 2025.pdf', true, 'HASH-0195-6', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Fornecedores intragrupo - DIVERGE PARTICIPAÇÕES','valor_num','9900','unidade','milhar','confianca','0.97')
  ), 'N2');

  v_per_consulta := fn_upsert_periodo(v_caso, 'multi', '23,25');
  select fn_reconciliar_intragrupo(v_caso, v_per_consulta) into v_json;
  select v_json->>'resultado' into v_res;
  perform pg_temp.teste_assert_0195(v_res = 'zona_cinzenta',
    'a divergência de 2025 (9.000 x 9.900) é acusada', format('resultado=%s', v_res));

  select r.materialidade->>'pares_conferidos' into v_txt from reconciliacao r
    where r.id = (v_json->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0195(v_txt = '1',
    'e é UM par só (2023 continua sem par — A não tem balanço nesse ano)', format('pares_conferidos=%s', v_txt));

  select count(*) into v_txt from pendencia
    where caso_id = v_caso and estado <> 'resolvida' and motivo = 'reconciliacao:intragrupo_espelho';
  perform pg_temp.teste_assert_0195(v_txt = '1', 'e ABRE uma pendência', format('%s pendência(s)', v_txt));

  select descricao into v_desc from pendencia
    where caso_id = v_caso and estado <> 'resolvida' and motivo = 'reconciliacao:intragrupo_espelho';
  perform pg_temp.teste_assert_0195(v_desc like '%2025%' and v_desc not like '%2023%',
    'e o texto nomeia 2025, nunca 2023 (que não tem par nenhum para citar)', left(v_desc, 300));
  perform pg_temp.teste_assert_0195(v_desc like '%900000%',
    'e a diferença em reais (900 mil, escalas já convertidas)', v_desc);
end $$;

-- =============================================================================
do $$
declare
  v_n int;
begin
  select case when is_called then last_value else 0 end into v_n from pg_temp._falhas_0195;
  if v_n > 0 then
    raise exception 'FALHOU: % assert(s) da 0195 reprovaram — ver as linhas FALHOU acima', v_n;
  end if;
  raise notice 'TODOS OS TESTES DA 0195 PASSARAM';
end $$;

rollback;
