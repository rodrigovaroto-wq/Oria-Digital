-- =============================================================================
-- 0216 — O ACESSO POR MANDATO NO BANCO: Sócio · Analista · Leitura, alocação por caso, RLS por caso
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md): 99 chamadas de assert, 124 execuções — o número por guarda desligada está no cabeçalho de
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
--   8. NENHUMA policy de authenticated sobrou como `using (true)`, e toda tabela com caso_id depende de fn_pode_*.
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
  perform teste_assert_acesso(teste_tenta_acesso(format($q$delete from pendencia where id = %L$q$, v_pend_a)) = 'ok:0'
    and exists (select 1 from pendencia where id = v_pend_a), 'Leitura não APAGA em A (nenhuma linha some)');
  perform teste_assert_acesso(teste_tenta_acesso(format($q$insert into campo_extraido (documento_versao_id, chave, valor_num) values (%L, 'Y', 1)$q$, v_ver_a)) = '42501',
    'Leitura não escreve campo extraído');
  v_t := teste_tenta_acesso(format($q$select fn_decidir_pendencia(%L, 'leo@0216', 'prosseguir', 'Leitura decidindo')$q$, v_pend_a));
  perform teste_super_acesso(u_socio);
  perform teste_assert_acesso((select estado::text from pendencia where id = v_pend_a) = 'aberta', 'fn_decidir_pendencia NÃO decide por Leitura (a pendência segue aberta)', v_t);
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
