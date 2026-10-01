-- Testes da 0197 (Supabase/migrations/0197_o_faturamento_que_nao_via_o_mes_na_coluna.sql).
-- Rodar via Supabase/test/run.sh.
--
-- OS ARRANJOS SÃO OS REAIS, MEDIDOS EM PRODUÇÃO (30/09/2026, somente leitura) — regra 4:
--
--   A. "teste v29", v27, v28, v40: chave "Faturamento", colunas "jan/2024", "jan/2025"… (o mês
--      na COLUNA), mais TOTAL DO EXERCÍCIO / Média mensal / Ticket médio SEM periodo_coluna.
--   B. "Teste v4x - Canastra": chave "Faturamento (R$)", colunas "Janeiro/2023"…
--   C. "Teste v35", v33, v39 custo: rótulo "Faturamento Janeiro", coluna-INTERVALO
--      "jan/2024 — jan/2025" com UMA célula por mês. Aqui NÃO há como saber de que ano é o
--      valor (a extração perdeu uma das pontas): o comportamento honesto é 0 meses.
--   D. "teste v24": meses como em C e "Ticket Médio por Pedido 2024" com coluna "2024" — em
--      produção a função vigente (0167) somava 38,2 (o ticket) como se fosse faturamento.
--   E. Ticket médio por RÓTULO num documento sem coluna de ano: não existe em produção (o que
--      mais se parece é o D); fixture mínimo do modo por rótulo, dito aqui por honestidade.
--
-- O QUE ESTE ARQUIVO TRAVA, em COMPORTAMENTO (regra 3):
--   1. Mês na coluna: 2024 soma 183.480 em 12 meses, 2025 soma 138.400 em 12 meses, sem as
--      linhas de TOTAL/Média/Ticket; e a receita de cada ano confere com a DRE.
--   2. Mês na coluna com rótulo "Faturamento (R$)" e meses de outro ano: só o ano pedido
--      soma; ano sem mês continua 0 e a receita diz que NÃO COMPAROU (o motivo segue verdadeiro).
--   3. Coluna-intervalo de dois anos: não é atribuída a ano nenhum (0 meses).
--   4. "Ticket médio" não entra na soma, nem pela coluna de ano (D) nem pelo rótulo (E).
--   5. CONTROLE: rótulo legítimo com "remédios" (contém "medio") continua somando.
--
-- NÃO PARA NO PRIMEIRO ERRO: anota e segue, e o bloco final reprova com a CONTAGEM (regra 2).

begin;

create temp sequence _falhas_0197;

