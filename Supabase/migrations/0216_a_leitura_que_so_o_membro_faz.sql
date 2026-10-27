-- =============================================================================
-- 0216 — A LEITURA QUE SÓ O MEMBRO FAZ: a RLS por mandato em toda tabela de dado do cliente
-- (Troca 47 policies `using (true)` por policies que perguntam a pertinência da 0215, restringe o bucket `documentos`,
--  dá `caso_id` ao rastro de auditoria e reemite fn_upsert_caso e a sonda.)
--
-- O DEFEITO. Decisão D7 (Espec. 11 §7.1): "o mandato só é visto por quem trabalha nele". Medido em 27/10/2026 no banco
-- montado pelo run.sh na 0215: 49 tabelas, 65 policies de public, as de dado do cliente `using (true)` — todo usuário
-- logado lia e gravava todo mandato —, e storage.objects com `documentos_authenticated_all` (o bucket inteiro: o
-- balanço e o contrato social de qualquer mandato). A 0215 criou a pertinência (caso_membro, administrador,
-- fn_eh_membro) e NÃO tocou policy nenhuma; esta é a que liga.
--
-- A CAUSA do defeito de partida: a `0003` deixou um TODO de membership que nunca veio. Dois efeitos que a RLS cria
-- e que esta migration trata (porque, sem tratar, ela introduz defeito novo):
--   1. fn_upsert_caso procura o caso por NOME. Com RLS em `caso`, quem não é membro não enxerga o mandato existente e
--      CRIAVA UM DUPLICADO com o mesmo nome. Chamadores (grep em 27/10/2026): o nó "Upsert Caso" do n8n
--      (service_role, auth.uid() nulo), portal/src/lib/envio-oficial.ts#obterCasoId (authenticated) e ~70 chamadas em
--      Supabase/test (superusuário). Todos passam pela MESMA função: corrigida nela, reemitida INTEIRA (memória
--      nunca-corrigir-funcao-por-replace).
--   2. `insert ... returning id` em `caso` checa a policy de SELECT na hora do insert, ANTES do gatilho AFTER INSERT da
--      0215 dar a pertinência ao criador: com RLS de SELECT o authenticated levaria 42501 ao criar o próprio mandato.
--      Medido ao desligar a correção (tabela abaixo, "fn_upsert_caso com RETURNING"): o teste morre na montagem. O id é
--      gerado antes e o insert não tem RETURNING.
--
-- O QUE ENTRA.
--   * fn_meus_casos() (SECURITY DEFINER, STABLE): os ids dos mandatos do usuário (todos, se administrador). Toda policy
--     de tabela com caso_id pergunta `caso_id in (select fn_meus_casos())`.
--   * Tabela INDIRETA pergunta ao PAI: `documento_versao_id in (select id from documento_versao)` etc. (documento_versao
--     → documento; campo_extraido e documento_fato → documento_versao; campo_classe_* → campo_extraido;
--     arquivo_oficial_registro/_lancamento_mes → arquivo_oficial; golden_documento/_campo/_rotulo → documento, que eles
--     têm por documento_id). A RLS do pai se compõe até o caso. Caminhos CONFERIDOS em pg_constraint no banco montado;
--     `arquivo_oficial` e `documento` têm `caso_id` direto.
--   * `caso`: SELECT/UPDATE/DELETE só membro; INSERT segue aberto (é como o portal cria o mandato; o gatilho da 0215
--     torna o criador membro).
--   * Mesmo CONJUNTO de operações de antes: onde a policy era `for all` fica UMA `for all` (`<tabela>_por_mandato`;
--     o que o privilégio revoga, como delete em arquivo_oficial (0210), continua revogado); onde era só
--     select/insert/update (caso_pergunta, controlador, controlador_vinculo, entidade_controlador, perimetro,
--     campo_classe_*, golden_*) ficam as mesmas operações, com os mesmos NOMES — e a de reapontar de caso_pergunta
--     mantém a condição "mesma entidade, mesmo caso". O with check do UPDATE também exige o mandato: mover linha de X
--     para Y leva 42501.
--   * storage.objects: `documentos_por_mandato` — só a pasta do caso (fn_caso_da_chave(name) in fn_meus_casos()). NÃO
--     usa storage.foldername (o replay local não a tem) e o cast para uuid é seguro (uma chave de forma estranha dava
--     erro na policy de SELECT e derrubava a listagem do bucket inteiro).
--   * evento_auditoria.caso_id (`references caso on delete set null`, índice): preenchido por gatilho BEFORE INSERT que
--     deriva de entidade_ref pelo FK (fn_caso_da_referencia, SECURITY INVOKER: o não membro deriva nulo e não forja
--     evento no mandato alheio; o rastro dele entra, sem caso, e só o administrador o lê). Formas levantadas por grep
--     nas 222 inserções: caso:, documento:, documento_versao:, campo_extraido:, reconciliacao:, pendencia:,
--     entidade:, controlador:<uuid>. Sem caso por natureza: estagio:, golden_rodada:, usuario:, caso_nome:<nome>,
--     `campo_extraido` sem id (backfills 0203/0204), documento_versao:null. Backfill do histórico pela MESMA função.
--     Leitura: membro do caso_id; caso_id nulo, só administrador. Insert segue aberto, exceto com caso_id explícito
--     de mandato alheio.
--   * Sonda: 64 requisitos (policy por mandato de cada tabela, as funções, os EXECUTE, a coluna, o gatilho, o corpo de
--     fn_upsert_caso). O ramo `policy` ganhou o MARCADOR (a expressão da policy tem de conter fn_meus_casos ou o pai) e
--     aceita `schema.tabela.policy` — sem isso a policy `using (true)` de mesmo nome passaria por "presente" — e a
--     policy do bucket (storage.objects). `instalacao_cobertura` vai a 0216.
--   * A GUARDA (sinal positivo, regra 7): a migration RECUSA aplicar (55000) se `administrador` está vazia e existe
--     mandato real sem nenhum membro — os que o n8n cria nascem sem membro e SUMIRIAM para todos, sem erro. No replay
--     não trava: as migrations rodam sem mandato real (só as 2 fixtures da sonda, 0162 e 0164, que a guarda ignora
--     pelo nome). Dentro de begin/commit: a recusa deixa o banco como estava.
--
-- EFEITOS QUE O DONO PRECISA SABER (regra 1: o que some não some calado).
--   a. Mandato criado pelo n8n (intake do portal) NASCE SEM MEMBRO: só o administrador o vê até alguém ser atribuído
--      (fn_membro_adicionar) ou o portal chamar fn_upsert_caso antes do envio. É a FATIA DE PORTAL; até ela, o
--      analista que sobe um arquivo de mandato novo não o vê. Isto já estava na 0215; a 0216 é o que o torna real.
--   b. Evento sem caso (estagio:..., golden_rodada:..., mandato excluído) só o administrador lê: a tela /autonomia
--      (portal/src/app/autonomia/page.tsx) deixa de listar o histórico de mudança de dial para quem não é administrador.
--   c. `caso.nome` NÃO é único e fn_upsert_caso busca por `limit 1` sem `order by`: com nomes duplicados já existentes o
--      n8n (vê todos) pega um qualquer e o authenticated pega um dos DELE. Não se cria unique aqui (decisão do dono).
--   d. O Supabase novo (30/10/2026) não concede EXECUTE/GRANT por default: as 4 funções novas chamadas pelas policies
--      têm `grant execute ... to authenticated` explícito; as de gatilho e a guarda, não.
--   e. Os 12 testes que rodavam como authenticated SEM identidade dependiam do `using (true)`; passam a chamar
--      teste_como_admin_0216()/teste_fim_admin_0216() em par (Supabase/test/suporte_authenticated.sql).
--
-- AINDA ABERTO (de propósito, com o porquê). Catálogos e globais seguem legíveis ao authenticated: taxonomia_* (5),
-- premissa_catalogo, classe_contabil_catalogo, rubrica_classe, fato_tipo_catalogo, pergunta_catalogo, indice_macro_*
-- (3), instalacao_*, golden_rodada, golden_criterio, estagio_autonomia — não têm caso nem dado do cliente. ACHADO FORA
-- DE ESCOPO, não mexido: estagio_autonomia e premissa_catalogo têm policy `for all using (true)` para authenticated, ou
-- seja, qualquer usuário logado pode dar UPDATE direto no teto de autonomia sem passar por fn_mudar_dial; e
-- golden_rodada tem update livre. É decisão para outra fatia (o teto é doutrina e só deveria mudar por migration).
--
-- DESEMPENHO (medido em 27/10/2026, banco com 53.893 campo_extraido, um caso com 50.000 deles, usuário membro desse
-- caso, `explain analyze`, duas rodadas):
--     forma                                                        count(*)      por documento_versao_id
--     using (true) (antes)                                          7,0 ms        0,37 ms
--     fn_eh_membro por linha, subconsulta correlata ao pai          3.450 ms      4,3 ms      (REPROVADA: >1 s)
--     cadeia + `caso_id in (select fn_meus_casos())` correlato      254 ms        1,0 ms
--     `in (select id from pai)` encadeado + fn_meus_casos (ESTA)    12,1 ms       1,35 ms
--   A forma escolhida: administrador 10 ms; quem não é membro 3,6 ms; campo_classe_sugerida (3 níveis) 26 ms;
--   reconciliacao 1 ms; evento_auditoria 2,8 ms. O que mata é a chamada POR LINHA: `in (select fn_meus_casos())` vira um
--   hashed SubPlan executado UMA vez. fn_eh_membro continua existindo (é a pergunta de um caso só) e o teste afirma
--   que as duas concordam.
--
-- O QUE FICA PARA O DONO, À MÃO NO SUPABASE: (1) ANTES de aplicar, no SQL Editor:
--     select fn_administrador_definir('<seu e-mail>', true);
--   (a migration recusa sem isso se houver mandato real sem membro); (2) aplicar (Supabase/README.md); (3) conferir
--   `select chave, detalhe from fn_instalacao_conferir() where migration = '0216' and not presente;` — ZERO linhas;
--   (4) quantos mandatos reais ficaram sem membro: select count(*) from caso c where not exists (select 1 from
--   caso_membro m where m.caso_id = c.id); — o administrador os vê e os atribui. Migration escrita não é migration
--   aplicada: quem responde é a sonda, contra o banco em que se está conectado.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2), medida em 27/10/2026 sobre
-- Supabase/test/rls_por_mandato.test.sql, cópia do teste com o assert em `raise notice` (volta a `raise exception` no
-- arquivo commitado) sobre cópias do banco montado, UMA correção desligada por vez. Sem desligar nada: 0 dos 56 asserts
-- reprovam e os 54 aparecem no log. Com a correção desligada, reprovam (os marcados "aborta" morrem num erro de
-- execução antes de chegar aos asserts seguintes — o teste reprova do mesmo jeito):
--     policy documento (direta) com using (true) .......................... 12 dos 56 asserts (aborta no 17º)
--     policy campo_extraido (indireta, 2 níveis) com using (true) ......... 8 dos 56 asserts
--     policy documento_versao (indireta, pai da cadeia) com using (true) .. 8 dos 56 asserts
--     policy caso_select com using (true) ................................. 5 dos 56 asserts (aborta no 29º)
--     policy caso_update com using (true) ................................. 3 dos 56 asserts
--     policy caso_delete com using (true) ................................. 3 dos 56 asserts
--     policy evento_auditoria_read com using (true) ....................... 10 dos 56 asserts
--     policy evento_auditoria_read lendo também o evento sem caso ......... 7 dos 56 asserts
--     policy evento_auditoria_insert com check (true) ..................... 4 dos 56 asserts
--     policy golden_campo_read com using (true) ........................... 6 dos 56 asserts
--     policy golden_documento_read com using (true) ....................... 6 dos 56 asserts
--     policy caso_pergunta_read com using (true) .......................... 6 dos 56 asserts
--     storage.objects de volta ao bucket inteiro .......................... 7 dos 56 asserts
--     gatilho trg_evento_caso_id desabilitado ............................. 9 dos 56 asserts
--     fn_caso_da_referencia devolvendo nulo ............................... 8 dos 56 asserts
--     fn_meus_casos devolvendo todos os casos ............................. 3 dos 56 asserts (aborta no 15º)
--     fn_upsert_caso sem a guarda de não membro ........................... 4 dos 56 asserts
--     fn_upsert_caso com insert ... returning (sem gerar o id antes) ...... 0 dos 56 asserts (aborta no 3º: 42501 na montagem)
--     fn_0216_exige_administrador sem o raise ............................. 1 dos 56 asserts
--     sonda sem o marcador/storage (a função da 0215) ..................... 3 dos 56 asserts
--     tabela de cliente NOVA com policy using (true) e sem dados .......... 3 dos 56 asserts
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1. O SINAL POSITIVO (regra 7): recusa aplicar com `administrador` vazia e caso sem nenhum membro. A função existe
--    para o teste a chamar sobre um arranjo montado; a migration a chama logo abaixo. No replay (run.sh, e2e) as
--    migrations rodam sobre banco SEM mandato real — as fixtures dos livros entram depois; só ficam as duas fixtures
--    da sonda, excluídas da conta pelo nome —, então a contagem dá zero e nada trava.
--    O `begin`/`commit` desta migration faz a recusa deixar o banco como estava (psql -f sem ON_ERROR_STOP seguiria).
-- -----------------------------------------------------------------------------
create or replace function fn_0216_exige_administrador()
returns void
language plpgsql
as $$
declare
  v_orfaos bigint;
