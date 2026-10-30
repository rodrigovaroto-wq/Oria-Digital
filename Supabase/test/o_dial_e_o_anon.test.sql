-- =============================================================================
-- 0217 — O DIAL QUE SÓ MEDIA O RECORTE DE QUEM DISPARAVA, e o `anon` que tinha privilégio demais
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md): 69 chamadas de assert, 82 execuções (uma chamada roda 14 vezes, na seção 9) — o número por correção desligada está no cabeçalho de
-- Supabase/migrations/0217_o_dial_que_so_media_o_recorte_de_quem_disparava.sql ("MEDIÇÃO NÃO-VAZIA"). Controle intacto: 82 ok, 0 falhas.
--
-- COMO RODA. Uma transação só (`begin` ... `rollback`): o teste apaga todas as decisões para controlar o denominador do veredito global,
-- concede privilégios a `anon` para simular o banco de produção ANTES da 0217 e reaplica a migration por cima (`\i`) — nada disso pode
-- ficar. Cada usuário é um JWT (`request.jwt.claims`) mais `set local role authenticated`, o que o PostgREST faz; `anon` é
-- `set_config('request.jwt.claims','{"role":"anon"}')` + `set local role anon` — e o JWT é LIMPO antes, porque o banco de teste guarda o
-- de um Sócio em pg_db_role_setting e sem limpar o "anon" viraria Sócio e o teste mentiria. A montagem usa as funções que o portal e o n8n
-- chamam (fn_upsert_caso, fn_registrar_documento, fn_decidir_pendencia, fn_definir_papel, fn_alocar).
--
-- O QUE AFIRMA (comportamento, não mecanismo):
--   1. O veredito de produção GLOBAL é um só, para qualquer papel. Analista alocado num recorte de concordância ALTA com a global
--      insuficiente decide uma pendência e o dial NÃO sobe; com a global suficiente e o recorte dele insuficiente, o dial SOBE — disparado
--      por Analista ou por Sócio, para todos, com a trilha `sistema:auto_dial`.
--   2. Analista não muda o dial à mão (função, UPDATE direto, nem com a marca da promoção posta por fora); Sócio muda.
--   3. As métricas da tela /autonomia (veredito, classe contábil, classe A, cobertura do golden) devolvem o MESMO número a Sócio e a
--      Analista; com um mandato (p_caso_id) só se o chamador o lê; sem papel nenhum, nada.
--   4. Com os privilégios que produção tinha ANTES (concedidos aqui dentro), a migration reaplicada os remove: nenhuma tabela, view,
--      sequence nem função de public fica com privilégio para `anon` (nem de coluna, nem herdado de PUBLIC); authenticated e
--      service_role ficam EXATAMENTE como estavam; o default privilege de anon some; o que anon tentava (os caminhos de escalada) leva
--      42501; e a sonda acusa o privilégio que se conceder a anon depois.
-- =============================================================================

\set ON_ERROR_STOP on
\if :{?arq0217}
\else
  \set arq0217 'Supabase/migrations/0217_o_dial_que_so_media_o_recorte_de_quem_disparava.sql'
\endif

begin;

