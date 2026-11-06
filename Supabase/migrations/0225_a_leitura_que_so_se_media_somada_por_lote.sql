-- =============================================================================
-- 0225 — A LEITURA QUE SÓ SE MEDIA SOMADA POR LOTE: a cobertura passa a ser gravada por DOCUMENTO (linha de base da P4)
-- (Troca a assinatura de fn_registrar_campos_extraidos (drop + create: ganha o último parâmetro `p_medicao jsonb default null`, corpo da 0204 inteiro + a medição no evento);
--  cria 1 função de leitura, fn_linha_de_base_extracao (SECURITY INVOKER, somente leitura); acrescenta 5 requisitos à sonda. Sem tabela, sem backfill, sem GRANT de tabela.
--  Reaplicável: drop if exists + create da função de gravação (ACL refeita), create or replace na de leitura, upsert dos requisitos.)
--
-- O DEFEITO. A cobertura da leitura (contas que o texto do documento tinha × linhas que a IA devolveu) só era gravada SOMADA por lote
-- (`lote_execucao.contas_nos_documentos` / `contas_extraidas` / `cobertura`, montada no nó "Resumo de Custo" de N8N/build-workflow.mjs). Por
-- documento ela se perdia, e a P4 precisa comparar documento a documento ANTES × DEPOIS da mudança de leitura. Medido em PRODUÇÃO (só leitura):
-- lotes com cobertura 1,31, 1,43 e 2,25 — acima de 1 a régua conta errado — e nenhuma forma de saber em QUAL documento.
--
-- A CAUSA. O número nasce no n8n, por documento, e some na soma do lote; o banco nunca o recebeu. Já existia um ponto por onde TODO documento passa
-- uma vez, `fn_registrar_campos_extraidos` (nó "Gravar Campos (Sombra)"), que grava o evento `extracao_sombra` por documento_versao — mas sem a medição.
--
-- A CORREÇÃO (escada, degrau 2: estende o que existe, não cria tabela).
--   1. `fn_registrar_campos_extraidos` ganha `p_medicao jsonb default null` (ÚLTIMO parâmetro). O evento `extracao_sombra` passa a levar `medicao`:
--      o objeto como veio (esperado do n8n: contas_no_documento, linhas_devolvidas, contas_distintas, blocos, blocos_planejados, custo_usd, tokens;
--      nenhum campo é validado: o n8n é a fonte). Três estados DISTINTOS (regras 1 e 7): objeto = mediu; `medicao` nula EXPLÍCITA no evento = o n8n é anterior
--      a esta migration ou não mediu (NUNCA se confunde com medição zerada); não-objeto = grava `medicao_invalida` com o tipo recebido, em vez de descartar calado.
--      Mudar a assinatura criaria SOBRECARGA ambígua se a antiga ficasse (a chamada do n8n, com argumentos nomeados, passaria a ser ambígua ou cairia na velha), por isso
--      drop da antiga + create da nova. Preserva o corpo vigente (0204, reemitido inteiro), SECURITY INVOKER, o comentário e a ACL (REVOKE de PUBLIC; EXECUTE para
--      authenticated e service_role — o estado medido em Supabase/schema.sql). Chamadores (grep em Supabase/ N8N/ portal/src/): o nó do n8n
--      (`fn_registrar_campos_extraidos($1::uuid, $2::jsonb, p_falha_motivo=>$3::text, p_tem_dado_financeiro=>$4::boolean)`: continua valendo, p_medicao assume o default),
--      N8N/lib/extract.mjs e os testes SQL (todos de até 5 argumentos), Supabase/conferir/conferir_chamadas.sql (gerado do nó). Nenhuma função SQL a chama: só comentários citam o nome.
--   2. `fn_linha_de_base_extracao(p_caso_id)`: UMA linha por documento_versao do mandato, com nome, tipo, n_campos, falha_motivo, a medição do ÚLTIMO evento daquela
--      versão (contas_no_documento, linhas_devolvidas, cobertura = linhas/contas quando contas > 0, senão NULL com `cobertura_motivo`), as pendências ABERTAS da
--      origem extração por tipo e `extracao_rodou` (há evento de extração?). Documento sem evento ≠ documento que rodou e não achou nada (regra 7): a coluna
--      diz qual dos dois é. Pendência é por documento e versão é N por documento: a pendência é agregada por documento_id ANTES da junção, para não multiplicar linhas.
--      Pela mesma razão ela aparece SÓ na linha da versão mais nova (nas outras NULL + `pendencias_motivo`): repetida em toda versão, a v1 limpa mostraria a falha da v2 e um sum() contaria em dobro.
--      `n_campos` é o acumulado em campo_extraido; `campos_ultimo_evento` e `versao_medicao` vêm do último evento (comparáveis a `linhas_devolvidas`).
--      SECURITY INVOKER: a RLS de documento/documento_versao/campo_extraido/evento_auditoria/pendencia vale — quem não lê o mandato recebe ZERO linhas (não distingue
--      mandato alheio de mandato inexistente; a função não faz essa distinção de propósito).
--   NÃO muda o n8n: enquanto o nó não passar `p_medicao`, TODO evento novo sai com `medicao` nula e a linha de base diz `sem_medicao` — é o estado honesto, e é ele que
--   a sonda não pode confundir com "medido". O n8n (nó "Gravar Campos (Sombra)" + o que monta a medição por documento) é a fatia seguinte.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/linha_de_base_da_leitura.test.sql — 61 asserts (EXECUCOES=61 na linha final), medidos em 06/11/2026 com `PGOPTIONS='-c p4.medindo=on'`
-- (o assert vira `raise warning` e CONTA; voltou para `raise exception` e o log inteiro foi lido atrás de `FALHOU:`). Cada variante foi APLICADA ao banco migrado
-- (conferido: a variante aplicou com rc 0 e a linha final trouxe EXECUCOES=61) e UMA guarda desligada por vez; depois de cada uma a migration intacta foi reaplicada.
-- Controle (migration intacta): 0 dos 61 reprovam, antes e depois das variantes.
--   * gravação que DESCARTA a medição (v_medicao sempre nula): 9 dos 61 asserts reprovam; nula OMITIDA em vez de explícita (a chave some): 4 dos 61 asserts;
--     medicao_invalida descartada: 4 dos 61 asserts; JSON null tratado como inválido: 1 dos 61 asserts; ACL com EXECUTE para PUBLIC (sem o revoke): 1 dos 61 asserts;
--     sobrecarga da assinatura antiga de volta: o teste ABORTA na chamada nomeada do n8n ("function ... is not unique"), antes de contar — a chamada do n8n quebraria em produção;
--   * leitura: pendência NÃO agregada por documento (multiplica linhas): 3 dos 61 asserts; cobertura truncada em 1: 2 dos 61 asserts; cobertura arredondada a inteiro: 2 dos 61 asserts;
--     zero FABRICADO quando o documento não tem contas: 5 dos 61 asserts; primeiro evento da versão em vez do último: 5 dos 61 asserts; pendência de qualquer origem: 1 dos 61 asserts;
--     pendência resolvida conta: 1 dos 61 asserts; SECURITY DEFINER (a RLS some): 2 dos 61 asserts; extracao_rodou sempre verdadeiro: 3 dos 61 asserts;
--     sem o motivo extracao_nao_rodou: 3 dos 61 asserts; medicao_invalida vira sem_medicao: 1 dos 61 asserts; medicao_incompleta some: 1 dos 61 asserts;
--     a versão 2 herda o evento da versão 1: 2 dos 61 asserts;
--   * (revisão) pendência repetida em TODA versão do documento (a v1 limpa mostra a falha da v2; sum() conta em dobro): 2 dos 61 asserts; sem o pendencias_motivo: 1 dos 61 asserts;
--     "versão mais nova" lida como a mais velha: 4 dos 61 asserts; campos_ultimo_evento igual ao acumulado n_campos: 1 dos 61 asserts; versao_medicao sempre nula: 1 dos 61 asserts;
--     policy de leitura de evento_auditoria que esconde o evento da Analista (tudo viraria "não rodou" com a suíte verde): 2 dos 61 asserts;
--   * sonda: requisito medicao_gravada_no_evento fora do catálogo: 3 dos 61 asserts; requisito linha_de_base_funcao fora do catálogo: 2 dos 61 asserts.
-- NÃO MEDIDO, e dito: (0) "o catálogo declara a 0225" não tem variante: um gatilho da plataforma ("o marcador já está em 0225 e não regride") impede desfazer a cobertura, então o assert
-- é só o estado esperado (o portão do run.sh cobra a cobertura); (1) a RLS contra um Analista de verdade em PRODUÇÃO (a suíte usa o papel `authenticated` do banco de teste);
-- (2) a latência de fn_linha_de_base_extracao em lote grande (não medida: um lateral por versão sobre idx_evento_entidade_ref); (3) o grant para `supabase_read_only_user`: o papel não existe
-- no banco de teste, então não há assert; conferi à mão, criando o papel no banco descartável e reaplicando a migration (o EXECUTE aparece), e removi o papel em seguida.
--
-- O QUE AINDA PRECISA SER APLICADO À MÃO: esta migration (rodar COMO `postgres`; ver Supabase/README.md). Escrita ≠ aplicada: quem responde é a sonda,
-- `select chave, presente, detalhe from fn_instalacao_conferir() where migration = '0225' and not presente;` — ZERO linhas.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. A GRAVAÇÃO: o evento por documento passa a levar a medição
-- ---------------------------------------------------------------------------
-- Reemitida INTEIRA a partir do corpo da 0204 (NÃO por replace de texto). Mudanças: o parâmetro novo, duas variáveis, e o evento `extracao_sombra`.
drop function if exists fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text, boolean);

