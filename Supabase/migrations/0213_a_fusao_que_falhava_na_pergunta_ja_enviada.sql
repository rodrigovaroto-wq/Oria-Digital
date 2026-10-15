-- =============================================================================
-- 0213 — A FUSÃO NÃO FALHA MAIS POR `caso_pergunta`, E A PERGUNTA JÁ ENVIADA ACOMPANHA A SOBREVIVENTE
-- (F1, depois da 0212. Reemite fn_fundir_entidade INTEIRA a partir do corpo da 0211 (dump do banco montado das
--  migrations, com os acréscimos marcados "0213") e dá ao authenticated a escrita MÍNIMA em caso_pergunta.)
--
-- O DEFEITO, listado na 0211: `caso_pergunta.entidade_id` é FK NO ACTION, e a tabela é append-only (só SELECT e
-- INSERT para o authenticated). Uma entidade citada num registro de pergunta enviada ou descartada fazia
-- `fn_fundir_entidade` FALHAR alto na FK (23503), e a tela de perímetro manda fundir as fantasmas.
--
-- A DECISÃO DO DONO: "se for como sugestão, não; se for sobre já ter acontecido, sim". A SUGESTÃO é calculada ao
-- vivo por fn_sugerir_perguntas (0120/0187) e nunca é gravada, então não há o que carregar. As LINHAS de
-- caso_pergunta são ação humana que JÁ ACONTECEU (enviada, descartada) e passam para a sobrevivente. Isso é o que
-- faz `ja_enviada` valer para ela: a pergunta enviada sobre a absorvida não volta a ser sugerida como pendente.
-- O evento `entidade_fundida` lista o que foi repontado (caso_pergunta_id, codigo, acao, criado_em) em
-- depois->perguntas_repontadas, e o retorno traz a contagem.
--
-- A ESCRITA MÍNIMA, e por que esta saída. A tabela é append-only de verdade desde a 0120 (policies só de select e
-- insert): o texto do que foi perguntado ao cliente é fato histórico. Para repontar só é preciso mudar UMA coluna.
--   * GRANT UPDATE (entidade_id) ao authenticated, no lugar do UPDATE da tabela inteira: o Postgres recusa com
--     42501 qualquer UPDATE que toque texto_enviado, acao, autor, criado_em, pergunta_codigo, caso_id ou id,
--     por privilégio de coluna, antes mesmo da RLS.
--   * Policy de UPDATE com `with check` restrito: a nova entidade tem de existir e ser do MESMO caso da pergunta.
--   * Gatilho BEFORE UPDATE: só repontar de uma entidade para outra (nunca de ou para nulo) e nada além de
--     entidade_id muda (cobre quem entra por fora do privilégio de coluna). AFTER UPDATE grava
--     `caso_pergunta_reapontada` em evento_auditoria, para o reponte direto também deixar rastro.
--   * `revoke delete` (padrão da 0206/0210): sem policy de delete a RLS só apagaria 0 linhas, calada; o revoke
--     faz o delete direto dar 42501.
--   O que NÃO fica fechado, dito: um analista ainda pode repontar direto uma pergunta para OUTRA entidade do mesmo
--   caso (a policy não sabe se há fusão em curso, e a casa não usa security definer). Fica com rastro (o evento do
--   gatilho), não impedido. Escolhi isto a uma função security definer porque a casa não usa nenhuma.
--
-- NÃO HÁ BACKFILL: nenhuma linha muda ao aplicar. MEDIÇÃO NÃO-VAZIA (regra 2):
-- Supabase/test/fusao_pergunta.test.sql — 23 asserts, medidos em 15/10/2026 com o assert em `raise warning` (voltou
-- para `raise exception`), cada guarda desligada UMA por vez na função/gatilho/policy reaplicada e restaurada, e
-- conferido que a mutação APLICOU (controle intacto: 23 ok, 0 falhou). Com o corpo da 0211 e sem a escrita em
-- caso_pergunta (o estado anterior), 11 dos 23 asserts reprovam. Por guarda: não repontar as perguntas 8, evento sem
-- a lista 1, retorno sem a contagem 1, gatilho sem a trava de colunas 2, gatilho sem a trava de "de/para nulo" 1,
-- gatilho do evento de reponte 1, UPDATE da tabela inteira devolvido 3, policy sem o check de mesmo caso 2, delete
-- devolvido 1, e sem a policy de update 12 dos 23 (a fusão como authenticated volta a falhar). O assert "nem o dono
-- da tabela reescreve o texto" foi acrescentado depois da primeira medição porque a trava de colunas do gatilho
-- reprovava 0 asserts (o privilégio de coluna já a cobria para o authenticated): agora reprova 2 dos 23.
-- =============================================================================

