-- Testes da 0270: a linha extraída passa a levar `ln`, o número da linha do texto numerado do documento de onde ela veio.
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO PROVA (comportamento, não mecanismo):
--   (A) `ln` válido (número JSON inteiro >= 1) é gravado como veio, inclusive nas pontas (1 e 999999999).
--   (B) `ln` nulo grava nulo. Zero, negativo, fracionário, texto (inclusive "12"), booleano e número que estoura int viram NULO: o valor inválido não aborta o lote (todas as linhas do
--       lote são gravadas) e não é corrigido para um palpite.
--   (C) campo SEM a chave `ln` (o n8n anterior à P11) grava exatamente como antes: mesma contagem, mesmos valores, `ln` nulo. A assinatura de 6 argumentos não muda (chamada de 3 argumentos funciona).
--   (D) o banco recusa `ln` <= 0 por conta própria (check), aceita nulo e aceita 1; linha inserida sem `ln` fica com `ln` nulo.
--   (E) a sonda enxerga os requisitos da 0270.
--
-- HONESTIDADE (regra 4): não há dado de produção com `ln` (a coluna nasce com esta migration), então o arranjo é inteiro à mão: documento de fn_registrar_documento e linhas de
-- fn_registrar_campos_extraidos DE VERDADE, com os valores de `ln` escolhidos para exercitar cada ramo. O teste afirma o comportamento da gravação, não que o n8n manda o `ln` certo (isso é da P11 no N8N).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número reprovado por sabotagem está no cabeçalho de Supabase/migrations/0270_a_linha_que_nao_sabia_de_que_linha_veio.sql ("MEDIÇÃO NÃO-VAZIA").
-- `p270.medindo = on` (PGOPTIONS='-c p270.medindo=on') vira `raise warning` e CONTA.

\set ON_ERROR_STOP on

-- REAPLICA a 0270 (idempotente) antes de tudo: o_balanco_sem_dado_financeiro.test.sql reaplica a 0231 duas vezes e deixa no banco o corpo ANTIGO de fn_registrar_campos_extraidos (sem `ln`).
-- Medido: sem esta linha o primeiro assert (ln 5 grava 5) lê nulo, e o schema.sql regerado ao fim do run.sh levaria o corpo da 0231 em vez do vigente.
\i Supabase/migrations/0270_a_linha_que_nao_sabia_de_que_linha_veio.sql

