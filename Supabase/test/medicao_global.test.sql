-- =============================================================================
-- 0218 — a medição que dependia de quem olhava
--
-- O QUE ESTE TESTE AFIRMA (comportamento, não mecanismo):
--   1. A decisão de um Analista que COMPLETA o critério global promove o dial (antes: ficava em N1, 0 eventos).
--   2. Um recorte alto com o global baixo NÃO promove, e o veredito que o Analista lê é o global.
--   3. As quatro medições dão ao Analista e à Leitura o MESMO número que dão ao serviço (n8n), e esse número
--      é diferente do de um mandato vazio (senão a igualdade seria vazia).
--   4. Mandato que o leitor não lê dá 42501 (antes: zero calado); o mandato dele, não.
--   5. O navegador continua sem mudar o dial: o Analista chamando fn_mudar_dial direto não muda nada.
--   6. A sonda acusa RLS desligada numa tabela de public, e volta a presente quando religa.
--
-- COMO RODA. Uma transação, desfeita no fim. Os usuários são JWT (`request.jwt.claims`) mais `set local role
-- authenticated`, como o PostgREST faz (o mesmo de acesso_por_caso.test.sql). "Serviço" é sem JWT e sem
-- papel, que é como o n8n chega (fn_conexao_de_servico).
--
-- MEDIDO NÃO-VAZIO: ver o fim do arquivo (a contagem de cada correção desligada vai lá e na mensagem do
-- commit). Com `set acesso.medindo = on` o assert vira WARNING e conta, em vez de abortar.
-- =============================================================================
\set ON_ERROR_STOP on

begin;

