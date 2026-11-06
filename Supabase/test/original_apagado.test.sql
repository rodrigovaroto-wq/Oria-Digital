-- =============================================================================
-- 0224 — O ORIGINAL QUE O ANALISTA APAGAVA SEM TRILHA (D16): toda exclusão no bucket `documentos` deixa evento e aparece no Histórico
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md): os números por guarda desligada estão no cabeçalho de
-- Supabase/migrations/0224_o_original_que_o_analista_apagava_sem_trilha.sql ("MEDIÇÃO NÃO-VAZIA").
--
--
-- COMO RODA. Dois caminhos, porque a API do Storage apaga em DUAS etapas (supabase/storage, src/internal/database/pg-connection.ts:725-742):
--   (a) `testPermission` avalia a RLS COMO O USUÁRIO numa transação DESFEITA, e a exclusão EFETIVA roda como `service_role` com `request.jwt.claim.sub=''` e o
--       JWT do usuário só em `request.headers` -> `authorization`. É o caminho REAL: `teste_api_d16` o reproduz (role service_role, sub vazio, cabeçalho). Antes desta
--       versão a suíte só apagava como `authenticated` direto (mecanismo suposto) e a 0224 gravaria `sistema:storage` em TODA exclusão do Analista sem que nada reprovasse;
--   (b) `authenticated` direto com JWT em `request.jwt.claims` (o que o PostgREST faz): é o teste das seções 1 a 4.
-- Superusuário ignora RLS e passaria sobre qualquer policy; o stub do run.sh dá BYPASSRLS ao service_role (como o Supabase real). O stub não tem o gatilho
-- protect_objects_delete da plataforma, que só recusa SQL direto em produção.
--
-- O QUE AFIRMA (comportamento, não mecanismo):
--   1. Analista alocada apaga original do mandato dela: o objeto some e fica UM evento, com o e-mail dela como ator, o mandato certo,
--      o nome original e o tamanho em `antes`, e `depois` nulo;
--   2. Sócio apaga: evento com o e-mail do Sócio;
--   3. quem não pode apagar (Analista de outro mandato, Leitura, sem papel) NÃO apaga e NÃO deixa evento (a tentativa barrada não é exclusão);
--   4. objeto de OUTRO bucket apagado: nenhum evento; vários objetos num DELETE só: um evento por objeto;
--   5. conexão SQL de serviço (sem request.headers): `storage:sql_direto` com session_user em antes (ato de pessoa, nunca "Sistema"); objeto solto (chave sem mandato) apagado: evento `storage:documentos/<chave>`, não some;
--   5b. O CAMINHO REAL DA API: ator = e-mail lido do JWT de `request.headers` (com todos os paddings do base64url e com `-`/`_`), cabeçalho em maiúscula também; cabeçalho
--      ausente, malformado, sem sub, sub inexistente ou ilegível: o DELETE SEGUE e o ator é `storage:nao_identificado` com o motivo; JWT de service_role: `storage:chave_de_servico`; operação que não é a REST de exclusão verificada (S3, outras, vazia = job): `authorization` nunca lido (lista de PERMITIDOS por storage.operation);
--      JWT sem o prefixo Bearer: atribuído;
--   6. o Histórico do mandato mostra a exclusão a quem lê o mandato (Analista alocada, Leitura) e NÃO a quem não lê; `storage:nao_identificado` NÃO some como "Sistema";
--   7. falha fechada: se a trilha não puder ser gravada, o objeto NÃO é apagado;
--   8. a sonda enxerga o gatilho, a policy de update e o versionamento: 9 requisitos da 0224 presentes, e cada um desfeito a faz acusar;
--   9. mover/sobrescrever original (UPDATE) é só do Sócio; o upload (INSERT) do Analista alocado continua;
--  11. a trilha não se forja pela porta da frente: ninguém insere à mão a ação documento_original_apagado (nem o Sócio), e o gatilho continua gravando;
--   1b. `auth.uid()` só atribui dentro da operação REST de exclusão; fora dela (SQL direto com claims à mão) é `storage:sql_direto` com o sub só ALEGADO;
--  10. versionamento: delete marker e versão arquivada não viram evento; sem as colunas do versionamento o gatilho continua gravando.
-- =============================================================================

