-- Testes da 0243 (Supabase/migrations/0243_a_linha_que_nao_tinha_identidade.sql): o fato_financeiro acima de campo_extraido (P27, Fase 3, etapa 3.2).
-- Rodar via Supabase/test/run.sh (as fixtures de vertentes e canastra já estão carregadas; elas entram DEPOIS das migrations, então o backfill da migration rodou sobre um banco vazio e é
-- a fn_materializar_fatos_backfill() que este arquivo chama sobre elas). Tudo corre numa transação que é DESFEITA no fim: o banco fica como estava para os testes seguintes.
--
-- O QUE ESTE ARQUIVO PROVA (comportamento, regra 3):
--   (a) a BIJEÇÃO: toda linha elegível (documento de demonstração, papel conta, com valor) tem fato depois do backfill, e nenhum fato existe para o que não é elegível; o backfill é idempotente;
--   (b) nenhum fato aponta para nó que não é seção (identidade = seção, decisão do dono);
--   (c) seção inferida = heuristica, declarada = declarada, sem seção (nula ou o literal NAO_CLASSIFICAVEL das fixtures) ou fora do catálogo = sem_conta, com o motivo — e a linha sem conta NÃO ganha conta;
--   (d) a EXTRAÇÃO NOVA (fn_registrar_campos_extraidos, o ponto do n8n): só linhas declaradas abrem 0 pendência; heurística ou sem seção abre exatamente 1 por documento-versão (e a segunda versão abre a dela); documento
--       que não é de demonstração não materializa nada; o evento fatos_materializados prova que rodou; a falha da materialização NÃO derruba a extração (o evento fatos_materializacao_falhou diz);
--   (e) o backfill NÃO abre pendência e grava o resumo (quantas linhas incertas ficaram sem pendência, e por quê);
--   (f) tipos fora da lista (Estoque, Razão, Aging...), subtotal, linha sem valor: continuam só evidência;
--   (g) o período da COLUNA prevalece sobre o do documento quando diferem; coluna de ano sem período no mandato deixa o período explícito e NULO (o período não é criado); a entidade pela coluna (uma entidade, o total
--       do documento, a eliminação que não é entidade);
--   (h) o fato segue o documento (corrigir a entidade/o período do documento leva os fatos que herdaram dele, não os que vieram de uma coluna); (i) a fusão de entidade leva os fatos (a FK não a derruba);
--   (j) o acesso: sem papel lê zero, Sócio lê, o Analista alocado materializa pelo caminho do portal; (k) a sonda: os 18 requisitos presentes e ela ACUSA cada guarda removida (não está cega).
--
-- HONESTIDADE (regra 4): as fixtures de vertentes e canastra são sintéticas e não trazem o arranjo que produção traz de linhas com entidade_coluna sem entidade cadastrada nem o de duas colunas de ano de um balanço real;
-- os asserts de (d), (g), (h), (i) usam linhas sintéticas porque provam a REGRA de resolução (qual coluna vence), não reproduzem um documento do cliente. Os números de produção estão na migration, medidos read-only.
--
-- NÃO PARA NO PRIMEIRO ERRO: anota e segue, e o bloco final reprova com a CONTAGEM (regra 2). `PGOPTIONS='-c ff.medindo=on'` só tira o `raise exception` do fim (para a medição por sabotagem).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número que reprova por sabotagem, parte a parte, está no cabeçalho de Supabase/migrations/0243_a_linha_que_nao_tinha_identidade.sql.

-- A 0243 é REAPLICADA aqui, antes da transação: o run.sh roda o_balanco_sem_dado_financeiro.test.sql, que reaplica a 0231 INTEIRA e com ela devolve a fn_registrar_campos_extraidos ao corpo de ANTES da 0243 (sem a chamada que materializa o fato).
-- Medido no run.sh: sem esta linha 37 dos 95 asserts reprovam (os mesmos da sabotagem "registrar sem a chamada") e a sonda fecha o run.sh com o requisito registrar_materializa_fatos ausente. A migration é idempotente de propósito (reaplicável).
\i Supabase/migrations/0243_a_linha_que_nao_tinha_identidade.sql

begin;

create temp sequence _falhas_0243;
create temp sequence _execucoes_0243;

create or replace function pg_temp.teste_assert_ff(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform nextval('pg_temp._execucoes_0243');
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  else
    raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
    perform nextval('pg_temp._falhas_0243');
  end if;
end $$;

-- O ELEGÍVEL, reescrito AQUI de propósito (e não pela fn_linha_vira_fato da migration): um teste que pergunta ao código o que o código acha elegível protege o bug (regra 3).
create temp view _elegiveis as
  select ce.id as campo_id, ce.documento_versao_id, d.tipo_taxonomia as tipo, ce.secao_canonica, ce.secao_canonica_inferida as inferida
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
   where ce.valor_num is not null
     and d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DRE', 'FLUXO_CAIXA', 'DVA', 'DMPL', 'DF_AUDITADA')
     and fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) = 'conta';

-- Registra um documento de demonstração e grava as linhas pelo caminho do n8n; devolve a versão.
create or replace function pg_temp.doc(p_caso uuid, p_ent text, p_per text, p_tipo text, p_hash text, p_campos jsonb) returns uuid
language plpgsql as $$
declare v uuid;
begin
  v := (fn_registrar_documento(p_caso, p_ent, 'anual', p_per, p_tipo, 0.97, 'nome_arquivo', 'supabase_storage', '0243/' || p_hash || '.pdf', p_hash || '.pdf', true, p_hash, 'ok')->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v, p_campos);
  return v;
end $$;

create or replace function pg_temp.l(p_chave text, p_valor text, p_secao_canonica text default null, p_secao text default null, p_pcol text default null, p_ecol text default null) returns jsonb
language sql as $$
  select jsonb_strip_nulls(jsonb_build_object('chave', p_chave, 'valor_num', p_valor, 'secao_canonica', p_secao_canonica, 'secao', p_secao, 'periodo_coluna', p_pcol, 'entidade_coluna', p_ecol, 'confianca', '0.97'))
