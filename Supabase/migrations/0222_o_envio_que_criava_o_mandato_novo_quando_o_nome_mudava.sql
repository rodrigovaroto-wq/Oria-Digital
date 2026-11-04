-- =============================================================================
-- 0222 — O ENVIO QUE CRIAVA UM MANDATO NOVO QUANDO O NOME MUDAVA: o token v2 carrega o CASO, não o nome
-- (Cria 3 funções — fn_pode_escrever_caso_de, fn_caso_do_envio — e REDEFINE fn_pode_escrever_caso e fn_conferir_envio, esta com a
--  MESMA assinatura e as MESMAS colunas de saída; acrescenta 5 requisitos à sonda. Sem tabela, sem gatilho, sem backfill.)
--
-- O DEFEITO. O envio roteava por NOME: o portal assinava `mandato_normalizado|exp|usuario` e o n8n chamava fn_upsert_caso(nome).
-- Renomear um mandato fazia o envio seguinte, ainda com o nome antigo (aba aberta, token já emitido), CRIAR um mandato novo e
-- vazio com o nome antigo — e os documentos iam para ele, longe do mandato que o analista estava olhando. Reproduzido no teste
-- (conferir_envio_v2.test.sql): fn_upsert_caso('nome antigo') depois do rename acrescenta 1 linha em `caso` (CONTROLE do teste).
--
-- A CAUSA. O nome identifica o mandato só enquanto ninguém o renomeia; a identidade verdadeira é o `caso.id`, e o token não a levava.
-- Decisões do dono (04/11/2026): o envio NUNCA cria mandato; mandato FECHADO recusa envio; nome divergente é ACEITO e AUDITADO.
--
-- O TOKEN v2 (contrato fixo; o portal e a lib N8N/lib/assinatura-do-envio.mjs seguem a mesma forma):
--     v2.<exp>.<usuario_uuid>.<caso_uuid>.<hmac_hex>      uuids em minúsculas (regex de uuid ANTES de qualquer cast)
--     hmac = HMAC-SHA256 hex de   v2|<caso_id>|<exp>|<usuario>   com o segredo n8n_intake_segredo do Vault
-- A etiqueta `v2|` é obrigatória: sem ela, um mandato v1 chamado "<uuid de outro caso>" assinaria `<uuid>|exp|usuario` e o token
-- reescrito como v2 daquele caso passaria. Com ela a mensagem v2 nunca é igual à v1 de um nome que seja só o uuid.
-- FECHAMENTO NA ORIGEM (acréscimo do coordenador, achado da F1): um mandato chamado literalmente `v2|<uuid>` faz o v1 assinar
-- `v2|<uuid>|exp|usuario`, idêntico à mensagem v2 daquele caso — a etiqueta só fecha o nome que é o uuid puro. Por isso o ramo v1
-- recusa `malformado`, ANTES do HMAC, o mandato normalizado que comece com `v2|`. (A conferência de acesso do v2 já impede a
-- escalada — o usuário precisa escrever naquele caso —, mas o v1 nunca deve produzir uma mensagem que o v2 aceitaria.)
--
-- fn_conferir_envio (MESMA assinatura: fn_conferir_envio(text, text, timestamptz) e as mesmas 6 colunas; o nó publicado não muda):
--   v1 exatamente como na 0217 (caso_id NULL), mais o fechamento acima. v2, na ordem: sem_segredo > sem_token > malformado >
--   assinatura (antes de QUALQUER consulta a caso) > expirado > caso_inexistente > caso_fechado > sem_acesso. Autorizado devolve
--   o caso_id; as recusas pós-assinatura (expirado em diante) também, para prender a falha ao caso. `p_mandato` é ignorado no v2.
--   sem_acesso: o usuário do token, NO MOMENTO DO ENVIO, não é Sócio nem Analista alocado (fn_pode_escrever_caso_de).
-- fn_pode_escrever_caso_de(usuario, caso): o corpo de fn_pode_escrever_caso com o usuário como parâmetro; fn_pode_escrever_caso(caso)
--   passa a delegar a ela com auth.uid() (mesma semântica; está em dezenas de policies, e acesso_por_caso.test.sql passa inteira).
--   EXECUTE da nova: só service_role e postgres (ela responde "o usuário X escreve no caso Y?" para um X qualquer).
-- fn_caso_do_envio(caso, nome_no_envio): falha FECHADA (exceção) se o caso for nulo ou inexistente; se o nome atual divergir do nome
--   que veio no envio (lower(btrim(...)), a mesma comparação do upsert) grava 1 evento_auditoria 'envio_nome_divergente' com os dois
--   nomes; devolve o caso. EXECUTE só service_role e postgres.
--
-- O QUE FICA PARA O N8N (fora desta migration): o nó publicado ainda chama fn_upsert_caso(nome) com o token v1; trocá-lo por
-- fn_caso_do_envio(caso_id, nome) é a outra metade da F2 — enquanto isso o v1 continua aceito e o defeito continua aberto para ele.
--
-- A SONDA. 5 requisitos bloqueantes provam a 0222 aplicada: corpo de fn_conferir_envio com a mensagem `'v2|' || v_partes[4]`, com `caso_fechado` e com
-- `fn_pode_escrever_caso_de(`; as funções fn_caso_do_envio e fn_pode_escrever_caso_de. O requisito acesso_fn_pode_escrever da 0216
-- marcava `m.papel = 'analista'` em fn_pode_escrever_caso; o marcador sai dela (vai para a _de) e passa a ser a delegação — o
-- marcador antigo é recolocado no requisito novo da _de.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/conferir_envio_v2.test.sql — 52 asserts, medidos em 04/11/2026 com
-- `PGOPTIONS=-cenvio.medindo=on` (o assert vira `raise warning` e CONTA). Controle: 0 falhas em 52. Cada correção desligada UMA vez no
-- banco já migrado (conferido que a variante APLICOU antes de rodar o teste); reprovações / 52:
--   * sem a etiqueta `v2|` na mensagem: 17 (inclui a sonda)    * sem a conferência de acesso (sem_acesso): 6 (inclui a sonda)
--   * sem caso_fechado: 1                      * sem caso_inexistente: 1
--   * sem a auditoria do nome divergente: 3    * guarda v1 `v2|...` desligada: 2
--   * fn_caso_do_envio sem a falha fechada (caso inexistente): 1
--   * fn_pode_escrever_caso_de sempre true: 7 (inclui 2 asserts de fn_pode_escrever_caso, a das policies, que agora delega a ela)
--   * assinatura conferida DEPOIS da consulta a caso: 2
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. A PERGUNTA "ESSE USUÁRIO ESCREVE NESSE CASO?" COM O USUÁRIO COMO ARGUMENTO
-- -----------------------------------------------------------------------------
create function fn_pode_escrever_caso_de(p_usuario uuid, p_caso uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from membro m
     where m.usuario_id = p_usuario
       and (m.papel = 'socio'
            or (m.papel = 'analista' and p_caso is not null
                and exists (select 1 from alocacao a where a.caso_id = p_caso and a.usuario_id = m.usuario_id))))
