-- =============================================================================
-- 0219 — A GUARDA DO DIAL QUE CONFERIA O FORMATO DO UPDATE, e o `rls_auto_enable` que perdeu o PUBLIC
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md): 110 chamadas de assert, 110 execuções (cada chamada roda uma vez).
-- Controle intacto: 110 ok, 0 falhas.
-- O número por correção desligada está no cabeçalho de Supabase/migrations/0219_a_guarda_do_dial_que_conferia_o_formato_do_update.sql
-- ("MEDIÇÃO NÃO-VAZIA").
--
-- COMO RODA. Uma transação só (`begin` ... `rollback`). O teste REAPLICA o arquivo da migration (`\i`) logo no começo — com o arquivo real ele é um no-op
-- (a migration é idempotente) e é isso que prova a idempotência; com `-v arq0219=<arquivo>` ele aplica uma VARIANTE da migration, e é assim que se mede cada
-- correção desligada. Cada usuário é um JWT (`request.jwt.claims`) mais `set local role authenticated`, o que o PostgREST faz. O JWT é SEMPRE definido
-- (o banco de teste guarda o de um Sócio em pg_db_role_setting; num banco copiado ele pode estar vazio).
-- `dial.medindo = on` (PGOPTIONS='-c dial.medindo=on') vira `raise warning` e CONTA: é como se mede quantos asserts uma variante reprova sem parar no primeiro.
--
-- O QUE AFIRMA (comportamento, não mecanismo):
--   1. A promoção automática SOBE o dial quando o veredito GLOBAL basta, mesmo disparada por um Analista, e NÃO sobe quando não basta — e continua subindo se
--      o formato do UPDATE de fn_mudar_dial mudar (era o que a 0218 quebrava calado).
--   2. O Analista não muda o dial nem o catálogo de premissas à mão (fn_mudar_dial, UPDATE direto, INSERT e DELETE: 42501), com a camada do gatilho ISOLADA
--      (policies abertas dentro da transação); o Sócio muda; o dono (SQL Editor, migration) escreve.
--   3. O risco que a regra simples abre existe (uma definer executável por authenticated burla a guarda) e a SONDA o acusa: escreve direto, chama fn_mudar_dial,
--      função de gatilho; e NÃO acusa a que não é perigosa (fechada ao authenticated, invoker, só leitura).
--   3b. OS PONTOS CEGOS DO PORTÃO, reproduzidos um a um (PARTE 2b; revisão independente de 03/11/2026): a definer que chama helper INVOKER que escreve (uma e duas chamadas de
--      distância), que escreve numa tabela cujo gatilho INVOKER escreve no dial, em `begin atomic` (prosrc vazio), a função de event trigger, e a cascata de FK (a ação referencial
--      roda como dono: ON DELETE SET NULL, ON UPDATE CASCADE, SET DEFAULT, e o filho com gatilho BEFORE que escreve no dial). Cada arranjo primeiro prova que o Analista BURLA a guarda
--      e depois exige que a sonda ACUSE; e os que não são perigosos (helper só de leitura, a PORTA fn_dial_auto_promover, FK restrict/no action, o pai da cascata) ficam verdes.
--   4. Função que retorna event_trigger não é chamável; a sonda do anon a ignora e continua acusando a função comum; a migration devolve o PUBLIC ao
--      `rls_auto_enable` (e só a ele, e só se retornar event_trigger).
--   5. A reemissão de fn_instalacao_conferir não perdeu os ramos da 0217 (segredo) e da 0218 (sem_privilegio).
-- =============================================================================

\set ON_ERROR_STOP on
\if :{?arq0219}
\else
  \set arq0219 'Supabase/migrations/0219_a_guarda_do_dial_que_conferia_o_formato_do_update.sql'
\endif

begin;

create or replace function teste_assert_0219(p_cond boolean, p_nome text, p_detalhe text default null)
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
create or replace function teste_tenta_0219(p_sql text) returns text
language plpgsql as $$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return 'ok:' || n;
exception when others then
  return sqlstate;
end $$;

create or replace function teste_como_0219(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create or replace function teste_super_0219(p_socio uuid) returns void
language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_socio, 'role', 'authenticated')::text, true);
end $$;

create or replace function teste_semear_0219(p_caso uuid, p_n int, p_acertos int) returns void
language plpgsql as $$
declare i int;
begin
  for i in 1..p_n loop
    insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (p_caso, (case when i <= p_acertos then 'aprovacao' else 'correcao_classificacao' end)::decisao_tipo,
            'analista:0219', 'veredito de teste',
            jsonb_build_object('documento_id', gen_random_uuid(), 'tipo_de', 'balanco_patrimonial',
                               'tipo_para', case when i <= p_acertos then 'balanco_patrimonial' else 'balancete' end));
  end loop;
end $$;

-- Estágio em N1 com a promoção DESLIGADA, vereditos semeados (o gatilho roda a cada linha), e SÓ ENTÃO a promoção ligada: o que se mede é a decisão que o
-- Analista toma depois, não a semeadura.
create or replace function teste_cenario_0219(p_a uuid, p_a_n int, p_a_ac int, p_b uuid, p_b_n int, p_b_ac int) returns void
language plpgsql as $$
begin
  update estagio_autonomia
     set nivel_atual = 'N1', base_do_nivel = 'nao_se_aplica', auto_promocao = false, medicao_em = null, medicao_resumo = null, atualizado_por = 'teste:0219'
   where estagio = 'classificacao_doc_checklist';
  delete from decisao where autor = 'analista:0219';
  perform teste_semear_0219(p_a, p_a_n, p_a_ac);
  perform teste_semear_0219(p_b, p_b_n, p_b_ac);
  update estagio_autonomia set auto_promocao = true where estagio = 'classificacao_doc_checklist';
end $$;

create or replace function teste_nivel_0219() returns text
language sql as $$ select nivel_atual::text from estagio_autonomia where estagio = 'classificacao_doc_checklist' $$;

-- A migration sob teste: o arquivo real (no-op) ou a variante.
\i :arq0219

delete from decisao;   -- os vereditos de OUTRAS suítes não entram no denominador (a transação volta)

-- =============================================================================
-- PARTE 1 — A GUARDA E A PROMOÇÃO
-- =============================================================================
do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000000d901';   -- Sócio
  u_ana   uuid := '00000000-0000-0000-0000-00000000d902';   -- Analista, alocada em A
  v_a uuid; v_b uuid; v_t text; v_nmin int; v_est constant text := 'classificacao_doc_checklist';
  v_p1 uuid; v_p2 uuid; v_p3 uuid; v_ev0 int; v_ev1 int; v_n int;
