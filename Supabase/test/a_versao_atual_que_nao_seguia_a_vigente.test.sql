-- Testes da 0240: fn_versao_atual (a versão que as reconciliações leem) segue a versão VIGENTE; as guardas de extração do fn_reconferir_caso leem a MAIS NOVA.
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO PROVA (comportamento):
--   (A) documento com v1 parcial (2 linhas, flag falha_transitoria_esgotada) e v2 PIOR (1 linha, flag): a reconciliação Ativo = Passivo + PL lê a v1 (a que o book mostra) e dá `ok`;
--       lendo a v2 (só o ATIVO) ela daria pré-condição. fn_versao_atual = fn_versao_com_extracao; fn_versao_mais_nova continua sendo a v2.
--   (B) controles que passam na função antiga de propósito: documento recém-registrado, sem nenhuma linha, ainda tem "versão atual" (a mais nova); v2 completa vence a v1.
--   (C) a v2 que volta SEM linha (extracao_falhou aberta) por cima de uma v1 com linha: fn_reconferir_caso NÃO fecha a pendência (lida a v1 as guardas a fechariam com "a versão tem linhas",
--       e a falha do reenvio sumiria da fila com o book mostrando a v1).
--   (D) a sonda enxerga os 3 requisitos da 0240.
--
-- ARRANJO: tudo por fn_registrar_documento / fn_registrar_campos_extraidos de verdade; à mão só a versão a mais (o reenvio de verdade só re-extrai quando a anterior não vale). Nenhum arranjo de
-- produção é reproduzido: o campo falha_transitoria_esgotada é novo (0 eventos em 10/11/2026) e o número de versões com linha em produção é 9 documentos de 1.465 (0233).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número reprovado por sabotagem está no cabeçalho de Supabase/migrations/0240_a_versao_atual_que_nao_seguia_a_vigente.sql ("MEDIÇÃO NÃO-VAZIA").
-- `p40.medindo = on` (PGOPTIONS='-c p40.medindo=on') vira `raise warning` e CONTA.

\set ON_ERROR_STOP on

