-- =============================================================================
-- 0204 — A SEÇÃO QUE O DOCUMENTO JÁ DIZIA PELA ÁRVORE E O ATIVO CIRCULANTE QUE NÃO FECHAVA
--
-- O DEFEITO (medido em PRODUÇÃO, 05/10/2026, só leitura, DEPOIS da 0203 aplicada; Fw Valtra 03a66ab6, BALANCO ref 2025,
-- coluna "Saldo Final"). Sobraram linhas sem `secao_canonica` cuja seção bruta NÃO é um texto que a regra de nome (0203)
-- reconheça, mas que é o NOME DE OUTRA LINHA DO MESMO DOCUMENTO — e essa outra linha TEM seção:
--     CAIXA MATRIZ                         95.747,82   seção bruta "CAIXA"
--     DUPLICATAS A RECEBER              4.292.868,90   seção bruta "CLIENTES"
--     DUPLICATAS A RECEBER OUTROS       3.166.371,69   seção bruta "DUPLICATAS A RECEBER"      (neto de CLIENTES)
--     DUPLICATAS A RECEBER FILIAL 01    1.126.497,21   idem
--     TÍTULOS E VALORES IMOBILIÁRIOS       55.000,00   seção bruta "OUTROS CRÉDITOS"
--     FUNDOS DE INVESTIMENTOS             114.429,85   idem
--     ADIANTAMENTOS A FORNECEDORES        439.229,17   idem
--     ADIANTAMENTO A EMPREGADOS             4.950,00   idem
--     CRÉDITOS A RECEBER                        0,00   idem
--     TRIBUTOS A RECUPERAR/COMPENSAR      409.958,77   idem
--     (netos) "OUROCAP PU" 5.000 sob "TITULOS E VALORES IMOBILIÁRIOS"; "ICMS A RECUPERAR" 186.110,09 sob
--     "TRIBUTOS A RECUPERAR/COMPENSAR"…
-- Ao mesmo tempo, no MESMO documento, há linha cuja `chave` é "CLIENTES" com seção bruta "ATIVO CIRCULANTE" e canônica
-- ativo_circulante, e a seção bruta "OUTROS CRÉDITOS" tem 32 linhas com ativo_circulante e 6 sem. A hierarquia do próprio
-- documento já dizia a seção. EFEITO medido no export do Fw Valtra: resíduo de reconciliação do ATIVO CIRCULANTE de
-- 3.750.141 em 2025 (9,7% do ativo) e 2.422.985 em 2022 — contas reais do AC fora da soma, porque o agrupamento é por seção
-- e a seção nula é "família própria" (fn_familia_da_secao).
--
-- A CAUSA: a 0203 olha só o TEXTO da seção bruta, e "CLIENTES", "CAIXA", "DUPLICATAS A RECEBER" sozinhos não dizem o lado
-- nem o prazo (conservadora de propósito: CLIENTES pode ser ativo circulante ou longo prazo). Quem diz é o PAI: a linha
-- do documento que se chama "CLIENTES" e está sob "ATIVO CIRCULANTE". Nada no banco subia essa árvore.
--
-- A REGRA (comportamento), `fn_herdar_secao_pela_arvore(versão, caso)` — determinística, só sobre linhas SEM seção:
--   um NOME (texto normalizado, sem marcador de sinal nem numeração) tem uma seção quando as linhas DA MESMA VERSÃO
--   DE DOCUMENTO que o carregam — como `chave` (o pai: a linha "CLIENTES") ou como seção bruta (as irmãs: as 32 linhas
--   de "OUTROS CRÉDITOS") — que TÊM secao_canonica concordam em UMA só. Linha sem seção cuja seção bruta é esse nome
--   herda. Recursivo, rodada a rodada (o neto herda do filho que herdou na rodada anterior), no máximo 10 rodadas; só
--   preenche NULL, então ciclo (A sob B, B sob A) não trava: sem âncora com seção ninguém herda, e termina.
--   CONFLITO (duas seções para o mesmo nome — "OUTROS CRÉDITOS" em circulante e em longo prazo, ou o pai diz uma e as
--   irmãs outra) -> fica NULL, e a função DIZ quantos nomes e linhas ficaram em conflito (regra 1: o que não resolveu
--   não finge que resolveu).
--   NUNCA herda de, nem para, nome de topo ou total: "ATIVO", "PASSIVO", "TOTAL DO ATIVO", "PASSIVO E PATRIMÔNIO
--   LÍQUIDO", "CIRCULANTE", "Balancete Analítico"... Esses abrigam circulante e não circulante juntos (159 linhas sob
--   "ATIVO" em produção): concordar por acaso não é herdar, e o subtotal dentro da soma da seção dobraria a conta.
--   Fora dos cinco tipos de demonstração (BALANCO, BALANCETE, COMBINADO, DF_AUDITADA, DRE) não opina, como a 0203.
--   NÃO toca em linha revisada (revisado_por) nem transcrita por pessoa (origem_valor <> 'extracao'): triagem humana
--   existe e a regra não a desfaz — mas ESSAS linhas servem de pai, porque a seção delas é dado.
--   A linha herdada grava `secao_canonica_inferida = true` (a mesma coluna da 0203). Não distingo "pelo nome" de "pela
--   árvore" numa coluna nova: o evento_auditoria 'secao_herdada_pela_arvore' (gravação) e o aviso do backfill contam a
--   quantidade; se um dia for preciso desfazer SÓ a herança, a coluna vira text ('nome'|'arvore') numa migration à parte.
--
-- ONDE RODA (ponto único, o mesmo da 0203): `fn_registrar_campos_extraidos`, reemitida INTEIRA a partir do corpo da 0203,
-- depois do laço de inserção e ANTES das guardas/completude/classificação contábil (que leem secao_canonica). A herança
-- precisa do DOCUMENTO inteiro: o n8n grava UMA vez por documento (nó "Gravar Campos (Sombra)", depois de "Juntar
-- Blocos", N8N/build-workflow.mjs) — o documento está completo naquele momento, e a função é idempotente sobre a versão
-- inteira, então mesmo uma gravação por bloco convergiria na última. NÃO PRECISA MUDAR O n8N: a assinatura não muda.
--
-- BACKFILL: `fn_herdar_secao_pela_arvore()` sobre todas as versões, logo abaixo (depois da 0203, que já inferiu o que o
-- texto dizia: a herança parte do que a 0203 deixou). A contagem sai em `raise notice` e em evento_auditoria.
-- DEPOIS DE APLICAR, nos casos tocados: `select fn_reconciliar_caso('<caso>'); select fn_recomputar_completude('<caso>');`
-- — o que fica GRAVADO (pendências de conflito/duplicidade/intragrupo/mútuos, linha_exigida_ausente) só muda recomputado.
-- A migration não os roda: recomputar tudo na migration é efeito que ninguém pediu. Para MEDIR antes de aplicar, cole o
-- arquivo dentro de `begin; ... rollback;`: o aviso do backfill diz quantas linhas a herança alcança, sem gravar nada.
-- Reaproveitamento de triagem humana: o filtro é o da 0203 (revisado_por / origem_valor); não há outra triagem de
-- SEÇÃO no banco (a 0179 é do papel da ENTIDADE, outro eixo).
--
-- TETO CONHECIDO: o que o documento não diz por árvore nem por irmã (linha cuja seção bruta é nula, ou cujo nome não é
-- chave nem seção de ninguém que tenha seção) segue NULL e segue fora do realizado; profundidade acima de 10 níveis
-- termina na rodada seguinte (a gravação/backfill seguinte retoma). A 0204 não muda o prompt de extração.
--
-- NÃO FAZ: não toca em produção por estar escrita; migration escrita ≠ aplicada. Quem responde é a sonda, contra o
-- banco em que se está conectado:
--
--   select chave, migration, tipo, objeto, presente, detalhe, porque
--     from fn_instalacao_conferir() where not presente order by 1;
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/secao_herdada_pela_arvore.test.sql — 37 asserts. Com a correção desligada (fn_herdar_secao_pela_arvore devolvendo zero) reprovam 21; só a gravação sem chamar a herança,
-- 15; sem o PAI (chave), 19; sem as IRMÃS (seção bruta), 12; sem recursão (1 rodada), 13; sem o teto de 10 rodadas, 2; topo/total
-- como pai, 5; conflito resolvido no min() em vez de NULL, 5; conflito não declarado, 2; linha revisada/transcrita como alvo, 2;
-- herança vazando entre versões, 4; sem restringir aos cinco tipos, 2; sem a marca secao_canonica_inferida, 10; sem tirar o código
-- contábil do ERP, 3; sobrescrevendo o que a IA deu, 9. Cada mutação foi aplicada sobre o banco com a migration e reprovou ISOLADA.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. O NOME DE SEÇÃO NORMALIZADO e o que é TOPO/TOTAL (puras)
-- ---------------------------------------------------------------------------
-- O mesmo tratamento da 0203 (fn_secao_canonica_da_secao_bruta), mais o código contábil do ERP que a 0202 já sabe
-- tirar ("1.1.02 CLIENTES" é o pai de quem está sob "CLIENTES"): minúsculas sem acento, sem o marcador de sinal
-- "(-)", "=", sem a numeração do cabeçalho ("1.1 -", "II -"), sem pontuação final. Dois textos que a 0203 leria
-- como o mesmo cabeçalho são o mesmo nome aqui. Vazio -> NULL.
create or replace function fn_nome_de_secao_normalizado(p_texto text)
returns text language sql immutable as $$
  select nullif(
    regexp_replace(
      regexp_replace(
        regexp_replace(fn_normalizar_texto(fn_sem_codigo_de_conta(p_texto)), '^(\(\s*[-+=]\s*\)|[-+=])\s*', ''),
        '^([0-9]+(\.[0-9]+)*|[ivx]+)\s*[-.)]\s*', ''),
      '[\s:.;]+$', ''),
    '')
$$;

-- Nome que é o TOPO da demonstração, um total, ou o nome do documento — nunca uma seção: abriga lados diferentes
-- do balanço (159 linhas sob "ATIVO" em produção) e o subtotal dentro da soma da seção alheia dobra a conta.
-- Recebe o nome JÁ normalizado.
create or replace function fn_nome_de_topo_ou_total(p_nome text)
returns boolean language sql immutable as $$
  select p_nome ~ '^(ativo|passivo|ativo e passivo|passivo e patrimonio liquido|circulante|nao circulante|balanco patrimonial|balancete analitico|balancete|resumo do balancete|eliminacoes do combinado|contas temporarias|nao classificavel|nao_classificavel|dre|demonstracao do resultado( do exercicio)?)$'
      or p_nome ~ '(^| )(total|totais)( |$)'
$$;

-- ---------------------------------------------------------------------------
-- 2. A HERANÇA PELA ÁRVORE
-- ---------------------------------------------------------------------------
-- p_documento_versao_id e p_caso_id nulos = todas as versões. Devolve {linhas, versoes, casos, conflitos,
-- linhas_em_conflito, rodadas}. `conflitos` = nomes (por versão) com duas seções que ficaram NULL por isso.
-- MATERIALIZED nas três CTEs: sem ele o Postgres inlina `e` (usada três vezes, mas `fonte`/`unica` uma vez cada) e o
-- agrupamento que decide "uma só seção" vira uma subconsulta correlata por linha alvo.
create or replace function fn_herdar_secao_pela_arvore(p_documento_versao_id uuid default null, p_caso_id uuid default null)
returns jsonb language plpgsql as $$
declare
  c_rodadas constant int := 10;
  v_ids     uuid[] := '{}';
  v_novos   uuid[];
  v_conf    int := 0;
  v_lconf   int := 0;
  v_i       int := 0;
  v_linhas  int; v_versoes int; v_casos int;
begin
  loop
    v_i := v_i + 1;
    with e as materialized (
      select ce.id, ce.documento_versao_id, d.caso_id,
             nullif(btrim(ce.secao_canonica), '')          as sc,
             fn_nome_de_secao_normalizado(ce.chave)          as nc,
             fn_nome_de_secao_normalizado(ce.secao)          as ns,
             (ce.origem_valor = 'extracao' and ce.revisado_por is null) as alvo
        from campo_extraido ce
        join documento_versao dv on dv.id = ce.documento_versao_id
        join documento d on d.id = dv.documento_id
       where d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DF_AUDITADA', 'DRE')
         and (p_documento_versao_id is null or ce.documento_versao_id = p_documento_versao_id)
         and (p_caso_id is null or d.caso_id = p_caso_id)
    ), fonte as materialized (
      -- o PAI: a linha do documento cuja chave é o nome, e que tem seção
      select documento_versao_id, nc as nome, sc from e
       where sc is not null and nc is not null and not fn_nome_de_topo_ou_total(nc)
      union
      -- as IRMÃS: as outras linhas que estão sob a mesma seção bruta e têm seção
      select documento_versao_id, ns, sc from e
       where sc is not null and ns is not null and not fn_nome_de_topo_ou_total(ns)
    ), unica as materialized (
      select documento_versao_id, nome, min(sc) as sc, count(*) as n   -- (versão, nome, sc) já é distinto: n = nº de seções
        from fonte group by 1, 2
    ), upd as (
      update campo_extraido ce
         set secao_canonica = u.sc, secao_canonica_inferida = true
        from e join unica u on u.documento_versao_id = e.documento_versao_id and u.nome = e.ns
       where ce.id = e.id and e.alvo and e.sc is null and u.n = 1
      returning ce.id
    )
    select (select coalesce(array_agg(id), '{}') from upd),
           (select count(distinct (u.documento_versao_id, u.nome)) from unica u
             where u.n > 1 and exists (select 1 from e where e.documento_versao_id = u.documento_versao_id
                                         and e.ns = u.nome and e.alvo and e.sc is null)),
           (select count(*) from e join unica u on u.documento_versao_id = e.documento_versao_id and u.nome = e.ns
             where u.n > 1 and e.alvo and e.sc is null)
      into v_novos, v_conf, v_lconf;

    v_ids := v_ids || v_novos;
    exit when coalesce(array_length(v_novos, 1), 0) = 0 or v_i >= c_rodadas;
  end loop;

  select count(*), count(distinct ce.documento_versao_id), count(distinct d.caso_id)
    into v_linhas, v_versoes, v_casos
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
   where ce.id = any (v_ids);

  return jsonb_build_object('linhas', v_linhas, 'versoes', v_versoes, 'casos', v_casos,
                            'conflitos', v_conf, 'linhas_em_conflito', v_lconf, 'rodadas', v_i);
end $$;

comment on function fn_herdar_secao_pela_arvore(uuid, uuid) is
  '0204: herda secao_canonica pela ÁRVORE do próprio documento. Para linha sem seção (extração, sem revisão humana) cuja seção bruta, normalizada, é a chave de outra linha da MESMA versão que tem seção (o pai) ou a seção bruta de outras que têm (as irmãs), herda — se todas concordam em UMA seção; conflito fica NULL e é contado. Recursivo (até 10 rodadas), nunca herda de/para topo ou total (ATIVO, TOTAL DO ATIVO…), só nos cinco tipos de demonstração. Marca secao_canonica_inferida. Idempotente. Devolve {linhas, versoes, casos, conflitos, linhas_em_conflito, rodadas}.';

-- ---------------------------------------------------------------------------
-- 3. O PONTO ÚNICO DE ESCRITA — reemitido INTEIRO a partir do corpo da 0203 (NÃO por replace de texto)
-- ---------------------------------------------------------------------------
-- Chamadores medidos (grep em Supabase/ N8N/ portal/src Verificação/): o nó "Gravar Campos (Sombra)" da ingestão, o arnês
-- Verificação/run.mts e variacoes.mts e os testes SQL. Única mudança: a chamada a fn_herdar_secao_pela_arvore depois do laço.
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
  v_herdadas           jsonb;
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
  'Grava campos extraídos e roda as três guardas (0043: fn_avaliar_guardas_extracao). Sinal 3 ("veio vazia") só dispara extracao_falhou quando p_tem_dado_financeiro não é explicitamente false — 0111: documento sem valor monetário por natureza (certidão, organograma, parecer de auditoria) não é falha de extração. 0203: quando a IA não dá secao_canonica, ela é inferida do texto da seção bruta (fn_secao_canonica_da_secao_bruta) e a linha grava secao_canonica_inferida = true; o que a IA deu nunca é sobrescrito. 0204: depois do laço, a seção que ainda falta é herdada pela árvore do próprio documento (fn_herdar_secao_pela_arvore).';

grant execute on function fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. BACKFILL das linhas que já estão no banco (depois da 0203, que já inferiu o que o texto dizia)
-- ---------------------------------------------------------------------------
do $$
declare
  v_r jsonb := fn_herdar_secao_pela_arvore();
begin
  raise notice '0204 backfill: % linha(s) em % versão(ões) de % caso(s) herdaram secao_canonica pela árvore do documento; % nome(s) em conflito (% linha(s)) ficaram NULL',
    v_r->>'linhas', v_r->>'versoes', v_r->>'casos', v_r->>'conflitos', v_r->>'linhas_em_conflito';

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:migration_0204', 'secao_herdada_pela_arvore_backfill', 'campo_extraido',
            v_r || jsonb_build_object('porque', 'depois da 0203 ainda havia linha sem secao_canonica cuja seção bruta é o nome de outra linha do mesmo documento que TEM seção (Fw Valtra: resíduo do ativo circulante 3.750.141 em 2025); herdada pela árvore, marcada secao_canonica_inferida'));
