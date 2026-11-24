#!/usr/bin/env bash
# CÓPIA DE SEGURANÇA DO BANCO, COM PROVA DE QUE ELA TEM O QUE O BANCO TEM (Fase A, fatia A1).
#
#   BACKUP_DB_URL=postgresql://...  PGHOST=localhost PGUSER=postgres PGPASSWORD=... \
#     Supabase/backup/copia-do-banco.sh copiar   <pasta>   # passos 1-3: a cópia
#     Supabase/backup/copia-do-banco.sh conferir <pasta>   # passos 4-5: restaurar e comparar
#
# Dois modos porque o workflow guarda o artefato ENTRE eles: se a conferência reprovar, a cópia do
# dia ainda existe e o job fica vermelho dizendo o que não bateu.
#
# A ORIGEM vem só da `BACKUP_DB_URL` (URL completa: as variáveis PG* não a alteram). O DESTINO da
# restauração é o Postgres descartável apontado pelas variáveis PG* do libpq; o banco `restauro`
# (ou $RESTAURO_DB) é apagado e recriado lá.
#
# Faz, nesta ordem:
#   1. abre UMA transação somente-leitura com `row_security = off` e exporta o snapshot dela;
#   2. conta as linhas de 5 tabelas-chave DENTRO desse snapshot;
#   3. roda o pg_dump no MESMO snapshot (`--snapshot`): contagem e cópia veem o mesmo instante,
#      então a comparação é de igualdade, sem tolerância para escrita concorrente;
#   4. restaura a cópia num Postgres descartável, conta as mesmas 5 tabelas e compara;
#   5. roda a sonda (`fn_instalacao_conferir`) na cópia restaurada e em produção e compara o
#      conjunto do que falta: a cópia não pode faltar nada que produção tem.
#
# POR QUE O `row_security = off` NA CONTAGEM. A armadilha conhecida da cópia é o papel que passa
# pela RLS: ele lê só as linhas que a policy deixa e o arquivo sai VAZIO, SEM ERRO (plano da Fase A,
# §5 A1). Comparar a cópia com uma contagem feita pelo MESMO papel não pegaria nada — os dois lados
# sairiam vazios e iguais. Com `row_security = off`, o Postgres RECUSA a consulta ("query would be
# affected by row-level security policy") em vez de filtrá-la: o papel errado vira erro em voz alta
# no passo 2, antes de existir cópia. E as tabelas-chave precisam ter linha (> 0): um banco vazio ou
# o projeto errado também daria igualdade.
#
# POR QUE RESTAURAR TODO DIA, e não "uma vez". A cópia que nunca foi restaurada tem a mesma aparência
# da que restaura (regra 7). Custa um Postgres descartável no runner por alguns minutos.
#
# O QUE FICA FORA, de propósito: os schemas internos do Supabase (vault, realtime, extensions,
# supabase_functions…) — não são dados da Oria e não se restauram fora do Supabase. Os segredos do
# Vault NÃO estão nesta cópia: numa restauração de verdade, cadastrá-los de novo (o requisito
# `envio_segredo_no_vault` da sonda acusa a falta).
set -euo pipefail

MODO="${1:?uso: copia-do-banco.sh copiar|conferir <pasta>}"
OUT="${2:?uso: copia-do-banco.sh copiar|conferir <pasta>}"
: "${BACKUP_DB_URL:?BACKUP_DB_URL vazio}"
RESTAURO_DB="${RESTAURO_DB:-restauro}"
# As 5 tabelas-chave: o mandato, o documento, a entidade, a pendência e a reconciliação — as que
# respondem "o trabalho da Oria está aqui". Em 13/11/2026 produção tinha 81 casos, 2.999 pendências
# e 7.599 reconciliações (ESTADO.md, sessão da 0277): nenhuma delas é vazia de verdade.
TABELAS="caso documento entidade pendencia reconciliacao"
SCHEMAS="-n public -n auth -n storage"

mkdir -p "$OUT"
log() { printf '[copia] %s\n' "$*" >&2; }

if [ "$MODO" = copiar ]; then

