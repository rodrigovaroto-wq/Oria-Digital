-- AS CORRIDAS DA 0243, COM DUAS SESSÕES REAIS (Supabase/migrations/0243_a_linha_que_nao_tinha_identidade.sql).
--
-- O DEFEITO QUE ESTE ARQUIVO EXISTE PARA PEGAR. No desenho anterior (a TABELA fato_financeiro mantida por gatilhos) a 5ª revisão reproduziu corridas em que o fato gravado não convergia para o estado atual: um gatilho de cadastro recalculava num snapshot velho enquanto um update de documento não comitado segurava o lock (R1 e R3), e uma
-- extração COMBINADO concorrente com o cadastro de uma entidade que casa a mesma coluna deixava o motivo falso ou o valor atribuído onde o do-zero dá coluna_casa_varias_entidades (R2). Com a VIEW não há cópia: cada leitura lê o estado COMITADO daquele instante, e a única coisa que a migration ainda escreve é a pendência (R4).
--
-- O QUE PROVA (comportamento): (R1) a extração não comitada de uma sessão e o cadastro de uma entidade da outra: antes do commit a leitura NÃO vê a extração (isolamento) e depois vê o fato certo, escrito à mão; (R2) a extração e o cadastro de uma 2ª entidade que casa a coluna: o fato é o do zero (coluna_casa_varias_entidades), nas DUAS ordens de commit;
-- (R3) o update de documento.entidade_id não comitado e o cadastro de entidade e de período: a leitura mostra o estado comitado e, depois do commit, o novo; (R4) duas extrações concorrentes de duas versões do MESMO documento: uma pendência aberta só (a da vigente), pela trava do documento.
-- Só dá para provar com sessões que comitam separadas, por isso é um arquivo à parte e usa dblink (uma conexão do servidor a ele mesmo, pelo socket Unix). Sem dblink a suíte diz "NÃO EXECUTADO" e NÃO finge que passou (regra 7); o CI roda o postgres:16 oficial, que o tem.
--
-- NÃO É TRANSACIONAL: comita de verdade e apaga o que criou no fim (os mandatos "0243 corrida ..."). Roda DEPOIS dos demais testes do banco montado.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número que reprova com a correção desligada está no cabeçalho de Supabase/migrations/0243_a_linha_que_nao_tinha_identidade.sql (a trava do documento removida: a R4; as demais corridas não têm código a desligar na view: o que elas provam é que NÃO há cópia a envelhecer, e a medição é rodar o mesmo roteiro contra a TABELA da versão 7d5f503, onde reprovam).

\set ON_ERROR_STOP on

create temp sequence _falhas_ffc;
create temp sequence _execucoes_ffc;
create or replace function pg_temp.teste_assert_ffc(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform nextval('pg_temp._execucoes_ffc');
  if coalesce(p_ok, false) then raise notice 'ok    %', p_nome;
  else raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, ''); perform nextval('pg_temp._falhas_ffc'); end if;
end $$;

-- o fato como texto (o mesmo formato do fato_financeiro.test.sql) e a diferença contra o esperado à mão
create or replace function pg_temp.atual(p_versao uuid) returns text[] language sql as $$
  select coalesce(array_agg(x order by x), '{}'::text[]) from (
    select ce.chave || '|' || coalesce(nullif(btrim(ce.periodo_coluna), ''), '-') || '|' || coalesce(nullif(btrim(ce.entidade_coluna), ''), '-') || '|' || trim_scale(f.valor)::text
           || '|' || coalesce(f.conta_id, 'sem_conta:' || f.sem_conta_motivo) || case when f.resolucao_metodo = 'heuristica' then ' (heuristica)' else '' end
           || '|' || coalesce(e.razao_social, '-') || '|' || coalesce(f.entidade_motivo, '-') || '|' || coalesce(p.referencia, '-') || '|' || coalesce(f.periodo_motivo, '-') as x
      from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id left join entidade e on e.id = f.entidade_id left join periodo p on p.id = f.periodo_id
     where f.documento_versao_id = p_versao) z
