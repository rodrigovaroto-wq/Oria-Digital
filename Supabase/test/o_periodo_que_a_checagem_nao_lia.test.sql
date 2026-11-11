-- Testes da 0234: o período que o documento tinha e a checagem não lia.
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO PROVA (comportamento, não mecanismo):
--   (A) um balanço/DRE cujas colunas são "Saldo Final"/"Saldo Inicial" (ou "Saldo atual"/"Saldo anterior"), sem ano no texto, é reconciliado no ano da referência do documento em vez de cair em
--       "sem período par"; fechamento = ano, abertura = ano - 1; NENHUM dos dois em documento de período parcial (balancete/DRE semestral, balanço de junho); a abertura só em demonstração patrimonial ou em documento sem Débito/Crédito (o Saldo anterior de uma DRE em razão é 0); Débito/Crédito nunca é saldo; "Saldo"/"Valor" continuam sem exercício; referência multi-ano continua sem
--       afirmar (teto declarado); coluna com ano no texto continua mandando; a divergência de verdade continua divergente.
--   (B) o período do diagnóstico e o registrado são equivalentes quando NENHUM lado é parcial, o ano mais recente é o mesmo, um conjunto contém o outro e a união é contígua ("data-base 2025-06-30" x "multi 24,25" NÃO); e os controles que TÊM de continuar abrindo continuam
--       ("anual 21,25" x "multi 23,24,25", "anual 25,26" x "multi 24,25", "anual 23,24" x "anual 2023", "multi 2024,2025" x "multi 01,24,25"). Ponta a ponta por fn_registrar_diagnostico, e o backfill
--       fn_resolver_periodo_incorreto_falso só resolve o 'aberta' de origem 'diagnostico'.
--
-- ARRANJO À MÃO (e só ele): a pendência periodo_incorreto "falsa" do backfill é inserida direto, no formato de descrição que fn_registrar_diagnostico gravava antes da 0234 (a função nova já não a abre,
-- esse é o ponto); o documento e as linhas vêm de fn_registrar_documento e fn_registrar_campos_extraidos de verdade. Os 8 e os 57 de produção não são reproduzidos: o teste afirma só o que dá para provar.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md): 50 execuções (34 chamadas de assert no arquivo; as 16 execuções a mais vêm dos laços B1 e B2); o número reprovado por sabotagem está no cabeçalho de
-- Supabase/migrations/0234_o_periodo_que_o_documento_tinha_e_a_checagem_nao_lia.sql ("MEDIÇÃO NÃO-VAZIA").
--
-- `p9.medindo = on` (PGOPTIONS='-c p9.medindo=on') vira `raise warning` e CONTA.

\set ON_ERROR_STOP on

