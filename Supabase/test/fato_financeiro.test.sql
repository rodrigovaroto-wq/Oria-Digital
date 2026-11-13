-- Testes da 0243 (Supabase/migrations/0243_a_linha_que_nao_tinha_identidade.sql): fato_financeiro como VIEW security_invoker sobre fn_fato_resolver, acima de campo_extraido (P27, Fase 3, etapa 3.2).
-- Rodar via Supabase/test/run.sh (as fixtures de vertentes e canastra já estão carregadas). Tudo que escreve corre numa transação que é DESFEITA no fim: o banco fica como estava para os testes seguintes. A ÚNICA exceção é o topo (fora da transação): ele reaplica a migration duas vezes e liga/desliga o default de privilégio do Supabase, e
-- este arquivo o restaura no fim. As corridas (duas sessões reais) estão em Supabase/test/fato_financeiro_corridas.test.sql: não cabem numa transação.
--
-- O QUE ESTE ARQUIVO PROVA (comportamento, regra 3):
--   (a) FATO ESCRITO À MÃO: em cada cenário das 5 revisões a conta, a entidade, o período, o motivo e o valor de CADA linha estão escritos aqui, um a um, e a leitura da view tem de ser IGUAL a eles nos dois sentidos (faltam / sobram). "A view é igual ao resolver" seria tautologia: a view É o resolver. Os cenários: 1.310 (balancete de seis colunas), 500 e 435 e 342 (balancete e DRE de junho,
--       colunas de mês e de data), ALFA/Beta/Eliminações/Consolidado (o COMBINADO), "Alfa Comércio" x a razão social, "Alfa Comércio Atacado" x "Alfa Comércio" nas duas ordens de gravação, Saldo Final + Saldo Atual, 2025 + 31/12/2025, balancete parcial, DRE -> BALANCETE, a fusão Atacado -> ALFA e Imóveis -> Metalúrgica (a coluna do absorvido fica sem dono, com o motivo), a gravação em duas chamadas,
--       a seção e o valor alterados por reparo, a transcrição humana, a entidade renomeada e cadastrada depois, o período cadastrado depois, a ordem real do n8n (documento sem entidade e sem período no momento da extração);
--   (b) a BIJEÇÃO: toda linha elegível tem fato e nenhum fato existe para o que não é elegível (o elegível é reescrito AQUI, sem perguntar à função da migration), sem duplicata, sobre as fixtures; a view dá o mesmo que o resolver do zero (sanidade) e a leitura por mandato e por versão PODA o cálculo (a contagem de chamadas do resolver: 1 por versão que sobra);
--   (c) a PENDÊNCIA conta_canonica_incerta: uma por documento-versão, só para extração NOVA (nenhuma para o que já estava gravado nem para a transcrição humana nem para a troca de tipo), a versão superada baixa, o que a pessoa decidiu não reabre, a falha da pendência não derruba a extração e o cancelamento não é engolido;
--   (d) a SEGURANÇA: o authenticated lê só o próprio mandato, o anon nada, o service_role tudo, o leitor só-leitura lê a sonda, NINGUÉM escreve na view; tudo sob o default de privilégio do Supabase SIMULADO (de tabela e de função: a view e as funções são descartadas e a migration reaplicada com o default ligado) e sob um ACL ESTRITO de função (sem EXECUTE de PUBLIC nas 17 funções da cadeia);
--   (e) a ORDEM: o `ln` da 0270 continua gravado e a pendência abre mesmo depois de fn_registrar_campos_extraidos ser reemitida; a reaplicação da migration é idempotente (as definições, as permissões e o catálogo não mudam); só existe UM gatilho da 0243;
--   (f) a SONDA: os 20 requisitos presentes e ela ACUSA cada guarda removida (security_invoker desligado, o resolver como definer, privilégio de escrita, o anon lendo, a cadeia, o gatilho, o corpo do resolver).
--
-- HONESTIDADE (regra 4): as fixtures de vertentes e canastra são sintéticas e não trazem o arranjo que produção traz de linhas com entidade_coluna sem entidade cadastrada nem o de duas colunas de ano de um balanço real; os cenários usam linhas sintéticas porque provam a REGRA de resolução (qual coluna vence), não reproduzem um documento do cliente.
-- Dois cenários dependem de a função do banco escolher entre colunas total SEM ordem (fn_coluna_entidade): lá o teste afirma só o que não depende da escolha (nenhuma entidade recebe valor, todas as linhas com motivo).
--
-- NÃO PARA NO PRIMEIRO ERRO: anota e segue, e o bloco final reprova com a CONTAGEM (regra 2). `PGOPTIONS='-c ff.medindo=on'` só tira o `raise exception` do fim (para a medição por sabotagem).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número que reprova por sabotagem, parte a parte, está no cabeçalho de Supabase/migrations/0243_a_linha_que_nao_tinha_identidade.sql.

\set ON_ERROR_STOP on

-- ===========================================================================================================
-- TOPO (fora da transação). A reaplicação #1 prova a IDEMPOTÊNCIA; a #2, com o default de privilégio do Supabase ligado, prova que a migration NORMALIZA o ACL.
-- (a medição por sabotagem roda uma cópia deste arquivo SEM este bloco: senão a migration desfaria a sabotagem)
-- ===========================================================================================================
create or replace function pg_temp.acl_txt(p_acl aclitem[]) returns text language sql as $f$
  select coalesce((select string_agg(x, ',' order by x) from (select case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end || ':' || a.privilege_type as x from aclexplode(p_acl) a) q), '-')
$f$;
create or replace function pg_temp.assinatura() returns text language sql as $f$
  select md5(string_agg(x, E'\n' order by x)) from (
    select 'view|' || pg_get_viewdef(c.oid) || '|' || pg_temp.acl_txt(c.relacl) || '|' || coalesce(c.reloptions::text, '-') as x from pg_class c where c.oid = 'public.fato_financeiro'::regclass
    union all
    select 'fn|' || p.oid::regprocedure::text || '|' || pg_get_functiondef(p.oid) || '|' || pg_temp.acl_txt(p.proacl)
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in ('fn_fato_resolver', 'fn_fato_pendencia_da_versao', 'fn_fato_pendencia_da_extracao', 'fn_fato_pode_escrever', 'fn_fato_ator', 'fn_tipo_gera_fato', 'fn_linha_vira_fato', 'fn_fato_sonda_recentes')
    union all
    select 'trg|' || pg_get_triggerdef(t.oid) from pg_trigger t where t.tgname = 'trg_fato_pendencia_da_extracao' and not t.tgisinternal
    union all
    select 'req|' || r::text from instalacao_requisito r where r.migration = '0243') z
$f$;
select pg_temp.assinatura() as h0 \gset
\i Supabase/migrations/0243_a_linha_que_nao_tinha_identidade.sql
select pg_temp.assinatura() as h1 \gset

-- o default de privilégio do Supabase (ALL em tabela, view e sequência; EXECUTE em função, para anon, authenticated e service_role), ligado para o dono atual, e a view e as funções DESCARTADAS: a migration as recria como um projeto novo as recriaria.
do $$ begin
  execute format('alter default privileges for role %I in schema public grant all on tables to anon, authenticated, service_role', current_user);
  execute format('alter default privileges for role %I in schema public grant all on sequences to anon, authenticated, service_role', current_user);
  execute format('alter default privileges for role %I in schema public grant execute on functions to anon, authenticated, service_role', current_user);
end $$;
drop trigger trg_fato_pendencia_da_extracao on evento_auditoria;
drop view fato_financeiro, instalacao_sonda_fato_financeiro_view_invoker, instalacao_sonda_fato_financeiro_so_le, instalacao_sonda_fato_financeiro_recentes, instalacao_sonda_fato_financeiro_cadeia, instalacao_sonda_fato_financeiro_pendencia_tipo, instalacao_sonda_fato_financeiro_tipos;
drop function fn_fato_sonda_recentes(), fn_fato_pendencia_da_extracao(), fn_fato_pendencia_da_versao(uuid), fn_fato_resolver(uuid), fn_linha_vira_fato(text, text, text, numeric), fn_tipo_gera_fato(text), fn_fato_pode_escrever(uuid), fn_fato_ator();
\i Supabase/migrations/0243_a_linha_que_nao_tinha_identidade.sql
select pg_temp.assinatura() as h2 \gset
-- o que o default concedeu ao ANON e a quem não devia, ANTES de qualquer teste: a view e o resolver (os asserts abaixo; aqui só os fatos de arranjo)
select has_table_privilege('anon', 'public.fato_financeiro'::regclass, 'select') as anon_le_a_view,
       has_table_privilege('authenticated', 'public.fato_financeiro'::regclass, 'insert') as auth_insere_na_view,
       has_function_privilege('anon', 'fn_fato_resolver(uuid)', 'execute') as anon_executa_o_resolver,
       has_function_privilege('authenticated', 'fn_fato_pendencia_da_versao(uuid)', 'execute') as auth_executa_a_pendencia,
       has_function_privilege('authenticated', 'fn_fato_pode_escrever(uuid)', 'execute') as auth_executa_a_guarda \gset
-- devolve o banco ao que era (o default liga-se só para isto) — antes da transação, para o ROLLBACK do teste não o desfazer pela metade
do $$ begin
  execute format('alter default privileges for role %I in schema public revoke all on tables from anon, authenticated, service_role', current_user);
  execute format('alter default privileges for role %I in schema public revoke all on sequences from anon, authenticated, service_role', current_user);
  execute format('alter default privileges for role %I in schema public revoke execute on functions from anon, authenticated, service_role', current_user);
end $$;
select set_config('ff.h0', :'h0', false) as g0, set_config('ff.h1', :'h1', false) as g1, set_config('ff.h2', :'h2', false) as g2,
       set_config('ff.default_acl', concat_ws(',', :'anon_le_a_view', :'auth_insere_na_view', :'anon_executa_o_resolver', :'auth_executa_a_pendencia', :'auth_executa_a_guarda'), false) as g3 \gset

begin;

create temp sequence _falhas_0243;
create temp sequence _execucoes_0243;

create or replace function pg_temp.teste_assert_ff(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform nextval('pg_temp._execucoes_0243');
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  else
    raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
    perform nextval('pg_temp._falhas_0243');
  end if;
end $$;

-- O FATO COMO TEXTO, uma linha por fato: chave|coluna de período|coluna de entidade|valor|conta|entidade|motivo da entidade|período|motivo do período. Nulo é '-'. A conta de linha sem conta é `sem_conta:<motivo>`; a heurística leva ` (heuristica)` depois da conta.
create or replace function pg_temp.atual(p_versao uuid) returns text[] language sql as $$
  select coalesce(array_agg(x order by x), '{}'::text[]) from (
    select ce.chave || '|' || coalesce(nullif(btrim(ce.periodo_coluna), ''), '-') || '|' || coalesce(nullif(btrim(ce.entidade_coluna), ''), '-') || '|' || trim_scale(f.valor)::text
           || '|' || coalesce(f.conta_id, 'sem_conta:' || f.sem_conta_motivo) || case when f.resolucao_metodo = 'heuristica' then ' (heuristica)' else '' end
           || '|' || coalesce(e.razao_social, '-') || '|' || coalesce(f.entidade_motivo, '-') || '|' || coalesce(p.referencia, '-') || '|' || coalesce(f.periodo_motivo, '-') as x
      from fato_financeiro f
      join campo_extraido ce on ce.id = f.campo_extraido_id
      left join entidade e on e.id = f.entidade_id
      left join periodo p on p.id = f.periodo_id
     where f.documento_versao_id = p_versao) z
$$;
-- '' quando o fato lido é IGUAL ao esperado (nos dois sentidos); senão diz o que falta e o que sobra.
create or replace function pg_temp.dif(p_versao uuid, p_esperado text[]) returns text language sql as $$
  select coalesce((select 'FALTAM: ' || string_agg(x, ' ;; ') from (select unnest(p_esperado) x except all select unnest(pg_temp.atual(p_versao))) a having count(*) > 0), '')
      || coalesce((select ' || SOBRAM: ' || string_agg(x, ' ;; ') from (select unnest(pg_temp.atual(p_versao)) x except all select unnest(p_esperado)) b having count(*) > 0), '')
$$;

-- O ELEGÍVEL, reescrito AQUI de propósito (e não pela fn_linha_vira_fato da migration): um teste que pergunta ao código o que o código acha elegível protege o bug (regra 3).
create temp view _elegiveis as
  select ce.id as campo_id, ce.documento_versao_id, d.tipo_taxonomia as tipo, ce.secao_canonica, ce.secao_canonica_inferida as inferida
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
   where ce.valor_num is not null
     and d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DRE', 'FLUXO_CAIXA', 'DVA', 'DMPL', 'DF_AUDITADA')
     and fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) = 'conta';

-- Registra um documento de demonstração e grava as linhas pelo caminho do n8n; devolve a versão.
create or replace function pg_temp.doc(p_caso uuid, p_ent text, p_per text, p_tipo text, p_hash text, p_campos jsonb, p_ptipo text default 'anual') returns uuid
language plpgsql as $$
declare v uuid;
begin
  v := (fn_registrar_documento(p_caso, p_ent, p_ptipo, p_per, p_tipo, 0.97, 'nome_arquivo', 'supabase_storage', '0243/' || p_hash || '.pdf', p_hash || '.pdf', true, p_hash, 'ok')->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v, p_campos);
  return v;
end $$;

create or replace function pg_temp.l(p_chave text, p_valor text, p_secao_canonica text default null, p_secao text default null, p_pcol text default null, p_ecol text default null) returns jsonb
language sql as $$
  select jsonb_strip_nulls(jsonb_build_object('chave', p_chave, 'valor_num', p_valor, 'secao_canonica', p_secao_canonica, 'secao', p_secao, 'periodo_coluna', p_pcol, 'entidade_coluna', p_ecol, 'confianca', '0.97'))
$$;

-- QUANTAS VEZES fn_papel_linha foi chamada nesta transação (pg_stat_xact_user_functions; track_functions ligado só aqui). O resolver é SQL e o planejador o INLINA na consulta (por isso ele não aparece na estatística de função), mas fn_papel_linha roda UMA vez por
-- (tipo, rótulo, unidade) distintos de cada versão que o resolver lê: contar as chamadas dela é contar o que foi lido, e comparar com o que o filtro deveria deixar (calculado por SQL independente) prova a PODA.
set local track_functions = 'all';
create or replace function pg_temp.chamadas_do_papel() returns bigint language sql as $$
  select coalesce((select calls from pg_stat_xact_user_functions where funcname = 'fn_papel_linha'), 0)
$$;
-- o que o resolver DEVE ler para as versões de demonstração de um mandato (nulo = todos): os (rótulo, unidade) distintos de cada versão, com valor
create or replace function pg_temp.papel_esperado(p_caso uuid) returns bigint language sql as $$
  select coalesce(sum(n), 0) from (
    select dv.id, count(distinct (ce.chave, ce.unidade)) as n
      from campo_extraido ce join documento_versao dv on dv.id = ce.documento_versao_id join documento d on d.id = dv.documento_id
     where (p_caso is null or d.caso_id = p_caso) and ce.valor_num is not null and d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DRE', 'FLUXO_CAIXA', 'DVA', 'DMPL', 'DF_AUDITADA')
     group by dv.id) z
$$;

-- A INVARIANTE DA FAMÍLIA: em NENHUM documento duas colunas diferentes caem na mesma (conta, entidade, período) não nulos (é o que fazia a soma dobrar).
create or replace function pg_temp.colunas_na_mesma_chave() returns bigint language sql as $f$
  select count(*) from (
    select f.documento_versao_id, f.conta_id, f.entidade_id, f.periodo_id
      from fato_financeiro f
     where f.conta_id is not null and f.entidade_id is not null and f.periodo_id is not null
     group by 1, 2, 3, 4
    having count(distinct coalesce(f.periodo_coluna, '') || '|' || coalesce(f.entidade_coluna, '')) > 1) x
$f$;
-- afirmada depois de cada cenário que muda o que o fato lê: a invariante, o mesmo mandato e a identidade explicada, sobre TUDO que a view mostra. Devolve '' quando vale; senão o que falhou (quem chama afirma).
create or replace function pg_temp.inv() returns text language plpgsql as $f$
declare v_c bigint; v_m bigint; v_e bigint;
begin
  v_c := pg_temp.colunas_na_mesma_chave();
  select count(*) into v_m from fato_financeiro f join documento_versao dv on dv.id = f.documento_versao_id join documento d on d.id = dv.documento_id
   where (f.entidade_id is not null and not exists (select 1 from entidade e where e.id = f.entidade_id and e.caso_id = d.caso_id))
      or (f.periodo_id is not null and not exists (select 1 from periodo p where p.id = f.periodo_id and p.caso_id = d.caso_id));
  select count(*) into v_e from fato_financeiro where (entidade_id is null) <> (entidade_motivo is not null) or (periodo_id is null) <> (periodo_motivo is not null);
  if v_c = 0 and v_m = 0 and v_e = 0 then return ''; end if;
  return v_c || ' chave(s) com duas colunas; ' || v_m || ' de outro mandato; ' || v_e || ' nulo sem motivo';
end $f$;

-- ---------------------------------------------------------------------------------------------------------------
-- b. A BIJEÇÃO sobre as fixtures (e a poda do cálculo): toda linha elegível tem fato, e só ela; a view é o que o resolver do zero dá; ler um mandato ou uma versão só resolve as versões que sobram.
do $$
declare
  v_el int; v_tipos int; v_n int; v_n2 int; v_caso uuid := '11111111-1111-1111-1111-111111111111'; v_versao uuid; c0 bigint; c1 bigint; v_esperado bigint;
