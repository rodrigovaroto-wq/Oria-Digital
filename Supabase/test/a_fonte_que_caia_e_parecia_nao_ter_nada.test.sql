-- Testes da 0303: a base comum das fontes externas (fonte_externa, consulta_externa, fato_externo e fn_registrar_consulta_externa).
-- Rodar via Supabase/test/run.sh.
--
-- O QUE ESTE ARQUIVO PROVA (comportamento, regra 3): uma API derrubada (HTTP 503, timeout sem status, erro de leitura) grava "falhou" e NUNCA "nada_encontrado";
-- "falhou" não vira outra coisa por UPDATE (nem do superusuário em sessão normal; em modo replica ele passa por cima, e é o que a limpeza usa); fonte fora do catálogo, CPF, fato em consulta sem achado e escrita direta pelo portal são
-- recusados; o usuário de OUTRO mandato não vê a consulta (a escrita e a leitura rodam COMO `authenticated`, a lição de
-- .claude/memory/rls-so-select-passa-no-superusuario.md). Também: toda fonte tem prazo (decisão 8), "nada" exige prova de leitura e, em fonte de lista, registros lidos > 0,
-- a data é do banco, custo é explícito, nem UPDATE nem DELETE apagam uma falha, o caminho do SERVIÇO (sem JWT, role service_role, como o n8n chama) e o gatilho deferido
-- no COMMIT de verdade (seção 8: fora do DO único, com psql `begin; ...; commit;` e o SQLSTATE do COMMIT lido de volta).
--
-- DE ONDE VÊM OS DADOS (regra 4): esta tabela nasce vazia e nenhum chamador existe ainda (A3 e A4 vêm depois), então NÃO há bug de produção reproduzido aqui.
-- Os desfechos (503, timeout, 200 com itens, 200 vazio) são os que a CLASSIFICAÇÃO precisa distinguir, escritos à mão como a entrada da função; o que se afirma é a
-- classificação e as recusas do banco, não o formato de resposta de nenhuma API real. Os 22 nomes de fonte são os do plano (FASE_A_FONTES_PUBLICAS.md §5 A3 e A4).
--
-- A seção 8 faz COMMIT de verdade e a falha esperada do COMMIT aparece no log como uma linha ERROR (é o gatilho deferido recusando "encontrado sem fato"): o resultado
-- é conferido pelo SQLSTATE, não pela ausência do ERROR. Cada resultado volta ao banco limpo no fim (teste_limpa_0303, em modo replica: o DELETE é recusado de propósito).
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
  p_naoc text default null, p_custo numeric default 0) returns text
language plpgsql as $$
declare v_r jsonb; v_out text;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    v_r := fn_registrar_consulta_externa(p_fonte, p_caso, p_cnpj, p_status, p_erro, p_corpo, p_itens, null, p_custo, p_naoc);
    v_out := v_r::text;
  exception when others then
    v_out := sqlstate;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  return v_out;
end $$;

-- O resultado gravado (o que o banco decidiu) de um registro como Sócio padrão do run.sh (superusuário com o JWT do Sócio).
create or replace function teste_res_0303(p_fonte text, p_caso uuid, p_cnpj text, p_status int, p_erro text, p_corpo text, p_itens jsonb, p_naoc text default null,
  p_reg int default null, p_custo numeric default 0) returns text
language plpgsql as $$
begin
  return fn_registrar_consulta_externa(p_fonte, p_caso, p_cnpj, p_status, p_erro, p_corpo, p_itens, p_reg, p_custo, p_naoc) ->> 'resultado';
exception when others then
  return sqlstate;
end $$;

-- Insere direto na tabela (como o service_role/superusuário: sem passar pela função) e devolve 'ok' ou o SQLSTATE. Quem chama desfaz o que entrou.
create or replace function teste_ins_0303(p_fonte text, p_caso uuid, p_cnpj text, p_res text, p_status int, p_motivo text, p_hash text default null, p_reg int default null) returns text
language plpgsql as $$
begin
  insert into consulta_externa (fonte, caso_id, alvo_cnpj, custo, fornecedor, base_legal, http_status, hash_bruto, registros_lidos, motivo, resultado)
  values (p_fonte, p_caso, p_cnpj, 0, 'teste', 'dado_publico', p_status, p_hash, p_reg, p_motivo, p_res);
  return 'ok';
exception when others then
  return sqlstate;
end $$;

-- O CAMINHO DO SERVIÇO (achado G): sem JWT (auth.uid() nulo) e com o role service_role, como o n8n chama. É o que `fn_conexao_de_servico()` reconhece; o teste_sql_0303 com
-- `sub` preenchido NÃO é isto (a pessoa continua identificada). Devolve 'ok' ou o SQLSTATE.
create or replace function teste_srv_0303(p_sql text) returns text
language plpgsql as $$
declare v_out text;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute 'set local role service_role';
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

-- A função de registro COMO serviço: devolve o resultado gravado ou o SQLSTATE.
create or replace function teste_srv_reg_0303(p_fonte text, p_caso uuid, p_cnpj text, p_status int, p_erro text, p_corpo text, p_itens jsonb, p_reg int default null) returns text
language plpgsql as $$
declare v_out text;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute 'set local role service_role';
  begin
    v_out := fn_registrar_consulta_externa(p_fonte, p_caso, p_cnpj, p_status, p_erro, p_corpo, p_itens, p_reg, 0) ->> 'resultado';
  exception when others then
    v_out := sqlstate;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  return v_out;
end $$;

-- Insere uma fonte de teste no catálogo e a apaga: devolve 'ok' ou o SQLSTATE (o que o catálogo aceita de prazo).
create or replace function teste_fonte_0303(p_cadencia text, p_dias int, p_origem text) returns text
language plpgsql as $$
begin
  insert into fonte_externa (chave, nome, origem, tipo, oficial, forma, cadencia, validade_dias, validade_origem, fornecedor, base_legal_tipica)
  values ('teste_prazo_0303', 'teste', 'teste', 'mercado', true, 'consulta', p_cadencia, p_dias, p_origem, 'teste', 'dado_publico');
  delete from fonte_externa where chave = 'teste_prazo_0303';
  return 'ok';
