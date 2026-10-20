-- =============================================================================
-- 0214 — O GRANT QUE O SUPABASE DEIXOU DE DAR: acesso explícito às tabelas de `public` (e a sonda que o cobra)
-- (Só concede privilégio, reaplica os revokes intencionais e acrescenta um ramo à sonda. Sem tabela, sem função de
--  negócio, sem backfill. NO-OP EM PRODUÇÃO: os privilégios abaixo já existem lá.)
--
-- O DEFEITO, avisado pelo Supabase e medido em 20/10/2026. A partir de 30/10/2026, tabela criada em `public` deixa
-- de receber GRANT automático para anon/authenticated/service_role (até então vinha dos default privileges que o
-- projeto trazia). Vale para TODO replay de migrations — projeto novo, preview branch, `supabase db reset` — e as
-- tabelas que já existem mantêm o que têm. Este repositório dependia inteiramente do comportamento antigo:
-- 51 `create table` nas migrations, 39 sem nenhum GRANT (a mais nova, `controlador_vinculo`, da 0212), e o
-- `Supabase/test/run.sh` SIMULAVA o default antigo (`alter default privileges ... grant all on tables`), de modo que
-- o CI continuaria verde depois de 30/10 enquanto a primeira tabela nova nascia em produção sem acesso: PostgREST
-- devolve "permission denied" e a tela quebra sem nenhuma suíte ter avisado (regra 7).
--
-- O QUE MUDA, em três partes (todas no mesmo PR):
--   1. `run.sh` deixa de simular o default: o replay passa a ser o do Supabase novo. Medido: com isso o replay
--      MORRE na 0028 (a verificação embutida roda como authenticated e leva 42501), e depois dela
--      `resumo_oficial.test.sql` e outros testes que fazem `set role authenticated` caem em
--      "permission denied for table caso". A 0028 ganhou UMA linha de grant (no-op em produção, comentada no lugar);
--      é a única edição de migration já aplicada, e só porque nenhuma migration posterior pode consertar uma anterior
--      que aborta antes dela.
--   2. ESTA migration concede, nas tabelas que existem neste ponto do replay, o que o portal usa:
--        authenticated: SELECT/INSERT/UPDATE/DELETE em tabela; SELECT em view; USAGE em sequence.
--        service_role:  SELECT/INSERT/UPDATE/DELETE em tabela; SELECT em view; USAGE em sequence.
--      NÃO concede nada a `anon`: o portal usa a chave anon só para abrir a sessão (cookie, supabase-js em
--      `portal/src/lib/supabase/{client,server,proxy}.ts`) e todo acesso a tabela e RPC corre como `authenticated`;
--      nenhuma leitura de tabela acontece sem sessão (conferido por grep em `portal/src`). O que o Supabase dava a
--      `anon` por default em produção NÃO é removido (esta migration nunca revoga o que já existe), mas um replay novo
--      deixa de herdá-lo — que é o comportamento correto. TRUNCATE/REFERENCES/TRIGGER também não são concedidos: nada
--      do portal os usa.
--   3. A sonda (`fn_instalacao_conferir`) ganha o tipo `privilegio`: toda tabela/view/sequence de `public` sem o
--      mínimo, vira buraco: SELECT para o authenticated (INSERT/UPDATE/DELETE variam de propósito — catálogo é só
--      leitura e seis tabelas perderam o delete —, então exigi-los da tabela inteira acusaria o revoke intencional;
--      foi o que a primeira versão fez, e o instalacao.test.sql reprovou), as quatro operações para o service_role
--      (nenhum revoke o atinge), SELECT nas views e USAGE nas sequences, para os dois. É o que faz `instalacao.test.sql` (dentro do
--      `run.sh`, que exige que um banco recém-migrado só esteja sem o requisito do n8n) reprovar NO CI uma migration
--      futura que esqueça o grant, e o `sonda-producao.mjs` agendado enxergar o mesmo em produção.
--
-- OS REVOKES INTENCIONAIS, e o mecanismo escolhido. Existem seis (todos `from authenticated`): delete em
-- arquivo_oficial (0206), perimetro, controlador e entidade_controlador (0210), controlador_vinculo (0212), e em
-- caso_pergunta update (exceto a coluna entidade_id, por GRANT de coluna) e delete (0213). Conferido por grep em
-- `revoke` nas migrations: não há outro em tabela (o único restante é `revoke all on function ... from public`, 0187).
-- A saída é "grant geral e depois os MESMOS revokes, na mesma migration (mesma transação no caminho do Supabase)":
--   * lista explícita de ~50 tabelas ficaria velha na primeira migration seguinte, e é a mesma lista que a sonda
--     acabou de aprender a dispensar;
--   * "grant geral" sozinho DESFARIA os revokes num replay — e em produção também, de passagem, por um instante;
--   * por isso o grant geral é seguido, no mesmo arquivo, da repetição literal de cada revoke. Em produção o estado
--     final é idêntico ao anterior (o grant devolve, o revoke tira). `revoke update` em nível de tabela remove também
--     os privilégios de coluna, então o `grant update (entidade_id)` da 0213 é repetido depois dele.
--   O teste prova o resultado final (authenticated SEM delete onde hoje não tem, e sem update fora de entidade_id em
--   caso_pergunta), não o mecanismo. Quem criar um novo revoke intencional o acrescenta AQUI e no teste.
--
-- CONVENÇÃO DAQUI PARA FRENTE (e está em `Supabase/README.md`, seção "Convenção de migration"): TODA migration que
-- cria tabela, view ou sequence concede, NA MESMA migration, o que o portal e o service_role usam. Esta migration
-- não cobre o futuro (o loop roda uma vez); quem cobre é a sonda.
--
-- Tabelas que NÃO devem ser acessíveis ao portal: nenhuma conhecida (o dono não declarou nenhuma, e a 0214 concede
-- a todas o que o portal usa; nenhuma tinha revoke de SELECT). Se aparecer uma, a regra da sonda ganha exceção
-- NOMEADA no catálogo, com o porquê — não uma isenção silenciosa.
--
-- NÃO HÁ BACKFILL: nenhuma linha muda.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/grant_de_tabela.test.sql — 19 chamadas de assert, 29 execuções (dois
-- asserts rodam em laço, 6 vezes cada), medidas em 20/10/2026 com o assert em `raise warning` (voltou para
-- `raise exception`; o log inteiro, sem nenhum FALHOU) e a migration conferida como APLICADA em cada variante
-- (`instalacao_cobertura.ate_migration = 0214`). Controle intacto: 29 ok, 0 falhou. Cada guarda desligada UMA por
-- vez numa cópia da migration:
--   * sem o grant geral (laço filtrado por `and false`): 12 das 29 execuções reprovam, e a sonda acusa 5 dos 6
--     requisitos (35 tabelas sem SELECT para authenticated, 49 sem as quatro operações para service_role, 10 views
--     sem SELECT para service_role, 1 sequence sem USAGE para cada papel);
--   * sem os revokes repetidos: 7 das 29 (o delete volta nas seis tabelas e o update fora de entidade_id em
--     caso_pergunta);
--   * ramo da sonda cego (`v_ok := true`): 8 das 29 (os seis requisitos deixam de acusar o objeto sem grant, e o
--     service_role deixa de distinguir o grant parcial);
--   * tabela nova sem grant numa migration 0215 sintética (a convenção esquecida): a sonda acusa os 2 requisitos de
--     tabela (`grant_tabelas_authenticated` e `grant_tabelas_service_role`, 1 objeto cada), `sonda-producao.mjs`
--     sai com 1 e `instalacao.test.sql` reprova ("ausentes: ... grant_tabelas_authenticated, ...") — é ESTE o
--     portão do CI, dentro do `run.sh`. O `--so-buraco` do `sonda-producao.mjs` NÃO o vê: ele só mede migration
--     declarada no README que não deixou rastro no catálogo, não requisito ausente.
-- O ANTES da suíte inteira (run.sh com a simulação do default removida): morria na 0028; com a 0028 consertada e sem
-- a 0214, caía em `resumo_oficial.test.sql` ("permission denied for table caso", exit 3) — e as 8 suítes que fazem
-- `set role authenticated` dependiam disso sem saber.
-- =============================================================================

