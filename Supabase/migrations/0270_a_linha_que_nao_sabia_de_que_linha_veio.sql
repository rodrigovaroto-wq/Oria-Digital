-- =============================================================================
-- 0270 — A LINHA QUE NÃO SABIA DE QUE LINHA VEIO: campo_extraido ganha `ln` (o número da linha do texto numerado do documento de onde a linha extraída veio), e fn_registrar_campos_extraidos o grava
-- (Cria 1 coluna, campo_extraido.ln integer null, com o check campo_extraido_ln_check (ln is null or ln >= 1), e 1 view da sonda; reemite fn_registrar_campos_extraidos INTEIRA (corpo da 0231, a vigente; mesma assinatura de 6 args, mesma ACL)
--  com TRÊS mudanças: a variável v_ln, o cálculo dela e a coluna ln no insert. 4 requisitos novos na sonda. Sem backfill, sem tabela, sem gatilho.)
--
-- O DEFEITO. A P11 (leitura linha a linha, PLANO_LINHA_A_LINHA.md §3 Fase 1) precisa saber, para cada linha extraída, de que linha do texto do documento ela saiu. O n8n passa a mandar a chave `ln` em cada
-- objeto do array entregue a fn_registrar_campos_extraidos. Sem lugar para gravá-la e sem a função lê-la, a coordenada seria DESCARTADA em silêncio: o `jsonb` extra não dá erro, a linha grava como sempre, e a
-- Fase 3 (outra conta, que só lê campo_extraido) leria uma coluna que nunca existiu. Medido contra o corpo da 0231 (sabotagem S1 abaixo): com `ln` válido no lote, 3 das 3 linhas voltam com ln nulo.
--
-- A CAUSA. campo_extraido não tinha coluna de coordenada no texto: `origem_pagina` e `origem_linha` (texto livre da IA) existem, mas não são o número inteiro de uma linha numerada que se possa conferir contra o texto.
--
-- A CORREÇÃO.
--   1. campo_extraido.ln integer null, check (ln is null or ln >= 1). ADITIVA: linha antiga, linha de n8n anterior à P11 e documento sem camada de texto ficam com `ln` nulo, que quer dizer "não medível" e nunca zero (regra 1:
--      ausência não vira dado). Ninguém precisa conhecer a coluna: o portal, os exports e as reconciliações leem campo_extraido por nome de coluna (conferido por grep: nenhum `select *` depende da forma da tabela para o que a 0270 muda).
--   2. fn_registrar_campos_extraidos lê `ln` do JSON de cada campo. Só vale NÚMERO JSON inteiro >= 1 e de no máximo 9 dígitos, sem zero à esquerda; zero, negativo, fracionário, texto (inclusive "12"), booleano e estouro de
--      int viram NULO. Valor inválido NÃO aborta o lote (um cast que estourasse o int derrubaria o documento inteiro, e o n8n grava um por documento) e NÃO é corrigido para um palpite. O check do banco é a segunda barreira.
--      DECISÃO DE DESENHO: "12" como texto vira nulo (o n8n manda número; texto numérico é defeito de quem mandou, e adivinhar a coordenada é o que a regra 1 proíbe). 7.0 também vira nulo. Se a P11 mandar ln como texto, muda aqui.
--   3. CHAMADORES de fn_registrar_campos_extraidos (grep em Supabase/ N8N/ portal/src/, 11/11/2026): o nó "Gravar Campos (Sombra)" do workflow de ingestão (N8N/build-workflow.mjs:3321, por argumentos NOMEADOS:
--      p_falha_motivo, p_tem_dado_financeiro, p_medicao) e 59 arquivos de Supabase/test; Supabase/conferir/conferir_chamadas.sql só confere que a chamada resolve; portal/src não chama (só cita em comentário). A assinatura
--      NÃO muda, então nenhum deles muda: o conferidor de chamadas e `create or replace` com a mesma assinatura preservam ACL e chamadas.
--   4. CÓPIAS DE campo_extraido que poderiam perder o `ln`: procurado `insert into campo_extraido` em todas as migrations, em N8N/lib, N8N/build-workflow*.mjs e portal/src. Os únicos que gravam linhas extraídas por
--      conta própria são as versões antigas da própria fn_registrar_campos_extraidos (esta, a vigente, as substitui) e fn_registrar_transcricao_humana (0129: linha transcrita por pessoa, sem texto numerado: `ln` nulo
--      é a verdade). NÃO há função de cópia de versão, reprocesso ou export que faça `insert ... select` de campo_extraido: o reprocesso re-extrai e regrava pelo n8n, e a versão nova traz o `ln` dela. Nenhum caminho perde
--      `ln` em silêncio; o escopo não foi ampliado.
--   5. SEM BACKFILL: o `ln` das linhas já gravadas não é recuperável (o texto numerado não foi guardado com elas) e inventá-lo seria fabricar coordenada. Elas ficam nulas; a P11 só mede o que for reextraído.
--
-- COMO O TESTE PASSOU A REAPLICAR A 0270. o_balanco_sem_dado_financeiro.test.sql reaplica a 0231 duas vezes e deixa no banco o corpo ANTIGO de fn_registrar_campos_extraidos. O teste da 0270 reaplica a 0270 antes de tudo
--      (ela é idempotente): sem isso lê nulo no primeiro assert, e o schema.sql regerado levaria o corpo da 0231. Medido: sem a linha, o 1º assert reprova (rc 3).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/a_linha_que_nao_sabia_de_que_linha_veio.test.sql — 21 asserts (contagem de execuções = chamadas: o arquivo não tem laço; run.sh inteiro, rc 0, 21 `ok` no log).
-- Medido em 11/11/2026 com `raise exception` trocado por `raise warning` (p270.medindo = on) sobre cópias da migration com a correção DESLIGADA, o log lido atrás de FALHOU:, cada cópia aplicada de fato (o teste reaplica a cópia):
--   S1 `ln` NÃO gravado (coluna e valor tirados do insert; o cálculo fica): 5 dos 21 asserts reprovam (ln 5, ln 1, ln 999999999, "só as 3 linhas com ln válido" e a sonda, que vê 3 dos 4 requisitos).
--   S2 validação FROUXA (aceita zero, negativo e "12" como texto) E sem o check: 7 dos 21 asserts reprovam (ln 0, ln -3, ln "12", a contagem das 3 válidas, os 2 do check e a sonda, que vê 2 dos 4).
--      Só a validação frouxa COM o check ligado reprova de outro jeito: o insert estoura check_violation e o lote inteiro aborta (ERROR, rc 3), sem contar asserts.
--   S3 só o CHECK desligado (validação íntegra): 3 dos 21 asserts reprovam (os 2 inserts diretos de ln 0 e -1 e a sonda, que vê 3 dos 4).
--   Controle (migration intacta): 0 dos 21.
--   Conferido em cada rodada que a migration aplicou e que o teste aparece no log. Achado de arranjo da própria medição: a primeira versão do teste lia nulo no 1º assert por causa do corpo antigo deixado pelo teste da 0231 (ver acima).
-- =============================================================================

