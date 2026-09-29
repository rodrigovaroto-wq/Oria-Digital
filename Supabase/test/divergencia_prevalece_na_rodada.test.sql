-- Testes de `fn_registrar_reconciliacao` / `fn_reconciliar_caso` (0192).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO TRAVA: dentro da MESMA rodada (mesma transação —
-- `fn_reconciliar_caso`, 0152, roda inteira numa chamada só), duas checagens
-- do mesmo caso/tipo/entidade com períodos COMPATÍVEIS (não iguais — Balanço
-- `multi` "24,25" e Balanço `anual` "12M25", {2024,2025} ∩ {2025} ≠ ∅) caem na
-- MESMA pendência por período compatível (regra desde a 0023). Antes da 0192,
-- a ORDEM em que as duas chegavam decidia se a divergência de um período
-- terminava ABERTA ou RESOLVIDA pelo `ok` do outro — medido em produção
-- (25/09/2026): teste v33/v35, `caixa_bp_fluxo`, divergência de 2024
-- (4.340.000) criada e resolvida no MESMO instante pelo `ok` de 2025.
--
-- CENÁRIOS 1 e 2 VÊM PELA COSTURA REAL — fn_upsert_caso, fn_registrar_documento,
-- fn_registrar_campos_extraidos, fn_upsert_periodo e a própria
-- fn_reconciliar_caixa_bp_fluxo (0031/0188) — chamada DUAS VEZES na MESMA
-- transação (um bloco `do $$`), uma vez por período, nas duas ordens possíveis.
-- Isso é o que prova que a ordem deixou de decidir o desfecho: se o teste
-- escrevesse o estado final à mão, provaria só que o UPDATE funciona.
--
-- CENÁRIO 3 é o retry que a 0152 DESENHOU e que esta migration NÃO MUDA:
-- pré-condição seguida de `ok` da MESMA chave continua fechando sem deixar
-- pendência — a guarda só protege uma divergência CONCLUÍDA, não pré-condição.
--
-- CENÁRIO 4 é a rodada SEGUINTE (uma transação NOVA — outro bloco `do $$`,
-- `now()` diferente): com a divergência corrigida, a reconciliação resolve a
-- pendência normalmente — a guarda não trava resolução legítima entre rodadas.

\set ON_ERROR_STOP on

create or replace function teste_assert_divirmana(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- =============================================================================
-- Fixture compartilhada: um caso com uma entidade, um Balanço `multi` "24,25"
-- (Caixa 2024 = 10000, Caixa 2025 = 6000) e um Fluxo de Caixa `multi` "24,25"
-- (Saldo final 2024 = 5660 — diferença de 4340 —, Saldo final 2025 = 6000,
-- confere). `fn_upsert_periodo` cria, à parte, o período `anual` "12M25"
-- (canônico "2025" — o MESMO ano do multi, período DIFERENTE do multi, ver
-- 0030): fn_documento_balanco/fn_documento_por_tipo o acham pelos MESMOS
-- documentos, por compatibilidade (fn_periodos_compativeis), e
-- fn_anos_alvo('anual','12M25') = {2025} só confere o ano que já bate.
-- =============================================================================
create or replace function teste_divirmana_montar_fixture(p_nome_caso text, out o_caso uuid,
  out o_ent uuid, out o_per_multi uuid, out o_per_anual uuid)
language plpgsql as $$
declare
  v_r      jsonb;
  v_ver_bp uuid;
  v_ver_fx uuid;
  v_doc_bp uuid;
begin
  o_caso := (fn_upsert_caso(p_nome_caso))::uuid;

  v_r := fn_registrar_documento(o_caso, 'Divergencia Irma Ltda.', 'multi', '24,25', 'BALANCO', 0.95,
    'nome_arquivo', 'supabase_storage', 'mp/0192-bp.pdf', 'BP DIVERGENCIA IRMA.pdf', true,
    'HASH-0192-BP-' || p_nome_caso, 'ok');
  v_ver_bp := (v_r->>'documento_versao_id')::uuid;
  v_doc_bp := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver_bp, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Caixa e equivalentes de caixa','valor_num','10000',
      'periodo_coluna','2024','confianca','0.97'),
    jsonb_build_object('ordem',1,'chave','Caixa e equivalentes de caixa','valor_num','6000',
      'periodo_coluna','2025','confianca','0.97')
  ), 'N2');

  v_r := fn_registrar_documento(o_caso, 'Divergencia Irma Ltda.', 'multi', '24,25', 'FLUXO_CAIXA', 0.95,
    'nome_arquivo', 'supabase_storage', 'mp/0192-fx.pdf', 'DFC DIVERGENCIA IRMA.pdf', true,
    'HASH-0192-FX-' || p_nome_caso, 'ok');
  v_ver_fx := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver_fx, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Saldo final de caixa','valor_num','5660',
      'periodo_coluna','2024','confianca','0.97'),
    jsonb_build_object('ordem',1,'chave','Saldo final de caixa','valor_num','6000',
      'periodo_coluna','2025','confianca','0.97')
  ), 'N2');

  select entidade_id, periodo_id into o_ent, o_per_multi from documento where id = v_doc_bp;
  o_per_anual := fn_upsert_periodo(o_caso, 'anual', '12M25');
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid; v_ent uuid; v_per_multi uuid; v_per_anual uuid;
  v_f    record;
  v_r    jsonb;
  v_n_aberta int;
  v_tipo     text;
  v_desc     text;
