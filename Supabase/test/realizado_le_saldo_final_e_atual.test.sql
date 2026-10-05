-- Testes da 0201 (Supabase/migrations/0201_o_realizado_que_nao_lia_saldo_final_e_saldo_atual.sql).
-- Rodar via Supabase/test/run.sh.
--
-- O ARRANJO É O REAL, MEDIDO EM PRODUÇÃO (05/10/2026, só-leitura, caso "Fw Valtra" 03a66ab6, empresa
-- MOTO AGRICOLA VOLKWEIS LTDA). Em produção `fn_linhas_do_realizado` devolvia só as linhas do DFC
-- (entidade "Metodo Indireto Moto Agricola") e NENHUMA do BALANCO nem da DRE. Reproduzido aqui:
--
--   • BALANCO ref "2025" e ref "2024", colunas `Saldo Inicial` / `Saldo Final`; DRE ref "2025" e ref
--     "2024", colunas `Saldo anterior` / `Saldo atual`. Nenhuma traz ano no texto.
--   • Os números das razões do caso (2023 / 2024 / 2025), REAIS, são os de produção:
--       receita líquida  42.141.648,35 / 41.860.490,85 / 38.676.650,89
--       CMV             -33.266.737,80 / -31.864.336,87 / -29.960.764,50
--       CLIENTES          4.045.437,98 /  5.218.337,81 /  4.292.868,90
--       ESTOQUE          12.319.473,90 / 18.801.847,59 / 26.420.390,24
--       FORNECEDORES      6.539.839,93 /  8.212.315,99 /  6.726.585,42
--     Quem leu em qual documento/coluna cada um mora é o arranjo: o de um ano é o `Saldo Final` do
--     documento daquele ano E o `Saldo Inicial` do ano seguinte (o mesmo número nos dois), que é
--     como o documento anual se encadeia. A SEÇÃO de "RECEITA LIQUIDA" ('receita_bruta') e a de
--     "FORNECEDORES" ('passivo_circulante') é arranjo — a seção não é o que o teste mede.
--   • Os marcados "arranjo" abaixo (IMPOSTOS A RECUPERAR, os documentos trimestral/semestral, o
--     CONTRATO_SOCIAL, o Débito, o ticket médio) foram escolhidos aqui porque o valor de produção
--     não foi anotado: afirmam só a ORDEM entre números (o que vence), nunca o número como se fosse do
--     cliente (regra 4).
--
-- O QUE TRAVA, em COMPORTAMENTO (regra 3):
--   1. O documento anual de Saldo Final/Saldo atual entra: as cinco razões do caso, três anos, 15 células.
--   2. Abertura pertence ao ano anterior e perde para o fechamento, mesmo MAIOR em módulo.
--   3. Movimento (Débito) nunca é saldo; CONTRATO_SOCIAL não entra.
--   4. Período parcial: trimestral NÃO sobrepõe o anual do mesmo ano; semestral de 2026 ENTRA porque
--      é a única fonte do ano.
--   5. Coluna sem ano e sem nome de saldo ("Ticket médio (R$)") continua SEM exercício (decisão da
--      0150): diferença deliberada em relação a fn_valores_por_ano. Coluna com ano no texto segue valendo.
--   6. CONTA ÚNICA: toda célula de fn_linhas_do_realizado é idêntica à da série fn_valores_por_ano.
--
-- NÃO PARA NO PRIMEIRO ERRO: anota e segue, e o bloco final reprova com a CONTAGEM (regra 2).
--
-- MEDIÇÃO (regra 2): 27 asserts. Com a fn_linhas_do_realizado da 0151 de volta (correção desligada) reprovam 18;
-- sem o fechamento-antes-de-abertura no order by, 2; sem o filtro de parcial (c'), 4; sem a exclusão
-- Societário/Legal/Garantias, 2; com a abertura lida no MESMO ano em vez de ano - 1, 7; com fn_coluna_e_saldo
-- sempre falso (coluna sem ano volta a ficar fora), 18. O assert do Débito (99.999.999) é CONTROLE: a coluna não
-- tem ano nem nome de saldo e já caía fora na 0150, então nenhuma mutação o reprova.

begin;

create temp sequence _falhas_0201;

create or replace function pg_temp.teste_assert_0201(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  else
    raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
    perform nextval('pg_temp._falhas_0201');
  end if;
end $$;

-- O valor de uma célula do realizado, ou NULL quando a linha não existe naquele exercício.
create or replace function pg_temp.l0201(p_caso uuid, p_rotulo text, p_ano int) returns numeric
language sql as $$
  select valor from fn_linhas_do_realizado(p_caso, 'MOTO AGRICOLA VOLKWEIS LTDA')
   where rotulo_norm = fn_normalizar_texto(p_rotulo) and exercicio = p_ano
$$;

do $$
declare
  v_caso uuid; v_r jsonb; v_n int; v_num numeric; v_txt text;
  c constant text := 'MOTO AGRICOLA VOLKWEIS LTDA';
begin
  v_caso := (fn_upsert_caso('0201: Fw Valtra, realizado'))::uuid;

  -- BALANCO 2025: Saldo Inicial (= fechamento de 2024) e Saldo Final.
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0201/bp2025.pdf', 'balanco_2025.pdf', true, 'HASH-0201-1', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','CLIENTES','secao_canonica','ativo_circulante','periodo_coluna','Saldo Inicial','valor_num','5218337.81','confianca','0.97','origem_pagina','2'),
    jsonb_build_object('ordem',0,'chave','CLIENTES','secao_canonica','ativo_circulante','periodo_coluna','Saldo Final','valor_num','4292868.90','confianca','0.97','origem_pagina','2'),
    -- arranjo: o Débito do ano, enorme, que não é saldo de coisa nenhuma
    jsonb_build_object('ordem',0,'chave','CLIENTES','secao_canonica','ativo_circulante','periodo_coluna','Débito','valor_num','99999999.00','confianca','0.97','origem_pagina','2'),
    jsonb_build_object('ordem',1,'chave','ESTOQUES','secao_canonica','ativo_circulante','periodo_coluna','Saldo Inicial','valor_num','18801847.59','confianca','0.97','origem_pagina','2'),
    jsonb_build_object('ordem',1,'chave','ESTOQUES','secao_canonica','ativo_circulante','periodo_coluna','Saldo Final','valor_num','26420390.24','confianca','0.97','origem_pagina','2'),
    jsonb_build_object('ordem',2,'chave','FORNECEDORES','secao_canonica','passivo_circulante','periodo_coluna','Saldo Inicial','valor_num','8212315.99','confianca','0.97','origem_pagina','3'),
    jsonb_build_object('ordem',2,'chave','FORNECEDORES','secao_canonica','passivo_circulante','periodo_coluna','Saldo Final','valor_num','6726585.42','confianca','0.97','origem_pagina','3'),
    -- arranjo: abertura MAIOR em módulo que o fechamento de 2024 do balanço de 2024
    jsonb_build_object('ordem',3,'chave','IMPOSTOS A RECUPERAR','secao_canonica','ativo_circulante','periodo_coluna','Saldo Inicial','valor_num','3500000.00','confianca','0.97','origem_pagina','2'),
    jsonb_build_object('ordem',3,'chave','IMPOSTOS A RECUPERAR','secao_canonica','ativo_circulante','periodo_coluna','Saldo Final','valor_num','3200000.00','confianca','0.97','origem_pagina','2')
  ), 'N2');

  -- BALANCO 2024.
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2024', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0201/bp2024.pdf', 'balanco_2024.pdf', true, 'HASH-0201-2', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','CLIENTES','secao_canonica','ativo_circulante','periodo_coluna','Saldo Inicial','valor_num','4045437.98','confianca','0.97','origem_pagina','2'),
    jsonb_build_object('ordem',0,'chave','CLIENTES','secao_canonica','ativo_circulante','periodo_coluna','Saldo Final','valor_num','5218337.81','confianca','0.97','origem_pagina','2'),
    jsonb_build_object('ordem',1,'chave','ESTOQUES','secao_canonica','ativo_circulante','periodo_coluna','Saldo Inicial','valor_num','12319473.90','confianca','0.97','origem_pagina','2'),
    jsonb_build_object('ordem',1,'chave','ESTOQUES','secao_canonica','ativo_circulante','periodo_coluna','Saldo Final','valor_num','18801847.59','confianca','0.97','origem_pagina','2'),
    jsonb_build_object('ordem',2,'chave','FORNECEDORES','secao_canonica','passivo_circulante','periodo_coluna','Saldo Inicial','valor_num','6539839.93','confianca','0.97','origem_pagina','3'),
    jsonb_build_object('ordem',2,'chave','FORNECEDORES','secao_canonica','passivo_circulante','periodo_coluna','Saldo Final','valor_num','8212315.99','confianca','0.97','origem_pagina','3'),
    jsonb_build_object('ordem',3,'chave','IMPOSTOS A RECUPERAR','secao_canonica','ativo_circulante','periodo_coluna','Saldo Final','valor_num','3000000.00','confianca','0.97','origem_pagina','2')
  ), 'N2');

  -- DRE 2025: Saldo anterior (= 2024) e Saldo atual (= 2025).
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2025', 'DRE', 0.97,
    'nome_arquivo', 'supabase_storage', '0201/dre2025.pdf', 'dre_2025.pdf', true, 'HASH-0201-3', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','RECEITA LIQUIDA','secao_canonica','receita_bruta','periodo_coluna','Saldo anterior','valor_num','41860490.85','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',0,'chave','RECEITA LIQUIDA','secao_canonica','receita_bruta','periodo_coluna','Saldo atual','valor_num','38676650.89','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',1,'chave','CMV','secao_canonica','custos','periodo_coluna','Saldo anterior','valor_num','-31864336.87','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',1,'chave','CMV','secao_canonica','custos','periodo_coluna','Saldo atual','valor_num','-29960764.50','confianca','0.97','origem_pagina','1'),
    -- arranjo: coluna que não nomeia exercício nem saldo — continua sem exercício
    jsonb_build_object('ordem',2,'chave','TICKET MEDIO','secao_canonica','receita_bruta','periodo_coluna','Ticket médio (R$)','valor_num','85000.00','confianca','0.97','origem_pagina','1'),
    -- arranjo: coluna com ano no texto — segue valendo como antes
    jsonb_build_object('ordem',3,'chave','VENDAS DO ANO','secao_canonica','receita_bruta','periodo_coluna','2025','valor_num','1000.00','confianca','0.97','origem_pagina','1')
  ), 'N2');

  -- DRE 2024.
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2024', 'DRE', 0.97,
    'nome_arquivo', 'supabase_storage', '0201/dre2024.pdf', 'dre_2024.pdf', true, 'HASH-0201-4', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','RECEITA LIQUIDA','secao_canonica','receita_bruta','periodo_coluna','Saldo anterior','valor_num','42141648.35','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',0,'chave','RECEITA LIQUIDA','secao_canonica','receita_bruta','periodo_coluna','Saldo atual','valor_num','41860490.85','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',1,'chave','CMV','secao_canonica','custos','periodo_coluna','Saldo anterior','valor_num','-33266737.80','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',1,'chave','CMV','secao_canonica','custos','periodo_coluna','Saldo atual','valor_num','-31864336.87','confianca','0.97','origem_pagina','1')
  ), 'N2');

  -- arranjo: DRE do 1º trimestre de 2025 (período PARCIAL) com a receita muito diferente e uma conta
  -- que só existe nele. O ano 2025 já tem DRE anual: o trimestre não entra.
  v_r := fn_registrar_documento(v_caso, c, 'trimestre', '1T25', 'DRE', 0.97,
    'nome_arquivo', 'supabase_storage', '0201/dre1t25.pdf', 'dre_1t25.pdf', true, 'HASH-0201-5', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','RECEITA LIQUIDA','secao_canonica','receita_bruta','periodo_coluna','Saldo atual','valor_num','99000000.00','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',1,'chave','OUTRAS RECEITAS','secao_canonica','receita_bruta','periodo_coluna','Saldo atual','valor_num','777000.00','confianca','0.97','origem_pagina','1')
  ), 'N2');

  -- arranjo: DRE do 1º semestre de 2026 (período PARCIAL), única fonte do ano 2026. O Saldo anterior
  -- dele é 2025, que já tem anual: não entra; o Saldo atual é 2026 e ENTRA.
  v_r := fn_registrar_documento(v_caso, c, 'outro', '01/01/2026 - 30/06/2026', 'DRE', 0.97,
    'nome_arquivo', 'supabase_storage', '0201/dre1s26.pdf', 'dre_1s26.pdf', true, 'HASH-0201-6', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','RECEITA LIQUIDA','secao_canonica','receita_bruta','periodo_coluna','Saldo anterior','valor_num','55000000.00','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',0,'chave','RECEITA LIQUIDA','secao_canonica','receita_bruta','periodo_coluna','Saldo atual','valor_num','20000000.00','confianca','0.97','origem_pagina','1')
  ), 'N2');

  -- CONTRATO_SOCIAL com coluna de saldo: quotas não são saldo.
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2025', 'CONTRATO_SOCIAL', 0.97,
    'nome_arquivo', 'supabase_storage', '0201/contrato.pdf', 'contrato_social.pdf', true, 'HASH-0201-7', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','total - capital social','secao_canonica','patrimonio_liquido','periodo_coluna','Saldo Final','valor_num','15500000','confianca','0.97','origem_pagina','2')
  ), 'N2');

  raise notice '--- 1. o documento anual de Saldo Final/Saldo atual entra (15 células das cinco razões) ---';
  select count(*) into v_n from (values ('RECEITA LIQUIDA'),('CMV'),('CLIENTES'),('ESTOQUES'),('FORNECEDORES')) r(rot),
         generate_series(2023, 2025) a
   where pg_temp.l0201(v_caso, r.rot, a) is not null;
  perform pg_temp.teste_assert_0201(v_n = 15, 'as cinco razões do caso têm valor nos três exercícios (15 de 15)', format('%s de 15', v_n));
  perform pg_temp.teste_assert_0201(pg_temp.l0201(v_caso, 'RECEITA LIQUIDA', 2023) = 42141648.35, 'RECEITA LIQUIDA 2023 = Saldo anterior da DRE 2024 (42.141.648,35)');
  perform pg_temp.teste_assert_0201(pg_temp.l0201(v_caso, 'RECEITA LIQUIDA', 2024) = 41860490.85, 'RECEITA LIQUIDA 2024 = 41.860.490,85');
  perform pg_temp.teste_assert_0201(pg_temp.l0201(v_caso, 'RECEITA LIQUIDA', 2025) = 38676650.89, 'RECEITA LIQUIDA 2025 = Saldo atual da DRE 2025 (38.676.650,89), não o trimestre de 99 mi');
  perform pg_temp.teste_assert_0201(pg_temp.l0201(v_caso, 'CMV', 2023) = -33266737.80, 'CMV 2023 = -33.266.737,80');
  perform pg_temp.teste_assert_0201(pg_temp.l0201(v_caso, 'CMV', 2024) = -31864336.87, 'CMV 2024 = -31.864.336,87');
  perform pg_temp.teste_assert_0201(pg_temp.l0201(v_caso, 'CMV', 2025) = -29960764.50, 'CMV 2025 = -29.960.764,50');
  perform pg_temp.teste_assert_0201(pg_temp.l0201(v_caso, 'CLIENTES', 2023) = 4045437.98, 'CLIENTES 2023 = Saldo Inicial do balanço 2024 (4.045.437,98)');
  perform pg_temp.teste_assert_0201(pg_temp.l0201(v_caso, 'CLIENTES', 2025) = 4292868.90, 'CLIENTES 2025 = Saldo Final (4.292.868,90)');
  perform pg_temp.teste_assert_0201(pg_temp.l0201(v_caso, 'ESTOQUES', 2025) = 26420390.24, 'ESTOQUES 2025 = 26.420.390,24');
  perform pg_temp.teste_assert_0201(pg_temp.l0201(v_caso, 'ESTOQUES', 2023) = 12319473.90, 'ESTOQUES 2023 = 12.319.473,90');
  perform pg_temp.teste_assert_0201(pg_temp.l0201(v_caso, 'FORNECEDORES', 2023) = 6539839.93, 'FORNECEDORES 2023 = 6.539.839,93');
  perform pg_temp.teste_assert_0201(pg_temp.l0201(v_caso, 'FORNECEDORES', 2025) = 6726585.42, 'FORNECEDORES 2025 = 6.726.585,42');

  raise notice '--- 2. abertura pertence ao ano anterior e perde para o fechamento ---';
  perform pg_temp.teste_assert_0201(pg_temp.l0201(v_caso, 'CLIENTES', 2024) = 5218337.81,
    'CLIENTES 2024 = 5.218.337,81 (Saldo Final de 2024 = Saldo Inicial de 2025), nunca o do ano do documento');
  v_num := pg_temp.l0201(v_caso, 'IMPOSTOS A RECUPERAR', 2024);
  perform pg_temp.teste_assert_0201(v_num = 3000000,
    'IMPOSTOS A RECUPERAR 2024 = 3.000.000 (Saldo Final de 2024), não a abertura de 2025 que é MAIOR (3.500.000)', format('%s', v_num));
  v_num := pg_temp.l0201(v_caso, 'IMPOSTOS A RECUPERAR', 2025);
  perform pg_temp.teste_assert_0201(v_num = 3200000, 'IMPOSTOS A RECUPERAR 2025 = Saldo Final (3.200.000)', format('%s', v_num));

  raise notice '--- 3. movimento e documento societário não entram ---';
  select count(*) into v_n from fn_linhas_do_realizado(v_caso, c) where valor = 99999999;
  perform pg_temp.teste_assert_0201(v_n = 0, 'o Débito de 99.999.999 não vira saldo de linha nenhuma', format('%s linhas', v_n));
  select count(*) into v_n from fn_linhas_do_realizado(v_caso, c) where rotulo_norm like '%capital social%';
  perform pg_temp.teste_assert_0201(v_n = 0, 'CONTRATO_SOCIAL (capital social, coluna Saldo Final) fica fora', format('%s linhas', v_n));

  raise notice '--- 4. período parcial: só o ano sem anual da família ---';
  v_num := pg_temp.l0201(v_caso, 'OUTRAS RECEITAS', 2025);
  perform pg_temp.teste_assert_0201(v_num is null, 'conta que só existe na DRE do 1º trimestre NÃO entra em 2025 (o ano tem DRE anual)', format('%s', v_num));
  v_num := pg_temp.l0201(v_caso, 'RECEITA LIQUIDA', 2026);
  perform pg_temp.teste_assert_0201(v_num = 20000000, 'o semestre de 2026 ENTRA: é a única fonte do ano (20.000.000)', format('%s', v_num));
  select string_agg(exercicio::text, ',' order by exercicio) into v_txt
    from fn_linhas_do_realizado(v_caso, c) where rotulo_norm = 'receita liquida';
  perform pg_temp.teste_assert_0201(v_txt = '2023,2024,2025,2026',
    'RECEITA LIQUIDA tem os exercícios 2023 a 2026, um por ano (o Saldo anterior do semestre, 55 mi, não duplica 2025)', v_txt);

  raise notice '--- 5. coluna sem ano e sem nome de saldo continua sem exercício ---';
  select count(*) into v_n from fn_linhas_do_realizado(v_caso, c) where rotulo_norm = 'ticket medio';
  perform pg_temp.teste_assert_0201(v_n = 0, '"Ticket médio (R$)" não vira exercício no realizado (decisão da 0150)', format('%s linhas', v_n));
  select count(*) into v_n from fn_valores_por_ano(v_caso, c) where rotulo_norm = 'ticket medio';
  perform pg_temp.teste_assert_0201(v_n = 1, 'controle: a série por ano, mais permissiva, o lê (diferença deliberada entre as duas funções)', format('%s linhas', v_n));
  v_num := pg_temp.l0201(v_caso, 'VENDAS DO ANO', 2025);
  perform pg_temp.teste_assert_0201(v_num = 1000, 'coluna com ano no texto ("2025") segue valendo como antes', format('%s', v_num));

  raise notice '--- 6. conta única: cada célula do realizado é a da série por ano ---';
  select count(*) into v_n
    from fn_linhas_do_realizado(v_caso, c) l
    join fn_valores_por_ano(v_caso, c) s
      on s.rotulo_norm = l.rotulo_norm and s.secao_canonica is not distinct from l.secao_canonica and s.ano = l.exercicio
   where s.valor is distinct from l.valor;
  perform pg_temp.teste_assert_0201(v_n = 0, 'nenhuma célula do realizado difere da série por ano', format('%s divergentes', v_n));
  select count(*) into v_n
    from fn_linhas_do_realizado(v_caso, c) l
    left join fn_valores_por_ano(v_caso, c) s
      on s.rotulo_norm = l.rotulo_norm and s.secao_canonica is not distinct from l.secao_canonica and s.ano = l.exercicio
   where s.valor is null;
  perform pg_temp.teste_assert_0201(v_n = 0, 'e nenhuma célula do realizado falta na série por ano', format('%s ausentes', v_n));
  select count(*) - count(distinct (rotulo_norm, secao_canonica, exercicio)) into v_n from fn_linhas_do_realizado(v_caso, c);
  perform pg_temp.teste_assert_0201(v_n = 0, 'uma linha por (rótulo, seção, exercício)', format('%s duplicadas', v_n));
end $$;

do $$
declare
  v_n int;
begin
  select case when is_called then last_value else 0 end into v_n from pg_temp._falhas_0201;
  if v_n > 0 then
    raise exception 'FALHOU: % assert(s) da 0201 reprovaram — ver as linhas FALHOU acima', v_n;
  end if;
  raise notice 'TODOS OS TESTES DA 0201 (realizado lê Saldo Final/Saldo atual) PASSARAM';
end $$;

rollback;
