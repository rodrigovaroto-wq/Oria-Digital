-- =============================================================================
-- 0192 — O OK QUE MATAVA A DIVERGÊNCIA IRMÃ
--
-- O DEFEITO, medido em produção (25/09/2026, SOMENTE LEITURA — nenhuma escrita,
-- nenhum apply). `fn_registrar_reconciliacao` (corpo vigente até aqui: 0188:343)
-- acha a pendência aberta por (caso, motivo, entidade, PERÍODO COMPATÍVEL via
-- `fn_periodos_compativeis`, não igual — 0186:462). Duas checagens da MESMA
-- rodada (`fn_reconciliar_caso`, 0152) para o MESMO tipo/entidade, com períodos
-- compatíveis (ex.: Balanço `multi` "24,25" e Balanço `anual` "12M25" — anos
-- {2024,2025} ∩ {2025} ≠ ∅), caem na MESMA pendência. E `fn_reconciliar_caso`
-- varre `select distinct d.entidade_id, d.periodo_id from documento` SEM
-- `order by` — a ordem física/hash decide qual checagem chega primeiro.
--
-- Resultado: a ORDEM decide se a divergência termina ABERTA ou RESOLVIDA.
--
-- Teste v33 (e v35, idêntico), 31/07/2026, `caixa_bp_fluxo`, mesma entidade,
-- mesma transação (`criado_em` igual): Balanço "24,25" → `divergente`,
-- `divergencia_abs = 4.340.000`; Balanço "12M25" → `ok`. A pendência
-- `divergencia_reconciliacao` do "24,25" foi criada e resolvida no MESMO
-- instante (`criada_em = resolvida_em`, `resolvida_por = 'sistema:reconciliacao'`):
-- o `ok` de 2025 apagou uma divergência que era de 2024. No MESMO banco, o
-- teste AMOBELEZA (14/09/2026, receita, divergência de 64 mi + ok compatível)
-- ficou ABERTA — porque lá a divergente veio DEPOIS. Mesmo arranjo, dois
-- desfechos, só por causa da ordem.
--
-- CONTAGEM GERAL: 41 pendências `reconciliacao:%` nascidas e mortas no mesmo
-- instante. 37 são `precondicao_nao_satisfeita` — na maioria o laço de retry
-- de UMA chave só (período 1 sem par abre, período 2 conclui `ok` e fecha, o
-- comportamento DESENHADO da 0152, que esta migration NÃO MUDA). 4 são
-- `divergencia_reconciliacao` — essas sim o defeito: um achado que CONCLUIU
-- divergente sendo apagado por um `ok` (ou uma pré-condição) de OUTRO período
-- compatível, na mesma rodada.
--
-- A CORREÇÃO, em duas partes.
--
-- (1) `fn_registrar_reconciliacao`, REEMITIDA INTEIRA (corpo vigente 0188:343)
--   — nunca `replace` de texto (`.claude/memory/nunca-corrigir-funcao-por-
--   replace.md`). NA MESMA TRANSAÇÃO (mesma rodada — `now()` é fixo do início
--   da transação, e `fn_reconciliar_caso` roda inteira numa chamada só), um
--   achado que CONCLUIU divergente PREVALECE: antes de resolver a pendência
--   (ramo `elsif v_pendencia_id is not null`) e antes de sobrescrever a
--   `descricao` de uma pendência já aberta com o texto de um achado de
--   PRÉ-CONDIÇÃO, a função verifica se já existe, em `reconciliacao`, outra
--   linha desta MESMA transação (`criado_em = now()`, excluindo a que acabou
--   de inserir) do mesmo caso/tipo/entidade, `resultado in ('divergente',
--   'divergencia', 'zona_cinzenta')`, com período compatível com o da
--   pendência. Se existir: NÃO resolve, e NÃO troca a descrição da divergência
--   pela de pré-condição.
--
--   O QUE NÃO MUDA: pré-condição seguida de `ok` da MESMA chave — o retry
--   desenhado pela 0152 — continua fechando normalmente, porque nesse caso não
--   há linha `divergente`/`divergencia`/`zona_cinzenta` concorrente nenhuma na
--   rodada; a guarda só dispara quando ela existe. As 37 pendências de
--   pré-condição nascidas-e-mortas continuam nascendo e morrendo — é o
--   comportamento certo, e não é o que esta migration mexe.
--
--   O TETO DECLARADO: "mesma rodada" aqui é "mesma transação", que é o início
--   dela (`now()` em plpgsql é o `statement timestamp` fixo por transação,
--   não por chamada). Cobre `fn_reconciliar_caso` (uma chamada n8n, uma
--   transação) e `fn_reconciliar_chaves_do_documento` chamada sozinha dentro
--   da MESMA transação de quem a invoca. NÃO cobre duas chamadas de
--   `fn_reconciliar_chaves_do_documento` em transações SEPARADAS para o mesmo
--   caso (ex.: reconciliar por documento, um documento por vez, cada um sua
--   própria transação) — aí a proteção volta a depender da ordem cronológica
--   entre transações, como antes. Isso é o mesmo teto que "mesma rodada" já
--   tinha antes desta migration para qualquer coisa que dependa de `now()`;
--   fechar o caso entre-transações exigiria um identificador de rodada
--   explícito (`lote_execucao`?), que é mudança de contrato maior e fora do
--   escopo deste defeito.
--
-- (2) `fn_reconciliar_caso`, REEMITIDA INTEIRA (corpo vigente 0152:599 — grep
--   confirma que nenhuma migration entre a 0152 e esta a reemitiu). `order by`
--   em TODO laço `select distinct ... from documento`: sem ele, a ORDEM em que
--   as chaves (entidade, período) chegam à guarda de (1) — e portanto qual
--   período a pendência acaba carregando quando mais de um é compatível — não
--   é determinística. Com (1), o desfecho ABERTO/RESOLVIDO deixa de depender
--   da ordem; (2) é só determinismo de QUAL período a pendência mostra, não
--   mais uma correção de segurança. `fn_reconciliar_chaves_do_documento`
--   (0152:394) já ordena o laço de período interno
--   (`array_agg(... order by (p.id = p_periodo_id) desc, p.referencia)`) — não
--   precisa de mudança.
--
-- O QUE ESTA MIGRATION NÃO FAZ.
--   • Não roda reconciliação nem recompute em caso nenhum. As 4 pendências já
--     nascidas-e-mortas em produção continuam assim até a próxima rodada de
--     cada caso — corrigir o já gravado é um backfill à parte que esta
--     migration não faz (e que precisaria da mesma medição de alcance que a
--     0179/0183 pulou — ver `.claude/memory/aplicar-migration-em-producao-
--     pela-api.md`).
--   • Não muda o CONTRATO de motivos da 0186/0188, o vocabulário de
--     `p_resultado`, o dial de influência (0127), nem o ramo de sombra.
--   • Não é aplicada em produção por estar escrita. Quem responde é a sonda:
--
--       select chave, migration, tipo, objeto, presente, detalhe, porque
--         from fn_instalacao_conferir() where not presente order by 1;
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (1) fn_registrar_reconciliacao — REEMITIDA INTEIRA a partir do corpo vigente
-- (0188:343). ÚNICA mudança de comportamento: a declaração de
-- `v_pendencia_periodo_id` e `v_divergencia_concorrente`, a query que a
-- calcula, e as duas guardas que a usam (marcadas "0192" abaixo). Todo o
-- resto — vocabulário, achatamento, `v_res_retorno`, dial/sombra, evento de
-- auditoria — é cópia literal.
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_reconciliacao(
  p_caso_id       uuid,
  p_entidade_id   uuid,
  p_periodo_id    uuid,
  p_tipo          text,
  p_classe        text,
  p_documento_id  uuid,
  p_fonte_a       jsonb,
  p_fonte_b       jsonb,
  p_resultado     text,
  p_divergencia_abs numeric,
  p_divergencia_pct numeric,
  p_materialidade jsonb,
  p_descricao     text
)
returns jsonb
language plpgsql
as $$
declare
  v_reconciliacao_id uuid;
  v_pendencia_id     uuid;
  v_motivo           text := 'reconciliacao:' || p_tipo;
  -- 0186: O CONTRATO — todo motivo que o achatamento reconhece como "a
  -- checagem não concluiu". `resultado` sai `precondicao_nao_satisfeita` para
  -- QUALQUER um destes; o valor ORIGINAL vai para `motivo_precondicao` (ver
  -- abaixo). Desde a 0188 os cinco têm emissor.
  v_motivos_precondicao text[] := array[
    'documento_ausente', 'precondicao_nao_satisfeita',
    'linha_nao_localizada', 'unidade_divergente', 'sem_periodo_par'
  ];
  -- CORRIGIDO após revisão independente (achado mais grave: um p_resultado
  -- fora do vocabulário virava 'a checagem concluiu' — precondicoes_ok =
  -- TRUE, afirmação positiva e FALSA, medido passando 'linha_nao_localizado',
  -- uma letra fora do contrato). Todo valor que QUALQUER `fn_reconciliar_*`
  -- hoje realmente emite (grep em todas as migrations) mais os três
  -- reservados do CONTRATO acima — nada além disso é reconhecido.
  v_vocabulario_resultado text[] := array['ok', 'divergente', 'divergencia', 'zona_cinzenta']
                                       || v_motivos_precondicao;
  -- 'documento_ausente' é um resultado NOSSO, para decidir a pendência; no log
  -- ele é gravado como pré-condição não satisfeita (é o que ele é).
  v_res_log          text := case when p_resultado = any(v_motivos_precondicao)
                                  then 'precondicao_nao_satisfeita' else p_resultado end;
  -- motivo_precondicao: o valor ORIGINAL, antes do achatamento acima — NULL
  -- quando a checagem concluiu (v_res_log não é 'precondicao_nao_satisfeita').
  -- Quando p_resultado já chega como 'precondicao_nao_satisfeita' (a função de
  -- checagem não detalhou o motivo), grava esse mesmo valor: é honesto — "sem
  -- motivo específico" é informação, não lacuna.
  v_motivo_precondicao text := case when v_res_log = 'precondicao_nao_satisfeita'
                                     then p_resultado else null end;
  -- 0188: O QUE A FUNÇÃO DEVOLVE em `resultado`. Os despachantes (0152)
  -- decidem se tentam o PRÓXIMO período por
  -- `exit when v_res->>'resultado' <> 'precondicao_nao_satisfeita'`. Até a
  -- 0187 isso era o p_resultado cru, e só dois valores de precondição
  -- existiam: 'documento_ausente' (para o laço — falta a contraparte, outro
  -- período não a cria) e o genérico (segue o laço). Os três motivos da 0188
  -- são refinamentos do GENÉRICO, então devolvem o genérico: o laço continua
  -- exatamente como antes. 'documento_ausente' continua saindo cru.
  v_res_retorno      text := case when p_resultado in ('linha_nao_localizada',
                                                       'unidade_divergente',
                                                       'sem_periodo_par')
                                  then 'precondicao_nao_satisfeita' else p_resultado end;
  -- 0127: a decisão passa para o corpo, porque agora ela depende do DIAL da
  -- classe — e o dial não se lê no declare sem esconder a regra.
  --
  -- 0186: ESTA LINHA NÃO MUDA. `documento_ausente` continua sendo o ÚNICO
  -- motivo de precondição que NÃO abre pendência — é cobrança do checklist do
  -- Kit Básico, não achado de revisão (0023, reafirmado pela 0127). Qualquer
  -- motivo novo do array acima que não seja 'documento_ausente' cai do lado
  -- de ABRE pendência por esta mesma linha, sem precisar tocá-la: documento
  -- presente e algo não localizado é sempre achado acionável, mesmo quando o
  -- motivo específico ainda não existe (default seguro).
  v_divergente       boolean := p_resultado not in ('ok', 'documento_ausente');
  v_abre_pendencia   boolean;
  v_estagio_dial     text;
  v_influencia       boolean;
  -- 0192: o período que a pendência JÁ CARREGA (pode ser diferente de
  -- p_periodo_id — a busca acima acha por compatibilidade, não igualdade), e
  -- se, NA MESMA TRANSAÇÃO, outra checagem do mesmo caso/tipo/entidade já
  -- CONCLUIU divergente para um período compatível com ele.
  v_pendencia_periodo_id    uuid;
  v_divergencia_concorrente boolean := false;
