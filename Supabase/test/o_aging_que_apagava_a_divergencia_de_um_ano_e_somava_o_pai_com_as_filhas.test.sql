-- Testes da 0277: a conciliação do aging da 0274 depois da revisão independente (3 ALTOS e 3 médios).
-- Rodar via Supabase/test/run.sh (que aplica as migrations e carrega as fixtures dos books antes).
--
-- O QUE ESTE ARQUIVO PROVA (comportamento, regra 3):
--   1. ALTO 1: a pendência e o estado vigente do aging são da DATA-BASE da carteira (fn_registrar_reconciliacao, por fonte_a.aging_id). Num balanço COMPARATIVO ("multi 24,25")
--      as carteiras de 2024 e de 2025 têm pendência própria (na importação e na rodada do mandato); duas datas-base do MESMO ano (31/12 e 30/06) também; a carteira sem par
--      (periodo_id NULL) não captura a divergência de outro ano; a guarda da 0192 não vale entre datas-base (balanços de períodos compatíveis); o texto é o da última rodada;
--      a função recusa o tipo do aging sem importação deste mandato e desta entidade. Importar aging NÃO cria período nem muda o que as checagens clássicas produzem (assinatura
--      tirada ANTES de qualquer aging, num mandato à parte).
--   2. ALTO 2: pai e filhas de Fornecedores/Clientes NA FORMA DE PRODUÇÃO (mesma `secao` ou `secao` nula; o valor do pai é a soma das filhas) valem uma vez.
--      Pai que as filhas cobrem em parte vale sozinho e AVISA; o aviso descreve o que ENTROU (três níveis: sem aviso de dobro).
--   2b. Convenção de sinal: o aging (em módulo) é comparado com o módulo do balanço quando o documento prova que imprime o passivo negativo (produção: 3 de 917 versões, a forma
--      de 5b930fad, b5ce0a25 e 4a14371f); os arranjos de sinais mistos são GUARDAS da regra declarada, não prova de bug de produção.
--   2c. Fora dessa prova o balanço se compara COM O SINAL: Clientes -100 mil no ativo contra a carteira de R$ 100.000 diverge em R$ 200.000 (antes: ok), Fornecedores negativo em documento
--      com passivo positivo (a forma de 787ec844) diverge e avisa, e o patrimônio líquido positivo não desprova a convenção. As formas de produção são as de 4a14371f/5b930fad/b5ce0a25
--      (convenção) e 787ec844/28923274 (mistura); a coluna "Crédito" de 044202cf não é reproduzida (uma coluna só), a regra "passivo positivo no documento" é a que a exclui.
--   5c. A fusão de entidades leva a carteira de aging da absorvida (antes: o cascade a apagava sem evento e a pendência ficava aberta sem origem); com a mesma data-base nas duas, a da
--      absorvida vira substituída (sem apagar) e a pendência dela é resolvida; apagar entidade com carteira reprova (23503); apagar o mandato continua funcionando.
--   3. ALTO 3: balanço que só existe como coluna de um combinado de OUTRA empresa do grupo concilia (e a descrição diz de quem é); o da própria entidade vence;
--      documento de outra empresa SEM coluna desta entidade não vale (documento_ausente, sem pendência).
--   4. Médios: conta de ESTOQUE com "cliente"/"fornecedor" no rótulo fica fora (por seção em texto e por secao_canonica de outro lado; secao_canonica NULA não exclui);
--      carteira sem par com o lado vazio é ok (B2); o resumo que não se amarra ao aplicador é recusado na função e na CHECK da tabela.
--
-- DE ONDE VÊM AS FIXTURES (regra 4: nada inventado para provar bug de produção). As FORMAS vêm de produção, lidas em 12/11/2026 (leitura, nenhuma escrita):
--   "Fornecedores" 24.549 = "Fornecedores nacionais" 16.843 + "Fornecedores intragrupo" 3.600 + "Fornecedores no exterior - resinas" 4.106 (R$ mil, 31/12/2024, ordem 33-36);
--   "Fornecedores" 1.892 = "Fornecedores de EPC e equipamentos" 1.892; "Fornecedores" 3.966 com a única filha "Fornecedores - silvicultura e colheita" 2.934 (seção Passivo
--   Circulante); "Clientes - duplicatas a receber - mercado interno" 24.861 ao lado de "Duplicatas a receber de clientes - mercado interno" 35.044 na mesma coluna (d19a86ce: extração
--   que juntou a mesma conta de dois anos, NÃO um pai com filha; ver o comentário no ponto); "MERCADORIA EM GARANTIA/CONSERTO A RECEBER(FORNECEDOR)" na seção ESTOQUE;
--   "Fornecedores nacionais - em atraso" -4.719 e "- a vencer" -902 (4a14371f) e "FORNECEDORES" -8.111.470 (5b930fad). Os NÚMEROS de aging são montados aqui (não há arquivo de
--   aging real: DM7 pendente) a partir do valor do balanço. As empresas dos fixtures têm nomes bem diferentes: a entidade é unificada por nome parecido (o que escondeu uma prova vazia).
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

-- A fusão devolvendo 'ok|<json>' ou 'sqlstate|mensagem' em vez de estourar (a sabotagem não pode abortar a medição). Como o AUTHENTICATED, que é quem funde em produção: ele só LÊ aging_importado.
create or replace function teste_funde_0277(p_caso uuid, p_de uuid, p_para uuid, p_como_authenticated boolean default true) returns text
language plpgsql as $$
declare v_r jsonb;
begin
  if p_como_authenticated then set local role authenticated; end if;
  v_r := fn_fundir_entidade(p_caso, p_de, p_para, 'teste:0277');
  reset role;
  return 'ok|' || v_r::text;
exception when others then
  return sqlstate || '|' || sqlerrm;
end $$;

-- A função de levar a carteira chamada DIRETO (como /rpc), com o papel authenticated e as claims que estiverem postas: devolve 'ok|<json>' ou o sqlstate.
create or replace function teste_levar_direto_0277(p_caso uuid, p_de uuid, p_para uuid, p_por text) returns text
language plpgsql as $$
declare v_r jsonb;
begin
  set local role authenticated;
  v_r := fn_aging_levar_na_fusao(p_caso, p_de, p_para, p_por);
  reset role;
  return 'ok|' || v_r::text;
