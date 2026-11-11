-- 0241 — A DESCRIÇÃO QUE O PERÍODO IRMÃO REESCREVIA: fn_registrar_reconciliacao só reescreve a descrição da pendência quando a rodada é do período que ela carrega (ou da chave dele), não de um período compatível de outra chave; backfill das já contaminadas (sistema:0241).
-- (Reemite 1 função com a MESMA assinatura, o MESMO retorno e a MESMA ACL: fn_registrar_reconciliacao (0192). Cria 1 função, fn_corrigir_descricao_contaminada. Backfill uma vez. 3 requisitos novos na sonda. Sem tabela, sem gatilho.)
--
-- O DEFEITO. A busca da pendência aberta da mesma chave (caso, motivo, entidade) casa por período COMPATÍVEL, não igual (`periodo_id is not distinct from p_periodo_id or fn_periodos_compativeis(...)`), e isso é
-- de propósito: a mesma checagem chega por dois documentos de granularidade diferente (anual 2024 e multi 24,26) e sem a compatibilidade abriria duas pendências. Mas o ramo "abre pendência e ela já existe" fazia
-- `update pendencia set descricao = p_descricao` SEM olhar de quem era o texto: o `periodo_id` da pendência fica o de quem a abriu (A), e a descrição passava a ser a da última rodada, a do irmão (B). O analista abre
-- a pendência "anual 2024" e lê o valor, a diferença e o período de "multi 24,26".
-- MEDIDO em PRODUÇÃO (somente leitura, 11/11/2026): 7 pendências ABERTAS de reconciliação com descrição que nenhuma `reconciliacao` do próprio `periodo_id` gerou (mesmo caso, mesmo `'reconciliacao:'||tipo = motivo`,
-- mesma descrição, `periodo_id` = o da pendência):
--   Fw Valtra            receita_dre_vs_faturamento  anual 2024         <- multi 24,26
--   Krauspenhar          despfin_dre_vs_divida       anual 2024         <- multi 2024-2026
--   Krauspenhar          despfin_dre_vs_divida       multi 2024-2026    <- anual 2026 / multi 01/01/2026 a 31/08/2026
--   Canastra sintético   ativo_passivo_pl            anual 2025         <- multi 23,24,25
--   Canastra sintético   caixa_bp_fluxo              anual 2025         <- multi 23,24,25
--   Distress sintético   despfin_dre_vs_divida       multi 23,24,25     <- anual 2025 / data-base 31/12/2025
--   Vertentes ponta a ponta ativo_passivo_pl         anual 2025         <- multi 24,25 / multi jan/2024 a dez/2025
--
-- A CORREÇÃO, NO PONTO ÚNICO. Todas as fn_reconciliar_* gravam por fn_registrar_reconciliacao (e fn_registrar_reconciliacao_b só a chama com classe 'B'); corrigi-la corrige todas. Chamadores (grep em Supabase/ N8N/
-- portal/src/, 11/11/2026; N8N/ e portal/src/: nenhum): as fn_reconciliar_* (arvore, ativo_passivo_pl, caixa_bp_fluxo, despfin_dre_vs_divida, intragrupo, mutuos, receita_dre_vs_faturamento e os despachantes de
-- 0152/0192, nas migrations 0105 a 0234); fn_registrar_reconciliacao_b (0015) e os testes dial_obedecido, divergencia_prevalece_na_rodada, divergencia_vigente_entre_rodadas, reconciliacao_motivo_precondicao.
-- A reescrita da descrição passa a exigir que a rodada seja do período que a pendência carrega (`v_pendencia_periodo_id is not distinct from p_periodo_id`) OU da chave dele (`... from v_periodo_chave_id`, o
-- `oria.periodo_chave` que o laço deixa; chamada avulsa é a sua própria chave). A SEGUNDA metade existe porque a primeira versão desta correção (só o período) reprovou divergencia_vigente_entre_rodadas.test.sql
-- (0192/4, "Pa primeiro"): a chave Pb dá pré-condição no seu período (abre a pendência ali, "Pb sem par") e o laço desce a P24, compatível, onde DIVERGE — e o texto da divergência TEM de trocar o da pré-condição,
-- é a mesma chave. Sem chave gravada na pendência não se distingue o texto de uma chave que desce a um terceiro período compatível: esse caso (chave B descendo a um período A'' que não é o da pendência de A) segue
-- reescrevendo, e é o resíduo declarado desta correção. Nada mais muda: a deduplicação por período compatível, a guarda da divergência irmã (0192, que já impedia o texto de
-- pré-condição de trocar o de divergência quando há divergência concorrente), a resolução e o tipo por documento (secao_fecha casa por documento_id; o período dele é o da chave) seguem como estavam. O corpo é o VIGENTE do
-- schema.sql com a variável, o seu cálculo e o `if`.
--   * O QUE SE PERDE, DECLARADO: a pendência de A só ganha texto novo quando uma rodada de A passa por ela. Se o período de A deixa de ter registro (documento apagado, período do documento mudado), a descrição fica a do
--     último registro de A (velha), onde antes seria a do irmão (de outro período, e por isso errada de outro jeito). O `ok` de B continua não resolvendo (0192, guarda por chave). Em operação normal fn_reconciliar_caso
--     visita cada chave a cada rodada, então A reescreve a sua. Se o laço descer a OUTRO período que o de abertura (pré-condição no período da chave, divergência no compatível), é esse o período que a pendência passa a
--     carregar desde a abertura, e é ele que reescreve de novo a cada rodada: não muda com esta migration.
--
-- O BACKFILL. fn_corrigir_descricao_contaminada(p_caso_id default null) acha a pendência de origem 'reconciliacao', estado 'aberta' (as demais são decisão de gente: em_correcao_interna, reenviada_ao_cliente,
-- aceita_com_ressalva, rejeitada; e a resolvida não se toca), com `periodo_id` e descrição, que nenhuma `reconciliacao` do mesmo caso e tipo, com a mesma descrição e o `periodo_id` dela, produziu (o critério da
-- medição acima). Para cada uma põe em `descricao` a da reconciliação MAIS RECENTE do próprio período (mesmo caso, tipo, entidade, `periodo_id`; tipo por documento também no mesmo documento) cujo resultado é coerente
-- com o `tipo` da pendência: divergente/divergencia/zona_cinzenta para `divergencia_reconciliacao`, precondicao_nao_satisfeita para `precondicao_nao_satisfeita`, descrição não vazia (regra 1: nada em branco). Sem
-- registro assim, NÃO toca e conta (`sem_registro_proprio`): ausência declarada, não texto inventado. `resolvida_por` e `estado` ficam intocados. Cada correção grava um evento_auditoria (ator `sistema:0241`, acao
-- `descricao_da_pendencia_corrigida`, entidade_ref `pendencia:<id>`) com a descrição antiga em `antes` e a nova e a `reconciliacao` de origem em `depois`; e um resumo (acao `descricao_contaminada_resumo`) com as
-- contagens quando algo foi corrigido. Idempotente: depois de corrigida a descrição passa a ser a de uma reconciliação do próprio período, e a segunda chamada devolve corrigidas = 0. A migration a chama uma vez.
-- O QUE NÃO FOI MEDIDO: quantas das 7 de produção têm registro próprio do período para devolver (a medição de produção só leu a contaminação). O resumo do backfill diz (corrigidas x sem_registro_proprio).
--
-- A ASSINATURA E O RETORNO DE fn_registrar_reconciliacao NÃO MUDAM. Reaplicável: create or replace + upsert dos requisitos; o backfill é idempotente.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/a_descricao_que_o_periodo_irmao_reescrevia.test.sql — 20 asserts (20 execuções), medidos em
-- 11/11/2026 com o assert trocado por raise warning (`p41.medindo = on`), que CONTA; cada sabotagem é a migration reemitida sobre o banco já montado pelo run.sh (cópia por template, teste rodado inteiro, aviso MEDIDO lido).
-- Controle (migration intacta): 0 dos 20 reprovam. Correção desligada (`if true then` no lugar de `if v_reescreve_descricao then`): 3 (2 de comportamento, a pendência de A com o texto de B depois da divergência e depois
-- da pré-condição do irmão, + 1 da sonda). Backfill desligado (o `update` vira `null`): 4 (a descrição que não volta, a segunda chamada que acha de novo, a trilha duplicada e a escolha coerente com o tipo). As duas juntas: 7.
-- Os asserts de controle (deduplicação, a rodada do mesmo período que continua reescrevendo, o estado e resolvida_por intocados, sem registro próprio, decisão humana, catálogo) passam nas versões sabotadas de propósito:
-- protegem o que não pode mudar. A primeira versão da correção (só `p_periodo_id`, sem a chave) reprovou 1 assert de divergencia_vigente_entre_rodadas.test.sql (0192/4, "Pa primeiro"): é o que fez a condição incluir a chave.
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- fn_registrar_reconciliacao: o corpo VIGENTE (0192) com a descrição reescrita só pelo mesmo período.
-- ---------------------------------------------------------------------------
create or replace function fn_registrar_reconciliacao(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tipo text, p_classe text, p_documento_id uuid, p_fonte_a jsonb, p_fonte_b jsonb, p_resultado text, p_divergencia_abs numeric, p_divergencia_pct numeric, p_materialidade jsonb, p_descricao text)
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
  -- 0241: a rodada é do período que a pendência carrega, ou da CHAVE dele (calculado depois da busca, no corpo).
  v_reescreve_descricao           boolean;
  -- 0192 (terceira correção da guarda): o período da CHAVE que originou esta chamada — o que o
  -- laço de fn_reconciliar_caso / fn_reconciliar_chaves_do_documento deixou em `oria.periodo_chave`.
  -- Chamada avulsa (sem laço, como a `fn_reconciliar_arvore` e os testes) é a sua própria chave.
  v_periodo_chave_id        uuid := coalesce(nullif(current_setting('oria.periodo_chave', true), '')::uuid,
                                             p_periodo_id);
  -- 0192 (achado 5): os tipos cuja checagem é POR DOCUMENTO — a pendência e o estado
  -- vigente são do documento, não da chave (caso, entidade, período). Hoje só `secao_fecha`
  -- (fn_reconciliar_arvore, 0133/0190). Tipo novo por documento entra AQUI e na sonda.
  c_tipos_por_documento constant text[] := array['secao_fecha'];
  v_por_documento boolean := p_tipo = any(c_tipos_por_documento);
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
     precondicoes_ok, resultado, motivo_precondicao, divergencia_abs, divergencia_pct, materialidade,
     documento_id, descricao, periodo_chave_id)
  values (
    p_caso_id, p_entidade_id, p_periodo_id, p_tipo, p_classe, p_fonte_a, p_fonte_b,
    v_res_log <> 'precondicao_nao_satisfeita', v_res_log, v_motivo_precondicao,
    p_divergencia_abs, p_divergencia_pct, p_materialidade,
    -- 0192 (achados 4/5/6): o documento que a checagem recebeu e o texto que ela deu, SEMPRE.
    p_documento_id, p_descricao,
    -- 0192 (guarda por CHAVE): o período da chave que originou a chamada, não o que o laço desceu.
    v_periodo_chave_id
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
    -- 0192 (achado 5): tipo POR DOCUMENTO só casa a pendência do PRÓPRIO documento.
    and (not v_por_documento or documento_id is not distinct from p_documento_id)
    and estado <> 'resolvida'
  order by criada_em
  limit 1;

  v_reescreve_descricao := v_pendencia_periodo_id is not distinct from p_periodo_id
                           or v_pendencia_periodo_id is not distinct from v_periodo_chave_id;

  -- 0192: O OK (OU A PRÉ-CONDIÇÃO) QUE MATAVA A DIVERGÊNCIA IRMÃ — ESTADO VIGENTE POR CHAVE.
  -- Duas checagens do mesmo tipo/entidade com períodos COMPATÍVEIS (Balanço "multi 24,25" ×
  -- "anual 12M25", {2024,2025} ∩ {2025} ≠ ∅) caem na MESMA pendência (busca acima, desde a
  -- 0023), e sem guarda SÓ A ORDEM de visita decidia se o `ok` de uma RESOLVIA a divergência da
  -- outra: dentro da rodada (medido em produção, 25/09/2026: v33/v35, `caixa_bp_fluxo`,
  -- 4.340.000 criada e resolvida no mesmo instante) e ENTRE rodadas.
  -- A guarda raciocina por CHAVE (o período do documento que o laço visita), não pelo período
  -- em que o resultado FICOU gravado: o laço desce a períodos compatíveis de outras entidades
  -- enquanto der pré-condição, e o resultado conclusivo fica num período sem documento da
  -- entidade (332 estados vigentes assim em produção, 30/09/2026). Duas versões que olhavam o
  -- período gravado (db6a258, 0202b8f) descartavam exatamente esse estado e resolviam.
  -- Bloqueia se:
  --   (a) alguma CHAVE VIVA (há documento do caso com `periodo_id` = a chave, da entidade quando
  --       ela não é nula) tem como ÚLTIMO registro (`periodo_chave_id` = a chave; `criado_em desc`,
  --       `cmin` desempata dentro da transação) um resultado divergente, gravado num período
  --       igual ou compatível com o da pendência. Chave sem documento (reclassificada, NULL) não
  --       prende; linha anterior à 0192 (sem `periodo_chave_id`) não bloqueia — teto declarado;
  --   (b) OU alguma linha DESTA transação (`criado_em = now()`), de outro período que o desta
  --       chamada, é divergente e compatível — a guarda original da mesma rodada, que vale
  --       mesmo sem documento na chave.
  -- Tipo POR DOCUMENTO (secao_fecha) não roda a guarda: o casamento por `documento_id`
  -- (acima) já isola a pendência do próprio documento.
  if v_pendencia_id is not null and not v_por_documento then
    select exists (
      select 1 from (
        select distinct on (r.periodo_chave_id) r.periodo_id, r.resultado
        from reconciliacao r
        where r.caso_id = p_caso_id and r.tipo = p_tipo
          and coalesce(r.entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
            = coalesce(p_entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
          and r.periodo_chave_id is not null
          and exists (
            select 1 from documento d
            where d.caso_id = p_caso_id
              and (p_entidade_id is null or d.entidade_id = p_entidade_id)
              and d.periodo_id = r.periodo_chave_id)
        order by r.periodo_chave_id, r.criado_em desc, r.cmin::text::int desc
      ) ultimo_por_chave
      where ultimo_por_chave.resultado in ('divergente', 'divergencia', 'zona_cinzenta')
        and (ultimo_por_chave.periodo_id is not distinct from v_pendencia_periodo_id
             or fn_periodos_compativeis(ultimo_por_chave.periodo_id, v_pendencia_periodo_id))
    ) or exists (
      select 1 from (
        select distinct on (r.periodo_id) r.periodo_id, r.resultado
        from reconciliacao r
        where r.caso_id = p_caso_id and r.tipo = p_tipo
          and coalesce(r.entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
            = coalesce(p_entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
          and r.periodo_id is distinct from p_periodo_id
          and r.criado_em = now()
        order by r.periodo_id, r.criado_em desc, r.cmin::text::int desc
      ) ultimo_na_rodada
      where ultimo_na_rodada.resultado in ('divergente', 'divergencia', 'zona_cinzenta')
        and (ultimo_na_rodada.periodo_id is not distinct from v_pendencia_periodo_id
             or fn_periodos_compativeis(ultimo_na_rodada.periodo_id, v_pendencia_periodo_id))
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
      -- 0192: este achado é PRÉ-CONDIÇÃO, e o ESTADO VIGENTE de um período
      -- IRMÃO (chave viva, ou linha desta rodada) compatível é divergente — não troca a descrição
      -- da divergência pela de "não especificado"/checklist. A pendência
      -- continua com o texto e o `tipo` da divergência.
      null;
    else
      -- 0241: a descrição é do PERÍODO que a pendência carrega. A busca acima acha por compatibilidade, não por igualdade, então chega aqui
      -- a rodada de um período IRMÃO (anual 2024 x multi 24,26): reescrever dava à pendência de A o texto escrito para B (7 pendências
      -- abertas em produção, 11/11/2026). Só reescreve a rodada do período da pendência OU da chave que o carrega (o laço desce de uma chave com
      -- pré-condição no seu período a um compatível e diverge ali: é o texto da MESMA chave, e a pendência da 0192 conta com isso); a chave irmã mantém a deduplicação e deixa o texto como está.
      if v_reescreve_descricao then
        update pendencia set descricao = p_descricao where id = v_pendencia_id;
      end if;
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
      -- 0192: este achado CONCLUIU (ok/documento_ausente), mas o estado VIGENTE de
      -- uma chave IRMÃ (desta ou de rodada anterior) ainda é divergente num período compatível — não
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

comment on function fn_registrar_reconciliacao(uuid, uuid, uuid, text, text, uuid, jsonb, jsonb, text, numeric, numeric, jsonb, text) is
  'Registro unificado de reconciliação (0023), motivo fino por pré-condição (0186/0188). 0192: a pendência só resolve (ou troca a descrição por uma de pré-condição) se nenhuma CHAVE viva (período de documento) tem como último registro uma divergência em período compatível, em qualquer rodada; tipo por documento (secao_fecha) casa a pendência e o estado por documento_id; grava documento_id, descricao e periodo_chave_id em toda linha de reconciliacao. 0241: a pendência é achada por período COMPATÍVEL (deduplica), mas a descrição só é reescrita pela rodada do período que a pendência carrega ou da chave dele: a chave irmã (período compatível) não troca o texto de A pelo de B.';

-- ---------------------------------------------------------------------------
-- fn_corrigir_descricao_contaminada: o backfill reexecutável.
-- ---------------------------------------------------------------------------
create or replace function fn_corrigir_descricao_contaminada(p_caso_id uuid default null)
returns jsonb
language plpgsql
as $$
declare
  v_contaminadas int := 0;
  v_corrigidas   int := 0;
  v_sem_registro int := 0;
  v_pe           record;
  v_r            record;
begin
  -- só a pendência que o sistema abriu (origem reconciliacao) e em estado 'aberta': as demais são decisão de gente (ou já resolvida) e ficam como estão.
  for v_pe in
    select pe.id, pe.caso_id, pe.tipo, pe.motivo, pe.entidade_id, pe.periodo_id, pe.documento_id, pe.descricao
      from pendencia pe
     where pe.origem_estagio = 'reconciliacao'
       and pe.estado = 'aberta'
       and pe.periodo_id is not null
       and pe.descricao is not null
       and pe.motivo like 'reconciliacao:%'
       and (p_caso_id is null or pe.caso_id = p_caso_id)
       and not exists (
         select 1 from reconciliacao r
          where r.caso_id = pe.caso_id
            and 'reconciliacao:' || r.tipo = pe.motivo
            and r.descricao = pe.descricao
            and r.periodo_id = pe.periodo_id)
     order by pe.criada_em, pe.id
  loop
    v_contaminadas := v_contaminadas + 1;
    v_r := null;
    -- a MAIS RECENTE do próprio período, de resultado coerente com o tipo da pendência; tipo por documento (secao_fecha) também do próprio documento.
    select r.id, r.descricao into v_r
      from reconciliacao r
     where r.caso_id = v_pe.caso_id
       and 'reconciliacao:' || r.tipo = v_pe.motivo
       and coalesce(r.entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
         = coalesce(v_pe.entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
       and r.periodo_id = v_pe.periodo_id
       and (r.tipo <> 'secao_fecha' or r.documento_id is not distinct from v_pe.documento_id)
       and nullif(btrim(r.descricao), '') is not null
       and case v_pe.tipo::text
             when 'divergencia_reconciliacao' then r.resultado in ('divergente', 'divergencia', 'zona_cinzenta')
             when 'precondicao_nao_satisfeita' then r.resultado = 'precondicao_nao_satisfeita'
             else false end
     order by r.criado_em desc, r.cmin::text::int desc
     limit 1;
    if v_r.id is null then
      v_sem_registro := v_sem_registro + 1;   -- ausência declarada: não se inventa descrição
      continue;
    end if;
    update pendencia set descricao = v_r.descricao where id = v_pe.id;
    insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
      values ('sistema:0241', 'descricao_da_pendencia_corrigida', 'pendencia:' || v_pe.id,
              jsonb_build_object('descricao', v_pe.descricao),
              jsonb_build_object('descricao', v_r.descricao, 'reconciliacao_id', v_r.id, 'periodo_id', v_pe.periodo_id,
                                 'porque', 'a descricao era de outro periodo compativel (a rodada do irmao a reescrevia, ate a 0241)'));
    v_corrigidas := v_corrigidas + 1;
  end loop;

  if v_corrigidas > 0 then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:0241', 'descricao_contaminada_resumo', 'pendencia',
              jsonb_build_object('contaminadas', v_contaminadas, 'corrigidas', v_corrigidas, 'sem_registro_proprio', v_sem_registro,
                                 'caso_id', p_caso_id));
  end if;
  return jsonb_build_object('contaminadas', v_contaminadas, 'corrigidas', v_corrigidas, 'sem_registro_proprio', v_sem_registro);
end;
$$;

comment on function fn_corrigir_descricao_contaminada(uuid) is
  '0241: para a pendência de reconciliação aberta cuja descrição nenhuma reconciliacao do próprio período gerou (a rodada de um período irmão a reescrevia), põe a descrição da reconciliacao MAIS RECENTE do próprio período (mesmo caso, tipo, entidade, periodo_id) de resultado coerente com o tipo da pendência. Sem registro assim, não toca e conta (sem_registro_proprio). Só estado aberta (as demais são decisão de gente); resolvida_por e estado intocados. Grava evento_auditoria sistema:0241 com a descrição antiga em antes. Devolve {contaminadas, corrigidas, sem_registro_proprio}; idempotente.';

revoke all on function fn_corrigir_descricao_contaminada(uuid) from public, anon;
grant execute on function fn_corrigir_descricao_contaminada(uuid) to service_role;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    execute 'grant execute on function fn_corrigir_descricao_contaminada(uuid) to supabase_read_only_user';
  end if;
end $$;

do $$
declare v_r jsonb;
begin
  v_r := fn_corrigir_descricao_contaminada();
  raise notice '0241 backfill: % (sistema:0241)', v_r;
end $$;

-- ---------------------------------------------------------------------------
-- A SONDA. Marcadores em CÓDIGO, nunca de comentário (pg_get_functiondef traz os comentários do corpo: um marcador citado num comentário passaria sem a lógica).
-- ---------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('reconciliacao_descricao_so_do_mesmo_periodo', '0241', 'corpo', 'fn_registrar_reconciliacao', 'if v_reescreve_descricao then', null,
   'A descrição da pendência só é reescrita pela rodada do período que ela carrega (ou da chave dele). Corpo sem isto = a rodada do período compatível de outra chave (anual 2024 x multi 24,26) troca o texto de A pelo de B: o analista lê, na pendência de um período, o valor e a diferença de outro (7 pendências abertas em produção, 11/11/2026).',
   'importante', 1089),
  ('descricao_contaminada_funcao', '0241', 'funcao', 'fn_corrigir_descricao_contaminada', null, null,
   'O backfill reexecutável da descrição contaminada. Ausente = a 0241 não foi aplicada: as pendências já contaminadas continuam mostrando o texto de outro período.',
   'importante', 1090),
  ('descricao_contaminada_so_aberta', '0241', 'corpo', 'fn_corrigir_descricao_contaminada', 'pe.estado = ''aberta''', null,
   'O backfill só toca a pendência em estado aberta. Corpo sem isto = o texto de uma pendência em decisão humana (em_correcao_interna, aceita_com_ressalva...) ou já resolvida é reescrito pela migration.',
   'importante', 1091)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0241', revisado_em = current_date,
       observacao = 'A 0241 reemite fn_registrar_reconciliacao (a descrição da pendência só é reescrita pela rodada do mesmo período, não pelo compatível) e cria fn_corrigir_descricao_contaminada (backfill sistema:0241). 3 requisitos novos (ordem 1089-1091).'
 where id = true;

commit;
