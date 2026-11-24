-- Testes da 0303: a base comum das fontes externas (fonte_externa, consulta_externa, fato_externo e fn_registrar_consulta_externa).
-- Rodar via Supabase/test/run.sh.
--
-- O QUE ESTE ARQUIVO PROVA (comportamento, regra 3): uma API derrubada (HTTP 503, timeout sem status, erro de leitura) grava "falhou" e NUNCA "nada_encontrado";
-- "falhou" não vira outra coisa por UPDATE (nem do superusuário); fonte fora do catálogo, CPF, fato em consulta sem achado e escrita direta pelo portal são
-- recusados; o usuário de OUTRO mandato não vê a consulta (a escrita e a leitura rodam COMO `authenticated`, a lição de
-- .claude/memory/rls-so-select-passa-no-superusuario.md).
--
-- DE ONDE VÊM OS DADOS (regra 4): esta tabela nasce vazia e nenhum chamador existe ainda (A3 e A4 vêm depois), então NÃO há bug de produção reproduzido aqui.
-- Os desfechos (503, timeout, 200 com itens, 200 vazio) são os que a CLASSIFICAÇÃO precisa distinguir, escritos à mão como a entrada da função; o que se afirma é a
-- classificação e as recusas do banco, não o formato de resposta de nenhuma API real. Os 22 nomes de fonte são os do plano (FASE_A_FONTES_PUBLICAS.md §5 A3 e A4).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número de asserts e o de reprovações por guarda desligada são medidos por outro passo e vão na mensagem do commit, não aqui.
-- `ct303.medindo = on` (PGOPTIONS='-c ct303.medindo=on') vira `raise warning` e CONTA (ct303.execucoes / ct303.falhas); sem a variável, o assert é `raise exception` (o CI).

\set ON_ERROR_STOP on

