-- Testes da 0232: a fila de reprocesso (fn_fila_de_reprocesso).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO PROVA (comportamento, não mecanismo): a fila lista UMA linha por documento do mandato com `extracao_falhou` não resolvida, na versão mais nova, e diz se reenviar
-- o original guardado re-extrairia (`reprocessavel`) ou por que não (`motivo_bloqueio`). A coluna `reprocessavel` é provada contra o COMPORTAMENTO do reenvio: onde a fila diz
-- reprocessavel, fn_registrar_documento do mesmo hash e fingerprint NÃO reaproveita; onde diz 'reaproveitaria', reaproveita. Um usuário sem alocação no mandato não vê linha (RLS).
--
-- ARRANJO MONTADO À MÃO (e só ele): a pendência `extracao_falhou` é inserida direto (o que se afirma é a LEITURA da fila, não o Sinal que a abre — esse é do o_balanco_sem_dado_financeiro.test.sql),
-- a linha de campo_extraido vem de fn_registrar_campos_extraidos de verdade, e a versão 2 do cenário "versão antiga com falha" é inserida direto (pelo caminho real, o hash igual com linha seria
-- reaproveitado e a v2 nunca nasceria — que é justamente o teto da P8). Documentos e versões vêm de fn_registrar_documento. Nada aqui reproduz um arranjo de produção.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md): 43 asserts (43 execuções); o número reprovado por sabotagem está no cabeçalho de
-- Supabase/migrations/0232_a_fila_de_reprocesso_que_o_portal_nao_tinha.sql ("MEDIÇÃO NÃO-VAZIA").
--
-- `fila.medindo = on` (PGOPTIONS='-c fila.medindo=on') vira `raise warning` e CONTA: é como se mede quantos asserts uma sabotagem reprova sem parar no primeiro.

\set ON_ERROR_STOP on