$$;

-- ---------------------------------------------------------------------------------------------------------------
do $$
declare
  v_el int; v_sem_antes int; v_tipos int; v_r jsonb; v_r2 jsonb; v_pend_antes int; v_pend_depois int; v_n int; v_n2 int; v_ev jsonb;
begin
  raise notice '--- a. a bijeção sobre as fixtures carregadas (toda linha elegível tem fato; só ela) ---';
  -- O ESTADO DE ANTES DO BACKFILL: os testes anteriores que passaram por fn_registrar_campos_extraidos já deixaram fatos; aqui, dentro desta transação (desfeita no fim), eles são apagados e o backfill roda sobre tudo, fixtures incluídas.
  delete from fato_financeiro;
  delete from evento_auditoria where acao = 'fato_financeiro_backfill';
  select count(*), count(distinct tipo) into v_el, v_tipos from _elegiveis;
  perform pg_temp.teste_assert_ff(v_el >= 1000 and v_tipos >= 4, 'as fixtures trazem linhas elegíveis para medir (o laço abaixo não corre sobre o vazio)', v_el || ' linhas em ' || v_tipos || ' tipos');
  select count(*) into v_sem_antes from _elegiveis e where not exists (select 1 from fato_financeiro f where f.campo_extraido_id = e.campo_id);
  perform pg_temp.teste_assert_ff(v_sem_antes > 0, 'antes do backfill há linha elegível sem fato (o backfill tem o que fazer)', v_sem_antes::text);
  select count(*) into v_pend_antes from pendencia where tipo = 'conta_canonica_incerta';

  v_r := fn_materializar_fatos_backfill();
  perform pg_temp.teste_assert_ff((v_r->>'fatos_criados')::int = v_sem_antes, 'o backfill cria exatamente um fato por linha elegível que não tinha', (v_r->>'fatos_criados') || ' x ' || v_sem_antes);
  perform pg_temp.teste_assert_ff(not exists (select 1 from _elegiveis e where not exists (select 1 from fato_financeiro f where f.campo_extraido_id = e.campo_id)),
    'depois do backfill TODA linha elegível tem fato');
  select count(*) into v_n from fato_financeiro f where not exists (select 1 from _elegiveis e where e.campo_id = f.campo_extraido_id);
  perform pg_temp.teste_assert_ff(v_n = 0, 'e nenhum fato existe para linha que não é elegível', v_n::text);
  select count(*) into v_n from fato_financeiro;
  perform pg_temp.teste_assert_ff(v_n = (select count(*) from _elegiveis), 'fatos = linhas elegíveis (bijeção)', v_n || ' x ' || (select count(*) from _elegiveis));
  v_r2 := fn_materializar_fatos_backfill();
  perform pg_temp.teste_assert_ff((v_r2->>'fatos_criados')::int = 0, 'o backfill é idempotente: a segunda chamada cria 0', v_r2->>'fatos_criados');
  select count(*) into v_n from fato_financeiro group by campo_extraido_id having count(*) > 1 limit 1;
  perform pg_temp.teste_assert_ff(coalesce(v_n, 0) = 0, 'nenhuma evidência tem dois fatos');
  perform pg_temp.teste_assert_ff((select count(distinct f.documento_versao_id) from fato_financeiro f) >= 20, 'os fatos vêm de várias versões de documento', (select count(distinct documento_versao_id) from fato_financeiro)::text);

  raise notice '--- b. nenhum fato aponta para nó que não é seção ---';
  select count(*) into v_n from fato_financeiro f join conta_canonica c on c.codigo = f.conta_id where c.secao_canonica is null;
  perform pg_temp.teste_assert_ff(v_n = 0, 'nenhum fato aponta para raiz, grupo ou subgrupo', v_n::text);
  select count(*) into v_n from fato_financeiro f join conta_canonica c on c.codigo = f.conta_id where c.secao_canonica is not null;
  perform pg_temp.teste_assert_ff(v_n >= 1000, 'e há fatos com conta de seção (o assert acima não é sobre o vazio)', v_n::text);
  select count(*) into v_n from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id join conta_canonica c on c.codigo = f.conta_id where c.secao_canonica is distinct from ce.secao_canonica;
  perform pg_temp.teste_assert_ff(v_n = 0, 'a conta do fato é a seção que a linha traz, nunca outra', v_n::text);

  raise notice '--- c. o método: declarada, heuristica, sem_conta ---';
  select count(*) into v_n from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where ce.secao_canonica_inferida;
  perform pg_temp.teste_assert_ff(v_n >= 1, 'as fixtures trazem linha com seção inferida elegível (o assert abaixo mede algo)', v_n::text);
  select count(*) into v_n from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where ce.secao_canonica_inferida and f.resolucao_metodo <> 'heuristica';
  perform pg_temp.teste_assert_ff(v_n = 0, 'linha com seção inferida é heuristica', v_n::text);
  select count(*) into v_n from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.resolucao_metodo = 'heuristica' and not ce.secao_canonica_inferida;
  perform pg_temp.teste_assert_ff(v_n = 0, 'e heuristica só existe para seção inferida', v_n::text);
  select count(*) into v_n from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.resolucao_metodo = 'declarada' and (ce.secao_canonica_inferida or ce.secao_canonica is null);
  perform pg_temp.teste_assert_ff(v_n = 0, 'declarada é só o que a IA deu', v_n::text);
  select count(*) into v_n from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where ce.secao_canonica = 'NAO_CLASSIFICAVEL';
  select count(*) into v_n2 from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where ce.secao_canonica = 'NAO_CLASSIFICAVEL' and f.resolucao_metodo = 'sem_conta' and f.conta_id is null and f.sem_conta_motivo = 'secao_nao_declarada';
  perform pg_temp.teste_assert_ff(v_n >= 1 and v_n = v_n2, 'o literal NAO_CLASSIFICAVEL das fixtures vira sem_conta (conta nula, secao_nao_declarada)', v_n2 || ' de ' || v_n);
  select count(*) into v_n from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where ce.secao_canonica is null;
  select count(*) into v_n2 from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where ce.secao_canonica is null and f.resolucao_metodo = 'sem_conta' and f.conta_id is null and f.sem_conta_motivo = 'secao_nao_declarada';
  perform pg_temp.teste_assert_ff(v_n >= 1 and v_n = v_n2, 'a seção nula (o que o extrator grava) é tratada IGUAL ao literal: sem_conta', v_n2 || ' de ' || v_n);
  select count(*) into v_n from fato_financeiro f where f.resolucao_metodo = 'sem_conta' and f.conta_id is not null;
  perform pg_temp.teste_assert_ff(v_n = 0, 'linha sem conta NÃO ganha conta (nem a raiz da demonstração pelo tipo do documento)', v_n::text);
  select count(*) into v_n from fato_financeiro f where f.resolucao_metodo = 'sem_conta';
  perform pg_temp.teste_assert_ff(v_n >= 100, 'e há linhas sem conta nas fixtures (o assert acima mede algo)', v_n::text);

  raise notice '--- e. o backfill não abre pendência e grava o resumo ---';
  select count(*) into v_pend_depois from pendencia where tipo = 'conta_canonica_incerta';
  perform pg_temp.teste_assert_ff(v_pend_depois = v_pend_antes, 'o backfill NÃO abre pendência (heurística e sem conta ficam só no método gravado)', v_pend_antes || ' -> ' || v_pend_depois);
  perform pg_temp.teste_assert_ff((v_r->>'heuristica')::int + (v_r->>'sem_conta')::int > 0 and (v_r->>'linhas_incertas_sem_pendencia')::int = (v_r->>'heuristica')::int + (v_r->>'sem_conta')::int,
    'o resumo conta as linhas incertas que ficaram sem pendência', v_r::text);
  perform pg_temp.teste_assert_ff((v_r->>'pendencias_abertas')::int = 0 and length(v_r->>'porque_sem_pendencia') > 40, 'o resumo diz POR QUE ficaram sem pendência', v_r->>'porque_sem_pendencia');
  select count(*) into v_n from evento_auditoria where acao = 'fato_financeiro_backfill' and ator = 'sistema:migration_0243' and depois = v_r;
  perform pg_temp.teste_assert_ff(v_n = 1, 'o resumo fica em evento_auditoria (fato_financeiro_backfill), com os mesmos números que a função devolveu', v_n::text);
  perform pg_temp.teste_assert_ff((v_r->>'declarada')::int + (v_r->>'heuristica')::int + (v_r->>'sem_conta')::int = (v_r->>'fatos_criados')::int, 'os três métodos somam os fatos criados', v_r::text);
  select count(*) into v_n from fato_financeiro where origem = 'backfill_0243' and resolucao_metodo <> 'declarada';
  perform pg_temp.teste_assert_ff(v_n > 0, 'a incerteza do que já estava gravado fica consultável pela origem backfill_0243 (sem fila de pendência)', v_n::text);

  raise notice '--- f. o que continua só evidência ---';
  select count(*) into v_n from campo_extraido ce join documento_versao dv on dv.id = ce.documento_versao_id join documento d on d.id = dv.documento_id
   where d.tipo_taxonomia in ('ESTOQUE', 'RAZAO', 'AGING_AR', 'AGING_AP', 'MAPA_DIVIDA', 'NOTAS_EXPL', 'FATURAMENTO_24M', 'MUTUOS') and ce.valor_num is not null and fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) = 'conta';
  perform pg_temp.teste_assert_ff(v_n >= 100, 'as fixtures trazem linhas de papel conta em Estoque/Razão/Aging/Mapa de Dívida/Notas/Faturamento/Mútuos (o que fica de fora existe)', v_n::text);
  select count(*) into v_n from fato_financeiro f join documento_versao dv on dv.id = f.documento_versao_id join documento d on d.id = dv.documento_id
   where d.tipo_taxonomia not in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DRE', 'FLUXO_CAIXA', 'DVA', 'DMPL', 'DF_AUDITADA') or d.tipo_taxonomia is null;
  perform pg_temp.teste_assert_ff(v_n = 0, 'nenhum fato nasce de documento fora da lista de demonstrações', v_n::text);
  select count(*) into v_n from campo_extraido ce join documento_versao dv on dv.id = ce.documento_versao_id join documento d on d.id = dv.documento_id
   where d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DRE', 'FLUXO_CAIXA', 'DVA', 'DMPL', 'DF_AUDITADA') and ce.valor_num is not null and fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) = 'subtotal';
  perform pg_temp.teste_assert_ff(v_n >= 50, 'as fixtures trazem subtotais em demonstração (o assert seguinte mede algo)', v_n::text);
  select count(*) into v_n2 from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id join documento_versao dv on dv.id = ce.documento_versao_id join documento d on d.id = dv.documento_id
   where fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) <> 'conta';
  perform pg_temp.teste_assert_ff(v_n2 = 0, 'subtotal (e derivado, e série mensal) não vira fato: é a P28', v_n2::text);
  select count(*) into v_n from campo_extraido ce join documento_versao dv on dv.id = ce.documento_versao_id join documento d on d.id = dv.documento_id
   where d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DRE', 'FLUXO_CAIXA', 'DVA', 'DMPL', 'DF_AUDITADA') and ce.valor_num is null and fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) = 'conta';
  select count(*) into v_n2 from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where ce.valor_num is null;
  perform pg_temp.teste_assert_ff(v_n >= 1 and v_n2 = 0, 'linha de conta SEM valor (célula vazia) não vira fato: ausência não é zero (regra 1)', v_n || ' sem valor; ' || v_n2 || ' viraram fato');
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- d + g. A extração nova e a resolução de entidade e de período, sobre linhas sintéticas (a REGRA, não um documento do cliente).
do $$
declare
  v_caso uuid; v_a uuid; v_b uuid; v_b2 uuid; v_c uuid; v_d uuid; v_e uuid; v_f uuid;
  v_n int; v_txt text; v_p25 uuid; v_p24 uuid; v_beta uuid; v_alfa uuid; v_x record; v_pend record; v_ev jsonb; v_cnt int;
