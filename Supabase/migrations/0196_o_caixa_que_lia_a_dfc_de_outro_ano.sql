-- =============================================================================
-- 0196 — O CAIXA QUE LIA A DFC DE OUTRO ANO
--
-- O DEFEITO (30/09/2026, mandato de teste em produção, caso bb37f726, book
-- sintético `Dados de Teste/book-vertentes`). `fn_reconciliar_caixa_bp_fluxo`
-- (corpo vigente na 0193) comparou o Balanço "multi 24,25" (Disponível 2024 =
-- 4.840) com a DFC ANUAL 2025 (saldo final 500) e gravou `divergente` para 2024:
-- pendência Classe A `divergencia_reconciliacao` de R$ 4,34 mi FALSA. O gabarito
-- (`Dados de Teste/book-vertentes/pdf/GUIA_DE_TESTE.md`) só pede 2025 (500 = 500).
-- É o MESMO R$ 4,34 mi do "Teste v33/v35" que o cabeçalho da 0192 descreveu como
-- divergência real: era falso positivo. A 0192 já está aplicada e não foi editada.
--
-- A CAUSA, MEDIDA. As linhas da DFC de UM exercício só têm `periodo_coluna` NULL, e
-- a função lê `fn_coluna_periodo_do_ano(...)` = NULL como "documento sem coluna de
-- período, não filtra" — a linha vale para QUALQUER ano do laço `foreach v_ano`. É o
-- vício 2 que a 0194 corrigiu em mútuos e a 0195 em intragrupo, fatorado em
-- `fn_linha_vale_para_ano`. Aqui o NULL era lido nos DOIS lados (Balanço e DFC).
--
-- MEDIDO EM PRODUÇÃO (30/09/2026, SOMENTE LEITURA):
--   • 72 pendências abertas `reconciliacao:caixa_bp_fluxo`; 5 têm descrição de
--     divergência. As 5 têm o arranjo exato — Balanço "multi 24,25" (colunas
--     31/12/2024 e 31/12/2025) × DFC "anual 2025" com 0 linhas de periodo_coluna — e
--     a descrição diz "2024: Caixa no Balanço … vs Saldo final na DFC 500".
--   • 4 delas (casos a0344b3f, 03c8804c/entidade A, ceb8b47f, bb37f726) têm 2025 conferindo
--     (500 = 500) e 2024 = 4.840 contra 500: R$ 4.340.000 de diferença FALSA. A 5ª
--     (03c8804c/entidade B) tem 2024 = 358 contra 500 (falso, pelo mesmo motivo) E
--     2025 = 320 contra 500 (R$ 180 mil, divergência que a correção NÃO apaga).
--   • O banco tem 7 últimas reconciliações `caixa_bp_fluxo` divergentes (por caso, entidade e
--     período); as 5 pendências acima são as que consegui rastrear até o arranjo. As outras 2
--     não foram examinadas.
--   Sem backfill: a correção vale na PRÓXIMA rodada de cada caso; as 4 pendências falsas
--   se resolvem sozinhas quando a checagem rodar de novo (`fn_registrar_reconciliacao`
--   resolve a pendência de um resultado não-divergente), a 5ª continua aberta por 2025.
--
-- A CORREÇÃO. Em `fn_reconciliar_caixa_bp_fluxo` (REEMITIDA INTEIRA do corpo vigente
-- 0193, nunca `replace` de texto), cada lado, quando o documento NÃO tem coluna de
-- período (v_col_per nulo), só vale para o ano do laço se `fn_linha_vale_para_ano`
-- disser que o PERÍODO PRÓPRIO do documento ancora o ano (ou não ancora ano nenhum —
-- indecidível, passa, como sempre). Se não ancora, `v_col_per` vira a sentinela
-- E'\x01' (a que a 0023 já usa: "documento com colunas, nenhuma é deste ano"): a busca
-- não devolve linha, e `fn_motivo_do_lado` já a traduz em `sem_periodo_par`, o motivo
-- do contrato 0186/0188. Nada novo no vocabulário. A tolerância da 0193 (na base, com o
-- piso de arredondamento) fica LITERAL, e o resto do corpo também.
--
-- REGRA 1 (ausência não é dado). O ano que fica de fora NÃO some calado quando o outro
-- ano conclui: a descrição ganha " Não comparado — 2024: o Fluxo de Caixa é de 2025 —
-- não traz este exercício." Antes, um ano sem as duas linhas saía do `v_partes` sem
-- rastro. A mesma frase foi acrescentada às outras duas funções reemitidas.
--
-- AS OUTRAS CHECAGENS POR ANO — AUDITADAS UMA A UMA (probe em banco descartável, cada uma
-- com o arranjo "documento de um ano só × período multi", antes de qualquer edição):
--
--   TINHAM O VÍCIO (corrigidas aqui, cada uma com assert que reprova desligada):
--   • fn_reconciliar_receita_dre_vs_faturamento — DRE anual 2025 SEM coluna valia como a
--     Receita Bruta de 2024: 2024 saía `zona_cinzenta` (74.000 contra 10.000 de faturamento)
--     e 2025 `confere`. MEDIDO EM PRODUÇÃO: das 25 últimas reconciliações de receita com
--     fonte_a, 3 leem uma DRE sem coluna em mais anos que o período dela — e as 3 não são ok.
--   • fn_reconciliar_despfin_dre_vs_divida — o corte da 0191 só olhava o lado do MAPA; a DRE
--     sem coluna também valia para qualquer ano. Com DRE anual 2025 × Mapa de 31/12/2024 em
--     período multi 24,25, o 2024 saía `zona_cinzenta` (9.000 contra 1.000). MEDIDO EM
--     PRODUÇÃO: 0 de 17 — LATENTE hoje; corrigida porque o arranjo é provado por teste e é o
--     mesmo vício, e porque deixar UMA checagem por ano de fora é como o vício voltou três
--     vezes (0194, 0195, esta).
--
--   NÃO TÊM (não tocadas):
--   • fn_reconciliar_ativo_passivo_pl — compara Ativo com Passivo+PL DENTRO do mesmo documento e
--     do mesmo ano do laço; o valor de cada lado não depende do ano, então documento de um ano
--     só não produz resultado FALSO (o probe deu o mesmo resultado para 2024 e 2025). O que
--     sobra é cosmético: `anos_checados` conta 2 para um balanço de 1 ano. Não é o vício
--     "compara o ano errado"; fica como achado menor.
--   • fn_reconciliar_mutuos e fn_reconciliar_intragrupo — já usam `fn_linha_vale_para_ano` (0194/0195).
--   • fn_reconciliar_duplicidade, por_documento, caso — não iteram por ano.
--
-- ACHADO DO COMPARATIVO, FORA DO ESCOPO E NÃO CORRIGIDO: `fn_reconciliar_ativo_passivo_pl`
-- ainda tem a tolerância absoluta `p_tolerancia_abs * fator_da_escala` (a 0188 corrigiu a despfin
-- e a 0193 a caixa e a receita, mas não esta). No probe, Ativo 1.000 × Passivo+PL 900 em milhar
-- (R$ 100 mil de diferença) saiu "confere". Migration própria, com medição própria.
--
-- SEGUNDO DEFEITO DA MESMA FAMÍLIA, MEDIDO NO MESMO CASO (bb37f726, documento
-- `10_Faturamento_24M_Vertentes_Metalurgica.pdf`): `fn_somar_faturamento_ano` (0167) tirava o
-- ano do RÓTULO. O relatório tem, por mês, o rótulo "jan/2024 — jan/2025" e TRÊS colunas
-- (`periodo_coluna` '2024', '2025' e 'Variação %'), mais "TOTAL DO EXERCÍCIO", "Média mensal" e
-- "Ticket médio…" depois dos meses. O rótulo contém os DOIS anos, então para 2024 E para 2025
-- a função somava as três células de cada mês: 183.480 + 138.400 + (-300,4 de percentuais) =
-- 321.579,6 — é o `fonte_b.soma_faturamento` gravado em produção — contra 183.480 que os 12
-- meses de 2024 somam de verdade (= Receita Bruta 2024 do gabarito). Ao contrário do caixa, o
-- vício é do PARSER DE ANO: não é linha sem coluna valendo para todo ano.
--   CORREÇÃO: quando alguma coluna do documento ancora ano (`fn_anos_texto(periodo_coluna)` não
--   vazio), o ano vem da COLUNA; o rótulo só precisa parecer um mês (traz o ano pedido ou começa
--   por jan…dez), o que mantém fora o "Ticket médio…" (sem mês) e as linhas de total/média (as
--   exclusões de 0167 ficam). Coluna de percentual ('%' ou 'variação') nunca entra na soma, em
--   nenhum modo. Sem coluna que ancore ano (o relatório de categorias da 0167: Saídas R$, Total R$),
--   o comportamento de 0167 é o mesmo, byte a byte, exceto pela exclusão de percentual. A CTE
--   `por_rotulo` fica (é o marcador da 0167 na sonda). A tolerância Classe B da receita não muda.
--   MEDIDO EM PRODUÇÃO (30/09/2026, só-leitura): 83 documentos FATURAMENTO_24M, 16 com coluna de
--   ano, 1 com 'Variação %' (este) — o caso do probe é o único com o percentual; os outros 15 só
--   mudam de caminho (ano pela coluna em vez do rótulo) e dão a mesma soma quando rótulo e coluna
--   concordam (é o formato do fixture do book, conferido pelo reconciliacao.test.sql).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2) — Supabase/test/caixa_dfc_de_um_ano.test.sql, 21 asserts (contados
-- no log). Com as quatro funções de volta ao corpo anterior (0193, 0193, 0191, 0167), 17 reprovam
-- e 4 seguem passando (os controles: caixa com coluna divergente = 2, mesmo ano sem coluna = 1,
-- tolerância Classe B da receita = 1); contados sem parar no primeiro `raise`. Desligadas UMA A UMA:
-- caixa 8, receita 2, despfin 2, faturamento 6 (a soma dá 18 e não 17 porque um assert da receita
-- depende das duas correções). Nenhum assert existente mudou: a suíte inteira continua verde.
--
-- NÃO FAZ: não roda reconciliação nem recompute em caso nenhum; não é aplicada por estar escrita —
-- quem responde é a sonda contra o banco em que se está conectado:
--
--   select chave, migration, tipo, objeto, presente, detalhe, porque
--     from fn_instalacao_conferir() where not presente order by 1;
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (1) fn_reconciliar_caixa_bp_fluxo — REEMITIDA INTEIRA (corpo vigente 0193:96).
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
  -- 0196: o PERÍODO PRÓPRIO de cada documento (Balanço e DFC), lido uma vez fora do
  -- laço, e se ESTE ano do laço cai fora dele. Ver o cabeçalho da migration.
  v_bp_tipo      text;
  v_bp_ref       text;
  v_fx_tipo      text;
  v_fx_ref       text;
  v_bp_outro_ano boolean;
  v_fx_outro_ano boolean;
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
  select pe.tipo, pe.referencia into v_bp_tipo, v_bp_ref
    from documento d left join periodo pe on pe.id = d.periodo_id where d.id = v_doc_bp;
  select pe.tipo, pe.referencia into v_fx_tipo, v_fx_ref
    from documento d left join periodo pe on pe.id = d.periodo_id where d.id = v_doc_fx;

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    v_col_per := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_ver_bp, v_ano) end;
    -- 0196: Balanço SEM coluna de período (v_col_per nulo) deixava a linha valer para
    -- QUALQUER ano do laço. `fn_linha_vale_para_ano` (0195) responde se o PERÍODO
    -- PRÓPRIO do documento ancora o ano; se não, a sentinela E'\x01' — a mesma que
    -- a 0023 já usa para "documento com colunas, nenhuma é deste ano" — faz a busca
    -- não devolver nada e o motivo sair `sem_periodo_par` (contrato 0186/0188).
    v_bp_outro_ano := false;
    if v_ano is not null and v_col_per is null
       and not fn_linha_vale_para_ano(v_ver_bp, null, v_bp_tipo, v_bp_ref, v_ano) then
      v_col_per := E'\x01';
      v_bp_outro_ano := true;
    end if;
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
    -- 0196: o mesmo do Balanço, agora para a DFC — a DFC ANUAL de um exercício só tem
    -- periodo_coluna nulo e era lida como saldo final de 2024 e de 2025.
    v_fx_outro_ano := false;
    if v_ano is not null and v_col_per is null
       and not fn_linha_vale_para_ano(v_ver_fx, null, v_fx_tipo, v_fx_ref, v_ano) then
      v_col_per := E'\x01';
      v_fx_outro_ano := true;
    end if;
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
            case when v_bp_outro_ano then format('o Balanço é de %s — não traz este exercício', v_bp_ref)
                 when v_col_bp = E'\x01' then 'o Balanço não tem coluna deste exercício'
                 when v_col_ent = E'\x01' then 'o Balanço não tem coluna desta entidade'
                 else 'o Caixa/Disponível do Balanço não foi localizado' end end,
          case when v_saldo.id is null then
            case when v_fx_outro_ano then format('o Fluxo de Caixa é de %s — não traz este exercício', v_fx_ref)
                 when v_col_per = E'\x01' then 'o Fluxo de Caixa não tem coluna deste exercício'
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
    format('Caixa do Balanço vs Saldo final do Fluxo de Caixa em %s ano(s): %s.%s',
           v_n, array_to_string(v_partes, '; '),
           -- 0196 (regra 1): ano sem par não some calado — fica dito que não foi comparado.
           case when cardinality(v_faltas) > 0
                then ' Não comparado — ' || array_to_string(v_faltas, '; ') || '.' else '' end));
