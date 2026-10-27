-- =============================================================================
-- 0210 — O authenticated ESCREVE o perímetro da F1 (a tela chama as funções COMO authenticated, e os testes
--        da 0178–0209 rodavam como superusuário, que ignora a RLS)
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md) — Supabase/test/f1_escrita_authenticated.test.sql: 20 asserts;
-- o número com as policies novas removidas está no cabeçalho de
-- Supabase/migrations/0210_a_escrita_do_perimetro_que_so_o_superusuario_fazia.sql.
--
-- O QUE ESTE ARQUIVO MEDE (comportamento): cada função de escrita da F1 que a tela vai usar, chamada com
-- `set local role authenticated`, GRAVA (a linha esperada e, quando a função grava evento, o evento); apagar
-- direto em perimetro, controlador e entidade_controlador continua negado; a fusão de entidades (que apaga a
-- absorvida por cascata) funciona como authenticated; e a sonda enxerga a policy ausente.
-- Os dados são montados como superusuário (fn_upsert_entidade não é da tela da F1) e o resto roda como
-- authenticated. Cada chamada é isolada num begin/exception para que o relatório diga QUAIS funções falham.
-- =============================================================================

create or replace function teste_assert_0210(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_cond then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

delete from caso where nome in ('0210 — escrita authenticated');

do $$
declare
  v_caso uuid; v_e1 uuid; v_e2 uuid; v_e3 uuid; v_e4 uuid; v_ctrl uuid;
  v_err text; v_n int; v_ev0 int; v_ev1 int;
  d0 constant date := current_date - 100;
  v_presente boolean;
begin
  -- montagem como superusuário
  v_caso := fn_upsert_caso('0210 — escrita authenticated');
  v_e1 := fn_upsert_entidade(v_caso, 'PRIMEIRA LTDA. (0210)');
  v_e2 := fn_upsert_entidade(v_caso, 'SEGUNDA SA (0210)');
  v_e3 := fn_upsert_entidade(v_caso, 'TERCEIRA LTDA. (0210)');
  v_e4 := fn_upsert_entidade(v_caso, 'QUARTA LTDA. (0210)');

  perform teste_como_admin_0216();
  set local role authenticated;

  raise notice '--- 1. as funções de escrita da F1, COMO authenticated ---';
  select count(*) into v_ev0 from evento_auditoria where ator = 'portal@0210';

  v_err := null;
  begin perform fn_entidade_definir_participacao(v_e1, v_e2, 60, 'portal@0210');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  perform teste_assert_0210(v_err is null and (select controladora_id from entidade where id = v_e1) = v_e2,
    'fn_entidade_definir_participacao grava a controladora', v_err);

  v_err := null;
  begin perform fn_entidade_definir_forma_de_controle(v_e1, 'controlada_por_entidade', 'portal@0210');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  perform teste_assert_0210(v_err is null
    and (select forma_de_controle from entidade where id = v_e1) = 'controlada_por_entidade',
    'fn_entidade_definir_forma_de_controle grava a forma', v_err);

  v_err := null;
  begin perform fn_entidade_definir_papel_no_grupo(v_e1, 'operacional', 'portal@0210');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  perform teste_assert_0210(v_err is null
    and (select papel_no_grupo from entidade where id = v_e1) = 'operacional',
    'fn_entidade_definir_papel_no_grupo grava o papel', v_err);

  v_err := null;
  begin perform fn_perimetro_definir_escopo(v_caso, v_e1, 'combinado', d0, 'portal@0210');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  perform teste_assert_0210(v_err is null
    and exists (select 1 from perimetro where entidade_id = v_e1 and escopo = 'combinado' and desde = d0 and ate is null),
    'fn_perimetro_definir_escopo grava o intervalo', v_err);

  v_err := null;
  begin perform fn_perimetro_definir_escopo(v_caso, v_e1, 'combinado', d0 + 10, 'portal@0210');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  perform teste_assert_0210(v_err is null
    and (select ate from perimetro where entidade_id = v_e1 and desde = d0) = d0 + 9
    and exists (select 1 from perimetro where entidade_id = v_e1 and desde = d0 + 10 and ate is null),
    'e a troca de escopo FECHA o anterior (UPDATE) e abre o novo (INSERT) como authenticated', v_err);

  v_err := null;
  begin perform fn_perimetro_encerrar_escopo(v_caso, v_e1, 'combinado', d0 + 20, 'portal@0210');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  perform teste_assert_0210(v_err is null
    and (select ate from perimetro where entidade_id = v_e1 and desde = d0 + 10) = d0 + 20,
    'fn_perimetro_encerrar_escopo fecha o intervalo vigente', v_err);

  v_err := null;
  begin v_ctrl := fn_controlador_registrar(v_caso, 'Sócio da Silva (0210)', '123.456.789-00', 'fisica', 'portal@0210');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  perform teste_assert_0210(v_err is null and exists (select 1 from controlador where id = v_ctrl and nome = 'Sócio da Silva (0210)'),
    'fn_controlador_registrar grava o controlador', v_err);

  v_err := null;
  begin perform fn_entidade_definir_controlador(v_e2, v_ctrl, 40, 'portal@0210');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  perform teste_assert_0210(v_err is null
    and (select percentual from entidade_controlador where entidade_id = v_e2 and controlador_id = v_ctrl) = 40,
    'fn_entidade_definir_controlador grava o vínculo (INSERT)', v_err);

  v_err := null;
  begin perform fn_entidade_definir_controlador(v_e2, v_ctrl, 45, 'portal@0210');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  perform teste_assert_0210(v_err is null
    and (select percentual from entidade_controlador where entidade_id = v_e2 and controlador_id = v_ctrl) = 45,
    'e reatribuir o percentual (o ON CONFLICT DO UPDATE) também grava', v_err);

  v_err := null;
  begin perform fn_entidade_definir_forma_de_controle(v_e2, 'controle_comum', 'portal@0210');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  perform teste_assert_0210(v_err is null
    and (select forma_de_controle from entidade where id = v_e2) = 'controle_comum',
    'controle_comum, que lê o vínculo na própria guarda, grava como authenticated', v_err);

  select count(*) into v_ev1 from evento_auditoria where ator = 'portal@0210';
  perform teste_assert_0210(v_ev1 - v_ev0 = 10,
    'as 10 chamadas gravaram 10 eventos de auditoria (o authenticated escreve evento_auditoria)',
    format('%s eventos', v_ev1 - v_ev0));

  raise notice '--- 2. apagar direto continua negado ---';
  v_err := null;
  begin delete from perimetro where entidade_id = v_e1;
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0210(v_err = '42501', 'delete direto em perimetro é negado (permission denied)', v_err);
  v_err := null;
  begin delete from controlador where id = v_ctrl;
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0210(v_err = '42501', 'delete direto em controlador é negado', v_err);
  v_err := null;
  begin delete from entidade_controlador where entidade_id = v_e2;
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0210(v_err = '42501', 'delete direto em entidade_controlador é negado', v_err);
  select count(*) into v_n from perimetro where entidade_id = v_e1;
  perform teste_assert_0210(v_n = 2, 'e o histórico do perímetro continua inteiro (2 intervalos)', v_n::text);

  raise notice '--- 3. a fusão (apaga a absorvida por cascata) como authenticated ---';
  reset role;
  perform teste_fim_admin_0216();
  v_ctrl := fn_controlador_registrar(v_caso, 'Outro Sócio (0210)', null, 'fisica', 'setup@0210');
  perform fn_entidade_definir_controlador(v_e3, v_ctrl, 30, 'setup@0210');
  perform teste_como_admin_0216();
  set local role authenticated;
  v_err := null;
  begin perform fn_fundir_entidade(v_caso, v_e3, v_e4, 'portal@0210');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  perform teste_assert_0210(v_err is null and not exists (select 1 from entidade where id = v_e3),
    'fn_fundir_entidade funciona como authenticated (a entidade absorvida some)', v_err);
  perform teste_assert_0210(exists (select 1 from entidade_controlador where entidade_id = v_e4 and controlador_id = v_ctrl),
    'e o vínculo de controle da absorvida passou para a sobrevivente (UPDATE em entidade_controlador)');

  reset role;
  perform teste_fim_admin_0216();

  raise notice '--- 4. a sonda enxerga a policy ---';
  select presente into v_presente from fn_instalacao_conferir() where chave = 'perimetro_insert_policy';
  perform teste_assert_0210(v_presente is true, 'controle: com a policy instalada a sonda diz presente', v_presente::text);
  begin
    drop policy perimetro_insert on perimetro;
    select presente into v_presente from fn_instalacao_conferir() where chave = 'perimetro_insert_policy';
    raise exception 'DESFAZER:%', v_presente;
  exception when raise_exception then
    if sqlerrm not like 'DESFAZER:%' then raise; end if;
    v_err := substr(sqlerrm, 10);
  end;
  perform teste_assert_0210(v_err = 'f', 'sem a policy a sonda diz AUSENTE (a RLS sem ela nega ao authenticated)', v_err);
  perform teste_assert_0210(exists (select 1 from pg_policy where polname = 'perimetro_insert'),
    'e a subtransação foi desfeita (a policy continua instalada)');

  raise notice 'ESCRITA DA F1 COMO authenticated OK — as sete funções gravam, apagar continua negado, a fusão funciona e a sonda vê a policy';
end $$;