exception when others then
  return sqlstate;
end $$;

-- Devolve o banco limpo: DELETE em consulta_externa e fato_externo é recusado de propósito (achado F), então a limpeza do TESTE roda em modo replica (os gatilhos comuns
-- não disparam; só o superusuário pode). Fato primeiro: no modo replica a cascata da FK também não roda.
create or replace function teste_limpa_0303() returns void
language plpgsql as $$
begin
  perform set_config('session_replication_role', 'replica', true);
  delete from fato_externo;
  delete from consulta_externa;
  perform set_config('session_replication_role', 'origin', true);
end $$;

select teste_limpa_0303();

do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-0000000e0301';
  u_ana   uuid := '00000000-0000-0000-0000-0000000e0302';  -- analista alocada em A
  u_leo   uuid := '00000000-0000-0000-0000-0000000e0303';  -- leitura em A
  u_xan   uuid := '00000000-0000-0000-0000-0000000e0304';  -- analista alocada só em B
  u_nil   uuid := '00000000-0000-0000-0000-0000000e0305';  -- sem papel
  c_ok    text := '11222333000181';
  v_a uuid; v_b uuid;
  v_ch text[]; v_r text; v_j jsonb; v_id uuid; v_id2 uuid; v_n int; v_n2 int; v_t text; v_s int; v_hash text;
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
  -- decisão 6 do dono (24/11/2026): ANBIMA, CCEE e FipeZAP são oficiais; só a BrasilAPI fica de fora
  perform teste_assert_0303((select oficial from fonte_externa where chave = 'anbima_curva') and (select oficial from fonte_externa where chave = 'ccee')
    and (select oficial from fonte_externa where chave = 'fipezap'), 'ANBIMA, CCEE e FipeZAP são oficiais (decisão 6 do dono)');
  select array_agg(chave order by chave) into v_ch from fonte_externa where not oficial;
  perform teste_assert_0303(v_ch = array['brasilapi_cnpj'], 'a BrasilAPI é a ÚNICA fonte não oficial do catálogo', v_ch::text);
  -- decisão 7: o 404 de "não existe" só se preenche na A4, depois de MEDIR; nenhuma das 22 foi medida
  select count(*) into v_n from fonte_externa where http_inexistente is not null;
  perform teste_assert_0303(v_n = 0, 'nenhum status "não existe" inventado no seed: a A4 mede cada fonte e o preenche (decisão 7)', v_n::text);
  select array_agg(chave order by chave) into v_ch from fonte_externa where forma = 'lista';
  perform teste_assert_0303(v_ch = array['cgu_ceis', 'cgu_cnep', 'ibama_autos', 'ibama_embargos', 'mte_trabalho_escravo'], 'as fontes de LISTA são as baixadas inteiras e procuradas pelo CNPJ', v_ch::text);

  raise notice '--- 1b. toda fonte tem prazo (decisão 8): o banco recusa fonte sem prazo e prazo que não bate com a origem ---';
  select count(*) into v_n from fonte_externa where validade_dias is null or validade_dias <= 0 or validade_origem is null;
  perform teste_assert_0303(v_n = 0, 'as 22 fontes do seed têm prazo e origem do prazo', v_n::text);
  -- bcb_juros_modalidade sai do mínimo na 0304 (conectada via SGS, mensal, 30 dias; coberta por a_fonte_que_dizia_mensal_e_rodava_todo_dia.test.sql): as 21 restantes seguem as do seed da 0303
  select count(*) filter (where validade_origem = 'minimo_por_desconhecida' and validade_dias = 1 and cadencia is null),
         count(*) filter (where validade_origem = 'cadencia')
    into v_n, v_n2 from fonte_externa where chave <> 'bcb_juros_modalidade';
  perform teste_assert_0303(v_n = 21 and v_n2 = 0, 'o seed: as 21 fontes além dos juros no mínimo de 1 dia (cadência de publicação desconhecida) e nenhuma por cadência (o MTE incluído, decisão do dono)', v_n || '/' || v_n2);
  perform teste_assert_0303((select validade_dias = 1 and cadencia is null and validade_origem = 'minimo_por_desconhecida' from fonte_externa where chave = 'mte_trabalho_escravo'),
    'o MTE (o plano diz a periodicidade da lista, não a data de publicação) vence em 1 dia, cadência nula: nunca parece nova estando velha (decisão do dono)');
  perform teste_assert_0303((select cadencia is null and validade_dias = 1 from fonte_externa where chave = 'bcb_sgs')
    and (select cadencia is null and validade_dias = 1 from fonte_externa where chave = 'cgu_ceis'),
    'a cadência de BUSCA (SGS mensal, CGU diária por nós) não vira prazo: a de publicação é desconhecida, então 1 dia');
  perform teste_assert_0303(teste_fonte_0303(null, null, 'minimo_por_desconhecida') = '23502', 'fonte SEM prazo (validade_dias nulo) é recusada (23502)');
  perform teste_assert_0303(teste_fonte_0303(null, 0, 'minimo_por_desconhecida') = '23514', 'prazo zero é recusado');
  perform teste_assert_0303(teste_fonte_0303(null, 1, null) = '23502', 'prazo sem a origem do prazo é recusado (23502)');
  perform teste_assert_0303(teste_fonte_0303(null, 1, 'chute') = '23514', 'origem do prazo fora das três é recusada');
  perform teste_assert_0303(teste_fonte_0303(null, 1, 'minimo_por_desconhecida') = 'ok', 'controle positivo: cadência desconhecida com 1 dia e origem mínimo passa');
  perform teste_assert_0303(teste_fonte_0303(null, 7, 'minimo_por_desconhecida') = '23514', 'cadência desconhecida com mais de 1 dia é recusada (vence tarde: parece nova estando velha)');
  perform teste_assert_0303(teste_fonte_0303('mensal', 1, 'minimo_por_desconhecida') = '23514', 'origem "mínimo" com cadência conhecida é recusada');
  perform teste_assert_0303(teste_fonte_0303('mensal', 30, 'cadencia') = 'ok', 'controle positivo: cadência mensal com 30 dias passa');
  perform teste_assert_0303(teste_fonte_0303('mensal', 29, 'cadencia') = '23514', 'cadência mensal com 29 dias é recusada: o prazo tem de ser o da cadência');
  perform teste_assert_0303(teste_fonte_0303(null, 30, 'cadencia') = '23514', 'origem "cadência" sem cadência é recusada');
  perform teste_assert_0303(teste_fonte_0303('diaria', 1, 'cadencia') = 'ok' and teste_fonte_0303('semanal', 7, 'cadencia') = 'ok' and teste_fonte_0303('trimestral', 90, 'cadencia') = 'ok'
    and teste_fonte_0303('semestral', 180, 'cadencia') = 'ok' and teste_fonte_0303('anual', 365, 'cadencia') = 'ok', 'diária 1, semanal 7, trimestral 90, semestral 180 e anual 365 passam');
  perform teste_assert_0303(teste_fonte_0303('semestral', 90, 'cadencia') = '23514' and teste_fonte_0303('anual', 360, 'cadencia') = '23514', 'semestral com 90 e anual com 360 são recusadas');
  perform teste_assert_0303(teste_fonte_0303('mensal', 45, 'publicado') = 'ok', 'o prazo que a PRÓPRIA fonte publica vale como ele é (origem "publicado")');
  perform teste_assert_0303(teste_fonte_0303('sob_demanda', 1, 'minimo_por_desconhecida') = '23514', '"sob_demanda" não é cadência de publicação: recusada');

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
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, 200, null, '[]', '[]'::jsonb);
  perform teste_assert_0303(v_r = 'nada_encontrado', 'HTTP 200 com corpo lido e lista vazia grava nada_encontrado (fonte de consulta)', v_r);
  -- CORPO VAZIO NÃO É LEITURA (2º ciclo, achado 1). Regra 4: o antigo assert aqui afirmava que "204 com '' vira nada_encontrado na BrasilAPI", e isso NÃO foi medido contra a
  -- BrasilAPI (nenhuma resposta real foi vista); só se sabe que um 200/204 vazio de proxy em manutenção, lido com JSON.parse(body || '[]'), chega como "sem itens". O que se afirma
  -- é o comportamento seguro: corpo vazio (ou só espaço) é "não li" e grava falhou, nunca nada_encontrado.
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, 204, null, '', '[]'::jsonb);
  perform teste_assert_0303(v_r = 'falhou', 'HTTP 204 com corpo VAZIO ('''') grava falhou: a string vazia tem hash, mas não prova leitura', v_r);
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, 200, null, '', '[]'::jsonb);
  perform teste_assert_0303(v_r = 'falhou', 'HTTP 200 com corpo vazio (proxy em manutenção) grava falhou, não nada_encontrado', v_r);
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, 200, null, E' \n\t ', '[]'::jsonb);
  perform teste_assert_0303(v_r = 'falhou', 'corpo só de espaço e quebra de linha também é "não li": falhou', v_r);
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, 200, null, '', v_itens);
  perform teste_assert_0303(v_r = 'falhou', 'corpo vazio COM itens também é falhou: o dado não tem a prova do que a fonte disse', v_r);
  v_r := teste_res_0303('cgu_ceis', v_a, c_ok, 200, null, '', '[]'::jsonb, null, 100);
  perform teste_assert_0303(v_r = 'falhou', 'fonte de lista com corpo vazio e registros_lidos informado ainda é falhou (o corpo é a prova)', v_r);
  perform teste_assert_0303((select motivo like '%corpo cru%' and motivo like '%vazio%' from consulta_externa where fonte = 'brasilapi_cnpj' and http_status = 204 and resultado = 'falhou' order by id limit 1),
    'e o motivo diz que o corpo estava vazio');
  perform teste_assert_0303(not exists (select 1 from consulta_externa where hash_bruto = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' and resultado in ('encontrado', 'nada_encontrado')),
    'nenhuma consulta nada_encontrado/encontrado do banco tem o hash da string vazia');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'nada_encontrado', 200, null, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') = '23514', 'escrita direta: nada_encontrado com o hash da string vazia é recusado (CHECK)');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'encontrado', 200, null, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') = '23514', 'escrita direta: encontrado com o hash da string vazia é recusado (CHECK)');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'falhou', 200, 'corpo vazio', 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') = 'ok', 'controle: o hash da string vazia é aceito em falhou (é o registro do que se viu)');
  v_r := teste_res_0303('cgu_ceis', v_a, c_ok, 200, null, '[{"cnpj":"99999999000199"}]', '[]'::jsonb, null, 18234);
  perform teste_assert_0303(v_r = 'nada_encontrado', 'fonte de LISTA com 18234 registros varridos e nenhum do CNPJ grava nada_encontrado', v_r);
  v_j := fn_registrar_consulta_externa('brasilapi_cnpj', v_a, c_ok, 200, null, v_corpo, v_itens, null, 0);
  perform teste_assert_0303(v_j ->> 'resultado' = 'encontrado' and (v_j ->> 'fatos')::int = 2, 'HTTP 200 com 2 itens grava encontrado e 2 fatos', v_j::text);
  v_id := (v_j ->> 'id')::uuid;
  select count(*) into v_n from fato_externo where consulta_id = v_id and chave in ('razao_social', 'cnae_principal');
  perform teste_assert_0303(v_n = 2, 'os 2 fatos estão ligados à consulta que os trouxe');
  select hash_bruto into v_hash from consulta_externa where id = v_id;
  perform teste_assert_0303(v_hash = encode(sha256(convert_to(v_corpo, 'UTF8')), 'hex'), 'o hash do bruto é o sha256 do texto exato do corpo');
  perform teste_assert_0303((select fornecedor from consulta_externa where id = v_id) = 'BrasilAPI' and (select base_legal from consulta_externa where id = v_id) = 'dado_publico'
    and (select custo from consulta_externa where id = v_id) = 0
    and (select validade_em from consulta_externa where id = v_id) = (select data_consulta from consulta_externa where id = v_id) + interval '1 day',
    'fornecedor e base legal vêm do catálogo, o custo é o informado (0) e a validade é a data + o prazo do catálogo (1 dia: o mínimo da BrasilAPI)');
  perform teste_assert_0303((select data_consulta from consulta_externa where id = v_id) between now() and clock_timestamp(), 'a data da consulta é a do banco (clock_timestamp: entre o início da transação e agora)');
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
  v_r := teste_res_0303('pgfn_divida_ativa', v_a, c_ok, null, null, '{"x":1}', null, 'não consultei');
  perform teste_assert_0303(v_r = '22023', 'nao_consultado com corpo é contraditório (não houve chamada, não há corpo nem hash): recusado', v_r);
  perform teste_assert_0303(teste_ins_0303('pgfn_divida_ativa', v_a, c_ok, 'nao_consultado', null, 'não consultei', repeat('a', 64)) = '23514', 'escrita direta: nao_consultado com hash é recusado (CHECK)');
  perform teste_assert_0303(teste_ins_0303('pgfn_divida_ativa', v_a, c_ok, 'nao_consultado', null, 'não consultei', null) = 'ok', 'controle: nao_consultado sem hash entra');
  v_r := teste_res_0303('pgfn_divida_ativa', v_a, c_ok, 200, null, null, '[]'::jsonb, 'não consultei');
  perform teste_assert_0303(v_r = '22023', 'nao_consultado com status e itens (uma resposta) é contraditório: recusado', v_r);
  perform teste_assert_0303((select bool_and(http_status is null) from consulta_externa where fonte = 'pgfn_divida_ativa' and resultado = 'nao_consultado'),
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
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, 404, null, null, '[]'::jsonb);
  perform teste_assert_0303(v_r = 'falhou', 'o 404 documentado SEM o corpo cru lido é falhou: sem prova de leitura não se grava "nada"', v_r);
  update fonte_externa set http_inexistente = null where chave = 'brasilapi_cnpj';
  -- fonte de LISTA: o 404 nunca é "não existe" (é o arquivo que sumiu), mesmo se alguém preencher http_inexistente
  update fonte_externa set http_inexistente = 404 where chave = 'cgu_ceis';
  v_r := teste_res_0303('cgu_ceis', v_a, c_ok, 404, null, 'Not Found', '[]'::jsonb, null, 100);
  perform teste_assert_0303(v_r = 'falhou', 'fonte de lista com 404 grava falhou, mesmo com http_inexistente preenchido', v_r);
  perform teste_assert_0303(teste_ins_0303('cgu_ceis', v_a, c_ok, 'nada_encontrado', 404, null, repeat('a', 64), 100) = '23514', 'e a escrita direta de nada_encontrado com 404 em lista também é recusada');
  update fonte_externa set http_inexistente = null where chave = 'cgu_ceis';
  -- o prazo vem do catálogo, nunca do chamador
  update fonte_externa set validade_dias = 90, validade_origem = 'cadencia', cadencia = 'trimestral' where chave = 'cgu_ceis';
  v_j := fn_registrar_consulta_externa('cgu_ceis', v_a, c_ok, 200, null, '[]', '[]'::jsonb, 10, 0);
  perform teste_assert_0303((select validade_em from consulta_externa where id = (v_j ->> 'id')::uuid) = (select data_consulta + interval '90 days' from consulta_externa where id = (v_j ->> 'id')::uuid),
    'a validade da consulta é a data mais o prazo do catálogo (90 dias, trimestral)');
  update fonte_externa set validade_dias = 1, validade_origem = 'minimo_por_desconhecida', cadencia = null where chave = 'cgu_ceis';
  v_j := fn_registrar_consulta_externa('cgu_ceis', v_a, c_ok, 200, null, '[]', '[]'::jsonb, 10, 0);
  perform teste_assert_0303((select validade_em from consulta_externa where id = (v_j ->> 'id')::uuid) = (select data_consulta + interval '1 day' from consulta_externa where id = (v_j ->> 'id')::uuid),
    'e muda junto com o catálogo (volta para 1 dia): o vencimento é lido do catálogo a cada consulta');
  -- mercado: sem mandato, sem alvo
  v_j := fn_registrar_consulta_externa('bcb_sgs', null, null, 200, null, '[{"data":"01/10/2026","valor":"0.50"}]', '[{"chave":"ipca_2026_10","valor":0.50}]'::jsonb, null, 0);
  perform teste_assert_0303(v_j ->> 'resultado' = 'encontrado' and (select caso_id is null and alvo_cnpj is null from consulta_externa where id = (v_j ->> 'id')::uuid),
    'consulta de mercado grava sem mandato e sem alvo');
  v_r := teste_res_0303('bcb_sgs', null, null, 503, null, null, null);
  perform teste_assert_0303(v_r = 'falhou', 'e uma série de mercado com a API derrubada também grava falhou', v_r);

  -- ------------------------------------------------------------------ 3b. PROVA DE LEITURA, CUSTO E DATA
  raise notice '--- 3b. "nada" exige prova de leitura (corpo e, em lista, registros lidos), custo é explícito e a data é do banco ---';
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, 200, null, null, '[]'::jsonb);
  perform teste_assert_0303(v_r = 'falhou', '200 + [] com o corpo NULO grava falhou, não nada_encontrado (não há prova de que a resposta foi lida)', v_r);
  perform teste_assert_0303((select motivo like '%corpo cru%' from consulta_externa where fonte = 'brasilapi_cnpj' and http_status = 200 and hash_bruto is null and resultado = 'falhou' order by id limit 1),
    'e o motivo diz que faltou o corpo cru');
  v_j := fn_registrar_consulta_externa('brasilapi_cnpj', v_a, c_ok, 200, null, null, v_itens, null, 0);
  perform teste_assert_0303(v_j ->> 'resultado' = 'falhou' and (v_j ->> 'fatos')::int = 0 and not exists (select 1 from fato_externo where consulta_id = (v_j ->> 'id')::uuid),
    '200 com itens mas SEM o corpo cru também é falhou, e não grava fato (o dado não tem a prova do que a fonte disse)', v_j::text);
  v_r := teste_res_0303('cgu_ceis', v_a, c_ok, 200, null, '[]', '[]'::jsonb);
  perform teste_assert_0303(v_r = 'falhou', 'fonte de LISTA, 200 com lista vazia e registros_lidos NÃO informado grava falhou', v_r);
  v_r := teste_res_0303('cgu_ceis', v_a, c_ok, 200, null, '[]', '[]'::jsonb, null, 0);
  perform teste_assert_0303(v_r = 'falhou', 'fonte de LISTA com 0 registros lidos (lista vazia ou página de manutenção com 200) grava falhou', v_r);
  perform teste_assert_0303((select motivo like '%registros lidos%' from consulta_externa where fonte = 'cgu_ceis' and resultado = 'falhou' and registros_lidos = 0 limit 1), 'e o motivo diz o que faltou: os registros lidos');
  v_r := teste_res_0303('cgu_ceis', v_a, c_ok, 200, null, '<html>Manutenção</html>', '[]'::jsonb, null, 0);
  perform teste_assert_0303(v_r = 'falhou', 'a página de manutenção servida com 200 (nenhum registro lido) é falhou', v_r);
  v_r := teste_res_0303('cgu_ceis', v_a, c_ok, 200, null, '[{"cnpj":"11222333000181"}]', '[{"chave":"sancao","valor":"inidoneidade"}]'::jsonb, null, 0);
  perform teste_assert_0303(v_r = 'falhou', 'lista com itens mas 0 registros lidos é falhou: o número varrido não contradiz o achado', v_r);
  v_r := teste_res_0303('cgu_ceis', v_a, c_ok, 200, null, '[{"cnpj":"11222333000181"}]', '[{"chave":"sancao","valor":"inidoneidade"}]'::jsonb, null, 18234);
  perform teste_assert_0303(v_r = 'encontrado', 'controle positivo: lista com 18234 registros lidos e o CNPJ achado grava encontrado', v_r);
  v_r := teste_res_0303('cgu_ceis', v_a, c_ok, 200, null, '[]', '[]'::jsonb, 'x', 5);
  perform teste_assert_0303(v_r = '22023', 'nao_consultado com registros lidos é contraditório: recusado', v_r);
  perform teste_assert_0303(teste_ins_0303('cgu_ceis', v_a, c_ok, 'nada_encontrado', 200, null, repeat('a', 64), null) = '23514', 'escrita direta: nada_encontrado de LISTA sem registros_lidos é recusada (gatilho)');
  perform teste_assert_0303(teste_ins_0303('cgu_ceis', v_a, c_ok, 'nada_encontrado', 200, null, repeat('a', 64), 0) = '23514', 'e com registros_lidos = 0');
  perform teste_assert_0303(teste_ins_0303('cgu_ceis', v_a, c_ok, 'nada_encontrado', 200, null, repeat('a', 64), 7) = 'ok', 'controle positivo: nada_encontrado de LISTA com 7 registros lidos passa');
  perform teste_assert_0303(teste_ins_0303('cgu_ceis', v_a, c_ok, 'nada_encontrado', 200, null, null, 7) = '23514', 'escrita direta: nada_encontrado sem o hash do bruto é recusado (CHECK)');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'nada_encontrado', 200, null, null) = '23514', 'inclusive em fonte de consulta');
  perform teste_assert_0303(teste_ins_0303('cgu_ceis', v_a, c_ok, 'falhou', 200, 'x', null, -1) = '23514', 'registros_lidos negativo é recusado (CHECK)');
  -- custo explícito (achado I)
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, 503, null, null, null, null, null, null);
  perform teste_assert_0303(v_r = '22023', 'custo NULO é recusado (22023): custo desconhecido não vira zero medido', v_r);
  perform teste_assert_0303(teste_res_0303('brasilapi_cnpj', v_a, c_ok, 503, null, null, null, null, null, -1) = '22023', 'custo negativo é recusado');
  perform teste_assert_0303(teste_res_0303('pgfn_divida_ativa', v_a, c_ok, null, null, null, null, 'não consultei', null, null) = '22023', 'custo nulo é recusado também em nao_consultado');
  v_r := teste_res_0303('brasilapi_cnpj', v_a, c_ok, 503, null, null, null, null, null, 0.25);   -- numa instrução separada: a subconsulta da mesma expressão não enxergaria a linha que a função grava
  perform teste_assert_0303(v_r = 'falhou' and (select count(*) from consulta_externa where fonte = 'brasilapi_cnpj' and custo = 0.25) = 1, 'o custo informado é gravado como informado', v_r);
  v_t := null;
  begin
    insert into consulta_externa (fonte, caso_id, alvo_cnpj, fornecedor, base_legal, http_status, motivo, resultado)
    values ('brasilapi_cnpj', v_a, c_ok, 'teste', 'dado_publico', 503, 'x', 'falhou');
  exception when others then v_t := sqlstate; end;
  perform teste_assert_0303(v_t = '23502', 'escrita direta sem o custo é recusada (23502): a coluna não tem mais default zero', v_t);
  -- a data é do banco (achado D)
  perform teste_assert_0303((select pg_get_function_arguments(oid) from pg_proc where proname = 'fn_registrar_consulta_externa') not like '%consultada%'
    and (select pg_get_function_arguments(oid) from pg_proc where proname = 'fn_registrar_consulta_externa') not like '%quando%',
    'a função de registro NÃO recebe data: não há parâmetro para o chamador escolher quando a consulta aconteceu');
  v_t := null;
  begin
    insert into consulta_externa (fonte, caso_id, alvo_cnpj, data_consulta, validade_em, custo, fornecedor, base_legal, http_status, hash_bruto, registros_lidos, resultado)
    values ('cgu_ceis', v_a, c_ok, '2099-01-01', '2099-12-31', 0, 'teste', 'dado_publico', 200, repeat('e', 64), 9, 'nada_encontrado') returning id into v_id;
  exception when others then v_t := sqlstate; end;
  perform teste_assert_0303(v_t is null, 'arranjo: a escrita direta com data e validade de 2099 entra (o gatilho as sobrescreve)', v_t);
  perform teste_assert_0303((select data_consulta between now() and clock_timestamp() and validade_em = data_consulta + interval '1 day' from consulta_externa where id = v_id),
    'um nada_encontrado datado 2099 NÃO fica em 2099: data = a do banco e validade = o catálogo (1 dia), nunca o que o chamador mandou');
  v_j := fn_registrar_consulta_externa('bcb_sgs', null, null, 503, null, null, null, null, 0);
  v_id2 := (fn_registrar_consulta_externa('bcb_sgs', null, null, 200, null, '[{"d":1}]', '[{"chave":"ordem_2","valor":2}]'::jsonb, null, 0) ->> 'id')::uuid;
  perform teste_assert_0303((select b.data_consulta > a.data_consulta from consulta_externa a, consulta_externa b where a.id = (v_j ->> 'id')::uuid and b.id = v_id2),
    'duas consultas da MESMA transação têm datas distintas e ordenadas (clock_timestamp, não now()): "a mais recente" nunca fica indefinida');
  perform teste_assert_0303(not exists (select 1 from consulta_externa where data_consulta > clock_timestamp() + interval '1 second'), 'nenhuma consulta no banco está no futuro (a "mais recente" é sempre uma real)');
  perform teste_assert_0303((select registrado_por is not distinct from auth.uid() from consulta_externa where id = v_id), 'o registrado_por é o auth.uid() de quem gravou, não o que o chamador mandar');
  v_r := teste_reg_0303(u_ana, 'brasilapi_cnpj', v_a, c_ok, 503, null, null, null);
  perform teste_assert_0303((select registrado_por = u_ana from consulta_externa where id = ((v_r::jsonb) ->> 'id')::uuid), 'registrado pela Analista, a consulta guarda quem foi (auth.uid()): a autoria de um "nada" fica rastreável');

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
  perform teste_assert_0303(teste_srv_0303(format('update consulta_externa set resultado = ''nada_encontrado'' where id = %L', v_id)) = '23001',
    'o service_role (sem JWT, como o n8n chama) também não consegue: a imutabilidade não depende do papel');
  perform teste_assert_0303(teste_sql_0303(u_ana, 'authenticated', format('update consulta_externa set resultado = ''nada_encontrado'' where id = %L', v_id)) = '42501',
    'e o authenticated (o portal) nem tem o privilégio (42501)');
  perform teste_assert_0303(teste_sql_0303(u_ana, 'authenticated', format('delete from consulta_externa where id = %L', v_id)) = '42501',
    'o authenticated não apaga consulta: a falha não some');
  -- achado F: o service_role TEM o privilégio de DELETE, e apagar a falha mais nova faz a nada_encontrado antiga voltar a ser a mais recente
  perform teste_assert_0303(teste_srv_0303(format('delete from consulta_externa where id = %L', v_id)) = '23001', 'o service_role NÃO apaga consulta (23001): a falha não some por DELETE');
  v_t := null;
  begin delete from consulta_externa where id = v_id;
  exception when others then v_t := sqlstate; end;
  perform teste_assert_0303(v_t = '23001', 'nem o superusuário apaga a consulta de um mandato vivo', v_t);
  perform teste_assert_0303(exists (select 1 from consulta_externa where id = v_id) and (select resultado from consulta_externa where id = v_id) = 'falhou', 'e a linha falhou continua lá depois das tentativas');
  select id into v_id2 from consulta_externa where fonte = 'bcb_sgs' and resultado = 'falhou' limit 1;
  perform teste_assert_0303(v_id2 is not null and teste_srv_0303(format('delete from consulta_externa where id = %L', v_id2)) = '23001',
    'a consulta de MERCADO (sem mandato, sem cascata possível) nunca se apaga');
  select consulta_id into v_id2 from fato_externo limit 1;
  perform teste_assert_0303(teste_srv_0303('delete from fato_externo') = '23001', 'o service_role não apaga fato (23001): o dado achado não some e deixa a consulta encontrado sem fato');
  perform teste_assert_0303(teste_srv_0303(format('delete from fato_externo where consulta_id = %L', v_id2)) = '23001', 'nem os fatos de uma consulta só');
  select count(*) into v_n from fato_externo;
  perform teste_assert_0303(v_n >= 3, 'os fatos continuam todos lá depois das tentativas de apagar', v_n::text);
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
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'nada_encontrado', 503, null, repeat('a', 64)) = '23514', 'nada_encontrado com HTTP 503 é recusado: a escrita direta não fabrica "nada" de uma falha');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'nada_encontrado', null, null, repeat('a', 64)) = '23514', 'nada_encontrado sem status é recusado');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'nada_encontrado', 404, null, repeat('a', 64)) = '23514', 'nada_encontrado com 404 que a fonte NÃO documenta é recusado (o gatilho confere com a fonte)');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'nada_encontrado', 200, null, repeat('a', 64)) = 'ok', 'controle positivo: nada_encontrado com HTTP 200 e o hash do bruto passa');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'encontrado', 200, null, null) = '23514', 'encontrado sem hash do bruto é recusado');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'encontrado', 503, null, repeat('a', 64)) = '23514', 'encontrado com HTTP 503 é recusado');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'falhou', 503, 'x', 'abc') = '23514', 'hash que não é sha256 (64 hex) é recusado');
  perform teste_assert_0303(teste_ins_0303('brasilapi_cnpj', v_a, c_ok, 'sei_la', 200, 'x') = '23514', 'resultado fora dos quatro estados é recusado');
  -- encontrado sem nenhum fato: recusado ao fim da transação (o gatilho deferido; aqui forçado a conferir já. O caso do COMMIT de verdade é a seção 8, fora deste DO)
  v_t := null;
  begin
    insert into consulta_externa (id, fonte, caso_id, alvo_cnpj, custo, fornecedor, base_legal, http_status, hash_bruto, resultado)
    values (gen_random_uuid(), 'brasilapi_cnpj', v_a, c_ok, 0, 'teste', 'dado_publico', 200, repeat('b', 64), 'encontrado');
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
  perform teste_assert_0303(teste_sql_0303(u_ana, 'authenticated', format('insert into consulta_externa (fonte, caso_id, alvo_cnpj, custo, fornecedor, base_legal, resultado, motivo) values (''brasilapi_cnpj'', %L, %L, 0, ''x'', ''dado_publico'', ''falhou'', ''x'')', v_a, c_ok)) = '42501',
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
  perform teste_assert_0303(teste_sql_0303(null, 'anon', format('select fn_registrar_consulta_externa(''bcb_sgs'', null, null, 503, null, null, null, null, 0)')) = '42501',
    'o anon não executa a função de registro (42501)');
  perform teste_assert_0303(teste_sql_0303(null, 'anon', 'select count(*) from consulta_externa') = '42501', 'o anon não lê a consulta (42501)');
  perform teste_assert_0303(teste_sql_0303(null, 'authenticated', 'select fn_registrar_consulta_externa(''bcb_sgs'', null, null, 503, null, null, null, null, 0)') = '42501',
    'authenticated SEM uid (JWT sem sub) não é "conexão de serviço": a fonte de mercado continua recusada (42501)');

  -- ------------------------------------------------------------------ 6b. O CAMINHO DO SERVIÇO (achado G)
  raise notice '--- 6b. o caminho do serviço: sem JWT, role service_role, como o n8n chama ---';
  v_r := teste_srv_reg_0303('bcb_sgs', null, null, 503, null, null, null);
  perform teste_assert_0303(v_r = 'falhou', 'o serviço registra a fonte de MERCADO (sem ser Sócio): 503 grava falhou', v_r);
  v_r := teste_srv_reg_0303('bcb_sgs', null, null, 200, null, '[{"data":"01/11/2026","valor":"0.39"}]', '[{"chave":"ipca_2026_11","valor":0.39}]'::jsonb);
  perform teste_assert_0303(v_r = 'encontrado', 'o serviço registra um achado de mercado: encontrado + fato', v_r);
  perform teste_assert_0303((select registrado_por is null and caso_id is null from consulta_externa where fonte = 'bcb_sgs' and resultado = 'encontrado' and id in (select consulta_id from fato_externo where chave = 'ipca_2026_11')),
    'e o registrado_por é nulo: foi a conexão de serviço, não uma pessoa');
  v_r := teste_srv_reg_0303('brasilapi_cnpj', v_a, c_ok, 503, null, null, null);
  perform teste_assert_0303(v_r = 'falhou', 'o serviço registra a fonte de EMPRESA no mandato A (a guarda de conexão de serviço)', v_r);
  v_r := teste_srv_reg_0303('cgu_cnep', v_a, c_ok, 200, null, '[]', '[]'::jsonb);
  perform teste_assert_0303(v_r = 'falhou', 'o serviço também cai na regra da lista: 200 vazio sem registros lidos é falhou, não nada', v_r);
  v_r := teste_srv_reg_0303('cgu_cnep', v_a, c_ok, 200, null, '[{"cnpj":"99999999000199"}]', '[]'::jsonb, 18234);
  perform teste_assert_0303(v_r = 'nada_encontrado', 'e com 18234 registros varridos é nada_encontrado', v_r);
  v_r := teste_srv_reg_0303('brasilapi_cnpj', '00000000-0000-0000-0000-00000000ffff', c_ok, 503, null, null, null);
  perform teste_assert_0303(v_r = 'P0002', 'o serviço registrando num mandato que não existe é recusado (P0002)', v_r);
  v_r := teste_srv_reg_0303('fonte_inventada', v_a, c_ok, 200, null, '[]', '[]'::jsonb);
  perform teste_assert_0303(v_r = '23503', 'o serviço registrando fonte fora do catálogo é recusado (23503)', v_r);
  perform teste_assert_0303(teste_srv_0303(format('insert into consulta_externa (fonte, caso_id, alvo_cnpj, custo, fornecedor, base_legal, http_status, resultado) values (''brasilapi_cnpj'', %L, %L, 0, ''x'', ''dado_publico'', 200, ''nada_encontrado'')', v_a, c_ok)) = '23514',
    'o serviço gravando DIRETO na tabela um nada_encontrado sem hash é recusado (23514)');
  perform teste_assert_0303(teste_srv_0303(format('insert into consulta_externa (fonte, caso_id, alvo_cnpj, custo, fornecedor, base_legal, http_status, hash_bruto, resultado, motivo) values (''brasilapi_cnpj'', %L, ''12345678909'', 0, ''x'', ''dado_publico'', 503, null, ''falhou'', ''x'')', v_a)) = '23514',
    'o serviço gravando direto um CPF é recusado (23514)');
  perform teste_assert_0303(teste_srv_0303('update fonte_externa set oficial = false where chave = ''bcb_sgs''') = 'ok', 'o serviço mantém o catálogo (o grant de escrita do service_role é o que a sonda da 0214 exige)');
  update fonte_externa set oficial = true where chave = 'bcb_sgs';
  perform teste_assert_0303(teste_srv_0303(format('update consulta_externa set motivo = ''x'' where caso_id = %L', v_a)) = '23001', 'o serviço não atualiza consulta nenhuma do mandato (23001)');
  perform teste_assert_0303(teste_srv_0303('select count(*) from consulta_externa') = 'ok', 'o serviço lê (a RLS não o barra: bypassrls, como no Supabase)');

  -- ------------------------------------------------------------------ 7. A SONDA
  raise notice '--- 7. a sonda enxerga tudo o que a 0303 instala ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0303' and not presente;
  perform teste_assert_0303(v_n = 0, 'a sonda enxerga os 36 requisitos da 0303 (zero ausentes)', (select string_agg(chave || ': ' || coalesce(detalhe, ''), ' | ') from fn_instalacao_conferir() where migration = '0303' and not presente));
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0303';
  perform teste_assert_0303(v_n = 36, 'e o catálogo da 0303 tem 36 requisitos (não está vazio nem encolheu)', v_n::text);

  -- DEVOLVE O ESTADO. O mandato apagado leva as consultas dele e os fatos pela CASCATA (a única saída do DELETE recusado): conta antes e depois, para a limpeza não correr sobre o vazio.
  select count(*) into v_n from consulta_externa where caso_id in (v_a, v_b);
  perform teste_assert_0303(v_n >= 10, 'há consultas nos mandatos de teste antes de apagá-los', v_n::text);
  delete from caso where nome like '0303 —%';
  select count(*) into v_n from consulta_externa where caso_id in (v_a, v_b);
  perform teste_assert_0303(v_n = 0, 'apagar o MANDATO leva as consultas dele pela cascata (a exceção legítima do DELETE recusado)', v_n::text);
  perform teste_assert_0303(not exists (select 1 from fato_externo f where not exists (select 1 from consulta_externa c where c.id = f.consulta_id)), 'e nenhum fato fica órfão');
  perform teste_assert_0303((select count(*) from consulta_externa where caso_id is null) >= 3, 'as consultas de mercado, sem mandato, não saem com a cascata');
  perform teste_limpa_0303();
  delete from auth.users where id in (u_socio, u_ana, u_leo, u_xan, u_nil);
