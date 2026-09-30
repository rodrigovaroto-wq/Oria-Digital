-- Testes da 0196 (Supabase/migrations/0196_o_caixa_que_lia_a_dfc_de_outro_ano.sql).
-- Rodar via Supabase/test/run.sh.
--
-- O ARRANJO É O REAL, MEDIDO EM PRODUÇÃO (30/09/2026, caso bb37f726, book sintético
-- `Dados de Teste/book-vertentes`) — e nenhum dos fixtures existentes o tem: lá a DFC
-- e a DRE sempre trazem `periodo_coluna` (o ano em texto), nunca nulo:
--
--   • Balanço "multi 24,25", colunas "31/12/2024" (Disponível 4.840) e "31/12/2025" (500);
--   • DFC ANUAL 2025, SEM `periodo_coluna` nenhum (um exercício só), saldo final 500;
--   • Faturamento 24M "multi 24,25" com TRÊS colunas por mês ('2024', '2025' e
--     'Variação %'), rótulo "jan/2024 — jan/2025", e as linhas "TOTAL DO EXERCÍCIO",
--     "Média mensal" e "Ticket médio…" DEPOIS dos meses.
--
-- O QUE ESTE ARQUIVO TRAVA, em COMPORTAMENTO (regra 3):
--
--   1. Caixa: a DFC de 2025 NÃO é lida como saldo final de 2024 — 2025 confere, 2024
--      não é comparado (sem_periodo_par), e nenhuma pendência de divergência abre.
--   1b. O mesmo quando 2024 é o ÚNICO ano que sobraria: motivo sem_periodo_par, não
--      divergente.
--   2. CONTROLE: DFC com coluna 2024 de verdade e divergente SEGUE divergente.
--   3. CONTROLE: Balanço e DFC do MESMO ano, ambos sem coluna, seguem conferindo.
--   4. Faturamento: o ano vem da COLUNA, não do rótulo — 2024 soma 183.480 e 2025
--      soma 138.400 (12 meses cada), sem a coluna 'Variação %' nem o "Ticket médio";
--      a receita de cada ano confere com a DRE, e a tolerância Classe B segue valendo
--      (DRE 2024 18% abaixo da soma continua zona_cinzenta).
--   5. Receita: DRE de um ano só (sem coluna) não é lida como receita do outro ano.
--   6. Faturamento sem coluna de ano: coluna de percentual nunca entra na soma.
--   7. Despesa financeira: idem 5, para a DRE contra o Mapa de Dívida.
--
-- NÃO PARA NO PRIMEIRO ERRO: anota e segue, e o bloco final reprova com a CONTAGEM
-- (regra 2 — medir quantos asserts a correção desligada derruba).

begin;

create temp sequence _falhas_0196;

