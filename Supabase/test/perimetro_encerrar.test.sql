-- =============================================================================
-- 0209 — fn_perimetro_definir_escopo confirma de novo sem estourar, e fn_perimetro_encerrar_escopo
--        tira a entidade do escopo (o gesto que a falta fora_do_perimetro_com_escopo_vigente da 0208 pede)
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md) — Supabase/test/perimetro_encerrar.test.sql: 28 asserts; o
-- número por guarda desligada está no cabeçalho de
-- Supabase/migrations/0209_o_escopo_que_nao_se_confirmava_nem_se_encerrava.sql.
--
-- O QUE ESTE ARQUIVO MEDE (comportamento):
--   1. definir de novo com o MESMO desde: não levanta, devolve o id vigente, não duplica linha nem evento;
--   2. definir com desde ANTERIOR ao vigente: recusa em português (não é violação de CHECK) e não altera nada;
--   3. definir com desde POSTERIOR continua fechando o anterior em desde - 1 (comportamento da 0180);
--   4. encerrar fecha o vigente com ate = p_ate (inclusivo), grava o evento e devolve o id; a entidade sai do
--      fn_perimetro_vigente depois do ate e continua nele NO ate;
--   5. encerrar sem intervalo vigente (já encerrado, outro escopo, outro caso) e com p_ate antes do desde
--      recusa em português e não grava nada; p_ate nulo recusa; p_ate = desde vale;
--   6. encerrar um escopo não toca outro escopo da mesma entidade; reabrir depois de encerrado funciona;
--   7. a falta fora_do_perimetro_com_escopo_vigente da 0208 se resolve por encerrar.
-- =============================================================================

