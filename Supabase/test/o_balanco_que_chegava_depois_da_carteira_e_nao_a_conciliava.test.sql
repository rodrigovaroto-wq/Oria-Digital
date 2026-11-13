-- Testes da 0278: a rodada de reconciliações (fn_reconciliar_caso) passa a conciliar a carteira de aging do mandato com o balanço.
-- Rodar via Supabase/test/run.sh (que aplica as migrations e carrega as fixtures dos books antes).
--
-- O QUE ESTE ARQUIVO PROVA (comportamento, regra 3):
--   1. A FORMA DE PRODUÇÃO DO DEFEITO: a carteira é importada ANTES do balanço (a entidade existe por outro documento, aqui uma DRE) e fica documento_ausente; o balanço chega;
--      até a rodada rodar nada muda; a rodada (fn_reconciliar_caso, a que o n8n chama uma vez por lote) concilia a carteira: confere (ok, diferença 0) ou diverge com a pendência
--      aberta pela DATA-BASE e o valor da diferença.
--   2. A rodada é idempotente: rodar de novo não duplica a pendência (a mesma, uma) nem muda o resultado.
--   3. Mandato SEM carteira: a rodada não grava nenhuma linha do aging (reconciliacao e pendencia), não devolve checagem do aging e `chamadas` é a de antes; e, para quem não pode
--      escrever, o retorno é exatamente o de antes (array vazio num mandato sem documento).
--   4. Quem não escreve no mandato (Leitura) NÃO derruba a rodada com 42501 por causa do aging: o retorno traz uma checagem `executado = false` com o motivo (sinal positivo:
--      estágio que não rodou não parece que rodou e não achou nada), e nada do aging é gravado. O Analista alocado e a conexão de serviço (o n8n) rodam o aging.
--   5. O aging roda UMA vez por rodada, não por chave: um mandato com várias chaves (entidades e períodos) e uma carteira grava as checagens de UMA carteira.
--   6. A chave de período (oria.periodo_chave, 0192) não vaza: vale '' depois da rodada, mesmo quando a chamada começa com uma chave posta. (Que a checagem do aging carregue a
--      chave do balanço lido e não herde a do último laço NÃO tem assert: medido, desligar a gravação da chave em fn_reconciliar_aging não muda nada, porque fn_registrar_reconciliacao
--      cai no período do documento; o assert seria vazio. Por construção a chave está '' no ponto da chamada: ela vem depois do reset da 0192.)
--   7. A sonda enxerga os requisitos da 0278. (A cobertura não rebaixa por um gatilho da própria tabela, trg_instalacao_cobertura_nao_regride: a migration usa `greatest` e foi
--      reaplicada por cima do banco completo em 0300 sem erro; não há assert, porque a sabotagem de rebaixar a cobertura é barrada pelo gatilho e não mediria nada.)
--
-- O QUE NÃO É PROVA DE PRODUÇÃO (regra 4). Produção tem a tabela aging_importado vazia (13/11/2026): não existe carteira real para reproduzir. O arranjo "carteira antes do
-- balanço" é construído com as MESMAS funções de produção (fn_registrar_documento, fn_aging_importar) e os valores são os do teste da 0277 (Clientes 24.917 R$ mil contra R$ 24.917.000,00).
-- A seção 4 usa um mandato com carteira e SEM documento nenhum, porque com documento de tipo conciliável o authenticated Leitura já leva 42501 das checagens que gravam
-- (a RLS de reconciliacao): o arranjo prova a guarda do aging, não é um caso de produção.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número reprovado por correção desligada está no cabeçalho de
-- Supabase/migrations/0278_o_balanco_que_chegava_depois_da_carteira_e_nao_a_conciliava.sql. `ct78.medindo = on` (PGOPTIONS='-c ct78.medindo=on') vira `raise warning`
-- e CONTA; sem a variável, o assert é `raise exception` (o CI).

\set ON_ERROR_STOP on

