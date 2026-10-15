-- =============================================================================
-- 0210 — A ESCRITA DA F1 QUE SÓ O SUPERUSUÁRIO FAZIA: policies de escrita para o `authenticated`
-- (F1, depois da 0209. Só ACRESCENTA policies e um revoke; nenhuma função é reemitida, sem backfill.)
--
-- O DEFEITO, medido pela sessão principal em 15/10/2026 (banco local, `set local role authenticated`,
-- transação desfeita): fn_perimetro_definir_escopo (0180/0209) morria com 42501 "new row violates row-level
-- security policy for table perimetro", e fn_controlador_registrar (0182) idem para `controlador`;
-- fn_entidade_definir_papel_no_grupo e fn_aprovar_caso (controle positivo) passavam. A CAUSA: as funções são
-- security INVOKER (o padrão do repositório: só UMA função security definer em todo o schema) e as três tabelas
-- que a F1 criou (perimetro 0180, controlador e entidade_controlador 0182) nasceram com RLS ligada e SÓ a
-- policy `*_read` (select). Os testes rodam como superusuário, que ignora a RLS, e por isso 0180, 0182 e 0209
-- passaram em toda suíte: a tela nasceria quebrada (regra 7: escrita que só existe para quem não precisa de RLS).
-- evento_auditoria NÃO era problema: tem `evento_auditoria_insert` (with check true) desde antes.
--
-- A SAÍDA, e por que esta: o padrão da casa para tabela escrita pelo portal é policy `with check (true)` por
-- operação (`golden_rodada_insert/_update`, `caso_pergunta_insert`, `campo_classe_override_insert`) ou
-- `*_authenticated_all` (`entidade`, `caso`, `pendencia`, `arquivo_oficial*`) — a casa não usa security definer
-- nem policy por dono, porque todo authenticated é analista da Oria (decisão registrada desde a 0011). Então:
--   * perimetro:            INSERT + UPDATE (definir abre intervalo e fecha o anterior; encerrar fecha)
--   * controlador:          INSERT (fn_controlador_registrar só insere)
--   * entidade_controlador: INSERT + UPDATE (fn_entidade_definir_controlador é upsert; a fusão de entidades
--                           (0153/0183) move o vínculo com UPDATE)
--   * SEM DELETE nas três, e `revoke delete ... from authenticated` nas três (o mesmo que a 0206 faz em
--     arquivo_oficial): sem policy de delete a RLS só devolveria "0 linhas apagadas" calada, e com o revoke é
--     `permission denied`, que o analista e o teste enxergam. O histórico do perímetro e o quadro de
--     controladores não se apagam pelo portal; encerrar é fechar `ate`, e apagar é SQL direto com a trilha na mão.
--     O `on delete cascade` das FKs (apagar a entidade na fusão) NÃO passa por este privilégio: o Postgres o
--     executa com o dono da tabela, e o teste prova isso (a fusão como authenticated).
--
-- O QUE FICA ABERTO, dito em vez de escondido:
--   * Escrita DIRETA (por fora das funções) também passa: INSERT/UPDATE com `with check (true)` valem para quem
--     chama a função e para quem escreve a tabela na mão. Restringir só às funções exigiria security definer,
--     que a casa não usa. O teto é "o analista da Oria é confiável"; a trilha (evento_auditoria) só cobre a
--     escrita pelas funções. Um UPDATE direto em perimetro pode reescrever desde/ate sem evento.
--   * A fusão (fn_fundir_entidade) apaga a entidade absorvida e o `on delete cascade` de perimetro leva os
--     escopos dela embora (perimetro_entidade_id_fkey): a sobrevivente fica com o escopo que já tinha, e o da
--     absorvida some sem evento. Não tocado aqui (não é permissão); a tela deve avisar antes de fundir.
--
-- NÃO HÁ BACKFILL.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/f1_escrita_authenticated.test.sql — 20 asserts, medidos em 15/10/2026
-- com o assert em `raise warning` (voltou para `raise exception`), cada guarda desligada UMA por vez numa passada
-- da 0210 reaplicada intacta e depois mutada (controle intacto: 20 ok, 0 falhou). Reprovam: sem perimetro_insert 6
-- (e o teste aborta no bloco da sonda), sem perimetro_update 4, sem controlador_insert 5, sem
-- entidade_controlador_insert 4, sem entidade_controlador_update 3, `grant delete` devolvido em cada uma das três
-- tabelas 1, ramo `policy` da sonda sempre presente 1. Com TODAS as policies removidas e os três delete devolvidos
-- (o estado anterior à 0210), 14 dos 20 asserts reprovam e o teste aborta no bloco da sonda; só os três de
-- entidade (papel, forma e participação, que passavam pela policy `entidade_authenticated_all`) e a fusão
-- continuam verdes. O ANTES por função, como authenticated: fn_entidade_definir_papel_no_grupo OK,
-- fn_entidade_definir_forma_de_controle OK, fn_entidade_definir_participacao OK, fn_fundir_entidade sem erro mas
-- PERDENDO o vínculo de controle da absorvida (o UPDATE sem policy afeta 0 linhas calado e a cascata apaga o
-- vínculo), fn_perimetro_definir_escopo 42501, fn_controlador_registrar 42501, e falham em cascata (sem
-- intervalo, sem controlador): fn_perimetro_encerrar_escopo, fn_entidade_definir_controlador e a forma
-- controle_comum.
-- DEPOIS, todas gravam. O delete direto, no ANTES, não dava erro: a RLS sem policy de delete apaga 0 linhas em
-- silêncio, e é por isso que o revoke vale (42501 audível).
-- =============================================================================