end $$;

-- ------------------------------------------------------------------ 8. O GATILHO DEFERIDO, NO COMMIT DE VERDADE (achado H)
-- O `set constraints ... immediate` da seção 5 só força a conferência dentro do DO; ele nunca prova que o gatilho roda no COMMIT com a linha presente. Aqui a transação é do psql
-- (`begin; ...; commit;`), e o SQLSTATE do COMMIT é lido de volta (psql :SQLSTATE). ON_ERROR_STOP fica desligado SÓ nestes três blocos: a falha esperada do COMMIT é uma linha ERROR no log.
do $$ begin raise notice '--- 8. o gatilho deferido no COMMIT de verdade (a linha ERROR logo abaixo é a ESPERADA: "encontrado" sem fato recusado no commit) ---'; end $$;
\set ON_ERROR_STOP off

-- 8a. a função grava encontrado + os fatos e o COMMIT passa (a linha existe no commit e há fato)
begin;
select fn_registrar_consulta_externa('bcb_sgs', null, null, 200, null, '[{"data":"01/10/2026","valor":"0.50"}]', '[{"chave":"ipca_2026_10","valor":0.50},{"chave":"ipca_2026_09","valor":0.44}]'::jsonb, null, 0);
commit;
select set_config('ct303.commit_8a', :'SQLSTATE', false);

