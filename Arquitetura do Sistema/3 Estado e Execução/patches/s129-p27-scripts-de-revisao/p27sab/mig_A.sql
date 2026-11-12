-- (cabeçalho provisório)
alter type pendencia_tipo add value if not exists 'conta_canonica_incerta';

begin;

-- LOCK: nada abaixo espera um lote do n8n por mais de 5 s. Esta migration NÃO cria tabela, NÃO faz backfill e só cria UM gatilho (em evento_auditoria): o lock dele dura milissegundos.
set local lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- LIMPEZA dos rascunhos anteriores desta migration (idempotente; em produção nada disto existe). A tabela mantida por gatilhos (1ª a 4ª revisão) vira VIEW: o que a mantinha sai.
-- -----------------------------------------------------------------------------
do $limpa$
declare v_k "char";
begin
  select c.relkind into v_k from pg_class c where c.oid = to_regclass('public.fato_financeiro');
  if v_k in ('r', 'p') then execute 'drop table fato_financeiro cascade'; end if;
end $limpa$;
drop trigger if exists trg_fato_segue_o_documento on documento;
drop trigger if exists trg_fato_cadastro_periodo on periodo;
drop trigger if exists trg_fato_cadastro_entidade on entidade;
drop function if exists fn_fato_segue_o_documento();
drop function if exists fn_fato_cadastro_periodo();
drop function if exists fn_fato_cadastro_entidade();
drop function if exists fn_fato_recalcular_caso(uuid, text, text);
drop function if exists fn_fato_recalcular(uuid, text, text);
drop function if exists fn_fato_reresolver_caso(uuid, text);
drop function if exists fn_fato_repontar_entidade(uuid, uuid, uuid);
drop function if exists fn_materializar_fatos(uuid, text);
drop function if exists fn_materializar_fatos_do_caso(uuid, text, text);
drop function if exists fn_materializar_fatos_da_extracao(uuid, text);
drop function if exists fn_materializar_fatos_backfill();
drop function if exists fn_fato_mesmo_caso();
drop function if exists fn_fato_resolver(uuid, boolean);
drop view if exists instalacao_sonda_fato_financeiro_constraints;
drop view if exists instalacao_sonda_fato_financeiro_so_secao;
drop view if exists instalacao_sonda_fato_financeiro_recentes;
drop view if exists instalacao_sonda_fato_financeiro_um_escritor;
drop view if exists instalacao_sonda_fato_financeiro_authenticated_so_le;
delete from instalacao_requisito where migration = '0243';

