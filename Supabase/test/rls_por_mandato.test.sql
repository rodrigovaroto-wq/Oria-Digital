-- =============================================================================
-- 0216 — A leitura que só o membro faz: RLS por mandato em toda tabela de dado do cliente
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número de asserts e o de reprovações com cada correção desligada estão no
-- cabeçalho de Supabase/migrations/0216_a_leitura_que_so_o_membro_faz.sql.
--
-- O QUE MEDE (comportamento, sempre como `authenticated` com o jwt de cada usuário — a ficha
-- rls-so-select-passa-no-superusuario existe porque o superusuário ignora RLS e tudo passaria): (1) o usuário A,
-- membro só do mandato X, não lê NENHUMA linha do mandato Y em NENHUMA tabela de dado do cliente, e o B espelha; o
-- administrador lê os dois; quem não é membro de nada lê zero; (2) a lista das tabelas vem do CATÁLOGO, não de uma
-- lista fixa aqui: tabela nova sem policy por mandato reprova (fail-closed: tudo que não está na lista de catálogos
-- globais é dado de cliente); (3) A escreve normalmente em X e não escreve em Y (insert, update, delete, evento
-- forjado, objeto do bucket); (4) o evento sem mandato só o administrador lê, e o gatilho deriva o caso de cada forma
-- de entidade_ref que existe no código; (5) o bucket `documentos` só abre a pasta do mandato; (6) fn_upsert_caso do
-- não membro recusa (42501) e NÃO cria o segundo caso; (7) a guarda da migration recusa administrador vazio com caso
-- órfão; (8) a sonda enxerga a policy que voltou a using (true).
--
-- Montagem: usuários e dados como superusuário (auth.uid() nulo); os mandatos X e Y nascem por fn_upsert_caso COMO
-- A e COMO B (o caminho real do portal). O "service_role" é o superusuário sem claims: no banco de teste o papel
-- service_role não tem BYPASSRLS como o do Supabase. O Supabase concede o acesso de storage.objects ao authenticated;
-- o replay local não, então o teste concede (e só no teste).
-- =============================================================================

