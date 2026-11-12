-- Testes da 0277: a conciliação do aging da 0274 depois da revisão independente (3 ALTOS e 3 médios).
-- Rodar via Supabase/test/run.sh (que aplica as migrations e carrega as fixtures dos books antes).
--
-- O QUE ESTE ARQUIVO PROVA (comportamento, regra 3):
--   1. ALTO 1: num balanço COMPARATIVO ("multi 24,25", colunas 31/12/2024 e 31/12/2025) as carteiras de 2024 e de 2025 têm pendência própria: o ok de um
--      ano nunca resolve a divergência do outro, na importação e na rodada do mandato (fn_reconciliar_aging_do_caso, que visita por data-base crescente).
--      TETO MEDIDO: duas datas-base do MESMO ano (31/12 e 30/06) continuam compartilhando a pendência (a busca por período compatível é por ano).
--      E importar aging não muda o resultado das checagens clássicas do mandato (o `periodo` data-base entra nos laços de períodos compatíveis).
--   2. ALTO 2: pai e filhas de Fornecedores/Clientes NA FORMA DE PRODUÇÃO (mesma `secao` ou `secao` nula; o valor do pai é a soma das filhas) valem uma vez.
--      Pai que as filhas cobrem em parte vale sozinho e AVISA; pai que as filhas excedem não é subtotal: todas entram e AVISA, e o aviso chega à descrição.
--   3. ALTO 3: balanço que só existe como coluna de um combinado de OUTRA empresa do grupo concilia (e a descrição diz de quem é); o da própria entidade vence;
--      documento de outra empresa SEM coluna desta entidade não vale (documento_ausente, sem pendência).
--   4. Médios: conta de ESTOQUE com "cliente"/"fornecedor" no rótulo fica fora (por seção em texto e por secao_canonica de outro lado; secao_canonica NULA não exclui);
--      o resumo que não se amarra ao aplicador é recusado na função e na CHECK da tabela.
--
-- DE ONDE VÊM AS FIXTURES (regra 4: nada inventado para provar bug de produção). As FORMAS vêm de produção, lidas em 12/11/2026 (leitura, nenhuma escrita):
--   "Fornecedores" 24.549 = "Fornecedores nacionais" 16.843 + "Fornecedores intragrupo" 3.600 + "Fornecedores no exterior - resinas" 4.106 (R$ mil, 31/12/2024, ordem 33-36);
--   "Fornecedores" 1.892 = "Fornecedores de EPC e equipamentos" 1.892; "Fornecedores" 3.966 com a única filha "Fornecedores - silvicultura e colheita" 2.934 (seção Passivo
--   Circulante); "Clientes - duplicatas a receber - mercado interno" 24.861 ao lado de "Duplicatas a receber de clientes - mercado interno" 35.044; "MERCADORIA EM GARANTIA/CONSERTO
--   A RECEBER(FORNECEDOR)" na seção ESTOQUE. Os NÚMEROS de aging são montados aqui (não há arquivo de aging real: DM7 pendente) a partir do valor do balanço.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número reprovado por correção desligada está no cabeçalho de
-- Supabase/migrations/0277_o_aging_que_apagava_a_divergencia_de_um_ano_e_somava_o_pai_com_as_filhas.sql. `ct77.medindo = on` (PGOPTIONS='-c ct77.medindo=on') vira `raise warning`
-- e CONTA; sem a variável, o assert é `raise exception` (o CI).

\set ON_ERROR_STOP on

