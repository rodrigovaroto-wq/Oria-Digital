-- =============================================================================
-- 0219 — A GUARDA DO DIAL QUE CONFERIA O FORMATO DO UPDATE, e o `rls_auto_enable` que perdeu o PUBLIC
-- (REDEFINE 4 funções — fn_trg_so_socio, fn_dial_auto_promover, fn_trg_auto_promover_dial e fn_instalacao_conferir (+1 tipo, `definer_sem_escrita`,
--  e o ramo `sem_privilegio` passa a ignorar função que retorna event_trigger); +1 requisito novo, 1 renomeado e 3 com marcador novo na sonda; DEVOLVE a
--  `public.rls_auto_enable()` o EXECUTE de PUBLIC, SE ela existir. Sem tabela, sem backfill, sem dado alterado. Idempotente: pode ser reaplicada.)
--
-- >>> RODE COMO `postgres` (a função da plataforma é do postgres; o REVOKE/GRANT de quem não é dono só avisa).
-- >>> A 0218 está APLICADA e CONFERIDA em produção (sonda 302/302 em 30/10/2026) e NÃO foi tocada: esta migration é por cima dela.
--
-- ===== DEFEITO 1 (latente, calado): a guarda de Sócio do dial conferia o FORMATO do UPDATE, e quebrava a promoção sem avisar =====
-- A guarda do dial e do catálogo de premissas é o MESMO gatilho (`fn_trg_so_socio`: trg_estagio_autonomia_so_socio e trg_premissa_catalogo_so_socio, 0216).
-- A 0218 abriu nele UMA exceção para a promoção automática: a GUC `tdf.promocao_automatica = 'sim'` E `current_user` fora de authenticated/anon E o formato
-- exato do UPDATE (nível N2, base `medida_por_veredito`, autor `sistema:auto_dial`). O formato é o que `fn_mudar_dial` escreve HOJE. Quem mudar `fn_mudar_dial`
-- (outra base, outro autor, um passo a mais) faz a guarda recusar a promoção com 42501 — e o gatilho da 0137 engole o erro e o transforma em NOTICE: o dial
-- deixa de subir por decisão de qualquer pessoa, sem erro, sem linha na trilha (regra 7: estágio que não rodou com cara de estágio que rodou). A revisão de código da
-- 0218 (03/11/2026) apontou o risco; ele não tem sintoma até o dia em que alguém mexe em `fn_mudar_dial`.
--
-- A CORREÇÃO (decisão do dono, 03/11/2026): UMA regra, "código que roda como dono é confiável". Se `current_user` NÃO é `authenticated` nem `anon`, a escrita
-- passa; caso contrário, `fn_exige_socio` como antes. Isto cobre (a) a conexão de serviço (SQL Editor, n8n, service_role) e (b) o código SECURITY DEFINER do
-- dono, que é como o Postgres trata a função definer (dentro dela `current_user` é o dono). A GUC e o formato saem: `fn_dial_auto_promover` e o handler de
-- `fn_trg_auto_promover_dial` são reemitidos INTEIROS, a partir do corpo da 0218, só sem o `set_config` da marca (e sem os comentários dela). Nada mais mudou neles.
-- `fn_mudar_dial` NÃO foi reescrita (continua INVOKER: é isso que faz o Analista, que a chama como authenticated, levar o 42501 do gatilho).
--
-- QUEM CHAMA (grep -rn em Supabase/ N8N/ portal/src, 03/11/2026):
--   fn_trg_so_socio            <- só os dois gatilhos (0216); nenhum chamador direto.
--   fn_dial_auto_promover      <- fn_trg_auto_promover_dial; testes (auto_promocao_dial.test.sql, o_dial_e_o_anon.test.sql); nenhum chamador no portal nem no n8n.
--   fn_trg_auto_promover_dial  <- só trg_auto_promover_dial (AFTER INSERT em decisao).
--   fn_instalacao_conferir     <- portal (tela da sonda), n8n/sonda agendada (sonda-producao.mjs), testes. A assinatura de retorno NÃO mudou.
--
-- O RISCO QUE A REGRA SIMPLES ABRE, e o portão novo. Uma função SECURITY DEFINER nova, executável por `authenticated`, que escreva em estagio_autonomia ou em
-- premissa_catalogo — direto, ou chamando `fn_mudar_dial` —, passa pela guarda sem o chamador ser Sócio (o teste CRIA uma e prova: o Analista sobe o dial).
-- Medido no replay local em 03/11/2026 (migrations até a 0218): NENHUMA função definer escreve direto nessas tabelas; as únicas que as citam com escrita são
-- `fn_mudar_dial` (INVOKER) e `fn_dial_auto_promover` (definer, FECHADA ao authenticated: só o gatilho, que é definer, e o service_role a executam). O pedido do
-- dono informa a mesma medição em produção (eu não a refiz). O portão é o requisito `definer_nao_escreve_no_dial` (tipo novo `definer_sem_escrita`, BLOQUEANTE):
-- acusa toda função de public com SECURITY DEFINER e (EXECUTE para authenticated OU função de gatilho) cujo corpo escreva nas duas tabelas ou chame `fn_mudar_dial`.
-- LISTA DE EXCEÇÕES: NENHUMA. Não há exceção legítima hoje, e não implementei o mecanismo (degrau 1 da escada: necessidade especulativa); o dia em que houver, a
-- função que a admite é fn_instalacao_conferir, numa migration, com o motivo. Decidi incluir a função de GATILHO sem exigir EXECUTE: ela dispara no DML de quem
-- escreve na tabela e roda como dono sem que ninguém a "execute", então o critério do pedido (EXECUTE para authenticated) a deixaria passar.
-- O QUE O PORTÃO NÃO VÊ (declarado no ramo): SQL dinâmico; o helper definer chamado por uma definer; definer fechada ao authenticated. Chamar `fn_dial_auto_promover`
-- de uma definer também não conta, de propósito: ela só sobe o estágio quando o veredito GLOBAL basta, que é o mesmo que o gatilho já faz a cada decisão.
-- LIMITE DA REGRA (honestidade, regra 1): ela confia em NOME de papel, não em pertinência. Um papel de login criado DENTRO de `authenticated` (herda o papel) não
-- é `authenticated` para `current_user` e passaria. Em produção não há tal papel (o PostgREST troca para authenticated/anon; n8n e SQL Editor entram como postgres);
-- a sonda não confere isso. Se um dia houver, a guarda tem de olhar `pg_auth_members`.
--
-- ===== DEFEITO 2: o laço de revoke da 0218 reescreveu a ACL de uma função que NÃO é do projeto =====
-- `public.rls_auto_enable()` é a função do event trigger `ensure_rls` da PLATAFORMA Supabase: em produção dona postgres, SECURITY DEFINER, retorna `event_trigger`.
-- Ela NÃO existe no repositório nem no replay. O laço da 0218 (todo objeto de public do postgres que não é de extensão) tirou-lhe o PUBLIC e repôs
-- authenticated, service_role e supabase_read_only_user: hoje a ACL é {postgres=X, authenticated=X, service_role=X, supabase_read_only_user=X}; antes era PUBLIC
-- (o anon tinha EXECUTE em 265 de 265 funções). Informado pelo pedido do dono em 03/11/2026 (medido em produção pela sessão principal; eu não o refiz).
-- A CORREÇÃO: se a função existir E retornar event_trigger, devolve o EXECUTE de PUBLIC e retira os grants explícitos que a 0218 pôs. No replay é no-op (a função
-- não existe). Se existir com outro retorno, NÃO mexe e avisa: não abrir a PUBLIC uma função que não é a da plataforma.
-- POR QUE É SEGURO ter o PUBLIC numa função que retorna event_trigger: ela não pode ser chamada por SQL nem por RPC (`select f()` e a chamada do PostgREST levam
-- erro "trigger functions can only be called as triggers"; o teste cria uma de mentira e prova isso por comportamento, como postgres e como anon).
-- A SONDA: o ramo `sem_privilegio` (anon_sem_funcoes) agora ignora função que retorna event_trigger; sem isso ela acusaria a própria correção em produção. Só
-- event_trigger, NÃO `trigger`: função de gatilho comum também não é chamável, mas o projeto já faz `revoke all ... from public` em todas as funções (a 0218 o fez
-- em todas) e ignorá-las afrouxaria o portão sem necessidade; a única que produção precisa que seja ignorada é a da plataforma. O teste prova: event_trigger dona
-- postgres com EXECUTE para PUBLIC não é acusada; função comum na mesma situação é.
-- GENERALIZAÇÃO, DE PROPÓSITO: FUNÇÃO DE PLATAFORMA FICA FORA DO CONTROLE DE ANON. Quem cria `rls_auto_enable` e os event triggers é o Supabase, não este repositório: nenhuma
-- migration nossa a cria, redefine ou concede nela, e a nossa convenção ("função nova faz revoke from public") não vale para código que não escrevemos. O laço da
-- 0218 não roda de novo; daqui para a frente o portão é a sonda, que (a) ignora event_trigger e (b) já ignora função de extensão e função de dono diferente de postgres.
-- A migration devolve a ACL só da função conhecida, pelo nome: não inventei uma lista do que "seria" de plataforma.
--
-- A SONDA (o catálogo revisado). `fn_instalacao_conferir` reemitida INTEIRA a partir da 0218 (ramos `segredo`, 0217, e `sem_privilegio`, 0218, preservados; o teste
-- reprova se sumirem): o diff contra a 0218 é só de linhas ACRESCENTADAS (2 variáveis, 1 filtro de event_trigger e o ramo novo). Requisitos: +1 (definer_nao_escreve_no_dial);
-- `dial_guarda_de_socio_tem_a_promocao` RENOMEADO para `dial_guarda_de_socio_confia_no_dono` (marcador: a linha `current_user not in (...)` da guarda nova; o antigo,
-- `tdf.promocao_automatica`, não existe mais no corpo); `dial_promocao_independe_do_leitor` e `dial_gatilho_independe_do_leitor` com marcador novo (o `set_config` da
-- marca saiu): as linhas SECURITY DEFINER e SET search_path que o pg_get_functiondef gera, que é o que os dois requisitos dizem. Os dois passam a valer `0219` na coluna
-- migration (são ela que os confere agora). `anon_sem_funcoes` só ganha um `porque` mais fiel.
--
-- DECIDI SOZINHO (cada item pode ser revertido numa migration nova): (1) incluir função de gatilho no portão novo; (2) não ter lista de exceções; (3) só event_trigger no
-- ramo do anon, não `trigger`; (4) devolver o PUBLIC só se a função retornar event_trigger; (5) renomear o requisito da guarda e mudar a coluna `migration` dos três que
-- mudaram de marcador; (6) marcador por cabeçalho (SECURITY DEFINER + SET search_path) nos dois requisitos da promoção, porque sem a GUC não sobrou linha de código
-- própria da 0218 nelas (o corpo é o da 0137); o portão sonda_marcador_e_codigo aceita (tem `_`) e o marcador é, de fato, o que o requisito afirma.
-- UM EFEITO COLATERAL SEU: a 0218 (arquivo) NÃO pode mais ser reaplicada por cima desta sem apagar antes os requisitos `definer_sem_escrita` — o `add constraint` do tipo
-- recusa linha de tipo que ela não conhece. O teste o_dial_e_o_anon.test.sql, que reaplica a 0218, apaga essa linha antes (dentro da transação que volta).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/a_guarda_do_dial_que_conferia_o_formato.test.sql — 57 chamadas de assert, 57 execuções (cada chamada roda uma vez), medidas em
-- 03/11/2026 com `PGOPTIONS='-c dial.medindo=on'` (o assert vira `raise warning` e CONTA; sem a variável é `raise exception`; o `run.sh` completo foi rodado sem ela, exit 0, e o log
-- relido inteiro atrás de FALHOU). Controle intacto: 57 ok, 0 falhas. Cada correção desligada UMA vez, num banco que já tem a 0219, com a variante reaplicada por `\i`
-- (`-v arq0219=<arquivo>`, que o teste faz logo no começo); em cada variante a migration APLICOU (rc 0) e o log traz a linha FIM com 57 execuções. Reprovações / 57:
--   * a guarda da 0218 (GUC + formato do UPDATE) com as funções sem a GUC — "o que acontece com a promoção": 6 (o dial não sobe por decisão de Analista: nível, base e trilha; não
--     sobe com o UPDATE em outro formato; o dono com o JWT de Analista leva 42501; e a definer-de-controle também, porque a regra do dono some);
--   * a guarda SEM o `current_user` (passa sempre): 12 · com o `current_user` excluindo só `anon` (authenticated passa): 12 · sem a exceção do dono (nunca passa): 7;
--   * a sonda `definer_sem_escrita` CEGA (v_ok sempre verdadeiro): 5 · sem exigir SECURITY DEFINER: 6 · sem a função de GATILHO: 1 · sem a chamada a fn_mudar_dial: 1 · com a busca
--     sensível a caixa: 1;
--   * a sonda do anon SEM excluir event_trigger: 5 (a correção passa a ser acusada, e o caso de função de event_trigger com PUBLIC);
--   * `rls_auto_enable` sem o grant a PUBLIC (simulado com uma função de event_trigger de mentira de mesmo nome): 3 · sem retirar os grants explícitos da 0218: 1 · sem checar
--     que retorna event_trigger (abriria também a homônima comum): 1;
--   * a reemissão da sonda sem o ramo `segredo` (0217): 2 · sem o ramo `sem_privilegio` (0218): 7;
--   * os três requisitos do dial com o marcador antigo (a GUC): 1;
--   * SÓ O MARCADOR, e é o número honesto: fn_dial_auto_promover sem SECURITY DEFINER: 1 · fn_trg_auto_promover_dial sem SECURITY DEFINER: 1. Nas duas, o comportamento NÃO muda dentro de uma só
--     sessão (o plpgsql guarda em cache a checagem de EXECUTE da chamada, aquecida pela semeadura como superusuário: mesma limitação que a 0218 já declarava), e quem reprova é o requisito
--     da sonda; por comportamento elas são indistinguíveis aqui;
--   * a constraint de tipo SEM `definer_sem_escrita`: a migration MORRE ("violated by some row", rc 3) e nenhum assert roda — isto NÃO é zero reprovações, é migration recusada.
-- Limite do teste: simula `rls_auto_enable` com uma função de event_trigger de mentira (a real é da plataforma e não existe no replay), e NÃO reproduz a ACL nem o dono de produção.
-- =============================================================================