end;
$$;

-- -----------------------------------------------------------------------------
-- (2) fn_reconciliar_receita_dre_vs_faturamento — REEMITIDA INTEIRA (corpo vigente 0193:335).
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
  -- 0196: período PRÓPRIO da DRE e se este ano do laço cai fora dele.
  v_dre_tipo      text;
  v_dre_ref       text;
  v_dre_outro_ano boolean;
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
  select pe.tipo, pe.referencia into v_dre_tipo, v_dre_ref
    from documento d left join periodo pe on pe.id = d.periodo_id where d.id = v_doc_dre;

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    if v_ano is null then
      -- sem ano não há como recortar o mês. 0188: motivo GENÉRICO de propósito.
      v_motivos_ano := v_motivos_ano || 'precondicao_nao_satisfeita'::text;
      v_faltas := v_faltas || 'o período não tem ano, e sem ano não há como recortar os meses do faturamento'::text;
      continue;
    end if;
    v_col_per := fn_coluna_periodo_do_ano(v_ver_dre, v_ano);
    -- 0196: DRE SEM coluna de período valia para qualquer ano do laço, enquanto o
    -- faturamento é recortado POR ANO — a receita de um exercício saía contra os
    -- meses de outro. Ver o cabeçalho da migration.
    v_dre_outro_ano := false;
    if v_col_per is null
       and not fn_linha_vale_para_ano(v_ver_dre, null, v_dre_tipo, v_dre_ref, v_ano) then
      v_col_per := E'\x01';
      v_dre_outro_ano := true;
    end if;

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
          case when v_dre_outro_ano then format('a DRE é de %s — não traz este exercício', v_dre_ref)
               when v_col_per = E'\x01' then 'a DRE não tem coluna deste exercício'
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
    format('Receita Bruta da DRE vs faturamento mensal em %s ano(s): %s.%s',
           v_n, array_to_string(v_partes, '; '),
           case when cardinality(v_faltas) > 0
                then ' Não comparado — ' || array_to_string(v_faltas, '; ') || '.' else '' end));