begin
  raise notice '--- d. a extração nova: o ponto do n8n (fn_registrar_campos_extraidos) ---';
  v_caso := (fn_upsert_caso('0243: fato da extração nova'))::uuid;
  v_alfa := fn_upsert_entidade(v_caso, 'ALFA P27 LTDA');
  v_beta := fn_upsert_entidade(v_caso, 'BETA P27 LTDA');
  v_p25 := fn_upsert_periodo(v_caso, 'anual', '2025');
  v_p24 := fn_upsert_periodo(v_caso, 'anual', '2024');

  -- A: só linhas DECLARADAS, com duas colunas de ano (2025 = período do documento; 2024 = outro, que o mandato TEM; 2023 = que o mandato NÃO tem), um subtotal e uma linha sem valor
  v_a := pg_temp.doc(v_caso, 'ALFA P27 LTDA', '2025', 'BALANCO', 'p27-a', jsonb_build_array(
    pg_temp.l('Caixa', '100', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'),
    pg_temp.l('Caixa', '90', 'ativo_circulante', 'ATIVO CIRCULANTE', '2024'),
    pg_temp.l('Fornecedores', '50', 'passivo_circulante', 'PASSIVO CIRCULANTE', '2023'),
    pg_temp.l('Capital social', '10', 'patrimonio_liquido', 'PATRIMÔNIO LÍQUIDO'),
    pg_temp.l('Caixa inicial', '70', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Inicial'),
    pg_temp.l('Total do ativo circulante', '190', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'),
    pg_temp.l('Estoques', 'n/d', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025')));
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_a;
  perform pg_temp.teste_assert_ff(v_n = 5, 'A: 5 fatos (4 contas + a de Saldo Inicial; o subtotal e a linha sem valor ficam fora)', v_n::text);
  select count(*) into v_n from pendencia where tipo = 'conta_canonica_incerta' and caso_id = v_caso;
  perform pg_temp.teste_assert_ff(v_n = 0, 'A: extração só com linhas declaradas abre 0 pendência', v_n::text);
  select count(*) into v_n from evento_auditoria where acao = 'fatos_materializados' and entidade_ref = 'documento_versao:' || v_a;
  perform pg_temp.teste_assert_ff(v_n = 1, 'A: o evento fatos_materializados prova que a materialização RODOU (regra 7)', v_n::text);
  select depois into v_ev from evento_auditoria where acao = 'fatos_materializados' and entidade_ref = 'documento_versao:' || v_a;
  perform pg_temp.teste_assert_ff((v_ev->>'fatos_criados')::int = 5 and (v_ev->>'declarada')::int = 5 and (v_ev->>'materializado')::boolean, 'A: o evento traz os números (5 criados, 5 declaradas)', v_ev::text);

  raise notice '--- g. período e entidade: a coluna da linha vence o documento ---';
  select periodo_id, periodo_origem into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_a and ce.chave = 'Caixa' and ce.periodo_coluna = '2025';
  perform pg_temp.teste_assert_ff(v_x.periodo_id = v_p25 and v_x.periodo_origem = 'coluna', 'coluna 2025 = o período 2025 do mandato (que é também o do documento)', v_x::text);
  select periodo_id, periodo_origem into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_a and ce.chave = 'Caixa' and ce.periodo_coluna = '2024';
  perform pg_temp.teste_assert_ff(v_x.periodo_id = v_p24 and v_x.periodo_id <> (select periodo_id from documento d join documento_versao dv on dv.documento_id = d.id where dv.id = v_a) and v_x.periodo_origem = 'coluna',
    'coluna 2024 numa DOCUMENTO de 2025 = o período 2024: a coluna prevalece sobre o do documento', v_x::text);
  select f.periodo_id, f.periodo_origem, f.periodo_coluna into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_a and ce.chave = 'Fornecedores';
  perform pg_temp.teste_assert_ff(v_x.periodo_id is null and v_x.periodo_origem is null and v_x.periodo_coluna = '2023', 'coluna 2023 sem período no mandato: periodo_id NULO, a coluna fica explícita (o período não é inventado nem criado)', v_x::text);
  perform pg_temp.teste_assert_ff(not exists (select 1 from periodo where caso_id = v_caso and fn_periodo_canonico(tipo, referencia) = '2023'), 'e o período 2023 NÃO foi criado pela materialização');
  select periodo_id, periodo_origem into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_a and ce.chave = 'Capital social';
  perform pg_temp.teste_assert_ff(v_x.periodo_id = v_p25 and v_x.periodo_origem = 'documento', 'linha sem coluna de período: o período do documento', v_x::text);
  select periodo_id, periodo_origem into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_a and ce.chave = 'Caixa inicial';
  perform pg_temp.teste_assert_ff(v_x.periodo_id is null and v_x.periodo_origem is null, 'coluna "Saldo Inicial" é o ano ANTERIOR ao do documento: período NULO, não o do documento', v_x::text);
  select entidade_id, entidade_origem into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_a and ce.chave = 'Capital social';
  perform pg_temp.teste_assert_ff(v_x.entidade_id = v_alfa and v_x.entidade_origem = 'documento', 'sem entidade_coluna: a entidade do documento', v_x::text);

  -- B: heurística (seção inferida do texto da seção bruta), sem seção, seção fora do catálogo, o literal, e as três colunas de entidade
  v_b := pg_temp.doc(v_caso, 'ALFA P27 LTDA', '2025', 'BALANCO', 'p27-b', jsonb_build_array(
    pg_temp.l('Caixa B', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'),
    pg_temp.l('Duplicatas a receber', '20', null, 'ATIVO CIRCULANTE', '2025'),
    pg_temp.l('Conta misteriosa', '30', null, 'Outros', '2025'),
    pg_temp.l('Conta com seção inventada', '40', 'inventada_xyz', 'Outros', '2025'),
    pg_temp.l('Conta escape', '5', 'NAO_CLASSIFICAVEL', 'Outros', '2025'),
    pg_temp.l('Linha da Beta', '7', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'BETA P27 LTDA'),
    pg_temp.l('Linha do combinado', '8', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Combinado'),
    pg_temp.l('Linha da eliminação', '-9', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Eliminações'),
    pg_temp.l('Linha de empresa que ninguém cadastrou', '11', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'GAMA SEM CADASTRO LTDA')));
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_b;
  perform pg_temp.teste_assert_ff(v_n = 9, 'B: 9 fatos (nenhuma linha elegível se perde, incerta ou não)', v_n::text);
  select resolucao_metodo, conta_id, sem_conta_motivo into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_b and ce.chave = 'Duplicatas a receber';
  perform pg_temp.teste_assert_ff(v_x.resolucao_metodo = 'heuristica' and v_x.conta_id = 'ativo_circulante', 'B: seção inferida do texto da seção bruta = heuristica, com a conta inferida', v_x::text);
  select resolucao_metodo, conta_id, sem_conta_motivo into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_b and ce.chave = 'Conta misteriosa';
  perform pg_temp.teste_assert_ff(v_x.resolucao_metodo = 'sem_conta' and v_x.conta_id is null and v_x.sem_conta_motivo = 'secao_nao_declarada', 'B: sem seção (nem inferível) = sem_conta, conta NULA, secao_nao_declarada', v_x::text);
  select resolucao_metodo, conta_id, sem_conta_motivo into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_b and ce.chave = 'Conta com seção inventada';
  perform pg_temp.teste_assert_ff(v_x.resolucao_metodo = 'sem_conta' and v_x.conta_id is null and v_x.sem_conta_motivo = 'secao_fora_do_catalogo', 'B: seção que o catálogo não conhece = sem_conta, secao_fora_do_catalogo (não vira a mais parecida)', v_x::text);
  select resolucao_metodo, conta_id, sem_conta_motivo into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_b and ce.chave = 'Conta escape';
  perform pg_temp.teste_assert_ff(v_x.resolucao_metodo = 'sem_conta' and v_x.sem_conta_motivo = 'secao_nao_declarada', 'B: o literal NAO_CLASSIFICAVEL = sem_conta, igual ao null', v_x::text);
  select entidade_id, entidade_origem into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_b and ce.chave = 'Linha da Beta';
  perform pg_temp.teste_assert_ff(v_x.entidade_id = v_beta and v_x.entidade_origem = 'coluna', 'entidade_coluna que casa UMA entidade do mandato: essa entidade, não a do documento', v_x::text);
  select entidade_id, entidade_origem into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_b and ce.chave = 'Linha do combinado';
  perform pg_temp.teste_assert_ff(v_x.entidade_id = v_alfa and v_x.entidade_origem = 'coluna_total', 'coluna Combinado = a entidade do documento (o total do próprio documento, como fn_coluna_entidade)', v_x::text);
  select f.entidade_id, f.entidade_origem, f.entidade_coluna into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_b and ce.chave = 'Linha da eliminação';
  perform pg_temp.teste_assert_ff(v_x.entidade_id is null and v_x.entidade_origem is null and v_x.entidade_coluna = 'Eliminações', 'coluna Eliminações não é entidade: entidade NULA, a coluna fica explícita (nunca a do documento)', v_x::text);
  select entidade_id, entidade_origem into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_b and ce.chave = 'Linha de empresa que ninguém cadastrou';
  perform pg_temp.teste_assert_ff(v_x.entidade_id is null and v_x.entidade_origem is null, 'entidade_coluna sem entidade no mandato: NULA (a entidade NÃO é criada nem substituída pela do documento)', v_x::text);

  select count(*) into v_n from pendencia where tipo = 'conta_canonica_incerta' and documento_id = (select documento_id from documento_versao where id = v_b) and estado = 'aberta';
  perform pg_temp.teste_assert_ff(v_n = 1, 'B: heurística + sem conta abrem EXATAMENTE 1 pendência para o documento-versão (e não 4, uma por linha)', v_n::text);
  select * into v_pend from pendencia where motivo = 'fato:conta_incerta:' || v_b;
  perform pg_temp.teste_assert_ff(v_pend.severidade = 'complementar' and v_pend.origem_estagio = 'extracao' and v_pend.caso_id = v_caso, 'a pendência é complementar, da extração, do mandato do documento', v_pend.severidade::text);
  perform pg_temp.teste_assert_ff(v_pend.descricao like '4 linha(s)%' and v_pend.descricao like '%Duplicatas a receber%' and v_pend.descricao like '%Conta misteriosa%' and v_pend.descricao like '%Conta com seção inventada%' and v_pend.descricao like '%sem identidade%',
    'a descrição conta as 4 linhas, lista os rótulos e diz o EFEITO (fato sem identidade não entra em seção nenhuma)', v_pend.descricao);

  -- o REENVIO do mesmo arquivo (mesmo hash) é a versão 2 do mesmo documento, com outra linha heurística: abre a SUA pendência
  v_b2 := pg_temp.doc(v_caso, 'ALFA P27 LTDA', '2025', 'BALANCO', 'p27-b', jsonb_build_array(
    pg_temp.l('Caixa B2', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'),
    pg_temp.l('Clientes B2', '12', null, 'ATIVO CIRCULANTE', '2025')));
  perform pg_temp.teste_assert_ff(v_b2 <> v_b and (select documento_id from documento_versao where id = v_b2) = (select documento_id from documento_versao where id = v_b), 'B2: é a segunda versão do MESMO documento (o arranjo do teste)');
  select count(*) into v_n from pendencia where tipo = 'conta_canonica_incerta' and caso_id = v_caso and estado = 'aberta';
  perform pg_temp.teste_assert_ff(v_n = 2, 'uma pendência POR DOCUMENTO-VERSÃO: a v2 abre a dela, a da v1 continua', v_n::text);

  -- reenvio: chamar de novo não duplica a pendência nem o fato
  v_ev := fn_materializar_fatos_da_extracao(v_b);
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_b;
  select count(*) into v_cnt from fato_financeiro where documento_versao_id = v_b;
  perform pg_temp.teste_assert_ff(v_n = 1 and v_cnt = 9 and (v_ev->>'fatos_criados')::int = 0, 'rodar de novo (o reenvio, o reparo) não duplica a pendência nem o fato', v_n || ' pendência(s), ' || v_cnt || ' fatos');

  -- o que a pessoa resolveu não reabre
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'ana@teste' where motivo = 'fato:conta_incerta:' || v_b2;
  perform fn_materializar_fatos_da_extracao(v_b2);
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_b2 and estado <> 'resolvida';
  perform pg_temp.teste_assert_ff(v_n = 0, 'pendência resolvida por PESSOA não é reaberta pelo reenvio', v_n::text);

  -- C: só declaradas num DRE com subtotal; D: tipo fora da lista (Estoque)
  v_c := pg_temp.doc(v_caso, 'ALFA P27 LTDA', '2025', 'DRE', 'p27-c', jsonb_build_array(
    pg_temp.l('Venda de produtos', '1000', 'receita_bruta', 'RECEITA', '2025'),
    pg_temp.l('Receita líquida', '900', 'receita_bruta', 'RECEITA', '2025')));
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_c;
  perform pg_temp.teste_assert_ff(v_n = 1, 'C (DRE): 1 fato; "Receita líquida" é subtotal e fica fora', v_n::text);
  v_d := pg_temp.doc(v_caso, 'ALFA P27 LTDA', '2025', 'ESTOQUE', 'p27-d', jsonb_build_array(
    pg_temp.l('Parafusos', '100', 'ativo_circulante', 'ESTOQUE', '2025'),
    pg_temp.l('Porcas', '50', null, 'ESTOQUE', '2025')));
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_d;
  perform pg_temp.teste_assert_ff(v_n = 0, 'D (Estoque, tipo fora da lista): 0 fato', v_n::text);
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_d;
  perform pg_temp.teste_assert_ff(v_n = 0, 'D: e 0 pendência (linha sem seção de documento que não é demonstração não é fato sem identidade)', v_n::text);
  select count(*) into v_n from evento_auditoria where entidade_ref = 'documento_versao:' || v_d and acao in ('fatos_materializados', 'fatos_materializacao_falhou');
  perform pg_temp.teste_assert_ff(v_n = 0, 'D: nem evento (o tipo não é de demonstração: não rodou e não finge)', v_n::text);

  raise notice '--- d. a falha da materialização NÃO derruba a extração ---';
  create function pg_temp.explode() returns trigger language plpgsql as $f$ begin raise exception 'fato recusado de propósito (teste)'; end $f$;
  create trigger trg_explode before insert on fato_financeiro for each row execute function pg_temp.explode();
  v_e := (fn_registrar_documento(v_caso, 'ALFA P27 LTDA', 'anual', '2025', 'BALANCETE', 0.97, 'nome_arquivo', 'supabase_storage', '0243/p27-e.pdf', 'p27-e.pdf', true, 'p27-e', 'ok')->>'documento_versao_id')::uuid;
  begin
    v_n := fn_registrar_campos_extraidos(v_e, jsonb_build_array(pg_temp.l('Caixa E', '1', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025')));
  exception when others then v_n := -1;   -- a falha do fato derrubou a extração: o assert abaixo reprova (e o resto do arquivo segue)
  end;
  drop trigger trg_explode on fato_financeiro;
  perform pg_temp.teste_assert_ff(v_n = 1 and (select count(*) from campo_extraido where documento_versao_id = v_e) = 1, 'a linha extraída FICA mesmo quando o fato não pôde ser gravado (a evidência vale mais)', v_n::text);
  select count(*) into v_n from evento_auditoria where acao = 'fatos_materializacao_falhou' and entidade_ref = 'documento_versao:' || v_e;
  perform pg_temp.teste_assert_ff(v_n = 1 and (select count(*) from fato_financeiro where documento_versao_id = v_e) = 0, 'e o evento fatos_materializacao_falhou diz que o fato não nasceu (não é falha calada)', v_n::text);
  perform fn_materializar_fatos(v_e);
  perform pg_temp.teste_assert_ff((select count(*) from fato_financeiro where documento_versao_id = v_e) = 1, 'fn_materializar_fatos() repara: cria o fato que faltou', (select count(*) from fato_financeiro where documento_versao_id = v_e)::text);

  raise notice '--- h. o fato segue o documento ---';
  -- A: o período do documento passa de 2025 para 2024 (correção humana de periodo_incorreto); a entidade de ALFA para BETA
  update documento set periodo_id = v_p24 where id = (select documento_id from documento_versao where id = v_a);
  select periodo_id into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_a and ce.chave = 'Capital social';
  perform pg_temp.teste_assert_ff(v_x.periodo_id = v_p24, 'corrigir o período do documento leva o fato que o herdou dele (linha sem coluna)', v_x::text);
  select periodo_id into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_a and ce.chave = 'Caixa' and ce.periodo_coluna = '2025';
  perform pg_temp.teste_assert_ff(v_x.periodo_id = v_p25, 'e NÃO leva o fato cujo período veio de uma COLUNA (a coluna 2025 continua 2025)', v_x::text);
  update documento set entidade_id = v_beta where id = (select documento_id from documento_versao where id = v_a);
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_a and entidade_id = v_beta and entidade_origem = 'documento';
  perform pg_temp.teste_assert_ff(v_n = 5, 'corrigir a entidade do documento leva TODOS os fatos que a herdaram dele', v_n::text);
  update documento set entidade_id = null where id = (select documento_id from documento_versao where id = v_a);
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_a and entidade_id is null and entidade_origem is null;
  perform pg_temp.teste_assert_ff(v_n = 5, 'documento sem entidade: os fatos ficam com entidade NULA e origem NULA (a regra de coerência vale)', v_n::text);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- i. a fusão de entidade leva os fatos (a FK NO ACTION não pode derrubá-la).
do $$
declare
  v_caso uuid; v_g uuid; v_de uuid; v_para uuid; v_ver uuid; v_r jsonb; v_n int;
begin
  raise notice '--- i. a fusão de entidade ---';
  v_caso := (fn_upsert_caso('0243: fusão com fato'))::uuid;
  v_para := fn_upsert_entidade(v_caso, 'GAMA P27 LTDA');
  v_de := fn_upsert_entidade(v_caso, 'DELTA P27 LTDA');
  v_ver := pg_temp.doc(v_caso, 'GAMA P27 LTDA', '2025', 'BALANCO', 'p27-g', jsonb_build_array(
    pg_temp.l('Caixa G', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'),
    pg_temp.l('Caixa da Delta', '20', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'DELTA P27 LTDA')));
  select count(*) into v_n from fato_financeiro where entidade_id = v_de;
  perform pg_temp.teste_assert_ff(v_n = 1, 'a Delta tem 1 fato (pela coluna) antes da fusão', v_n::text);
  begin
    v_r := fn_fundir_entidade(v_caso, v_de, v_para);
  exception when others then v_r := jsonb_build_object('erro', sqlerrm);   -- a FK derrubou a fusão: os asserts abaixo reprovam
  end;
  perform pg_temp.teste_assert_ff(v_r->>'fundida' = 'DELTA P27 LTDA' and (v_r->>'fatos_repontados')::int = 1, 'a fusão NÃO cai na FK de fato_financeiro e conta os fatos repontados', v_r::text);
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_ver and entidade_id = v_para;
  perform pg_temp.teste_assert_ff(v_n = 2 and not exists (select 1 from entidade where id = v_de), 'os 2 fatos ficam na sobrevivente e a absorvida deixa de existir', v_n::text);
  select count(*) into v_n from evento_auditoria where acao = 'entidade_fundida' and entidade_ref = 'entidade:' || v_para and (depois->>'fatos_repontados')::int = 1;
  perform pg_temp.teste_assert_ff(v_n = 1, 'o evento da fusão diz quantos fatos foram repontados', v_n::text);
  select count(*) into v_n from fato_financeiro f where f.entidade_id is not null and not exists (select 1 from entidade e where e.id = f.entidade_id);
  perform pg_temp.teste_assert_ff(v_n = 0, 'nenhum fato fica apontando para entidade que a fusão apagou', v_n::text);

  -- excluir o MANDATO com fatos: a cascata da entidade e a dos fatos (documento > versão > linha > fato) não podem se atropelar (as FKs de dimensão são adiadas)
  begin
    delete from caso where id = v_caso;
    v_n := 0;
  exception when others then v_n := -1;
  end;
  perform pg_temp.teste_assert_ff(v_n = 0 and not exists (select 1 from fato_financeiro where documento_versao_id = v_ver), 'excluir o mandato leva os fatos junto, sem a FK de entidade ou de período atropelar a cascata', v_n::text);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
do $$
declare
  v_uid uuid := gen_random_uuid(); v_ana uuid := gen_random_uuid(); v_caso uuid; v_ver uuid; v_n int; v_tot int; v_t text; v_sem int; v_n2 int;
begin
  raise notice '--- j. o acesso ---';
  select count(*) into v_tot from fato_financeiro;
  insert into auth.users (id, email) values (v_uid, 'ff0243@teste'), (v_ana, 'ana0243@teste');
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_sem from fato_financeiro;
  execute 'reset role';
  perform pg_temp.teste_assert_ff(v_tot > 100 and v_sem = 0, 'usuário sem papel não lê fato nenhum', v_sem || ' de ' || v_tot);
  insert into membro (usuario_id, papel) values (v_uid, 'socio');
  execute 'set local role authenticated';
  select count(*) into v_n from fato_financeiro;
  begin
    update fato_financeiro set valor = 0;
    v_t := 'ok';
  exception when others then v_t := sqlstate;
  end;
  execute 'reset role';
  perform pg_temp.teste_assert_ff(v_n = v_tot, 'o Sócio lê todos os fatos', v_n || ' de ' || v_tot);
  perform pg_temp.teste_assert_ff(v_t = '42501', 'ninguém altera o VALOR do fato (UPDATE só nas colunas de identidade)', v_t);

  -- o Analista alocado materializa pelo caminho do portal (fn_registrar_campos_extraidos como authenticated)
  v_caso := (fn_upsert_caso('0243: acesso do analista'))::uuid;
  insert into membro (usuario_id, papel) values (v_ana, 'analista');
  insert into alocacao (caso_id, usuario_id) values (v_caso, v_ana);
  v_ver := (fn_registrar_documento(v_caso, 'ACESSO P27 LTDA', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage', '0243/p27-h.pdf', 'p27-h.pdf', true, 'p27-h', 'ok')->>'documento_versao_id')::uuid;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_ana, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('chave', 'Caixa H', 'valor_num', '5', 'secao_canonica', 'ativo_circulante', 'secao', 'ATIVO CIRCULANTE', 'confianca', '0.97'),
    jsonb_build_object('chave', 'Conta H sem seção', 'valor_num', '6', 'secao', 'Outros', 'confianca', '0.97')));
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_ver;
  select count(*) into v_n2 from pendencia where motivo = 'fato:conta_incerta:' || v_ver;
  execute 'reset role';
  perform pg_temp.teste_assert_ff(v_n = 2, 'o Analista alocado materializa os fatos pelo caminho do portal (a RLS de insert deixa)', v_n::text);
  perform pg_temp.teste_assert_ff(v_n2 = 1, 'e a pendência da linha sem seção abre também como Analista', v_n2::text);
  perform set_config('request.jwt.claims', '', true);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- k. A sonda: os 18 requisitos presentes; e ela ACUSA cada guarda removida (nos mesmos termos do teste da 0242: a migration é a coisa medida, aqui o estado do banco montado).
do $$
declare v_n int; v_lista text; v_def text; v_ok boolean; v_f int;
begin
  raise notice '--- k. a sonda de instalação ---';
  set constraints all immediate;   -- as FKs de dimensão são adiadas: sem isto o `alter table` abaixo morre em `pending trigger events`
  select count(*), string_agg(chave, ', ') filter (where not presente) into v_n, v_lista from fn_instalacao_conferir() where migration = '0243';
  perform pg_temp.teste_assert_ff(v_n = 18 and v_lista is null, 'os 18 requisitos da 0243 estão no catálogo e presentes', v_n || ' requisitos; ausentes: ' || coalesce(v_lista, 'nenhum'));
  perform pg_temp.teste_assert_ff((select count(*) from instalacao_sonda_fato_financeiro_constraints) = 13, 'as 13 constraints estruturais existem com o predicado esperado', (select count(*) from instalacao_sonda_fato_financeiro_constraints)::text);

  -- cada constraint dropada deixa o requisito ausente (e a guarda de comportamento junto)
  alter table fato_financeiro drop constraint fato_financeiro_conta_metodo_ck;
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_constraints'), 'a sonda acusa a constraint conta-nula-só-com-sem_conta dropada');
  alter table fato_financeiro add constraint fato_financeiro_conta_metodo_ck check ((conta_id is null) = (resolucao_metodo = 'sem_conta'));
  perform pg_temp.teste_assert_ff((select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_constraints'), 'recolocada a constraint, a sonda volta a presente (a acusação era dela)');
  alter table fato_financeiro drop constraint fato_financeiro_campo_extraido_id_key;
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_constraints'), 'a sonda acusa a FK única da evidência dropada (dois fatos por linha passariam)');
  alter table fato_financeiro add constraint fato_financeiro_campo_extraido_id_key unique (campo_extraido_id);

  -- fato numa conta que não é seção
  insert into fato_financeiro (campo_extraido_id, documento_versao_id, conta_id, resolucao_metodo, valor, origem)
    select ce.id, ce.documento_versao_id, 'demo_dre', 'declarada', 1, 'extracao'
      from campo_extraido ce where not exists (select 1 from fato_financeiro f where f.campo_extraido_id = ce.id) limit 1;
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_so_secao'), 'a sonda acusa fato apontando para a RAIZ da demonstração (a identidade é seção)');
  delete from fato_financeiro where conta_id = 'demo_dre';
  perform pg_temp.teste_assert_ff((select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_so_secao'), 'sem o fato na raiz a sonda volta a presente');

  -- a extração recente sem fato: a sonda acusa (é o estágio que não rodou)
  delete from fato_financeiro where documento_versao_id = (select dv.id from documento_versao dv join documento d on d.id = dv.documento_id where fn_tipo_gera_fato(d.tipo_taxonomia) and dv.criada_em = (select max(criada_em) from documento_versao)
                                                              and exists (select 1 from fato_financeiro f where f.documento_versao_id = dv.id) order by dv.id limit 1);
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_extracao_nova_materializa'), 'a sonda acusa a versão mais nova (que passou pela extração) de demonstração SEM fato (estágio que não rodou não parece limpo, regra 7)');
  perform fn_materializar_fatos();
  perform pg_temp.teste_assert_ff((select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_extracao_nova_materializa'), 'o reparo (fn_materializar_fatos) devolve a sonda a presente');

  -- o gatilho do documento desabilitado
  begin
    alter table documento disable trigger trg_fato_segue_o_documento;
  exception when undefined_object then null;   -- gatilho já removido: a sonda o acusa do mesmo jeito
  end;
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_segue_o_documento_gatilho'), 'a sonda acusa o gatilho do documento desabilitado');
  begin
    alter table documento enable trigger trg_fato_segue_o_documento;
  exception when undefined_object then null;
  end;

  -- o corpo de fn_registrar_campos_extraidos antigo (sem a chamada)
  v_def := pg_get_functiondef('fn_registrar_campos_extraidos(uuid,jsonb,nivel_autonomia,text,boolean,jsonb)'::regprocedure);
  execute replace(v_def, 'perform fn_materializar_fatos_da_extracao(p_documento_versao_id);', 'null;');
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'registrar_materializa_fatos'), 'a sonda acusa fn_registrar_campos_extraidos de corpo antigo (sem a chamada que materializa)');
  execute v_def;
  perform pg_temp.teste_assert_ff((select presente from fn_instalacao_conferir() where chave = 'registrar_materializa_fatos'), 'recolocado o corpo, presente');

  v_def := pg_get_functiondef('fn_fundir_entidade(uuid,uuid,uuid,text)'::regprocedure);
  execute replace(v_def, 'fatos_repontados', 'x_repontados');
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fundir_entidade_leva_os_fatos'), 'a sonda acusa fn_fundir_entidade de corpo anterior (que cairia na FK dos fatos)');
  execute v_def;

  v_def := pg_get_functiondef('fn_materializar_fatos(uuid,text)'::regprocedure);
  execute replace(v_def, 'left join conta_canonica c on c.secao_canonica = a.secao', 'left join conta_canonica c on c.codigo = a.tipo');
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'materializa_conta_so_pela_secao'), 'a sonda acusa a materialização que acha a conta por outro critério que a seção');
  execute v_def;
  select count(*) into v_f from fn_instalacao_conferir() where migration = '0243' and not presente;
  perform pg_temp.teste_assert_ff(v_f = 0, 'depois de recolocar tudo, os 18 requisitos estão presentes de novo', v_f::text);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
do $$
declare v_exec bigint := (select last_value from pg_temp._execucoes_0243); v_falhas bigint;
begin
  select case when is_called then last_value else 0 end into v_falhas from pg_temp._falhas_0243;
  raise notice 'fato_financeiro: % asserts executados, % reprovados', v_exec, v_falhas;
  if v_falhas > 0 and coalesce(current_setting('ff.medindo', true), '') <> 'on' then
    raise exception 'FALHOU: % assert(s) da 0243 reprovaram (veja os FALHOU acima)', v_falhas;
  end if;
  if v_falhas = 0 then raise notice 'TODOS OS TESTES DO FATO FINANCEIRO PASSARAM'; end if;
end $$;

rollback;
