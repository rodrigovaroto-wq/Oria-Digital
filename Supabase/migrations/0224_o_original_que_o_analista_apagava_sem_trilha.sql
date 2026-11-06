-- =============================================================================
-- 0224 — O ORIGINAL QUE O ANALISTA APAGAVA SEM TRILHA: toda exclusão no Storage passa a ser AUDITADA e aparece no Histórico (D16)
-- (Cria 1 função de gatilho (SECURITY DEFINER), 1 gatilho AFTER DELETE em storage.objects, 4 views da sonda; recria a policy de INSERT de evento_auditoria; RESTRINGE a policy documentos_update a Sócio;
--  REDEFINE fn_historico_do_caso (a da 0215 inteira + 1 ramo); acrescenta 8 requisitos à sonda. Sem tabela, sem backfill, sem GRANT de tabela. NÃO muda quem pode
--  apagar. Reaplicável: create or replace na função e nas views, drop+create da policy, o gatilho só é criado se não existir, upsert dos requisitos.)
--
-- A DECISÃO DO DONO (D16, 04/11/2026): o Analista CONTINUA podendo apagar o original do cliente no Storage (é o desenho da 0216:
-- policy `documentos_delete` por `<caso_id>/` da chave), mas TODA exclusão é auditada — quem apagou, quando, qual arquivo, de qual
-- mandato — e aparece no Histórico do mandato. Achado de origem: `Arquitetura do Sistema/3 Estado e Execução/VISTORIA_P2.md`, D3
-- ("o Analista apaga o original sem trilha": com o JWT de Analista, `storage.from('documentos').remove([...])` apagou o objeto e nada
-- foi gravado; sem lixeira, o original do cliente é irreversível).
--
-- O DEFEITO. Quem apaga um objeto do bucket `documentos` não deixava rastro em lugar nenhum: o Storage não guarda histórico de
-- exclusão, `documento_versao.arquivo_ref` continuava apontando para a chave e `evento_auditoria` só conhece o que as funções da casa
-- gravam. O "Ver original" passava a dar "não pôde ser assinado" e ninguém sabia dizer quem, nem quando.
--
-- A CAUSA, medida (leitura de código, portal e migrations, 04/11/2026): o PORTAL NÃO APAGA original em lugar nenhum — o único uso de
-- `supabase.storage` em portal/src é `createSignedUrl` (portal/src/app/casos/[id]/documentos/[docId]/original/route.ts:59), e `.remove(`
-- não existe no portal. A exclusão só acontece por chamada DIRETA à API do Storage com o JWT do usuário (foi como a vistoria a fez),
-- autorizada pela policy `documentos_delete` da 0216 (Sócio ou quem escreve no mandato da chave). Por isso a trilha não pode morar
-- no portal (uma ação de tela): tem de morar no BANCO, no ponto por onde TODA exclusão passa — a linha de `storage.objects` sumindo.
--
-- A CORREÇÃO. Gatilho AFTER DELETE FOR EACH ROW em `storage.objects`, só para `bucket_id = 'documentos'` (cláusula WHEN: apagar objeto de
-- outro bucket nem chama a função), que grava em `evento_auditoria` UM evento por objeto apagado:
--   acao         documento_original_apagado
--   entidade_ref `caso:<id>` resolvido do primeiro segmento da chave (fn_caso_da_chave_do_storage, 0216 — a chave é `<caso_id>/<hash>.<ext>`).
--                Chave que NÃO começa com uuid de caso (objeto solto) vira `storage:documentos/<chave>`: a exclusão é gravada MESMO ASSIM
--                (regra 1: não some da trilha; só o Sócio a lê, porque o prefixo `storage:` não resolve para mandato — 0216).
--   ator         QUEM apagou, por ordem: (1) `auth.uid()` SÓ dentro de uma operação REST de exclusão (fora dela, auth.uid() não-nulo é SQL direto com claims à mão: `storage:sql_direto` com `antes.sub_alegado`); (2) o `sub` do JWT em
--                `request.headers` -> `authorization`, CONFERIDO em auth.users (é o caminho de TODA exclusão pela API do Storage: ver "A ETAPA 2" abaixo); em ambos o e-mail,
--                ou `usuario:<uuid>` se o usuário não tem e-mail; (3) `storage:chave_de_servico` se o JWT do cabeçalho é de `service_role` (o n8n nunca apaga: é uma pessoa com a chave; "Sistema" seria mentira); `storage:sql_direto` se NÃO há request.headers e a conexão é de serviço (SQL direto: a API sempre o define, ao menos '{}'; session_user em antes); (4) senão
--                `storage:nao_identificado`, com o motivo em `antes.ator_motivo` ('sem cabecalho authorization' | 'jwt malformado' | 'jwt sem sub' |
--                'sub inexistente em auth.users' (com `antes.sub_alegado`) | 'operacao <x>' | 'operacao ausente' | 'cabecalho ilegivel') e a origem em `antes.ator_origem`. NUNCA `sistema:*` para exclusão de objeto:
--                fn_historico_do_caso anula autor `^(sistema|n8n)` e a tela diria "Sistema" (regra 1: ausência apresentada como dado). Cabeçalho esquisito NÃO derruba o
--                DELETE (a falha fechada é para "não gravou a trilha", não para "não entendi o cabeçalho"): vira `storage:nao_identificado`.
--   antes        o que se perdeu: bucket, caminho (a chave inteira), arquivo (hash.ext), nome_original (de documento_versao.arquivo_ref, se
--                houver), documento_id, n_versao, tamanho_bytes (metadata->size do Storage) e usuario_id.
--   depois       null (o objeto não existe mais).
-- É SECURITY DEFINER com search_path fixo porque o `authenticated` NÃO consegue gravar evento_auditoria de mandato alheio nem a chave de
-- um objeto sem mandato (policy da 0216: a escrita exige poder escrever o mandato) — e a trilha de uma exclusão não pode depender de
-- o usuário ter permissão de gravá-la. EXECUTE revogado de public/anon/authenticated: é função de gatilho, ninguém a chama.
-- FALHA FECHADA: se a gravação da trilha falhar, o DELETE inteiro volta (AFTER ROW dentro da mesma transação) e a API devolve erro. Exclusão
-- sem trilha era o defeito; preferimos recusar a apagar calado.
--
-- Histórico do mandato (portal/src/app/casos/[id]/historico/page.tsx → fn_historico_do_caso): ele NÃO mostrava o evento — a função lê
-- `evento_auditoria` por LISTA FECHADA de ações (`ev`), e `documento_original_apagado` não estava nela. Esta migration REDEFINE fn_historico_do_caso
-- (a da 0215, inteira, com a MESMA assinatura, colunas, ACL, SECURITY INVOKER e STABLE) acrescentando a ação à lista e o ramo
-- `documento_original_apagado`. O portal traz o rótulo ("Original apagado", categoria Documentos) em
-- portal/src/lib/historico-do-mandato.ts e mostra `storage:nao_identificado` como "Não identificado (o Storage não informou quem apagou)", nunca como "Sistema".
--
-- VIABILIDADE EM PRODUÇÃO (medida SÓ LEITURA pela API de gerenciamento, 04/11/2026, begin read only/rollback):
--   * dono de storage.objects = supabase_storage_admin; o `postgres` NÃO é membro dele (pg_has_role MEMBER = false) e NÃO é superusuário,
--     mas tem o privilégio TRIGGER na tabela (ACL `postgres=a*r*w*d*D*x*t*m*/supabase_storage_admin`: com grant option). CREATE TRIGGER exige
--     só o privilégio TRIGGER, então esta migration CRIA o gatilho como `postgres`. O que o `postgres` NÃO pode: DROP/ALTER/DISABLE do gatilho
--     (exigem ser dono da tabela) — reverter a trilha é trocar o corpo da função (create or replace, que o postgres possui) ou entrar como
--     supabase_storage_admin pelo painel. A migration só CRIA o gatilho se ele não existir (reaplicar não tenta DROP).
--   * já há 2 gatilhos na tabela: `protect_objects_delete` (BEFORE DELETE de COMANDO; recusa DELETE por SQL direto com 42501 a menos que
--     `storage.allow_delete_query` seja 'true', que a API do Storage liga) e `update_objects_updated_at`. O AFTER DELETE FOR EACH ROW
--     convive: só dispara quando a API apaga. Consequência a saber: `delete from storage.objects` por SQL no painel continua recusado pela
--     plataforma (não é a 0224), e o que passa pela API é auditado.
--   * drop/create de policy em storage.objects como `postgres`: funciona NÃO por ser dono (não é), e sim porque `supautils.policy_grants` do Supabase inclui storage.objects (medido pelo revisor); a 0216 fez o mesmo e foi aplicada.
--   * RLS ligada em storage.objects; policy de DELETE: só `documentos_delete` [authenticated]. 9 objetos no bucket (prévia de 04/11/2026; 8 na primeira medição), todos com `<caso_id>/` na chave.
--   * evento_auditoria: colunas id, criado_em, ator, acao, entidade_ref, antes, depois; o authenticated tem INSERT (RLS de mandato, 0216);
--     o `postgres` (dono da função) tem BYPASSRLS = true.
--
-- A ETAPA 2 (o achado da revisão independente, lendo o código-fonte do supabase/storage). A exclusão pela API tem DUAS etapas: (1) `testPermission` avalia a RLS como o
-- usuário (authenticated) numa transação DESFEITA; (2) a exclusão EFETIVA roda com `asSuperUser()` (src/internal/database/pg-connection.ts:725-742): role=service_role e
-- `request.jwt.claim.sub=''`. No gatilho AFTER DELETE real, portanto, auth.uid() é NULO e fn_conexao_de_servico() é VERDADEIRO: a versão anterior desta migration gravaria
-- `sistema:storage` em TODA exclusão do Analista e o Histórico diria "Sistema" — e a suíte não via, porque apagava como authenticated direto (mecanismo suposto).
-- O que sobra é o cabeçalho: asSuperUser() repassa `this.headersPayload` (o JSON.stringify dos cabeçalhos do chamador; Node os baixa para minúsculas) e scope.ts:15-24 faz
-- `set_config('request.headers', $6, true)` na transação da exclusão; o JWT é lido de `request.headers.authorization` em src/http/plugins/jwt.ts:41 e JÁ foi validado pelo
-- Storage na entrada da requisição — por isso o gatilho só DECODIFICA o payload (base64url, com o padding que o JWT omite e `-`/`_`), sem revalidar a assinatura, e confere o
-- `sub` em auth.users. `apikey` (chave anon/service) vem em OUTRO cabeçalho e não é lido; se o `authorization` for a chave anon (sem sub) o motivo é 'jwt sem sub'.
--   NÃO MEDIDO, e dito: o formato REAL de `request.headers` na hospedagem do Supabase (a leitura foi do código-fonte; o Kong/gateway pode renomear ou omitir o cabeçalho).
--     Só uma exclusão de verdade prova. Se vier `storage:nao_identificado` com ator_motivo 'sem cabecalho authorization', é o gateway. CONFERIR APÓS APLICAR (README).
--
-- A SONDA (regra 7: estágio desligado parece limpo). O tipo `gatilho` do catálogo só resolve tabelas de `public` (to_regclass('public.'||...)), então o
-- gatilho de storage.objects NÃO cabe nele. Em vez de reescrever fn_instalacao_conferir inteira (a 0221 é um ramo de ~450 linhas), a view
-- `instalacao_sonda_gatilho_original_apagado` devolve UMA linha somente se o gatilho existe em storage.objects, está HABILITADO ('O' ou 'A'), é
-- AFTER DELETE por LINHA e chama exatamente fn_trg_auditar_original_apagado; o requisito é do tipo `comportamento` (>= 1 linha da view). Oito requisitos: a função, o corpo dela, a leitura
-- de request.headers (corpo), o gatilho (view), a policy de update só do Sócio (view), o bucket sem versionamento (view), o insert à mão da ação barrado em evento_auditoria (view) e o ramo novo do histórico.
--
-- O QUE A TRILHA GARANTE, e o que não: é NÃO FORJÁVEL por quem só tem JWT (o cabeçalho é lido só nas operações verificadas, o `sub` é conferido, a ação não se insere à mão pela API).
-- Quem tem ACESSO SQL ao banco forja (set_config de headers/operação, ou insert direto como postgres): fora do alcance de uma trilha dentro do próprio banco.
--
-- MOVER/SOBRESCREVER (decisão do dono): UPDATE em storage.objects não deixa trilha (move é UPDATE do `name`; upsert sobrescreve o conteúdo) e a 0216 deixava o Analista
-- alocado fazê-lo. A policy `documentos_update` passa a ser SÓ de Sócio (using e with check). Grep: portal e n8n não fazem update/move/upsert com JWT de usuário (n8n sobe com
-- x-upsert pela chave de serviço, que ignora RLS). Upload (INSERT) e exclusão do Analista alocado continuam.
-- VERSIONAMENTO DO BUCKET: hoje `versioning_status='DISABLED'` em produção. Ligado, a exclusão do usuário vira delete marker (INSERT/UPDATE, invisível ao gatilho de DELETE) e o
-- ciclo de vida apaga versões antigas com DELETE dias depois, atribuído ao sistema. O gatilho ignora `is_delete_marker`/`archived_at` (por to_jsonb: os NOMES dessas colunas
-- não foram conferidos em produção, e a ausência delas não derruba o gatilho) e a sonda EXIGE `DISABLED` (coluna ausente = acusa: nada foi medido).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/original_apagado.test.sql — 79 asserts (EXECUCOES=79 na linha final), medidos em 06/11/2026 com `PGOPTIONS='-c d16.medindo=on'`
-- (o assert vira `raise warning` e CONTA; voltou para `raise exception` e o log inteiro foi lido atrás de `FALHOU:`), cada variante APLICADA ao banco migrado (conferido pela linha
-- final EXECUCOES=79) e UMA guarda desligada por vez. Controle (migration intacta): 0 dos 79 reprovam, antes e depois das variantes.
--   * policy de INSERT de evento_auditoria no desenho da 0216 (forja pela porta da frente): 7 dos 79 reprovam; requisito `insert_sem_forja` tirado do catálogo: 3;
--   * `auth.uid()` atribuindo FORA da operação REST de exclusão (personificação em SQL): 1; `sub_alegado` sem gravar: 3; sub não-uuid perdido no handler: 1;
--   * a 0224 ANTERIOR (a função ignora request.headers: `sistema:storage` na etapa 2 da API): 36 — o defeito que a revisão achou (os asserts das seções 1, 2 e 4 agora passam pela REST real);
--   * LISTA DE PERMITIDOS por `storage.operation`: aceitar QUALQUER operação: 9; permitir só 'storage.object.delete' (sem delete_many): 4;
--     permitir a operação vazia (job de fila): 3; `request.path` gravado COM a query (X-Amz-Security-Token = JWT na trilha): 2;
--   * "Bearer" obrigatório (o Storage o aceita opcional): 2; chave de serviço gravada como `sistema:servico`: 3; SQL direto gravado como `sistema:sql`: 2; sem `session_user` em antes: 2;
--   * sem traduzir `-`/`_` do base64url: 2; sem o padding: 6; sem tratar cabeçalho esquisito (a exceção sobe e derruba o DELETE): 7;
--   * sem o ramo do JWT de service_role: 2; sem conferir o `sub` em auth.users: 2; nome do cabeçalho `authorization` sensível a caixa: 2;
--   * não identificado gravado como `sistema:storage` em vez de `storage:nao_identificado`: 21;
--   * sem ignorar delete marker/versão arquivada: 1; policy documentos_update no desenho da 0216: 6 (3 diretos: a sonda e "a Analista move"; o resto é cascata do objeto movido);
--   * requisito ator_do_cabecalho tirado do catálogo: 1; requisito update_so_socio: 3; requisito sem_versionamento: 4; view do versionamento sem o filtro DISABLED: 2;
--     o marcador do requisito ator_do_cabecalho é CÓDIGO (`current_setting('request.headers'`), não o texto solto: revertida a leitura e mantido o comentário, o requisito acusa (conferido);
--   * SEM O GATILHO (drop trigger): 48 reprovam e o arquivo ABORTA na seção 8 (`disable trigger` de um gatilho que não existe), então os asserts seguintes nem rodam;
--   * mandato nunca resolvido da chave (tudo vira `storage:documentos/<chave>`): 16; sem o filtro de bucket (gatilho sem WHEN e função sem a defesa): 3;
--     sem o nome original em `antes`: 2; NÃO falha fechada (erro da gravação da trilha engolido): 1;
--   * Histórico sem o ramo novo de fn_historico_do_caso: 5; sem a ação na lista fechada `ev`: 5.
-- O teste simula a REST real de exclusão com `storage.operation='storage.object.delete'` e o path '/object/documentos/<chave>' (teste_api_d16); operação e path vazios = job de fila.
-- NÃO MEDIDO, e dito: (0) o gatilho gravando com o dono SEM BYPASSRLS (o stub local roda como superusuário; em produção o `postgres` tem BYPASSRLS, medido só leitura), agora que a policy de INSERT exclui a ação; (1) o formato real de `request.headers` e o valor real de `storage.operation` na hospedagem (ver "A ETAPA 2"; os nomes 'storage.object.delete'/'storage.object.delete_many' são do código do Storage, não de uma exclusão real): a suíte os SIMULA a partir do código do Storage; só uma exclusão em produção prova;
-- (2) o CREATE TRIGGER e o drop/create de policy como `postgres` em storage.objects de produção (viabilidade por catálogo e pela 0216; a migration aborta com mensagem se o Supabase
-- recusar o gatilho); (3) os nomes `is_delete_marker`/`archived_at` e a coluna `versioning_status` no Storage de produção (o dono disse que `versioning_status` existe e é DISABLED).
-- Efeito colateral nas suítes antigas: sonda_ve_gatilho.test.sql EXCLUI o schema storage da igualdade de conjuntos (o gatilho novo é catalogado por view + `comportamento`).
-- Os gatilhos DA PLATAFORMA em storage.objects (protect_objects_delete, update_objects_updated_at...) ficam fora do catálogo de propósito: não são nossos.

