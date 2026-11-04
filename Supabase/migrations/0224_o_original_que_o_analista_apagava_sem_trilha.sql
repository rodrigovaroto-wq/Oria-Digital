-- =============================================================================
-- 0224 — O ORIGINAL QUE O ANALISTA APAGAVA SEM TRILHA: toda exclusão no Storage passa a ser AUDITADA e aparece no Histórico (D16)
-- (Cria 1 função de gatilho (SECURITY DEFINER), 1 gatilho AFTER DELETE em storage.objects, 1 view da sonda; REDEFINE fn_historico_do_caso
--  (a da 0215 inteira + 1 ramo); acrescenta 4 requisitos à sonda. Sem tabela, sem backfill, sem GRANT de tabela. NÃO muda quem pode apagar.)
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
--   ator         e-mail de quem apagou (auth.users, via auth.uid() do JWT que a API do Storage repassa); `usuario:<uuid>` se o usuário não tem
--                e-mail; `sistema:storage` quando é conexão de serviço (service_role/postgres, sem JWT: fn_conexao_de_servico, 0216);
--                `portal:desconhecido` se chegou como authenticated/anon sem `sub` (o mesmo texto que as demais funções gravam sem e-mail).
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
-- `documento_original_apagado`. O portal NÃO foi alterado: o mapa de tipos de portal/src/lib/historico-do-mandato.ts não conhece o tipo
-- novo e o mostra com o NOME CRU na categoria "Outros" (a regra do próprio arquivo: tipo desconhecido nunca some). Para o rótulo certo
-- ("Original apagado", categoria Documentos) falta UMA entrada em TIPOS desse arquivo e o assert correspondente em portal — outra fatia.
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
--   * RLS ligada em storage.objects; policy de DELETE: só `documentos_delete` [authenticated]. 9 objetos no bucket (prévia de 04/11/2026; 8 na primeira medição), todos com `<caso_id>/` na chave.
--   * evento_auditoria: colunas id, criado_em, ator, acao, entidade_ref, antes, depois; o authenticated tem INSERT (RLS de mandato, 0216);
--     o `postgres` (dono da função) tem BYPASSRLS = true.
--   NÃO MEDIDO (só uma exclusão de verdade prova): que a API do Storage repassa o `sub` do JWT em `request.jwt.claims` DENTRO da transação do
--     DELETE (o Storage faz `set_config('request.jwt.claims', ...)` antes de apagar; é o que faz a policy `documentos_delete` enxergar o usuário,
--     e a 0216 foi aplicada e a vistoria D3 passou por ela). Se não repassasse, o ator sairia `portal:desconhecido` e a suíte do banco não
--     perceberia. CONFERIR APÓS APLICAR: apagar um objeto de teste pela API e ler o evento (consulta no fim do README).
--
-- A SONDA (regra 7: estágio desligado parece limpo). O tipo `gatilho` do catálogo só resolve tabelas de `public` (to_regclass('public.'||...)), então o
-- gatilho de storage.objects NÃO cabe nele. Em vez de reescrever fn_instalacao_conferir inteira (a 0221 é um ramo de ~450 linhas), a view
-- `instalacao_sonda_gatilho_original_apagado` devolve UMA linha somente se o gatilho existe em storage.objects, está HABILITADO ('O' ou 'A'), é
-- AFTER DELETE por LINHA e chama exatamente fn_trg_auditar_original_apagado; o requisito é do tipo `comportamento` (>= 1 linha da view). Quatro requisitos:
-- a função, o corpo dela, o gatilho (via view) e o ramo novo do histórico.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/original_apagado.test.sql — 26 asserts, medidos em 04/11/2026 com `PGOPTIONS='-c d16.medindo=on'` (o assert vira
-- `raise warning` e CONTA; voltou para `raise exception` e o log inteiro foi lido atrás de `FALHOU:`), cada variante APLICADA ao banco migrado (conferido pela
-- linha final EXECUCOES=26) e a guarda desligada UMA por vez. Controle (migration intacta): 0 dos 26 asserts reprovam, antes e depois das variantes.
--   * SEM O GATILHO (drop trigger): 15 dos 26 asserts reprovam e o arquivo ABORTA na seção 8 (`disable trigger` de um gatilho que não existe), então os 2 últimos
--     asserts nem rodam — é o defeito original: o Analista apaga e nada é gravado;
--   * ator fixo `sistema:storage` (a função ignora o JWT): 4 dos 26 reprovam;
--   * mandato nunca resolvido da chave (tudo vira `storage:documentos/<chave>`): 11 dos 26 reprovam;
--   * sem o filtro de bucket (gatilho sem WHEN e função sem a defesa): 3 dos 26 reprovam;
--   * sem o nome original em `antes` (a busca em documento_versao desligada): 2 dos 26 reprovam;
--   * NÃO falha fechada (erro da gravação da trilha engolido): 1 dos 26 reprova;
--   * Histórico sem o ramo novo de fn_historico_do_caso: 4 dos 26 reprovam; sem a ação na lista fechada `ev` (o ramo existe, mas a lista não a deixa passar): 4 dos 26.
-- NÃO MEDIDO, e dito: (1) o `sub` do JWT chegando ao gatilho pela API REAL do Storage (o teste apaga como `authenticated` com JWT simulado; só uma exclusão em
-- produção prova que o ator sai com o e-mail e não `portal:desconhecido`); (2) o CREATE TRIGGER como `postgres` em storage.objects de produção (viabilidade
-- medida só por catálogo: privilégio TRIGGER presente; a migration aborta com mensagem explicando se o Supabase recusar); (3) `portal:desconhecido` (authenticated
-- sem `sub` com permissão de apagar não existe no desenho da 0216: a policy exige papel).
-- Efeito colateral medido nas suítes antigas: sonda_ve_gatilho.test.sql tinha a igualdade "todo gatilho do banco tem requisito `gatilho`" e passou a EXCLUIR o
-- schema storage (o gatilho novo é catalogado por view + `comportamento`); a cobertura do schema storage é afirmada aqui (assert "nenhum gatilho do schema storage
-- fica fora do catálogo da sonda").

-- =============================================================================

create function fn_trg_auditar_original_apagado() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid  uuid := auth.uid();
  v_ator text;
  v_caso uuid;
  v_ref  text;
  v_ver  record;
begin
  -- Defesa em profundidade: o gatilho já tem WHEN (old.bucket_id = 'documentos'); se alguém o recriar sem ele, outro bucket não vira evento.
  if old.bucket_id is distinct from 'documentos' then return null; end if;

  v_ator := case
              when v_uid is not null then coalesce((select u.email from auth.users u where u.id = v_uid), 'usuario:' || v_uid::text)
              when fn_conexao_de_servico() then 'sistema:storage'
              else 'portal:desconhecido'
            end;
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
                             'usuario_id', v_uid),
          null);
  return null;
end $$;

revoke all on function fn_trg_auditar_original_apagado() from public, anon, authenticated;

comment on function fn_trg_auditar_original_apagado() is
  '0224 (D16): gatilho AFTER DELETE de storage.objects (bucket documentos). Grava evento_auditoria `documento_original_apagado` com o ator (e-mail do JWT, ou sistema:storage), o mandato (caso:<id> da chave) e o que se perdeu (caminho, nome original, tamanho). Falha fechada: sem trilha, o DELETE volta.';

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
    -- o ator é o e-mail de quem apagou (ou `sistema:storage`, que a consulta final anula como nas demais ações do sistema).
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
  ('historico_mostra_original_apagado', '0224', 'corpo', 'fn_historico_do_caso', 'documento_original_apagado', null,
   'fn_historico_do_caso lê evento_auditoria por LISTA FECHADA de ações; sem esta ação na lista, o gatilho grava e o Histórico do mandato não mostra quem apagou o original.',
   'importante', 1033)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0224', revisado_em = current_date,
       observacao = 'A 0224 cria o gatilho de auditoria de exclusão em storage.objects (fora de public: catalogado por view + tipo comportamento) e o ramo novo de fn_historico_do_caso; 4 requisitos.'
 where id = true;