-- =============================================================================
-- 1. A GUARDA — código que roda como dono é confiável
-- =============================================================================
-- IFs sem aninhar nada que dependa de `new`: a guarda NÃO lê a linha (por isso serve ao catálogo de premissas, que não tem `atualizado_por`, e ao dial).
-- Roda como INVOKER de propósito: dentro de uma definer o `current_user` do gatilho é o dono; chamada por authenticated (fn_mudar_dial é INVOKER, o UPDATE direto
-- também), é authenticated. O `current_user` é o do DML, não o dono da função do gatilho.
create or replace function fn_trg_so_socio() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  perform fn_exige_socio(tg_argv[0]);
  return case when tg_op = 'DELETE' then old else new end;
end $$;

comment on function fn_trg_so_socio() is
  '0216/0219: guarda de Sócio do dial (estagio_autonomia) e do catálogo de premissas. Desde a 0219 a regra é uma só: quem roda como dono (current_user fora de authenticated/anon: conexão de serviço, SQL Editor, n8n, service_role e o código SECURITY DEFINER do dono, como a promoção automática da 0137) escreve; quem roda como authenticated ou anon precisa ser Sócio (fn_exige_socio, 42501). A 0218 conferia a GUC tdf.promocao_automatica e o formato exato do UPDATE da promoção; saíram. RISCO: uma função SECURITY DEFINER executável por authenticated que escreva nessas tabelas passa pela guarda; a sonda (definer_nao_escreve_no_dial) a acusa.';