create or replace function teste_assert_0278(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('ct78.execucoes', (coalesce(nullif(current_setting('ct78.execucoes', true), ''), '0')::int + 1)::text, false);
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  elsif current_setting('ct78.medindo', true) = 'on' then
    perform set_config('ct78.falhas', (coalesce(nullif(current_setting('ct78.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

create or replace function teste_ln_0278(p_ordem int, p_chave text, p_valor numeric, p_unid text default 'milhar', p_col text default null) returns jsonb
language sql immutable as $$
  select jsonb_strip_nulls(jsonb_build_object('ordem', p_ordem, 'chave', p_chave, 'valor_num', p_valor::text, 'unidade', p_unid, 'periodo_coluna', p_col, 'confianca', '0.97')) $$;

-- O documento de uma empresa; devolve o id da ENTIDADE.
create or replace function teste_doc_0278(p_caso uuid, p_razao text, p_idx int, p_linhas jsonb, p_ptipo text default 'anual', p_pref text default '2025',
  p_tipo text default 'BALANCO') returns uuid
language plpgsql as $$
declare v_r jsonb;
begin
  v_r := fn_registrar_documento(p_caso, p_razao, p_ptipo, p_pref, p_tipo, 0.97, 'nome_arquivo', 'supabase_storage', '0278/' || p_idx || '.pdf',
                                'BP' || p_idx || '.pdf', true, 'HASH-0278-' || p_idx, 'ok');
  perform fn_registrar_campos_extraidos((v_r ->> 'documento_versao_id')::uuid, p_linhas, 'N2');
  return (select entidade_id from documento where id = (v_r ->> 'documento_id')::uuid);
end $$;

create or replace function teste_resumo_0278(p_data date, p_pos bigint) returns jsonb
language plpgsql immutable as $$
declare v_venc bigint := p_pos / 5 * 2; v_m1 bigint := p_pos / 2;
begin
  return jsonb_build_object(
    'data_base', p_data::text, 'titulos', 3, 'liquidados', 0,
    'positivos', jsonb_build_object('titulos', 3, 'saldo', p_pos::text, 'vencido', v_venc::text, 'vencido_pct', 40,
      'por_faixa', jsonb_build_object('a_vencer', (p_pos - v_venc)::text, '1_30', v_venc::text, '31_60', '0', '61_90', '0', '91_180', '0', '181_360', '0', 'acima_360', '0')),
    'negativos', jsonb_build_object('titulos', 0, 'saldo', '0', 'efeito', 'créditos e adiantamentos', 'maiores', '[]'::jsonb,
      'demais', jsonb_build_object('contrapartes', 0, 'saldo', '0', 'titulos', 0)),
    'emitidos_depois_da_data_base', jsonb_build_object('titulos', 0, 'saldo_positivos', '0', 'saldo_negativos', '0'),
    'documentos_invalidos', jsonb_build_object('titulos', 0),
    'contrapartes_com_saldo', 2, 'concentracao_top10_pct', 100,
    'maiores', jsonb_build_array(jsonb_build_object('contraparte', 'ACME LTDA', 'documento', null, 'saldo', v_m1::text, 'vencido', v_venc::text, 'titulos', 2)),
    'demais', jsonb_build_object('contrapartes', 1, 'saldo', (p_pos - v_m1)::text, 'vencido', '0', 'titulos', 1));
end $$;

-- Importa como o Sócio padrão do run.sh; devolve a resposta (com a conciliação da importação).
create or replace function teste_imp_0278(p_caso uuid, p_ent uuid, p_data date, p_pos bigint) returns jsonb
language plpgsql as $$
declare v_res jsonb := teste_resumo_0278(p_data, p_pos);
begin
  return fn_aging_importar(p_caso, p_ent, 'contas_a_receber', p_data, v_res,
    jsonb_build_object('formato', 'csv', 'sha256', repeat('a', 64), 'bytes', 2048, 'linhas', jsonb_build_object('corpo', 3)),
    jsonb_build_object('titulo', 3, 'motivos', '{}'::jsonb, 'saldo_titulos', p_pos::text,
      'titulos_com_saldo_negativo', jsonb_build_object('linhas', 0, 'saldo', '0'), 'conferencia_com_o_total_do_arquivo', jsonb_build_object('estado', 'confere')),
    jsonb_build_object('nome', 'ag.csv', 'sha256', repeat('a', 64), 'bytes', 2048, 'formato', 'csv'),
    current_setting('ct78.map_ar')::uuid);
end $$;

-- A checagem de um tipo no retorno de uma rodada (ou de uma importação: `conciliacao`), como a linha de reconciliacao que ela gravou.
create or replace function teste_rec_0278(p_checagens jsonb, p_tipo text) returns reconciliacao
language sql stable as $$
  select r.* from reconciliacao r
   where r.entidade_id = current_setting('ct78.ent')::uuid
     and r.id in (select (e ->> 'reconciliacao_id')::uuid from jsonb_array_elements(case when jsonb_typeof(p_checagens) = 'array' then p_checagens else '[]'::jsonb end) e where e ->> 'tipo' = p_tipo)
   limit 1 $$;

create or replace function teste_pend_0278(p_caso uuid, p_ent uuid, p_tipo text) returns int
language sql stable as $$
  select count(*)::int from pendencia where caso_id = p_caso and entidade_id = p_ent and motivo = 'reconciliacao:' || p_tipo and estado <> 'resolvida' $$;

-- Quantas linhas do aging o mandato tem em reconciliacao e em pendencia (a medida de "a rodada não tocou o aging").
create or replace function teste_n_aging_0278(p_caso uuid) returns int
language sql stable as $$
  select (select count(*) from reconciliacao where caso_id = p_caso and tipo like 'aging\_%')::int + (select count(*) from pendencia where caso_id = p_caso and motivo like 'reconciliacao:aging\_%')::int $$;

-- A rodada chamada COMO um usuário (authenticated + claims) ou como a conexão de serviço (p_user nulo: sem JWT e sem role): devolve 'ok|<json>' ou 'sqlstate|mensagem'.
create or replace function teste_rodada_0278(p_caso uuid, p_user uuid, p_chave_antes text default null) returns text
language plpgsql as $$
declare v_claims text := current_setting('request.jwt.claims', true); v_r jsonb;
begin
  if p_user is null then
    perform set_config('request.jwt.claims', '', true);
  else
    perform set_config('request.jwt.claims', jsonb_build_object('sub', p_user, 'role', 'authenticated')::text, true);
    set local role authenticated;
  end if;
  if p_chave_antes is not null then perform set_config('oria.periodo_chave', p_chave_antes, true); end if;
  v_r := fn_reconciliar_caso(p_caso);
  reset role;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  return 'ok|' || v_r::text;
exception when others then
  reset role;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  return sqlstate || '|' || sqlerrm;
end $$;

-- Limpeza de rodada anterior (o teste é reexecutável).
delete from caso where nome like '0278 —%';

do $$
declare
  c_ar constant text := 'contas_a_receber';
  v_a uuid; v_b uuid; v_c uuid; v_d uuid; v_e uuid; v_f uuid;
  e_ok uuid; e_div uuid; e_leit uuid; e_ana uuid; e_k1 uuid; e_k2 uuid; e_k3 uuid; e_srv uuid;
  u_leo uuid := '00000000-0000-0000-0000-000000278b01'; u_ana uuid := '00000000-0000-0000-0000-000000278b02';
  v_cab jsonb := '["Cliente0278","Vencimento","Saldo"]'; v_mapa jsonb := '{"contraparte":0,"vencimento":1,"saldo":2}'; v_fmt jsonb := '{"decimal":"virgula","datas":"dia_mes_ano"}';
  v_r jsonb; v_imp jsonb; v_t text; v_chk jsonb; v_chk2 jsonb; rr reconciliacao; v_n int; v_n2 int; v_m int; v_g uuid; v_def text; v_pend uuid; v_pend2 uuid; v_ch text;
begin
  insert into auth.users (id, email) values (u_leo, 'leo@0278.local'), (u_ana, 'ana@0278.local') on conflict (id) do nothing;
  perform fn_definir_papel(u_leo, 'leitura');
  perform fn_definir_papel(u_ana, 'analista');
  perform set_config('ct78.map_ar', (fn_mapeamento_confirmar(c_ar, v_cab, v_mapa, v_fmt) ->> 'id'), false);

  -- ================================================================== 1. A FORMA DE PRODUÇÃO: A CARTEIRA ANTES DO BALANÇO
  raise notice '--- 1. a carteira importada antes do balanço: a rodada a concilia quando o balanço chega ---';
  v_a := fn_upsert_caso('0278 — mandato A');
  -- A entidade existe por outro documento (uma DRE), como em produção: a carteira se importa por entidade, e o balanço ainda não veio.
  e_ok := teste_doc_0278(v_a, 'Alfa 0278 Ltda', 1, jsonb_build_array(teste_ln_0278(0, 'Receita líquida', 90000)), 'anual', '2025', 'DRE');
  e_div := teste_doc_0278(v_a, 'Beta 0278 Ltda', 2, jsonb_build_array(teste_ln_0278(0, 'Receita líquida', 90000)), 'anual', '2025', 'DRE');
  perform set_config('ct78.ent', e_ok::text, false);
  v_imp := teste_imp_0278(v_a, e_ok, '2025-12-31', 2491700000);          -- confere com 24.917 R$ mil
  rr := teste_rec_0278(v_imp -> 'conciliacao', 'aging_ar_clientes');
  perform teste_assert_0278(rr.resultado = 'precondicao_nao_satisfeita' and rr.motivo_precondicao = 'documento_ausente' and teste_pend_0278(v_a, e_ok, 'aging_ar_clientes') = 0,
    'a carteira importada sem balanço fica documento_ausente (sem pendência): o estado de partida do defeito', rr.resultado || ' | ' || coalesce(rr.motivo_precondicao, 'null'));
  perform set_config('ct78.ent', e_div::text, false);
  v_imp := teste_imp_0278(v_a, e_div, '2025-12-31', 2600000000);         -- diverge: 26.000.000 contra 24.917.000
  perform teste_assert_0278((teste_rec_0278(v_imp -> 'conciliacao', 'aging_ar_clientes')).motivo_precondicao = 'documento_ausente' and teste_pend_0278(v_a, e_div, 'aging_ar_clientes') = 0,
    'a segunda carteira (que vai divergir) também parte de documento_ausente', null);
  -- O balanço chega DEPOIS (o do mesmo ano e a mesma empresa), pelo caminho de produção.
  perform teste_doc_0278(v_a, 'Alfa 0278 Ltda', 3, jsonb_build_array(teste_ln_0278(0, 'Clientes - duplicatas a receber', 24917)));
  perform teste_doc_0278(v_a, 'Beta 0278 Ltda', 4, jsonb_build_array(teste_ln_0278(0, 'Clientes - duplicatas a receber', 24917)));
  perform teste_assert_0278((select count(*) from reconciliacao where caso_id = v_a and tipo = 'aging_ar_clientes' and resultado <> 'precondicao_nao_satisfeita') = 0
                            and teste_pend_0278(v_a, e_div, 'aging_ar_clientes') = 0,
    'antes da rodada nada muda: o balanço registrado, sozinho, não concilia a carteira (o defeito: só a importação ou uma chamada à mão conciliavam)', (select count(*)::text from reconciliacao where caso_id = v_a and tipo = 'aging_ar_clientes'));

  v_t := teste_rodada_0278(v_a, null);                                   -- a conexão de serviço (o n8n)
  perform teste_assert_0278(v_t like 'ok|%', 'a rodada do mandato com carteira roda sem erro', v_t);
  v_chk := substr(v_t, 4)::jsonb;
  perform set_config('ct78.ent', e_ok::text, false);
  rr := teste_rec_0278(v_chk -> 'checagens', 'aging_ar_clientes');
  perform teste_assert_0278(rr.resultado = 'ok' and rr.divergencia_abs = 0 and teste_pend_0278(v_a, e_ok, 'aging_ar_clientes') = 0,
    'depois da rodada a carteira que confere está conciliada: ok, diferença 0, sem pendência', rr.resultado || ' | ' || coalesce(rr.divergencia_abs::text, 'null'));
  perform teste_assert_0278(rr.documento_id = (select id from documento where caso_id = v_a and entidade_id = e_ok and tipo_taxonomia = 'BALANCO')
                            and rr.data_base = date '2025-12-31' and rr.classe = 'A',
    'e ela é conferida com o BALANÇO que chegou depois (não com a DRE), pela data-base da carteira', coalesce(rr.documento_id::text, 'null'));
  perform set_config('ct78.ent', e_div::text, false);
  rr := teste_rec_0278(v_chk -> 'checagens', 'aging_ar_clientes');
  perform teste_assert_0278(rr.resultado = 'divergente' and rr.divergencia_abs = 1083000 and teste_pend_0278(v_a, e_div, 'aging_ar_clientes') = 1,
    'a carteira que diverge abre a pendência com a diferença (R$ 1.083.000)', rr.resultado || ' | ' || coalesce(rr.divergencia_abs::text, 'null'));
  select id into v_pend from pendencia where caso_id = v_a and entidade_id = e_div and motivo = 'reconciliacao:aging_ar_clientes' and estado <> 'resolvida';
  perform teste_assert_0278((select p.data_base from pendencia p where p.id = v_pend) = date '2025-12-31' and (select p.descricao from pendencia p where p.id = v_pend) like '%R$ 1.083.000,00%'
                            and (select p.descricao from pendencia p where p.id = v_pend) like '%31/12/2025%',
    'a pendência é da data-base da carteira e o texto diz a data e o valor da diferença', (select descricao from pendencia where id = v_pend));
  perform teste_assert_0278((v_chk ->> 'executado')::boolean and (v_chk ->> 'chamadas')::int = jsonb_array_length(v_chk -> 'checagens') - 2,
    'o retorno mantém o formato (executado, chamadas, checagens) e `chamadas` conta UMA chamada por carteira vigente (2 carteiras = 2; cada uma devolve 2 checagens: clientes e adiantamentos)',
    (v_chk ->> 'chamadas') || ' x ' || jsonb_array_length(v_chk -> 'checagens'));

  -- ================================================================== 2. IDEMPOTÊNCIA
  raise notice '--- 2. rodar de novo não duplica a pendência ---';
  v_n := teste_n_aging_0278(v_a);
  v_t := teste_rodada_0278(v_a, null);
  v_chk2 := substr(v_t, 4)::jsonb;
  select id into v_pend2 from pendencia where caso_id = v_a and entidade_id = e_div and motivo = 'reconciliacao:aging_ar_clientes' and estado <> 'resolvida';
  perform teste_assert_0278(v_pend2 = v_pend and (select count(*) from pendencia where caso_id = v_a and motivo = 'reconciliacao:aging_ar_clientes') = 1,
    'a segunda rodada reaproveita a MESMA pendência (uma só, não duplica)', (select count(*)::text from pendencia where caso_id = v_a and motivo = 'reconciliacao:aging_ar_clientes'));
  perform set_config('ct78.ent', e_div::text, false);
  perform teste_assert_0278((teste_rec_0278(v_chk2 -> 'checagens', 'aging_ar_clientes')).resultado = 'divergente'
                            and (select count(*) from pendencia where caso_id = v_a and motivo like 'reconciliacao:aging\_%' and estado <> 'resolvida') = 1,
    'e o resultado é o mesmo: divergente, uma pendência aberta do aging no mandato inteiro', null);
  perform teste_assert_0278(teste_n_aging_0278(v_a) - v_n = 4,
    'a segunda rodada acrescenta só o histórico das 4 checagens (2 carteiras x clientes e adiantamentos); a pendência não cresce', (teste_n_aging_0278(v_a) - v_n)::text);

  -- ================================================================== 3. MANDATO SEM CARTEIRA: ZERO EFEITO
  raise notice '--- 3. mandato sem carteira: a rodada não toca o aging ---';
  v_b := fn_upsert_caso('0278 — mandato B (sem aging)');
  perform teste_doc_0278(v_b, 'Sem Carteira 0278 Ltda', 5, jsonb_build_array(teste_ln_0278(1, 'Total do Ativo', 1000, 'milhar', '31/12/2025'),
    teste_ln_0278(2, 'Total do Passivo e Patrimônio Líquido', 1000, 'milhar', '31/12/2025'), teste_ln_0278(3, 'Clientes', 100)));
  v_t := teste_rodada_0278(v_b, null);
  v_chk := substr(v_t, 4)::jsonb;
  perform teste_assert_0278(v_t like 'ok|%' and (v_chk ->> 'chamadas')::int = jsonb_array_length(v_chk -> 'checagens') and (v_chk ->> 'chamadas')::int > 0,
    'sem carteira, a rodada devolve o que sempre devolveu: uma chamada por checagem (chamadas = checagens, e há checagens)', (v_chk ->> 'chamadas') || ' x ' || jsonb_array_length(v_chk -> 'checagens'));
  perform teste_assert_0278(teste_n_aging_0278(v_b) = 0 and not exists (select 1 from jsonb_array_elements(v_chk -> 'checagens') e where e ->> 'tipo' like 'aging%' or e ->> 'executado' = 'false'),
    'sem carteira: nenhuma linha do aging em reconciliacao e pendencia, e nenhuma checagem do aging (nem o aviso de "não rodou") no retorno', teste_n_aging_0278(v_b)::text);
  -- Quem não escreve no mandato e o mandato não tem documento nenhum: a rodada devolve exatamente o retorno vazio de antes (sem o aviso do aging, que só existe com carteira).
  v_c := fn_upsert_caso('0278 — mandato C (vazio)');
  perform fn_alocar(v_c, u_leo);
  v_t := teste_rodada_0278(v_c, u_leo);
  perform teste_assert_0278(v_t like 'ok|%' and (substr(v_t, 4)::jsonb -> 'checagens') = '[]'::jsonb and (substr(v_t, 4)::jsonb ->> 'chamadas') = '0',
    'mandato sem carteira e sem documento, chamado por quem não escreve: checagens = [] e chamadas = 0 (o aviso do aging só existe com carteira)', v_t);

  -- ================================================================== 4. QUEM CHAMA
  raise notice '--- 4. a rodada nunca falha por causa do aging: Leitura é avisada, Analista e a conexão de serviço rodam ---';
  v_d := fn_upsert_caso('0278 — mandato D (Leitura)');
  perform fn_alocar(v_d, u_leo);
  -- Entidade sem documento (insert direto, só o arranjo): a carteira se importa como o Sócio padrão.
  insert into entidade (caso_id, razao_social) values (v_d, 'Leitura 0278 Ltda') returning id into e_leit;
  perform set_config('ct78.ent', e_leit::text, false);
  v_imp := teste_imp_0278(v_d, e_leit, '2025-12-31', 2491700000);
  v_n := teste_n_aging_0278(v_d);
  v_t := teste_rodada_0278(v_d, u_leo);
  perform teste_assert_0278(v_t like 'ok|%', 'o Leitura (authenticated, sem escrita) chama a rodada de um mandato com carteira e a rodada NÃO falha com 42501', left(v_t, 200));
  v_chk := case when v_t like 'ok|%' then substr(v_t, 4)::jsonb else '{}'::jsonb end;
  perform teste_assert_0278(exists (select 1 from jsonb_array_elements(coalesce(v_chk -> 'checagens', '[]'::jsonb)) e
                                     where e ->> 'tipo' = 'aging' and e ->> 'executado' = 'false' and (e ->> 'carteiras_vigentes')::int = 1 and e ->> 'motivo' like '%não foi conciliada nesta rodada%'),
    'e diz que o aging NÃO rodou, com o motivo e quantas carteiras ficaram de fora (sinal positivo, não silêncio)', left(coalesce(v_chk ->> 'checagens', 'null'), 300));
  perform teste_assert_0278(teste_n_aging_0278(v_d) = v_n, 'o Leitura não grava nada do aging (a rodada pulou, e disse que pulou)', (teste_n_aging_0278(v_d) - v_n)::text);
  -- O retorno ninguém lê (o nó n8n não o lê): o "não conciliou" também fica DURÁVEL, em evento_auditoria, mesmo para quem não escreve (o Leitura não insere lá: a função é definer).
  perform teste_assert_0278((select count(*) from evento_auditoria where entidade_ref = 'caso:' || v_d and acao = 'aging_nao_conciliado_na_rodada' and ator = 'sistema:reconciliacao'
                               and depois ->> 'sqlstate' = '42501' and (depois ->> 'carteiras_vigentes')::int = 1 and depois ->> 'motivo' like '%não foi conciliada nesta rodada%') = 1,
    'o aviso de permissão deixa rastro DURÁVEL: 1 evento aging_nao_conciliado_na_rodada no mandato, com o motivo, o sqlstate e as carteiras de fora', (select count(*)::text from evento_auditoria where entidade_ref = 'caso:' || v_d));
  -- O Analista alocado roda o aging (a função é definer) mesmo chamando COMO authenticated.
  v_e := fn_upsert_caso('0278 — mandato E (Analista)');
  perform fn_alocar(v_e, u_ana);
  e_ana := teste_doc_0278(v_e, 'Analista 0278 Ltda', 6, jsonb_build_array(teste_ln_0278(0, 'Receita líquida', 90000)), 'anual', '2025', 'DRE');
  perform set_config('ct78.ent', e_ana::text, false);
  perform teste_imp_0278(v_e, e_ana, '2025-12-31', 2491700000);
  perform teste_doc_0278(v_e, 'Analista 0278 Ltda', 7, jsonb_build_array(teste_ln_0278(0, 'Clientes - duplicatas a receber', 24917)));
  v_t := teste_rodada_0278(v_e, u_ana);
  v_chk := case when v_t like 'ok|%' then substr(v_t, 4)::jsonb else '{}'::jsonb end;
  perform teste_assert_0278(v_t like 'ok|%' and (teste_rec_0278(v_chk -> 'checagens', 'aging_ar_clientes')).resultado = 'ok'
                            and not exists (select 1 from jsonb_array_elements(v_chk -> 'checagens') e where e ->> 'executado' = 'false'),
    'o Analista alocado (authenticated) roda a rodada e a carteira é conciliada (ok), sem aviso de "não rodou"', left(v_t, 200));
  -- E a conexão de serviço (n8n: sem JWT) já foi exercitada na seção 1; aqui o contrário: uma importação SUBSTITUÍDA não é conciliada de novo nem conta como carteira vigente.
  v_f := fn_upsert_caso('0278 — mandato F (substituída)');
  e_srv := teste_doc_0278(v_f, 'Subst 0278 Ltda', 8, jsonb_build_array(teste_ln_0278(0, 'Receita líquida', 90000)), 'anual', '2025', 'DRE');
  perform set_config('ct78.ent', e_srv::text, false);
  perform teste_imp_0278(v_f, e_srv, '2025-12-31', 2600000000);
  perform teste_imp_0278(v_f, e_srv, '2025-12-31', 2491700000);           -- reimporta a mesma data-base: a primeira vira substituída
  perform teste_doc_0278(v_f, 'Subst 0278 Ltda', 9, jsonb_build_array(teste_ln_0278(0, 'Clientes - duplicatas a receber', 24917)));
  v_t := teste_rodada_0278(v_f, null);
  v_chk := substr(v_t, 4)::jsonb;
  perform teste_assert_0278((v_chk ->> 'chamadas')::int - (select count(*) from jsonb_array_elements(v_chk -> 'checagens') e where e ->> 'tipo' not like 'aging%')::int = 1
                            and (teste_rec_0278(v_chk -> 'checagens', 'aging_ar_clientes')).resultado = 'ok' and teste_pend_0278(v_f, e_srv, 'aging_ar_clientes') = 0,
    'só a carteira VIGENTE é conciliada (a substituída, de R$ 26 milhões, não reabre pendência): 1 chamada do aging e resultado ok', (v_chk ->> 'chamadas'));

  -- ================================================================== 5. UMA VEZ POR RODADA, NÃO POR CHAVE
  raise notice '--- 5. o aging roda uma vez por rodada ---';
  v_n2 := null;
  v_e := fn_upsert_caso('0278 — mandato G (várias chaves)');
  -- Três entidades e dois períodos de balanço: o laço de chaves visita muitas chaves; a carteira é uma só.
  e_k1 := teste_doc_0278(v_e, 'Chave Um 0278 Ltda', 10, jsonb_build_array(teste_ln_0278(0, 'Clientes - duplicatas a receber', 24917)), 'anual', '2025');
  perform teste_doc_0278(v_e, 'Chave Um 0278 Ltda', 11, jsonb_build_array(teste_ln_0278(0, 'Clientes - duplicatas a receber', 20000)), 'anual', '2024');
  e_k2 := teste_doc_0278(v_e, 'Chave Dois 0278 Ltda', 12, jsonb_build_array(teste_ln_0278(0, 'Clientes - duplicatas a receber', 100)), 'anual', '2025');
  e_k3 := teste_doc_0278(v_e, 'Chave Tres 0278 Ltda', 13, jsonb_build_array(teste_ln_0278(0, 'Clientes - duplicatas a receber', 100)), 'anual', '2024');
  perform set_config('ct78.ent', e_k1::text, false);
  perform teste_imp_0278(v_e, e_k1, '2025-12-31', 2491700000);
  v_n := (select count(*) from reconciliacao where caso_id = v_e and tipo like 'aging\_%');
  v_t := teste_rodada_0278(v_e, null);
  v_chk := substr(v_t, 4)::jsonb;
  perform teste_assert_0278((select count(*) from reconciliacao where caso_id = v_e and tipo like 'aging\_%') - v_n = 2
                            and (select count(*) from jsonb_array_elements(v_chk -> 'checagens') e where e ->> 'tipo' like 'aging\_%') = 2,
    'num mandato com várias chaves e UMA carteira a rodada grava as 2 checagens dessa carteira (clientes e adiantamentos), não uma vez por chave', ((select count(*) from reconciliacao where caso_id = v_e and tipo like 'aging\_%') - v_n)::text);
  perform teste_assert_0278((select count(*) from jsonb_array_elements(v_chk -> 'checagens') e where e ->> 'tipo' not like 'aging%') >= 6,
    'e o arranjo tem de fato várias chaves (a prova de "uma vez" não é vazia: pelo menos 6 checagens fora do aging)', (select count(*)::text from jsonb_array_elements(v_chk -> 'checagens') e where e ->> 'tipo' not like 'aging%'));

  -- ================================================================== 6. A CHAVE DE PERÍODO NÃO VAZA
  raise notice '--- 6. oria.periodo_chave (0192) não vaza ---';
  v_ch := '0278caca-0000-0000-0000-000000000000';
  v_t := teste_rodada_0278(v_e, null, v_ch);
  v_chk := substr(v_t, 4)::jsonb;
  perform teste_assert_0278(v_t like 'ok|%' and coalesce(current_setting('oria.periodo_chave', true), '') = '',
    'depois da rodada a chave vale vazio, mesmo começando de uma chave posta por fora (não herda a anterior nem deixa a do aging)', coalesce(current_setting('oria.periodo_chave', true), 'null'));

  -- ================================================================== 8. O AGING QUE LEVANTA EXCEÇÃO NÃO DERRUBA A RODADA
  raise notice '--- 8. exceção no aging: as checagens clássicas do lote ficam e o rastro fica ---';
  v_g := fn_upsert_caso('0278 — mandato H (aging que falha)');
  e_k1 := teste_doc_0278(v_g, 'Falha Um 0278 Ltda', 14, jsonb_build_array(teste_ln_0278(0, 'Receita líquida', 90000)), 'anual', '2025', 'DRE');
  perform teste_doc_0278(v_g, 'Falha Um 0278 Ltda', 15, jsonb_build_array(teste_ln_0278(1, 'Total do Ativo', 1000, 'milhar', '31/12/2025'),
    teste_ln_0278(2, 'Total do Passivo e Patrimônio Líquido', 1000, 'milhar', '31/12/2025'), teste_ln_0278(3, 'Clientes - duplicatas a receber', 24917)));
  perform set_config('ct78.ent', e_k1::text, false);
  perform teste_imp_0278(v_g, e_k1, '2025-12-31', 2491700000);
  -- Rodada normal: mede quantas linhas CLÁSSICAS (fora do aging) uma rodada grava neste mandato (a referência).
  v_n := (select count(*) from reconciliacao where caso_id = v_g and tipo not like 'aging\_%');
  v_t := teste_rodada_0278(v_g, null);
  v_n2 := (select count(*) from reconciliacao where caso_id = v_g and tipo not like 'aging\_%') - v_n;       -- clássicas gravadas por uma rodada sem sabotagem
  perform teste_assert_0278(v_t like 'ok|%' and v_n2 >= 6 and not exists (select 1 from evento_auditoria where entidade_ref = 'caso:' || v_g and acao = 'aging_nao_conciliado_na_rodada'),
    'referência: a rodada sem sabotagem grava as checagens clássicas (pelo menos 6, não vazio) e não deixa rastro de aging não conciliado', v_n2::text);
  -- Sabota o aging (levanta divisão por zero), SÓ dentro deste bloco: o DO é uma transação e a definição original é reposta logo abaixo.
  v_def := pg_get_functiondef('fn_reconciliar_aging(uuid)'::regprocedure);
  execute 'create or replace function fn_reconciliar_aging(p_aging_id uuid) returns jsonb language plpgsql as $f$ begin perform 1/0; return null; end $f$';
  v_n := (select count(*) from reconciliacao where caso_id = v_g and tipo not like 'aging\_%');
  v_m := (select count(*) from reconciliacao where caso_id = v_g and tipo like 'aging\_%');
  v_t := teste_rodada_0278(v_g, null);
  v_chk := case when v_t like 'ok|%' then substr(v_t, 4)::jsonb else '{}'::jsonb end;
  perform teste_assert_0278(v_t like 'ok|%', 'o aging levantando exceção NÃO derruba a rodada (a chamada não leva o erro)', left(v_t, 200));
  perform teste_assert_0278((select count(*) from reconciliacao where caso_id = v_g and tipo not like 'aging\_%') - v_n = v_n2,
    'e as checagens clássicas do lote continuam gravadas (a mesma contagem da rodada sem sabotagem)', ((select count(*) from reconciliacao where caso_id = v_g and tipo not like 'aging\_%') - v_n)::text || ' de ' || v_n2);
  perform teste_assert_0278((select count(*) from reconciliacao where caso_id = v_g and tipo like 'aging\_%') = v_m,
    'o aging que falhou não deixa linha pela metade (a subtransação o desfaz inteiro)', ((select count(*) from reconciliacao where caso_id = v_g and tipo like 'aging\_%') - v_m)::text);
  perform teste_assert_0278(exists (select 1 from jsonb_array_elements(coalesce(v_chk -> 'checagens', '[]'::jsonb)) e
                                     where e ->> 'tipo' = 'aging' and e ->> 'executado' = 'false' and e ->> 'sqlstate' = '22012' and e ->> 'motivo' like '%division by zero%'),
    'o retorno diz que o aging NÃO rodou, com o motivo e o sqlstate (22012)', left(coalesce(v_chk ->> 'checagens', 'null'), 200));
  perform teste_assert_0278((select count(*) from evento_auditoria where entidade_ref = 'caso:' || v_g and acao = 'aging_nao_conciliado_na_rodada' and ator = 'sistema:reconciliacao'
                               and depois ->> 'sqlstate' = '22012' and depois ->> 'motivo' like '%division by zero%' and (depois ->> 'carteiras_vigentes')::int = 1) = 1,
    'e deixa rastro DURÁVEL: 1 evento aging_nao_conciliado_na_rodada com o motivo, o sqlstate e as carteiras de fora', (select count(*)::text from evento_auditoria where entidade_ref = 'caso:' || v_g));
  execute v_def;                                                          -- repõe fn_reconciliar_aging
  perform teste_assert_0278(pg_get_functiondef('fn_reconciliar_aging(uuid)'::regprocedure) = v_def,
    'a sabotagem do teste foi desfeita (fn_reconciliar_aging volta a ser a original)', null);

  -- ================================================================== 7. A SONDA
  raise notice '--- 7. a sonda enxerga a 0278 ---';
  perform teste_assert_0278((select count(*) from fn_instalacao_conferir() where migration = '0278' and presente) = 5 and (select count(*) from fn_instalacao_conferir() where migration = '0278') = 5,
    'os 5 requisitos da 0278 existem no catálogo e estão presentes', (select string_agg(chave || ':' || presente, ', ') from fn_instalacao_conferir() where migration = '0278'));

  raise notice 'TODOS OS TESTES DA 0278 PASSARAM (% asserts executados)', current_setting('ct78.execucoes', true);
end $$;
