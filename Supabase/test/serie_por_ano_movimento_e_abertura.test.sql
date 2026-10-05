-- Testes da 0199 (Supabase/migrations/0199_a_serie_por_ano_que_lia_movimento_e_abertura_como_saldo.sql).
-- Rodar via Supabase/test/run.sh.
--
-- O ARRANJO É O REAL, MEDIDO EM PRODUÇÃO (05/10/2026, só-leitura, caso "Fw Valtra" 03a66ab6, empresa
-- MOTO AGRICOLA VOLKWEIS LTDA). Os números ENTRE ASPAS NO COMENTÁRIO "real" são os de produção;
-- os marcados "arranjo" foram escolhidos aqui porque o valor de produção não foi anotado — afirmam
-- só a ORDEM entre números (o que vence), nunca o número como se fosse do cliente (regra 4):
--
--   • BALANCO ref "2025", colunas `Saldo Inicial` / `Saldo Final`. Real: CLIENTES Final 4.292.868,90,
--     Inicial 5.218.337,81; ATIVO Final 38.483.404,04; ATIVO CIRCULANTE Final 33.056.432,15.
--   • DRE ref "2023" e "2024", colunas `Saldo anterior` / `Saldo atual`. Real: ref 2023 "VENDA DE
--     IMPLEMENTOS NOVOS" anterior 10.162.581,81 (= 2022) e atual 9.673.146,21; ref 2024 "VENDA DE
--     TRATORES VALTRA NOVOS" anterior 21.114.784,03 (= 2023) e atual 19.374.000.
--   • BALANCETE ref "01/01/2025 - 30/06/2025" (período `outro`), colunas `Saldo Anterior` / `Débito` /
--     `Crédito` / `Saldo Atual`. Real: ATIVO Débito 125.859.727,84; ATIVO CIRCULANTE Débito
--     125.484.949,09. Arranjo: o Saldo Atual de 30/06 do ATIVO (41.000.000) e do CLIENTES (6.000.000)
--     MAIORES que o fechamento anual, que é o que faz a regra (c) ser medida sozinha, sem a ajuda de
--     a (o Débito já é maior que tudo).
--   • CONTRATO_SOCIAL com `patrimonio_liquido`: "total - nº de quotas" 15.500.000, "total - %" 100,
--     "total - capital social" 15.500.000.
--
-- O QUE TRAVA, em COMPORTAMENTO (regra 3):
--   1. Movimento (Débito/Crédito) nunca é saldo: ATIVO e ATIVO CIRCULANTE de 2025 são os do BALANCO.
--   2. Abertura pertence ao ano anterior: CLIENTES 2025 = Saldo Final; "Saldo anterior" da DRE de
--      2023 aparece em 2022 e a DRE de 2024 dá o 2023 dos tratores.
--   3. Fechamento vence abertura do mesmo (rótulo, ano), mesmo quando a abertura é maior em módulo.
--   4. Período anual vence o parcial (30/06 não ganha do 31/12), e o parcial ENTRA quando é a única
--      fonte (decisão declarada na 0199).
--   5. CONTRATO_SOCIAL não entra na série.
--   6. Desempate determinístico em empate de módulo com sinais opostos.
--   7. Controle: a proveniência continua sendo a da célula, e `n_ocorrencias` conta as elegíveis.
--
-- NÃO PARA NO PRIMEIRO ERRO: anota e segue, e o bloco final reprova com a CONTAGEM (regra 2).
--
-- MEDIÇÃO (regra 2): com o corpo da 0125 de volta, 19 dos 21 asserts reprovam; os 2 verdes são controles.
-- Sem a chave de fechamento-antes-de-abertura reprova 1; sem a de anual-antes-de-parcial, 5.

begin;

create temp sequence _falhas_0199;

