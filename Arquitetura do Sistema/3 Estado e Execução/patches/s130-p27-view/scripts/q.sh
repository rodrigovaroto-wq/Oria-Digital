#!/usr/bin/env bash
# q.sh <db> <sql...>  — roda como postgres
db=$1; shift
sudo -u postgres psql -h /tmp -p 5432 -d "$db" -X "$@"
