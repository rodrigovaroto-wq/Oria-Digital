-- Testes da 0233: a falha transitória COM linha que o reenvio não relia (fn_versao_extracao_concluida).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO PROVA (comportamento): o n8n P8 grava em `medicao.falha_transitoria_esgotada` (booleano) do evento `extracao_sombra`; a versão com linha, com esse campo `true` no ÚLTIMO
-- evento, com `extracao_falhou` aberta e SEM linha aceita por humano deixa de ser "concluída" (o reenvio re-extrai e a fila de reprocesso a mostra como reprocessável). Campo ausente, falso,
-- não-booleano, medição nula, falha resolvida ou inexistente, aceite humano (inclusive com ressalva): continua reaproveitando. Aceite do sistema (auto_aceite) NÃO protege.
--
-- ARRANJO: os eventos vêm de fn_registrar_campos_extraidos de verdade (o campo entra por p_medicao, como o n8n o mandará). À mão, só o aceite `sistema:` e o `com_ressalva` (UPDATE; fn_aceitar_extracao
-- grava 'aceito'). Nenhum arranjo de produção é reproduzido: o campo é novo (0 eventos com ele em 10/11/2026).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md): 23 asserts (23 execuções); o número reprovado por sabotagem está no cabeçalho de
-- Supabase/migrations/0233_a_falha_transitoria_com_linha_que_o_reenvio_nao_relia.sql ("MEDIÇÃO NÃO-VAZIA").
--
-- `p8.medindo = on` (PGOPTIONS='-c p8.medindo=on') vira `raise warning` e CONTA.

\set ON_ERROR_STOP on

-- O teste de o_balanco_sem_dado_financeiro.test.sql REAPLICA a 0231 no meio da suíte (para provar o backfill dela) e, com isso, devolve fn_versao_extracao_concluida ao corpo da 0231, apagando a
-- 0233 do banco de teste: aqui o teste reaplica a 0233 (reaplicável por desenho) para voltar ao estado "instalação completa" — o mesmo estado que a sonda exige no fim da suíte.
\i Supabase/migrations/0233_a_falha_transitoria_com_linha_que_o_reenvio_nao_relia.sql

