begin;
\i /tmp/p27sab/helpers_new.sql
do $$
declare c uuid; v uuid; h uuid; a uuid; b uuid; i int;
begin
  c := fn_upsert_caso('exp')::uuid; h := fn_upsert_entidade(c, 'HOLDING P27 LTDA'); perform fn_upsert_entidade(c, 'SUB P27 LTDA'); perform fn_upsert_periodo(c, 'anual', '2025');
  v := pg_temp.doc(c, 'HOLDING P27 LTDA', '2025', 'BALANCETE', 'e1', jsonb_build_array(
    pg_temp.l('Caixa','100','ativo_circulante','AC','Saldo Anterior'), pg_temp.l('Caixa','500','ativo_circulante','AC','Débito'), pg_temp.l('Caixa','450','ativo_circulante','AC','Crédito'),
    pg_temp.l('Caixa','150','ativo_circulante','AC','Saldo Atual'), pg_temp.l('Caixa','50','ativo_circulante','AC','Variação'), pg_temp.l('Caixa','160','ativo_circulante','AC','Orçado')));
  raise notice '%', array_to_string(pg_temp.linhas(v), E'\n');
  v := pg_temp.doc(c, 'HOLDING P27 LTDA', '2025', 'COMBINADO', 'e2', jsonb_build_array(
    pg_temp.l('Caixa','25','ativo_circulante','AC','2025','Consolidado'), pg_temp.l('Caixa','30','ativo_circulante','AC','2025','Total Geral')));
  raise notice E'%', array_to_string(pg_temp.linhas(v), E'\n');
  v := pg_temp.doc(c, 'HOLDING P27 LTDA', '2025', 'COMBINADO', 'e3', jsonb_build_array(
    pg_temp.l('Caixa','10','ativo_circulante','AC','2025','HOLDING P27 LTDA'), pg_temp.l('Caixa','20','ativo_circulante','AC','2025','SUB P27 LTDA'), pg_temp.l('Caixa','-5','ativo_circulante','AC','2025','Eliminações'), pg_temp.l('Caixa','-5','ativo_circulante','AC','2025','Total Eliminações'), pg_temp.l('Caixa','25','ativo_circulante','AC','2025','Consolidado')));
  raise notice E'%', array_to_string(pg_temp.linhas(v), E'\n');
  v := pg_temp.doc(c, 'HOLDING P27 LTDA', '2025', 'BALANCETE', 'e4', jsonb_build_array(
    pg_temp.l('Caixa','100','ativo_circulante','AC','Saldo Final'), pg_temp.l('Caixa','150','ativo_circulante','AC','Saldo Atual')));
  raise notice E'%', array_to_string(pg_temp.linhas(v), E'\n');
  v := pg_temp.doc(c, 'HOLDING P27 LTDA', '2025', 'BALANCO', 'e5', jsonb_build_array(
    pg_temp.l('Caixa','100','ativo_circulante','AC','2025'), pg_temp.l('Caixa','101','ativo_circulante','AC','31/12/2025')));
  raise notice E'%', array_to_string(pg_temp.linhas(v), E'\n');
end $$;
rollback;