begin
  -- 0186 (achado 1 da revisão): p_resultado FORA do vocabulário conhecido
  -- REPROVA ALTO — não vira 'a checagem concluiu' por acidente de digitação.
  -- `raise` em vez de `check constraint` na coluna `resultado`: a tabela tem
  -- histórico com valores legados (ok, divergente, divergencia, zona_cinzenta,
  -- precondicao_nao_satisfeita) e um check retroativo recusaria linha antiga
  -- ou faria o `alter table` falhar — o raise protege só a ESCRITA daqui pra
  -- frente, sem tocar no que já está gravado.
  if not (p_resultado = any(v_vocabulario_resultado)) then
    raise exception 'fn_registrar_reconciliacao: p_resultado=% fora do vocabulario conhecido (%)',
      p_resultado, array_to_string(v_vocabulario_resultado, ', ');
  end if;

  -- 0127: O DIAL DA CLASSE DECIDE SE O ACHADO CHEGA À FILA DE ALGUÉM.
  --
  -- `reconciliacao_classe_bc` declarava N0 — "roda, registra a saída, mas NÃO
  -- influencia decisão" (Arquitetura do Sistema/1 Visão e Doutrina/01) — e abria pendência: as checagens B passam 'B'
  -- para cá e esta função nunca olhou a classe. Pendência entra na fila do painel
  -- e é contada na avaliação do Portão 2; isso é influenciar. O comportamento era
  -- N1, que é o teto dela — não era inseguro, era MAL DECLARADO.
  --
  -- Note que o registro em `reconciliacao` acontece SEMPRE, inclusive em N0: "roda
  -- e registra" é a primeira metade da definição de sombra, e é ela que permite
  -- medir um estágio antes de confiar nele.
  v_estagio_dial := case when upper(coalesce(p_classe, 'A')) = 'A'
                         then 'reconciliacao_classe_a'
                         else 'reconciliacao_classe_bc' end;
  v_influencia := fn_dial_influencia(v_estagio_dial);
  v_abre_pendencia := v_divergente and v_influencia;

  insert into reconciliacao
    (caso_id, entidade_id, periodo_id, tipo, classe, fonte_a, fonte_b,
     precondicoes_ok, resultado, motivo_precondicao, divergencia_abs, divergencia_pct, materialidade)
  values (
    p_caso_id, p_entidade_id, p_periodo_id, p_tipo, p_classe, p_fonte_a, p_fonte_b,
    v_res_log <> 'precondicao_nao_satisfeita', v_res_log, v_motivo_precondicao,
    p_divergencia_abs, p_divergencia_pct, p_materialidade
  )
  returning id into v_reconciliacao_id;

  select id, periodo_id into v_pendencia_id, v_pendencia_periodo_id from pendencia
  where caso_id = p_caso_id and motivo = v_motivo
    and coalesce(entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
      = coalesce(p_entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
    -- Período COMPATÍVEL, não igual: a mesma checagem chega por dois documentos
    -- com granularidade diferente (DRE "multi 24,25" × Faturamento "L24M") e sem
    -- isso o mesmo achado abriria duas pendências.
    and (periodo_id is not distinct from p_periodo_id
         or fn_periodos_compativeis(periodo_id, p_periodo_id))
    and estado <> 'resolvida'
  order by criada_em
  limit 1;

  -- 0192: O OK (OU A PRÉ-CONDIÇÃO) QUE MATAVA A DIVERGÊNCIA IRMÃ. Antes de
  -- decidir se resolve ou sobrescreve a descrição da pendência achada acima,
  -- confere se OUTRA linha desta MESMA transação (`criado_em = now()` —
  -- `fn_reconciliar_caso`, 0152, roda a rodada inteira numa chamada só) do
  -- mesmo caso/tipo/entidade já CONCLUIU divergente (`divergente`,
  -- `divergencia` ou `zona_cinzenta`) para um período compatível com o da
  -- pendência. Sem isto: duas checagens da mesma rodada, mesmo tipo/entidade,
  -- períodos compatíveis (Balanço "multi 24,25" × "anual 12M25", anos
  -- {2024,2025} ∩ {2025} ≠ ∅) caem na MESMA pendência por período COMPATÍVEL
  -- (linha acima, desde a 0023) — e SÓ A ORDEM em que `fn_reconciliar_caso`
  -- visita as chaves decide se o `ok` de um período RESOLVE a divergência do
  -- outro. Medido em produção (25/09/2026): teste v33/v35, `caixa_bp_fluxo`,
  -- divergência de 2024 (4.340.000) criada e resolvida no MESMO instante pelo
  -- `ok` de 2025. Só roda a query quando há pendência a proteger.
  if v_pendencia_id is not null then
    select exists (
      select 1 from (
        -- O ÚLTIMO achado desta rodada, por período OUTRO que o desta chamada
        -- (`distinct on` + `cmin` — o contador de COMANDO dentro da própria
        -- transação, que cresce a cada INSERT desta função, mesmo com
        -- `criado_em` empatado — não há coluna serial em `reconciliacao` para
        -- ordenar por "chegou depois" dentro do mesmo instante). SÓ O ÚLTIMO
        -- por período, não qualquer um: uma checagem pode rodar a MESMA chave
        -- (mesmo p_periodo_id) MAIS DE UMA VEZ na mesma transação — um teste
        -- que reconcilia, corrige o dado, reconcilia de novo, tudo antes do
        -- commit (`secao_fecha.test.sql`, "recolocada a linha, a pendência
        -- auto-resolve"; `reconciliacao.test.sql`, "saldo corrigido") — e aí a
        -- tentativa ANTERIOR (já divergente) da MESMA checagem, de um período
        -- DIFERENTE do atual mas que TAMBÉM já foi corrigida nesta rodada, não
        -- pode contar como irmã viva. Só o estado MAIS RECENTE de cada período
        -- decide.
        select distinct on (r.periodo_id) r.periodo_id, r.resultado
        from reconciliacao r
        where r.caso_id = p_caso_id and r.tipo = p_tipo
          and coalesce(r.entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
            = coalesce(p_entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
          and r.criado_em = now()
          and r.periodo_id is distinct from p_periodo_id
        order by r.periodo_id, r.cmin::text::int desc
      ) ultimo_por_periodo
      where ultimo_por_periodo.resultado in ('divergente', 'divergencia', 'zona_cinzenta')
        and (ultimo_por_periodo.periodo_id is not distinct from v_pendencia_periodo_id
             or fn_periodos_compativeis(ultimo_por_periodo.periodo_id, v_pendencia_periodo_id))
    ) into v_divergencia_concorrente;
  end if;

  if v_abre_pendencia then
    if v_pendencia_id is null then
      insert into pendencia
        (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao,
         documento_id, entidade_id, periodo_id, motivo)
      values (
        p_caso_id, 'reconciliacao',
        case when v_res_log = 'precondicao_nao_satisfeita' then 'precondicao_nao_satisfeita'
             else 'divergencia_reconciliacao' end::pendencia_tipo,
        'importante', true, p_descricao, p_documento_id, p_entidade_id, p_periodo_id, v_motivo
      )
      returning id into v_pendencia_id;
    elsif v_res_log = 'precondicao_nao_satisfeita' and v_divergencia_concorrente then
      -- 0192: este achado é PRÉ-CONDIÇÃO, e uma divergência IRMÃ da mesma
      -- rodada já está gravada em período compatível — não troca a descrição
      -- da divergência pela de "não especificado"/checklist. A pendência
      -- continua com o texto e o `tipo` da divergência.
      null;
    else
      update pendencia set descricao = p_descricao where id = v_pendencia_id;
    end if;
  elsif v_divergente and not v_influencia then
    -- 0127: SOMBRA COM DIVERGÊNCIA PRESENTE — e este ramo existe para não mentir.
    --
    -- Sem ele, este caso cairia no `elsif` de baixo e a pendência aberta seria
    -- marcada "resolvida por sistema:reconciliacao". Mas o sintoma NÃO sumiu: o
    -- estágio foi silenciado. Resolver aqui escreveria na trilha que o problema
    -- acabou, quando o que acabou foi o direito daquele estágio de falar — e a
    -- trilha é append-only justamente para não permitir esse tipo de reescrita.
    --
    -- Então: registra em sombra, e deixa em paz a pendência que um humano já pode
    -- estar tratando.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:reconciliacao', 'reconciliacao_em_sombra',
              'reconciliacao:' || v_reconciliacao_id,
              jsonb_build_object('estagio', v_estagio_dial, 'classe', p_classe,
                                 'tipo', p_tipo, 'resultado', p_resultado,
                                 'divergencia_abs', p_divergencia_abs,
                                 'pendencia_preexistente', v_pendencia_id,
                                 'porque', 'estagio em N0: registra e nao abre pendencia (Arquitetura do Sistema/1 Visão e Doutrina/01). '
                                           'Pendencia anterior, se existe, NAO foi resolvida: o '
                                           'sintoma nao sumiu, o estagio foi silenciado.'));

  elsif v_pendencia_id is not null then
    if v_divergencia_concorrente then
      -- 0192: este achado CONCLUIU (ok/documento_ausente), mas uma divergência
      -- IRMÃ da mesma rodada, em período compatível, ainda está de pé — não
      -- resolve. O `ok` de um período não apaga a divergência de outro.
      null;
    else
      -- Sumiu o sintoma (reextração corrigiu, ou a pendência era falsa e a regra
      -- nova não a emite mais): fecha. Não escreve número nenhum em base viva.
      update pendencia set estado = 'resolvida', resolvida_em = now(),
             resolvida_por = 'sistema:reconciliacao'
      where id = v_pendencia_id;
      v_pendencia_id := null;
    end if;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:reconciliacao', 'reconciliacao_' || p_tipo,
            'reconciliacao:' || v_reconciliacao_id,
            jsonb_build_object('resultado', p_resultado, 'divergencia_abs', p_divergencia_abs));

  return jsonb_build_object(
    'reconciliacao_id', v_reconciliacao_id, 'tipo', p_tipo,
    'resultado', v_res_retorno, 'motivo_precondicao', v_motivo_precondicao,
    'pendencia_id', v_pendencia_id
  );
end;
$$;

comment on function fn_registrar_reconciliacao(uuid, uuid, uuid, text, text, uuid, jsonb, jsonb, text,
  numeric, numeric, jsonb, text) is
  'Registro unificado de reconciliação (0023), motivo fino por pré-condição (0186/0188). 0192: '
  'dentro da MESMA transação (mesma rodada de fn_reconciliar_caso), um achado que CONCLUIU '
  'divergente/divergencia/zona_cinzenta prevalece — não resolve e não perde a descrição para um '
  'achado de pré-condição/ok de OUTRO período compatível chegado na mesma rodada.';

-- -----------------------------------------------------------------------------
-- (2) fn_reconciliar_caso — REEMITIDA INTEIRA a partir do corpo vigente
-- (0152:599; grep confirma que nenhuma migration entre a 0152 e esta a
-- reemitiu). ÚNICA mudança: `order by` em cada laço `select distinct ... from
-- documento` — determinismo de qual período a pendência carrega quando mais
-- de um é compatível. Com (1) acima, o ABERTO/RESOLVIDO já não depende da
-- ordem; isto é só reprodutibilidade (dois `run.sh` do mesmo fixture não
-- podiam divergir por ordem física de tabela).
-- -----------------------------------------------------------------------------
create or replace function fn_reconciliar_caso(p_caso_id uuid)
returns jsonb language plpgsql as $$
-- 0152: cada checagem sobre a SUA chave.
-- 0192: `order by` em cada laço — determinismo de qual período a pendência
-- carrega (a guarda de fn_registrar_reconciliacao já não depende da ordem
-- para decidir aberto/resolvido; isto é só reprodutibilidade).
declare
  v_k          record;
  v_per        uuid;
  v_res        jsonb;
  v_checagens  jsonb := '[]'::jsonb;
  v_chamadas   int := 0;
  v_documentos int := 0;
  c_arvore     constant text[] := array['BALANCO','BALANCETE','COMBINADO'];
  c_fluxo      constant text[] := array['BALANCO','BALANCETE','COMBINADO','FLUXO_CAIXA'];
  c_receita    constant text[] := array['DRE','FATURAMENTO_24M'];
  c_despfin    constant text[] := array['DRE','MAPA_DIVIDA'];
  c_mutuos     constant text[] := array['MUTUOS','BALANCO','COMBINADO','DF_AUDITADA'];
  c_intra      constant text[] := array['BALANCO','BALANCETE','DF_AUDITADA'];
  c_conflito   constant text[] := array['BALANCO','BALANCETE','COMBINADO','DF_AUDITADA','DRE',
                                        'FLUXO_CAIXA','DMPL','DVA','NOTAS_EXPL'];
begin
  select count(*) into v_documentos from documento where caso_id = p_caso_id;

  -- ---- (entidade, período), com laço de período -----------------------------
  for v_k in select distinct d.entidade_id, d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_arvore)
             order by d.entidade_id, d.periodo_id loop
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_ativo_passivo_pl(p_caso_id, v_k.entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.entidade_id, d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_fluxo)
             order by d.entidade_id, d.periodo_id loop
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_caixa_bp_fluxo(p_caso_id, v_k.entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.entidade_id, d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_receita)
             order by d.entidade_id, d.periodo_id loop
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_receita_dre_vs_faturamento(p_caso_id, v_k.entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.entidade_id, d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_despfin)
             order by d.entidade_id, d.periodo_id loop
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_despfin_dre_vs_divida(p_caso_id, v_k.entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  -- ---- só (período) — mútuos e intragrupo são do GRUPO, não da empresa ------
  for v_k in select distinct d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_mutuos)
             order by d.periodo_id loop
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_mutuos(p_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_intra)
             order by d.periodo_id loop
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_intragrupo(p_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  -- ---- só (entidade) — sem período nenhum ----------------------------------
  for v_k in select distinct d.entidade_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_arvore)
             order by d.entidade_id loop
    v_checagens := v_checagens
      || jsonb_build_array(fn_reconciliar_duplicidade(p_caso_id, v_k.entidade_id));
    v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.entidade_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_conflito)
             order by d.entidade_id loop
    v_checagens := v_checagens
      || jsonb_build_array(fn_reconciliar_versoes_do_periodo(p_caso_id, v_k.entidade_id));
    v_chamadas := v_chamadas + 1;
  end loop;

  return jsonb_build_object(
    'executado', true, 'caso_id', p_caso_id,
    'documentos', v_documentos, 'chamadas', v_chamadas,
    'checagens', v_checagens);
end;
$$;

comment on function fn_reconciliar_caso(uuid) is
  'Roda cada uma das oito checagens de reconciliação sobre a SUA chave (0152). 0192: `order by` em '
  'cada laço `select distinct` — determinismo de qual período a pendência carrega quando mais de um '
  'é compatível; o aberto/resolvido em si já não depende da ordem (guarda em fn_registrar_reconciliacao).';

grant execute on function fn_registrar_reconciliacao(uuid, uuid, uuid, text, text, uuid, jsonb, jsonb,
  text, numeric, numeric, jsonb, text) to authenticated;
grant execute on function fn_reconciliar_caso(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Catálogo da sonda — o requisito de CORPO que prova que a guarda está
-- instalada (a assinatura das duas funções não muda: elas continuam provando
-- só que a função EXISTE). Marcador é código, não comentário
-- (`sonda_marcador_e_codigo.test.sql` exige isso para todo marcador novo de
-- tipo `corpo`).
--
-- ORDEM 832: a 0190 usa 830 e a 0191 usa 831.
-- -----------------------------------------------------------------------------

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, porque, severidade, ordem) values

  ('ok_nao_mata_divergencia_irma', '0192', 'corpo', 'fn_registrar_reconciliacao',
   'v_divergencia_concorrente',
   'Sem esta guarda, duas checagens da mesma rodada (fn_reconciliar_caso) para o mesmo caso/tipo/'
   'entidade, com períodos COMPATÍVEIS (ex.: Balanço multi "24,25" x anual "12M25"), caem na MESMA '
   'pendência por período compatível — e a ORDEM em que a rodada visitou as chaves decide se um '
   '''ok'' de um período RESOLVE a divergência gravada pelo outro. Medido em produção (25/09/2026, '
   'somente leitura): pendência divergencia_reconciliacao criada e resolvida no MESMO instante, '
   '4 casos de 41 pendências reconciliacao:% nascidas-e-mortas na mesma rodada.',
   'importante', 832)

on conflict (chave) do update
  set migration = excluded.migration,
      tipo      = excluded.tipo,
      objeto    = excluded.objeto,
      marcador  = excluded.marcador,
      porque    = excluded.porque,
      severidade = excluded.severidade,
      ordem     = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0192', revisado_em = current_date,
       observacao = 'A 0192 reemite fn_registrar_reconciliacao e fn_reconciliar_caso para fechar a '
         'janela em que um achado que CONCLUIU (ok/pré-condição) de um período apagava, na mesma '
         'rodada, a divergência gravada por um período compatível: agora um achado divergente/'
         'divergencia/zona_cinzenta concorrente da mesma transação impede resolver a pendência e '
         'impede trocar sua descrição pela de um achado de pré-condição. fn_reconciliar_caso ganha '
         '`order by` nos laços — determinismo de qual período a pendência carrega. Catalogado pelo '
         'corpo (ok_nao_mata_divergencia_irma) — a assinatura de fn_registrar_reconciliacao não muda.'
 where id = true;