revoke update on caso_pergunta from authenticated;
grant update (entidade_id) on caso_pergunta to authenticated;
revoke delete on caso_pergunta from authenticated;

drop policy if exists caso_pergunta_reapontar on caso_pergunta;
create policy caso_pergunta_reapontar on caso_pergunta for update to authenticated
  using (true)
  with check (entidade_id is not null
              and exists (select 1 from entidade e
                           where e.id = caso_pergunta.entidade_id and e.caso_id = caso_pergunta.caso_id));

comment on policy caso_pergunta_reapontar on caso_pergunta is
  '0213: o authenticated só pode repontar a pergunta para uma entidade do MESMO caso (e o privilégio de coluna só deixa mexer em entidade_id). É o que a fusão de entidades faz com a ação já tomada.';

create function public.fn_trg_caso_pergunta_so_reaponta() returns trigger
    language plpgsql
    as $$
begin
  if tg_when = 'BEFORE' then
    if (new.id, new.caso_id, new.pergunta_codigo, new.acao, new.texto_enviado, new.autor, new.criado_em)
       is distinct from
       (old.id, old.caso_id, old.pergunta_codigo, old.acao, old.texto_enviado, old.autor, old.criado_em) then
      raise exception 'caso_pergunta é append-only: só entidade_id pode mudar, e só numa fusão de entidades. O que foi perguntado ao cliente não se reescreve.';
    end if;
    if old.entidade_id is null or new.entidade_id is null then
      raise exception 'a pergunta % não pode ser repontada de ou para "nenhuma entidade": o reponte é de uma entidade para outra (fusão)', old.id;
    end if;
    return new;
  end if;
  -- AFTER UPDATE: o rastro
  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values ('banco:' || session_user, 'caso_pergunta_reapontada', 'caso:' || new.caso_id,
          jsonb_build_object('caso_pergunta_id', new.id, 'pergunta_codigo', new.pergunta_codigo,
                             'acao', new.acao, 'de', old.entidade_id, 'para', new.entidade_id));
  return new;
end;
$$;

comment on function public.fn_trg_caso_pergunta_so_reaponta() is
  '0213: a guarda de caso_pergunta (append-only): só entidade_id muda, nunca de ou para nulo, e cada reponte deixa o evento caso_pergunta_reapontada.';


create trigger trg_caso_pergunta_so_reaponta
  before update on caso_pergunta
  for each row execute function public.fn_trg_caso_pergunta_so_reaponta();
create trigger trg_caso_pergunta_reaponta_evento
  after update on caso_pergunta
  for each row when (old.entidade_id is distinct from new.entidade_id)
  execute function public.fn_trg_caso_pergunta_so_reaponta();

comment on table caso_pergunta is
  'Ação HUMANA sobre uma pergunta sugerida: enviada (com o texto renderizado congelado) ou descartada. O sistema sugere, o humano decide (Arquitetura do Sistema/1 Visão e Doutrina/01); nenhum envio é automático. Append-only: o authenticated só lê e insere, e desde a 0213 só pode repontar entidade_id (fusão de entidades), nada mais. A SUGESTÃO nunca é gravada aqui; só a ação que já aconteceu.';

