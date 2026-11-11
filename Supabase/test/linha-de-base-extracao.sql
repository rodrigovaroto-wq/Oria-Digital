-- LINHA DE BASE DA EXTRAÇÃO (F3), DOCUMENTO A DOCUMENTO — o número de base que o plano pede.
--
-- Plano (PLANO_DE_EXECUCAO_2026-11.md, linha 111): "Script que mede, por documento: falhou,
-- incompleto, linhas, descartadas por desalinhamento, seções que não fecham. Critério: número de
-- base publicado por documento." Sem esta medida a F3 não tem como dizer que melhorou: qualquer
-- melhora é comparada com a memória de alguém.
--
-- SOMENTE LEITURA: um SELECT, sem DDL, sem escrita, sem variável psql. Cola inteiro no SQL Editor
-- do Supabase ou vai pela API de gerenciamento. Não reusa `cobertura-do-lote.sql` porque aquele
-- responde OUTRA pergunta (o documento tem linha? aceite da F0, por caso, com `:caso_id` do psql);
-- este mede a QUALIDADE da extração, para todos os mandatos, sem psql.
--
-- ESCOPO: edite `padroes` abaixo. Vazio = todos os mandatos. Os padrões são `ilike`, p.ex.
--   array['Fw Valtra%', 'KRAUSPENHAR%', 'AMO teste 00%', 'teste ponta a ponta 30-09%', 'teste Canastra%']
--
-- SAÍDA: uma linha por documento (bloco = 1) e, no fim, uma linha de RESUMO por mandato
-- (bloco = 2) — na MESMA query porque o SQL Editor e a API só mostram o resultado do último
-- comando. Na linha de resumo, `falhou`, `incompleto` e os contadores são SOMAS sobre os
-- documentos; `cobertura` é o PIOR percentual medido; `obs` diz em quantos documentos cada soma
-- foi medida (soma sobre parte dos documentos é dito, não escondido).
--
-- DE ONDE VEM CADA COLUNA (e o que cada uma NÃO afirma):
--   * Versão: a de maior `n_versao`. Se ela ainda não foi extraída (0102/0149: a versão nasce
--     antes das linhas) e uma anterior foi, o motivo lido é o da anterior e `obs` diz qual.
--   * Motivo: `falha_motivo` do último evento `extracao_sombra` (é o que
--     `fn_registrar_campos_extraidos` recebeu); sem ele, `pendencia.descricao` da
--     `extracao_falhou` (que embute o mesmo motivo, `fn_descricao_extracao_falhou`).
--   * falhou: existe pendência `extracao_falhou` (aberta OU resolvida, o plano conta as duas);
--     `falhou_aberta` separa a que ainda está de pé.
--   * incompleto: o motivo traz "Extração INCOMPLETA" (N8N/lib/cobertura.mjs ~957).
--     LIMITE: motivo nulo = "a guarda não reclamou", e a guarda só roda com texto lido e
--     esperadas >= mínimo; documento sem texto de PDF não tem como aparecer incompleto aqui.
--   * linhas_devolvidas / linhas_esperadas / cobertura: lidas do texto
--     "N linha(s) devolvida(s) para um documento com M linha(s) ... (P% de cobertura". Só existem
--     quando a guarda disparou; documento são tem NULL, e NULL aqui é "a guarda não disparou",
--     não "cobertura zero". O texto é de produção e pode mudar: se mudar, estas três colunas
--     voltam NULL com `obs` — não 0.
--   * linhas_gravadas: count de `campo_extraido` da versão (PARES conta x coluna, não linhas do
--     documento — por isso não se compara com linhas_devolvidas; 0154). É a SOMA das duas
--     colunas seguintes, mantida para parear com a foto antiga.
--   * valores_gravados: pares com `valor_num` NÃO nulo. REGRESSÃO DE DADO SE LÊ AQUI.
--   * textos_gravados: pares só de texto (`valor_num` nulo: Natureza, Objeto, Agência, Conta...).
--     Cair aqui NÃO é perda de dado: o modelo pode juntar a coluna de texto ao rótulo da linha.
--     Nenhum leitor (portal/src/lib, Supabase/migrations, N8N/lib) depende dessas colunas.
--     Caso medido em produção (11/11, P10, re-extração do Canastra sintético): `linhas_gravadas`
--     de 26_Contingencias_e_Processos_Judiciais caiu de 38 para 16 e a de
--     29_Extrato_Bancario_Consolidado de 27 para 6 — parecia regressão. Não era: valores_gravados
--     idêntico nas duas versões (Contingências 12 valores, soma 78.608; Extrato 6 valores, soma
--     1.650); o que caiu foram os textos (26 -> 4 e 21 -> 0).
--   * descartadas_desalinhamento: "N conta(s) descartada(s) por desalinhamento"
--     (N8N/lib/extract.mjs ~1396).
--   * secoes_que_nao_fecham: ocorrências de "identidade de linha não fecha" + "total da série não
--     fecha" no motivo (N8N/lib/aritmetica.mjs 119/209) + pendências `divergencia_reconciliacao`
--     abertas do documento. TETO: o nó junta no máximo 5 de cada identidade ("| ..."), então 5
--     de cada é "5 ou mais". As três parcelas vêm separadas nas colunas seguintes.
--
-- REGRA 1: ausência é NULL com motivo em `obs`. Documento NUNCA extraído (sem evento e sem linha)
-- tem NULL em tudo que a extração mede; extraído com 0 linhas tem 0.
set default_transaction_read_only = on;

