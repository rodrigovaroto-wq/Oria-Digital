-- =============================================================================
-- 0231 — O BALANÇO QUE A IA DECLAROU SEM DADO FINANCEIRO E NINGUÉM VIA: `tem_dado_financeiro = false` só cala o documento que não tem número por natureza
-- (Cria 1 função, fn_tipo_sem_dado_por_natureza (SQL, stable, SECURITY INVOKER, somente leitura); reemite fn_versao_extracao_concluida (corpo da 0230, mesmo comportamento, a conta do tipo passa a morar
--  na função nova) e fn_registrar_campos_extraidos INTEIRA (corpo da 0229; mesma assinatura de 6 args, mesma ACL; a 0230 não a tocou: conferido por grep nas migrations) com UMA mudança no Sinal 3.
--  Backfill idempotente de pendências, 1 evento de auditoria, 4 requisitos novos na sonda e 1 reapontado. Sem tabela, sem gatilho.)
--
-- O DEFEITO. O Sinal 3 era `p_falha_motivo is not null or (v_count = 0 and coalesce(p_tem_dado_financeiro, true))`: com `tem_dado_financeiro = false` e zero linha NADA abria, para QUALQUER tipo.
-- Certo para certidão/organograma/contrato social (0111); falha silenciosa para BALANCO, DRE etc. Medido em PRODUÇÃO em 09/11/2026 (somente leitura): 41 documentos de tipo NÃO societário
-- (versão mais nova, último evento `extracao_sombra` sem falha e com `tem_dado_financeiro = 'false'`, zero linha em `campo_extraido`, sem `extracao_falhou` aberta):
--     BALANCO 3, DRE 5, FATURAMENTO_24M 2 (AMOBELEZA, real); MAPA_DIVIDA 1 (KRAUSPENHAR E HARTMANN, real); EXTRATO_BANCARIO 2 (AMO teste 00);
--     DF_AUDITADA 16 e NOTAS_EXPL 12 (mandatos de teste e sintéticos) ........................................ 41
-- Os societários na mesma situação são 31 (CERTIDOES 17, CONTRATO_SOCIAL 3, ORGANOGRAMA 11) e continuam calados.
--
-- A CAUSA. A 0111 tratou a declaração da IA como prova de "este documento não tem número", sem olhar o tipo. A 0230 já tinha medido que a declaração não basta (DF_AUDITADA 16 com
-- medicao.contas_no_documento > 0) e escreveu o predicado do tipo INLINE em fn_versao_extracao_concluida; o Sinal 3 nunca o usou. Resultado: o reenvio paga de novo esses documentos (a 0230 não
-- os reaproveita), mas nada na fila diz ao analista que eles voltaram sem número.
--
-- A CORREÇÃO.
--   1. fn_tipo_sem_dado_por_natureza(p_tipo): o tipo existe em taxonomia_tipo_documento, categoria 'Societário/Legal' e codigo <> 'CONTINGENCIAS' (traz valor de causa e provisão). Tipo nulo ou
--      desconhecido = false, nunca nulo. EXATAMENTE o predicado da 0230. SIMPLIFICAÇÃO DELIBERADA com o teto da 0230: a categoria é proxy de "não traz tabela financeira"; sobe quando a taxonomia
--      ganhar atributo próprio.
--   2. fn_versao_extracao_concluida chama a função (duas cópias da mesma conta divergem sem erro). Comportamento idêntico: reextracao.test.sql passa inteiro.
--   3. Sinal 3: zero linha + sem falha + `false` abre `extracao_falhou` quando `not fn_tipo_sem_dado_por_natureza(v_tipo)` (tipo nulo abre). O motivo é próprio e COMEÇA por
--      "a leitura declarou que este documento não tem dado financeiro, mas " (o portal casa esse prefixo por regex: não mude). Os outros ramos ficam como estão. O evento `extracao_sombra` NÃO muda
--      (falha_motivo continua nulo nesse caso): conferido que isso não quebra fn_versao_extracao_concluida (documento financeiro sem linha não é reaproveitável: a parte nova exige tipo
--      societário E não há pendência aberta) nem fn_linha_de_base_extracao (não olha o motivo da pendência; a pendência aparece em pendencias_abertas por tipo).
--   3b. DECISÃO HUMANA NÃO SE DESFAZ NO REENVIO (achado de revisão, reproduzido: DF_AUDITADA/NOTAS_EXPL, 28 em produção, são esse caso). O motivo manda "se de fato não tem número, resolva esta
--      Decisão de pessoa vale com QUALQUER contagem da régua (ela conta CPF/OAB como conta: 9 na procuração do book-espelho). Regra 2: exigida a
--      contagem zero também nesse ramo, o assert 6d "concluída mesmo com 9 contas" reprova (run.sh rc 3); religado, rc 0 com 3.268 ok.
--      pendência"; resolvida, o reenvio pagava de novo (fn_versao_extracao_concluida dava false, tipo não societário) e o Sinal 3 abria OUTRA, porque procurava só estado <> 'resolvida'.
--      Agora: (i) o ramo novo do Sinal 3 NÃO abre quando o documento tem extracao_falhou resolvida por pessoa (resolvida_por <> 'sistema:extracao'; `true`/nulo e falha explícita não mudam);
--      (ii) fn_versao_extracao_concluida também vale quando, com o último evento sem falha, false e sem conta contada, o documento tem extracao_falhou resolvida por pessoa e nenhuma aberta.
--      Resolvida pelo SISTEMA (reextração com linha) NÃO é decisão humana. Societário inalterado.
--   4. BACKFILL, pelo MESMO predicado: versão mais nova do documento; último evento sem falha e com tem_dado_financeiro = 'false'; zero linha na versão; sem extracao_falhou não resolvida;
--      not fn_tipo_sem_dado_por_natureza(tipo). Idempotente (o `not exists` de pendência não resolvida com o mesmo motivo). Um evento `extracao_pendencia_backfill` com a contagem. Esperado em
--      produção: 42. NO BANCO DE TESTE: 0 na aplicação da migration (banco vazio) e 2 na reaplicação do teste (DRE e MAPA_DIVIDA do cenário; as fixtures dos outros testes não caem no predicado), 0 na seguinte.
--      Documento cuja extracao_falhou foi RESOLVIDA por pessoa (resolvida_por não 'sistema:extracao') fica FORA do backfill: decisão humana não se reabre
--      por migration (0183). Medido em produção em 09/11/2026: 42 alvos (41 de antes + 1 do lote de medição do mesmo dia), 0 resolvidos por pessoa.
--      Regra 2 desta exclusão: trocada por `and false`, o run.sh reprova (o assert "o backfill abre só para DRE e MAPA_DIVIDA" vê DRE,DRE,MAPA_DIVIDA; rc 3). Religada: rc 0.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/o_balanco_sem_dado_financeiro.test.sql — 42 asserts (contagem de execuções, medida pelo `ok` no log do run.sh inteiro, rc 0). Medido em 09/11/2026 com `raise exception` trocado por `raise warning` (cópia temporária, restaurada), o log lido atrás de FALHOU:
-- Os números abaixo de 11/19 foram medidos quando o arquivo tinha 33 asserts; com os 9 da decisão de pessoa (6b/6c) a medição desta parte é a das duas linhas seguintes, sobre 42.
-- DECISÃO DE PESSOA (3b), medido sobre os 42: exclusão do Sinal 3 desligada (`v_decidiu_pessoa := false and ...`, marcador da sonda mantido): 2 reprovam (nova leitura não reabre; não cria outra pendência). Parte de fn_versao_extracao_concluida desligada (`or false and exists`): 3 reprovam (concluída por pessoa; reenvio reaproveita; trocado o autor para pessoa). Religadas: 0.
-- Com a condição ANTIGA do Sinal 3 religada (mantido o marcador da sonda em código morto): 11 dos 33 reprovam. Com a condição antiga SEM o marcador, a sonda (instalacao.test.sql) já reprova antes, 1 assert, rc 3.
-- Com fn_tipo_sem_dado_por_natureza devolvendo sempre true: 19 dos 33 reprovam, mais 3 do reextracao.test.sql (0230: BALANCO, sem tipo e CONTINGENCIAS passam a ser reaproveitados). Controle (migration intacta): 0. Conferido em cada rodada que a migration aplicou e que o teste aparece no log.
-- =============================================================================

