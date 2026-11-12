-- Testes da 0274: o resumo do aging guardado POR MANDATO e conciliado com o balanço extraído (aging_importado, fn_aging_importar,
-- fn_aging_resumo_erros, fn_reconciliar_aging, fn_reconciliar_aging_do_caso, fn_balanco_fecha_em, fn_aging_linhas_do_balanco).
-- Rodar via Supabase/test/run.sh (que aplica as migrations e carrega as fixtures dos books antes).
--
-- O QUE ESTE ARQUIVO PROVA (comportamento, regra 3): a ESCRITA COMO `authenticated` com papel e com membro de OUTRO mandato (a lição
-- .claude/memory/rls-so-select-passa-no-superusuario.md); a conciliação POR RESULTADO (conferido com divergência 0, conferido dentro do
-- arredondamento, divergente com o valor, linha não localizada, sem par de data, documento ausente, escala desconhecida); o resumo
-- que não fecha consigo mesmo é recusado (um motivo por assert) e nem o service_role o grava (as CHECKs); reimportar substitui sem apagar.
--
-- DE ONDE VÊM OS BALANÇOS (regra 4: nada inventado para provar bug de produção; esta tabela nasce vazia, não há bug de produção aqui).
--   * REAL: o balanço do fixture do book difícil (fixture_book_canastra.sql, CANASTRA INDÚSTRIA, versão 55555555-3333-...-0001, colunas
--     2023/2024/2025, R$ mil), que traz o PAI "Contas a Receber" líquido de PDD e duplicatas descontadas, os filhos "Clientes - duplicatas a
--     receber - mercado interno" e "Duplicatas a receber de clientes - mercado externo", o pai "Fornecedores" com filhos e os dois Adiantamentos.
--     Os RESUMOS de aging desse caso são MONTADOS aqui a partir dos números do balanço (não há arquivo de aging real: DM7 pendente).
--   * MONTADOS aqui, no formato que `campo_extraido` tem (fn_registrar_documento + fn_registrar_campos_extraidos, como caixa_dfc_de_um_ano.test.sql):
--     os valores de AGING UM são os da Metalúrgica do book-distress (Dados de Teste/book-distress/dados.py, 2025: Clientes 24.917, PDD -4.386,
--     Adiantamentos de clientes 212, a fornecedores 212, Fornecedores nacionais 13.954 + estrangeiros 946 = 14.900, em R$ mil); os demais são
--     variações mínimas desse (sem a conta de adiantamentos, sem escala, escala em reais, balancete de junho, comparativo de dois exercícios).
--   Os RESUMOS de aging são montados por teste_resumo_0274 no formato de Leitor/lib/aging.mjs (12/11/2026, depois da revisão independente).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número reprovado por guarda desligada está no cabeçalho de
-- Supabase/migrations/0274_o_aging_que_so_existia_no_navegador_e_nunca_conferia_com_o_balanco.sql ("MEDIÇÃO NÃO-VAZIA").
-- `ct74.medindo = on` (PGOPTIONS='-c ct74.medindo=on') vira `raise warning` e CONTA (ct74.execucoes / ct74.falhas); sem a variável, o assert é
-- `raise exception` (o CI).

\set ON_ERROR_STOP on

