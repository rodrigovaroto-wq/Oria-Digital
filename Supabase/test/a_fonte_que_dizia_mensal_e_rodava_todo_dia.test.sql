-- Testes da 0304: o catálogo fonte_externa acompanha o macro da A3 (juros por modalidade conectada via SGS, mensal, 30 dias).
-- Rodar via Supabase/test/run.sh.
--
-- O QUE ESTE ARQUIVO PROVA (comportamento, regra 3): uma consulta de juros por modalidade vence em 30 dias (a próxima publicação mensal do BCB), e a de bcb_sgs
-- segue vencendo em 1 dia (a busca diária não vira prazo); as três fontes que o macro lê têm endereço; e a sonda enxerga o requisito da 0304 (é o que separa
-- "0304 não aplicada" de "aplicada"). Não afirma o TEXTO das observações: texto se reescreve, o estado não.
--
-- DE ONDE VÊM OS DADOS (regra 4): nenhum bug de produção é reproduzido. O desfecho (200 com um item) é escrito à mão, como entrada da função de registro.
-- Cada consulta criada é apagada no fim em modo replica (o DELETE é recusado de propósito, como na suíte da 0303).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): números de asserts e de reprovações vão na mensagem do commit. `ct304.medindo = on` (PGOPTIONS='-c ct304.medindo=on') vira
-- `raise warning` e CONTA (ct304.execucoes / ct304.falhas); sem a variável, o assert é `raise exception` (o CI).

\set ON_ERROR_STOP on

create or replace function teste_assert_0304(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('ct304.execucoes', (coalesce(nullif(current_setting('ct304.execucoes', true), ''), '0')::int + 1)::text, false);
  if p_ok is true then
    raise notice 'ok    %', p_nome;
  elsif current_setting('ct304.medindo', true) = 'on' then
    perform set_config('ct304.falhas', (coalesce(nullif(current_setting('ct304.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

do $$
declare
  v_j jsonb;
  v_n int;
begin
  perform set_config('session_replication_role', 'replica', true);
  delete from fato_externo;
  delete from consulta_externa;
  perform set_config('session_replication_role', 'origin', true);

  raise notice '--- 1. as fontes que o macro lê têm endereço, e os juros têm prazo de publicação mensal ---';
  select count(*) into v_n from fonte_externa where chave in ('bcb_sgs', 'bcb_focus', 'bcb_juros_modalidade') and url is not null;
  perform teste_assert_0304(v_n = 3, 'bcb_sgs, bcb_focus e bcb_juros_modalidade têm url', v_n::text);
  perform teste_assert_0304((select cadencia = 'mensal' and validade_dias = 30 and validade_origem = 'cadencia' from fonte_externa where chave = 'bcb_juros_modalidade'),
    'juros por modalidade: cadência mensal, 30 dias, origem cadencia (o BCB publica a série todo mês)');
  perform teste_assert_0304((select cadencia is null and validade_dias = 1 and validade_origem = 'minimo_por_desconhecida' from fonte_externa where chave = 'bcb_sgs')
    and (select cadencia is null and validade_dias = 1 and validade_origem = 'minimo_por_desconhecida' from fonte_externa where chave = 'bcb_focus'),
    'bcb_sgs e bcb_focus seguem no mínimo de 1 dia: buscar todo dia não é a cadência de publicação');

  raise notice '--- 2. o prazo da consulta vem do catálogo ---';
  v_j := fn_registrar_consulta_externa('bcb_juros_modalidade', null, null, 200, null, '[{"data":"01/10/2026","valor":"21.5"}]', '[{"chave":"juros_pj_total","valor":21.5}]'::jsonb, null, 0);
  perform teste_assert_0304(v_j ->> 'resultado' = 'encontrado', 'a consulta de juros por modalidade é gravada como encontrado', v_j ->> 'resultado');
  perform teste_assert_0304((select validade_em = data_consulta + interval '30 days' from consulta_externa where id = (v_j ->> 'id')::uuid),
    'a consulta de juros por modalidade vence 30 dias depois de feita');
  v_j := fn_registrar_consulta_externa('bcb_sgs', null, null, 200, null, '[{"data":"01/10/2026","valor":"0.50"}]', '[{"chave":"ipca_2026_10","valor":0.50}]'::jsonb, null, 0);
  perform teste_assert_0304((select validade_em = data_consulta + interval '1 day' from consulta_externa where id = (v_j ->> 'id')::uuid),
    'a consulta de bcb_sgs continua vencendo em 1 dia');

  raise notice '--- 3. a sonda enxerga o requisito da 0304 ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0304';
  perform teste_assert_0304(v_n = 1, 'o catálogo da 0304 tem 1 requisito (não está vazio)', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0304' and not presente;
  perform teste_assert_0304(v_n = 0, 'e a sonda o enxerga presente', (select string_agg(chave || ': ' || coalesce(detalhe, ''), ' | ') from fn_instalacao_conferir() where migration = '0304' and not presente));

  perform set_config('session_replication_role', 'replica', true);
  delete from fato_externo;
  delete from consulta_externa;
  perform set_config('session_replication_role', 'origin', true);
  select count(*) into v_n from consulta_externa;
  perform teste_assert_0304(v_n = 0, 'o banco volta limpo', v_n::text);

  raise notice 'EXECUCOES=% FALHAS=%', current_setting('ct304.execucoes', true), coalesce(current_setting('ct304.falhas', true), '0');
  if current_setting('ct304.medindo', true) is distinct from 'on' then
    raise notice 'TODOS OS TESTES DA 0304 PASSARAM';
  end if;
end $$;
