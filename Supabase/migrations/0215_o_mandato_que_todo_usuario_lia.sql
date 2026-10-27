-- =============================================================================
-- 0215 — O MANDATO QUE TODO USUÁRIO LIA: a pertinência (membro + administrador) que a restrição por mandato exige
-- (Cria duas tabelas, cinco funções de negócio, um gatilho e um backfill; NÃO toca policy de tabela existente —
--  isso é a 0216. Reemite fn_instalacao_conferir com um ramo novo, `execucao`.)
--
-- O DEFEITO. Decisão do dono D7 (Espec. 11 §7.1) e fase F2E etapa 1: "o mandato só é visto por quem trabalha nele".
-- Hoje não é: 49 tabelas, 65 policies, 53 delas `using (true)` — a `0003` deixou um TODO de membership que nunca
-- veio, e todo usuário logado lê todo mandato (medido em 27/10/2026 no banco montado pelo run.sh na 0214). Nenhuma
-- das 233 funções `fn_*` executáveis pelo authenticated é SECURITY DEFINER: todas rodam como o chamador, então a
-- RLS valerá DENTRO delas assim que as policies mudarem. Esta migration é só a PERTINÊNCIA — de quem é membro de
-- quê —, sem a qual a 0216 não tem o que perguntar.
--
-- O PAPEL VOLTA. A `0110` removeu `usuario_papel` e `fn_papel` a pedido do dono, porque a tabela não tinha UM leitor
-- e "schema que guarda o que não usa ensina quem lê a não confiar no que vê"; o próprio cabeçalho dela dizia que,
-- "se o controle por papel voltar, ele volta com a regra que o justifica". É este o caso: `administrador` tem leitor
-- desde o primeiro dia (fn_eh_admin, que toda policy da 0216 chamará) e a regra que o justifica é a D7.
--
-- DECISÕES DO DONO DE 27/10/2026 QUE VIRAM REQUISITO.
--   1. Modelo MEMBRO + ADMINISTRADOR: o analista vê os mandatos em que é membro; o administrador vê todos e atribui
--      membros (administrador é membro de tudo: fn_eh_membro devolve true para ele, sem linha em caso_membro).
--   2. TRANSIÇÃO: todo usuário atual vira membro de todo caso atual, na própria migration (por = migracao:0215).
--      Ninguém perde acesso no dia. EFEITO: a restrição só passa a restringir os mandatos criados DEPOIS, até o
--      administrador retirar gente de mandato antigo (fn_membro_remover). Quantas linhas isto cria em PRODUÇÃO é
--      usuários x casos de lá e NÃO foi medido por esta sessão (sem acesso); no banco de teste a conta é conferida
--      pelo teste (passo 1). Conferir depois de aplicar: select count(*) from caso_membro where por = 'migracao:0215'.
--
-- O QUE ENTRA.
--   * administrador(usuario_id, desde, por) e caso_membro(caso_id, usuario_id, desde, por), FKs para auth.users e
--     caso com ON DELETE CASCADE. RLS: o usuário lê as PRÓPRIAS linhas de caso_membro; o administrador lê e escreve
--     tudo; `administrador` só o administrador lê. Escrita pelas funções, que gravam evento_auditoria.
--   * fn_eh_admin() e fn_eh_membro(caso): STABLE, SECURITY DEFINER, search_path = public, pg_temp, sobre auth.uid().
--     São as que RESPONDEM e precisam ler as tabelas sem recursão de RLS (a policy de caso_membro pergunta se o
--     usuário é administrador). auth.uid() nulo (service_role, superusuário, sessão sem jwt) => false: quem bypassa a
--     RLS não precisa delas, e quem não tem identidade não é membro de nada.
--   * fn_membro_adicionar / fn_membro_remover (só administrador; 42501 com mensagem clara; evento de auditoria só
--     quando algo mudou) e fn_administrador_definir(email, ativo): SEM EXECUTE para authenticated e anon (revoke),
--     só service_role/postgres. É como o dono se torna o primeiro administrador, uma vez, no SQL Editor:
--         select fn_administrador_definir('<e-mail>', true);
--     NINGUÉM é administrador depois desta migration — o dono tem de rodar isso; até lá só quem é membro vê.
--   * Gatilho AFTER INSERT em caso: se auth.uid() não é nulo, o criador vira membro. EFEITO (regra 1): caso criado
--     pelo n8n (service_role, uid nulo) NASCE SEM MEMBRO e só o administrador o vê até alguém ser atribuído. O
--     intake normal do portal manda ao n8n, que cria o caso: a pertinência de quem subiu o arquivo é a FATIA DE
--     PORTAL, não esta. Até ela, depois que a 0216 ligar, mandato novo de intake some do analista que o criou.
--   * fn_caso_membro_backfill_0215(): a transição isolada numa função (idempotente, devolve as linhas novas) para o
--     teste chamá-la sobre usuários e casos montados antes. Só postgres/service_role: rodá-la de novo depois da
--     transição daria a todo usuário todo caso.
--   * Sonda: 21 requisitos (2 tabelas, 7 funções, 1 gatilho, 4 policies, 7 de execução) e o tipo NOVO `execucao`
--     (EXECUTE de função por papel, via has_function_privilege, que enxerga o PUBLIC). Sem ele, o revoke esquecido
--     de fn_administrador_definir seria invisível à sonda: a função existe, o corpo está certo e qualquer usuário
--     logado se promove administrador. `instalacao_cobertura` vai a 0215.
--
-- DECISÕES QUE O PEDIDO NÃO ESPECIFICAVA.
--   a. fn_trg_caso_criador_membro é a TERCEIRA função SECURITY DEFINER e a única que escreve: o authenticated não
--      tem (nem deve ter) policy "posso me inserir em qualquer caso", e sem ela o gatilho do criador morreria em
--      42501. Ela só insere auth.uid() no caso que acabou de nascer e só se o usuário existe em auth.users (jwt de
--      usuário apagado não derruba a criação do caso pela FK).
--   b. Nem o administrador executa fn_administrador_definir: promover administrador é de quem tem o banco.
--   c. authenticated tem INSERT/DELETE em caso_membro (só passam pela policy do administrador). Escrita direta
--      de um administrador, sem a função, NÃO deixa evento: o rastro é das funções.
--   d. O `run.sh` ganhou o schema `auth` mínimo (auth.users com id e email; auth.uid()) — o replay local nunca o
--      teve porque nenhuma migration anterior o usava.
--
-- O QUE FICA PARA O DONO, À MÃO NO SUPABASE: aplicar esta migration (Supabase/README.md), rodar
-- fn_administrador_definir com o próprio e-mail, e conferir fn_instalacao_conferir() onde migration = '0215'.
-- Migration escrita não é migration aplicada: quem responde é a sonda, contra o banco em que se está conectado.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2), medida em 27/10/2026 sobre
-- Supabase/test/caso_membro.test.sql, cópia do teste com o assert em `raise notice` (volta a `raise exception`
-- no arquivo commitado) sobre cópias do banco montado, UMA correção desligada por vez. Sem desligar nada: 0 dos 55
-- asserts reprovam e os 55 aparecem no log. Com a correção desligada, reprovam:
--     fn_eh_membro devolvendo true sempre ................................ 6 dos 55 asserts
--     fn_eh_admin devolvendo true sempre ................................. 11 dos 55 asserts
--     sem o gatilho trg_caso_criador_membro ............................... 9 dos 55 asserts
--     gatilho que torna TODOS os usuários membros do caso novo ............ 13 dos 55 asserts
--     transição (backfill) que não insere nada ............................ 3 dos 55 asserts
--     fn_membro_adicionar sem a guarda de administrador ................... 2 dos 55 asserts
--     fn_administrador_definir com EXECUTE para authenticated ............. 1 dos 55 asserts
--     fn_caso_membro_backfill_0215 com EXECUTE para authenticated ......... 2 dos 55 asserts
--     policy caso_membro_select com using (true) .......................... 1 dos 55 asserts
--     policy caso_membro_insert com check (true) .......................... 4 dos 55 asserts
--     policy administrador_select com using (true) ........................ 1 dos 55 asserts
--     catálogo sem os requisitos de execução (delete) ..................... 2 dos 55 asserts
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. AS DUAS TABELAS
-- -----------------------------------------------------------------------------
create table administrador (
  usuario_id uuid primary key references auth.users(id) on delete cascade,
  desde      timestamptz not null default now(),
  por        text not null
);
comment on table administrador is
  'Quem vê TODOS os mandatos e atribui membros (0215). Escrita só por fn_administrador_definir, que o authenticated não executa: o primeiro administrador nasce por SQL do dono. Vazia = ninguém é administrador (nada o promove sozinho).';

