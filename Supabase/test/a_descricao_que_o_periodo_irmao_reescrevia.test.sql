-- Testes da 0241: a descrição da pendência só é reescrita pela rodada do MESMO período que ela carrega; o backfill conserta a já contaminada.
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO PROVA (comportamento):
--   (A) dois documentos de períodos COMPATÍVEIS (anual 2024 e multi 24,26) da mesma entidade e do mesmo tipo de checagem, ambos divergentes, em transações separadas (como o n8n, um documento por chamada): continua UMA
--       pendência (a deduplicação por compatibilidade não muda), a do período A, e ela mostra a descrição de A depois que B roda. A rodada seguinte de A reescreve a descrição de A (o mesmo período continua reescrevendo).
--   (B) o mesmo com a rodada de B terminando em pré-condição, sem documento vivo na chave de A (a guarda da divergência irmã da 0192 não a segura): o texto de pré-condição de B não troca o de A.
--   (C) o backfill: uma pendência já contaminada volta a mostrar a descrição da reconciliação mais recente do PRÓPRIO período; é idempotente; grava evento_auditoria (sistema:0241) com a descrição antiga em `antes`;
--       nunca volta a um registro mais antigo que o último do próprio período (não toca e conta); sem registro do próprio período NÃO toca e conta; pendência em decisão humana NÃO é tocada.
--   (E) (revisão) a chave que desce a um período compatível escreve o texto da própria pendência (0192/4), e o backfill reconhece esse texto (periodo_chave_id) em vez de trocá-lo.
--   (F) (revisão) A confere e B segue divergindo: a pendência fica aberta (guarda 0192) e passa a mostrar a divergência de B, não a de A que já não existe.
--   (F2) (2a revisão) o backfill não conta a pendência correta de (F) como contaminada nem sem registro, e grava o resumo mesmo com tudo zero.
--   (G) (revisão) secao_fecha: o documento reclassificado para um período compatível continua reescrevendo o texto da própria pendência.
--   (D) a sonda enxerga os 3 requisitos da 0241.
--
-- HONESTIDADE (regra 4): a contaminação de (C) é fabricada por `update pendencia set descricao`, porque o corpo antigo não existe mais no banco montado. O arranjo real de produção (7 pendências, 11/11/2026) vem do
-- caminho que (A) e (B) exercitam de verdade, e é lá que a correção é medida; (C) prova o backfill sobre o estado que o defeito deixa (descrição de outro período), não que o defeito o produz. A pendência "sem registro
-- do próprio período" é montada trocando o `periodo_id` à mão, pelo mesmo motivo.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número reprovado por sabotagem está no cabeçalho de Supabase/migrations/0241_a_descricao_que_o_periodo_irmao_reescrevia.sql ("MEDIÇÃO NÃO-VAZIA").
-- `p41.medindo = on` (PGOPTIONS='-c p41.medindo=on') vira `raise warning` e CONTA.

\set ON_ERROR_STOP on