create or replace function pg_temp.teste_assert_0196(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  else
    raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
    perform nextval('pg_temp._falhas_0196');
  end if;
end $$;

-- O faturamento do book (12 meses, valores do `book-vertentes`), no formato que
-- produção tem: UMA linha de campo_extraido por célula.
create or replace function pg_temp.campos_faturamento_3_colunas() returns jsonb
language plpgsql as $$
declare
  meses text[] := array['jan','fev','mar','abr','mai','jun','jul','ago','set','out','nov','dez'];
  v24 numeric[] := array[15493,15948,16404,16100,16708,15796,15189,15644,14885,14429,13974,12910];
  v25 numeric[] := array[14452,13718,14085,12860,12493,12003,11268,10778,10533,9798,8818,7594];
  r jsonb := '[]'::jsonb;
  i int;
  rot text;
begin
  for i in 1..12 loop
    rot := format('%s/2024 — %s/2025', meses[i], meses[i]);
    r := r || jsonb_build_array(
      jsonb_build_object('ordem',i-1,'chave',rot,'periodo_coluna','2024','valor_num',v24[i]::text,'unidade','milhar','moeda','BRL','confianca','0.97'),
      jsonb_build_object('ordem',i-1,'chave',rot,'periodo_coluna','2025','valor_num',v25[i]::text,'unidade','milhar','moeda','BRL','confianca','0.97'),
      jsonb_build_object('ordem',i-1,'chave',rot,'periodo_coluna','Variação %','valor_num',round((v25[i]/v24[i]-1)*100, 1)::text,'confianca','0.97'));
  end loop;
  r := r || jsonb_build_array(
    jsonb_build_object('ordem',12,'chave','TOTAL DO EXERCÍCIO','periodo_coluna','2024','valor_num','183480','unidade','milhar','moeda','BRL','confianca','0.97'),
    jsonb_build_object('ordem',12,'chave','TOTAL DO EXERCÍCIO','periodo_coluna','2025','valor_num','138400','unidade','milhar','moeda','BRL','confianca','0.97'),
    jsonb_build_object('ordem',12,'chave','TOTAL DO EXERCÍCIO','periodo_coluna','Variação %','valor_num','-24.6','confianca','0.97'),
    jsonb_build_object('ordem',13,'chave','Média mensal','periodo_coluna','2024','valor_num','15290','unidade','milhar','moeda','BRL','confianca','0.97'),
    jsonb_build_object('ordem',13,'chave','Média mensal','periodo_coluna','2025','valor_num','11533','unidade','milhar','moeda','BRL','confianca','0.97'),
    jsonb_build_object('ordem',14,'chave','Ticket médio por pedido (R$ mil) — indicador gerencial','periodo_coluna','2024','valor_num','38.2','unidade','milhar','moeda','BRL','confianca','0.97'),
    jsonb_build_object('ordem',14,'chave','Ticket médio por pedido (R$ mil) — indicador gerencial','periodo_coluna','2025','valor_num','31.4','unidade','milhar','moeda','BRL','confianca','0.97'),
    jsonb_build_object('ordem',14,'chave','Ticket médio por pedido (R$ mil) — indicador gerencial','periodo_coluna','Variação %','valor_num','-17.8','confianca','0.97'));
  return r;
end $$;

-- =============================================================================
-- 1, 1b, 2, 3. CAIXA
-- =============================================================================
do $$
declare
  v_caso uuid; v_r jsonb; v_ent uuid; v_per uuid; v_rec uuid;
  v_res text; v_motivo text; v_desc text; v_anos text; v_n int;
begin
  raise notice '--- 1. caixa: DFC anual de 2025 (sem periodo_coluna) contra Balanço multi 24,25 ---';
  v_caso := (fn_upsert_caso('0196: caixa, DFC de um exercício só'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'CAIXA UM ANO LTDA.', 'multi', '24,25', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0196/bp.pdf', 'BP.pdf', true, 'HASH-0196-1', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Disponível','valor_num','4840','periodo_coluna','31/12/2024','unidade','milhar','confianca','0.97'),
    jsonb_build_object('ordem',1,'chave','Disponível','valor_num','500','periodo_coluna','31/12/2025','unidade','milhar','confianca','0.97')
  ), 'N2');
  select entidade_id, periodo_id into v_ent, v_per from documento where id = (v_r->>'documento_id')::uuid;
  v_r := fn_registrar_documento(v_caso, 'CAIXA UM ANO LTDA.', 'anual', '2025', 'FLUXO_CAIXA', 0.97,
    'nome_arquivo', 'supabase_storage', '0196/dfc.pdf', 'DFC.pdf', true, 'HASH-0196-2', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Caixa e equivalentes de caixa no final do exercício','valor_num','500','unidade','milhar','confianca','0.97')
  ), 'N2');

  v_r := fn_reconciliar_caixa_bp_fluxo(v_caso, v_ent, v_per);
  select resultado, descricao, materialidade->>'anos_checados' into v_res, v_desc, v_anos
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0196(v_res = 'ok',
    'Balanço 2024=4.840 × DFC anual 2025=500: a checagem CONCLUI ok (2025 confere), não divergente',
    format('resultado=%s | %s', v_res, v_desc));
  perform pg_temp.teste_assert_0196(v_anos = '1',
    'e compara UM ano só (2025) — a DFC de 2025 não é saldo final de 2024',
    format('anos_checados=%s', v_anos));
  perform pg_temp.teste_assert_0196(v_desc like '%2025: confere%' and v_desc not like '%2024: Caixa no Balanço%',
    'e a descrição não acusa diferença de 2024', v_desc);
  perform pg_temp.teste_assert_0196(v_desc like '%Não comparado%2024%',
    'e diz, em vez de calar, que 2024 não foi comparado (regra 1)', v_desc);
  select count(*) into v_n from pendencia
   where caso_id = v_caso and estado <> 'resolvida' and tipo = 'divergencia_reconciliacao';
  perform pg_temp.teste_assert_0196(v_n = 0,
    'e nenhuma pendência de divergência (Classe A) fica aberta', format('abertas=%s', v_n));

  raise notice '--- 1b. o único ano possível é o que a DFC não cobre: sem_periodo_par, não divergente ---';
  v_caso := (fn_upsert_caso('0196: caixa, só sobra 2024'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'CAIXA SO 2024 LTDA.', 'multi', '24,25', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0196/bp-b.pdf', 'BP B.pdf', true, 'HASH-0196-3', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Disponível','valor_num','4840','periodo_coluna','31/12/2024','unidade','milhar','confianca','0.97')
  ), 'N2');
  select entidade_id, periodo_id into v_ent, v_per from documento where id = (v_r->>'documento_id')::uuid;
  v_r := fn_registrar_documento(v_caso, 'CAIXA SO 2024 LTDA.', 'anual', '2025', 'FLUXO_CAIXA', 0.97,
    'nome_arquivo', 'supabase_storage', '0196/dfc-b.pdf', 'DFC B.pdf', true, 'HASH-0196-4', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Saldo final de caixa','valor_num','500','unidade','milhar','confianca','0.97')
  ), 'N2');
  v_r := fn_reconciliar_caixa_bp_fluxo(v_caso, v_ent, v_per);
  select resultado, motivo_precondicao, descricao into v_res, v_motivo, v_desc
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0196(v_res <> 'divergente',
    'Balanço só com 2024 (4.840) × DFC anual 2025: NÃO é divergente', format('resultado=%s', v_res));
  perform pg_temp.teste_assert_0196(v_motivo = 'sem_periodo_par',
    '2024 sem linha válida do outro lado vira sem_periodo_par (motivo de pré-condição do contrato 0186)',
    format('motivo_precondicao=%s | %s', v_motivo, v_desc));
  select count(*) into v_n from pendencia
   where caso_id = v_caso and estado <> 'resolvida' and tipo = 'divergencia_reconciliacao';
  perform pg_temp.teste_assert_0196(v_n = 0, 'e não abre pendência de divergência', format('abertas=%s', v_n));

  raise notice '--- 2. CONTROLE: DFC com coluna 2024 e divergente SEGUE divergente ---';
  v_caso := (fn_upsert_caso('0196: caixa, DFC comparativa divergente'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'CAIXA COMPARATIVO LTDA.', 'multi', '24,25', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0196/bp-c.pdf', 'BP C.pdf', true, 'HASH-0196-5', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Disponível','valor_num','4840','periodo_coluna','31/12/2024','unidade','milhar','confianca','0.97'),
    jsonb_build_object('ordem',1,'chave','Disponível','valor_num','500','periodo_coluna','31/12/2025','unidade','milhar','confianca','0.97')
  ), 'N2');
  select entidade_id, periodo_id into v_ent, v_per from documento where id = (v_r->>'documento_id')::uuid;
  v_r := fn_registrar_documento(v_caso, 'CAIXA COMPARATIVO LTDA.', 'multi', '24,25', 'FLUXO_CAIXA', 0.97,
    'nome_arquivo', 'supabase_storage', '0196/dfc-c.pdf', 'DFC C.pdf', true, 'HASH-0196-6', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Saldo final de caixa','valor_num','900','periodo_coluna','2024','unidade','milhar','confianca','0.97'),
    jsonb_build_object('ordem',1,'chave','Saldo final de caixa','valor_num','500','periodo_coluna','2025','unidade','milhar','confianca','0.97')
  ), 'N2');
  v_r := fn_reconciliar_caixa_bp_fluxo(v_caso, v_ent, v_per);
  select resultado, materialidade->>'anos_checados' into v_res, v_anos
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0196(v_res = 'divergente' and v_anos = '2',
    'DFC com coluna 2024 (900) contra Disponível 2024 (4.840): divergente de verdade, nos 2 anos',
    format('resultado=%s anos=%s', v_res, v_anos));
  select count(*) into v_n from pendencia
   where caso_id = v_caso and estado <> 'resolvida' and tipo = 'divergencia_reconciliacao';
  perform pg_temp.teste_assert_0196(v_n = 1, 'e abre a pendência de divergência', format('abertas=%s', v_n));

  raise notice '--- 3. CONTROLE: Balanço e DFC do mesmo ano, ambos sem coluna, seguem conferindo ---';
  v_caso := (fn_upsert_caso('0196: caixa, mesmo ano sem coluna'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'CAIXA MESMO ANO LTDA.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0196/bp-d.pdf', 'BP D.pdf', true, 'HASH-0196-7', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Disponível','valor_num','500','unidade','milhar','confianca','0.97')
  ), 'N2');
  select entidade_id, periodo_id into v_ent, v_per from documento where id = (v_r->>'documento_id')::uuid;
  v_r := fn_registrar_documento(v_caso, 'CAIXA MESMO ANO LTDA.', 'anual', '2025', 'FLUXO_CAIXA', 0.97,
    'nome_arquivo', 'supabase_storage', '0196/dfc-d.pdf', 'DFC D.pdf', true, 'HASH-0196-8', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Saldo final de caixa','valor_num','500','unidade','milhar','confianca','0.97')
  ), 'N2');
  v_r := fn_reconciliar_caixa_bp_fluxo(v_caso, v_ent, v_per);
  select resultado, materialidade->>'anos_checados' into v_res, v_anos
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0196(v_res = 'ok' and v_anos = '1',
    'Balanço e DFC anuais de 2025, sem coluna, conferem (500 = 500): o ano do próprio período vale',
    format('resultado=%s anos=%s', v_res, v_anos));
