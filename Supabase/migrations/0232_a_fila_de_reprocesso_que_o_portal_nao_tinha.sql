-- =============================================================================
-- 0232 — A FILA DE REPROCESSO QUE O PORTAL NÃO TINHA: quais documentos do mandato estão com falha de extração aberta, e se reenviar o original guardado de fato re-extrairia (P7b)
-- (Cria 1 função de leitura, fn_fila_de_reprocesso (SQL, stable, SECURITY INVOKER, somente leitura). Não toca fn_versao_extracao_concluida nem fn_registrar_documento. Acrescenta 4 requisitos à sonda.
--  Sem tabela, sem gatilho, sem backfill, sem GRANT de tabela. Reaplicável: create or replace + upsert dos requisitos.)
--
-- O DEFEITO. A 0230 (P7) fez o reenvio re-extrair só o que ainda não foi extraído (`fn_versao_extracao_concluida`). Mas o portal não tinha como LISTAR os documentos de um mandato com
-- `extracao_falhou` aberta, nem saber, antes de baixar o original do bucket `documentos` e reenviá-lo ao n8n, se o reenvio pagaria a extração ou seria reaproveitado em silêncio
-- (botão que "funciona" e não faz nada: estágio que não rodou com cara de estágio que rodou, regra 7). A pergunta "este reenvio re-extrai?" já tem dono; faltava a lista.
--
-- A CORREÇÃO (escada, degrau 2: a pergunta única já existe). fn_fila_de_reprocesso(p_caso_id) devolve UMA linha por documento do mandato com ao menos uma pendência
-- `tipo = 'extracao_falhou'` não resolvida, sobre a versão de MAIOR n_versao do documento. `reprocessavel` = há original no bucket do portal (arquivo_ref não vazio E
-- origem_arquivo = 'supabase_storage' E o objeto EXISTE em storage.objects, bucket `documentos`, name = arquivo_ref; arquivo do SharePoint o portal não baixa) E `not fn_versao_extracao_concluida(versao)` — a MESMA função que fn_registrar_documento consulta, então a fila e
-- o reenvio não podem divergir. `motivo_bloqueio`: 'sem_original' (vence), 'reaproveitaria' (a função diz concluída), ou nulo.
--
-- A FORMA DO REGISTRAR (correção da revisão independente). fn_registrar_documento reaproveita QUALQUER versão do mandato com o mesmo hash E o mesmo fingerprint que esteja concluída, não só a mais nova.
-- Perguntar só pela mais nova errava nos dois sentidos: (a) o mesmo arquivo registrado 2x antes de extrair, v1 com linha e v2 sem: a fila dizia "reprocessável" e o reenvio reaproveitava a v1 (nada extrai, a pendência
-- fica aberta); (b) a mais nova concluída com fingerprint antigo: a fila dizia "reaproveitaria" e o reenvio re-extrairia. Agora `reaproveitaria` = existe versão do caso com o hash da versão em questão (não nulo/vazio) e o
-- fingerprint VIGENTE, concluída por fn_versao_extracao_concluida: o mesmo teste do registrar. Hash vazio nunca é reaproveitado (o registrar não casa hash nulo).
-- FINGERPRINT VIGENTE = o da versão mais recente (criada_em, depois id) do MANDATO com fingerprint preenchido. LIMITE CONHECIDO: a fila não conhece o fingerprint que o n8n publicado mandará no reenvio; o do registro mais recente do
-- caso é o melhor proxy sem tabela nova (o n8n manda o mesmo a todo documento). Sobe se o fingerprint vigente passar a morar no banco; até lá, mandato sem nenhum registro recente com o fingerprint vigente pode ser classificado
-- pelo anterior, e o pior efeito é uma linha 'reaproveitaria' ou 'reprocessavel' errada, nunca um reprocesso que apaga dado (a fila só lê).
--
-- "ABERTA" = `estado <> 'resolvida'`, o mesmo predicado de fn_versao_extracao_concluida e de fn_linha_de_base_extracao (0229): em_correcao_interna, reenviada_ao_cliente, aceita_com_ressalva e
-- rejeitada também contam. Uma implementação só: se a fila usasse outro filtro, haveria documento que a função trata como falha aberta (reextrai) e a fila não mostra, ou o inverso.
-- Limite conhecido: `rejeitada` é estado terminal na 0106 e, aqui, ainda lista; sobe quando a função da pergunta única passar a distinguir (mexer nela muda o reenvio, outra fatia).
--
-- POR QUE O OBJETO E NÃO SÓ O arquivo_ref. Medido em PRODUÇÃO (somente leitura, 10/11/2026): 517 documentos com extracao_falhou aberta; os 517 têm arquivo_ref e origem supabase_storage, mas só 11 têm o objeto em
-- storage.objects (o defeito de jul a out/2026: o arquivo nunca foi guardado). Pelo critério só de arquivo_ref 447 seriam "reprocessáveis" e cerca de 436 falsamente: o botão baixaria um arquivo que não existe.
-- Sem o objeto o motivo é o mesmo, 'sem_original'. RLS (medido no teste): a policy documentos_read de storage.objects (0216) deixa o authenticated que lê o caso ver o objeto (sócio, ou fn_pode_ler_caso da chave
-- `<caso_id>/...`), então SECURITY INVOKER basta; quem não lê o caso nem chega à linha.
--
-- HOJE O CASO "FALHA COM LINHA" SAI COMO 'reaproveitaria' (a 0118/0230 mantêm reaproveitada a extração que gravou linha, mesmo com falha: teto conhecido). A P8 trata; a fila já o mostra em vez de esconder.
--
-- SECURITY INVOKER: a RLS do usuário decide o que ele vê (analista sem alocação no mandato recebe zero linhas, medido no teste). ACL como a 0230: PUBLIC e anon sem EXECUTE,
-- authenticated e service_role com.
--
-- SEM BACKFILL: é só leitura; o critério é lido na hora.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/fila_de_reprocesso.test.sql — 43 asserts (43 execuções), medidos em 10/11/2026 com o assert trocado por raise warning (`fila.medindo = on`), que CONTA; cada sabotagem aplicada como a migration inteira reaplicada sobre o banco montado pelo run.sh, conferido que ela aplicou e que o teste apareceu no log. Controle (migration intacta): 0 dos 43 reprovam. (i) o defeito da revisão independente, `reaproveitaria` perguntado só sobre a versão mais nova (como a primeira versão desta migration): 5 dos 43 reprovam (os dois arranjos novos, a ordem, o RLS e a sonda). (ii) fingerprint da própria versão em vez do vigente do mandato: 3 dos 43 (o arranjo (b), a ordem e a ordem interna). (iii) sem `not concluida` em reprocessavel: 5 dos 43 (a falha com linha e o arranjo (a) viram reprocessáveis, mais ordem e RLS). (iv) sem o filtro `estado <> 'resolvida'`: 6 dos 43. (v) sem o `exists` em storage.objects: 6 dos 43 (inclui o objeto de outro bucket e a sonda). (vi) sem `origem_arquivo = 'supabase_storage'`: 4 dos 43. (vii) versão de MENOR n_versao: 7 dos 43. (viii) SECURITY DEFINER: 2 dos 43. Os asserts de controle (caso de outro mandato, outro tipo de pendência, ACL, caso nulo, os reenvios reais) passam em todas as variantes: protegem o comportamento.
-- =============================================================================