create table caso_membro (
  caso_id    uuid not null references caso(id) on delete cascade,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  desde      timestamptz not null default now(),
  por        text not null,
  primary key (caso_id, usuario_id)
);
create index idx_caso_membro_usuario on caso_membro(usuario_id);
comment on table caso_membro is
  'Quem trabalha no mandato (0215, decisão D7). `por` diz de onde veio a linha: usuario:<uuid> (administrador atribuiu), criador (gatilho de caso) ou migracao:0215 (a transição, todo usuário x todo caso).';

-- -----------------------------------------------------------------------------
-- 2. AS DUAS FUNÇÕES DE PERTINÊNCIA — as únicas SECURITY DEFINER que RESPONDEM, porque a policy de caso_membro
--    pergunta "sou membro?" e ler caso_membro como o chamador reentraria na própria policy (recursão de RLS).
--    auth.uid() nulo (service_role, superusuário, sessão sem jwt) => false: quem bypassa a RLS não precisa delas e
--    quem não tem identidade não é membro de nada. Administrador é membro de TUDO, inclusive de caso que não existe.
-- -----------------------------------------------------------------------------
create or replace function fn_eh_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.administrador where usuario_id = auth.uid());
$$;
comment on function fn_eh_admin() is
  'O usuário do jwt (auth.uid()) é administrador? SECURITY DEFINER para ler administrador sem recursão de RLS. auth.uid() nulo => false. 0215.';

