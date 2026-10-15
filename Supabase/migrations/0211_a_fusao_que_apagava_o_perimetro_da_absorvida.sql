-- =============================================================================
-- 0211 — A FUSÃO DE ENTIDADES NÃO APAGA MAIS O PERÍMETRO DA ABSORVIDA EM SILÊNCIO
-- (F1, depois da 0210. Reemite fn_fundir_entidade INTEIRA a partir do corpo vigente — a última a reemiti-la
--  é a 0183, e o corpo abaixo é o dump de pg_get_functiondef do banco montado das migrations, com os acréscimos
--  marcados "0211", não replace de texto. Só a função muda: sem tabela nova, sem backfill.)
--
-- O DEFEITO (apontado na 0210, regra 1 — perda silenciosa): `fn_fundir_entidade` faz `delete from entidade` na
-- absorvida, e `perimetro_entidade_id_fkey` é ON DELETE CASCADE (0180): os escopos da absorvida sumiam sem evento.
-- A tela de perímetro manda fundir as fantasmas, então o caminho vai ser exercitado. Não é o primeiro:
-- entidade_controlador (0182) tem o mesmo cascade e a 0183 já o tratou.
--
-- A REGRA PARA O PERÍMETRO. Cada intervalo da absorvida passa para a sobrevivente, EXCETO o que se sobrepõe a um
-- intervalo do MESMO escopo que ela já tem. Sobreposição inclui o vigente (dois "ate is null" no mesmo escopo
-- violariam perimetro_atual_unico, e dois intervalos que se tocam seriam o mesmo período contado duas vezes).
-- Por que NÃO fundir os dois intervalos em um maior: isso inventaria um início (ou fim) que ninguém declarou,
-- e uma data de perímetro que mente sobre o exercício é pior que uma data ausente. Fica o da sobrevivente; o da
-- absorvida vai para o evento `entidade_fundida` em depois->perimetro_descartado, com escopo, desde, ate, o
-- motivo e o intervalo da sobrevivente que o cobriu. Se a data certa era a da absorvida, o analista a reabre
-- com fn_perimetro_definir_escopo. O que é movido é contado em perimetro_movido.
--
-- LISTA DAS FKs QUE APONTAM PARA entidade (medida no banco montado, confdeltype), com o EFEITO da fusão:
--   documento, checklist_item_status, pendencia, reconciliacao (NO ACTION): a fusão já as REAPONTA (0153).
--   perimetro (CASCADE): perdia em silêncio. CORRIGIDO aqui.
--   entidade_controlador (CASCADE): perdia em silêncio. Corrigido na 0183.
--   entidade.controladora_id (NO ACTION): quem tinha a absorvida como controladora fazia a fusão INTEIRA
--     falhar com "violates foreign key constraint entidade_controladora_id_fkey" (medido). CORRIGIDO aqui: as
--     controladas passam à sobrevivente e saem em depois->controladas_repontadas. Se a SOBREVIVENTE era a
--     controlada pela absorvida, a participação viraria dela com ela mesma: recusa com mensagem em português
--     (não há leitura automática).
--   caso_pergunta (NO ACTION): uma entidade citada num registro de pergunta enviada/descartada faz a fusão FALHAR
--     alto (FK). NÃO corrigido: o authenticated só tem policy de insert e read nessa tabela (log), e mover
--     exigiria policy de update sobre um registro que é histórico.
--   Sem FK, só texto: caso_linha_premissa.entidade e caso_modelagem.entidade guardam o NOME da entidade; depois
--     da fusão o nome da absorvida fica órfão ali (a premissa continua apontando para uma razão social que não
--     existe mais). NÃO corrigido; a tela de premissas é quem conhece o nome.
--   O que a LINHA apagada declarava e a sobrevivente não herda — papel_no_grupo, controladora_id,
--     percentual_participacao — antes sumia sem rastro (só forma_de_controle ia ao evento); agora vai em
--     antes->papel_no_grupo, controladora_id e percentual_participacao.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/fusao_perimetro.test.sql — 20 asserts, medidos em 15/10/2026 com o
-- assert em `raise warning` (voltou para `raise exception`), cada guarda desligada UMA por vez na função
-- reaplicada, e antes de cada número conferi que a mutação APLICOU (controle com a 0211 intacta: 20 ok, 0 falhou).
-- Com o corpo da 0183 de volta (o estado anterior), 17 dos 20 asserts reprovam. Por guarda: não mover os intervalos 4,
-- não checar a sobreposição 8 (o vigente contra o vigente estoura perimetro_atual_unico), encostar contar como
-- sobrepor 4, evento sem o descartado 1, não repor as controladas 8, sem a guarda da sobrevivente controlada 1,
-- evento sem o papel da absorvida 1, evento sem as controladas repontadas 1, evento sem perimetro_movido 1.
-- Medi também, antes de escrever, que a fusão com uma entidade que tem a absorvida como controladora falhava na FK
-- entidade_controladora_id_fkey (23503), e que o cascade de perimetro apagava os escopos sem evento.
-- =============================================================================

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
                             'controladas_repontadas', v_controladas));

  return jsonb_build_object('fundida', v_de, 'em', v_para, 'documentos', v_docs,
                            'vinculos_movidos', v_vinculos_movidos,
                            'vinculos_descartados', jsonb_array_length(v_descartados),
                            'perimetro_movido', v_perim_movidos,
                            'perimetro_descartado', jsonb_array_length(v_perim_descartado),
                            'controladas_repontadas', v_n_controladas);
end;
$function$;

comment on function public.fn_fundir_entidade(p_caso_id uuid, p_de_id uuid, p_para_id uuid, p_por text) is
  'Funde duas entidades que são a mesma empresa, levando junto documentos, checklist, pendências e reconciliações (0153). Nada some sem rastro: evento_auditoria guarda o nome que existia e quantos documentos mudaram de dono. 0183: leva também os vínculos de entidade_controlador quando a sobrevivente não tem nenhum (se já tem, os da absorvida vão para o evento como vinculos_descartados). Não herda forma_de_controle (registra no evento) e resolve as pendências de forma e de papel da absorvida. 0211: leva os intervalos de perimetro da absorvida, exceto os que se sobrepõem a um intervalo do mesmo escopo da sobrevivente (esses ficam no evento em perimetro_descartado); repõe como controladora da sobrevivente quem era controlado pela absorvida (controladas_repontadas); recusa em português se a sobrevivente era controlada pela absorvida; registra no evento o papel, a controladora e o percentual da absorvida.';

grant execute on function public.fn_fundir_entidade(uuid, uuid, uuid, text) to authenticated;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fundir_entidade_leva_perimetro_corpo', '0211', 'corpo', 'fn_fundir_entidade', 'perimetro_descartado', null,
   'Corpo anterior ao desta migration deixa o ON DELETE CASCADE apagar os escopos de perímetro da entidade absorvida sem evento: a tela manda fundir as fantasmas e o perímetro delas some calado.',
   'importante', 899)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0211', revisado_em = current_date,
       observacao = 'A 0211 reemite fn_fundir_entidade: leva o perímetro da absorvida (o descartado por sobreposição vai ao evento), repõe as controladas e registra papel/controladora/percentual da absorvida. Sem tabela nova nem backfill.'
 where id = true;
