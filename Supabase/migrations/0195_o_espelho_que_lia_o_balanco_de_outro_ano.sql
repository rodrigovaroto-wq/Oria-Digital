-- =============================================================================
-- 0195 — O ESPELHO INTRAGRUPO QUE LIA O BALANÇO DE OUTRO ANO
--
-- O DEFEITO. `fn_reconciliar_intragrupo` (0124, corpo vigente até aqui —
-- confirmado que nenhuma migration entre a 0124 e esta reemitiu o corpo:
-- `grep -l "create or replace function fn_reconciliar_intragrupo"
-- Supabase/migrations/*.sql` só acha a 0124) tem os DOIS vícios que a 0194
-- acabou de corrigir em `fn_reconciliar_mutuos`, e o cabeçalho da 0194 já
-- deixou isto registrado, sem corrigir (fora do escopo daquele arquivo):
--
--   1. o balanço de cada entidade é escolhido UMA VEZ para a checagem
--      inteira, só por tipo/`criado_em` — sem preferir, entre os documentos
--      do exercício, o que TRAZ dado daquele ano. A mesma escolha, reaplicada
--      sem mudança a cada `v_ano` do laço `foreach`.
--   2. o filtro de linha (`fn_coluna_periodo_do_ano(v.ver, v_ano) is null`)
--      deixa um documento SEM `periodo_coluna` (balanço de um ano só, sem
--      coluna nenhuma) valer para QUALQUER `v_ano` perguntado — não só o seu
--      próprio, que é o que o período do documento (`periodo.tipo`,
--      `periodo.referencia`) diz.
--
-- MEDIDO EM PRODUÇÃO (28/09/2026, SOMENTE LEITURA — réplica fiel do filtro da
-- 0124, sem alterar nada): nos 7 casos com intragrupo, praticamente TODA linha
-- incluída em cada (caso, ano) vem de um documento cujo período NÃO ancora
-- aquele ano —
--
--   • "teste - Canastra"/2023: 4 de 4 linhas;
--   • "teste alto volume - grupo araucária"/2025: 5 de 5;
--   • "Araucária teste", nos 5 anos (2021…2025): entre 2 e 7 de 7 linhas,
--     SEMPRE 100%.
--
-- Historicamente a tabela `reconciliacao` tem 52 linhas `intragrupo_espelho`
-- com resultado `ok` e 117 `documento_ausente` — ZERO `zona_cinzenta`
-- registrada. É consistente com "ok" por SORTE (o mesmo saldo vazando para
-- todo ano do laço, e o book de cada mandato reaproveitando os mesmos números
-- ano a ano), não com o defeito não existir — a mesma leitura que a 0194 já
-- fez para o vício 1 dos mútuos.
--
-- A CORREÇÃO. A regra é a MESMA que a 0194 já escreveu para `fn_reconciliar_-
-- mutuos` — "documento traz dado deste exercício" na escolha do balanço, e
-- "linha de documento sem coluna de ano só vale se o período do PRÓPRIO
-- documento ancora `v_ano`" no filtro de linha. Escrevê-la uma segunda vez
-- diverge sem erro nenhum (CLAUDE.md, degrau 2 da escada — `buscar.mjs` achou
-- a conta já resolvida). Fatorada aqui em `fn_linha_vale_para_ano`, uma função
-- pequena e pura que responde "esta linha, com esta `periodo_coluna`, deste
-- documento (versão + período do documento), vale para este ano?" — as DUAS
-- funções (`fn_reconciliar_mutuos`, reemitida sem mudar comportamento, e
-- `fn_reconciliar_intragrupo`, reemitida com a correção) passam a chamá-la, em
-- vez de cada uma repetir a mesma conta de três ramos.
--
-- GRUPO A DA REVISÃO (30/09/2026, corrigido NO PRÓPRIO ARQUIVO — a 0195 nunca
-- foi aplicada): três achados, cada um medido não-vazio em
-- Supabase/test/espelho_grupo_a.test.sql (8 asserts; desligado cada item,
-- reprovam 2 + 2 + 2 = 6 dos 8):
--   1. CRÍTICO — `linhas` de fn_reconciliar_mutuos (herdada da 0123) somava
--      DUAS vezes a conta repetida na face e na nota "Partes Relacionadas" do
--      mesmo documento (doc 2f17a7ba, Varejo: 409/890/1.600/2.600/3.900 mil).
--      As "divergências reais" de 409 e 890 mil que a 0194 e o README
--      descreviam ERAM essa duplicata (ver o bloco no corpo e a CORREÇÃO no
--      cabeçalho da 0194). Mútuos MUDA de comportamento nesse ponto.
--   2. ALTO — `criado_em` empata em produção (44 grupos, 160 documentos, 14
--      casos): `d.id` é o último critério nas 3 ordenações (balancos e
--      planilha-do-ano de mútuos; balancos de intragrupo).
--   3. MÉDIO — o "tem dado intragrupo" de fn_reconciliar_intragrupo exige
--      contraparte, lado e escala (a mesma definição do CTE `intragrupo`),
--      não "qualquer linha diferente de zero".
-- Fora desses três pontos, fn_reconciliar_mutuos abaixo é só troca de mecanismo:
-- fn_reconciliar_mutuos NÃO MUDA DE COMPORTAMENTO — é só troca de mecanismo
-- (as duas ocorrências do bloco `v_ano is null or (... is not null and ...)
-- or (... is null and ...)` viram uma chamada a `fn_linha_vale_para_ano`, com
-- os MESMOS argumentos que cada ramo já usava). MEDIDO: `run.sh` inteiro
-- (`mutuos_retrato_de_uma_data.test.sql` e os dois fixtures) fica IDÊNTICO,
-- sem um assert mudando de lado — é o que prova que a fatoração não mexeu na
-- conta, só no lugar onde ela mora.
--
-- fn_reconciliar_intragrupo GANHA OS DOIS CONSERTOS, na mesma forma que a
-- 0194 já validou para os mútuos:
--   • `balancos` passa a escolher, por ENTIDADE, o documento que TEM dado
--     intragrupo (`fn_texto_nomeia_mutuo` fora, `fn_mutuo_com_socio` fora,
--     `fn_linha_vale_para_ano` a favor) de cada ano — antes da prioridade de
--     tipo (BALANCO > DF_AUDITADA > BALANCETE) e do mais recente, que só
--     desempatam quando nenhum documento tem dado, ou mais de um tem;
--   • `linhas` filtra pela MESMA `fn_linha_vale_para_ano`, com o período do
--     documento escolhido (carregado pelo `balancos`) — um balanço de um ano
--     só deixa de valer para os outros anos do período de consulta.
--
-- O RESTO DO CORPO — o pareamento pelo par de empresas (não pela natureza), a
-- exigência dos DOIS lados presentes, a tolerância em base, `COMBINADO` fora,
-- mútuo com sócio fora — NÃO MUDA uma linha.
--
-- MEDIDO NOS FIXTURES DOS DOIS BOOKS (regra 2): NENHUM assert de
-- `canastra.test.sql` ou `reconciliacao.test.sql` muda. Book Canastra: cada
-- entidade só tem UM documento BALANCO no fixture (`fixture_book_canastra.sql`
-- — `select entidade_id, count(*) from documento where tipo_taxonomia =
-- 'BALANCO' group by 1 having count(*) > 1` devolve ZERO linhas), então o
-- vício 1 não tem o que escolher errado ali; e todo `periodo_coluna` do
-- fixture é o ANO em texto (nunca NULO), então `fn_coluna_periodo_do_ano`
-- nunca cai no ramo de "documento sem coluna" que o vício 2 corrigia — os
-- QUATRO pares (2.900, 5.200, 940, 1.900) continuam fechando, com os MESMOS
-- `pares_conferidos` (4 em 2025, 5 no multi 23,24,25). Book Vertentes: a
-- única entidade com DOIS documentos (MT Metalúrgica: BALANCO multi 24,25 +
-- BALANCETE anual 2025) já tinha o BALANCO vencendo pela prioridade de tipo
-- ANTES desta correção — e é o BALANCO quem tem a linha de conta corrente que
-- fecha o par com a VT Logística, então `fn_linha_vale_para_ano` concorda com
-- a escolha de sempre; as 8 checagens (`reconciliacao.test.sql`) continuam
-- chegando a `ok` com o mesmo número.
--
-- OS TESTES NOVOS: `Supabase/test/espelho_grupo_a.test.sql` (grupo A da revisão)
-- e `Supabase/test/intragrupo_le_o_ano_certo.test.sql`, este último exercita
-- o arranjo que os dois fixtures não têm — entidade com balanço de um ano só
-- (sem `periodo_coluna`) consultada em outro ano, e entidade com dois
-- documentos do mesmo par em anos diferentes.
--
-- A PREVISÃO DO EFEITO EM PRODUÇÃO — MEDIDA, não estimada (28/09/2026,
-- SOMENTE LEITURA, réplica da lógica corrigida por consulta direta, mesma
-- técnica da 0194). Ainda ESCRITA, NÃO APLICADA: quem responde de verdade,
-- depois de aplicar, é a sonda:
--
--   select chave, migration, tipo, objeto, presente, detalhe, porque
--     from fn_instalacao_conferir() where not presente order by 1;
--
-- Por (caso, ano), linhas intragrupo que entram / pares com os DOIS balanços /
-- pares que divergem além da tolerância. REMEDIDO em 30/09/2026 (só-leitura,
-- réplica da lógica corrigida INCLUINDO o desempate por `d.id` e a exigência
-- de contraparte+lado+escala na escolha do balanço — os itens 2 e 3 do grupo
-- A da revisão). ANTES = corpo da 0124; DEPOIS = esta migration:
--
-- | caso                                | ano  | ANTES linhas/pares/div | DEPOIS linhas/pares/div | previsto |
-- |--------------------------------------|------|-----------------------:|------------------------:|----------|
-- | teste - Canastra  (= teste Canastra) | 2023 | 4/0/0 | 5/1/0 | ok (1 par) |
-- | teste - Canastra  (= teste Canastra) | 2024 | 8/4/0 | 8/4/0 | ok (4 pares) |
-- | teste - Canastra  (= teste Canastra) | 2025 | 8/4/0 | 8/4/0 | ok (4 pares) |
-- | Teste comparativo - Grupo Canastra   | 2023 | 5/1/0 | 5/1/0 | ok (1 par) |
-- | Teste comparativo - Grupo Canastra   | 2024 | 8/4/0 | 8/4/0 | ok (4 pares) |
-- | Teste comparativo - Grupo Canastra   | 2025 | 7/3/0 | 8/4/0 | ok (4 pares) |
-- | teste v48                            | 2023 | 4/0/0 | 5/1/0 | ok (1 par) |
-- | teste v48                            | 2024 | 7/3/0 | 8/4/0 | ok (4 pares) |
-- | teste v48                            | 2025 | 7/3/0 | 8/4/0 | ok (4 pares) |
-- | teste alto volume - grupo araucária  | 2021 | 3/0/0 | 2/0/0 | documento_ausente (nenhum par com os dois balanços) |
-- | teste alto volume - grupo araucária  | 2022 | (vazio) | 2/0/0 | documento_ausente |
-- | teste alto volume - grupo araucária  | 2023 | 2/0/0 | 2/0/0 | documento_ausente |
-- | teste alto volume - grupo araucária  | 2024 | 2/0/0 | 5/0/0 | documento_ausente |
-- | teste alto volume - grupo araucária  | 2025 | 4/0/0 | 5/0/0 | documento_ausente |
-- | Teste 00                             | 2025 | 2/0/0 | 5/0/0 | documento_ausente |
--
-- CORREÇÃO DESTA TABELA (30/09/2026). A versão de 28/09 previa "documento_-
-- ausente" para Canastra 2023/2024 e "ok" para o alto volume 2023–2025; a
-- remedição com a réplica acima NÃO sustenta nenhuma das duas: o balanço
-- Canastra tem coluna 2023 e 2024 (há par em ambos), e o alto volume não tem
-- NENHUM par com os dois balanços em ano nenhum (pares = 0 nos 5). Os números
-- da versão anterior não eram reproduzíveis e saíram. O que a remedição
-- confirma: nenhuma divergência (div = 0 em todas as 18 linhas), e os itens 2
-- e 3 do grupo A NÃO mudam nenhuma linha da produção (DEPOIS é idêntico com e
-- sem `d.id` e com e sem a exigência de contraparte) — são guardas contra o
-- empate de `criado_em` (44 grupos / 160 documentos / 14 casos) e contra o
-- documento "só com Caixa" vencer, que hoje não mordem em nenhum dos 7 casos.
-- Segue valendo: não há `zona_cinzenta` prevista, e quem responde de verdade,
-- depois de aplicar, é a sonda.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- fn_linha_vale_para_ano — a conta que a 0194 escreveu duas vezes dentro de
-- `fn_reconciliar_mutuos` (a escolha do balanço "que traz dado do ano" e o
-- filtro de linha), fatorada para não divergir quando outra função precisar
-- da mesma resposta (agora `fn_reconciliar_intragrupo`).
--
-- Responde: esta linha, com esta `periodo_coluna`, de um documento cuja
-- VERSÃO é `p_versao` e cujo PERÍODO PRÓPRIO é (`p_periodo_tipo`,
-- `p_periodo_ref`), vale para o ano `p_ano`?
--
--   • `p_ano` nulo (período de consulta que não ancora ano nenhum) → vale
--     sempre (undecidable é melhor que excluir à toa — mesma exceção que a
--     0191 abre para o Mapa de Dívida, preservada pela 0194).
--   • O documento TEM coluna de período e uma delas é `p_ano`
--     (`fn_coluna_periodo_do_ano` devolve o rótulo) → só a linha DESSA coluna
--     vale.
--   • O documento TEM coluna de período mas NENHUMA é `p_ano` (a sentinela
--     `E'\x01'`) → NENHUMA linha vale (é o "documento comparativo, ano fora
--     do que ele cobre" — não cai no ramo de baixo).
--   • O documento NÃO TEM coluna de período nenhuma (`fn_coluna_periodo_do_-
--     ano` devolve `null` puro) → a linha vale só quando o PERÍODO DO PRÓPRIO
--     DOCUMENTO ancora `p_ano` (ou não ancora ano nenhum — undecidable,
--     passa). Ela NÃO vale para qualquer ano perguntado: é exatamente o
--     vício 2, medido pela 0194 em "Teste 00"/2023 e por esta migration em
--     `fn_reconciliar_intragrupo`.
-- ---------------------------------------------------------------------------
create or replace function fn_linha_vale_para_ano(
  p_versao        uuid,
  p_periodo_coluna text,
  p_periodo_tipo   text,
  p_periodo_ref    text,
  p_ano            int
) returns boolean language plpgsql stable as $$
declare
  v_col text;
begin
  if p_ano is null then
    return true;
  end if;

  v_col := fn_coluna_periodo_do_ano(p_versao, p_ano);

  if v_col is not null then
    -- Documento com coluna de período: só a coluna DESTE ano vale — inclusive
    -- quando `v_col` é a sentinela `E'\x01'` (nenhuma coluna é deste ano):
    -- nenhuma `periodo_coluna` normaliza para o byte sentinela, então o
    -- `=` abaixo nunca casa, e a linha corretamente não vale para o ano.
    return fn_normalizar_texto(p_periodo_coluna) = fn_normalizar_texto(v_col);
  end if;

  -- Sem coluna de período nenhuma (retrato/anual de um ano só): vale só
  -- quando o PERÍODO DO PRÓPRIO DOCUMENTO ancora este ano, ou não ancora ano
  -- nenhum (undecidable, passa — comportamento de sempre para este caso).
  return p_periodo_tipo is null
      or cardinality(coalesce(fn_anos_periodo(p_periodo_tipo, p_periodo_ref), '{}'::int[])) = 0
      or p_ano = any(fn_anos_periodo(p_periodo_tipo, p_periodo_ref));
end;
$$;

comment on function fn_linha_vale_para_ano(uuid, text, text, text, int) is
  '0195: uma linha (versão do documento, sua periodo_coluna, e o período PRÓPRIO do documento) vale para o ano pedido? Fatorada da lógica que a 0194 escreveu duas vezes dentro de fn_reconciliar_mutuos — documento sem coluna de período só conta para o ano que o SEU período ancora, nunca para qualquer ano perguntado.';

grant execute on function fn_linha_vale_para_ano(uuid, text, text, text, int) to authenticated;


-- ---------------------------------------------------------------------------
-- fn_reconciliar_mutuos — REEMITIDA A PARTIR DO CORPO VIGENTE (0194), SEM
-- MUDAR COMPORTAMENTO. As duas ocorrências do bloco de três ramos (a
-- prioridade "tem dado do ano" dentro de `balancos`, e o filtro de linha
-- dentro de `linhas`) viram uma chamada a `fn_linha_vale_para_ano` com os
-- MESMOS argumentos que cada ramo já usava — nunca `replace` de texto
-- (`.claude/memory/nunca-corrigir-funcao-por-replace.md`). O resto do corpo
-- é cópia literal da 0194.
-- ---------------------------------------------------------------------------
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
      select distinct on (d.entidade_id) d.id, d.entidade_id,
             pe.tipo as periodo_tipo, pe.referencia as periodo_ref
      from documento d
      join lateral (select fn_versao_atual(d.id) as ver) v on true
      left join periodo pe on pe.id = d.periodo_id
      where d.caso_id = p_caso_id
        and d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DF_AUDITADA')
      order by d.entidade_id,
               -- 0195: fatorada em `fn_linha_vale_para_ano` — mesma conta,
               -- mesmos argumentos (v.ver, ce2.periodo_coluna, pe.tipo,
               -- pe.referencia, v_ano), agora nomeada uma vez só.
               (exists (
                  select 1 from campo_extraido ce2
                  where ce2.documento_versao_id = v.ver
                    and ce2.valor_num is not null
                    and fn_texto_nomeia_mutuo(ce2.chave)
                    and fn_linha_vale_para_ano(v.ver, ce2.periodo_coluna, pe.tipo, pe.referencia, v_ano)
               )) desc,
               array_position(array['BALANCO','COMBINADO','DF_AUDITADA','BALANCETE'],
                              d.tipo_taxonomia),
               d.criado_em desc,
               -- 0195 (achado 2 da revisão): `criado_em` EMPATA em produção (44 grupos,
               -- 160 documentos, 14 casos) e sem último critério o plano escolhe o
               -- documento. `d.id` torna a escolha determinística.
               d.id
    ), linhas as (
      -- 0195 (achado 1 da revisão, CRÍTICO): A MESMA CONTA NA FACE E NA NOTA
      -- ERA SOMADA DUAS VEZES. Medido em produção só-leitura (30/09/2026): o
      -- doc 2f17a7ba (Varejo, multi 21..25) traz "Mútuos a pagar -
      -- controladora" na face do balanço (ordem 38, sem seção) E na nota
      -- "Partes Relacionadas" (ordem 62), mesmo valor, mesma coluna, nos 5
      -- anos — 409 (2021), 890 (2022), 1.600, 2.600, 3.900 mil, todos dobrados.
      -- As "divergências reais" de 409 e 890 mil que o cabeçalho da 0194 e o
      -- Supabase/README.md descreviam ERAM essa duplicata: sem ela os dois
      -- lados fecham exatos. Critério: no MESMO documento, a mesma conta
      -- (rótulo normalizado) na mesma coluna, com o mesmo lado, valor e
      -- escala, é UMA posição lida em dois lugares — conta uma vez (fica a
      -- de menor `ordem`, a face). Valor DIFERENTE com o mesmo rótulo não é
      -- deduplicado (seria outra posição). Medido em TODA a produção: 5
      -- grupos assim em mútuos, todos nesse único documento, 0 com valor
      -- diferente — o critério não toca mais nada.
      select distinct on (d.id, fn_normalizar_texto(ce.chave), ce.periodo_coluna,
                          fn_lado_do_mutuo(ce.chave, ce.secao_canonica),
                          fn_valor_em_base(ce.valor_num, ce.unidade), ce.unidade)
             d.id as doc_id,
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
        -- 0195: fatorada em `fn_linha_vale_para_ano` (mesma conta que a 0194
        -- escreveu inline: documento sem coluna de período só conta para
        -- `v_ano` quando o PRÓPRIO PERÍODO do documento ancora esse ano).
        and fn_linha_vale_para_ano(v.ver, ce.periodo_coluna, d.periodo_tipo, d.periodo_ref, v_ano)
        and fn_lado_do_mutuo(ce.chave, ce.secao_canonica) is not null
      order by d.id, fn_normalizar_texto(ce.chave), ce.periodo_coluna,
               fn_lado_do_mutuo(ce.chave, ce.secao_canonica),
               fn_valor_em_base(ce.valor_num, ce.unidade), ce.unidade, ce.ordem
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
             d.criado_em desc,
             d.id   -- 0195: desempate final determinístico (ver `balancos`)
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
  '0195: mesmo corpo da 0194, SEM MUDAR COMPORTAMENTO — os dois trechos que decidiam "esta linha vale '
  'para este ano" (a prioridade de escolha do balanço em ''balancos'' e o filtro de ''linhas'') agora '
  'chamam fn_linha_vale_para_ano em vez de repetir a conta inline, para não divergir de '
  'fn_reconciliar_intragrupo, que precisa da MESMA resposta. 0194: a planilha de mútuos é um RETRATO '
  'de uma data (0145 — o conceito mora na coluna, não é comparativa): quando a coluna de período sai '
  'sentinela e o documento escolhido para o ano cobre de fato o ano (achado 3), a coluna do saldo é '
  'achada pelo localizador da 0145 (MUTUOS/saldo_de_mutuo, termo ''saldo''), em vez de zerar a '
  'comparação e devolver documento_ausente falso. Retrato sem coluna de saldo, ou planilha sem linha '
  'para o lado do balanço: linha_nao_localizada; escala incomparável: unidade_divergente — abrem '
  'pendência (0186), diferente de documento_ausente. 0123: a natureza "mútuo" é lida na linha OU na '
  'seção. Confere os dois lados entre si antes de comparar a planilha; lados que discordam são o '
  'achado, e aí a planilha não é atribuída a um deles. Mútuo com sócio fica fora: não tem espelho no '
  'mandato.';

grant execute on function fn_reconciliar_mutuos(uuid, uuid, numeric, numeric) to authenticated;


-- ---------------------------------------------------------------------------
-- fn_reconciliar_intragrupo — REEMITIDA A PARTIR DO CORPO VIGENTE (0124), COM
-- OS DOIS CONSERTOS DO CABEÇALHO. O pareamento pelo par de empresas, a
-- exigência dos dois lados presentes, `COMBINADO` fora, mútuo com sócio fora
-- e a tolerância em base NÃO MUDAM uma linha.
-- ---------------------------------------------------------------------------
create or replace function fn_reconciliar_intragrupo(
  p_caso_id        uuid,
  p_periodo_id     uuid,
  p_tolerancia_abs numeric default 50000,
  p_tolerancia_pct numeric default 0.005
) returns jsonb language plpgsql as $$
declare
  v_ano int;
  v_par record;
  v_resultado text := 'ok';
  v_partes text[] := '{}';
  v_n int := 0;
  v_pior_abs numeric; v_pior_pct numeric;
  v_div numeric; v_tol numeric;
  v_fonte_a jsonb := '[]'::jsonb;
  v_pares_conferidos int := 0;
begin
  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    for v_par in
      with balancos as (
        -- UM DOCUMENTO POR ENTIDADE **por ano** — o MESMO defeito que a 0194
        -- mediu e corrigiu em fn_reconciliar_mutuos, medido aqui em produção
        -- só-leitura (28/09/2026): escolher só por tipo/`criado_em`, sem
        -- olhar o ano, reaplica o MESMO documento a todo `v_ano` do laço —
        -- "teste - Canastra"/2023: 4 de 4 linhas incluídas vinham de um
        -- documento que não ancora 2023; "Araucária teste", nos 5 anos,
        -- sempre 100%. Critério agora (0195, mesmo da 0194): entre os
        -- documentos do exercício, o que TEM dado intragrupo elegível para
        -- ESTE ano (`fn_linha_vale_para_ano`) vence o que só ANCORA o ano
        -- sem trazer linha; só então a prioridade de tipo e o mais recente
        -- desempatam. `COMBINADO` fica FORA (ver o cabeçalho da 0124: as
        -- linhas intragrupo dele são eliminações).
        select distinct on (d.entidade_id) d.id, d.entidade_id,
               pe.tipo as periodo_tipo, pe.referencia as periodo_ref
        from documento d
        join lateral (select fn_versao_atual(d.id) as ver) v on true
        left join periodo pe on pe.id = d.periodo_id
        where d.caso_id = p_caso_id
          and d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'DF_AUDITADA')
          and d.entidade_id is not null
        order by d.entidade_id,
                 (exists (
                    select 1 from campo_extraido ce2
                    where ce2.documento_versao_id = v.ver
                      and ce2.valor_num is not null
                      and ce2.valor_num <> 0
                      and fn_papel_linha(ce2.chave) <> 'subtotal'
                      and not fn_texto_nomeia_mutuo(ce2.chave)
                      and not fn_mutuo_com_socio(ce2.chave, ce2.secao)
                      -- 0195 (achado 3 da revisão): "tem dado intragrupo" = a MESMA
                      -- definição de linha intragrupo que o CTE `intragrupo` usa
                      -- (contraparte, lado e escala), não "qualquer linha ≠ 0" —
                      -- senão o documento com saldo de caixa vence o que tem o espelho.
                      and fn_contraparte_intragrupo(p_caso_id, ce2.chave, d.entidade_id) is not null
                      and fn_lado_intragrupo(ce2.chave, ce2.secao_canonica) is not null
                      and ce2.unidade is not null
                      and fn_linha_vale_para_ano(v.ver, ce2.periodo_coluna, pe.tipo, pe.referencia, v_ano)
                 )) desc,
                 array_position(array['BALANCO','DF_AUDITADA','BALANCETE'], d.tipo_taxonomia),
                 d.criado_em desc,
                 d.id   -- 0195: desempate final determinístico (ver fn_reconciliar_mutuos)
      ), linhas as (
        select
          b.entidade_id as dona,
          fn_contraparte_intragrupo(p_caso_id, ce.chave, b.entidade_id) as contraparte,
          fn_lado_intragrupo(ce.chave, ce.secao_canonica) as lado,
          fn_valor_em_base(ce.valor_num, ce.unidade) as valor_base,
          fn_natureza_intragrupo(ce.chave, ce.secao) as natureza,
          ce.chave,
          ce.unidade
        from balancos b
        join lateral (select fn_versao_atual(b.id) as ver) v on true
        join campo_extraido ce on ce.documento_versao_id = v.ver
        where ce.valor_num is not null
          and ce.valor_num <> 0
          and fn_papel_linha(ce.chave) <> 'subtotal'
          -- MÚTUO É DA OUTRA CHECAGEM. Uma linha, uma régua.
          and not fn_texto_nomeia_mutuo(ce.chave)
          and not fn_mutuo_com_socio(ce.chave, ce.secao)
          -- 0195 (mesmo vício de linha que a 0194 corrigiu em
          -- fn_reconciliar_mutuos): documento SEM `periodo_coluna` (retrato/
          -- anual de um ano só) só vale para `v_ano` quando o PRÓPRIO
          -- PERÍODO do documento ancora esse ano — não para qualquer ano
          -- perguntado. `fn_linha_vale_para_ano` responde a MESMA pergunta
          -- que o `balancos` acima já usou para escolher o documento, com o
          -- período DESSE documento (b.periodo_tipo/periodo_ref).
          and fn_linha_vale_para_ano(v.ver, ce.periodo_coluna, b.periodo_tipo, b.periodo_ref, v_ano)
      ), intragrupo as (
        select * from linhas
        where contraparte is not null and lado is not null
          -- ESCALA AUSENTE NÃO SE CONVERTE, e o critério é o da 0009: sem saber a
          -- escala, afirmar "confere" seria pior que calar.
          and unidade is not null
      )
      select
        least(dona, contraparte)    as ent_a,
        greatest(dona, contraparte) as ent_b,
        sum(case when lado = 'ativo'   then abs(valor_base) else 0 end) as receber,
        sum(case when lado = 'passivo' then abs(valor_base) else 0 end) as pagar,
        count(*)::int as n_linhas,
        string_agg(distinct natureza, ', ' order by natureza) as naturezas,
        min(chave) as exemplo
      from intragrupo
      group by 1, 2
      having
        -- OS DOIS LADOS TÊM DE EXISTIR, e a exigência é sobre o par: A e B ambas
        -- com balanço no mandato. Sem isso a falta de espelho é a falta do
        -- documento — que o Portão 1 já cobra — e não erro de número.
        count(distinct dona) = 2
    loop
      v_pares_conferidos := v_pares_conferidos + 1;
      v_div := abs(v_par.receber - v_par.pagar);
      -- Tolerância em MOEDA BASE, como no resto da família (0117/0123): o mesmo
      -- número tem de significar a mesma coisa num balanço em milhar e noutro em
      -- unidade.
      v_tol := greatest(p_tolerancia_abs, greatest(v_par.receber, v_par.pagar) * p_tolerancia_pct);
      v_fonte_a := v_fonte_a || jsonb_build_array(jsonb_build_object(
        'ano', v_ano,
        'entidade_a', (select razao_social from entidade where id = v_par.ent_a),
        'entidade_b', (select razao_social from entidade where id = v_par.ent_b),
        'a_receber', v_par.receber, 'a_pagar', v_par.pagar,
        'naturezas', v_par.naturezas, 'n_linhas', v_par.n_linhas, 'exemplo', v_par.exemplo));
      if v_div > v_tol then
        v_n := v_n + 1;
        v_resultado := 'zona_cinzenta';
        v_partes := v_partes || format(
          '%s — %s × %s (%s): um lado registra %s a receber e o outro %s a pagar, diferença de %s '
          || '(em reais, já convertidas as escalas). A mesma posição intragrupo tem de fechar nos '
          || 'dois balanços; exemplo de linha: "%s"',
          v_ano,
          (select razao_social from entidade where id = v_par.ent_a),
          (select razao_social from entidade where id = v_par.ent_b),
          v_par.naturezas, round(v_par.receber), round(v_par.pagar), round(v_div), v_par.exemplo);
        if v_pior_abs is null or v_div > v_pior_abs then
          v_pior_abs := v_div;
          v_pior_pct := case when greatest(v_par.receber, v_par.pagar) <> 0
                             then v_div / greatest(v_par.receber, v_par.pagar) end;
        end if;
      end if;
    end loop;
  end loop;

  if v_pares_conferidos = 0 then
    -- SEM PENDÊNCIA, pela mesma doutrina da 0117: não haver par intragrupo com os
    -- DOIS balanços no mandato é o caso comum e correto — mandato de uma empresa
    -- só não tem intragrupo, e mandato de grupo pode não ter recebido todos os
    -- balanços. Abrir pendência aqui encheria a fila com um aviso que não pede
    -- ação, e fila assim é fila que ninguém lê.
    return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
      'intragrupo_espelho', 'B', null, null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      'Nenhum par intragrupo com os DOIS balanços no mandato: não há espelho para conferir.');
  end if;

  return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
    'intragrupo_espelho', 'B', null, v_fonte_a, null, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'pares_conferidos', v_pares_conferidos, 'pares_divergentes', v_n),
    case when v_n = 0
      then format('Intragrupo (fora mútuo): %s par(es) de empresas conferido(s) pelo espelho — '
                  || 'todos fecham nos dois balanços.', v_pares_conferidos)
      else format('Intragrupo (fora mútuo): %s de %s par(es) de empresas NÃO fecham — %s.',
                  v_n, v_pares_conferidos, array_to_string(v_partes, '; ')) end);
