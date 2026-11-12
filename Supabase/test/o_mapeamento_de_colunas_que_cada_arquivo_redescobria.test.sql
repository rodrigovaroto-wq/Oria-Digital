-- Testes da 0272: o mapeamento de colunas confirmado (mapeamento_de_colunas, fn_mapeamento_confirmar, fn_mapeamento_vigente).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO PROVA (comportamento, regra 3): a ESCRITA COMO `authenticated` com papel (a lição
-- .claude/memory/rls-so-select-passa-no-superusuario.md: como superusuário tudo passa) — Analista e Sócio confirmam, Leitura, sem papel,
-- JWT sem `sub` e `anon` NÃO; cada recusa de validação diz o porquê e não grava nada; a impressão do cabeçalho sai igual aos vetores calculados
-- pela biblioteca JS (Leitor/lib/mapeamento.mjs) e NFD = NFC; uma confirmação nova marca a anterior como substituída e só uma fica vigente
-- (nem o service_role grava a segunda); o formato é fechado (decimal, datas); a trilha grava o autor; a escrita direta do authenticated é negada.
-- Os dados são montados como superusuário e o resto roda como o papel de cada usuário (helpers teste_conf_0272 / teste_vig_0272).
--
-- Vetores das impressões: calculados por impressaoDoCabecalho (JS) em 11/11/2026 e passados pelo coordenador; NÃO inventados aqui.
-- Nada deste arquivo reproduz arranjo de produção (a tabela nasce vazia, 0 mapeamentos).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número reprovado por guarda desligada está no cabeçalho de Supabase/migrations/0272_o_mapeamento_de_colunas_que_cada_arquivo_redescobria.sql ("MEDIÇÃO NÃO-VAZIA").
-- `mc42.medindo = on` (PGOPTIONS='-c mc42.medindo=on') vira `raise warning` e CONTA (mc42.execucoes / mc42.falhas); sem a variável, o assert é `raise exception` (o CI).

\set ON_ERROR_STOP on

