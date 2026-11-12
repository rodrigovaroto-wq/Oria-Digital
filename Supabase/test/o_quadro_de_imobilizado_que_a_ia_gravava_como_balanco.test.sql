-- Testes da 0271: o tipo COMPOSICAO_IMOBILIZADO (quadro de bens do ativo imobilizado) existe e o documento dele NÃO entra nas checagens de balanço.
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO PROVA (comportamento, não mecanismo):
--   (A) o tipo existe, está ativo, é complementar (não mexe no Kit Básico nem na completude), não é societário (então zero linha com tem_dado_financeiro = false é falha, não normalidade) e
--       está declarado no portão D6.
--   (B) o MESMO quadro (linhas TOTAL nas colunas Custo, Depreciação acumulada e Valor líquido, anual 2025, ao lado de um fluxo de caixa de 2025) registrado como COMPOSICAO_IMOBILIZADO não abre
--       ativo_passivo_pl nem caixa_bp_fluxo: nenhuma reconciliação "sem período par", nenhuma pendência de pré-condição, nenhuma "linha exigida do BALANCO ausente". Registrado como BALANCO (o defeito,
--       CONTROLE), o mesmo arranjo abre as duas "sem período par" com as pendências: é isso que prova que o arranjo enxerga o defeito, e que a ausência em (B) não é arranjo vazio.
--   (C) a linha do quadro NÃO entra na soma do realizado (abertura analítica: o balanço já declara a conta Imobilizado); a mesma linha num BALANCO entra (CONTROLE).
--   (D) a migration é idempotente: reaplicada, não duplica o tipo nem a declaração.
--   (E) a sonda enxerga o requisito da 0271.
--
-- ARRANJO (regra 4): o quadro real de produção (`27_Composicao_do_Imobilizado_Canastra_Industria_2025.pdf`) não está no banco de teste; o arranjo é à mão e reproduz o que a ficha mediu
-- (colunas Custo/Depreciação acumulada/Valor líquido, linhas TOTAL só nessas colunas, período anual 2025, a IA o classificando como BALANCO). Documento e linhas vêm de fn_registrar_documento e
-- fn_registrar_campos_extraidos DE VERDADE; as reconciliações rodam por fn_reconciliar_caso. O teste NÃO afirma que a IA passa a classificar o quadro certo: isso só acontece depois da republicação do n8n.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número reprovado por sabotagem está no cabeçalho de Supabase/migrations/0271_o_quadro_de_imobilizado_que_a_ia_gravava_como_balanco.sql ("MEDIÇÃO NÃO-VAZIA").
-- `p271.medindo = on` (PGOPTIONS='-c p271.medindo=on') vira `raise warning` e CONTA.

\set ON_ERROR_STOP on