create or replace function teste_assert_p270(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('p270.execucoes', (coalesce(nullif(current_setting('p270.execucoes', true), ''), '0')::int + 1)::text, false);
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  elsif current_setting('p270.medindo', true) = 'on' then
    perform set_config('p270.falhas', (coalesce(nullif(current_setting('p270.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

delete from caso where nome like 'Caso P270 %';

do $$
declare
  v_caso uuid; v_r jsonb; v_ver uuid; v_n int; v_ln int; v_ok boolean; v_estado text;
  v_campos jsonb;
begin
  v_caso := (fn_upsert_caso('Caso P270 A'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'MOTO P270 LTDA', 'anual', '2024', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage', 'p270/a.pdf', 'a.pdf', true, 'P270-A', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;

  -- Um lote com todos os ramos de `ln`. A ordem é a do array; `ordem` identifica a linha.
  v_campos := jsonb_build_array(
    jsonb_build_object('ordem', 1,  'chave', 'LN valido',        'valor_num', 100, 'ln', 5),
    jsonb_build_object('ordem', 2,  'chave', 'LN um',            'valor_num', 101, 'ln', 1),
    jsonb_build_object('ordem', 3,  'chave', 'LN maximo',        'valor_num', 102, 'ln', 999999999),
    jsonb_build_object('ordem', 4,  'chave', 'LN nulo',          'valor_num', 103, 'ln', null),
    jsonb_build_object('ordem', 5,  'chave', 'LN zero',          'valor_num', 104, 'ln', 0),
    jsonb_build_object('ordem', 6,  'chave', 'LN negativo',      'valor_num', 105, 'ln', -3),
    jsonb_build_object('ordem', 7,  'chave', 'LN texto',         'valor_num', 106, 'ln', 'abc'),
    jsonb_build_object('ordem', 8,  'chave', 'LN texto numerico','valor_num', 107, 'ln', '12'),
    jsonb_build_object('ordem', 9,  'chave', 'LN fracionario',   'valor_num', 108, 'ln', 2.5),
    jsonb_build_object('ordem', 10, 'chave', 'LN estoura int',   'valor_num', 109, 'ln', 99999999999),
    jsonb_build_object('ordem', 11, 'chave', 'LN booleano',      'valor_num', 110, 'ln', true),
    jsonb_build_object('ordem', 12, 'chave', 'Sem a chave ln',   'valor_num', 111));

  raise notice '--- A/B/C. um lote com todos os ramos de ln grava TODAS as linhas ---';
  v_n := fn_registrar_campos_extraidos(v_ver, v_campos, 'N2');
  perform teste_assert_p270(v_n = 12, 'o lote inteiro é gravado (12 linhas): ln inválido não aborta', v_n::text);
  select count(*) into v_n from campo_extraido where documento_versao_id = v_ver;
  perform teste_assert_p270(v_n = 12, 'e há 12 linhas em campo_extraido', v_n::text);

  select ln into v_ln from campo_extraido where documento_versao_id = v_ver and chave = 'LN valido';
  perform teste_assert_p270(v_ln = 5, 'ln 5 grava 5', coalesce(v_ln::text, 'null'));
  select ln into v_ln from campo_extraido where documento_versao_id = v_ver and chave = 'LN um';
  perform teste_assert_p270(v_ln = 1, 'ln 1 (a ponta de baixo) grava 1', coalesce(v_ln::text, 'null'));
  select ln into v_ln from campo_extraido where documento_versao_id = v_ver and chave = 'LN maximo';
  perform teste_assert_p270(v_ln = 999999999, 'ln 999999999 (a ponta de cima que cabe) grava como veio', coalesce(v_ln::text, 'null'));

  select (ln is null) into v_ok from campo_extraido where documento_versao_id = v_ver and chave = 'LN nulo';
  perform teste_assert_p270(v_ok, 'ln nulo grava nulo (não medível, nunca zero)');
  select (ln is null) into v_ok from campo_extraido where documento_versao_id = v_ver and chave = 'LN zero';
  perform teste_assert_p270(v_ok, 'ln 0 vira nulo');
  select (ln is null) into v_ok from campo_extraido where documento_versao_id = v_ver and chave = 'LN negativo';
  perform teste_assert_p270(v_ok, 'ln -3 vira nulo');
  select (ln is null) into v_ok from campo_extraido where documento_versao_id = v_ver and chave = 'LN texto';
  perform teste_assert_p270(v_ok, 'ln "abc" vira nulo');
  select (ln is null) into v_ok from campo_extraido where documento_versao_id = v_ver and chave = 'LN texto numerico';
  perform teste_assert_p270(v_ok, 'ln "12" (texto, não número JSON) vira nulo: a coordenada não é adivinhada');
  select (ln is null) into v_ok from campo_extraido where documento_versao_id = v_ver and chave = 'LN fracionario';
  perform teste_assert_p270(v_ok, 'ln 2.5 vira nulo');
  select (ln is null) into v_ok from campo_extraido where documento_versao_id = v_ver and chave = 'LN estoura int';
  perform teste_assert_p270(v_ok, 'ln 99999999999 (estoura int) vira nulo em vez de abortar o lote');
  select (ln is null) into v_ok from campo_extraido where documento_versao_id = v_ver and chave = 'LN booleano';
  perform teste_assert_p270(v_ok, 'ln true vira nulo');

  select count(*) into v_n from campo_extraido where documento_versao_id = v_ver and ln is not null;
  perform teste_assert_p270(v_n = 3, 'só as 3 linhas com ln válido ficam com ln (nenhuma inválida vira número)', v_n::text);

  raise notice '--- C. campo sem a chave ln grava igual a antes ---';
  perform teste_assert_p270((select valor_num = 111 and ln is null and ordem = 12 and nivel_autonomia = 'N2' and status_aceite in ('pendente', 'aceito')
                               from campo_extraido where documento_versao_id = v_ver and chave = 'Sem a chave ln'),
    'linha sem a chave ln: valor, ordem e nível gravados como sempre, ln nulo');
  v_r := fn_registrar_documento(v_caso, 'MOTO P270 LTDA', 'anual', '2023', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage', 'p270/b.pdf', 'b.pdf', true, 'P270-B', 'ok');
  v_n := fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid,
    jsonb_build_array(jsonb_build_object('ordem', 1, 'chave', 'ATIVO', 'valor_num', 900, 'unidade', 'milhar', 'confianca', 0.97, 'secao_canonica', 'ativo_total')), 'N2');
  perform teste_assert_p270(v_n = 1 and (select ln is null and valor_num = 900 and unidade = 'milhar' and secao_canonica = 'ativo_total'
                                           from campo_extraido where documento_versao_id = (v_r->>'documento_versao_id')::uuid),
    'chamada de 3 argumentos de um n8n anterior (nenhum ln): grava igual, ln nulo', v_n::text);

  raise notice '--- D. o banco recusa ln <= 0 e aceita nulo e 1 ---';
  v_estado := 'nao recusou';
  begin
    insert into campo_extraido (documento_versao_id, chave, ln) values (v_ver, 'direto zero', 0);
  exception when check_violation then v_estado := 'recusou';
  end;
  perform teste_assert_p270(v_estado = 'recusou', 'insert direto com ln = 0 é recusado pelo check', v_estado);
  v_estado := 'nao recusou';
  begin
    insert into campo_extraido (documento_versao_id, chave, ln) values (v_ver, 'direto negativo', -1);
  exception when check_violation then v_estado := 'recusou';
  end;
  perform teste_assert_p270(v_estado = 'recusou', 'insert direto com ln = -1 é recusado pelo check', v_estado);
  insert into campo_extraido (documento_versao_id, chave, ln) values (v_ver, 'direto um', 1), (v_ver, 'direto nulo', null);
  insert into campo_extraido (documento_versao_id, chave) values (v_ver, 'direto sem ln');
  perform teste_assert_p270((select count(*) = 3 and count(ln) = 1 from campo_extraido where documento_versao_id = v_ver and chave like 'direto %' and chave not in ('direto zero', 'direto negativo')),
    'insert direto com ln = 1, nulo e sem a coluna é aceito, e só o 1 fica com valor');

  raise notice '--- E. a sonda enxerga os requisitos da 0270 ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0270' and presente;
  perform teste_assert_p270(v_n = 4, 'os 4 requisitos da 0270 estão presentes na sonda', v_n::text);
  select count(*) into v_n from instalacao_requisito where migration = '0270';
  perform teste_assert_p270(v_n = 4, 'e o catálogo declara exatamente 4', v_n::text);

  if current_setting('p270.medindo', true) = 'on' then
    raise warning 'MEDIDO: % falha(s) de % execucoes', coalesce(current_setting('p270.falhas', true), '0'), current_setting('p270.execucoes', true);
  end if;
  raise notice 'TODOS OS TESTES DA 0270 PASSARAM';
end $$;

delete from caso where nome like 'Caso P270 %';