# ---------- 1-2. snapshot e contagem ----------
fifo="$(mktemp -u)"; mkfifo "$fifo"
saida="$OUT/.sessao.txt"; : >"$saida"
psql "$BACKUP_DB_URL" -X -qAt -v ON_ERROR_STOP=1 <"$fifo" >"$saida" 2>&1 &
pid_sessao=$!
exec 3>"$fifo"
trap 'exec 3>&- 2>/dev/null || true; kill $pid_sessao 2>/dev/null || true; rm -f "$fifo"' EXIT

consulta_contagem=""
for t in $TABELAS; do
  consulta_contagem+="${consulta_contagem:+ union all }select 'n|$t|' || count(*) from public.$t"
done
cat >&3 <<SQL
begin isolation level repeatable read read only;
set local row_security = off;
select 'snap|' || pg_export_snapshot();
$consulta_contagem;
SQL

# espera as 1 + 5 linhas (ou o psql morrer com erro)
for _ in $(seq 1 120); do
  [ "$(grep -c '^n|' "$saida" || true)" -ge 5 ] && break
  kill -0 $pid_sessao 2>/dev/null || break
  sleep 1
done
if [ "$(grep -c '^n|' "$saida" || true)" -lt 5 ]; then
  log "ERRO: a sessão de contagem falhou ou não respondeu (papel que passa pela RLS cai aqui). Saída do psql:"; cat "$saida" >&2
  exit 1
fi
snap="$(sed -n 's/^snap|//p' "$saida")"
grep '^n|' "$saida" | sed 's/^n|//' | sort >"$OUT/contagem-producao.txt"
log "snapshot $snap; contagem em produção:"; sed 's/^/  /' "$OUT/contagem-producao.txt" >&2
if awk -F'|' '$2 == 0 {z=1} END {exit !z}' "$OUT/contagem-producao.txt"; then
  log "ERRO: tabela-chave com ZERO linhas em produção — banco errado, vazio, ou papel que não vê tudo."
  exit 1
fi

# ---------- 3. a cópia, no mesmo snapshot ----------
# shellcheck disable=SC2086  # SCHEMAS são várias palavras de propósito
pg_dump "$BACKUP_DB_URL" --snapshot="$snap" -Fc $SCHEMAS --no-owner -f "$OUT/banco.dump"
# Os papéis (sem senha) entram na cópia: sem eles, as policies `TO authenticated` e os GRANTs não
# se restauram. `--no-role-passwords` porque o papel do Supabase não lê pg_authid.
psql "$BACKUP_DB_URL" -X -qAt -v ON_ERROR_STOP=1 \
  -c "select e.extname || '|' || n.nspname from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname <> 'plpgsql' order by 1" \
  >"$OUT/extensoes.txt"
pg_dumpall -d "$BACKUP_DB_URL" --roles-only --no-role-passwords -f "$OUT/papeis.sql"
echo "commit;" >&3; exec 3>&-; wait $pid_sessao || { log "ERRO ao fechar a sessão:"; cat "$saida" >&2; exit 1; }
trap - EXIT; rm -f "$fifo"
rm -f "$saida"
log "dump: $(du -h "$OUT/banco.dump" | cut -f1)"
exit 0
fi

[ "$MODO" = conferir ] || { log "modo desconhecido: $MODO"; exit 2; }

# ---------- 4. restaurar e contar ----------
R() { psql -X -qAt -v ON_ERROR_STOP=1 "$@"; }
R -d postgres -c "drop database if exists $RESTAURO_DB" -c "create database $RESTAURO_DB"
# Cada papel citado na cópia, criado sem login (o atributo e a senha não importam para restaurar).
for papel in $(sed -nE 's/^CREATE ROLE "?([^";]+)"?;$/\1/p' "$OUT/papeis.sql"); do
  R -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = '$papel') then create role \"$papel\" nologin; end if; end \$\$"