create or replace function teste_assert_p271(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('p271.execucoes', (coalesce(nullif(current_setting('p271.execucoes', true), ''), '0')::int + 1)::text, false);
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  elsif current_setting('p271.medindo', true) = 'on' then
    perform set_config('p271.falhas', (coalesce(nullif(current_setting('p271.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- O mesmo arranjo, com o tipo como parâmetro: o quadro (6 linhas, nenhuma com ano na coluna, como o de produção) + um fluxo de caixa de 2025. Devolve o caso.
create or replace function teste_caso_p271(p_nome text, p_tipo text) returns uuid language plpgsql as $$
declare v_caso uuid; v_r jsonb; v_l jsonb;
begin
  v_caso := (fn_upsert_caso(p_nome))::uuid;
  v_r := fn_registrar_documento(v_caso, 'CANASTRA P271 LTDA', 'anual', '2025', p_tipo, 0.97, 'nome_arquivo', 'supabase_storage', 'p271/' || p_tipo || '.pdf', p_tipo || '.pdf', true, 'P271-' || p_tipo, 'ok');
  v_l := jsonb_build_array(
    jsonb_build_object('ordem', 1, 'chave', 'Terrenos', 'periodo_coluna', 'Custo', 'valor_num', 1000),
    jsonb_build_object('ordem', 2, 'chave', 'Terrenos', 'periodo_coluna', 'Depreciação acumulada', 'valor_num', 0),
    jsonb_build_object('ordem', 3, 'chave', 'Terrenos', 'periodo_coluna', 'Valor líquido', 'valor_num', 1000),
    jsonb_build_object('ordem', 4, 'chave', 'TOTAL', 'periodo_coluna', 'Custo', 'valor_num', 5000),
    jsonb_build_object('ordem', 5, 'chave', 'TOTAL', 'periodo_coluna', 'Depreciação acumulada', 'valor_num', 2000),
    jsonb_build_object('ordem', 6, 'chave', 'TOTAL', 'periodo_coluna', 'Valor líquido', 'valor_num', 3000));
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid,
    (select jsonb_agg(e || jsonb_build_object('unidade', 'milhar', 'confianca', 0.97)) from jsonb_array_elements(v_l) e), 'N2');
  v_r := fn_registrar_documento(v_caso, 'CANASTRA P271 LTDA', 'anual', '2025', 'FLUXO_CAIXA', 0.97, 'nome_arquivo', 'supabase_storage', 'p271/dfc-' || p_tipo || '.pdf', 'dfc-' || p_tipo || '.pdf', true, 'P271DFC-' || p_tipo, 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem', 1, 'chave', 'Caixa e equivalentes de caixa no final do período', 'periodo_coluna', '2025', 'valor_num', 700, 'unidade', 'milhar', 'confianca', 0.97, 'secao_canonica', 'caixa_final'),
    jsonb_build_object('ordem', 2, 'chave', 'Caixa e equivalentes de caixa no início do período', 'periodo_coluna', '2025', 'valor_num', 500, 'unidade', 'milhar', 'confianca', 0.97, 'secao_canonica', 'caixa_inicial')), 'N2');
  perform fn_reconciliar_caso(v_caso);
  return v_caso;
end $$;

-- (C) uma linha só, COM ano na coluna e seção canônica, para o realizado; o tipo é parâmetro. Separada do arranjo acima porque uma coluna "2025" daria exercício ao quadro e esconderia o defeito.
create or replace function teste_caso_realizado_p271(p_nome text, p_tipo text) returns uuid language plpgsql as $$
declare v_caso uuid; v_r jsonb;
begin
  v_caso := (fn_upsert_caso(p_nome))::uuid;
  v_r := fn_registrar_documento(v_caso, 'CANASTRA P271 LTDA', 'anual', '2025', p_tipo, 0.97, 'nome_arquivo', 'supabase_storage', 'p271r/' || p_tipo || '.pdf', 'r-' || p_tipo || '.pdf', true, 'P271R-' || p_tipo, 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem', 1, 'chave', 'Imobilizado liquido do quadro', 'periodo_coluna', '2025', 'valor_num', 3000, 'unidade', 'milhar', 'confianca', 0.97, 'secao_canonica', 'ativo_nao_circulante')), 'N2');
  return v_caso;
end $$;

delete from caso where nome like 'Caso P271 %';

do $$
declare
  v_t record; v_n int; v_ver text; v_c uuid; v_b uuid;
begin
  raise notice '--- A. o tipo existe, é complementar, não é societário e está no D6 ---';
  select * into v_t from taxonomia_tipo_documento where codigo = 'COMPOSICAO_IMOBILIZADO';
  perform teste_assert_p271(v_t.codigo is not null and v_t.ativo, 'COMPOSICAO_IMOBILIZADO existe na taxonomia e está ativo');
  perform teste_assert_p271(v_t.obrigatoriedade = 'complementar', 'é complementar: não entra no Kit Básico nem muda a completude', v_t.obrigatoriedade::text);
  perform teste_assert_p271(v_t.categoria = 'Contábil/Demonstrações', 'categoria Contábil/Demonstrações (demonstrativo contábil, como NOTAS_EXPL)', v_t.categoria);
  perform teste_assert_p271(not fn_tipo_sem_dado_por_natureza('COMPOSICAO_IMOBILIZADO'), 'não é "sem dado por natureza": zero linha com tem_dado_financeiro = false é falha, não normalidade');
  perform teste_assert_p271(v_t.abertura_analitica and v_t.autoridade = 0 and not v_t.nao_sobrepujavel, 'abertura analítica, autoridade 0 e sobrepujável (anexo: o balanço manda)');
  select count(*) into v_n from taxonomia_tipo_documento where obrigatoriedade = 'obrigatorio';
  perform teste_assert_p271(v_n = 8, 'o Kit Básico continua com os 8 obrigatórios', v_n::text);
  perform teste_assert_p271((select veredito from fn_cobertura_de_tipos() where tipo_taxonomia = 'COMPOSICAO_IMOBILIZADO') not in ('SEM_COBERTURA', 'DECLARACAO_QUEBRADA'),
    'D6: o tipo tem declaração de cobertura válida', (select veredito from fn_cobertura_de_tipos() where tipo_taxonomia = 'COMPOSICAO_IMOBILIZADO'));
  perform teste_assert_p271(exists (select 1 from instalacao_sonda_cobertura_de_tipos), 'o portão D6 estrito continua verde com o tipo novo');

  raise notice '--- B. o quadro registrado como COMPOSICAO_IMOBILIZADO não abre as checagens de balanço; como BALANCO (o defeito) abre ---';
  v_c := teste_caso_p271('Caso P271 quadro', 'COMPOSICAO_IMOBILIZADO');
  v_b := teste_caso_p271('Caso P271 controle', 'BALANCO');

  select count(*) into v_n from reconciliacao where caso_id = v_b and tipo = 'ativo_passivo_pl' and motivo_precondicao = 'sem_periodo_par';
  perform teste_assert_p271(v_n = 1, 'CONTROLE: o quadro como BALANCO dá ativo_passivo_pl "sem_periodo_par" (o defeito de produção está no arranjo)', v_n::text);
  select count(*) into v_n from reconciliacao where caso_id = v_b and tipo = 'caixa_bp_fluxo' and motivo_precondicao = 'sem_periodo_par';
  perform teste_assert_p271(v_n = 1, 'CONTROLE: e caixa_bp_fluxo "sem_periodo_par"', v_n::text);
  select count(*) into v_n from pendencia where caso_id = v_b and tipo = 'precondicao_nao_satisfeita' and estado <> 'resolvida'
     and (motivo = 'reconciliacao:ativo_passivo_pl' or motivo = 'reconciliacao:caixa_bp_fluxo');
  perform teste_assert_p271(v_n = 2, 'CONTROLE: com as 2 pendências abertas, como no Canastra', v_n::text);

  select count(*) into v_n from reconciliacao where caso_id = v_c and tipo = 'ativo_passivo_pl';
  perform teste_assert_p271(v_n = 0, 'o quadro como COMPOSICAO_IMOBILIZADO NÃO é conferido como balanço: nenhuma reconciliação ativo_passivo_pl', v_n::text);
  select count(*) into v_n from reconciliacao where caso_id = v_c and tipo = 'caixa_bp_fluxo' and motivo_precondicao = 'sem_periodo_par';
  perform teste_assert_p271(v_n = 0, 'e nenhum caixa_bp_fluxo "sem_periodo_par"', v_n::text);
  select count(*) into v_n from pendencia where caso_id = v_c and tipo = 'precondicao_nao_satisfeita'
     and (motivo = 'reconciliacao:ativo_passivo_pl' or motivo = 'reconciliacao:caixa_bp_fluxo');
  perform teste_assert_p271(v_n = 0, 'e nenhuma pendência de pré-condição dessas duas checagens', v_n::text);
  select count(*) into v_n from pendencia where caso_id = v_b and tipo = 'linha_exigida_ausente' and motivo like 'completude:linha_exigida:BALANCO:%';
  perform teste_assert_p271(v_n > 0, 'CONTROLE: como BALANCO ele ainda abre "linha exigida do BALANCO ausente"', v_n::text);
  select count(*) into v_n from pendencia where caso_id = v_c and tipo = 'linha_exigida_ausente' and motivo like 'completude:linha_exigida:BALANCO:%';
  perform teste_assert_p271(v_n = 0, 'como COMPOSICAO_IMOBILIZADO ele não abre "linha exigida do BALANCO ausente"', v_n::text);
  select d.tipo_taxonomia into v_ver from documento d where d.caso_id = v_c and d.tipo_taxonomia = 'COMPOSICAO_IMOBILIZADO';
  perform teste_assert_p271(v_ver = 'COMPOSICAO_IMOBILIZADO', 'o documento guarda o tipo novo (a chave estrangeira o aceita)', coalesce(v_ver, 'null'));

  raise notice '--- C. a linha do quadro não entra na soma do realizado (abertura analítica) ---';
  v_c := teste_caso_realizado_p271('Caso P271 realizado quadro', 'COMPOSICAO_IMOBILIZADO');
  v_b := teste_caso_realizado_p271('Caso P271 realizado controle', 'BALANCO');
  select count(*) into v_n from fn_linhas_do_realizado(v_c) where chave = 'Imobilizado liquido do quadro';
  perform teste_assert_p271(v_n = 0, 'a linha do quadro NÃO entra no realizado: o balanço já declara a conta Imobilizado', v_n::text);
  select count(*) into v_n from fn_linhas_do_realizado(v_b) where chave = 'Imobilizado liquido do quadro';
  perform teste_assert_p271(v_n = 1, 'CONTROLE: a mesma linha num BALANCO entra no realizado', v_n::text);
end $$;

-- (D) reaplicada, não duplica
\i Supabase/migrations/0271_o_quadro_de_imobilizado_que_a_ia_gravava_como_balanco.sql

do $$
declare
  v_n int;
begin
  raise notice '--- D. a migration é idempotente ---';
  select count(*) into v_n from taxonomia_tipo_documento where codigo = 'COMPOSICAO_IMOBILIZADO';
  perform teste_assert_p271(v_n = 1, 'reaplicada, o tipo continua em UMA linha', v_n::text);
  select count(*) into v_n from taxonomia_tipo_cobertura where tipo_taxonomia = 'COMPOSICAO_IMOBILIZADO';
  perform teste_assert_p271(v_n = 1, 'e a declaração do D6 continua em UMA linha', v_n::text);

  raise notice '--- E. a sonda enxerga o requisito da 0271 ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0271' and presente;
  perform teste_assert_p271(v_n = 1, 'o requisito da 0271 está presente na sonda', v_n::text);
  select count(*) into v_n from instalacao_requisito where migration = '0271';
  perform teste_assert_p271(v_n = 1, 'e o catálogo declara exatamente 1', v_n::text);

  if current_setting('p271.medindo', true) = 'on' then
    raise warning 'MEDIDO: % falha(s) de % execucoes', coalesce(current_setting('p271.falhas', true), '0'), current_setting('p271.execucoes', true);
  end if;
  raise notice 'TODOS OS TESTES DA 0271 PASSARAM';
end $$;

delete from caso where nome like 'Caso P271 %';