begin
  insert into auth.users (id, email) values (u_socio, 'socio@0219.local'), (u_ana, 'ana@0219.local');
  perform fn_definir_papel(u_socio, 'socio', 'teste 0219');
  perform fn_definir_papel(u_ana, 'analista');
  v_a := fn_upsert_caso('0219 — mandato A');
  v_b := fn_upsert_caso('0219 — mandato B');
  perform fn_alocar(v_a, u_ana);
  perform teste_super_0219(u_socio);
  select n_minimo_veredito into v_nmin from golden_criterio where estagio = v_est;
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao) values (v_a, 'completude', 'item_sem_conteudo', 'bloqueante', true, 'p1 de A') returning id into v_p1;
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao) values (v_a, 'completude', 'item_sem_conteudo', 'bloqueante', true, 'p2 de A') returning id into v_p2;
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao) values (v_a, 'completude', 'item_sem_conteudo', 'bloqueante', true, 'p3 de A') returning id into v_p3;

  raise notice '--- 1. a promoção automática disparada por um Analista: sobe quando o veredito global basta, NÃO sobe quando não basta ---';
  -- A global SUFICIENTE (todos confirmam, 4 x o mínimo): a decisão da Analista promove. O dial é UMA linha para todos.
  perform teste_cenario_0219(v_a, 5, 5, v_b, v_nmin * 4, v_nmin * 4);
  perform teste_assert_0219((fn_veredito_producao(v_est)->>'suficiente')::boolean, 'controle: o veredito global é suficiente', fn_veredito_producao(v_est)::text);
  perform teste_assert_0219(teste_nivel_0219() = 'N1', 'controle: o estágio parte de N1 com a promoção ligada');
  select count(*) into v_ev0 from evento_auditoria where acao = 'mudanca_dial' and ator = 'sistema:auto_dial' and entidade_ref = 'estagio:' || v_est;
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219(format($q$select fn_decidir_pendencia(%L, 'ana@0219', 'prosseguir', 'decidida pela Analista')$q$, v_p1));
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = 'ok:1', 'a decisão da Analista é gravada', v_t);
  perform teste_assert_0219(teste_nivel_0219() = 'N2', 'o dial SOBE para N2, disparado pela Analista, quando a global basta', teste_nivel_0219());
  perform teste_assert_0219((select base_do_nivel from estagio_autonomia where estagio = v_est) = 'medida_por_veredito', 'e a base declara o piso enviesado (medida_por_veredito)');
  select count(*) into v_ev1 from evento_auditoria where acao = 'mudanca_dial' and ator = 'sistema:auto_dial' and entidade_ref = 'estagio:' || v_est;
  perform teste_assert_0219(v_ev1 - v_ev0 = 1, 'a trilha guarda UMA promoção, com o ator sistema:auto_dial', (v_ev1 - v_ev0)::text);

  -- A global INSUFICIENTE (50%), e o recorte da Analista (mandato A) passaria: a decisão dela NÃO promove.
  perform teste_cenario_0219(v_a, v_nmin, v_nmin, v_b, v_nmin * 3, v_nmin);
  perform teste_assert_0219(not (fn_veredito_producao(v_est)->>'suficiente')::boolean, 'controle: o veredito global é INSUFICIENTE (4 x mínimo vereditos a 50%)');
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219(format($q$select fn_decidir_pendencia(%L, 'ana@0219', 'prosseguir', 'decidida pela Analista')$q$, v_p2));
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = 'ok:1' and teste_nivel_0219() = 'N1', 'o dial NÃO sobe quando a global não basta (e a decisão da Analista é gravada)', v_t || ' / ' || teste_nivel_0219());

  -- O FORMATO DO UPDATE NÃO IMPORTA. A 0218 só deixava passar o UPDATE a N2 + medida_por_veredito + autor sistema:auto_dial: quem mudasse fn_mudar_dial quebrava a promoção
  -- e o gatilho da 0137 engolia o 42501. Aqui um gatilho BEFORE (que dispara antes da guarda: nome em ordem alfabética) muda o autor gravado, como mudaria uma fn_mudar_dial nova.
  perform teste_cenario_0219(v_a, 5, 5, v_b, v_nmin * 4, v_nmin * 4);
  create function teste_0219_muda_formato() returns trigger language plpgsql as $f$ begin new.atualizado_por := 'teste:outro_formato'; return new; end $f$;
  create trigger a_teste_0219_formato before update on estagio_autonomia for each row execute function teste_0219_muda_formato();
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219(format($q$select fn_decidir_pendencia(%L, 'ana@0219', 'prosseguir', 'decidida pela Analista')$q$, v_p3));
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = 'ok:1' and teste_nivel_0219() = 'N2' and (select atualizado_por from estagio_autonomia where estagio = v_est) = 'teste:outro_formato',
    'a promoção sobe mesmo com o UPDATE em OUTRO formato (autor diferente): a guarda não confere o formato', v_t || ' / ' || teste_nivel_0219());
  drop trigger a_teste_0219_formato on estagio_autonomia;
  drop function teste_0219_muda_formato();

  raise notice '--- 2. o Analista não muda o dial nem o catálogo à mão; o Sócio muda; o dono escreve ---';
  perform teste_cenario_0219(v_a, 5, 5, v_b, v_nmin * 4, v_nmin * 4);
  update estagio_autonomia set auto_promocao = false where estagio = v_est;   -- a global basta: só a guarda de Sócio recusa
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$select fn_mudar_dial('classificacao_doc_checklist', 'N2', 'ana@0219', 'por veredito', null, null, null, true)$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = '42501' and teste_nivel_0219() = 'N1', 'a Analista NÃO sobe o dial por fn_mudar_dial (42501)', v_t || ' / ' || teste_nivel_0219());
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$select fn_mudar_dial('classificacao_doc_checklist', 'N0', 'ana@0219', 'baixando')$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = '42501' and teste_nivel_0219() = 'N1', 'a Analista NÃO desce o dial por fn_mudar_dial (42501)', v_t || ' / ' || teste_nivel_0219());
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$update estagio_autonomia set nivel_atual = 'N2' where estagio = 'classificacao_doc_checklist'$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = '42501' and teste_nivel_0219() = 'N1', 'a Analista NÃO muda o dial por UPDATE direto (42501)', v_t || ' / ' || teste_nivel_0219());
  -- DELETE: a policy de DELETE deixa QUALQUER papel achar a linha (o gatilho é quem recusa), então estes dois asserts já isolam o gatilho.
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$delete from estagio_autonomia where estagio = 'classificacao_doc_checklist'$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = '42501' and teste_nivel_0219() = 'N1', 'a Analista NÃO apaga estágio do dial (42501; a policy deixa achar a linha, o gatilho recusa)', v_t);
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$delete from premissa_catalogo where codigo = 'IPCA'$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = '42501' and exists (select 1 from premissa_catalogo where codigo = 'IPCA'), 'a Analista NÃO apaga premissa do catálogo (42501; só o gatilho a barra)', v_t);
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$update premissa_catalogo set ativo = ativo where codigo = 'IPCA'$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = '42501', 'a Analista NÃO altera o catálogo de premissas por UPDATE (42501)', v_t);
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$insert into premissa_catalogo (codigo, nome, natureza, formula) select 'X0219', 'x', natureza, formula from premissa_catalogo limit 1$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = '42501' and not exists (select 1 from premissa_catalogo where codigo = 'X0219'), 'a Analista NÃO insere no catálogo de premissas (42501)', v_t);

  -- O Sócio muda.
  perform teste_como_0219(u_socio);
  v_t := teste_tenta_0219($q$select fn_mudar_dial('classificacao_doc_checklist', 'N0', 'socio@0219', 'freio de mão')$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = 'ok:1' and teste_nivel_0219() = 'N0', 'controle: o Sócio muda o dial por fn_mudar_dial', v_t || ' / ' || teste_nivel_0219());
  perform teste_como_0219(u_socio);
  v_t := teste_tenta_0219($q$update premissa_catalogo set ativo = ativo where codigo = 'IPCA'$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = 'ok:1', 'controle: o Sócio altera o catálogo de premissas', v_t);

  -- O DONO: conexão de serviço (SQL Editor, migration, n8n) — sem JWT nenhum — e o código que roda como dono.
  perform set_config('request.jwt.claims', '', true);
  v_t := teste_tenta_0219($q$update premissa_catalogo set ativo = ativo where codigo = 'IPCA'$q$);
  perform teste_assert_0219(v_t = 'ok:1', 'o UPDATE do catálogo de premissas por migration/SQL Editor (sem JWT, como dono) continua passando', v_t);
  v_t := teste_tenta_0219($q$update estagio_autonomia set atualizado_por = atualizado_por where estagio = 'classificacao_doc_checklist'$q$);
  perform teste_assert_0219(v_t = 'ok:1', 'e o UPDATE do dial por migration/SQL Editor também', v_t);
  -- Decisão do dono (03/11/2026): a guarda confia no PAPEL DE BANCO, não no JWT. Como dono com o JWT de uma Analista (não existe no SQL Editor; é o que se afirma da regra), passa.
  perform teste_como_0219(u_ana);
  execute 'reset role';
  v_t := teste_tenta_0219($q$update estagio_autonomia set atualizado_por = atualizado_por where estagio = 'classificacao_doc_checklist'$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = 'ok:1', 'quem roda como dono escreve ainda que o JWT na sessão seja o de uma Analista: a regra é "código de dono é confiável"', v_t);

  raise notice '--- 3. a ÚLTIMA camada, isolada: com as policies abertas, só o gatilho separa o Analista do dial e do catálogo ---';
  -- A guarda de Sócio tem camadas (o gatilho, o WITH CHECK da policy de UPDATE/INSERT e a policy de INSERT em evento_auditoria para `estagio:`). Os asserts acima passam
  -- mesmo que SÓ O GATILHO caia. Aqui as policies são abertas (dentro da transação, que volta): o que resta entre o Analista e a tabela é o gatilho.
  perform teste_cenario_0219(v_a, 5, 5, v_b, v_nmin * 4, v_nmin * 4);
  update estagio_autonomia set auto_promocao = false where estagio = v_est;
  drop policy estagio_autonomia_update on estagio_autonomia;
  create policy estagio_autonomia_update on estagio_autonomia for update to authenticated using (true) with check (true);
  drop policy estagio_autonomia_insert on estagio_autonomia;
  create policy estagio_autonomia_insert on estagio_autonomia for insert to authenticated with check (true);
  drop policy premissa_catalogo_update on premissa_catalogo;
  create policy premissa_catalogo_update on premissa_catalogo for update to authenticated using (true) with check (true);
  drop policy premissa_catalogo_insert on premissa_catalogo;
  create policy premissa_catalogo_insert on premissa_catalogo for insert to authenticated with check (true);
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$update estagio_autonomia set nivel_atual = 'N2' where estagio = 'classificacao_doc_checklist'$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = '42501' and teste_nivel_0219() = 'N1', 'com a policy de UPDATE do dial aberta, quem roda como authenticated ainda leva 42501 (só o gatilho resta)', v_t || ' / ' || teste_nivel_0219());
  -- A MARCA da 0218 (a GUC tdf.promocao_automatica) e o formato exato da promoção NÃO abrem nada: a regra é o papel de banco.
  perform teste_como_0219(u_ana);
  perform set_config('tdf.promocao_automatica', 'sim', true);
  v_t := teste_tenta_0219($q$update estagio_autonomia set nivel_atual = 'N2', base_do_nivel = 'medida_por_veredito', atualizado_por = 'sistema:auto_dial' where estagio = 'classificacao_doc_checklist'$q$);
  perform set_config('tdf.promocao_automatica', '', true);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = '42501' and teste_nivel_0219() = 'N1', 'a marca da 0218 posta pela Analista e o formato exato da promoção: ainda 42501', v_t || ' / ' || teste_nivel_0219());
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$insert into estagio_autonomia (estagio, natureza, nivel_atual, teto) select 'estagio_0219', natureza, nivel_atual, teto from estagio_autonomia limit 1$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = '42501' and not exists (select 1 from estagio_autonomia where estagio = 'estagio_0219'), 'com a policy de INSERT do dial aberta, a Analista ainda leva 42501 (o gatilho)', v_t);
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$update premissa_catalogo set ativo = ativo where codigo = 'IPCA'$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = '42501', 'com a policy de UPDATE do catálogo aberta, a Analista ainda leva 42501 (o gatilho)', v_t);
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$insert into premissa_catalogo (codigo, nome, natureza, formula) select 'X0219', 'x', natureza, formula from premissa_catalogo limit 1$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = '42501' and not exists (select 1 from premissa_catalogo where codigo = 'X0219'), 'com a policy de INSERT do catálogo aberta, a Analista ainda leva 42501 (o gatilho)', v_t);
  -- (as policies ficam abertas até o rollback: nada abaixo depende delas)
