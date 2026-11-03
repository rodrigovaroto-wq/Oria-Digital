-- =============================================================================
-- 0220 — O PORTÃO DO DIAL QUE SÓ VIA O NOME DA TABELA SEGUIDO DE ESPAÇO, `;`, FIM OU `(`
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md): 37 dos 37 asserts medidos (cada chamada roda uma vez). Controle intacto: 37 ok, 0 falhas.
-- O número por correção desligada está no cabeçalho de Supabase/migrations/0220_o_portao_do_dial_que_so_via_espaco_e_parentese.sql ("MEDIÇÃO NÃO-VAZIA").
--
-- COMO RODA. Uma transação só (`begin` ... `rollback`). O teste REAPLICA o arquivo da migration (`\i`) logo no começo — com o arquivo real ele é um no-op (a migration é idempotente) e
-- é isso que prova a idempotência; com `-v arq0220=<arquivo>` ele aplica uma VARIANTE da migration, e é assim que se mede cada correção desligada. O JWT (`request.jwt.claims`) é SEMPRE
-- definido de forma explícita: o banco de teste guarda o de um Sócio em pg_db_role_setting, e num banco copiado ele pode estar vazio.
-- `dial.medindo = on` (PGOPTIONS='-c dial.medindo=on') vira `raise warning` e CONTA: é como se mede quantos asserts uma variante reprova sem parar no primeiro.
-- O FIM do arquivo confere o número de execuções: assert que sumiu (um bloco que saiu cedo, uma chamada apagada) reprova em vez de passar calado (regra 7).
--
-- O QUE AFIRMA (comportamento, não mecanismo):
--   1. No banco montado, o portão está verde e todos os ramos da sonda estão vivos (segredo, sem_privilegio, definer_sem_escrita, sem_acao_referencial), com os 13 tipos na constraint.
--   2. Uma função SECURITY DEFINER com EXECUTE para authenticated que escreve no dial ou no catálogo de premissas por qualquer destas formas é ACUSADA: o DML numa CTE sem filtro
--      (`with d as (delete from premissa_catalogo) select`), o `truncate premissa_catalogo, x` (a protegida antes da vírgula), as aspas coladas (`delete from"t"`) e o comentário entre a
--      palavra e o nome. E o risco é real: a Analista chama a definer e o catálogo some (a burla é medida, dentro de uma subtransação que volta).
--   3. A aresta do GATILHO (a definer escreve numa tabela cujo gatilho escreve no dial) enxerga o mesmo formato, e a parte B da FK (o filho com gatilho que escreve no dial) também.
--   4. Nada acusado a mais: nome de tabela parecido, leitura em subconsulta, a palavra num comentário, função fechada ao authenticated.
--   5. VIEW atualizável e RULE sobre o catálogo NÃO burlam a guarda (42501): o comentário da 0219 que os declarava pontos cegos estava errado.
--   6. Reaplicar a migration não muda nada.
-- =============================================================================

\set ON_ERROR_STOP on
\if :{?arq0220}
\else
  \set arq0220 'Supabase/migrations/0220_o_portao_do_dial_que_so_via_espaco_e_parentese.sql'
\endif

begin;

create or replace function teste_assert_0220(p_cond boolean, p_nome text, p_detalhe text default null)
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

-- Executa um comando COMO o papel corrente: 'ok:<linhas>' ou o SQLSTATE.
create or replace function teste_tenta_0220(p_sql text) returns text
language plpgsql as $$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return 'ok:' || n;
exception when others then
  return sqlstate;
end $$;

create or replace function teste_como_0220(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create or replace function teste_super_0220(p_socio uuid) returns void
language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_socio, 'role', 'authenticated')::text, true);
end $$;

-- A BURLA, medida: a Analista chama a RPC `p_fn()` e contamos as linhas de `p_tab` antes e depois. Tudo dentro de uma SUBTRANSAÇÃO que volta (o `raise` com SQLSTATE próprio): o catálogo
-- reaparece inteiro. Devolve 'ok:<n>|<antes>|<depois>' (ou o SQLSTATE no lugar de ok:<n>).
create or replace function teste_burla_0220(p_ana uuid, p_socio uuid, p_fn text, p_tab text) returns text
language plpgsql as $$
declare v_antes bigint; v_dep bigint; v_t text;
begin
  execute format('select count(*) from %I', p_tab) into v_antes;
  begin
    perform teste_como_0220(p_ana);
    v_t := teste_tenta_0220(format('select %I()', p_fn));
    perform teste_super_0220(p_socio);
    execute format('select count(*) from %I', p_tab) into v_dep;
    raise exception 'desfaz a burla' using errcode = 'P0220';
  exception when sqlstate 'P0220' then null;
  end;
  perform teste_super_0220(p_socio);
  return v_t || '|' || v_antes || '|' || v_dep;
