-- =============================================================================
-- 0203 — A SEÇÃO QUE A IA NÃO DEU E A LINHA QUE SUMIA DO REALIZADO
--
-- O DEFEITO (medido em PRODUÇÃO, 05/10/2026, só leitura, caso Fw Valtra 03a66ab6). A `secao_canonica` de cada
-- linha extraída é escolhida pelo LLM na extração (enum em N8N/lib/extract.mjs). Quando ele devolve nulo, a
-- linha some de receita/custo/giro em fn_linhas_do_realizado, fn_valores_por_ano, fn_linhas_para_modelagem e
-- nas reconciliações — calada: o agrupamento é por seção, e a seção nula é "família própria" (fn_familia_da_secao).
-- DRE ref 2025 do Fw Valtra: 136 de 724 linhas sem `secao_canonica`; a seção BRUTA (`campo_extraido.secao`) era
-- "VENDAS DE PRODUTOS, MERCADORIAS E SERVIÇOS" (34) e "(-) DEDUÇÕES" (94). Efeito: receita bruta 2025 do realizado
-- = 235.650 (só "outras receitas") em vez de ~43,85 mi; sugestões CUSTO_VARIAVEL 2025 = 26.958% e PMR 19.674 dias.
-- A DRE 2023/2024 do mesmo caso, com a mesma seção rotulada de outro jeito, foi mapeada pela IA.
-- Em produção há linhas vigentes sem seção canônica e COM seção bruta em 21+ tipos/seções (353 do balancete
-- "Balancete Analítico", 302 de "Eliminações do combinado", 159 de "ATIVO", 109 de "ATIVO CIRCULANTE"…).
--
-- A CAUSA: nada no banco olhava a seção bruta quando a IA calava. A seção bruta é o cabeçalho do grupo a que a
-- linha pertence no documento; quando ele diz inequivocamente "PASSIVO CIRCULANTE" ou "(-) DEDUÇÕES", a resposta
-- da IA nula era perda de informação que o documento já continha.
--
-- A REGRA (comportamento): quando a IA NÃO deu secao_canonica, ela é inferida do texto da seção bruta por
-- `fn_secao_canonica_da_secao_bruta(secao, tipo_documento)` — pura, determinística, e CONSERVADORA: casa o texto
-- inteiro (âncora nas duas pontas) e só nos cinco tipos de demonstração (BALANCO, BALANCETE, COMBINADO, DF_AUDITADA,
-- DRE). O que a IA deu NUNCA é sobrescrito. A linha diz que foi inferida: `secao_canonica_inferida` (regra 1/7 —
-- seção inferida não tem a mesma aparência da seção dada).
--
-- O QUE MAPEIA (inequívoco): receita/vendas/faturamento/(-) deduções -> receita_bruta (deduções só em DRE e
-- DF_AUDITADA: "deduções" num balanço é outra coisa); CMV/CPV/CSP/custo(s) [dos produtos, das vendas…] -> custos;
-- despesas operacionais/administrativas/gerais/comerciais/com vendas/com pessoal -> despesas_operacionais;
-- receitas/despesas financeiras e "resultado financeiro" -> resultado_financeiro; IR/CSLL/tributos sobre o lucro
-- (DRE) -> impostos_lucro; ativo circulante/disponível/disponibilidades/caixa e equivalentes/bancos [conta
-- movimento]/aplicações financeiras -> ativo_circulante; ativo não circulante/permanente/realizável a LP/
-- imobilizado/intangível/investimentos -> ativo_nao_circulante; passivo circulante/contas a pagar/fornecedores/
-- obrigações [com o pessoal, trabalhistas, sociais, fiscais…]/empréstimos e financiamentos de CURTO prazo ->
-- passivo_circulante; passivo não circulante/exigível a LP/empréstimos… de LONGO prazo -> passivo_nao_circulante;
-- patrimônio líquido -> patrimonio_liquido.
--
-- O QUE FICA NULL, e por quê (cada um é "procurei e não é inequívoco"):
--   "ATIVO" / "PASSIVO" sozinhos, "TOTAL DO ATIVO", "TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO", "PASSIVO E
--     PATRIMÔNIO LÍQUIDO", "TOTAL", "TOTAIS" — são o TOTAL ou o TOPO da demonstração, não uma seção: o subtotal
--     não deve virar conta de seção (fn_papel_linha já os trata como subtotal pelo NOME da linha; dar-lhes seção
--     os poria dentro da soma da seção alheia e a dupla contagem voltaria);
--   "CIRCULANTE" / "NÃO CIRCULANTE" sem lado — ativo ou passivo? O texto não diz;
--   "LUCRO BRUTO", "RESULTADO …" (operacional, antes dos tributos, do exercício), "PREJUÍZO DO EXERCÍCIO",
--     "RECEITA LÍQUIDA" — subtotais que atravessam seções (receita menos custo, etc.);
--   "Eliminações do combinado", "Balancete Analítico", "RESUMO DO BALANCETE", "CONTAS TEMPORARIAS" — nome do
--     documento ou do ajuste, não de uma conta;
--   "PROVISÕES" — ativo, passivo ou despesa; "EMPRÉSTIMOS E FINANCIAMENTOS" sem prazo — curto ou longo;
--   "NAO_CLASSIFICAVEL" — a própria IA disse que não sabe; "CONTAS DE RESULTADO - RECEITAS" — mistura receita
--     operacional e financeira.
-- Âncora nas duas pontas porque "DESPESAS ANTECIPADAS" é ativo, "RECEITAS DIFERIDAS" é passivo e "IMPOSTOS A
-- RECOLHER" é passivo: conter a palavra não basta. A 0203 NÃO resolve estes: o que continua NULL continua sumindo
-- do realizado, mas agora é porque o documento não diz, não porque a IA calou.
--
-- PONTO ÚNICO DE ESCRITA: `fn_registrar_campos_extraidos` (reemitida INTEIRA, a partir do corpo vigente — NÃO
-- por `replace` de texto). Chamadores medidos (grep em Supabase/ N8N/ portal/src Verificação/): UM nó do n8n, "Gravar
-- Campos (Sombra)" (N8N/build-workflow.mjs:2738, a ingestão), o arnês Verificação/run.mts e variacoes.mts, e os
-- testes SQL; nenhum `insert into campo_extraido` em N8N/ nem em portal/src. A única outra função que grava linha é
-- fn_registrar_transcricao_humana (linha transcrita por PESSOA, origem_valor = 'transcricao_humana', fora do
-- alcance de propósito). Sem reimportar workflow: a assinatura não muda.
--
-- LEITORES de campo_extraido.secao_canonica (pg_proc.prosrc, esquema vigente): fn_linhas_do_realizado,
-- fn_valores_por_ano, fn_linhas_para_modelagem, fn_conflitos_do_caso, fn_pares_duplicados_do_caso,
-- fn_reconciliar_intragrupo, fn_reconciliar_mutuos, fn_reconciliar_duplicidade, fn_reconciliar_versoes_do_periodo,
-- fn_exigencias_do_caso (checagem `secao_presente`), fn_papel_do_rotulo_no_caso, fn_lado_intragrupo,
-- fn_lado_do_mutuo, fn_classe_contabil_sugerir / fn_classificar_contabil, fn_vincular_linha_premissa,
-- fn_aplicar_premissa_em_lote, fn_upsert_periodo, fn_linhas_para_transcrever. Mudar a seção de uma linha muda o
-- que TODAS elas veem. As leituras (realizado, série, modelagem) mudam sozinhas no próximo carregamento. O que fica
-- GRAVADO (pendências de conflito/duplicidade/intragrupo/mútuos, `linha_exigida_ausente`) só muda quando for
-- recomputado: DEPOIS DE APLICAR, rodar `fn_reconciliar_caso(caso)` e `fn_recomputar_completude(caso)` nos casos
-- que o backfill tocou (o aviso da migration diz quantos; `fn_inferir_secao_canonica_das_linhas(caso)` devolve a
-- contagem por caso). A 0203 não os roda: recomputar tudo na migration é efeito que ninguém pediu.
--
-- BACKFILL: `fn_inferir_secao_canonica_das_linhas()` — a MESMA conta que o teste exerce. Só extração
-- (origem_valor = 'extracao') sem revisão humana (revisado_por nulo); todas as versões; idempotente. A contagem
-- sai em `raise notice` e em evento_auditoria.
--
-- TETO CONHECIDO: a inferência lê só a seção bruta. Linha cuja seção bruta é nula, ou é uma das ambíguas acima,
-- segue sem seção. O prompt de extração (N8N/lib/extract.mjs) NÃO muda aqui: pedir à IA que não calar é outra
-- fatia, e esta rede vale mesmo depois dela.
--
-- NÃO FAZ: não toca em produção por estar escrita; migration escrita ≠ aplicada. Quem responde é a sonda, contra o
-- banco em que se está conectado:
--
--   select chave, migration, tipo, objeto, presente, detalhe, porque
--     from fn_instalacao_conferir() where not presente order by 1;
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/secao_inferida_da_secao_bruta.test.sql — 71 asserts; com a correção
-- desligada (fn_secao_canonica_da_secao_bruta sempre NULL) reprovam 38; só a gravação sem inferir, 12; só o backfill
-- desligado, 3; a IA sobrescrita, 3 (e 5 do teste da 0200, que já protegiam o que a IA deu); o backfill sem o filtro de
-- revisão humana, 2; o backfill sem a marca, 1; a função sem a âncora de início, 1; o total do ativo mapeado, 3.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. A COLUNA QUE DIZ "ESTA SEÇÃO FOI INFERIDA" (regra 1/7: a linha não pode fingir que a IA a classificou)
-- ---------------------------------------------------------------------------
alter table campo_extraido
  add column if not exists secao_canonica_inferida boolean not null default false;

