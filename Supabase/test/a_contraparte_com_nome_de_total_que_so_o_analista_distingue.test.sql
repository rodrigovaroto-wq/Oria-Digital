-- Testes da 0273: a contraparte com nome de total que o analista confirma, POR MANDATO (contraparte_confirmada, fn_contraparte_confirmar,
-- fn_contraparte_revogar, fn_contrapartes_confirmadas, fn_texto_normalizado).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO PROVA (comportamento, regra 3): a ESCRITA E A LEITURA COMO `authenticated` com papel e com membro de OUTRO mandato
-- (a lição .claude/memory/rls-so-select-passa-no-superusuario.md: como superusuário tudo passa). Sócio e Analista DO MANDATO confirmam e
-- revogam; Leitura, Analista de outro mandato, sem papel, JWT sem `sub`, `anon` e conexão de serviço NÃO; quem não enxerga o mandato não lê
-- (42501, nunca um array vazio) e a leitura direta da tabela não devolve a linha dele; o nome sai normalizado como a biblioteca (os três vetores
-- calculados por textoNormalizado, JS); no máximo UMA vigente (nem o service_role grava a segunda); revogar NÃO apaga; confirmar o que já
-- está vigente não duplica, não troca o autor e não grava evento; cada confirmação e cada revogação deixa um evento no mandato; tipo_base fora da lista
-- e contraparte vazia são recusados; a escrita direta do authenticated é negada. Os dados são montados como superusuário e o resto roda como o papel
-- de cada usuário (helpers teste_conf_0273 / teste_rev_0273 / teste_lis_0273).
--
-- Vetores da normalização: calculados por textoNormalizado (Leitor/lib/mapeamento.mjs) em 12/11/2026 e passados pelo coordenador; NÃO inventados aqui.
-- Nada deste arquivo reproduz arranjo de produção (a tabela nasce vazia, 0 confirmações).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número reprovado por guarda desligada está no cabeçalho de
-- Supabase/migrations/0273_a_contraparte_com_nome_de_total_que_so_o_analista_distingue.sql ("MEDIÇÃO NÃO-VAZIA").
-- `ct73.medindo = on` (PGOPTIONS='-c ct73.medindo=on') vira `raise warning` e CONTA (ct73.execucoes / ct73.falhas); sem a variável, o assert é
-- `raise exception` (o CI).

\set ON_ERROR_STOP on