create or replace function pg_temp.teste_assert_0197(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  else
    raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
    perform nextval('pg_temp._falhas_0197');
  end if;
end $$;

-- Arranjo A, como produção tem: UMA linha de campo_extraido por célula, valores do book.
create or replace function pg_temp.campos_mes_na_coluna() returns jsonb
language plpgsql as $$
declare
  meses text[] := array['jan','fev','mar','abr','mai','jun','jul','ago','set','out','nov','dez'];
  v24 numeric[] := array[15493,15948,16404,16100,16708,15796,15189,15644,14885,14429,13974,12910];
  v25 numeric[] := array[14452,13718,14085,12860,12493,12003,11268,10778,10533,9798,8818,7594];
  r jsonb := '[]'::jsonb;
  i int;
begin
  for i in 1..12 loop
    r := r || jsonb_build_array(
      jsonb_build_object('ordem',2*i-2,'chave','Faturamento','periodo_coluna',meses[i]||'/2024','valor_num',v24[i]::text,'unidade','milhar','moeda','BRL','confianca','0.97'),
      jsonb_build_object('ordem',2*i-1,'chave','Faturamento','periodo_coluna',meses[i]||'/2025','valor_num',v25[i]::text,'unidade','milhar','moeda','BRL','confianca','0.97'));
  end loop;
  r := r || jsonb_build_array(
    jsonb_build_object('ordem',24,'chave','TOTAL DO EXERCÍCIO 2024','valor_num','183480','unidade','milhar','moeda','BRL','confianca','0.97'),
    jsonb_build_object('ordem',25,'chave','TOTAL DO EXERCÍCIO 2025','valor_num','138400','unidade','milhar','moeda','BRL','confianca','0.97'),
    jsonb_build_object('ordem',26,'chave','Média mensal 2024','valor_num','15290','unidade','milhar','moeda','BRL','confianca','0.97'),
    jsonb_build_object('ordem',27,'chave','Média mensal 2025','valor_num','11533','unidade','milhar','moeda','BRL','confianca','0.97'),
    jsonb_build_object('ordem',28,'chave','Ticket médio por pedido 2024','valor_num','38.2','unidade','milhar','moeda','BRL','confianca','0.97'),
    jsonb_build_object('ordem',29,'chave','Ticket médio por pedido 2025','valor_num','31.4','unidade','milhar','moeda','BRL','confianca','0.97'));
  return r;
end $$;

do $$
declare
  v_caso uuid; v_r jsonb; v_ent uuid; v_per uuid; v_ver uuid;
  v_soma numeric; v_n int; v_res text; v_desc text; v_anos text; v_fb jsonb;
begin
  raise notice '--- 1. mês na COLUNA (chave "Faturamento", colunas jan/2024…): soma os meses do ano ---';
  v_caso := (fn_upsert_caso('0197: faturamento com o mês na coluna'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'MES NA COLUNA LTDA.', 'multi', '24,25', 'DRE', 0.97,
    'nome_arquivo', 'supabase_storage', '0197/dre.pdf', 'DRE.pdf', true, 'HASH-0197-1', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','RECEITA OPERACIONAL BRUTA','valor_num','183480','periodo_coluna','2024','unidade','milhar','confianca','0.97'),
    jsonb_build_object('ordem',0,'chave','RECEITA OPERACIONAL BRUTA','valor_num','138400','periodo_coluna','2025','unidade','milhar','confianca','0.97')
  ), 'N2');
  select entidade_id, periodo_id into v_ent, v_per from documento where id = (v_r->>'documento_id')::uuid;
  v_r := fn_registrar_documento(v_caso, 'MES NA COLUNA LTDA.', 'multi', '24,25', 'FATURAMENTO_24M', 0.97,
    'nome_arquivo', 'supabase_storage', '0197/fat.pdf', 'FAT.pdf', true, 'HASH-0197-2', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, pg_temp.campos_mes_na_coluna(), 'N2');

  select soma, n_linhas into v_soma, v_n from fn_somar_faturamento_ano(v_ver, '2024', '24');
  perform pg_temp.teste_assert_0197(v_soma = 183480 and v_n = 12,
    '2024 soma os 12 meses = 183.480, contados como 12 MESES (não 1 linha "Faturamento")',
    format('soma=%s meses=%s (esperado 183480 / 12)', v_soma, v_n));
  select soma, n_linhas into v_soma, v_n from fn_somar_faturamento_ano(v_ver, '2025', '25');
  perform pg_temp.teste_assert_0197(v_soma = 138400 and v_n = 12,
    '2025 soma os 12 meses = 138.400, sem TOTAL/Média/Ticket',
    format('soma=%s meses=%s (esperado 138400 / 12)', v_soma, v_n));

  v_r := fn_reconciliar_receita_dre_vs_faturamento(v_caso, v_ent, v_per);
  select resultado, materialidade->>'anos_checados', fonte_b, descricao into v_res, v_anos, v_fb, v_desc
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0197(v_res = 'ok' and v_anos = '2',
    'a receita dos DOIS anos é conferida contra o faturamento e confere (gabarito do book)',
    format('resultado=%s anos=%s | %s', v_res, v_anos, v_desc));
  perform pg_temp.teste_assert_0197(coalesce(v_desc, '') not like '%não traz linha mensal%',
    'e nenhum motivo diz que o Faturamento "não traz linha mensal" (os meses estão lá)', v_desc);

  raise notice '--- 2. rótulo "Faturamento (R$)", colunas "Janeiro/2023": só o ano pedido soma ---';
  v_caso := (fn_upsert_caso('0197: faturamento Canastra, meses de um ano só'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'MES CANASTRA LTDA.', 'multi', '23,24', 'DRE', 0.97,
    'nome_arquivo', 'supabase_storage', '0197/dre-2.pdf', 'DRE 2.pdf', true, 'HASH-0197-3', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','RECEITA OPERACIONAL BRUTA','valor_num','70278000','periodo_coluna','2023','unidade','unidade','confianca','0.97'),
    jsonb_build_object('ordem',0,'chave','RECEITA OPERACIONAL BRUTA','valor_num','80000000','periodo_coluna','2024','unidade','unidade','confianca','0.97')
  ), 'N2');
  select entidade_id, periodo_id into v_ent, v_per from documento where id = (v_r->>'documento_id')::uuid;
  v_r := fn_registrar_documento(v_caso, 'MES CANASTRA LTDA.', 'multi', '23,24', 'FATURAMENTO_24M', 0.97,
    'nome_arquivo', 'supabase_storage', '0197/fat-2.pdf', 'FAT 2.pdf', true, 'HASH-0197-4', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Faturamento (R$)','periodo_coluna','Janeiro/2023','valor_num','22578000','unidade','unidade','confianca','0.97'),
    jsonb_build_object('ordem',1,'chave','Faturamento (R$)','periodo_coluna','Fevereiro/2023','valor_num','21624000','unidade','unidade','confianca','0.97'),
    jsonb_build_object('ordem',2,'chave','Faturamento (R$)','periodo_coluna','Março/2023','valor_num','26076000','unidade','unidade','confianca','0.97')
  ), 'N2');
  select soma, n_linhas into v_soma, v_n from fn_somar_faturamento_ano(v_ver, '2023', '23');
  perform pg_temp.teste_assert_0197(v_soma = 70278000 and v_n = 3,
    '2023 soma os 3 meses da coluna "Mês/2023" = 70.278.000',
    format('soma=%s meses=%s', v_soma, v_n));
  select soma, n_linhas into v_soma, v_n from fn_somar_faturamento_ano(v_ver, '2024', '24');
  perform pg_temp.teste_assert_0197(v_soma = 0 and v_n = 0,
    '2024 não tem mês nenhum: 0 meses (ausência, não soma de outro ano)',
    format('soma=%s meses=%s', v_soma, v_n));
  v_r := fn_reconciliar_receita_dre_vs_faturamento(v_caso, v_ent, v_per);
  select resultado, descricao into v_res, v_desc from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0197(v_desc like '%Não comparado%2024%não traz linha mensal%',
    'e a receita de 2024 diz que NÃO comparou, com o motivo verdadeiro (o Faturamento não traz linha mensal de 2024)',
    format('resultado=%s | %s', v_res, v_desc));
  perform pg_temp.teste_assert_0197(v_res = 'ok' and v_desc like '%2023: confere%',
    'enquanto 2023 é conferido normalmente (70.278.000 = 70.278.000)',
    format('resultado=%s | %s', v_res, v_desc));
