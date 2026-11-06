-- Teste da 0227 — a decisão 'reabrir' de fn_decidir_pendencia (P16, VISTORIA_P2 §6 ALTA 1).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): 23 asserts. Medição: `PGOPTIONS=-cp16.medindo=on` faz o assert virar `raise warning 'FALHOU:'` e CONTAR.
-- Controle com a 0227 aplicada: 0 FALHOU. Com o corpo da 0109 de volta (conferido que a variante APLICOU antes de rodar): 16 de 23 FALHOU.
--
-- O QUE SE AFIRMA É COMPORTAMENTO: uma pendência decidida volta a `aberta`, sai da contagem de ressalvas/rejeitadas e VOLTA A BLOQUEAR o Portão 2;
-- a trilha (evento_auditoria) diz de onde veio e se desfez uma decisão. Os três ramos da 0109 seguem em pendencia_decisao.test.sql (não repetidos).
-- Sem `decisao` na reversão é DECISÃO DE DESENHO (cabeçalho da 0227), e por isso há um assert de que a decisao antiga fica e nenhuma nova nasce.

\set ON_ERROR_STOP on

create or replace function teste_assert_reab(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_pend  uuid;
  v_r     jsonb;
  v_aval  jsonb;
  v_p     pendencia%rowtype;
  v_n0    int;
  v_n     int;
  v_ev    evento_auditoria%rowtype;
begin
  v_caso := (fn_upsert_caso('0227 — reabrir pendência'))::uuid;
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
    values (v_caso, 'completude', 'item_faltante', 'bloqueante', true, 'falta o MUTUOS')
    returning id into v_pend;

  raise notice '--- 1. presa em "Contatar o Cliente" (o defeito da vistoria) volta a aberta ---';
  perform fn_decidir_pendencia(v_pend, 'analista@oria', 'contatar_cliente');
  v_r := fn_decidir_pendencia(v_pend, 'analista@oria', 'reabrir');
  perform teste_assert_reab((v_r->>'decidida') = 'true' and (v_r->>'estado') = 'aberta' and (v_r->>'rotulo') = 'Reaberta',
    'reabrir é aceito e devolve estado aberta', v_r::text);
  select * into v_p from pendencia where id = v_pend;
  perform teste_assert_reab(v_p.estado = 'aberta', 'a linha volta a aberta', v_p.estado::text);
  perform teste_assert_reab(v_p.resolvida_em is null and v_p.resolvida_por is null, 'sem resolvida_em/resolvida_por');
  perform teste_assert_reab(not (v_r->'avaliacao'->>'elegivel')::boolean, 'o portão segue fechado', v_r::text);

  raise notice '--- 2. decidida (prosseguir) libera o portão; REABRIR o fecha de novo ---';
  v_r := fn_decidir_pendencia(v_pend, 'analista@oria', 'prosseguir');
  perform teste_assert_reab((v_r->'avaliacao'->>'elegivel')::boolean and (v_r->'avaliacao'->>'ressalvas_ativas')::int = 1,
    'prosseguir libera e conta a ressalva', v_r::text);
  select count(*) into v_n0 from decisao where caso_id = v_caso;
  v_r := fn_decidir_pendencia(v_pend, 'socio@oria', 'reabrir', 'cliente mandou outro balanço');
  v_aval := fn_avaliar_portao2(v_caso);
  perform teste_assert_reab(not (v_aval->>'elegivel')::boolean and (v_aval->>'bloqueantes_abertas')::int = 1,
    'o Portão 2 volta a contar a pendência reaberta como BLOQUEANTE', v_aval::text);
  perform teste_assert_reab((v_aval->>'ressalvas_ativas')::int = 0, 'e a ressalva sai da contagem', v_aval::text);
  perform teste_assert_reab((v_r->'avaliacao'->>'elegivel')::boolean is false, 'a própria resposta já traz o portão fechado', v_r::text);
  select * into v_p from pendencia where id = v_pend;
  perform teste_assert_reab(v_p.estado = 'aberta' and v_p.resolvida_em is null and v_p.resolvida_por is null,
    'resolvida_em/por voltam a nulos depois de uma decisão final');
  perform teste_assert_reab(v_p.motivo = 'cliente mandou outro balanço', 'o motivo informado fica na pendência', v_p.motivo);

  raise notice '--- 3. a trilha: antes -> depois, e a reversão declarada ---';
  -- (criado_em é now() e o bloco é uma transação só: o evento se acha pelo estado de ORIGEM, não pela ordem.)
  select * into v_ev from evento_auditoria where acao = 'pendencia_decidida' and entidade_ref = 'pendencia:' || v_pend
    and antes->>'estado' = 'aceita_com_ressalva' and depois->>'rotulo' = 'Reaberta';
  perform teste_assert_reab(v_ev.antes->>'estado' = 'aceita_com_ressalva' and v_ev.depois->>'estado' = 'aberta'
    and v_ev.depois->>'rotulo' = 'Reaberta' and v_ev.ator = 'socio@oria',
    'evento_auditoria registra aceita_com_ressalva -> aberta, quem e o rótulo', row_to_json(v_ev)::text);
  perform teste_assert_reab((v_ev.depois->>'reverte_decisao') = 'true', 'e marca que desfez uma decisão', v_ev.depois::text);
  select count(*) into v_n from decisao where caso_id = v_caso;
  perform teste_assert_reab(v_n = v_n0, 'a reversão não grava decisao nova (nenhum decisao_tipo a descreve)', format('%s -> %s', v_n0, v_n));
  perform teste_assert_reab(exists (select 1 from decisao where caso_id = v_caso and tipo = 'ressalva'
      and payload->>'pendencia_id' = v_pend::text), 'e a decisao antiga (ressalva) NÃO é apagada');

  raise notice '--- 4. de rejeitada também volta; de em tratamento não "reverte" decisão ---';
  perform fn_decidir_pendencia(v_pend, 'analista@oria', 'nao_procede');
  v_r := fn_decidir_pendencia(v_pend, 'analista@oria', 'reabrir');
  perform teste_assert_reab((v_r->>'estado') = 'aberta' and not (v_r->'avaliacao'->>'elegivel')::boolean,
    'rejeitada -> aberta e o portão fecha', v_r::text);
  -- (criado_em é now() e o bloco é uma transação só: o evento se acha pelo estado de ORIGEM, não pela ordem.)
  select * into v_ev from evento_auditoria where acao = 'pendencia_decidida' and entidade_ref = 'pendencia:' || v_pend
    and antes->>'estado' = 'rejeitada' and depois->>'rotulo' = 'Reaberta';
  perform teste_assert_reab(v_ev.antes->>'estado' = 'rejeitada' and (v_ev.depois->>'reverte_decisao') = 'true',
    'o evento diz rejeitada -> aberta, revertendo', row_to_json(v_ev)::text);
  perform fn_decidir_pendencia(v_pend, 'analista@oria', 'contatar_cliente');
  perform fn_decidir_pendencia(v_pend, 'analista@oria', 'reabrir');
  -- (criado_em é now() e o bloco é uma transação só: o evento se acha pelo estado de ORIGEM, não pela ordem.)
  select * into v_ev from evento_auditoria where acao = 'pendencia_decidida' and entidade_ref = 'pendencia:' || v_pend
    and antes->>'estado' = 'reenviada_ao_cliente' and depois->>'rotulo' = 'Reaberta';
  perform teste_assert_reab(v_ev.antes->>'estado' = 'reenviada_ao_cliente' and (v_ev.depois->>'reverte_decisao') = 'false',
    'reenviada_ao_cliente -> aberta não conta como reversão de decisão', row_to_json(v_ev)::text);

  raise notice '--- 5. reabrir o que já está aberta é no-op; o que o sistema resolveu é recusado ---';
  select count(*) into v_n0 from evento_auditoria where acao = 'pendencia_decidida' and entidade_ref = 'pendencia:' || v_pend;
  v_r := fn_decidir_pendencia(v_pend, 'analista@oria', 'reabrir');
  perform teste_assert_reab((v_r->>'sem_mudanca') = 'true', 'reabrir de aberta: sem_mudanca', v_r::text);
  select count(*) into v_n from evento_auditoria where acao = 'pendencia_decidida' and entidade_ref = 'pendencia:' || v_pend;
  perform teste_assert_reab(v_n = v_n0, 'e não polui a trilha', format('%s -> %s', v_n0, v_n));
  update pendencia set estado = 'resolvida' where id = v_pend;
  v_r := fn_decidir_pendencia(v_pend, 'analista@oria', 'reabrir');
  perform teste_assert_reab((v_r->>'recusado') = 'true', 'reabrir de resolvida (do sistema): recusado', v_r::text);
  perform teste_assert_reab((select estado::text from pendencia where id = v_pend) = 'resolvida', 'e a pendência segue resolvida');

  raise notice '--- 6. a lista de decisões e a sonda ---';
  v_r := fn_decidir_pendencia(v_pend, 'analista@oria', 'ignorar');
  perform teste_assert_reab((v_r->>'recusado') = 'true' and (v_r->>'motivo_recusa') like '%reabrir%',
    'a recusa de decisão desconhecida lista reabrir entre as opções', v_r->>'motivo_recusa');
  perform teste_assert_reab((select presente from fn_instalacao_conferir() where chave = 'pendencia_decidir_reabrir'),
    'a sonda: pendencia_decidir_reabrir (0227) presente');

  raise notice 'TODOS OS TESTES DE REABRIR A PENDÊNCIA PASSARAM';
end $$;
