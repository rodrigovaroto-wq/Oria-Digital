-- Testes de `caso_apresentacao_campo` (Supabase/migrations/0201).
-- Travam: valor vazio/em branco é recusado (regra 1), chave fora do formato é recusada,
-- a PK (caso, chave) não duplica, o authenticated lê e escreve, e apagar o caso leva os campos.
\set ON_ERROR_STOP on

create or replace function teste_assert_ac(p_ok boolean, p_nome text)
returns void language plpgsql as $$
begin
  if p_ok then raise notice 'ok    %', p_nome;
  else raise exception 'FALHOU: %', p_nome; end if;
end $$;

do $$
declare
  v_caso uuid;
  v_n int;
begin
  insert into caso (nome) values ('teste apresentacao campo') returning id into v_caso;

  insert into caso_apresentacao_campo (caso_id, chave, valor, fonte)
  values (v_caso, 'xiv.ajuste.nao_recorrentes', 'R$ 1,2 mi', 'analista');
  perform teste_assert_ac(true, 'valor e chave válidos entram');

  begin
    insert into caso_apresentacao_campo (caso_id, chave, valor) values (v_caso, 'i.kpi.vazio', '');
    perform teste_assert_ac(false, 'valor vazio é recusado');
  exception when check_violation then perform teste_assert_ac(true, 'valor vazio é recusado'); end;

  begin
    insert into caso_apresentacao_campo (caso_id, chave, valor) values (v_caso, 'i.kpi.branco', E'  \t ');
    perform teste_assert_ac(false, 'valor só com espaço é recusado');
  exception when check_violation then perform teste_assert_ac(true, 'valor só com espaço é recusado'); end;

  begin
    insert into caso_apresentacao_campo (caso_id, chave, valor) values (v_caso, 'SemPonto', 'x');
    perform teste_assert_ac(false, 'chave sem capítulo.campo é recusada');
  exception when check_violation then perform teste_assert_ac(true, 'chave sem capítulo.campo é recusada'); end;

  begin
    insert into caso_apresentacao_campo (caso_id, chave, valor) values (v_caso, 'I.KPI.Maiuscula', 'x');
    perform teste_assert_ac(false, 'chave em maiúscula é recusada');
  exception when check_violation then perform teste_assert_ac(true, 'chave em maiúscula é recusada'); end;

  begin
    insert into caso_apresentacao_campo (caso_id, chave, valor) values (v_caso, 'xiv.ajuste.nao_recorrentes', 'outro');
    perform teste_assert_ac(false, 'mesma chave no mesmo caso é recusada');
  exception when unique_violation then perform teste_assert_ac(true, 'mesma chave no mesmo caso é recusada'); end;

  set local role authenticated;
  select count(*) into v_n from caso_apresentacao_campo where caso_id = v_caso;
  perform teste_assert_ac(v_n = 1, 'authenticated lê');
  insert into caso_apresentacao_campo (caso_id, chave, valor) values (v_caso, 'i.kpi.tamanho_setor', 'R$ 40 bi');
  update caso_apresentacao_campo set valor = 'R$ 41 bi' where caso_id = v_caso and chave = 'i.kpi.tamanho_setor';
  perform teste_assert_ac(
    (select valor from caso_apresentacao_campo where caso_id = v_caso and chave = 'i.kpi.tamanho_setor') = 'R$ 41 bi',
    'authenticated escreve e atualiza');
  reset role;

  delete from caso where id = v_caso;
  select count(*) into v_n from caso_apresentacao_campo where caso_id = v_caso;
  perform teste_assert_ac(v_n = 0, 'apagar o caso leva os campos (cascade)');
end $$;

drop function teste_assert_ac(boolean, text);