comment on column campo_extraido.secao_canonica_inferida is
  '0203: true = a secao_canonica NÃO veio da IA; foi inferida do texto da seção bruta (campo_extraido.secao) por fn_secao_canonica_da_secao_bruta, na gravação ou no backfill. false = a IA deu (ou a linha segue sem seção). A inferência é conservadora e determinística; o que ela não reconhece fica NULL.';

-- ---------------------------------------------------------------------------
-- 2. A FUNÇÃO PURA: seção bruta + tipo do documento -> seção canônica, ou NULL
-- ---------------------------------------------------------------------------
create or replace function fn_secao_canonica_da_secao_bruta(p_secao text, p_tipo_documento text)
returns text language plpgsql immutable as $$
declare
  n       text;
  v_patr  boolean := p_tipo_documento in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DF_AUDITADA');
  v_res   boolean := p_tipo_documento in ('DRE', 'DF_AUDITADA', 'BALANCETE', 'COMBINADO');
  v_dre   boolean := p_tipo_documento in ('DRE', 'DF_AUDITADA');
  v_lp    boolean;
begin
  -- Fora dos cinco tipos de demonstração a seção bruta tem outro significado (DMPL, DVA, fluxo, mapa de
  -- dívida, faturamento…): quem decide é a IA, e a função não opina.
  if p_secao is null or not (v_patr or v_res) then
    return null;
  end if;

  n := fn_normalizar_texto(p_secao);
  -- tira o marcador de sinal e a numeração do cabeçalho: "(-) Deduções", "= Receita", "1.1 Ativo circulante", "II - Passivo"
  n := regexp_replace(n, '^(\(\s*[-+=]\s*\)|[-+=])\s*', '');
  n := regexp_replace(n, '^([0-9]+(\.[0-9]+)*|[ivx]+)\s*[-.)]\s*', '');
  n := regexp_replace(n, '[\s:.;]+$', '');
  if n = '' then
    return null;
  end if;

  -- "longo prazo" / "não circulante" / "LP" no texto: o lado do prazo é explícito
  v_lp := n ~ '(longo prazo|nao circulante|\mlp\M)';

  -- ---- PATRIMONIAL ---------------------------------------------------------
  -- O LADO (ativo × passivo) tem de estar NO TEXTO. "CIRCULANTE", "NÃO CIRCULANTE", "ATIVO", "PASSIVO",
  -- "TOTAL DO ATIVO", "PASSIVO E PATRIMÔNIO LÍQUIDO" não dizem a seção — ficam NULL (abaixo).
  if v_patr then
    if n ~ '^(ativo (nao circulante|permanente|realizavel a longo prazo)|nao circulante ativo|realizavel a longo prazo|ativo realizavel a longo prazo|imobilizado|ativo imobilizado|intangivel|ativo intangivel|investimentos|direito de uso)$' then
      return 'ativo_nao_circulante';
    end if;
    if n ~ '^(passivo (nao circulante|exigivel a longo prazo|de longo prazo)|nao circulante passivo|exigivel a longo prazo)$'
       or (v_lp and n ~ '^(emprestimos|financiamentos|obrigacoes|contas a pagar|fornecedores)') then
      return 'passivo_nao_circulante';
    end if;
    if n ~ '^(ativo circulante|circulante ativo|disponivel|disponibilidades|caixa e equivalentes( de caixa)?|bancos( conta movimento)?|aplicacoes financeiras)$' then
      return 'ativo_circulante';
    end if;
    if n ~ '^(passivo circulante|circulante passivo|contas a pagar|fornecedores)$'
       or n ~ '^obrigacoes( (com o pessoal|com pessoal|trabalhistas|sociais|fiscais|tributarias|previdenciarias)( e (trabalhistas|sociais|fiscais|tributarias|previdenciarias))*)?$'
       or n ~ '^(emprestimos e financiamentos|emprestimos|financiamentos)( -| /)? (de |a )?(curto prazo|cp)$' then
      return 'passivo_circulante';
    end if;
    if n = 'patrimonio liquido' then
      return 'patrimonio_liquido';
    end if;
  end if;

  -- ---- RESULTADO -----------------------------------------------------------
  -- Âncora nas duas pontas, sempre: "despesas antecipadas" (ativo), "receitas diferidas" (passivo),
  -- "impostos a recolher" (passivo) e "provisão para IR" no balancete NÃO podem cair aqui por conterem
  -- uma palavra de resultado.
  if v_res then
    if n ~ '^((resultado|receitas?|despesas?)( e (receitas?|despesas?))? financeir[oa]s?( liquid[oa]s?)?)$' then
      return 'resultado_financeiro';
    end if;
    if v_dre and n ~ '^(imposto de renda( e contribuicao social)?( sobre o lucro)?|contribuicao social( sobre o lucro)?|irpj( e csll)?|csll|tributos sobre o lucro|impostos sobre o lucro|provisao para (imposto de renda|irpj)( e contribuicao social| e csll)?)$' then
      return 'impostos_lucro';
    end if;
    if v_dre and n ~ '^deducoes( da receita( bruta)?| de vendas| e abatimentos)?$' then
      return 'receita_bruta';
    end if;
    if n ~ '^(receitas?( operacionais?)?( brutas?)?|receitas? brutas? operacionais?|receitas? (de )?(vendas?|servicos|vendas e servicos|vendas de mercadorias)|faturamento( bruto)?|vendas( brutas)?( de (produtos|mercadorias|servicos|produtos e servicos|mercadorias e servicos|produtos, mercadorias e servicos))?)$' then
      return 'receita_bruta';
    end if;
    if n ~ '^(cmv|cpv|csp|custos?( operacionais?)?|custos? d[aeo]s? (vendas|produtos vendidos|mercadorias vendidas|servicos prestados|produtos e servicos|produtos|mercadorias|servicos)( vendid[oa]s| prestad[oa]s)?)$' then
      return 'custos';
    end if;
    if n ~ '^despesas (operacionais|administrativas|gerais|comerciais|com vendas|de vendas|com pessoal|gerais e administrativas|administrativas e gerais|administrativas e comerciais|com vendas e administrativas)$' then
      return 'despesas_operacionais';
    end if;
  end if;

  -- NULL de propósito (cada um é "procurei e não é inequívoco", não "esqueci"): ver o cabeçalho da 0203.
  return null;
