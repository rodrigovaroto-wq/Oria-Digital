-- =============================================================================
-- 0225 — A PENDÊNCIA DECIDIDA QUE NÃO TINHA VOLTA (P16, VISTORIA_P2 §6 ALTA 1)
-- (Redefine fn_decidir_pendencia com a MESMA assinatura e a MESMA ACL (execute para authenticated, invoker); acrescenta a decisão 'reabrir'
--  e 1 requisito à sonda. Os três ramos da 0109 ficam byte a byte. Sem tabela, sem gatilho, sem backfill.)
--
-- O DEFEITO. A vistoria P2 deixou pendências presas na etiqueta "Contatar o Cliente": a 0109 oferece contatar_cliente / prosseguir / nao_procede e
-- nenhum caminho de volta a `aberta`. Um clique errado (ou um cliente que não respondeu) deixava a pendência na etiqueta para sempre.
--
-- A CORREÇÃO. decisão 'reabrir': estado volta a `aberta`, resolvida_em/resolvida_por voltam a nulos (já saem nulos para o que não é final), e o
-- evento_auditoria `pendencia_decidida` registra antes -> depois com o rótulo 'Reaberta' e `reverte_decisao` (true quando o estado anterior era
-- aceita_com_ressalva/rejeitada). 'reabrir' de pendência já `aberta` = sem_mudanca (o no-op da 0109); de `resolvida` = recusado (é do sistema, como
-- na 0109). O Portão 2 (fn_avaliar_portao2, 0109) já conta `aberta` como bloqueante viva: a pendência reaberta volta a travar o caso na mesma chamada.
--
-- SEM `decisao` NA REVERSÃO, de propósito. decisao_tipo = aprovacao | override | ressalva | mudanca_dial | correcao_classificacao. Nenhum diz "reabri":
-- 'override' e 'ressalva' são o oposto (um humano passando por cima do motor), 'aprovacao' é a do caso, 'correcao_classificacao' é de documento, e o
-- histórico do caso (0215) lê 'override' como ação de premissa. Gravar uma delas mentiria na trilha. Acrescentar valor ao enum é mudança de modelo fora
-- do escopo. A decisão ORIGINAL (ressalva/override) não é apagada; a reversão fica no evento_auditoria (que o histórico já lê como pendencia_decidida).
--
-- A SONDA. Requisito pendencia_decidir_reabrir (bloqueante): o corpo de fn_decidir_pendencia contém a atribuição `v_rotulo := 'Reaberta'` do ramo reabrir.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/pendencia_reabrir.test.sql, 23 asserts, medidos em 06/11/2026 com `PGOPTIONS=-cp16.medindo=on` (o assert vira `raise warning` e CONTA). Controle com a migration aplicada: 0 reprovam. Com o corpo anterior de volta (conferido que a variante APLICOU antes de rodar): 16 de 23 reprovam.
-- =============================================================================

