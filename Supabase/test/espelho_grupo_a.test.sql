-- Testes do GRUPO A da revisão da 0195 (Supabase/migrations/0195_o_espelho_que_lia_o_balanco_de_outro_ano.sql).
-- Rodar via Supabase/test/run.sh.
--
-- O QUE CADA FIXTURE PROVA (regra 4 — nenhuma finge ser produção):
--
--   1. FACE + NOTA. Reproduz o ARRANJO medido em produção (30/09/2026, só-leitura): o
--      doc 2f17a7ba (Varejo) traz "Mútuos a pagar - controladora" na face (ordem 38, sem
--      seção) E na nota "Partes Relacionadas" (ordem 62), com o MESMO valor e a MESMA coluna.
--      Os NÚMEROS são inventados (3.900 nos dois lugares, contra uma planilha de 3.900) — o
--      que a fixture prova é o COMPORTAMENTO: a mesma conta lida em dois lugares conta UMA
--      vez. Ela NÃO prova que 409/890 mil de produção fecham: isso foi medido à parte.
--      O NEGATIVO (o mesmo rótulo com valor DIFERENTE na nota) prova que a deduplicação não
--      engole uma segunda posição.
--   2. EMPATE DE criado_em. Dois documentos da mesma entidade, mesmo tipo, mesmo período-ano e
--      `criado_em` IDÊNTICO (forçado por update — em produção são 44 grupos / 160 documentos /
--      14 casos que empatam). Um espelha o outro lado, o outro não. O teste roda as DUAS
--      atribuições (o espelho no documento de MENOR id e no de MAIOR id) e exige que a resposta
--      siga o id — a escolha é função do dado (vence o menor id), nunca da ordem física das
--      linhas, que é o que decidia antes (medido: com o espelho no menor id o banco antigo
--      respondia zona_cinzenta, e ok com ele no maior).
--   3. LINHA ≠ 0 SEM CONTRAPARTE. Um documento mais novo só com "Caixa" (≠ 0, sem
--      contraparte nem lado) não pode vencer o mais antigo que TEM a linha intragrupo.
--
-- O ASSERT NÃO PARA NO PRIMEIRO ERRO: anota e segue, e o bloco final reprova com a CONTAGEM
-- (regra 2).

begin;

create temp sequence _falhas_grupo_a;

create or replace function pg_temp.teste_assert_ga(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  else
    raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
    perform nextval('pg_temp._falhas_grupo_a');
  end if;
end $$;

-- =============================================================================
-- 1. FACE + NOTA (achado 1, CRÍTICO)
-- =============================================================================
do $$
declare
  v_caso uuid; v_r jsonb; v_per uuid; v_res text; v_div numeric; v_ok boolean;
begin
  raise notice '--- 1. a mesma conta na face e na nota conta UMA vez ---';
  v_caso := (fn_upsert_caso('GA1: mútuo repetido na face e na nota'))::uuid;

  v_r := fn_registrar_documento(v_caso, 'GA1 HOLDING', 'data-base', '2025-12-31', 'MUTUOS', 0.96,
    'nome_arquivo', 'supabase_storage', 'ga/mutuos.pdf', 'MUTUOS.pdf', true, 'HASH-GA-1', 'ok');
  v_per := (select periodo_id from documento where id = (v_r->>'documento_id')::uuid);
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','GA1 HOLDING → GA1 VAREJO','valor_num','3900','unidade','milhar','periodo_coluna','Saldo devedor','confianca','0.96'),
    jsonb_build_object('ordem',1,'chave','TOTAL','valor_num','3900','unidade','milhar','periodo_coluna','Saldo devedor','confianca','0.96')
  ), 'N2');

  v_r := fn_registrar_documento(v_caso, 'GA1 HOLDING', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', 'ga/bp-holding.pdf', 'BP HOLDING.pdf', true, 'HASH-GA-2', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a receber - controlada','valor_num','3900','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');

  -- O balanço do VAREJO: a mesma conta na face (sem seção) e na nota.
  v_r := fn_registrar_documento(v_caso, 'GA1 VAREJO', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', 'ga/bp-varejo.pdf', 'BP VAREJO.pdf', true, 'HASH-GA-3', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',38,'chave','Mútuos a pagar - controladora','valor_num','3900','unidade','milhar','periodo_coluna','2025','confianca','0.97'),
    jsonb_build_object('ordem',62,'chave','Mútuos a pagar - controladora','secao','Partes Relacionadas','valor_num','3900','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');

  v_r := fn_reconciliar_mutuos(v_caso, v_per);
  select resultado, divergencia_abs, precondicoes_ok into v_res, v_div, v_ok
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_ga(v_ok and v_res = 'ok',
    'face + nota com o mesmo valor: os dois lados fecham (3.900 = 3.900), ok',
    format('resultado=%s divergencia=%s', v_res, v_div));
  perform pg_temp.teste_assert_ga(coalesce(v_div, 0) = 0,
    'e a divergência é ZERO (não 3.900 mil fabricados pela duplicata)', format('divergencia=%s', v_div));

  -- NEGATIVO: a nota traz o MESMO rótulo com valor DIFERENTE (outra posição, 1.000):
  -- não é duplicata e tem de continuar somando — passivo 4.900 contra 3.900.
  update campo_extraido ce set valor_num = 1000
    from documento_versao dv join documento d on d.id = dv.documento_id
   where ce.documento_versao_id = dv.id and d.caso_id = v_caso and ce.ordem = 62;
  v_r := fn_reconciliar_mutuos(v_caso, v_per);
  select resultado, divergencia_abs into v_res, v_div
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_ga(v_res = 'zona_cinzenta' and v_div between 999000 and 1001000,
    'NEGATIVO: mesmo rótulo com valor DIFERENTE na nota é outra posição e soma (4.900 x 3.900)',
    format('resultado=%s divergencia=%s', v_res, v_div));