create or replace function pg_temp.mg_assert(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('mg.execucoes', (coalesce(nullif(current_setting('mg.execucoes', true), ''), '0')::int + 1)::text, false);
  if coalesce(p_cond, false) then
    raise notice 'ok    %', p_nome;
  elsif current_setting('acesso.medindo', true) = 'on' then
    perform set_config('mg.falhas', (coalesce(nullif(current_setting('mg.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

create or replace function pg_temp.mg_como(p_uid uuid) returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create or replace function pg_temp.mg_servico() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- Uma decisão de revisão de documento: o veredito do estágio classificacao_doc_checklist (0136).
create or replace function pg_temp.mg_dec(p_caso uuid, p_concorda boolean) returns void language sql as $$
  insert into decisao (caso_id, tipo, autor, motivo, payload)
  values (p_caso, (case when p_concorda then 'aprovacao' else 'correcao_classificacao' end)::decisao_tipo,
          'analista:teste-0218', 'veredito de teste',
          jsonb_build_object('documento_id', gen_random_uuid(), 'tipo_de', 'balanco_patrimonial',
                             'tipo_para', case when p_concorda then 'balanco_patrimonial' else 'dre' end))
$$;

-- Arranjo do veredito sem o gatilho (senão o próprio arranjo, gravado como serviço, já promoveria) e o dial
-- devolvido a N1 com a promoção automática ligada.
create or replace function pg_temp.mg_arranjar(p_a_concordam int, p_b_concordam int, p_b_discordam int)
returns void language plpgsql as $$
begin
  perform pg_temp.mg_servico();
  delete from decisao;
  alter table decisao disable trigger trg_auto_promover_dial;
  perform pg_temp.mg_dec('00000000-0000-0000-0000-0000000218a0', true)  from generate_series(1, p_a_concordam);
  perform pg_temp.mg_dec('00000000-0000-0000-0000-0000000218b0', true)  from generate_series(1, p_b_concordam);
  perform pg_temp.mg_dec('00000000-0000-0000-0000-0000000218b0', false) from generate_series(1, p_b_discordam);
  alter table decisao enable trigger trg_auto_promover_dial;
  update estagio_autonomia set nivel_atual = 'N1', auto_promocao = true, base_do_nivel = 'nao_se_aplica',
         medicao_em = null, medicao_resumo = null
   where estagio = 'classificacao_doc_checklist';
end $$;

create or replace function pg_temp.mg_nivel() returns text language sql as $$
  select nivel_atual::text from estagio_autonomia where estagio = 'classificacao_doc_checklist'
$$;

create or replace function pg_temp.mg_erro(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return sqlstate;
end $$;

do $$
declare
  u_analista constant uuid := '00000000-0000-0000-0000-0000000218e1';
  u_leitura  constant uuid := '00000000-0000-0000-0000-0000000218e2';
  u_sem      constant uuid := '00000000-0000-0000-0000-0000000218e3';  -- logado, sem linha em membro
  c_a        constant uuid := '00000000-0000-0000-0000-0000000218a0';  -- o Analista e a Leitura estão aqui
  c_b        constant uuid := '00000000-0000-0000-0000-0000000218b0';  -- ninguém de teste está aqui
  c_vazio    constant uuid := '00000000-0000-0000-0000-0000000218c0';  -- mandato sem nada: o "recorte vazio"
  v_r        jsonb;
  v_s        jsonb;
  v_t        jsonb;
  v_n        int;
  v_rodada   uuid;
  v_det      text;
begin
  perform pg_temp.mg_servico();
  insert into auth.users (id, email) values (u_analista, 'analista-0218@teste'), (u_leitura, 'leitura-0218@teste'),
                                         (u_sem, 'sem-papel-0218@teste');
  insert into membro (usuario_id, papel) values (u_analista, 'analista'), (u_leitura, 'leitura');
  insert into caso (id, nome) values (c_a, 'Teste 0218 A'), (c_b, 'Teste 0218 B'), (c_vazio, 'Teste 0218 vazio');
  insert into alocacao (caso_id, usuario_id) values (c_a, u_analista), (c_a, u_leitura), (c_vazio, u_analista);

  -- ---------------------------------------------------------------------------
  raise notice '--- 1. a decisão do Analista que completa o critério GLOBAL promove o dial ---';
  -- Global: 29 concordâncias (A 9, B 20). O Analista vê só as 9 de A. A 30ª é dele.
  perform pg_temp.mg_arranjar(9, 20, 0);
  perform pg_temp.mg_como(u_analista);
  select count(*) into v_n from decisao;
  perform pg_temp.mg_assert(v_n = 9, 'controle: o Analista lê só as 9 decisões do mandato dele (a RLS está valendo)',
                            format('leu %s', v_n));
  perform pg_temp.mg_dec(c_a, true);
  perform pg_temp.mg_servico();
  perform pg_temp.mg_assert(pg_temp.mg_nivel() = 'N2',
    'a 30ª concordância, gravada pelo Analista, sobe o dial para N2 (o global tem 30 a 1,0)',
    format('dial em %s', pg_temp.mg_nivel()));
  perform pg_temp.mg_assert(exists (select 1 from evento_auditoria
                                     where entidade_ref = 'estagio:classificacao_doc_checklist'
                                       and acao = 'mudanca_dial' and ator = 'sistema:auto_dial'
                                       and (depois->'medicao'->>'n')::int = 30
                                       -- Só a desta transação: o tdf_test guarda eventos iguais de outras
                                       -- suítes, e sem isto o assert passava com a promoção quebrada (medido).
                                       and criado_em >= transaction_timestamp()),
    'a trilha registra a promoção com a medição GLOBAL (n = 30), com o ator sistema:auto_dial');

  -- ---------------------------------------------------------------------------
  raise notice '--- 2. recorte alto, global baixo: NÃO promove ---';
  -- Global: 49 (A 29 concordam, B 20 discordam) = 0,59. O Analista vê 29 a 1,0; a 30ª dele daria 30 a 1,0.
  perform pg_temp.mg_arranjar(29, 0, 20);
  perform pg_temp.mg_como(u_analista);
  perform pg_temp.mg_dec(c_a, true);
  v_r := fn_veredito_producao('classificacao_doc_checklist');
  perform pg_temp.mg_servico();
  perform pg_temp.mg_assert(pg_temp.mg_nivel() = 'N1',
    'com o global em 50 a 0,60, a 30ª concordância do recorte do Analista NÃO sobe o dial',
    format('dial em %s', pg_temp.mg_nivel()));
  perform pg_temp.mg_assert((v_r->>'n')::int = 50 and not (v_r->>'suficiente')::boolean,
    'o veredito que o Analista lê é o global (50 vereditos, insuficiente), não o recorte dele (30, suficiente)',
    v_r::text);

  -- ---------------------------------------------------------------------------
  raise notice '--- 3. o mesmo número para todo leitor ---';
  perform pg_temp.mg_servico();
  v_s := fn_veredito_producao('classificacao_doc_checklist');
  perform pg_temp.mg_como(u_leitura);
  v_t := fn_veredito_producao('classificacao_doc_checklist');
  perform pg_temp.mg_servico();
  perform pg_temp.mg_assert((v_t->>'n') = (v_s->>'n') and (v_t->>'concordancia') = (v_s->>'concordancia'),
    'fn_veredito_producao: a Leitura recebe o número do serviço', format('leitura %s, serviço %s', v_t->>'n', v_s->>'n'));

  -- classificação contábil (0128). Controle: o global não é o de um mandato vazio.
  v_s := fn_classe_contabil_concordancia(null);
  v_r := fn_classe_contabil_concordancia(c_vazio);
  perform pg_temp.mg_assert((v_s->>'com_veredito_humano')::int > 0 and v_s is distinct from v_r,
    'controle: há concordância contábil medida no banco, diferente da de um mandato vazio', v_s::text);
  perform pg_temp.mg_como(u_analista);
  v_t := fn_classe_contabil_concordancia(null);
  perform pg_temp.mg_servico();
  perform pg_temp.mg_assert(v_t = v_s, 'fn_classe_contabil_concordancia: o Analista recebe o número do serviço',
    format('analista %s, serviço %s', v_t->>'com_veredito_humano', v_s->>'com_veredito_humano'));

  -- Classe A (0126), que alimenta o veredito de reconciliacao_classe_a.
  v_s := fn_golden_classe_a(null);
  v_r := fn_golden_classe_a(c_vazio);
  perform pg_temp.mg_assert(v_s is distinct from v_r,
    'controle: há pendência de Classe A no banco, diferente da de um mandato vazio', v_s::text);
  perform pg_temp.mg_como(u_analista);
  v_t := fn_golden_classe_a(null);
  perform pg_temp.mg_servico();
  perform pg_temp.mg_assert(v_t = v_s, 'fn_golden_classe_a: o Analista recebe o número do serviço',
    format('analista %s, serviço %s', v_t, v_s));

  -- Cobertura do golden set (0126): a rodada com mais documentos, para o controle não ser vazio.
  select r.id into v_rodada from golden_rodada r
   order by (select coalesce(sum(n_documentos), 0) from fn_golden_cobertura(r.id)) desc limit 1;
  select jsonb_agg(to_jsonb(c) order by c.tipo) into v_s from fn_golden_cobertura(v_rodada) c;
  perform pg_temp.mg_assert((select sum((x->>'n_documentos')::int) from jsonb_array_elements(v_s) x) > 0,
    'controle: há rodada de golden set com documento rotulado', coalesce(v_rodada::text, 'nenhuma rodada'));
  perform pg_temp.mg_como(u_leitura);
  select jsonb_agg(to_jsonb(c) order by c.tipo) into v_t from fn_golden_cobertura(v_rodada) c;
  perform pg_temp.mg_servico();
  perform pg_temp.mg_assert(v_t = v_s, 'fn_golden_cobertura: a Leitura recebe a cobertura do serviço (antes: zero em tudo)');

  -- ---------------------------------------------------------------------------
  raise notice '--- 4. mandato alheio dá 42501; o próprio, não ---';
  perform pg_temp.mg_como(u_analista);
  perform pg_temp.mg_assert(pg_temp.mg_erro(format('select fn_veredito_producao(%L, %L)', 'classificacao_doc_checklist', c_b)) = '42501',
    'fn_veredito_producao com mandato alheio: 42501');
  perform pg_temp.mg_assert(pg_temp.mg_erro(format('select fn_classe_contabil_concordancia(%L)', c_b)) = '42501',
    'fn_classe_contabil_concordancia com mandato alheio: 42501');
  perform pg_temp.mg_assert(pg_temp.mg_erro(format('select fn_golden_classe_a(%L)', c_b)) = '42501',
    'fn_golden_classe_a com mandato alheio: 42501');
  v_r := fn_veredito_producao('classificacao_doc_checklist', c_a);
  perform pg_temp.mg_assert((v_r->>'n')::int = 30,
    'fn_veredito_producao com o mandato do próprio Analista: o recorte dele (30), sem erro', v_r->>'n');
  perform pg_temp.mg_como(u_sem);
  perform pg_temp.mg_assert(pg_temp.mg_erro('select fn_classe_contabil_concordancia(null)') = '42501'
                            and pg_temp.mg_erro('select fn_golden_classe_a(null)') = '42501'
                            and pg_temp.mg_erro($q$select fn_veredito_producao('classificacao_doc_checklist')$q$) = '42501'
                            and pg_temp.mg_erro(format('select count(*) from fn_golden_cobertura(%L)', v_rodada)) = '42501',
    'usuário sem papel: as quatro medições globais dão 42501 (0216: sem papel, nada)');
  perform pg_temp.mg_servico();

  -- ---------------------------------------------------------------------------
  raise notice '--- 5. o navegador continua sem mudar o dial ---';
  -- Global suficiente (50 a 1,0) e o Analista tenta pela porta de sempre, com o ator do sistema.
  perform pg_temp.mg_arranjar(25, 25, 0);
  -- Uma ação por vez, com o dial conferido entre elas: senão uma esconde a outra (medido).
  perform pg_temp.mg_como(u_analista);
  perform pg_temp.mg_erro($q$update estagio_autonomia set nivel_atual = 'N2'
                              where estagio = 'classificacao_doc_checklist'$q$);
  perform pg_temp.mg_servico();
  perform pg_temp.mg_assert(pg_temp.mg_nivel() = 'N1', 'o Analista não muda o dial por update direto',
    format('dial em %s', pg_temp.mg_nivel()));
  perform pg_temp.mg_como(u_analista);
  v_det := pg_temp.mg_erro($q$select fn_mudar_dial('classificacao_doc_checklist', 'N2', 'sistema:auto_dial',
                                                   'forja', null, null, null, true)$q$);
  perform pg_temp.mg_servico();
  perform pg_temp.mg_assert(pg_temp.mg_nivel() = 'N1',
    'o Analista chamando fn_mudar_dial direto (ator forjado sistema:auto_dial) não muda o dial',
    format('resultado %s, dial em %s', v_det, pg_temp.mg_nivel()));
  -- A promoção em si não é RPC: com o global suficiente, a Leitura chamando-a direto não sobe o dial.
  perform pg_temp.mg_como(u_leitura);
  v_det := pg_temp.mg_erro($q$select fn_dial_auto_promover('classificacao_doc_checklist')$q$);
  perform pg_temp.mg_servico();
  perform pg_temp.mg_assert(pg_temp.mg_nivel() = 'N1' and v_det = '42501',
    'a Leitura chamando fn_dial_auto_promover direto leva 42501 e o dial não sobe',
    format('resultado %s, dial em %s', v_det, pg_temp.mg_nivel()));

  -- ---------------------------------------------------------------------------
  raise notice '--- 6. a sonda acusa RLS desligada ---';
  -- Sem `strict`: requisito ausente do catálogo tem de CONTAR como reprovado no modo medindo, não abortar.
  perform pg_temp.mg_assert(exists (select 1 from fn_instalacao_conferir() where chave = 'rls_ligada_em_public' and presente),
    'com toda tabela de public com RLS, rls_ligada_em_public está presente');
  alter table decisao disable row level security;
  select detalhe into v_det from fn_instalacao_conferir() where chave = 'rls_ligada_em_public' and not presente;
  perform pg_temp.mg_assert(v_det like '%decisao%',
    'com a RLS desligada em decisao, a sonda acusa rls_ligada_em_public e nomeia a tabela', coalesce(v_det, 'presente'));
  alter table decisao enable row level security;
  perform pg_temp.mg_assert(exists (select 1 from fn_instalacao_conferir() where chave = 'rls_ligada_em_public' and presente),
    'religada, o requisito volta a presente');

  if current_setting('acesso.medindo', true) = 'on' then
    raise notice 'MEDINDO: % de % asserts reprovaram', coalesce(nullif(current_setting('mg.falhas', true), ''), '0'),
      current_setting('mg.execucoes', true);
  else
    raise notice 'TODOS OS % ASSERTS DA MEDIÇÃO GLOBAL PASSARAM', current_setting('mg.execucoes', true);
  end if;
end $$;

rollback;

-- MEDIDO NÃO-VAZIO (preenchido pelo protocolo; cada correção desligada sozinha, com `set acesso.medindo = on`):
--   * o banco de ANTES (as cinco funções invoker, a guarda da 0216, sem fn_exige_ler_caso; os privilégios da
--     0218 mantidos): 11 de 23
--   * fn_dial_auto_promover invoker: 2 (o dial fica em N1; a trilha não registra)
--   * fn_trg_so_socio com o corpo da 0216: 2 (os mesmos: a promoção é barrada como Analista)
--   * fn_veredito_producao invoker: 2 · fn_classe_contabil_concordancia invoker: 1 · fn_golden_classe_a invoker: 1 ·
--     fn_golden_cobertura invoker: 1
--   * fn_exige_ler_caso sem recusar: 3 (os três 42501)
--   * sem o requisito rls_ligada_em_public: 3
--   * o veredito filtrando pelos mandatos de quem chama, dentro do definer (a regressão que o "recorte alto não
--     promove" existe para pegar): 4, inclusive esse
--   * fn_mudar_dial security definer: 1 (a forja pelo ator sistema:auto_dial passa)
--   * fn_exige_ler_caso deixando passar quem não tem papel (a primeira versão): 1 · fn_dial_auto_promover
--     executável pelo authenticated (a primeira versão): 1 · o gatilho fn_trg_auto_promover_dial invoker: 2
--   * sem a guarda trg_estagio_autonomia_so_socio: 0 — a policy de update ainda barra; sem a guarda E com a policy
--     de update aberta: 2. Defesa em duas camadas, cada uma suficiente sozinha.
--   * NÃO derrubados por mutação nenhuma, por construção: os 4 controles de não-vazio e o recorte do próprio
--     Analista (30), que protege contra guarda excessiva.
--   Antes desta correção, o assert da trilha passava vazio (o tdf_test tem eventos iguais de outras suítes) e a falta
--   do requisito abortava o teste em vez de contar; os dois foram corrigidos e remedidos.