begin
  if exists (select 1 from administrador) then
    return;
  end if;
  -- Fora da conta ficam as fixtures da sonda (0162 e 0164: "fixture da instalação, não é mandato real"): nascem
  -- sem membro em TODO replay — medido em 27/10/2026, 2 casos no banco montado só pelas migrations — e a guarda
  -- travaria o run.sh e o Verificação/run.mts por causa deles.
  select count(*) into v_orfaos from caso c
   where c.nome not like '%fixture da instalação, não é mandato real%'
     and not exists (select 1 from caso_membro m where m.caso_id = c.id);
  if v_orfaos > 0 then
    raise exception '0216 recusada: % mandato(s) sem nenhum membro (criados pelo n8n, sem identidade) e ninguém é administrador — com a restrição por mandato ligada eles sumiriam para todos, sem erro. Rode ANTES, no SQL Editor: select fn_administrador_definir(''<seu e-mail>'', true);', v_orfaos
      using errcode = '55000';
  end if;
end;
$$;
comment on function fn_0216_exige_administrador() is
  'Guarda da 0216: levanta 55000 se administrador está vazia E existe caso sem membro. Só postgres/service_role. 0216.';
revoke execute on function fn_0216_exige_administrador() from public, anon, authenticated;
grant execute on function fn_0216_exige_administrador() to service_role;