-- =============================================================================
-- 2. A PROMOÇÃO AUTOMÁTICA — sem a marca de transação (corpo da 0218, só sem o set_config)
-- =============================================================================
create or replace function fn_dial_auto_promover(p_estagio text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r         record;
  v_med     jsonb;
  v_res     jsonb;
  v_feitos  jsonb := '[]'::jsonb;
begin
  for r in
    select ea.estagio, ea.nivel_atual, ea.teto, ea.auto_promocao, ea.natureza
      from estagio_autonomia ea
     where (p_estagio is null or ea.estagio = p_estagio)
       and ea.natureza = 'interpretativo'
       and ea.auto_promocao
       and ea.nivel_atual < 'N2'::nivel_autonomia
       and ea.teto >= 'N2'::nivel_autonomia
  loop
    v_med := fn_veredito_producao(r.estagio);
    if not coalesce((v_med->>'suficiente')::boolean, false) then
      continue;
    end if;

    -- A PROMOÇÃO PASSA PELA MESMA PORTA DE SEMPRE. Chamar `fn_mudar_dial` em vez
    -- de dar `update` na tabela é o que garante que a automação não escape de
    -- nenhuma guarda: o teto, a regra de ouro e a trilha continuam sendo os
    -- mesmos, e o dia em que uma guarda nova for acrescentada lá ela passa a
    -- valer aqui sem ninguém lembrar de copiar.
    -- 0219: SEM MARCA. Esta função é DEFINER (roda como dono) e fn_trg_so_socio deixa passar quem roda como dono; ninguém confere mais o formato do
    -- UPDATE que fn_mudar_dial faz (a 0218 o conferia, e mudar fn_mudar_dial quebrava a promoção calado: o gatilho da 0137 engole o 42501).
    v_res := fn_mudar_dial(
      r.estagio, 'N2'::nivel_autonomia, 'sistema:auto_dial',
      format('Promoção automática (0137): o veredito de produção alcançou o critério — %s vereditos '
             'a %s de concordância, mínimo %s a %s. O número é PISO enviesado, e por isso a subida '
             'para em N2.',
             v_med->>'n', v_med->>'concordancia',
             v_med->>'n_minimo', v_med->>'concordancia_minima'),
      null, null, null, true);

    v_feitos := v_feitos || jsonb_build_object(
      'estagio', r.estagio,
      'de', r.nivel_atual,
      'para', v_res->>'nivel_atual',
      'recusado', coalesce((v_res->>'recusado')::boolean, false),
      'medicao', v_med);
  end loop;

  return jsonb_build_object(
    'promovidos', v_feitos,
    'quantos', jsonb_array_length(v_feitos),
    'como_ler', 'Promoção automática por veredito de produção (0137). Ela sobe no máximo até N2, '
                'nunca N3: o veredito mede um PISO enviesado, e piso não sustenta autonomia plena. '
                'Estágio com auto_promocao = false não entra aqui — é o freio de quem baixou o '
                'nível à mão, e religá-lo é decisão explícita.');
end;
$$;

comment on function fn_dial_auto_promover(text) is
  'Sobe para N2 todo estágio interpretativo elegível cujo veredito de produção alcançou o critério (0137). Sobe pela fn_mudar_dial, nunca por update direto, para não escapar de guarda nenhuma. Para em N2 por decisão: piso enviesado não sustenta autonomia plena. 0218: SECURITY DEFINER e fechada ao authenticated — mede o veredito GLOBAL e pode subir o dial mesmo disparada por um Analista; só o gatilho e o service_role a chamam. 0219: sem marca de transação; a guarda de Sócio (fn_trg_so_socio) deixa passar quem roda como dono, e esta função roda como dono.';

create or replace function fn_trg_auto_promover_dial()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_r jsonb;
begin
  if pg_trigger_depth() > 1 then
    return null;
  end if;

  begin
    v_r := fn_dial_auto_promover();
    if coalesce((v_r->>'quantos')::int, 0) > 0 then
      raise notice '0137: promoção automática do dial — %', v_r->'promovidos';
    end if;
  exception when others then
    raise notice '0137: a promoção automática falhou e foi ignorada (a decisão que a disparou está '
                 'gravada). Erro: %', sqlerrm;
  end;

  return null;
end;
$$;

comment on function fn_trg_auto_promover_dial() is
  'Gatilho da promoção automática (0137): toda decisão humana nova pode ter completado o critério do veredito de produção. NUNCA derruba a transação de quem o disparou — falha vira NOTICE, porque o analista não pode perder a rejeição de uma pendência por causa do dial. 0218: SECURITY DEFINER, para que a promoção não dependa do recorte nem do papel de quem decidiu. 0219: sem a marca tdf.promocao_automatica.';

-- =============================================================================
-- 3. O `rls_auto_enable` DA PLATAFORMA — devolve o PUBLIC que o laço da 0218 tirou
-- =============================================================================
do $$
declare
  v_f     regprocedure := to_regprocedure('public.rls_auto_enable()');
  v_papel text;
begin
  if v_f is null then
    raise notice '0219: public.rls_auto_enable() não existe neste banco (o replay local não tem o event trigger da plataforma): nada a devolver.';
    return;
  end if;
  if (select p.prorettype from pg_proc p where p.oid = v_f::oid) is distinct from 'event_trigger'::regtype then
    raise warning '0219: public.rls_auto_enable() existe mas NÃO retorna event_trigger: não é a função da plataforma, e o EXECUTE de PUBLIC NÃO foi devolvido.';
    return;
  end if;
  -- Os grants explícitos que a 0218 pôs (só os papéis que existirem: no Supabase os três existem).
  foreach v_papel in array array['authenticated', 'service_role', 'supabase_read_only_user'] loop
    if exists (select 1 from pg_roles where rolname = v_papel) then
      execute format('revoke all on function %s from %I', v_f, v_papel);
    end if;
  end loop;
  execute format('grant execute on function %s to public', v_f);
  raise notice '0219: o EXECUTE de PUBLIC foi devolvido a % (retorna event_trigger: não é chamável por SQL nem por RPC).', v_f;
end $$;

-- =============================================================================
-- 4. A SONDA — o portão do risco novo, o ramo do anon sem a função da plataforma, e os marcadores que a GUC deixou órfãos
-- =============================================================================
alter table instalacao_requisito drop constraint if exists instalacao_requisito_tipo_check;
alter table instalacao_requisito add constraint instalacao_requisito_tipo_check
  check (tipo in ('tabela', 'coluna', 'funcao', 'seed', 'comportamento', 'corpo', 'gatilho', 'policy', 'privilegio', 'segredo', 'sem_privilegio', 'definer_sem_escrita'));

-- fn_instalacao_conferir: a da 0218 INTEIRA (a que a produção tem desde 30/10/2026: ramos `segredo` da 0217 e `sem_privilegio` da 0218), só com linhas ACRESCENTADAS:
-- as variáveis v_tabs e v_funs, o filtro de event_trigger no ramo do anon e o ramo `definer_sem_escrita`. NÃO partir de outra: reemitir a função de antes APAGARIA um ramo.
CREATE OR REPLACE FUNCTION public.fn_instalacao_conferir()
 RETURNS TABLE(chave text, migration text, tipo text, objeto text, presente boolean, detalhe text, porque text, severidade text)
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  r            instalacao_requisito;
  v_ok         boolean;
  v_det        text;
  v_n          bigint;
  v_alvo       regclass;
  v_crit       int;
  v_proc       regproc;
  v_src        text;
  v_tg_enabled "char";
  v_tg_fn      text;
  v_role       text;
  v_privs      text[];
  v_kinds      "char"[];
  v_lista      text;
  v_classe     text;
  v_tabs       text;
  v_funs       text;
begin
  for r in select * from instalacao_requisito order by ordem, chave loop
    v_ok  := false;
    v_det := null;

    if r.tipo = 'tabela' then
      v_ok := to_regclass('public.' || r.objeto) is not null;

    elsif r.tipo = 'funcao' then
      -- `to_regproc` falha quando a função tem sobrecargas ambíguas; o nome sem
      -- argumentos resolve pelo único candidato, e sobrecarga é sinal de que o
      -- requisito devia declarar a assinatura. Nenhum dos requisitos abaixo tem.
      begin
        v_ok := to_regproc('public.' || r.objeto) is not null;
      exception when others then
        -- Ambiguidade significa que EXISTE mais de uma — logo, existe.
        v_ok := true;
        v_det := 'mais de uma assinatura com este nome';
      end;

    elsif r.tipo = 'corpo' then
      -- 0147: o corpo PUBLICADO tem de conter o marcador.
      --
      -- Como todo ramo desta função, ele não pode derrubar a sonda: função
      -- ausente, nome ambíguo e marcador ausente são três respostas diferentes,
      -- e as três são `presente = false` com o detalhe dizendo QUAL — porque
      -- "aplique a migration" e "há duas assinaturas com este nome" pedem ações
      -- diferentes de quem está lendo a tela.
      begin
        v_proc := to_regproc('public.' || r.objeto);
      exception when others then
        v_proc := null;
        v_det  := 'mais de uma assinatura com este nome — o requisito precisa declarar os argumentos';
      end;

      if v_proc is null then
        v_ok  := false;
        v_det := coalesce(v_det, 'a função nem existe');
      else
        v_src := pg_get_functiondef(v_proc::oid);
        v_ok  := v_src is not null and position(r.marcador in v_src) > 0;
        v_det := case when v_ok then 'corpo com o marcador'
                      else 'a função existe, mas o corpo é ANTERIOR a esta migration' end;
      end if;

    elsif r.tipo = 'coluna' then
      -- 0132: `pg_attribute` em vez de `information_schema.columns` — mesma
      -- resposta, 14× mais barato (3,4 ms → 0,25 ms medidos). A view do
      -- information_schema junta várias tabelas de catálogo e filtra por
      -- privilégio linha a linha; aqui a pergunta é "existe esta coluna", e
      -- `attrelid` já vem resolvido por `to_regclass`.
      --
      -- `to_regclass` devolvendo NULL não é erro: significa que a TABELA não
      -- existe, e aí a coluna também não — `attrelid = null` não casa com nada e
      -- o `exists` dá false, que é a resposta certa. É a mesma proteção do ramo
      -- de seed abaixo, obtida de graça pela forma da consulta.
      v_ok := exists (
        select 1 from pg_attribute a
         where a.attrelid  = to_regclass('public.' || split_part(r.objeto, '.', 1))
           and a.attname   = split_part(r.objeto, '.', 2)
           and a.attnum    > 0
           and not a.attisdropped);

    elsif r.tipo = 'policy' then
      -- 0210: policy de RLS é catalogada POR SI (objeto = 'tabela.nome_da_policy'). Nenhum outro tipo a
      -- enxerga: a tabela existe, a função existe, e sem a policy o authenticated leva 42501 ao escrever.
      v_alvo := to_regclass('public.' || split_part(r.objeto, '.', 1));
      if v_alvo is null then
        v_ok  := false;
        v_det := 'a tabela nem existe';
      else
        v_ok := exists (select 1 from pg_policy p
                         where p.polrelid = v_alvo and p.polname = split_part(r.objeto, '.', 2));
        v_det := case when v_ok then 'policy presente'
                      else 'a policy não existe na tabela (RLS ligada sem ela nega a operação ao authenticated)' end;
      end if;

    elsif r.tipo = 'gatilho' then
      -- 0189: gatilho é catalogado POR SI, não pela função que ele chama.
      --
      -- POR QUE ISTO NÃO CABE NO TIPO `funcao`. A função de um gatilho
      -- SOBREVIVE a `drop trigger` e a `alter table ... disable trigger` — o
      -- exemplo já estava no catálogo antes deste tipo existir, em
      -- `gatilho_da_promocao` (0137): a função `fn_trg_auto_promover_dial`
      -- existe e nada garante que algo a chame. `objeto` aqui é
      -- `tabela.nome_do_gatilho`; a tabela é resolvida primeiro, como em todo
      -- ramo desta função — tabela ausente nunca pode virar exceção que
      -- derruba a sonda inteira.
      v_alvo := to_regclass('public.' || split_part(r.objeto, '.', 1));
      if v_alvo is null then
        v_ok  := false;
        v_det := 'a tabela nem existe';
      else
        select tgenabled, tgfoid::regproc::text
          into v_tg_enabled, v_tg_fn
          from pg_trigger
         where tgrelid = v_alvo
           and tgname  = split_part(r.objeto, '.', 2)
           and not tgisinternal;

        if v_tg_enabled is null then
          v_ok  := false;
          v_det := 'o gatilho não existe na tabela (a função dele pode existir — ela sobrevive ao drop trigger)';
        elsif v_tg_enabled = 'D' then
          v_ok  := false;
          v_det := 'o gatilho existe mas está DESABILITADO (disable trigger) — a guarda não roda';
        elsif v_tg_enabled = 'R' then
          -- 'R' = ENABLE REPLICA TRIGGER. Decisão deliberada, e mais estrita
          -- que `<> 'D'`: um gatilho em modo réplica NÃO dispara com
          -- `session_replication_role = origin`, que é o padrão de toda sessão
          -- normal (é o que o pooler do Supabase usa). Do ponto de vista de
          -- quem depende da guarda rodando na sessão normal, um gatilho em
          -- modo réplica está tão desligado quanto um desabilitado — só que
          -- calado, porque `tgenabled <> 'D'` deixaria passar.
          v_ok  := false;
          v_det := 'o gatilho existe mas só dispara em modo réplica — na sessão normal a guarda não roda';
        elsif v_tg_enabled in ('O', 'A') then
          -- 'O' = ENABLE (origin, o padrão) · 'A' = ENABLE ALWAYS (dispara em
          -- origin e em réplica). As duas rodam em sessão normal — é só isso
          -- que este ramo promete. Ele NÃO confere se o gatilho chama a
          -- função certa nem em quais eventos (INSERT/UPDATE/DELETE) — só que
          -- existe e dispara. `v_tg_fn` entra no detalhe por informação, sem
          -- afetar `v_ok`.
          v_ok  := true;
          v_det := format('gatilho habilitado (chama %s)', coalesce(v_tg_fn, '?'));
        else
          -- Não deveria acontecer — `tgenabled` só tem estes quatro valores —
          -- mas a sonda nunca assume "presente" por omissão de um `case`.
          v_ok  := false;
          v_det := format('estado de gatilho desconhecido: %s', v_tg_enabled);
        end if;
      end if;

    elsif r.tipo = 'privilegio' then
      -- 0214: privilégio de TABELA/VIEW/SEQUENCE do schema public para um papel. `objeto` = 'papel:classe' (classe
      -- tabelas | views | sequences) e `marcador` = os privilégios exigidos, separados por vírgula. Varre TODO o
      -- schema, não uma lista: o defeito que isto pega é a tabela NOVA cuja migration esqueceu o GRANT (a partir
      -- de 30/10/2026 o Supabase não concede mais nada por default privilege), e uma lista de nomes seria
      -- exatamente a que ninguém atualiza. Objeto de extensão fica de fora (não é nosso). Revoke intencional
      -- (delete do authenticated em arquivo_oficial etc.) não aparece aqui: só se exige o MÍNIMO por classe.
      v_role  := split_part(r.objeto, ':', 1);
      v_privs := string_to_array(r.marcador, ',');
      v_kinds := case split_part(r.objeto, ':', 2)
                   when 'tabelas'   then array['r', 'p']::"char"[]
                   when 'views'     then array['v', 'm']::"char"[]
                   when 'sequences' then array['S']::"char"[]
                 end;
      if v_kinds is null or v_privs is null then
        v_ok  := false;
        v_det := 'requisito mal declarado: objeto papel:(tabelas|views|sequences) e marcador com os privilégios';
      elsif not exists (select 1 from pg_roles where rolname = v_role) then
        v_ok  := false;
        v_det := format('o papel %s nem existe', v_role);
      else
        select count(*), string_agg(x.relname, ', ' order by x.relname) filter (where x.rn <= 15)
          into v_n, v_lista
          from (select c.relname, row_number() over (order by c.relname) as rn
                  from pg_class c
                  join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'public'
                   and c.relkind = any (v_kinds)
                   and not exists (select 1 from pg_depend d
                                    where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e')
                   and exists (select 1 from unnest(v_privs) p
                                where not case when c.relkind = 'S'
                                         then has_sequence_privilege(v_role, c.oid, p)
                                         else has_table_privilege(v_role, c.oid, p) end)) x;
        v_ok  := v_n = 0;
        v_det := case when v_ok then format('nenhum objeto de public sem %s para %s', r.marcador, v_role)
                      else format('%s objeto(s) de public SEM %s para %s: %s%s', v_n, r.marcador, v_role, v_lista,
                                  case when v_n > 15 then ' ...' else '' end) end;
      end if;

    elsif r.tipo = 'sem_privilegio' then
      -- 0218: o INVERSO do `privilegio`. Aquele exige o MÍNIMO (o buraco é o que falta); este exige a AUSÊNCIA (o buraco é o que sobra).
      -- `objeto` = 'papel:classe' (classe tabelas | views | sequences | funcoes) e `marcador` = os privilégios que o papel NÃO pode ter.
      -- Varre TODO o schema public, não uma lista: o defeito é o objeto NOVO que nasce com privilégio (o default privilege antigo do
      -- Supabase dava tudo a `anon`; função nova nasce com EXECUTE para PUBLIC, e `anon` herda de PUBLIC — por isso `has_*_privilege`,
      -- que enxerga a herança, e não a leitura da ACL). Privilégio de COLUNA conta (`has_any_column_privilege`): um `grant select (id)`
      -- não aparece em `has_table_privilege`. Fora da varredura: objeto de extensão e objeto cujo dono não é `postgres` (o REVOKE de quem não é dono só avisa: o requisito nasceria ausente por um motivo que a migration não corrige; ex.: unaccent, do supabase_admin), e função `teste_*`, que só existe no
      -- harness local (a suíte as cria em public e não as apaga; em produção nenhuma função tem este prefixo).
      v_role   := split_part(r.objeto, ':', 1);
      v_privs  := string_to_array(r.marcador, ',');
      v_classe := split_part(r.objeto, ':', 2);
      if v_classe not in ('tabelas', 'views', 'sequences', 'funcoes') or v_privs is null then
        v_ok  := false;
        v_det := 'requisito mal declarado: objeto papel:(tabelas|views|sequences|funcoes) e marcador com os privilégios proibidos';
      elsif not exists (select 1 from pg_roles where rolname = v_role) then
        v_ok  := true;
        v_det := format('o papel %s nem existe: não há privilégio a vazar', v_role);
      else
        if v_classe = 'funcoes' then
          select count(*), string_agg(x.nome, ', ' order by x.nome) filter (where x.rn <= 15)
            into v_n, v_lista
            from (select p.oid::regprocedure::text as nome, row_number() over (order by p.oid::regprocedure::text) as rn
                    from pg_proc p
                    join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'public'
                     and p.proname not like 'teste\_%'
                     and p.proowner = (select oid from pg_roles where rolname = 'postgres')
                     -- 0219: função que RETORNA event_trigger não é chamável (nem por SQL nem por RPC: "trigger functions can only be called as triggers"),
                     -- logo o EXECUTE de PUBLIC nela não é superfície. É a função do event trigger da PLATAFORMA Supabase (`rls_auto_enable`, dona postgres,
                     -- SECURITY DEFINER, que NÃO está neste repositório): o laço da 0218 lhe tirou o PUBLIC e a 0219 o devolveu, e a sonda não pode acusar a correção.
                     -- Só event_trigger: função de GATILHO comum (`trigger`) continua na varredura, porque o projeto já faz `revoke ... from public` em todas.
                     and p.prorettype <> 'event_trigger'::regtype
                     and not exists (select 1 from pg_depend d
                                      where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
                     and exists (select 1 from unnest(v_privs) q where has_function_privilege(v_role, p.oid, q))) x;
        else
          select count(*), string_agg(x.relname, ', ' order by x.relname) filter (where x.rn <= 15)
            into v_n, v_lista
            from (select c.relname, row_number() over (order by c.relname) as rn
                    from pg_class c
                    join pg_namespace n on n.oid = c.relnamespace
                   where n.nspname = 'public'
                     and c.relkind = any (case v_classe when 'tabelas'   then array['r', 'p']::"char"[]
                                                        when 'views'     then array['v', 'm']::"char"[]
                                                        else array['S']::"char"[] end)
                     and c.relowner = (select oid from pg_roles where rolname = 'postgres')
                     and not exists (select 1 from pg_depend d
                                      where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e')
                     and exists (select 1 from unnest(v_privs) q
                                  where case when c.relkind = 'S'
                                             then has_sequence_privilege(v_role, c.oid, q)
                                             when lower(q) in ('select', 'insert', 'update', 'references')
                                             then has_any_column_privilege(v_role, c.oid, q)
                                             else has_table_privilege(v_role, c.oid, q) end)) x;
        end if;
        v_ok  := v_n = 0;
        v_det := case when v_ok then format('nenhum objeto (%s) de public com privilégio para %s', v_classe, v_role)
                      else format('%s objeto(s) (%s) de public COM privilégio para %s: %s%s', v_n, v_classe, v_role, v_lista,
                                  case when v_n > 15 then ' ...' else '' end) end;
      end if;

    elsif r.tipo = 'segredo' then
      -- 0217: segredo do Vault do Supabase (objeto = o NOME do segredo; o valor nunca é lido aqui). A sonda roda como o
      -- chamador (o portal é `authenticated`, que não lê o Vault), então a pergunta "existe e não está vazio?" passa por
      -- uma função SECURITY DEFINER que só devolve boolean. Falha ao perguntar (Vault ausente, sem permissão) é
      -- `presente = false` com o motivo, nunca uma exceção que derrube a sonda inteira.
      begin
        v_ok  := coalesce(fn_segredo_do_vault_presente(r.objeto), false);
        v_det := case when v_ok then 'segredo presente no Vault (valor não lido)'
                      else 'o Vault não tem este segredo, ou ele está vazio' end;
      exception when others then
        v_ok  := false;
        v_det := 'não foi possível consultar o Vault: ' || sqlerrm;
      end;

    elsif r.tipo = 'definer_sem_escrita' then
      -- 0219: a guarda de Sócio (fn_trg_so_socio) deixa passar quem roda como DONO (current_user fora de authenticated/anon). Função SECURITY DEFINER roda como
      -- dono: uma definer executável por `authenticated` que escreva numa tabela protegida pela guarda — direto, ou chamando a função que a escreve — passaria
      -- pela guarda sem o chamador ser Sócio. `objeto` = as tabelas protegidas (separadas por vírgula) e `marcador` = as funções cuja chamada também conta.
      -- Entra na varredura: SECURITY DEFINER em public E (EXECUTE para authenticated OU função de gatilho, que dispara no DML de quem escreve sem precisar de
      -- EXECUTE) E corpo com `insert into | update | delete from | truncate | merge into <tabela>` ou `<função>(`. NÃO enxerga: SQL dinâmico (`execute format(...)`),
      -- nem o helper definer chamado por uma definer, nem uma definer FECHADA ao authenticated (fn_dial_auto_promover é assim, de propósito: só o gatilho e o
      -- service_role a chamam). Falso positivo possível (a frase `update estagio_autonomia` num comentário da função): é o erro do lado seguro, e some com
      -- `revoke all on function f(args) from public` se a função não deve ser executável, ou com a linha reescrita.
      v_tabs := array_to_string(string_to_array(r.objeto, ','), '|');
      v_funs := array_to_string(string_to_array(r.marcador, ','), '|');
      if coalesce(v_tabs, '') = '' or coalesce(v_funs, '') = '' then
        v_ok  := false;
        v_det := 'requisito mal declarado: objeto = tabelas protegidas e marcador = funções que as escrevem, cada lista separada por vírgula';
      else
        select count(*), string_agg(x.nome, ', ' order by x.nome) filter (where x.rn <= 15)
          into v_n, v_lista
          from (select p.oid::regprocedure::text as nome, row_number() over (order by p.oid::regprocedure::text) as rn
                  from pg_proc p
                  join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public'
                   and p.prosecdef
                   and (p.prorettype = 'trigger'::regtype or has_function_privilege('authenticated', p.oid, 'execute'))
                   and (p.prosrc ~* ('(insert\s+into|update|delete\s+from|truncate(\s+table)?|merge\s+into)\s+(only\s+)?(public\.)?"?(' || v_tabs || ')"?(\s|;|$|\()')
                        or p.prosrc ~* ('(^|[^a-z0-9_])(' || v_funs || ')\s*\('))) x;
        v_ok  := v_n = 0;
        v_det := case when v_ok then format('nenhuma função SECURITY DEFINER executável por authenticated (ou de gatilho) escreve em %s nem chama %s', r.objeto, r.marcador)
                      else format('%s função(ões) SECURITY DEFINER que authenticated executa (ou de gatilho) escrevem em %s ou chamam %s — a guarda de Sócio as deixa passar, porque rodam como dono: %s%s',
                                  v_n, r.objeto, r.marcador, v_lista, case when v_n > 15 then ' ...' else '' end) end;
      end if;

    elsif r.tipo in ('seed', 'comportamento') then
      -- A tabela pode não existir ainda: contar nela levantaria erro e derrubaria
      -- a sonda inteira, transformando "um requisito faltando" em "o painel não
      -- abre". A sonda de instalação é o último lugar do sistema que pode falhar
      -- por causa do que ela existe para medir.
      v_alvo := to_regclass('public.' || r.objeto);
      if v_alvo is null then
        v_ok  := false;
        v_det := 'a tabela nem existe';
      else
        -- 0132: CONTAGEM LIMITADA AO CRITÉRIO. Ver o cabeçalho: a pergunta é
        -- ">= criterio", e varrer a tabela inteira para respondê-la faz o custo
        -- do painel crescer junto com `lote_execucao`, que cresce para sempre.
        v_crit := greatest(coalesce(r.criterio_seed, 1), 1);
        execute format('select count(*) from (select 1 from public.%I limit %s) x',
                       r.objeto, v_crit)
           into v_n;
        v_ok := v_n >= v_crit;
        -- No caso PRESENTE o total exato não é conhecido (nem usado pela tela).
        -- No caso AUSENTE ele é exato por construção — a varredura parou antes do
        -- limite, logo passou por tudo — e é nele que o número informa algo:
        -- "3 linha(s)" com critério 8 diz que o seed rodou pela metade.
        v_det := case when v_ok then format('%s linha(s) ou mais', v_crit)
                      else format('%s linha(s)', v_n) end;
      end if;
    end if;

    return query select r.chave, r.migration, r.tipo, r.objeto, v_ok, v_det,
                        r.porque, r.severidade;
  end loop;
end;
$function$;

comment on function fn_instalacao_conferir() is
  'Confere cada requisito de instalacao_requisito contra o catálogo do banco. Sobrevive ao objeto ausente (to_regclass/to_regproc devolvem NULL em vez de erro): a sonda não pode falhar por causa do que ela existe para medir. Desde a 0147 confere também o CORPO da função (tipo=corpo), que é o único jeito de distinguir uma correção aplicada de uma função homônima com o corpo velho. Desde a 0189 confere também GATILHO (tipo=gatilho): existência na tabela E tgenabled em (''O'',''A'') — a função do gatilho sobrevive a drop trigger/disable trigger e por isso NUNCA prova, sozinha, que a guarda está ligada. Desde a 0210 confere também POLICY (tipo=policy, objeto tabela.nome_da_policy): existência em pg_policy. Desde a 0214 confere PRIVILÉGIO (tipo=privilegio, objeto papel:classe, marcador = privilégios): toda tabela/view/sequence de public sem o mínimo para authenticated e service_role é buraco — o Supabase deixou de conceder por default privilege em 30/10/2026. Desde a 0217 confere SEGREDO do Vault (tipo=segredo, objeto = nome do segredo): existe e não está vazio, sem ler o valor. Desde a 0218 confere também a AUSÊNCIA de privilégio (tipo=sem_privilegio, objeto papel:classe com classe tabelas|views|sequences|funcoes, marcador = privilégios proibidos): todo objeto de public com privilégio para anon é buraco (função herda EXECUTE de PUBLIC; privilégio de coluna conta; função de extensão e teste_* ficam de fora). Desde a 0219 confere DEFINER QUE ESCREVE NO DIAL (tipo=definer_sem_escrita, objeto = tabelas protegidas, marcador = funções cuja chamada conta): função SECURITY DEFINER executável por authenticated (ou de gatilho) que escreve nelas passa pela guarda de Sócio, que confia em quem roda como dono. E o ramo sem_privilegio ignora função que retorna event_trigger (a da plataforma Supabase, não chamável).';

-- O requisito da guarda trocou de nome e de marcador (o `tdf.promocao_automatica` não existe mais no corpo): sai o antigo, entra o novo.
delete from instalacao_requisito where chave = 'dial_guarda_de_socio_tem_a_promocao';

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('dial_guarda_de_socio_confia_no_dono', '0219', 'corpo', 'fn_trg_so_socio', 'current_user not in (''authenticated'', ''anon'')', null,
   'A guarda de Sócio do dial e do catálogo de premissas deixa passar quem roda como DONO (a promoção automática, que é definer, e a conexão de serviço). Sem a linha, a 0218 (GUC e formato do UPDATE) voltou, e mudar fn_mudar_dial quebra a promoção calado; sem a exceção, o dial nunca sobe por decisão de Analista. O marcador é a condição da guarda.',
   'bloqueante', 988),
  ('dial_promocao_independe_do_leitor', '0219', 'corpo', 'fn_dial_auto_promover',
   E' SECURITY DEFINER\n SET search_path TO ''public'', ''pg_temp''', null,
   'Sem SECURITY DEFINER a promoção automática roda com o papel de quem decidiu: Analista dispara, a guarda de Sócio recusa, o gatilho engole o erro e o dial nunca sobe por decisão dele — calado. O marcador são as linhas SECURITY DEFINER e SET search_path que o pg_get_functiondef escreve (a 0219 tirou a GUC, que era a linha de código própria da 0218).',
   'bloqueante', 986),
  ('dial_gatilho_independe_do_leitor', '0219', 'corpo', 'fn_trg_auto_promover_dial',
   E' SECURITY DEFINER\n SET search_path TO ''public'', ''pg_temp''', null,
   'O gatilho da promoção precisa rodar como dono para chamar fn_dial_auto_promover (fechada ao authenticated) e para a guarda de Sócio o deixar passar. O marcador são as linhas SECURITY DEFINER e SET search_path que o pg_get_functiondef escreve.',
   'bloqueante', 987),
  ('definer_nao_escreve_no_dial', '0219', 'definer_sem_escrita', 'estagio_autonomia,premissa_catalogo', 'fn_mudar_dial', null,
   'A guarda de Sócio do dial e do catálogo de premissas confia em quem roda como dono. Uma função SECURITY DEFINER executável por authenticated (ou de gatilho) que escreva nessas tabelas, direto ou chamando fn_mudar_dial, passa pela guarda sem o chamador ser Sócio: o Analista mudaria o dial. Se reprova: faça a função INVOKER, ou `revoke all on function f(args) from public;` se ela não deve ser chamada pelo portal, ou leve a escrita para fn_mudar_dial (INVOKER) chamada por um Sócio.',
   'bloqueante', 993),
  ('anon_sem_funcoes', '0218', 'sem_privilegio', 'anon:funcoes', 'execute', null,
   'Função de public executável por `anon` (direto ou herdado de PUBLIC): quem chega ao PostgREST sem login pode chamar a RPC. fn_definir_papel, fn_alocar e fn_acesso_bootstrap só estão a salvo da escalada por causa da guarda dentro do corpo. A migration que cria função faz `revoke all on function <f>(<args>) from public;` e concede a authenticated/service_role o que o portal usa (Supabase/README.md). Função `teste_*`, de extensão e a que RETORNA event_trigger (a da plataforma Supabase, `rls_auto_enable`: não é chamável por SQL nem por RPC) não contam.',
   'bloqueante', 983)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0219', revisado_em = current_date,
       observacao = 'A 0219 troca a guarda de Sócio do dial (GUC + formato do UPDATE) pela regra única "quem roda como dono é confiável", reemite a promoção automática sem a marca, devolve o PUBLIC a rls_auto_enable (função de event trigger da plataforma, se existir) e acrescenta à sonda o tipo definer_sem_escrita (definer_nao_escreve_no_dial, bloqueante: a regra nova abre o risco de uma definer burlar a guarda), o filtro de event_trigger no anon_sem_funcoes e os marcadores novos dos três requisitos do dial que dependiam da GUC.'
 where id = true;