-- -----------------------------------------------------------------------------
-- O QUE É ELEGÍVEL: uma lista só, e todo o resto (backfill, extração nova, sonda, teste) pergunta a ela.
-- -----------------------------------------------------------------------------
create or replace function fn_tipo_gera_fato(p_tipo text)
returns boolean language sql immutable as $$
  select coalesce(p_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DRE', 'FLUXO_CAIXA', 'DVA', 'DMPL', 'DF_AUDITADA'), false)
$$;
comment on function fn_tipo_gera_fato(text) is
  '0243: os tipos de documento cujas linhas viram fato_financeiro: as demonstrações. BALANCO, BALANCETE, COMBINADO, DRE e FLUXO_CAIXA são as 5 de ESTRUTURA_POR_TIPO (statement-templates.ts); DVA e DMPL são as 2 que a 0024 pôs na taxonomia e o portal já roteia por seção (FAMILIA_POR_SECAO_CANONICA); DF_AUDITADA traz as demonstrações juntas e cada linha vai para a SUA seção. '
  'A categoria Contábil/Demonstrações da taxonomia NÃO serve de proxy: ela inclui RAZAO e NOTAS_EXPL. Estoque, Razão, Aging, Mapa de Dívida e o resto continuam só evidência. A sonda confere os 8 tipos um a um (view), não pelo corpo.';

create or replace function fn_linha_vira_fato(p_tipo text, p_chave text, p_unidade text, p_valor numeric)
returns boolean language sql immutable as $$
  select p_valor is not null and fn_tipo_gera_fato(p_tipo) and fn_papel_linha(p_chave, p_tipo, p_unidade) = 'conta'
$$;
comment on function fn_linha_vira_fato(text, text, text, numeric) is
  '0243: a linha de campo_extraido vira fato quando (1) tem valor (célula vazia é ausência, não zero: regra 1), (2) o documento é de demonstração e (3) o papel é conta (fn_papel_linha): subtotal é a P28, derivado e série mensal não são conta.';

revoke all on function fn_tipo_gera_fato(text), fn_linha_vira_fato(text, text, text, numeric) from public, anon;
grant execute on function fn_tipo_gera_fato(text), fn_linha_vira_fato(text, text, text, numeric) to authenticated, service_role;
-- E ao leitor só-leitura da API de gerenciamento (`supabase_read_only_user`), como a 0233, a 0234 e a correção da 0242: as views da sonda chamam estas funções com o privilégio de quem LÊ, e sem o grant a sonda INTEIRA fica ilegível para quem lê
-- produção sem escrever (o defeito que a 0242 teve em 11/11/2026). fn_papel_linha entra porque fn_linha_vira_fato a chama (chamada transitiva: o Postgres confere o EXECUTE de cada função da cadeia com o leitor; em produção ela já o tem, medido,
-- e o grant é idempotente; no banco do run.sh, que cria o papel antes das migrations, é ele que o dá).
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    execute 'grant execute on function fn_tipo_gera_fato(text) to supabase_read_only_user';
    execute 'grant execute on function fn_linha_vira_fato(text, text, text, numeric) to supabase_read_only_user';
    execute 'grant execute on function fn_papel_linha(text, text, text) to supabase_read_only_user';
  end if;
end $$;


-- O ATOR REAL do evento: o usuário autenticado quando há (a reclassificação humana de um documento grava o nome dele, não 'sistema:n8n'), senão o sistema.
create or replace function fn_fato_ator()
returns text language sql stable as $$ select coalesce('usuario:' || auth.uid()::text, 'sistema:0243') $$;
revoke all on function fn_fato_ator() from public, anon;
grant execute on function fn_fato_ator() to authenticated, service_role;

-- QUEM PODE ESCREVER fato: conexão de serviço (o n8n, a migration: o papel da sessão é service_role ou nenhum) ou quem escreve no mandato (fn_pode_escrever_caso, 0216). O `current_setting('role')` é o papel que o PostgREST pôs
-- com SET ROLE e é lido DENTRO de função security definer (current_user lá seria o dono). Caso nulo (o backfill de tudo) só a conexão de serviço.
create or replace function fn_fato_pode_escrever(p_caso uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(current_setting('role', true), 'none') in ('none', 'service_role', 'postgres', 'supabase_admin')
      or (p_caso is not null and fn_pode_escrever_caso(p_caso))
$$;
revoke all on function fn_fato_pode_escrever(uuid) from public, anon, authenticated;


-- -----------------------------------------------------------------------------
-- A RESOLUÇÃO: a identidade de TODAS as linhas elegíveis do estado ATUAL (versão nula = todas). Só LÊ: quem grava é fn_fato_recalcular (4ª revisão: o fato é sempre recalculado do estado atual, nunca remendado por caminho parcial).
-- -----------------------------------------------------------------------------
drop function if exists fn_fato_resolver(uuid, boolean);
create or replace function fn_fato_resolver(p_documento_versao_id uuid)
returns table (campo_id uuid, documento_versao_id uuid, conta_id text, resolucao_metodo text, sem_conta_motivo text,
               entidade_id uuid, entidade_origem text, entidade_motivo text, entidade_coluna text,
               periodo_id uuid, periodo_origem text, periodo_motivo text, periodo_coluna text,
               valor numeric, unidade text, moeda text, origem text, criado_em timestamptz)
language sql stable as $$
  with cand as materialized (
    select ce.id as campo_id, ce.documento_versao_id, d.caso_id, d.tipo_taxonomia as tipo, ce.chave, d.entidade_id as doc_entidade, d.periodo_id as doc_periodo,
           pd.tipo as dper_tipo, pd.referencia as dper_ref,
           ce.valor_num, ce.unidade, ce.moeda, ce.origem_valor as origem, ce.criado_em as campo_criado_em, ce.secao_canonica as secao, ce.secao_canonica_inferida as inferida,
           nullif(btrim(ce.entidade_coluna), '') as ecol, nullif(btrim(ce.periodo_coluna), '') as pcol
      from campo_extraido ce
      join documento_versao dv on dv.id = ce.documento_versao_id
      join documento d on d.id = dv.documento_id
      left join periodo pd on pd.id = d.periodo_id
     where (p_documento_versao_id is null or ce.documento_versao_id = p_documento_versao_id)
       and ce.valor_num is not null and fn_tipo_gera_fato(d.tipo_taxonomia)
  ),
  -- O papel da linha (fn_papel_linha, ~180 µs) UMA vez por (tipo, rótulo, unidade) distintos, não por linha. Medido em produção em 11/11/2026: 100.215 linhas de demonstração com valor, 6.841 combinações distintas (15x menos chamadas).
  -- fn_linha_vira_fato é o predicado ÚNICO (a sonda e o teste o usam): o valor entra como 1 porque ele só pergunta se é nulo, e a CTE acima já tirou os nulos.
  -- (duas CTEs, não uma subconsulta: o Postgres empurra o filtro para DENTRO do distinct e chama fn_papel_linha por LINHA de novo — medido, 21 s.)
  rotulos as materialized (select distinct tipo, chave, unidade from cand),
  papel as materialized (
    select x.tipo, x.chave, x.unidade from rotulos x where fn_linha_vira_fato(x.tipo, x.chave, x.unidade, 1)
  ),
  alvo as materialized (
    select c.* from cand c join papel p on p.tipo = c.tipo and p.chave = c.chave and coalesce(p.unidade, '') = coalesce(c.unidade, '')
  ),
  vinfo as materialized (
    select v.documento_versao_id, v.caso_id, v.tipo, v.doc_entidade, v.doc_periodo, v.dper_tipo, v.dper_ref,
           case when cardinality(fn_anos_periodo(v.dper_tipo, v.dper_ref)) = 1 then (fn_anos_periodo(v.dper_tipo, v.dper_ref))[1] end as y
      from (select distinct documento_versao_id, caso_id, tipo, doc_entidade, doc_periodo, dper_tipo, dper_ref from alvo) v
  ),
  -- ===== ENTIDADE: quem decide é fn_coluna_entidade (0023/0030, com fn_mesma_entidade): a coluna que ela devolve para a entidade E é a coluna de E. Nenhum casamento de nome é escrito aqui.
  -- 3ª REVISÃO, ALTO 1: fn_coluna_entidade devolve UMA coluna por entidade (`limit 1` sem order by). Com duas colunas do documento que casam o nome da MESMA entidade ("Alfa Comércio Atacado", empresa não cadastrada, e "Alfa Comércio") ela entrega a que a ordem física der, e a ALFA recebia a soma de uma coluna que
  -- talvez nem fosse dela, com a própria coluna anulada pelo motivo falso coluna_sem_entidade_no_mandato. Unicidade por (versão, entidade): as colunas DISTINTAS do documento em que fn_mesma_entidade é verdadeira para a entidade; mais de uma = nenhuma delas é atribuída (entidade_com_varias_colunas).
  ecols as materialized (
    select distinct ce.documento_versao_id, v.caso_id, nullif(btrim(ce.entidade_coluna), '') as col
      from (select distinct documento_versao_id, caso_id from alvo where ecol is not null) v
      join campo_extraido ce on ce.documento_versao_id = v.documento_versao_id and nullif(btrim(ce.entidade_coluna), '') is not null
  ),
  enome as materialized (
    select c.documento_versao_id, c.col, e.id as entidade_id
      from ecols c join entidade e on e.caso_id = c.caso_id
     where fn_mesma_entidade(c.col, e.razao_social)
  ),
  enome_n as materialized (select documento_versao_id, entidade_id, count(distinct col) as n from enome group by 1, 2),
  eescolha as materialized (
    select x.documento_versao_id, x.col, x.entidade_id, x.razao_social
      from (select v.documento_versao_id, e.id as entidade_id, e.razao_social, nullif(btrim(fn_coluna_entidade(v.documento_versao_id, e.id)), '') as col
              from (select distinct documento_versao_id, caso_id from alvo where ecol is not null) v
              join entidade e on e.caso_id = v.caso_id) x
     where x.col is not null and x.col <> chr(1)
       and not exists (select 1 from enome_n n where n.documento_versao_id = x.documento_versao_id and n.entidade_id = x.entidade_id and n.n > 1)
  ),
  emap as materialized (
    select documento_versao_id, col, count(*) as n, (array_agg(entidade_id))[1] as entidade_id, bool_or(fn_mesma_entidade(col, razao_social)) as por_nome
      from eescolha group by 1, 2
  ),
  -- fn_coluna_entidade entrega "a" coluna total (limit 1, sem ordem): com mais de uma coluna total no documento a escolha é arbitrária, e arbitrária não é inequívoca
  etot as materialized (
    select ce.documento_versao_id, count(distinct nullif(btrim(ce.entidade_coluna), '')) as n
      from campo_extraido ce
     where ce.documento_versao_id in (select documento_versao_id from vinfo) and ce.entidade_coluna is not null
       and fn_normalizar_texto(ce.entidade_coluna) ~ '^(combinad|consolidad|total|soma)'
     group by 1
  ),
  -- documento que TEM coluna de entidade: a linha sem entidade_coluna não tem dono inequívoco (a coluna total do dono e a linha "sem coluna" seriam duas colunas na mesma chave: a soma dobra)
  vecol as materialized (
    select distinct ce.documento_versao_id
      from campo_extraido ce
     where ce.documento_versao_id in (select documento_versao_id from vinfo) and nullif(btrim(ce.entidade_coluna), '') is not null
  ),
  ent as materialized (
    select k.documento_versao_id, coalesce(k.ecol, '') as ekey,
           case when k.ecol is null then (case when not k.tem_ecols then k.doc_entidade end) when m.n = 1 and (m.por_nome or coalesce(t.n, 0) <= 1) then m.entidade_id end as entidade_id,
           case when k.ecol is null then (case when k.doc_entidade is not null and not k.tem_ecols then 'documento' end)
                when m.n = 1 and (m.por_nome or coalesce(t.n, 0) <= 1) then (case when m.por_nome then 'coluna' else 'coluna_total' end) end as origem,
           case when k.ecol is null then (case when k.doc_entidade is null then 'documento_sem_entidade' when k.tem_ecols then 'linha_sem_coluna_em_documento_com_colunas_de_entidade' end)
                when m.n = 1 and m.por_nome then null
                when m.n = 1 and coalesce(t.n, 0) <= 1 then null
                when m.n = 1 then 'coluna_total_ambigua'
                when m.n > 1 then 'coluna_casa_varias_entidades'
                when exists (select 1 from enome en join enome_n nn on nn.documento_versao_id = en.documento_versao_id and nn.entidade_id = en.entidade_id
                              where en.documento_versao_id = k.documento_versao_id and en.col = k.ecol and nn.n > 1) then 'entidade_com_varias_colunas'
                when fn_normalizar_texto(k.ecol) ~ '^(combinad|consolidad|total|soma)' then (case when coalesce(t.n, 0) > 1 and exists (select 1 from emap e2 where e2.documento_versao_id = k.documento_versao_id and not e2.por_nome) then 'coluna_total_ambigua' else 'coluna_total_nao_escolhida' end)
                else 'coluna_sem_entidade_no_mandato' end as motivo
      from (select x.documento_versao_id, x.doc_entidade, x.ecol, (ve.documento_versao_id is not null) as tem_ecols
              from (select distinct documento_versao_id, doc_entidade, ecol from alvo) x
              left join vecol ve on ve.documento_versao_id = x.documento_versao_id) k
      left join emap m on m.documento_versao_id = k.documento_versao_id and m.col = k.ecol
      left join etot t on t.documento_versao_id = k.documento_versao_id
  ),
  -- ===== PERÍODO: a 0243 não interpreta nome de coluna. Só atribui quando as funções do banco para esta pergunta (fn_coluna_e_saldo, fn_coluna_e_abertura, fn_periodo_e_parcial, fn_anos_periodo, fn_periodo_canonico: 0199-0201/0234) decidem de forma INEQUÍVOCA.
  --   A coluna que É o período do documento: a ÚNICA coluna de saldo (Saldo final/atual) ou, na falta de saldo, a ÚNICA coluna que nomeia só o ano do documento num documento NÃO parcial. Duas candidatas (ou nenhuma): nenhuma é escolhida (fn_coluna_periodo_do_ano
  --   desempata por contagem e ordem alfabética: no balancete de junho com Jun/2025 e 30/06/2025 ela entrega uma ao acaso, e "ao acaso" é número fabricado). Documento sem coluna nenhuma: a linha é do período do documento.
  vcol as materialized (
    select i.documento_versao_id, c.pcol, i.y,
           fn_coluna_e_abertura(c.pcol) as abertura,
           (fn_coluna_e_saldo(c.pcol) and not fn_coluna_e_abertura(c.pcol)) as saldo,
           fn_periodo_e_parcial(c.pcol, i.tipo, i.dper_tipo, i.dper_ref) as parcial,
           case when regexp_replace(fn_periodo_canonico('outro', c.pcol), '^(\d{4})-12-31$', '\1') ~ '^\d{4}$'
                then regexp_replace(fn_periodo_canonico('outro', c.pcol), '^(\d{4})-12-31$', '\1')::int end as ano_puro
      from vinfo i
      join (select distinct ce.documento_versao_id, nullif(btrim(ce.periodo_coluna), '') as pcol
              from campo_extraido ce
             where ce.documento_versao_id in (select documento_versao_id from vinfo) and nullif(btrim(ce.periodo_coluna), '') is not null) c
        on c.documento_versao_id = i.documento_versao_id
  ),
  vcol2 as materialized (
    select c.*, (c.ano_puro is not null and not c.parcial and c.ano_puro = c.y) as e_ano_do_doc,
           (c.y is not null and (c.saldo or (c.ano_puro is not null and not c.parcial and c.ano_puro = c.y))) as cand,
           count(*) filter (where c.ano_puro is not null and not c.parcial) over (partition by c.documento_versao_id, c.ano_puro) as n_mesmo_ano
      from vcol c
  ),
  vesc as materialized (
    select documento_versao_id, count(*) as n_cols,
           case when count(*) filter (where y is not null and (saldo or e_ano_do_doc)) = 1
                then min(pcol) filter (where y is not null and (saldo or e_ano_do_doc)) end as escolhida,
           count(*) filter (where cand) as n_cand
      from vcol2 group by 1
  ),
  per0 as materialized (
    select documento_versao_id, pcol, abertura, parcial, ano_puro, e_ano_do_doc, n_mesmo_ano, cand from vcol2
    union all
    select documento_versao_id, null, false, false, null::int, false, 0, false from vinfo
  ),
  per as materialized (
    select z.documento_versao_id, coalesce(z.pcol, '') as pkey,
           z.pid as periodo_id,
           case when z.pid is null then null when z.pcol is null or z.pcol = z.escolhida then 'documento' else 'coluna' end as origem,
           case when z.pid is not null then null
                when z.pcol is null and z.n_cols > 0 then 'linha_sem_coluna_em_documento_com_colunas'
                when (z.pcol is null or z.pcol = z.escolhida) and z.doc_periodo is null then 'documento_sem_periodo'
                when z.abertura then 'coluna_de_abertura'
                when z.n_mesmo_ano > 1 then 'mais_de_uma_coluna_para_o_mesmo_periodo'
                when z.cand and z.n_cand > 1 then 'mais_de_uma_coluna_para_o_mesmo_periodo'
                when z.ano_puro is not null and not z.parcial and not z.e_ano_do_doc then 'periodo_da_coluna_nao_cadastrado'
                else 'coluna_nao_e_o_periodo_do_documento' end as motivo
      from (select p.documento_versao_id, p.pcol, p.abertura, p.parcial, p.ano_puro, p.e_ano_do_doc, p.n_mesmo_ano, p.cand,
                   i.doc_periodo, coalesce(e.n_cols, 0) as n_cols, e.escolhida, e.n_cand,
                   case when p.pcol is null then (case when coalesce(e.n_cols, 0) = 0 then i.doc_periodo end)
                        when p.pcol = e.escolhida then i.doc_periodo
                        when p.abertura then null
                        when p.ano_puro is not null and not p.parcial and not p.e_ano_do_doc and p.n_mesmo_ano = 1 then x.id
                        else null end as pid
              from per0 p
              join vinfo i on i.documento_versao_id = p.documento_versao_id
              left join vesc e on e.documento_versao_id = p.documento_versao_id
              left join lateral (
                -- o MESMO casamento de fn_upsert_periodo (forma canônica, o de menor referência no empate), sem o insert: o período NÃO é criado aqui. O fechamento 31/12/AAAA e o ano AAAA são o mesmo período.
                select coalesce(
                         (select q.id from periodo q where q.id = i.doc_periodo
                             and regexp_replace(fn_periodo_canonico(q.tipo, q.referencia), '^(\d{4})-12-31$', '\1') = p.ano_puro::text),
                         (select q.id from periodo q where q.caso_id = i.caso_id
                             and regexp_replace(fn_periodo_canonico(q.tipo, q.referencia), '^(\d{4})-12-31$', '\1') = p.ano_puro::text
                           order by q.referencia, q.id limit 1)) as id
                 where p.ano_puro is not null and not p.parcial and not p.e_ano_do_doc and p.n_mesmo_ano = 1) x on true) z
  )
  select a.campo_id, a.documento_versao_id, c.codigo,
         case when c.codigo is null then 'sem_conta' when a.inferida then 'heuristica' else 'declarada' end,
         case when c.codigo is not null then null
              when coalesce(nullif(btrim(a.secao), ''), 'NAO_CLASSIFICAVEL') = 'NAO_CLASSIFICAVEL' then 'secao_nao_declarada'
              else 'secao_fora_do_catalogo' end,
         e.entidade_id, e.origem, e.motivo, a.ecol, p.periodo_id, p.origem, p.motivo, a.pcol, a.valor_num, a.unidade, a.moeda, a.origem, a.campo_criado_em
    from alvo a
    left join conta_canonica c on c.secao_canonica = a.secao
    join ent e on e.documento_versao_id = a.documento_versao_id and e.ekey = coalesce(a.ecol, '')
    join per p on p.documento_versao_id = a.documento_versao_id and p.pkey = coalesce(a.pcol, '')
$$;
comment on function fn_fato_resolver(uuid) is
  '0243: a identidade de cada linha elegível: conta (a seção, pelo catálogo), entidade e período (pela coluna da linha quando ela diz, pelo documento quando não, e NULOS com o motivo quando a coluna não é saldo, é de abertura, o documento é parcial ou o total duplica a coluna da entidade). p_novos: as sem fato (materializar); falso: as que já têm (repor a identidade quando o documento muda).';
revoke all on function fn_fato_resolver(uuid) from public, anon;
grant execute on function fn_fato_resolver(uuid) to authenticated, service_role;



-- -----------------------------------------------------------------------------
-- A VIEW. `fato_financeiro` é o resolver LIDO, não uma cópia: igual ao "do zero" por construção, sem gatilho, sem backfill, sem corrida. Mostra TODAS as versões de documento (como a tabela mostrava): quem consome escolhe a vigente com fn_versao_atual(documento_id) — a leitura de uma versão superada
-- continua evidência do que ela disse. Identidade da linha: `id` = `campo_extraido_id` (uma linha por linha elegível de campo_extraido).
-- SECURITY_INVOKER = TRUE é o que mantém a RLS: uma view comum roda com o privilégio do DONO e pularia a RLS de campo_extraido, documento_versao, documento, entidade e periodo (o authenticated leria fato de todos os mandatos). Exige PostgreSQL 15+ (o CI e o banco local são 16; produção: ver o cabeçalho). O resolver é SECURITY INVOKER (o default) pelo mesmo motivo.
-- -----------------------------------------------------------------------------
create or replace view fato_financeiro with (security_invoker = true) as
  select r.campo_id as id, r.campo_id as campo_extraido_id, r.documento_versao_id, r.conta_id, r.resolucao_metodo, r.sem_conta_motivo,
         r.entidade_id, r.entidade_origem, r.entidade_motivo, r.entidade_coluna, r.periodo_id, r.periodo_origem, r.periodo_motivo, r.periodo_coluna,
         r.valor, r.unidade, r.moeda, r.origem, r.criado_em
    from fn_fato_resolver(null) r;

revoke all on fato_financeiro from public, anon, authenticated;
grant select on fato_financeiro to authenticated, service_role;
comment on view fato_financeiro is
  '0243 (P27): o fato canônico ACIMA de campo_extraido: UMA linha por linha extraída elegível (fn_linha_vira_fato: demonstração, papel conta, com valor), com a identidade (conta = a SEÇÃO; entidade e período só quando uma função do banco decide sem ambiguidade, senão nulos com motivo). É uma VIEW sobre fn_fato_resolver (security_invoker: a RLS de quem lê vale): igual ao do zero por construção, nunca envelhece. TODAS as versões; a vigente é fn_versao_atual. origem = campo_extraido.origem_valor (extracao | transcricao_humana).';

-- -----------------------------------------------------------------------------
-- A PENDÊNCIA conta_canonica_incerta: UMA por documento-versão, só para extração NOVA. Lê o resolver (a conta de cada linha: heurística ou sem conta) e NÃO grava fato nenhum (o fato é a view). Convergente: reflete o estado atual das linhas de EXTRAÇÃO da versão (a transcrição humana, origem transcricao_humana, nunca entra).
-- -----------------------------------------------------------------------------
create or replace function fn_fato_pendencia_da_versao(p_documento_versao_id uuid)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_caso uuid; v_doc uuid; v_nome text;
  v_h int; v_s int; v_lista text; v_desc text; v_pend uuid; v_vigente uuid;
  v_motivo text := 'fato:conta_incerta:' || p_documento_versao_id;
begin
  select d.caso_id, d.id, dv.nome_original into v_caso, v_doc, v_nome
    from documento_versao dv join documento d on d.id = dv.documento_id where dv.id = p_documento_versao_id;
  if v_doc is null then return null; end if;
  if not fn_fato_pode_escrever(v_caso) then
    raise exception 'fn_fato_pendencia_da_versao: sem permissão de escrita no mandato' using errcode = 'insufficient_privilege';
  end if;

  -- versão que NÃO é a vigente (fn_versao_atual): a leitura que ela traz foi superada, não se abre pendência sobre ela (e a aberta se baixa abaixo, pelo ramo de "sem linha incerta")
  v_vigente := fn_versao_atual(v_doc);

  select count(*) filter (where x.resolucao_metodo = 'heuristica'), count(*) filter (where x.resolucao_metodo = 'sem_conta'),
         string_agg(x.rotulo, '; ' order by x.rn) filter (where x.rn <= 12)
    into v_h, v_s, v_lista
    from (select f.resolucao_metodo,
                 ce.chave || case f.resolucao_metodo
                               when 'heuristica' then ' [seção inferida: ' || coalesce(ce.secao_canonica, '?') || ']'
                               else ' [sem seção' || case when f.sem_conta_motivo = 'secao_fora_do_catalogo' then ': "' || coalesce(ce.secao_canonica, '') || '" não está no catálogo' else '' end || ']' end as rotulo,
                 row_number() over (order by ce.ordem nulls last, ce.id) as rn
            from fn_fato_resolver(p_documento_versao_id) f join campo_extraido ce on ce.id = f.campo_id
           where f.origem = 'extracao' and f.resolucao_metodo <> 'declarada') x;

  select id into v_pend from pendencia where caso_id = v_caso and motivo = v_motivo and estado = 'aberta' limit 1;

  if v_vigente is distinct from p_documento_versao_id then
    v_h := 0; v_s := 0;
  end if;

  if v_h + v_s > 0 then
    v_desc := format('%s linha(s) de "%s" ficaram com a conta canônica por HEURÍSTICA (%s: a IA não deu a seção, ela foi inferida do texto da seção ou da árvore do documento) ou SEM conta (%s: sem seção, ou com uma que o catálogo não conhece). '
                     'Linha sem conta é fato sem identidade: não entra em nenhuma seção até alguém dizer qual é. Confirme a seção destas linhas%s: %s%s',
                     v_h + v_s, coalesce(v_nome, '?'), v_h, v_s,
                     case when v_h + v_s > 12 then ' (as 12 primeiras de ' || (v_h + v_s) || ')' else '' end,
                     v_lista, '.');
    if v_pend is not null then
      update pendencia set descricao = v_desc where id = v_pend;
    elsif not exists (select 1 from pendencia where caso_id = v_caso and motivo = v_motivo
                         and (estado <> 'resolvida' or coalesce(resolvida_por, '') not like 'sistema:%')) then
      -- (viva em outro estado, ou resolvida por uma PESSOA: não se abre outra; decisão humana não se desfaz, 0231)
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso, 'extracao', 'conta_canonica_incerta', 'complementar', true, v_desc, v_doc, v_motivo)
        returning id into v_pend;
    end if;
  elsif v_pend is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = case when v_vigente is distinct from p_documento_versao_id then 'sistema:versao_superada' else 'sistema:extracao' end where id = v_pend;
    v_pend := null;
  end if;
  return v_pend;
end $$;
comment on function fn_fato_pendencia_da_versao(uuid) is
  '0243: a pendência conta_canonica_incerta (motivo fato:conta_incerta:<versão>), UMA por documento-versão, listando as linhas de EXTRAÇÃO resolvidas por heurística ou sem conta (as 12 primeiras no texto). Reabre-se sozinha no texto e se resolve sozinha quando não sobra linha incerta; só toca estado aberta. Em outro estado, ou resolvida por pessoa, não é reaberta. Complementar e sobrepujável: não trava o mandato, avisa.';



-- O PONTO da extração nova: chamado pelo gatilho do evento extracao_sombra (abaixo). A extração é a evidência e vale mais que a pendência: se a avaliação falhar, a extração FICA e o evento diz. NÃO se captura query_canceled (statement_timeout): o cancelamento é do chamador.
create or replace function fn_fato_avaliar_pendencia_da_extracao(p_documento_versao_id uuid, p_ator text default 'sistema:n8n')
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_tipo text; v_caso uuid; v_doc uuid; v_r jsonb; v_pend uuid; v_vigente uuid;
begin
  select d.tipo_taxonomia, d.caso_id, d.id into v_tipo, v_caso, v_doc from documento_versao dv join documento d on d.id = dv.documento_id where dv.id = p_documento_versao_id;
  if not fn_tipo_gera_fato(v_tipo) then
    return jsonb_build_object('avaliada', false, 'porque', 'tipo do documento não é de demonstração');
  end if;
  if not fn_fato_pode_escrever(v_caso) then
    -- (regra 7: a recusa deixa rastro, não é silêncio)
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (coalesce(fn_fato_ator(), p_ator), 'pendencia_conta_incerta_negada', 'documento_versao:' || p_documento_versao_id,
              jsonb_build_object('porque', 'sem permissão de escrita no mandato', 'ator_declarado', p_ator));
    return jsonb_build_object('avaliada', false, 'porque', 'sem permissão de escrita no mandato');
  end if;
  begin
    v_pend := fn_fato_pendencia_da_versao(p_documento_versao_id);
    -- A VERSÃO SUPERADA: quando esta é a vigente (fn_versao_atual), a pendência ABERTA das outras versões do documento perde o sentido (a leitura que ela julgava não é mais a que vale).
    v_vigente := fn_versao_atual(v_doc);
    if v_vigente = p_documento_versao_id then
      update pendencia
         set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:versao_superada',
             descricao = coalesce(descricao, '') || ' — Resolvida automaticamente: versão superada pela versão ' || p_documento_versao_id || ' do documento.'
       where documento_id = v_doc and estado = 'aberta' and motivo like 'fato:conta_incerta:%' and motivo <> 'fato:conta_incerta:' || p_documento_versao_id;
    end if;
    v_r := jsonb_build_object('avaliada', true, 'pendencia_id', v_pend);
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_ator, 'pendencia_conta_incerta_avaliada', 'documento_versao:' || p_documento_versao_id, v_r);
  exception
    when query_canceled then raise;
    when others then
      insert into evento_auditoria (ator, acao, entidade_ref, depois)
        values (p_ator, 'pendencia_conta_incerta_falhou', 'documento_versao:' || p_documento_versao_id,
                jsonb_build_object('sqlstate', sqlstate, 'erro', sqlerrm, 'porque', 'a extração foi gravada (e o fato, que é a view, está certo); só a pendência não foi avaliada.'));
      v_r := jsonb_build_object('avaliada', false, 'erro', sqlerrm);
  end;
  return v_r;
