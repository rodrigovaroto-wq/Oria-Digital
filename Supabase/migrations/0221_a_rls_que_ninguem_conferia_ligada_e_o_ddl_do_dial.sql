-- =============================================================================
-- 0221 — A RLS QUE NINGUÉM CONFERIA LIGADA, E O PORTÃO DO DIAL QUE NÃO VIA DDL
-- (REDEFINE 1 função, fn_instalacao_conferir: +1 ramo (`rls_ligada`, PARTE A) e +2 critérios de ESCRITORA no ramo `definer_sem_escrita` (PARTE B); +1 tipo na constraint (14);
--  +6 requisitos na sonda (1 `rls_ligada` e 5 `corpo`). Sem tabela, sem backfill, sem dado alterado, sem função do projeto alterada. Idempotente: pode ser reaplicada.)
--
-- >>> RODE COMO `postgres`, como a 0219 e a 0220. A 0220 está APLICADA em produção e NÃO foi tocada: esta migration é por cima dela.
-- >>> DUAS PARTES, MARCADAS COM `PARTE A` / `PARTE B` (arquivo, função e teste). Elas reemitem a MESMA função, então não são dois arquivos: separam-se por hunk (`git add -p`).
--
-- ===== PARTE A — O DEFEITO: a RLS por mandato (0216) só vale com a RLS LIGADA, e nenhum requisito do catálogo conferia isso =====
-- O catálogo da sonda confere tabela, coluna, função, policy, gatilho, privilégio... e NENHUM confere `pg_class.relrowsecurity`. Desligar a RLS numa tabela (`alter table t disable row level
-- security`), ou criar tabela nova sem ligá-la, não acendia nada: as policies por mandato da 0216 continuam LÁ, no catálogo, e deixam de valer. Pendência declarada da P1b.
-- MEDIDO. Produção (04/11/2026, só leitura, informado no pedido; eu não o refiz): 51 tabelas em public, 51 com RLS, 0 sem, 0 com FORCE. Em produção existe o event trigger da PLATAFORMA
-- (`ensure_rls` -> `rls_auto_enable()`) que liga a RLS de tabela nova: é ele que mantém o 51/51 hoje, e a sonda passa a confirmar isso em vez de supor. O banco local do `run.sh` NÃO tem esse
-- event trigger (pg_event_trigger: 0 linhas): medi aqui quantas tabelas ficam sem RLS só pelas migrations: 51 tabelas de public, 51 com RLS, 0 SEM. Não há defeito de instalação limpa e portanto
-- NÃO há `alter table ... enable row level security` nesta migration (seria um no-op em produção e no replay, e o que ela provaria já está no teste).
-- ESCOPO: o requisito cobre TODO o schema `public` (relkind r e p), não uma lista. Uma lista é exatamente o que a tabela nova não está: o defeito é "criei uma tabela e esqueci", e a lista só acusaria
-- depois de alguém lembrar de acrescentá-la. Fora da conta, de propósito: tabela de EXTENSÃO (pg_depend `e`), que o dono do projeto não altera (sem caso conhecido: produção tem 0 tabelas sem RLS, de qualquer origem; a exclusão não foi exercida por teste). Ausente lista as
-- tabelas sem RLS (até 15). Tipo novo `rls_ligada` (a constraint de tipo vai de 13 para 14 valores), requisito `rls_ligada_em_public`, BLOQUEANTE: com RLS desligada o dado de um mandato é legível por outro.
-- LIMITE (declarado): confere que a RLS está LIGADA, não que há policy (tabela com RLS e sem policy fica fechada, que é o lado seguro), nem `FORCE` (o dono da tabela a ignora sem FORCE; produção tem 0 com FORCE e
-- o dono é quem roda as definer, que o portão do dial vigia à parte). Vê só `public`: `storage.objects` e `auth.*` são da plataforma.
-- Medida da PARTE A (regra 2, o bloco de medição está abaixo): (5 asserts reprovam sem o critério `not relrowsecurity`; 14 sem o ramo).
--
-- ===== PARTE B — O DEFEITO: o portão `definer_nao_escreve_no_dial` não via DDL =====
-- Ponto cego declarado no ESTADO da S116b e no cabeçalho da 0220 ("o portão varre ESCRITA DE LINHA, não DDL"). Uma função SECURITY DEFINER com EXECUTE para authenticated que rode
-- `alter table estagio_autonomia disable trigger ...`, `drop trigger ... on estagio_autonomia`, `alter table <protegida> disable row level security` ou mexa em `session_replication_role` não escreve linha
-- nenhuma, então não era acusada; mas desliga a guarda de Sócio (fn_trg_so_socio) como dono e o Analista, na MESMA transação, escreve no dial direto (e a 0219 já faz a guarda confiar em quem roda como dono).
-- MEDIDO em produção (04/11/2026, só leitura, informado no pedido): as funções de public cujo corpo casa `alter\s+table|drop\s+trigger|session_replication_role|row\s+level\s+security` são 3:
-- fn_registrar_reconciliacao (INVOKER), fn_instalacao_conferir (INVOKER) e rls_auto_enable() (DEFINER, event trigger da plataforma, genérica por SQL dinâmico, NÃO cita as tabelas protegidas). O critério novo
-- tem de continuar dando presente = t lá: ele não acusa nenhuma das três (as INVOKER só entrariam no fecho, e só seriam acusadas por chamar uma definer; a rls_auto_enable não cita tabela protegida). A consulta
-- só-leitura que repete isso em produção, com o critério NOVO, está em /tmp/claude-0/-home-user-Oria-Digital/cf2acbd9-ade7-5098-ad82-d8eb2d444191/scratchpad/0221_previa.sql.
-- A CORREÇÃO: ESCRITORA (a base do fecho) passa a incluir (1) DDL sobre as tabelas PROTEGIDAS: `alter table [if exists] [only] <protegida>` (qualquer subcomando: disable trigger, disable row level security,
-- no force...), `drop table <protegida>` e `drop trigger [if exists] <nome> on <protegida>`, com os mesmos `public.`, aspas e comentários do v_pre; e (2) o parâmetro de sessão que faz o Postgres pular TODOS os gatilhos
-- (session_replication + _role), em QUALQUER lugar do corpo, de qualquer tabela. O resto do fecho (função que chama a escritora, gatilho da tabela que ela escreve) e a acusação (DEFINER e EXECUTE para authenticated, ou de
-- gatilho) NÃO mudaram. Escolha: acusar `alter table <protegida>` de QUALQUER subcomando (até `add column`) é falso positivo do lado seguro: nenhuma função real faz isso hoje.
-- A sonda não se acusa: o parâmetro é escrito em duas metades no corpo (`'session_replication' || '_role'`), e as menções em comentário foram reescritas, senão o corpo da própria sonda casaria o critério e
-- a poria no fecho. O teste afirma por comportamento que uma definer que CHAMA fn_instalacao_conferir() não é acusada.
-- O QUE O PORTÃO AINDA NÃO VÊ (declarado, regra 1): SQL dinâmico (`execute format('alter table %s ...')` com a tabela vinda de variável); `drop function`/`alter function` com argumento de parênteses aninhados (`drop function f(numeric(10,2))`) antes da guarda numa lista;
-- `set role`/`set session authorization`; DDL por função em outro schema; `create policy`/`alter policy` na protegida (alargar a RLS); nome de gatilho entre aspas colado ao `on` (`drop trigger "x"on t`);
-- DDL numa tabela que NÃO é protegida mas tem gatilho que escreve no dial.
-- REVISÃO INDEPENDENTE (04/11/2026), corrigida neste mesmo arquivo (a 0221 não foi aplicada): (1) `alter table estagio_autonomia* disable trigger all` (o `*` dos descendentes colado ao nome) deixava o gatilho em tgenabled = 'D' com o
-- portão verde: o v_pos (nos DOIS ramos, definer e FK) aceita também `*`, e isso fecha `delete from t*` e `update t*` pelo mesmo caminho; (2) `drop table if exists x, estagio_autonomia cascade`: o ramo do drop table aceita LISTA, como o truncate;
-- (3) `drop function fn_trg_so_socio() cascade` apaga os dois gatilhos de guarda sem escrever linha, e a irmã `create or replace function` troca a guarda: ESCOLHIDO fechar a FAMÍLIA, e não o nome fixo. A guarda é a função de QUALQUER
-- gatilho das tabelas protegidas, resolvida pelo catálogo (pg_trigger) a cada chamada (v_gfn); DDL de função (drop, alter, create or replace, com `public.`, `if exists` e lista) que a cite conta como escrita. A sonda não entra no fecho (o assert
-- de quem a chama) e as migrations não são varridas (são arquivos, não corpos de função); (4) o `rls_ligada` presente agora diz "N tabelas examinadas" e exige N > 0 (regra 7: schema existente e vazio, como graphql_public, dava t sem olhar nada).
-- LIMITE DECLARADO (re-revisão): a troca do gatilho é acusada pelo ESTADO do catálogo (acesso_gatilho_dial ausente) DEPOIS que acontece, não pela definer ANTES de rodar: o portão da definer só vê DDL de função e de tabela, não
-- `create or replace trigger`. E o portão agora fica AUSENTE se nenhuma guarda estiver declarada (marcador nulo nos dois requisitos `gatilho`), em vez de verde calado.
-- Os marcadores dos 2 requisitos da 0220 sobre o v_pos foram a linha EXATA que mudou: trocados no fim deste arquivo. Requisito novo: sonda_dial_ve_ddl_da_funcao_da_guarda.
-- Medida da PARTE B (regra 2, o bloco de medição está abaixo): (8 asserts de comportamento + 3 de marcador reprovam sem os dois critérios).
--
-- ===== OS REQUISITOS =====
-- +1 `rls_ligada_em_public` (tipo novo, bloqueante) e +5 `corpo` sobre fn_instalacao_conferir, que provam em produção que a 0221 foi aplicada (marcadores de UMA linha, como a 0220, distintos entre si):
--   sonda_ve_rls_ligada (o ramo da PARTE A), sonda_dial_ve_ddl_na_protegida, sonda_dial_ve_replication_role e sonda_dial_ve_ddl_da_funcao_da_guarda (os três critérios da PARTE B).
-- Os dois requisitos da 0220 sobre o v_pos (sonda_dial_v_pos_fecha_o_definer e _a_fk) têm o marcador TROCADO aqui (o v_pos ganhou `\*`): o `update` perto do fim da migration.
-- QUEM CHAMA fn_instalacao_conferir (grep -rn): o workflow `sonda-producao.yml` (-> sonda-producao.mjs), o SQL Editor, testes e conferir-chamadas. A assinatura de retorno NÃO mudou.
-- Os testes das migrations 0218, 0219 e 0220 reaplicam a migration velha, que recria a constraint com menos tipos: eles agora apagam antes o requisito do tipo novo (como a 0219 fez com os seus).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/a_rls_ligada_e_o_ddl_do_dial.test.sql — 58 dos 58 asserts medidos em 04/11/2026 com `PGOPTIONS='-c dial.medindo=on'` (o assert vira `raise warning` e CONTA;
-- sem a variável é `raise exception`; o `run.sh` completo foi rodado sem ela e o log relido INTEIRO atrás de FALHOU). Controle intacto: 58 execuções, 0 falhas. Cada correção desligada UMA vez, num banco que já
-- tem a 0221, com a variante reaplicada por `\i` (`-v arq0221=<arquivo>`); em todas a migration APLICOU e o log traz a linha FIM com as 58 execuções ('marcador' = os asserts do catálogo que dependem do requisito da linha desligada):
--   PARTE A: `and not c.relrowsecurity` trocado por `and false` (o ramo nunca acusa): 5 reprovam (a tabela criada sem RLS, a lista de "1 tabela(s)", o `disable row level security` numa existente, a particionada, as 17);
--            o ramo `rls_ligada` APAGADO da função: 16 reprovam (os 5 acima e 11 que dependem de a linha do ramo responder: o estado limpo, os marcadores, os dois "volta a PRESENTE", o schema inexistente, o outro schema, a limpeza das 17 e a idempotência).
--   PARTE B: o critério de DDL (`or f.src ~* (v_ddl ...`) fora: 12 reprovam (9 de comportamento, os 7 abaixo mais o `alter table t*` e o `drop table` com lista: alter table ... disable trigger, drop trigger, disable row level security, `if exists only public.`, comentário e aspas, o helper INVOKER, a função de gatilho; e 3 de marcador);
--            o critério do parâmetro de réplica (`or f.src ~* v_srr`) fora: 4 (1 de comportamento e 3 de marcador); os DOIS fora: 13 (10 de comportamento e 3 de marcador);
--            o parâmetro escrito INTEIRO no corpo da sonda (sem as duas metades): 1 (quem chama fn_instalacao_conferir() passa a ser acusado: a sonda entrou no fecho).
--   REVISÕES (as correções descritas acima, medidas com o teste de 55): `\*` fora do v_pos (nos dois ramos): 3 reprovam (`alter table t*`, `delete from t*` e o marcador da 0220 que mudou; `update t *` com espaço já era visto);
--            o `drop table` sem lista: 1; o critério de DDL de função (`or f.src ~* (v_dfn ...`) fora: 10 (7 de comportamento: drop, create or replace, drop routine, drop procedure, alter routine, alter function, a lista; 3 de marcador/idempotência);
--            sem `routine|procedure` no v_dfn: 3 (drop routine, drop procedure, alter routine); `v_tot > 0` fora do rls_ligada (schema vazio dá t): 1.
--   GATILHO TROCADO (segunda rodada de buraco na varredura de texto, então a correção foi no ESTADO do catálogo e não em regex): o ramo `gatilho` confere a função que o gatilho chama contra a que o requisito declara no `marcador`
--            (fn_trg_so_socio, em acesso_gatilho_dial e acesso_gatilho_premissa_catalogo), e o v_gfn parte dessa função DECLARADA, não de pg_trigger. Ramo sem a conferência (`if true`): 2 reprovam (o gatilho trocado do dial e o do catálogo
--            ficam presentes); os marcadores dos dois requisitos NÃO declarados (sem o `update` do fim da migration): 9 (os 2 acima e os 7 do v_dfn, que perdem a função declarada); o v_gfn lido de pg_trigger em vez do declarado: 1.
--            Sem o ramo `nenhuma guarda declarada` (marcador nulo ou guarda inexistente: o portão ficaria verde calado): 2 reprovam (marcador nulo nos dois; guarda declarada que não existe).
--            Pega a troca por qualquer caminho, inclusive SQL dinâmico. A troca é real (assert): com o gatilho chamando outra função a Analista escreve no dial.
-- Os asserts da BURLA (B1: a Analista liga a definer e o dial vai de N1 a N0; controle: 42501 sem ela) e os de "não acusa" (a genérica rls_auto_enable, DDL de outra tabela, nome parecido, definer fechada, só leitura) são
-- CONTROLES do arranjo: nenhuma variante os reprova (a burla existe com ou sem a sonda; o que não acusa é verde também na 0220). Limite do teste: a BURLA mede só o `disable trigger`; as outras formas (drop trigger,
-- disable row level security, o parâmetro de réplica) são medidas pela ACUSAÇÃO, não pelo efeito.
-- =============================================================================

