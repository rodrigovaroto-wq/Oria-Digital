-- Testes do ENVELOPE do arquivo oficial (Supabase/migrations/0206): trilha desligável por caso (G25),
-- idempotência por hash, "lido" nunca sem contagem (regra 7) e a regra de versão vigente (G9).
-- Cada assert descreve COMPORTAMENTO (o que o banco aceita, recusa e devolve), não como a função o faz.
-- NÃO há fixture de produção aqui (regra 4): ainda não existe arquivo oficial real no repositório (G15);
-- os envelopes são sintéticos e só provam a regra, não que um SPED real chegue assim.
\set ON_ERROR_STOP on

create or replace function teste_assert_ao(p_ok boolean, p_nome text)
returns void language plpgsql as $$
begin
  if p_ok then raise notice 'ok    %', p_nome;
  else raise exception 'FALHOU: %', p_nome; end if;
end $$;

-- Executa um comando e devolve o SQLSTATE do erro, ou 'ok' se passou. O comando roda num subbloco:
-- o erro desfaz só ele, e o assert (fora do subbloco) não é engolido pelo `when others`.
create or replace function teste_estado_ao(p_sql text)
returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return sqlstate;
end $$;

-- Chama a função e devolve só o id (o retorno é jsonb).
create or replace function teste_reg_ao(p_caso uuid, p_doc uuid, p_env jsonb)
returns uuid language sql as $$ select (fn_registrar_arquivo_oficial(p_caso, p_doc, p_env)->>'id')::uuid $$;

-- Envelope sintético mínimo. Só o que o teste varia é argumento.
create or replace function teste_env_ao(
  p_hash text, p_chave text, p_retif boolean default false, p_status text default 'lido',
  p_tipo text default 'contagem_declarada', p_decl bigint default 10, p_lido bigint default 10)
returns jsonb language sql as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'familia', 'sped', 'subtipo', 'ECD', 'versao_leiaute', '9', 'hash_sha256', p_hash,
    'cnpj', '11222333000181', 'periodo_ini', '2025-01-01', 'periodo_fim', '2025-12-31',
    'chave_natural', p_chave, 'retificadora', p_retif, 'controle_tipo', p_tipo,
    'controle_declarado', p_decl, 'controle_lido', p_lido, 'status', p_status,
    'leitor_versao', 'teste'))
$$;

-- INSERT direto (sem a função) para exercitar os checks da tabela.
create or replace function teste_insere_ao(
  p_caso uuid, p_hash text, p_status text, p_tipo text, p_decl bigint, p_lido bigint)
returns text language plpgsql as $$
begin
  return teste_estado_ao(format(
    'insert into arquivo_oficial (caso_id, familia, hash_sha256, controle_tipo, controle_declarado, controle_lido, status, leitor_versao)
     values (%L, ''sped'', %L, %L, %s, %s, %L, ''teste'')',
    p_caso, p_hash, p_tipo, coalesce(p_decl::text, 'null'), coalesce(p_lido::text, 'null'), p_status));
end $$;

do $$
declare
  v_caso uuid; v_outro uuid; v_doc uuid;
  v_id uuid; v_id2 uuid; v_orig uuid; v_ret uuid; v_a uuid; v_b uuid; v_c uuid; v_div uuid; v_x uuid;
  v_n int; v_msg text; v_j jsonb; v_r1 uuid; v_r2 uuid; v_o2 uuid; v_z uuid;