begin
  raise notice '--- b. a bijeção sobre as fixtures (toda linha elegível tem fato; só ela) ---';
  select count(*), count(distinct tipo) into v_el, v_tipos from _elegiveis;
  perform pg_temp.teste_assert_ff(v_el >= 1000 and v_tipos >= 4, 'as fixtures trazem linhas elegíveis para medir (o laço abaixo não corre sobre o vazio)', v_el || ' linhas em ' || v_tipos || ' tipos');
  select count(*) into v_n from fato_financeiro;
  perform pg_temp.teste_assert_ff(v_n = v_el, 'fatos = linhas elegíveis (bijeção)', v_n || ' x ' || v_el);
  perform pg_temp.teste_assert_ff(not exists (select 1 from _elegiveis e where not exists (select 1 from fato_financeiro f where f.campo_extraido_id = e.campo_id)), 'TODA linha elegível tem fato');
  select count(*) into v_n from fato_financeiro f where not exists (select 1 from _elegiveis e where e.campo_id = f.campo_extraido_id);
  perform pg_temp.teste_assert_ff(v_n = 0, 'e nenhum fato existe para linha que não é elegível', v_n::text);
  select count(*) into v_n from (select campo_extraido_id from fato_financeiro group by 1 having count(*) > 1) x;
  perform pg_temp.teste_assert_ff(v_n = 0, 'nenhuma evidência tem dois fatos', v_n::text);
  select count(*) into v_n from fato_financeiro where id <> campo_extraido_id;
  perform pg_temp.teste_assert_ff(v_n = 0, 'a identidade do fato é a da linha extraída (id = campo_extraido_id)', v_n::text);
  perform pg_temp.teste_assert_ff((select count(distinct documento_versao_id) from fato_financeiro) >= 20, 'os fatos vêm de várias versões de documento', (select count(distinct documento_versao_id) from fato_financeiro)::text);
  select count(*) into v_n from (select campo_id, documento_versao_id, conta_id, resolucao_metodo, sem_conta_motivo, entidade_id, entidade_origem, entidade_motivo, entidade_coluna, periodo_id, periodo_origem, periodo_motivo, periodo_coluna, valor, unidade, moeda from fn_fato_resolver(null)
     except select campo_extraido_id, documento_versao_id, conta_id, resolucao_metodo, sem_conta_motivo, entidade_id, entidade_origem, entidade_motivo, entidade_coluna, periodo_id, periodo_origem, periodo_motivo, periodo_coluna, valor, unidade, moeda from fato_financeiro) x;
  select count(*) into v_n2 from (select campo_extraido_id, documento_versao_id, conta_id, resolucao_metodo, sem_conta_motivo, entidade_id, entidade_origem, entidade_motivo, entidade_coluna, periodo_id, periodo_origem, periodo_motivo, periodo_coluna, valor, unidade, moeda from fato_financeiro
     except select campo_id, documento_versao_id, conta_id, resolucao_metodo, sem_conta_motivo, entidade_id, entidade_origem, entidade_motivo, entidade_coluna, periodo_id, periodo_origem, periodo_motivo, periodo_coluna, valor, unidade, moeda from fn_fato_resolver(null)) x;
  perform pg_temp.teste_assert_ff(v_n = 0 and v_n2 = 0, 'sanidade: a view dá, versão a versão, o MESMO que o resolver do zero dá de uma vez (a junção lateral não vaza identidade entre versões)', v_n || ' só no resolver; ' || v_n2 || ' só na view');

  raise notice '--- b2. ler um mandato ou uma versão só resolve o que sobra (o filtro entra no cálculo) ---';
  v_esperado := pg_temp.papel_esperado(v_caso);
  perform pg_temp.teste_assert_ff(v_esperado >= 100 and v_esperado < pg_temp.papel_esperado(null), 'arranjo: o mandato das fixtures tem muitos rótulos a ler, e não é o banco inteiro', v_esperado || ' de ' || pg_temp.papel_esperado(null));
  c0 := pg_temp.chamadas_do_papel();
  select count(*) into v_n from fato_financeiro where caso_id = v_caso;
  c1 := pg_temp.chamadas_do_papel();
  perform pg_temp.teste_assert_ff(v_n > 100 and c1 - c0 = v_esperado, 'where caso_id = X: o resolver lê SÓ as versões do mandato (fn_papel_linha roda uma vez por rótulo de cada versão dele, nenhuma de outro)', 'chamadas ' || (c1 - c0) || ', esperado ' || v_esperado || '; fatos ' || v_n);
  select dv.id into v_versao from fato_financeiro f join documento_versao dv on dv.id = f.documento_versao_id where f.caso_id = v_caso group by dv.id order by count(*) desc limit 1;
  c0 := pg_temp.chamadas_do_papel();
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_versao;
  c1 := pg_temp.chamadas_do_papel();
  perform pg_temp.teste_assert_ff(v_n > 20 and c1 - c0 = (select count(distinct (ce.chave, ce.unidade)) from campo_extraido ce where ce.documento_versao_id = v_versao and ce.valor_num is not null),
    'where documento_versao_id = X: o resolver lê SÓ essa versão', 'chamadas ' || (c1 - c0) || '; fatos ' || v_n);
  c0 := pg_temp.chamadas_do_papel();
  select count(*) into v_n from fato_financeiro where conta_id = 'ativo_circulante';
  c1 := pg_temp.chamadas_do_papel();
  perform pg_temp.teste_assert_ff(c1 - c0 = pg_temp.papel_esperado(null), 'filtrar por conta NÃO poda (lê todas as versões que o usuário enxerga): o custo que a P28 resolve com view materializada', (c1 - c0) || ' x ' || pg_temp.papel_esperado(null));
end $$;

-- b3. A conta e o método (a seção da linha; heurística; sem conta): sobre as fixtures.
do $$
declare v_n int; v_n2 int;
begin
  raise notice '--- b3. nenhum fato aponta para nó que não é seção; o método: declarada, heuristica, sem_conta ---';
  select count(*) into v_n from fato_financeiro f join conta_canonica c on c.codigo = f.conta_id where c.secao_canonica is null;
  perform pg_temp.teste_assert_ff(v_n = 0, 'nenhum fato aponta para raiz, grupo ou subgrupo', v_n::text);
  select count(*) into v_n from fato_financeiro f join conta_canonica c on c.codigo = f.conta_id where c.secao_canonica is not null;
  perform pg_temp.teste_assert_ff(v_n >= 1000, 'e há fatos com conta de seção (o assert acima não é sobre o vazio)', v_n::text);
  select count(*) into v_n from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id join conta_canonica c on c.codigo = f.conta_id where c.secao_canonica is distinct from ce.secao_canonica;
  perform pg_temp.teste_assert_ff(v_n = 0, 'a conta do fato é a seção que a linha traz, nunca outra', v_n::text);
  select count(*) into v_n from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where ce.secao_canonica_inferida;
  perform pg_temp.teste_assert_ff(v_n >= 1, 'as fixtures trazem linha com seção inferida elegível (o assert abaixo mede algo)', v_n::text);
  select count(*) into v_n from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where ce.secao_canonica_inferida and f.resolucao_metodo <> 'heuristica';
  perform pg_temp.teste_assert_ff(v_n = 0, 'linha com seção inferida é heuristica', v_n::text);
  select count(*) into v_n from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.resolucao_metodo = 'heuristica' and not ce.secao_canonica_inferida;
  perform pg_temp.teste_assert_ff(v_n = 0, 'e heuristica só existe para seção inferida', v_n::text);
  select count(*) into v_n from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.resolucao_metodo = 'declarada' and (ce.secao_canonica_inferida or ce.secao_canonica is null);
  perform pg_temp.teste_assert_ff(v_n = 0, 'declarada é só o que a IA deu', v_n::text);
  select count(*) into v_n from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where ce.secao_canonica = 'NAO_CLASSIFICAVEL';
  select count(*) into v_n2 from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where ce.secao_canonica = 'NAO_CLASSIFICAVEL' and f.resolucao_metodo = 'sem_conta' and f.conta_id is null and f.sem_conta_motivo = 'secao_nao_declarada';
  perform pg_temp.teste_assert_ff(v_n >= 1 and v_n = v_n2, 'o literal NAO_CLASSIFICAVEL das fixtures vira sem_conta (conta nula, secao_nao_declarada)', v_n2 || ' de ' || v_n);
  select count(*) into v_n from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where ce.secao_canonica is null;
  select count(*) into v_n2 from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where ce.secao_canonica is null and f.resolucao_metodo = 'sem_conta' and f.conta_id is null and f.sem_conta_motivo = 'secao_nao_declarada';
  perform pg_temp.teste_assert_ff(v_n >= 1 and v_n = v_n2, 'a seção nula (o que o extrator grava) é tratada IGUAL ao literal: sem_conta', v_n2 || ' de ' || v_n);
  select count(*) into v_n from fato_financeiro f where f.resolucao_metodo = 'sem_conta' and f.conta_id is not null;
  perform pg_temp.teste_assert_ff(v_n = 0, 'linha sem conta NÃO ganha conta (nem a raiz da demonstração pelo tipo do documento)', v_n::text);
  select count(*) into v_n from fato_financeiro f where f.resolucao_metodo = 'sem_conta';
  perform pg_temp.teste_assert_ff(v_n >= 100, 'e há linhas sem conta nas fixtures (o assert acima mede algo)', v_n::text);

  raise notice '--- f. o que continua só evidência ---';
  select count(*) into v_n from campo_extraido ce join documento_versao dv on dv.id = ce.documento_versao_id join documento d on d.id = dv.documento_id
   where d.tipo_taxonomia in ('ESTOQUE', 'RAZAO', 'AGING_AR', 'AGING_AP', 'MAPA_DIVIDA', 'NOTAS_EXPL', 'FATURAMENTO_24M', 'MUTUOS') and ce.valor_num is not null and fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) = 'conta';
  perform pg_temp.teste_assert_ff(v_n >= 100, 'as fixtures trazem linhas de papel conta em Estoque/Razão/Aging/Mapa de Dívida/Notas/Faturamento/Mútuos (o que fica de fora existe)', v_n::text);
  select count(*) into v_n from fato_financeiro f join documento_versao dv on dv.id = f.documento_versao_id join documento d on d.id = dv.documento_id
   where d.tipo_taxonomia not in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DRE', 'FLUXO_CAIXA', 'DVA', 'DMPL', 'DF_AUDITADA') or d.tipo_taxonomia is null;
  perform pg_temp.teste_assert_ff(v_n = 0, 'nenhum fato nasce de documento fora da lista de demonstrações', v_n::text);
  select count(*) into v_n from campo_extraido ce join documento_versao dv on dv.id = ce.documento_versao_id join documento d on d.id = dv.documento_id
   where d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DRE', 'FLUXO_CAIXA', 'DVA', 'DMPL', 'DF_AUDITADA') and ce.valor_num is not null and fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) = 'subtotal';
  perform pg_temp.teste_assert_ff(v_n >= 50, 'as fixtures trazem subtotais em demonstração (o assert seguinte mede algo)', v_n::text);
  select count(*) into v_n2 from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id join documento_versao dv on dv.id = ce.documento_versao_id join documento d on d.id = dv.documento_id
   where fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) <> 'conta';
  perform pg_temp.teste_assert_ff(v_n2 = 0, 'subtotal (e derivado, e série mensal) não vira fato: é a P28', v_n2::text);
  select count(*) into v_n from campo_extraido ce join documento_versao dv on dv.id = ce.documento_versao_id join documento d on d.id = dv.documento_id
   where d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DRE', 'FLUXO_CAIXA', 'DVA', 'DMPL', 'DF_AUDITADA') and ce.valor_num is null and fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) = 'conta';
  select count(*) into v_n2 from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where ce.valor_num is null;
  perform pg_temp.teste_assert_ff(v_n >= 1 and v_n2 = 0, 'linha de conta SEM valor (célula vazia) não vira fato: ausência não é zero (regra 1)', v_n || ' sem valor; ' || v_n2 || ' viraram fato');

  raise notice '--- c0. as fixtures (o que já estava gravado) NÃO ganham pendência: nenhuma extração nova as tocou ---';
  select count(distinct f.documento_versao_id) into v_n from fato_financeiro f where f.resolucao_metodo <> 'declarada' and f.caso_id in ('11111111-1111-1111-1111-111111111111', '11111111-3333-3333-3333-111111111111');
  select count(*) into v_n2 from pendencia where tipo = 'conta_canonica_incerta' and caso_id in ('11111111-1111-1111-1111-111111111111', '11111111-3333-3333-3333-111111111111');
  perform pg_temp.teste_assert_ff(v_n >= 5 and v_n2 = 0, 'há versões antigas com linha heurística ou sem conta (as fixtures) e NENHUMA pendência conta_canonica_incerta: o que já estava gravado não abre pendência', v_n || ' versões com linha incerta; ' || v_n2 || ' pendências');
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- d + g. A extração nova (o ponto do n8n), a pendência e a resolução de entidade e de período, sobre linhas sintéticas (a REGRA, não um documento do cliente). O fato esperado de cada linha está escrito à mão.
create or replace function pg_temp.reextrair(p_versao uuid) returns void language sql as $$
  -- o evento que fn_registrar_campos_extraidos grava no fim (a prova de que a extração RODOU): serve para disparar o gatilho outra vez sem acrescentar linha. (Sintético, e declarado: nas demais cenas a extração é a real.)
  insert into evento_auditoria (ator, acao, entidade_ref, depois) values ('sistema:n8n', 'extracao_sombra', 'documento_versao:' || p_versao, '{"campos": 0}'::jsonb)
$$;
do $$
declare
  v_caso uuid; v_a uuid; v_b uuid; v_b2 uuid; v_c uuid; v_d uuid; v_e uuid; v_f1 uuid; v_f2 uuid;
  v_n int; v_p25 uuid; v_p24 uuid; v_beta uuid; v_alfa uuid; v_pend record; v_ev jsonb; v_d_ text; v_pid uuid; v_doc uuid; v_desc text;