-- `d16.medindo = on` (PGOPTIONS='-c d16.medindo=on') vira `raise warning` e CONTA: é como se mede quantos asserts uma guarda desligada reprova.
create or replace function teste_assert_d16(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('d16.execucoes', (coalesce(nullif(current_setting('d16.execucoes', true), ''), '0')::int + 1)::text, false);
  if p_cond then
    raise notice 'ok    %', p_nome;
  elsif current_setting('d16.medindo', true) = 'on' then
    perform set_config('d16.falhas', (coalesce(nullif(current_setting('d16.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- Executa um comando COMO o papel corrente e devolve 'ok:<linhas>' ou o SQLSTATE.
create or replace function teste_tenta_d16(p_sql text) returns text
language plpgsql as $$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return 'ok:' || n;
exception when others then
  return sqlstate;
end $$;

-- Entra como o usuário (JWT) com o papel `authenticated`.
create or replace function teste_como_d16(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

-- Volta a CONEXÃO DE SERVIÇO: superusuário SEM JWT e SEM request.headers (o SQL Editor chega assim; a API do Storage sempre define request.headers).
create or replace function teste_servico_d16() returns void
language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.headers', '', true);
  perform set_config('request.path', '', true);
  perform set_config('storage.operation', '', true);
end $$;

-- A ETAPA 2 DA API DO STORAGE (a exclusão efetiva): role service_role, sub vazio, e o JWT do usuário só em request.headers (scope.ts:15-24 do supabase/storage).
create or replace function teste_api_d16(p_headers text, p_path text default '', p_op text default '') returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.headers', p_headers, true);
  perform set_config('request.path', p_path, true);   -- request.url do Fastify, CRUA do cliente (REST: '/object/documentos/<chave>')
  perform set_config('storage.operation', p_op, true); -- request.operation = config da ROTA ('storage.object.delete'); vazio = job de fila
  execute 'set local role service_role';
end $$;

-- base64url SEM padding (o formato do JWT) de um texto, e um JWT de mentira (cabeçalho fixo + payload + assinatura que ninguém confere: o Storage já validou).
create or replace function teste_b64u_d16(p text) returns text language sql immutable as $$
  select rtrim(translate(replace(encode(convert_to(p, 'utf8'), 'base64'), E'\n', ''), '+/', '-_'), '=') $$;
create or replace function teste_jwt_d16(p_payload text) returns text language sql immutable as $$
  select 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.' || teste_b64u_d16(p_payload) || '.assinatura' $$;

-- Cabeçalhos de um usuário na REST: só o `authorization` com o JWT dele (o que o Storage verificou na entrada).
create or replace function teste_hdr_d16(p_uid uuid) returns text language sql immutable as $$
  select jsonb_build_object('authorization', 'Bearer ' || teste_jwt_d16(jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text))::text $$;

-- Apaga UM objeto pelo caminho real da API com os cabeçalhos dados e devolve o resultado do DELETE.
create or replace function teste_api_apaga_d16(p_headers text, p_nome text, p_path text default null, p_op text default 'storage.object.delete') returns text
language plpgsql as $$
declare r text;
begin
  -- Sem path/operação informados, é a REST REAL de exclusão (a única em que o Storage verifica o JWT do cabeçalho). Operação '' = job de fila.
  perform teste_api_d16(p_headers, coalesce(p_path, '/object/documentos/' || p_nome), p_op);
  r := teste_tenta_d16(format($q$delete from storage.objects where bucket_id = 'documentos' and name = any (string_to_array(%L, '|'))$q$, p_nome));   -- p_nome: um nome, ou vários separados por '|' (um DELETE só)
  perform teste_servico_d16();
  return r;
end $$;

-- Limpeza de rodada anterior (o teste é reexecutável).
delete from caso where nome like '0224 —%';
delete from storage.objects where name like '%-0224.pdf';
update storage.buckets set versioning_status = 'DISABLED' where id = 'documentos';
delete from auth.users where id in ('00000000-0000-0000-0000-00000000d161', '00000000-0000-0000-0000-00000000d162',
  '00000000-0000-0000-0000-00000000d163', '00000000-0000-0000-0000-00000000d164', '00000000-0000-0000-0000-00000000d165');
delete from evento_auditoria where acao in ('documento_original_apagado', 'teste_0224_outra');

do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000000d161';   -- Sócio
  u_ana   uuid := '00000000-0000-0000-0000-00000000d162';   -- Analista, alocada em A
  u_leo   uuid := '00000000-0000-0000-0000-00000000d163';   -- Leitura, alocado em A
  u_nil   uuid := '00000000-0000-0000-0000-00000000d164';   -- SEM papel
  u_xan   uuid := '00000000-0000-0000-0000-00000000d165';   -- Analista, alocado só em B
  v_a uuid; v_b uuid; v_r jsonb; v_res text; v_n int; v_n0 int; v_ev record; v_txt text; v_falta int;
  v_doc_a uuid;
  v_c uuid; v_pq text; v_pw text; v_i int; v_j text; v_nome text; v_hdr text; v_esp text;
begin
  -- ---------------------------------------------------------------- montagem (conexão de serviço)
  insert into auth.users (id, email) values
    (u_socio, 'socio@0224.local'), (u_ana, 'ana@0224.local'), (u_leo, 'leo@0224.local'),
    (u_nil, 'nil@0224.local'), (u_xan, 'xan@0224.local');
  v_a := fn_upsert_caso('0224 — mandato A');
  v_b := fn_upsert_caso('0224 — mandato B');
  v_c := fn_upsert_caso('0224 — mandato C (caminho da API)');
  perform fn_definir_papel(u_socio, 'socio', 'teste 0224');
  perform fn_definir_papel(u_ana, 'analista');
  perform fn_definir_papel(u_leo, 'leitura');
  perform fn_definir_papel(u_xan, 'analista');
  perform fn_alocar(v_a, u_ana);
  perform fn_alocar(v_a, u_leo);
  perform fn_alocar(v_b, u_xan);

  v_r := fn_registrar_documento(v_a, 'ALFA SA', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', v_a || '/hash-1-0224.pdf', 'BP Alfa.pdf', true, 'HASH-1-0224', 'ok');
  v_doc_a := (v_r->>'documento_id')::uuid;

  insert into storage.objects (bucket_id, name, metadata) values
    ('documentos', v_a || '/hash-1-0224.pdf', '{"size": 1234}'),
    ('documentos', v_a || '/hash-2-0224.pdf', '{"size": 2048}'),
    ('documentos', v_a || '/hash-3-0224.pdf', '{"size": 10}'),
    ('documentos', v_a || '/hash-4-0224.pdf', '{"size": 11}'),
    ('documentos', v_a || '/hash-5-0224.pdf', '{"size": 12}'),
    ('documentos', v_b || '/hash-b-0224.pdf', '{"size": 99}'),
    ('documentos', 'solto-0224.pdf', null),
    ('relatorios', v_a || '/outro-bucket-0224.pdf', '{"size": 5}'),
    ('documentos', v_a || '/mover-0224.pdf', '{"size": 7}');

  -- ---------------------------------------------------------------- 1. Analista alocada apaga o original do mandato dela
  raise notice '--- 1. a Analista alocada apaga: o objeto some e fica UM evento, com ela como ator e o mandato certo ---';
  -- Pela REST REAL (etapa 2: service_role, sub vazio, JWT no cabeçalho, operação storage.object.delete): é o único caminho em que o ator se identifica.
  v_res := teste_api_apaga_d16(teste_hdr_d16(u_ana), v_a || '/hash-1-0224.pdf');
  perform teste_assert_d16(v_res = 'ok:1' and not exists (select 1 from storage.objects where name = v_a || '/hash-1-0224.pdf'),
    'a Analista alocada apaga o original do mandato dela (a decisão do dono: continua podendo)', v_res);
  select count(*) into v_n from evento_auditoria where acao = 'documento_original_apagado' and entidade_ref = 'caso:' || v_a;
  perform teste_assert_d16(v_n = 1, 'a exclusão deixa exatamente UM evento no mandato', v_n::text);
  select * into v_ev from evento_auditoria where acao = 'documento_original_apagado' and entidade_ref = 'caso:' || v_a order by criado_em, id limit 1;
  perform teste_assert_d16(v_ev.ator = 'ana@0224.local', 'o ator é o e-mail de quem apagou (do JWT), não "sistema"', v_ev.ator);
  perform teste_assert_d16(v_ev.antes->>'caminho' = v_a || '/hash-1-0224.pdf' and v_ev.antes->>'arquivo' = 'hash-1-0224.pdf'
    and v_ev.antes->>'bucket' = 'documentos', 'o evento diz qual objeto se perdeu (caminho, arquivo, bucket)', v_ev.antes::text);
  perform teste_assert_d16(v_ev.antes->>'nome_original' = 'BP Alfa.pdf' and (v_ev.antes->>'documento_id')::uuid = v_doc_a,
    'e o nome que o cliente deu ao arquivo, e de qual documento era', v_ev.antes::text);
  perform teste_assert_d16((v_ev.antes->>'tamanho_bytes')::int = 1234 and (v_ev.antes->>'usuario_id')::uuid = u_ana,
    'e o tamanho que se perdeu e o id de quem apagou', v_ev.antes::text);
  perform teste_assert_d16(v_ev.depois is null, 'depois é nulo: o objeto não existe mais', coalesce(v_ev.depois::text, 'null'));

  -- ---------------------------------------------------------------- 2. Sócio apaga
  raise notice '--- 2. o Sócio apaga: evento com o e-mail dele ---';
  v_res := teste_api_apaga_d16(teste_hdr_d16(u_socio), v_a || '/hash-2-0224.pdf');
  select * into v_ev from evento_auditoria where acao = 'documento_original_apagado' and antes->>'caminho' = v_a || '/hash-2-0224.pdf';
  perform teste_assert_d16(v_res = 'ok:1' and v_ev.ator = 'socio@0224.local' and v_ev.entidade_ref = 'caso:' || v_a,
    'o Sócio apaga e a exclusão é auditada com o e-mail dele no mandato certo', v_res || ' ' || coalesce(v_ev.ator, 'sem evento'));

  -- ---------------------------------------------------------------- 1b. auth.uid() só atribui dentro da operação REST de exclusão
  raise notice '--- 1b. SQL direto com claims à mão (auth.uid() não-nulo, sem operação REST): storage:sql_direto, sub só alegado ---';
  v_nome := v_c || '/direto-0224.pdf';
  insert into storage.objects (bucket_id, name, metadata) values ('documentos', v_nome, '{"size": 3}');
  perform teste_como_d16(u_socio);
  v_res := teste_tenta_d16(format($q$delete from storage.objects where name = '%s'$q$, v_nome));
  perform teste_servico_d16();
  select * into v_ev from evento_auditoria where acao = 'documento_original_apagado' and antes->>'caminho' = v_nome;
  perform teste_assert_d16(v_res = 'ok:1' and v_ev.ator = 'storage:sql_direto' and v_ev.antes->>'sub_alegado' = u_socio::text and v_ev.antes->>'usuario_id' is null
    and v_ev.antes->>'sessao_usuario' = session_user and v_ev.antes->>'ator_origem' = 'auth.uid_fora_da_rest',
    'auth.uid() não-nulo SEM a operação REST de exclusão (personificação em SQL): não atribui; storage:sql_direto com o sub alegado e session_user', v_res || ' ' || coalesce(v_ev.ator, 'sem evento') || ' / ' || coalesce(v_ev.antes::text, ''));
  v_nome := v_c || '/direto-op-0224.pdf';
  insert into storage.objects (bucket_id, name, metadata) values ('documentos', v_nome, '{"size": 3}');
  perform set_config('storage.operation', 'storage.object.delete', true);
  perform teste_como_d16(u_socio);
  v_res := teste_tenta_d16(format($q$delete from storage.objects where name = '%s'$q$, v_nome));
  perform teste_servico_d16();
  select * into v_ev from evento_auditoria where acao = 'documento_original_apagado' and antes->>'caminho' = v_nome;
  perform teste_assert_d16(v_res = 'ok:1' and v_ev.ator = 'socio@0224.local' and v_ev.antes->>'ator_origem' = 'auth.uid',
    'auth.uid() não-nulo DENTRO da operação REST de exclusão: atribui (e-mail)', v_res || ' ' || coalesce(v_ev.ator, 'sem evento'));

  -- ---------------------------------------------------------------- 3. quem não pode apagar não apaga e não deixa evento
  raise notice '--- 3. Analista de outro mandato, Leitura e sem papel não apagam, e a tentativa barrada não vira evento ---';
  select count(*) into v_n0 from evento_auditoria where acao = 'documento_original_apagado';
  perform teste_como_d16(u_xan);
  v_res := teste_tenta_d16(format($q$delete from storage.objects where bucket_id = 'documentos' and name = '%s/hash-3-0224.pdf'$q$, v_a));
  perform teste_servico_d16();
  perform teste_assert_d16(v_res in ('ok:0', '42501') and exists (select 1 from storage.objects where name = v_a || '/hash-3-0224.pdf'),
    'a Analista alocada só em B não apaga original de A (RLS do Storage)', v_res);
  perform teste_como_d16(u_leo);
  v_res := teste_tenta_d16(format($q$delete from storage.objects where bucket_id = 'documentos' and name = '%s/hash-3-0224.pdf'$q$, v_a));
  perform teste_servico_d16();
  perform teste_assert_d16(v_res in ('ok:0', '42501') and exists (select 1 from storage.objects where name = v_a || '/hash-3-0224.pdf'),
    'a Leitura não apaga original (42501 ou 0 linhas)', v_res);
  perform teste_como_d16(u_nil);
  v_res := teste_tenta_d16(format($q$delete from storage.objects where bucket_id = 'documentos' and name = '%s/hash-3-0224.pdf'$q$, v_a));
  perform teste_servico_d16();
  perform teste_assert_d16(v_res in ('ok:0', '42501') and exists (select 1 from storage.objects where name = v_a || '/hash-3-0224.pdf'),
    'quem não tem papel não apaga original', v_res);
  select count(*) into v_n from evento_auditoria where acao = 'documento_original_apagado';
  perform teste_assert_d16(v_n = v_n0, 'nenhuma dessas tentativas barradas virou evento de exclusão', format('%s -> %s', v_n0, v_n));

  -- ---------------------------------------------------------------- 4. outro bucket; vários objetos num DELETE
  raise notice '--- 4. outro bucket não gera evento; vários objetos num DELETE geram um evento por objeto ---';
  select count(*) into v_n0 from evento_auditoria where acao = 'documento_original_apagado';
  -- Pela conexão de serviço: nenhuma policy de authenticated cobre outro bucket (o Sócio leva 0 linhas), e o que se afirma é o GATILHO, não a policy.
  v_res := teste_tenta_d16(format($q$delete from storage.objects where bucket_id = 'relatorios' and name = '%s/outro-bucket-0224.pdf'$q$, v_a));
  select count(*) into v_n from evento_auditoria where acao = 'documento_original_apagado';
  perform teste_assert_d16(v_n = v_n0 and not exists (select 1 from storage.objects where name = v_a || '/outro-bucket-0224.pdf'),
    'apagar objeto de OUTRO bucket não deixa evento de original', format('apagou %s; eventos %s -> %s', v_res, v_n0, v_n));
  v_res := teste_api_apaga_d16(teste_hdr_d16(u_ana), v_a || '/hash-4-0224.pdf|' || v_a || '/hash-5-0224.pdf', '/object/documentos', 'storage.object.delete_many');
  select count(*) into v_n from evento_auditoria where acao = 'documento_original_apagado' and ator = 'ana@0224.local'
    and antes->>'caminho' in (v_a || '/hash-4-0224.pdf', v_a || '/hash-5-0224.pdf');
  perform teste_assert_d16(v_res = 'ok:2' and v_n = 2, 'dois objetos num DELETE só: um evento para cada um', v_res || ' / ' || v_n);

  -- ---------------------------------------------------------------- 5. conexão de serviço e objeto sem mandato
  raise notice '--- 5. a conexão SQL de serviço (sem request.headers) apaga como storage:sql_direto; objeto solto também é gravado ---';
  v_res := teste_tenta_d16(format($q$delete from storage.objects where bucket_id = 'documentos' and name = '%s/hash-b-0224.pdf'$q$, v_b));
  select * into v_ev from evento_auditoria where acao = 'documento_original_apagado' and entidade_ref = 'caso:' || v_b;
  perform teste_assert_d16(v_res = 'ok:1' and v_ev.ator = 'storage:sql_direto' and v_ev.antes->>'sessao_usuario' = session_user and v_ev.antes->>'ator_origem' = 'conexao_sql', 'a conexão SQL de serviço (sem request.headers: não veio pela API) apaga e o ator é storage:sql_direto com session_user, no mandato B', v_res || ' ' || coalesce(v_ev.ator, 'sem evento'));
  v_res := teste_tenta_d16($q$delete from storage.objects where bucket_id = 'documentos' and name = 'solto-0224.pdf'$q$);
  select * into v_ev from evento_auditoria where acao = 'documento_original_apagado' and entidade_ref = 'storage:documentos/solto-0224.pdf';
  perform teste_assert_d16(v_res = 'ok:1' and v_ev.id is not null and v_ev.antes->>'nome_original' is null,
    'objeto sem mandato na chave: a exclusão é gravada do mesmo jeito (storage:documentos/<chave>), sem nome inventado', v_res);

  -- ---------------------------------------------------------------- 5b. O CAMINHO REAL DA API (etapa 2: service_role, sub vazio, JWT só no cabeçalho)
  raise notice '--- 5b. a exclusão efetiva da API do Storage (service_role, sub vazio): o ator vem do JWT de request.headers ---';
  -- Os 4 paddings do base64url (0, 1, 2 e '=' removidos) e os caracteres `-`/`_` (o extra '>>>???' codifica '+' e '/'), todos resolvendo para a Analista.
  v_i := 0;
  foreach v_esp in array array['', 'a', 'ab', '>>>???~~'] loop
    v_i := v_i + 1;
    v_nome := v_c || '/api-pad' || v_i || '-0224.pdf';
    insert into storage.objects (bucket_id, name, metadata) values ('documentos', v_nome, '{"size": 3}');
    v_hdr := jsonb_build_object('authorization', 'Bearer ' || teste_jwt_d16(jsonb_build_object('sub', u_ana, 'role', 'authenticated', 'x', v_esp)::text),
                                'apikey', 'chave-anon-que-nao-importa')::text;
    v_res := teste_api_apaga_d16(v_hdr, v_nome);
    select * into v_ev from evento_auditoria where acao = 'documento_original_apagado' and antes->>'caminho' = v_nome;
    perform teste_assert_d16(v_res = 'ok:1' and v_ev.ator = 'ana@0224.local' and v_ev.entidade_ref = 'caso:' || v_c
      and (v_ev.antes->>'usuario_id')::uuid = u_ana,
      'pela API real (service_role, sub vazio) o ator é o e-mail da Analista lido do JWT do cabeçalho (padding/-/_ variante ' || v_i || ')',
      v_res || ' ' || coalesce(v_ev.ator, 'sem evento'));
  end loop;
  -- O nome do cabeçalho em maiúscula também (o Node baixa a caixa; a leitura não depende disso).
  v_nome := v_c || '/api-caixa-0224.pdf';
  insert into storage.objects (bucket_id, name, metadata) values ('documentos', v_nome, '{"size": 3}');
  v_res := teste_api_apaga_d16(jsonb_build_object('Authorization', 'bearer ' || teste_jwt_d16(jsonb_build_object('sub', u_socio, 'role', 'authenticated')::text))::text, v_nome);
  select * into v_ev from evento_auditoria where acao = 'documento_original_apagado' and antes->>'caminho' = v_nome;
  perform teste_assert_d16(v_res = 'ok:1' and v_ev.ator = 'socio@0224.local' and v_ev.antes->>'ator_origem' = 'cabecalho_jwt',
    'o nome do cabeçalho e o "Bearer" em qualquer caixa funcionam', v_res || ' ' || coalesce(v_ev.ator, 'sem evento'));

  -- O Storage aceita o JWT SEM o prefixo "Bearer" (jwt.ts:41: replace(/^Bearer\s+/i, '')): mandar o token cru não pode virar "não identificado".
  v_nome := v_c || '/api-cru-0224.pdf';
  insert into storage.objects (bucket_id, name, metadata) values ('documentos', v_nome, '{"size": 3}');
  v_res := teste_api_apaga_d16(jsonb_build_object('authorization', teste_jwt_d16(jsonb_build_object('sub', u_ana, 'role', 'authenticated')::text))::text, v_nome);
  select * into v_ev from evento_auditoria where acao = 'documento_original_apagado' and antes->>'caminho' = v_nome;
  perform teste_assert_d16(v_res = 'ok:1' and v_ev.ator = 'ana@0224.local', 'JWT SEM o prefixo "Bearer" (o Storage aceita): atribuído à Analista', v_res || ' ' || coalesce(v_ev.ator, 'sem evento'));
  -- delete_many é a outra operação REST verificada.
  v_nome := v_c || '/api-many-0224.pdf';
  insert into storage.objects (bucket_id, name, metadata) values ('documentos', v_nome, '{"size": 3}');
  v_res := teste_api_apaga_d16(jsonb_build_object('authorization', 'Bearer ' || teste_jwt_d16(jsonb_build_object('sub', u_ana, 'role', 'authenticated')::text))::text, v_nome, '/object/documentos', 'storage.object.delete_many');
  select * into v_ev from evento_auditoria where acao = 'documento_original_apagado' and antes->>'caminho' = v_nome;
  perform teste_assert_d16(v_res = 'ok:1' and v_ev.ator = 'ana@0224.local' and v_ev.antes->>'storage_operation' = 'storage.object.delete_many', 'a REST de exclusão em lote (storage.object.delete_many) também atribui', v_res || ' ' || coalesce(v_ev.ator, 'sem evento'));
  -- QUALQUER OPERAÇÃO QUE NÃO É A REST VERIFICADA: lista de PERMITIDOS sobre `storage.operation` (a config da rota, que o cliente não escreve). O `authorization` nas outras rotas
  -- (S3 autentica por signatureV4 e não valida o JWT do cabeçalho) é do cliente: um Bearer forjado com o sub do Sócio NUNCA é atribuído a ele, nem a service_role. O path
  -- é CRU do cliente e o roteador o normaliza (`/%73%33/...`, absolute-form): os paths abaixo registram que ele NÃO decide mais nada. Operação vazia = job de fila.
  foreach v_j in array array[
      'storage.s3.object.delete|/s3/documentos/x?X-Amz-Signature=abc&X-Amz-Security-Token=eyJsegredo',
      'storage.s3.object.delete_many|/storage/v1/s3/documentos?delete',
      'storage.s3.object.delete|/%73%33/documentos/a/b',
      'storage.s3.object.delete|http://h/s3/documentos/a/b',
      'storage.object.update|/object/documentos/x',
      '|/object/documentos/x',
      '|']
  loop
    v_i := v_i + 1;
    v_nome := v_c || '/api-op-' || v_i || '-0224.pdf';
    insert into storage.objects (bucket_id, name, metadata) values ('documentos', v_nome, '{"size": 3}');
    v_res := teste_api_apaga_d16(jsonb_build_object('authorization', 'Bearer ' || teste_jwt_d16(jsonb_build_object('sub', u_socio, 'role', 'authenticated')::text))::text, v_nome,
                                 split_part(v_j, '|', 2), split_part(v_j, '|', 1));
    select * into v_ev from evento_auditoria where acao = 'documento_original_apagado' and antes->>'caminho' = v_nome;
    perform teste_assert_d16(v_res = 'ok:1' and v_ev.ator = 'storage:nao_identificado' and v_ev.antes->>'usuario_id' is null
      and v_ev.antes->>'ator_motivo' = case when split_part(v_j, '|', 1) = '' then 'operacao ausente' else 'operacao ' || split_part(v_j, '|', 1) end
      and v_ev.antes->>'storage_operation' = split_part(v_j, '|', 1) and v_ev.antes->>'request_path' not like '%?%' and v_ev.antes::text not like '%eyJsegredo%',
      format('operação "%s" (path "%s") com Bearer forjado do sub do Sócio: nunca atribuído, query fora da trilha', split_part(v_j, '|', 1), split_part(v_j, '|', 2)),
      v_res || ' ' || coalesce(v_ev.ator, 'sem evento') || ' / ' || coalesce(v_ev.antes::text, ''));
  end loop;
  v_nome := v_c || '/api-s3-sr-0224.pdf';
  insert into storage.objects (bucket_id, name, metadata) values ('documentos', v_nome, '{"size": 3}');
  v_res := teste_api_apaga_d16(jsonb_build_object('authorization', 'Bearer ' || teste_jwt_d16('{"role":"service_role"}'))::text, v_nome, '/s3/documentos/x', 'storage.s3.object.delete');
  select * into v_ev from evento_auditoria where acao = 'documento_original_apagado' and antes->>'caminho' = v_nome;
  perform teste_assert_d16(v_res = 'ok:1' and v_ev.ator = 'storage:nao_identificado', 'operação S3 com payload service_role forjado: nunca vira chave de serviço nem sistema', v_res || ' ' || coalesce(v_ev.ator, 'sem evento'));

  -- O que não identifica ninguém: o DELETE SEGUE (o objeto some) e o ator é storage:nao_identificado com o motivo. NUNCA sistema:*.
  v_i := 0;
  foreach v_j in array array[
      '{}|sem cabecalho authorization',
      '{"apikey":"x"}|sem cabecalho authorization',
      '{"authorization":"Basic abc"}|jwt malformado',
      '{"authorization":"Bearer lixo"}|jwt malformado',
      'isto nao e json|cabecalho ilegivel',
      '[1,2]|cabecalho ilegivel',
      '{"authorization":"Bearer a.!!!.c"}|cabecalho ilegivel',
      'ANON_SEM_SUB|jwt sem sub',
      'SUB_INEXISTENTE|sub inexistente em auth.users',
      'SUB_NAO_UUID|cabecalho ilegivel',
      'PAYLOAD_NAO_JSON|cabecalho ilegivel']
  loop
    v_i := v_i + 1;
    v_hdr := split_part(v_j, '|', 1);
    v_hdr := case v_hdr
      when 'ANON_SEM_SUB'      then jsonb_build_object('authorization', 'Bearer ' || teste_jwt_d16('{"role":"anon"}'))::text
      when 'SUB_INEXISTENTE'   then jsonb_build_object('authorization', 'Bearer ' || teste_jwt_d16('{"sub":"00000000-0000-0000-0000-0000000fffff","role":"authenticated"}'))::text
      when 'SUB_NAO_UUID'      then jsonb_build_object('authorization', 'Bearer ' || teste_jwt_d16('{"sub":"nao-e-uuid","role":"authenticated"}'))::text
      when 'PAYLOAD_NAO_JSON'  then jsonb_build_object('authorization', 'Bearer a.' || teste_b64u_d16('isto nao e json') || '.c')::text
      else v_hdr end;
    v_nome := v_c || '/api-nid' || v_i || '-0224.pdf';
    insert into storage.objects (bucket_id, name, metadata) values ('documentos', v_nome, '{"size": 3}');
    v_res := teste_api_apaga_d16(v_hdr, v_nome);
    select * into v_ev from evento_auditoria where acao = 'documento_original_apagado' and antes->>'caminho' = v_nome;
    perform teste_assert_d16(v_res = 'ok:1' and not exists (select 1 from storage.objects where name = v_nome)
      and v_ev.ator = 'storage:nao_identificado' and v_ev.antes->>'ator_motivo' = split_part(v_j, '|', 2),
      format('cabeçalho "%s": o DELETE segue e o ator é storage:nao_identificado, motivo "%s"', split_part(v_j, '|', 1), split_part(v_j, '|', 2)),
      v_res || ' ' || coalesce(v_ev.ator, 'sem evento') || ' / ' || coalesce(v_ev.antes->>'ator_motivo', 'sem motivo'));
    if v_j like 'SUB_NAO_UUID|%' then
      perform teste_assert_d16(v_ev.antes->>'sub_alegado' = 'nao-e-uuid', 'sub que não é uuid: o texto alegado fica em antes.sub_alegado (evidência)', coalesce(v_ev.antes::text, 'sem evento'));
    end if;
    if v_j like 'SUB_INEXISTENTE|%' then
      perform teste_assert_d16(v_ev.antes->>'sub_alegado' = '00000000-0000-0000-0000-0000000fffff', 'sub inexistente: o sub alegado fica em antes.sub_alegado (evidência)', coalesce(v_ev.antes::text, 'sem evento'));
    end if;
  end loop;

  -- JWT de service_role: o n8n nunca apaga do bucket (só POST com x-upsert); quem apaga com a chave é uma pessoa não identificada.
  v_nome := v_c || '/api-servico-0224.pdf';
  insert into storage.objects (bucket_id, name, metadata) values ('documentos', v_nome, '{"size": 3}');
  v_res := teste_api_apaga_d16(jsonb_build_object('authorization', 'Bearer ' || teste_jwt_d16('{"role":"service_role"}'))::text, v_nome);
  select * into v_ev from evento_auditoria where acao = 'documento_original_apagado' and antes->>'caminho' = v_nome;
  perform teste_assert_d16(v_res = 'ok:1' and v_ev.ator = 'storage:chave_de_servico', 'JWT de service_role: ator storage:chave_de_servico (o n8n não apaga; é uma pessoa com a chave, nunca "Sistema")', v_res || ' ' || coalesce(v_ev.ator, 'sem evento'));
  -- Um JWT de usuário que traz `role` service_role por engano de claim NÃO é o caso: o `sub` do usuário comum continua valendo (já coberto acima); aqui, o que importa é a
  -- garantia de que NENHUMA exclusão pela API (cabeçalho presente) saiu como sistema:*.
  select count(*) into v_n from evento_auditoria where acao = 'documento_original_apagado' and entidade_ref = 'caso:' || v_c and ator like 'sistema:%';
  perform teste_assert_d16(v_n = 0, 'nenhuma exclusão pela API virou sistema:*', v_n::text);
  -- O Histórico: `storage:nao_identificado` aparece COMO ESTÁ (não é anulado em "Sistema"); `storage:chave_de_servico` e `storage:sql_direto` também aparecem como estão.
  perform teste_como_d16(u_socio);
  select count(*) filter (where autor = 'storage:nao_identificado'), count(*) filter (where autor = 'storage:chave_de_servico') into v_n, v_n0
    from fn_historico_do_caso(v_c) where tipo = 'documento_original_apagado';
  perform teste_servico_d16();
  perform teste_assert_d16(v_n = 19 and v_n0 = 1,
    'no Histórico, as 19 exclusões não identificadas mostram storage:nao_identificado e a da chave de serviço storage:chave_de_servico (nenhuma vira autor nulo = "Sistema")', format('%s não identificadas, %s chave de serviço', v_n, v_n0));

  -- ---------------------------------------------------------------- 6. o Histórico do mandato
  raise notice '--- 6. o Histórico do mandato mostra a exclusão a quem lê o mandato, e só a ele ---';
  perform teste_como_d16(u_ana);
  select count(*), string_agg(autor, ',' order by autor) into v_n, v_txt from fn_historico_do_caso(v_a) where tipo = 'documento_original_apagado';
  perform teste_servico_d16();
  perform teste_assert_d16(v_n = 4 and v_txt = 'ana@0224.local,ana@0224.local,ana@0224.local,socio@0224.local',
    'a Analista alocada vê no Histórico as 4 exclusões do mandato, cada uma com quem apagou', format('%s: %s', v_n, v_txt));
  perform teste_como_d16(u_ana);
  select resumo into v_txt from fn_historico_do_caso(v_a) where tipo = 'documento_original_apagado' and referencia->>'arquivo' = 'hash-1-0224.pdf';
  perform teste_servico_d16();
  perform teste_assert_d16(v_txt = 'Original apagado do armazenamento: "BP Alfa.pdf" (1234 bytes)',
    'o resumo diz qual arquivo (o nome do cliente) e o tamanho, em português', v_txt);
  perform teste_como_d16(u_leo);
  select count(*) into v_n from fn_historico_do_caso(v_a) where tipo = 'documento_original_apagado';
  perform teste_servico_d16();
  perform teste_assert_d16(v_n = 4, 'a Leitura alocada também vê (lê o mandato)', v_n::text);
  perform teste_como_d16(u_xan);
  select count(*) into v_n from fn_historico_do_caso(v_a) where tipo = 'documento_original_apagado';
  perform teste_servico_d16();
  perform teste_assert_d16(v_n = 0, 'a Analista de OUTRO mandato não vê a exclusão do mandato A no Histórico', v_n::text);
  perform teste_como_d16(u_xan);
  select count(*), min(autor) into v_n, v_txt from fn_historico_do_caso(v_b) where tipo = 'documento_original_apagado';
  perform teste_servico_d16();
  perform teste_assert_d16(v_n = 1 and v_txt = 'storage:sql_direto', 'no mandato B a exclusão por SQL direto aparece com o autor storage:sql_direto (nunca nulo = "Sistema")', v_n || ' ' || coalesce(v_txt, 'null'));

  -- ---------------------------------------------------------------- 7. falha fechada
  raise notice '--- 7. falha fechada: se a trilha não puder ser gravada, o objeto não é apagado ---';
  insert into storage.objects (bucket_id, name, metadata) values ('documentos', v_a || '/fechada-0224.pdf', '{"size": 1}');
  alter table evento_auditoria add constraint teste_d16_sem_trilha check (acao <> 'documento_original_apagado') not valid;
  v_res := teste_tenta_d16(format($q$delete from storage.objects where bucket_id = 'documentos' and name = '%s/fechada-0224.pdf'$q$, v_a));
  alter table evento_auditoria drop constraint teste_d16_sem_trilha;
  perform teste_assert_d16(v_res = '23514' and exists (select 1 from storage.objects where name = v_a || '/fechada-0224.pdf'),
    'sem conseguir gravar a trilha, a exclusão inteira volta: o original continua lá', v_res);

  -- ---------------------------------------------------------------- 8. a sonda
  raise notice '--- 8. a sonda enxerga o gatilho ---';
  select count(*) filter (where not presente), count(*) into v_falta, v_n from fn_instalacao_conferir() where migration = '0224';
  perform teste_assert_d16(v_n = 9 and v_falta = 0, 'os 9 requisitos da 0224 estão no catálogo e presentes', format('%s requisitos, %s ausentes', v_n, v_falta));
  -- O gatilho da 0224 está na view da sonda. Os gatilhos DA PLATAFORMA em storage.objects (em produção: protect_objects_delete, update_objects_updated_at, ...) ficam fora do
  -- catálogo de propósito: não são nossos e o stub do run.sh nem os tem; este assert NÃO afirma nada sobre eles.
  select count(*) into v_n from instalacao_sonda_gatilho_original_apagado where gatilho = 'trg_auditar_original_apagado';
  perform teste_assert_d16(v_n = 1, 'o gatilho da 0224 está na view da sonda', v_n::text);
  alter table storage.objects disable trigger trg_auditar_original_apagado;
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'original_apagado_gatilho' and not presente;
  alter table storage.objects enable trigger trg_auditar_original_apagado;
  perform teste_assert_d16(v_n = 1, 'com o gatilho DESABILITADO a sonda acusa original_apagado_gatilho (a função sozinha sobrevive)', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'original_apagado_gatilho' and presente;
  perform teste_assert_d16(v_n = 1, 'religado, a sonda volta a ver o gatilho', v_n::text);
  -- a policy de update: desfeita (volta ao desenho da 0216), a sonda acusa; refeita, volta a ver.
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'original_apagado_update_so_socio' and presente;
  perform teste_assert_d16(v_n = 1, 'a sonda vê a policy de update só do Sócio', v_n::text);
  -- guarda a policy INSTALADA (o que a migration deixou) para devolvê-la igual: recriar o texto esperado esconderia uma migration que não a restringiu.
  select p.qual, p.with_check into v_pq, v_pw from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects' and p.policyname = 'documentos_update';
  drop policy documentos_update on storage.objects;
  create policy documentos_update on storage.objects for update to authenticated
    using (bucket_id = 'documentos' and ((select fn_eh_socio()) or fn_pode_ler_caso(fn_caso_da_chave_do_storage(name))))
    with check (bucket_id = 'documentos' and ((select fn_eh_socio()) or fn_pode_escrever_caso(fn_caso_da_chave_do_storage(name))));
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'original_apagado_update_so_socio' and not presente;
  drop policy documentos_update on storage.objects;
  execute format('create policy documentos_update on storage.objects for update to authenticated using (%s) with check (%s)', v_pq, v_pw);
  perform teste_assert_d16(v_n = 1, 'com a policy de update no desenho da 0216 (Analista alocado move) a sonda acusa', v_n::text);
  -- Policies PERMISSIVE somam com OR: uma SEGUNDA policy de UPDATE para authenticated (template do Studio) reabre o buraco, e a sonda tem de acusar mesmo com documentos_update certa.
  create policy teste_d16_extra_update on storage.objects for update to authenticated using (true);
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'original_apagado_update_so_socio' and not presente;
  drop policy teste_d16_extra_update on storage.objects;
  perform teste_assert_d16(v_n = 1, 'uma segunda policy permissiva de UPDATE em storage.objects faz a sonda acusar', v_n::text);
  create policy teste_d16_extra_all on storage.objects for all to public using (true);
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'original_apagado_update_so_socio' and not presente;
  drop policy teste_d16_extra_all on storage.objects;
  perform teste_assert_d16(v_n = 1, 'uma policy permissiva ALL para public em storage.objects também faz a sonda acusar', v_n::text);
  -- anon tem UPDATE em storage.objects em produção (medido: role_table_grants), e a chave anon é pública: uma policy para anon move o original sem login nenhum.
  create policy teste_d16_extra_anon on storage.objects for update to anon using (true);
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'original_apagado_update_so_socio' and not presente;
  drop policy teste_d16_extra_anon on storage.objects;
  perform teste_assert_d16(v_n = 1, 'uma policy permissiva de UPDATE para anon em storage.objects faz a sonda acusar', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'original_apagado_update_so_socio' and presente;
  perform teste_assert_d16(v_n = 1, 'removida a policy extra, a sonda volta a ver o update só do Sócio', v_n::text);
  -- o versionamento: ligado, ou a coluna ausente, a sonda acusa (regra 7: sem medição não passa).
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'original_apagado_sem_versionamento' and presente;
  perform teste_assert_d16(v_n = 1, 'a sonda vê o bucket documentos com versionamento DISABLED', v_n::text);
  update storage.buckets set versioning_status = 'ENABLED' where id = 'documentos';
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'original_apagado_sem_versionamento' and not presente;
  update storage.buckets set versioning_status = 'DISABLED' where id = 'documentos';
  perform teste_assert_d16(v_n = 1, 'com o versionamento ligado a sonda acusa', v_n::text);
  alter table storage.buckets drop column versioning_status;
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'original_apagado_sem_versionamento' and not presente;
  alter table storage.buckets add column versioning_status text default 'DISABLED';
  perform teste_assert_d16(v_n = 1, 'sem a coluna versioning_status nada foi medido e a sonda acusa (não passa vazia)', v_n::text);
  -- a policy de INSERT de evento_auditoria: no desenho da 0216 (sem excluir a ação) a sonda acusa; devolvida a INSTALADA, volta a ver.
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'original_apagado_insert_sem_forja' and presente;
  perform teste_assert_d16(v_n = 1, 'a sonda vê a policy de INSERT que barra a ação documento_original_apagado', v_n::text);
  select p.with_check into v_pw from pg_policies p where p.schemaname = 'public' and p.tablename = 'evento_auditoria' and p.policyname = 'evento_auditoria_insert';
  drop policy evento_auditoria_insert on evento_auditoria;
  create policy evento_auditoria_insert on evento_auditoria for insert to authenticated with check (fn_pode_escrever_evento(entidade_ref));
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'original_apagado_insert_sem_forja' and not presente;
  drop policy evento_auditoria_insert on evento_auditoria;
  execute format('create policy evento_auditoria_insert on evento_auditoria for insert to authenticated with check (%s)', v_pw);
  perform teste_assert_d16(v_n = 1, 'com a policy de INSERT no desenho da 0216 a sonda acusa', v_n::text);
  create policy teste_d16_extra_insert on evento_auditoria for insert to authenticated with check (true);
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'original_apagado_insert_sem_forja' and not presente;
  drop policy teste_d16_extra_insert on evento_auditoria;
  perform teste_assert_d16(v_n = 1, 'uma segunda policy permissiva de INSERT em evento_auditoria faz a sonda acusar', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'original_apagado_insert_sem_forja' and presente;
  perform teste_assert_d16(v_n = 1, 'removida a policy extra, a sonda volta a ver o insert fechado', v_n::text);

  -- Marcadores do Histórico: cada um ocorre UMA vez só no corpo publicado (em código), e cada um acusa sozinho.
  select count(*) into v_n from fn_instalacao_conferir() where chave in ('historico_mostra_original_apagado', 'historico_lista_ev_original_apagado') and presente;
  perform teste_assert_d16(v_n = 2, 'os dois marcadores do Histórico (ramo e lista ev) estão presentes', v_n::text);
  select (length(d) - length(replace(d, 'from ev e where e.acao = ''documento_original_apagado''', ''))) / length('from ev e where e.acao = ''documento_original_apagado'''),
         (length(d) - length(replace(d, '''entidade_fundida'', ''documento_original_apagado'')', ''))) / length('''entidade_fundida'', ''documento_original_apagado'')')
    into v_n, v_n0 from (select pg_get_functiondef('fn_historico_do_caso(uuid,int,timestamptz,text)'::regprocedure) as d) x;
  perform teste_assert_d16(v_n = 1 and v_n0 = 1, 'cada marcador ocorre uma vez só no corpo da função', format('ramo %s, lista %s', v_n, v_n0));
  -- O índice do gatilho existe (a busca por arquivo_ref a cada exclusão, 2x por objeto, era seq scan).
  select count(*) into v_n from pg_indexes where schemaname = 'public' and tablename = 'documento_versao' and indexdef ~ '\(arquivo_ref\)';
  perform teste_assert_d16(v_n = 1, 'documento_versao tem índice em arquivo_ref (o gatilho de exclusão o usa)', v_n::text);

  -- ---------------------------------------------------------------- 9. mover/sobrescrever só para Sócio
  raise notice '--- 9. mover/sobrescrever original (UPDATE) é só do Sócio; o upload do Analista alocado continua ---';
  perform teste_como_d16(u_ana);
  v_res := teste_tenta_d16(format($q$update storage.objects set name = '%s/movido-0224.pdf' where bucket_id = 'documentos' and name = '%s/mover-0224.pdf'$q$, v_a, v_a));
  perform teste_servico_d16();
  perform teste_assert_d16(v_res in ('ok:0', '42501') and exists (select 1 from storage.objects where name = v_a || '/mover-0224.pdf'),
    'a Analista alocada NÃO move o original (UPDATE do name)', v_res);
  perform teste_como_d16(u_ana);
  v_res := teste_tenta_d16(format($q$update storage.objects set metadata = '{"size": 999}' where bucket_id = 'documentos' and name = '%s/mover-0224.pdf'$q$, v_a));
  perform teste_servico_d16();
  perform teste_assert_d16(v_res in ('ok:0', '42501') and (select metadata->>'size' from storage.objects where name = v_a || '/mover-0224.pdf') = '7',
    'a Analista alocada NÃO sobrescreve o original (UPDATE do conteúdo/metadata)', v_res);
  perform teste_como_d16(u_leo);
  v_res := teste_tenta_d16(format($q$update storage.objects set name = '%s/movido-0224.pdf' where bucket_id = 'documentos' and name = '%s/mover-0224.pdf'$q$, v_a, v_a));
  perform teste_servico_d16();
  perform teste_assert_d16(v_res in ('ok:0', '42501') and exists (select 1 from storage.objects where name = v_a || '/mover-0224.pdf'),
    'a Leitura NÃO move o original', v_res);
  perform teste_como_d16(u_socio);
  v_res := teste_tenta_d16(format($q$update storage.objects set name = '%s/movido-0224.pdf' where bucket_id = 'documentos' and name = '%s/mover-0224.pdf'$q$, v_a, v_a));
  perform teste_servico_d16();
  perform teste_assert_d16(v_res = 'ok:1' and exists (select 1 from storage.objects where name = v_a || '/movido-0224.pdf'),
    'o Sócio move o original', v_res);
  perform teste_como_d16(u_ana);
  v_res := teste_tenta_d16(format($q$insert into storage.objects (bucket_id, name, metadata) values ('documentos', '%s/upload-0224.pdf', '{"size": 1}')$q$, v_a));
  perform teste_servico_d16();
  perform teste_assert_d16(v_res = 'ok:1', 'o upload (INSERT) da Analista alocada continua permitido', v_res);

  -- ---------------------------------------------------------------- 10. versionamento
  raise notice '--- 10. versionamento: delete marker e versão arquivada não são exclusão do usuário; coluna ausente não derruba o gatilho ---';
  select count(*) into v_n0 from evento_auditoria where acao = 'documento_original_apagado';
  insert into storage.objects (bucket_id, name, metadata, is_delete_marker) values ('documentos', v_c || '/marcador-0224.pdf', '{"size": 1}', true);
  insert into storage.objects (bucket_id, name, metadata, archived_at) values ('documentos', v_c || '/arquivada-0224.pdf', '{"size": 1}', now());
  delete from storage.objects where name in (v_c || '/marcador-0224.pdf', v_c || '/arquivada-0224.pdf');
  select count(*) into v_n from evento_auditoria where acao = 'documento_original_apagado';
  perform teste_assert_d16(v_n = v_n0, 'apagar delete marker ou versão arquivada (ciclo de vida do versionamento) não vira evento de exclusão do usuário', format('%s -> %s', v_n0, v_n));
  alter table storage.objects drop column is_delete_marker, drop column archived_at;
  insert into storage.objects (bucket_id, name, metadata) values ('documentos', v_c || '/sem-colunas-0224.pdf', '{"size": 1}');
  v_res := teste_tenta_d16(format($q$delete from storage.objects where name = '%s/sem-colunas-0224.pdf'$q$, v_c));
  alter table storage.objects add column is_delete_marker boolean default false, add column archived_at timestamptz;
  select count(*) into v_n from evento_auditoria where acao = 'documento_original_apagado' and antes->>'caminho' = v_c || '/sem-colunas-0224.pdf';
  perform teste_assert_d16(v_res = 'ok:1' and v_n = 1, 'sem as colunas do versionamento no Storage, o gatilho continua gravando a exclusão', v_res || ' / ' || v_n);

  -- ---------------------------------------------------------------- 11. a trilha não se forja pela porta da frente
  raise notice '--- 11. ninguém insere à mão a ação documento_original_apagado; outras ações seguem; o gatilho continua gravando ---';
  perform teste_como_d16(u_ana);
  v_res := teste_tenta_d16(format($q$insert into evento_auditoria (ator, acao, entidade_ref, antes) values ('socio@0224.local', 'documento_original_apagado', 'caso:%s', '{"nome_original": "FORJADO.pdf"}')$q$, v_a));
  perform teste_servico_d16();
  perform teste_assert_d16(v_res = '42501', 'a Analista alocada NÃO insere à mão a exclusão de original (ator livre = forja do Sócio)', v_res);
  perform teste_como_d16(u_socio);
  v_res := teste_tenta_d16(format($q$insert into evento_auditoria (ator, acao, entidade_ref, antes) values ('socio@0224.local', 'documento_original_apagado', 'caso:%s', '{"nome_original": "FORJADO.pdf"}')$q$, v_a));
  perform teste_servico_d16();
  perform teste_assert_d16(v_res = '42501', 'nem o Sócio insere à mão a exclusão de original (só o gatilho grava essa ação)', v_res);
  perform teste_como_d16(u_xan);
  v_res := teste_tenta_d16(format($q$insert into evento_auditoria (ator, acao, entidade_ref, antes) values ('x@0224.local', 'documento_original_apagado', 'caso:%s', '{}')$q$, v_b));
  perform teste_servico_d16();
  perform teste_assert_d16(v_res = '42501', 'nem a Analista alocada no próprio mandato B', v_res);
  perform teste_como_d16(u_ana);
  perform teste_como_d16(u_ana);
  v_res := teste_tenta_d16(format($q$insert into evento_auditoria (ator, acao, entidade_ref) values ('ana@0224.local', 'teste_0224_outra', 'caso:%s')$q$, v_a));
  perform teste_servico_d16();
  perform teste_assert_d16(v_res = 'ok:1', 'a policy não é larga demais: a Analista alocada continua inserindo OUTRAS ações no mandato dela', v_res);
  perform teste_como_d16(u_socio);
  select count(*) into v_n from fn_historico_do_caso(v_a) where resumo like '%FORJADO%';
  perform teste_servico_d16();
  perform teste_assert_d16(v_n = 0, 'o Histórico do mandato não mostra a exclusão forjada', v_n::text);
  select count(*) into v_n from evento_auditoria where acao = 'documento_original_apagado' and antes->>'nome_original' = 'FORJADO.pdf';
  perform teste_assert_d16(v_n = 0, 'nenhuma linha forjada em evento_auditoria', v_n::text);
  -- O gatilho (SECURITY DEFINER do dono, que no Supabase tem BYPASSRLS) continua gravando com a policy fechada: as seções 1, 2 e 5b apagam e acham o evento.
  -- NÃO testável aqui: dono sem BYPASSRLS (o stub local roda como superusuário); em produção o `postgres` tem BYPASSRLS (medido, só leitura).

  -- ---------------------------------------------------------------- limpeza
  delete from caso where nome like '0224 —%';
  delete from storage.objects where name like '%-0224.pdf';
  delete from auth.users where id in (u_socio, u_ana, u_leo, u_nil, u_xan);
  delete from evento_auditoria where acao in ('documento_original_apagado', 'teste_0224_outra');

  raise notice 'EXECUCOES=% FALHAS=%', current_setting('d16.execucoes', true), coalesce(current_setting('d16.falhas', true), '0');
  if current_setting('d16.medindo', true) is distinct from 'on' then
    raise notice 'TODOS OS TESTES DA EXCLUSÃO AUDITADA PASSARAM';
  end if;
end $$;