create or replace function teste_assert_p9(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('p9.execucoes', (coalesce(nullif(current_setting('p9.execucoes', true), ''), '0')::int + 1)::text, false);
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  elsif current_setting('p9.medindo', true) = 'on' then
    perform set_config('p9.falhas', (coalesce(nullif(current_setting('p9.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- documento + linhas (uma por [chave, coluna, valor]); devolve a versão
create or replace function teste_doc_p9(p_caso uuid, p_ent text, p_ptipo text, p_pref text, p_tipo text, p_hash text, p_linhas jsonb) returns uuid language plpgsql as $$
declare v_r jsonb; v_i int := 0; v_l jsonb := '[]'::jsonb; v_x jsonb;
begin
  v_r := fn_registrar_documento(p_caso, p_ent, p_ptipo, p_pref, p_tipo, 0.97, 'nome_arquivo', 'supabase_storage', 'p9/' || p_hash || '.pdf', p_hash || '.pdf', true, p_hash, 'ok');
  for v_x in select * from jsonb_array_elements(p_linhas) loop
    v_l := v_l || jsonb_build_object('ordem', v_i, 'chave', v_x->>0, 'periodo_coluna', v_x->>1, 'valor_num', v_x->>2, 'unidade', 'milhar', 'confianca', '0.97');
    v_i := v_i + 1;
  end loop;
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, v_l, 'N2');
  return (v_r->>'documento_versao_id')::uuid;
end $$;

delete from caso where nome like 'Caso P9 %';

do $$
declare
  v_caso uuid; v_ver uuid; v_n int; v_col text; v_r jsonb; v_res text; v_ent uuid; v_per uuid;
  v_sent constant text := E'\x01';
begin
  raise notice '--- A1. BALANÇO anual 2024 com "Saldo Final"/"Saldo Inicial" (o arranjo do Fw Valtra) ---';
  v_caso := (fn_upsert_caso('Caso P9 A1'))::uuid;
  v_ver := teste_doc_p9(v_caso, 'MOTO P9 LTDA', 'anual', '2024', 'BALANCO', 'P9-A1', jsonb_build_array(
    jsonb_build_array('ATIVO', 'Saldo Final', 1000), jsonb_build_array('ATIVO', 'Saldo Inicial', 900),
    jsonb_build_array('PASSIVO E PATRIMÔNIO LÍQUIDO', 'Saldo Final', 1000), jsonb_build_array('PASSIVO E PATRIMÔNIO LÍQUIDO', 'Saldo Inicial', 900),
    jsonb_build_array('Ativo Circulante', 'Saldo Final', 300), jsonb_build_array('Ativo Circulante', 'Saldo Inicial', 250)));
  perform teste_assert_p9(fn_coluna_periodo_do_ano(v_ver, 2024) = 'Saldo Final', 'ano da referência (2024): a coluna é "Saldo Final"', coalesce(fn_coluna_periodo_do_ano(v_ver, 2024), 'null'));
  perform teste_assert_p9(fn_coluna_periodo_do_ano(v_ver, 2023) = 'Saldo Inicial', 'ano - 1 (2023): a coluna é "Saldo Inicial"', coalesce(fn_coluna_periodo_do_ano(v_ver, 2023), 'null'));
  perform teste_assert_p9(fn_coluna_periodo_do_ano(v_ver, 2025) = v_sent and fn_coluna_periodo_do_ano(v_ver, 2022) = v_sent, 'outro ano (2025, 2022): sentinela, como antes');
  select entidade_id, periodo_id into v_ent, v_per from documento where caso_id = v_caso limit 1;
  v_r := fn_reconciliar_ativo_passivo_pl(v_caso, v_ent, v_per);
  perform teste_assert_p9(v_r->>'resultado' = 'ok', 'Ativo = Passivo+PL em "Saldo Final": a reconciliação CONFERE (antes: sem_periodo_par)', v_r::text);
  select count(*) into v_n from pendencia where caso_id = v_caso and estado <> 'resolvida' and tipo = 'precondicao_nao_satisfeita';
  perform teste_assert_p9(v_n = 0, 'e nenhuma pré-condição fica aberta', v_n::text);

  raise notice '--- A2. a divergência de verdade continua divergente ---';
  v_caso := (fn_upsert_caso('Caso P9 A2'))::uuid;
  v_ver := teste_doc_p9(v_caso, 'MOTO P9 DIV LTDA', 'anual', '2024', 'BALANCO', 'P9-A2', jsonb_build_array(
    jsonb_build_array('ATIVO', 'Saldo Final', 1000), jsonb_build_array('PASSIVO E PATRIMÔNIO LÍQUIDO', 'Saldo Final', 800),
    jsonb_build_array('ATIVO', 'Saldo Inicial', 900), jsonb_build_array('PASSIVO E PATRIMÔNIO LÍQUIDO', 'Saldo Inicial', 900)));
  select entidade_id, periodo_id into v_ent, v_per from documento where caso_id = v_caso limit 1;
  v_r := fn_reconciliar_ativo_passivo_pl(v_caso, v_ent, v_per);
  perform teste_assert_p9(v_r->>'resultado' = 'divergente', 'Ativo 1000 x Passivo+PL 800 em "Saldo Final": divergente de verdade (a correção não esconde)', v_r::text);

  raise notice '--- A3. DRE "Saldo atual"/"Saldo anterior" ---';
  v_caso := (fn_upsert_caso('Caso P9 A3'))::uuid;
  v_ver := teste_doc_p9(v_caso, 'MOTO P9 DRE LTDA', 'anual', '2024', 'DRE', 'P9-A3', jsonb_build_array(
    jsonb_build_array('Receita Bruta', 'Saldo atual', 5000), jsonb_build_array('Receita Bruta', 'Saldo anterior', 4000)));
  perform teste_assert_p9(fn_coluna_periodo_do_ano(v_ver, 2024) = 'Saldo atual' and fn_coluna_periodo_do_ano(v_ver, 2023) = 'Saldo anterior',
    'DRE: 2024 = "Saldo atual", 2023 = "Saldo anterior"');
  -- (revisão, médio 2) DRE no formato de RAZÃO (com Débito/Crédito): o Saldo anterior das contas de resultado é 0 (zeradas no fechamento), então NÃO é o ano - 1.
  v_ver := teste_doc_p9(v_caso, 'MOTO P9 RAZAO LTDA', 'anual', '2024', 'DRE', 'P9-A3B', jsonb_build_array(
    jsonb_build_array('Receita Bruta', 'Saldo anterior', 0), jsonb_build_array('Receita Bruta', 'Débito', 100), jsonb_build_array('Receita Bruta', 'Crédito', 5100),
    jsonb_build_array('Receita Bruta', 'Saldo atual', 5000)));
  perform teste_assert_p9(fn_coluna_periodo_do_ano(v_ver, 2024) = 'Saldo atual', 'DRE em razão: 2024 continua "Saldo atual"', coalesce(fn_coluna_periodo_do_ano(v_ver, 2024), 'null'));
  perform teste_assert_p9(fn_coluna_periodo_do_ano(v_ver, 2023) = v_sent, 'DRE em razão (Débito/Crédito): 2023 NÃO é o "Saldo anterior" (seria receita 0 do ano anterior): sentinela', coalesce(fn_coluna_periodo_do_ano(v_ver, 2023), 'null'));
  -- e o BALANÇO com movimento (patrimonial): o saldo inicial É o fechamento do ano anterior
  v_ver := teste_doc_p9(v_caso, 'MOTO P9 BPMOV LTDA', 'anual', '2024', 'BALANCO', 'P9-A3C', jsonb_build_array(
    jsonb_build_array('ATIVO', 'Saldo Inicial', 900), jsonb_build_array('ATIVO', 'Débito', 300), jsonb_build_array('ATIVO', 'Crédito', 200), jsonb_build_array('ATIVO', 'Saldo Final', 1000)));
  perform teste_assert_p9(fn_coluna_periodo_do_ano(v_ver, 2023) = 'Saldo Inicial', 'BALANÇO com Débito/Crédito (patrimonial): 2023 = "Saldo Inicial"', coalesce(fn_coluna_periodo_do_ano(v_ver, 2023), 'null'));

  raise notice '--- A4. movimento nunca é saldo; "Saldo" e "Valor" não nomeiam saldo ---';
  v_caso := (fn_upsert_caso('Caso P9 A4'))::uuid;
  v_ver := teste_doc_p9(v_caso, 'MOTO P9 BAL LTDA', 'anual', '2024', 'BALANCO', 'P9-A4', jsonb_build_array(
    jsonb_build_array('ATIVO', 'Débito', 7000), jsonb_build_array('ATIVO', 'Crédito', 6000), jsonb_build_array('ATIVO', 'Saldo Final', 1000)));
  perform teste_assert_p9(fn_coluna_periodo_do_ano(v_ver, 2024) = 'Saldo Final', 'com Débito, Crédito e Saldo Final: o ano 2024 é "Saldo Final", nunca o movimento', coalesce(fn_coluna_periodo_do_ano(v_ver, 2024), 'null'));
  perform teste_assert_p9(fn_coluna_periodo_do_ano(v_ver, 2023) = v_sent, 'e sem abertura no documento, 2023 é sentinela (Débito/Crédito não viram "Saldo Inicial")');
  v_ver := teste_doc_p9(v_caso, 'MOTO P9 BAL2 LTDA', 'anual', '2024', 'BALANCO', 'P9-A4B', jsonb_build_array(
    jsonb_build_array('ATIVO', 'Saldo', 1000), jsonb_build_array('ATIVO', 'Valor', 1000)));
  perform teste_assert_p9(fn_coluna_periodo_do_ano(v_ver, 2024) = v_sent, 'colunas "Saldo" e "Valor" não nomeiam saldo: continuam sem exercício (sentinela)');
  v_ver := teste_doc_p9(v_caso, 'MOTO P9 SEM LTDA', 'anual', '2024', 'BALANCO', 'P9-A4C', '[]'::jsonb);
  perform teste_assert_p9(fn_coluna_periodo_do_ano(v_ver, 2024) is null, 'documento sem coluna de período nenhuma: nulo (retrato de um ano), como antes');

  raise notice '--- A5. o que não se afirma: referência multi-ano; balancete parcial; coluna com ano no texto ---';
  v_ver := teste_doc_p9(v_caso, 'MOTO P9 MULTI LTDA', 'multi', '24,25', 'BALANCO', 'P9-A5', jsonb_build_array(
    jsonb_build_array('ATIVO', 'Saldo Final', 1000), jsonb_build_array('ATIVO', 'Saldo Inicial', 900)));
  perform teste_assert_p9(fn_coluna_periodo_do_ano(v_ver, 2025) = v_sent and fn_coluna_periodo_do_ano(v_ver, 2024) = v_sent,
    'referência multi 24,25 com "Saldo Final": não diz de qual ano (sentinela; teto declarado)');
  v_ver := teste_doc_p9(v_caso, 'MOTO P9 SEMESTRE LTDA', 'data-base', '01/01/2026 - 30/06/2026', 'BALANCETE', 'P9-A5B', jsonb_build_array(
    jsonb_build_array('ATIVO', 'Saldo Final', 1000), jsonb_build_array('ATIVO', 'Saldo Inicial', 900)));
  perform teste_assert_p9(fn_coluna_periodo_do_ano(v_ver, 2026) = v_sent, 'balancete semestral: o "Saldo Final" NÃO vale como o ano cheio de 2026 (sentinela, como antes da 0234)', coalesce(fn_coluna_periodo_do_ano(v_ver, 2026), 'null'));
  perform teste_assert_p9(fn_coluna_periodo_do_ano(v_ver, 2025) = v_sent, 'balancete semestral: o "Saldo Inicial" NÃO vira o fechamento de 2025 (é o início do período)', coalesce(fn_coluna_periodo_do_ano(v_ver, 2025), 'null'));
  -- (revisão, médio 1) DRE de período parcial com "Saldo atual": o acumulado de 6 meses não é o ano de 2026
  v_ver := teste_doc_p9(v_caso, 'MOTO P9 DRESEM LTDA', 'data-base', '01/01/2026 - 30/06/2026', 'DRE', 'P9-A5D', jsonb_build_array(
    jsonb_build_array('Receita Bruta', 'Saldo atual', 2500), jsonb_build_array('Receita Bruta', 'Saldo anterior', 0)));
  perform teste_assert_p9(fn_coluna_periodo_do_ano(v_ver, 2026) = v_sent and fn_coluna_periodo_do_ano(v_ver, 2025) = v_sent,
    'DRE semestral ("01/01/2026 - 30/06/2026") com "Saldo atual": nem 2026 nem 2025 (sentinela; antes valia como o ano cheio)');
  v_ver := teste_doc_p9(v_caso, 'MOTO P9 BP0630 LTDA', 'data-base', '2025-06-30', 'BALANCO', 'P9-A5E', jsonb_build_array(
    jsonb_build_array('ATIVO', 'Saldo Final', 1000), jsonb_build_array('ATIVO', 'Saldo Inicial', 900)));
  perform teste_assert_p9(fn_coluna_periodo_do_ano(v_ver, 2025) = v_sent, 'balanço intermediário (data-base 2025-06-30): o "Saldo Final" de junho NÃO é o fechamento de 2025 (sentinela)');
  v_ver := teste_doc_p9(v_caso, 'MOTO P9 BP1231 LTDA', 'data-base', '2025-12-31', 'BALANCO', 'P9-A5F', jsonb_build_array(
    jsonb_build_array('ATIVO', 'Saldo Final', 1000), jsonb_build_array('ATIVO', 'Saldo Inicial', 900)));
  perform teste_assert_p9(fn_coluna_periodo_do_ano(v_ver, 2025) = 'Saldo Final' and fn_coluna_periodo_do_ano(v_ver, 2024) = 'Saldo Inicial',
    'controle: data-base 2025-12-31 (fecha o ano) não é parcial: 2025 = "Saldo Final", 2024 = "Saldo Inicial"');
  v_ver := teste_doc_p9(v_caso, 'MOTO P9 TEXTO LTDA', 'multi', '24,25', 'BALANCO', 'P9-A5C', jsonb_build_array(
    jsonb_build_array('ATIVO', '31/12/2024', 800), jsonb_build_array('ATIVO', '31/12/2025', 900), jsonb_build_array('ATIVO', 'Saldo Final', 999)));
  perform teste_assert_p9(fn_coluna_periodo_do_ano(v_ver, 2024) = '31/12/2024' and fn_coluna_periodo_do_ano(v_ver, 2025) = '31/12/2025',
    'coluna com o ano no TEXTO continua mandando (o casamento por texto vem primeiro)');
end $$;

do $$
declare
  v_caso uuid; v_r jsonb; v_doc uuid; v_ver uuid; v_n int; v_i int;
  v_p record; v_ids uuid[] := '{}'; v_id uuid;
begin
  raise notice '--- B1. fn_periodos_equivalentes: o que passa a ser o mesmo exercício ---';
  for v_p in select * from (values
    ('anual', '12M25', 'multi', '24,25'), ('data-base', '2025-12-31', 'multi', '24,25'), ('anual', '23,24,25', 'multi', '24,25'),
    ('anual', '12M25', 'multi', '23,24,25'), ('data-base', '15/01/2025', 'data-base', '2025-01-15'),
    ('data-base', '2025-06-30', 'anual', '2025')   -- parcial x anual do MESMO ano: já era equivalente (conjuntos iguais); a granularidade abaixo do ano não é verificada
  ) as t(ta, ra, tb, rb) loop
    perform teste_assert_p9(fn_periodos_equivalentes(v_p.ta, v_p.ra, v_p.tb, v_p.rb) and fn_periodos_equivalentes(v_p.tb, v_p.rb, v_p.ta, v_p.ra),
      format('equivalentes (nos dois sentidos): %s %s x %s %s', v_p.ta, v_p.ra, v_p.tb, v_p.rb));
  end loop;
  raise notice '--- B2. e os controles que TÊM de continuar abrindo ---';
  for v_p in select * from (values
    ('anual', '21,25', 'multi', '23,24,25'), ('anual', '25,26', 'multi', '24,25'), ('anual', '23,24', 'anual', '2023'),
    ('multi', '2024,2025', 'multi', '01,24,25'), ('anual', '2024', 'anual', '2025'), ('anual', '2025', 'multi', '02,25'),
    ('anual', '23,25', 'multi', '24,25'),
    ('data-base', '2025-06-30', 'multi', '24,25'),               -- (revisão, alto) o balanço de junho não é o comparativo 24,25
    ('data-base', '2026-06-30', 'multi', '01/07/2025 a 30/06/2026'), ('anual', '12M26', 'multi', '01/07/2025 a 30/06/2026'),
    ('outro', '12M26', 'multi', '01/07/2025 a 30/06/2026'), ('data-base', '2025-06-30', 'multi', '23,24,25')
  ) as t(ta, ra, tb, rb) loop
    perform teste_assert_p9(not fn_periodos_equivalentes(v_p.ta, v_p.ra, v_p.tb, v_p.rb) and not fn_periodos_equivalentes(v_p.tb, v_p.rb, v_p.ta, v_p.ra),
      format('DISTINTOS (segue abrindo): %s %s x %s %s', v_p.ta, v_p.ra, v_p.tb, v_p.rb));
  end loop;

  raise notice '--- B3. ponta a ponta pelo diagnóstico: o comparativo não abre pendência; o documento de 2021 registrado errado abre ---';
  v_caso := (fn_upsert_caso('Caso P9 B3'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'COMPARATIVO P9 LTDA', 'multi', '24,25', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage', 'p9/b3.pdf', 'BP_2025x2024.pdf', true, 'P9-B3', 'ok');
  perform fn_registrar_diagnostico((v_r->>'documento_id')::uuid, (v_r->>'documento_versao_id')::uuid, 'COMPARATIVO P9 LTDA', true, 'BALANCO', 'anual', '12M25', 'ok', null, 'resumo', 'justificativa');
  select count(*) into v_n from pendencia where caso_id = v_caso and tipo = 'periodo_incorreto';
  perform teste_assert_p9(v_n = 0, 'registrado "multi 24,25", IA diz "anual 12M25": nenhuma pendência periodo_incorreto', v_n::text);
  perform fn_registrar_diagnostico((v_r->>'documento_id')::uuid, (v_r->>'documento_versao_id')::uuid, 'COMPARATIVO P9 LTDA', true, 'BALANCO', 'anual', '21,25', 'ok', null, 'resumo', 'justificativa');
  select count(*) into v_n from pendencia where caso_id = v_caso and tipo = 'periodo_incorreto' and estado = 'aberta';
  perform teste_assert_p9(v_n = 1, 'controle: IA diz "anual 21,25" contra "multi 24,25": a pendência abre', v_n::text);

  raise notice '--- B4. o backfill: só o aberto de origem diagnostico, e só o falso ---';
  v_caso := (fn_upsert_caso('Caso P9 B4'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'BACKFILL P9 LTDA', 'multi', '24,25', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage', 'p9/b4.pdf', 'B4.pdf', true, 'P9-B4', 'ok');
  v_doc := (v_r->>'documento_id')::uuid;
  -- ARRANJO À MÃO: a descrição no formato de fn_registrar_diagnostico antes da 0234 (o par já é equivalente pela regra nova)
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo, estado)
    select v_caso, o, 'periodo_incorreto', 'importante', true,
           format('Diagnóstico de conteúdo sugere período "%s" (documento está registrado com "%s"). j', s, r), v_doc, 'diagnostico:periodo:' || v_doc || ':' || k, e::pendencia_estado
      from (values
        ('diagnostico', 'anual 12M25',  'multi 24,25',      'aberta',              'falsa'),
        ('diagnostico', 'anual 21,25',  'multi 23,24,25',   'aberta',              'verdadeira'),
        ('diagnostico', 'anual 12M25',  'multi 24,25',      'em_correcao_interna', 'humana'),
        ('completude',  'anual 12M25',  'multi 24,25',      'aberta',              'outra_origem'),
        ('diagnostico', 'anual 12M25',  'multi 24,25',      'aceita_com_ressalva', 'ressalva')
      ) as t(o, s, r, e, k);
  v_n := fn_resolver_periodo_incorreto_falso(v_caso);
  perform teste_assert_p9(v_n = 1, 'o backfill resolve UMA (a falsa, aberta, do diagnóstico)', v_n::text);
  perform teste_assert_p9((select resolvida_por from pendencia where documento_id = v_doc and motivo like '%:falsa') = 'sistema:0234'
      and (select estado::text from pendencia where documento_id = v_doc and motivo like '%:falsa') = 'resolvida', 'resolvida_por = sistema:0234');
  perform teste_assert_p9((select estado::text from pendencia where documento_id = v_doc and motivo like '%:verdadeira') = 'aberta', 'a verdadeira ("anual 21,25" x "multi 23,24,25") continua aberta');
  perform teste_assert_p9((select estado::text from pendencia where documento_id = v_doc and motivo like '%:humana') = 'em_correcao_interna'
      and (select estado::text from pendencia where documento_id = v_doc and motivo like '%:ressalva') = 'aceita_com_ressalva', 'a decisão humana (em_correcao_interna, aceita_com_ressalva) não é tocada');
  perform teste_assert_p9((select estado::text from pendencia where documento_id = v_doc and motivo like '%:outra_origem') = 'aberta', 'a de outra origem (não diagnostico) não é tocada');
  perform teste_assert_p9(fn_resolver_periodo_incorreto_falso(v_caso) = 0, 'idempotente: a segunda rodada resolve 0');
  perform teste_assert_p9(exists (select 1 from evento_auditoria where acao = 'periodo_incorreto_falso_resolvido' and ator = 'sistema:migration_0234'), 'e deixa o rastro de auditoria');

  raise notice '--- C. a sonda enxerga os requisitos da 0234 ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0234' and presente;
  perform teste_assert_p9(v_n = 8, 'os 8 requisitos da 0234 estão presentes na sonda', v_n::text);
  select count(*) into v_n from instalacao_requisito where migration = '0234';
  perform teste_assert_p9(v_n = 8, 'e o catálogo declara exatamente 8', v_n::text);

  if current_setting('p9.medindo', true) = 'on' then
    raise warning 'MEDIDO: % falha(s) de % execucoes', coalesce(current_setting('p9.falhas', true), '0'), current_setting('p9.execucoes', true);
  end if;
  raise notice 'TODOS OS TESTES DA 0234 PASSARAM';
end $$;