begin;

create or replace function fn_fila_de_reprocesso(p_caso_id uuid)
returns table (
  documento_id         uuid,
  documento_versao_id  uuid,
  n_versao             integer,
  nome_original        text,
  arquivo_ref          text,
  tipo_taxonomia       text,
  falha_aberta_desde   timestamptz,
  falha_descricao      text,
  tem_linha            boolean,
  reprocessavel        boolean,
  motivo_bloqueio      text
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with falha as materialized (
    select pe.documento_id,
           min(pe.criada_em) as desde,
           (array_agg(pe.descricao order by pe.criada_em desc, pe.id desc))[1] as descricao
      from pendencia pe
     where pe.caso_id = p_caso_id
       and pe.tipo = 'extracao_falhou'
       and pe.estado <> 'resolvida'
       and pe.documento_id is not null
     group by pe.documento_id
  ),
  nova as (
    select distinct on (dv.documento_id) dv.*
      from documento_versao dv
      join falha f on f.documento_id = dv.documento_id
     order by dv.documento_id, dv.n_versao desc
  ),
  vigente as (
    select dv.fingerprint_extracao as fp
      from documento_versao dv
      join documento d on d.id = dv.documento_id
     where d.caso_id = p_caso_id
       and dv.fingerprint_extracao is not null and length(trim(dv.fingerprint_extracao)) > 0
     order by dv.criada_em desc, dv.id desc
     limit 1
  ),
  fila as (
    select d.id as doc_id, v.id as versao_id, v.n_versao as n, v.nome_original as nome, v.arquivo_ref as ref,
           d.tipo_taxonomia as tipo, f.desde, f.descricao,
           exists (select 1 from campo_extraido ce where ce.documento_versao_id = v.id) as linha,
           (v.arquivo_ref is not null and length(trim(v.arquivo_ref)) > 0
              and v.origem_arquivo = 'supabase_storage'
              and exists (select 1 from storage.objects o where o.bucket_id = 'documentos' and o.name = v.arquivo_ref)) as com_original,
           (v.hash is not null and length(trim(v.hash)) > 0
              and exists (select 1
                            from documento_versao v2
                            join documento d2 on d2.id = v2.documento_id
                           where d2.caso_id = p_caso_id
                             and v2.hash = v.hash
                             and v2.fingerprint_extracao = (select vg.fp from vigente vg)
                             and fn_versao_extracao_concluida(v2.id))) as concluida
      from nova v
      join documento d on d.id = v.documento_id and d.caso_id = p_caso_id
      join falha f on f.documento_id = d.id
  )
  select doc_id, versao_id, n, nome, ref, tipo, desde, descricao, linha,
         (com_original and not concluida),
         case when not com_original then 'sem_original'
              when concluida then 'reaproveitaria' end
    from fila
   order by (com_original and not concluida) desc, desde, doc_id
$$;

comment on function fn_fila_de_reprocesso(uuid) is
  '0232: a fila de reprocesso do mandato. Uma linha por documento com pendência extracao_falhou NÃO resolvida (estado <> resolvida, o predicado de fn_versao_extracao_concluida), sobre a versão de maior n_versao. falha_aberta_desde = min(criada_em) das pendências abertas; falha_descricao = a da mais recente. tem_linha = a versão tem campo_extraido. reprocessavel = arquivo_ref não vazio E origem_arquivo = supabase_storage E o objeto existe em storage.objects (bucket documentos, name = arquivo_ref; sem ele, 517 de 517 em produção tinham o ref e só 11 o arquivo) E NÃO existe versão do mandato com o mesmo hash e o fingerprint vigente (o da versão mais recente do mandato) concluída por fn_versao_extracao_concluida: a MESMA forma da pergunta de fn_registrar_documento (qualquer versão, não só a mais nova), então reenviar o original re-extrai de fato. motivo_bloqueio: sem_original (vence), reaproveitaria (hoje: falha COM linha, a P8 trata) ou nulo. Ordem: reprocessáveis primeiro, depois por falha_aberta_desde. SECURITY INVOKER: a RLS do usuário decide o que ele vê. Somente leitura.';

revoke all on function fn_fila_de_reprocesso(uuid) from public, anon;
grant execute on function fn_fila_de_reprocesso(uuid) to authenticated, service_role;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    execute 'grant execute on function fn_fila_de_reprocesso(uuid) to supabase_read_only_user';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- A SONDA. Marcadores em CÓDIGO (pg_get_functiondef traz comentário; o corpo da função não tem nenhum).
-- ---------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fila_de_reprocesso_funcao', '0232', 'funcao', 'fn_fila_de_reprocesso', null, null,
   'A lista que o portal mostra com o botão de reprocessar. Ausente = a 0232 não foi aplicada: o portal não sabe quais documentos estão com falha aberta nem se o reenvio re-extrairia.',
   'importante', 1070),
  ('fila_de_reprocesso_pergunta_unica', '0232', 'corpo', 'fn_fila_de_reprocesso', 'fn_versao_extracao_concluida(v2.id)', null,
   'reprocessavel pergunta a MESMA função que fn_registrar_documento, sobre QUALQUER versão do mandato com o mesmo hash e o fingerprint vigente. Corpo sem isto = a fila promete reprocesso que o reenvio reaproveita em silêncio (botão que não paga nada e não diz por quê).',
   'importante', 1071),
  ('fila_de_reprocesso_so_original_do_bucket', '0232', 'corpo', 'fn_fila_de_reprocesso', 'v.origem_arquivo = ''supabase_storage''', null,
   'Só o original guardado no bucket do portal é reprocessável. Corpo sem isto = documento do SharePoint aparece como reprocessável e o portal não tem o que baixar.',
   'importante', 1072),
  ('fila_de_reprocesso_exige_o_objeto_no_bucket', '0232', 'corpo', 'fn_fila_de_reprocesso', 'from storage.objects o where o.bucket_id = ''documentos''', null,
   'reprocessavel exige o objeto em storage.objects. Corpo sem isto = arquivo_ref preenchido sem arquivo guardado vira reprocessável (517 de 517 em produção tinham o ref, só 11 o objeto, 10/11/2026) e o botão baixa o que não existe.',
   'importante', 1073)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0232', revisado_em = current_date,
       observacao = 'A 0232 cria fn_fila_de_reprocesso (leitura, SECURITY INVOKER): a fila de documentos com extracao_falhou aberta e se o reenvio do original re-extrairia (pergunta única fn_versao_extracao_concluida); 4 requisitos novos.'
 where id = true;

commit;
