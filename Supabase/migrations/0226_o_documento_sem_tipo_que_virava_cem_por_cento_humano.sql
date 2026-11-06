-- =============================================================================
-- 0226 — O DOCUMENTO SEM TIPO QUE VIRAVA "100% · HUMANO" (P16, VISTORIA_P2 §6 ALTA 1)
-- (Redefine fn_revisar_documento com a MESMA assinatura, a MESMA ACL (execute para authenticated, invoker, RLS vale) e o MESMO
--  retorno nos caminhos que gravam; acrescenta 1 requisito à sonda. Sem tabela, sem gatilho, sem backfill.)
--
-- O DEFEITO. Medido em produção em 04/11/2026: um .txt de 57 bytes, sem tipo, foi "confirmado sem tipo" pela fila de revisão e ficou
-- "100% · Humano" — o selo de máxima confiança num documento que ninguém classificou.
--
-- A CAUSA. A 0018 calcula tipo_final = coalesce(novo, antigo) e grava `tipo_taxonomia = tipo_final, confianca = 1.0, fonte = 'humano'` e fecha
-- a pendência mesmo com tipo_final nulo (o `if v_tipo_final is not null` só protegia o checklist). Confirmar o nada era aceito como confirmação.
--
-- A CORREÇÃO. tipo_final nulo = nada é gravado (nem documento, nem entidade/período, nem decisao, nem evento, nem pendência fechada) e a função
-- DEVOLVE a recusa como valor, no padrão de fn_decidir_pendencia (0109): {recusado: true, documento_id, motivo_recusa}. Não levanta exceção:
-- o portal já lê `recusado`/`motivo_recusa` desse padrão e uma exceção viraria erro genérico. Com tipo (novo ou antigo) o corpo é byte a byte o da 0018.
--
-- CHAMADORES (grep em Supabase/ N8N/ portal/src): o portal (casos/[id]/pendencias/actions.ts), testes e a 0216 (só cita a função na lista de RPCs
-- de escrita de trabalho). Nenhuma migration posterior à 0018 a redefine nem mexe nos privilégios dela. Nenhum caller depende do comportamento antigo
-- SEM tipo; o portal lê `.documento_id`/`.tipo_taxonomia` do retorno — ver o relatório da rodada para o ponto que o portal precisa tratar (recusado).
--
-- A SONDA. Requisito revisar_documento_recusa_sem_tipo (bloqueante): o corpo de fn_revisar_documento contém o `if coalesce(p_novo_tipo_taxonomia, v_tipo_antigo) is null` da guarda (código, não a frase da recusa). Ausente = a 0226
-- não foi aplicada (ou uma migration posterior republicou a função da 0018).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/revisar_documento_sem_tipo.test.sql, 19 asserts, medidos em 06/11/2026 com `PGOPTIONS=-cp16.medindo=on` (o assert vira `raise warning` e CONTA). Controle com a migration aplicada: 0 reprovam. Com o corpo anterior de volta (conferido que a variante APLICOU antes de rodar): 10 de 19 reprovam.
-- =============================================================================