end $$;

-- ---------------------------------------------------------------------------
-- 5. A SONDA
-- ---------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, porque, severidade, ordem) values
  ('secao_herdada_funcao', '0204', 'funcao', 'fn_herdar_secao_pela_arvore', null,
   'Sem ela a linha cuja seção bruta é o NOME de outra linha do mesmo documento (CLIENTES, CAIXA, OUTROS CRÉDITOS) fica sem secao_canonica e some do realizado. MEDIDO em produção (05/10/2026, Fw Valtra, BALANCO 2025, depois da 0203): resíduo de reconciliação do ativo circulante 3.750.141 em 2025 (9,7% do ativo) e 2.422.985 em 2022.',
   'importante', 865),
  ('secao_herdada_nome_funcao', '0204', 'funcao', 'fn_nome_de_secao_normalizado', null,
   'A chave de comparação da herança (a mesma normalização de cabeçalho da 0203); sem ela fn_herdar_secao_pela_arvore não existe.',
   'importante', 866),
  ('secao_herdada_na_gravacao', '0204', 'corpo', 'fn_registrar_campos_extraidos',
   'v_herdadas := fn_herdar_secao_pela_arvore(',
   'Sem este corpo a extração nova continua gravando sem seção a linha que o próprio documento classifica pela árvore, e o backfill da 0204 envelhece a cada documento novo.',
   'importante', 867)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, porque = excluded.porque,
      severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0204', revisado_em = current_date,
       observacao = 'A 0204 herda a secao_canonica pela árvore do próprio documento (fn_herdar_secao_pela_arvore: o pai pela chave, as irmãs pela seção bruta, só se concordam; nunca de topo/total), na gravação (fn_registrar_campos_extraidos) e nas linhas existentes. '
         'Medido em produção depois da 0203 (Fw Valtra, BALANCO 2025): resíduo do ativo circulante 3.750.141 (9,7% do ativo). Catalogada por função e corpo (secao_herdada_*).'
 where id = true;