end $$;

-- A sonda acusa a função `p_fn` no requisito `p_chave`? (presente = false e o nome da função no detalhe)
create or replace function teste_acusa_0220(p_chave text, p_fn text) returns boolean
language sql as $$
  select coalesce((select not presente and detalhe like '%' || p_fn || '%' from fn_instalacao_conferir() where chave = p_chave), false) $$;

-- A migration sob teste: o arquivo real (no-op) ou a variante.
\i :arq0220

-- =============================================================================
-- PARTE 1 — O ESTADO LIMPO: o portão verde, os ramos vivos, os 13 tipos, os 3 requisitos da 0220
-- =============================================================================
do $$
begin
  raise notice '--- 1. estado limpo ---';
  perform teste_assert_0220((select presente and severidade = 'bloqueante' from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'),
    'estado limpo: definer_nao_escreve_no_dial presente e BLOQUEANTE', (select detalhe from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'));
  perform teste_assert_0220((select presente and severidade = 'bloqueante' from fn_instalacao_conferir() where chave = 'dial_sem_cascata_de_fk'),
    'estado limpo: dial_sem_cascata_de_fk presente e BLOQUEANTE', (select detalhe from fn_instalacao_conferir() where chave = 'dial_sem_cascata_de_fk'));
  perform teste_assert_0220((select count(*) from fn_instalacao_conferir() where migration = '0220' and presente) = 3
                            and (select count(*) from instalacao_requisito where migration = '0220') = 3,
    'os 3 requisitos da 0220 estão no catálogo e PRESENTES (a sonda prova em produção que a 0220 foi aplicada)',
    (select string_agg(chave || '=' || presente, ', ') from fn_instalacao_conferir() where migration = '0220'));
  perform teste_assert_0220(not exists (select 1 from fn_instalacao_conferir() where migration in ('0219', '0220') and not presente),
    'nenhum requisito da 0219 nem da 0220 está ausente',
    (select string_agg(chave, ', ') from fn_instalacao_conferir() where migration in ('0219', '0220') and not presente));
  -- Os quatro ramos que a reemissão tinha de preservar: cada um RESPONDE (a linha existe e o detalhe não é de requisito mal declarado nem de erro).
  perform teste_assert_0220((select count(*) from fn_instalacao_conferir() where tipo = 'segredo') >= 1
                            and (select bool_and(presente) from fn_instalacao_conferir() where tipo = 'segredo'),
    'o ramo `segredo` (0217) segue vivo e verde na reemissão (o banco de teste traz o segredo do Vault)');
  perform teste_assert_0220((select count(*) from fn_instalacao_conferir() where tipo = 'sem_privilegio') >= 1
                            and (select bool_and(presente) from fn_instalacao_conferir() where tipo = 'sem_privilegio'),
    'o ramo `sem_privilegio` (0218) segue vivo e verde na reemissão');
  perform teste_assert_0220((select count(*) from fn_instalacao_conferir() where tipo = 'definer_sem_escrita') >= 1
                            and (select bool_and(presente) from fn_instalacao_conferir() where tipo = 'definer_sem_escrita'),
    'o ramo `definer_sem_escrita` (0219) segue vivo e verde na reemissão');
  perform teste_assert_0220((select count(*) from fn_instalacao_conferir() where tipo = 'sem_acao_referencial') >= 1
                            and (select bool_and(presente) from fn_instalacao_conferir() where tipo = 'sem_acao_referencial'),
    'o ramo `sem_acao_referencial` (0219) segue vivo e verde na reemissão');
  perform teste_assert_0220((select count(*) from regexp_matches((select pg_get_constraintdef(oid) from pg_constraint where conname = 'instalacao_requisito_tipo_check'), '''[a-z_]+''', 'g')) = 13,
    'a constraint de tipo segue com os 13 tipos da 0219 (a 0220 não criou tipo)',
    (select pg_get_constraintdef(oid) from pg_constraint where conname = 'instalacao_requisito_tipo_check'));
end $$;

-- =============================================================================
-- PARTE 2 — O FALSO VERDE: a definer que escreve no dial por um formato que o v_pos/v_pre antigo não via
-- =============================================================================
do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000000e901';
  u_ana   uuid := '00000000-0000-0000-0000-00000000e902';
  v_t text;
begin
  insert into auth.users (id, email) values (u_socio, 'socio@0220.local'), (u_ana, 'ana@0220.local');
  perform fn_definir_papel(u_socio, 'socio', 'teste 0220');
  perform fn_definir_papel(u_ana, 'analista');
  perform teste_super_0220(u_socio);
  -- sem filhos do catálogo, o DELETE sem filtro do CTE não esbarra na FK (a transação volta)
  delete from caso_linha_premissa;
  delete from caso_premissa;

  raise notice '--- 2a. with d as (delete from premissa_catalogo) select: o `)` depois do nome ---';
  create function zz_cte_0220() returns int language sql security definer set search_path = public, pg_temp
    as $f$ with d as (delete from premissa_catalogo) select 1 $f$;
  revoke all on function zz_cte_0220() from public;
  grant execute on function zz_cte_0220() to authenticated;
  v_t := teste_burla_0220(u_ana, u_socio, 'zz_cte_0220', 'premissa_catalogo');
  perform teste_assert_0220(split_part(v_t, '|', 1) = 'ok:1' and split_part(v_t, '|', 2)::int > 0 and split_part(v_t, '|', 3)::int = 0,
    'a BURLA é real: a Analista chama a definer do CTE e o catálogo de premissas vai de N a 0 linhas (a guarda de Sócio confia no dono)', v_t);
  perform teste_super_0220(u_socio);
  perform teste_assert_0220(teste_acusa_0220('definer_nao_escreve_no_dial', 'zz_cte_0220'),
    'a sonda ACUSA a definer com `with d as (delete from premissa_catalogo) select` (nome seguido de `)`)',
    (select detalhe from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'));
  drop function zz_cte_0220();
  perform teste_assert_0220((select presente from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'),
    'removida a função, o portão volta a verde (era ela que acusava)');

  raise notice '--- 2b. (delete from estagio_autonomia): o `)` depois do nome, no dial ---';
  create function zz_cte_dial_0220() returns int language sql security definer set search_path = public, pg_temp
    as $f$ with d as (delete from estagio_autonomia) select 1 $f$;
  grant execute on function zz_cte_dial_0220() to authenticated;
  perform teste_assert_0220(teste_acusa_0220('definer_nao_escreve_no_dial', 'zz_cte_dial_0220'),
    'a sonda ACUSA a definer com `(delete from estagio_autonomia)` em CTE', (select detalhe from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'));
  drop function zz_cte_dial_0220();

  raise notice '--- 2c. truncate premissa_catalogo, x: a vírgula depois do nome ---';
  create function zz_trunc_0220() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin truncate premissa_catalogo, caso_premissa; end $f$;
  grant execute on function zz_trunc_0220() to authenticated;
  perform teste_assert_0220(teste_acusa_0220('definer_nao_escreve_no_dial', 'zz_trunc_0220'),
    'a sonda ACUSA a definer com `truncate premissa_catalogo, caso_premissa` (a protegida antes da vírgula)', (select detalhe from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'));
  drop function zz_trunc_0220();
  create function zz_trunc2_0220() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin truncate table only caso_premissa, estagio_autonomia, caso_linha_premissa; end $f$;
  grant execute on function zz_trunc2_0220() to authenticated;
  perform teste_assert_0220(teste_acusa_0220('definer_nao_escreve_no_dial', 'zz_trunc2_0220'),
    'a sonda ACUSA o truncate com a protegida no MEIO da lista (vírgula dos dois lados)', (select detalhe from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'));
  drop function zz_trunc2_0220();

  raise notice '--- 2d. as aspas coladas na palavra: delete from"t", update"t" ---';
  create function zz_aspas_0220() returns int language sql security definer set search_path = public, pg_temp
    as $f$ with d as (delete from"premissa_catalogo") select 1 $f$;
  grant execute on function zz_aspas_0220() to authenticated;
  v_t := teste_burla_0220(u_ana, u_socio, 'zz_aspas_0220', 'premissa_catalogo');
  perform teste_assert_0220(split_part(v_t, '|', 1) = 'ok:1' and split_part(v_t, '|', 2)::int > 0 and split_part(v_t, '|', 3)::int = 0,
    'a BURLA com `delete from"premissa_catalogo"` (aspas coladas, SQL válido) é real: o catálogo vai de N a 0', v_t);
  perform teste_super_0220(u_socio);
  perform teste_assert_0220(teste_acusa_0220('definer_nao_escreve_no_dial', 'zz_aspas_0220'),
    'a sonda ACUSA o `delete from"premissa_catalogo"` (aspas coladas na palavra)', (select detalhe from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'));
  drop function zz_aspas_0220();
  create function zz_aspas2_0220() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin update"estagio_autonomia" set atualizado_por = atualizado_por; end $f$;
  grant execute on function zz_aspas2_0220() to authenticated;
  perform teste_assert_0220(teste_acusa_0220('definer_nao_escreve_no_dial', 'zz_aspas2_0220'),
    'a sonda ACUSA o `update"estagio_autonomia" set` (aspas coladas)', (select detalhe from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'));
  drop function zz_aspas2_0220();

  raise notice '--- 2e. comentário entre a palavra e o nome ---';
  create function zz_coment_0220() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin delete from /* só os de ontem */ premissa_catalogo where false; end $f$;
  grant execute on function zz_coment_0220() to authenticated;
  perform teste_assert_0220(teste_acusa_0220('definer_nao_escreve_no_dial', 'zz_coment_0220'),
    'a sonda ACUSA o `delete from /* c */ premissa_catalogo` (comentário de bloco no meio)', (select detalhe from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'));
  drop function zz_coment_0220();
  create function zz_coment2_0220() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin update -- o dial
      estagio_autonomia set atualizado_por = atualizado_por; end $f$;
  grant execute on function zz_coment2_0220() to authenticated;
  perform teste_assert_0220(teste_acusa_0220('definer_nao_escreve_no_dial', 'zz_coment2_0220'),
    'a sonda ACUSA o `update -- comentário<quebra> estagio_autonomia` (comentário de linha no meio)', (select detalhe from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'));
  drop function zz_coment2_0220();

  raise notice '--- 2f. a aresta do GATILHO usa o mesmo formato: a definer escreve numa tabela cujo gatilho escreve no dial ---';
  create table zz_t_0220 (x int);
  create function zz_trg_0220() returns trigger language plpgsql set search_path = public, pg_temp
    as $f$ begin update estagio_autonomia set atualizado_por = atualizado_por; return old; end $f$;
  create trigger zz_trg_0220 before delete on zz_t_0220 for each row execute function zz_trg_0220();
  create function zz_via_gatilho_0220() returns int language sql security definer set search_path = public, pg_temp
    as $f$ with d as (delete from zz_t_0220) select 1 $f$;
  grant execute on function zz_via_gatilho_0220() to authenticated;
  perform teste_assert_0220(teste_acusa_0220('definer_nao_escreve_no_dial', 'zz_via_gatilho_0220'),
    'a sonda ACUSA a definer que apaga numa tabela com `(delete from zz_t_0220)` cujo gatilho escreve no dial (aresta do gatilho com `)`)',
    (select detalhe from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'));
  drop function zz_via_gatilho_0220();
  drop table zz_t_0220;
  drop function zz_trg_0220();
  perform teste_assert_0220((select presente from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'), 'sem as funções de teste o portão está verde de novo');

  raise notice '--- 2g. o que NÃO é perigoso não é acusado (senão o `)` e a vírgula viram ruído) ---';
  create function zz_parecida_0220() returns void language plpgsql security definer set search_path = public, pg_temp
    as $f$ begin delete from premissa_catalogo_historico_0220 where false; update estagio_autonomiax set a = 1; truncate zz_outra_0220, premissa_catalogox; end $f$;
  grant execute on function zz_parecida_0220() to authenticated;
  perform teste_assert_0220((select presente from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'),
    'nome de tabela PARECIDO (premissa_catalogo_historico_0220, estagio_autonomiax, premissa_catalogox) não é acusado', (select detalhe from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'));
  drop function zz_parecida_0220();
  create function zz_leitura_0220() returns bigint language sql security definer set search_path = public, pg_temp
    as $f$ select (select count(*) from premissa_catalogo) + (select count(*) from estagio_autonomia where estagio in (select estagio from estagio_autonomia)) $f$;
  grant execute on function zz_leitura_0220() to authenticated;
  perform teste_assert_0220((select presente from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'),
    'leitura do catálogo e do dial entre parênteses, em subconsulta, NÃO é acusada (o `)` só vale depois de uma palavra de escrita)', (select detalhe from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'));
  drop function zz_leitura_0220();
  create function zz_fechada_0220() returns int language sql security definer set search_path = public, pg_temp
    as $f$ with d as (delete from premissa_catalogo) select 1 $f$;
  revoke all on function zz_fechada_0220() from public;
  perform teste_assert_0220((select presente from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'),
    'a definer do CTE FECHADA ao authenticated (sem EXECUTE) não é acusada: só a alcançável pelo portal conta', (select detalhe from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'));
  drop function zz_fechada_0220();
end $$;

-- =============================================================================
-- PARTE 3 — A PARTE B DA FK: o filho tem gatilho cujo corpo escreve no dial por um formato que o v_pos antigo não via
-- =============================================================================
do $$
begin
  raise notice '--- 3. FK com ação referencial cujo FILHO tem gatilho que escreve no dial ---';
  create table zz_pai_0220 (id int primary key);
  create table zz_filho_0220 (id int primary key, pai_id int references zz_pai_0220 (id) on delete set null);
  create function zz_trg_filho_0220() returns trigger language plpgsql set search_path = public, pg_temp
    as $f$ declare n int; begin with d as (delete from estagio_autonomia) select 1 into n; return new; end $f$;
  create trigger zz_trg_filho_0220 before update on zz_filho_0220 for each row execute function zz_trg_filho_0220();
  perform teste_assert_0220((select not presente and detalhe like '%zz_filho_0220%' from fn_instalacao_conferir() where chave = 'dial_sem_cascata_de_fk'),
    'a FK ON DELETE SET NULL cujo filho tem gatilho com `(delete from estagio_autonomia)` é ACUSADA (parte B da FK: v_pos com `)`)',
    (select detalhe from fn_instalacao_conferir() where chave = 'dial_sem_cascata_de_fk'));
  drop trigger zz_trg_filho_0220 on zz_filho_0220;
  drop function zz_trg_filho_0220();
  create function zz_trg_filho_0220() returns trigger language plpgsql set search_path = public, pg_temp
    as $f$ begin truncate premissa_catalogo, caso_premissa; return new; end $f$;
  create trigger zz_trg_filho_0220 before update on zz_filho_0220 for each row execute function zz_trg_filho_0220();
  perform teste_assert_0220((select not presente and detalhe like '%zz_filho_0220%' from fn_instalacao_conferir() where chave = 'dial_sem_cascata_de_fk'),
    'a mesma FK, com o gatilho do filho em `truncate premissa_catalogo, caso_premissa` (vírgula), é ACUSADA',
    (select detalhe from fn_instalacao_conferir() where chave = 'dial_sem_cascata_de_fk'));
  drop trigger zz_trg_filho_0220 on zz_filho_0220;
  drop function zz_trg_filho_0220();
  create function zz_trg_filho_0220() returns trigger language plpgsql set search_path = public, pg_temp
    as $f$ begin delete from"estagio_autonomia" where false; return new; end $f$;
  create trigger zz_trg_filho_0220 before update on zz_filho_0220 for each row execute function zz_trg_filho_0220();
  perform teste_assert_0220((select not presente and detalhe like '%zz_filho_0220%' from fn_instalacao_conferir() where chave = 'dial_sem_cascata_de_fk'),
    'a mesma FK, com o gatilho do filho em `delete from"estagio_autonomia"` (aspas coladas), é ACUSADA',
    (select detalhe from fn_instalacao_conferir() where chave = 'dial_sem_cascata_de_fk'));
  drop table zz_filho_0220;
  drop table zz_pai_0220;
  drop function zz_trg_filho_0220();
  perform teste_assert_0220((select presente from fn_instalacao_conferir() where chave = 'dial_sem_cascata_de_fk'), 'sem o arranjo de teste a FK está verde de novo');
end $$;

-- =============================================================================
-- PARTE 4 — VIEW atualizável e RULE NÃO são ponto cego: a guarda de Sócio os recusa (o comentário da 0219 estava errado)
-- =============================================================================
do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000000e901';
  u_ana   uuid := '00000000-0000-0000-0000-00000000e902';
  v_t text;
begin
  raise notice '--- 4. escrita por VIEW atualizável e por RULE: a Analista leva 42501 ---';
  create view zz_view_0220 as select * from premissa_catalogo;
  grant select, update on zz_view_0220 to authenticated;
  perform teste_como_0220(u_ana);
  v_t := teste_tenta_0220($q$update zz_view_0220 set ativo = ativo where codigo = 'IPCA'$q$);
  perform teste_super_0220(u_socio);
  perform teste_assert_0220(v_t = '42501', 'a Analista NÃO altera o catálogo por VIEW atualizável do dono (42501: current_user segue authenticated)', v_t);
  perform teste_assert_0220((select presente from fn_instalacao_conferir() where chave = 'definer_nao_escreve_no_dial'), 'e a view não vira acusação: não é função');
  perform teste_super_0220(u_socio);
  v_t := teste_tenta_0220($q$update zz_view_0220 set ativo = ativo where codigo = 'IPCA'$q$);
  perform teste_assert_0220(v_t = 'ok:1', 'controle: o Sócio altera o catálogo pela mesma view (ela funciona; o que barrou a Analista foi a guarda)', v_t);
  drop view zz_view_0220;

  create table zz_regra_0220 (x int);
  create rule zz_regra_0220 as on update to zz_regra_0220 do also update premissa_catalogo set ativo = ativo where codigo = 'IPCA';
  insert into zz_regra_0220 values (1);
  grant select, update on zz_regra_0220 to authenticated;
  perform teste_como_0220(u_ana);
  v_t := teste_tenta_0220($q$update zz_regra_0220 set x = 2$q$);
  perform teste_super_0220(u_socio);
  perform teste_assert_0220(v_t = '42501', 'a Analista NÃO altera o catálogo por RULE do dono (42501: a ação da regra dispara a guarda, com current_user authenticated)', v_t);
  v_t := teste_tenta_0220($q$update zz_regra_0220 set x = 3$q$);
  perform teste_assert_0220(v_t = 'ok:1', 'controle: o Sócio dispara a mesma regra (ela funciona; o que barrou a Analista foi a guarda)', v_t);
  drop table zz_regra_0220;
end $$;

-- =============================================================================
-- PARTE 5 — A MIGRATION REAPLICADA NÃO MUDA NADA, e o corpo da sonda segue com os marcadores
-- =============================================================================
do $$
begin
  perform set_config('dial.n_req_0220', (select count(*) from instalacao_requisito)::text, false);
  perform set_config('dial.corpo_0220', md5(pg_get_functiondef('fn_instalacao_conferir()'::regprocedure)), false);
end $$;

\i :arq0220

do $$
begin
  raise notice '--- 5. idempotência ---';
  perform teste_assert_0220((select count(*) from instalacao_requisito)::text = current_setting('dial.n_req_0220'),
    'reaplicar a migration não muda o número de requisitos do catálogo', (select count(*) from instalacao_requisito)::text || ' / ' || current_setting('dial.n_req_0220'));
  perform teste_assert_0220(md5(pg_get_functiondef('fn_instalacao_conferir()'::regprocedure)) = current_setting('dial.corpo_0220'), 'e o corpo de fn_instalacao_conferir fica idêntico');
  perform teste_assert_0220((select count(*) from fn_instalacao_conferir() where migration = '0220' and presente) = 3, 'e os 3 requisitos da 0220 seguem presentes');
end $$;

-- O número de execuções tem de ser o do arquivo: assert que sumiu não pode passar calado.
do $$
declare v_esperado constant int := 37;
  v_real int := coalesce(nullif(current_setting('dial.execucoes', true), ''), '0')::int;
begin
  if v_real <> v_esperado then
    raise exception 'FALHOU: o teste da 0220 executou % asserts, e o arquivo declara %. Um bloco saiu antes ou uma chamada sumiu.', v_real, v_esperado;
  end if;
end $$;

select 'FIM 0220: ' || coalesce(current_setting('dial.execucoes', true), '0') || ' execuções, '
       || coalesce(nullif(current_setting('dial.falhas', true), ''), '0') || ' falhas' as medicao;

rollback;