create or replace function teste_assert_0232(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('fila.execucoes', (coalesce(nullif(current_setting('fila.execucoes', true), ''), '0')::int + 1)::text, false);
  if p_ok then
    raise notice 'ok    %', p_nome;
  elsif current_setting('fila.medindo', true) = 'on' then
    perform set_config('fila.falhas', (coalesce(nullif(current_setting('fila.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- documento novo no mandato; devolve a versão. p_origem/p_ref controlam o que a fila lê do original.
drop function if exists teste_doc_0232(uuid, text, text, text, text, boolean);  -- assinatura antiga: sem isto o banco reaproveitado teria duas sobrecargas
-- p_guardar: grava também o objeto em storage.objects (o original de fato guardado no bucket); false = só o arquivo_ref, o defeito de produção.
create or replace function teste_doc_0232(p_caso uuid, p_nome text, p_hash text, p_ref text default null, p_origem text default 'supabase_storage', p_guardar boolean default true, p_fp text default 'FP-0232') returns uuid language plpgsql as $$
declare v_ref text := coalesce(p_ref, p_caso || '/' || p_hash || '.pdf');
begin
  if p_guardar then insert into storage.objects (bucket_id, name, metadata) values ('documentos', v_ref, '{"size": 3}'); end if;
  return (fn_registrar_documento(p_caso, 'Gama Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    p_origem::origem_arquivo, v_ref, p_nome, true, p_hash, 'ok', 0.7, null, p_fp)->>'documento_versao_id')::uuid;
end $$;

create or replace function teste_falha_0232(p_versao uuid, p_estado text default 'aberta', p_criada timestamptz default now(), p_descricao text default 'falhou') returns void language sql as $$
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, estado, sobrepujavel, descricao, documento_id, criada_em)
    select d.caso_id, 'extracao', 'extracao_falhou', 'bloqueante', p_estado::pendencia_estado, true, p_descricao, d.id, p_criada
      from documento_versao dv join documento d on d.id = dv.documento_id where dv.id = p_versao $$;

create or replace function teste_linha_0232(p_versao uuid) returns void language sql as $$
  select fn_registrar_campos_extraidos(p_versao,
    jsonb_build_array(jsonb_build_object('ordem', 0, 'chave', 'Caixa', 'valor_num', 100, 'unidade', 'unidade', 'confianca', 0.99)), 'N0') $$;

create or replace function teste_doc_da_versao_0232(p_versao uuid) returns uuid language sql as $$
  select documento_id from documento_versao where id = p_versao $$;

-- Entra como o usuário (JWT) com o papel authenticated; superusuário ignora RLS e passaria sobre qualquer policy.
create or replace function teste_como_0232(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;
create or replace function teste_super_0232() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
end $$;

delete from caso where nome like '0232 —%';
delete from storage.objects where name like '%/H0232-%';
delete from auth.users where id in ('00000000-0000-0000-0000-0000000232a1', '00000000-0000-0000-0000-0000000232a2');

do $$
declare
  u_ana uuid := '00000000-0000-0000-0000-0000000232a1';   -- Analista alocada em A
  u_xan uuid := '00000000-0000-0000-0000-0000000232a2';   -- Analista alocado só em B
  v_a uuid; v_b uuid;
  v1 uuid; v2 uuid; v3 uuid; v4 uuid; v5 uuid; v6 uuid; v7a uuid; v7b uuid; v8 uuid; v9 uuid; v10 uuid; v11 uuid; v12a uuid; v12b uuid; v13 uuid;
  r record; n int; v_rep int; v_r jsonb; v_ids uuid[]; v_ord text;
  t0 timestamptz := now() - interval '10 days';
begin
  v_a := fn_upsert_caso('0232 — mandato A');
  v_b := fn_upsert_caso('0232 — mandato B');

  -- 1. falha SEM linha, original no bucket -> reprocessável
  v1 := teste_doc_0232(v_a, 'sem-linha.pdf', 'H0232-1');
  perform teste_falha_0232(v1, 'aberta', t0 + interval '1 day', 'a leitura voltou vazia');
  select * into r from fn_fila_de_reprocesso(v_a) where documento_versao_id = v1;
  perform teste_assert_0232(r.documento_id is not null, 'falha sem linha: o documento está na fila');
  perform teste_assert_0232(r.reprocessavel is true and r.motivo_bloqueio is null, 'falha sem linha com original: reprocessável, sem motivo de bloqueio', r.reprocessavel::text || '/' || coalesce(r.motivo_bloqueio, 'null'));
  perform teste_assert_0232(r.tem_linha is false, 'falha sem linha: tem_linha = false');
  perform teste_assert_0232(r.nome_original = 'sem-linha.pdf' and r.arquivo_ref = v_a || '/H0232-1.pdf' and r.tipo_taxonomia = 'BALANCO' and r.n_versao = 1,
    'a linha traz nome, arquivo_ref, tipo e n_versao da versão', r.nome_original || '|' || r.arquivo_ref);
  perform teste_assert_0232(r.falha_aberta_desde = t0 + interval '1 day' and r.falha_descricao = 'a leitura voltou vazia', 'falha_aberta_desde e falha_descricao vêm da pendência');
  -- o COMPORTAMENTO que a coluna promete: o reenvio do mesmo hash e fingerprint NÃO reaproveita
  v_r := fn_registrar_documento(v_a, 'Gama Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo', 'supabase_storage', v_a || '/H0232-1.pdf', 'sem-linha.pdf', true, 'H0232-1', 'ok', 0.7, null, 'FP-0232');
  perform teste_assert_0232((v_r->>'reaproveitou_extracao')::boolean is not true, 'reprocessável: o reenvio do original NÃO é reaproveitado (re-extrai de fato)', v_r::text);
  -- o reenvio criou a versão 2: a fila passa a olhá-la
  select * into r from fn_fila_de_reprocesso(v_a) where documento_id = teste_doc_da_versao_0232(v1);
  perform teste_assert_0232(r.n_versao = 2 and r.documento_versao_id <> v1, 'depois do reenvio a fila olha a versão nova (n_versao 2)', r.n_versao::text);

  -- 2. falha COM linha -> reaproveitaria
  v2 := teste_doc_0232(v_a, 'com-linha.pdf', 'H0232-2');
  perform teste_linha_0232(v2);
  perform teste_falha_0232(v2, 'aberta', t0 + interval '2 days');
  select * into r from fn_fila_de_reprocesso(v_a) where documento_versao_id = v2;
  perform teste_assert_0232(r.documento_id is not null, 'falha com linha: o documento está na fila');
  perform teste_assert_0232(r.tem_linha is true and r.reprocessavel is false and r.motivo_bloqueio = 'reaproveitaria', 'falha com linha: não reprocessável, motivo reaproveitaria', r.reprocessavel::text || '/' || coalesce(r.motivo_bloqueio, 'null'));
  v_r := fn_registrar_documento(v_a, 'Gama Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo', 'supabase_storage', v_a || '/H0232-2.pdf', 'com-linha.pdf', true, 'H0232-2', 'ok', 0.7, null, 'FP-0232');
  perform teste_assert_0232((v_r->>'reaproveitou_extracao')::boolean is true, 'reaproveitaria: o reenvio de fato é reaproveitado (a fila não mente)', v_r::text);

  -- 3. arquivo_ref vazio -> sem_original (a coluna é NOT NULL; vazio é o que sobra de "sem arquivo")
  v3 := teste_doc_0232(v_a, 'sem-ref.pdf', 'H0232-3', null, 'supabase_storage', false);
  update documento_versao set arquivo_ref = '   ' where id = v3;
  perform teste_falha_0232(v3, 'aberta', t0 + interval '3 days');
  select * into r from fn_fila_de_reprocesso(v_a) where documento_versao_id = v3;
  perform teste_assert_0232(r.reprocessavel is false and r.motivo_bloqueio = 'sem_original', 'arquivo_ref vazio: sem_original', r.reprocessavel::text || '/' || coalesce(r.motivo_bloqueio, 'null'));

  -- 4. origem sharepoint -> sem_original (com objeto de mesmo nome no bucket, para a origem decidir sozinha)
  v4 := teste_doc_0232(v_a, 'sharepoint.pdf', 'H0232-4', 'https://sp.exemplo/doc.pdf', 'sharepoint', true);
  perform teste_falha_0232(v4, 'aberta', t0 + interval '4 days');
  select * into r from fn_fila_de_reprocesso(v_a) where documento_versao_id = v4;
  perform teste_assert_0232(r.reprocessavel is false and r.motivo_bloqueio = 'sem_original', 'origem sharepoint (mesmo com arquivo_ref preenchido): sem_original', r.reprocessavel::text || '/' || coalesce(r.motivo_bloqueio, 'null'));

  -- 5. pendência resolvida -> fora da fila
  v5 := teste_doc_0232(v_a, 'resolvida.pdf', 'H0232-5');
  perform teste_falha_0232(v5, 'resolvida', t0 + interval '5 days');
  select count(*) into n from fn_fila_de_reprocesso(v_a) where documento_versao_id = v5;
  perform teste_assert_0232(n = 0, 'pendência resolvida: o documento fica fora da fila', n::text);

  -- 6. documento de OUTRO mandato -> fora; e aparece no dele
  v6 := teste_doc_0232(v_b, 'do-b.pdf', 'H0232-6');
  perform teste_falha_0232(v6, 'aberta', t0 + interval '6 days');
  select count(*) into n from fn_fila_de_reprocesso(v_a) where documento_versao_id = v6;
  perform teste_assert_0232(n = 0, 'documento de outro mandato: fora da fila do A', n::text);
  select count(*) into n from fn_fila_de_reprocesso(v_b) where documento_versao_id = v6;
  perform teste_assert_0232(n = 1, 'o mesmo documento aparece na fila do mandato dele (B)', n::text);

  -- 7. versão antiga com falha E linha, versão nova sem linha -> usa a nova (reprocessável); a antiga, sozinha, seria reaproveitaria
  v7a := teste_doc_0232(v_a, 'duas-versoes.pdf', 'H0232-7');
  perform teste_linha_0232(v7a);
  perform teste_falha_0232(v7a, 'aberta', t0 + interval '7 days');
  insert into storage.objects (bucket_id, name, metadata) values ('documentos', v_a || '/H0232-7-v2.pdf', '{"size": 3}');
  insert into documento_versao (documento_id, n_versao, origem_arquivo, arquivo_ref, nome_original, hash, fingerprint_extracao)
    values (teste_doc_da_versao_0232(v7a), 2, 'supabase_storage', v_a || '/H0232-7-v2.pdf', 'duas-versoes-v2.pdf', 'H0232-7B', 'FP-0232') returning id into v7b;
  select count(*) into n from fn_fila_de_reprocesso(v_a) where documento_id = teste_doc_da_versao_0232(v7a);
  perform teste_assert_0232(n = 1, 'documento com duas versões: UMA linha na fila', n::text);
  select * into r from fn_fila_de_reprocesso(v_a) where documento_id = teste_doc_da_versao_0232(v7a);
  perform teste_assert_0232(r.documento_versao_id = v7b and r.n_versao = 2 and r.arquivo_ref = v_a || '/H0232-7-v2.pdf', 'usa a versão de maior n_versao (a nova), não a antiga', r.n_versao::text);
  perform teste_assert_0232(r.tem_linha is false and r.reprocessavel is true and r.motivo_bloqueio is null, 'a versão nova sem linha é reprocessável (a velha com linha não decide)', r.tem_linha::text || '/' || r.reprocessavel::text);

  -- 8. sem_original vence reaproveitaria (zero original E a função diz concluída)
  v8 := teste_doc_0232(v_a, 'sem-ref-com-linha.pdf', 'H0232-8', null, 'supabase_storage', false);
  perform teste_linha_0232(v8);
  update documento_versao set arquivo_ref = '' where id = v8;
  perform teste_falha_0232(v8, 'aberta', t0 + interval '8 days');
  select * into r from fn_fila_de_reprocesso(v_a) where documento_versao_id = v8;
  perform teste_assert_0232(r.motivo_bloqueio = 'sem_original' and r.reprocessavel is false, 'sem_original vence reaproveitaria', coalesce(r.motivo_bloqueio, 'null'));

  -- 9. duas pendências abertas no mesmo documento (uma em_correcao_interna): UMA linha, desde = a mais antiga, descrição = a mais recente
  v9 := teste_doc_0232(v_a, 'duas-falhas.pdf', 'H0232-9');
  perform teste_falha_0232(v9, 'em_correcao_interna', t0 + interval '9 days', 'a primeira');
  perform teste_falha_0232(v9, 'aberta', t0 + interval '12 days', 'a mais recente');
  perform teste_falha_0232(v9, 'resolvida', t0 + interval '13 days', 'a resolvida, mais recente de todas');
  select count(*) into n from fn_fila_de_reprocesso(v_a) where documento_versao_id = v9;
  perform teste_assert_0232(n = 1, 'duas pendências abertas no documento: UMA linha (em_correcao_interna conta como aberta, como em fn_versao_extracao_concluida)', n::text);
  select * into r from fn_fila_de_reprocesso(v_a) where documento_versao_id = v9;
  perform teste_assert_0232(r.falha_aberta_desde = t0 + interval '9 days', 'falha_aberta_desde = min(criada_em) das abertas', r.falha_aberta_desde::text);
  perform teste_assert_0232(r.falha_descricao = 'a mais recente', 'falha_descricao = a da pendência aberta mais recente (a resolvida não entra)', r.falha_descricao);

  -- 10. outro tipo de pendência não põe o documento na fila
  v10 := teste_doc_0232(v_a, 'outra-pendencia.pdf', 'H0232-10');
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id)
    values (v_a, 'completude', 'item_sem_conteudo', 'bloqueante', true, 'outra causa', teste_doc_da_versao_0232(v10));
  select count(*) into n from fn_fila_de_reprocesso(v_a) where documento_versao_id = v10;
  perform teste_assert_0232(n = 0, 'pendência de outro tipo: fora da fila', n::text);

  -- 11. arquivo_ref preenchido, origem supabase_storage, mas o OBJETO não está no bucket (o defeito de produção: 517 com ref, 11 com objeto) -> sem_original
  v11 := teste_doc_0232(v_a, 'ref-sem-objeto.pdf', 'H0232-11', null, 'supabase_storage', false);
  perform teste_falha_0232(v11, 'aberta', t0 + interval '11 days');
  select * into r from fn_fila_de_reprocesso(v_a) where documento_versao_id = v11;
  perform teste_assert_0232(r.arquivo_ref = v_a || '/H0232-11.pdf' and r.reprocessavel is false and r.motivo_bloqueio = 'sem_original',
    'arquivo_ref preenchido mas objeto ausente do bucket: sem_original', r.reprocessavel::text || '/' || coalesce(r.motivo_bloqueio, 'null'));
  insert into storage.objects (bucket_id, name, metadata) values ('documentos', v_a || '/H0232-11.pdf', '{"size": 3}');
  select * into r from fn_fila_de_reprocesso(v_a) where documento_versao_id = v11;
  perform teste_assert_0232(r.reprocessavel is true and r.motivo_bloqueio is null, 'o mesmo documento, depois de o objeto ser guardado: reprocessável', r.reprocessavel::text);
  delete from storage.objects where bucket_id = 'documentos' and name = v_a || '/H0232-11.pdf';
  insert into storage.objects (bucket_id, name, metadata) values ('outro-bucket', v_a || '/H0232-11.pdf', '{"size": 3}');
  select * into r from fn_fila_de_reprocesso(v_a) where documento_versao_id = v11;
  perform teste_assert_0232(r.reprocessavel is false and r.motivo_bloqueio = 'sem_original', 'objeto de mesmo nome em OUTRO bucket não conta', r.reprocessavel::text);
  delete from storage.objects where bucket_id = 'outro-bucket';

  -- 12. (a) o MESMO arquivo registrado 2x antes de extrair: v1 com linha, v2 (a mais nova) sem. O registrar reaproveita a v1 (qualquer versão do caso com o hash e o fingerprint, concluída);
  --     a fila, que olha a v2, tem de dizer reaproveitaria — não reprocessável (o botão não extrairia nada e a pendência ficaria aberta).
  v12a := teste_doc_0232(v_a, 'duas-vezes.pdf', 'H0232-12');
  v_r := fn_registrar_documento(v_a, 'Gama Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo', 'supabase_storage', v_a || '/H0232-12.pdf', 'duas-vezes.pdf', true, 'H0232-12', 'ok', 0.7, null, 'FP-0232');
  v12b := (v_r->>'documento_versao_id')::uuid;
  perform teste_assert_0232(v12b <> v12a and (v_r->>'n_versao')::int = 2, 'arranjo (a): o mesmo arquivo registrado 2x antes de extrair gera a versão 2', v_r::text);
  perform teste_linha_0232(v12a);
  perform teste_falha_0232(v12a, 'aberta', t0 + interval '14 days');
  select * into r from fn_fila_de_reprocesso(v_a) where documento_id = teste_doc_da_versao_0232(v12a);
  perform teste_assert_0232(r.documento_versao_id = v12b and r.tem_linha is false, 'arranjo (a): a fila olha a versão mais nova, sem linha', r.n_versao::text);
  perform teste_assert_0232(r.reprocessavel is false and r.motivo_bloqueio = 'reaproveitaria', 'arranjo (a): reaproveitaria (a v1 com linha vale), não reprocessável', r.reprocessavel::text || '/' || coalesce(r.motivo_bloqueio, 'null'));
  v_r := fn_registrar_documento(v_a, 'Gama Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo', 'supabase_storage', v_a || '/H0232-12.pdf', 'duas-vezes.pdf', true, 'H0232-12', 'ok', 0.7, null, 'FP-0232');
  perform teste_assert_0232((v_r->>'reaproveitou_extracao')::boolean is true, 'arranjo (a): o reenvio de fato reaproveita (a fila não mente)', v_r::text);

  -- 13. (b) a versão MAIS NOVA do documento está concluída (linha) mas com fingerprint ANTIGO; o fingerprint vigente do mandato é outro. O reenvio, com o vigente, re-extrai: a fila tem de dizer reprocessável.
  v13 := teste_doc_0232(v_a, 'fingerprint-antigo.pdf', 'H0232-13', null, 'supabase_storage', true, 'FP-0232-ANTIGO');
  perform teste_linha_0232(v13);
  update documento_versao set criada_em = t0 where id = v13;
  perform teste_falha_0232(v13, 'aberta', t0 + interval '13 days');
  select * into r from fn_fila_de_reprocesso(v_a) where documento_versao_id = v13;
  perform teste_assert_0232(r.tem_linha is true and r.reprocessavel is true and r.motivo_bloqueio is null, 'arranjo (b): concluída com fingerprint antigo e vigente diferente: reprocessável', r.reprocessavel::text || '/' || coalesce(r.motivo_bloqueio, 'null'));

  -- ordem: reprocessáveis primeiro, depois por falha_aberta_desde
  select string_agg(coalesce(motivo_bloqueio, 'ok'), ',' order by ord) into v_ord
    from (select row_number() over () as ord, f.* from fn_fila_de_reprocesso(v_a) f) x;
  perform teste_assert_0232(v_ord = 'ok,ok,ok,ok,reaproveitaria,sem_original,sem_original,sem_original,sem_original,reaproveitaria', 'ordem: reprocessáveis primeiro, os bloqueados depois', v_ord);
  select array_agg(documento_versao_id order by ord) into v_ids from (select row_number() over () as ord, f.* from fn_fila_de_reprocesso(v_a) f) x;
  perform teste_assert_0232(v_ids[1] = (select id from documento_versao where documento_id = teste_doc_da_versao_0232(v1) and n_versao = 2)
                            and v_ids[2] = v7b and v_ids[3] = v9 and v_ids[4] = v13, 'dentro dos reprocessáveis, por falha_aberta_desde (1, 7, 9 e 13 dias)', array_to_string(v_ids, ','));
  select count(*) into n from fn_fila_de_reprocesso(v_a);
  perform teste_assert_0232(n = 10, 'a fila do A tem exatamente os 10 documentos com falha aberta', n::text);
  v_r := fn_registrar_documento(v_a, 'Gama Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo', 'supabase_storage', v_a || '/H0232-13.pdf', 'fingerprint-antigo.pdf', true, 'H0232-13', 'ok', 0.7, null, 'FP-0232');
  perform teste_assert_0232((v_r->>'reaproveitou_extracao')::boolean is not true, 'arranjo (b): o reenvio com o fingerprint vigente de fato re-extrai (a fila não mente)', v_r::text);
  select count(*) into n from fn_fila_de_reprocesso(null);
  perform teste_assert_0232(n = 0, 'caso nulo: fila vazia, nunca erro', n::text);

  -- RLS: o analista alocado em A vê a fila de A; o alocado só em B não vê nenhuma linha dela
  insert into auth.users (id, email) values (u_ana, 'ana@0232.local'), (u_xan, 'xan@0232.local');
  perform fn_definir_papel(u_ana, 'analista');
  perform fn_definir_papel(u_xan, 'analista');
  perform fn_alocar(v_a, u_ana);
  perform fn_alocar(v_b, u_xan);
  perform teste_como_0232(u_ana);
  select count(*), count(*) filter (where reprocessavel) into n, v_rep from fn_fila_de_reprocesso(v_a);
  perform teste_super_0232();
  perform teste_assert_0232(n = 10 and v_rep = 4, 'RLS: o analista alocado no mandato vê as 10 linhas e os 4 reprocessáveis (objetos do bucket (a policy de storage.objects deixa o invoker ver)', n::text || '/' || v_rep::text);
  perform teste_como_0232(u_xan);
  select count(*) into n from fn_fila_de_reprocesso(v_a);
  perform teste_super_0232();
  perform teste_assert_0232(n = 0, 'RLS: o analista SEM alocação no mandato não vê linha nenhuma', n::text);
  perform teste_como_0232(u_xan);
  select count(*) into n from fn_fila_de_reprocesso(v_b);
  perform teste_super_0232();
  perform teste_assert_0232(n = 1, 'RLS: o mesmo analista vê a fila do mandato dele (a RLS não esconde tudo)', n::text);

  perform teste_assert_0232(has_function_privilege('authenticated', 'fn_fila_de_reprocesso(uuid)', 'execute')
                            and has_function_privilege('service_role', 'fn_fila_de_reprocesso(uuid)', 'execute')
                            and not has_function_privilege('anon', 'fn_fila_de_reprocesso(uuid)', 'execute'),
    'ACL: authenticated e service_role executam; anon não');
  perform teste_assert_0232(not (select prosecdef from pg_proc where proname = 'fn_fila_de_reprocesso') and (select provolatile from pg_proc where proname = 'fn_fila_de_reprocesso') = 's',
    'SECURITY INVOKER e stable');
  perform teste_assert_0232(not exists (select 1 from fn_instalacao_conferir() where migration = '0232' and not presente),
    'a sonda reconhece os requisitos da 0232 como presentes',
    (select string_agg(chave, ',') from fn_instalacao_conferir() where migration = '0232' and not presente));
  perform teste_assert_0232((select count(*) from fn_instalacao_conferir() where migration = '0232') = 4, 'a sonda tem os 4 requisitos da 0232');

  if current_setting('fila.medindo', true) = 'on' then
    raise warning 'MEDIDO: % falha(s) de % execucoes', coalesce(current_setting('fila.falhas', true), '0'), current_setting('fila.execucoes', true);
  end if;
end $$;
