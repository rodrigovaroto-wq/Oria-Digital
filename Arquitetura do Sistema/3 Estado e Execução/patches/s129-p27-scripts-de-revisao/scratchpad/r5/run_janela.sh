#!/bin/bash
P0="sudo -u postgres psql -h /tmp -p 5432"
$P0 -qc "drop database if exists tdf_r5_j" -c "create database tdf_r5_j template tdf_r5_base"
rm -f /tmp/p27r5/janela_ok
( $P0 -d tdf_r5_j -v ON_ERROR_STOP=1 -f /tmp/p27r5/m_sleep.sql > /tmp/p27r5/A.log 2>&1; echo FIM >> /tmp/p27r5/A.log ) &
until [ -f /tmp/p27r5/janela_ok ]; do sleep 0.2; done
$P0 -d tdf_r5_j -v ON_ERROR_STOP=1 -f /tmp/p27r5/b.sql 2>&1 | grep -E "dre|velhos|ERROR|janela" 
wait
grep -E "NOTICE:  0243|ERROR|FIM" /tmp/p27r5/A.log
$P0 -d tdf_r5_j -Atc "select 'DRE janela fatos=' || count(*) from fato_financeiro f join documento_versao dv on dv.id=f.documento_versao_id where dv.nome_original='janela.pdf'" -c "select 'velhos=' || count(*) from fato_financeiro f join documento_versao dv on dv.id=f.documento_versao_id join documento d on d.id=dv.documento_id where f.entidade_origem='documento' and f.entidade_id is distinct from d.entidade_id"