do $$
declare
  v_c record;
begin
  for v_c in
    select c.oid, c.relkind, quote_ident(n.nspname) || '.' || quote_ident(c.relname) as nome
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind in ('r', 'p', 'v', 'm', 'S')
       and not exists (select 1 from pg_depend d
                        where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e')
  loop
    if v_c.relkind in ('r', 'p') then
      execute format('grant select, insert, update, delete on %s to authenticated, service_role', v_c.nome);
    elsif v_c.relkind in ('v', 'm') then
      execute format('grant select on %s to authenticated, service_role', v_c.nome);
    else
      execute format('grant usage, select on sequence %s to authenticated, service_role', v_c.nome);
    end if;
  end loop;
end $$;

-- Os revokes intencionais (0206, 0210, 0212, 0213), repetidos DEPOIS do grant geral. Ver o cabeçalho.
revoke delete on arquivo_oficial from authenticated;
revoke delete on perimetro from authenticated;
revoke delete on controlador from authenticated;
revoke delete on entidade_controlador from authenticated;
revoke delete on controlador_vinculo from authenticated;
revoke update on caso_pergunta from authenticated;
grant update (entidade_id) on caso_pergunta to authenticated;
revoke delete on caso_pergunta from authenticated;

-- -----------------------------------------------------------------------------
-- A SONDA PASSA A VER PRIVILÉGIO. O catálogo (tabela, coluna, função, corpo, gatilho, policy, seed) só sabe dizer
-- que o objeto EXISTE; uma tabela sem GRANT existe, tem policy e responde "permission denied" a todo o portal. Tipo
-- novo `privilegio`, objeto `papel:classe`, marcador = privilégios exigidos; a função abaixo é a da 0210 INTEIRA
-- (extraída do próprio arquivo, não replace de texto) com UM ramo novo.
-- -----------------------------------------------------------------------------
alter table instalacao_requisito drop constraint if exists instalacao_requisito_tipo_check;
alter table instalacao_requisito add constraint instalacao_requisito_tipo_check
  check (tipo in ('tabela', 'coluna', 'funcao', 'seed', 'comportamento', 'corpo', 'gatilho', 'policy', 'privilegio'));

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

comment on function fn_instalacao_conferir() is
  'Confere cada requisito de instalacao_requisito contra o catálogo do banco. Sobrevive ao objeto ausente (to_regclass/to_regproc devolvem NULL em vez de erro): a sonda não pode falhar por causa do que ela existe para medir. Desde a 0147 confere também o CORPO da função (tipo=corpo), que é o único jeito de distinguir uma correção aplicada de uma função homônima com o corpo velho. Desde a 0189 confere também GATILHO (tipo=gatilho): existência na tabela E tgenabled em (''O'',''A'') — a função do gatilho sobrevive a drop trigger/disable trigger e por isso NUNCA prova, sozinha, que a guarda está ligada. Desde a 0210 confere também POLICY (tipo=policy, objeto tabela.nome_da_policy): existência em pg_policy. Desde a 0214 confere PRIVILÉGIO (tipo=privilegio, objeto papel:classe, marcador = privilégios): toda tabela/view/sequence de public sem o mínimo para authenticated e service_role é buraco — o Supabase deixou de conceder por default privilege em 30/10/2026.';

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('grant_tabelas_authenticated', '0214', 'privilegio', 'authenticated:tabelas', 'select', null,
   'Tabela de public sem SELECT para authenticated: o portal leva "permission denied" ao ler (a tela quebra). Desde 30/10/2026 o Supabase não concede mais por default; a migration que cria a tabela concede na mesma migration. Só SELECT é exigido de TODA tabela porque INSERT/UPDATE/DELETE variam de propósito (catálogo é só leitura; arquivo_oficial, perimetro e outras tiveram o delete revogado); a escrita ausente é pega pelo catálogo de policies e pelos testes como authenticated.',
   'bloqueante', 910),
  ('grant_tabelas_service_role', '0214', 'privilegio', 'service_role:tabelas', 'select,insert,update,delete', null,
   'Tabela de public sem acesso para service_role: o que usa a chave de serviço (rotinas administrativas, API) leva "permission denied".',
   'bloqueante', 911),
  ('grant_views_authenticated', '0214', 'privilegio', 'authenticated:views', 'select', null,
   'View de public sem SELECT para authenticated: a tela que a lê (sonda e painéis de instalação) leva "permission denied".',
   'bloqueante', 912),
  ('grant_views_service_role', '0214', 'privilegio', 'service_role:views', 'select', null,
   'View de public sem SELECT para service_role.',
   'importante', 913),
  ('grant_sequences_authenticated', '0214', 'privilegio', 'authenticated:sequences', 'usage', null,
   'Sequence de public sem USAGE para authenticated: o INSERT do portal numa tabela que a usa como default morre com "permission denied for sequence".',
   'bloqueante', 914),
  ('grant_sequences_service_role', '0214', 'privilegio', 'service_role:sequences', 'usage', null,
   'Sequence de public sem USAGE para service_role.',
   'importante', 915)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0214', revisado_em = current_date,
       observacao = 'A 0214 concede explicitamente (authenticated e service_role) o acesso às tabelas, views e sequences de public, preservando os revokes intencionais, e acrescenta à sonda o tipo privilegio (6 requisitos). No-op em produção: os grants já existem; sem tabela nova nem backfill.'
 where id = true;
