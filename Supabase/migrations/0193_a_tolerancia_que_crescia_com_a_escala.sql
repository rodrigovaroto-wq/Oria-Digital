-- =============================================================================
-- 0193 — A TOLERÂNCIA QUE CRESCIA COM A ESCALA
--
-- O DEFEITO. A 0188 corrigiu, em `fn_reconciliar_despfin_dre_vs_divida`, a
-- tolerância absoluta que era `p_tolerancia_abs * fator_da_escala`: numa DRE
-- em 'milhar' os R$ 50.000 do default viravam R$ 50 MILHÕES, e qualquer
-- divergência abaixo disso saía "confere" (medido em produção, 22/09/2026: 1
-- despfin "ok" era falsa, R$ 12,4 mi de diferença). O corpo vigente na 0188
-- ficou com `v_tol := greatest(p_tolerancia_abs, abs(v_a) * p_tolerancia_pct)`
-- — `v_a`/`v_b` já estão em moeda BASE (`fn_valor_em_base`), e é ali que a
-- tolerância absoluta tem de estar.
--
-- O MESMO VÍCIO continuava, sem ninguém ter mexido desde a 0023, nas OUTRAS
-- DUAS checagens que multiplicam a tolerância absoluta pela escala:
--
--   fn_reconciliar_receita_dre_vs_faturamento (0023/0188:1234) — default
--     abs 50.000, pct 5%: `v_tol := greatest(p_tolerancia_abs *
--     coalesce(fn_fator_escala(v_unid_rec), 1), abs(v_a) * p_tolerancia_pct)`.
--   fn_reconciliar_caixa_bp_fluxo (0031/0188:773) — default abs 100, pct
--     0,5%: mesma forma, com `fn_fator_escala(v_caixa.unidade)`.
--
-- MEDIDO EM PRODUÇÃO (25/09/2026, SOMENTE LEITURA — recomputando cada linha
-- `resultado = 'ok'` a partir de `fonte_a`/`fonte_b`/`materialidade`, sem
-- escrever nada): receita, 30 `ok` (10 em milhar) — 0 viram divergência com a
-- tolerância na base, a pior chega a 4,75% (abaixo dos 5%, então continuaria
-- `ok` de qualquer forma); caixa, 33 `ok` (as 33 em milhar) — 0 viram
-- divergência, diferença zero em todas. **A correção é LATENTE: zero efeito
-- em produção hoje.** O risco é o mesmo da despfin — só ainda não se
-- materializou nestas duas —, e é isso, não um achado novo em produção, que
-- justifica corrigir agora: o vício é estrutural nas três funções que
-- multiplicam tolerância absoluta por fator de escala, e só uma delas tinha
-- sido corrigida.
--
-- Exemplo de ordem de grandeza (não é produção — ilustra por que o vício
-- importa mesmo com efeito zero hoje): uma DRE em 'milhar' com receita de
-- R$ 74 mi tem, com o `× fator`, um piso de tolerância de R$ 50 MILHÕES —
-- uma diferença de 30% sairia "confere". É o arranjo do bloco de teste
-- abaixo (sintético, regra 4 — não é fixture de bug de produção).
--
-- A CORREÇÃO. As DUAS funções, REEMITIDAS INTEIRAS a partir do corpo vigente
-- na 0188 (nunca `replace` de texto —
-- `.claude/memory/nunca-corrigir-funcao-por-replace.md`): a única mudança de
-- COMPORTAMENTO é a linha da tolerância, igual à que a 0188 já aplicou na
-- despfin. Nenhuma outra linha muda — os corpos são, de resto, byte a byte
-- os da 0188. As duas funções são chamadas SÓ posicionalmente (3 argumentos,
-- os defaults de tolerância nunca sobrescritos — conferido em
-- `Supabase/`, `N8N/`, `portal/src/`), então nenhum chamador muda.
--
-- INVARIANTE DURO: esta migration NÃO muda motivo_precondicao, o vocabulário
-- de resultado (`ok`/`zona_cinzenta`/`divergente`/`precondicao_nao_-
-- satisfeita`), nem qualquer texto fora da própria comparação numérica. Só a
-- tolerância aplicada quando as duas partes JÁ foram localizadas e a escala
-- JÁ é comparável.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): com `× fator` de volta em cada função
-- SEPARADAMENTE, os dois asserts que este arquivo acrescenta (um por função)
-- reprovam — contados sem parar no primeiro `raise`, ver
-- `Supabase/test/tolerancia_na_base.test.sql`. Nenhum assert de fixture
-- existente (`reconciliacao.test.sql`, `reconciliacao_do_lote.test.sql`,
-- `motivo_especifico.test.sql`, os fixtures do book-canastra/book-vertentes)
-- muda — medido rodando `Supabase/test/run.sh` antes e depois desta
-- migration.
--
-- REVISÃO DE FIDELIDADE (28/09/2026, achado MÉDIO, corrigido NO PRÓPRIO
-- arquivo — 0193 ainda não aplicada em produção). A tolerância na base,
-- sozinha, abre um segundo buraco em `fn_reconciliar_caixa_bp_fluxo`: o
-- ARREDONDAMENTO do próprio documento. Num Balanço/DFC em 'milhar', cada
-- número impresso já carrega até R$ 1.000 de arredondamento — duas linhas
-- corretas podem diferir em 1 unidade da escala sem que nada esteja errado.
-- Com caixa abaixo de R$ 200 mil, 0,5% de `abs(v_a)` fica ABAIXO de R$ 1.000
-- (a unidade da escala 'milhar'): uma DFC impressa "12" contra um Balanço
-- "11" sairia 'divergente' por puro arredondamento — Classe A, abre
-- pendência. MEDIDO EM PRODUÇÃO (28/09/2026, somente leitura): 0 casos hoje
-- (39 linhas de caixa em 'milhar', nenhuma com caixa abaixo de R$ 200 mil).
-- Correção LATENTE, mesmo raciocínio da árvore que já valia para a 0133
-- (tolerância de arredondamento em unidade do documento). CORREÇÃO: a
-- tolerância absoluta de `fn_reconciliar_caixa_bp_fluxo` ganha um terceiro
-- piso — 1 unidade da escala mais grossa dos dois lados (Balanço/DFC, cada
-- `fn_fator_escala` coalescido a 1), sem voltar ao `× fator` (que dava R$ 100
-- MIL): `greatest(p_tolerancia_abs, greatest(fn_fator_escala(unid. do BP),
-- fn_fator_escala(unid. da DFC)) coalescidos a 1, abs(v_a) * p_tolerancia_pct)`.
-- A receita (`fn_reconciliar_receita_dre_vs_faturamento`) NÃO ganha o mesmo
-- piso: com pct 5%, o piso percentual só cai abaixo de 1 unidade da escala
-- quando a receita é menor que R$ 20 mil em 'milhar' — irrelevante neste
-- domínio (nenhuma receita de mandato chega perto disso), então a função
-- fica como estava. MEDIÇÃO NÃO-VAZIA (regra 2): com o piso de
-- arredondamento removido, o assert do bloco 3 de
-- `Supabase/test/tolerancia_na_base.test.sql` reprova — contado junto com os
-- outros dois, sem parar no primeiro `raise`.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (1) fn_reconciliar_caixa_bp_fluxo — REEMITIDA INTEIRA (corpo vigente 0188:773).
-- Mudança única: a tolerância absoluta na base, não × fn_fator_escala.
-- -----------------------------------------------------------------------------
create or replace function fn_reconciliar_caixa_bp_fluxo(p_caso_id uuid, p_entidade_id uuid,
  p_periodo_id uuid, p_tolerancia_abs numeric default 100, p_tolerancia_pct numeric default 0.005)