with filtro as (
  select array[]::text[] as padroes          -- <- EDITE AQUI; vazio = todos os mandatos
),
docs as (
  select c.nome as mandato, d.id as documento_id, d.tipo_taxonomia,
         v.id as versao_id, v.n_versao, v.nome_original
    from documento d
    join caso c on c.id = d.caso_id
    cross join filtro f
    cross join lateral (
      select dv.id, dv.n_versao, dv.nome_original
        from documento_versao dv
       where dv.documento_id = d.id
       order by dv.n_versao desc limit 1
    ) v
   where cardinality(f.padroes) = 0 or c.nome ilike any (f.padroes)
),
-- MATERIALIZED: cada CTE é lida mais de uma vez; sem isso o Postgres inlina e refaz a varredura
-- de evento_auditoria por referência.
evento as materialized (
  select distinct on (dv.documento_id)
         dv.documento_id, dv.n_versao as n_versao_evento,
         ea.depois->>'falha_motivo' as falha_motivo
    from documento_versao dv
    join docs on docs.documento_id = dv.documento_id
    join evento_auditoria ea
      on ea.acao = 'extracao_sombra'
     and ea.entidade_ref = 'documento_versao:' || dv.id::text
   order by dv.documento_id, ea.criado_em desc
),
linhas as materialized (
  select docs.documento_id, count(ce.id) as n,
         count(ce.id) filter (where ce.valor_num is not null) as n_valores,
         count(ce.id) filter (where ce.valor_num is null) as n_textos
    from docs
    left join campo_extraido ce on ce.documento_versao_id = docs.versao_id
   group by docs.documento_id
),
falha as materialized (
  select p.documento_id,
         count(*) as n,
         bool_or(p.estado <> 'resolvida') as aberta,
         (array_agg(p.descricao order by p.criada_em desc))[1] as descricao
    from pendencia p
   where p.tipo = 'extracao_falhou' and p.documento_id in (select documento_id from docs)
   group by p.documento_id
),
recon as materialized (
  select p.documento_id, count(*) as n
    from pendencia p
   where p.tipo = 'divergencia_reconciliacao' and p.estado <> 'resolvida'
     and p.documento_id in (select documento_id from docs)
   group by p.documento_id
),
base as (
  select docs.*,
         (e.documento_id is not null or l.n > 0) as extraido,
         e.n_versao_evento,
         l.n as linhas_gravadas, l.n_valores as valores_gravados, l.n_textos as textos_gravados,
         (f.documento_id is not null) as tem_pend_falhou,
         coalesce(f.aberta, false) as pend_aberta,
         coalesce(e.falha_motivo, f.descricao) as motivo,
         (e.falha_motivo is null and f.descricao is not null) as motivo_da_pendencia,
         coalesce(r.n, 0) as recon_abertas
    from docs
    join linhas l on l.documento_id = docs.documento_id
    left join evento e on e.documento_id = docs.documento_id
    left join falha  f on f.documento_id = docs.documento_id
    left join recon  r on r.documento_id = docs.documento_id
),
doc as (
  select b.*,
         substring(b.motivo from '(\d+) linha\(s\) devolvida\(s\) para um documento com \d+')::int as devolvidas,
         substring(b.motivo from '\d+ linha\(s\) devolvida\(s\) para um documento com (\d+)')::int as esperadas,
         substring(b.motivo from '\((\d+)% de cobertura')::int as cobertura,
         substring(b.motivo from '(\d+) conta\(s\) descartada\(s\) por desalinhamento')::int as descartadas,
         (length(b.motivo) - length(replace(b.motivo, 'identidade de linha não fecha', '')))
           / length('identidade de linha não fecha') as sec_linha,
         (length(b.motivo) - length(replace(b.motivo, 'total da série não fecha', '')))
           / length('total da série não fecha') as sec_serie
    from base b
),
saida as (
  select 1 as bloco, mandato, nome_original as documento, tipo_taxonomia as tipo, n_versao as versao,
         case when not extraido then null else case when tem_pend_falhou then 1 else 0 end end as falhou,
         case when not extraido then null else case when pend_aberta then 1 else 0 end end as falhou_aberta,
         case when not extraido then null
              else case when motivo like '%Extração INCOMPLETA%' then 1 else 0 end end as incompleto,
         devolvidas as linhas_devolvidas,
         esperadas  as linhas_esperadas,
         case when extraido then linhas_gravadas end as linhas_gravadas,
         case when extraido then valores_gravados end as valores_gravados,
         case when extraido then textos_gravados end as textos_gravados,
         case when not extraido then null else coalesce(descartadas, 0) end as descartadas_desalinhamento,
         case when not extraido then null else sec_linha + sec_serie + recon_abertas end as secoes_que_nao_fecham,
         case when not extraido then null else sec_linha end as sec_identidade_linha,
         case when not extraido then null else sec_serie end as sec_total_serie,
         case when not extraido then null else recon_abertas end as sec_reconciliacao_aberta,
         cobertura,
         concat_ws(' | ',
           case when not extraido then 'NUNCA EXTRAÍDO: sem evento extracao_sombra e sem linha em nenhuma versão; nada foi medido (NULL, não 0)' end,
           case when extraido and n_versao_evento is not null and n_versao_evento <> n_versao
                then 'versão ' || n_versao || ' ainda não extraída; motivo lido da v' || n_versao_evento
                     || ', linhas_gravadas é da v' || n_versao end,
           case when extraido and n_versao_evento is null and linhas_gravadas > 0
                then 'linhas sem evento extracao_sombra (dado anterior ao evento); motivo só da pendência' end,
           case when extraido and motivo_da_pendencia then 'motivo lido da pendência, não do evento' end,
           case when extraido and linhas_gravadas = 0 then 'extraído com ZERO linha gravada (medido, não ausente)' end,
           case when extraido and cobertura is null then 'sem número de cobertura: a guarda não disparou (ou o texto do motivo mudou)' end,
           case when extraido and (sec_linha >= 5 or sec_serie >= 5) then 'identidade/série no teto de 5 por motivo: pode haver mais' end
         ) as obs
    from doc
  union all
  select 2, mandato, 'RESUMO: ' || count(*) || ' documento(s)', null, null,
         sum(case when not extraido then null else case when tem_pend_falhou then 1 else 0 end end),
         sum(case when not extraido then null else case when pend_aberta then 1 else 0 end end),
         sum(case when not extraido then null else case when motivo like '%Extração INCOMPLETA%' then 1 else 0 end end),
         sum(devolvidas), sum(esperadas),
         sum(case when extraido then linhas_gravadas end),
         sum(case when extraido then valores_gravados end),
         sum(case when extraido then textos_gravados end),
         sum(case when not extraido then null else coalesce(descartadas, 0) end),
         sum(case when not extraido then null else sec_linha + sec_serie + recon_abertas end),
         sum(case when not extraido then null else sec_linha end),
         sum(case when not extraido then null else sec_serie end),
         sum(case when not extraido then null else recon_abertas end),
         min(cobertura),
         count(*) filter (where not extraido) || ' nunca extraído(s); '
         || count(*) filter (where extraido) || ' extraído(s); '
         || count(*) filter (where extraido and linhas_gravadas = 0) || ' extraído(s) com 0 linha; '
         || count(*) filter (where devolvidas is not null) || ' com cobertura medida (linhas_devolvidas/esperadas/cobertura-pior só somam esses); '
         || count(*) filter (where extraido and not tem_pend_falhou and motivo is null) || ' sem motivo nem pendência'
    from doc
   group by mandato
)
select * from saida
 order by bloco, mandato,
          -- os que mais precisam de olho primeiro
          coalesce(incompleto, 0) desc, coalesce(falhou, 0) desc, coalesce(secoes_que_nao_fecham, 0) desc,
          documento;
