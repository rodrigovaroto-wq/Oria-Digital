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
--   (j) o acesso: sem papel lê zero, Sócio lê, o Analista alocado materializa pelo caminho do portal; (k) a sonda: os 32 requisitos presentes e ela ACUSA cada guarda removida (não está cega);
--   (g2) a coluna que não é saldo (A1), o período parcial (A2) e o total que duplica a coluna da entidade (M1); (g3) o tipo do documento (M2), a ordem real registrar-depois-preencher (M3), a versão superada (M4), o cancelamento não engolido (M7), a guarda de mesmo mandato (M5).
--
-- HONESTIDADE (regra 4): as fixtures de vertentes e canastra são sintéticas e não trazem o arranjo que produção traz de linhas com entidade_coluna sem entidade cadastrada nem o de duas colunas de ano de um balanço real;
-- os asserts de (d), (g), (h), (i) usam linhas sintéticas porque provam a REGRA de resolução (qual coluna vence), não reproduzem um documento do cliente. Os números de produção estão na migration, medidos read-only.
--
-- NÃO PARA NO PRIMEIRO ERRO: anota e segue, e o bloco final reprova com a CONTAGEM (regra 2). `PGOPTIONS='-c ff.medindo=on'` só tira o `raise exception` do fim (para a medição por sabotagem).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número que reprova por sabotagem, parte a parte, está no cabeçalho de Supabase/migrations/0243_a_linha_que_nao_tinha_identidade.sql.

-- SEM reaplicar a 0243 aqui (a 3ª tentativa a reaplicava porque o_balanco_sem_dado_financeiro.test.sql devolve fn_registrar_campos_extraidos ao corpo da 0231 e a 0243 vivia dentro dela): desde 12/11/2026 a materialização da extração nova é o gatilho
-- trg_fato_extracao_nova em evento_auditoria, que nenhum teste de outra migration reemite — e o teste da parte (d) prova que ele sobrevive a essa reemissão.
-- O ACL DE PRODUÇÃO (o `pg_default_acl` do dono dá ALL a authenticated e anon em toda tabela nova de public; o banco montado pelo run.sh não tem esse default): simulado aqui com um `grant all` e a migration REAPLICADA — se ela não revogar, o
-- authenticated escreve em fato_financeiro e os asserts da parte j (e a sonda fato_authenticated_so_le) reprovam. A migration é idempotente e o marcador de cobertura não regride (o gatilho de instalacao_cobertura ignora a regressão).
grant all on fato_financeiro to authenticated, anon;
-- E O DEFAULT DE FUNÇÕES (3ª revisão, B7): o Supabase dá EXECUTE ao authenticated e ao anon em toda função nova de public; simulado nas duas funções do serviço e a migration reaplicada tem de revogar.
grant execute on function fn_materializar_fatos(uuid, text), fn_fato_pendencia_da_versao(uuid) to authenticated, anon;
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

-- A INVARIANTE DA FAMÍLIA (4ª revisão, a regra nova do dono: o fato é SEMPRE o recalculado do estado atual): fato_financeiro é IGUAL ao que a materialização do zero daria. Compara (linha, versão, conta, método, motivo da conta, entidade, origem, motivo, coluna, período, origem, motivo, coluna,
-- valor, unidade, moeda), linha a linha, nos dois sentidos — não conta. O que o resolver devolve e não está no fato, mais o que está no fato e o resolver não devolve. Afirmada depois de cada cenário que muda o que o fato lê.
create or replace function pg_temp.divergentes() returns bigint language sql as $f$
  select count(*) from (
    (select campo_id, documento_versao_id, conta_id, resolucao_metodo, sem_conta_motivo, entidade_id, entidade_origem, entidade_motivo, entidade_coluna, periodo_id, periodo_origem, periodo_motivo, periodo_coluna, valor, unidade, moeda from fn_fato_resolver(null)
     except
     select campo_extraido_id, documento_versao_id, conta_id, resolucao_metodo, sem_conta_motivo, entidade_id, entidade_origem, entidade_motivo, entidade_coluna, periodo_id, periodo_origem, periodo_motivo, periodo_coluna, valor, unidade, moeda from fato_financeiro)
    union all
    (select campo_extraido_id, documento_versao_id, conta_id, resolucao_metodo, sem_conta_motivo, entidade_id, entidade_origem, entidade_motivo, entidade_coluna, periodo_id, periodo_origem, periodo_motivo, periodo_coluna, valor, unidade, moeda from fato_financeiro
     except
     select campo_id, documento_versao_id, conta_id, resolucao_metodo, sem_conta_motivo, entidade_id, entidade_origem, entidade_motivo, entidade_coluna, periodo_id, periodo_origem, periodo_motivo, periodo_coluna, valor, unidade, moeda from fn_fato_resolver(null))) x
$f$;
create or replace function pg_temp.inv(p_cenario text) returns void language plpgsql as $f$
declare v_n bigint := pg_temp.divergentes();
begin
  perform pg_temp.teste_assert_ff(v_n = 0, 'INVARIANTE depois de ' || p_cenario || ': fato_financeiro é igual ao que a materialização do zero daria', v_n || ' linha(s) divergentes');