end $$;

-- =============================================================================
-- 4, 5. RECEITA × FATURAMENTO (3 colunas) e DRE de um ano só
-- =============================================================================
do $$
declare
  v_caso uuid; v_r jsonb; v_ent uuid; v_per uuid; v_ver_fat uuid;
  v_res text; v_desc text; v_anos text; v_soma numeric; v_nm int; v_fb jsonb;
begin
  raise notice '--- 4. faturamento: o ano vem da COLUNA (2024, 2025, Variação %%), não do rótulo ---';
  v_caso := (fn_upsert_caso('0196: faturamento com três colunas'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'FAT TRES COLUNAS LTDA.', 'multi', '24,25', 'DRE', 0.97,
    'nome_arquivo', 'supabase_storage', '0196/dre.pdf', 'DRE.pdf', true, 'HASH-0196-9', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','RECEITA OPERACIONAL BRUTA','valor_num','183480','periodo_coluna','2024','unidade','milhar','confianca','0.97'),
    jsonb_build_object('ordem',0,'chave','RECEITA OPERACIONAL BRUTA','valor_num','138400','periodo_coluna','2025','unidade','milhar','confianca','0.97')
  ), 'N2');
  select entidade_id, periodo_id into v_ent, v_per from documento where id = (v_r->>'documento_id')::uuid;
  v_r := fn_registrar_documento(v_caso, 'FAT TRES COLUNAS LTDA.', 'multi', '24,25', 'FATURAMENTO_24M', 0.97,
    'nome_arquivo', 'supabase_storage', '0196/fat.pdf', 'FAT.pdf', true, 'HASH-0196-10', 'ok');
  v_ver_fat := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver_fat, pg_temp.campos_faturamento_3_colunas(), 'N2');

  select soma, n_linhas into v_soma, v_nm from fn_somar_faturamento_ano(v_ver_fat, '2024', '24');
  perform pg_temp.teste_assert_0196(v_soma = 183480 and v_nm = 12,
    '2024 soma os 12 meses da coluna 2024 = 183.480 (sem a coluna 2025, sem Variação %, sem Ticket médio)',
    format('soma=%s meses=%s', v_soma, v_nm));
  select soma, n_linhas into v_soma, v_nm from fn_somar_faturamento_ano(v_ver_fat, '2025', '25');
  perform pg_temp.teste_assert_0196(v_soma = 138400 and v_nm = 12,
    '2025 soma os 12 meses da coluna 2025 = 138.400', format('soma=%s meses=%s', v_soma, v_nm));

  v_r := fn_reconciliar_receita_dre_vs_faturamento(v_caso, v_ent, v_per);
  select resultado, materialidade->>'anos_checados', fonte_b into v_res, v_anos, v_fb
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0196(v_res = 'ok' and v_anos = '2',
    'DRE 183.480 / 138.400 × faturamento: a receita dos DOIS anos confere (gabarito do book)',
    format('resultado=%s anos=%s fonte_b=%s', v_res, v_anos, v_fb));
  perform pg_temp.teste_assert_0196((v_fb->>'soma_faturamento')::numeric = 138400 and (v_fb->>'n_meses')::int = 12,
    'e o registro guarda a soma de 2025 (138.400, 12 meses), não 321.579,6',
    v_fb::text);

  -- CONTROLE: a tolerância Classe B segue valendo. DRE 2024 em 150.000 (18% abaixo
  -- da soma real de 183.480) é zona_cinzenta — a correção não virou "sempre ok".
  update campo_extraido ce set valor_num = 150000
    from documento_versao dv join documento d on d.id = dv.documento_id
   where d.caso_id = v_caso and d.tipo_taxonomia = 'DRE' and ce.documento_versao_id = dv.id
     and ce.periodo_coluna = '2024';
  v_r := fn_reconciliar_receita_dre_vs_faturamento(v_caso, v_ent, v_per);
  select resultado, descricao into v_res, v_desc from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0196(v_res = 'zona_cinzenta' and v_desc like '%2024: Receita Bruta 150000%',
    'CONTROLE: DRE 2024 = 150.000 contra 183.480 segue zona_cinzenta (tolerância Classe B intacta)',
    format('resultado=%s | %s', v_res, v_desc));

  raise notice '--- 5. receita: DRE de um ano só (sem coluna) não é a receita do outro ano ---';
  v_caso := (fn_upsert_caso('0196: DRE de um exercício só'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'DRE UM ANO LTDA.', 'anual', '2025', 'DRE', 0.97,
    'nome_arquivo', 'supabase_storage', '0196/dre-5.pdf', 'DRE 5.pdf', true, 'HASH-0196-11', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','RECEITA OPERACIONAL BRUTA','valor_num','138400','unidade','milhar','confianca','0.97')
  ), 'N2');
  select entidade_id into v_ent from documento where id = (v_r->>'documento_id')::uuid;
  v_r := fn_registrar_documento(v_caso, 'DRE UM ANO LTDA.', 'multi', '24,25', 'FATURAMENTO_24M', 0.97,
    'nome_arquivo', 'supabase_storage', '0196/fat-5.pdf', 'FAT 5.pdf', true, 'HASH-0196-12', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, pg_temp.campos_faturamento_3_colunas(), 'N2');
  select periodo_id into v_per from documento where id = (v_r->>'documento_id')::uuid;
  v_r := fn_reconciliar_receita_dre_vs_faturamento(v_caso, v_ent, v_per);
  select resultado, descricao, materialidade->>'anos_checados' into v_res, v_desc, v_anos
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0196(v_res = 'ok' and v_anos = '1',
    'DRE anual 2025 (138.400) × faturamento 24M: 2025 confere e 2024 NÃO é comparado com a receita de 2025',
    format('resultado=%s anos=%s | %s', v_res, v_anos, v_desc));
  perform pg_temp.teste_assert_0196(v_desc like '%Não comparado%2024%',
    'e diz que 2024 não foi comparado (regra 1)', v_desc);
