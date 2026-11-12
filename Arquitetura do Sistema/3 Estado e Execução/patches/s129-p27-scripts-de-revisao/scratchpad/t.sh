#!/bin/bash
# roda o teste 0270 e o da 0243 contra o banco tdf_p27 já montado
cd /home/user/Oria-Digital
for t in a_linha_que_nao_sabia_de_que_linha_veio fato_financeiro; do
  psql -v ON_ERROR_STOP=1 -h /tmp -p 5432 -U postgres -d tdf_p27 -f Supabase/test/$t.test.sql 2>&1 | grep -E '^(NOTICE|ERROR|psql|WARNING)' | sed -E 's/^NOTICE:  //'
done