end $$;

do $$
declare
  v_caso uuid; v_r jsonb; v_ver uuid; v_soma numeric; v_n int;
begin
  raise notice '--- 3. coluna-INTERVALO "jan/2024 — jan/2025" (uma célula): não é atribuída a ano ---';
  v_caso := (fn_upsert_caso('0197: faturamento com coluna-intervalo'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'INTERVALO LTDA.', 'multi', '24,25', 'FATURAMENTO_24M', 0.97,
    'nome_arquivo', 'supabase_storage', '0197/fat-3.pdf', 'FAT 3.pdf', true, 'HASH-0197-5', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Faturamento Janeiro','periodo_coluna','jan/2024 — jan/2025','valor_num','15493','unidade','milhar','confianca','0.97'),
    jsonb_build_object('ordem',1,'chave','Faturamento Fevereiro','periodo_coluna','fev/2024 — fev/2025','valor_num','15948','unidade','milhar','confianca','0.97'),
    jsonb_build_object('ordem',2,'chave','Faturamento Março','periodo_coluna','mar/2024 — mar/2025','valor_num','16404','unidade','milhar','confianca','0.97')
  ), 'N2');
  select soma, n_linhas into v_soma, v_n from fn_somar_faturamento_ano(v_ver, '2024', '24');
  perform pg_temp.teste_assert_0197(v_soma = 0 and v_n = 0,
    '2024: a célula do intervalo não é dito ser de 2024 (a extração não diz de qual ano é o valor)',
    format('soma=%s meses=%s', v_soma, v_n));
  select soma, n_linhas into v_soma, v_n from fn_somar_faturamento_ano(v_ver, '2025', '25');
  perform pg_temp.teste_assert_0197(v_soma = 0 and v_n = 0,
    '2025: idem — a mesma célula não vira faturamento dos dois anos',
    format('soma=%s meses=%s', v_soma, v_n));

  raise notice '--- 4. "Ticket médio" não é faturamento (D: coluna de ano; E: rótulo) ---';
  v_caso := (fn_upsert_caso('0197: ticket médio fora da soma'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'TICKET COLUNA LTDA.', 'multi', '24,25', 'FATURAMENTO_24M', 0.97,
    'nome_arquivo', 'supabase_storage', '0197/fat-4.pdf', 'FAT 4.pdf', true, 'HASH-0197-6', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Faturamento Janeiro','periodo_coluna','jan/2024 — jan/2025','valor_num','15493','unidade','milhar','confianca','0.97'),
    jsonb_build_object('ordem',1,'chave','Total do Exercício 2024','periodo_coluna','2024','valor_num','183480','unidade','milhar','confianca','0.97'),
    jsonb_build_object('ordem',2,'chave','Média Mensal 2024','periodo_coluna','2024','valor_num','15290','unidade','milhar','confianca','0.97'),
    jsonb_build_object('ordem',3,'chave','Ticket Médio por Pedido 2024','periodo_coluna','2024','valor_num','38.2','unidade','milhar','confianca','0.97')
  ), 'N2');
  select soma, n_linhas into v_soma, v_n from fn_somar_faturamento_ano(v_ver, '2024', '24');
  perform pg_temp.teste_assert_0197(v_soma = 0 and v_n = 0,
    'D: com coluna de ano, "Ticket Médio por Pedido 2024" (38,2) NÃO entra como faturamento de 2024',
    format('soma=%s meses=%s (o ticket daria 38.2 / 1)', v_soma, v_n));

  v_r := fn_registrar_documento(v_caso, 'TICKET ROTULO LTDA.', 'anual', '2024', 'FATURAMENTO_24M', 0.97,
    'nome_arquivo', 'supabase_storage', '0197/fat-5.pdf', 'FAT 5.pdf', true, 'HASH-0197-7', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Faturamento Janeiro 2024','valor_num','1000','unidade','unidade','confianca','0.97'),
    jsonb_build_object('ordem',1,'chave','Ticket médio por pedido 2024','valor_num','38.2','unidade','unidade','confianca','0.97'),
    jsonb_build_object('ordem',2,'chave','Média mensal 2024','valor_num','500','unidade','unidade','confianca','0.97')
  ), 'N2');
  select soma, n_linhas into v_soma, v_n from fn_somar_faturamento_ano(v_ver, '2024', '24');
  perform pg_temp.teste_assert_0197(v_soma = 1000 and v_n = 1,
    'E: por rótulo, o ticket médio e a média ficam fora: soma só o mês (1.000, 1 mês)',
    format('soma=%s meses=%s (com o ticket: 1038.2 / 2)', v_soma, v_n));

  raise notice '--- 5. CONTROLE: rótulo legítimo que contém "medio" como parte de outra palavra ---';
  v_r := fn_registrar_documento(v_caso, 'REMEDIOS LTDA.', 'anual', '2024', 'FATURAMENTO_24M', 0.97,
    'nome_arquivo', 'supabase_storage', '0197/fat-6.pdf', 'FAT 6.pdf', true, 'HASH-0197-8', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Venda de remédios jan/2024','valor_num','500','unidade','unidade','confianca','0.97')
  ), 'N2');
  select soma, n_linhas into v_soma, v_n from fn_somar_faturamento_ano(v_ver, '2024', '24');
  perform pg_temp.teste_assert_0197(v_soma = 500 and v_n = 1,
    'CONTROLE: "Venda de remédios jan/2024" segue somando (o filtro de média é por palavra)',
    format('soma=%s meses=%s', v_soma, v_n));
end $$;

do $$
declare
  v_n int;
begin
  select case when is_called then last_value else 0 end into v_n from pg_temp._falhas_0197;
  if v_n > 0 then
    raise exception 'FALHOU: % assert(s) da 0197 reprovaram — ver as linhas FALHOU acima', v_n;
  end if;
  raise notice 'TODOS OS TESTES DA 0197 (faturamento com o mês na coluna; ticket médio fora) PASSARAM';
end $$;

rollback;