select fn_0216_exige_administrador();

-- -----------------------------------------------------------------------------
-- 2. AS FUNÇÕES QUE AS POLICIES CHAMAM
-- -----------------------------------------------------------------------------
-- fn_meus_casos(): os ids dos mandatos do usuário do jwt (todos, se administrador). É o que a policy pergunta como
-- `caso_id in (select fn_meus_casos())`: um SubPlan hashed, executado UMA vez por comando, e não uma chamada por linha
-- (medido: ver cabeçalho). SECURITY DEFINER pelo mesmo motivo de fn_eh_membro (ler caso_membro/administrador sem
-- reentrar na RLS). auth.uid() nulo => nenhum caso. Tem de concordar com fn_eh_membro; o teste afirma a concordância.
create or replace function fn_meus_casos()
returns setof uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select c.id from public.caso c
   where exists (select 1 from public.administrador where usuario_id = auth.uid())
  union
  select m.caso_id from public.caso_membro m where m.usuario_id = auth.uid();
$$;
comment on function fn_meus_casos() is
  'Ids dos mandatos do usuário do jwt (todos, se administrador). Base de toda policy por mandato (caso_id in (select fn_meus_casos())). Concorda com fn_eh_membro. auth.uid() nulo => vazio. 0216.';

-- fn_caso_id_do_nome(): o id do caso com este nome INDEPENDENTE da RLS. Só existe para fn_upsert_caso distinguir "não
-- existe" de "existe e eu não o vejo". Devolve só o id (nome e id de mandato não são segredo que a RLS proteja: quem
-- decide o acesso é a pertinência, não o conhecimento do id).
create or replace function fn_caso_id_do_nome(p_nome text)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select id from public.caso where nome = p_nome limit 1;
$$;
comment on function fn_caso_id_do_nome(text) is
  'Id do caso com este nome, sem passar pela RLS (só devolve o id). Existe para fn_upsert_caso não criar duplicado quando o chamador não é membro. 0216.';