create or replace function teste_assert_0216(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_cond then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- As tabelas de dado do cliente, DO CATÁLOGO: toda tabela de public que não é catálogo global nem a própria
-- pertinência. Tabela nova entra aqui sozinha — e, sem policy por mandato, reprova abaixo.
create or replace function teste_tabelas_cliente_0216() returns setof text language sql stable as $$
  select c.relname::text from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
     and c.relname not like 'teste\_%'
     and c.relname not in ('administrador', 'caso_membro',
        'premissa_catalogo', 'classe_contabil_catalogo', 'rubrica_classe', 'fato_tipo_catalogo', 'pergunta_catalogo',
        'golden_rodada', 'golden_criterio', 'estagio_autonomia', 'instalacao_cobertura', 'instalacao_requisito')
     and c.relname !~ '^(taxonomia|indice_macro)_'
   order by 1
$$;

-- Os catálogos globais que o authenticated continua lendo.
create or replace function teste_catalogos_0216() returns setof text language sql stable as $$
  select unnest(array['premissa_catalogo', 'classe_contabil_catalogo', 'rubrica_classe', 'fato_tipo_catalogo',
    'pergunta_catalogo', 'golden_rodada', 'estagio_autonomia', 'instalacao_cobertura', 'instalacao_requisito',
    'taxonomia_tipo_documento', 'taxonomia_tipo_cobertura', 'taxonomia_linha_exigida', 'taxonomia_linha_alternativa',
    'taxonomia_linha_localizador', 'indice_macro_serie', 'indice_macro_obs', 'indice_macro_expectativa'])
$$;

-- ORÁCULO (superusuário): o filtro "linhas deste mandato" de cada tabela, derivado pelo FK, INDEPENDENTE da policy.
create or replace function teste_filtro_0216(p_tabela text) returns text language sql immutable as $$
  select case
    when p_tabela = 'documento_versao' then 'documento_id in (select id from documento where caso_id = $1)'
    when p_tabela in ('campo_extraido', 'documento_fato') then
      'documento_versao_id in (select dv.id from documento_versao dv join documento d on d.id = dv.documento_id where d.caso_id = $1)'
    when p_tabela in ('campo_classe_sugerida', 'campo_classe_override') then
      'campo_extraido_id in (select c.id from campo_extraido c join documento_versao dv on dv.id = c.documento_versao_id join documento d on d.id = dv.documento_id where d.caso_id = $1)'
    when p_tabela in ('arquivo_oficial_registro', 'arquivo_oficial_lancamento_mes') then
      'arquivo_oficial_id in (select id from arquivo_oficial where caso_id = $1)'
    when p_tabela in ('golden_documento', 'golden_campo', 'golden_rotulo') then
      'documento_id in (select id from documento where caso_id = $1)'
    when p_tabela = 'caso' then 'id = $1'
    else 'caso_id = $1' end
$$;

create or replace function teste_n_do_caso_0216(p_tabela text, p_caso uuid) returns bigint language plpgsql as $$
declare v bigint;
begin
  execute format('select count(*) from public.%I where %s', p_tabela, teste_filtro_0216(p_tabela)) into v using p_caso;
  return v;
end $$;

-- Roda COMO o chamador (invoker): a RLS vale. Chamada com o role authenticated já posto.
create or replace function teste_conta_0216(p_tabela text, p_onde text default 'true') returns bigint language plpgsql as $$
declare v bigint;
begin
  execute format('select count(*) from public.%I where %s', p_tabela, p_onde) into v;
  return v;
end $$;

-- Quantas tabelas o usuário (jwt atual, role authenticated) vê com mais linhas do que as do mandato dele. Devolve a
-- lista dos infratores: p_caso_ok = o único mandato que ele pode ler (ou null: nenhum).
create or replace function teste_infratores_0216(p_caso_ok uuid) returns text language plpgsql as $$
declare t text; n bigint; esperado bigint; lista text := '';
begin
  for t in select * from teste_tabelas_cliente_0216() loop
    n := teste_conta_0216(t);
    esperado := case when p_caso_ok is null then 0 else (select teste_n_do_caso_super_0216(t, p_caso_ok)) end;
    if n <> esperado then lista := lista || t || '(' || n || '≠' || esperado || ') '; end if;
  end loop;
  return lista;
end $$;
-- a contagem esperada precisa do superusuário: função SECURITY DEFINER do teste (o dono é quem aplica o teste)
create or replace function teste_n_do_caso_super_0216(p_tabela text, p_caso uuid) returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare v bigint;
begin
  execute format('select count(*) from public.%I where %s', p_tabela, teste_filtro_0216(p_tabela)) into v using p_caso;
  return v;
end $$;

create or replace function teste_total_super_0216(p_tabela text) returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare v bigint;
begin
  execute format('select count(*) from public.%I', p_tabela) into v;
  return v;
end $$;

-- O administrador: vê o TOTAL de toda tabela de cliente.
create or replace function teste_infratores_admin_0216() returns text language plpgsql as $$
declare t text; n bigint; lista text := '';
begin
  for t in select * from teste_tabelas_cliente_0216() loop
    n := teste_conta_0216(t);
    if n <> teste_total_super_0216(t) then lista := lista || t || '(' || n || '≠' || teste_total_super_0216(t) || ') '; end if;
  end loop;
  return lista;
end $$;

-- Semeia UMA linha em cada tabela de dado do cliente para o mandato (superusuário). Cada insert é o mínimo que os
-- NOT NULL e os checks pedem; valores de enum/FK copiados de linhas que o banco já tem.
create or replace function teste_semear_0216(p_caso uuid, p_rodada uuid) returns void language plpgsql as $$
declare
  v_ent uuid; v_per uuid; v_doc uuid; v_ver uuid; v_campo uuid; v_ao uuid; v_c1 uuid; v_c2 uuid;
begin
  insert into entidade (caso_id, razao_social) values (p_caso, 'Empresa 0216 ' || p_caso) returning id into v_ent;
  insert into periodo (caso_id, tipo, referencia) values (p_caso, 'anual', '2025') returning id into v_per;
  insert into documento (caso_id, entidade_id, periodo_id, fonte) values (p_caso, v_ent, v_per, '0216') returning id into v_doc;
  insert into documento_versao (documento_id, arquivo_ref) values (v_doc, p_caso || '/h0216.pdf') returning id into v_ver;
  insert into campo_extraido (documento_versao_id, chave, valor_num, ordem) values (v_ver, 'receita_liquida', 100, 1) returning id into v_campo;
  insert into documento_fato (documento_versao_id, tipo, trecho) values (v_ver, 'continuidade_operacional', 'trecho do fato 0216 com mais de vinte caracteres');
  insert into campo_classe_sugerida (campo_extraido_id, classe_codigo, justificativa, versao_taxonomia, nivel_autonomia)
    values (v_campo, 'recorrente', 'j', 1, 'N0');
  insert into campo_classe_override (campo_extraido_id, classe_final, autor) values (v_campo, 'recorrente', 'teste');
  insert into pendencia (caso_id, tipo, severidade) values (p_caso, 'papel_no_grupo_indefinido', 'complementar');
  insert into reconciliacao (caso_id, tipo, precondicoes_ok, resultado) values (p_caso, 'conflito_entre_documentos', true, 'ok');
  insert into decisao (caso_id, tipo, autor) values (p_caso, 'aprovacao', 'teste');
  insert into caso_premissa (caso_id, premissa_codigo) values (p_caso, 'IPCA');
  insert into caso_linha_premissa (caso_id, rotulo_norm) values (p_caso, 'rotulo 0216');
  insert into caso_apresentacao_campo (caso_id, chave, valor) values (p_caso, 'k0216.a', 'v');
  insert into caso_modelagem (caso_id) values (p_caso) on conflict do nothing;
  insert into caso_pergunta (caso_id, pergunta_codigo, acao, autor, texto_enviado) values (p_caso, 'A3', 'enviada', 'teste', 'texto 0216');
  insert into checklist_item_status (caso_id, tipo_taxonomia, obrigatoriedade)
    select p_caso, codigo, 'obrigatorio' from taxonomia_tipo_documento limit 1;
  insert into lote_execucao (caso_id, execucao_ref) values (p_caso, 'ref-0216-' || p_caso);
  insert into execucao_falha (caso_id, etapa, mensagem) values (p_caso, 'teste', 'falha 0216');
  insert into perimetro (caso_id, entidade_id, escopo, desde) values (p_caso, v_ent, 'COMBINADO 0216', current_date);
  insert into controlador (caso_id, nome, tipo_pessoa) values (p_caso, 'Ctl A 0216', 'fisica') returning id into v_c1;
  insert into controlador (caso_id, nome, tipo_pessoa) values (p_caso, 'Ctl B 0216', 'fisica') returning id into v_c2;
  insert into entidade_controlador (caso_id, entidade_id, controlador_id) values (p_caso, v_ent, v_c1);
  insert into controlador_vinculo (caso_id, controlador_a, controlador_b, parentesco, fonte, declarado_por)
    values (p_caso, least(v_c1, v_c2), greatest(v_c1, v_c2), 'conjuge_companheiro', 'teste 0216', 'teste');
  insert into arquivo_oficial (caso_id, familia, hash_sha256, controle_tipo, status, controle_lido, leitor_versao)
    values (p_caso, 'sped', 'h0216' || p_caso, 'documento_unico', 'lido', 1, 'teste/1') returning id into v_ao;
  insert into arquivo_oficial_registro (arquivo_oficial_id, linha, registro, conteudo) values (v_ao, 1, '0000', 'x');
  insert into arquivo_oficial_lancamento_mes (arquivo_oficial_id, conta, debito, credito, partidas, partidas_sem_valor)
    values (v_ao, '1.1', 1, 1, 1, 0);
  insert into golden_documento (rodada_id, documento_id, estrato, origem) values (p_rodada, v_doc, 'escaneado', 'real');
  insert into golden_campo (rodada_id, documento_id, rotulador, chave) values (p_rodada, v_doc, 'teste', 'receita_liquida');
  insert into golden_rotulo (rodada_id, documento_id, rotulador) values (p_rodada, v_doc, 'teste');
end $$;

-- limpeza de rodada anterior (cascata leva caso_membro e o que pende do caso; o rastro é append-only e fica)
delete from storage.objects where name like '0216a1%' or name like 'lixo0216/%' or name = 'raiz0216.pdf';
delete from golden_rodada where nome = '0216 — rodada';
delete from caso where nome like '0216 — %';
delete from auth.users where email like '%@0216.teste';
grant usage on schema storage to authenticated;
grant select, insert, update, delete on storage.objects to authenticated;

do $$
declare
  ua constant uuid := '0216a000-0000-0000-0000-00000000000a';
  ub constant uuid := '0216a000-0000-0000-0000-00000000000b';
  uc constant uuid := '0216a000-0000-0000-0000-00000000000c';
  un constant uuid := '0216a000-0000-0000-0000-00000000000d';
  v_x uuid; v_y uuid; v_z uuid; v_rod uuid; v_novo uuid; v_dup1 uuid; v_dup2 uuid;
  v_n bigint; v_m bigint; v_lista text; v_err text; v_b boolean;
  v_doc_y uuid; v_ver_x uuid; v_ver_y uuid; v_ent_y uuid; v_doc_x uuid; v_ent_x uuid;
  v_ev int; v_casos int; v_tag text; v_res jsonb; v_res2 jsonb;
begin
  raise notice '--- 0. o catálogo da sonda tem os requisitos da 0216 e nenhum está ausente ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0216';
  perform teste_assert_0216(v_n = 64, 'a sonda tem os 64 requisitos da 0216', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0216' and not presente;
  perform teste_assert_0216(v_n = 0, 'nenhum requisito da 0216 ausente',
    (select string_agg(chave || ': ' || detalhe, ' | ') from fn_instalacao_conferir() where migration = '0216' and not presente));

  raise notice '--- 1. montagem: A (membro de X), B (membro de Y), C (administrador), N (de nada) ---';
  insert into auth.users (id, email) values (ua, 'a@0216.teste'), (ub, 'b@0216.teste'), (uc, 'c@0216.teste'), (un, 'n@0216.teste');
  perform fn_administrador_definir('c@0216.teste', true);
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_x := fn_upsert_caso('0216 — X', 'portal:navegador');
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', ub, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_y := fn_upsert_caso('0216 — Y', 'portal:navegador');
  reset role;
  perform set_config('request.jwt.claims', '', true);
  insert into golden_rodada (nome, taxonomia_versao) values ('0216 — rodada', 1) returning id into v_rod;
  perform teste_semear_0216(v_x, v_rod);
  perform teste_semear_0216(v_y, v_rod);
  select count(*) into v_n from (select t from teste_tabelas_cliente_0216() t
     where teste_n_do_caso_super_0216(t, v_x) > 0 and teste_n_do_caso_super_0216(t, v_y) > 0) s;
  select count(*) into v_m from teste_tabelas_cliente_0216();
  perform teste_assert_0216(v_n = v_m and v_m >= 29,
    'o arranjo não é vazio: TODA tabela de cliente do catálogo tem linha em X e em Y', v_n || ' de ' || v_m);

  raise notice '--- 2. A lê só X; B lê só Y; C lê tudo; N não lê nada (em TODA tabela de cliente) ---';
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_lista := teste_infratores_0216(v_x);
  reset role;
  perform teste_assert_0216(v_lista = '', 'A vê exatamente as linhas de X em toda tabela de cliente (e nenhuma de Y)', v_lista);
  perform set_config('request.jwt.claims', json_build_object('sub', ub, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_lista := teste_infratores_0216(v_y);
  reset role;
  perform teste_assert_0216(v_lista = '', 'B vê exatamente as linhas de Y em toda tabela de cliente (e nenhuma de X)', v_lista);
  perform set_config('request.jwt.claims', json_build_object('sub', un, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_lista := teste_infratores_0216(null);
  reset role;
  perform teste_assert_0216(v_lista = '', 'N, que não é membro de nada, vê zero linhas em toda tabela de cliente', v_lista);
  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_lista := teste_infratores_admin_0216();
  reset role;
  perform teste_assert_0216(v_lista = '', 'C, administrador, lê o TOTAL de toda tabela de cliente (X, Y e o resto)', v_lista);
  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from caso;
  reset role;
  select count(*) into v_m from caso;
  perform teste_assert_0216(v_n = v_m, 'C lê TODOS os casos (o administrador é membro de tudo)', v_n || ' de ' || v_m);

  raise notice '--- 3. as tabelas de cliente do catálogo têm RLS e nenhuma policy using (true) ---';
  select string_agg(t, ' ') into v_lista from teste_tabelas_cliente_0216() t
   where not (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass);
  perform teste_assert_0216(v_lista is null, 'toda tabela de cliente tem RLS ligada', v_lista);
  select string_agg(tablename || '.' || policyname, ' ') into v_lista from pg_policies p
   where schemaname = 'public' and tablename in (select teste_tabelas_cliente_0216())
     and cmd <> 'INSERT' and (qual = 'true');
  perform teste_assert_0216(v_lista is null, 'nenhuma policy de leitura/alteração de tabela de cliente é using (true)', v_lista);
  select string_agg(tablename || '.' || policyname, ' ') into v_lista from pg_policies p
   where schemaname = 'public' and tablename in (select teste_tabelas_cliente_0216())
     and (with_check = 'true') and tablename <> 'caso';
  perform teste_assert_0216(v_lista is null, 'nenhuma policy de escrita de tabela de cliente é with check (true) (só o insert de caso)', v_lista);

  raise notice '--- 4. os catálogos globais continuam legíveis ---';
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select string_agg(t, ' ') into v_lista from teste_catalogos_0216() t where teste_conta_0216(t) = 0;
  reset role;
  perform teste_assert_0216(v_lista is null, 'A lê todo catálogo global (nenhum vazio para ele)', v_lista);
  perform set_config('request.jwt.claims', json_build_object('sub', un, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from taxonomia_tipo_documento;
  reset role;
  select count(*) into v_m from taxonomia_tipo_documento;
  perform teste_assert_0216(v_n = v_m and v_n > 0, 'e N, sem mandato nenhum, também lê a taxonomia', v_n || ' de ' || v_m);

  raise notice '--- 5. A usa X normalmente (o portal faz isto) ---';
  select id into v_ent_x from entidade where caso_id = v_x limit 1;
  select id into v_doc_x from documento where caso_id = v_x limit 1;
  select id into v_ver_x from documento_versao where documento_id = v_doc_x limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into entidade (caso_id, razao_social) values (v_x, 'Nova de A 0216');
  update documento set resumo = 'editado por A' where id = v_doc_x;
  get diagnostics v_n = row_count;
  insert into campo_extraido (documento_versao_id, chave, valor_num, ordem) values (v_ver_x, 'custo', 5, 2);
  insert into pendencia (caso_id, tipo, severidade) values (v_x, 'papel_no_grupo_indefinido', 'complementar');
  insert into caso_apresentacao_campo (caso_id, chave, valor) values (v_x, 'k0216.b', 'v')
    on conflict (caso_id, chave) do update set valor = excluded.valor;
  insert into caso_apresentacao_campo (caso_id, chave, valor) values (v_x, 'k0216.b', 'v2')
    on conflict (caso_id, chave) do update set valor = excluded.valor;
  update caso set nome = '0216 — X' where id = v_x;
  get diagnostics v_m = row_count;
  v_err := null;
  begin
    perform fn_recomputar_completude(v_x);
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  reset role;
  perform teste_assert_0216(v_n = 1 and v_m = 1, 'A atualiza o documento e o caso de X (1 linha cada)', v_n || '/' || v_m);
  perform teste_assert_0216(exists (select 1 from entidade where caso_id = v_x and razao_social = 'Nova de A 0216')
    and exists (select 1 from campo_extraido where documento_versao_id = v_ver_x and chave = 'custo')
    and (select count(*) from pendencia where caso_id = v_x) >= 2
    and (select valor from caso_apresentacao_campo where caso_id = v_x and chave = 'k0216.b') = 'v2',
    'A insere entidade, campo (pela cadeia), pendência e faz upsert de apresentação em X',
    (exists (select 1 from entidade where caso_id = v_x and razao_social = 'Nova de A 0216'))::text || '/'
    || (exists (select 1 from campo_extraido where documento_versao_id = v_ver_x and chave = 'custo'))::text || '/'
    || (select count(*) from pendencia where caso_id = v_x)::text || '/'
    || coalesce((select valor from caso_apresentacao_campo where caso_id = v_x and chave = 'k0216.b'), 'null'));
  perform teste_assert_0216(v_err is null, 'a função de negócio rodando como A (invoker) funciona em X', v_err);
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  delete from entidade where caso_id = v_x and razao_social = 'Nova de A 0216';
  get diagnostics v_n = row_count;
  reset role;
  perform teste_assert_0216(v_n = 1, 'A apaga uma entidade de X');

  raise notice '--- 6. A NÃO escreve em Y ---';
  select id into v_ent_y from entidade where caso_id = v_y limit 1;
  select id into v_doc_y from documento where caso_id = v_y limit 1;
  select id into v_ver_y from documento_versao where documento_id = v_doc_y limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  update documento set resumo = 'invadido' where caso_id = v_y;      get diagnostics v_n = row_count;
  delete from entidade where caso_id = v_y;                          get diagnostics v_m = row_count;
  update caso set nome = '0216 — Y invadido' where id = v_y;         get diagnostics v_ev = row_count;
  delete from caso where id = v_y;                                   get diagnostics v_casos = row_count;
  reset role;
  perform teste_assert_0216(v_n = 0 and v_m = 0 and v_ev = 0 and v_casos = 0,
    'update/delete em Y por A alcançam 0 linhas (documento, entidade, caso, caso)', v_n || '/' || v_m || '/' || v_ev || '/' || v_casos);
  perform teste_assert_0216((select nome from caso where id = v_y) = '0216 — Y' and exists (select 1 from entidade where caso_id = v_y)
    and not exists (select 1 from documento where caso_id = v_y and resumo = 'invadido'), 'e Y continua intacto');
  v_lista := '';
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin insert into entidade (caso_id, razao_social) values (v_y, 'forjada');
  exception when others then if sqlstate <> '42501' then v_lista := v_lista || 'entidade:' || sqlstate || ' '; end if; end;
  begin insert into campo_extraido (documento_versao_id, chave, valor_num) values (v_ver_y, 'forjado', 1);
  exception when others then if sqlstate <> '42501' then v_lista := v_lista || 'campo:' || sqlstate || ' '; end if; end;
  begin insert into documento_fato (documento_versao_id, tipo, trecho) values (v_ver_y, 'continuidade_operacional', 'forjado com mais de vinte caracteres aqui');
  exception when others then if sqlstate <> '42501' then v_lista := v_lista || 'fato:' || sqlstate || ' '; end if; end;
  begin insert into pendencia (caso_id, tipo, severidade) values (v_y, 'papel_no_grupo_indefinido', 'complementar');
  exception when others then if sqlstate <> '42501' then v_lista := v_lista || 'pendencia:' || sqlstate || ' '; end if; end;
  reset role;
  perform teste_assert_0216(v_lista = '' and not exists (select 1 from entidade where caso_id = v_y and razao_social = 'forjada')
    and not exists (select 1 from campo_extraido where chave = 'forjado') and not exists (select 1 from documento_fato where trecho like 'forjado%')
    and (select count(*) from pendencia where caso_id = v_y) = 1,
    'insert em Y por A leva 42501 em entidade, campo (indireta), fato (indireta) e pendência, e nada entra', v_lista);
  -- o que A PODE tentar mudar em X para levar uma linha para Y: o with check do update
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_err := null;
  begin update documento set caso_id = v_y where id = v_doc_x;
  exception when others then v_err := sqlstate; end;
  reset role;
  perform teste_assert_0216(v_err = '42501' and (select caso_id from documento where id = v_doc_x) = v_x,
    'A não consegue MOVER um documento de X para Y (with check do update, 42501)', v_err);

  raise notice '--- 7. o administrador escreve em qualquer mandato ---';
  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  update documento set resumo = 'editado por C' where caso_id = v_y;
  get diagnostics v_n = row_count;
  reset role;
  perform teste_assert_0216(v_n = 1, 'C atualiza o documento de Y (1 linha)', v_n::text);

  v_tag := 't_' || v_x;
  raise notice '--- 8. o evento: o gatilho deriva o caso de cada forma de entidade_ref ---';
  perform set_config('request.jwt.claims', '', true);
  insert into evento_auditoria (ator, acao, entidade_ref) values
    (v_tag, 'e_caso', 'caso:' || v_x),
    (v_tag, 'e_documento', 'documento:' || v_doc_x),
    (v_tag, 'e_versao', 'documento_versao:' || v_ver_x),
    (v_tag, 'e_campo', 'campo_extraido:' || (select id from campo_extraido where documento_versao_id = v_ver_x limit 1)),
    (v_tag, 'e_reconc', 'reconciliacao:' || (select id from reconciliacao where caso_id = v_x limit 1)),
    (v_tag, 'e_pend', 'pendencia:' || (select id from pendencia where caso_id = v_x limit 1)),
    (v_tag, 'e_ent', 'entidade:' || (select id from entidade where caso_id = v_x limit 1)),
    (v_tag, 'e_ctl', 'controlador:' || (select id from controlador where caso_id = v_x limit 1));
  select string_agg(acao, ' ') into v_lista from evento_auditoria e
   where e.ator = v_tag and e.caso_id is distinct from v_x;
  perform teste_assert_0216(v_lista is null, 'as 8 formas com caso (caso, documento, versão, campo, reconciliação, pendência, entidade, controlador) derivam X', v_lista);
  insert into evento_auditoria (ator, acao, entidade_ref) values
    (v_tag, 'n_estagio', 'estagio:classificacao_doc_checklist'),
    (v_tag, 'n_nome', 'caso_nome:0216 — inexistente'),
    (v_tag, 'n_nulo', 'documento_versao:null'),
    (v_tag, 'n_bare', 'campo_extraido'),
    (v_tag, 'n_golden', 'golden_rodada:' || v_rod),
    (v_tag, 'n_orfao', 'documento:00000000-0000-0000-0000-00000000dead');
  select count(*) into v_n from evento_auditoria where ator = v_tag and acao like 'n\_%' and caso_id is null;
  perform teste_assert_0216(v_n >= 6, 'as formas SEM caso por natureza (estagio, caso_nome, versao:null, campo sem id, golden_rodada, id inexistente) ficam nulas', v_n::text);

  raise notice '--- 9. quem lê o evento ---';
  insert into evento_auditoria (ator, acao, entidade_ref) values (v_tag, 'y_caso', 'caso:' || v_y);
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from evento_auditoria where caso_id is distinct from v_x;
  select count(*) into v_m from evento_auditoria where caso_id = v_x;
  reset role;
  perform teste_assert_0216(v_n = 0 and v_m > 0, 'A lê só eventos de X: nenhum de Y, nenhum sem caso', v_n || ' alheios, ' || v_m || ' de X');
  select count(*) into v_n from evento_auditoria where caso_id = v_x;
  perform teste_assert_0216(v_m = v_n, 'e lê TODOS os de X', v_m || ' de ' || v_n);
  perform set_config('request.jwt.claims', json_build_object('sub', un, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from evento_auditoria;
  reset role;
  perform teste_assert_0216(v_n = 0, 'N não lê evento nenhum', v_n::text);
  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from evento_auditoria where caso_id is null;
  select count(*) into v_m from evento_auditoria where caso_id = v_y;
  reset role;
  perform teste_assert_0216(v_n > 0 and v_m > 0, 'C, administrador, lê o evento sem caso e o de Y', v_n || ' sem caso, ' || v_m || ' de Y');

  raise notice '--- 10. quem GRAVA o evento: o rastro não falha, e não se forja em mandato alheio ---';
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into evento_auditoria (ator, acao, entidade_ref) values (v_tag, 'a_em_x', 'documento:' || v_doc_x);
  insert into evento_auditoria (ator, acao, entidade_ref) values (v_tag, 'a_em_y', 'documento:' || v_doc_y);
  insert into evento_auditoria (ator, acao, entidade_ref) values (v_tag, 'a_sem_caso', 'estagio:x');
  v_err := null;
  begin insert into evento_auditoria (ator, acao, entidade_ref, caso_id) values (v_tag, 'a_forjado', 'caso:' || v_y, v_y);
  exception when others then v_err := sqlstate; end;
  select count(*) into v_n from evento_auditoria where acao = 'a_em_x';
  select count(*) into v_m from evento_auditoria where acao in ('a_em_y', 'a_sem_caso');
  reset role;
  perform teste_assert_0216((select caso_id from evento_auditoria where acao = 'a_em_x' order by criado_em desc limit 1) = v_x and v_n = 1,
    'A grava evento sobre documento de X: o gatilho deriva X e A o lê');
  perform teste_assert_0216((select caso_id from evento_auditoria where acao = 'a_em_y' order by criado_em desc limit 1) is null and v_m = 0,
    'evento de A sobre documento de Y NÃO falha (rastro) e entra sem caso: A não o lê, só o administrador');
  perform teste_assert_0216(v_err = '42501' and not exists (select 1 from evento_auditoria where acao = 'a_forjado'),
    'A não forja evento com caso_id explícito de Y (42501)', v_err);

  raise notice '--- 11. o histórico: o backfill deriva pela mesma função ---';
  perform set_config('request.jwt.claims', '', true);
  set session_replication_role = replica;      -- sem o gatilho: simula a linha que já existia antes da 0216
  insert into evento_auditoria (ator, acao, entidade_ref) values (v_tag, 'h_velho', 'documento:' || v_doc_x), (v_tag, 'h_velho', 'estagio:x');
  set session_replication_role = origin;
  select count(*) into v_n from evento_auditoria where ator = v_tag and acao = 'h_velho' and caso_id is not null;
  update evento_auditoria set caso_id = fn_caso_da_referencia(entidade_ref) where caso_id is null and ator = v_tag and acao = 'h_velho';
  select count(*) into v_m from evento_auditoria where ator = v_tag and acao = 'h_velho' and caso_id = v_x;
  perform teste_assert_0216(v_n = 0 and v_m >= 1, 'o evento velho (sem o gatilho) nasce sem caso e o update do backfill o liga a X', v_n || ' antes, ' || v_m || ' depois');

  raise notice '--- 12. mandato excluído: o rastro fica, sem caso (só o administrador) ---';
  v_z := fn_upsert_caso('0216 — Z', 'sistema:n8n');
  select count(*) into v_n from evento_auditoria where caso_id = v_z;
  delete from caso where id = v_z;
  select count(*) into v_m from evento_auditoria where entidade_ref = 'caso:' || v_z and caso_id is null;
  perform teste_assert_0216(v_n = 1 and v_m = 1, 'o evento caso_criado nasce ligado ao caso e, excluído o caso, fica com caso_id nulo (ON DELETE SET NULL)', v_n || '/' || v_m);

  -- e COMO authenticated: o membro exclui o PRÓPRIO mandato (a cascata e o SET NULL do FK rodam por dentro da RLS) e o
  -- membro de outro mandato não exclui o dele (fn_excluir_caso, 0108, é SECURITY INVOKER).
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_z := fn_upsert_caso('0216 — Z2', 'portal:navegador');
  v_res := fn_excluir_caso(v_z, 'a@0216.teste');
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', ub, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_res2 := fn_excluir_caso(v_x, 'b@0216.teste');
  reset role;
  perform teste_assert_0216((v_res->>'excluido')::boolean and not exists (select 1 from caso where id = v_z)
    and exists (select 1 from evento_auditoria where entidade_ref = 'caso:' || v_z and acao = 'caso_excluido' and caso_id is null),
    'A exclui o mandato que criou (cascata e SET NULL por dentro da RLS) e o rastro fica sem caso', v_res::text);
  perform teste_assert_0216(coalesce((v_res2->>'recusado')::boolean, false) and exists (select 1 from caso where id = v_x),
    'B não exclui o mandato de A: o caso não existe para ele (recusa) e X continua', v_res2::text);

  raise notice '--- 13. o bucket documentos: só a pasta do mandato ---';
  insert into storage.objects (bucket_id, name) values
    ('documentos', v_x || '/h1.pdf'), ('documentos', v_y || '/h2.pdf'),
    ('documentos', 'lixo0216/x.pdf'), ('documentos', 'raiz0216.pdf'), ('outro', v_x || '/h3.pdf');
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from storage.objects where name like v_x || '%' or name like v_y || '%' or name like 'lixo0216/%' or name = 'raiz0216.pdf';
  select count(*) into v_m from storage.objects where bucket_id = 'documentos' and name = v_x || '/h1.pdf';
  v_err := null;
  begin insert into storage.objects (bucket_id, name) values ('documentos', v_y || '/forjado.pdf');
  exception when others then v_err := sqlstate; end;
  begin insert into storage.objects (bucket_id, name) values ('documentos', v_x || '/novo.pdf');
  exception when others then v_err := coalesce(v_err, '') || '/x:' || sqlstate; end;
  delete from storage.objects where name = v_y || '/h2.pdf';
  get diagnostics v_ev = row_count;
  reset role;
  perform teste_assert_0216(v_n = 1 and v_m = 1, 'A vê no storage só o objeto de X (nem Y, nem pasta fora do formato, nem a raiz, nem outro bucket)', v_n::text);
  perform teste_assert_0216(v_err = '42501' and exists (select 1 from storage.objects where name = v_x || '/novo.pdf')
    and not exists (select 1 from storage.objects where name = v_y || '/forjado.pdf'),
    'A grava no storage em X e leva 42501 em Y', v_err);
  perform teste_assert_0216(v_ev = 0 and exists (select 1 from storage.objects where name = v_y || '/h2.pdf'), 'A não apaga o objeto de Y');
  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from storage.objects where name like v_x || '/h1%' or name like v_y || '/h2%';
  reset role;
  perform teste_assert_0216(v_n = 2, 'C, administrador, vê o objeto dos dois mandatos', v_n::text);
  perform set_config('request.jwt.claims', json_build_object('sub', un, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from storage.objects where bucket_id = 'documentos' and (name like v_x || '%' or name like v_y || '%');
  reset role;
  perform teste_assert_0216(v_n = 0, 'N não vê objeto nenhum', v_n::text);

  raise notice '--- 14. fn_upsert_caso: o não membro NÃO cria o segundo caso ---';
  select count(*) into v_casos from caso where nome = '0216 — Y';
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_err := null;
  begin v_novo := fn_upsert_caso('0216 — Y', 'portal:navegador');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  reset role;
  select count(*) into v_n from caso where nome = '0216 — Y';
  perform teste_assert_0216(left(v_err, 5) = '42501' and v_err like '%existe e você não é membro%' and v_novo is null,
    'A chamando com o nome de Y recebe 42501 com a mensagem do administrador', v_err);
  perform teste_assert_0216(v_n = 1 and v_casos = 1, 'e NÃO se criou caso duplicado: continua UM caso chamado Y', v_casos || ' → ' || v_n);
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_novo := fn_upsert_caso('0216 — A criou', 'portal:navegador');
  v_dup1 := fn_upsert_caso('0216 — A criou', 'portal:navegador');
  select count(*) into v_n from caso where nome = '0216 — A criou';
  reset role;
  perform teste_assert_0216(v_novo is not null and v_novo = v_dup1 and v_n = 1, 'A com nome novo cria o mandato e a segunda chamada devolve o MESMO (não duplica)');
  perform teste_assert_0216(exists (select 1 from caso_membro where caso_id = v_novo and usuario_id = ua and por = 'criador')
    and (select count(*) from caso_membro where caso_id = v_novo) = 1, 'e A vira o único membro do que criou');
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from caso where id = v_novo;
  select count(*) into v_m from evento_auditoria where entidade_ref = 'caso:' || v_novo and acao = 'caso_criado' and caso_id = v_novo;
  reset role;
  perform teste_assert_0216(v_n = 1 and v_m = 1, 'A lê o caso que criou e o evento caso_criado dele (criado sem RETURNING: o gatilho do criador vem depois)');
  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_dup1 := fn_upsert_caso('0216 — Y', 'portal:navegador');
  reset role;
  perform teste_assert_0216(v_dup1 = v_y, 'o administrador chamando com o nome de Y recebe o id de Y');
  perform set_config('request.jwt.claims', '', true);
  v_dup1 := fn_upsert_caso('0216 — Y');
  v_dup2 := fn_upsert_caso('0216 — n8n criou');
  perform teste_assert_0216(v_dup1 = v_y and v_dup2 is not null and not exists (select 1 from caso_membro where caso_id = v_dup2),
    'sem identidade (n8n/service_role) o comportamento é o de sempre: acha Y pelo nome, cria o novo sem membro');
  -- nomes duplicados JÁ existentes: o membro recebe o dele; o n8n recebe um qualquer (documentado, sem unique)
  insert into caso (nome) values ('0216 — duplicado') returning id into v_dup1;
  insert into caso (nome) values ('0216 — duplicado') returning id into v_dup2;
  insert into caso_membro (caso_id, usuario_id, por) values (v_dup2, ua, 'teste');
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_novo := fn_upsert_caso('0216 — duplicado', 'portal:navegador');
  reset role;
  perform teste_assert_0216(v_novo = v_dup2, 'com dois casos de mesmo nome, o membro recebe o DELE (não é recusado por causa do outro)');

  raise notice '--- 15. fn_meus_casos concorda com fn_eh_membro (as policies e as funções dizem o mesmo) ---';
  v_lista := '';
  for v_n in 1..4 loop
    perform set_config('request.jwt.claims', json_build_object('sub', (array[ua, ub, uc, un])[v_n], 'role', 'authenticated')::text, true);
    set local role authenticated;
    select string_agg(c.id::text, ' ') into v_err from caso c
     where (fn_eh_membro(c.id)) is distinct from (c.id in (select fn_meus_casos()));
    reset role;
    v_lista := v_lista || coalesce(v_err, '');
  end loop;
  perform teste_assert_0216(v_lista = '', 'para A, B, C e N, em todo caso: fn_eh_membro(c) = (c in fn_meus_casos())', v_lista);
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from fn_meus_casos();
  reset role;
  perform teste_assert_0216(v_n = (select count(*) from caso_membro where usuario_id = ua), 'A, sem ser administrador, tem exatamente os casos de caso_membro', v_n::text);

  raise notice '--- 16. a guarda da migration: administrador vazio + caso sem membro = recusa ---';
  perform set_config('request.jwt.claims', '', true);
  perform fn_administrador_definir('c@0216.teste', false);
  v_err := null;
  begin perform fn_0216_exige_administrador();
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  perform teste_assert_0216(left(v_err, 5) = '55000' and v_err like '%fn_administrador_definir%',
    'sem administrador e com caso órfão a guarda levanta 55000 e manda rodar fn_administrador_definir', v_err);
  begin
    insert into caso_membro (caso_id, usuario_id, por) select id, ua, 'teste' from caso on conflict do nothing;
    insert into caso (nome) values ('0216 — Sonda 0999 — x (fixture da instalação, não é mandato real)');  -- órfã, mas é fixture da sonda
    v_err := null;
    begin perform fn_0216_exige_administrador(); exception when others then v_err := sqlstate; end;
    v_b := v_err is null;
    raise exception 'rollback_0216';
  exception when others then if sqlerrm <> 'rollback_0216' then raise; end if; end;
  perform teste_assert_0216(v_b, 'sem administrador, com todo mandato real tendo membro e só uma fixture da sonda órfã (o replay), a guarda deixa passar');
  perform fn_administrador_definir('c@0216.teste', true);
  v_err := null;
  begin perform fn_0216_exige_administrador(); exception when others then v_err := sqlstate; end;
  perform teste_assert_0216(v_err is null, 'com administrador a guarda deixa passar mesmo com caso órfão');

  raise notice '--- 17. a sonda enxerga a policy que voltou a using (true) ---';
  begin
    alter policy documento_por_mandato on documento using (true) with check (true);
    select count(*) into v_n from fn_instalacao_conferir() where chave = 'mandato_documento_por_mandato' and not presente;
    raise exception 'rollback_0216';
  exception when others then if sqlerrm <> 'rollback_0216' then raise; end if; end;
  perform teste_assert_0216(v_n = 1, 'com documento_por_mandato em using (true) a sonda acusa o requisito (nome igual, regra errada)');
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0216' and not presente;
  perform teste_assert_0216(v_n = 0, 'desfeito, a sonda se cala', v_n::text);

  -- limpeza
  delete from storage.objects where name like '0216a1%' or name like 'lixo0216/%' or name = 'raiz0216.pdf' or name like v_x || '/%' or name like v_y || '/%';
  delete from golden_rodada where nome = '0216 — rodada';
  delete from caso where nome like '0216 — %';
  delete from auth.users where email like '%@0216.teste';
  select count(*) into v_n from caso_membro where usuario_id in (ua, ub, uc, un);
  perform teste_assert_0216(v_n = 0, 'a limpeza levou as pertinências junto (cascata)', v_n::text);
end $$;

drop function teste_infratores_0216(uuid);
drop function teste_infratores_admin_0216();
drop function teste_total_super_0216(text);
drop function teste_semear_0216(uuid, uuid);
drop function teste_n_do_caso_0216(text, uuid);
drop function teste_n_do_caso_super_0216(text, uuid);
drop function teste_conta_0216(text, text);
drop function teste_filtro_0216(text);
drop function teste_catalogos_0216();
drop function teste_tabelas_cliente_0216();
