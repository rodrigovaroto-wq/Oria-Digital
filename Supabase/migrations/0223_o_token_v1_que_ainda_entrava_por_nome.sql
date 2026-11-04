-- =============================================================================
-- 0223 — O TOKEN v1 QUE AINDA ENTRAVA: o envio por NOME é recusado, com motivo próprio (P3, fatia F5)
-- (Redefine fn_conferir_envio com a MESMA assinatura, as MESMAS 6 colunas, a MESMA ACL e SECURITY DEFINER; acrescenta 1 requisito à sonda.
--  Sem tabela, sem gatilho, sem backfill. Só se aplica depois de 30+ min sem NENHUM v1 aceito no n8n: ver DESENHO_P3_ROTEAR_POR_CASO_ID.md.)
--
-- O DEFEITO. A 0222 criou o token v2 (carrega o CASO), mas deixou o v1 aceito para não derrubar envio em voo. Enquanto o v1 for aceito, o
-- envio por nome segue aberto: um portal antigo (URL velha da Vercel com o segredo) ou um token emitido antes do deploy ainda assina
-- `mandato_normalizado|exp|usuario`, e o n8n o roteia por fn_upsert_caso(nome) — que CRIA mandato novo e vazio se o nome mudou.
--
-- A CAUSA. O ramo v1 de fn_conferir_envio existia só como ponte da transição. Passada a janela (portal v2 no ar, n8n republicado com
-- fn_caso_do_envio), ele é só a porta do defeito.
--
-- A CORREÇÃO. Todo token `v1.` de 4 partes é recusado com motivo_recusa = 'versao_antiga' e a mensagem "token de envio antigo; recarregue a
-- página do portal e envie de novo. Nada foi gravado." — ANTES do HMAC: recusar uma versão não precisa do segredo, e o v1 nunca mais calcula
-- assinatura (some a escada de normalização lower(... collate "und-x-icu") e a guarda `v2|`, que só existiam por causa do v1). Ordem:
-- sem_segredo > sem_token > (v1 de 4 partes: versao_antiga) | (v2: malformado > assinatura > expirado > caso_inexistente > caso_fechado >
-- sem_acesso) | qualquer outra forma: malformado. O v2 fica byte a byte como na 0222. Um v1 com outro número de partes continua malformado.
-- Efeito para o usuário: quem estava com a aba aberta num portal antigo vê a recusa explícita (regra 1/7: nunca um envio aceito calado pelo nome).
--
-- fn_upsert_caso NÃO é removida e continua com chamador legítimo: o passo 1 do portal ("Novo mandato", portal/src/app/casos/novo/actions.ts:25)
-- cria o mandato por ela, com o ator da tela. O que sai é o chamador do ENVIO (o nó Upsert Caso do n8n), que é a outra metade da F5 e não está aqui.
--
-- A SONDA. 1 requisito bloqueante, envio_recusa_versao_antiga: o corpo de fn_conferir_envio tem `v_motivo := 'versao_antiga'`. Ausente = a 0223
-- não foi aplicada e o v1 ainda entra. O requisito envio_v2_etiqueta (0222) segue valendo: o ramo v2 não mudou.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): conferir_envio.test.sql (65 asserts) e conferir_envio_v2.test.sql (65 asserts), medidos em 04/11/2026
-- com `PGOPTIONS=-cenvio.medindo=on` (o assert vira `raise warning` e CONTA), cada um sobre o banco migrado. Controle: 0 falhas nos dois.
-- Com o ramo v1 da 0222 de volta (conferido que a variante APLICOU antes de rodar): 32 de 65 reprovam em conferir_envio.test.sql e
-- 8 de 65 em conferir_envio_v2.test.sql. A mudança de sentido é a pretendida: 32 asserts de conferir_envio.test.sql e 7 de conferir_envio_v2.test.sql (39) que afirmavam "v1 aceito" (ou recusado
-- por assinatura/expirado/malformado do v1) passaram a afirmar `versao_antiga`; o resto (v2, sem_token, sem_segredo, EXECUTE, sonda) não mudou de sentido.
-- =============================================================================

create or replace function fn_conferir_envio(p_token text, p_mandato text, p_agora timestamptz default now())
returns table (envio_autorizado boolean, caso_id uuid, etapa_recusa text, motivo_recusa text,
               orcamento_mensagem text, usuario_id text)
language plpgsql
stable
security definer
set search_path = pg_catalog, extensions, public, pg_temp
as $$
declare
  c_ws     constant text := '[\u0009\u000a\u000b\u000c\u000d\u0020\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]';
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
      elsif v_partes[1] = 'v1' and coalesce(array_length(v_partes, 1), 0) = 4 then
        -- ---------------------------------------------------------------- v1: recusado ANTES do HMAC (a versão não precisa do segredo)
        v_motivo := 'versao_antiga';
      else
        v_motivo := 'malformado';
      end if;
    end if;
  end if;

  return query select
    v_motivo is null,
    -- O id só sai se o caso EXISTE (nulo para caso_inexistente e para qualquer recusa em que o caso foi apagado): execucao_falha.caso_id tem FK
    -- para caso(id), e o nó Registrar Recusa chama fn_registrar_falha_execucao($json.caso_id, ...). Medido: id inexistente = 23503
    -- execucao_falha_caso_id_fkey e a recusa se perde. A raiz está em fn_registrar_falha_execucao (seção 2a); isto é a defesa barata.
    (select c.id from caso c where c.id = v_caso),
    'envio'::text,
    v_motivo,
    case
      when v_motivo is null then null
      when v_motivo = 'sem_segredo' then 'Envio recusado: falta o segredo do envio no Vault do banco (nome n8n_intake_segredo). '
        || 'Nada foi gravado. É configuração do responsável pelo sistema.'
      when v_motivo = 'versao_antiga' then 'Envio recusado: token de envio antigo; recarregue a página do portal e envie de novo. Nada foi gravado.'
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
  '0223 (sobre a 0222): confere o token HMAC do envio. v2.<exp>.<usuario>.<caso>.<hmac> (assinado sobre v2|caso|exp|usuario): confere a assinatura ANTES de consultar caso e recusa caso_inexistente, caso_fechado e sem_acesso, devolvendo o caso_id também nas recusas pós-assinatura (só se o caso existir; senão NULL). v1.<exp>.<usuario>.<hmac> (4 partes) é recusado com versao_antiga ANTES do HMAC: o envio por nome não existe mais. Qualquer outra forma é malformado. Sempre UMA linha. motivo_recusa = sem_segredo|sem_token|malformado|versao_antiga|assinatura|expirado|caso_inexistente|caso_fechado|sem_acesso. security definer; só service_role e postgres executam.';

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('envio_recusa_versao_antiga', '0223', 'corpo', 'fn_conferir_envio', 'v_motivo := ''versao_antiga''', null,
   'fn_conferir_envio sem a recusa do token v1: o envio por NOME volta a ser aceito (portal antigo ou token emitido antes do deploy), e o nó do n8n que roteia pelo nome cria um mandato novo e vazio quando o mandato foi renomeado. Ausente = a 0223 não foi aplicada (ou uma migration posterior republicou a função da 0222).',
   'bloqueante', 1020)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0223', revisado_em = current_date,
       observacao = 'A 0223 recusa o token de envio v1 (por nome) com o motivo versao_antiga, antes do HMAC; o requisito envio_recusa_versao_antiga prova em produção que foi aplicada.'
 where id = true;