$$;
create or replace function pg_temp.dif(p_versao uuid, p_esperado text[]) returns text language sql as $$
  select coalesce((select 'FALTAM: ' || string_agg(x, ' ;; ') from (select unnest(p_esperado) x except all select unnest(pg_temp.atual(p_versao))) a having count(*) > 0), '')
      || coalesce((select ' || SOBRAM: ' || string_agg(x, ' ;; ') from (select unnest(pg_temp.atual(p_versao)) x except all select unnest(p_esperado)) b having count(*) > 0), '')
$$;

-- 0. dblink e as duas conexões (A e B), a cada uma a sua sessão. Sem dblink: não executado, e DIZ.
do $$
declare v_dir text; v_cs text;
begin
  create schema if not exists ff_dblink;
  begin
    create extension if not exists dblink schema ff_dblink;
  exception when others then
    raise notice 'NÃO EXECUTADO: dblink indisponível neste servidor (%). As corridas R1-R4 da 0243 NÃO foram provadas por este teste.', sqlerrm;
    perform set_config('ffc.sem_dblink', '1', false);
    return;
  end;
  v_dir := split_part(current_setting('unix_socket_directories'), ',', 1);
  v_cs := format('dbname=%s user=%s host=%s port=%s', current_database(), current_user, v_dir, current_setting('port'));
  begin
    perform ff_dblink.dblink_connect('a', v_cs);
    perform ff_dblink.dblink_connect('b', v_cs);
    -- uma espera de lock que não termina faria o teste PENDURAR (e o CI com ele): nas duas sessões ela falha em 20 s, alto, com o motivo
    perform ff_dblink.dblink_exec('a', 'set lock_timeout = ''20s''');
    perform ff_dblink.dblink_exec('b', 'set lock_timeout = ''20s''');
  exception when others then
    raise notice 'NÃO EXECUTADO: dblink não conectou (%). As corridas R1-R4 da 0243 NÃO foram provadas por este teste.', sqlerrm;
    perform set_config('ffc.sem_dblink', '1', false);
  end;
end $$;

