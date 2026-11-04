-- =============================================================================
-- 0221 — A RLS QUE NINGUÉM CONFERIA LIGADA, E O PORTÃO DO DIAL QUE NÃO VIA DDL
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md): 58 dos 58 asserts medidos (cada chamada roda uma vez). Controle intacto: 58 execuções, 0 falhas.
-- O número por parte, com a correção desligada, está no cabeçalho de Supabase/migrations/0221_a_rls_que_ninguem_conferia_ligada_e_o_ddl_do_dial.sql.
--
-- COMO RODA. Como o teste da 0220: uma transação só (`begin` ... `rollback`); reaplica o arquivo da migration (`\i`) no começo (no-op com o arquivo real: prova a idempotência) ou uma VARIANTE com
-- `-v arq0221=<arquivo>`, que é como se mede cada correção desligada; `PGOPTIONS='-c dial.medindo=on'` transforma o assert em `raise warning` e CONTA. O JWT é sempre definido de forma explícita.
-- O FIM do arquivo confere o número de execuções: assert que sumiu reprova em vez de passar calado (regra 7).
--
-- O QUE AFIRMA (comportamento, não mecanismo):
--   PARTE A. Tabela de public com a RLS desligada (criada sem ela, ou `disable row level security` numa existente, ou particionada) acende rls_ligada_em_public e o detalhe a NOMEIA; ligada a RLS, apaga.
--            Não acusa: view, tabela de outro schema, tabela com RLS e sem policy. Schema inexistente é ausente, não exceção. A lista corta em 15.
--   PARTE B. A Analista, com as policies abertas (só o gatilho resta), chama uma definer que desliga a guarda de Sócio por DDL e escreve no dial: a BURLA é real, e a sonda ACUSA a definer (alter table ...
--            disable trigger, drop trigger ... on, disable row level security, com `public.`, `if exists`, aspas e comentário; o parâmetro de réplica; helper INVOKER; função de gatilho). NÃO acusa: a
--            genérica do tipo rls_auto_enable (SQL dinâmico, não cita a protegida), DDL de outra tabela, nome parecido, definer fechada ao authenticated, INVOKER sem definer, leitura, e quem CHAMA fn_instalacao_conferir().
--   B5. A guarda TROCADA (`create or replace trigger` com o mesmo nome e outra função): a Analista escreve no dial, e acesso_gatilho_dial / acesso_gatilho_premissa_catalogo ficam AUSENTES (o requisito declara a função da guarda). DDL de
--       routine e procedure é acusado como o de function.
--   Reaplicar a migration não muda nada.
-- =============================================================================

\set ON_ERROR_STOP on
\if :{?arq0221}
\else
  \set arq0221 'Supabase/migrations/0221_a_rls_que_ninguem_conferia_ligada_e_o_ddl_do_dial.sql'
\endif

begin;

create or replace function teste_assert_0221(p_cond boolean, p_nome text, p_detalhe text default null)
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

create or replace function teste_tenta_0221(p_sql text) returns text
language plpgsql as $$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return 'ok:' || n;
exception when others then
  return sqlstate;
end $$;

create or replace function teste_como_0221(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create or replace function teste_super_0221(p_socio uuid) returns void
language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_socio, 'role', 'authenticated')::text, true);
end $$;

