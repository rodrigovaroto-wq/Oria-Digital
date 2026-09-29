-- =============================================================================
-- 0191 — O MAPA DE UM ANO CONTRA A DRE DE DOIS
--
-- O DEFEITO. `fn_reconciliar_despfin_dre_vs_divida` (corpo vigente na 0188,
-- `Supabase/migrations/0188_o_motivo_que_a_checagem_sabia_e_nao_dizia.sql:1033`)
-- itera `foreach v_ano in array fn_anos_alvo(p_periodo_id)` e, em CADA ano,
-- compara a Despesa Financeira da DRE daquele ano com a soma dos juros do
-- Mapa de Dívida INTEIRO (`sum(ce.valor_num)` sobre o `documento_versao_id`,
-- sem corte por ano — o próprio comentário da 0188 já dizia "o mapa não é
-- recortado por ano"). O Mapa de Dívida é um retrato de UMA data: MEDIDO EM
-- PRODUÇÃO (25/09/2026, somente leitura): todo período de documento
-- MAPA_DIVIDA hoje é `data-base` ou `anual` de um ano só (31/12/2025 ×12,
-- 31/12/2024 ×8, 31/12/2022 ×8, anual 2025 ×7, 12M25 ×6…). Então, com uma DRE
-- `multi "24,25"`, a checagem compara a despesa de 2024 com os juros do mapa
-- de 2025: resultado sem sentido — `zona_cinzenta` falsa se diferirem, `ok`
-- falso se coincidirem.
--
-- MEDIDO NO FIXTURE (book-vertentes, `Supabase/test/reconciliacao.test.sql`,
-- CASO 11111111-…, VERTENTES METALÚRGICA LTDA.): a DRE é `multi "24,25"`
-- (período 33333333-…-0001) e o Mapa de Dívida é `data-base "2025-12-31"`
-- (período 33333333-…-0004). Despesa Financeira 2024 = R$ 8.900 mil, juros do
-- mapa (ano único, 2025) = R$ 12.400 mil: 2024 sai comparada contra o mapa do
-- OUTRO ano, R$ 3,5 milhões de diferença sem sentido nenhum.
--
-- HOJE ISSO FICA ESCONDIDO, e por que: `fn_reconciliar_caso`/`fn_reconciliar_-
-- por_documento` chamam esta função uma vez por período distinto da entidade.
-- Com p_periodo_id = 'multi:24,25' (2024 e 2025, o Mapa não recortado), o
-- PRIMEIRO ano do laço já diverge e o `v_resultado` fica `zona_cinzenta` até o
-- fim da função (nunca volta a `ok` — é um valor só, não um por ano); com
-- p_periodo_id = 'data-base:2025-12-31' (só 2025), a MESMA checagem conclui
-- `ok` (2025 contra 2025 confere). `fn_registrar_reconciliacao` casa as duas
-- gravações na MESMA pendência por período COMPATÍVEL (`fn_periodos_compati-
-- veis`, que aqui é verdade: os dois períodos têm 2025 em comum) — e como o
-- Mapa de Dívida (documento id 44444444-…-0011) é processado DEPOIS da DRE
-- (id …-0007) em `teste_reconciliar_tudo`/`fn_reconciliar_por_documento`
-- (ordem por id), o `ok` da chamada `data-base:2025-12-31` chega por ÚLTIMO e
-- RESOLVE a pendência que a chamada `multi:24,25` tinha acabado de abrir —
-- `fn_registrar_reconciliacao`, ramo `elsif v_pendencia_id is not null`
-- (0188:508-514). MEDIDO agora, ANTES desta migration, contra o fixture
-- (`tdf_claude`, HEAD 73403e3): as 4 chamadas de despfin para VERTENTES
-- METALÚRGICA alternam `zona_cinzenta` (anos_checados=2, período multi/L24M)
-- e `ok` (anos_checados=1, período anual/data-base), sempre terminando em `ok`
-- — SELECT tipo, resultado, materialidade->>'anos_checados' FROM reconciliacao
-- WHERE tipo='despfin_dre_vs_divida' AND entidade_id='22222222-…-0001' ORDER
-- BY criado_em confirma a alternância. `reconciliacao.test.sql` bloco 1 passa
-- porque só cobra `resultado='ok'` existir alguma vez (linha 143), não que a
-- fila fique limpa — é a MESMA lacuna que a 0188 corrigiu num outro ramo: o
-- `ok` de um período resolve, em silêncio, o que outro período tinha achado.
-- Corrigi-la é a fatia seguinte (já escrita, esperando esta): sem ESTA
-- migration primeiro, aquela correção faria a pendência FALSA de 2024
-- sobreviver, porque não teria mais o `ok` de 2025 para apagá-la.
--
-- MEDIDO EM PRODUÇÃO (25/09/2026, somente leitura, hoje — antes desta
-- migration): 44 linhas de `despfin_dre_vs_divida` — 15 `ok`, 29 pré-condição,
-- 0 divergentes; as 29 pendências abertas são todas `precondicao_nao_-
-- satisfeita`. Nenhuma tem hoje uma DRE `multi`/`L*M` cruzando um Mapa de
-- Dívida de um ano só com resultado divergente publicado — o defeito de HOJE é
-- silencioso pela MESMA razão do fixture (o `ok` do período compatível
-- resolve), então a exposição real só aparece quando a fatia seguinte fechar
-- esse segundo buraco.
--
-- A CORREÇÃO. Só compara o ano `v_ano` do laço quando o período do DOCUMENTO
-- do Mapa de Dívida (`documento.periodo_id` de `v_doc_div` → `periodo.tipo,
-- referencia` → `fn_anos_periodo`) contém esse ano — lido UMA VEZ antes do
-- laço, não recalculado ano a ano. Ano que o Mapa não cobre: NÃO compara —
-- entra em `v_motivos_ano` como `'sem_periodo_par'` (motivo do CONTRATO da
-- 0186; a agregação `fn_motivo_precondicao_agregado`, inalterada, só o escolhe
-- se TODOS os anos ficarem assim, e cede para `linha_nao_localizada` se algum
-- ano tiver isso) e em `v_faltas` com o efeito, não um zero mudo: "2024: o
-- Mapa de Dívida é de 2025-12-31 — não há juros deste exercício para
-- comparar" (regra 1).
--
-- AS DUAS EXCEÇÕES, onde o comportamento ANTIGO fica — porque não há como
-- afirmar o ano que o mapa não declara:
--   • o Mapa de Dívida não tem `periodo_id` (documento sem período atribuído);
--   • `fn_anos_periodo` do período do Mapa devolve vazio (período que não
--     ancora ano nenhum — texto livre, por exemplo).
-- Nos dois, `v_anos_mapa` fica vazio e a guarda nova não filtra nada: TODO ano
-- do laço é comparado contra a soma do documento inteiro, exatamente como
-- antes desta migration.
--
-- O QUE NÃO MUDA. A tolerância na base (`v_tol := greatest(p_tolerancia_abs,
-- abs(v_a) * p_tolerancia_pct)`, PARTE 4 da 0188) fica LITERAL — é o texto que
-- o requisito `despfin_tolerancia_na_base` da sonda procura. O localizador de
-- "JUROS E COMISSÕES BANCÁRIAS" (PARTE 3 da 0188) não muda. `fn_registrar_-
-- reconciliacao`, `fn_motivo_do_lado`, `fn_motivo_precondicao_agregado`,
-- `fn_motivo_precondicao_prefixo` não são tocadas — só o corpo desta checagem.
-- Os despachantes (`fn_reconciliar_caso`, `fn_reconciliar_chaves_do_documento`,
-- 0152) não mudam: continuam lendo o `resultado` DEVOLVIDO (achatado pela
-- 0188) e o laço de períodos continua igual — `sem_periodo_par`, como os
-- outros dois motivos do CONTRATO, já cai do lado "não concluiu, tenta o
-- período seguinte".
--
-- REEMITIDA A FUNÇÃO INTEIRA a partir do corpo vigente (0188) — nunca
-- `replace` de texto (`.claude/memory/nunca-corrigir-funcao-por-replace.md`).
-- Conferido por grep (`create or replace function
-- fn_reconciliar_despfin_dre_vs_divida` em `Supabase/migrations/`) que
-- nenhuma migration entre a 0188 e esta reemitiu o corpo — só a 0188 o define.
--
-- MEDIDO NAS FIXTURES DOS DOIS BOOKS (regra 2 — ver Supabase/README.md, bloco
-- desta migration, para o comando e a conferência completa): com a guarda
-- desligada e religada, nenhuma linha do retrato byte-a-byte de
-- `motivo_especifico.test.sql` (blocos 1 e 2, o literal medido na 0187) muda —
-- as chamadas de `despfin_dre_vs_divida` que essas fixtures exercitam
-- concluem por `unidade_divergente` (perturbação 5) ou já comparam um único
-- ano compatível, então o corte por ano não altera qual ramo elas tomam.
-- `reconciliacao.test.sql` (VERTENTES) passa a registrar `ok` nas QUATRO
-- chamadas de despfin em vez de alternar `zona_cinzenta`/`ok` — a pendência
-- nunca chegou a existir (nenhum assert dependia da alternância).
--
-- O QUE ESTA MIGRATION NÃO FAZ.
--   • Não roda reconciliação nem recompute em caso nenhum. As 44 linhas de
--     produção continuam como estão — o corte por ano vale a partir da
--     próxima rodada de cada caso.
--   • Não fecha o segundo buraco descrito acima (o `ok` de um período
--     resolvendo, em silêncio, a pendência que outro período abriu) — é a
--     fatia seguinte, já escrita, que dependia desta vir primeiro.
--   • Não muda o vocabulário da 0186, a tolerância da 0188, nem a linha que
--     decide pendência (`fn_registrar_reconciliacao`).
--   • Não é aplicada em produção por estar escrita. Quem responde é a sonda:
--
--       select chave, migration, tipo, objeto, presente, detalhe, porque
--         from fn_instalacao_conferir() where not presente order by 1;
-- =============================================================================

create or replace function fn_reconciliar_despfin_dre_vs_divida(p_caso_id uuid, p_entidade_id uuid,
  p_periodo_id uuid, p_tolerancia_abs numeric default 50000, p_tolerancia_pct numeric default 0.05)
returns jsonb
language plpgsql
as $_$
declare
  v_doc_dre uuid;
  v_doc_div uuid;
  v_ver_dre uuid;
  v_ver_div uuid;
  v_col_ent text;
  v_ano int;
  v_col_per text;
  v_despfin campo_extraido;
  v_juros   record;
  v_unid_div text;
  v_motivo text;
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
  v_alt         record;
  v_recado      text;
  -- 0191: os anos que o PERÍODO DO DOCUMENTO do Mapa de Dívida ancora. Lido
  -- uma vez, fora do laço — o mapa não muda de período ano a ano. Vazio =
  -- "não há como afirmar o ano" (sem período, ou período que não ancora ano
  -- nenhum): a guarda nova não filtra nada, comportamento de antes.
  v_periodo_id_div uuid;
  v_tipo_div        text;
  v_ref_div         text;
  v_anos_mapa       int[];
begin
  v_doc_dre := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'DRE');
  v_doc_div := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'MAPA_DIVIDA');

  if v_doc_dre is null or v_doc_div is null then
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'despfin_dre_vs_divida', 'B', coalesce(v_doc_dre, v_doc_div), null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      format('Sem par para reconciliar despesa financeira: %s não foi entregue para esta entidade/período.',
        case when v_doc_dre is null and v_doc_div is null then 'DRE e Mapa de Dívida'
             when v_doc_dre is null then 'DRE' else 'Mapa de Dívida' end));
  end if;

  v_ver_dre  := fn_versao_atual(v_doc_dre);
  v_ver_div  := fn_versao_atual(v_doc_div);
  v_col_ent  := fn_coluna_entidade(v_ver_dre, p_entidade_id);
  v_unid_div := fn_unidade_predominante(v_ver_div);

  -- 0191: o Mapa de Dívida é um retrato de UMA data — MEDIDO EM PRODUÇÃO
  -- (25/09/2026): todo MAPA_DIVIDA hoje tem período de um ano só. Sem este
  -- corte, o laço abaixo compara CADA ano da DRE contra a soma de juros do
  -- documento inteiro (não recortada por ano), inclusive anos que o mapa não
  -- cobre — ver o cabeçalho desta migration.
  select periodo_id into v_periodo_id_div from documento where id = v_doc_div;
  if v_periodo_id_div is not null then
    select tipo, referencia into v_tipo_div, v_ref_div from periodo where id = v_periodo_id_div;
    v_anos_mapa := fn_anos_periodo(v_tipo_div, v_ref_div);
  end if;

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    v_col_per := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_ver_dre, v_ano) end;

    -- 0191: o ano deste laço não é coberto pelo período do Mapa de Dívida —
    -- não compara. `v_anos_mapa` vazio (mapa sem período, ou período que não
    -- ancora ano nenhum) mantém o comportamento antigo: sem como afirmar que o
    -- ano não é coberto, a guarda não filtra.
    if v_ano is not null and cardinality(coalesce(v_anos_mapa, '{}'::int[])) > 0
       and not (v_ano = any(v_anos_mapa)) then
      v_motivos_ano := v_motivos_ano || 'sem_periodo_par'::text;
      v_faltas := v_faltas || format(
        '%s: o Mapa de Dívida é de %s — não há juros deste exercício para comparar',
        v_ano, coalesce(v_ref_div, 'outro período'));
      continue;
    end if;

    select * into v_despfin from fn_valor_conceito_col(v_ver_dre,
      array['despesa', 'financeira'], array['receita'], v_col_ent, v_col_per);
    if v_despfin.id is null then
      select * into v_despfin from fn_valor_conceito_col(v_ver_dre,
        array['juros', 'encargos'], array['receita', 'pagos'], v_col_ent, v_col_per);
    end if;
    -- 0188 (parte 3): "JUROS E COMISSÕES BANCÁRIAS" — o rótulo de UMA entidade
    -- de produção cuja pendência de despesa financeira era falsa, porque o
    -- localizador de cima exige "juros" E "encargos". Medido sobre TODOS os
    -- rótulos de DRE com juros/financeir/encargo em produção (22/09/2026): casa
    -- "juros e comissoes bancarias" (8 linhas, 4 entidades, todas negativas) e
    -- NENHUM rótulo de receita — o exclui leva 'aplicac' porque "juros s/
    -- aplicação financeira" e "juros de aplicações" são receita. O MESMO par
    -- está em taxonomia_linha_localizador (DRE/despesa_financeira, ordem 3):
    -- duplicação assumida da 0113, para exigência e checagem não divergirem.
    if v_despfin.id is null then
      select * into v_despfin from fn_valor_conceito_col(v_ver_dre,
        array['juros', 'bancari'], array['receita', 'aplicac'], v_col_ent, v_col_per);
    end if;
    if v_despfin.id is null then
      v_motivos_ano := v_motivos_ano || fn_motivo_do_lado(false, v_col_ent, v_col_per);
      -- 0188 (parte 2, do lado da checagem): a DRE traz o LÍQUIDO no lugar? A
      -- alternativa é a mesma linha que a pendência de completude lê.
      if v_recado is null then
        select a.recado, ce.chave into v_alt
          from taxonomia_linha_alternativa a
          join taxonomia_linha_exigida e on e.id = a.exigencia_id
          cross join lateral fn_valor_conceito_col(v_ver_dre, a.termos_inclui, a.termos_exclui,
                                                   v_col_ent, v_col_per) ce
         where e.tipo_taxonomia = 'DRE' and e.conceito = 'despesa_financeira' and e.ativo
           and a.contra = 'chave' and ce.id is not null
         order by a.ordem
         limit 1;
        if v_alt.recado is not null then
          v_recado := format('A DRE traz "%s" no lugar. %s', v_alt.chave, v_alt.recado);
        end if;
      end if;
      v_faltas := v_faltas || format('%s: %s', coalesce(v_ano::text, 'período do documento'),
        case when v_col_per = E'\x01' then 'a DRE não tem coluna deste exercício'
             when v_col_ent = E'\x01' then 'a DRE não tem coluna desta entidade'
             else 'a Despesa Financeira da DRE não foi localizada' end);
      continue;
    end if;

    -- Juros do exercício no mapa: soma as linhas por contrato, excluindo o total.
    select coalesce(sum(ce.valor_num), 0)::numeric as soma, count(*)::int as n
      into v_juros
    from campo_extraido ce
    where ce.documento_versao_id = v_ver_div
      and ce.valor_num is not null
      -- 0145: o conceito pode morar na COLUNA. No mapa de dívida matricial a
      -- chave é o contrato ("Banco Meridional S.A. - Capital de giro (…)") e o
      -- cabeçalho é "Juros do exercício (R$)". Sem este segundo ramo a soma vinha
      -- vazia e a checagem devolvia precondicao_nao_satisfeita sobre um documento
      -- perfeitamente extraído — pendência da v48 no 02_DRE_Canastra_Industria.
      and (fn_normalizar_texto(ce.chave) like '%juros%'
           or fn_normalizar_texto(ce.chave) like '%encargos%'
           or fn_normalizar_texto(coalesce(ce.periodo_coluna, '')) like '%juros%'
           or fn_normalizar_texto(coalesce(ce.periodo_coluna, '')) like '%encargos%')
      and fn_normalizar_texto(ce.chave) not like 'total%'
      and fn_normalizar_texto(ce.chave) not like '%total %';
    if coalesce(v_juros.n, 0) = 0 then
      -- 0188: o mapa não é recortado por ano (a soma lê o documento inteiro),
      -- então do lado dele não há "sem período": é linha não localizada.
      v_motivos_ano := v_motivos_ano || 'linha_nao_localizada'::text;
      v_faltas := v_faltas || format('%s: o Mapa de Dívida não tem linha nem coluna de juros/encargos',
        coalesce(v_ano::text, 'período do documento'));
      continue;
    end if;

    v_motivo := fn_motivo_escala_incomparavel(v_despfin.unidade, v_unid_div,
      'a Despesa Financeira da DRE', 'o Mapa de Dívida');
    if v_motivo is not null then
      return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
        'despfin_dre_vs_divida', 'B', v_doc_dre, null, null,
        'unidade_divergente', null, null,
        jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
        fn_motivo_precondicao_prefixo('unidade_divergente') || v_motivo);
    end if;

    -- Comparação em VALOR ABSOLUTO: a DRE traz a despesa como negativa
    -- (dedução), o mapa traz os juros como positivos.
    v_a := abs(fn_valor_em_base(v_despfin.valor_num, v_despfin.unidade));
    v_b := abs(fn_valor_em_base(v_juros.soma, v_unid_div));
    v_n := v_n + 1;
    v_div := abs(v_a - v_b);
    -- 0188 (revisão, 22/09/2026): A TOLERÂNCIA ABSOLUTA ESTÁ NA BASE, como v_a
    -- e v_b. Da 0023 até aqui ela era `p_tolerancia_abs * fator_da_DRE`: numa
    -- DRE em 'milhar', os 50.000 do default viravam R$ 50 MILHÕES, e qualquer
    -- divergência abaixo disso saía "confere". MEDIDO EM PRODUÇÃO (22/09/2026,
    -- somente leitura): das 33 despfin com resultado 'ok', 32 conferem de
    -- verdade com greatest(R$ 50.000, 5%) e 1 é falsa — R$ 12.400.000 de
    -- diferença saindo "confere". fn_reconciliar_mutuos (0123) já fazia assim
    -- ("tolerância em MOEDA BASE ... senão a checagem é mais frouxa justamente
    -- onde os valores são maiores"). Esta é a SEGUNDA mudança de resultado
    -- desta migration (a primeira é a parte 3) — ver o cabeçalho. MEDIDO
    -- (regra 2): com o `× fator` de volta, 2 asserts reprovam — o bloco 5 de
    -- motivo_especifico.test.sql (8.194 × 5.308 em milhar sai "ok") e o
    -- requisito despfin_tolerancia_na_base de instalacao.test.sql.
    v_tol := greatest(p_tolerancia_abs, abs(v_a) * p_tolerancia_pct);
    if v_div > v_tol then
      v_resultado := 'zona_cinzenta';
      v_partes := v_partes || format('%s: Despesa Financeira %s "%s" vs soma de %s contratos %s "%s" — diferença de %s na base',
        v_ano, v_despfin.valor_num, coalesce(v_despfin.unidade, 'sem escala'),
        v_juros.n, v_juros.soma, coalesce(v_unid_div, 'sem escala'), v_div);
      if v_pior_abs is null or v_div > v_pior_abs then
        v_pior_abs := v_div;
        v_pior_pct := case when v_a <> 0 then v_div / abs(v_a) end;
      end if;
    else
      v_partes := v_partes || format('%s: confere (Despesa Financeira %s "%s" = juros de %s contratos %s "%s", convertidos à mesma base)',
        v_ano, v_despfin.valor_num, coalesce(v_despfin.unidade, 'sem escala'),
        v_juros.n, v_juros.soma, coalesce(v_unid_div, 'sem escala'));
    end if;
    v_fonte_a := jsonb_build_object('chave', v_despfin.chave, 'valor', v_despfin.valor_num,
      'unidade', v_despfin.unidade, 'ano', v_ano, 'documento_versao_id', v_ver_dre);
    v_fonte_b := jsonb_build_object('soma_juros', v_juros.soma, 'n_contratos', v_juros.n,
      'unidade', v_unid_div, 'documento_versao_id', v_ver_div);
  end loop;

  if v_n = 0 then
    v_motivo_prec := fn_motivo_precondicao_agregado(v_motivos_ano);
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'despfin_dre_vs_divida', 'B', v_doc_dre, null, null,
      v_motivo_prec, null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      fn_motivo_precondicao_prefixo(v_motivo_prec)
      || 'DRE e Mapa de Dívida presentes, mas não foi possível localizar a Despesa Financeira da DRE '
      || 'e/ou as linhas de juros do mapa (rótulos extraídos não bateram). '
      || array_to_string(v_faltas, '; ') || '.'
      || coalesce(' ' || v_recado, ''));
  end if;

  return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
    'despfin_dre_vs_divida', 'B', v_doc_dre, v_fonte_a, v_fonte_b, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'anos_checados', v_n),
    format('Despesa Financeira da DRE vs juros do Mapa de Dívida em %s ano(s): %s.',
           v_n, array_to_string(v_partes, '; ')));
