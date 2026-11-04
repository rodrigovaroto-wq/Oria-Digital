-- Teste da 0222 — o token de envio v2 (carrega o CASO) e o mandato que o envio deixou de criar.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md): 65 asserts (medidos; eram 64 na 0222, a 0223 acrescentou 1 da sonda) — ver o cabeçalho de
-- Supabase/migrations/0222_o_envio_que_criava_o_mandato_novo_quando_o_nome_mudava.sql ("MEDIÇÃO NÃO-VAZIA") para o número que reprova
-- com cada correção desligada.
--
-- O QUE SE AFIRMA (comportamento, não mecanismo): um token v2 que o PORTAL assina é aceito e devolve o caso; renomear o mandato depois
-- de emitido o token NÃO muda o caso nem cria outro (e o nome antigo fica auditado); sem acesso, fechado e inexistente são recusas com
-- o caso preso; a assinatura vem antes de qualquer consulta a caso; o v1 é recusado como versao_antiga (0223).
--
-- OS VETORES NÃO SÃO FIXTURE INVENTADA PARA UM BUG DE PRODUÇÃO: foram calculados em 04/11/2026 FORA do SQL (`node` com
-- crypto.createHmac, a mesma mensagem `v2|<caso>|<exp>|<usuario>` da lib) e colados aqui. O banco não os recalcula. Um deles é o vetor
-- da própria lib (N8N/lib/assinatura-do-envio.mjs, segredo s3gredo-de-teste-do-n8n) para provar paridade entre lib e banco. O
-- defeito do rename É reproduzível no banco (rename + fn_upsert_caso), então o CONTROLE o reproduz de verdade.
--
-- Roda dentro de uma transação desfeita.

begin;

