-- Testes de `fn_registrar_reconciliacao` (0192, revisão da S102, achados 4, 5 e 6).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO TRAVA, e por que cada bloco é um `do $$` SEPARADO: cada `do $$` é uma
-- TRANSAÇÃO (o psql roda um comando por vez, em autocommit) com `now()` próprio. É isso que
-- reproduz o n8n (`queryBatching: 'independently'`, um documento por chamada) e a "rodada
-- seguinte" — o que a guarda "mesma transação" da primeira versão da 0192 não enxergava.
-- `divergencia_prevalece_na_rodada.test.sql` trava o caso de UMA transação e segue valendo.
--
-- HONESTIDADE (regra 4): os estados são escritos chamando `fn_registrar_reconciliacao`
-- DIRETO, com documentos reais (fn_registrar_documento) e períodos reais. Não se monta uma árvore
-- de balanço que "não fecha" só para produzir a divergência: o que se prova aqui é o CONTRATO do
-- registro (quem resolve e quem não resolve a pendência), não a conta de `fn_conferir_arvore`
-- (essa é de secao_fecha.test.sql). O arranjo real de produção (21 pendências secao_fecha
-- resolvidas em < 10 min, 28/09/2026) não é reproduzível aqui: lá o `documento_id` que resolveu
-- não foi gravado. Afirma-se só o que dá para provar: o `ok` de OUTRO documento deixa de resolver.
--
--   A (achado 5)  dois balanços, mesma entidade e período, transações separadas: um diverge,
--                 o outro fecha (e o outro fica sem seção conferida) — a pendência do divergente
--                 segue aberta; só o PRÓPRIO documento fechando a resolve; dois divergentes
--                 abrem DUAS pendências.
--   B (achado 4)  entre rodadas, o ok do período irmão antes da divergente: nem resolve (mesmo
--                 em `em_correcao_interna`) nem duplica; nas duas ordens.
--   B2            estado VELHO de período sem documento vivo não prende a pendência.
--   C (achado 6)  a descrição é gravada quando NÃO abre pendência.
--   E/F/G (S102, achado 1) estado velho não prende: documento reclassificado pela fila de revisão
--                 (tipo por chave e por documento) e documento com período NULL.
--   H/H2          (terceira correção) a guarda por CHAVE: o laço desce a período de outra entidade
--                 (cenário Pa/Pb, as duas ordens) e os laços gravam a chave.
--   D             o retry da 0152 (pré-condição de um período, ok de outro da MESMA chave) fecha.

\set ON_ERROR_STOP on