end;
$$;

-- -----------------------------------------------------------------------------
-- (3) fn_reconciliar_despfin_dre_vs_divida — REEMITIDA INTEIRA (corpo vigente 0191:126).
-- -----------------------------------------------------------------------------
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
  -- 0196: período PRÓPRIO da DRE e se este ano do laço cai fora dele.
  v_dre_tipo      text;
  v_dre_ref       text;
  v_dre_outro_ano boolean;
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
  select pe.tipo, pe.referencia into v_dre_tipo, v_dre_ref
    from documento d left join periodo pe on pe.id = d.periodo_id where d.id = v_doc_dre;

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
    -- 0196: DRE SEM coluna de período valia para qualquer ano do laço (o corte da
    -- 0191 só olhava o lado do MAPA). Ver o cabeçalho da migration.
    v_dre_outro_ano := false;
    if v_ano is not null and v_col_per is null
       and not fn_linha_vale_para_ano(v_ver_dre, null, v_dre_tipo, v_dre_ref, v_ano) then
      v_col_per := E'\x01';
      v_dre_outro_ano := true;
    end if;

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
        case when v_dre_outro_ano then format('a DRE é de %s — não traz este exercício', v_dre_ref)
             when v_col_per = E'\x01' then 'a DRE não tem coluna deste exercício'
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
    format('Despesa Financeira da DRE vs juros do Mapa de Dívida em %s ano(s): %s.%s',
           v_n, array_to_string(v_partes, '; '),
           case when cardinality(v_faltas) > 0
                then ' Não comparado — ' || array_to_string(v_faltas, '; ') || '.' else '' end));
