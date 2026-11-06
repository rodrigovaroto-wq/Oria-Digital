-- Teste da 0224 — fn_revisar_documento não confirma documento SEM tipo (P16, VISTORIA_P2 §6 ALTA 1).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): 19 asserts. Medição: `PGOPTIONS=-cp16.medindo=on` faz o assert virar `raise warning 'FALHOU:'` e CONTAR,
-- em vez de parar no primeiro. Controle com a 0224 aplicada: 0 FALHOU. Com o corpo da 0018 de volta (conferido que a variante APLICOU
-- antes de rodar): 10 de 19 FALHOU.
--
-- O QUE SE AFIRMA É COMPORTAMENTO: confirmar documento sem tipo devolve recusa e NADA muda (nem documento, nem entidade/período novos, nem
-- decisao, nem evento, nem checklist, nem a pendência); com tipo (novo ou antigo) a confirmação segue como na 0018.
-- Fixture: o documento sem tipo é construído por INSERT direto (é o estado que produção mostrou: .txt de 57 bytes sem classificação); não se
-- reproduz o upload real, só o arranjo que o defeito exige (documento.tipo_taxonomia nulo + pendência de classificação aberta).

\set ON_ERROR_STOP on

create or replace function teste_assert_rev(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  elsif current_setting('p16.medindo', true) = 'on' then
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

do $$
declare
  v_caso  uuid;
  v_doc   uuid;
  v_pend  uuid;
  v_r     jsonb;
  v_tipo  text;
  v_d     documento%rowtype;
  v_n     int;
  v_nd0   int;
  v_ne0   int;
begin
  select codigo into v_tipo from taxonomia_tipo_documento order by codigo limit 1;
  v_caso := (fn_upsert_caso('0224 — documento sem tipo'))::uuid;
  insert into documento (caso_id, tipo_taxonomia) values (v_caso, null) returning id into v_doc;
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id)
    values (v_caso, 'classificacao', 'classificacao_pendente', 'bloqueante', true, 'documento sem tipo', v_doc)
    returning id into v_pend;
  select count(*) into v_nd0 from decisao where caso_id = v_caso;
  select count(*) into v_ne0 from entidade where caso_id = v_caso;

  raise notice '--- 1. sem tipo (novo nem antigo): recusa como valor, nada gravado ---';
  v_r := fn_revisar_documento(v_doc, 'ana@oria', null, null, null, null, 'conferi');
  perform teste_assert_rev((v_r->>'recusado') = 'true', 'a confirmação sem tipo é recusada', v_r::text);
  perform teste_assert_rev((v_r->>'documento_id') = v_doc::text, 'a recusa diz de qual documento', v_r::text);
  perform teste_assert_rev((v_r->>'motivo_recusa') like 'Escolha o tipo do documento antes de confirmar%',
    'a recusa manda escolher o tipo', v_r->>'motivo_recusa');
  select * into v_d from documento where id = v_doc;
  perform teste_assert_rev(v_d.tipo_taxonomia is null and v_d.confianca is null and v_d.fonte is null,
    'o documento segue sem tipo, sem confiança e sem fonte (nada de "100% · Humano")',
    format('tipo=%s conf=%s fonte=%s', v_d.tipo_taxonomia, v_d.confianca, v_d.fonte));
  perform teste_assert_rev((select estado::text from pendencia where id = v_pend) = 'aberta',
    'a pendência de classificação continua aberta');
  select count(*) into v_n from decisao where caso_id = v_caso;
  perform teste_assert_rev(v_n = v_nd0, 'nenhuma decisao gravada', format('%s -> %s', v_nd0, v_n));
  perform teste_assert_rev(not exists (select 1 from evento_auditoria
      where acao = 'documento_revisado' and entidade_ref = 'documento:' || v_doc),
    'nenhum evento documento_revisado');
  perform teste_assert_rev(not exists (select 1 from checklist_item_status where documento_id = v_doc),
    'nenhum item de checklist criado');

  raise notice '--- 2. a recusa vem ANTES de qualquer escrita: entidade/período novos não nascem ---';
  v_r := fn_revisar_documento(v_doc, 'ana@oria', null, 'ENTIDADE FANTASMA 0224', 'anual', '2099', 'conferi');
  perform teste_assert_rev((v_r->>'recusado') = 'true', 'sem tipo e com entidade/período novos: recusado', v_r::text);
  select count(*) into v_n from entidade where caso_id = v_caso;
  perform teste_assert_rev(v_n = v_ne0, 'a entidade nova não foi criada', format('%s -> %s', v_ne0, v_n));
  perform teste_assert_rev(not exists (select 1 from periodo where caso_id = v_caso and referencia = '2099'),
    'o período novo não foi criado');

  raise notice '--- 3. escolhido o tipo, confirma como sempre ---';
  v_r := fn_revisar_documento(v_doc, 'ana@oria', v_tipo, null, null, null, 'tipo escolhido');
  perform teste_assert_rev(v_r->>'recusado' is null and (v_r->>'tipo_taxonomia') = v_tipo and (v_r->>'mudou_tipo') = 'true',
    'com tipo novo: aceito, devolve o tipo e mudou_tipo', v_r::text);
  select * into v_d from documento where id = v_doc;
  perform teste_assert_rev(v_d.tipo_taxonomia = v_tipo and v_d.confianca = 1.0 and v_d.fonte = 'humano',
    'o documento ganha o tipo, confiança 1.0 e fonte humano');
  perform teste_assert_rev((select estado::text from pendencia where id = v_pend) = 'resolvida',
    'a pendência de classificação é resolvida');
  perform teste_assert_rev(exists (select 1 from decisao where caso_id = v_caso and tipo = 'correcao_classificacao'),
    'grava a decisao de correção de classificação');
  perform teste_assert_rev(exists (select 1 from checklist_item_status where documento_id = v_doc and tipo_taxonomia = v_tipo),
    'e o item de checklist do tipo escolhido');

  raise notice '--- 4. documento que JÁ tem tipo: confirmar sem escolher outro continua valendo ---';
  v_r := fn_revisar_documento(v_doc, 'ana@oria', null, null, null, null, 'conferido');
  perform teste_assert_rev(v_r->>'recusado' is null and (v_r->>'mudou_tipo') = 'false',
    'tipo antigo mantido: aceito, sem mudança de tipo', v_r::text);
  perform teste_assert_rev(exists (select 1 from decisao where caso_id = v_caso and tipo = 'aprovacao'),
    'e grava a decisao de aprovação');

  raise notice '--- 5. a sonda vê a correção ---';
  perform teste_assert_rev((select presente from fn_instalacao_conferir() where chave = 'revisar_documento_recusa_sem_tipo'),
    'a sonda: revisar_documento_recusa_sem_tipo (0224) presente');

  raise notice 'TODOS OS TESTES DO DOCUMENTO SEM TIPO PASSARAM';
end $$;
