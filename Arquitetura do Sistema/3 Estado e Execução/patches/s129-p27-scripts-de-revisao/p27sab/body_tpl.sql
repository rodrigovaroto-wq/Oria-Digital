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

@@TIPO@@
@@ATOR@@
@@RES@@

-- -----------------------------------------------------------------------------
-- A VIEW. `fato_financeiro` é o resolver LIDO, não uma cópia: igual ao "do zero" por construção, sem gatilho, sem backfill, sem corrida. Mostra TODAS as versões de documento (como a tabela mostrava): quem consome escolhe a vigente com fn_versao_atual(documento_id) — a leitura de uma versão superada
-- continua evidência do que ela disse. Identidade da linha: `id` = `campo_extraido_id` (uma linha por linha elegível de campo_extraido).
-- SECURITY_INVOKER = TRUE é o que mantém a RLS: uma view comum roda com o privilégio do DONO e pularia a RLS de campo_extraido, documento_versao, documento, entidade e periodo (o authenticated leria fato de todos os mandatos). Exige PostgreSQL 15+ (o CI e o banco local são 16; produção: ver o cabeçalho). O resolver é SECURITY INVOKER (o default) pelo mesmo motivo.
-- -----------------------------------------------------------------------------
@@VIEW@@
revoke all on fato_financeiro from public, anon, authenticated;
grant select on fato_financeiro to authenticated, service_role;
comment on view fato_financeiro is
  '0243 (P27): o fato canônico ACIMA de campo_extraido: UMA linha por linha extraída elegível (fn_linha_vira_fato: demonstração, papel conta, com valor), com a identidade (conta = a SEÇÃO; entidade e período só quando uma função do banco decide sem ambiguidade, senão nulos com motivo). É uma VIEW sobre fn_fato_resolver (security_invoker: a RLS de quem lê vale): igual ao do zero por construção, nunca envelhece. TODAS as versões; a vigente é fn_versao_atual. origem = campo_extraido.origem_valor (extracao | transcricao_humana).';

-- -----------------------------------------------------------------------------
-- A PENDÊNCIA conta_canonica_incerta: UMA por documento-versão, só para extração NOVA. Lê o resolver (a conta de cada linha: heurística ou sem conta) e NÃO grava fato nenhum (o fato é a view). Convergente: reflete o estado atual das linhas de EXTRAÇÃO da versão (a transcrição humana, origem transcricao_humana, nunca entra).
-- -----------------------------------------------------------------------------
@@PEND@@

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
