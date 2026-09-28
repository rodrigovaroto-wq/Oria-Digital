-- =============================================================================
-- 0194 — A PLANILHA DE MÚTUOS QUE NUNCA FOI LIDA
--
-- O DEFEITO, medido em produção (25/09/2026, SOMENTE LEITURA). O resultado
-- mais recente de `mutuos_planilha_vs_balanco` é `documento_ausente` nos 12
-- casos que têm a planilha MUTUOS — inclusive nos 7 que TÊM planilha MUTUOS
-- **e** contas de mútuo no balanço (teste - Canastra, teste Canastra, Teste
-- comparativo - Grupo Canastra, teste v48: 14 linhas de mútuo no balanço cada;
-- Teste 00: 39; teste alto volume - grupo araucária: 136). A descrição gravada
-- diz "nenhum balanço do mandato traz conta de mútuo com lado reconhecível" —
-- FALSO nesses 7. A checagem NUNCA CONCLUI, e é a regra 7: um estágio que não
-- roda tem a mesma cara de um que rodou e não achou nada.
--
-- A CAUSA, reproduzida por consulta só de leitura no caso "teste - Canastra",
-- ano 2025 (corpo vigente na `0123`,
-- `Supabase/migrations/0123_mutuos_a_natureza_fora_da_linha.sql:185` —
-- conferido por `grep -l "create or replace function fn_reconciliar_mutuos"
-- Supabase/migrations/*.sql`: só 0117 e 0123 a definem).
--
-- A planilha de produção é um RETRATO de uma data, não uma demonstração
-- comparativa: documento `MUTUOS` com período `data-base 31/12/2025`, linhas
-- com `chave` = par de empresas ("CANASTRA PARTICIPAÇÕES S.A. - CANASTRA
-- INDÚSTRIA DE EMBALAGENS LTDA."), `secao` nula, e o CONCEITO na COLUNA —
-- exatamente a forma matricial que a `0145` já descreveu para MAPA_DIVIDA e
-- FAT_INTRAGRUPO, só que ninguém tinha aplicado a MUTUOS: `periodo_coluna` é
-- o CABEÇALHO ("Mutuante", "Mutuária" com `valor_num` nulo, "Saldo devedor"
-- com o número, "TOTAL" o subtotal), unidade 'milhar'. Em TODOS os casos de
-- produção a coluna numérica é "Saldo devedor" (Teste 00 e alto volume: um
-- documento MUTUOS por data-base, 31/12/2021…31/12/2025 — um retrato por
-- exercício, não um comparativo).
--
-- `v_col_mut := fn_coluna_periodo_do_ano(v_ver_mut, v_ano)` devolve a
-- SENTINELA `E'\x01'` ("o documento TEM `periodo_coluna`, mas nenhuma é deste
-- ano" — `0023:190`), não NULL: nenhum dos cabeçalhos do retrato ("Mutuante",
-- "Saldo devedor", "TOTAL") é ano nenhum. O filtro do LADO B foi escrito para
-- NULL: `(v_col_mut is null or fn_normalizar_texto(ce.periodo_coluna) =
-- fn_normalizar_texto(v_col_mut))` — com a sentinela, exclui TODAS as linhas,
-- `v_pl.n = 0`, `continue`, `v_n` termina em 0, e a função devolve
-- `documento_ausente` com o texto falso. O filtro foi escrito pensando num
-- documento COMPARATIVO (a mesma pergunta que a 0145 já tinha resolvido para
-- os outros dois tipos matriciais); o formato "conceito mora na coluna" da
-- própria 0145 quebrou esta checagem, que nunca foi atualizada para ele.
--
-- EFEITO: a divergência PLANTADA do book Canastra (balanços concordam em
-- 16.300 dos dois lados; planilha soma 16.060 — diferença 240 mil) nunca foi
-- acusada em produção — só no fixture, cujo formato NÃO é o de produção (ver
-- "O FIXTURE MENTIA A FAVOR DO CÓDIGO", abaixo).
--
-- OS OUTROS `continue` SILENCIOSOS DA MESMA FUNÇÃO têm o mesmo vício de
-- texto, e ficam corrigidos juntos (mesma causa, mesmo remédio — regra 6 não
-- pede um commit por `continue`, pede uma fatia coerente):
--   • escala ausente de um lado (`tem_sem_escala <> (v_unid_mut is null)`)
--     também terminava em "nenhum balanço traz conta de mútuo";
--   • a planilha não achar linha para o lado do balanço (`v_pl.n = 0`, depois
--     de a coluna estar corretamente resolvida) idem.
--
-- O FIXTURE MENTIA A FAVOR DO CÓDIGO. `fixture_book_canastra.sql`
-- (documento_versao `55555555-3333-0000-0000-000000000014`) e
-- `fixture_book_vertentes.sql` (`…-000000000012`) gravam `periodo_coluna =
-- '2025'` em TODAS as linhas da planilha de mútuos — o ANO, não o cabeçalho
-- da coluna. Com isso `fn_coluna_periodo_do_ano` acha o ano '2025' batendo
-- direto (nunca cai na sentinela) e o filtro `= fn_normalizar_texto(v_col_mut)`
-- casa normalmente: os dois fixtures testam uma FORMA que a extração real
-- nunca produz para este tipo de documento. É a mesma família de achado da
-- `.claude/conhecimento/fichas/f2-localizador-chave-pendencia-falsa.md`
-- ("fixture ≠ produção"): o teste confirmava o código porque os dois foram
-- escritos com a mesma suposição errada sobre a FORMA do dado, não sobre o
-- CONTEÚDO. Os fixtures ficam como estão (mudar o formato deles é fora do
-- escopo desta migration — trocaria o que `canastra.test.sql`/
-- `reconciliacao.test.sql` já travam byte a byte); o teste NOVO desta
-- migration (`Supabase/test/mutuos_retrato_de_uma_data.test.sql`) é quem
-- exercita o formato de produção.
--
-- A CORREÇÃO. Quando `v_col_mut = E'\x01'` e o PERÍODO DO DOCUMENTO da
-- planilha (`documento.periodo_id` → `periodo.tipo, referencia` →
-- `fn_anos_periodo`, o MESMO caminho que a `0191` já usou para o Mapa de
-- Dívida — outro retrato de uma data) cobre exatamente `v_ano`, a coluna do
-- saldo é achada pelo MESMO localizador que a `0145` já cadastrou para este
-- conceito (`taxonomia_linha_localizador`, `MUTUOS`/`saldo_de_mutuo`, termo
-- `'saldo'` — `Supabase/migrations/0145_o_conceito_que_mora_na_coluna.sql:288`):
-- reuso do termo, não um `like '%saldo%'` novo inventado. Três desfechos:
--   • o documento não cobre `v_ano`                → `sem_periodo_par`;
--   • cobre, mas nenhuma coluna diz "saldo"        → `linha_nao_localizada`;
--   • cobre e a coluna existe                      → segue a comparação de
--     sempre, com `v_col_mut` apontando para o cabeçalho real.
-- Documento sem período (ou período que não ancora ano nenhum): sem como
-- afirmar retrato de QUAL ano — `v_col_mut` segue sentinela, comportamento de
-- ANTES desta migration (mesma exceção da 0191 para o Mapa de Dívida).
--
-- CADA `continue` QUE NÃO É "o balanço não tem conta de mútuo" (`n_lados =
-- 0`, comportamento DESENHADO da 0117/0123, preservado: é o caso comum e
-- legítimo — combinado elimina intragrupo, individual às vezes agrega em
-- "outras partes relacionadas") guarda o motivo do ano em `v_motivos_ano` /
-- `v_faltas`, no MESMO padrão que a 0188/0191/0193 já usam. No fim, se
-- `v_n = 0`: só grava `documento_ausente` com o texto de sempre quando TODOS
-- os anos pularam por falta de conta de mútuo no balanço (`v_motivos_ano`
-- vazio); senão grava o motivo agregado (`fn_motivo_precondicao_agregado`,
-- 0188 — CONTRATO da 0186) com texto que diz o ano, o motivo e o efeito
-- (regra 1). Isso ABRE pendência (`fn_registrar_reconciliacao`: todo motivo
-- de precondição além de `documento_ausente` abre — 0186), e é o certo:
-- documento presente e a checagem não conseguiu conferir é achado acionável,
-- não silêncio.
--
-- REEMITIDA A FUNÇÃO INTEIRA a partir do corpo vigente (0123) — nunca
-- `replace` de texto (`.claude/memory/nunca-corrigir-funcao-por-replace.md`).
-- Confirmado que nenhuma migration entre a 0123 e esta reemitiu o corpo (grep
-- acima). O resto do corpo — degraus de natureza (rótulo/seção/tipo), mútuo
-- com sócio, um documento por entidade, os dois lados que se espelham,
-- tolerância em base — não muda uma linha.
--
-- MEDIDO NAS FIXTURES DOS DOIS BOOKS (regra 2 — ver Supabase/README.md, bloco
-- desta migration): com a substituição do `v_col_mut` sentinela desligada e
-- religada, NENHUM assert de `canastra.test.sql` ou `reconciliacao.test.sql`
-- muda — os dois fixtures gravam `periodo_coluna` = o ANO, nunca a sentinela,
-- então o ramo novo nunca dispara sobre eles (ver "O FIXTURE MENTIA A FAVOR
-- DO CÓDIGO", acima). O teste novo (`mutuos_retrato_de_uma_data.test.sql`)
-- é quem exercita o formato de produção.
--
-- A PREVISÃO DO EFEITO EM PRODUÇÃO — MEDIDA, não estimada (28/09/2026,
-- SOMENTE LEITURA, replicando a lógica dos três achados por consulta direta
-- contra produção — a mesma técnica do revisor). Ainda ESCRITA, NÃO
-- APLICADA: quem responde de verdade, depois de aplicar, é a sonda:
--
--   select chave, migration, tipo, objeto, presente, detalhe, porque
--     from fn_instalacao_conferir() where not presente order by 1;
--
-- | caso                                | ano  | lado A ativo | lado A passivo | planilha    | previsto |
-- |--------------------------------------|------|-------------:|----------------:|------------:|----------|
-- | teste - Canastra                     | 2023 |            0 |       4.200.000 |  (ausente)  | documento_ausente (planilha deste exercício não entregue) |
-- | teste - Canastra                     | 2024 |   12.700.000 |      12.700.000 |  (ausente)  | documento_ausente (idem) |
-- | teste - Canastra                     | 2025 |   16.300.000 |      16.300.000 |  16.060.000 | **zona_cinzenta, diff 240 mil** (a plantada) |
-- | teste Canastra                       | 2025 |   16.300.000 |      16.300.000 |  16.060.000 | zona_cinzenta, diff 240 mil (mesmos números do acima) |
-- | Teste comparativo - Grupo Canastra    | 2025 |   16.300.000 |      16.300.000 |  16.060.000 | zona_cinzenta, diff 240 mil |
-- | teste v48                            | 2025 |   16.300.000 |      16.300.000 |  16.060.000 | zona_cinzenta, diff 240 mil |
-- | Teste 00                             | 2023 |            0 |       1.100.000 |  33.060.000 | **SUSPEITO — ver nota abaixo, não aceitar sem checar** |
-- | Teste 00                             | 2025 |   74.800.000 |      74.800.000 |  74.560.000 | **zona_cinzenta, diff 240 mil** |
-- | teste alto volume - grupo araucária  | 2021 |    8.965.000 |      27.090.000 |  (não comparada) | zona_cinzenta (os DOIS LADOS do balanço não se espelham — achado da própria correção, não bug) |
-- | teste alto volume - grupo araucária  | 2022 |   19.490.000 |      31.180.000 |  (não comparada) | zona_cinzenta (idem) |
-- | teste alto volume - grupo araucária  | 2023 |   33.300.000 |      46.300.000 |  (não comparada) | zona_cinzenta (idem) |
-- | teste alto volume - grupo araucária  | 2024 |   51.600.000 |      58.900.000 |  (não comparada) | zona_cinzenta (idem) |
-- | teste alto volume - grupo araucária  | 2025 |   74.800.000 |      74.800.000 |  74.560.000 | zona_cinzenta, diff 240 mil |
-- | Araucária teste (7º caso, achado na medição — não citado no cabeçalho original) | 2021 | 8.965.000 | 7.217.000 | (não comparada) | zona_cinzenta (os dois lados do balanço não se espelham) |
-- | Araucária teste                      | 2022 |   19.490.000 |      19.490.000 |  19.250.000 | zona_cinzenta, diff 240 mil |
-- | Araucária teste                      | 2023 |   33.300.000 |      33.300.000 |  33.060.000 | zona_cinzenta, diff 240 mil |
-- | Araucária teste                      | 2024 |   51.600.000 |      51.600.000 |  51.360.000 | zona_cinzenta, diff 240 mil |
-- | Araucária teste                      | 2025 |   74.800.000 |      83.400.000 |  (não comparada) | zona_cinzenta (os dois lados não se espelham) |
--
-- LEITURA: nos anos em que os dois lados do balanço SE ESPELHAM, o efeito é
-- estável e consistente entre casos e anos — a mesma divergência plantada
-- de 240 mil (a régua do book Canastra), medida onde a checagem agora
-- CONSEGUE olhar (antes: 12/12 casos em `documento_ausente`, texto falso).
-- Nos anos em que os dois lados NÃO se espelham (vários em "alto volume" e
-- em "Araucária teste"), a planilha não é comparada — é o comportamento
-- JÁ DESENHADO pela 0123 (preservado, não desta migration): o achado é dos
-- BALANÇOS, não da planilha.
--
-- "Araucária teste" (e as variantes "Araucária teste 1"/"araucária test 52",
-- e ~14 casos "teste vNN" com poucas linhas) apareceram na medição além dos
-- 6 nomeados no cabeçalho original — não foram todos medidos linha a linha
-- aqui (a maioria são artefatos de sondagem antiga, não mandatos), mas
-- qualificam pelo mesmo critério (planilha MUTUOS + conta de mútuo no
-- balanço) e a sonda os pegará na próxima rodada de cada um.
--
-- "Teste 00"/2023 é MARCADO SUSPEITO e não deve ser aceito sem checar: o
-- lado A (R$ 1,1 mi, uma única linha) é muito menor que o mesmo ano nos
-- casos irmãos "Araucária teste"/"teste alto volume" (R$ 33,3 mi) — a causa
-- provável, investigada mas NÃO CORRIGIDA aqui (fora do escopo dos três
-- achados revisados): quando uma entidade só tem UM documento de balanço
-- candidato para o ano e ele é de OUTRO ano (ex.: só "anual 2025", sem
-- alternativa para 2023), o filtro de coluna do LADO A (herdado da 0123,
-- `fn_coluna_periodo_do_ano(...) is null` passa por um documento de um ano
-- só independente de qual ano está sendo perguntado) deixa esse documento
-- "aparecer" para qualquer ano, inclusive quando não é dele — os 3 achados
-- desta revisão não tocam essa parte do desenho da 0123, e corrigi-la
-- exigiria mudar o filtro de LINHA (não só a ESCOLHA do documento), o que é
-- maior que os 3 achados pedidos. Registrado aqui para a próxima rodada, não
-- corrigido: revisar "Teste 00"/2023 à mão antes de comunicar ao cliente.
-- =============================================================================

create or replace function fn_reconciliar_mutuos(
  p_caso_id        uuid,
  p_periodo_id     uuid,
  p_tolerancia_abs numeric default 50000,
  p_tolerancia_pct numeric default 0.005
) returns jsonb language plpgsql as $$
declare
  v_doc_mut uuid;
  v_ver_mut uuid;
  v_ano int;
  v_col_mut text;
  v_unid_mut text;
  v_bp   record;
  v_pl   record;
  v_a numeric; v_b numeric; v_div numeric; v_tol numeric;
  v_resultado text := 'ok';
  v_partes text[] := '{}';
  v_n int := 0;
  v_pior_abs numeric; v_pior_pct numeric;
  v_fonte_a jsonb; v_fonte_b jsonb;
  v_tem_balanco boolean;
  -- 0123: os dois degraus específicos, respondidos sobre o DOCUMENTO. Algum
  -- rótulo nomeia (degrau 1)? Alguma seção nomeia (degrau 2)? Nenhum dos dois é
  -- o degrau 3.
  v_pl_rotulo boolean;
  v_pl_secao  boolean;
  -- 0123: os lados do balanço, colhidos ANTES de comparar — é o que permite
  -- perguntar se eles concordam entre si, que a versão anterior não fazia.
  v_lados record;
  v_lado_alvo text;
  v_rotulo_lado text;
  -- 0194: a planilha é um RETRATO de uma data (0145: o conceito mora na
  -- coluna). `v_col_saldo` responde "onde mora a coluna do saldo" no
  -- documento escolhido para ESTE ano; `v_pl_retrato` (achado 2 da revisão de
  -- fidelidade, 28/09/2026) diz se ESTE documento é matricial (chave = par de
  -- empresas) — quando é, o rótulo/a seção da linha não carregam lado nenhum,
  -- e filtrar por `fn_lado_do_mutuo` descarta linha boa (ver o filtro do
  -- LADO B, abaixo).
  v_col_saldo  text;
  v_pl_retrato boolean;
  -- 0194 (achado 3 da revisão): a planilha é escolhida POR ANO, não uma vez
  -- para a checagem inteira — `v_doc_ano` é o documento MUTUOS do caso cujo
  -- período cobre `v_ano` (ou, faltando isso, um documento cujo período não
  -- ancora ano nenhum — o mesmo fallback ambíguo de ANTES desta migration).
  -- `v_doc_ano_cobre_ano` distingue os dois: só no primeiro caso é seguro
  -- resolver a sentinela pela coluna de saldo.
  v_doc_ano           uuid;
  v_doc_ano_cobre_ano boolean;
  -- 0194 (mesmo padrão da 0188/0191/0193): o motivo de cada ano/lado que não
  -- concluiu, e o que fica faltando dito em texto — para o `v_n = 0` do fim
  -- distinguir "nenhum balanço tem conta de mútuo" (silêncio de sempre) de
  -- "documento presente, checagem não concluiu" (achado, abre pendência) de
  -- "a planilha deste exercício não foi entregue" (achado 3: silêncio
  -- também — é cobrança de checklist, não achado — mas ainda assim dita em
  -- texto em `v_faltas`, para quando for o ÚNICO motivo de nada concluir).
  v_motivos_ano text[] := '{}';
  v_faltas      text[] := '{}';
  v_motivo_prec text;
begin
  -- A PLANILHA É DO GRUPO E O SALDO É DE CADA EMPRESA — por isso esta checagem
  -- é por CASO, e não por (caso, entidade) como as outras.
  --
  -- Foi a primeira versão desta função que ensinou isso, errando: ela procurava
  -- o balanço DA MESMA entidade dona da planilha. No book Vertentes a planilha é
  -- do "GRUPO VERTENTES" e a única demonstração dessa entidade é a COMBINADA —
  -- que, por definição, ELIMINA o intragrupo e não tem uma linha de mútuo
  -- sequer. A checagem "não achava o par" e abria pendência de pré-condição num
  -- caso que está perfeitamente em ordem. O par certo é o outro: a planilha
  -- lista "A → B", e o saldo mora no balanço de A (a receber) ou de B (a pagar).
  --
  -- 0194 (achado 3 da revisão): a EXISTÊNCIA da planilha, para esta
  -- pré-condição de abertura, não precisa de período específico — é só
  -- "existe QUALQUER planilha MUTUOS no caso?". QUAL planilha vale para QUAL
  -- ano é resolvido ano a ano, dentro do laço abaixo — nunca uma escolha só
  -- para a checagem inteira (era esse o defeito: aqui em cima ainda tentava
  -- o período específico primeiro, mas o resultado só alimentava a
  -- pré-condição e o `p_documento_id` do registro; era o USO ano a ano, mais
  -- abaixo, que faltava — corrigido no laço, não aqui). A chamada com
  -- `p_periodo_id` é o marcador do catálogo da sonda (D6, 0187,
  -- `d6_cobertura_de_tipos_estrita`) — preservada por isso, embora o valor
  -- que ela devolve não decida mais nada sozinho.
  v_doc_mut := fn_documento_por_tipo(p_caso_id, null, p_periodo_id, 'MUTUOS');
  if v_doc_mut is null then
    v_doc_mut := fn_documento_por_tipo(p_caso_id, null, null, 'MUTUOS');
  end if;

  select exists (
    select 1 from documento d
    where d.caso_id = p_caso_id
      and d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DF_AUDITADA')
  ) into v_tem_balanco;

  if v_doc_mut is null or not v_tem_balanco then
    return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
      'mutuos_planilha_vs_balanco', 'B', v_doc_mut, null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      format('Sem par para reconciliar mútuos: %s não foi entregue neste mandato.',
        case when v_doc_mut is null and not v_tem_balanco then 'a planilha de mútuos e nenhum balanço'
             when v_doc_mut is null then 'a planilha de mútuos' else 'nenhum balanço' end));
  end if;

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    -- ---- LADO A: o saldo de mútuos, somado sobre TODOS os balanços do caso --
    -- Soma, e não `fn_valor_conceito_col`: o saldo aparece numa conta por
    -- empresa, e pegar UMA compararia parte do saldo com a planilha inteira.
    -- A escala entra linha a linha (`fn_valor_em_base`), então um caso com um
    -- balanço em milhar e outro em unidade continua somando certo.
    --
    -- 0123: o resultado é AGREGADO em uma linha só (um objeto por lado), em vez
    -- de percorrido lado a lado. É essa mudança de forma que torna possível
    -- perguntar "os dois lados concordam?" antes de comparar qualquer coisa.
    with balancos as (
      -- UM DOCUMENTO POR ENTIDADE **por ano** — correção de defeito medido,
      -- não zelo. A 0123 escolhia por `criado_em` sem olhar o ano: o book
      -- Vertentes entrega para a mesma controlada um BALANÇO e um BALANCETE
      -- do mesmo exercício, com o mesmo saldo de mútuo (3.974) — somar os
      -- dois duplicava o lado. Essa parte não muda.
      --
      -- 0194 (achado 1 da revisão de fidelidade, MEDIDO em produção
      -- só-leitura, 28/09/2026): olhar só `criado_em` sem o ANO tem o MESMO
      -- vício quando duas peças da MESMA entidade são de ANOS diferentes —
      -- um documento "multi 24,25" sem coluna por ano e sem linha de mútuo
      -- (só lista as controladas) vencia o "anual 2025", que TEM a linha, só
      -- por ter sido carregado depois. Caso "Teste 00", ano 2025: 10/12
      -- controladas escolhiam assim — lado A saía 8,6 mi (só passivo, 2
      -- documentos) contra a planilha 68,16 mi, uma `zona_cinzenta`
      -- fabricada de 59,56 mi; o correto é os dois lados fechando em 74,8 mi
      -- contra 74,56 da planilha — divergência real de 240 mil (a mesma
      -- plantada no book Canastra). Mesmo desenho no "teste alto volume -
      -- grupo araucária" (2024: passivo 25,8 mi de 6 documentos × planilha
      -- 46,76 mi). Critério agora: entre os documentos do exercício, o que
      -- TRAZ dado do ano (linha de mútuo na coluna certa, ou sem coluna
      -- nenhuma — documento de um ano só) vence o que só ANCORA o ano sem
      -- trazer dado; só então a prioridade de tipo da 0123 (BALANCO >
      -- COMBINADO > DF_AUDITADA > BALANCETE) e o mais recente. Um "multi
      -- 24,25" que TEM colunas por ano e linha de mútuo continua valendo — o
      -- critério é "tem dado", não "é anual".
      select distinct on (d.entidade_id) d.id, d.entidade_id
      from documento d
      join lateral (select fn_versao_atual(d.id) as ver) v on true
      where d.caso_id = p_caso_id
        and d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DF_AUDITADA')
      order by d.entidade_id,
               (exists (
                  select 1 from campo_extraido ce2
                  where ce2.documento_versao_id = v.ver
                    and ce2.valor_num is not null
                    and fn_texto_nomeia_mutuo(ce2.chave)
                    and (v_ano is null
                         or fn_coluna_periodo_do_ano(v.ver, v_ano) is null
                         or fn_normalizar_texto(ce2.periodo_coluna)
                            = fn_normalizar_texto(fn_coluna_periodo_do_ano(v.ver, v_ano)))
               )) desc,
               array_position(array['BALANCO','COMBINADO','DF_AUDITADA','BALANCETE'],
                              d.tipo_taxonomia),
               d.criado_em desc
    ), linhas as (
      select d.id as doc_id,
             fn_lado_do_mutuo(ce.chave, ce.secao_canonica) as lado,
             fn_valor_em_base(ce.valor_num, ce.unidade) as valor_base,
             ce.chave,
             ce.unidade
      from balancos d
      join lateral (select fn_versao_atual(d.id) as ver) v on true
      join campo_extraido ce on ce.documento_versao_id = v.ver
      where ce.valor_num is not null
        -- O LADO DO BALANÇO CONTINUA LENDO O RÓTULO, e isto é deliberado: o
        -- defeito medido é do lado da PLANILHA, e nos balanços do Canastra e de
        -- Vertentes a conta diz "Mútuos a pagar" / "Mútuos a receber" no próprio
        -- rótulo. Alargar aqui para a seção seria consertar um caso que não
        -- existe — e traria a mesma over-inclusão: a subseção de balanço é
        -- "Partes Relacionadas", que agrupa mútuo, conta corrente e aluguel.
        and fn_texto_nomeia_mutuo(ce.chave)
        -- 0123: mútuo com SÓCIO sai — a outra ponta dele não está no mandato,
        -- então ele não espelha e não é da população da planilha intragrupo.
        and not fn_mutuo_com_socio(ce.chave, ce.secao)
        and fn_papel_linha(ce.chave) <> 'subtotal'
        and (fn_coluna_periodo_do_ano(v.ver, v_ano) is null
             or fn_normalizar_texto(ce.periodo_coluna)
                = fn_normalizar_texto(fn_coluna_periodo_do_ano(v.ver, v_ano)))
        and fn_lado_do_mutuo(ce.chave, ce.secao_canonica) is not null
    ), por_lado as (
      select lado, abs(sum(valor_base)) as soma_base
      from linhas group by lado
    )
    select
      (select count(*)::int from por_lado) as n_lados,
      (select soma_base from por_lado where lado = 'ativo')   as soma_ativo,
      (select soma_base from por_lado where lado = 'passivo') as soma_passivo,
      -- CONTAGENS SOBRE AS LINHAS, não sobre os lados agregados: com os dois
      -- lados somados num número, `max(n_docs)` por lado dizia "2 documentos"
      -- num par que vem de 3. O que a mensagem promete é quantas peças
      -- sustentam o número, e isso só se conta antes de agrupar.
      count(*)::int as n_linhas,
      count(distinct doc_id)::int as n_docs,
      min(chave) as exemplo,
      bool_or(unidade is null) as tem_sem_escala
    into v_lados
    from linhas;

    if coalesce(v_lados.n_lados, 0) = 0 then
      -- SEM MOTIVO: é o caso comum e legítimo (0117/0123, comportamento
      -- desenhado e preservado) — não achar linha de mútuo NO BALANÇO não é
      -- achado. É o ÚNICO `continue` de LADO A que não alimenta `v_motivos_ano`.
      continue;
    end if;

    -- ---- A PLANILHA DESTE ANO ----------------------------------------------
    -- 0194 (achado 3 da revisão): escolhida POR ANO, não uma vez para a
    -- checagem inteira (ver o cabeçalho da função — MEDIDO em produção
    -- só-leitura, 28/09/2026: "Teste 00" e "teste alto volume - grupo
    -- araucária" têm um documento MUTUOS por data-base, um por ano de
    -- 2021 a 2025; escolher só um fazia os outros anos acusarem
    -- `sem_periodo_par` mesmo com a planilha certa presente no caso;
    -- "teste - Canastra", com uma única planilha de 2025, abria a mesma
    -- pendência falsa para os anos 2023/2024 do período de consulta).
    -- Prioridade: o documento cujo período COBRE `v_ano`; faltando isso, um
    -- documento cujo período não ancora ano nenhum (o mesmo fallback
    -- ambíguo de ANTES desta migration — `v_doc_ano_cobre_ano = false` avisa
    -- o resto do laço para não tratar a sentinela como resolvida). Nenhum
    -- dos dois: a planilha deste exercício não foi entregue — não é achado
    -- de reconciliação, é cobrança de checklist (0186), e fica silenciosa
    -- como o `continue` de cima, só registrada em `v_faltas` para o texto do
    -- `documento_ausente` final, se for o caso.
    --
    -- MEDIDO em produção só-leitura (28/09/2026, "Teste 00", MUTUOS de
    -- 31/12/2023): o caso tem DUAS versões de documento para o MESMO ano — a
    -- reextração deixou uma casca de 0 linhas ao lado da que TEM as 13
    -- linhas — e desempatar só por `criado_em` tinha a MESMA falha do achado
    -- 1 (a casca vazia podia vencer por ter sido criada depois). O critério
    -- é o mesmo dos dois achados: entre os documentos empatados no ano, o
    -- que TEM linha (`tem_linha` abaixo) vence antes do mais recente.
    select d.id,
           (v_ano is not null and pe.id is not null
            and v_ano = any(fn_anos_periodo(pe.tipo, pe.referencia)))
      into v_doc_ano, v_doc_ano_cobre_ano
    from documento d
    left join periodo pe on pe.id = d.periodo_id
    where d.caso_id = p_caso_id
      and d.tipo_taxonomia = 'MUTUOS'
      and (v_ano is null
           or pe.id is null
           or cardinality(coalesce(fn_anos_periodo(pe.tipo, pe.referencia), '{}'::int[])) = 0
           or v_ano = any(fn_anos_periodo(pe.tipo, pe.referencia)))
    order by (v_ano is not null and pe.id is not null
              and v_ano = any(fn_anos_periodo(pe.tipo, pe.referencia))) desc,
             (exists (
                select 1 from campo_extraido ce3
                where ce3.documento_versao_id = fn_versao_atual(d.id)
                  and ce3.valor_num is not null
              )) desc,
             d.criado_em desc
    limit 1;

    if v_doc_ano is null then
      v_faltas := v_faltas || format(
        '%s: a planilha de mútuos deste exercício não foi entregue neste mandato', v_ano);
      continue;
    end if;

    v_ver_mut  := fn_versao_atual(v_doc_ano);
    v_unid_mut := fn_unidade_predominante(v_ver_mut);

    -- OS DEGRAUS SÃO RESOLVIDOS UMA VEZ POR DOCUMENTO (0123) — e agora o
    -- documento pode mudar de ano para ano (achado 3), então esta resolução
    -- entra no laço junto com ele. A pergunta do degrau é "este documento
    -- diferencia natureza no rótulo?"; respondê-la por linha faria a linha
    -- calada de um documento que diferencia entrar junto (o erro original),
    -- e a de um que não diferencia ficar de fora (o outro erro).
    select bool_or(fn_texto_nomeia_mutuo(ce.chave)),
           bool_or(fn_texto_nomeia_mutuo(ce.secao))
      into v_pl_rotulo, v_pl_secao
    from campo_extraido ce
    where ce.documento_versao_id = v_ver_mut
      and ce.valor_num is not null
      and fn_papel_linha(ce.chave) <> 'subtotal';
    v_pl_rotulo := coalesce(v_pl_rotulo, false);
    v_pl_secao  := coalesce(v_pl_secao, false);

    -- 0194: A COLUNA DO SALDO, achada pelo MESMO localizador que a 0145 já
    -- cadastrou para este conceito (`taxonomia_linha_localizador`,
    -- MUTUOS/saldo_de_mutuo, termo 'saldo') — reuso do termo, não um `like`
    -- novo. Lida uma vez por documento: o retrato tem uma coluna de saldo
    -- só, não uma por ano. `v_pl_retrato` (achado 2 da revisão) reaproveita
    -- o MESMO achado: um documento com coluna "saldo" é matricial (chave =
    -- par de empresas), e é isso — não uma palavra no rótulo da linha — que
    -- diz se a linha carrega lado.
    select ce.periodo_coluna into v_col_saldo
    from campo_extraido ce
    where ce.documento_versao_id = v_ver_mut
      and ce.periodo_coluna is not null
      and fn_normalizar_texto(ce.periodo_coluna) like '%saldo%'
    group by ce.periodo_coluna
    order by count(*) desc, ce.periodo_coluna
    limit 1;
    v_pl_retrato := v_col_saldo is not null;

    -- Escala ausente de um dos lados é o mesmo critério conservador da 0009:
    -- não há o que converter, e afirmar "confere" seria pior que calar.
    if coalesce(v_lados.tem_sem_escala, false) <> (v_unid_mut is null) then
      -- 0194: o MESMO vício de texto dos outros `continue` — escala ausente
      -- de um lado terminava no MESMO `documento_ausente` falso. É achado (a
      -- escala não é comparável), não ausência de dado.
      v_motivos_ano := v_motivos_ano || 'unidade_divergente'::text;
      v_faltas := v_faltas || format(
        '%s: escala não comparável entre o balanço e a planilha de mútuos (um lado declara, o outro não)',
        v_ano);
      continue;
    end if;

    -- OS DOIS LADOS SE ESPELHAM: CONFERI-LOS ENTRE SI VEM PRIMEIRO.
    if v_lados.n_lados = 2 then
      v_div := abs(v_lados.soma_ativo - v_lados.soma_passivo);
      v_tol := greatest(p_tolerancia_abs, v_lados.soma_ativo * p_tolerancia_pct);
      if v_div > v_tol then
        -- O achado é dos BALANÇOS, e a planilha não é comparada neste ano:
        -- atribuir a um dos lados uma linha de planilha que não declara lado
        -- seria escolher por sorteio qual metade da contradição é a verdade.
        v_n := v_n + 1;
        v_resultado := 'zona_cinzenta';
        v_partes := v_partes || format(
          '%s: os DOIS LADOS do mesmo mútuo não fecham DENTRO do mandato — a receber soma %s e '
          || 'a pagar soma %s, diferença de %s (em reais). A planilha não foi comparada neste '
          || 'exercício: sem saber qual lado é o correto, atribuir a linha da planilha a um deles '
          || 'seria chute.',
          v_ano, round(v_lados.soma_ativo), round(v_lados.soma_passivo), round(v_div));
        if v_pior_abs is null or v_div > v_pior_abs then
          v_pior_abs := v_div;
          v_pior_pct := case when v_lados.soma_ativo <> 0
                             then v_div / v_lados.soma_ativo end;
        end if;
        continue;
      end if;
      -- Concordam: o saldo do balanço está estabelecido por dupla evidência.
      -- UMA comparação, contra o número que as duas pontas confirmam.
      v_lado_alvo := null;
      v_a := v_lados.soma_ativo;
      v_rotulo_lado := 'os dois lados';
    else
      v_lado_alvo := case when v_lados.soma_ativo is not null then 'ativo' else 'passivo' end;
      v_a := coalesce(v_lados.soma_ativo, v_lados.soma_passivo);
      v_rotulo_lado := v_lado_alvo;
    end if;

    -- 0194: A COLUNA DA PLANILHA-RETRATO. Chegamos aqui só quando o BALANÇO
    -- tem conta de mútuo para este ano (n_lados>0, escala comparável) e uma
    -- planilha foi achada PARA ESTE ANO (achado 3) — então o que falta
    -- resolver agora é só a COLUNA, e é aí que morava o defeito original
    -- desta migration.
    --
    -- `fn_coluna_periodo_do_ano` devolve a sentinela quando o documento TEM
    -- colunas de período e nenhuma é deste ano — a pergunta certa para um
    -- documento COMPARATIVO. A planilha de mútuos de produção não é
    -- comparativa: é um RETRATO de uma data (0145 — o documento é matricial,
    -- a chave é o PAR de empresas e o conceito mora na coluna:
    -- "Mutuante"/"Mutuária"/"Saldo devedor"/"TOTAL"). Nenhum desses
    -- cabeçalhos é ano nenhum, então a sentinela sempre disparava — e antes
    -- desta migration o filtro do LADO B (escrito para NULL) zerava a soma, o
    -- laço caía no `continue` mudo e a função devolvia `documento_ausente`
    -- com um texto falso (ver o cabeçalho). A pergunta certa para um retrato:
    -- o documento escolhido para ESTE ano REALMENTE cobre `v_ano`
    -- (`v_doc_ano_cobre_ano`, achado 3 — não o fallback ambíguo)? Se sim, a
    -- coluna do saldo é a que `v_col_saldo` já achou.
    v_col_mut := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_ver_mut, v_ano) end;
    if v_col_mut = E'\x01' and v_doc_ano_cobre_ano then
      v_col_mut := v_col_saldo;
      if v_col_mut is null then
        -- O documento cobre o ano, mas nenhuma coluna diz "saldo": achado
        -- acionável (o documento pode ter mudado de formato), não silêncio.
        v_motivos_ano := v_motivos_ano || 'linha_nao_localizada'::text;
        v_faltas := v_faltas || format(
          '%s: a planilha de mútuos é retrato deste exercício, mas nenhuma coluna diz '
          '"saldo" (o mesmo termo do localizador da 0145)', v_ano);
        continue;
      end if;
    end if;
    -- `v_ano` nulo (período de consulta que não ancora ano nenhum) ou
    -- `v_doc_ano_cobre_ano = false` (o documento MUTUOS achado só pelo
    -- fallback ambíguo — sem período, ou período que não ancora ano
    -- nenhum): sem como afirmar retrato de QUAL ano, `v_col_mut` segue o que
    -- `fn_coluna_periodo_do_ano` devolveu (tipicamente a sentinela) —
    -- comportamento de ANTES desta migration (mesma exceção que a 0191 já
    -- abre para o Mapa de Dívida). A antiga ramificação "documento não cobre
    -- o ano → `sem_periodo_par`" saiu: a seleção acima (achado 3) já garante
    -- que só se chega aqui com um documento que cobre `v_ano`, ou com o
    -- fallback ambíguo — o caso "não cobre" não sobrevive à seleção. Um
    -- `sem_periodo_par` ainda pode nascer adiante (`fn_motivo_do_lado`), no
    -- raro caso do fallback ambíguo cuja sentinela não resolve nenhuma linha.

    -- ---- LADO B: a planilha ----------------------------------------------
    select coalesce(sum(fn_valor_em_base(ce.valor_num, ce.unidade)), 0) as soma_base,
           coalesce(sum(ce.valor_num), 0) as soma_bruta,
           count(*)::int as n
      into v_pl
    from campo_extraido ce
    where ce.documento_versao_id = v_ver_mut
      and ce.valor_num is not null
      and fn_papel_linha(ce.chave) <> 'subtotal'
      -- MÚTUO CONTRA MÚTUO — nos degraus 1 e 2. A planilha de intragrupo lista
      -- mais coisa que mútuo (conta corrente rotativa, aluguel entre
      -- coligadas, rateio de despesa), e o balanço registra cada natureza num
      -- lugar diferente. Comparar a planilha INTEIRA contra as contas de
      -- mútuo do balanço acusaria como divergência aquilo que é só natureza
      -- diferente.
      --
      -- OS TRÊS DEGRAUS, NA ORDEM. O `case` é o que impede o degrau 2 de valer
      -- quando o degrau 1 existe — sem isso, seção larga ("MÚTUOS E CONTAS
      -- INTRAGRUPO") passa a incluir a conta corrente que o rótulo já tinha
      -- separado, que é o defeito de novo.
      and (case
             when v_pl_rotulo then fn_texto_nomeia_mutuo(ce.chave)
             when v_pl_secao  then fn_texto_nomeia_mutuo(ce.secao)
             else true
           end)
      -- A MESMA RÉGUA DOS DOIS LADOS. Se o balanço exclui o mútuo com sócio e a
      -- planilha não, a diferença que sobra é da régua e não do dado — é o defeito
      -- que a 0123 consertou, cometido de novo em espelho.
      and not fn_mutuo_com_socio(ce.chave, ce.secao)
      -- 0194 (achado 2 da revisão de fidelidade, MEDIDO em produção
      -- só-leitura, 28/09/2026): numa planilha-RETRATO (`v_pl_retrato`) a
      -- `chave` é o PAR de empresas ("ARAUCÁRIA PARTICIPAÇÕES … - AR
      -- SERVIÇOS ADMINISTRATIVOS E COMPARTILHADOS LTDA."), não o lado — e
      -- `fn_lado_do_mutuo` casava "administr**ativo**s" com "...ativo" e
      -- derrubava a linha inteira do lado errado (6,4 mi fora da soma, no
      -- book Canastra — o mesmo 74,56 − 6,40 = 68,16 do achado 1). No "teste
      -- alto volume - grupo araucária" de 2021, as 11 linhas da planilha
      -- chegam com `secao_canonica = 'ativo_circulante'` herdada da
      -- classificação genérica da extração — não é lado contábil nenhum para
      -- uma linha de retrato — e o filtro esvaziava a planilha inteira:
      -- `linha_nao_localizada` falso, 8,725 mi somem. Quando o balanço tem
      -- um lado só e a planilha É comparativa de verdade (`not v_pl_retrato`
      -- — formato da 0123, preservado: o rótulo declara lado de verdade e o
      -- filtro continua valendo), a linha que DECLARA lado tem de ser do
      -- mesmo; a que não declara entra (ela é as duas pontas). Com os dois
      -- lados concordando, `v_lado_alvo` é nulo e não há o que filtrar em
      -- nenhum dos dois formatos.
      and (v_pl_retrato or v_lado_alvo is null
           or coalesce(fn_lado_do_mutuo(ce.chave, ce.secao_canonica), v_lado_alvo) = v_lado_alvo)
      and (v_col_mut is null
           or fn_normalizar_texto(ce.periodo_coluna) = fn_normalizar_texto(v_col_mut));
    if coalesce(v_pl.n, 0) = 0 then
      -- 0194: a coluna FOI resolvida (ou é o caso "sem como afirmar", ver
      -- acima) e mesmo assim nenhuma linha da planilha casou com o lado do
      -- balanço — achado, não ausência.
      v_motivos_ano := v_motivos_ano || fn_motivo_do_lado(false, null, v_col_mut);
      v_faltas := v_faltas || format('%s: %s', v_ano,
        case when v_col_mut = E'\x01'
             then 'a planilha de mútuos não tem coluna deste exercício'
             else 'a planilha de mútuos não tem linha para o lado do balanço neste exercício' end);
      continue;
    end if;

    v_b := abs(coalesce(v_pl.soma_base, 0));
    v_a := abs(coalesce(v_a, 0));
    v_n := v_n + 1;
    v_div := abs(v_a - v_b);
    -- Tolerância em MOEDA BASE (reais), não na escala do documento: o mesmo
    -- número tem de significar a mesma coisa num balanço em milhar e noutro
    -- em unidade, senão a checagem é mais frouxa justamente onde os valores
    -- são maiores.
    v_tol := greatest(p_tolerancia_abs, v_a * p_tolerancia_pct);

    if v_div > v_tol then
      v_resultado := 'zona_cinzenta';
      v_partes := v_partes || format(
        '%s (%s): balanço soma %s em %s linha(s) de %s documento(s) e a planilha soma %s em %s '
        || 'linha(s) — diferença de %s (em reais, já convertidas as escalas)',
        v_ano, v_rotulo_lado, round(v_a), v_lados.n_linhas, v_lados.n_docs, round(v_b),
        v_pl.n, round(v_div));
      if v_pior_abs is null or v_div > v_pior_abs then
        v_pior_abs := v_div;
        v_pior_pct := case when v_a <> 0 then v_div / v_a end;
      end if;
    else
      v_partes := v_partes || format('%s (%s): confere (balanço %s = planilha %s, em reais)',
        v_ano, v_rotulo_lado, round(v_a), round(v_b));
    end if;

    v_fonte_a := jsonb_build_object('lado', v_rotulo_lado, 'soma_base', v_a,
      'n_linhas', v_lados.n_linhas, 'n_documentos', v_lados.n_docs,
      'exemplo', v_lados.exemplo, 'ano', v_ano);
    v_fonte_b := jsonb_build_object('lado', v_rotulo_lado, 'soma_base', v_b,
      'soma_bruta', v_pl.soma_bruta, 'n_linhas', v_pl.n, 'unidade', v_unid_mut,
      'documento_versao_id', v_ver_mut,
      'natureza_no_rotulo', v_pl_rotulo, 'natureza_na_secao', v_pl_secao);
  end loop;

  if v_n = 0 then
    if cardinality(v_motivos_ano) = 0 then
      -- SEM PENDÊNCIA, e é decisão de projeto: `documento_ausente` é o único
      -- resultado que `fn_registrar_reconciliacao` não transforma em pendência.
      -- 0194 (achado 3 da revisão): quando o ÚNICO motivo de nenhum ano ter
      -- concluído é "a planilha deste exercício não foi entregue" (`v_faltas`
      -- não vazio), o texto diz QUAIS anos — ainda é cobrança de checklist,
      -- não achado, mas nomear o ano que falta é a regra 1 (nota com o
      -- efeito, nunca silêncio liso). Sem NENHUM motivo (`v_faltas` também
      -- vazio): o texto genérico de sempre — não achar linha de mútuo NO
      -- BALANÇO é o caso comum e correto (combinado elimina intragrupo;
      -- individual às vezes agrega em "outras partes relacionadas"). Abrir
      -- pendência aqui encheria a fila de todo mandato com um aviso que não
      -- pede ação nenhuma, e uma fila assim é uma fila que ninguém lê.
      return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
        'mutuos_planilha_vs_balanco', 'B', v_doc_mut, null, null,
        'documento_ausente', null, null,
        jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
        case when cardinality(v_faltas) > 0 then
          'Balanço com conta de mútuo presente, mas a planilha de mútuos não cobre o(s) '
          || 'exercício(s) em que ela seria comparada — ' || array_to_string(v_faltas, '; ')
          || '. Sem a planilha do exercício, não há o que conferir; é cobrança de checklist '
          || '(kit básico), não achado de reconciliação.'
        else
          'Planilha de mútuos presente, mas nenhum balanço do mandato traz conta de mútuo com lado '
          || 'reconhecível (combinado elimina intragrupo; individual às vezes agrega em "partes '
          || 'relacionadas"). Sem par, não há o que conferir.'
        end);
    end if;

    -- 0194: o balanço TEM conta de mútuo em algum ano, mas a checagem não
    -- concluiu por outro motivo — documento presente e algo não localizado é
    -- ACHADO ACIONÁVEL (0186), não ausência. Abre pendência
    -- (fn_registrar_reconciliacao: todo motivo de precondição além de
    -- documento_ausente abre).
    v_motivo_prec := fn_motivo_precondicao_agregado(v_motivos_ano);
    return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
      'mutuos_planilha_vs_balanco', 'B', v_doc_mut, null, null,
      v_motivo_prec, null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      fn_motivo_precondicao_prefixo(v_motivo_prec)
      || 'Planilha de mútuos e balanço com conta de mútuo presentes, mas a checagem não concluiu '
      || 'em nenhum exercício. ' || array_to_string(v_faltas, '; ') || '.');
  end if;

  return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
    'mutuos_planilha_vs_balanco', 'B', v_doc_mut, v_fonte_a, v_fonte_b, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'comparacoes', v_n,
                       'natureza_no_rotulo', v_pl_rotulo,
                       'natureza_na_secao', v_pl_secao),
    format('Mútuos: a planilha intragrupo contra o saldo dos balanços em %s comparação(ões) — %s.',
           v_n, array_to_string(v_partes, '; ')));