returns jsonb
language plpgsql
as $$
declare
  v_doc_bp    uuid;
  v_doc_fx    uuid;
  v_ver_bp    uuid;
  v_ver_fx    uuid;
  v_col_ent   text;
  v_ano       int;
  v_col_per   text;
  v_caixa     campo_extraido;
  v_saldo     campo_extraido;
  v_motivo    text;
  v_a         numeric;
  v_b         numeric;
  v_div_abs   numeric;
  v_tol       numeric;
  v_resultado text := 'ok';
  v_partes    text[] := '{}';
  v_n         int := 0;
  v_pior_abs  numeric;
  v_pior_pct  numeric;
  v_fonte_a   jsonb;
  v_fonte_b   jsonb;
  -- 0188
  v_col_bp      text;
  v_motivos_ano text[] := '{}';
  v_motivo_ano  text;
  v_faltas      text[] := '{}';
  v_motivo_prec text;
begin
  v_doc_bp := fn_documento_balanco(p_caso_id, p_entidade_id, p_periodo_id);
  v_doc_fx := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'FLUXO_CAIXA');

  if v_doc_bp is null or v_doc_fx is null then
    -- Fato comum e legítimo: nem toda empresa do grupo entrega DFC. Quem cobra
    -- documento faltante é o checklist do Kit Básico, não a fila de revisão.
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'caixa_bp_fluxo', 'A', coalesce(v_doc_bp, v_doc_fx), null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      format('Sem par para reconciliar: %s não foi entregue para esta entidade/período.',
        case when v_doc_bp is null and v_doc_fx is null then 'Balanço e Fluxo de Caixa'
             when v_doc_bp is null then 'Balanço Patrimonial' else 'Fluxo de Caixa' end));
  end if;

  v_ver_bp  := fn_versao_atual(v_doc_bp);
  v_ver_fx  := fn_versao_atual(v_doc_fx);
  v_col_ent := fn_coluna_entidade(v_ver_bp, p_entidade_id);

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    v_col_per := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_ver_bp, v_ano) end;
    v_col_bp := v_col_per;

    -- Caixa no Balanço. "Disponível"/"Disponibilidades" é o rótulo mais comum em
    -- demonstração brasileira detalhada — a DFC do book chega a dizer, na nota,
    -- que o saldo final "confere com a rubrica Disponível do balanço".
    select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
      array['caixa', 'equivalentes'], array['circulante', 'fluxo', 'inicio', 'inicial'],
      v_col_ent, v_col_per);
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['disponibilidades'], array['circulante'], v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['disponivel'], array['circulante'], v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['caixa', 'bancos'], array['circulante'], v_col_ent, v_col_per);
    end if;
    -- 0031: as quatro tentativas acima olham SÓ `ce.chave`, e é isso que produzia a
    -- pendência "não foi possível localizar o Caixa/Disponível" no teste v31. Contra
    -- os rótulos reais do book:
    --
    --   Holding      "Caixa e Equivalentes de Caixa"  -> casa (1)
    --   Metalúrgica  "Disponibilidades"               -> casa (2)
    --   Componentes  "Numerário Disponível"           -> casa (3)
    --   SPE          "Caixa"                          -> NÃO casava: (1) exige
    --                                                   'equivalentes' e (4) exige 'bancos'
    --   VT Logística "Bancos Conta Movimento"         -> NÃO casava nenhuma
    --
    -- E o dado que faltava ESTAVA no documento: a `secao` da VT Logística diz
    -- "Disponível". A função nunca olhou `ce.secao`.
    if v_caixa.id is null then
      -- "Caixa" puro (SPE). Vem depois das combinações de dois termos, que são
      -- mais específicas — assim um documento que tem as duas coisas escolhe a
      -- linha certa em vez da mais genérica.
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['caixa'], array['circulante', 'fluxo', 'inicio', 'inicial', 'equivalente'],
        v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      -- Pela SEÇÃO do documento: é o que resolve "Bancos Conta Movimento".
      select * into v_caixa from fn_valor_conceito_secao(v_ver_bp,
        array['disponivel'], array['circulante'], v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_secao(v_ver_bp,
        array['caixa'], array['circulante', 'fluxo'], v_col_ent, v_col_per);
    end if;

    -- Saldo final na DFC (a coluna de período da DFC é a dela, não a do BP).
    v_col_per := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_ver_fx, v_ano) end;
    select * into v_saldo from fn_valor_conceito_col(v_ver_fx,
      array['saldo', 'final'], array['inicial', 'inicio'], null, v_col_per);
    if v_saldo.id is null then
      select * into v_saldo from fn_valor_conceito_col(v_ver_fx,
        array['caixa', 'final'], array['inicial', 'inicio'], null, v_col_per);
    end if;
    if v_saldo.id is null then
      select * into v_saldo from fn_valor_conceito_col(v_ver_fx,
        array['caixa', 'fim'], array['inicial', 'inicio'], null, v_col_per);
    end if;

    if v_caixa.id is null or v_saldo.id is null then
      -- 0188: cada lado com o motivo dele (o Balanço com a coluna de entidade e
      -- a de período do Balanço; a DFC só com a de período dela).
      v_motivo_ano := fn_motivo_precondicao_agregado(array[
        fn_motivo_do_lado(v_caixa.id is not null, v_col_ent, v_col_bp),
        fn_motivo_do_lado(v_saldo.id is not null, null, v_col_per)]);
      v_motivos_ano := v_motivos_ano || v_motivo_ano;
      v_faltas := v_faltas || format('%s: %s',
        coalesce(v_ano::text, 'período do documento'),
        array_to_string(array_remove(array[
          case when v_caixa.id is null then
            case when v_col_bp = E'\x01' then 'o Balanço não tem coluna deste exercício'
                 when v_col_ent = E'\x01' then 'o Balanço não tem coluna desta entidade'
                 else 'o Caixa/Disponível do Balanço não foi localizado' end end,
          case when v_saldo.id is null then
            case when v_col_per = E'\x01' then 'o Fluxo de Caixa não tem coluna deste exercício'
                 else 'o Saldo final do Fluxo de Caixa não foi localizado' end end
        ], null), ' e '));
      continue;
    end if;

    v_motivo := fn_motivo_escala_incomparavel(v_caixa.unidade, v_saldo.unidade,
      'o Caixa do Balanço', 'o Saldo final do Fluxo de Caixa');
    if v_motivo is not null then
      return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
        'caixa_bp_fluxo', 'A', v_doc_bp, null, null, 'unidade_divergente', null, null,
        jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
        fn_motivo_precondicao_prefixo('unidade_divergente') || v_motivo);
    end if;

    v_a := fn_valor_em_base(v_caixa.valor_num, v_caixa.unidade);
    v_b := fn_valor_em_base(v_saldo.valor_num, v_saldo.unidade);
    v_n := v_n + 1;
    v_div_abs := abs(v_a - v_b);
    -- 0193: A TOLERÂNCIA ABSOLUTA ESTÁ NA BASE, como v_a e v_b. Da 0031 até
    -- aqui ela era `p_tolerancia_abs * fator_da_escala`: numa entidade com
    -- Balanço/DFC em 'milhar', os R$ 100 do default viravam R$ 100 MIL, e
    -- qualquer divergência de caixa abaixo disso saía "confere". MEDIDO EM
    -- PRODUÇÃO (25/09/2026, somente leitura, recomputando fonte_a/fonte_b):
    -- das 33 caixa_bp_fluxo com resultado 'ok' (as 33 em 'milhar'), 0
    -- mudariam de resultado com a tolerância na base — diferença zero em
    -- todas. Correção LATENTE: mesmo vício estrutural da despfin (0188), sem
    -- efeito ainda medido nesta checagem. MEDIDO (regra 2): com o `× fator`
    -- de volta, o assert do bloco 1 de
    -- Supabase/test/tolerancia_na_base.test.sql reprova.
    --
    -- REVISÃO DE FIDELIDADE (28/09/2026): a tolerância na base, sozinha, tem
    -- um segundo vício — o piso de ARREDONDAMENTO do próprio documento. Num
    -- Balanço/DFC em 'milhar' cada número impresso já carrega até R$ 1.000
    -- de arredondamento (duas linhas arredondadas podem diferir em 1 unidade
    -- da escala sem que nada esteja errado). Com caixa abaixo de R$ 200 mil,
    -- 0,5% de v_a fica ABAIXO de R$ 1.000: uma DFC "12" contra um Balanço
    -- "11" (em milhar, diferença de R$ 1.000, arredondamento puro) sairia
    -- 'divergente' — mesma forma do vício que motivou esta migration, só que
    -- pela ESCALA DO DOCUMENTO, não pela unidade monetária. MEDIDO EM
    -- PRODUÇÃO (28/09/2026, somente leitura): 0 casos hoje — das 39 linhas de
    -- caixa em 'milhar', nenhuma com caixa abaixo de R$ 200 mil. Correção
    -- LATENTE, mesmo raciocínio da árvore (0133: tolerância de arredondamento
    -- em unidade do documento). Por isso o piso ganha também 1 unidade da
    -- escala mais grossa dos dois lados (Balanço/DFC podem, em tese, estar em
    -- escalas diferentes conhecidas — 0023 permite comparar), coalescida a 1
    -- (unidade/escala ausente = já está na base). Não é `× fator` de volta:
    -- é um PISO fixo de 1 unidade, não uma multiplicação da tolerância
    -- inteira. A receita (fn_reconciliar_receita_dre_vs_faturamento) NÃO
    -- ganha o mesmo piso: com pct 5%, o piso percentual só fica abaixo de 1
    -- unidade da escala quando a receita é menor que R$ 20 mil em 'milhar' —
    -- irrelevante neste domínio (nenhuma receita de mandato chega perto
    -- disso). MEDIDO (regra 2): com o piso removido (voltando a
    -- `greatest(p_tolerancia_abs, abs(v_a) * p_tolerancia_pct)`), o assert do
    -- bloco 3 de Supabase/test/tolerancia_na_base.test.sql reprova.
    v_tol := greatest(p_tolerancia_abs,
      greatest(coalesce(fn_fator_escala(v_caixa.unidade), 1), coalesce(fn_fator_escala(v_saldo.unidade), 1)),
      abs(v_a) * p_tolerancia_pct);
    if v_div_abs > v_tol then
      v_resultado := 'divergente';
      v_partes := v_partes || format('%s: Caixa no Balanço %s ("%s") vs Saldo final na DFC %s ("%s") — diferença de %s',
        coalesce(v_ano::text, 'período do documento'), v_caixa.valor_num, v_caixa.chave,
        v_saldo.valor_num, v_saldo.chave, v_div_abs);
      if v_pior_abs is null or v_div_abs > v_pior_abs then
        v_pior_abs := v_div_abs;
        v_pior_pct := case when v_a <> 0 then v_div_abs / abs(v_a) end;
      end if;
    else
      v_partes := v_partes || format('%s: confere (%s "%s" = %s "%s")',
        coalesce(v_ano::text, 'período do documento'), v_caixa.valor_num, v_caixa.chave,
        v_saldo.valor_num, v_saldo.chave);
    end if;
    v_fonte_a := jsonb_build_object('chave', v_caixa.chave, 'valor', v_caixa.valor_num,
      'unidade', v_caixa.unidade, 'documento_versao_id', v_ver_bp);
    v_fonte_b := jsonb_build_object('chave', v_saldo.chave, 'valor', v_saldo.valor_num,
      'unidade', v_saldo.unidade, 'documento_versao_id', v_ver_fx);
  end loop;

  if v_n = 0 then
    v_motivo_prec := fn_motivo_precondicao_agregado(v_motivos_ano);
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'caixa_bp_fluxo', 'A', v_doc_bp, null, null, v_motivo_prec, null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      fn_motivo_precondicao_prefixo(v_motivo_prec)
      || 'Balanço e Fluxo de Caixa presentes, mas não foi possível localizar o Caixa/Disponível do '
      || 'Balanço e/ou o Saldo final de caixa do Fluxo (rótulos extraídos não bateram). '
      || array_to_string(v_faltas, '; ') || '.');
  end if;

  return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
    'caixa_bp_fluxo', 'A', v_doc_bp, v_fonte_a, v_fonte_b, v_resultado, v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'anos_checados', v_n),
    format('Caixa do Balanço vs Saldo final do Fluxo de Caixa em %s ano(s): %s.',
           v_n, array_to_string(v_partes, '; ')));
