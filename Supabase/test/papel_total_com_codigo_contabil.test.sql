-- Testes da 0202 (Supabase/migrations/0202_o_total_com_codigo_contabil_que_virava_conta.sql).
-- Rodar via Supabase/test/run.sh.
--
-- O DEFEITO, medido no arnês de variações (Verificação/variacoes.mts, variante
-- `codigo_contabil_no_rotulo`): o Mapa de Dívida com o código do ERP na frente de cada linha, INCLUSIVE
-- do TOTAL ("2.3.71 TOTAL — saldo devedor"), tinha o papel do TOTAL lido como `conta` e o total virava
-- uma tranche a mais: dívida de 102.600 onde o documento diz 51.300.
--
-- O ARRANJO. Os rótulos de TOTAL com código são o do arnês (que reproduz o formato do ERP); o Mapa de
-- Dívida do bloco 4 é um arranjo com nove tranches somando 51.300 e o TOTAL de 51.300 — os dois números
-- do arnês; os valores individuais das tranches são arranjo (o arnês mede a soma, e é a soma que o teste
-- afirma — regra 4: nenhum número aqui é apresentado como do cliente).
--
-- O QUE TRAVA, em COMPORTAMENTO (regra 3):
--   1. Rótulo de total com código contábil na frente é subtotal, em todas as grafias do prefixo.
--   2. Os outros grupos da função (ativo circulante, lucro líquido, indicador gerencial) também
--      enxergam o nome por baixo do código.
--   3. CONTROLES: conta com código continua conta; "2.500" (um ponto) e "1.1" (dois grupos) não são
--      código; rótulo sem código não mudou.
--   4. No caso: a tela de modelagem não soma o TOTAL do mapa de dívida como conta (51.300, não 102.600).
--
-- NÃO PARA NO PRIMEIRO ERRO: anota e segue, e o bloco final reprova com a CONTAGEM (regra 2).
--
-- MEDIÇÃO (regra 2): 21 asserts. Com a fn_papel_linha da 0116 de volta (correção desligada) reprovam 13 — e a
-- soma das contas do mapa dá 102.600, o número do arnês; sem tirar o código dos tokens estruturais, 1; sem
-- tirá-lo do texto, 11; com o regex exigindo 4 grupos, 12; com o regex aceitando 2 grupos ("1.1" vira código), 1.

begin;

create temp sequence _falhas_0202;