end $$;
comment on function fn_fato_avaliar_pendencia_da_extracao(uuid, text) is
  '0243: abre, atualiza ou fecha a pendência conta_canonica_incerta da versão recém-extraída (lendo o resolver) e baixa a das versões superadas, com o evento pendencia_conta_incerta_avaliada (a prova de que RODOU: regra 7). Tipo fora da lista: não faz nada. NÃO grava fato (o fato é a view).';

-- O GATILHO: o evento `extracao_sombra` é a prova de que fn_registrar_campos_extraidos gravou uma extração (grava DEPOIS do laço e da herança da seção). A pendência só olha a SEÇÃO das linhas (conta, heurística), nunca entidade nem período: por isso não depende de corrida com cadastro nenhum.
create or replace function fn_fato_extracao_nova()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare v_versao uuid;
begin
  -- entidade_ref = 'documento_versao:<uuid>'; qualquer outra forma (evento sintético, uuid inválido) não é extração de versão nenhuma: não faz nada, e NÃO derruba o evento
  if new.entidade_ref ~ '^documento_versao:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    v_versao := substr(new.entidade_ref, length('documento_versao:') + 1)::uuid;
    perform fn_fato_avaliar_pendencia_da_extracao(v_versao);
  end if;
  return null;
end $$;
revoke all on function fn_fato_pendencia_da_versao(uuid), fn_fato_avaliar_pendencia_da_extracao(uuid, text), fn_fato_extracao_nova() from public, anon, authenticated;
grant execute on function fn_fato_pendencia_da_versao(uuid) to service_role;
comment on function fn_fato_extracao_nova() is
  '0243: gatilho de evento_auditoria (acao = extracao_sombra): avalia a pendência conta_canonica_incerta da versão. NÃO grava fato.';