begin
  raise notice '--- 1. DIVERGENTE primeiro, OK depois (mesma rodada) — a ordem do teste v33 ---';
  v_f := teste_divirmana_montar_fixture('0192: divergente antes do ok');
  v_caso := v_f.o_caso; v_ent := v_f.o_ent; v_per_multi := v_f.o_per_multi; v_per_anual := v_f.o_per_anual;

  -- período multi "24,25": 2024 diverge (4340), 2025 confere — resultado
  -- agregado 'divergente'. Chamada DIRETA (força a ordem — o objetivo do
  -- teste é a ORDEM DE CHAMADA, não a ordem em que fn_reconciliar_caso visita
  -- as chaves, que é outro portão, o do CENÁRIO da 0192 na migration).
  v_r := fn_reconciliar_caixa_bp_fluxo(v_caso, v_ent, v_per_multi);
  perform teste_assert_divirmana(v_r->>'resultado' = 'divergente',
    'passo 1: período multi "24,25" conclui divergente', coalesce(v_r->>'resultado', '(null)'));

  -- período anual "12M25" (mesmo caso/entidade, período COMPATÍVEL, DIFERENTE
  -- id): só o ano 2025 é conferido, que bate — 'ok'.
  v_r := fn_reconciliar_caixa_bp_fluxo(v_caso, v_ent, v_per_anual);
  perform teste_assert_divirmana(v_r->>'resultado' = 'ok',
    'passo 2: período anual "12M25" (compatível, ano 2025) conclui ok', coalesce(v_r->>'resultado', '(null)'));

  select count(*) into v_n_aberta from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida';
  perform teste_assert_divirmana(v_n_aberta = 1,
    '0192: o ok de 2025 NÃO resolve a divergência de 2024 — continua exatamente 1 pendência aberta',
    format('%s pendência(s) aberta(s) — antes da 0192 o ok apagava a divergência (medido em produção, '
           'v33/v35, 25/09/2026)', v_n_aberta));

  select tipo, descricao into v_tipo, v_desc from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida';
  perform teste_assert_divirmana(v_tipo = 'divergencia_reconciliacao',
    'e o tipo continua divergencia_reconciliacao (não foi rebaixada a pré-condição)', coalesce(v_tipo,'(null)'));
  perform teste_assert_divirmana(v_desc like '%4340%' or v_desc like '%diferença%',
    'e a descrição continua a da DIVERGÊNCIA (o ok não trocou o texto pelo dele)', coalesce(v_desc, '(null)'));
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid; v_ent uuid; v_per_multi uuid; v_per_anual uuid;
  v_f    record;
  v_r    jsonb;
  v_n_aberta int;
  v_tipo     text;
begin
  raise notice '--- 2. OK primeiro, DIVERGENTE depois (mesma rodada) — a ordem do teste AMOBELEZA ---';
  v_f := teste_divirmana_montar_fixture('0192: ok antes do divergente');
  v_caso := v_f.o_caso; v_ent := v_f.o_ent; v_per_multi := v_f.o_per_multi; v_per_anual := v_f.o_per_anual;

  v_r := fn_reconciliar_caixa_bp_fluxo(v_caso, v_ent, v_per_anual);
  perform teste_assert_divirmana(v_r->>'resultado' = 'ok',
    'passo 1: período anual "12M25" conclui ok', coalesce(v_r->>'resultado', '(null)'));

  v_r := fn_reconciliar_caixa_bp_fluxo(v_caso, v_ent, v_per_multi);
  perform teste_assert_divirmana(v_r->>'resultado' = 'divergente',
    'passo 2: período multi "24,25" conclui divergente', coalesce(v_r->>'resultado', '(null)'));

  select count(*) into v_n_aberta from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida';
  perform teste_assert_divirmana(v_n_aberta = 1,
    'nesta ordem já era o comportamento certo (AMOBELEZA) — continua 1 pendência aberta',
    format('%s pendência(s) aberta(s)', v_n_aberta));

  select tipo into v_tipo from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida';
  perform teste_assert_divirmana(v_tipo = 'divergencia_reconciliacao',
    'e é a pendência da DIVERGÊNCIA (divergencia_reconciliacao) — o mesmo desfecho que o bloco 1 '
    'exige na ordem inversa; os dois juntos são a invariância à ordem', coalesce(v_tipo, '(null)'));
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid;
  v_r    jsonb;
  v_n    int;