create or replace function teste_assert_0274(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('ct74.execucoes', (coalesce(nullif(current_setting('ct74.execucoes', true), ''), '0')::int + 1)::text, false);
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  elsif current_setting('ct74.medindo', true) = 'on' then
    perform set_config('ct74.falhas', (coalesce(nullif(current_setting('ct74.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

create or replace function teste_json_0274(p_res text) returns jsonb
language sql immutable as $$ select case when p_res like 'ok|{%' or p_res like 'ok|[%' then substring(p_res from 4)::jsonb end $$;

-- Entra como `p_papel` (authenticated com o JWT do usuário; NULL = JWT SEM sub), executa a expressão, volta a superusuário com o JWT do Sócio
-- padrão do run.sh. Devolve 'ok|<resultado em texto>' ou '<sqlstate>|<mensagem>'. SQL dinâmico de propósito (ver 0273: o plano de uma
-- expressão simples não reconfere o EXECUTE depois de um `set role`).
create or replace function teste_exec_0274(p_uid uuid, p_papel text, p_expr text)
returns text language plpgsql as $$
declare v_r text; v_out text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '{"role":"authenticated"}'
                     else jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
  execute format('set local role %I', p_papel);
  begin
    execute 'select (' || p_expr || ')::text' into v_r;
    v_out := 'ok|' || coalesce(v_r, 'NULL');
  exception when others then
    v_out := sqlstate || '|' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  return v_out;
end $$;

-- O resumo de um aging coerente no formato de Leitor/lib/aging.mjs. S = saldo positivo e N = saldo negativo, em centavos.
create or replace function teste_resumo_0274(p_data date, p_pos bigint, p_neg bigint) returns jsonb
language plpgsql immutable as $$
declare
  v_venc bigint := p_pos / 5 * 2;
  v_m1   bigint := p_pos / 2;
begin
  return jsonb_build_object(
    'data_base', p_data::text,
    'titulos', 3 + case when p_neg < 0 then 1 else 0 end, 'liquidados', 0,
    'positivos', jsonb_build_object('titulos', 3, 'saldo', p_pos::text, 'vencido', v_venc::text, 'vencido_pct', 40,
      'por_faixa', jsonb_build_object('a_vencer', (p_pos - v_venc)::text, '1_30', v_venc::text, '31_60', '0', '61_90', '0', '91_180', '0', '181_360', '0', 'acima_360', '0')),
    'negativos', jsonb_build_object('titulos', case when p_neg < 0 then 1 else 0 end, 'saldo', p_neg::text, 'efeito', 'créditos e adiantamentos',
      'maiores', case when p_neg < 0 then jsonb_build_array(jsonb_build_object('contraparte', 'CLIENTE CREDOR', 'documento', null, 'saldo', p_neg::text, 'titulos', 1))
                      else '[]'::jsonb end,
      'demais', jsonb_build_object('contrapartes', 0, 'saldo', '0', 'titulos', 0)),
    'emitidos_depois_da_data_base', jsonb_build_object('titulos', 0, 'saldo_positivos', '0', 'saldo_negativos', '0'),
    'documentos_invalidos', jsonb_build_object('titulos', 0),
    'contrapartes_com_saldo', 2, 'concentracao_top10_pct', 100,
    'maiores', jsonb_build_array(jsonb_build_object('contraparte', 'ACME LTDA', 'documento', null, 'saldo', v_m1::text, 'vencido', v_venc::text, 'titulos', 2)),
    'demais', jsonb_build_object('contrapartes', 1, 'saldo', (p_pos - v_m1)::text, 'vencido', '0', 'titulos', 1));
end $$;

-- Importa COMO o papel, com leitura, aplicador, arquivo e mapeamento coerentes (cada um pode ser trocado para provar a recusa).
create or replace function teste_imp_0274(p_uid uuid, p_caso uuid, p_ent uuid, p_tipo text, p_data date, p_resumo jsonb,
  p_papel text default 'authenticated', p_leitura jsonb default null, p_arquivo jsonb default null, p_map uuid default null, p_aplicador jsonb default null) returns text
language sql as $$
  select teste_exec_0274(p_uid, p_papel, format('fn_aging_importar(%L::uuid, %L::uuid, %L, %L::date, %L::jsonb, %L::jsonb, %L::jsonb, %L::jsonb, %L::uuid)',
    p_caso, p_ent, p_tipo, p_data, p_resumo,
    coalesce(p_leitura, jsonb_build_object('formato', 'csv', 'sha256', repeat('a', 64), 'bytes', 2048, 'linhas', jsonb_build_object('corpo', 3))),
    coalesce(p_aplicador, jsonb_build_object('titulo', 3, 'motivos', '{}'::jsonb, 'conferencia_com_o_total_do_arquivo', jsonb_build_object('estado', 'confere'))),
    coalesce(p_arquivo, jsonb_build_object('nome', 'ar.csv', 'sha256', repeat('a', 64), 'bytes', 2048, 'formato', 'csv')),
    coalesce(p_map, current_setting('ct74.map_' || case p_tipo when 'contas_a_pagar' then 'ap' else 'ar' end)::uuid))) $$;

-- A linha de campo_extraido no formato de produção; o balanço de teste.
create or replace function teste_ln_0274(p_ordem int, p_chave text, p_valor numeric, p_unid text default 'milhar', p_col text default null,
  p_ent_col text default null, p_secao text default null) returns jsonb
language sql immutable as $$
  select jsonb_strip_nulls(jsonb_build_object('ordem', p_ordem, 'chave', p_chave, 'valor_num', p_valor::text, 'unidade', p_unid, 'periodo_coluna', p_col,
                                              'entidade_coluna', p_ent_col, 'secao', p_secao, 'confianca', '0.97')) $$;

create or replace function teste_bal_0274(p_caso uuid, p_razao text, p_idx int, p_linhas jsonb, p_ptipo text default 'anual', p_pref text default '2025',
  p_tipo text default 'BALANCO') returns uuid
language plpgsql as $$
declare v_r jsonb;
begin
  v_r := fn_registrar_documento(p_caso, p_razao, p_ptipo, p_pref, p_tipo, 0.97, 'nome_arquivo', 'supabase_storage', '0274/' || p_idx || '.pdf',
                                'BP' || p_idx || '.pdf', true, 'HASH-0274-' || p_idx, 'ok');
  perform fn_registrar_campos_extraidos((v_r ->> 'documento_versao_id')::uuid, p_linhas, 'N2');
  return (select entidade_id from documento where id = (v_r ->> 'documento_id')::uuid);
end $$;

-- A linha de reconciliacao de UMA checagem do resultado de fn_aging_importar.
create or replace function teste_rec_0274(p_imp jsonb, p_tipo text) returns reconciliacao
language sql stable as $$
  select r.* from reconciliacao r
   where r.id = (select (e ->> 'reconciliacao_id')::uuid from jsonb_array_elements(case when jsonb_typeof(p_imp -> 'conciliacao') = 'array' then p_imp -> 'conciliacao' else '[]'::jsonb end) e where e ->> 'tipo' = p_tipo) $$;

create or replace function teste_pend_0274(p_caso uuid, p_ent uuid, p_tipo text) returns int
language sql stable as $$
  select count(*)::int from pendencia where caso_id = p_caso and entidade_id = p_ent and motivo = 'reconciliacao:' || p_tipo and estado <> 'resolvida' $$;

-- Insere direto na tabela (service_role/superusuário: sem passar pela função) e devolve 'ok' ou o SQLSTATE; a linha de sucesso é desfeita pelo chamador.
create or replace function teste_ins_0274(p_caso uuid, p_ent uuid, p_resumo jsonb, p_sha text default null, p_leitura jsonb default null,
  p_data date default '2031-01-01', p_tipo text default 'contas_a_receber', p_sub_em timestamptz default null, p_sub_por uuid default null,
  p_bytes bigint default 2048, p_formato text default 'csv') returns text
language plpgsql as $$
begin
  insert into aging_importado (caso_id, entidade_id, tipo_base, data_base, resumo, leitura, aplicador, arquivo_nome, arquivo_sha256, arquivo_bytes,
                               arquivo_formato, mapeamento_id, importado_por, substituido_em, substituido_por)
  values (p_caso, p_ent, p_tipo, p_data, p_resumo, coalesce(p_leitura, '{}'::jsonb), '{}'::jsonb, 'direto.csv', coalesce(p_sha, repeat('b', 64)), p_bytes, p_formato,
          current_setting('ct74.map_ar')::uuid, '00000000-0000-0000-0000-00000000a001', p_sub_em, p_sub_por);
  return 'ok';
exception when others then
  return sqlstate;
end $$;

-- Quantas linhas o usuário VÊ na tabela (a leitura direta, pela policy) e na trilha do mandato.
create or replace function teste_ve_0274(p_uid uuid, p_caso uuid) returns int
language plpgsql as $$
declare v_n int;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute format('select count(*) from aging_importado where caso_id = %L', p_caso) into v_n;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  return v_n;
end $$;

create or replace function teste_ve_evento_0274(p_uid uuid, p_caso uuid) returns int
language plpgsql as $$
declare v_n int;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute format('select count(*) from evento_auditoria where entidade_ref = %L and acao = ''aging_importado''', 'caso:' || p_caso) into v_n;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  return v_n;
end $$;

-- Executa um comando COMO o papel e devolve o SQLSTATE ('ok' se passou).
create or replace function teste_sql_0274(p_uid uuid, p_papel text, p_sql text) returns text
language plpgsql as $$
declare v_out text;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', p_papel)::text, true);
  execute format('set local role %I', p_papel);
  begin
    execute p_sql;
    v_out := 'ok';
  exception when others then
    v_out := sqlstate;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  return v_out;
end $$;

-- Limpeza de rodada anterior (o teste é reexecutável).
delete from aging_importado;
delete from evento_auditoria where acao = 'aging_importado' or acao like 'reconciliacao\_aging\_%';
delete from reconciliacao where tipo like 'aging\_a%';
delete from pendencia where motivo like 'reconciliacao:aging\_a%';
delete from caso where nome like '0274 —%';
delete from auth.users where id in ('00000000-0000-0000-0000-00000274b001', '00000000-0000-0000-0000-00000274b002',
  '00000000-0000-0000-0000-00000274b003', '00000000-0000-0000-0000-00000274b004', '00000000-0000-0000-0000-00000274b005');

do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000274b001';
  u_ana   uuid := '00000000-0000-0000-0000-00000274b002';   -- Analista alocada em A
  u_leo   uuid := '00000000-0000-0000-0000-00000274b003';   -- Leitura alocado em A
  u_nil   uuid := '00000000-0000-0000-0000-00000274b004';   -- SEM papel
  u_xan   uuid := '00000000-0000-0000-0000-00000274b005';   -- Analista alocado só em B
  v_a uuid; v_b uuid;
  c_ar constant text := 'contas_a_receber';
  c_ap constant text := 'contas_a_pagar';
  c_can constant uuid := '11111111-3333-3333-3333-111111111111';   -- o caso do fixture Canastra
  c_ind constant uuid := '22222222-3333-0000-0000-000000000002';   -- Canastra Indústria
  v_ef text := repeat('a', 64);
  e1 uuid; e2 uuid; e3 uuid; e4 uuid; e5 uuid; e6 uuid; e7 uuid; e8 uuid; e9 uuid; e10 uuid; e11 uuid; e12 uuid; e13 uuid; e14 uuid; e15 uuid; e16 uuid; e18 uuid; e19 uuid; e20 uuid; e21 uuid; e22 uuid; e23 uuid; eb uuid;
  v_map_ar uuid; v_map_ap uuid; v_cab jsonb := '["Cliente0274","Vencimento","Saldo"]'; v_mapa jsonb := '{"contraparte":0,"vencimento":1,"saldo":2}';
  v_fmt jsonb := '{"decimal":"virgula","datas":"dia_mes_ano"}';
  v_res text; v_res2 text; v_r jsonb; v_r2 jsonb; v_base jsonb; v_b31 jsonb; v_n int; v_n2 int; v_id uuid; v_id2 uuid; rr reconciliacao; rr2 reconciliacao; f record; v_t text;
begin
  insert into auth.users (id, email) values (u_socio, 'socio@0274.local'), (u_ana, 'ana@0274.local'), (u_leo, 'leo@0274.local'),
    (u_nil, 'nil@0274.local'), (u_xan, 'xan@0274.local');
  perform fn_definir_papel(u_socio, 'socio', 'teste 0274');
  perform fn_definir_papel(u_ana, 'analista');
  perform fn_definir_papel(u_leo, 'leitura');
  perform fn_definir_papel(u_xan, 'analista');
  v_a := fn_upsert_caso('0274 — mandato A');
  v_b := fn_upsert_caso('0274 — mandato B');
  perform fn_alocar(v_a, u_ana);
  perform fn_alocar(v_a, u_leo);
  perform fn_alocar(v_b, u_xan);
  -- Os mapeamentos confirmados (0272), pelo Sócio padrão do run.sh: um por tipo_base.
  v_map_ar := (fn_mapeamento_confirmar(c_ar, v_cab, v_mapa, v_fmt) ->> 'id')::uuid;
  v_map_ap := (fn_mapeamento_confirmar(c_ap, v_cab, v_mapa, v_fmt) ->> 'id')::uuid;
  perform set_config('ct74.map_ar', v_map_ar::text, false);
  perform set_config('ct74.map_ap', v_map_ap::text, false);

  -- Os balanços de teste (todos no mandato A, montados no formato de campo_extraido).
  -- AGING UM: o balanço 2025 da Metalúrgica do book-distress (R$ mil), sem coluna de período (um exercício só).
  e1 := teste_bal_0274(v_a, 'Alfa Comercial Ltda', 1, jsonb_build_array(
    teste_ln_0274(0, 'Clientes - duplicatas a receber', 24917), teste_ln_0274(1, '(-) Perdas estimadas em créditos de liquidação duvidosa de clientes', -4386),
    teste_ln_0274(2, 'Adiantamentos a fornecedores', 212), teste_ln_0274(3, 'Adiantamentos de clientes', 212),
    teste_ln_0274(4, 'Fornecedores nacionais', 13954), teste_ln_0274(5, 'Fornecedores estrangeiros', 946)));
  e2 := teste_bal_0274(v_a, 'Bravo Metais Ltda', 2, jsonb_build_array(teste_ln_0274(0, 'Clientes - duplicatas a receber', 24917)));   -- sem a conta de adiantamentos
  e3 := teste_bal_0274(v_a, 'Charlie Plasticos Ltda', 3, jsonb_build_array(teste_ln_0274(0, 'Clientes - duplicatas a receber', 24917)));   -- idem
  e4 := teste_bal_0274(v_a, 'Delta Moveis Ltda', 4, jsonb_build_array(teste_ln_0274(0, 'Clientes - duplicatas a receber', 24917, null)));   -- sem escala
  e5 := teste_bal_0274(v_a, 'Echo Quimica Ltda', 5, jsonb_build_array(teste_ln_0274(0, 'Clientes - duplicatas a receber', 24917)));   -- só dezembro
  insert into entidade (caso_id, razao_social) values (v_a, 'Foxtrot Graos Ltda') returning id into e6;                                   -- sem balanço nenhum
  e8 := teste_bal_0274(v_a, 'Golf Textil Ltda', 8, jsonb_build_array(teste_ln_0274(0, 'Clientes - duplicatas a receber', 24917000, 'unidade')));
  e9 := teste_bal_0274(v_a, 'Hotel Papel Ltda', 9, jsonb_build_array(teste_ln_0274(0, 'Clientes - duplicatas a receber', 20000)), 'mes', '06/2025', 'BALANCETE');
  e10 := teste_bal_0274(v_a, 'India Energia Ltda', 10, jsonb_build_array(
    teste_ln_0274(0, 'Clientes - duplicatas a receber', 21902, 'milhar', '31/12/2024'), teste_ln_0274(1, 'Clientes - duplicatas a receber', 24917, 'milhar', '31/12/2025')),
    'multi', '24,25');
  e11 := teste_bal_0274(v_a, 'Juliet Vidros Ltda', 11, jsonb_build_array(teste_ln_0274(0, 'Clientes - duplicatas a receber', 23000, 'milhar', '30/06/2025')), 'data-base', '2025-06-30');
  e12 := teste_bal_0274(v_a, 'Kilo Racoes Ltda', 12, jsonb_build_array(teste_ln_0274(0, 'Clientes - duplicatas a receber', 24917)), 'multi', '24,25');   -- vários exercícios, sem coluna
  e13 := teste_bal_0274(v_a, 'Lima Embalagens Ltda', 13, jsonb_build_array(teste_ln_0274(0, 'Clientes - duplicatas a receber', 19000)), 'trimestre', '1T25');
  -- Entidade que NÃO tem coluna num balanço de várias empresas; e a que tem, ao lado de outra empresa com outro número.
  e14 := teste_bal_0274(v_a, 'Mike Logistica Ltda', 14, jsonb_build_array(teste_ln_0274(0, 'Clientes - duplicatas a receber', 24917, 'milhar', null, 'OUTRA EMPRESA S.A.')));
  e15 := teste_bal_0274(v_a, 'November Tintas Ltda', 15, jsonb_build_array(
    teste_ln_0274(0, 'Clientes - duplicatas a receber', 99999, 'milhar', null, 'OUTRA EMPRESA S.A.'),
    teste_ln_0274(1, 'Clientes - duplicatas a receber', 24917, 'milhar', null, 'November Tintas Ltda')));
  -- Pai "Clientes" LÍQUIDO (tem a provisão como filha) com o filho bruto: a conciliação quer o bruto (24.917), não o pai (20.000).
  e16 := teste_bal_0274(v_a, 'Oscar Cimentos Ltda', 16, jsonb_build_array(
    teste_ln_0274(0, 'Clientes', 20000, 'milhar', null, null, 'Contas a Receber'),
    teste_ln_0274(1, 'Clientes nacionais', 24917, 'milhar', null, null, 'Clientes'),
    teste_ln_0274(2, '(-) Provisão para devedores duvidosos', -4917, 'milhar', null, null, 'Clientes')));
  -- Balancete de mês cuja referência não diz o dia (parcial, sem data de fechamento): com e sem coluna de período.
  e18 := teste_bal_0274(v_a, 'Papa Calcados Ltda', 18, jsonb_build_array(teste_ln_0274(0, 'Clientes - duplicatas a receber', 24917, 'milhar', '06/2025')), 'mes', 'junho-2025', 'BALANCETE');
  e19 := teste_bal_0274(v_a, 'Quebec Bebidas Ltda', 19, jsonb_build_array(teste_ln_0274(0, 'Clientes - duplicatas a receber', 24917)), 'mes', 'junho-2025', 'BALANCETE');
  -- Dois balanços fechando em 31/12/2025: o BALANCETE (criado por último, 24.917) e o BALANCO (20.000): vale o BALANCO.
  e20 := teste_bal_0274(v_a, 'Romeo Fertilizantes Ltda', 21, jsonb_build_array(teste_ln_0274(0, 'Clientes - duplicatas a receber', 20000)));
  perform teste_bal_0274(v_a, 'Romeo Fertilizantes Ltda', 22, jsonb_build_array(teste_ln_0274(0, 'Clientes - duplicatas a receber', 24917)), 'mes', '12/2025', 'BALANCETE');
  update documento set criado_em = now() + interval '1 minute' where entidade_id = e20 and tipo_taxonomia = 'BALANCETE';   -- numa transação todos têm o mesmo now(): sem isto o desempate por criado_em seria sorte
  -- AGING SETE: só um DRE por ora; o balanço chega depois (seção 8).
  e7 := teste_bal_0274(v_a, 'Sierra Cafe Ltda', 7, jsonb_build_array(teste_ln_0274(0, 'Receita operacional líquida', 1000)), 'anual', '2025', 'DRE');
  e21 := teste_bal_0274(v_a, 'Uniform Aco Ltda', 23, jsonb_build_array(teste_ln_0274(0, 'Clientes - duplicatas a receber', 23000)), 'data-base', '2025-06-30');
  e22 := teste_bal_0274(v_a, 'Victor Tecidos Ltda', 24, jsonb_build_array(teste_ln_0274(0, 'Clientes - duplicatas a receber', 23000)), 'mes', '6M25', 'BALANCETE');
  e23 := teste_bal_0274(v_a, 'Whiskey Couros Ltda', 25, jsonb_build_array(teste_ln_0274(0, 'Clientes - duplicatas a receber', 23000)), 'anual', 'FY');
  -- Uma entidade do mandato B.
  eb := teste_bal_0274(v_b, 'Tango Pecas Ltda', 20, jsonb_build_array(teste_ln_0274(0, 'Clientes - duplicatas a receber', 100)));

  -- ------------------------------------------------------------------ 1. EM QUE DATA O BALANÇO FECHA
  raise notice '--- 1. fn_balanco_fecha_em: a data de fechamento que a conciliação compara ---';
  select * into f from fn_balanco_fecha_em((select id from documento where caso_id = v_a and entidade_id = e1), 2025);
  perform teste_assert_0274(f.fecha_em = date '2025-12-31' and f.observacao is null, 'balanço anual de um exercício, sem coluna: fecha em 31/12 do ano', f.fecha_em::text);
  select * into f from fn_balanco_fecha_em((select id from documento where caso_id = v_a and entidade_id = e1), 2024);
  perform teste_assert_0274(f.fecha_em is null and f.observacao like '%não traz o exercício 2024%', 'o mesmo balanço perguntado por 2024: NULL, dizendo que não traz o exercício', f.observacao);
  select * into f from fn_balanco_fecha_em((select id from documento where caso_id = v_a and entidade_id = e9), 2025);
  perform teste_assert_0274(f.fecha_em = date '2025-06-30', 'balancete do mês 06/2025: fecha em 30/06/2025 (fim do mês)', f.fecha_em::text);
  select * into f from fn_balanco_fecha_em((select id from documento where caso_id = v_a and entidade_id = e13), 2025);
  perform teste_assert_0274(f.fecha_em = date '2025-03-31', 'balanço do trimestre 1T25: fecha em 31/03/2025 (fim do trimestre)', f.fecha_em::text);
  select * into f from fn_balanco_fecha_em((select id from documento where caso_id = v_a and entidade_id = e10), 2024);
  perform teste_assert_0274(f.fecha_em = date '2024-12-31' and f.coluna = '31/12/2024', 'comparativo de dois exercícios, coluna "31/12/2024": fecha em 31/12/2024', f.fecha_em::text);
  select * into f from fn_balanco_fecha_em((select id from documento where caso_id = v_a and entidade_id = e10), 2025);
  perform teste_assert_0274(f.fecha_em = date '2025-12-31' and f.coluna = '31/12/2025', 'e coluna "31/12/2025" fecha em 31/12/2025', f.fecha_em::text);
  select * into f from fn_balanco_fecha_em((select id from documento where caso_id = v_a and entidade_id = e11), 2025);
  perform teste_assert_0274(f.fecha_em = date '2025-06-30', 'coluna com data "30/06/2025": fecha na data da coluna, não em 31/12', f.fecha_em::text);
  select * into f from fn_balanco_fecha_em((select id from documento where caso_id = v_a and entidade_id = e12), 2025);
  perform teste_assert_0274(f.fecha_em is null and f.observacao like '%cobre vários exercícios%', 'documento de dois exercícios SEM coluna de período: NULL, sem palpite de qual ano é', f.observacao);

  select * into f from fn_balanco_fecha_em((select id from documento where caso_id = v_a and entidade_id = e21), 2025);
  perform teste_assert_0274(f.fecha_em = date '2025-06-30', 'período "data-base 2025-06-30" sem coluna: fecha na data do período', f.fecha_em::text);
  select * into f from fn_balanco_fecha_em((select id from documento where caso_id = v_a and entidade_id = e22), 2025);
  perform teste_assert_0274(f.fecha_em = date '2025-06-30', 'período "6M25" (seis meses até junho): fecha em 30/06/2025', f.fecha_em::text);
  select * into f from fn_balanco_fecha_em((select id from documento where caso_id = v_a and entidade_id = e23), 2025);
  perform teste_assert_0274(f.fecha_em is null and f.observacao like '%não ancora ano nenhum%', 'período sem ano ("FY"): NULL, dizendo que não ancora ano nenhum', f.observacao);
  select * into f from fn_balanco_fecha_em((select id from documento where caso_id = v_a and entidade_id = e10), 2023);
  perform teste_assert_0274(f.fecha_em is null and f.observacao like '%nenhuma é de 2023%', 'comparativo 2024/2025 perguntado por 2023: NULL, dizendo que nenhuma coluna é de 2023', f.observacao);

  -- ------------------------------------------------------------------ 2. A CONCILIAÇÃO: O QUE CONFERE
  raise notice '--- 2. a carteira que fecha com o balanço em R$ mil: conferido, 0 ---';
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, -21200000));
  perform teste_assert_0274(v_res like 'ok|%', 'a Analista do mandato A importa o aging de contas a receber', v_res);
  v_r := teste_json_0274(v_res); v_id := (v_r ->> 'id')::uuid;
  perform teste_assert_0274(case when jsonb_typeof(v_r -> 'conciliacao') = 'array' then jsonb_array_length(v_r -> 'conciliacao') end = 2 and v_r -> 'substitui' = 'null'::jsonb,
    'a importação devolve o id, a substituída (nula) e as DUAS checagens (carteira e adiantamentos)', v_res);
  perform teste_assert_0274((select importado_por from aging_importado where id = v_id) = u_ana, 'o autor gravado na linha é o auth.uid() da Analista que importou', null);
  rr := teste_rec_0274(v_r, 'aging_ar_clientes');
  perform teste_assert_0274(rr.resultado = 'ok' and rr.divergencia_abs = 0 and rr.precondicoes_ok,
    'R$ 24.917.000,00 de aging × 24.917 R$ mil de Clientes: conferido, com divergência 0 GRAVADA (não ausência)', rr.resultado || ' / ' || coalesce(rr.divergencia_abs::text, 'NULL'));
  perform teste_assert_0274(rr.descricao like '%Conferido, diferença de R$ 0,00%' and rr.descricao like '%24.917.000,00%' and rr.descricao like '%Clientes - duplicatas a receber%',
    'a descrição diz os dois valores, a conta usada e "Conferido, diferença de R$ 0,00"', rr.descricao);
  perform teste_assert_0274(rr.classe = 'A' and rr.documento_id is not null and (rr.fonte_a ->> 'centavos') = '2491700000' and (rr.fonte_b -> 'chaves') is not null,
    'a linha é de classe A, com o documento do balanço, os centavos do aging na fonte A e as contas usadas na fonte B', rr.fonte_a::text);
  perform teste_assert_0274(rr.descricao not like '%PDD%' and (rr.fonte_b ->> 'valor')::numeric = 24917000,
    'o valor do balanço é o BRUTO, 24.917.000 (a PDD de -4.386 é linha própria e fica de fora)', rr.fonte_b::text);
  perform teste_assert_0274(teste_pend_0274(v_a, e1, 'aging_ar_clientes') = 0, 'e nenhuma pendência fica aberta', null);
  rr := teste_rec_0274(v_r, 'aging_ar_adiantamentos');
  perform teste_assert_0274(rr.resultado = 'ok' and rr.divergencia_abs = 0 and (rr.fonte_a ->> 'valor')::numeric = 212000 and (rr.fonte_b ->> 'valor')::numeric = 212000000 / 1000,
    'os NEGATIVOS (R$ -212.000,00) conciliam com Adiantamentos de clientes (212 R$ mil), em valor absoluto: conferido, 0', rr.fonte_a::text || ' | ' || rr.fonte_b::text);
  perform teste_assert_0274(rr.descricao like '%Adiantamentos de clientes%' and rr.descricao like '%Conferido%', 'e a descrição nomeia a conta de Adiantamentos', rr.descricao);

  raise notice '--- 3. reimportar substitui sem apagar; a diferença plantada abre pendência com o valor ---';
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491760000, -21200000));
  perform teste_assert_0274(v_res like 'ok|%', 'importar de novo a mesma (entidade, tipo_base, data-base) é aceito', v_res);
  v_r2 := teste_json_0274(v_res); v_id2 := (v_r2 ->> 'id')::uuid;
  perform teste_assert_0274((v_r2 ->> 'substitui')::uuid = v_id, 'a resposta diz QUAL importação foi substituída', v_res);
  perform teste_assert_0274((select count(*) from aging_importado where caso_id = v_a and entidade_id = e1 and tipo_base = c_ar and data_base = '2025-12-31') = 2
                            and (select count(*) from aging_importado where caso_id = v_a and entidade_id = e1 and tipo_base = c_ar and data_base = '2025-12-31' and substituido_em is null) = 1,
    'a antiga NÃO é apagada (2 linhas) e só uma fica vigente', null);
  perform teste_assert_0274((select substituido_por from aging_importado where id = v_id) = v_id2 and (select substituido_em from aging_importado where id = v_id) is not null
                            and (select substituido_em from aging_importado where id = v_id2) is null,
    'a substituída aponta para a nova (substituido_por) e tem data; a nova está vigente', null);
  rr := teste_rec_0274(v_r2, 'aging_ar_clientes');
  perform teste_assert_0274(rr.resultado = 'divergente' and rr.divergencia_abs = 600, 'R$ 600,00 a mais (acima da meia unidade, R$ 500): divergente, com a diferença de R$ 600', rr.resultado || ' / ' || coalesce(rr.divergencia_abs::text, 'NULL'));
  perform teste_assert_0274(rr.descricao like '%Diferença de R$ 600,00, acima de R$ 500,00%', 'a descrição traz a diferença (R$ 600,00) e a tolerância (R$ 500,00)', rr.descricao);
  perform teste_assert_0274(teste_pend_0274(v_a, e1, 'aging_ar_clientes') = 1 and (select descricao from pendencia where caso_id = v_a and entidade_id = e1 and motivo = 'reconciliacao:aging_ar_clientes' and estado <> 'resolvida') like '%R$ 600,00%',
    'a divergência ABRE a pendência, e o texto dela traz o valor', null);
  perform teste_assert_0274(fn_reconciliar_aging(v_id) ->> 'executado' = 'false', 'a conciliação da importação SUBSTITUÍDA não roda (só a vigente se concilia)', fn_reconciliar_aging(v_id)::text);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, -21200000));
  perform teste_assert_0274(teste_pend_0274(v_a, e1, 'aging_ar_clientes') = 0, 'reimportar o aging corrigido FECHA a pendência (o sintoma sumiu)', v_res);

  raise notice '--- 4. a tolerância é o arredondamento da escala (meia unidade), não um percentual ---';
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491740000, -21200000));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_clientes');
  perform teste_assert_0274(rr.resultado = 'ok' and rr.divergencia_abs = 400, 'R$ 400,00 a mais (dentro de R$ 500): conferido, com a diferença REAL (400) gravada', rr.resultado || ' / ' || coalesce(rr.divergencia_abs::text, 'NULL'));
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491750000, -21200000));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_clientes');
  perform teste_assert_0274(rr.resultado = 'ok' and rr.divergencia_abs = 500, 'R$ 500,00 exatos (a meia unidade): ainda conferido', rr.resultado || ' / ' || coalesce(rr.divergencia_abs::text, 'NULL'));
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491750001, -21200000));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_clientes');
  perform teste_assert_0274(rr.resultado = 'divergente' and rr.divergencia_abs = 500.01, 'R$ 500,01: um centavo acima da meia unidade já é divergente', rr.resultado || ' / ' || coalesce(rr.divergencia_abs::text, 'NULL'));
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, -21200000));   -- volta ao conferido
  -- escala em reais: a meia unidade é R$ 0,50
  v_res := teste_imp_0274(u_ana, v_a, e8, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, 0));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_clientes');
  perform teste_assert_0274(rr.resultado = 'ok' and rr.divergencia_abs = 0, 'balanço em REAIS (24.917.000 unidade) × aging de R$ 24.917.000,00: conferido', rr.resultado);
  v_res := teste_imp_0274(u_ana, v_a, e8, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491710000, 0));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_clientes');
  perform teste_assert_0274(rr.resultado = 'divergente' and rr.divergencia_abs = 100, 'balanço em reais: R$ 100,00 de diferença é divergente (a tolerância acompanha a escala: R$ 0,50, não R$ 500)', rr.resultado || ' / ' || coalesce(rr.divergencia_abs::text, 'NULL'));
  v_res := teste_imp_0274(u_ana, v_a, e4, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, 0));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_clientes');
  perform teste_assert_0274(rr.resultado = 'precondicao_nao_satisfeita' and rr.motivo_precondicao = 'unidade_divergente' and rr.divergencia_abs is null,
    'balanço SEM escala reconhecida: unidade_divergente, sem comparar (um falso "confere" é pior que a pendência)', rr.resultado || ' / ' || coalesce(rr.motivo_precondicao, 'NULL'));
  perform teste_assert_0274(teste_pend_0274(v_a, e4, 'aging_ar_clientes') = 1, 'e a pendência abre', null);

  raise notice '--- 5. negativos: sem a conta de adiantamentos, e zero sem a conta ---';
  v_res := teste_imp_0274(u_ana, v_a, e2, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, -15000000));
  v_r := teste_json_0274(v_res);
  rr := teste_rec_0274(v_r, 'aging_ar_adiantamentos');
  perform teste_assert_0274(rr.resultado = 'precondicao_nao_satisfeita' and rr.motivo_precondicao = 'linha_nao_localizada' and rr.divergencia_abs = 150000,
    'negativos de R$ 150.000,00 SEM a conta de Adiantamentos de clientes: linha_nao_localizada, com a diferença de R$ 150.000', rr.resultado || ' / ' || coalesce(rr.motivo_precondicao, 'NULL') || ' / ' || coalesce(rr.divergencia_abs::text, 'NULL'));
  perform teste_assert_0274(rr.descricao like '%R$ 150.000,00%' and rr.descricao like '%não traz a conta Adiantamentos de clientes%', 'a descrição diz o valor e que o balanço não traz a conta', rr.descricao);
  perform teste_assert_0274(teste_pend_0274(v_a, e2, 'aging_ar_adiantamentos') = 1, 'e a pendência abre (a diferença aparece como pendência com o valor)', null);
  perform teste_assert_0274((teste_rec_0274(v_r, 'aging_ar_clientes')).resultado = 'ok', 'a carteira (positivos) da mesma importação segue conferindo: as duas checagens são independentes', null);
  v_res := teste_imp_0274(u_ana, v_a, e3, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, 0));
  v_r := teste_json_0274(v_res);
  rr := teste_rec_0274(v_r, 'aging_ar_adiantamentos');
  perform teste_assert_0274(rr.resultado = 'ok' and rr.divergencia_abs = 0 and rr.descricao like '%nada a conciliar%', 'negativos ZERO e sem a conta: nada a conciliar, dito na descrição, divergência 0', rr.resultado || ' | ' || rr.descricao);
  perform teste_assert_0274(teste_pend_0274(v_a, e3, 'aging_ar_adiantamentos') = 0, 'e nenhuma pendência', null);
  v_res := teste_imp_0274(u_ana, v_a, e3, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, 0));
  -- negativos zero, mas o balanço TEM a conta: o aging não traz o que o balanço diz ter
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, 0));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_adiantamentos');
  perform teste_assert_0274(rr.resultado = 'divergente' and rr.divergencia_abs = 212000, 'negativos zero mas o balanço TEM Adiantamentos de clientes (212 R$ mil): divergente de R$ 212.000', rr.resultado || ' / ' || coalesce(rr.divergencia_abs::text, 'NULL'));
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, -21200000));

  raise notice '--- 6. outra data, sem balanço, balancete e coluna certa ---';
  v_res := teste_imp_0274(u_ana, v_a, e5, c_ar, '2025-06-30', teste_resumo_0274('2025-06-30', 2491700000, 0));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_clientes');
  perform teste_assert_0274(rr.resultado = 'precondicao_nao_satisfeita' and rr.motivo_precondicao = 'sem_periodo_par' and rr.fonte_b is null and rr.divergencia_abs is null,
    'carteira de 30/06/2025 × balanço de dezembro: sem_periodo_par, SEM comparar (nenhum número do balanço entra)', rr.resultado || ' / ' || coalesce(rr.motivo_precondicao, 'NULL'));
  perform teste_assert_0274(rr.descricao like '%fecha em 31/12/2025, não em 30/06/2025%', 'a descrição diz de que data é o balanço e de que data é a carteira', rr.descricao);
  perform teste_assert_0274(teste_pend_0274(v_a, e5, 'aging_ar_clientes') = 1, 'sem_periodo_par ABRE pendência (contrato da 0186: documento presente, sem par)', null);
  v_res := teste_imp_0274(u_ana, v_a, e5, c_ar, '2024-12-31', teste_resumo_0274('2024-12-31', 2491700000, 0));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_clientes');
  perform teste_assert_0274(rr.motivo_precondicao = 'sem_periodo_par' and rr.descricao like '%não traz o exercício 2024%', 'carteira de dezembro de 2024 × balanço só de 2025: sem_periodo_par, dizendo que não traz 2024', rr.descricao);
  v_res := teste_imp_0274(u_ana, v_a, e6, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, -21200000));
  v_r := teste_json_0274(v_res);
  rr := teste_rec_0274(v_r, 'aging_ar_clientes');
  perform teste_assert_0274(rr.resultado = 'precondicao_nao_satisfeita' and rr.motivo_precondicao = 'documento_ausente' and rr.documento_id is null and rr.descricao like '%balanço desta entidade não foi entregue%',
    'entidade SEM balanço no mandato: documento_ausente, descrito', rr.resultado || ' / ' || coalesce(rr.motivo_precondicao, 'NULL'));
  perform teste_assert_0274(teste_pend_0274(v_a, e6, 'aging_ar_clientes') = 0 and teste_pend_0274(v_a, e6, 'aging_ar_adiantamentos') = 0,
    'documento_ausente NÃO abre pendência (é cobrança do checklist do Kit Básico)', null);
  perform teste_assert_0274((teste_rec_0274(v_r, 'aging_ar_adiantamentos')).motivo_precondicao = 'documento_ausente', 'e a checagem dos adiantamentos também é registrada (não some): documento_ausente', null);
  v_res := teste_imp_0274(u_ana, v_a, e9, c_ar, '2025-06-30', teste_resumo_0274('2025-06-30', 2000000000, 0));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_clientes');
  perform teste_assert_0274(rr.resultado = 'ok' and rr.divergencia_abs = 0, 'carteira de 30/06/2025 × BALANCETE de 06/2025 (R$ 20.000 mil): CONFERE, porque as datas são as mesmas', rr.resultado || ' / ' || coalesce(rr.descricao, ''));
  v_res := teste_imp_0274(u_ana, v_a, e10, c_ar, '2024-12-31', teste_resumo_0274('2024-12-31', 2190200000, 0));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_clientes');
  perform teste_assert_0274(rr.resultado = 'ok' and rr.divergencia_abs = 0, 'comparativo de dois exercícios: a carteira de 2024 lê a coluna 31/12/2024 (21.902), não a de 2025', rr.resultado || ' / ' || coalesce(rr.descricao, ''));
  v_res := teste_imp_0274(u_ana, v_a, e10, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, 0));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_clientes');
  perform teste_assert_0274(rr.resultado = 'ok' and rr.divergencia_abs = 0, 'e a de 2025 lê a coluna 31/12/2025 (24.917)', rr.resultado || ' / ' || coalesce(rr.descricao, ''));
  v_res := teste_imp_0274(u_ana, v_a, e12, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, 0));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_clientes');
  perform teste_assert_0274(rr.resultado = 'precondicao_nao_satisfeita' and rr.motivo_precondicao = 'sem_periodo_par', 'balanço de dois exercícios SEM coluna de período: sem_periodo_par, não palpite de qual exercício', rr.resultado || ' / ' || coalesce(rr.motivo_precondicao, 'NULL'));

  v_res := teste_imp_0274(u_ana, v_a, e14, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, 0));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_clientes');
  perform teste_assert_0274(rr.resultado = 'precondicao_nao_satisfeita' and rr.motivo_precondicao = 'precondicao_nao_satisfeita' and rr.descricao like '%não tem coluna desta entidade%' and rr.divergencia_abs is null,
    'balanço de VÁRIAS empresas sem coluna desta entidade: não compara (sem coluna é sem par, não "usa a única coluna")', rr.resultado || ' / ' || rr.descricao);
  perform teste_assert_0274(teste_pend_0274(v_a, e14, 'aging_ar_clientes') = 1, 'e a pendência abre', null);
  v_res := teste_imp_0274(u_ana, v_a, e15, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, 0));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_clientes');
  perform teste_assert_0274(rr.resultado = 'ok' and rr.divergencia_abs = 0, 'balanço de duas empresas: a carteira lê a coluna da SUA entidade (24.917), não a da outra (99.999)', rr.resultado || ' / ' || coalesce(rr.descricao, ''));
  v_res := teste_imp_0274(u_ana, v_a, e16, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, 0));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_clientes');
  perform teste_assert_0274(rr.resultado = 'ok' and (rr.fonte_b ->> 'valor')::numeric = 24917000, 'pai "Clientes" LÍQUIDO (a provisão é filha dele): o valor é o do filho bruto (24.917), não o do pai (20.000)', rr.resultado || ' | ' || rr.fonte_b::text);
  v_res := teste_imp_0274(u_ana, v_a, e18, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, 0));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_clientes');
  perform teste_assert_0274(rr.motivo_precondicao = 'sem_periodo_par' and rr.descricao like '%período parcial e não diz a data de fechamento%',
    'balancete com COLUNA de mês ("06/2025") sem dia: parcial, sem data de fechamento: sem_periodo_par, não palpite de 31/12', rr.descricao);
  v_res := teste_imp_0274(u_ana, v_a, e19, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, 0));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_clientes');
  perform teste_assert_0274(rr.motivo_precondicao = 'sem_periodo_par' and rr.descricao like '%é parcial e não diz a data de fechamento%',
    'balancete de período "junho-2025" (parcial) sem coluna: sem_periodo_par, não palpite de 31/12', rr.descricao);
  v_res := teste_imp_0274(u_ana, v_a, e20, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, 0));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_clientes');
  perform teste_assert_0274(rr.resultado = 'divergente' and (rr.fonte_b ->> 'valor')::numeric = 20000000, 'dois balanços fecham na data: vale o BALANCO (20.000) antes do BALANCETE criado depois (24.917)', rr.resultado || ' | ' || rr.fonte_b::text);
  perform teste_assert_0274(coalesce(current_setting('oria.periodo_chave', true), '') = '', 'a conciliação devolve o `oria.periodo_chave` como encontrou (não vaza o período do balanço para a checagem seguinte)', current_setting('oria.periodo_chave', true));
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491760000, -21200000), 'authenticated', null, null, null,
    jsonb_build_object('titulo', 3, 'motivos', jsonb_build_object('total_por_data', jsonb_build_object('linhas', 3, 'saldo', '1500000')),
                       'conferencia_com_o_total_do_arquivo', jsonb_build_object('estado', 'diverge')));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ar_clientes');
  perform teste_assert_0274(rr.resultado = 'divergente' and rr.descricao like '%deixou fora do aging 3 linhas rejeitadas, com saldo de R$ 15.000,00%',
    'a divergência diz o que o aplicador deixou FORA do aging (3 linhas, R$ 15.000,00): pode explicar a diferença', rr.descricao);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, -21200000));

  raise notice '--- 7. contas a pagar: Fornecedores e Adiantamentos a fornecedores ---';
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ap, '2025-12-31', teste_resumo_0274('2025-12-31', 1490000000, -21200000));
  v_r := teste_json_0274(v_res);
  rr := teste_rec_0274(v_r, 'aging_ap_fornecedores');
  perform teste_assert_0274(rr.resultado = 'ok' and rr.divergencia_abs = 0 and (rr.fonte_b ->> 'valor')::numeric = 14900000,
    'contas a pagar de R$ 14.900.000,00 × Fornecedores (nacionais 13.954 + estrangeiros 946 = 14.900 R$ mil, DUAS linhas somadas): conferido, 0', rr.resultado || ' | ' || rr.fonte_b::text);
  perform teste_assert_0274(rr.descricao like '%Fornecedores%' and rr.descricao like '%Fornecedores nacionais%' and rr.descricao like '%Fornecedores estrangeiros%', 'a descrição nomeia as duas contas somadas', rr.descricao);
  rr := teste_rec_0274(v_r, 'aging_ap_adiantamentos');
  perform teste_assert_0274(rr.resultado = 'ok' and rr.divergencia_abs = 0 and rr.descricao like '%Adiantamentos a fornecedores%',
    'os negativos do AP conciliam com Adiantamentos A fornecedores (ativo), não com os de clientes', rr.resultado || ' | ' || rr.descricao);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ap, '2025-12-31', teste_resumo_0274('2025-12-31', 1490150000, -21200000));
  rr := teste_rec_0274(teste_json_0274(v_res), 'aging_ap_fornecedores');
  perform teste_assert_0274(rr.resultado = 'divergente' and rr.divergencia_abs = 1500 and teste_pend_0274(v_a, e1, 'aging_ap_fornecedores') = 1,
    'AP com R$ 1.500,00 a mais (a tolerância de DUAS linhas em R$ mil é R$ 1.000, a soma das meias unidades): divergente e a pendência abre', rr.resultado || ' / ' || coalesce(rr.divergencia_abs::text, 'NULL'));
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ap, '2025-12-31', teste_resumo_0274('2025-12-31', 1490100000, -21200000));
  rr2 := teste_rec_0274(teste_json_0274(v_res), 'aging_ap_fornecedores');
  perform teste_assert_0274(rr2.resultado = 'ok' and rr2.divergencia_abs = 1000 and teste_pend_0274(v_a, e1, 'aging_ap_fornecedores') = 0,
    'AP com R$ 1.000,00 a mais, EXATOS a soma das meias unidades das duas linhas: conferido, e a pendência anterior fecha', rr2.resultado || ' / ' || coalesce(rr2.divergencia_abs::text, 'NULL'));
  perform teste_assert_0274(teste_pend_0274(v_a, e1, 'aging_ar_clientes') = 0 and rr.tipo = 'aging_ap_fornecedores' and teste_pend_0274(v_a, e1, 'aging_ap_adiantamentos') = 0,
    'a divergência do AP não toca a pendência do AR da mesma entidade nem a dos adiantamentos (tipos separados por tipo_base)', null);

  raise notice '--- 8. o balanço que chega DEPOIS reconcilia a carteira que já estava ---';
  v_res := teste_imp_0274(u_ana, v_a, e7, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2491700000, 0));
  v_r := teste_json_0274(v_res);
  perform teste_assert_0274((teste_rec_0274(v_r, 'aging_ar_clientes')).motivo_precondicao = 'documento_ausente' and teste_pend_0274(v_a, e7, 'aging_ar_clientes') = 0,
    'a carteira importada antes do balanço fica documento_ausente, sem pendência', v_res);
  perform teste_assert_0274(teste_bal_0274(v_a, 'Sierra Cafe Ltda', 17, jsonb_build_array(teste_ln_0274(0, 'Clientes - duplicatas a receber', 20000))) = e7,
    'o balanço chega depois e é da MESMA entidade', null);
  v_res := teste_exec_0274(u_ana, 'authenticated', format('fn_reconciliar_aging_do_caso(%L::uuid)', v_a));
  perform teste_assert_0274(v_res like 'ok|[%' and teste_json_0274(v_res) @> '[{"tipo":"aging_ar_clientes"}]'::jsonb, 'a Analista chama fn_reconciliar_aging_do_caso e recebe as checagens', left(v_res, 200));
  select r.* into rr from reconciliacao r where r.caso_id = v_a and r.entidade_id = e7 and r.tipo = 'aging_ar_clientes' order by r.criado_em desc, r.cmin::text::int desc limit 1;
  perform teste_assert_0274(rr.resultado = 'divergente' and rr.divergencia_abs = 4917000 and teste_pend_0274(v_a, e7, 'aging_ar_clientes') = 1,
    'a rodada do mandato acha o balanço novo (20.000 R$ mil) e ABRE a pendência da carteira (24.917.000): diferença de R$ 4.917.000', rr.resultado || ' / ' || coalesce(rr.divergencia_abs::text, 'NULL'));

  perform teste_assert_0274(jsonb_array_length(teste_json_0274(v_res)) = 2 * (select count(*) from aging_importado where caso_id = v_a and substituido_em is null),
    'a rodada do mandato devolve DUAS checagens por importação vigente (as substituídas não entram)', jsonb_array_length(teste_json_0274(v_res))::text);
  perform set_config('request.jwt.claims', '', true);
  begin
    perform fn_reconciliar_aging_do_caso(v_a);
    v_res2 := 'ok';
  exception when others then v_res2 := sqlstate; end;
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  perform teste_assert_0274(v_res2 = 'ok', 'a conexão de serviço (o n8n) chama a rodada do mandato', v_res2);
  begin
    perform fn_aging_linhas_do_balanco('55555555-3333-0000-0000-000000000001', 'xyz', null, '2025');
    v_res2 := 'ok';
  exception when others then v_res2 := sqlstate; end;
  perform teste_assert_0274(v_res2 = '22023', 'conceito que não existe: 22023 (não devolve zero linhas como se o balanço não tivesse a conta)', v_res2);

  -- ------------------------------------------------------------------ 9. O BALANÇO REAL DO FIXTURE (Canastra Indústria)
  raise notice '--- 9. fixture real do book difícil: pai líquido, filhos somados, pai com filhos, coluna do exercício ---';
  select string_agg(chave || '=' || valor_num::bigint, '; ' order by chave) into v_t from fn_aging_linhas_do_balanco('55555555-3333-0000-0000-000000000001', 'clientes', null, '2025');
  perform teste_assert_0274(v_t = 'Clientes - duplicatas a receber - mercado interno=24861; Duplicatas a receber de clientes - mercado externo=3845',
    'Clientes (Canastra, 2025): os DOIS filhos bruto (interno 24.861 + externo 3.845); o pai líquido "Contas a Receber" (12.795), a PDD e as duplicatas descontadas ficam de fora', v_t);
  select string_agg(chave || '=' || valor_num::bigint, '; ' order by chave) into v_t from fn_aging_linhas_do_balanco('55555555-3333-0000-0000-000000000001', 'fornecedores', null, '2025');
  perform teste_assert_0274(v_t = 'Fornecedores=28634', 'Fornecedores (Canastra, 2025): o PAI (28.634) vale sozinho; os filhos (17.945 + 1.901 + 5.888 + 2.900) não somam de novo', v_t);
  select string_agg(chave || '=' || valor_num::bigint, '; ' order by chave) into v_t from fn_aging_linhas_do_balanco('55555555-3333-0000-0000-000000000001', 'adiantamentos_de_clientes', null, '2025');
  perform teste_assert_0274(v_t = 'Adiantamentos de clientes=862', 'Adiantamentos de clientes (2025): 862', v_t);
  select string_agg(chave || '=' || valor_num::bigint, '; ' order by chave) into v_t from fn_aging_linhas_do_balanco('55555555-3333-0000-0000-000000000001', 'adiantamentos_a_fornecedores', null, '2025');
  perform teste_assert_0274(v_t = 'Adiantamentos a fornecedores=1113', 'Adiantamentos a fornecedores (2025): 1.113 (os "a empregados" de 694 NÃO entram)', v_t);
  select string_agg(chave || '=' || valor_num::bigint, '; ' order by chave) into v_t from fn_aging_linhas_do_balanco('55555555-3333-0000-0000-000000000001', 'clientes', null, '2024');
  perform teste_assert_0274(v_t = 'Duplicatas a receber de clientes - mercado externo=5080; Duplicatas a receber de clientes - mercado interno=31328', 'a coluna do exercício decide: Clientes de 2024 = 31.328 + 5.080', v_t);
  v_res := teste_imp_0274(u_socio, c_can, c_ind, c_ar, '2025-12-31', teste_resumo_0274('2025-12-31', 2870600000, -86200000));
  v_r := teste_json_0274(v_res);
  perform teste_assert_0274(v_res like 'ok|%' and (teste_rec_0274(v_r, 'aging_ar_clientes')).resultado = 'ok' and (teste_rec_0274(v_r, 'aging_ar_clientes')).divergencia_abs = 0
                            and (teste_rec_0274(v_r, 'aging_ar_adiantamentos')).resultado = 'ok' and (teste_rec_0274(v_r, 'aging_ar_adiantamentos')).divergencia_abs = 0,
    'Canastra Indústria, AR de 31/12/2025 (R$ 28.706.000,00 e -862.000,00, montados do balanço): carteira e adiantamentos conferidos, 0', left(v_res, 300));
  v_res := teste_imp_0274(u_socio, c_can, c_ind, c_ap, '2025-12-31', teste_resumo_0274('2025-12-31', 2863400000, -111300000));
  v_r := teste_json_0274(v_res);
  perform teste_assert_0274((teste_rec_0274(v_r, 'aging_ap_fornecedores')).resultado = 'ok' and (teste_rec_0274(v_r, 'aging_ap_fornecedores')).divergencia_abs = 0
                            and (teste_rec_0274(v_r, 'aging_ap_adiantamentos')).resultado = 'ok' and (teste_rec_0274(v_r, 'aging_ap_adiantamentos')).divergencia_abs = 0,
    'Canastra Indústria, AP de 31/12/2025 (R$ 28.634.000,00 e -1.113.000,00): Fornecedores e Adiantamentos a fornecedores conferidos, 0', left(v_res, 300));

  -- ------------------------------------------------------------------ 10. O RESUMO QUE NÃO FECHA CONSIGO MESMO É RECUSADO
  raise notice '--- 10. a fronteira de confiança: cada incoerência do resumo é recusada com o motivo ---';
  v_base := teste_resumo_0274('2025-12-31', 2491700000, -21200000);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', v_base);
  perform teste_assert_0274(v_res like 'ok|%', 'CONTROLE: o resumo coerente (o mesmo que as falhas abaixo alteram) é aceito', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', jsonb_set(v_base, '{positivos,por_faixa,1_30}', '"996680100"'));
  perform teste_assert_0274(v_res like '22023|%Σ por_faixa%', 'Σ das faixas diferente do saldo positivo: recusado', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', jsonb_set(v_base, '{positivos,vencido}', '"996680001"'));
  perform teste_assert_0274(v_res like '22023|%positivos.vencido%', 'vencido diferente da soma das faixas vencidas: recusado', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', jsonb_set(v_base, '{maiores,0,saldo}', '"1245850001"'));
  perform teste_assert_0274(v_res like '22023|%Σ maiores + demais%', 'Σ maiores + demais diferente do saldo positivo (uma contraparte sumiu): recusado', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', jsonb_set(v_base, '{demais,titulos}', '2'));
  perform teste_assert_0274(v_res like '22023|%Σ títulos%', 'Σ de títulos dos maiores + demais diferente de positivos.titulos: recusado', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', jsonb_set(v_base, '{negativos,saldo}', '"21200000"'));
  perform teste_assert_0274(v_res like '22023|%negativos.saldo positivo%', 'saldo negativo POSITIVO: recusado', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', jsonb_set(v_base, '{positivos,saldo}', '"-5"'));
  perform teste_assert_0274(v_res like '22023|%positivos.saldo negativo%', 'saldo positivo NEGATIVO: recusado', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', jsonb_set(v_base, '{data_base}', '"2025-12-30"'));
  perform teste_assert_0274(v_res like '22023|%data_base do resumo%', 'data_base do resumo diferente da data-base informada: recusado', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', jsonb_set(v_base, '{positivos,titulos}', '"3"'));
  perform teste_assert_0274(v_res like '22023|%positivos.titulos não é contagem inteira%', 'contagem de títulos como TEXTO ("3"): recusada', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', jsonb_set(v_base, '{positivos,saldo}', '2491700000'::jsonb));
  perform teste_assert_0274(v_res like '22023|%positivos.saldo não é inteiro em centavos, em texto%', 'centavos como NÚMERO JSON (perde precisão acima de 2^53): recusado', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', jsonb_set(v_base, '{positivos,por_faixa,a_vencer}', '"1495020000.50"'));
  perform teste_assert_0274(v_res like '22023|%faixa a_vencer%', 'centavos com casa decimal ("1495020000.50"): recusado', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', v_base #- '{positivos,por_faixa,acima_360}');
  perform teste_assert_0274(v_res like '22023|%exatamente as 7 faixas%', 'faixa faltando: recusado (exatamente as 7 faixas)', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', jsonb_set(v_base, '{positivos,por_faixa,extra}', '"0"'));
  perform teste_assert_0274(v_res like '22023|%exatamente as 7 faixas%', 'faixa a mais: recusado', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', jsonb_set(v_base, '{negativos,demais,saldo}', '"1"'));
  perform teste_assert_0274(v_res like '22023|%Σ negativos.maiores + negativos.demais%', 'Σ negativos.maiores + negativos.demais diferente do saldo negativo (um crédito sumiu): recusado', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', v_base #- '{negativos,demais}');
  perform teste_assert_0274(v_res like '22023|%negativos.demais%ausente%', 'negativos sem o "demais" (formato antigo da biblioteca): recusado, não aceito calado', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', '[]'::jsonb);
  perform teste_assert_0274(v_res like '22023|%não é um objeto%', 'resumo que nem é um objeto: recusado', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', jsonb_set(jsonb_set(v_base, '{positivos,por_faixa,1_30}', '"1"'), '{negativos,saldo}', '"5"'));
  perform teste_assert_0274(v_res like '22023|%Σ por_faixa%' and v_res like '%negativos.saldo positivo%', 'o recusado traz TODOS os motivos juntos, não só o primeiro', v_res);
  select count(*) into v_n2 from aging_importado;
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', jsonb_set(v_base, '{positivos,por_faixa,1_30}', '"996680100"'));
  perform teste_assert_0274((select count(*) from aging_importado) = v_n2, 'uma importação recusada NÃO grava linha nenhuma', null);

  raise notice '--- 11. leitura, arquivo, mapeamento e entidade ---';
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', v_base, 'authenticated', jsonb_build_object('formato', 'csv', 'sha256', null, 'parcial', true));
  perform teste_assert_0274(v_res like '22023|%PARCIAL%', 'leitura PARCIAL (interrompida depois da amostra): recusada', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', v_base, 'authenticated', jsonb_build_object('formato', 'csv', 'sha256', repeat('c', 64), 'bytes', 2048));
  perform teste_assert_0274(v_res like '22023|%sha256 da leitura é diferente%', 'sha256 da leitura diferente do do arquivo: recusado', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', v_base, 'authenticated', '[]'::jsonb);
  perform teste_assert_0274(v_res like '22023|%têm de ser objetos%', 'o resumo da leitura que não é objeto: recusado', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', v_base, 'authenticated', null, jsonb_build_object('nome', 'ar.csv', 'sha256', 'xyz', 'bytes', 2048, 'formato', 'csv'));
  perform teste_assert_0274(v_res like '22023|%sha256 (64 hex minúsculos)%', 'arquivo com sha256 que não é 64 hex: recusado', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', v_base, 'authenticated', null, jsonb_build_object('nome', 'ar.csv', 'sha256', v_ef, 'bytes', 0, 'formato', 'csv'));
  perform teste_assert_0274(v_res like '22023|%bytes > 0%', 'arquivo com 0 bytes: recusado', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', v_base, 'authenticated', null, jsonb_build_object('nome', 'ar.csv', 'sha256', v_ef, 'bytes', 2048, 'formato', 'pdf'));
  perform teste_assert_0274(v_res like '22023|%formato csv ou xlsx%', 'arquivo de formato fora de csv/xlsx: recusado', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', v_base, 'authenticated', null, null, v_map_ap);
  perform teste_assert_0274(v_res like '22023|%o mapeamento é de contas_a_pagar%', 'mapeamento de OUTRO tipo_base: recusado', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', v_base, 'authenticated', null, null, gen_random_uuid());
  perform teste_assert_0274(v_res like '22023|%mapeamento inexistente%', 'mapeamento que não existe: recusado (arquivo sem mapeamento confirmado não vira dado)', v_res);
  v_res := teste_imp_0274(u_ana, v_a, eb, c_ar, '2025-12-31', v_base);
  perform teste_assert_0274(v_res like '22023|%não é deste mandato%', 'entidade de OUTRO mandato: recusada', v_res);
  v_res := teste_imp_0274(u_ana, v_a, null, c_ar, '2025-12-31', v_base);
  perform teste_assert_0274(v_res like '22023|%não é deste mandato%', 'entidade nula: recusada (de qual empresa é a carteira é obrigatório)', v_res);
  v_res := teste_exec_0274(u_ana, 'authenticated', format('fn_aging_importar(%L::uuid, %L::uuid, %L, NULL::date, %L::jsonb, %L::jsonb, %L::jsonb, %L::jsonb, %L::uuid)', v_a, e1, c_ar, v_base, '{}', '{}', '{}', v_map_ar));
  perform teste_assert_0274(v_res like '22023|%data-base é obrigatória%', 'data-base nula: recusada', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, 'x', '2025-12-31', v_base);
  perform teste_assert_0274(v_res like '22023|%tipo_base%', 'tipo_base fora da lista: recusado', v_res);
  v_res := teste_imp_0274(u_socio, gen_random_uuid(), e1, c_ar, '2025-12-31', v_base);
  perform teste_assert_0274(v_res like 'P0002|%', 'mandato inexistente (para o Sócio): P0002', v_res);

  -- ------------------------------------------------------------------ 12. AS CHECKs: NEM O SERVICE_ROLE GRAVA INCOERÊNCIA
  v_b31 := teste_resumo_0274('2031-01-01', 2491700000, -21200000);
  raise notice '--- 12. as CHECKs da tabela cobrem quem escreve sem passar pela função ---';
  perform teste_assert_0274(teste_ins_0274(v_a, e1, v_b31) = 'ok', 'CONTROLE: a inserção direta coerente é aceita (as recusas abaixo são das CHECKs, não de um erro de montagem)', null);
  delete from aging_importado where data_base = '2031-01-01';
  perform teste_assert_0274(teste_ins_0274(v_a, e1, jsonb_set(v_b31, '{positivos,por_faixa,1_30}', '"996680100"')) = '23514', 'direto: resumo que não fecha: 23514 (CHECK aging_resumo_fecha)', null);
  perform teste_assert_0274(teste_ins_0274(v_a, e1, v_b31, 'xyz') = '23514', 'direto: sha256 que não é 64 hex: 23514 (CHECK aging_arquivo_inteiro)', null);
  perform teste_assert_0274(teste_ins_0274(v_a, e1, v_b31, null, null, '2031-01-01', c_ar, null, null, 0) = '23514', 'direto: bytes = 0: 23514', null);
  perform teste_assert_0274(teste_ins_0274(v_a, e1, v_b31, null, null, '2031-01-01', c_ar, null, null, 2048, 'pdf') = '23514', 'direto: formato pdf: 23514', null);
  perform teste_assert_0274(teste_ins_0274(v_a, e1, v_b31, null, '[]'::jsonb) = '23514', 'direto: leitura que não é objeto: 23514 (CHECK aging_leitura_e_aplicador_objetos)', null);
  perform teste_assert_0274(teste_ins_0274(v_a, e1, v_b31, null, null, '2031-01-01', c_ar, now(), null) = '23514', 'direto: substituido_em sem substituido_por: 23514 (CHECK aging_substituicao_inteira)', null);
  perform teste_assert_0274(teste_ins_0274(v_a, e1, jsonb_set(v_b31, '{data_base}', '"2031-01-02"')) = '23514', 'direto: data_base do resumo diferente da coluna data_base: 23514', null);
  perform teste_assert_0274(teste_ins_0274(v_a, e1, v_b31, null, null, '2031-01-01', 'x') = '23514', 'direto: tipo_base fora da lista: 23514', null);
  perform teste_assert_0274(teste_ins_0274(v_a, e1, v_b31) = 'ok' and teste_ins_0274(v_a, e1, v_b31) = '23505',
    'direto: duas vigentes da mesma (caso, entidade, tipo_base, data_base): a segunda leva 23505 (índice único parcial)', null);
  delete from aging_importado where data_base = '2031-01-01';
  perform teste_assert_0274(teste_ins_0274(v_a, e1, v_b31) = 'ok' and teste_ins_0274(v_a, e1, v_b31, null, null, '2031-01-01', c_ar, now(), gen_random_uuid()) = 'ok',
    'direto: a substituída (com autor da substituição) NÃO conta como vigente: duas linhas da mesma chave, uma vigente, entram', null);
  delete from aging_importado where data_base = '2031-01-01';

  -- ------------------------------------------------------------------ 13. QUEM IMPORTA, COMO authenticated
  raise notice '--- 13. quem importa, COMO authenticated, no mandato (e quem não) ---';
  v_res := teste_imp_0274(u_socio, v_a, e1, c_ar, '2025-12-31', v_base);
  perform teste_assert_0274(v_res like 'ok|%', 'o Sócio importa', v_res);
  v_res := teste_imp_0274(u_leo, v_a, e1, c_ar, '2025-12-31', v_base);
  perform teste_assert_0274(v_res like '42501|%', 'a Leitura do mandato NÃO importa (42501)', v_res);
  v_res := teste_imp_0274(u_xan, v_a, e1, c_ar, '2025-12-31', v_base);
  perform teste_assert_0274(v_res like '42501|%', 'a Analista de OUTRO mandato (alocada só em B) NÃO importa em A (42501)', v_res);
  v_res := teste_imp_0274(u_ana, v_b, eb, c_ar, '2025-12-31', v_base);
  perform teste_assert_0274(v_res like '42501|%', 'a Analista de A NÃO importa em B (42501)', v_res);
  v_res := teste_imp_0274(u_nil, v_a, e1, c_ar, '2025-12-31', v_base);
  perform teste_assert_0274(v_res like '42501|%', 'quem não tem papel NÃO importa (42501)', v_res);
  v_res := teste_imp_0274(null, v_a, e1, c_ar, '2025-12-31', v_base);
  perform teste_assert_0274(v_res like '42501|%', 'authenticated com JWT SEM sub NÃO importa (42501)', v_res);
  v_res := teste_imp_0274(u_ana, v_a, e1, c_ar, '2025-12-31', v_base, 'anon');
  perform teste_assert_0274(v_res like '42501|%', 'o papel anon não tem EXECUTE (42501)', v_res);
  v_res := teste_imp_0274(u_socio, null, e1, c_ar, '2025-12-31', v_base);
  perform teste_assert_0274(v_res like '42501|%', 'mandato nulo, ATÉ PARA O SÓCIO: recusa (42501)', v_res);
  perform set_config('request.jwt.claims', '', true);
  begin
    perform fn_aging_importar(v_a, e1, c_ar, '2025-12-31', v_base, '{}', '{}', '{}', v_map_ar);
    v_res := 'ok';
  exception when others then v_res := sqlstate; end;
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  perform teste_assert_0274(v_res = '42501', 'a conexão de serviço (sem auth.uid() não há autor) NÃO importa (42501)', v_res);
  v_res := teste_exec_0274(u_ana, 'authenticated', format('fn_reconciliar_aging(%L::uuid)', v_id2));
  perform teste_assert_0274(v_res like '42501|%', 'fn_reconciliar_aging: o authenticated NÃO executa (escreve em reconciliacao; só service_role e as funções definer)', v_res);
  v_res := teste_exec_0274(u_leo, 'authenticated', format('fn_reconciliar_aging_do_caso(%L::uuid)', v_a));
  perform teste_assert_0274(v_res like '42501|%', 'fn_reconciliar_aging_do_caso: a Leitura NÃO dispara a conciliação (42501)', v_res);
  v_res := teste_exec_0274(u_xan, 'authenticated', format('fn_reconciliar_aging_do_caso(%L::uuid)', v_a));
  perform teste_assert_0274(v_res like '42501|%', 'fn_reconciliar_aging_do_caso: a Analista de OUTRO mandato NÃO dispara a conciliação (42501)', v_res);
  v_res := teste_exec_0274(u_socio, 'authenticated', 'fn_reconciliar_aging_do_caso(NULL::uuid)');
  perform teste_assert_0274(v_res like '42501|%', 'fn_reconciliar_aging_do_caso com mandato nulo, ATÉ PARA O SÓCIO: 42501 (NULL não é "todos os mandatos")', v_res);
  perform teste_assert_0274(teste_sql_0274(u_ana, 'authenticated', format('insert into aging_importado (caso_id) values (%L)', v_a)) = '42501', 'a escrita DIRETA do authenticated (insert) é negada: 42501', null);
  perform teste_assert_0274(teste_sql_0274(u_ana, 'authenticated', 'update aging_importado set arquivo_nome = ''x''') = '42501', 'o update direto do authenticated é negado: 42501', null);
  perform teste_assert_0274(teste_sql_0274(u_ana, 'authenticated', 'delete from aging_importado') = '42501', 'o delete direto do authenticated é negado: 42501', null);
  perform teste_assert_0274(teste_sql_0274(u_ana, 'anon', 'select count(*) from aging_importado') = '42501', 'o anon não lê a tabela: 42501', null);

  raise notice '--- 14. quem lê (RLS por mandato) e a trilha ---';
  perform teste_assert_0274(teste_ve_0274(u_leo, v_a) > 0 and teste_ve_0274(u_ana, v_a) = teste_ve_0274(u_leo, v_a), 'a Leitura e a Analista do mandato A leem as importações de A (as mesmas)', teste_ve_0274(u_leo, v_a)::text);
  perform teste_assert_0274(teste_ve_0274(u_xan, v_a) = 0, 'a Analista de B NÃO lê as importações de A (resumo de carteira é dado do cliente)', teste_ve_0274(u_xan, v_a)::text);
  perform teste_assert_0274(teste_ve_0274(u_nil, v_a) = 0, 'quem não tem papel não lê nenhuma', teste_ve_0274(u_nil, v_a)::text);
  perform teste_assert_0274(teste_ve_0274(u_socio, v_a) = (select count(*) from aging_importado where caso_id = v_a), 'o Sócio lê todas as de A', null);
  perform teste_assert_0274((select count(*) from evento_auditoria where acao = 'aging_importado' and entidade_ref = 'caso:' || v_a and ator = 'usuario:' || u_ana
                              and depois ->> 'entidade_id' = e7::text and depois ->> 'tipo_base' = c_ar and depois ->> 'data_base' = '2025-12-31' and depois ->> 'arquivo_sha256' = v_ef) = 1,
    'a importação grava aging_importado (caso:<id>, o autor, a entidade, a data-base e o sha256)', null);
  perform teste_assert_0274((select count(*) from evento_auditoria where acao = 'aging_importado' and entidade_ref = 'caso:' || v_a and antes ? 'substituido') >= 1,
    'e a que SUBSTITUI traz a substituída no `antes`', null);
  perform teste_assert_0274(teste_ve_evento_0274(u_leo, v_a) = (select count(*) from evento_auditoria where acao = 'aging_importado' and entidade_ref = 'caso:' || v_a)
                            and teste_ve_evento_0274(u_xan, v_a) = 0, 'a Leitura de A lê a trilha de A; a Analista de B não lê (o entidade_ref `caso:` resolve o mandato)', null);

  -- ------------------------------------------------------------------ 15. A SONDA
  raise notice '--- 15. a sonda enxerga tudo o que a 0274 instala ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0274' and not presente;
  perform teste_assert_0274(v_n = 0, 'a sonda enxerga os 14 requisitos da 0274 (zero ausentes)', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0274';
  perform teste_assert_0274(v_n = 14, 'e o catálogo da 0274 tem 14 requisitos (não está vazio nem encolheu)', v_n::text);

  -- DEVOLVE O ESTADO: os dados de teste saem (inclusive o que foi gravado no caso do fixture Canastra, que outras suítes leem).
  delete from aging_importado;
  delete from evento_auditoria where acao = 'aging_importado' or acao like 'reconciliacao\_aging\_%';
  delete from pendencia where motivo like 'reconciliacao:aging\_a%';
  delete from reconciliacao where tipo like 'aging\_a%';
  delete from caso where nome like '0274 —%';
  delete from mapeamento_de_colunas where id in (v_map_ar, v_map_ap);
  delete from auth.users where id in (u_socio, u_ana, u_leo, u_nil, u_xan);

  raise notice 'EXECUCOES=% FALHAS=%', current_setting('ct74.execucoes', true), coalesce(current_setting('ct74.falhas', true), '0');
  if current_setting('ct74.medindo', true) is distinct from 'on' then
    raise notice 'TODOS OS TESTES DA 0274 PASSARAM';
  end if;
end $$;