-- O requisito `p_chave` está presente? / acusa a função `p_fn` (ausente e o nome no detalhe)?
create or replace function teste_presente_0221(p_chave text) returns boolean
language sql as $$ select coalesce((select presente from fn_instalacao_conferir() where chave = p_chave), false) $$;
create or replace function teste_detalhe_0221(p_chave text) returns text
language sql as $$ select detalhe from fn_instalacao_conferir() where chave = p_chave $$;
create or replace function teste_acusa_0221(p_fn text) returns boolean
language sql as $$
  select coalesce((select not presente and detalhe like '%' || p_fn || '%' from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'), false) $$;

-- A migration sob teste: o arquivo real (no-op) ou a variante.
\i :arq0221

-- =============================================================================
-- PARTE 1 — O ESTADO LIMPO
-- =============================================================================
do $$
begin
  raise notice '--- 1. estado limpo ---';
  perform teste_assert_0221((select presente and severidade = 'bloqueante' from fn_instalacao_conferir() where chave = 'rls_ligada_em_public'),
    'estado limpo: rls_ligada_em_public presente e BLOQUEANTE (todas as tabelas de public têm a RLS ligada)', teste_detalhe_0221('rls_ligada_em_public'));
  perform teste_assert_0221((select count(*) from fn_instalacao_conferir() where migration = '0221' and presente) = 6
                            and (select count(*) from instalacao_requisito where migration = '0221') = 6,
    'os 6 requisitos da 0221 estão no catálogo e PRESENTES (a sonda prova em produção que a 0221 foi aplicada)',
    (select string_agg(chave || '=' || presente, ', ') from fn_instalacao_conferir() where migration = '0221'));
  perform teste_assert_0221((select count(*) from regexp_matches((select pg_get_constraintdef(oid) from pg_constraint where conname = 'instalacao_requisito_tipo_check'), '''[a-z_]+''', 'g')) = 14
                            and (select pg_get_constraintdef(oid) from pg_constraint where conname = 'instalacao_requisito_tipo_check') like '%rls_ligada%',
    'a constraint de tipo tem os 14 tipos (os 13 da 0220 e rls_ligada)', (select pg_get_constraintdef(oid) from pg_constraint where conname = 'instalacao_requisito_tipo_check'));
  perform teste_assert_0221(not exists (select 1 from fn_instalacao_conferir() where migration in ('0219', '0220', '0221') and not presente)
                            and (select count(*) from fn_instalacao_conferir() where tipo in ('segredo', 'sem_privilegio', 'definer_sem_escrita', 'sem_acao_referencial') and presente) >= 4,
    'nenhum requisito da 0219, 0220 nem 0221 ausente, e os ramos antigos (segredo, sem_privilegio, definer_sem_escrita, sem_acao_referencial) seguem vivos e verdes na reemissão',
    (select string_agg(chave, ', ') from fn_instalacao_conferir() where migration in ('0219', '0220', '0221') and not presente));
end $$;

-- =============================================================================
-- PARTE A — a RLS desligada
-- =============================================================================
do $$
declare
  v_n int;
  v_det text;
begin
  raise notice '--- A1. tabela criada SEM a RLS (o que o banco local faz; em produção o event trigger ensure_rls liga) ---';
  create table zz_sem_rls_0221 (id int);
  perform teste_assert_0221(not teste_presente_0221('rls_ligada_em_public') and teste_detalhe_0221('rls_ligada_em_public') like '%zz_sem_rls_0221%',
    'tabela nova de public SEM a RLS: rls_ligada_em_public AUSENTE e o detalhe nomeia a tabela', teste_detalhe_0221('rls_ligada_em_public'));
  perform teste_assert_0221(teste_detalhe_0221('rls_ligada_em_public') like '1 tabela(s) de public%',
    'e só ela: "1 tabela(s)" (nenhuma outra tabela do banco montado está sem RLS)', teste_detalhe_0221('rls_ligada_em_public'));
  alter table zz_sem_rls_0221 enable row level security;
  perform teste_assert_0221(teste_presente_0221('rls_ligada_em_public'), 'ligada a RLS, o requisito volta a PRESENTE (e a tabela com RLS e SEM policy não é acusada: fica fechada, o lado seguro)',
    teste_detalhe_0221('rls_ligada_em_public'));
  drop table zz_sem_rls_0221;

  raise notice '--- A2. a RLS DESLIGADA numa tabela que tinha ---';
  alter table instalacao_requisito disable row level security;
  perform teste_assert_0221(not teste_presente_0221('rls_ligada_em_public') and teste_detalhe_0221('rls_ligada_em_public') like '%instalacao_requisito%',
    'disable row level security numa tabela existente (instalacao_requisito): AUSENTE e nomeada (as policies seguem no catálogo, e não valem)', teste_detalhe_0221('rls_ligada_em_public'));
  alter table instalacao_requisito enable row level security;
  perform teste_assert_0221(teste_presente_0221('rls_ligada_em_public'), 'religada a RLS, PRESENTE de novo', teste_detalhe_0221('rls_ligada_em_public'));

  raise notice '--- A3. tabela particionada ---';
  create table zz_part_0221 (id int) partition by range (id);
  perform teste_assert_0221(not teste_presente_0221('rls_ligada_em_public') and teste_detalhe_0221('rls_ligada_em_public') like '%zz_part_0221%',
    'tabela PARTICIONADA (relkind p) sem RLS também é acusada', teste_detalhe_0221('rls_ligada_em_public'));
  drop table zz_part_0221;

  raise notice '--- A4. o que NÃO é tabela de public ---';
  create schema zz_outro_0221;
  create table zz_outro_0221.t (id int);
  create view zz_view_0221 as select 1 as x;
  create sequence zz_seq_0221;
  perform teste_assert_0221(teste_presente_0221('rls_ligada_em_public'),
    'tabela de OUTRO schema sem RLS, view e sequence de public não são acusadas (o requisito é sobre as tabelas de public)', teste_detalhe_0221('rls_ligada_em_public'));
  drop view zz_view_0221; drop sequence zz_seq_0221; drop schema zz_outro_0221 cascade;

  raise notice '--- A5. schema que não existe: ausente com o motivo, nunca uma exceção que derruba a sonda ---';
  insert into instalacao_requisito (chave, migration, tipo, objeto, porque, severidade, ordem)
    values ('zz_rls_schema_0221', '0221', 'rls_ligada', 'zz_nao_existe_0221', 'teste', 'informativo', 9999);
  select presente, detalhe into v_n, v_det from (select presente::int as presente, detalhe from fn_instalacao_conferir() where chave = 'zz_rls_schema_0221') x;
  perform teste_assert_0221(v_n = 0 and v_det like '%nem existe%', 'objeto = schema inexistente: AUSENTE com "nem existe", e a sonda inteira ainda responde', v_det);
  delete from instalacao_requisito where chave = 'zz_rls_schema_0221';

  raise notice '--- A5b. schema que existe e está VAZIO: o verde não pode vir de não ter olhado nada (regra 7) ---';
  create schema zz_vazio_0221;
  insert into instalacao_requisito (chave, migration, tipo, objeto, porque, severidade, ordem)
    values ('zz_rls_vazio_0221', '0221', 'rls_ligada', 'zz_vazio_0221', 'teste', 'informativo', 9999);
  select presente::int, detalhe into v_n, v_det from fn_instalacao_conferir() where chave = 'zz_rls_vazio_0221';
  perform teste_assert_0221(v_n = 0 and v_det like 'nenhuma tabela examinada%', 'schema existente e VAZIO: AUSENTE, e o detalhe diz que nada foi examinado (não "todas com RLS")', v_det);
  delete from instalacao_requisito where chave = 'zz_rls_vazio_0221';
  drop schema zz_vazio_0221;
  perform teste_assert_0221(teste_detalhe_0221('rls_ligada_em_public') = format('%s tabelas examinadas em public, todas com a RLS ligada',
                              (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relkind in ('r', 'p'))),
    'o PRESENTE diz quantas tabelas examinou (N = as tabelas de public)', teste_detalhe_0221('rls_ligada_em_public'));

  raise notice '--- A6. muitas tabelas: a lista corta em 15, a contagem não ---';
  for i in 1..17 loop execute format('create table zz_muitas_%s_0221 (id int)', lpad(i::text, 2, '0')); end loop;
  perform teste_assert_0221(teste_detalhe_0221('rls_ligada_em_public') like '17 tabela(s) de public%' and teste_detalhe_0221('rls_ligada_em_public') like '%...',
    '17 tabelas sem RLS: o detalhe diz 17 e a lista é cortada com "..." (15 nomes)', teste_detalhe_0221('rls_ligada_em_public'));
  for i in 1..17 loop execute format('drop table zz_muitas_%s_0221', lpad(i::text, 2, '0')); end loop;
  perform teste_assert_0221(teste_presente_0221('rls_ligada_em_public'), 'removidas, PRESENTE de novo (nenhum resíduo)', teste_detalhe_0221('rls_ligada_em_public'));
end $$;

-- =============================================================================
-- PARTE B — o DDL que desliga a guarda
-- =============================================================================
do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000000f901';
  u_ana   uuid := '00000000-0000-0000-0000-00000000f902';
  v_t text; v_t2 text; v_antes text; v_dep text;
begin
  insert into auth.users (id, email) values (u_socio, 'socio@0221.local'), (u_ana, 'ana@0221.local');
  perform fn_definir_papel(u_socio, 'socio', 'teste 0221');
  perform fn_definir_papel(u_ana, 'analista');
  perform teste_super_0221(u_socio);

  raise notice '--- B1. a BURLA, medida: a Analista liga/desliga a guarda por DDL dentro de uma definer ---';
  -- Isola a ÚLTIMA camada (como o teste da 0219): com a policy de UPDATE do dial aberta, só o gatilho separa a Analista do dial.
  drop policy estagio_autonomia_update on estagio_autonomia;
  create policy estagio_autonomia_update on estagio_autonomia for update to authenticated using (true) with check (true);
  create function zz_desliga_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin alter table estagio_autonomia disable trigger trg_estagio_autonomia_so_socio; end $f$;
  revoke all on function zz_desliga_0221() from public;
  grant execute on function zz_desliga_0221() to authenticated;
  select nivel_atual::text into v_antes from estagio_autonomia where estagio = 'classificacao_doc_checklist';
  perform teste_como_0221(u_ana);
  v_t := teste_tenta_0221($q$update estagio_autonomia set nivel_atual = 'N0' where estagio = 'classificacao_doc_checklist'$q$);
  perform teste_super_0221(u_socio);
  perform teste_assert_0221(v_t = '42501', 'controle: com a policy aberta e a guarda ligada, a Analista leva 42501 no UPDATE do dial (só o gatilho resta)', v_t);
  begin
    perform teste_como_0221(u_ana);
    v_t  := teste_tenta_0221('select zz_desliga_0221()');
    v_t2 := teste_tenta_0221($q$update estagio_autonomia set nivel_atual = 'N0' where estagio = 'classificacao_doc_checklist'$q$);
    perform teste_super_0221(u_socio);
    select nivel_atual::text into v_dep from estagio_autonomia where estagio = 'classificacao_doc_checklist';
    raise exception 'desfaz a burla' using errcode = 'P0221';
  exception when sqlstate 'P0221' then null;
  end;
  perform teste_super_0221(u_socio);
  perform teste_assert_0221(v_t = 'ok:1' and v_t2 = 'ok:1' and v_dep = 'N0' and v_antes <> 'N0',
    'a BURLA é real: a Analista chama a definer que desliga o gatilho e, na mesma transação, o dial vai de ' || v_antes || ' para N0 sem ela ser Sócio', v_t || ' / ' || v_t2 || ' / ' || v_antes || ' -> ' || v_dep);
  perform teste_assert_0221(teste_acusa_0221('zz_desliga_0221'),
    'a sonda ACUSA a definer com `alter table estagio_autonomia disable trigger` (não escreve linha nenhuma)', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_desliga_0221();
  perform teste_assert_0221(teste_presente_0221('definer_nao_escreve_no_dial'), 'removida a função, o portão volta a verde (era ela que acusava)', teste_detalhe_0221('definer_nao_escreve_no_dial'));

  raise notice '--- B2. as outras formas de desligar a guarda ---';
  create function zz_dropgat_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin drop trigger if exists trg_estagio_autonomia_so_socio on estagio_autonomia; end $f$;
  grant execute on function zz_dropgat_0221() to authenticated;
  perform teste_assert_0221(teste_acusa_0221('zz_dropgat_0221'), 'a sonda ACUSA a definer com `drop trigger ... on estagio_autonomia`', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_dropgat_0221();

  create function zz_semrls_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin alter table premissa_catalogo disable row level security; end $f$;
  grant execute on function zz_semrls_0221() to authenticated;
  perform teste_assert_0221(teste_acusa_0221('zz_semrls_0221'), 'a sonda ACUSA a definer com `alter table premissa_catalogo disable row level security`', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_semrls_0221();

  create function zz_completa_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin alter table if exists only public.estagio_autonomia disable trigger user; end $f$;
  grant execute on function zz_completa_0221() to authenticated;
  perform teste_assert_0221(teste_acusa_0221('zz_completa_0221'), 'a sonda ACUSA `alter table if exists only public.estagio_autonomia disable trigger user` (if exists, only, schema)', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_completa_0221();

  create function zz_aspas_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin alter table/* só um instante */"estagio_autonomia" disable trigger all; end $f$;
  grant execute on function zz_aspas_0221() to authenticated;
  perform teste_assert_0221(teste_acusa_0221('zz_aspas_0221'), 'a sonda ACUSA o DDL com comentário e aspas coladas (`alter table/* c */"estagio_autonomia"`)', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_aspas_0221();

  create function zz_replica_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin perform set_config('session_replication_role', 'replica', true); end $f$;
  grant execute on function zz_replica_0221() to authenticated;
  perform teste_assert_0221(teste_acusa_0221('zz_replica_0221'), 'a sonda ACUSA a definer que ajusta o modo de réplica da sessão (os gatilhos de TODAS as tabelas deixam de disparar), sem citar tabela nenhuma', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_replica_0221();

  create function zz_helper_ddl_0221() returns void language plpgsql as $f$ begin alter table estagio_autonomia disable trigger all; end $f$;
  create function zz_via_helper_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin perform zz_helper_ddl_0221(); end $f$;
  grant execute on function zz_via_helper_0221() to authenticated;
  perform teste_assert_0221(teste_acusa_0221('zz_via_helper_0221') and not teste_acusa_0221('zz_helper_ddl_0221'),
    'a sonda ACUSA a definer que CHAMA um helper INVOKER com o DDL (o fecho), e não acusa o helper INVOKER em si', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_via_helper_0221();
  perform teste_assert_0221(teste_presente_0221('definer_nao_escreve_no_dial'),
    'o helper INVOKER com DDL, sem nenhuma definer que o chame, NÃO acusa (não roda como dono)', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_helper_ddl_0221();

  create function zz_gat_0221() returns trigger language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin alter table estagio_autonomia disable trigger all; return null; end $f$;
  perform teste_assert_0221(teste_acusa_0221('zz_gat_0221'), 'a sonda ACUSA a função de GATILHO definer com o DDL (dispara sem precisar de EXECUTE)', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_gat_0221();

  raise notice '--- B3. o que NÃO acusa (o portão não pode gritar à toa) ---';
  -- A genérica da plataforma: SQL dinâmico, a tabela vem de variável, nunca cita a protegida. Duas formas: a de event trigger (como a real) e a chamável.
  create function zz_rls_auto_0221() returns event_trigger language plpgsql security definer set search_path = pg_catalog
    as $f$ declare cmd record; begin for cmd in select * from pg_event_trigger_ddl_commands() where command_tag in ('CREATE TABLE') loop
             execute format('alter table %s enable row level security', cmd.object_identity); end loop; end $f$;
  create function zz_rls_chamavel_0221(p_tab text) returns void language plpgsql security definer set search_path = pg_catalog
    as $f$ begin execute format('alter table %I enable row level security', p_tab); end $f$;
  grant execute on function zz_rls_chamavel_0221(text) to authenticated;
  perform teste_assert_0221(teste_presente_0221('definer_nao_escreve_no_dial'),
    'a genérica tipo rls_auto_enable (SQL dinâmico, definer, de event trigger e outra chamável pelo authenticated) NÃO é acusada: não cita as tabelas protegidas', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_rls_auto_0221(); drop function zz_rls_chamavel_0221(text);

  create function zz_outra_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin alter table caso disable trigger all; drop trigger if exists x on caso; end $f$;
  grant execute on function zz_outra_0221() to authenticated;
  perform teste_assert_0221(teste_presente_0221('definer_nao_escreve_no_dial'), 'DDL numa tabela que NÃO é protegida (alter table caso, drop trigger ... on caso) não acusa', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_outra_0221();

  create function zz_parecida_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin alter table estagio_autonomia_historico disable trigger all; alter table premissa_catalogo_x disable trigger all; end $f$;
  grant execute on function zz_parecida_0221() to authenticated;
  perform teste_assert_0221(teste_presente_0221('definer_nao_escreve_no_dial'), 'nome de tabela PARECIDO (estagio_autonomia_historico, premissa_catalogo_x) não acusa', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_parecida_0221();

  create function zz_fechada_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin alter table estagio_autonomia disable trigger all; end $f$;
  revoke all on function zz_fechada_0221() from public, authenticated, anon;
  perform teste_assert_0221(teste_presente_0221('definer_nao_escreve_no_dial'), 'a definer com DDL FECHADA ao authenticated (sem EXECUTE) não é alcançável pelo portal e não acusa', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_fechada_0221();

  create function zz_le_0221() returns bigint language sql security definer set search_path = public, pg_temp
    as $f$ select count(*) from estagio_autonomia $f$;
  grant execute on function zz_le_0221() to authenticated;
  perform teste_assert_0221(teste_presente_0221('definer_nao_escreve_no_dial'), 'definer que só LÊ a tabela protegida não acusa (controle de que o critério novo não virou "cita a tabela")', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_le_0221();

  create function zz_chama_sonda_0221() returns bigint language sql security definer set search_path = public, pg_temp
    as $f$ select count(*) from fn_instalacao_conferir() $f$;
  grant execute on function zz_chama_sonda_0221() to authenticated;
  perform teste_assert_0221(teste_presente_0221('definer_nao_escreve_no_dial'),
    'quem CHAMA fn_instalacao_conferir() não é acusado: a sonda não entra no fecho (o parâmetro de réplica está em duas metades no corpo dela)', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_chama_sonda_0221();

  raise notice '--- B5. a guarda TROCADA: create or replace trigger com o mesmo nome, outra função ---';
  create function zz_inofensiva_0221() returns trigger language plpgsql as $f$ begin return new; end $f$;
  perform teste_assert_0221((select presente from fn_instalacao_conferir() where chave = 'acesso_gatilho_dial') and teste_presente_0221('acesso_gatilho_premissa_catalogo'),
    'controle: com os gatilhos certos (fn_trg_so_socio), acesso_gatilho_dial e acesso_gatilho_premissa_catalogo estão PRESENTES', teste_detalhe_0221('acesso_gatilho_dial'));
  begin
    execute 'create or replace trigger trg_estagio_autonomia_so_socio before insert or update or delete on estagio_autonomia for each row execute function zz_inofensiva_0221()';
    perform teste_como_0221(u_ana);
    v_t2 := teste_tenta_0221($q$update estagio_autonomia set nivel_atual = 'N0' where estagio = 'classificacao_doc_checklist'$q$);
    perform teste_super_0221(u_socio);
    v_t  := (select case when presente then 'presente' else detalhe end from fn_instalacao_conferir() where chave = 'acesso_gatilho_dial');
    execute 'create or replace trigger trg_premissa_catalogo_so_socio before insert or update or delete on premissa_catalogo for each row execute function zz_inofensiva_0221()';
    v_dep := (select case when presente then 'presente' else 'ausente' end from fn_instalacao_conferir() where chave = 'acesso_gatilho_premissa_catalogo');
    raise exception 'desfaz a troca' using errcode = 'P0221';
  exception when sqlstate 'P0221' then null;
  end;
  perform teste_super_0221(u_socio);
  perform teste_assert_0221(v_t2 = 'ok:1', 'a TROCA é real: com o gatilho do dial apontando para outra função (mesmo nome, habilitado), a Analista escreve no dial sem ser Sócio', v_t2);
  perform teste_assert_0221(v_t like '%TROCADA%' and v_t like '%zz_inofensiva_0221%', 'acesso_gatilho_dial fica AUSENTE quando o gatilho chama outra função, e o detalhe diz qual', v_t);
  perform teste_assert_0221(v_dep = 'ausente', 'o mesmo no catálogo de premissas: acesso_gatilho_premissa_catalogo AUSENTE com o gatilho trocado', v_dep);
  drop function zz_inofensiva_0221();

  raise notice '--- B6. sem guarda DECLARADA o portão não pode ficar verde calado (regra 7) ---';
  update instalacao_requisito set marcador = null where chave in ('acesso_gatilho_dial', 'acesso_gatilho_premissa_catalogo');
  perform teste_assert_0221(not teste_presente_0221('definer_nao_escreve_no_dial') and teste_detalhe_0221('definer_nao_escreve_no_dial') like 'nenhuma guarda declarada%',
    'marcador NULO nos dois requisitos de gatilho: definer_nao_escreve_no_dial AUSENTE, dizendo que a troca do gatilho e o DDL da guarda não estão vigiados', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  update instalacao_requisito set marcador = 'fn_zz_nao_existe_0221' where chave = 'acesso_gatilho_dial';
  update instalacao_requisito set marcador = 'fn_trg_so_socio' where chave = 'acesso_gatilho_premissa_catalogo';
  perform teste_assert_0221(not teste_presente_0221('definer_nao_escreve_no_dial'), 'guarda declarada que NÃO existe em public: AUSENTE também', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  update instalacao_requisito set marcador = 'fn_trg_so_socio' where chave in ('acesso_gatilho_dial', 'acesso_gatilho_premissa_catalogo');
  perform teste_assert_0221(teste_presente_0221('definer_nao_escreve_no_dial'), 'controle: com a guarda declarada de volta (fn_trg_so_socio), o portão volta a PRESENTE', teste_detalhe_0221('definer_nao_escreve_no_dial'));

  raise notice '--- B4. o `*` colado ao nome, a lista no drop table, o DDL da FUNÇÃO da guarda ---';
  create function zz_estrela_ddl_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin alter table estagio_autonomia* disable trigger all; end $f$;
  grant execute on function zz_estrela_ddl_0221() to authenticated;
  perform teste_assert_0221(teste_acusa_0221('zz_estrela_ddl_0221'), 'a sonda ACUSA `alter table estagio_autonomia* disable trigger all` (o `*` dos descendentes colado ao nome)', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_estrela_ddl_0221();
  create function zz_estrela_upd_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin update estagio_autonomia * set atualizado_por = atualizado_por; end $f$;
  grant execute on function zz_estrela_upd_0221() to authenticated;
  perform teste_assert_0221(teste_acusa_0221('zz_estrela_upd_0221'), 'a sonda ACUSA `update estagio_autonomia * set` (DML com `*`)', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_estrela_upd_0221();
  create function zz_estrela_del_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin delete from premissa_catalogo* where false; end $f$;
  grant execute on function zz_estrela_del_0221() to authenticated;
  perform teste_assert_0221(teste_acusa_0221('zz_estrela_del_0221'), 'a sonda ACUSA `delete from premissa_catalogo*` (DML com `*` colado)', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_estrela_del_0221();

  create function zz_droplista_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin drop table if exists zz_nada_0221, estagio_autonomia cascade; end $f$;
  grant execute on function zz_droplista_0221() to authenticated;
  perform teste_assert_0221(teste_acusa_0221('zz_droplista_0221'), 'a sonda ACUSA `drop table if exists zz_nada, estagio_autonomia cascade` (a protegida DEPOIS da vírgula)', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_droplista_0221();

  create function zz_dropfn_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin drop function fn_trg_so_socio() cascade; end $f$;
  grant execute on function zz_dropfn_0221() to authenticated;
  perform teste_assert_0221(teste_acusa_0221('zz_dropfn_0221'), 'a sonda ACUSA `drop function fn_trg_so_socio() cascade` (apaga a guarda e os gatilhos dela, sem escrever linha)', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_dropfn_0221();
  create function zz_crfn_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin create or replace function public.fn_trg_so_socio() returns trigger language plpgsql as 'begin return new; end'; end $f$;
  grant execute on function zz_crfn_0221() to authenticated;
  perform teste_assert_0221(teste_acusa_0221('zz_crfn_0221'), 'a sonda ACUSA `create or replace function public.fn_trg_so_socio()` (trocar a guarda por uma que deixa passar)', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_crfn_0221();
  create function zz_dropro_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin drop routine fn_trg_so_socio() cascade; end $f$;
  grant execute on function zz_dropro_0221() to authenticated;
  perform teste_assert_0221(teste_acusa_0221('zz_dropro_0221'), 'a sonda ACUSA `drop routine fn_trg_so_socio() cascade` (routine, e não só function)', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_dropro_0221();
  create function zz_dropproc_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin drop procedure if exists fn_trg_so_socio(); end $f$;
  grant execute on function zz_dropproc_0221() to authenticated;
  perform teste_assert_0221(teste_acusa_0221('zz_dropproc_0221'), 'a sonda ACUSA `drop procedure fn_trg_so_socio()`', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_dropproc_0221();
  create function zz_alro_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin alter routine fn_trg_so_socio() owner to authenticated; end $f$;
  grant execute on function zz_alro_0221() to authenticated;
  perform teste_assert_0221(teste_acusa_0221('zz_alro_0221'), 'a sonda ACUSA `alter routine fn_trg_so_socio() ...`', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_alro_0221();
  create function zz_alfn_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin alter function fn_trg_so_socio() owner to authenticated; end $f$;
  grant execute on function zz_alfn_0221() to authenticated;
  perform teste_assert_0221(teste_acusa_0221('zz_alfn_0221'), 'a sonda ACUSA `alter function fn_trg_so_socio() ...`', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_alfn_0221();
  create function zz_droplfn_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin drop function if exists zz_a_0221(int), public.fn_trg_so_socio(); end $f$;
  grant execute on function zz_droplfn_0221() to authenticated;
  perform teste_assert_0221(teste_acusa_0221('zz_droplfn_0221'), 'a sonda ACUSA a guarda numa LISTA de `drop function` (depois da vírgula)', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_droplfn_0221();
  -- A guarda é a função de QUALQUER gatilho das tabelas protegidas (pelo catálogo), não o nome fixo.
  create function zz_guarda_nova_0221() returns trigger language plpgsql as $f$ begin return new; end $f$;
  create trigger zz_trg_guarda_0221 before update on premissa_catalogo for each row execute function zz_guarda_nova_0221();
  create function zz_dropguarda_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin drop function zz_guarda_nova_0221() cascade; end $f$;
  grant execute on function zz_dropguarda_0221() to authenticated;
  perform teste_assert_0221(teste_presente_0221('definer_nao_escreve_no_dial'),
    'o DDL da função de um gatilho EXTRA (não declarado pelo catálogo) não acusa: o portão vigia a guarda DECLARADA, e não o que estiver em pg_trigger (um gatilho trocado faria o portão vigiar a função inofensiva)', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_dropguarda_0221();
  drop trigger zz_trg_guarda_0221 on premissa_catalogo;
  create function zz_dropoutra_0221() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin drop function if exists zz_qualquer_0221(int); alter function zz_guarda_nova_0221() rename to zz_x_0221; end $f$;
  grant execute on function zz_dropoutra_0221() to authenticated;
  perform teste_assert_0221(teste_presente_0221('definer_nao_escreve_no_dial'),
    'DDL de função que NÃO é a guarda de nenhuma tabela protegida (a ex-guarda, já sem o gatilho) não acusa', teste_detalhe_0221('definer_nao_escreve_no_dial'));
  drop function zz_dropoutra_0221(); drop function zz_guarda_nova_0221();

  perform teste_assert_0221(teste_presente_0221('definer_nao_escreve_no_dial') and teste_presente_0221('dial_sem_cascata_de_fk'),
    'controle positivo: sem nenhuma função de teste, o banco montado segue VERDE nos dois portões do dial', teste_detalhe_0221('definer_nao_escreve_no_dial'));
end $$;

-- =============================================================================
-- PARTE 5 — idempotência
-- =============================================================================
do $$
begin
  perform set_config('dial.n_req_0221', (select count(*) from instalacao_requisito)::text, false);
  perform set_config('dial.corpo_0221', md5(pg_get_functiondef('fn_instalacao_conferir()'::regprocedure)), false);
end $$;

\i :arq0221

do $$
begin
  raise notice '--- 5. idempotência ---';
  perform teste_assert_0221((select count(*) from instalacao_requisito)::text = current_setting('dial.n_req_0221'),
    'reaplicar a migration não muda o número de requisitos do catálogo', (select count(*) from instalacao_requisito)::text || ' / ' || current_setting('dial.n_req_0221'));
  perform teste_assert_0221(md5(pg_get_functiondef('fn_instalacao_conferir()'::regprocedure)) = current_setting('dial.corpo_0221'), 'e o corpo de fn_instalacao_conferir fica idêntico');
  perform teste_assert_0221((select count(*) from fn_instalacao_conferir() where migration = '0221' and presente) = 6, 'e os 6 requisitos da 0221 seguem presentes');
end $$;

-- O número de execuções tem de ser o do arquivo: assert que sumiu não pode passar calado.
do $$
declare v_esperado constant int := 58;
  v_real int := coalesce(nullif(current_setting('dial.execucoes', true), ''), '0')::int;
begin
  if v_real <> v_esperado then
    raise exception 'FALHOU: o teste da 0221 executou % asserts, e o arquivo declara %. Um bloco saiu antes ou uma chamada sumiu.', v_real, v_esperado;
  end if;
end $$;

select 'FIM 0221: ' || coalesce(current_setting('dial.execucoes', true), '0') || ' execuções, '
       || coalesce(nullif(current_setting('dial.falhas', true), ''), '0') || ' falhas' as medicao;

rollback;
