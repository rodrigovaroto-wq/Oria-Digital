-- =============================================================================
-- Migration 0028 — RLS e GRANT dos índices macro, esquecidos na 0025
--
-- O DEFEITO. O dono aplicou 0025 + a carga inicial (seed) + reimportou os
-- workflows — tudo certo — e o export continuou saindo com a aba Macro vazia.
-- Comparando `0025_indices_macro.sql` com toda migration anterior que cria
-- tabela ou função chamada PELO PORTAL, falta os dois passos que o resto do
-- banco sempre faz:
--
--  1. TODA tabela nova neste projeto ganha `enable row level security` + policy
--     na MESMA migration que a cria — sem exceção (`0003`, `0005`, `0009`, e
--     todas as que vieram depois). `indice_macro_serie`, `indice_macro_obs` e
--     `indice_macro_expectativa` (0025) quebraram esse padrão: nenhuma das três
--     tem RLS habilitado nem policy nenhuma.
--  2. Função chamada PELO PORTAL (via `supabase.rpc()`, que resolve para o papel
--     `authenticated` do Postgres — o portal usa a chave anon + sessão do
--     usuário, nunca a service_role) ganha `grant execute ... to authenticated`
--     explícito: é o padrão de `fn_revisar_documento` (0008) e
--     `fn_aceitar_extracao` (0011). Função chamada só pelo N8N não precisa disso
--     porque o N8N conecta via Postgres NATIVO (Session Pooler, credencial
--     própria) — nunca passa pelo PostgREST, então nunca depende de GRANT de
--     papel. `fn_indice_macro_anual` é chamada pelo `export/route.ts` do
--     portal e ficou sem o grant.
--
-- O SINTOMA bate ponto a ponto com o que o dono viu: RLS habilitado sem policy
-- devolve **zero linhas, sem erro** para quem consulta (não é bloqueio visível,
-- é ausência silenciosa) — e função sem grant devolve ERRO de permissão, que o
-- `export/route.ts` também engolia (`?? []` sobre `.data`, sem olhar `.error`).
-- Resultado: dado presente no banco, export saindo como se não houvesse nada.
--
-- POR QUE ISSO NÃO FOI PEGO POR TESTE NENHUM: `Supabase/test/run.sh` roda tudo como
-- usuário `postgres` (superusuário) — RLS e GRANT de papel simplesmente NÃO SE
-- APLICAM a esse usuário, então um defeito de autorização é invisível para a
-- suíte inteira. O teste novo abaixo (dentro deste arquivo, seção de
-- verificação) faz `set role authenticated` de propósito — é o único jeito de
-- reproduzir o que o portal realmente vê.
-- =============================================================================

alter table indice_macro_serie enable row level security;
alter table indice_macro_obs enable row level security;
alter table indice_macro_expectativa enable row level security;

-- Leitura para todo autenticado, como o catálogo de taxonomia (0003,
-- `taxonomia_read`) — a série macro é a mesma para todos os mandatos, não há
-- escopo de caso para restringir. Escrita fica de fora de propósito: quem grava
-- é o N8N (Postgres nativo, ignora RLS) e o seed (rodado como `postgres` no SQL
-- Editor do Supabase, também ignora RLS) — o portal nunca escreve aqui.
create policy indice_macro_serie_read on indice_macro_serie
  for select to authenticated using (true);
create policy indice_macro_obs_read on indice_macro_obs
  for select to authenticated using (true);
create policy indice_macro_expectativa_read on indice_macro_expectativa
  for select to authenticated using (true);

-- ACRESCENTADO NA 0214 (replay sem o default privilege do Supabase, a partir de 30/10/2026): a verificação
-- embutida abaixo roda como authenticated e, sem GRANT de tabela, morre em 42501 e aborta o replay INTEIRO
-- na 0028 (medido em 20/10/2026). Em produção a linha é no-op: o default privilege antigo já concedeu.
grant select on indice_macro_serie, indice_macro_obs, indice_macro_expectativa to authenticated;

