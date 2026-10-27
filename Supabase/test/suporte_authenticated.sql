-- =============================================================================
-- SUPORTE aos testes que rodam COMO `authenticated` (0216, 27/10/2026)
--
-- POR QUE EXISTE. Até a 0215 toda policy de dado do cliente era `using (true)`: `set local role authenticated`
-- sem jwt bastava para ler e gravar em qualquer mandato, e 12 testes dependiam disso (apresentacao_campo,
-- arquivo_oficial, classificacao_contabil, controlador_familia, f1_escrita_authenticated, fato_material,
-- fusao_pergunta, fusao_perimetro, golden, grant_de_tabela, resumo_oficial e o de caso_pergunta em perguntas).
-- Com a 0216 a policy pergunta fn_meus_casos(), que sem identidade (auth.uid() nulo) é vazio: o mesmo teste leria
-- zero linhas. O que esses testes medem é GRANT, constraint e função, não pertinência — a pertinência é de
-- rls_por_mandato.test.sql. Então eles passam a ser o administrador (membro de tudo) durante o trecho authenticated.
--
-- COMO. `teste_como_admin_0216()` cria um usuário de teste, o torna administrador e põe o jwt dele na SESSÃO (não
-- na transação: resumo_oficial roda comandos soltos); `teste_fim_admin_0216()` apaga o usuário (a cascata leva a
-- linha de administrador) e limpa o jwt. Sempre em par, chamados como superusuário (antes de `set role` e depois de
-- `reset role`), para NÃO deixar usuário nem administrador para trás: caso_membro.test.sql conta os usuários de
-- auth.users e que `administrador` está vazia, e rls_por_mandato.test.sql parte de administrador vazio.
-- =============================================================================
create or replace function teste_como_admin_0216() returns void language plpgsql as $$
declare v constant uuid := '0216f000-0000-0000-0000-0000000000ad';
begin
  insert into auth.users (id, email) values (v, 'suporte-admin@0216.teste') on conflict do nothing;
  insert into administrador (usuario_id, por) values (v, 'teste-suporte') on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub', v, 'role', 'authenticated')::text, false);
end $$;

create or replace function teste_fim_admin_0216() returns void language plpgsql as $$
begin
  delete from auth.users where id = '0216f000-0000-0000-0000-0000000000ad';
  perform set_config('request.jwt.claims', '', false);
end $$;