end $$;

comment on function fn_secao_canonica_da_secao_bruta(text, text) is
  '0203: seção canônica inferida do texto da seção BRUTA (campo_extraido.secao) quando a IA não deu secao_canonica. Pura e conservadora: casa o texto INTEIRO (âncora nas duas pontas) e só nos cinco tipos de demonstração (BALANCO, BALANCETE, COMBINADO, DF_AUDITADA, DRE). Ambíguo -> NULL: ATIVO/PASSIVO sozinhos, TOTAL DO ATIVO, PASSIVO E PL, TOTAL(IS), LUCRO BRUTO, RESULTADO (menos o financeiro), RECEITA LÍQUIDA, Eliminações do combinado, Balancete Analítico, RESUMO DO BALANCETE, CIRCULANTE sem lado, PROVISÕES, EMPRÉSTIMOS E FINANCIAMENTOS sem prazo, NAO_CLASSIFICAVEL, CONTAS DE RESULTADO - RECEITAS.';

grant execute on function fn_secao_canonica_da_secao_bruta(text, text) to authenticated;

create or replace function fn_registrar_campos_extraidos(p_documento_versao_id uuid, p_campos jsonb, p_nivel nivel_autonomia DEFAULT 'N0'::nivel_autonomia, p_falha_motivo text DEFAULT NULL::text, p_tem_dado_financeiro boolean DEFAULT NULL::boolean)
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

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'extracao_sombra', 'documento_versao:'||p_documento_versao_id,
            jsonb_build_object('campos', v_count, 'nivel', p_nivel, 'falha_motivo', p_falha_motivo,
                               'tem_dado_financeiro', p_tem_dado_financeiro, 'auto_aceitos', v_n_auto_aceitos));

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