-- =============================================================================

create or replace function fn_trg_auditar_original_apagado() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_old    jsonb := to_jsonb(old);   -- jsonb porque is_delete_marker/archived_at podem não existir na versão do Storage (campo ausente de record levanta erro)
  v_uid    uuid  := auth.uid();
  v_hdr    text  := nullif(current_setting('request.headers', true), '');
  v_ator   text;
  v_origem text;
  v_motivo text;
  v_uid_ev uuid;     -- quem o evento diz ter apagado (de auth.uid() ou do JWT do cabeçalho)
  v_auth   text;
  v_tok    text;
  v_partes text[];
  v_seg    text;
  v_pl     jsonb;
  v_sub    uuid;
  v_sub_al text;     -- o sub que o JWT ALEGA (evidência quando ele não existe em auth.users)
  v_op     text  := coalesce(current_setting('storage.operation', true), '');
  -- request.path SEM a query (a query do S3 pré-assinado traz X-Amz-Signature e X-Amz-Security-Token = um JWT: não vai para a trilha). É só perícia; nenhuma decisão o usa.
  v_path   text  := split_part(coalesce(current_setting('request.path', true), ''), '?', 1);
  v_email  text;
  v_caso   uuid;
  v_ref    text;
  v_ver    record;
begin
  -- Defesa em profundidade: o gatilho já tem WHEN (old.bucket_id = 'documentos'); se alguém o recriar sem ele, outro bucket não vira evento.
  if old.bucket_id is distinct from 'documentos' then return null; end if;
  -- Versionamento do bucket (hoje DESABILITADO, e a sonda exige isso): com ele ligado a "exclusão" do usuário vira delete marker (INSERT/UPDATE, que este
  -- gatilho não vê) e o ciclo de vida apagaria versões antigas com DELETE dias depois, em nome do sistema. Esse DELETE não é um ato de alguém: não vira evento.
  if v_old ->> 'is_delete_marker' = 'true' or v_old ->> 'archived_at' is not null then return null; end if;

  if v_uid is not null and v_op in ('storage.object.delete', 'storage.object.delete_many') then
    -- Caminho 1: o JWT chegou como o do usuário DENTRO de uma operação REST de exclusão (a lista de permitidos abaixo). Na API real auth.uid() só é não-nulo na sondagem
    -- DESFEITA do testPermission (etapa 1); no DELETE efetivo (etapa 2) é nulo e o ator vem do cabeçalho (caminho 2).
    v_uid_ev := v_uid;
    v_origem := 'auth.uid';
    v_ator   := coalesce((select u.email from auth.users u where u.id = v_uid), 'usuario:' || v_uid::text);
  elsif v_uid is not null then
    -- auth.uid() não-nulo FORA da operação REST de exclusão só acontece em SQL direto com claims setados à mão (ex.: personificação de papel no SQL Editor mais
    -- `set local storage.allow_delete_query='true'`). Gravar o nome da pessoa personificada como autor certo seria ausência apresentada como dado: é SQL direto, o sub
    -- é só ALEGADO (antes.sub_alegado) e session_user diz quem conectou.
    v_ator := 'storage:sql_direto'; v_origem := 'auth.uid_fora_da_rest'; v_sub_al := v_uid::text;
    v_motivo := 'auth.uid fora da operacao REST de exclusao';
  else
    -- Caminho 2: a exclusão EFETIVA da API do Storage roda como superusuário (asSuperUser, supabase/storage src/internal/database/pg-connection.ts:725-742):
    -- role=service_role e request.jwt.claim.sub vazio — auth.uid() é nulo e fn_conexao_de_servico() é VERDADEIRO para toda exclusão, inclusive a do Analista.
    -- Mas asSuperUser() repassa os cabeçalhos do chamador e scope.ts:15-24 faz set_config('request.headers', ...): o `authorization` (nome em minúsculas: o
    -- Node baixa a caixa; a busca abaixo ignora a caixa mesmo assim) traz o JWT do usuário que o Storage JÁ validou na entrada (src/http/plugins/jwt.ts:41),
    -- então aqui basta ler o `sub`, sem revalidar a assinatura. NUNCA se grava `sistema:*` para exclusão vinda da API: o Histórico anula esse autor e a tela diria
    -- "Sistema" (ausência apresentada como dado, regra 1). Um cabeçalho esquisito NÃO derruba o DELETE (falha fechada é para "não gravou a trilha", não para
    -- "não entendi o cabeçalho"): vira `storage:nao_identificado` com o motivo em antes.ator_motivo.
    begin
      if v_hdr is null then
        -- Sem request.headers: o DELETE não veio pela API do Storage (ela sempre o define, ao menos '{}'; os jobs chegam com '{}', não NULL). Apagar por SQL exige
        -- `set local storage.allow_delete_query='true'` (protect_objects_delete): é ato deliberado de PESSOA, não do sistema. `sistema:*` seria ausência apresentada como
        -- dado (regra 1): grava `storage:sql_direto` com session_user e o papel em antes (perícia).
        if fn_conexao_de_servico() then v_ator := 'storage:sql_direto'; v_origem := 'conexao_sql';
        else v_motivo := 'sem cabecalho authorization'; end if;
      elsif v_op not in ('storage.object.delete', 'storage.object.delete_many') then
        -- LISTA DE PERMITIDOS sobre valor que o SERVIDOR define. O `authorization` só vale quando o Storage o VERIFICOU, e isso só acontece nas rotas REST de exclusão, que estão
        -- sob registerJwtAuth sem allowInvalidJwt (src/http/routes/object/index.ts:28, deleteObject.ts:47 e deleteObjects.ts:71: operações 'storage.object.delete' e
        -- 'storage.object.delete_many', src/http/routes/operations.ts:19-20). Em qualquer outra rota (S3, que autentica por signatureV4 e NÃO registra o plugin jwt:
        -- s3/index.ts:242; jobs de fila; rota desconhecida) o db plugin repassa `request.headers` INTEIRO com um `authorization` que ninguém verificou (db.ts:72): quem tem a
        -- credencial de A poderia acrescentar um Bearer com o sub de B. `storage.operation` vem de `request.operation` = config da ROTA (log-request.ts:112; s3/index.ts:131),
        -- que o cliente não escreve, e asSuperUser() o repassa (`...this.options`; scope.ts:77-79). A versão anterior era lista de PROIBIDOS sobre `request.path` (a request.url
        -- CRUA do cliente) e o roteador normaliza antes de rotear (`/%73%33/...`, `/s%33/...` e a absolute-form `http://h/s3/...` chegam à rota S3): o path não decide nada aqui.
        -- Operação vazia (job de fila: emptyBucket / ObjectAdminDeleteAllBefore, headers '{}') = 'operacao ausente'.
        v_motivo := case when v_op = '' then 'operacao ausente' else 'operacao ' || v_op end;
      else
        select h.value into v_auth from jsonb_each_text(v_hdr::jsonb) h where lower(h.key) = 'authorization' limit 1;
        -- Espelha o Storage (src/http/plugins/jwt.ts:41: `(authorization || '').replace(/^Bearer\s+/i, '')`): o prefixo "Bearer" é OPCIONAL e a caixa livre.
        v_tok    := substring(v_auth from '(?i)^\s*(?:bearer\s+)?(\S+)\s*$');
        v_partes := string_to_array(v_tok, '.');
        if v_auth is null then
          v_motivo := 'sem cabecalho authorization';
        elsif v_tok is null or cardinality(v_partes) <> 3 then
          v_motivo := 'jwt malformado';
        else
          -- base64url -> base64: '-' e '_' viram '+' e '/', e o padding '=' que o JWT omite volta até fechar múltiplo de 4.
          v_seg := translate(v_partes[2], '-_', '+/');
          v_seg := v_seg || repeat('=', (4 - length(v_seg) % 4) % 4);
          v_pl  := convert_from(decode(v_seg, 'base64'), 'UTF8')::jsonb;
          if v_pl ->> 'role' = 'service_role' then
            -- A chave de serviço: o n8n NUNCA apaga do bucket (só POST com x-upsert, N8N/build-workflow.mjs:2755-2766); quem apaga com ela é uma PESSOA (script, painel).
            -- "Sistema" na tela seria ausência apresentada como dado (regra 1): grava `storage:chave_de_servico` e o portal diz que a pessoa não foi identificada.
            v_ator := 'storage:chave_de_servico'; v_origem := 'jwt_service_role';
          elsif nullif(v_pl ->> 'sub', '') is null then
            v_motivo := 'jwt sem sub';
          else
            v_sub_al := v_pl ->> 'sub';   -- antes do cast: um sub que não é uuid cai no handler abaixo e a evidência (texto) fica
            v_sub := v_sub_al::uuid;
            select u.email into v_email from auth.users u where u.id = v_sub;
            if not found then v_motivo := 'sub inexistente em auth.users';
            else v_uid_ev := v_sub; v_origem := 'cabecalho_jwt'; v_ator := coalesce(v_email, 'usuario:' || v_sub::text); end if;
          end if;
        end if;
      end if;
    exception when others then
      v_uid_ev := null; v_origem := null; v_ator := null;
      v_motivo := 'cabecalho ilegivel';
    end;
    if v_ator is null then v_ator := 'storage:nao_identificado'; v_origem := 'nao_identificado'; end if;
  end if;

  v_caso := fn_caso_da_chave_do_storage(old.name);
  v_ref  := case when v_caso is not null then 'caso:' || v_caso::text else 'storage:documentos/' || old.name end;

  -- Qual arquivo: o nome que o cliente deu vem de documento_versao (arquivo_ref = a chave). Sem versão apontando para a chave
  -- (objeto solto, ou o documento já foi apagado) o campo fica null — ausência dita, não inventada.
  select v.nome_original, v.documento_id, v.n_versao into v_ver
    from documento_versao v where v.arquivo_ref = old.name order by v.criada_em desc limit 1;

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
  values (v_ator, 'documento_original_apagado', v_ref,
          jsonb_build_object('bucket', old.bucket_id, 'caminho', old.name,
                             'arquivo', split_part(old.name, '/', 2),
                             'nome_original', v_ver.nome_original,
                             'documento_id', v_ver.documento_id,
                             'n_versao', v_ver.n_versao,
                             'tamanho_bytes', old.metadata -> 'size',
                             'usuario_id', v_uid_ev,
                             'ator_origem', v_origem,
                             'ator_motivo', v_motivo,
                             'sub_alegado', v_sub_al,
                             'storage_operation', v_op, 'request_path', v_path,
                             'sessao_usuario', session_user, 'papel_sessao', current_setting('role', true)),
          null);
  return null;