create or replace function teste_assert_0272(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('mc42.execucoes', (coalesce(nullif(current_setting('mc42.execucoes', true), ''), '0')::int + 1)::text, false);
  if p_ok then
    raise notice 'ok    %', p_nome;
  elsif current_setting('mc42.medindo', true) = 'on' then
    perform set_config('mc42.falhas', (coalesce(nullif(current_setting('mc42.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- 'ok|<json>' -> o json; qualquer outra coisa -> NULL (o assert que o usa reprova pela comparação, em vez de morrer num cast).
create or replace function teste_json_0272(p_res text) returns jsonb
language sql immutable as $$ select case when p_res like 'ok|{%' then substring(p_res from 4)::jsonb end $$;

-- Entra como `authenticated` (JWT do usuário; NULL = JWT SEM sub), chama a função, volta a superusuário com o JWT do Sócio padrão do run.sh.
-- Devolve 'ok|<jsonb>' ou '<sqlstate>|<mensagem>'.
create or replace function teste_conf_0272(p_uid uuid, p_cab jsonb, p_mapa jsonb, p_fmt jsonb, p_tipo text default 'contas_a_receber', p_papel text default 'authenticated')
returns text language plpgsql as $$
declare v_r jsonb; v_out text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '{"role":"authenticated"}'
                     else jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
  execute format('set local role %I', p_papel);
  begin
    -- SQL DINÂMICO de propósito: o plpgsql guarda o plano de uma expressão simples pela transação e NÃO reconfere o EXECUTE depois de um `set role`
    -- (medido: a 3ª chamada como anon passava). Com `execute` o privilégio é conferido a cada chamada, como a requisição de verdade.
    execute 'select fn_mapeamento_confirmar($1, $2, $3, $4)' into v_r using p_tipo, p_cab, p_mapa, p_fmt;
    v_out := 'ok|' || v_r::text;
  exception when others then
    v_out := sqlstate || '|' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  return v_out;
end $$;

create or replace function teste_vig_0272(p_uid uuid, p_tipo text, p_cab jsonb)
returns text language plpgsql as $$
declare v_r jsonb; v_out text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '{"role":"authenticated"}'
                     else jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
  execute 'set local role authenticated';
  begin
    execute 'select fn_mapeamento_vigente($1, $2)' into v_r using p_tipo, p_cab;   -- dinâmico: ver teste_conf_0272
    v_out := 'ok|' || coalesce(v_r::text, 'NULL');
  exception when others then
    v_out := sqlstate || '|' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  return v_out;
end $$;

-- Executa um comando COMO o papel (authenticated com o JWT do usuário) e devolve o SQLSTATE ('ok' se passou).
create or replace function teste_sql_0272(p_uid uuid, p_papel text, p_sql text) returns text
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

-- Limpeza de rodada anterior (o teste é reexecutável).
delete from mapeamento_de_colunas;
delete from evento_auditoria where acao = 'mapeamento_confirmado';
delete from auth.users where id in ('00000000-0000-0000-0000-00000272b001', '00000000-0000-0000-0000-00000272b002',
  '00000000-0000-0000-0000-00000272b003', '00000000-0000-0000-0000-00000272b004', '00000000-0000-0000-0000-00000272b005');

do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000272b001';
  u_ana   uuid := '00000000-0000-0000-0000-00000272b002';   -- Analista
  u_leo   uuid := '00000000-0000-0000-0000-00000272b003';   -- Leitura
  u_nil   uuid := '00000000-0000-0000-0000-00000272b004';   -- SEM papel
  u_ana2  uuid := '00000000-0000-0000-0000-00000272b005';   -- outra Analista
  v_cab   jsonb := '["Código","Cliente","CNPJ/CPF","Título","Parcela","Emissão","Vencimento","Valor Original","Valor Pago","Saldo","Data Pagamento","Situação"]';
  v_mapa  jsonb := '{"contraparte":1,"documento_contraparte":2,"titulo":3,"parcela":4,"emissao":5,"vencimento":6,"valor_original":7,"valor_pago":8,"saldo":9,"data_pagamento":10,"situacao":11}';
  v_fmt   jsonb := '{"decimal":"virgula","datas":"dia_mes_ano"}';
  v_min   jsonb := '{"contraparte":0,"vencimento":1,"saldo":2}';
  v_cab3  jsonb := '["Cliente","Vencimento","Saldo"]';
  v_res text; v_res2 text; v_n int; v_n2 int; v_id uuid; v_id2 uuid; v_ev int; v_imp text; v_r jsonb; v_t text;
begin
  insert into auth.users (id, email) values (u_socio, 'socio@0272.local'), (u_ana, 'ana@0272.local'), (u_leo, 'leo@0272.local'),
    (u_nil, 'nil@0272.local'), (u_ana2, 'ana2@0272.local');
  perform fn_definir_papel(u_socio, 'socio', 'teste 0272');
  perform fn_definir_papel(u_ana, 'analista');
  perform fn_definir_papel(u_leo, 'leitura');
  perform fn_definir_papel(u_ana2, 'analista');

  -- ------------------------------------------------------------------ 1. a impressão (vetores da biblioteca JS)
  raise notice '--- 1. a impressão do cabeçalho é a da biblioteca, calculada pelo banco ---';
  perform teste_assert_0272(fn_impressao_do_cabecalho(v_cab) = '85e6f43fb9eed49ea6cc1ed90cab717d711a18b54c14dee3c8a04a667795f72d',
    'a impressão do cabeçalho de 12 colunas é o vetor da biblioteca', fn_impressao_do_cabecalho(v_cab));
  perform teste_assert_0272(fn_impressao_do_cabecalho(jsonb_build_array('  Código ', 'Cli' || chr(160) || ' ente', '', '')) = 'b9b00f3fd09b66b137353b69ed211fabfb259bb78b10690a7266e2b6c004188f',
    'espaço nas pontas, NBSP (U+00A0) no meio, e células vazias do fim: o vetor da biblioteca', null);
  perform teste_assert_0272(fn_impressao_do_cabecalho(jsonb_build_array('A' || 'c' || U&'\0327' || 'a' || U&'\0303' || 'o'))
                            = fn_impressao_do_cabecalho(jsonb_build_array(normalize('A' || 'c' || U&'\0327' || 'a' || U&'\0303' || 'o', NFC))),
    '"Ação" em NFD tem a mesma impressão que em NFC', null);
  perform teste_assert_0272(fn_impressao_do_cabecalho('["Ação"]') = fn_impressao_do_cabecalho(jsonb_build_array('A' || 'c' || U&'\0327' || 'a' || U&'\0303' || 'o')),
    'e o NFC literal ("Ação" pré-composto) é o mesmo texto que o NFD decomposto', null);
  perform teste_assert_0272(fn_impressao_do_cabecalho('["Cliente","Saldo"]') = fn_impressao_do_cabecalho('["Cliente","Saldo","","   "]'),
    'células vazias (ou só espaço) do FIM não mudam a impressão', null);
  perform teste_assert_0272(fn_impressao_do_cabecalho('["Cliente","","Saldo"]') <> fn_impressao_do_cabecalho('["Cliente","Saldo"]'),
    'célula vazia no MEIO muda a impressão (a coluna existe)', null);
  perform teste_assert_0272(fn_impressao_do_cabecalho('["Cliente","Saldo"]') <> fn_impressao_do_cabecalho('["cliente","saldo"]'),
    'a caixa conta: a impressão não passa por minúsculas (lower() depende do LC_CTYPE)', null);
  perform teste_assert_0272(fn_impressao_do_cabecalho(jsonb_build_array('Valor' || chr(9) || chr(10) || chr(13) || ' Original')) = fn_impressao_do_cabecalho('["Valor Original"]'),
    'tab, quebra de linha e retorno entre palavras colapsam em um espaço', null);

  -- ------------------------------------------------------------------ 2. quem confirma
  raise notice '--- 2. quem confirma, COMO authenticated (e quem não) ---';
  v_res := teste_conf_0272(u_ana, v_cab, v_mapa, v_fmt);
  perform teste_assert_0272(v_res like 'ok|%', 'a Analista confirma o mapeamento (como authenticated)', v_res);
  perform teste_assert_0272((v_res like 'ok|%') and (teste_json_0272(v_res) ->> 'impressao') = '85e6f43fb9eed49ea6cc1ed90cab717d711a18b54c14dee3c8a04a667795f72d'
                            and (teste_json_0272(v_res) ->> 'id') is not null,
    'a função devolve o id e a impressão do vetor da biblioteca', v_res);
  perform teste_assert_0272((select count(*) from mapeamento_de_colunas where impressao = '85e6f43fb9eed49ea6cc1ed90cab717d711a18b54c14dee3c8a04a667795f72d'
                              and tipo_base = 'contas_a_receber' and confirmado_por = u_ana and confirmado_em is not null and substituido_em is null) = 1,
    'a linha gravada tem o autor (auth.uid() da Analista), a data e está vigente', null);
  v_res := teste_conf_0272(u_socio, v_cab3, v_min, v_fmt, 'contas_a_pagar');
  perform teste_assert_0272(v_res like 'ok|%', 'o Sócio confirma o mapeamento', v_res);

  select count(*) into v_n from mapeamento_de_colunas;
  v_res := teste_conf_0272(u_leo, '["Fornecedor","Vencimento","Saldo"]', v_min, v_fmt);
  perform teste_assert_0272(v_res like '42501|%', 'a Leitura NÃO confirma (42501)', v_res);
  v_res := teste_conf_0272(u_nil, '["Fornecedor","Vencimento","Saldo"]', v_min, v_fmt);
  perform teste_assert_0272(v_res like '42501|%', 'quem não tem papel NÃO confirma (42501)', v_res);
  v_res := teste_conf_0272(null, '["Fornecedor","Vencimento","Saldo"]', v_min, v_fmt);
  perform teste_assert_0272(v_res like '42501|%', 'authenticated com JWT SEM sub (anônimo) NÃO confirma (42501)', v_res);
  v_res := teste_conf_0272(u_ana, '["Fornecedor","Vencimento","Saldo"]', v_min, v_fmt, 'contas_a_pagar', 'anon');
  perform teste_assert_0272(v_res like '42501|%', 'o papel anon não tem EXECUTE (42501)', v_res);
  select count(*) into v_n2 from mapeamento_de_colunas;
  perform teste_assert_0272(v_n2 = v_n, 'as quatro recusas não gravaram nada', v_n || ' -> ' || v_n2);
  -- conexão de serviço (sem JWT e sem role authenticated): o autor é o auth.uid(), não há autor
  perform set_config('request.jwt.claims', '', true);
  begin
    perform fn_mapeamento_confirmar('contas_a_pagar', '["Fornecedor","Vencimento","Saldo"]', v_min, v_fmt);
    v_res := 'ok';
  exception when others then v_res := sqlstate; end;
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  perform teste_assert_0272(v_res = '42501', 'conexão de serviço (sem auth.uid()) NÃO confirma: mapeamento sem autor não vale', v_res);

  -- ------------------------------------------------------------------ 3. a validação recusa com o motivo
  raise notice '--- 3. cada guarda de validação recusa com o porquê e não grava ---';
  select count(*) into v_n from mapeamento_de_colunas;
  v_res := teste_conf_0272(u_ana, v_cab3, '{"vencimento":1,"saldo":2}', v_fmt);
  perform teste_assert_0272(v_res like '22023|%falta o campo obrigatório contraparte%', 'falta contraparte: recusa e diz o efeito', v_res);
  v_res := teste_conf_0272(u_ana, v_cab3, '{"contraparte":0,"saldo":2}', v_fmt);
  perform teste_assert_0272(v_res like '22023|%falta o campo obrigatório vencimento%o aging não pode ser calculado%', 'falta vencimento: recusa e diz "o aging não pode ser calculado"', v_res);
  v_res := teste_conf_0272(u_ana, v_cab3, '{"contraparte":0,"vencimento":1}', v_fmt);
  perform teste_assert_0272(v_res like '22023|%falta o campo obrigatório saldo%', 'falta saldo: recusa e diz o efeito', v_res);
  v_res := teste_conf_0272(u_ana, v_cab3, '{"contraparte":0,"vencimento":1,"saldo":3}', v_fmt);
  perform teste_assert_0272(v_res like '22023|%saldo: coluna 3 fora do cabeçalho (3 colunas)%', 'índice igual ao número de colunas: fora do cabeçalho (recusa)', v_res);
  v_res := teste_conf_0272(u_ana, v_cab3, '{"contraparte":0,"vencimento":1,"saldo":-1}', v_fmt);
  perform teste_assert_0272(v_res like '22023|%saldo: o índice da coluna tem de ser um inteiro a partir de 0%', 'índice negativo: recusa', v_res);
  v_res := teste_conf_0272(u_ana, v_cab3, '{"contraparte":0,"vencimento":1,"saldo":1.5}', v_fmt);
  perform teste_assert_0272(v_res like '22023|%saldo: o índice da coluna tem de ser um inteiro%', 'índice fracionário: recusa', v_res);
  v_res := teste_conf_0272(u_ana, v_cab3, '{"contraparte":0,"vencimento":1,"saldo":"2"}', v_fmt);
  perform teste_assert_0272(v_res like '22023|%saldo: o índice da coluna tem de ser um inteiro%', 'índice em texto ("2"): recusa', v_res);
  v_res := teste_conf_0272(u_ana, v_cab3, '{"contraparte":0,"vencimento":1,"saldo":1}', v_fmt);
  perform teste_assert_0272(v_res like '22023|%a coluna "Vencimento" está em saldo e em vencimento%', 'a mesma coluna em dois campos: recusa e diz a coluna e os campos', v_res);
  v_res := teste_conf_0272(u_ana, v_cab3, '{"contraparte":0,"vencimento":1,"saldo":2,"cor_do_cliente":0}', v_fmt);
  perform teste_assert_0272(v_res like '22023|%campo desconhecido: cor_do_cliente%', 'campo fora dos 11 válidos: recusa', v_res);
  v_res := teste_conf_0272(u_ana, v_cab3, '[0,1,2]', v_fmt);
  perform teste_assert_0272(v_res like '22023|%o mapa tem de ser um objeto%', 'mapa que não é objeto: recusa', v_res);
  v_res := teste_conf_0272(u_ana, v_cab3, v_min, v_fmt, 'contas_a_pagar_e_a_receber');
  perform teste_assert_0272(v_res like '22023|%tipo_base%não existe%', 'tipo_base fora da lista: recusa', v_res);
  v_res := teste_conf_0272(u_ana, '[]', v_min, v_fmt);
  perform teste_assert_0272(v_res like '22023|%o cabeçalho está vazio%', 'cabeçalho vazio: recusa', v_res);
  v_res := teste_conf_0272(u_ana, '["", "  "]', '{"contraparte":0,"vencimento":1,"saldo":1}', v_fmt);
  perform teste_assert_0272(v_res like '22023|%o cabeçalho está vazio%', 'cabeçalho só de células em branco: recusa (a impressão seria a do vazio)', v_res);
  v_res := teste_conf_0272(u_ana, '{"a":1}', v_min, v_fmt);
  perform teste_assert_0272(v_res like '22023|%o cabeçalho tem de ser uma lista%', 'cabeçalho que não é lista: recusa', v_res);
  select count(*) into v_n2 from mapeamento_de_colunas;
  perform teste_assert_0272(v_n2 = v_n, 'nenhuma das recusas de validação gravou', v_n || ' -> ' || v_n2);
  -- o índice é contra o cabeçalho ORIGINAL: coluna 3 existe no original (célula vazia no meio e uma coluna depois do fim útil)
  v_res := teste_conf_0272(u_ana, '["Cliente","Vencimento","Saldo","", "Obs", "", ""]', '{"contraparte":0,"vencimento":1,"saldo":2,"situacao":4}', v_fmt);
  perform teste_assert_0272(v_res like 'ok|%', 'o índice vale contra o cabeçalho ORIGINAL (coluna 4 de 7, com células vazias no meio e no fim)', v_res);
  v_res := teste_conf_0272(u_ana, '["Cliente","Vencimento","Saldo","", "Obs", "", ""]', '{"contraparte":0,"vencimento":1,"saldo":2,"situacao":6}', v_fmt);
  perform teste_assert_0272(v_res like 'ok|%', 'e uma coluna do FIM em branco ainda é índice válido do original (6 de 7): o analista pode apontá-la', v_res);

  -- ------------------------------------------------------------------ 4. o formato
  raise notice '--- 4. o formato é fechado: decimal e datas, sem default ---';
  select count(*) into v_n from mapeamento_de_colunas;
  v_res := teste_conf_0272(u_ana, v_cab3, v_min, null);
  perform teste_assert_0272(v_res like '22023|%o formato tem de ser um objeto%', 'sem formato (NULL): recusa', v_res);
  v_res := teste_conf_0272(u_ana, v_cab3, v_min, '{"datas":"dia_mes_ano"}');
  perform teste_assert_0272(v_res like '22023|%formato: falta a chave decimal%', 'formato sem decimal: recusa e explica "1.250"', v_res);
  v_res := teste_conf_0272(u_ana, v_cab3, v_min, '{"decimal":"virgula"}');
  perform teste_assert_0272(v_res like '22023|%formato: falta a chave datas%', 'formato sem datas: recusa e explica "03/04/2025"', v_res);
  v_res := teste_conf_0272(u_ana, v_cab3, v_min, '{"decimal":"virgula","datas":"dia_mes_ano","moeda":"BRL"}');
  perform teste_assert_0272(v_res like '22023|%formato: chave desconhecida "moeda"%', 'formato com chave a mais: recusa', v_res);
  v_res := teste_conf_0272(u_ana, v_cab3, v_min, '{"decimal":"virgola","datas":"dia_mes_ano"}');
  perform teste_assert_0272(v_res like '22023|%formato.decimal: "virgola" não está na lista (virgula, ponto)%', 'decimal fora da lista: recusa', v_res);
  v_res := teste_conf_0272(u_ana, v_cab3, v_min, '{"decimal":"virgula","datas":"ano_mes_dia"}');
  perform teste_assert_0272(v_res like '22023|%formato.datas: "ano_mes_dia" não está na lista (dia_mes_ano, mes_dia_ano)%', 'datas fora da lista: recusa', v_res);
  v_res := teste_conf_0272(u_ana, v_cab3, v_min, '{"decimal":1,"datas":true}');
  perform teste_assert_0272(v_res like '22023|%formato.decimal: 1 não está na lista%', 'valor que não é texto: recusa', v_res);
  v_res := teste_conf_0272(u_ana, v_cab3, v_min, '"virgula"');
  perform teste_assert_0272(v_res like '22023|%o formato tem de ser um objeto%', 'formato que não é objeto: recusa', v_res);
  select count(*) into v_n2 from mapeamento_de_colunas;
  perform teste_assert_0272(v_n2 = v_n, 'nenhuma recusa de formato gravou', v_n || ' -> ' || v_n2);
  v_res := teste_conf_0272(u_ana, '["Cliente","Vencimento","Saldo","Dt"]', v_min, '{"decimal":"ponto","datas":"mes_dia_ano"}');
  perform teste_assert_0272(v_res like 'ok|%', 'ponto + mes_dia_ano (o arquivo em formato americano) é aceito', v_res);
  v_r := fn_mapeamento_vigente('contas_a_receber', '["Cliente","Vencimento","Saldo","Dt"]');
  perform teste_assert_0272(v_r -> 'formato' = '{"decimal":"ponto","datas":"mes_dia_ano"}'::jsonb, 'a leitura devolve o formato confirmado', v_r::text);

  -- ------------------------------------------------------------------ 5. uma vigente só
  raise notice '--- 5. a nova confirmação substitui a anterior sem apagá-la; uma vigente por par ---';
  v_res := teste_conf_0272(u_ana, '["Sacado","Venc","Em aberto"]', '{"contraparte":0,"vencimento":1,"saldo":2}', v_fmt);
  v_id := (teste_json_0272(v_res) ->> 'id')::uuid;
  v_res2 := teste_conf_0272(u_ana2, '["Sacado","Venc","Em aberto"]', '{"contraparte":0,"vencimento":2,"saldo":1}', '{"decimal":"ponto","datas":"mes_dia_ano"}');
  v_id2 := (teste_json_0272(v_res2) ->> 'id')::uuid;
  perform teste_assert_0272(v_res2 like 'ok|%' and (teste_json_0272(v_res2) ->> 'substitui')::uuid = v_id, 'a segunda confirmação do par devolve o id da que substituiu', v_res2);
  select count(*) into v_n from mapeamento_de_colunas where tipo_base = 'contas_a_receber' and impressao = fn_impressao_do_cabecalho('["Sacado","Venc","Em aberto"]');
  select count(*) into v_n2 from mapeamento_de_colunas where tipo_base = 'contas_a_receber' and impressao = fn_impressao_do_cabecalho('["Sacado","Venc","Em aberto"]') and substituido_em is null;
  perform teste_assert_0272(v_n = 2, 'a confirmação anterior NÃO foi apagada (2 linhas do par)', v_n::text);
  perform teste_assert_0272(v_n2 = 1, 'só UMA linha do par está vigente', v_n2::text);
  perform teste_assert_0272((select substituido_por from mapeamento_de_colunas where id = v_id) = v_id2 and (select substituido_em from mapeamento_de_colunas where id = v_id) is not null
                            and (select substituido_em from mapeamento_de_colunas where id = v_id2) is null,
    'a anterior aponta para a nova (substituido_por) e tem a data; a nova está vigente', null);
  v_r := fn_mapeamento_vigente('contas_a_receber', '["Sacado","Venc","Em aberto"]');
  perform teste_assert_0272((v_r ->> 'id')::uuid = v_id2 and (v_r -> 'mapa' ->> 'vencimento') = '2' and (v_r ->> 'confirmado_por')::uuid = u_ana2,
    'a leitura devolve a confirmação MAIS NOVA (o mapa e o autor dela)', v_r::text);
  v_res := teste_conf_0272(u_ana, '["Sacado","Venc","Em aberto"]', '{"contraparte":0,"vencimento":1,"saldo":2}', v_fmt, 'contas_a_pagar');
  perform teste_assert_0272(v_res like 'ok|%' and (teste_json_0272(v_res) ->> 'substitui') is null, 'o MESMO cabeçalho em outro tipo_base é outro par: não substitui', v_res);
  perform teste_assert_0272((select count(*) from mapeamento_de_colunas where impressao = fn_impressao_do_cabecalho('["Sacado","Venc","Em aberto"]') and substituido_em is null) = 2,
    'e os dois tipo_base têm cada um a sua vigente', null);
  -- o banco garante, não só a função: nem o service_role (que ignora RLS e chama sem a função) grava a segunda vigente
  perform set_config('request.jwt.claims', '', true);
  set local role service_role;
  begin
    insert into mapeamento_de_colunas (tipo_base, impressao, cabecalho, mapa, formato, confirmado_por)
    values ('contas_a_receber', fn_impressao_do_cabecalho('["Sacado","Venc","Em aberto"]'), '["Sacado","Venc","Em aberto"]',
            '{"contraparte":0,"vencimento":1,"saldo":2}', v_fmt, u_ana);
    v_t := 'ok';
  exception when others then v_t := sqlstate; end;
  reset role;
  perform teste_assert_0272(v_t = '23505', 'o índice único parcial recusa a segunda vigente do par (23505), até para o service_role', v_t);
  set local role service_role;
  begin
    insert into mapeamento_de_colunas (tipo_base, impressao, cabecalho, mapa, formato, confirmado_por, substituido_em, substituido_por)
    values ('contas_a_receber', fn_impressao_do_cabecalho('["Sacado","Venc","Em aberto"]'), '["Sacado","Venc","Em aberto"]',
            '{"contraparte":0,"vencimento":1,"saldo":2}', v_fmt, u_ana, now(), v_id2);
    v_t := 'ok';
  exception when others then v_t := sqlstate; end;
  reset role;
  perform teste_assert_0272(v_t = 'ok', 'controle: uma linha JÁ substituída do mesmo par entra (o índice só conta as vigentes)', v_t);
  set local role service_role;
  begin
    insert into mapeamento_de_colunas (tipo_base, impressao, cabecalho, mapa, formato, confirmado_por)
    values ('contas_a_receber', fn_impressao_do_cabecalho('["X","Y","Z"]'), '["X","Y","Z"]', '{"contraparte":0,"vencimento":1}', v_fmt, u_ana);
    v_t := 'ok';
  exception when others then v_t := sqlstate; end;
  reset role;
  perform teste_assert_0272(v_t = '23514', 'a CHECK recusa mapa inválido (obrigatório faltando) mesmo escrito pelo service_role (23514)', v_t);
  set local role service_role;
  begin
    insert into mapeamento_de_colunas (tipo_base, impressao, cabecalho, mapa, formato, confirmado_por)
    values ('contas_a_receber', repeat('a', 64), '["X","Y","Z"]', '{"contraparte":0,"vencimento":1,"saldo":2}', v_fmt, u_ana);
    v_t := 'ok';
  exception when others then v_t := sqlstate; end;
  reset role;
  perform teste_assert_0272(v_t = '23514', 'a CHECK recusa impressão que o cabeçalho não produz, mesmo pelo service_role (a impressão é do banco)', v_t);
  set local role service_role;
  begin
    insert into mapeamento_de_colunas (tipo_base, impressao, cabecalho, mapa, formato, confirmado_por)
    values ('contas_a_receber', fn_impressao_do_cabecalho('["X","Y","Z"]'), '["X","Y","Z"]', '{"contraparte":0,"vencimento":1,"saldo":2}',
            '{"decimal":"virgula"}', u_ana);
    v_t := 'ok';
  exception when others then v_t := sqlstate; end;
  reset role;
  perform teste_assert_0272(v_t = '23514', 'a CHECK recusa formato incompleto, mesmo pelo service_role', v_t);
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);

  -- ------------------------------------------------------------------ 6. reaproveitar: o mesmo ERP, outro arquivo, outro mandato
  raise notice '--- 6. o mapeamento é reaproveitado pelo cabeçalho (NFD = NFC), por quem tem papel ---';
  v_res := teste_conf_0272(u_ana, jsonb_build_array('Ação', 'Vencimento', 'Saldo'), v_min, v_fmt);
  perform teste_assert_0272(v_res like 'ok|%', 'confirmado com "Ação" pré-composto (NFC)', v_res);
  v_res := teste_vig_0272(u_leo, 'contas_a_receber', jsonb_build_array('A' || 'c' || U&'\0327' || 'a' || U&'\0303' || 'o', 'Vencimento', 'Saldo'));
  perform teste_assert_0272(v_res like 'ok|{%' and (teste_json_0272(v_res) -> 'mapa' ->> 'saldo') = '2',
    'a Leitura lê o mapeamento confirmado, mesmo com o cabeçalho do arquivo novo em NFD', v_res);
  v_res := teste_vig_0272(u_ana, 'contas_a_receber', '["Ação ", "  Vencimento", "Saldo", "", ""]');
  perform teste_assert_0272(v_res like 'ok|{%', 'espaço nas pontas e colunas vazias do fim no arquivo novo não impedem de achar o mapeamento', v_res);
  v_res := teste_vig_0272(u_ana, 'contas_a_receber', '["Cabeçalho que ninguém confirmou", "Vencimento", "Saldo"]');
  perform teste_assert_0272(v_res = 'ok|NULL', 'cabeçalho nunca confirmado: NULL (ausência declarada), não erro e não mapa de palpite', v_res);
  v_res := teste_vig_0272(u_ana, 'contas_a_pagar', jsonb_build_array('Ação', 'Vencimento', 'Saldo'));
  perform teste_assert_0272(v_res = 'ok|NULL', 'o mapeamento de contas a receber não vale para contas a pagar (tipo_base é parte da chave)', v_res);
  v_res := teste_vig_0272(u_nil, 'contas_a_receber', jsonb_build_array('Ação', 'Vencimento', 'Saldo'));
  perform teste_assert_0272(v_res like '42501|%', 'quem não tem papel é recusado na leitura (não recebe NULL, que pareceria "ninguém confirmou")', v_res);
  v_res := teste_vig_0272(null, 'contas_a_receber', jsonb_build_array('Ação', 'Vencimento', 'Saldo'));
  perform teste_assert_0272(v_res like '42501|%', 'JWT sem sub também é recusado na leitura', v_res);
  perform set_config('request.jwt.claims', '', true);
  v_r := fn_mapeamento_vigente('contas_a_receber', jsonb_build_array('Ação', 'Vencimento', 'Saldo'));
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  perform teste_assert_0272(v_r is not null and (v_r ->> 'confirmado_por')::uuid = u_ana, 'a conexão de serviço (n8n) lê o mapeamento e o autor vem junto', v_r::text);

  -- ------------------------------------------------------------------ 7. escrita direta
  raise notice '--- 7. escrita direta pelo authenticated é negada (só a função escreve) ---';
  v_res := teste_sql_0272(u_socio, 'authenticated', format($q$insert into mapeamento_de_colunas (tipo_base, impressao, cabecalho, mapa, formato, confirmado_por)
    values ('contas_a_receber', %L, '["Cliente","Vencimento","Saldo"]', '{"contraparte":0,"vencimento":1,"saldo":2}', '{"decimal":"virgula","datas":"dia_mes_ano"}', %L)$q$,
    fn_impressao_do_cabecalho('["Cliente","Vencimento","Saldo"]'), u_socio));
  perform teste_assert_0272(v_res = '42501', 'nem o Sócio INSERE direto na tabela (42501)', v_res);
  v_res := teste_sql_0272(u_ana, 'authenticated', $q$update mapeamento_de_colunas set mapa = '{"contraparte":0,"vencimento":1,"saldo":2}'$q$);
  perform teste_assert_0272(v_res = '42501', 'a Analista não ATUALIZA direto o mapa de uma confirmação (42501)', v_res);
  v_res := teste_sql_0272(u_ana, 'authenticated', $q$delete from mapeamento_de_colunas$q$);
  perform teste_assert_0272(v_res = '42501', 'a Analista não APAGA direto (42501)', v_res);
  select count(*) into v_n from mapeamento_de_colunas;
  v_res := teste_sql_0272(u_leo, 'authenticated', 'select count(*) from mapeamento_de_colunas');
  perform teste_assert_0272(v_res = 'ok' and v_n > 0, 'a Leitura LÊ a tabela (policy de leitura por papel)', v_res);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', u_nil, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n2 from mapeamento_de_colunas;
  reset role;
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  perform teste_assert_0272(v_n2 = 0 and v_n > 0, 'quem não tem papel lê ZERO linhas da tabela, mesmo com linhas nela', v_n2 || ' de ' || v_n);

  -- ------------------------------------------------------------------ 8. a trilha
  raise notice '--- 8. a trilha: cada confirmação grava o evento com o autor; a recusada não ---';
  select count(*) into v_ev from evento_auditoria where acao = 'mapeamento_confirmado';
  v_res := teste_conf_0272(u_ana, '["Trilha","Vencimento","Saldo"]', '{"contraparte":0,"vencimento":1,"saldo":2}', v_fmt);
  v_id := (teste_json_0272(v_res) ->> 'id')::uuid;
  perform teste_assert_0272((select count(*) from evento_auditoria where acao = 'mapeamento_confirmado') = v_ev + 1, 'a confirmação grava UM evento mapeamento_confirmado', v_ev::text);
  perform teste_assert_0272(exists (select 1 from evento_auditoria where acao = 'mapeamento_confirmado' and entidade_ref = 'mapeamento_de_colunas:' || v_id
                                      and ator = 'usuario:' || u_ana and depois ->> 'impressao' = fn_impressao_do_cabecalho('["Trilha","Vencimento","Saldo"]')
                                      and depois -> 'formato' = v_fmt),
    'o evento tem a entidade, o autor (auth.uid() da Analista), a impressão e o formato', null);
  v_res := teste_conf_0272(u_leo, '["Trilha 2","Vencimento","Saldo"]', '{"contraparte":0,"vencimento":1,"saldo":2}', v_fmt);
  v_res2 := teste_conf_0272(u_ana, '["Trilha 2","Vencimento","Saldo"]', '{"contraparte":0,"vencimento":1}', v_fmt);
  perform teste_assert_0272((select count(*) from evento_auditoria where acao = 'mapeamento_confirmado') = v_ev + 1, 'a confirmação recusada (papel ou validação) não deixa evento', null);
  v_res := teste_conf_0272(u_ana2, '["Trilha","Vencimento","Saldo"]', '{"contraparte":0,"vencimento":1,"saldo":2}', v_fmt);
  perform teste_assert_0272(exists (select 1 from evento_auditoria where acao = 'mapeamento_confirmado' and antes ->> 'substituido' = v_id::text and ator = 'usuario:' || u_ana2),
    'a re-confirmação grava no evento QUAL confirmação substituiu', null);

  -- ------------------------------------------------------------------ 9. a sonda
  raise notice '--- 9. a sonda enxerga tudo o que a 0272 instala ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0272' and not presente;
  perform teste_assert_0272(v_n = 0, 'a sonda não acusa nenhum requisito da 0272 ausente', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0272';
  perform teste_assert_0272(v_n = 10, 'e o catálogo da 0272 tem os 10 requisitos', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where tipo in ('privilegio', 'sem_privilegio') and not presente;
  perform teste_assert_0272(v_n = 0, 'nenhum buraco de privilégio (a tabela e as funções novas têm o GRANT, e anon não tem nada)', v_n::text);

  -- limpeza
  delete from mapeamento_de_colunas;
  delete from evento_auditoria where acao = 'mapeamento_confirmado';
  delete from auth.users where id in (u_socio, u_ana, u_leo, u_nil, u_ana2);
  raise notice 'asserts executados: %; falhas medidas: %', current_setting('mc42.execucoes', true), coalesce(nullif(current_setting('mc42.falhas', true), ''), '0');
  raise notice 'TODOS OS TESTES DO MAPEAMENTO DE COLUNAS (0272) PASSARAM';
end $$;