end;
$_$;

comment on function fn_reconciliar_despfin_dre_vs_divida(uuid, uuid, uuid, numeric, numeric) is
  'Reconcilia a Despesa Financeira da DRE contra a soma dos juros do Mapa de Dívida, ano a ano. '
  '0191: só compara o ano quando o período do DOCUMENTO do Mapa de Dívida o cobre '
  '(fn_anos_periodo do período do mapa) — o Mapa é um retrato de UMA data, e comparar um ano que '
  'ele não cobre contra a soma do documento inteiro é comparação sem sentido. Ano fora: '
  'sem_periodo_par, não ok nem zona_cinzenta. Mapa sem período (ou período sem ano ancorado): '
  'comportamento antigo, sem filtro.';

grant execute on function fn_reconciliar_despfin_dre_vs_divida(uuid, uuid, uuid, numeric, numeric) to authenticated;

-- -----------------------------------------------------------------------------
-- Catálogo da sonda — o requisito de CORPO que prova que o corte por ano está
-- instalado (a assinatura não muda: `reconciliar_despfin_dre_vs_divida`, tipo
-- funcao, migration 0015, continua provando só que a função EXISTE). Marcador
-- é código, não comentário (`sonda_marcador_e_codigo.test.sql`).
--
-- ORDEM 831: a 0190 usa 830.
-- -----------------------------------------------------------------------------

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, porque, severidade, ordem) values

  ('despfin_ano_par_do_mapa', '0191', 'corpo', 'fn_reconciliar_despfin_dre_vs_divida',
   'v_ano = any(v_anos_mapa)',
   'Sem este corte, a checagem compara CADA ano da DRE contra a soma de juros do Mapa de Dívida '
   'INTEIRO, sem recorte por ano — e o Mapa é um retrato de UMA data (MEDIDO EM PRODUÇÃO, '
   '25/09/2026: todo MAPA_DIVIDA tem período de um ano só). Numa DRE multi-ano, o ano que o mapa '
   'não cobre sai comparado do mesmo jeito: zona_cinzenta falsa se os valores diferirem, ok falso '
   'se coincidirem por acaso.',
   'importante', 831)

on conflict (chave) do update
  set migration = excluded.migration,
      tipo      = excluded.tipo,
      objeto    = excluded.objeto,
      marcador  = excluded.marcador,
      porque    = excluded.porque,
      severidade = excluded.severidade,
      ordem     = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0191', revisado_em = current_date,
       observacao = 'A 0191 reemite fn_reconciliar_despfin_dre_vs_divida para só comparar o ano da '
         'DRE contra o Mapa de Dívida quando o período do DOCUMENTO do mapa cobre esse ano — antes '
         'comparava todo ano contra a soma do documento inteiro, sem recorte. Ano fora do período do '
         'mapa: sem_periodo_par (CONTRATO da 0186), não ok nem zona_cinzenta. Mapa sem período, ou '
         'período que não ancora ano nenhum: comportamento antigo, sem filtro (sem como afirmar o '
         'ano). Catalogado pelo corpo (despfin_ano_par_do_mapa) — a assinatura da função não muda.'
 where id = true;