end $$;

revoke all on function fn_trg_auditar_original_apagado() from public, anon, authenticated;

comment on function fn_trg_auditar_original_apagado() is
  '0224 (D16): gatilho AFTER DELETE de storage.objects (bucket documentos). Grava evento_auditoria `documento_original_apagado` com o ator (e-mail do `sub` do JWT em request.headers, ou storage:nao_identificado + motivo), o mandato (caso:<id> da chave) e o que se perdeu (caminho, nome original, tamanho). Falha fechada: sem trilha, o DELETE volta.';

-- O gatilho. storage.objects é do supabase_storage_admin e o `postgres` tem só o privilégio TRIGGER nela (medido em produção em 04/11/2026): CREATE
-- TRIGGER basta; DROP/DISABLE exigiriam ser dono, por isso NÃO se faz `drop trigger` aqui (reaplicar não toca no que existe — o corpo da função já foi trocado acima).
do $$
begin
  if not exists (select 1 from pg_trigger where tgrelid = 'storage.objects'::regclass and tgname = 'trg_auditar_original_apagado' and not tgisinternal) then
    begin
      create trigger trg_auditar_original_apagado
        after delete on storage.objects
        for each row when (old.bucket_id = 'documentos')
        execute function public.fn_trg_auditar_original_apagado();
    exception when insufficient_privilege then
      raise exception '0224: o papel % não pôde criar o gatilho em storage.objects (dono: %). Crie-o como o dono, pelo painel do Supabase (SQL Editor): create trigger trg_auditar_original_apagado after delete on storage.objects for each row when (old.bucket_id = ''documentos'') execute function public.fn_trg_auditar_original_apagado();',
        current_user, (select relowner::regrole::text from pg_class where oid = 'storage.objects'::regclass)
        using errcode = '42501';
    end;
  end if;