create or replace function fn_registrar_campos_extraidos(p_documento_versao_id uuid, p_campos jsonb, p_nivel nivel_autonomia DEFAULT 'N0'::nivel_autonomia, p_falha_motivo text DEFAULT NULL::text, p_tem_dado_financeiro boolean DEFAULT NULL::boolean, p_medicao jsonb DEFAULT NULL::jsonb)
 RETURNS integer
 LANGUAGE plpgsql
as $$
declare
  v_count            int := 0;
  v_item             jsonb;
  v_valor             numeric;
  v_confianca          numeric;
  v_status_aceite      text;
  v_aceito_por         text;
  v_aceito_em          timestamptz;
  v_n_auto_aceitos     int := 0;
  v_documento_id       uuid;
  v_caso_id            uuid;
  v_nome_original      text;
  v_pendencia_id       uuid;
  v_guarda_disparou    boolean := false;
  v_nivel_dial         nivel_autonomia;
  v_limiar             numeric;
  v_auto_permitido     boolean;
  v_n_excluidas        int := 0;
  v_g                  jsonb;
  v_tipo               text;
  v_secao              text;
  v_inferida           boolean;
  v_herdadas           jsonb;
  v_medicao            jsonb;
  v_invalida           jsonb;
begin
  -- 0203: o tipo do documento entra na inferência da seção (fn_secao_canonica_da_secao_bruta).
  select d.tipo_taxonomia into v_tipo
  from documento_versao dv join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;

  select ea.nivel_atual, ea.limiar_auto_clear into v_nivel_dial, v_limiar
  from estagio_autonomia ea where ea.estagio = 'extracao_linhas_financeiras';
  v_auto_permitido := v_nivel_dial in ('N2', 'N3') and v_limiar is not null;

  if p_campos is not null and jsonb_typeof(p_campos) = 'array' then
    for v_item in select * from jsonb_array_elements(p_campos)
    loop
      v_valor := case when (v_item->>'valor_num') ~ '^-?\d+(\.\d+)?$' then (v_item->>'valor_num')::numeric else null end;
      v_confianca := case when (v_item->>'confianca') ~ '^-?\d+(\.\d+)?$' then (v_item->>'confianca')::numeric else null end;

      -- 0203: a IA devolve `secao_canonica` nula em parte das linhas (medido em produção em 05/10/2026: 136 de
      -- 724 numa DRE) e a linha some de receita/custo/giro. Só quando a IA NÃO deu (nulo ou em branco) a seção
      -- é inferida do texto da seção bruta; o que veio NUNCA é sobrescrito. A linha diz que foi inferida.
      v_secao := v_item->>'secao_canonica';
      v_inferida := false;
      if nullif(btrim(v_secao), '') is null then
        v_secao := fn_secao_canonica_da_secao_bruta(v_item->>'secao', v_tipo);
        v_inferida := v_secao is not null;
      end if;

      v_status_aceite := 'pendente';
      v_aceito_por := null;
      v_aceito_em := null;
      if v_auto_permitido and v_confianca is not null and v_confianca >= v_limiar then
        v_n_auto_aceitos := v_n_auto_aceitos + 1;
      end if;

      insert into campo_extraido
        (documento_versao_id, chave, valor_texto, valor_num, unidade, moeda, confianca,
         origem_pagina, origem_linha, ordem, nivel_autonomia, secao, secao_canonica, secao_canonica_inferida, entidade_coluna, periodo_coluna,
         status_aceite, aceito_por, aceito_em)
      values (
        p_documento_versao_id,
        coalesce(v_item->>'chave', '(sem rótulo)'),
        v_item->>'valor_texto',
        v_valor,
        v_item->>'unidade',
        v_item->>'moeda',
        v_confianca,
        case when (v_item->>'origem_pagina') ~ '^\d+$' then (v_item->>'origem_pagina')::int else null end,
        v_item->>'origem_linha',
        case when (v_item->>'ordem') ~ '^\d+$' then (v_item->>'ordem')::int else null end,
        p_nivel,
        v_item->>'secao',
        v_secao,
        v_inferida,
        v_item->>'entidade_coluna',
        v_item->>'periodo_coluna',
        v_status_aceite,
        v_aceito_por,
        v_aceito_em
      );
      v_count := v_count + 1;
    end loop;
  end if;

  -- 0204: a seção que nem a IA nem o nome da seção bruta deram, herdada da ÁRVORE DO PRÓPRIO DOCUMENTO. Precisa do
  -- documento inteiro, por isso depois do laço de inserção e ANTES de tudo o que lê secao_canonica (guardas, completude,
  -- classificação contábil). O n8n grava UMA vez por documento (nó "Gravar Campos (Sombra)", depois de "Juntar Blocos"),
  -- então este é o ponto em que o documento está completo; se um dia a gravação for por bloco, a função é idempotente e
  -- sobre a versão inteira, e a última chamada converge. Não muda a assinatura: sem reimportar workflow.
  v_herdadas := fn_herdar_secao_pela_arvore(p_documento_versao_id);
  if (v_herdadas->>'linhas')::int > 0 or (v_herdadas->>'conflitos')::int > 0 then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:n8n', 'secao_herdada_pela_arvore', 'documento_versao:'||p_documento_versao_id, v_herdadas);
  end if;

  -- 0225: a MEDIÇÃO da leitura deste documento (o que o n8n contou: contas que o texto tinha, linhas que a IA devolveu, blocos, custo)
  -- entra no mesmo evento, como veio. Três estados DISTINTOS, porque "não mediu" e "mediu zero" não podem ter a mesma cara (regra 1 e 7):
  -- objeto = o n8n mediu; chave `medicao` nula = o n8n era anterior à 0225 ou não mediu; tipo que não é objeto = defeito do chamador,
  -- gravado na chave `medicao_invalida` com o tipo recebido, em vez de descartado calado. Nenhum campo é validado aqui: o n8n é a fonte.
  v_medicao  := case when p_medicao is not null and jsonb_typeof(p_medicao) = 'object' then p_medicao else null end;
  v_invalida := case when p_medicao is not null and jsonb_typeof(p_medicao) not in ('object', 'null')
                     then jsonb_build_object('medicao_invalida', jsonb_typeof(p_medicao)) else '{}'::jsonb end;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'extracao_sombra', 'documento_versao:'||p_documento_versao_id,
            jsonb_build_object('campos', v_count, 'nivel', p_nivel, 'falha_motivo', p_falha_motivo,
                               'tem_dado_financeiro', p_tem_dado_financeiro, 'auto_aceitos', v_n_auto_aceitos,
                               'medicao', v_medicao) || v_invalida);

  select d.id, d.caso_id, dv.nome_original into v_documento_id, v_caso_id, v_nome_original
  from documento_versao dv join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;

  if v_documento_id is null then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:n8n', 'extracao_orfa', 'documento_versao:'||coalesce(p_documento_versao_id::text,'null'),
              jsonb_build_object('campos_descartados', v_count, 'falha_motivo', p_falha_motivo,
                                 'porque', 'documento_versao inexistente: campos e motivo nao tinham onde ser gravados'));
    raise warning 'fn_registrar_campos_extraidos: documento_versao % inexistente; % campo(s) e o motivo "%" foram descartados',
      p_documento_versao_id, v_count, coalesce(p_falha_motivo, '(sem motivo)');
    return v_count;
  end if;

  v_g := fn_avaliar_guardas_extracao(p_documento_versao_id);

  if v_count > 0 then
    -- ----- Sinal 1 (0013/0022/0034): mesmo valor material repetido em contas ---
    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:padrao_suspeito:' || v_documento_id and estado <> 'resolvida'
      limit 1;
    if (v_g->>'padrao_suspeito')::boolean then
      v_guarda_disparou := true;
      if v_pendencia_id is null then
        insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
          values (v_caso_id, 'extracao', 'extracao_padrao_suspeito', 'importante', true,
            format('%s contas diferentes, na MESMA coluna, vieram com o MESMO valor material (%s) — padrão '
                   'típico de fabricação/alucinação, não de dado real. Conferir contra o arquivo original. '
                   'Contas: %s',
                   v_g->>'n_contas_repetindo', round((v_g->>'valor_repetido')::numeric, 2),
                   array_to_string(array(select jsonb_array_elements_text(v_g->'rotulos_repetindo')), '; ')),
            v_documento_id, 'extracao:padrao_suspeito:' || v_documento_id);
      end if;
    elsif v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
        where id = v_pendencia_id;
    end if;

    -- ----- Sinal 2 (0013): parcela relevante das linhas com confiança baixa ----
    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:baixa_confianca:' || v_documento_id and estado <> 'resolvida'
      limit 1;
    if (v_g->>'baixa_confianca')::boolean then
      v_guarda_disparou := true;
      if v_pendencia_id is null then
        insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
          values (v_caso_id, 'extracao', 'extracao_baixa_confianca', 'importante', true,
            format('%s de %s linhas extraídas vieram com confiança abaixo de 70%%. Revisar antes de aceitar.',
                   v_g->>'n_baixa_confianca', v_count),
            v_documento_id, 'extracao:baixa_confianca:' || v_documento_id);
      end if;
    elsif v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
        where id = v_pendencia_id;
    end if;
  end if;

  -- ----- Sinal 3 (0016/0029, unidade corrigida por 0111) ---------------------
  -- "veio vazia" só é sinal de FALHA quando ninguém disse o contrário. Um
  -- chamador antigo (workflow não reimportado) manda `p_tem_dado_financeiro`
  -- null, e o comportamento é IDÊNTICO ao de antes desta migration
  -- (coalesce(null, true) = true). Só o diagnóstico da própria chamada, com
  -- `false` explícito, prova que zero linhas era o resultado certo.
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'extracao:falhou:' || v_documento_id and estado <> 'resolvida'
    limit 1;
  if p_falha_motivo is not null or (v_count = 0 and coalesce(p_tem_dado_financeiro, true)) then
    v_guarda_disparou := true;
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'extracao', 'extracao_falhou', 'importante', true,
          fn_descricao_extracao_falhou(v_nome_original, v_count, p_falha_motivo),
          v_documento_id, 'extracao:falhou:' || v_documento_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
      where id = v_pendencia_id;
  end if;

  -- ----- Auto-aceite (0029): DEPOIS das guardas, nunca antes -----------------
  --
  -- 0141: E A TRILHA PASSA A DIZER QUANTO O LIMIAR FILTROU, porque medido em
  -- 24/08 ele nunca filtrou nada. Em 15.030 linhas gravadas por este sistema, a
  -- confiança auto-reportada assumiu TRÊS valores — 0,95, 0,99 e 1 — e o limiar
  -- de `extracao_linhas_financeiras` é 0,95. O limiar é exatamente o PISO do que
  -- o modelo já emitiu: `confianca >= v_limiar` é satisfeito por toda linha que
  -- já existiu, e 14.470 das 15.030 foram auto-aceitas (as outras 560 foram
  -- barradas por GUARDA, não por confiança).
  --
  -- A guarda de baixa confiança (Sinal 2, limiar 0,70) nunca disparou pelo mesmo
  -- motivo: zero linhas abaixo de 0,70 em toda a história do banco.
  --
  -- Isto NÃO muda comportamento — decisão do dono, 24/08. O que muda é que a
  -- decisão passa a registrar quantas linhas o limiar excluiu. Quando exclui
  -- zero, ela diz isso com todas as letras, porque um portão que aprova tudo e
  -- não declara que aprovou tudo é pior que portão nenhum: ele parece funcionar.
  v_n_excluidas := greatest(v_count - v_n_auto_aceitos, 0);
  if v_n_auto_aceitos > 0 and not v_guarda_disparou then
    update campo_extraido
      set status_aceite = 'aceito',
          aceito_por = format('sistema:auto_aceite (dial %s, limiar %s, sem guarda disparada)',
                              v_nivel_dial, v_limiar),
          aceito_em = now()
      where documento_versao_id = p_documento_versao_id
        and confianca >= v_limiar
        and status_aceite = 'pendente';

    insert into decisao (caso_id, tipo, autor, motivo, payload)
      values (v_caso_id, 'aprovacao', 'sistema:auto_aceite',
        format('%s linha(s) auto-aceitas na extração de "%s" — dial %s, limiar %s, nenhuma guarda disparou. %s',
               v_n_auto_aceitos, coalesce(v_nome_original, '?'), v_nivel_dial, v_limiar,
               case when v_n_excluidas = 0
                 then format('O limiar NAO excluiu nenhuma das %s linhas: a confiança auto-reportada não '
                             'discriminou nada nesta versão, e o que barra linha aqui são as guardas.', v_count)
                 else format('O limiar deixou %s de %s linha(s) pendentes.', v_n_excluidas, v_count)
               end),
        jsonb_build_object('documento_id', v_documento_id, 'documento_versao_id', p_documento_versao_id,
                           'n_auto_aceitos', v_n_auto_aceitos,
                           'n_excluidas_pelo_limiar', v_n_excluidas,
                           'limiar_discriminou', v_n_excluidas > 0));
  elsif v_n_auto_aceitos > 0 then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:auto_aceite', 'auto_aceite_suprimido', 'documento_versao:'||p_documento_versao_id,
              jsonb_build_object('n_elegiveis', v_n_auto_aceitos,
                                 'n_excluidas_pelo_limiar', v_n_excluidas,
                                 'limiar_discriminou', v_n_excluidas > 0,
                                 'porque', 'guarda de extracao disparou; linhas seguem pendentes de revisao humana'));
  end if;
  perform fn_recomputar_completude(v_caso_id);

  -- 0128: A CLASSIFICAÇÃO CONTÁBIL RODA AQUI, e o lugar não é arbitrário.
  --
  -- Este é o único ponto do pipeline que roda DEPOIS da extração — é o mesmo
  -- motivo pelo qual a 0036 pôs a recomputação de completude nesta linha, e o
  -- comentário dela explica: `Registrar Documento` liga em paralelo para a
  -- completude e para a extração, então nada que dependa das linhas extraídas pode
  -- morar antes daqui.
  --
  -- Pendurar aqui também é o que evita REIMPORTAR o workflow: um nó novo no canvas
  -- exigiria isso do dono, e o n8n executa o JSON importado (merge não reimporta).
  --
  -- E é seguro por construção: em N0 a função só escreve em campo_classe_sugerida.
  -- Não abre pendência, não toca em campo_extraido, não entra em caminho de export.
  -- O pior caso dela é não fazer nada — se o dial não tiver a linha do estágio, ela
  -- devolve zero e segue.
  perform fn_classificar_contabil(p_documento_versao_id);

  return v_count;
