-- =============================================================================
-- 0276 — A VISÃO GERAL QUE BUSCAVA DEZ MIL LINHAS E FAZIA 230 CHAMADAS PARA CONTAR: duas leituras em lote que o portal pede a
--        UMA ida cada (fn_linhas_por_versao, fn_algum_documento_serve_como)
-- (Cria 2 funções de leitura e 1 view da sonda. Nenhum backfill, nenhum dado tocado.)
--
-- O DEFEITO. A visão geral do mandato (portal/src/app/casos/[id]/page.tsx) levou 13,4 s para terminar numa sessão real (mandato com
-- 115 documentos e 10.231 linhas de campo_extraido). Duas causas somam 10,2 s:
--   1. `contarLinhasPorVersao` (portal/src/lib/supabase/linhas-por-versao.ts) trazia TODAS as linhas de campo_extraido (só a coluna
--      documento_versao_id) em páginas de 1.000, sequenciais, só para contar por versão: 12 idas, 5,8 s. O paginar existe porque o
--      PostgREST corta o resultado em 1.000 linhas SEM erro (teto silencioso); contar no banco não tem teto nenhum.
--   2. `itensDoKitBasicoAtendidos` (portal/src/lib/kit-basico.ts) chamava fn_documento_serve_como (0157) uma vez por par
--      item × documento: 2 itens × 115 documentos = 230 RPCs, 4,4 s.
--
-- O QUE A MIGRATION INSTALA
--   * `fn_linhas_por_versao(p_versoes uuid[]) returns table (documento_versao_id uuid, linhas bigint)`: UMA linha por versão DISTINTA pedida,
--     com `0` EXPLÍCITO quando a versão não tem linha (left join sobre `unnest` distinto; elemento nulo é descartado). POR QUE O 0 EXPLÍCITO:
--     o `db-max-rows` do PostgREST (1.000 no Supabase) corta também a resposta de RPC que devolve várias linhas, sem erro. A CONTAGEM deixa de
--     ter teto (é um `count(*)` no banco), mas o NÚMERO DE VERSÕES na resposta continua com ele. Se "sem linha" fosse "não vem", o portal não
--     distinguiria zero linhas de resposta cortada (era o sinal `incompleto` de `contarLinhasPorVersao`, que se perderia na troca). Com uma
--     linha por versão pedida, o portal confere "linhas devolvidas = versões distintas pedidas" como sinal POSITIVO de leitura completa
--     (regra 1/7). Pedir mais de 1.000 versões distintas de uma vez continua cortável: o portal deve fatiar o pedido.
--     VERSÃO SEM ACESSO (RLS): vem com 0, igual ao que a paginação atual daria (a RLS esconde as linhas). Não vaza nada: 0 é o que o usuário já
--     vê lendo a tabela, e a função não revela se a versão existe (uuid inexistente e uuid de mandato alheio dão o mesmo 0).
--   * `fn_algum_documento_serve_como(p_documento_ids uuid[], p_tipo_taxonomia text) returns boolean`: bool_or(fn_documento_serve_como(d, tipo))
--     sobre o array; false para array vazio ou nulo. REUSA a regra da 0157 (a decisão de quem serve continua em UM lugar): esta função
--     só tira o laço do portal, não reimplementa a regra.
--
-- A POLÍTICA DE SEGURANÇA: `security invoker` (o padrão do Postgres, escrito por extenso), stable, search_path fixo. Hoje o portal lê
-- campo_extraido e chama fn_documento_serve_como COM O JWT DO USUÁRIO, sob a RLS da 0216; as duas funções novas rodam como quem chama, então
-- a RLS de campo_extraido (e a de documento, dentro de fn_documento_serve_como) continua decidindo linha a linha: um usuário sem acesso ao
-- mandato obtém ZERO linhas de contagem do outro mandato, exatamente como obtinha lendo a tabela. `security definer` aqui seria o defeito
-- contrário (qualquer authenticated contaria linhas de mandato alheio); a casa só o usa onde precisa ler membro/alocacao sem recursão
-- (0216). grant execute ao authenticated e ao service_role (convenção do Supabase/README.md:42, como a 0274), com revoke de public e anon: a sonda anon_sem_funcoes da 0218 reprova função que o anon executa; o anon não executa.
--
-- DESEMPENHO. fn_linhas_por_versao usa idx_campo_docversao (documento_versao_id) e a policy por SubPlan da 0216; é UM agrupamento no
-- banco em vez de 10.231 linhas atravessando a rede. fn_algum_documento_serve_como é uma ida em vez de 115 por item; o custo SQL por
-- documento é o mesmo de antes (a regra é a mesma). O ganho medido no portal fica para quem trocar os dois chamadores.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/a_visao_geral_que_buscava_dez_mil_linhas_e_230_chamadas_para_contar.test.sql — 28 asserts
--   (medido: 28 execuções, controle com a migration intacta: 0 reprovam; reconferido com Supabase/test/medicao-denominador.test.mjs). Cada correção
--   desligada UMA por vez, com o teste em `raise warning` (voltou para `raise exception`; log lido atrás de FALHOU), 12/11/2026:
--   * 0 explícito desligado (volta ao inner join: versão sem linha não vem): 7 · teto de 1.000 linhas na contagem: 5 ·
--     sem o `distinct` (versão repetida no array duplica a linha): 2 ·
--     fn_algum_documento_serve_como devolvendo false sempre: 5 · bool_and no lugar de bool_or: 2 ·
--     reimplementação TESTADA = a regra ANTIGA, só por rótulo (`d.tipo_taxonomia = p_tipo_taxonomia`, sem a exceção estrutural do COMBINADO): 3 ·
--     security definer nas duas (o authenticated conta e serve mandato alheio): 7 · EXECUTE concedido a public (o anon executa): 1 ·
--     sem o grant ao service_role: 1.
--   O assert "anon: 42501" sozinho NÃO pega o EXECUTE a public (o 42501 vem da tabela); por isso o assert de has_function_privilege à parte.
-- =============================================================================