end;
$$;

comment on function fn_reconciliar_intragrupo(uuid, uuid, numeric, numeric) is
  '0195: a posição intragrupo entre cada PAR de empresas fecha nos dois balanços? Pareia pelo par de '
  'empresas (a contraparte vem do rótulo), não pela natureza — cada ponta usa o vocabulário dela. '
  'Mútuo fica com fn_reconciliar_mutuos. CORRIGIDO (mesmo vício que a 0194 já tinha corrigido em '
  'fn_reconciliar_mutuos, medido em produção só-leitura 28/09/2026): o balanço de cada entidade é '
  'escolhido POR ANO (fn_linha_vale_para_ano decide quem TEM dado do exercício, antes da prioridade '
  'de tipo) — não mais uma escolha só por criado_em, reaplicada sem mudança a cada ano do laço; e uma '
  'linha de documento SEM periodo_coluna só vale para o ano que o PRÓPRIO PERÍODO do documento ancora '
  '— não para qualquer ano perguntado.';

grant execute on function fn_reconciliar_intragrupo(uuid, uuid, numeric, numeric) to authenticated;


-- -----------------------------------------------------------------------------
-- Catálogo da sonda — o requisito de CORPO que prova que os dois consertos
-- estão instalados na intragrupo (a assinatura não muda: `reconciliar_-
-- intragrupo`, tipo funcao, migration 0124, continua provando só que a função
-- EXISTE). fn_reconciliar_mutuos não ganha requisito novo — o comportamento
-- não muda, só o mecanismo, e o requisito `mutuos_retrato_de_uma_data` da
-- 0194 já cobre o corpo que importa. Marcador é código, não comentário
-- (`sonda_marcador_e_codigo.test.sql`).
--
-- ORDEM 836: a 0194 usa 835.
-- -----------------------------------------------------------------------------

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, porque, severidade, ordem) values

  ('intragrupo_documento_por_ano', '0195', 'corpo', 'fn_reconciliar_intragrupo',
   'fn_linha_vale_para_ano(v.ver, ce.periodo_coluna, b.periodo_tipo, b.periodo_ref, v_ano)',
   'Sem este corpo, o balanço de cada entidade é escolhido UMA VEZ para a checagem inteira (só por '
   'tipo/criado_em) e reaplicado sem mudança a cada ano do laço, e uma linha de documento sem '
   'periodo_coluna vale para QUALQUER ano perguntado — MEDIDO EM PRODUÇÃO (28/09/2026, só-leitura, '
   'réplica fiel do filtro da 0124): nos 7 casos com intragrupo, praticamente 100% das linhas '
   'incluídas por (caso, ano) vêm de um documento que NÃO ancora aquele ano (''teste - Canastra''/2023: '
   '4 de 4; ''teste alto volume''/2025: 5 de 5; ''Araucária teste'', os 5 anos, sempre 100%). É o MESMO '
   'vício que a 0194 já corrigiu em fn_reconciliar_mutuos, medido e não corrigido lá por instrução '
   'explícita de escopo.',
   'importante', 836),

  ('mutuos_conta_repetida_conta_uma_vez', '0195', 'corpo', 'fn_reconciliar_mutuos',
   'select distinct on (d.id, fn_normalizar_texto(ce.chave), ce.periodo_coluna,',
   'Sem este corpo o lado A de mútuos soma DUAS vezes a mesma conta quando o balanço a traz na face E '
   'na nota "Partes Relacionadas" — MEDIDO EM PRODUÇÃO (30/09/2026, só-leitura): o doc 2f17a7ba '
   '(Varejo, multi 21..25) repete "Mútuos a pagar - controladora" nos 5 anos (409, 890, 1.600, 2.600, '
   '3.900 mil), e as "divergências reais" de 409 e 890 mil do teste alto volume eram essa duplicata. '
   'Em TODA a produção são 5 grupos assim em mútuos, todos nesse documento.',
   'importante', 837),

  ('intragrupo_dado_exige_contraparte', '0195', 'corpo', 'fn_reconciliar_intragrupo',
   'fn_contraparte_intragrupo(p_caso_id, ce2.chave, d.entidade_id) is not null',
   'Sem este corpo o "documento tem dado intragrupo" aceita qualquer linha diferente de zero (um saldo '
   'de caixa), e o balanço sem contraparte pode vencer o que tem o espelho.',
   'importante', 838)