begin;

create or replace function fn_tipo_sem_dado_por_natureza(p_tipo text)
returns boolean
language sql
stable
as $$
  select exists (select 1
                   from taxonomia_tipo_documento t
                  where t.codigo = p_tipo
                    and t.categoria = 'Societário/Legal'
                    -- CONTINGENCIAS fica de fora: é da mesma categoria, mas a relação de processos traz valor de causa e provisão.
                    and t.codigo <> 'CONTINGENCIAS')
$$;

comment on function fn_tipo_sem_dado_por_natureza(text) is
  '0231: o tipo de documento não carrega tabela financeira por natureza (certidão, organograma, contrato social)? Verdadeira só quando o tipo existe em taxonomia_tipo_documento, é da categoria Societário/Legal e não é CONTINGENCIAS. Tipo nulo ou desconhecido = false, nunca nulo. Quem pergunta: fn_versao_extracao_concluida (reaproveitar no reenvio) e o Sinal 3 de fn_registrar_campos_extraidos (zero linha com tem_dado_financeiro = false só é normal para esses tipos).';

revoke all on function fn_tipo_sem_dado_por_natureza(text) from public;
grant execute on function fn_tipo_sem_dado_por_natureza(text) to authenticated, service_role;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    execute 'grant execute on function fn_tipo_sem_dado_por_natureza(text) to supabase_read_only_user';
  end if;
