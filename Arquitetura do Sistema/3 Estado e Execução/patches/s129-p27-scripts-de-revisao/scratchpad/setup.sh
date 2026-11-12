#!/usr/bin/env bash
# Aplica as migrations num Postgres local, carrega os fixtures dos DOIS books
# (Vertentes, o fácil; Canastra, o difícil) e roda os testes de reconciliação.
#
#   Supabase/test/run.sh                     # usa um Postgres já rodando (PGHOST/PGPORT/PGUSER)
#   PGPORT=5599 Supabase/test/run.sh         # porta alternativa
#
# Precisa de um Postgres 16 acessível e de permissão para criar banco. Não toca
# em Supabase — é tudo local e descartável (o banco é recriado a cada execução).
set -euo pipefail

DB="${TEST_DB:-tdf_test}"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd /home/user/Oria-Digital

psql -q -c "drop database if exists $DB" -c "create database $DB"

# Papéis e schema que o Supabase provê por padrão e as migrations assumem.
for r in anon authenticated service_role; do
  psql -tAc "select 1 from pg_roles where rolname='$r'" | grep -q 1 \
    || psql -q -c "create role $r nologin"
done
# O leitor SÓ-LEITURA da API de gerenciamento do Supabase, criado ANTES das migrations, como é em produção (membro de pg_monitor e pg_read_all_data, rolbypassrls = true;
# nologin aqui). Sem isto as migrations rodavam sem o papel e o bloco `if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user')` dos grants nunca
# executava: a 0242 chegou a produção com a sonda ilegível para esse leitor ("permission denied for function fn_conta_canonica_orfas") e nenhum teste acusou (11/11/2026).
psql -tAc "select 1 from pg_roles where rolname='supabase_read_only_user'" | grep -q 1 \
  || psql -q -c "create role supabase_read_only_user nologin bypassrls"
psql -q -c "alter role supabase_read_only_user nologin bypassrls" -c "grant pg_read_all_data, pg_monitor to supabase_read_only_user"
psql -q -d "$DB" -c "
  create schema if not exists storage;
  create table if not exists storage.buckets(id text primary key, name text, public boolean default false,
    versioning_status text default 'DISABLED');  -- 0224: a coluna que a sonda lê (o Storage real a tem; produção: DISABLED em documentos)
  create table if not exists storage.objects(id uuid default gen_random_uuid() primary key,
    bucket_id text, name text, owner uuid, metadata jsonb,  -- 0224: metadata (size) como no Storage real; o gatilho de auditoria lê o tamanho
    is_delete_marker boolean default false, archived_at timestamptz);  -- 0224: colunas do versionamento (nomes NÃO conferidos em produção; o gatilho as lê por to_jsonb e tolera a ausência)
  alter table storage.objects enable row level security;
  -- 0216: o Supabase concede ao authenticated o uso do schema storage e as quatro operações em storage.objects (o que
  -- limita é a policy); sem isto o teste de acesso ao Storage por mandato leva 42501 antes de a policy ser avaliada.
  -- 0224: service_role ignora RLS no Supabase real (BYPASSRLS); a etapa 2 da API do Storage apaga como ele, e o teste precisa disso para simular o caminho real.
  alter role service_role bypassrls;
  grant usage on schema storage to authenticated, service_role;
  grant select, insert, update, delete on storage.objects to authenticated, service_role;
  -- 0216: o schema auth do Supabase (usuários e auth.uid()), no mínimo que as migrations e os testes usam. O
  -- auth.uid() é o do Supabase: lê o sub de request.jwt.claims, que o PostgREST preenche por requisição.
  create schema if not exists auth;
  create table if not exists auth.users(id uuid primary key default gen_random_uuid(), email text, created_at timestamptz not null default now());
  create or replace function auth.uid() returns uuid language sql stable as \$\$
    select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid \$\$;
  grant usage on schema auth to anon, authenticated, service_role;" >/dev/null