begin
  raise notice '--- d. a extração nova: o ponto do n8n (fn_registrar_campos_extraidos) ---';
  v_caso := (fn_upsert_caso('0243: fato da extração nova'))::uuid;
  v_alfa := fn_upsert_entidade(v_caso, 'ALFA P27 LTDA');
  v_beta := fn_upsert_entidade(v_caso, 'BETA P27 LTDA');
  v_p25 := fn_upsert_periodo(v_caso, 'anual', '2025');
  v_p24 := fn_upsert_periodo(v_caso, 'anual', '2024');

  -- A: só linhas DECLARADAS, com duas colunas de ano (2025 = período do documento; 2024 = outro, que o mandato TEM; 2023 = que o mandato NÃO tem), uma coluna de abertura, uma linha sem coluna, um subtotal e uma linha sem valor
  v_a := pg_temp.doc(v_caso, 'ALFA P27 LTDA', '2025', 'BALANCO', 'p27-a', jsonb_build_array(
    pg_temp.l('Caixa', '100', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'),
    pg_temp.l('Caixa', '90', 'ativo_circulante', 'ATIVO CIRCULANTE', '2024'),
    pg_temp.l('Fornecedores', '50', 'passivo_circulante', 'PASSIVO CIRCULANTE', '2023'),
    pg_temp.l('Capital social', '10', 'patrimonio_liquido', 'PATRIMÔNIO LÍQUIDO'),
    pg_temp.l('Caixa inicial', '70', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Inicial'),
    pg_temp.l('Total do ativo circulante', '190', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'),
    pg_temp.l('Estoques', 'n/d', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025')));
  v_d_ := pg_temp.dif(v_a, array[
    'Caixa|2025|-|100|ativo_circulante|ALFA P27 LTDA|-|2025|-',
    'Caixa|2024|-|90|ativo_circulante|ALFA P27 LTDA|-|2024|-',
    'Fornecedores|2023|-|50|passivo_circulante|ALFA P27 LTDA|-|-|periodo_da_coluna_nao_cadastrado',
    'Capital social|-|-|10|patrimonio_liquido|ALFA P27 LTDA|-|-|linha_sem_coluna_em_documento_com_colunas',
    'Caixa inicial|Saldo Inicial|-|70|ativo_circulante|ALFA P27 LTDA|-|-|coluna_de_abertura']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'A (balanço de 2025): 5 fatos escritos à mão (o subtotal e a linha sem valor ficam fora; 2023 sem período no mandato; abertura nula; linha sem coluna nula)', v_d_);
  perform pg_temp.teste_assert_ff(not exists (select 1 from periodo where caso_id = v_caso and fn_periodo_canonico(tipo, referencia) = '2023'), 'e o período 2023 NÃO foi criado pela leitura (a view não escreve nada)');
  select count(*) into v_n from pendencia where tipo = 'conta_canonica_incerta' and caso_id = v_caso;
  perform pg_temp.teste_assert_ff(v_n = 0, 'A: extração só com linhas declaradas abre 0 pendência', v_n::text);
  select count(*) into v_n from evento_auditoria where acao = 'fato_pendencia_avaliada' and entidade_ref = 'documento_versao:' || v_a;
  perform pg_temp.teste_assert_ff(v_n = 1, 'A: o evento fato_pendencia_avaliada prova que a avaliação da pendência RODOU (regra 7), uma vez', v_n::text);
  select count(*) into v_n from evento_auditoria where acao in ('fatos_materializados', 'fatos_recalculados', 'fatos_materializacao_falhou') and entidade_ref = 'documento_versao:' || v_a;
  perform pg_temp.teste_assert_ff(v_n = 0, 'A: e nenhum evento de materialização: o fato não é gravado, é lido');

  raise notice '--- d0. a 0243 NÃO toma conta de fn_registrar_campos_extraidos: o `ln` da 0270 continua gravado e a pendência abre ---';
  -- ARRANJO: este arquivo roda DEPOIS do teste da 0270 no run.sh (o 0270 reaplica a própria migration, então o corpo vigente é o da 0270); se alguém mover o bloco, a primeira linha abaixo reprova em vez de a prova sumir calada.
  perform pg_temp.teste_assert_ff(position('v_ln' in pg_get_functiondef('fn_registrar_campos_extraidos(uuid,jsonb,nivel_autonomia,text,boolean,jsonb)'::regprocedure)) > 0,
    'arranjo: o corpo vigente de fn_registrar_campos_extraidos é o da 0270 (grava ln); este teste tem de rodar depois do da 0270');
  perform pg_temp.teste_assert_ff(position('fn_fato' in pg_get_functiondef('fn_registrar_campos_extraidos(uuid,jsonb,nivel_autonomia,text,boolean,jsonb)'::regprocedure)) = 0
    and position('fato_financeiro' in pg_get_functiondef('fn_registrar_campos_extraidos(uuid,jsonb,nivel_autonomia,text,boolean,jsonb)'::regprocedure)) = 0,
    'fn_registrar_campos_extraidos NÃO conhece o fato: a pendência mora no gatilho, que nenhuma reemissão da função (a P11 a reemite a cada fatia) leva embora');
  v_f1 := pg_temp.doc(v_caso, 'ALFA P27 LTDA', '2025', 'BALANCO', 'p27-ln', jsonb_build_array(
    pg_temp.l('Caixa LN', '5', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025') || jsonb_build_object('ln', 7),
    pg_temp.l('Clientes LN', '6', null, 'ATIVO CIRCULANTE', '2025') || jsonb_build_object('ln', 0)));
  select ln into v_n from campo_extraido where documento_versao_id = v_f1 and chave = 'Caixa LN';
  perform pg_temp.teste_assert_ff(v_n = 7, 'o ln (0270) continua gravado na mesma chamada que a pendência: 7', coalesce(v_n::text, 'nulo'));
  perform pg_temp.teste_assert_ff((select ln from campo_extraido where documento_versao_id = v_f1 and chave = 'Clientes LN') is null, 'e o ln inválido (zero) continua virando nulo, como a 0270 deixou');
  v_d_ := pg_temp.dif(v_f1, array['Caixa LN|2025|-|5|ativo_circulante|ALFA P27 LTDA|-|2025|-', 'Clientes LN|2025|-|6|ativo_circulante (heuristica)|ALFA P27 LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '' and exists (select 1 from pendencia where motivo = 'fato:conta_incerta:' || v_f1 and estado = 'aberta'), 'a mesma chamada que grava o ln dá o fato certo (escrito à mão) e abre a pendência da linha inferida', v_d_);
  -- a sobrevivência: reemitir fn_registrar a partir do corpo vigente (o que a P11 faz) não derruba a pendência
  execute replace(pg_get_functiondef('fn_registrar_campos_extraidos(uuid,jsonb,nivel_autonomia,text,boolean,jsonb)'::regprocedure), 'v_count := v_count + 1;', 'v_count := v_count + 1; /* reemitida */');
  v_f2 := pg_temp.doc(v_caso, 'ALFA P27 LTDA', '2025', 'BALANCO', 'p27-ln2', jsonb_build_array(pg_temp.l('Clientes LN2', '8', null, 'ATIVO CIRCULANTE', '2025')));
  perform pg_temp.teste_assert_ff(exists (select 1 from pendencia where motivo = 'fato:conta_incerta:' || v_f2 and estado = 'aberta') and exists (select 1 from evento_auditoria where acao = 'fato_pendencia_avaliada' and entidade_ref = 'documento_versao:' || v_f2),
    'reemitida a fn_registrar_campos_extraidos (outra migration da P11), a pendência continua abrindo (o gatilho é do evento, não do corpo da função)');

  -- B: heurística (seção inferida do texto da seção bruta), sem seção, seção fora do catálogo, o literal, e colunas de entidade (o documento TEM colunas: as linhas sem coluna ficam sem dono)
  v_b := pg_temp.doc(v_caso, 'ALFA P27 LTDA', '2025', 'BALANCO', 'p27-b', jsonb_build_array(
    pg_temp.l('Caixa B', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'),
    pg_temp.l('Duplicatas a receber', '20', null, 'ATIVO CIRCULANTE', '2025'),
    pg_temp.l('Conta misteriosa', '30', null, 'Outros', '2025'),
    pg_temp.l('Conta com seção inventada', '40', 'inventada_xyz', 'Outros', '2025'),
    pg_temp.l('Conta escape', '5', 'NAO_CLASSIFICAVEL', 'Outros', '2025'),
    pg_temp.l('Linha da Beta', '7', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'BETA P27 LTDA'),
    pg_temp.l('Linha do combinado', '8', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Combinado'),
    pg_temp.l('Linha da eliminação', '-9', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Eliminações'),
    pg_temp.l('Linha de empresa que ninguém cadastrou', '11', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'GAMA SEM CADASTRO LTDA')));
  v_d_ := pg_temp.dif(v_b, array[
    'Caixa B|2025|-|10|ativo_circulante|-|linha_sem_coluna_em_documento_com_colunas_de_entidade|2025|-',
    'Duplicatas a receber|2025|-|20|ativo_circulante (heuristica)|-|linha_sem_coluna_em_documento_com_colunas_de_entidade|2025|-',
    'Conta misteriosa|2025|-|30|sem_conta:secao_nao_declarada|-|linha_sem_coluna_em_documento_com_colunas_de_entidade|2025|-',
    'Conta com seção inventada|2025|-|40|sem_conta:secao_fora_do_catalogo|-|linha_sem_coluna_em_documento_com_colunas_de_entidade|2025|-',
    'Conta escape|2025|-|5|sem_conta:secao_nao_declarada|-|linha_sem_coluna_em_documento_com_colunas_de_entidade|2025|-',
    'Linha da Beta|2025|BETA P27 LTDA|7|ativo_circulante|BETA P27 LTDA|-|2025|-',
    'Linha do combinado|2025|Combinado|8|ativo_circulante|ALFA P27 LTDA|-|2025|-',
    'Linha da eliminação|2025|Eliminações|-9|ativo_circulante|-|coluna_sem_entidade_no_mandato|2025|-',
    'Linha de empresa que ninguém cadastrou|2025|GAMA SEM CADASTRO LTDA|11|ativo_circulante|-|coluna_sem_entidade_no_mandato|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'B: 9 fatos escritos à mão (a conta: declarada, heurística, sem seção, seção fora do catálogo, o literal; a entidade: Beta, o Combinado do dono, Eliminações e empresa não cadastrada sem dono; a linha sem coluna num documento com colunas sem dono)', v_d_);

  select count(*) into v_n from pendencia where tipo = 'conta_canonica_incerta' and documento_id = (select documento_id from documento_versao where id = v_b) and estado = 'aberta';
  perform pg_temp.teste_assert_ff(v_n = 1, 'B: heurística + sem conta abrem EXATAMENTE 1 pendência para o documento-versão (e não 4, uma por linha)', v_n::text);
  select * into v_pend from pendencia where motivo = 'fato:conta_incerta:' || v_b;
  perform pg_temp.teste_assert_ff(v_pend.severidade = 'complementar' and v_pend.origem_estagio = 'extracao' and v_pend.caso_id = v_caso and v_pend.sobrepujavel, 'a pendência é complementar e sobrepujável, da extração, do mandato do documento', v_pend.severidade::text);
  perform pg_temp.teste_assert_ff(v_pend.descricao like '4 linha(s)%' and v_pend.descricao like '%Duplicatas a receber%' and v_pend.descricao like '%Conta misteriosa%' and v_pend.descricao like '%Conta com seção inventada%' and v_pend.descricao like '%sem identidade%',
    'a descrição conta as 4 linhas, lista os rótulos e diz o EFEITO (fato sem identidade não entra em seção nenhuma)', v_pend.descricao);
  v_pid := v_pend.id; v_desc := v_pend.descricao;

  -- o REENVIO do mesmo arquivo (mesmo hash) é a versão 2 do mesmo documento, com outra linha heurística: abre a SUA pendência e baixa a da v1
  v_b2 := pg_temp.doc(v_caso, 'ALFA P27 LTDA', '2025', 'BALANCO', 'p27-b', jsonb_build_array(
    pg_temp.l('Caixa B2', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'),
    pg_temp.l('Clientes B2', '12', null, 'ATIVO CIRCULANTE', '2025')));
  perform pg_temp.teste_assert_ff(v_b2 <> v_b and (select documento_id from documento_versao where id = v_b2) = (select documento_id from documento_versao where id = v_b), 'B2: é a segunda versão do MESMO documento (o arranjo do teste)');
  v_d_ := pg_temp.dif(v_b2, array['Caixa B2|2025|-|10|ativo_circulante|ALFA P27 LTDA|-|2025|-', 'Clientes B2|2025|-|12|ativo_circulante (heuristica)|ALFA P27 LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'B2: os 2 fatos da v2 escritos à mão (sem colunas de entidade: a do documento)', v_d_);
  select count(*) into v_n from pendencia where tipo = 'conta_canonica_incerta' and caso_id = v_caso and estado = 'aberta' and documento_id = (select documento_id from documento_versao where id = v_b);
  perform pg_temp.teste_assert_ff(v_n = 1 and exists (select 1 from pendencia where motivo = 'fato:conta_incerta:' || v_b2 and estado = 'aberta'), 'a v2 (a vigente) abre a SUA pendência, uma por documento-versão', v_n::text);
  perform pg_temp.teste_assert_ff((select resolvida_por from pendencia where id = v_pid) = 'sistema:versao_superada' and (select estado from pendencia where id = v_pid) = 'resolvida',
    'a pendência aberta da v1 SE BAIXA quando a v2 vira a vigente (versão superada), com o autor dizendo por quê');
  -- a v1 continua lendo o que sempre leu: a leitura de uma versão superada NÃO muda (todas as versões ficam na view)
  perform pg_temp.teste_assert_ff(array_length(pg_temp.atual(v_b), 1) = 9, 'a versão superada continua na view, com os mesmos 9 fatos (quem consome escolhe a vigente com fn_versao_atual)');

  -- reenvio: o gatilho de novo não duplica a pendência
  perform pg_temp.reextrair(v_b2);
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_b2;
  perform pg_temp.teste_assert_ff(v_n = 1 and exists (select 1 from pendencia where motivo = 'fato:conta_incerta:' || v_b2 and estado = 'aberta'), 'a extração de novo (o reenvio, o reparo) não duplica a pendência', v_n::text);
  perform pg_temp.reextrair(v_b);
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_b and estado = 'aberta';
  perform pg_temp.teste_assert_ff(v_n = 0, 'a versão superada, extraída de novo, NÃO reabre a pendência dela', v_n::text);

  -- o que a pessoa resolveu não reabre
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'ana@teste' where motivo = 'fato:conta_incerta:' || v_b2;
  perform pg_temp.reextrair(v_b2);
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_b2 and estado <> 'resolvida';
  perform pg_temp.teste_assert_ff(v_n = 0, 'pendência resolvida por PESSOA não é reaberta pela extração de novo', v_n::text);
  -- a que alguém está tratando (ou decidiu) não é tocada: nem reaberta, nem baixada pela auto-resolução, nem substituída
  update pendencia set estado = 'em_correcao_interna', resolvida_em = null, resolvida_por = null where motivo = 'fato:conta_incerta:' || v_b2;
  update campo_extraido set secao_canonica = 'ativo_circulante', secao_canonica_inferida = false where documento_versao_id = v_b2 and chave = 'Clientes B2';
  perform pg_temp.reextrair(v_b2);
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_b2 and estado = 'em_correcao_interna';
  perform pg_temp.teste_assert_ff(v_n = 1 and (select count(*) from pendencia where motivo = 'fato:conta_incerta:' || v_b2) = 1, 'a pendência em correção interna NÃO é baixada pela auto-resolução (só estado aberta)', v_n::text);
  -- e a leitura segue a linha na hora: a seção corrigida já é a conta declarada (nenhum recálculo a esperar)
  v_d_ := pg_temp.dif(v_b2, array['Caixa B2|2025|-|10|ativo_circulante|ALFA P27 LTDA|-|2025|-', 'Clientes B2|2025|-|12|ativo_circulante|ALFA P27 LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'a seção corrigida da linha já é a conta DECLARADA na leitura seguinte (a view não tem cópia para esperar recálculo)', v_d_);
  -- a convergência: aberta e sem linha incerta, a pendência da extração se resolve sozinha
  update pendencia set estado = 'aberta' where motivo = 'fato:conta_incerta:' || v_b2;
  perform pg_temp.reextrair(v_b2);
  perform pg_temp.teste_assert_ff((select estado from pendencia where motivo = 'fato:conta_incerta:' || v_b2) = 'resolvida' and (select resolvida_por from pendencia where motivo = 'fato:conta_incerta:' || v_b2) = 'sistema:extracao',
    'aberta e sem linha incerta, a pendência se resolve sozinha na extração seguinte (convergente)');

  -- C: só declaradas num DRE com subtotal; D: tipo fora da lista (Estoque)
  v_c := pg_temp.doc(v_caso, 'ALFA P27 LTDA', '2025', 'DRE', 'p27-c', jsonb_build_array(
    pg_temp.l('Venda de produtos', '1000', 'receita_bruta', 'RECEITA', '2025'),
    pg_temp.l('Receita líquida', '900', 'receita_bruta', 'RECEITA', '2025')));
  v_d_ := pg_temp.dif(v_c, array['Venda de produtos|2025|-|1000|receita_bruta|ALFA P27 LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'C (DRE): 1 fato; "Receita líquida" é subtotal e fica fora', v_d_);
  -- E: o ZERO é valor medido (regra 1: a célula VAZIA é ausência, o zero NÃO): a linha com 0 vira fato com valor 0; a linha vazia, não
  v_e := pg_temp.doc(v_caso, 'ALFA P27 LTDA', '2025', 'DRE', 'p27-z', jsonb_build_array(
    pg_temp.l('Receita zerada', '0', 'receita_bruta', 'RECEITA', '2025'),
    pg_temp.l('Deducoes', '-15', 'receita_bruta', 'RECEITA', '2025'),
    pg_temp.l('Outras receitas', '', 'receita_bruta', 'RECEITA', '2025')));
  v_d_ := pg_temp.dif(v_e, array['Receita zerada|2025|-|0|receita_bruta|ALFA P27 LTDA|-|2025|-', 'Deducoes|2025|-|-15|receita_bruta|ALFA P27 LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'E: o ZERO e o valor negativo viram fato (valor 0 e -15); a célula vazia ("Outras receitas") NÃO: ausência não é zero (regra 1) — escrito à mão', v_d_);
  v_d := pg_temp.doc(v_caso, 'ALFA P27 LTDA', '2025', 'ESTOQUE', 'p27-d', jsonb_build_array(
    pg_temp.l('Parafusos', '100', 'ativo_circulante', 'ESTOQUE', '2025'),
    pg_temp.l('Porcas', '50', null, 'ESTOQUE', '2025')));
  perform pg_temp.teste_assert_ff(array_length(pg_temp.atual(v_d), 1) is null, 'D (Estoque, tipo fora da lista): 0 fato');
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_d;
  perform pg_temp.teste_assert_ff(v_n = 0, 'D: e 0 pendência (linha sem seção de documento que não é demonstração não é fato sem identidade)', v_n::text);
  select count(*) into v_n from evento_auditoria where entidade_ref = 'documento_versao:' || v_d and acao in ('fato_pendencia_avaliada', 'fato_pendencia_falhou', 'fato_pendencia_negada');
  perform pg_temp.teste_assert_ff(v_n = 0, 'D: nem evento (o tipo não é de demonstração: não rodou e não finge)', v_n::text);

  raise notice '--- d. a falha da pendência NÃO derruba a extração; o cancelamento não é engolido ---';
  create function pg_temp.explode() returns trigger language plpgsql as $f$ begin raise exception 'pendência recusada de propósito (teste)'; end $f$;
  create trigger trg_explode before insert on pendencia for each row when (new.tipo = 'conta_canonica_incerta') execute function pg_temp.explode();   -- só a pendência desta migration (a extração abre outras, e a falha delas não é o assunto)
  v_e := (fn_registrar_documento(v_caso, 'ALFA P27 LTDA', 'anual', '2025', 'BALANCETE', 0.97, 'nome_arquivo', 'supabase_storage', '0243/p27-e.pdf', 'p27-e.pdf', true, 'p27-e', 'ok')->>'documento_versao_id')::uuid;
  begin
    v_n := fn_registrar_campos_extraidos(v_e, jsonb_build_array(pg_temp.l('Caixa sem seção E', '1', null, 'Outros', '2025')));
  exception when others then v_n := -1;   -- a falha da pendência derrubou a extração: o assert abaixo reprova (e o resto do arquivo segue)
  end;
  drop trigger trg_explode on pendencia;
  perform pg_temp.teste_assert_ff(v_n = 1 and (select count(*) from campo_extraido where documento_versao_id = v_e) = 1, 'a linha extraída FICA mesmo quando a pendência não pôde ser gravada (a evidência vale mais)', v_n::text);
  select count(*) into v_n from evento_auditoria where acao = 'fato_pendencia_falhou' and entidade_ref = 'documento_versao:' || v_e;
  perform pg_temp.teste_assert_ff(v_n = 1 and not exists (select 1 from pendencia where motivo = 'fato:conta_incerta:' || v_e), 'e o evento fato_pendencia_falhou diz que a pendência não nasceu (não é falha calada)', v_n::text);
  perform pg_temp.teste_assert_ff(array_length(pg_temp.atual(v_e), 1) = 1, 'e o FATO não depende da pendência: a view já o mostra');
  perform fn_fato_pendencia_da_versao(v_e);
  perform pg_temp.teste_assert_ff(exists (select 1 from pendencia where motivo = 'fato:conta_incerta:' || v_e and estado = 'aberta'), 'fn_fato_pendencia_da_versao(versão) avalia de novo e abre a pendência que faltou');

  create function pg_temp.cancela() returns trigger language plpgsql as $f$ begin raise exception 'cancelado de propósito (teste)' using errcode = '57014'; end $f$;
  create trigger trg_cancela before insert on pendencia for each row when (new.tipo = 'conta_canonica_incerta') execute function pg_temp.cancela();
  v_f1 := (fn_registrar_documento(v_caso, 'ALFA P27 LTDA', 'anual', '2025', 'BALANCETE', 0.97, 'nome_arquivo', 'supabase_storage', '0243/p27-m7.pdf', 'p27-m7.pdf', true, 'p27-m7', 'ok')->>'documento_versao_id')::uuid;
  begin
    perform fn_registrar_campos_extraidos(v_f1, jsonb_build_array(pg_temp.l('Caixa M7', '1', null, 'Outros', '2025')));
    v_d_ := 'engolido';
  exception when query_canceled or others then v_d_ := sqlstate;   -- `others` NÃO inclui query_canceled
  end;
  drop trigger trg_cancela on pendencia;
  select count(*) into v_n from evento_auditoria where acao = 'fato_pendencia_falhou' and entidade_ref = 'documento_versao:' || v_f1;
  perform pg_temp.teste_assert_ff(v_d_ = '57014' and v_n = 0, 'M7: query_canceled sobe ao chamador (não vira evento fato_pendencia_falhou)', v_d_ || ', eventos ' || v_n);

  raise notice '--- h. o fato segue o documento na hora: período, entidade ---';
  -- o período do documento passa de 2025 para 2024 (correção humana de periodo_incorreto); depois a entidade de ALFA para BETA e para nenhuma
  update documento set periodo_id = v_p24 where id = (select documento_id from documento_versao where id = v_a);
  v_d_ := pg_temp.dif(v_a, array[
    'Caixa|2025|-|100|ativo_circulante|ALFA P27 LTDA|-|2025|-',
    'Caixa|2024|-|90|ativo_circulante|ALFA P27 LTDA|-|2024|-',
    'Fornecedores|2023|-|50|passivo_circulante|ALFA P27 LTDA|-|-|periodo_da_coluna_nao_cadastrado',
    'Capital social|-|-|10|patrimonio_liquido|ALFA P27 LTDA|-|-|linha_sem_coluna_em_documento_com_colunas',
    'Caixa inicial|Saldo Inicial|-|70|ativo_circulante|ALFA P27 LTDA|-|-|coluna_de_abertura']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'corrigir o período do documento (agora 2024): a coluna 2024 passa a ser a do documento e a 2025 a de outro ano; o resto igual — escrito à mão', v_d_);
  update documento set entidade_id = v_beta where id = (select documento_id from documento_versao where id = v_a);
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_a and entidade_id = v_beta and entidade_origem = 'documento';
  perform pg_temp.teste_assert_ff(v_n = 5, 'corrigir a entidade do documento (agora BETA) leva TODOS os 5 fatos', v_n::text);
  update documento set entidade_id = null where id = (select documento_id from documento_versao where id = v_a);
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_a and entidade_id is null and entidade_origem is null and entidade_motivo = 'documento_sem_entidade';
  perform pg_temp.teste_assert_ff(v_n = 5, 'documento sem entidade: os 5 fatos ficam com entidade NULA e o motivo documento_sem_entidade', v_n::text);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- g2. O CRITÉRIO: a 0243 não interpreta nome de coluna; só atribui período e entidade quando a função do banco decide de forma INEQUÍVOCA, senão nulo com motivo. Os cenários que somavam errado (1.310, 500, 435, 342) e os do COMBINADO, com o fato esperado escrito à mão.
do $$
declare
  v_caso uuid; v_ver uuid; v_d_ text; v_pm uuid; v_hold uuid; v_sub uuid; v_n int; v_s numeric;
begin
  raise notice '--- g2. período e entidade só quando a função do banco decide ---';
  v_caso := (fn_upsert_caso('0243: colunas do balancete'))::uuid;
  v_hold := fn_upsert_entidade(v_caso, 'HOLDING P27 LTDA');
  v_sub := fn_upsert_entidade(v_caso, 'SUB P27 LTDA');
  perform fn_upsert_periodo(v_caso, 'anual', '2025');

  -- 1.310: o balancete de seis colunas (Saldo Anterior 100, Débito 500, Crédito 450, Saldo Atual 150, Variação 50, Orçado 160): só o Saldo Atual é o período do documento; somar o fato da conta no período dá 150, não 1.310
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '2025', 'BALANCETE', 'p27-a1', jsonb_build_array(
    pg_temp.l('Caixa', '100', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Anterior'),
    pg_temp.l('Caixa', '500', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Débito'),
    pg_temp.l('Caixa', '450', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Crédito'),
    pg_temp.l('Caixa', '150', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Atual'),
    pg_temp.l('Caixa', '50', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Variação'),
    pg_temp.l('Caixa', '160', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Orçado')));
  v_d_ := pg_temp.dif(v_ver, array[
    'Caixa|Saldo Anterior|-|100|ativo_circulante|HOLDING P27 LTDA|-|-|coluna_de_abertura',
    'Caixa|Débito|-|500|ativo_circulante|HOLDING P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento',
    'Caixa|Crédito|-|450|ativo_circulante|HOLDING P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento',
    'Caixa|Saldo Atual|-|150|ativo_circulante|HOLDING P27 LTDA|-|2025|-',
    'Caixa|Variação|-|50|ativo_circulante|HOLDING P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento',
    'Caixa|Orçado|-|160|ativo_circulante|HOLDING P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento']);
  perform pg_temp.teste_assert_ff(v_d_ = '', '1.310: as seis colunas viram seis fatos e SÓ o Saldo Atual tem período (150); abertura, Débito, Crédito, Variação e Orçado ficam nulos com o motivo — escrito à mão', v_d_);
  select sum(f.valor) into v_s from fato_financeiro f where f.documento_versao_id = v_ver and f.periodo_id is not null;
  perform pg_temp.teste_assert_ff(v_s = 150, '1.310: somar o fato da conta no período dá 150, não 1.310', v_s::text);

  -- documento SEM coluna nenhuma: a linha é do período do documento
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '2025', 'BALANCO', 'p27-sc', jsonb_build_array(pg_temp.l('Caixa SC', '5', 'ativo_circulante', 'ATIVO CIRCULANTE')));
  v_d_ := pg_temp.dif(v_ver, array['Caixa SC|-|-|5|ativo_circulante|HOLDING P27 LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'documento sem coluna de período nem de entidade: o período e a entidade do documento — escrito à mão', v_d_);

  -- 500: balancete de JUNHO (período parcial 06/2025) com colunas de mês e de data: nenhuma é INEQUÍVOCA, nenhuma recebe o período (antes somavam 500)
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '06/2025', 'BALANCETE', 'p27-a2', jsonb_build_array(
    pg_temp.l('Receita acumulada', '100', 'receita_bruta', 'RECEITA', 'Mai/2025'),
    pg_temp.l('Receita acumulada', '150', 'receita_bruta', 'RECEITA', 'Jun/2025'),
    pg_temp.l('Receita acumulada', '120', 'receita_bruta', 'RECEITA', '31/05/2025'),
    pg_temp.l('Receita acumulada', '130', 'receita_bruta', 'RECEITA', '30/06/2025')), 'mes');
  select documento.periodo_id into v_pm from documento join documento_versao dv on dv.documento_id = documento.id where dv.id = v_ver;
  perform pg_temp.teste_assert_ff(v_pm is not null and v_pm <> (select id from periodo where caso_id = v_caso and referencia = '2025'), 'arranjo: o mandato tem o período anual 2025 e o documento é do período parcial 06/2025', v_pm::text);
  v_d_ := pg_temp.dif(v_ver, array[
    'Receita acumulada|Mai/2025|-|100|receita_bruta|HOLDING P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento',
    'Receita acumulada|Jun/2025|-|150|receita_bruta|HOLDING P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento',
    'Receita acumulada|31/05/2025|-|120|receita_bruta|HOLDING P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento',
    'Receita acumulada|30/06/2025|-|130|receita_bruta|HOLDING P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento']);
  perform pg_temp.teste_assert_ff(v_d_ = '', '500: Mai/2025, Jun/2025, 31/05/2025 e 30/06/2025 do balancete de junho: 4 fatos, NENHUM com período (antes somavam 500) — escrito à mão', v_d_);
  -- 435: a DRE de junho: Jun/2025, Acumulado 2025, 1T2025, 2T2025
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '06/2025', 'DRE', 'p27-a2b', jsonb_build_array(
    pg_temp.l('Receita', '100', 'receita_bruta', 'RECEITA', 'Jun/2025'),
    pg_temp.l('Receita', '135', 'receita_bruta', 'RECEITA', 'Acumulado 2025'),
    pg_temp.l('Receita', '80', 'receita_bruta', 'RECEITA', '1T2025'),
    pg_temp.l('Receita', '120', 'receita_bruta', 'RECEITA', '2T2025')), 'mes');
  v_d_ := pg_temp.dif(v_ver, array[
    'Receita|Jun/2025|-|100|receita_bruta|HOLDING P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento',
    'Receita|Acumulado 2025|-|135|receita_bruta|HOLDING P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento',
    'Receita|1T2025|-|80|receita_bruta|HOLDING P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento',
    'Receita|2T2025|-|120|receita_bruta|HOLDING P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento']);
  perform pg_temp.teste_assert_ff(v_d_ = '', '435: a DRE de junho com Jun/2025, Acumulado 2025, 1T2025 e 2T2025: 4 fatos, NENHUM com período (antes somavam 435) — escrito à mão', v_d_);
  -- balancete PARCIAL com colunas de ANO puro (2025 e 2024) e sem saldo: nem a do ano do documento vale (o acumulado do semestre não é o ano), nem a de outro ano
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '06/2025', 'BALANCETE', 'p27-a2d', jsonb_build_array(
    pg_temp.l('Receita acumulada', '900', 'receita_bruta', 'RECEITA', '2025'),
    pg_temp.l('Receita acumulada', '700', 'receita_bruta', 'RECEITA', '2024')), 'mes');
  v_d_ := pg_temp.dif(v_ver, array[
    'Receita acumulada|2025|-|900|receita_bruta|HOLDING P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento',
    'Receita acumulada|2024|-|700|receita_bruta|HOLDING P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'balancete parcial com colunas 2025 e 2024 e sem saldo: os 2 fatos sem período (documento parcial não dá o ano a coluna nenhuma) — escrito à mão', v_d_);
  -- 342: Saldo Atual 150, Orçado 2025, AV% 2025, Var. 2025 x 2024: só o Saldo Atual (o período do documento: 06/2025)
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '06/2025', 'BALANCETE', 'p27-a2c', jsonb_build_array(
    pg_temp.l('Caixa', '150', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Atual'),
    pg_temp.l('Caixa', '160', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Orçado 2025'),
    pg_temp.l('Caixa', '12', 'ativo_circulante', 'ATIVO CIRCULANTE', 'AV% 2025'),
    pg_temp.l('Caixa', '20', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Var. 2025 x 2024')), 'mes');
  v_d_ := pg_temp.dif(v_ver, array[
    'Caixa|Saldo Atual|-|150|ativo_circulante|HOLDING P27 LTDA|-|06/2025|-',
    'Caixa|Orçado 2025|-|160|ativo_circulante|HOLDING P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento',
    'Caixa|AV% 2025|-|12|ativo_circulante|HOLDING P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento',
    'Caixa|Var. 2025 x 2024|-|20|ativo_circulante|HOLDING P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento']);
  perform pg_temp.teste_assert_ff(v_d_ = '', '342: Saldo Atual + Orçado 2025 + AV% 2025 + Var. 2025 x 2024: só o Saldo Atual recebe o período 06/2025 (150, não 342) — escrito à mão', v_d_);

  -- DUAS candidatas a ser a coluna do período do documento: nenhuma é escolhida (a escolha seria ao acaso, e ao acaso é número fabricado). Duas colunas de SALDO...
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '2025', 'BALANCETE', 'p27-sd', jsonb_build_array(
    pg_temp.l('Caixa SD', '100', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Final'),
    pg_temp.l('Caixa SD', '150', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Atual')));
  v_d_ := pg_temp.dif(v_ver, array[
    'Caixa SD|Saldo Final|-|100|ativo_circulante|HOLDING P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento',
    'Caixa SD|Saldo Atual|-|150|ativo_circulante|HOLDING P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'Saldo Final + Saldo Atual: duas colunas de saldo, nenhuma recebe o período (qual delas é o saldo?) — escrito à mão', v_d_);
  -- ... e duas colunas que nomeiam o ano do documento (2025 e 31/12/2025) num documento que não é parcial
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '2025', 'BALANCO', 'p27-ad', jsonb_build_array(
    pg_temp.l('Caixa AD', '100', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'),
    pg_temp.l('Caixa AD', '101', 'ativo_circulante', 'ATIVO CIRCULANTE', '31/12/2025')));
  v_d_ := pg_temp.dif(v_ver, array[
    'Caixa AD|2025|-|100|ativo_circulante|HOLDING P27 LTDA|-|-|mais_de_uma_coluna_para_o_mesmo_periodo',
    'Caixa AD|31/12/2025|-|101|ativo_circulante|HOLDING P27 LTDA|-|-|mais_de_uma_coluna_para_o_mesmo_periodo']);
  perform pg_temp.teste_assert_ff(v_d_ = '', '2025 + 31/12/2025: duas colunas do ano do documento, nenhuma recebe o período, motivo mais_de_uma_coluna_para_o_mesmo_periodo — escrito à mão', v_d_);

  -- ALFA/Beta/Eliminações/Consolidado: o COMBINADO da HOLDING com colunas por empresa, eliminações, total das eliminações e consolidado (a coluna 2025 é a única do ano do documento)
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '2025', 'COMBINADO', 'p27-m1', jsonb_build_array(
    pg_temp.l('Caixa M1', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'HOLDING P27 LTDA'),
    pg_temp.l('Caixa M1', '20', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'SUB P27 LTDA'),
    pg_temp.l('Caixa M1', '-5', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Eliminações'),
    pg_temp.l('Caixa M1', '-5', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Total Eliminações'),
    pg_temp.l('Caixa M1', '25', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Consolidado')));
  v_d_ := pg_temp.dif(v_ver, array[
    'Caixa M1|2025|HOLDING P27 LTDA|10|ativo_circulante|HOLDING P27 LTDA|-|2025|-',
    'Caixa M1|2025|SUB P27 LTDA|20|ativo_circulante|SUB P27 LTDA|-|2025|-',
    'Caixa M1|2025|Eliminações|-5|ativo_circulante|-|coluna_sem_entidade_no_mandato|2025|-',
    'Caixa M1|2025|Total Eliminações|-5|ativo_circulante|-|coluna_total_nao_escolhida|2025|-',
    'Caixa M1|2025|Consolidado|25|ativo_circulante|-|coluna_total_nao_escolhida|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'COMBINADO: a HOLDING recebe só a coluna dela (10, não 10+25-5), a SUB a dela (20), e Eliminações, Total Eliminações e Consolidado ficam sem entidade, com o motivo — escrito à mão', v_d_);

  -- duas colunas TOTAL (Consolidado e Total Geral) e nenhuma coluna de empresa: fn_coluna_entidade entrega "a" total sem ordem, então a escolha é arbitrária e nenhuma vale. (O motivo de cada uma depende de qual total a função devolve para qual entidade: o teste afirma o que NÃO depende dessa ordem.)
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '2025', 'COMBINADO', 'p27-e2', jsonb_build_array(
    pg_temp.l('Caixa E2', '25', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Consolidado'),
    pg_temp.l('Caixa E2', '30', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Total Geral')));
  select count(*) into v_n from fato_financeiro f where f.documento_versao_id = v_ver and f.entidade_id is null and f.entidade_motivo in ('coluna_total_ambigua', 'coluna_total_nao_escolhida', 'coluna_casa_varias_entidades');
  perform pg_temp.teste_assert_ff(v_n = 2 and (select count(*) from fato_financeiro f where f.documento_versao_id = v_ver) = 2,
    'duas colunas total e nenhuma da entidade: as 2 linhas ficam SEM entidade (nenhuma soma ao dono), cada uma com um motivo de total', v_n::text);
  -- documento que TEM coluna de entidade: a linha SEM coluna de entidade não tem dono inequívoco
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '2025', 'COMBINADO', 'p27-e3', jsonb_build_array(
    pg_temp.l('Caixa E3', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'HOLDING P27 LTDA'),
    pg_temp.l('Caixa E3', '7', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025')));
  v_d_ := pg_temp.dif(v_ver, array[
    'Caixa E3|2025|HOLDING P27 LTDA|10|ativo_circulante|HOLDING P27 LTDA|-|2025|-',
    'Caixa E3|2025|-|7|ativo_circulante|-|linha_sem_coluna_em_documento_com_colunas_de_entidade|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'a linha sem entidade_coluna num documento com colunas de entidade fica sem entidade (não soma ao dono) — escrito à mão', v_d_);
  v_d_ := pg_temp.inv(); perform pg_temp.teste_assert_ff(v_d_ = '', 'INVARIANTE depois de os cenários do balancete (1.310, 500, 435, 342), o combinado, as duas colunas de total: nenhuma chave com duas colunas, entidade e período do mesmo mandato, identidade nula explicada', v_d_);

  -- "Alfa Comércio" x a razão social: o nome da coluna é abreviado em relação à razão social: fn_mesma_entidade casa, a igualdade de nome não casava (o Consolidado ia para a ALFA, com a coluna dela nula). Mandato SÓ com a ALFA.
  v_caso := (fn_upsert_caso('0243: alfa abreviada'))::uuid;
  perform fn_upsert_entidade(v_caso, 'ALFA COMERCIO DE ALIMENTOS LTDA'); perform fn_upsert_periodo(v_caso, 'anual', '2025');
  v_ver := pg_temp.doc(v_caso, 'ALFA COMERCIO DE ALIMENTOS LTDA', '2025', 'COMBINADO', 'p27-alfa', jsonb_build_array(
    pg_temp.l('Caixa ALFA', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio'),
    pg_temp.l('Caixa ALFA', '25', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Consolidado')));
  v_d_ := pg_temp.dif(v_ver, array[
    'Caixa ALFA|2025|Alfa Comércio|10|ativo_circulante|ALFA COMERCIO DE ALIMENTOS LTDA|-|2025|-',
    'Caixa ALFA|2025|Consolidado|25|ativo_circulante|-|coluna_total_nao_escolhida|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'a coluna "Alfa Comércio" é da ALFA COMERCIO DE ALIMENTOS LTDA (10) e o Consolidado (25) NÃO vira dela — escrito à mão', v_d_);
  v_d_ := pg_temp.inv(); perform pg_temp.teste_assert_ff(v_d_ = '', 'INVARIANTE depois de "Alfa Comércio" x a razão social: nenhuma chave com duas colunas, entidade e período do mesmo mandato, identidade nula explicada', v_d_);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- g3. O fato segue o TIPO do documento; a ORDEM real (registrar, depois preencher entidade e período); a transcrição humana.
do $$
declare
  v_caso uuid; v_ent uuid; v_per uuid; v_r uuid; v_k1 uuid; v_k2 uuid; v_doc uuid; v_n int; v_d_ text; v_v1 uuid; v_v2 uuid; v_res jsonb; v_pend_antes int;
begin
  raise notice '--- g3. tipo do documento, ordem real, transcrição humana ---';
  v_caso := (fn_upsert_caso('0243: tipo e ordem'))::uuid;
  v_ent := fn_upsert_entidade(v_caso, 'ORDEM P27 LTDA');
  v_per := fn_upsert_periodo(v_caso, 'anual', '2025');

  -- Razão (só evidência) reclassificada para Balancete passa a ter fato (e de volta para Razão, deixa de ter): a leitura segue o tipo na hora, sem pendência (não é extração nova)
  v_r := pg_temp.doc(v_caso, 'ORDEM P27 LTDA', '2025', 'RAZAO', 'p27-m2', jsonb_build_array(
    pg_temp.l('Caixa R', '5', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'),
    pg_temp.l('Conta sem seção R', '6', null, 'Outros', '2025')));
  select documento_id into v_doc from documento_versao where id = v_r;
  perform pg_temp.teste_assert_ff(array_length(pg_temp.atual(v_r), 1) is null, 'RAZAO: documento de Razão não tem fato');
  update documento set tipo_taxonomia = 'BALANCETE' where id = v_doc;
  -- (o BALANCETE é parcial: a coluna 2025, sem saldo, não é inequívoca; o período fica nulo, explicado)
  v_d_ := pg_temp.dif(v_r, array[
    'Caixa R|2025|-|5|ativo_circulante|ORDEM P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento',
    'Conta sem seção R|2025|-|6|sem_conta:secao_nao_declarada|ORDEM P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'RAZAO -> BALANCETE: os 2 fatos aparecem na hora (sem esperar recálculo), escritos à mão', v_d_);
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_r;
  perform pg_temp.teste_assert_ff(v_n = 0, 'e a troca de tipo NÃO abre pendência (só extração nova abre): a linha sem conta está na view, consultável', v_n::text);
  update documento set tipo_taxonomia = 'RAZAO' where id = v_doc;
  select count(*) into v_n from campo_extraido where documento_versao_id = v_r;
  perform pg_temp.teste_assert_ff(array_length(pg_temp.atual(v_r), 1) is null and v_n = 2, 'BALANCETE -> RAZAO: os fatos somem na hora e a evidência (as 2 linhas) FICA', v_n::text);

  -- a ORDEM REAL do n8n: as linhas chegam ANTES de o documento ter entidade e período (o diagnóstico preenche depois). O resultado tem de ser o da ordem inversa (a leitura não tem ordem: lê o estado de agora)
  v_k1 := pg_temp.doc(v_caso, 'ORDEM P27 LTDA', '2025', 'BALANCO', 'p27-k1', jsonb_build_array(
    pg_temp.l('Caixa K', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Atual', 'Consolidado'),
    pg_temp.l('Estoque K', '20', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Atual', 'Consolidado')));
  v_d_ := pg_temp.dif(v_k1, array[
    'Caixa K|Saldo Atual|Consolidado|10|ativo_circulante|ORDEM P27 LTDA|-|2025|-',
    'Estoque K|Saldo Atual|Consolidado|20|ativo_circulante|ORDEM P27 LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'ordem direta (documento com entidade e período): a coluna Consolidado é o total do dono e o Saldo Atual o período do documento — escrito à mão', v_d_);
  v_k2 := (fn_registrar_documento(v_caso, 'ORDEM P27 LTDA', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage', '0243/p27-k2.pdf', 'p27-k2.pdf', true, 'p27-k2', 'ok')->>'documento_versao_id')::uuid;
  select documento_id into v_doc from documento_versao where id = v_k2;
  update documento set entidade_id = null, periodo_id = null where id = v_doc;
  perform fn_registrar_campos_extraidos(v_k2, jsonb_build_array(
    pg_temp.l('Caixa K', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Atual', 'Consolidado'),
    pg_temp.l('Estoque K', '20', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Atual', 'Consolidado')));
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_k2 and entidade_id is null and periodo_id is null and entidade_motivo is not null and periodo_motivo is not null;
  perform pg_temp.teste_assert_ff(v_n = 2, 'ordem real, antes do diagnóstico: com o documento sem entidade e sem período os 2 fatos ficam NULOS e explicados (nenhum fabricado)', v_n::text);
  update documento set entidade_id = v_ent, periodo_id = v_per where id = v_doc;
  v_d_ := pg_temp.dif(v_k2, array[
    'Caixa K|Saldo Atual|Consolidado|10|ativo_circulante|ORDEM P27 LTDA|-|2025|-',
    'Estoque K|Saldo Atual|Consolidado|20|ativo_circulante|ORDEM P27 LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'ordem real, depois do diagnóstico: preencher a entidade e o período DEPOIS dá a MESMA identidade da ordem direta — escrito à mão', v_d_);

  -- A TRANSCRIÇÃO HUMANA (fn_registrar_transcricao_humana, 0129): cria a versão vigente do documento. Ela vira fato na hora, sem pendência (a pessoa que digitou é a autoridade da seção e não há extração: nenhum evento extracao_sombra).
  v_v1 := pg_temp.doc(v_caso, 'ORDEM P27 LTDA', '2025', 'BALANCO', 'p27-tr', jsonb_build_array(pg_temp.l('Caixa TR', '3', null, 'Outros', '2025')));
  select documento_id into v_doc from documento_versao where id = v_v1;
  perform pg_temp.teste_assert_ff(exists (select 1 from pendencia where motivo = 'fato:conta_incerta:' || v_v1 and estado = 'aberta'), 'arranjo: a extração da v1 (linha sem seção) abriu a pendência');
  select count(*) into v_pend_antes from pendencia where documento_id = v_doc and tipo = 'conta_canonica_incerta';
  v_res := fn_registrar_transcricao_humana(v_doc, jsonb_build_array(
    jsonb_build_object('chave', 'Caixa TR', 'valor_num', '3', 'secao_canonica', 'ativo_circulante', 'secao', 'ATIVO CIRCULANTE', 'periodo_coluna', '2025'),
    jsonb_build_object('chave', 'Fornecedores TR', 'valor_num', '9', 'secao', 'Outros', 'periodo_coluna', '2025')), 'ana@teste', 'transcrição do teste');
  perform pg_temp.teste_assert_ff(coalesce((v_res->>'recusado')::boolean, false) = false, 'arranjo: a transcrição humana foi aceita', v_res::text);
  select id into v_v2 from documento_versao where documento_id = v_doc order by n_versao desc limit 1;
  perform pg_temp.teste_assert_ff(v_v2 <> v_v1 and fn_versao_atual(v_doc) = v_v2, 'arranjo: a transcrição criou a versão vigente (v2)');
  v_d_ := pg_temp.dif(v_v2, array[
    'Caixa TR|2025|-|3|ativo_circulante|ORDEM P27 LTDA|-|2025|-',
    'Fornecedores TR|2025|-|9|sem_conta:secao_nao_declarada|ORDEM P27 LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'a versão transcrita (vigente) já tem seus 2 fatos, escritos à mão: a que a pessoa declarou e a que ela não declarou (sem conta, dito)', v_d_);
  select count(*) into v_n from pendencia where documento_id = v_doc and tipo = 'conta_canonica_incerta';
  perform pg_temp.teste_assert_ff(v_n = v_pend_antes and not exists (select 1 from pendencia where motivo = 'fato:conta_incerta:' || v_v2),
    'DECISÃO: a transcrição humana NÃO abre pendência (a pessoa é a autoridade; não há extração por máquina): a v2 sem conta fica na view, consultável', v_n || ' pendência(s) no documento; antes ' || v_pend_antes);
  v_d_ := pg_temp.inv(); perform pg_temp.teste_assert_ff(v_d_ = '', 'INVARIANTE depois de a troca de tipo, a ordem real e a transcrição humana: nenhuma chave com duas colunas, entidade e período do mesmo mandato, identidade nula explicada', v_d_);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- g4. O "nulo com motivo" não pode ficar FALSO: período ou entidade cadastrado depois, a entidade renomeada e a segunda que casa a mesma coluna, a seção e o valor alterados por reparo. Na view não há nada a re-resolver: lê-se o estado de agora.
do $$
declare
  v_caso uuid; v_ent uuid; v_p23 uuid; v_f uuid; v_ver uuid; v_d_ text; v_beta uuid; v_n int;
begin
  raise notice '--- g4. cadastro depois, renomeação, reparo ---';
  v_caso := (fn_upsert_caso('0243: cadastro depois'))::uuid;
  v_ent := fn_upsert_entidade(v_caso, 'CAD P27 LTDA');
  perform fn_upsert_periodo(v_caso, 'anual', '2025');
  v_ver := pg_temp.doc(v_caso, 'CAD P27 LTDA', '2025', 'BALANCO', 'p27-cad', jsonb_build_array(
    pg_temp.l('Caixa CAD', '1', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'FILHA CAD P27 LTDA'),
    pg_temp.l('Caixa CAD', '2', 'ativo_circulante', 'ATIVO CIRCULANTE', '2023')));
  v_d_ := pg_temp.dif(v_ver, array[
    'Caixa CAD|2025|FILHA CAD P27 LTDA|1|ativo_circulante|-|coluna_sem_entidade_no_mandato|2025|-',
    'Caixa CAD|2023|-|2|ativo_circulante|-|linha_sem_coluna_em_documento_com_colunas_de_entidade|-|periodo_da_coluna_nao_cadastrado']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'antes do cadastro: a coluna FILHA sem entidade e a 2023 sem período, cada uma com o motivo — escrito à mão', v_d_);
  v_p23 := fn_upsert_periodo(v_caso, 'anual', '2023');
  v_d_ := pg_temp.dif(v_ver, array[
    'Caixa CAD|2025|FILHA CAD P27 LTDA|1|ativo_circulante|-|coluna_sem_entidade_no_mandato|2025|-',
    'Caixa CAD|2023|-|2|ativo_circulante|-|linha_sem_coluna_em_documento_com_colunas_de_entidade|2023|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'cadastrar o período 2023 DEPOIS: a leitura seguinte já o traz (nenhum gatilho de cadastro a esperar) — escrito à mão', v_d_);
  v_f := fn_upsert_entidade(v_caso, 'FILHA CAD P27 LTDA');
  v_d_ := pg_temp.dif(v_ver, array[
    'Caixa CAD|2025|FILHA CAD P27 LTDA|1|ativo_circulante|FILHA CAD P27 LTDA|-|2025|-',
    'Caixa CAD|2023|-|2|ativo_circulante|-|linha_sem_coluna_em_documento_com_colunas_de_entidade|2023|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'cadastrar a entidade FILHA depois: a coluna dela passa a ser dela (a linha sem coluna segue sem dono) — escrito à mão', v_d_);

  -- a entidade RENOMEADA e a 2ª entidade que casa uma coluna já atribuída (as duas deixavam o fato velho na cópia gravada)
  v_caso := fn_upsert_caso('0243: entidade renomeada')::uuid;
  perform fn_upsert_entidade(v_caso, 'MATRIZ M4 LTDA'); v_beta := fn_upsert_entidade(v_caso, 'BETA INDUSTRIA LTDA'); perform fn_upsert_periodo(v_caso, 'anual', '2025');
  perform fn_upsert_entidade(v_caso, 'GAMA SERVICOS LTDA');
  v_ver := pg_temp.doc(v_caso, 'MATRIZ M4 LTDA', '2025', 'COMBINADO', 'r3-m4', jsonb_build_array(
    pg_temp.l('Caixa', '7', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Beta Indústria'), pg_temp.l('Caixa', '3', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Gama Serviços'),
    pg_temp.l('Caixa', '99', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'MATRIZ M4 LTDA')));
  v_d_ := pg_temp.dif(v_ver, array[
    'Caixa|2025|Beta Indústria|7|ativo_circulante|BETA INDUSTRIA LTDA|-|2025|-',
    'Caixa|2025|Gama Serviços|3|ativo_circulante|GAMA SERVICOS LTDA|-|2025|-',
    'Caixa|2025|MATRIZ M4 LTDA|99|ativo_circulante|MATRIZ M4 LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'arranjo da renomeação: cada coluna é da empresa que tem o nome dela — escrito à mão', v_d_);
  update entidade set razao_social = 'DELTA SERVICOS LTDA' where id = v_beta;
  v_d_ := pg_temp.dif(v_ver, array[
    'Caixa|2025|Beta Indústria|7|ativo_circulante|-|coluna_sem_entidade_no_mandato|2025|-',
    'Caixa|2025|Gama Serviços|3|ativo_circulante|GAMA SERVICOS LTDA|-|2025|-',
    'Caixa|2025|MATRIZ M4 LTDA|99|ativo_circulante|MATRIZ M4 LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'renomear a BETA para DELTA tira dela o fato da coluna "Beta Indústria" (que não é mais o nome dela): sem entidade, explicado — escrito à mão', v_d_);
  insert into entidade (caso_id, razao_social) values (v_caso, 'GAMA SERVICOS HOLDING SA');   -- fn_upsert_entidade a fundiria com a GAMA SERVICOS LTDA (casamento por nome); o insert direto é o cadastro que o upsert não impede
  v_d_ := pg_temp.dif(v_ver, array[
    'Caixa|2025|Beta Indústria|7|ativo_circulante|-|coluna_sem_entidade_no_mandato|2025|-',
    'Caixa|2025|Gama Serviços|3|ativo_circulante|-|coluna_casa_varias_entidades|2025|-',
    'Caixa|2025|MATRIZ M4 LTDA|99|ativo_circulante|MATRIZ M4 LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'cadastrar uma 2ª entidade que casa a coluna "Gama Serviços" já atribuída torna-a coluna_casa_varias_entidades (nenhuma das duas) — escrito à mão', v_d_);
  v_d_ := pg_temp.inv(); perform pg_temp.teste_assert_ff(v_d_ = '', 'INVARIANTE depois de cadastrar período e entidade depois, renomear e a 2ª que casa: nenhuma chave com duas colunas, entidade e período do mesmo mandato, identidade nula explicada', v_d_);

  -- ALTO 1: o mandato tem "ALFA COMERCIO LTDA"; o COMBINADO traz "Alfa Comércio Atacado" (empresa que ninguém cadastrou) E "Alfa Comércio": as duas casam o nome da ALFA e fn_coluna_entidade (limit 1, sem order by) escolhia pela ordem física
  v_caso := fn_upsert_caso('0243: duas colunas da mesma entidade')::uuid;
  perform fn_upsert_entidade(v_caso, 'ALFA COMERCIO LTDA'); perform fn_upsert_periodo(v_caso, 'anual', '2025');
  v_ver := pg_temp.doc(v_caso, 'ALFA COMERCIO LTDA', '2025', 'COMBINADO', 'r3-a1', jsonb_build_array(
    pg_temp.l('Caixa', '7', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio Atacado'), pg_temp.l('Clientes', '70', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio Atacado'),
    pg_temp.l('Caixa', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio'), pg_temp.l('Clientes', '100', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio'),
    pg_temp.l('Caixa', '17', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Consolidado'), pg_temp.l('Clientes', '170', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Consolidado')));
  v_d_ := pg_temp.dif(v_ver, array[
    'Caixa|2025|Alfa Comércio Atacado|7|ativo_circulante|-|entidade_com_varias_colunas|2025|-', 'Clientes|2025|Alfa Comércio Atacado|70|ativo_circulante|-|entidade_com_varias_colunas|2025|-',
    'Caixa|2025|Alfa Comércio|10|ativo_circulante|-|entidade_com_varias_colunas|2025|-', 'Clientes|2025|Alfa Comércio|100|ativo_circulante|-|entidade_com_varias_colunas|2025|-',
    'Caixa|2025|Consolidado|17|ativo_circulante|-|coluna_total_nao_escolhida|2025|-', 'Clientes|2025|Consolidado|170|ativo_circulante|-|coluna_total_nao_escolhida|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'Alfa Comércio Atacado x Alfa Comércio (ordem 1: Atacado primeiro): com duas colunas que casam a ALFA, a ALFA não recebe NENHUMA (antes: 77), cada coluna com o motivo próprio — escrito à mão', v_d_);
  -- a ordem inversa de gravação: a coluna da ALFA primeiro (outro documento, as mesmas linhas em outra ordem física). O fato esperado é o mesmo.
  v_ver := pg_temp.doc(v_caso, 'ALFA COMERCIO LTDA', '2025', 'COMBINADO', 'r3-a2', jsonb_build_array(
    pg_temp.l('Caixa', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio'), pg_temp.l('Clientes', '100', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio'),
    pg_temp.l('Caixa', '7', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio Atacado'), pg_temp.l('Clientes', '70', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio Atacado'),
    pg_temp.l('Caixa', '17', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Consolidado'), pg_temp.l('Clientes', '170', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Consolidado')));
  v_d_ := pg_temp.dif(v_ver, array[
    'Caixa|2025|Alfa Comércio Atacado|7|ativo_circulante|-|entidade_com_varias_colunas|2025|-', 'Clientes|2025|Alfa Comércio Atacado|70|ativo_circulante|-|entidade_com_varias_colunas|2025|-',
    'Caixa|2025|Alfa Comércio|10|ativo_circulante|-|entidade_com_varias_colunas|2025|-', 'Clientes|2025|Alfa Comércio|100|ativo_circulante|-|entidade_com_varias_colunas|2025|-',
    'Caixa|2025|Consolidado|17|ativo_circulante|-|coluna_total_nao_escolhida|2025|-', 'Clientes|2025|Consolidado|170|ativo_circulante|-|coluna_total_nao_escolhida|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'Alfa Comércio Atacado x Alfa Comércio (ordem 2: a ALFA primeiro): o mesmo fato (o resultado não depende da ordem física de gravação) — escrito à mão', v_d_);

  -- ALTO 2: o tipo muda entre dois da lista (DRE -> BALANCETE: BALANCETE é parcial). A leitura segue na hora e é a que um documento já desse tipo dá.
  v_caso := fn_upsert_caso('0243: tipo entre dois da lista')::uuid;
  perform fn_upsert_entidade(v_caso, 'TIPO P27 LTDA'); perform fn_upsert_periodo(v_caso, 'anual', '2025'); perform fn_upsert_periodo(v_caso, 'anual', '2024');
  v_ver := pg_temp.doc(v_caso, 'TIPO P27 LTDA', '2025', 'DRE', 'r3-t1', jsonb_build_array(
    pg_temp.l('Receita', '1200', 'receita_bruta', 'RECEITA', '2025'), pg_temp.l('Receita', '900', 'receita_bruta', 'RECEITA', '2024')));
  v_d_ := pg_temp.dif(v_ver, array['Receita|2025|-|1200|receita_bruta|TIPO P27 LTDA|-|2025|-', 'Receita|2024|-|900|receita_bruta|TIPO P27 LTDA|-|2024|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'DRE de 2025 com as colunas 2025 e 2024: os dois períodos — escrito à mão', v_d_);
  update documento set tipo_taxonomia = 'BALANCETE' where id = (select documento_id from documento_versao where id = v_ver);
  v_d_ := pg_temp.dif(v_ver, array['Receita|2025|-|1200|receita_bruta|TIPO P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento', 'Receita|2024|-|900|receita_bruta|TIPO P27 LTDA|-|-|coluna_nao_e_o_periodo_do_documento']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'DRE -> BALANCETE (os dois na lista, BALANCETE é parcial): a leitura NÃO fica com o período de antes — escrito à mão', v_d_);
  v_d_ := pg_temp.inv(); perform pg_temp.teste_assert_ff(v_d_ = '', 'INVARIANTE depois de as duas colunas da mesma entidade (as duas ordens) e a troca de tipo entre dois da lista: nenhuma chave com duas colunas, entidade e período do mesmo mandato, identidade nula explicada', v_d_);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- g6. A fusão (Atacado -> ALFA; Imóveis -> Metalúrgica), a gravação em duas chamadas na mesma versão, a seção e o valor alterados por reparo.
do $$
declare
  v_caso uuid; v_alfa uuid; v_ata uuid; v_v1 uuid; v_v2 uuid; v_d_ text; v_r jsonb; v_met uuid; v_imo uuid; v_n int; v_pid uuid; v_desc text;
begin
  raise notice '--- g6. a fusão, as duas chamadas, o reparo ---';
  -- a fusão: "ALFA COMERCIO LTDA" + "ATACADO ALFA LTDA", colunas "Alfa Comércio"=100 e "Atacado Alfa"=70. Depois de fn_fundir_entidade(ATACADO -> ALFA) a coluna do absorvido não casa nenhuma entidade: fica sem dono, com o motivo (antes a fusão trocava o id às cegas e a ALFA ficava com 170)
  v_caso := fn_upsert_caso('0243: fusão que torna a coluna sem dono')::uuid;
  v_alfa := fn_upsert_entidade(v_caso, 'ALFA COMERCIO LTDA');
  insert into entidade (caso_id, razao_social) values (v_caso, 'ATACADO ALFA LTDA') returning id into v_ata;   -- fn_upsert_entidade fundiria as duas por nome
  perform fn_upsert_periodo(v_caso, 'anual', '2025');
  v_v1 := pg_temp.doc(v_caso, 'ALFA COMERCIO LTDA', '2025', 'COMBINADO', 'r4-f', jsonb_build_array(
    pg_temp.l('Caixa', '100', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio'), pg_temp.l('Caixa', '70', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Atacado Alfa')));
  v_d_ := pg_temp.dif(v_v1, array['Caixa|2025|Alfa Comércio|100|ativo_circulante|ALFA COMERCIO LTDA|-|2025|-', 'Caixa|2025|Atacado Alfa|70|ativo_circulante|ATACADO ALFA LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'antes da fusão: a ALFA tem 100 e o ATACADO 70, cada uma pela coluna dela — escrito à mão', v_d_);
  v_r := fn_fundir_entidade(v_caso, v_ata, v_alfa);
  perform pg_temp.teste_assert_ff(v_r->>'fundida' = 'ATACADO ALFA LTDA' and not exists (select 1 from entidade where id = v_ata), 'a fusão não conhece o fato (fn_fundir_entidade é a da migration anterior, sem repor nada) e funciona', v_r::text);
  v_d_ := pg_temp.dif(v_v1, array['Caixa|2025|Alfa Comércio|100|ativo_circulante|ALFA COMERCIO LTDA|-|2025|-', 'Caixa|2025|Atacado Alfa|70|ativo_circulante|-|coluna_sem_entidade_no_mandato|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'depois da fusão Atacado -> ALFA: a ALFA fica com 100 (a coluna dela) e a coluna do absorvido fica SEM dono, com o motivo (antes: 170) — escrito à mão', v_d_);
  perform fn_upsert_entidade(v_caso, 'OMEGA SEM RELACAO LTDA');
  perform pg_temp.teste_assert_ff(pg_temp.dif(v_v1, array['Caixa|2025|Alfa Comércio|100|ativo_circulante|ALFA COMERCIO LTDA|-|2025|-', 'Caixa|2025|Atacado Alfa|70|ativo_circulante|-|coluna_sem_entidade_no_mandato|2025|-']) = '',
    'cadastrar uma entidade que não tem relação com a fusão NÃO muda o fato (antes mudava)');
  -- Imóveis -> Metalúrgica (o caso do corpus): a coluna "Vertentes Imóveis" fica sem dono, com o motivo
  v_caso := fn_upsert_caso('0243: fusão Vertentes')::uuid;
  v_met := fn_upsert_entidade(v_caso, 'VERTENTES METALURGICA TESTE LTDA');
  insert into entidade (caso_id, razao_social) values (v_caso, 'VERTENTES IMOVEIS TESTE SPE LTDA') returning id into v_imo;
  perform fn_upsert_periodo(v_caso, 'anual', '2025');
  v_v2 := pg_temp.doc(v_caso, 'GRUPO VERTENTES TESTE', '2025', 'COMBINADO', 'fu-v', jsonb_build_array(
    pg_temp.l('Receita de vendas', '100', 'receita_bruta', 'RECEITA', '2025', 'Vertentes Metalúrgica Teste'), pg_temp.l('Receita de vendas', '70', 'receita_bruta', 'RECEITA', '2025', 'Vertentes Imóveis Teste')));
  v_d_ := pg_temp.dif(v_v2, array['Receita de vendas|2025|Vertentes Metalúrgica Teste|100|receita_bruta|VERTENTES METALURGICA TESTE LTDA|-|2025|-', 'Receita de vendas|2025|Vertentes Imóveis Teste|70|receita_bruta|VERTENTES IMOVEIS TESTE SPE LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'antes da fusão Imóveis -> Metalúrgica: cada coluna é da sua empresa — escrito à mão', v_d_);
  perform fn_fundir_entidade(v_caso, v_imo, v_met);
  v_d_ := pg_temp.dif(v_v2, array['Receita de vendas|2025|Vertentes Metalúrgica Teste|100|receita_bruta|VERTENTES METALURGICA TESTE LTDA|-|2025|-', 'Receita de vendas|2025|Vertentes Imóveis Teste|70|receita_bruta|-|coluna_sem_entidade_no_mandato|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'depois da fusão Imóveis -> Metalúrgica: a Metalúrgica fica com os 100 dela e a coluna "Vertentes Imóveis" fica sem dono, com o motivo — escrito à mão', v_d_);
  v_d_ := pg_temp.inv(); perform pg_temp.teste_assert_ff(v_d_ = '', 'INVARIANTE depois de as duas fusões: nenhuma chave com duas colunas, entidade e período do mesmo mandato, identidade nula explicada', v_d_);
  -- excluir o MANDATO com fatos: nenhuma FK de fato existe (a view não tem linha) e a exclusão não depende de ordem de cascata
  begin
    delete from caso where id = v_caso;
    v_n := 0;
  exception when others then v_n := -1;
  end;
  perform pg_temp.teste_assert_ff(v_n = 0 and not exists (select 1 from fato_financeiro where documento_versao_id = v_v2) and not exists (select 1 from entidade where caso_id = v_caso), 'excluir o mandato leva os fatos junto (não há o que apagar: a view os lê do que sobrou, e nada sobrou)', v_n::text);

  -- as DUAS CHAMADAS na MESMA versão: a 1ª sem entidade_coluna, a 2ª com "Consolidado" e a coluna de outra empresa. Lido do estado de agora: a linha da 1ª fica nula (o documento passou a TER colunas de entidade)
  v_caso := fn_upsert_caso('0243: duas chamadas na mesma versão')::uuid;
  perform fn_upsert_entidade(v_caso, 'METALURGICA P27 LTDA'); perform fn_upsert_entidade(v_caso, 'VERTENTES COMPONENTES LTDA'); perform fn_upsert_periodo(v_caso, 'anual', '2025');
  v_v2 := (fn_registrar_documento(v_caso, 'METALURGICA P27 LTDA', 'anual', '2025', 'COMBINADO', 0.97, 'nome_arquivo', 'supabase_storage', '0243/r4-d.pdf', 'r4-d.pdf', true, 'r4-d', 'ok')->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_v2, jsonb_build_array(pg_temp.l('Receita', '100', 'receita_bruta', 'RECEITA', '2025')));
  v_d_ := pg_temp.dif(v_v2, array['Receita|2025|-|100|receita_bruta|METALURGICA P27 LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'depois da 1ª chamada (sem coluna de entidade): a linha é do dono do documento — escrito à mão', v_d_);
  perform fn_registrar_campos_extraidos(v_v2, jsonb_build_array(pg_temp.l('Receita', '100', 'receita_bruta', 'RECEITA', '2025', 'Consolidado'), pg_temp.l('Receita', '40', 'receita_bruta', 'RECEITA', '2025', 'Vertentes Componentes')));
  v_d_ := pg_temp.dif(v_v2, array[
    'Receita|2025|-|100|receita_bruta|-|linha_sem_coluna_em_documento_com_colunas_de_entidade|2025|-',
    'Receita|2025|Consolidado|100|receita_bruta|METALURGICA P27 LTDA|-|2025|-',
    'Receita|2025|Vertentes Componentes|40|receita_bruta|VERTENTES COMPONENTES LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'depois da 2ª chamada na mesma versão: a linha da 1ª fica sem dono e a dona soma só o Consolidado (100, não 200) — escrito à mão', v_d_);
  v_d_ := pg_temp.inv(); perform pg_temp.teste_assert_ff(v_d_ = '', 'INVARIANTE depois de a gravação em duas chamadas na mesma versão: nenhuma chave com duas colunas, entidade e período do mesmo mandato, identidade nula explicada', v_d_);

  -- a SEÇÃO e o VALOR que mudam por reparo de serviço (os reparos em massa das 0203/0204 fazem update de campo_extraido): a leitura seguinte já é a de agora; a pendência fica como a extração a deixou
  v_caso := fn_upsert_caso('0243: seção e valor que mudam por reparo')::uuid;
  perform fn_upsert_entidade(v_caso, 'SECAO P27 LTDA'); perform fn_upsert_periodo(v_caso, 'anual', '2025');
  v_v1 := pg_temp.doc(v_caso, 'SECAO P27 LTDA', '2025', 'BALANCO', 'r4-s', jsonb_build_array(
    pg_temp.l('Caixa R4', '5', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'), pg_temp.l('Clientes R4', '6', null, 'Outros', '2025'), pg_temp.l('Estoques R4', '7', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025')));
  select id, descricao into v_pid, v_desc from pendencia where motivo = 'fato:conta_incerta:' || v_v1 and estado = 'aberta';
  perform pg_temp.teste_assert_ff(v_pid is not null, 'arranjo: a extração nova com linha sem seção abre a pendência (1)');
  update campo_extraido set secao_canonica = case chave when 'Clientes R4' then 'ativo_circulante' else 'passivo_circulante' end, secao_canonica_inferida = false where documento_versao_id = v_v1;   -- o reparo em massa
  v_d_ := pg_temp.dif(v_v1, array[
    'Caixa R4|2025|-|5|passivo_circulante|SECAO P27 LTDA|-|2025|-',
    'Clientes R4|2025|-|6|ativo_circulante|SECAO P27 LTDA|-|2025|-',
    'Estoques R4|2025|-|7|passivo_circulante|SECAO P27 LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'depois do reparo de seção em massa a leitura é a de AGORA: a conta e o método de cada linha (a sem seção virou declarada) — escrito à mão, sem recálculo nenhum', v_d_);
  update campo_extraido set valor_num = 55 where documento_versao_id = v_v1 and chave = 'Caixa R4';
  update campo_extraido set valor_num = null where documento_versao_id = v_v1 and chave = 'Estoques R4';
  v_d_ := pg_temp.dif(v_v1, array['Caixa R4|2025|-|55|passivo_circulante|SECAO P27 LTDA|-|2025|-', 'Clientes R4|2025|-|6|ativo_circulante|SECAO P27 LTDA|-|2025|-']);
  perform pg_temp.teste_assert_ff(v_d_ = '', 'valor alterado (5 -> 55) vale na leitura seguinte, e valor apagado (a célula ficou vazia) faz o fato SUMIR (ausência não é zero) — escrito à mão', v_d_);
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_v1 and estado = 'aberta' and id = v_pid and descricao = v_desc;
  perform pg_temp.teste_assert_ff(v_n = 1, 'a pendência da extração nova (1, aberta, mesmo texto) NÃO foi tocada pelo reparo nem pela leitura (só a extração de novo a converge)', v_n::text);
  perform pg_temp.reextrair(v_v1);
  perform pg_temp.teste_assert_ff((select estado from pendencia where id = v_pid) = 'resolvida', 'e a extração de novo a converge (não sobra linha incerta: resolve-se)');
  v_d_ := pg_temp.inv(); perform pg_temp.teste_assert_ff(v_d_ = '', 'INVARIANTE depois de a seção e o valor que mudam por reparo: nenhuma chave com duas colunas, entidade e período do mesmo mandato, identidade nula explicada', v_d_);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- A INVARIANTE (regra 3, a família inteira e não os casos): em NENHUM documento duas colunas diferentes caem na mesma (conta, entidade, período) não nulos — é o que fazia a soma dobrar (1.310 em vez de 150; 500; 435; 342). Sobre as fixtures e TODOS os cenários acima.
do $$
declare v_n bigint; v_nn bigint;
begin
  raise notice '--- a invariante: nenhuma chave com duas colunas do mesmo documento ---';
  select count(*) into v_nn from fato_financeiro where conta_id is not null and entidade_id is not null and periodo_id is not null;
  perform pg_temp.teste_assert_ff(v_nn >= 1000, 'a invariante mede sobre fatos de identidade completa (não sobre o vazio)', v_nn::text);
  select pg_temp.colunas_na_mesma_chave() into v_n;
  perform pg_temp.teste_assert_ff(v_n = 0, 'INVARIANTE: nenhum documento (fixtures e cenários) tem duas colunas diferentes na mesma (conta, entidade, período)', v_n || ' chave(s)');
  select count(*) into v_n from fato_financeiro f join documento_versao dv on dv.id = f.documento_versao_id join documento d on d.id = dv.documento_id
   where (f.entidade_id is not null and not exists (select 1 from entidade e where e.id = f.entidade_id and e.caso_id = d.caso_id))
      or (f.periodo_id is not null and not exists (select 1 from periodo p where p.id = f.periodo_id and p.caso_id = d.caso_id));
  perform pg_temp.teste_assert_ff(v_n = 0, 'a entidade e o período de TODO fato são do mesmo mandato do documento (por construção da leitura, sem guarda gravada)', v_n::text);
  select count(*) into v_n from fato_financeiro where (entidade_id is null) <> (entidade_motivo is not null) or (entidade_id is null) <> (entidade_origem is null)
      or (periodo_id is null) <> (periodo_motivo is not null) or (periodo_id is null) <> (periodo_origem is null) or ((conta_id is null) <> (resolucao_metodo = 'sem_conta'));
  perform pg_temp.teste_assert_ff(v_n = 0, 'identidade nula é identidade EXPLICADA em TODO fato: id nulo <=> origem nula <=> motivo; conta nula <=> sem_conta', v_n::text);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- e. A ORDEM, a idempotência e o que NÃO existe mais: um gatilho só; sem tabela, sem backfill, sem materialização.
do $$
declare v_n int; v_h0 text := current_setting('ff.h0'); v_h1 text := current_setting('ff.h1'); v_h2 text := current_setting('ff.h2');
begin
  raise notice '--- e. idempotência da migration, um gatilho só, nada gravado ---';
  perform pg_temp.teste_assert_ff(v_h0 = v_h1, 'a migration reaplicada é IDEMPOTENTE: a view, as funções, as permissões, o gatilho e o catálogo da sonda ficam byte a byte iguais (assinatura ' || left(v_h1, 8) || ')', v_h0 || ' x ' || v_h1);
  perform pg_temp.teste_assert_ff(v_h1 = v_h2, 'e, aplicada como num projeto novo (default de privilégio do Supabase ligado, a view e as funções recriadas), ela NORMALIZA o ACL: o mesmo resultado, byte a byte', v_h1 || ' x ' || v_h2);
  perform pg_temp.teste_assert_ff(current_setting('ff.default_acl') = 'f,f,f,f,f', 'sob o default (anon e authenticated com tudo em tabela/view e EXECUTE em função): o anon NÃO lê a view, o authenticated NÃO insere nela, o anon NÃO executa o resolver, o authenticated NÃO executa a pendência nem a guarda de escrita', current_setting('ff.default_acl'));
  perform pg_temp.teste_assert_ff((select relkind from pg_class where oid = 'public.fato_financeiro'::regclass) = 'v', 'fato_financeiro é VIEW (não há tabela, nem cópia, nem backfill)');
  select count(*) into v_n from pg_trigger t join pg_proc p on p.oid = t.tgfoid where not t.tgisinternal and p.proname like 'fn\_fato\_%';
  perform pg_temp.teste_assert_ff(v_n = 1 and exists (select 1 from pg_trigger t where t.tgname = 'trg_fato_pendencia_da_extracao' and t.tgrelid = 'evento_auditoria'::regclass and not t.tgisinternal and t.tgenabled in ('O', 'A')),
    'UM gatilho só da 0243, no evento_auditoria (o da extração nova); nenhum em documento, periodo, entidade ou campo_extraido', v_n::text);
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
     and p.proname in ('fn_fato_recalcular', 'fn_fato_recalcular_caso', 'fn_materializar_fatos', 'fn_materializar_fatos_do_caso', 'fn_materializar_fatos_da_extracao', 'fn_materializar_fatos_backfill', 'fn_fato_segue_o_documento', 'fn_fato_cadastro_periodo', 'fn_fato_cadastro_entidade', 'fn_fato_extracao_nova', 'fn_fato_mesmo_caso', 'fn_fato_repontar_entidade', 'fn_fato_reresolver_caso');
  perform pg_temp.teste_assert_ff(v_n = 0, 'não restou função de materialização, recálculo, backfill, reponta ou gatilho de documento/cadastro (o desenho de tabela saiu inteiro)', v_n::text);
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'fn_fundir_entidade' and pg_get_functiondef(p.oid) ilike '%fato%';
  perform pg_temp.teste_assert_ff(v_n = 0, 'fn_fundir_entidade NÃO conhece o fato: é a da migration anterior (a 0243 não a reemite)', v_n::text);
  select count(*) into v_n from evento_auditoria where acao in ('fato_financeiro_backfill', 'fato_financeiro_recalculo_final', 'fatos_materializados', 'fatos_recalculados', 'fatos_removidos_por_reclassificacao');
  perform pg_temp.teste_assert_ff(v_n = 0, 'e nenhum evento de backfill, recálculo ou materialização (nada é gravado)', v_n::text);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- d. A SEGURANÇA: o authenticated lê só o próprio mandato (a RLS de campo_extraido, documento, entidade e periodo vale para quem lê), o anon nada, o service_role tudo, o leitor só-leitura lê a sonda, NINGUÉM escreve na view.
do $$
declare
  v_socio uuid := gen_random_uuid(); v_ana uuid := gen_random_uuid(); v_sem uuid := gen_random_uuid(); v_c1 uuid; v_c2 uuid; v_ver1 uuid; v_ver2 uuid; v_tot bigint; v_t1 bigint; v_t2 bigint;
  v_ana_n bigint; v_ana_c2 bigint; v_ana_res bigint; v_ana_res_c2 bigint; v_ana_casos bigint; v_sem_n bigint; v_sem_res bigint; v_socio_n bigint; v_srv_n bigint; v_anon_t text; v_anon_f text;
  v_ana_dir bigint; v_forja text; v_pend_forja bigint; v_i text; v_u text; v_d text; v_tr text; v_si text; v_su text; v_sd text; v_leitor int; v_leitor_pres int; v_leitor_n bigint; v_leitor_erro text; v_ana_valor bigint; v_ana_ent bigint;
begin
  raise notice '--- d. segurança: dois mandatos, quatro papéis, e ninguém escreve ---';
  insert into auth.users (id, email) values (v_socio, 'socio0243@teste'), (v_ana, 'ana0243@teste'), (v_sem, 'sem0243@teste');
  insert into membro (usuario_id, papel) values (v_socio, 'socio'), (v_ana, 'analista');
  v_c1 := fn_upsert_caso('0243: seguranca mandato 1')::uuid; v_c2 := fn_upsert_caso('0243: seguranca mandato 2')::uuid;
  insert into alocacao (caso_id, usuario_id) values (v_c1, v_ana);
  perform fn_upsert_entidade(v_c1, 'SEG UM P27 LTDA'); perform fn_upsert_periodo(v_c1, 'anual', '2025');
  perform fn_upsert_entidade(v_c2, 'SEG DOIS P27 LTDA'); perform fn_upsert_periodo(v_c2, 'anual', '2025');
  v_ver1 := pg_temp.doc(v_c1, 'SEG UM P27 LTDA', '2025', 'BALANCO', 'seg-1', jsonb_build_array(pg_temp.l('Caixa S1', '11', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'), pg_temp.l('Clientes S1', '12', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025')));
  v_ver2 := pg_temp.doc(v_c2, 'SEG DOIS P27 LTDA', '2025', 'BALANCO', 'seg-2', jsonb_build_array(pg_temp.l('Caixa S2', '21', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'), pg_temp.l('Clientes S2', '22', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'), pg_temp.l('Estoque S2', '23', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025')));
  select count(*) into v_tot from fato_financeiro;
  select count(*) into v_t1 from fato_financeiro where caso_id = v_c1;
  select count(*) into v_t2 from fato_financeiro where caso_id = v_c2;

  -- a Analista alocada SÓ no mandato 1
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_ana, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*), count(*) filter (where caso_id = v_c2), count(distinct caso_id), coalesce(sum(valor) filter (where caso_id = v_c1), 0), count(*) filter (where entidade_id is not null) into v_ana_n, v_ana_c2, v_ana_casos, v_ana_valor, v_ana_ent from fato_financeiro;
  select count(*), count(*) filter (where documento_versao_id = v_ver2) into v_ana_res, v_ana_res_c2 from fn_fato_resolver(null);
  select count(*) into v_ana_dir from fn_fato_resolver(v_ver2);   -- o resolver chamado DIRETO para a versão de OUTRO mandato
  begin
    insert into evento_auditoria (ator, acao, entidade_ref, depois) values ('sistema:n8n', 'extracao_sombra', 'documento_versao:' || v_ver2, '{"campos": 0}'::jsonb);   -- o evento FORJADO para a versão do mandato 2
    v_forja := 'ok';
  exception when others then v_forja := sqlstate;
  end;
  execute 'reset role';
  -- o usuário SEM papel
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_sem, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_sem_n from fato_financeiro;
  select count(*) into v_sem_res from fn_fato_resolver(null);
  execute 'reset role';
  -- o Sócio
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_socio, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_socio_n from fato_financeiro;
  -- ninguém escreve na view: insert, update, delete e truncate do próprio Sócio
  begin
    insert into fato_financeiro (campo_extraido_id, documento_versao_id, conta_id, resolucao_metodo, valor) select ce.id, ce.documento_versao_id, 'ativo_circulante', 'declarada', 999999999 from campo_extraido ce limit 1;
    v_i := 'ok';
  exception when others then v_i := sqlstate;
  end;
  begin update fato_financeiro set valor = 0; v_u := 'ok'; exception when others then v_u := sqlstate; end;
  begin delete from fato_financeiro; v_d := 'ok'; exception when others then v_d := sqlstate; end;
  begin truncate fato_financeiro; v_tr := 'ok'; exception when others then v_tr := sqlstate; end;
  execute 'reset role';
  -- o service_role (BYPASSRLS): lê tudo, e também não escreve
  execute 'set local role service_role';
  select count(*) into v_srv_n from fato_financeiro;
  begin insert into fato_financeiro (campo_extraido_id, documento_versao_id, conta_id, resolucao_metodo, valor) select ce.id, ce.documento_versao_id, 'ativo_circulante', 'declarada', 1 from campo_extraido ce limit 1; v_si := 'ok'; exception when others then v_si := sqlstate; end;
  begin update fato_financeiro set valor = 0; v_su := 'ok'; exception when others then v_su := sqlstate; end;
  begin delete from fato_financeiro; v_sd := 'ok'; exception when others then v_sd := sqlstate; end;
  execute 'reset role';
  -- o anon
  execute 'set local role anon';
  begin perform count(*) from fato_financeiro; v_anon_t := 'ok'; exception when others then v_anon_t := sqlstate; end;
  begin perform count(*) from fn_fato_resolver(null); v_anon_f := 'ok'; exception when others then v_anon_f := sqlstate; end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  -- o leitor só-leitura da API de gerenciamento: lê a sonda inteira e a view
  begin
    execute 'set local role supabase_read_only_user';
    select count(*), count(*) filter (where presente) into v_leitor, v_leitor_pres from fn_instalacao_conferir() where migration = '0243';
    select count(*) into v_leitor_n from fato_financeiro where caso_id = v_c2;
  exception when others then v_leitor_erro := sqlerrm;
  end;
  execute 'reset role';

  perform pg_temp.teste_assert_ff(v_t1 = 2 and v_t2 = 3 and v_tot >= 1000, 'arranjo: o mandato 1 tem 2 fatos e o 2 tem 3, em um banco com as fixtures (o que a Analista NÃO pode ver existe)', v_t1 || ' / ' || v_t2 || ' / ' || v_tot);
  perform pg_temp.teste_assert_ff(v_ana_n = v_t1 and v_ana_c2 = 0 and v_ana_casos = 1, 'a Analista alocada só no mandato 1 lê os 2 fatos do mandato 1 e NENHUM de outro (a RLS por mandato vale para quem lê a view)', v_ana_n || ' fatos, ' || v_ana_c2 || ' do mandato 2, ' || v_ana_casos || ' mandato(s)');
  perform pg_temp.teste_assert_ff(v_ana_valor = 23 and v_ana_ent = 2, 'e vê o valor e a entidade dos fatos do mandato dela (23 = 11 + 12; 2 entidades preenchidas): a leitura funciona, não só nega', v_ana_valor || ' / ' || v_ana_ent);
  perform pg_temp.teste_assert_ff(v_ana_res = v_t1 and v_ana_res_c2 = 0, 'o próprio resolver (fn_fato_resolver(null)), chamado pela Analista, devolve só o mandato dela: ele NÃO é security definer', v_ana_res || ' linhas; ' || v_ana_res_c2 || ' do mandato 2');
  select count(*) into v_pend_forja from pendencia where caso_id = v_c2 and tipo = 'conta_canonica_incerta';
  perform pg_temp.teste_assert_ff(v_ana_dir = 0, 'o resolver chamado DIRETO pela Analista para a versão de OUTRO mandato devolve 0 linhas (a RLS vale dentro dele)', v_ana_dir::text);
  perform pg_temp.teste_assert_ff(v_forja = '42501' and v_pend_forja = 0, 'a Analista NÃO forja o evento extracao_sombra de outro mandato (a policy de insert de evento_auditoria recusa) e nenhuma pendência abre nele', v_forja || ' / ' || v_pend_forja);
  perform pg_temp.teste_assert_ff(v_sem_n = 0 and v_sem_res = 0, 'usuário sem papel não lê fato nenhum (nem pelo resolver)', v_sem_n || ' / ' || v_sem_res);
  perform pg_temp.teste_assert_ff(v_socio_n = v_tot, 'o Sócio lê todos os fatos', v_socio_n || ' de ' || v_tot);
  perform pg_temp.teste_assert_ff(v_srv_n = v_tot, 'o service_role lê todos os fatos', v_srv_n || ' de ' || v_tot);
  perform pg_temp.teste_assert_ff(v_i <> 'ok' and v_u <> 'ok' and v_d <> 'ok' and v_tr <> 'ok' and not has_any_column_privilege('authenticated', 'public.fato_financeiro'::regclass, 'insert') and not has_any_column_privilege('authenticated', 'public.fato_financeiro'::regclass, 'update') and not has_table_privilege('authenticated', 'public.fato_financeiro'::regclass, 'delete'),
    'NINGUÉM escreve na view: nem o Sócio (insert 999999999, update, delete, truncate) como authenticated: cada um é recusado (a view tem junção e função no FROM, não é atualizável) e o privilégio de escrita nem existe', v_i || ' ' || v_u || ' ' || v_d || ' ' || v_tr);
  perform pg_temp.teste_assert_ff(v_si <> 'ok' and v_su <> 'ok' and v_sd <> 'ok' and not has_any_column_privilege('service_role', 'public.fato_financeiro'::regclass, 'insert') and not has_any_column_privilege('service_role', 'public.fato_financeiro'::regclass, 'update'), 'nem o service_role escreve na view (insert, update, delete)', v_si || ' ' || v_su || ' ' || v_sd);
  perform pg_temp.teste_assert_ff(v_anon_t = '42501' and v_anon_f = '42501', 'o anon não lê a view nem executa o resolver (permission denied)', v_anon_t || ' ' || v_anon_f);
  perform pg_temp.teste_assert_ff(v_leitor_erro is null and v_leitor = 20 and v_leitor_pres = 20 and v_leitor_n = v_t2, 'o leitor só-leitura (supabase_read_only_user) lê a sonda da 0243 inteira (20 de 20 presentes) e a view', coalesce(v_leitor_erro, v_leitor_pres || ' de ' || v_leitor));
  perform pg_temp.teste_assert_ff(not exists (select 1 from pg_roles where rolname in ('authenticated', 'anon') and rolbypassrls), 'arranjo: o authenticated e o anon NÃO têm BYPASSRLS (a RLS vale para eles)');
end $$;

-- d1. A pendência pelo caminho do portal: a Analista alocada extrai (fn_registrar_campos_extraidos como authenticated) e a pendência abre; sem permissão no mandato a guarda recusa e deixa o evento (regra 7).
do $$
declare
  v_ana uuid := gen_random_uuid(); v_c uuid; v_ver uuid; v_n bigint; v_ev bigint; v_ver2 uuid; v_def text;
begin
  raise notice '--- d1. a pendência pelo caminho do portal (a Analista alocada) e a recusa com rastro ---';
  insert into auth.users (id, email) values (v_ana, 'ana3-0243@teste');
  insert into membro (usuario_id, papel) values (v_ana, 'analista');
  v_c := fn_upsert_caso('0243: pendencia pelo portal')::uuid;
  insert into alocacao (caso_id, usuario_id) values (v_c, v_ana);
  perform fn_upsert_entidade(v_c, 'PORTAL P27 LTDA'); perform fn_upsert_periodo(v_c, 'anual', '2025');
  v_ver := (fn_registrar_documento(v_c, 'PORTAL P27 LTDA', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage', '0243/portal-1.pdf', 'portal-1.pdf', true, 'portal-1', 'ok')->>'documento_versao_id')::uuid;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_ana, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(jsonb_build_object('chave', 'Caixa PT', 'valor_num', '5', 'secao_canonica', 'ativo_circulante', 'secao', 'ATIVO CIRCULANTE', 'periodo_coluna', '2025', 'confianca', '0.97'), jsonb_build_object('chave', 'Conta PT sem seção', 'valor_num', '6', 'secao', 'Outros', 'periodo_coluna', '2025', 'confianca', '0.97')));
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_ver and estado = 'aberta';
  perform pg_temp.teste_assert_ff(v_n = 1 and array_length(pg_temp.atual(v_ver), 1) = 2, 'a Analista alocada extrai pelo caminho do portal: os 2 fatos aparecem e a pendência da linha sem seção abre (o gatilho é do evento, o authenticated não precisa de EXECUTE nele)', v_n::text);
  -- a guarda negada: a função que decide quem escreve devolve falso (sem permissão no mandato): nenhuma pendência, e o evento diz quem foi recusado
  v_def := pg_get_functiondef('fn_fato_pode_escrever(uuid)'::regprocedure);
  execute 'create or replace function fn_fato_pode_escrever(p_caso uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $q$ select false $q$';
  v_ver2 := pg_temp.doc(v_c, 'PORTAL P27 LTDA', '2025', 'BALANCO', 'portal-2', jsonb_build_array(pg_temp.l('Conta PT2 sem seção', '7', null, 'Outros', '2025')));
  execute v_def;
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_ver2;
  select count(*) into v_ev from evento_auditoria where acao = 'fato_pendencia_negada' and entidade_ref = 'documento_versao:' || v_ver2;
  perform pg_temp.teste_assert_ff(v_n = 0 and v_ev = 1 and array_length(pg_temp.atual(v_ver2), 1) = 1, 'sem permissão de escrita no mandato a guarda NÃO abre a pendência e deixa o evento fato_pendencia_negada (regra 7); o fato (a view) existe do mesmo jeito', v_n || ' pendência(s), ' || v_ev || ' evento(s)');
end $$;

-- d2. O ACL ESTRITO de função: sem EXECUTE de PUBLIC nas 17 funções da cadeia (como produção PODE estar), a view continua legível para quem a migration declarou, e a lista é MESMO o fecho (tirar uma do authenticated quebra a leitura e a sonda acusa).
do $$
declare
  v_ana uuid := gen_random_uuid(); v_c1 uuid; v_n bigint; v_n2 bigint; v_e text; v_cadeia int; v_leitor bigint; v_srv bigint; v_f text; v_fs text[] := array[
    'fn_fato_resolver(uuid)', 'fn_tipo_gera_fato(text)', 'fn_linha_vira_fato(text, text, text, numeric)', 'fn_papel_linha(text, text, text)', 'fn_sem_codigo_de_conta(text)',
    'fn_tokens_estruturais(text)', 'fn_mes_do_rotulo(text)', 'fn_ano4(text)', 'fn_anos_periodo(text, text)', 'fn_coluna_e_abertura(text)', 'fn_coluna_e_saldo(text)',
    'fn_coluna_entidade(uuid, uuid)', 'fn_entidade_canonica(text)', 'fn_mesma_entidade(text, text)', 'fn_normalizar_texto(text)', 'fn_periodo_canonico(text, text)', 'fn_periodo_e_parcial(text, text, text, text)'];
begin
  raise notice '--- d2. ACL estrito de função: a lista da cadeia basta, e é necessária ---';
  insert into auth.users (id, email) values (v_ana, 'ana2-0243@teste');
  insert into membro (usuario_id, papel) values (v_ana, 'analista');
  v_c1 := fn_upsert_caso('0243: acl estrito')::uuid;
  insert into alocacao (caso_id, usuario_id) values (v_c1, v_ana);
  perform fn_upsert_entidade(v_c1, 'ESTRITO P27 LTDA'); perform fn_upsert_periodo(v_c1, 'anual', '2025');
  perform pg_temp.doc(v_c1, 'ESTRITO P27 LTDA', '2025', 'BALANCO', 'estr-1', jsonb_build_array(pg_temp.l('Caixa ES', '11', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'), pg_temp.l('Clientes ES', '12', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025')));
  foreach v_f in array v_fs loop
    execute format('revoke execute on function %s from public', v_f);
  end loop;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_ana, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin select count(*) into v_n from fato_financeiro where caso_id = v_c1; v_e := 'ok'; exception when others then v_e := sqlstate || ' ' || sqlerrm; end;
  execute 'reset role';
  perform pg_temp.teste_assert_ff(v_e = 'ok' and v_n = 2, 'sem EXECUTE de PUBLIC nas 17 funções da cadeia, a Analista ainda lê os 2 fatos do mandato dela (os grants explícitos da migration bastam)', coalesce(v_e, '') || ' / ' || coalesce(v_n::text, '-'));
  execute 'set local role service_role';
  select count(*) into v_srv from fato_financeiro where caso_id = v_c1;
  execute 'reset role';
  begin
    execute 'set local role supabase_read_only_user';
    select count(*) into v_leitor from fato_financeiro where caso_id = v_c1;
    select count(*) into v_cadeia from fn_instalacao_conferir() where migration = '0243' and presente;
  exception when others then v_e := sqlerrm;
  end;
  execute 'reset role';
  perform pg_temp.teste_assert_ff(v_srv = 2 and v_leitor = 2 and v_cadeia = 20, 'e o service_role e o leitor só-leitura também leem a view, e a sonda inteira dá 20 de 20 sob o ACL estrito', v_srv || ' / ' || v_leitor || ' / ' || v_cadeia);
  select count(*) into v_cadeia from instalacao_sonda_fato_financeiro_cadeia;
  perform pg_temp.teste_assert_ff(v_cadeia = 17, 'a sonda da cadeia vê as 17 funções executáveis (authenticated, service_role e leitor)', v_cadeia::text);
  -- a lista é necessária: tira uma função do FECHO do authenticated e a leitura quebra com permission denied
  revoke execute on function fn_papel_linha(text, text, text) from authenticated;
  execute 'set local role authenticated';
  begin select count(*) into v_n2 from fato_financeiro where caso_id = v_c1; v_e := 'ok'; exception when others then v_e := sqlstate || ' ' || sqlerrm; end;
  execute 'reset role';
  perform pg_temp.teste_assert_ff(v_e like '42501%', 'sem o EXECUTE de fn_papel_linha para o authenticated a leitura da view dá permission denied (a cadeia é MESMO necessária)', v_e);
  select count(*) into v_cadeia from instalacao_sonda_fato_financeiro_cadeia;
  perform pg_temp.teste_assert_ff(v_cadeia = 16 and not (select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_cadeia_executavel'), 'e a sonda acusa a função da cadeia sem grant (16 de 17: ausente)', v_cadeia::text);
  grant execute on function fn_papel_linha(text, text, text) to authenticated;
  perform pg_temp.teste_assert_ff((select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_cadeia_executavel'), 'devolvido o grant, a sonda volta a presente');
  perform set_config('request.jwt.claims', '', true);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- f. A sonda: os 20 requisitos presentes; e ela ACUSA cada guarda removida (nos mesmos termos do teste da 0242: a migration é a coisa medida, aqui o estado do banco montado).
do $$
declare v_n int; v_lista text; v_def text; v_cs uuid; v_new uuid; v_f int; v_a text; v_gatilho_off int;
begin
  raise notice '--- f. a sonda de instalação ---';
  select count(*), string_agg(chave, ', ') filter (where not presente) into v_n, v_lista from fn_instalacao_conferir() where migration = '0243';
  perform pg_temp.teste_assert_ff(v_n = 20 and v_lista is null, 'os 20 requisitos da 0243 estão no catálogo e presentes', v_n || ' requisitos; ausentes: ' || coalesce(v_lista, 'nenhum'));

  -- 1. security_invoker desligado: a view roda com o privilégio do dono (o buraco central desta migration)
  alter view fato_financeiro set (security_invoker = off);
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_view_invoker'), 'a sonda acusa a view SEM security_invoker (ela leria o fato de todos os mandatos)');
  alter view fato_financeiro set (security_invoker = on);
  perform pg_temp.teste_assert_ff((select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_view_invoker'), 'religado o security_invoker, a sonda volta a presente (a acusação era dela)');
  -- 2. o resolver como definer
  alter function fn_fato_resolver(uuid) security definer;
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_view_invoker'), 'a sonda acusa o resolver como SECURITY DEFINER (pularia a RLS que a view existe para respeitar)');
  alter function fn_fato_resolver(uuid) security invoker;
  perform pg_temp.teste_assert_ff((select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_view_invoker'), 'de volta a invoker, presente');
  -- 3. o privilégio de escrita e o anon
  grant insert on fato_financeiro to authenticated;
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_so_le'), 'a sonda acusa o authenticated com INSERT na view');
  revoke insert on fato_financeiro from authenticated;
  grant select on fato_financeiro to anon;
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_so_le'), 'a sonda acusa o anon lendo a view');
  revoke select on fato_financeiro from anon;
  grant execute on function fn_fato_resolver(uuid) to anon;
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_so_le'), 'a sonda acusa o anon executando o resolver');
  revoke execute on function fn_fato_resolver(uuid) from anon;
  perform pg_temp.teste_assert_ff((select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_so_le'), 'sem os privilégios a mais, a sonda volta a presente');

  -- 4. a leitura que discorda da linha: o resolver que acha a conta por OUTRO critério que a seção (a concordância da sonda, pelo comportamento, não por um marcador de corpo)
  v_cs := fn_upsert_caso('0243: sonda por comportamento')::uuid;
  perform fn_upsert_entidade(v_cs, 'SONDA P27 LTDA'); perform fn_upsert_periodo(v_cs, 'anual', '2025');
  v_new := pg_temp.doc(v_cs, 'SONDA P27 LTDA', '2025', 'BALANCO', 'r3-s1', jsonb_build_array(pg_temp.l('Caixa S', '5', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'), pg_temp.l('Clientes S', '6', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'), pg_temp.l('Total do ativo circulante', '11', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025')));
  update documento_versao set criada_em = now() + interval '2 days' where id = v_new;   -- a mais nova (as versões deste teste empatam em now())
  perform pg_temp.teste_assert_ff((select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_le_as_versoes_recentes'), 'a leitura das 3 versões mais novas concorda com as linhas (a sonda está presente)');
  v_def := pg_get_functiondef('fn_fato_resolver(uuid)'::regprocedure);
  execute replace(v_def, 'left join conta_canonica c on c.secao_canonica = a.secao', 'left join conta_canonica c on c.codigo = a.tipo');
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_le_as_versoes_recentes'), 'a sonda acusa o resolver que acha a conta por outro critério que a seção (o fato discorda da linha), pelo COMPORTAMENTO');
  execute v_def;
  perform pg_temp.teste_assert_ff((select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_le_as_versoes_recentes'), 'recolocado o corpo, presente');
  -- e a mesma coisa quando o resolver devolve fato para o que NÃO é elegível (o Estoque, o subtotal)
  execute replace(v_def, 'select x.tipo, x.chave, x.unidade from rotulos x where fn_linha_vira_fato(x.tipo, x.chave, x.unidade, 1)', 'select x.tipo, x.chave, x.unidade from rotulos x');
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_le_as_versoes_recentes'), 'a sonda acusa o resolver sem o filtro de papel (subtotal vira fato): fato de linha que não é elegível');
  execute v_def;
  -- sem versão a medir a sonda é AUSENTE (-1), nunca verde
  perform pg_temp.teste_assert_ff(fn_fato_sonda_recentes() = 0, 'arranjo: a amostra mede (0 divergências, e há versão a medir)', fn_fato_sonda_recentes()::text);

  -- 5. o gatilho da pendência: desabilitado, a extração nova grava a linha e NENHUMA pendência abre (o estágio que não rodou), e a sonda acusa
  begin
    alter table evento_auditoria disable trigger trg_fato_pendencia_da_extracao;
  exception when undefined_object then null;   -- gatilho já removido: a sonda o acusa do mesmo jeito
  end;
  v_new := pg_temp.doc(v_cs, 'SONDA P27 LTDA', '2025', 'BALANCO', 'r3-s2', jsonb_build_array(pg_temp.l('Clientes S2', '6', null, 'ATIVO CIRCULANTE', '2025')));
  select count(*) into v_gatilho_off from pendencia where motivo = 'fato:conta_incerta:' || v_new;
  perform pg_temp.teste_assert_ff(v_gatilho_off = 0 and array_length(pg_temp.atual(v_new), 1) = 1, 'sem o gatilho a extração grava a linha, o FATO existe (a view) e a pendência NÃO abre (arranjo da acusação)', v_gatilho_off::text);
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'pendencia_conta_gatilho'), 'a sonda acusa o gatilho da pendência desabilitado');
  begin
    alter table evento_auditoria enable trigger trg_fato_pendencia_da_extracao;
  exception when undefined_object then null;
  end;
  perform pg_temp.teste_assert_ff((select presente from fn_instalacao_conferir() where chave = 'pendencia_conta_gatilho'), 'e volta a presente ao reabilitar');
  v_def := pg_get_functiondef('fn_fato_pendencia_da_extracao()'::regprocedure);
  execute replace(v_def, 'v_pend := fn_fato_pendencia_da_versao(v_versao);', 'v_pend := null;');
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'pendencia_conta_gatilho_chama'), 'a sonda acusa a função do gatilho que não chama a avaliação da pendência');
  execute v_def;
  execute replace(v_def, 'if not fn_fato_pode_escrever(v_caso) then', 'if false then');
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'pendencia_conta_chama_a_guarda'), 'a sonda acusa a função do gatilho sem a guarda de escrita');
  execute v_def;
  v_def := pg_get_functiondef('fn_fato_pendencia_da_versao(uuid)'::regprocedure);
  execute replace(v_def, 'from fn_fato_resolver(p_documento_versao_id) r join campo_extraido ce on ce.id = r.campo_id', 'from (select ce2.id as campo_id, ''heuristica''::text as resolucao_metodo, null::text as sem_conta_motivo from campo_extraido ce2 where ce2.documento_versao_id = p_documento_versao_id) r join campo_extraido ce on ce.id = r.campo_id');
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'pendencia_le_o_resolver'), 'a sonda acusa a pendência que NÃO lê o resolver (uma segunda definição de "conta incerta")');
  execute v_def;

  -- 6. a guarda de escrita trocada por `select true`, e sem o search_path fixo
  v_def := pg_get_functiondef('fn_fato_pode_escrever(uuid)'::regprocedure);
  execute 'create or replace function fn_fato_pode_escrever(p_caso uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $q$ select true $q$';
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_guarda_de_escrita_corpo'), 'a sonda acusa fn_fato_pode_escrever trocada por select true');
  execute v_def;
  alter function fn_fato_pode_escrever(uuid) reset search_path;
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_guarda_de_escrita_search_path'), 'a sonda acusa fn_fato_pode_escrever sem o search_path fixo (security definer sequestrável)');
  alter function fn_fato_pode_escrever(uuid) set search_path = public, pg_temp;

  -- 7. a lista dos tipos é conferida TIPO A TIPO, não pelo fim do corpo
  v_def := pg_get_functiondef('fn_tipo_gera_fato(text)'::regprocedure);
  execute replace(v_def, '''BALANCO'', ', '');
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'tipos_que_geram_fato'), 'a sonda acusa a lista de tipos sem o BALANCO (e a mesma função que liga o estágio não responde por si)');
  execute v_def;
  execute replace(v_def, '''DF_AUDITADA'')', '''DF_AUDITADA'', ''RAZAO'')');
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'tipos_que_geram_fato'), 'e a que passa a gerar fato de RAZAO (o que é só evidência)');
  execute v_def;

  -- 8. os marcadores de corpo do resolver: o critério do período e o da entidade
  v_def := pg_get_functiondef('fn_fato_resolver(uuid)'::regprocedure);
  execute replace(v_def, 'mais_de_uma_coluna_para_o_mesmo_periodo', 'periodo_x');
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'periodo_coluna_do_documento_so_se_unica'), 'a sonda acusa o resolver sem o critério "duas candidatas, nenhuma escolhida"');
  execute v_def;
  execute replace(v_def, 'coluna_total_ambigua', 'total_x');
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'entidade_total_so_se_unica'), 'a sonda acusa o resolver sem o critério "mais de uma coluna total, nenhuma vale"');
  execute v_def;
  select count(*) into v_f from fn_instalacao_conferir() where migration = '0243' and not presente;
  perform pg_temp.teste_assert_ff(v_f = 0, 'depois de recolocar tudo, os 20 requisitos estão presentes de novo', v_f::text);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
do $$
declare v_exec bigint := (select last_value from pg_temp._execucoes_0243); v_falhas bigint;
begin
  select case when is_called then last_value else 0 end into v_falhas from pg_temp._falhas_0243;
  raise notice 'fato_financeiro: % asserts executados, % reprovados', v_exec, v_falhas;
  if v_falhas > 0 and coalesce(current_setting('ff.medindo', true), '') <> 'on' then
    raise exception 'FALHOU: % assert(s) da 0243 reprovaram (veja os FALHOU acima)', v_falhas;
  end if;
  if v_falhas = 0 then raise notice 'TODOS OS TESTES DO FATO FINANCEIRO PASSARAM'; end if;
end $$;

rollback;