end $$;

-- Reemitida a partir do corpo da 0230; só o `and exists (... taxonomia ...)` virou a chamada. CREATE OR REPLACE com a mesma assinatura preserva a ACL.
create or replace function fn_versao_extracao_concluida(p_documento_versao_id uuid)
returns boolean
language sql
stable
as $$
  -- (1) tem linha: o critério da 0118, intacto. (2) ou TODAS: o ÚLTIMO evento de extração (criado_em; empate na mesma transação é indefinido, ver o cabeçalho) existe, sem falha,
  -- declara tem_dado_financeiro = false e não contou conta; o tipo do documento é da categoria 'Societário/Legal'; e não há pendência extracao_falhou aberta no documento.
  -- Qualquer parte ilegível = false (paga de novo), nunca nula.
  select exists (select 1 from campo_extraido ce where ce.documento_versao_id = p_documento_versao_id)
      or coalesce((
    select u.depois->>'falha_motivo' is null
       and u.depois->>'tem_dado_financeiro' = 'false'
       -- (2a) tipo societário/legal SEM conta contada pela régua, OU uma PESSOA resolveu a extracao_falhou do documento. A decisão
       -- de pessoa vale com qualquer contagem: a régua conta CPF/OAB/percentual como conta (medido na procuração do book-espelho: 9),
       -- e foi a pessoa, com o arquivo aberto, que decidiu que não há número. Pagar de novo só repetiria a leitura que ela já julgou.
       and ((fn_tipo_sem_dado_por_natureza((select d.tipo_taxonomia from documento_versao dv join documento d on d.id = dv.documento_id where dv.id = p_documento_versao_id))
             and (u.depois->'medicao'->>'contas_no_documento' is null
                  or (u.depois->'medicao'->>'contas_no_documento' ~ '^[0-9]+(\.[0-9]+)?$'
                      and (u.depois->'medicao'->>'contas_no_documento')::numeric = 0)))
            or exists (select 1
                         from documento_versao dv
                         join pendencia pe on pe.documento_id = dv.documento_id
                        where dv.id = p_documento_versao_id
                          and pe.tipo = 'extracao_falhou'
                          and pe.estado = 'resolvida'
                          and coalesce(pe.resolvida_por, '') <> 'sistema:extracao'))
       and not exists (select 1
                         from documento_versao dv
                         join pendencia pe on pe.documento_id = dv.documento_id
                        where dv.id = p_documento_versao_id
                          and pe.tipo = 'extracao_falhou'
                          and pe.estado <> 'resolvida')
      from evento_auditoria u
     where u.acao = 'extracao_sombra'
       and u.entidade_ref = 'documento_versao:' || p_documento_versao_id::text
     order by u.criado_em desc
     limit 1
  ), false)
$$;

comment on function fn_versao_extracao_concluida(uuid) is
  '0230: a versão já foi extraída (vale reaproveitar no reenvio)? Verdadeira quando a versão TEM linha em campo_extraido (o critério da 0118, intacto, mesmo sem evento e mesmo com falha) OU quando TODAS valem: o ÚLTIMO evento extracao_sombra (criado_em) existe, sem falha_motivo e com tem_dado_financeiro = false explícito; o tipo do documento é da categoria Societário/Legal de taxonomia_tipo_documento (CERTIDOES, CONTRATO_SOCIAL, ORGANOGRAMA; CONTINGENCIAS é da categoria e fica DE FORA, porque traz valor de causa e provisão; tipo nulo ou de outra categoria = não); a medição do evento não contou conta (contas_no_documento nulo ou 0); e o documento não tem pendência extracao_falhou aberta. Simplificação deliberada: a categoria é proxy de "tipo que não traz tabela financeira"; sobe quando a taxonomia ganhar atributo próprio. Zero linha sem tudo isso = false (a 0118 protege extração recusada/truncada); condição ilegível = false (paga de novo). Falha COM linha continua reaproveitada (teto conhecido, P8). A pergunta de fn_registrar_documento e da fatia de orçamento do lote: uma implementação só. SECURITY INVOKER, somente leitura. 0231: o tipo é perguntado a fn_tipo_sem_dado_por_natureza (mesma conta, comportamento idêntico).';