create or replace function fn_eh_membro(p_caso uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.administrador where usuario_id = auth.uid())
      or exists (select 1 from public.caso_membro
                  where caso_id = p_caso and usuario_id = auth.uid());
$$;
comment on function fn_eh_membro(uuid) is
  'O usuário do jwt (auth.uid()) trabalha neste mandato? Administrador é membro de todos. SECURITY DEFINER para ler caso_membro sem recursão de RLS. auth.uid() nulo => false. 0215.';

-- -----------------------------------------------------------------------------
-- 3. RLS: o usuário lê as PRÓPRIAS linhas; o administrador lê e escreve tudo; administrador só o administrador lê.
--    Sem policy de update: a linha de pertinência não tem coluna que se edite (entra ou sai).
-- -----------------------------------------------------------------------------
alter table administrador enable row level security;
alter table caso_membro   enable row level security;

create policy administrador_select on administrador
  for select to authenticated using (fn_eh_admin());

create policy caso_membro_select on caso_membro
  for select to authenticated using (usuario_id = auth.uid() or fn_eh_admin());
create policy caso_membro_insert on caso_membro
  for insert to authenticated with check (fn_eh_admin());
create policy caso_membro_delete on caso_membro
  for delete to authenticated using (fn_eh_admin());

-- -----------------------------------------------------------------------------
-- 4. A ESCRITA: funções com o rastro em evento_auditoria. SECURITY INVOKER (o padrão): a RLS vale dentro delas.
-- -----------------------------------------------------------------------------
create or replace function fn_membro_adicionar(p_caso uuid, p_usuario uuid)
returns boolean
language plpgsql
as $$
declare
  v_n int;
begin
  if not fn_eh_admin() then
    raise exception 'fn_membro_adicionar: só o administrador atribui membros a um mandato' using errcode = '42501';
  end if;
  if p_caso is null or p_usuario is null then
    raise exception 'fn_membro_adicionar: caso e usuário são obrigatórios' using errcode = '22004';
  end if;
  insert into caso_membro (caso_id, usuario_id, por)
    values (p_caso, p_usuario, 'usuario:' || auth.uid())
    on conflict do nothing;
  get diagnostics v_n = row_count;
  if v_n > 0 then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('usuario:' || auth.uid(), 'membro_adicionado', 'caso:' || p_caso,
              jsonb_build_object('usuario_id', p_usuario));
  end if;
  return v_n > 0;