create or replace function teste_assert_divvig(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- Fixture COMMITADA: um caso, uma entidade, dois BALANÇOS do mesmo período multi "24,25", o período
-- anual "12M25" (compatível, id diferente) e um período multi "23,24" SEM documento vivo.
do $$
declare
  v_caso uuid; v_r jsonb;
begin
  v_caso := (fn_upsert_caso('0192v: dois balanços, mesmo período'))::uuid;
  perform fn_registrar_documento(v_caso, 'Vigente Ltda.', 'multi', '24,25', 'BALANCO', 0.95,
    'nome_arquivo', 'supabase_storage', 'mp/0192v-a.pdf', 'BP A.pdf', true, 'HASH-0192V-A', 'ok');
  perform fn_registrar_documento(v_caso, 'Vigente Ltda.', 'multi', '24,25', 'BALANCO', 0.95,
    'nome_arquivo', 'supabase_storage', 'mp/0192v-b.pdf', 'BP B.pdf', true, 'HASH-0192V-B', 'ok');
  perform fn_upsert_periodo(v_caso, 'anual', '12M25');
  perform fn_upsert_periodo(v_caso, 'multi', '23,24');
end $$;

-- helper de teste: registra um achado com os ids do fixture, por nome de documento
create or replace function teste_divvig_reg(p_tipo text, p_doc text, p_per text, p_res text, p_desc text)
returns jsonb language plpgsql as $$
declare v_caso uuid; v_ent uuid; v_per uuid; v_doc uuid;
begin
  select id into v_caso from caso where nome = '0192v: dois balanços, mesmo período';
  select entidade_id into v_ent from documento where caso_id = v_caso limit 1;
  select p.id into v_per from periodo p where p.caso_id = v_caso
    and p.referencia = case p_per when 'multi' then '24,25' when 'anual' then '12M25' else '23,24' end;
  select d.id into v_doc from documento d join documento_versao v on v.documento_id = d.id
   where d.caso_id = v_caso and v.nome_original = case p_doc when 'A' then 'BP A.pdf' else 'BP B.pdf' end
   limit 1;
  return fn_registrar_reconciliacao(v_caso, v_ent, v_per, p_tipo, 'A', v_doc, null, null,
    p_res, null, null, null, p_desc);
end $$;

-- =============================================================================
-- A. ACHADO 5 — secao_fecha é POR DOCUMENTO
-- =============================================================================
do $$ begin
  perform teste_divvig_reg('secao_fecha', 'A', 'multi', 'divergente', 'A: seção Estoques não fecha');
end $$;

do $$ begin  -- transação SEPARADA: o n8n processando o balanço B
  perform teste_divvig_reg('secao_fecha', 'B', 'multi', 'ok', 'B: 12 seções conferidas');
end $$;

do $$ begin  -- e de novo, agora B "sem nenhuma seção conferida" (0190: documento_ausente)
  perform teste_divvig_reg('secao_fecha', 'B', 'multi', 'documento_ausente', 'B: nenhuma seção conferida');
end $$;

do $$
declare
  v_caso uuid; v_n int; v_estado text; v_desc text;
begin
  raise notice '--- A. achado 5: o ok/documento_ausente do OUTRO balanço não resolve a divergência ---';
  select id into v_caso from caso where nome = '0192v: dois balanços, mesmo período';
  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:secao_fecha' and estado <> 'resolvida';
  perform teste_assert_divvig(v_n = 1,
    '0192/5: a pendência do balanço A segue aberta depois do ok e do documento_ausente do balanço B',
    format('%s aberta(s) — antes da correção o ok de B a resolvia (21 casos em produção)', v_n));
  select estado::text, descricao into v_estado, v_desc from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:secao_fecha' and estado <> 'resolvida';
  perform teste_assert_divvig(v_desc like 'A:%',
    'e é a pendência do A, com o texto do A (o ok de B não trocou a descrição)', coalesce(v_desc,'(null)'));
  perform teste_assert_divvig(
    (select documento_id from pendencia where caso_id = v_caso and motivo = 'reconciliacao:secao_fecha'
        and estado <> 'resolvida') = (select d.id from documento d join documento_versao v on v.documento_id = d.id where d.caso_id = v_caso and v.nome_original = 'BP A.pdf'),
    'e ela carrega o documento A');
end $$;

do $$ begin  -- B também diverge (transação própria): abre a SUA pendência, não reaproveita a de A
  perform teste_divvig_reg('secao_fecha', 'B', 'multi', 'divergente', 'B: seção Imobilizado não fecha');
end $$;

do $$
declare v_caso uuid; v_n int;
begin
  select id into v_caso from caso where nome = '0192v: dois balanços, mesmo período';
  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:secao_fecha' and estado <> 'resolvida';
  perform teste_assert_divvig(v_n = 2,
    '0192/5: dois balanços que não fecham abrem DUAS pendências, uma por documento',
    format('%s aberta(s)', v_n));
end $$;

do $$ begin  -- A passa a fechar consigo mesmo
  perform teste_divvig_reg('secao_fecha', 'A', 'multi', 'ok', 'A: fecha');
end $$;

do $$
declare v_caso uuid; v_n int; v_res int;
begin
  select id into v_caso from caso where nome = '0192v: dois balanços, mesmo período';
  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:secao_fecha' and estado <> 'resolvida';
  select count(*) into v_res from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:secao_fecha' and estado = 'resolvida';
  perform teste_assert_divvig(v_n = 1 and v_res = 1,
    '0192/5: o PRÓPRIO documento fechando resolve a pendência dele — e só a dele (B segue aberta)',
    format('%s aberta(s), %s resolvida(s)', v_n, v_res));
end $$;

-- =============================================================================
-- B. ACHADO 4 — entre rodadas, o estado vigente decide (tipo por chave: caixa_bp_fluxo)
-- =============================================================================
do $$ begin  -- rodada 1: o período multi diverge
  perform teste_divvig_reg('caixa_bp_fluxo', 'A', 'multi', 'divergente', 'multi: caixa diverge 4340');
end $$;

do $$  -- um humano assume a pendência
declare v_caso uuid;
begin
  select id into v_caso from caso where nome = '0192v: dois balanços, mesmo período';
  update pendencia set estado = 'em_correcao_interna'
   where caso_id = v_caso and motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida';
end $$;

do $$ begin  -- rodada 2: o período anual (irmão compatível) é visitado PRIMEIRO e fecha
  perform teste_divvig_reg('caixa_bp_fluxo', 'A', 'anual', 'ok', 'anual: confere');
end $$;

do $$
declare v_caso uuid; v_n int; v_est text; v_id1 uuid;
begin
  raise notice '--- B. achado 4: entre rodadas, o ok do irmão não resolve a divergência de pé ---';
  select id into v_caso from caso where nome = '0192v: dois balanços, mesmo período';
  select count(*), min(estado::text) into v_n, v_est from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida';
  perform teste_assert_divvig(v_n = 1 and v_est = 'em_correcao_interna',
    '0192/4: o ok do período irmão (rodada seguinte) NÃO resolve a pendência em_correcao_interna',
    format('%s aberta(s), estado %s', v_n, coalesce(v_est,'(nenhum)')));
end $$;

do $$ begin  -- rodada 2, continuação: o multi é visitado e continua divergente
  perform teste_divvig_reg('caixa_bp_fluxo', 'A', 'multi', 'divergente', 'multi: caixa diverge 4340 (de novo)');
end $$;

do $$
declare v_caso uuid; v_n int; v_tot int; v_est text;
begin
  select id into v_caso from caso where nome = '0192v: dois balanços, mesmo período';
  select count(*), min(estado::text) into v_n, v_est from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida';
  select count(*) into v_tot from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:caixa_bp_fluxo';
  perform teste_assert_divvig(v_tot = 1 and v_n = 1 and v_est = 'em_correcao_interna',
    '0192/4: a divergente que chega depois NÃO abre outra — é a mesma pendência, ainda em correção',
    format('%s no total, %s aberta(s), estado %s', v_tot, v_n, coalesce(v_est,'(nenhum)')));
end $$;

do $$ begin  -- rodada 3: o dado foi corrigido; o irmão (anual) fecha de novo e o multi fecha
  perform teste_divvig_reg('caixa_bp_fluxo', 'A', 'anual', 'ok', 'anual: confere');
  perform teste_divvig_reg('caixa_bp_fluxo', 'A', 'multi', 'ok', 'multi: corrigido');
end $$;

do $$
declare v_caso uuid; v_n int;
begin
  select id into v_caso from caso where nome = '0192v: dois balanços, mesmo período';
  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida';
  perform teste_assert_divvig(v_n = 0,
    '0192/4: com os DOIS períodos fechando, a pendência resolve (a guarda não trava resolução legítima)',
    format('%s aberta(s)', v_n));
end $$;

-- B, ordem inversa: irmão ok primeiro, divergente depois, rodadas separadas (tipo distinto)
do $$ begin perform teste_divvig_reg('receita_dre_vs_faturamento', 'A', 'anual', 'ok', 'anual confere'); end $$;
do $$ begin perform teste_divvig_reg('receita_dre_vs_faturamento', 'A', 'multi', 'divergente', 'multi diverge'); end $$;
do $$ begin perform teste_divvig_reg('receita_dre_vs_faturamento', 'A', 'anual', 'ok', 'anual confere de novo'); end $$;
do $$
declare v_caso uuid; v_n int; v_tot int; v_desc text;
begin
  select id into v_caso from caso where nome = '0192v: dois balanços, mesmo período';
  select count(*), min(descricao) into v_n, v_desc from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:receita_dre_vs_faturamento' and estado <> 'resolvida';
  select count(*) into v_tot from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:receita_dre_vs_faturamento';
  perform teste_assert_divvig(v_tot = 1 and v_n = 1 and v_desc = 'multi diverge',
    '0192/4: ok, divergente, ok em rodadas separadas — 1 pendência, aberta, com o texto da divergência',
    format('%s no total, %s aberta(s), descrição %s', v_tot, v_n, coalesce(v_desc,'(null)')));
end $$;

-- =============================================================================
-- B2. estado VELHO de período sem documento vivo não prende a pendência para sempre
-- =============================================================================
-- O período multi "23,24" não tem documento compatível nenhum neste caso (os balanços são
-- "24,25": {2024,2025} ∩ {2023,2024} = {2024} ≠ ∅ — COMPATÍVEL, por isso o fixture usa um
-- caso à parte abaixo).
do $$
declare v_caso uuid;
begin
  v_caso := (fn_upsert_caso('0192v: período sem documento vivo'))::uuid;
  perform fn_registrar_documento(v_caso, 'Vigente Ltda.', 'anual', '12M25', 'BALANCO', 0.95,
    'nome_arquivo', 'supabase_storage', 'mp/0192v-c.pdf', 'BP C.pdf', true, 'HASH-0192V-C', 'ok');
  perform fn_upsert_periodo(v_caso, 'anual', '12M24');
  perform fn_upsert_periodo(v_caso, 'multi', '23,24');
end $$;

create or replace function teste_divvig_reg2(p_per_tipo text, p_per_ref text, p_res text)
returns jsonb language plpgsql as $$
declare v_caso uuid; v_ent uuid; v_per uuid;
begin
  select id into v_caso from caso where nome = '0192v: período sem documento vivo';
  select entidade_id into v_ent from documento where caso_id = v_caso limit 1;
  select id into v_per from periodo where caso_id = v_caso and tipo = p_per_tipo and referencia = p_per_ref;
  return fn_registrar_reconciliacao(v_caso, v_ent, v_per, 'caixa_bp_fluxo', 'A', null, null, null,
    p_res, null, null, null, 'texto ' || p_res);
end $$;

do $$ begin perform teste_divvig_reg2('multi', '23,24', 'divergente'); end $$;  -- abre a pendência em 23,24
do $$ begin perform teste_divvig_reg2('multi', '23,24', 'divergente'); end $$;  -- e o estado vigente de 23,24 é divergente
-- 12M24 (2024) é compatível com 23,24; o único documento do caso é 12M25 (2025): NÃO é compatível
-- com 23,24 — o 23,24 é um período sem documento vivo.
do $$ begin perform teste_divvig_reg2('anual', '12M24', 'ok'); end $$;
do $$
declare v_caso uuid; v_n int;
begin
  raise notice '--- B2. estado velho de período sem documento vivo ---';
  select id into v_caso from caso where nome = '0192v: período sem documento vivo';
  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida';
  perform teste_assert_divvig(v_n = 0,
    '0192/4: divergência velha de período SEM documento vivo não prende a pendência (o ok resolve)',
    format('%s aberta(s)', v_n));
end $$;

-- =============================================================================
-- C. ACHADO 6 — a descrição é gravada SEMPRE
-- =============================================================================
do $$ begin
  perform teste_divvig_reg('secao_fecha', 'B', 'anual', 'documento_ausente',
    'hierarquia achatada: 3 rótulos duplicados');
end $$;
do $$ begin
  perform teste_divvig_reg('mutuos', 'B', 'anual', 'ok', 'confere em 1 ano(s); 2024 sem par');
end $$;
do $$
declare v_caso uuid; v_d1 text; v_d2 text; v_doc uuid;
begin
  raise notice '--- C. achado 6: a descrição é gravada quando a checagem não abre pendência ---';
  select id into v_caso from caso where nome = '0192v: dois balanços, mesmo período';
  select descricao into v_d1 from reconciliacao
   where caso_id = v_caso and tipo = 'secao_fecha' and periodo_id = (select id from periodo where caso_id = v_caso and referencia = '12M25');
  select descricao into v_d2 from reconciliacao where caso_id = v_caso and tipo = 'mutuos';
  perform teste_assert_divvig(v_d1 = 'hierarquia achatada: 3 rótulos duplicados',
    '0192/6: documento_ausente (sem pendência) grava o texto da checagem', coalesce(v_d1,'(null)'));
  perform teste_assert_divvig(v_d2 = 'confere em 1 ano(s); 2024 sem par',
    '0192/6: ok (sem pendência) grava o texto da checagem', coalesce(v_d2,'(null)'));
  select documento_id into v_doc from reconciliacao where caso_id = v_caso and tipo = 'mutuos';
  perform teste_assert_divvig(v_doc = (select d.id from documento d join documento_versao v on v.documento_id = d.id where d.caso_id = v_caso and v.nome_original = 'BP B.pdf'),
    '0192/4-5: e o documento que a checagem recebeu', coalesce(v_doc::text,'(null)'));
end $$;

-- =============================================================================
-- D. O RETRY DA 0152 NÃO MUDA (período diferente, MESMA chave)
-- =============================================================================
do $$ begin perform teste_divvig_reg('ativo_passivo_pl', 'A', 'multi', 'precondicao_nao_satisfeita', 'sem par no multi'); end $$;
do $$
declare v_caso uuid; v_n int;
begin
  select id into v_caso from caso where nome = '0192v: dois balanços, mesmo período';
  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:ativo_passivo_pl' and estado <> 'resolvida';
  perform teste_assert_divvig(v_n = 1, 'retry: a pré-condição abre pendência (comportamento de sempre)',
    format('%s aberta(s)', v_n));
end $$;
do $$ begin perform teste_divvig_reg('ativo_passivo_pl', 'A', 'anual', 'ok', 'anual confere'); end $$;
do $$
declare v_caso uuid; v_n int;
begin
  raise notice '--- D. retry da 0152 ---';
  select id into v_caso from caso where nome = '0192v: dois balanços, mesmo período';
  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:ativo_passivo_pl' and estado <> 'resolvida';
  perform teste_assert_divvig(v_n = 0,
    '0192 NÃO MUDA o retry da 0152: pré-condição de um período seguida de ok de outro da MESMA chave fecha',
    format('%s aberta(s) — devia ser 0', v_n));
end $$;

-- =============================================================================
-- E/F/G. REVISÃO DA S102, ACHADO 1 — estado velho NÃO prende a pendência para sempre
-- =============================================================================
-- Helper: registra um achado pelo NOME do caso, pelo nome do arquivo do documento e pelo período
-- (tipo, referência). O período é buscado/criado por `fn_upsert_periodo`.
create or replace function teste_divvig_reg3(p_caso text, p_arquivo text, p_per_tipo text,
  p_per_ref text, p_tipo text, p_res text, p_desc text)
returns jsonb language plpgsql as $$
declare v_caso uuid; v_ent uuid; v_per uuid; v_doc uuid;
begin
  select id into v_caso from caso where nome = p_caso;
  select d.id, d.entidade_id into v_doc, v_ent from documento d
    join documento_versao v on v.documento_id = d.id
   where d.caso_id = v_caso and v.nome_original = p_arquivo limit 1;
  select id into v_per from periodo where caso_id = v_caso and tipo = p_per_tipo and referencia = p_per_ref;
  return fn_registrar_reconciliacao(v_caso, v_ent, v_per, p_tipo, 'A', v_doc, null, null,
    p_res, null, null, null, p_desc);
end $$;

-- E. O documento é RECLASSIFICADO pela fila de revisão do portal (multi "24,25" -> anual 12M24).
-- A divergência gravada em "24,25" é estado velho de um período que não é mais chave de ninguém:
-- a rodada seguinte reconcilia 12M24, e o ok dela tem de fechar a pendência.
do $$
declare v_caso uuid; v_doc uuid;
begin
  v_caso := (fn_upsert_caso('0192v: documento reclassificado'))::uuid;
  v_doc := (fn_registrar_documento(v_caso, 'Reclass Ltda.', 'multi', '24,25', 'BALANCO', 0.95,
    'nome_arquivo', 'supabase_storage', 'mp/0192v-e.pdf', 'BP E.pdf', true, 'HASH-0192V-E', 'ok')->>'documento_id')::uuid;
  perform fn_upsert_periodo(v_caso, 'anual', '12M24');
end $$;
do $$ begin perform teste_divvig_reg3('0192v: documento reclassificado', 'BP E.pdf', 'multi', '24,25',
  'caixa_bp_fluxo', 'divergente', 'E: caixa diverge em 24,25'); end $$;
do $$ begin perform teste_divvig_reg3('0192v: documento reclassificado', 'BP E.pdf', 'multi', '24,25',
  'secao_fecha', 'divergente', 'E: seção não fecha em 24,25'); end $$;
do $$
declare v_doc uuid;
begin  -- o revisor do portal corrige o período do documento
  select d.id into v_doc from documento d join documento_versao v on v.documento_id = d.id
   where v.nome_original = 'BP E.pdf';
  perform fn_revisar_documento(v_doc, 'humano:revisor', null, null, 'anual', '12M24', 'período era 12M24');
  -- `fn_revisar_documento` grava uma `decisao` (veredito de classificação). Este banco é
  -- COMPARTILHADO com `veredito_producao.test.sql`, que espera zero vereditos: a decisão de
  -- fixture sai daqui, o que este teste prova (a pendência) não depende dela.
  delete from decisao where autor = 'humano:revisor' and payload->>'documento_id' = v_doc::text;
end $$;
do $$ begin perform teste_divvig_reg3('0192v: documento reclassificado', 'BP E.pdf', 'anual', '12M24',
  'caixa_bp_fluxo', 'ok', 'E: 12M24 confere'); end $$;
do $$ begin perform teste_divvig_reg3('0192v: documento reclassificado', 'BP E.pdf', 'anual', '12M24',
  'secao_fecha', 'ok', 'E: 12M24 fecha'); end $$;
do $$
declare v_caso uuid; v_n int;
begin
  raise notice '--- E. achado 1: documento reclassificado pela fila de revisão ---';
  select id into v_caso from caso where nome = '0192v: documento reclassificado';
  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida';
  perform teste_assert_divvig(v_n = 0,
    '0192/1: tipo por chave — a divergência velha de "24,25" (sem documento nesse período) não prende a pendência',
    format('%s aberta(s) depois do ok de 12M24, com o dado corrigido', v_n));
  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:secao_fecha' and estado <> 'resolvida';
  perform teste_assert_divvig(v_n = 0,
    '0192/1: secao_fecha (por documento) — o documento reclassificado de M para A compatível fecha a pendência',
    format('%s aberta(s) depois do ok do próprio documento em 12M24', v_n));
end $$;

-- F. Documento com período NULL na entidade: `fn_periodos_compativeis(NULL, x)` é true, e o
-- filtro de "documento vivo" não filtrava nada (29 de 59 casos em produção têm documento assim).
do $$
declare v_caso uuid;
begin
  v_caso := (fn_upsert_caso('0192v: documento sem período'))::uuid;
  perform fn_registrar_documento(v_caso, 'Sem Periodo Ltda.', 'anual', '12M25', 'BALANCO', 0.95,
    'nome_arquivo', 'supabase_storage', 'mp/0192v-f.pdf', 'BP F.pdf', true, 'HASH-0192V-F', 'ok');
  perform fn_upsert_periodo(v_caso, 'multi', '23,24');
  perform fn_upsert_periodo(v_caso, 'anual', '12M24');
  update documento set periodo_id = null where caso_id = v_caso;
end $$;
do $$ begin perform teste_divvig_reg3('0192v: documento sem período', 'BP F.pdf', 'multi', '23,24',
  'caixa_bp_fluxo', 'divergente', 'F: caixa diverge em 23,24'); end $$;
do $$ begin perform teste_divvig_reg3('0192v: documento sem período', 'BP F.pdf', 'anual', '12M24',
  'caixa_bp_fluxo', 'ok', 'F: 12M24 confere'); end $$;
do $$
declare v_caso uuid; v_n int;
begin
  raise notice '--- F. achado 1: documento com período NULL na entidade ---';
  select id into v_caso from caso where nome = '0192v: documento sem período';
  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida';
  perform teste_assert_divvig(v_n = 0,
    '0192/1: documento com período NULL não conta como "documento vivo" do período velho (não prende)',
    format('%s aberta(s)', v_n));
end $$;

-- =============================================================================
-- H. TERCEIRA CORREÇÃO DA GUARDA (por CHAVE, não por período gravado): o laço DESCE a períodos
-- compatíveis de OUTRAS entidades, e o resultado conclusivo fica num período SEM documento da
-- entidade. Entidade E com Balanço "23,24" (Pa) e "24,25" (Pb); o caso tem 12M24 (P24) de OUTRA
-- entidade. Rodada 1: a chave Pb dá pré-condição, desce a P24 e diverge (pendência em P24; um
-- humano a põe em em_correcao_interna). Rodada 2: a chave Pa dá ok; P24 é compatível com Pa, acha a
-- pendência — e a guarda por período descartava a divergente de P24 (rodada anterior, sem documento
-- exato) e RESOLVIA; Pb, ao chegar, abria OUTRA. Nas DUAS ordens de chave. A chave é simulada com o
-- mesmo `set_config` que os laços fazem; que os laços o fazem é provado em H2.
-- (Regra 4: a rodada 2 é um `do $$` = UMA transação, como a chamada única de fn_reconciliar_caso.)
-- =============================================================================
create or replace function teste_divvig_chave(p_caso text, p_chave text, p_per text, p_res text, p_desc text)
returns jsonb language plpgsql as $$
declare v_caso uuid; v_ent uuid; v_chave uuid; v_per uuid;
begin
  select id into v_caso from caso where nome = p_caso;
  select d.entidade_id into v_ent from documento d join entidade e on e.id = d.entidade_id
   where d.caso_id = v_caso and e.razao_social like 'Chaves E%' limit 1;
  select id into v_chave from periodo where caso_id = v_caso and referencia = p_chave;
  select id into v_per from periodo where caso_id = v_caso and referencia = p_per;
  perform set_config('oria.periodo_chave', v_chave::text, true);
  return fn_registrar_reconciliacao(v_caso, v_ent, v_per, 'caixa_bp_fluxo', 'A', null, null, null,
    p_res, null, null, null, p_desc);
end $$;

create or replace function teste_divvig_monta_chaves(p_caso text)
returns void language plpgsql as $$
declare v_caso uuid;
begin
  v_caso := (fn_upsert_caso(p_caso))::uuid;
  perform fn_registrar_documento(v_caso, 'Chaves E Ltda.', 'multi', '23,24', 'BALANCO', 0.95,
    'nome_arquivo', 'supabase_storage', 'mp/0192h-' || p_caso || '-a.pdf', 'BP Pa.pdf', true, 'HASH-0192H-A-' || p_caso, 'ok');
  perform fn_registrar_documento(v_caso, 'Chaves E Ltda.', 'multi', '24,25', 'BALANCO', 0.95,
    'nome_arquivo', 'supabase_storage', 'mp/0192h-' || p_caso || '-b.pdf', 'BP Pb.pdf', true, 'HASH-0192H-B-' || p_caso, 'ok');
  perform fn_registrar_documento(v_caso, 'Outra Ltda.', 'anual', '12M24', 'BALANCO', 0.95,
    'nome_arquivo', 'supabase_storage', 'mp/0192h-' || p_caso || '-c.pdf', 'BP P24.pdf', true, 'HASH-0192H-C-' || p_caso, 'ok');
end $$;

create or replace function teste_divvig_estado(p_caso text, out n_total int, out n_abertas int, out estado text, out descr text)
language plpgsql as $$
declare v_caso uuid;
begin
  select id into v_caso from caso where nome = p_caso;
  select count(*), count(*) filter (where pe.estado <> 'resolvida'),
         min(pe.estado::text) filter (where pe.estado <> 'resolvida'),
         min(pe.descricao) filter (where pe.estado <> 'resolvida')
    into n_total, n_abertas, estado, descr
    from pendencia pe where pe.caso_id = v_caso and pe.motivo = 'reconciliacao:caixa_bp_fluxo';
end $$;

do $$ begin perform teste_divvig_monta_chaves('0192h: Pa primeiro'); perform teste_divvig_monta_chaves('0192h: Pb primeiro'); end $$;

-- Rodada 1 (as duas): a chave Pb dá pré-condição em Pb e diverge em P24.
do $$ begin
  perform teste_divvig_chave('0192h: Pa primeiro', '24,25', '24,25', 'precondicao_nao_satisfeita', 'Pb sem par');
  perform teste_divvig_chave('0192h: Pa primeiro', '24,25', '12M24', 'divergente', 'P24 diverge 4340');
  perform teste_divvig_chave('0192h: Pb primeiro', '24,25', '24,25', 'precondicao_nao_satisfeita', 'Pb sem par');
  perform teste_divvig_chave('0192h: Pb primeiro', '24,25', '12M24', 'divergente', 'P24 diverge 4340');
  update pendencia set estado = 'em_correcao_interna'
   where motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida'
     and caso_id in (select id from caso where nome like '0192h:%');
end $$;

do $$
declare v_caso uuid; v_chave uuid; v_per uuid; v_n int; e record;
begin
  raise notice '--- H. terceira correção: a guarda raciocina por CHAVE ---';
  select id into v_caso from caso where nome = '0192h: Pa primeiro';
  select periodo_chave_id, periodo_id into v_chave, v_per from reconciliacao
   where caso_id = v_caso and resultado = 'divergente';
  perform teste_assert_divvig(v_chave = (select id from periodo where caso_id = v_caso and referencia = '24,25')
                              and v_per = (select id from periodo where caso_id = v_caso and referencia = '12M24'),
    '0192/4: a linha divergente fica em P24 mas carrega a CHAVE Pb (periodo_chave_id != periodo_id)',
    format('chave=%s periodo=%s', v_chave, v_per));
  select * into e from teste_divvig_estado('0192h: Pa primeiro');
  perform teste_assert_divvig(e.n_total = 1 and e.estado = 'em_correcao_interna',
    'rodada 1: uma pendência, em_correcao_interna', format('%s total, estado %s', e.n_total, e.estado));
end $$;

-- Rodada 2, ORDEM 1: a chave Pa (irmã) é visitada PRIMEIRO e dá ok; depois Pb desce de novo e diverge.
do $$ begin
  perform teste_divvig_chave('0192h: Pa primeiro', '23,24', '23,24', 'ok', 'Pa confere');
end $$;
do $$
declare e record;
begin
  select * into e from teste_divvig_estado('0192h: Pa primeiro');
  perform teste_assert_divvig(e.n_abertas = 1 and e.estado = 'em_correcao_interna',
    '0192/4 (Pa primeiro): o ok da chave irmã Pa NÃO resolve a pendência que a chave Pb deixou em P24',
    format('%s aberta(s), estado %s — a guarda por período a resolvia', e.n_abertas, coalesce(e.estado,'(nenhum)')));
end $$;
do $$ begin
  perform teste_divvig_chave('0192h: Pa primeiro', '24,25', '24,25', 'precondicao_nao_satisfeita', 'Pb sem par');
  perform teste_divvig_chave('0192h: Pa primeiro', '24,25', '12M24', 'divergente', 'P24 diverge 4340');
end $$;
do $$
declare e record;
begin
  select * into e from teste_divvig_estado('0192h: Pa primeiro');
  perform teste_assert_divvig(e.n_total = 1 and e.n_abertas = 1 and e.estado = 'em_correcao_interna'
                              and e.descr = 'P24 diverge 4340',
    '0192/4 (Pa primeiro): a divergente que chega depois NÃO abre outra — mesma pendência, em correção, com o texto da divergência',
    format('%s no total, %s aberta(s), estado %s', e.n_total, e.n_abertas, coalesce(e.estado,'(nenhum)')));
end $$;

-- Rodada 2, ORDEM 2: Pb primeiro (precondição em Pb, divergência em P24), depois Pa ok — em UMA transação.
do $$ begin
  perform teste_divvig_chave('0192h: Pb primeiro', '24,25', '24,25', 'precondicao_nao_satisfeita', 'Pb sem par');
  perform teste_divvig_chave('0192h: Pb primeiro', '24,25', '12M24', 'divergente', 'P24 diverge 4340');
  perform teste_divvig_chave('0192h: Pb primeiro', '23,24', '23,24', 'ok', 'Pa confere');
end $$;
do $$
declare e record;
begin
  select * into e from teste_divvig_estado('0192h: Pb primeiro');
  perform teste_assert_divvig(e.n_total = 1 and e.n_abertas = 1 and e.estado = 'em_correcao_interna'
                              and e.descr = 'P24 diverge 4340',
    '0192/4 (Pb primeiro): uma pendência só, em correção, com o texto da divergência',
    format('%s no total, %s aberta(s), estado %s', e.n_total, e.n_abertas, coalesce(e.estado,'(nenhum)')));
end $$;

-- Rodada 3 (o dado foi corrigido): as DUAS chaves concluem ok -> a guarda não trava a resolução legítima.
do $$ begin
  perform teste_divvig_chave('0192h: Pa primeiro', '23,24', '23,24', 'ok', 'Pa confere');
  perform teste_divvig_chave('0192h: Pa primeiro', '24,25', '24,25', 'ok', 'Pb confere');
  perform teste_divvig_chave('0192h: Pb primeiro', '24,25', '24,25', 'ok', 'Pb confere');
  perform teste_divvig_chave('0192h: Pb primeiro', '23,24', '23,24', 'ok', 'Pa confere');
end $$;
do $$
declare e1 record; e2 record;
begin
  select * into e1 from teste_divvig_estado('0192h: Pa primeiro');
  select * into e2 from teste_divvig_estado('0192h: Pb primeiro');
  perform teste_assert_divvig(e1.n_abertas = 0 and e2.n_abertas = 0,
    '0192/4: com todas as chaves concluindo ok a pendência resolve (nas duas ordens)',
    format('%s e %s aberta(s)', e1.n_abertas, e2.n_abertas));
end $$;

-- H2. Os LAÇOS gravam a chave: fn_reconciliar_caso e fn_reconciliar_por_documento(...,'tudo'). Sem
-- isto o fallback (período da descida) reabre o defeito em produção mesmo com H verde.
do $$
declare v_caso uuid; v_pb uuid; v_n_nulo int; v_n_desce int; v_doc uuid; v_resto text;
begin
  raise notice '--- H2. os laços gravam periodo_chave_id ---';
  perform teste_divvig_monta_chaves('0192h: laços');
  select id into v_caso from caso where nome = '0192h: laços';
  select id into v_pb from periodo where caso_id = v_caso and referencia = '24,25';

  perform fn_reconciliar_caso(v_caso);
  select count(*) filter (where periodo_chave_id is null),
         count(*) filter (where periodo_chave_id is distinct from periodo_id)
    into v_n_nulo, v_n_desce
    from reconciliacao where caso_id = v_caso and tipo in ('ativo_passivo_pl', 'caixa_bp_fluxo');
  perform teste_assert_divvig(v_n_nulo = 0 and v_n_desce > 0,
    'fn_reconciliar_caso grava a CHAVE em toda linha por período, e ela difere do período quando o laço desce',
    format('%s sem chave, %s com chave diferente do período', v_n_nulo, v_n_desce));
  perform teste_assert_divvig(coalesce(current_setting('oria.periodo_chave', true), '') = '',
    'fn_reconciliar_caso zera a chave ao sair (não vaza para a chamada seguinte)',
    coalesce(current_setting('oria.periodo_chave', true), '(null)'));

  delete from reconciliacao where caso_id = v_caso;
  select d.id into v_doc from documento d join documento_versao v on v.documento_id = d.id
   where d.caso_id = v_caso and v.nome_original = 'BP Pb.pdf';
  perform fn_reconciliar_por_documento(v_doc, 'tudo');
  select count(*) filter (where periodo_chave_id is distinct from v_pb),
         count(*) filter (where periodo_chave_id is distinct from periodo_id)
    into v_n_nulo, v_n_desce
    from reconciliacao where caso_id = v_caso and tipo in ('ativo_passivo_pl', 'caixa_bp_fluxo');
  perform teste_assert_divvig(v_n_nulo = 0 and v_n_desce > 0,
    'fn_reconciliar_por_documento(tudo) grava a chave do DOCUMENTO (Pb) em toda linha por período',
    format('%s com outra chave, %s com chave diferente do período', v_n_nulo, v_n_desce));
  perform teste_assert_divvig(coalesce(current_setting('oria.periodo_chave', true), '') = '',
    'fn_reconciliar_por_documento zera a chave ao sair');
end $$;

drop function teste_divvig_estado(text);
drop function teste_divvig_chave(text, text, text, text, text);
drop function teste_divvig_monta_chaves(text);
drop function teste_divvig_reg2(text, text, text);
drop function teste_divvig_reg3(text, text, text, text, text, text, text);
drop function teste_divvig_reg(text, text, text, text, text);
drop function teste_assert_divvig(boolean, text, text);