-- Reemitida INTEIRA a partir do corpo da 0229 (NÃO por replace de texto: .claude/memory/ancora-de-texto-quebra-com-crlf.md). Mesma assinatura, então create or replace preserva a ACL.
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
  v_decidiu_pessoa := exists (select 1 from pendencia pe
                               where pe.documento_id = v_documento_id and pe.tipo = 'extracao_falhou'
                                 and pe.estado = 'resolvida' and coalesce(pe.resolvida_por, '') <> 'sistema:extracao');
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
  'Grava campos extraídos e roda as três guardas (0043: fn_avaliar_guardas_extracao). Sinal 3 ("veio vazia") só dispara extracao_falhou quando p_tem_dado_financeiro não é explicitamente false — 0111: documento sem valor monetário por natureza (certidão, organograma, parecer de auditoria) não é falha de extração. 0203: quando a IA não dá secao_canonica, ela é inferida do texto da seção bruta (fn_secao_canonica_da_secao_bruta) e a linha grava secao_canonica_inferida = true; o que a IA deu nunca é sobrescrito. 0204: depois do laço, a seção que ainda falta é herdada pela árvore do próprio documento (fn_herdar_secao_pela_arvore). 0228: o auto-aceite exige documento com tipo (v_tipo nulo = linhas seguem pendentes). 0229: o evento extracao_sombra leva a chave medicao (o objeto de p_medicao como veio; nula explícita quando o chamador não mediu; medicao_invalida quando o tipo não é objeto) — a linha de base da leitura por documento (fn_linha_de_base_extracao). 0231: zero linha com tem_dado_financeiro = false TAMBÉM abre extracao_falhou quando o tipo não é societário/legal por natureza (fn_tipo_sem_dado_por_natureza; tipo nulo abre), com motivo que começa por "a leitura declarou que este documento não tem dado financeiro, mas ".';

-- ---------------------------------------------------------------------------
-- BACKFILL: a mesma pendência que o Sinal 3 passa a abrir, para o que já está nessa situação. Idempotente.
-- ---------------------------------------------------------------------------
do $$
declare
  v_n int;
begin
  with alvo as materialized (
    select d.id as documento_id, d.caso_id, d.tipo_taxonomia, dv.nome_original
      from documento d
      join lateral (select v.id, v.nome_original
                      from documento_versao v
                     where v.documento_id = d.id
                     order by v.n_versao desc
                     limit 1) dv on true
     where not fn_tipo_sem_dado_por_natureza(d.tipo_taxonomia)
       and not exists (select 1 from campo_extraido ce where ce.documento_versao_id = dv.id)
       and not exists (select 1 from pendencia pe
                        where pe.documento_id = d.id and pe.tipo = 'extracao_falhou' and pe.estado <> 'resolvida')
       -- Decisão de pessoa não se reabre por migration (o defeito da 0183). Medido em produção em 09/11/2026: 0 dos 42 alvos.
       and not exists (select 1 from pendencia pe
                        where pe.documento_id = d.id and pe.tipo = 'extracao_falhou' and pe.estado = 'resolvida'
                          and coalesce(pe.resolvida_por, '') <> 'sistema:extracao')
       and coalesce((select u.depois->>'falha_motivo' is null and u.depois->>'tem_dado_financeiro' = 'false'
                       from evento_auditoria u
                      where u.acao = 'extracao_sombra'
                        and u.entidade_ref = 'documento_versao:' || dv.id::text
                      order by u.criado_em desc
                      limit 1), false)
  ), aberta as (
    insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
    select a.caso_id, 'extracao', 'extracao_falhou', 'importante', true,
           fn_descricao_extracao_falhou(a.nome_original, 0,
             'a leitura declarou que este documento não tem dado financeiro, mas '
             || case when a.tipo_taxonomia is null then 'ele não tem tipo' else 'ele é do tipo ' || a.tipo_taxonomia end
             || '. Abra o arquivo: se de fato não tem número, resolva esta pendência; se tem, reenvie o documento.'),
           a.documento_id, 'extracao:falhou:' || a.documento_id
      from alvo a
    returning 1
  )
  select count(*) into v_n from aberta;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:migration', 'extracao_pendencia_backfill', 'migration:0231',
            jsonb_build_object('pendencias_abertas', v_n,
                               'porque', 'documento de tipo nao societario com zero linha e tem_dado_financeiro = false, sem extracao_falhou aberta'));
  raise notice '0231: % pendencia(s) extracao_falhou aberta(s) pelo backfill', v_n;