begin
  raise notice '--- 3. RETRY (0152) NÃO MUDA: pré-condição seguida de ok da MESMA chave fecha sem pendência ---';
  v_caso := (fn_upsert_caso('0192: retry de precondicao continua fechando'))::uuid;

  -- Mesma chave (mesmo período, sem período irmão nenhum): pré-condição abre,
  -- ok da MESMA reconciliação fecha — não há divergência CONCORRENTE nenhuma
  -- na rodada, então a guarda da 0192 não dispara.
  v_r := fn_registrar_reconciliacao(v_caso, null, null, 'teste_retry_0192', 'A', null, null, null,
    'precondicao_nao_satisfeita', null, null, null, 'sem par ainda — primeira tentativa da chave');
  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:teste_retry_0192' and estado <> 'resolvida';
  perform teste_assert_divirmana(v_n = 1, 'pré-condição abre pendência (comportamento de sempre)',
    format('%s pendência(s)', v_n));

  v_r := fn_registrar_reconciliacao(v_caso, null, null, 'teste_retry_0192', 'A', null, null, null,
    'ok', null, null, null, 'segunda tentativa da MESMA chave: concluiu');
  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:teste_retry_0192' and estado <> 'resolvida';
  perform teste_assert_divirmana(v_n = 0,
    '0192 NÃO MUDA o retry desenhado pela 0152: ok da mesma chave continua fechando sem pendência',
    format('%s pendência(s) aberta(s) — devia ser 0', v_n));
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid; v_ent uuid; v_per_multi uuid; v_per_anual uuid;
  v_f    record;
  v_r    jsonb;
  v_n_aberta int;
  v_ver_fx   uuid;
begin
  raise notice '--- 4. RODADA SEGUINTE (transação nova): divergência corrigida resolve normalmente ---';
  v_f := teste_divirmana_montar_fixture('0192: rodada seguinte resolve');
  v_caso := v_f.o_caso; v_ent := v_f.o_ent; v_per_multi := v_f.o_per_multi; v_per_anual := v_f.o_per_anual;

  v_r := fn_reconciliar_caixa_bp_fluxo(v_caso, v_ent, v_per_multi);
  perform teste_assert_divirmana(v_r->>'resultado' = 'divergente',
    'rodada 1: período multi "24,25" conclui divergente', coalesce(v_r->>'resultado', '(null)'));

  select count(*) into v_n_aberta from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida';
  perform teste_assert_divirmana(v_n_aberta = 1, 'rodada 1: pendência aberta', format('%s', v_n_aberta));
end $$;

-- Corrige o Saldo final de 2024 da DFC para bater com o Caixa do Balanço (a
-- reextração que resolveria o arranjo real), NUMA transação separada — o
-- `do $$` seguinte é a "rodada seguinte" de verdade, com `now()` diferente.
do $$
declare
  v_caso uuid; v_ent uuid; v_per_multi uuid;
  v_ver_fx uuid;
  v_r      jsonb;
  v_n_aberta int;
begin
  select id into v_caso from caso where nome = '0192: rodada seguinte resolve';
  select entidade_id, periodo_id into v_ent, v_per_multi from documento
   where caso_id = v_caso and tipo_taxonomia = 'BALANCO';

  select fn_versao_atual(id) into v_ver_fx from documento
   where caso_id = v_caso and tipo_taxonomia = 'FLUXO_CAIXA';
  update campo_extraido set valor_num = '10000'
   where documento_versao_id = v_ver_fx and periodo_coluna = '2024' and chave = 'Saldo final de caixa';

  v_r := fn_reconciliar_caixa_bp_fluxo(v_caso, v_ent, v_per_multi);
  perform teste_assert_divirmana(v_r->>'resultado' = 'ok',
    'rodada 2 (transação nova): com a divergência corrigida, o período multi conclui ok',
    coalesce(v_r->>'resultado', '(null)'));

  select count(*) into v_n_aberta from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida';
  perform teste_assert_divirmana(v_n_aberta = 0,
    'e a pendência resolve normalmente — a guarda da 0192 não trava resolução legítima entre rodadas',
    format('%s pendência(s) ainda aberta(s)', v_n_aberta));
end $$;

drop function teste_divirmana_montar_fixture(text);
drop function teste_assert_divirmana(boolean, text, text);
