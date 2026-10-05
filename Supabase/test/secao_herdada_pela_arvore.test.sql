-- Testes da 0204 (Supabase/migrations/0204_a_secao_que_o_documento_ja_dizia_pela_arvore.sql).
-- Rodar via Supabase/test/run.sh.
--
-- O ARRANJO É O REAL, MEDIDO EM PRODUÇÃO (05/10/2026, só-leitura, depois da 0203; caso "Fw Valtra" 03a66ab6, empresa
-- MOTO AGRICOLA VOLKWEIS LTDA, BALANCO ref 2025, coluna "Saldo Final"). Linhas que a IA deixou sem secao_canonica e que a
-- 0203 não alcança (a seção bruta é um nome de conta, não um cabeçalho): com os VALORES REAIS
--     CAIXA MATRIZ 95.747,82 (seção "CAIXA") · DUPLICATAS A RECEBER 4.292.868,90 (seção "CLIENTES") ·
--     DUPLICATAS A RECEBER OUTROS 3.166.371,69 e ... FILIAL 01 1.126.497,21 (seção "DUPLICATAS A RECEBER") ·
--     sob "OUTROS CRÉDITOS": TITULOS E VALORES IMOBILIÁRIOS 55.000 · FUNDOS DE INVESTIMENTOS 114.429,85 ·
--     ADIANTAMENTOS A FORNECEDORES 439.229,17 · ADIANTAMENTO A EMPREGADOS 4.950 · CRÉDITOS A RECEBER 0 ·
--     TRIBUTOS A RECUPERAR/COMPENSAR 409.958,77 · netos: OUROCAP PU 5.000 (sob TITULOS E VALORES IMOBILIÁRIOS),
--     ICMS A RECUPERAR 186.110,09 (sob TRIBUTOS A RECUPERAR/COMPENSAR).
-- e, no MESMO documento, a linha "CLIENTES" (4.292.868,90, real) com seção ativo_circulante.
-- OS MARCADOS "arranjo" foram escolhidos aqui porque o valor/rótulo de produção não foi anotado (a linha-pai CAIXA, as
-- duas irmãs classificadas de "OUTROS CRÉDITOS" — em produção são 32 —, todos os controles): afirmam só a SEÇÃO e a
-- MARCA, nunca o número como se fosse do cliente (regra 4). Não reproduz as ~150 linhas do balanço real.
--
-- O QUE TRAVA, em COMPORTAMENTO (regra 3):
--   1. A linha sem seção cuja seção bruta é a CHAVE de outra linha do mesmo documento com seção (o pai) herda — e o neto
--      herda do filho que herdou (CLIENTES -> DUPLICATAS A RECEBER -> DUPLICATAS A RECEBER OUTROS), pela gravação.
--   2. A que está sob uma seção bruta que outras linhas já têm classificada, e todas concordam (as irmãs), herda.
--   3. As linhas herdadas voltam ao realizado em ativo_circulante com o valor real, na série por ano e na modelagem.
--   4. Conflito (duas seções para o mesmo nome — irmãs que discordam; pai e irmã que discordam) fica NULL, e a função
--      DIZ quantos ficaram assim.
--   5. Topo e total ("ATIVO", "TOTAL DO ATIVO CIRCULANTE") nunca viram pai nem irmã, mesmo com seção dada pela IA.
--   6. Ciclo não trava: sem âncora ninguém herda; com âncora herdam os dois, e termina. Profundidade tem teto.
--   7. O que a IA deu nunca é alterado nem marcado; linha revisada/transcrita por pessoa não é alvo (mas serve de pai).
--   8. Outra versão de documento, e tipo fora das demonstrações, não vazam nem recebem.
--   9. O backfill é a mesma conta, só sobre o caso pedido, e idempotente.
--
-- NÃO PARA NO PRIMEIRO ERRO: anota e segue, e o bloco final reprova com a CONTAGEM (regra 2).
--
-- MEDIÇÃO (regra 2): 37 asserts. Com a correção desligada (fn_herdar_secao_pela_arvore devolvendo zero) reprovam 21; só a gravação sem chamar a herança,
-- 15; sem o PAI (chave), 19; sem as IRMÃS (seção bruta), 12; sem recursão (1 rodada), 13; sem o teto de 10 rodadas, 2; topo/total
-- como pai, 5; conflito resolvido no min() em vez de NULL, 5; conflito não declarado, 2; linha revisada/transcrita como alvo, 2;
-- herança vazando entre versões, 4; sem restringir aos cinco tipos, 2; sem a marca secao_canonica_inferida, 10; sem tirar o código
-- contábil do ERP, 3; sobrescrevendo o que a IA deu, 9. Cada mutação foi aplicada sobre o banco com a migration e reprovou ISOLADA.

