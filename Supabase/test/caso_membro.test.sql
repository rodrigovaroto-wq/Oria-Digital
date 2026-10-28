-- =============================================================================
-- 0215 — O mandato só é visto por quem trabalha nele: membro + administrador
--
-- (revisão independente, 27/10/2026) A BARREIRA DE `administrador` E `caso_membro` É A RLS, NÃO A FALTA DE GRANT: no
-- projeto existente o default privilege ainda concede ALL a anon/authenticated em tabela nova até 30/10/2026. O passo
-- 6b CONCEDE temporariamente o privilégio ao authenticated e exige que a RLS negue assim mesmo; o passo 1 conta só
-- usuários ATIVOS (não confirmado, banido, apagado e anônimo não viram membros); o 2 recusa e-mail duplicado e
-- p_ativo nulo; o 8 mede a sonda nova (`rls`, `execucao` sem marcador).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número de asserts e o de reprovações com cada correção desligada estão no
-- cabeçalho de Supabase/migrations/0215_o_mandato_que_todo_usuario_lia.sql.
--
-- O QUE MEDE (comportamento, sempre como `authenticated` com o jwt de cada usuário — `set local role` +
-- `request.jwt.claims`, que é o que o PostgREST faz; a ficha rls-so-select-passa-no-superusuario existe porque o
-- superusuário ignora RLS e tudo passaria): (1) a transição dá a todo usuário todo caso que já existia, e só isso;
-- (2) quem cria um caso vira membro dele e de mais nenhum; (3) o administrador é membro de tudo sem constar em
-- caso_membro; (4) o usuário lê só as próprias pertinências e só o administrador lê `administrador`; (5) só o
-- administrador atribui e retira membros, e deixa evento; (6) ninguém logado, nem administrador, executa
-- fn_administrador_definir; (7) caso criado sem identidade (n8n) nasce sem membro; (8) a sonda enxerga o EXECUTE
-- indevido. Este teste NÃO mede que as demais tabelas escondam o caso de quem não é membro: isso é a 0216.
--
-- Montagem: usuários e casos como superusuário (auth.uid() nulo). O "service_role" do passo 7 é o superusuário sem
-- claims: no banco de teste o papel service_role não tem BYPASSRLS como o do Supabase, então não serve de proxy.
-- Os dados nascem num caso_membro que já passou pela transição vazia da 0215 (zero usuários na época), por isso o
-- passo 1 chama a função de backfill sobre usuários e casos montados AQUI.
-- =============================================================================