begin;

-- A COLUNA. Aditiva: linha antiga e linha de n8n anterior à P11 ficam com `ln` nulo, que quer dizer "não medível" (regra 1: ausência não vira zero). Ninguém que lê campo_extraido (portal,
-- exports, reconciliações, a Fase 3 da P11) é obrigado a conhecê-la.
alter table campo_extraido add column if not exists ln integer;

-- O check mora fora do add column para a migration poder ser reaplicada (drop + add) sem depender de a coluna ter sido criada agora.
alter table campo_extraido drop constraint if exists campo_extraido_ln_check;
alter table campo_extraido add constraint campo_extraido_ln_check check (ln is null or ln >= 1);

comment on column campo_extraido.ln is
  '0270 (P11, Fase 1): número (1..N, inteiro) da linha do texto numerado do documento de onde esta linha extraída veio. Nulo = não medível (documento sem camada de texto, n8n anterior à P11, linha anterior à 0270, ou valor inválido que fn_registrar_campos_extraidos recusou); nunca zero.';
comment on constraint campo_extraido_ln_check on campo_extraido is
  '0270: a linha do texto numerado começa em 1; zero ou negativo não é coordenada, é defeito de quem mandou. Nulo é permitido: significa não medível.';

-- A VIEW DA SONDA do check: o tipo `corpo`/`coluna` não enxerga constraint. Uma linha somente se o check existe, é de CHECK e ainda diz ln >= 1.
create or replace view instalacao_sonda_ln_check as
  select c.conname::text as restricao
    from pg_constraint c
   where c.conrelid = 'public.campo_extraido'::regclass
     and c.conname = 'campo_extraido_ln_check'
     and c.contype = 'c'
     and pg_get_constraintdef(c.oid) like '%ln >= 1%';

