-- =============================================================================
-- 0216 — O ACESSO POR MANDATO NO BANCO: Sócio · Analista · Leitura, alocação por caso, RLS por caso
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md): 129 chamadas de assert, 217 execuções — o número por guarda desligada está no cabeçalho de
-- Supabase/migrations/0216_o_acesso_que_so_o_portal_decidia.sql (cabeçalho: "MEDIÇÃO NÃO-VAZIA").
--
-- COMO RODA. Cada usuário de teste é um JWT (`request.jwt.claims`, o que o PostgREST preenche) mais `set local role
-- authenticated` — o papel que o navegador usa. Superusuário ignora RLS: um teste que montasse e lesse como superusuário
-- passaria sobre qualquer policy (`.claude/memory/rls-so-select-passa-no-superusuario.md`). A montagem (dois mandatos, com
-- documento, campo extraído, pendência, pergunta, entidade) usa as MESMAS funções que o portal e o n8n chamam; só a
-- alocação e o papel passam por fn_definir_papel/fn_alocar, que são o que o portal vai chamar.
--
-- O QUE AFIRMA (comportamento, não mecanismo):
--   1. Analista alocado em A lê A (caso, documento, versão, campo extraído, pendência, evento, pergunta) e NÃO lê B;
--      escreve em A e não escreve em B, nem move linha de A para B;
--   2. Leitura lê A e não escreve em A (insert e update dão 42501; delete não apaga nada);
--   3. Sócio lê e escreve tudo, e é o único que aprova, fecha, reabre e exclui mandato, muda o dial e gere a equipe;
--   4. usuário SEM papel não lê nada (nem catálogo) e não cria mandato;
--   5. nunca se remove nem rebaixa o último Sócio (pela função, por DELETE direto e por cascata de auth.users);
--   6. alocar/desalocar/rebaixar/retirar muda o que a pessoa enxerga, no mesmo instante;
--   7. o Analista que cria um mandato fica alocado nele; conexão de serviço (n8n, SQL Editor) continua passando;
--   8. NENHUMA policy de authenticated sobrou como `using (true)`, e toda tabela com caso_id depende de fn_pode_*;
--   9. (revisão independente) as ~21 RPCs de trabalho mudam o mandato para a Analista alocada e NADA para Leitura nem para Analista de outro
--      mandato; id/nome de mandato alheio não se conquista (ON CONFLICT, homônimo, renomear); falha do pipeline sem caso_id lê-se pelo nome;
--      evento sem mandato só o Sócio grava; bootstrap só com `membro` vazia; DELETE da Leitura dá 42501; fn_membros_da_equipe é do Sócio.
-- =============================================================================

