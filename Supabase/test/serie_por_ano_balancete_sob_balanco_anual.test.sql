-- Testes da 0200 (Supabase/migrations/0200_o_balancete_semestral_que_entrava_por_cima_do_balanco_anual.sql).
-- Rodar via Supabase/test/run.sh.
--
-- O ARRANJO É O REAL, MEDIDO EM PRODUÇÃO (05/10/2026, só-leitura, caso "Fw Valtra" 03a66ab6, empresa
-- MOTO AGRICOLA VOLKWEIS LTDA), depois da 0199. Reais (de produção): o BALANCO anual traz contas
-- SINTÉTICAS — ATIVO CIRCULANTE 29.275.182,61 (2024) / 33.056.432,15 (2025); CLIENTES 5.218.337,81 /
-- 4.292.868,90 — e o BALANCETE 01/01–30/06/2025 traz centenas de contas ANALÍTICAS com o código no
-- rótulo ("12388 1.1.5.01.007 TRANSFERENCIA DE MERCADORIAS TRATORES"), com Saldo Anterior / Débito /
-- Crédito / Saldo Atual. Os RÓTULOS analíticos abaixo são os do formato real; os VALORES das analíticas
-- são do arranjo (os de produção não foram anotados — regra 4): o teste afirma ONDE a célula aparece
-- (em que ano), nunca o número como se fosse do cliente. O resíduo -36 mi/-46,9 mi de produção é a
-- consequência (a soma das contas passa do total) e não é reproduzido aqui: afirma-se a causa, que
-- é a contagem de contas do circulante por ano.
--
-- O QUE TRAVA, em COMPORTAMENTO (regra 3):
--   1. Ano COM balanço anual (2024 e 2025): as contas analíticas do balancete NÃO aparecem — nem o
--      Saldo Atual de 30/06/2025 em 2025, nem o Saldo Anterior (abertura) em 2024.
--   2. As contas do circulante de 2024 e 2025 são só as do balanço (sintéticas), com os valores dele.
--   3. Ano SEM balanço anual (2026, só balancete de jun/2026): as analíticas aparecem, e a abertura
--      do balancete de 2026 (que é 2025) NÃO as faz aparecer em 2025 — aparecem só em 2026.
--   4. A decisão é por FAMÍLIA: balanço anual não esconde conta de RESULTADO do balancete (não há DRE
--      anual de 2025), mas a DRE anual de 2024 esconde a de 2024. Seção NULL é família própria.
--   5. A decisão é por ENTIDADE: o balanço anual de uma entidade não esconde o balancete de outra.
--
-- NÃO PARA NO PRIMEIRO ERRO: anota e segue, e o bloco final reprova com a CONTAGEM (regra 2).
--
-- MEDIÇÃO (regra 2): 17 asserts. Com o filtro da alínea c' desligado (`where true`) reprovam 6 (as 3
-- analíticas fora de 2024/2025, as duas contagens do circulante e a conta de resultado de 2024); os
-- outros 11 são os valores do balanço e o lado "entra quando é a única fonte" (2026, resultado 2025,
-- sem seção, outra entidade). Com a regra AO CONTRÁRIO (parcial nunca entra) reprovam 10 — esse lado
-- é o que impede o conserto de virar "balancete excluído".

begin;

create temp sequence _falhas_0200;