create or replace function pg_temp.teste_assert_0199(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  else
    raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
    perform nextval('pg_temp._falhas_0199');
  end if;
end $$;

-- O valor de uma célula da série, ou NULL quando a linha não existe naquele ano.
create or replace function pg_temp.v0199(p_caso uuid, p_rotulo text, p_ano int) returns numeric
language sql as $$
  select valor from fn_valores_por_ano(p_caso, 'MOTO AGRICOLA VOLKWEIS LTDA')
   where rotulo_norm = fn_normalizar_texto(p_rotulo) and ano = p_ano
$$;

do $$
declare
  v_caso uuid; v_r jsonb; v_n int; v_txt text; v_num numeric;
  c constant text := 'MOTO AGRICOLA VOLKWEIS LTDA';
begin
  v_caso := (fn_upsert_caso('0199: Fw Valtra, série por ano'))::uuid;

  -- BALANCO 2025: Saldo Inicial (= fechamento de 2024) e Saldo Final.
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0199/bp2025.pdf', 'balanco_2025.pdf', true, 'HASH-0199-1', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','ATIVO','secao_canonica','ativo_total','periodo_coluna','Saldo Inicial','valor_num','40100000.00','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',0,'chave','ATIVO','secao_canonica','ativo_total','periodo_coluna','Saldo Final','valor_num','38483404.04','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',1,'chave','ATIVO CIRCULANTE','secao_canonica','ativo_circulante','periodo_coluna','Saldo Inicial','valor_num','34000000.00','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',1,'chave','ATIVO CIRCULANTE','secao_canonica','ativo_circulante','periodo_coluna','Saldo Final','valor_num','33056432.15','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',2,'chave','CLIENTES','secao_canonica','ativo_circulante','periodo_coluna','Saldo Inicial','valor_num','5218337.81','confianca','0.97','origem_pagina','2'),
    jsonb_build_object('ordem',2,'chave','CLIENTES','secao_canonica','ativo_circulante','periodo_coluna','Saldo Final','valor_num','4292868.90','confianca','0.97','origem_pagina','2'),
    -- arranjo: abertura MAIOR em módulo que o fechamento de 2025 e que o de 2024 reapresentado
    jsonb_build_object('ordem',3,'chave','ESTOQUES','secao_canonica','ativo_circulante','periodo_coluna','Saldo Inicial','valor_num','9000000.00','confianca','0.97','origem_pagina','2'),
    jsonb_build_object('ordem',3,'chave','ESTOQUES','secao_canonica','ativo_circulante','periodo_coluna','Saldo Final','valor_num','7500000.00','confianca','0.97','origem_pagina','2'),
    -- arranjo: empate de módulo com sinais opostos, mesma coluna, mesmo documento
    jsonb_build_object('ordem',4,'chave','AJUSTE DE AVALIACAO','secao_canonica','patrimonio_liquido','periodo_coluna','Saldo Final','valor_num','-1900','confianca','0.97','origem_pagina','3'),
    jsonb_build_object('ordem',5,'chave','AJUSTE DE AVALIACAO','secao_canonica','patrimonio_liquido','periodo_coluna','Saldo Final','valor_num','1900','confianca','0.97','origem_pagina','3')
  ), 'N2');

  -- BALANCO 2024 (arranjo): reapresenta ESTOQUES de 2024 em 8.000.000, que difere da abertura de 2025.
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2024', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0199/bp2024.pdf', 'balanco_2024.pdf', true, 'HASH-0199-2', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','ESTOQUES','secao_canonica','ativo_circulante','periodo_coluna','Saldo Final','valor_num','8000000.00','confianca','0.97','origem_pagina','2')
  ), 'N2');

  -- DRE 2023 e 2024: Saldo anterior (= exercício anterior) e Saldo atual.
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2023', 'DRE', 0.97,
    'nome_arquivo', 'supabase_storage', '0199/dre2023.pdf', 'dre_2023.pdf', true, 'HASH-0199-3', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','VENDA DE IMPLEMENTOS NOVOS','secao_canonica','receita_bruta','periodo_coluna','Saldo anterior','valor_num','10162581.81','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',0,'chave','VENDA DE IMPLEMENTOS NOVOS','secao_canonica','receita_bruta','periodo_coluna','Saldo atual','valor_num','9673146.21','confianca','0.97','origem_pagina','1')
  ), 'N2');
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2024', 'DRE', 0.97,
    'nome_arquivo', 'supabase_storage', '0199/dre2024.pdf', 'dre_2024.pdf', true, 'HASH-0199-4', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','VENDA DE TRATORES VALTRA NOVOS','secao_canonica','receita_bruta','periodo_coluna','Saldo anterior','valor_num','21114784.03','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',0,'chave','VENDA DE TRATORES VALTRA NOVOS','secao_canonica','receita_bruta','periodo_coluna','Saldo atual','valor_num','19374000','confianca','0.97','origem_pagina','1')
  ), 'N2');

  -- BALANCETE semestral: Saldo Anterior / Débito / Crédito / Saldo Atual.
  v_r := fn_registrar_documento(v_caso, c, 'outro', '01/01/2025 - 30/06/2025', 'BALANCETE', 0.97,
    'nome_arquivo', 'supabase_storage', '0199/balancete.pdf', 'balancete_1s2025.pdf', true, 'HASH-0199-5', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','ATIVO','secao_canonica','ativo_total','periodo_coluna','Saldo Anterior','valor_num','40100000.00','confianca','0.99','origem_pagina','1'),
    jsonb_build_object('ordem',0,'chave','ATIVO','secao_canonica','ativo_total','periodo_coluna','Débito','valor_num','125859727.84','confianca','0.99','origem_pagina','1'),
    jsonb_build_object('ordem',0,'chave','ATIVO','secao_canonica','ativo_total','periodo_coluna','Crédito','valor_num','120000000.00','confianca','0.99','origem_pagina','1'),
    jsonb_build_object('ordem',0,'chave','ATIVO','secao_canonica','ativo_total','periodo_coluna','Saldo Atual','valor_num','41000000.00','confianca','0.99','origem_pagina','1'),
    jsonb_build_object('ordem',1,'chave','ATIVO CIRCULANTE','secao_canonica','ativo_circulante','periodo_coluna','Débito','valor_num','125484949.09','confianca','0.99','origem_pagina','1'),
    jsonb_build_object('ordem',1,'chave','ATIVO CIRCULANTE','secao_canonica','ativo_circulante','periodo_coluna','Saldo Atual','valor_num','32000000.00','confianca','0.99','origem_pagina','1'),
    jsonb_build_object('ordem',2,'chave','CLIENTES','secao_canonica','ativo_circulante','periodo_coluna','Saldo Atual','valor_num','6000000.00','confianca','0.99','origem_pagina','2'),
    -- conta que SÓ existe no balancete: o parcial entra por ser a única fonte (decisão da 0199)
    jsonb_build_object('ordem',3,'chave','CAIXA GERAL','secao_canonica','ativo_circulante','periodo_coluna','Saldo Anterior','valor_num','1000000.00','confianca','0.99','origem_pagina','3'),
    jsonb_build_object('ordem',3,'chave','CAIXA GERAL','secao_canonica','ativo_circulante','periodo_coluna','Débito','valor_num','9000000.00','confianca','0.99','origem_pagina','3'),
    jsonb_build_object('ordem',3,'chave','CAIXA GERAL','secao_canonica','ativo_circulante','periodo_coluna','Crédito','valor_num','8800000.00','confianca','0.99','origem_pagina','3'),
    jsonb_build_object('ordem',3,'chave','CAIXA GERAL','secao_canonica','ativo_circulante','periodo_coluna','Saldo Atual','valor_num','1200000.00','confianca','0.99','origem_pagina','3')
  ), 'N2');

  -- CONTRATO_SOCIAL: quotas, percentual e capital social "no PL".
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2025', 'CONTRATO_SOCIAL', 0.97,
    'nome_arquivo', 'supabase_storage', '0199/contrato.pdf', 'contrato_social.pdf', true, 'HASH-0199-6', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','total - nº de quotas','secao_canonica','patrimonio_liquido','valor_num','15500000','confianca','0.97','origem_pagina','2'),
    jsonb_build_object('ordem',1,'chave','total - %','secao_canonica','patrimonio_liquido','valor_num','100','confianca','0.97','origem_pagina','2'),
    jsonb_build_object('ordem',2,'chave','total - capital social','secao_canonica','patrimonio_liquido','valor_num','15500000','confianca','0.97','origem_pagina','2')
  ), 'N2');

  raise notice '--- 1. movimento (Débito/Crédito) nunca é saldo ---';
  v_num := pg_temp.v0199(v_caso, 'ATIVO', 2025);
  perform pg_temp.teste_assert_0199(v_num = 38483404.04,
    'ATIVO 2025 = o do BALANCO anual (38.483.404,04), não o Débito do balancete (125.859.727,84)', format('%s', v_num));
  v_num := pg_temp.v0199(v_caso, 'ATIVO CIRCULANTE', 2025);
  perform pg_temp.teste_assert_0199(v_num = 33056432.15,
    'ATIVO CIRCULANTE 2025 = 33.056.432,15, não o Débito (125.484.949,09)', format('%s', v_num));
  select count(*) into v_n from fn_valores_por_ano(v_caso, c) where valor in (125859727.84, 125484949.09, 120000000.00, 9000000.00, 8800000.00) and rotulo_norm <> 'estoques';
  perform pg_temp.teste_assert_0199(v_n = 0,
    'nenhum valor de coluna Débito/Crédito aparece na série, em ano nenhum', format('%s célula(s)', v_n));

  raise notice '--- 2. abertura pertence ao ANO ANTERIOR ---';
  v_num := pg_temp.v0199(v_caso, 'CLIENTES', 2025);
  perform pg_temp.teste_assert_0199(v_num = 4292868.90,
    'CLIENTES 2025 = Saldo Final (4.292.868,90), não o Saldo Inicial (5.218.337,81, que é o de 2024)', format('%s', v_num));
  v_num := pg_temp.v0199(v_caso, 'CLIENTES', 2024);
  perform pg_temp.teste_assert_0199(v_num = 5218337.81,
    'e o Saldo Inicial aparece onde mora: CLIENTES 2024 = 5.218.337,81 (única fonte de 2024)', format('%s', v_num));
  v_num := pg_temp.v0199(v_caso, 'VENDA DE IMPLEMENTOS NOVOS', 2023);
  perform pg_temp.teste_assert_0199(v_num = 9673146.21,
    'DRE 2023: VENDA DE IMPLEMENTOS NOVOS 2023 = Saldo atual (9.673.146,21), não o Saldo anterior', format('%s', v_num));
  v_num := pg_temp.v0199(v_caso, 'VENDA DE IMPLEMENTOS NOVOS', 2022);
  perform pg_temp.teste_assert_0199(v_num = 10162581.81,
    'e o Saldo anterior da DRE 2023 é o exercício de 2022 (10.162.581,81)', format('%s', v_num));
  v_num := pg_temp.v0199(v_caso, 'VENDA DE TRATORES VALTRA NOVOS', 2024);
  perform pg_temp.teste_assert_0199(v_num = 19374000,
    'DRE 2024: TRATORES 2024 = Saldo atual (19.374.000), não o Saldo anterior (21.114.784,03)', format('%s', v_num));
  v_num := pg_temp.v0199(v_caso, 'VENDA DE TRATORES VALTRA NOVOS', 2023);
  perform pg_temp.teste_assert_0199(v_num = 21114784.03,
    'e o Saldo anterior da DRE 2024 é o 2023 dos tratores (21.114.784,03)', format('%s', v_num));

  raise notice '--- 3. fechamento vence abertura do mesmo (rótulo, seção, ano) ---';
  v_num := pg_temp.v0199(v_caso, 'ESTOQUES', 2024);
  perform pg_temp.teste_assert_0199(v_num = 8000000,
    'ESTOQUES 2024 = 8.000.000 (Saldo Final do BALANCO 2024), não 9.000.000 (a abertura de 2025, maior em módulo)', format('%s', v_num));
  v_num := pg_temp.v0199(v_caso, 'ESTOQUES', 2025);
  perform pg_temp.teste_assert_0199(v_num = 7500000,
    'ESTOQUES 2025 = Saldo Final (7.500.000), não a abertura (9.000.000)', format('%s', v_num));

  raise notice '--- 4. período anual vence o parcial; parcial entra quando é a única fonte ---';
  select arquivo into v_txt from fn_valores_por_ano(v_caso, c) where rotulo_norm = fn_normalizar_texto('ATIVO') and ano = 2025;
  perform pg_temp.teste_assert_0199(v_txt = 'balanco_2025.pdf',
    'ATIVO 2025 vem do BALANCO anual mesmo com o Saldo Atual de 30/06 (41.000.000) maior em módulo', coalesce(v_txt, '(nulo)'));
  v_num := pg_temp.v0199(v_caso, 'CLIENTES', 2025);
  perform pg_temp.teste_assert_0199(v_num <> 6000000,
    'CLIENTES 2025 não é o Saldo Atual de 30/06 do balancete (6.000.000)', format('%s', v_num));
  select arquivo into v_txt from fn_valores_por_ano(v_caso, c) where rotulo_norm = fn_normalizar_texto('ATIVO') and ano = 2024;
  perform pg_temp.teste_assert_0199(v_txt = 'balanco_2025.pdf',
    'ATIVO 2024 (abertura): a do BALANCO anual vence a do balancete, a mesma 40.100.000 em duas fontes', coalesce(v_txt, '(nulo)'));
  v_num := pg_temp.v0199(v_caso, 'CAIXA GERAL', 2025);
  perform pg_temp.teste_assert_0199(v_num = 1200000,
    'conta SÓ do balancete: 2025 = o Saldo Atual (1.200.000) — o parcial entra por ser a única fonte, mas sem o Débito (9.000.000)', format('%s', v_num));
  v_num := pg_temp.v0199(v_caso, 'CAIXA GERAL', 2024);
  perform pg_temp.teste_assert_0199(v_num = 1000000,
    'e o Saldo Anterior do balancete é o 2024 dela (1.000.000)', format('%s', v_num));

  raise notice '--- 5. CONTRATO_SOCIAL não entra na série ---';
  select count(*) into v_n from fn_valores_por_ano(v_caso, c) where arquivo = 'contrato_social.pdf';
  perform pg_temp.teste_assert_0199(v_n = 0,
    'nenhuma linha do CONTRATO_SOCIAL (quotas, %, capital social) chega à série', format('%s célula(s)', v_n));
  select count(*) into v_n from fn_valores_por_ano(v_caso, c)
   where secao_canonica = 'patrimonio_liquido' and ano = 2025 and valor in (15500000, 100);
  perform pg_temp.teste_assert_0199(v_n = 0,
    'e o PL de 2025 não carrega 15.500.000 nem 100', format('%s célula(s)', v_n));

  raise notice '--- 6. desempate determinístico ---';
  v_num := pg_temp.v0199(v_caso, 'AJUSTE DE AVALIACAO', 2025);
  perform pg_temp.teste_assert_0199(v_num = 1900,
    'empate de módulo com sinais opostos (-1.900 / 1.900) resolve sempre para o positivo', format('%s', v_num));

  raise notice '--- 7. a proveniência segue sendo a da célula, e n_ocorrencias conta as elegíveis ---';
  select n_ocorrencias into v_n from fn_valores_por_ano(v_caso, c) where rotulo_norm = fn_normalizar_texto('ATIVO') and ano = 2025;
  perform pg_temp.teste_assert_0199(v_n = 2,
    'ATIVO 2025 tem 2 ocorrências elegíveis (Saldo Final e Saldo Atual); Débito, Crédito e as aberturas não contam', format('%s', v_n));
  select origem_pagina into v_n from fn_valores_por_ano(v_caso, c) where rotulo_norm = fn_normalizar_texto('CLIENTES') and ano = 2025;
  perform pg_temp.teste_assert_0199(v_n = 2,
    'CLIENTES 2025: a página é a da ocorrência que deu o valor (balanço p.2)', format('%s', v_n));
end $$;

do $$
declare
  v_n int;
begin
  select case when is_called then last_value else 0 end into v_n from pg_temp._falhas_0199;
  if v_n > 0 then
    raise exception 'FALHOU: % assert(s) da 0199 reprovaram — ver as linhas FALHOU acima', v_n;
  end if;
  raise notice 'TODOS OS TESTES DA 0199 (série por ano sem movimento nem abertura) PASSARAM';
end $$;

rollback;