end $$;

-- MOVER/SOBRESCREVER SÓ PARA SÓCIO (decisão do dono, D16). A exclusão é auditada pelo gatilho acima, mas UPDATE em storage.objects NÃO é: `move` da API do Storage
-- é UPDATE do `name` (o original some da chave antiga sem DELETE, e `documento_versao.arquivo_ref` passa a apontar para o vazio) e o upsert sobrescreve o conteúdo.
-- A 0216 deixava o Analista alocado fazer as duas coisas (documentos_update: ler no using, escrever no with check). Grep em portal/src e N8N/: ninguém faz update/move/upsert
-- com JWT de usuário (o portal só assina URL; o n8n sobe com x-upsert pela chave de serviço, que ignora RLS). Mesmo padrão da 0216 (drop + create, como `postgres`: permitido por `supautils.policy_grants`, não por posse da tabela).
drop policy if exists documentos_update on storage.objects;
create policy documentos_update on storage.objects for update to authenticated
  using (bucket_id = 'documentos' and (select fn_eh_socio()))
  with check (bucket_id = 'documentos' and (select fn_eh_socio()));

-- A TRILHA NÃO SE FORJA PELA PORTA DA FRENTE. O Histórico lê toda linha `evento_auditoria` com acao='documento_original_apagado', e a policy evento_auditoria_insert
-- (0216: with check fn_pode_escrever_evento(entidade_ref)) deixava o authenticated inserir essa linha com `ator` LIVRE: a Analista alocada em A fazia POST
-- /rest/v1/evento_auditoria {ator:'socio@...', acao:'documento_original_apagado', entidade_ref:'caso:<A>'} e o Histórico mostrava o Sócio apagando. Medido pelo revisor em
-- produção (só leitura): INSERT para authenticated, sem gatilho em evento_auditoria, `ator` sem default. Grep em portal/src, N8N e Supabase/migrations: NENHUM insert
-- legítimo dessa ação por authenticated (só o gatilho abaixo, SECURITY DEFINER do `postgres`, que tem BYPASSRLS em produção e ignora a policy). A policy é recriada com
-- `acao <> 'documento_original_apagado'`: NINGUÉM grava essa ação via authenticated, nem o Sócio (não há ato manual que a justifique; correção de trilha se faz por SQL).
-- LIMITE DITO: a fraqueza do `ator` livre vale para TODA ação de evento_auditoria desde a 0216 e fica para outra fatia (aqui só se protege a ação desta trilha).
drop policy if exists evento_auditoria_insert on evento_auditoria;
create policy evento_auditoria_insert on evento_auditoria for insert to authenticated
  with check (fn_pode_escrever_evento(entidade_ref) and acao <> 'documento_original_apagado');