end;
$$;
comment on function fn_membro_adicionar(uuid, uuid) is
  'Só administrador. Torna o usuário membro do mandato; devolve false se já era (e então não grava evento). Caso ou usuário inexistente: 23503 da FK. 0215.';

create or replace function fn_membro_remover(p_caso uuid, p_usuario uuid)
returns boolean
language plpgsql
as $$
declare
  v_n int;
begin
  if not fn_eh_admin() then
    raise exception 'fn_membro_remover: só o administrador retira membros de um mandato' using errcode = '42501';
  end if;
  delete from caso_membro where caso_id = p_caso and usuario_id = p_usuario;
  get diagnostics v_n = row_count;
  if v_n > 0 then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('usuario:' || auth.uid(), 'membro_removido', 'caso:' || p_caso,
              jsonb_build_object('usuario_id', p_usuario));
  end if;
  return v_n > 0;
end;
$$;
comment on function fn_membro_remover(uuid, uuid) is
  'Só administrador. Retira o usuário do mandato; devolve false se não era membro (e então não grava evento). 0215.';

-- O primeiro administrador. NÃO executável pelo authenticated (revoke abaixo): o dono roda no SQL Editor
-- (postgres) ou a chave de serviço chama. Quem for administrador também NÃO a executa: promover administrador é
-- decisão de quem tem o banco, não de quem tem a tela.
create or replace function fn_administrador_definir(p_email text, p_ativo boolean)
returns boolean
language plpgsql
as $$
declare
  v_id uuid;
  v_n  int;
begin
  select id into v_id from auth.users where lower(email) = lower(p_email);
  if v_id is null then
    raise exception 'fn_administrador_definir: nenhum usuário com o e-mail %', p_email using errcode = 'P0002';
  end if;
  if p_ativo then
    insert into administrador (usuario_id, por) values (v_id, 'sql:' || current_user) on conflict do nothing;
  else
    delete from administrador where usuario_id = v_id;
  end if;
  get diagnostics v_n = row_count;
  if v_n > 0 then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sql:' || current_user,
              case when p_ativo then 'administrador_definido' else 'administrador_removido' end,
              'usuario:' || v_id, jsonb_build_object('ativo', p_ativo));
  end if;
  return v_n > 0;
end;
$$;
comment on function fn_administrador_definir(text, boolean) is
  'Torna (p_ativo) ou deixa de tornar o usuário de auth.users com este e-mail administrador. Devolve false se nada mudou. Só postgres/service_role: o authenticated NÃO a executa (a sonda cobra isso, tipo=execucao). 0215.';