end;
$$;

-- -----------------------------------------------------------------------------
-- (2) fn_reconciliar_receita_dre_vs_faturamento — REEMITIDA INTEIRA (corpo
-- vigente 0188:1234). Mudança única: a tolerância absoluta na base, não ×
-- fn_fator_escala.
-- -----------------------------------------------------------------------------
create or replace function fn_reconciliar_receita_dre_vs_faturamento(p_caso_id uuid,
  p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric default 50000,
  p_tolerancia_pct numeric default 0.05)
returns jsonb
language plpgsql
as $$
declare
  v_doc_dre  uuid;
  v_doc_fat  uuid;
  v_ver_dre  uuid;
  v_ver_fat  uuid;
  v_col_ent  text;
  v_ano      int;
  v_col_per  text;
  v_receita  campo_extraido;
  v_soma_sec record;
  v_val_rec  numeric;
  v_unid_rec text;
  v_chave_rec text;
  v_fat      record;
  v_unid_fat text;
  v_motivo   text;
  v_a numeric; v_b numeric; v_div numeric; v_tol numeric;
  v_resultado text := 'ok';
  v_partes text[] := '{}';
  v_n int := 0;
  v_pior_abs numeric; v_pior_pct numeric;
  v_fonte_a jsonb; v_fonte_b jsonb;
  -- 0188
  v_motivos_ano text[] := '{}';
  v_faltas      text[] := '{}';
  v_motivo_prec text;