-- PARTE A: o tipo novo. A reemissão abaixo tem os 13 da 0220 e o `rls_ligada`.
alter table instalacao_requisito drop constraint if exists instalacao_requisito_tipo_check;
alter table instalacao_requisito add constraint instalacao_requisito_tipo_check
  check (tipo in ('tabela', 'coluna', 'funcao', 'seed', 'comportamento', 'corpo', 'gatilho', 'policy', 'privilegio', 'segredo', 'sem_privilegio', 'definer_sem_escrita', 'sem_acao_referencial', 'rls_ligada'));

-- fn_instalacao_conferir: a da 0220 INTEIRA (a que a produção tem desde 03/11/2026), mais o ramo `rls_ligada` (PARTE A) e v_ddl/v_srr (PARTE B). NÃO partir de outra: reemitir a função de antes APAGARIA um ramo.
CREATE OR REPLACE FUNCTION public.fn_instalacao_conferir()
 RETURNS TABLE(chave text, migration text, tipo text, objeto text, presente boolean, detalhe text, porque text, severidade text)
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  r            instalacao_requisito;
  v_ok         boolean;
  v_det        text;
  v_n          bigint;
  v_alvo       regclass;
  v_crit       int;
  v_proc       regproc;
  v_src        text;
  v_tg_enabled "char";
  v_tg_fn      text;
  v_role       text;
  v_privs      text[];
  v_kinds      "char"[];
  v_lista      text;
  v_classe     text;
  v_tabs       text;
  v_funs       text[];
  v_barr       oid[];
  v_pre        text;
  v_pos        text;
  v_g          text := '(\s|/\*([^*]|\*+[^*/])*\*+/|--[^\n]*\n)';
  v_ddl        text;   -- 0221 PARTE B
  v_dfn        text;   -- 0221 PARTE B
  v_gfn        text;   -- 0221 PARTE B
  v_tot        bigint; -- 0221 PARTE A
  v_tgf        oid;    -- 0221 PARTE B
  v_srr        text;   -- 0221 PARTE B