grant execute on function fn_indice_macro_anual(int) to authenticated;

-- -----------------------------------------------------------------------------
-- Verificação embutida: prova que a POLICY das três tabelas funciona, rodando
-- de fato AS authenticated (não como postgres) — falha a migration inteira se
-- a leitura sem dado nenhum voltar vazia por autorização em vez de por
-- ausência de dado. Provado localmente que isto é real (não vazio):
-- `Supabase/test/run.sh` reproduz o default de projeto que o Supabase provê (GRANT
-- de tabela para authenticated), e sem a `create policy` deste arquivo o `perform`
-- correspondente estoura `insufficient_privilege` como esperado.
--
-- O `perform fn_indice_macro_anual(2015)` é SMOKE TEST, não prova negativa: em
-- Postgres puro, função nova é executável por PUBLIC por padrão, e não há como
-- reproduzir localmente a revogação que o Supabase faz em produção (medido:
-- `alter default privileges ... revoke execute on functions from public` não
-- grava entrada em `pg_default_acl` e não tem efeito nenhum). O `grant execute`
-- acima é necessário em produção mesmo assim — é o mesmo padrão já comprovado
-- por `fn_revisar_documento` (0008) e `fn_aceitar_extracao` (0011), as duas
-- únicas outras funções que o portal chama diretamente.
-- =============================================================================
--
-- IMPORTANTE sobre a forma do teste: RLS habilitado SEM policy não estoura
-- `insufficient_privilege` — devolve ZERO LINHAS, em silêncio (é o próprio
-- mecanismo que causou o defeito real: a consulta "funciona", só nunca acha
-- nada). `perform ... limit 1` numa tabela genuinamente vazia (que é o estado
-- logo após a migration, antes do seed) não distingue "RLS bloqueando" de
-- "tabela vazia mesmo" — as duas dão zero linhas sem erro. Por isso o teste
-- insere uma linha de VERDADE primeiro (como `postgres`, que ignora RLS) e
-- confere por `COUNT(*)` que ela aparece PARA authenticated, removendo a linha
-- em seguida. `indice_macro_obs`/`indice_macro_expectativa` referenciam a série
-- 'IPCA', já semeada pela `0025` — a FK exige um código que já exista.
do $$
declare
  v_n int;
begin
  insert into indice_macro_obs (serie, fonte, data_ref, valor)
    values ('IPCA', '__verificacao_0028__', '1900-01-01', 0);
  insert into indice_macro_expectativa (serie, ano_ref, mediana, coletado_em)
    values ('IPCA', 1900, 0, '1900-01-01');

  set local role authenticated;

  select count(*) into v_n from indice_macro_serie where codigo = 'IPCA';
  if v_n = 0 then
    raise exception 'indice_macro_serie: RLS esconde uma linha que EXISTE do papel authenticated — ver 0028';
  end if;

  select count(*) into v_n from indice_macro_obs where fonte = '__verificacao_0028__';
  if v_n = 0 then
    raise exception 'indice_macro_obs: RLS esconde uma linha que EXISTE do papel authenticated — ver 0028';
  end if;

  select count(*) into v_n from indice_macro_expectativa where ano_ref = 1900;
  if v_n = 0 then
    raise exception 'indice_macro_expectativa: RLS esconde uma linha que EXISTE do papel authenticated — ver 0028';
  end if;

  perform fn_indice_macro_anual(2015); -- smoke test da RPC (não prova o grant sozinho — ver nota acima)

  reset role;
exception when insufficient_privilege then
  reset role;
  raise exception 'RLS/GRANT dos índices macro ainda bloqueia o papel authenticated — ver 0028';
end $$;

-- Limpa a linha de verificação (como postgres — RLS não se aplica).
delete from indice_macro_obs where fonte = '__verificacao_0028__';
delete from indice_macro_expectativa where ano_ref = 1900;
