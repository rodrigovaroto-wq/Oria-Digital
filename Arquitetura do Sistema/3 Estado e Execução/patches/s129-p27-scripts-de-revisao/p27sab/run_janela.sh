#!/bin/bash
# uso: run_janela.sh <migration.sql> <db>
P="psql -h /tmp -p 5432 -U postgres"
rm -f /tmp/p27sab/janela_ok
$P -d postgres -c "drop database if exists $2" -c "create database $2 template tdf_rev4w" >/dev/null 2>&1
( $P -d $2 -v ON_ERROR_STOP=1 -f $1 > /tmp/p27sab/A_$2.log 2>&1 ) &
for i in $(seq 1 120); do [ -f /tmp/p27sab/janela_ok ] && break; sleep 1; done
echo "janela aberta apos ${i}s"
$P -d $2 -f /tmp/p27sab/b.sql 2>&1 | tail -4
wait
grep -E "ERROR|deadlock|recálculo final" /tmp/p27sab/A_$2.log | head -3
$P -d $2 -f /tmp/p27sab/c.sql 2>&1 | cat