# 0217: o Vault do Supabase (`supabase_vault`, schema `vault`) no mínimo que a conferência do envio usa: a view
# `vault.decrypted_secrets` (name, decrypted_secret) e as duas funções que o cabeçalho da migration manda o dono chamar. A
# extensão real cifra `secret`; aqui o valor fica em claro porque o que se testa é a CONFERÊNCIA, não a cifra. Em produção nada
# disto existe (a extensão cria o schema). O banco montado traz o segredo `n8n_intake_segredo` com um valor de TESTE — é o estado
# "instalação completa" que a sonda exige (requisito `envio_segredo_no_vault`); `conferir_envio.test.sql` o troca/remove dentro
# de uma transação e desfaz.
psql -q -d "$DB" -c "
  create schema if not exists vault;
  create table vault.secrets(id uuid primary key default gen_random_uuid(), name text unique, description text,
    secret text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
  create view vault.decrypted_secrets as
    select id, name, description, secret, secret as decrypted_secret, created_at, updated_at from vault.secrets;
  create function vault.create_secret(new_secret text, new_name text default null, new_description text default '')
    returns uuid language sql as \$\$
    insert into vault.secrets(name, description, secret) values (new_name, new_description, new_secret) returning id \$\$;
  create function vault.update_secret(secret_id uuid, new_secret text default null) returns void language sql as \$\$
    update vault.secrets set secret = coalesce(new_secret, secret), updated_at = now() where id = secret_id \$\$;
  select vault.create_secret('segredo-de-teste-do-run-sh', 'n8n_intake_segredo', 'stub local');" >/dev/null

# O SUPABASE NOVO NÃO CONCEDE MAIS NADA POR DEFAULT PRIVILEGE (20/10/2026). Até 29/10/2026 o projeto trazia
# `alter default privileges in schema public grant all on tables/sequences to anon, authenticated, service_role`, e este
# script SIMULAVA isso — "nenhuma migration faz GRANT de tabela porque conta com isso". A partir de 30/10/2026 tabela
# criada em `public` nasce SEM grant (projeto novo, preview branch, `supabase db reset`; as existentes mantêm o que
# têm). Medido aqui: 51 `create table` nas migrations, 39 sem nenhum GRANT — a mais recente, `controlador_vinculo`
# (0212), entre elas. Com a simulação mantida o CI continuaria verde depois de 30/10 enquanto a primeira tabela nova
# nascia em produção sem acesso ("permission denied" no portal): estágio que não rodou com cara de estágio que rodou
# (regra 7). Por isso o replay aqui é o do Supabase NOVO: só `usage` no schema, nenhum default privilege. Medido ao
# remover a simulação: o replay morria na 0028 (a verificação embutida roda como authenticated) e, consertada ela, o
# `resumo_oficial.test.sql` caía em "permission denied for table caso". Quem concede agora é a `0214` (as tabelas que
# existem até ali, preservando os revokes intencionais) e, daí em diante, a própria migration que cria a tabela
# (convenção em `Supabase/README.md`); quem cobra é a sonda (`tipo = privilegio`, 0214), via `instalacao.test.sql`.
# O mesmo vale para o achado original deste bloco — Supabase/migrations/0028 (índices macro sem RLS nem grant): um
# defeito de AUTORIZAÇÃO só aparece num teste que roda como `authenticated`, e sem grant `set role authenticated`
# falha para QUALQUER tabela; por isso o que se mede é o grant concedido, não a ausência dele.
#
# Função é DIFERENTE de tabela, e não replicamos o lado de função aqui — de
# propósito, depois de medir. Em produção o Supabase impede EXECUTE público em
# função nova (é por isso que este projeto já tem, desde a sessão 8, `grant
# execute ... to authenticated` explícito em toda função chamada PELO PORTAL:
# 0008 `fn_revisar_documento`, 0011 `fn_aceitar_extracao`, 0028
# `fn_indice_macro_anual`). Tentei replicar isso aqui com `alter default
# privileges ... revoke execute on functions from public` e MEDI que não
# funciona neste Postgres: a revoke não grava linha em `pg_default_acl` (objtype
# 'f') e função criada depois continua executável por PUBLIC — plain Postgres
# não tem como REVOGAR um default que nunca foi GRANTado por default privilege
# (o hardcoded "PUBLIC pode executar" não passa por ali). O mecanismo real do
# Supabase para isso não é `ALTER DEFAULT PRIVILEGES` puro. Por isso os `grant
# execute` em migration continuam sendo o único jeito CORRETO de garantir o
# acesso em produção — só não dá para provar aqui, com teste local, que a
# ausência deles quebraria (o teste da 0028 exercita a chamada como smoke test,
# não como negativo).
psql -q -d "$DB" -c "
  grant usage on schema public to anon, authenticated, service_role;"