-- A VIEW DA SONDA: uma linha somente se o gatilho existe, está habilitado, é AFTER DELETE por linha e chama a função certa.
-- tgtype: bit 1 = por linha, bit 2 = BEFORE (ausente = AFTER), bit 8 = DELETE, bit 4 = INSERT, bit 16 = UPDATE, bit 32 = TRUNCATE.
create or replace view instalacao_sonda_gatilho_original_apagado as
  select t.tgname::text as gatilho
    from pg_trigger t
   where t.tgrelid = 'storage.objects'::regclass
     and t.tgname = 'trg_auditar_original_apagado'
     and not t.tgisinternal
     and t.tgenabled in ('O', 'A')
     and (t.tgtype & 1) = 1 and (t.tgtype & 2) = 0 and (t.tgtype & 8) = 8
     and t.tgfoid = to_regproc('public.fn_trg_auditar_original_apagado');

comment on view instalacao_sonda_gatilho_original_apagado is
  'Sonda da 0224: uma linha = o gatilho de auditoria de exclusão existe em storage.objects, habilitado, AFTER DELETE por linha, chamando fn_trg_auditar_original_apagado. Zero linhas: a exclusão de original voltou a não deixar trilha.';

grant select on instalacao_sonda_gatilho_original_apagado to authenticated, service_role;  -- service_role: o requisito grant_views_service_role (0214) cobra toda view de public

-- A SONDA DA POLICY DE UPDATE: o tipo `policy` só resolve tabelas de `public`. Uma linha somente se documentos_update existe em storage.objects para UPDATE e AMBAS as
-- cláusulas (using e with check) exigem fn_eh_socio e nenhuma delas deixa passar por fn_pode_ (a 0216 usava fn_pode_ler/escrever_caso).
create or replace view instalacao_sonda_update_documentos_so_socio as
  select p.policyname::text as policy
    from pg_policies p
   where p.schemaname = 'storage' and p.tablename = 'objects' and p.policyname = 'documentos_update' and p.cmd = 'UPDATE'
     and 'authenticated' = any (p.roles)
     and p.qual ~ 'fn_eh_socio' and p.with_check ~ 'fn_eh_socio'
     and p.qual !~ 'fn_pode_' and p.with_check !~ 'fn_pode_';
comment on view instalacao_sonda_update_documentos_so_socio is
  'Sonda da 0224: uma linha = mover/sobrescrever original (UPDATE em storage.objects do bucket documentos) é só do Sócio. Zero linhas: a policy voltou ao desenho da 0216 (Analista alocado move o original sem trilha).';
grant select on instalacao_sonda_update_documentos_so_socio to authenticated, service_role;

-- A SONDA DA POLICY DE INSERT DE evento_auditoria: uma linha somente se ela existe para INSERT de authenticated e o with check exclui a ação da exclusão de original.
create or replace view instalacao_sonda_evento_sem_forja as
  select p.policyname::text as policy
    from pg_policies p
   where p.schemaname = 'public' and p.tablename = 'evento_auditoria' and p.policyname = 'evento_auditoria_insert' and p.cmd = 'INSERT'
     and 'authenticated' = any (p.roles)
     and p.with_check ~ 'documento_original_apagado';
comment on view instalacao_sonda_evento_sem_forja is
  'Sonda da 0224: uma linha = authenticated não insere à mão evento documento_original_apagado. Zero linhas: a policy voltou ao desenho da 0216 e qualquer Analista forja quem apagou o original.';
grant select on instalacao_sonda_evento_sem_forja to authenticated, service_role;

-- A SONDA DO VERSIONAMENTO: uma linha somente se o bucket `documentos` existe E tem `versioning_status = 'DISABLED'`. Regra 7: se a coluna não existe nesta versão do Storage
-- o requisito ACUSA (não há medição) em vez de passar vazio. to_jsonb(b) porque a coluna pode não existir e a view não pode quebrar por isso.
create or replace view instalacao_sonda_versionamento_documentos as
  select b.id::text as bucket
    from storage.buckets b
   where b.id = 'documentos' and to_jsonb(b) ->> 'versioning_status' = 'DISABLED';