begin
  for r in select * from instalacao_requisito order by ordem, chave loop
    v_ok  := false;
    v_det := null;

    if r.tipo = 'tabela' then
      v_ok := to_regclass('public.' || r.objeto) is not null;

    elsif r.tipo = 'funcao' then
      -- `to_regproc` falha quando a função tem sobrecargas ambíguas; o nome sem
      -- argumentos resolve pelo único candidato, e sobrecarga é sinal de que o
      -- requisito devia declarar a assinatura. Nenhum dos requisitos abaixo tem.
      begin
        v_ok := to_regproc('public.' || r.objeto) is not null;
      exception when others then
        -- Ambiguidade significa que EXISTE mais de uma — logo, existe.
        v_ok := true;
        v_det := 'mais de uma assinatura com este nome';
      end;

    elsif r.tipo = 'corpo' then
      -- 0147: o corpo PUBLICADO tem de conter o marcador.
      --
      -- Como todo ramo desta função, ele não pode derrubar a sonda: função
      -- ausente, nome ambíguo e marcador ausente são três respostas diferentes,
      -- e as três são `presente = false` com o detalhe dizendo QUAL — porque
      -- "aplique a migration" e "há duas assinaturas com este nome" pedem ações
      -- diferentes de quem está lendo a tela.
      begin
        v_proc := to_regproc('public.' || r.objeto);
      exception when others then
        v_proc := null;
        v_det  := 'mais de uma assinatura com este nome — o requisito precisa declarar os argumentos';
      end;

      if v_proc is null then
        v_ok  := false;
        v_det := coalesce(v_det, 'a função nem existe');
      else
        v_src := pg_get_functiondef(v_proc::oid);
        v_ok  := v_src is not null and position(r.marcador in v_src) > 0;
        v_det := case when v_ok then 'corpo com o marcador'
                      else 'a função existe, mas o corpo é ANTERIOR a esta migration' end;
      end if;

    elsif r.tipo = 'coluna' then
      -- 0132: `pg_attribute` em vez de `information_schema.columns` — mesma
      -- resposta, 14× mais barato (3,4 ms → 0,25 ms medidos). A view do
      -- information_schema junta várias tabelas de catálogo e filtra por
      -- privilégio linha a linha; aqui a pergunta é "existe esta coluna", e
      -- `attrelid` já vem resolvido por `to_regclass`.
      --
      -- `to_regclass` devolvendo NULL não é erro: significa que a TABELA não
      -- existe, e aí a coluna também não — `attrelid = null` não casa com nada e
      -- o `exists` dá false, que é a resposta certa. É a mesma proteção do ramo
      -- de seed abaixo, obtida de graça pela forma da consulta.
      v_ok := exists (
        select 1 from pg_attribute a
         where a.attrelid  = to_regclass('public.' || split_part(r.objeto, '.', 1))
           and a.attname   = split_part(r.objeto, '.', 2)
           and a.attnum    > 0
           and not a.attisdropped);

    elsif r.tipo = 'policy' then
      -- 0210: policy de RLS é catalogada POR SI (objeto = 'tabela.nome_da_policy'). Nenhum outro tipo a
      -- enxerga: a tabela existe, a função existe, e sem a policy o authenticated leva 42501 ao escrever.
      v_alvo := to_regclass('public.' || split_part(r.objeto, '.', 1));
      if v_alvo is null then
        v_ok  := false;
        v_det := 'a tabela nem existe';
      else
        v_ok := exists (select 1 from pg_policy p
                         where p.polrelid = v_alvo and p.polname = split_part(r.objeto, '.', 2));
        v_det := case when v_ok then 'policy presente'
                      else 'a policy não existe na tabela (RLS ligada sem ela nega a operação ao authenticated)' end;
      end if;

    elsif r.tipo = 'gatilho' then
      -- 0189: gatilho é catalogado POR SI, não pela função que ele chama.
      --
      -- POR QUE ISTO NÃO CABE NO TIPO `funcao`. A função de um gatilho
      -- SOBREVIVE a `drop trigger` e a `alter table ... disable trigger` — o
      -- exemplo já estava no catálogo antes deste tipo existir, em
      -- `gatilho_da_promocao` (0137): a função `fn_trg_auto_promover_dial`
      -- existe e nada garante que algo a chame. `objeto` aqui é
      -- `tabela.nome_do_gatilho`; a tabela é resolvida primeiro, como em todo
      -- ramo desta função — tabela ausente nunca pode virar exceção que
      -- derruba a sonda inteira.
      v_alvo := to_regclass('public.' || split_part(r.objeto, '.', 1));
      if v_alvo is null then
        v_ok  := false;
        v_det := 'a tabela nem existe';
      else
        select tgenabled, tgfoid::regproc::text, tgfoid
          into v_tg_enabled, v_tg_fn, v_tgf
          from pg_trigger
         where tgrelid = v_alvo
           and tgname  = split_part(r.objeto, '.', 2)
           and not tgisinternal;

        if v_tg_enabled is null then
          v_ok  := false;
          v_det := 'o gatilho não existe na tabela (a função dele pode existir — ela sobrevive ao drop trigger)';
        elsif v_tg_enabled = 'D' then
          v_ok  := false;
          v_det := 'o gatilho existe mas está DESABILITADO (disable trigger) — a guarda não roda';
        elsif v_tg_enabled = 'R' then
          -- 'R' = ENABLE REPLICA TRIGGER. Decisão deliberada, e mais estrita
          -- que `<> 'D'`: um gatilho em modo réplica NÃO dispara com
          -- o parâmetro de réplica da sessão em `origin`, que é o padrão de toda sessão
          -- normal (é o que o pooler do Supabase usa). Do ponto de vista de
          -- quem depende da guarda rodando na sessão normal, um gatilho em
          -- modo réplica está tão desligado quanto um desabilitado — só que
          -- calado, porque `tgenabled <> 'D'` deixaria passar.
          v_ok  := false;
          v_det := 'o gatilho existe mas só dispara em modo réplica — na sessão normal a guarda não roda';
        elsif v_tg_enabled in ('O', 'A') then
          -- 'O' = ENABLE (origin, o padrão) · 'A' = ENABLE ALWAYS (dispara em origin e em réplica): as duas rodam em sessão normal.
          -- 0221 (revisão): ligado NÃO basta. `create or replace trigger <mesmo nome> ... execute function <outra>` deixa o gatilho com o mesmo nome e habilitado, chamando uma função inofensiva, e a
          -- guarda de Sócio deixa de rodar sem nenhum DML nem DDL de função que um regex veja (nem por SQL dinâmico). Quando o requisito DECLARA a função da guarda (`marcador` = o nome em public), o gatilho
          -- tem de chamar EXATAMENTE ela (tgfoid = to_regproc). Sem marcador (os demais gatilhos do catálogo) vale o de antes: existe e dispara; ele NÃO confere eventos (INSERT/UPDATE/DELETE).
          if r.marcador is null then
            v_ok  := true;
            v_det := format('gatilho habilitado (chama %s)', coalesce(v_tg_fn, '?'));
          else
            begin
              v_proc := to_regproc('public.' || r.marcador);
            exception when others then
              v_proc := null;
            end;
            v_ok  := v_proc is not null and v_tgf = v_proc::oid;
            v_det := case when v_ok then format('gatilho habilitado e chama %s, a função da guarda que o requisito declara', v_tg_fn)
                          else format('o gatilho está habilitado, mas chama %s e NÃO %s, a função da guarda que o requisito declara: a guarda foi TROCADA (create or replace trigger) e não roda', coalesce(v_tg_fn, '?'), r.marcador) end;
          end if;
        else
          -- Não deveria acontecer — `tgenabled` só tem estes quatro valores —
          -- mas a sonda nunca assume "presente" por omissão de um `case`.
          v_ok  := false;
          v_det := format('estado de gatilho desconhecido: %s', v_tg_enabled);
        end if;
      end if;

    elsif r.tipo = 'privilegio' then
      -- 0214: privilégio de TABELA/VIEW/SEQUENCE do schema public para um papel. `objeto` = 'papel:classe' (classe
      -- tabelas | views | sequences) e `marcador` = os privilégios exigidos, separados por vírgula. Varre TODO o
      -- schema, não uma lista: o defeito que isto pega é a tabela NOVA cuja migration esqueceu o GRANT (a partir
      -- de 30/10/2026 o Supabase não concede mais nada por default privilege), e uma lista de nomes seria
      -- exatamente a que ninguém atualiza. Objeto de extensão fica de fora (não é nosso). Revoke intencional
      -- (delete do authenticated em arquivo_oficial etc.) não aparece aqui: só se exige o MÍNIMO por classe.
      v_role  := split_part(r.objeto, ':', 1);
      v_privs := string_to_array(r.marcador, ',');
      v_kinds := case split_part(r.objeto, ':', 2)
                   when 'tabelas'   then array['r', 'p']::"char"[]
                   when 'views'     then array['v', 'm']::"char"[]
                   when 'sequences' then array['S']::"char"[]
                 end;
      if v_kinds is null or v_privs is null then
        v_ok  := false;
        v_det := 'requisito mal declarado: objeto papel:(tabelas|views|sequences) e marcador com os privilégios';
      elsif not exists (select 1 from pg_roles where rolname = v_role) then
        v_ok  := false;
        v_det := format('o papel %s nem existe', v_role);
      else
        select count(*), string_agg(x.relname, ', ' order by x.relname) filter (where x.rn <= 15)
          into v_n, v_lista
          from (select c.relname, row_number() over (order by c.relname) as rn
                  from pg_class c
                  join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'public'
                   and c.relkind = any (v_kinds)
                   and not exists (select 1 from pg_depend d
                                    where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e')
                   and exists (select 1 from unnest(v_privs) p
                                where not case when c.relkind = 'S'
                                         then has_sequence_privilege(v_role, c.oid, p)
                                         else has_table_privilege(v_role, c.oid, p) end)) x;
        v_ok  := v_n = 0;
        v_det := case when v_ok then format('nenhum objeto de public sem %s para %s', r.marcador, v_role)
                      else format('%s objeto(s) de public SEM %s para %s: %s%s', v_n, r.marcador, v_role, v_lista,
                                  case when v_n > 15 then ' ...' else '' end) end;
      end if;

    elsif r.tipo = 'sem_privilegio' then
      -- 0218: o INVERSO do `privilegio`. Aquele exige o MÍNIMO (o buraco é o que falta); este exige a AUSÊNCIA (o buraco é o que sobra).
      -- `objeto` = 'papel:classe' (classe tabelas | views | sequences | funcoes) e `marcador` = os privilégios que o papel NÃO pode ter.
      -- Varre TODO o schema public, não uma lista: o defeito é o objeto NOVO que nasce com privilégio (o default privilege antigo do
      -- Supabase dava tudo a `anon`; função nova nasce com EXECUTE para PUBLIC, e `anon` herda de PUBLIC — por isso `has_*_privilege`,
      -- que enxerga a herança, e não a leitura da ACL). Privilégio de COLUNA conta (`has_any_column_privilege`): um `grant select (id)`
      -- não aparece em `has_table_privilege`. Fora da varredura: objeto de extensão e objeto cujo dono não é `postgres` (o REVOKE de quem não é dono só avisa: o requisito nasceria ausente por um motivo que a migration não corrige; ex.: unaccent, do supabase_admin), e função `teste_*`, que só existe no
      -- harness local (a suíte as cria em public e não as apaga; em produção nenhuma função tem este prefixo).
      v_role   := split_part(r.objeto, ':', 1);
      v_privs  := string_to_array(r.marcador, ',');
      v_classe := split_part(r.objeto, ':', 2);
      if v_classe not in ('tabelas', 'views', 'sequences', 'funcoes') or v_privs is null then
        v_ok  := false;
        v_det := 'requisito mal declarado: objeto papel:(tabelas|views|sequences|funcoes) e marcador com os privilégios proibidos';
      elsif not exists (select 1 from pg_roles where rolname = v_role) then
        v_ok  := true;
        v_det := format('o papel %s nem existe: não há privilégio a vazar', v_role);
      else
        if v_classe = 'funcoes' then
          select count(*), string_agg(x.nome, ', ' order by x.nome) filter (where x.rn <= 15)
            into v_n, v_lista
            from (select p.oid::regprocedure::text as nome, row_number() over (order by p.oid::regprocedure::text) as rn
                    from pg_proc p
                    join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'public'
                     and p.proname not like 'teste\_%'
                     and p.proowner = (select oid from pg_roles where rolname = 'postgres')
                     -- 0219: função que RETORNA event_trigger não é chamável (nem por SQL nem por RPC: "trigger functions can only be called as triggers"),
                     -- logo o EXECUTE de PUBLIC nela não é superfície. É a função do event trigger da PLATAFORMA Supabase (`rls_auto_enable`, dona postgres,
                     -- SECURITY DEFINER, que NÃO está neste repositório): o laço da 0218 lhe tirou o PUBLIC e a 0219 o devolveu, e a sonda não pode acusar a correção.
                     -- Só event_trigger: função de GATILHO comum (`trigger`) continua na varredura, porque o projeto já faz `revoke ... from public` em todas.
                     and p.prorettype <> 'event_trigger'::regtype
                     and not exists (select 1 from pg_depend d
                                      where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
                     and exists (select 1 from unnest(v_privs) q where has_function_privilege(v_role, p.oid, q))) x;
        else
          select count(*), string_agg(x.relname, ', ' order by x.relname) filter (where x.rn <= 15)
            into v_n, v_lista
            from (select c.relname, row_number() over (order by c.relname) as rn
                    from pg_class c
                    join pg_namespace n on n.oid = c.relnamespace
                   where n.nspname = 'public'
                     and c.relkind = any (case v_classe when 'tabelas'   then array['r', 'p']::"char"[]
                                                        when 'views'     then array['v', 'm']::"char"[]
                                                        else array['S']::"char"[] end)
                     and c.relowner = (select oid from pg_roles where rolname = 'postgres')
                     and not exists (select 1 from pg_depend d
                                      where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e')
                     and exists (select 1 from unnest(v_privs) q
                                  where case when c.relkind = 'S'
                                             then has_sequence_privilege(v_role, c.oid, q)
                                             when lower(q) in ('select', 'insert', 'update', 'references')
                                             then has_any_column_privilege(v_role, c.oid, q)
                                             else has_table_privilege(v_role, c.oid, q) end)) x;
        end if;
        v_ok  := v_n = 0;
        v_det := case when v_ok then format('nenhum objeto (%s) de public com privilégio para %s', v_classe, v_role)
                      else format('%s objeto(s) (%s) de public COM privilégio para %s: %s%s', v_n, v_classe, v_role, v_lista,
                                  case when v_n > 15 then ' ...' else '' end) end;
      end if;

    elsif r.tipo = 'segredo' then
      -- 0217: segredo do Vault do Supabase (objeto = o NOME do segredo; o valor nunca é lido aqui). A sonda roda como o
      -- chamador (o portal é `authenticated`, que não lê o Vault), então a pergunta "existe e não está vazio?" passa por
      -- uma função SECURITY DEFINER que só devolve boolean. Falha ao perguntar (Vault ausente, sem permissão) é
      -- `presente = false` com o motivo, nunca uma exceção que derrube a sonda inteira.
      begin
        v_ok  := coalesce(fn_segredo_do_vault_presente(r.objeto), false);
        v_det := case when v_ok then 'segredo presente no Vault (valor não lido)'
                      else 'o Vault não tem este segredo, ou ele está vazio' end;
      exception when others then
        v_ok  := false;
        v_det := 'não foi possível consultar o Vault: ' || sqlerrm;
      end;

    elsif r.tipo = 'definer_sem_escrita' then
      -- 0219: a guarda de Sócio (fn_trg_so_socio) deixa passar quem roda como DONO (current_user fora de authenticated/anon). Função SECURITY DEFINER roda como
      -- dono: uma definer que o portal alcança e que, DIRETA OU INDIRETAMENTE, escreve numa tabela protegida passaria pela guarda sem o chamador ser Sócio.
      -- `objeto` = as tabelas protegidas (lista por vírgula). `marcador` = `RAIZES;PORTAS`: antes do `;`, funções que contam como escritoras só pelo nome (fn_mudar_dial);
      -- depois, as PORTAS declaradas (hoje só fn_dial_auto_promover), que o fecho não atravessa. Ver o cabeçalho da migration.
      --
      -- O FECHO (revisão independente, 03/11/2026: a primeira versão só lia o corpo da própria definer e deixava passar `definer -> helper INVOKER -> update`).
      -- ESCRITORAS = toda função de public, de QUALQUER segurança, cujo corpo escreve nas tabelas (insert into | update | delete from | merge into | truncate), mais as RAIZES.
      -- Depois, até não crescer mais (recursive com UNION: termina sozinho, sem limite de profundidade): entra no fecho a função X se (a) o corpo de X cita
      -- `Y(` para algum Y do fecho, ou (b) X escreve numa tabela T que tem gatilho cuja função é Y do fecho. Este (b) é o gatilho INVOKER numa tabela que uma definer
      -- escreve: ele dispara no DML da definer, com current_user = dono, e a guarda o deixa passar.
      -- ACUSADA = função do fecho que é SECURITY DEFINER E (EXECUTE para authenticated, OU retorna trigger/event_trigger, que dispara sem precisar de EXECUTE).
      -- O corpo é prosrc, ou, no `begin atomic` (prosqlbody não nulo, prosrc vazio), pg_get_function_sqlbody: o `begin atomic` passava invisível.
      -- ESCOLHA: o fecho por NOME, não só "uma volta". Falso positivo é o lado seguro: a citação do nome num comentário, ou uma homônima de outro schema, acusam a mais.
      -- 0220: escrita por VIEW atualizável ou por RULE sobre a tabela NÃO é ponto cego (a 0219 o declarava, sem medir): a view e a regra rodam com os privilégios do dono da
      -- view, mas `current_user` segue sendo o de quem chamou (authenticated), e a guarda de Sócio recusa com 42501 (medido na 0220, com o Analista).
      -- O QUE VEM DEPOIS DO NOME: v_pos aceita espaço, `;`, fim, `(`, `)` e `,` (a 0219 só os quatro primeiros: `with d as (delete from t) select`, `truncate t, x` e
      -- `(delete from t)` davam presente = t; uma definer assim, com EXECUTE para authenticated, apagou o catálogo de 89 a 0 linhas). O QUE VEM ANTES: v_pre aceita, entre a palavra e o nome, espaço, aspas
      -- imediatas (`delete from"t"`) e comentário de bloco ou de linha (`delete from /* c */ t`): v_g.
      -- 0221 PARTE B: DDL conta como ESCRITA. `alter table <protegida> ...` (disable trigger, disable row level security, no force...), `drop trigger ... on <protegida>` e
      -- `drop table <protegida>` não escrevem linha, mas desligam a guarda de Sócio (ou a RLS) na mesma transação, e o Analista que chamou a definer escreve no dial direto. E
      -- o parâmetro de sessão `session_replication` + `_role` (escrito em duas metades aqui) em QUALQUER lugar do corpo (ele faz o Postgres PULAR todos os gatilhos, de qualquer tabela). O alcance do DDL é a lista de tabelas protegidas (v_tabs):
      -- um `alter table` genérico, de outra tabela ou por SQL dinâmico (rls_auto_enable), não acusa. Lado seguro, como no DML: acusa a mais um `alter table <protegida> add column`.
      -- 0221 (revisão): o v_pos aceita também `*` (`alter table t* disable trigger`, `update t *`, `delete from t *` são SQL válido); `drop table a, b` aceita lista; e DDL de FUNÇÃO (drop, alter, create or replace)
      -- sobre a função de qualquer gatilho das tabelas protegidas (v_gfn, pelo catálogo) conta como escrita.
      -- NÃO enxerga (declarado): SQL dinâmico (`execute format(...)`, regproc em texto); função fora de public;
      -- a função que o gatilho chama só por SQL dinâmico. Chamar uma PORTA (fn_dial_auto_promover) de uma definer não conta, de propósito: é o caminho que o dono
      -- aprovou na 0137 (o gatilho de `decisao` promove, no máximo até N2, SÓ quando o veredito GLOBAL basta; o chamador não escolhe nada).
      v_tabs   := array_to_string(string_to_array(r.objeto, ','), '|');
      v_funs   := coalesce(string_to_array(nullif(split_part(r.marcador, ';', 1), ''), ','), array[]::text[]);
      -- As PORTAS são ASSINATURAS exatas (`fn_dial_auto_promover(text)`, separadas por `|`), resolvidas para oid: por NOME, qualquer sobrecarga herdaria a isenção (medido pela revisão
      -- independente: `fn_dial_auto_promover(int)` INVOKER com `update estagio_autonomia`, chamada por uma definer com EXECUTE para authenticated, deu presente = t). Assinatura que não resolve
      -- (a porta sumiu) vira NULL e é descartada: o filtro `is not null` impede que um NULL dentro do `<> all` anule a junção inteira e esconda o fecho.
      v_barr   := coalesce((select array_agg(to_regprocedure('public.' || btrim(q))::oid)
                              from unnest(string_to_array(nullif(split_part(r.marcador, ';', 2), ''), '|')) q
                             where to_regprocedure('public.' || btrim(q)) is not null), array[]::oid[]);
      v_pre    := replace(replace('(insert@+into$|update$|delete@+from$|merge@+into$|truncate$(table@+)?(only@+)?([a-z0-9_."]+@*,@*)*)(only@+)?("?public"?@*\.@*)?"?', '$', '(@+|(?="))'), '@', v_g);
      v_pos    := '"?(\s|;|$|\(|\)|,|\*)';
      -- 0221 PARTE B. O `$` é o mesmo do v_pre: espaço/comentário (v_g) ou nada se a próxima coisa for `"`. o parâmetro é montado em duas metades de propósito: escrito inteiro
      -- aqui, o corpo desta própria sonda casaria o critério e a poria no fecho (INVOKER, não é acusada, mas puxaria quem a chamasse).
      v_ddl    := replace(replace('(alter@+table$(if@+exists$)?(only$)?|drop@+table$(if@+exists$)?([a-z0-9_."]+@*,@*)*|drop@+trigger$(if@+exists$)?("[^"]+"|[a-z0-9_]+)$on$(only$)?)("?public"?@*\.@*)?"?', '$', '(@+|(?="))'), '@', v_g);
      v_srr    := 'session_replication' || '_role';
      -- A GUARDA É A FUNÇÃO DE QUALQUER GATILHO das tabelas protegidas, resolvida pelo catálogo (pg_trigger), não o nome fixo: apagá-la ou trocá-la tira a guarda (o `drop` com cascata apaga os gatilhos
      -- junto) sem escrever linha. `v_gfn` = as funções que os requisitos `gatilho` das tabelas protegidas DECLARAM (marcador), escapadas e separadas por `|`: parte do ESPERADO, não do que estiver em pg_trigger agora (um gatilho trocado faria o v_gfn vigiar a função inofensiva). NULL se nada declarado (aí o critério não casa). DDL de função que cite um deles conta como escrita.
      v_gfn    := (select string_agg(distinct regexp_replace(g.marcador, '([.^$*+?()\[\]{}|\\])', '\\\1', 'g'), '|')
                     from instalacao_requisito g
                    where g.tipo = 'gatilho' and g.marcador is not null
                      and split_part(g.objeto, '.', 1) = any (select btrim(q) from unnest(string_to_array(r.objeto, ',')) q));
      v_dfn    := replace(replace('(drop@+(function|routine|procedure)$(if@+exists$)?([a-z0-9_."]+@*(\([^)]*\))?@*,@*)*|alter@+(function|routine|procedure)$|create@+(or@+replace@+)?(function|procedure)$)("?public"?@*\.@*)?"?', '$', '(@+|(?="))'), '@', v_g);
      if coalesce(v_tabs, '') = '' or cardinality(v_funs) = 0 then
        v_ok  := false;
        v_det := 'requisito mal declarado: objeto = tabelas protegidas (lista por vírgula) e marcador = RAIZES;PORTAS, com ao menos uma raiz';
      elsif v_gfn is null or exists (select 1 from instalacao_requisito g
                                      where g.tipo = 'gatilho' and g.marcador is not null
                                        and split_part(g.objeto, '.', 1) = any (select btrim(q) from unnest(string_to_array(r.objeto, ',')) q)
                                        and not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = g.marcador)) then
        -- 0221 (re-revisão, regra 7): sem guarda DECLARADA (marcador nulo nos requisitos `gatilho` das tabelas protegidas, ou declarada e inexistente) o ramo `gatilho` volta a só conferir que o gatilho existe, e o
        -- critério de DDL de função (v_gfn) desliga calado: a sonda ficaria verde sem vigiar nada. Aqui isso é AUSENTE, com o motivo. Só a 0216 zera o marcador (on conflict com excluded.marcador nulo).
        v_ok  := false;
        v_det := format('nenhuma guarda declarada no catálogo para %s (ou a declarada não existe em public) — a troca do gatilho e o DDL da função da guarda não estão sendo vigiados', r.objeto);
      else
        with recursive
          fn as materialized (
            select p.oid, p.proname::text as nome, p.prosecdef, p.prorettype,
                   case when p.prosqlbody is not null then pg_get_function_sqlbody(p.oid) else p.prosrc end as src
              from pg_proc p
             -- o filtro de schema é um predicado do PRÓPRIO scan, e não um join: com o join o planner calculava o pg_get_function_sqlbody de TODA função do
             -- banco (as do pg_catalog também) antes de descartar as que não são de public: medido 610 ms só nisso, na sonda inteira de ~100 ms.
             where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')),
          -- gatilhos: (função do gatilho, tabela). Fora do recursive e SEM subconsulta correlacionada: com `exists (select ... from pg_trigger ...)` dentro do join do recursive
          -- a sonda inteira foi de ~100 ms para ~700 ms (medido); com este left join, ~30 ms.
          gat as materialized (
            select t.tgfoid as oid, regexp_replace(c.relname, '([.^$*+?()\[\]{}|\\])', '\\\1', 'g') as rel
              from pg_trigger t
              join pg_class c on c.oid = t.tgrelid
             where not t.tgisinternal and c.relnamespace = 'public'::regnamespace),
          fecho(oid) as (
            select f.oid from fn f
             where f.src ~* (v_pre || '(' || v_tabs || ')' || v_pos)
                or f.src ~* (v_ddl || '(' || v_tabs || ')' || v_pos)
                or f.src ~* v_srr
                or f.src ~* (v_dfn || '(' || v_gfn || ')' || v_pos)
                or f.nome = any (v_funs)
            union
            select x.oid
              from fecho fe
              join fn y on y.oid = fe.oid and y.oid <> all (v_barr)
              left join gat g on g.oid = y.oid
              join fn x on (x.src ~* ('(^|[^a-z0-9_])"?' || regexp_replace(y.nome, '([.^$*+?()\[\]{}|\\])', '\\\1', 'g') || '"?\s*\(')
                            or x.src ~* (v_pre || '(' || g.rel || ')' || v_pos))),
          acusadas as (
            select f.oid::regprocedure::text as nome
              from fn f
              join fecho on fecho.oid = f.oid
             where f.prosecdef
               and (f.prorettype in ('trigger'::regtype, 'event_trigger'::regtype) or has_function_privilege('authenticated', f.oid, 'execute')))
        select count(*), string_agg(x.nome, ', ' order by x.nome) filter (where x.rn <= 15)
          into v_n, v_lista
          from (select a.nome, row_number() over (order by a.nome) as rn from acusadas a) x;
        v_ok  := v_n = 0;
        v_det := case when v_ok then format('nenhuma função SECURITY DEFINER alcançável pelo portal (EXECUTE para authenticated, ou de gatilho/event trigger) escreve em %s, direta ou indiretamente (por função que chama ou por gatilho)', r.objeto)
                      else format('%s função(ões) SECURITY DEFINER alcançáveis pelo portal escrevem em %s ou chamam quem escreve (direto, por função chamada ou por gatilho da tabela que escrevem) — a guarda de Sócio as deixa passar, porque rodam como dono: %s%s',
                                  v_n, r.objeto, v_lista, case when v_n > 15 then ' ...' else '' end) end;
      end if;

    elsif r.tipo = 'sem_acao_referencial' then
      -- 0219: a AÇÃO REFERENCIAL de uma FK (on delete|update cascade, set null, set default) roda como DONO da tabela filha (medido: num `on delete set null` o gatilho do filho viu
      -- current_user = postgres). A guarda de Sócio confia em quem roda como dono; então uma FK cujo FILHO é uma tabela protegida deixaria o Analista que apaga o PAI alterar o dial ou o
      -- catálogo sem ser Sócio. `objeto` = as tabelas protegidas. Acusa (A) toda FK com a tabela protegida como FILHA e ação em c|n|d (delete OU update), e (B) toda FK com ação
      -- c|n|d cuja tabela FILHA tem gatilho cuja função (corpo DIRETO, sem o fecho) escreve nas tabelas protegidas: a ação dispara o gatilho como dono. `restrict` e `no action` não
      -- alteram linha e ficam de fora. A FK que TEM a protegida como PAI (golden_criterio -> estagio_autonomia, on delete cascade) não conta: ela apaga a linha do FILHO, que não é protegido.
      v_tabs := array_to_string(string_to_array(r.objeto, ','), '|');
      v_pre  := replace(replace('(insert@+into$|update$|delete@+from$|merge@+into$|truncate$(table@+)?(only@+)?([a-z0-9_."]+@*,@*)*)(only@+)?("?public"?@*\.@*)?"?', '$', '(@+|(?="))'), '@', v_g);
      v_pos  := '"?(\s|;|$|\(|\)|,|\*)';
      if coalesce(v_tabs, '') = '' then
        v_ok  := false;
        v_det := 'requisito mal declarado: objeto = tabelas protegidas, lista por vírgula';
      else
        select count(*), string_agg(x.nome, '; ' order by x.nome) filter (where x.rn <= 15)
          into v_n, v_lista
          from (select y.nome, row_number() over (order by y.nome) as rn
                  from (select format('%s -> %s (%s, ON DELETE %s, ON UPDATE %s%s)', c.conrelid::regclass, c.confrelid::regclass, c.conname,
                                      case c.confdeltype when 'c' then 'CASCADE' when 'n' then 'SET NULL' when 'd' then 'SET DEFAULT' else 'sem alteração' end,
                                      case c.confupdtype when 'c' then 'CASCADE' when 'n' then 'SET NULL' when 'd' then 'SET DEFAULT' else 'sem alteração' end,
                                      case when c.conrelid = any (select to_regclass('public.' || trim(t)) from unnest(string_to_array(r.objeto, ',')) t) then ''
                                           else ', o filho tem gatilho que escreve na tabela protegida' end) as nome
                          from pg_constraint c
                         where c.contype = 'f'
                           and (c.confdeltype in ('c', 'n', 'd') or c.confupdtype in ('c', 'n', 'd'))
                           and (c.conrelid = any (select to_regclass('public.' || trim(t)) from unnest(string_to_array(r.objeto, ',')) t)
                                or exists (select 1
                                             from pg_trigger t
                                             join pg_proc p on p.oid = t.tgfoid
                                            where t.tgrelid = c.conrelid and not t.tgisinternal
                                              and (case when p.prosqlbody is not null then pg_get_function_sqlbody(p.oid) else p.prosrc end) ~* (v_pre || '(' || v_tabs || ')' || v_pos)))) y) x;
        v_ok  := v_n = 0;
        v_det := case when v_ok then format('nenhuma FK com ação referencial (cascade, set null, set default) altera linha de %s', r.objeto)
                      else format('%s FK(s) com ação referencial que alteram %s como dono, sem passar pela guarda de Sócio: %s%s', v_n, r.objeto, v_lista,
                                  case when v_n > 15 then ' ...' else '' end) end;
      end if;

    elsif r.tipo = 'rls_ligada' then
      -- 0221 PARTE A: a RLS por mandato (0216) só vale com a RLS LIGADA. Nenhum requisito do catálogo conferia `pg_class.relrowsecurity`: desligá-la numa tabela, ou criar tabela
      -- nova sem ela, não acendia nada. `objeto` = o SCHEMA (hoje 'public'): TODAS as tabelas (relkind r e p) do schema, e não uma lista, porque a lista é exatamente o que uma tabela
      -- nova não está. Fora da conta, de propósito: tabela de EXTENSÃO (pg_depend 'e'), que o dono do projeto não altera. Ausente = lista das tabelas sem RLS (até 15).
      -- Lê só o catálogo, e roda como o chamador: `pg_class` é legível por todos.
      if to_regnamespace(r.objeto) is null then
        v_ok  := false;
        v_det := format('o schema %s nem existe', r.objeto);
      else
        select count(*) filter (where not x.rls), string_agg(x.nome, ', ' order by x.nome) filter (where x.rn <= 15 and not x.rls), count(*)
          into v_n, v_lista, v_tot
          from (select c.relname::text as nome, c.relrowsecurity as rls, row_number() over (partition by c.relrowsecurity order by c.relname) as rn
                  from pg_class c
                 where c.relnamespace = to_regnamespace(r.objeto)
                   and c.relkind in ('r', 'p')
                   and not exists (select 1 from pg_depend d where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e')) x;
        -- Regra 7: o verde só vale se ALGO foi examinado. Schema que existe e está vazio (ex.: graphql_public) daria presente sem olhar tabela nenhuma.
        v_ok  := v_n = 0 and v_tot > 0;
        v_det := case when v_tot = 0 then format('nenhuma tabela examinada em %s (o schema existe e não tem tabela): a conferência não olhou nada', r.objeto)
                      when v_ok then format('%s tabelas examinadas em %s, todas com a RLS ligada', v_tot, r.objeto)
                      else format('%s tabela(s) de %s com a RLS DESLIGADA (a policy por mandato não vale nelas): %s%s', v_n, r.objeto, v_lista, case when v_n > 15 then ' ...' else '' end) end;
      end if;

    elsif r.tipo in ('seed', 'comportamento') then
      -- A tabela pode não existir ainda: contar nela levantaria erro e derrubaria
      -- a sonda inteira, transformando "um requisito faltando" em "o painel não
      -- abre". A sonda de instalação é o último lugar do sistema que pode falhar
      -- por causa do que ela existe para medir.
      v_alvo := to_regclass('public.' || r.objeto);
      if v_alvo is null then
        v_ok  := false;
        v_det := 'a tabela nem existe';
      else
        -- 0132: CONTAGEM LIMITADA AO CRITÉRIO. Ver o cabeçalho: a pergunta é
        -- ">= criterio", e varrer a tabela inteira para respondê-la faz o custo
        -- do painel crescer junto com `lote_execucao`, que cresce para sempre.
        v_crit := greatest(coalesce(r.criterio_seed, 1), 1);
        execute format('select count(*) from (select 1 from public.%I limit %s) x',
                       r.objeto, v_crit)
           into v_n;
        v_ok := v_n >= v_crit;
        -- No caso PRESENTE o total exato não é conhecido (nem usado pela tela).
        -- No caso AUSENTE ele é exato por construção — a varredura parou antes do
        -- limite, logo passou por tudo — e é nele que o número informa algo:
        -- "3 linha(s)" com critério 8 diz que o seed rodou pela metade.
        v_det := case when v_ok then format('%s linha(s) ou mais', v_crit)
                      else format('%s linha(s)', v_n) end;
      end if;
    end if;

    return query select r.chave, r.migration, r.tipo, r.objeto, v_ok, v_det,
                        r.porque, r.severidade;
  end loop;
end;
$function$;


-- Os requisitos novos. A sonda de produção passa a PROVAR que a 0221 foi aplicada (sem requisito com `migration = '0221'` o `sonda-producao.mjs --so-buraco` não tem rastro dela).
-- Marcador = UMA linha do corpo de fn_instalacao_conferir, como `pg_get_functiondef` a devolve.
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('rls_ligada_em_public', '0221', 'rls_ligada', 'public', null, null,
   'Toda tabela de public tem de ter a RLS LIGADA: a RLS por mandato (0216) só vale com ela, e as policies continuam no catálogo mesmo com a RLS desligada, então nada acusava. Ausente = a lista das tabelas sem RLS: nelas o dado de um mandato é legível por outro. Em produção a RLS de tabela nova é ligada pelo event trigger da plataforma (ensure_rls), que o banco local não tem.',
   'bloqueante', 1001),
  ('sonda_ve_rls_ligada', '0221', 'corpo', 'fn_instalacao_conferir', 'elsif r.tipo = ''rls_ligada'' then', null,
   'O tipo `rls_ligada` precisa de ramo na sonda: sem ele a linha rls_ligada_em_public cairia no fim do laço sem ramo nenhum e voltaria presente = false com detalhe nulo (ou, numa reemissão velha, a constraint recusaria o tipo). O marcador é a linha do ramo.',
   'bloqueante', 1002),
  ('sonda_dial_ve_ddl_na_protegida', '0221', 'corpo', 'fn_instalacao_conferir', 'or f.src ~* (v_ddl || ''('' || v_tabs || '')'' || v_pos)', null,
   'O portão definer_nao_escreve_no_dial só via ESCRITA DE LINHA: uma definer com EXECUTE para authenticated e `alter table estagio_autonomia disable trigger`, `drop trigger ... on <protegida>` ou `alter table <protegida> disable row level security` não era acusada, e desliga a guarda de Sócio na mesma transação em que o Analista escreve no dial. O marcador é a linha do fecho que inclui o DDL sobre a tabela protegida.',
   'bloqueante', 1003),
  ('sonda_dial_ve_ddl_da_funcao_da_guarda', '0221', 'corpo', 'fn_instalacao_conferir', 'or f.src ~* (v_dfn || ''('' || v_gfn || '')'' || v_pos)', null,
   'O portão definer_nao_escreve_no_dial não via DDL de FUNÇÃO: uma definer com EXECUTE para authenticated e `drop function ... cascade` (ou create or replace, ou alter function) sobre a função de gatilho das tabelas protegidas apaga ou troca a guarda de Sócio sem escrever linha. A guarda é resolvida pelo catálogo (a função de qualquer gatilho das tabelas protegidas). O marcador é a linha do fecho que inclui esse DDL.',
   'bloqueante', 1005),
  ('sonda_gatilho_chama_a_guarda_declarada', '0221', 'corpo', 'fn_instalacao_conferir', 'v_ok  := v_proc is not null and v_tgf = v_proc::oid;', null,
   'O ramo `gatilho` só conferia que o gatilho EXISTE e está habilitado: `create or replace trigger trg_estagio_autonomia_so_socio ... execute function <inofensiva>` troca a guarda de Sócio do dial por nada, com o mesmo nome e habilitado, e acesso_gatilho_dial seguia presente. O marcador é a linha que compara a função que o gatilho chama com a que o requisito declara.',
   'bloqueante', 1006),
  ('sonda_dial_ve_replication_role', '0221', 'corpo', 'fn_instalacao_conferir', 'or f.src ~* v_srr', null,
   'O parâmetro de sessão de replicação em modo `replica` faz o Postgres PULAR todos os gatilhos, inclusive a guarda de Sócio, e uma definer que o ajusta não escreve linha nenhuma. O marcador é a linha do fecho que o inclui em qualquer lugar do corpo.',
   'bloqueante', 1004)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

-- A 0221 muda a linha do v_pos nos dois ramos (acrescenta `\*`: `alter table t* ...`, `update t *`, `delete from t *`), e os marcadores dos requisitos da 0220 eram essa linha EXATA. Sem trocá-los, a sonda
-- acusaria a 0220 como ausente em produção logo depois de a 0221 ser aplicada (falso alarme). Trocados aqui, ficam com a migration '0220' (quem os declarou).
update instalacao_requisito set marcador = 'v_pos    := ''"?(\s|;|$|\(|\)|,|\*)''' where chave = 'sonda_dial_v_pos_fecha_o_definer';
update instalacao_requisito set marcador = 'v_pos  := ''"?(\s|;|$|\(|\)|,|\*)''' where chave = 'sonda_dial_v_pos_fecha_a_fk';

-- 0221 (revisão): os dois requisitos `gatilho` das tabelas protegidas passam a DECLARAR a função da guarda no `marcador` (o ramo `gatilho` agora confere que o gatilho a chama).
update instalacao_requisito set marcador = 'fn_trg_so_socio' where chave in ('acesso_gatilho_dial', 'acesso_gatilho_premissa_catalogo');

update instalacao_cobertura
   set ate_migration = '0221', revisado_em = current_date,
       observacao = 'A 0221 acrescenta à sonda o tipo rls_ligada (rls_ligada_em_public, bloqueante: a RLS por mandato da 0216 só vale com a RLS ligada, e nenhum requisito a conferia) e faz o portão definer_nao_escreve_no_dial enxergar DDL: alter table / drop table / drop trigger ... on <tabela protegida> e o parâmetro de sessão de replicação contam como escrita. Reemite fn_instalacao_conferir inteira e acrescenta 3 requisitos corpo (sonda_ve_rls_ligada, sonda_dial_ve_ddl_na_protegida, sonda_dial_ve_replication_role) que provam em produção que a 0221 foi aplicada.'
 where id = true;
