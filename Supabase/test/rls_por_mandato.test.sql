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
-- não membro recebe null (e um evento de rastro) e NÃO cria o segundo caso, e não cria nem renomeia por insert/update
-- direto para um nome já usado; (7) a guarda da migration recusa administrador vazio com usuário ativo; (8) a sonda
-- enxerga a policy que voltou a using (true), a RLS desligada e o definer que virou invoker; (9) o veredito global do
-- dial não depende de quem dispara (analista com recorte alto NÃO promove), os agregados de /autonomia são iguais para
-- todo leitor, a falha sem caso (caso_id nulo) chega a quem sobe o arquivo, e o dial/catálogos só o administrador escreve.
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
    'pergunta_catalogo', 'golden_rodada', 'golden_criterio', 'estagio_autonomia', 'instalacao_cobertura', 'instalacao_requisito',
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

-- N vereditos de revisão de documento no caso, `p_acertos` deles confirmando (a forma que fn_veredito_producao conta).
create or replace function teste_decisoes_0216(p_caso uuid, p_n int, p_acertos int) returns void language plpgsql as $$
declare i int;
begin
  for i in 1..p_n loop
    insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (p_caso, (case when i <= p_acertos then 'aprovacao' else 'correcao_classificacao' end)::decisao_tipo,
            'analista:t0216', 'veredito de teste 0216',
            jsonb_build_object('documento_id', gen_random_uuid(), 'tipo_de', 'balanco_patrimonial',
                               'tipo_para', case when i <= p_acertos then 'balanco_patrimonial' else 'balancete' end));
  end loop;
end $$;

-- limpeza de rodada anterior (cascata leva caso_membro e o que pende do caso; o rastro é append-only e fica)
delete from storage.objects where name like '0216a1%' or name like 'lixo0216/%' or name = 'raiz0216.pdf';
delete from execucao_falha where caso_id is null and caso_nome like '0216 — %';
delete from golden_rodada where nome like '0216 — %';
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
  v_m2 bigint; v_t text; v_nivel text; v_nivel2 text; v_tipo text; v_j1 jsonb; v_j2 jsonb; v_j3 jsonb;