create or replace function teste_assert_p40(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('p40.execucoes', (coalesce(nullif(current_setting('p40.execucoes', true), ''), '0')::int + 1)::text, false);
  if p_ok then
    raise notice 'ok    %', p_nome;
  elsif current_setting('p40.medindo', true) = 'on' then
    perform set_config('p40.falhas', (coalesce(nullif(current_setting('p40.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

create or replace function teste_envia_p40(p_caso uuid, p_nome text, p_hash text) returns jsonb language sql as $$
  select fn_registrar_documento(p_caso, 'Omega Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/' || p_nome, p_nome, true, p_hash, 'ok', p_fingerprint_extracao => 'FP-P40') $$;

-- as linhas do balanço: p_n = 1 só o ATIVO; p_n = 2 ATIVO e PASSIVO E PL (fecha: 1000 = 1000)
create or replace function teste_balanco_p40(p_versao uuid, p_n int, p_falha text, p_medicao jsonb) returns void language plpgsql as $$
declare v_l jsonb := jsonb_build_array(jsonb_build_object('ordem', 0, 'chave', 'ATIVO', 'valor_num', 1000, 'periodo_coluna', '2025', 'confianca', 0.99));
begin
  if p_n >= 2 then
    v_l := v_l || jsonb_build_object('ordem', 1, 'chave', 'PASSIVO E PATRIMÔNIO LÍQUIDO', 'valor_num', 1000, 'periodo_coluna', '2025', 'confianca', 0.99);
  end if;
  perform fn_registrar_campos_extraidos(p_versao, v_l, 'N0', p_falha, null, p_medicao);
end $$;

create or replace function teste_nova_versao_p40(p_doc uuid, p_hash text) returns uuid language sql as $$
  insert into documento_versao (documento_id, n_versao, origem_arquivo, arquivo_ref, hash, legibilidade)
  select p_doc, max(n_versao) + 1, 'supabase_storage', 'p40/' || p_hash || '.pdf', p_hash, 'ok' from documento_versao where documento_id = p_doc
  returning id $$;

delete from caso where nome like 'Caso P40 %';

do $$
declare
  v_caso uuid; v_a jsonb; v_b jsonb; v_doc uuid; v_ent uuid; v_per uuid;
  v_ver uuid; v_ver2 uuid; v_r json; v_n int;
  v_esg jsonb := jsonb_build_object('falha_transitoria_esgotada', true);
  v_falha text := 'Extração INCOMPLETA: bloco 3 sem conteúdo';
begin
  raise notice '--- A. v1 parcial (2 linhas) + v2 parcial PIOR (1 linha): a reconciliação lê a v1 ---';
  v_caso := (fn_upsert_caso('Caso P40 vigente'))::uuid;
  v_a := teste_envia_p40(v_caso, 'a.pdf', 'HP40-A');
  v_ver := (v_a->>'documento_versao_id')::uuid; v_doc := (v_a->>'documento_id')::uuid;
  perform teste_balanco_p40(v_ver, 2, v_falha, v_esg);
  v_b := teste_envia_p40(v_caso, 'a.pdf', 'HP40-A');
  perform teste_assert_p40((v_b->>'n_versao')::int = 2 and not (v_b->>'reaproveitou_extracao')::boolean, 'premissa: o reenvio criou a v2', v_b::text);
  v_ver2 := (v_b->>'documento_versao_id')::uuid;
  perform teste_balanco_p40(v_ver2, 1, v_falha, v_esg);
  perform teste_assert_p40(fn_versao_com_extracao(v_doc) = v_ver, 'premissa: o book (a versão vigente) mostra a v1');
  perform teste_assert_p40(fn_versao_atual(v_doc) = v_ver, 'fn_versao_atual segue a vigente: a v1, não a v2 parcial', coalesce(fn_versao_atual(v_doc)::text, 'null'));
  perform teste_assert_p40(fn_versao_mais_nova(v_doc) = v_ver2, 'e fn_versao_mais_nova continua a v2 (o que o reenvio criou)');
  select entidade_id, periodo_id into v_ent, v_per from documento where id = v_doc;
  v_r := fn_reconciliar_ativo_passivo_pl(v_caso, v_ent, v_per);
  perform teste_assert_p40((v_r->>'resultado') = 'ok', 'a reconciliação Ativo = Passivo + PL confere o número da v1 (ok), não o da v2 que só tem o ATIVO', v_r::text);

  raise notice '--- B. controles: o que a função antiga já fazia continua valendo ---';
  v_caso := (fn_upsert_caso('Caso P40 janela'))::uuid;
  v_a := teste_envia_p40(v_caso, 'b.pdf', 'HP40-B');
  v_doc := (v_a->>'documento_id')::uuid;
  perform teste_assert_p40(fn_versao_atual(v_doc) = (v_a->>'documento_versao_id')::uuid,
    'documento recém-registrado, sem nenhuma linha: a versão atual é a mais nova (não nula)', coalesce(fn_versao_atual(v_doc)::text, 'null'));
  perform teste_assert_p40(fn_versao_atual(gen_random_uuid()) is null, 'documento inexistente: nula');
  v_caso := (fn_upsert_caso('Caso P40 completa'))::uuid;
  v_a := teste_envia_p40(v_caso, 'c.pdf', 'HP40-C'); v_ver := (v_a->>'documento_versao_id')::uuid; v_doc := (v_a->>'documento_id')::uuid;
  perform teste_balanco_p40(v_ver, 2, v_falha, v_esg);
  v_ver2 := teste_nova_versao_p40(v_doc, 'HP40-C-2');
  perform teste_balanco_p40(v_ver2, 1, null, jsonb_build_object('falha_transitoria_esgotada', false));
  perform teste_assert_p40(fn_versao_atual(v_doc) = v_ver2, 'v2 COMPLETA (sem a flag) vence a v1 parcial, também nas reconciliações');

  raise notice '--- C. a reconferência não fecha a falha que o reenvio abriu ---';
  v_caso := (fn_upsert_caso('Caso P40 reconferir'))::uuid;
  v_a := teste_envia_p40(v_caso, 'd.pdf', 'HP40-D'); v_ver := (v_a->>'documento_versao_id')::uuid; v_doc := (v_a->>'documento_id')::uuid;
  perform teste_balanco_p40(v_ver, 2, null, null);
  v_ver2 := teste_nova_versao_p40(v_doc, 'HP40-D-2');
  perform fn_registrar_campos_extraidos(v_ver2, '[]'::jsonb, 'N0', 'Extração falhou: a leitura do reenvio voltou vazia', true, null);
  select count(*) into v_n from pendencia where documento_id = v_doc and tipo = 'extracao_falhou' and estado <> 'resolvida';
  perform teste_assert_p40(v_n = 1, 'premissa: a v2 sem linha abriu extracao_falhou', format('abertas=%s', v_n));
  perform teste_assert_p40(fn_versao_com_extracao(v_doc) = v_ver and fn_versao_mais_nova(v_doc) = v_ver2, 'premissa: o book mostra a v1 (com linha) e a mais nova é a v2 (vazia)');
  perform fn_reconferir_caso(v_caso);
  select count(*) into v_n from pendencia where documento_id = v_doc and tipo = 'extracao_falhou' and estado <> 'resolvida';
  perform teste_assert_p40(v_n = 1, 'fn_reconferir_caso NÃO fecha a extracao_falhou da v2 vazia só porque a v1 tem linhas', format('abertas=%s', v_n));

  raise notice '--- D. a sonda enxerga os requisitos da 0240 ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0240' and presente;
  perform teste_assert_p40(v_n = 3, 'os 3 requisitos da 0240 estão presentes na sonda', format('presentes=%s', v_n));
  select count(*) into v_n from instalacao_requisito where migration = '0240';
  perform teste_assert_p40(v_n = 3, 'e o catálogo declara exatamente 3', format('declarados=%s', v_n));

  if current_setting('p40.medindo', true) = 'on' then
    raise warning 'MEDIDO: % falha(s) de % execucoes', coalesce(current_setting('p40.falhas', true), '0'), current_setting('p40.execucoes', true);
  end if;
  raise notice 'TODOS OS TESTES DA 0240 PASSARAM';
end $$;