comment on view instalacao_sonda_ln_check is
  'Sonda da 0270: uma linha = campo_extraido_ln_check existe e exige ln >= 1. Zero linhas: o banco voltou a aceitar ln zero ou negativo como coordenada.';

grant select on instalacao_sonda_ln_check to authenticated, service_role;  -- service_role: o requisito grant_views_service_role (0214) cobra toda view de public

-- Reemitida INTEIRA a partir do corpo da 0231 (a vigente: nenhuma migration de 0232 a 0241 a redefine, conferido por grep), NÃO por replace de texto (.claude/memory/nunca-corrigir-funcao-por-replace.md,
-- .claude/memory/ancora-de-texto-quebra-com-crlf.md). Mesma assinatura de 6 argumentos, então create or replace preserva a ACL. Três mudanças: a variável v_ln, o cálculo dela e a coluna ln no insert.
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
  v_decidiu_pessoa     boolean;
  v_ln                 int;
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

      -- 0270: a coordenada da linha no texto numerado do documento. Só um NÚMERO JSON inteiro >= 1 e que cabe em int vale (no máximo 9 dígitos, sem zero à esquerda): zero, negativo,
      -- fracionário, texto (inclusive "12") e o estouro de int viram nulo, e nulo é "não medível", nunca zero nem palpite. Nenhum valor inválido derruba o lote: o laço é de
      -- um insert por linha, e um cast que estourasse abortaria o documento inteiro.
      v_ln := case when jsonb_typeof(v_item->'ln') = 'number' and (v_item->>'ln') ~ '^[1-9][0-9]{0,8}$' then (v_item->>'ln')::int else null end;

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
         origem_pagina, origem_linha, ordem, ln, nivel_autonomia, secao, secao_canonica, secao_canonica_inferida, entidade_coluna, periodo_coluna,
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
        v_ln,
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

  -- 0229: a MEDIÇÃO da leitura deste documento (o que o n8n contou: contas que o texto tinha, linhas que a IA devolveu, blocos, custo)
  -- entra no mesmo evento, como veio. Três estados DISTINTOS, porque "não mediu" e "mediu zero" não podem ter a mesma cara (regra 1 e 7):
  -- objeto = o n8n mediu; chave `medicao` nula = o n8n era anterior à 0229 ou não mediu; tipo que não é objeto = defeito do chamador,
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
  -- 0231: `false` explícito só cala o sinal quando o TIPO não carrega tabela financeira por natureza (fn_tipo_sem_dado_por_natureza). BALANCO/DRE/... com zero linha
  -- e `false` é a IA dizendo que não leu nada de um documento que devia ter número: falha, com motivo próprio (o prefixo é casado por regex no portal).
  -- 0231: e NÃO reabre o que uma PESSOA já decidiu. O motivo manda "se de fato não tem número, resolva"; quem resolveu disse que o documento não tem número, e o reenvio
  -- (que paga de novo porque o tipo não é societário) não pode desfazer isso. Só vale para o ramo novo: `true`/nulo e falha explícita seguem como eram.
  v_decidiu_pessoa := fn_pessoa_decidiu_sem_dado(v_documento_id);
  if p_falha_motivo is not null
     or (v_count = 0 and (coalesce(p_tem_dado_financeiro, true)
                          or (not fn_tipo_sem_dado_por_natureza(v_tipo) and not v_decidiu_pessoa))) then
    v_guarda_disparou := true;
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'extracao', 'extracao_falhou', 'importante', true,
          fn_descricao_extracao_falhou(v_nome_original, v_count,
            case when p_falha_motivo is null and v_count = 0 and p_tem_dado_financeiro is false
              then 'a leitura declarou que este documento não tem dado financeiro, mas '
                   || case when v_tipo is null then 'ele não tem tipo' else 'ele é do tipo ' || v_tipo end
                   || '. Abra o arquivo: se de fato não tem número, resolva esta pendência; se tem, reenvie o documento.'
              else p_falha_motivo end),
          v_documento_id, 'extracao:falhou:' || v_documento_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
      where id = v_pendencia_id;
  end if;

  -- ----- Auto-aceite (0029): DEPOIS das guardas, nunca antes -----------------
  --
  -- 0228: E SÓ DE DOCUMENTO COM TIPO. `v_tipo` (lido no topo, 0203) nulo = o documento nunca foi classificado: nada do que ele diz foi
  -- conferido contra o que um BALANCO/DRE/... deve conter, e "aceito" no Excel passa a querer dizer "conferido". Medido em produção em 04/11/2026:
  -- um .txt de 57 bytes sem tipo, entidade e período teve "Saldo de caixa: 1000" auto-aceita e chegou ao book como ACEITO.
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
  if v_n_auto_aceitos > 0 and not v_guarda_disparou and v_tipo is not null then
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
                                 'porque', case when v_tipo is null
                                   then 'documento sem tipo; linhas seguem pendentes de revisao humana ate alguem escolher o tipo'
                                   else 'guarda de extracao disparou; linhas seguem pendentes de revisao humana' end));
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
  'Grava campos extraídos e roda as três guardas (0043: fn_avaliar_guardas_extracao). Sinal 3 ("veio vazia") só dispara extracao_falhou quando p_tem_dado_financeiro não é explicitamente false — 0111: documento sem valor monetário por natureza (certidão, organograma, parecer de auditoria) não é falha de extração. 0203: quando a IA não dá secao_canonica, ela é inferida do texto da seção bruta (fn_secao_canonica_da_secao_bruta) e a linha grava secao_canonica_inferida = true; o que a IA deu nunca é sobrescrito. 0204: depois do laço, a seção que ainda falta é herdada pela árvore do próprio documento (fn_herdar_secao_pela_arvore). 0228: o auto-aceite exige documento com tipo (v_tipo nulo = linhas seguem pendentes). 0229: o evento extracao_sombra leva a chave medicao (o objeto de p_medicao como veio; nula explícita quando o chamador não mediu; medicao_invalida quando o tipo não é objeto) — a linha de base da leitura por documento (fn_linha_de_base_extracao). 0231: zero linha com tem_dado_financeiro = false TAMBÉM abre extracao_falhou quando o tipo não é societário/legal por natureza (fn_tipo_sem_dado_por_natureza; tipo nulo abre), com motivo que começa por "a leitura declarou que este documento não tem dado financeiro, mas ". 0270: cada linha grava `ln`, a coordenada (inteiro >= 1) da linha do texto numerado do documento que o n8n manda na chave `ln`; nulo, ausente ou inválido (zero, negativo, fracionário, texto, estouro de int) grava nulo, que é "não medível", nunca zero.';