create or replace function teste_assert_0215(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_cond then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- "este usuário é membro deste caso?", perguntado COMO ele (authenticated + o jwt dele), do jeito que a policy perguntará.
create or replace function teste_membro_0215(p_usuario uuid, p_caso uuid) returns boolean language plpgsql as $$
declare v boolean;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_usuario, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v := fn_eh_membro(p_caso);
  reset role;
  return v;
end $$;

-- limpeza de rodada anterior (cascata leva caso_membro e administrador)
delete from caso where nome like '0215 — %';
delete from auth.users where email like '%@0215.teste';

do $$
declare
  ua constant uuid := '0215a000-0000-0000-0000-00000000000a';
  ub constant uuid := '0215a000-0000-0000-0000-00000000000b';
  uc constant uuid := '0215a000-0000-0000-0000-00000000000c';
  ud constant uuid := '0215a000-0000-0000-0000-00000000000d';   -- convite não confirmado
  ue constant uuid := '0215a000-0000-0000-0000-00000000000e';   -- banido (banned_until no futuro)
  uf constant uuid := '0215a000-0000-0000-0000-00000000000f';   -- anônimo
  ug constant uuid := '0215a000-0000-0000-0000-000000000010';   -- apagado (deleted_at)
  uh constant uuid := '0215a000-0000-0000-0000-000000000011';   -- ban JÁ vencido: ativo
  ui constant uuid := '0215a000-0000-0000-0000-000000000012';
  uj constant uuid := '0215a000-0000-0000-0000-000000000013';   -- ATIVO, mas entra DEPOIS da transição
  v_x uuid; v_y uuid; v_z uuid; v_antigo uuid; v_ativos int;
  v_n bigint; v_m bigint; v_err text; v_b boolean; v_ev int;
  v_casos int; v_usuarios int;
begin
  raise notice '--- 0. o catálogo da sonda tem os requisitos da 0215 e nenhum está ausente ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0215';
  perform teste_assert_0215(v_n = 25, 'a sonda tem os 25 requisitos da 0215', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0215' and not presente;
  perform teste_assert_0215(v_n = 0, 'nenhum requisito da 0215 ausente',
    (select string_agg(chave || ': ' || detalhe, ' | ') from fn_instalacao_conferir() where migration = '0215' and not presente));

  raise notice '--- 1. a transição: todo usuário x todo caso que JÁ existia ---';
  insert into auth.users (id, email, email_confirmed_at, banned_until, deleted_at, is_anonymous) values
    (ua, 'a@0215.teste', now(), null, null, false),
    (ub, 'b@0215.teste', now(), null, null, false),
    (uc, 'c@0215.teste', now(), null, null, false),
    (ud, 'd@0215.teste', null,  null, null, false),
    (ue, 'e@0215.teste', now(), now() + interval '30 days', null, false),
    (uf, 'f@0215.teste', now(), null, null, true),
    (ug, 'g@0215.teste', now(), null, now(), false),
    (uh, 'h@0215.teste', now(), now() - interval '1 day', null, false);
  v_antigo := fn_upsert_caso('0215 — caso antigo');          -- superusuário: auth.uid() nulo, nasce sem membro
  select count(*) into v_casos from caso;
  select count(*) into v_usuarios from auth.users;
  select count(*) into v_ativos from fn_usuarios_ativos();
  perform teste_assert_0215(v_casos >= 3 and v_usuarios = 8 and v_ativos = 4,
    'o arranjo não é vazio: casos das fixtures + o antigo, oito usuários dos quais QUATRO ativos (a, b, c e o de ban vencido)',
    v_casos || ' casos, ' || v_usuarios || ' usuários, ' || v_ativos || ' ativos');
  select count(*) into v_n from caso_membro where usuario_id in (ua, ub, uc, ud, ue, uf, ug, uh);
  perform teste_assert_0215(v_n = 0, 'antes da transição os usuários novos não são membros de nada', v_n::text);

  v_n := fn_caso_membro_backfill_0215();
  perform teste_assert_0215(v_n = v_casos * v_ativos, 'a transição devolve usuários ATIVOS x casos',
    v_n || ' de ' || v_casos * v_ativos);
  select count(*) into v_m from (
    select c.id, u from caso c cross join fn_usuarios_ativos() u
    except select caso_id, usuario_id from caso_membro) f;
  perform teste_assert_0215(v_m = 0, 'o produto cartesiano dos ativos está completo: nenhum par ativo/caso faltando', v_m::text);
  select count(*) into v_m from caso_membro where por = 'migracao:0215';
  perform teste_assert_0215(v_m = v_casos * v_ativos, 'e só ele: toda linha da transição é par ativo/caso, marcada migracao:0215', v_m::text);
  select count(*) into v_m from caso_membro where usuario_id in (ud, ue, uf, ug);
  perform teste_assert_0215(v_m = 0, 'convite não confirmado, banido, anônimo e apagado NÃO viram membros', v_m::text);
  perform teste_assert_0215(exists (select 1 from caso_membro where usuario_id = uh and caso_id = v_antigo),
    'e o ban JÁ vencido é usuário ativo: vira membro');
  perform teste_assert_0215(fn_caso_membro_backfill_0215() = 0, 'a transição é idempotente (segunda chamada: 0 linhas novas)');
  -- A TRANSIÇÃO CONFERE O PRÓPRIO RESULTADO: se algo descarta linhas (aqui, um gatilho BEFORE INSERT que devolve null
  -- para um usuário novo — o que uma RLS ou um gatilho de produção também faria), ela morre em 55000 em vez de
  -- devolver um número menor sem que ninguém o compare ao esperado.
  begin
    insert into auth.users (id, email, email_confirmed_at) values (ui, 'i@0215.teste', now());
    create function teste_descarta_0215() returns trigger language plpgsql as $f$ begin return null; end $f$;
    create trigger teste_descarta_0215 before insert on caso_membro for each row
      when (new.usuario_id = '0215a000-0000-0000-0000-000000000012') execute function teste_descarta_0215();
    v_err := null;
    begin perform fn_caso_membro_backfill_0215();
    exception when others then v_err := sqlstate; end;
    raise exception 'rollback_0215';
  exception when others then if sqlerrm <> 'rollback_0215' then raise; end if; end;
  perform teste_assert_0215(v_err = '55000', 'a transição que insere MENOS que o esperado levanta 55000 (não devolve o número menor calada)', v_err);
  select count(*) into v_n from administrador;
  perform teste_assert_0215(v_n = 0, 'ninguém vira administrador sozinho', v_n::text);
  -- EFEITO DITO NO CABEÇALHO (regra 1): só os usuários ativos DE HOJE herdam os mandatos antigos. Quem entra na equipe
  -- depois da transição chega com a lista vazia — sem erro nenhum — até um administrador atribuí-lo.
  insert into auth.users (id, email, email_confirmed_at) values (uj, 'j@0215.teste', now());
  select count(*) into v_n from caso_membro where usuario_id = uj;
  perform teste_assert_0215(v_n = 0 and not teste_membro_0215(uj, v_antigo),
    'quem entra DEPOIS da transição (usuário ativo novo) NÃO é membro de mandato antigo nenhum até ser atribuído', v_n::text);

  raise notice '--- 2. o primeiro administrador, pelo SQL do dono ---';
  -- evento_auditoria é append-only: o uuid de C é fixo, então se conta o que ESTA rodada acrescentou (o teste é reexecutável)
  select count(*) into v_ev from evento_auditoria where acao = 'administrador_definido' and entidade_ref = 'usuario:' || uc;
  perform teste_assert_0215(fn_administrador_definir('C@0215.TESTE', true), 'fn_administrador_definir promove (e-mail sem diferenciar caixa)');
  perform teste_assert_0215(exists (select 1 from administrador where usuario_id = uc), 'C consta em administrador');
  perform teste_assert_0215(not fn_administrador_definir('c@0215.teste', true), 'promover quem já é administrador não muda nada (false)');
  v_err := null;
  begin perform fn_administrador_definir('ninguem@0215.teste', true);
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0215(v_err = 'P0002', 'e-mail sem usuário: recusa com mensagem, não promove ninguém', v_err);
  select count(*) - v_ev into v_n from evento_auditoria where acao = 'administrador_definido' and entidade_ref = 'usuario:' || uc;
  perform teste_assert_0215(v_n = 1, 'a promoção deixou UM evento (a repetida não grava outro)', v_n::text);
  -- p_ativo nulo cairia no ramo de REMOVER (if null não é verdadeiro) e despromoveria C sem querer
  v_err := null;
  begin perform fn_administrador_definir('c@0215.teste', null);
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0215(v_err = '22004' and exists (select 1 from administrador where usuario_id = uc),
    'p_ativo nulo é recusado (22004) e C continua administrador', v_err);
  -- o e-mail pode repetir no Supabase real (conta com senha + conta SSO): recusa, não promove uma ao acaso
  insert into auth.users (id, email) values ('0215a000-0000-0000-0000-0000000000a1', 'dup@0215.teste'),
                                           ('0215a000-0000-0000-0000-0000000000a2', 'DUP@0215.teste');
  v_err := null;
  begin perform fn_administrador_definir('dup@0215.teste', true);
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0215(v_err = '21000' and not exists (select 1 from administrador where usuario_id::text like '0215a000-0000-0000-0000-0000000000a%'),
    'e-mail que aparece em dois usuários é recusado (21000) e ninguém é promovido', v_err);

  raise notice '--- 3. quem cria o caso vira membro dele, e de mais nenhum ---';
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_x := fn_upsert_caso('0215 — caso X', 'portal:navegador');
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', ub, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_y := fn_upsert_caso('0215 — caso Y', 'portal:navegador');
  reset role;
  perform teste_assert_0215(v_x is not null and v_y is not null and v_x <> v_y, 'A criou X e B criou Y como authenticated');
  perform teste_assert_0215((select array_agg(usuario_id) from caso_membro where caso_id = v_x) = array[ua],
    'X tem exatamente um membro: A, o criador');
  perform teste_assert_0215((select array_agg(usuario_id) from caso_membro where caso_id = v_y) = array[ub],
    'Y tem exatamente um membro: B, o criador');
  perform teste_assert_0215((select por from caso_membro where caso_id = v_x and usuario_id = ua) = 'criador', 'a linha do criador diz por = criador');

  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform teste_assert_0215(fn_eh_membro(v_x), 'A é membro de X (fn_eh_membro)');
  perform teste_assert_0215(not fn_eh_membro(v_y), 'A NÃO é membro de Y (fn_eh_membro)');
  perform teste_assert_0215(not fn_eh_admin(), 'A não é administrador');
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', ub, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform teste_assert_0215(fn_eh_membro(v_y) and not fn_eh_membro(v_x), 'B é membro de Y e não de X');
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform teste_assert_0215(fn_eh_admin(), 'C é administrador');
  perform teste_assert_0215(fn_eh_membro(v_x) and fn_eh_membro(v_y), 'C, administrador, é membro de X e de Y');
  reset role;
  perform teste_assert_0215(not exists (select 1 from caso_membro where usuario_id = uc and caso_id in (v_x, v_y)),
    'e C não consta em caso_membro de X nem de Y: é o papel, não uma linha');

  raise notice '--- 4. sem identidade ninguém é membro, e o caso do n8n nasce sem membro ---';
  perform set_config('request.jwt.claims', '', true);
  v_z := fn_upsert_caso('0215 — caso do n8n');                -- superusuário sem claims: o n8n/service_role
  select count(*) into v_n from caso_membro where caso_id = v_z;
  perform teste_assert_0215(v_n = 0, 'caso criado sem auth.uid() nasce com 0 membros', v_n::text);
  set local role authenticated;
  perform teste_assert_0215(not fn_eh_admin() and not fn_eh_membro(v_x), 'sem jwt: nem administrador nem membro de caso algum');
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform teste_assert_0215(fn_eh_membro(v_z), 'mas o administrador o enxerga');
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform teste_assert_0215(not fn_eh_membro(v_z), 'e o analista que não foi atribuído, não');
  reset role;

  raise notice '--- 5. o que cada um LÊ ---';
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from caso_membro where usuario_id <> ua;
  select count(*) into v_m from caso_membro where usuario_id = ua;
  perform teste_assert_0215(v_n = 0 and v_m > 0, 'A lê as próprias pertinências e nenhuma de B nem de C',
    v_n || ' alheias, ' || v_m || ' próprias');
  select count(*) into v_n from administrador;
  perform teste_assert_0215(v_n = 0, 'A não lê a tabela administrador', v_n::text);
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from caso_membro where usuario_id in (ua, ub);
  perform teste_assert_0215(v_n > 0
    and exists (select 1 from caso_membro where usuario_id = ua and caso_id = v_x)
    and exists (select 1 from caso_membro where usuario_id = ub and caso_id = v_y),
    'C, administrador, lê as pertinências de A e de B', v_n::text);
  select count(*) into v_n from administrador;
  perform teste_assert_0215(v_n = 1, 'C lê a tabela administrador', v_n::text);
  reset role;

  raise notice '--- 6. quem ESCREVE a pertinência ---';
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_err := null;
  begin perform fn_membro_adicionar(v_y, ua);
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  -- A MENSAGEM da guarda, não só o 42501: sem a guarda o insert levaria 42501 da RLS do mesmo jeito ("row-level security")
  perform teste_assert_0215(left(v_err, 5) = '42501' and v_err like '%só o administrador atribui%',
    'A não consegue chamar fn_membro_adicionar (42501 da guarda da função)', v_err);
  v_err := null;
  begin insert into caso_membro (caso_id, usuario_id, por) values (v_y, ua, 'burla');
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0215(v_err = '42501', 'nem inserir a si mesmo direto em caso_membro (RLS, 42501)', v_err);
  begin delete from caso_membro where caso_id = v_y and usuario_id = ub;
  exception when others then null; end;
  reset role;
  perform teste_assert_0215(exists (select 1 from caso_membro where caso_id = v_y and usuario_id = ub),
    'nem apagar a pertinência de B direto: a linha de B continua lá');
  -- A policy de delete é a que SEGURA a retirada: a de SELECT (só as próprias linhas) já esconderia a linha de B de A, mas
  -- a linha PRÓPRIA é visível — sem a policy de delete (using fn_eh_admin) A se retiraria do mandato, sem volta.
  set local role authenticated;
  delete from caso_membro where caso_id = v_x and usuario_id = ua;
  get diagnostics v_n = row_count;
  reset role;
  perform teste_assert_0215(v_n = 0 and exists (select 1 from caso_membro where caso_id = v_x and usuario_id = ua),
    'A nem se retira do próprio mandato por delete direto (só o administrador retira: 0 linhas, a pertinência continua)', v_n::text);
  perform teste_assert_0215(not teste_membro_0215(ua, v_y), 'A continua fora de Y depois das tentativas');
  set local role authenticated;
  v_err := null;
  begin perform fn_membro_remover(v_x, ua);
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  perform teste_assert_0215(left(v_err, 5) = '42501' and v_err like '%só o administrador retira%',
    'A não consegue chamar fn_membro_remover (42501 da guarda da função)', v_err);
  reset role;

  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_b := fn_membro_adicionar(v_y, ua);
  perform teste_assert_0215(v_b, 'C (administrador) atribui A a Y');
  v_b := fn_membro_adicionar(v_y, ua);
  perform teste_assert_0215(not v_b, 'atribuir quem já é membro não muda nada (false)');
  v_err := null;
  begin perform fn_membro_adicionar(v_y, '0215a000-0000-0000-0000-0000000000ff');
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0215(v_err = '23503', 'usuário inexistente: recusa (FK), não cria membro fantasma', v_err);
  reset role;
  perform teste_assert_0215(teste_membro_0215(ua, v_y), 'depois disso A é membro de Y');
  select count(*) into v_ev from evento_auditoria
   where acao = 'membro_adicionado' and entidade_ref = 'caso:' || v_y and ator = 'usuario:' || uc;
  perform teste_assert_0215(v_ev = 1, 'a atribuição deixou UM evento, com o administrador como ator (a repetida não grava outro)', v_ev::text);

  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_b := fn_membro_remover(v_y, ua);
  perform teste_assert_0215(v_b, 'C retira A de Y');
  perform teste_assert_0215(not fn_membro_remover(v_y, ua), 'retirar quem não é membro não muda nada (false)');
  reset role;
  perform teste_assert_0215(not teste_membro_0215(ua, v_y), 'depois disso A não é mais membro de Y');
  select count(*) into v_ev from evento_auditoria
   where acao = 'membro_removido' and entidade_ref = 'caso:' || v_y and ator = 'usuario:' || uc;
  perform teste_assert_0215(v_ev = 1, 'a retirada deixou UM evento', v_ev::text);

  raise notice '--- 6b. a RLS é a barreira, não a falta de GRANT (produção: o default privilege concede ALL) ---';
  -- o que a migration deixa (replay = produção depois do revoke): anon nada; authenticated só o que usa
  perform teste_assert_0215(
    not (has_table_privilege('anon', 'administrador', 'select') or has_table_privilege('anon', 'administrador', 'insert')
         or has_table_privilege('anon', 'caso_membro', 'select') or has_table_privilege('anon', 'caso_membro', 'insert')
         or has_table_privilege('anon', 'caso_membro', 'delete') or has_table_privilege('anon', 'caso_membro', 'update')),
    'anon não tem privilégio nenhum em administrador nem em caso_membro');
  perform teste_assert_0215(
    has_table_privilege('authenticated', 'administrador', 'select')
    and not (has_table_privilege('authenticated', 'administrador', 'insert') or has_table_privilege('authenticated', 'administrador', 'update')
             or has_table_privilege('authenticated', 'administrador', 'delete') or has_table_privilege('authenticated', 'administrador', 'truncate')),
    'authenticated só LÊ administrador (sem insert, update, delete nem truncate)');
  perform teste_assert_0215(
    has_table_privilege('authenticated', 'caso_membro', 'select') and has_table_privilege('authenticated', 'caso_membro', 'insert')
    and has_table_privilege('authenticated', 'caso_membro', 'delete')
    and not (has_table_privilege('authenticated', 'caso_membro', 'update') or has_table_privilege('authenticated', 'caso_membro', 'truncate')),
    'authenticated lê, insere e apaga caso_membro (pela policy do administrador) mas não atualiza nem trunca');
  -- agora CONCEDE o que o default privilege concederia, e a RLS tem de negar assim mesmo
  grant insert, update, delete on administrador to authenticated;
  grant update on caso_membro to authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_err := null;
  begin insert into administrador (usuario_id, por) values (ua, 'burla');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  update administrador set por = 'burla';                         get diagnostics v_n = row_count;
  delete from administrador;                                      get diagnostics v_m = row_count;
  reset role;
  perform teste_assert_0215(left(v_err, 5) = '42501' and v_err like '%row-level security%' and not exists (select 1 from administrador where usuario_id = ua),
    'COM o GRANT de insert, A não se insere em administrador: a RLS nega (42501 row-level security)', v_err);
  perform teste_assert_0215(v_n = 0 and v_m = 0 and exists (select 1 from administrador where usuario_id = uc and por <> 'burla'),
    'COM o GRANT, A não atualiza nem apaga administrador (0 linhas) e C continua lá', v_n || '/' || v_m);
  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_err := null;
  begin insert into administrador (usuario_id, por) values (ua, 'burla');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  update administrador set por = 'burla';                         get diagnostics v_n = row_count;
  delete from administrador;                                      get diagnostics v_m = row_count;
  reset role;
  perform teste_assert_0215(left(v_err, 5) = '42501' and v_n = 0 and v_m = 0 and exists (select 1 from administrador where usuario_id = uc and por <> 'burla')
    and not exists (select 1 from administrador where usuario_id = ua),
    'COM o GRANT, nem o administrador escreve em administrador pela tabela (sem policy de escrita; só a função, que o authenticated não executa)', v_err || ' ' || v_n || '/' || v_m);
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  update caso_membro set por = 'burla' where usuario_id = ua;     get diagnostics v_n = row_count;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  update caso_membro set por = 'burla';                           get diagnostics v_m = row_count;
  reset role;
  perform teste_assert_0215(v_n = 0 and v_m = 0 and not exists (select 1 from caso_membro where por = 'burla'),
    'COM o GRANT de update, ninguém — nem o administrador — edita uma linha de caso_membro (sem policy de update)', v_n || '/' || v_m);
  revoke insert, update, delete on administrador from authenticated;
  revoke update on caso_membro from authenticated;
  perform teste_assert_0215(not has_table_privilege('authenticated', 'administrador', 'insert') and not has_table_privilege('authenticated', 'caso_membro', 'update'),
    'os grants temporários foram revogados de volta');

  raise notice '--- 7. ninguém logado promove administrador ---';
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_err := null;
  begin perform fn_administrador_definir('a@0215.teste', true);
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  reset role;
  -- A MENSAGEM, não só o 42501: sem o revoke a função rodaria (invoker) e o authenticated levaria 42501 do mesmo jeito,
  -- em auth.users ("permission denied for table users"). É o texto que distingue "o revoke segurou" de "outra coisa negou".
  perform teste_assert_0215(left(v_err, 5) = '42501' and v_err like '%permission denied for function fn_administrador_definir%',
    'authenticated não executa fn_administrador_definir (permission denied for function)', v_err);
  perform teste_assert_0215(not exists (select 1 from administrador where usuario_id = ua), 'e A não virou administrador');
  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_err := null;
  begin perform fn_administrador_definir('b@0215.teste', true);
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  reset role;
  perform teste_assert_0215(left(v_err, 5) = '42501' and v_err like '%permission denied for function fn_administrador_definir%',
    'nem o administrador a executa (promover é de quem tem o banco)', v_err);
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_err := null;
  begin insert into administrador (usuario_id, por) values (ua, 'burla');
  exception when others then v_err := sqlstate; end;
  reset role;
  perform teste_assert_0215(v_err = '42501', 'nem inserir direto em administrador (42501)', v_err);
  v_err := null;
  set local role authenticated;
  begin perform fn_caso_membro_backfill_0215();
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  reset role;
  perform teste_assert_0215(left(v_err, 5) = '42501' and v_err like '%permission denied for function fn_caso_membro_backfill_0215%',
    'nem repetir a transição (daria todo caso a todo usuário ativo)', v_err);
  -- anon (a chave pública): no Supabase o default privilege concede EXECUTE a anon EXPLICITAMENTE, e `revoke ... from
  -- public` não o tira; por isso a migration revoga de anon também.
  set local role anon;
  v_err := null;
  begin perform fn_administrador_definir('a@0215.teste', true);
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  reset role;
  perform teste_assert_0215(left(v_err, 5) = '42501' and v_err like '%permission denied for function fn_administrador_definir%',
    'anon não executa fn_administrador_definir (permission denied for function)', v_err);

  raise notice '--- 8. a sonda enxerga o EXECUTE indevido ---';
  perform set_config('request.jwt.claims', '', true);
  grant execute on function fn_administrador_definir(text, boolean) to authenticated;
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'exec_definir_admin_authenticated' and not presente;
  revoke execute on function fn_administrador_definir(text, boolean) from authenticated;
  perform teste_assert_0215(v_n = 1, 'com o EXECUTE concedido ao authenticated a sonda acusa o requisito');
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0215' and not presente;
  perform teste_assert_0215(v_n = 0, 'revogado de novo, a sonda se cala', v_n::text);
  grant execute on function fn_administrador_definir(text, boolean) to anon;
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'exec_definir_admin_anon' and not presente;
  revoke execute on function fn_administrador_definir(text, boolean) from anon;
  perform teste_assert_0215(v_n = 1, 'com o EXECUTE concedido ao anon a sonda acusa o requisito');

  raise notice '--- 8b. a sonda exige RLS LIGADA (policy em tabela com RLS desligada não vale) ---';
  perform teste_assert_0215(
    (select count(*) from fn_instalacao_conferir() where tipo = 'rls' and migration = '0215' and presente) = 2,
    'em banco íntegro os dois requisitos rls da 0215 estão presentes');
  begin
    alter table administrador disable row level security;
    select count(*) into v_n from fn_instalacao_conferir() where chave = 'rls_administrador' and not presente;
    select count(*) into v_m from fn_instalacao_conferir() where chave = 'rls_caso_membro' and not presente;
    raise exception 'rollback_0215';
  exception when others then if sqlerrm <> 'rollback_0215' then raise; end if; end;
  perform teste_assert_0215(v_n = 1 and v_m = 0, 'com a RLS DESLIGADA em administrador a sonda acusa rls_administrador (e só ele)', v_n || '/' || v_m);
  begin
    alter table caso_membro disable row level security;
    select count(*) into v_n from fn_instalacao_conferir() where chave = 'rls_caso_membro' and not presente;
    select count(*) into v_m from fn_instalacao_conferir() where chave = 'rls_administrador' and not presente;
    raise exception 'rollback_0215';
  exception when others then if sqlerrm <> 'rollback_0215' then raise; end if; end;
  perform teste_assert_0215(v_n = 1 and v_m = 0, 'com a RLS DESLIGADA em caso_membro a sonda acusa rls_caso_membro (e só ele)', v_n || '/' || v_m);
  -- e a RLS desligada é, de fato, a brecha: com o GRANT que o default privilege dá, o insert direto PASSA
  begin
    alter table administrador disable row level security;
    grant insert on administrador to authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_err := null;
    begin insert into administrador (usuario_id, por) values (ua, 'burla');
    exception when others then v_err := sqlstate; end;
    reset role;
    raise exception 'rollback_0215';
  exception when others then if sqlerrm <> 'rollback_0215' then raise; end if; end;
  perform teste_assert_0215(v_err is null, 'controle: com a RLS desligada e o GRANT do default privilege, A SE PROMOVE (é isto que a sonda rls existe para acusar)', v_err);

  raise notice '--- 8c. a sonda não deixa requisito sair NULL ---';
  begin
    insert into instalacao_requisito (chave, migration, tipo, objeto, marcador, porque, severidade, ordem)
      values ('_teste_exec_sem_marcador', '0215', 'execucao', 'authenticated:fn_eh_admin', null, 'teste', 'informativo', 9999);
    select count(*), max(detalhe) into v_n, v_err from fn_instalacao_conferir() where chave = '_teste_exec_sem_marcador' and not presente;
    select count(*) into v_m from fn_instalacao_conferir() where presente is null;
    raise exception 'rollback_0215';
  exception when others then if sqlerrm <> 'rollback_0215' then raise; end if; end;
  perform teste_assert_0215(v_n = 1 and v_err like '%mal declarado%',
    'requisito execucao com marcador NULO aparece como ausente, dizendo que está mal declarado (antes: presente NULL, sumia de where not presente)', v_n || ' ' || coalesce(v_err, '<null>'));
  perform teste_assert_0215(v_m = 0, 'nenhum requisito sai com presente NULL', v_m::text);

  -- limpeza
  delete from caso where nome like '0215 — %';
  delete from auth.users where email like '%@0215.teste';
  select count(*) into v_n from caso_membro where usuario_id in (ua, ub, uc);
  perform teste_assert_0215(v_n = 0, 'a limpeza levou as pertinências junto (cascata)', v_n::text);
end $$;