begin
  v_doc_dre := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'DRE');
  v_doc_fat := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'FATURAMENTO_24M');

  if v_doc_dre is null or v_doc_fat is null then
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'receita_dre_vs_faturamento', 'B', coalesce(v_doc_dre, v_doc_fat), null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      format('Sem par para reconciliar receita: %s não foi entregue para esta entidade/período.',
        case when v_doc_dre is null and v_doc_fat is null then 'DRE e Faturamento (24m)'
             when v_doc_dre is null then 'DRE' else 'Faturamento (24m)' end));
  end if;

  v_ver_dre  := fn_versao_atual(v_doc_dre);
  v_ver_fat  := fn_versao_atual(v_doc_fat);
  v_col_ent  := fn_coluna_entidade(v_ver_dre, p_entidade_id);
  v_unid_fat := fn_unidade_predominante(v_ver_fat);

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    if v_ano is null then
      -- sem ano não há como recortar o mês. 0188: motivo GENÉRICO de propósito.
      v_motivos_ano := v_motivos_ano || 'precondicao_nao_satisfeita'::text;
      v_faltas := v_faltas || 'o período não tem ano, e sem ano não há como recortar os meses do faturamento'::text;
      continue;
    end if;
    v_col_per := fn_coluna_periodo_do_ano(v_ver_dre, v_ano);

    select * into v_receita from fn_valor_conceito_col(v_ver_dre,
      array['receita', 'bruta'], array['liquida', 'deducoes', 'deducao'], v_col_ent, v_col_per);
    if v_receita.id is not null then
      v_val_rec := v_receita.valor_num; v_unid_rec := v_receita.unidade;
      v_chave_rec := v_receita.chave;
    else
      -- "RECEITA OPERACIONAL BRUTA" costuma ser CABEÇALHO SEM VALOR: soma as
      -- contas da seção (Vendas de produtos, Prestação de serviços...).
      select * into v_soma_sec from fn_soma_secao(v_ver_dre,
        array['receita', 'bruta'], v_col_ent, v_col_per,
        array['deducoes', 'deducao'],
        array['liquida', 'lucro bruto', 'resultado', 'prejuizo']);
      if coalesce(v_soma_sec.n_linhas, 0) = 0 then
        v_motivos_ano := v_motivos_ano || fn_motivo_do_lado(false, v_col_ent, v_col_per);
        v_faltas := v_faltas || format('%s: %s', v_ano,
          case when v_col_per = E'\x01' then 'a DRE não tem coluna deste exercício'
               when v_col_ent = E'\x01' then 'a DRE não tem coluna desta entidade'
               else 'a Receita Bruta da DRE não foi localizada (nem como linha, nem como seção)' end);
        continue;
      end if;
      v_val_rec := v_soma_sec.soma; v_unid_rec := v_soma_sec.unidade;
      v_chave_rec := format('soma de %s contas da seção Receita Bruta', v_soma_sec.n_linhas);
    end if;

    select soma, n_linhas into v_fat
    from fn_somar_faturamento_ano(v_ver_fat, v_ano::text, right(v_ano::text, 2));
    if coalesce(v_fat.n_linhas, 0) = 0 then
      -- 0188: GENÉRICO de propósito — "o relatório não tem este ano" e "o
      -- rótulo do mês não carrega o ano" são indistinguíveis daqui.
      v_motivos_ano := v_motivos_ano || 'precondicao_nao_satisfeita'::text;
      v_faltas := v_faltas || format('%s: o Faturamento não traz linha mensal deste ano', v_ano);
      continue;
    end if;

    v_motivo := fn_motivo_escala_incomparavel(v_unid_rec, v_unid_fat,
      'a Receita Bruta da DRE', 'o Faturamento mensal');
    if v_motivo is not null then
      return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
        'receita_dre_vs_faturamento', 'B', v_doc_dre, null, null,
        'unidade_divergente', null, null,
        jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
        fn_motivo_precondicao_prefixo('unidade_divergente') || v_motivo);
    end if;

    v_a := fn_valor_em_base(v_val_rec, v_unid_rec);
    v_b := fn_valor_em_base(v_fat.soma, v_unid_fat);
    v_n := v_n + 1;
    v_div := abs(v_a - v_b);
    -- 0193: A TOLERÂNCIA ABSOLUTA ESTÁ NA BASE, como v_a e v_b. Da 0023 até
    -- aqui ela era `p_tolerancia_abs * fator_da_escala`: numa DRE em
    -- 'milhar', os R$ 50.000 do default viravam R$ 50 MILHÕES, e uma
    -- diferença de até 30% da receita sairia "confere" (ver o cabeçalho
    -- desta migration). MEDIDO EM PRODUÇÃO (25/09/2026, somente leitura,
    -- recomputando fonte_a/fonte_b): das 30 receita_dre_vs_faturamento com
    -- resultado 'ok' (10 em 'milhar'), 0 mudariam de resultado com a
    -- tolerância na base — a pior diferença entre elas chega a 4,75%, abaixo
    -- do piso percentual de 5%. Correção LATENTE. MEDIDO (regra 2): com o
    -- `× fator` de volta, o assert do bloco 2 de
    -- Supabase/test/tolerancia_na_base.test.sql reprova.
    v_tol := greatest(p_tolerancia_abs, abs(v_a) * p_tolerancia_pct);
    if v_div > v_tol then
      v_resultado := 'zona_cinzenta';
      v_partes := v_partes || format('%s: Receita Bruta %s vs %s meses de faturamento %s — diferença de %s '
        || '(Classe B: faturamento e receita reconhecida podem divergir por competência/recorte)',
        v_ano, v_val_rec, v_fat.n_linhas, v_fat.soma, v_div);
      if v_pior_abs is null or v_div > v_pior_abs then
        v_pior_abs := v_div;
        v_pior_pct := case when v_a <> 0 then v_div / abs(v_a) end;
      end if;
    else
      v_partes := v_partes || format('%s: confere (Receita Bruta %s = soma de %s meses %s)',
        v_ano, v_val_rec, v_fat.n_linhas, v_fat.soma);
    end if;
    v_fonte_a := jsonb_build_object('chave', v_chave_rec, 'valor', v_val_rec,
      'unidade', v_unid_rec, 'ano', v_ano, 'documento_versao_id', v_ver_dre);
    v_fonte_b := jsonb_build_object('soma_faturamento', v_fat.soma, 'n_meses', v_fat.n_linhas,
      'ano', v_ano, 'unidade', v_unid_fat, 'documento_versao_id', v_ver_fat);
  end loop;

  if v_n = 0 then
    v_motivo_prec := fn_motivo_precondicao_agregado(v_motivos_ano);
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'receita_dre_vs_faturamento', 'B', v_doc_dre, null, null,
      v_motivo_prec, null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      fn_motivo_precondicao_prefixo(v_motivo_prec)
      || 'DRE e Faturamento presentes, mas não foi possível casar Receita Bruta e meses do mesmo ano '
      || '(rótulos extraídos não bateram, ou o faturamento não traz o mês por linha). '
      || array_to_string(v_faltas, '; ') || '.');
  end if;

  return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
    'receita_dre_vs_faturamento', 'B', v_doc_dre, v_fonte_a, v_fonte_b, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'anos_checados', v_n),
    format('Receita Bruta da DRE vs faturamento mensal em %s ano(s): %s.',
           v_n, array_to_string(v_partes, '; ')));