begin;

create or replace function fn_linhas_por_versao(p_versoes uuid[])
returns table (documento_versao_id uuid, linhas bigint)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select v.id, coalesce(c.n, 0)::bigint
    from (select distinct u.id from unnest(p_versoes) as u(id) where u.id is not null) v
    left join (select ce.documento_versao_id as id, count(*) as n
                 from campo_extraido ce
                where ce.documento_versao_id = any (p_versoes)
                group by ce.documento_versao_id) c on c.id = v.id;
$$;

comment on function fn_linhas_por_versao(uuid[]) is
  '0276: quantas linhas de campo_extraido tem cada versão pedida, contadas no banco (sem o teto silencioso de 1.000 linhas do PostgREST que obrigava o portal a paginar: 10.231 linhas = 12 idas, 5,8 s). UMA linha por versão distinta pedida, com 0 explícito (o teto de 1.000 do PostgREST vale para o número de linhas da resposta: o portal confere linhas devolvidas = versões distintas pedidas). security invoker: a RLS de campo_extraido (0216) decide, então mandato alheio devolve zero linhas, como a leitura direta da tabela.';

-- Função nova nasce com EXECUTE para PUBLIC (e logo para o anon): a sonda anon_sem_funcoes (0218, bloqueante) reprova sem este revoke.
revoke all on function fn_linhas_por_versao(uuid[]) from public, anon;
grant execute on function fn_linhas_por_versao(uuid[]) to authenticated, service_role;

create or replace function fn_algum_documento_serve_como(p_documento_ids uuid[], p_tipo_taxonomia text)
returns boolean
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select coalesce(bool_or(fn_documento_serve_como(d, p_tipo_taxonomia)), false)
    from unnest(p_documento_ids) as d;
$$;

comment on function fn_algum_documento_serve_como(uuid[], text) is
  '0276: algum destes documentos satisfaz o item <tipo_taxonomia> do Kit Básico? bool_or de fn_documento_serve_como (0157, a regra mora lá) sobre o array; array vazio ou nulo = false. Uma ida no lugar de uma por documento (2 itens × 115 documentos = 230 RPCs, 4,4 s). security invoker: documento sob RLS, como a função de uma só.';

revoke all on function fn_algum_documento_serve_como(uuid[], text) from public, anon;
grant execute on function fn_algum_documento_serve_como(uuid[], text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- A SONDA. Marcadores em CÓDIGO, nunca de comentário. A política de segurança é atributo da função, não texto do corpo: a view
-- confere `security invoker`, `stable` e o search_path fixo nas duas (um `security definer` aqui abriria mandato alheio).
-- ---------------------------------------------------------------------------
create or replace view instalacao_sonda_leitura_em_lote_invoker as
  select count(*)::text as n
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('fn_linhas_por_versao', 'fn_algum_documento_serve_como')
     and not p.prosecdef
     and p.provolatile = 's'
     and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
  having count(*) = 2;
comment on view instalacao_sonda_leitura_em_lote_invoker is
  'Sonda da 0276: uma linha = as duas leituras em lote são security invoker, stable e com search_path fixo. Zero linhas: alguma virou security definer e o authenticated conta linhas de mandato alheio.';
grant select on instalacao_sonda_leitura_em_lote_invoker to authenticated, service_role;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('linhas_por_versao_funcao', '0276', 'funcao', 'fn_linhas_por_versao', null, null,
   'A contagem de linhas por versão feita no banco. Ausente = a visão geral do mandato volta a paginar campo_extraido inteiro pelo PostgREST (10.231 linhas, 12 idas, 5,8 s).',
   'importante', 1360),
  ('algum_documento_serve_funcao', '0276', 'funcao', 'fn_algum_documento_serve_como', null, null,
   'O Kit Básico perguntando por item em UMA ida. Ausente = volta o laço de 230 chamadas a fn_documento_serve_como (4,4 s).',
   'importante', 1361),
  ('algum_documento_serve_reusa_regra', '0276', 'corpo', 'fn_algum_documento_serve_como', 'fn_documento_serve_como(', null,
   'A decisão de quem serve um item mora em fn_documento_serve_como (0157). Corpo sem a chamada = uma segunda regra que diverge da primeira sem erro nenhum.',
   'bloqueante', 1362),
  ('leitura_em_lote_invoker', '0276', 'comportamento', 'instalacao_sonda_leitura_em_lote_invoker', null, 1,
   'As duas leituras em lote rodam COM a RLS de quem chama (security invoker). Zero linhas = alguma virou security definer e um usuário conta linhas de campo_extraido de mandato alheio.',
   'bloqueante', 1363)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0276', revisado_em = current_date,
       observacao = 'A 0276 cria fn_linhas_por_versao e fn_algum_documento_serve_como (leituras em lote security invoker que tiram da visão geral do mandato 10,2 s de 13,4 s) e a view instalacao_sonda_leitura_em_lote_invoker. 4 requisitos novos (ordem 1360-1363).'
 where id = true;

commit;
