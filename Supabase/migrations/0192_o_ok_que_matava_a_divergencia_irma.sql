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
-- =============================================================================
-- REVISÃO DA S102, GRUPO B (achados 4, 5 e 6) — o desenho escolhido, escrito ANTES
-- do código. O teto "mesma transação" da parte (1) acima ERA o achado 4; o que
-- vale agora é o que está nesta seção, e a parte (1) acima passa a ser o caso
-- particular "a rodada inteira numa transação só".
--
-- ACHADO 5 (ALTO) — `secao_fecha` é POR DOCUMENTO e a pendência era casada por
-- (caso, motivo, entidade, período compatível). O n8n roda
-- `fn_reconciliar_por_documento($1,'documento')` em transações SEPARADAS
-- (`queryBatching: 'independently'`, N8N/build-workflow.mjs:2405 e :2030), um
-- documento por vez; a guarda "mesma transação" nunca os via. O `ok` (ou o
-- `documento_ausente`, que a 0190 passou a gravar para "nenhuma seção
-- conferida") de OUTRO balanço da mesma entidade/período resolvia a divergência
-- de um balanço que continuava não fechando consigo mesmo.
--   MEDIDO em produção (28/09/2026, somente leitura): `reconciliacao:secao_fecha`
--   tem 78 pendências, 27 resolvidas (todas por `sistema:reconciliacao`), 21
--   delas em menos de 10 minutos da criação (ex.: `866d4c3d`, `c5c10450`). Nas 21:
--   (a) a entidade tem de 2 a 20 documentos de árvore (BALANCO/BALANCETE/
--   COMBINADO) e em TODAS existe OUTRO documento de árvore com período
--   compatível; (b) no mesmo segundo da resolução (+-1 s) existe, em
--   `reconciliacao`, uma linha `secao_fecha` não-divergente da mesma
--   entidade com período compatível — 21 de 21 (remedido em
--   28/09/2026): 10 com um `ok` e 11 só com `precondicao_nao_satisfeita` (o
--   `documento_ausente` da 0190, gravado como pré-condição, também resolve).
--   Ou seja: nenhuma das 21 foi resolvida porque o PRÓPRIO documento passou a
--   fechar; foi o lote processando o documento seguinte. (A coluna
--   `reconciliacao.documento_id` não existia, então o documento que resolveu
--   não é recuperável linha a linha — a prova é a coincidência de segundo, de
--   entidade e de período, nas 21.)
--   CORREÇÃO: a pendência de um tipo POR DOCUMENTO só é casada por
--   `documento_id` igual (além de caso, motivo, entidade e período compatível).
--   Os tipos por documento são os de `c_tipos_por_documento` em
--   `fn_registrar_reconciliacao` — hoje só `secao_fecha`: é o único cuja
--   entrada é o conteúdo de UM documento (a árvore intra-documento, 0133); os
--   outros lêem (caso, entidade, período) e o `documento_id` que passam é só o
--   documento representativo (0152:408, "as oito checagens leem a chave, não o
--   documento"). Consequência: dois balanços do mesmo período que não fecham
--   abrem DUAS pendências de `secao_fecha` — uma por documento, como o texto
--   de `fn_reconciliar_arvore` já prometia ("UMA pendência por documento").
--
-- ACHADO 4 (ALTO) — ENTRE RODADAS a ordem ainda decidia. Com a divergência de
-- pé (gravada numa transação anterior), o `ok` do período que a rodada seguinte
-- visitava primeiro RESOLVIA a pendência (inclusive `em_correcao_interna`/
-- `aceita_com_ressalva`) e a divergente, ao chegar, abria OUTRA: o trabalho
-- humano sumia e a trilha dizia "resolvida". A guarda `criado_em = now()` não
-- enxergava nada de transação anterior.
--   A GUARDA FOI CORRIGIDA TRÊS VEZES (db6a258, 0202b8f, e esta) e as duas primeiras
--   raciocinavam por PERÍODO GRAVADO ("o último estado de cada outro período compatível").
--   Falhavam pelo mesmo motivo: o período em que o resultado FICA gravado não é o período
--   da CHAVE que o produziu. `fn_reconciliar_caso` (e `fn_reconciliar_chaves_do_documento`)
--   percorre `fn_periodos_compativeis_array(caso, chave)` e DESCE para períodos compatíveis
--   de OUTRAS entidades enquanto der pré-condição; o resultado conclusivo fica num período
--   sem documento da entidade. Cenário (reproduzido em divergencia_vigente_entre_rodadas):
--   entidade E com Balanço "23,24" (Pa) e "24,25" (Pb); o caso tem 12M24 (P24) de outra
--   entidade. Rodada 1: a chave Pb dá pré-condição, desce a P24 e diverge — pendência em
--   P24, e um humano a põe em `em_correcao_interna`. Rodada 2: a chave Pa, visitada
--   primeiro, dá `ok`; P24 é compatível com Pa, acha a pendência, e a guarda por período
--   descartava a divergente de P24 ("rodada anterior, sem documento exato") -> RESOLVIA;
--   depois Pb descia de novo, divergia e abria OUTRA. Em produção, 332 estados vigentes
--   (20 dias, 30/09/2026) estão em período SEM documento exato da entidade: o mecanismo
--   está vivo, não é hipótese.
--   O DESENHO AGORA É POR CHAVE (a sessão principal decidiu, pela regra das três
--   correções falhas): o que a guarda pergunta é "alguma CHAVE ainda viva concluiu
--   divergente, no seu último registro?", não "algum período gravado está divergente?".
--     (1) Coluna NOVA `reconciliacao.periodo_chave_id` (nullable, FK `on delete set null`):
--         o período da CHAVE que originou a chamada. Os laços (`fn_reconciliar_caso` e
--         `fn_reconciliar_chaves_do_documento` — os DOIS únicos que despacham as checagens
--         por chave, conferido por grep em todas as migrations) fazem
--         `set_config('oria.periodo_chave', <período da chave>, true)` antes de cada laço de
--         período, e `fn_registrar_reconciliacao` grava
--         `nullif(current_setting('oria.periodo_chave', true), '')::uuid`. Sem o setting
--         (chamada direta, como nos testes e na `fn_reconciliar_arvore`), a chave é o
--         próprio `p_periodo_id`: uma chamada avulsa é a sua própria chave. Os laços
--         ZERAM o setting antes das checagens sem período (duplicidade, versões) e ao
--         sair, para a chave de uma chamada nunca vazar para a seguinte.
--     (2) Antes de resolver (ou de trocar a descrição por uma de pré-condição), para cada
--         CHAVE viva K — existe documento do caso com `periodo_id = K` (da entidade, quando
--         a entidade não é nula) — olha-se o ÚLTIMO registro com `periodo_chave_id = K`
--         (mesmo caso/tipo/entidade; `criado_em desc`, `cmin` desempata dentro da
--         transação). Se ele é divergente (`divergente`, `divergencia`, `zona_cinzenta`)
--         num período igual ou compatível com o da pendência, NÃO resolve (e não troca a
--         descrição). Mais: qualquer linha DESTA transação (`criado_em = now()`), de outro
--         período que o desta chamada, divergente e compatível, também bloqueia (a guarda
--         original, que vale dentro de uma rodada mesmo para chave sem documento).
--     (3) Continua resolvendo: reclassificação (a chave antiga deixa de ter documento ->
--         não prende), período NULL (nenhum documento tem `periodo_id = NULL` como chave),
--         o retry da 0152 (o último registro da chave é pré-condição, não divergente) e a
--         resolução legítima (todas as chaves concluem ok). Tipos POR DOCUMENTO
--         (secao_fecha) seguem SEM guarda: o casamento por `documento_id` isola o documento.
--     A coluna `reconciliacao.documento_id` (nullable, FK `on delete set null`) é gravada
--     com `p_documento_id`; linha antiga fica NULL.
--   TETO DECLARADO: (i) linha gravada ANTES desta migration não tem `periodo_chave_id` e NÃO
--   bloqueia — falha para o lado de RESOLVER, como era antes da 0192 (ninguém sabe de que
--   chave ela veio; inventar seria fabricar dado). Uma divergência já aberta em produção só
--   passa a ser protegida depois da primeira rodada do caso com o corpo novo;
--   (ii) o laço de `fn_reconciliar_por_documento(...,'tudo')` sai no primeiro período que
--   conclui, então reconciliar só o documento do período `ok` não fecha a pendência cuja
--   chave irmã ficou divergente (fica aberta, nunca fechada em falso);
--   (iii) "documento vivo" é (caso, entidade, período) com QUALQUER tipo de documento, não
--   "o tipo que alimenta ESTA checagem" — uma chave cujo único documento é de outro tipo
--   ainda conta e segura a pendência até ser reconciliada de novo;
--   (iv) a ordem entre transações é `criado_em` (relógio do banco): duas rodadas no mesmo
--   microssegundo não se ordenam (não medido, improvável);
--   (v) checagens por período apenas (mútuos, intragrupo: entidade NULL) têm a chave viva
--   por QUALQUER documento do caso naquele período;
--   (vi) ainda não há identificador de rodada (`lote_execucao`).
--
-- ACHADO 6 (MÉDIO) — regra 1: o texto da checagem se perdia quando ela não
-- abria pendência. `reconciliacao` não tinha coluna de descrição; "hierarquia
-- achatada/rótulo duplicado" (0190) e "planilha deste exercício não entregue"
-- (0194) ficavam iguais a "nenhum balanço traz mútuo", e o `ok` da 0191 dizia
-- "em 1 ano(s)" sem dizer que 2024 ficou sem par. CORREÇÃO: coluna nova
-- `reconciliacao.descricao` (text), gravada SEMPRE por `fn_registrar_reconciliacao`
-- com `p_descricao`, inclusive quando não abre pendência (ok, documento_ausente,
-- sombra). Linha antiga fica NULL (ausência, não string vazia); nenhum
-- backfill — o texto antigo não existe em lugar nenhum.
-- =============================================================================
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
-- (0) AS COLUNAS NOVAS de `reconciliacao` (achados 4 e 6 da revisão da S102)
-- -----------------------------------------------------------------------------
alter table reconciliacao
  add column if not exists documento_id uuid references documento(id) on delete set null,
  add column if not exists descricao    text,
  add column if not exists periodo_chave_id uuid references periodo(id) on delete set null;

comment on column reconciliacao.documento_id is
  'O documento que a checagem recebeu (p_documento_id de fn_registrar_reconciliacao), ou NULL. '
  'Só é CRITÉRIO para os tipos POR DOCUMENTO (hoje secao_fecha): ali a pendência e o estado vigente '
  'são por documento. Nos demais tipos é o documento REPRESENTATIVO que o emissor escolheu e não '
  'distingue nada. NULL também nas linhas anteriores à 0192 e quando o documento foi apagado '
  '(on delete set null).';
comment on column reconciliacao.descricao is
  'O texto que o emissor deu ao achado (p_descricao), gravado SEMPRE — inclusive quando a checagem '
  'NÃO abre pendência (ok, documento_ausente, estágio em sombra). É o que separa "não conferiu, e '
  'por quê" de "conferiu e fechou". NULL nas linhas anteriores à 0192: o texto delas não existe em '
  'lugar nenhum (ausência, não string vazia).';

comment on column reconciliacao.periodo_chave_id is
  'O período da CHAVE que originou a chamada (o período do documento que o laço de fn_reconciliar_caso / '
  'fn_reconciliar_chaves_do_documento estava visitando), que NÃO é o `periodo_id` quando o laço DESCEU '
  'para um período compatível de outra entidade. É por esta coluna que a guarda de '
  'fn_registrar_reconciliacao lê o ESTADO VIGENTE de cada chave. NULL nas linhas anteriores à 0192 '
  '(não bloqueiam a resolução: ninguém sabe de que chave vieram) e quando o período foi apagado '
  '(on delete set null).';

-- O estado vigente lê o último registro por (caso, tipo, CHAVE): sem o índice é ordenar o
-- histórico do caso inteiro a cada registro (6.236 linhas em 44 casos em produção, 28/09/2026).
create index if not exists idx_reconciliacao_vigente
  on reconciliacao (caso_id, tipo, periodo_chave_id, criado_em desc);

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

comment on function fn_registrar_reconciliacao(uuid, uuid, uuid, text, text, uuid, jsonb, jsonb, text,
  numeric, numeric, jsonb, text) is
  'Registro unificado de reconciliação (0023), motivo fino por pré-condição (0186/0188). 0192: '
  'a pendência só resolve (ou troca a descrição por uma de pré-condição) se nenhuma CHAVE viva (período '
  'de documento) tem como último registro uma divergência em período compatível, em qualquer rodada; '
  'tipo por documento (secao_fecha) casa a pendência e o estado por documento_id; grava documento_id, '
  'descricao e periodo_chave_id em toda linha de reconciliacao.';

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
-- 0192 (guarda por CHAVE): cada laço grava em `oria.periodo_chave` o período da chave que visita
-- (set_config local à transação); fn_registrar_reconciliacao o lê e o grava em
-- `reconciliacao.periodo_chave_id`. O laço DESCE a períodos compatíveis (foreach), o que muda o
-- `periodo_id` da linha mas não a chave.
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
    perform set_config('oria.periodo_chave', coalesce(v_k.periodo_id::text, ''), true);
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_ativo_passivo_pl(p_caso_id, v_k.entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.entidade_id, d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_fluxo)
             order by d.entidade_id, d.periodo_id loop
    perform set_config('oria.periodo_chave', coalesce(v_k.periodo_id::text, ''), true);
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_caixa_bp_fluxo(p_caso_id, v_k.entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.entidade_id, d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_receita)
             order by d.entidade_id, d.periodo_id loop
    perform set_config('oria.periodo_chave', coalesce(v_k.periodo_id::text, ''), true);
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_receita_dre_vs_faturamento(p_caso_id, v_k.entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.entidade_id, d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_despfin)
             order by d.entidade_id, d.periodo_id loop
    perform set_config('oria.periodo_chave', coalesce(v_k.periodo_id::text, ''), true);
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
    perform set_config('oria.periodo_chave', coalesce(v_k.periodo_id::text, ''), true);
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_mutuos(p_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_intra)
             order by d.periodo_id loop
    perform set_config('oria.periodo_chave', coalesce(v_k.periodo_id::text, ''), true);
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_intragrupo(p_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  -- ---- só (entidade) — sem período nenhum ----------------------------------
  -- 0192: sem chave de período; o que o último laço deixou não pode vazar para estas.
  perform set_config('oria.periodo_chave', '', true);
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

  perform set_config('oria.periodo_chave', '', true);
  return jsonb_build_object(
    'executado', true, 'caso_id', p_caso_id,
    'documentos', v_documentos, 'chamadas', v_chamadas,
    'checagens', v_checagens);
end;
$$;

-- 0192: fn_reconciliar_chaves_do_documento — REEMITIDA INTEIRA (corpo 0152:394).
create or replace function fn_reconciliar_chaves_do_documento(
  p_caso_id     uuid,
  p_entidade_id uuid,
  p_periodo_id  uuid,
  p_tipo        text
)
returns jsonb language plpgsql as $$
-- 0152: extraída de fn_reconciliar_por_documento sem mudança de lógica.
-- 0192: REEMITIDA INTEIRA (corpo vigente 0152:394, nenhuma migration a reemitiu) só para gravar a
-- CHAVE em `oria.periodo_chave` (ver fn_registrar_reconciliacao).
-- 0151: o conflito entre documentos do mesmo período mora aqui, no fim.
declare
  v_checagens jsonb := '[]'::jsonb;
  v_periodos  uuid[];
  v_per       uuid;
  v_res       jsonb;
begin
  select array_agg(p.id order by (p.id = p_periodo_id) desc, p.referencia)
    into v_periodos
  from periodo p
  where p.caso_id = p_caso_id
    and (p.id = p_periodo_id or fn_periodos_compativeis(p.id, p_periodo_id));
  if v_periodos is null or cardinality(v_periodos) = 0 then
    v_periodos := array[p_periodo_id];
  end if;

  -- 0192 (guarda por CHAVE): o período do documento é a chave de TODAS as checagens por período
  -- abaixo; o laço desce a períodos compatíveis, a chave não muda. As duas sem período (duplicidade,
  -- versões) zeram o setting.
  perform set_config('oria.periodo_chave', coalesce(p_periodo_id::text, ''), true);

  -- Classe A (0009)
  if p_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_ativo_passivo_pl(p_caso_id, p_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;
  if p_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO', 'FLUXO_CAIXA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_caixa_bp_fluxo(p_caso_id, p_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Classe B (0015/0021)
  if p_tipo in ('DRE', 'FATURAMENTO_24M') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_receita_dre_vs_faturamento(p_caso_id, p_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;
  if p_tipo in ('DRE', 'MAPA_DIVIDA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_despfin_dre_vs_divida(p_caso_id, p_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Mútuos (0117/0123). Pelos dois lados: quem chega por último fecha o par.
  if p_tipo in ('MUTUOS', 'BALANCO', 'COMBINADO', 'DF_AUDITADA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_mutuos(p_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Intragrupo FORA mútuo (0124). Disparada por balanço individual, que é a
  -- única peça de que ela precisa — não há documento par a esperar. `COMBINADO`
  -- não dispara e não é lido: as linhas intragrupo dele são eliminações.
  if p_tipo in ('BALANCO', 'BALANCETE', 'DF_AUDITADA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_intragrupo(p_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Duplicidade de rótulo (0105). Sem laço de período: é por caso/entidade.
  perform set_config('oria.periodo_chave', '', true);
  if p_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    v_checagens := v_checagens || jsonb_build_array(
      fn_reconciliar_duplicidade(p_caso_id, p_entidade_id));
  end if;

  -- Conflito entre documentos do mesmo período (0151). Sem laço de período: a
  -- checagem descobre sozinha quais exercícios existem.
  if p_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DF_AUDITADA', 'DRE',
                'FLUXO_CAIXA', 'DMPL', 'DVA', 'NOTAS_EXPL') then
    v_checagens := v_checagens || jsonb_build_array(
      fn_reconciliar_versoes_do_periodo(p_caso_id, p_entidade_id));
  end if;

  perform set_config('oria.periodo_chave', '', true);
  return v_checagens;
end;
$$;

comment on function fn_reconciliar_chaves_do_documento(uuid, uuid, uuid, text) is
  'As oito checagens que leem (caso, entidade, período) e não o documento (0152). Extraída de '
  'fn_reconciliar_por_documento sem mudança de lógica, para que o lote possa rodá-las uma vez '
  'por CHAVE em vez de uma vez por documento. 0192: grava o período da chave em oria.periodo_chave.';

comment on function fn_reconciliar_caso(uuid) is
  'Roda cada uma das oito checagens de reconciliação sobre a SUA chave (0152). 0192: `order by` em '
  'cada laço `select distinct` — determinismo de qual período a pendência carrega quando mais de um '
  'é compatível; o aberto/resolvido em si já não depende da ordem (guarda em fn_registrar_reconciliacao). '
  '0192: cada laço grava o período da CHAVE em oria.periodo_chave (lido por fn_registrar_reconciliacao).';

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
   'ultimo_por_chave',
   'Sem esta guarda (último registro de cada CHAVE viva, em qualquer rodada), duas checagens do mesmo '
   'caso/tipo/entidade com períodos COMPATÍVEIS (ex.: Balanço multi "24,25" x anual "12M25"), caem na '
   'MESMA pendência por período compatível — e a ORDEM de visita decide se um ''ok'' de um período '
   'RESOLVE a divergência gravada pelo outro. Medido em produção (25/09/2026, somente leitura): '
   'pendência divergencia_reconciliacao criada e resolvida no MESMO instante, 4 casos de 41 '
   'pendências reconciliacao:% nascidas-e-mortas na mesma rodada.',
   'importante', 832),

  ('pendencia_por_documento_secao_fecha', '0192', 'corpo', 'fn_registrar_reconciliacao',
   'v_por_documento',
   'Sem isto a pendência de secao_fecha (checagem POR DOCUMENTO: o n8n roda '
   'fn_reconciliar_por_documento($1,''documento'') em transações separadas) é casada só por '
   '(entidade, período compatível), e o ''ok'' (ou documento_ausente) de OUTRO balanço da mesma '
   'entidade resolve a divergência de um balanço que continua não fechando. Medido em produção '
   '(28/09/2026, somente leitura): 27 das 78 pendências reconciliacao:secao_fecha resolvidas por '
   'sistema:reconciliacao, 21 em menos de 10 minutos da criação, todas no mesmo segundo de uma '
   'linha secao_fecha não-divergente de OUTRO documento da entidade.',
   'importante', 839),

  ('reconciliacao_documento_id_existe', '0192', 'coluna', 'reconciliacao.documento_id',
   null,
   'O documento que a checagem recebeu, gravado por fn_registrar_reconciliacao. Sem a coluna o '
   'estado vigente por documento (secao_fecha) não tem de onde ler e fn_registrar_reconciliacao '
   'morre no INSERT.',
   'importante', 840),

  ('reconciliacao_descricao_existe', '0192', 'coluna', 'reconciliacao.descricao',
   null,
   'O texto que a checagem deu ao achado, gravado SEMPRE (regra 1: "hierarquia achatada", "planilha '
   'deste exercício não entregue" e "nenhum balanço traz mútuo" eram indistinguíveis no histórico '
   'quando a checagem não abria pendência). Sem a coluna, fn_registrar_reconciliacao morre no INSERT.',
   'importante', 841),

  ('reconciliacao_documento_id_gravado', '0192', 'corpo', 'fn_registrar_reconciliacao',
   'p_documento_id, p_descricao',
   'O INSERT em reconciliacao grava documento_id e descricao. Sem o marcador, a coluna existe e '
   'continua NULL em toda linha nova — a ausência vira "não sei qual documento nem por quê".',
   'importante', 842),

  ('guarda_vigente_so_periodo_chave', '0192', 'corpo', 'fn_registrar_reconciliacao',
   'd.periodo_id = r.periodo_chave_id',
   'A guarda olha o último registro de cada CHAVE (período do documento que o laço visita) e só '
   'conta a chave se há documento vivo com esse período EXATO. Raciocinar pelo período GRAVADO '
   '(versões db6a258 e 0202b8f) descartava o resultado que o laço deixa num período compatível '
   'SEM documento da entidade (fn_periodos_compativeis_array desce a períodos de outras entidades): '
   'o ok da chave irmã resolvia a divergência em em_correcao_interna e a chave original abria OUTRA. '
   'Medido em produção (30/09/2026, somente leitura): 332 estados vigentes (20 dias) em período sem '
   'documento exato da entidade.',
   'importante', 843),

  ('reconciliacao_periodo_chave_existe', '0192', 'coluna', 'reconciliacao.periodo_chave_id',
   null,
   'O período da CHAVE que originou a chamada, gravado por fn_registrar_reconciliacao. Sem a coluna '
   'a guarda por chave não tem de onde ler e fn_registrar_reconciliacao morre no INSERT.',
   'importante', 844),

  ('laco_caso_grava_periodo_chave', '0192', 'corpo', 'fn_reconciliar_caso',
   'set_config(''oria.periodo_chave'', coalesce(v_k.periodo_id::text, ''''), true)',
   'Sem isto o laço de fn_reconciliar_caso não diz a fn_registrar_reconciliacao qual é a chave: '
   'periodo_chave_id cai no fallback (o período em que o laço DESCEU) e a guarda volta a raciocinar '
   'pelo período gravado — o cenário Pa/Pb (resultado conclusivo em período de outra entidade).',
   'importante', 845),

  ('laco_documento_grava_periodo_chave', '0192', 'corpo', 'fn_reconciliar_chaves_do_documento',
   'set_config(''oria.periodo_chave'', coalesce(p_periodo_id::text, ''''), true)',
   'Idem para o caminho por documento (fn_reconciliar_por_documento(...,''tudo'')): sem a chave '
   'gravada, o laço que desce a períodos compatíveis grava a linha com o período da descida.',
   'importante', 846),

  ('registro_grava_periodo_chave', '0192', 'corpo', 'fn_registrar_reconciliacao',
   'current_setting(''oria.periodo_chave'', true)',
   'O INSERT em reconciliacao grava periodo_chave_id lido de oria.periodo_chave. Sem isto a coluna '
   'existe e fica NULL em toda linha nova, e a guarda por chave nunca bloqueia nada.',
   'importante', 847)

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
       observacao = 'A 0192 reemite fn_registrar_reconciliacao e fn_reconciliar_caso: a pendência só '
         'resolve se o ÚLTIMO registro de cada CHAVE viva (em qualquer rodada) não é divergente em período compatível; secao_fecha casa pendência e estado por documento_id; reconciliacao ganha '
         'documento_id, descricao e periodo_chave_id, gravados sempre; a guarda é POR CHAVE (o período do '
         'documento que o laço visita), e fn_reconciliar_caso e fn_reconciliar_chaves_do_documento '
         '(reemitida inteira) a gravam em oria.periodo_chave. fn_reconciliar_caso ganha `order by` nos laços. '
         'Catalogado pelo corpo (ok_nao_mata_divergencia_irma, pendencia_por_documento_secao_fecha, '
         'reconciliacao_documento_id_gravado, guarda_vigente_so_periodo_chave, laco_caso_grava_periodo_chave, '
         'laco_documento_grava_periodo_chave, registro_grava_periodo_chave) e pelas colunas.'
 where id = true;