-- ---------------------------------------------------------------------------
-- A SONDA. Marcadores em CÓDIGO, nunca de comentário (pg_get_functiondef traz os comentários do corpo: um marcador citado num comentário passaria sem a lógica).
-- ---------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('campo_extraido_ln_coluna', '0270', 'coluna', 'campo_extraido.ln', null, null,
   'A coordenada da linha no texto numerado do documento (P11, Fase 1). Ausente = a 0270 não foi aplicada: o n8n manda `ln` e ele se perde sem erro, e a leitura linha a linha não tem de onde partir.',
   'importante', 1270),
  ('campo_extraido_ln_check', '0270', 'comportamento', 'instalacao_sonda_ln_check', null, 1,
   'O check ln >= 1 (nulo permitido). Zero linhas = o banco voltou a aceitar ln zero ou negativo, e um zero fabricado se confunde com a coordenada de uma linha.',
   'importante', 1271),
  ('campo_extraido_ln_valida', '0270', 'corpo', 'fn_registrar_campos_extraidos', 'jsonb_typeof(v_item->''ln'') = ''number''', null,
   'fn_registrar_campos_extraidos só aceita ln que seja número JSON inteiro >= 1; o resto vira nulo. Corpo sem isto = valor inválido aborta o lote (cast) ou grava coordenada inventada.',
   'importante', 1272),
  ('campo_extraido_ln_gravada', '0270', 'corpo', 'fn_registrar_campos_extraidos', 'ordem, ln, nivel_autonomia', null,
   'fn_registrar_campos_extraidos grava ln no insert. Corpo anterior (0231) = o n8n manda a coordenada e ela é descartada: toda linha extraída fica sem origem no texto, sem erro nenhum.',
   'importante', 1273)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0270', revisado_em = current_date,
       observacao = 'A 0270 acrescenta campo_extraido.ln (P11 Fase 1: a linha do texto numerado de onde a linha extraída veio; nulo = não medível) com check ln >= 1, e reemite fn_registrar_campos_extraidos INTEIRA para gravá-lo (inválido vira nulo, não aborta). 4 requisitos novos (ordem 1270-1273).'
 where id = true;

commit;