create or replace function teste_assert_0209(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_cond then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

delete from caso where nome = '0209 — encerrar escopo';

do $$
declare
  v_caso   uuid;
  v_outro  uuid;
  v_a      uuid;
  v_h      uuid;
  v_id1    uuid;
  v_id2    uuid;
  v_n      int;
  v_ev     int;
  v_msg    text;
  v_state  text;
  v_ate    date;
  v_desde  date;
  v_s      record;
  d0       constant date := current_date - 100;
begin
  v_caso  := fn_upsert_caso('0209 — encerrar escopo');
  v_outro := fn_upsert_caso('0209 — outro caso');
  v_a := fn_upsert_entidade(v_caso, 'ESCOPO A LTDA. (0209)');
  v_h := fn_upsert_entidade(v_caso, 'HOLDING ESCOPO SA (0209)');

  raise notice '--- 1. confirmar de novo o MESMO escopo com o MESMO desde ---';
  v_id1 := fn_perimetro_definir_escopo(v_caso, v_a, 'combinado', d0, 'analista@0209');
  v_msg := null;
  begin
    v_id2 := fn_perimetro_definir_escopo(v_caso, v_a, 'combinado', d0, 'analista@0209');
  exception when others then v_msg := sqlerrm; end;
  perform teste_assert_0209(v_msg is null, 'confirmar o mesmo escopo com o mesmo desde NÃO levanta erro', v_msg);
  perform teste_assert_0209(v_id2 = v_id1, 'e devolve o id do intervalo que já estava vigente');
  select count(*) into v_n from perimetro where entidade_id = v_a;
  perform teste_assert_0209(v_n = 1, 'sem linha nova', v_n::text);
  select count(*) into v_ev from evento_auditoria
   where acao = 'perimetro_escopo_definido' and entidade_ref = 'entidade:' || v_a;
  perform teste_assert_0209(v_ev = 1, 'e sem evento novo (a trilha guarda decisões, não confirmações)', v_ev::text);

  raise notice '--- 2. desde ANTERIOR ao vigente: recusa clara, nada muda ---';
  v_msg := null; v_state := null;
  begin
    perform fn_perimetro_definir_escopo(v_caso, v_a, 'combinado', d0 - 10, 'analista@0209');
  exception when others then v_msg := sqlerrm; v_state := sqlstate; end;
  perform teste_assert_0209(v_msg is not null, 'desde anterior ao vigente é recusado');
  perform teste_assert_0209(v_state <> '23514' and v_msg like '%já está no escopo%',
    'a recusa é a frase da função, não o erro de CHECK do Postgres', format('%s: %s', v_state, v_msg));
  select count(*), min(desde), min(ate) into v_n, v_desde, v_ate from perimetro where entidade_id = v_a;
  perform teste_assert_0209(v_n = 1 and v_desde = d0 and v_ate is null,
    'e o intervalo vigente ficou intacto', format('%s linhas, desde %s, ate %s', v_n, v_desde, v_ate));

  raise notice '--- 3. desde POSTERIOR continua fechando o anterior ---';
  v_id2 := fn_perimetro_definir_escopo(v_caso, v_a, 'combinado', d0 + 10, 'analista@0209');
  select ate into v_ate from perimetro where id = v_id1;
  perform teste_assert_0209(v_ate = d0 + 9 and v_id2 <> v_id1,
    'desde posterior fecha o anterior em desde - 1 e abre outro intervalo', v_ate::text);

  raise notice '--- 3b. encerrar o intervalo errado NÃO encerra o vigente (caso errado, escopo errado) ---';
  v_msg := null;
  begin
    perform fn_perimetro_encerrar_escopo(v_outro, v_a, 'combinado', d0 + 30, 'analista@0209');
  exception when others then v_msg := sqlerrm; end;
  perform teste_assert_0209(v_msg like '%nada a encerrar%',
    'com um intervalo VIGENTE, passar o caso errado é recusado (não encerra o de outro caso)', v_msg);
  v_msg := null;
  begin
    perform fn_perimetro_encerrar_escopo(v_caso, v_a, 'escopo inexistente', d0 + 30, 'analista@0209');
  exception when others then v_msg := sqlerrm; end;
  perform teste_assert_0209(v_msg like '%nada a encerrar%',
    'com um intervalo VIGENTE em outro escopo, passar o escopo errado é recusado', v_msg);
  perform teste_assert_0209((select ate from perimetro where id = v_id2) is null,
    'e o intervalo vigente continua vigente depois das duas recusas');

  raise notice '--- 4. encerrar ---';
  v_msg := null;
  begin
    v_id1 := fn_perimetro_encerrar_escopo(v_caso, v_a, 'combinado', d0 + 20, 'analista@0209');
  exception when others then v_msg := sqlerrm; end;
  perform teste_assert_0209(v_msg is null and v_id1 = v_id2,
    'encerrar o vigente funciona e devolve o id do intervalo encerrado', v_msg);
  select ate into v_ate from perimetro where id = v_id2;
  perform teste_assert_0209(v_ate = d0 + 20, 'ate = p_ate', v_ate::text);
  perform teste_assert_0209(exists (select 1 from evento_auditoria
        where acao = 'perimetro_escopo_encerrado' and entidade_ref = 'entidade:' || v_a
          and ator = 'analista@0209' and depois->>'ate' = (d0 + 20)::text and depois->>'escopo' = 'combinado'),
    'o evento perimetro_escopo_encerrado traz ator, escopo e ate');
  perform teste_assert_0209(exists (select 1 from fn_perimetro_vigente(v_caso, 'combinado', d0 + 20) e where e.id = v_a),
    'no próprio ate a entidade ainda está dentro (ate é inclusivo)');
  perform teste_assert_0209(not exists (select 1 from fn_perimetro_vigente(v_caso, 'combinado', d0 + 21) e where e.id = v_a),
    'no dia seguinte ao ate ela já saiu');

  raise notice '--- 5. recusas do encerrar ---';
  select count(*) into v_ev from evento_auditoria where acao = 'perimetro_escopo_encerrado' and entidade_ref = 'entidade:' || v_a;
  v_msg := null;
  begin
    perform fn_perimetro_encerrar_escopo(v_caso, v_a, 'combinado', d0 + 30, 'analista@0209');
  exception when others then v_msg := sqlerrm; end;
  perform teste_assert_0209(v_msg like '%nada a encerrar%',
    'encerrar de novo (já encerrado) é recusado, não é no-op silencioso', v_msg);
  v_msg := null;
  begin
    perform fn_perimetro_encerrar_escopo(v_caso, v_a, 'outro escopo', d0 + 30, 'analista@0209');
  exception when others then v_msg := sqlerrm; end;
  perform teste_assert_0209(v_msg like '%nada a encerrar%' and v_msg like '%outro escopo%',
    'escopo sem intervalo vigente é recusado e o erro nomeia o escopo', v_msg);
  v_msg := null;
  begin
    perform fn_perimetro_encerrar_escopo(v_outro, v_a, 'combinado', d0 + 30, 'analista@0209');
  exception when others then v_msg := sqlerrm; end;
  perform teste_assert_0209(v_msg like '%nada a encerrar%', 'caso errado não encerra o intervalo de outro caso', v_msg);
  select count(*) into v_n from evento_auditoria where acao = 'perimetro_escopo_encerrado' and entidade_ref = 'entidade:' || v_a;
  perform teste_assert_0209(v_n = v_ev, 'nenhuma recusa gravou evento', format('%s x %s', v_n, v_ev));

  -- reabre e testa as outras recusas
  v_id1 := fn_perimetro_definir_escopo(v_caso, v_a, 'combinado', d0 + 40, 'analista@0209');
  perform teste_assert_0209(v_id1 <> v_id2 and (select ate from perimetro where id = v_id1) is null,
    'depois de encerrado, o escopo pode ser reaberto com desde posterior');
  v_msg := null;
  begin
    perform fn_perimetro_encerrar_escopo(v_caso, v_a, 'combinado', d0 + 39, 'analista@0209');
  exception when others then v_msg := sqlerrm; v_state := sqlstate; end;
  perform teste_assert_0209(v_msg like '%antes do começo%' and v_state <> '23514',
    'p_ate antes do desde: recusa em português (não o CHECK)', format('%s: %s', v_state, v_msg));
  perform teste_assert_0209((select ate from perimetro where id = v_id1) is null, 'e o intervalo continua vigente');
  v_msg := null;
  begin
    perform fn_perimetro_encerrar_escopo(v_caso, v_a, 'combinado', null, 'analista@0209');
  exception when others then v_msg := sqlerrm; end;
  perform teste_assert_0209(v_msg like '%p_ate não pode ser nulo%', 'p_ate nulo é recusado', v_msg);
  perform fn_perimetro_encerrar_escopo(v_caso, v_a, 'combinado', d0 + 40, 'analista@0209');
  perform teste_assert_0209((select ate from perimetro where id = v_id1) = d0 + 40,
    'p_ate igual ao desde vale (intervalo de um dia)');

  raise notice '--- 6. um escopo não toca o outro ---';
  perform fn_perimetro_definir_escopo(v_caso, v_a, 'escopo B', d0, 'analista@0209');
  perform fn_perimetro_definir_escopo(v_caso, v_a, 'escopo C', d0, 'analista@0209');
  perform fn_perimetro_encerrar_escopo(v_caso, v_a, 'escopo B', current_date - 1, 'analista@0209');
  perform teste_assert_0209((select ate from perimetro where entidade_id = v_a and escopo = 'escopo C') is null,
    'encerrar o escopo B deixa o escopo C vigente');

  raise notice '--- 7. a falta da 0208 se resolve por encerrar ---';
  perform fn_entidade_definir_papel_no_grupo(v_a, 'fora_do_perimetro', 'analista@0209');
  perform fn_entidade_definir_participacao(v_a, v_h, 30, 'analista@0209');
  perform fn_entidade_definir_forma_de_controle(v_a, 'controlada_por_entidade', 'analista@0209');
  -- 'escopo C' ainda vigente; 'combinado' já encerrado
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.entidade_id = v_a;
  perform teste_assert_0209(v_s.falta = array['fora_do_perimetro_com_escopo_vigente'],
    'controle: fora_do_perimetro com escopo vigente tem a falta da 0208', v_s.falta::text);
  perform fn_perimetro_encerrar_escopo(v_caso, v_a, 'escopo C', current_date - 1, 'analista@0209');
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.entidade_id = v_a;
  perform teste_assert_0209(v_s.pronta and v_s.falta = '{}',
    'encerrado o último escopo vigente, a entidade fora_do_perimetro fica pronta', v_s.falta::text);

  raise notice 'ESCOPO DO PERÍMETRO OK — confirmar de novo é idempotente, desde anterior e encerramento '
    'inválido recusam em português, e encerrar é o caminho para tirar a entidade do escopo';
end $$;
