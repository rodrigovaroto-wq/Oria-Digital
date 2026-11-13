-- Testes da 0301: fn_kit_do_caso reemitida sem varrer documento_versao inteira sob a RLS. Rodar via Supabase/test/run.sh (que aplica as migrations).
--
-- O QUE ESTE ARQUIVO PROVA (comportamento, regra 3):
--   E1  a resposta da fn_kit_do_caso é a MESMA da 0300, linha por linha (to_jsonb das 14 colunas), em mandatos que montam os sete estados do item
--       (faltante, dispensado, aguardando_extracao, recebido_sem_linha por falha / por arquivo_ilegivel / por documento_nao_extraido,
--       lido_sem_dado_por_natureza, extraido, conferido), o COMBINADO por estrutura e a reextração, lida COMO superusuário, COMO sócio e COMO analista
--       alocada. A referência é a cópia VERBATIM do corpo da 0300 (teste_kit_0300_ref): a 0300 foi substituída por esta migration, então o que ela
--       respondia só existe aqui.
--   E2  o custo: lida COMO sócio (a RLS que fazia a 0300 varrer documento_versao inteira), a função chama fn_versao_extracao_concluida no máximo
--       uma vez por versão dos documentos DO MANDATO, e não uma vez por versão do banco. Medido pelo contador de chamadas da transação
--       (track_functions), não por relógio: tempo varia por máquina, a contagem não.
--   E3  a sonda enxerga o requisito novo e o catálogo da 0300 segue inteiro.
-- Regra 4: o defeito é de plano de execução sob RLS e não é reproduzível com dado fabricado em tamanho de produção (2.247 versões). O que se afirma é a
-- contagem de chamadas, que é proporcional ao número de versões do banco; os arranjos são montados pelas funções de produção.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): ct301.medindo = on (PGOPTIONS='-c ct301.medindo=on') vira `raise warning` e CONTA (ct301.execucoes / ct301.falhas); sem a
-- variável, o assert é `raise exception`. O número reprovado por correção desligada está no cabeçalho da migration 0301.

\set ON_ERROR_STOP on