begin
  insert into caso (nome) values ('teste arquivo oficial') returning id into v_caso;
  insert into caso (nome) values ('teste arquivo oficial outro') returning id into v_outro;

  -- 1. A TRILHA DESLIGADA RECUSA -------------------------------------------------------------------
  raise notice '--- 1. trilha desligada: recusa, não finge que rodou ---';
  perform teste_assert_ao((select trilha_transacional from caso where id = v_caso) = false,
    'caso novo nasce com a trilha desligada (nada muda até alguém ligar)');
  v_msg := null;
  begin
    perform fn_registrar_arquivo_oficial(v_caso, null, teste_env_ao('h-off', 'k-off'));
  exception when others then v_msg := sqlerrm;
  end;
  perform teste_assert_ao(v_msg is not null, 'trilha desligada recusa o registro');
  perform teste_assert_ao(v_msg like '%trilha_transacional%' and v_msg like '%' || v_caso::text || '%',
    'a recusa diz o caso e como ligar (coluna trilha_transacional)');
  perform teste_assert_ao((select count(*) from arquivo_oficial where caso_id = v_caso) = 0,
    'a recusa não gravou linha nenhuma');

  update caso set trilha_transacional = true where id in (v_caso, v_outro);

  -- 2. REGISTRO E IDEMPOTÊNCIA ---------------------------------------------------------------------
  raise notice '--- 2. registro e idempotência por hash ---';
  v_id := teste_reg_ao(v_caso, null, teste_env_ao('h-1', 'k-1'));
  perform teste_assert_ao(v_id is not null and exists (
    select 1 from arquivo_oficial where id = v_id and caso_id = v_caso and hash_sha256 = 'h-1'
       and familia = 'sped' and status = 'lido' and controle_lido = 10 and periodo_ini = date '2025-01-01'),
    'com a trilha ligada o envelope vira linha, com as chaves do jsonb nas colunas');
  v_id2 := teste_reg_ao(v_caso, null, teste_env_ao('h-1', 'k-1'));
  perform teste_assert_ao(v_id2 = v_id, 'reenviar o mesmo arquivo devolve o id que já existia');
  perform teste_assert_ao((select count(*) from arquivo_oficial where caso_id = v_caso and hash_sha256 = 'h-1') = 1,
    'reenviar o mesmo arquivo não duplica a linha');
  v_x := teste_reg_ao(v_outro, null, teste_env_ao('h-1', 'k-1'));
  perform teste_assert_ao(v_x <> v_id, 'o mesmo hash em OUTRO caso é um registro novo (a idempotência é por caso)');

  insert into documento (caso_id) values (v_caso) returning id into v_doc;
  v_x := teste_reg_ao(v_caso, v_doc, teste_env_ao('h-doc', 'k-doc'));
  perform teste_assert_ao((select documento_id from arquivo_oficial where id = v_x) = v_doc,
    'o documento da ingestão fica ligado ao envelope');

  v_x := teste_reg_ao(v_caso, null,
    teste_env_ao('h-forca', 'k-forca') || jsonb_build_object('vigente', false, 'substituido_por', v_id, 'id', v_id));
  perform teste_assert_ao(v_x <> v_id and (select vigente from arquivo_oficial where id = v_x)
    and (select substituido_por from arquivo_oficial where id = v_x) is null,
    'o envelope não consegue impor id, vigente nem substituido_por: quem decide é a regra');

  -- 3. "LIDO" NUNCA SEM CONTAGEM (checks da tabela) -------------------------------------------------
  raise notice '--- 3. coerência entre status e contagem ---';
  perform teste_assert_ao(teste_insere_ao(v_caso, 'c-1', 'lido', 'contagem_declarada', 10, null) = '23514',
    'lido sem controle_lido reprova');
  perform teste_assert_ao(teste_insere_ao(v_caso, 'c-2', 'lido', 'contagem_declarada', 10, 9) = '23514',
    'lido com contagem declarada diferente da lida reprova');
  perform teste_assert_ao(teste_insere_ao(v_caso, 'c-3', 'lido', 'contagem_declarada', null, 10) = '23514',
    'lido que devia ter contagem declarada mas veio sem ela reprova (nulo não passa por igual)');
  perform teste_assert_ao(teste_insere_ao(v_caso, 'c-4', 'controle_divergente', 'contagem_declarada', 10, 10) = '23514',
    'controle_divergente com as duas contagens iguais reprova');
  perform teste_assert_ao(teste_insere_ao(v_caso, 'c-5', 'controle_divergente', 'contagem_declarada', 10, null) = '23514',
    'controle_divergente sem a contagem lida reprova');
  perform teste_assert_ao(teste_insere_ao(v_caso, 'c-6', 'controle_divergente', 'contagem_declarada', null, 9) = '23514',
    'controle_divergente sem a contagem declarada reprova');
  perform teste_assert_ao(teste_insere_ao(v_caso, 'c-7', 'controle_divergente', 'contagem_declarada', 10, 9) = 'ok',
    'controle_divergente com as duas contagens diferentes entra');
  perform teste_assert_ao(teste_insere_ao(v_caso, 'c-8', 'lido', 'documento_unico', null, 1) = 'ok',
    'documento único lido sem contagem declarada entra, desde que diga quantos leu');
  perform teste_assert_ao(teste_insere_ao(v_caso, 'c-9', 'lido', 'sem_controle_no_formato', null, null) = '23514',
    'formato sem controle também não é "lido" sem dizer quantos registros foram lidos');
  perform teste_assert_ao(teste_insere_ao(v_caso, 'c-10', 'falhou', 'contagem_declarada', null, null) = 'ok',
    'falha sem contagem entra: a falha é visível, não precisa de contagem');
  perform teste_assert_ao(teste_insere_ao(v_caso, 'c-11', 'lido', 'contagem_inventada', 10, 10) = '23514',
    'controle_tipo fora da lista reprova');
  perform teste_assert_ao(
    teste_estado_ao(format('select fn_registrar_arquivo_oficial(%L, null, %L::jsonb)', v_caso,
      teste_env_ao('c-12', 'k-c12', false, 'lido', 'contagem_declarada', 10, null)::text)) = '23514',
    'pela função, lido sem contagem também reprova (o check vale para quem passa por ela)');
  perform teste_assert_ao((select count(*) from arquivo_oficial where hash_sha256 = 'c-12') = 0,
    'e o envelope recusado não deixa linha');

  -- 4. VERSÃO VIGENTE (G9) ---------------------------------------------------------------------------
  raise notice '--- 4. versão vigente: um SPED retificado não conta em dobro ---';
  v_orig := teste_reg_ao(v_caso, null, teste_env_ao('v-orig', 'k-vig'));
  perform teste_assert_ao((select vigente from arquivo_oficial where id = v_orig),
    'a única versão lida de uma chave é a vigente');
  v_ret := teste_reg_ao(v_caso, null, teste_env_ao('v-ret', 'k-vig', true));
  perform teste_assert_ao((select vigente from arquivo_oficial where id = v_ret),
    'a retificadora é a vigente');
  perform teste_assert_ao(not (select vigente from arquivo_oficial where id = v_orig),
    'a original deixa de ser vigente');
  perform teste_assert_ao((select substituido_por from arquivo_oficial where id = v_orig) = v_ret,
    'a original guarda quem a substituiu, como evidência');
  perform teste_assert_ao((select count(*) from arquivo_oficial where caso_id = v_caso and chave_natural = 'k-vig' and vigente) = 1,
    'exatamente uma vigente na chave');

  v_x := teste_reg_ao(v_caso, null, teste_env_ao('v-orig2', 'k-vig'));
  perform teste_assert_ao((select vigente from arquivo_oficial where id = v_ret) and not (select vigente from arquivo_oficial where id = v_x),
    'uma ORIGINAL que chega depois não derruba a retificadora');
  perform teste_assert_ao((select substituido_por from arquivo_oficial where id = v_x) = v_ret,
    'a original tardia também aponta para a retificadora');

  v_c := teste_reg_ao(v_caso, null, teste_env_ao('v-ret2', 'k-vig', true));
  perform teste_assert_ao((select count(*) from arquivo_oficial where caso_id = v_caso and chave_natural = 'k-vig' and vigente) = 0,
    'uma SEGUNDA retificadora na chave tira a vigente (a ordem do zip não decide qual retificação vale; detalhado na seção 7)');

  v_a := teste_reg_ao(v_caso, null, teste_env_ao('d-a', 'k-dup'));
  v_b := teste_reg_ao(v_caso, null, teste_env_ao('d-b', 'k-dup'));
  perform teste_assert_ao((select vigente from arquivo_oficial where id = v_b) and not (select vigente from arquivo_oficial where id = v_a),
    'entre duas originais vence a registrada por último');
  perform teste_assert_ao((select substituido_por from arquivo_oficial where id = v_a) = v_b,
    'a original anterior aponta para a última');

  v_div := teste_reg_ao(v_caso, null,
    teste_env_ao('d-div', 'k-dup', true, 'controle_divergente', 'contagem_declarada', 10, 9));
  perform teste_assert_ao(not (select vigente from arquivo_oficial where id = v_div),
    'controle_divergente nunca é vigente, mesmo sendo retificadora e a última');
  perform teste_assert_ao((select vigente from arquivo_oficial where id = v_b) and (select substituido_por from arquivo_oficial where id = v_div) is null,
    'e não derruba a vigente que já havia (um arquivo mal lido não substitui um bem lido)');
  v_x := teste_reg_ao(v_caso, null,
    teste_env_ao('d-falhou', 'k-dup', true, 'falhou', 'contagem_declarada', null, null));
  perform teste_assert_ao(not (select vigente from arquivo_oficial where id = v_x) and (select vigente from arquivo_oficial where id = v_b),
    'status falhou também nunca é vigente');
  perform teste_assert_ao((select count(*) from arquivo_oficial where caso_id = v_caso and chave_natural = 'k-dup' and vigente) = 1,
    'a chave k-dup segue com exatamente uma vigente');

  v_x := teste_reg_ao(v_caso, null,
    teste_env_ao('so-div', 'k-so-div', false, 'controle_divergente', 'contagem_declarada', 10, 9));
  perform teste_assert_ao((select count(*) from arquivo_oficial where caso_id = v_caso and chave_natural = 'k-so-div' and vigente) = 0,
    'chave só com arquivo mal lido fica SEM vigente: o número não entra como se estivesse completo');

  v_x := teste_reg_ao(v_outro, null, teste_env_ao('o-1', 'k-vig'));
  perform teste_assert_ao((select vigente from arquivo_oficial where id = v_x)
    and not (select vigente from arquivo_oficial where id = v_c),
    'a mesma chave em outro caso tem a sua própria vigente, e a ambiguidade de um caso não contamina o outro');

  v_x := teste_reg_ao(v_caso, null, teste_env_ao('sem-chave', null));
  perform teste_assert_ao((select vigente from arquivo_oficial where id = v_x),
    'lido sem chave_natural é vigente: sem identidade não há com quem competir, e sumir seria perda de dado');

  -- 5. UNICIDADE DA VIGENTE --------------------------------------------------------------------------
  raise notice '--- 5. no máximo uma vigente por (caso, chave) ---';
  perform teste_assert_ao(
    teste_estado_ao(format('update arquivo_oficial set vigente = true where id = %L', v_a)) = '23505',
    'forçar uma segunda vigente na mesma chave reprova (índice único parcial)');
  perform teste_assert_ao(
    teste_estado_ao(format('update arquivo_oficial set vigente = true where id = %L', v_div)) = '23514',
    'forçar vigente num arquivo que não está lido reprova');

  -- 6. RELEITURA DO MESMO ARQUIVO (versão desconhecida que passa a ser conhecida) -----------------------
  raise notice '--- 6. releitura: o envelope novo não é descartado ---';
  v_j := fn_registrar_arquivo_oficial(v_caso, null,
    teste_env_ao('rel-1', 'k-rel', false, 'versao_desconhecida', 'contagem_declarada', null, null));
  perform teste_assert_ao(v_j->>'status' = 'versao_desconhecida' and (v_j->>'vigente')::boolean = false
    and (v_j->>'atualizado')::boolean = false, 'primeira leitura: devolve o status gravado, sem vigente e sem atualização');
  v_j := fn_registrar_arquivo_oficial(v_caso, v_doc,
    teste_env_ao('rel-1', 'k-rel', false, 'lido', 'contagem_declarada', 7, 7) || '{"leitor_versao":"teste-2"}'::jsonb);
  perform teste_assert_ao(v_j->>'status' = 'lido' and (v_j->>'vigente')::boolean and (v_j->>'atualizado')::boolean,
    'relido com a versão agora conhecida: a linha vira lido, vigente, e a resposta diz que atualizou');
  perform teste_assert_ao((select count(*) from arquivo_oficial where caso_id = v_caso and hash_sha256 = 'rel-1') = 1
    and (select controle_lido from arquivo_oficial where hash_sha256 = 'rel-1' and caso_id = v_caso) = 7
    and (select leitor_versao from arquivo_oficial where hash_sha256 = 'rel-1' and caso_id = v_caso) = 'teste-2',
    'a releitura atualiza a MESMA linha com os campos do envelope novo, sem duplicar');
  perform teste_assert_ao((select documento_id from arquivo_oficial where hash_sha256 = 'rel-1' and caso_id = v_caso) = v_doc,
    'a releitura completa o documento_id que faltava');
  v_j := fn_registrar_arquivo_oficial(v_caso, null,
    teste_env_ao('rel-1', 'k-rel', false, 'lido', 'contagem_declarada', 7, 7) || '{"leitor_versao":"teste-2"}'::jsonb);
  perform teste_assert_ao(not (v_j->>'atualizado')::boolean and (v_j->>'vigente')::boolean,
    'lido com o mesmo leitor é reenvio puro: não atualiza');
  perform teste_assert_ao((select documento_id from arquivo_oficial where hash_sha256 = 'rel-1' and caso_id = v_caso) = v_doc,
    'o reenvio puro sem documento não apaga o documento_id');
  v_j := fn_registrar_arquivo_oficial(v_caso, null,
    teste_env_ao('rel-1', 'k-rel', false, 'lido', 'contagem_declarada', 8, 8) || '{"leitor_versao":"teste-3"}'::jsonb);
  perform teste_assert_ao((v_j->>'atualizado')::boolean and (select controle_lido from arquivo_oficial where hash_sha256 = 'rel-1' and caso_id = v_caso) = 8,
    'lido por OUTRO leitor_versao também atualiza (leitor corrigido relê)');

  -- a releitura muda a chave: as DUAS vigências são recalculadas
  v_o2 := teste_reg_ao(v_caso, null, teste_env_ao('mv-a', 'k-mv-1'));
  v_x := teste_reg_ao(v_caso, null, teste_env_ao('mv-b', 'k-mv-1'));
  perform teste_assert_ao((select vigente from arquivo_oficial where id = v_x) and not (select vigente from arquivo_oficial where id = v_o2),
    'preparo: em k-mv-1 a vigente é a última');
  perform fn_registrar_arquivo_oficial(v_caso, null,
    teste_env_ao('mv-b', 'k-mv-2', false, 'lido', 'contagem_declarada', 10, 10) || '{"leitor_versao":"teste-9"}'::jsonb);
  perform teste_assert_ao((select vigente from arquivo_oficial where id = v_o2) and (select substituido_por from arquivo_oficial where id = v_o2) is null,
    'a linha que saiu da chave antiga deixa de ofuscar a outra: a chave antiga é recalculada');
  perform teste_assert_ao((select vigente from arquivo_oficial where id = v_x) and (select chave_natural from arquivo_oficial where id = v_x) = 'k-mv-2',
    'e a chave nova também (a linha movida é vigente nela)');

  -- 7. DUAS RETIFICADORAS SEM CADEIA -------------------------------------------------------------------
  raise notice '--- 7. duas retificadoras: ausência visível, não palpite ---';
  v_orig := teste_reg_ao(v_caso, null, teste_env_ao('rr-o', 'k-rr'));
  v_r1 := teste_reg_ao(v_caso, null, teste_env_ao('rr-1', 'k-rr', true));
  perform teste_assert_ao((select vigente from arquivo_oficial where id = v_r1), 'preparo: com uma retificadora só, ela vence');
  v_r2 := teste_reg_ao(v_caso, null, teste_env_ao('rr-2', 'k-rr', true));
  perform teste_assert_ao((select count(*) from arquivo_oficial where caso_id = v_caso and chave_natural = 'k-rr' and vigente) = 0,
    'duas retificadoras lidas na mesma chave: SEM vigente');
  perform teste_assert_ao((select count(*) from arquivo_oficial where caso_id = v_caso and chave_natural = 'k-rr'
      and detalhe->>'vigencia' like 'ambigua: 2 retificadoras%') = 3,
    'as três linhas lidas da chave dizem o motivo em detalhe.vigencia');
  perform teste_assert_ao((select count(*) from arquivo_oficial where caso_id = v_caso and chave_natural = 'k-rr' and substituido_por is not null) = 0,
    'e nenhuma é dada como substituída');
  v_j := fn_registrar_arquivo_oficial(v_caso, null, teste_env_ao('rr-2', 'k-rr', true, 'lido', 'contagem_declarada', 10, 10) || '{"leitor_versao":"teste-9"}'::jsonb);
  perform teste_assert_ao(v_j->>'vigencia' like 'ambigua%' and not (v_j->>'vigente')::boolean,
    'a resposta da função carrega o motivo (o CLI não leria vigente por engano)');
  v_x := teste_reg_ao(v_caso, null, teste_env_ao('rr-f', 'k-rr', true, 'controle_divergente', 'contagem_declarada', 10, 9));
  perform teste_assert_ao((select count(*) from arquivo_oficial where caso_id = v_caso and chave_natural = 'k-rr' and vigente) = 0,
    'retificadora mal lida não conta para a ambiguidade nem para a vigência (continua a mesma ambiguidade de 2)');
  -- a ambiguidade acaba: a segunda retificadora passa a falhar na releitura
  perform fn_registrar_arquivo_oficial(v_caso, null,
    teste_env_ao('rr-2', 'k-rr', true, 'falhou', 'contagem_declarada', null, null) || '{"leitor_versao":"teste-10"}'::jsonb);
  perform teste_assert_ao((select vigente from arquivo_oficial where id = v_r1), 'sem a ambiguidade a única retificadora lida volta a ser a vigente');
  perform teste_assert_ao((select count(*) from arquivo_oficial where caso_id = v_caso and chave_natural = 'k-rr' and detalhe ? 'vigencia') = 0,
    'e o detalhe.vigencia de ambiguidade é limpo');

  -- 8. FAMILIA ZIP -----------------------------------------------------------------------------------
  raise notice '--- 8. o contêiner zip tem linha própria ---';
  v_z := teste_reg_ao(v_caso, null, jsonb_build_object('familia', 'zip', 'hash_sha256', 'zip-1', 'chave_natural', 'zip-1',
    'controle_tipo', 'contagem_declarada', 'controle_declarado', 3, 'controle_lido', 2, 'status', 'controle_divergente',
    'detalhe', jsonb_build_object('recusadas', jsonb_build_array('cifrada.txt')), 'leitor_versao', 'teste'));
  perform teste_assert_ao((select familia from arquivo_oficial where id = v_z) = 'zip'
    and (select detalhe->'recusadas'->>0 from arquivo_oficial where id = v_z) = 'cifrada.txt',
    'familia zip entra, e a entrada recusada fica registrada em detalhe');
  perform teste_assert_ao(teste_insere_ao(v_caso, 'z-2', 'lido', 'contagem_declarada', 1, 1) = 'ok'
    and teste_estado_ao(format('update arquivo_oficial set familia = ''rar'' where id = %L', v_z)) = '23514',
    'familia fora da lista (rar) continua reprovada');

  -- 9. NINGUÉM APAGA EVIDÊNCIA PELO PORTAL -------------------------------------------------------------
  raise notice '--- 9. delete negado ao authenticated ---';
  perform teste_como_admin_0216();
  set local role authenticated;
  perform teste_assert_ao(teste_estado_ao(format('delete from arquivo_oficial where id = %L', v_orig)) = '42501',
    'authenticated não apaga arquivo oficial (permission denied)');
  perform teste_assert_ao((select count(*) from arquivo_oficial where id = v_orig) = 1, 'authenticated ainda LÊ');
  reset role;
  perform teste_fim_admin_0216();
  perform teste_assert_ao(exists (select 1 from arquivo_oficial where id = v_orig), 'a linha segue lá depois da tentativa');

  delete from documento where id = v_doc;
  delete from caso where id in (v_caso, v_outro);
  raise notice 'TODOS OS TESTES DO ARQUIVO OFICIAL PASSARAM';
end $$;

drop function teste_reg_ao(uuid, uuid, jsonb);
drop function teste_insere_ao(uuid, text, text, text, bigint, bigint);
drop function teste_env_ao(text, text, boolean, text, text, bigint, bigint);
drop function teste_estado_ao(text);
drop function teste_assert_ao(boolean, text);
