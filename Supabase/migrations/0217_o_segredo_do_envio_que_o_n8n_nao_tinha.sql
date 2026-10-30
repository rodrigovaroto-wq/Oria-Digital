-- =============================================================================
-- 0217 — O SEGREDO DO ENVIO NO VAULT DO BANCO: `fn_conferir_envio` (a conferência do token HMAC sai do n8n e vira função)
-- (Cria 2 funções — fn_conferir_envio e fn_segredo_do_vault_presente —, acrescenta o tipo `segredo` à sonda e 3 requisitos.
--  Sem tabela, sem gatilho, sem backfill, e a migration NÃO GRAVA SEGREDO NENHUM: o valor nunca entra no repositório.)
--
-- O DEFEITO (medido em 30/10/2026). O nó `Conferir Envio` do workflow de ingestão lia o segredo do envio de
-- `$env.N8N_INTAKE_SEGREDO` ou de `$vars`. Em produção NENHUM dos dois existe: a licença do n8n não tem Variables (403
-- da API) e o PikaPods, onde o n8n roda, não deixa criar variável de ambiente. Sem segredo o nó recusa TODO envio, com a
-- mensagem "o n8n não tem o segredo" — o portal inteiro parou de ingerir, e nada no banco acusava (a recusa é uma
-- falha gravada em `execucao_falha`, não um erro de instalação).
--
-- A CAUSA. O segredo morava onde o dono não consegue configurar. Decisão do dono (30/10/2026): ele vai para o Vault do
-- Supabase (extensões `supabase_vault` 0.3.1 e `pgcrypto` 1.3 já instaladas em produção, medido) e a conferência passa a
-- ser uma função do Postgres, chamada por um nó Postgres do n8n. É a MESMA semântica de `verificarEnvio` /
-- `veredictoDoEnvio` em N8N/lib/assinatura-do-envio.mjs (o lado que assina é portal/src/lib/assinatura-do-envio.ts):
-- mesmos motivos, na mesma ordem — sem_segredo > sem_token > malformado > assinatura > expirado, a assinatura
-- conferida ANTES do prazo, para a recusa por expiração só existir para quem provou ter o segredo.
--
-- O CONTRATO (o nó do n8n depende dele; não mude a assinatura sem mudar o nó):
--   fn_conferir_envio(p_token text, p_mandato text, p_agora timestamptz default now())
--   returns table(envio_autorizado boolean, caso_id uuid, etapa_recusa text, motivo_recusa text,
--                 orcamento_mensagem text, usuario_id text)
-- SEMPRE exatamente UMA linha. `caso_id` é sempre NULL e `etapa_recusa` é sempre 'envio' (o formato que `Registrar
-- Recusa` já lê). `motivo_recusa` = sem_segredo | sem_token | malformado | assinatura | expirado (NULL quando autorizado);
-- `orcamento_mensagem` = o texto que o portal mostra; `usuario_id` = quem assinou (só quando autorizado).
--
-- COMO GRAVAR O SEGREDO (uma vez, por quem administra o banco — SQL Editor do Supabase, como `postgres`):
--     select vault.create_secret('<o mesmo valor de N8N_INTAKE_SEGREDO da Vercel>', 'n8n_intake_segredo',
--                                'Segredo do HMAC do envio ao n8n (0217)');
-- COMO TROCAR (o portal na Vercel e o banco têm de receber o MESMO valor; entre uma troca e a outra todo envio é recusado,
-- então troque os dois juntos e republique o deploy):
--     select vault.update_secret(id, '<novo valor>') from vault.secrets where name = 'n8n_intake_segredo';
-- COMO CONFERIR QUE ESTÁ LÁ (sem ler o valor): `select * from fn_instalacao_conferir() where chave = 'envio_segredo_no_vault'`.
-- O valor nunca é devolvido por função nenhuma deste repositório.
--
-- QUEM EXECUTA. `security definer` (o dono, `postgres`, lê `vault.decrypted_secrets`; o chamador não precisa de acesso ao
-- Vault) e `set search_path` fixo. EXECUTE: `service_role` e `postgres` — a conexão de serviço do n8n (Postgres nativo pelo
-- pooler, BYPASSRLS, ESTADO 30/10/2026) é uma dessas duas. `anon`, `authenticated` e PUBLIC NÃO executam: se `authenticated`
-- pudesse, qualquer usuário logado testaria tokens contra o segredo sem limite e sem que ninguém visse.
--
-- DECISÕES QUE PODERIAM TER SIDO OUTRAS:
--   * COMPARAÇÃO DA ASSINATURA. O JS compara em tempo constante. Aqui compara-se o HMAC (chave = o próprio segredo) do valor
--     esperado com o HMAC do valor recebido: o `=` de bytea para no primeiro byte diferente, mas os bytes comparados são
--     digestos que o atacante não controla nem consegue prever sem o segredo — o prefixo em comum de dois HMAC não diz
--     nada sobre o prefixo em comum das assinaturas originais. Mesma garantia do double-HMAC, sem laço em plpgsql.
--   * MINÚSCULAS. O portal assina `mandato.toLowerCase()` (JS). O `lower()` do Postgres DIVERGE dele em texto real, e o
--     resultado ainda depende do locale do banco. MEDIDO em 30/10/2026 (banco C.UTF-8, PG 16.15), com a divergência SENDO
--     do `lower()` e não do ICU: "İ" (U+0130) o JS devolve "i" + U+0307 e o `lower()` devolve "i"; "ΑΣ" o JS devolve com
--     sigma FINAL ("ας") e o `lower()` devolve "ασ". Com `lower(x collate "und-x-icu")` (ICU, mapeamento Unicode completo,
--     independente de locale) os dois casos batem com o JS, e "AÇÕES", "Ä", "ẞ", "ᾈ" batem nos dois. A migration usa o ICU
--     e ABORTA, com a explicação, se a collation `und-x-icu` não existir (banco sem ICU) — recusar a migration é melhor
--     que recusar, em silêncio, todo mandato acentuado. Nome de mandato com "İ" ou "Σ" final é raro; o custo do ICU é
--     zero, e a paridade com o portal tem teste (Supabase/test/conferir_envio.test.sql).
--   * ESPAÇO. `normalizarMandato` tira só U+0020 das pontas (a mesma regra do índice `caso_nome_unico`, `btrim`); o `trim()`
--     do TOKEN e do SEGREDO tira todo espaço Unicode do JS (\s do ECMAScript: tab, quebras, NBSP, U+2000–200A, U+2028/9,
--     U+202F, U+205F, U+3000, BOM). As duas regras foram reproduzidas, cada uma onde o JS a usa.
--   * HMAC. `hmac()` do pgcrypto, que no Supabase mora no schema `extensions` (e, num Postgres local, em `public`): o
--     `search_path` da função é `pg_catalog, extensions, public, pg_temp` — `extensions` ANTES de `public` e `pg_temp`
--     por último, para um objeto criado em `public` ou na sessão não sombrear o `hmac` verdadeiro nem `lower`/`encode`.
--
-- A SONDA. Tipo novo `segredo` (objeto = nome do segredo no Vault), com a função da 0214 reeditada INTEIRA, extraída do
-- próprio arquivo e com UM ramo novo (diff contra a função do banco antes: só esse ramo). O ramo pergunta a
-- `fn_segredo_do_vault_presente`, que devolve boolean e nunca o valor. Requisito `envio_segredo_no_vault` é bloqueante e
-- diz o SINTOMA: "todo envio pelo portal é recusado" (regra 7: sem ele o estágio parece instalado — função presente, nada
-- vermelho — e o n8n recusa tudo).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/conferir_envio.test.sql — 63 asserts, medidos em 30/10/2026 com
-- `PGOPTIONS=-cenvio.medindo=on` (o assert vira `raise warning` e CONTA; sem a variável é `raise exception`). Controle: 0 falhas em
-- 63. Cada correção desligada UMA vez no banco já migrado (conferido que a variante APLICOU antes de rodar o teste); reprovações / 63:
--   * minúsculas sem o ICU (lower() puro): 2 ("İ" e sigma final)   * sem minúsculas no mandato: 16   * hmac ignora o mandato: 17
--   * sem o trim do token: 3          * trim de TODO espaço no mandato (em vez de só U+0020): 1   * segredo só de espaços vale: 3
--   * sem_segredo desligado: 5        * EXECUTE concedido a authenticated: 2          * prazo conferido ANTES da assinatura: 1
--   * prazo frouxo (>= em vez de >): 1 * sonda sempre verde para o segredo: 4         * lista de nomes de fn_segredo_do_vault_presente removida: 1
--   * `\d` no lugar de [0-9] no exp: 0 — NÃO reprova em C.UTF-8 (o \d do ARE só casa ASCII nesse locale); o [0-9] fica porque em
--     outro locale o \d pode casar dígitos não-ASCII, e isso não dá para provar aqui. É o único 0, declarado.
-- Comparação em tempo constante (HMAC dos dois lados): sem assert, de propósito — é propriedade de TEMPO, e o resultado é idêntico a `<>`.