-- fn_caso_da_chave(): o caso de um objeto do bucket `documentos`. A chave é <caso_id>/<hash><ext> (N8N/lib/hash.mjs
-- #chaveDoOriginal). NÃO usa storage.foldername: o replay local (run.sh, Verificação) não tem essa função, e o cast
-- direto para uuid levantaria erro numa policy de SELECT se algum objeto tivesse outra forma de pasta — a listagem
-- inteira do bucket cairia. Forma estranha => nulo => ninguém vê o objeto (só o service_role).
create or replace function fn_caso_da_chave(p_name text)
returns uuid
language sql
immutable
as $$
  select case when p_name ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
              then substr(p_name, 1, 36)::uuid end;
$$;
comment on function fn_caso_da_chave(text) is
  'O caso_id da primeira pasta da chave de um objeto do bucket documentos (<caso_id>/<hash><ext>); nulo se a chave não tem essa forma. 0216.';

-- fn_caso_da_referencia(): o caso a que uma `entidade_ref` de evento_auditoria se refere, pelo FK. SECURITY INVOKER de
-- propósito: a RLS vale. Um usuário que NÃO é membro e grava um evento sobre documento:<uuid> alheio não enxerga o
-- documento, deriva nulo, e o evento vira "só administrador" em vez de entrar forjado no rastro do mandato alheio.
-- Formas que existem no código (levantadas por grep nas 222 inserções): caso:, documento:, documento_versao:,
-- reconciliacao:, pendencia:, entidade:, controlador:, campo_extraido:<uuid>; e SEM caso por natureza: estagio:,
-- golden_rodada:, usuario:, caso_nome:<nome>, `campo_extraido` sem id (backfills de 0203/0204), documento_versao:null.
create or replace function fn_caso_da_referencia(p_ref text)
returns uuid
language plpgsql
stable
as $$
declare
  v_tipo text := split_part(coalesce(p_ref, ''), ':', 1);
  v_txt  text := split_part(coalesce(p_ref, ''), ':', 2);
  v_id   uuid;
  v_caso uuid;
begin
  if v_txt !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  v_id := v_txt::uuid;
  if    v_tipo = 'caso'          then select id into v_caso from caso where id = v_id;
  elsif v_tipo = 'documento'     then select caso_id into v_caso from documento where id = v_id;
  elsif v_tipo = 'documento_versao' then
    select d.caso_id into v_caso from documento_versao dv join documento d on d.id = dv.documento_id where dv.id = v_id;
  elsif v_tipo = 'campo_extraido' then
    select d.caso_id into v_caso from campo_extraido c
      join documento_versao dv on dv.id = c.documento_versao_id
      join documento d on d.id = dv.documento_id where c.id = v_id;
  elsif v_tipo = 'reconciliacao' then select caso_id into v_caso from reconciliacao where id = v_id;
  elsif v_tipo = 'pendencia'     then select caso_id into v_caso from pendencia where id = v_id;
  elsif v_tipo = 'entidade'      then select caso_id into v_caso from entidade where id = v_id;
  elsif v_tipo = 'controlador'   then select caso_id into v_caso from controlador where id = v_id;
  end if;
  return v_caso;
end;
$$;
comment on function fn_caso_da_referencia(text) is
  'O caso de uma entidade_ref de evento_auditoria, pelo FK (nulo se a forma não tem caso). SECURITY INVOKER: a RLS vale e o não membro deriva nulo. 0216.';

create or replace function fn_trg_evento_caso_id()
returns trigger
language plpgsql
as $$
begin
  if new.caso_id is null then
    new.caso_id := fn_caso_da_referencia(new.entidade_ref);
  end if;
  return new;
end;
$$;
comment on function fn_trg_evento_caso_id() is
  'Gatilho BEFORE INSERT de evento_auditoria: preenche caso_id derivando de entidade_ref quando quem insere não o informou. 0216.';

-- -----------------------------------------------------------------------------
-- 3. evento_auditoria.caso_id: a coluna, o índice, o gatilho e o backfill do histórico pela MESMA função.
--    ON DELETE SET NULL: excluir o mandato (fn_excluir_caso) não apaga o rastro, que passa a ser só do administrador.
-- -----------------------------------------------------------------------------
alter table evento_auditoria add column caso_id uuid null references caso(id) on delete set null;
create index idx_evento_auditoria_caso on evento_auditoria(caso_id);
comment on column evento_auditoria.caso_id is
  'O mandato a que o evento pertence (0216), derivado de entidade_ref pelo gatilho. Nulo = sem mandato (estagio:, golden_rodada:, caso_nome:...) ou mandato excluído: só o administrador lê.';

create trigger trg_evento_caso_id
  before insert on evento_auditoria
  for each row execute function fn_trg_evento_caso_id();

update evento_auditoria set caso_id = fn_caso_da_referencia(entidade_ref) where caso_id is null;

-- -----------------------------------------------------------------------------
-- 4. fn_upsert_caso, REEMITIDA INTEIRA (a da 0207 + a guarda). Chamadores (grep em 27/10/2026): o nó "Upsert Caso" do
--    n8n (service_role, auth.uid() nulo: comportamento IDÊNTICO ao da 0207), portal/src/lib/envio-oficial.ts#obterCasoId
--    (authenticated, p_ator 'portal:navegador') e ~70 chamadas em Supabase/test/*.test.sql e fixtures (superusuário).
--    Dois efeitos da RLS que a guarda trata: (1) o não membro não enxergava o caso e CRIAVA UM DUPLICADO com o mesmo
--    nome — agora a busca visível falha, fn_caso_id_do_nome acha o existente e a função recusa com 42501; (2) `insert
--    ... returning` em caso com RLS de SELECT checa a policy ANTES do gatilho do criador (AFTER INSERT) dar a
--    pertinência: falharia com 42501. O id é gerado antes e não há RETURNING.
--    `caso.nome` NÃO é único (schema.sql) e a busca é `limit 1` sem `order by`: com nomes duplicados já existentes, o
--    n8n (service_role, vê todos) pega um qualquer e o authenticated pega um dos DELE. Não se cria unique aqui
--    (decisão do dono).
-- -----------------------------------------------------------------------------
create or replace function fn_upsert_caso(p_nome text, p_ator text default 'sistema:n8n')
returns uuid
language plpgsql
as $$
declare
  v_id uuid;
begin
  if p_ator not in ('sistema:n8n', 'portal:navegador') then
    raise exception 'fn_upsert_caso: ator % fora da lista (sistema:n8n, portal:navegador)', p_ator;
  end if;
  select id into v_id from caso where nome = p_nome limit 1;
  if v_id is null then
    if auth.uid() is not null and fn_caso_id_do_nome(p_nome) is not null then
      raise exception 'fn_upsert_caso: o mandato "%" existe e você não é membro; peça acesso ao administrador', p_nome
        using errcode = '42501';
    end if;
    v_id := gen_random_uuid();
    insert into caso (id, nome) values (v_id, p_nome);
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_ator, 'caso_criado', 'caso:'||v_id, jsonb_build_object('nome', p_nome));
  end if;
  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 5. AS POLICIES. Cada `drop` tem de achar a policy que existe (sem `if exists`): policy que a migration não
--    encontra é policy que ela não trocou. Tabelas que eram `for all using (true)` ficam com UMA policy `for all`
--    (mesmo conjunto de operações; o que o privilégio revoga — delete em arquivo_oficial, 0210 — continua revogado).
--    Tabelas append-only ou sem update (caso_pergunta, controlador, campo_classe_*, golden_*) mantêm as operações e os
--    nomes que tinham, só restritas ao membro. Tabela indireta pergunta ao PAI (`x_id in (select id from pai)`): a RLS
--    do pai se compõe até o caso, e o planner faz uma junção hashed (medido: ver cabeçalho) em vez de uma subconsulta
--    correlata por linha (3,4 s para 54 mil campos).
-- -----------------------------------------------------------------------------
drop policy arquivo_oficial_authenticated_all on arquivo_oficial;
create policy arquivo_oficial_por_mandato on arquivo_oficial for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy caso_apresentacao_campo_authenticated_all on caso_apresentacao_campo;
create policy caso_apresentacao_campo_por_mandato on caso_apresentacao_campo for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy caso_linha_premissa_authenticated_all on caso_linha_premissa;
create policy caso_linha_premissa_por_mandato on caso_linha_premissa for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy caso_modelagem_authenticated_all on caso_modelagem;
create policy caso_modelagem_por_mandato on caso_modelagem for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy caso_premissa_authenticated_all on caso_premissa;
create policy caso_premissa_por_mandato on caso_premissa for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy checklist_item_status_authenticated_all on checklist_item_status;
create policy checklist_item_status_por_mandato on checklist_item_status for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy decisao_authenticated_all on decisao;
create policy decisao_por_mandato on decisao for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy documento_authenticated_all on documento;
create policy documento_por_mandato on documento for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy entidade_authenticated_all on entidade;
create policy entidade_por_mandato on entidade for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy execucao_falha_authenticated_all on execucao_falha;
create policy execucao_falha_por_mandato on execucao_falha for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy lote_execucao_authenticated_all on lote_execucao;
create policy lote_execucao_por_mandato on lote_execucao for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy pendencia_authenticated_all on pendencia;
create policy pendencia_por_mandato on pendencia for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy periodo_authenticated_all on periodo;
create policy periodo_por_mandato on periodo for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy reconciliacao_authenticated_all on reconciliacao;
create policy reconciliacao_por_mandato on reconciliacao for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy documento_versao_authenticated_all on documento_versao;
create policy documento_versao_por_mandato on documento_versao for all to authenticated
  using (documento_id in (select id from documento))
  with check (documento_id in (select id from documento));

drop policy campo_extraido_authenticated_all on campo_extraido;
create policy campo_extraido_por_mandato on campo_extraido for all to authenticated
  using (documento_versao_id in (select id from documento_versao))
  with check (documento_versao_id in (select id from documento_versao));

drop policy documento_fato_authenticated_all on documento_fato;
create policy documento_fato_por_mandato on documento_fato for all to authenticated
  using (documento_versao_id in (select id from documento_versao))
  with check (documento_versao_id in (select id from documento_versao));

drop policy arquivo_oficial_registro_authenticated_all on arquivo_oficial_registro;
create policy arquivo_oficial_registro_por_mandato on arquivo_oficial_registro for all to authenticated
  using (arquivo_oficial_id in (select id from arquivo_oficial))
  with check (arquivo_oficial_id in (select id from arquivo_oficial));

drop policy arquivo_oficial_lancamento_mes_authenticated_all on arquivo_oficial_lancamento_mes;
create policy arquivo_oficial_lancamento_mes_por_mandato on arquivo_oficial_lancamento_mes for all to authenticated
  using (arquivo_oficial_id in (select id from arquivo_oficial))
  with check (arquivo_oficial_id in (select id from arquivo_oficial));

drop policy caso_pergunta_read on caso_pergunta;
create policy caso_pergunta_read on caso_pergunta for select to authenticated using (caso_id in (select fn_meus_casos()));

drop policy caso_pergunta_insert on caso_pergunta;
create policy caso_pergunta_insert on caso_pergunta for insert to authenticated with check (caso_id in (select fn_meus_casos()));

drop policy caso_pergunta_reapontar on caso_pergunta;
create policy caso_pergunta_reapontar on caso_pergunta for update to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos())
        and entidade_id is not null
        and exists (select 1 from entidade e where e.id = caso_pergunta.entidade_id and e.caso_id = caso_pergunta.caso_id));

drop policy controlador_read on controlador;
create policy controlador_read on controlador for select to authenticated using (caso_id in (select fn_meus_casos()));

drop policy controlador_insert on controlador;
create policy controlador_insert on controlador for insert to authenticated with check (caso_id in (select fn_meus_casos()));

drop policy controlador_vinculo_read on controlador_vinculo;
create policy controlador_vinculo_read on controlador_vinculo for select to authenticated using (caso_id in (select fn_meus_casos()));

drop policy controlador_vinculo_insert on controlador_vinculo;
create policy controlador_vinculo_insert on controlador_vinculo for insert to authenticated with check (caso_id in (select fn_meus_casos()));

drop policy controlador_vinculo_update on controlador_vinculo;
create policy controlador_vinculo_update on controlador_vinculo for update to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy entidade_controlador_read on entidade_controlador;
create policy entidade_controlador_read on entidade_controlador for select to authenticated using (caso_id in (select fn_meus_casos()));

drop policy entidade_controlador_insert on entidade_controlador;
create policy entidade_controlador_insert on entidade_controlador for insert to authenticated with check (caso_id in (select fn_meus_casos()));

drop policy entidade_controlador_update on entidade_controlador;
create policy entidade_controlador_update on entidade_controlador for update to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy perimetro_read on perimetro;
create policy perimetro_read on perimetro for select to authenticated using (caso_id in (select fn_meus_casos()));

drop policy perimetro_insert on perimetro;
create policy perimetro_insert on perimetro for insert to authenticated with check (caso_id in (select fn_meus_casos()));

drop policy perimetro_update on perimetro;
create policy perimetro_update on perimetro for update to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy campo_classe_override_read on campo_classe_override;
create policy campo_classe_override_read on campo_classe_override for select to authenticated using (campo_extraido_id in (select id from campo_extraido));

drop policy campo_classe_override_insert on campo_classe_override;
create policy campo_classe_override_insert on campo_classe_override for insert to authenticated with check (campo_extraido_id in (select id from campo_extraido));

drop policy campo_classe_sugerida_read on campo_classe_sugerida;
create policy campo_classe_sugerida_read on campo_classe_sugerida for select to authenticated using (campo_extraido_id in (select id from campo_extraido));

drop policy campo_classe_sugerida_insert on campo_classe_sugerida;
create policy campo_classe_sugerida_insert on campo_classe_sugerida for insert to authenticated with check (campo_extraido_id in (select id from campo_extraido));

drop policy golden_documento_read on golden_documento;
create policy golden_documento_read on golden_documento for select to authenticated using (documento_id in (select id from documento));

drop policy golden_documento_insert on golden_documento;
create policy golden_documento_insert on golden_documento for insert to authenticated with check (documento_id in (select id from documento));

drop policy golden_campo_read on golden_campo;
create policy golden_campo_read on golden_campo for select to authenticated using (documento_id in (select id from documento));

drop policy golden_campo_insert on golden_campo;
create policy golden_campo_insert on golden_campo for insert to authenticated with check (documento_id in (select id from documento));

drop policy golden_rotulo_read on golden_rotulo;
create policy golden_rotulo_read on golden_rotulo for select to authenticated using (documento_id in (select id from documento));

drop policy golden_rotulo_insert on golden_rotulo;
create policy golden_rotulo_insert on golden_rotulo for insert to authenticated with check (documento_id in (select id from documento));

drop policy caso_authenticated_all on caso;
create policy caso_select on caso for select to authenticated using (id in (select fn_meus_casos()));
-- INSERT continua aberto: é como o portal cria o mandato (fn_upsert_caso); o gatilho da 0215 torna o criador membro.
create policy caso_insert on caso for insert to authenticated with check (true);
create policy caso_update on caso for update to authenticated
  using (id in (select fn_meus_casos())) with check (id in (select fn_meus_casos()));
create policy caso_delete on caso for delete to authenticated using (id in (select fn_meus_casos()));

drop policy evento_auditoria_read on evento_auditoria;
create policy evento_auditoria_read on evento_auditoria for select to authenticated
  using (caso_id in (select fn_meus_casos()) or (caso_id is null and fn_eh_admin()));
drop policy evento_auditoria_insert on evento_auditoria;
create policy evento_auditoria_insert on evento_auditoria for insert to authenticated
  with check (caso_id is null or caso_id in (select fn_meus_casos()));

drop policy documentos_authenticated_all on storage.objects;
create policy documentos_por_mandato on storage.objects for all to authenticated
  using (bucket_id = 'documentos' and public.fn_caso_da_chave(name) in (select public.fn_meus_casos()))
  with check (bucket_id = 'documentos' and public.fn_caso_da_chave(name) in (select public.fn_meus_casos()));

-- -----------------------------------------------------------------------------
-- 6. GRANTs (0214): nenhum objeto novo sem acesso. A coluna caso_id herda o do evento_auditoria. Função: o Postgres dá
--    EXECUTE a PUBLIC por default, então o revoke vem primeiro. Gatilho não precisa de EXECUTE para o authenticated.
-- -----------------------------------------------------------------------------
revoke execute on function fn_meus_casos(), fn_caso_id_do_nome(text), fn_caso_da_chave(text),
  fn_caso_da_referencia(text), fn_trg_evento_caso_id() from public, anon, authenticated;
grant execute on function fn_meus_casos(), fn_caso_id_do_nome(text), fn_caso_da_chave(text),
  fn_caso_da_referencia(text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 7. A SONDA. A função é a da 0215 INTEIRA (extraída do próprio arquivo, não replace de texto sobre o banco — memória
--    nunca-corrigir-funcao-por-replace) com o ramo `policy` ampliado (schema.tabela.policy e marcador na expressão).
-- -----------------------------------------------------------------------------
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
  v_polnome    name;
  v_polexpr    text;
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
      -- 0216: (a) `objeto` aceita 'schema.tabela.policy' (a policy do bucket mora em storage.objects); (b) `marcador`,
      -- quando declarado, tem de aparecer na EXPRESSÃO da policy (using + with check). Sem (b), a policy
      -- `using (true)` que a 0216 existe para tirar passaria por "presente": o nome é o mesmo, só a regra mudou.
      if array_length(string_to_array(r.objeto, '.'), 1) = 3 then
        v_alvo := to_regclass(split_part(r.objeto, '.', 1) || '.' || split_part(r.objeto, '.', 2));
      else
        v_alvo := to_regclass('public.' || split_part(r.objeto, '.', 1));
      end if;
      if v_alvo is null then
        v_ok  := false;
        v_det := 'a tabela nem existe';
      else
        select p.polname, coalesce(pg_get_expr(p.polqual, p.polrelid), '') || ' ' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '')
          into v_polnome, v_polexpr
          from pg_policy p
         where p.polrelid = v_alvo and p.polname = split_part(r.objeto, '.', array_length(string_to_array(r.objeto, '.'), 1));
        if v_polnome is null then
          v_ok  := false;
          v_det := 'a policy não existe na tabela (RLS ligada sem ela nega a operação ao authenticated)';
        elsif r.marcador is not null and position(r.marcador in v_polexpr) = 0 then
          v_ok  := false;
          v_det := format('a policy existe, mas a expressão dela NÃO contém %s — a regra por mandato não está nela (using (true)?)', r.marcador);
        else
          v_ok  := true;
          v_det := 'policy presente';
        end if;
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
  'Confere cada requisito de instalacao_requisito contra o catálogo do banco. Sobrevive ao objeto ausente (to_regclass/to_regproc devolvem NULL em vez de erro): a sonda não pode falhar por causa do que ela existe para medir. Desde a 0147 confere também o CORPO da função (tipo=corpo), que é o único jeito de distinguir uma correção aplicada de uma função homônima com o corpo velho. Desde a 0189 confere também GATILHO (tipo=gatilho): existência na tabela E tgenabled em (''O'',''A'') — a função do gatilho sobrevive a drop trigger/disable trigger e por isso NUNCA prova, sozinha, que a guarda está ligada. Desde a 0210 confere também POLICY (tipo=policy, objeto tabela.nome_da_policy): existência em pg_policy. Desde a 0214 confere PRIVILÉGIO (tipo=privilegio, objeto papel:classe, marcador = privilégios): toda tabela/view/sequence de public sem o mínimo para authenticated e service_role é buraco — o Supabase deixou de conceder por default privilege em 30/10/2026. Desde a 0215 confere também EXECUÇÃO de função (tipo=execucao, objeto papel:funcao, marcador sim|nao): has_function_privilege, que enxerga o PUBLIC — é o que cobra o revoke de fn_administrador_definir. Desde a 0216 o requisito de policy aceita `schema.tabela.policy` e um marcador que tem de constar na expressão da policy (é o que distingue a policy por mandato do using (true) de mesmo nome).';

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('mandato_arquivo_oficial_por_mandato', '0216', 'policy', 'arquivo_oficial.arquivo_oficial_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de arquivo_oficial (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 941),
  ('mandato_caso_apresentacao_campo_por_mandato', '0216', 'policy', 'caso_apresentacao_campo.caso_apresentacao_campo_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de caso_apresentacao_campo (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 942),
  ('mandato_caso_linha_premissa_por_mandato', '0216', 'policy', 'caso_linha_premissa.caso_linha_premissa_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de caso_linha_premissa (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 943),
  ('mandato_caso_modelagem_por_mandato', '0216', 'policy', 'caso_modelagem.caso_modelagem_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de caso_modelagem (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 944),
  ('mandato_caso_premissa_por_mandato', '0216', 'policy', 'caso_premissa.caso_premissa_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de caso_premissa (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 945),
  ('mandato_checklist_item_status_por_mandato', '0216', 'policy', 'checklist_item_status.checklist_item_status_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de checklist_item_status (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 946),
  ('mandato_decisao_por_mandato', '0216', 'policy', 'decisao.decisao_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de decisao (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 947),
  ('mandato_documento_por_mandato', '0216', 'policy', 'documento.documento_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de documento (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 948),
  ('mandato_entidade_por_mandato', '0216', 'policy', 'entidade.entidade_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de entidade (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 949),
  ('mandato_execucao_falha_por_mandato', '0216', 'policy', 'execucao_falha.execucao_falha_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de execucao_falha (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 950),
  ('mandato_lote_execucao_por_mandato', '0216', 'policy', 'lote_execucao.lote_execucao_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de lote_execucao (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 951),
  ('mandato_pendencia_por_mandato', '0216', 'policy', 'pendencia.pendencia_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de pendencia (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 952),
  ('mandato_periodo_por_mandato', '0216', 'policy', 'periodo.periodo_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de periodo (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 953),
  ('mandato_reconciliacao_por_mandato', '0216', 'policy', 'reconciliacao.reconciliacao_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de reconciliacao (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 954),
  ('mandato_documento_versao_por_mandato', '0216', 'policy', 'documento_versao.documento_versao_por_mandato', 'FROM documento', null,
   'Sem a policy por mandato de documento_versao (ou com ela voltada a using (true)) todo usuário logado lê e grava as linhas dos mandatos alheios — o caso desta tabela vem do pai (documento).',
   'bloqueante', 955),
  ('mandato_campo_extraido_por_mandato', '0216', 'policy', 'campo_extraido.campo_extraido_por_mandato', 'FROM documento_versao', null,
   'Sem a policy por mandato de campo_extraido (ou com ela voltada a using (true)) todo usuário logado lê e grava as linhas dos mandatos alheios — o caso desta tabela vem do pai (documento_versao).',
   'bloqueante', 956),
  ('mandato_documento_fato_por_mandato', '0216', 'policy', 'documento_fato.documento_fato_por_mandato', 'FROM documento_versao', null,
   'Sem a policy por mandato de documento_fato (ou com ela voltada a using (true)) todo usuário logado lê e grava as linhas dos mandatos alheios — o caso desta tabela vem do pai (documento_versao).',
   'bloqueante', 957),
  ('mandato_arquivo_oficial_registro_por_mandato', '0216', 'policy', 'arquivo_oficial_registro.arquivo_oficial_registro_por_mandato', 'FROM arquivo_oficial', null,
   'Sem a policy por mandato de arquivo_oficial_registro (ou com ela voltada a using (true)) todo usuário logado lê e grava as linhas dos mandatos alheios — o caso desta tabela vem do pai (arquivo_oficial).',
   'bloqueante', 958),
  ('mandato_arquivo_oficial_lancamento_mes_por_mandato', '0216', 'policy', 'arquivo_oficial_lancamento_mes.arquivo_oficial_lancamento_mes_por_mandato', 'FROM arquivo_oficial', null,
   'Sem a policy por mandato de arquivo_oficial_lancamento_mes (ou com ela voltada a using (true)) todo usuário logado lê e grava as linhas dos mandatos alheios — o caso desta tabela vem do pai (arquivo_oficial).',
   'bloqueante', 959),
  ('mandato_caso_pergunta_read', '0216', 'policy', 'caso_pergunta.caso_pergunta_read', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy caso_pergunta_read (select em caso_pergunta) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 960),
  ('mandato_caso_pergunta_insert', '0216', 'policy', 'caso_pergunta.caso_pergunta_insert', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy caso_pergunta_insert (insert em caso_pergunta) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 961),
  ('mandato_caso_pergunta_reapontar', '0216', 'policy', 'caso_pergunta.caso_pergunta_reapontar', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy caso_pergunta_reapontar (update em caso_pergunta) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 962),
  ('mandato_controlador_read', '0216', 'policy', 'controlador.controlador_read', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy controlador_read (select em controlador) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 963),
  ('mandato_controlador_insert', '0216', 'policy', 'controlador.controlador_insert', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy controlador_insert (insert em controlador) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 964),
  ('mandato_controlador_vinculo_read', '0216', 'policy', 'controlador_vinculo.controlador_vinculo_read', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy controlador_vinculo_read (select em controlador_vinculo) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 965),
  ('mandato_controlador_vinculo_insert', '0216', 'policy', 'controlador_vinculo.controlador_vinculo_insert', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy controlador_vinculo_insert (insert em controlador_vinculo) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 966),
  ('mandato_controlador_vinculo_update', '0216', 'policy', 'controlador_vinculo.controlador_vinculo_update', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy controlador_vinculo_update (update em controlador_vinculo) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 967),
  ('mandato_entidade_controlador_read', '0216', 'policy', 'entidade_controlador.entidade_controlador_read', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy entidade_controlador_read (select em entidade_controlador) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 968),
  ('mandato_entidade_controlador_insert', '0216', 'policy', 'entidade_controlador.entidade_controlador_insert', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy entidade_controlador_insert (insert em entidade_controlador) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 969),
  ('mandato_entidade_controlador_update', '0216', 'policy', 'entidade_controlador.entidade_controlador_update', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy entidade_controlador_update (update em entidade_controlador) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 970),
  ('mandato_perimetro_read', '0216', 'policy', 'perimetro.perimetro_read', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy perimetro_read (select em perimetro) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 971),
  ('mandato_perimetro_insert', '0216', 'policy', 'perimetro.perimetro_insert', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy perimetro_insert (insert em perimetro) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 972),
  ('mandato_perimetro_update', '0216', 'policy', 'perimetro.perimetro_update', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy perimetro_update (update em perimetro) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 973),
  ('mandato_campo_classe_override_read', '0216', 'policy', 'campo_classe_override.campo_classe_override_read', 'FROM campo_extraido', null,
   'Sem a restrição por mandato na policy campo_classe_override_read (select em campo_classe_override) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 974),
  ('mandato_campo_classe_override_insert', '0216', 'policy', 'campo_classe_override.campo_classe_override_insert', 'FROM campo_extraido', null,
   'Sem a restrição por mandato na policy campo_classe_override_insert (insert em campo_classe_override) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 975),
  ('mandato_campo_classe_sugerida_read', '0216', 'policy', 'campo_classe_sugerida.campo_classe_sugerida_read', 'FROM campo_extraido', null,
   'Sem a restrição por mandato na policy campo_classe_sugerida_read (select em campo_classe_sugerida) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 976),
  ('mandato_campo_classe_sugerida_insert', '0216', 'policy', 'campo_classe_sugerida.campo_classe_sugerida_insert', 'FROM campo_extraido', null,
   'Sem a restrição por mandato na policy campo_classe_sugerida_insert (insert em campo_classe_sugerida) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 977),
  ('mandato_golden_documento_read', '0216', 'policy', 'golden_documento.golden_documento_read', 'FROM documento', null,
   'Sem a restrição por mandato na policy golden_documento_read (select em golden_documento) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 978),
  ('mandato_golden_documento_insert', '0216', 'policy', 'golden_documento.golden_documento_insert', 'FROM documento', null,
   'Sem a restrição por mandato na policy golden_documento_insert (insert em golden_documento) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 979),
  ('mandato_golden_campo_read', '0216', 'policy', 'golden_campo.golden_campo_read', 'FROM documento', null,
   'Sem a restrição por mandato na policy golden_campo_read (select em golden_campo) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 980),
  ('mandato_golden_campo_insert', '0216', 'policy', 'golden_campo.golden_campo_insert', 'FROM documento', null,
   'Sem a restrição por mandato na policy golden_campo_insert (insert em golden_campo) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 981),
  ('mandato_golden_rotulo_read', '0216', 'policy', 'golden_rotulo.golden_rotulo_read', 'FROM documento', null,
   'Sem a restrição por mandato na policy golden_rotulo_read (select em golden_rotulo) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 982),
  ('mandato_golden_rotulo_insert', '0216', 'policy', 'golden_rotulo.golden_rotulo_insert', 'FROM documento', null,
   'Sem a restrição por mandato na policy golden_rotulo_insert (insert em golden_rotulo) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 983),
  ('mandato_caso_select', '0216', 'policy', 'caso.caso_select', 'fn_meus_casos', null,
   'Sem a restrição por mandato em caso_select o usuário logado lê/altera/apaga o mandato alheio.',
   'bloqueante', 984),
  ('mandato_caso_update', '0216', 'policy', 'caso.caso_update', 'fn_meus_casos', null,
   'Sem a restrição por mandato em caso_update o usuário logado lê/altera/apaga o mandato alheio.',
   'bloqueante', 985),
  ('mandato_caso_delete', '0216', 'policy', 'caso.caso_delete', 'fn_meus_casos', null,
   'Sem a restrição por mandato em caso_delete o usuário logado lê/altera/apaga o mandato alheio.',
   'bloqueante', 986),
  ('mandato_caso_insert', '0216', 'policy', 'caso.caso_insert', null, null,
   'Sem a policy de insert em caso o portal não cria mandato (42501).',
   'bloqueante', 987),
  ('mandato_evento_auditoria_read', '0216', 'policy', 'evento_auditoria.evento_auditoria_read', 'fn_meus_casos', null,
   'Sem a restrição por mandato o rastro de auditoria (que guarda antes/depois do dado do cliente) é lido por todo usuário logado.',
   'bloqueante', 988),
  ('mandato_evento_auditoria_insert', '0216', 'policy', 'evento_auditoria.evento_auditoria_insert', 'fn_meus_casos', null,
   'Sem a policy o authenticated forja evento no mandato alheio — ou, ausente, o rastro falha (42501).',
   'bloqueante', 989),
  ('mandato_storage_documentos', '0216', 'policy', 'storage.objects.documentos_por_mandato', 'fn_meus_casos', null,
   'Sem a restrição por mandato no bucket documentos todo usuário logado baixa o arquivo original de qualquer mandato (o balanço, o contrato social).',
   'bloqueante', 990),
  ('tabela_evento_caso_id', '0216', 'coluna', 'evento_auditoria.caso_id', null, null,
   'Sem a coluna o evento não tem a que mandato pertencer: a leitura por mandato do rastro não funciona.',
   'bloqueante', 991),
  ('gatilho_evento_caso_id', '0216', 'gatilho', 'evento_auditoria.trg_evento_caso_id', null, null,
   'Sem o gatilho (ou desabilitado) o evento novo nasce sem caso_id e só o administrador o lê: o membro deixa de ver o rastro do próprio mandato, calado.',
   'bloqueante', 992),
  ('fn_meus_casos', '0216', 'funcao', 'fn_meus_casos', null, null,
   'Toda policy por mandato chama; sem ela (ou sem EXECUTE) o portal inteiro leva "permission denied" ou zero linhas.',
   'bloqueante', 993),
  ('fn_caso_id_do_nome', '0216', 'funcao', 'fn_caso_id_do_nome', null, null,
   'fn_upsert_caso a chama; sem ela o não membro volta a criar mandato duplicado (ou a função morre).',
   'bloqueante', 994),
  ('fn_caso_da_chave', '0216', 'funcao', 'fn_caso_da_chave', null, null,
   'A policy do bucket documentos chama; sem ela ninguém lê o arquivo original.',
   'bloqueante', 995),
  ('fn_caso_da_referencia', '0216', 'funcao', 'fn_caso_da_referencia', null, null,
   'O gatilho do evento chama; sem ela todo insert de evento falha.',
   'bloqueante', 996),
  ('fn_trg_evento_caso_id', '0216', 'funcao', 'fn_trg_evento_caso_id', null, null,
   'O gatilho do evento chama.',
   'bloqueante', 997),
  ('fn_0216_exige_administrador', '0216', 'funcao', 'fn_0216_exige_administrador', null, null,
   'Guarda da 0216 (sinal positivo de administrador).',
   'informativo', 998),
  ('exec_meus_casos_authenticated', '0216', 'execucao', 'authenticated:fn_meus_casos', 'sim', null,
   'authenticated não executa fn_meus_casos: a policy por mandato (ou fn_upsert_caso) leva "permission denied" e a tela quebra.',
   'bloqueante', 999),
  ('exec_caso_id_do_nome_authenticated', '0216', 'execucao', 'authenticated:fn_caso_id_do_nome', 'sim', null,
   'authenticated não executa fn_caso_id_do_nome: a policy por mandato (ou fn_upsert_caso) leva "permission denied" e a tela quebra.',
   'bloqueante', 1000),
  ('exec_caso_da_chave_authenticated', '0216', 'execucao', 'authenticated:fn_caso_da_chave', 'sim', null,
   'authenticated não executa fn_caso_da_chave: a policy por mandato (ou fn_upsert_caso) leva "permission denied" e a tela quebra.',
   'bloqueante', 1001),
  ('exec_caso_da_referencia_authenticated', '0216', 'execucao', 'authenticated:fn_caso_da_referencia', 'sim', null,
   'authenticated não executa fn_caso_da_referencia: a policy por mandato (ou fn_upsert_caso) leva "permission denied" e a tela quebra.',
   'bloqueante', 1002),
  ('exec_exige_admin_authenticated', '0216', 'execucao', 'authenticated:fn_0216_exige_administrador', 'nao', null,
   'authenticated executa a guarda da 0216 (inofensiva, mas não é do portal).',
   'informativo', 1003),
  ('upsert_caso_guarda_membro', '0216', 'corpo', 'fn_upsert_caso', 'fn_caso_id_do_nome', null,
   'fn_upsert_caso com o corpo ANTERIOR à 0216: o não membro cria mandato duplicado com o nome de um existente (a RLS esconde o original).',
   'bloqueante', 1004)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0216', revisado_em = current_date,
       observacao = 'A 0216 troca as policies using (true) das tabelas de dado do cliente por policies por mandato (caso_membro/administrador da 0215), restringe o bucket documentos, dá caso_id ao evento_auditoria (gatilho + backfill) e reemite fn_upsert_caso com a recusa ao não membro. A sonda ganha 64 requisitos e o ramo policy passa a conferir a EXPRESSÃO da policy (marcador) e policies de storage.'
 where id = true;

commit;
