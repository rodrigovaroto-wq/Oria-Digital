-- Teste da 0226 — o auto-aceite de linhas só vale para documento COM TIPO (P16 G1, VISTORIA_P2 §6 ALTA 2).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): 13 asserts. Medição: `PGOPTIONS=-cp16.medindo=on` faz o assert virar `raise warning 'FALHOU:'` e CONTAR.
-- Controle com a 0226 aplicada: 0 FALHOU. Com o corpo da 0204 de volta (conferido que a variante APLICOU antes de rodar): 7 de 13 FALHOU.
--
-- COMPORTAMENTO afirmado: documento sem tipo (sem entidade e sem período, como o .txt de 57 bytes medido em produção) fica com a linha PENDENTE e
-- com o evento auto_aceite_suprimido dizendo "documento sem tipo"; documento com tipo, nas mesmas condições, continua auto-aceito (o controle:
-- prova que a guarda não desligou o auto-aceite de tudo). Fixture: não reproduz o upload real do .txt; reproduz só o arranjo que o defeito exige
-- (tipo nulo, linha com confiança acima do limiar, dial N2).

\set ON_ERROR_STOP on

create or replace function teste_assert_aat(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_caso   uuid;
  v_r      jsonb;
  v_ver_s  uuid;
  v_ver_c  uuid;
  v_n      int;
  v_ret    int;
  v_st     text;
  v_ev     evento_auditoria%rowtype;
  v_campos jsonb := jsonb_build_array(jsonb_build_object('ordem', 0, 'chave', 'Saldo de caixa', 'valor_texto', '1000',
      'valor_num', '1000', 'moeda', 'BRL', 'confianca', '0.98', 'secao_canonica', 'ativo_circulante'));
begin
  v_caso := (fn_upsert_caso('0226 — auto-aceite exige tipo'))::uuid;

  raise notice '--- 0. a precondição: dial N2 com limiar, e a linha está acima dele ---';
  perform teste_assert_aat((select nivel_atual in ('N2', 'N3') and limiar_auto_clear is not null and limiar_auto_clear <= 0.98
                              from estagio_autonomia where estagio = 'extracao_linhas_financeiras'),
    'o dial da extração auto-aceita 0.98 (senão o teste mediria o dial, não o tipo)');

  raise notice '--- 1. documento SEM tipo, entidade e período: a linha NÃO é auto-aceita ---';
  v_r := fn_registrar_documento(v_caso, null, null, null, null, null, 'nome_arquivo',
    'supabase_storage', 'bucket/0226-sem-tipo.txt', 'saldo.txt', true, 'HASH-0226-SEM-TIPO', 'ok');
  v_ver_s := (v_r->>'documento_versao_id')::uuid;
  perform teste_assert_aat((select tipo_taxonomia is null and entidade_id is null and periodo_id is null
                              from documento where id = (v_r->>'documento_id')::uuid),
    'o arranjo: documento sem tipo, sem entidade e sem período');
  v_ret := fn_registrar_campos_extraidos(v_ver_s, v_campos, 'N0');
  perform teste_assert_aat(v_ret = 1, 'a função segue devolvendo o número de linhas gravadas', v_ret::text);
  select status_aceite::text into v_st from campo_extraido where documento_versao_id = v_ver_s;
  perform teste_assert_aat(v_st = 'pendente', '"Saldo de caixa: 1000" fica PENDENTE', v_st);
  select count(*) into v_n from campo_extraido where documento_versao_id = v_ver_s and (aceito_por is not null or aceito_em is not null);
  perform teste_assert_aat(v_n = 0, 'sem aceito_por nem aceito_em', v_n::text);
  select * into v_ev from evento_auditoria
    where acao = 'auto_aceite_suprimido' and entidade_ref = 'documento_versao:' || v_ver_s;
  perform teste_assert_aat(v_ev.id is not null, 'o evento auto_aceite_suprimido foi gravado');
  perform teste_assert_aat((v_ev.depois->>'porque') like 'documento sem tipo%', 'e o porque nomeia "documento sem tipo"', v_ev.depois::text);
  perform teste_assert_aat((v_ev.depois->>'n_elegiveis')::int = 1, 'e conta a linha que seria aceita', v_ev.depois::text);
  perform teste_assert_aat(not exists (select 1 from decisao where caso_id = v_caso and autor = 'sistema:auto_aceite'
                                         and payload->>'documento_versao_id' = v_ver_s::text),
    'nenhuma decisao de auto-aceite foi gravada para ele');

  raise notice '--- 2. o CONTROLE: o mesmo arranjo COM tipo continua auto-aceito ---';
  v_r := fn_registrar_documento(v_caso, 'Controle Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/0226-com-tipo.pdf', 'bp.pdf', true, 'HASH-0226-COM-TIPO', 'ok');
  v_ver_c := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver_c, v_campos, 'N0');
  select status_aceite::text into v_st from campo_extraido where documento_versao_id = v_ver_c;
  perform teste_assert_aat(v_st = 'aceito', 'com tipo, a linha 0.98 é auto-aceita como sempre', v_st);
  perform teste_assert_aat(exists (select 1 from decisao where caso_id = v_caso and autor = 'sistema:auto_aceite'
                                     and payload->>'documento_versao_id' = v_ver_c::text),
    'e a decisao de auto-aceite é gravada');
  perform teste_assert_aat(not exists (select 1 from evento_auditoria
      where acao = 'auto_aceite_suprimido' and entidade_ref = 'documento_versao:' || v_ver_c),
    'e nenhuma supressão é registrada para ele');

  raise notice '--- 3. a sonda vê a correção ---';
  perform teste_assert_aat((select presente from fn_instalacao_conferir() where chave = 'campos_auto_aceite_exige_tipo'),
    'a sonda: campos_auto_aceite_exige_tipo (0226) presente');

  raise notice 'TODOS OS TESTES DO AUTO-ACEITE SEM TIPO PASSARAM';
end $$;