-- `acesso.medindo = on` (PGOPTIONS='-c acesso.medindo=on') vira `raise warning` e CONTA: é como se mede quantos asserts uma
-- guarda desligada reprova, sem parar no primeiro. Sem a variável, o assert é `raise exception` (o comportamento do CI).
create or replace function teste_assert_acesso(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('acesso.execucoes', (coalesce(nullif(current_setting('acesso.execucoes', true), ''), '0')::int + 1)::text, false);
  if p_cond then
    raise notice 'ok    %', p_nome;
  elsif current_setting('acesso.medindo', true) = 'on' then
    perform set_config('acesso.falhas', (coalesce(nullif(current_setting('acesso.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- Executa um comando COMO o papel corrente e devolve o resultado: 'ok:<linhas afetadas>' ou o SQLSTATE.
create or replace function teste_tenta_acesso(p_sql text) returns text
language plpgsql as $$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return 'ok:' || n;
exception when others then
  return sqlstate;
end $$;

-- Entra como o usuário (JWT) com o papel `authenticated`. `null` = authenticated com JWT SEM `sub`.
create or replace function teste_como_acesso(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then '{"role":"authenticated"}'
         else jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
  execute 'set local role authenticated';
end $$;

-- Volta a superusuário COM o JWT do Sócio de teste: `reset role` sozinho deixa no ar o JWT do último usuário, e a montagem
-- seguinte (fn_alocar, fn_definir_papel) levaria 42501 como se fosse ele.
create or replace function teste_super_acesso(p_socio uuid) returns void
language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_socio, 'role', 'authenticated')::text, true);
end $$;


-- IMPRESSÃO DIGITAL do que um mandato guarda: o que as RPCs de trabalho escrevem (modelagem, premissas, decisões, perímetro,
-- controladores, entidades, perguntas, campos, arquivo oficial) mais a trilha. Uma chamada que não muda nada deixa a impressão igual.
create or replace function teste_fp_acesso(p_caso uuid) returns text
language sql as $$
  select md5(concat_ws('|',
    (select coalesce(string_agg(row_to_json(x)::text, ',' order by x::text), '') from caso_modelagem x where caso_id = p_caso),
    (select coalesce(string_agg(row_to_json(x)::text, ',' order by x::text), '') from caso_premissa x where caso_id = p_caso),
    (select coalesce(string_agg(row_to_json(x)::text, ',' order by x::text), '') from caso_linha_premissa x where caso_id = p_caso),
    (select coalesce(string_agg(row_to_json(x)::text, ',' order by x::text), '') from decisao x where caso_id = p_caso),
    (select coalesce(string_agg(row_to_json(x)::text, ',' order by x::text), '') from perimetro x where caso_id = p_caso),
    (select coalesce(string_agg(row_to_json(x)::text, ',' order by x::text), '') from controlador x where caso_id = p_caso),
    (select coalesce(string_agg(row_to_json(x)::text, ',' order by x::text), '') from controlador_vinculo x where caso_id = p_caso),
    (select coalesce(string_agg(row_to_json(x)::text, ',' order by x::text), '') from entidade_controlador x where caso_id = p_caso),
    (select coalesce(string_agg(row_to_json(x)::text, ',' order by x::text), '') from entidade x where caso_id = p_caso),
    (select coalesce(string_agg(row_to_json(x)::text, ',' order by x::text), '') from caso_pergunta x where caso_id = p_caso),
    (select coalesce(string_agg(row_to_json(x)::text, ',' order by x::text), '') from pendencia x where caso_id = p_caso),
    (select coalesce(string_agg(row_to_json(x)::text, ',' order by x::text), '') from arquivo_oficial x where caso_id = p_caso),
    (select coalesce(string_agg(row_to_json(x)::text, ',' order by x::text), '') from documento x where caso_id = p_caso),
    (select coalesce(string_agg(row_to_json(c)::text, ',' order by c::text), '')
       from campo_extraido c join documento_versao v on v.id = c.documento_versao_id join documento d on d.id = v.documento_id where d.caso_id = p_caso),
    (select count(*)::text from campo_classe_override),
    (select count(*)::text from evento_auditoria)))
$$;

-- Chama `p_sql` COMO o usuário e devolve 'resultado|mudou' (mudou = a impressão do mandato mudou). Volta a superusuário no fim.
create or replace function teste_chamar_acesso(p_uid uuid, p_sql text, p_caso uuid, p_socio uuid) returns text
language plpgsql as $$
declare v_fp0 text; v_fp1 text; v_res text;
begin
  perform teste_super_acesso(p_socio);
  v_fp0 := teste_fp_acesso(p_caso);
  perform teste_como_acesso(p_uid);
  v_res := teste_tenta_acesso(p_sql);
  perform teste_super_acesso(p_socio);
  v_fp1 := teste_fp_acesso(p_caso);
  return v_res || '|' || (v_fp0 is distinct from v_fp1)::text;
end $$;

-- Limpeza de rodada anterior (o teste é reexecutável). Antes de apagar os usuários de teste há outro Sócio (a001, do run.sh).
delete from caso where nome like '0216 —%';
delete from storage.objects where name like '%-0216.pdf' or name like '%/novo.pdf';
delete from auth.users where id in ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000b002',
  '00000000-0000-0000-0000-00000000b003', '00000000-0000-0000-0000-00000000b004', '00000000-0000-0000-0000-00000000b005');
delete from evento_auditoria where acao in ('papel_definido', 'papel_removido', 'alocado', 'desalocado');

do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000000b001';   -- Sócio
  u_ana   uuid := '00000000-0000-0000-0000-00000000b002';   -- Analista, alocada em A
  u_leo   uuid := '00000000-0000-0000-0000-00000000b003';   -- Leitura, alocado em A
  u_nil   uuid := '00000000-0000-0000-0000-00000000b004';   -- SEM papel
  u_xan   uuid := '00000000-0000-0000-0000-00000000b005';   -- Analista, alocado só em B
  v_a uuid; v_b uuid; v_c uuid; v_d uuid; v_r jsonb; v_t text; v_n int; v_n2 int;
  v_ver_a uuid; v_ver_b uuid; v_doc_a uuid; v_doc_b uuid; v_pend_a uuid; v_pend_b uuid; v_pend_a2 uuid;
  v_novo uuid; v_estagio text; v_nivel text; v_tab text; v_ev0 int;
  v_rodada int; v_uid uuid; v_dif int;
  v_e1 uuid; v_e2 uuid; v_e3 uuid; v_ctl1 uuid; v_ctl2 uuid; v_ctl3 uuid; v_vinc uuid; v_campo uuid; v_arq uuid;
  v_campo_b uuid; v_chamadas text[]; v_rotulos text[]; v_i int; v_res text; v_hash text; v_falha_a uuid; v_falha_n uuid; v_falha_x uuid; v_falha_b uuid;
begin
  -- ---------------------------------------------------------------- montagem (superusuário, JWT do Sócio padrão do run.sh)
  insert into auth.users (id, email) values
    (u_socio, 'socio@0216.local'), (u_ana, 'ana@0216.local'), (u_leo, 'leo@0216.local'),
    (u_nil, 'nil@0216.local'), (u_xan, 'xan@0216.local');

  v_a := fn_upsert_caso('0216 — mandato A');
  v_b := fn_upsert_caso('0216 — mandato B');
  -- C e D são DESCARTÁVEIS: é neles que Analista e Leitura tentam fechar/excluir/aprovar. Com a guarda desligada o mandato some,
  -- e o resto do arquivo (que usa A e B) segue medindo em vez de quebrar no meio.
  v_c := fn_upsert_caso('0216 — mandato C (descartável, alvo da Analista)');
  v_d := fn_upsert_caso('0216 — mandato D (descartável, alvo de Leitura)');

  v_r := fn_registrar_documento(v_a, 'ALFA SA', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', v_a || '/hash-a-0216.pdf', 'BP Alfa.pdf', true, 'HASH-A-0216', 'ok');
  v_ver_a := (v_r->>'documento_versao_id')::uuid;  v_doc_a := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver_a, '[{"chave": "TOTAL DO ATIVO", "valor_num": "900", "confianca": "0.9"}]'::jsonb, 'N0');
  v_r := fn_registrar_documento(v_b, 'BETA SA', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', v_b || '/hash-b-0216.pdf', 'BP Beta.pdf', true, 'HASH-B-0216', 'ok');
  v_ver_b := (v_r->>'documento_versao_id')::uuid;  v_doc_b := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver_b, '[{"chave": "TOTAL DO ATIVO", "valor_num": "777", "confianca": "0.9"}]'::jsonb, 'N0');

  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id)
    values (v_a, 'completude', 'item_sem_conteudo', 'bloqueante', true, 'pendência de A', v_doc_a) returning id into v_pend_a;
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id)
    values (v_a, 'completude', 'item_sem_conteudo', 'bloqueante', true, 'segunda pendência de A', v_doc_a) returning id into v_pend_a2;
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id)
    values (v_b, 'completude', 'item_sem_conteudo', 'bloqueante', true, 'pendência de B', v_doc_b) returning id into v_pend_b;
  perform fn_registrar_pergunta_acao(v_a, 'A3', 'enviada', 'pergunta de A', 'setup@0216');
  perform fn_registrar_pergunta_acao(v_b, 'A3', 'enviada', 'pergunta de B', 'setup@0216');
  insert into storage.objects (bucket_id, name) values ('documentos', v_a || '/hash-a-0216.pdf'), ('documentos', v_b || '/hash-b-0216.pdf');

  raise notice '--- 1. a gestão da equipe: papéis e alocações pelas funções que o portal vai chamar ---';
  select count(*) into v_ev0 from evento_auditoria where acao in ('papel_definido', 'alocado');
  perform fn_definir_papel(u_socio, 'socio', 'teste 0216');
  perform fn_definir_papel(u_ana, 'analista');
  perform fn_definir_papel(u_leo, 'leitura');
  perform fn_definir_papel(u_xan, 'analista');
  perform fn_alocar(v_a, u_ana);
  perform fn_alocar(v_a, u_leo);
  perform fn_alocar(v_b, u_xan);
  perform fn_alocar(v_c, u_ana);
  perform fn_alocar(v_d, u_leo);
  select count(*) into v_n from evento_auditoria where acao in ('papel_definido', 'alocado');
  perform teste_assert_acesso(v_n - v_ev0 = 9, 'cada papel definido e cada alocação grava evento_auditoria (4 papéis + 5 alocações)', (v_n - v_ev0)::text);
  v_r := fn_definir_papel(u_ana, 'analista');
  perform teste_assert_acesso((v_r->>'mudou')::boolean = false
    and (select count(*) from evento_auditoria where acao = 'papel_definido' and entidade_ref = 'membro:' || u_ana) = 1,
    'definir o mesmo papel de novo é idempotente e não grava evento duplicado');
  v_r := fn_alocar(v_a, u_ana);
  perform teste_assert_acesso((v_r->>'mudou')::boolean = false
    and (select count(*) from alocacao where caso_id = v_a and usuario_id = u_ana) = 1, 'alocar de novo é idempotente');
  perform teste_assert_acesso(teste_tenta_acesso(format('select fn_definir_papel(%L, ''chefe'')', u_ana)) = '22023', 'papel inexistente é recusado');
  perform teste_assert_acesso(teste_tenta_acesso(format('select fn_definir_papel(%L, ''leitura'')', gen_random_uuid())) = '23503',
    'papel para usuário que não existe no Auth é recusado');
  perform teste_assert_acesso(teste_tenta_acesso(format('select fn_alocar(%L, %L)', v_a, u_nil)) = 'P0001', 'alocar usuário SEM papel é recusado');
  perform teste_assert_acesso(teste_tenta_acesso(format('select fn_alocar(%L, %L)', v_a, u_socio)) = 'P0001', 'alocar Sócio é recusado (ele já vê tudo)');
  perform teste_assert_acesso(teste_tenta_acesso(format('select fn_alocar(%L, %L)', gen_random_uuid(), u_ana)) = '23503', 'alocar em mandato que não existe é recusado');

  -- ---------------------------------------------------------------- 2. Analista ALOCADA em A
  raise notice '--- 2. Analista alocada em A: lê e escreve em A, não toca em B ---';
  perform teste_como_acesso(u_ana);
  perform teste_assert_acesso(fn_meu_papel() = 'analista', 'fn_meu_papel devolve o papel do JWT');
  foreach v_tab in array array['caso', 'documento', 'documento_versao', 'campo_extraido', 'pendencia', 'caso_pergunta', 'periodo', 'entidade'] loop
    execute format($q$select count(*) from %I where %s$q$, v_tab, case v_tab
      when 'caso' then format('id = %L', v_a)
      when 'documento_versao' then format('id = %L', v_ver_a)
      when 'campo_extraido' then format('documento_versao_id = %L', v_ver_a)
      else format('caso_id = %L', v_a) end) into v_n;
    execute format($q$select count(*) from %I where %s$q$, v_tab, case v_tab
      when 'caso' then format('id = %L', v_b)
      when 'documento_versao' then format('id = %L', v_ver_b)
      when 'campo_extraido' then format('documento_versao_id = %L', v_ver_b)
      else format('caso_id = %L', v_b) end) into v_n2;
    if v_tab = 'entidade' then
      -- entidade: a montagem acima não cria uma por mandato (fn_registrar_documento só amarra se houver CNPJ); o que importa é B = 0
      perform teste_assert_acesso(v_n2 = 0, format('Analista de A não lê %s de B', v_tab), v_n2::text);
    else
      perform teste_assert_acesso(v_n >= 1, format('Analista de A LÊ %s de A (controle positivo: o assert abaixo não é vazio)', v_tab), v_n::text);
      perform teste_assert_acesso(v_n2 = 0, format('Analista de A NÃO lê %s de B', v_tab), v_n2::text);
    end if;
  end loop;
  perform teste_assert_acesso((select count(*) from evento_auditoria where entidade_ref = 'caso:' || v_a) >= 1
    and (select count(*) from evento_auditoria where entidade_ref = 'caso:' || v_b) = 0,
    'a trilha (evento_auditoria) é lida por mandato: os eventos de A sim, os de B não');
  perform teste_assert_acesso((select count(*) from evento_auditoria where entidade_ref like 'estagio:%') = 0
    and (select count(*) from evento_auditoria where entidade_ref like 'membro:%') = 0,
    'evento sem mandato (estágio do dial, gestão de equipe) só o Sócio lê');
  perform teste_assert_acesso((select count(*) from caso where nome like '0216 —%') = 2, 'a lista de mandatos traz só os dela (A e C), não B nem D');

  perform teste_assert_acesso(teste_tenta_acesso(format($q$update pendencia set descricao = 'editada' where id = %L$q$, v_pend_a)) = 'ok:1',
    'Analista ATUALIZA pendência de A');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$update pendencia set descricao = 'invadida' where id = %L$q$, v_pend_b)) = 'ok:0'
    and (select descricao from pendencia where id = v_pend_b) is null, 'Analista não atualiza pendência de B (a linha nem aparece)');
  perform teste_super_acesso(u_socio);
  perform teste_assert_acesso((select descricao from pendencia where id = v_pend_b) = 'pendência de B',
    'e a pendência de B continua como estava (confirmado como superusuário)');
  perform teste_como_acesso(u_ana);
  perform teste_assert_acesso(teste_tenta_acesso(format($q$insert into pendencia (caso_id, origem_estagio, tipo, severidade, descricao)
      values (%L, 'completude', 'item_sem_conteudo', 'bloqueante', 'nova em A')$q$, v_a)) = 'ok:1', 'Analista INSERE pendência em A');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$insert into pendencia (caso_id, origem_estagio, tipo, severidade, descricao)
      values (%L, 'completude', 'item_sem_conteudo', 'bloqueante', 'forjada em B')$q$, v_b)) = '42501', 'Analista não INSERE pendência em B (42501)');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$update pendencia set caso_id = %L where id = %L$q$, v_b, v_pend_a)) = '42501',
    'Analista não MOVE pendência de A para B (o WITH CHECK olha o caso novo)');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$insert into caso_apresentacao_campo (caso_id, chave, valor) values (%L, 'i.kpi.tamanho_setor', 'v')$q$, v_a)) = 'ok:1'
    and teste_tenta_acesso(format($q$insert into caso_apresentacao_campo (caso_id, chave, valor) values (%L, 'i.kpi.tamanho_setor', 'v')$q$, v_b)) = '42501',
    'Analista escreve a apresentação de A e não a de B');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$insert into campo_extraido (documento_versao_id, chave, valor_num) values (%L, 'X', 1)$q$, v_ver_a)) = 'ok:1'
    and teste_tenta_acesso(format($q$insert into campo_extraido (documento_versao_id, chave, valor_num) values (%L, 'X', 1)$q$, v_ver_b)) = '42501',
    'campo extraído (a tabela chega ao caso por versão -> documento): escreve na versão de A e não na de B');
  v_t := teste_tenta_acesso(format($q$select fn_decidir_pendencia(%L, 'ana@0216', 'prosseguir', 'decidida pela Analista')$q$, v_pend_a2));
  perform teste_assert_acesso(v_t = 'ok:1' and (select estado::text from pendencia where id = v_pend_a2) <> 'aberta', 'a função do portal (fn_decidir_pendencia) funciona para a Analista em A', v_t);
  v_t := teste_tenta_acesso(format($q$select fn_decidir_pendencia(%L, 'ana@0216', 'prosseguir', 'tentando B')$q$, v_pend_b));
  perform teste_super_acesso(u_socio);
  perform teste_assert_acesso((select estado::text from pendencia where id = v_pend_b) = 'aberta',
    'e a mesma função NÃO decide a pendência de B (a pendência continua aberta)', v_t);
  perform teste_como_acesso(u_ana);

  raise notice '--- 3. o que é reservado a Sócio, tentado pela Analista ---';
  perform teste_assert_acesso(teste_tenta_acesso(format($q$update caso set status = 'aprovado' where id = %L$q$, v_c)) = '42501', 'Analista não aprova (UPDATE direto de status)');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$select fn_aprovar_caso(%L, 'ana@0216')$q$, v_c)) in ('42501', 'ok:1')
    and (select status::text from caso where id = v_c) <> 'aprovado', 'fn_aprovar_caso não deixa o mandato aprovado por mão de Analista');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$select fn_fechar_caso(%L, 'ana@0216', 'x')$q$, v_c)) = '42501'
    and (select fechado_em from caso where id = v_c) is null, 'Analista não fecha o mandato (fn_fechar_caso)');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$update caso set fechado_em = now() where id = %L$q$, v_c)) = '42501', 'nem por UPDATE direto de fechado_em');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$select fn_excluir_caso(%L, 'ana@0216')$q$, v_c)) = '42501'
    and exists (select 1 from caso where id = v_c), 'Analista não exclui o mandato (fn_excluir_caso)');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$delete from caso where id = %L$q$, v_c)) = '42501', 'nem por DELETE direto');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$update caso set status = 'em_triagem' where id = %L$q$, v_a)) = 'ok:1',
    'mas as transições de trabalho (intake -> em_triagem) seguem livres para a Analista');
  select estagio, nivel_atual::text into v_estagio, v_nivel from estagio_autonomia limit 1;
  perform teste_assert_acesso(teste_tenta_acesso(format($q$select fn_mudar_dial(%L, %L::nivel_autonomia, 'ana@0216')$q$, v_estagio, v_nivel)) = '42501',
    'Analista não mexe no dial de autonomia (fn_mudar_dial)');
  perform teste_assert_acesso(teste_tenta_acesso($q$update estagio_autonomia set limiar_auto_clear = 0.1$q$) = '42501', 'nem por UPDATE direto em estagio_autonomia');
  perform teste_assert_acesso(teste_tenta_acesso(format('select fn_definir_papel(%L, ''socio'')', u_ana)) = '42501', 'Analista não se promove a Sócio (fn_definir_papel)');
  perform teste_assert_acesso(teste_tenta_acesso(format('select fn_alocar(%L, %L)', v_b, u_ana)) = '42501', 'Analista não se aloca em B (fn_alocar)');
  perform teste_assert_acesso(teste_tenta_acesso(format('select fn_desalocar(%L, %L)', v_a, u_leo)) = '42501', 'Analista não desaloca ninguém');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$insert into membro (usuario_id, papel) values (%L, 'socio')$q$, u_ana)) = '42501'
    and teste_tenta_acesso(format($q$update membro set papel = 'socio' where usuario_id = %L$q$, u_ana)) = '42501'
    and teste_tenta_acesso(format($q$insert into alocacao (caso_id, usuario_id) values (%L, %L)$q$, v_b, u_ana)) = '42501',
    'e não escreve em membro/alocacao direto: o authenticated só tem SELECT nelas');
  perform teste_assert_acesso((select count(*) from membro) = 1 and (select count(*) from alocacao) = 2,
    'cada um enxerga só a PRÓPRIA linha de membro e de alocacao (nada da equipe dos outros)');
  -- Restaura o que uma guarda desligada deixaria mudado (promoção, alocação em B, desalocação de Leitura): nada disto faz
  -- nada quando as guardas funcionam, e é o que deixa os asserts seguintes medirem em vez de herdar o estrago.
  perform teste_super_acesso(u_socio);
  update membro set papel = 'analista' where usuario_id = u_ana;
  delete from alocacao where caso_id = v_b and usuario_id = u_ana;
  insert into alocacao (caso_id, usuario_id) values (v_a, u_leo) on conflict do nothing;
  insert into estagio_autonomia (estagio, nivel_atual, teto) values ('teste_0216', 'N1', 'N2') on conflict do nothing;
  insert into premissa_catalogo (codigo, nome, natureza, formula, unidade) select 'teste_0216', 'teste', natureza, formula, unidade from premissa_catalogo limit 1 on conflict do nothing;
  perform teste_como_acesso(u_ana);
  perform teste_assert_acesso(teste_tenta_acesso($q$delete from estagio_autonomia where estagio = 'teste_0216'$q$) = '42501'
    and teste_tenta_acesso($q$delete from premissa_catalogo where codigo = 'teste_0216'$q$) = '42501',
    'Analista não APAGA estágio do dial nem premissa do catálogo (o gatilho dá o erro: a policy deixa achar a linha)');
  perform teste_super_acesso(u_socio);
  delete from estagio_autonomia where estagio = 'teste_0216';
  delete from premissa_catalogo where codigo = 'teste_0216';
  perform teste_como_acesso(u_ana);

  perform teste_assert_acesso(teste_tenta_acesso($q$update premissa_catalogo set ativo = ativo$q$) = '42501'
    and teste_tenta_acesso($q$insert into golden_rodada (nome) values ('x')$q$) = '42501', 'catálogo de premissas e rodada do golden set: só Sócio escreve');
  perform teste_assert_acesso((select count(*) from golden_rotulo) = 0 and (select count(*) from golden_documento) = 0,
    'os rótulos do golden set (documentos de qualquer mandato) não são da Analista');
  perform teste_assert_acesso((select count(*) from taxonomia_tipo_documento) > 0 and (select count(*) from instalacao_requisito) > 0
    and (select count(*) from estagio_autonomia) > 0, 'o catálogo e o dial (globais) a Analista lê');

  raise notice '--- 4. a trilha e o Storage, por mandato ---';
  perform teste_assert_acesso(teste_tenta_acesso(format($q$insert into evento_auditoria (ator, acao, entidade_ref) values ('ana@0216', 'nota', 'caso:%s')$q$, v_a)) = 'ok:1'
    and teste_tenta_acesso(format($q$insert into evento_auditoria (ator, acao, entidade_ref) values ('ana@0216', 'nota', 'caso:%s')$q$, v_b)) = '42501',
    'a Analista grava evento do mandato dela e não de B (a trilha não se forja em outro mandato)');
  perform teste_assert_acesso(teste_tenta_acesso($q$update evento_auditoria set acao = 'x'$q$) in ('42501', 'ok:0')
    and teste_tenta_acesso($q$delete from evento_auditoria$q$) in ('42501', 'ok:0'), 'evento_auditoria segue append-only');
  perform teste_assert_acesso((select count(*) from storage.objects where bucket_id = 'documentos' and name = v_a || '/hash-a-0216.pdf') = 1
    and (select count(*) from storage.objects where bucket_id = 'documentos' and name = v_b || '/hash-b-0216.pdf') = 0,
    'o original no Storage (chave <caso>/<hash>) só aparece para quem lê o mandato');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$insert into storage.objects (bucket_id, name) values ('documentos', '%s/novo.pdf')$q$, v_a)) = 'ok:1'
    and teste_tenta_acesso(format($q$insert into storage.objects (bucket_id, name) values ('documentos', '%s/novo.pdf')$q$, v_b)) = '42501',
    'e a Analista só sobe arquivo no mandato dela');
  perform teste_super_acesso(u_socio);


  -- ---------------------------------------------------------------- 4b. as RPCs de TRABALHO, uma a uma, por papel
  -- A 0216 declara ~20 RPCs "Analista alocado escreve" e a primeira versão deste teste só exercitava fn_decidir_pendencia. Cada uma
  -- roda aqui como Analista alocada (muda o mandato), como Leitura alocado (não muda nada) e como Analista alocado SÓ em B (não muda
  -- nada em A). "Muda" é a impressão digital do mandato (teste_fp_acesso), não o valor devolvido: várias funções recusam devolvendo
  -- jsonb em vez de erro, e a pergunta é se o mandato mudou.
  raise notice '--- 4b. as RPCs de trabalho: Analista alocada escreve; Leitura e Analista de outro mandato não ---';
  insert into entidade (caso_id, razao_social, cnpj) values (v_a, 'ALFA UM 0216', '11222333000181') returning id into v_e1;
  insert into entidade (caso_id, razao_social, cnpj) values (v_a, 'ALFA DOIS 0216', '45997418000153') returning id into v_e2;
  insert into entidade (caso_id, razao_social) values (v_a, 'ALFA TRES 0216') returning id into v_e3;
  v_ctl1 := fn_controlador_registrar(v_a, 'Pessoa Um 0216', null, 'fisica', 'setup@0216');
  v_ctl2 := fn_controlador_registrar(v_a, 'Pessoa Dois 0216', null, 'fisica', 'setup@0216');
  v_ctl3 := fn_controlador_registrar(v_a, 'Pessoa Tres 0216', null, 'fisica', 'setup@0216');
  v_vinc := fn_controlador_vincular_familia(v_a, v_ctl1, v_ctl2, 'irmao', 'declaração (teste 0216)', 'setup@0216');
  perform fn_perimetro_definir_escopo(v_a, v_e1, 'combinado', current_date - 30, 'setup@0216');
  perform fn_definir_modelagem(v_a, 'ALFA SA', 2025, 'IPCA', 'industria', 'setup@0216', 5);
  perform fn_ativar_premissa(v_a, 'CRESC_NOMINAL', '{"2026": 0.05, "2027": 0.05}'::jsonb, 'digitado', 'setup@0216');
  select c.id into v_campo from campo_extraido c where c.documento_versao_id = v_ver_a limit 1;
  v_hash := 'hash-0216-' || gen_random_uuid();
  update caso set trilha_transacional = true where id = v_a;      -- fn_resumo_iniciar recusa mandato sem a trilha de arquivos oficiais

  v_rotulos := array[
    'fn_aceitar_extracao', 'fn_revisar_documento', 'fn_registrar_transcricao_humana', 'fn_registrar_classe_override',
    'fn_registrar_pergunta_acao', 'fn_definir_modelagem', 'fn_ativar_premissa',
    'fn_vincular_linha_premissa', 'fn_aplicar_premissa_em_lote', 'fn_controlador_registrar', 'fn_controlador_vincular_familia',
    'fn_controlador_desvincular_familia', 'fn_entidade_definir_papel_no_grupo', 'fn_entidade_definir_participacao',
    'fn_entidade_definir_controlador', 'fn_entidade_definir_forma_de_controle', 'fn_perimetro_definir_escopo',
    'fn_perimetro_encerrar_escopo', 'fn_resumo_iniciar', 'fn_fundir_entidade', 'fn_desativar_premissa'];
  v_chamadas := array[
    format($q$select fn_aceitar_extracao(%L, 'ana@0216', 'aceita')$q$, v_ver_a),
    format($q$select fn_revisar_documento(%L, 'ana@0216', null, null, 'anual', '2024', 'período revisto')$q$, v_doc_a),
    format($q$select fn_registrar_transcricao_humana(%L, '[{"chave": "Caixa", "valor_num": "10"}]'::jsonb, 'ana@0216', 'digitado')$q$, v_doc_a),
    format($q$select fn_registrar_classe_override(%L, 'nao_recorrente', 'ana@0216', 'motivo')$q$, v_campo),
    format($q$select fn_registrar_pergunta_acao(%L, 'A4', 'enviada', 'pergunta nova de A', 'ana@0216')$q$, v_a),
    format($q$select fn_definir_modelagem(%L, 'ALFA SA', 2024, 'IPCA', 'comercio', 'ana@0216', 4)$q$, v_a),
    format($q$select fn_ativar_premissa(%L, 'SAZONALIDADE', '{"2026": 1}'::jsonb, 'digitado', 'ana@0216')$q$, v_a),
    format($q$select fn_vincular_linha_premissa(%L, null, 'X', null, 'CRESC_NOMINAL', 'ana@0216')$q$, v_a),
    format($q$select fn_aplicar_premissa_em_lote(%L, 'receita_bruta', 'CRESC_NOMINAL', 'ana@0216')$q$, v_a),
    format($q$select fn_controlador_registrar(%L, 'Pessoa Quatro 0216', null, 'fisica', 'ana@0216')$q$, v_a),
    format($q$select fn_controlador_vincular_familia(%L, %L, %L, 'irmao', 'fonte', 'ana@0216')$q$, v_a, v_ctl2, v_ctl3),
    format($q$select fn_controlador_desvincular_familia(%L, 'retificado', 'ana@0216')$q$, v_vinc),
    format($q$select fn_entidade_definir_papel_no_grupo(%L, 'operacional'::entidade_papel_no_grupo, 'ana@0216')$q$, v_e1),
    format($q$select fn_entidade_definir_participacao(%L, %L, 70, 'ana@0216')$q$, v_e2, v_e1),
    format($q$select fn_entidade_definir_controlador(%L, %L, 50, 'ana@0216')$q$, v_e1, v_ctl1),
    format($q$select fn_entidade_definir_forma_de_controle(%L, 'controlada_por_entidade', 'ana@0216')$q$, v_e2),
    format($q$select fn_perimetro_definir_escopo(%L, %L, 'combinado', current_date - 10, 'ana@0216')$q$, v_a, v_e2),
    format($q$select fn_perimetro_encerrar_escopo(%L, %L, 'combinado', current_date, 'ana@0216')$q$, v_a, v_e1),
    format($q$select fn_resumo_iniciar(%L, null, jsonb_build_object('familia','sped','subtipo','ECD','versao_leiaute','9.00','hash_sha256',%L,
      'cnpj','11222333000181','periodo_ini','2025-01-01','periodo_fim','2025-12-31','chave_natural','0216|'||%L,'retificadora',false,
      'controle_tipo','contagem_declarada','controle_declarado',1,'controle_lido',1,'status','lido','detalhe','{}'::jsonb,'leitor_versao','leitor-envelope/1'),
      jsonb_build_object('versao','resumo/1','hash_sha256',%L,'conferencia','{"i250_lidos":0,"valores_invalidos":0,"lancamentos_desbalanceados":0}'::jsonb,
        'descartado','x','total_registros',0,'total_grupos',0))$q$, v_a, v_hash, v_hash, v_hash),
    format($q$select fn_fundir_entidade(%L, %L, %L, 'ana@0216')$q$, v_a, v_e3, v_e2),
    format($q$select fn_desativar_premissa(%L, 'CRESC_NOMINAL', 'ana@0216')$q$, v_a)];

  -- 1) Leitura (alocado em A) e Xan (Analista alocado só em B): NADA muda em A, e não é por a função ter se recusado por outro motivo
  --    (o arranjo é o mesmo da Ana, que muda). Cada função tem de aparecer nas duas rodadas.
  for v_i in 1 .. array_length(v_chamadas, 1) loop
    v_res := teste_chamar_acesso(u_leo, v_chamadas[v_i], v_a, u_socio);
    perform teste_assert_acesso(v_res like '%|false', format('Leitura NÃO escreve pela RPC %s (o mandato fica como estava)', v_rotulos[v_i]), v_res);
    v_res := teste_chamar_acesso(u_xan, v_chamadas[v_i], v_a, u_socio);
    perform teste_assert_acesso(v_res like '%|false', format('Analista alocado só em B NÃO escreve em A pela RPC %s', v_rotulos[v_i]), v_res);
  end loop;
  -- 2) Ana (alocada em A): cada uma passa e muda o mandato (controle positivo das duas rodadas acima: o arranjo é válido).
  for v_i in 1 .. array_length(v_chamadas, 1) loop
    v_res := teste_chamar_acesso(u_ana, v_chamadas[v_i], v_a, u_socio);
    perform teste_assert_acesso(v_res like 'ok:%|true', format('Analista alocada ESCREVE em A pela RPC %s (controle positivo)', v_rotulos[v_i]), v_res);
  end loop;

  -- ---------------------------------------------------------------- 4c. a trilha não se forja
  raise notice '--- 4c. evento sem mandato (estagio:, membro:, golden_rodada:) só o Sócio grava; o que tem mandato, só quem escreve nele ---';
  select c.id into v_campo from campo_extraido c where c.documento_versao_id = v_ver_a limit 1;
  select c.id into v_campo_b from campo_extraido c where c.documento_versao_id = v_ver_b limit 1;
  perform teste_como_acesso(u_ana);
  perform teste_assert_acesso(
    teste_tenta_acesso($q$insert into evento_auditoria (ator, acao, entidade_ref) values ('ana@0216', 'mudanca_dial', 'estagio:extracao_linhas_financeiras')$q$) = '42501'
    and teste_tenta_acesso(format($q$insert into evento_auditoria (ator, acao, entidade_ref) values ('ana@0216', 'papel_definido', 'membro:%s')$q$, u_ana)) = '42501'
    and teste_tenta_acesso($q$insert into evento_auditoria (ator, acao, entidade_ref) values ('ana@0216', 'rodada', 'golden_rodada:1')$q$) = '42501'
    and teste_tenta_acesso(format($q$insert into evento_auditoria (ator, acao, entidade_ref) values ('ana@0216', 'x', 'entidade:%s')$q$, gen_random_uuid())) = '42501',
    'a Analista não forja na trilha o que não tem mandato (mudanca_dial, papel_definido, rodada do golden set, entidade inexistente)');
  perform teste_assert_acesso(
    teste_tenta_acesso(format($q$insert into evento_auditoria (ator, acao, entidade_ref) values ('ana@0216', 'classe', 'campo_extraido:%s')$q$, v_campo)) = 'ok:1'
    and teste_tenta_acesso(format($q$insert into evento_auditoria (ator, acao, entidade_ref) values ('ana@0216', 'classe', 'campo_extraido:%s')$q$, v_campo_b)) = '42501',
    'mas grava o evento de campo extraído do mandato dela (é o que fn_registrar_classe_override faz) e não o do campo de B');
  perform teste_super_acesso(u_socio);
  perform teste_como_acesso(u_socio);
  perform teste_assert_acesso(teste_tenta_acesso($q$insert into evento_auditoria (ator, acao, entidade_ref) values ('socio@0216', 'nota', 'estagio:extracao_linhas_financeiras')$q$) = 'ok:1',
    'o Sócio grava evento sem mandato (controle positivo)');
  perform teste_super_acesso(u_socio);

  -- ---------------------------------------------------------------- 5. Leitura
  raise notice '--- 5. Leitura alocado em A: lê, não escreve ---';
  perform teste_como_acesso(u_leo);
  perform teste_assert_acesso((select count(*) from documento where caso_id = v_a) = 1
    and (select count(*) from campo_extraido where documento_versao_id = v_ver_a) >= 1
    and (select count(*) from pendencia where caso_id = v_a) >= 1, 'Leitura LÊ documento, campo extraído e pendência de A');
  perform teste_assert_acesso((select count(*) from documento where caso_id = v_b) = 0
    and (select count(*) from campo_extraido where documento_versao_id = v_ver_b) = 0
    and (select count(*) from caso where id = v_b) = 0, 'Leitura NÃO lê nada de B');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$insert into pendencia (caso_id, origem_estagio, tipo, severidade, descricao)
      values (%L, 'completude', 'item_sem_conteudo', 'bloqueante', 'Leitura escrevendo')$q$, v_a)) = '42501', 'Leitura não INSERE em A (42501)');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$update pendencia set descricao = 'Leitura editou' where id = %L$q$, v_pend_a)) = '42501',
    'Leitura não ATUALIZA em A (42501, erro e não "0 linhas" calado)');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$delete from pendencia where id = %L$q$, v_pend_a)) = '42501'
    and teste_tenta_acesso(format($q$delete from campo_extraido where documento_versao_id = %L$q$, v_ver_a)) = '42501'
    and exists (select 1 from pendencia where id = v_pend_a), 'Leitura não APAGA em A: 42501 (e não "0 linhas" calado), e nenhuma linha some');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$insert into campo_extraido (documento_versao_id, chave, valor_num) values (%L, 'Y', 1)$q$, v_ver_a)) = '42501',
    'Leitura não escreve campo extraído');
  -- pendência NOVA: as RPCs da seção 4b (fn_aceitar_extracao...) já resolvem as de A, e a pergunta aqui é só se a Leitura decide uma ABERTA
  perform teste_super_acesso(u_socio);
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id)
    values (v_a, 'completude', 'item_sem_conteudo', 'bloqueante', true, 'aberta para a Leitura tentar decidir', v_doc_a) returning id into v_pend_a2;
  perform teste_como_acesso(u_leo);
  v_t := teste_tenta_acesso(format($q$select fn_decidir_pendencia(%L, 'leo@0216', 'prosseguir', 'Leitura decidindo')$q$, v_pend_a2));
  perform teste_super_acesso(u_socio);
  perform teste_assert_acesso((select estado::text from pendencia where id = v_pend_a2) = 'aberta', 'fn_decidir_pendencia NÃO decide por Leitura (a pendência segue aberta)', v_t);
  perform teste_como_acesso(u_leo);
  perform teste_assert_acesso(teste_tenta_acesso($q$select fn_upsert_caso('0216 — Leitura criando', 'portal:navegador')$q$) = '42501'
    and teste_tenta_acesso($q$insert into caso (nome) values ('0216 — Leitura criando direto')$q$) = '42501', 'Leitura não cria mandato (nem pela função, nem por INSERT direto)');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$insert into evento_auditoria (ator, acao, entidade_ref) values ('leo', 'nota', 'caso:%s')$q$, v_a)) = '42501',
    'Leitura não grava na trilha do mandato');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$select fn_fechar_caso(%L, 'leo@0216')$q$, v_d)) = '42501'
    and teste_tenta_acesso(format($q$select fn_excluir_caso(%L, 'leo@0216')$q$, v_d)) = '42501'
    and exists (select 1 from caso where id = v_d and fechado_em is null), 'Leitura não fecha nem exclui');
  perform teste_super_acesso(u_socio);

  -- ---------------------------------------------------------------- 6. Sócio
  raise notice '--- 6. Sócio: tudo, em todos os mandatos ---';
  perform teste_como_acesso(u_socio);
  perform teste_assert_acesso((select count(*) from caso where id in (v_a, v_b)) = 2
    and (select count(*) from documento where caso_id in (v_a, v_b)) = 2
    and (select count(*) from campo_extraido where documento_versao_id in (v_ver_a, v_ver_b)) >= 2
    and (select count(*) from evento_auditoria where entidade_ref in ('caso:' || v_a, 'caso:' || v_b)) >= 2,
    'Sócio LÊ os dois mandatos (caso, documento, campo extraído, trilha)');
  perform teste_assert_acesso((select count(*) from membro) >= 5 and (select count(*) from alocacao) >= 3, 'Sócio lê a equipe inteira (membro e alocacao)');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$update pendencia set descricao = 'sócio editou' where id = %L$q$, v_pend_b)) = 'ok:1'
    and teste_tenta_acesso(format($q$insert into pendencia (caso_id, origem_estagio, tipo, severidade, descricao)
      values (%L, 'completude', 'item_sem_conteudo', 'bloqueante', 'sócio em B')$q$, v_b)) = 'ok:1', 'Sócio ESCREVE em B, onde ninguém o alocou');
  -- (cada passo é um comando próprio: a subconsulta do MESMO comando não enxerga o que a função chamada acabou de gravar)
  v_t := teste_tenta_acesso(format($q$select fn_fechar_caso(%L, 'socio@0216', 'teste')$q$, v_b));
  perform teste_assert_acesso(v_t = 'ok:1' and (select fechado_em from caso where id = v_b) is not null, 'Sócio fecha o mandato');
  v_t := teste_tenta_acesso(format($q$select fn_reabrir_caso(%L, 'socio@0216')$q$, v_b));
  perform teste_assert_acesso(v_t = 'ok:1' and (select fechado_em from caso where id = v_b) is null, 'e o reabre');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$update caso set status = 'aprovado' where id = %L$q$, v_b)) = 'ok:1', 'Sócio aprova (a transição que a Analista não faz)');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$select fn_mudar_dial(%L, %L::nivel_autonomia, 'socio@0216')$q$, v_estagio, v_nivel)) = 'ok:1',
    'Sócio mexe no dial');
  v_novo := fn_upsert_caso('0216 — mandato do Sócio');
  v_t := teste_tenta_acesso(format($q$select fn_excluir_caso(%L, 'socio@0216')$q$, v_novo));
  perform teste_assert_acesso(v_t = 'ok:1' and not exists (select 1 from caso where id = v_novo), 'Sócio exclui mandato');
  perform teste_super_acesso(u_socio);

  -- ---------------------------------------------------------------- 7. sem papel
  raise notice '--- 7. usuário SEM papel: nada ---';
  perform teste_como_acesso(u_nil);
  perform teste_assert_acesso(fn_meu_papel() is null and not fn_tem_papel(), 'sem papel: fn_meu_papel é nulo');
  foreach v_tab in array array['caso', 'documento', 'documento_versao', 'campo_extraido', 'pendencia', 'evento_auditoria', 'caso_pergunta',
                               'taxonomia_tipo_documento', 'instalacao_requisito', 'estagio_autonomia', 'premissa_catalogo', 'indice_macro_serie', 'membro', 'alocacao'] loop
    execute format('select count(*) from %I', v_tab) into v_n;
    perform teste_assert_acesso(v_n = 0, format('usuário sem papel não lê %s', v_tab), v_n::text);
  end loop;
  perform teste_assert_acesso((select count(*) from storage.objects where bucket_id = 'documentos') = 0, 'usuário sem papel não lê o Storage');
  perform teste_assert_acesso(teste_tenta_acesso($q$select fn_upsert_caso('0216 — sem papel criando', 'portal:navegador')$q$) = '42501'
    and teste_tenta_acesso($q$insert into caso (nome) values ('0216 — sem papel criando direto')$q$) = '42501', 'usuário sem papel não cria mandato (nem pela função, nem por INSERT direto)');
  perform teste_assert_acesso(teste_tenta_acesso(format('select fn_definir_papel(%L, ''socio'')', u_nil)) = '42501', 'usuário sem papel não se promove');
  perform teste_super_acesso(u_socio);
  perform teste_como_acesso(null);
  perform teste_assert_acesso((select count(*) from caso) = 0 and fn_meu_papel() is null
    and teste_tenta_acesso('select fn_exige_socio(''x'')') = '42501',
    'authenticated com JWT sem sub (ou sem JWT) também não é conexão de serviço: não lê e não passa na guarda de Sócio');
  perform teste_super_acesso(u_socio);

  -- ---------------------------------------------------------------- 8. o Analista que cria o mandato
  raise notice '--- 8. o Analista que cria um mandato fica alocado nele ---';
  perform teste_como_acesso(u_ana);
  v_t := teste_tenta_acesso($q$select fn_upsert_caso('0216 — criado pela Analista', 'portal:navegador')$q$);
  select id into v_novo from caso where nome = '0216 — criado pela Analista';
  perform teste_assert_acesso(v_t = 'ok:1' and v_novo is not null, 'a Analista cria o mandato e o enxerga logo (RETURNING e a leitura seguinte)', v_t);
  perform teste_assert_acesso(exists (select 1 from alocacao where caso_id = v_novo and usuario_id = u_ana), 'e ficou alocada nele');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$insert into pendencia (caso_id, origem_estagio, tipo, severidade, descricao)
      values (%L, 'completude', 'item_sem_conteudo', 'bloqueante', 'no que ela criou')$q$, v_novo)) = 'ok:1', 'e escreve nele');
  perform teste_super_acesso(u_socio);
  perform teste_como_acesso(u_xan);
  perform teste_assert_acesso(not exists (select 1 from caso where id = v_novo), 'a outra Analista (alocada só em B) não vê o mandato que a Ana criou');
  perform teste_super_acesso(u_socio);

  raise notice '--- 8c. o id e o nome de um mandato alheio não se conquistam ---';
  -- (a) ON CONFLICT DO NOTHING: o gatilho BEFORE alocava antes de o conflito ser conhecido.
  perform teste_como_acesso(u_xan);
  perform teste_assert_acesso(teste_tenta_acesso(format($q$insert into caso (id, nome) values (%L, 'forjado 0216') on conflict do nothing$q$, v_a)) = 'ok:0',
    'INSERT de caso com id alheio e ON CONFLICT DO NOTHING não cria linha');
  perform teste_assert_acesso(teste_tenta_acesso($q$insert into caso (nome) values ('0216 — MANDATO a ') on conflict do nothing$q$) = 'ok:0',
    'nem com o nome de um mandato alheio (ignorando caixa e espaço)');
  perform teste_super_acesso(u_socio);
  perform teste_assert_acesso(not exists (select 1 from alocacao where caso_id = v_a and usuario_id = u_xan),
    'e o Analista NÃO ficou alocado no mandato alheio (o gatilho não aloca linha que o conflito descarta)');
  perform teste_como_acesso(u_xan);
  perform teste_assert_acesso(not exists (select 1 from caso where id = v_a) and (select count(*) from documento where caso_id = v_a) = 0,
    'e continua sem ver o mandato nem os documentos dele');
  -- (b) o homônimo
  v_t := teste_tenta_acesso($q$select fn_upsert_caso('0216 — mandato A', 'portal:navegador')$q$);
  perform teste_assert_acesso(v_t = '42501', 'fn_upsert_caso de nome que é de mandato que o Analista não lê é recusada (42501), e não cria o homônimo', v_t);
  v_t := null;
  begin
    perform fn_upsert_caso('  0216 — MANDATO A  ', 'portal:navegador');
  exception when others then v_t := sqlstate || ' ' || sqlerrm;
  end;
  perform teste_assert_acesso(v_t like '42501 Já existe um mandato com este nome ao qual você não tem acesso%',
    'a recusa vale também para o nome em outra caixa/com espaços, e a mensagem diz o que houve e o que fazer', v_t);
  perform teste_assert_acesso(teste_tenta_acesso(format($q$update caso set nome = '0216 — mandato A' where id = %L$q$, v_b)) = '23505',
    'o Analista não renomeia o próprio mandato para o nome de outro (capturaria os uploads dele)');
  perform teste_super_acesso(u_socio);
  perform teste_assert_acesso((select count(*) from caso where lower(btrim(nome)) = lower('0216 — mandato A')) = 1
    and (select nome from caso where id = v_b) = '0216 — mandato B',
    'resultado: continua UM mandato "0216 — mandato A", e o B não foi renomeado');
  perform teste_assert_acesso(teste_tenta_acesso($q$insert into caso (nome) values (' 0216 — MANDATO A')$q$) = '23505',
    'o banco garante a unicidade do nome (sem caixa e sem espaço nas pontas), também para o Sócio e o SQL Editor');
  v_novo := null;
  begin v_novo := fn_upsert_caso('0216 — MANDATO A ', 'sistema:n8n'); exception when others then null; end;
  perform teste_assert_acesso(v_novo = v_a,
    'o n8n (conexão de serviço) que manda o nome em outra caixa cai no MESMO mandato, e não em um homônimo');
  perform teste_como_acesso(u_leo);
  perform teste_assert_acesso(fn_upsert_caso('0216 — mandato A', 'portal:navegador') = v_a, 'quem lê o mandato continua o achando pelo nome');
  perform teste_super_acesso(u_socio);

  raise notice '--- 8d. falha do pipeline sem caso_id (morreu antes de resolver o caso) é lida pelo NOME do mandato ---';
  insert into execucao_falha (caso_id, caso_nome, etapa, mensagem) values (null, '0216 — MANDATO A', '0216', 'falha órfã do mandato A') returning id into v_falha_a;
  insert into execucao_falha (caso_id, caso_nome, etapa, mensagem) values (null, '0216 — mandato B', '0216', 'falha órfã do mandato B') returning id into v_falha_b;
  insert into execucao_falha (caso_id, caso_nome, etapa, mensagem) values (null, 'mandato que não existe 0216', '0216', 'falha de nome sem mandato') returning id into v_falha_n;
  insert into execucao_falha (caso_id, caso_nome, etapa, mensagem) values (null, null, '0216', 'falha sem caso nem nome') returning id into v_falha_x;
  perform teste_como_acesso(u_ana);
  perform teste_assert_acesso((select count(*) from execucao_falha where etapa = '0216') = 1
    and exists (select 1 from execucao_falha where id = v_falha_a),
    'a Analista alocada em A vê a falha órfã de A (e só ela: não a de B, não a de nome sem mandato, não a sem nome)',
    (select count(*) from execucao_falha where etapa = '0216')::text);
  perform teste_assert_acesso((select count(*) from fn_falhas_abertas('0216 — mandato A', now() - interval '1 day')) = 1,
    'fn_falhas_abertas (o que o sino consulta) devolve a falha órfã à Analista, em vez de ficar em "aguarde"');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$update execucao_falha set visto_em = now(), visto_por = 'ana@0216' where id = %L$q$, v_falha_a)) = 'ok:1',
    'e ela a marca como vista (fn_marcar_falha_vista)');
  perform teste_super_acesso(u_socio);
  update execucao_falha set visto_em = null, visto_por = null where id = v_falha_a;
  perform teste_como_acesso(u_leo);
  perform teste_assert_acesso((select count(*) from execucao_falha where etapa = '0216') = 1
    and (select count(*) from fn_falhas_abertas('0216 — mandato A', now() - interval '1 day')) = 1,
    'a Leitura alocada em A também a vê');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$update execucao_falha set visto_em = now() where id = %L$q$, v_falha_a)) = '42501',
    'mas não a marca como vista (42501)');
  perform teste_super_acesso(u_socio);
  perform teste_como_acesso(u_xan);
  perform teste_assert_acesso((select count(*) from execucao_falha where etapa = '0216') = 1
    and exists (select 1 from execucao_falha where id = v_falha_b),
    'a Analista de B vê a falha órfã de B e não a de A');
  perform teste_super_acesso(u_socio);
  perform teste_como_acesso(u_nil);
  perform teste_assert_acesso((select count(*) from execucao_falha) = 0, 'quem não tem papel não vê falha nenhuma');
  perform teste_super_acesso(u_socio);
  perform teste_como_acesso(u_socio);
  perform teste_assert_acesso((select count(*) from execucao_falha where etapa = '0216') = 4,
    'o Sócio vê as quatro, inclusive a que não tem caso_id nem nome (decisão: só o Sócio — a mensagem pode trazer trecho de documento de mandato alheio, e o sino só consulta por nome)');
  perform teste_super_acesso(u_socio);
  delete from execucao_falha where etapa = '0216';

  raise notice '--- 8e. a tela da equipe: fn_membros_da_equipe é do Sócio ---';
  select count(*) into v_n2 from auth.users;          -- como superusuário: o authenticated não lê auth.users
  perform teste_como_acesso(u_socio);
  select count(*) into v_n from fn_membros_da_equipe();
  perform teste_assert_acesso(v_n = v_n2 and v_n >= 6
    and not exists (select 1 from fn_membros_da_equipe() where email is null)
    and (select papel from fn_membros_da_equipe() where usuario_id = u_nil) is null
    and exists (select 1 from fn_membros_da_equipe() where usuario_id = u_nil)
    and (select papel from fn_membros_da_equipe() where usuario_id = u_xan) = 'analista'
    and (select v_b = any (alocacoes) from fn_membros_da_equipe() where usuario_id = u_xan),
    'o Sócio vê TODOS os usuários do Auth com e-mail, inclusive o sem papel (papel nulo), e as alocações de cada um', v_n::text);
  perform teste_super_acesso(u_socio);
  foreach v_uid in array array[u_ana, u_leo, u_nil, u_xan] loop
    perform teste_como_acesso(v_uid);
    perform teste_assert_acesso(teste_tenta_acesso('select * from fn_membros_da_equipe()') = '42501',
      'Analista, Leitura e sem papel recebem 42501 em fn_membros_da_equipe', v_uid::text);
  end loop;
  perform teste_super_acesso(u_socio);

  raise notice '--- 8b. a forma por linha e a forma por conjunto são a mesma regra ---';
  -- A forma por LINHA (fn_pode_*) e a forma por CONJUNTO (fn_casos_*) são a mesma regra escrita duas vezes: têm de concordar, para
  -- cada usuário e cada mandato. Ana (analista alocada em A e C), Leo (leitura em A e D), Xan (analista em B), sem papel e Sócio.
  v_n := 0; v_n2 := 0;
  foreach v_uid in array array[u_socio, u_ana, u_leo, u_nil, u_xan] loop
    perform set_config('request.jwt.claims', jsonb_build_object('sub', v_uid)::text, true);
    select count(*) into v_dif from caso c
     where fn_pode_ler_caso(c.id) is distinct from (c.id in (select x from fn_casos_legiveis() x))
        or fn_pode_escrever_caso(c.id) is distinct from (c.id in (select x from fn_casos_escreviveis() x));
    v_n := v_n + v_dif;
    select count(*) into v_dif from caso c where fn_pode_ler_caso(c.id);
    v_n2 := v_n2 + v_dif;
  end loop;
  perform teste_assert_acesso(v_n = 0, 'fn_pode_ler/escrever_caso (por linha) e fn_casos_legiveis/escreviveis (por conjunto) concordam para todo usuário e mandato', v_n::text);
  perform teste_assert_acesso(v_n2 > 0, 'e a comparação não é vazia: há mandato legível pelos usuários de teste', v_n2::text);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', u_socio, 'role', 'authenticated')::text, true);

  -- ---------------------------------------------------------------- 9. mudar a equipe muda o acesso, no ato
  raise notice '--- 9. alocar, desalocar, rebaixar e retirar mudam o que a pessoa enxerga ---';
  perform fn_desalocar(v_a, u_ana);
  perform teste_como_acesso(u_ana);
  perform teste_assert_acesso(not exists (select 1 from caso where id = v_a) and (select count(*) from campo_extraido where documento_versao_id = v_ver_a) = 0,
    'desalocada de A, a Analista deixa de ver o mandato e os números');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$update pendencia set descricao = 'x' where id = %L$q$, v_pend_a)) = 'ok:0', 'e deixa de escrever nele');
  perform teste_super_acesso(u_socio);
  perform teste_assert_acesso((select count(*) from evento_auditoria where acao = 'desalocado' and entidade_ref = 'caso:' || v_a) = 1, 'a desalocação gravou evento_auditoria');
  perform fn_alocar(v_a, u_ana);
  perform fn_definir_papel(u_ana, 'leitura');
  perform teste_como_acesso(u_ana);
  perform teste_assert_acesso(exists (select 1 from caso where id = v_a)
    and teste_tenta_acesso(format($q$update pendencia set descricao = 'x' where id = %L$q$, v_pend_a)) = '42501', 'rebaixada a Leitura, a Analista ainda lê A e já não escreve');
  perform teste_super_acesso(u_socio);
  perform fn_definir_papel(u_ana, null);
  perform teste_como_acesso(u_ana);
  perform teste_assert_acesso(not exists (select 1 from caso) and fn_meu_papel() is null, 'sem papel (acesso retirado), não vê mais nenhum mandato, ainda que a alocação continue gravada');
  perform teste_super_acesso(u_socio);
  perform teste_assert_acesso((select count(*) from evento_auditoria where acao = 'papel_removido' and entidade_ref = 'membro:' || u_ana) = 1, 'retirar o papel gravou evento_auditoria');

  -- ---------------------------------------------------------------- 10. conexão de serviço
  raise notice '--- 10. a conexão de serviço (n8n, SQL Editor) passa pela guarda; o navegador não ---';
  perform set_config('request.jwt.claims', '', true);
  perform teste_assert_acesso(fn_conexao_de_servico() and teste_tenta_acesso(format($q$update caso set fechado_em = now(), fechado_por = 'n8n' where id = %L$q$, v_a)) = 'ok:1',
    'sem JWT e sem set role (n8n, SQL Editor): fechar mandato passa — o pipeline não para na guarda');
  execute 'set local role service_role';
  perform teste_assert_acesso(fn_conexao_de_servico(), 'service_role sem JWT também é conexão de serviço');
  reset role;
  execute 'set local role authenticated';
  perform teste_assert_acesso(not fn_conexao_de_servico(), 'authenticated sem JWT NÃO é conexão de serviço');
  reset role;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', u_socio, 'role', 'authenticated')::text, true);

  raise notice '--- 10b. reaplicar a migration não promove a Sócio quem a equipe deixou sem papel ---';
  select count(*) into v_n from membro;  v_dif := v_n;
  v_n2 := fn_acesso_bootstrap();
  perform teste_assert_acesso(v_n2 = 0 and not exists (select 1 from membro where usuario_id = u_nil)
    and (select count(*) from membro) = v_n,
    'o bootstrap com `membro` já povoada promove ninguém: u_nil segue sem papel', v_n2::text);
  -- controle positivo: com `membro` VAZIA ele promove todo usuário (sem o replica role o gatilho do último Sócio recusaria esvaziar).
  -- O bloco interno é desfeito por exceção: nada do que ele muda sobrevive.
  v_n2 := -1;
  begin
    set local session_replication_role = replica;
    delete from membro;
    v_n2 := fn_acesso_bootstrap();
    select count(*) into v_n from membro where papel = 'socio';
    raise exception 'desfaz' using errcode = 'P0042';
  exception when sqlstate 'P0042' then null;
  end;
  perform teste_assert_acesso(v_n2 > 0 and v_n = v_n2 and v_n >= 6,
    'e com `membro` vazia ele promove todos os usuários de auth.users (o bootstrap que a primeira aplicação precisa)', v_n2::text || '/' || v_n::text);
  perform teste_assert_acesso((select count(*) from membro) = v_dif and not exists (select 1 from membro where usuario_id = u_nil),
    'e o bloco de controle foi desfeito (o estado da equipe voltou)');

  -- ---------------------------------------------------------------- 11. o último Sócio
  raise notice '--- 11. nunca ficar sem Sócio ---';
  delete from membro where papel = 'socio' and usuario_id <> u_socio;       -- sobra só o b001 (dois ou mais: o gatilho deixa)
  perform teste_assert_acesso((select count(*) from membro where papel = 'socio') = 1, 'montagem: há um único Sócio');
  -- (a restauração entre as tentativas só faz algo quando o gatilho está desligado: aí o estrago de uma não esconde a seguinte)
  perform teste_assert_acesso(teste_tenta_acesso(format('select fn_definir_papel(%L, ''analista'')', u_socio)) = 'P0001', 'não rebaixa o último Sócio (fn_definir_papel)');
  insert into membro (usuario_id, papel) values (u_socio, 'socio') on conflict (usuario_id) do update set papel = 'socio';
  perform teste_assert_acesso(teste_tenta_acesso(format('select fn_definir_papel(%L, null)', u_socio)) = 'P0001', 'não retira o último Sócio (fn_definir_papel NULL)');
  insert into membro (usuario_id, papel) values (u_socio, 'socio') on conflict (usuario_id) do update set papel = 'socio';
  perform teste_assert_acesso(teste_tenta_acesso(format('delete from membro where usuario_id = %L', u_socio)) = 'P0001', 'nem por DELETE direto em membro');
  insert into membro (usuario_id, papel) values (u_socio, 'socio') on conflict (usuario_id) do update set papel = 'socio';
  perform teste_assert_acesso(teste_tenta_acesso(format('update membro set papel = ''leitura'' where usuario_id = %L', u_socio)) = 'P0001', 'nem por UPDATE direto');
  update membro set papel = 'socio' where usuario_id = u_socio;
  perform teste_assert_acesso(teste_tenta_acesso(format('delete from auth.users where id = %L', u_socio)) = 'P0001', 'nem apagando o usuário no Auth (a cascata passa pelo gatilho)');
  insert into auth.users (id, email) values (u_socio, 'socio@0216.local') on conflict (id) do nothing;
  insert into membro (usuario_id, papel) values (u_socio, 'socio') on conflict (usuario_id) do update set papel = 'socio';
  perform fn_definir_papel(u_ana, 'socio');
  perform teste_assert_acesso(teste_tenta_acesso(format('select fn_definir_papel(%L, ''analista'')', u_socio)) = 'ok:1',
    'com um segundo Sócio, rebaixar o primeiro é permitido (a regra é "nunca zero", não "nunca rebaixar")');
  update membro set papel = 'socio' where usuario_id = u_socio;      -- (ele mesmo se rebaixou acima: volta por SQL, como superusuário)
  delete from membro where usuario_id = u_ana;

  -- ---------------------------------------------------------------- 12. a forma do conjunto
  raise notice '--- 12. a forma: nenhuma policy `using (true)` de authenticated, e toda tabela com caso_id depende de fn_pode_* ---';
  select count(*) into v_n from pg_policies
   where 'authenticated' = any (roles) and (schemaname = 'public' or tablename = 'objects')
     and (qual = 'true' or with_check = 'true');
  perform teste_assert_acesso(v_n = 0, 'nenhuma policy de authenticated é `true` (public e storage.objects)', v_n::text);
  select count(*), string_agg(c.relname, ', ') into v_n, v_t
    from pg_class c join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
   where c.relkind = 'r' and c.relrowsecurity
     and not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname
                       and p.cmd in ('SELECT', 'ALL') and 'authenticated' = any (p.roles));
  perform teste_assert_acesso(v_n = 0, 'toda tabela com RLS tem policy de leitura para authenticated (RLS sem policy devolve zero calado)', v_t);
  select count(*), string_agg(distinct a.attrelid::regclass::text, ', ') into v_n, v_t
    from pg_attribute a join pg_class c on c.oid = a.attrelid and c.relkind = 'r' and c.relrowsecurity
    join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
   where a.attname = 'caso_id' and not a.attisdropped and c.relname <> 'alocacao'
     and not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname
                       and p.cmd = 'SELECT' and (p.qual like '%fn_casos_legiveis%' or p.qual like '%fn_pode_ler_caso%'));
  perform teste_assert_acesso(v_n = 0, 'toda tabela com coluna caso_id lê pelos conjuntos de acesso (tabela nova com caso_id e policy frouxa reprova aqui)', v_t);
  select count(*) into v_n from pg_class c join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
   where c.relkind = 'r' and not c.relrowsecurity;
  perform teste_assert_acesso(v_n = 0, 'toda tabela de public tem RLS ligada (golden_criterio estava sem)', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0216' and not presente;
  perform teste_assert_acesso(v_n = 0, 'a sonda enxerga tudo o que a 0216 instala', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0216';
  perform teste_assert_acesso(v_n >= 20, 'e o catálogo da 0216 não está vazio', v_n::text);

  -- DEVOLVE O ESTADO: o Sócio padrão do run.sh (a001) foi removido na seção 11 para sobrar um só, e os testes seguintes
  -- rodam como ele. Os usuários e mandatos de teste saem (a cascata de auth.users leva membro e alocacao).
  insert into membro (usuario_id, papel) values ('00000000-0000-0000-0000-00000000a001', 'socio') on conflict (usuario_id) do update set papel = 'socio';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  delete from caso where nome like '0216 —%';
  delete from auth.users where id in (u_socio, u_ana, u_leo, u_nil, u_xan);
  delete from storage.objects where name like '%-0216.pdf' or name like '%/novo.pdf';

  raise notice 'EXECUCOES=% FALHAS=%', current_setting('acesso.execucoes', true), coalesce(current_setting('acesso.falhas', true), '0');
  if current_setting('acesso.medindo', true) is distinct from 'on' then
    raise notice 'TODOS OS TESTES DO ACESSO POR MANDATO PASSARAM';
  end if;
end $$;
