-- =============================================================================
-- 0224 — O ORIGINAL QUE O ANALISTA APAGAVA SEM TRILHA (D16): toda exclusão no bucket `documentos` deixa evento e aparece no Histórico
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md): os números por guarda desligada estão no cabeçalho de
-- Supabase/migrations/0224_o_original_que_o_analista_apagava_sem_trilha.sql ("MEDIÇÃO NÃO-VAZIA").
--
-- COMO RODA. Cada usuário é um JWT (`request.jwt.claims`) mais `set local role authenticated`: o papel do navegador/da API do Storage.
-- Superusuário ignora RLS e passaria sobre qualquer policy. A "API do Storage" aqui é o DELETE em storage.objects COMO authenticated (o
-- stub do run.sh não tem o gatilho protect_objects_delete da plataforma, que só recusa SQL direto em produção).
--
-- O QUE AFIRMA (comportamento, não mecanismo):
--   1. Analista alocada apaga original do mandato dela: o objeto some e fica UM evento, com o e-mail dela como ator, o mandato certo,
--      o nome original e o tamanho em `antes`, e `depois` nulo;
--   2. Sócio apaga: evento com o e-mail do Sócio;
--   3. quem não pode apagar (Analista de outro mandato, Leitura, sem papel) NÃO apaga e NÃO deixa evento (a tentativa barrada não é exclusão);
--   4. objeto de OUTRO bucket apagado: nenhum evento; vários objetos num DELETE só: um evento por objeto;
--   5. conexão de serviço apaga: ator `sistema:storage`; objeto solto (chave sem mandato) apagado: evento `storage:documentos/<chave>`, não some;
--   6. o Histórico do mandato mostra a exclusão a quem lê o mandato (Analista alocada, Leitura) e NÃO a quem não lê;
--   7. falha fechada: se a trilha não puder ser gravada, o objeto NÃO é apagado;
--   8. a sonda enxerga o gatilho: 4 requisitos da 0224 presentes, e desabilitar o gatilho a faz acusar.
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

-- Volta a CONEXÃO DE SERVIÇO: superusuário SEM JWT (o n8n e o SQL Editor chegam assim).
create or replace function teste_servico_d16() returns void
language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end $$;

-- Limpeza de rodada anterior (o teste é reexecutável).
delete from caso where nome like '0224 —%';
delete from storage.objects where name like '%-0224.pdf';
delete from auth.users where id in ('00000000-0000-0000-0000-00000000d161', '00000000-0000-0000-0000-00000000d162',
  '00000000-0000-0000-0000-00000000d163', '00000000-0000-0000-0000-00000000d164', '00000000-0000-0000-0000-00000000d165');
delete from evento_auditoria where acao = 'documento_original_apagado';

do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000000d161';   -- Sócio
  u_ana   uuid := '00000000-0000-0000-0000-00000000d162';   -- Analista, alocada em A
  u_leo   uuid := '00000000-0000-0000-0000-00000000d163';   -- Leitura, alocado em A
  u_nil   uuid := '00000000-0000-0000-0000-00000000d164';   -- SEM papel
  u_xan   uuid := '00000000-0000-0000-0000-00000000d165';   -- Analista, alocado só em B
  v_a uuid; v_b uuid; v_r jsonb; v_res text; v_n int; v_n0 int; v_ev record; v_txt text; v_falta int;
  v_doc_a uuid;