end $$;

-- ---------------------------------------------------------------------------
-- A SONDA. Marcadores em CÓDIGO (pg_get_functiondef traz comentário, por isso nenhum deles aparece em comentário nos corpos).
-- extracao_concluida_estreita_pela_categoria (0230) é REAPONTADA: a categoria agora mora em fn_tipo_sem_dado_por_natureza; o marcador antigo sumiria do corpo de
-- fn_versao_extracao_concluida e a sonda acusaria como ausente uma 0230 que está aplicada. Continua atribuída à 0230 (reextracao.test.sql conta 3 requisitos dela).
-- ---------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('tipo_sem_dado_funcao', '0231', 'funcao', 'fn_tipo_sem_dado_por_natureza', null, null,
   'A pergunta única "este tipo não traz tabela financeira por natureza?". Ausente = a 0231 não foi aplicada: BALANCO/DRE declarados sem dado financeiro (41 em produção, 09/11/2026) seguem sem pendência.',
   'importante', 1060),
  ('extracao_concluida_estreita_pela_categoria', '0230', 'corpo', 'fn_tipo_sem_dado_por_natureza', 't.categoria = ''Societário/Legal''', null,
   'O tipo "sem dado por natureza" é só da categoria Societário/Legal (reapontado da 0230). Corpo sem isto = a declaração tem_dado_financeiro = false da IA vale para qualquer tipo, e DF_AUDITADA/NOTAS_EXPL/DRE com dado deixam de ser reextraídos e de abrir pendência: buraco silencioso permanente.',
   'importante', 1051),
  ('tipo_sem_dado_exclui_contingencias', '0231', 'corpo', 'fn_tipo_sem_dado_por_natureza', 't.codigo <> ''CONTINGENCIAS''', null,
   'CONTINGENCIAS é da categoria Societário/Legal mas traz valor de causa e provisão. Sem a exclusão, zero linha + false nele fica calado e o reenvio o pula.',
   'importante', 1061),
  ('extracao_concluida_pergunta_ao_tipo', '0231', 'corpo', 'fn_versao_extracao_concluida', 'fn_tipo_sem_dado_por_natureza((select d.tipo_taxonomia', null,
   'fn_versao_extracao_concluida pergunta o tipo à função única. Corpo anterior = duas cópias da mesma conta, que divergem sem erro.',
   'importante', 1062),
  ('falha_do_documento_financeiro_sem_dado', '0231', 'corpo', 'fn_registrar_campos_extraidos', 'not fn_tipo_sem_dado_por_natureza(v_tipo)', null,
   'O Sinal 3 abre extracao_falhou para zero linha + tem_dado_financeiro = false quando o tipo não é societário. Corpo anterior = BALANCO/DRE sem linha e com false (41 em produção, 09/11/2026) ficam sem pendência nenhuma.',
   'importante', 1063),
  ('falha_nao_reabre_decisao_de_pessoa', '0231', 'corpo', 'fn_registrar_campos_extraidos', 'and not v_decidiu_pessoa', null,
   'O Sinal 3 não reabre a extracao_falhou que uma pessoa resolveu (DF_AUDITADA/NOTAS_EXPL, 28 em produção em 09/11/2026). Corpo sem isto = a decisão do analista é desfeita a cada reenvio.',
   'importante', 1064),
  ('extracao_concluida_respeita_decisao_de_pessoa', '0231', 'corpo', 'fn_versao_extracao_concluida', 'and pe.estado = ''resolvida''', null,
   'A versão cujo documento teve a extracao_falhou resolvida por pessoa (e nenhuma aberta) conta como concluída: o reenvio não paga de novo o que o analista decidiu que não tem número.',
   'importante', 1065)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0231', revisado_em = current_date,
       observacao = 'A 0231 cria fn_tipo_sem_dado_por_natureza, reemite fn_versao_extracao_concluida (usa a função) e fn_registrar_campos_extraidos INTEIRA (Sinal 3: zero linha com tem_dado_financeiro = false abre extracao_falhou para tipo não societário), com backfill idempotente; 6 requisitos novos e 1 reapontado.'
 where id = true;

commit;