-- -----------------------------------------------------------------------------
-- 0. PRÉ-CONDIÇÕES — abortar aqui, com a explicação, é melhor que instalar uma conferência que recusa tudo.
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_collation where collname = 'und-x-icu') then
    raise exception '0217: a collation "und-x-icu" não existe neste banco (Postgres sem ICU). fn_conferir_envio usa lower(... collate "und-x-icu") para dar as MESMAS minúsculas do toLowerCase do portal; sem ela, mandato com "İ" ou sigma final seria recusado em silêncio.';
  end if;
  if not exists (select 1 from pg_extension where extname = 'pgcrypto') then
    raise exception '0217: a extensão pgcrypto não está instalada (create extension pgcrypto with schema extensions) — fn_conferir_envio calcula o HMAC com hmac().';
  end if;
  if to_regclass('vault.decrypted_secrets') is null then
    raise exception '0217: vault.decrypted_secrets não existe — habilite a extensão supabase_vault (create extension supabase_vault) antes.';
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- 1. A SONDA PERGUNTA SE O SEGREDO EXISTE, SEM LÊ-LO
-- -----------------------------------------------------------------------------
create or replace function fn_segredo_do_vault_presente(p_nome text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
  -- Só os nomes desta lista: a função é executável por `authenticated` (a sonda roda no portal) e não pode virar um
  -- oráculo "esta chave existe?" sobre o Vault inteiro. Vazio ou só espaço = ausente (o mesmo critério de fn_conferir_envio).
  select p_nome in ('n8n_intake_segredo')
     and exists (select 1 from vault.decrypted_secrets s
                  where s.name = p_nome
                    and regexp_replace(coalesce(s.decrypted_secret, ''),
                        '[\u0009\u000a\u000b\u000c\u000d\u0020\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]', '', 'g') <> '')
$$;

revoke all on function fn_segredo_do_vault_presente(text) from public, anon;
grant execute on function fn_segredo_do_vault_presente(text) to authenticated, service_role;

comment on function fn_segredo_do_vault_presente(text) is
  '0217: o segredo (só n8n_intake_segredo) existe no Vault e não está vazio? Devolve boolean, nunca o valor. security definer porque a sonda roda como authenticated, que não lê o Vault.';

-- -----------------------------------------------------------------------------
-- 2. A CONFERÊNCIA DO ENVIO
-- -----------------------------------------------------------------------------
create or replace function fn_conferir_envio(p_token text, p_mandato text, p_agora timestamptz default now())
returns table (envio_autorizado boolean, caso_id uuid, etapa_recusa text, motivo_recusa text,
               orcamento_mensagem text, usuario_id text)
language plpgsql
stable
security definer
set search_path = pg_catalog, extensions, public, pg_temp
as $$
declare
  -- \s do ECMAScript (o que String.prototype.trim tira), como classe de ARE. Os controles vão por \uXXXX, não por \n/\r:
  -- o portão guarda_ancora_crlf.py toma `\n` num regexp_replace por âncora de patch de função (aqui não há patch nenhum).
  c_ws     constant text := '[\u0009\u000a\u000b\u000c\u000d\u0020\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]';
  v_segredo text;
  v_token   text;
  v_partes  text[];
  v_msg     text;
  v_motivo  text;
  v_usuario text;
begin
  -- 1. sem_segredo: ausente, vazio ou só espaços. O valor entra como chave do HMAC SEM trim (como o JS).
  select s.decrypted_secret into v_segredo from vault.decrypted_secrets s where s.name = 'n8n_intake_segredo' limit 1;
  if v_segredo is null or regexp_replace(v_segredo, c_ws, '', 'g') = '' then
    v_motivo := 'sem_segredo';
  else
    -- 2. sem_token: nulo, vazio ou só espaços.
    v_token := regexp_replace(coalesce(p_token, ''), '^' || c_ws || '+|' || c_ws || '+$', '', 'g');
    if v_token = '' then
      v_motivo := 'sem_token';
    else
      -- 3. malformado: v1.<exp>.<usuario>.<hmac>. [0-9] e não \d: o \d do ARE segue o locale; o do JS é só ASCII.
      v_partes := string_to_array(v_token, '.');
      if coalesce(array_length(v_partes, 1), 0) <> 4 or v_partes[1] <> 'v1'
         or v_partes[2] !~ '^[0-9]{1,12}$' or v_partes[3] !~ '^[0-9a-fA-F-]{8,64}$' or v_partes[4] !~ '^[0-9a-f]{64}$' then
        v_motivo := 'malformado';
      else
        -- 4. assinatura. Mensagem = mandato (só U+0020 das pontas tirado, minúsculas do ICU = toLowerCase) | exp | usuário.
        v_msg := lower(regexp_replace(coalesce(p_mandato, ''), '^ +| +$', '', 'g') collate "und-x-icu")
                 || '|' || v_partes[2] || '|' || v_partes[3];
        -- Comparação dos HMAC dos dois valores (ver o cabeçalho: não vaza a posição da divergência).
        if hmac(convert_to(encode(hmac(convert_to(v_msg, 'UTF8'), convert_to(v_segredo, 'UTF8'), 'sha256'), 'hex'), 'UTF8'),
                convert_to(v_segredo, 'UTF8'), 'sha256')
           is distinct from hmac(convert_to(v_partes[4], 'UTF8'), convert_to(v_segredo, 'UTF8'), 'sha256') then
          v_motivo := 'assinatura';
        -- 5. expirado: só depois de a assinatura provar que o token é nosso. exp*1000 > agora (ms), senão expirado.
        elsif not (v_partes[2]::bigint * 1000 > floor(extract(epoch from p_agora) * 1000)::bigint) then
          v_motivo := 'expirado';
        else
          v_usuario := v_partes[3];
        end if;
      end if;
    end if;
  end if;

  return query select
    v_motivo is null,
    null::uuid,
    'envio'::text,
    v_motivo,
    case
      when v_motivo is null then null
      when v_motivo = 'sem_segredo' then 'Envio recusado: falta o segredo do envio no Vault do banco (nome n8n_intake_segredo). '
        || 'Nada foi gravado. É configuração do responsável pelo sistema.'
      when v_motivo = 'expirado' then 'Envio sem autorização válida: o token do envio expirou. Nada foi gravado. Reenvie pelo portal.'
      else 'Envio sem autorização válida. Nada foi gravado. Envie pelo portal, com o login de quem tem acesso ao mandato.'
    end,
    v_usuario;
end;
$$;

revoke all on function fn_conferir_envio(text, text, timestamptz) from public, anon, authenticated;
grant execute on function fn_conferir_envio(text, text, timestamptz) to service_role, postgres;

comment on function fn_conferir_envio(text, text, timestamptz) is
  '0217: confere o token HMAC do envio (v1.<exp>.<usuario>.<hmac>, assinado pelo portal sobre mandato_normalizado|exp|usuario) contra o segredo n8n_intake_segredo do Vault. Sempre UMA linha: envio_autorizado, caso_id (sempre NULL), etapa_recusa (sempre envio), motivo_recusa (sem_segredo|sem_token|malformado|assinatura|expirado), orcamento_mensagem, usuario_id. Mesma semântica de verificarEnvio em N8N/lib/assinatura-do-envio.mjs. security definer; só service_role e postgres executam (authenticated testaria tokens contra o segredo).';

-- -----------------------------------------------------------------------------
-- 3. A SONDA PASSA A VER SEGREDO DO VAULT (a função da 0214 INTEIRA, com UM ramo novo: `segredo`)
-- -----------------------------------------------------------------------------
alter table instalacao_requisito drop constraint if exists instalacao_requisito_tipo_check;
alter table instalacao_requisito add constraint instalacao_requisito_tipo_check
  check (tipo in ('tabela', 'coluna', 'funcao', 'seed', 'comportamento', 'corpo', 'gatilho', 'policy', 'privilegio', 'segredo'));

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
  'Confere cada requisito de instalacao_requisito contra o catálogo do banco. Sobrevive ao objeto ausente (to_regclass/to_regproc devolvem NULL em vez de erro): a sonda não pode falhar por causa do que ela existe para medir. Desde a 0147 confere também o CORPO da função (tipo=corpo), que é o único jeito de distinguir uma correção aplicada de uma função homônima com o corpo velho. Desde a 0189 confere também GATILHO (tipo=gatilho): existência na tabela E tgenabled em (''O'',''A'') — a função do gatilho sobrevive a drop trigger/disable trigger e por isso NUNCA prova, sozinha, que a guarda está ligada. Desde a 0210 confere também POLICY (tipo=policy, objeto tabela.nome_da_policy): existência em pg_policy. Desde a 0214 confere PRIVILÉGIO (tipo=privilegio, objeto papel:classe, marcador = privilégios): toda tabela/view/sequence de public sem o mínimo para authenticated e service_role é buraco — o Supabase deixou de conceder por default privilege em 30/10/2026. Desde a 0217 confere SEGREDO do Vault (tipo=segredo, objeto = nome do segredo): existe e não está vazio, sem ler o valor.';

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('envio_segredo_no_vault', '0217', 'segredo', 'n8n_intake_segredo', null, null,
   'O segredo do envio não está no Vault do banco (ou está vazio): TODO envio pelo portal é recusado ("falta o segredo do envio no Vault"), nada é gravado e o lote não anda — e nenhum outro item desta lista fica vermelho. Grave-o uma vez, no SQL Editor: select vault.create_secret(''<o valor de N8N_INTAKE_SEGREDO da Vercel>'', ''n8n_intake_segredo''); o MESMO valor tem de estar na Vercel.',
   'bloqueante', 960),
  ('envio_conferencia_funcao', '0217', 'funcao', 'fn_conferir_envio', null, null,
   'Sem fn_conferir_envio o nó Conferir Envio do n8n não encontra a função: todo envio pelo portal falha antes de gravar o primeiro documento.',
   'bloqueante', 961),
  ('envio_conferencia_corpo', '0217', 'corpo', 'fn_conferir_envio', 'decrypted_secrets', null,
   'A função existe mas o corpo não lê o segredo do Vault (uma edição que o devolva às variáveis do n8n recusa todo envio de novo, e a função continua presente).',
   'bloqueante', 962)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0217', revisado_em = current_date,
       observacao = 'A 0217 cria fn_conferir_envio e o tipo de requisito segredo (Vault). Catalogada por nome, corpo e pelo segredo n8n_intake_segredo.'
 where id = true;