set local lock_timeout = '5s';
drop trigger if exists trg_fato_extracao_nova on evento_auditoria;
create trigger trg_fato_extracao_nova after insert on evento_auditoria
  for each row when (new.acao = 'extracao_sombra') execute function fn_fato_extracao_nova();
set local lock_timeout = 0;

-- -----------------------------------------------------------------------------
-- As VIEWS da sonda (padrão da 0224/0242: uma linha = uma garantia presente; rodam com os privilégios do dono). Nada preso a alias interno do resolver: a sonda afirma COMPORTAMENTO.
-- -----------------------------------------------------------------------------
-- fato_financeiro É uma view, é SECURITY_INVOKER e é o resolver LIDO (a view depende de fn_fato_resolver no catálogo: pg_depend, não texto nem alias).
create or replace view instalacao_sonda_fato_financeiro_view as
  select 1 as ok
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'fato_financeiro' and c.relkind = 'v'
     and exists (select 1 from unnest(c.reloptions) o where o in ('security_invoker=true', 'security_invoker=on'))
     and exists (select 1 from pg_rewrite r join pg_depend d on d.objid = r.oid and d.classid = 'pg_rewrite'::regclass
                  where r.ev_class = c.oid and d.refclassid = 'pg_proc'::regclass and d.refobjid = 'public.fn_fato_resolver(uuid)'::regprocedure)
     and (select count(*) from information_schema.columns k where k.table_schema = 'public' and k.table_name = 'fato_financeiro'
             and k.column_name in ('id', 'campo_extraido_id', 'documento_versao_id', 'conta_id', 'resolucao_metodo', 'entidade_id', 'entidade_motivo', 'periodo_id', 'periodo_motivo', 'valor', 'origem')) = 11;
