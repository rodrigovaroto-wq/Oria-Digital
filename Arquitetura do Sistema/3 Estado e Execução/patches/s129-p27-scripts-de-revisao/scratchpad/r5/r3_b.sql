begin;
update documento set entidade_id = (select id from entidade where razao_social='VERTENTES METALÚRGICA LTDA.') where id = (select documento_id from documento_versao where nome_original='r3a.pdf');
select pg_sleep(5);
commit;