comment on view instalacao_sonda_versionamento_documentos is
  'Sonda da 0224: uma linha = o bucket documentos tem versioning_status DISABLED. Zero linhas: versionamento ligado (o gatilho deixaria de ver a exclusão do usuário: ela viraria delete marker) ou a coluna/bucket não existe e nada foi medido.';
grant select on instalacao_sonda_versionamento_documentos to authenticated, service_role;

-- fn_historico_do_caso: a da 0215 INTEIRA (nenhuma outra migration a redefiniu: grep em Supabase/migrations) + a ação na lista `ev` e o ramo
-- `documento_original_apagado`. NÃO partir de outra: reemitir uma versão anterior APAGARIA ramos.
create or replace function fn_historico_do_caso(
  p_caso_id      uuid,
  p_limite       int         default 200,
  p_antes        timestamptz default null,
  p_antes_chave  text        default null
)
returns table (
  em           timestamptz,
  tipo         text,
  autor        text,
  resumo       text,
  documento_id uuid,
  referencia   jsonb,
  chave        text
)
language sql
stable
security invoker
as $$
  with recursive absorvidas(ref, absorvida) as (
    -- 0215 (revisão): `fn_fundir_entidade` APAGA a entidade absorvida e grava `entidade_fundida` com `entidade_ref` =
    -- a SOBREVIVENTE e o id da absorvida em `antes->>'entidade_id'` (medido no corpo da 0213). Os eventos de perímetro
    -- da absorvida (`entidade:<id da absorvida>`) continuam em `evento_auditoria`, mas sem esta CTE nenhuma referência
    -- do caso os alcançava. Recursiva porque a absorvida pode ter sido sobrevivente de uma fusão anterior (A em B, depois
    -- B em C): a partir das entidades que EXISTEM, desce pelas fusões. `union` (não `all`) por causa de ciclo.
    select a.entidade_ref, a.antes->>'entidade_id'
      from entidade e
      join evento_auditoria a on a.entidade_ref = 'entidade:' || e.id::text and a.acao = 'entidade_fundida'
     where e.caso_id = p_caso_id
    union
    select a.entidade_ref, a.antes->>'entidade_id'
      from absorvidas f
      join evento_auditoria a on a.entidade_ref = 'entidade:' || f.absorvida and a.acao = 'entidade_fundida'
     where f.absorvida is not null
  ),
  refs as materialized (
    select 'caso:' || p_caso_id::text as ref, null::uuid as documento_id
    union all
    select 'documento:' || d.id::text, d.id from documento d where d.caso_id = p_caso_id
    union all
    select 'documento_versao:' || v.id::text, d.id
      from documento_versao v join documento d on d.id = v.documento_id
     where d.caso_id = p_caso_id
    union all
    select 'pendencia:' || p.id::text, p.documento_id from pendencia p where p.caso_id = p_caso_id
    union all
    select 'entidade:' || e.id::text, null::uuid from entidade e where e.caso_id = p_caso_id
    union all
    select 'entidade:' || f.absorvida, null::uuid from absorvidas f where f.absorvida is not null
  ),
  ev as materialized (
    select a.*, r.documento_id as doc_id
      from refs r
      join evento_auditoria a on a.entidade_ref = r.ref
     where a.acao in ('extracao_aceita', 'documento_revisado', 'transcricao_humana', 'pendencia_decidida',
                      'modelagem_parametros', 'caso_criado', 'caso_fechado', 'caso_reaberto', 'reconferir_caso',
                      'perimetro_escopo_definido', 'perimetro_escopo_encerrado', 'entidade_papel_no_grupo_definido',
                      'entidade_forma_de_controle_definida', 'entidade_controlador_definido',
                      'entidade_participacao_definida', 'entidade_fundida',
                     'documento_original_apagado')
  ),
  eventos as (
    -- documento recebido
    select v.criada_em as em, 'documento_recebido'::text as tipo, null::text as autor,
           case when v.n_versao > 1
                then format('Nova versão (%s) do arquivo "%s" recebida', v.n_versao, coalesce(v.nome_original, '(sem nome)'))
                else format('Arquivo "%s" recebido', coalesce(v.nome_original, '(sem nome)')) end as resumo,
           d.id as documento_id,
           -- `autor_desconhecido`: a tabela `documento` não guarda quem enviou; autor NULL aqui é "não sei", e o NULL
           -- dos eventos `sistema:*` é "foi o sistema". A tela distingue pelo campo, em vez de chamar tudo de "sistema".
           jsonb_build_object('documento_versao_id', v.id, 'n_versao', v.n_versao, 'autor_desconhecido', true) as referencia,
           'versao:' || v.id::text as chave
      from documento d join documento_versao v on v.documento_id = d.id
     where d.caso_id = p_caso_id
       -- `fn_registrar_transcricao_humana` cria uma `documento_versao` NOVA copiando arquivo_ref/nome/hash: o arquivo não
       -- chegou de novo, quem o digitou é o evento `transcricao_humana`. Sem este filtro cada transcrição virava também
       -- um "Nova versão do arquivo recebida" que não aconteceu.
       and not exists (select 1 from ev t where t.acao = 'transcricao_humana'
                        and t.entidade_ref = 'documento_versao:' || v.id::text)

    union all
    select e.criado_em, 'extracao_aceita', e.ator,
           format('Extração aceita: %s campo(s)%s', coalesce(e.depois->>'n_campos_aceitos', '?'),
                  case when nullif(e.depois->>'motivo', '') is not null then ' — ' || (e.depois->>'motivo') else '' end),
           e.doc_id, jsonb_build_object('documento_versao_id', substring(e.entidade_ref from 18)),
           'evento:' || e.id::text
      from ev e where e.acao = 'extracao_aceita'

    union all
    -- ACEITE AUTOMÁTICO (dial N2/N3): `fn_registrar_campos_extraidos` grava SÓ a `decisao` (tipo aprovacao, autor
    -- `sistema:auto_aceite`, sem a chave `portao` e sem `evento_auditoria 'extracao_aceita'`, que é do aceite humano).
    -- Sem este ramo a extração aceita pelo sistema não entrava e o histórico sugeria que ninguém a aceitou.
    select x.criado_em, 'extracao_aceita', x.autor,
           format('Extração aceita automaticamente: %s campo(s)', coalesce(x.payload->>'n_auto_aceitos', '?')),
           nullif(x.payload->>'documento_id', '')::uuid,
           jsonb_build_object('documento_versao_id', x.payload->>'documento_versao_id', 'automatico', true,
                              'n_excluidas_pelo_limiar', x.payload->'n_excluidas_pelo_limiar'),
           'decisao:' || x.id::text
      from decisao x
     where x.caso_id = p_caso_id and x.tipo = 'aprovacao' and x.autor like 'sistema:auto_aceite%'

    union all
    select e.criado_em, 'documento_revisado', e.ator,
           case when e.antes->>'tipo' is distinct from e.depois->>'tipo'
                then format('Tipo do documento corrigido de "%s" para "%s"',
                            coalesce((select t.documento from taxonomia_tipo_documento t where t.codigo = e.antes->>'tipo'
                                       order by t.versao desc limit 1), e.antes->>'tipo', '(sem tipo)'),
                            coalesce((select t.documento from taxonomia_tipo_documento t where t.codigo = e.depois->>'tipo'
                                       order by t.versao desc limit 1), e.depois->>'tipo', '(sem tipo)'))
                else 'Classificação do documento confirmada' end
             || case when nullif(e.depois->>'motivo', '') is not null then ' — ' || (e.depois->>'motivo') else '' end,
           e.doc_id, jsonb_build_object('tipo_de', e.antes->>'tipo', 'tipo_para', e.depois->>'tipo'),
           'evento:' || e.id::text
      from ev e where e.acao = 'documento_revisado'

    union all
    select e.criado_em, 'transcricao_humana', e.ator,
           format('Transcrição manual: %s linha(s) digitadas a partir de arquivo ilegível', coalesce(e.depois->>'linhas', '?')),
           coalesce(e.doc_id, nullif(e.depois->>'documento_id', '')::uuid),
           jsonb_build_object('documento_versao_id', substring(e.entidade_ref from 18), 'n_versao', e.depois->'n_versao'),
           'evento:' || e.id::text
      from ev e where e.acao = 'transcricao_humana'

    union all
    select o.criado_em, 'classe_corrigida', o.autor,
           format('Classe contábil da linha "%s" definida como "%s"', c.chave,
                  coalesce((select k.nome from classe_contabil_catalogo k where k.codigo = o.classe_final), o.classe_final))
             || case when nullif(o.motivo, '') is not null then ' — ' || o.motivo else '' end,
           d.id, jsonb_build_object('campo_extraido_id', o.campo_extraido_id, 'classe_final', o.classe_final,
                                    'sugestao_original', o.sugestao_original),
           'override:' || o.id::text
      from documento d
      join documento_versao v on v.documento_id = d.id
      join campo_extraido c on c.documento_versao_id = v.id
      join campo_classe_override o on o.campo_extraido_id = c.id
     where d.caso_id = p_caso_id

    union all
    select e.criado_em, 'pendencia_decidida', e.ator,
           format('Pendência "%s": %s', coalesce(p.descricao, '(sem descrição)'), coalesce(e.depois->>'rotulo', 'decidida'))
             || case when nullif(e.depois->>'motivo', '') is not null then ' — ' || (e.depois->>'motivo') else '' end,
           p.documento_id, jsonb_build_object('pendencia_id', p.id, 'estado', e.depois->>'estado'),
           'evento:' || e.id::text
      from ev e join pendencia p on e.entidade_ref = 'pendencia:' || p.id::text
     where e.acao = 'pendencia_decidida'

    union all
    select q.criado_em, 'pergunta_' || case q.acao when 'enviada' then 'enviada' else 'descartada' end, q.autor,
           format('Pergunta "%s" %s', coalesce(pc.titulo, q.pergunta_codigo),
                  case q.acao when 'enviada' then 'enviada ao cliente' else 'descartada' end),
           null::uuid, jsonb_build_object('caso_pergunta_id', q.id, 'pergunta_codigo', q.pergunta_codigo,
                                          'entidade_id', q.entidade_id),
           'pergunta:' || q.id::text
      from caso_pergunta q left join pergunta_catalogo pc on pc.codigo = q.pergunta_codigo
     where q.caso_id = p_caso_id

    union all
    select x.criado_em,
           case when x.payload ? 'n_linhas' then 'premissa_aplicada_em_lote'
                when (x.payload->>'ativo') = 'false' then 'premissa_removida'
                else 'premissa_ativada' end,
           x.autor, x.motivo, null::uuid, x.payload, 'decisao:' || x.id::text
      from decisao x
     where x.caso_id = p_caso_id and x.tipo = 'override' and x.payload ? 'premissa'

    union all
    select g.atualizado_em, 'premissa_vinculada_a_linha', g.atualizado_por,
           format('%s linha(s) do modelo vinculada(s) a premissa', count(*)),
           null::uuid, jsonb_build_object('n_linhas', count(*), 'premissas', jsonb_agg(distinct g.premissa_codigo)),
           'vinculo:' || extract(epoch from g.atualizado_em)::text || ':' || coalesce(g.atualizado_por, '')
      from caso_linha_premissa g
     where g.caso_id = p_caso_id
       and g.premissa_codigo is not null
       and not exists (select 1 from decisao x
                        where x.caso_id = p_caso_id and x.tipo = 'override' and x.payload ? 'n_linhas'
                          and x.criado_em = g.atualizado_em and x.autor is not distinct from g.atualizado_por)
     group by g.atualizado_em, g.atualizado_por

    union all
    select e.criado_em, 'modelagem_definida', e.ator,
           format('Parâmetros da modelagem definidos (último exercício real %s, %s ano(s) projetados)',
                  coalesce(e.depois->>'ultimo_exercicio_real', 'não informado'), coalesce(e.depois->>'anos_projetados', '?')),
           null::uuid, e.depois, 'evento:' || e.id::text
      from ev e where e.acao = 'modelagem_parametros'

    union all
    -- "SALVA", não "preenchida por": a action do portal regrava `preenchido_por/em` de TODOS os campos a cada salvamento,
    -- então a coluna diz quem salvou por ÚLTIMO, não quem escreveu aquele valor. Um campo por linha, e o resumo diz
    -- "último salvamento" para ninguém ler o autor como autoria do conteúdo.
    select c.preenchido_em, 'apresentacao_salva', c.preenchido_por,
           format('Apresentação salva — último salvamento do campo "%s"%s', c.chave,
                  case when c.fonte is not null then ' (fonte: ' || c.fonte || ')' else '' end),
           null::uuid, jsonb_build_object('chave', c.chave), 'apresentacao:' || c.chave
      from caso_apresentacao_campo c where c.caso_id = p_caso_id

    union all
    select x.criado_em, 'caso_aprovado', x.autor,
           'Caso aprovado no Portão 2' || case when nullif(x.motivo, '') is not null and x.motivo <> 'Portão 2: caso aprovado'
                                               then ' — ' || x.motivo else '' end,
           null::uuid, jsonb_build_object('decisao_id', x.id), 'decisao:' || x.id::text
      from decisao x
     where x.caso_id = p_caso_id and x.tipo = 'aprovacao' and x.payload ? 'portao'

    union all
    select e.criado_em, e.acao, e.ator,
           case e.acao
             when 'caso_criado'     then 'Mandato criado'
             when 'caso_fechado'    then 'Mandato fechado'
                                         || case when nullif(e.depois->>'motivo', '') is not null then ' — ' || (e.depois->>'motivo') else '' end
             when 'caso_reaberto'   then 'Mandato reaberto'
             else format('Caso reconferido: %s pendência(s) aberta(s) antes, %s depois',
                         coalesce(e.antes->>'pendencias_abertas', '?'), coalesce(e.depois->>'pendencias_abertas', '?'))
           end,
           null::uuid, '{}'::jsonb, 'evento:' || e.id::text
      from ev e where e.acao in ('caso_criado', 'caso_fechado', 'caso_reaberto', 'reconferir_caso')

    union all
    select e.criado_em, 'perimetro_alterado', e.ator,
           case when e.acao = 'entidade_fundida'
                then format('Entidade "%s" fundida em "%s"', coalesce(e.antes->>'razao_social', '(sem nome)'),
                            coalesce(e.depois->>'razao_social', '(sem nome)'))
                else format('%s — %s',
                  case e.acao
                    when 'perimetro_escopo_definido'          then 'Escopo do perímetro definido'
                    when 'perimetro_escopo_encerrado'         then 'Escopo do perímetro encerrado'
                    when 'entidade_papel_no_grupo_definido'   then 'Papel no grupo definido'
                    when 'entidade_forma_de_controle_definida' then 'Forma de controle definida'
                    when 'entidade_controlador_definido'      then 'Controlador definido'
                    when 'entidade_participacao_definida'     then 'Participação societária definida'
                    else 'Entidades fundidas' end,
                  -- a entidade absorvida já não existe: o nome dela sobrou no evento da fusão (`antes->>'razao_social'`)
                  coalesce(en.razao_social,
                           (select f.antes->>'razao_social' from ev f
                             where f.acao = 'entidade_fundida' and f.antes->>'entidade_id' = substring(e.entidade_ref from 10)
                             limit 1),
                           '(entidade removida)')) end,
           null::uuid, jsonb_build_object('acao', e.acao, 'entidade_id', substring(e.entidade_ref from 10)),
           'evento:' || e.id::text
      from ev e left join entidade en on e.entidade_ref = 'entidade:' || en.id::text
     where e.acao in ('perimetro_escopo_definido', 'perimetro_escopo_encerrado', 'entidade_papel_no_grupo_definido',
                      'entidade_forma_de_controle_definida', 'entidade_controlador_definido',
                      'entidade_participacao_definida', 'entidade_fundida')

    union all
    -- 0224 (D16): o original do cliente apagado do Storage. O gatilho de storage.objects grava `caso:<id>` + o que se perdeu em `antes`;
    -- o ator é o e-mail de quem apagou; `storage:nao_identificado` aparece como está; os `storage:*` aparecem como estão (o portal os rotula; nenhum vira "Sistema").
    select e.criado_em, 'documento_original_apagado', e.ator,
           format('Original apagado do armazenamento: "%s"%s',
                  coalesce(e.antes->>'nome_original', nullif(e.antes->>'arquivo', ''), '(sem nome)'),
                  case when e.antes->>'tamanho_bytes' ~ '^[0-9]+$'
                       then format(' (%s)', pg_size_pretty((e.antes->>'tamanho_bytes')::bigint)) else '' end),
           (select d.id from documento d where d.caso_id = p_caso_id and d.id::text = e.antes->>'documento_id'),
           jsonb_build_object('caminho', e.antes->>'caminho', 'arquivo', e.antes->>'arquivo',
                              'documento_id', e.antes->>'documento_id', 'n_versao', e.antes->>'n_versao'),
           'evento:' || e.id::text
      from ev e where e.acao = 'documento_original_apagado'
  )
  select h.em, h.tipo,
         case when h.autor ~ '^(sistema|n8n)(:|$)' then null else h.autor end,
         h.resumo, h.documento_id, h.referencia, h.chave
    from eventos h
   where h.em is not null
     -- cursor composto: estritamente anterior em `em`, OU no mesmo instante com `chave` menor. Sem `p_antes_chave` o
     -- comportamento é o de antes (estritamente anterior), para quem só tem o instante.
     and (p_antes is null
          or h.em < p_antes
          or (p_antes_chave is not null and h.em = p_antes and h.chave collate "C" < p_antes_chave collate "C"))
   order by h.em desc, h.chave collate "C" desc
   limit least(greatest(coalesce(p_limite, 200), 1), 1000)