begin;

create temp sequence _falhas_0204;

create or replace function pg_temp.teste_assert_0204(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  else
    raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
    perform nextval('pg_temp._falhas_0204');
  end if;
end $$;

-- Uma linha do Saldo Final no formato que a extração entrega (canon nula/ausente = a IA calou).
create or replace function pg_temp.r0204(p_ordem int, p_chave text, p_secao text, p_canon text, p_valor numeric)
returns jsonb language sql as $$
  select jsonb_strip_nulls(jsonb_build_object('ordem', p_ordem, 'chave', p_chave, 'secao', p_secao,
    'secao_canonica', p_canon, 'periodo_coluna', 'Saldo Final', 'valor_num', p_valor::text,
    'confianca', '0.97', 'origem_pagina', '2'))
$$;

-- "secao_canonica/inferida" de uma linha, por versão e chave.
create or replace function pg_temp.s0204(p_ver uuid, p_chave text) returns text
language sql as $$
  select coalesce(secao_canonica, 'NULL') || '/' || secao_canonica_inferida::text
    from campo_extraido where documento_versao_id = p_ver and chave = p_chave
$$;

create or replace function pg_temp.rl0204(p_caso uuid, p_rotulo text, p_ano int) returns numeric
language sql as $$
  select valor from fn_linhas_do_realizado(p_caso, 'MOTO AGRICOLA VOLKWEIS LTDA')
   where rotulo_norm = fn_normalizar_texto(p_rotulo) and exercicio = p_ano and secao_canonica = 'ativo_circulante'
$$;

do $$
declare
  v_caso uuid; v_r jsonb; v_ver uuid; v_verb uuid; v_verc uuid; v_verf uuid; v_n int; v_num numeric; v_txt text;
  i int;
  c constant text := 'MOTO AGRICOLA VOLKWEIS LTDA';
begin
  raise notice '--- 1. as peças puras: o nome e o que é topo/total ---';
  perform pg_temp.teste_assert_0204(fn_nome_de_secao_normalizado('  (-) 1.1 - Títulos e Valores Imobiliários: ') = 'titulos e valores imobiliarios',
    'o nome normalizado tira acento, marcador de sinal, numeração e pontuação final');
  perform pg_temp.teste_assert_0204(fn_nome_de_secao_normalizado('1.1.02 CLIENTES') = 'clientes', 'e o código contábil do ERP (a 0202 já sabe tirá-lo)');
  perform pg_temp.teste_assert_0204(fn_nome_de_secao_normalizado('   ') is null and fn_nome_de_secao_normalizado(null) is null, 'vazio ou nulo -> NULL');
  perform pg_temp.teste_assert_0204(fn_nome_de_topo_ou_total('ativo') and fn_nome_de_topo_ou_total('passivo e patrimonio liquido')
    and fn_nome_de_topo_ou_total('total do ativo circulante') and fn_nome_de_topo_ou_total('balancete analitico') and fn_nome_de_topo_ou_total('totais'),
    'ATIVO, PASSIVO E PATRIMÔNIO LÍQUIDO, TOTAL DO ATIVO CIRCULANTE, Balancete Analítico, Totais são topo/total');
  perform pg_temp.teste_assert_0204(not fn_nome_de_topo_ou_total('clientes') and not fn_nome_de_topo_ou_total('ativo circulante')
    and not fn_nome_de_topo_ou_total('outros creditos') and not fn_nome_de_topo_ou_total('patrimonio liquido'),
    'CLIENTES, ATIVO CIRCULANTE, OUTROS CRÉDITOS, PATRIMÔNIO LÍQUIDO são nomes de seção, não topo');

  raise notice '--- 2. o arranjo do Fw Valtra, pela GRAVAÇÃO (fn_registrar_campos_extraidos) ---';
  v_caso := (fn_upsert_caso('0204: Fw Valtra, balanço sem seção'))::uuid;
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0204/bp2025.pdf', 'balanco_2025.pdf', true, 'HASH-0204-1', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    -- as âncoras que a IA classificou
    pg_temp.r0204(0,  'CLIENTES',                    'ATIVO CIRCULANTE', 'ativo_circulante', 4292868.90),            -- real
    pg_temp.r0204(1,  'CAIXA',                       'ATIVO CIRCULANTE', 'ativo_circulante', 95747.82),              -- arranjo: o pai CAIXA
    pg_temp.r0204(2,  'ADIANTAMENTO DE VIAGENS',     'OUTROS CRÉDITOS',  'ativo_circulante', 1000),                  -- arranjo: irmã classificada
    pg_temp.r0204(3,  'DEPOSITOS JUDICIAIS',         'OUTROS CRÉDITOS',  'ativo_circulante', 2000),                  -- arranjo: irmã classificada
    -- o que a IA calou (VALORES REAIS)
    pg_temp.r0204(10, 'CAIXA MATRIZ',                'CAIXA',            null, 95747.82),
    pg_temp.r0204(11, 'DUPLICATAS A RECEBER',        'CLIENTES',         null, 4292868.90),
    pg_temp.r0204(12, 'DUPLICATAS A RECEBER OUTROS', 'DUPLICATAS A RECEBER', null, 3166371.69),
    pg_temp.r0204(13, 'DUPLICATAS A RECEBER FILIAL 01', 'DUPLICATAS A RECEBER', null, 1126497.21),
    pg_temp.r0204(14, 'TÍTULOS E VALORES IMOBILIÁRIOS', 'OUTROS CRÉDITOS', null, 55000),
    pg_temp.r0204(15, 'FUNDOS DE INVESTIMENTOS',     'OUTROS CRÉDITOS',  null, 114429.85),
    pg_temp.r0204(16, 'ADIANTAMENTOS A FORNECEDORES','OUTROS CRÉDITOS',  null, 439229.17),
    pg_temp.r0204(17, 'ADIANTAMENTO A EMPREGADOS',   'OUTROS CRÉDITOS',  null, 4950),
    pg_temp.r0204(18, 'CRÉDITOS A RECEBER',          'OUTROS CRÉDITOS',  null, 0),
    pg_temp.r0204(19, 'TRIBUTOS A RECUPERAR/COMPENSAR', 'OUTROS CRÉDITOS', null, 409958.77),
    pg_temp.r0204(20, 'OUROCAP PU',                  'TITULOS E VALORES IMOBILIÁRIOS', null, 5000),                 -- neto
    pg_temp.r0204(21, 'ICMS A RECUPERAR',            'TRIBUTOS A RECUPERAR/COMPENSAR', null, 186110.09),            -- neto
    -- controle: conflito entre irmãs (uma diz circulante, outra passivo) — a filha fica NULL
    pg_temp.r0204(30, 'IRMA ATIVA',                  'OUTROS VALORES',   'ativo_circulante',  10),
    pg_temp.r0204(31, 'IRMA PASSIVA',                'OUTROS VALORES',   'passivo_circulante', 20),
    pg_temp.r0204(32, 'LINHA EM CONFLITO',           'OUTROS VALORES',   null, 30),
    -- controle: o PAI diz circulante e uma irmã diz passivo — a filha fica NULL
    pg_temp.r0204(33, 'ADIANTAMENTOS',               'ATIVO CIRCULANTE', 'ativo_circulante', 40),
    pg_temp.r0204(34, 'IRMA QUE DISCORDA DO PAI',    'ADIANTAMENTOS',    'passivo_circulante', 50),
    pg_temp.r0204(35, 'FILHA DO PAI QUE DISCORDA',   'ADIANTAMENTOS',    null, 60),
    -- controle: topo e total NUNCA são pai nem irmã, mesmo com seção dada pela IA
    pg_temp.r0204(40, 'ATIVO',                       'BALANCO PATRIMONIAL', 'ativo_circulante', 70),
    pg_temp.r0204(41, 'ATIVO RESIDUAL',              'ATIVO',            null, 80),
    pg_temp.r0204(42, 'TOTAL DO ATIVO CIRCULANTE',   'ATIVO CIRCULANTE', 'ativo_circulante', 90),
    pg_temp.r0204(43, 'SOBRA DO TOTAL',              'TOTAL DO ATIVO CIRCULANTE', null, 100),
    pg_temp.r0204(44, 'IRMA CLASSIFICADA DO TOPO',   'ATIVO',            'ativo_circulante', 110),
    -- controle: ciclo sem âncora (A sob B, B sob A): ninguém herda e termina
    pg_temp.r0204(50, 'CICLO A',                     'CICLO B',          null, 1),
    pg_temp.r0204(51, 'CICLO B',                     'CICLO A',          null, 2),
    -- controle: ciclo COM âncora (a irmã classificada sob CICLO C): herdam os dois e termina
    pg_temp.r0204(52, 'CICLO C',                     'CICLO D',          null, 3),
    pg_temp.r0204(53, 'CICLO D',                     'CICLO C',          null, 4),
    pg_temp.r0204(54, 'ANCORA DO CICLO',             'CICLO C',          'ativo_circulante', 5)
  ), 'N2');

  select count(*) into v_n from campo_extraido where documento_versao_id = v_ver and secao_canonica_inferida;
  perform pg_temp.teste_assert_0204(v_n = 14, '14 linhas herdadas na gravação (12 do arranjo real + 2 do ciclo com âncora)', format('%s linhas', v_n));

  perform pg_temp.teste_assert_0204(pg_temp.s0204(v_ver, 'CAIXA MATRIZ') = 'ativo_circulante/true', 'CAIXA MATRIZ herda do PAI "CAIXA" (95.747,82)', pg_temp.s0204(v_ver, 'CAIXA MATRIZ'));
  perform pg_temp.teste_assert_0204(pg_temp.s0204(v_ver, 'DUPLICATAS A RECEBER') = 'ativo_circulante/true', 'DUPLICATAS A RECEBER herda do pai "CLIENTES" (4.292.868,90)', pg_temp.s0204(v_ver, 'DUPLICATAS A RECEBER'));
  perform pg_temp.teste_assert_0204(pg_temp.s0204(v_ver, 'DUPLICATAS A RECEBER OUTROS') = 'ativo_circulante/true', 'o NETO "DUPLICATAS A RECEBER OUTROS" herda do filho que herdou (3 níveis: CLIENTES -> DUPLICATAS -> OUTROS)', pg_temp.s0204(v_ver, 'DUPLICATAS A RECEBER OUTROS'));
  perform pg_temp.teste_assert_0204(pg_temp.s0204(v_ver, 'DUPLICATAS A RECEBER FILIAL 01') = 'ativo_circulante/true', '"DUPLICATAS A RECEBER FILIAL 01" idem', pg_temp.s0204(v_ver, 'DUPLICATAS A RECEBER FILIAL 01'));
  select count(*) into v_n from campo_extraido
   where documento_versao_id = v_ver and secao = 'OUTROS CRÉDITOS' and secao_canonica = 'ativo_circulante' and secao_canonica_inferida;
  perform pg_temp.teste_assert_0204(v_n = 6, 'as 6 linhas reais de "OUTROS CRÉDITOS" sem seção herdam das irmãs classificadas (que concordam)', format('%s linhas', v_n));
  perform pg_temp.teste_assert_0204(pg_temp.s0204(v_ver, 'OUROCAP PU') = 'ativo_circulante/true', 'o neto "OUROCAP PU" herda de "TÍTULOS E VALORES IMOBILIÁRIOS", que herdou de "OUTROS CRÉDITOS" (acento e caixa não importam)', pg_temp.s0204(v_ver, 'OUROCAP PU'));
  perform pg_temp.teste_assert_0204(pg_temp.s0204(v_ver, 'ICMS A RECUPERAR') = 'ativo_circulante/true', 'o neto "ICMS A RECUPERAR" (186.110,09) herda de "TRIBUTOS A RECUPERAR/COMPENSAR"', pg_temp.s0204(v_ver, 'ICMS A RECUPERAR'));

  raise notice '--- 3. as linhas voltam ao realizado, com o valor real ---';
  perform pg_temp.teste_assert_0204(pg_temp.rl0204(v_caso, 'CAIXA MATRIZ', 2025) = 95747.82, 'o realizado traz CAIXA MATRIZ 2025 em ativo_circulante = 95.747,82', format('%s', pg_temp.rl0204(v_caso, 'CAIXA MATRIZ', 2025)));
  perform pg_temp.teste_assert_0204(pg_temp.rl0204(v_caso, 'DUPLICATAS A RECEBER OUTROS', 2025) = 3166371.69, 'DUPLICATAS A RECEBER OUTROS 2025 = 3.166.371,69', format('%s', pg_temp.rl0204(v_caso, 'DUPLICATAS A RECEBER OUTROS', 2025)));
  perform pg_temp.teste_assert_0204(pg_temp.rl0204(v_caso, 'ICMS A RECUPERAR', 2025) = 186110.09, 'ICMS A RECUPERAR 2025 = 186.110,09', format('%s', pg_temp.rl0204(v_caso, 'ICMS A RECUPERAR', 2025)));
  select count(*) into v_n from fn_linhas_do_realizado(v_caso, c)
   where exercicio = 2025 and secao_canonica is null
     and rotulo_norm in ('caixa matriz', 'duplicatas a receber', 'duplicatas a receber outros', 'fundos de investimentos', 'adiantamentos a fornecedores',
                         'tributos a recuperar/compensar', 'icms a recuperar', 'ourocap pu');
  perform pg_temp.teste_assert_0204(v_n = 0, 'nenhuma das contas reais do AC sobra no grupo sem seção do realizado 2025', format('%s linhas', v_n));
  select valor into v_num from fn_valores_por_ano(v_caso, c)
   where rotulo_norm = 'fundos de investimentos' and ano = 2025 and secao_canonica = 'ativo_circulante';
  perform pg_temp.teste_assert_0204(v_num = 114429.85, 'a série por ano vê a mesma célula: FUNDOS DE INVESTIMENTOS 2025 = 114.429,85 em ativo_circulante', format('%s', v_num));
  select count(*) into v_n from fn_linhas_para_modelagem(v_caso)
   where rotulo_norm = 'adiantamentos a fornecedores' and secao_canonica = 'ativo_circulante';
  perform pg_temp.teste_assert_0204(v_n = 1, 'a lista da modelagem mostra ADIANTAMENTOS A FORNECEDORES sob ativo_circulante', format('%s linhas', v_n));

  raise notice '--- 4. conflito fica NULL, e a função diz ---';
  perform pg_temp.teste_assert_0204(pg_temp.s0204(v_ver, 'LINHA EM CONFLITO') = 'NULL/false', 'irmãs que discordam (circulante x passivo): a filha fica NULL e marca false', pg_temp.s0204(v_ver, 'LINHA EM CONFLITO'));
  perform pg_temp.teste_assert_0204(pg_temp.s0204(v_ver, 'FILHA DO PAI QUE DISCORDA') = 'NULL/false', 'o pai diz circulante e uma irmã diz passivo: a filha fica NULL', pg_temp.s0204(v_ver, 'FILHA DO PAI QUE DISCORDA'));
  v_r := fn_herdar_secao_pela_arvore(v_ver);
  perform pg_temp.teste_assert_0204((v_r->>'conflitos')::int = 2 and (v_r->>'linhas_em_conflito')::int = 2,
    'a função DECLARA os 2 nomes e as 2 linhas que ficaram em conflito (regra 1: o que não resolveu não finge que resolveu)', v_r::text);
  select count(*) into v_n from evento_auditoria
   where acao = 'secao_herdada_pela_arvore' and entidade_ref = 'documento_versao:' || v_ver and (depois->>'linhas')::int = 14 and (depois->>'conflitos')::int = 2;
  perform pg_temp.teste_assert_0204(v_n = 1, 'a gravação deixa o evento de auditoria com 14 linhas herdadas e 2 conflitos', format('%s evento(s)', v_n));

  raise notice '--- 5. topo e total nunca viram pai nem irmã ---';
  perform pg_temp.teste_assert_0204(pg_temp.s0204(v_ver, 'ATIVO RESIDUAL') = 'NULL/false', 'filha de "ATIVO" fica NULL mesmo com chave ATIVO e uma irmã com ativo_circulante dadas pela IA', pg_temp.s0204(v_ver, 'ATIVO RESIDUAL'));
  perform pg_temp.teste_assert_0204(pg_temp.s0204(v_ver, 'SOBRA DO TOTAL') = 'NULL/false', 'filha de "TOTAL DO ATIVO CIRCULANTE" fica NULL (o total com seção dada pela IA não é pai)', pg_temp.s0204(v_ver, 'SOBRA DO TOTAL'));
  perform pg_temp.teste_assert_0204(pg_temp.s0204(v_ver, 'ATIVO') = 'ativo_circulante/false' and pg_temp.s0204(v_ver, 'TOTAL DO ATIVO CIRCULANTE') = 'ativo_circulante/false',
    'e o que a IA deu ao topo e ao total não é tocado nem marcado');

  raise notice '--- 6. ciclo não trava; profundidade tem teto ---';
  perform pg_temp.teste_assert_0204(pg_temp.s0204(v_ver, 'CICLO A') = 'NULL/false' and pg_temp.s0204(v_ver, 'CICLO B') = 'NULL/false',
    'ciclo sem âncora (A sob B, B sob A): ninguém herda, e a gravação terminou', pg_temp.s0204(v_ver, 'CICLO A') || ' ' || pg_temp.s0204(v_ver, 'CICLO B'));
  perform pg_temp.teste_assert_0204(pg_temp.s0204(v_ver, 'CICLO D') = 'ativo_circulante/true' and pg_temp.s0204(v_ver, 'CICLO C') = 'ativo_circulante/true',
    'ciclo COM âncora: os dois herdam (D da irmã classificada, depois C de D) e termina', pg_temp.s0204(v_ver, 'CICLO C') || ' ' || pg_temp.s0204(v_ver, 'CICLO D'));
  -- cadeia de 12 níveis: a âncora é N00; cada Nk está sob o nome N(k-1). O teto é 10 rodadas.
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2021', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0204/bp2021.pdf', 'balanco_2021.pdf', true, 'HASH-0204-5', 'ok');
  v_verf := (v_r->>'documento_versao_id')::uuid;
  insert into campo_extraido (documento_versao_id, chave, valor_num, secao, secao_canonica, periodo_coluna, confianca)
    values (v_verf, 'N00', 1, 'ATIVO CIRCULANTE', 'ativo_circulante', 'Saldo Final', 0.97);
  for i in 1..12 loop
    insert into campo_extraido (documento_versao_id, chave, valor_num, secao, periodo_coluna, confianca)
      values (v_verf, format('N%s', lpad(i::text, 2, '0')), 1, format('N%s', lpad((i - 1)::text, 2, '0')), 'Saldo Final', 0.97);
  end loop;
  v_r := fn_herdar_secao_pela_arvore(v_verf);
  perform pg_temp.teste_assert_0204((v_r->>'linhas')::int = 10 and (v_r->>'rodadas')::int = 10,
    'cadeia de 12 níveis: uma chamada herda 10 (o teto) e para; os 2 últimos ficam para a próxima', v_r::text);
  v_r := fn_herdar_secao_pela_arvore(v_verf);
  perform pg_temp.teste_assert_0204((v_r->>'linhas')::int = 2, 'a chamada seguinte retoma e herda os 2 que faltavam (a gravação/backfill seguinte converge)', v_r::text);

  raise notice '--- 7. o backfill: a mesma conta, linha humana não é alvo mas serve de pai, sem vazar entre versões ---';
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2024', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0204/bp2024.pdf', 'balanco_2024.pdf', true, 'HASH-0204-2', 'ok');
  v_verb := (v_r->>'documento_versao_id')::uuid;
  -- linhas "de antes da 0204": inseridas direto, sem passar pela gravação nova
  insert into campo_extraido (documento_versao_id, chave, valor_num, secao, secao_canonica, periodo_coluna, confianca) values
    (v_verb, 'CLIENTES', 5218337.81, 'ATIVO CIRCULANTE', 'ativo_circulante', 'Saldo Final', 0.97);
  insert into campo_extraido (documento_versao_id, chave, valor_num, secao, secao_canonica, periodo_coluna, confianca, revisado_por) values
    (v_verb, 'CAIXA', 100, 'ATIVO CIRCULANTE', 'ativo_circulante', 'Saldo Final', 0.97, 'analista@oria');     -- pai humano
  insert into campo_extraido (documento_versao_id, chave, valor_num, secao, secao_canonica, periodo_coluna, confianca) values
    (v_verb, '1.1.03 ESTOQUES', 9, 'ATIVO CIRCULANTE', 'ativo_circulante', 'Saldo Final', 0.97);              -- arranjo: balancete com código
  insert into campo_extraido (documento_versao_id, chave, valor_num, secao, periodo_coluna, confianca) values
    (v_verb, 'DUPLICATAS A RECEBER', 5218337.81, 'CLIENTES', 'Saldo Final', 0.97),
    (v_verb, 'CAIXA MATRIZ',         100,        'CAIXA',    'Saldo Final', 0.97),
    (v_verb, 'ESTOQUE ACABADO',      9,          'ESTOQUES', 'Saldo Final', 0.97),                           -- arranjo: o pai tem código do ERP
    (v_verb, 'SEM SECAO BRUTA',      1,          null,       'Saldo Final', 0.97);
  insert into campo_extraido (documento_versao_id, chave, valor_num, secao, periodo_coluna, confianca, revisado_por) values
    (v_verb, 'REVISADA',             7,          'CLIENTES', 'Saldo Final', 0.97, 'analista@oria');          -- revisada: não é alvo
  insert into campo_extraido (documento_versao_id, chave, valor_num, secao, periodo_coluna, confianca, origem_valor) values
    (v_verb, 'TRANSCRITA',           8,          'CLIENTES', 'Saldo Final', null, 'transcricao_humana');     -- transcrita: não é alvo

  -- uma terceira versão sem NENHUM pai nem irmã: o CLIENTES das outras versões não pode vazar para cá
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2023', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0204/bp2023.pdf', 'balanco_2023.pdf', true, 'HASH-0204-3', 'ok');
  v_verc := (v_r->>'documento_versao_id')::uuid;
  insert into campo_extraido (documento_versao_id, chave, valor_num, secao, periodo_coluna, confianca) values
    (v_verc, 'DUPLICATAS A RECEBER', 1, 'CLIENTES', 'Saldo Final', 0.97);
  -- e um tipo fora das cinco demonstrações, com pai e filha
  v_r := fn_registrar_documento(v_caso, c, 'anual', '2025', 'FATURAMENTO_24M', 0.97,
    'nome_arquivo', 'supabase_storage', '0204/fat.pdf', 'fat.pdf', true, 'HASH-0204-4', 'ok');
  insert into campo_extraido (documento_versao_id, chave, valor_num, secao, secao_canonica, periodo_coluna, confianca)
    values ((v_r->>'documento_versao_id')::uuid, 'CLIENTES', 1, 'ATIVO CIRCULANTE', 'ativo_circulante', 'Saldo Final', 0.97);
  insert into campo_extraido (documento_versao_id, chave, valor_num, secao, periodo_coluna, confianca)
    values ((v_r->>'documento_versao_id')::uuid, 'FILHA FORA DO TIPO', 1, 'CLIENTES', 'Saldo Final', 0.97);

  v_r := fn_herdar_secao_pela_arvore(null, v_caso);
  -- 3 na versão 2024 (DUPLICATAS A RECEBER, CAIXA MATRIZ, ESTOQUE ACABADO) + nada nas outras
  perform pg_temp.teste_assert_0204((v_r->>'linhas')::int = 3 and (v_r->>'versoes')::int = 1 and (v_r->>'casos')::int = 1,
    'o backfill do caso alcança as 3 linhas da versão 2024 e diz em quantas versões e casos', v_r::text);
  select string_agg(chave || '=' || coalesce(secao_canonica, 'NULL') || '/' || secao_canonica_inferida::text, ', ' order by chave) into v_txt
    from campo_extraido where documento_versao_id = v_verb and chave in ('DUPLICATAS A RECEBER', 'CAIXA MATRIZ', 'ESTOQUE ACABADO', 'REVISADA', 'TRANSCRITA', 'SEM SECAO BRUTA');
  perform pg_temp.teste_assert_0204(v_txt = 'CAIXA MATRIZ=ativo_circulante/true, DUPLICATAS A RECEBER=ativo_circulante/true, ESTOQUE ACABADO=ativo_circulante/true, REVISADA=NULL/false, SEM SECAO BRUTA=NULL/false, TRANSCRITA=NULL/false',
    'herdam as três (a CAIXA MATRIZ de um pai revisado por pessoa; o ESTOQUE ACABADO de um pai com código do ERP "1.1.03"); a revisada, a transcrita e a sem-seção-bruta ficam como estavam', v_txt);
  perform pg_temp.teste_assert_0204(pg_temp.s0204(v_verc, 'DUPLICATAS A RECEBER') = 'NULL/false', 'a versão 2023, sem pai nem irmã, NÃO herda do CLIENTES das outras versões (a árvore é a do documento)', pg_temp.s0204(v_verc, 'DUPLICATAS A RECEBER'));
  select count(*) into v_n from campo_extraido where chave = 'FILHA FORA DO TIPO' and secao_canonica is null and not secao_canonica_inferida;
  perform pg_temp.teste_assert_0204(v_n = 1, 'FATURAMENTO_24M não herda: fora das cinco demonstrações a herança não opina', format('%s', v_n));
  v_r := fn_herdar_secao_pela_arvore(null, v_caso);
  perform pg_temp.teste_assert_0204((v_r->>'linhas')::int = 0, 'idempotente: a segunda rodada não alcança linha nenhuma', v_r::text);
  v_r := fn_herdar_secao_pela_arvore(null, gen_random_uuid());
  perform pg_temp.teste_assert_0204((v_r->>'linhas')::int = 0 and (v_r->>'conflitos')::int = 0, 'caso sem linhas: zero, sem erro', v_r::text);

  raise notice '--- 8. o que a IA deu nunca é marcado como herdado ---';
  select count(*) into v_n from campo_extraido
   where documento_versao_id = v_ver and chave in ('CLIENTES', 'CAIXA', 'ADIANTAMENTO DE VIAGENS', 'DEPOSITOS JUDICIAIS', 'IRMA ATIVA', 'IRMA PASSIVA', 'ANCORA DO CICLO')
     and (secao_canonica_inferida or secao_canonica is null);
  perform pg_temp.teste_assert_0204(v_n = 0, 'as 7 linhas que a IA classificou seguem com a seção que ela deu e marcam false', format('%s violações', v_n));
end $$;

do $$
declare
  v_n int;
begin
  select case when is_called then last_value else 0 end into v_n from pg_temp._falhas_0204;
  if v_n > 0 then
    raise exception 'FALHOU: % assert(s) da 0204 reprovaram — ver as linhas FALHOU acima', v_n;
  end if;
  raise notice 'TODOS OS TESTES DA 0204 (seção herdada pela árvore) PASSARAM';
end $$;

rollback;