comment on view instalacao_sonda_fato_financeiro_view is
  'Sonda da 0243: uma linha = fato_financeiro é uma VIEW com security_invoker ligado, que depende de fn_fato_resolver e expõe as colunas do fato. Zero linhas: virou tabela (e a cópia envelhece), perdeu o security_invoker (a view passa a rodar com o dono e PULA a RLS: o authenticated lê fato de todos os mandatos) ou deixou de ler o resolver.';

-- Só leitura, e só para quem deve: o authenticated lê (a RLS de quem lê vale), ninguém escreve, o anon não lê nada.
create or replace view instalacao_sonda_fato_financeiro_so_leitura as
  select 1 as ok
   where has_table_privilege('authenticated', 'public.fato_financeiro'::regclass, 'select')
     and not has_any_column_privilege('authenticated', 'public.fato_financeiro'::regclass, 'insert')
     and not has_any_column_privilege('authenticated', 'public.fato_financeiro'::regclass, 'update')
     and not has_table_privilege('authenticated', 'public.fato_financeiro'::regclass, 'delete')
     and not has_table_privilege('authenticated', 'public.fato_financeiro'::regclass, 'truncate')
     and not has_any_column_privilege('anon', 'public.fato_financeiro'::regclass, 'select')
     and not has_any_column_privilege('anon', 'public.fato_financeiro'::regclass, 'insert')
     and not has_any_column_privilege('anon', 'public.fato_financeiro'::regclass, 'update')
     and not has_function_privilege('anon', 'public.fn_fato_resolver(uuid)'::regprocedure, 'execute');
