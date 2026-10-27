-- =============================================================================
-- 0215 — O mandato só é visto por quem trabalha nele: membro + administrador
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
  v_x uuid; v_y uuid; v_z uuid; v_antigo uuid;
  v_n bigint; v_m bigint; v_err text; v_b boolean; v_ev int;
  v_casos int; v_usuarios int;
begin
  raise notice '--- 0. o catálogo da sonda tem os requisitos da 0215 e nenhum está ausente ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0215';
  perform teste_assert_0215(v_n = 21, 'a sonda tem os 21 requisitos da 0215', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0215' and not presente;
  perform teste_assert_0215(v_n = 0, 'nenhum requisito da 0215 ausente',
    (select string_agg(chave || ': ' || detalhe, ' | ') from fn_instalacao_conferir() where migration = '0215' and not presente));

  raise notice '--- 1. a transição: todo usuário x todo caso que JÁ existia ---';
  insert into auth.users (id, email) values (ua, 'a@0215.teste'), (ub, 'b@0215.teste'), (uc, 'c@0215.teste');
  v_antigo := fn_upsert_caso('0215 — caso antigo');          -- superusuário: auth.uid() nulo, nasce sem membro
  select count(*) into v_casos from caso;
  select count(*) into v_usuarios from auth.users;
  perform teste_assert_0215(v_casos >= 3 and v_usuarios = 3,
    'o arranjo não é vazio: casos das fixtures + o antigo, e três usuários', v_casos || ' casos, ' || v_usuarios || ' usuários');
  select count(*) into v_n from caso_membro where usuario_id in (ua, ub, uc);
  perform teste_assert_0215(v_n = 0, 'antes da transição os usuários novos não são membros de nada', v_n::text);

  v_n := fn_caso_membro_backfill_0215();
  perform teste_assert_0215(v_n = v_casos * v_usuarios, 'a transição devolve usuários x casos',
    v_n || ' de ' || v_casos * v_usuarios);
  select count(*) into v_m from (
    select c.id, u.id from caso c cross join auth.users u
    except select caso_id, usuario_id from caso_membro) f;
  perform teste_assert_0215(v_m = 0, 'o produto cartesiano está completo: nenhum par usuário/caso faltando', v_m::text);
  select count(*) into v_m from caso_membro where por = 'migracao:0215';
  perform teste_assert_0215(v_m = v_casos * v_usuarios, 'e só ele: toda linha da transição é par usuário/caso, marcada migracao:0215', v_m::text);
  perform teste_assert_0215(fn_caso_membro_backfill_0215() = 0, 'a transição é idempotente (segunda chamada: 0 linhas novas)');
  select count(*) into v_n from administrador;
  perform teste_assert_0215(v_n = 0, 'ninguém vira administrador sozinho', v_n::text);

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
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0215(v_err = '42501', 'A não consegue chamar fn_membro_adicionar (42501)', v_err);
  v_err := null;
  begin insert into caso_membro (caso_id, usuario_id, por) values (v_y, ua, 'burla');
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0215(v_err = '42501', 'nem inserir a si mesmo direto em caso_membro (RLS, 42501)', v_err);
  begin delete from caso_membro where caso_id = v_y and usuario_id = ub;
  exception when others then null; end;
  reset role;
  perform teste_assert_0215(exists (select 1 from caso_membro where caso_id = v_y and usuario_id = ub),
    'nem apagar a pertinência de B direto: a linha de B continua lá');
  perform teste_assert_0215(not teste_membro_0215(ua, v_y), 'A continua fora de Y depois das tentativas');
  set local role authenticated;
  v_err := null;
  begin perform fn_membro_remover(v_x, ua);
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0215(v_err = '42501', 'A não consegue chamar fn_membro_remover (42501)', v_err);
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

  raise notice '--- 7. ninguém logado promove administrador ---';
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_err := null;
  begin perform fn_administrador_definir('a@0215.teste', true);
  exception when others then v_err := sqlstate; end;
  reset role;
  perform teste_assert_0215(v_err = '42501', 'authenticated não executa fn_administrador_definir (42501)', v_err);
  perform teste_assert_0215(not exists (select 1 from administrador where usuario_id = ua), 'e A não virou administrador');
  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_err := null;
  begin perform fn_administrador_definir('b@0215.teste', true);
  exception when others then v_err := sqlstate; end;
  reset role;
  perform teste_assert_0215(v_err = '42501', 'nem o administrador a executa (promover é de quem tem o banco)', v_err);
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
  exception when others then v_err := sqlstate; end;
  reset role;
  perform teste_assert_0215(v_err = '42501', 'nem repetir a transição (daria todo caso a todo usuário)', v_err);

  raise notice '--- 8. a sonda enxerga o EXECUTE indevido ---';
  perform set_config('request.jwt.claims', '', true);
  grant execute on function fn_administrador_definir(text, boolean) to authenticated;
  select count(*) into v_n from fn_instalacao_conferir() where chave = 'exec_definir_admin_authenticated' and not presente;
  revoke execute on function fn_administrador_definir(text, boolean) from authenticated;
  perform teste_assert_0215(v_n = 1, 'com o EXECUTE concedido ao authenticated a sonda acusa o requisito');
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0215' and not presente;
  perform teste_assert_0215(v_n = 0, 'revogado de novo, a sonda se cala', v_n::text);

  -- limpeza
  delete from caso where nome like '0215 — %';
  delete from auth.users where email like '%@0215.teste';
  select count(*) into v_n from caso_membro where usuario_id in (ua, ub, uc);
  perform teste_assert_0215(v_n = 0, 'a limpeza levou as pertinências junto (cascata)', v_n::text);
end $$;