$$;

comment on function fn_historico_do_caso(uuid, int, timestamptz, text) is
  '0224 (sobre a 0215): linha do tempo do mandato (quem fez o quê e quando), da mais nova para a mais velha, montada do que já é gravado. Acrescenta o tipo documento_original_apagado (o original apagado do Storage, com ator e nome do arquivo). Cursor composto (p_antes + p_antes_chave); autor NULL = sistema.';

grant execute on function fn_historico_do_caso(uuid, int, timestamptz, text) to authenticated, service_role;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('original_apagado_funcao', '0224', 'funcao', 'fn_trg_auditar_original_apagado', null, null,
   'A função do gatilho que audita a exclusão de original no Storage. Ausente = a 0224 não foi aplicada e o Analista apaga o original do cliente sem trilha (VISTORIA_P2 D3).',
   'bloqueante', 1030),
  ('original_apagado_corpo', '0224', 'corpo', 'fn_trg_auditar_original_apagado', 'documento_original_apagado', null,
   'O corpo que grava o evento. O marcador pega uma reedição futura da função que mantenha o nome e perca a gravação (a trilha some sem erro).',
   'bloqueante', 1031),
  ('original_apagado_gatilho', '0224', 'comportamento', 'instalacao_sonda_gatilho_original_apagado', null, 1,
   'O gatilho em storage.objects (fora de public, onde o tipo `gatilho` não enxerga): a view só tem linha se ele existe, está habilitado, é AFTER DELETE por linha e chama a função certa. Zero linhas = a exclusão de original voltou a não deixar trilha; a função, sozinha, sobrevive a drop trigger e a disable trigger. O postgres não é dono de storage.objects: recriar o gatilho exige o SQL da 0224 (ou o dono pelo painel).',
   'bloqueante', 1032),
  ('original_apagado_ator_do_cabecalho', '0224', 'corpo', 'fn_trg_auditar_original_apagado', 'current_setting(''request.headers''', null,
   'A exclusão efetiva da API do Storage roda como service_role sem sub: só o JWT de request.headers diz quem apagou. Sem esta leitura toda exclusão do Analista sai sem autor (ou "Sistema").',
   'bloqueante', 1034),
  ('original_apagado_update_so_socio', '0224', 'comportamento', 'instalacao_sonda_update_documentos_so_socio', null, 1,
   'Mover/sobrescrever original (UPDATE em storage.objects, bucket documentos) é só do Sócio: UPDATE não deixa trilha. Zero linhas = a policy documentos_update voltou ao desenho da 0216, em que o Analista alocado move o original sem evento.',
   'bloqueante', 1035),
  ('original_apagado_sem_versionamento', '0224', 'comportamento', 'instalacao_sonda_versionamento_documentos', null, 1,
   'O bucket documentos precisa de versioning_status DISABLED: ligado, a exclusão do usuário vira delete marker (o gatilho de DELETE não a vê) e o ciclo de vida apaga versões antigas com DELETE atribuído ao sistema. Zero linhas também quando a coluna não existe: nada foi medido.',
   'bloqueante', 1036),
  ('original_apagado_insert_sem_forja', '0224', 'comportamento', 'instalacao_sonda_evento_sem_forja', null, 1,
   'A policy de INSERT de evento_auditoria precisa excluir a ação documento_original_apagado: sem isso um Analista alocado insere a linha com `ator` livre (o Sócio, por exemplo) e o Histórico mostra quem NÃO apagou. Zero linhas = a trilha de exclusão voltou a ser forjável pela porta da frente.',
   'bloqueante', 1037),
  ('historico_mostra_original_apagado', '0224', 'corpo', 'fn_historico_do_caso', 'documento_original_apagado', null,
   'fn_historico_do_caso lê evento_auditoria por LISTA FECHADA de ações; sem esta ação na lista, o gatilho grava e o Histórico do mandato não mostra quem apagou o original.',
   'importante', 1033)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0224', revisado_em = current_date,
       observacao = 'A 0224 cria o gatilho de auditoria de exclusão em storage.objects (fora de public: catalogado por view + tipo comportamento), restringe documentos_update a Sócio, fecha o insert à mão da ação em evento_auditoria e acrescenta o ramo novo de fn_historico_do_caso; 8 requisitos.'
 where id = true;