drop policy if exists perimetro_insert on perimetro;
create policy perimetro_insert on perimetro for insert to authenticated with check (true);
drop policy if exists perimetro_update on perimetro;
create policy perimetro_update on perimetro for update to authenticated using (true) with check (true);

drop policy if exists controlador_insert on controlador;
create policy controlador_insert on controlador for insert to authenticated with check (true);

drop policy if exists entidade_controlador_insert on entidade_controlador;
create policy entidade_controlador_insert on entidade_controlador for insert to authenticated with check (true);
drop policy if exists entidade_controlador_update on entidade_controlador;
create policy entidade_controlador_update on entidade_controlador for update to authenticated using (true) with check (true);

-- (Em produção o default privilege do Supabase concede delete; este revoke vem depois dele.)
revoke delete on perimetro from authenticated;
revoke delete on controlador from authenticated;
revoke delete on entidade_controlador from authenticated;

comment on policy perimetro_insert on perimetro is
  '0210: o authenticated abre intervalos de perímetro (fn_perimetro_definir_escopo é security invoker). Sem policy de delete e com revoke: o histórico não se apaga pelo portal.';
comment on policy entidade_controlador_update on entidade_controlador is
  '0210: fn_entidade_definir_controlador (upsert) e a fusão de entidades movem o vínculo com UPDATE. Sem delete: ver o cabeçalho.';

-- -----------------------------------------------------------------------------
-- A SONDA PASSA A VER POLICY. O catálogo da 0131–0189 (tabela, coluna, função, corpo, gatilho, seed) não
-- tem como dizer "a policy de escrita existe": a 0180 e a 0182 estavam todas `presente` na sonda e a escrita
-- do portal morria em 42501. Tipo novo `policy`, objeto `tabela.nome_da_policy`; a função abaixo é a 0189
-- INTEIRA (dump de pg_get_functiondef do banco montado das migrations, não replace de texto) com UM ramo novo.
-- -----------------------------------------------------------------------------
alter table instalacao_requisito drop constraint if exists instalacao_requisito_tipo_check;
alter table instalacao_requisito add constraint instalacao_requisito_tipo_check
  check (tipo in ('tabela', 'coluna', 'funcao', 'seed', 'comportamento', 'corpo', 'gatilho', 'policy'));

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
  'Confere cada requisito de instalacao_requisito contra o catálogo do banco. Sobrevive ao objeto ausente (to_regclass/to_regproc devolvem NULL em vez de erro): a sonda não pode falhar por causa do que ela existe para medir. Desde a 0147 confere também o CORPO da função (tipo=corpo), que é o único jeito de distinguir uma correção aplicada de uma função homônima com o corpo velho. Desde a 0189 confere também GATILHO (tipo=gatilho): existência na tabela E tgenabled em (''O'',''A'') — a função do gatilho sobrevive a drop trigger/disable trigger e por isso NUNCA prova, sozinha, que a guarda está ligada. Desde a 0210 confere também POLICY (tipo=policy, objeto tabela.nome_da_policy): existência em pg_policy.';

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('perimetro_insert_policy', '0210', 'policy', 'perimetro.perimetro_insert', null, null,
   'Sem ela o authenticated não abre intervalo de perímetro (42501): fn_perimetro_definir_escopo só funciona para o superusuário dos testes e a tela nasce quebrada.',
   'importante', 896),
  ('controlador_insert_policy', '0210', 'policy', 'controlador.controlador_insert', null, null,
   'Sem ela o authenticated não registra controlador (42501): fn_controlador_registrar só funciona para o superusuário.',
   'importante', 897),
  ('entidade_controlador_insert_policy', '0210', 'policy', 'entidade_controlador.entidade_controlador_insert', null, null,
   'Sem ela o authenticated não vincula entidade a controlador (42501): fn_entidade_definir_controlador só funciona para o superusuário.',
   'importante', 898)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0210', revisado_em = current_date,
       observacao = 'A 0210 dá ao authenticated INSERT/UPDATE (sem DELETE) em perimetro, controlador e entidade_controlador, que a F1 criou só com policy de leitura. Policies, sem função nova nem backfill.'
 where id = true;