comment on view instalacao_sonda_fato_financeiro_so_leitura is
  'Sonda da 0243: uma linha = o authenticated lê fato_financeiro e não escreve, o anon não lê nem escreve e não executa o resolver. Zero linhas: o default de privilégio do Supabase (ALL ao authenticated e ao anon em objeto novo) voltou a valer.';

-- O RESOLVER não é SECURITY DEFINER: com definer ele leria campo_extraido, documento e entidade com o privilégio do dono e a RLS de quem lê sumiria, mesmo com a view em security_invoker.
create or replace view instalacao_sonda_fato_financeiro_resolver as
  select 1 as ok from pg_proc p
   where p.oid = 'public.fn_fato_resolver(uuid)'::regprocedure and not p.prosecdef and p.provolatile = 's';
comment on view instalacao_sonda_fato_financeiro_resolver is
  'Sonda da 0243: uma linha = fn_fato_resolver é SECURITY INVOKER e STABLE. Zero linhas: ele virou definer (a RLS some) ou volátil (a view deixa de ser leitura pura).';

-- O RESOLVER RESPONDE para a extração recente (regra 7): as 2 versões de demonstração mais novas que têm linha elegível (até 1.000 linhas: a sonda não cresce com o dado, 0132; a view inteira custa ~2,3 s com 82 mil linhas e cresce com elas, então a sonda NÃO a lê: ela lê o resolver da versão, que é o que a view lê,
-- e confere a ligação view-resolver pelo catálogo, acima) devolvem EXATAMENTE as linhas elegíveis delas, com o valor da linha, a conta que a seção dela manda, o método pela flag de inferida e identidade coerente (id nulo <=> origem nula <=> motivo). Não olha o evento extracao_sombra nem o corpo de nenhuma função.
create or replace view instalacao_sonda_fato_financeiro_responde as
  with v as materialized (
    select dv.id, d.tipo_taxonomia
      from documento_versao dv join documento d on d.id = dv.documento_id
     where fn_tipo_gera_fato(d.tipo_taxonomia)
       and (select count(*) from campo_extraido x where x.documento_versao_id = dv.id and x.valor_num is not null) between 1 and 1000
     order by dv.criada_em desc, dv.id limit 2),
  el as materialized (
    select ce.id, ce.valor_num, ce.secao_canonica, ce.secao_canonica_inferida, v.id as versao
      from v join campo_extraido ce on ce.documento_versao_id = v.id
     where fn_linha_vira_fato(v.tipo_taxonomia, ce.chave, ce.unidade, ce.valor_num)),
  fx as materialized (
    select r.* from v cross join lateral fn_fato_resolver(v.id) r)
  select 1 as ok
   where exists (select 1 from v)
     and not exists (
           select 1 from el where not exists (
             select 1 from fx left join conta_canonica c on c.codigo = fx.conta_id
              where fx.campo_id = el.id and fx.valor = el.valor_num
                and fx.resolucao_metodo = case when fx.conta_id is null then 'sem_conta' when el.secao_canonica_inferida then 'heuristica' else 'declarada' end
                and ((fx.conta_id is not null and c.secao_canonica = el.secao_canonica) or (fx.conta_id is null and not exists (select 1 from conta_canonica c2 where c2.secao_canonica = el.secao_canonica)))
                and (fx.entidade_id is null) = (fx.entidade_origem is null) and (fx.entidade_id is null) = (fx.entidade_motivo is not null)
                and (fx.periodo_id is null) = (fx.periodo_origem is null) and (fx.periodo_id is null) = (fx.periodo_motivo is not null)))
     and not exists (select 1 from fx where not exists (select 1 from el where el.id = fx.campo_id));
