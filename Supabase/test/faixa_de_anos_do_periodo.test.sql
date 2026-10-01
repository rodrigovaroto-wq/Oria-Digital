-- Testes da 0198 (Supabase/migrations/0198_a_faixa_de_anos_que_perdia_o_ano_do_meio.sql).
-- Rodar via Supabase/test/run.sh.
--
-- OS FORMATOS SÃO OS REAIS DE `select distinct tipo, referencia from periodo` EM PRODUÇÃO
-- (30/09/2026, somente leitura): "multi 2024-2026" (Mapa de Dívida do Krauspenhar), "multi
-- 2024-2025", "multi 2021, 2025" e "multi 2025,2024" (listas), "multi Jan/2024 a Dez/2025",
-- "data-base 2024-12-31", "outro 01/01/2025 - 30/06/2025". A faixa "2024 a 2026" por extenso e
-- "2026-2024" NÃO existem em produção: entram como entrada de fronteira, e o teste diz qual
-- comportamento afirma (a ambígua mantém o antigo).
--
-- O QUE TRAVA, em COMPORTAMENTO (regra 3):
--   1. A FAIXA devolve todos os anos dela; a LISTA, só os listados.
--   2. Datas e intervalos de data não viram faixa de anos.
--   3. Faixa ambígua (fim antes do início) NÃO é expandida.
--   4. A despesa financeira de 2025 contra um Mapa "2024-2026" não diz que o mapa não cobre 2025.
--   5. O período "2024-2026" é compatível com o "anual 2025" do mesmo caso.
--
-- NÃO PARA NO PRIMEIRO ERRO: anota e segue, e o bloco final reprova com a CONTAGEM (regra 2).

begin;

create temp sequence _falhas_0198;

