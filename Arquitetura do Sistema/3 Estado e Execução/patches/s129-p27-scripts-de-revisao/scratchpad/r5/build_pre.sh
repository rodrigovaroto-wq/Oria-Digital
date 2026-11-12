#!/usr/bin/env bash
# uso: build.sh DB ordem   (ordem=prod: 0243 por último, depois das fixtures; zero: ordem alfabética, fixtures depois)
set -euo pipefail
DB=$1; ORD=$2
P="sudo -u postgres psql -h /tmp -p 5432"
cd /home/user/Oria-Digital
sed -e '/^set -euo/d' /tmp/claude-0/-home-user-Oria-Digital/2ec90589-c004-5ebb-8574-7d4fde161a1d/scratchpad/setup.sh > /tmp/claude-0/-home-user-Oria-Digital/2ec90589-c004-5ebb-8574-7d4fde161a1d/scratchpad/setup2.sh
export TEST_DB=$DB
psql() { sudo -u postgres psql -h /tmp -p 5432 "$@"; }
export -f psql
bash -c "source /tmp/claude-0/-home-user-Oria-Digital/2ec90589-c004-5ebb-8574-7d4fde161a1d/scratchpad/setup2.sh" >/dev/null
for f in Supabase/migrations/*.sql; do
  if [ "$ORD" = prod ] && [[ $f == *0243_* ]]; then continue; fi
  $P -q -v ON_ERROR_STOP=1 -d $DB < $f >/dev/null 2>&1 || { echo FALHOU $f; exit 1; }
done
$P -q -v ON_ERROR_STOP=1 -d $DB < Supabase/test/fixture_book_vertentes.sql >/dev/null 2>&1
$P -q -v ON_ERROR_STOP=1 -d $DB < Supabase/test/fixture_book_canastra.sql >/dev/null 2>&1
if [ "$ORD" = prod ] && false; then
  $P -v ON_ERROR_STOP=1 -d $DB < Supabase/migrations/0243_a_linha_que_nao_tinha_identidade.sql 2>&1 | grep -E 'NOTICE|ERROR' | head
fi
echo ok $DB