create or replace function public.fn_fundir_entidade(p_caso_id uuid, p_de_id uuid, p_para_id uuid, p_por text DEFAULT 'sistema:fusao'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_de    text;
  v_para  text;
  v_docs  int;
  -- 0183
  v_forma_de         entidade_forma_de_controle;
  v_vinculos_de      jsonb;
  v_vinculos_movidos int := 0;
  v_descartados      jsonb := '[]'::jsonb;
  -- 0211
  v_papel_de         entidade_papel_no_grupo;
  v_controladora_de  uuid;
  v_pct_de           numeric;
  r                  record;
  v_s                record;
  v_perim_movidos    int := 0;
  v_perim_descartado jsonb := '[]'::jsonb;
  v_controladas      jsonb;
  v_n_controladas    int := 0;
  -- 0213
  v_perguntas        jsonb;
  v_n_perguntas      int := 0;
begin
  if p_de_id = p_para_id then
    raise exception 'fundir uma entidade nela mesma não faz sentido (%)', p_de_id;
  end if;

  select razao_social into v_de   from entidade where id = p_de_id   and caso_id = p_caso_id;
  select razao_social into v_para from entidade where id = p_para_id and caso_id = p_caso_id;
  if v_de is null or v_para is null then
    raise exception 'entidade não encontrada neste mandato (de=%, para=%)', p_de_id, p_para_id;
  end if;

  -- 0211: a sobrevivente controlada pela absorvida vira controlada por si mesma. Isso não tem leitura
  -- automática (a forma declarada deixa de fazer sentido), então recusa em vez de adivinhar. Antes da 0211
  -- era a FK entidade_controladora_id_fkey que recusava, com uma mensagem do Postgres.
  if exists (select 1 from entidade where id = p_para_id and controladora_id = p_de_id) then
    raise exception 'a entidade "%" é controlada por "%", que está sendo fundida nela: a participação passaria a ser dela com ela mesma. Remova a participação (fn_entidade_definir_participacao) e a forma de controle e refaça a fusão.', v_para, v_de;
  end if;

  update documento set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;
  get diagnostics v_docs = row_count;

  -- Tudo o que aponta para a entidade acompanha o documento. `checklist_item_status`
  -- e `pendencia` guardam entidade_id por conta própria, e deixá-los para trás
  -- faria o Portão 1 continuar cobrando de uma empresa que não existe mais.
  update checklist_item_status set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;
  update pendencia set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;
  update reconciliacao set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;

  -- 0183: o controle declarado de A. Sem isto, o `on delete cascade` de entidade_controlador o
  -- apagava junto com a linha (ver o item (10) da migration 0183).
  select forma_de_controle, papel_no_grupo, controladora_id, percentual_participacao
    into v_forma_de, v_papel_de, v_controladora_de, v_pct_de
    from entidade where id = p_de_id;
  select coalesce(jsonb_agg(jsonb_build_object('controlador_id', ec.controlador_id,
                                               'controlador', k.nome,
                                               'percentual', ec.percentual)
                            order by k.nome), '[]'::jsonb)
    into v_vinculos_de
    from entidade_controlador ec join controlador k on k.id = ec.controlador_id
   where ec.entidade_id = p_de_id;

  if not exists (select 1 from entidade_controlador where entidade_id = p_para_id) then
    update entidade_controlador set entidade_id = p_para_id where entidade_id = p_de_id;
    get diagnostics v_vinculos_movidos = row_count;
  else
    v_descartados := v_vinculos_de;
  end if;

  -- 0211: o perímetro da absorvida. `perimetro_entidade_id_fkey` é ON DELETE CASCADE: sem isto o
  -- `delete from entidade` abaixo levava os escopos dela embora, sem evento. REGRA: cada intervalo da
  -- absorvida passa para a sobrevivente, EXCETO o que se sobrepõe a um intervalo do MESMO escopo que ela já
  -- tem (inclusive o vigente, que a unicidade perimetro_atual_unico de qualquer jeito não deixaria
  -- duplicar). O que sobrepõe NÃO é fundido em um intervalo maior: isso inventaria um início que ninguém
  -- declarou. Fica o da sobrevivente, o da absorvida vai para o evento (perimetro_descartado), com o
  -- intervalo da sobrevivente que o cobriu, e o analista reabre o escopo com fn_perimetro_definir_escopo se
  -- a data certa for outra.
  for r in select id, escopo, desde, ate from perimetro
            where caso_id = p_caso_id and entidade_id = p_de_id order by escopo, desde loop
    select s.desde, s.ate into v_s from perimetro s
     where s.caso_id = p_caso_id and s.entidade_id = p_para_id and s.escopo = r.escopo
       and r.desde <= coalesce(s.ate, 'infinity'::date)
       and coalesce(r.ate, 'infinity'::date) >= s.desde
     limit 1;
    if found then
      v_perim_descartado := v_perim_descartado || jsonb_build_array(jsonb_build_object(
        'escopo', r.escopo, 'desde', r.desde, 'ate', r.ate,
        'motivo', 'sobrepõe um intervalo do mesmo escopo que a sobrevivente já tinha',
        'sobrevivente_desde', v_s.desde, 'sobrevivente_ate', v_s.ate));
    else
      update perimetro set entidade_id = p_para_id where id = r.id;
      v_perim_movidos := v_perim_movidos + 1;
    end if;
  end loop;

  -- 0211: quem era controlada pela absorvida passa a ser controlada pela sobrevivente (a FK
  -- entidade_controladora_id_fkey recusava a fusão inteira com uma mensagem do Postgres).
  select coalesce(jsonb_agg(jsonb_build_object('entidade_id', e.id, 'razao_social', e.razao_social)
                            order by e.razao_social), '[]'::jsonb), count(*)::int
    into v_controladas, v_n_controladas
    from entidade e where e.caso_id = p_caso_id and e.controladora_id = p_de_id;
  update entidade set controladora_id = p_para_id
   where caso_id = p_caso_id and controladora_id = p_de_id;

  -- 0213: as perguntas JÁ AGIDAS (enviada/descartada) sobre a absorvida passam a ser da sobrevivente. São ação
  -- humana que aconteceu e é o que `ja_enviada` lê: sem isto a pergunta enviada sobre a absorvida voltaria a ser
  -- sugerida para a sobrevivente, e `caso_pergunta_entidade_id_fkey` (NO ACTION) fazia a fusão INTEIRA falhar.
  -- A SUGESTÃO não é carregada: é calculada ao vivo por fn_sugerir_perguntas e nunca é gravada.
  select coalesce(jsonb_agg(jsonb_build_object('caso_pergunta_id', cp.id, 'codigo', cp.pergunta_codigo,
                                               'acao', cp.acao, 'criado_em', cp.criado_em)
                            order by cp.criado_em, cp.id), '[]'::jsonb), count(*)::int
    into v_perguntas, v_n_perguntas
    from caso_pergunta cp where cp.caso_id = p_caso_id and cp.entidade_id = p_de_id;
  update caso_pergunta set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;

  -- A pendência de ambiguidade da entidade fundida está respondida.
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_por
   where caso_id = p_caso_id and motivo = 'entidade_ambigua:' || p_de_id and estado <> 'resolvida';

  -- 0183: e as de forma e de papel de A também — a pergunta era sobre uma entidade que deixa de
  -- existir; a de B é de B.
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_por
   where caso_id = p_caso_id
     and motivo in ('forma_de_controle_indefinida:' || p_de_id, 'papel_no_grupo_indefinido:' || p_de_id)
     and estado <> 'resolvida';

  delete from entidade where id = p_de_id and caso_id = p_caso_id;

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
  values (p_por, 'entidade_fundida', 'entidade:' || p_para_id,
          jsonb_build_object('entidade_id', p_de_id, 'razao_social', v_de,
                             -- 0183
                             'forma_de_controle', v_forma_de, 'vinculos', v_vinculos_de,
                             -- 0211: o que a linha apagada declarava e a sobrevivente não herda
                             'papel_no_grupo', v_papel_de, 'controladora_id', v_controladora_de,
                             'percentual_participacao', v_pct_de),
          jsonb_build_object('entidade_id', p_para_id, 'razao_social', v_para,
                             'documentos_movidos', v_docs,
                             -- 0183
                             'vinculos_movidos', v_vinculos_movidos,
                             'vinculos_descartados', v_descartados,
                             -- 0211
                             'perimetro_movido', v_perim_movidos,
                             'perimetro_descartado', v_perim_descartado,
                             'controladas_repontadas', v_controladas,
                             -- 0213
                             'perguntas_repontadas', v_perguntas));

  return jsonb_build_object('fundida', v_de, 'em', v_para, 'documentos', v_docs,
                            'vinculos_movidos', v_vinculos_movidos,
                            'vinculos_descartados', jsonb_array_length(v_descartados),
                            'perimetro_movido', v_perim_movidos,
                            'perimetro_descartado', jsonb_array_length(v_perim_descartado),
                            'controladas_repontadas', v_n_controladas,
                            'perguntas_repontadas', v_n_perguntas);
end;
$function$;

comment on function public.fn_fundir_entidade(p_caso_id uuid, p_de_id uuid, p_para_id uuid, p_por text) is
  'Funde duas entidades que são a mesma empresa, levando junto documentos, checklist, pendências e reconciliações (0153). Nada some sem rastro: evento_auditoria guarda o nome que existia e quantos documentos mudaram de dono. 0183: leva os vínculos de entidade_controlador quando a sobrevivente não tem nenhum (senão vão para o evento como vinculos_descartados); não herda forma_de_controle e resolve as pendências de forma e de papel da absorvida. 0211: leva os intervalos de perimetro da absorvida, exceto os que se sobrepõem a um intervalo do mesmo escopo da sobrevivente (ficam no evento em perimetro_descartado); repõe como controladora da sobrevivente quem era controlado pela absorvida; recusa em português se a sobrevivente era controlada pela absorvida; registra papel, controladora e percentual da absorvida. 0213: leva as perguntas JÁ ENVIADAS ou descartadas (caso_pergunta) para a sobrevivente, listadas no evento em perguntas_repontadas; a sugestão não se carrega (é calculada ao vivo).';

grant execute on function public.fn_fundir_entidade(uuid, uuid, uuid, text) to authenticated;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fundir_entidade_leva_perguntas_corpo', '0213', 'corpo', 'fn_fundir_entidade', 'perguntas_repontadas', null,
   'Corpo anterior ao desta migration deixa a fusão falhar na FK de caso_pergunta, e a pergunta enviada sobre a absorvida voltaria a ser sugerida para a sobrevivente.',
   'importante', 909),
  ('caso_pergunta_reapontar_policy', '0213', 'policy', 'caso_pergunta.caso_pergunta_reapontar', null, null,
   'Sem ela o authenticated não repõe a pergunta na fusão (o UPDATE afeta 0 linhas calado e a FK derruba a fusão).',
   'importante', 910),
  ('caso_pergunta_so_reaponta_gatilho', '0213', 'gatilho', 'caso_pergunta.trg_caso_pergunta_so_reaponta', null, null,
   'Sem ele a tabela append-only aceita reescrever a ação já tomada por quem tiver o privilégio.',
   'importante', 911),
  ('caso_pergunta_reaponta_evento_gatilho', '0213', 'gatilho', 'caso_pergunta.trg_caso_pergunta_reaponta_evento', null, null,
   'Sem ele o reponte direto de uma pergunta (fora da fusão) não deixa evento_auditoria.',
   'informativo', 912)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0213', revisado_em = current_date,
       observacao = 'A 0213 reemite fn_fundir_entidade (leva as perguntas já agidas, perguntas_repontadas no evento) e dá ao authenticated UPDATE só em caso_pergunta.entidade_id (policy com check de mesmo caso, gatilho append-only, revoke delete). Sem tabela nova nem backfill.'
 where id = true;
