-- =============================================================================
-- 0301 — O KIT QUE LEVAVA 4 SEGUNDOS PARA ABRIR: fn_kit_do_caso perguntava "a leitura desta versão concluiu?" para TODAS as versões do banco, uma vez por documento do mandato
--        (reemite fn_kit_do_caso da 0300: mesma assinatura, mesmas 14 colunas, mesma resposta, mesma ACL; nenhuma tabela, índice ou outra função muda)
--
-- O DEFEITO. O portal passou a ler fn_kit_do_caso (commit 40ab600) e a visão geral do mandato foi de 1,5-2,2 s para 6,5-7,9 s. Medido pelo portal, com a
-- sessão de um usuário via PostgREST: 4,3-5,1 s no mandato ee6251e6 (9 documentos); 5,9 s e 2 estouros de statement_timeout (8,9 s) em 3 chamadas no mandato
-- 5469db1d (115 documentos). Uma ida trivial leva ~0,26 s.
--
-- A CAUSA, MEDIDA EM PRODUÇÃO em 13/11/2026 (API de gerenciamento, só leitura; a função é `stable` e não escreve, então o EXPLAIN ANALYZE a executa sem efeito):
--   * como `postgres` (sem RLS) a mesma chamada leva 44 ms; como `authenticated` com o JWT de um sócio, 3.232 ms no mandato ee6251e6 (143.783 buffers contra
--     3.607). O custo não acompanha os documentos do mandato porque é a RLS que o muda de natureza.
--   * o nó caro é o CTE `lido`: duas subconsultas `exists (select 1 from documento_versao dv where dv.documento_id = s.doc and fn_versao_extracao_concluida(dv.id))`
--     (os dois ramos "leitura concluída" do estado sem linha). Sem RLS o planejador as roda como índice por documento. COM a RLS (documento_versao_read) o filtro
--     da política vem antes e a subconsulta vira um SubPlan HASHED: um Seq Scan em documento_versao INTEIRA (2.247 versões, de TODOS os mandatos) que chama
--     fn_versao_extracao_concluida em cada uma — 0,77 ms por versão, 1.679 chamadas por subconsulta —, uma vez por subconsulta: 1.731 ms + 1.232 ms = 2.963 dos
--     3.182 ms da execução (EXPLAIN ANALYZE, BUFFERS, como authenticated). O hash é montado uma vez, não por documento; por isso a conta não cresce com os 115
--     documentos do outro mandato (lá o resto, ~0,35 s, é o serve-como do COMBINADO por documento), e por isso o custo cresce com o BANCO inteiro, não com o mandato.
--   * o resto da função, medido isolado como authenticated: documento 2 ms, pendencia 2 ms, evento 0,7 ms, fn_documento_serve_como por documento 4-8 ms, serve 16 ms.
--
-- A CORREÇÃO. O CTE novo `concluida` (MATERIALIZED) pergunta fn_versao_extracao_concluida SÓ das versões dos documentos do mandato que ainda não têm versão com
-- linha (`s.v is null`, os únicos que a pergunta decide), por um LATERAL. Os dois ramos do `lido`
-- passam a consultar esse CTE. Mesma pergunta, mesmo filtro por documento: a resposta é a mesma. `MATERIALIZED` não é enfeite: sem ele o Postgres
-- poderia inlinar o CTE e voltar a decidir o plano por conta própria. O `offset 0` no LATERAL foi medido e NÃO é necessário (a versão sem ele deu 0,034 s no
-- mandato de 9 documentos, em produção): o que corrige é perguntar num CTE próprio, não dentro do `exists` do CASE; por isso não está lá.
--   Medido em PRODUÇÃO, numa transação com ROLLBACK, a função nova com outro nome contra a 0300, como authenticated (sócio), nos DOIS mandatos:
--     ee6251e6 (9 documentos):    3,09 s  ->  0,03 s   (duas rodadas; 3,09 s e 3,07 s  ->  0,030 s e 0,030 s)
--     5469db1d (115 documentos):  4,7 s / 4,3 s  ->  0,37 s / 0,41 s  (o resto é o serve-como do COMBINADO por documento; um atalho por tipo foi medido e não ganhou nada)
--   e as 8 linhas devolvidas, comparadas com to_jsonb linha a linha, IGUAIS nos dois. O rollback não deixou objeto algum (pg_proc sem fn_kit_do_caso_novo).
--
-- O QUE NÃO MUDA. Os estados, os motivos, as 14 colunas, `security invoker`, `stable`, o search_path, os grants, o COMMENT e os 9 requisitos da 0300 (a sonda
-- lê o corpo: todos os marcadores da 0300 continuam no corpo novo). Teto declarado: o serve-como do COMBINADO ainda roda uma vez por documento do mandato
-- (115 documentos = ~0,35 s); se o mandato passar de ~1.000 documentos ele volta a pesar, e a correção é calcular o COMBINADO em lote (a 0276 já tem a forma).
--
-- A SONDA: 1 requisito novo (ordem 1389, severidade importante) e `instalacao_cobertura` em 0301.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/o_kit_que_levava_quatro_segundos_para_abrir.test.sql — 22 asserts
--   (medido: 36 execuções, porque o laço de mandatos e o de E2 repetem asserts; controle com a migration intacta: 0 reprovam; reconferido com Supabase/test/medicao-denominador.test.mjs).
--   Cada correção desligada UMA por vez, com o teste em `raise warning` (voltou para `raise exception`; log lido atrás de FALHOU), 13/11/2026, no banco montado:
--   * a fn_kit_do_caso volta ao corpo da 0300 (o defeito): 2 dos 22 asserts reprovam (3 execuções): o E2 nos dois mandatos (944 e 472 chamadas de
--     fn_versao_extracao_concluida contra 9 e 3 versões do mandato, num banco de 472 versões) e o assert da sonda, que acusa o corpo sem o CTE `concluida`.
--   * o CTE `concluida` nunca conclui nada (resposta errada: `where false`): 4 dos 22 asserts reprovam (4 execuções): o do arranjo A, que deixa de mostrar os estados, e o E1 do
--     mandato A nos três papéis (superusuário, sócio, analista).
--   * medido e DESCARTADO como correção: `offset 0` no LATERAL. Sem ele o E2 continua verde e produção deu 0,034 s: o que corrige é o CTE próprio, e o assert da sonda o guarda.
--   Teto do teste: o E2 conta chamadas, não segundos; um plano que volte a ser lento por outra razão (por exemplo o COMBINADO por documento) não o reprova.

