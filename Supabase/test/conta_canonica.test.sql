-- Testes da 0242: o catálogo `conta_canonica` (a árvore demonstração > grupo > seção > subgrupo) e as guardas dele.
-- Rodar via Supabase/test/run.sh (que aplica as migrations e carrega as fixtures de vertentes e canastra antes).
--
-- O QUE ESTE ARQUIVO PROVA (comportamento):
--   (1) toda `secao_canonica` que as fixtures carregadas gravam em `campo_extraido` tem conta no catálogo — medido sobre o DADO CARREGADO, não sobre uma lista fixa: se o extrator passar a gravar uma seção que o
--       catálogo não conhece, o teste reprova; e o denominador não é vazio (o assert de "há seções medidas" reprova se a fixture não trouxer nenhuma);
--   (2) a estrutura: 5 raízes (uma por demonstração), os 27 nós esperados presentes (por CÓDIGO, nunca por contagem: a P27 acrescenta folhas), todo nó sobe até a raiz da PRÓPRIA demonstração (nenhuma conta sem pai exceto as raízes), os 4 subgrupos e o balde Outros do ANC são filhos de ativo_nao_circulante, e a
--       natureza = saldo normal do grupo (receita_bruta credora), 'mista' só onde o grupo tem componentes próprios dos dois lados (regra 1: não fabricar);
--   (3) as guardas RECUSAM: pai nulo em não-raiz, raiz com pai, pai de outra demonstração, pai inexistente, pai = o próprio, ciclo de 2 e de 3 nós (por UPDATE), o ciclo de um INSERT em lote e o de dois pais trocados num UPDATE só (os dois que o gatilho de linha da primeira versão deixava passar), natureza e demonstração inválidas, seção duplicada,
--       o escape NAO_CLASSIFICAVEL, classe_recorrencia inexistente — e ACEITAM o reparentamento legítimo e a folha válida (controle positivo: a guarda não recusa tudo);
--   (4) o acesso: sem papel o authenticated lê zero linhas; com papel lê o catálogo; não escreve;
--   (5) a sonda: os 9 requisitos da 0242 presentes, e ela ACUSA o nó esperado que falta (mesmo com folha a mais), cada uma das 9 constraints dropadas, o gatilho desabilitado e o nó órfão (a sonda não está cega).
--
-- HONESTIDADE (regra 4): o book DISTRESS não tem fixture no banco. Os asserts de (1) cobrem as seções que as fixtures de vertentes e canastra trazem (14 de 15; `dva` não aparece) e NÃO provam que o terceiro book
-- é coberto. As linhas sintéticas de (3) existem para provar a GUARDA (recusa/aceite), não para reproduzir bug de produção, e são desfeitas.
-- A régua contra `SECAO_CANONICA_ENUM` (o conjunto do catálogo = o do extrator) mora em Supabase/test/conta_canonica_regua.test.mjs.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número reprovado por sabotagem está no cabeçalho de Supabase/migrations/0242_a_secao_que_so_existia_em_codigo.sql ("MEDIÇÃO NÃO-VAZIA").
-- `cc.medindo = on` (PGOPTIONS='-c cc.medindo=on') vira `raise warning` e CONTA.

\set ON_ERROR_STOP on