end $$;

-- =============================================================================
-- 2. EMPATE DE criado_em (achado 2, ALTO) — as duas funções.
--    Par de empresas P → Q. Q tem DOIS balanços BALANCO de 2025, com criado_em idêntico:
--    um espelha P (9.000), o outro não (1.000). Rodado com o espelho no documento de MENOR
--    id (caso a) e de MAIOR id (caso b): a resposta tem de seguir o id (vence o menor), não a ordem física.
-- =============================================================================
create or replace function pg_temp.monta_empate(p_nome text, p_espelho_no_menor_id boolean, p_mutuo boolean)
returns table(v_caso uuid, v_per uuid) language plpgsql as $$
declare
  v_c uuid; v_r jsonb; v_p uuid; v_d1 uuid; v_d2 uuid; v_menor uuid; v_maior uuid;
  v_chave_q text := case when p_mutuo then 'Mútuos a pagar - partes relacionadas'
                         else 'Fornecedores intragrupo - ' || p_nome || ' P' end;
  v_chave_p text := case when p_mutuo then 'Mútuos a receber - partes relacionadas'
                         else 'Contas a receber intragrupo - ' || p_nome || ' Q' end;
begin
  v_c := (fn_upsert_caso('GA2 ' || p_nome))::uuid;
  if p_mutuo then
    v_r := fn_registrar_documento(v_c, p_nome || ' P', 'data-base', '2025-12-31', 'MUTUOS', 0.96,
      'nome_arquivo', 'supabase_storage', 'ga/' || p_nome || '-mut.pdf', 'MUT.pdf', true, 'HASH-GA-' || p_nome || '-m', 'ok');
    v_p := (select periodo_id from documento where id = (v_r->>'documento_id')::uuid);
    perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
      jsonb_build_object('ordem',0,'chave',p_nome || ' P → ' || p_nome || ' Q','valor_num','9000','unidade','milhar','periodo_coluna','Saldo devedor','confianca','0.96')
    ), 'N2');
  end if;
  v_r := fn_registrar_documento(v_c, p_nome || ' P', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', 'ga/' || p_nome || '-p.pdf', 'P.pdf', true, 'HASH-GA-' || p_nome || '-p', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave',v_chave_p,'valor_num','9000','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');
  if not p_mutuo then v_p := (select periodo_id from documento where id = (v_r->>'documento_id')::uuid); end if;

  -- Os dois balanços de Q: períodos diferentes que ancoram o mesmo ano (2025) para serem
  -- dois documentos, não duas versões do mesmo.
  v_r := fn_registrar_documento(v_c, p_nome || ' Q', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', 'ga/' || p_nome || '-q1.pdf', 'Q1.pdf', true, 'HASH-GA-' || p_nome || '-q1', 'ok');
  v_d1 := (v_r->>'documento_id')::uuid;
  v_r := fn_registrar_documento(v_c, p_nome || ' Q', 'data-base', '2025-12-31', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', 'ga/' || p_nome || '-q2.pdf', 'Q2.pdf', true, 'HASH-GA-' || p_nome || '-q2', 'ok');
  v_d2 := (v_r->>'documento_id')::uuid;
  update documento set criado_em = timestamptz '2026-01-01 00:00:00+00' where id in (v_d1, v_d2);

  v_menor := least(v_d1, v_d2); v_maior := greatest(v_d1, v_d2);
  perform fn_registrar_campos_extraidos(fn_versao_atual(case when p_espelho_no_menor_id then v_menor else v_maior end),
    jsonb_build_array(jsonb_build_object('ordem',0,'chave',v_chave_q,'valor_num','9000','unidade','milhar','periodo_coluna','2025','confianca','0.97')), 'N2');
  perform fn_registrar_campos_extraidos(fn_versao_atual(case when p_espelho_no_menor_id then v_maior else v_menor end),
    jsonb_build_array(jsonb_build_object('ordem',0,'chave',v_chave_q,'valor_num','1000','unidade','milhar','periodo_coluna','2025','confianca','0.97')), 'N2');
  v_caso := v_c; v_per := v_p; return next;
end $$;

do $$
declare
  v_caso uuid; v_per uuid; v_r jsonb; v_a text; v_b text; v_n int;
begin
  raise notice '--- 2. empate de criado_em: o empate se resolve pelo id, não pela ordem física ---';
  -- INTRAGRUPO. Empate com o espelho no menor id / no maior id.
  select * into v_caso, v_per from pg_temp.monta_empate('IGA', true, false);
  select count(*) into v_n from documento where caso_id = v_caso and criado_em = timestamptz '2026-01-01 00:00:00+00';
  perform pg_temp.teste_assert_ga(v_n = 2, 'intragrupo: o empate de criado_em foi de fato montado (2 documentos)', format('%s', v_n));
  v_r := fn_reconciliar_intragrupo(v_caso, v_per);
  select resultado into v_a from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  select * into v_caso, v_per from pg_temp.monta_empate('IGB', false, false);
  v_r := fn_reconciliar_intragrupo(v_caso, v_per);
  select resultado into v_b from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_ga(v_a = 'ok' and v_b = 'zona_cinzenta',
    'intragrupo: no empate de criado_em vence o documento de MENOR id (espelho nele: ok; só no outro: zona_cinzenta)',
    format('menor_id=%s maior_id=%s', v_a, v_b));

  -- MÚTUOS.
  select * into v_caso, v_per from pg_temp.monta_empate('MGA', true, true);
  v_r := fn_reconciliar_mutuos(v_caso, v_per);
  select resultado into v_a from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  select * into v_caso, v_per from pg_temp.monta_empate('MGB', false, true);
  v_r := fn_reconciliar_mutuos(v_caso, v_per);
  select resultado into v_b from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_ga(v_a = 'ok' and v_b = 'zona_cinzenta',
    'mútuos: no empate de criado_em vence o documento de MENOR id (espelho nele: ok; só no outro: zona_cinzenta)',
    format('menor_id=%s maior_id=%s', v_a, v_b));
end $$;

-- =============================================================================
-- 3. LINHA ≠ 0 SEM CONTRAPARTE (achado 3, MÉDIO)
--    Q tem dois balanços de 2025. O MAIS ANTIGO traz o espelho (9.000 a pagar a P). O MAIS
--    NOVO traz só "Caixa" (≠ 0, sem contraparte nem lado). Quem vence é o que tem dado
--    intragrupo — não o mais novo.
-- =============================================================================
do $$
declare
  v_caso uuid; v_r jsonb; v_per uuid; v_d1 uuid; v_d2 uuid; v_res text; v_n text;
begin
  raise notice '--- 3. linha diferente de zero sem contraparte não conta como dado intragrupo ---';
  v_caso := (fn_upsert_caso('GA3: caixa não é dado intragrupo'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'GA3 P', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', 'ga/ga3-p.pdf', 'P.pdf', true, 'HASH-GA-31', 'ok');
  v_per := (select periodo_id from documento where id = (v_r->>'documento_id')::uuid);
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Contas a receber intragrupo - GA3 Q','valor_num','9000','unidade','milhar','periodo_coluna','2025','confianca','0.97')), 'N2');

  v_r := fn_registrar_documento(v_caso, 'GA3 Q', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', 'ga/ga3-q1.pdf', 'Q1.pdf', true, 'HASH-GA-32', 'ok');
  v_d1 := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Fornecedores intragrupo - GA3 P','valor_num','9000','unidade','milhar','periodo_coluna','2025','confianca','0.97')), 'N2');
  v_r := fn_registrar_documento(v_caso, 'GA3 Q', 'data-base', '2025-12-31', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', 'ga/ga3-q2.pdf', 'Q2.pdf', true, 'HASH-GA-33', 'ok');
  v_d2 := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Caixa e equivalentes de caixa','valor_num','500','unidade','milhar','periodo_coluna','2025','confianca','0.97')), 'N2');
  update documento set criado_em = timestamptz '2026-01-01 00:00:00+00' where id = v_d1;
  update documento set criado_em = timestamptz '2026-02-01 00:00:00+00' where id = v_d2;

  v_r := fn_reconciliar_intragrupo(v_caso, v_per);
  select resultado, materialidade->>'pares_conferidos' into v_res, v_n
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_ga(v_res = 'ok',
    'o balanço mais novo só com Caixa não vence o mais antigo que tem o espelho: conclui ok',
    format('resultado=%s', v_res));
  perform pg_temp.teste_assert_ga(v_n = '1',
    'e o par é conferido (1), não perdido por ter escolhido o documento sem a linha',
    format('pares_conferidos=%s', v_n));
end $$;

-- =============================================================================
do $$
declare
  v_n int;
begin
  select case when is_called then last_value else 0 end into v_n from pg_temp._falhas_grupo_a;
  if v_n > 0 then
    raise exception 'FALHOU: % assert(s) do grupo A da 0195 reprovaram — ver as linhas FALHOU acima', v_n;
  end if;
  raise notice 'TODOS OS TESTES DO GRUPO A DA 0195 PASSARAM';
end $$;

rollback;