create or replace function teste_assert_0273(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('ct73.execucoes', (coalesce(nullif(current_setting('ct73.execucoes', true), ''), '0')::int + 1)::text, false);
  if p_ok then
    raise notice 'ok    %', p_nome;
  elsif current_setting('ct73.medindo', true) = 'on' then
    perform set_config('ct73.falhas', (coalesce(nullif(current_setting('ct73.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- 'ok|<json>' -> o json; qualquer outra coisa -> NULL (o assert que o usa reprova pela comparação, em vez de morrer num cast).
create or replace function teste_json_0273(p_res text) returns jsonb
language sql immutable as $$ select case when p_res like 'ok|{%' or p_res like 'ok|[%' then substring(p_res from 4)::jsonb end $$;

-- Entra como `p_papel` (authenticated com o JWT do usuário; NULL = JWT SEM sub), executa a expressão, volta a superusuário com o JWT do Sócio
-- padrão do run.sh. Devolve 'ok|<resultado em texto>' ou '<sqlstate>|<mensagem>'.
create or replace function teste_exec_0273(p_uid uuid, p_papel text, p_expr text)
returns text language plpgsql as $$
declare v_r text; v_out text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '{"role":"authenticated"}'
                     else jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
  execute format('set local role %I', p_papel);
  begin
    -- SQL DINÂMICO de propósito: o plpgsql guarda o plano de uma expressão simples pela transação e NÃO reconfere o EXECUTE depois de um `set role`
    -- (medido na 0272: a 3ª chamada como anon passava). Com `execute` o privilégio é conferido a cada chamada, como a requisição de verdade.
    execute 'select (' || p_expr || ')::text' into v_r;
    v_out := 'ok|' || coalesce(v_r, 'NULL');
  exception when others then
    v_out := sqlstate || '|' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  return v_out;
end $$;

create or replace function teste_conf_0273(p_uid uuid, p_caso uuid, p_tipo text, p_nome text, p_papel text default 'authenticated')
returns text language sql as $$
  select teste_exec_0273(p_uid, p_papel, format('fn_contraparte_confirmar(%L::uuid, %L, %L)', p_caso, p_tipo, p_nome)) $$;

create or replace function teste_rev_0273(p_uid uuid, p_caso uuid, p_tipo text, p_nome text, p_papel text default 'authenticated')
returns text language sql as $$
  select teste_exec_0273(p_uid, p_papel, format('fn_contraparte_revogar(%L::uuid, %L, %L)', p_caso, p_tipo, p_nome)) $$;

-- A lista vira jsonb para o assert comparar elemento a elemento (array de texto em texto escapa aspas e espaços).
create or replace function teste_lis_0273(p_uid uuid, p_caso uuid, p_tipo text, p_papel text default 'authenticated')
returns text language sql as $$
  select teste_exec_0273(p_uid, p_papel, format('to_jsonb(fn_contrapartes_confirmadas(%L::uuid, %L))', p_caso, p_tipo)) $$;

-- Executa um comando COMO o papel (com o JWT do usuário) e devolve o SQLSTATE ('ok' se passou).
create or replace function teste_sql_0273(p_uid uuid, p_papel text, p_sql text) returns text
language plpgsql as $$
declare v_out text;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', p_papel)::text, true);
  execute format('set local role %I', p_papel);
  begin
    execute p_sql;
    v_out := 'ok';
  exception when others then
    v_out := sqlstate;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  return v_out;
end $$;

-- Quantas linhas o usuário VÊ na tabela (a leitura direta, pela policy).
create or replace function teste_ve_0273(p_uid uuid, p_caso uuid) returns int
language plpgsql as $$
declare v_n int;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute format('select count(*) from contraparte_confirmada where caso_id = %L', p_caso) into v_n;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  return v_n;
end $$;

-- Quantos eventos do mandato o usuário VÊ na trilha (evento_auditoria é lida pelo mandato do entidade_ref).
create or replace function teste_ve_evento_0273(p_uid uuid, p_caso uuid) returns int
language plpgsql as $$
declare v_n int;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute format('select count(*) from evento_auditoria where entidade_ref = %L and acao in (''contraparte_confirmada'', ''contraparte_revogada'')', 'caso:' || p_caso) into v_n;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  return v_n;
end $$;

-- Limpeza de rodada anterior (o teste é reexecutável).
delete from contraparte_confirmada;
delete from evento_auditoria where acao in ('contraparte_confirmada', 'contraparte_revogada');
delete from caso where nome like '0273 —%';
delete from auth.users where id in ('00000000-0000-0000-0000-00000273b001', '00000000-0000-0000-0000-00000273b002',
  '00000000-0000-0000-0000-00000273b003', '00000000-0000-0000-0000-00000273b004', '00000000-0000-0000-0000-00000273b005');

do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000273b001';
  u_ana   uuid := '00000000-0000-0000-0000-00000273b002';   -- Analista alocada em A
  u_leo   uuid := '00000000-0000-0000-0000-00000273b003';   -- Leitura alocado em A
  u_nil   uuid := '00000000-0000-0000-0000-00000273b004';   -- SEM papel
  u_xan   uuid := '00000000-0000-0000-0000-00000273b005';   -- Analista alocado só em B (o membro de OUTRO mandato)
  v_a uuid; v_b uuid;
  v_rec  constant text := 'contas_a_receber';
  v_pag  constant text := 'contas_a_pagar';
  -- os três vetores de textoNormalizado (JS)
  v_v1   text := '  SOMA ' || chr(160) || ' ENGENHARIA  LTDA' || chr(160);
  v_v2   text := 'CONSTRUC' || U&'\0327' || 'A' || U&'\0303' || 'O TOTAL S.A.';
  v_v2n  text := 'CONSTRU' || U&'\00C7' || U&'\00C3' || 'O TOTAL S.A.';
  v_v3   text := U&'\2003' || 'ACME' || U&'\2003';
  v_res text; v_res2 text; v_n int; v_n2 int; v_ev int; v_ev2 int; v_id uuid; v_id2 uuid; v_em timestamptz; v_r jsonb;
begin
  insert into auth.users (id, email) values (u_socio, 'socio@0273.local'), (u_ana, 'ana@0273.local'), (u_leo, 'leo@0273.local'),
    (u_nil, 'nil@0273.local'), (u_xan, 'xan@0273.local');
  perform fn_definir_papel(u_socio, 'socio', 'teste 0273');
  perform fn_definir_papel(u_ana, 'analista');
  perform fn_definir_papel(u_leo, 'leitura');
  perform fn_definir_papel(u_xan, 'analista');
  v_a := fn_upsert_caso('0273 — mandato A');
  v_b := fn_upsert_caso('0273 — mandato B');
  perform fn_alocar(v_a, u_ana);
  perform fn_alocar(v_a, u_leo);
  perform fn_alocar(v_b, u_xan);

  -- ------------------------------------------------------------------ 1. a normalização (vetores da biblioteca JS)
  raise notice '--- 1. a normalização do nome é a da biblioteca, calculada pelo banco ---';
  perform teste_assert_0273(fn_texto_normalizado(v_v1) = 'SOMA ENGENHARIA LTDA',
    'vetor 1: espaços nas pontas, NBSP (U+00A0) e espaço duplo colapsam: "SOMA ENGENHARIA LTDA"', fn_texto_normalizado(v_v1));
  perform teste_assert_0273(v_v2 <> v_v2n and fn_texto_normalizado(v_v2) = v_v2n,
    'vetor 2: o NFD (C + U+0327, A + U+0303) vira o NFC pré-composto "CONSTRUÇÃO TOTAL S.A."', fn_texto_normalizado(v_v2));
  perform teste_assert_0273(fn_texto_normalizado(v_v3) = v_v3,
    'vetor 3: U+2003 (espaço em) NÃO está na lista dos cinco: nem a biblioteca nem o banco o aparam', fn_texto_normalizado(v_v3));
  perform teste_assert_0273(fn_texto_normalizado('Valor' || chr(9) || chr(10) || chr(13) || ' Total') = 'Valor Total',
    'tab, quebra de linha e retorno entre palavras colapsam em um espaço', null);
  perform teste_assert_0273(fn_texto_normalizado(chr(9) || chr(10) || ' ACME ' || chr(13)) = 'ACME',
    'tab, quebra de linha e retorno também são aparados nas pontas', null);
  perform teste_assert_0273(fn_texto_normalizado('Total ACME') = 'Total ACME' and fn_texto_normalizado('Total ACME') <> 'total acme',
    'a caixa conta: o nome não passa por minúsculas (lower() depende do LC_CTYPE)', null);
  perform teste_assert_0273(fn_texto_normalizado(null) = '' and fn_texto_normalizado(chr(160) || ' ' || chr(9)) = '',
    'NULL e texto só de espaços (inclusive NBSP) viram vazio', null);
  -- A cópia da célula na impressão da 0272 e esta função são DUAS implementações da mesma conta: o teste as amarra.
  perform teste_assert_0273(
    (select bool_and(fn_impressao_do_cabecalho(jsonb_build_array(t.x)) = encode(sha256(convert_to(fn_texto_normalizado(t.x), 'UTF8')), 'hex'))
       from (values (v_v1), (v_v2), (v_v3), ('Cliente' || chr(160) || chr(9) || 'X'), ('  Já  ')) as t(x)),
    'para uma célula, a impressão do cabeçalho (0272) é o sha256 do texto desta função: as duas cópias da normalização não divergem', null);

  -- ------------------------------------------------------------------ 2. quem confirma
  raise notice '--- 2. quem confirma, COMO authenticated, no mandato (e quem não) ---';
  v_res := teste_conf_0273(u_ana, v_a, v_rec, v_v1);
  perform teste_assert_0273(v_res like 'ok|%', 'a Analista do mandato A confirma', v_res);
  perform teste_assert_0273((teste_json_0273(v_res) ->> 'contraparte') = 'SOMA ENGENHARIA LTDA' and (teste_json_0273(v_res) ->> 'id') is not null
                            and (teste_json_0273(v_res) ->> 'ja_vigente') = 'false',
    'a função devolve o id, o nome NORMALIZADO e ja_vigente = false', v_res);
  perform teste_assert_0273((select count(*) from contraparte_confirmada where caso_id = v_a and tipo_base = v_rec and contraparte = 'SOMA ENGENHARIA LTDA'
                              and confirmado_por = u_ana and confirmado_em is not null and revogado_em is null and revogado_por is null) = 1,
    'a linha gravada tem o nome normalizado, o mandato, o autor (auth.uid() da Analista) e está vigente', null);
  v_res := teste_conf_0273(u_socio, v_a, v_rec, v_v2);
  perform teste_assert_0273(v_res like 'ok|%' and (teste_json_0273(v_res) ->> 'contraparte') = v_v2n, 'o Sócio confirma (e o NFD é gravado em NFC)', v_res);
  v_res := teste_conf_0273(u_socio, v_b, v_pag, v_v3);
  perform teste_assert_0273(v_res like 'ok|%', 'o Sócio confirma também em outro mandato (B), em contas a pagar', v_res);

  select count(*) into v_n from contraparte_confirmada;
  select count(*) into v_ev from evento_auditoria where acao in ('contraparte_confirmada', 'contraparte_revogada');
  v_res := teste_conf_0273(u_leo, v_a, v_rec, 'TOTAL DISTRIBUIDORA LTDA');
  perform teste_assert_0273(v_res like '42501|%', 'a Leitura do mandato NÃO confirma (42501)', v_res);
  v_res := teste_conf_0273(u_xan, v_a, v_rec, 'TOTAL DISTRIBUIDORA LTDA');
  perform teste_assert_0273(v_res like '42501|%', 'a Analista de OUTRO mandato (alocada só em B) NÃO confirma em A (42501)', v_res);
  v_res := teste_conf_0273(u_ana, v_b, v_rec, 'TOTAL DISTRIBUIDORA LTDA');
  perform teste_assert_0273(v_res like '42501|%', 'a Analista de A NÃO confirma em B (42501)', v_res);
  v_res := teste_conf_0273(u_nil, v_a, v_rec, 'TOTAL DISTRIBUIDORA LTDA');
  perform teste_assert_0273(v_res like '42501|%', 'quem não tem papel NÃO confirma (42501)', v_res);
  v_res := teste_conf_0273(null, v_a, v_rec, 'TOTAL DISTRIBUIDORA LTDA');
  perform teste_assert_0273(v_res like '42501|%', 'authenticated com JWT SEM sub (anônimo) NÃO confirma (42501)', v_res);
  v_res := teste_conf_0273(u_ana, v_a, v_rec, 'TOTAL DISTRIBUIDORA LTDA', 'anon');
  perform teste_assert_0273(v_res like '42501|%', 'o papel anon não tem EXECUTE (42501)', v_res);
  v_res := teste_conf_0273(u_socio, null, v_rec, 'TOTAL DISTRIBUIDORA LTDA');
  perform teste_assert_0273(v_res like '42501|%', 'mandato nulo, ATÉ PARA O SÓCIO: recusa (42501); fn_pode_escrever_caso(NULL) é verdadeiro para o Sócio, e NULL não é "todos os mandatos"', v_res);
  -- conexão de serviço (sem JWT e sem role authenticated): não há auth.uid(), logo não há autor
  perform set_config('request.jwt.claims', '', true);
  begin
    perform fn_contraparte_confirmar(v_a, v_rec, 'TOTAL DISTRIBUIDORA LTDA');
    v_res := 'ok';
  exception when others then v_res := sqlstate; end;
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  perform teste_assert_0273(v_res = '42501', 'conexão de serviço (sem auth.uid()) NÃO confirma: confirmação sem autor não vale', v_res);
  select count(*) into v_n2 from contraparte_confirmada;
  perform teste_assert_0273(v_n2 = v_n, 'as sete recusas de papel e mandato não gravaram nada', v_n || ' -> ' || v_n2);
  select count(*) into v_ev2 from evento_auditoria where acao in ('contraparte_confirmada', 'contraparte_revogada');
  perform teste_assert_0273(v_ev2 = v_ev, 'e não deixaram evento na trilha', v_ev || ' -> ' || v_ev2);

  -- ------------------------------------------------------------------ 3. a validação recusa e não grava
  raise notice '--- 3. contraparte vazia, tipo_base fora da lista e mandato inexistente são recusados ---';
  select count(*) into v_n from contraparte_confirmada;
  v_res := teste_conf_0273(u_ana, v_a, v_rec, '');
  perform teste_assert_0273(v_res like '22023|%vazia%', 'contraparte vazia: recusa e diz o motivo', v_res);
  v_res := teste_conf_0273(u_ana, v_a, v_rec, '   ' || chr(160) || chr(9) || ' ');
  perform teste_assert_0273(v_res like '22023|%vazia%', 'contraparte só de espaços/NBSP/tab: vazia DEPOIS de normalizar, recusa', v_res);
  v_res := teste_conf_0273(u_ana, v_a, v_rec, null);
  perform teste_assert_0273(v_res like '22023|%vazia%', 'contraparte NULL: recusa', v_res);
  v_res := teste_conf_0273(u_ana, v_a, 'contas_a_pagar_e_a_receber', 'ACME');
  perform teste_assert_0273(v_res like '22023|%tipo_base%não existe%', 'tipo_base fora da lista: recusa na confirmação', v_res);
  v_res := teste_conf_0273(u_ana, v_a, null, 'ACME');
  perform teste_assert_0273(v_res like '22023|%tipo_base%não existe%', 'tipo_base nulo: recusa na confirmação', v_res);
  v_res := teste_rev_0273(u_ana, v_a, 'extrato', 'ACME');
  perform teste_assert_0273(v_res like '22023|%tipo_base%não existe%', 'tipo_base fora da lista: recusa também na revogação', v_res);
  v_res := teste_rev_0273(u_ana, v_a, v_rec, '  ');
  perform teste_assert_0273(v_res like '22023|%vazia%', 'revogar contraparte vazia: recusa', v_res);
  v_res := teste_conf_0273(u_socio, gen_random_uuid(), v_rec, 'ACME');
  perform teste_assert_0273(v_res like 'P0002|%', 'mandato que não existe (o Sócio passa pela guarda de acesso): recusa P0002, não violação de FK', v_res);
  select count(*) into v_n2 from contraparte_confirmada;
  perform teste_assert_0273(v_n2 = v_n, 'nenhuma recusa de validação gravou', v_n || ' -> ' || v_n2);
  select count(*) into v_ev2 from evento_auditoria where acao in ('contraparte_confirmada', 'contraparte_revogada');
  perform teste_assert_0273(v_ev2 = v_ev, 'nenhuma recusa de validação deixou evento', v_ev || ' -> ' || v_ev2);

  -- ------------------------------------------------------------------ 4. no máximo uma vigente
  raise notice '--- 4. no máximo UMA confirmação vigente por (mandato, tipo_base, nome normalizado) ---';
  select id, confirmado_em into v_id, v_em from contraparte_confirmada where caso_id = v_a and tipo_base = v_rec and contraparte = 'SOMA ENGENHARIA LTDA';
  select count(*) into v_ev from evento_auditoria where acao = 'contraparte_confirmada' and entidade_ref = 'caso:' || v_a;
  v_res := teste_conf_0273(u_socio, v_a, v_rec, '  SOMA   ENGENHARIA LTDA ');
  perform teste_assert_0273(v_res like 'ok|%' and (teste_json_0273(v_res) ->> 'id') = v_id::text and (teste_json_0273(v_res) ->> 'ja_vigente') = 'true',
    'confirmar de novo o que já está vigente (com outro espaçamento) devolve a MESMA vigente, ja_vigente = true', v_res);
  perform teste_assert_0273((select count(*) from contraparte_confirmada where caso_id = v_a and tipo_base = v_rec and contraparte = 'SOMA ENGENHARIA LTDA') = 1,
    'e não duplica a linha', null);
  perform teste_assert_0273((select confirmado_por = u_ana and confirmado_em = v_em from contraparte_confirmada where id = v_id),
    'e não reescreve o autor nem a data: vale a primeira confirmação (o Sócio que clicou depois não vira o autor)', null);
  select count(*) into v_ev2 from evento_auditoria where acao = 'contraparte_confirmada' and entidade_ref = 'caso:' || v_a;
  perform teste_assert_0273(v_ev2 = v_ev, 'e não grava um segundo evento', v_ev || ' -> ' || v_ev2);
  v_res := teste_conf_0273(u_ana, v_a, v_pag, 'SOMA ENGENHARIA LTDA');
  perform teste_assert_0273(v_res like 'ok|%' and (teste_json_0273(v_res) ->> 'ja_vigente') = 'false' and (teste_json_0273(v_res) ->> 'id') <> v_id::text,
    'o mesmo nome em OUTRO tipo_base é outra confirmação (a pagar não herda a de receber)', v_res);
  v_res := teste_conf_0273(u_socio, v_b, v_rec, 'SOMA ENGENHARIA LTDA');
  perform teste_assert_0273(v_res like 'ok|%' and (teste_json_0273(v_res) ->> 'ja_vigente') = 'false',
    'o mesmo nome em OUTRO mandato é outra confirmação (a do mandato A não vale em B)', v_res);
  -- A segunda vigente pelo caminho que não passa pela função: nem o superusuário nem o service_role gravam
  begin
    insert into contraparte_confirmada (caso_id, tipo_base, contraparte, confirmado_por) values (v_a, v_rec, 'SOMA ENGENHARIA LTDA', u_ana);
    v_res := 'ok';
  exception when others then v_res := sqlstate; end;
  perform teste_assert_0273(v_res = '23505', 'o banco recusa a segunda vigente (índice único parcial), mesmo sem a função', v_res);
  v_res := teste_sql_0273(u_ana, 'service_role', format(
    'insert into contraparte_confirmada (caso_id, tipo_base, contraparte, confirmado_por) values (%L, %L, %L, %L)', v_a, v_rec, 'SOMA ENGENHARIA LTDA', u_ana));
  perform teste_assert_0273(v_res = '23505', 'o service_role também leva 23505 na segunda vigente', v_res);
  v_res := teste_sql_0273(u_ana, 'service_role', format(
    'insert into contraparte_confirmada (caso_id, tipo_base, contraparte, confirmado_por) values (%L, %L, %L, %L)', v_a, v_rec, 'soma  engenharia ' || chr(160), u_ana));
  perform teste_assert_0273(v_res = '23514', 'o service_role não grava nome fora da forma normalizada (CHECK 23514)', v_res);
  v_res := teste_sql_0273(u_ana, 'service_role', format(
    'insert into contraparte_confirmada (caso_id, tipo_base, contraparte, confirmado_por) values (%L, %L, %L, %L)', v_a, v_rec, '', u_ana));
  perform teste_assert_0273(v_res = '23514', 'o service_role não grava nome vazio (CHECK 23514)', v_res);
  v_res := teste_sql_0273(u_ana, 'service_role', format(
    'insert into contraparte_confirmada (caso_id, tipo_base, contraparte, confirmado_por, revogado_em) values (%L, %L, %L, %L, now())', v_a, v_rec, 'ACME REVOGADA SEM AUTOR', u_ana));
  perform teste_assert_0273(v_res = '23514', 'o service_role não grava revogação sem autor (CHECK 23514)', v_res);
  v_res := teste_sql_0273(u_ana, 'service_role', format(
    'insert into contraparte_confirmada (caso_id, tipo_base, contraparte, confirmado_por) values (%L, %L, %L, %L)', v_a, 'extrato', 'ACME', u_ana));
  perform teste_assert_0273(v_res = '23514', 'o service_role não grava tipo_base fora da lista (CHECK 23514)', v_res);

  -- ------------------------------------------------------------------ 5. revogar não apaga
  raise notice '--- 5. revogar MARCA, não apaga; quem não escreve o mandato não revoga ---';
  select count(*) into v_n from contraparte_confirmada;
  v_res := teste_rev_0273(u_leo, v_a, v_rec, v_v1);
  perform teste_assert_0273(v_res like '42501|%', 'a Leitura NÃO revoga (42501)', v_res);
  v_res := teste_rev_0273(u_xan, v_a, v_rec, v_v1);
  perform teste_assert_0273(v_res like '42501|%', 'a Analista de OUTRO mandato NÃO revoga em A (42501)', v_res);
  v_res := teste_rev_0273(u_nil, v_a, v_rec, v_v1);
  perform teste_assert_0273(v_res like '42501|%', 'quem não tem papel NÃO revoga (42501)', v_res);
  v_res := teste_rev_0273(null, v_a, v_rec, v_v1);
  perform teste_assert_0273(v_res like '42501|%', 'JWT sem sub NÃO revoga (42501)', v_res);
  v_res := teste_rev_0273(u_ana, v_a, v_rec, v_v1, 'anon');
  perform teste_assert_0273(v_res like '42501|%', 'o papel anon não tem EXECUTE na revogação (42501)', v_res);
  perform teste_assert_0273((select count(*) from contraparte_confirmada where revogado_em is not null) = 0 and (select count(*) from contraparte_confirmada) = v_n,
    'as cinco recusas não revogaram nada e não apagaram nada', null);
  select count(*) into v_ev from evento_auditoria where acao = 'contraparte_revogada';
  v_res := teste_rev_0273(u_ana, v_a, v_rec, '  soma engenharia ltda');
  perform teste_assert_0273(v_res like 'P0002|%Não há confirmação vigente%', 'revogar com outra caixa: o nome é outro, não há vigente (a caixa conta) e a recusa diz isso', v_res);
  v_res := teste_rev_0273(u_ana, v_a, v_rec, ' SOMA  ' || chr(160) || 'ENGENHARIA LTDA ');
  perform teste_assert_0273(v_res like 'ok|%' and (teste_json_0273(v_res) ->> 'id') = v_id::text and (teste_json_0273(v_res) ->> 'contraparte') = 'SOMA ENGENHARIA LTDA',
    'a Analista revoga (o nome vem normalizado, com NBSP e espaço duplo) e a função devolve o id da confirmação', v_res);
  perform teste_assert_0273((select count(*) from contraparte_confirmada) = v_n, 'a linha continua lá: revogar NÃO apaga', null);
  perform teste_assert_0273((select revogado_em is not null and revogado_por = u_ana and confirmado_por = u_ana and confirmado_em = v_em from contraparte_confirmada where id = v_id),
    'a linha ficou marcada com data e autor da revogação, e a confirmação original intacta', null);
  v_res := teste_rev_0273(u_ana, v_a, v_rec, v_v1);
  perform teste_assert_0273(v_res like 'P0002|%', 'revogar o que já foi revogado: recusa (P0002), não "feito" calado', v_res);
  v_res := teste_rev_0273(u_ana, v_a, v_rec, 'NUNCA CONFIRMADA SA');
  perform teste_assert_0273(v_res like 'P0002|%', 'revogar o que nunca foi confirmado: recusa (P0002)', v_res);
  select count(*) into v_ev2 from evento_auditoria where acao = 'contraparte_revogada';
  perform teste_assert_0273(v_ev2 = v_ev + 1, 'só a revogação que valeu deixou evento (as recusas não)', v_ev || ' -> ' || v_ev2);
  v_res := teste_conf_0273(u_ana, v_a, v_rec, v_v1);
  select id into v_id2 from contraparte_confirmada where caso_id = v_a and tipo_base = v_rec and contraparte = 'SOMA ENGENHARIA LTDA' and revogado_em is null;
  perform teste_assert_0273(v_res like 'ok|%' and (teste_json_0273(v_res) ->> 'ja_vigente') = 'false' and v_id2 is not null and v_id2 <> v_id
                            and (select count(*) from contraparte_confirmada where caso_id = v_a and tipo_base = v_rec and contraparte = 'SOMA ENGENHARIA LTDA') = 2,
    'confirmar de novo depois de revogar cria linha NOVA: a trilha fica com a revogada e a vigente (2 linhas, 1 vigente)', v_res);

  -- ------------------------------------------------------------------ 6. listar: o que vai para contrapartesReais
  raise notice '--- 6. listar as vigentes: o array de contrapartesReais, e "sem acesso" nunca parece "nenhuma" ---';
  v_res := teste_lis_0273(u_ana, v_a, v_rec);
  perform teste_assert_0273(teste_json_0273(v_res) = jsonb_build_array(v_v2n, 'SOMA ENGENHARIA LTDA'),
    'a Analista lista as vigentes de A em contas a receber: os dois nomes normalizados, ordenados, e a revogada-e-reconfirmada aparece UMA vez', v_res);
  v_res := teste_lis_0273(u_leo, v_a, v_rec);
  perform teste_assert_0273(teste_json_0273(v_res) = jsonb_build_array(v_v2n, 'SOMA ENGENHARIA LTDA'), 'a Leitura DO mandato lê a lista', v_res);
  v_res := teste_lis_0273(u_socio, v_a, v_rec);
  perform teste_assert_0273(teste_json_0273(v_res) = jsonb_build_array(v_v2n, 'SOMA ENGENHARIA LTDA'), 'o Sócio lê a lista', v_res);
  v_res := teste_lis_0273(u_ana, v_a, v_pag);
  perform teste_assert_0273(teste_json_0273(v_res) = jsonb_build_array('SOMA ENGENHARIA LTDA'), 'a lista é por tipo_base: em contas a pagar de A só a confirmada em contas a pagar', v_res);
  v_res := teste_lis_0273(u_socio, v_b, v_rec);
  perform teste_assert_0273(teste_json_0273(v_res) = jsonb_build_array('SOMA ENGENHARIA LTDA'), 'e por mandato: B só devolve o que foi confirmado em B', v_res);
  v_res := teste_lis_0273(u_xan, v_a, v_rec);
  perform teste_assert_0273(v_res like '42501|%' and v_res not like 'ok|%', 'quem não enxerga o mandato (Analista de B lendo A) leva 42501, NÃO um array vazio', v_res);
  v_res := teste_lis_0273(u_nil, v_a, v_rec);
  perform teste_assert_0273(v_res like '42501|%', 'quem não tem papel leva 42501, não array vazio', v_res);
  v_res := teste_lis_0273(null, v_a, v_rec);
  perform teste_assert_0273(v_res like '42501|%', 'JWT sem sub leva 42501, não array vazio', v_res);
  v_res := teste_lis_0273(u_ana, v_a, v_rec, 'anon');
  perform teste_assert_0273(v_res like '42501|%', 'o papel anon não tem EXECUTE na listagem (42501)', v_res);
  v_res := teste_lis_0273(u_socio, null, v_rec);
  perform teste_assert_0273(v_res like '42501|%', 'mandato nulo, até para o Sócio (fn_pode_ler_caso(NULL) é verdadeiro para ele): 42501, não array vazio', v_res);
  v_res := teste_lis_0273(u_socio, gen_random_uuid(), v_rec);
  perform teste_assert_0273(v_res like 'P0002|%', 'mandato inexistente (o Sócio passa pela guarda de acesso): P0002, não array vazio', v_res);
  v_res := teste_lis_0273(u_ana, v_a, 'extrato');
  perform teste_assert_0273(v_res like '22023|%tipo_base%', 'tipo_base fora da lista na listagem: recusa', v_res);
  -- Mandato lido, nada confirmado: vazio de verdade (o contraste que dá sentido à recusa acima)
  v_res := teste_lis_0273(u_xan, v_b, v_rec);
  perform teste_assert_0273(teste_json_0273(v_res) = jsonb_build_array('SOMA ENGENHARIA LTDA'), 'a Analista de B lê B (controle: o 42501 de cima é do mandato, não da função)', v_res);
  v_res := teste_lis_0273(u_xan, v_b, v_pag);
  perform teste_assert_0273(teste_json_0273(v_res) = jsonb_build_array(U&'\2003' || 'ACME' || U&'\2003'), 'o vetor 3 (U+2003) foi gravado como veio: o banco não o apara', v_res);
  v_res := teste_lis_0273(u_leo, v_a, v_pag);
  perform teste_assert_0273(teste_json_0273(v_res) = jsonb_build_array('SOMA ENGENHARIA LTDA'), 'controle da Leitura em contas a pagar', v_res);
  perform fn_contraparte_revogar(v_a, v_pag, 'SOMA ENGENHARIA LTDA');   -- Sócio padrão (a001) do run.sh
  v_res := teste_lis_0273(u_leo, v_a, v_pag);
  perform teste_assert_0273(v_res = 'ok|[]', 'mandato lido e nenhuma vigente: array VAZIO de verdade (revogada sai da lista)', v_res);
  -- conexão de serviço (o n8n) lê
  perform set_config('request.jwt.claims', '', true);
  begin
    v_res := 'ok|' || to_jsonb(fn_contrapartes_confirmadas(v_a, v_rec))::text;
  exception when others then v_res := sqlstate; end;
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  perform teste_assert_0273(teste_json_0273(v_res) = jsonb_build_array(v_v2n, 'SOMA ENGENHARIA LTDA'), 'a conexão de serviço (n8n) lê a lista', v_res);

  -- ------------------------------------------------------------------ 7. a leitura direta e a escrita direta
  raise notice '--- 7. a RLS por mandato na leitura direta; a escrita direta do authenticated é negada ---';
  perform teste_assert_0273(teste_ve_0273(u_leo, v_a) = (select count(*) from contraparte_confirmada where caso_id = v_a), 'a Leitura do mandato vê as linhas de A (todas, inclusive a revogada)', null);
  perform teste_assert_0273(teste_ve_0273(u_xan, v_a) = 0 and (select count(*) from contraparte_confirmada where caso_id = v_a) > 0,
    'a Analista de B vê ZERO linhas de A pela tabela (nome de cliente é dado do mandato)', null);
  perform teste_assert_0273(teste_ve_0273(u_nil, v_a) = 0, 'quem não tem papel vê zero linhas', null);
  perform teste_assert_0273(teste_ve_0273(u_socio, v_a) = (select count(*) from contraparte_confirmada where caso_id = v_a)
                            and teste_ve_0273(u_socio, v_b) = (select count(*) from contraparte_confirmada where caso_id = v_b), 'o Sócio vê os dois mandatos', null);
  perform teste_assert_0273(teste_sql_0273(u_ana, 'authenticated', format(
      'insert into contraparte_confirmada (caso_id, tipo_base, contraparte, confirmado_por) values (%L, %L, %L, %L)', v_a, v_rec, 'ESCRITA DIRETA SA', u_ana)) = '42501',
    'a Analista do mandato NÃO insere direto na tabela (sem grant e sem policy: 42501)', null);
  perform teste_assert_0273(teste_sql_0273(u_socio, 'authenticated', 'update contraparte_confirmada set revogado_em = null, revogado_por = null') = '42501',
    'nem o Sócio atualiza direto (desfazer uma revogação pelo lado de fora: 42501)', null);
  perform teste_assert_0273(teste_sql_0273(u_socio, 'authenticated', 'delete from contraparte_confirmada') = '42501',
    'nem o Sócio apaga direto (42501): a trilha das confirmações não se apaga', null);
  perform teste_assert_0273(not has_function_privilege('anon', 'fn_contraparte_confirmar(uuid, text, text)', 'execute')
                            and not has_function_privilege('anon', 'fn_contraparte_revogar(uuid, text, text)', 'execute')
                            and not has_function_privilege('anon', 'fn_contrapartes_confirmadas(uuid, text)', 'execute')
                            and has_function_privilege('authenticated', 'fn_contraparte_confirmar(uuid, text, text)', 'execute')
                            and has_function_privilege('service_role', 'fn_contrapartes_confirmadas(uuid, text)', 'execute'),
    'GRANT (0214): anon sem EXECUTE nas três funções públicas; authenticated e service_role com', null);

  -- ------------------------------------------------------------------ 8. a trilha
  raise notice '--- 8. cada confirmação e cada revogação deixa um evento no mandato ---';
  perform teste_assert_0273((select count(*) from evento_auditoria where acao = 'contraparte_confirmada' and entidade_ref = 'caso:' || v_a
                              and ator = 'usuario:' || u_ana and depois ->> 'contraparte' = 'SOMA ENGENHARIA LTDA' and depois ->> 'tipo_base' = v_rec) = 2,
    'a confirmação grava contraparte_confirmada (caso:<id>, autor, nome normalizado, tipo_base): 2 (a original e a reconfirmada depois de revogar)', null);
  perform teste_assert_0273((select count(*) from evento_auditoria where acao = 'contraparte_revogada' and entidade_ref = 'caso:' || v_a
                              and ator = 'usuario:' || u_ana and depois ->> 'id' = v_id::text and depois ->> 'contraparte' = 'SOMA ENGENHARIA LTDA') = 1,
    'a revogação grava contraparte_revogada com o id da confirmação revogada', null);
  perform teste_assert_0273((select count(*) from evento_auditoria where acao in ('contraparte_confirmada', 'contraparte_revogada') and entidade_ref = 'caso:' || v_a) = 6,
    'o mandato A tem 6 eventos: 4 confirmações (SOMA a receber, a do Sócio, SOMA a pagar, SOMA a receber de novo) e 2 revogações (a da Analista e a do Sócio em contas a pagar)',
    (select count(*)::text from evento_auditoria where acao in ('contraparte_confirmada', 'contraparte_revogada') and entidade_ref = 'caso:' || v_a));
  perform teste_assert_0273(teste_ve_evento_0273(u_leo, v_a) = 6, 'a Leitura do mandato A lê a trilha de A (o entidade_ref `caso:` resolve o mandato)', teste_ve_evento_0273(u_leo, v_a)::text);
  perform teste_assert_0273(teste_ve_evento_0273(u_xan, v_a) = 0, 'a Analista de B NÃO lê a trilha de A (o nome do cliente está no `depois`)', teste_ve_evento_0273(u_xan, v_a)::text);

  -- ------------------------------------------------------------------ 9. a sonda
  raise notice '--- 9. a sonda enxerga tudo o que a 0273 instala ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0273' and not presente;
  perform teste_assert_0273(v_n = 0, 'a sonda enxerga os 12 requisitos da 0273 (zero ausentes)', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0273';
  perform teste_assert_0273(v_n = 12, 'e o catálogo da 0273 tem 12 requisitos (não está vazio nem encolheu)', v_n::text);

  -- DEVOLVE O ESTADO: os dados de teste saem (a cascata de caso leva as confirmações; a de auth.users leva membro e alocacao).
  delete from contraparte_confirmada where caso_id in (v_a, v_b);
  delete from evento_auditoria where entidade_ref in ('caso:' || v_a, 'caso:' || v_b) and acao in ('contraparte_confirmada', 'contraparte_revogada');
  delete from caso where nome like '0273 —%';
  delete from auth.users where id in (u_socio, u_ana, u_leo, u_nil, u_xan);

  raise notice 'EXECUCOES=% FALHAS=%', current_setting('ct73.execucoes', true), coalesce(current_setting('ct73.falhas', true), '0');
  if current_setting('ct73.medindo', true) is distinct from 'on' then
    raise notice 'TODOS OS TESTES DA 0273 PASSARAM';
  end if;
end $$;