end $$;

-- =============================================================================
-- 6. FATURAMENTO SEM COLUNA DE ANO: percentual nunca entra na soma
-- =============================================================================
do $$
declare
  v_caso uuid; v_r jsonb; v_soma numeric; v_nm int;
begin
  raise notice '--- 6. faturamento sem coluna de ano: coluna de percentual fora da soma ---';
  v_caso := (fn_upsert_caso('0196: faturamento com coluna de percentual'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'FAT PERCENTUAL LTDA.', 'anual', '2025', 'FATURAMENTO_24M', 0.97,
    'nome_arquivo', 'supabase_storage', '0196/fat-6.pdf', 'FAT 6.pdf', true, 'HASH-0196-13', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Janeiro 2025','valor_num','1000','periodo_coluna','Vendas R$','unidade','milhar','moeda','BRL','confianca','0.97'),
    jsonb_build_object('ordem',0,'chave','Janeiro 2025','valor_num','12.5','periodo_coluna','Variação %','confianca','0.97'),
    jsonb_build_object('ordem',1,'chave','Fevereiro 2025','valor_num','2000','periodo_coluna','Vendas R$','unidade','milhar','moeda','BRL','confianca','0.97'),
    jsonb_build_object('ordem',1,'chave','Fevereiro 2025','valor_num','7.1','periodo_coluna','Variação %','confianca','0.97')
  ), 'N2');
  select soma, n_linhas into v_soma, v_nm
    from fn_somar_faturamento_ano((v_r->>'documento_versao_id')::uuid, '2025', '25');
  perform pg_temp.teste_assert_0196(v_soma = 3000 and v_nm = 2,
    'Vendas R$ 1.000 + 2.000 com coluna Variação % ao lado: soma 3.000 (2 meses), sem os 19,6 de percentual',
    format('soma=%s meses=%s', v_soma, v_nm));