create or replace function teste_assert_0303(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('ct303.execucoes', (coalesce(nullif(current_setting('ct303.execucoes', true), ''), '0')::int + 1)::text, false);
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  elsif current_setting('ct303.medindo', true) = 'on' then
    perform set_config('ct303.falhas', (coalesce(nullif(current_setting('ct303.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- Executa um comando COMO o papel (com o JWT do usuário) e devolve 'ok' ou o SQLSTATE. Volta a superusuário com o JWT do Sócio padrão do run.sh.
create or replace function teste_sql_0303(p_uid uuid, p_papel text, p_sql text) returns text
language plpgsql as $$
declare v_out text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '{"role":"authenticated"}' else jsonb_build_object('sub', p_uid, 'role', p_papel)::text end, true);
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

-- Quantas linhas o usuário VÊ (leitura direta, pela policy). p_sql é um `select count(*) ...`.
create or replace function teste_n_0303(p_uid uuid, p_sql text) returns int
language plpgsql as $$
declare v_n int;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute p_sql into v_n;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  return v_n;
end $$;

-- Registra uma consulta COMO o usuário e devolve o jsonb do resultado, ou o SQLSTATE se a função recusou. A guarda é a da função, não a do papel de banco.
create or replace function teste_reg_0303(p_uid uuid, p_fonte text, p_caso uuid, p_cnpj text, p_status int, p_erro text, p_corpo text, p_itens jsonb,
  p_naoc text default null) returns text
language plpgsql as $$
declare v_r jsonb; v_out text;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    v_r := fn_registrar_consulta_externa(p_fonte, p_caso, p_cnpj, p_status, p_erro, p_corpo, p_itens, p_naoc);
    v_out := v_r::text;
  exception when others then
    v_out := sqlstate;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  return v_out;
end $$;

-- O resultado gravado (o que o banco decidiu) de um registro como Sócio padrão do run.sh (superusuário com o JWT do Sócio).
create or replace function teste_res_0303(p_fonte text, p_caso uuid, p_cnpj text, p_status int, p_erro text, p_corpo text, p_itens jsonb, p_naoc text default null) returns text
language plpgsql as $$
begin
  return fn_registrar_consulta_externa(p_fonte, p_caso, p_cnpj, p_status, p_erro, p_corpo, p_itens, p_naoc) ->> 'resultado';
exception when others then
  return sqlstate;
end $$;

-- Insere direto na tabela (como o service_role/superusuário: sem passar pela função) e devolve 'ok' ou o SQLSTATE. Quem chama desfaz o que entrou.
create or replace function teste_ins_0303(p_fonte text, p_caso uuid, p_cnpj text, p_res text, p_status int, p_motivo text, p_hash text default null) returns text
language plpgsql as $$
begin
  insert into consulta_externa (fonte, caso_id, alvo_cnpj, fornecedor, base_legal, http_status, hash_bruto, motivo, resultado)
  values (p_fonte, p_caso, p_cnpj, 'teste', 'dado_publico', p_status, p_hash, p_motivo, p_res);
  return 'ok';
exception when others then
  return sqlstate;
end $$;

delete from consulta_externa;

do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-0000000e0301';
  u_ana   uuid := '00000000-0000-0000-0000-0000000e0302';  -- analista alocada em A
  u_leo   uuid := '00000000-0000-0000-0000-0000000e0303';  -- leitura em A
  u_xan   uuid := '00000000-0000-0000-0000-0000000e0304';  -- analista alocada só em B
  u_nil   uuid := '00000000-0000-0000-0000-0000000e0305';  -- sem papel
  c_ok    text := '11222333000181';
  v_a uuid; v_b uuid;
  v_r text; v_j jsonb; v_id uuid; v_n int; v_n2 int; v_t text; v_s int; v_hash text;
  v_status int[] := array[301, 400, 401, 404, 429, 500, 503];
  v_corpo text := '{"razao_social":"ACME LTDA","cnae":"4711-3/02"}';
  v_itens jsonb := '[{"chave":"razao_social","valor":"ACME LTDA","referencia":"$.razao_social"},{"chave":"cnae_principal","valor":"4711-3/02"}]';
begin
  insert into auth.users (id, email) values (u_socio, 'socio@0303.local'), (u_ana, 'ana@0303.local'), (u_leo, 'leo@0303.local'),
    (u_xan, 'xan@0303.local'), (u_nil, 'nil@0303.local');
  perform fn_definir_papel(u_socio, 'socio', 'teste 0303');
  perform fn_definir_papel(u_ana, 'analista');
  perform fn_definir_papel(u_leo, 'leitura');
  perform fn_definir_papel(u_xan, 'analista');
  v_a := fn_upsert_caso('0303 — mandato A');
  v_b := fn_upsert_caso('0303 — mandato B');
  perform fn_alocar(v_a, u_ana);
  perform fn_alocar(v_a, u_leo);
  perform fn_alocar(v_b, u_xan);

  -- ------------------------------------------------------------------ 1. O CATÁLOGO
  raise notice '--- 1. o catálogo tem as 22 fontes da A3 e da A4 (e a BrasilAPI é não oficial) ---';
  select count(*) into v_n from fonte_externa;
  perform teste_assert_0303(v_n = 22, 'o catálogo tem 22 fontes', v_n::text);
  select count(*) filter (where tipo = 'mercado'), count(*) filter (where tipo = 'empresa') into v_n, v_n2 from fonte_externa;
  perform teste_assert_0303(v_n = 15 and v_n2 = 7, '15 de mercado e 7 de empresa', v_n || '/' || v_n2);
  select count(*) into v_n from unnest(array['bcb_sgs', 'bcb_focus', 'bcb_juros_modalidade', 'ibge_sidra', 'cvm_dados_abertos', 'anbima_curva', 'ipeadata', 'comex_stat', 'caged', 'aneel',
    'ccee', 'antt', 'anp', 'susep', 'fipezap', 'brasilapi_cnpj', 'cgu_ceis', 'cgu_cnep', 'mte_trabalho_escravo', 'ibama_autos', 'ibama_embargos', 'pgfn_divida_ativa']) k
   where exists (select 1 from fonte_externa f where f.chave = k);
  perform teste_assert_0303(v_n = 22, 'as 22 fontes nomeadas pelo plano estão todas no catálogo (pelo nome, não pela contagem)', v_n::text);
  perform teste_assert_0303((select not oficial from fonte_externa where chave = 'brasilapi_cnpj') and (select tipo from fonte_externa where chave = 'brasilapi_cnpj') = 'empresa',
    'a BrasilAPI é fonte de empresa e NÃO oficial (decisão 2 do dono, 24/11/2026)');
  perform teste_assert_0303((select oficial from fonte_externa where chave = 'bcb_sgs') and (select oficial from fonte_externa where chave = 'cgu_ceis'),
    'BCB e CGU são oficiais');
  select count(*) into v_n from fonte_externa where validade_dias is not null or http_inexistente is not null;
  perform teste_assert_0303(v_n = 0, 'nenhuma validade nem status "não existe" inventados no seed (ausência é nulo, não palpite)', v_n::text);

  -- ------------------------------------------------------------------ 2. A API DERRUBADA GRAVA "FALHOU"
  raise notice '--- 2. API derrubada: falhou, nunca nada_encontrado ---';
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, 503, null, '<html>Service Unavailable</html>', null);
  perform teste_assert_0303(v_r = 'falhou', 'HTTP 503 (API derrubada) grava falhou', v_r);
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, null, 'timeout após 30 s', null, null);
  perform teste_assert_0303(v_r = 'falhou', 'timeout (sem status HTTP, com o erro) grava falhou', v_r);
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, null, null, null, null);
  perform teste_assert_0303(v_r = 'falhou', 'sem status e sem erro (conexão que nem respondeu) grava falhou, não "nada"', v_r);
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, 200, 'JSON inválido: Unexpected token <', '<html>', null);
  perform teste_assert_0303(v_r = 'falhou', 'HTTP 200 com o erro de leitura do corpo grava falhou (o chamador não conseguiu ler)', v_r);
  v_n := 0;
  foreach v_s in array v_status loop
    v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, v_s, null, null, '[]'::jsonb);
    if v_r = 'falhou' then v_n := v_n + 1; end if;
  end loop;
  perform teste_assert_0303(v_n = array_length(v_status, 1), 'os status 301, 400, 401, 404, 429, 500 e 503 gravam falhou (o 404 também: nenhuma fonte documentou o "não existe")', v_n::text);
  select count(*) into v_n from consulta_externa where fonte = 'brasilapi_cnpj' and resultado = 'nada_encontrado';
  perform teste_assert_0303(v_n = 0, 'depois de todas as falhas, nenhuma consulta da BrasilAPI está como nada_encontrado', v_n::text);
  select count(*) into v_n from consulta_externa where fonte = 'brasilapi_cnpj' and resultado = 'falhou' and length(btrim(motivo)) > 0;
  perform teste_assert_0303(v_n = 11, 'as 11 falhas (4 + 7) guardam o motivo', v_n::text);
  perform teste_assert_0303((select bool_and(motivo like '%503%') from consulta_externa where fonte = 'brasilapi_cnpj' and http_status = 503),
    'o motivo de um 503 diz o status');
  perform teste_assert_0303(exists (select 1 from consulta_externa where fonte = 'brasilapi_cnpj' and http_status is null and motivo = 'timeout após 30 s'),
    'o motivo de um timeout é o erro que o chamador viu');

  -- ------------------------------------------------------------------ 3. OS OUTROS DESFECHOS
  raise notice '--- 3. a classificação do que deu certo, e o que a função recusa em vez de adivinhar ---';
  v_r := teste_res_0303('cgu_ceis', v_a, c_ok, 200, null, '[]', '[]'::jsonb);
  perform teste_assert_0303(v_r = 'nada_encontrado', 'HTTP 200 com lista vazia grava nada_encontrado', v_r);
  v_r := teste_res_0303('cgu_cnep', v_a, c_ok, 204, null, '', '[]'::jsonb);
  perform teste_assert_0303(v_r = 'nada_encontrado', 'HTTP 204 com lista vazia grava nada_encontrado', v_r);
  v_j := fn_registrar_consulta_externa('brasilapi_cnpj', v_a, c_ok, 200, null, v_corpo, v_itens);
  perform teste_assert_0303(v_j ->> 'resultado' = 'encontrado' and (v_j ->> 'fatos')::int = 2, 'HTTP 200 com 2 itens grava encontrado e 2 fatos', v_j::text);
  v_id := (v_j ->> 'id')::uuid;
  select count(*) into v_n from fato_externo where consulta_id = v_id and chave in ('razao_social', 'cnae_principal');
  perform teste_assert_0303(v_n = 2, 'os 2 fatos estão ligados à consulta que os trouxe');
  select hash_bruto into v_hash from consulta_externa where id = v_id;
  perform teste_assert_0303(v_hash = encode(sha256(convert_to(v_corpo, 'UTF8')), 'hex'), 'o hash do bruto é o sha256 do texto exato do corpo');
  perform teste_assert_0303((select fornecedor from consulta_externa where id = v_id) = 'BrasilAPI' and (select base_legal from consulta_externa where id = v_id) = 'dado_publico'
    and (select custo from consulta_externa where id = v_id) = 0 and (select validade_em from consulta_externa where id = v_id) is null,
    'fornecedor e base legal vêm do catálogo, o custo é zero e a validade é nula (a fonte não tem prazo decidido)');
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, 200, null, '{}', null);
  perform teste_assert_0303(v_r = '22023', 'HTTP 200 SEM a lista de itens é recusado (22023): "não li" não vira "vazio"', v_r);
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, 200, null, '{}', '{"a":1}'::jsonb);
  perform teste_assert_0303(v_r = '22023', 'itens que não é uma lista é recusado', v_r);
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, 200, null, '{}', '[{"chave":"x"}]'::jsonb);
  perform teste_assert_0303(v_r = '22023', 'item sem valor não é fato: recusado', v_r);
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, 200, null, '{}', '[{"chave":"x","valor":null}]'::jsonb);
  perform teste_assert_0303(v_r = '22023', 'item com valor JSON null não é fato: recusado', v_r);
  -- nao_consultado
  v_r := teste_res_0303('pgfn_divida_ativa', v_a, c_ok, null, null, null, null, 'fonte por CNPJ ainda não achada: a dívida ativa da empresa é DESCONHECIDA');
  perform teste_assert_0303(v_r = 'nao_consultado', 'o motivo de não consultar grava nao_consultado', v_r);
  v_r := teste_res_0303('pgfn_divida_ativa', v_a, c_ok, null, null, null, null, '   ');
  perform teste_assert_0303(v_r = '22023', 'nao_consultado sem motivo (só espaços) é recusado: ausência sem a causa não se registra', v_r);
  v_r := teste_res_0303('pgfn_divida_ativa', v_a, c_ok, 200, null, null, '[]'::jsonb, 'não consultei');
  perform teste_assert_0303(v_r = '22023', 'nao_consultado com status e itens (uma resposta) é contraditório: recusado', v_r);
  perform teste_assert_0303((select http_status from consulta_externa where fonte = 'pgfn_divida_ativa' and resultado = 'nao_consultado') is null,
    'nao_consultado fica sem status HTTP');
  -- o "não existe" documentado pela fonte (só ele vira nada_encontrado)
  update fonte_externa set http_inexistente = 404 where chave = 'brasilapi_cnpj';
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, 404, null, '{"message":"CNPJ não encontrado"}', null);
  perform teste_assert_0303(v_r = 'nada_encontrado', 'o 404 que a fonte DOCUMENTA como "não existe" grava nada_encontrado', v_r);
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, 503, null, null, null);
  perform teste_assert_0303(v_r = 'falhou', 'mesmo com o 404 documentado, o 503 continua falhou', v_r);
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, 410, null, null, null);
  perform teste_assert_0303(v_r = 'falhou', 'e outro 4xx que a fonte não documentou continua falhou', v_r);
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, 404, null, null, '[{"chave":"x","valor":1}]'::jsonb);
  perform teste_assert_0303(v_r = '22023', 'o "não existe" documentado vindo com itens é resposta contraditória: recusado', v_r);
  update fonte_externa set http_inexistente = null where chave = 'brasilapi_cnpj';
  -- a validade vem do catálogo quando ele a tem
  update fonte_externa set validade_dias = 90 where chave = 'cgu_ceis';
  v_j := fn_registrar_consulta_externa('cgu_ceis', v_a, c_ok, 200, null, '[]', '[]'::jsonb, null, 0, '2026-11-24 12:00:00+00');
  perform teste_assert_0303((select validade_em from consulta_externa where id = (v_j ->> 'id')::uuid) = '2026-11-24 12:00:00+00'::timestamptz + interval '90 days',
    'a validade da consulta é a data mais o prazo do catálogo (quando o catálogo o tem)');
  update fonte_externa set validade_dias = null where chave = 'cgu_ceis';
  -- mercado: sem mandato, sem alvo
  v_j := fn_registrar_consulta_externa('bcb_sgs', null, null, 200, null, '[{"data":"01/10/2026","valor":"0.50"}]', '[{"chave":"ipca_2026_10","valor":0.50}]'::jsonb);
  perform teste_assert_0303(v_j ->> 'resultado' = 'encontrado' and (select caso_id is null and alvo_cnpj is null from consulta_externa where id = (v_j ->> 'id')::uuid),
    'consulta de mercado grava sem mandato e sem alvo');
  v_r := teste_res_0303('bcb_sgs', null, null, 503, null, null, null);
  perform teste_assert_0303(v_r = 'falhou', 'e uma série de mercado com a API derrubada também grava falhou', v_r);

  -- ------------------------------------------------------------------ 4. "FALHOU" É IMUTÁVEL
  raise notice '--- 4. falhou não vira nada_encontrado: a consulta e o fato são imutáveis ---';
  select id into v_id from consulta_externa where fonte = 'brasilapi_cnpj' and http_status = 503 limit 1;
  v_t := null;
  begin update consulta_externa set resultado = 'nada_encontrado' where id = v_id;
  exception when others then v_t := sqlstate; end;
  perform teste_assert_0303(v_t = '23001', 'UPDATE falhou -> nada_encontrado é recusado (23001), até para o superusuário', v_t);
  perform teste_assert_0303((select resultado from consulta_externa where id = v_id) = 'falhou', 'e a linha continua falhou depois da tentativa');
  v_t := null;
  begin update consulta_externa set motivo = 'ok', http_status = 200 where id = v_id;
  exception when others then v_t := sqlstate; end;
  perform teste_assert_0303(v_t = '23001', 'nem o motivo nem o status de uma consulta se reescrevem', v_t);
  perform teste_assert_0303(teste_sql_0303(u_ana, 'service_role', format('update consulta_externa set resultado = ''nada_encontrado'' where id = %L', v_id)) = '23001',
    'o service_role também não consegue: a imutabilidade não depende do papel');
  perform teste_assert_0303(teste_sql_0303(u_ana, 'authenticated', format('update consulta_externa set resultado = ''nada_encontrado'' where id = %L', v_id)) = '42501',
    'e o authenticated (o portal) nem tem o privilégio (42501)');
  perform teste_assert_0303(teste_sql_0303(u_ana, 'authenticated', format('delete from consulta_externa where id = %L', v_id)) = '42501',
    'o authenticated não apaga consulta: a falha não some');
  select id into v_id from fato_externo limit 1;
  v_t := null;
  begin update fato_externo set valor = '"outro"'::jsonb where id = v_id;
  exception when others then v_t := sqlstate; end;
  perform teste_assert_0303(v_t = '23001', 'o dado achado (fato_externo) também é imutável', v_t);

  -- ------------------------------------------------------------------ 5. O QUE O BANCO RECUSA, MESMO PARA QUEM ESCREVE DIRETO
  raise notice '--- 5. fonte fora do catálogo, CPF, status incoerente, falha sem motivo, fato em consulta sem achado ---';
  v_r := teste_res_0303('fonte_inventada', v_a, c_ok, 200, null, '[]', '[]'::jsonb);
  perform teste_assert_0303(v_r = '23503', 'fonte fora do catálogo é recusada pela função (23503)', v_r);
  perform teste_assert_0303(teste_ins_0303('fonte_inventada', v_a, c_ok, 'falhou', 503, 'x') = '23503', 'e pela escrita direta (gatilho/FK, 23503)');
  v_r := teste_res_0303('brasilapi_cnpj', v_a, '12345678909', 200, null, '{}', '[]'::jsonb);
  perform teste_assert_0303(v_r = '23514', 'CPF (11 dígitos) é recusado pela função (23514): só CNPJ', v_r);
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, '12345678909', 'falhou', 503, 'x') = '23514', 'CPF é recusado também na escrita direta (CHECK)');
  perform teste_assert_0303(teste_res_0303('brasilapi_cnpj', v_a, '123.456.789-09', 200, null, '{}', '[]'::jsonb) = '23514', 'CPF com máscara é recusado');
  perform teste_assert_0303(teste_res_0303('brasilapi_cnpj', v_a, '11.222.333/0001-81', 200, null, '{}', '[]'::jsonb) = '23514', 'CNPJ com máscara também (quem chama normaliza para 14 dígitos)');
  perform teste_assert_0303(teste_res_0303('brasilapi_cnpj', v_a, '1122233300018', 200, null, '{}', '[]'::jsonb) = '23514', 'CNPJ de 13 dígitos é recusado');
  perform teste_assert_0303(teste_res_0303('brasilapi_cnpj', v_a, null, 200, null, '{}', '[]'::jsonb) = '23514', 'fonte de empresa sem CNPJ é recusada');
  perform teste_assert_0303(teste_res_0303('brasilapi_cnpj', null, c_ok, 200, null, '{}', '[]'::jsonb) = '42501', 'fonte de empresa sem mandato é recusada (a guarda de escrita do mandato)');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', null, c_ok, 'falhou', 503, 'x') = '23514', 'e na escrita direta (gatilho)');
  perform teste_assert_0303(teste_res_0303('bcb_sgs', v_a, null, 200, null, '{}', '[]'::jsonb) = '23514', 'fonte de mercado com mandato é recusada (não carrega dado de cliente)');
  perform teste_assert_0303(teste_res_0303('bcb_sgs', null, c_ok, 200, null, '{}', '[]'::jsonb) = '23514', 'fonte de mercado com CNPJ é recusada');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'falhou', 503, null) = '23514', 'falhou sem motivo é recusado (CHECK)');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'falhou', 503, '   ') = '23514', 'falhou com motivo só de espaços é recusado');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'nao_consultado', null, null) = '23514', 'nao_consultado sem motivo é recusado');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'nada_encontrado', 503, null) = '23514', 'nada_encontrado com HTTP 503 é recusado: a escrita direta não fabrica "nada" de uma falha');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'nada_encontrado', null, null) = '23514', 'nada_encontrado sem status é recusado');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'nada_encontrado', 404, null) = '23514', 'nada_encontrado com 404 que a fonte NÃO documenta é recusado (o gatilho confere com a fonte)');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'nada_encontrado', 200, null) = 'ok', 'controle positivo: nada_encontrado com HTTP 200 passa');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'encontrado', 200, null, null) = '23514', 'encontrado sem hash do bruto é recusado');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'encontrado', 503, null, repeat('a', 64)) = '23514', 'encontrado com HTTP 503 é recusado');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'falhou', 503, 'x', 'abc') = '23514', 'hash que não é sha256 (64 hex) é recusado');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'sei_la', 200, 'x') = '23514', 'resultado fora dos quatro estados é recusado');
  -- encontrado sem nenhum fato: recusado ao fim da transação (o gatilho deferido; aqui forçado a conferir já)
  v_t := null;
  begin
    insert into consulta_externa (id, fonte, caso_id, alvo_cnpj, fornecedor, base_legal, http_status, hash_bruto, resultado)
    values (gen_random_uuid(), 'brasilapi_cnpj', v_a, c_ok, 'teste', 'dado_publico', 200, repeat('b', 64), 'encontrado');
    set constraints trg_consulta_externa_com_fato immediate;
  exception when others then v_t := sqlstate; end;
  perform teste_assert_0303(v_t = '23514', 'encontrado SEM nenhum fato é recusado (a ausência não se apresenta como dado)', v_t);
  -- o fato só existe em consulta encontrado
  select id into v_id from consulta_externa where fonte = 'cgu_ceis' and resultado = 'nada_encontrado' limit 1;
  v_t := null;
  begin insert into fato_externo (consulta_id, chave, valor) values (v_id, 'sancao', '"sim"'::jsonb);
  exception when others then v_t := sqlstate; end;
  perform teste_assert_0303(v_t = '23514', 'fato em consulta nada_encontrado é recusado', v_t);
  select id into v_id from consulta_externa where fonte = 'brasilapi_cnpj' and resultado = 'falhou' limit 1;
  v_t := null;
  begin insert into fato_externo (consulta_id, chave, valor) values (v_id, 'razao_social', '"ACME"'::jsonb);
  exception when others then v_t := sqlstate; end;
  perform teste_assert_0303(v_t = '23514', 'fato em consulta falhou é recusado', v_t);
  select id into v_id from consulta_externa where fonte = 'pgfn_divida_ativa' and resultado = 'nao_consultado' limit 1;
  v_t := null;
  begin insert into fato_externo (consulta_id, chave, valor) values (v_id, 'divida', '1'::jsonb);
  exception when others then v_t := sqlstate; end;
  perform teste_assert_0303(v_t = '23514', 'fato em consulta nao_consultado é recusado', v_t);
  select id into v_id from consulta_externa where fonte = 'brasilapi_cnpj' and resultado = 'encontrado' limit 1;
  v_t := null;
  begin insert into fato_externo (consulta_id, chave, valor) values (v_id, 'situacao', '"ATIVA"'::jsonb);
  exception when others then v_t := sqlstate; end;
  perform teste_assert_0303(v_t is null, 'controle positivo: fato em consulta encontrado entra');
  v_t := null;
  begin insert into fato_externo (consulta_id, chave, valor) values (v_id, 'situacao2', 'null'::jsonb);
  exception when others then v_t := sqlstate; end;
  perform teste_assert_0303(v_t = '23514', 'fato com valor JSON null é recusado (ausência não é fato)', v_t);

  -- ------------------------------------------------------------------ 6. QUEM ESCREVE E QUEM LÊ (COMO authenticated)
  raise notice '--- 6. RLS por mandato e a escrita só pela função ---';
  select count(*) into v_n from consulta_externa where caso_id = v_a;
  perform teste_assert_0303(v_n >= 10, 'há consultas do mandato A para o assert de visibilidade não correr sobre o vazio', v_n::text);
  perform teste_assert_0303(teste_n_0303(u_socio, format('select count(*) from consulta_externa where caso_id = %L', v_a)) = v_n, 'o Sócio lê todas as consultas de A');
  perform teste_assert_0303(teste_n_0303(u_ana, format('select count(*) from consulta_externa where caso_id = %L', v_a)) = v_n, 'a Analista alocada em A lê as consultas de A');
  perform teste_assert_0303(teste_n_0303(u_leo, format('select count(*) from consulta_externa where caso_id = %L', v_a)) = v_n, 'a Leitura de A lê as consultas de A');
  perform teste_assert_0303(teste_n_0303(u_xan, format('select count(*) from consulta_externa where caso_id = %L', v_a)) = 0, 'o usuário de OUTRO mandato (Analista só de B) NÃO vê a consulta de A');
  perform teste_assert_0303(teste_n_0303(u_nil, format('select count(*) from consulta_externa where caso_id = %L', v_a)) = 0, 'quem não tem papel não vê a consulta de A');
  select count(*) into v_n2 from fato_externo f join consulta_externa c on c.id = f.consulta_id where c.caso_id = v_a;
  perform teste_assert_0303(v_n2 >= 3 and teste_n_0303(u_ana, format('select count(*) from fato_externo f join consulta_externa c on c.id = f.consulta_id where c.caso_id = %L', v_a)) = v_n2,
    'a Analista de A lê os fatos de A', v_n2::text);
  perform teste_assert_0303(teste_n_0303(u_xan, 'select count(*) from fato_externo') = (select count(*) from fato_externo f join consulta_externa c on c.id = f.consulta_id where c.caso_id is null),
    'o usuário de B não vê NENHUM fato de A (só os da consulta de mercado, que é da equipe)');
  perform teste_assert_0303(teste_n_0303(u_xan, 'select count(*) from consulta_externa where caso_id is null') = (select count(*) from consulta_externa where caso_id is null)
    and (select count(*) from consulta_externa where caso_id is null) >= 2, 'a consulta de MERCADO (sem mandato) é lida por quem tem papel');
  perform teste_assert_0303(teste_n_0303(u_nil, 'select count(*) from consulta_externa') = 0, 'quem não tem papel não lê nem a consulta de mercado');
  perform teste_assert_0303(teste_n_0303(u_xan, 'select count(*) from fonte_externa') = 22 and teste_n_0303(u_nil, 'select count(*) from fonte_externa') = 0,
    'o catálogo é legível pela equipe (22) e por quem não tem papel, nada');
  -- a escrita: só pela função, e a função é quem guarda
  perform teste_assert_0303(teste_sql_0303(u_ana, 'authenticated', format('insert into consulta_externa (fonte, caso_id, alvo_cnpj, fornecedor, base_legal, resultado, motivo) values (''brasilapi_cnpj'', %L, %L, ''x'', ''dado_publico'', ''falhou'', ''x'')', v_a, c_ok)) = '42501',
    'a Analista de A NÃO insere direto na consulta (42501): o portal só passa pela função, que classifica');
  perform teste_assert_0303(teste_sql_0303(u_socio, 'authenticated', format('insert into fato_externo (consulta_id, chave, valor) values (%L, ''x'', ''1''::jsonb)', v_id)) = '42501',
    'nem o Sócio insere fato direto');
  perform teste_assert_0303(teste_sql_0303(u_socio, 'authenticated', 'update fonte_externa set oficial = true') = '42501', 'nem altera o catálogo');
  v_r := teste_reg_0303(u_ana, 'brasilapi_cnpj', v_a, c_ok, 503, null, null, null);
  perform teste_assert_0303((v_r::jsonb) ->> 'resultado' = 'falhou', 'controle positivo: a Analista de A registra pela função (503 -> falhou)', v_r);
  v_r := teste_reg_0303(u_ana, 'brasilapi_cnpj', v_b, c_ok, 503, null, null, null);
  perform teste_assert_0303(v_r = '42501', 'a Analista de A não registra consulta no mandato B (42501)', v_r);
  v_r := teste_reg_0303(u_leo, 'brasilapi_cnpj', v_a, c_ok, 503, null, null, null);
  perform teste_assert_0303(v_r = '42501', 'a Leitura não registra consulta nem no mandato dela (42501)', v_r);
  v_r := teste_reg_0303(u_nil, 'brasilapi_cnpj', v_a, c_ok, 503, null, null, null);
  perform teste_assert_0303(v_r = '42501', 'quem não tem papel não registra (42501)', v_r);
  v_r := teste_reg_0303(u_ana, 'bcb_sgs', null, null, 503, null, null, null);
  perform teste_assert_0303(v_r = '42501', 'a fonte de mercado é do Sócio: a Analista não registra (42501)', v_r);
  v_r := teste_reg_0303(u_socio, 'bcb_sgs', null, null, 503, null, null, null);
  perform teste_assert_0303((v_r::jsonb) ->> 'resultado' = 'falhou', 'e o Sócio registra a de mercado', v_r);
  perform teste_assert_0303(teste_sql_0303(null, 'anon', format('select fn_registrar_consulta_externa(''bcb_sgs'', null, null, 503, null, null, null)')) = '42501',
    'o anon não executa a função de registro (42501)');
  perform teste_assert_0303(teste_sql_0303(null, 'anon', 'select count(*) from consulta_externa') = '42501', 'o anon não lê a consulta (42501)');

  -- ------------------------------------------------------------------ 7. A SONDA
  raise notice '--- 7. a sonda enxerga tudo o que a 0303 instala ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0303' and not presente;
  perform teste_assert_0303(v_n = 0, 'a sonda enxerga os 25 requisitos da 0303 (zero ausentes)', (select string_agg(chave || ': ' || coalesce(detalhe, ''), ' | ') from fn_instalacao_conferir() where migration = '0303' and not presente));
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0303';
  perform teste_assert_0303(v_n = 25, 'e o catálogo da 0303 tem 25 requisitos (não está vazio nem encolheu)', v_n::text);

  -- DEVOLVE O ESTADO: as consultas e os mandatos de teste saem (a cascata do mandato leva o resto), e os usuários de teste também.
  delete from consulta_externa;
  delete from caso where nome like '0303 —%';
  delete from auth.users where id in (u_socio, u_ana, u_leo, u_xan, u_nil);

  raise notice 'EXECUCOES=% FALHAS=%', current_setting('ct303.execucoes', true), coalesce(current_setting('ct303.falhas', true), '0');
  if current_setting('ct303.medindo', true) is distinct from 'on' then
    raise notice 'TODOS OS TESTES DA 0303 PASSARAM';
  end if;
end $$;