begin
  -- ---------------------------------------------------------------- montagem (conexão de serviço)
  insert into auth.users (id, email) values
    (u_socio, 'socio@0224.local'), (u_ana, 'ana@0224.local'), (u_leo, 'leo@0224.local'),
    (u_nil, 'nil@0224.local'), (u_xan, 'xan@0224.local');
  v_a := fn_upsert_caso('0224 — mandato A');
  v_b := fn_upsert_caso('0224 — mandato B');
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
    ('relatorios', v_a || '/outro-bucket-0224.pdf', '{"size": 5}');

  -- ---------------------------------------------------------------- 1. Analista alocada apaga o original do mandato dela
  raise notice '--- 1. a Analista alocada apaga: o objeto some e fica UM evento, com ela como ator e o mandato certo ---';
  perform teste_como_d16(u_ana);
  v_res := teste_tenta_d16(format($q$delete from storage.objects where bucket_id = 'documentos' and name = '%s/hash-1-0224.pdf'$q$, v_a));
  perform teste_servico_d16();
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
  perform teste_como_d16(u_socio);
  v_res := teste_tenta_d16(format($q$delete from storage.objects where bucket_id = 'documentos' and name = '%s/hash-2-0224.pdf'$q$, v_a));
  perform teste_servico_d16();
  select * into v_ev from evento_auditoria where acao = 'documento_original_apagado' and antes->>'caminho' = v_a || '/hash-2-0224.pdf';
  perform teste_assert_d16(v_res = 'ok:1' and v_ev.ator = 'socio@0224.local' and v_ev.entidade_ref = 'caso:' || v_a,
    'o Sócio apaga e a exclusão é auditada com o e-mail dele no mandato certo', v_res || ' ' || coalesce(v_ev.ator, 'sem evento'));

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
  perform teste_como_d16(u_ana);
  v_res := teste_tenta_d16(format($q$delete from storage.objects where bucket_id = 'documentos' and name in ('%s/hash-4-0224.pdf', '%s/hash-5-0224.pdf')$q$, v_a, v_a));
  perform teste_servico_d16();
  select count(*) into v_n from evento_auditoria where acao = 'documento_original_apagado' and ator = 'ana@0224.local'
    and antes->>'caminho' in (v_a || '/hash-4-0224.pdf', v_a || '/hash-5-0224.pdf');
  perform teste_assert_d16(v_res = 'ok:2' and v_n = 2, 'dois objetos num DELETE só: um evento para cada um', v_res || ' / ' || v_n);

  -- ---------------------------------------------------------------- 5. conexão de serviço e objeto sem mandato
  raise notice '--- 5. a conexão de serviço apaga como sistema:storage; objeto solto também é gravado ---';
  v_res := teste_tenta_d16(format($q$delete from storage.objects where bucket_id = 'documentos' and name = '%s/hash-b-0224.pdf'$q$, v_b));
  select * into v_ev from evento_auditoria where acao = 'documento_original_apagado' and entidade_ref = 'caso:' || v_b;
  perform teste_assert_d16(v_res = 'ok:1' and v_ev.ator = 'sistema:storage', 'a conexão de serviço (n8n, SQL Editor) apaga e o ator é sistema:storage, no mandato B', v_res || ' ' || coalesce(v_ev.ator, 'sem evento'));
  v_res := teste_tenta_d16($q$delete from storage.objects where bucket_id = 'documentos' and name = 'solto-0224.pdf'$q$);
  select * into v_ev from evento_auditoria where acao = 'documento_original_apagado' and entidade_ref = 'storage:documentos/solto-0224.pdf';
  perform teste_assert_d16(v_res = 'ok:1' and v_ev.id is not null and v_ev.antes->>'nome_original' is null,
    'objeto sem mandato na chave: a exclusão é gravada do mesmo jeito (storage:documentos/<chave>), sem nome inventado', v_res);

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
  perform teste_assert_d16(v_n = 1 and v_txt is null, 'no mandato B a exclusão da conexão de serviço aparece com autor nulo (a tela escreve "Sistema")', v_n || ' ' || coalesce(v_txt, 'null'));

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
  perform teste_assert_d16(v_n = 4 and v_falta = 0, 'os 4 requisitos da 0224 estão no catálogo e presentes', format('%s requisitos, %s ausentes', v_n, v_falta));
  -- Todo gatilho do schema storage tem de estar coberto pela view da sonda: sonda_ve_gatilho.test.sql exclui `storage.%` da igualdade de conjuntos
  -- (o tipo `gatilho` não enxerga fora de public), e esta é a igualdade que sobra para o schema storage.
  select count(*) into v_n from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace s on s.oid = c.relnamespace
   where s.nspname = 'storage' and not t.tgisinternal and t.tgname not in (select gatilho from instalacao_sonda_gatilho_original_apagado);
  perform teste_assert_d16(v_n = 0, 'nenhum gatilho do schema storage fica fora do catálogo da sonda (a exclusão de original não é o único risco de trilha calada)', v_n::text);
  alter table storage.objects disable trigger trg_auditar_original_apagado;
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'original_apagado_gatilho' and not presente;
  alter table storage.objects enable trigger trg_auditar_original_apagado;
  perform teste_assert_d16(v_n = 1, 'com o gatilho DESABILITADO a sonda acusa original_apagado_gatilho (a função sozinha sobrevive)', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'original_apagado_gatilho' and presente;
  perform teste_assert_d16(v_n = 1, 'religado, a sonda volta a ver o gatilho', v_n::text);

  -- ---------------------------------------------------------------- limpeza
  delete from caso where nome like '0224 —%';
  delete from storage.objects where name like '%-0224.pdf';
  delete from auth.users where id in (u_socio, u_ana, u_leo, u_nil, u_xan);
  delete from evento_auditoria where acao = 'documento_original_apagado';

  raise notice 'EXECUCOES=% FALHAS=%', current_setting('d16.execucoes', true), coalesce(current_setting('d16.falhas', true), '0');
  if current_setting('d16.medindo', true) is distinct from 'on' then
    raise notice 'TODOS OS TESTES DA EXCLUSÃO AUDITADA PASSARAM';
  end if;
end $$;