create or replace function fn_revisar_documento(
  p_documento_id        uuid,
  p_autor               text,
  p_novo_tipo_taxonomia text default null,  -- null = mantém o tipo atual
  p_nova_entidade_nome  text default null,  -- null = mantém a entidade atual
  p_novo_periodo_tipo   text default null,
  p_novo_periodo_ref    text default null,  -- null = mantém o período atual
  p_motivo              text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_caso_id     uuid;
  v_tipo_antigo text;
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_tipo_final  text;
  v_obrig       obrigatoriedade;
  v_mudou_tipo  boolean;
begin
  select caso_id, tipo_taxonomia, entidade_id, periodo_id
    into v_caso_id, v_tipo_antigo, v_entidade_id, v_periodo_id
  from documento where id = p_documento_id;

  if v_caso_id is null then
    raise exception 'documento % não encontrado', p_documento_id;
  end if;

  -- 0226: sem tipo não há o que confirmar. Fica ANTES de qualquer escrita (entidade/período novos também gravam).
  if coalesce(p_novo_tipo_taxonomia, v_tipo_antigo) is null then
    return jsonb_build_object('recusado', true, 'documento_id', p_documento_id,
      'motivo_recusa', 'Escolha o tipo do documento antes de confirmar: sem tipo não há o que confirmar.');
  end if;

  if p_nova_entidade_nome is not null and length(trim(p_nova_entidade_nome)) > 0 then
    select id into v_entidade_id from entidade
      where caso_id = v_caso_id and lower(razao_social) = lower(p_nova_entidade_nome) limit 1;
    if v_entidade_id is null then
      insert into entidade (caso_id, razao_social) values (v_caso_id, p_nova_entidade_nome)
        returning id into v_entidade_id;
    end if;
  end if;

  if p_novo_periodo_ref is not null and length(trim(p_novo_periodo_ref)) > 0 then
    select id into v_periodo_id from periodo
      where caso_id = v_caso_id and tipo = coalesce(p_novo_periodo_tipo,'outro') and referencia = p_novo_periodo_ref limit 1;
    if v_periodo_id is null then
      insert into periodo (caso_id, tipo, referencia)
        values (v_caso_id, coalesce(p_novo_periodo_tipo,'outro'), p_novo_periodo_ref)
        returning id into v_periodo_id;
    end if;
  end if;

  v_tipo_final := coalesce(p_novo_tipo_taxonomia, v_tipo_antigo);
  v_mudou_tipo := v_tipo_final is distinct from v_tipo_antigo;

  update documento set
    tipo_taxonomia = v_tipo_final,
    entidade_id     = v_entidade_id,
    periodo_id      = v_periodo_id,
    confianca       = 1.0,
    fonte           = 'humano',
    justificativa   = coalesce(p_motivo, justificativa)
  where id = p_documento_id;

  -- Checklist: a entrada antiga (se houver) ficaria presa ao tipo errado —
  -- remove e recria para o tipo final (idempotente: sempre reflete o estado atual).
  delete from checklist_item_status where documento_id = p_documento_id;
  if v_tipo_final is not null then
    select obrigatoriedade into v_obrig from taxonomia_tipo_documento where codigo = v_tipo_final;
    insert into checklist_item_status
      (caso_id, entidade_id, periodo_id, tipo_taxonomia, obrigatoriedade, status, documento_id)
      values (v_caso_id, v_entidade_id, v_periodo_id, v_tipo_final,
              coalesce(v_obrig,'complementar'), 'presente', p_documento_id);
  end if;

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (v_caso_id,
            (case when v_mudou_tipo then 'correcao_classificacao' else 'aprovacao' end)::decisao_tipo,
            p_autor, p_motivo,
            jsonb_build_object('documento_id', p_documento_id, 'tipo_de', v_tipo_antigo, 'tipo_para', v_tipo_final));

  -- FIX (0018): resolve TODOS os tipos de pendência de revisão gerados para
  -- este documento — não só `classificacao_pendente`. `tipo_incorreto`/
  -- `entidade_incorreta`/`periodo_incorreto` (migration 0010) são fechados
  -- pela MESMA ação de revisão (o formulário já reenvia tipo+entidade+período
  -- juntos), então a resolução tem que cobrir os quatro.
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_autor
  where documento_id = p_documento_id
    and tipo in ('classificacao_pendente', 'tipo_incorreto', 'entidade_incorreta', 'periodo_incorreto')
    and estado <> 'resolvida';

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'documento_revisado', 'documento:'||p_documento_id,
            jsonb_build_object('tipo', v_tipo_antigo),
            jsonb_build_object('tipo', v_tipo_final, 'motivo', p_motivo));

  perform fn_recomputar_completude(v_caso_id);

  return jsonb_build_object('documento_id', p_documento_id, 'tipo_taxonomia', v_tipo_final, 'mudou_tipo', v_mudou_tipo);
end;
$$;

comment on function fn_revisar_documento(uuid, text, text, text, text, text, text) is
  '0226 (sobre a 0018): confirma/corrige a classificação do documento. Sem tipo final (novo nem antigo) devolve {recusado, documento_id, motivo_recusa} e não grava nada. Com tipo: grava documento (confiança 1.0, fonte humano), refaz o checklist, registra decisão e evento, e fecha as pendências de revisão do documento.';

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('revisar_documento_recusa_sem_tipo', '0226', 'corpo', 'fn_revisar_documento', 'if coalesce(p_novo_tipo_taxonomia, v_tipo_antigo) is null then', null,
   'fn_revisar_documento sem a recusa do documento sem tipo: confirmar um arquivo que ninguém classificou grava confiança 1.0 / fonte humano ("100% · Humano") e fecha a pendência. Ausente = a 0226 não foi aplicada (ou uma migration posterior republicou a função da 0018).',
   'bloqueante', 1021)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0226', revisado_em = current_date,
       observacao = 'A 0226 recusa confirmar documento sem tipo (fn_revisar_documento devolve recusado e não grava); o requisito revisar_documento_recusa_sem_tipo prova em produção que foi aplicada.'
 where id = true;