end;
$$;


comment on function fn_reconciliar_mutuos(uuid, uuid, numeric, numeric) is
  '0194: a planilha de mútuos é um RETRATO de uma data (0145 — o conceito mora na coluna, não é '
  'comparativa): quando a coluna de período sai sentinela e o documento escolhido para o ano cobre '
  'de fato o ano (achado 3), a coluna do saldo é achada pelo localizador da 0145 '
  '(MUTUOS/saldo_de_mutuo, termo ''saldo''), em vez de zerar a comparação e devolver '
  'documento_ausente falso. Retrato sem coluna de saldo, ou planilha sem linha para o lado do '
  'balanço: linha_nao_localizada; escala incomparável: unidade_divergente — abrem pendência (0186), '
  'diferente de documento_ausente. A REVISÃO DE FIDELIDADE (28/09/2026, antes da migration ser '
  'aplicada) mediu três achados sobreviventes, todos corrigidos AQUI: (1) o balanço escolhido por '
  'entidade agora é POR ANO — um documento que só ANCORA o ano sem trazer linha de mútuo não vence '
  'mais o que TRAZ o dado; (2) `fn_lado_do_mutuo` só filtra a planilha quando ela é COMPARATIVA '
  '(0123: rótulo declara lado de verdade) — numa planilha-RETRATO a chave é o PAR de empresas, e o '
  'filtro descartava linha boa por casar "administrativos" com "ativo" ou por herdar '
  '`secao_canonica` sem sentido de lado; (3) a planilha agora é escolhida POR ANO, não uma vez para '
  'a checagem inteira — o ano sem planilha própria vira "planilha deste exercício não entregue" '
  '(documento_ausente, cobrança de checklist), não mais uma pendência falsa quando o caso TEM a '
  'planilha certa de outro ano. 0123: a natureza "mútuo" é lida na linha OU na seção. Confere os '
  'dois lados entre si antes de comparar a planilha; lados que discordam são o achado, e aí a '
  'planilha não é atribuída a um deles. Mútuo com sócio fica fora: não tem espelho no mandato.';

