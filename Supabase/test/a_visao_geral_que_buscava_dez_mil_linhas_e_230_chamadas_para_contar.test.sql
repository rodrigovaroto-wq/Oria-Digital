-- Testes da 0276: fn_linhas_por_versao e fn_algum_documento_serve_como (as leituras em lote da visão geral do mandato).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO PROVA (comportamento, regra 3):
--   * a contagem em lote bate com `count(*)` direto por versão, inclusive numa versão com 2.500 linhas (> 1.000: o teto silencioso do
--     PostgREST que obrigava o portal a paginar; a função não tem teto), e versão sem linha não vem (ausência = 0 para quem lê);
--   * fn_algum_documento_serve_como concorda com o bool_or das chamadas individuais a fn_documento_serve_como (0157), num caso que serve
--     (pelo rótulo e pela exceção estrutural do COMBINADO) e num que não serve, e dá false para array vazio/nulo;
--   * o ISOLAMENTO POR MANDATO, COMO authenticated com JWT (a lição .claude/memory/rls-so-select-passa-no-superusuario.md): quem não tem
--     o mandato recebe zero linhas e false, e o anon não executa.
-- Regra 4: nada de bug de produção é reproduzido aqui (o defeito é de desempenho do portal; o número 13,4 s/10,2 s está no cabeçalho da
-- migration). As fixtures são montadas no formato de produção (fn_registrar_documento + linhas de campo_extraido).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número reprovado por correção desligada está no cabeçalho da migration 0276. `ct76.medindo = on`
-- (PGOPTIONS='-c ct76.medindo=on') vira `raise warning` e CONTA (ct76.execucoes / ct76.falhas); sem a variável, o assert é `raise exception`.

\set ON_ERROR_STOP on