on conflict (chave) do update
  set migration = excluded.migration,
      tipo      = excluded.tipo,
      objeto    = excluded.objeto,
      marcador  = excluded.marcador,
      porque    = excluded.porque,
      severidade = excluded.severidade,
      ordem     = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0195', revisado_em = current_date,
       observacao = 'A 0195 fatora fn_linha_vale_para_ano (a conta que a 0194 escreveu duas vezes '
         'dentro de fn_reconciliar_mutuos) e reemite fn_reconciliar_mutuos usando-a SEM MUDAR '
         'COMPORTAMENTO (só o mecanismo — nenhum assert de canastra.test.sql/reconciliacao.test.sql/ '
         'mutuos_retrato_de_uma_data.test.sql muda). fn_reconciliar_intragrupo (0124) ganha os DOIS '
         'consertos que a 0194 já tinha aplicado à mútuos e registrado, sem corrigir, no próprio '
         'cabeçalho: o balanço de cada entidade agora é escolhido POR ANO (o que TEM dado intragrupo '
         'do exercício vence o que só ancora o ano sem trazer linha), e uma linha de documento sem '
         'periodo_coluna só vale para o ano que o PRÓPRIO PERÍODO do documento ancora. MEDIDO EM '
         'PRODUÇÃO SÓ-LEITURA (28/09/2026): nos 7 casos com intragrupo, praticamente 100% das linhas '
         'incluídas por (caso, ano) vinham de um documento que não ancora aquele ano; a tabela '
         'reconciliacao tem 52 linhas intragrupo_espelho ok e 117 documento_ausente, ZERO '
         'zona_cinzenta — consistente com "ok" por sorte (o mesmo saldo vazando para todo ano), não '
         'com o defeito não existir. PREVISÃO (réplica da lógica corrigida, só-leitura): os 52 ok '
         'históricos continuam ok (mesmos números, menos anos por caso — os anos sem balanço próprio '
         'do par viram documento_ausente, honesto, em vez de reaplicar o balanço de outro ano). '
         'IDEMPOTENTE — não roda reconciliação em caso nenhum; só a próxima rodada de cada caso grava '
         'com o corpo novo. Catalogado pelo corpo (intragrupo_documento_por_ano) — a assinatura da '
         'função não muda.'
 where id = true;