end;
$_$;

-- -----------------------------------------------------------------------------
-- (4) fn_somar_faturamento_ano — REEMITIDA INTEIRA (corpo vigente 0167:67).
-- -----------------------------------------------------------------------------
create or replace function fn_somar_faturamento_ano(
  p_documento_versao_id uuid,
  p_ano4 text,
  p_ano2 text
)
returns table(soma numeric, n_linhas integer)
language sql
stable
as $_$
  with modo as (
    -- O documento traz o ANO na coluna? ('2024', '2025', '31/12/2024'...) Só então o
    -- ano sai da `periodo_coluna`; colunas de CATEGORIA (Saídas R$, Total R$) não
    -- ancoram ano nenhum e ficam no modo do rótulo, o de sempre (0167).
    select exists (
      select 1 from campo_extraido ce
      where ce.documento_versao_id = p_documento_versao_id
        and ce.periodo_coluna is not null
        and cardinality(fn_anos_texto(ce.periodo_coluna)) > 0
    ) as ano_na_coluna
  ),
  candidatos as (
    select ce.chave, ce.periodo_coluna, ce.valor_num
    from campo_extraido ce cross join modo
    where ce.documento_versao_id = p_documento_versao_id
      and ce.valor_num is not null
      and (
        case when modo.ano_na_coluna then
          -- 0196: a célula é do ano pedido quando a COLUNA diz que é; o rótulo só
          -- precisa parecer um mês (o "jan/2024 — jan/2025" traz os DOIS anos, e a
          -- linha "Ticket médio…" não é mês nenhum).
          fn_anos_texto(ce.periodo_coluna) && fn_anos_texto(p_ano4)
          and (
            position(p_ano4 in fn_normalizar_texto(ce.chave)) > 0
            or fn_normalizar_texto(ce.chave) ~ ('[/. -]' || p_ano2 || '($|[^0-9])')
            or fn_normalizar_texto(ce.chave) ~ '^(jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)'
          )
        else
          position(p_ano4 in fn_normalizar_texto(ce.chave)) > 0
          or fn_normalizar_texto(ce.chave) ~ ('[/. -]' || p_ano2 || '($|[^0-9])')
        end
      )
      and fn_normalizar_texto(ce.chave) not like '%total%'
      and fn_normalizar_texto(ce.chave) not like '%acumulad%'
      and fn_normalizar_texto(ce.chave) not like '%media%'
      and fn_normalizar_texto(ce.chave) not like '%médi%'
      -- 0196: coluna de PERCENTUAL nunca é dinheiro (a 'Variação %' do relatório de
      -- 3 colunas somava -41,2 a -6,7 ao faturamento de cada mês).
      and position('%' in coalesce(ce.periodo_coluna, '')) = 0
      and fn_normalizar_texto(coalesce(ce.periodo_coluna, '')) not like '%variac%'
  ),
  -- UM VALOR POR MÊS (0167) — inalterado.
  por_rotulo as (
    select
      chave,
      coalesce(
        max(valor_num) filter (where fn_normalizar_texto(periodo_coluna) like '%total%'),
        sum(valor_num)
      ) as valor
    from candidatos
    group by chave
  )
  select coalesce(sum(valor), 0)::numeric, count(*)::int from por_rotulo;
