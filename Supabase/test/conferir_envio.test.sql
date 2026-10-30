-- Teste da 0217 — fn_conferir_envio: a conferência do token HMAC do envio, agora no banco, com o segredo no Vault.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md): 63 asserts (medidos) — ver o cabeçalho de
-- Supabase/migrations/0217_o_segredo_do_envio_que_o_n8n_nao_tinha.sql ("MEDIÇÃO NÃO-VAZIA") para o número que reprova com cada correção desligada.
--
-- O QUE SE AFIRMA (comportamento, não mecanismo): um token que o PORTAL assina é aceito pelo banco; cada motivo de recusa
-- aparece quando e só quando deve, na ordem do verificarEnvio do N8N/lib/assinatura-do-envio.mjs; quem não é a conexão de
-- serviço não consegue sequer perguntar; o segredo nunca volta no resultado.
--
-- OS VETORES NÃO SÃO FIXTURE INVENTADA PARA UM BUG DE PRODUÇÃO: foram gerados em 30/10/2026 pelo `createHmac` do Node com a
-- mesma `mensagemAssinada` que o portal usa (portal/src/lib/assinatura-do-envio.ts, `assinarEnvio`), segredo e mandatos
-- fixos, e colados aqui. O banco não os recalcula — recalcular com a mesma conta provaria que a função concorda consigo mesma.
-- Os mandatos "İSTANBUL", "ΟΔΥΣΣΕΑΣ ΑΣ" e "Ǆ ß ẞ ᾈ" são os casos em que o `lower()` do Postgres DIVERGE do toLowerCase do JS.
--
-- Roda dentro de uma transação desfeita: o segredo de teste que o run.sh grava no Vault local volta ao que era.

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

-- 'ok' quando autorizado, senão o motivo.
create or replace function teste_motivo(p_token text, p_mandato text, p_agora timestamptz default '2026-10-30 12:00:00+00')
returns text language sql as $$
  select case when envio_autorizado then 'ok' else coalesce(motivo_recusa, '?') end
    from fn_conferir_envio(p_token, p_mandato, p_agora) $$;

do $teste$
declare
  c_seg  constant text := 'segredo-de-paridade-ç-Ω';
  c_u    constant text := '3f2b8c1e-5a4d-4e6f-9a1b-0c2d3e4f5a6b';
  c_exp  constant text := '4102444800';              -- 2100-01-01T00:00:00Z
  c_pre  constant text := 'v1.4102444800.3f2b8c1e-5a4d-4e6f-9a1b-0c2d3e4f5a6b.';
  -- gerados pelo createHmac do Node (mensagemAssinada do portal), segredo c_seg, usuário c_u, exp c_exp:
  v_beta   constant text := c_pre || '98de1c3c51c7174cddc59a87f4c33ef04452187af36ffd3b8d00cc0f99b31555';  -- "Beta Ações"
  v_acoes  constant text := c_pre || 'b5aa059295e544792e8bda0d20c8b918f24330843f61be5f15b3d9d31fb176db';  -- "  AÇÕES S.A.  "
  v_istan  constant text := c_pre || '71c6e16b2891b4ca826c73b4289084ba94e2495908650d7783d0ef74086d188d';  -- "İSTANBUL"
  v_sigma  constant text := c_pre || '9494f56897dc6a3f9c1568af6a3a8b97f1f83d4062b53fc7e81c17323c018cc3';  -- "ΟΔΥΣΣΕΑΣ ΑΣ"
  v_tab    constant text := c_pre || 'b5eced584ce8d33aeea368a273acb272e32115fb1f5a96f936d89b9a7df3af69';  -- "\tTab"
  v_alfa   constant text := c_pre || 'd4d6d48cc2c4495c8d4dcd8a48878df36c1cf6113825fb2a2c7d6d98618ec87b';  -- " Alfa 2026 "
  v_exot   constant text := c_pre || 'f07f4440b180f7be840592c940edafc1a4c12d11b6f85b612d7b91e6e47ecb1e';  -- "Ǆ ß ẞ ᾈ"
  c_zero constant text := repeat('0', 64);
  v_agora constant timestamptz := '2026-10-30 12:00:00+00';
  v_r    record;
  v_n    int;
  v_sqlstate text;
  v_id   uuid;
  v_txt  text;