create or replace function teste_assert_envio(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('envio.execucoes', (coalesce(nullif(current_setting('envio.execucoes', true), ''), '0')::int + 1)::text, false);
  if p_cond is true then
    raise notice 'ok    %', p_nome;
  elsif current_setting('envio.medindo', true) = 'on' then
    perform set_config('envio.falhas', (coalesce(nullif(current_setting('envio.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

create or replace function teste_motivo(p_token text, p_mandato text default 'x', p_agora timestamptz default '2026-11-04 12:00:00+00')
returns text language sql as $$
  select case when envio_autorizado then 'ok' else coalesce(motivo_recusa, '?') end
    from fn_conferir_envio(p_token, p_mandato, p_agora) $$;

do $teste$
declare
  c_seg constant text := 'segredo-de-paridade-ç-Ω';
  u_socio constant uuid := 'a0000000-0000-4000-8000-000000000001';
  u_ana   constant uuid := 'a0000000-0000-4000-8000-000000000002';
  u_lei   constant uuid := 'a0000000-0000-4000-8000-000000000003';
  k_a constant uuid := 'c0000000-0000-4000-8000-00000000000a';   -- "Alfa": ana alocada
  k_b constant uuid := 'c0000000-0000-4000-8000-00000000000b';   -- "Beta": ana NÃO alocada
  k_f constant uuid := 'c0000000-0000-4000-8000-00000000000f';   -- "Fechado": fechado
  k_d constant uuid := 'c0000000-0000-4000-8000-00000000000d';   -- nunca existiu
  k_x constant uuid := 'c0000000-0000-4000-8000-000000000099';   -- criado e apagado no teste / nunca existiu
  t_exp_x constant text := 'v2.1800000000.a0000000-0000-4000-8000-000000000001.c0000000-0000-4000-8000-000000000099.42ede57d2d0dcba7dbef771b662ee4aedb0b33bc761a7a8c319cfb06ade09fde';  -- Sócio, caso k_x, exp 1800000000
  -- vetores v2 (node, segredo c_seg, exp 4102444800 = 2100-01-01):
  t_ana_a  constant text := 'v2.4102444800.a0000000-0000-4000-8000-000000000002.c0000000-0000-4000-8000-00000000000a.c9df5f97e60e558f9a541cf63d5b0a9f628c4df462444cb690322ad6658bf271';
  t_soc_a  constant text := 'v2.4102444800.a0000000-0000-4000-8000-000000000001.c0000000-0000-4000-8000-00000000000a.8c8caf3bc1c89f33b4b52256296b45b5601a9fe3fdab50c94fb261ef0fb258d5';
  t_ana_b  constant text := 'v2.4102444800.a0000000-0000-4000-8000-000000000002.c0000000-0000-4000-8000-00000000000b.d21f1bef4e8bfb5b0cdfb2c1b8f36e17b92913f5229626b97a0d9e1da0fc01a4';
  t_soc_d  constant text := 'v2.4102444800.a0000000-0000-4000-8000-000000000001.c0000000-0000-4000-8000-00000000000d.f570c95af29c7ba80b04124c5324ddb9264693b5306f1e5ae72b99511b4244fd';
  t_soc_f  constant text := 'v2.4102444800.a0000000-0000-4000-8000-000000000001.c0000000-0000-4000-8000-00000000000f.f77ee9a9340b10a951fbf5ee6d8b3fb97e5b2a6ab2ba822543304c4c801a8b30';
  t_lei_a  constant text := 'v2.4102444800.a0000000-0000-4000-8000-000000000003.c0000000-0000-4000-8000-00000000000a.0dd81f73a72ee4d2286d01ff21c0a94ac764f284692ee58796a90e94e60594f0';
  t_ana_a_exp constant text := 'v2.1800000000.a0000000-0000-4000-8000-000000000002.c0000000-0000-4000-8000-00000000000a.9e6e4083d33a925d9f94a97621406ba41d325b08dfdafbec2cc7d747863a2cc0';
  -- colisão v1 -> v2: mandato chamado "<uuid de B>"; o token v1 reescrito como v2 de B:
  t_col_v1    constant text := 'v1.4102444800.a0000000-0000-4000-8000-000000000002.acbca5d97fbf523feca93b3dc8e0a60cde5b1ce08d3d619e84d3585a9a64298a';
  t_col_v2    constant text := 'v2.4102444800.a0000000-0000-4000-8000-000000000002.c0000000-0000-4000-8000-00000000000b.acbca5d97fbf523feca93b3dc8e0a60cde5b1ce08d3d619e84d3585a9a64298a';
  -- mandato chamado "v2|<uuid de B>" (a mensagem v1 É a mensagem v2 de B), e o v1 reescrito como v2 de B (o hmac é o de t_ana_b):
  t_nome_v1   constant text := 'v1.4102444800.a0000000-0000-4000-8000-000000000002.d21f1bef4e8bfb5b0cdfb2c1b8f36e17b92913f5229626b97a0d9e1da0fc01a4';
  t_beta_v1   constant text := 'v1.4102444800.a0000000-0000-4000-8000-000000000002.cf28153c7d5d617601947e2c1884cce76e7b51114dd2db31e6e2b9287deb36c2';  -- "Beta Ações"
  -- vetor da LIB (segredo s3gredo-de-teste-do-n8n; usuário/caso da lib):
  t_lib constant text := 'v2.1893456000.3f1c9a52-7b0e-4d34-9a5e-0c2b1d6e8f10.7d2e4b18-5c63-4a9f-8e01-b3a6d5c9f742.f99872e4ecdb126c3d81e69bd34c957573fa70077980fd8dc4062a508f3780ea';
  k_lib constant uuid := '7d2e4b18-5c63-4a9f-8e01-b3a6d5c9f742';
  u_lib constant uuid := '3f1c9a52-7b0e-4d34-9a5e-0c2b1d6e8f10';
  v_r record;
  v_f execucao_falha;
  v_txt text;
  v_n int; v_n0 int; v_id uuid; v_sqlstate text;
begin
  update vault.secrets set secret = c_seg where name = 'n8n_intake_segredo';
  perform teste_assert_envio(found, 'precondição: o run.sh deixou o segredo no Vault local');

  insert into auth.users (id, email) values (u_socio, 'socio@t'), (u_ana, 'ana@t'), (u_lei, 'lei@t'), (u_lib, 'lib@t');
  insert into membro (usuario_id, papel) values (u_socio, 'socio'), (u_ana, 'analista'), (u_lei, 'leitura'), (u_lib, 'socio')
    on conflict (usuario_id) do update set papel = excluded.papel;
  insert into caso (id, nome) values (k_a, 'Alfa'), (k_b, 'Beta'), (k_f, 'Fechado'), (k_lib, 'Mandato da lib');
  update caso set fechado_em = now() where id = k_f;
  insert into alocacao (caso_id, usuario_id) values (k_a, u_ana) on conflict do nothing;

  -- 1. v2 VÁLIDO: autorizado, com o caso e o usuário.
  select * into v_r from fn_conferir_envio(t_ana_a, 'qualquer nome', '2026-11-04 12:00:00+00');
  perform teste_assert_envio(v_r.envio_autorizado and v_r.caso_id = k_a and v_r.usuario_id = u_ana::text and v_r.motivo_recusa is null
      and v_r.etapa_recusa = 'envio' and v_r.orcamento_mensagem is null,
    'v2 de Analista alocado: autorizado, devolve o caso_id e o usuário', row_to_json(v_r)::text);
  perform teste_assert_envio(teste_motivo(t_soc_a) = 'ok', 'v2 de Sócio (não precisa de alocação): autorizado');
  select count(*) into v_n from fn_conferir_envio(t_ana_a, 'x');
  perform teste_assert_envio(v_n = 1, 'v2: exatamente uma linha');
  perform teste_assert_envio(teste_motivo(t_ana_a, 'nome totalmente outro') = 'ok', 'v2 ignora o nome do mandato no envio (o caso é o do token)');

  -- 2. PARIDADE COM A LIB: o vetor que N8N/lib/assinatura-do-envio.mjs gera é aceito pelo banco com o segredo da lib.
  update vault.secrets set secret = 's3gredo-de-teste-do-n8n' where name = 'n8n_intake_segredo';
  select * into v_r from fn_conferir_envio(t_lib, 'x', '2026-11-04 12:00:00+00');
  perform teste_assert_envio(v_r.envio_autorizado and v_r.caso_id = k_lib and v_r.usuario_id = u_lib::text,
    'o vetor v2 da LIB é aceito pelo banco (mesma mensagem v2|caso|exp|usuario)', row_to_json(v_r)::text);
  perform teste_assert_envio(teste_motivo(t_ana_a) = 'assinatura', 'segredo da lib não valida token assinado com outro segredo');
  update vault.secrets set secret = c_seg where name = 'n8n_intake_segredo';

  -- 3. O DEFEITO: renomear o mandato depois de emitido o token.
  update caso set nome = 'Alfa Renomeado' where id = k_a;
  select * into v_r from fn_conferir_envio(t_ana_a, 'Alfa', '2026-11-04 12:00:00+00');
  perform teste_assert_envio(v_r.envio_autorizado and v_r.caso_id = k_a,
    'renomeado o mandato, o MESMO token ainda aponta para o MESMO caso', row_to_json(v_r)::text);
  select count(*) into v_n0 from caso;
  perform teste_assert_envio(fn_caso_do_envio(k_a, 'Alfa') = k_a, 'fn_caso_do_envio com o nome ANTIGO devolve o caso do token');
  select count(*) into v_n from caso;
  perform teste_assert_envio(v_n = v_n0, 'o envio com o nome antigo NÃO cria mandato (count(caso) não muda)', v_n0 || ' -> ' || v_n);
  select count(*) into v_n from evento_auditoria where acao = 'envio_nome_divergente' and entidade_ref = 'caso:' || k_a;
  perform teste_assert_envio(v_n = 1, 'o nome divergente é auditado: 1 evento', v_n::text);
  select * into v_r from evento_auditoria where acao = 'envio_nome_divergente' and entidade_ref = 'caso:' || k_a;
  perform teste_assert_envio(v_r.antes ->> 'nome_no_envio' = 'Alfa' and v_r.depois ->> 'nome_atual' = 'Alfa Renomeado',
    'a auditoria guarda os dois nomes', row_to_json(v_r)::text);
  perform fn_caso_do_envio(k_a, '  ALFA renomeado ');
  select count(*) into v_n from evento_auditoria where acao = 'envio_nome_divergente' and entidade_ref = 'caso:' || k_a;
  perform teste_assert_envio(v_n = 1, 'nome igual (caixa e pontas normalizadas) NÃO audita', v_n::text);
  -- CONTROLE: o roteamento ANTIGO (por nome) cria o mandato vazio. É o defeito; sem este assert o "count não muda" acima não provaria nada.
  select count(*) into v_n0 from caso;
  v_id := fn_upsert_caso('Alfa');
  select count(*) into v_n from caso;
  perform teste_assert_envio(v_n = v_n0 + 1 and v_id <> k_a,
    'CONTROLE: fn_upsert_caso(nome antigo) CRIA um mandato novo (o defeito do roteamento por nome)', v_n0 || ' -> ' || v_n);

  -- 4. fn_caso_do_envio falha FECHADA.
  begin perform fn_caso_do_envio(null, 'x'); v_sqlstate := 'ok'; exception when others then v_sqlstate := sqlstate; end;
  perform teste_assert_envio(v_sqlstate = 'P0002', 'fn_caso_do_envio(nulo) lança exceção', v_sqlstate);
  select count(*) into v_n0 from caso;
  begin perform fn_caso_do_envio(k_d, 'x'); v_sqlstate := 'ok'; exception when others then v_sqlstate := sqlstate; end;
  select count(*) into v_n from caso;
  perform teste_assert_envio(v_sqlstate = 'P0002' and v_n = v_n0, 'fn_caso_do_envio(caso inexistente) lança exceção e não cria nada', v_sqlstate);

  -- 5. RECUSAS PÓS-ASSINATURA, todas com o caso preso.
  select * into v_r from fn_conferir_envio(t_ana_b, 'Beta');
  perform teste_assert_envio(not v_r.envio_autorizado and v_r.motivo_recusa = 'sem_acesso' and v_r.caso_id = k_b and v_r.usuario_id is null
      and v_r.orcamento_mensagem like '%acesso%' and v_r.orcamento_mensagem like '%Nada foi gravado%',
    'Analista NÃO alocado no caso: sem_acesso, com o caso e a mensagem', row_to_json(v_r)::text);
  select count(*) into v_n0 from execucao_falha where caso_id = k_b;
  begin perform fn_registrar_falha_execucao(v_r.caso_id, 'Beta', v_r.etapa_recusa, v_r.orcamento_mensagem, null); v_sqlstate := 'ok';
  exception when others then v_sqlstate := sqlstate; end;
  select count(*) into v_n from execucao_falha where caso_id = k_b;
  perform teste_assert_envio(v_sqlstate = 'ok' and v_n = v_n0 + 1, 'sem_acesso: a recusa é GRAVADA presa ao caso pela sequência do nó', v_sqlstate || ' ' || v_n0 || '->' || v_n);
  delete from alocacao where caso_id = k_a and usuario_id = u_ana;
  select * into v_r from fn_conferir_envio(t_ana_a, 'Alfa');
  perform teste_assert_envio(v_r.motivo_recusa = 'sem_acesso' and v_r.caso_id = k_a,
    'Analista DESALOCADO depois de emitir o token: sem_acesso (vale o acesso do momento do envio)', row_to_json(v_r)::text);
  insert into alocacao (caso_id, usuario_id) values (k_a, u_ana);
  perform teste_assert_envio(teste_motivo(t_ana_a) = 'ok', 'realocado, o mesmo token volta a valer');
  select * into v_r from fn_conferir_envio(t_lei_a, 'Alfa');
  perform teste_assert_envio(v_r.motivo_recusa = 'sem_acesso' and v_r.caso_id = k_a, 'Leitura (não alocada): sem_acesso', row_to_json(v_r)::text);
  insert into alocacao (caso_id, usuario_id) values (k_a, u_lei);
  perform teste_assert_envio(teste_motivo(t_lei_a) = 'sem_acesso', 'Leitura alocada continua sem_acesso (só Sócio e Analista escrevem)');
  select * into v_r from fn_conferir_envio(t_soc_d, 'x');
  perform teste_assert_envio(v_r.motivo_recusa = 'caso_inexistente' and v_r.orcamento_mensagem like '%nunca cria mandato%',
    'caso apagado/inexistente: caso_inexistente (o envio nunca cria mandato)', row_to_json(v_r)::text);
  -- COMPORTAMENTO: a mesma sequência do nó Registrar Recusa (fn_registrar_falha_execucao(caso_id, mandato, etapa, mensagem, null)) GRAVA a recusa.
  -- execucao_falha.caso_id é FK de caso(id): devolver o id que não existe fazia o nó levar 23503 e a recusa se perdia.
  select count(*) into v_n0 from execucao_falha;
  begin perform fn_registrar_falha_execucao(v_r.caso_id, 'Mandato apagado', v_r.etapa_recusa, v_r.orcamento_mensagem, null); v_sqlstate := 'ok';
  exception when others then v_sqlstate := sqlstate; end;
  select count(*) into v_n from execucao_falha;
  perform teste_assert_envio(v_sqlstate = 'ok' and v_n = v_n0 + 1,
    'caso_inexistente: a recusa é GRAVADA em execucao_falha pela sequência do nó (sem violar a FK)', v_sqlstate || ' ' || v_n0 || '->' || v_n);
  select * into v_r from fn_conferir_envio(t_soc_f, 'Fechado');
  perform teste_assert_envio(v_r.motivo_recusa = 'caso_fechado' and v_r.caso_id = k_f and v_r.orcamento_mensagem like '%fechado%',
    'mandato FECHADO recusa o envio, mesmo de Sócio: caso_fechado', row_to_json(v_r)::text);
  select count(*) into v_n0 from execucao_falha where caso_id = k_f;
  begin perform fn_registrar_falha_execucao(v_r.caso_id, 'Fechado', v_r.etapa_recusa, v_r.orcamento_mensagem, null); v_sqlstate := 'ok';
  exception when others then v_sqlstate := sqlstate; end;
  select count(*) into v_n from execucao_falha where caso_id = k_f;
  perform teste_assert_envio(v_sqlstate = 'ok' and v_n = v_n0 + 1, 'caso_fechado: a recusa é GRAVADA presa ao caso pela sequência do nó', v_sqlstate || ' ' || v_n0 || '->' || v_n);
  select * into v_r from fn_conferir_envio(t_ana_a_exp, 'Alfa', '2027-06-01');
  perform teste_assert_envio(v_r.motivo_recusa = 'expirado' and v_r.caso_id = k_a and v_r.orcamento_mensagem like '%expirou%',
    'v2 expirado: expirado, com o caso preso', row_to_json(v_r)::text);
  update caso set fechado_em = null where id = k_f;
  perform teste_assert_envio(teste_motivo(t_soc_f) = 'ok', 'reaberto o mandato, o envio volta a ser aceito');
  update caso set fechado_em = now() where id = k_f;

  -- 5b. A RAIZ: a falha NUNCA se perde por causa de um id de caso que não existe (FK de execucao_falha, 23503 medido).
  -- expirado + mandato apagado: o caso do token existiu e sumiu. Apago k_x (criado aqui) com um token expirado dele.
  select * into v_r from fn_conferir_envio(t_exp_x, 'X', '2027-06-01');   -- k_x NÃO existe (nunca criado): expirado com caso que nunca existiu
  perform teste_assert_envio(v_r.motivo_recusa = 'expirado' and v_r.caso_id is null, 'expirado com caso que nunca existiu: devolve caso_id nulo', row_to_json(v_r)::text);
  select count(*) into v_n0 from execucao_falha;
  begin perform fn_registrar_falha_execucao(v_r.caso_id, 'X', v_r.etapa_recusa, v_r.orcamento_mensagem, null); v_sqlstate := 'ok';
  exception when others then v_sqlstate := sqlstate; end;
  select count(*) into v_n from execucao_falha;
  perform teste_assert_envio(v_sqlstate = 'ok' and v_n = v_n0 + 1, 'expirado + caso que nunca existiu: a sequência do nó GRAVA a recusa', v_sqlstate || ' ' || v_n0 || '->' || v_n);
  insert into caso (id, nome) values (k_x, 'Apagado depois');
  delete from caso where id = k_x;
  select * into v_r from fn_conferir_envio(t_exp_x, 'Apagado depois', '2027-06-01');
  perform teste_assert_envio(v_r.motivo_recusa = 'expirado' and v_r.caso_id is null, 'expirado com o mandato APAGADO: caso_id nulo (não devolve id solto)', row_to_json(v_r)::text);
  select count(*) into v_n0 from execucao_falha;
  begin perform fn_registrar_falha_execucao(v_r.caso_id, 'Apagado depois', v_r.etapa_recusa, v_r.orcamento_mensagem, null); v_sqlstate := 'ok';
  exception when others then v_sqlstate := sqlstate; end;
  select count(*) into v_n from execucao_falha;
  perform teste_assert_envio(v_sqlstate = 'ok' and v_n = v_n0 + 1, 'expirado + mandato apagado: a sequência do nó GRAVA a recusa', v_sqlstate || ' ' || v_n0 || '->' || v_n);
  -- A CORRIDA (caso apagado entre o retorno de fn_conferir_envio e o Registrar Recusa): chamada direta com id que não existe.
  select count(*) into v_n0 from execucao_falha;
  begin v_txt := fn_registrar_falha_execucao(k_x, 'Corrida', 'envio', 'msg', null)::text; v_sqlstate := 'ok';
  exception when others then v_sqlstate := sqlstate; end;
  select count(*) into v_n from execucao_falha;
  perform teste_assert_envio(v_sqlstate = 'ok' and v_n = v_n0 + 1, 'id inexistente direto na função de registro: grava 1 linha, sem 23503', v_sqlstate || ' ' || v_n0 || '->' || v_n);
  select * into v_f from execucao_falha where caso_nome = 'Corrida';
  perform teste_assert_envio(v_f.caso_id is null and v_f.caso_nome = 'Corrida' and v_f.detalhe ->> 'caso_id_anulado' = k_x::text,
    'a falha com id anulado guarda o NOME e o rastro do id anulado em detalhe', row_to_json(v_f)::text);
  begin perform fn_registrar_falha_execucao(k_x, 'Corrida2', 'envio', 'msg', '{"a":1}'::jsonb); exception when others then null; end;
  select * into v_f from execucao_falha where caso_nome = 'Corrida2';
  perform teste_assert_envio(v_f.detalhe ->> 'a' = '1' and v_f.detalhe ->> 'caso_id_anulado' = k_x::text, 'o detalhe que veio é preservado ao anular o id', row_to_json(v_f)::text);
  -- CONTROLE: caso que existe grava PRESO ao caso, sem anulação; id nulo continua gravando.
  perform fn_registrar_falha_execucao(k_b, 'Beta', 'envio', 'msg', null);
  select * into v_f from execucao_falha where caso_nome = 'Beta' and mensagem = 'msg';
  perform teste_assert_envio(v_f.caso_id = k_b and v_f.detalhe is null, 'CONTROLE: caso existente grava preso ao caso, sem rastro de anulação', row_to_json(v_f)::text);
  perform fn_registrar_falha_execucao(null, 'Sem caso', 'envio', 'msg', null);
  select * into v_f from execucao_falha where caso_nome = 'Sem caso';
  perform teste_assert_envio(v_f.caso_id is null and v_f.detalhe is null, 'CONTROLE: id nulo segue gravando com caso_id nulo (o caso ainda não existe)', row_to_json(v_f)::text);

  -- 6. ASSINATURA ANTES DE QUALQUER CONSULTA A CASO: token adulterado nunca revela se o caso existe/está fechado.
  select * into v_r from fn_conferir_envio(replace(t_soc_f, '.f77e', '.0000'), 'x');
  perform teste_assert_envio(v_r.motivo_recusa = 'assinatura' and v_r.caso_id is null,
    'hmac errado sobre caso FECHADO: assinatura (não caso_fechado), sem caso_id', row_to_json(v_r)::text);
  perform teste_assert_envio(teste_motivo(replace(t_soc_d, '.f570', '.0000')) = 'assinatura', 'hmac errado sobre caso INEXISTENTE: assinatura');
  perform teste_assert_envio(teste_motivo(replace(t_ana_b, '.d21f', '.0000')) = 'assinatura', 'hmac errado sobre caso sem acesso: assinatura');
  perform teste_assert_envio(teste_motivo(replace(t_ana_a, k_a::text, k_b::text)) = 'assinatura', 'caso trocado no token v2: assinatura');
  perform teste_assert_envio(teste_motivo(replace(t_ana_a, u_ana::text, u_socio::text)) = 'assinatura', 'usuário trocado no token v2 (escalada para Sócio): assinatura');

  -- 7. COLISÃO v1 -> v2 (a etiqueta 'v2|' é o que separa as duas mensagens).
  perform teste_assert_envio(teste_motivo(t_col_v1, k_b::text) = 'versao_antiga', 'v1 de um mandato chamado "<uuid de B>": versao_antiga, não aceito (0223)');
  perform teste_assert_envio(teste_motivo(t_col_v2) = 'assinatura', 'o mesmo hmac reescrito como v2 de B: assinatura (a etiqueta v2| separa)');
  -- 7b. Mandato chamado "v2|<uuid de B>": desde a 0223 o v1 inteiro é recusado antes do HMAC (a guarda `v2|` do v1 ficou sem função); o v2
  --     reescrito (assinatura VÁLIDA, é a de t_ana_b) cai em sem_acesso.
  select * into v_r from fn_conferir_envio(t_nome_v1, 'v2|' || k_b);
  perform teste_assert_envio(v_r.motivo_recusa = 'versao_antiga' and not v_r.envio_autorizado,
    'v1 de mandato chamado "v2|<uuid>": versao_antiga, antes do HMAC', row_to_json(v_r)::text);
  perform teste_assert_envio(teste_motivo(t_nome_v1, '  V2|' || k_b || ' ') = 'versao_antiga', 'idem com caixa e espaços nas pontas');
  perform teste_assert_envio(teste_motivo(t_ana_b) = 'sem_acesso', 'o v1 de "v2|<uuid de B>" reescrito como v2 de B: não autoriza (sem_acesso)');
  perform teste_assert_envio(teste_motivo(t_beta_v1, 'Beta Ações') = 'versao_antiga', 'v1 de mandato comum: versao_antiga');

  -- 8. v1 RECUSADO (0223): antes, 'exatamente como na 0217'.
  select * into v_r from fn_conferir_envio(t_beta_v1, 'Beta Ações', '2026-11-04 12:00:00+00');
  perform teste_assert_envio(not v_r.envio_autorizado and v_r.motivo_recusa = 'versao_antiga' and v_r.caso_id is null and v_r.usuario_id is null and v_r.etapa_recusa = 'envio',
    'v1 que a 0222 ainda aceitava: recusado, sem caso, sem usuário', row_to_json(v_r)::text);
  perform teste_assert_envio(teste_motivo(t_beta_v1, 'Alfa') = 'versao_antiga', 'v1 com mandato trocado: versao_antiga');
  select * into v_r from fn_conferir_envio(t_beta_v1, 'Beta Ações', '2101-01-01');
  perform teste_assert_envio(v_r.motivo_recusa = 'versao_antiga' and v_r.caso_id is null, 'v1 expirado: versao_antiga, caso_id nulo', row_to_json(v_r)::text);

  -- 9. MALFORMADO v2.
  perform teste_assert_envio(teste_motivo(t_ana_a || '.x') = 'malformado', 'v2 com 6 partes: malformado');
  perform teste_assert_envio(teste_motivo('v2.4102444800.' || u_ana || '.' || k_a) = 'malformado', 'v2 com 4 partes: malformado');
  perform teste_assert_envio(teste_motivo(replace(t_ana_a, k_a::text, upper(k_a::text))) = 'malformado', 'v2 com uuid do caso em maiúsculas: malformado');
  perform teste_assert_envio(teste_motivo(replace(t_ana_a, u_ana::text, upper(u_ana::text))) = 'malformado', 'v2 com uuid do usuário em maiúsculas: malformado');
  perform teste_assert_envio(teste_motivo(replace(t_ana_a, k_a::text, 'nao-e-um-uuid')) = 'malformado', 'v2 com caso que não é uuid: malformado (sem erro de cast)');
  perform teste_assert_envio(teste_motivo(replace(t_ana_a, '.c9df', '.c9DF')) = 'malformado', 'v2 com hmac em maiúsculas: malformado');

  -- 10. EXECUTE: só a conexão de serviço.
  perform teste_assert_envio(has_function_privilege('service_role', 'fn_caso_do_envio(uuid,text)', 'execute')
      and has_function_privilege('postgres', 'fn_caso_do_envio(uuid,text)', 'execute')
      and not has_function_privilege('authenticated', 'fn_caso_do_envio(uuid,text)', 'execute')
      and not has_function_privilege('anon', 'fn_caso_do_envio(uuid,text)', 'execute'),
    'EXECUTE de fn_caso_do_envio: service_role e postgres sim; authenticated e anon não');
  perform teste_assert_envio(has_function_privilege('service_role', 'fn_pode_escrever_caso_de(uuid,uuid)', 'execute')
      and not has_function_privilege('authenticated', 'fn_pode_escrever_caso_de(uuid,uuid)', 'execute')
      and not has_function_privilege('anon', 'fn_pode_escrever_caso_de(uuid,uuid)', 'execute'),
    'EXECUTE de fn_pode_escrever_caso_de: só service_role/postgres (não é oráculo de papel para o authenticated)');

  -- 11. fn_pode_escrever_caso (a das policies) segue igual, por auth.uid().
  perform set_config('request.jwt.claim.sub', u_ana::text, true);
  set local role authenticated;
  perform teste_assert_envio(fn_pode_escrever_caso(k_a) and not fn_pode_escrever_caso(k_b) and not fn_pode_escrever_caso(null),
    'fn_pode_escrever_caso (policies): Analista escreve onde está alocado e só ali');
  reset role;
  perform set_config('request.jwt.claim.sub', u_lei::text, true);
  set local role authenticated;
  perform teste_assert_envio(not fn_pode_escrever_caso(k_a), 'fn_pode_escrever_caso: Leitura nunca escreve');
  reset role;
  perform set_config('request.jwt.claim.sub', u_socio::text, true);
  set local role authenticated;
  perform teste_assert_envio(fn_pode_escrever_caso(k_b), 'fn_pode_escrever_caso: Sócio escreve tudo');
  reset role;

  -- 12. A SONDA prova a 0222 aplicada.
  perform teste_assert_envio((select count(*) from fn_instalacao_conferir() where migration = '0222') = 6
      and not exists (select 1 from fn_instalacao_conferir() where migration = '0222' and not presente),
    'a sonda: os 6 requisitos da 0222 presentes');
  perform teste_assert_envio((select presente from fn_instalacao_conferir() where chave = 'acesso_fn_pode_escrever'),
    'a sonda: acesso_fn_pode_escrever (0216) segue presente com o marcador da delegação');
  perform teste_assert_envio((select presente from fn_instalacao_conferir() where chave = 'envio_recusa_versao_antiga'),
    'a sonda: envio_recusa_versao_antiga (0223) presente');

  raise notice 'fim: % execuções', current_setting('envio.execucoes', true);
  if current_setting('envio.medindo', true) = 'on' then
    raise notice 'MEDIÇÃO: % falhas em % execuções', coalesce(current_setting('envio.falhas', true), '0'), current_setting('envio.execucoes', true);
  end if;
end
$teste$;

rollback;