comment on function fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text, boolean) is
  'Grava campos extraídos e roda as três guardas (0043: fn_avaliar_guardas_extracao). Sinal 3 ("veio vazia") só dispara extracao_falhou quando p_tem_dado_financeiro não é explicitamente false — 0111: documento sem valor monetário por natureza (certidão, organograma, parecer de auditoria) não é falha de extração. 0203: quando a IA não dá secao_canonica, ela é inferida do texto da seção bruta (fn_secao_canonica_da_secao_bruta) e a linha grava secao_canonica_inferida = true; o que a IA deu nunca é sobrescrito.';

grant execute on function fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. BACKFILL das linhas que já estão no banco — função, para o teste exercer a MESMA conta da migration
-- ---------------------------------------------------------------------------
-- Só extração (origem_valor = 'extracao') que ninguém revisou (revisado_por nulo): linha transcrita por
-- humano ou revisada por humano é triagem que existe e não se desfaz por regra de texto. Todas as versões,
-- não só a vigente: a versão antiga não é lida, e marcar só a vigente deixaria o banco com duas verdades
-- sobre a mesma regra. Idempotente: depois da primeira rodada o `where secao_canonica is null` não alcança
-- mais nada que a função reconheça. `p_caso_id` nulo = todos os casos. Ação de migration/service_role —
-- sem grant para o portal.
create or replace function fn_inferir_secao_canonica_das_linhas(p_caso_id uuid default null)
returns jsonb language plpgsql as $$
declare
  v_linhas int; v_versoes int; v_casos int;
