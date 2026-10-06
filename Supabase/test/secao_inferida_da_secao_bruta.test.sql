-- Testes da 0203 (Supabase/migrations/0203_a_secao_que_a_ia_nao_deu_e_a_linha_que_sumia.sql).
-- Rodar via Supabase/test/run.sh.
--
-- O ARRANJO É O REAL, MEDIDO EM PRODUÇÃO (05/10/2026, só-leitura, caso "Fw Valtra" 03a66ab6, empresa
-- MOTO AGRICOLA VOLKWEIS LTDA). DRE ref 2025: a IA devolveu `secao_canonica` nula em 136 de 724 linhas, e a seção
-- BRUTA dessas linhas era "VENDAS DE PRODUTOS, MERCADORIAS E SERVIÇOS" (34) e "(-) DEDUÇÕES" (94). Efeito medido:
-- receita bruta 2025 do realizado = 235.650 (só "outras receitas") em vez de ~43,85 mi. A DRE 2024 do mesmo caso,
-- com a seção rotulada de outro jeito, a IA mapeou. Reproduzido aqui com os números REAIS que o dono anotou:
--     VENDA DE TRATORES VALTRA NOVOS   2025 (Saldo atual) 19.411.699,33   Saldo anterior 19.374.000
--     VENDAS DE PRODUTOS, MERCADORIAS E SERVIÇOS   2025 (Saldo atual) 43.850.157,37
--     RECEITA LÍQUIDA   2025 38.676.650,89 / 2024 41.860.490,85
--     OUTRAS RECEITAS   2025 235.650 (a única linha que a IA classificou: o que o realizado mostrava)
-- OS MARCADOS "arranjo" (a conta de dedução, as linhas ambíguas, os outros tipos de documento) foram escolhidos aqui
-- porque o valor de produção não foi anotado: afirmam só a SEÇÃO e a MARCA, nunca o número como se fosse do
-- cliente (regra 4). O arranjo NÃO reproduz as outras ~600 linhas da DRE real (a hierarquia de total e componentes):
-- por isso o teste afirma que a linha de venda ENTRA em receita_bruta com o valor real, e não a soma da receita.
--
-- O QUE TRAVA, em COMPORTAMENTO (regra 3):
--   1. fn_secao_canonica_da_secao_bruta mapeia o INEQUÍVOCO (os dois textos do Fw Valtra e os da distribuição de
--      produção) e devolve NULL no ambíguo, no total/topo, no texto que só CONTÉM a palavra e no tipo de
--      documento fora das cinco demonstrações.
--   2. A linha que a IA não classificou volta a existir em receita_bruta no realizado, na série por ano e na
--      lista da modelagem, com o valor real do Fw Valtra — e a linha diz que foi INFERIDA.
--   3. O que a IA deu NUNCA é sobrescrito (nem quando a seção bruta diria outra coisa), e marca false.
--   4. O ambíguo fica NULL e marca false; a seção bruta nula fica NULL.
--   5. O backfill alcança só o que reconhece, ignora linha revisada/transcrita por humano, e é idempotente.
--
-- NÃO PARA NO PRIMEIRO ERRO: anota e segue, e o bloco final reprova com a CONTAGEM (regra 2).
--
-- MEDIÇÃO (regra 2): 71 asserts. Com a correção desligada (fn_secao_canonica_da_secao_bruta sempre NULL) reprovam 38; só a gravação sem
-- inferir, 12; só o backfill desligado, 3; a IA sobrescrita (infere mesmo com secao_canonica dada), 3; o backfill sem o
-- filtro de revisão humana, 2; o backfill sem a marca secao_canonica_inferida, 1; a função sem a âncora de início da
-- receita, 1; "TOTAL DO ATIVO" mapeado, 3. Os 12 e os 3 do backfill são disjuntos de propósito: a extração nova e a linha
-- já gravada são dois caminhos, e desligar um não pode passar pelo outro.

begin;

create temp sequence _falhas_0203;