end $$;

-- =============================================================================
-- 7. DESPESA FINANCEIRA: DRE de um ano só contra o Mapa de Dívida de outro
-- =============================================================================
do $$
declare
  v_caso uuid; v_r jsonb; v_ent uuid; v_per uuid;
  v_res text; v_motivo text; v_desc text;
begin
  raise notice '--- 7. despesa financeira: DRE anual 2025 (sem coluna) × Mapa de 31/12/2024 ---';
  v_caso := (fn_upsert_caso('0196: despfin, DRE de um exercício só'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'DESPFIN UM ANO LTDA.', 'anual', '2025', 'DRE', 0.97,
    'nome_arquivo', 'supabase_storage', '0196/dre-7.pdf', 'DRE 7.pdf', true, 'HASH-0196-14', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Despesa Financeira','valor_num','-9000','unidade','milhar','confianca','0.97')
  ), 'N2');
  select entidade_id into v_ent from documento where id = (v_r->>'documento_id')::uuid;
  v_r := fn_registrar_documento(v_caso, 'DESPFIN UM ANO LTDA.', 'data-base', '2024-12-31', 'MAPA_DIVIDA', 0.97,
    'nome_arquivo', 'supabase_storage', '0196/mapa-7.pdf', 'MAPA 7.pdf', true, 'HASH-0196-15', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Juros do contrato A','valor_num','1000','unidade','milhar','confianca','0.97')
  ), 'N2');
  v_per := fn_upsert_periodo(v_caso, 'multi', '24,25');
  v_r := fn_reconciliar_despfin_dre_vs_divida(v_caso, v_ent, v_per);
  select resultado, motivo_precondicao, descricao into v_res, v_motivo, v_desc
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0196(v_res <> 'zona_cinzenta',
    'DRE de 2025 (9.000) não é comparada com os juros do mapa de 2024 (1.000): não é zona_cinzenta',
    format('resultado=%s | %s', v_res, v_desc));
  perform pg_temp.teste_assert_0196(v_motivo = 'sem_periodo_par',
    'os dois anos ficam sem par (2024 sem DRE própria; 2025 sem mapa próprio): sem_periodo_par',
    format('motivo_precondicao=%s', v_motivo));
end $$;

-- =============================================================================
do $$
declare
  v_n int;
begin
  select case when is_called then last_value else 0 end into v_n from pg_temp._falhas_0196;
  if v_n > 0 then
    raise exception 'FALHOU: % assert(s) da 0196 reprovaram — ver as linhas FALHOU acima', v_n;
  end if;
  raise notice 'TODOS OS TESTES DA 0196 (caixa/receita/despfin por ano; faturamento por coluna) PASSARAM';
end $$;

rollback;