create or replace function teste_assert_0276(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('ct76.execucoes', (coalesce(nullif(current_setting('ct76.execucoes', true), ''), '0')::int + 1)::text, false);
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  elsif current_setting('ct76.medindo', true) = 'on' then
    perform set_config('ct76.falhas', (coalesce(nullif(current_setting('ct76.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- Executa a expressão COMO o papel (authenticated com o JWT do usuário; NULL = sem sub) e volta ao superusuário com o JWT do Sócio
-- padrão do run.sh. Devolve 'ok|<resultado>' ou '<sqlstate>|<mensagem>'. SQL dinâmico (ver 0274).
create or replace function teste_exec_0276(p_uid uuid, p_papel text, p_expr text)
returns text language plpgsql as $$
declare v_r text; v_out text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then jsonb_build_object('role', p_papel)::text
                     else jsonb_build_object('sub', p_uid, 'role', p_papel)::text end, true);
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

-- Como `teste_exec_0276`, para a contagem por versão: devolve 'versao=linhas;...' em ordem estável (vazio = nenhuma linha).
create or replace function teste_lote_0276(p_uid uuid, p_papel text, p_versoes uuid[]) returns text
language sql as $$
  select regexp_replace(teste_exec_0276(p_uid, p_papel, format(
    $f$(select coalesce(string_agg(documento_versao_id || '=' || linhas, ';' order by documento_versao_id), '') from fn_linhas_por_versao(%L::uuid[]))$f$,
    p_versoes)), '^ok\|', '') $$;

delete from caso where nome like '0276 —%';
delete from auth.users where id in ('00000000-0000-0000-0000-00000276b001', '00000000-0000-0000-0000-00000276b002',
  '00000000-0000-0000-0000-00000276b003', '00000000-0000-0000-0000-00000276b004');

do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000276b001';
  u_ana   uuid := '00000000-0000-0000-0000-00000276b002';   -- Analista alocada em A
  u_xan   uuid := '00000000-0000-0000-0000-00000276b003';   -- Analista alocado só em B
  u_nil   uuid := '00000000-0000-0000-0000-00000276b004';   -- SEM papel
  v_a uuid; v_b uuid;
  r jsonb; v_t text;
  vg uuid; vp uuid; vz uuid; vb uuid;              -- versões: grande (2.500 linhas), pequena (3), sem linha, do mandato B (4)
  d_comb uuid; d_unico uuid; d_rot uuid; d_b uuid; -- documentos: BALANCO com 2 empresas (serve COMBINADO), BALANCO com 1 (não serve), COMBINADO pelo rótulo, do mandato B
  v_ind boolean; v_lote boolean; v_n int;
begin
  insert into auth.users (id, email) values (u_socio, 'socio@0276.local'), (u_ana, 'ana@0276.local'), (u_xan, 'xan@0276.local'), (u_nil, 'nil@0276.local');
  perform fn_definir_papel(u_socio, 'socio', 'teste 0276');
  perform fn_definir_papel(u_ana, 'analista');
  perform fn_definir_papel(u_xan, 'analista');
  v_a := fn_upsert_caso('0276 — mandato A');
  v_b := fn_upsert_caso('0276 — mandato B');
  perform fn_alocar(v_a, u_ana);
  perform fn_alocar(v_b, u_xan);

  -- Documentos e versões (formato de produção).
  r := fn_registrar_documento(v_a, 'Alfa 0276 Ltda', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage', '0276/grande.pdf', 'grande.pdf', true, 'HASH-0276-1', 'ok');
  vg := (r ->> 'documento_versao_id')::uuid; d_comb := (r ->> 'documento_id')::uuid;
  r := fn_registrar_documento(v_a, 'Bravo 0276 Ltda', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage', '0276/pequena.pdf', 'pequena.pdf', true, 'HASH-0276-2', 'ok');
  vp := (r ->> 'documento_versao_id')::uuid; d_unico := (r ->> 'documento_id')::uuid;
  r := fn_registrar_documento(v_a, 'Charlie 0276 Ltda', 'anual', '2025', 'COMBINADO', 0.97, 'nome_arquivo', 'supabase_storage', '0276/vazia.pdf', 'vazia.pdf', true, 'HASH-0276-3', 'ok');
  vz := (r ->> 'documento_versao_id')::uuid; d_rot := (r ->> 'documento_id')::uuid;
  r := fn_registrar_documento(v_b, 'Delta 0276 Ltda', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage', '0276/b.pdf', 'b.pdf', true, 'HASH-0276-4', 'ok');
  vb := (r ->> 'documento_versao_id')::uuid; d_b := (r ->> 'documento_id')::uuid;

  -- 2.500 linhas na versão grande, 2 empresas com valor (serve COMBINADO); 3 na pequena, 1 empresa só (não serve); 4 no mandato B, 2 empresas.
  insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, entidade_coluna)
    select vg, 'conta ' || g, g, 'unidade', case when g % 2 = 0 then 'EMPRESA UM' else 'EMPRESA DOIS' end from generate_series(1, 2500) g;
  insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, entidade_coluna)
    select vp, 'conta ' || g, g, 'unidade', 'EMPRESA UNICA' from generate_series(1, 3) g;
  insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, entidade_coluna)
    select vb, 'conta ' || g, g, 'unidade', case when g % 2 = 0 then 'EMPRESA UM' else 'EMPRESA DOIS' end from generate_series(1, 4) g;

  -- ---------------------------------------------------------------- 1. A CONTAGEM BATE COM count(*) DIRETO, SEM TETO
  raise notice '--- 1. fn_linhas_por_versao: a contagem em lote bate com count(*) direto, sem teto ---';
  perform teste_assert_0276((select count(*) from campo_extraido where documento_versao_id = vg) = 2500, 'fixture: a versão grande tem 2.500 linhas (> 1.000, o teto do PostgREST)', null);
  perform teste_assert_0276(teste_lote_0276(u_socio, 'authenticated', array[vg]) = vg || '=2500',
    'a versão com 2.500 linhas devolve 2.500, não 1.000 (a função não tem teto)', teste_lote_0276(u_socio, 'authenticated', array[vg]));
  perform teste_assert_0276(teste_lote_0276(u_socio, 'authenticated', array[vp]) = vp || '=3', 'a versão com 3 linhas devolve 3', null);
  perform teste_assert_0276(teste_lote_0276(u_socio, 'authenticated', array[vz]) = '', 'versão sem nenhuma linha NÃO vem (ausência = 0 para quem lê)', null);
  v_t := teste_lote_0276(u_socio, 'authenticated', array[vg, vp, vz]);
  perform teste_assert_0276(v_t = (select string_agg(x.v || '=' || x.n, ';' order by x.v) from
                                     (select documento_versao_id v, count(*) n from campo_extraido where documento_versao_id in (vg, vp, vz) group by 1) x),
    'três versões numa só ida: o resultado é exatamente o count(*) direto agrupado', v_t);
  perform teste_assert_0276(teste_lote_0276(u_socio, 'authenticated', array[vg, vg]) = vg || '=2500', 'versão repetida no array não duplica a contagem', null);
  perform teste_assert_0276(teste_lote_0276(u_socio, 'authenticated', array[]::uuid[]) = '', 'array vazio devolve zero linhas', null);
  perform teste_assert_0276(teste_lote_0276(u_socio, 'authenticated', null) = '', 'array nulo devolve zero linhas (e não erro)', null);

  -- ---------------------------------------------------------------- 2. O ISOLAMENTO POR MANDATO (RLS de quem chama)
  raise notice '--- 2. isolamento por mandato, COMO authenticated ---';
  perform teste_assert_0276(teste_lote_0276(u_ana, 'authenticated', array[vg, vp, vb]) = (select string_agg(x.v || '=' || x.n, ';' order by x.v) from
                              (select vg v, 2500 n union all select vp, 3) x),
    'a Analista de A conta as versões de A e NÃO a de B (mesma chamada, mandato alheio some)', teste_lote_0276(u_ana, 'authenticated', array[vg, vp, vb]));
  perform teste_assert_0276(teste_lote_0276(u_xan, 'authenticated', array[vg, vp]) = '',
    'a Analista de B pedindo só versões de A recebe zero linhas (não obtém contagem de outro mandato)', teste_lote_0276(u_xan, 'authenticated', array[vg, vp]));
  perform teste_assert_0276(teste_lote_0276(u_xan, 'authenticated', array[vb]) = vb || '=4', 'e conta a do próprio mandato', null);
  perform teste_assert_0276(teste_lote_0276(u_nil, 'authenticated', array[vg, vb]) = '', 'quem não tem papel não conta nada', null);
  perform teste_assert_0276(teste_lote_0276(u_socio, 'authenticated', array[vg, vb]) like vg || '=2500;%' or teste_lote_0276(u_socio, 'authenticated', array[vg, vb]) like '%;' || vg || '=2500',
    'o Sócio conta as de todos os mandatos', teste_lote_0276(u_socio, 'authenticated', array[vg, vb]));
  perform teste_assert_0276(teste_lote_0276(null, 'anon', array[vg]) like '42501|%', 'o anon não executa (sem grant)', teste_lote_0276(null, 'anon', array[vg]));

  -- O 42501 acima pode vir da tabela (o anon não lê campo_extraido), não da função: o privilégio de EXECUTE é afirmado à parte.
  perform teste_assert_0276(not has_function_privilege('anon', 'fn_linhas_por_versao(uuid[])', 'execute')
                            and not has_function_privilege('anon', 'fn_algum_documento_serve_como(uuid[], text)', 'execute')
                            and has_function_privilege('authenticated', 'fn_linhas_por_versao(uuid[])', 'execute')
                            and has_function_privilege('authenticated', 'fn_algum_documento_serve_como(uuid[], text)', 'execute'),
    'o anon não tem EXECUTE nas duas funções e o authenticated tem', null);

  -- ---------------------------------------------------------------- 3. fn_algum_documento_serve_como = bool_or das individuais
  raise notice '--- 3. fn_algum_documento_serve_como concorda com bool_or de fn_documento_serve_como ---';
  v_ind := fn_documento_serve_como(d_comb, 'COMBINADO') or fn_documento_serve_como(d_unico, 'COMBINADO');
  v_lote := fn_algum_documento_serve_como(array[d_comb, d_unico], 'COMBINADO');
  perform teste_assert_0276(v_ind is true and v_lote = v_ind, 'caso que SERVE (BALANCO com 2 empresas com valor): o lote é true, como o bool_or das individuais', v_lote::text);
  v_ind := fn_documento_serve_como(d_unico, 'COMBINADO');
  v_lote := fn_algum_documento_serve_como(array[d_unico], 'COMBINADO');
  perform teste_assert_0276(v_ind is false and v_lote = v_ind, 'caso que NÃO serve (BALANCO de uma empresa só): o lote é false, como a individual', v_lote::text);
  perform teste_assert_0276(fn_algum_documento_serve_como(array[d_unico, d_rot], 'COMBINADO') is true
                            and fn_documento_serve_como(d_rot, 'COMBINADO') is true, 'serve pelo rótulo (documento COMBINADO): um só no array basta', null);
  perform teste_assert_0276(fn_algum_documento_serve_como(array[d_comb, d_unico], 'DRE') is false
                            and fn_algum_documento_serve_como(array[d_comb, d_unico], 'BALANCO') is true,
    'a regra do tipo vale por item: BALANCO serve BALANCO e nenhum serve DRE (a exceção só abre COMBINADO)', null);
  perform teste_assert_0276(fn_algum_documento_serve_como(array[]::uuid[], 'COMBINADO') is false
                            and fn_algum_documento_serve_como(null, 'COMBINADO') is false, 'array vazio ou nulo é false (nunca nulo)', null);

  -- Isolamento: o lote sob RLS de documento, COMO authenticated.
  perform teste_assert_0276(teste_exec_0276(u_ana, 'authenticated', format('fn_algum_documento_serve_como(%L::uuid[], ''COMBINADO'')', array[d_comb])) = 'ok|true',
    'a Analista de A vê o documento de A servir', teste_exec_0276(u_ana, 'authenticated', format('fn_algum_documento_serve_como(%L::uuid[], ''COMBINADO'')', array[d_comb])));
  perform teste_assert_0276(teste_exec_0276(u_xan, 'authenticated', format('fn_algum_documento_serve_como(%L::uuid[], ''COMBINADO'')', array[d_comb])) = 'ok|false',
    'a Analista de B pergunta pelo documento de A e recebe false (a RLS de documento esconde o mandato alheio)',
    teste_exec_0276(u_xan, 'authenticated', format('fn_algum_documento_serve_como(%L::uuid[], ''COMBINADO'')', array[d_comb])));
  perform teste_assert_0276(teste_exec_0276(u_nil, 'authenticated', format('fn_algum_documento_serve_como(%L::uuid[], ''COMBINADO'')', array[d_comb])) = 'ok|false',
    'quem não tem papel recebe false', null);
  perform teste_assert_0276(teste_exec_0276(null, 'anon', format('fn_algum_documento_serve_como(%L::uuid[], ''COMBINADO'')', array[d_comb])) like '42501|%',
    'o anon não executa (sem grant)', null);

  -- ---------------------------------------------------------------- 4. A SONDA
  raise notice '--- 4. a sonda enxerga o que a 0276 instala ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0276' and not presente;
  perform teste_assert_0276(v_n = 0, 'a sonda enxerga os 4 requisitos da 0276 (zero ausentes)', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0276';
  perform teste_assert_0276(v_n = 4, 'e o catálogo da 0276 tem 4 requisitos (não está vazio nem encolheu)', v_n::text);

  -- DEVOLVE O ESTADO.
  delete from caso where nome like '0276 —%';
  delete from auth.users where id in (u_socio, u_ana, u_xan, u_nil);

  raise notice 'EXECUCOES=% FALHAS=%', current_setting('ct76.execucoes', true), coalesce(current_setting('ct76.falhas', true), '0');
  if current_setting('ct76.medindo', true) is distinct from 'on' then
    raise notice 'TODOS OS TESTES DA 0276 PASSARAM';
  end if;
end $$;