create or replace function pg_temp.teste_assert_0203(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  else
    raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
    perform nextval('pg_temp._falhas_0203');
  end if;
end $$;

-- A seção inferida de um texto de seção bruta num tipo de documento (NULL = não reconhece).
create or replace function pg_temp.s0203(p_secao text, p_tipo text) returns text
language sql as $$ select fn_secao_canonica_da_secao_bruta(p_secao, p_tipo) $$;

-- O valor de uma célula do realizado em receita_bruta.
create or replace function pg_temp.rb0203(p_caso uuid, p_rotulo text, p_ano int) returns numeric
language sql as $$
  select valor from fn_linhas_do_realizado(p_caso, 'MOTO AGRICOLA VOLKWEIS LTDA')
   where rotulo_norm = fn_normalizar_texto(p_rotulo) and exercicio = p_ano and secao_canonica = 'receita_bruta'
$$;

do $$
declare
  v_caso uuid; v_r jsonb; v_ver25 uuid; v_ver24 uuid; v_ver_b uuid; v_ver_f uuid;
  v_n int; v_num numeric; v_txt text; v_bool boolean;
  c constant text := 'MOTO AGRICOLA VOLKWEIS LTDA';
begin
  raise notice '--- 1. a função pura: o inequívoco mapeia ---';
  -- os dois textos do Fw Valtra
  perform pg_temp.teste_assert_0203(pg_temp.s0203('VENDAS DE PRODUTOS, MERCADORIAS E SERVIÇOS', 'DRE') = 'receita_bruta', 'Fw Valtra: "VENDAS DE PRODUTOS, MERCADORIAS E SERVIÇOS" (DRE) -> receita_bruta');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('(-) DEDUÇÕES', 'DRE') = 'receita_bruta', 'Fw Valtra: "(-) DEDUÇÕES" (DRE) -> receita_bruta (o marcador de sinal não atrapalha)');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('RECEITA BRUTA', 'DRE') = 'receita_bruta', '"RECEITA BRUTA" (DRE) -> receita_bruta');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('CUSTOS', 'DRE') = 'custos', '"CUSTOS" (DRE) -> custos');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('Custo dos Produtos Vendidos', 'DRE') = 'custos', '"Custo dos Produtos Vendidos" -> custos');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('DESPESAS OPERACIONAIS', 'DRE') = 'despesas_operacionais', '"DESPESAS OPERACIONAIS" (DRE) -> despesas_operacionais');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('DESPESAS GERAIS', 'BALANCETE') = 'despesas_operacionais', '"DESPESAS GERAIS" (BALANCETE) -> despesas_operacionais');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('DESPESAS COM PESSOAL', 'BALANCETE') = 'despesas_operacionais', '"DESPESAS COM PESSOAL" (BALANCETE) -> despesas_operacionais');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('Receitas Financeiras', 'DRE') = 'resultado_financeiro', '"Receitas Financeiras" -> resultado_financeiro');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('IRPJ e CSLL', 'DRE') = 'impostos_lucro', '"IRPJ e CSLL" (DRE) -> impostos_lucro');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('ATIVO CIRCULANTE', 'BALANCO') = 'ativo_circulante', '"ATIVO CIRCULANTE" -> ativo_circulante');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('1.1 - Ativo Circulante', 'BALANCO') = 'ativo_circulante', 'a numeração do cabeçalho ("1.1 - ") não atrapalha');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('DISPONIVEL', 'BALANCO') = 'ativo_circulante', '"DISPONIVEL" -> ativo_circulante');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('DISPONÍVEL', 'BALANCETE') = 'ativo_circulante', '"DISPONÍVEL" (BALANCETE) -> ativo_circulante');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('BANCOS CONTA MOVIMENTO', 'BALANCO') = 'ativo_circulante', '"BANCOS CONTA MOVIMENTO" -> ativo_circulante');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('APLICAÇÕES FINANCEIRAS', 'BALANCO') = 'ativo_circulante', '"APLICAÇÕES FINANCEIRAS" -> ativo_circulante');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('ATIVO NÃO CIRCULANTE', 'BALANCO') = 'ativo_nao_circulante', '"ATIVO NÃO CIRCULANTE" -> ativo_nao_circulante');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('Realizável a Longo Prazo', 'BALANCO') = 'ativo_nao_circulante', '"Realizável a Longo Prazo" -> ativo_nao_circulante');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('PASSIVO CIRCULANTE', 'BALANCO') = 'passivo_circulante', '"PASSIVO CIRCULANTE" -> passivo_circulante');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('CONTAS A PAGAR', 'BALANCETE') = 'passivo_circulante', '"CONTAS A PAGAR" -> passivo_circulante');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('OBRIGAÇÕES COM O PESSOAL', 'BALANCETE') = 'passivo_circulante', '"OBRIGAÇÕES COM O PESSOAL" -> passivo_circulante');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('EMPRÉSTIMOS E FINANCIAMENTOS - CURTO PRAZO', 'BALANCO') = 'passivo_circulante', '"EMPRÉSTIMOS E FINANCIAMENTOS - CURTO PRAZO" -> passivo_circulante');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('EMPRÉSTIMOS E FINANCIAMENTOS - LONGO PRAZO', 'BALANCO') = 'passivo_nao_circulante', '"EMPRÉSTIMOS E FINANCIAMENTOS - LONGO PRAZO" -> passivo_nao_circulante');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('PASSIVO NÃO CIRCULANTE', 'BALANCO') = 'passivo_nao_circulante', '"PASSIVO NÃO CIRCULANTE" -> passivo_nao_circulante');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('PATRIMÔNIO LÍQUIDO', 'BALANCO') = 'patrimonio_liquido', '"PATRIMÔNIO LÍQUIDO" -> patrimonio_liquido');

  raise notice '--- 2. a função pura: o ambíguo, o total e o topo ficam NULL ---';
  perform pg_temp.teste_assert_0203(pg_temp.s0203('ATIVO', 'BALANCO') is null, '"ATIVO" sozinho -> NULL (é o topo, não uma seção)');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('PASSIVO', 'BALANCO') is null, '"PASSIVO" sozinho -> NULL');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('TOTAL DO ATIVO', 'BALANCO') is null, '"TOTAL DO ATIVO" -> NULL (subtotal não vira conta de seção)');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO', 'BALANCO') is null, '"TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO" -> NULL');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('PASSIVO E PATRIMÔNIO LÍQUIDO', 'BALANCO') is null, '"PASSIVO E PATRIMÔNIO LÍQUIDO" -> NULL (contém "patrimônio líquido" e não é)');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('TOTAL', 'DRE') is null, '"TOTAL" -> NULL');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('Totais', 'BALANCETE') is null, '"Totais" -> NULL');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('LUCRO BRUTO', 'DRE') is null, '"LUCRO BRUTO" -> NULL (atravessa receita e custo)');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('RESULTADO DO EXERCÍCIO', 'DRE') is null, '"RESULTADO DO EXERCÍCIO" -> NULL');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('RESULTADO ANTES DOS TRIBUTOS SOBRE O LUCRO', 'DRE') is null, '"RESULTADO ANTES DOS TRIBUTOS SOBRE O LUCRO" -> NULL (contém "tributos sobre o lucro" e é subtotal)');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('RECEITA LÍQUIDA', 'DRE') is null, '"RECEITA LÍQUIDA" -> NULL (subtotal depois das deduções)');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('Eliminações do combinado', 'COMBINADO') is null, '"Eliminações do combinado" -> NULL');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('Balancete Analítico', 'BALANCETE') is null, '"Balancete Analítico" -> NULL');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('RESUMO DO BALANCETE', 'BALANCETE') is null, '"RESUMO DO BALANCETE" -> NULL');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('CIRCULANTE', 'BALANCO') is null, '"CIRCULANTE" sem lado -> NULL');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('PROVISÕES', 'BALANCETE') is null, '"PROVISÕES" -> NULL');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('EMPRÉSTIMOS E FINANCIAMENTOS', 'BALANCETE') is null, '"EMPRÉSTIMOS E FINANCIAMENTOS" sem prazo -> NULL');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('NAO_CLASSIFICAVEL', 'BALANCO') is null, '"NAO_CLASSIFICAVEL" -> NULL');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('CONTAS DE RESULTADO - RECEITAS', 'BALANCETE') is null, '"CONTAS DE RESULTADO - RECEITAS" -> NULL (mistura receita financeira)');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('DESPESAS ANTECIPADAS', 'BALANCETE') is null, '"DESPESAS ANTECIPADAS" (ativo) -> NULL: conter "despesas" não basta');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('RECEITAS DIFERIDAS', 'BALANCO') is null, '"RECEITAS DIFERIDAS" (passivo) -> NULL');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('(-) DEDUÇÕES', 'BALANCO') is null, '"(-) DEDUÇÕES" num BALANCO -> NULL: dedução só é receita na DRE');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('ATIVO CIRCULANTE', 'DRE') is null, '"ATIVO CIRCULANTE" numa DRE -> NULL: seção patrimonial só nos tipos patrimoniais');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('RECEITA BRUTA', 'FATURAMENTO_24M') is null, 'tipo fora das cinco demonstrações (FATURAMENTO_24M) -> NULL');
  perform pg_temp.teste_assert_0203(pg_temp.s0203('PATRIMÔNIO LÍQUIDO', 'DMPL') is null, 'tipo DMPL -> NULL (a DMPL tem o próprio valor, "dmpl")');
  perform pg_temp.teste_assert_0203(pg_temp.s0203(null, 'DRE') is null and pg_temp.s0203('RECEITA BRUTA', null) is null, 'seção nula ou tipo nulo -> NULL');

  raise notice '--- 3. o arranjo do Fw Valtra: a linha que a IA não classificou volta ao realizado ---';
  v_caso := (fn_upsert_caso('0203: Fw Valtra, DRE sem seção'))::uuid;

  -- DRE ref 2025. A IA classificou SÓ "OUTRAS RECEITAS"; as demais vieram com secao_canonica nula e a seção bruta.
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2025', 'DRE', 0.97,
    'nome_arquivo', 'supabase_storage', '0203/dre2025.pdf', 'dre_2025.pdf', true, 'HASH-0203-1', 'ok');
  v_ver25 := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver25, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','OUTRAS RECEITAS','secao','OUTRAS RECEITAS OPERACIONAIS','secao_canonica','receita_bruta','periodo_coluna','Saldo atual','valor_num','235650','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',1,'chave','VENDAS DE PRODUTOS, MERCADORIAS E SERVIÇOS','secao','VENDAS DE PRODUTOS, MERCADORIAS E SERVIÇOS','periodo_coluna','Saldo atual','valor_num','43850157.37','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',2,'chave','VENDA DE TRATORES VALTRA NOVOS','secao','VENDAS DE PRODUTOS, MERCADORIAS E SERVIÇOS','periodo_coluna','Saldo anterior','valor_num','19374000','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',2,'chave','VENDA DE TRATORES VALTRA NOVOS','secao','VENDAS DE PRODUTOS, MERCADORIAS E SERVIÇOS','periodo_coluna','Saldo atual','valor_num','19411699.33','confianca','0.97','origem_pagina','1'),
    -- arranjo: uma conta de dedução (o valor de produção não foi anotado)
    jsonb_build_object('ordem',3,'chave','ICMS SOBRE VENDAS','secao','(-) DEDUÇÕES','periodo_coluna','Saldo atual','valor_num','-5000000','confianca','0.97','origem_pagina','1'),
    -- a RECEITA LÍQUIDA real, sob um cabeçalho ambíguo: fica sem seção (e a IA calou)
    jsonb_build_object('ordem',4,'chave','RECEITA LIQUIDA','secao','RECEITA LÍQUIDA','periodo_coluna','Saldo atual','valor_num','38676650.89','confianca','0.97','origem_pagina','1'),
    -- arranjo: outros ambíguos que a IA deixou sem seção
    jsonb_build_object('ordem',5,'chave','LUCRO BRUTO','secao','LUCRO BRUTO','periodo_coluna','Saldo atual','valor_num','7000000','confianca','0.97','origem_pagina','1'),
    jsonb_build_object('ordem',6,'chave','RESULTADO DO EXERCICIO','secao','RESULTADO DO EXERCÍCIO','periodo_coluna','Saldo atual','valor_num','1200000','confianca','0.97','origem_pagina','1'),
    -- arranjo: sem seção bruta nenhuma
    jsonb_build_object('ordem',7,'chave','LINHA SOLTA','periodo_coluna','Saldo atual','valor_num','111','confianca','0.97','origem_pagina','1'),
    -- arranjo: a IA deu 'custos' e a seção bruta diria receita_bruta: o que a IA deu NUNCA é sobrescrito
    jsonb_build_object('ordem',8,'chave','LINHA CLASSIFICADA PELA IA','secao','RECEITA BRUTA','secao_canonica','custos','periodo_coluna','Saldo atual','valor_num','222','confianca','0.97','origem_pagina','1'),
    -- arranjo: seção canônica EM BRANCO conta como "a IA não deu"
    jsonb_build_object('ordem',9,'chave','LINHA COM SECAO EM BRANCO','secao','CUSTOS','secao_canonica','  ','periodo_coluna','Saldo atual','valor_num','-333','confianca','0.97','origem_pagina','1')
  ), 'N2');

  -- DRE ref 2024: a IA classificou tudo (seção rotulada de outro jeito). Valores reais da receita líquida.
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2024', 'DRE', 0.97,
    'nome_arquivo', 'supabase_storage', '0203/dre2024.pdf', 'dre_2024.pdf', true, 'HASH-0203-2', 'ok');
  v_ver24 := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver24, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','RECEITA LIQUIDA','secao','RECEITA OPERACIONAL LÍQUIDA','secao_canonica','receita_bruta','periodo_coluna','Saldo atual','valor_num','41860490.85','confianca','0.97','origem_pagina','1')
  ), 'N2');

  select valor into v_num from fn_linhas_do_realizado(v_caso, c)
   where rotulo_norm = 'vendas de produtos, mercadorias e servicos' and exercicio = 2025 and secao_canonica = 'receita_bruta';
  perform pg_temp.teste_assert_0203(v_num = 43850157.37, 'o realizado traz "VENDAS DE PRODUTOS, MERCADORIAS E SERVIÇOS" 2025 em receita_bruta = 43.850.157,37', format('%s', v_num));
  v_num := pg_temp.rb0203(v_caso, 'VENDA DE TRATORES VALTRA NOVOS', 2025);
  perform pg_temp.teste_assert_0203(v_num = 19411699.33, '"VENDA DE TRATORES VALTRA NOVOS" 2025 = 19.411.699,33 em receita_bruta', format('%s', v_num));
  v_num := pg_temp.rb0203(v_caso, 'VENDA DE TRATORES VALTRA NOVOS', 2024);
  perform pg_temp.teste_assert_0203(v_num = 19374000, '"VENDA DE TRATORES VALTRA NOVOS" 2024 = 19.374.000 (o Saldo anterior)', format('%s', v_num));
  v_num := pg_temp.rb0203(v_caso, 'ICMS SOBRE VENDAS', 2025);
  perform pg_temp.teste_assert_0203(v_num = -5000000, 'a conta sob "(-) DEDUÇÕES" também entra em receita_bruta (a família da dedução mora na seção)', format('%s', v_num));
  select coalesce(sum(valor), 0) into v_num from fn_linhas_do_realizado(v_caso, c)
   where secao_canonica = 'receita_bruta' and exercicio = 2025 and papel = 'conta' and valor > 0;
  perform pg_temp.teste_assert_0203(v_num > 235650 and v_num >= 43850157.37,
    'a receita bruta 2025 do realizado deixa de ser SÓ "outras receitas" (235.650)', format('%s', v_num));
  select count(*) into v_n from fn_linhas_do_realizado(v_caso, c)
   where exercicio = 2025 and secao_canonica is null and rotulo_norm like 'venda%';
  perform pg_temp.teste_assert_0203(v_n = 0, 'nenhuma linha de venda sobra no grupo sem seção do realizado 2025', format('%s linhas', v_n));
  select valor into v_num from fn_valores_por_ano(v_caso, c)
   where rotulo_norm = 'vendas de produtos, mercadorias e servicos' and ano = 2025 and secao_canonica = 'receita_bruta';
  perform pg_temp.teste_assert_0203(v_num = 43850157.37, 'a série por ano (fn_valores_por_ano) vê a mesma célula: receita_bruta 2025 = 43.850.157,37', format('%s', v_num));
  select count(*) into v_n from fn_linhas_para_modelagem(v_caso)
   where rotulo_norm = 'vendas de produtos, mercadorias e servicos' and secao_canonica = 'receita_bruta';
  perform pg_temp.teste_assert_0203(v_n = 1, 'a lista da modelagem mostra a linha de venda sob receita_bruta, não no grupo sem seção', format('%s linhas', v_n));

  raise notice '--- 4. a linha diz que foi inferida; o que a IA deu nunca é sobrescrito ---';
  select count(*) into v_n from campo_extraido
   where documento_versao_id = v_ver25 and secao_canonica_inferida and secao_canonica is not null;
  perform pg_temp.teste_assert_0203(v_n = 5, '5 linhas da DRE 2025 gravam secao_canonica_inferida = true (vendas, 2 de trator, dedução e a de seção em branco)', format('%s linhas', v_n));
  select secao_canonica || '/' || secao_canonica_inferida::text into v_txt from campo_extraido
   where documento_versao_id = v_ver25 and chave = 'LINHA CLASSIFICADA PELA IA';
  perform pg_temp.teste_assert_0203(v_txt = 'custos/false', 'o que a IA deu NUNCA é sobrescrito: "custos" fica, mesmo com a seção bruta "RECEITA BRUTA"; marca false', v_txt);
  select secao_canonica || '/' || secao_canonica_inferida::text into v_txt from campo_extraido
   where documento_versao_id = v_ver25 and chave = 'OUTRAS RECEITAS';
  perform pg_temp.teste_assert_0203(v_txt = 'receita_bruta/false', 'a linha que a IA classificou ("OUTRAS RECEITAS") marca false', v_txt);
  select secao_canonica || '/' || secao_canonica_inferida::text into v_txt from campo_extraido
   where documento_versao_id = v_ver25 and chave = 'LINHA COM SECAO EM BRANCO';
  perform pg_temp.teste_assert_0203(v_txt = 'custos/true', 'secao_canonica em BRANCO conta como "a IA não deu": inferida de "CUSTOS"', v_txt);
  select count(*) into v_n from campo_extraido
   where documento_versao_id = v_ver25 and chave in ('RECEITA LIQUIDA', 'LUCRO BRUTO', 'RESULTADO DO EXERCICIO', 'LINHA SOLTA')
     and secao_canonica is null and not secao_canonica_inferida;
  perform pg_temp.teste_assert_0203(v_n = 4, 'o ambíguo (RECEITA LÍQUIDA, LUCRO BRUTO, RESULTADO) e a linha sem seção bruta ficam NULL e marcam false', format('%s de 4', v_n));
  select count(*) into v_n from campo_extraido
   where documento_versao_id = v_ver24 and secao_canonica_inferida;
  perform pg_temp.teste_assert_0203(v_n = 0, 'a DRE 2024, que a IA classificou inteira, não tem linha inferida', format('%s linhas', v_n));

  raise notice '--- 5. fora das cinco demonstrações a gravação não opina ---';
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2025', 'FATURAMENTO_24M', 0.97,
    'nome_arquivo', 'supabase_storage', '0203/fat.pdf', 'fat.pdf', true, 'HASH-0203-3', 'ok');
  v_ver_f := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver_f, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Faturamento Janeiro','secao','RECEITA BRUTA','valor_num','15493','confianca','0.97')
  ), 'N2');
  select count(*) into v_n from campo_extraido where documento_versao_id = v_ver_f and secao_canonica is null and not secao_canonica_inferida;
  perform pg_temp.teste_assert_0203(v_n = 1, 'FATURAMENTO_24M com seção bruta "RECEITA BRUTA" segue sem seção canônica (o mapa de faturamento é série mensal)', format('%s', v_n));

  raise notice '--- 6. o backfill: a mesma conta, só o que reconhece, sem revisão humana, idempotente ---';
  -- Linhas "de antes da 0203": inseridas direto, sem passar pela gravação nova, com secao_canonica nula.
  v_r := fn_registrar_documento(v_caso, 'BALANCO LTDA', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0203/bp.pdf', 'bp.pdf', true, 'HASH-0203-4', 'ok');
  v_ver_b := (v_r->>'documento_versao_id')::uuid;
  insert into campo_extraido (documento_versao_id, chave, valor_num, secao, periodo_coluna, confianca) values
    (v_ver_b, 'CAIXA',          100, 'ATIVO CIRCULANTE',  'Saldo Final', 0.97),
    (v_ver_b, 'FORNECEDORES',   200, 'PASSIVO CIRCULANTE','Saldo Final', 0.97),
    (v_ver_b, 'TOTAL DO ATIVO', 300, 'TOTAL DO ATIVO',    'Saldo Final', 0.97),
    (v_ver_b, 'SEM SECAO',      400, null,                'Saldo Final', 0.97);
  -- revisada por pessoa: a triagem humana existe e a regra de texto não a desfaz
  insert into campo_extraido (documento_versao_id, chave, valor_num, secao, periodo_coluna, confianca, revisado_por) values
    (v_ver_b, 'REVISADA',       500, 'ATIVO CIRCULANTE',  'Saldo Final', 0.97, 'analista@oria');
  -- transcrita por pessoa
  insert into campo_extraido (documento_versao_id, chave, valor_num, secao, periodo_coluna, confianca, origem_valor) values
    (v_ver_b, 'TRANSCRITA',     600, 'ATIVO CIRCULANTE',  'Saldo Final', null, 'transcricao_humana');

  v_r := fn_inferir_secao_canonica_das_linhas(v_caso);
  perform pg_temp.teste_assert_0203((v_r->>'linhas')::int = 2, 'o backfill alcança as 2 linhas reconhecíveis do caso (CAIXA e FORNECEDORES)', v_r::text);
  perform pg_temp.teste_assert_0203((v_r->>'versoes')::int = 1 and (v_r->>'casos')::int = 1, 'e diz em quantas versões e casos', v_r::text);
  select string_agg(chave || '=' || coalesce(secao_canonica, 'NULL') || '/' || secao_canonica_inferida::text, ', ' order by chave) into v_txt
    from campo_extraido where documento_versao_id = v_ver_b;
  perform pg_temp.teste_assert_0203(v_txt = 'CAIXA=ativo_circulante/true, FORNECEDORES=passivo_circulante/true, REVISADA=NULL/false, SEM SECAO=NULL/false, TOTAL DO ATIVO=NULL/false, TRANSCRITA=NULL/false',
    'CAIXA e FORNECEDORES inferidas e marcadas; o total, a sem-seção, a revisada e a transcrita ficam como estavam', v_txt);
  v_r := fn_inferir_secao_canonica_das_linhas(v_caso);
  perform pg_temp.teste_assert_0203((v_r->>'linhas')::int = 0, 'idempotente: a segunda rodada não alcança linha nenhuma', v_r::text);
  v_r := fn_inferir_secao_canonica_das_linhas(gen_random_uuid());
  perform pg_temp.teste_assert_0203((v_r->>'linhas')::int = 0, 'caso sem linhas: zero, sem erro', v_r::text);
end $$;

do $$
declare
  v_n int;
begin
  select case when is_called then last_value else 0 end into v_n from pg_temp._falhas_0203;
  if v_n > 0 then
    raise exception 'FALHOU: % assert(s) da 0203 reprovaram — ver as linhas FALHOU acima', v_n;
  end if;
  raise notice 'TODOS OS TESTES DA 0203 (seção inferida da seção bruta) PASSARAM';
end $$;

rollback;