begin;

create or replace function fn_kit_do_caso(p_caso uuid)
returns table (
  tipo text,
  estado text,
  motivo text,
  documentos uuid[],
  docs_por_estado jsonb,
  conferido_por text,
  conferido_em timestamptz,
  empresas_total int,
  empresas_com_documento int,
  empresas_atendidas int,
  documentos_sem_empresa int,
  aguardando_desde timestamptz,
  conferencia_em timestamptz,
  documentos_depois_da_conferencia int
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with kit as materialized (
    -- "N de M empresas" só faz sentido onde o item é cobrado por empresa (granularidade entidade e entidade_periodo): MUTUOS e FAT_INTRAGRUPO
    -- são do caso, COMBINADO é do período — um documento só os cumpre, e "1 de 8" para item completo seria número falso.
    select t.codigo, t.granularidade::text in ('entidade', 'entidade_periodo') as por_empresa
      from taxonomia_tipo_documento t where t.obrigatoriedade = 'obrigatorio'
  ),
  -- A pergunta "este documento serve como o tipo" é a de fn_documento_serve_como (0157), a mesma do passo 1 da conferência.
  serve as materialized (
    select k.codigo, d.id as doc, d.tipo_taxonomia as tipo_doc, d.entidade_id, d.criado_em, fn_versao_com_extracao(d.id) as v,
           exists (select 1 from entidade e
                    where e.id = d.entidade_id and e.papel_no_grupo is distinct from 'fora_do_perimetro') as no_perimetro
      from kit k
      join documento d on d.caso_id = p_caso and fn_documento_serve_como(d.id, k.codigo)
  ),
  -- A pergunta "a leitura desta versão concluiu" (fn_versao_extracao_concluida, cara: 0,77 ms por versão sob a RLS) só interessa às versões dos documentos
  -- DESTE mandato sem versão com linha. Como `exists (... where dv.documento_id = s.doc and fn_...)` a RLS a transformava em hash sobre documento_versao
  -- INTEIRA (2.247 versões, 1.679 chamadas, duas vezes: 2,96 de 3,18 s medidos em produção, 13/11/2026); o CTE separado, materializado, calcula a pergunta uma vez por versão do mandato.
  concluida as materialized (
    select distinct s.doc
      from serve s
      cross join lateral (select dv.id from documento_versao dv where dv.documento_id = s.doc) v
     where s.v is null and fn_versao_extracao_concluida(v.id)
  ),
  lido as materialized (
    select s.*,
           case
             -- sem versão com linha: ou a leitura já acabou sem dado, ou o sistema já declarou que não vai acontecer, ou ainda não acabou
             when s.v is null then
               case
                 -- o sistema JÁ disse que a leitura não houve: fn_conferir_lote abre documento_nao_extraido (a extração nunca foi chamada),
                 -- e o diagnóstico abre arquivo_ilegivel/arquivo_corrompido. Esperar por uma leitura que ele já declarou perdida é mentir "aguardando".
                 when exists (select 1 from pendencia pe
                               where pe.documento_id = s.doc and pe.estado <> 'resolvida'
                                 and pe.tipo in ('documento_nao_extraido', 'arquivo_ilegivel', 'arquivo_corrompido'))
                      then 'recebido_sem_linha'
                 -- leitura concluída SEM dado em tipo que não traz dado financeiro por natureza (contrato social, certidão): zero linha é o
                 -- resultado certo, não falta (fn_tipo_sem_dado_por_natureza, 0231). Não há linha a conferir.
                 when fn_tipo_sem_dado_por_natureza(s.tipo_doc)
                      and exists (select 1 from concluida c where c.doc = s.doc)
                      then 'lido_sem_dado_por_natureza'
                 when exists (select 1 from concluida c where c.doc = s.doc)
                      or exists (select 1 from pendencia pe
                                  where pe.documento_id = s.doc and pe.tipo = 'extracao_falhou' and pe.estado <> 'resolvida')
                      then 'recebido_sem_linha'
                 else 'aguardando_extracao' end
             -- com linha, mas alguma sem aceite de PESSOA (o auto-aceite `sistema:` não conta)
             when exists (select 1 from campo_extraido ce
                           where ce.documento_versao_id = s.v
                             and not (ce.status_aceite <> 'pendente' and ce.aceito_por is not null
                                      and ce.aceito_por not like 'sistema:%')) then 'extraido'
             else 'conferido'
           end as estado
      from serve s
  ),
  aceite as materialized (
    select l.codigo, max(ce.aceito_em) as em,
           (array_agg(ce.aceito_por order by ce.aceito_em desc nulls last))[1] as por
      from lido l
      join campo_extraido ce on ce.documento_versao_id = l.v
     where l.estado = 'conferido'
     group by l.codigo
  ),
  item as materialized (
    select k.codigo, k.por_empresa,
           count(l.doc)::int as n_docs,
           coalesce(array_agg(l.doc order by l.criado_em, l.doc) filter (where l.doc is not null), '{}') as docs,
           -- o documento lido-sem-dado-por-natureza não pesa: não há linha a conferir nele; só vale como estado do item se for o ÚNICO
           min(case l.estado when 'recebido_sem_linha' then 1 when 'aguardando_extracao' then 2
                             when 'extraido' then 3 when 'conferido' then 4 end)
             filter (where l.estado <> 'lido_sem_dado_por_natureza') as pior,
           min(l.criado_em) filter (where l.estado = 'aguardando_extracao') as aguardando_desde,
           count(*) filter (where l.doc is not null and l.entidade_id is null)::int as sem_empresa,
           count(distinct l.entidade_id) filter (where l.no_perimetro)::int as com_documento,
           count(distinct l.entidade_id) filter (where l.no_perimetro and l.estado in ('extraido', 'conferido', 'lido_sem_dado_por_natureza'))::int as lidas
      from kit k
      left join lido l on l.codigo = k.codigo
     group by k.codigo, k.por_empresa
  ),
  conf as (
    select max(ev.criado_em) as em
      from evento_auditoria ev
     where ev.acao = 'completude_recomputada' and ev.entidade_ref = 'caso:' || p_caso::text
  ),
  m as (
    select count(*)::int as n from entidade e
     where e.caso_id = p_caso and e.papel_no_grupo is distinct from 'fora_do_perimetro'
  )
  select i.codigo::text,
         est.estado,
         case est.estado
           when 'faltante' then
             format('Nenhum documento recebido serve como %s. Enquanto faltar, o Portão 1 não abre e o que depende dele sai em branco no book.', i.codigo)
           when 'dispensado' then
             format('Seguiu sem %s por decisão de pessoa (prosseguir com ressalva). O que depende dele sai em branco no book, e a ressalva fica na pendência.', i.codigo)
           when 'aguardando_extracao' then
             'Recebido, mas a leitura ainda não terminou: nenhuma versão concluiu a extração e não há falha registrada. Se isto não mudar, o documento ficou sem leitura e o book sai vazio nesta parte.'
           when 'recebido_sem_linha' then
             'Recebido, mas nenhuma linha foi lida (a extração falhou, nunca foi chamada ou o arquivo está ilegível): o book sai VAZIO nesta parte, mesmo com o item recebido.'
           when 'lido_sem_dado_por_natureza' then
             'Lido: este tipo de documento (societário/legal) não traz dado financeiro, então não há linha a conferir. O book não depende de linha dele.'
           when 'extraido' then
             'Lido, mas nenhuma pessoa conferiu todas as linhas. O aceite automático do sistema não conta como conferência.'
           else
             'Toda linha da versão vigente foi aceita por pessoa.'
         end,
         i.docs,
         coalesce((select jsonb_object_agg(g.estado, g.n)
                     from (select l2.estado, count(*) as n from lido l2 where l2.codigo = i.codigo group by l2.estado) g),
                  '{}'::jsonb),
         case when est.estado = 'conferido' then a.por end,
         case when est.estado = 'conferido' then a.em end,
         case when i.por_empresa then m.n end,
         case when i.por_empresa then i.com_documento end,
         case when i.por_empresa then i.lidas end,
         case when i.por_empresa then i.sem_empresa end,
         i.aguardando_desde,
         conf.em,
         (select count(*)::int from documento d where d.caso_id = p_caso and (conf.em is null or d.criado_em > conf.em))
    from item i
    cross join conf
    cross join m
    left join aceite a on a.codigo = i.codigo
    cross join lateral (
      select case
               when i.n_docs = 0 then
                 case when exists (select 1 from pendencia pe
                                    where pe.caso_id = p_caso and pe.tipo = 'item_faltante'
                                      and pe.chave_motor = 'completude:item_faltante:' || i.codigo
                                      and pe.estado = 'aceita_com_ressalva')
                      then 'dispensado' else 'faltante' end
               when i.pior is null then 'lido_sem_dado_por_natureza'
               when i.pior = 1 then 'recebido_sem_linha'
               when i.pior = 2 then 'aguardando_extracao'
               when i.pior = 3 then 'extraido'
               else 'conferido'
             end as estado
    ) est
   -- mandato que o chamador não enxerga (RLS) ou que não existe: nenhuma linha, nunca "tudo faltante"
   where exists (select 1 from caso c where c.id = p_caso)
  order by i.codigo;
$$;

-- O COMMENT é o da 0300 (o `create or replace` não o apaga; repetido aqui para a leitura da migration não depender da 0300) com a 0301 no fim.
comment on function fn_kit_do_caso(uuid) is
  '0300: o estado de cada item OBRIGATÓRIO do Kit Básico do mandato, derivado de campo_extraido na leitura. Estados: faltante, dispensado (item_faltante aceita_com_ressalva e ainda sem documento), aguardando_extracao (aguardando_desde = o criado_em do documento mais antigo nessa espera), recebido_sem_linha (extração concluída ou falha aberta sem linha, OU o sistema já declarou documento_nao_extraido/arquivo_ilegivel/arquivo_corrompido aberta), lido_sem_dado_por_natureza (leitura concluída sem dado em tipo societário/legal: não há linha a conferir), extraido, conferido (toda linha da versão vigente aceita por PESSOA; o auto-aceite sistema: não conta). O item toma o pior estado dos documentos que servem (o lido_sem_dado_por_natureza não pesa, salvo se for o único). empresas_total/com_documento/atendidas/documentos_sem_empresa dizem "N de M" SÓ para granularidade entidade e entidade_periodo (M sem fora_do_perimetro); nos demais tipos (caso, periodo) são NULOS e a tela não mostra fração. conferencia_em = último evento completude_recomputada; documentos_depois_da_conferencia = documentos criados depois dele (todos se nunca rodou). Mandato invisível ao chamador (RLS) = zero linhas, e o portal deve ler isso como "Kit não lido", nunca como faltante. security invoker. 0301: o CTE concluida pergunta fn_versao_extracao_concluida só das versões dos documentos do mandato (LATERAL), não de documento_versao inteira sob a RLS; mesma resposta.';

revoke all on function fn_kit_do_caso(uuid) from public, anon;
grant execute on function fn_kit_do_caso(uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- A SONDA. O marcador está em CÓDIGO (a sonda lê pg_get_functiondef, que traz os comentários do corpo): a pergunta "a leitura concluiu" só pode ser feita sobre
-- as versões dos documentos do mandato, pelo CTE `concluida`.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('kit_leitura_concluida_so_do_mandato', '0301', 'corpo', 'fn_kit_do_caso', 'from concluida c where c.doc = s.doc', null,
   'fn_versao_extracao_concluida só das versões dos documentos DO MANDATO, no CTE concluida. Corpo anterior (0300) = com a RLS o planejador a roda em TODAS as versões do banco, uma vez por subconsulta: 3,2 s para abrir o Kit de um mandato de 9 documentos (44 ms sem RLS), medido em produção em 13/11/2026, e estouro de statement_timeout no de 115.',
   'importante', 1389)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0301', revisado_em = current_date,
       observacao = 'A 0301 reemite fn_kit_do_caso (mesma assinatura e resposta) sem varrer documento_versao inteira sob a RLS: 3,2 s -> 0,03 s no mandato de 9 documentos, 4,5 s -> 0,4 s no de 115 (medido em produção, como authenticated, com rollback). 1 requisito novo (ordem 1389). A 0275 continua reservada ao aging: nunca rebaixar esta cobertura quando ela entrar.'
 where id = true;

commit;