grant execute on function fn_reconciliar_mutuos(uuid, uuid, numeric, numeric) to authenticated;

-- -----------------------------------------------------------------------------
-- Catálogo da sonda — o requisito de CORPO que prova que a substituição da
-- coluna-retrato está instalada (a assinatura não muda: `reconciliar_mutuos`,
-- tipo funcao, migration 0117, continua provando só que a função EXISTE).
-- Marcador é código, não comentário (`sonda_marcador_e_codigo.test.sql`).
--
-- ORDEM 835: a 0193 usa 833/834.
-- -----------------------------------------------------------------------------

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, porque, severidade, ordem) values

  ('mutuos_retrato_de_uma_data', '0194', 'corpo', 'fn_reconciliar_mutuos',
   'v_col_mut := v_col_saldo;',
   'Sem este corpo, a planilha de mútuos (retrato de uma data, conceito na coluna — 0145) sempre '
   'devolve a sentinela em fn_coluna_periodo_do_ano, o filtro do lado B (escrito para NULL) exclui '
   'todas as linhas, e a checagem devolve documento_ausente com um texto falso — MEDIDO EM '
   'PRODUÇÃO (25/09/2026): os 12 casos com planilha MUTUOS nunca concluem, 7 deles com conta de '
   'mútuo no balanço. A REVISÃO DE FIDELIDADE (28/09/2026, antes de aplicar) corrigiu no mesmo '
   'corpo três achados: escolha do balanço POR ANO (não só por criado_em), o filtro de lado só '
   'para planilha comparativa (não para o retrato, cuja chave é o par de empresas), e a planilha '
   'escolhida POR ANO (não uma vez para a checagem inteira).',
   'importante', 835)