end;
$$;

-- -----------------------------------------------------------------------------
-- Catálogo da sonda — requisitos de CORPO que provam a tolerância na base nas
-- duas funções (marcador é código, não comentário — sonda_marcador_e_codigo).
--
-- ORDEM 833/834: a 0192 usa 832.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, porque, severidade, ordem) values

  ('caixa_bp_fluxo_tolerancia_na_base', '0193', 'corpo', 'fn_reconciliar_caixa_bp_fluxo',
   'greatest(coalesce(fn_fator_escala(v_caixa.unidade), 1), coalesce(fn_fator_escala(v_saldo.unidade), 1))',
   'Sem este corpo, a tolerância absoluta do Caixa × Saldo final do Fluxo de Caixa é multiplicada '
   'pela escala do Balanço (em milhar, R$ 100 MIL em vez de R$ 100 — mesmo vício estrutural que a '
   '0188 corrigiu na despfin; latente hoje, 0 das 33 caixa_bp_fluxo ''ok'' em produção mudariam de '
   'resultado, medido 25/09/2026) OU não tem o piso de arredondamento de 1 unidade da escala mais '
   'grossa dos dois lados (sem ele, caixa abaixo de R$ 200 mil em ''milhar'' pode sair '
   '''divergente'' por puro arredondamento do documento — latente hoje, 0 casos em 39 linhas de '
   'caixa em ''milhar'', medido 28/09/2026). O marcador é o argumento novo da tolerância, e não '
   'casa a forma antiga ''× fator'' nem a forma sem piso.',
   'importante', 833),

  ('receita_dre_vs_faturamento_tolerancia_na_base', '0193', 'corpo',
   'fn_reconciliar_receita_dre_vs_faturamento',
   'v_tol := greatest(p_tolerancia_abs, abs(v_a) * p_tolerancia_pct)',
   'Sem este corpo, a tolerância absoluta da Receita Bruta × Faturamento é multiplicada pela '
   'escala da DRE: em milhar, R$ 50 MILHÕES em vez de R$ 50 mil — uma diferença de até 30% da '
   'receita sairia "confere". Mesmo vício estrutural que a 0188 corrigiu na despfin; latente hoje '
   '(0 das 30 receita_dre_vs_faturamento ''ok'' em produção mudariam de resultado, medido '
   '25/09/2026; a pior diferença entre elas é 4,75%, abaixo do piso de 5%).',
   'importante', 834)

on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, porque = excluded.porque, severidade = excluded.severidade,
      ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0193', revisado_em = current_date,
       observacao = 'A 0193 reemite fn_reconciliar_caixa_bp_fluxo e fn_reconciliar_receita_dre_vs_'
         'faturamento para levar a mesma correção da despfin (0188) à tolerância absoluta: ela '
         'passa a estar na base (fn_valor_em_base), não multiplicada pelo fator de escala do '
         'documento. Vício estrutural das três funções desde a 0023/0031; corrigido agora nas duas '
         'que faltavam. Medido em produção (25/09/2026, somente leitura): efeito ZERO hoje nas duas '
         '(0 de 33 caixa_bp_fluxo e 0 de 30 receita_dre_vs_faturamento ''ok'' mudariam de '
         'resultado) — correção latente, não achado novo. Catalogado pelo corpo '
         '(caixa_bp_fluxo_tolerancia_na_base, receita_dre_vs_faturamento_tolerancia_na_base) — as '
         'assinaturas não mudam. REVISÃO DE FIDELIDADE (28/09/2026): a tolerância na base '
         'sozinha ainda saía ''divergente'' por arredondamento do documento (caixa abaixo de '
         'R$ 200 mil em ''milhar''); fn_reconciliar_caixa_bp_fluxo ganhou um piso de 1 unidade da '
         'escala mais grossa dos dois lados — latente, 0 casos em 39 linhas de caixa em ''milhar'', '
         'medido 28/09/2026. A receita não precisa do mesmo piso (pct 5% só cairia abaixo de 1 '
         'unidade com receita < R$ 20 mil em ''milhar'', irrelevante neste domínio).'
 where id = true;