end $$;

-- =============================================================================
-- PARTE 2 — O RISCO QUE A REGRA SIMPLES ABRE, e a sonda que o acusa
-- =============================================================================
do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000000d901';
  u_ana   uuid := '00000000-0000-0000-0000-00000000d902';
  v_t text; v_acusa boolean; v_det text; v_est constant text := 'classificacao_doc_checklist';
begin
  raise notice '--- 4. uma função SECURITY DEFINER executável por authenticated que escreve no dial BURLA a guarda — e a sonda a acusa ---';
  perform teste_assert_0219((select presente and severidade = 'bloqueante' from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'),
    'controle: no banco montado o requisito definer_nao_escreve_no_dial está presente e é BLOQUEANTE (nenhuma função definer escreve no dial)',
    (select detalhe from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'));

  update estagio_autonomia set nivel_atual = 'N1', base_do_nivel = 'nao_se_aplica', auto_promocao = false, atualizado_por = 'teste:0219' where estagio = v_est;
  create function fn_0219_definer_update() returns void language sql security definer set search_path = public, pg_temp
    as $f$ update estagio_autonomia set nivel_atual = 'N2' where estagio = 'classificacao_doc_checklist' $f$;
  revoke all on function fn_0219_definer_update() from public;
  grant execute on function fn_0219_definer_update() to authenticated;
  -- O RISCO É REAL: a Analista chama a RPC e o dial muda, sem ser Sócio. É o que o portão existe para impedir.
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$select fn_0219_definer_update()$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = 'ok:1' and teste_nivel_0219() = 'N2', 'controle: a definer executável por authenticated BURLA a guarda (a Analista muda o dial por ela) — o risco que a sonda cobre', v_t || ' / ' || teste_nivel_0219());
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial';
  perform teste_assert_0219(v_acusa and v_det like '%fn_0219_definer_update%', 'a sonda ACUSA a definer que dá UPDATE em estagio_autonomia, pelo nome', v_det);
  drop function fn_0219_definer_update();
  perform teste_assert_0219((select presente from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'), 'removida a função, a sonda volta a verde (era ela que acusava)');

  create function fn_0219_definer_premissa() returns void language sql security definer set search_path = public, pg_temp
    as $f$ insert into public."premissa_catalogo" (codigo, nome, natureza, formula) select 'Y0219', 'y', natureza, formula from premissa_catalogo limit 1 $f$;
  grant execute on function fn_0219_definer_premissa() to authenticated;
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial';
  perform teste_assert_0219(v_acusa and v_det like '%fn_0219_definer_premissa%', 'a sonda ACUSA a definer que dá INSERT em premissa_catalogo (com schema e aspas), pelo nome', v_det);
  drop function fn_0219_definer_premissa();

  create function fn_0219_definer_delete() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin DELETE FROM PUBLIC.ESTAGIO_AUTONOMIA where estagio = 'inexistente'; end $f$;
  grant execute on function fn_0219_definer_delete() to authenticated;
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial';
  perform teste_assert_0219(v_acusa and v_det like '%fn_0219_definer_delete%', 'a sonda ACUSA o DELETE em maiúsculas e com schema (a busca ignora caixa)', v_det);
  drop function fn_0219_definer_delete();

  create function fn_0219_definer_chama() returns jsonb language sql security definer set search_path = public, pg_temp
    as $f$ select fn_mudar_dial('classificacao_doc_checklist', 'N2', 'x', 'y', null, null, null, true) $f$;
  grant execute on function fn_0219_definer_chama() to authenticated;
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial';
  perform teste_assert_0219(v_acusa and v_det like '%fn_0219_definer_chama%', 'a sonda ACUSA a definer que CHAMA fn_mudar_dial (o caminho indireto do pedido)', v_det);
  drop function fn_0219_definer_chama();

  create function fn_0219_trigger_definer() returns trigger language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin update estagio_autonomia set atualizado_por = atualizado_por; return null; end $f$;
  revoke all on function fn_0219_trigger_definer() from public;   -- sem EXECUTE para ninguém: o gatilho dispara mesmo assim
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial';
  perform teste_assert_0219(v_acusa and v_det like '%fn_0219_trigger_definer%', 'a sonda ACUSA a função de GATILHO definer que escreve no dial, mesmo sem EXECUTE para authenticated (ela roda como dono ao disparar)', v_det);
  drop function fn_0219_trigger_definer();

  -- O que NÃO é perigoso não é acusado (senão o portão vira ruído e se aprende a ignorá-lo).
  create function fn_0219_fechada() returns void language sql security definer set search_path = public, pg_temp
    as $f$ update estagio_autonomia set atualizado_por = atualizado_por $f$;
  revoke all on function fn_0219_fechada() from public;
  perform teste_assert_0219((select presente from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'),
    'definer que escreve mas FECHADA ao authenticated (como fn_dial_auto_promover: só o gatilho e o service_role) NÃO é acusada');
  drop function fn_0219_fechada();
  create function fn_0219_invoker() returns void language sql set search_path = public, pg_temp
    as $f$ update estagio_autonomia set atualizado_por = atualizado_por $f$;
  grant execute on function fn_0219_invoker() to authenticated;
  perform teste_assert_0219((select presente from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'),
    'função INVOKER que escreve (a guarda de Sócio a barra) NÃO é acusada');
  drop function fn_0219_invoker();
  create function fn_0219_le() returns bigint language sql stable security definer set search_path = public, pg_temp
    as $f$ select count(*) from estagio_autonomia e join premissa_catalogo p on true $f$;
  grant execute on function fn_0219_le() to authenticated;
  perform teste_assert_0219((select presente from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'),
    'definer que só LÊ as tabelas (como fn_veredito_producao) NÃO é acusada');
  drop function fn_0219_le();
  perform teste_assert_0219((select presente from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'), 'removidas todas, a sonda está verde de novo (nada ficou na transação)');

  raise notice '--- 5. a reemissão não perdeu o que a 0217 e a 0218 puseram na sonda ---';
  perform teste_assert_0219((select presente and detalhe like 'segredo presente%' from fn_instalacao_conferir() where chave = 'envio_segredo_no_vault'),
    'o ramo `segredo` (0217) segue vivo: com o segredo no Vault, envio_segredo_no_vault está presente',
    (select presente::text || ' / ' || coalesce(detalhe, 'detalhe nulo') from fn_instalacao_conferir() where chave = 'envio_segredo_no_vault'));
  delete from vault.secrets where name = 'n8n_intake_segredo';
  perform teste_assert_0219((select not presente and detalhe like 'o Vault não tem%' from fn_instalacao_conferir() where chave = 'envio_segredo_no_vault'),
    'e sem o segredo no Vault o requisito fica AUSENTE e diz o motivo');
  insert into vault.secrets(name, description, secret) values ('n8n_intake_segredo', 'stub local', 'segredo-de-teste-do-run-sh');
  grant select on membro to anon;
  perform teste_assert_0219((select not presente and detalhe like '%membro%' from fn_instalacao_conferir() where chave = 'anon_sem_tabelas'),
    'o ramo `sem_privilegio` (0218) segue vivo: SELECT concedido a anon em membro é acusado pelo nome');
  revoke all on membro from anon;
  perform teste_assert_0219((select count(*) from fn_instalacao_conferir() where chave like 'anon_sem_%' and presente) = 4, 'e os 4 requisitos de anon estão presentes depois');
  perform teste_assert_0219(not exists (select 1 from instalacao_requisito where chave = 'dial_guarda_de_socio_tem_a_promocao')
                            and (select count(*) from fn_instalacao_conferir() where chave in ('dial_guarda_de_socio_confia_no_dono', 'dial_promocao_independe_do_leitor', 'dial_gatilho_independe_do_leitor') and presente) = 3,
    'o requisito da guarda foi renomeado (o antigo saiu) e os 3 requisitos do dial que dependiam da GUC conferem o corpo novo');
  perform teste_assert_0219(not has_function_privilege('authenticated', 'fn_dial_auto_promover(text)', 'execute') and has_function_privilege('service_role', 'fn_dial_auto_promover(text)', 'execute')
                            and not has_function_privilege('anon', 'fn_dial_auto_promover(text)', 'execute'),
    'fn_dial_auto_promover reemitida segue FECHADA ao authenticated e aberta ao service_role (o create or replace preservou a ACL)');
end $$;

-- =============================================================================
-- PARTE 2b — OS PONTOS CEGOS DO PORTÃO (revisão independente de 03/11/2026): cada arranjo é REPRODUZIDO (o Analista burla a guarda) e a sonda tem de ACUSAR
-- =============================================================================
do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000000d901';
  u_ana   uuid := '00000000-0000-0000-0000-00000000d902';
  v_t text; v_acusa boolean; v_det text; v_est constant text := 'classificacao_doc_checklist';
begin
  raise notice '--- 4b. controles: os dois requisitos existem, são bloqueantes e estão verdes no banco montado ---';
  perform teste_assert_0219((select count(*) from fn_instalacao_conferir() where chave in ('definer_nao_escreve_no_dial', 'dial_sem_cascata_de_fk') and presente and severidade = 'bloqueante') = 2,
    'controle: definer_nao_escreve_no_dial e dial_sem_cascata_de_fk estão presentes e BLOQUEANTES no banco montado',
    (select string_agg(chave || '=' || presente::text || ' ' || coalesce(detalhe, ''), ' | ') from fn_instalacao_conferir() where chave in ('definer_nao_escreve_no_dial', 'dial_sem_cascata_de_fk')));
  perform teste_assert_0219(exists (select 1 from pg_constraint c where c.contype = 'f' and c.conrelid = 'golden_criterio'::regclass and c.confrelid = 'estagio_autonomia'::regclass and c.confdeltype = 'c'),
    'controle: a única cascata que toca estagio_autonomia é golden_criterio -> estagio_autonomia (ela é PAI: apaga o filho, que não é protegido) e a sonda a deixa passar');

  raise notice '--- 4c. PONTO CEGO 1 (transitividade): a definer que chama um helper INVOKER que escreve no dial burla a guarda — e a sonda acusa ---';
  update estagio_autonomia set nivel_atual = 'N1', base_do_nivel = 'nao_se_aplica', auto_promocao = false, atualizado_por = 'teste:0219' where estagio = v_est;
  create function fn_0219_helper_inv(p text) returns void language sql set search_path = public, pg_temp
    as $f$ update premissa_catalogo set descricao = p where codigo = 'IPCA' $f$;                       -- INVOKER: dentro da definer roda como dono
  revoke all on function fn_0219_helper_inv(text) from public;
  create function fn_0219_def_helper() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin perform fn_0219_helper_inv('HACK'); end $f$;                                          -- o corpo da definer NÃO escreve em nada
  revoke all on function fn_0219_def_helper() from public;
  grant execute on function fn_0219_def_helper() to authenticated;
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$select fn_0219_def_helper()$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = 'ok:1' and (select descricao from premissa_catalogo where codigo = 'IPCA') = 'HACK',
    'controle: a definer que só chama o helper INVOKER BURLA a guarda (a Analista grava descricao = HACK no catálogo)', v_t);
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial';
  perform teste_assert_0219(v_acusa and v_det like '%fn_0219_def_helper%', 'a sonda ACUSA a definer que chama um helper INVOKER que escreve no catálogo (transitividade de uma volta)', v_det);
  perform teste_assert_0219(v_det not like '%fn_0219_helper_inv%', 'e acusa SÓ a definer: o helper INVOKER, que a guarda barra, não é acusado', v_det);

  -- Duas voltas: definer -> helper A (INVOKER) -> helper B (INVOKER) -> update. O fecho não pode parar na primeira.
  create function fn_0219_helper_b() returns void language sql set search_path = public, pg_temp
    as $f$ update estagio_autonomia set nivel_atual = 'N2' where estagio = 'classificacao_doc_checklist' $f$;
  create function fn_0219_helper_a() returns void language plpgsql set search_path = public, pg_temp
    as $f$ begin perform fn_0219_helper_b(); end $f$;
  create function fn_0219_def_fundo() returns void language sql security definer set search_path = public, pg_temp
    as $f$ select fn_0219_helper_a() $f$;
  grant execute on function fn_0219_def_fundo() to authenticated;
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$select fn_0219_def_fundo()$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = 'ok:1' and teste_nivel_0219() = 'N2', 'controle: a definer a DUAS chamadas do UPDATE também burla a guarda (a Analista sobe o dial)', v_t || ' / ' || teste_nivel_0219());
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial';
  perform teste_assert_0219(v_acusa and v_det like '%fn_0219_def_fundo%', 'a sonda ACUSA a definer a duas chamadas de distância (o fecho vai até onde der, sem limite de volta)', v_det);
  drop function fn_0219_def_fundo(); drop function fn_0219_helper_a(); drop function fn_0219_helper_b();
  drop function fn_0219_def_helper(); drop function fn_0219_helper_inv(text);
  perform teste_assert_0219((select presente from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'), 'removidas as funções do arranjo, a sonda volta a verde');

  -- GATILHO INVOKER numa tabela que uma definer escreve.
  update estagio_autonomia set nivel_atual = 'N1', atualizado_por = 'teste:0219' where estagio = v_est;
  create table teste_0219_alvo (id int);
  create function fn_0219_trg_inv() returns trigger language plpgsql set search_path = public, pg_temp
    as $f$ begin update estagio_autonomia set nivel_atual = 'N2' where estagio = 'classificacao_doc_checklist'; return new; end $f$;
  create trigger teste_0219_alvo_gat after insert on teste_0219_alvo for each row execute function fn_0219_trg_inv();
  create function fn_0219_def_grava() returns void language sql security definer set search_path = public, pg_temp
    as $f$ insert into teste_0219_alvo values (1) $f$;
  grant execute on function fn_0219_def_grava() to authenticated;
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$select fn_0219_def_grava()$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = 'ok:1' and teste_nivel_0219() = 'N2', 'controle: a definer que só INSERE numa tabela cujo gatilho INVOKER muda o dial BURLA a guarda (a Analista sobe o dial)', v_t || ' / ' || teste_nivel_0219());
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial';
  perform teste_assert_0219(v_acusa and v_det like '%fn_0219_def_grava%' and v_det not like '%fn_0219_trg_inv%', 'a sonda ACUSA a definer que escreve numa tabela com gatilho que escreve no dial (e não o gatilho INVOKER)', v_det);
  drop table teste_0219_alvo; drop function fn_0219_def_grava(); drop function fn_0219_trg_inv();

  -- O que NÃO é perigoso continua sem acusação (senão o fecho vira ruído).
  create table teste_0219_inofensiva (id int);
  create function fn_0219_trg_le() returns trigger language plpgsql set search_path = public, pg_temp
    as $f$ begin perform count(*) from estagio_autonomia; return new; end $f$;
  create trigger teste_0219_inofensiva_gat after insert on teste_0219_inofensiva for each row execute function fn_0219_trg_le();
  create function fn_0219_helper_le() returns bigint language sql stable set search_path = public, pg_temp as $f$ select count(*) from estagio_autonomia $f$;
  create function fn_0219_def_ok() returns bigint language sql security definer set search_path = public, pg_temp
    as $f$ insert into teste_0219_inofensiva values (1); select fn_0219_helper_le() $f$;
  grant execute on function fn_0219_def_ok() to authenticated;
  perform teste_assert_0219((select presente from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'),
    'definer que escreve em tabela com gatilho que só LÊ o dial e chama helper que só LÊ NÃO é acusada');
  create function fn_0219_def_porta() returns jsonb language sql security definer set search_path = public, pg_temp
    as $f$ select fn_dial_auto_promover(null) $f$;
  grant execute on function fn_0219_def_porta() to authenticated;
  perform teste_assert_0219((select presente from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'),
    'definer que chama fn_dial_auto_promover (a PORTA declarada: o caminho que o dono aprovou na 0137, só sobe com o veredito global) NÃO é acusada');
  drop function fn_0219_def_porta(); drop function fn_0219_def_ok(); drop function fn_0219_helper_le();
  drop table teste_0219_inofensiva; drop function fn_0219_trg_le();

  raise notice '--- 4d. PONTO CEGO 2 (begin atomic): o corpo não está em prosrc ---';
  update estagio_autonomia set nivel_atual = 'N1', atualizado_por = 'teste:0219' where estagio = v_est;
  execute $q$create function fn_0219_atomica() returns void language sql security definer set search_path = public, pg_temp
    begin atomic update estagio_autonomia set nivel_atual = 'N2' where estagio = 'classificacao_doc_checklist'; end$q$;
  grant execute on function fn_0219_atomica() to authenticated;
  perform teste_assert_0219((select p.prosrc = '' and p.prosqlbody is not null from pg_proc p where p.oid = 'fn_0219_atomica()'::regprocedure),
    'controle: no `begin atomic` o prosrc vem VAZIO e o corpo está em prosqlbody (o arranjo que cega a leitura de prosrc)');
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$select fn_0219_atomica()$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = 'ok:1' and teste_nivel_0219() = 'N2', 'controle: a definer `begin atomic` com UPDATE do dial BURLA a guarda (a Analista sobe o dial)', v_t || ' / ' || teste_nivel_0219());
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial';
  perform teste_assert_0219(v_acusa and v_det like '%fn_0219_atomica%', 'a sonda ACUSA a definer `begin atomic` que dá UPDATE em estagio_autonomia', v_det);
  drop function fn_0219_atomica();
  execute $q$create function fn_0219_atomica_chama() returns void language sql security definer set search_path = public, pg_temp
    begin atomic select fn_mudar_dial('classificacao_doc_checklist', 'N2', 'x', 'y', null, null, null, true); end$q$;
  grant execute on function fn_0219_atomica_chama() to authenticated;
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial';
  perform teste_assert_0219(v_acusa and v_det like '%fn_0219_atomica_chama%', 'a sonda ACUSA a definer `begin atomic` que CHAMA fn_mudar_dial (a chamada também está só em prosqlbody)', v_det);
  drop function fn_0219_atomica_chama();

  raise notice '--- 4e. PONTO CEGO 4 (event_trigger): a função de event trigger definer que escreve no dial ---';
  create function fn_0219_evt_escreve() returns event_trigger language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin update estagio_autonomia set atualizado_por = atualizado_por; end $f$;
  revoke all on function fn_0219_evt_escreve() from public;           -- sem EXECUTE para ninguém: o event trigger dispara mesmo assim
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial';
  perform teste_assert_0219(v_acusa and v_det like '%fn_0219_evt_escreve%', 'a sonda ACUSA a função de EVENT TRIGGER definer que escreve no dial, mesmo sem EXECUTE para authenticated', v_det);
  drop function fn_0219_evt_escreve();
  perform teste_assert_0219((select presente from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'), 'removidas todas as funções do arranjo, a sonda do portão está verde de novo');

  raise notice '--- 4f. PONTO CEGO 3 (cascata de FK): a ação referencial roda como DONO da tabela ---';
  create table teste_0219_pai (id int primary key);
  insert into teste_0219_pai values (1), (2);
  grant select, delete, update on teste_0219_pai to authenticated;
  alter table premissa_catalogo add column pai_0219 int;
  update premissa_catalogo set pai_0219 = 1 where codigo = 'IPCA';
  alter table premissa_catalogo add constraint teste_0219_fk foreign key (pai_0219) references teste_0219_pai(id) on delete set null;
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$delete from teste_0219_pai where id = 1$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = 'ok:1' and (select pai_0219 from premissa_catalogo where codigo = 'IPCA') is null,
    'controle: com ON DELETE SET NULL a Analista que apaga o PAI altera uma linha do catálogo SEM ser Sócio (a ação roda como dono)', v_t);
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'dial_sem_cascata_de_fk';
  perform teste_assert_0219(v_acusa and v_det like '%teste_0219_fk%' and v_det like '%premissa_catalogo%', 'a sonda ACUSA a FK com premissa_catalogo como FILHA e ON DELETE SET NULL, pelo nome da constraint', v_det);
  alter table premissa_catalogo drop constraint teste_0219_fk;
  alter table premissa_catalogo add constraint teste_0219_fk foreign key (pai_0219) references teste_0219_pai(id) on update cascade;   -- on delete: no action
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'dial_sem_cascata_de_fk';
  perform teste_assert_0219(v_acusa and v_det like '%teste_0219_fk%', 'e acusa ON UPDATE CASCADE (o confupdtype, com o ON DELETE sem ação)', v_det);
  alter table premissa_catalogo drop constraint teste_0219_fk;
  alter table premissa_catalogo add constraint teste_0219_fk foreign key (pai_0219) references teste_0219_pai(id) on delete set default;
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'dial_sem_cascata_de_fk';
  perform teste_assert_0219(v_acusa and v_det like '%teste_0219_fk%', 'e acusa ON DELETE SET DEFAULT', v_det);
  alter table premissa_catalogo drop constraint teste_0219_fk;
  alter table premissa_catalogo add constraint teste_0219_fk foreign key (pai_0219) references teste_0219_pai(id) on delete restrict on update no action;
  perform teste_assert_0219((select presente from fn_instalacao_conferir() where chave = 'dial_sem_cascata_de_fk'), 'FK com premissa_catalogo como filha mas RESTRICT / NO ACTION NÃO é acusada (não altera linha)');
  alter table premissa_catalogo drop constraint teste_0219_fk;
  alter table estagio_autonomia add column pai_0219 int;
  alter table estagio_autonomia add constraint teste_0219_fk foreign key (pai_0219) references teste_0219_pai(id) on delete cascade;
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'dial_sem_cascata_de_fk';
  perform teste_assert_0219(v_acusa and v_det like '%estagio_autonomia%' and v_det like '%teste_0219_fk%', 'a sonda ACUSA a FK com estagio_autonomia como FILHA e ON DELETE CASCADE', v_det);
  alter table estagio_autonomia drop constraint teste_0219_fk;
  alter table estagio_autonomia drop column pai_0219;
  alter table premissa_catalogo drop column pai_0219;
  perform teste_assert_0219((select presente from fn_instalacao_conferir() where chave = 'dial_sem_cascata_de_fk'), 'removidas as FKs do arranjo, a sonda volta a verde');

  -- O FILHO com gatilho: a ação referencial dispara o gatilho do filho como dono, e o gatilho INVOKER escreve no dial. SÓ O BEFORE: medido, o gatilho AFTER do filho
  -- fica na fila da consulta externa e roda como o chamador (a primeira versão deste arranjo, com AFTER DELETE, levou 42501 da guarda); o BEFORE roda dentro da ação, como dono.
  update estagio_autonomia set nivel_atual = 'N1', atualizado_por = 'teste:0219' where estagio = v_est;
  create table teste_0219_filha (id int, pai int references teste_0219_pai(id) on delete cascade);
  insert into teste_0219_filha values (1, 2);
  create function fn_0219_trg_filha() returns trigger language plpgsql set search_path = public, pg_temp
    as $f$ begin update estagio_autonomia set nivel_atual = 'N2' where estagio = 'classificacao_doc_checklist'; return old; end $f$;
  create trigger teste_0219_filha_gat before delete on teste_0219_filha for each row execute function fn_0219_trg_filha();
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$delete from teste_0219_pai where id = 2$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = 'ok:1' and teste_nivel_0219() = 'N2', 'controle: a Analista que apaga o PAI sobe o dial pela cascata que dispara o gatilho do FILHO (que roda como dono)', v_t || ' / ' || teste_nivel_0219());
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'dial_sem_cascata_de_fk';
  perform teste_assert_0219(v_acusa and v_det like '%teste_0219_filha%' and v_det like '%gatilho%', 'a sonda ACUSA a FK com cascata cujo FILHO tem gatilho que escreve no dial', v_det);
  drop table teste_0219_filha; drop function fn_0219_trg_filha(); drop table teste_0219_pai;
  perform teste_assert_0219((select count(*) from fn_instalacao_conferir() where chave in ('definer_nao_escreve_no_dial', 'dial_sem_cascata_de_fk') and presente) = 2, 'removido tudo, os dois requisitos novos estão verdes (nada ficou na transação)');

  raise notice '--- 4g. a RAIZ por nome: se fn_mudar_dial passar a escrever por SQL dinâmico (o corpo não cita mais a tabela), quem a chama continua acusado ---';
  -- Última coisa do bloco: troca fn_mudar_dial por uma versão de mentira (a transação volta). Sem a raiz por nome, o fecho não a enxerga e a definer abaixo passaria.
  create or replace function fn_mudar_dial(p_estagio text, p_nivel nivel_autonomia, p_autor text, p_motivo text default null, p_limiar numeric default null,
                                           p_rodada_golden uuid default null, p_sem_medicao_porque text default null, p_por_veredito boolean default false)
    returns jsonb language plpgsql as $f$ begin execute 'update ' || 'estagio_autonomia set atualizado_por = atualizado_por'; return '{}'::jsonb; end $f$;
  create function fn_0219_def_dinamica() returns jsonb language sql security definer set search_path = public, pg_temp
    as $f$ select fn_mudar_dial('classificacao_doc_checklist', 'N2', 'x', 'y') $f$;
  grant execute on function fn_0219_def_dinamica() to authenticated;
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial';
  perform teste_assert_0219(v_acusa and v_det like '%fn_0219_def_dinamica%', 'a sonda ACUSA a definer que chama fn_mudar_dial mesmo com o corpo dela escrito por SQL dinâmico (a raiz é o NOME, não só o corpo)', v_det);
  drop function fn_0219_def_dinamica();
end $$;

-- =============================================================================
-- PARTE 2c — A SEGUNDA REVISÃO INDEPENDENTE (03/11/2026): o escape do nome, a porta por ASSINATURA, o `"public"."tabela"` e a porta que ganha EXECUTE
-- =============================================================================
do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000000d901';
  u_ana   uuid := '00000000-0000-0000-0000-00000000d902';
  v_t text; v_acusa boolean; v_det text; v_def text; v_ok1 boolean; v_ok2 boolean; v_ok3 boolean; v_ok4 boolean;
begin
  perform teste_assert_0219((select presente from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'), 'controle: a sonda do portão parte VERDE para a parte 2c');

  raise notice '--- 4h. ESCAPE: o nome entra no regex como TEXTO. A sonda não pode morrer nem deixar passar por causa de maiúscula, $ ou ( no nome ---';
  -- Tabela de nome com MAIÚSCULA ("Cx") com gatilho INVOKER que escreve no catálogo, e uma definer que só INSERE nela. O escape antigo punha `\` antes de TODA letra maiúscula: `\C` é
  -- "invalid escape" no regex do Postgres (a fn_instalacao_conferir() INTEIRA levantava erro: a sonda morria) e `\Z`, `\D`, `\S` viram âncora/classe (falso negativo calado).
  create table "Cx" (id int);
  create function fn_0219_trg_cx() returns trigger language plpgsql set search_path = public, pg_temp
    as $f$ begin update premissa_catalogo set descricao = 'HACKCX' where codigo = 'IPCA'; return new; end $f$;
  create trigger teste_0219_cx_gat after insert on "Cx" for each row execute function fn_0219_trg_cx();
  create function fn_0219_def_cx() returns void language sql security definer set search_path = public, pg_temp
    as $f$ insert into "Cx" values (1) $f$;
  grant execute on function fn_0219_def_cx() to authenticated;
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$select fn_0219_def_cx()$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = 'ok:1' and (select descricao from premissa_catalogo where codigo = 'IPCA') = 'HACKCX',
    'controle: a definer que insere em "Cx" (gatilho INVOKER escreve no catálogo) BURLA a guarda (a Analista grava descricao = HACKCX)', v_t);
  v_t := teste_tenta_0219('select count(*) from fn_instalacao_conferir()');
  perform teste_assert_0219(v_t like 'ok:%', 'a sonda NÃO morre com uma tabela de nome com maiúscula ("Cx") com gatilho (antes: invalid escape \C, e a fn_instalacao_conferir() inteira levantava erro)', v_t);
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial';
  perform teste_assert_0219(v_acusa and v_det like '%fn_0219_def_cx%', 'e ACUSA a definer que insere em "Cx" (o escape de maiúscula não pode virar classe/âncora e deixar passar)', v_det);
  drop table "Cx"; drop function fn_0219_def_cx(); drop function fn_0219_trg_cx();

  -- Função de nome com `$` (era âncora de fim de linha no padrão: falso negativo) e com `(` (parêntese desbalanceado: a sonda inteira morria).
  create function "zz$w"() returns void language sql set search_path = public, pg_temp as $f$ update premissa_catalogo set descricao = 'HACKW' where codigo = 'IPCA' $f$;
  create function fn_0219_def_dolar() returns void language sql security definer set search_path = public, pg_temp as $f$ select "zz$w"() $f$;
  grant execute on function fn_0219_def_dolar() to authenticated;
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$select fn_0219_def_dolar()$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = 'ok:1' and (select descricao from premissa_catalogo where codigo = 'IPCA') = 'HACKW',
    'controle: a definer que chama a função "zz$w" (INVOKER que escreve no catálogo) BURLA a guarda', v_t);
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial';
  perform teste_assert_0219(v_acusa and v_det like '%fn_0219_def_dolar%', 'a sonda ACUSA a definer que chama uma função de nome com $ (o $ do nome entrava cru no padrão: âncora, falso negativo)', v_det);
  create function "zz(w"() returns void language sql set search_path = public, pg_temp as $f$ update premissa_catalogo set descricao = 'HACKP' where codigo = 'IPCA' $f$;
  create function fn_0219_def_paren() returns void language sql security definer set search_path = public, pg_temp as $f$ select "zz(w"() $f$;
  grant execute on function fn_0219_def_paren() to authenticated;
  v_t := teste_tenta_0219('select count(*) from fn_instalacao_conferir()');
  perform teste_assert_0219(v_t like 'ok:%', 'a sonda NÃO morre com uma função de nome com ( (antes: "parentheses () not balanced", e a fn_instalacao_conferir() inteira levantava erro)', v_t);
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial';
  perform teste_assert_0219(v_acusa and v_det like '%fn_0219_def_paren%', 'e ACUSA a definer que chama a função de nome com (', v_det);
  drop function fn_0219_def_paren(); drop function "zz(w"(); drop function fn_0219_def_dolar(); drop function "zz$w"();

  raise notice '--- 4i. A PORTA é uma ASSINATURA, não um nome: uma sobrecarga de fn_dial_auto_promover não herda a isenção ---';
  update estagio_autonomia set nivel_atual = 'N1', atualizado_por = 'teste:0219' where estagio = 'classificacao_doc_checklist';
  create function fn_dial_auto_promover(p int) returns jsonb language sql set search_path = public, pg_temp
    as $f$ update estagio_autonomia set atualizado_por = 'HACKSOBRE' where estagio = 'classificacao_doc_checklist'; select '{}'::jsonb $f$;     -- INVOKER, e NÃO é a porta
  create function fn_0219_def_sobrecarga() returns jsonb language sql security definer set search_path = public, pg_temp as $f$ select fn_dial_auto_promover(1) $f$;
  grant execute on function fn_0219_def_sobrecarga() to authenticated;
  perform teste_como_0219(u_ana);
  v_t := teste_tenta_0219($q$select fn_0219_def_sobrecarga()$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t = 'ok:1' and (select atualizado_por from estagio_autonomia where estagio = 'classificacao_doc_checklist') = 'HACKSOBRE',
    'controle: a definer que chama a SOBRECARGA fn_dial_auto_promover(int) (INVOKER, escreve no dial) BURLA a guarda (a Analista grava no dial)', v_t);
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial';
  perform teste_assert_0219(v_acusa and v_det like '%fn_0219_def_sobrecarga%', 'a sonda ACUSA a definer que chama a sobrecarga (a porta é fn_dial_auto_promover(text), e não o nome)', v_det);
  drop function fn_0219_def_sobrecarga(); drop function fn_dial_auto_promover(int);
  perform teste_assert_0219((select presente from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'), 'removida a sobrecarga, a sonda volta a verde: a porta de verdade (fn_trg_auto_promover_dial -> fn_dial_auto_promover(text)) segue sem acusação');

  raise notice '--- 4j. a PORTA que ganha EXECUTE para authenticated é acusada por si mesma ---';
  grant execute on function fn_dial_auto_promover(text) to authenticated;
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial';
  perform teste_assert_0219(v_acusa and v_det like '%fn_dial_auto_promover(text)%', 'a sonda ACUSA fn_dial_auto_promover(text) quando ela ganha EXECUTE para authenticated (a isenção é de quem a chama, não dela)', v_det);
  revoke all on function fn_dial_auto_promover(text) from authenticated;
  perform teste_assert_0219((select presente from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'), 'tirado o EXECUTE, a sonda volta a verde');

  raise notice '--- 4k. `"public"."tabela"` (as duas partes entre aspas) também é escrita no dial ---';
  create function fn_0219_def_aspas() returns void language sql security definer set search_path = public, pg_temp
    as $f$ update "public"."estagio_autonomia" set atualizado_por = atualizado_por $f$;
  grant execute on function fn_0219_def_aspas() to authenticated;
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial';
  perform teste_assert_0219(v_acusa and v_det like '%fn_0219_def_aspas%', 'a sonda ACUSA a definer com `update "public"."estagio_autonomia"` (o prefixo aceitava `public.` e `"tabela"`, não `"public".`)', v_det);
  drop function fn_0219_def_aspas();
  create table teste_0219_pai_q (id int primary key);
  create table teste_0219_filha_q (id int, pai int references teste_0219_pai_q(id) on delete cascade);
  create function fn_0219_trg_filha_q() returns trigger language plpgsql set search_path = public, pg_temp
    as $f$ begin update "public"."estagio_autonomia" set atualizado_por = atualizado_por; return old; end $f$;
  create trigger teste_0219_filha_q_gat before delete on teste_0219_filha_q for each row execute function fn_0219_trg_filha_q();
  select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'dial_sem_cascata_de_fk';
  perform teste_assert_0219(v_acusa and v_det like '%teste_0219_filha_q%', 'a sonda da FK ACUSA a cascata cujo filho tem gatilho com `update "public"."estagio_autonomia"` (mesmo prefixo, parte B)', v_det);
  drop table teste_0219_filha_q; drop table teste_0219_pai_q; drop function fn_0219_trg_filha_q();
  perform teste_assert_0219((select count(*) from fn_instalacao_conferir() where chave in ('definer_nao_escreve_no_dial', 'dial_sem_cascata_de_fk') and presente) = 2, 'removido tudo, os dois requisitos estão verdes (nada ficou na transação)');

  raise notice '--- 4l. o que JUSTIFICA a porta está travado no corpo dela: a checagem do veredito e o teto N2 (e o marcador não depende de quebra de linha) ---';
  perform teste_assert_0219((select count(*) from fn_instalacao_conferir() where chave in ('dial_porta_exige_veredito_suficiente', 'dial_porta_para_em_n2') and presente and severidade = 'bloqueante') = 2,
    'controle: os dois requisitos do corpo da porta estão presentes e BLOQUEANTES no banco montado');
  v_def := pg_get_functiondef('fn_dial_auto_promover(text)'::regprocedure);
  perform teste_assert_0219(position('suficiente' in v_def) > 0 and position('''N2''::nivel_autonomia' in v_def) > 0, 'controle: o corpo publicado da porta traz a checagem do veredito e o N2 que os marcadores esperam');
  begin
    execute replace(v_def, 'coalesce((v_med->>''suficiente'')::boolean, false)', 'true');         -- a porta SEM a checagem do veredito
    select presente into v_ok1 from fn_instalacao_conferir() where chave = 'dial_porta_exige_veredito_suficiente';
    select presente into v_ok2 from fn_instalacao_conferir() where chave = 'dial_porta_para_em_n2';
    raise exception 'volta' using errcode = 'P0001';
  exception when sqlstate 'P0001' then null; end;
  perform teste_assert_0219(v_ok1 is false and v_ok2 is true, 'a porta SEM a checagem do veredito suficiente reprova o requisito da checagem (e só ele)', coalesce(v_ok1::text, 'nulo') || ' / ' || coalesce(v_ok2::text, 'nulo'));
  begin
    execute replace(v_def, '''N2''::nivel_autonomia, ''sistema:auto_dial''', '''N3''::nivel_autonomia, ''sistema:auto_dial''');   -- a porta SEM o teto N2
    select presente into v_ok1 from fn_instalacao_conferir() where chave = 'dial_porta_exige_veredito_suficiente';
    select presente into v_ok2 from fn_instalacao_conferir() where chave = 'dial_porta_para_em_n2';
    raise exception 'volta' using errcode = 'P0001';
  exception when sqlstate 'P0001' then null; end;
  perform teste_assert_0219(v_ok1 is true and v_ok2 is false, 'a porta que passa a subir a N3 reprova o requisito do teto N2 (e só ele)', coalesce(v_ok1::text, 'nulo') || ' / ' || coalesce(v_ok2::text, 'nulo'));
  begin
    execute replace(v_def, E'\n', E'\r\n');                                                         -- o corpo em produção pode vir com CRLF
    select presente into v_ok3 from fn_instalacao_conferir() where chave = 'dial_porta_exige_veredito_suficiente';
    select presente into v_ok4 from fn_instalacao_conferir() where chave = 'dial_porta_para_em_n2';
    raise exception 'volta' using errcode = 'P0001';
  exception when sqlstate 'P0001' then null; end;
  perform teste_assert_0219(v_ok3 is true and v_ok4 is true, 'com o corpo em CRLF os dois marcadores continuam presentes (não dependem de quebra de linha)', coalesce(v_ok3::text, 'nulo') || ' / ' || coalesce(v_ok4::text, 'nulo'));
  perform teste_assert_0219((select count(*) from fn_instalacao_conferir() where chave in ('dial_porta_exige_veredito_suficiente', 'dial_porta_para_em_n2') and presente) = 2, 'e a porta de verdade, restaurada pelo rollback do bloco, está com os dois marcadores');

  raise notice '--- 4m. a porta que SUMIU (assinatura que não resolve) não cega o fecho: um NULL dentro do `<> all` apagaria a junção inteira e tudo ficaria verde ---';
  begin
    drop function fn_dial_auto_promover(text);
    create function fn_0219_def_semporta() returns jsonb language sql security definer set search_path = public, pg_temp
      as $f$ select fn_mudar_dial('classificacao_doc_checklist', 'N2', 'x', 'y') $f$;
    grant execute on function fn_0219_def_semporta() to authenticated;
    v_t := teste_tenta_0219('select count(*) from fn_instalacao_conferir()');
    select not presente, detalhe into v_acusa, v_det from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial';
    raise exception 'volta' using errcode = 'P0001';
  exception when sqlstate 'P0001' then null; end;
  perform teste_assert_0219(v_t like 'ok:%' and v_acusa and v_det like '%fn_0219_def_semporta%', 'sem a porta no banco a sonda não morre e continua acusando a definer que chama a raiz fn_mudar_dial', coalesce(v_t, 'nulo') || ' / ' || coalesce(v_det, 'nulo'));
  perform teste_assert_0219(to_regprocedure('fn_dial_auto_promover(text)') is not null and (select presente from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'), 'e a porta de verdade voltou com o rollback do bloco (sonda verde)');
end $$;

-- =============================================================================
-- PARTE 3 — O EVENT TRIGGER DA PLATAFORMA: não é chamável, a sonda do anon o ignora, a migration devolve o PUBLIC
-- =============================================================================
do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000000d901';
  v_t text; v_det text; v_ok boolean;
begin
  raise notice '--- 6. função que retorna event_trigger não é chamável, nem por quem tem EXECUTE ---';
  create function fn_0219_evt() returns event_trigger language plpgsql as $f$ begin null; end $f$;   -- nasce com EXECUTE para PUBLIC
  perform teste_assert_0219(has_function_privilege('anon', 'fn_0219_evt()', 'execute'), 'controle: o anon TEM o EXECUTE de PUBLIC nela (a simulação armou o caso)');
  v_t := teste_tenta_0219($q$select fn_0219_evt()$q$);
  perform teste_assert_0219(v_t <> 'ok:1', 'como dono, `select fn_0219_evt()` falha (não há como chamar uma função de event trigger por SQL)', v_t);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  v_t := teste_tenta_0219($q$select fn_0219_evt()$q$);
  perform teste_super_0219(u_socio);
  perform teste_assert_0219(v_t <> 'ok:1' and v_t <> '42501', 'como anon, com o EXECUTE de PUBLIC, também falha — e NÃO por permissão: a função em si não é chamável (por SQL nem por RPC)', v_t);

  raise notice '--- 7. a sonda do anon ignora a função de event_trigger e continua acusando a comum ---';
  select presente, detalhe into v_ok, v_det from fn_instalacao_conferir() where chave = 'anon_sem_funcoes';
  perform teste_assert_0219(v_ok, 'função de event_trigger, dona postgres, com EXECUTE para PUBLIC: anon_sem_funcoes NÃO acusa', v_det);
  create function fn_0219_comum() returns int language sql as 'select 1';                -- a mesma situação: dona postgres, EXECUTE de PUBLIC
  select presente, detalhe into v_ok, v_det from fn_instalacao_conferir() where chave = 'anon_sem_funcoes';
  perform teste_assert_0219(not v_ok and v_det like '%fn_0219_comum%' and v_det not like '%fn_0219_evt%', 'a função COMUM na mesma situação É acusada, pelo nome (e a de event_trigger, não)', v_det);
  drop function fn_0219_comum();
  perform teste_assert_0219((select presente from fn_instalacao_conferir() where chave = 'anon_sem_funcoes'), 'removida a comum, a sonda volta a verde');
  drop function fn_0219_evt();

  raise notice '--- 8. a migration devolve o PUBLIC a rls_auto_enable (e só a ele, e só se retornar event_trigger) ---';
  -- O estado de produção depois da 0218: ACL {postgres, authenticated, service_role, supabase_read_only_user}, sem PUBLIC.
  if not exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then create role supabase_read_only_user nologin; end if;
  create function public.rls_auto_enable() returns event_trigger language plpgsql security definer set search_path = pg_catalog as $f$ begin null; end $f$;
  revoke all on function public.rls_auto_enable() from public;
  grant execute on function public.rls_auto_enable() to authenticated, service_role, supabase_read_only_user;
  perform teste_assert_0219(not has_function_privilege('anon', 'public.rls_auto_enable()', 'execute') and has_function_privilege('authenticated', 'public.rls_auto_enable()', 'execute'),
    'controle: o estado que a 0218 deixou em produção (anon sem EXECUTE, authenticated com grant explícito)');
end $$;

\i :arq0219

do $$
declare
  v_det text; v_ok boolean;
  v_acl aclitem[] := (select proacl from pg_proc where oid = 'public.rls_auto_enable()'::regprocedure);
begin
  perform teste_assert_0219(has_function_privilege('anon', 'public.rls_auto_enable()', 'execute'), 'depois da migration, rls_auto_enable tem de novo o EXECUTE de PUBLIC (anon o herda)', v_acl::text);
  perform teste_assert_0219((select count(*) from aclexplode(v_acl) a where a.grantee in (select oid from pg_roles where rolname in ('authenticated', 'service_role', 'supabase_read_only_user'))) = 0
                            and (select count(*) from aclexplode(v_acl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE') = 1
                            and (select count(*) from aclexplode(v_acl) a where a.grantee = (select oid from pg_roles where rolname = 'postgres') and a.privilege_type = 'EXECUTE') = 1,
    'e a ACL é a de ANTES da 0218: PUBLIC e o dono, sem os grants explícitos que a 0218 pôs', v_acl::text);
  perform teste_assert_0219(has_function_privilege('authenticated', 'public.rls_auto_enable()', 'execute') and has_function_privilege('service_role', 'public.rls_auto_enable()', 'execute'),
    'authenticated e service_role seguem executando, agora por PUBLIC');
  select presente, detalhe into v_ok, v_det from fn_instalacao_conferir() where chave = 'anon_sem_funcoes';
  perform teste_assert_0219(v_ok, 'e a sonda NÃO acusa a correção (função de event_trigger com PUBLIC): anon_sem_funcoes presente', v_det);
  perform teste_assert_0219((select count(*) from fn_instalacao_conferir() where chave like 'anon_sem_%' and presente) = 4, 'os 4 requisitos de anon estão presentes depois da correção');

  raise notice '--- 9. função homônima que NÃO retorna event_trigger não é aberta ---';
  drop function public.rls_auto_enable();
  create function public.rls_auto_enable() returns int language sql security definer set search_path = pg_catalog as 'select 1';
  revoke all on function public.rls_auto_enable() from public;
  grant execute on function public.rls_auto_enable() to authenticated;
end $$;

\i :arq0219

do $$
begin
  perform teste_assert_0219(not has_function_privilege('anon', 'public.rls_auto_enable()', 'execute') and has_function_privilege('authenticated', 'public.rls_auto_enable()', 'execute'),
    'uma função de mesmo nome que NÃO retorna event_trigger fica como estava (sem PUBLIC): a migration só abre a da plataforma');
end $$;

-- O número de execuções tem de ser o do arquivo (110): o run.sh só filtra NOTICE/ERROR/WARNING e o `select` do FIM abaixo some do log; um bloco que saiu cedo ou uma chamada que sumiu
-- passava calado (regra 7, achado da revisão independente de 03/11/2026).
do $$
declare v_esperado constant int := 110;
  v_real int := coalesce(nullif(current_setting('dial.execucoes', true), ''), '0')::int;
begin
  if v_real <> v_esperado then
    raise exception 'FALHOU: o teste da 0219 executou % asserts, e o arquivo declara %. Um bloco saiu antes ou uma chamada sumiu.', v_real, v_esperado;
  end if;
end $$;

select 'FIM 0219: ' || coalesce(current_setting('dial.execucoes', true), '0') || ' execuções, '
       || coalesce(nullif(current_setting('dial.falhas', true), ''), '0') || ' falhas' as medicao;

rollback;
