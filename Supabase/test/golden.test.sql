-- Testes do golden set e do portão da regra de ouro (Supabase/migrations/0126).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTES TESTES TRAVAM. Antes da 0126, `Arquitetura do Sistema/1 Visão e Doutrina/01` fechava com uma regra de
-- ouro em negrito — "nada de subir o dial de autonomia de um estágio
-- interpretativo sem golden set e concordância medida" — e `fn_mudar_dial`
-- conferia só o teto. A regra existia na doutrina, no cabeçalho de duas
-- migrations e em letras âmbar na tela de autonomia; não existia em código
-- nenhum. Nenhum teste podia notar, porque não havia o que ligar.
--
-- As propriedades, em ordem de importância:
--
--   1. SUBIR PARA AUTO-CLEAR SEM MEDIÇÃO É RECUSADO. Se isto quebrar, a regra de
--      ouro volta a ser prosa e o projeto perde a única garantia que separa
--      "N2 medido" de "N2 porque alguém digitou N2".
--   2. DESCER NUNCA PEDE NADA. Freio que exige papelada não é freio. Vale para o
--      portão novo exatamente como já valia para o teto.
--   3. GOLDEN SINTÉTICO NÃO SOBE DIAL. Sem isto o portão é teatro: os dois books
--      têm GABARITO.json, rotulá-los é de graça e a concordância sai ~100% por
--      construção. Seria medir o instrumento e chamar de autonomia — a ressalva
--      que o `medir-auto-aceite.mts` carrega no cabeçalho desde que existe.
--   4. ONDE OS HUMANOS DISCORDAM, A MÁQUINA NÃO É COBRADA. `Arquitetura do Sistema/2 Especificação/f0/06`: "se humanos
--      discordam, a máquina não tem como acertar". Contar como erro cobraria dela
--      uma resposta que não existe; contar como acerto premiaria adivinhação.
--   5. AUSENTE NÃO É ERRADO. Perda silenciosa é a família de defeito que custou
--      as três camadas de cobertura; somar as duas num "erro de extração" apagaria
--      a distinção que motivou metade das sessões 45-47.
--   6. A RODADA CONGELADA NÃO MUDA MAIS. Evidência editável depois de ter
--      autorizado uma subida de dial é pior que evidência nenhuma.
--
-- POR QUE OS CENÁRIOS USAM 20+ DOCUMENTOS E NÃO 2. O `n_minimo` do `Arquitetura do Sistema/2 Especificação/f0/06` é ~20
-- por tipo core, e ele entra em `golden_criterio` como default. Um teste com dois
-- documentos teria de baixar o critério para passar — e aí estaria provando um
-- portão calibrado por ele mesmo. Os documentos são baratos; o critério real é
-- que precisa ser exercitado.
--
-- ESTE ARQUIVO RODA UMA VEZ POR BANCO, e não é descuido: os nomes de rodada são
-- únicos (`golden_rodada.nome`), então uma segunda execução no MESMO banco morre
-- em chave duplicada. O `run.sh` monta o banco do zero, que é o caminho normal.
-- Se você estiver religando um defeito à mão, recrie o banco em vez de reexecutar
-- só este arquivo — o nome duplicado é ruído e não o defeito que você procura.

\set ON_ERROR_STOP on

create or replace function teste_assert_golden(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- Cria um documento com a saída da MÁQUINA já gravada (tipo, entidade, período e
-- as linhas), sem passar pela ingestão. O que está sob teste é a medição, não o
-- pipeline: usar `fn_registrar_documento` traria a canonicalização de entidade e o
-- auto-aceite para dentro do cenário, e um assert de F1 que falha por causa da
-- 0030 não diz nada sobre F1.
create or replace function teste_golden_doc(
  p_caso uuid, p_tipo_maquina text, p_entidade text, p_periodo text, p_sufixo text
) returns uuid language plpgsql as $$
declare v_ent uuid; v_per uuid; v_doc uuid; v_ver uuid;
begin
  select id into v_ent from entidade where caso_id = p_caso and razao_social = p_entidade;
  if v_ent is null then
    insert into entidade (caso_id, razao_social) values (p_caso, p_entidade) returning id into v_ent;
  end if;
  select id into v_per from periodo where caso_id = p_caso and referencia = p_periodo;
  if v_per is null then
    insert into periodo (caso_id, tipo, referencia) values (p_caso, 'anual', p_periodo)
      returning id into v_per;
  end if;

  insert into documento (caso_id, entidade_id, periodo_id, tipo_taxonomia, confianca)
    values (p_caso, v_ent, v_per, p_tipo_maquina, 0.97) returning id into v_doc;
  insert into documento_versao (documento_id, n_versao, arquivo_ref, nome_original, hash)
    values (v_doc, 1, 'bucket/golden-'||p_sufixo||'.pdf', 'golden-'||p_sufixo||'.pdf',
            'HASH-GOLDEN-'||p_sufixo)
    returning id into v_ver;
  return v_doc;
end $$;

-- Grava uma linha extraída (a resposta da máquina) na versão vigente do documento.
create or replace function teste_golden_linha(
  p_doc uuid, p_chave text, p_valor numeric, p_periodo text default null,
  p_auto_aceito boolean default false
) returns void language plpgsql as $$
declare v_ver uuid;
begin
  select id into v_ver from documento_versao where documento_id = p_doc order by n_versao desc limit 1;
  insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca,
                              periodo_coluna, status_aceite, aceito_por, aceito_em)
  values (v_ver, p_chave, p_valor, 'milhar', 0.98, p_periodo,
          case when p_auto_aceito then 'aceito' else 'pendente' end,
          case when p_auto_aceito then 'sistema:auto_aceite (dial N2, limiar 0.95, teste)' end,
          case when p_auto_aceito then now() end);