begin
  with upd as (
    update campo_extraido ce
       set secao_canonica = x.s,
           secao_canonica_inferida = true
      from (select ce2.id, d.caso_id,
                   fn_secao_canonica_da_secao_bruta(ce2.secao, d.tipo_taxonomia) as s
              from campo_extraido ce2
              join documento_versao dv on dv.id = ce2.documento_versao_id
              join documento d on d.id = dv.documento_id
             where nullif(btrim(ce2.secao_canonica), '') is null
               and ce2.secao is not null
               and ce2.origem_valor = 'extracao'
               and ce2.revisado_por is null
               and (p_caso_id is null or d.caso_id = p_caso_id)) x
     where ce.id = x.id and x.s is not null
    returning ce.documento_versao_id, x.caso_id
  )
  select count(*), count(distinct documento_versao_id), count(distinct caso_id)
    into v_linhas, v_versoes, v_casos from upd;
  return jsonb_build_object('linhas', v_linhas, 'versoes', v_versoes, 'casos', v_casos);
end $$;

comment on function fn_inferir_secao_canonica_das_linhas(uuid) is
  '0203: backfill de secao_canonica nas linhas extraídas que a IA deixou sem seção, a partir da seção bruta (fn_secao_canonica_da_secao_bruta). Marca secao_canonica_inferida. Ignora linha revisada ou transcrita por humano. Idempotente. NÃO recomputa reconciliação nem completude: depois dela, rodar fn_reconciliar_caso e fn_recomputar_completude nos casos afetados.';