$$;
revoke all on function fn_pode_escrever_caso_de(uuid, uuid) from public, anon, authenticated;
grant execute on function fn_pode_escrever_caso_de(uuid, uuid) to service_role, postgres;
comment on function fn_pode_escrever_caso_de(uuid, uuid) is
  '0222: o usuário X escreve no caso Y? Sócio escreve tudo; Analista onde está alocado; Leitura nunca. Mesmo corpo que fn_pode_escrever_caso tinha na 0216, com o usuário por parâmetro (o envio decide pelo usuário do TOKEN, não por auth.uid()). Só service_role e postgres executam: para um authenticated qualquer seria um oráculo sobre o papel dos outros.';

-- A policy-facing continua com a mesma assinatura, a mesma volatilidade e a mesma resposta; só delega.
create or replace function fn_pode_escrever_caso(p_caso uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select fn_pode_escrever_caso_de(auth.uid(), p_caso)
$$;

-- -----------------------------------------------------------------------------
-- 2. A CONFERÊNCIA DO ENVIO, v1 + v2
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
  c_ws     constant text := '[\u0009\u000a\u000b\u000c\u000d    -     　﻿]';
  c_uuid   constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  v_segredo text;
  v_token   text;
  v_partes  text[];
  v_msg     text;
  v_motivo  text;
  v_usuario text;
  v_caso    uuid;
  v_ok_mac  boolean;
  v_exp     text;
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
      v_partes := string_to_array(v_token, '.');
      if v_partes[1] = 'v2' then
        -- ---------------------------------------------------------------- v2: v2.<exp>.<usuario>.<caso>.<hmac>
        -- 3. malformado. Os uuids são MINÚSCULOS e validados por regex ANTES do cast (um cast de lixo viraria erro 22P02).
        if coalesce(array_length(v_partes, 1), 0) <> 5
           or v_partes[2] !~ '^[0-9]{1,12}$' or v_partes[3] !~ c_uuid or v_partes[4] !~ c_uuid or v_partes[5] !~ '^[0-9a-f]{64}$' then
          v_motivo := 'malformado';
        else
          v_exp := v_partes[2];
          -- 4. assinatura, ANTES de qualquer consulta a caso: quem não prova o segredo não descobre se o caso existe.
          --    A etiqueta 'v2|' separa esta mensagem da v1 (mandato = "<uuid>").
          v_msg := 'v2|' || v_partes[4] || '|' || v_exp || '|' || v_partes[3];
          v_ok_mac := hmac(convert_to(encode(hmac(convert_to(v_msg, 'UTF8'), convert_to(v_segredo, 'UTF8'), 'sha256'), 'hex'), 'UTF8'),
                           convert_to(v_segredo, 'UTF8'), 'sha256')
                      is not distinct from hmac(convert_to(v_partes[5], 'UTF8'), convert_to(v_segredo, 'UTF8'), 'sha256');
          if not v_ok_mac then
            v_motivo := 'assinatura';
          else
            -- Daqui em diante o token é nosso: toda recusa prende a falha ao caso do token.
            v_caso := v_partes[4]::uuid;
            if not (v_exp::bigint * 1000 > floor(extract(epoch from p_agora) * 1000)::bigint) then
              v_motivo := 'expirado';
            elsif not exists (select 1 from caso c where c.id = v_caso) then
              v_motivo := 'caso_inexistente';
            elsif exists (select 1 from caso c where c.id = v_caso and c.fechado_em is not null) then
              v_motivo := 'caso_fechado';
            elsif not fn_pode_escrever_caso_de(v_partes[3]::uuid, v_caso) then
              v_motivo := 'sem_acesso';
            else
              v_usuario := v_partes[3];
            end if;
          end if;
        end if;
      else
        -- ---------------------------------------------------------------- v1: v1.<exp>.<usuario>.<hmac> (como na 0217)
        v_msg := lower(regexp_replace(coalesce(p_mandato, ''), '^ +| +$', '', 'g') collate "und-x-icu");
        if coalesce(array_length(v_partes, 1), 0) <> 4 or v_partes[1] <> 'v1'
           or v_partes[2] !~ '^[0-9]{1,12}$' or v_partes[3] !~ '^[0-9a-fA-F-]{8,64}$' or v_partes[4] !~ '^[0-9a-f]{64}$'
           -- 0222: mandato "v2|..." faria o v1 assinar uma mensagem que o v2 aceitaria; recusa antes do HMAC.
           or left(v_msg, 3) = 'v2|' then
          v_motivo := 'malformado';
        else
          v_msg := v_msg || '|' || v_partes[2] || '|' || v_partes[3];
          if hmac(convert_to(encode(hmac(convert_to(v_msg, 'UTF8'), convert_to(v_segredo, 'UTF8'), 'sha256'), 'hex'), 'UTF8'),
                  convert_to(v_segredo, 'UTF8'), 'sha256')
             is distinct from hmac(convert_to(v_partes[4], 'UTF8'), convert_to(v_segredo, 'UTF8'), 'sha256') then
            v_motivo := 'assinatura';
          elsif not (v_partes[2]::bigint * 1000 > floor(extract(epoch from p_agora) * 1000)::bigint) then
            v_motivo := 'expirado';
          else
            v_usuario := v_partes[3];
          end if;
        end if;
      end if;
    end if;
  end if;

  return query select
    v_motivo is null,
    v_caso,
    'envio'::text,
    v_motivo,
    case
      when v_motivo is null then null
      when v_motivo = 'sem_segredo' then 'Envio recusado: falta o segredo do envio no Vault do banco (nome n8n_intake_segredo). '
        || 'Nada foi gravado. É configuração do responsável pelo sistema.'
      when v_motivo = 'expirado' then 'Envio sem autorização válida: o token do envio expirou. Nada foi gravado. Reenvie pelo portal.'
      when v_motivo = 'caso_inexistente' then 'Envio recusado: o mandato deste envio não existe mais. Nada foi gravado. '
        || 'O envio nunca cria mandato: abra o mandato no portal e reenvie.'
      when v_motivo = 'caso_fechado' then 'Envio recusado: o mandato está fechado e não recebe documentos. Nada foi gravado. '
        || 'Peça a um Sócio para reabri-lo.'
      when v_motivo = 'sem_acesso' then 'Envio recusado: você não tem acesso de escrita a este mandato (só Sócio e Analista alocado enviam). '
        || 'Nada foi gravado. Peça a um Sócio para alocá-lo.'
      else 'Envio sem autorização válida. Nada foi gravado. Envie pelo portal, com o login de quem tem acesso ao mandato.'
    end,
    v_usuario;
end;
$$;

revoke all on function fn_conferir_envio(text, text, timestamptz) from public, anon, authenticated;
grant execute on function fn_conferir_envio(text, text, timestamptz) to service_role, postgres;

comment on function fn_conferir_envio(text, text, timestamptz) is
  '0222 (sobre a 0217): confere o token HMAC do envio. v1.<exp>.<usuario>.<hmac> (assinado sobre mandato_normalizado|exp|usuario; caso_id NULL; mandato "v2|..." é malformado) e v2.<exp>.<usuario>.<caso>.<hmac> (assinado sobre v2|caso|exp|usuario): v2 confere a assinatura ANTES de consultar caso e recusa caso_inexistente, caso_fechado e sem_acesso (usuário do token não é Sócio nem Analista alocado), devolvendo o caso_id também nas recusas pós-assinatura. Sempre UMA linha. motivo_recusa = sem_segredo|sem_token|malformado|assinatura|expirado|caso_inexistente|caso_fechado|sem_acesso. security definer; só service_role e postgres executam.';

-- -----------------------------------------------------------------------------
-- 3. O CASO DO ENVIO: falha fechada, e o nome divergente é auditado
-- -----------------------------------------------------------------------------
create function fn_caso_do_envio(p_caso uuid, p_nome_no_envio text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_nome text;
begin
  if p_caso is null then
    raise exception 'fn_caso_do_envio: envio sem caso (o envio nunca cria mandato)' using errcode = 'P0002';
  end if;
  select nome into v_nome from caso where id = p_caso;
  if not found then
    raise exception 'fn_caso_do_envio: o mandato % não existe (o envio nunca cria mandato)', p_caso using errcode = 'P0002';
  end if;
  if lower(btrim(v_nome)) is distinct from lower(btrim(coalesce(p_nome_no_envio, ''))) then
    insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
      values ('sistema:n8n', 'envio_nome_divergente', 'caso:' || p_caso,
              jsonb_build_object('nome_no_envio', p_nome_no_envio), jsonb_build_object('nome_atual', v_nome));
  end if;
  return p_caso;
end $$;
revoke all on function fn_caso_do_envio(uuid, text) from public, anon, authenticated;
grant execute on function fn_caso_do_envio(uuid, text) to service_role, postgres;
comment on function fn_caso_do_envio(uuid, text) is
  '0222: o mandato de um envio v2, pelo ID (não pelo nome). Exceção se o caso for nulo ou não existir — o envio nunca cria mandato. Se o nome atual divergir do nome que veio no envio (lower(btrim), como o upsert), grava 1 evento_auditoria envio_nome_divergente com os dois nomes e segue.';

-- -----------------------------------------------------------------------------
-- 4. A SONDA
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('envio_v2_etiqueta', '0222', 'corpo', 'fn_conferir_envio', '''v2|'' || v_partes[4]', null,
   'fn_conferir_envio sem o token v2 (etiqueta ''v2|''): o envio continua roteado por NOME, e renomear um mandato faz o envio seguinte criar um mandato novo e vazio com o nome antigo. Ausente = a 0222 não foi aplicada (ou uma migration posterior republicou a função da 0217).',
   'bloqueante', 1010),
  ('envio_v2_recusa_caso_fechado', '0222', 'corpo', 'fn_conferir_envio', 'caso_fechado', null,
   'fn_conferir_envio sem a recusa de mandato fechado: um mandato fechado (fechado_em não nulo) volta a receber documentos pelo envio.',
   'bloqueante', 1011),
  ('envio_v2_confere_acesso', '0222', 'corpo', 'fn_conferir_envio', 'fn_pode_escrever_caso_de(', null,
   'fn_conferir_envio sem a conferência de acesso: um token v2 de usuário desalocado do mandato (ou de Leitura) passa a ser aceito até expirar.',
   'bloqueante', 1012),
  ('envio_fn_caso_do_envio', '0222', 'funcao', 'fn_caso_do_envio', null, null,
   'Sem fn_caso_do_envio o n8n não consegue resolver o mandato pelo ID do token v2 nem registrar o nome divergente: o envio volta a criar mandato por nome.',
   'bloqueante', 1013),
  ('acesso_fn_pode_escrever_de', '0222', 'corpo', 'fn_pode_escrever_caso_de', 'm.papel = ''analista''', null,
   'A pergunta de escrita com o usuário por parâmetro (usada pelo envio v2 e, por delegação, por toda policy de escrita). O marcador é o papel que escreve só onde está alocado: sem ele Leitura passaria a escrever.',
   'bloqueante', 1014)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

-- O marcador da 0216 (`m.papel = 'analista'`) mudou de função: fn_pode_escrever_caso agora só delega.
update instalacao_requisito set marcador = 'fn_pode_escrever_caso_de(auth.uid(), p_caso)' where chave = 'acesso_fn_pode_escrever';

update instalacao_cobertura
   set ate_migration = '0222', revisado_em = current_date,
       observacao = 'A 0222 acrescenta o token de envio v2 (carrega o caso, não o nome): fn_conferir_envio ganha v2 e as recusas caso_inexistente, caso_fechado e sem_acesso; nascem fn_pode_escrever_caso_de e fn_caso_do_envio; 5 requisitos (envio_v2_etiqueta, envio_v2_recusa_caso_fechado, envio_v2_confere_acesso, envio_fn_caso_do_envio, acesso_fn_pode_escrever_de) provam em produção que foi aplicada.'
 where id = true;