$_$;

comment on function fn_somar_faturamento_ano(uuid, text, text) is
  'Soma o faturamento de um ano, UM VALOR POR MÊS. 0167: a categoria mora em periodo_coluna '
  '(Saídas/Serviços/Outros/Total) e a chave repete o mês nas quatro — com coluna de total, ela manda. '
  '0196: quando as colunas do documento são ANOS (2024, 2025), o ano sai da COLUNA — o rótulo '
  '"jan/2024 — jan/2025" traz os dois anos e somava as duas colunas e a Variação % juntas; coluna '
  'de percentual nunca entra na soma.';

comment on function fn_reconciliar_caixa_bp_fluxo(uuid, uuid, uuid, numeric, numeric) is
  '0196: Balanço e DFC sem periodo_coluna só valem para o ano que o PERÍODO PRÓPRIO do documento ancora (fn_linha_vale_para_ano); ano sem linha válida do outro lado é sem_periodo_par, não divergência. Tolerância na base com piso de arredondamento (0193).';

grant execute on function fn_reconciliar_caixa_bp_fluxo(uuid, uuid, uuid, numeric, numeric) to authenticated;
grant execute on function fn_reconciliar_receita_dre_vs_faturamento(uuid, uuid, uuid, numeric, numeric) to authenticated;
grant execute on function fn_reconciliar_despfin_dre_vs_divida(uuid, uuid, uuid, numeric, numeric) to authenticated;
grant execute on function fn_somar_faturamento_ano(uuid, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Catálogo da sonda — requisitos de CORPO (marcador é código, não comentário:
-- sonda_marcador_e_codigo.test.sql). As assinaturas não mudam.
--
-- ORDEM 848…851: a 0195/0183 usam até 847.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, porque, severidade, ordem) values

  ('caixa_dfc_de_um_ano', '0196', 'corpo', 'fn_reconciliar_caixa_bp_fluxo',
   'fn_linha_vale_para_ano(v_ver_fx, null, v_fx_tipo, v_fx_ref, v_ano)',
   'Sem este corpo a DFC de UM exercício (periodo_coluna nulo) vale para qualquer ano do laço: o Balanço '
   '"multi 24,25" (Disponível 2024 = 4.840) sai comparado com a DFC anual 2025 (500) e grava divergente '
   'para 2024 — pendência Classe A FALSA de R$ 4,34 mi. MEDIDO EM PRODUÇÃO (30/09/2026, só-leitura): 5 '
   'pendências abertas com este arranjo em 4 casos (bb37f726 entre eles).',
   'importante', 848),

  ('receita_dre_de_um_ano', '0196', 'corpo', 'fn_reconciliar_receita_dre_vs_faturamento',
   'fn_linha_vale_para_ano(v_ver_dre, null, v_dre_tipo, v_dre_ref, v_ano)',
   'Sem este corpo a DRE de UM exercício (sem periodo_coluna) vale como a Receita Bruta de qualquer ano '
   'do laço, e é comparada com o faturamento daquele ano: zona_cinzenta falsa em 2024 com a receita de '
   '2025. MEDIDO EM PRODUÇÃO (30/09/2026): 3 das 25 últimas reconciliações de receita leem uma DRE sem '
   'coluna em mais anos que o período dela, e as 3 não são ok.',
   'importante', 849),

  ('despfin_dre_de_um_ano', '0196', 'corpo', 'fn_reconciliar_despfin_dre_vs_divida',
   'fn_linha_vale_para_ano(v_ver_dre, null, v_dre_tipo, v_dre_ref, v_ano)',
   'Sem este corpo a DRE de UM exercício (sem periodo_coluna) vale como a Despesa Financeira de qualquer '
   'ano que o Mapa de Dívida cubra (o corte da 0191 só olha o mapa). Latente hoje: 0 de 17 '
   'reconciliações de despfin em produção (30/09/2026).',
   'importante', 850),

  ('faturamento_ano_pela_coluna', '0196', 'corpo', 'fn_somar_faturamento_ano',
   'fn_anos_texto(ce.periodo_coluna) && fn_anos_texto(p_ano4)',
   'Sem este corpo o ano do faturamento sai do RÓTULO: num relatório "jan/2024 — jan/2025" com as colunas '
   '2024, 2025 e Variação %, cada ano soma as três colunas (321.579,6 em vez dos 183.480 de 2024, medido '
   'no caso bb37f726, 30/09/2026) e a receita do ano sai zona_cinzenta contra um faturamento que não é '
   'dele.',
   'importante', 851)