end $$;

do $$
declare
  v_caso      uuid;
  v_boa       uuid;   -- rodada real, congelada, 20 documentos, classificação perfeita
  v_ruim      uuid;   -- rodada real, congelada, 25 documentos, 5 classificados errado
  v_pequena   uuid;   -- rodada real, congelada, 5 documentos: concordância ótima, N insuficiente
  v_sintetica uuid;   -- rodada de book: rotular o que já se conhece
  v_aberta    uuid;   -- rodada não congelada
  v_doc       uuid;
  v_docs_bons uuid[] := '{}';
  v_r         jsonb;
  v_med       jsonb;
  v_n         int;
  v_txt       text;
  v_num       numeric;
begin
  v_caso := (fn_upsert_caso('Caso golden set 0126'))::uuid;

  -- ==========================================================================
  raise notice '--- 1. o portão: subir para auto-clear sem medição é RECUSADO ---';
  -- ==========================================================================
  -- `classificacao_doc_checklist` tem teto N2, então é um estágio interpretativo
  -- que a regra de ouro governa — usar a extração aqui mediria o estado já
  -- declarado pela 0041.
  --
  -- O CENÁRIO ESTABELECE A PRÓPRIA PRÉ-CONDIÇÃO, e isto é conserto de um teste
  -- frágil que a 0127 expôs. Antes ele confiava em o estágio estar em N1 por
  -- semeadura (0002) — e no dia em que uma migration declarou o N2 que a
  -- classificação já praticava, o cenário passou a testar "N2 → N2", que não é
  -- subida, e reprovou. Baixar aqui é sempre permitido e não custa nada; depender
  -- de um default global é que custa.
  perform fn_mudar_dial('classificacao_doc_checklist', 'N1', 'teste:golden',
                        'o cenário precisa partir de N1 para que a subida seja subida');
  v_r := fn_mudar_dial('classificacao_doc_checklist', 'N2', 'teste:golden',
                       'subindo sem nada nas mãos');
  perform teste_assert_golden((v_r->>'recusado')::boolean,
    'N1 -> N2 sem rodada de golden set e sem motivo assumido é RECUSADO', v_r::text);
  perform teste_assert_golden(v_r->>'motivo_recusa' like '%concordância medida%',
    'e a recusa cita a exigência do Arquitetura do Sistema/1 Visão e Doutrina/01, não um erro genérico', v_r->>'motivo_recusa');
  perform teste_assert_golden(v_r->>'motivo_recusa' like '%p_rodada_golden%'
                          and v_r->>'motivo_recusa' like '%p_sem_medicao_porque%',
    'e nomeia os DOIS caminhos — recusa que não diz como prosseguir é beco sem saída');

  select nivel_atual::text into v_txt from estagio_autonomia
    where estagio = 'classificacao_doc_checklist';
  perform teste_assert_golden(v_txt = 'N1', 'o nível NÃO mudou', coalesce(v_txt, '(null)'));

  perform teste_assert_golden(
    exists (select 1 from evento_auditoria
             where acao = 'mudanca_dial_recusada'
               and entidade_ref = 'estagio:classificacao_doc_checklist'
               and depois->>'porque' like '%sem rodada%'),
    'a tentativa recusada fica na trilha — é o que ela precisa guardar (Arquitetura do Sistema/1 Visão e Doutrina/01)');

  -- ==========================================================================
  raise notice '--- 2. descer NUNCA pede nada, e reafirmar o mesmo nível não é subida ---';
  -- ==========================================================================
  -- Esta é a propriedade que um portão mal escrito quebra primeiro: cobrar
  -- evidência para DESLIGAR autonomia transformaria a guarda em armadilha.
  v_r := fn_mudar_dial('extracao_linhas_financeiras', 'N0', 'teste:golden',
                       'desligando a autonomia sem apresentar medição nenhuma');
  perform teste_assert_golden(coalesce((v_r->>'recusado')::boolean, false) = false,
    'baixar de N2 para N0 é permitido sem rodada e sem motivo assumido', v_r::text);
  perform teste_assert_golden(v_r->>'base_do_nivel' = 'nao_se_aplica',
    'e em N0 a base do nível é "nao_se_aplica" — não há autonomia a justificar', v_r::text);

  perform fn_mudar_dial('extracao_linhas_financeiras', 'N2', 'teste:golden',
                        'restaurando', 0.95, null, 'arnês de teste; não é medição');
  v_r := fn_mudar_dial('extracao_linhas_financeiras', 'N2', 'teste:golden',
                       'mexendo só no limiar, sem mexer no nível', 0.96);
  perform teste_assert_golden(coalesce((v_r->>'recusado')::boolean, false) = false,
    'reafirmar N2 já vigente (para ajustar o limiar) não é subida e não é cobrado', v_r::text);
  perform fn_mudar_dial('extracao_linhas_financeiras', 'N2', 'teste:golden',
                        'limiar de volta ao da 0019', 0.95);

  -- ==========================================================================
  raise notice '--- 3. o escape declarado sobe, mas fica CONTÁVEL ---';
  -- ==========================================================================
  v_r := fn_mudar_dial('classificacao_doc_checklist', 'N2', 'teste:golden',
                       'decisão de produto', null, null,
                       'sem golden set ainda; o dono assume o risco por escrito');
  perform teste_assert_golden(coalesce((v_r->>'recusado')::boolean, false) = false,
    'com p_sem_medicao_porque a subida acontece — a decisão continua sendo do dono', v_r::text);
  perform teste_assert_golden(v_r->>'base_do_nivel' = 'declarada',
    'e o nível se declara DECLARADO, não medido', v_r::text);
  perform teste_assert_golden(v_r->>'medicao_rodada_id' is null,
    'sem rodada apontada — nada finge ter sido medido');
  perform teste_assert_golden(
    exists (select 1 from evento_auditoria
             where acao = 'mudanca_dial_sem_medicao'
               and entidade_ref = 'estagio:classificacao_doc_checklist'
               and depois->>'sem_medicao_porque' like '%assume o risco%'),
    'a trilha grava a AÇÃO PRÓPRIA "mudanca_dial_sem_medicao" com o motivo',
    'sem ação própria, o declarado fica indistinguível do medido numa lista de mudanca_dial');

  -- volta para N1 para os cenários de medição partirem do mesmo lugar
  perform fn_mudar_dial('classificacao_doc_checklist', 'N1', 'teste:golden', 'de volta ao N1 da 0002');

  -- ==========================================================================
  raise notice '--- 4. as três rodadas: N insuficiente, concordância insuficiente, e a que passa ---';
  -- ==========================================================================
  insert into golden_rodada (nome, taxonomia_versao, criada_por)
    values ('teste-0126-boa', 1, 'teste:golden') returning id into v_boa;
  insert into golden_rodada (nome, taxonomia_versao, criada_por)
    values ('teste-0126-ruim', 1, 'teste:golden') returning id into v_ruim;
  insert into golden_rodada (nome, taxonomia_versao, criada_por)
    values ('teste-0126-pequena', 1, 'teste:golden') returning id into v_pequena;

  -- 20 balanços que a máquina classificou CERTO.
  for v_n in 1..20 loop
    v_doc := teste_golden_doc(v_caso, 'BALANCO', 'Golden Indústria Ltda.', '2025', 'ok-'||v_n);
    v_docs_bons := array_append(v_docs_bons, v_doc);
    insert into golden_documento (rodada_id, documento_id, estrato, origem, incluido_por)
      values (v_boa, v_doc, 'pdf_nativo', 'real', 'teste:golden'),
             (v_ruim, v_doc, 'pdf_nativo', 'real', 'teste:golden');
    insert into golden_rotulo (rodada_id, documento_id, rotulador, tipo_correto,
                               entidade_correta, periodo_correto, legibilidade)
      values (v_boa, v_doc, 'rotulador:ana', 'BALANCO', 'Golden Indústria Ltda.', '2025', 'ok'),
             (v_ruim, v_doc, 'rotulador:ana', 'BALANCO', 'Golden Indústria Ltda.', '2025', 'ok');
    if v_n <= 5 then
      insert into golden_documento (rodada_id, documento_id, estrato, origem, incluido_por)
        values (v_pequena, v_doc, 'pdf_nativo', 'real', 'teste:golden');
      insert into golden_rotulo (rodada_id, documento_id, rotulador, tipo_correto,
                                 entidade_correta, periodo_correto, legibilidade)
        values (v_pequena, v_doc, 'rotulador:ana', 'BALANCO', 'Golden Indústria Ltda.', '2025', 'ok');
    end if;
  end loop;

  -- 5 balanços que a máquina chamou de DRE. Entram SÓ na rodada ruim.
  for v_n in 1..5 loop
    v_doc := teste_golden_doc(v_caso, 'DRE', 'Golden Indústria Ltda.', '2025', 'erro-'||v_n);
    insert into golden_documento (rodada_id, documento_id, estrato, origem, incluido_por)
      values (v_ruim, v_doc, 'pdf_nativo', 'real', 'teste:golden');
    insert into golden_rotulo (rodada_id, documento_id, rotulador, tipo_correto,
                               entidade_correta, periodo_correto, legibilidade)
      values (v_ruim, v_doc, 'rotulador:ana', 'BALANCO', 'Golden Indústria Ltda.', '2025', 'ok');
  end loop;

  update golden_rodada set congelada_em = now(), congelada_por = 'teste:golden'
    where id in (v_boa, v_ruim, v_pequena);

  -- 4a. N insuficiente ------------------------------------------------------
  v_med := fn_golden_suficiente('classificacao_doc_checklist', v_pequena);
  perform teste_assert_golden((v_med->>'suficiente')::boolean = false,
    'rodada com 5 documentos reprova por N, mesmo com classificação PERFEITA', v_med::text);
  perform teste_assert_golden(v_med->'falhas'->0->>'falha' = 'n_minimo',
    'e a falha nomeada é n_minimo — não "concordância baixa", que seria mentira',
    (v_med->'falhas')::text);
  perform teste_assert_golden((v_med->>'pior_caso')::numeric = 1.0,
    'a concordância medida É 1.0; o que falta é tamanho de amostra', v_med::text);

  -- 4b. concordância insuficiente -------------------------------------------
  v_med := fn_golden_suficiente('classificacao_doc_checklist', v_ruim);
  perform teste_assert_golden((v_med->>'suficiente')::boolean = false,
    'rodada com 25 documentos e 5 classificados errado reprova por concordância', v_med::text);
  perform teste_assert_golden(v_med->'falhas'->0->>'falha' = 'concordancia',
    'e a falha nomeada é concordancia — o N está satisfeito', (v_med->'falhas')::text);
  -- F1 do BALANCO = 2*20 / (2*20 + 0 FP + 5 FN) = 40/45 = 0.8889
  perform teste_assert_golden((v_med->>'pior_caso')::numeric = 0.8889,
    'o F1 do tipo mais fraco é 0.8889, e é ele que decide', v_med->>'pior_caso');

  -- E o erro é contado UMA vez, no tipo que tinha a verdade. O DRE aparece com
  -- 5 falso-positivos e n_verdade zero — se ele participasse do "mais fraco
  -- governa", o mesmo erro pesaria duas vezes e um único documento vetaria.
  select fp into v_n from fn_golden_classificacao(v_ruim) where tipo = 'DRE';
  perform teste_assert_golden(v_n = 5,
    'o tipo que a máquina INVENTOU aparece no relatório com seus 5 falso-positivos',
    format('fp=%s', v_n));
  select n_verdade into v_n from fn_golden_classificacao(v_ruim) where tipo = 'DRE';
  perform teste_assert_golden(v_n = 0,
    'com n_verdade zero — e por isso ele não vira veto de um documento só',
    format('n_verdade=%s', v_n));

  -- 4c. a que passa ---------------------------------------------------------
  v_med := fn_golden_suficiente('classificacao_doc_checklist', v_boa);
  perform teste_assert_golden((v_med->>'suficiente')::boolean,
    '20 documentos reais com classificação perfeita SATISFAZEM o critério', v_med::text);

  v_r := fn_mudar_dial('classificacao_doc_checklist', 'N2', 'teste:golden',
                       'concordância medida contra a rodada teste-0126-boa', null, v_boa);
  perform teste_assert_golden(coalesce((v_r->>'recusado')::boolean, false) = false,
    'e a subida é ACEITA — o portão não é um "não" permanente', v_r::text);
  perform teste_assert_golden(v_r->>'base_do_nivel' = 'medida',
    'com base MEDIDA, que é o que a distingue da subida declarada', v_r::text);
  perform teste_assert_golden((v_r->>'medicao_rodada_id')::uuid = v_boa,
    'e a rodada que a autorizou fica apontada');
  perform teste_assert_golden(v_r->'medicao_resumo'->>'pior_caso' is not null,
    'com o resumo da medição congelado — "com que número isto subiu?" tem resposta depois');

  -- A rodada ruim NÃO sobe, e a recusa carrega a medição.
  perform fn_mudar_dial('classificacao_doc_checklist', 'N1', 'teste:golden', 'de volta para o próximo cenário');
  v_r := fn_mudar_dial('classificacao_doc_checklist', 'N2', 'teste:golden',
                       'tentando com a rodada ruim', null, v_ruim);
  perform teste_assert_golden((v_r->>'recusado')::boolean,
    'com a rodada ruim a subida é RECUSADA', v_r::text);
  perform teste_assert_golden(v_r->'medicao'->'falhas'->0->>'falha' = 'concordancia',
    'e a recusa vem com o número que faltou, não só com um "não"', v_r::text);

  -- Descer depois de ter subido MEDIDO limpa o ponteiro: subir de novo não
  -- reaproveita a medição antiga como se ela tivesse sido feita agora.
  select medicao_rodada_id into v_doc from estagio_autonomia
    where estagio = 'classificacao_doc_checklist';
  perform teste_assert_golden(v_doc is null,
    'descer para N1 limpou a medição — ela não sobrevive ao nível que justificava');

  -- ==========================================================================
  raise notice '--- 5. golden SINTÉTICO não sobe dial ---';
  -- ==========================================================================
  insert into golden_rodada (nome, taxonomia_versao, criada_por)
    values ('teste-0126-sintetica', 1, 'teste:golden') returning id into v_sintetica;
  for v_n in 1..20 loop
    insert into golden_documento (rodada_id, documento_id, estrato, origem, incluido_por)
      values (v_sintetica, v_docs_bons[v_n], 'digital', 'sintetico', 'teste:golden');
    insert into golden_rotulo (rodada_id, documento_id, rotulador, tipo_correto,
                               entidade_correta, periodo_correto, legibilidade)
      values (v_sintetica, v_docs_bons[v_n], 'rotulador:ana', 'BALANCO',
              'Golden Indústria Ltda.', '2025', 'ok');
  end loop;
  update golden_rodada set congelada_em = now(), congelada_por = 'teste:golden'
    where id = v_sintetica;

  -- Os MESMOS 20 documentos, a MESMA classificação perfeita, o MESMO N. A única
  -- diferença é a coluna `origem` — e ela é a diferença entre medir o modelo e
  -- medir o instrumento.
  v_med := fn_golden_suficiente('classificacao_doc_checklist', v_sintetica);
  perform teste_assert_golden((v_med->>'suficiente')::boolean = false,
    'rodada de origem sintética NÃO autoriza subida, com os mesmos 20 e o mesmo F1',
    v_med::text);
  perform teste_assert_golden(v_med->>'porque' like '%instrumento%',
    'e o motivo diz por quê: rotular o que já se conhece mede o instrumento',
    v_med->>'porque');

  v_r := fn_mudar_dial('classificacao_doc_checklist', 'N2', 'teste:golden',
                       'tentando subir com o book', null, v_sintetica);
  perform teste_assert_golden((v_r->>'recusado')::boolean,
    'e o dial recusa de fato — não é só a função de medição que reclama', v_r::text);

  -- ==========================================================================
  raise notice '--- 6. rodada NÃO CONGELADA não autoriza nada ---';
  -- ==========================================================================
  insert into golden_rodada (nome, taxonomia_versao, criada_por)
    values ('teste-0126-aberta', 1, 'teste:golden') returning id into v_aberta;
  for v_n in 1..20 loop
    insert into golden_documento (rodada_id, documento_id, estrato, origem, incluido_por)
      values (v_aberta, v_docs_bons[v_n], 'pdf_nativo', 'real', 'teste:golden');
    insert into golden_rotulo (rodada_id, documento_id, rotulador, tipo_correto,
                               entidade_correta, periodo_correto, legibilidade)
      values (v_aberta, v_docs_bons[v_n], 'rotulador:ana', 'BALANCO',
              'Golden Indústria Ltda.', '2025', 'ok');
  end loop;

  v_med := fn_golden_suficiente('classificacao_doc_checklist', v_aberta);
  perform teste_assert_golden((v_med->>'suficiente')::boolean = false,
    'rodada real, 20 documentos, F1 perfeito — e reprova por não estar CONGELADA', v_med::text);
  perform teste_assert_golden(v_med->>'porque' like '%CONGELADA%',
    'e o motivo é esse, dito com essa palavra', v_med->>'porque');

  -- ==========================================================================
  raise notice '--- 7. a rodada congelada não aceita mais rótulo, e não descongela ---';
  -- ==========================================================================
  begin
    insert into golden_rotulo (rodada_id, documento_id, rotulador, tipo_correto)
      values (v_boa, v_docs_bons[1], 'rotulador:tardio', 'BALANCO');
    perform teste_assert_golden(false, 'rótulo novo em rodada congelada deveria ter sido recusado');
  exception when check_violation then
    perform teste_assert_golden(true, 'rótulo novo em rodada CONGELADA é recusado pelo gatilho');
  end;

  begin
    update golden_rodada set congelada_em = null where id = v_boa;
    perform teste_assert_golden(false, 'descongelar deveria ter sido recusado');
  exception when check_violation then
    perform teste_assert_golden(true,
      'e a rodada não DESCONGELA — ampliar é rodada nova (Arquitetura do Sistema/2 Especificação/f0/06)');
  end;

  -- E não RENOMEIA: o nome da rodada é citado na trilha e em medicao_resumo, e a
  -- política de UPDATE existe só para permitir congelar. Sem esta guarda, ela
  -- deixava a evidência de uma decisão de dial ser reetiquetada depois da decisão.
  begin
    update golden_rodada set nome = 'teste-0126-renomeada' where id = v_boa;
    perform teste_assert_golden(false, 'renomear rodada congelada deveria ter sido recusado');
  exception when check_violation then
    perform teste_assert_golden(true,
      'nem RENOMEIA — o nome está citado na trilha e no medicao_resumo');
  end;
  begin
    update golden_rodada set taxonomia_versao = 99 where id = v_boa;
    perform teste_assert_golden(false, 'trocar a versão da taxonomia deveria ter sido recusado');
  exception when check_violation then
    perform teste_assert_golden(true,
      'nem troca a versão da taxonomia — ela é a premissa dos rótulos');
  end;

  -- Rodada ABERTA continua editável: congelar é o que fecha, e antes disso
  -- corrigir o nome de uma rodada em montagem é trabalho normal.
  update golden_rodada set nome = 'teste-0126-aberta-renomeada' where id = v_aberta;
  perform teste_assert_golden(true, 'e rodada AINDA ABERTA continua editável (congelar é o que fecha)');

  -- ==========================================================================
  raise notice '--- 8. onde os rotuladores discordam, a máquina não é cobrada ---';
  -- ==========================================================================
  -- Rodada com dois rotuladores: num documento eles concordam, no outro não.
  declare
    v_disc uuid;
    v_d_ok uuid;
    v_d_nao uuid;
  begin
    insert into golden_rodada (nome, taxonomia_versao, criada_por)
      values ('teste-0126-discordancia', 1, 'teste:golden') returning id into v_disc;

    v_d_ok  := teste_golden_doc(v_caso, 'BALANCO', 'Golden Indústria Ltda.', '2025', 'disc-ok');
    v_d_nao := teste_golden_doc(v_caso, 'BALANCO', 'Golden Indústria Ltda.', '2025', 'disc-nao');
    insert into golden_documento (rodada_id, documento_id, estrato, origem, incluido_por)
      values (v_disc, v_d_ok, 'escaneado', 'real', 'teste:golden'),
             (v_disc, v_d_nao, 'escaneado', 'real', 'teste:golden');

    insert into golden_rotulo (rodada_id, documento_id, rotulador, tipo_correto, entidade_correta)
      values (v_disc, v_d_ok, 'rotulador:ana',  'BALANCO', 'Golden Indústria Ltda.'),
             (v_disc, v_d_ok, 'rotulador:bruno','BALANCO', 'GOLDEN INDUSTRIA LTDA'),
             -- Aqui os dois humanos leem tipos diferentes no mesmo arquivo. A
             -- máquina disse BALANCO, que é o que a Ana diz — e mesmo assim o
             -- documento não pode contar como acerto: não há verdade acordada.
             (v_disc, v_d_nao, 'rotulador:ana',  'BALANCO', 'Golden Indústria Ltda.'),
             (v_disc, v_d_nao, 'rotulador:bruno','COMBINADO', 'Golden Indústria Ltda.');

    select n_medido, n_sem_consenso into v_n, v_num
      from fn_golden_identificadores(v_disc) where identificador = 'tipo';
    perform teste_assert_golden(v_n = 1 and v_num = 1,
      'o documento com discordância de tipo sai do placar (1 medido, 1 sem consenso)',
      format('n_medido=%s n_sem_consenso=%s', v_n, v_num));

    select acuracia into v_num from fn_golden_identificadores(v_disc) where identificador = 'tipo';
    perform teste_assert_golden(v_num = 1.0,
      'e a acurácia é 1.0 sobre o que TEM verdade — não 0.5 cobrando o indecidível',
      v_num::text);

    -- E as duas grafias da mesma companhia NÃO são discordância: é o que
    -- fn_mesma_entidade (0030) resolve, e a 0121 mostrou o custo de não usá-la.
    select n_concordam into v_n from fn_golden_inter_avaliador(v_disc) where campo = 'entidade';
    perform teste_assert_golden(v_n = 2,
      '"Golden Indústria Ltda." e "GOLDEN INDUSTRIA LTDA" concordam nos DOIS documentos',
      format('concordam=%s', v_n));
    select n_concordam into v_n from fn_golden_inter_avaliador(v_disc) where campo = 'tipo';
    perform teste_assert_golden(v_n = 1,
      'e a concordância inter-avaliador de TIPO acusa o único par que divergiu',
      format('concordam=%s', v_n));

    -- E SILÊNCIO NÃO É CONCORDÂNCIA. No documento em que os dois concordam no
    -- tipo, nenhum dos dois julgou o `assinado`. Sem esta regra, "os dois deixaram
    -- null" contaria como consenso e o campo entraria no placar da máquina com uma
    -- verdade que ninguém afirmou — a forma mais silenciosa de inventar ground
    -- truth. É o que `count(x) = count(*)` faz na fn_golden_consenso.
    select count(*) into v_n from fn_golden_consenso(v_disc) where assinado_consenso;
    perform teste_assert_golden(v_n = 0,
      'campo que NINGUÉM julgou não tem consenso — null é "não sei", não acordo',
      format('%s documento(s) com consenso de assinado', v_n));
  end;

  -- ==========================================================================
  raise notice '--- 9. campos: AUSENTE não é ERRADO, e a cobertura olha o lado inverso ---';
  -- ==========================================================================
  declare
    v_rc      uuid;
    v_d       uuid;
    v_exato   int;
    v_tol     int;
    v_errado  int;
    v_ausente int;
    v_auto    int;
    v_auto_s  int;
    v_cob     numeric;
  begin
    insert into golden_rodada (nome, taxonomia_versao, criada_por)
      values ('teste-0126-campos', 1, 'teste:golden') returning id into v_rc;
    v_d := teste_golden_doc(v_caso, 'BALANCO', 'Campos Ltda.', '2025', 'campos');
    insert into golden_documento (rodada_id, documento_id, estrato, origem, incluido_por)
      values (v_rc, v_d, 'pdf_nativo', 'real', 'teste:golden');
    insert into golden_rotulo (rodada_id, documento_id, rotulador, tipo_correto)
      values (v_rc, v_d, 'rotulador:ana', 'BALANCO');

    -- A máquina devolveu: uma exata, uma dentro da tolerância, uma errada, uma
    -- que o rótulo não confere (e que ela AUTO-ACEITOU). E não devolveu a quarta.
    perform teste_golden_linha(v_d, 'Caixa e equivalentes', 1200, '2025', true);
    perform teste_golden_linha(v_d, 'Estoques',             3401, '2025', true);
    perform teste_golden_linha(v_d, 'Imobilizado',          9999, '2025', true);
    perform teste_golden_linha(v_d, 'Conta que ninguém rotulou', 77, '2025', true);

    insert into golden_campo (rodada_id, documento_id, rotulador, chave, periodo_coluna,
                              valor_correto, tolerancia)
      values (v_rc, v_d, 'rotulador:ana', 'Caixa e equivalentes', '2025', 1200, 0),
             (v_rc, v_d, 'rotulador:ana', 'Estoques',             '2025', 3400, 1),
             (v_rc, v_d, 'rotulador:ana', 'Imobilizado',          '2025', 5000, 1),
             -- Esta o rótulo afirma e a extração NÃO devolveu: perda silenciosa.
             (v_rc, v_d, 'rotulador:ana', 'Contas a receber',     '2025', 4200, 1);

    select n_exato, n_dentro_tolerancia, n_errado, n_ausente, acerto
      into v_exato, v_tol, v_errado, v_ausente, v_cob
      from fn_golden_campos(v_rc) where tipo = 'BALANCO';
    perform teste_assert_golden(v_exato = 1, '1 campo exato', format('%s', v_exato));
    perform teste_assert_golden(v_tol = 1, '1 campo dentro da tolerância (3401 contra 3400 ±1)',
      format('%s', v_tol));
    perform teste_assert_golden(v_errado = 1, '1 campo ERRADO (9999 contra 5000)',
      format('%s', v_errado));
    perform teste_assert_golden(v_ausente = 1,
      'e 1 campo AUSENTE, contado à parte: a linha não voltou, e isso é perda '
      'silenciosa, não valor errado', format('%s', v_ausente));

    perform teste_assert_golden(v_cob = 0.5,
      'o acerto é 2 de 4 — o ausente pesa como não-acerto, ele só não se confunde com erro',
      v_cob::text);

    -- A cobertura vai na direção contrária: das linhas AUTO-ACEITAS, quantas
    -- algum rótulo consegue conferir. É "a métrica que mais importa" segundo o
    -- cabeçalho do medir-auto-aceite.mts, e é a que o N2 aposta sem saber.
    select n_auto_aceito, n_auto_aceito_sem_rotulo, cobertura_conferida
      into v_auto, v_auto_s, v_cob from fn_golden_campos(v_rc) where tipo = 'BALANCO';
    perform teste_assert_golden(v_auto = 4, '4 linhas foram auto-aceitas', format('%s', v_auto));
    perform teste_assert_golden(v_auto_s = 1,
      'e 1 delas nenhum rótulo confere — virou fato sem humano nem teste olhar',
      format('%s', v_auto_s));
    perform teste_assert_golden(v_cob = 0.75,
      'cobertura conferida = 0.75', v_cob::text);
  end;

  -- ==========================================================================
  raise notice '--- 10. Classe A: o rótulo é o veredito humano da 0106 ---';
  -- ==========================================================================
  declare
    v_caso_a uuid;
    v_p1 uuid; v_p2 uuid; v_p3 uuid;
  begin
    v_caso_a := (fn_upsert_caso('Caso golden classe A 0126'))::uuid;

    -- Três divergências Classe A registradas, com três destinos diferentes.
    insert into reconciliacao (caso_id, tipo, classe, precondicoes_ok, resultado, divergencia_abs)
      values (v_caso_a, 'ativo_passivo_pl', 'A', true, 'divergente', 100),
             (v_caso_a, 'caixa_bp_fluxo',   'A', true, 'divergente', 200),
             (v_caso_a, 'duplicidade_de_rotulo', 'A', true, 'divergente', 300);

    insert into pendencia (caso_id, origem_estagio, tipo, severidade, motivo, estado,
                           resolvida_por, resolvida_em)
      values (v_caso_a, 'reconciliacao', 'divergencia_reconciliacao', 'importante',
              'reconciliacao:ativo_passivo_pl', 'rejeitada', 'rodrigo@oria', now())
      returning id into v_p1;
    insert into pendencia (caso_id, origem_estagio, tipo, severidade, motivo, estado,
                           resolvida_por, resolvida_em)
      values (v_caso_a, 'reconciliacao', 'divergencia_reconciliacao', 'importante',
              'reconciliacao:caixa_bp_fluxo', 'resolvida', 'rodrigo@oria', now())
      returning id into v_p2;
    -- Esta o SISTEMA resolveu: o sintoma sumiu. Ninguém disse que ela procedia.
    insert into pendencia (caso_id, origem_estagio, tipo, severidade, motivo, estado,
                           resolvida_por, resolvida_em)
      values (v_caso_a, 'reconciliacao', 'divergencia_reconciliacao', 'importante',
              'reconciliacao:duplicidade_de_rotulo', 'resolvida', 'sistema:reconciliacao', now())
      returning id into v_p3;

    v_med := fn_golden_classe_a(v_caso_a);
    perform teste_assert_golden((v_med->>'com_veredito_humano')::int = 2,
      'o denominador são os DOIS vereditos humanos', v_med::text);
    perform teste_assert_golden((v_med->>'falso_positivo')::int = 1,
      'a "rejeitada" conta como falso positivo do motor — é a definição da 0106', v_med::text);
    perform teste_assert_golden((v_med->>'resolvida_pelo_sistema_sem_veredito')::int = 1,
      'a que o sistema resolveu fica FORA dos dois lados, e é contada à parte',
      v_med::text);
    perform teste_assert_golden((v_med->>'taxa_falso_positivo')::numeric = 0.5,
      'taxa de falso-positivo = 1 de 2 = 0.5 — não 1 de 3', v_med::text);
    perform teste_assert_golden((v_med->>'nao_falso_positivo')::numeric = 0.5,
      'e ela entra invertida no critério, para "mais alto é melhor" valer para todos');
  end;

  -- ==========================================================================
  raise notice '--- 11. o determinístico não é cobrado, e o teto N1 recusa antes ---';
  -- ==========================================================================
  v_med := fn_golden_suficiente('completude_portao1', null);
  perform teste_assert_golden((v_med->>'aplica')::boolean = false
                          and (v_med->>'suficiente')::boolean,
    'estágio determinístico não é cobrado pela regra de ouro (Arquitetura do Sistema/1 Visão e Doutrina/01)', v_med::text);

  v_r := fn_mudar_dial('completude_portao1', 'N3', 'teste:golden',
                       'determinístico sobe sem golden set, e o teto permite N3');
  perform teste_assert_golden(coalesce((v_r->>'recusado')::boolean, false) = false,
    'e sobe de fato — cobrar rotulador para conferir se um zip abre não mediria nada', v_r::text);
  perform teste_assert_golden(v_r->>'base_do_nivel' = 'nao_se_aplica',
    'com base "nao_se_aplica": a garantia dele é teste, não concordância', v_r::text);
  perform fn_mudar_dial('completude_portao1', 'N2', 'teste:golden', 'restaurando o N2 da 0002');

  -- Teto N1: o portão da regra de ouro nunca é alcançado, porque o teto recusa
  -- primeiro. A ordem das guardas importa e é esta que Arquitetura do Sistema/1 Visão e Doutrina/01 exige.
  v_r := fn_mudar_dial('classificacao_contabil', 'N2', 'teste:golden', 'tentando com tudo em mãos',
                       null, v_boa);
  perform teste_assert_golden((v_r->>'recusado')::boolean
                          and v_r->>'motivo_recusa' like '%TETO%',
    'estágio de teto N1 é recusado pelo TETO, mesmo com rodada de golden set válida',
    v_r::text);

  -- ==========================================================================
  raise notice '--- 12. o estado final é o que as migrations deixaram ---';
  -- ==========================================================================
  -- Os cenários mexeram no dial, e os testes rodam todos no MESMO banco: um dial
  -- deixado fora do lugar faria qualquer teste futuro de auto-aceite passar ou
  -- reprovar por motivo errado. É a mesma disciplina do cenário 10 da dial.test.
  -- Restaura o estado que as MIGRATIONS deixaram, que desde a 0127 é N2/0,70 para
  -- a classificação — e não o N1 da semeadura da 0002.
  perform fn_mudar_dial('classificacao_doc_checklist', 'N2', 'teste:golden',
                        'restaurando o estado declarado pela 0127', 0.70,
                        null, 'arnês de teste restaurando o N2 da 0127; não é medição');
  perform fn_mudar_dial('extracao_linhas_financeiras', 'N2', 'teste:golden',
                        'restaurando o estado declarado pela 0041', 0.95,
                        null, 'arnês de teste restaurando o N2 da 0041; não é medição');

  select count(*) into v_n from estagio_autonomia
   where estagio = 'extracao_linhas_financeiras'
     and nivel_atual = 'N2' and limiar_auto_clear = 0.95 and base_do_nivel = 'declarada';
  perform teste_assert_golden(v_n = 1,
    'extracao_linhas_financeiras de volta em N2 / 0.95 / declarada');
  select count(*) into v_n from estagio_autonomia
   where estagio = 'classificacao_doc_checklist'
     and nivel_atual = 'N2' and limiar_auto_clear = 0.70 and base_do_nivel = 'declarada';
  perform teste_assert_golden(v_n = 1,
    'e classificacao_doc_checklist de volta em N2 / 0,70 / declarada (o estado da 0127)');

  raise notice 'TODOS OS TESTES DO GOLDEN SET PASSARAM';