create or replace function teste_assert_p41(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('p41.execucoes', (coalesce(nullif(current_setting('p41.execucoes', true), ''), '0')::int + 1)::text, false);
  if p_ok then
    raise notice 'ok    %', p_nome;
  elsif current_setting('p41.medindo', true) = 'on' then
    perform set_config('p41.falhas', (coalesce(nullif(current_setting('p41.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- registra um achado de checagem 'teste_0241' num dos períodos do caso (A = anual 2024, B = multi 24,26), sem entidade
create or replace function teste_reg_p41(p_caso text, p_per text, p_res text, p_desc text, p_doc boolean default false)
returns jsonb language plpgsql as $$
declare v_caso uuid; v_per uuid; v_ent uuid; v_doc uuid;
begin
  select id into v_caso from caso where nome = p_caso;
  select p.id into v_per from periodo p where p.caso_id = v_caso
    and p.referencia = case p_per when 'A' then '2024' else '24,26' end;
  if p_doc then
    select d.entidade_id, d.id into v_ent, v_doc from documento d where d.caso_id = v_caso and d.periodo_id = v_per;
  end if;
  return fn_registrar_reconciliacao(v_caso, v_ent, v_per, 'teste_0241', 'A', v_doc, null, null, p_res, null, null, null, p_desc);
end $$;

-- como teste_reg_p41, mas a chamada vem de uma CHAVE (o período do documento que o laço visita) que pode ser diferente do período em que o resultado fica gravado
create or replace function teste_chave_p41(p_caso text, p_per text, p_chave text, p_res text, p_desc text)
returns jsonb language plpgsql as $$
declare v_caso uuid; v_per uuid; v_ch uuid;
begin
  select id into v_caso from caso where nome = p_caso;
  select id into v_per from periodo where caso_id = v_caso and referencia = case p_per when 'A' then '2024' else '24,26' end;
  select id into v_ch from periodo where caso_id = v_caso and referencia = case p_chave when 'A' then '2024' else '24,26' end;
  perform set_config('oria.periodo_chave', v_ch::text, true);
  return fn_registrar_reconciliacao(v_caso, null, v_per, 'teste_0241', 'A', null, null, null, p_res, null, null, null, p_desc);
end $$;

create or replace function teste_pend_p41(p_caso text) returns pendencia language sql as $$
  select pe.* from pendencia pe join caso c on c.id = pe.caso_id
   where c.nome = p_caso and pe.motivo = 'reconciliacao:teste_0241' and pe.estado <> 'resolvida' order by pe.criada_em limit 1 $$;

delete from caso where nome like '0241: %';

-- FIXTURE 1: dois documentos (o período vem do documento) e os dois períodos compatíveis; FIXTURE 2: só os dois períodos, sem documento (a chave de A não está viva).
do $$
declare v_c uuid;
begin
  v_c := (fn_upsert_caso('0241: com documentos'))::uuid;
  perform fn_registrar_documento(v_c, 'Irma Ltda.', 'anual', '2024', 'BALANCO', 0.95, 'nome_arquivo', 'supabase_storage', 'p41/a.pdf', 'BP anual.pdf', true, 'HASH-P41-A', 'ok');
  perform fn_registrar_documento(v_c, 'Irma Ltda.', 'multi', '24,26', 'BALANCO', 0.95, 'nome_arquivo', 'supabase_storage', 'p41/b.pdf', 'BP multi.pdf', true, 'HASH-P41-B', 'ok');
  v_c := (fn_upsert_caso('0241: sem documentos'))::uuid;
  perform fn_upsert_periodo(v_c, 'anual', '2024');
  perform fn_upsert_periodo(v_c, 'multi', '24,26');
  v_c := (fn_upsert_caso('0241: backfill tipo'))::uuid;
  perform fn_upsert_periodo(v_c, 'anual', '2024');
  perform fn_upsert_periodo(v_c, 'multi', '24,26');
  v_c := (fn_upsert_caso('0241: backfill sem registro'))::uuid;
  perform fn_upsert_periodo(v_c, 'anual', '2024');
  perform fn_upsert_periodo(v_c, 'multi', '24,26');
  v_c := (fn_upsert_caso('0241: backfill decisao humana'))::uuid;
  perform fn_upsert_periodo(v_c, 'anual', '2024');
  perform fn_upsert_periodo(v_c, 'multi', '24,26');
  v_c := (fn_upsert_caso('0241: estado velho'))::uuid;
  perform fn_registrar_documento(v_c, 'Velha Ltda.', 'anual', '2024', 'BALANCO', 0.95, 'nome_arquivo', 'supabase_storage', 'p41/c.pdf', 'BP anual v.pdf', true, 'HASH-P41-C', 'ok');
  perform fn_registrar_documento(v_c, 'Velha Ltda.', 'multi', '24,26', 'BALANCO', 0.95, 'nome_arquivo', 'supabase_storage', 'p41/d.pdf', 'BP multi v.pdf', true, 'HASH-P41-D', 'ok');
  v_c := (fn_upsert_caso('0241: chave desce'))::uuid;
  perform fn_upsert_periodo(v_c, 'anual', '2024');
  perform fn_upsert_periodo(v_c, 'multi', '24,26');
  v_c := (fn_upsert_caso('0241: documento reclassificado'))::uuid;
  perform fn_registrar_documento(v_c, 'Reclas Ltda.', 'anual', '2024', 'BALANCO', 0.95, 'nome_arquivo', 'supabase_storage', 'p41/e.pdf', 'BP reclas.pdf', true, 'HASH-P41-E', 'ok');
  perform fn_upsert_periodo(v_c, 'multi', '24,26');
end $$;

-- A: transações separadas, como o n8n
do $$ begin perform teste_reg_p41('0241: com documentos', 'A', 'divergente', 'A: valor 100 contra 90 (anual 2024)', true); end $$;
do $$ begin perform teste_reg_p41('0241: com documentos', 'B', 'divergente', 'B: valor 500 contra 400 (multi 24,26)', true); end $$;

do $$
declare
  v_p pendencia; v_n int; v_a uuid; v_b uuid; v_c uuid;
begin
  raise notice '--- A. o período irmão não troca a descrição ---';
  select id into v_c from caso where nome = '0241: com documentos';
  select id into v_a from periodo where caso_id = v_c and referencia = '2024';
  select id into v_b from periodo where caso_id = v_c and referencia = '24,26';
  perform teste_assert_p41(fn_periodos_compativeis(v_a, v_b) and v_a <> v_b, 'premissa: anual 2024 e multi 24,26 são períodos distintos e compatíveis');
  select count(*) into v_n from pendencia where caso_id = v_c and motivo = 'reconciliacao:teste_0241' and estado <> 'resolvida';
  perform teste_assert_p41(v_n = 1, 'a deduplicação por período compatível continua: uma pendência para as duas rodadas', format('%s', v_n));
  v_p := teste_pend_p41('0241: com documentos');
  perform teste_assert_p41(v_p.periodo_id = v_a, 'a pendência carrega o período de quem a abriu (A)');
  perform teste_assert_p41(v_p.descricao = 'A: valor 100 contra 90 (anual 2024)', 'a pendência de A mostra a descrição de A depois que a rodada de B rodou', v_p.descricao);
end $$;

do $$ begin perform teste_reg_p41('0241: com documentos', 'A', 'divergente', 'A2: valor 120 contra 90 (anual 2024)', true); end $$;
do $$
declare v_p pendencia;
begin
  v_p := teste_pend_p41('0241: com documentos');
  perform teste_assert_p41(v_p.descricao = 'A2: valor 120 contra 90 (anual 2024)', 'a rodada seguinte do MESMO período continua reescrevendo a descrição', v_p.descricao);
end $$;

-- B: pré-condição do irmão, sem documento vivo na chave de A
do $$ begin perform teste_reg_p41('0241: sem documentos', 'A', 'divergente', 'A: divergência no anual 2024'); end $$;
do $$ begin perform teste_reg_p41('0241: sem documentos', 'B', 'precondicao_nao_satisfeita', 'B: o multi 24,26 não localizou a linha'); end $$;
do $$
declare v_p pendencia;
begin
  raise notice '--- B. a pré-condição do irmão não troca a descrição da divergência ---';
  v_p := teste_pend_p41('0241: sem documentos');
  perform teste_assert_p41(v_p.id is not null and v_p.descricao = 'A: divergência no anual 2024', 'a pré-condição do período irmão não troca o texto da pendência de A', coalesce(v_p.descricao, '(sem pendência)'));
end $$;

-- C1: o backfill conserta a pendência contaminada (caso '0241: com documentos'; o estado contaminado é o que o corpo antigo deixava)
do $$
declare v_p pendencia;
begin
  v_p := teste_pend_p41('0241: com documentos');
  update pendencia set descricao = 'B: valor 500 contra 400 (multi 24,26)' where id = v_p.id;
end $$;
do $$
declare
  v_p pendencia; v_r jsonb; v_c uuid; v_n int; v_antes text; v_por text; v_est text;
begin
  raise notice '--- C. o backfill ---';
  select id into v_c from caso where nome = '0241: com documentos';
  v_p := teste_pend_p41('0241: com documentos'); v_por := v_p.resolvida_por; v_est := v_p.estado::text;
  v_r := fn_corrigir_descricao_contaminada(v_c);
  perform teste_assert_p41((v_r->>'corrigidas')::int = 1 and (v_r->>'contaminadas')::int = 1, 'o backfill acha e corrige a pendência contaminada', v_r::text);
  v_p := teste_pend_p41('0241: com documentos');
  perform teste_assert_p41(v_p.descricao = 'A2: valor 120 contra 90 (anual 2024)', 'e devolve a descrição da reconciliação mais recente do próprio período', v_p.descricao);
  perform teste_assert_p41(v_p.resolvida_por is not distinct from v_por and v_p.estado::text = v_est, 'resolvida_por e estado ficam intocados');
  select count(*) into v_n from evento_auditoria where ator = 'sistema:0241' and entidade_ref = 'pendencia:' || v_p.id and acao = 'descricao_da_pendencia_corrigida';
  perform teste_assert_p41(v_n = 1, 'a trilha de auditoria existe (sistema:0241)', format('%s', v_n));
  select antes->>'descricao' into v_antes from evento_auditoria where ator = 'sistema:0241' and entidade_ref = 'pendencia:' || v_p.id;
  perform teste_assert_p41(v_antes = 'B: valor 500 contra 400 (multi 24,26)', 'com a descrição antiga em antes', coalesce(v_antes, '(null)'));
  v_r := fn_corrigir_descricao_contaminada(v_c);
  perform teste_assert_p41((v_r->>'corrigidas')::int = 0 and (v_r->>'contaminadas')::int = 0, 'idempotente: a segunda chamada não acha nada', v_r::text);
  select count(*) into v_n from evento_auditoria where ator = 'sistema:0241' and entidade_ref = 'pendencia:' || v_p.id;
  perform teste_assert_p41(v_n = 1, 'e não repete a trilha', format('%s', v_n));
end $$;

-- C2: o backfill nunca volta a um registro MAIS ANTIGO que o último do próprio período. A pendência é de DIVERGÊNCIA; o último registro do período é de pré-condição (e o texto dela é o legítimo: o mesmo período
-- reescreve). Contaminada à mão, o backfill não a toca (o último registro não é coerente com o tipo) e conta, em vez de pular o mais novo e devolver a divergência velha.
do $$ begin perform teste_reg_p41('0241: backfill tipo', 'A', 'divergente', 'A: divergência de 10'); end $$;
do $$ begin perform teste_reg_p41('0241: backfill tipo', 'A', 'precondicao_nao_satisfeita', 'A: a checagem não localizou a linha'); end $$;
do $$
declare v_p pendencia; v_r jsonb; v_c uuid;
begin
  select id into v_c from caso where nome = '0241: backfill tipo';
  v_p := teste_pend_p41('0241: backfill tipo');
  perform teste_assert_p41(v_p.tipo::text = 'divergencia_reconciliacao' and v_p.descricao = 'A: a checagem não localizou a linha', 'premissa: pendência de divergência, com o texto da pré-condição mais recente de A (o mesmo período reescreve)', v_p.tipo::text || ' / ' || coalesce(v_p.descricao, ''));
  update pendencia set descricao = 'B: divergência de 99' where id = v_p.id;
  v_r := fn_corrigir_descricao_contaminada(v_c);
  v_p := teste_pend_p41('0241: backfill tipo');
  perform teste_assert_p41((v_r->>'corrigidas')::int = 0 and (v_r->>'sem_registro_proprio')::int = 1 and v_p.descricao = 'B: divergência de 99',
    'o backfill não volta à divergência antiga de A quando o último registro de A é outro: não toca e conta', v_r::text || ' / ' || coalesce(v_p.descricao, ''));
end $$;

-- E: a chave que desce (0192/4). A chave B dá pré-condição no seu período (abre a pendência ali) e desce a A, compatível, onde DIVERGE: na mesma transação, como o laço.
do $$ begin
  perform teste_chave_p41('0241: chave desce', 'B', 'B', 'precondicao_nao_satisfeita', 'B: sem par');
  perform teste_chave_p41('0241: chave desce', 'A', 'B', 'divergente', 'A (chave B): diverge 4340');
end $$;
do $$
declare v_p pendencia; v_r jsonb; v_c uuid;
begin
  raise notice '--- E. a chave que desce a um período compatível escreve o texto da própria pendência ---';
  select id into v_c from caso where nome = '0241: chave desce';
  v_p := teste_pend_p41('0241: chave desce');
  perform teste_assert_p41(v_p.descricao = 'A (chave B): diverge 4340', 'a divergência que a chave B achou ao descer troca a pré-condição da própria chave', coalesce(v_p.descricao, ''));
  v_r := fn_corrigir_descricao_contaminada(v_c);
  v_p := teste_pend_p41('0241: chave desce');
  perform teste_assert_p41((v_r->>'contaminadas')::int = 0 and v_p.descricao = 'A (chave B): diverge 4340',
    'o backfill reconhece o texto da própria chave (periodo_chave_id) e não o troca pelo de pré-condição', v_r::text || ' / ' || coalesce(v_p.descricao, ''));
end $$;

-- F: o estado velho. Rodada 1: A e B divergem. Rodada 2: A confere (ok) e B ainda diverge, com outro número. A guarda 0192 segura a pendência aberta por causa de B; o texto tem de ser o de B, não a divergência de A que já não existe.
do $$ begin perform teste_reg_p41('0241: estado velho', 'A', 'divergente', 'A: 100 contra 90', true); end $$;
do $$ begin perform teste_reg_p41('0241: estado velho', 'B', 'divergente', 'B: 500 contra 400', true); end $$;
do $$ begin
  perform teste_reg_p41('0241: estado velho', 'A', 'ok', 'A: confere', true);
  perform teste_reg_p41('0241: estado velho', 'B', 'divergente', 'B: 700 contra 400', true);
end $$;
do $$
declare v_p pendencia; v_n int;
begin
  raise notice '--- F. a divergência de A que já não existe não fica congelada na pendência ---';
  v_p := teste_pend_p41('0241: estado velho');
  select count(*) into v_n from pendencia pe join caso c on c.id = pe.caso_id where c.nome = '0241: estado velho' and pe.motivo = 'reconciliacao:teste_0241' and pe.estado <> 'resolvida';
  perform teste_assert_p41(v_n = 1, 'A conferiu, B segue divergindo: a pendência continua aberta, uma só (guarda 0192)', format('%s', v_n));
  perform teste_assert_p41(v_p.descricao = 'B: 700 contra 400', 'e mostra a divergência que existe (B), não a de A que já conferiu', coalesce(v_p.descricao, ''));
end $$;
do $$
declare v_c uuid; v_r jsonb; v_n int;
begin
  select id into v_c from caso where nome = '0241: estado velho';
  v_r := fn_corrigir_descricao_contaminada(v_c);
  perform teste_assert_p41((v_r->>'contaminadas')::int = 0 and (v_r->>'sem_registro_proprio')::int = 0 and (v_r->>'corrigidas')::int = 0,
    'o backfill não conta como contaminada nem como "sem registro" a pendência correta em que A conferiu e B segue divergindo', v_r::text);
  perform teste_assert_p41((teste_pend_p41('0241: estado velho')).descricao = 'B: 700 contra 400', 'e não toca o texto dela');
  select count(*) into v_n from evento_auditoria where ator = 'sistema:0241' and acao = 'descricao_contaminada_resumo'
     and depois->>'caso_id' = v_c::text and (depois->>'corrigidas')::int = 0 and (depois->>'contaminadas')::int = 0;
  perform teste_assert_p41(v_n = 1, 'o resumo do backfill é gravado mesmo com tudo zero (trilha de que rodou)', format('%s', v_n));
end $$;

-- G: tipo por documento. A pendência secao_fecha é do documento; o documento passa a outro período compatível (reclassificado) e a árvore chama sem chave: o texto é do documento e tem de seguir.
do $$
declare v_c uuid; v_a uuid; v_d uuid; v_ent uuid;
begin
  select id into v_c from caso where nome = '0241: documento reclassificado';
  select id, entidade_id, periodo_id into v_d, v_ent, v_a from documento where caso_id = v_c;
  perform fn_registrar_reconciliacao(v_c, v_ent, v_a, 'secao_fecha', 'A', v_d, null, null, 'divergente', null, null, null, 'S1: a seção Estoques não fecha');
end $$;
do $$
declare v_c uuid; v_b uuid; v_d uuid; v_ent uuid; v_n int; v_desc text;
begin
  raise notice '--- G. secao_fecha: o texto acompanha o documento reclassificado ---';
  select id into v_c from caso where nome = '0241: documento reclassificado';
  select id into v_b from periodo where caso_id = v_c and referencia = '24,26';
  select id, entidade_id into v_d, v_ent from documento where caso_id = v_c;
  update documento set periodo_id = v_b where id = v_d;   -- reclassificação montada à mão: o documento muda para um período compatível
  perform fn_registrar_reconciliacao(v_c, v_ent, v_b, 'secao_fecha', 'A', v_d, null, null, 'divergente', null, null, null, 'S2: a seção Imobilizado não fecha');
  select count(*), min(descricao) into v_n, v_desc from pendencia where caso_id = v_c and motivo = 'reconciliacao:secao_fecha' and estado <> 'resolvida';
  perform teste_assert_p41(v_n = 1, 'a pendência do documento segue uma só depois da reclassificação', format('%s', v_n));
  perform teste_assert_p41(v_desc = 'S2: a seção Imobilizado não fecha', 'e mostra o texto atual do documento, não o congelado do período antigo', coalesce(v_desc, ''));
end $$;

-- C3: sem registro do próprio período — não toca e conta
do $$ begin perform teste_reg_p41('0241: backfill sem registro', 'A', 'divergente', 'A: divergência de 10'); end $$;
do $$
declare v_p pendencia; v_r jsonb; v_c uuid; v_b uuid;
begin
  select id into v_c from caso where nome = '0241: backfill sem registro';
  select id into v_b from periodo where caso_id = v_c and referencia = '24,26';
  v_p := teste_pend_p41('0241: backfill sem registro');
  update pendencia set periodo_id = v_b, descricao = 'B: divergência de 99' where id = v_p.id;   -- estado montado à mão: o período B não tem registro algum
  v_r := fn_corrigir_descricao_contaminada(v_c);
  v_p := teste_pend_p41('0241: backfill sem registro');
  perform teste_assert_p41((v_r->>'sem_registro_proprio')::int = 1 and (v_r->>'corrigidas')::int = 0, 'sem registro do próprio período: conta e não corrige', v_r::text);
  perform teste_assert_p41(v_p.descricao = 'B: divergência de 99', 'e a descrição não é tocada nem inventada', v_p.descricao);
end $$;

-- C4: decisão humana
do $$ begin perform teste_reg_p41('0241: backfill decisao humana', 'A', 'divergente', 'A: divergência de 10'); end $$;
do $$
declare v_p pendencia; v_r jsonb; v_c uuid;
begin
  select id into v_c from caso where nome = '0241: backfill decisao humana';
  v_p := teste_pend_p41('0241: backfill decisao humana');
  update pendencia set descricao = 'B: divergência de 99', estado = 'em_correcao_interna' where id = v_p.id;
  v_r := fn_corrigir_descricao_contaminada(v_c);
  v_p := teste_pend_p41('0241: backfill decisao humana');
  perform teste_assert_p41((v_r->>'contaminadas')::int = 0 and v_p.descricao = 'B: divergência de 99', 'pendência em decisão humana (em_correcao_interna) não é tocada', v_r::text || ' / ' || coalesce(v_p.descricao, ''));
end $$;

do $$
declare v_n int;
begin
  raise notice '--- D. a sonda enxerga os requisitos da 0241 ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0241' and presente;
  perform teste_assert_p41(v_n = 3, 'os 3 requisitos da 0241 estão presentes na sonda', format('presentes=%s', v_n));
  select count(*) into v_n from instalacao_requisito where migration = '0241';
  perform teste_assert_p41(v_n = 3, 'e o catálogo declara exatamente 3', format('declarados=%s', v_n));

  if current_setting('p41.medindo', true) = 'on' then
    raise warning 'MEDIDO: % falha(s) de % execucoes', coalesce(current_setting('p41.falhas', true), '0'), current_setting('p41.execucoes', true);
  end if;
  raise notice 'TODOS OS TESTES DA 0241 PASSARAM';
end $$;