end;
$$;


comment on function fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text, boolean, jsonb) is
  'Grava campos extraídos e roda as três guardas (0043: fn_avaliar_guardas_extracao). Sinal 3 ("veio vazia") só dispara extracao_falhou quando p_tem_dado_financeiro não é explicitamente false — 0111: documento sem valor monetário por natureza (certidão, organograma, parecer de auditoria) não é falha de extração. 0203: quando a IA não dá secao_canonica, ela é inferida do texto da seção bruta (fn_secao_canonica_da_secao_bruta) e a linha grava secao_canonica_inferida = true; o que a IA deu nunca é sobrescrito. 0204: depois do laço, a seção que ainda falta é herdada pela árvore do próprio documento (fn_herdar_secao_pela_arvore). 0225: o evento extracao_sombra leva a chave medicao (o objeto de p_medicao como veio; nula explícita quando o chamador não mediu; medicao_invalida quando o tipo não é objeto) — a linha de base da leitura por documento (fn_linha_de_base_extracao).';

-- A ACL do que o drop levou: o estado medido em Supabase/schema.sql era REVOKE de PUBLIC + EXECUTE para authenticated e service_role.
revoke all on function fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text, boolean, jsonb) from public;
grant execute on function fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text, boolean, jsonb) to authenticated, service_role;
-- Produção tem EXECUTE também para `supabase_read_only_user` (concessão avulsa da plataforma: 237 de 271 funções de public têm), e o drop levou a da assinatura antiga.
-- Para a cópia ser fiel o grant é refeito — mas o papel NÃO existe no banco local de teste (nem em instalação nova), por isso só se ele existir.
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    execute 'grant execute on function fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text, boolean, jsonb) to supabase_read_only_user';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. A LEITURA: a linha de base por documento (somente leitura, respeita a RLS de quem chama)
-- ---------------------------------------------------------------------------
-- Por que a cobertura sai NULL com motivo, e não 0: contas_no_documento = 0 (o texto não tinha conta) e "o n8n não mediu" são coisas diferentes de
-- "a IA devolveu tudo" — um 0 fabricado aqui seria indistinguível de uma medição (regra 1). `cobertura_motivo` é NULL exatamente quando a cobertura existe.
-- NÃO é arredondada: a P4 compara antes × depois e arredondar esconderia a diferença pequena. Passa de 1 quando a IA devolve mais linhas que contas contadas
-- (a régua conta errado: medido em produção 1,31 / 1,43 / 2,25 por lote) — a função NÃO trunca em 1, porque truncar esconderia exatamente esse defeito.
-- A assinatura de RETORNO cresceu (campos_ultimo_evento, versao_medicao, pendencias_motivo): create or replace não troca colunas de retorno, por isso o drop (reaplicável).
-- `n_campos` é o ACUMULADO em campo_extraido da versão: reprocessar a MESMA versão soma as gravações (medido em produção: uma versão com 2 eventos, de 32 e 24 campos, dá n_campos 56)
-- e NÃO é comparável a `linhas_devolvidas`, que vem só do último evento; `campos_ultimo_evento` é o que o último evento gravou, e é com ele que se compara.
-- A pendência é do DOCUMENTO, não da versão: ela aparece só na linha da versão MAIS NOVA do documento (n_versao máximo); nas demais fica NULL com pendencias_motivo preenchido.
-- Repetir em toda versão faria a v1 limpa mostrar a falha da v2 e um sum() contar 2 onde há 1 (produção: 12 documentos com mais de uma versão).
drop function if exists fn_linha_de_base_extracao(uuid);
create function fn_linha_de_base_extracao(p_caso_id uuid)
returns table (
  documento_id            uuid,
  documento_versao_id     uuid,
  n_versao                integer,
  nome_original           text,
  tipo_taxonomia          text,
  n_campos                bigint,
  extracao_rodou          boolean,
  extraido_em             timestamptz,
  falha_motivo            text,
  contas_no_documento     numeric,
  linhas_devolvidas       numeric,
  cobertura               numeric,
  cobertura_motivo        text,
  pendencias_extracao_falhou           integer,
  pendencias_extracao_padrao_suspeito  integer,
  campos_ultimo_evento    integer,
  versao_medicao          text,
  pendencias_motivo       text
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with pend as materialized (
    -- agregada por documento ANTES de juntar às versões (versão é N por documento: junto direto multiplicaria as linhas)
    select p.documento_id,
           count(*) filter (where p.tipo = 'extracao_falhou')::integer           as falhou,
           count(*) filter (where p.tipo = 'extracao_padrao_suspeito')::integer  as suspeito
      from pendencia p
     where p.caso_id = p_caso_id and p.origem_estagio = 'extracao' and p.estado <> 'resolvida'
       and p.documento_id is not null
     group by p.documento_id
  ),
  base as (
    select d.id as documento_id, dv.id as versao_id, dv.n_versao, dv.nome_original, d.tipo_taxonomia,
           (select count(*) from campo_extraido ce where ce.documento_versao_id = dv.id) as n_campos,
           ev.criado_em as extraido_em, ev.depois as depois,
           dv.n_versao = max(dv.n_versao) over (partition by d.id) as e_a_mais_nova
      from documento d
      join documento_versao dv on dv.documento_id = d.id
      left join lateral (
        select ea.criado_em, ea.depois
          from evento_auditoria ea
         where ea.acao = 'extracao_sombra' and ea.entidade_ref = 'documento_versao:' || dv.id::text
         order by ea.criado_em desc, ea.id desc
         limit 1) ev on true
     where d.caso_id = p_caso_id
  ),
  med as (
    select b.*,
           case when b.depois is null then null
                when jsonb_typeof(b.depois->'medicao') = 'object' then b.depois->'medicao' end as m,
           case when b.depois->>'medicao_invalida' is not null then 'medicao_invalida' end as invalida
      from base b
  ),
  num as (
    select m.*,
           case when (m.m->>'contas_no_documento') ~ '^-?\d+(\.\d+)?$' then (m.m->>'contas_no_documento')::numeric end as contas,
           case when (m.m->>'linhas_devolvidas')   ~ '^-?\d+(\.\d+)?$' then (m.m->>'linhas_devolvidas')::numeric   end as linhas
      from med m
  )
  select n.documento_id, n.versao_id, n.n_versao, n.nome_original, n.tipo_taxonomia, n.n_campos,
         n.depois is not null,
         n.extraido_em,
         n.depois->>'falha_motivo',
         n.contas, n.linhas,
         case when n.contas > 0 and n.linhas is not null then n.linhas / n.contas end,
         case when n.depois is null                  then 'extracao_nao_rodou'
              when n.invalida is not null            then 'medicao_invalida'
              when n.m is null                       then 'sem_medicao'
              when n.contas is null or n.linhas is null then 'medicao_incompleta'
              when n.contas <= 0                     then 'documento_sem_contas' end,
         case when n.e_a_mais_nova then coalesce(pd.falhou, 0) end,
         case when n.e_a_mais_nova then coalesce(pd.suspeito, 0) end,
         case when (n.depois->>'campos') ~ '^\d+$' then (n.depois->>'campos')::integer end,
         n.m->>'versao_medicao',
         case when not n.e_a_mais_nova then 'pendencia_e_do_documento_ver_versao_mais_nova' end
    from num n
    left join pend pd on pd.documento_id = n.documento_id
   order by n.nome_original, n.n_versao, n.versao_id
$$;

comment on function fn_linha_de_base_extracao(uuid) is
  '0225: linha de base da leitura POR DOCUMENTO (P4, comparar antes × depois). Uma linha por documento_versao do mandato: n_campos, falha_motivo, a medição do ÚLTIMO evento extracao_sombra da versão (contas_no_documento, linhas_devolvidas, cobertura = linhas/contas quando contas > 0 — sem arredondar nem truncar em 1), e as pendências ABERTAS da origem extração por tipo — do DOCUMENTO, então só na linha da versão mais nova (nas outras NULL, com pendencias_motivo). n_campos é o ACUMULADO em campo_extraido da versão (reprocessar soma as gravações); campos_ultimo_evento é o que o último evento gravou, comparável a linhas_devolvidas; versao_medicao é a versão da medição que o n8n declarou (separa eventos medidos por versões diferentes). extracao_rodou = existe evento de extração (documento sem evento NÃO é documento que rodou e não achou nada). cobertura_motivo é NULL só quando a cobertura existe; senão diz por quê: extracao_nao_rodou | medicao_invalida | sem_medicao (n8n anterior à 0225) | medicao_incompleta | documento_sem_contas. SECURITY INVOKER: a RLS vale e quem não lê o mandato recebe zero linhas. Somente leitura.';

revoke all on function fn_linha_de_base_extracao(uuid) from public;
grant execute on function fn_linha_de_base_extracao(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. A SONDA
-- ---------------------------------------------------------------------------
-- Marcadores em CÓDIGO (conferidos 1× por position no corpo publicado; pg_get_functiondef traz comentário, por isso os trechos abaixo não aparecem em comentário).
-- O primeiro é a ASSINATURA que pg_get_functiondef regenera: a função da 0204 (sem o parâmetro) não o tem, e só a nova o tem.
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('medicao_parametro_na_gravacao', '0225', 'corpo', 'fn_registrar_campos_extraidos', 'p_medicao jsonb DEFAULT NULL::jsonb', null,
   'A assinatura nova de fn_registrar_campos_extraidos (último parâmetro p_medicao). Corpo anterior = o n8n não tem onde entregar a medição por documento e a P4 volta a comparar só lotes somados.',
   'importante', 1040),
  ('medicao_gravada_no_evento', '0225', 'corpo', 'fn_registrar_campos_extraidos', '''medicao'', v_medicao', null,
   'O evento extracao_sombra leva a chave medicao (objeto, ou nula EXPLÍCITA quando o chamador não mediu). Tirada a gravação, o parâmetro existe e a medição some sem erro.',
   'importante', 1041),
  ('medicao_invalida_nao_some', '0225', 'corpo', 'fn_registrar_campos_extraidos', '''medicao_invalida'', jsonb_typeof(p_medicao)', null,
   'Medição que não é objeto é gravada como medicao_invalida com o tipo recebido, não descartada calada (regra 1). Sem isto um n8n que manda texto parece um n8n que não mediu.',
   'importante', 1042),
  ('linha_de_base_funcao', '0225', 'funcao', 'fn_linha_de_base_extracao', null, null,
   'A função de leitura da linha de base da leitura por documento (P4). Ausente = a 0225 não foi aplicada e a cobertura volta a existir só somada por lote.',
   'importante', 1043),
  ('linha_de_base_motivo_da_cobertura', '0225', 'corpo', 'fn_linha_de_base_extracao', '''sem_medicao''', null,
   'O corpo que diz POR QUE a cobertura de um documento é nula (extracao_nao_rodou | sem_medicao | ...). Sem o motivo, "não mediu" e "mediu zero" voltam a ter a mesma cara.',
   'importante', 1044)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0225', revisado_em = current_date,
       observacao = 'A 0225 troca a assinatura de fn_registrar_campos_extraidos (p_medicao: a medição da leitura por documento no evento extracao_sombra) e cria fn_linha_de_base_extracao (leitura por documento, SECURITY INVOKER); 5 requisitos.'
 where id = true;
