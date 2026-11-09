-- Testes da idempotência por hash de fn_registrar_documento (Supabase/migrations/0026).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- A propriedade que estes testes travam: **reenviar/reextrair o MESMO arquivo não
-- suja o caso** — nem documento duplicado, nem item de checklist a mais, nem
-- cartão repetido na fila. E o inverso, igualmente importante: arquivo DIFERENTE
-- (ou sem hash) continua sendo documento novo, porque fundir dois documentos
-- distintos é o erro mais caro que esta função pode cometer.
--
-- 0230 (seções 12 a 17): o documento que a IA declarou SEM dado financeiro (zero linha, tem_dado_financeiro
-- = false, sem falha) deixa de ser pago a cada reenvio. A mudança é só ADITIVA: "tem linha" continua
-- reaproveitando como na 0118 (a seção 8 abaixo segue inserindo a linha à mão, sem evento, e segue valendo).
-- Os eventos das seções novas vêm de fn_registrar_campos_extraidos de verdade; o único arranjo montado à mão é
-- "linha sem evento" (a função nunca grava linha sem evento), dito no comentário da seção 14.

\set ON_ERROR_STOP on

create or replace function teste_assert_rx(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

do $$
declare
  v_caso uuid;
  v_r1 jsonb; v_r2 jsonb; v_r3 jsonb; v_r4 jsonb;
  v_n int;
  v_txt text;
begin
  raise notice '--- 1. o MESMO arquivo (mesmo hash) é VERSÃO NOVA, não documento novo ---';
  v_caso := (fn_upsert_caso('Caso reextração'))::uuid;

  v_r1 := fn_registrar_documento(
    v_caso, 'Alfa Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/bp.pdf', 'BP Alfa 2025.pdf', true, 'HASH-A', 'ok');
  v_r2 := fn_registrar_documento(
    v_caso, 'Alfa Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/bp.pdf', 'BP Alfa 2025.pdf', true, 'HASH-A', 'ok');

  perform teste_assert_rx(
    (v_r1->>'documento_id') = (v_r2->>'documento_id'),
    'mesmo hash => MESMO documento',
    format('1=%s 2=%s', v_r1->>'documento_id', v_r2->>'documento_id'));
  perform teste_assert_rx(
    (v_r1->>'documento_versao_id') <> (v_r2->>'documento_versao_id'),
    'mesmo hash => versão NOVA (a extração anterior não é sobrescrita)');
  perform teste_assert_rx((v_r1->>'n_versao') = '1' and (v_r2->>'n_versao') = '2',
    'n_versao incrementa', format('1=%s 2=%s', v_r1->>'n_versao', v_r2->>'n_versao'));
  perform teste_assert_rx((v_r2->>'reaproveitou_documento')::boolean,
    'o retorno DIZ que reaproveitou (é o que o workflow pode usar para decidir)');

  select count(*) into v_n from documento where caso_id = v_caso;
  perform teste_assert_rx(v_n = 1, 'um arquivo = um documento no caso', format('documentos=%s', v_n));

  raise notice '--- 2. reextração não infla checklist nem fila de revisão ---';
  select count(*) into v_n from checklist_item_status
    where caso_id = v_caso and documento_id = (v_r1->>'documento_id')::uuid;
  perform teste_assert_rx(v_n = 1, 'um item de checklist, não dois', format('itens=%s', v_n));

  -- Classificação incerta duas vezes: um cartão só na fila.
  v_r3 := fn_registrar_documento(
    v_caso, 'Beta Ltda.', 'anual', '2025', null, 0.2, 'nome_arquivo',
    'supabase_storage', 'bucket/x.pdf', 'arquivo estranho.pdf', null, 'HASH-B', 'ok');
  v_r4 := fn_registrar_documento(
    v_caso, 'Beta Ltda.', 'anual', '2025', null, 0.2, 'nome_arquivo',
    'supabase_storage', 'bucket/x.pdf', 'arquivo estranho.pdf', null, 'HASH-B', 'ok');
  select count(*) into v_n from pendencia
    where documento_id = (v_r3->>'documento_id')::uuid
      and tipo = 'classificacao_pendente' and estado <> 'resolvida';
  perform teste_assert_rx(v_n = 1, 'uma pendência de classificação, não uma por reenvio',
    format('pendências=%s', v_n));

  raise notice '--- 3. a máquina NÃO desfaz a revisão do humano (anti-ancoragem) ---';
  -- O humano corrige o tipo na fila; o dono então reextrai o arquivo. Se a
  -- reextração sobrepusesse o tipo, a correção humana seria perdida em silêncio.
  perform fn_revisar_documento((v_r3->>'documento_id')::uuid, 'humano:rodrigo', 'DMPL',
                               null, null, null, 'é a DMPL, não mútuos');
  perform fn_registrar_documento(
    v_caso, 'Beta Ltda.', 'anual', '2025', 'MUTUOS', 0.9, 'openai_conteudo',
    'supabase_storage', 'bucket/x.pdf', 'arquivo estranho.pdf', null, 'HASH-B', 'ok');
  select tipo_taxonomia into v_txt from documento where id = (v_r3->>'documento_id')::uuid;
  perform teste_assert_rx(v_txt = 'DMPL',
    'tipo revisado por humano sobrevive à reextração', format('tipo=%s', v_txt));

  raise notice '--- 4. NEGATIVO: arquivo diferente continua sendo documento novo ---';
  perform fn_registrar_documento(
    v_caso, 'Alfa Ltda.', 'anual', '2024', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/bp24.pdf', 'BP Alfa 2024.pdf', true, 'HASH-C', 'ok');
  select count(*) into v_n from documento where caso_id = v_caso;
  perform teste_assert_rx(v_n = 3, 'hash diferente => documento próprio (nada é fundido)',
    format('documentos=%s (esperado 3)', v_n));

  raise notice '--- 5. NEGATIVO: sem hash não há como afirmar que é o mesmo arquivo ---';
  -- Dois desconhecidos não são "o mesmo desconhecido": tratá-los como o mesmo
  -- documento fundiria arquivos distintos, que é o erro mais caro aqui.
  perform fn_registrar_documento(
    v_caso, 'Gama Ltda.', 'anual', '2025', 'DRE', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/s1.pdf', 'sem hash 1.pdf', null, null, 'ok');
  perform fn_registrar_documento(
    v_caso, 'Gama Ltda.', 'anual', '2025', 'DRE', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/s2.pdf', 'sem hash 2.pdf', null, null, 'ok');
  select count(*) into v_n from documento where caso_id = v_caso;
  perform teste_assert_rx(v_n = 5, 'hash nulo não casa (comportamento de antes)',
    format('documentos=%s (esperado 5)', v_n));

  raise notice '--- 6. UMA assinatura só (o overload morto não voltou) ---';
  -- A 0026 matou o de 14 args; a 0118 acrescentou o 16º (o fingerprint) e teve
  -- de MATAR o de 15 pelo mesmo motivo: com dois vivos, a chamada do n8n (13
  -- posicionais + o resto por nome) casa com AMBOS e o Postgres recusa com
  -- "function is not unique" — no meio de um lote real, não em teste.
  select count(*) into v_n from pg_proc where proname = 'fn_registrar_documento';
  perform teste_assert_rx(v_n = 1, 'existe exatamente UMA fn_registrar_documento',
    format('assinaturas vivas=%s', v_n));
  -- 0170: passou a 17 com o `p_cnpj`. O número muda quando a assinatura muda —
  -- é esse o trabalho deste assert. O que ele protege é a UNICIDADE acima: foi
  -- um overload vivo que derrubou um lote real com "function is not unique".
  select count(*) into v_n from pg_proc
    where proname = 'fn_registrar_documento' and pronargs = 17;
  perform teste_assert_rx(v_n = 1, 'e ela é a de 17 args (o fingerprint da 0118 + o CNPJ da 0170)',
    format('assinaturas de 17 args=%s', v_n));

  raise notice '--- 7. a reextração fica no rastro de auditoria ---';
  select count(*) into v_n from evento_auditoria
    where acao = 'documento_reextraido' and entidade_ref = 'documento:'||(v_r1->>'documento_id');
  perform teste_assert_rx(v_n = 1, 'evento próprio (documento_reextraido), não silêncio',
    format('eventos=%s', v_n));

  raise notice '--- 8. FINGERPRINT (0118): mesmo arquivo + mesmo prompt não paga de novo ---';
  -- O par (hash, fingerprint) só autoriza reaproveitar quando a versão antiga TEM
  -- linha extraída. Aqui a primeira versão recebe uma linha, e é isso que faz o
  -- segundo registro devolver a MESMA versão em vez de abrir outra.
  v_caso := (fn_upsert_caso('Caso fingerprint'))::uuid;
  v_r1 := fn_registrar_documento(
    v_caso, 'Delta Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/d.pdf', 'BP Delta.pdf', true, 'HASH-D', 'ok',
    p_fingerprint_extracao => 'FP-1');
  insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca)
    values ((v_r1->>'documento_versao_id')::uuid, 'Caixa', 100, 'unidade', 0.99);

  v_r2 := fn_registrar_documento(
    v_caso, 'Delta Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/d.pdf', 'BP Delta.pdf', true, 'HASH-D', 'ok',
    p_fingerprint_extracao => 'FP-1');
  perform teste_assert_rx((v_r2->>'reaproveitou_extracao')::boolean,
    'mesmo hash + mesmo fingerprint + já tem linha => reaproveita a extração');
  perform teste_assert_rx(
    (v_r1->>'documento_versao_id') = (v_r2->>'documento_versao_id'),
    'e NÃO cria versão nova — é a mesma versão que volta',
    format('%s vs %s', v_r1->>'documento_versao_id', v_r2->>'documento_versao_id'));
  select count(*) into v_n from documento_versao
    where documento_id = (v_r1->>'documento_id')::uuid;
  perform teste_assert_rx(v_n = 1, 'uma versão só, depois de dois registros',
    format('versões=%s', v_n));
  select count(*) into v_n from evento_auditoria
    where acao = 'documento_extracao_reaproveitada';
  perform teste_assert_rx(v_n = 1, 'o reaproveitamento fica no rastro de auditoria',
    format('eventos=%s', v_n));

  raise notice '--- 9. fingerprint DIFERENTE volta a pagar (é a reextração deliberada) ---';
  -- É o caso de o prompt ter mudado — a 0116 mexeu nele, e uma extração feita com
  -- o prompt de ontem não vale como a de hoje. Aqui tem de nascer versão nova.
  v_r3 := fn_registrar_documento(
    v_caso, 'Delta Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/d.pdf', 'BP Delta.pdf', true, 'HASH-D', 'ok',
    p_fingerprint_extracao => 'FP-2');
  perform teste_assert_rx(not (v_r3->>'reaproveitou_extracao')::boolean,
    'fingerprint diferente NÃO reaproveita');
  perform teste_assert_rx((v_r3->>'reaproveitou_documento')::boolean,
    'mas continua sendo o MESMO documento (a idempotência da 0026 segue valendo)');
  perform teste_assert_rx((v_r3->>'n_versao')::int = 2, 'e a versão é a 2',
    format('n_versao=%s', v_r3->>'n_versao'));

  raise notice '--- 10. EXTRAÇÃO QUE FALHOU não vale como extração feita ---';
  -- A propriedade que impede o pior erro desta migration. A versão 3 nasce com o
  -- fingerprint FP-3 e NENHUMA linha (extração truncada/recusada). Reenviar o
  -- arquivo — que é o conserto — tem de chamar a IA de novo.
  v_r4 := fn_registrar_documento(
    v_caso, 'Delta Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/d.pdf', 'BP Delta.pdf', true, 'HASH-D', 'ok',
    p_fingerprint_extracao => 'FP-3');
  perform teste_assert_rx(not (v_r4->>'reaproveitou_extracao')::boolean,
    'a versão com FP-3 nasceu sem linha nenhuma');
  v_r4 := fn_registrar_documento(
    v_caso, 'Delta Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/d.pdf', 'BP Delta.pdf', true, 'HASH-D', 'ok',
    p_fingerprint_extracao => 'FP-3');
  perform teste_assert_rx(not (v_r4->>'reaproveitou_extracao')::boolean,
    'e o reenvio com o MESMO fingerprint volta a pagar a extração — sem linha, não há o que reaproveitar');

  raise notice '--- 11. sem fingerprint, o comportamento é o da 0026 ---';
  -- Workflow antigo (que não manda o campo) não pode virar reaproveitamento
  -- silencioso: fingerprint nulo nunca casa, igual a hash nulo.
  v_r4 := fn_registrar_documento(
    v_caso, 'Delta Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/d.pdf', 'BP Delta.pdf', true, 'HASH-D', 'ok');
  perform teste_assert_rx(not (v_r4->>'reaproveitou_extracao')::boolean,
    'fingerprint nulo não casa');

end $$;

-- =============================================================================
-- 0230 — o documento sem dado financeiro declarado não é pago a cada reenvio
-- =============================================================================
create or replace function teste_envia_rx(p_caso uuid, p_nome text, p_hash text) returns jsonb language sql as $$
  select fn_registrar_documento(p_caso, 'Omega Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/' || p_nome, p_nome, true, p_hash, 'ok', p_fingerprint_extracao => 'FP-P7') $$;

-- Grava a extração da versão pela função de verdade (o formato do evento é o dela).
create or replace function teste_extrai_rx(p_versao uuid, p_linha boolean, p_falha text, p_tem boolean) returns void language plpgsql as $$
begin
  perform fn_registrar_campos_extraidos(p_versao,
    case when p_linha then jsonb_build_array(jsonb_build_object('ordem', 0, 'chave', 'Caixa', 'valor_num', 100, 'unidade', 'unidade', 'confianca', 0.99))
         else '[]'::jsonb end,
    'N0', p_falha, p_tem);
end $$;

-- Dentro de UMA transação now() é constante: dois eventos da mesma versão empatam em criado_em. Em produção cada chamada do n8n é a sua transação.
-- Antes de regravar uma versão o teste recua os eventos dela, para o "último" ser o mais novo de verdade.
create or replace function teste_recua_rx(p_versao uuid) returns void language sql as $$
  update evento_auditoria set criado_em = criado_em - interval '1 minute'
   where acao = 'extracao_sombra' and entidade_ref = 'documento_versao:' || p_versao $$;

do $$
declare
  v_caso uuid;
  v_a jsonb; v_b jsonb; v_c jsonb; v_d jsonb;
  v_n int; v_nlinhas int; v_st text;
  v_lote text[] := array['L1', 'L2', 'L3', 'L4'];
  v_r jsonb[]; v_i int;
  v_ok int; v_pago int;
begin
  raise notice '--- 12. documento SEM linha que declarou não ter dado financeiro (certidão, contrato) não é pago a cada reenvio ---';
  v_caso := (fn_upsert_caso('Caso P7 sem dado financeiro'))::uuid;
  v_a := teste_envia_rx(v_caso, 'certidao.pdf', 'HP7-CERT');
  perform teste_extrai_rx((v_a->>'documento_versao_id')::uuid, false, null, false);
  select count(*) into v_nlinhas from campo_extraido where documento_versao_id = (v_a->>'documento_versao_id')::uuid;
  perform teste_assert_rx(v_nlinhas = 0, 'premissa: a versão tem ZERO linha', format('linhas=%s', v_nlinhas));
  v_b := teste_envia_rx(v_caso, 'certidao.pdf', 'HP7-CERT');
  perform teste_assert_rx((v_b->>'reaproveitou_extracao')::boolean,
    'zero linha + tem_dado_financeiro = false + sem falha: o reenvio reaproveita');
  perform teste_assert_rx((v_b->>'documento_versao_id') = (v_a->>'documento_versao_id'),
    'e devolve a MESMA versão, sem abrir outra');
  select count(*) into v_n from documento_versao where documento_id = (v_a->>'documento_id')::uuid;
  perform teste_assert_rx(v_n = 1, 'uma versão só', format('versões=%s', v_n));

  raise notice '--- 13. o que continua NÃO reaproveitável (a 0118 protege) ---';
  v_caso := (fn_upsert_caso('Caso P7 controles'))::uuid;
  -- (a) zero linha SEM declaração: extração recusada/truncada
  v_a := teste_envia_rx(v_caso, 'c-a.pdf', 'HP7-CA');
  perform teste_extrai_rx((v_a->>'documento_versao_id')::uuid, false, null, null);
  perform teste_assert_rx(not (teste_envia_rx(v_caso, 'c-a.pdf', 'HP7-CA')->>'reaproveitou_extracao')::boolean,
    'zero linha sem declarar tem_dado_financeiro: NÃO reaproveita');
  -- (b) zero linha com tem_dado_financeiro = true: afirmar que TEM dado e não devolver linha é falha, não certidão
  v_a := teste_envia_rx(v_caso, 'c-b.pdf', 'HP7-CB');
  perform teste_extrai_rx((v_a->>'documento_versao_id')::uuid, false, null, true);
  perform teste_assert_rx(not (teste_envia_rx(v_caso, 'c-b.pdf', 'HP7-CB')->>'reaproveitou_extracao')::boolean,
    'zero linha com tem_dado_financeiro = true: NÃO reaproveita');
  -- (c) a declaração de "sem dado" NÃO apaga uma falha: falha_motivo vence
  v_a := teste_envia_rx(v_caso, 'c-c.pdf', 'HP7-CC');
  perform teste_extrai_rx((v_a->>'documento_versao_id')::uuid, false, 'timeout da IA', false);
  perform teste_assert_rx(not (teste_envia_rx(v_caso, 'c-c.pdf', 'HP7-CC')->>'reaproveitou_extracao')::boolean,
    'zero linha, tem_dado_financeiro = false COM falha_motivo: NÃO reaproveita');
  -- (d) versão que nem existe: false, nunca nulo
  perform teste_assert_rx(fn_versao_extracao_concluida(gen_random_uuid()) is false,
    'versão inexistente: a pergunta única responde false (não nulo)');

  raise notice '--- 14. o que a 0118 reaproveitava continua reaproveitado (a mudança é só aditiva) ---';
  -- TETO CONHECIDO, MANTIDO DE PROPÓSITO: falha COM linha (extração incompleta/desalinhada) continua reaproveitada até o prompt mudar. Em produção ~95% dessas falhas
  -- se repetem com o mesmo arquivo e o mesmo prompt; reextrair custa a cada vez e cria versão nova que tira da Modelagem a linha que o analista aceitou. O conserto é
  -- o prompt (o fingerprint muda) ou a retentativa classificada: fatia P8 do plano. Este assert trava que ELA NÃO voltou a ser paga por esta fatia.
  v_caso := (fn_upsert_caso('Caso P7 falha com linha'))::uuid;
  v_a := teste_envia_rx(v_caso, 'trunc.pdf', 'HP7-TRUNC');
  perform teste_extrai_rx((v_a->>'documento_versao_id')::uuid, true, 'Extração INCOMPLETA: 12 linhas devolvidas para um documento com 12 linhas', null);
  perform fn_aceitar_extracao((v_a->>'documento_versao_id')::uuid, 'humano:teste', 'aceite da linha que veio');
  select status_aceite into v_st from campo_extraido where documento_versao_id = (v_a->>'documento_versao_id')::uuid;
  perform teste_assert_rx(v_st = 'aceito', 'premissa: o analista aceitou a linha da versão com falha', format('status=%s', v_st));
  v_b := teste_envia_rx(v_caso, 'trunc.pdf', 'HP7-TRUNC');
  perform teste_assert_rx((v_b->>'reaproveitou_extracao')::boolean,
    'falha COM linha: o reenvio reaproveita (comportamento da 0118, teto conhecido; a retentativa é a P8)');
  perform teste_assert_rx((v_b->>'documento_versao_id') = (v_a->>'documento_versao_id'),
    'e NÃO nasce versão nova que tire da Modelagem a linha aceita');
  perform teste_assert_rx((select fn_versao_com_extracao((v_a->>'documento_id')::uuid)) = (v_a->>'documento_versao_id')::uuid
      and (select status_aceite from campo_extraido where documento_versao_id = (v_a->>'documento_versao_id')::uuid limit 1) = 'aceito',
    'o aceite humano da linha continua na versão vigente depois do reenvio');
  -- linha SEM evento nenhum (6 versões de produção, anteriores ao evento): reaproveita como antes. ARRANJO MONTADO À MÃO: a função nunca grava linha sem evento.
  v_a := teste_envia_rx(v_caso, 'sem-evento.pdf', 'HP7-SE');
  insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca)
    values ((v_a->>'documento_versao_id')::uuid, 'Caixa', 100, 'unidade', 0.99);
  select count(*) into v_n from evento_auditoria
    where acao = 'extracao_sombra' and entidade_ref = 'documento_versao:' || (v_a->>'documento_versao_id');
  perform teste_assert_rx(v_n = 0, 'premissa: a versão tem linha e NENHUM evento extracao_sombra', format('eventos=%s', v_n));
  perform teste_assert_rx((teste_envia_rx(v_caso, 'sem-evento.pdf', 'HP7-SE')->>'reaproveitou_extracao')::boolean,
    'linha sem evento nenhum: reaproveita (como antes da 0230)');

  raise notice '--- 15. o ÚLTIMO evento decide a parte nova (declaração de sem dado), nos dois sentidos ---';
  v_caso := (fn_upsert_caso('Caso P7 ultimo evento'))::uuid;
  v_a := teste_envia_rx(v_caso, 'u.pdf', 'HP7-U');
  perform teste_extrai_rx((v_a->>'documento_versao_id')::uuid, false, null, false);
  perform teste_assert_rx(fn_versao_extracao_concluida((v_a->>'documento_versao_id')::uuid), 'declaração sem falha: concluída');
  perform teste_recua_rx((v_a->>'documento_versao_id')::uuid);
  perform teste_extrai_rx((v_a->>'documento_versao_id')::uuid, false, 'regravada com falha', false);
  perform teste_assert_rx(not fn_versao_extracao_concluida((v_a->>'documento_versao_id')::uuid),
    'a falha MAIS NOVA vence a declaração mais antiga');
  perform teste_recua_rx((v_a->>'documento_versao_id')::uuid);
  perform teste_extrai_rx((v_a->>'documento_versao_id')::uuid, false, null, false);
  perform teste_assert_rx(fn_versao_extracao_concluida((v_a->>'documento_versao_id')::uuid),
    'e a declaração MAIS NOVA, sem falha, vence a falha mais antiga');

  raise notice '--- 16. O ACEITE DA FATIA: lote de 4 (2 com linha, 1 sem dado financeiro declarado, 1 falha total), reenviado inteiro, paga só a falha ---';
  v_caso := (fn_upsert_caso('Caso P7 lote'))::uuid;
  v_r := array[]::jsonb[];
  for v_i in 1..4 loop
    v_r := v_r || teste_envia_rx(v_caso, v_lote[v_i] || '.pdf', 'HP7-' || v_lote[v_i]);
  end loop;
  perform teste_extrai_rx((v_r[1]->>'documento_versao_id')::uuid, true,  null, null);
  perform teste_extrai_rx((v_r[2]->>'documento_versao_id')::uuid, true,  null, null);
  perform teste_extrai_rx((v_r[3]->>'documento_versao_id')::uuid, false, null, false);
  perform teste_extrai_rx((v_r[4]->>'documento_versao_id')::uuid, false, 'resposta sem conteúdo', null);
  v_ok := 0; v_pago := 0;
  for v_i in 1..4 loop
    v_c := teste_envia_rx(v_caso, v_lote[v_i] || '.pdf', 'HP7-' || v_lote[v_i]);
    if (v_c->>'reaproveitou_extracao')::boolean then v_ok := v_ok + 1; else v_pago := v_pago + 1; end if;
    if v_i = 4 then v_d := v_c; end if;
  end loop;
  perform teste_assert_rx(v_pago = 1, 'o reenvio do lote paga EXATAMENTE 1 documento (com o critério antigo seriam 2)', format('pagos=%s', v_pago));
  perform teste_assert_rx(v_ok = 3, 'e reaproveita os outros 3', format('reaproveitados=%s', v_ok));
  perform teste_assert_rx(not (v_d->>'reaproveitou_extracao')::boolean and (v_d->>'n_versao')::int = 2,
    'o que pagou é o L4 (a falha total, sem linha), na versão 2', format('L4 reaproveitou=%s n_versao=%s', v_d->>'reaproveitou_extracao', v_d->>'n_versao'));
  select count(*) into v_n from documento_versao dv join documento d on d.id = dv.documento_id where d.caso_id = v_caso;
  perform teste_assert_rx(v_n = 5, 'o lote ganhou UMA versão nova (4 + 1), não quatro', format('versões=%s', v_n));
  -- depois que a retentativa termina bem, o terceiro envio não paga nada
  perform teste_extrai_rx((v_d->>'documento_versao_id')::uuid, true, null, null);
  v_ok := 0; v_pago := 0;
  for v_i in 1..4 loop
    v_c := teste_envia_rx(v_caso, v_lote[v_i] || '.pdf', 'HP7-' || v_lote[v_i]);
    if (v_c->>'reaproveitou_extracao')::boolean then v_ok := v_ok + 1; else v_pago := v_pago + 1; end if;
  end loop;
  perform teste_assert_rx(v_ok = 4 and v_pago = 0, 'terceiro envio do lote: os 4 reaproveitam', format('reaproveitados=%s pagos=%s', v_ok, v_pago));
  select count(*) into v_n from documento_versao dv join documento d on d.id = dv.documento_id where d.caso_id = v_caso;
  perform teste_assert_rx(v_n = 5, 'nenhuma versão nova no terceiro envio', format('versões=%s', v_n));

  raise notice '--- 17. a sonda enxerga os requisitos da 0230 ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0230' and presente;
  perform teste_assert_rx(v_n = 3, 'os 3 requisitos da 0230 estão presentes na sonda', format('presentes=%s', v_n));
  select count(*) into v_n from instalacao_requisito where migration = '0230';
  perform teste_assert_rx(v_n = 3, 'e o catálogo declara exatamente 3', format('declarados=%s', v_n));

  raise notice 'TODOS OS TESTES DE REEXTRAÇÃO PASSARAM';
end $$;