create or replace function teste_assert_p8(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('p8.execucoes', (coalesce(nullif(current_setting('p8.execucoes', true), ''), '0')::int + 1)::text, false);
  if p_ok then
    raise notice 'ok    %', p_nome;
  elsif current_setting('p8.medindo', true) = 'on' then
    perform set_config('p8.falhas', (coalesce(nullif(current_setting('p8.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

create or replace function teste_envia_p8(p_caso uuid, p_nome text, p_hash text, p_tipo text default 'BALANCO') returns jsonb language sql as $$
  select fn_registrar_documento(p_caso, 'Omega Ltda.', 'anual', '2025', p_tipo, 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/' || p_nome, p_nome, true, p_hash, 'ok', p_fingerprint_extracao => 'FP-P8') $$;

create or replace function teste_extrai_p8(p_versao uuid, p_linha boolean, p_falha text, p_tem boolean, p_medicao jsonb default null) returns void language plpgsql as $$
begin
  perform fn_registrar_campos_extraidos(p_versao,
    case when p_linha then jsonb_build_array(jsonb_build_object('ordem', 0, 'chave', 'Caixa', 'valor_num', 100, 'unidade', 'unidade', 'confianca', 0.99))
         else '[]'::jsonb end,
    'N0', p_falha, p_tem, p_medicao);
end $$;

-- Dentro de UMA transação now() é constante; o teste recua os eventos antes de regravar para o "último" ser o mais novo de verdade.
create or replace function teste_recua_p8(p_versao uuid) returns void language sql as $$
  update evento_auditoria set criado_em = criado_em - interval '1 minute'
   where acao = 'extracao_sombra' and entidade_ref = 'documento_versao:' || p_versao $$;

delete from caso where nome like 'Caso P8 %';
delete from storage.objects where name = 'bucket/t11.pdf';

do $$
declare
  v_caso uuid;
  v_a jsonb; v_b jsonb;
  v_ver uuid; v_n int; v_f record;
  v_esg jsonb := jsonb_build_object('falha_transitoria_esgotada', true);
  v_falha text := 'Extração INCOMPLETA: bloco 4 sem conteúdo';
begin
  raise notice '--- 18. falha transitória esgotada COM linha: o reenvio re-extrai (sem aceite humano) ---';
  v_caso := (fn_upsert_caso('Caso P8 transitória'))::uuid;
  v_a := teste_envia_p8(v_caso, 't1.pdf', 'HP8-T1');
  v_ver := (v_a->>'documento_versao_id')::uuid;
  perform teste_extrai_p8(v_ver, true, v_falha, null, v_esg);
  select count(*) into v_n from pendencia where documento_id = (v_a->>'documento_id')::uuid and tipo = 'extracao_falhou' and estado <> 'resolvida';
  perform teste_assert_p8(v_n = 1 and exists (select 1 from campo_extraido where documento_versao_id = v_ver),
    'premissa: a versão tem linha E falha aberta, e o evento marca falha_transitoria_esgotada', format('pendências=%s', v_n));
  perform teste_assert_p8(not exists (select 1 from campo_extraido where documento_versao_id = v_ver and status_aceite <> 'pendente' and aceito_por not like 'sistema:%'),
    'premissa: nenhuma linha aceita por humano');
  perform teste_assert_p8(fn_versao_extracao_concluida(v_ver) is false, 'transitória esgotada + falha aberta + sem aceite humano: NÃO concluída');
  v_b := teste_envia_p8(v_caso, 't1.pdf', 'HP8-T1');
  perform teste_assert_p8(not (v_b->>'reaproveitou_extracao')::boolean and (v_b->>'n_versao')::int = 2,
    'o reenvio RE-EXTRAI (versão 2)', format('reaproveitou=%s n_versao=%s', v_b->>'reaproveitou_extracao', v_b->>'n_versao'));

  raise notice '--- 18b. o campo: ausente, falso, não-booleano, medição nula = comportamento da 0230 (reaproveita) ---';
  v_a := teste_envia_p8(v_caso, 't2.pdf', 'HP8-T2'); v_ver := (v_a->>'documento_versao_id')::uuid;
  perform teste_extrai_p8(v_ver, true, v_falha, null, jsonb_build_object('linhas_devolvidas', 3));
  perform teste_assert_p8(fn_versao_extracao_concluida(v_ver), 'campo AUSENTE (n8n antigo): reaproveita, como hoje');
  v_a := teste_envia_p8(v_caso, 't3.pdf', 'HP8-T3'); v_ver := (v_a->>'documento_versao_id')::uuid;
  perform teste_extrai_p8(v_ver, true, v_falha, null, jsonb_build_object('falha_transitoria_esgotada', false));
  perform teste_assert_p8(fn_versao_extracao_concluida(v_ver), 'campo FALSO: reaproveita');
  v_a := teste_envia_p8(v_caso, 't4.pdf', 'HP8-T4'); v_ver := (v_a->>'documento_versao_id')::uuid;
  perform teste_extrai_p8(v_ver, true, v_falha, null, jsonb_build_object('falha_transitoria_esgotada', 'true'));
  perform teste_assert_p8(fn_versao_extracao_concluida(v_ver), 'campo STRING "true" (não booleano): reaproveita, ilegível não paga');
  v_a := teste_envia_p8(v_caso, 't5.pdf', 'HP8-T5'); v_ver := (v_a->>'documento_versao_id')::uuid;
  perform teste_extrai_p8(v_ver, true, v_falha, null, null);
  perform teste_assert_p8(fn_versao_extracao_concluida(v_ver), 'medição NULA: reaproveita');

  raise notice '--- 18c. sem falha aberta não há o que re-tentar ---';
  v_a := teste_envia_p8(v_caso, 't6.pdf', 'HP8-T6'); v_ver := (v_a->>'documento_versao_id')::uuid;
  perform teste_extrai_p8(v_ver, true, null, null, v_esg);
  select count(*) into v_n from pendencia where documento_id = (v_a->>'documento_id')::uuid and tipo = 'extracao_falhou' and estado <> 'resolvida';
  perform teste_assert_p8(v_n = 0, 'premissa: sem pendência extracao_falhou', format('pendências=%s', v_n));
  perform teste_assert_p8(fn_versao_extracao_concluida(v_ver), 'campo true mas SEM falha aberta: reaproveita');
  v_a := teste_envia_p8(v_caso, 't7.pdf', 'HP8-T7'); v_ver := (v_a->>'documento_versao_id')::uuid;
  perform teste_extrai_p8(v_ver, true, v_falha, null, v_esg);
  update pendencia set estado = 'resolvida' where documento_id = (v_a->>'documento_id')::uuid and tipo = 'extracao_falhou';
  perform teste_assert_p8(fn_versao_extracao_concluida(v_ver), 'campo true com a falha RESOLVIDA: reaproveita');

  raise notice '--- 18d. aceite humano segura o reaproveitamento (teto declarado); aceite do sistema não ---';
  v_a := teste_envia_p8(v_caso, 't8.pdf', 'HP8-T8'); v_ver := (v_a->>'documento_versao_id')::uuid;
  perform teste_extrai_p8(v_ver, true, v_falha, null, v_esg);
  perform fn_aceitar_extracao(v_ver, 'humano:teste', 'aceite do analista');
  perform teste_assert_p8(exists (select 1 from campo_extraido where documento_versao_id = v_ver and status_aceite = 'aceito' and aceito_por = 'humano:teste'),
    'premissa: o analista aceitou a linha');
  perform teste_assert_p8(fn_versao_extracao_concluida(v_ver), 'com aceite HUMANO: continua concluída (reaproveita)');
  v_b := teste_envia_p8(v_caso, 't8.pdf', 'HP8-T8');
  perform teste_assert_p8((v_b->>'reaproveitou_extracao')::boolean and (v_b->>'documento_versao_id') = v_ver::text,
    'e o reenvio devolve a MESMA versão (a linha aceita fica na Modelagem)');
  -- ARRANJO À MÃO: o aceite do sistema e o com_ressalva só se fabricam por UPDATE (fn_aceitar_extracao grava 'aceito' e o autor que se passa)
  v_a := teste_envia_p8(v_caso, 't9.pdf', 'HP8-T9'); v_ver := (v_a->>'documento_versao_id')::uuid;
  perform teste_extrai_p8(v_ver, true, v_falha, null, v_esg);
  update campo_extraido set status_aceite = 'aceito', aceito_por = 'sistema:auto_aceite (confiança >=95%)' where documento_versao_id = v_ver;
  perform teste_assert_p8(fn_versao_extracao_concluida(v_ver) is false, 'aceite do SISTEMA (auto_aceite) NÃO protege: re-extrai');
  update campo_extraido set status_aceite = 'com_ressalva', aceito_por = 'humano:teste' where documento_versao_id = v_ver;
  perform teste_assert_p8(fn_versao_extracao_concluida(v_ver), 'aceite HUMANO com ressalva também protege');

  raise notice '--- 18e. o ÚLTIMO evento decide ---';
  v_a := teste_envia_p8(v_caso, 't10.pdf', 'HP8-T10'); v_ver := (v_a->>'documento_versao_id')::uuid;
  perform teste_extrai_p8(v_ver, true, v_falha, null, v_esg);
  perform teste_recua_p8(v_ver);
  perform teste_extrai_p8(v_ver, true, v_falha, null, jsonb_build_object('falha_transitoria_esgotada', false));
  perform teste_assert_p8(fn_versao_extracao_concluida(v_ver), 'evento antigo true, o mais novo false: reaproveita');
  perform teste_recua_p8(v_ver);
  perform teste_extrai_p8(v_ver, true, v_falha, null, v_esg);
  perform teste_assert_p8(fn_versao_extracao_concluida(v_ver) is false, 'evento antigo false, o mais novo true: re-extrai');

  raise notice '--- 18f. a fila (0232) mostra o documento como reprocessável, e o reenvio confirma ---';
  v_a := teste_envia_p8(v_caso, 't11.pdf', 'HP8-T11'); v_ver := (v_a->>'documento_versao_id')::uuid;
  insert into storage.objects (bucket_id, name, metadata) values ('documentos', 'bucket/t11.pdf', '{"size": 3}');
  perform teste_extrai_p8(v_ver, true, v_falha, null, jsonb_build_object('linhas_devolvidas', 3));
  select * into v_f from fn_fila_de_reprocesso(v_caso) where documento_versao_id = v_ver;
  perform teste_assert_p8(v_f.reprocessavel is false and v_f.motivo_bloqueio = 'reaproveitaria', 'fila, campo ausente: reaproveitaria (como antes)',
    coalesce(v_f.motivo_bloqueio, 'null'));
  perform teste_recua_p8(v_ver);
  perform teste_extrai_p8(v_ver, true, v_falha, null, v_esg);
  select * into v_f from fn_fila_de_reprocesso(v_caso) where documento_versao_id = v_ver;
  perform teste_assert_p8(v_f.reprocessavel is true and v_f.motivo_bloqueio is null, 'fila, transitória esgotada sem aceite humano: reprocessável', coalesce(v_f.motivo_bloqueio, 'null'));
  perform fn_aceitar_extracao(v_ver, 'humano:teste', 'aceite');
  select * into v_f from fn_fila_de_reprocesso(v_caso) where documento_versao_id = v_ver;
  perform teste_assert_p8(v_f.reprocessavel is false and v_f.motivo_bloqueio = 'reaproveitaria', 'fila, com aceite humano: volta a reaproveitaria', coalesce(v_f.motivo_bloqueio, 'null'));

  raise notice '--- 18g. a sonda enxerga os requisitos da 0233 ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0233' and presente;
  perform teste_assert_p8(v_n = 2, 'os 2 requisitos da 0233 estão presentes na sonda', format('presentes=%s', v_n));
  select count(*) into v_n from instalacao_requisito where migration = '0233';
  perform teste_assert_p8(v_n = 2, 'e o catálogo declara exatamente 2', format('declarados=%s', v_n));

  if current_setting('p8.medindo', true) = 'on' then
    raise warning 'MEDIDO: % falha(s) de % execucoes', coalesce(current_setting('p8.falhas', true), '0'), current_setting('p8.execucoes', true);
  end if;
  raise notice 'TODOS OS TESTES DA FALHA TRANSITÓRIA PASSARAM';
end $$;