done
# O pgcrypto mora no schema `extensions` no Supabase; o `hmac(` do envio usa-o.
# As extensões, na versão de produção. `pg_dump -n` NÃO leva `create extension` — medido no
# primeiro teste local: a cópia restaurou, as contagens bateram, e a sonda morreu em
# "function unaccent(text) does not exist". Uma extensão que não existe fora do Supabase
# (pg_graphql, supabase_vault…) é só listada: se ela fizer falta, a sonda acusa no passo 5.
while IFS='|' read -r ext nsp; do
  [ -n "$ext" ] || continue
  if ! R -d "$RESTAURO_DB" -c "create schema if not exists \"$nsp\"" \
         -c "create extension if not exists \"$ext\" schema \"$nsp\"" 2>/dev/null; then
    log "aviso: extensão $ext ($nsp) não existe fora do Supabase — não recriada"
  fi
done <"$OUT/extensoes.txt"

# O banco recém-criado já traz o `public` (onde as extensões acabaram de entrar) e o dump o recria:
# "schema public already exists", medido no primeiro teste local. A entrada sai do índice.
pg_restore -l "$OUT/banco.dump" | grep -vE '^[0-9]+; [0-9]+ [0-9]+ SCHEMA - public ' >"$OUT/.indice"

# Sem --exit-on-error para LISTAR todos os erros de uma vez; mas qualquer erro reprova.
if ! pg_restore -L "$OUT/.indice" -d "$RESTAURO_DB" "$OUT/banco.dump" 2>"$OUT/restauro.log"; then
  log "ERRO: a restauração teve erro ($(grep -c '^pg_restore: error' "$OUT/restauro.log" || true) erros). Os primeiros:"
  grep -m 30 'error' "$OUT/restauro.log" >&2 || cat "$OUT/restauro.log" >&2
  exit 1
fi

for t in $TABELAS; do
  echo "$t|$(R -d "$RESTAURO_DB" -c "set row_security = off; select count(*) from public.$t" | tail -1)"
done | sort >"$OUT/contagem-restaurada.txt"
if ! diff -u "$OUT/contagem-producao.txt" "$OUT/contagem-restaurada.txt" >&2; then
  log "ERRO: a cópia restaurada NÃO tem as mesmas linhas que produção tinha no mesmo instante."
  exit 1
fi
log "contagens batem nas 5 tabelas-chave"

# ---------- 5. a sonda, nos dois lados ----------
sonda="select chave from fn_instalacao_conferir() where not presente order by 1"
psql "$BACKUP_DB_URL" -X -qAt -v ON_ERROR_STOP=1 -c "set default_transaction_read_only = on" -c "$sonda" \
  | sed '/^SET$/d' >"$OUT/sonda-producao.txt"
R -d "$RESTAURO_DB" -c "$sonda" >"$OUT/sonda-restaurada.txt"
# O que falta na cópia e NÃO falta em produção é o que a cópia perdeu. Uma única exceção, nomeada:
# o segredo do Vault, que fica fora da cópia de propósito (cabeçalho). Medido no teste local de
# 24/11/2026: com o segredo presente na origem, este passo acusou exatamente `envio_segredo_no_vault`
# — a prova de que a comparação não é cega. Em produção ele já falta (ESTADO.md), então lá não muda.
FORA_DE_PROPOSITO="envio_segredo_no_vault"
perdido="$(comm -13 "$OUT/sonda-producao.txt" "$OUT/sonda-restaurada.txt" | grep -vxF "$FORA_DE_PROPOSITO" || true)"
if comm -13 "$OUT/sonda-producao.txt" "$OUT/sonda-restaurada.txt" | grep -qxF "$FORA_DE_PROPOSITO"; then
  log "esperado: $FORA_DE_PROPOSITO falta na cópia (o Vault não é copiado; recadastrar após restaurar)"
fi
log "sonda: produção sem $(wc -l <"$OUT/sonda-producao.txt") item(ns); cópia sem $(wc -l <"$OUT/sonda-restaurada.txt")"
if [ -n "$perdido" ]; then
  log "ERRO: a cópia restaurada não tem o que produção tem, segundo a sonda:"; echo "$perdido" >&2
  exit 1
fi
log "OK: cópia restaurada do zero, contagens iguais, sonda sem perda"