-- helper: roda uma consulta de uma coluna texto numa conexão e devolve o valor
create or replace function pg_temp.via(p_con text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  select t.x into v from ff_dblink.dblink(p_con, p_sql) as t(x text);
  return v;
end $$;

-- 1. O ARRANJO (comita): um mandato por corrida
do $$
declare v_c uuid;
begin
  if current_setting('ffc.sem_dblink', true) = '1' then return; end if;
  delete from caso where nome like '0243 corrida %';   -- o que uma execução anterior interrompida deixou
  v_c := fn_upsert_caso('0243 corrida R1')::uuid; perform fn_upsert_entidade(v_c, 'METAL R1 LTDA'); perform fn_upsert_periodo(v_c, 'anual', '2025');
  v_c := fn_upsert_caso('0243 corrida R2')::uuid; perform fn_upsert_entidade(v_c, 'VERTENTES R2 LTDA'); perform fn_upsert_periodo(v_c, 'anual', '2025');
  v_c := fn_upsert_caso('0243 corrida R3')::uuid; perform fn_upsert_entidade(v_c, 'DOC R3 UM LTDA'); perform fn_upsert_entidade(v_c, 'DOC R3 DOIS LTDA'); perform fn_upsert_periodo(v_c, 'anual', '2025');
  v_c := fn_upsert_caso('0243 corrida R4')::uuid; perform fn_upsert_entidade(v_c, 'PEND R4 LTDA'); perform fn_upsert_periodo(v_c, 'anual', '2025');
end $$;

-- R1: a sessão A extrai um COMBINADO e NÃO comita; a sessão B cadastra a entidade GAMA FORJADOS (uma das colunas da extração) e comita. Nada trava (a view não tem gatilho nem cópia). Antes do commit de A a leitura não vê a extração; depois vê o fato certo.
do $$
declare v_c uuid; v_a text; v_antes bigint; v_d text; v_n int;
begin
  if current_setting('ffc.sem_dblink', true) = '1' then return; end if;
  raise notice '--- R1: extração não comitada (A) x cadastro de entidade (B) ---';
  select id into v_c from caso where nome = '0243 corrida R1';
  perform ff_dblink.dblink_exec('a', 'begin');
  v_a := pg_temp.via('a', format($q$select (fn_registrar_documento(%L, 'METAL R1 LTDA', 'anual', '2025', 'COMBINADO', 0.97, 'nome_arquivo', 'supabase_storage', 'r1/a.pdf', 'r1a.pdf', true, 'r1hash', 'ok')->>'documento_versao_id')$q$, v_c));
  perform pg_temp.via('a', format($q$select fn_registrar_campos_extraidos(%L::uuid, '[{"chave":"Receita de vendas","valor_num":"100","secao_canonica":"receita_bruta","periodo_coluna":"2025","entidade_coluna":"Gama Forjados R1","confianca":"0.97"},{"chave":"Receita de vendas","valor_num":"200","secao_canonica":"receita_bruta","periodo_coluna":"2025","entidade_coluna":"Metal R1","confianca":"0.97"}]'::jsonb)::text$q$, v_a));
  perform ff_dblink.dblink_exec('b', format($q$insert into entidade (caso_id, razao_social) values (%L, 'GAMA FORJADOS R1 LTDA')$q$, v_c));   -- B comita na hora: não espera A
  select count(*) into v_antes from fato_financeiro where caso_id = v_c;
  perform pg_temp.teste_assert_ffc(v_antes = 0, 'R1: com a extração de A ainda NÃO comitada, a leitura do mandato não a enxerga (isolamento) e o cadastro de B não travou', v_antes::text);
  perform ff_dblink.dblink_exec('a', 'commit');
  v_d := pg_temp.dif(v_a::uuid, array[
    'Receita de vendas|2025|Gama Forjados R1|100|receita_bruta|GAMA FORJADOS R1 LTDA|-|2025|-',
    'Receita de vendas|2025|Metal R1|200|receita_bruta|METAL R1 LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ffc(v_d = '', 'R1: depois do commit de A, o fato é o certo — a coluna "Gama Forjados R1" é da entidade que B cadastrou no meio (100) e a "Metal R1" da dona do documento (200) — escrito à mão', v_d);
end $$;

-- R2: A extrai um COMBINADO (coluna "Vertentes R2") e NÃO comita; B cadastra a 2ª entidade que casa a mesma coluna ("VERTENTES R2 DO SUL LTDA") e comita. O fato do zero: a coluna casa DUAS entidades, nenhuma a recebe.
do $$
declare v_c uuid; v_a text; v_d text;
begin
  if current_setting('ffc.sem_dblink', true) = '1' then return; end if;
  raise notice '--- R2: extração COMBINADO (A) x 2ª entidade que casa a coluna (B) ---';
  select id into v_c from caso where nome = '0243 corrida R2';
  perform ff_dblink.dblink_exec('a', 'begin');
  v_a := pg_temp.via('a', format($q$select (fn_registrar_documento(%L, 'VERTENTES R2 LTDA', 'anual', '2025', 'COMBINADO', 0.97, 'nome_arquivo', 'supabase_storage', 'r2/a.pdf', 'r2a.pdf', true, 'r2hash', 'ok')->>'documento_versao_id')$q$, v_c));
  perform pg_temp.via('a', format($q$select fn_registrar_campos_extraidos(%L::uuid, '[{"chave":"Receita de vendas","valor_num":"200","secao_canonica":"receita_bruta","periodo_coluna":"2025","entidade_coluna":"Vertentes R2","confianca":"0.97"}]'::jsonb)::text$q$, v_a));
  perform ff_dblink.dblink_exec('b', format($q$insert into entidade (caso_id, razao_social) values (%L, 'VERTENTES R2 DO SUL LTDA')$q$, v_c));
  perform ff_dblink.dblink_exec('a', 'commit');
  v_d := pg_temp.dif(v_a::uuid, array['Receita de vendas|2025|Vertentes R2|200|receita_bruta|-|coluna_casa_varias_entidades|2025|-']);
  perform pg_temp.teste_assert_ffc(v_d = '', 'R2: extração e cadastro concorrentes (B comita antes de A): a coluna casa DUAS entidades e nenhuma recebe o valor, com o motivo — o que o zero dá — escrito à mão', v_d);
  -- a ordem inversa: o commit de A ANTES do cadastro de B
  perform ff_dblink.dblink_exec('b', format($q$delete from entidade where caso_id = %L and razao_social = 'VERTENTES R2 DO SUL LTDA'$q$, v_c));
  v_d := pg_temp.dif(v_a::uuid, array['Receita de vendas|2025|Vertentes R2|200|receita_bruta|VERTENTES R2 LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ffc(v_d = '', 'R2: removida a 2ª entidade a coluna volta a ser da primeira (200): a leitura segue o estado, em qualquer ordem — escrito à mão', v_d);
  perform ff_dblink.dblink_exec('b', format($q$insert into entidade (caso_id, razao_social) values (%L, 'VERTENTES R2 DO SUL LTDA')$q$, v_c));
  v_d := pg_temp.dif(v_a::uuid, array['Receita de vendas|2025|Vertentes R2|200|receita_bruta|-|coluna_casa_varias_entidades|2025|-']);
  perform pg_temp.teste_assert_ffc(v_d = '', 'R2: cadastrada a 2ª entidade DEPOIS do commit de A: o mesmo fato do zero (a ordem entre a extração e o cadastro não importa)', v_d);
end $$;

-- R3: A atualiza documento.entidade_id e NÃO comita (segura o lock do documento); B cadastra uma entidade e um período do mandato e comita. Nada trava. A leitura de B mostra o estado COMITADO (a entidade antiga) e, depois do commit de A, a nova.
-- (o arranjo de R3 e de R4 COMITA antes da corrida: uma linha não comitada nesta sessão é invisível para A e para B, e a espera de A por ela travaria este próprio teste)
do $$
declare v_c uuid; v_v text;
begin
  if current_setting('ffc.sem_dblink', true) = '1' then return; end if;
  select id into v_c from caso where nome = '0243 corrida R3';
  v_v := (fn_registrar_documento(v_c, 'DOC R3 UM LTDA', 'anual', '2025', 'DRE', 0.97, 'nome_arquivo', 'supabase_storage', 'r3/a.pdf', 'r3a.pdf', true, 'r3hash', 'ok')->>'documento_versao_id');
  perform fn_registrar_campos_extraidos(v_v::uuid, '[{"chave":"Receita de vendas","valor_num":"100","secao_canonica":"receita_bruta","periodo_coluna":"2025","confianca":"0.97"},{"chave":"Custo","valor_num":"-40","secao_canonica":"custos","periodo_coluna":"2025","confianca":"0.97"}]'::jsonb);
  select id into v_c from caso where nome = '0243 corrida R4';
  v_v := (fn_registrar_documento(v_c, 'PEND R4 LTDA', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage', 'r4/a.pdf', 'r4a.pdf', true, 'r4hash', 'ok')->>'documento_versao_id');
  perform fn_registrar_campos_extraidos(v_v::uuid, '[{"chave":"Clientes R4a","valor_num":"1","secao":"ATIVO CIRCULANTE","periodo_coluna":"2025","confianca":"0.97"}]'::jsonb);
  perform fn_registrar_documento(v_c, 'PEND R4 LTDA', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage', 'r4/b.pdf', 'r4b.pdf', true, 'r4hash', 'ok');
  perform fn_registrar_documento(v_c, 'PEND R4 LTDA', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage', 'r4/c.pdf', 'r4c.pdf', true, 'r4hash', 'ok');
end $$;

do $$
declare v_c uuid; v_v text; v_doc uuid; v_um uuid; v_dois uuid; v_d text; v_t timestamptz;
begin
  if current_setting('ffc.sem_dblink', true) = '1' then return; end if;
  raise notice '--- R3: update de documento não comitado (A) x cadastro de entidade e de período (B) ---';
  select id into v_c from caso where nome = '0243 corrida R3';
  select id into v_um from entidade where caso_id = v_c and razao_social = 'DOC R3 UM LTDA';
  select id into v_dois from entidade where caso_id = v_c and razao_social = 'DOC R3 DOIS LTDA';
  select dv.id::text, dv.documento_id into v_v, v_doc from documento_versao dv join documento d on d.id = dv.documento_id where d.caso_id = v_c and dv.n_versao = 1;
  perform ff_dblink.dblink_exec('a', 'begin');
  perform ff_dblink.dblink_exec('a', format($q$update documento set entidade_id = %L where id = %L$q$, v_dois, v_doc));
  v_t := clock_timestamp();
  perform ff_dblink.dblink_exec('b', format($q$insert into entidade (caso_id, razao_social) values (%L, 'DOC R3 TRES LTDA')$q$, v_c));
  perform ff_dblink.dblink_exec('b', format($q$insert into periodo (caso_id, tipo, referencia) values (%L, 'anual', '2023')$q$, v_c));
  perform pg_temp.teste_assert_ffc(clock_timestamp() - v_t < interval '3 seconds', 'R3: o cadastro de entidade e de período de B NÃO espera o lock do documento de A (não há gatilho de cadastro que o segure)', (clock_timestamp() - v_t)::text);
  v_d := pg_temp.dif(v_v::uuid, array['Receita de vendas|2025|-|100|receita_bruta|DOC R3 UM LTDA|-|2025|-', 'Custo|2025|-|-40|custos|DOC R3 UM LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ffc(v_d = '', 'R3: com o update de A não comitado a leitura mostra a entidade COMITADA (a UM) — escrito à mão', v_d);
  perform ff_dblink.dblink_exec('a', 'commit');
  v_d := pg_temp.dif(v_v::uuid, array['Receita de vendas|2025|-|100|receita_bruta|DOC R3 DOIS LTDA|-|2025|-', 'Custo|2025|-|-40|custos|DOC R3 DOIS LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ffc(v_d = '', 'R3: depois do commit de A, TODOS os fatos do documento são da entidade nova (a DOIS), nenhum com a antiga (antes: 177 com a antiga) — escrito à mão', v_d);
end $$;

-- R4: a pendência. Duas extrações concorrentes de duas versões do MESMO documento (a v2 e a v3, registradas e comitadas, ainda sem linhas): a sessão A extrai a v2 e NÃO comita; a sessão B extrai a v3 (assíncrona: o gatilho espera a trava do documento). Depois que A comita, B avalia com o estado novo.
-- Esperado: UMA pendência aberta no documento (a da vigente, v3); a da v2 e a da v1 baixadas.
do $$
declare v_c uuid; v_v1 uuid; v_v2 uuid; v_v3 uuid; v_doc uuid; v_abertas int; v_busy int; v_r text;
begin
  if current_setting('ffc.sem_dblink', true) = '1' then return; end if;
  raise notice '--- R4: duas extrações concorrentes do mesmo documento (a pendência) ---';
  select id into v_c from caso where nome = '0243 corrida R4';
  select dv.id, dv.documento_id into v_v1, v_doc from documento_versao dv join documento d on d.id = dv.documento_id where d.caso_id = v_c and dv.n_versao = 1;
  select dv.id into v_v2 from documento_versao dv where dv.documento_id = v_doc and dv.n_versao = 2;
  select dv.id into v_v3 from documento_versao dv where dv.documento_id = v_doc and dv.n_versao = 3;
  perform pg_temp.teste_assert_ffc(v_v2 is not null and v_v3 is not null and (select count(*) from pendencia where documento_id = v_doc and tipo = 'conta_canonica_incerta' and estado = 'aberta') = 1, 'arranjo: três versões do documento, e só a v1 (extraída) tem a sua pendência aberta');
  perform ff_dblink.dblink_exec('a', 'begin');
  perform pg_temp.via('a', format($q$select fn_registrar_campos_extraidos(%L::uuid, '[{"chave":"Clientes R4b","valor_num":"2","secao":"ATIVO CIRCULANTE","periodo_coluna":"2025","confianca":"0.97"}]'::jsonb)::text$q$, v_v2));
  perform ff_dblink.dblink_send_query('b', format($q$select fn_registrar_campos_extraidos(%L::uuid, '[{"chave":"Clientes R4c","valor_num":"3","secao":"ATIVO CIRCULANTE","periodo_coluna":"2025","confianca":"0.97"}]'::jsonb)::text$q$, v_v3));
  perform pg_sleep(1.5);
  v_busy := ff_dblink.dblink_is_busy('b');
  perform pg_temp.teste_assert_ffc(v_busy = 1, 'R4: a extração da v3 (sessão B) ESPERA a trava do documento enquanto A não comitou', v_busy::text);
  perform ff_dblink.dblink_exec('a', 'commit');
  select t.x into v_r from ff_dblink.dblink_get_result('b') as t(x text);
  perform pg_temp.teste_assert_ffc(v_r is not null, 'arranjo: a extração da v3 (sessão B) terminou depois do commit de A', v_r);
  select count(*) into v_abertas from pendencia where documento_id = v_doc and tipo = 'conta_canonica_incerta' and estado = 'aberta';
  perform pg_temp.teste_assert_ffc(fn_versao_atual(v_doc) = v_v3, 'arranjo: a v3 é a versão vigente', fn_versao_atual(v_doc)::text);
  perform pg_temp.teste_assert_ffc(v_abertas = 1 and exists (select 1 from pendencia p where p.documento_id = v_doc and p.tipo = 'conta_canonica_incerta' and p.estado = 'aberta' and p.motivo = 'fato:conta_incerta:' || v_v3),
    'R4: depois das duas extrações concorrentes há UMA pendência aberta no documento, a da vigente (v3); a da v2 e a da v1 foram baixadas (sem a trava do documento ficavam duas abertas)', v_abertas || ' abertas');
end $$;

-- 9. LIMPEZA: o que este arquivo criou (comitado) sai. As conexões fecham.
do $$
begin
  if current_setting('ffc.sem_dblink', true) = '1' then return; end if;
  delete from caso where nome like '0243 corrida %';
  perform ff_dblink.dblink_disconnect('a'); perform ff_dblink.dblink_disconnect('b');
  perform pg_temp.teste_assert_ffc(not exists (select 1 from caso where nome like '0243 corrida %'), 'a limpeza: nenhum mandato de corrida sobrou');
end $$;
do $$ begin
  if current_setting('ffc.sem_dblink', true) is distinct from '1' then
    drop extension if exists dblink;
    drop schema if exists ff_dblink;
  end if;
end $$;

do $$
declare v_exec bigint := (select last_value from pg_temp._execucoes_ffc); v_falhas bigint;
begin
  if current_setting('ffc.sem_dblink', true) = '1' then
    raise notice 'fato_financeiro_corridas: NÃO EXECUTADO (sem dblink): 0 asserts executados — isto NÃO é um teste verde';
    return;
  end if;
  select case when is_called then last_value else 0 end into v_falhas from pg_temp._falhas_ffc;
  raise notice 'fato_financeiro_corridas: % asserts executados, % reprovados', v_exec, v_falhas;
  if v_falhas > 0 and coalesce(current_setting('ff.medindo', true), '') <> 'on' then
    raise exception 'FALHOU: % assert(s) das corridas da 0243 reprovaram (veja os FALHOU acima)', v_falhas;
  end if;
  if v_falhas = 0 then raise notice 'TODOS OS TESTES DAS CORRIDAS DO FATO FINANCEIRO PASSARAM'; end if;
end $$;