on conflict (chave) do update
  set migration = excluded.migration,
      tipo      = excluded.tipo,
      objeto    = excluded.objeto,
      marcador  = excluded.marcador,
      porque    = excluded.porque,
      severidade = excluded.severidade,
      ordem     = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0196', revisado_em = current_date,
       observacao = 'A 0196 reemite fn_reconciliar_caixa_bp_fluxo, fn_reconciliar_receita_dre_vs_faturamento e '
         'fn_reconciliar_despfin_dre_vs_divida para que documento SEM periodo_coluna só valha para o ano que o '
         'PERÍODO PRÓPRIO dele ancora (fn_linha_vale_para_ano, 0195) — o vício 2 da 0194/0195, agora nas três '
         'checagens por ano que faltavam; e fn_somar_faturamento_ano para tirar o ano da COLUNA quando as colunas '
         'são anos (o rótulo "jan/2024 — jan/2025" somava 2024+2025+Variação %). Medido em produção (30/09/2026, '
         'só-leitura): 5 pendências abertas de caixa com o arranjo, em 4 casos; 3 de 25 receitas; 0 de 17 '
         'despfin (latente); 1 documento de faturamento com coluna de percentual. Catalogado pelo corpo '
         '(caixa_dfc_de_um_ano, receita_dre_de_um_ano, despfin_dre_de_um_ano, faturamento_ano_pela_coluna) — '
         'as assinaturas não mudam. fn_reconciliar_ativo_passivo_pl auditada e NÃO tocada (compara dentro do '
         'mesmo documento).'
 where id = true;