create or replace function teste_assert_0277(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('ct77.execucoes', (coalesce(nullif(current_setting('ct77.execucoes', true), ''), '0')::int + 1)::text, false);
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  elsif current_setting('ct77.medindo', true) = 'on' then
    perform set_config('ct77.falhas', (coalesce(nullif(current_setting('ct77.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- A linha de campo_extraido no formato de produção.
create or replace function teste_ln_0277(p_ordem int, p_chave text, p_valor numeric, p_unid text default 'milhar', p_col text default null,
  p_ent_col text default null, p_secao text default null, p_canon text default null) returns jsonb
language sql immutable as $$
  select jsonb_strip_nulls(jsonb_build_object('ordem', p_ordem, 'chave', p_chave, 'valor_num', p_valor::text, 'unidade', p_unid, 'periodo_coluna', p_col,
                                              'entidade_coluna', p_ent_col, 'secao', p_secao, 'secao_canonica', p_canon, 'confianca', '0.97')) $$;

-- O documento de balanço de uma empresa; devolve o id da ENTIDADE.
create or replace function teste_bal_0277(p_caso uuid, p_razao text, p_idx int, p_linhas jsonb, p_ptipo text default 'anual', p_pref text default '2025',
  p_tipo text default 'BALANCO') returns uuid
language plpgsql as $$
declare v_r jsonb;
begin
  v_r := fn_registrar_documento(p_caso, p_razao, p_ptipo, p_pref, p_tipo, 0.97, 'nome_arquivo', 'supabase_storage', '0277/' || p_idx || '.pdf',
                                'BP' || p_idx || '.pdf', true, 'HASH-0277-' || p_idx, 'ok');
  perform fn_registrar_campos_extraidos((v_r ->> 'documento_versao_id')::uuid, p_linhas, 'N2');
  return (select entidade_id from documento where id = (v_r ->> 'documento_id')::uuid);
end $$;

-- A versão atual do documento de uma entidade (o primeiro do tipo).
create or replace function teste_ver_0277(p_caso uuid, p_ent uuid, p_tipo text default 'BALANCO') returns uuid
language sql stable as $$
  select fn_versao_atual(d.id) from documento d where d.caso_id = p_caso and d.entidade_id = p_ent and d.tipo_taxonomia = p_tipo order by d.criado_em, d.id limit 1 $$;

-- O resumo de um aging coerente (formato de Leitor/lib/aging.mjs) e o do aplicador amarrado a ele (Leitor/lib/mapeamento.mjs).
create or replace function teste_resumo_0277(p_data date, p_pos bigint, p_neg bigint default 0) returns jsonb
language plpgsql immutable as $$
declare v_venc bigint := p_pos / 5 * 2; v_m1 bigint := p_pos / 2;
begin
  return jsonb_build_object(
    'data_base', p_data::text,
    'titulos', 3 + case when p_neg < 0 then 1 else 0 end, 'liquidados', 0,
    'positivos', jsonb_build_object('titulos', 3, 'saldo', p_pos::text, 'vencido', v_venc::text, 'vencido_pct', 40,
      'por_faixa', jsonb_build_object('a_vencer', (p_pos - v_venc)::text, '1_30', v_venc::text, '31_60', '0', '61_90', '0', '91_180', '0', '181_360', '0', 'acima_360', '0')),
    'negativos', jsonb_build_object('titulos', case when p_neg < 0 then 1 else 0 end, 'saldo', p_neg::text, 'efeito', 'créditos e adiantamentos',
      'maiores', case when p_neg < 0 then jsonb_build_array(jsonb_build_object('contraparte', 'CLIENTE CREDOR', 'documento', null, 'saldo', p_neg::text, 'titulos', 1)) else '[]'::jsonb end,
      'demais', jsonb_build_object('contrapartes', 0, 'saldo', '0', 'titulos', 0)),
    'emitidos_depois_da_data_base', jsonb_build_object('titulos', 0, 'saldo_positivos', '0', 'saldo_negativos', '0'),
    'documentos_invalidos', jsonb_build_object('titulos', 0),
    'contrapartes_com_saldo', 2, 'concentracao_top10_pct', 100,
    'maiores', jsonb_build_array(jsonb_build_object('contraparte', 'ACME LTDA', 'documento', null, 'saldo', v_m1::text, 'vencido', v_venc::text, 'titulos', 2)),
    'demais', jsonb_build_object('contrapartes', 1, 'saldo', (p_pos - v_m1)::text, 'vencido', '0', 'titulos', 1));
end $$;

create or replace function teste_aplic_0277(p_resumo jsonb) returns jsonb
language sql immutable as $$
  select jsonb_build_object('titulo', (p_resumo ->> 'titulos')::int, 'motivos', '{}'::jsonb,
    'saldo_titulos', ((p_resumo #>> '{positivos,saldo}')::numeric + (p_resumo #>> '{negativos,saldo}')::numeric)::text,
    'titulos_com_saldo_negativo', jsonb_build_object('linhas', (p_resumo #>> '{negativos,titulos}')::int, 'saldo', p_resumo #>> '{negativos,saldo}'),
    'conferencia_com_o_total_do_arquivo', jsonb_build_object('estado', 'confere')) $$;

-- Importa como o Sócio padrão do run.sh (o papel já é medido pela 0274); devolve a resposta. p_aplic nulo = o coerente com o resumo.
create or replace function teste_imp_0277(p_caso uuid, p_ent uuid, p_tipo text, p_data date, p_pos bigint, p_neg bigint default 0, p_aplic jsonb default null,
  p_resumo jsonb default null) returns jsonb
language plpgsql as $$
declare v_res jsonb := coalesce(p_resumo, teste_resumo_0277(p_data, p_pos, p_neg));
begin
  return fn_aging_importar(p_caso, p_ent, p_tipo, p_data, v_res,
    jsonb_build_object('formato', 'csv', 'sha256', repeat('a', 64), 'bytes', 2048, 'linhas', jsonb_build_object('corpo', 3)),
    coalesce(p_aplic, teste_aplic_0277(v_res)),
    jsonb_build_object('nome', 'ag.csv', 'sha256', repeat('a', 64), 'bytes', 2048, 'formato', 'csv'),
    current_setting('ct77.map_' || case p_tipo when 'contas_a_pagar' then 'ap' else 'ar' end)::uuid);
end $$;

-- A mesma importação, devolvendo 'sqlstate|mensagem' em vez de estourar.
create or replace function teste_tenta_0277(p_caso uuid, p_ent uuid, p_tipo text, p_data date, p_pos bigint, p_neg bigint default 0, p_aplic jsonb default null,
  p_resumo jsonb default null) returns text
language plpgsql as $$
begin
  perform teste_imp_0277(p_caso, p_ent, p_tipo, p_data, p_pos, p_neg, p_aplic, p_resumo);
  return 'ok';
exception when others then
  return sqlstate || '|' || sqlerrm;
end $$;

create or replace function teste_rec_0277(p_imp jsonb, p_tipo text) returns reconciliacao
language sql stable as $$
  select r.* from reconciliacao r
   where r.id = (select (e ->> 'reconciliacao_id')::uuid from jsonb_array_elements(case when jsonb_typeof(p_imp -> 'conciliacao') = 'array' then p_imp -> 'conciliacao' else '[]'::jsonb end) e where e ->> 'tipo' = p_tipo) $$;

create or replace function teste_pend_0277(p_caso uuid, p_ent uuid, p_tipo text) returns int
language sql stable as $$
  select count(*)::int from pendencia where caso_id = p_caso and entidade_id = p_ent and motivo = 'reconciliacao:' || p_tipo and estado <> 'resolvida' $$;

-- Limpeza de rodada anterior (o teste é reexecutável).
delete from aging_importado;
delete from evento_auditoria where acao = 'aging_importado' or acao like 'reconciliacao\_aging\_%';
delete from reconciliacao where tipo like 'aging\_a%';
delete from pendencia where motivo like 'reconciliacao:aging\_a%';
delete from caso where nome like '0277 —%';

do $$
declare
  v_a uuid;
  c_ar constant text := 'contas_a_receber';
  c_ap constant text := 'contas_a_pagar';
  e_cmp uuid; e_cmp2 uuid; e_ano uuid; e_pf1 uuid; e_pf2 uuid; e_pf3 uuid; e_pf4 uuid; e_pf5 uuid; e_cl uuid; e_ex uuid; e_cn uuid; e_ct uuid;
  e_alfa uuid; e_beta uuid; e_gama uuid; e_prop uuid; e_aplic uuid; e_clw uuid;
  v_map_ar uuid; v_map_ap uuid;
  v_cab jsonb := '["Cliente0277","Vencimento","Saldo"]'; v_mapa jsonb := '{"contraparte":0,"vencimento":1,"saldo":2}'; v_fmt jsonb := '{"decimal":"virgula","datas":"dia_mes_ano"}';
  v_r jsonb; v_r2 jsonb; rr reconciliacao; l record; v_t text; v_n int; v_ver uuid; v_antes jsonb; v_depois jsonb; v_pend_antes int; v_pend_depois int; v_res text;
  v_id uuid;
begin
  v_a := fn_upsert_caso('0277 — mandato A');
  v_map_ar := (fn_mapeamento_confirmar(c_ar, v_cab, v_mapa, v_fmt) ->> 'id')::uuid;
  v_map_ap := (fn_mapeamento_confirmar(c_ap, v_cab, v_mapa, v_fmt) ->> 'id')::uuid;
  perform set_config('ct77.map_ar', v_map_ar::text, false);
  perform set_config('ct77.map_ap', v_map_ap::text, false);

  -- ================================================================== 1. ALTO 1: A PENDÊNCIA É DA CARTEIRA, NÃO DO DOCUMENTO
  raise notice '--- 1. balanço comparativo (multi 24,25): carteiras de 2024 e 2025 têm pendência própria ---';
  e_cmp := teste_bal_0277(v_a, 'Comparativa Alfa 0277 Ltda', 1, jsonb_build_array(
    teste_ln_0277(0, 'Clientes - duplicatas a receber', 21902, 'milhar', '31/12/2024'), teste_ln_0277(1, 'Clientes - duplicatas a receber', 24917, 'milhar', '31/12/2025')),
    'multi', '24,25');
  -- A carteira de 2024 DIVERGE (22.000.000 contra 21.902.000); a de 2025 CONFERE (24.917.000).
  v_r := teste_imp_0277(v_a, e_cmp, c_ar, '2024-12-31', 2200000000);
  rr := teste_rec_0277(v_r, 'aging_ar_clientes');
  perform teste_assert_0277(rr.resultado = 'divergente' and rr.divergencia_abs = 98000 and teste_pend_0277(v_a, e_cmp, 'aging_ar_clientes') = 1,
    'a carteira de 31/12/2024 diverge em R$ 98.000 e abre a pendência', rr.resultado || ' | ' || coalesce(rr.divergencia_abs::text, 'null'));
  v_r2 := teste_imp_0277(v_a, e_cmp, c_ar, '2025-12-31', 2491700000);
  perform teste_assert_0277((teste_rec_0277(v_r2, 'aging_ar_clientes')).resultado = 'ok', 'a carteira de 31/12/2025 confere com a coluna 31/12/2025', (teste_rec_0277(v_r2, 'aging_ar_clientes')).resultado);
  perform teste_assert_0277(teste_pend_0277(v_a, e_cmp, 'aging_ar_clientes') = 1,
    'o ok de 2025 NÃO resolve a divergência de 2024: a pendência segue aberta', teste_pend_0277(v_a, e_cmp, 'aging_ar_clientes')::text);
  perform teste_assert_0277((select descricao from pendencia where caso_id = v_a and entidade_id = e_cmp and motivo = 'reconciliacao:aging_ar_clientes' and estado <> 'resolvida') like '%31/12/2024%'
                            and (select descricao from pendencia where caso_id = v_a and entidade_id = e_cmp and motivo = 'reconciliacao:aging_ar_clientes' and estado <> 'resolvida') not like '%31/12/2025%',
    'e a descrição dela é a de 2024 (o ano novo não reescreve o texto do velho)', (select descricao from pendencia where caso_id = v_a and entidade_id = e_cmp and motivo = 'reconciliacao:aging_ar_clientes' and estado <> 'resolvida'));
  v_r := fn_reconciliar_aging_do_caso(v_a)::jsonb;
  perform teste_assert_0277(teste_pend_0277(v_a, e_cmp, 'aging_ar_clientes') = 1,
    'a rodada do mandato (fn_reconciliar_aging_do_caso, que visita por data-base crescente: 2024 e depois 2025) também deixa a de 2024 aberta', teste_pend_0277(v_a, e_cmp, 'aging_ar_clientes')::text);
  -- Corrige 2024: agora fecha.
  v_r := teste_imp_0277(v_a, e_cmp, c_ar, '2024-12-31', 2190200000);
  perform teste_assert_0277(teste_pend_0277(v_a, e_cmp, 'aging_ar_clientes') = 0, 'corrigida a carteira de 2024, a pendência fecha (o sintoma sumiu)', teste_pend_0277(v_a, e_cmp, 'aging_ar_clientes')::text);
  -- O sentido contrário: 2025 diverge, 2024 (importada depois) confere.
  e_cmp2 := teste_bal_0277(v_a, 'Comparativa Bravo 0277 Ltda', 2, jsonb_build_array(
    teste_ln_0277(0, 'Clientes - duplicatas a receber', 21902, 'milhar', '31/12/2024'), teste_ln_0277(1, 'Clientes - duplicatas a receber', 24917, 'milhar', '31/12/2025')),
    'multi', '24,25');
  v_r := teste_imp_0277(v_a, e_cmp2, c_ar, '2025-12-31', 2600000000);
  v_r2 := teste_imp_0277(v_a, e_cmp2, c_ar, '2024-12-31', 2190200000);
  perform teste_assert_0277(teste_pend_0277(v_a, e_cmp2, 'aging_ar_clientes') = 1 and (teste_rec_0277(v_r2, 'aging_ar_clientes')).resultado = 'ok',
    'sentido contrário: o ok de 2024, importado DEPOIS, não resolve a divergência de 2025', teste_pend_0277(v_a, e_cmp2, 'aging_ar_clientes')::text);
  perform teste_assert_0277((select count(distinct p.id) from pendencia p where p.caso_id = v_a and p.entidade_id = e_cmp2 and p.motivo = 'reconciliacao:aging_ar_clientes') = 1
                            and (select pe.referencia from pendencia p join periodo pe on pe.id = p.periodo_id where p.caso_id = v_a and p.entidade_id = e_cmp2 and p.motivo = 'reconciliacao:aging_ar_clientes' and p.estado <> 'resolvida') = '2025-12-31',
    'a pendência aberta é do período da carteira (data-base 2025-12-31), o efeito declarado na migration', null);
  v_r := teste_imp_0277(v_a, e_cmp2, c_ar, '2025-12-31', 2491700000);
  perform teste_assert_0277(teste_pend_0277(v_a, e_cmp2, 'aging_ar_clientes') = 0, 'corrigida a de 2025, fecha', null);
  perform teste_assert_0277((select count(*) from periodo where caso_id = v_a and tipo = 'data-base' and referencia in ('2024-12-31', '2025-12-31')) = 2,
    'o período da carteira é criado UMA vez por data-base (2 linhas em periodo para 2 datas, depois de 6 importações)', (select count(*)::text from periodo where caso_id = v_a and tipo = 'data-base'));

  -- TETO MEDIDO: o MESMO ano, datas-base diferentes, compartilham a pendência (fn_registrar_reconciliacao acha por ano). Documentado, não corrigido.
  e_ano := teste_bal_0277(v_a, 'Anual Charlie 0277 Ltda', 3, jsonb_build_array(teste_ln_0277(0, 'Clientes - duplicatas a receber', 24917)));
  v_r := teste_imp_0277(v_a, e_ano, c_ar, '2025-12-31', 2600000000);
  v_r2 := teste_imp_0277(v_a, e_ano, c_ar, '2025-06-30', 2491700000);
  perform teste_assert_0277(teste_pend_0277(v_a, e_ano, 'aging_ar_clientes') = 1 and (teste_rec_0277(v_r2, 'aging_ar_clientes')).motivo_precondicao = 'sem_periodo_par',
    'TETO (1) da 0274 que continua: 31/12 divergente e 30/06 (sem par) do MESMO ano compartilham UMA pendência', teste_pend_0277(v_a, e_ano, 'aging_ar_clientes')::text);

  -- Importar aging não muda as checagens clássicas do mandato (o período data-base entra nos laços de períodos compatíveis).
  perform fn_reconciliar_caso(v_a);
  v_antes := (select coalesce(jsonb_object_agg(tipo, resultado), '{}'::jsonb) from (select distinct on (tipo) tipo, resultado from reconciliacao
               where caso_id = v_a and tipo not like 'aging\_%' order by tipo, criado_em desc, cmin::text::int desc) x);
  v_pend_antes := (select count(*) from pendencia where caso_id = v_a and motivo not like 'reconciliacao:aging\_%' and estado <> 'resolvida');
  e_aplic := teste_bal_0277(v_a, 'Neutra Delta 0277 Ltda', 4, jsonb_build_array(teste_ln_0277(0, 'Clientes - duplicatas a receber', 24917, 'milhar', '31/12/2025'),
                                                                                 teste_ln_0277(1, 'Clientes - duplicatas a receber', 21902, 'milhar', '31/12/2024')), 'multi', '24,25');
  perform fn_reconciliar_caso(v_a);
  v_antes := (select coalesce(jsonb_object_agg(tipo, resultado), '{}'::jsonb) from (select distinct on (tipo) tipo, resultado from reconciliacao
               where caso_id = v_a and tipo not like 'aging\_%' order by tipo, criado_em desc, cmin::text::int desc) x);
  v_pend_antes := (select count(*) from pendencia where caso_id = v_a and motivo not like 'reconciliacao:aging\_%' and estado <> 'resolvida');
  v_r := teste_imp_0277(v_a, e_aplic, c_ar, '2025-12-31', 2491700000);
  v_r := teste_imp_0277(v_a, e_aplic, c_ar, '2024-12-31', 2190200000);
  perform fn_reconciliar_caso(v_a);
  v_depois := (select coalesce(jsonb_object_agg(tipo, resultado), '{}'::jsonb) from (select distinct on (tipo) tipo, resultado from reconciliacao
               where caso_id = v_a and tipo not like 'aging\_%' order by tipo, criado_em desc, cmin::text::int desc) x);
  v_pend_depois := (select count(*) from pendencia where caso_id = v_a and motivo not like 'reconciliacao:aging\_%' and estado <> 'resolvida');
  perform teste_assert_0277(v_antes = v_depois and v_pend_antes = v_pend_depois,
    'importar aging NÃO muda o resultado (por tipo) nem a contagem de pendências das checagens clássicas do mandato', v_antes::text || ' | ' || v_depois::text || ' | ' || v_pend_antes || ' x ' || v_pend_depois);

  -- ================================================================== 2. ALTO 2: O PAI QUE SOMAVA COM AS FILHAS (a forma de PRODUÇÃO)
  raise notice '--- 2. pai e filhas de Fornecedores/Clientes: a forma de produção (mesma seção, seção nula) ---';
  -- Mesma `secao` em todas (Passivo Circulante) e o valor do pai é a soma exata das filhas (24.549 = 16.843 + 3.600 + 4.106).
  e_pf1 := teste_bal_0277(v_a, 'Pai Um 0277 Ltda', 5, jsonb_build_array(
    teste_ln_0277(33, 'Fornecedores', 24549, 'milhar', '31/12/2024', null, 'Passivo Circulante', 'passivo_circulante'),
    teste_ln_0277(34, 'Fornecedores nacionais', 16843, 'milhar', '31/12/2024', null, 'Passivo Circulante', 'passivo_circulante'),
    teste_ln_0277(35, 'Fornecedores intragrupo', 3600, 'milhar', '31/12/2024', null, 'Passivo Circulante', 'passivo_circulante'),
    teste_ln_0277(36, 'Fornecedores no exterior - resinas', 4106, 'milhar', '31/12/2024', null, 'Passivo Circulante', 'passivo_circulante')), 'multi', '24,25');
  v_ver := teste_ver_0277(v_a, e_pf1);
  select count(*), sum(valor_num), min(chave) into v_n, rr.divergencia_abs, v_t from fn_aging_linhas_do_balanco(v_ver, 'fornecedores', null, '31/12/2024');
  perform teste_assert_0277(v_n = 1 and rr.divergencia_abs = 24549 and v_t = 'Fornecedores', 'mesma secao no pai e nas 3 filhas: o pai vale sozinho (24.549), as filhas não somam de novo',
    v_n || ' linhas, soma ' || coalesce(rr.divergencia_abs::text, 'null'));
  v_r := teste_imp_0277(v_a, e_pf1, c_ap, '2024-12-31', 2454900000);
  rr := teste_rec_0277(v_r, 'aging_ap_fornecedores');
  perform teste_assert_0277(rr.resultado = 'ok' and rr.divergencia_abs = 0 and teste_pend_0277(v_a, e_pf1, 'aging_ap_fornecedores') = 0,
    'e a carteira a pagar de R$ 24.549.000,00 CONFERE com o balanço (antes: 49.098 contra 24.549, divergência falsa)', rr.resultado || ' | ' || coalesce(rr.divergencia_abs::text, 'null') || ' | ' || coalesce(rr.descricao, ''));
  -- Seção nula e ordem nula (o arranjo que a extração deixa quando não lê a ordem).
  e_pf2 := teste_bal_0277(v_a, 'Pai Dois 0277 Ltda', 6, jsonb_build_array(
    teste_ln_0277(null, 'Fornecedores', 6611, 'milhar', '31/12/2025'), teste_ln_0277(null, 'Fornecedores nacionais', 4211, 'milhar', '31/12/2025'),
    teste_ln_0277(null, 'Fornecedores intragrupo', 2400, 'milhar', '31/12/2025')), 'multi', '24,25');
  select count(*), min(chave) into v_n, v_t from fn_aging_linhas_do_balanco(teste_ver_0277(v_a, e_pf2), 'fornecedores', null, '31/12/2025');
  perform teste_assert_0277(v_n = 1 and v_t = 'Fornecedores', 'seção nula e SEM ordem: o pai ainda vale sozinho (a prova não depende da ordem)', v_n || ' linhas');
  -- Filha única com o mesmo valor.
  e_pf3 := teste_bal_0277(v_a, 'Pai Tres 0277 Ltda', 7, jsonb_build_array(
    teste_ln_0277(16, 'Fornecedores', 1892, 'milhar', '31/12/2025'), teste_ln_0277(17, 'Fornecedores de EPC e equipamentos', 1892, 'milhar', '31/12/2025')), 'multi', '24,25');
  select count(*), sum(valor_num) into v_n, rr.divergencia_abs from fn_aging_linhas_do_balanco(teste_ver_0277(v_a, e_pf3), 'fornecedores', null, '31/12/2025');
  perform teste_assert_0277(v_n = 1 and rr.divergencia_abs = 1892, 'filha única com o valor do pai (1.892 = 1.892): conta uma vez', v_n || ' linhas, soma ' || coalesce(rr.divergencia_abs::text, 'null'));
  -- Pai que as filhas COBREM EM PARTE (3.966 contra a única filha 2.934): vale sozinho e AVISA.
  e_pf4 := teste_bal_0277(v_a, 'Pai Quatro 0277 Ltda', 8, jsonb_build_array(
    teste_ln_0277(24, 'Fornecedores', 3966, 'milhar', '31/12/2025', null, 'Passivo Circulante', 'passivo_circulante'),
    teste_ln_0277(25, 'Fornecedores - silvicultura e colheita', 2934, 'milhar', '31/12/2025', null, 'Passivo Circulante', 'passivo_circulante')), 'multi', '24,25');
  select count(*), sum(valor_num), max(aviso) into v_n, rr.divergencia_abs, v_t from fn_aging_linhas_do_balanco(teste_ver_0277(v_a, e_pf4), 'fornecedores', null, '31/12/2025');
  perform teste_assert_0277(v_n = 1 and rr.divergencia_abs = 3966 and v_t like '%entrou sozinho%cobre(m) só parte%',
    'pai que as filhas cobrem em parte (3.966 contra 2.934): vale sozinho e o AVISO diz isso', v_n || ' | ' || coalesce(v_t, 'sem aviso'));
  v_r := teste_imp_0277(v_a, e_pf4, c_ap, '2025-12-31', 400000000);
  rr := teste_rec_0277(v_r, 'aging_ap_fornecedores');
  perform teste_assert_0277(rr.resultado = 'divergente' and rr.descricao like '%Atenção na leitura do balanço:%entrou sozinho%',
    'a descrição da divergência carrega o aviso do pai que não fecha (não é escolha em silêncio)', rr.descricao);
  -- Pai que as filhas EXCEDEM (24.861 contra 35.044): não é subtotal; todas entram e AVISA.
  e_pf5 := teste_bal_0277(v_a, 'Pai Cinco 0277 Ltda', 9, jsonb_build_array(
    teste_ln_0277(15, 'Clientes - duplicatas a receber - mercado interno', 24861, 'milhar', '31/12/2024', null, 'Ativo Circulante', 'ativo_circulante'),
    teste_ln_0277(25, 'Duplicatas a receber de clientes - mercado interno', 35044, 'milhar', '31/12/2024', null, 'Ativo Circulante', 'ativo_circulante'),
    teste_ln_0277(26, 'Duplicatas a receber de clientes - mercado externo', 5080, 'milhar', '31/12/2024', null, 'Ativo Circulante', 'ativo_circulante')), 'multi', '24,25');
  select count(*), max(aviso) into v_n, v_t from fn_aging_linhas_do_balanco(teste_ver_0277(v_a, e_pf5), 'clientes', null, '31/12/2024');
  perform teste_assert_0277(v_n = 3 and v_t like '%parece o total%mais que ele%em dobro%', 'pai que as filhas EXCEDEM não é subtotal: as 3 linhas entram e o AVISO diz que pode estar em dobro', v_n || ' | ' || coalesce(v_t, 'sem aviso'));
  v_r := teste_imp_0277(v_a, e_pf5, c_ar, '2024-12-31', 6498500000);
  rr := teste_rec_0277(v_r, 'aging_ar_clientes');
  perform teste_assert_0277(rr.descricao like '%Atenção na leitura do balanço:%parece o total%', 'e a descrição da conciliação carrega esse aviso, ok ou divergente', rr.resultado || ' | ' || rr.descricao);
  -- Clientes de nome de manual seguido de linhas SEM o nome dele: a janela por ordem (100 = 70 + 30).
  e_cl := teste_bal_0277(v_a, 'Janela Seis 0277 Ltda', 10, jsonb_build_array(
    teste_ln_0277(5, 'Clientes', 100, 'milhar', '31/12/2025', null, 'Ativo Circulante', 'ativo_circulante'),
    teste_ln_0277(6, 'Duplicatas a receber - mercado interno', 70, 'milhar', '31/12/2025', null, 'Ativo Circulante', 'ativo_circulante'),
    teste_ln_0277(7, 'Duplicatas a receber - exportação', 30, 'milhar', '31/12/2025', null, 'Ativo Circulante', 'ativo_circulante')), 'multi', '24,25');
  select count(*), sum(valor_num) into v_n, rr.divergencia_abs from fn_aging_linhas_do_balanco(teste_ver_0277(v_a, e_cl), 'clientes', null, '31/12/2025');
  perform teste_assert_0277(v_n = 1 and rr.divergencia_abs = 100, '"Clientes" 100 seguido de duas duplicatas (70 + 30) sem o nome dele: pela ordem, o pai vale sozinho', v_n || ' linhas, soma ' || coalesce(rr.divergencia_abs::text, 'null'));
  -- A mesma conta com dois nomes de manual (CLIENTES e DUPLICATAS A RECEBER, o mesmo valor ao centavo), com e sem ordem.
  e_clw := teste_bal_0277(v_a, 'Dois Nomes 0277 Ltda', 11, jsonb_build_array(
    teste_ln_0277(36, 'CLIENTES', 17978205.57, 'unidade', null, null, 'CLIENTES'), teste_ln_0277(37, 'DUPLICATAS A RECEBER', 17978205.57, 'unidade', null, null, 'DUPLICATAS A RECEBER')));
  select count(*) into v_n from fn_aging_linhas_do_balanco(teste_ver_0277(v_a, e_clw), 'clientes', null, null);
  perform teste_assert_0277(v_n = 1, 'CLIENTES e DUPLICATAS A RECEBER com o mesmo valor (com ordem 36/37): contam uma vez', v_n::text);
  e_ex := teste_bal_0277(v_a, 'Dois Nomes Sem Ordem 0277 Ltda', 12, jsonb_build_array(
    teste_ln_0277(null, 'CLIENTES', 17978205.57, 'unidade', null, null, 'ATIVO'), teste_ln_0277(null, 'DUPLICATAS A RECEBER', 17978205.57, 'unidade', null, null, 'ATIVO')));
  select count(*) into v_n from fn_aging_linhas_do_balanco(teste_ver_0277(v_a, e_ex), 'clientes', null, null);
  perform teste_assert_0277(v_n = 1, 'e o mesmo sem `ordem` (extração que não a leu): contam uma vez', v_n::text);
  -- Duas contas DIFERENTES que somam: não há pai, e a regra não inventa um (Clientes nacionais 100 + Clientes exterior 60).
  e_cn := teste_bal_0277(v_a, 'Irmas 0277 Ltda', 13, jsonb_build_array(
    teste_ln_0277(1, 'Clientes nacionais', 100, 'milhar', null, null, 'Ativo Circulante', 'ativo_circulante'), teste_ln_0277(2, 'Clientes exterior', 60, 'milhar', null, null, 'Ativo Circulante', 'ativo_circulante')));
  select count(*), sum(valor_num) into v_n, rr.divergencia_abs from fn_aging_linhas_do_balanco(teste_ver_0277(v_a, e_cn), 'clientes', null, null);
  perform teste_assert_0277(v_n = 2 and rr.divergencia_abs = 160, 'controle: duas contas irmãs (nenhuma é o nome da outra) somam as duas (160): a regra não inventa pai', v_n || ' linhas, soma ' || coalesce(rr.divergencia_abs::text, 'null'));
  -- Controle: a forma antiga que já funcionava (filhas com secao = nome do pai).
  e_ct := teste_bal_0277(v_a, 'Forma Antiga 0277 Ltda', 14, jsonb_build_array(
    teste_ln_0277(1, 'Fornecedores', 100, 'milhar', null, null, 'Passivo Circulante'), teste_ln_0277(2, 'Fornecedores nacionais', 60, 'milhar', null, null, 'Fornecedores'),
    teste_ln_0277(3, 'Fornecedores estrangeiros', 40, 'milhar', null, null, 'Fornecedores')));
  select count(*), sum(valor_num) into v_n, rr.divergencia_abs from fn_aging_linhas_do_balanco(teste_ver_0277(v_a, e_ct), 'fornecedores', null, null);
  perform teste_assert_0277(v_n = 1 and rr.divergencia_abs = 100, 'controle: a forma antiga (filhas com secao = nome do pai) continua valendo o pai sozinho', v_n || ' linhas, soma ' || coalesce(rr.divergencia_abs::text, 'null'));

  -- ================================================================== 3. MÉDIO: O LADO DO BALANÇO E A SEÇÃO DE ESTOQUE
  raise notice '--- 3. a conta de ESTOQUE com "fornecedor"/"cliente" no rótulo não é o conceito ---';
  e_gama := teste_bal_0277(v_a, 'Estoque Sete 0277 Ltda', 15, jsonb_build_array(
    teste_ln_0277(1, 'Fornecedores', 1000, 'milhar', null, null, 'Passivo Circulante', 'passivo_circulante'),
    teste_ln_0277(2, 'MERCADORIA EM GARANTIA/CONSERTO A RECEBER(FORNECEDOR)', 500, 'milhar', null, null, 'ESTOQUE EM GARANTIA/CONSERTO', 'ativo_circulante'),
    teste_ln_0277(3, 'Mercadoria de fornecedor em poder de terceiros', 7, 'milhar', null, null, 'ESTOQUE', null)));   -- (esta fica fora por seção em texto)
  select count(*), sum(valor_num) into v_n, rr.divergencia_abs from fn_aging_linhas_do_balanco(teste_ver_0277(v_a, e_gama), 'fornecedores', null, null);
  perform teste_assert_0277(v_n = 1 and rr.divergencia_abs = 1000, 'conta de ESTOQUE com "(FORNECEDOR)" fica fora, por secao_canonica de outro lado E por seção em texto, mesmo sem secao_canonica', v_n || ' linhas, soma ' || coalesce(rr.divergencia_abs::text, 'null'));
  e_clw := teste_bal_0277(v_a, 'Estoque Nove 0277 Ltda', 20, jsonb_build_array(
    teste_ln_0277(1, 'Duplicatas a receber', 900, 'milhar', null, null, 'Ativo Circulante', 'ativo_circulante'),
    teste_ln_0277(2, 'ESTOQUE EM DEMONSTRAÇÃO COM CLIENTES', 40, 'milhar', null, null, 'ESTOQUE', null)));
  select count(*), sum(valor_num) into v_n, rr.divergencia_abs from fn_aging_linhas_do_balanco(teste_ver_0277(v_a, e_clw), 'clientes', null, null);
  perform teste_assert_0277(v_n = 1 and rr.divergencia_abs = 900, 'estoque em demonstração "COM CLIENTES" (seção ESTOQUE, secao_canonica nula) fica fora de Clientes só pela seção em texto', v_n || ' linhas, soma ' || coalesce(rr.divergencia_abs::text, 'null'));
  e_beta := teste_bal_0277(v_a, 'Lado Oito 0277 Ltda', 16, jsonb_build_array(
    teste_ln_0277(1, 'Clientes', 900, 'milhar', null, null, null, null), teste_ln_0277(2, 'Clientes diversos (conta de passivo)', 50, 'milhar', null, null, null, 'passivo_circulante')));
  select count(*), sum(valor_num) into v_n, rr.divergencia_abs from fn_aging_linhas_do_balanco(teste_ver_0277(v_a, e_beta), 'clientes', null, null);
  perform teste_assert_0277(v_n = 1 and rr.divergencia_abs = 900, 'secao_canonica de passivo fora de Clientes; e secao_canonica NULA não exclui (a "Clientes" sem classificação fica: teto declarado)', v_n || ' linhas, soma ' || coalesce(rr.divergencia_abs::text, 'null'));

  -- ================================================================== 4. ALTO 3: O BALANÇO DO GRUPO É A FONTE DA ENTIDADE QUE NÃO TEM O PRÓPRIO
  raise notice '--- 4. o balanço combinado de outra empresa do grupo concilia a controlada que só existe como coluna ---';
  -- O combinado do grupo é um BALANCO (do mesmo tipo que o próprio virá a ser) e MAIS NOVO: só a preferência pelo próprio, e não a ordem do tipo nem a data, o deixa em segundo.
  perform teste_bal_0277(v_a, 'Grupo Holding 0277 SA', 17, jsonb_build_array(
    teste_ln_0277(1, 'Clientes', 5000, 'milhar', null, 'Controlada Alfa 0277 Ltda', 'Ativo Circulante', 'ativo_circulante'),
    teste_ln_0277(2, 'Clientes', 9000, 'milhar', null, 'Grupo Holding 0277 SA', 'Ativo Circulante', 'ativo_circulante')), 'anual', '2025', 'BALANCO');
  update documento set criado_em = now() + interval '1 minute' where caso_id = v_a and tipo_taxonomia = 'BALANCO' and entidade_id = (select id from entidade where caso_id = v_a and razao_social = 'Grupo Holding 0277 SA');
  insert into entidade (caso_id, razao_social) values (v_a, 'Controlada Alfa 0277 Ltda') returning id into e_alfa;
  v_r := teste_imp_0277(v_a, e_alfa, c_ar, '2025-12-31', 500000000);
  rr := teste_rec_0277(v_r, 'aging_ar_clientes');
  perform teste_assert_0277(rr.resultado = 'ok' and rr.divergencia_abs = 0 and (rr.fonte_b ->> 'valor')::numeric = 5000000,
    'a controlada sem balanço próprio concilia com a SUA coluna (5.000) do combinado do grupo, não com a da holding (9.000)', rr.resultado || ' | ' || coalesce(rr.fonte_b::text, 'sem fonte_b') || ' | ' || coalesce(rr.descricao, ''));
  perform teste_assert_0277(rr.documento_id is not null and (rr.fonte_b ->> 'documento_de_outra_empresa')::boolean and rr.descricao like '%Grupo Holding 0277 SA%outra empresa do grupo%',
    'e a descrição e a fonte dizem que o documento é de outra empresa (Grupo Holding), na coluna da controlada', rr.descricao);
  v_r := teste_imp_0277(v_a, e_alfa, c_ar, '2025-12-31', 900000000);
  rr := teste_rec_0277(v_r, 'aging_ar_clientes');
  perform teste_assert_0277(rr.resultado = 'divergente' and rr.divergencia_abs = 4000000 and teste_pend_0277(v_a, e_alfa, 'aging_ar_clientes') = 1,
    'carteira de 9.000 contra a coluna da controlada (5.000): DIVERGENTE com o valor (4.000.000) e pendência, não documento_ausente', rr.resultado || ' | ' || coalesce(rr.divergencia_abs::text, 'null'));
  -- O próprio vence: a controlada ganha o balanço dela (5.200) e a conciliação passa a usá-lo.
  perform teste_bal_0277(v_a, 'Controlada Alfa 0277 Ltda', 18, jsonb_build_array(teste_ln_0277(1, 'Clientes', 5200, 'milhar', null, null, 'Ativo Circulante', 'ativo_circulante')));
  v_r := teste_imp_0277(v_a, e_alfa, c_ar, '2025-12-31', 520000000);
  rr := teste_rec_0277(v_r, 'aging_ar_clientes');
  perform teste_assert_0277(rr.resultado = 'ok' and (rr.fonte_b ->> 'valor')::numeric = 5200000 and not (rr.fonte_b ->> 'documento_de_outra_empresa')::boolean and rr.descricao not like '%outra empresa do grupo%',
    'o balanço PRÓPRIO vence o da coluna do combinado (5.200, não 5.000): a preferência é pelo próprio', rr.resultado || ' | ' || coalesce(rr.fonte_b::text, 'sem fonte_b'));
  perform teste_assert_0277(teste_pend_0277(v_a, e_alfa, 'aging_ar_clientes') = 0, 'e a pendência da carteira de 9.000 fecha com a carteira corrigida', null);
  -- Documento de outra empresa SEM coluna desta entidade não vale; entidade sem coluna no combinado também não.
  insert into entidade (caso_id, razao_social) values (v_a, 'Sem Coluna 0277 Ltda') returning id into e_prop;
  v_r := teste_imp_0277(v_a, e_prop, c_ar, '2025-12-31', 500000000);
  rr := teste_rec_0277(v_r, 'aging_ar_clientes');
  perform teste_assert_0277(rr.resultado = 'precondicao_nao_satisfeita' and rr.motivo_precondicao = 'documento_ausente' and teste_pend_0277(v_a, e_prop, 'aging_ar_clientes') = 0 and rr.descricao like '%nem como coluna%',
    'entidade que NÃO tem coluna no combinado (nem balanço próprio): documento_ausente, sem pendência, e a descrição diz "nem como coluna"', rr.resultado || ' | ' || coalesce(rr.motivo_precondicao, '') || ' | ' || coalesce(rr.descricao, ''));
  perform teste_bal_0277(v_a, 'Zeta Papeis 0277 Ltda', 19, jsonb_build_array(teste_ln_0277(1, 'Clientes', 777, 'milhar', null, null, 'Ativo Circulante')));
  v_r := teste_imp_0277(v_a, e_prop, c_ar, '2025-12-31', 77700000);
  rr := teste_rec_0277(v_r, 'aging_ar_clientes');
  perform teste_assert_0277(rr.motivo_precondicao = 'documento_ausente' and teste_pend_0277(v_a, e_prop, 'aging_ar_clientes') = 0,
    'balanço de OUTRA empresa sem colunas de entidade não é usado por palpite: continua documento_ausente', rr.resultado || ' | ' || coalesce(rr.motivo_precondicao, ''));

  -- ================================================================== 5. MÉDIO: O RESUMO AMARRADO AO APLICADOR
  raise notice '--- 5. o resumo que não é o do arquivo lido ---';
  e_aplic := e_cn;
  v_t := teste_tenta_0277(v_a, e_aplic, c_ar, '2025-12-31', 2491700000, 0, jsonb_set(teste_aplic_0277(teste_resumo_0277('2025-12-31', 2491700000)), '{titulo}', '9'::jsonb));
  perform teste_assert_0277(v_t like '22023|%o resumo conta 3 títulos e o aplicador aplicou 9%', 'a função recusa resumo com outra contagem de títulos que a do aplicador (22023)', v_t);
  v_t := teste_tenta_0277(v_a, e_aplic, c_ar, '2025-12-31', 2491700000, 0, jsonb_set(teste_aplic_0277(teste_resumo_0277('2025-12-31', 2491700000)), '{saldo_titulos}', '"2491700001"'::jsonb));
  perform teste_assert_0277(v_t like '22023|%soma dos saldos do aplicador%', 'recusa resumo cuja soma de saldos não é a do aplicador (um centavo de diferença)', v_t);
  v_t := teste_tenta_0277(v_a, e_aplic, c_ar, '2025-12-31', 2491700000, -21200000, jsonb_set(teste_aplic_0277(teste_resumo_0277('2025-12-31', 2491700000, -21200000)), '{titulos_com_saldo_negativo,linhas}', '2'::jsonb));
  perform teste_assert_0277(v_t like '22023|%o resumo tem 1 títulos negativos e o aplicador 2%', 'recusa resumo cujos títulos negativos não são os do aplicador', v_t);
  v_t := teste_tenta_0277(v_a, e_aplic, c_ar, '2025-12-31', 2491700000, -21200000, jsonb_set(teste_aplic_0277(teste_resumo_0277('2025-12-31', 2491700000, -21200000)), '{titulos_com_saldo_negativo,saldo}', '"-1"'::jsonb));
  perform teste_assert_0277(v_t like '22023|%o saldo negativo do resumo%diferente do do aplicador%', 'recusa resumo cujo saldo negativo não é o do aplicador', v_t);
  v_t := teste_tenta_0277(v_a, e_aplic, c_ar, '2025-12-31', 2491700000, 0, '{"motivos":{}}'::jsonb);
  perform teste_assert_0277(v_t like '22023|%o aplicador não diz quantos títulos%' and v_t like '%não diz a soma dos saldos%' and v_t like '%não diz os títulos de saldo negativo%',
    'aplicador sem os campos: a ausência é dita (nunca passa por zero), com os três motivos juntos', v_t);
  v_t := teste_tenta_0277(v_a, e_aplic, c_ar, '2025-12-31', 0, 0, null, jsonb_set(teste_resumo_0277('2025-12-31', 2491700000), '{titulos}', '7'::jsonb));
  perform teste_assert_0277(v_t like '22023|%resumo.titulos (7) diferente de positivos (3) + negativos (0) + liquidados (0)%', 'a identidade do resumo (titulos = positivos + negativos + liquidados) é conferida', v_t);
  v_t := teste_tenta_0277(v_a, e_aplic, c_ar, '2025-12-31', 2491700000);
  perform teste_assert_0277(v_t = 'ok', 'controle: resumo e aplicador coerentes entram', v_t);
  -- A CHECK da tabela cobre quem escreve sem passar pela função (service_role).
  begin
    insert into aging_importado (caso_id, entidade_id, tipo_base, data_base, resumo, leitura, aplicador, arquivo_nome, arquivo_sha256, arquivo_bytes, arquivo_formato, mapeamento_id, importado_por)
    values (v_a, e_cn, c_ar, '2031-01-01', teste_resumo_0277('2031-01-01', 100), '{}'::jsonb, jsonb_set(teste_aplic_0277(teste_resumo_0277('2031-01-01', 100)), '{titulo}', '4'::jsonb),
            'direto.csv', repeat('b', 64), 10, 'csv', v_map_ar, '00000000-0000-0000-0000-00000000a001');
    v_t := 'ok';
  exception when check_violation then v_t := 'check';
  when others then v_t := sqlstate;
  end;
  perform teste_assert_0277(v_t = 'check', 'direto na tabela: aplicador com outra contagem de títulos é recusado pela CHECK aging_resumo_e_aplicador (23514)', v_t);
  begin
    insert into aging_importado (caso_id, entidade_id, tipo_base, data_base, resumo, leitura, aplicador, arquivo_nome, arquivo_sha256, arquivo_bytes, arquivo_formato, mapeamento_id, importado_por)
    values (v_a, e_cn, c_ar, '2031-01-01', teste_resumo_0277('2031-01-01', 100), '{}'::jsonb, '{}'::jsonb, 'direto.csv', repeat('b', 64), 10, 'csv', v_map_ar, '00000000-0000-0000-0000-00000000a001');
    v_t := 'ok';
  exception when check_violation then v_t := 'check';
  when others then v_t := sqlstate;
  end;
  perform teste_assert_0277(v_t = 'check', 'direto na tabela: aplicador vazio ({}) também é recusado (ausência não vira coerência)', v_t);

  -- ================================================================== 6. A SONDA
  raise notice '--- 6. a sonda enxerga a 0277 ---';
  perform teste_assert_0277((select count(*) from fn_instalacao_conferir() where migration = '0277' and presente) = 7 and (select count(*) from fn_instalacao_conferir() where migration = '0277') = 7,
    'os 7 requisitos da 0277 existem no catálogo e estão presentes', (select string_agg(chave || ':' || presente, ', ') from fn_instalacao_conferir() where migration = '0277'));
  perform teste_assert_0277((select ate_migration from instalacao_cobertura where id = true) >= '0277', 'a cobertura da sonda foi até a 0277', (select ate_migration from instalacao_cobertura where id = true));

  raise notice 'TODOS OS TESTES DA 0277 PASSARAM (% asserts executados)', current_setting('ct77.execucoes', true);
end $$;