-- -----------------------------------------------------------------------------
-- 5. O CRIADOR VIRA MEMBRO. Gatilho AFTER INSERT em caso. SECURITY DEFINER de propósito (a terceira da fatia, e a
--    única que ESCREVE): o authenticated não tem policy de insert em caso_membro para si, e dar uma ("posso me
--    inserir em qualquer caso") deixaria qualquer usuário entrar em qualquer mandato cujo uuid conheça. A função
--    só insere auth.uid() no caso que acabou de nascer. O `select ... from auth.users` evita que um jwt cujo
--    usuário não existe mais derrube a criação do caso pela FK.
--    EFEITO (regra 1): caso criado com auth.uid() nulo — o n8n, como service_role — NASCE SEM MEMBRO e só o
--    administrador o vê até alguém ser atribuído. A pertinência de quem sobe o arquivo pelo portal é da fatia de
--    portal (o intake manda ao n8n, que cria o caso): até lá, mandato novo de intake some do analista que o criou.
-- -----------------------------------------------------------------------------
create or replace function fn_trg_caso_criador_membro()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is not null then
    insert into public.caso_membro (caso_id, usuario_id, por)
      select new.id, u.id, 'criador' from auth.users u where u.id = auth.uid()
      on conflict do nothing;
  end if;
  return null;
end;
$$;
comment on function fn_trg_caso_criador_membro() is
  'Gatilho de caso (AFTER INSERT): o usuário do jwt que cria o mandato vira membro dele. auth.uid() nulo (n8n/service_role) => nasce sem membro. SECURITY DEFINER pelo motivo no cabeçalho da 0215.';

create trigger trg_caso_criador_membro
  after insert on caso
  for each row execute function fn_trg_caso_criador_membro();

-- -----------------------------------------------------------------------------
-- 6. A TRANSIÇÃO: todo usuário x todo caso. Função própria (e não um insert solto) para o teste a chamar sobre
--    usuários e casos montados antes, do jeito que a migration a chama abaixo. Idempotente; devolve quantas linhas
--    NOVAS. Restrita a postgres/service_role: chamada de novo, depois da transição, daria a todo usuário todo caso.
-- -----------------------------------------------------------------------------
create or replace function fn_caso_membro_backfill_0215()
returns bigint
language plpgsql
as $$
declare
  v_n bigint;
begin
  insert into caso_membro (caso_id, usuario_id, por)
    select c.id, u.id, 'migracao:0215' from caso c cross join auth.users u
    on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
comment on function fn_caso_membro_backfill_0215() is
  'A transição da 0215: todo usuário de auth.users vira membro de todo caso existente (por = migracao:0215). Idempotente. Só postgres/service_role — chamá-la de novo concede tudo a todos.';

-- -----------------------------------------------------------------------------
-- 7. GRANTs (convenção da 0214) e REVOKEs. Tabela: authenticated lê (e o administrador escreve em caso_membro, pela
--    policy); service_role tem as quatro operações. Função: o Postgres dá EXECUTE a PUBLIC por default, então o
--    revoke vem primeiro e o grant depois.
-- -----------------------------------------------------------------------------
grant select                 on administrador to authenticated;
grant select, insert, delete on caso_membro   to authenticated;
grant select, insert, update, delete on administrador, caso_membro to service_role;

revoke execute on function fn_eh_admin(), fn_eh_membro(uuid), fn_membro_adicionar(uuid, uuid),
  fn_membro_remover(uuid, uuid), fn_administrador_definir(text, boolean), fn_trg_caso_criador_membro(),
  fn_caso_membro_backfill_0215() from public, anon, authenticated;
grant execute on function fn_eh_admin(), fn_eh_membro(uuid), fn_membro_adicionar(uuid, uuid),
  fn_membro_remover(uuid, uuid) to authenticated;
grant execute on function fn_eh_admin(), fn_eh_membro(uuid), fn_membro_adicionar(uuid, uuid),
  fn_membro_remover(uuid, uuid), fn_administrador_definir(text, boolean), fn_caso_membro_backfill_0215()
  to service_role;

-- -----------------------------------------------------------------------------
-- 8. O BACKFILL
-- -----------------------------------------------------------------------------
select fn_caso_membro_backfill_0215();

-- -----------------------------------------------------------------------------
-- 9. A SONDA: o tipo `execucao` (acima) e os requisitos da 0215. A função é a da 0214 INTEIRA (extraída do próprio
--    arquivo, não replace de texto — nunca-corrigir-funcao-por-replace) com UM ramo novo.
-- -----------------------------------------------------------------------------
alter table instalacao_requisito drop constraint if exists instalacao_requisito_tipo_check;
alter table instalacao_requisito add constraint instalacao_requisito_tipo_check
  check (tipo in ('tabela', 'coluna', 'funcao', 'seed', 'comportamento', 'corpo', 'gatilho', 'policy', 'privilegio', 'execucao'));

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

    elsif r.tipo = 'execucao' then
      -- 0215: EXECUTE de função para um papel. `objeto` = 'papel:nome_da_funcao' (sem argumentos: o nome tem de ser
      -- único) e `marcador` = 'sim' (o papel TEM de executar) ou 'nao' (NÃO pode). O 'nao' existe por
      -- fn_administrador_definir: função em public nasce executável por PUBLIC no Postgres, e um revoke esquecido
      -- deixa qualquer usuário logado se promover administrador — nenhum outro tipo vê isso, porque a função
      -- existe e o corpo está certo. `has_function_privilege` enxerga a concessão a PUBLIC, que é a que importa.
      v_role := split_part(r.objeto, ':', 1);
      if r.marcador not in ('sim', 'nao') then
        v_ok  := false;
        v_det := 'requisito mal declarado: marcador tem de ser sim ou nao';
      elsif not exists (select 1 from pg_roles where rolname = v_role) then
        v_ok  := false;
        v_det := format('o papel %s nem existe', v_role);
      else
        begin
          v_proc := to_regproc('public.' || split_part(r.objeto, ':', 2));
        exception when others then
          v_proc := null;
          v_det  := 'mais de uma assinatura com este nome — o requisito precisa de um nome único';
        end;
        if v_proc is null then
          v_ok  := false;
          v_det := coalesce(v_det, 'a função nem existe');
        else
          v_ok  := has_function_privilege(v_role, v_proc::oid, 'execute') = (r.marcador = 'sim');
          v_det := case when v_ok then format('%s %s executa', v_role, case when r.marcador = 'sim' then 'pode' else 'NÃO pode' end)
                        when r.marcador = 'sim' then format('%s NÃO executa a função (o portal leva "permission denied")', v_role)
                        else format('%s EXECUTA a função e não podia (revoke esquecido)', v_role) end;
        end if;
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
  'Confere cada requisito de instalacao_requisito contra o catálogo do banco. Sobrevive ao objeto ausente (to_regclass/to_regproc devolvem NULL em vez de erro): a sonda não pode falhar por causa do que ela existe para medir. Desde a 0147 confere também o CORPO da função (tipo=corpo), que é o único jeito de distinguir uma correção aplicada de uma função homônima com o corpo velho. Desde a 0189 confere também GATILHO (tipo=gatilho): existência na tabela E tgenabled em (''O'',''A'') — a função do gatilho sobrevive a drop trigger/disable trigger e por isso NUNCA prova, sozinha, que a guarda está ligada. Desde a 0210 confere também POLICY (tipo=policy, objeto tabela.nome_da_policy): existência em pg_policy. Desde a 0214 confere PRIVILÉGIO (tipo=privilegio, objeto papel:classe, marcador = privilégios): toda tabela/view/sequence de public sem o mínimo para authenticated e service_role é buraco — o Supabase deixou de conceder por default privilege em 30/10/2026. Desde a 0215 confere também EXECUÇÃO de função (tipo=execucao, objeto papel:funcao, marcador sim|nao): has_function_privilege, que enxerga o PUBLIC — é o que cobra o revoke de fn_administrador_definir.';


insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('tabela_administrador', '0215', 'tabela', 'administrador', null, null,
   'Sem a tabela de administradores ninguém vê todos os mandatos nem atribui membros: quando a restrição por mandato (0216) ligar, o dono fica sem como enxergar o que os outros criaram.',
   'bloqueante', 920),
  ('tabela_caso_membro', '0215', 'tabela', 'caso_membro', null, null,
   'Sem caso_membro não há quem trabalhe em mandato nenhum: a restrição por mandato (0216) esconderia todos os casos de todos os analistas.',
   'bloqueante', 921),
  ('fn_eh_admin', '0215', 'funcao', 'fn_eh_admin', null, null,
   'As policies por mandato perguntam "é administrador?" por esta função; sem ela a policy erra e o caso some para todo mundo.',
   'bloqueante', 922),
  ('fn_eh_membro', '0215', 'funcao', 'fn_eh_membro', null, null,
   'As policies por mandato perguntam "trabalha neste mandato?" por esta função; sem ela a policy erra e o caso some para todo mundo.',
   'bloqueante', 923),
  ('fn_membro_adicionar', '0215', 'funcao', 'fn_membro_adicionar', null, null,
   'Sem ela o administrador não atribui ninguém a um mandato (e a tela de membros não tem o que chamar).',
   'importante', 924),
  ('fn_membro_remover', '0215', 'funcao', 'fn_membro_remover', null, null,
   'Sem ela o administrador não retira ninguém de um mandato.',
   'importante', 925),
  ('fn_administrador_definir', '0215', 'funcao', 'fn_administrador_definir', null, null,
   'Sem ela o dono não consegue se tornar o primeiro administrador sem escrever SQL à mão na tabela.',
   'importante', 926),
  ('fn_caso_membro_backfill_0215', '0215', 'funcao', 'fn_caso_membro_backfill_0215', null, null,
   'A transição (todo usuário vira membro de todo caso) não pôde ser reexecutada nem testada.',
   'informativo', 927),
  ('fn_trg_caso_criador_membro', '0215', 'funcao', 'fn_trg_caso_criador_membro', null, null,
   'Sem a função do gatilho, o criador de um mandato novo não vira membro e não o vê depois que a restrição por mandato ligar.',
   'bloqueante', 928),
  ('gatilho_caso_criador_membro', '0215', 'gatilho', 'caso.trg_caso_criador_membro', null, null,
   'Sem o gatilho (ou com ele desabilitado) o analista que cria um mandato pelo portal não é membro dele e o mandato some da sua tela, calado, quando a restrição por mandato ligar.',
   'bloqueante', 929),
  ('policy_administrador_select', '0215', 'policy', 'administrador.administrador_select', null, null,
   'RLS ligada sem a policy: o administrador não lê nem a própria linha (zero linhas sem erro).',
   'bloqueante', 930),
  ('policy_caso_membro_select', '0215', 'policy', 'caso_membro.caso_membro_select', null, null,
   'RLS ligada sem a policy: o usuário não lê as próprias pertinências (zero linhas sem erro, parecido com "sem mandato nenhum").',
   'bloqueante', 931),
  ('policy_caso_membro_insert', '0215', 'policy', 'caso_membro.caso_membro_insert', null, null,
   'Sem a policy o administrador não consegue atribuir membro pelo portal (42501 ao chamar fn_membro_adicionar).',
   'importante', 932),
  ('policy_caso_membro_delete', '0215', 'policy', 'caso_membro.caso_membro_delete', null, null,
   'Sem a policy o administrador não consegue retirar membro pelo portal.',
   'importante', 933),
  ('exec_definir_admin_authenticated', '0215', 'execucao', 'authenticated:fn_administrador_definir', 'nao', null,
   'authenticated executa fn_administrador_definir: qualquer usuário logado se promove administrador e passa a ver todos os mandatos. Revoke esquecido (o Postgres dá EXECUTE a PUBLIC por default).',
   'bloqueante', 934),
  ('exec_definir_admin_anon', '0215', 'execucao', 'anon:fn_administrador_definir', 'nao', null,
   'anon executa fn_administrador_definir: a chave pública promove administrador. Revoke de PUBLIC/anon esquecido.',
   'bloqueante', 935),
  ('exec_backfill_authenticated', '0215', 'execucao', 'authenticated:fn_caso_membro_backfill_0215', 'nao', null,
   'authenticated executa a transição da 0215: qualquer usuário logado entra em todos os mandatos.',
   'bloqueante', 936),
  ('exec_eh_membro_authenticated', '0215', 'execucao', 'authenticated:fn_eh_membro', 'sim', null,
   'authenticated não executa fn_eh_membro: as policies por mandato (0216) levam "permission denied" e a tela quebra.',
   'bloqueante', 937),
  ('exec_eh_admin_authenticated', '0215', 'execucao', 'authenticated:fn_eh_admin', 'sim', null,
   'authenticated não executa fn_eh_admin: as policies por mandato (0216) levam "permission denied" e a tela quebra.',
   'bloqueante', 938),
  ('exec_membro_adicionar_authenticated', '0215', 'execucao', 'authenticated:fn_membro_adicionar', 'sim', null,
   'authenticated não executa fn_membro_adicionar: o administrador leva "permission denied" ao atribuir membro.',
   'importante', 939),
  ('exec_membro_remover_authenticated', '0215', 'execucao', 'authenticated:fn_membro_remover', 'sim', null,
   'authenticated não executa fn_membro_remover: o administrador leva "permission denied" ao retirar membro.',
   'importante', 940)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0215', revisado_em = current_date,
       observacao = 'A 0215 cria administrador e caso_membro (RLS, grants, funções de pertinência e de escrita, gatilho do criador, backfill todo usuário x todo caso) e acrescenta à sonda o tipo execucao (21 requisitos ao todo). Não toca policy de tabela existente (0216).'
 where id = true;