end $f$;

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
create or replace function pg_temp.doc(p_caso uuid, p_ent text, p_per text, p_tipo text, p_hash text, p_campos jsonb, p_ptipo text default 'anual') returns uuid
language plpgsql as $$
declare v uuid;
begin
  v := (fn_registrar_documento(p_caso, p_ent, p_ptipo, p_per, p_tipo, 0.97, 'nome_arquivo', 'supabase_storage', '0243/' || p_hash || '.pdf', p_hash || '.pdf', true, p_hash, 'ok')->>'documento_versao_id')::uuid;
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
  perform pg_temp.inv('o backfill sobre as fixtures');
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- d + g. A extração nova e a resolução de entidade e de período, sobre linhas sintéticas (a REGRA, não um documento do cliente).
do $$
declare
  v_caso uuid; v_a uuid; v_b uuid; v_b2 uuid; v_c uuid; v_d uuid; v_e uuid; v_f uuid; v_f1 uuid; v_f2 uuid;
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

  raise notice '--- d0. a 0243 NÃO toma conta de fn_registrar_campos_extraidos: o `ln` da 0270 continua gravado, e o fato nasce ---';
  -- ARRANJO: este arquivo roda DEPOIS do teste da 0270 no run.sh (o 0270 reaplica a própria migration, então o corpo vigente é o da 0270); se alguém mover o bloco, a primeira linha abaixo reprova em vez de a prova sumir calada.
  perform pg_temp.teste_assert_ff(position('v_ln' in pg_get_functiondef('fn_registrar_campos_extraidos(uuid,jsonb,nivel_autonomia,text,boolean,jsonb)'::regprocedure)) > 0,
    'arranjo: o corpo vigente de fn_registrar_campos_extraidos é o da 0270 (grava ln); este teste tem de rodar depois do da 0270');
  perform pg_temp.teste_assert_ff(position('fn_materializar_fatos' in pg_get_functiondef('fn_registrar_campos_extraidos(uuid,jsonb,nivel_autonomia,text,boolean,jsonb)'::regprocedure)) = 0,
    'fn_registrar_campos_extraidos NÃO chama a materialização: ela mora no gatilho, que nenhuma reemissão da função (a P11 a reemite a cada fatia) leva embora');
  v_f1 := pg_temp.doc(v_caso, 'ALFA P27 LTDA', '2025', 'BALANCO', 'p27-ln', jsonb_build_array(
    pg_temp.l('Caixa LN', '5', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025') || jsonb_build_object('ln', 7),
    pg_temp.l('Clientes LN', '6', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025') || jsonb_build_object('ln', 0)));
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_f1;
  perform pg_temp.teste_assert_ff(v_n = 2, 'a chamada que grava o ln também materializa o fato (as duas coisas na mesma chamada do n8n)', v_n::text);
  select ln into v_n from campo_extraido where documento_versao_id = v_f1 and chave = 'Caixa LN';
  perform pg_temp.teste_assert_ff(v_n = 7, 'e o ln (0270) continua gravado: 7', coalesce(v_n::text, 'nulo'));
  perform pg_temp.teste_assert_ff((select ln from campo_extraido where documento_versao_id = v_f1 and chave = 'Clientes LN') is null, 'e o ln inválido (zero) continua virando nulo, como a 0270 deixou');
  -- a sobrevivência: reemitir fn_registrar a partir do corpo vigente (o que a P11 faz) não derruba a materialização
  execute replace(pg_get_functiondef('fn_registrar_campos_extraidos(uuid,jsonb,nivel_autonomia,text,boolean,jsonb)'::regprocedure), 'v_count := v_count + 1;', 'v_count := v_count + 1; /* reemitida */');
  v_f2 := pg_temp.doc(v_caso, 'ALFA P27 LTDA', '2025', 'BALANCO', 'p27-ln2', jsonb_build_array(pg_temp.l('Caixa LN2', '8', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025')));
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_f2;
  perform pg_temp.teste_assert_ff(v_n = 1 and (select count(*) from evento_auditoria where acao = 'fatos_materializados' and entidade_ref = 'documento_versao:' || v_f2) = 1,
    'reemitida a fn_registrar_campos_extraidos (outra migration da P11), a materialização continua: o evento fatos_materializados e o fato', v_n::text);

  raise notice '--- g. período e entidade: a coluna da linha vence o documento ---';
  select periodo_id, periodo_origem into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_a and ce.chave = 'Caixa' and ce.periodo_coluna = '2025';
  perform pg_temp.teste_assert_ff(v_x.periodo_id = v_p25 and v_x.periodo_origem = 'documento', 'coluna 2025 de um documento de 2025, a ÚNICA coluna do ano do documento: o período do documento', v_x::text);
  select periodo_id, periodo_origem into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_a and ce.chave = 'Caixa' and ce.periodo_coluna = '2024';
  perform pg_temp.teste_assert_ff(v_x.periodo_id = v_p24 and v_x.periodo_id <> (select periodo_id from documento d join documento_versao dv on dv.documento_id = d.id where dv.id = v_a) and v_x.periodo_origem = 'coluna',
    'coluna 2024 numa DOCUMENTO de 2025 = o período 2024: a coluna prevalece sobre o do documento', v_x::text);
  select f.periodo_id, f.periodo_origem, f.periodo_coluna into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_a and ce.chave = 'Fornecedores';
  perform pg_temp.teste_assert_ff(v_x.periodo_id is null and v_x.periodo_origem is null and v_x.periodo_coluna = '2023' and (select f2.periodo_motivo from fato_financeiro f2 join campo_extraido c2 on c2.id = f2.campo_extraido_id where f2.documento_versao_id = v_a and c2.chave = 'Fornecedores') = 'periodo_da_coluna_nao_cadastrado', 'coluna 2023 sem período no mandato: periodo_id NULO, a coluna fica explícita (o período não é inventado nem criado)', v_x::text);
  perform pg_temp.teste_assert_ff(not exists (select 1 from periodo where caso_id = v_caso and fn_periodo_canonico(tipo, referencia) = '2023'), 'e o período 2023 NÃO foi criado pela materialização');
  select periodo_id, periodo_origem into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_a and ce.chave = 'Capital social';
  perform pg_temp.teste_assert_ff(v_x.periodo_id is null and (select f2.periodo_motivo from fato_financeiro f2 join campo_extraido c2 on c2.id = f2.campo_extraido_id where f2.documento_versao_id = v_a and c2.chave = 'Capital social') = 'linha_sem_coluna_em_documento_com_colunas',
    'linha SEM coluna num documento que TEM colunas: período nulo e explicado (a regra de fn_linha_vale_para_ano, 0195: só a coluna escolhida vale)', v_x::text);
  select periodo_id, periodo_origem into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_a and ce.chave = 'Caixa inicial';
  perform pg_temp.teste_assert_ff(v_x.periodo_id is null and v_x.periodo_origem is null and (select f2.periodo_motivo from fato_financeiro f2 join campo_extraido c2 on c2.id = f2.campo_extraido_id where f2.documento_versao_id = v_a and c2.chave = 'Caixa inicial') = 'coluna_de_abertura', 'coluna "Saldo Inicial" é o ano ANTERIOR ao do documento: período NULO e explicado (coluna_de_abertura), não o do documento', v_x::text);
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
  perform pg_temp.teste_assert_ff(v_x.entidade_id is null and v_x.entidade_origem is null and v_x.entidade_coluna = 'Eliminações' and (select f2.entidade_motivo from fato_financeiro f2 join campo_extraido c2 on c2.id = f2.campo_extraido_id where f2.documento_versao_id = v_b and c2.chave = 'Linha da eliminação') = 'coluna_sem_entidade_no_mandato', 'coluna Eliminações não é entidade: entidade NULA, a coluna fica explícita (nunca a do documento)', v_x::text);
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
  perform pg_temp.teste_assert_ff(v_n = 1 and exists (select 1 from pendencia where motivo = 'fato:conta_incerta:' || v_b2 and estado = 'aberta'), 'a v2 (a vigente) abre a SUA pendência, uma por documento-versão', v_n::text);
  perform pg_temp.teste_assert_ff((select resolvida_por from pendencia where motivo = 'fato:conta_incerta:' || v_b) = 'sistema:versao_superada' and (select estado from pendencia where motivo = 'fato:conta_incerta:' || v_b) = 'resolvida',
    'a pendência aberta da v1 SE BAIXA quando a v2 vira a vigente (versão superada), com o autor dizendo por quê');

  -- reenvio: chamar de novo não duplica a pendência nem o fato
  v_ev := fn_materializar_fatos_da_extracao(v_b2);
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_b2;
  select count(*) into v_cnt from fato_financeiro where documento_versao_id = v_b2;
  perform pg_temp.teste_assert_ff(v_n = 1 and v_cnt = 2 and (v_ev->>'fatos_criados')::int = 0, 'rodar de novo (o reenvio, o reparo) não duplica a pendência nem o fato', v_n || ' pendência(s), ' || v_cnt || ' fatos');
  perform fn_materializar_fatos_da_extracao(v_b);
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_b and estado = 'aberta';
  perform pg_temp.teste_assert_ff(v_n = 0, 'a versão superada, rematerializada, NÃO reabre a pendência dela', v_n::text);

  -- o que a pessoa resolveu não reabre
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'ana@teste' where motivo = 'fato:conta_incerta:' || v_b2;
  perform fn_materializar_fatos_da_extracao(v_b2);
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_b2 and estado <> 'resolvida';
  perform pg_temp.teste_assert_ff(v_n = 0, 'pendência resolvida por PESSOA não é reaberta pelo reenvio', v_n::text);
  -- a que alguém está tratando (ou decidiu) não é tocada: nem reaberta, nem baixada pela auto-resolução, nem substituída
  update pendencia set estado = 'em_correcao_interna', resolvida_em = null, resolvida_por = null where motivo = 'fato:conta_incerta:' || v_b2;
  update campo_extraido set secao_canonica = 'ativo_circulante', secao_canonica_inferida = false where documento_versao_id = v_b2 and chave = 'Clientes B2';
  delete from fato_financeiro where documento_versao_id = v_b2;
  perform fn_materializar_fatos_da_extracao(v_b2);
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_b2 and estado = 'em_correcao_interna';
  perform pg_temp.teste_assert_ff(v_n = 1 and (select count(*) from pendencia where motivo = 'fato:conta_incerta:' || v_b2) = 1, 'a pendência em correção interna NÃO é baixada pela auto-resolução (só estado aberta)', v_n::text);

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
  select periodo_id into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_a and ce.chave = 'Caixa' and ce.periodo_coluna = '2024';
  perform pg_temp.teste_assert_ff(v_x.periodo_id = v_p24, 'corrigir o período do documento (agora 2024) leva a coluna 2024, que passa a ser a do documento', v_x::text);
  select periodo_id into v_x from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_a and ce.chave = 'Caixa' and ce.periodo_coluna = '2025';
  perform pg_temp.teste_assert_ff(v_x.periodo_id = v_p25, 'e NÃO leva o fato cujo período veio de uma COLUNA (a coluna 2025 continua 2025)', v_x::text);
  update documento set entidade_id = v_beta where id = (select documento_id from documento_versao where id = v_a);
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_a and entidade_id = v_beta and entidade_origem = 'documento';
  perform pg_temp.teste_assert_ff(v_n = 5, 'corrigir a entidade do documento leva TODOS os fatos que a herdaram dele', v_n::text);
  update documento set entidade_id = null where id = (select documento_id from documento_versao where id = v_a);
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_a and entidade_id is null and entidade_origem is null;
  perform pg_temp.teste_assert_ff(v_n = 5, 'documento sem entidade: os fatos ficam com entidade NULA e origem NULA (a regra de coerência vale)', v_n::text);
  perform pg_temp.inv('as extrações novas, a falha com reparo e a correção do documento (cenários d, g, h)');
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- g2. O CRITÉRIO NOVO: a 0243 não interpreta nome de coluna; só atribui período e entidade quando a função do banco decide de forma INEQUÍVOCA, senão nulo com motivo (os achados A1, A2, M1 e a 2ª revisão, com linhas sintéticas: a REGRA).
do $$
declare
  v_caso uuid; v_hold uuid; v_sub uuid; v_p25 uuid; v_ver uuid; v_n int; v_c2 int; v_s numeric; v_x record; v_pm uuid; v_alfa uuid;
begin
  raise notice '--- g2. período e entidade só quando a função do banco decide ---';
  v_caso := (fn_upsert_caso('0243: colunas do balancete'))::uuid;
  v_hold := fn_upsert_entidade(v_caso, 'HOLDING P27 LTDA');
  v_sub := fn_upsert_entidade(v_caso, 'SUB P27 LTDA');
  v_p25 := fn_upsert_periodo(v_caso, 'anual', '2025');

  -- A1: o balancete de seis colunas (Saldo Anterior 100, Débito 500, Crédito 450, Saldo Atual 150, Variação 50, Orçado 160): só o Saldo Atual é o período do documento
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '2025', 'BALANCETE', 'p27-a1', jsonb_build_array(
    pg_temp.l('Caixa', '100', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Anterior'),
    pg_temp.l('Caixa', '500', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Débito'),
    pg_temp.l('Caixa', '450', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Crédito'),
    pg_temp.l('Caixa', '150', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Atual'),
    pg_temp.l('Caixa', '50', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Variação'),
    pg_temp.l('Caixa', '160', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Orçado')));
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_ver;
  perform pg_temp.teste_assert_ff(v_n = 6, 'A1: as seis colunas viram seis fatos (nenhuma linha é descartada)', v_n::text);
  select sum(f.valor) into v_s from fato_financeiro f where f.documento_versao_id = v_ver and f.periodo_id is not null;
  perform pg_temp.teste_assert_ff(v_s = 150, 'A1: somar o fato da conta no período dá 150 (o Saldo Atual), não 1.310', v_s::text);
  select count(*) into v_n from fato_financeiro f where f.documento_versao_id = v_ver and f.periodo_id is null and f.periodo_origem is null and f.periodo_motivo = 'coluna_nao_e_o_periodo_do_documento';
  perform pg_temp.teste_assert_ff(v_n = 4, 'A1: Débito, Crédito, Variação e Orçado ficam com período NULO e o motivo coluna_nao_e_o_periodo_do_documento', v_n::text);
  perform pg_temp.teste_assert_ff((select f.periodo_motivo from fato_financeiro f where f.documento_versao_id = v_ver and f.periodo_coluna = 'Saldo Anterior') = 'coluna_de_abertura', 'A1: Saldo Anterior segue nulo com o motivo coluna_de_abertura');

  -- documento SEM coluna nenhuma: a linha é do período do documento
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '2025', 'BALANCO', 'p27-sc', jsonb_build_array(pg_temp.l('Caixa SC', '5', 'ativo_circulante', 'ATIVO CIRCULANTE')));
  select f.periodo_id, f.periodo_origem into v_x from fato_financeiro f where f.documento_versao_id = v_ver;
  perform pg_temp.teste_assert_ff(v_x.periodo_id = v_p25 and v_x.periodo_origem = 'documento', 'documento sem coluna de período: o período do documento', v_x::text);

  -- A2 (2ª revisão), balancete de JUNHO com colunas de mês e de data: nenhuma é INEQUÍVOCA (a função desempata ao acaso), então nenhuma recebe o período; antes a soma dava 500
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '06/2025', 'BALANCETE', 'p27-a2', jsonb_build_array(
    pg_temp.l('Receita acumulada', '100', 'receita_bruta', 'RECEITA', 'Mai/2025'),
    pg_temp.l('Receita acumulada', '150', 'receita_bruta', 'RECEITA', 'Jun/2025'),
    pg_temp.l('Receita acumulada', '120', 'receita_bruta', 'RECEITA', '31/05/2025'),
    pg_temp.l('Receita acumulada', '130', 'receita_bruta', 'RECEITA', '30/06/2025')), 'mes');
  select d.periodo_id into v_pm from documento d join documento_versao dv on dv.documento_id = d.id where dv.id = v_ver;
  perform pg_temp.teste_assert_ff(v_pm is not null and v_pm <> v_p25, 'A2: arranjo: o mandato tem o período anual 2025 e o documento é do período parcial 06/2025', v_pm::text);
  select coalesce(sum(f.valor) filter (where f.periodo_id is not null), 0), count(*) filter (where f.periodo_id is not null) into v_s, v_n from fato_financeiro f where f.documento_versao_id = v_ver;
  perform pg_temp.teste_assert_ff(v_n = 0 and v_s = 0, 'A2: Mai/2025, Jun/2025, 31/05/2025 e 30/06/2025: nenhuma recebe o período (antes somavam 500)', v_n || ' com período; soma ' || v_s);
  -- a DRE de junho: Jun/2025, Acumulado 2025, 1T2025, 2T2025 (antes somavam 435)
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '06/2025', 'DRE', 'p27-a2b', jsonb_build_array(
    pg_temp.l('Receita', '100', 'receita_bruta', 'RECEITA', 'Jun/2025'),
    pg_temp.l('Receita', '135', 'receita_bruta', 'RECEITA', 'Acumulado 2025'),
    pg_temp.l('Receita', '80', 'receita_bruta', 'RECEITA', '1T2025'),
    pg_temp.l('Receita', '120', 'receita_bruta', 'RECEITA', '2T2025')), 'mes');
  select count(*) filter (where f.periodo_id is not null) into v_n from fato_financeiro f where f.documento_versao_id = v_ver;
  perform pg_temp.teste_assert_ff(v_n = 0, 'A2: DRE de junho com Jun/2025, Acumulado 2025, 1T2025 e 2T2025: nenhuma recebe o período (antes somavam 435)', v_n::text);
  -- documento PARCIAL com colunas de ANO puro (2025 e 2024) e sem saldo: nem a do ano do documento vale (o acumulado do semestre não é o ano), nem a de outro ano (documento parcial)
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '06/2025', 'BALANCETE', 'p27-a2d', jsonb_build_array(
    pg_temp.l('Receita acumulada', '900', 'receita_bruta', 'RECEITA', '2025'),
    pg_temp.l('Receita acumulada', '700', 'receita_bruta', 'RECEITA', '2024')), 'mes');
  select count(*) filter (where f.periodo_id is not null) into v_n from fato_financeiro f where f.documento_versao_id = v_ver;
  perform pg_temp.teste_assert_ff(v_n = 0, 'A2: balancete de junho com colunas 2025 e 2024 e sem saldo: nenhuma recebe período (documento parcial não dá o ano a coluna nenhuma)', v_n::text);
  -- Saldo Atual 150, Orçado 2025, AV% 2025, Var. 2025 x 2024 (antes somavam 342): só o Saldo Atual
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '06/2025', 'BALANCETE', 'p27-a2c', jsonb_build_array(
    pg_temp.l('Caixa', '150', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Atual'),
    pg_temp.l('Caixa', '160', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Orçado 2025'),
    pg_temp.l('Caixa', '12', 'ativo_circulante', 'ATIVO CIRCULANTE', 'AV% 2025'),
    pg_temp.l('Caixa', '20', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Var. 2025 x 2024')), 'mes');
  select coalesce(sum(f.valor) filter (where f.periodo_id is not null), 0), count(*) filter (where f.periodo_id is not null) into v_s, v_n from fato_financeiro f where f.documento_versao_id = v_ver;
  perform pg_temp.teste_assert_ff(v_s = 150 and v_n = 1 and (select f.periodo_id from fato_financeiro f where f.documento_versao_id = v_ver and f.periodo_coluna = 'Saldo Atual') = v_pm, 'A2: Saldo Atual + Orçado 2025 + AV% 2025 + Var. 2025 x 2024: só o Saldo Atual recebe o período (150, não 342)', v_n || ' com período; soma ' || v_s);

  -- DUAS candidatas a ser a coluna do período do documento: nenhuma é escolhida (a escolha seria ao acaso, e ao acaso é número fabricado). Duas colunas de SALDO (Saldo Final e Saldo Atual)...
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '2025', 'BALANCETE', 'p27-sd', jsonb_build_array(
    pg_temp.l('Caixa SD', '100', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Final'),
    pg_temp.l('Caixa SD', '150', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Atual')));
  select count(*) filter (where f.periodo_id is not null), count(*) into v_n, v_c2 from fato_financeiro f where f.documento_versao_id = v_ver;
  perform pg_temp.teste_assert_ff(v_c2 = 2 and v_n = 0, 'duas colunas de SALDO (Saldo Final e Saldo Atual): nenhuma recebe o período do documento (qual delas é o saldo?)', v_n || ' com período de ' || v_c2);
  -- ... e duas colunas que nomeiam o ano do documento (2025 e 31/12/2025) num documento que não é parcial
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '2025', 'BALANCO', 'p27-ad', jsonb_build_array(
    pg_temp.l('Caixa AD', '100', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'),
    pg_temp.l('Caixa AD', '101', 'ativo_circulante', 'ATIVO CIRCULANTE', '31/12/2025')));
  select count(*) filter (where f.periodo_id is not null), count(*) filter (where f.periodo_motivo = 'mais_de_uma_coluna_para_o_mesmo_periodo') into v_n, v_c2 from fato_financeiro f where f.documento_versao_id = v_ver;
  perform pg_temp.teste_assert_ff(v_n = 0 and v_c2 = 2, 'duas colunas do ano do documento (2025 e 31/12/2025): nenhuma recebe o período, motivo mais_de_uma_coluna_para_o_mesmo_periodo', v_n || ' com período; ' || v_c2 || ' com o motivo');

  -- M1 + 2ª revisão (entidade pela função do banco): o COMBINADO da HOLDING com colunas por empresa, eliminações, total das eliminações e consolidado
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '2025', 'COMBINADO', 'p27-m1', jsonb_build_array(
    pg_temp.l('Caixa M1', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'HOLDING P27 LTDA'),
    pg_temp.l('Caixa M1', '20', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'SUB P27 LTDA'),
    pg_temp.l('Caixa M1', '-5', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Eliminações'),
    pg_temp.l('Caixa M1', '-5', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Total Eliminações'),
    pg_temp.l('Caixa M1', '25', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Consolidado')));
  select sum(f.valor) into v_s from fato_financeiro f where f.documento_versao_id = v_ver and f.entidade_id = v_hold;
  perform pg_temp.teste_assert_ff(v_s = 10, 'M1: a HOLDING recebe só a coluna dela (10), não 10 + 25 + (-5)', v_s::text);
  select sum(f.valor) into v_s from fato_financeiro f where f.documento_versao_id = v_ver and f.entidade_id = v_sub;
  perform pg_temp.teste_assert_ff(v_s = 20, 'a SUB recebe a coluna dela (20)', v_s::text);
  select count(*) into v_n from fato_financeiro f where f.documento_versao_id = v_ver and f.entidade_id is null and f.entidade_motivo in ('coluna_total_nao_escolhida', 'coluna_sem_entidade_no_mandato');
  perform pg_temp.teste_assert_ff(v_n = 3, 'as colunas Eliminações, Total Eliminações e Consolidado ficam sem entidade, com o motivo', v_n::text);

  -- duas colunas TOTAL (Consolidado e Total Geral) e nenhuma coluna da própria HOLDING: fn_coluna_entidade entrega "a" total sem ordem, então a escolha é arbitrária e nenhuma vale
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '2025', 'COMBINADO', 'p27-e2', jsonb_build_array(
    pg_temp.l('Caixa E2', '25', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Consolidado'),
    pg_temp.l('Caixa E2', '30', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Total Geral')));
  select count(*) into v_n from fato_financeiro f where f.documento_versao_id = v_ver and f.entidade_id is null and f.entidade_motivo in ('coluna_total_ambigua', 'coluna_total_nao_escolhida');
  perform pg_temp.teste_assert_ff(v_n = 2 and exists (select 1 from fato_financeiro f where f.documento_versao_id = v_ver and f.entidade_motivo = 'coluna_total_ambigua'),
    'duas colunas total e nenhuma da entidade: nenhuma é a do dono (a que a função escolhe é coluna_total_ambigua, a outra coluna_total_nao_escolhida)', v_n::text);
  -- documento que TEM coluna de entidade: a linha SEM coluna de entidade não tem dono inequívoco
  v_ver := pg_temp.doc(v_caso, 'HOLDING P27 LTDA', '2025', 'COMBINADO', 'p27-e3', jsonb_build_array(
    pg_temp.l('Caixa E3', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'HOLDING P27 LTDA'),
    pg_temp.l('Caixa E3', '7', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025')));
  select count(*) into v_n from fato_financeiro f where f.documento_versao_id = v_ver and f.entidade_id is null and f.entidade_motivo = 'linha_sem_coluna_em_documento_com_colunas_de_entidade';
  perform pg_temp.teste_assert_ff(v_n = 1, 'a linha sem entidade_coluna num documento com colunas de entidade fica sem entidade (não soma ao dono)', v_n::text);

  -- 2ª revisão: o nome da coluna é abreviado em relação à razão social ("Alfa Comércio" x "ALFA COMERCIO DE ALIMENTOS LTDA"): fn_mesma_entidade casa, a igualdade de nome não casava
  v_alfa := fn_upsert_entidade(v_caso, 'ALFA COMERCIO DE ALIMENTOS LTDA');
  v_ver := pg_temp.doc(v_caso, 'ALFA COMERCIO DE ALIMENTOS LTDA', '2025', 'COMBINADO', 'p27-alfa', jsonb_build_array(
    pg_temp.l('Caixa ALFA', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio'),
    pg_temp.l('Caixa ALFA', '25', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Consolidado')));
  select sum(f.valor) into v_s from fato_financeiro f where f.documento_versao_id = v_ver and f.entidade_id = v_alfa;
  perform pg_temp.teste_assert_ff(v_s = 10 and (select f.entidade_origem from fato_financeiro f where f.documento_versao_id = v_ver and f.entidade_coluna = 'Alfa Comércio') = 'coluna', 'a coluna "Alfa Comércio" é da ALFA COMERCIO DE ALIMENTOS LTDA (10); o Consolidado não vira dela de novo', v_s::text);
  perform pg_temp.teste_assert_ff((select f.entidade_id from fato_financeiro f where f.documento_versao_id = v_ver and f.entidade_coluna = 'Consolidado') is null, 'e o Consolidado fica sem entidade (a ALFA já tem a coluna dela)');
  perform pg_temp.inv('os cenários do balancete (500, 435, 342), o combinado, as duas colunas de total e o "Alfa Comércio"');
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- g3. O fato segue o TIPO do documento; a ORDEM real (registrar, depois preencher entidade e período); a pendência da versão superada; o cancelamento não é engolido.
do $$
declare
  v_caso uuid; v_ent uuid; v_per uuid; v_r uuid; v_k1 uuid; v_k2 uuid; v_doc uuid; v_n int; v_n2 int; v_t text; v_v1 uuid; v_v2 uuid; v_ev int; v_dif int;
begin
  raise notice '--- g3. tipo do documento, ordem real, versão superada, cancelamento ---';
  v_caso := (fn_upsert_caso('0243: tipo e ordem'))::uuid;
  v_ent := fn_upsert_entidade(v_caso, 'ORDEM P27 LTDA');
  v_per := fn_upsert_periodo(v_caso, 'anual', '2025');

  -- M2: Razão (só evidência) reclassificada para Balancete gera os fatos; de volta para Razão, os remove (a evidência fica)
  v_r := pg_temp.doc(v_caso, 'ORDEM P27 LTDA', '2025', 'RAZAO', 'p27-m2', jsonb_build_array(
    pg_temp.l('Caixa R', '5', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'),
    pg_temp.l('Conta sem seção R', '6', null, 'Outros', '2025')));
  select documento_id into v_doc from documento_versao where id = v_r;
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_r;
  perform pg_temp.teste_assert_ff(v_n = 0, 'M2: documento de Razão não tem fato', v_n::text);
  update documento set tipo_taxonomia = 'BALANCETE' where id = v_doc;
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_r;
  perform pg_temp.teste_assert_ff(v_n = 2, 'M2: RAZAO -> BALANCETE materializa os 2 fatos', v_n::text);
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_r and estado = 'aberta';
  perform pg_temp.teste_assert_ff(v_n = 1, 'M2: e abre a pendência da linha sem conta (como a extração nova)', v_n::text);
  update documento set tipo_taxonomia = 'RAZAO' where id = v_doc;
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_r;
  select count(*) into v_n2 from campo_extraido where documento_versao_id = v_r;
  perform pg_temp.teste_assert_ff(v_n = 0 and v_n2 = 2, 'M2: BALANCETE -> RAZAO remove os fatos (derivados) e a evidência (as 2 linhas) FICA', v_n || ' fatos, ' || v_n2 || ' linhas');
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_r and estado = 'aberta';
  perform pg_temp.teste_assert_ff(v_n = 0, 'M2: e baixa a pendência aberta do documento que deixou de ser de demonstração', v_n::text);
  select count(*) into v_n from evento_auditoria where acao = 'fatos_removidos_por_reclassificacao' and entidade_ref = 'documento:' || v_doc and (depois->>'fatos_removidos')::int = 2;
  perform pg_temp.teste_assert_ff(v_n = 1, 'M2: o evento fatos_removidos_por_reclassificacao grava quantos', v_n::text);

  -- M3: a ORDEM REAL do n8n: as linhas chegam ANTES de o documento ter entidade e período (o diagnóstico preenche depois). O resultado tem de ser o da ordem inversa.
  v_k1 := pg_temp.doc(v_caso, 'ORDEM P27 LTDA', '2025', 'BALANCO', 'p27-k1', jsonb_build_array(
    pg_temp.l('Caixa K', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Atual', 'Consolidado'),
    pg_temp.l('Estoque K', '20', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Atual', 'Consolidado')));
  v_k2 := (fn_registrar_documento(v_caso, 'ORDEM P27 LTDA', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage', '0243/p27-k2.pdf', 'p27-k2.pdf', true, 'p27-k2', 'ok')->>'documento_versao_id')::uuid;
  select documento_id into v_doc from documento_versao where id = v_k2;
  update documento set entidade_id = null, periodo_id = null where id = v_doc;
  perform fn_registrar_campos_extraidos(v_k2, jsonb_build_array(
    pg_temp.l('Caixa K', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Atual', 'Consolidado'),
    pg_temp.l('Estoque K', '20', 'ativo_circulante', 'ATIVO CIRCULANTE', 'Saldo Atual', 'Consolidado')));
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_k2 and entidade_id is null and periodo_id is null and entidade_motivo is not null and periodo_motivo is not null;
  perform pg_temp.teste_assert_ff(v_n = 2, 'M3: com o documento ainda sem entidade e período, os fatos ficam NULOS e explicados', v_n::text);
  update documento set entidade_id = v_ent, periodo_id = v_per where id = v_doc;
  select count(*) into v_dif from (
    select ce.chave, f.entidade_id, f.entidade_origem, f.entidade_motivo, f.periodo_id, f.periodo_origem, f.periodo_motivo
      from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_k1
    except
    select ce.chave, f.entidade_id, f.entidade_origem, f.entidade_motivo, f.periodo_id, f.periodo_origem, f.periodo_motivo
      from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_k2) x;
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_k2 and entidade_id = v_ent and periodo_id = v_per;
  perform pg_temp.teste_assert_ff(v_dif = 0 and v_n = 2, 'M3: preencher a entidade e o período DEPOIS dá a mesma identidade da ordem inversa (a coluna Consolidado incluída)', v_dif || ' linhas diferentes; ' || v_n || ' completas');

  -- M4: a versão superada. v1 com linha sem seção abre a pendência; v2 limpa vira a vigente: a da v1 se baixa e nenhuma fica aberta
  v_v1 := pg_temp.doc(v_caso, 'ORDEM P27 LTDA', '2025', 'BALANCO', 'p27-m4', jsonb_build_array(
    pg_temp.l('Caixa M4', '1', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'),
    pg_temp.l('Conta M4 sem seção', '2', null, 'Outros', '2025')));
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_v1 and estado = 'aberta';
  perform pg_temp.teste_assert_ff(v_n = 1, 'M4: a v1 com linha sem seção abre a pendência', v_n::text);
  v_v2 := pg_temp.doc(v_caso, 'ORDEM P27 LTDA', '2025', 'BALANCO', 'p27-m4', jsonb_build_array(
    pg_temp.l('Caixa M4', '1', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'),
    pg_temp.l('Conta M4 com seção', '2', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025')));
  select count(*) into v_n from pendencia where documento_id = (select documento_id from documento_versao where id = v_v1) and estado = 'aberta' and motivo like 'fato:conta_incerta:%';
  perform pg_temp.teste_assert_ff(v_n = 0 and v_v2 <> v_v1 and fn_versao_atual((select documento_id from documento_versao where id = v_v1)) = v_v2, 'M4: a v2 limpa vira a vigente e NENHUMA pendência da heurística fica aberta no documento', v_n::text);

  perform pg_temp.inv('a troca de tipo, a ordem real (registrar, depois preencher) e a versão superada');

  -- M7: o cancelamento (statement_timeout, query_canceled) NÃO é engolido: a falha comum vira evento, o cancelamento sobe
  create function pg_temp.cancela() returns trigger language plpgsql as $f$ begin raise exception 'cancelado de propósito (teste)' using errcode = '57014'; end $f$;
  create trigger trg_cancela before insert on fato_financeiro for each row execute function pg_temp.cancela();
  v_r := (fn_registrar_documento(v_caso, 'ORDEM P27 LTDA', 'anual', '2025', 'BALANCETE', 0.97, 'nome_arquivo', 'supabase_storage', '0243/p27-m7.pdf', 'p27-m7.pdf', true, 'p27-m7', 'ok')->>'documento_versao_id')::uuid;
  begin
    perform fn_registrar_campos_extraidos(v_r, jsonb_build_array(pg_temp.l('Caixa M7', '1', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025')));
    v_t := 'engolido';
  exception when query_canceled or others then v_t := sqlstate;   -- `others` NÃO inclui query_canceled
  end;
  drop trigger trg_cancela on fato_financeiro;
  select count(*) into v_ev from evento_auditoria where acao = 'fatos_materializacao_falhou' and entidade_ref = 'documento_versao:' || v_r;
  perform pg_temp.teste_assert_ff(v_t = '57014' and v_ev = 0, 'M7: query_canceled sobe ao chamador (não vira evento fatos_materializacao_falhou)', v_t || ', eventos ' || v_ev);

  -- M5: a entidade e o período do fato são do MESMO mandato do documento (guarda do banco, também contra o serviço)
  begin
    update fato_financeiro set periodo_id = (select id from periodo where caso_id <> v_caso limit 1), periodo_origem = 'coluna', periodo_motivo = null, periodo_coluna = periodo_coluna
     where documento_versao_id = v_v2;
    v_t := 'ok';
  exception when others then v_t := sqlstate;
  end;
  perform pg_temp.teste_assert_ff(v_t = '23514', 'M5: período de OUTRO mandato num fato é recusado (check_violation)', v_t);
  begin
    update fato_financeiro set entidade_id = (select id from entidade where caso_id <> v_caso limit 1), entidade_origem = 'coluna', entidade_motivo = null
     where documento_versao_id = v_v2;
    v_t := 'ok';
  exception when others then v_t := sqlstate;
  end;
  perform pg_temp.teste_assert_ff(v_t = '23514', 'M5: entidade de OUTRO mandato num fato é recusada (check_violation)', v_t);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- g4. O "nulo com motivo" não pode ficar FALSO: período ou entidade cadastrado depois re-resolve os fatos nulos (gatilho) e fn_materializar_fatos() re-resolve os existentes (reparo).
do $$
declare
  v_caso uuid; v_ent uuid; v_p25 uuid; v_p23 uuid; v_f uuid; v_ver uuid; v_ver2 uuid; v_x record; v_r jsonb; v_n int;
begin
  raise notice '--- g4. cadastro depois re-resolve o nulo ---';
  v_caso := (fn_upsert_caso('0243: cadastro depois'))::uuid;
  v_ent := fn_upsert_entidade(v_caso, 'CAD P27 LTDA');
  v_p25 := fn_upsert_periodo(v_caso, 'anual', '2025');
  v_ver := pg_temp.doc(v_caso, 'CAD P27 LTDA', '2025', 'BALANCO', 'p27-cad', jsonb_build_array(
    pg_temp.l('Caixa CAD', '1', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'FILHA CAD P27 LTDA'),
    pg_temp.l('Caixa CAD', '2', 'ativo_circulante', 'ATIVO CIRCULANTE', '2023')));
  select f.periodo_id, f.periodo_motivo into v_x from fato_financeiro f where f.documento_versao_id = v_ver and f.periodo_coluna = '2023';
  perform pg_temp.teste_assert_ff(v_x.periodo_id is null and v_x.periodo_motivo = 'periodo_da_coluna_nao_cadastrado', 'antes do cadastro: a coluna 2023 fica nula, periodo_da_coluna_nao_cadastrado', v_x::text);
  select f.entidade_id, f.entidade_motivo into v_x from fato_financeiro f where f.documento_versao_id = v_ver and f.entidade_coluna = 'FILHA CAD P27 LTDA';
  perform pg_temp.teste_assert_ff(v_x.entidade_id is null and v_x.entidade_motivo = 'coluna_sem_entidade_no_mandato', 'antes do cadastro: a coluna FILHA fica sem entidade, coluna_sem_entidade_no_mandato', v_x::text);
  v_p23 := fn_upsert_periodo(v_caso, 'anual', '2023');
  select f.periodo_id, f.periodo_origem, f.periodo_motivo into v_x from fato_financeiro f where f.documento_versao_id = v_ver and f.periodo_coluna = '2023';
  perform pg_temp.teste_assert_ff(v_x.periodo_id = v_p23 and v_x.periodo_origem = 'coluna' and v_x.periodo_motivo is null, 'cadastrar o período 2023 DEPOIS re-resolve o fato nulo (o gatilho do cadastro)', v_x::text);
  v_f := fn_upsert_entidade(v_caso, 'FILHA CAD P27 LTDA');
  select f.entidade_id, f.entidade_origem into v_x from fato_financeiro f where f.documento_versao_id = v_ver and f.entidade_coluna = 'FILHA CAD P27 LTDA';
  perform pg_temp.teste_assert_ff(v_x.entidade_id = v_f and v_x.entidade_origem = 'coluna', 'cadastrar a entidade FILHA depois re-resolve o fato nulo', v_x::text);

  -- o reparo: com os gatilhos de cadastro desligados o nulo fica; fn_materializar_fatos() o re-resolve
  begin
    alter table periodo disable trigger trg_fato_cadastro_periodo;
  exception when undefined_object then null;   -- gatilho já removido
  end;
  v_ver2 := pg_temp.doc(v_caso, 'CAD P27 LTDA', '2025', 'BALANCO', 'p27-cad2', jsonb_build_array(pg_temp.l('Caixa CAD2', '3', 'ativo_circulante', 'ATIVO CIRCULANTE', '2022'), pg_temp.l('Caixa CAD2', '4', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025')));
  perform fn_upsert_periodo(v_caso, 'anual', '2022');
  begin
    alter table periodo enable trigger trg_fato_cadastro_periodo;
  exception when undefined_object then null;
  end;
  select count(*) into v_n from fato_financeiro f where f.documento_versao_id = v_ver2 and f.periodo_coluna = '2022' and f.periodo_id is null;
  perform pg_temp.teste_assert_ff(v_n = 1, 'sem o gatilho de cadastro o nulo continua (o arranjo do reparo)', v_n::text);
  v_r := fn_materializar_fatos();
  select count(*) into v_n from fato_financeiro f where f.documento_versao_id = v_ver2 and f.periodo_coluna = '2022' and f.periodo_id is not null and f.periodo_origem = 'coluna';
  perform pg_temp.teste_assert_ff(v_n = 1 and (v_r->>'atualizados')::int >= 1, 'fn_materializar_fatos() RECALCULA os fatos existentes (o de identidade nula que o gatilho de cadastro não pegou)', v_r::text);
  perform pg_temp.inv('cadastrar período e entidade depois, e o reparo');
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- g5. A 3ª revisão independente: duas colunas da mesma entidade (ALTO 1), o tipo que muda entre dois da lista (ALTO 2), a entidade renomeada ou a 2ª que casa (M4) e o default de função (B7).
do $$
declare
  v_caso uuid; v_alfa uuid; v_v1 uuid; v_v2 uuid; v_n int; v_s numeric; v_dif int; v_doc uuid; v_beta uuid; v_g1 uuid;
begin
  raise notice '--- g5. 3ª revisão ---';
  -- ALTO 1: o mandato tem "ALFA COMERCIO LTDA"; o COMBINADO traz "Alfa Comércio Atacado" (empresa que ninguém cadastrou) E "Alfa Comércio": as duas casam o nome da ALFA e fn_coluna_entidade (limit 1, sem order by) escolhia pela ordem física
  v_caso := fn_upsert_caso('0243: duas colunas da mesma entidade')::uuid;
  v_alfa := fn_upsert_entidade(v_caso, 'ALFA COMERCIO LTDA');
  perform fn_upsert_periodo(v_caso, 'anual', '2025');
  -- ORDEM 1: a coluna do Atacado primeiro
  v_v1 := pg_temp.doc(v_caso, 'ALFA COMERCIO LTDA', '2025', 'COMBINADO', 'r3-a1', jsonb_build_array(
    pg_temp.l('Caixa', '7', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio Atacado'), pg_temp.l('Clientes', '70', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio Atacado'),
    pg_temp.l('Caixa', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio'), pg_temp.l('Clientes', '100', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio'),
    pg_temp.l('Caixa', '17', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Consolidado'), pg_temp.l('Clientes', '170', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Consolidado')));
  -- ORDEM 2: a coluna da ALFA primeiro
  v_v2 := pg_temp.doc(v_caso, 'ALFA COMERCIO LTDA', '2025', 'COMBINADO', 'r3-a2', jsonb_build_array(
    pg_temp.l('Caixa', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio'), pg_temp.l('Clientes', '100', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio'),
    pg_temp.l('Caixa', '7', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio Atacado'), pg_temp.l('Clientes', '70', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio Atacado'),
    pg_temp.l('Caixa', '17', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Consolidado'), pg_temp.l('Clientes', '170', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Consolidado')));
  select coalesce(sum(f.valor), 0) into v_s from fato_financeiro f where f.documento_versao_id = v_v1 and f.entidade_id = v_alfa;
  perform pg_temp.teste_assert_ff(v_s = 0, 'ALTO 1, ordem 1: com duas colunas que casam a ALFA, a ALFA não recebe NENHUMA delas (antes: 77, a soma das duas colunas de caixa e clientes de uma delas)', v_s::text);
  select coalesce(sum(f.valor), 0) into v_s from fato_financeiro f where f.documento_versao_id = v_v2 and f.entidade_id = v_alfa;
  perform pg_temp.teste_assert_ff(v_s = 0, 'ALTO 1, ordem 2: o mesmo com as colunas gravadas na ordem inversa (o resultado não depende da ordem física)', v_s::text);
  select count(*) into v_n from fato_financeiro f where f.documento_versao_id in (v_v1, v_v2) and f.entidade_id is null and f.entidade_motivo = 'entidade_com_varias_colunas';
  perform pg_temp.teste_assert_ff(v_n = 8, 'ALTO 1: as 4 linhas de cada coluna ficam sem entidade com o motivo PRÓPRIO entidade_com_varias_colunas (e não o falso coluna_sem_entidade_no_mandato)', v_n::text);
  select count(*) into v_dif from (
    select ce.chave, f.entidade_coluna, f.entidade_id, f.entidade_origem, f.entidade_motivo from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_v1
    except select ce.chave, f.entidade_coluna, f.entidade_id, f.entidade_origem, f.entidade_motivo from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_v2) x;
  perform pg_temp.teste_assert_ff(v_dif = 0, 'ALTO 1: as duas ordens de gravação dão a MESMA identidade, linha a linha', v_dif::text);

  -- ALTO 2: o tipo muda entre dois da lista. Re-resolver depois da mudança tem de dar o que materializar do zero dá.
  v_caso := fn_upsert_caso('0243: tipo entre dois da lista')::uuid;
  perform fn_upsert_entidade(v_caso, 'TIPO P27 LTDA'); perform fn_upsert_periodo(v_caso, 'anual', '2025'); perform fn_upsert_periodo(v_caso, 'anual', '2024');
  v_v1 := pg_temp.doc(v_caso, 'TIPO P27 LTDA', '2025', 'DRE', 'r3-t1', jsonb_build_array(
    pg_temp.l('Receita', '1200', 'receita_bruta', 'RECEITA', '2025'), pg_temp.l('Receita', '900', 'receita_bruta', 'RECEITA', '2024')));
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_v1 and periodo_id is not null;
  perform pg_temp.teste_assert_ff(v_n = 2, 'arranjo do ALTO 2: o DRE de 2025 com as colunas 2025 e 2024 tem os dois períodos', v_n::text);
  select documento_id into v_doc from documento_versao where id = v_v1;
  update documento set tipo_taxonomia = 'BALANCETE' where id = v_doc;
  v_v2 := pg_temp.doc(v_caso, 'TIPO P27 LTDA', '2025', 'BALANCETE', 'r3-t2', jsonb_build_array(
    pg_temp.l('Receita', '1200', 'receita_bruta', 'RECEITA', '2025'), pg_temp.l('Receita', '900', 'receita_bruta', 'RECEITA', '2024')));
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_v1 and periodo_id is not null;
  perform pg_temp.teste_assert_ff(v_n = 0, 'ALTO 2: DRE -> BALANCETE (os dois na lista, BALANCETE é parcial) NÃO deixa os fatos com o período de antes', v_n::text);
  select count(*) into v_dif from (
    select ce.chave, f.periodo_coluna, f.periodo_id, f.periodo_origem, f.periodo_motivo, f.entidade_id from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_v1
    except select ce.chave, f.periodo_coluna, f.periodo_id, f.periodo_origem, f.periodo_motivo, f.entidade_id from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where f.documento_versao_id = v_v2) x;
  perform pg_temp.teste_assert_ff(v_dif = 0, 'ALTO 2, a INVARIANTE: re-resolver depois de mudar o tipo dá a mesma identidade que materializar do zero um documento já desse tipo', v_dif::text);

  -- M4: a entidade renomeada, e a 2ª entidade que casa uma coluna já atribuída
  v_caso := fn_upsert_caso('0243: entidade renomeada')::uuid;
  perform fn_upsert_entidade(v_caso, 'MATRIZ M4 LTDA'); v_beta := fn_upsert_entidade(v_caso, 'BETA INDUSTRIA LTDA'); perform fn_upsert_periodo(v_caso, 'anual', '2025');
  v_g1 := fn_upsert_entidade(v_caso, 'GAMA SERVICOS LTDA');
  v_v1 := pg_temp.doc(v_caso, 'MATRIZ M4 LTDA', '2025', 'COMBINADO', 'r3-m4', jsonb_build_array(
    pg_temp.l('Caixa', '7', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Beta Indústria'), pg_temp.l('Caixa', '3', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Gama Serviços'),
    pg_temp.l('Caixa', '99', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'MATRIZ M4 LTDA')));
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_v1 and entidade_id = v_beta;
  perform pg_temp.teste_assert_ff(v_n = 1, 'arranjo do M4: a coluna "Beta Indústria" é da BETA INDUSTRIA LTDA', v_n::text);
  update entidade set razao_social = 'DELTA SERVICOS LTDA' where id = v_beta;
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_v1 and entidade_id = v_beta;
  perform pg_temp.teste_assert_ff(v_n = 0 and exists (select 1 from fato_financeiro f where f.documento_versao_id = v_v1 and f.entidade_coluna = 'Beta Indústria' and f.entidade_id is null and f.entidade_motivo = 'coluna_sem_entidade_no_mandato'),
    'M4: renomear a entidade tira dela os fatos da coluna que não é mais o nome dela (antes ficavam na entidade renomeada)', v_n::text);
  insert into entidade (caso_id, razao_social) values (v_caso, 'GAMA SERVICOS HOLDING SA');   -- fn_upsert_entidade a fundiria com a GAMA SERVICOS LTDA (casamento por nome); o insert direto é o cadastro que o upsert não impede
  perform pg_temp.teste_assert_ff(exists (select 1 from fato_financeiro f where f.documento_versao_id = v_v1 and f.entidade_coluna = 'Gama Serviços' and f.entidade_id is null and f.entidade_motivo = 'coluna_casa_varias_entidades'),
    'M4: cadastrar uma 2ª entidade que casa a coluna "Gama Serviços" já atribuída a outra a torna coluna_casa_varias_entidades (antes ficava com a 1ª)');

  -- B7: o default de função do Supabase (EXECUTE ao authenticated e ao anon) foi simulado no topo e a migration reaplicada revogou
  perform pg_temp.teste_assert_ff(not has_function_privilege('authenticated', 'fn_materializar_fatos(uuid, text)', 'execute') and not has_function_privilege('anon', 'fn_materializar_fatos(uuid, text)', 'execute'), 'B7: fn_materializar_fatos não é executável pelo authenticated nem pelo anon (o default de função foi simulado e revogado)');
  perform pg_temp.teste_assert_ff(not has_function_privilege('authenticated', 'fn_fato_pendencia_da_versao(uuid)', 'execute') and not has_function_privilege('anon', 'fn_fato_pendencia_da_versao(uuid)', 'execute'), 'B7: fn_fato_pendencia_da_versao (sem guarda de mandato) não é executável pelo authenticated nem pelo anon');
  perform pg_temp.teste_assert_ff(has_function_privilege('authenticated', 'fn_materializar_fatos_da_extracao(uuid, text)', 'execute') and has_function_privilege('service_role', 'fn_materializar_fatos(uuid, text)', 'execute'), 'e o que o portal precisa continua executável (a da extração, guardada) e o serviço executa a dele');
  perform pg_temp.inv('os cenários da 3ª revisão (duas colunas da mesma entidade, troca de tipo, entidade renomeada ou cadastrada)');
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- g6. A 4ª revisão independente: a regra nova (o fato é sempre recalculado do estado atual). A fusão sem reponta às cegas, a gravação em duas chamadas na mesma versão, a seção que muda mais o reparo, a pendência preservada, o ator real.
do $$
declare
  v_caso uuid; v_alfa uuid; v_ata uuid; v_v1 uuid; v_v2 uuid; v_s numeric; v_n int; v_r jsonb; v_pend uuid; v_desc text; v_uid uuid := gen_random_uuid(); v_doc uuid; v_ev int; v_n0 int; v_n2 int;
begin
  raise notice '--- g6. 4ª revisão ---';
  -- MÉDIO 1a: a fusão. "ALFA COMERCIO LTDA" + "ATACADO ALFA LTDA", colunas "Alfa Comércio"=100 e "Atacado Alfa"=70. Depois de fn_fundir_entidade(ATACADO -> ALFA) as DUAS colunas casam a ALFA: o do zero não atribui nenhuma. Antes a fusão trocava o id às cegas (a ALFA ficava com 170).
  v_caso := fn_upsert_caso('0243: fusão que torna a coluna ambígua')::uuid;
  v_alfa := fn_upsert_entidade(v_caso, 'ALFA COMERCIO LTDA');
  v_ata := (select id from entidade where caso_id = v_caso and razao_social = 'ATACADO ALFA LTDA');
  if v_ata is null then insert into entidade (caso_id, razao_social) values (v_caso, 'ATACADO ALFA LTDA') returning id into v_ata; end if;   -- fn_upsert_entidade fundiria as duas por nome
  perform fn_upsert_periodo(v_caso, 'anual', '2025');
  v_v1 := pg_temp.doc(v_caso, 'ALFA COMERCIO LTDA', '2025', 'COMBINADO', 'r4-f', jsonb_build_array(
    pg_temp.l('Caixa', '100', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Alfa Comércio'), pg_temp.l('Caixa', '70', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'Atacado Alfa')));
  select coalesce(sum(valor), 0) into v_s from fato_financeiro where documento_versao_id = v_v1 and entidade_id = v_alfa;
  perform pg_temp.teste_assert_ff(v_s = 100 and (select coalesce(sum(valor), 0) from fato_financeiro where documento_versao_id = v_v1 and entidade_id = v_ata) = 70, 'arranjo da fusão: antes dela a ALFA tem 100 e o ATACADO 70, cada uma pela coluna dela', v_s::text);
  perform fn_fundir_entidade(v_caso, v_ata, v_alfa);
  select coalesce(sum(valor), 0) into v_s from fato_financeiro where documento_versao_id = v_v1 and entidade_id = v_alfa;
  -- o do zero: "Atacado Alfa" não casa a ALFA (fn_mesma_entidade) e o ATACADO deixou de existir: a coluna dele fica sem entidade, a ALFA fica com a dela (100). A fusão antiga trocava o id às cegas e a ALFA ficava com 170, as duas por coluna.
  perform pg_temp.teste_assert_ff(v_s = 100 and exists (select 1 from fato_financeiro where documento_versao_id = v_v1 and entidade_coluna = 'Atacado Alfa' and entidade_id is null and entidade_motivo = 'coluna_sem_entidade_no_mandato'), 'MÉDIO 1a: depois da fusão a ALFA fica com 100 (a coluna dela) e a coluna do absorvido fica sem entidade, explicada (antes: 170, as duas por coluna)', v_s::text);
  perform pg_temp.inv('a fusão que torna duas colunas ambíguas');
  perform fn_upsert_entidade(v_caso, 'OMEGA SEM RELACAO LTDA');
  perform pg_temp.inv('cadastrar uma entidade que não tem relação com a fusão (antes mudava o resultado)');

  -- MÉDIO 1b: a gravação em DUAS chamadas na MESMA versão: a 1ª sem entidade_coluna, a 2ª com "Consolidado" e a coluna de outra empresa. O do zero: a linha sem coluna fica nula (o documento passou a TER colunas de entidade); a soma da dona é só a do Consolidado (antes 200: 100 'documento' + 100 'coluna_total').
  v_caso := fn_upsert_caso('0243: duas chamadas na mesma versão')::uuid;
  v_alfa := fn_upsert_entidade(v_caso, 'METALURGICA P27 LTDA'); perform fn_upsert_entidade(v_caso, 'VERTENTES COMPONENTES LTDA'); perform fn_upsert_periodo(v_caso, 'anual', '2025');
  v_v2 := (fn_registrar_documento(v_caso, 'METALURGICA P27 LTDA', 'anual', '2025', 'COMBINADO', 0.97, 'nome_arquivo', 'supabase_storage', '0243/r4-d.pdf', 'r4-d.pdf', true, 'r4-d', 'ok')->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_v2, jsonb_build_array(pg_temp.l('Receita', '100', 'receita_bruta', 'RECEITA', '2025')));
  perform fn_registrar_campos_extraidos(v_v2, jsonb_build_array(pg_temp.l('Receita', '100', 'receita_bruta', 'RECEITA', '2025', 'Consolidado'), pg_temp.l('Receita', '40', 'receita_bruta', 'RECEITA', '2025', 'Vertentes Componentes')));
  select coalesce(sum(valor), 0) into v_s from fato_financeiro where documento_versao_id = v_v2 and entidade_id = v_alfa and periodo_id is not null;
  perform pg_temp.teste_assert_ff(v_s = 100 and exists (select 1 from fato_financeiro f where f.documento_versao_id = v_v2 and f.entidade_coluna is null and f.entidade_id is null and f.entidade_motivo = 'linha_sem_coluna_em_documento_com_colunas_de_entidade'),
    'MÉDIO 1b: gravada em duas chamadas, a linha da 1ª (sem coluna) fica nula e a dona soma só o Consolidado: 100 (antes 200, a invariante quebrava)', v_s::text);
  perform pg_temp.inv('a gravação em duas chamadas na mesma versão');

  -- MÉDIO 2: a seção que muda por reparo de serviço (os reparos em massa das 0203/0204 fazem update de campo_extraido.secao_canonica). Não há gatilho em campo_extraido (decisão no cabeçalho): a sonda recentes acusa o fato velho e o reparo que ela manda rodar DE FATO conserta.
  v_caso := fn_upsert_caso('0243: seção que muda por reparo')::uuid;
  perform fn_upsert_entidade(v_caso, 'SECAO P27 LTDA'); perform fn_upsert_periodo(v_caso, 'anual', '2025');
  v_v1 := pg_temp.doc(v_caso, 'SECAO P27 LTDA', '2025', 'BALANCO', 'r4-s', jsonb_build_array(
    pg_temp.l('Caixa R4', '5', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'), pg_temp.l('Clientes R4', '6', null, 'Outros', '2025'), pg_temp.l('Estoques R4', '7', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025')));
  update documento_versao set criada_em = now() + interval '1 day' where id = v_v1;
  select id, descricao into v_pend, v_desc from pendencia where motivo = 'fato:conta_incerta:' || v_v1 and estado = 'aberta';
  perform pg_temp.teste_assert_ff(v_pend is not null, 'arranjo: a extração nova com linha sem seção abre a pendência (1)');
  update campo_extraido set secao_canonica = case chave when 'Clientes R4' then 'ativo_circulante' else 'passivo_circulante' end, secao_canonica_inferida = false where documento_versao_id = v_v1;   -- o reparo em massa
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_extracao_nova_materializa'), 'depois do reparo de seção em massa o fato envelheceu e a sonda recentes acusa');
  v_r := fn_materializar_fatos();
  perform pg_temp.teste_assert_ff((v_r->>'atualizados')::int >= 3 and (select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_extracao_nova_materializa'), 'MÉDIO 2: o reparo que a sonda manda rodar (fn_materializar_fatos) RECALCULA a conta e a sonda volta a verde (antes devolvia 0 e ela seguia vermelha)', v_r::text);
  perform pg_temp.teste_assert_ff((select conta_id from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where ce.documento_versao_id = v_v1 and ce.chave = 'Caixa R4') = 'passivo_circulante'
     and (select resolucao_metodo from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where ce.documento_versao_id = v_v1 and ce.chave = 'Clientes R4') = 'declarada', 'e a conta e o método dos fatos são os da linha de hoje');
  perform pg_temp.inv('a seção que muda por reparo em massa mais o reparo');

  -- A PENDÊNCIA fica como a extração nova a deixou: nenhum recálculo (reparo, cadastro, documento, fusão) abre, fecha ou reescreve.
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_v1 and estado = 'aberta' and id = v_pend and descricao = v_desc;
  perform pg_temp.teste_assert_ff(v_n = 1, 'a pendência da extração nova (1, aberta, mesmo texto) NÃO foi tocada pelo recálculo do reparo (nem aberta, nem fechada, nem reescrita)', v_n::text);
  perform fn_upsert_entidade(v_caso, 'OUTRA P27 LTDA'); perform fn_upsert_periodo(v_caso, 'anual', '2024');
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_v1 and estado = 'aberta' and id = v_pend and descricao = v_desc;
  select count(*) into v_n2 from pendencia where caso_id = v_caso and tipo = 'conta_canonica_incerta';
  perform pg_temp.teste_assert_ff(v_n = 1 and v_n2 = 1, 'e nem o recálculo por cadastro de entidade e de período a toca (continua 1 pendência da versão)', v_n || ' x ' || v_n2);
  perform pg_temp.teste_assert_ff(not exists (select 1 from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id where ce.documento_versao_id = v_v1 and f.origem <> 'extracao'), 'a origem dos fatos da extração nova continua extracao depois dos recálculos (a pendência só lê fato de extração)');
  -- O ATOR REAL no evento do recálculo: a correção do documento por uma pessoa grava fatos_recalculados com o nome dela; sem pessoa, o sistema
  select documento_id into v_doc from documento_versao where id = v_v1;
  select count(*) into v_n0 from evento_auditoria where acao = 'fatos_recalculados';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  update documento set entidade_id = (select id from entidade where caso_id = v_caso and razao_social = 'OUTRA P27 LTDA') where id = v_doc;
  perform set_config('request.jwt.claims', '', true);
  select count(*) into v_ev from evento_auditoria where acao = 'fatos_recalculados' and entidade_ref = 'documento_versao:' || v_v1 and ator = 'usuario:' || v_uid and depois->>'motivo' = 'documento_alterado';
  perform pg_temp.teste_assert_ff(v_ev = 1, 'trocar a entidade do documento grava o evento fatos_recalculados com o ator REAL e o motivo (o fato trocado nunca é silêncio)', v_ev::text);
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_v1 and estado = 'aberta' and id = v_pend and descricao = v_desc;
  perform pg_temp.teste_assert_ff(v_n = 1, 'e a correção do documento (recálculo da versão) também NÃO toca a pendência: continua aberta, a mesma, com o mesmo texto', v_n::text);
  perform fn_materializar_fatos(v_v1);
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_v1 and estado = 'aberta' and id = v_pend and descricao = v_desc;
  perform pg_temp.teste_assert_ff(v_n = 1, 'e o recálculo explícito da VERSÃO (o reparo) idem: nem fecha (agora não sobra linha incerta), nem reescreve', v_n::text);
  -- só a PORTA DA EXTRAÇÃO mexe na pendência: rodar a extração de novo a converge (não sobra linha incerta: resolve-se) e nunca duplica
  perform fn_materializar_fatos_da_extracao(v_v1);
  select count(*) into v_n from pendencia where motivo = 'fato:conta_incerta:' || v_v1;
  perform pg_temp.teste_assert_ff(v_n = 1 and (select estado from pendencia where id = v_pend) = 'resolvida', 'a porta da extração converge a pendência (resolve-se: nenhuma linha incerta) e não duplica', v_n::text);
  perform pg_temp.inv('a troca de entidade do documento, depois de tudo');
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- A INVARIANTE (regra 3, a família inteira e não os casos): em NENHUM documento duas colunas diferentes caem na mesma (conta, entidade, período) não nulos — é o que fazia a soma dobrar (1.310 em vez de 150; 500; 435; 342).
create or replace function pg_temp.colunas_na_mesma_chave() returns bigint language sql as $f$
  select count(*) from (
    select f.documento_versao_id, f.conta_id, f.entidade_id, f.periodo_id
      from fato_financeiro f
     where f.conta_id is not null and f.entidade_id is not null and f.periodo_id is not null
     group by 1, 2, 3, 4
    having count(distinct coalesce(f.periodo_coluna, '') || '|' || coalesce(f.entidade_coluna, '')) > 1) x
$f$;
do $$
declare v_n bigint; v_nn bigint;
begin
  raise notice '--- a invariante: nenhuma chave com duas colunas do mesmo documento ---';
  select count(*) into v_nn from fato_financeiro where conta_id is not null and entidade_id is not null and periodo_id is not null;
  perform pg_temp.teste_assert_ff(v_nn >= 1000, 'a invariante mede sobre fatos de identidade completa (não sobre o vazio)', v_nn::text);
  select pg_temp.colunas_na_mesma_chave() into v_n;
  perform pg_temp.teste_assert_ff(v_n = 0, 'INVARIANTE: nenhum documento (fixtures e cenários) tem duas colunas diferentes na mesma (conta, entidade, período)',
    v_n || ' chave(s): ' || coalesce((select string_agg(x.d || ' ' || x.c, ' / ') from (select dv.nome_original as d, string_agg(distinct coalesce(f.periodo_coluna, '-') || '|' || coalesce(f.entidade_coluna, '-'), ', ') as c
        from fato_financeiro f join documento_versao dv on dv.id = f.documento_versao_id where f.conta_id is not null and f.entidade_id is not null and f.periodo_id is not null
       group by dv.nome_original, f.conta_id, f.entidade_id, f.periodo_id having count(distinct coalesce(f.periodo_coluna, '') || '|' || coalesce(f.entidade_coluna, '')) > 1) x), '-'));
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
    pg_temp.l('Caixa G', '10', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'GAMA P27 LTDA'),
    pg_temp.l('Caixa da Delta', '20', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025', 'DELTA P27 LTDA')));
  select count(*) into v_n from fato_financeiro where entidade_id = v_de;
  perform pg_temp.teste_assert_ff(v_n = 1, 'a Delta tem 1 fato (pela coluna) antes da fusão', v_n::text);
  begin
    v_r := fn_fundir_entidade(v_caso, v_de, v_para);
  exception when others then v_r := jsonb_build_object('erro', sqlerrm);   -- a FK derrubou a fusão: os asserts abaixo reprovam
  end;
  perform pg_temp.teste_assert_ff(v_r->>'fundida' = 'DELTA P27 LTDA' and (v_r->>'fatos_repontados')::int = 1, 'a fusão NÃO cai na FK de fato_financeiro e conta os fatos repontados', v_r::text);
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_ver and entidade_id = v_para;
  -- a coluna da absorvida ("DELTA P27 LTDA") não casa mais nenhuma entidade: o fato dela NÃO some e NÃO é jogado na sobrevivente às cegas — fica sem entidade, com o motivo (é o que o zero daria)
  perform pg_temp.teste_assert_ff(v_n = 1 and not exists (select 1 from entidade where id = v_de), 'a sobrevivente fica só com o fato da coluna dela e a absorvida deixa de existir', v_n::text);
  perform pg_temp.teste_assert_ff(exists (select 1 from fato_financeiro f where f.documento_versao_id = v_ver and f.entidade_coluna = 'DELTA P27 LTDA' and f.entidade_id is null and f.entidade_motivo = 'coluna_sem_entidade_no_mandato'),
    'o fato da coluna da absorvida fica sem entidade com o motivo coluna_sem_entidade_no_mandato (explicado, não perdido, não repontado às cegas)');
  perform pg_temp.inv('a fusão de entidade');
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
  v_uid uuid := gen_random_uuid(); v_ana uuid := gen_random_uuid(); v_caso uuid; v_ver uuid; v_n int; v_tot int; v_t text; v_t2 text; v_t3 text; v_sem int; v_n2 int; v_outra uuid; v_r jsonb; v_e1 uuid; v_e2 uuid; v_rz uuid; v_docrz uuid; v_t4 text;
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
  begin
    insert into fato_financeiro (campo_extraido_id, documento_versao_id, conta_id, resolucao_metodo, valor, origem)
      select ce.id, ce.documento_versao_id, 'ativo_circulante', 'declarada', 999999999, 'extracao' from campo_extraido ce limit 1;
    v_t2 := 'ok';
  exception when others then v_t2 := sqlstate;
  end;
  begin
    update fato_financeiro set entidade_id = entidade_id, entidade_origem = entidade_origem;
    v_t3 := 'ok';
  exception when others then v_t3 := sqlstate;
  end;
  execute 'reset role';
  perform pg_temp.teste_assert_ff(v_n = v_tot, 'o Sócio lê todos os fatos', v_n || ' de ' || v_tot);
  perform pg_temp.teste_assert_ff(v_t = '42501', 'ninguém altera o VALOR do fato', v_t);
  perform pg_temp.teste_assert_ff(v_t2 = '42501', 'nem o Sócio, como authenticated, INSERE fato (o fato é derivado: valor arbitrário passava na primeira versão)', v_t2);
  perform pg_temp.teste_assert_ff(v_t3 = '42501', 'nem repõe a identidade (a entidade de OUTRO mandato passava na primeira versão)', v_t3);

  -- o Analista alocado materializa pelo caminho do portal (fn_registrar_campos_extraidos como authenticated)
  v_caso := (fn_upsert_caso('0243: acesso do analista'))::uuid;
  insert into membro (usuario_id, papel) values (v_ana, 'analista');
  insert into alocacao (caso_id, usuario_id) values (v_caso, v_ana);
  select f.documento_versao_id into v_outra from fato_financeiro f join documento_versao dv on dv.id = f.documento_versao_id join documento d on d.id = dv.documento_id where d.caso_id <> v_caso order by dv.criada_em, dv.id limit 1;   -- a MAIS ANTIGA (uma das fixtures), não uma dos cenários acima
  delete from fato_financeiro where documento_versao_id = v_outra;
  v_e1 := fn_upsert_entidade(v_caso, 'ACESSO UM P27 LTDA'); v_e2 := fn_upsert_entidade(v_caso, 'ACESSO DOIS P27 LTDA');
  v_rz := (fn_registrar_documento(v_caso, 'ACESSO UM P27 LTDA', 'anual', '2025', 'RAZAO', 0.97, 'nome_arquivo', 'supabase_storage', '0243/p27-rz.pdf', 'p27-rz.pdf', true, 'p27-rz', 'ok')->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_rz, jsonb_build_array(jsonb_build_object('chave', 'Caixa RZ', 'valor_num', '3', 'secao_canonica', 'ativo_circulante', 'secao', 'AC', 'confianca', '0.97')));
  select documento_id into v_docrz from documento_versao where id = v_rz;
  v_ver := (fn_registrar_documento(v_caso, 'ACESSO P27 LTDA', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage', '0243/p27-h.pdf', 'p27-h.pdf', true, 'p27-h', 'ok')->>'documento_versao_id')::uuid;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_ana, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('chave', 'Caixa H', 'valor_num', '5', 'secao_canonica', 'ativo_circulante', 'secao', 'ATIVO CIRCULANTE', 'confianca', '0.97'),
    jsonb_build_object('chave', 'Conta H sem seção', 'valor_num', '6', 'secao', 'Outros', 'confianca', '0.97')));
  select count(*) into v_n from fato_financeiro where documento_versao_id = v_ver;
  select count(*) into v_n2 from pendencia where motivo = 'fato:conta_incerta:' || v_ver;
  v_r := fn_materializar_fatos_da_extracao(v_outra);
  begin
    perform fn_materializar_fatos(v_ver);   -- até no PRÓPRIO mandato, onde ele escreve: o execute é só do serviço
    v_t := 'ok';
  exception when others then v_t := sqlstate;
  end;
  begin
    perform fn_materializar_fatos_do_caso(gen_random_uuid(), 'entidade');   -- o Analista recalculando fato de OUTRO mandato
    v_t4 := 'ok';
  exception when others then v_t4 := sqlstate;
  end;
  update documento set tipo_taxonomia = 'BALANCETE' where id = v_docrz;   -- a reclassificação humana: o evento leva o NOME dele
  execute 'reset role';
  perform pg_temp.teste_assert_ff(v_t4 = '42501', 'o Analista NÃO recalcula os fatos de OUTRO mandato (fn_materializar_fatos_do_caso é guardada)', v_t4);
  perform pg_temp.teste_assert_ff(not has_function_privilege('authenticated', 'fn_fato_recalcular(uuid, text, text)', 'execute') and not has_function_privilege('authenticated', 'fn_fato_recalcular_caso(uuid, text, text)', 'execute'), 'o escritor interno (fn_fato_recalcular) e o do mandato (fn_fato_recalcular_caso) não são executáveis pelo authenticated');
  perform pg_temp.teste_assert_ff(exists (select 1 from evento_auditoria where acao = 'fatos_materializacao_negada' and entidade_ref = 'documento_versao:' || v_outra and ator = 'usuario:' || v_ana),
    'a recusa por permissão deixa o evento fatos_materializacao_negada, com o ator real (regra 7)');
  perform pg_temp.teste_assert_ff((select count(*) from fato_financeiro where documento_versao_id = v_rz) = 1 and exists (select 1 from evento_auditoria where acao = 'fatos_materializados' and entidade_ref = 'documento_versao:' || v_rz and ator = 'usuario:' || v_ana),
    'a materialização por reclassificação humana grava o ator REAL (usuario:<id>), não sistema:n8n');
  perform pg_temp.teste_assert_ff(coalesce((v_r->>'materializado')::boolean, true) = false and not exists (select 1 from fato_financeiro where documento_versao_id = v_outra),
    'o Analista NÃO alocado no mandato não materializa fato nele (a função diz sem permissão e não cria nada)', v_r::text);
  perform pg_temp.teste_assert_ff(v_t = '42501', 'e não chama fn_materializar_fatos direto, nem no mandato onde escreve (execute só do serviço)', v_t);
  perform pg_temp.teste_assert_ff(v_n = 2, 'o Analista alocado materializa os fatos pelo caminho do portal (a RLS de insert deixa)', v_n::text);
  perform pg_temp.teste_assert_ff(v_n2 = 1, 'e a pendência da linha sem seção abre também como Analista', v_n2::text);
  perform set_config('request.jwt.claims', '', true);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- k. A sonda: os 32 requisitos presentes; e ela ACUSA cada guarda removida (nos mesmos termos do teste da 0242: a migration é a coisa medida, aqui o estado do banco montado).
do $$
declare v_n int; v_lista text; v_def text; v_ok boolean; v_f int; v_cs uuid; v_new uuid;
begin
  raise notice '--- k. a sonda de instalação ---';
  -- a parte j apaga os fatos de uma versão de OUTRO mandato para provar que o Analista não materializa nele: o reparo antes da sonda (que agora mede por comportamento, sem olhar evento)
  perform fn_materializar_fatos();
  set constraints all immediate;   -- as FKs de dimensão são adiadas: sem isto o `alter table` abaixo morre em `pending trigger events`
  select count(*), string_agg(chave, ', ') filter (where not presente) into v_n, v_lista from fn_instalacao_conferir() where migration = '0243';
  perform pg_temp.teste_assert_ff(v_n = 32 and v_lista is null, 'os 32 requisitos da 0243 estão no catálogo e presentes', v_n || ' requisitos; ausentes: ' || coalesce(v_lista, 'nenhum') || coalesce(' | versões sem fato: ' || (select string_agg(distinct dv.nome_original || '/' || ce.chave, ', ')
      from (select dv.id from documento_versao dv join documento d on d.id = dv.documento_id where fn_tipo_gera_fato(d.tipo_taxonomia)
              and exists (select 1 from evento_auditoria e where e.entidade_ref = 'documento_versao:' || dv.id and e.acao = 'extracao_sombra') order by dv.criada_em desc, dv.id limit 20) v
      join documento_versao dv on dv.id = v.id join documento d on d.id = dv.documento_id join campo_extraido ce on ce.documento_versao_id = v.id and ce.origem_valor = 'extracao'
     where fn_linha_vira_fato(d.tipo_taxonomia, ce.chave, ce.unidade, ce.valor_num) and not exists (select 1 from fato_financeiro f where f.campo_extraido_id = ce.id)), ''));
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
  insert into fato_financeiro (campo_extraido_id, documento_versao_id, conta_id, resolucao_metodo, entidade_motivo, periodo_motivo, valor, origem)
    select ce.id, ce.documento_versao_id, 'demo_dre', 'declarada', 'documento_sem_entidade', 'documento_sem_periodo', 1, 'extracao'
      from campo_extraido ce where not exists (select 1 from fato_financeiro f where f.campo_extraido_id = ce.id) limit 1;
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_so_secao'), 'a sonda acusa fato apontando para a RAIZ da demonstração (a identidade é seção)');
  delete from fato_financeiro where conta_id = 'demo_dre';
  perform pg_temp.teste_assert_ff((select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_so_secao'), 'sem o fato na raiz a sonda volta a presente');

  -- A3 (3ª revisão): a sonda da extração nova mede por COMPORTAMENTO, não pelo evento extracao_sombra nem pelo corpo. Sem o gatilho, uma extração nova grava a linha e NENHUM fato; e, se o evento nunca fosse gravado (fn_registrar que deixasse de gravá-lo), a amostra antiga ficaria vazia e a sonda verde.
  v_cs := fn_upsert_caso('0243: sonda por comportamento')::uuid;
  perform fn_upsert_entidade(v_cs, 'SONDA P27 LTDA'); perform fn_upsert_periodo(v_cs, 'anual', '2025');
  begin
    alter table evento_auditoria disable trigger trg_fato_extracao_nova;
  exception when undefined_object then null;
  end;
  v_new := pg_temp.doc(v_cs, 'SONDA P27 LTDA', '2025', 'BALANCO', 'r3-s1', jsonb_build_array(pg_temp.l('Caixa S', '5', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025'), pg_temp.l('Clientes S', '6', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025')));
  update documento_versao set criada_em = now() + interval '2 days' where id = v_new;   -- a mais nova (as versões deste teste empatam em now())
  delete from evento_auditoria where entidade_ref = 'documento_versao:' || v_new and acao = 'extracao_sombra';   -- a extração que NUNCA gravou o evento
  perform pg_temp.teste_assert_ff((select count(*) from fato_financeiro where documento_versao_id = v_new) = 0, 'arranjo: a extração nova sem o gatilho grava a linha e nenhum fato');
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_extracao_nova_materializa'), 'a sonda acusa a extração nova SEM fato mesmo sem o evento extracao_sombra (regra 7: o estágio que não rodou não parece limpo, e a sonda não depende do sinal que o próprio estágio emite)');
  begin
    alter table evento_auditoria enable trigger trg_fato_extracao_nova;
  exception when undefined_object then null;
  end;
  perform fn_materializar_fatos();
  perform pg_temp.teste_assert_ff((select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_extracao_nova_materializa'), 'o reparo (fn_materializar_fatos) devolve a sonda a presente');
  -- o fato que discorda da linha (o evento gravado ANTES da herança da seção materializaria a seção velha): acusado
  update campo_extraido set secao_canonica = 'passivo_circulante' where documento_versao_id = v_new and chave = 'Caixa S';
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_extracao_nova_materializa'), 'a sonda acusa o fato cuja conta discorda da seção que a linha tem hoje (o fato nasceu antes da herança da seção)');
  update campo_extraido set secao_canonica = 'ativo_circulante' where documento_versao_id = v_new and chave = 'Caixa S';
  perform pg_temp.teste_assert_ff((select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_extracao_nova_materializa'), 'e volta a presente quando a linha e o fato concordam');

  -- o ÚNICO ESCRITOR (4ª revisão): uma função que grava em fato_financeiro fora de fn_fato_recalcular é acusada
  execute 'create function fn_fato_escritor_extra() returns void language sql as $q$ update fato_financeiro set valor = valor where false $q$';
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_um_escritor_so'), 'a sonda acusa uma 2ª função que grava em fato_financeiro (de volta a re-resolução parcial)');
  execute 'drop function fn_fato_escritor_extra()';
  perform pg_temp.teste_assert_ff((select presente from fn_instalacao_conferir() where chave = 'fato_um_escritor_so'), 'removida, o único escritor volta a presente');

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

  -- o gatilho da extração nova desabilitado: a extração grava a linha e o fato não nasce (o estágio que não rodou)
  begin
    alter table evento_auditoria disable trigger trg_fato_extracao_nova;
  exception when undefined_object then null;   -- gatilho já removido: a sonda o acusa do mesmo jeito
  end;
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'extracao_nova_gatilho'), 'a sonda acusa o gatilho da extração nova desabilitado');
  begin
    alter table evento_auditoria enable trigger trg_fato_extracao_nova;
  exception when undefined_object then null;
  end;
  perform pg_temp.teste_assert_ff((select presente from fn_instalacao_conferir() where chave = 'extracao_nova_gatilho'), 'e volta a presente ao reabilitar');
  -- e o gatilho que existe mas não chama a materialização
  v_def := pg_get_functiondef('fn_fato_extracao_nova()'::regprocedure);
  execute replace(v_def, 'perform fn_materializar_fatos_da_extracao(v_versao);', 'null;');
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'extracao_nova_gatilho_chama'), 'a sonda acusa a função do gatilho que não chama a materialização');
  execute v_def;
  perform pg_temp.teste_assert_ff((select presente from fn_instalacao_conferir() where chave = 'extracao_nova_gatilho_chama'), 'recolocado o corpo, presente');

  v_def := pg_get_functiondef('fn_fundir_entidade(uuid,uuid,uuid,text)'::regprocedure);
  execute replace(v_def, 'perform fn_materializar_fatos_do_caso(p_caso_id, ''entidade'', ''fusao_de_entidade'');', 'null;');
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fundir_entidade_leva_os_fatos'), 'a sonda acusa fn_fundir_entidade que não recalcula os fatos (cairia na FK dos fatos)');
  execute v_def;

  -- a materialização que acha a conta por outro critério que a seção: a sonda acusa pelo COMPORTAMENTO (o fato novo discorda da linha), não por um marcador de corpo
  v_def := pg_get_functiondef('fn_fato_resolver(uuid)'::regprocedure);
  execute replace(v_def, 'left join conta_canonica c on c.secao_canonica = a.secao', 'left join conta_canonica c on c.codigo = a.tipo');
  v_new := pg_temp.doc(v_cs, 'SONDA P27 LTDA', '2025', 'BALANCO', 'r3-s2', jsonb_build_array(pg_temp.l('Caixa S2', '5', 'ativo_circulante', 'ATIVO CIRCULANTE', '2025')));
  update documento_versao set criada_em = now() + interval '3 days' where id = v_new;
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_financeiro_extracao_nova_materializa'), 'a sonda acusa a materialização que acha a conta por outro critério que a seção (o fato novo discorda da linha)');
  execute v_def;
  delete from fato_financeiro where documento_versao_id = v_new;
  perform fn_materializar_fatos();
  -- a guarda de escrita trocada por `select true`, e sem o search_path fixo; o authenticated com privilégio de escrita
  v_def := pg_get_functiondef('fn_fato_pode_escrever(uuid)'::regprocedure);
  execute 'create or replace function fn_fato_pode_escrever(p_caso uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $q$ select true $q$';
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_guarda_de_escrita_corpo'), 'a sonda acusa fn_fato_pode_escrever trocada por select true');
  execute v_def;
  alter function fn_fato_pode_escrever(uuid) reset search_path;
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_guarda_de_escrita_search_path'), 'a sonda acusa fn_fato_pode_escrever sem o search_path fixo (security definer sequestrável)');
  alter function fn_fato_pode_escrever(uuid) set search_path = public, pg_temp;
  grant insert on fato_financeiro to authenticated;
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'fato_authenticated_so_le'), 'a sonda acusa o authenticated com INSERT em fato_financeiro');
  revoke insert on fato_financeiro from authenticated;
  perform pg_temp.teste_assert_ff((select presente from fn_instalacao_conferir() where chave = 'fato_authenticated_so_le'), 'e volta a presente sem o privilégio');

  -- a lista dos tipos é conferida TIPO A TIPO, não pelo fim do corpo: tirar o BALANCO da lista deixa o requisito ausente
  v_def := pg_get_functiondef('fn_tipo_gera_fato(text)'::regprocedure);
  execute replace(v_def, '''BALANCO'', ', '');
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'tipos_que_geram_fato'), 'a sonda acusa a lista de tipos sem o BALANCO (e a mesma função que liga o estágio não responde por si)');
  execute v_def;
  execute replace(v_def, '''DF_AUDITADA'')', '''DF_AUDITADA'', ''RAZAO'')');
  perform pg_temp.teste_assert_ff(not (select presente from fn_instalacao_conferir() where chave = 'tipos_que_geram_fato'), 'e a que passa a gerar fato de RAZAO (o que é só evidência)');
  execute v_def;
  select count(*) into v_f from fn_instalacao_conferir() where migration = '0243' and not presente;
  perform pg_temp.teste_assert_ff(v_f = 0, 'depois de recolocar tudo, os 32 requisitos estão presentes de novo', v_f::text);
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