begin
  raise notice '--- 0. o catálogo da sonda tem os requisitos da 0216 e nenhum está ausente ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0216';
  perform teste_assert_0216(v_n = 125, 'a sonda tem os 125 requisitos da 0216', v_n::text);
  -- `administrador` está VAZIA neste ponto (nada a promoveu ainda): o requisito `primeiro_administrador` é o ÚNICO ausente
  -- (como custo_gravado_pelo_n8n no replay: comportamento que nenhum CI satisfaz) — e é o sinal positivo da regra 7.
  select string_agg(chave, ',' order by chave) into v_lista from fn_instalacao_conferir() where migration = '0216' and not presente;
  perform teste_assert_0216(v_lista = 'primeiro_administrador',
    'com administrador vazia a sonda acusa EXATAMENTE o primeiro_administrador e nenhum outro requisito da 0216', coalesce(v_lista, '<nenhum>'));
  select count(*) into v_n from fn_instalacao_conferir() where presente is null;
  perform teste_assert_0216(v_n = 0, 'nenhum requisito da sonda sai com presente NULL', v_n::text);

  raise notice '--- 1. montagem: A (membro de X), B (membro de Y), C (administrador), N (de nada) ---';
  insert into auth.users (id, email) values (ua, 'a@0216.teste'), (ub, 'b@0216.teste'), (uc, 'c@0216.teste'), (un, 'n@0216.teste');
  perform fn_administrador_definir('c@0216.teste', true);
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0216' and not presente;
  perform teste_assert_0216(v_n = 0, 'com um administrador, nenhum requisito da 0216 está ausente (o sinal some quando o dono age)',
    (select string_agg(chave || ': ' || detalhe, ' | ') from fn_instalacao_conferir() where migration = '0216' and not presente));
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

  raise notice '--- 3b. a sonda exige RLS LIGADA em TODA tabela de cliente (e no bucket e nos catálogos de escrita restrita) ---';
  select string_agg(t, ' ') into v_lista from teste_tabelas_cliente_0216() t
   where not exists (select 1 from instalacao_requisito q where q.tipo = 'rls' and q.objeto = t);
  perform teste_assert_0216(v_lista is null, 'toda tabela de cliente do catálogo tem requisito rls na sonda (tabela nova sem ele reprova)', v_lista);
  v_lista := '';
  for v_t in select t from teste_tabelas_cliente_0216() t
             union all select unnest(array['storage.objects', 'golden_criterio', 'estagio_autonomia', 'premissa_catalogo', 'golden_rodada'])
  loop
    v_err := null;
    begin
      execute format('alter table %s disable row level security', case when v_t like '%.%' then v_t else 'public.' || v_t end);
      select string_agg(chave, ',' order by chave) into v_err from fn_instalacao_conferir() where tipo = 'rls' and not presente;
      raise exception 'rollback_0216';
    exception when others then if sqlerrm <> 'rollback_0216' then raise; end if; end;
    if v_err is distinct from 'rls_' || replace(v_t, '.', '_') then v_lista := v_lista || v_t || '(' || coalesce(v_err, '-') || ') '; end if;
  end loop;
  perform teste_assert_0216(v_lista = '', 'desligar a RLS de QUALQUER tabela de cliente (e do bucket e dos catálogos de escrita restrita) a sonda acusa o requisito dela, e só ele', v_lista);
  -- e é a brecha: com o GRANT que o default privilege dá, a RLS desligada abre o mandato alheio a quem não é membro
  begin
    alter table pendencia disable row level security;
    perform set_config('request.jwt.claims', json_build_object('sub', un, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select count(*) into v_n from pendencia;
    reset role;
    raise exception 'rollback_0216';
  exception when others then if sqlerrm <> 'rollback_0216' then raise; end if; end;
  perform teste_assert_0216(v_n > 0, 'controle: com a RLS de pendencia desligada, N (que não é membro de nada) lê pendência alheia — é isto que a sonda rls acusa', v_n::text);

  raise notice '--- 3c. dial e catálogos: leitura livre, escrita só do administrador ---';
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_lista := '';
  select count(*) into v_n from golden_criterio;
  select count(*) into v_m from estagio_autonomia;
  select count(*) into v_ev from premissa_catalogo;
  select count(*) into v_casos from golden_rodada;
  if v_n = 0 or v_m = 0 or v_ev = 0 or v_casos = 0 then v_lista := 'leitura vazia ' || v_n || '/' || v_m || '/' || v_ev || '/' || v_casos; end if;
  update golden_criterio set concordancia_minima = 0;                               get diagnostics v_n = row_count;
  delete from golden_criterio;                                                      get diagnostics v_m = row_count;
  update estagio_autonomia set teto = 'N3' where estagio = 'classificacao_contabil'; get diagnostics v_ev = row_count;
  update premissa_catalogo set nome = nome;                                         get diagnostics v_casos = row_count;
  v_err := null;
  begin insert into golden_rodada (nome, taxonomia_versao) values ('0216 — invasora', 1);
  exception when others then v_err := sqlstate; end;
  update golden_rodada set nome = nome;                                             get diagnostics v_m2 = row_count;
  reset role;
  perform teste_assert_0216(v_lista = '', 'A (qualquer usuário logado) LÊ golden_criterio, estagio_autonomia, premissa_catalogo e golden_rodada', v_lista);
  perform teste_assert_0216(v_n = 0 and v_m = 0 and v_ev = 0 and v_casos = 0 and v_err = '42501' and v_m2 = 0,
    'e NÃO escreve neles: update/delete em golden_criterio, update do teto, update em premissa_catalogo e golden_rodada alcançam 0 linhas e o insert leva 42501',
    v_n || '/' || v_m || '/' || v_ev || '/' || v_casos || '/' || coalesce(v_err, '-') || '/' || v_m2);
  perform teste_assert_0216((select concordancia_minima from golden_criterio where estagio = 'classificacao_doc_checklist') > 0
    and (select teto from estagio_autonomia where estagio = 'classificacao_contabil') = 'N1'
    and not exists (select 1 from golden_rodada where nome = '0216 — invasora'),
    'e nada mudou: o limiar continua, o teto de classificacao_contabil continua N1 (doutrina), nenhuma rodada nasceu');
  -- O USO LEGÍTIMO: as funções que abrem e congelam rodada (0130, INVOKER, EXECUTE para authenticated) são a única escrita
  -- em golden_rodada que existe (grep portal/src e N8N: ninguém as chama; o golden set é conduzido pelo dono). Como
  -- administrador elas seguem funcionando; como analista levam 42501 da RLS — não "abrem" uma rodada que não nasceu.
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_err := null;
  begin perform fn_golden_abrir_rodada('0216 — rodada de A', 'a@0216.teste');
  exception when others then v_err := sqlstate; end;
  reset role;
  perform teste_assert_0216(v_err = '42501' and not exists (select 1 from golden_rodada where nome = '0216 — rodada de A'),
    'A (analista) chamando fn_golden_abrir_rodada leva 42501 e nenhuma rodada nasce', v_err);
  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_res := fn_golden_abrir_rodada('0216 — rodada de C', 'c@0216.teste');
  reset role;
  perform teste_assert_0216(exists (select 1 from golden_rodada where nome = '0216 — rodada de C'),
    'C (administrador) abre rodada pela função normalmente (o uso legítimo não quebrou)', v_res::text);
  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  update golden_criterio set n_minimo_veredito = n_minimo_veredito;                   get diagnostics v_n = row_count;
  update estagio_autonomia set atualizado_por = atualizado_por where estagio = 'classificacao_contabil'; get diagnostics v_m = row_count;
  reset role;
  perform teste_assert_0216(v_n >= 4 and v_m = 1, 'C, administrador, ESCREVE nos catálogos (golden_criterio e estagio_autonomia): o uso legítimo continua', v_n || '/' || v_m);
  -- fn_mudar_dial é invoker: quem não é administrador NÃO "muda" o dial (a RLS recusa o UPDATE) — e a função não pode
  -- gravar o evento de mudança nem devolver sucesso nesse caso.
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_err := null;
  begin perform fn_mudar_dial('classificacao_contabil', 'N0', 'a@0216.teste', 'tentativa de A');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  reset role;
  perform teste_assert_0216(left(v_err, 5) = '42501' and v_err like '%só o administrador altera%'
    and not exists (select 1 from evento_auditoria where acao = 'mudanca_dial' and ator = 'a@0216.teste'),
    'A chamando fn_mudar_dial leva 42501 e NENHUM evento mudanca_dial é gravado (a trilha não afirma o que não aconteceu)', v_err);
  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_res := fn_mudar_dial('classificacao_contabil', 'N0', 'c@0216.teste', 'reafirmação do administrador');
  reset role;
  perform teste_assert_0216(coalesce((v_res->>'recusado')::boolean, false) = false and exists (select 1 from evento_auditoria where acao = 'mudanca_dial' and ator = 'c@0216.teste'),
    'C, administrador, chama fn_mudar_dial normalmente (e a trilha registra)', v_res::text);

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
  v_err := null; v_novo := gen_random_uuid();
  begin v_novo := fn_upsert_caso('0216 — Y', 'portal:navegador');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  reset role;
  select count(*) into v_n from caso where nome = '0216 — Y';
  -- A RECUSA NÃO É EXCEÇÃO: uma exceção desfaria a transação e, com ela, o evento que registra a tentativa.
  perform teste_assert_0216(v_err is null and v_novo is null,
    'A chamando com o nome de Y NÃO recebe id (null) e não leva exceção: a recusa não pode desfazer o próprio rastro', coalesce(v_err, v_novo::text, 'null'));
  perform teste_assert_0216(v_n = 1 and v_casos = 1, 'e NÃO se criou caso duplicado: continua UM caso chamado Y', v_casos || ' → ' || v_n);
  select count(*) into v_n from evento_auditoria
   where acao = 'caso_acesso_recusado' and ator = 'usuario:' || ua and entidade_ref = 'caso_nome:0216 — Y' and caso_id is null;
  perform teste_assert_0216(v_n = 1, 'a recusa deixou UM evento caso_acesso_recusado, com o ator (usuario:<uuid>) e o nome pedido', v_n::text);
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from evento_auditoria where acao = 'caso_acesso_recusado';
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_m from evento_auditoria where acao = 'caso_acesso_recusado' and ator = 'usuario:' || ua;
  reset role;
  perform teste_assert_0216(v_n = 0 and v_m = 1, 'o rastro da recusa é do administrador: A não o lê, C lê', v_n || '/' || v_m);
  -- O ORÁCULO DE NOMES: fn_caso_nome_existe não é executável pelo authenticated (em M&A o nome do alvo é informação privilegiada)
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_err := null;
  begin perform fn_caso_nome_existe('0216 — Y');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  reset role;
  perform teste_assert_0216(left(v_err, 5) = '42501' and v_err like '%permission denied for function fn_caso_nome_existe%',
    'A não consegue perguntar se um nome de mandato existe (fn_caso_nome_existe sem EXECUTE para o authenticated)', v_err);
  -- e não resta, com outro nome, a pergunta que devolvia o ID do mandato (a primeira forma do oráculo, fn_caso_id_do_nome)
  perform teste_assert_0216(to_regproc('fn_caso_id_do_nome') is null
    or not (has_function_privilege('authenticated', to_regproc('fn_caso_id_do_nome')::oid, 'execute')
         or has_function_privilege('anon', to_regproc('fn_caso_id_do_nome')::oid, 'execute')),
    'nenhuma função devolve o id de um mandato pelo nome ao authenticated/anon (fn_caso_id_do_nome não existe ou não executa)');
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

  raise notice '--- 16. a guarda da migration: administrador vazia + usuário ativo = recusa ---';
  -- A guarda anterior olhava "caso órfão" e não protegia nada na ordem normal (a 0215 dá todo caso a todo usuário ativo:
  -- zero órfãos no dia). O que a 0216 estraga é "ninguém atribui nem vê": a conta é de USUÁRIOS ATIVOS.
  perform set_config('request.jwt.claims', '', true);
  perform fn_administrador_definir('c@0216.teste', false);
  select count(*) into v_n from fn_usuarios_ativos();
  v_err := null;
  begin perform fn_0216_exige_administrador();
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0216(v_n = 0 and v_err is null,
    'sem administrador e SEM usuário ativo (o replay: usuários só de teste, nenhum confirmado) a guarda deixa passar', v_n || ' ativos, ' || coalesce(v_err, 'ok'));
  update auth.users set email_confirmed_at = now() where id = ua;
  v_err := null;
  begin perform fn_0216_exige_administrador();
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  perform teste_assert_0216(left(v_err, 5) = '55000' and v_err like '%fn_administrador_definir%',
    'sem administrador e COM um usuário ativo a guarda levanta 55000 e manda rodar fn_administrador_definir', v_err);
  -- mesmo com todo caso tendo membro (a ordem normal da 0215), a guarda recusa: não depende de órfão
  insert into caso_membro (caso_id, usuario_id, por) select id, ua, 'teste16' from caso on conflict do nothing;
  v_err := null;
  begin perform fn_0216_exige_administrador();
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0216(v_err = '55000', 'e recusa mesmo sem NENHUM caso órfão (a ordem normal: a 0215 deu todo caso a todo ativo)', v_err);
  update auth.users set banned_until = now() + interval '1 day' where id = ua;
  v_err := null;
  begin perform fn_0216_exige_administrador(); exception when others then v_err := sqlstate; end;
  perform teste_assert_0216(v_err is null, 'usuário banido não conta como ativo: a guarda deixa passar', v_err);
  update auth.users set banned_until = null where id = ua;
  perform fn_administrador_definir('c@0216.teste', true);
  v_err := null;
  begin perform fn_0216_exige_administrador(); exception when others then v_err := sqlstate; end;
  perform teste_assert_0216(v_err is null, 'com administrador a guarda deixa passar mesmo com usuário ativo');
  update auth.users set email_confirmed_at = null where id = ua;
  delete from caso_membro where por = 'teste16';      -- A volta a ser membro só do que era (os passos seguintes dependem disso)

  raise notice '--- 17. a sonda enxerga a policy que voltou a using (true) ---';
  begin
    alter policy documento_por_mandato on documento using (true) with check (true);
    select count(*) into v_n from fn_instalacao_conferir() where chave = 'mandato_documento_por_mandato' and not presente;
    raise exception 'rollback_0216';
  exception when others then if sqlerrm <> 'rollback_0216' then raise; end if; end;
  perform teste_assert_0216(v_n = 1, 'com documento_por_mandato em using (true) a sonda acusa o requisito (nome igual, regra errada)');
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0216' and not presente;
  perform teste_assert_0216(v_n = 0, 'desfeito, a sonda se cala', v_n::text);
  -- o ALTER FUNCTION ... SECURITY DEFINER não muda uma letra do corpo: só o tipo `definer` o vê
  begin
    alter function fn_dial_auto_promover(text) security invoker;
    select count(*) into v_n from fn_instalacao_conferir() where chave = 'definer_fn_dial_auto_promover' and not presente;
    raise exception 'rollback_0216';
  exception when others then if sqlerrm <> 'rollback_0216' then raise; end if; end;
  perform teste_assert_0216(v_n = 1, 'fn_dial_auto_promover de volta a INVOKER: a sonda acusa o requisito definer');
  begin
    alter function fn_veredito_producao(text, uuid) reset search_path;
    select count(*) into v_n from fn_instalacao_conferir() where chave = 'definer_fn_veredito_producao' and not presente;
    raise exception 'rollback_0216';
  exception when others then if sqlerrm <> 'rollback_0216' then raise; end if; end;
  perform teste_assert_0216(v_n = 1, 'fn_veredito_producao definer SEM search_path fixo: a sonda acusa (definer sem search_path é sequestrável)');
  begin
    alter function fn_mudar_dial(text, nivel_autonomia, text, text, numeric, uuid, text, boolean) security definer;
    select count(*) into v_n from fn_instalacao_conferir() where chave = 'invoker_fn_mudar_dial' and not presente;
    raise exception 'rollback_0216';
  exception when others then if sqlerrm <> 'rollback_0216' then raise; end if; end;
  perform teste_assert_0216(v_n = 1, 'fn_mudar_dial virando SECURITY DEFINER (qualquer usuário mudaria o dial): a sonda acusa o requisito');

  raise notice '--- 18. a promoção automática do dial NÃO depende de quem dispara (veredito GLOBAL, não o recorte do analista) ---';
  -- ARRANJO. Tudo dentro de um sub-bloco que se desfaz (rollback_0216): apaga os vereditos de outros testes para o
  -- número ser determinístico e não deixa rastro. Y (de B) tem 40 correções; X (de A) tem 30 confirmações a 100%.
  -- O RECORTE de A (só X) alcança o critério (n 30, concordância 1,00); o GLOBAL (70 vereditos, 30 certos) não.
  -- Antes da correção o veredito era calculado como A (invoker + RLS por mandato) e o gatilho de A promovia o dial de todos.
  -- anon (a chave pública) NÃO executa as funções que esta migration tornou SECURITY DEFINER: definer executável por PUBLIC/anon
  -- é o caminho clássico de escalada (e a guarda de p_caso_id deixa passar quem não tem identidade)
  v_lista := '';
  perform set_config('request.jwt.claims', '', true);
  set local role anon;
  begin perform fn_dial_auto_promover();
  exception when others then v_lista := v_lista || case when sqlerrm like '%permission denied for function fn_dial_auto_promover%' then '' else 'dial:' || sqlerrm || ' ' end; end;
  begin perform fn_veredito_producao('classificacao_doc_checklist', v_x);
  exception when others then v_lista := v_lista || case when sqlerrm like '%permission denied for function fn_veredito_producao%' then '' else 'veredito:' || sqlerrm || ' ' end; end;
  begin perform fn_falhas_abertas('0216 — X', now() - interval '1 hour');
  exception when others then v_lista := v_lista || case when sqlerrm like '%permission denied for function fn_falhas_abertas%' then '' else 'falhas:' || sqlerrm || ' ' end; end;
  begin perform fn_upsert_caso('0216 — anon');
  exception when others then v_lista := v_lista || case when sqlerrm like '%permission denied for function fn_upsert_caso%' then '' else 'upsert:' || sqlerrm || ' ' end; end;
  reset role;
  perform teste_assert_0216(v_lista = '' and not exists (select 1 from caso where nome = '0216 — anon'),
    'anon leva "permission denied for function" em fn_dial_auto_promover, fn_veredito_producao, fn_falhas_abertas e fn_upsert_caso (nenhum definer executável pela chave pública)', v_lista);
  select nivel_atual::text into v_t from estagio_autonomia where estagio = 'classificacao_doc_checklist';
  begin
    update estagio_autonomia set nivel_atual = 'N1', base_do_nivel = 'nao_se_aplica', auto_promocao = true,
           medicao_em = null, medicao_resumo = null where estagio = 'classificacao_doc_checklist';
    delete from decisao where payload ? 'tipo_para';
    set session_replication_role = replica;               -- sem o gatilho: semeia sem disparar a promoção
    perform teste_decisoes_0216(v_x, 30, 30);
    perform teste_decisoes_0216(v_y, 40, 0);
    set session_replication_role = origin;
    v_j1 := fn_veredito_producao('classificacao_doc_checklist');               -- o global, como o dono
    v_j2 := fn_veredito_producao('classificacao_doc_checklist', v_x);           -- o recorte de X, como o dono
    -- o MESMO global para quem não é dono: A (membro de X), B (de Y) e N (de nada)
    perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_res := fn_veredito_producao('classificacao_doc_checklist');
    v_err := null;
    begin perform fn_veredito_producao('classificacao_doc_checklist', v_y);
    exception when others then v_err := sqlstate; end;
    reset role;
    perform set_config('request.jwt.claims', json_build_object('sub', un, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_res2 := fn_veredito_producao('classificacao_doc_checklist');
    reset role;
    v_j3 := jsonb_build_object('a_n', (v_res->>'n')::int, 'n_n', (v_res2->>'n')::int, 'g_n', (v_j1->>'n')::int,
                               'g_suf', v_j1->'suficiente', 'x_suf', v_j2->'suficiente', 'x_n', (v_j2->>'n')::int,
                               'a_suf', v_res->'suficiente', 'err', v_err);
    -- a nota de A em X, depois de o recorte dele bastar e o global não
    perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
    set local role authenticated;
    perform teste_decisoes_0216(v_x, 1, 1);
    reset role;
    select nivel_atual into v_nivel from estagio_autonomia where estagio = 'classificacao_doc_checklist';
    -- CONTROLE POSITIVO: com o global suficiente (mais 800 confirmações em Y) a mesma nota de A PROMOVE pelo caminho
    -- novo (definer) — sem isto "não promoveu" poderia ser "a promoção está quebrada".
    perform set_config('request.jwt.claims', '', true);
    set session_replication_role = replica;
    perform teste_decisoes_0216(v_y, 800, 800);
    set session_replication_role = origin;
    v_tipo := (fn_veredito_producao('classificacao_doc_checklist')->>'suficiente');
    perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
    set local role authenticated;
    perform teste_decisoes_0216(v_x, 1, 1);
    reset role;
    select nivel_atual into v_nivel2 from estagio_autonomia where estagio = 'classificacao_doc_checklist';
    raise exception 'rollback_0216';
  exception when others then
    set session_replication_role = origin;
    if sqlerrm <> 'rollback_0216' then raise; end if;
  end;
  perform set_config('request.jwt.claims', '', true);
  perform teste_assert_0216((v_j3->>'x_suf')::boolean and (v_j3->>'x_n')::int = 30 and not (v_j3->>'g_suf')::boolean and (v_j3->>'g_n')::int = 70,
    'arranjo não vazio: o RECORTE de X basta (30 a 100%) e o GLOBAL (70 vereditos, 30 certos) não', v_j3::text);
  perform teste_assert_0216((v_j3->>'a_n')::int = 70 and (v_j3->>'n_n')::int = 70 and not (v_j3->>'a_suf')::boolean,
    'A (membro de X) e N (de nada) leem o MESMO veredito global que o dono: 70 vereditos, não o recorte', v_j3::text);
  perform teste_assert_0216(v_j3->>'err' = '42501', 'mas A não pergunta o veredito do mandato Y por p_caso_id (42501): o definer não abre o número de outro mandato', v_j3::text);
  perform teste_assert_0216(v_nivel = 'N1',
    'o analista A, com um recorte de concordância alta (30 a 100%), NÃO promove o dial quando a global não basta', v_nivel);
  perform teste_assert_0216(v_tipo = 'true' and v_nivel2 = 'N2',
    'controle positivo: com o global suficiente a mesma nota de A promove o estágio a N2 (a promoção funciona, pelo caminho definer)', v_tipo || '/' || coalesce(v_nivel2, '-'));
  perform teste_assert_0216((select nivel_atual::text from estagio_autonomia where estagio = 'classificacao_doc_checklist') = v_t,
    'o sub-bloco se desfez: o dial voltou ao nível que tinha antes do arranjo', v_t);

  raise notice '--- 19. /autonomia: os agregados globais são IGUAIS para todo leitor (só números) ---';
  perform set_config('request.jwt.claims', '', true);
  begin
    select codigo into v_tipo from taxonomia_tipo_documento where obrigatoriedade = 'obrigatorio' and ativo order by codigo limit 1;
    update golden_rotulo set tipo_correto = v_tipo where rodada_id = v_rod;
    v_j1 := (select coalesce(jsonb_agg(to_jsonb(c) order by c.tipo), '[]') from fn_golden_cobertura(v_rod) c);
    v_j2 := fn_classe_contabil_concordancia();
    perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_res  := (select coalesce(jsonb_agg(to_jsonb(c) order by c.tipo), '[]') from fn_golden_cobertura(v_rod) c);
    v_res2 := fn_classe_contabil_concordancia();
    v_j3   := fn_classe_contabil_concordancia(v_x);
    v_err := null;
    reset role;
    perform set_config('request.jwt.claims', json_build_object('sub', ub, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_n := (fn_classe_contabil_concordancia(v_x)->>'com_veredito_humano')::int;      -- B pergunta o mandato de A
    reset role;
    perform teste_assert_0216((select sum((e->>'n_documentos')::int) from jsonb_array_elements(v_j1) e) >= 2,
      'arranjo não vazio: a cobertura do golden set conta os documentos dos DOIS mandatos (X e Y)', v_j1::text);
    perform teste_assert_0216(v_res = v_j1, 'A lê a MESMA cobertura do golden set que o dono (não só os documentos de X)', v_res::text || ' ≠ ' || v_j1::text);
    perform teste_assert_0216((v_j2->>'com_veredito_humano')::int >= 2 and v_res2 = v_j2,
      'A lê a MESMA concordância da classe contábil que o dono (global), não a do recorte dele', (v_res2->>'com_veredito_humano') || ' ≠ ' || (v_j2->>'com_veredito_humano'));
    perform teste_assert_0216((v_j3->>'com_veredito_humano')::int = 1 and v_n = 0,
      'com p_caso_id: A conta o próprio mandato (1) e B perguntando o mandato de A não conta nada (0)', (v_j3->>'com_veredito_humano') || '/' || v_n);
    raise exception 'rollback_0216';
  exception when others then if sqlerrm <> 'rollback_0216' then raise; end if; end;
  perform set_config('request.jwt.claims', '', true);

  raise notice '--- 20. falha de execução SEM caso (caso_id nulo): quem sobe o arquivo a lê pelo nome ---';
  insert into execucao_falha (caso_id, caso_nome, etapa, mensagem) values (null, '0216 — Ainda Não Existe', 'extracao', 'falhou antes de o caso existir');
  perform set_config('request.jwt.claims', json_build_object('sub', un, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from fn_falhas_abertas('0216 — ainda não existe ', now() - interval '1 hour');
  select count(*) into v_m from execucao_falha where caso_id is null;
  reset role;
  perform teste_assert_0216(v_n = 1, 'N (sem mandato nenhum) recebe a falha de caso_id NULO pelo nome (o /api/intake/status sai do "aguarde" eterno)', v_n::text);
  perform teste_assert_0216(v_m = 0, 'mas não LÊ a falha sem caso pela tabela (só o administrador)', v_m::text);
  perform set_config('request.jwt.claims', json_build_object('sub', uc, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from execucao_falha where caso_id is null and caso_nome = '0216 — Ainda Não Existe';
  reset role;
  perform teste_assert_0216(v_n = 1, 'o administrador lê a falha sem caso pela tabela (NULL in (...) não a esconde dele)', v_n::text);
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from fn_falhas_abertas('0216 — X', now() - interval '1 hour');
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', ub, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_m from fn_falhas_abertas('0216 — X', now() - interval '1 hour');
  reset role;
  perform teste_assert_0216(v_n >= 1 and v_m = 0, 'a falha de um mandato que existe só vai ao membro: A (de X) a recebe, B não', v_n || '/' || v_m);

  raise notice '--- 21. o desvio de ingestão: o não membro não cria nem renomeia para um nome já usado ---';
  perform set_config('request.jwt.claims', json_build_object('sub', ua, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_lista := '';
  begin insert into caso (nome) values ('0216 — Y');
  exception when others then v_lista := v_lista || 'insert:' || sqlstate || ' '; end;
  begin update caso set nome = '0216 — Y' where id = v_x;
  exception when others then v_lista := v_lista || 'update:' || sqlstate || ' '; end;
  update caso set nome = '0216 — X' where id = v_x;                      get diagnostics v_n = row_count;     -- mesmo nome: não conflita consigo
  update caso set nome = '0216 — X renomeado' where id = v_x;            get diagnostics v_m = row_count;
  insert into caso (nome) values ('0216 — nome livre de A');
  reset role;
  perform teste_assert_0216(v_lista = 'insert:23505 update:23505 ',
    'A não insere caso com o nome de Y nem renomeia o PRÓPRIO caso para o nome de Y (23505), sem índice unique', v_lista);
  select count(*) into v_ev from caso where nome = '0216 — Y';
  perform teste_assert_0216(v_ev = 1 and (select nome from caso where id = v_x) = '0216 — X renomeado' and v_n = 1 and v_m = 1,
    'e nada mudou: continua UM caso chamado Y; renomear para o mesmo nome e para um nome livre funciona', v_ev || '/' || v_n || '/' || v_m);
  update caso set nome = '0216 — X' where id = v_x;
  perform teste_assert_0216(exists (select 1 from caso c join caso_membro m on m.caso_id = c.id where c.nome = '0216 — nome livre de A' and m.usuario_id = ua),
    'e o nome livre vira mandato de A (gatilho do criador)');
  -- sem identidade (n8n, dono, testes de superusuário) o gatilho não age: duplicar por SQL continua possível, documentado
  perform set_config('request.jwt.claims', '', true);
  insert into caso (nome) values ('0216 — Y');
  select count(*) into v_ev from caso where nome = '0216 — Y';
  delete from caso where nome = '0216 — Y' and id <> v_y;
  perform teste_assert_0216(v_ev = 2, 'sem identidade (superusuário/n8n) o gatilho não age: a duplicata por SQL entra (decisão do dono pendente: sem unique)', v_ev::text);

  -- limpeza
  delete from storage.objects where name like '0216a1%' or name like 'lixo0216/%' or name = 'raiz0216.pdf' or name like v_x || '/%' or name like v_y || '/%';
  delete from execucao_falha where caso_id is null and caso_nome like '0216 — %';
  delete from golden_rodada where nome like '0216 — %';
  delete from caso where nome like '0216 — %';
  delete from auth.users where email like '%@0216.teste';
  select count(*) into v_n from caso_membro where usuario_id in (ua, ub, uc, un);
  perform teste_assert_0216(v_n = 0, 'a limpeza levou as pertinências junto (cascata)', v_n::text);
end $$;

drop function teste_decisoes_0216(uuid, int, int);
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