do $$
declare
  v_r jsonb := fn_inferir_secao_canonica_das_linhas();
begin
  raise notice '0203 backfill: % linha(s) em % versão(ões) de % caso(s) ganharam secao_canonica inferida',
    v_r->>'linhas', v_r->>'versoes', v_r->>'casos';

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:migration_0203', 'secao_canonica_inferida_backfill', 'campo_extraido',
            v_r || jsonb_build_object('porque', 'a IA devolveu secao_canonica nula e a linha sumia de receita/custo/giro; '
                                                 'inferida do texto da seção bruta, conservadora, marcada secao_canonica_inferida'));
end $$;

-- ---------------------------------------------------------------------------
-- 5. A SONDA
-- ---------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, porque, severidade, ordem) values
  ('secao_inferida_funcao', '0203', 'funcao', 'fn_secao_canonica_da_secao_bruta', null,
   'Sem ela a linha que a IA devolve com secao_canonica nula some de receita, custo e giro do realizado. MEDIDO em '
   'produção (05/10/2026, Fw Valtra, DRE 2025): 136 de 724 linhas sem seção; receita bruta do realizado 235.650 '
   'em vez de ~43,85 mi, CUSTO_VARIAVEL 26.958%, PMR 19.674 dias.',
   'importante', 861),
  ('secao_inferida_backfill_funcao', '0203', 'funcao', 'fn_inferir_secao_canonica_das_linhas', null,
   'O backfill das linhas já gravadas sem seção; sem ele a correção vale só para a extração nova.',
   'importante', 864),
  ('secao_inferida_coluna', '0203', 'coluna', 'campo_extraido.secao_canonica_inferida', null,
   'A linha precisa dizer que a seção foi INFERIDA do texto da seção bruta e não dada pela IA (regra 1/7).',
   'importante', 862),
  ('secao_inferida_na_gravacao', '0203', 'corpo', 'fn_registrar_campos_extraidos',
   'v_secao := fn_secao_canonica_da_secao_bruta(',
   'Sem este corpo a extração nova continua gravando secao_canonica nula quando a IA não classifica, e o backfill '
   'da 0203 envelhece a cada documento novo.',
   'importante', 863)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, porque = excluded.porque,
      severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0203', revisado_em = current_date,
       observacao = 'A 0203 infere a secao_canonica da seção bruta quando a IA não deu (fn_secao_canonica_da_secao_bruta), '
         'na gravação (fn_registrar_campos_extraidos) e nas linhas existentes, e marca secao_canonica_inferida. '
         'Medido em produção (Fw Valtra, DRE 2025): 136 de 724 linhas sem seção. Catalogada por função, coluna e corpo '
         '(secao_inferida_*).'
 where id = true;