end $$;

-- -----------------------------------------------------------------------------
-- APPEND-ONLY, EXECUTADO com o ROLE que o portal usa — e a forma da falha não é
-- a que se espera.
--
-- Fora do bloco anterior de propósito: `set role` dentro de um `do $$` que já
-- escreveu como owner não prova nada sobre o que o portal consegue fazer. Os três
-- roles do Supabase (`anon`, `authenticated`, `service_role`) e o
-- `alter default privileges ... grant all on tables` são montados pelo próprio
-- `run.sh`, replicando a produção — então `authenticated` TEM privilégio de
-- tabela para DELETE, e o RLS é o único freio.
--
-- O QUE ISSO MUDA NO TESTE, e é o motivo deste comentário existir: sem política
-- de RLS para um comando, o Postgres NÃO levanta `insufficient_privilege` — ele
-- filtra as linhas alcançáveis para zero, e o `delete` volta com sucesso e
-- "DELETE 0". Um teste que espere exceção passa por não acontecer nada e falha
-- com o append-only funcionando. Então o que se afirma aqui é o EFEITO: a linha
-- continua lá, e o rótulo continua dizendo o que dizia.
--
-- A forma da política também é afirmada, como a `perguntas.test.sql` (#8) faz
-- para o `caso_pergunta`: as duas checagens pegam coisas diferentes — a de forma
-- pega uma política de UPDATE acrescentada por descuido, a de efeito pega o dia
-- em que alguém ligar `bypassrls` ou trocar o role da conexão.
-- -----------------------------------------------------------------------------
do $$
declare
  v_antes  int;
  v_depois int;
  v_n      int;
begin
  select count(*) into v_antes from golden_rotulo;
  perform teste_assert_golden(v_antes > 0,
    'há rótulo gravado para o teste de append-only ter o que tentar apagar',
    format('%s', v_antes));

  set local role authenticated;
  delete from golden_rotulo;
  update golden_rotulo set tipo_correto = 'MENTIRA';
  delete from golden_campo;
  delete from golden_documento;
  reset role;

  select count(*) into v_depois from golden_rotulo;
  perform teste_assert_golden(v_depois = v_antes,
    'como authenticated, o delete em golden_rotulo não apaga nada — RLS sem política de DELETE',
    format('antes %s, depois %s', v_antes, v_depois));

  select count(*) into v_n from golden_rotulo where tipo_correto = 'MENTIRA';
  perform teste_assert_golden(v_n = 0,
    'e o update não reescreve rótulo nenhum — o que autorizou uma subida de dial não se edita',
    format('%s linha(s) reescrita(s)', v_n));

  select count(*) into v_n from pg_policies
   where tablename in ('golden_documento', 'golden_rotulo', 'golden_campo')
     and cmd in ('ALL', 'UPDATE', 'DELETE');
  perform teste_assert_golden(v_n = 0,
    'e nenhuma das três tabelas de rótulo tem política de ALL/UPDATE/DELETE',
    format('achou %s política(s) permissiva(s)', v_n));

  raise notice 'TODOS OS TESTES DE APPEND-ONLY DO GOLDEN SET PASSARAM';
end $$;