create or replace function pg_temp.teste_assert_0200(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  else
    raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
    perform nextval('pg_temp._falhas_0200');
  end if;
end $$;

-- Os anos em que um rótulo aparece na série da entidade (texto "{2026}"; NULL = em ano nenhum).
create or replace function pg_temp.anos0200(p_caso uuid, p_rotulo text, p_entidade text) returns text
language sql as $$
  select array_agg(ano order by ano)::text from fn_valores_por_ano(p_caso, p_entidade)
   where rotulo_norm = fn_normalizar_texto(p_rotulo)
$$;
create or replace function pg_temp.v0200(p_caso uuid, p_rotulo text, p_ano int, p_entidade text) returns numeric
language sql as $$
  select valor from fn_valores_por_ano(p_caso, p_entidade)
   where rotulo_norm = fn_normalizar_texto(p_rotulo) and ano = p_ano
$$;

do $$
declare
  v_caso uuid; v_r jsonb; v_n int; v_txt text; v_num numeric;
  c  constant text := 'MOTO AGRICOLA VOLKWEIS LTDA';
  b  constant text := 'OUTRA REVENDA DE MAQUINAS LTDA';
  a1 constant text := '12388 1.1.5.01.007 TRANSFERENCIA DE MERCADORIAS TRATORES';
  a2 constant text := '12390 1.1.5.01.008 MERCADORIAS PARA REVENDA IMPLEMENTOS';
  a3 constant text := '10021 1.1.2.01.003 CLIENTES NACIONAIS TRATORES';
  r1 constant text := '30011 3.1.1.01.001 VENDA DE TRATORES BALCAO';
  s1 constant text := '99001 CONTA SEM SECAO DO BALANCETE';
begin
  v_caso := (fn_upsert_caso('0200: Fw Valtra, balancete sob balanço anual'))::uuid;

  -- BALANCO anual 2025: contas sintéticas, Saldo Inicial (= 2024) e Saldo Final (= 2025).
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0200/bp2025.pdf', 'balanco_2025.pdf', true, 'HASH-0200-1', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','ATIVO CIRCULANTE','secao_canonica','ativo_circulante','periodo_coluna','Saldo Inicial','valor_num','29275182.61','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',0,'chave','ATIVO CIRCULANTE','secao_canonica','ativo_circulante','periodo_coluna','Saldo Final','valor_num','33056432.15','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',1,'chave','CLIENTES','secao_canonica','ativo_circulante','periodo_coluna','Saldo Inicial','valor_num','5218337.81','confianca','0.97','origem_pagina','2'),
    jsonb_build_object('ordem',1,'chave','CLIENTES','secao_canonica','ativo_circulante','periodo_coluna','Saldo Final','valor_num','4292868.90','confianca','0.97','origem_pagina','2')
  ), 'N2');

  -- BALANCO anual 2024 (o documento do próprio exercício).
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2024', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0200/bp2024.pdf', 'balanco_2024.pdf', true, 'HASH-0200-2', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','ATIVO CIRCULANTE','secao_canonica','ativo_circulante','periodo_coluna','Saldo Final','valor_num','29275182.61','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',1,'chave','CLIENTES','secao_canonica','ativo_circulante','periodo_coluna','Saldo Final','valor_num','5218337.81','confianca','0.97','origem_pagina','2')
  ), 'N2');

  -- DRE anual 2024 (arranjo): só o exercício de 2024 tem DRE; 2025 NÃO tem.
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2024', 'DRE', 0.97,
    'nome_arquivo', 'supabase_storage', '0200/dre2024.pdf', 'dre_2024.pdf', true, 'HASH-0200-3', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','VENDA DE IMPLEMENTOS NOVOS','secao_canonica','receita_bruta','periodo_coluna','Saldo atual','valor_num','19374000','confianca','0.97','origem_pagina','1')
  ), 'N2');

  -- BALANCETE 01/01–30/06/2025: contas analíticas que o balanço anual NÃO tem.
  v_r := fn_registrar_documento(v_caso, c, 'outro', '01/01/2025 - 30/06/2025', 'BALANCETE', 0.97,
    'nome_arquivo', 'supabase_storage', '0200/balancete1s25.pdf', 'balancete_1s2025.pdf', true, 'HASH-0200-4', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave',a1,'secao_canonica','ativo_circulante','periodo_coluna','Saldo Anterior','valor_num','3100000.00','confianca','0.99','origem_pagina','5'),
    jsonb_build_object('ordem',0,'chave',a1,'secao_canonica','ativo_circulante','periodo_coluna','Débito','valor_num','8000000.00','confianca','0.99','origem_pagina','5'),
    jsonb_build_object('ordem',0,'chave',a1,'secao_canonica','ativo_circulante','periodo_coluna','Crédito','valor_num','7500000.00','confianca','0.99','origem_pagina','5'),
    jsonb_build_object('ordem',0,'chave',a1,'secao_canonica','ativo_circulante','periodo_coluna','Saldo Atual','valor_num','3600000.00','confianca','0.99','origem_pagina','5'),
    jsonb_build_object('ordem',1,'chave',a2,'secao_canonica','ativo_circulante','periodo_coluna','Saldo Anterior','valor_num','2200000.00','confianca','0.99','origem_pagina','5'),
    jsonb_build_object('ordem',1,'chave',a2,'secao_canonica','ativo_circulante','periodo_coluna','Saldo Atual','valor_num','2500000.00','confianca','0.99','origem_pagina','5'),
    jsonb_build_object('ordem',2,'chave',a3,'secao_canonica','ativo_circulante','periodo_coluna','Saldo Anterior','valor_num','1800000.00','confianca','0.99','origem_pagina','4'),
    jsonb_build_object('ordem',2,'chave',a3,'secao_canonica','ativo_circulante','periodo_coluna','Saldo Atual','valor_num','2100000.00','confianca','0.99','origem_pagina','4'),
    -- o MESMO rótulo do balanço: a regra antiga já o resolvia por rótulo; fica como controle
    jsonb_build_object('ordem',3,'chave','ATIVO CIRCULANTE','secao_canonica','ativo_circulante','periodo_coluna','Saldo Atual','valor_num','32000000.00','confianca','0.99','origem_pagina','1'),
    -- conta de RESULTADO: não há DRE anual de 2025, há de 2024
    jsonb_build_object('ordem',4,'chave',r1,'secao_canonica','receita_bruta','periodo_coluna','Saldo Anterior','valor_num','700000.00','confianca','0.99','origem_pagina','9'),
    jsonb_build_object('ordem',4,'chave',r1,'secao_canonica','receita_bruta','periodo_coluna','Saldo Atual','valor_num','900000.00','confianca','0.99','origem_pagina','9'),
    -- seção NULL: família própria; o ano não tem anual sem seção
    jsonb_build_object('ordem',5,'chave',s1,'periodo_coluna','Saldo Atual','valor_num','410000.00','confianca','0.99','origem_pagina','12')
  ), 'N2');

  -- BALANCETE 01/01–30/06/2026: 2026 NÃO tem balanço anual. A abertura dele (Saldo Anterior) é 2025.
  v_r := fn_registrar_documento(v_caso, c, 'outro', '01/01/2026 - 30/06/2026', 'BALANCETE', 0.97,
    'nome_arquivo', 'supabase_storage', '0200/balancete1s26.pdf', 'balancete_1s2026.pdf', true, 'HASH-0200-5', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave',a1,'secao_canonica','ativo_circulante','periodo_coluna','Saldo Anterior','valor_num','3650000.00','confianca','0.99','origem_pagina','5'),
    jsonb_build_object('ordem',0,'chave',a1,'secao_canonica','ativo_circulante','periodo_coluna','Saldo Atual','valor_num','4100000.00','confianca','0.99','origem_pagina','5'),
    jsonb_build_object('ordem',1,'chave',a2,'secao_canonica','ativo_circulante','periodo_coluna','Saldo Anterior','valor_num','2550000.00','confianca','0.99','origem_pagina','5'),
    jsonb_build_object('ordem',1,'chave',a2,'secao_canonica','ativo_circulante','periodo_coluna','Saldo Atual','valor_num','2700000.00','confianca','0.99','origem_pagina','5'),
    jsonb_build_object('ordem',2,'chave',a3,'secao_canonica','ativo_circulante','periodo_coluna','Saldo Anterior','valor_num','2150000.00','confianca','0.99','origem_pagina','4'),
    jsonb_build_object('ordem',2,'chave',a3,'secao_canonica','ativo_circulante','periodo_coluna','Saldo Atual','valor_num','2300000.00','confianca','0.99','origem_pagina','4'),
    jsonb_build_object('ordem',3,'chave','ATIVO CIRCULANTE','secao_canonica','ativo_circulante','periodo_coluna','Saldo Atual','valor_num','35000000.00','confianca','0.99','origem_pagina','1')
  ), 'N2');

  -- OUTRA entidade, só com BALANCETE jun/2025 (a primeira tem balanço anual de 2025; esta não).
  v_r := fn_registrar_documento(v_caso, b, 'outro', '01/01/2025 - 30/06/2025', 'BALANCETE', 0.97,
    'nome_arquivo', 'supabase_storage', '0200/balancete_b.pdf', 'balancete_b_1s2025.pdf', true, 'HASH-0200-6', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','CAIXA DA OUTRA REVENDA','secao_canonica','ativo_circulante','periodo_coluna','Saldo Atual','valor_num','777000.00','confianca','0.99','origem_pagina','1')
  ), 'N2');

  raise notice '--- 1. ano COM balanço anual: as analíticas do balancete não entram ---';
  v_txt := pg_temp.anos0200(v_caso, a1, c);
  perform pg_temp.teste_assert_0200(v_txt = '{2026}',
    'conta analítica 12388: só em 2026 (nem o Saldo Atual de 30/06/2025 em 2025, nem a abertura em 2024)', coalesce(v_txt, '(nulo)'));
  v_txt := pg_temp.anos0200(v_caso, a2, c);
  perform pg_temp.teste_assert_0200(v_txt = '{2026}',
    'conta analítica 12390: só em 2026', coalesce(v_txt, '(nulo)'));
  v_txt := pg_temp.anos0200(v_caso, a3, c);
  perform pg_temp.teste_assert_0200(v_txt = '{2026}',
    'conta analítica 10021 (clientes): só em 2026', coalesce(v_txt, '(nulo)'));

  raise notice '--- 2. o circulante de 2024 e 2025 é o do balanço (sintético), com os valores dele ---';
  select count(*) into v_n from fn_valores_por_ano(v_caso, c) where secao_canonica = 'ativo_circulante' and ano = 2025;
  perform pg_temp.teste_assert_0200(v_n = 2,
    'o circulante de 2025 tem 2 contas (ATIVO CIRCULANTE, CLIENTES) — não 2 + as analíticas do balancete', format('%s conta(s)', v_n));
  select count(*) into v_n from fn_valores_por_ano(v_caso, c) where secao_canonica = 'ativo_circulante' and ano = 2024;
  perform pg_temp.teste_assert_0200(v_n = 2,
    'o circulante de 2024 tem 2 contas (a abertura do balancete de 2025 não acrescenta nenhuma)', format('%s conta(s)', v_n));
  v_num := pg_temp.v0200(v_caso, 'ATIVO CIRCULANTE', 2025, c);
  perform pg_temp.teste_assert_0200(v_num = 33056432.15,
    'ATIVO CIRCULANTE 2025 = 33.056.432,15 (o balanço), não o Saldo Atual de 30/06 (32.000.000)', format('%s', v_num));
  v_num := pg_temp.v0200(v_caso, 'ATIVO CIRCULANTE', 2024, c);
  perform pg_temp.teste_assert_0200(v_num = 29275182.61, 'ATIVO CIRCULANTE 2024 = 29.275.182,61', format('%s', v_num));
  v_num := pg_temp.v0200(v_caso, 'CLIENTES', 2025, c);
  perform pg_temp.teste_assert_0200(v_num = 4292868.90, 'CLIENTES 2025 = 4.292.868,90', format('%s', v_num));
  v_num := pg_temp.v0200(v_caso, 'CLIENTES', 2024, c);
  perform pg_temp.teste_assert_0200(v_num = 5218337.81, 'CLIENTES 2024 = 5.218.337,81', format('%s', v_num));

  raise notice '--- 3. ano SEM balanço anual (2026): o balancete é a única fonte e entra ---';
  v_num := pg_temp.v0200(v_caso, a1, 2026, c);
  perform pg_temp.teste_assert_0200(v_num = 4100000, 'conta 12388 em 2026 = o Saldo Atual de 30/06/2026 (4.100.000)', format('%s', v_num));
  v_num := pg_temp.v0200(v_caso, a3, 2026, c);
  perform pg_temp.teste_assert_0200(v_num = 2300000, 'conta 10021 em 2026 = 2.300.000', format('%s', v_num));
  v_num := pg_temp.v0200(v_caso, 'ATIVO CIRCULANTE', 2026, c);
  perform pg_temp.teste_assert_0200(v_num = 35000000, 'ATIVO CIRCULANTE 2026 = 35.000.000 (única fonte do ano)', format('%s', v_num));

  raise notice '--- 4. a decisão é por FAMÍLIA da demonstração ---';
  v_txt := pg_temp.anos0200(v_caso, r1, c);
  perform pg_temp.teste_assert_0200(v_txt = '{2025}',
    'conta de RESULTADO do balancete: 2025 entra (não há DRE anual de 2025; o balanço anual não a esconde), 2024 não (há DRE anual de 2024)', coalesce(v_txt, '(nulo)'));
  v_num := pg_temp.v0200(v_caso, r1, 2025, c);
  perform pg_temp.teste_assert_0200(v_num = 900000, 'e o valor de 2025 é o Saldo Atual (900.000)', format('%s', v_num));
  v_txt := pg_temp.anos0200(v_caso, s1, c);
  perform pg_temp.teste_assert_0200(v_txt = '{2025}',
    'conta sem seção (família própria): entra em 2025, o ano não tem anual sem seção', coalesce(v_txt, '(nulo)'));

  raise notice '--- 5. a decisão é por ENTIDADE ---';
  v_num := pg_temp.v0200(v_caso, 'CAIXA DA OUTRA REVENDA', 2025, null);
  perform pg_temp.teste_assert_0200(v_num = 777000,
    'sem filtro de entidade: o balancete da OUTRA entidade entra em 2025 mesmo com o balanço anual da primeira', format('%s', v_num));
  v_num := pg_temp.v0200(v_caso, 'ATIVO CIRCULANTE', 2025, null);
  perform pg_temp.teste_assert_0200(v_num = 33056432.15,
    'e sem filtro o balanço anual segue valendo para a primeira (33.056.432,15)', format('%s', v_num));
end $$;

do $$
declare
  v_n int;
begin
  select case when is_called then last_value else 0 end into v_n from pg_temp._falhas_0200;
  if v_n > 0 then
    raise exception 'FALHOU: % assert(s) da 0200 reprovaram — ver as linhas FALHOU acima', v_n;
  end if;
  raise notice 'TODOS OS TESTES DA 0200 (balancete semestral sob balanço anual) PASSARAM';
end $$;

rollback;