create or replace function fn_decidir_pendencia(
  p_pendencia_id uuid,
  p_autor        text,
  p_decisao      text,
  p_motivo       text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_p       pendencia%rowtype;
  v_estado  pendencia_estado;
  v_motivo  text := nullif(trim(coalesce(p_motivo, '')), '');
  v_rotulo  text;
  v_tipo    decisao_tipo;
begin
  select * into v_p from pendencia where id = p_pendencia_id;
  if v_p.id is null then
    raise exception 'pendência % não encontrada', p_pendencia_id;
  end if;

  -- Os três botões da tela, nas palavras da tela.
  case p_decisao
    when 'contatar_cliente' then
      v_estado := 'reenviada_ao_cliente'; v_rotulo := 'Contatar o Cliente'; v_tipo := null;
    when 'prosseguir' then
      v_estado := 'aceita_com_ressalva';  v_rotulo := 'Prosseguir sem resolução'; v_tipo := 'ressalva';
    when 'nao_procede' then
      v_estado := 'rejeitada';            v_rotulo := 'Pendência não procede'; v_tipo := 'override';
    -- 0225: a volta. Sem `decisao` (v_tipo nulo): nenhum decisao_tipo existente diz "reabri", ver o cabeçalho.
    when 'reabrir' then
      v_estado := 'aberta';               v_rotulo := 'Reaberta'; v_tipo := null;
    else
      return jsonb_build_object('recusado', true, 'pendencia_id', p_pendencia_id,
        'motivo_recusa', format('Decisão desconhecida: %s. São quatro — contatar_cliente, '
                                'prosseguir, nao_procede, reabrir.', p_decisao));
  end case;

  -- Clicar de novo no mesmo botão é no-op declarado: dois cliques não viram
  -- duas decisões na trilha.
  if v_p.estado = v_estado then
    return jsonb_build_object('sem_mudanca', true, 'pendencia_id', p_pendencia_id,
                              'estado', v_estado, 'rotulo', v_rotulo,
                              'avaliacao', fn_avaliar_portao2(v_p.caso_id));
  end if;

  -- `resolvida` é do SISTEMA: ela significa "a condição que abriu a pendência
  -- deixou de valer", e um clique humano não pode afirmar isso. Trocar uma
  -- resolvida por decisão humana reescreveria o que o motor mediu.
  if v_p.estado = 'resolvida' then
    return jsonb_build_object('recusado', true, 'pendencia_id', p_pendencia_id,
      'motivo_recusa', 'Esta pendência já foi RESOLVIDA pelo próprio sistema: o problema que a '
        || 'abriu deixou de existir. Não há o que decidir sobre ela.');
  end if;

  update pendencia
     set estado        = v_estado,
         motivo        = coalesce(v_motivo, motivo),
         -- `resolvida_em`/`por` marcam QUANDO e QUEM tirou a pendência da fila.
         -- Para o estado de tratamento ficam nulos: contatar o cliente não tira
         -- nada da fila, só diz que alguém está cuidando.
         resolvida_em  = case when v_estado in ('rejeitada', 'aceita_com_ressalva') then now() else null end,
         resolvida_por = case when v_estado in ('rejeitada', 'aceita_com_ressalva') then p_autor else null end
   where id = p_pendencia_id;

  -- Decisão sobre o MÉRITO vira `decisao`; "estou cuidando" não vira, porque
  -- ninguém decidiu nada ainda.
  if v_tipo is not null then
    insert into decisao (caso_id, tipo, autor, motivo, payload)
      values (v_p.caso_id, v_tipo, p_autor, coalesce(v_motivo, v_rotulo),
              jsonb_build_object('acao', 'decidir_pendencia', 'decisao', p_decisao,
                                 'rotulo', v_rotulo, 'pendencia_id', p_pendencia_id,
                                 'tipo', v_p.tipo, 'severidade', v_p.severidade,
                                 'sobrepujavel', v_p.sobrepujavel,
                                 'estado_anterior', v_p.estado));
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'pendencia_decidida', 'pendencia:'||p_pendencia_id,
            jsonb_build_object('estado', v_p.estado),
            jsonb_build_object('estado', v_estado, 'rotulo', v_rotulo,
                               'caso_id', v_p.caso_id, 'motivo', v_motivo,
                               -- 0225: reabrir uma pendência JÁ DECIDIDA desfaz uma decisão que fica na trilha (a `decisao` antiga não se apaga).
                               'reverte_decisao', p_decisao = 'reabrir' and v_p.estado in ('aceita_com_ressalva', 'rejeitada')));

  return jsonb_build_object('decidida', true, 'pendencia_id', p_pendencia_id,
                            'estado', v_estado, 'rotulo', v_rotulo,
                            'avaliacao', fn_avaliar_portao2(v_p.caso_id));
end;
$$;

comment on function fn_decidir_pendencia(uuid, text, text, text) is
  'Os botões da tela em UMA função: contatar_cliente (não libera o portão), prosseguir (aceita com ressalva), nao_procede (rejeita) e, desde a 0225, reabrir (volta a aberta; de resolvida é recusado). Sem motivo obrigatório, sem expiração e sem teto, por decisão do dono (0109). Nada é apagado e tudo é contado.';

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('pendencia_decidir_reabrir', '0225', 'corpo', 'fn_decidir_pendencia', 'v_rotulo := ''Reaberta''', null,
   'fn_decidir_pendencia sem o ramo reabrir: pendência decidida (Contatar o Cliente, Prosseguir, Não procede) não tem volta a aberta e fica presa na etiqueta. Ausente = a 0225 não foi aplicada (ou uma migration posterior republicou a função da 0109).',
   'bloqueante', 1022)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0225', revisado_em = current_date,
       observacao = 'A 0225 acrescenta a decisão reabrir a fn_decidir_pendencia; o requisito pendencia_decidir_reabrir prova em produção que foi aplicada.'
 where id = true;
