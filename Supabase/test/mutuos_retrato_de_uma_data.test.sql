-- Testes da 0194 (Supabase/migrations/0194_a_planilha_de_mutuos_que_nunca_foi_lida.sql).
-- Rodar via Supabase/test/run.sh.
--
-- O FORMATO É O DE PRODUÇÃO, MEDIDO — não inventado (regra 4). A planilha
-- MUTUOS de produção é um RETRATO de uma data: documento com período
-- `data-base 31/12/2025`, linhas com `chave` = par de empresas, `secao` NULA,
-- e o CONCEITO NA COLUNA (`periodo_coluna`): "Mutuante"/"Mutuária" (sem
-- número) e "Saldo devedor" com o valor; "TOTAL" é o subtotal. Todos os casos
-- de produção medidos (25/09/2026) têm a coluna numérica chamada "Saldo
-- devedor". É o mesmo arranjo que os dois FIXTURES do book (Vertentes,
-- Canastra) NÃO reproduzem — eles gravam `periodo_coluna` = o ANO, não o
-- cabeçalho da coluna (ver o cabeçalho da 0194), e é por isso que precisam de
-- um teste à parte em vez de reusar os fixtures existentes.
--
-- O QUE ESTE ARQUIVO TRAVA, em COMPORTAMENTO (nunca mecanismo — regra 3):
--
--   1. Planilha-retrato + balanços com conta de mútuo: a checagem CONCLUI
--      (precondicoes_ok = true) e acusa a divergência real, em reais.
--   2. Planilha corrigida para bater com o balanço: conclui `ok`.
--   3. Planilha-retrato de OUTRO ano (2024) consultada no período de 2025:
--      não conclui — `sem_periodo_par`, pendência aberta com texto que diz o
--      ano sem par.
--   4. Planilha-retrato sem coluna de saldo nenhuma: não conclui —
--      `linha_nao_localizada`.
--   5. NEGATIVO — balanço sem conta de mútuo nenhuma: continua
--      `documento_ausente`, SEM pendência (comportamento desenhado da
--      0117/0123, preservado por esta migration).
--
-- O ASSERT NÃO PARA NO PRIMEIRO ERRO: anota e segue, e o bloco final reprova
-- com a CONTAGEM (regra 2 — medir quantos asserts a guarda desligada
-- derruba).

begin;

create temp sequence _falhas_0194;

