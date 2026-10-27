-- =============================================================================
-- 0214 — O acesso às tabelas de `public` é CONCEDIDO por migration, não herdado de default privilege
--
-- O run.sh deixou de simular o default privilege antigo do Supabase (que some em 30/10/2026): se este arquivo roda
-- verde, o replay das migrations entrega ao portal o que ele usa.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número de asserts e o de reprovações com a correção desligada estão no cabeçalho de
-- Supabase/migrations/0214_o_grant_que_o_supabase_deixou_de_dar.sql.
--
-- O QUE MEDE (comportamento): (1) toda tabela/view/sequence de public tem o mínimo para authenticated e service_role;
-- (2) o authenticated continua SEM delete onde um revoke intencional o tirou, e sem update fora de entidade_id em
-- caso_pergunta — por tentativa real, `set local role authenticated`, não só consulta de catálogo; (3) o authenticated
-- ainda LÊ e ESCREVE o que o portal usa (controle positivo); (4) a sonda acusa a tabela, a view e a sequence criadas
-- sem grant, por papel, e se cala quando o grant chega. Objeto sintético só no item 4, e nele o que se afirma é a
-- sonda, não um bug de produção (regra 4).
-- =============================================================================

create or replace function teste_assert_0214(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_cond then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

do $$
declare
  v_n int; v_det text; v_err text; v_ok boolean; v_t text;
begin
  raise notice '--- 1. todo objeto de public tem o mínimo, para os dois papéis ---';
  -- A sonda é a autoridade: nenhum requisito 0214 ausente, e os seis existem (não é "zero porque o catálogo veio vazio").
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0214';
  perform teste_assert_0214(v_n = 6, 'o catálogo da sonda tem os 6 requisitos de privilégio', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0214' and not presente;
  perform teste_assert_0214(v_n = 0, 'nenhum requisito de privilégio ausente', (select string_agg(chave || ': ' || detalhe, ' | ') from fn_instalacao_conferir() where migration = '0214' and not presente));

  -- Independente da sonda (a sonda poderia estar cega): conta direto no catálogo.
  select count(*) into v_n from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p');
  perform teste_assert_0214(v_n >= 40, 'o schema tem as tabelas esperadas (o laço abaixo não corre sobre o vazio)', v_n::text);
  select count(*) into v_n from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p')
     and not (has_table_privilege('authenticated', c.oid, 'select')
          and has_table_privilege('service_role', c.oid, 'insert') and has_table_privilege('service_role', c.oid, 'update')
          and has_table_privilege('service_role', c.oid, 'delete'));
  perform teste_assert_0214(v_n = 0, 'toda tabela: SELECT para authenticated e as quatro operações para service_role (o delete do authenticated varia de propósito)', v_n::text);
  select count(*) into v_n from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'S'
     and not (has_sequence_privilege('authenticated', c.oid, 'usage') and has_sequence_privilege('service_role', c.oid, 'usage'));
  perform teste_assert_0214(v_n = 0, 'toda sequence: USAGE para os dois', v_n::text);
  select count(*) into v_n from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'S';
  perform teste_assert_0214(v_n >= 1, 'há sequence no schema (arquivo_oficial_seq_seq): o assert acima não é vazio', v_n::text);

  raise notice '--- 2. os revokes intencionais sobrevivem (tentativa real como authenticated) ---';
  foreach v_t in array array['arquivo_oficial', 'perimetro', 'controlador', 'entidade_controlador', 'controlador_vinculo', 'caso_pergunta'] loop
    v_err := null;
    perform teste_como_admin_0216();
    set local role authenticated;
    begin execute format('delete from %I where false', v_t);
    exception when others then v_err := sqlstate; end;
    reset role;
    perform teste_fim_admin_0216();
    perform teste_assert_0214(v_err = '42501', format('authenticated NÃO apaga %s (permission denied)', v_t), v_err);
  end loop;

  v_err := null;
  perform teste_como_admin_0216();
  set local role authenticated;
  begin update caso_pergunta set id = id where false;
  exception when others then v_err := sqlstate; end;
  reset role;
  perform teste_fim_admin_0216();
  perform teste_assert_0214(v_err = '42501', 'authenticated NÃO atualiza caso_pergunta fora de entidade_id', v_err);

  v_err := null;
  perform teste_como_admin_0216();
  set local role authenticated;
  begin update caso_pergunta set entidade_id = entidade_id where false;
  exception when others then v_err := sqlstate; end;
  reset role;
  perform teste_fim_admin_0216();
  perform teste_assert_0214(v_err is null, 'authenticated ATUALIZA caso_pergunta.entidade_id (o grant de coluna da 0213 sobreviveu)', v_err);

  raise notice '--- 3. controle positivo: o que o portal usa continua funcionando ---';
  v_err := null;
  perform teste_como_admin_0216();
  set local role authenticated;
  begin
    perform 1 from caso limit 1;
    perform 1 from perimetro limit 1;
    perform 1 from instalacao_requisito limit 1;
    perform 1 from instalacao_sonda_passivo_bare limit 1;
    delete from caso where false;
  exception when others then v_err := sqlstate; end;
  reset role;
  perform teste_fim_admin_0216();
  perform teste_assert_0214(v_err is null, 'authenticated lê caso, perimetro, instalacao_requisito e uma view, e apaga em caso', v_err);
  perform teste_assert_0214(has_table_privilege('authenticated', 'perimetro', 'insert')
                        and has_table_privilege('authenticated', 'perimetro', 'update')
                        and has_table_privilege('authenticated', 'controlador_vinculo', 'insert')
                        and has_table_privilege('authenticated', 'controlador_vinculo', 'update'),
    'authenticated segue com INSERT/UPDATE nas tabelas da F1 (só o DELETE foi tirado)');
  perform teste_assert_0214(has_sequence_privilege('authenticated', 'arquivo_oficial_seq_seq', 'usage'),
    'authenticated usa a sequence de arquivo_oficial (o insert do portal depende dela)');
  perform teste_assert_0214(not has_table_privilege('anon', 'caso', 'select'),
    'anon NÃO recebe nada (o portal só usa a chave anon para a sessão)');

  raise notice '--- 4. a sonda acusa o objeto novo sem grant, por papel, e se cala quando ele chega ---';
  create table zz_sem_grant_0214 (a int);
  create view zz_view_sem_grant_0214 as select 1 as a;
  create sequence zz_seq_sem_grant_0214;

  for v_t in select unnest(array['grant_tabelas_authenticated', 'grant_tabelas_service_role', 'grant_views_authenticated',
                                 'grant_views_service_role', 'grant_sequences_authenticated', 'grant_sequences_service_role']) loop
    select presente, detalhe into v_ok, v_det from fn_instalacao_conferir() where chave = v_t;
    perform teste_assert_0214(v_ok is false and v_det like '%zz_%sem_grant_0214%', format('sem grant, a sonda acusa em %s', v_t), v_det);
  end loop;

  grant select on zz_sem_grant_0214 to authenticated;
  select presente into v_ok from fn_instalacao_conferir() where chave = 'grant_tabelas_authenticated';
  perform teste_assert_0214(v_ok is true, 'com o grant ao authenticated a regra do authenticated se cala');
  select presente into v_ok from fn_instalacao_conferir() where chave = 'grant_tabelas_service_role';
  perform teste_assert_0214(v_ok is false, 'mas a regra do service_role continua acusando (cada papel é medido por si)');

  grant select, insert, update on zz_sem_grant_0214 to service_role;
  select presente into v_ok from fn_instalacao_conferir() where chave = 'grant_tabelas_service_role';
  perform teste_assert_0214(v_ok is false, 'grant parcial (sem DELETE) ainda é buraco para o service_role');
  grant delete on zz_sem_grant_0214 to service_role;
  select presente into v_ok from fn_instalacao_conferir() where chave = 'grant_tabelas_service_role';
  perform teste_assert_0214(v_ok is true, 'grant completo cala a regra do service_role');

  grant select on zz_view_sem_grant_0214 to authenticated, service_role;
  grant usage on sequence zz_seq_sem_grant_0214 to authenticated, service_role;
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0214' and not presente;
  perform teste_assert_0214(v_n = 0, 'concedido tudo, a sonda volta a zero buracos', v_n::text);

  drop sequence zz_seq_sem_grant_0214;
  drop view zz_view_sem_grant_0214;
  drop table zz_sem_grant_0214;

  raise notice 'GRANT DE TABELA OK — o replay entrega o acesso, os revokes intencionais ficam e a sonda cobra o grant esquecido';
end $$;

drop function teste_assert_0214(boolean, text, text);