exception when others then
  reset role;
  return sqlstate;
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
  e_alfa uuid; e_beta uuid; e_gama uuid; e_prop uuid; e_aplic uuid; e_clw uuid; e_a1 uuid; e_rv uuid; e_sg1 uuid; e_sg2 uuid; e_sg3 uuid; e_sg4 uuid; e_sg5 uuid; e_sg6 uuid; e_h1 uuid; e_tx uuid; v_b uuid; v_ids1 uuid[]; v_sig1 text; v_sig2 text;
  v_map_ar uuid; v_map_ap uuid;
  v_cab jsonb := '["Cliente0277","Vencimento","Saldo"]'; v_mapa jsonb := '{"contraparte":0,"vencimento":1,"saldo":2}'; v_fmt jsonb := '{"decimal":"virgula","datas":"dia_mes_ano"}';
  v_r jsonb; v_r2 jsonb; rr reconciliacao; l record; v_t text; v_n int; v_ver uuid; v_antes jsonb; v_depois jsonb; v_pend_antes int; v_pend_depois int; v_res text;
  v_id uuid;
  e_sc1 uuid; e_sc2 uuid; e_sc3 uuid; e_sc4 uuid; e_sc5 uuid; v_f uuid; e_f1 uuid; e_f2 uuid; e_f3 uuid; e_f4 uuid; e_f5 uuid; e_f6 uuid; v_ag1 uuid; v_ag2 uuid; v_n2 int; v_uid_ant text; u_ana77 uuid := '00000000-0000-0000-0000-000000277b02'; e_g1 uuid; e_g2 uuid; e_g3 uuid; e_g4 uuid; v_ator text; v_g uuid;
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
                            and (select p.data_base from pendencia p where p.caso_id = v_a and p.entidade_id = e_cmp2 and p.motivo = 'reconciliacao:aging_ar_clientes' and p.estado <> 'resolvida') = date '2025-12-31',
    'a pendência aberta é da carteira de 2025-12-31 (pendencia.data_base), e foi UMA pendência no total (a de 2025 reaberta, não duplicada)', null);
  v_r := teste_imp_0277(v_a, e_cmp2, c_ar, '2025-12-31', 2491700000);
  perform teste_assert_0277(teste_pend_0277(v_a, e_cmp2, 'aging_ar_clientes') = 0, 'corrigida a de 2025, fecha', null);
  perform teste_assert_0277((select count(*) from periodo where caso_id = v_a and tipo = 'data-base') = 0
                            and (select count(*) from reconciliacao where caso_id = v_a and tipo like 'aging\_%' and data_base is null) = 0,
    'importar aging NÃO cria período nenhum no mandato (a primeira versão fabricava ''data-base AAAA-MM-DD''), e toda checagem do aging grava a data-base da carteira', (select count(*)::text from periodo where caso_id = v_a and tipo = 'data-base'));

  -- O MESMO ANO, datas-base diferentes (31/12 e 30/06 de 2025): cada uma tem a sua pendência e o seu texto (o TETO da 0274 acabou: era o que o período por ano não distinguia).
  e_ano := teste_bal_0277(v_a, 'Anual Charlie 0277 Ltda', 3, jsonb_build_array(teste_ln_0277(0, 'Clientes - duplicatas a receber', 24917)));
  v_r := teste_imp_0277(v_a, e_ano, c_ar, '2025-12-31', 2600000000);
  v_r2 := teste_imp_0277(v_a, e_ano, c_ar, '2025-06-30', 2491700000);
  perform teste_assert_0277(teste_pend_0277(v_a, e_ano, 'aging_ar_clientes') = 2 and (teste_rec_0277(v_r2, 'aging_ar_clientes')).motivo_precondicao = 'sem_periodo_par',
    'duas datas-base do MESMO ano: a de 30/06 (sem par) abre a SUA pendência, não cai na de 31/12 divergente', teste_pend_0277(v_a, e_ano, 'aging_ar_clientes')::text);
  perform teste_assert_0277((select p.descricao from pendencia p where p.caso_id = v_a and p.entidade_id = e_ano and p.motivo = 'reconciliacao:aging_ar_clientes' and p.data_base = date '2025-12-31' and p.estado <> 'resolvida') like '%31/12/2025%Diferença de%'
                            and (select p.descricao from pendencia p where p.caso_id = v_a and p.entidade_id = e_ano and p.motivo = 'reconciliacao:aging_ar_clientes' and p.data_base = date '2025-12-31' and p.estado <> 'resolvida') not like '%30/06/2025%',
    'e a pendência de 31/12 mantém o texto da divergência de 31/12 (a rodada de 30/06 não o reescreve)', (select string_agg(p.data_base::text || ': ' || left(p.descricao, 80), ' | ') from pendencia p where p.caso_id = v_a and p.entidade_id = e_ano and p.motivo = 'reconciliacao:aging_ar_clientes'));
  perform teste_assert_0277((teste_rec_0277(v_r2, 'aging_ar_adiantamentos')).resultado = 'ok' and teste_pend_0277(v_a, e_ano, 'aging_ar_adiantamentos') = 0,
    'B2: carteira de 30/06 sem par mas SEM saldo negativo (lado dos adiantamentos vazio): nada a conciliar, ok, sem pendência', (teste_rec_0277(v_r2, 'aging_ar_adiantamentos')).resultado || ' | ' || coalesce((teste_rec_0277(v_r2, 'aging_ar_adiantamentos')).descricao, ''));
  v_r := teste_imp_0277(v_a, e_ano, c_ar, '2025-12-31', 2491700000);
  perform teste_assert_0277(teste_pend_0277(v_a, e_ano, 'aging_ar_clientes') = 1
                            and (select p.data_base from pendencia p where p.caso_id = v_a and p.entidade_id = e_ano and p.motivo = 'reconciliacao:aging_ar_clientes' and p.estado <> 'resolvida') = date '2025-06-30',
    'corrigida a de 31/12, fecha SÓ ela: a de 30/06, que segue sem par, continua na fila (na 0274 sumia dela)', teste_pend_0277(v_a, e_ano, 'aging_ar_clientes')::text);

  -- ALTO 1 (rv2 da revisão): o balanço comparativo + a carteira de 30/06/2025 (sem par: o balanço fecha em 31/12), que passava periodo_id NULL e casava QUALQUER ano.
  e_a1 := teste_bal_0277(v_a, 'Comparativa Um 0277 Ltda', 23, jsonb_build_array(
    teste_ln_0277(0, 'Clientes - duplicatas a receber', 21902, 'milhar', '31/12/2024'), teste_ln_0277(1, 'Clientes - duplicatas a receber', 24917, 'milhar', '31/12/2025')), 'multi', '24,25');
  v_r := teste_imp_0277(v_a, e_a1, c_ar, '2025-06-30', 2400000000);
  v_r2 := teste_imp_0277(v_a, e_a1, c_ar, '2024-12-31', 2200000000);
  rr := teste_rec_0277(v_r2, 'aging_ar_clientes');
  perform teste_assert_0277(rr.resultado = 'divergente' and rr.divergencia_abs = 98000 and teste_pend_0277(v_a, e_a1, 'aging_ar_clientes') = 2,
    'sem par (30/06/2025) e divergente (31/12/2024) têm pendência CADA UM: a divergência de 2024 não cai na pendência sem período da outra carteira', rr.resultado || ' | ' || teste_pend_0277(v_a, e_a1, 'aging_ar_clientes'));
  v_r := teste_imp_0277(v_a, e_a1, c_ar, '2025-12-31', 2491700000);
  perform teste_assert_0277(teste_pend_0277(v_a, e_a1, 'aging_ar_clientes') = 2
                            and (select p.descricao from pendencia p where p.caso_id = v_a and p.entidade_id = e_a1 and p.motivo = 'reconciliacao:aging_ar_clientes' and p.data_base = date '2024-12-31' and p.estado <> 'resolvida') like '%R$ 98.000,00%',
    'o ok de 31/12/2025 não resolve nem a divergência de 2024 (com o valor dela no texto) nem a de 30/06/2025', teste_pend_0277(v_a, e_a1, 'aging_ar_clientes')::text);

  -- A guarda da 0192 (a divergência irmã) não vale entre datas-base. Arranjo da 0192/4 ("Pa primeiro"): a mesma empresa com um balanço comparativo (multi 24,25) e um anual 2025 mais novo: a carteira de 2024 só
  -- acha o comparativo; a de 2025 acha o anual (o mais novo do mesmo tipo). Com a pendência de 2024 aberta e a de 2025 divergente, corrigir a carteira de 2024 tem de resolver a de 2024: a chave
  -- "anual 2025" (compatível com multi 24,25) tem como último registro a divergência de 2025, e a guarda a tomaria por irmã da de 2024.
  e_sg5 := teste_bal_0277(v_a, 'Guarda Zero Dois 0277 Ltda', 29, jsonb_build_array(
    teste_ln_0277(0, 'Clientes - duplicatas a receber', 21902, 'milhar', '31/12/2024'), teste_ln_0277(1, 'Clientes - duplicatas a receber', 24917, 'milhar', '31/12/2025')), 'multi', '24,25');
  perform teste_bal_0277(v_a, 'Guarda Zero Dois 0277 Ltda', 30, jsonb_build_array(teste_ln_0277(0, 'Clientes - duplicatas a receber', 24917)), 'anual', '2025');
  update documento set criado_em = now() + interval '2 minutes' where caso_id = v_a and entidade_id = e_sg5 and periodo_id = (select id from periodo where caso_id = v_a and tipo = 'anual' and referencia = '2025');
  v_r := teste_imp_0277(v_a, e_sg5, c_ar, '2024-12-31', 2200000000);
  v_r2 := teste_imp_0277(v_a, e_sg5, c_ar, '2025-12-31', 2600000000);
  perform teste_assert_0277(teste_pend_0277(v_a, e_sg5, 'aging_ar_clientes') = 2 and (teste_rec_0277(v_r, 'aging_ar_clientes')).periodo_id is distinct from (teste_rec_0277(v_r2, 'aging_ar_clientes')).periodo_id,
    'duas carteiras divergentes de balanços de períodos compatíveis (multi 24,25 e anual 2025): uma pendência para cada', teste_pend_0277(v_a, e_sg5, 'aging_ar_clientes')::text);
  v_r := teste_imp_0277(v_a, e_sg5, c_ar, '2024-12-31', 2190200000);
  perform teste_assert_0277(teste_pend_0277(v_a, e_sg5, 'aging_ar_clientes') = 1 and (select p.data_base from pendencia p where p.caso_id = v_a and p.entidade_id = e_sg5 and p.motivo = 'reconciliacao:aging_ar_clientes' and p.estado <> 'resolvida') = date '2025-12-31',
    'corrigida a carteira de 2024, a pendência de 2024 RESOLVE mesmo com a divergência de 2025 viva em período compatível (a guarda da 0192 não é entre datas-base)', teste_pend_0277(v_a, e_sg5, 'aging_ar_clientes')::text);
  -- O texto é sempre o da última rodada daquela carteira, mesmo quando o balanço lido mudou de período (um balanço mais novo entrou entre as duas importações).
  e_tx := teste_bal_0277(v_a, 'Texto Novo 0277 Ltda', 31, jsonb_build_array(teste_ln_0277(0, 'Clientes - duplicatas a receber', 24917)), 'anual', '2025');
  v_r := teste_imp_0277(v_a, e_tx, c_ar, '2025-12-31', 2600000000);
  perform teste_bal_0277(v_a, 'Texto Novo 0277 Ltda', 32, jsonb_build_array(
    teste_ln_0277(0, 'Clientes - duplicatas a receber', 21902, 'milhar', '31/12/2024'), teste_ln_0277(1, 'Clientes - duplicatas a receber', 24917, 'milhar', '31/12/2025')), 'multi', '24,25');
  update documento set criado_em = now() + interval '3 minutes' where caso_id = v_a and entidade_id = e_tx and periodo_id = (select id from periodo where caso_id = v_a and tipo = 'multi' and referencia = '24,25');
  v_r := teste_imp_0277(v_a, e_tx, c_ar, '2025-12-31', 2700000000);
  perform teste_assert_0277(teste_pend_0277(v_a, e_tx, 'aging_ar_clientes') = 1
                            and (select p.descricao from pendencia p where p.caso_id = v_a and p.entidade_id = e_tx and p.motivo = 'reconciliacao:aging_ar_clientes' and p.estado <> 'resolvida') like '%R$ 27.000.000,00%',
    'reimportada a carteira com um balanço mais novo de OUTRO período lido, a pendência é a mesma (uma) e o texto é o da última rodada (27.000.000)',
    (select string_agg(p.descricao, ' | ') from pendencia p where p.caso_id = v_a and p.entidade_id = e_tx and p.motivo = 'reconciliacao:aging_ar_clientes' and p.estado <> 'resolvida'));

  -- A função central (fn_registrar_reconciliacao): o tipo do aging sem importação deste mandato e desta entidade em fonte_a.aging_id reprova ALTO.
  begin
    perform fn_registrar_reconciliacao(v_a, e_a1, null, 'aging_ar_clientes', 'A', null, '{}'::jsonb, null, 'divergente', 1, null, null, 'sem aging_id');
    v_t := 'passou';
  exception when others then v_t := sqlstate || '|' || sqlerrm;
  end;
  perform teste_assert_0277(v_t like 'P0001|%é por data-base%ausente%', 'tipo do aging SEM fonte_a.aging_id reprova ALTO (a pendência sem data-base voltaria a ser achada por período)', v_t);
  begin
    perform fn_registrar_reconciliacao(v_a, e_cmp, null, 'aging_ar_clientes', 'A', null, jsonb_build_object('aging_id', (select id from aging_importado where entidade_id = e_a1 limit 1)), null, 'divergente', 1, null, null, 'aging de outra entidade');
    v_t := 'passou';
  exception when others then v_t := sqlstate || '|' || sqlerrm;
  end;
  perform teste_assert_0277(v_t like 'P0001|%é por data-base%', 'e a importação de OUTRA entidade em aging_id também reprova (a data-base é lida do que é deste mandato e desta entidade)', v_t);

  -- ALTO 2 da revisão (A2): as checagens clássicas do mandato NÃO mudam depois de importar aging. Arranjo da reprodução da revisão: um balanço comparativo (multi 24,25) com
  -- Total do Ativo/Passivo, e um anual 2025 mais novo. O que se compara é a ASSINATURA (tipo, resultado, motivo) das linhas que a MESMA rodada produz antes e depois da importação,
  -- num mandato à parte e com a assinatura tirada ANTES de qualquer aging (a versão anterior a tirava depois de os períodos já existirem: não reprovava).
  v_b := fn_upsert_caso('0277 — mandato B (checagens clássicas)');
  e_rv := teste_bal_0277(v_b, 'Classica Eco 0277 Ltda', 21, jsonb_build_array(
    teste_ln_0277(1, 'Total do Ativo', 1000, 'milhar', '31/12/2024'), teste_ln_0277(2, 'Total do Passivo e Patrimônio Líquido', 1000, 'milhar', '31/12/2024'),
    teste_ln_0277(3, 'Clientes', 100, 'milhar', '31/12/2024')), 'multi', '24,25');
  perform teste_bal_0277(v_b, 'Classica Eco 0277 Ltda', 22, jsonb_build_array(teste_ln_0277(1, 'Clientes', 50, 'milhar', '31/12/2025')), 'anual', '2025');
  update documento set criado_em = now() + interval '1 minute' where caso_id = v_b and periodo_id = (select id from periodo where caso_id = v_b and referencia = '2025');
  perform fn_reconciliar_caso(v_b);
  v_ids1 := array(select id from reconciliacao where caso_id = v_b);
  -- A assinatura é a CONTAGEM por (tipo, resultado, motivo, período): uma linha `ok` a mais num tipo que já tinha `ok` muda a contagem (o conjunto distinto não mudaria).
  v_sig1 := (select string_agg(x, ' ; ' order by x) from (select r.tipo || '/' || r.resultado || '/' || coalesce(r.motivo_precondicao, '-') || '/' || coalesce(p.tipo || ' ' || p.referencia, 'sem período') || ' x' || count(*) x
                                                              from reconciliacao r left join periodo p on p.id = r.periodo_id where r.caso_id = v_b
                                                             group by r.tipo, r.resultado, r.motivo_precondicao, p.tipo, p.referencia) q);
  v_pend_antes := (select count(*) from pendencia where caso_id = v_b and motivo not like 'reconciliacao:aging\_%' and estado <> 'resolvida');
  v_r := teste_imp_0277(v_b, e_rv, c_ar, '2024-12-31', 10000000);
  perform teste_assert_0277((teste_rec_0277(v_r, 'aging_ar_clientes')).resultado = 'ok', 'controle: a carteira de 31/12/2024 do mandato B confere (R$ 100.000 = Clientes 100 milhar)', (teste_rec_0277(v_r, 'aging_ar_clientes')).resultado);
  perform fn_reconciliar_caso(v_b);
  v_sig2 := (select string_agg(x, ' ; ' order by x) from (select r.tipo || '/' || r.resultado || '/' || coalesce(r.motivo_precondicao, '-') || '/' || coalesce(p.tipo || ' ' || p.referencia, 'sem período') || ' x' || count(*) x
                                                              from reconciliacao r left join periodo p on p.id = r.periodo_id where r.caso_id = v_b and r.id <> all(v_ids1) and r.tipo not like 'aging\_%'
                                                             group by r.tipo, r.resultado, r.motivo_precondicao, p.tipo, p.referencia) q);
  v_pend_depois := (select count(*) from pendencia where caso_id = v_b and motivo not like 'reconciliacao:aging\_%' and estado <> 'resolvida');
  perform teste_assert_0277(v_sig1 = v_sig2 and v_pend_antes = v_pend_depois,
    'importar aging NÃO muda o que a mesma rodada das checagens clássicas produz (contagem por tipo, resultado, motivo e período) nem a contagem de pendências delas', v_sig1 || ' || ' || v_sig2 || ' || ' || v_pend_antes || ' x ' || v_pend_depois);
  perform teste_assert_0277((select count(*) from periodo where caso_id = v_b) = 2, 'e o mandato continua com os 2 períodos que os documentos trouxeram (nenhum período é fabricado)', (select string_agg(tipo || ' ' || referencia, ', ') from periodo where caso_id = v_b));

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
  -- Pai que as filhas EXCEDEM. REGRA 4, o que isto É e o que NÃO é: o único arranjo de produção com "excede" em grupo real é a versão d19a86ce (BALANCO, coluna 31/12/2024): "Clientes -
  -- duplicatas a receber - mercado interno" 24.861 e "Duplicatas a receber de clientes - mercado interno" 35.044 na MESMA coluna. Não é pai com filha: é a MESMA conta com dois nomes em
  -- ANOS diferentes (24.861 é a coluna 2025 e 35.044 a de 2023 na versão 6194209b do mesmo balanço), que a extração de d19a86ce deixou numa coluna só. Aqui afirma-se só o que dá para provar: as
  -- linhas entram todas (é o que o balanço extraído diz) e o aviso avisa que pode estar em dobro. NÃO se afirma que existe pai cujas filhas excedem na estrutura real do balanço.
  e_pf5 := teste_bal_0277(v_a, 'Pai Cinco 0277 Ltda', 9, jsonb_build_array(
    teste_ln_0277(15, 'Clientes - duplicatas a receber - mercado interno', 24861, 'milhar', '31/12/2024', null, 'Ativo Circulante', 'ativo_circulante'),
    teste_ln_0277(17, 'Duplicatas a receber de clientes - mercado externo', 5080, 'milhar', '31/12/2024', null, 'Ativo Circulante', 'ativo_circulante'),
    teste_ln_0277(25, 'Duplicatas a receber de clientes - mercado interno', 35044, 'milhar', '31/12/2024', null, 'Ativo Circulante', 'ativo_circulante')), 'multi', '24,25');
  select count(*), max(aviso) into v_n, v_t from fn_aging_linhas_do_balanco(teste_ver_0277(v_a, e_pf5), 'clientes', null, '31/12/2024');
  perform teste_assert_0277(v_n = 3 and v_t like '%entrou na soma junto com a linha%R$ 35.044.000,00 contra os R$ 24.861.000,00%em dobro%', 'extração que juntou a mesma conta de dois anos numa coluna (d19a86ce): as 3 linhas entram e o AVISO diz que pode estar em dobro', v_n || ' | ' || coalesce(v_t, 'sem aviso'));
  v_r := teste_imp_0277(v_a, e_pf5, c_ar, '2024-12-31', 6498500000);
  rr := teste_rec_0277(v_r, 'aging_ar_clientes');
  perform teste_assert_0277(rr.descricao like '%Atenção na leitura do balanço:%entrou na soma junto com%', 'e a descrição da conciliação carrega esse aviso, ok ou divergente', rr.resultado || ' | ' || rr.descricao);
  -- M2: o aviso descreve o que de fato ENTROU. Três níveis, a forma que a revisão reproduziu: Fornecedores 5.329 > Fornecedores nacionais 5.329 > em atraso 3.381 + a vencer 1.948. A janela por
  -- ordem absorve "nacionais" no pai e o nome absorve atraso e a vencer em "nacionais": entra só o pai (5.329). Antes o aviso era tirado ANTES da absorção e dizia "entraram todas, em dobro".
  e_h1 := teste_bal_0277(v_a, 'Tres Niveis 0277 Ltda', 24, jsonb_build_array(
    teste_ln_0277(47, 'Fornecedores', 5329, 'milhar', '31/12/2024', null, 'Passivo Circulante', 'passivo_circulante'),
    teste_ln_0277(48, 'Fornecedores nacionais', 5329, 'milhar', '31/12/2024', null, 'Passivo Circulante', 'passivo_circulante'),
    teste_ln_0277(49, 'Fornecedores nacionais - em atraso', 3381, 'milhar', '31/12/2024', null, 'Passivo Circulante', 'passivo_circulante'),
    teste_ln_0277(51, 'Fornecedores nacionais - a vencer', 1948, 'milhar', '31/12/2024', null, 'Passivo Circulante', 'passivo_circulante')), 'anual', '2024');
  select count(*), sum(valor_num), max(aviso) into v_n, rr.divergencia_abs, v_t from fn_aging_linhas_do_balanco(teste_ver_0277(v_a, e_h1), 'fornecedores', null, '31/12/2024');
  perform teste_assert_0277(v_n = 1 and rr.divergencia_abs = 5329 and v_t is null, 'três níveis: entra só o pai (5.329) e NÃO há aviso de "em dobro" (o aviso descreve o que entrou, não o que a leitura do pai supunha)', v_n || ' | ' || coalesce(v_t, 'sem aviso'));
  v_r := teste_imp_0277(v_a, e_h1, c_ap, '2024-12-31', 532900000);
  rr := teste_rec_0277(v_r, 'aging_ap_fornecedores');
  perform teste_assert_0277(rr.resultado = 'ok' and rr.descricao not like '%em dobro%', 'e a conciliação confere (R$ 5.329.000) sem aviso de dobro na descrição', rr.resultado || ' | ' || coalesce(rr.descricao, ''));
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
  -- (o nome é bem diferente do anterior: 'Dois Nomes Sem Ordem' era unificado pela entidade 'Dois Nomes' e o assert lia o 1º documento, o COM ordem: a prova era vazia)
  e_ex := teste_bal_0277(v_a, 'Marte Papeis 0277 Ltda', 12, jsonb_build_array(
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

  -- ================================================================== 2b. A3: A CONVENÇÃO DE SINAL (módulo)
  raise notice '--- 2b. passivo e crédito impressos negativos: o aging (em módulo) é comparado com o módulo do balanço ---';
  -- A forma de produção (versão 4a14371f, BALANCETE, que nunca fecha e por isso o fixture é um BALANCO com as MESMAS linhas): "Fornecedores nacionais - em atraso" -4.719 e "- a vencer" -902
  -- (R$ mil, seção Passivo Circulante), o grupo inteiro negativo. A carteira a pagar é 5.621.000,00.
  e_sg1 := teste_bal_0277(v_a, 'Sinal Um 0277 Ltda', 25, jsonb_build_array(
    teste_ln_0277(1, 'Fornecedores nacionais - em atraso', -4719, 'milhar', '31/12/2024', null, 'Passivo Circulante', 'passivo_circulante'),
    teste_ln_0277(2, 'Fornecedores nacionais - a vencer', -902, 'milhar', '31/12/2024', null, 'Passivo Circulante', 'passivo_circulante')), 'anual', '2024');
  v_r := teste_imp_0277(v_a, e_sg1, c_ap, '2024-12-31', 562100000);
  rr := teste_rec_0277(v_r, 'aging_ap_fornecedores');
  perform teste_assert_0277(rr.resultado = 'ok' and rr.divergencia_abs = 0 and (rr.fonte_b ->> 'valor')::numeric = 5621000 and (rr.fonte_b ->> 'valor_com_sinal')::numeric = -5621000
                            and rr.descricao like '%impresso com sinal negativo%' and teste_pend_0277(v_a, e_sg1, 'aging_ap_fornecedores') = 0,
    'balanço com Fornecedores negativos (-4.719 e -902) contra carteira de 5.621.000: CONFERE (antes: divergente de 11.242.000), e o texto diz que o sinal é convenção', rr.resultado || ' | ' || coalesce(rr.divergencia_abs::text, 'null') || ' | ' || coalesce(rr.descricao, ''));
  -- Versão 5b930fad (BALANCO): "FORNECEDORES" -8.111.470 em R$ (duas linhas de seções diferentes, o mesmo valor: contam uma).
  e_sg2 := teste_bal_0277(v_a, 'Sinal Dois 0277 Ltda', 26, jsonb_build_array(
    teste_ln_0277(26, 'FORNECEDORES', -8111470, 'unidade', null, null, 'PASSIVO CIRCULANTE', 'passivo_circulante'), teste_ln_0277(27, 'FORNECEDORES', -8111470, 'unidade', null, null, 'FORNECEDORES', 'passivo_circulante')));
  v_r := teste_imp_0277(v_a, e_sg2, c_ap, '2025-12-31', 811147000);
  rr := teste_rec_0277(v_r, 'aging_ap_fornecedores');
  perform teste_assert_0277(rr.resultado = 'ok' and rr.divergencia_abs = 0, 'FORNECEDORES -8.111.470 em reais contra a carteira de 8.111.470: confere', rr.resultado || ' | ' || coalesce(rr.divergencia_abs::text, 'null'));
  -- E a diferença verdadeira continua aparecendo com o sinal negativo (a convenção não vira "ok" para tudo).
  v_r := teste_imp_0277(v_a, e_sg2, c_ap, '2025-12-31', 900000000);
  rr := teste_rec_0277(v_r, 'aging_ap_fornecedores');
  perform teste_assert_0277(rr.resultado = 'divergente' and rr.divergencia_abs = 888530, 'e uma carteira de 9.000.000 contra o -8.111.470 DIVERGE em 888.530 (módulo, não zero)', rr.resultado || ' | ' || coalesce(rr.divergencia_abs::text, 'null'));
  -- Pai positivo com filhas negativas: ARRANJO QUE PRODUÇÃO NÃO PRODUZ (13 grupos só-negativos e 0 mistos, nos 2.027 medidos). Fica como guarda da regra declarada (módulo), não como prova de bug.
  e_sg3 := teste_bal_0277(v_a, 'Sinal Tres 0277 Ltda', 27, jsonb_build_array(
    teste_ln_0277(1, 'Fornecedores', 5621, 'milhar', '31/12/2024', null, 'Passivo Circulante', 'passivo_circulante'),
    teste_ln_0277(2, 'Fornecedores nacionais - em atraso', -4719, 'milhar', '31/12/2024', null, 'Passivo Circulante', 'passivo_circulante'),
    teste_ln_0277(3, 'Fornecedores nacionais - a vencer', -902, 'milhar', '31/12/2024', null, 'Passivo Circulante', 'passivo_circulante')), 'anual', '2024');
  select count(*), sum(valor_num) into v_n, rr.divergencia_abs from fn_aging_linhas_do_balanco(teste_ver_0277(v_a, e_sg3), 'fornecedores', null, '31/12/2024');
  perform teste_assert_0277(v_n = 1 and rr.divergencia_abs = 5621, 'guarda (arranjo que produção não produz): pai +5.621 e filhas -4.719 e -902 fecham em módulo: o pai vale sozinho', v_n || ' linhas, soma ' || coalesce(rr.divergencia_abs::text, 'null'));
  -- Linhas de sinais opostos que ENTRAM na soma (também nunca visto): a soma com sinal é a comparada e o texto diz.
  e_sg4 := teste_bal_0277(v_a, 'Sinal Quatro 0277 Ltda', 28, jsonb_build_array(
    teste_ln_0277(1, 'Clientes nacionais', 900, 'milhar', '31/12/2024', null, 'Ativo Circulante', 'ativo_circulante'),
    teste_ln_0277(2, 'Clientes exterior', -50, 'milhar', '31/12/2024', null, 'Ativo Circulante', 'ativo_circulante')), 'anual', '2024');
  v_r := teste_imp_0277(v_a, e_sg4, c_ar, '2024-12-31', 85000000);
  rr := teste_rec_0277(v_r, 'aging_ar_clientes');
  perform teste_assert_0277(rr.resultado = 'ok' and rr.descricao like '%Atenção na leitura do balanço:%sinais opostos (1 positivas, 1 negativas)%',
    'linhas de sinais opostos entram com sinal (900 - 50 = 850) e a descrição AVISA (a diferença pode não ser real)', rr.resultado || ' | ' || coalesce(rr.descricao, ''));

  -- A mesma regra na janela por ordem (pai de nome de manual): outro arranjo que produção não produz, guarda do módulo.
  e_sg6 := teste_bal_0277(v_a, 'Sinal Seis 0277 Ltda', 33, jsonb_build_array(
    teste_ln_0277(5, 'Clientes', 100, 'milhar', '31/12/2025', null, 'Ativo Circulante', 'ativo_circulante'),
    teste_ln_0277(6, 'Duplicatas a receber - mercado interno', -70, 'milhar', '31/12/2025', null, 'Ativo Circulante', 'ativo_circulante'),
    teste_ln_0277(7, 'Duplicatas a receber - exportação', -30, 'milhar', '31/12/2025', null, 'Ativo Circulante', 'ativo_circulante')), 'multi', '24,25');
  select count(*), sum(valor_num) into v_n, rr.divergencia_abs from fn_aging_linhas_do_balanco(teste_ver_0277(v_a, e_sg6), 'clientes', null, '31/12/2025');
  perform teste_assert_0277(v_n = 1 and rr.divergencia_abs = 100, 'guarda (arranjo que produção não produz): "Clientes" 100 seguido de duplicatas -70 e -30 fecha em módulo pela janela: o pai vale sozinho', v_n || ' linhas, soma ' || coalesce(rr.divergencia_abs::text, 'null'));


  -- ================================================================== 2c. A CONVENÇÃO DE SINAL SÓ VALE QUANDO O DOCUMENTO A PROVA
  raise notice '--- 2c. o módulo do balanço só quando o documento prova que imprime o passivo negativo ---';
  -- Produção (12/11/2026, leitura): das 917 versões de BALANCO/COMBINADO/BALANCETE só 3 têm passivo (circulante/não circulante) só negativo: 5b930fad, b5ce0a25 e 4a14371f, a convenção.
  -- Os outros grupos de Clientes/Fornecedores/Adiantamentos negativos NÃO são convenção: 044202cf (COMBINADO) tem a coluna "Crédito" (movimento) negativa ao lado de passivo positivo,
  -- 09e89930, 28923274 e 787ec844 (BALANCETE) misturam sinais. A coluna Crédito não é reproduzida aqui (a fixture usa uma coluna só); o arranjo "passivo positivo no documento" é a
  -- regra declarada que a exclui. O arranjo de Clientes negativo no ativo é o da revisão (não é de produção: nenhum documento tem ativo negativo SEM esse passivo; é guarda da regra).
  e_sc1 := teste_bal_0277(v_a, 'Credora Ativo 0277 Ltda', 41, jsonb_build_array(
    teste_ln_0277(1, 'Clientes', -100, 'milhar', null, null, 'Ativo Circulante', 'ativo_circulante'),
    teste_ln_0277(2, 'Fornecedores', 300, 'milhar', null, null, 'Passivo Circulante', 'passivo_circulante')), 'anual', '2025');
  v_r := teste_imp_0277(v_a, e_sc1, c_ar, '2025-12-31', 10000000);
  rr := teste_rec_0277(v_r, 'aging_ar_clientes');
  perform teste_assert_0277(rr.resultado = 'divergente' and rr.divergencia_abs = 200000 and rr.descricao like '%saldo NEGATIVO%a conta é do ativo%' and teste_pend_0277(v_a, e_sc1, 'aging_ar_clientes') = 1
                            and (rr.fonte_b ->> 'convencao_de_sinal_provada')::boolean = false and (rr.fonte_b ->> 'valor')::numeric = -100000,
    'Clientes -100 mil (saldo credor no ATIVO) contra a carteira de R$ 100.000 DIVERGE em R$ 200.000, com pendência e o aviso (antes: ok, "Conferido")', rr.resultado || ' | ' || coalesce(rr.divergencia_abs::text, 'null') || ' | ' || coalesce(rr.descricao, ''));
  -- Fornecedores negativo num documento que TAMBÉM imprime passivo positivo (a forma de 787ec844/28923274: Fornecedores negativo, outras contas de passivo positivas): saldo credor ou movimento, não convenção.
  e_sc2 := teste_bal_0277(v_a, 'Passivo Misto 0277 Ltda', 42, jsonb_build_array(
    teste_ln_0277(1, 'FORNECEDORES', -4719, 'milhar', null, null, 'Passivo Circulante', 'passivo_circulante'),
    teste_ln_0277(2, 'Empréstimos e financiamentos', 1200, 'milhar', null, null, 'Passivo Circulante', 'passivo_circulante')), 'anual', '2025');
  v_r := teste_imp_0277(v_a, e_sc2, c_ap, '2025-12-31', 471900000);
  rr := teste_rec_0277(v_r, 'aging_ap_fornecedores');
  perform teste_assert_0277(rr.resultado = 'divergente' and rr.divergencia_abs = 9438000 and rr.descricao like '%saldo NEGATIVO%o documento tem 1 linhas de passivo positivas%' and rr.descricao not like '%impresso com sinal negativo%',
    'Fornecedores -4.719 num documento com passivo POSITIVO: não é convenção, compara com o sinal (diverge em 9.438.000, com o aviso do porquê); antes: conferia em silêncio', rr.resultado || ' | ' || coalesce(rr.divergencia_abs::text, 'null') || ' | ' || coalesce(rr.descricao, ''));
  -- Controle: a convenção provada (passivo só negativo) segue conferindo, e o patrimônio líquido positivo NÃO a desprova (5b930fad e b5ce0a25 têm 2 linhas de PL positivas).
  e_sc3 := teste_bal_0277(v_a, 'Passivo Negativo 0277 Ltda', 43, jsonb_build_array(
    teste_ln_0277(1, 'FORNECEDORES', -5621, 'milhar', null, null, 'Passivo Circulante', 'passivo_circulante'),
    teste_ln_0277(2, 'Empréstimos e financiamentos', -2000, 'milhar', null, null, 'Passivo Circulante', 'passivo_circulante'),
    teste_ln_0277(3, 'Capital social', 500, 'milhar', null, null, 'Patrimônio Líquido', 'patrimonio_liquido')), 'anual', '2025');
  v_r := teste_imp_0277(v_a, e_sc3, c_ap, '2025-12-31', 562100000);
  rr := teste_rec_0277(v_r, 'aging_ap_fornecedores');
  perform teste_assert_0277(rr.resultado = 'ok' and rr.divergencia_abs = 0 and (rr.fonte_b ->> 'convencao_de_sinal_provada')::boolean and rr.descricao like '%impresso com sinal negativo%',
    'controle: passivo só negativo (com capital social positivo) é convenção provada: Fornecedores -5.621 confere com a carteira de 5.621.000', rr.resultado || ' | ' || coalesce(rr.divergencia_abs::text, 'null'));
  -- Sinais MISTURADOS entre as linhas que entram, soma negativa (nunca visto em produção): guarda da regra declarada, soma com sinal, divergência e o aviso dos sinais opostos.
  e_sc4 := teste_bal_0277(v_a, 'Soma Negativa 0277 Ltda', 44, jsonb_build_array(
    teste_ln_0277(1, 'Clientes nacionais', 50, 'milhar', null, null, 'Ativo Circulante', 'ativo_circulante'),
    teste_ln_0277(2, 'Clientes exterior', -90, 'milhar', null, null, 'Ativo Circulante', 'ativo_circulante')), 'anual', '2025');
  v_r := teste_imp_0277(v_a, e_sc4, c_ar, '2025-12-31', 4000000);
  rr := teste_rec_0277(v_r, 'aging_ar_clientes');
  perform teste_assert_0277(rr.resultado = 'divergente' and rr.divergencia_abs = 80000 and rr.descricao like '%sinais opostos (1 positivas, 1 negativas)%a soma com sinal foi a comparada%',
    'guarda (arranjo que produção não produz): linhas de sinais opostos com soma NEGATIVA (50 - 90) contra a carteira de 40.000 divergem em 80.000 (soma com sinal), não ok pelo módulo', rr.resultado || ' | ' || coalesce(rr.divergencia_abs::text, 'null') || ' | ' || coalesce(rr.descricao, ''));
  -- O ativo negativo mesmo em documento que imprime o passivo só negativo (a forma de 5b930fad: 2 linhas de ativo negativas, 0 de passivo positivas): saldo credor do ATIVO não é convenção.
  e_sc5 := teste_bal_0277(v_a, 'Credora Convencao 0277 Ltda', 45, jsonb_build_array(
    teste_ln_0277(1, 'Clientes', -100, 'milhar', null, null, 'Ativo Circulante', 'ativo_circulante'),
    teste_ln_0277(2, 'Empréstimos e financiamentos', -300, 'milhar', null, null, 'Passivo Circulante', 'passivo_circulante')), 'anual', '2025');
  v_r := teste_imp_0277(v_a, e_sc5, c_ar, '2025-12-31', 10000000);
  rr := teste_rec_0277(v_r, 'aging_ar_clientes');
  perform teste_assert_0277(rr.resultado = 'divergente' and rr.divergencia_abs = 200000 and rr.descricao like '%a conta é do ativo%',
    'Clientes -100 mil no ATIVO, num documento em que o passivo é só negativo: a convenção é do passivo, então compara com o sinal e DIVERGE em 200.000', rr.resultado || ' | ' || coalesce(rr.divergencia_abs::text, 'null'));
  -- Linhas de Fornecedores SEM seção nem secao_canonica (o registro de campos classifica pela seção em texto; sem ela a IA não classificou: 67 linhas assim em produção) de sinais opostos e soma negativa, num documento de passivo só negativo: o grupo não é todo negativo, não é convenção.
  e_sc3 := teste_bal_0277(v_a, 'Grupo Misto Nulo 0277 Ltda', 46, jsonb_build_array(
    teste_ln_0277(1, 'Fornecedores nacionais', 50, 'milhar'),
    teste_ln_0277(2, 'Fornecedores exterior', -90, 'milhar'),
    teste_ln_0277(3, 'Empréstimos e financiamentos', -300, 'milhar', null, null, 'Passivo Circulante', 'passivo_circulante')), 'anual', '2025');
  v_r := teste_imp_0277(v_a, e_sc3, c_ap, '2025-12-31', 4000000);
  rr := teste_rec_0277(v_r, 'aging_ap_fornecedores');
  perform teste_assert_0277(rr.resultado = 'divergente' and rr.divergencia_abs = 80000 and rr.descricao like '%sinais opostos%',
    'guarda: Fornecedores de sinais opostos (50 e -90, sem secao_canonica) com o passivo do documento só negativo NÃO é convenção (todas as linhas do grupo teriam de ser negativas): soma com sinal, diverge em 80.000', rr.resultado || ' | ' || coalesce(rr.divergencia_abs::text, 'null'));

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

  -- ================================================================== 5c. A FUSÃO DE ENTIDADES NÃO APAGA A CARTEIRA EM SILÊNCIO
  raise notice '--- 5c. fn_fundir_entidade leva a carteira de aging da absorvida ---';
  -- Regra 4: a fusão é a real (fn_fundir_entidade, como o AUTHENTICATED, que é quem funde); a carteira é montada (DM7: não há arquivo de aging real). Nenhuma fusão com aging existe em produção
  -- (aging_importado tinha 0 linhas em 12/11/2026): o defeito foi REPRODUZIDO na revisão (depois da fusão: aging=0, pendência aberta=1, eventos=0), não observado.
  v_f := fn_upsert_caso('0277 — mandato F (fusão)');
  e_f1 := teste_bal_0277(v_f, 'Helios Quimica 0277 Ltda', 51, jsonb_build_array(teste_ln_0277(1, 'Clientes', 50, 'milhar', null, null, 'Ativo Circulante', 'ativo_circulante')), 'anual', '2025');
  e_f2 := teste_bal_0277(v_f, 'Quasar Logistica 0277 SA', 52, jsonb_build_array(teste_ln_0277(1, 'Clientes', 80, 'milhar', null, null, 'Ativo Circulante', 'ativo_circulante')), 'anual', '2025');
  update documento set criado_em = now() + interval '1 minute' where caso_id = v_f and entidade_id = e_f2;
  v_r := teste_imp_0277(v_f, e_f1, c_ar, '2025-12-31', 10000000);
  v_ag1 := (v_r ->> 'id')::uuid;
  perform teste_assert_0277(teste_pend_0277(v_f, e_f1, 'aging_ar_clientes') = 1, 'preparo: a carteira da absorvida (R$ 100.000 contra Clientes 50 milhar) abre a pendência', teste_pend_0277(v_f, e_f1, 'aging_ar_clientes')::text);
  v_t := teste_funde_0277(v_f, e_f1, e_f2);
  perform teste_assert_0277(v_t like 'ok|%' and (substr(v_t, 4)::jsonb ->> 'aging_movido') = '1', 'a fusão (como authenticated) funciona com a absorvida tendo carteira, e diz quantas importações levou', v_t);
  perform teste_assert_0277((select count(*) from aging_importado where caso_id = v_f) = 1 and (select entidade_id from aging_importado where id = v_ag1) = e_f2 and (select substituido_em from aging_importado where id = v_ag1) is null,
    'a carteira da absorvida NÃO sumiu: é a vigente da sobrevivente (antes: o cascade a apagava sem evento, aging=0)', (select count(*)::text from aging_importado where caso_id = v_f));
  perform teste_assert_0277(teste_pend_0277(v_f, e_f2, 'aging_ar_clientes') = 1
                            and not exists (select 1 from pendencia p where p.caso_id = v_f and p.motivo like 'reconciliacao:aging\_%' and p.estado <> 'resolvida'
                                              and not exists (select 1 from aging_importado ai where ai.caso_id = v_f and ai.entidade_id = p.entidade_id and ai.data_base = p.data_base and ai.substituido_em is null)),
    'toda pendência aberta do aging tem a carteira vigente que a originou (antes: pendência aberta, com data_base, sem importação nenhuma)', teste_pend_0277(v_f, e_f2, 'aging_ar_clientes')::text);
  perform teste_assert_0277((select count(*) from evento_auditoria where acao = 'aging_levado_na_fusao' and entidade_ref = 'entidade:' || e_f2) = 1
                            and (select jsonb_array_length(depois -> 'importacoes_movidas') from evento_auditoria where acao = 'aging_levado_na_fusao' and entidade_ref = 'entidade:' || e_f2) = 1
                            and (select (depois -> 'aging' ->> 'movidos') from evento_auditoria where acao = 'entidade_fundida' and entidade_ref = 'entidade:' || e_f2) = '1',
    'a carteira levada deixa evento (aging_levado_na_fusao) e o entidade_fundida traz o aging movido', (select count(*)::text from evento_auditoria where acao = 'aging_levado_na_fusao' and entidade_ref = 'entidade:' || e_f2));
  -- E a pendência se resolve: a reimportação da sobrevivente (carteira que confere com o balanço dela, 80 milhar) substitui a carteira que veio da absorvida.
  v_r2 := teste_imp_0277(v_f, e_f2, c_ar, '2025-12-31', 8000000);
  perform teste_assert_0277((v_r2 ->> 'substitui')::uuid = v_ag1 and teste_pend_0277(v_f, e_f2, 'aging_ar_clientes') = 0,
    'reimportar a carteira na sobrevivente substitui a que veio da absorvida e RESOLVE a pendência', coalesce(v_r2 ->> 'substitui', 'null') || ' | ' || teste_pend_0277(v_f, e_f2, 'aging_ar_clientes')::text);

  -- Colisão: as duas têm carteira VIGENTE da mesma (tipo_base, data_base). A da absorvida (que também tem uma importação já substituída) vira SUBSTITUÍDA pela da sobrevivente; nada é apagado.
  e_f3 := teste_bal_0277(v_f, 'Boreal Embalagens 0277 Ltda', 53, jsonb_build_array(teste_ln_0277(1, 'Clientes', 50, 'milhar', null, null, 'Ativo Circulante', 'ativo_circulante')), 'anual', '2025');
  e_f4 := teste_bal_0277(v_f, 'Cobalto Servicos 0277 SA', 54, jsonb_build_array(teste_ln_0277(1, 'Clientes', 80, 'milhar', null, null, 'Ativo Circulante', 'ativo_circulante')), 'anual', '2025');
  perform teste_imp_0277(v_f, e_f3, c_ar, '2024-12-31', 9000000);
  v_r := teste_imp_0277(v_f, e_f3, c_ar, '2025-12-31', 9000000);
  v_r := teste_imp_0277(v_f, e_f3, c_ar, '2025-12-31', 10000000);
  v_ag1 := (v_r ->> 'id')::uuid;
  v_r2 := teste_imp_0277(v_f, e_f4, c_ar, '2025-12-31', 8000000);
  v_ag2 := (v_r2 ->> 'id')::uuid;
  v_n := (select count(*) from aging_importado where entidade_id in (e_f3, e_f4));
  perform teste_assert_0277(v_n = 4 and teste_pend_0277(v_f, e_f3, 'aging_ar_clientes') = 2 and teste_pend_0277(v_f, e_f4, 'aging_ar_clientes') = 0,
    'preparo: a absorvida tem 3 importações (31/12/2024, 31/12/2025 substituída e 31/12/2025 vigente) e 2 pendências (a de 2024, sem par, e a de 2025, divergente), a sobrevivente 1 importação e nenhuma pendência', v_n || ' | ' || teste_pend_0277(v_f, e_f3, 'aging_ar_clientes') || ' | ' || teste_pend_0277(v_f, e_f4, 'aging_ar_clientes'));
  v_t := teste_funde_0277(v_f, e_f3, e_f4);
  perform teste_assert_0277(v_t like 'ok|%' and (substr(v_t, 4)::jsonb ->> 'aging_movido') = '3' and (substr(v_t, 4)::jsonb ->> 'aging_substituido') = '1',
    'a fusão com a MESMA data-base nas duas (o índice de uma vigente por data-base) funciona: leva as 3 importações e declara 1 substituída', v_t);
  perform teste_assert_0277((select count(*) from aging_importado where entidade_id = e_f4) = 4
                            and (select count(*) from aging_importado where entidade_id = e_f4 and tipo_base = c_ar and data_base = '2025-12-31' and substituido_em is null) = 1
                            and (select substituido_por from aging_importado where id = v_ag1) = v_ag2,
    'nenhuma importação sumiu (4 na sobrevivente), uma vigente por data-base, e a vigente da absorvida foi substituída pela da sobrevivente (que prevalece)', (select count(*)::text from aging_importado where entidade_id = e_f4));
  perform teste_assert_0277(teste_pend_0277(v_f, e_f4, 'aging_ar_clientes') = 1
                            and (select p.data_base from pendencia p where p.caso_id = v_f and p.entidade_id = e_f4 and p.motivo = 'reconciliacao:aging_ar_clientes' and p.estado <> 'resolvida') = '2024-12-31'
                            and (select jsonb_array_length(depois -> 'importacoes_substituidas') from evento_auditoria where acao = 'aging_levado_na_fusao' and entidade_ref = 'entidade:' || e_f4) = 1
                            and (select jsonb_array_length(depois -> 'pendencias_resolvidas') from evento_auditoria where acao = 'aging_levado_na_fusao' and entidade_ref = 'entidade:' || e_f4) = 1,
    'a pendência da carteira SUBSTITUÍDA (31/12/2025) é resolvida pela fusão e o evento diz qual; a de 31/12/2024, cuja carteira veio junto, segue aberta (a sobrevivente não herda divergência de carteira que deixou de ser a vigente, e não perde a que é)', teste_pend_0277(v_f, e_f4, 'aging_ar_clientes')::text);
  -- Controle: fusão sem carteira nenhuma não grava evento de aging.
  e_f5 := teste_bal_0277(v_f, 'Delta Metais 0277 Ltda', 55, jsonb_build_array(teste_ln_0277(1, 'Clientes', 10, 'milhar', null, null, 'Ativo Circulante', 'ativo_circulante')), 'anual', '2025');
  e_f6 := teste_bal_0277(v_f, 'Epsilon Tintas 0277 SA', 56, jsonb_build_array(teste_ln_0277(1, 'Clientes', 20, 'milhar', null, null, 'Ativo Circulante', 'ativo_circulante')), 'anual', '2025');
  v_t := teste_funde_0277(v_f, e_f5, e_f6);
  perform teste_assert_0277(v_t like 'ok|%' and (substr(v_t, 4)::jsonb ->> 'aging_movido') = '0' and not exists (select 1 from evento_auditoria where acao = 'aging_levado_na_fusao' and entidade_ref = 'entidade:' || e_f6),
    'controle: fusão sem carteira funciona, devolve aging_movido = 0 e não grava evento de aging', v_t);
  -- A FK: apagar entidade que tem carteira reprova (23503), em vez de apagar o resumo; apagar o MANDATO inteiro continua funcionando (a cascata do caso).
  insert into entidade (caso_id, razao_social) values (v_f, 'Sem Documento 0277') returning id into e_sc5;
  perform teste_imp_0277(v_f, e_sc5, c_ap, '2025-12-31', 1000000);
  -- Tira o que a conciliação gravou para a entidade (reconciliacao e pendencia também a referenciam): sobra a carteira como ÚNICA razão de a FK reprovar.
  delete from reconciliacao where entidade_id = e_sc5;
  delete from pendencia where entidade_id = e_sc5;
  begin
    delete from entidade where id = e_sc5;
    v_t := 'apagou';
  exception when foreign_key_violation then v_t := sqlerrm;
  end;
  perform teste_assert_0277(v_t like '%aging_importado_entidade_id_fkey%' and exists (select 1 from aging_importado where entidade_id = e_sc5), 'apagar entidade com carteira reprova (23503) e a carteira continua lá (antes: cascade apagava sem trilha)', v_t);
  begin
    delete from caso where id = v_f;
    v_t := 'apagou';
  exception when others then v_t := sqlstate || '|' || sqlerrm;
  end;
  perform teste_assert_0277(v_t = 'apagou' and not exists (select 1 from aging_importado where caso_id = v_f), 'apagar o MANDATO com carteira continua funcionando (a cascata do caso apaga entidade e aging na mesma instrução)', v_t);
  -- A função de levar a carteira só é chamada pela fusão (revisão: o authenticated tem EXECUTE e a chamava por /rpc, fora de uma fusão). Direto, como Sócio e como Analista alocado:
  -- recusada (42501) e NADA move (a carteira de A não vai para B, A continua existindo, a pendência de A não fica órfã). A fusão real (acima) segue levando.
  v_g := fn_upsert_caso('0277 — mandato G (levar direto)');
  insert into auth.users (id, email) values (u_ana77, 'ana@0277.local') on conflict (id) do nothing;
  perform fn_definir_papel(u_ana77, 'analista');
  e_g1 := teste_bal_0277(v_g, 'Ferro Alfa 0277 Ltda', 61, jsonb_build_array(teste_ln_0277(1, 'Clientes', 50, 'milhar', null, null, 'Ativo Circulante', 'ativo_circulante')), 'anual', '2025');
  e_g2 := teste_bal_0277(v_g, 'Gama Beta 0277 SA', 62, jsonb_build_array(teste_ln_0277(1, 'Clientes', 80, 'milhar', null, null, 'Ativo Circulante', 'ativo_circulante')), 'anual', '2025');
  e_g3 := teste_bal_0277(v_g, 'Ônix Delta 0277 Ltda', 63, jsonb_build_array(teste_ln_0277(1, 'Clientes', 50, 'milhar', null, null, 'Ativo Circulante', 'ativo_circulante')), 'anual', '2025');
  e_g4 := teste_bal_0277(v_g, 'Prata Eta 0277 SA', 64, jsonb_build_array(teste_ln_0277(1, 'Clientes', 80, 'milhar', null, null, 'Ativo Circulante', 'ativo_circulante')), 'anual', '2025');
  perform fn_alocar(v_g, u_ana77);
  perform teste_imp_0277(v_g, e_g1, c_ar, '2025-12-31', 10000000);
  v_n := (select count(*) from evento_auditoria where acao = 'aging_levado_na_fusao');
  v_t := teste_levar_direto_0277(v_g, e_g1, e_g2, 'quem-eu-quiser');
  perform teste_assert_0277(v_t = '42501', 'chamada direta de fn_aging_levar_na_fusao como SÓCIO (authenticated, fora de uma fusão) é recusada (42501)', v_t);
  v_uid_ant := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', u_ana77, 'role', 'authenticated')::text, true);
  v_t := teste_levar_direto_0277(v_g, e_g1, e_g2, 'quem-eu-quiser');
  v_n2 := (select count(*) from aging_importado where caso_id = v_g and entidade_id = e_g1 and substituido_em is null);
  perform set_config('request.jwt.claims', v_uid_ant, true);
  perform teste_assert_0277(v_t = '42501', 'chamada direta como ANALISTA ALOCADO no mandato (authenticated, fora de uma fusão) é recusada (42501)', v_t);
  perform teste_assert_0277(v_n2 = 1 and not exists (select 1 from aging_importado where entidade_id = e_g2) and exists (select 1 from entidade where id = e_g1)
                            and teste_pend_0277(v_g, e_g1, 'aging_ar_clientes') = 1 and teste_pend_0277(v_g, e_g2, 'aging_ar_clientes') = 0
                            and (select count(*) from evento_auditoria where acao = 'aging_levado_na_fusao') = v_n,
    'a chamada direta recusada não move nada: a carteira e a pendência seguem na entidade de origem, a origem existe, nenhum evento (antes: a carteira ia para B, A ficava e a pendência de A ficava órfã)', v_n2 || ' | ' || teste_pend_0277(v_g, e_g1, 'aging_ar_clientes') || ' | ' || teste_pend_0277(v_g, e_g2, 'aging_ar_clientes'));
  -- A fusão real, na mesma entidade, continua levando; e o ator do evento é o usuário logado, não o texto de p_por.
  v_t := teste_funde_0277(v_g, e_g1, e_g2);
  select e.ator into v_ator from evento_auditoria e where e.acao = 'aging_levado_na_fusao' and e.entidade_ref = 'entidade:' || e_g2;
  perform teste_assert_0277(v_t like 'ok|%' and (substr(v_t, 4)::jsonb ->> 'aging_movido') = '1' and (select entidade_id from aging_importado where caso_id = v_g and substituido_em is null and entidade_id = e_g2 limit 1) = e_g2,
    'a fusão real, depois das chamadas diretas recusadas, continua levando a carteira', v_t);
  perform teste_assert_0277(v_ator = 'usuario:00000000-0000-0000-0000-00000000a001', 'o ator do evento aging_levado_na_fusao é o usuário logado (auth.uid), não o `p_por` que a fusão recebeu', v_ator);
  -- A função de levar a carteira checa quem chama (ela é definer): alguém sem papel no mandato leva 42501. A guarda da fusão é armada à mão para que ESTE assert meça só o papel.
  perform set_config('oria.fusao_de', e_cmp::text, true);
  v_uid_ant := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-0000-0000-00000000dead', 'role', 'authenticated')::text, true);
  begin
    perform fn_aging_levar_na_fusao(v_a, e_cmp, e_cmp2, 'teste:0277');
    v_t := 'passou';
  exception when others then v_t := sqlstate;
  end;
  perform set_config('request.jwt.claims', v_uid_ant, true);
  perform set_config('oria.fusao_de', '', true);
  perform teste_assert_0277(v_t = '42501', 'fn_aging_levar_na_fusao (security definer) recusa quem não escreve no mandato (42501)', v_t);

  -- ================================================================== 6. A SONDA
  raise notice '--- 6. a sonda enxerga a 0277 ---';
  perform teste_assert_0277((select count(*) from fn_instalacao_conferir() where migration = '0277' and presente) = 14 and (select count(*) from fn_instalacao_conferir() where migration = '0277') = 14,
    'os 14 requisitos da 0277 existem no catálogo e estão presentes', (select string_agg(chave || ':' || presente, ', ') from fn_instalacao_conferir() where migration = '0277'));
  perform teste_assert_0277((select ate_migration from instalacao_cobertura where id = true) >= '0277', 'a cobertura da sonda foi até a 0277', (select ate_migration from instalacao_cobertura where id = true));

  raise notice 'TODOS OS TESTES DA 0277 PASSARAM (% asserts executados)', current_setting('ct77.execucoes', true);
end $$;
