#!/usr/bin/env bash
# build_db.sh <db> <modo>   modo: normal (0001..0271 em ordem, com a 0243 nova no lugar), sem243 (tudo menos a 0243), prod (0001..0242,0270,0271,0243), fixtures (normal + fixtures)
set -euo pipefail
export TEST_DB="$1"; MODO="${2:-normal}"
DB="$1"
cd /home/user/Oria-Digital
RAIZ=/home/user/Oria-Digital
source /tmp/p27/prelude.sh
apl() { for f in "$@"; do if ! out=$(psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f" 2>&1); then echo "FALHOU $f"; echo "$out" | head -20; exit 1; fi; done; }
case "$MODO" in
  normal|fixtures) apl Supabase/migrations/*.sql ;;
  sem243) apl $(ls Supabase/migrations/*.sql | grep -v '/0243_') ;;
  prod) apl $(ls Supabase/migrations/*.sql | grep -v '/0243_' ) Supabase/migrations/0243_a_linha_que_nao_tinha_identidade.sql ;;
esac
source /tmp/p27/pos.sh
if [ "$MODO" = fixtures ]; then
  psql -q -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/fixture_book_vertentes.sql
  psql -q -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/fixture_book_canastra.sql
fi
echo "build_db $DB $MODO ok"