begin
  update vault.secrets set secret = c_seg where name = 'n8n_intake_segredo';
  perform teste_assert_envio(found, 'precondição: o run.sh deixou o segredo n8n_intake_segredo no Vault local');

  -- 1. HMAC puro: RFC 4231, caso 2 (chave "Jefe"). Prova que o hmac() que a função usa é o HMAC-SHA256 padrão.
  perform teste_assert_envio(
    encode(hmac(convert_to('what do ya want for nothing?', 'UTF8'), convert_to('Jefe', 'UTF8'), 'sha256'), 'hex')
      = '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
    'HMAC-SHA256 bate com o vetor do RFC 4231 caso 2');

  -- 2. PARIDADE COM O PORTAL: o token que o createHmac do Node gerou é aceito, com o usuário certo.
  select * into v_r from fn_conferir_envio(v_beta, 'Beta Ações', v_agora);
  perform teste_assert_envio(v_r.envio_autorizado and v_r.usuario_id = c_u and v_r.motivo_recusa is null and v_r.orcamento_mensagem is null,
    'token do portal (acentuado, com maiúscula) é aceito e devolve o usuário', row_to_json(v_r)::text);
  perform teste_assert_envio(teste_motivo(v_acoes, '  AÇÕES S.A.  ') = 'ok', 'token assinado com espaços e acentos nas pontas é aceito');
  perform teste_assert_envio(teste_motivo(v_tab, E'\tTab') = 'ok', 'mandato com TAB na ponta: só U+0020 é tirado, e o token do portal é aceito');
  perform teste_assert_envio(teste_motivo(v_alfa, ' Alfa 2026 ') = 'ok', 'mandato com espaços nas pontas é aceito');
  perform teste_assert_envio(teste_motivo(v_istan, 'İSTANBUL') = 'ok',
    'minúsculas de "İ": o JS dá "i" + U+0307 (o lower() puro do Postgres dá "i" e reprovaria)');
  perform teste_assert_envio(teste_motivo(v_sigma, 'ΟΔΥΣΣΕΑΣ ΑΣ') = 'ok',
    'minúsculas de sigma FINAL: o JS dá "ας" (o lower() puro do Postgres dá "ασ" e reprovaria)');
  perform teste_assert_envio(teste_motivo(v_exot, 'Ǆ ß ẞ ᾈ') = 'ok', 'minúsculas de Ǆ, ß, ẞ, ᾈ batem com o JS');

  -- 3. NORMALIZAÇÃO DO MANDATO.
  perform teste_assert_envio(teste_motivo(v_beta, 'BETA AÇÕES') = 'ok', 'caixa diferente do mandato normaliza igual: aceito');
  perform teste_assert_envio(teste_motivo(v_beta, '   beta ações   ') = 'ok', 'espaços nas pontas e caixa: aceito');
  perform teste_assert_envio(teste_motivo(v_beta, 'Alfa') = 'assinatura', 'mandato TROCADO depois de assinado cai em assinatura');
  perform teste_assert_envio(teste_motivo(v_beta, 'Beta  Ações') = 'assinatura', 'espaço no MEIO do mandato não é normalizado');
  perform teste_assert_envio(teste_motivo(v_tab, 'tab') = 'assinatura', 'TAB não é espaço: "\tTab" e "tab" são mandatos diferentes');
  perform teste_assert_envio(teste_motivo(v_beta, null) = 'assinatura', 'mandato nulo é um mandato vazio: assinatura');

  -- 4. TOKEN COM ESPAÇO NAS PONTAS (o JS faz token.trim()).
  perform teste_assert_envio(teste_motivo('  ' || v_beta || E'\n', 'Beta Ações') = 'ok', 'token com espaço e quebra de linha nas pontas é aceito');
  perform teste_assert_envio(teste_motivo(E'\u00a0' || v_beta || E'\u3000', 'Beta Ações') = 'ok', 'token com NBSP e espaço ideográfico nas pontas é aceito');

  -- 5. sem_token
  perform teste_assert_envio(teste_motivo(null, 'Beta Ações') = 'sem_token', 'token nulo: sem_token');
  perform teste_assert_envio(teste_motivo('', 'Beta Ações') = 'sem_token', 'token vazio: sem_token');
  perform teste_assert_envio(teste_motivo(E' \t\n ', 'Beta Ações') = 'sem_token', 'token só de espaços: sem_token');

  -- 6. malformado
  perform teste_assert_envio(teste_motivo('lixo', 'Beta Ações') = 'malformado', 'texto qualquer: malformado');
  perform teste_assert_envio(teste_motivo('v1.' || c_exp || '.' || c_u, 'Beta Ações') = 'malformado', '3 partes: malformado');
  perform teste_assert_envio(teste_motivo(v_beta || '.x', 'Beta Ações') = 'malformado', '5 partes: malformado');
  perform teste_assert_envio(teste_motivo(replace(v_beta, 'v1.', 'v2.'), 'Beta Ações') = 'malformado', 'versão v2: malformado');
  perform teste_assert_envio(teste_motivo('v1.1234567890123.' || c_u || '.' || c_zero, 'Beta Ações') = 'malformado', 'exp com 13 dígitos: malformado');
  perform teste_assert_envio(teste_motivo('v1.12a.' || c_u || '.' || c_zero, 'Beta Ações') = 'malformado', 'exp com letra: malformado');
  perform teste_assert_envio(teste_motivo('v1.' || c_exp || '.abc.' || c_zero, 'Beta Ações') = 'malformado', 'usuário com 3 caracteres: malformado');
  perform teste_assert_envio(teste_motivo(upper(v_beta), 'Beta Ações') = 'malformado', 'hmac em maiúsculas: malformado (o portal emite minúsculas)');
  perform teste_assert_envio(teste_motivo(c_pre || repeat('a', 63), 'Beta Ações') = 'malformado', 'hmac com 63 hex: malformado');
  perform teste_assert_envio(teste_motivo(replace(v_beta, '.' || c_exp || '.', '.٤١٠٢٤٤٤٨٠٠.'), 'Beta Ações') = 'malformado',
    'exp com dígitos não-ASCII: malformado (\d do JS é só ASCII)');

  -- 7. assinatura
  perform teste_assert_envio(teste_motivo(c_pre || c_zero, 'Beta Ações') = 'assinatura', 'hmac bem formado e errado: assinatura');
  perform teste_assert_envio(teste_motivo(replace(v_beta, c_u, '3f2b8c1e-5a4d-4e6f-9a1b-0c2d3e4f5a6c'), 'Beta Ações') = 'assinatura',
    'usuário trocado no token: assinatura');
  perform teste_assert_envio(teste_motivo(replace(v_beta, '.' || c_exp || '.', '.4102444801.'), 'Beta Ações') = 'assinatura',
    'exp adulterado para mais tempo: assinatura (não vira token eterno)');
  perform teste_assert_envio(teste_motivo(v_beta, 'Beta Ações', '2101-01-01') = 'expirado', 'assinatura certa e prazo vencido: expirado, não assinatura');
  update vault.secrets set secret = c_seg || 'x' where name = 'n8n_intake_segredo';
  perform teste_assert_envio(teste_motivo(v_beta, 'Beta Ações') = 'assinatura', 'segredo diferente do que assinou: assinatura');
  update vault.secrets set secret = c_seg where name = 'n8n_intake_segredo';

  -- 8. expirado — e a ordem: a assinatura vem ANTES do prazo.
  perform teste_assert_envio(teste_motivo(v_beta, 'Beta Ações', to_timestamp(4102444800) - interval '1 millisecond') = 'ok',
    'um milissegundo antes de exp: aceito');
  perform teste_assert_envio(teste_motivo(v_beta, 'Beta Ações', to_timestamp(4102444800)) = 'expirado', 'exatamente em exp: expirado (exp*1000 > agora é estrito)');
  select * into v_r from fn_conferir_envio(v_beta, 'Beta Ações', '2101-01-01');
  perform teste_assert_envio(v_r.orcamento_mensagem like '%expirou%' and not v_r.envio_autorizado and v_r.usuario_id is null,
    'a recusa por expiração diz que expirou e não devolve usuário', v_r.orcamento_mensagem);
  perform teste_assert_envio(teste_motivo(c_pre || c_zero, 'Beta Ações', '2101-01-01') = 'assinatura',
    'ordem: assinatura errada com prazo vencido é assinatura (expirado só para quem provou ter o segredo)');

  -- 9. sem_segredo — e é o PRIMEIRO motivo.
  select * into v_r from fn_conferir_envio(v_beta, 'Beta Ações', v_agora);
  update vault.secrets set secret = '' where name = 'n8n_intake_segredo';
  perform teste_assert_envio(teste_motivo(v_beta, 'Beta Ações') = 'sem_segredo', 'segredo vazio: sem_segredo');
  update vault.secrets set secret = E'  \t ' || E'\u00a0' where name = 'n8n_intake_segredo';
  perform teste_assert_envio(teste_motivo(v_beta, 'Beta Ações') = 'sem_segredo', 'segredo só de espaços (inclui NBSP): sem_segredo');
  perform teste_assert_envio(teste_motivo(null, 'Beta Ações') = 'sem_segredo', 'ordem: sem segredo vence sem_token');
  select * into v_r from fn_conferir_envio(v_beta, 'Beta Ações', v_agora);
  perform teste_assert_envio(not v_r.envio_autorizado and v_r.orcamento_mensagem like '%Vault%' and v_r.orcamento_mensagem like '%n8n_intake_segredo%'
      and v_r.orcamento_mensagem like '%Nada foi gravado%' and v_r.orcamento_mensagem like '%responsável pelo sistema%',
    'a mensagem de sem_segredo manda para o Vault, diz que nada foi gravado e que é configuração', v_r.orcamento_mensagem);
  delete from vault.secrets where name = 'n8n_intake_segredo';
  perform teste_assert_envio(teste_motivo(v_beta, 'Beta Ações') = 'sem_segredo', 'segredo AUSENTE do Vault: sem_segredo');
  perform teste_assert_envio(coalesce(fn_segredo_do_vault_presente('n8n_intake_segredo'), false) = false, 'a sonda vê o segredo ausente');
  update vault.secrets set secret = c_seg where name = 'n8n_intake_segredo';   -- no-op (linha apagada)
  perform vault.create_secret(c_seg, 'n8n_intake_segredo');
  perform teste_assert_envio(teste_motivo(v_beta, 'Beta Ações') = 'ok', 'segredo gravado com vault.create_secret: o mesmo token passa a ser aceito');
  perform teste_assert_envio(fn_segredo_do_vault_presente('n8n_intake_segredo'), 'a sonda vê o segredo presente');
  perform vault.create_secret('valor qualquer', 'outro_segredo');
  perform teste_assert_envio(fn_segredo_do_vault_presente('outro_segredo') = false, 'fn_segredo_do_vault_presente não responde por nome fora da lista');

  -- 10. FORMA: sempre UMA linha, caso_id nulo, etapa 'envio'.
  select count(*) into v_n from fn_conferir_envio(null, null, v_agora);
  perform teste_assert_envio(v_n = 1, 'tudo nulo: exatamente uma linha', v_n::text);
  select count(*) into v_n from fn_conferir_envio(v_beta, 'Beta Ações', v_agora);
  perform teste_assert_envio(v_n = 1, 'envio autorizado: exatamente uma linha', v_n::text);
  select * into v_r from fn_conferir_envio('lixo', 'x', v_agora);
  perform teste_assert_envio(v_r.caso_id is null and v_r.etapa_recusa = 'envio' and v_r.usuario_id is null and not v_r.envio_autorizado,
    'recusa: caso_id nulo, etapa_recusa = envio, sem usuário', row_to_json(v_r)::text);
  select * into v_r from fn_conferir_envio(v_beta, 'Beta Ações', v_agora);
  perform teste_assert_envio(v_r.caso_id is null and v_r.etapa_recusa = 'envio',
    'autorizado: caso_id continua nulo e etapa_recusa = envio', row_to_json(v_r)::text);
  perform teste_assert_envio(row_to_json(v_r)::text not like '%' || c_seg || '%', 'o segredo nunca aparece no resultado');

  -- 11. QUEM PODE EXECUTAR: só a conexão de serviço.
  set local role authenticated;
  begin perform fn_conferir_envio(v_beta, 'Beta Ações'); v_sqlstate := 'ok';
  exception when others then v_sqlstate := sqlstate; end;
  reset role;
  perform teste_assert_envio(v_sqlstate = '42501', 'authenticated NÃO executa fn_conferir_envio (42501)', v_sqlstate);
  set local role anon;
  begin perform fn_conferir_envio(v_beta, 'Beta Ações'); v_sqlstate := 'ok';
  exception when others then v_sqlstate := sqlstate; end;
  reset role;
  perform teste_assert_envio(v_sqlstate = '42501', 'anon NÃO executa fn_conferir_envio (42501)', v_sqlstate);
  set local role service_role;
  begin v_txt := teste_motivo(v_beta, 'Beta Ações'); exception when others then v_txt := 'erro ' || sqlstate; end;
  reset role;
  perform teste_assert_envio(v_txt = 'ok', 'service_role (a conexão do n8n) executa e o token é aceito', v_txt);
  perform teste_assert_envio(has_function_privilege('service_role', 'fn_conferir_envio(text,text,timestamptz)', 'execute')
      and has_function_privilege('postgres', 'fn_conferir_envio(text,text,timestamptz)', 'execute')
      and not has_function_privilege('authenticated', 'fn_conferir_envio(text,text,timestamptz)', 'execute')
      and not has_function_privilege('anon', 'fn_conferir_envio(text,text,timestamptz)', 'execute'),
    'EXECUTE: service_role e postgres sim; authenticated e anon não');
  perform teste_assert_envio((select prosecdef from pg_proc where oid = 'fn_conferir_envio(text,text,timestamptz)'::regprocedure)
      and exists (select 1 from pg_proc p, unnest(p.proconfig) c
                   where p.oid = 'fn_conferir_envio(text,text,timestamptz)'::regprocedure and c like 'search_path=%'),
    'security definer com search_path fixo');

  -- 12. A SONDA (regra 7): o segredo ausente é visível, com o sintoma.
  perform teste_assert_envio((select presente from fn_instalacao_conferir() where chave = 'envio_segredo_no_vault'),
    'a sonda: requisito envio_segredo_no_vault presente com o segredo no Vault');
  delete from vault.secrets where name = 'n8n_intake_segredo';
  select * into v_r from fn_instalacao_conferir() where chave = 'envio_segredo_no_vault';
  perform teste_assert_envio(not v_r.presente and v_r.porque like '%TODO envio%' and v_r.severidade = 'bloqueante',
    'a sonda ACUSA o segredo ausente, bloqueante, com o sintoma "todo envio recusado"', row_to_json(v_r)::text);
  perform vault.create_secret(E'   ', 'n8n_intake_segredo');
  perform teste_assert_envio(not (select presente from fn_instalacao_conferir() where chave = 'envio_segredo_no_vault'),
    'a sonda acusa segredo só de espaços como ausente');
  perform teste_assert_envio((select presente from fn_instalacao_conferir() where chave in ('envio_conferencia_funcao')),
    'a sonda: fn_conferir_envio presente');
  perform teste_assert_envio((select presente from fn_instalacao_conferir() where chave = 'envio_conferencia_corpo'),
    'a sonda: o corpo de fn_conferir_envio lê o Vault (marcador decrypted_secrets)');

  raise notice 'fim: % execuções', current_setting('envio.execucoes', true);
  if current_setting('envio.medindo', true) = 'on' then
    raise notice 'MEDIÇÃO: % falhas em % execuções', coalesce(current_setting('envio.falhas', true), '0'), current_setting('envio.execucoes', true);
  end if;
end
$teste$;

rollback;