create or replace function teste_assert_0301(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('ct301.execucoes', (coalesce(nullif(current_setting('ct301.execucoes', true), ''), '0')::int + 1)::text, false);
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  elsif current_setting('ct301.medindo', true) = 'on' then
    perform set_config('ct301.falhas', (coalesce(nullif(current_setting('ct301.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- Executa a expressão COMO o papel (authenticated com o JWT do usuário) e volta ao superusuário. Devolve 'ok|<resultado>' ou '<sqlstate>|<mensagem>'.
create or replace function teste_exec_0301(p_uid uuid, p_papel text, p_expr text)
returns text language plpgsql as $$
declare v_r text; v_out text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then jsonb_build_object('role', p_papel)::text
                     else jsonb_build_object('sub', p_uid, 'role', p_papel)::text end, true);
  execute format('set local role %I', p_papel);
  begin
    execute 'select (' || p_expr || ')::text' into v_r;
    v_out := 'ok|' || coalesce(v_r, 'NULL');
  exception when others then
    v_out := sqlstate || '|' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  return v_out;
end $$;

delete from caso where nome like '0301 —%';
delete from auth.users where id in ('00000000-0000-0000-0000-00000301b001', '00000000-0000-0000-0000-00000301b002');
drop function if exists teste_kit_0300_ref(uuid);

-- A REFERÊNCIA: o corpo da fn_kit_do_caso da 0300, copiado verbatim (security invoker, mesma assinatura). Só o nome muda.
create or replace function teste_kit_0300_ref(p_caso uuid)
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
                      and exists (select 1 from documento_versao dv
                                   where dv.documento_id = s.doc and fn_versao_extracao_concluida(dv.id))
                      then 'lido_sem_dado_por_natureza'
                 when exists (select 1 from documento_versao dv
                               where dv.documento_id = s.doc and fn_versao_extracao_concluida(dv.id))
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
grant execute on function teste_kit_0300_ref(uuid) to authenticated;

-- A conta que o teste compara: as 14 colunas de cada linha, em ordem de tipo, como jsonb.
create or replace function teste_kit_0301(p_caso uuid, p_ref boolean) returns jsonb
language plpgsql stable as $$
declare v jsonb;
begin
  if p_ref then
    select coalesce(jsonb_agg(to_jsonb(f) order by f.tipo), '[]'::jsonb) into v from teste_kit_0300_ref(p_caso) f;
  else
    select coalesce(jsonb_agg(to_jsonb(f) order by f.tipo), '[]'::jsonb) into v from fn_kit_do_caso(p_caso) f;
  end if;
  return v;
end $$;
grant execute on function teste_kit_0301(uuid, boolean) to authenticated;

create or replace function teste_linhas_0301(p_n int, p_conf numeric) returns jsonb
language sql as $$
  select jsonb_agg(jsonb_build_object('ordem', g, 'chave', 'Conta ' || g, 'valor_texto', (g * 100)::text, 'valor_num', (g * 100)::text,
                                      'unidade', 'unidade', 'moeda', 'BRL', 'confianca', p_conf::text, 'secao_canonica', 'ativo_circulante'))
    from generate_series(1, p_n) g $$;

-- =============================================================================================================================
-- BLOCO 1 — os arranjos: três mandatos, os sete estados e o COMBINADO por estrutura
-- =============================================================================================================================
do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000301b001';
  u_ana   uuid := '00000000-0000-0000-0000-00000301b002';
  v_a uuid; v_b uuid; v_c uuid; v_vazio uuid; r jsonb; v_doc uuid; v_ver uuid; v_n int; v_estados text;
begin
  raise notice '--- 1. os arranjos: o Kit em todos os estados, como o 0300 o devolve ---';
  insert into auth.users (id, email) values (u_socio, 'socio@0301.local'), (u_ana, 'ana@0301.local');
  perform fn_definir_papel(u_socio, 'socio', 'teste 0301');
  perform fn_definir_papel(u_ana, 'analista');

  -- MANDATO A: BALANCO com dois documentos (um só registrado, outro com a falha de extração), DRE auto-aceita, FLUXO_CAIXA conferido por pessoa,
  -- CONTRATO_SOCIAL lido sem dado, MUTUOS com arquivo ilegível, COMBINADO por estrutura (um balanço com três empresas nas colunas); FAT_INTRAGRUPO sem documento.
  v_a := fn_upsert_caso('0301 — mandato A todos os estados');
  perform fn_alocar(v_a, u_ana);
  r := fn_registrar_documento(v_a, 'Alfa 0301 Ltda', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0301/bp1.pdf', 'bp1.pdf', true, 'HASH-0301-BP1', 'ok');
  r := fn_registrar_documento(v_a, 'Alfa 0301 Ltda', 'anual', '2024', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0301/bp2.pdf', 'bp2.pdf', true, 'HASH-0301-BP2', 'ok');
  perform fn_registrar_campos_extraidos((r ->> 'documento_versao_id')::uuid, '[]'::jsonb, 'N0', 'Arquivo ilegível: a leitura não devolveu nenhuma conta.');

  r := fn_registrar_documento(v_a, 'Alfa 0301 Ltda', 'anual', '2025', 'DRE', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0301/dre.pdf', 'dre.pdf', true, 'HASH-0301-DRE', 'ok');
  perform fn_registrar_campos_extraidos((r ->> 'documento_versao_id')::uuid, teste_linhas_0301(2, 0.98), 'N0');

  r := fn_registrar_documento(v_a, 'Alfa 0301 Ltda', 'anual', '2025', 'FLUXO_CAIXA', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0301/fc.pdf', 'fc.pdf', true, 'HASH-0301-FC', 'ok');
  perform fn_registrar_campos_extraidos((r ->> 'documento_versao_id')::uuid, teste_linhas_0301(2, 0.5), 'N0');
  perform fn_aceitar_extracao((r ->> 'documento_versao_id')::uuid, 'analista@oria', 'conferi');

  r := fn_registrar_documento(v_a, 'Alfa 0301 Ltda', 'anual', '2025', 'CONTRATO_SOCIAL', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0301/cs.pdf', 'cs.pdf', true, 'HASH-0301-CS', 'ok');
  perform fn_registrar_campos_extraidos((r ->> 'documento_versao_id')::uuid, '[]'::jsonb, 'N0', null, false, jsonb_build_object('contas_no_documento', 0));

  r := fn_registrar_documento(v_a, 'Beta 0301 Ltda', 'anual', '2025', 'MUTUOS', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0301/mu.pdf', 'mu.pdf', true, 'HASH-0301-MU', 'ok');
  perform fn_registrar_diagnostico((r ->> 'documento_id')::uuid, (r ->> 'documento_versao_id')::uuid, 'Beta 0301 Ltda', true, 'MUTUOS', 'anual', '2025',
                                   'ilegivel', 'Digitalização ilegível.', 'r', 'j');

  r := fn_registrar_documento(v_a, 'Grupo 0301', 'anual', '2025', 'BALANCO', 1.0, 'openai_conteudo', 'supabase_storage',
                              '0301/comb.pdf', 'comb.pdf', true, 'HASH-0301-COMB', 'ok');
  perform fn_registrar_campos_extraidos((r ->> 'documento_versao_id')::uuid, '[
    {"chave": "TOTAL DO ATIVO", "valor_num": "100", "confianca": "1.0", "entidade_coluna": "Col Alfa Ltda"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "100", "confianca": "1.0", "entidade_coluna": "Col Alfa Ltda"},
    {"chave": "TOTAL DO ATIVO", "valor_num": "200", "confianca": "1.0", "entidade_coluna": "Col Beta Ltda"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "200", "confianca": "1.0", "entidade_coluna": "Col Beta Ltda"},
    {"chave": "TOTAL DO ATIVO", "valor_num": "300", "confianca": "1.0", "entidade_coluna": "Col Gama Ltda"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "300", "confianca": "1.0", "entidade_coluna": "Col Gama Ltda"}
  ]'::jsonb, 'N0');
  r := fn_registrar_documento(v_a, 'Alfa 0301 Ltda', 'anual', '2025', 'FATURAMENTO_24M', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0301/fat.pdf', 'fat.pdf', true, 'HASH-0301-FAT', 'ok');
  perform fn_registrar_campos_extraidos((r ->> 'documento_versao_id')::uuid, teste_linhas_0301(2, 0.5), 'N0');
  perform fn_aceitar_extracao((r ->> 'documento_versao_id')::uuid, 'analista@oria', 'conferi');
  -- a reextração: o MESMO arquivo ganha versão nova, sem aceite de pessoa
  r := fn_registrar_documento(v_a, 'Alfa 0301 Ltda', 'anual', '2025', 'FLUXO_CAIXA', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0301/fc.pdf', 'fc.pdf', true, 'HASH-0301-FC', 'ok');
  perform fn_registrar_campos_extraidos((r ->> 'documento_versao_id')::uuid, teste_linhas_0301(2, 0.5), 'N0');

  select string_agg(distinct estado, ',' order by estado) into v_estados from fn_kit_do_caso(v_a);
  perform teste_assert_0301(v_estados like '%conferido%' and v_estados like '%extraido%' and v_estados like '%recebido_sem_linha%'
                            and v_estados like '%lido_sem_dado_por_natureza%' and v_estados like '%faltante%',
    'o arranjo A: o mandato mostra conferido, extraido, recebido_sem_linha, lido_sem_dado_por_natureza e faltante (o teste não compara um Kit trivial)', v_estados);
  perform teste_assert_0301((select estado from fn_kit_do_caso(v_a) where tipo = 'COMBINADO') <> 'faltante',
    'o arranjo A: o COMBINADO é cumprido por estrutura (o balanço de três empresas), que é o único caminho em que serve_como não é igualdade de tipo',
    (select estado from fn_kit_do_caso(v_a) where tipo = 'COMBINADO'));

  -- MANDATO B: registrado e não lido (aguardando), depois a conferência do lote declara documento_nao_extraido; e um item dispensado por pessoa.
  v_b := fn_upsert_caso('0301 — mandato B aguardando e nao extraido');
  r := fn_registrar_documento(v_b, 'Alfa 0301 Ltda', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0301/n1.pdf', 'n1.pdf', true, 'HASH-0301-N1', 'ok');
  r := fn_registrar_documento(v_b, 'Alfa 0301 Ltda', 'anual', '2025', 'DRE', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0301/n2.pdf', 'n2.pdf', true, 'HASH-0301-N2', 'ok');
  perform teste_assert_0301((select estado from fn_kit_do_caso(v_b) where tipo = 'BALANCO') = 'aguardando_extracao',
    'o arranjo B: registrado e não lido = aguardando_extracao', (select estado from fn_kit_do_caso(v_b) where tipo = 'BALANCO'));
  perform fn_conferir_lote(v_b);
  r := fn_registrar_documento(v_b, 'Alfa 0301 Ltda', 'anual', '2025', 'FLUXO_CAIXA', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0301/n3.pdf', 'n3.pdf', true, 'HASH-0301-N3', 'ok');
  perform teste_assert_0301((select estado from fn_kit_do_caso(v_b) where tipo = 'BALANCO') = 'recebido_sem_linha'
                            and (select estado from fn_kit_do_caso(v_b) where tipo = 'FLUXO_CAIXA') = 'aguardando_extracao',
    'o arranjo B: documento_nao_extraido declarado = recebido_sem_linha, e o documento que chegou depois segue aguardando',
    (select string_agg(tipo || '=' || estado, ',') from fn_kit_do_caso(v_b) where tipo in ('BALANCO', 'FLUXO_CAIXA')));
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, chave_motor, estado)
    values (v_b, 'completude', 'item_faltante', 'importante', true, 'Item obrigatório do Kit Básico ausente: MUTUOS',
            'completude:item_faltante:MUTUOS', 'aceita_com_ressalva');
  perform teste_assert_0301((select estado from fn_kit_do_caso(v_b) where tipo = 'MUTUOS') = 'dispensado',
    'o arranjo B: item sem documento com a decisão de pessoa de seguir sem = dispensado', (select estado from fn_kit_do_caso(v_b) where tipo = 'MUTUOS'));

  -- MANDATO C: sem nenhum documento (tudo faltante).
  v_vazio := fn_upsert_caso('0301 — mandato C vazio');
  perform teste_assert_0301((select count(*) from fn_kit_do_caso(v_vazio) where estado = 'faltante') = (select count(*) from fn_kit_do_caso(v_vazio)),
    'o arranjo C: o mandato sem documento devolve o Kit inteiro faltante', null);

  -- MANDATO D: para o E2, versões de OUTROS mandatos em número claramente maior que as do mandato lido (o que a 0300 varria sob a RLS).
  v_c := fn_upsert_caso('0301 — mandato D ruido de outros mandatos');
  for v_n in 1..12 loop
    r := fn_registrar_documento(v_c, 'Delta 0301 Ltda', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage',
                                '0301/d' || v_n || '.pdf', 'd' || v_n || '.pdf', true, 'HASH-0301-D' || v_n, 'ok');
    if v_n % 2 = 0 then
      perform fn_registrar_campos_extraidos((r ->> 'documento_versao_id')::uuid, teste_linhas_0301(1, 0.98), 'N0');
    end if;
  end loop;
  select count(*) into v_n from documento_versao dv join documento d on d.id = dv.documento_id where d.caso_id = v_vazio or d.caso_id = v_a;
  perform teste_assert_0301((select count(*) from documento_versao) > 2 * (select count(*) from documento_versao dv join documento d on d.id = dv.documento_id where d.caso_id = v_a),
    'o arranjo D: o banco tem mais que o DOBRO das versões do mandato A (é o que torna a contagem do E2 capaz de reprovar)',
    format('%s no banco, %s no mandato A', (select count(*) from documento_versao),
           (select count(*) from documento_versao dv join documento d on d.id = dv.documento_id where d.caso_id = v_a)));
end $$;

-- =============================================================================================================================
-- BLOCO 2 — E1: a mesma resposta da 0300, nos três mandatos, COMO superusuário, COMO sócio e COMO analista alocada
-- =============================================================================================================================
do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000301b001';
  u_ana   uuid := '00000000-0000-0000-0000-00000301b002';
  v_caso uuid; v_nome text; v_n int; v_res text;
begin
  raise notice '--- 2. E1: a resposta é a da 0300, linha por linha ---';
  foreach v_nome in array array['0301 — mandato A todos os estados', '0301 — mandato B aguardando e nao extraido', '0301 — mandato C vazio', '0301 — mandato D ruido de outros mandatos'] loop
    select id into v_caso from caso where nome = v_nome;
    select jsonb_array_length(teste_kit_0301(v_caso, true)) into v_n;
    perform teste_assert_0301(v_n = (select count(*) from taxonomia_tipo_documento where obrigatoriedade = 'obrigatorio'),
      format('E1 (%s): a referência devolve uma linha por tipo obrigatório (não é vazia)', v_nome), v_n::text);
    perform teste_assert_0301(teste_kit_0301(v_caso, false) = teste_kit_0301(v_caso, true),
      format('E1 (%s) COMO superusuário: as 14 colunas de todas as linhas são iguais às da 0300', v_nome),
      left(teste_kit_0301(v_caso, false)::text, 300));

    v_res := teste_exec_0301(u_socio, 'authenticated', format('select teste_kit_0301(%L::uuid, false) = teste_kit_0301(%L::uuid, true)', v_caso, v_caso));
    perform teste_assert_0301(v_res = 'ok|true', format('E1 (%s) COMO sócio (a RLS que mudava o plano): igual à 0300', v_nome), v_res);
    v_res := teste_exec_0301(u_ana, 'authenticated', format('select teste_kit_0301(%L::uuid, false) = teste_kit_0301(%L::uuid, true)', v_caso, v_caso));
    perform teste_assert_0301(v_res = 'ok|true', format('E1 (%s) COMO analista alocada: igual à 0300', v_nome), v_res);
  end loop;

  -- a analista NÃO alocada ao mandato A segue vendo zero linhas (o isolamento da 0300 intacto, e igual à referência)
  select id into v_caso from caso where nome = '0301 — mandato D ruido de outros mandatos';
  v_res := teste_exec_0301(u_ana, 'authenticated', format('select count(*) from fn_kit_do_caso(%L::uuid)', v_caso));
  perform teste_assert_0301(v_res = 'ok|0', 'E1: a analista de A pedindo o Kit de D (não alocada) recebe ZERO linhas — nunca "tudo faltante"', v_res);
  v_res := teste_exec_0301(u_ana, 'authenticated', format('select count(*) from teste_kit_0300_ref(%L::uuid)', v_caso));
  perform teste_assert_0301(v_res = 'ok|0', 'e a 0300 dava o mesmo (o isolamento é o mesmo)', v_res);
  -- mandato inexistente
  perform teste_assert_0301(jsonb_array_length(teste_kit_0301('00000000-0000-0000-0000-000000000301', false)) = 0
                            and jsonb_array_length(teste_kit_0301('00000000-0000-0000-0000-000000000301', true)) = 0,
    'E1: mandato inexistente devolve zero linhas nas duas', null);
end $$;

-- =============================================================================================================================
-- BLOCO 3 — E2: COMO sócio, a função só pergunta "a leitura concluiu" das versões do mandato lido
-- =============================================================================================================================
do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000301b001';
  v_a uuid; v_fn oid; v_antes bigint; v_depois bigint; v_res text; v_proprias int; v_banco int; v_chamadas bigint; v_nome text;
begin
  raise notice '--- 3. E2: o custo é do mandato, não do banco ---';
  set local track_functions = 'all';
  select 'public.fn_versao_extracao_concluida(uuid)'::regprocedure::oid into v_fn;
  foreach v_nome in array array['0301 — mandato A todos os estados', '0301 — mandato B aguardando e nao extraido'] loop
    select id into v_a from caso where nome = v_nome;
    select count(*) into v_proprias from documento_versao dv join documento d on d.id = dv.documento_id where d.caso_id = v_a;
    select count(*) into v_banco from documento_versao;
    v_antes := coalesce(pg_stat_get_xact_function_calls(v_fn), 0);
    v_res := teste_exec_0301(u_socio, 'authenticated', format('select count(*) from fn_kit_do_caso(%L::uuid)', v_a));
    v_depois := coalesce(pg_stat_get_xact_function_calls(v_fn), 0);
    v_chamadas := v_depois - v_antes;
    perform teste_assert_0301(v_res like 'ok|%', format('o arranjo (%s): a chamada COMO sócio funcionou', v_nome), v_res);
    perform teste_assert_0301(v_chamadas <= v_proprias,
      format('E2 (%s): COMO sócio, fn_versao_extracao_concluida roda no máximo uma vez por versão do MANDATO (%s versões dele, %s no banco)', v_nome, v_proprias, v_banco),
      format('%s chamadas', v_chamadas));
  end loop;
end $$;

-- =============================================================================================================================
-- BLOCO 4 — E3: a sonda enxerga o requisito novo e o catálogo da 0300 segue inteiro; limpeza
-- =============================================================================================================================
do $$
declare
  v_n int;
begin
  raise notice '--- 4. a sonda ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0301' and not presente;
  perform teste_assert_0301(v_n = 0, 'a sonda enxerga o requisito da 0301 (zero ausentes)', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0301';
  perform teste_assert_0301(v_n = 1, 'e o catálogo da 0301 tem 1 requisito (não está vazio)', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0300' and not presente;
  perform teste_assert_0301(v_n = 0, 'os 9 requisitos da 0300 seguem presentes no corpo reemitido (nenhum marcador se perdeu)', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0300';
  perform teste_assert_0301(v_n = 9, 'e o catálogo da 0300 continua com 9', v_n::text);
  perform teste_assert_0301((select provolatile = 's' and not prosecdef and proconfig is not null from pg_proc where oid = 'fn_kit_do_caso(uuid)'::regprocedure),
    'fn_kit_do_caso segue stable, security invoker e com search_path fixo', null);
  perform teste_assert_0301(not has_function_privilege('anon', 'fn_kit_do_caso(uuid)', 'execute') and not has_function_privilege('public', 'fn_kit_do_caso(uuid)', 'execute')
                            and has_function_privilege('authenticated', 'fn_kit_do_caso(uuid)', 'execute'),
    'e os grants da 0300 seguem: sem EXECUTE para anon/public, com para authenticated', null);

  delete from caso where nome like '0301 —%';
  delete from auth.users where id in ('00000000-0000-0000-0000-00000301b001', '00000000-0000-0000-0000-00000301b002');
  drop function teste_kit_0300_ref(uuid);

  raise notice 'EXECUCOES=% FALHAS=%', current_setting('ct301.execucoes', true), coalesce(current_setting('ct301.falhas', true), '0');
  if current_setting('ct301.medindo', true) is distinct from 'on' then
    raise notice 'TODOS OS TESTES DA 0301 PASSARAM';
  end if;
end $$;
