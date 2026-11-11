-- Testes da 0233: a falha transitória COM linha que o reenvio não relia (fn_versao_extracao_concluida).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO PROVA (comportamento): o n8n P8 grava em `medicao.falha_transitoria_esgotada` (booleano) do evento `extracao_sombra`; a versão com linha, com esse campo `true` no ÚLTIMO
-- evento, com `extracao_falhou` aberta e SEM linha aceita por humano deixa de ser "concluída" (o reenvio re-extrai e a fila de reprocesso a mostra como reprocessável). Campo ausente, falso,
-- não-booleano, medição nula, falha resolvida ou inexistente, aceite humano (inclusive com ressalva): continua reaproveitando. Aceite do sistema (auto_aceite) NÃO protege.
--
-- A VERSÃO VIGENTE (18g): a v2 criada pelo reenvio por falha transitória não pode TIRAR do book o número que a v1 já tinha. fn_versao_com_extracao e a CTE versao_vigente de fn_linhas_para_modelagem preferem a leitura
-- SEM a flag; só se todas a têm, a de mais linhas, depois a de maior número.
--
-- ARRANJO: os eventos vêm de fn_registrar_campos_extraidos de verdade (o campo entra por p_medicao, como o n8n o mandará). À mão, só o aceite `sistema:` e o `com_ressalva` (UPDATE; fn_aceitar_extracao
-- grava 'aceito'). Nenhum arranjo de produção é reproduzido: o campo é novo (0 eventos com ele em 10/11/2026).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md): 34 asserts (34 execuções); o número reprovado por sabotagem está no cabeçalho de
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

-- n linhas (Caixa, Estoques, Clientes, Fornecedores) com seção canônica, para a Modelagem enxergá-las; valor = 10 x posição.
create or replace function teste_extrai_n_p8(p_versao uuid, p_n int, p_falha text, p_medicao jsonb default null) returns void language plpgsql as $$
declare v_l jsonb := '[]'::jsonb; v_i int; v_k text[] := array['Caixa', 'Estoques', 'Clientes', 'Fornecedores'];
begin
  for v_i in 1..p_n loop
    v_l := v_l || jsonb_build_object('ordem', v_i, 'chave', v_k[v_i], 'valor_num', v_i * 10, 'unidade', 'unidade', 'confianca', 0.99, 'secao_canonica', 'ativo_circulante');
  end loop;
  perform fn_registrar_campos_extraidos(p_versao, v_l, 'N0', p_falha, null, p_medicao);
end $$;