create or replace function pg_temp.teste_assert_0202(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  else
    raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
    perform nextval('pg_temp._falhas_0202');
  end if;
end $$;

do $$
declare
  v_caso uuid; v_r jsonb; v_num numeric; v_papel text; v_n int; v_txt text;
  c constant text := 'EMPRESA DO MAPA LTDA';
begin
  raise notice '--- 1. total com código contábil na frente é subtotal ---';
  perform pg_temp.teste_assert_0202(fn_papel_linha('2.3.71 TOTAL — saldo devedor', 'MAPA_DIVIDA') = 'subtotal',
    'o rótulo do arnês ("2.3.71 TOTAL — saldo devedor") é subtotal', fn_papel_linha('2.3.71 TOTAL — saldo devedor', 'MAPA_DIVIDA'));
  perform pg_temp.teste_assert_0202(fn_papel_linha('2.3.71 TOTAL') = 'subtotal', 'código + TOTAL');
  perform pg_temp.teste_assert_0202(fn_papel_linha('2.3.71 - Total geral') = 'subtotal', 'separador " - " depois do código');
  perform pg_temp.teste_assert_0202(fn_papel_linha('1.1.01.002 TOTAL DO ATIVO') = 'subtotal', 'código de quatro grupos + TOTAL DO ATIVO');
  perform pg_temp.teste_assert_0202(fn_papel_linha('2.3.71 Subtotal curto prazo') = 'subtotal', 'código + Subtotal');
  perform pg_temp.teste_assert_0202(fn_papel_linha('2.3.71 Soma das tranches') = 'subtotal', 'código + Soma');
  perform pg_temp.teste_assert_0202(fn_papel_linha('  2.3.71. TOTAIS') = 'subtotal', 'espaços na frente, ponto depois do código, TOTAIS');

  raise notice '--- 2. os outros grupos da função também enxergam o nome por baixo do código ---';
  perform pg_temp.teste_assert_0202(fn_papel_linha('1.1.01 ATIVO CIRCULANTE') = 'subtotal', '"1.1.01 ATIVO CIRCULANTE" é o grupo (b), subtotal');
  perform pg_temp.teste_assert_0202(fn_papel_linha('3.2.05 Lucro líquido') = 'subtotal', '"3.2.05 Lucro líquido" é a linha de resultado (c), subtotal');
  perform pg_temp.teste_assert_0202(fn_papel_linha('3.1.01 Ticket médio') = 'derivado', '"3.1.01 Ticket médio" é indicador, derivado');

  raise notice '--- 3. controles: o que NÃO é código, e o que não mudou ---';
  perform pg_temp.teste_assert_0202(fn_papel_linha('1.1.01.002 Caixa e bancos') = 'conta', 'conta com código continua conta');
  perform pg_temp.teste_assert_0202(fn_papel_linha('2.3.71 Banco Alfa S.A. - capital de giro') = 'conta', 'tranche com código continua conta');
  perform pg_temp.teste_assert_0202(fn_papel_linha('2.500 toneladas de total') = 'conta', '"2.500" (um ponto) não é código: o rótulo não começa por total');
  perform pg_temp.teste_assert_0202(fn_papel_linha('1.1 Total de vendas') = 'conta', '"1.1" (dois grupos) não é código: sem mudança');
  perform pg_temp.teste_assert_0202(fn_papel_linha('TOTAL DO ATIVO') = 'subtotal', 'sem código: TOTAL DO ATIVO segue subtotal');
  perform pg_temp.teste_assert_0202(fn_papel_linha('Caixa e bancos') = 'conta', 'sem código: Caixa e bancos segue conta');
  perform pg_temp.teste_assert_0202(fn_sem_codigo_de_conta('1.1.01.002 Caixa e bancos') = 'Caixa e bancos', 'fn_sem_codigo_de_conta tira o código do início');
  perform pg_temp.teste_assert_0202(fn_sem_codigo_de_conta('Parcela 2.3.71 vencida') = 'Parcela 2.3.71 vencida', 'e só do início: código no meio do rótulo fica');

  raise notice '--- 4. no caso: a tela de modelagem não soma o TOTAL do mapa de dívida como conta ---';
  v_caso := (fn_upsert_caso('0202: mapa de dívida com código'))::uuid;
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2025', 'MAPA_DIVIDA', 0.97,
    'nome_arquivo', 'supabase_storage', '0202/mapa.pdf', 'mapa_divida_2025.pdf', true, 'HASH-0202-1', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','2.3.01 Banco Alfa - capital de giro','secao_canonica','passivo_circulante','periodo_coluna','2025','valor_num','5000','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',1,'chave','2.3.02 Banco Beta - capital de giro','secao_canonica','passivo_circulante','periodo_coluna','2025','valor_num','5100','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',2,'chave','2.3.03 Banco Gama - desconto de duplicatas','secao_canonica','passivo_circulante','periodo_coluna','2025','valor_num','5200','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',3,'chave','2.3.04 Banco Delta - CCB','secao_canonica','passivo_circulante','periodo_coluna','2025','valor_num','5300','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',4,'chave','2.3.05 Banco Epsilon - FINAME','secao_canonica','passivo_circulante','periodo_coluna','2025','valor_num','5400','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',5,'chave','2.3.06 Banco Zeta - leasing','secao_canonica','passivo_circulante','periodo_coluna','2025','valor_num','5500','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',6,'chave','2.3.07 Banco Eta - cheque especial','secao_canonica','passivo_circulante','periodo_coluna','2025','valor_num','5700','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',7,'chave','2.3.08 Banco Theta - cartão corporativo','secao_canonica','passivo_circulante','periodo_coluna','2025','valor_num','6000','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',8,'chave','2.3.09 Banco Iota - conta garantida','secao_canonica','passivo_circulante','periodo_coluna','2025','valor_num','8100','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',9,'chave','2.3.71 TOTAL — saldo devedor','secao_canonica','passivo_circulante','periodo_coluna','2025','valor_num','51300','confianca','0.97','origem_pagina','1')
  ), 'N2');

  select papel into v_papel from fn_linhas_para_modelagem(v_caso) where chave like '%TOTAL%';
  perform pg_temp.teste_assert_0202(v_papel = 'subtotal', 'a linha "2.3.71 TOTAL — saldo devedor" chega à modelagem como subtotal', coalesce(v_papel, '(nula)'));
  select count(*), coalesce(sum(valor_ultimo), 0) into v_n, v_num from fn_linhas_para_modelagem(v_caso) where papel = 'conta';
  perform pg_temp.teste_assert_0202(v_num = 51300, 'a soma das CONTAS do mapa é 51.300 (o que o documento diz), não 102.600', format('%s em %s linhas', v_num, v_n));
  perform pg_temp.teste_assert_0202(v_n = 9, 'são nove tranches, e o total não é a décima', format('%s linhas', v_n));
end $$;

do $$
declare
  v_n int;
begin
  select case when is_called then last_value else 0 end into v_n from pg_temp._falhas_0202;
  if v_n > 0 then
    raise exception 'FALHOU: % assert(s) da 0202 reprovaram — ver as linhas FALHOU acima', v_n;
  end if;
  raise notice 'TODOS OS TESTES DA 0202 (total com código contábil) PASSARAM';
end $$;

rollback;