-- 8b. encontrado SEM nenhum fato: o COMMIT falha (23514) e a linha NÃO fica no banco
begin;
insert into consulta_externa (fonte, caso_id, alvo_cnpj, custo, fornecedor, base_legal, http_status, hash_bruto, resultado)
values ('bcb_sgs', null, null, 0, 'teste', 'dado_publico', 200, repeat('c', 64), 'encontrado');
commit;
select set_config('ct303.commit_8b', :'SQLSTATE', false);

-- 8c. encontrado + fato na mesma transação, escritos direto: o COMMIT passa
begin;
with c as (
  insert into consulta_externa (fonte, caso_id, alvo_cnpj, custo, fornecedor, base_legal, http_status, hash_bruto, resultado)
  values ('bcb_sgs', null, null, 0, 'teste', 'dado_publico', 200, repeat('d', 64), 'encontrado') returning id)
insert into fato_externo (consulta_id, chave, valor) select id, 'serie_teste', '1'::jsonb from c;
commit;
select set_config('ct303.commit_8c', :'SQLSTATE', false);

\set ON_ERROR_STOP on

do $$
declare v_n int;
begin
  perform teste_assert_0303(current_setting('ct303.commit_8a') = '00000', '8a: o COMMIT de encontrado + fatos (pela função) PASSA', current_setting('ct303.commit_8a'));
  select count(*) into v_n from fato_externo f join consulta_externa c on c.id = f.consulta_id
   where c.resultado = 'encontrado' and f.chave in ('ipca_2026_10', 'ipca_2026_09');
  perform teste_assert_0303(v_n = 2, '8a: e os 2 fatos estão comitados no banco (a transação anterior já terminou), ligados à consulta encontrado', v_n::text);
  perform teste_assert_0303(current_setting('ct303.commit_8b') = '23514', '8b: o COMMIT de encontrado SEM nenhum fato FALHA (23514): o gatilho deferido roda no commit, com a linha presente', current_setting('ct303.commit_8b'));
  perform teste_assert_0303(not exists (select 1 from consulta_externa where hash_bruto = repeat('c', 64)), '8b: e a consulta encontrado sem fato NÃO ficou no banco (a transação foi desfeita)');
  perform teste_assert_0303(current_setting('ct303.commit_8c') = '00000', '8c: o COMMIT de encontrado + fato escritos direto PASSA', current_setting('ct303.commit_8c'));
  perform teste_assert_0303(exists (select 1 from consulta_externa c join fato_externo f on f.consulta_id = c.id where c.hash_bruto = repeat('d', 64) and f.chave = 'serie_teste'), '8c: e a consulta e o fato estão comitados');
  perform teste_assert_0303(not exists (select 1 from consulta_externa c where c.resultado = 'encontrado' and not exists (select 1 from fato_externo f where f.consulta_id = c.id)),
    'depois de tudo, NENHUMA consulta encontrado do banco está sem fato');
  perform teste_limpa_0303();
  select count(*) into v_n from consulta_externa;
  perform teste_assert_0303(v_n = 0, 'o banco volta limpo da seção 8 (consultas)', v_n::text);

  raise notice 'EXECUCOES=% FALHAS=%', current_setting('ct303.execucoes', true), coalesce(current_setting('ct303.falhas', true), '0');
  if current_setting('ct303.medindo', true) is distinct from 'on' then
    raise notice 'TODOS OS TESTES DA 0303 PASSARAM';
  end if;
end $$;