comment on view instalacao_sonda_fato_financeiro_responde is
  'Sonda da 0243: uma linha = existe extração recente com linha elegível e o resolver devolve, para as 2 versões de demonstração mais novas (até 1.000 linhas), exatamente as linhas elegíveis delas, com valor, conta pela seção, método e identidade coerentes. Zero linhas: o resolver não responde (quebrado, função sem EXECUTE), devolve linha que não é elegível, ou não há extração recente para medir (banco sem demonstração: ausente, não verde).';

create or replace view instalacao_sonda_fato_financeiro_pendencia_tipo as
  select 1 as ok where exists (select 1 from pg_enum e where e.enumtypid = 'pendencia_tipo'::regtype and e.enumlabel = 'conta_canonica_incerta');
comment on view instalacao_sonda_fato_financeiro_pendencia_tipo is
  'Sonda da 0243: uma linha = o rótulo conta_canonica_incerta existe em pendencia_tipo. Sem ele a extração nova com linha heurística tentaria abrir a pendência e falharia (a falha é engolida e vira o evento pendencia_conta_incerta_falhou).';

-- A LISTA DOS TIPOS, um a um e INDEPENDENTE do corpo da função: os 8 tipos de demonstração geram fato e 2 que NÃO podem gerar (Razão e Notas, da mesma categoria da taxonomia) não geram. Uma linha por resposta certa: 10 = a lista inteira.
create or replace view instalacao_sonda_fato_financeiro_tipos as
  select e.tipo::text as tipo
    from (values ('BALANCO', true), ('BALANCETE', true), ('COMBINADO', true), ('DRE', true), ('FLUXO_CAIXA', true), ('DVA', true), ('DMPL', true), ('DF_AUDITADA', true), ('RAZAO', false), ('NOTAS_EXPL', false)) e(tipo, gera)
   where fn_tipo_gera_fato(e.tipo) = e.gera;
comment on view instalacao_sonda_fato_financeiro_tipos is
  'Sonda da 0243: uma linha = fn_tipo_gera_fato dá a resposta certa para um dos 10 tipos (BALANCO, BALANCETE, COMBINADO, DRE, FLUXO_CAIXA, DVA, DMPL, DF_AUDITADA geram; RAZAO e NOTAS_EXPL não). Menos de 10: um tipo de demonstração perdeu o fato, ou o que é só evidência virou fato.';

grant select on instalacao_sonda_fato_financeiro_view, instalacao_sonda_fato_financeiro_so_leitura, instalacao_sonda_fato_financeiro_resolver, instalacao_sonda_fato_financeiro_responde,
                instalacao_sonda_fato_financeiro_pendencia_tipo, instalacao_sonda_fato_financeiro_tipos to authenticated, service_role;  -- service_role: grant_views_service_role (0214)

