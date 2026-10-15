-- =============================================================================
-- 0208 — fn_perimetro_situacao / fn_perimetro_veredito: "o perímetro deste caso está fechado? se
--        não, o que falta, em qual entidade?" (F1 do roadmap, seção 12)
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md) — Supabase/test/perimetro_situacao.test.sql: 52 asserts; o número por
-- guarda desligada está no cabeçalho de Supabase/migrations/0208_a_situacao_do_perimetro_que_so_o_teste_lia.sql
-- (com `pronta` sempre verdadeira, 9 dos 52 asserts reprovam).
--
-- O QUE ESTE ARQUIVO MEDE (comportamento, não mecanismo — regra 3):
--   1. caso sem nenhuma entidade (e caso inexistente): fechado = false, com o motivo dito;
--   2. entidade sem papel: falta papel_no_grupo_indefinido e forma_de_controle_indefinida, nomeados;
--   3. papel definido + escopo vigente, forma ainda indefinida: falta SÓ a forma (a pendência
--      forma_de_controle_indefinida aberta não duplica a falta);
--   4. controle_comum cujo vínculo sumiu depois da declaração (a 0183 só prova o vínculo NA declaração):
--      falta controle_comum_sem_vinculo; e controlada_por_entidade sem controladora (a constraint da
--      0183 o torna inalcançável, então o teste a derruba DENTRO de uma subtransação desfeita);
--   5. papel definido, diferente de fora_do_perimetro, sem escopo vigente (nenhum, ou só expirado):
--      falta sem_escopo_vigente; fora_do_perimetro SEM escopo está pronta, e COM escopo vigente tem
--      falta própria (contradição);
--   6. entidade fantasma (0178: pendência entidade_nome_suspeito): não conta como entidade real,
--      aparece com falta própria e impede `fechado`;
--   7. pendência de perímetro aberta (entidade_ambigua) segura uma entidade que está certa em tudo;
--      resolvida ou rejeitada ("não procede") solta; aceita_com_ressalva solta e fica dita;
--   8. tudo certo: fechado, com grupos por controle comum, e o aceite financeiro continua
--      nao_verificado (fechado NÃO é aceite) — nunca 'ok' por omissão;
--   9. aceite_financeiro: pendente_conferencia só com COMBINADO que tem valor em mais de uma entidade.
--
-- RODA DEPOIS das migrations 0178–0183 (usa fn_upsert_entidade e as funções de definição).
-- =============================================================================