create or replace function pg_temp.teste_assert_0194(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  else
    raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
    perform nextval('pg_temp._falhas_0194');
  end if;
end $$;

-- =============================================================================
-- 1 e 2. Planilha-retrato 31/12/2025 (Mutuante/Mutuária/Saldo devedor/TOTAL,
-- milhar) contra dois balanços que CONCORDAM entre si (16.300 a receber numa
-- entidade, 11.400 + 4.900 a pagar em duas outras): a checagem CONCLUI e
-- acusa os R$ 240 mil que a planilha erra (16.060 x 16.300). Corrigida a
-- planilha, conclui `ok`.
-- =============================================================================
do $$
declare
  v_caso   uuid;
  v_per    uuid; -- período da planilha (data-base 31/12/2025)
  v_doc_mut uuid;
  v_r      jsonb;
  v_ok     boolean;
  v_res    text;
  v_motivo text;
  v_num    numeric;
begin
  raise notice '--- 1/2. planilha-retrato: conclui e acusa a divergência; corrigida, conclui ok ---';
  v_caso := (fn_upsert_caso('0194: planilha-retrato contra balanços que se espelham'))::uuid;

  -- A PLANILHA — retrato de 31/12/2025, conceito na coluna (0145).
  v_r := fn_registrar_documento(v_caso, 'GRUPO RETRATO', 'data-base', '2025-12-31', 'MUTUOS', 0.96,
    'nome_arquivo', 'supabase_storage', '0194/mutuos-retrato.pdf', 'MUTUOS.pdf', true, 'HASH-0194-1', 'ok');
  v_doc_mut := (v_r->>'documento_id')::uuid;
  v_per := (select periodo_id from documento where id = v_doc_mut);
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    -- Colunas de NOME, sem número (como o retrato real) — não entram em
    -- comparação nenhuma (valor_num nulo), aqui só para reproduzir a forma.
    jsonb_build_object('ordem',0,'chave','RETRATO PARTICIPAÇÕES → RETRATO INDÚSTRIA','valor_texto','RETRATO PARTICIPAÇÕES S.A.','periodo_coluna','Mutuante','confianca','0.96'),
    jsonb_build_object('ordem',1,'chave','RETRATO PARTICIPAÇÕES → RETRATO INDÚSTRIA','valor_texto','RETRATO INDÚSTRIA LTDA.','periodo_coluna','Mutuária','confianca','0.96'),
    -- A coluna do SALDO — a numérica, a única que entra na soma.
    jsonb_build_object('ordem',2,'chave','RETRATO PARTICIPAÇÕES → RETRATO INDÚSTRIA','valor_num','11160','unidade','milhar','periodo_coluna','Saldo devedor','confianca','0.96'),
    jsonb_build_object('ordem',3,'chave','RETRATO PARTICIPAÇÕES → RETRATO COMERCIAL','valor_num','4900','unidade','milhar','periodo_coluna','Saldo devedor','confianca','0.96'),
    jsonb_build_object('ordem',4,'chave','TOTAL','valor_num','16060','unidade','milhar','periodo_coluna','Saldo devedor','confianca','0.96')
  ), 'N2');

  -- OS BALANÇOS — os dois lados se espelham (16.300 = 11.400 + 4.900).
  v_r := fn_registrar_documento(v_caso, 'RETRATO PARTICIPAÇÕES S.A.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-holding.pdf', 'BP HOLDING.pdf', true, 'HASH-0194-2', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a receber - partes relacionadas','valor_num','16300','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');
  v_r := fn_registrar_documento(v_caso, 'RETRATO INDÚSTRIA LTDA.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-industria.pdf', 'BP INDUSTRIA.pdf', true, 'HASH-0194-3', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a pagar - partes relacionadas','valor_num','11400','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');
  v_r := fn_registrar_documento(v_caso, 'RETRATO COMERCIAL LTDA.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-comercial.pdf', 'BP COMERCIAL.pdf', true, 'HASH-0194-4', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a pagar - partes relacionadas','valor_num','4900','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');

  -- 1a. CONCLUI, e acusa os R$ 240 mil (16.300 x 16.060), em REAIS.
  v_r := fn_reconciliar_mutuos(v_caso, v_per);
  select precondicoes_ok, resultado, motivo_precondicao, divergencia_abs
    into v_ok, v_res, v_motivo, v_num
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0194(v_ok and v_res = 'zona_cinzenta' and v_motivo is null,
    'planilha-retrato + balanços com conta de mútuo: a checagem CONCLUI (não documento_ausente)',
    format('precondicoes_ok=%s resultado=%s motivo=%s', v_ok, v_res, v_motivo));
  perform pg_temp.teste_assert_0194(v_num between 239000 and 241000,
    'e acusa a divergência real (16.300 x 16.060, em reais)', format('divergencia_abs=%s', v_num));

  select count(*) into v_num from pendencia
    where caso_id = v_caso and motivo = 'reconciliacao:mutuos_planilha_vs_balanco' and estado <> 'resolvida';
  perform pg_temp.teste_assert_0194(v_num = 1,
    'e ABRE pendência (a checagem voltando a funcionar, não uma regressão)', format('%s pendência(s)', v_num));

  -- 1b. Corrigida a planilha (11.160 -> 11.400, TOTAL -> 16.300): ok.
  update campo_extraido ce set valor_num = 11400
    from documento_versao dv where dv.documento_id = v_doc_mut and ce.documento_versao_id = dv.id
      and ce.chave = 'RETRATO PARTICIPAÇÕES → RETRATO INDÚSTRIA' and ce.periodo_coluna = 'Saldo devedor';
  update campo_extraido ce set valor_num = 16300
    from documento_versao dv where dv.documento_id = v_doc_mut and ce.documento_versao_id = dv.id
      and ce.chave = 'TOTAL';
  v_r := fn_reconciliar_mutuos(v_caso, v_per);
  select precondicoes_ok, resultado, motivo_precondicao into v_ok, v_res, v_motivo
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0194(v_ok and v_res = 'ok' and v_motivo is null,
    'planilha corrigida (16.300 = 16.300): conclui ok',
    format('precondicoes_ok=%s resultado=%s motivo=%s', v_ok, v_res, v_motivo));
end $$;

-- =============================================================================
-- 3. Planilha-retrato de OUTRO ano (31/12/2024) consultada no período de
-- 2025 (achado 3 da revisão de fidelidade): a planilha É escolhida POR ANO,
-- não uma vez para a checagem inteira — o ano sem planilha própria (2025)
-- vira "planilha deste exercício não entregue", documento_ausente, SEM
-- pendência (é cobrança de checklist, não achado de reconciliação; a versão
-- original de 0194 abria pendência falsa aqui, com o texto "a planilha é
-- retrato de 2024 — não há esse exercício", mesmo quando o caso tivesse a
-- planilha certa de outro ano em produção — não é este caso, mas a régua de
-- comportamento é a mesma: não confundir "ano sem par" com "documento
-- presente que não localizou algo").
-- =============================================================================
do $$
declare
  v_caso uuid;
  v_r    jsonb;
  v_per_consulta uuid;
  v_ok   boolean;
  v_res  text;
  v_motivo text;
  v_n    int;
begin
  raise notice '--- 3. planilha-retrato de 2024 consultada em 2025: documento_ausente, sem pendência ---';
  v_caso := (fn_upsert_caso('0194: planilha-retrato de outro ano'))::uuid;

  -- Planilha: retrato de 31/12/2024.
  v_r := fn_registrar_documento(v_caso, 'GRUPO OUTRO ANO', 'data-base', '2024-12-31', 'MUTUOS', 0.96,
    'nome_arquivo', 'supabase_storage', '0194/mutuos-2024.pdf', 'MUTUOS 2024.pdf', true, 'HASH-0194-5', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','OUTRO ANO PARTICIPAÇÕES → OUTRO ANO INDÚSTRIA','valor_num','5000','unidade','milhar','periodo_coluna','Saldo devedor','confianca','0.96')
  ), 'N2');

  -- Balanço com conta de mútuo — SÓ para 2025 (periodo_coluna='2025'), para
  -- que o ano de 2024 (sem coluna correspondente no balanço) fique com
  -- n_lados=0 e não interfira: o que este teste isola é o ano de 2025, cujo
  -- balanço TEM conta de mútuo mas nenhuma planilha do caso cobre 2025 (a
  -- única planilha do caso é o retrato de 2024).
  v_r := fn_registrar_documento(v_caso, 'OUTRO ANO PARTICIPAÇÕES S.A.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-outro-ano.pdf', 'BP OUTRO ANO.pdf', true, 'HASH-0194-6', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a receber - partes relacionadas','valor_num','5200','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');

  -- Período de CONSULTA cobrindo 2024 e 2025 — precisa alcançar os dois
  -- anos para o laço avaliar v_ano=2025, que é o que este teste isola (2024
  -- fica silencioso por n_lados=0, como o cenário negativo #5).
  v_per_consulta := fn_upsert_periodo(v_caso, 'multi', '24,25');

  v_r := fn_reconciliar_mutuos(v_caso, v_per_consulta);
  select precondicoes_ok, resultado, motivo_precondicao into v_ok, v_res, v_motivo
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0194(not v_ok and v_res = 'precondicao_nao_satisfeita' and v_motivo = 'documento_ausente',
    'a planilha é retrato de 2024, o balanço tem mútuo em 2025: NÃO conclui, documento_ausente (achado 3 — não sem_periodo_par)',
    format('precondicoes_ok=%s resultado=%s motivo=%s', v_ok, v_res, v_motivo));

  select count(*) into v_n from pendencia
    where caso_id = v_caso and motivo = 'reconciliacao:mutuos_planilha_vs_balanco' and estado <> 'resolvida';
  perform pg_temp.teste_assert_0194(v_n = 0,
    'e NÃO abre pendência — documento_ausente continua sendo o único motivo que não abre (0117/0123, preservado)',
    format('%s pendência(s)', v_n));

  -- O texto ("%s: a planilha de mútuos deste exercício não foi entregue...")
  -- não fica em coluna nenhuma acessível por SQL: `documento_ausente` nunca
  -- abre pendência (é a própria 0117/0123, preservado — ver o teste 5), e
  -- `reconciliacao` não tem coluna `descricao` (só `pendencia` tem, e só
  -- quando abre uma). Mesma limitação de design de TODO `documento_ausente`
  -- desta função, não uma lacuna nova desta correção — não é um comportamento
  -- que este arquivo consiga travar em SQL sem mudar essa decisão de schema,
  -- que está fora do escopo dos três achados revisados.
end $$;

-- =============================================================================
-- 4. Planilha-retrato do próprio ano, mas SEM coluna de saldo nenhuma: não
-- conclui — linha_nao_localizada.
-- =============================================================================
do $$
declare
  v_caso uuid;
  v_r    jsonb;
  v_per  uuid;
  v_ok   boolean;
  v_motivo text;
begin
  raise notice '--- 4. planilha-retrato sem coluna de saldo: linha_nao_localizada ---';
  v_caso := (fn_upsert_caso('0194: planilha-retrato sem coluna de saldo'))::uuid;

  v_r := fn_registrar_documento(v_caso, 'GRUPO SEM SALDO', 'data-base', '2025-12-31', 'MUTUOS', 0.96,
    'nome_arquivo', 'supabase_storage', '0194/mutuos-sem-saldo.pdf', 'MUTUOS SEM SALDO.pdf', true, 'HASH-0194-7', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    -- Uma coluna numérica, mas o cabeçalho NÃO diz "saldo" — formato que o
    -- localizador da 0145 (termo 'saldo') não reconhece.
    jsonb_build_object('ordem',0,'chave','SEM SALDO PARTICIPAÇÕES → SEM SALDO INDÚSTRIA','valor_num','5000','unidade','milhar','periodo_coluna','Montante','confianca','0.96')
  ), 'N2');

  v_r := fn_registrar_documento(v_caso, 'SEM SALDO PARTICIPAÇÕES S.A.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-sem-saldo.pdf', 'BP SEM SALDO.pdf', true, 'HASH-0194-8', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a receber - partes relacionadas','valor_num','5000','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');
  select periodo_id into v_per from documento where caso_id = v_caso and tipo_taxonomia = 'MUTUOS';

  v_r := fn_reconciliar_mutuos(v_caso, v_per);
  select precondicoes_ok, motivo_precondicao into v_ok, v_motivo
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0194(not v_ok and v_motivo = 'linha_nao_localizada',
    'planilha-retrato do ano certo, mas sem coluna "saldo": NÃO conclui, linha_nao_localizada',
    format('precondicoes_ok=%s motivo=%s', v_ok, v_motivo));
end $$;

-- =============================================================================
-- 5. NEGATIVO — balanço sem conta de mútuo NENHUMA: continua documento_ausente,
-- SEM pendência (comportamento desenhado da 0117/0123, que esta migration
-- preserva).
-- =============================================================================
do $$
declare
  v_caso uuid;
  v_r    jsonb;
  v_per  uuid;
  v_ok   boolean;
  v_res  text;
  v_motivo text;
  v_n    int;
begin
  raise notice '--- 5. NEGATIVO: balanço sem conta de mútuo continua documento_ausente, sem pendência ---';
  v_caso := (fn_upsert_caso('0194: balanço sem conta de mútuo nenhuma'))::uuid;

  v_r := fn_registrar_documento(v_caso, 'GRUPO SEM MUTUO', 'data-base', '2025-12-31', 'MUTUOS', 0.96,
    'nome_arquivo', 'supabase_storage', '0194/mutuos-sem-conta.pdf', 'MUTUOS SEM CONTA.pdf', true, 'HASH-0194-9', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','SEM MUTUO PARTICIPAÇÕES → SEM MUTUO INDÚSTRIA','valor_num','5000','unidade','milhar','periodo_coluna','Saldo devedor','confianca','0.96')
  ), 'N2');

  -- Balanço PRESENTE, mas sem conta de mútuo nenhuma (só caixa).
  v_r := fn_registrar_documento(v_caso, 'SEM MUTUO PARTICIPAÇÕES S.A.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-sem-mutuo.pdf', 'BP SEM MUTUO.pdf', true, 'HASH-0194-10', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Caixa e equivalentes','valor_num','1000','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');
  select periodo_id into v_per from documento where caso_id = v_caso and tipo_taxonomia = 'MUTUOS';

  v_r := fn_reconciliar_mutuos(v_caso, v_per);
  select precondicoes_ok, resultado, motivo_precondicao into v_ok, v_res, v_motivo
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0194(not v_ok and v_res = 'precondicao_nao_satisfeita' and v_motivo = 'documento_ausente',
    -- `resultado` sai achatado para precondicao_nao_satisfeita (0186/0188); o
    -- valor ORIGINAL (documento_ausente) vive em motivo_precondicao — é ele
    -- quem decide, em fn_registrar_reconciliacao, que NÃO abre pendência.
    'balanço sem conta de mútuo: motivo_precondicao continua documento_ausente (comportamento preservado)',
    format('precondicoes_ok=%s resultado=%s motivo_precondicao=%s', v_ok, v_res, v_motivo));

  select count(*) into v_n from pendencia
    where caso_id = v_caso and motivo = 'reconciliacao:mutuos_planilha_vs_balanco' and estado <> 'resolvida';
  perform pg_temp.teste_assert_0194(v_n = 0,
    'e NÃO abre pendência — documento_ausente continua sendo o único motivo que não abre (0117/0123, preservado)',
    format('%s pendência(s)', v_n));
end $$;

-- =============================================================================
-- 6. ACHADO 1 (revisão de fidelidade, 28/09/2026): uma entidade tem DOIS
-- balanços do MESMO exercício — um "multi 24,25" carregado por ÚLTIMO, sem
-- coluna por ano e sem linha de mútuo (só lista as controladas, como o
-- documento real que causou o defeito), e um "anual 2025" carregado ANTES,
-- que TEM a linha de mútuo. Escolher só por `criado_em` (a versão original
-- desta migration) fazia o "multi" vencer e a entidade sumir do lado A. A
-- escolha correta é POR ANO: o documento que TRAZ dado do exercício vence.
-- =============================================================================
do $$
declare
  v_caso    uuid;
  v_per     uuid;
  v_doc_multi uuid;
  v_r       jsonb;
  v_ok      boolean;
  v_res     text;
  v_motivo  text;
  v_num     numeric;
begin
  raise notice '--- 6. achado 1: multi sem mútuo mais recente não vence anual com mútuo ---';
  v_caso := (fn_upsert_caso('0194: multi sem mútuo mais recente que anual com mútuo'))::uuid;

  -- A CONTROLADA: primeiro o "anual 2025", COM a linha de mútuo (passivo).
  v_r := fn_registrar_documento(v_caso, 'MULTI CONTROLADA LTDA.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-multi-anual.pdf', 'BP MULTI ANUAL.pdf', true, 'HASH-0194-20', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a pagar - partes relacionadas','valor_num','5000','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');

  -- Depois, para a MESMA entidade, um "multi 24,25" SEM coluna por ano e SEM
  -- linha de mútuo (só uma conta de caixa) — a forma real do documento que
  -- listava as controladas sem detalhar mútuo. `criado_em` empurrado para
  -- ADIANTE (mesma transação, `now()` fixo — o avanço explícito é o que
  -- reproduz "carregado depois" de forma determinística).
  v_r := fn_registrar_documento(v_caso, 'MULTI CONTROLADA LTDA.', 'multi', '24,25', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-multi-2425.pdf', 'BP MULTI 24-25.pdf', true, 'HASH-0194-21', 'ok');
  v_doc_multi := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Caixa e equivalentes','valor_num','900','unidade','milhar','confianca','0.97')
  ), 'N2');
  update documento set criado_em = criado_em + interval '1 minute' where id = v_doc_multi;

  -- A CONTRAPARTE: um único balanço, ativo 5.000 — espelha a MULTI CONTROLADA.
  v_r := fn_registrar_documento(v_caso, 'MULTI HOLDING S.A.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-multi-holding.pdf', 'BP MULTI HOLDING.pdf', true, 'HASH-0194-22', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a receber - partes relacionadas','valor_num','5000','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');

  -- A PLANILHA — retrato de 2025, batendo com os 5.000.
  v_r := fn_registrar_documento(v_caso, 'GRUPO MULTI', 'data-base', '2025-12-31', 'MUTUOS', 0.96,
    'nome_arquivo', 'supabase_storage', '0194/mutuos-multi.pdf', 'MUTUOS MULTI.pdf', true, 'HASH-0194-23', 'ok');
  v_per := (select periodo_id from documento where id = (v_r->>'documento_id')::uuid);
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','MULTI HOLDING S.A. → MULTI CONTROLADA LTDA.','valor_num','5000','unidade','milhar','periodo_coluna','Saldo devedor','confianca','0.96')
  ), 'N2');

  v_r := fn_reconciliar_mutuos(v_caso, v_per);
  select precondicoes_ok, resultado, motivo_precondicao, divergencia_abs
    into v_ok, v_res, v_motivo, v_num
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0194(v_ok and v_res = 'ok' and v_motivo is null,
    'achado 1: o "anual 2025" (tem a linha) vence o "multi 24,25" (não tem) mesmo carregado depois — conclui ok',
    format('precondicoes_ok=%s resultado=%s motivo=%s', v_ok, v_res, v_motivo));

  -- O assert acima sozinho é FRACO: se o "multi" vencesse (o bug), a
  -- MULTI CONTROLADA sumiria do lado A e sobraria só a HOLDING (ativo
  -- 5.000) contra a mesma planilha de 5.000 — ainda "ok", por coincidência
  -- de valor. O que distingue comportamento é os DOIS lados terem sido
  -- encontrados: `fonte_a->>'lado'` só é "os dois lados" quando n_lados=2
  -- (a MULTI CONTROLADA contribuiu o passivo).
  perform pg_temp.teste_assert_0194(
    (select fonte_a->>'lado' from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid) = 'os dois lados',
    'e os DOIS lados foram encontrados (não só a holding, por coincidência de valor)',
    (select fonte_a->>'lado' from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid));
end $$;

-- =============================================================================
-- 7. ACHADO 2 (revisão de fidelidade, 28/09/2026): razão social com
-- "ADMINISTRATIVOS" — `fn_lado_do_mutuo` casa "administr**ativo**s" com
-- "...ativo" e, aplicado à CHAVE da planilha-retrato (que é o PAR de
-- empresas, não um lado), derrubava a linha inteira quando o balanço só
-- tinha um lado. Numa planilha-retrato o filtro de lado não se aplica.
-- =============================================================================
do $$
declare
  v_caso   uuid;
  v_per    uuid;
  v_r      jsonb;
  v_ok     boolean;
  v_res    text;
  v_motivo text;
begin
  raise notice '--- 7. achado 2: razão social "ADMINISTRATIVOS" não derruba a linha da planilha-retrato ---';
  v_caso := (fn_upsert_caso('0194: razão social com ADMINISTRATIVOS'))::uuid;

  -- Só o lado PASSIVO no balanço.
  v_r := fn_registrar_documento(v_caso, 'AR SERVIÇOS ADMINISTRATIVOS E COMPARTILHADOS LTDA.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-ar-servicos.pdf', 'BP AR SERVICOS.pdf', true, 'HASH-0194-24', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a pagar - partes relacionadas','valor_num','8000','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');

  -- A planilha-retrato: a CHAVE é o par "ARAUCÁRIA PARTICIPAÇÕES S.A. - AR
  -- SERVIÇOS ADMINISTRATIVOS E COMPARTILHADOS LTDA." — `fn_lado_do_mutuo`
  -- casaria "ativo" dentro de "administrativos" se fosse aplicada aqui.
  v_r := fn_registrar_documento(v_caso, 'GRUPO ARAUCÁRIA TESTE', 'data-base', '2025-12-31', 'MUTUOS', 0.96,
    'nome_arquivo', 'supabase_storage', '0194/mutuos-araucaria.pdf', 'MUTUOS ARAUCARIA.pdf', true, 'HASH-0194-25', 'ok');
  v_per := (select periodo_id from documento where id = (v_r->>'documento_id')::uuid);
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','ARAUCÁRIA PARTICIPAÇÕES S.A. - AR SERVIÇOS ADMINISTRATIVOS E COMPARTILHADOS LTDA.','valor_num','8000','unidade','milhar','periodo_coluna','Saldo devedor','confianca','0.96')
  ), 'N2');

  v_r := fn_reconciliar_mutuos(v_caso, v_per);
  select precondicoes_ok, resultado, motivo_precondicao into v_ok, v_res, v_motivo
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0194(v_ok and v_res = 'ok' and v_motivo is null,
    'achado 2: a linha da planilha-retrato ENTRA mesmo com "ADMINISTRATIVOS" no par — conclui ok (não linha_nao_localizada)',
    format('precondicoes_ok=%s resultado=%s motivo=%s', v_ok, v_res, v_motivo));
end $$;

-- =============================================================================
-- 8. ACHADO 3 (revisão de fidelidade, 28/09/2026), positivo com DUAS
-- planilhas: o caso tem uma planilha-retrato por ano (2024 e 2025, como
-- "Teste 00"/"teste alto volume" em produção). Cada ano tem de casar com A
-- SUA planilha, não com "a" planilha escolhida uma vez para a checagem
-- inteira — 2024 fecha (ok) e 2025 diverge, na MESMA rodada.
-- =============================================================================
do $$
declare
  v_caso uuid;
  v_r    jsonb;
  v_per_consulta uuid;
  v_ok   boolean;
  v_res  text;
  v_motivo text;
  v_desc text;
  v_n    numeric;
begin
  raise notice '--- 8. achado 3: duas planilhas-retrato (2024 e 2025), cada ano casa com a sua ---';
  v_caso := (fn_upsert_caso('0194: duas planilhas-retrato, dois anos'))::uuid;

  -- Planilhas: 2024 bate exato (5.000); 2025 diverge (planilha 6.700 x balanço 7.000).
  v_r := fn_registrar_documento(v_caso, 'GRUPO DUPLO', 'data-base', '2024-12-31', 'MUTUOS', 0.96,
    'nome_arquivo', 'supabase_storage', '0194/mutuos-duplo-2024.pdf', 'MUTUOS DUPLO 2024.pdf', true, 'HASH-0194-26', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','DUPLO PARTICIPAÇÕES S.A. → DUPLO INDÚSTRIA LTDA.','valor_num','5000','unidade','milhar','periodo_coluna','Saldo devedor','confianca','0.96')
  ), 'N2');
  v_r := fn_registrar_documento(v_caso, 'GRUPO DUPLO', 'data-base', '2025-12-31', 'MUTUOS', 0.96,
    'nome_arquivo', 'supabase_storage', '0194/mutuos-duplo-2025.pdf', 'MUTUOS DUPLO 2025.pdf', true, 'HASH-0194-27', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','DUPLO PARTICIPAÇÕES S.A. → DUPLO INDÚSTRIA LTDA.','valor_num','6700','unidade','milhar','periodo_coluna','Saldo devedor','confianca','0.96')
  ), 'N2');

  -- Balanços: 2024 (5.000 = 5.000) e 2025 (7.000 x 7.000, mas a planilha
  -- de 2025 erra para 6.700 — a divergência que este teste isola).
  v_r := fn_registrar_documento(v_caso, 'DUPLO PARTICIPAÇÕES S.A.', 'anual', '2024', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-duplo-part-2024.pdf', 'BP DUPLO PART 2024.pdf', true, 'HASH-0194-28', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a receber - partes relacionadas','valor_num','5000','unidade','milhar','periodo_coluna','2024','confianca','0.97')
  ), 'N2');
  v_r := fn_registrar_documento(v_caso, 'DUPLO INDÚSTRIA LTDA.', 'anual', '2024', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-duplo-ind-2024.pdf', 'BP DUPLO IND 2024.pdf', true, 'HASH-0194-29', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a pagar - partes relacionadas','valor_num','5000','unidade','milhar','periodo_coluna','2024','confianca','0.97')
  ), 'N2');
  v_r := fn_registrar_documento(v_caso, 'DUPLO PARTICIPAÇÕES S.A.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-duplo-part-2025.pdf', 'BP DUPLO PART 2025.pdf', true, 'HASH-0194-30', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a receber - partes relacionadas','valor_num','7000','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');
  v_r := fn_registrar_documento(v_caso, 'DUPLO INDÚSTRIA LTDA.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-duplo-ind-2025.pdf', 'BP DUPLO IND 2025.pdf', true, 'HASH-0194-31', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a pagar - partes relacionadas','valor_num','7000','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');

  v_per_consulta := fn_upsert_periodo(v_caso, 'multi', '24,25');
  v_r := fn_reconciliar_mutuos(v_caso, v_per_consulta);
  select precondicoes_ok, resultado, motivo_precondicao, divergencia_abs
    into v_ok, v_res, v_motivo, v_n
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0194(v_ok and v_res = 'zona_cinzenta' and v_motivo is null,
    'achado 3: as DUAS planilhas casam cada uma com o SEU ano — a checagem conclui (não documento_ausente/sem_periodo_par)',
    format('precondicoes_ok=%s resultado=%s motivo=%s', v_ok, v_res, v_motivo));
  perform pg_temp.teste_assert_0194(v_n between 295000 and 305000,
    'e a divergência é a de 2025 (7.000 x 6.700 = 300 mil), sem contaminar 2024', format('divergencia_abs=%s', v_n));

  select descricao into v_desc from pendencia
    where caso_id = v_caso and motivo = 'reconciliacao:mutuos_planilha_vs_balanco' and estado <> 'resolvida';
  perform pg_temp.teste_assert_0194(v_desc like '%2024%confere%' and v_desc like '%2025%',
    'e o texto nomeia os DOIS anos, com 2024 conferindo', left(v_desc, 400));
end $$;

-- =============================================================================
-- 9. ACHADO 1, ESTENDIDO (acompanhamento de 28/09/2026, tarde — MEDIDO em
-- produção só-leitura, "Teste 00"/2023: lado A saía 1,1 mi contra 33,3 mi
-- nos casos irmãos). Causa: um documento SEM `periodo_coluna` (retrato/anual
-- de UM ano) tinha suas linhas contadas para QUALQUER `v_ano`, não só o seu
-- próprio — `fn_coluna_periodo_do_ano(...) is null` passava sem checar se o
-- PERÍODO DO DOCUMENTO ancora o ano perguntado. Arranjo real: uma entidade
-- cujo ÚNICO balanço é "anual 2025" (sem coluna de ano) consultada em 2023 —
-- a linha dela não pode entrar na soma de 2023.
-- =============================================================================
do $$
declare
  v_caso uuid;
  v_r    jsonb;
  v_per_consulta uuid;
  v_ok   boolean;
  v_res  text;
  v_motivo text;
  v_num  numeric;
begin
  raise notice '--- 9. achado 1 estendido: balanço "anual 2025" sem coluna não conta para 2023 ---';
  v_caso := (fn_upsert_caso('0194: balanço de um ano só não vaza para outro ano'))::uuid;

  -- SÓ2025 PARTICIPAÇÕES: o ÚNICO balanço é "anual 2025", SEM coluna de ano
  -- (documento de um ano só) — não existe candidato nenhum para 2023.
  v_r := fn_registrar_documento(v_caso, 'SO2025 PARTICIPACOES S.A.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-so2025-part.pdf', 'BP SO2025 PART.pdf', true, 'HASH-0194-40', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a receber - partes relacionadas','valor_num','9000','unidade','milhar','confianca','0.97')
  ), 'N2');

  -- SÓ2025 CONTROLADA: tem um balanço PRÓPRIO de 2023 (passivo 3.000) E outro
  -- de 2025 (passivo 9.000, espelha a participações). O de 2023 é o que deve
  -- responder por 2023 — nunca o "anual 2025" da outra entidade.
  v_r := fn_registrar_documento(v_caso, 'SO2025 CONTROLADA LTDA.', 'anual', '2023', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-so2025-contr-2023.pdf', 'BP SO2025 CONTR 2023.pdf', true, 'HASH-0194-41', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a pagar - partes relacionadas','valor_num','3000','unidade','milhar','confianca','0.97')
  ), 'N2');
  v_r := fn_registrar_documento(v_caso, 'SO2025 CONTROLADA LTDA.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-so2025-contr-2025.pdf', 'BP SO2025 CONTR 2025.pdf', true, 'HASH-0194-42', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a pagar - partes relacionadas','valor_num','9000','unidade','milhar','confianca','0.97')
  ), 'N2');

  -- Planilhas-retrato: 2023 (3.000, só o passivo real) e 2025 (9.000, os
  -- dois lados se espelham).
  v_r := fn_registrar_documento(v_caso, 'GRUPO SO2025', 'data-base', '2023-12-31', 'MUTUOS', 0.96,
    'nome_arquivo', 'supabase_storage', '0194/mutuos-so2025-2023.pdf', 'MUTUOS SO2025 2023.pdf', true, 'HASH-0194-43', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','SO2025 PARTICIPACOES S.A. -> SO2025 CONTROLADA LTDA.','valor_num','3000','unidade','milhar','periodo_coluna','Saldo devedor','confianca','0.96')
  ), 'N2');
  v_r := fn_registrar_documento(v_caso, 'GRUPO SO2025', 'data-base', '2025-12-31', 'MUTUOS', 0.96,
    'nome_arquivo', 'supabase_storage', '0194/mutuos-so2025-2025.pdf', 'MUTUOS SO2025 2025.pdf', true, 'HASH-0194-44', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','SO2025 PARTICIPACOES S.A. -> SO2025 CONTROLADA LTDA.','valor_num','9000','unidade','milhar','periodo_coluna','Saldo devedor','confianca','0.96')
  ), 'N2');

  v_per_consulta := fn_upsert_periodo(v_caso, 'multi', '23,25');
  v_r := fn_reconciliar_mutuos(v_caso, v_per_consulta);
  select precondicoes_ok, resultado, motivo_precondicao, divergencia_abs
    into v_ok, v_res, v_motivo, v_num
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;

  -- Se o "anual 2025" da SÓ2025 PARTICIPAÇÕES vazasse para 2023 (o defeito),
  -- 2023 sairia com os DOIS lados (9.000 ativo vazado + 3.000 passivo real)
  -- e NÃO se espelhando (diferença de 6.000) — zona_cinzenta na comparação
  -- dos BALANÇOS, planilha nem comparada. Corrigido: 2023 tem só o passivo
  -- real (3.000, n_lados=1) contra a planilha de 2023 (3.000) — ok; 2025
  -- também fecha (9.000 = 9.000) — ok nos dois anos, sem divergência nenhuma.
  perform pg_temp.teste_assert_0194(v_ok and v_res = 'ok' and v_motivo is null,
    'achado 1 estendido: o balanço "anual 2025" sem coluna NÃO vaza para 2023 — os dois anos concluem ok',
    format('precondicoes_ok=%s resultado=%s motivo=%s divergencia_abs=%s', v_ok, v_res, v_motivo, v_num));

  select count(*) into v_num from pendencia
    where caso_id = v_caso and motivo = 'reconciliacao:mutuos_planilha_vs_balanco' and estado <> 'resolvida';
  perform pg_temp.teste_assert_0194(v_num = 0,
    'e SEM pendência nenhuma (nem a falsa zona_cinzenta de "balanços que não se espelham")',
    format('%s pendência(s)', v_num));
end $$;

-- =============================================================================
do $$
declare
  v_n int;
begin
  select case when is_called then last_value else 0 end into v_n from pg_temp._falhas_0194;
  if v_n > 0 then
    raise exception 'FALHOU: % assert(s) da 0194 reprovaram — ver as linhas FALHOU acima', v_n;
  end if;
  raise notice 'TODOS OS TESTES DA 0194 PASSARAM';
end $$;

rollback;