on conflict (chave) do update
  set migration = excluded.migration,
      tipo      = excluded.tipo,
      objeto    = excluded.objeto,
      marcador  = excluded.marcador,
      porque    = excluded.porque,
      severidade = excluded.severidade,
      ordem     = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0194', revisado_em = current_date,
       observacao = 'A 0194 reemite fn_reconciliar_mutuos: a planilha de mútuos de produção é um '
         'RETRATO de uma data (conceito na coluna, 0145), não uma demonstração comparativa — a '
         'sentinela de fn_coluna_periodo_do_ano sempre disparava e o filtro (escrito para NULL) '
         'zerava a comparação, devolvendo documento_ausente com texto falso em produção (12/12 '
         'casos nunca concluem, 7 com conta de mútuo no balanço, medido 25/09/2026). Agora, quando '
         'o documento escolhido para o ano cobre de fato o ano, a coluna do saldo é achada pelo '
         'localizador da 0145 (MUTUOS/saldo_de_mutuo, termo ''saldo''). Sem coluna de saldo ou sem '
         'linha para o lado do balanço: linha_nao_localizada; escala incomparável: '
         'unidade_divergente — abrem pendência (0186), diferente de documento_ausente, que '
         'continua reservado a ''nenhum balanço tem conta de mútuo'' ou ''planilha deste exercício '
         'não entregue''. A REVISÃO DE FIDELIDADE (28/09/2026, antes de aplicar) corrigiu, no MESMO '
         'corpo, três achados medidos em produção só-leitura: (1) o balanço por entidade agora é '
         'escolhido POR ANO — um documento que só ancora o ano sem trazer linha de mútuo (ex.: '
         '"multi 24,25" sem coluna nem linha) não vence mais o que traz o dado (ex.: "anual 2025"); '
         '(2) fn_lado_do_mutuo só filtra quando a planilha É comparativa (0123) — numa '
         'planilha-retrato a chave é o par de empresas, e o filtro derrubava linha boa; (3) a '
         'planilha agora é escolhida POR ANO, e não mais uma vez para a checagem inteira — o ano '
         'sem planilha própria vira "planilha deste exercício não entregue" (documento_ausente, '
         'cobrança de checklist), não mais uma pendência falsa quando o caso TEM a planilha certa '
         'de outro ano. IDEMPOTENTE — não roda reconciliação em caso nenhum; só a próxima rodada de '
         'cada caso grava com o ramo novo. Catalogado pelo corpo (mutuos_retrato_de_uma_data) — a '
         'assinatura da função não muda.'
 where id = true;