-- `dial.medindo = on` (PGOPTIONS='-c dial.medindo=on') vira `raise warning` e CONTA: é como se mede quantos asserts uma correção
-- desligada reprova, sem parar no primeiro. Sem a variável, o assert é `raise exception` (o comportamento do CI).
create or replace function teste_assert_0217(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('dial.execucoes', (coalesce(nullif(current_setting('dial.execucoes', true), ''), '0')::int + 1)::text, false);
  if coalesce(p_cond, false) then
    raise notice 'ok    %', p_nome;
  elsif current_setting('dial.medindo', true) = 'on' then
    perform set_config('dial.falhas', (coalesce(nullif(current_setting('dial.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- Executa um comando COMO o papel corrente: 'ok:<linhas>' ou o SQLSTATE.
create or replace function teste_tenta_0217(p_sql text) returns text
language plpgsql as $$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return 'ok:' || n;
exception when others then
  return sqlstate;
end $$;

create or replace function teste_como_0217(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '{"role":"authenticated"}'
         else jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
  execute 'set local role authenticated';
end $$;

-- Volta a superusuário COM o JWT do Sócio de teste (reset role sozinho deixaria no ar o JWT do último usuário).
create or replace function teste_super_0217(p_socio uuid) returns void
language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_socio, 'role', 'authenticated')::text, true);
end $$;

-- N vereditos de revisão de documento no mandato, `p_acertos` deles confirmando (o que fn_revisar_documento grava).
create or replace function teste_semear_0217(p_caso uuid, p_n int, p_acertos int) returns void
language plpgsql as $$
declare i int;
begin
  for i in 1..p_n loop
    insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (p_caso, (case when i <= p_acertos then 'aprovacao' else 'correcao_classificacao' end)::decisao_tipo,
            'analista:0217', 'veredito de teste',
            jsonb_build_object('documento_id', gen_random_uuid(), 'tipo_de', 'balanco_patrimonial',
                               'tipo_para', case when i <= p_acertos then 'balanco_patrimonial' else 'balancete' end));
  end loop;
end $$;

-- Põe o estágio em N1 com a promoção DESLIGADA, semeia os vereditos (o gatilho roda a cada linha) e SÓ ENTÃO liga a promoção: o que o
-- teste mede é a decisão que o Analista toma depois, não a semeadura.
create or replace function teste_cenario_0217(p_a uuid, p_a_n int, p_a_ac int, p_b uuid, p_b_n int, p_b_ac int) returns void
language plpgsql as $$
begin
  update estagio_autonomia
     set nivel_atual = 'N1', base_do_nivel = 'nao_se_aplica', auto_promocao = false, medicao_em = null, medicao_resumo = null,
         atualizado_por = 'teste:0217'
   where estagio = 'classificacao_doc_checklist';
  delete from decisao where autor = 'analista:0217';
  perform teste_semear_0217(p_a, p_a_n, p_a_ac);
  perform teste_semear_0217(p_b, p_b_n, p_b_ac);
  update estagio_autonomia set auto_promocao = true where estagio = 'classificacao_doc_checklist';
end $$;

create or replace function teste_nivel_0217() returns text
language sql as $$ select nivel_atual::text from estagio_autonomia where estagio = 'classificacao_doc_checklist' $$;

-- Os vereditos já gravados por OUTRAS suítes não podem entrar no denominador (a transação volta).
delete from decisao;

-- =============================================================================
-- PARTE 1 — O DIAL
-- =============================================================================
do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000000c101';   -- Sócio
  u_ana   uuid := '00000000-0000-0000-0000-00000000c102';   -- Analista, alocada em A
  u_nil   uuid := '00000000-0000-0000-0000-00000000c104';   -- SEM papel
  v_a uuid; v_b uuid; v_r jsonb; v_rs jsonb; v_t text; v_nmin int; v_est constant text := 'classificacao_doc_checklist';
  v_ver_a uuid; v_ver_b uuid; v_doc_a uuid; v_doc_b uuid; v_p1 uuid; v_p2 uuid; v_p3 uuid; v_ev0 int; v_ev1 int;
  v_campo uuid; v_i int; v_rod uuid; v_cob_s jsonb; v_cob_a jsonb; v_n int;
begin
  insert into auth.users (id, email) values (u_socio, 'socio@0217.local'), (u_ana, 'ana@0217.local'), (u_nil, 'nil@0217.local');
  perform fn_definir_papel(u_socio, 'socio', 'teste 0217');
  perform fn_definir_papel(u_ana, 'analista');
  v_a := fn_upsert_caso('0217 — mandato A');
  v_b := fn_upsert_caso('0217 — mandato B');
  perform fn_alocar(v_a, u_ana);
  select n_minimo_veredito into v_nmin from golden_criterio where estagio = v_est;

  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
    values (v_a, 'completude', 'item_sem_conteudo', 'bloqueante', true, 'p1 de A') returning id into v_p1;
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
    values (v_a, 'completude', 'item_sem_conteudo', 'bloqueante', true, 'p2 de A') returning id into v_p2;
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
    values (v_a, 'completude', 'item_sem_conteudo', 'bloqueante', true, 'p3 de A') returning id into v_p3;

  raise notice '--- 1. a global INSUFICIENTE e o recorte da Analista SUFICIENTE: decidir NÃO promove ---';
  -- A: v_nmin vereditos a 100%. B: 3 x v_nmin a 33%. Global: 4 x v_nmin vereditos a 50%. O recorte de A sozinho passaria no critério.
  perform teste_cenario_0217(v_a, v_nmin, v_nmin, v_b, v_nmin * 3, v_nmin);
  v_r := fn_veredito_producao(v_est);
  perform teste_assert_0217((v_r->>'suficiente')::boolean = false and (v_r->>'n')::int = v_nmin * 4,
    'controle: o veredito GLOBAL é insuficiente (4 x mínimo vereditos a 50%)', v_r::text);
  perform teste_assert_0217(teste_nivel_0217() = 'N1', 'controle: a promoção está ligada e o estágio parte de N1');

  perform teste_como_0217(u_ana);
  v_rs := fn_veredito_producao(v_est);
  perform teste_assert_0217(v_rs = v_r, 'a Analista recebe o MESMO veredito global que o Sócio (não o do recorte dela)', v_rs::text);
  perform teste_assert_0217((fn_veredito_producao(v_est, v_a)->>'suficiente')::boolean
                            and (fn_veredito_producao(v_est, v_a)->>'n')::int = v_nmin,
    'controle: o recorte do mandato A, que ela lê, É suficiente (a armadilha está armada: quem medisse o recorte promoveria)');
  v_t := teste_tenta_0217(format($q$select fn_decidir_pendencia(%L, 'ana@0217', 'prosseguir', 'decidida pela Analista')$q$, v_p1));
  perform teste_assert_0217(v_t = 'ok:1', 'a decisão da Analista é gravada: o gatilho não a derruba', v_t);
  perform teste_super_0217(u_socio);
  perform teste_assert_0217((select count(*) from decisao where caso_id = v_a and autor = 'ana@0217') = 1,
    'controle: a decisão da Analista virou linha em decisao (foi ela que disparou o gatilho)');
  perform teste_assert_0217(teste_nivel_0217() = 'N1',
    'o dial NÃO sobe: o veredito global (50%) é insuficiente, ainda que o recorte da Analista (100%) passasse', teste_nivel_0217());

  raise notice '--- 2. a global SUFICIENTE e o recorte da Analista INSUFICIENTE: a promoção acontece, disparada por ela ---';
  perform teste_cenario_0217(v_a, 5, 5, v_b, v_nmin * 4, v_nmin * 4);
  v_r := fn_veredito_producao(v_est);
  perform teste_assert_0217((v_r->>'suficiente')::boolean and (v_r->>'concordancia')::numeric = 1,
    'controle: o veredito GLOBAL é suficiente (todos os vereditos confirmam)', v_r::text);
  select count(*) into v_ev0 from evento_auditoria where acao = 'mudanca_dial' and ator = 'sistema:auto_dial' and entidade_ref = 'estagio:' || v_est;
  perform teste_como_0217(u_ana);
  perform teste_assert_0217(not (fn_veredito_producao(v_est, v_a)->>'suficiente')::boolean,
    'controle: o recorte de A é INSUFICIENTE (5 vereditos, mínimo ' || v_nmin || '): quem medisse o recorte NÃO promoveria');
  v_t := teste_tenta_0217(format($q$select fn_decidir_pendencia(%L, 'ana@0217', 'prosseguir', 'decidida pela Analista')$q$, v_p2));
  perform teste_assert_0217(v_t = 'ok:1', 'a decisão da Analista é gravada', v_t);
  perform teste_super_0217(u_socio);
  perform teste_assert_0217(teste_nivel_0217() = 'N2',
    'o dial SOBE para N2, disparado pela Analista, porque a concordância do BANCO alcançou o critério', teste_nivel_0217());
  perform teste_assert_0217((select base_do_nivel from estagio_autonomia where estagio = v_est) = 'medida_por_veredito',
    'e a base declara que o rótulo é piso enviesado (medida_por_veredito)');
  select count(*) into v_ev1 from evento_auditoria where acao = 'mudanca_dial' and ator = 'sistema:auto_dial' and entidade_ref = 'estagio:' || v_est;
  perform teste_assert_0217(v_ev1 - v_ev0 = 1, 'a trilha guarda UMA promoção com o ator sistema:auto_dial', (v_ev1 - v_ev0)::text);

  raise notice '--- 3. o mesmo, disparado pelo Sócio (não-regressão) ---';
  perform teste_cenario_0217(v_a, 5, 5, v_b, v_nmin * 4, v_nmin * 4);
  perform teste_como_0217(u_socio);
  v_t := teste_tenta_0217(format($q$select fn_decidir_pendencia(%L, 'socio@0217', 'prosseguir', 'decidida pelo Sócio')$q$, v_p3));
  perform teste_super_0217(u_socio);
  perform teste_assert_0217(v_t = 'ok:1' and teste_nivel_0217() = 'N2', 'o Sócio que decide uma pendência também promove (global suficiente)', v_t || ' / ' || teste_nivel_0217());

  raise notice '--- 4. a Analista não muda o dial à mão; o Sócio muda ---';
  perform teste_cenario_0217(v_a, 5, 5, v_b, v_nmin * 4, v_nmin * 4);
  -- cenário com a global suficiente: se o manual passasse, o veredito autorizaria a subida — a recusa é só da guarda de Sócio.
  update estagio_autonomia set auto_promocao = false where estagio = v_est;
  perform teste_como_0217(u_ana);
  v_t := teste_tenta_0217($q$select fn_mudar_dial('classificacao_doc_checklist', 'N2', 'ana@0217', 'por veredito', null, null, null, true)$q$);
  perform teste_super_0217(u_socio);
  perform teste_assert_0217(v_t = '42501' and teste_nivel_0217() = 'N1', 'a Analista NÃO sobe o dial por fn_mudar_dial, nem pela porta do veredito (42501)', v_t || ' / ' || teste_nivel_0217());
  perform teste_como_0217(u_ana);
  v_t := teste_tenta_0217($q$select fn_mudar_dial('classificacao_doc_checklist', 'N0', 'ana@0217', 'baixando')$q$);
  perform teste_super_0217(u_socio);
  perform teste_assert_0217(v_t = '42501' and teste_nivel_0217() = 'N1', 'a Analista NÃO desce o dial por fn_mudar_dial (42501)', v_t || ' / ' || teste_nivel_0217());
  perform teste_como_0217(u_ana);
  v_t := teste_tenta_0217($q$update estagio_autonomia set nivel_atual = 'N2' where estagio = 'classificacao_doc_checklist'$q$);
  perform teste_super_0217(u_socio);
  perform teste_assert_0217(v_t = '42501' and teste_nivel_0217() = 'N1', 'a Analista NÃO muda o dial por UPDATE direto (42501)', v_t || ' / ' || teste_nivel_0217());
  -- A MARCA DA PROMOÇÃO NÃO É CHAVE: posta por quem roda como authenticated, a guarda continua recusando (current_user).
  perform teste_como_0217(u_ana);
  perform set_config('tdf.promocao_automatica', 'sim', true);
  v_t := teste_tenta_0217($q$select fn_mudar_dial('classificacao_doc_checklist', 'N2', 'sistema:auto_dial', 'forjado', null, null, null, true)$q$);
  perform set_config('tdf.promocao_automatica', '', true);
  perform teste_super_0217(u_socio);
  perform teste_assert_0217(v_t = '42501' and teste_nivel_0217() = 'N1', 'com a marca da promoção posta por ela e o autor forjado, ainda 42501: a marca sozinha não abre o dial', v_t || ' / ' || teste_nivel_0217());
  perform teste_como_0217(u_ana);
  v_t := teste_tenta_0217($q$select fn_dial_auto_promover()$q$);
  perform teste_super_0217(u_socio);
  perform teste_assert_0217(v_t = '42501', 'a Analista não chama fn_dial_auto_promover direto (fechada ao authenticated)', v_t);
  perform teste_como_0217(u_socio);
  v_t := teste_tenta_0217($q$select fn_mudar_dial('classificacao_doc_checklist', 'N0', 'socio@0217', 'freio de mão')$q$);
  perform teste_super_0217(u_socio);
  perform teste_assert_0217(v_t = 'ok:1' and teste_nivel_0217() = 'N0', 'controle: o Sócio muda o dial por fn_mudar_dial', v_t || ' / ' || teste_nivel_0217());

  raise notice '--- 5. as métricas da tela /autonomia: o MESMO número para Sócio e Analista ---';
  -- classe contábil: A tem 2 linhas com os dois lados (1 concorda), B tem 3 (nenhuma concorda). Global: 5 e 0,2. Recorte de A: 2 e 0,5.
  v_r := fn_registrar_documento(v_a, 'ALFA SA', 'anual', '2025', 'DRE', 0.9, 'nome_arquivo', 'supabase_storage', v_a || '/hash-a-0217.pdf', 'DRE Alfa.pdf', true, 'HASH-A-0217', 'ok');
  v_ver_a := (v_r->>'documento_versao_id')::uuid; v_doc_a := (v_r->>'documento_id')::uuid;
  v_r := fn_registrar_documento(v_b, 'BETA SA', 'anual', '2025', 'DRE', 0.9, 'nome_arquivo', 'supabase_storage', v_b || '/hash-b-0217.pdf', 'DRE Beta.pdf', true, 'HASH-B-0217', 'ok');
  v_ver_b := (v_r->>'documento_versao_id')::uuid; v_doc_b := (v_r->>'documento_id')::uuid;
  for v_i in 1..5 loop
    insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca, secao_canonica, periodo_coluna)
      values (case when v_i <= 2 then v_ver_a else v_ver_b end, 'Rubrica ' || v_i || ' 0217', -100 * v_i, 'milhar', 0.97, 'despesas_operacionais', '2025')
      returning id into v_campo;
    insert into campo_classe_sugerida (campo_extraido_id, classe_codigo, justificativa, versao_taxonomia, nivel_autonomia)
      values (v_campo, 'recorrente', 'teste 0217', 1, 'N0');
    insert into campo_classe_override (campo_extraido_id, classe_final, autor)
      values (v_campo, case when v_i = 1 then 'recorrente' else 'nao_recorrente' end, 'analista:0217');
  end loop;
  -- classe A (golden): A tem 1 rejeitada (falso positivo); B tem 2 resolvidas por humano. Global: 3 vereditos. Recorte de A: 1.
  insert into reconciliacao (caso_id, tipo, classe, precondicoes_ok, resultado) values (v_a, 'tipo_0217_a', 'A', true, 'diverge'), (v_b, 'tipo_0217_b', 'A', true, 'diverge');
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, estado, motivo, resolvida_por)
    values (v_a, 'reconciliacao', 'item_sem_conteudo', 'bloqueante', 'rejeitada', 'reconciliacao:tipo_0217_a', 'analista:0217'),
           (v_b, 'reconciliacao', 'item_sem_conteudo', 'bloqueante', 'resolvida', 'reconciliacao:tipo_0217_b', 'analista:0217'),
           (v_b, 'reconciliacao', 'item_sem_conteudo', 'bloqueante', 'resolvida', 'reconciliacao:tipo_0217_b', 'analista:0217');
  -- cobertura do golden: uma rodada com um BALANCO de A e um de B rotulados (as tabelas do golden são só do Sócio).
  insert into golden_rodada (nome, taxonomia_versao, criada_por) values ('0217-rodada', 1, 'teste:0217') returning id into v_rod;
  insert into golden_documento (rodada_id, documento_id, estrato, origem, incluido_por)
    values (v_rod, v_doc_a, 'pdf_nativo', 'real', 'teste:0217'), (v_rod, v_doc_b, 'pdf_nativo', 'real', 'teste:0217');
  insert into golden_rotulo (rodada_id, documento_id, rotulador, tipo_correto, entidade_correta, periodo_correto, legibilidade)
    values (v_rod, v_doc_a, 'rotulador:0217', 'BALANCO', 'ALFA SA', '2025', 'ok'), (v_rod, v_doc_b, 'rotulador:0217', 'BALANCO', 'BETA SA', '2025', 'ok');

  -- o que o Sócio vê (superusuário com o JWT do Sócio = o número do banco inteiro)
  v_r := fn_classe_contabil_concordancia(null);
  perform teste_assert_0217((v_r->>'com_veredito_humano')::int = 5 and (v_r->>'concordancia')::numeric = 0.2,
    'controle: a classe contábil do banco inteiro tem 5 vereditos a 0,2', v_r::text);
  v_cob_s := (select jsonb_agg(to_jsonb(c) order by c.tipo) from fn_golden_cobertura(v_rod) c);
  perform teste_assert_0217((select (x->>'n_documentos')::int from jsonb_array_elements(v_cob_s) x where x->>'tipo' = 'BALANCO') = 2,
    'controle: a cobertura do golden tem 2 BALANCOs rotulados (um de cada mandato)', v_cob_s::text);
  perform teste_assert_0217((fn_golden_classe_a(null)->>'com_veredito_humano')::int = 3,
    'controle: a classe A do banco inteiro tem 3 vereditos humanos');

  perform teste_como_0217(u_ana);
  perform teste_assert_0217(fn_classe_contabil_concordancia(null) = v_r, 'a Analista recebe a MESMA concordância de classe contábil que o Sócio (5 vereditos, não os 2 do recorte dela)', fn_classe_contabil_concordancia(null)::text);
  perform teste_assert_0217((fn_classe_contabil_concordancia(v_a)->>'com_veredito_humano')::int = 2,
    'e pedindo o mandato A, que ela lê, recebe só os 2 de A');
  perform teste_assert_0217((fn_golden_classe_a(null)->>'com_veredito_humano')::int = 3, 'a Analista recebe os 3 vereditos de classe A do banco inteiro');
  perform teste_assert_0217((fn_golden_classe_a(v_a)->>'com_veredito_humano')::int = 1, 'e pedindo o mandato A recebe só o 1 de A');
  v_cob_a := (select jsonb_agg(to_jsonb(c) order by c.tipo) from fn_golden_cobertura(v_rod) c);
  perform teste_assert_0217(v_cob_a = v_cob_s, 'a Analista recebe a MESMA cobertura do golden que o Sócio (2 BALANCOs, não zero)', v_cob_a::text);
  select count(*) into v_n from golden_rotulo;
  perform teste_assert_0217(v_n = 0, 'controle: ela NÃO lê golden_rotulo (os rótulos citam documentos de qualquer mandato) — o que a função entrega é só a contagem');
  perform teste_assert_0217(fn_veredito_producao('reconciliacao_classe_a') ->> 'n' = '3',
    'o veredito do estágio reconciliacao_classe_a, para ela, conta os 3 do banco inteiro');

  raise notice '--- 6. um mandato só se pergunta se o chamador o lê; sem papel, nada ---';
  perform teste_assert_0217(teste_tenta_0217(format($q$select fn_veredito_producao(%L, %L)$q$, v_est, v_b)) = '42501', 'Analista de A não pergunta o veredito do mandato B (42501)');
  perform teste_assert_0217(teste_tenta_0217(format($q$select fn_classe_contabil_concordancia(%L)$q$, v_b)) = '42501', 'nem a classe contábil de B');
  perform teste_assert_0217(teste_tenta_0217(format($q$select fn_golden_classe_a(%L)$q$, v_b)) = '42501', 'nem a classe A de B');
  perform teste_assert_0217(teste_tenta_0217(format($q$select fn_veredito_producao(%L, %L)$q$, v_est, v_a)) = 'ok:1', 'controle: o veredito do mandato A, que ela lê, responde');
  perform teste_como_0217(u_nil);
  perform teste_assert_0217(teste_tenta_0217(format($q$select fn_veredito_producao(%L)$q$, v_est)) = '42501', 'usuário SEM papel não lê o veredito global (42501)');
  perform teste_assert_0217(teste_tenta_0217($q$select fn_classe_contabil_concordancia(null)$q$) = '42501', 'nem a classe contábil');
  perform teste_assert_0217(teste_tenta_0217($q$select fn_golden_classe_a(null)$q$) = '42501', 'nem a classe A');
  perform teste_assert_0217(teste_tenta_0217(format($q$select * from fn_golden_cobertura(%L)$q$, v_rod)) = '42501', 'nem a cobertura do golden');
  perform teste_super_0217(u_socio);
  perform teste_assert_0217(teste_tenta_0217(format($q$select fn_veredito_producao(%L)$q$, v_est)) = 'ok:1', 'controle: a conexão de serviço/superusuário com JWT de Sócio continua perguntando');
end $$;

-- =============================================================================
-- PARTE 2 — O ANON: o que produção tinha ANTES, a migration reaplicada, e o que sobra
-- =============================================================================
-- O que authenticated e service_role podem EXECUTAR e LER agora (antes de qualquer simulação): a migration não pode mexer nisto.
create temp table snap_0217 as
  select p.oid as fn, has_function_privilege('authenticated', p.oid, 'execute') as auth, has_function_privilege('service_role', p.oid, 'execute') as srv
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname not like 'teste\_%'
     and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e');
create temp table snap_tab_0217 as
  select c.oid as rel, has_table_privilege('authenticated', c.oid, 'select') as a_sel, has_table_privilege('authenticated', c.oid, 'delete') as a_del,
         has_table_privilege('service_role', c.oid, 'select') as s_sel, has_table_privilege('service_role', c.oid, 'delete') as s_del
    from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm');

-- O BANCO DE PRODUÇÃO ANTES DA 0217: anon com tudo (default privilege antigo do Supabase + EXECUTE herdado de PUBLIC).
grant all on all tables in schema public to anon;
grant all on all sequences in schema public to anon;
grant execute on all functions in schema public to anon;
revoke all on caso from anon;
grant select (id) on caso to anon;                       -- só de COLUNA: has_table_privilege não vê
alter default privileges in schema public grant all on tables to anon;
alter default privileges in schema public grant all on sequences to anon;
alter default privileges in schema public grant execute on functions to anon;
create function fn_0217_publica() returns int language sql as 'select 1';
-- E o EXECUTE de authenticated/service_role chegava por PUBLIC, não por grant direto (função nova do Postgres): a simulação devolve as
-- funções a esse estado. Sem isto o retrato de "como estavam" passaria mesmo que a migration esquecesse de repor o grant depois de
-- tirar PUBLIC (medido: a variante sem reposição reprovava 0 asserts com os grants diretos que a primeira aplicação já tinha deixado).
do $$
declare f record;
begin
  for f in select fn from snap_0217 where auth and srv loop
    execute format('revoke all on function %s from authenticated, service_role', f.fn::regprocedure);
    execute format('grant execute on function %s to public', f.fn::regprocedure);
  end loop;
end $$;
   -- nasce com EXECUTE para PUBLIC, como toda função nova

do $$
begin
  perform teste_assert_0217(has_table_privilege('anon', 'membro', 'insert') and has_table_privilege('anon', 'alocacao', 'delete'),
    'controle: ANTES, anon escreve em membro e alocacao (a simulação do banco de produção armou o defeito)');
  perform teste_assert_0217(has_column_privilege('anon', 'caso', 'id', 'select') and not has_table_privilege('anon', 'caso', 'select'),
    'controle: ANTES, anon tem SELECT só de coluna em caso (o privilégio que has_table_privilege não enxerga)');
  perform teste_assert_0217(has_function_privilege('anon', 'fn_definir_papel(uuid,text,text)', 'execute') and has_function_privilege('anon', 'fn_acesso_bootstrap()', 'execute')
                            and has_function_privilege('anon', 'fn_0217_publica()', 'execute'),
    'controle: ANTES, anon executa fn_definir_papel, fn_acesso_bootstrap e a função recém-criada (PUBLIC)');
  perform teste_assert_0217(has_sequence_privilege('anon', 'arquivo_oficial_seq_seq', 'usage'), 'controle: ANTES, anon usa a sequence arquivo_oficial_seq_seq');
  perform teste_assert_0217((select count(distinct d.oid) from pg_default_acl d, aclexplode(d.defaclacl) a
                              where d.defaclnamespace = 'public'::regnamespace and a.grantee = (select oid from pg_roles where rolname = 'anon')) = 3,
    'controle: ANTES, o default privilege de anon existe para tabela, sequence e função (3 entradas)');
  perform teste_assert_0217((select count(*) from fn_instalacao_conferir() where chave like 'anon_sem_%' and not presente) = 4,
    'a sonda ACUSA os 4 requisitos de anon no banco de antes (tabelas, views, sequences, funções)');
end $$;

-- A MIGRATION, reaplicada por cima do que produção tinha antes.
\i :arq0217

do $$
declare
  v_n int; v_msgs text[] := '{}'; v_sqls text[]; v_i int; v_m text; v_ok boolean;
  u_socio uuid := '00000000-0000-0000-0000-00000000c101';
begin
  raise notice '--- 7. depois da migration: anon sem nenhum privilégio em public ---';
  perform teste_assert_0217((select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
                              where n.nspname = 'public' and c.relkind in ('r', 'p')
                                and (has_any_column_privilege('anon', c.oid, 'select') or has_any_column_privilege('anon', c.oid, 'insert')
                                  or has_any_column_privilege('anon', c.oid, 'update') or has_any_column_privilege('anon', c.oid, 'references')
                                  or has_table_privilege('anon', c.oid, 'delete') or has_table_privilege('anon', c.oid, 'truncate')
                                  or has_table_privilege('anon', c.oid, 'trigger'))) = 0,
    'nenhuma TABELA de public com privilégio para anon (select, insert, update, delete, truncate, references, trigger)');
  perform teste_assert_0217(not has_column_privilege('anon', 'caso', 'id', 'select'), 'e o privilégio só de COLUNA (caso.id) também foi removido');
  perform teste_assert_0217((select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
                              where n.nspname = 'public' and c.relkind in ('v', 'm') and has_any_column_privilege('anon', c.oid, 'select')) = 0,
    'nenhuma VIEW de public com SELECT para anon');
  perform teste_assert_0217((select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
                              where n.nspname = 'public' and c.relkind = 'S'
                                and (has_sequence_privilege('anon', c.oid, 'usage') or has_sequence_privilege('anon', c.oid, 'select') or has_sequence_privilege('anon', c.oid, 'update'))) = 0,
    'nenhuma SEQUENCE de public com privilégio para anon');
  perform teste_assert_0217((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                              where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')
                                and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')) = 0,
    'nenhuma FUNÇÃO de public (fora extensão) executável por anon — nem a herdada de PUBLIC, nem as teste_*');
  perform teste_assert_0217(not has_function_privilege('anon', 'fn_0217_publica()', 'execute'), 'a função que nasceu com EXECUTE de PUBLIC também perdeu o de anon');
  perform teste_assert_0217((select count(*) from pg_default_acl d, aclexplode(d.defaclacl) a
                              where d.defaclnamespace = 'public'::regnamespace and a.grantee = (select oid from pg_roles where rolname = 'anon')) = 0,
    'o default privilege de anon em public sumiu (tabela, sequence e função)');

  raise notice '--- 8. authenticated e service_role ficam EXATAMENTE como estavam ---';
  perform teste_assert_0217((select count(*) from snap_0217) > 250 and (select count(*) from snap_0217 where auth) > 200,
    'controle: o retrato de antes não é vazio (mais de 250 funções, mais de 200 executáveis por authenticated)');
  perform teste_assert_0217((select count(*) from snap_0217 s where has_function_privilege('authenticated', s.fn, 'execute') is distinct from s.auth) = 0,
    'o EXECUTE de authenticated em cada função de public é o mesmo de antes');
  perform teste_assert_0217((select count(*) from snap_0217 s where has_function_privilege('service_role', s.fn, 'execute') is distinct from s.srv) = 0,
    'o EXECUTE de service_role em cada função de public é o mesmo de antes');
  perform teste_assert_0217(not has_function_privilege('authenticated', 'fn_acesso_bootstrap()', 'execute') and has_function_privilege('service_role', 'fn_acesso_bootstrap()', 'execute'),
    'o EXECUTE retirado de propósito (fn_acesso_bootstrap só para service_role) continua retirado');
  perform teste_assert_0217((select count(*) from snap_tab_0217 s where has_table_privilege('authenticated', s.rel, 'select') is distinct from s.a_sel
                               or has_table_privilege('authenticated', s.rel, 'delete') is distinct from s.a_del
                               or has_table_privilege('service_role', s.rel, 'select') is distinct from s.s_sel
                               or has_table_privilege('service_role', s.rel, 'delete') is distinct from s.s_del) = 0
                            and (select count(*) from snap_tab_0217 where a_sel) > 40,
    'os privilégios de authenticated e service_role em tabela e view são os mesmos de antes (e o retrato tem mais de 40 relações)');
  perform teste_assert_0217((select count(*) from fn_instalacao_conferir() where tipo = 'privilegio' and not presente) = 0,
    'os 6 requisitos de privilégio mínimo da 0214 (authenticated e service_role) seguem presentes');

  raise notice '--- 9. o que anon tentava ---';
  -- Cada comando roda COMO anon, com o JWT LIMPO (o banco de teste guarda o de um Sócio em pg_db_role_setting).
  v_sqls := array[
    'select count(*) from membro',
    'insert into membro (usuario_id, papel) values (gen_random_uuid(), ''socio'')',
    'update membro set papel = ''socio''',
    'delete from alocacao',
    'insert into alocacao (caso_id, usuario_id) values (gen_random_uuid(), gen_random_uuid())',
    'select count(*) from caso',
    'select fn_definir_papel(gen_random_uuid(), ''socio'')',
    'select fn_alocar(gen_random_uuid(), gen_random_uuid())',
    'select fn_desalocar(gen_random_uuid(), gen_random_uuid())',
    'select fn_acesso_bootstrap()',
    'select fn_eh_socio()',
    'select * from fn_membros_da_equipe()',
    'select fn_pode_ler_caso(gen_random_uuid())',
    'select fn_veredito_producao(''classificacao_doc_checklist'')'];
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  for v_i in 1..array_length(v_sqls, 1) loop
    begin
      execute v_sqls[v_i];
      v_msgs := v_msgs || 'ok'::text;
    exception when others then
      v_msgs := v_msgs || (sqlstate || '|' || sqlerrm);
    end;
  end loop;
  execute 'reset role';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', u_socio, 'role', 'authenticated')::text, true);
  for v_i in 1..array_length(v_sqls, 1) loop
    perform teste_assert_0217(v_msgs[v_i] ~ '^42501\|.*(permission denied|permissão negada)',
      format('anon NÃO executa: %s', v_sqls[v_i]), v_msgs[v_i]);
  end loop;

  raise notice '--- 10. a sonda acusa o privilégio que se conceder a anon depois ---';
  perform teste_assert_0217((select count(*) from fn_instalacao_conferir() where chave like 'anon_sem_%' and presente) = 4
                            and (select count(*) from fn_instalacao_conferir() where chave like 'anon_sem_%' and severidade = 'bloqueante') = 4,
    'depois da migration os 4 requisitos de anon estão presentes, e todos são BLOQUEANTES');

  grant select on membro to anon;
  perform teste_assert_0217((select not presente and detalhe like '%membro%' from fn_instalacao_conferir() where chave = 'anon_sem_tabelas'),
    'SELECT concedido a anon em membro: a sonda acusa a tabela pelo nome', (select detalhe from fn_instalacao_conferir() where chave = 'anon_sem_tabelas'));
  revoke all on membro from anon;
  grant select (usuario_id) on membro to anon;
  perform teste_assert_0217((select not presente from fn_instalacao_conferir() where chave = 'anon_sem_tabelas'), 'privilégio só de COLUNA concedido a anon: a sonda acusa');
  revoke all on membro from anon;
  grant select on instalacao_sonda_modelagem_pronta to anon;
  perform teste_assert_0217((select not presente from fn_instalacao_conferir() where chave = 'anon_sem_views'), 'SELECT concedido a anon numa view: a sonda acusa');
  revoke all on instalacao_sonda_modelagem_pronta from anon;
  grant usage on sequence arquivo_oficial_seq_seq to anon;
  perform teste_assert_0217((select not presente from fn_instalacao_conferir() where chave = 'anon_sem_sequences'), 'USAGE concedido a anon numa sequence: a sonda acusa');
  revoke all on sequence arquivo_oficial_seq_seq from anon;
  grant execute on function fn_eh_socio() to anon;
  perform teste_assert_0217((select not presente and detalhe like '%fn_eh_socio%' from fn_instalacao_conferir() where chave = 'anon_sem_funcoes'),
    'EXECUTE concedido a anon numa função: a sonda acusa pelo nome', (select detalhe from fn_instalacao_conferir() where chave = 'anon_sem_funcoes'));
  revoke all on function fn_eh_socio() from public, anon;
  grant execute on function fn_eh_socio() to authenticated, service_role;
  create function fn_0217_esqueceu_o_revoke() returns int language sql as 'select 1';   -- a migration futura que esquece o `revoke ... from public`
  perform teste_assert_0217((select not presente and detalhe like '%fn_0217_esqueceu_o_revoke%' from fn_instalacao_conferir() where chave = 'anon_sem_funcoes'),
    'função NOVA sem o revoke de PUBLIC (anon a herda): a sonda a acusa — é o que o CI vê numa migration que esquece');
  revoke all on function fn_0217_esqueceu_o_revoke() from public;
  perform teste_assert_0217((select presente from fn_instalacao_conferir() where chave = 'anon_sem_funcoes'), 'com o revoke feito, a sonda volta a verde');
  create function teste_0217_auxiliar() returns int language sql as 'select 1';        -- harness: tem EXECUTE de PUBLIC e a sonda o ignora
  perform teste_assert_0217((select presente from fn_instalacao_conferir() where chave = 'anon_sem_funcoes') and has_function_privilege('anon', 'teste_0217_auxiliar()', 'execute'),
    'função teste_* (só existe no harness) não conta, ainda que anon a execute');

  raise notice '--- 11. objeto FUTURO nasce sem nada para anon ---';
  create table t_0217_novo (id serial primary key, x text);
  perform teste_assert_0217(not has_any_column_privilege('anon', 't_0217_novo', 'select') and not has_table_privilege('anon', 't_0217_novo', 'delete')
                            and not has_sequence_privilege('anon', 't_0217_novo_id_seq', 'usage'),
    'tabela e sequence criadas DEPOIS da migration não dão nada a anon (o default privilege foi revogado)');
end $$;

select 'FIM 0217: ' || coalesce(current_setting('dial.execucoes', true), '0') || ' execuções, '
       || coalesce(nullif(current_setting('dial.falhas', true), ''), '0') || ' falhas' as medicao;

rollback;