create or replace function teste_assert_cc(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('cc.execucoes', (coalesce(nullif(current_setting('cc.execucoes', true), ''), '0')::int + 1)::text, false);
  if p_ok then
    raise notice 'ok    %', p_nome;
  elsif current_setting('cc.medindo', true) = 'on' then
    perform set_config('cc.falhas', (coalesce(nullif(current_setting('cc.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- Executa o comando e devolve 'sqlstate|mensagem' do erro, ou 'ok:<linhas>'. NADA do que o comando fez fica, nem quando ele PASSA: com a guarda desligada (a medição da regra 2) o comando "recusado" entra, e a linha
-- que sobrasse contaminaria os asserts seguintes (medido na primeira versão: com uma guarda desligada reprovavam 3 asserts de contaminação além do da guarda).
create or replace function teste_tenta_cc(p_sql text) returns text language plpgsql as $$
declare n int;
begin
  begin
    execute p_sql;
    get diagnostics n = row_count;
    raise exception 'desfaz' using errcode = 'X0242';
  exception when sqlstate 'X0242' then
    return 'ok:' || n;
  end;
exception when others then
  return sqlstate || '|' || sqlerrm;
end $$;

-- Os 27 nós esperados (o conjunto do seed da 0242). Lista própria do teste: é com ela que se confere o banco por CÓDIGO, e não por contagem.
create or replace function teste_codigos_cc() returns text[] language sql immutable as $$
  select array['demo_balanco','demo_dre','demo_fluxo_caixa','demo_dmpl','demo_dva','ativo','passivo_pl',
    'receita_bruta','custos','despesas_operacionais','resultado_financeiro','impostos_lucro',
    'atividades_operacionais','atividades_investimento','atividades_financiamento','dmpl','dva',
    'ativo_circulante','ativo_nao_circulante','passivo_circulante','passivo_nao_circulante','patrimonio_liquido',
    'realizavel_lp','investimentos','imobilizado','intangivel','outros_ativos_nao_circulantes'] $$;

-- ---------------------------------------------------------------------------------------------------------------
do $$
declare v_n int; v_lista text;
begin
  raise notice '--- 1. a seção que as fixtures gravam tem conta (medido sobre o dado carregado) ---';
  select count(distinct secao_canonica) into v_n from campo_extraido where secao_canonica is not null;
  perform teste_assert_cc(v_n >= 10, 'as fixtures carregadas trazem seções para medir (o laço abaixo não corre sobre o vazio)', v_n::text);

  select string_agg(distinct ce.secao_canonica, ', ') into v_lista
    from campo_extraido ce
   where ce.secao_canonica is not null
     and ce.secao_canonica <> 'NAO_CLASSIFICAVEL'
     and not exists (select 1 from conta_canonica c where c.secao_canonica = ce.secao_canonica);
  perform teste_assert_cc(v_lista is null, 'toda secao_canonica gravada em campo_extraido tem conta canônica', v_lista);

  -- O ESCAPE FICA DE FORA DE PROPÓSITO, e o número que o justifica foi medido: as fixtures carregadas têm 466 linhas com o literal NAO_CLASSIFICAVEL em
  -- campo_extraido.secao_canonica (o extrator o grava como null, extract.mjs:612/1410, mas o dado carregado e as migrations 0105/0144/0151/0152/0159/0240 o tratam como valor).
  -- "Não sei a seção" não é seção: o escape não é conta. O assert abaixo prova que a exclusão é REAL (há o que excluir) e que ele é o ÚNICO valor fora do catálogo.
  select count(*) into v_n from campo_extraido where secao_canonica = 'NAO_CLASSIFICAVEL';
  perform teste_assert_cc(v_n > 0, 'as fixtures trazem o escape NAO_CLASSIFICAVEL (a exclusão acima exclui algo)', v_n::text);

  select count(*) into v_n from conta_canonica where secao_canonica is not null;
  perform teste_assert_cc(v_n = 15, 'o catálogo tem as 15 seções (as de SECAO_CANONICA_ENUM sem o escape)', v_n::text);
  perform teste_assert_cc(not exists (select 1 from conta_canonica where secao_canonica = 'NAO_CLASSIFICAVEL'),
    'o escape NAO_CLASSIFICAVEL não é conta ("não sei a seção" não é seção)');

  -- a demonstração de cada seção é a que o portal roteia (FAMILIA_POR_SECAO_CANONICA)
  select string_agg(c.secao_canonica || ' (' || c.demonstracao || ' <> ' || e.d || ')', ', ') into v_lista
    from conta_canonica c
    join (values ('ativo_circulante','balanco'), ('ativo_nao_circulante','balanco'), ('passivo_circulante','balanco'),
                 ('passivo_nao_circulante','balanco'), ('patrimonio_liquido','balanco'), ('receita_bruta','dre'), ('custos','dre'),
                 ('despesas_operacionais','dre'), ('resultado_financeiro','dre'), ('impostos_lucro','dre'),
                 ('atividades_operacionais','fluxo_caixa'), ('atividades_investimento','fluxo_caixa'),
                 ('atividades_financiamento','fluxo_caixa'), ('dmpl','dmpl'), ('dva','dva')) e(s, d) on e.s = c.secao_canonica
   where c.demonstracao <> e.d;
  perform teste_assert_cc(v_lista is null, 'cada seção está na demonstração que o portal roteia', v_lista);

  raise notice '--- 2. a estrutura: raízes, subida até a raiz, subgrupos, natureza ---';
  select string_agg(e, ', ') into v_lista from unnest(teste_codigos_cc()) e where not exists (select 1 from conta_canonica c where c.codigo = e);
  perform teste_assert_cc(v_lista is null and cardinality(teste_codigos_cc()) = 27,
    'os 27 nós esperados da taxonomia atual estão presentes, por código (5 raízes + 2 grupos + 15 seções + 4 subgrupos + Outros do ANC)', v_lista);
  select count(*) into v_n from conta_canonica where pai is null;
  perform teste_assert_cc(v_n = 5 and (select count(distinct demonstracao) from conta_canonica where pai is null) = 5,
    'cinco raízes, uma por demonstração', v_n::text);
  select string_agg(codigo, ', ') into v_lista from conta_canonica where pai is null and codigo <> 'demo_' || demonstracao;
  perform teste_assert_cc(v_lista is null, 'nenhuma conta sem pai exceto as raízes', v_lista);

  with recursive sobe(origem, atual, pai) as (
    select codigo, codigo, pai from conta_canonica
    union
    select s.origem, c.codigo, c.pai from sobe s join conta_canonica c on c.codigo = s.pai
  )
  select string_agg(c.codigo, ', ') into v_lista
    from conta_canonica c
   where not exists (select 1 from sobe s where s.origem = c.codigo and s.pai is null and s.atual = 'demo_' || c.demonstracao);
  perform teste_assert_cc(v_lista is null, 'todo nó sobe até a raiz da própria demonstração', v_lista);

  select count(*) into v_n from conta_canonica
   where pai = 'ativo_nao_circulante' and codigo in ('realizavel_lp', 'investimentos', 'imobilizado', 'intangivel', 'outros_ativos_nao_circulantes')
     and secao_canonica is null;
  perform teste_assert_cc(v_n = 5, 'os 4 subgrupos e o balde Outros são filhos do GRUPO ANC (o nó da seção ativo_nao_circulante) e não são seção do enum', v_n::text);
  perform teste_assert_cc((select secao_canonica from conta_canonica where codigo = 'ativo_nao_circulante') = 'ativo_nao_circulante'
    and (select pai from conta_canonica where codigo = 'ativo_nao_circulante') = 'ativo',
    'o nó com secao_canonica ativo_nao_circulante é o grupo ANC, filho de ativo (não o balde Outros)');

  select string_agg(secao_canonica, ', ') into v_lista from conta_canonica
   where secao_canonica in ('despesas_operacionais', 'resultado_financeiro', 'impostos_lucro', 'atividades_operacionais',
                            'atividades_investimento', 'atividades_financiamento', 'dmpl', 'dva')
     and natureza <> 'mista';
  perform teste_assert_cc(v_lista is null, 'seção sem sinal único é mista (nenhum sinal fabricado)', v_lista);
  perform teste_assert_cc(
    (select natureza from conta_canonica where codigo = 'ativo_circulante') = 'devedora'
    and (select natureza from conta_canonica where codigo = 'passivo_circulante') = 'credora'
    and (select natureza from conta_canonica where codigo = 'patrimonio_liquido') = 'credora'
    and (select natureza from conta_canonica where codigo = 'custos') = 'devedora'
    and (select natureza from conta_canonica where codigo = 'ativo_nao_circulante') = 'devedora',
    'natureza = saldo normal do grupo (ativo e custos devedoras; passivo e PL credoras)');
  perform teste_assert_cc((select natureza from conta_canonica where codigo = 'receita_bruta') = 'credora',
    'receita_bruta é credora: a dedução é folha redutora (P27) e a folha não herda a natureza do pai, então o grupo não fica mista por causa dela');
  perform teste_assert_cc(not exists (select 1 from conta_canonica where classe_recorrencia is not null),
    'nenhum nó traz classe_recorrencia (recorrência é da rubrica; classificá-la por seção seria inventar)');
end $$;

-- ---------------------------------------------------------------------------------------------------------------
do $$
declare v_t text;
begin
  raise notice '--- 3. as guardas recusam ---';
  v_t := teste_tenta_cc($q$insert into conta_canonica (codigo, nome, pai, demonstracao, natureza, ordem) values ('t_solta', 'solta', null, 'balanco', 'devedora', 1)$q$);
  perform teste_assert_cc(v_t like '23514|%', 'conta sem pai que não é raiz é recusada', v_t);

  v_t := teste_tenta_cc($q$update conta_canonica set pai = 'demo_dre' where codigo = 'demo_balanco'$q$);
  perform teste_assert_cc(v_t like '23514|%', 'raiz com pai é recusada', v_t);

  v_t := teste_tenta_cc($q$insert into conta_canonica (codigo, nome, pai, demonstracao, natureza, ordem) values ('t_cruza', 'cruza', 'ativo', 'dre', 'mista', 1)$q$);
  perform teste_assert_cc(v_t like '23503|%', 'pai de OUTRA demonstração é recusado (insert)', v_t);

  v_t := teste_tenta_cc($q$update conta_canonica set pai = 'custos' where codigo = 'realizavel_lp'$q$);
  perform teste_assert_cc(v_t like '23503|%', 'pai de OUTRA demonstração é recusado (update)', v_t);

  v_t := teste_tenta_cc($q$insert into conta_canonica (codigo, nome, pai, demonstracao, natureza, ordem) values ('t_orfa', 'orfa', 'nao_existe', 'balanco', 'devedora', 1)$q$);
  perform teste_assert_cc(v_t like '23503|%', 'pai inexistente é recusado', v_t);

  v_t := teste_tenta_cc($q$insert into conta_canonica (codigo, nome, pai, demonstracao, natureza, ordem) values ('t_si', 'si', 't_si', 'balanco', 'devedora', 1)$q$);
  perform teste_assert_cc(v_t like '23514|%', 'pai igual ao próprio código é recusado', v_t);

  v_t := teste_tenta_cc($q$update conta_canonica set pai = 'imobilizado' where codigo = 'ativo_nao_circulante'$q$);
  perform teste_assert_cc(v_t like '23514|%ciclo%', 'ciclo de 2 nós (o pai vira filho do próprio filho) é recusado', v_t);

  v_t := teste_tenta_cc($q$update conta_canonica set pai = 'imobilizado' where codigo = 'ativo'$q$);
  perform teste_assert_cc(v_t like '23514|%ciclo%', 'ciclo de 3 nós (ativo > ANC > imobilizado > ativo) é recusado', v_t);

  v_t := teste_tenta_cc($q$insert into conta_canonica (codigo, nome, pai, demonstracao, natureza, ordem) values
    ('t_a', 'a', 't_b', 'balanco', 'devedora', 1), ('t_b', 'b', 't_a', 'balanco', 'devedora', 2)$q$);
  perform teste_assert_cc(v_t like '23514|%ciclo%', 'ciclo num INSERT em lote (t_a pai t_b, t_b pai t_a) é recusado', v_t);

  -- dois pais trocados num UPDATE só: cada linha olhava a outra ainda com o pai antigo (o gatilho de linha da primeira versão não via)
  v_t := teste_tenta_cc($q$do $x$ begin
    insert into conta_canonica (codigo, nome, pai, demonstracao, natureza, ordem) values ('t_a', 'a', 'ativo', 'balanco', 'devedora', 1), ('t_b', 'b', 'ativo', 'balanco', 'devedora', 2);
    update conta_canonica set pai = case codigo when 't_a' then 't_b' else 't_a' end where codigo in ('t_a', 't_b');
  end $x$ $q$);
  perform teste_assert_cc(v_t like '23514|%ciclo%', 'ciclo por dois pais trocados num UPDATE só é recusado', v_t);

  v_t := teste_tenta_cc($q$update conta_canonica set natureza = 'neutra' where codigo = 'custos'$q$);
  perform teste_assert_cc(v_t like '23514|%', 'natureza fora de devedora/credora/mista é recusada', v_t);

  v_t := teste_tenta_cc($q$insert into conta_canonica (codigo, nome, pai, demonstracao, natureza, ordem) values ('t_demo', 'demo', 'ativo', 'balancete', 'devedora', 1)$q$);
  perform teste_assert_cc(v_t like '23514|%', 'demonstração fora das cinco é recusada', v_t);

  v_t := teste_tenta_cc($q$insert into conta_canonica (codigo, nome, pai, demonstracao, natureza, secao_canonica, ordem) values ('t_dup', 'dup', 'ativo', 'balanco', 'devedora', 'custos', 1)$q$);
  perform teste_assert_cc(v_t like '23505|%', 'secao_canonica repetida é recusada (uma conta por seção)', v_t);

  v_t := teste_tenta_cc($q$insert into conta_canonica (codigo, nome, pai, demonstracao, natureza, secao_canonica, ordem) values ('t_nc', 'nc', 'ativo', 'balanco', 'devedora', 'NAO_CLASSIFICAVEL', 1)$q$);
  perform teste_assert_cc(v_t like '23514|%', 'NAO_CLASSIFICAVEL não vira conta', v_t);

  v_t := teste_tenta_cc($q$insert into conta_canonica (codigo, nome, pai, demonstracao, natureza, classe_recorrencia, ordem) values ('t_cl', 'cl', 'ativo', 'balanco', 'devedora', 'inexistente', 1)$q$);
  perform teste_assert_cc(v_t like '23503|%', 'classe_recorrencia que não está no catálogo da 0128 é recusada', v_t);

  raise notice '--- 3b. controle positivo: a guarda aceita o legítimo ---';
  v_t := teste_tenta_cc($q$insert into conta_canonica (codigo, nome, pai, demonstracao, natureza, ordem) values ('t_folha_ok', 'folha ok', 'imobilizado', 'balanco', 'devedora', 99999)$q$);
  perform teste_assert_cc(v_t = 'ok:1', 'uma folha válida debaixo de um subgrupo é aceita', v_t);
  insert into conta_canonica (codigo, nome, pai, demonstracao, natureza, ordem) values ('t_folha_ok', 'folha ok', 'imobilizado', 'balanco', 'devedora', 99999);
  v_t := teste_tenta_cc($q$update conta_canonica set pai = 'ativo' where codigo = 't_folha_ok'$q$);
  perform teste_assert_cc(v_t = 'ok:1', 'reparentar dentro da mesma demonstração, sem ciclo, é aceito', v_t);
  delete from conta_canonica where codigo = 't_folha_ok';
end $$;

-- ---------------------------------------------------------------------------------------------------------------
do $$
declare v_uid uuid := gen_random_uuid(); v_n int; v_t text; v_total int;
begin
  raise notice '--- 4. o acesso: sem papel não lê; com papel lê e não escreve ---';
  select count(*) into v_total from conta_canonica;
  insert into auth.users (id, email) values (v_uid, 'cc0242@teste');

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_n from conta_canonica;
  perform teste_assert_cc(v_n = 0, 'usuário sem papel não lê o catálogo', v_n::text);
  execute 'reset role';

  insert into membro (usuario_id, papel) values (v_uid, 'leitura');
  execute 'set local role authenticated';
  select count(*) into v_n from conta_canonica;
  perform teste_assert_cc(v_n = v_total and (select count(*) from conta_canonica where codigo = any (teste_codigos_cc())) = 27, 'usuário com papel lê o catálogo inteiro (os 27 nós esperados entre eles)', v_n::text);
  v_t := teste_tenta_cc($q$insert into conta_canonica (codigo, nome, pai, demonstracao, natureza, ordem) values ('t_acesso', 'x', 'ativo', 'balanco', 'devedora', 1)$q$);
  perform teste_assert_cc(v_t like '42501|%', 'o authenticated não insere no catálogo', v_t);
  v_t := teste_tenta_cc($q$update conta_canonica set nome = 'alterado' where codigo = 'custos'$q$);
  perform teste_assert_cc(v_t in ('ok:0') or v_t like '42501|%', 'o authenticated não altera o catálogo', v_t);
  execute 'reset role';
  perform teste_assert_cc((select nome from conta_canonica where codigo = 'custos') = 'Custos', 'e o nome continua o do seed');

  delete from membro where usuario_id = v_uid;
  delete from auth.users where id = v_uid;
  perform set_config('request.jwt.claims', '', true);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
do $$
declare v_n int; v_ok boolean; v_seed boolean; v_seed_folha boolean; v_folha_so boolean; v_gat boolean; v_orf boolean;
        v_c text; v_res text := ''; v_ausentes int := 0;
begin
  raise notice '--- 5. a sonda enxerga os requisitos da 0242 e não está cega ---';
  select count(*) into v_n from instalacao_requisito where migration = '0242';
  perform teste_assert_cc(v_n = 9, 'o catálogo da sonda declara os 9 requisitos da 0242', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0242' and presente;
  perform teste_assert_cc(v_n = 9, 'os 9 estão presentes no banco montado', v_n::text);
  perform teste_assert_cc((select ate_migration >= '0242' from instalacao_cobertura), 'a cobertura da sonda chega à 0242');

  -- as medições dos blocos abaixo são lidas FORA do bloco desfeito: o rollback do bloco desfaz também o contador de asserts (set_config de sessão é transacional), e um assert dentro dele não contaria.
  -- (variável PL/pgSQL, ao contrário do banco, NÃO volta no rollback do bloco)

  -- nó esperado que falta
  begin
    delete from conta_canonica where codigo = 'intangivel';
    select presente into v_ok from fn_instalacao_conferir() where chave = 'conta_canonica_seed';
    v_seed := v_ok;
    raise exception 'desfaz' using errcode = 'X0242';
  exception when sqlstate 'X0242' then null;
  end;

  -- folha a mais NÃO derruba o seed (a P27 acrescenta folhas) — e não esconde o nó que falta (a contagem esconderia: 27 - 1 + 1)
  begin
    insert into conta_canonica (codigo, nome, pai, demonstracao, natureza, ordem) values ('t_folha_sonda', 'folha', 'imobilizado', 'balanco', 'devedora', 99999);
    select presente into v_ok from fn_instalacao_conferir() where chave = 'conta_canonica_seed';
    v_folha_so := v_ok;
    delete from conta_canonica where codigo = 'intangivel';
    select presente into v_ok from fn_instalacao_conferir() where chave = 'conta_canonica_seed';
    v_seed_folha := v_ok;
    raise exception 'desfaz' using errcode = 'X0242';
  exception when sqlstate 'X0242' then null;
  end;

  -- cada constraint estrutural dropada (cascade: a unique da chave composta leva a FK junto)
  for v_c in select unnest(array['conta_canonica_pkey', 'conta_canonica_codigo_demonstracao_uq', 'conta_canonica_secao_canonica_key', 'conta_canonica_raiz_ck',
                                 'conta_canonica_pai_fk', 'conta_canonica_classe_recorrencia_fkey',
                                 'conta_canonica_demonstracao_check', 'conta_canonica_natureza_check', 'conta_canonica_secao_canonica_check']) loop
    begin
      execute format('alter table conta_canonica drop constraint if exists %I cascade', v_c);
      select presente into v_ok from fn_instalacao_conferir() where chave = 'conta_canonica_constraints';
      v_res := v_res || v_c || '=' || coalesce(v_ok::text, 'null') || ' ';
      if v_ok = false then v_ausentes := v_ausentes + 1; end if;
      raise exception 'desfaz' using errcode = 'X0242';
    exception when sqlstate 'X0242' then null;
    end;
  end loop;

  -- gatilho desligado
  begin
    begin
      alter table conta_canonica disable trigger trg_conta_canonica_alcanca_a_raiz;
    exception when undefined_object then null;  -- gatilho nem existe: a sonda tem de acusar do mesmo jeito
    end;
    select presente into v_ok from fn_instalacao_conferir() where chave = 'conta_canonica_gatilho_raiz';
    v_gat := v_ok;
    raise exception 'desfaz' using errcode = 'X0242';
  exception when sqlstate 'X0242' then null;
  end;

  -- nó órfão (um ciclo, feito driblando as guardas por session_replication_role, o único jeito de ele existir)
  begin
    set local session_replication_role = replica;
    update conta_canonica set pai = 'imobilizado' where codigo = 'ativo_nao_circulante';
    select presente into v_ok from fn_instalacao_conferir() where chave = 'conta_canonica_sem_no_orfao';
    v_orf := v_ok;
    raise exception 'desfaz' using errcode = 'X0242';
  exception when sqlstate 'X0242' then null;
  end;

  perform teste_assert_cc(v_seed = false, 'a sonda acusa o nó esperado que falta (intangivel)');
  perform teste_assert_cc(v_folha_so, 'uma folha a mais não derruba o requisito do seed (a P27 acrescenta folhas)');
  perform teste_assert_cc(v_seed_folha = false, 'e uma folha a mais não esconde o nó esperado que falta (contagem esconderia)');
  perform teste_assert_cc(v_ausentes = 9, 'a sonda acusa cada uma das 9 constraints estruturais dropadas', v_res);
  perform teste_assert_cc(v_gat = false, 'a sonda acusa o gatilho de raiz desabilitado');
  perform teste_assert_cc(v_orf = false, 'a sonda acusa o nó órfão (ciclo)');
  select presente into v_ok from fn_instalacao_conferir() where chave = 'conta_canonica_gatilho_raiz';
  perform teste_assert_cc(v_ok, 'e volta a presente quando o bloco desfaz (o gatilho não ficou desligado)');
  select presente into v_ok from fn_instalacao_conferir() where chave = 'conta_canonica_sem_no_orfao';
  perform teste_assert_cc(v_ok, 'e o catálogo continua sem órfão depois dos blocos desfeitos');

  if current_setting('cc.medindo', true) = 'on' then
    raise warning 'MEDIDO: % falha(s) de % execucoes', coalesce(current_setting('cc.falhas', true), '0'), current_setting('cc.execucoes', true);
  end if;
  raise notice 'TODOS OS TESTES DA 0242 PASSARAM';
end $$;