-- ARRANJO À MÃO: uma versão a mais num documento já extraído (o reenvio de verdade só re-extrai quando a anterior não vale; aqui o cenário pede a v2 em qualquer caso).
create or replace function teste_nova_versao_p8(p_doc uuid, p_hash text) returns uuid language sql as $$
  insert into documento_versao (documento_id, n_versao, origem_arquivo, arquivo_ref, hash, legibilidade)
  select p_doc, max(n_versao) + 1, 'supabase_storage', 'p8/' || p_hash || '.pdf', p_hash, 'ok' from documento_versao where documento_id = p_doc
  returning id $$;

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
  v_ver uuid; v_ver2 uuid; v_ver3 uuid; v_n int; v_f record;
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

  raise notice '--- 18g. a versão vigente não troca uma leitura melhor por uma leitura que esgotou a falha transitória (ALTO 1 da revisão) ---';
  -- (1) o arranjo da revisão, PONTA A PONTA: v1 leu 3 linhas e esgotou a falha; o reenvio re-extrai (v2); a v2 esgota de novo e lê só 1 linha.
  v_caso := (fn_upsert_caso('Caso P8 vigente'))::uuid;
  v_a := teste_envia_p8(v_caso, 'v1.pdf', 'HP8-V1'); v_ver := (v_a->>'documento_versao_id')::uuid;
  perform teste_extrai_n_p8(v_ver, 3, v_falha, v_esg);
  v_b := teste_envia_p8(v_caso, 'v1.pdf', 'HP8-V1');
  perform teste_assert_p8((v_b->>'n_versao')::int = 2 and not (v_b->>'reaproveitou_extracao')::boolean, 'premissa: o reenvio criou a v2', v_b::text);
  perform teste_extrai_n_p8((v_b->>'documento_versao_id')::uuid, 1, v_falha, v_esg);
  perform teste_assert_p8(fn_versao_com_extracao((v_a->>'documento_id')::uuid) = v_ver,
    'v1 parcial (3 linhas) + v2 parcial PIOR (1 linha): a versão vigente continua a v1', coalesce(fn_versao_com_extracao((v_a->>'documento_id')::uuid)::text, 'null'));
  select count(*) into v_n from fn_linhas_para_modelagem(v_caso) where rotulo_norm = fn_normalizar_texto('Estoques');
  perform teste_assert_p8(v_n = 1, 'e a Modelagem (a CTE versao_vigente) ainda mostra a linha que só a v1 leu', format('linhas Estoques=%s', v_n));
  select count(*) into v_n from fn_linhas_para_modelagem(v_caso) where rotulo_norm = fn_normalizar_texto('Caixa');
  perform teste_assert_p8(v_n = 1, 'sem somar a v2 à v1: a linha que as duas leram aparece uma vez', format('linhas Caixa=%s', v_n));

  -- (2) a v2 completa (sem a flag) vence, mesmo com menos linhas que a v1 parcial
  v_caso := (fn_upsert_caso('Caso P8 vigente completa'))::uuid;
  v_a := teste_envia_p8(v_caso, 'v2c.pdf', 'HP8-V2C'); v_ver := (v_a->>'documento_versao_id')::uuid;
  perform teste_extrai_n_p8(v_ver, 3, v_falha, v_esg);
  v_ver2 := teste_nova_versao_p8((v_a->>'documento_id')::uuid, 'HP8-V2C-2');
  perform teste_extrai_n_p8(v_ver2, 2, null, jsonb_build_object('falha_transitoria_esgotada', false));
  perform teste_assert_p8(fn_versao_com_extracao((v_a->>'documento_id')::uuid) = v_ver2, 'v2 COMPLETA (sem a flag, 2 linhas) vence a v1 parcial (3 linhas)');
  select count(*) into v_n from fn_linhas_para_modelagem(v_caso) where rotulo_norm = fn_normalizar_texto('Estoques');
  perform teste_assert_p8(v_n = 1, 'e a Modelagem mostra a v2 (Estoques da v2 = 20, uma ocorrência)', format('linhas Estoques=%s', v_n));
  select count(*) into v_n from fn_linhas_para_modelagem(v_caso) where rotulo_norm = fn_normalizar_texto('Clientes');
  perform teste_assert_p8(v_n = 0, 'e a linha que só a v1 parcial tinha (Clientes) sai, como a v2 completa decidiu', format('linhas Clientes=%s', v_n));

  -- (3) ambas parciais: vence a que leu mais; empate, a de maior número
  v_caso := (fn_upsert_caso('Caso P8 vigente mais linhas'))::uuid;
  v_a := teste_envia_p8(v_caso, 'v3.pdf', 'HP8-V3'); v_ver := (v_a->>'documento_versao_id')::uuid;
  perform teste_extrai_n_p8(v_ver, 2, v_falha, v_esg);
  v_ver2 := teste_nova_versao_p8((v_a->>'documento_id')::uuid, 'HP8-V3-2');
  perform teste_extrai_n_p8(v_ver2, 3, v_falha, v_esg);
  perform teste_assert_p8(fn_versao_com_extracao((v_a->>'documento_id')::uuid) = v_ver2, 'ambas parciais, a v2 leu MAIS (3 x 2): vence a v2');
  v_ver3 := teste_nova_versao_p8((v_a->>'documento_id')::uuid, 'HP8-V3-3');
  perform teste_extrai_n_p8(v_ver3, 3, v_falha, v_esg);
  perform teste_assert_p8(fn_versao_com_extracao((v_a->>'documento_id')::uuid) = v_ver3, 'ambas parciais com o mesmo número de linhas (3 x 3): vence a de maior número');

  -- (4) v1 completa, v2 parcial (re-extração por outro caminho): fica a v1
  v_caso := (fn_upsert_caso('Caso P8 vigente v1 completa'))::uuid;
  v_a := teste_envia_p8(v_caso, 'v4.pdf', 'HP8-V4'); v_ver := (v_a->>'documento_versao_id')::uuid;
  perform teste_extrai_n_p8(v_ver, 3, null, null);
  v_ver2 := teste_nova_versao_p8((v_a->>'documento_id')::uuid, 'HP8-V4-2');
  perform teste_extrai_n_p8(v_ver2, 1, v_falha, v_esg);
  perform teste_assert_p8(fn_versao_com_extracao((v_a->>'documento_id')::uuid) = v_ver, 'v1 sem a flag + v2 com a flag: vigente a v1');
  -- (5) controle: nenhuma com a flag, a regra da 0102 (maior número) fica como estava
  v_a := teste_envia_p8(v_caso, 'v5.pdf', 'HP8-V5'); v_ver := (v_a->>'documento_versao_id')::uuid;
  perform teste_extrai_n_p8(v_ver, 3, null, null);
  v_ver2 := teste_nova_versao_p8((v_a->>'documento_id')::uuid, 'HP8-V5-2');
  perform teste_extrai_n_p8(v_ver2, 1, null, jsonb_build_object('falha_transitoria_esgotada', false));
  perform teste_assert_p8(fn_versao_com_extracao((v_a->>'documento_id')::uuid) = v_ver2, 'controle: nenhuma versão com a flag, vence a de maior número (a regra da 0102 intacta)');

  raise notice '--- 18h. a sonda enxerga os requisitos da 0233 ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0233' and presente;
  perform teste_assert_p8(v_n = 4, 'os 4 requisitos da 0233 estão presentes na sonda', format('presentes=%s', v_n));
  select count(*) into v_n from instalacao_requisito where migration = '0233';
  perform teste_assert_p8(v_n = 4, 'e o catálogo declara exatamente 4', format('declarados=%s', v_n));

  if current_setting('p8.medindo', true) = 'on' then
    raise warning 'MEDIDO: % falha(s) de % execucoes', coalesce(current_setting('p8.falhas', true), '0'), current_setting('p8.execucoes', true);
  end if;
  raise notice 'TODOS OS TESTES DA FALHA TRANSITÓRIA PASSARAM';
end $$;