create or replace function teste_assert_0208(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_cond then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

do $$
declare
  v_caso      uuid;
  v_caso2     uuid;
  v_vazio     uuid;
  v_sem_papel uuid;
  v_forma     uuid;
  v_cc        uuid;
  v_fora      uuid;
  v_fora_esc  uuid;
  v_expirado  uuid;
  v_fantasma  uuid;
  v_ambigua   uuid;
  v_holding   uuid;
  v_filha     uuid;
  v_ctrl      uuid;
  v_ctrl2     uuid;
  v_pend      uuid;
  v_s         record;
  v_v         record;
  v_n         int;
  v_txt       text;
  v_doc       uuid;
  v_ver       uuid;
begin
  v_caso := fn_upsert_caso('0208 — situação do perímetro');

  -- ===========================================================================
  raise notice '--- 1. caso sem entidade: zero entidades não é perímetro fechado ---';
  -- ===========================================================================
  v_vazio := fn_upsert_caso('0208 — caso vazio');
  select count(*) into v_n from fn_perimetro_situacao(v_vazio);
  perform teste_assert_0208(v_n = 0, 'caso sem entidade: a situação não tem linha', v_n::text);

  select * into v_v from fn_perimetro_veredito(v_vazio);
  perform teste_assert_0208(v_v.entidades = 0 and v_v.prontas = 0 and v_v.fantasmas = 0
                            and v_v.fechado = false,
    'caso sem entidade: 0/0/0 e fechado = false (zero entidades NÃO é perímetro fechado)',
    format('%s/%s/%s fechado=%s', v_v.entidades, v_v.prontas, v_v.fantasmas, v_v.fechado));
  perform teste_assert_0208(v_v.fechado_motivo like '%zero entidades%',
    'e o motivo diz por quê, em palavras', v_v.fechado_motivo);

  select * into v_v from fn_perimetro_veredito(gen_random_uuid());
  perform teste_assert_0208(v_v.fechado = false and v_v.entidades = 0,
    'caso inexistente também devolve UMA linha, não fechado', v_v.fechado::text);

  -- ===========================================================================
  raise notice '--- 2. entidade sem papel: a falta tem nome ---';
  -- ===========================================================================
  v_sem_papel := fn_upsert_entidade(v_caso, 'SEM PAPEL LTDA. (0208)');
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'SEM PAPEL LTDA. (0208)';
  perform teste_assert_0208(v_s.pronta = false, 'entidade recém-criada NÃO está pronta');
  perform teste_assert_0208('papel_no_grupo_indefinido' = any (v_s.falta),
    'a falta nomeia papel_no_grupo_indefinido', v_s.falta::text);
  perform teste_assert_0208('forma_de_controle_indefinida' = any (v_s.falta),
    'a falta nomeia forma_de_controle_indefinida', v_s.falta::text);
  perform teste_assert_0208(not exists (select 1 from unnest(v_s.falta) f where f like 'pendencia_aberta:%'),
    'as pendências de papel e de forma que a entidade nasce NÃO duplicam a falta da coluna',
    v_s.falta::text);
  perform teste_assert_0208(v_s.pendencias_abertas @> array['papel_no_grupo_indefinido', 'forma_de_controle_indefinida'],
    'mas as pendências aparecem em pendencias_abertas', v_s.pendencias_abertas::text);
  perform teste_assert_0208(v_s.fantasma = false and v_s.escopos_vigentes = '{}' and v_s.controladores = '[]'::jsonb,
    'sem fantasma, sem escopo e com controladores = [] (array vazio, não null)');

  -- ===========================================================================
  raise notice '--- 3. papel e escopo ok, forma indefinida: falta SÓ a forma ---';
  -- ===========================================================================
  v_forma := fn_upsert_entidade(v_caso, 'FORMA INDEFINIDA LTDA. (0208)');
  perform fn_entidade_definir_papel_no_grupo(v_forma, 'operacional', 'analista@0208');
  perform fn_perimetro_definir_escopo(v_caso, v_forma, 'combinado', current_date - 30, 'analista@0208');
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'FORMA INDEFINIDA LTDA. (0208)';
  perform teste_assert_0208(v_s.falta = array['forma_de_controle_indefinida'] and not v_s.pronta,
    'com papel e escopo vigente, falta exatamente forma_de_controle_indefinida', v_s.falta::text);
  perform teste_assert_0208(v_s.escopos_vigentes = array['combinado'],
    'o escopo vigente aparece em escopos_vigentes', v_s.escopos_vigentes::text);

  -- ===========================================================================
  raise notice '--- 4. coerência entre forma e vínculo ---';
  -- ===========================================================================
  v_cc := fn_upsert_entidade(v_caso, 'VINCULO COMUM LTDA. (0208)');
  perform fn_entidade_definir_papel_no_grupo(v_cc, 'operacional', 'analista@0208');
  perform fn_perimetro_definir_escopo(v_caso, v_cc, 'combinado', current_date - 30, 'analista@0208');
  v_ctrl := fn_controlador_registrar(v_caso, 'Sócio Pessoa Física (0208)', '000.000.000-00', 'fisica', 'analista@0208');
  perform fn_entidade_definir_controlador(v_cc, v_ctrl, 50, 'analista@0208');
  perform fn_entidade_definir_forma_de_controle(v_cc, 'controle_comum', 'analista@0208');
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'VINCULO COMUM LTDA. (0208)';
  perform teste_assert_0208(v_s.pronta and v_s.falta = '{}',
    'controle_comum COM vínculo, papel e escopo: pronta', v_s.falta::text);
  perform teste_assert_0208(jsonb_array_length(v_s.controladores) = 1
                            and v_s.controladores->0->>'nome' = 'Sócio Pessoa Física (0208)'
                            and (v_s.controladores->0->>'percentual')::numeric = 50
                            and v_s.controladores->0->>'tipo_pessoa' = 'fisica'
                            and v_s.controladores->0->>'documento' = '000.000.000-00',
    'os controladores vêm com nome, tipo, documento e percentual', v_s.controladores::text);

  -- o vínculo some DEPOIS da declaração (a 0183 só o prova na declaração, e diz isso)
  delete from entidade_controlador where entidade_id = v_cc;
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'VINCULO COMUM LTDA. (0208)';
  perform teste_assert_0208(v_s.falta = array['controle_comum_sem_vinculo'] and not v_s.pronta,
    'controle_comum cujo vínculo sumiu depois: falta controle_comum_sem_vinculo', v_s.falta::text);

  -- controlada_por_entidade sem controladora: a constraint da 0183 torna o estado inalcançável;
  -- derrubada DENTRO de uma subtransação desfeita para provar que a leitura não confia nela.
  v_filha := fn_upsert_entidade(v_caso, 'FILHA LTDA. (0208)');
  v_holding := fn_upsert_entidade(v_caso, 'HOLDING SA (0208)');
  perform fn_entidade_definir_papel_no_grupo(v_filha, 'operacional', 'analista@0208');
  perform fn_perimetro_definir_escopo(v_caso, v_filha, 'combinado', current_date - 30, 'analista@0208');
  perform fn_entidade_definir_participacao(v_filha, v_holding, 70, 'analista@0208');
  perform fn_entidade_definir_forma_de_controle(v_filha, 'controlada_por_entidade', 'analista@0208');
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'FILHA LTDA. (0208)';
  perform teste_assert_0208(v_s.pronta and v_s.controladora_id = v_holding and v_s.percentual_participacao = 70,
    'controlada_por_entidade COM controladora: pronta, e controladora e percentual voltam',
    v_s.falta::text);
  begin
    alter table entidade drop constraint entidade_forma_de_controle_coerente;
    update entidade set controladora_id = null, percentual_participacao = null where id = v_filha;
    select array_to_string(s.falta, ',') into v_txt from fn_perimetro_situacao(v_caso) s where s.razao_social = 'FILHA LTDA. (0208)';
    raise exception 'DESFAZER:%', v_txt;
  exception when raise_exception then
    if sqlerrm not like 'DESFAZER:%' then raise; end if;
    v_txt := substr(sqlerrm, 10);
  end;
  perform teste_assert_0208(v_txt = 'controlada_por_entidade_sem_controladora',
    'controlada_por_entidade sem controladora_id (constraint derrubada na subtransação): falta nomeada', v_txt);
  perform teste_assert_0208((select controladora_id from entidade where id = v_filha) = v_holding,
    'e a subtransação foi desfeita (a controladora continua gravada)');

  -- ===========================================================================
  raise notice '--- 5. escopo: papel dentro do perímetro exige; fora_do_perimetro não ---';
  -- ===========================================================================
  v_expirado := fn_upsert_entidade(v_caso, 'ESCOPO EXPIRADO LTDA. (0208)');
  perform fn_entidade_definir_papel_no_grupo(v_expirado, 'operacional', 'analista@0208');
  perform fn_entidade_definir_participacao(v_expirado, v_holding, 60, 'analista@0208');
  perform fn_entidade_definir_forma_de_controle(v_expirado, 'controlada_por_entidade', 'analista@0208');
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'ESCOPO EXPIRADO LTDA. (0208)';
  perform teste_assert_0208(v_s.falta = array['sem_escopo_vigente'],
    'papel e forma ok mas NENHUM escopo: falta sem_escopo_vigente', v_s.falta::text);
  perform fn_perimetro_definir_escopo(v_caso, v_expirado, 'combinado', current_date - 400, 'analista@0208');
  update perimetro set ate = current_date - 100 where entidade_id = v_expirado;
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'ESCOPO EXPIRADO LTDA. (0208)';
  perform teste_assert_0208(v_s.falta = array['sem_escopo_vigente'] and v_s.escopos_vigentes = '{}',
    'escopo que JÁ ACABOU não é vigente: continua faltando', v_s.falta::text);
  update perimetro set desde = current_date + 10, ate = null where entidade_id = v_expirado;
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'ESCOPO EXPIRADO LTDA. (0208)';
  perform teste_assert_0208(v_s.falta = array['sem_escopo_vigente'],
    'escopo que SÓ COMEÇA no futuro também não é vigente hoje', v_s.falta::text);

  v_fora := fn_upsert_entidade(v_caso, 'FORA DO PERIMETRO LTDA. (0208)');
  perform fn_entidade_definir_papel_no_grupo(v_fora, 'fora_do_perimetro', 'analista@0208');
  perform fn_entidade_definir_participacao(v_fora, v_holding, 30, 'analista@0208');
  perform fn_entidade_definir_forma_de_controle(v_fora, 'controlada_por_entidade', 'analista@0208');
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'FORA DO PERIMETRO LTDA. (0208)';
  perform teste_assert_0208(v_s.pronta and v_s.falta = '{}',
    'fora_do_perimetro SEM escopo está pronta (estar fora é a decisão)', v_s.falta::text);

  v_fora_esc := fn_upsert_entidade(v_caso, 'FORA COM ESCOPO LTDA. (0208)');
  perform fn_entidade_definir_papel_no_grupo(v_fora_esc, 'fora_do_perimetro', 'analista@0208');
  perform fn_entidade_definir_participacao(v_fora_esc, v_holding, 30, 'analista@0208');
  perform fn_entidade_definir_forma_de_controle(v_fora_esc, 'controlada_por_entidade', 'analista@0208');
  perform fn_perimetro_definir_escopo(v_caso, v_fora_esc, 'combinado', current_date - 5, 'analista@0208');
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'FORA COM ESCOPO LTDA. (0208)';
  perform teste_assert_0208(v_s.falta = array['fora_do_perimetro_com_escopo_vigente'],
    'fora_do_perimetro COM escopo vigente é contradição, nomeada', v_s.falta::text);

  -- ===========================================================================
  raise notice '--- 6. entidade fantasma (0178) ---';
  -- ===========================================================================
  v_fantasma := fn_upsert_entidade(v_caso, 'Controle Extratos Ofx');
  perform teste_assert_0208(exists (select 1 from pendencia where entidade_id = v_fantasma
                                       and motivo = 'entidade_nome_suspeito:' || v_fantasma
                                       and estado = 'aberta'),
    'a guarda da 0178 marcou a entidade (pendência entidade_nome_suspeito aberta) — controle positivo');
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'Controle Extratos Ofx';
  perform teste_assert_0208(v_s.fantasma and not v_s.pronta
                            and v_s.falta = array['entidade_fantasma_pendente_de_revisao'],
    'a fantasma aparece, marcada, com falta própria (nunca some em silêncio)', v_s.falta::text);
  perform teste_assert_0208(v_s.pendencias_abertas @> array['entidade_nome_suspeito'],
    'e a pendência que a marca está em pendencias_abertas', v_s.pendencias_abertas::text);
  select count(*) into v_n from fn_perimetro_situacao(v_caso) where fantasma;
  perform teste_assert_0208(v_n = 1, 'só a fantasma é fantasma', v_n::text);
  select * into v_v from fn_perimetro_veredito(v_caso);
  perform teste_assert_0208(v_v.fantasmas = 1, 'o veredito conta 1 fantasma', v_v.fantasmas::text);
  select count(*) into v_n from fn_perimetro_situacao(v_caso) where not fantasma;
  perform teste_assert_0208(v_v.entidades = v_n,
    'e `entidades` NÃO inclui a fantasma', format('%s x %s', v_v.entidades, v_n));

  -- ===========================================================================
  raise notice '--- 7. pendência de perímetro aberta ---';
  -- ===========================================================================
  v_ambigua := fn_upsert_entidade(v_caso, 'AMBIGUA LTDA. (0208)');
  perform fn_entidade_definir_papel_no_grupo(v_ambigua, 'operacional', 'analista@0208');
  perform fn_perimetro_definir_escopo(v_caso, v_ambigua, 'combinado', current_date - 30, 'analista@0208');
  perform fn_entidade_definir_participacao(v_ambigua, v_holding, 80, 'analista@0208');
  perform fn_entidade_definir_forma_de_controle(v_ambigua, 'controlada_por_entidade', 'analista@0208');
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'AMBIGUA LTDA. (0208)';
  perform teste_assert_0208(v_s.pronta, 'controle: sem pendência, a entidade certa está pronta', v_s.falta::text);

  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, entidade_id, motivo)
    values (v_caso, 'classificacao', 'entidade_incorreta', 'bloqueante', false, 'ambígua (teste 0208)',
            v_ambigua, 'entidade_ambigua:' || v_ambigua)
    returning id into v_pend;
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'AMBIGUA LTDA. (0208)';
  perform teste_assert_0208(not v_s.pronta and v_s.falta = array['pendencia_aberta:entidade_ambigua'],
    'pendência entidade_ambigua aberta segura uma entidade que está certa em tudo', v_s.falta::text);

  update pendencia set estado = 'em_correcao_interna' where id = v_pend;
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'AMBIGUA LTDA. (0208)';
  perform teste_assert_0208(not v_s.pronta, 'em_correcao_interna continua aberta', v_s.falta::text);

  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'teste' where id = v_pend;
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'AMBIGUA LTDA. (0208)';
  perform teste_assert_0208(v_s.pronta and v_s.pendencias_abertas = '{}',
    'resolvida solta a entidade', v_s.falta::text);

  update pendencia set estado = 'rejeitada' where id = v_pend;
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'AMBIGUA LTDA. (0208)';
  perform teste_assert_0208(v_s.pronta, 'rejeitada ("não procede") também solta', v_s.falta::text);

  update pendencia set estado = 'aceita_com_ressalva' where id = v_pend;
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'AMBIGUA LTDA. (0208)';
  perform teste_assert_0208(v_s.pronta, 'aceita_com_ressalva é decisão humana explícita e solta', v_s.falta::text);

  -- pendência que só cita o DOCUMENTO (o diagnóstico de conteúdo) vale para a entidade do documento
  insert into documento (caso_id, entidade_id, tipo_taxonomia) values (v_caso, v_ambigua, 'DRE') returning id into v_doc;
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
    values (v_caso, 'diagnostico', 'entidade_incorreta', 'importante', true, 'diagnóstico (teste 0208)',
            v_doc, 'diagnostico:entidade:' || v_doc);
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'AMBIGUA LTDA. (0208)';
  perform teste_assert_0208(v_s.falta = array['pendencia_aberta:entidade_incorreta'],
    'entidade_incorreta que só cita o documento vale para a entidade em que o documento está', v_s.falta::text);
  update pendencia set estado = 'resolvida' where documento_id = v_doc;

  -- contrato social ausente
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, motivo)
    values (v_caso, 'diagnostico', 'item_faltante', 'importante', true, 'sem contrato (teste 0208)',
            'contrato_social_ausente:' || v_ambigua);
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'AMBIGUA LTDA. (0208)';
  perform teste_assert_0208(v_s.falta = array['pendencia_aberta:contrato_social_ausente'],
    'item_faltante de contrato social (motivo contrato_social_ausente:<id>) segura a entidade', v_s.falta::text);
  update pendencia set estado = 'resolvida' where motivo = 'contrato_social_ausente:' || v_ambigua;

  -- item_faltante de OUTRO assunto não é de perímetro
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, entidade_id)
    values (v_caso, 'completude', 'item_faltante', 'bloqueante', true, 'Item obrigatório do Kit Básico ausente: DRE', v_ambigua);
  select * into v_s from fn_perimetro_situacao(v_caso) s where s.razao_social = 'AMBIGUA LTDA. (0208)';
  perform teste_assert_0208(v_s.pronta, 'item_faltante do Kit Básico NÃO é pendência de perímetro', v_s.falta::text);

  -- ===========================================================================
  raise notice '--- 8. o caso do teste ainda não fecha: o veredito diz quantas faltam ---';
  -- ===========================================================================
  select * into v_v from fn_perimetro_veredito(v_caso);
  perform teste_assert_0208(v_v.fechado = false and v_v.prontas < v_v.entidades,
    'com entidade faltando e fantasma aberta, fechado = false', format('%s/%s', v_v.prontas, v_v.entidades));
  perform teste_assert_0208(v_v.fechado_motivo like '%fantasma%',
    'e o motivo cita a fantasma', v_v.fechado_motivo);

  -- ===========================================================================
  raise notice '--- 9. tudo certo: fechado, com grupos; o aceite NÃO acompanha ---';
  -- ===========================================================================
  v_caso2 := fn_upsert_caso('0208 — perímetro fechado');
  v_holding := fn_upsert_entidade(v_caso2, 'HOLDING FECHADA SA (0208)');
  v_filha   := fn_upsert_entidade(v_caso2, 'IRMA FECHADA LTDA. (0208)');
  v_cc      := fn_upsert_entidade(v_caso2, 'OUTRA FECHADA LTDA. (0208)');
  v_ctrl    := fn_controlador_registrar(v_caso2, 'Sócio X (0208)', '111.111.111-11', 'fisica', 'analista@0208');
  perform fn_entidade_definir_controlador(v_holding, v_ctrl, 50, 'analista@0208');
  perform fn_entidade_definir_controlador(v_filha, v_ctrl, 50, 'analista@0208');
  perform fn_entidade_definir_papel_no_grupo(v_holding, 'holding', 'analista@0208');
  perform fn_entidade_definir_papel_no_grupo(v_filha, 'operacional', 'analista@0208');
  perform fn_entidade_definir_papel_no_grupo(v_cc, 'operacional', 'analista@0208');
  perform fn_entidade_definir_forma_de_controle(v_holding, 'controle_comum', 'analista@0208');
  perform fn_entidade_definir_forma_de_controle(v_filha, 'controle_comum', 'analista@0208');
  perform fn_entidade_definir_participacao(v_cc, v_holding, 90, 'analista@0208');
  perform fn_entidade_definir_forma_de_controle(v_cc, 'controlada_por_entidade', 'analista@0208');

  select * into v_v from fn_perimetro_veredito(v_caso2);
  perform teste_assert_0208(v_v.fechado = false and v_v.prontas = 0,
    'papel e forma definidos, mas SEM escopo vigente: nenhuma pronta e não fechado',
    format('%s prontas, fechado=%s', v_v.prontas, v_v.fechado));

  perform fn_perimetro_definir_escopo(v_caso2, v_holding, 'combinado', current_date - 90, 'analista@0208');
  perform fn_perimetro_definir_escopo(v_caso2, v_filha, 'combinado', current_date - 90, 'analista@0208');
  select * into v_v from fn_perimetro_veredito(v_caso2);
  perform teste_assert_0208(v_v.fechado = false and v_v.prontas = 2 and v_v.entidades = 3,
    'faltando UMA de três: 2 prontas de 3 e NÃO fechado', format('%s/%s', v_v.prontas, v_v.entidades));

  perform fn_perimetro_definir_escopo(v_caso2, v_cc, 'combinado', current_date - 90, 'analista@0208');
  select * into v_v from fn_perimetro_veredito(v_caso2);
  perform teste_assert_0208(v_v.fechado and v_v.entidades = 3 and v_v.prontas = 3 and v_v.fantasmas = 0,
    'tudo certo: 3 de 3 prontas, 0 fantasmas, FECHADO',
    format('%s/%s fantasmas=%s fechado=%s', v_v.prontas, v_v.entidades, v_v.fantasmas, v_v.fechado));
  perform teste_assert_0208(jsonb_array_length(v_v.grupos) = 1
                            and (v_v.grupos->0->>'quantas')::int = 2
                            and jsonb_array_length(v_v.grupos->0->'entidades') = 2,
    'os grupos por controle comum vêm resumidos: UM grupo de 2 (o sócio X liga a holding e a irmã)',
    v_v.grupos::text);

  perform teste_assert_0208(v_v.aceite_financeiro = 'nao_verificado',
    'perímetro FECHADO não é aceite: sem COMBINADO do cliente o aceite é nao_verificado, nunca ok',
    v_v.aceite_financeiro);
  perform teste_assert_0208(v_v.aceite_motivo like '%EFEITO%' or v_v.aceite_motivo like '%O efeito%',
    'e o motivo diz o EFEITO por extenso', v_v.aceite_motivo);

  -- ===========================================================================
  raise notice '--- 10. aceite financeiro: COMBINADO de verdade, e só ele ---';
  -- ===========================================================================
  insert into documento (caso_id, tipo_taxonomia) values (v_caso2, 'COMBINADO') returning id into v_doc;
  insert into documento_versao (documento_id, n_versao, arquivo_ref, nome_original, hash)
    values (v_doc, 1, 'bucket/comb0208.xlsx', 'combinado.xlsx', 'HASH-0208') returning id into v_ver;
  select * into v_v from fn_perimetro_veredito(v_caso2);
  perform teste_assert_0208(v_v.aceite_financeiro = 'nao_verificado',
    'documento COMBINADO ainda SEM conteúdo extraído: continua nao_verificado', v_v.aceite_financeiro);

  insert into campo_extraido (documento_versao_id, chave, valor_num, entidade_coluna)
    values (v_ver, 'receita', 100, 'HOLDING FECHADA SA');
  select * into v_v from fn_perimetro_veredito(v_caso2);
  perform teste_assert_0208(v_v.aceite_financeiro = 'nao_verificado',
    'COMBINADO com valor em UMA só coluna de entidade não é combinado: nao_verificado', v_v.aceite_financeiro);

  insert into campo_extraido (documento_versao_id, chave, valor_num, entidade_coluna)
    values (v_ver, 'receita', 80, 'IRMA FECHADA LTDA.');
  select * into v_v from fn_perimetro_veredito(v_caso2);
  perform teste_assert_0208(v_v.aceite_financeiro = 'pendente_conferencia',
    'COMBINADO com valor em duas entidades: pendente_conferencia', v_v.aceite_financeiro);
  perform teste_assert_0208(v_v.aceite_motivo like '%conferência é humana%',
    'e o motivo diz que a conferência é humana, não do sistema', v_v.aceite_motivo);
  perform teste_assert_0208(v_v.fechado, 'o aceite não mexe em fechado (são duas perguntas)');

  -- ===========================================================================
  raise notice '--- 11. fechado deixa de ser fechado quando uma fantasma aparece, mesmo com todas as reais prontas ---';
  -- ===========================================================================
  perform fn_upsert_entidade(v_caso2, 'Status Extratos');
  select * into v_v from fn_perimetro_veredito(v_caso2);
  perform teste_assert_0208(v_v.prontas = v_v.entidades and v_v.entidades = 3 and v_v.fantasmas = 1
                            and v_v.fechado = false and v_v.fechado_motivo like '%fantasma%',
    'as 3 reais seguem prontas, mas a fantasma sem revisão IMPEDE fechado e o motivo a cita',
    format('%s/%s fantasmas=%s fechado=%s', v_v.prontas, v_v.entidades, v_v.fantasmas, v_v.fechado));

  raise notice 'SITUAÇÃO DO PERÍMETRO OK — a regra "fechado" mora no banco: cada falta tem nome, a fantasma '
    'aparece e segura o fechamento, zero entidades não é fechado, e o aceite financeiro nunca é ok por omissão';
end $$;

