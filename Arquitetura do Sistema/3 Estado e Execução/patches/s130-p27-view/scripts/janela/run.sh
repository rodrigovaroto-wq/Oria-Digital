#!/bin/bash
# a JANELA DA APLICACAO: o n8n comita uma extracao enquanto a migration segura o lock do create trigger
P0="sudo -u postgres psql -X -h /tmp -p 5432"
cd /home/user/Oria-Digital
sudo -u postgres env PGHOST=/tmp PGPORT=5432 PGUSER=postgres /tmp/p27/build_db.sh tdf_p27j sem243 2>&1 | tail -1
# uma extracao ANTES da migration (o que ja estava gravado)
$P0 -d tdf_p27j -v ON_ERROR_STOP=1 -q <<'SQL'
select fn_upsert_caso('janela antes')::uuid as caso \gset
select fn_upsert_entidade(:'caso'::uuid, 'ANTES LTDA')\gset
select fn_upsert_periodo(:'caso'::uuid, 'anual', '2025')\gset
select (fn_registrar_documento(:'caso'::uuid, 'ANTES LTDA', 'anual', '2025', 'DRE', 0.97, 'nome_arquivo', 'supabase_storage', 'ja/a.pdf', 'jaa.pdf', true, 'jahash', 'ok')->>'documento_versao_id')::uuid as v \gset
select fn_registrar_campos_extraidos(:'v'::uuid, '[{"chave":"Receita de vendas","valor_num":"100","secao":"RECEITA","periodo_coluna":"2025","confianca":"0.97"}]'::jsonb) \g /dev/null
SQL
rm -f /tmp/p27/janela/janela_ok
( cd /home/user/Oria-Digital; T0=$(date +%s.%N); sudo -u postgres psql -X -h /tmp -p 5432 -d tdf_p27j -v ON_ERROR_STOP=1 -f /tmp/p27/janela/mig_sleep.sql > /tmp/p27/janela/M.log 2>&1; T1=$(date +%s.%N); echo "FIM" >> /tmp/p27/janela/M.log; echo "migration (com 8 s de pausa de teste): $(echo "$T1 - $T0" | bc) s" > /tmp/p27/janela/M.time ) &
until [ -f /tmp/p27/janela/janela_ok ]; do sleep 0.2; done
echo "janela aberta: a migration segura o lock; o n8n extrai agora"
$P0 -d tdf_p27j -v ON_ERROR_STOP=1 -f /tmp/p27/janela/x.sql 2>&1 | grep -E "Time|x_inicio|x_fim|^ 20|ERROR"
wait
grep -E "ERROR|FIM" /tmp/p27/janela/M.log; cat /tmp/p27/janela/M.time
$P0 -d tdf_p27j -Atc "select 'fatos do DRE da janela: ' || count(*) from fato_financeiro f join documento_versao dv on dv.id=f.documento_versao_id where dv.nome_original='ja.pdf'" \
  -c "select 'pendencias conta incerta da janela: ' || count(*) from pendencia where tipo='conta_canonica_incerta' and motivo like 'fato:conta_incerta:%' and caso_id=(select id from caso where nome='janela')" \
  -c "select 'fatos do DRE de ANTES da migration: ' || count(*) from fato_financeiro f join documento_versao dv on dv.id=f.documento_versao_id where dv.nome_original='jaa.pdf'" \
  -c "select 'pendencias do DRE de ANTES: ' || count(*) from pendencia where caso_id=(select id from caso where nome='janela antes')"