create or replace function pg_temp.teste_assert_0198(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  else
    raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
    perform nextval('pg_temp._falhas_0198');
  end if;
end $$;

do $$
begin
  raise notice '--- 1. faixa x lista ---';
  perform pg_temp.teste_assert_0198(fn_anos_periodo('multi', '2024-2026') = array[2024,2025,2026],
    'multi 2024-2026 = 2024, 2025 e 2026 (não perde o ano do meio)',
    fn_anos_periodo('multi', '2024-2026')::text);
  perform pg_temp.teste_assert_0198(fn_anos_periodo('multi', '2024-2025') = array[2024,2025],
    'multi 2024-2025 segue = 2024, 2025', fn_anos_periodo('multi', '2024-2025')::text);
  perform pg_temp.teste_assert_0198(fn_anos_periodo('multi', '2024 a 2026') = array[2024,2025,2026],
    'a faixa por extenso "2024 a 2026" (fronteira, não medida em produção) também', 
    fn_anos_periodo('multi', '2024 a 2026')::text);
  perform pg_temp.teste_assert_0198(fn_anos_periodo('multi', '2024, 2026') = array[2024,2026],
    'CONTROLE: a LISTA "2024, 2026" devolve só os listados (vírgula nunca é faixa)',
    fn_anos_periodo('multi', '2024, 2026')::text);
  perform pg_temp.teste_assert_0198(fn_anos_periodo('multi', '2025,2024') = array[2024,2025]
      and fn_anos_periodo('multi', '2021, 2025') = array[2021,2025],
    'CONTROLE: as listas reais de produção ("2025,2024", "2021, 2025") seguem como eram',
    fn_anos_periodo('multi', '2021, 2025')::text);

  raise notice '--- 2. datas não são faixa ---';
  perform pg_temp.teste_assert_0198(fn_anos_periodo('data-base', '2024-12-31') = array[2024]
      and fn_anos_periodo('outro', '01/01/2025 - 30/06/2025') = array[2025]
      and fn_anos_periodo('multi', 'Jan/2024 a Dez/2025') = array[2024,2025],
    'CONTROLE: "2024-12-31", "01/01/2025 - 30/06/2025" e "Jan/2024 a Dez/2025" seguem como eram',
    format('%s %s %s', fn_anos_periodo('data-base', '2024-12-31'),
           fn_anos_periodo('outro', '01/01/2025 - 30/06/2025'), fn_anos_periodo('multi', 'Jan/2024 a Dez/2025')));

  raise notice '--- 3. faixa ambígua mantém o comportamento antigo ---';
  perform pg_temp.teste_assert_0198(fn_anos_periodo('multi', '2026-2024') = array[2024,2026]
      and fn_anos_periodo('multi', '2000-2024') = array[2000,2024],
    'fim antes do início e faixa de mais de 10 anos NÃO são expandidas (só as pontas, como antes)',
    format('%s %s', fn_anos_periodo('multi', '2026-2024'), fn_anos_periodo('multi', '2000-2024')));
end $$;

do $$
declare
  v_caso uuid; v_r jsonb; v_ent uuid; v_per uuid; v_per_mapa uuid; v_per_2025 uuid;
  v_res text; v_desc text; v_anos text;
begin
  raise notice '--- 4. despesa financeira de 2025 contra o Mapa "multi 2024-2026" (o arranjo do Krauspenhar) ---';
  v_caso := (fn_upsert_caso('0198: Mapa de Dívida em faixa'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'FAIXA LTDA.', 'multi', '24,25,26', 'DRE', 0.97,
    'nome_arquivo', 'supabase_storage', '0198/dre.pdf', 'DRE.pdf', true, 'HASH-0198-1', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Despesa Financeira','valor_num','-1000','periodo_coluna','2024','unidade','milhar','confianca','0.97'),
    jsonb_build_object('ordem',0,'chave','Despesa Financeira','valor_num','-2000','periodo_coluna','2025','unidade','milhar','confianca','0.97'),
    jsonb_build_object('ordem',0,'chave','Despesa Financeira','valor_num','-3000','periodo_coluna','2026','unidade','milhar','confianca','0.97')
  ), 'N2');
  select entidade_id, periodo_id into v_ent, v_per from documento where id = (v_r->>'documento_id')::uuid;
  v_r := fn_registrar_documento(v_caso, 'FAIXA LTDA.', 'multi', '2024-2026', 'MAPA_DIVIDA', 0.97,
    'nome_arquivo', 'supabase_storage', '0198/mapa.pdf', 'MAPA.pdf', true, 'HASH-0198-2', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Juros do contrato A','valor_num','2000','unidade','milhar','confianca','0.97')
  ), 'N2');
  select periodo_id into v_per_mapa from documento where id = (v_r->>'documento_id')::uuid;

  v_r := fn_reconciliar_despfin_dre_vs_divida(v_caso, v_ent, v_per);
  select resultado, descricao into v_res, v_desc from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0198(coalesce(v_desc, '') not like '%2025: o Mapa de Dívida é de%',
    '2025 NÃO é dado como fora do Mapa "2024-2026" (o mapa cobre 2025)',
    format('resultado=%s | %s', v_res, v_desc));

  raise notice '--- 5. o período em faixa é compatível com o anual 2025 do mesmo caso ---';
  v_per_2025 := fn_upsert_periodo(v_caso, 'anual', '2025');
  perform pg_temp.teste_assert_0198(fn_periodos_compativeis(v_per_mapa, v_per_2025),
    'período "2024-2026" × "anual 2025": compatíveis (antes {2024,2026} ∩ {2025} era vazio)',
    format('%s x %s', fn_anos_periodo('multi','2024-2026'), fn_anos_periodo('anual','2025')));
end $$;

do $$
declare
  v_n int;
begin
  select case when is_called then last_value else 0 end into v_n from pg_temp._falhas_0198;
  if v_n > 0 then
    raise exception 'FALHOU: % assert(s) da 0198 reprovaram — ver as linhas FALHOU acima', v_n;
  end if;
  raise notice 'TODOS OS TESTES DA 0198 (faixa de anos do período) PASSARAM';
end $$;

rollback;
