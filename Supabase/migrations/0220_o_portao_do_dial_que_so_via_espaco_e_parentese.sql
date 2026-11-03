-- =============================================================================
-- 0220 — O PORTÃO DO DIAL QUE SÓ VIA O NOME DA TABELA SEGUIDO DE ESPAÇO, `;`, FIM OU `(`
-- (REDEFINE 1 função, fn_instalacao_conferir, só nos ramos `definer_sem_escrita` e `sem_acao_referencial`; +3 requisitos novos na sonda, todos `corpo` sobre fn_instalacao_conferir.
--  Sem tabela, sem backfill, sem dado alterado, SEM tipo novo (a constraint de tipo fica com os 13 da 0219). Idempotente: pode ser reaplicada.)
--
-- >>> RODE COMO `postgres`, como a 0219. A 0219 está APLICADA e CONFERIDA em produção (03/11/2026, PR #270) e NÃO foi tocada: esta migration é por cima dela.
--
-- ===== O DEFEITO: o portão `definer_nao_escreve_no_dial` dava VERDE para função que apaga o catálogo =====
-- O portão da 0219 acha as funções que escrevem em estagio_autonomia / premissa_catalogo com um regex: o prefixo (`delete from`, `update`, `insert into`, `merge into`,
-- `truncate a, b,`) seguido do nome da tabela seguido de `v_pos`. `v_pos` era `"?(\s|;|$|\()`: espaço, `;`, fim do texto ou `(`. FECHAR O PARÊNTESE ou SEPARAR POR VÍRGULA
-- não estava na lista. Medido pela revisão independente de 03/11/2026, num banco com a 0219:
--   * `with d as (delete from premissa_catalogo) select ...`, SECURITY DEFINER, EXECUTE para authenticated: sonda `definer_nao_escreve_no_dial` presente = t (verde). Uma Analista a
--     chamou e o catálogo foi de 89 a 0 linhas: a guarda de Sócio confia em quem roda como dono (0219), e o dono era a definer;
--   * `truncate premissa_catalogo, caso_premissa` (a tabela protegida vem ANTES da vírgula) e `(delete from estagio_autonomia)` escapavam igual.
-- Não há sintoma até o dia em que alguém escreve uma função assim: a sonda diz "nenhuma função burla a guarda" sobre um banco em que uma burla (regra 7: o portão que não
-- viu tem a mesma cara do portão que viu e não achou nada). O dono conferiu em PRODUÇÃO, só leitura (informado no pedido; eu não o refiz), que com o `v_pos` corrigido o portão
-- continua verde: nenhuma função real é acusada. A consulta que repete isso com o `v_pre` novo também está no relatório que acompanha esta migration. Esta migration NÃO muda nenhuma função
-- do projeto, só o que a sonda enxerga.
--
-- A CAUSA, medida. O `v_pos` entra em TRÊS pontos do mesmo ramo (a varredura do corpo da função, a aresta do GATILHO da tabela que a definer escreve, `g.rel`, e a parte B do ramo da FK);
-- todos usam a MESMA variável, e por isso uma correção só no primeiro seria um falso verde nos outros dois. Medido por regex puro, em 14 formatos de DML, antes e depois:
-- `delete from t)` (CTE ou parêntese), `truncate t, x` e `(delete from t)` eram os que o v_pos antigo não via, e os 11 restantes davam o mesmo resultado nos dois.
--
-- A CORREÇÃO. (1) `v_pos := '"?(\s|;|$|\(|\)|,)'`, nos dois ramos (definer e FK). (2) O outro lado, o `v_pre`, tinha buraco EQUIVALENTE e real (medido: as quatro funções abaixo são SQL
-- válido e executam): `delete from"t"` e `update"t" set` (aspas coladas na palavra, sem espaço), `delete from/* c */t` e `delete from -- c<quebra>t` (comentário entre a palavra e o nome). O
-- v_pre só aceitava `\s+` depois da palavra. Agora aceita, no lugar do espaço, `v_g` = espaço, comentário de bloco ou comentário de linha, ou nada SE a próxima coisa for `"` (lookahead).
-- Falso positivo novo? Medido por regex puro em 16 formatos (`premissa_catalogo_x`, `premissa_catalogox`, `select * from premissa_catalogo`, a palavra em comentário de OUTRA tabela): nenhum
-- passou a casar, e a leitura em subconsulta `(select ... from premissa_catalogo)` não casa porque o `)` só vale depois de uma palavra de escrita (assert 2g do teste).
-- LIMITES (declarados, regra 1): SQL dinâmico (`execute format(...)`) segue fora do alcance, como na 0219; a palavra de escrita citada num COMENTÁRIO ou num literal de texto acusa a mais (o lado
-- seguro, como na 0219); e o portão varre ESCRITA DE LINHA (DML), não DDL: um `alter table ... disable trigger` dentro de uma definer não é escrita de linha e não entra aqui (fora do escopo da 0220).
-- O custo, medido (a sonda inteira, banco do replay completo, mediana de 15 execuções): ~67 ms com a 0219 e ~77 ms com a 0220 (+10 ms).
--
-- ===== OS COMENTÁRIOS DA 0219 QUE ESTAVAM ERRADOS (corrigidos AQUI, não no arquivo da 0219, que já está em produção) =====
--   * A linha 28 da 0219 dizia que `fn_instalacao_conferir` é chamada pelo "portal (tela da sonda), n8n/sonda agendada". Não é: ela é chamada pelo GitHub Actions
--     (`.github/workflows/sonda-producao.yml` -> `Supabase/test/sonda-producao.mjs`) e pelo SQL Editor; o portal NÃO a chama (grep -rn fn_instalacao_conferir portal/src: nenhuma ocorrência).
--   * As linhas 66 e 595 da 0219 declaravam VIEW atualizável e RULE como PONTOS CEGOS do portão. Não são, e a 0220 o prova por comportamento (PARTE 4 do teste): a view e a regra rodam com os
--     privilégios do dono, mas `current_user` segue authenticated, e a guarda de Sócio recusa com 42501. O comentário que estava DENTRO do corpo reemitido de fn_instalacao_conferir
--     foi corrigido na reemissão (abaixo); o da linha 66 é do cabeçalho da 0219 e fica errado lá, por isso esta nota.
--
-- A SONDA. `fn_instalacao_conferir` reemitida INTEIRA a partir do corpo da 0219 (ramos `segredo`, `sem_privilegio`, `definer_sem_escrita` e `sem_acao_referencial` preservados; o teste reprova se
-- algum sumir). O diff contra a 0219 é só: a variável `v_g` (1 linha em declare), as duas linhas do `v_pre` e as duas do `v_pos` (uma de cada por ramo), e o comentário do ramo definer.
-- +3 requisitos `corpo` sobre fn_instalacao_conferir (a sonda sabe, em produção, que a 0220 foi aplicada, e que nenhum ramo voltou ao v_pos velho):
--   sonda_dial_v_pos_fecha_o_definer (a linha do v_pos do ramo definer), sonda_dial_v_pos_fecha_a_fk (a da FK) e sonda_dial_v_g_ve_aspas_e_comentario (a variável v_g).
-- Os marcadores são de UMA linha (o corpo em produção pode vir com CRLF) e distintos entre si e da 0219: o do definer tem 4 espaços antes do `:=`, o da FK tem 2, e nenhum deles é
-- substring do outro (conferido). `Supabase/test/sonda_marcador_e_codigo.test.sql` aceita (têm `_`, `(`, `=`).
--
-- QUEM CHAMA fn_instalacao_conferir (grep -rn em Supabase/ N8N/ portal/ .github/, 03/11/2026): o workflow `sonda-producao.yml` (-> sonda-producao.mjs), o SQL Editor, testes e
-- conferir-chamadas. A assinatura de retorno NÃO mudou.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/o_portao_do_dial_que_so_via_espaco_e_parentese.test.sql — 37 dos 37 asserts medidos em 03/11/2026 com
-- `PGOPTIONS='-c dial.medindo=on'` (o assert vira `raise warning` e CONTA; sem a variável é `raise exception`; o `run.sh` completo foi rodado sem ela e o log relido INTEIRO atrás de FALHOU).
-- Controle intacto: 37 ok, 0 falhas. Cada correção desligada UMA vez, num banco que já tem a 0220, com a variante reaplicada por `\i` (`-v arq0220=<arquivo>`):
--   (em todas a migration APLICOU, rc 0, e o log traz a linha FIM com 37 execuções, salvo onde dito; 'marcador' = os 3 asserts do catálogo que dependem do requisito da linha desligada)
--   * v_pos ANTIGO no ramo definer (`"?(\s|;|$|\()`): 9 reprovam (3 de marcador + 6 de comportamento: o CTE em premissa_catalogo, o CTE em estagio_autonomia, os dois truncates, as aspas coladas
--     e a aresta do gatilho);
--   * v_pos do ramo definer SEM o `)` (só a vírgula): 7 (3 de marcador + 4: os dois CTE, as aspas coladas dentro do CTE e a aresta do gatilho);
--   * v_pos do ramo definer SEM a `,` (só o `)`): 5 (3 de marcador + os dois truncates);
--   * v_pos ANTIGO na parte B da FK: 5 (3 de marcador + 2: o gatilho do filho em CTE e em `truncate a, b`);
--   * a aresta do gatilho (`g.rel`) com o v_pos antigo, o resto novo: 1 (a definer que apaga `(delete from zz_t_0220)` numa tabela com gatilho: o único assert que prova a terceira ponta do v_pos);
--   * v_pre ANTIGO no ramo definer (só `\s+`): 4 (as aspas coladas, nos dois formatos, e o comentário de bloco e o de linha); v_pre ANTIGO na parte B da FK: 1 (o gatilho do filho em `delete from"t"`);
--   * v_g só com `\s` (sem comentário): 5 (3 de marcador + os 2 de comentário); o lookahead `(?=")` fora (sem as aspas coladas), nos dois ramos: 3 (os dois do definer e o da FK);
--   * os requisitos da 0220 não inseridos (apagados no fim da variante): 2;
--   * a reemissão SEM o ramo `segredo` (0217): 1 · sem o `sem_privilegio` (0218): 1 · sem o `definer_sem_escrita` (0219): 18 · sem o `sem_acao_referencial` (0219): 7;
--   * a constraint de tipo SEM `sem_acao_referencial`: a migration MORRE ("violated by some row", rc 3) e nenhum assert roda — isto NÃO é zero reprovações, é migration recusada.
-- Os asserts de BURLA (2a e 2d: a Analista apaga o catálogo de N a 0) e os de VIEW/RULE (PARTE 4) são CONTROLES do arranjo, não de uma correção: nenhuma variante os reprova (a burla existe com ou sem a
-- sonda; a view e a regra seguem recusadas pela guarda). Limite do teste: o arranjo da FK usa gatilho BEFORE do filho e só lê o corpo direto dele, como a 0219.
-- =============================================================================

alter table instalacao_requisito drop constraint if exists instalacao_requisito_tipo_check;
alter table instalacao_requisito add constraint instalacao_requisito_tipo_check
  check (tipo in ('tabela', 'coluna', 'funcao', 'seed', 'comportamento', 'corpo', 'gatilho', 'policy', 'privilegio', 'segredo', 'sem_privilegio', 'definer_sem_escrita', 'sem_acao_referencial'));

-- fn_instalacao_conferir: a da 0219 INTEIRA (a que a produção tem desde 03/11/2026), só com v_g, v_pre e v_pos nos dois ramos e o comentário do ramo definer. NÃO partir de outra:
-- reemitir a função de antes APAGARIA um ramo.
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
        select tgenabled, tgfoid::regproc::text
          into v_tg_enabled, v_tg_fn
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
          -- `session_replication_role = origin`, que é o padrão de toda sessão
          -- normal (é o que o pooler do Supabase usa). Do ponto de vista de
          -- quem depende da guarda rodando na sessão normal, um gatilho em
          -- modo réplica está tão desligado quanto um desabilitado — só que
          -- calado, porque `tgenabled <> 'D'` deixaria passar.
          v_ok  := false;
          v_det := 'o gatilho existe mas só dispara em modo réplica — na sessão normal a guarda não roda';
        elsif v_tg_enabled in ('O', 'A') then
          -- 'O' = ENABLE (origin, o padrão) · 'A' = ENABLE ALWAYS (dispara em
          -- origin e em réplica). As duas rodam em sessão normal — é só isso
          -- que este ramo promete. Ele NÃO confere se o gatilho chama a
          -- função certa nem em quais eventos (INSERT/UPDATE/DELETE) — só que
          -- existe e dispara. `v_tg_fn` entra no detalhe por informação, sem
          -- afetar `v_ok`.
          v_ok  := true;
          v_det := format('gatilho habilitado (chama %s)', coalesce(v_tg_fn, '?'));
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
      v_pos    := '"?(\s|;|$|\(|\)|,)';
      if coalesce(v_tabs, '') = '' or cardinality(v_funs) = 0 then
        v_ok  := false;
        v_det := 'requisito mal declarado: objeto = tabelas protegidas (lista por vírgula) e marcador = RAIZES;PORTAS, com ao menos uma raiz';
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
      v_pos  := '"?(\s|;|$|\(|\)|,)';
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

-- Os três requisitos novos: a sonda de produção passa a PROVAR que a 0220 foi aplicada (sem requisito com `migration = '0220'` o `sonda-producao.mjs --so-buraco` não tem rastro dela).
-- Marcador = UMA linha do corpo de fn_instalacao_conferir, com o espaçamento exato do que `pg_get_functiondef` devolve (o ramo definer indenta o `:=` com 4 espaços, o da FK com 2).
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('sonda_dial_v_pos_fecha_o_definer', '0220', 'corpo', 'fn_instalacao_conferir', 'v_pos    := ''"?(\s|;|$|\(|\)|,)''', null,
   'O portão definer_nao_escreve_no_dial só via o nome da tabela protegida seguido de espaço, `;`, fim ou `(`: `with d as (delete from premissa_catalogo) select`, `truncate premissa_catalogo, x` e `(delete from estagio_autonomia)` de uma definer com EXECUTE para authenticated davam presente = t, e uma Analista apagou o catálogo de 89 a 0 linhas (revisão independente de 03/11/2026). O marcador é a linha do v_pos do ramo definer, com `)` e `,`. Sem ela, a 0219 voltou e o portão dá verde para a burla da guarda de Sócio.',
   'bloqueante', 997),
  ('sonda_dial_v_pos_fecha_a_fk', '0220', 'corpo', 'fn_instalacao_conferir', 'v_pos  := ''"?(\s|;|$|\(|\)|,)''', null,
   'A parte B do requisito dial_sem_cascata_de_fk (o filho da FK tem gatilho que escreve na tabela protegida) usa o MESMO v_pos do ramo definer, em outra linha: a 0219 o tinha sem `)` e `,` nos dois. O marcador é a linha do v_pos do ramo da FK (2 espaços antes do `:=`, distinto do marcador do ramo definer).',
   'bloqueante', 998),
  ('sonda_dial_v_g_ve_aspas_e_comentario', '0220', 'corpo', 'fn_instalacao_conferir', 'v_g          text := ''(\s|/\*([^*]|\*+[^*/])*\*+/|--[^\n]*\n)''', null,
   'O prefixo do DML (`delete from`, `update`, `insert into`, `merge into`, `truncate`) só aceitava espaço antes do nome da tabela: `delete from"premissa_catalogo"` (aspas coladas) e `delete from /* c */ premissa_catalogo` (comentário no meio) são SQL válido, executam, e o portão não os via. O marcador é a declaração de v_g, a lacuna que o prefixo agora aceita: espaço, comentário de bloco, comentário de linha ou nada se vier aspas.',
   'bloqueante', 999)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0220', revisado_em = current_date,
       observacao = 'A 0220 fecha o falso verde do portão definer_nao_escreve_no_dial (e da parte B de dial_sem_cascata_de_fk): o nome da tabela protegida seguido de `)` ou `,` (`with d as (delete from premissa_catalogo) select`, `truncate premissa_catalogo, x`, `(delete from estagio_autonomia)`) e o prefixo com aspas coladas ou comentário (`delete from"t"`, `delete from /* c */ t`) davam presente = t. Reemite fn_instalacao_conferir inteira, sem tipo novo, e acrescenta 3 requisitos corpo (sonda_dial_v_pos_fecha_o_definer, sonda_dial_v_pos_fecha_a_fk, sonda_dial_v_g_ve_aspas_e_comentario) que provam em produção que a 0220 foi aplicada.'
 where id = true;