-- -----------------------------------------------------------------------------
-- A SONDA. Marcadores em CÓDIGO, nunca de comentário; nunca alias interno (regra 3): só nome de função e literal de motivo, que a constraint do desenho torna estáveis.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fato_financeiro_view', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_view', null, 1,
   'fato_financeiro deixou de ser view com security_invoker: ou voltou a ser cópia que envelhece, ou roda com o dono e PULA a RLS (o authenticated lê fato de todos os mandatos).', 'importante', 1105),
  ('fato_view_so_leitura', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_so_leitura', null, 1,
   'O authenticated ganhou escrita em fato_financeiro, perdeu a leitura, ou o anon ganhou leitura/execução do resolver (o default de privilégio do Supabase voltou a valer).', 'importante', 1106),
  ('fato_resolver_invoker', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_resolver', null, 1,
   'fn_fato_resolver virou SECURITY DEFINER (a RLS de quem lê some, mesmo com a view em security_invoker) ou deixou de ser STABLE.', 'importante', 1107),
  ('fato_resolver_responde', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_responde', null, 1,
   'O resolver (o que a view fato_financeiro lê) não responde para a extração recente: não devolve as linhas elegíveis das versões mais novas, ou devolve valor, conta ou identidade que discordam da linha, ou não há extração recente para medir (regra 7: o estágio que não responde não pode parecer limpo).', 'importante', 1108),
  ('fato_pendencia_gatilho', '0243', 'gatilho', 'evento_auditoria.trg_fato_extracao_nova', 'fn_fato_extracao_nova', null,
   'Sem o gatilho a extração nova não abre a pendência conta_canonica_incerta (linha por heurística ou sem conta fica sem aviso).', 'importante', 1109),
  ('fato_pendencia_gatilho_chama', '0243', 'corpo', 'fn_fato_extracao_nova', 'fn_fato_avaliar_pendencia_da_extracao(', null,
   'O gatilho existe mas não chama a avaliação da pendência: o evento extracao_sombra passa e nenhuma pendência abre, sem erro.', 'importante', 1110),
  ('fato_pendencia_tipo', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_pendencia_tipo', null, 1,
   'Sem o rótulo conta_canonica_incerta em pendencia_tipo a pendência da heurística não abre.', 'importante', 1111),
  ('tipos_que_geram_fato', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_tipos', null, 10,
   'A lista dos tipos de demonstração perdeu um tipo (linha de demonstração fica sem fato), ou ganhou Razão/Notas (o que é só evidência vira fato). Conferida tipo a tipo, não pelo corpo.', 'importante', 1112),
  ('fato_pendencia_le_o_resolver', '0243', 'corpo', 'fn_fato_pendencia_da_versao', 'fn_fato_resolver(', null,
   'A pendência precisa ler a conta de cada linha do resolver (a mesma resposta da view); outra fonte (cópia, recontagem própria) volta a divergir do fato.', 'importante', 1113),
  ('fato_pendencia_uma_por_versao', '0243', 'corpo', 'fn_fato_pendencia_da_versao', '''fato:conta_incerta:''', null,
   'A pendência da heurística é UMA por documento-versão (o motivo carrega a versão). Outro motivo = uma por linha (fila de ruído) ou nenhuma.', 'importante', 1114),
  ('fato_pendencia_chama_a_guarda', '0243', 'corpo', 'fn_fato_avaliar_pendencia_da_extracao', 'fn_fato_pode_escrever(', null,
   'fn_fato_avaliar_pendencia_da_extracao é security definer: sem a guarda de escrita, a extração de um mandato abriria pendência em outro.', 'importante', 1115),
  ('fato_guarda_de_escrita_corpo', '0243', 'corpo', 'fn_fato_pode_escrever', 'fn_pode_escrever_caso(p_caso)', null,
   'A guarda de escrita (serviço ou quem escreve no mandato) foi trocada (por `select true`, por exemplo): a função security definer abre pendência para qualquer chamador.', 'importante', 1116),
  ('fato_guarda_de_escrita_search_path', '0243', 'corpo', 'fn_fato_pode_escrever', 'SET search_path TO ''public'', ''pg_temp''', null,
   'Função security definer sem search_path fixo: um schema do chamador na frente do public sequestra fn_pode_escrever_caso.', 'importante', 1117),
  ('materializa_so_o_elegivel', '0243', 'corpo', 'fn_fato_resolver', 'fn_linha_vira_fato(', null,
   'A resolução precisa perguntar a fn_linha_vira_fato: sem isso virar fato é "tudo que tem valor" (Estoque, Razão, subtotal).', 'importante', 1118),
  ('materializa_periodo_pela_coluna', '0243', 'corpo', 'fn_fato_resolver', 'fn_periodo_canonico(', null,
   'O período de outro ano vem da forma canônica da coluna de ano puro (31/12/AAAA = AAAA) que um período do MESMO mandato tem; sem isso o balanço de duas colunas de ano atribui o saldo de 2024 a 2025.', 'importante', 1119),
  ('periodo_so_da_coluna_de_saldo', '0243', 'corpo', 'fn_fato_resolver', 'fn_coluna_e_saldo(', null,
   'A coluna que É o período do documento é a de SALDO (fn_coluna_e_saldo, 0201): Débito, Crédito, Orçado, Variação e percentual com o mesmo período dão fatos idênticos em (conta, entidade, período) e a soma dobra.', 'importante', 1120),
  ('periodo_parcial_nao_vai_para_o_ano', '0243', 'corpo', 'fn_fato_resolver', 'fn_periodo_e_parcial(', null,
   'Documento de período PARCIAL (balancete de junho) não dá a coluna "2025" ao período anual: o acumulado de junho virava a receita do ano.', 'importante', 1121),
  ('periodo_coluna_do_documento_so_se_unica', '0243', 'corpo', 'fn_fato_resolver', 'mais_de_uma_coluna_para_o_mesmo_periodo', null,
   'Com duas candidatas a ser a coluna do período do documento (Jun/2025 e 30/06/2025; Saldo final e Saldo atual) nenhuma é escolhida: ao acaso é número fabricado.', 'importante', 1122),
  ('entidade_pela_funcao_do_banco', '0243', 'corpo', 'fn_fato_resolver', 'fn_coluna_entidade(', null,
   'A entidade da coluna é a que fn_coluna_entidade (0023/0030, com fn_mesma_entidade) escolhe: um casamento de nome próprio errou "Alfa Comércio" x "ALFA COMERCIO DE ALIMENTOS LTDA".', 'importante', 1123),
  ('entidade_total_so_se_unica', '0243', 'corpo', 'fn_fato_resolver', 'coluna_total_ambigua', null,
   'fn_coluna_entidade entrega "a" coluna total sem ordem: com mais de uma coluna total no documento a escolha é arbitrária e a entidade fica sem coluna total.', 'importante', 1124)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0243', revisado_em = current_date,
       observacao = 'A 0243 cria fato_financeiro como VIEW (security_invoker) sobre fn_fato_resolver (o fato canônico acima de campo_extraido, igual ao do zero por construção), a pendência conta_canonica_incerta por gatilho em evento_auditoria (só extração nova), 6 views de sonda e 20 requisitos novos (ordem 1105-1124). Sem tabela, sem backfill, sem gatilho de materialização.'
 where id = true;

commit;
