-- 0240 — A VERSÃO ATUAL QUE NÃO SEGUIA A VIGENTE: fn_versao_atual segue a regra de versão vigente da 0233; fn_reconferir_caso continua avaliando as guardas na versão MAIS NOVA.
--
-- O DEFEITO. fn_versao_atual (0009) devolvia max(n_versao), com ou sem linha. A 0233 mudou a versão vigente (fn_versao_com_extracao e a CTE versao_vigente de fn_linhas_para_modelagem): a maior n_versao COM campo_extraido,
-- e a que esgotou a falha transitória só vale quando nenhuma versão com linha está sem a flag (entre as com a flag, a de mais linhas). Ela listou fn_versao_atual como "DEVERIA SEGUIR e NÃO foi alterada" (janela de
-- re-extração). Efeito medido no banco local (arranjo do teste: v1 com ATIVO e PASSIVO E PL, v2 flagada só com o ATIVO): a Modelagem e o export mostram a v1 e fn_reconciliar_ativo_passivo_pl conferia a v2 (pré-condição
-- em vez de `ok`). As reconciliações conferiam um número diferente do que o book mostra.
--
-- A JANELA QUE A 0233 TEMIA. Entre fn_registrar_documento (cria a v2, vazia) e fn_registrar_campos_extraidos (grava as linhas) as reconciliações liam a v2 VAZIA. Com a troca leem a v1 (com dado), igual à Modelagem. Quando ela roda
-- no n8n (N8N/build-workflow.mjs ~3300-3340): fn_reconciliar_por_documento DEPOIS de gravar o diagnóstico e fn_reconciliar_caso no fim do lote, ambos depois de fn_registrar_campos_extraidos; a janela só é lida por um clique do
-- portal (fn_reconferir_caso) ou por quem reconcilia no meio do lote. Documento sem NENHUMA linha continua com versão atual (a mais nova), não nula.
--
-- A CORREÇÃO, NO PONTO ÚNICO. fn_versao_atual = coalesce(fn_versao_com_extracao(p), fn_versao_mais_nova(p)). fn_versao_mais_nova é o corpo antigo da 0009 com o nome certo. Mesma assinatura, mesmo retorno, mesma ACL,
-- stable. Um chamador deixou de poder ler a vigente, e é o motivo de a função nova existir:
--   * fn_reconferir_caso (0043) passa o id de fn_versao_atual a fn_reavaliar_guardas_extracao. A v2 que o reenvio criou e que voltou SEM linha tem a pendência extracao:falhou (por documento) aberta; avaliando a v1 (que tem
--     linha) o Sinal 3 a fecharia com "a versão tem linhas" e o padrao_suspeito/baixa_confianca da v2 com "a regra de hoje não abriria": a falha do reenvio some da fila, com o book mostrando a v1 (regra 7: falha com cara de
--     "não houve falha"). Achado ao conferir os chamadores, antes de escrever. Ela é reemitida aqui (corpo da 0043, uma linha trocada) e chama fn_versao_mais_nova; as reconciliações dentro dela seguem a vigente.
--
-- OS CHAMADORES DE fn_versao_atual (grep em Supabase/ N8N/ portal/src/, 11/11/2026; N8N/ e portal/src/: nenhum) E A SEMÂNTICA QUE CADA UM QUER:
--   * LEEM CONTEÚDO para reconciliar, devem seguir a vigente (= o book): fn_reconciliar_arvore, fn_reconciliar_ativo_passivo_pl, fn_reconciliar_caixa_bp_fluxo, fn_reconciliar_despfin_dre_vs_divida,
--     fn_reconciliar_intragrupo, fn_reconciliar_duplicidade (indireto, por fn_pares_duplicados_do_caso, reemitida), fn_reconciliar_mutuos (inclusive o `where ce3.documento_versao_id = fn_versao_atual(d.id)` e os join lateral), fn_reconciliar_receita_dre_vs_faturamento.
--     fn_reconciliar_por_documento e fn_reconciliar_caso só despacham para as acima (não chamam a função). Nenhuma ESCREVE nem avalia guarda de extração: só abrem/fecham pendência de RECONCILIAÇÃO pelo número lido.
--   * AVALIA GUARDA (precisa da mais nova): fn_reconferir_caso, reemitida aqui. fn_reavaliar_guardas_extracao e fn_registrar_campos_extraidos recebem o id da versão por argumento e não chamam a função.
--   * Testes: canastra.test.sql e divergencia_prevalece_na_rodada.test.sql acham a versão de documentos de UMA versão (vigente = mais nova, sem mudança); espelho_grupo_a.test.sql ESCREVE linhas na versão recém-criada,
--     vazia: trocado para fn_versao_mais_nova (com a vigente escreveria na v1 se já houvesse linha).
--
-- DENTRO DESTA FATIA DEPOIS DA REVISÃO INDEPENDENTE: fn_pares_duplicados_do_caso (0144), lida por fn_reconciliar_duplicidade, a oitava reconciliação, dizia aplicar "só a versão vigente (0102)" mas usava max(n_versao) sem exigir
-- linha: com a v1 com linhas e a v2 flagada, 7 das 8 reconciliações conferiam a v1 e a duplicidade abria ou fechava o par pela v2. Reemitida aqui (corpo vigente da 0144, uma condição trocada: `dv.id` = fn_versao_atual,
-- resolvida uma vez por documento numa CTE MATERIALIZED). Sem custo mensurável: fn_pares_duplicados_do_caso x30 no caso maior (31 documentos) 4,69 s e 4,17 s antes, 4,37 s e 4,48 s depois. O comment de
-- fn_versao_com_extracao (0233) citava fn_versao_atual como max(n_versao): reemitido com fn_versao_mais_nova.
-- FORA DESTA FATIA (regra 6, pendência declarada): `versoesVigentes` de portal/src/lib/export.ts (a mesma divergência em TypeScript, apontada pela 0233).
--
-- DESEMPENHO (banco local do run.sh: 401 documentos, 440 versões, 3.994 linhas; 2 rodadas alternadas antes/depois, "antes" = o corpo antigo via fn_versao_mais_nova): fn_versao_atual por documento passou de ~0,002 ms para
-- ~0,05 ms (300 varreduras dos 401 documentos: 253-254 ms antes, 6.161-6.193 ms depois, 24x; é o índice de evento_auditoria por entidade_ref que a flag lê, mais um exists em campo_extraido por versão). A conta é
-- barata em absoluto, e o custo fim a fim das reconciliações ficou DENTRO DO RUÍDO: fn_reconciliar_caso x30 no caso maior (~2,3 s cada) 70,4 s e 67,2 s antes, 73,2 s e 73,1 s depois (+4 a +9%, abaixo da variação
-- entre as duas rodadas "antes"). O plano das chamadas em join lateral e em `ce3.documento_versao_id = fn_versao_atual(d.id)` mantém o Index Only Scan com a função na condição (a SQL inlina o coalesce); a estimativa não
-- degenera para rows=1 (a 0164: 56 linhas estimadas antes e 200 depois, contra 237 reais; o EXPLAIN ANALYZE do join lateral foi de 1,8 ms para 22-24 ms, 3.797 linhas nos dois). Em produção: 1.465 documentos com linha, 9 com 2 versões
-- (0233) — o que a reconciliação de um caso grande paga a mais é de ordem de 50 microssegundos por documento lido.
--
-- SEM BACKFILL: o critério é lido na hora. As pendências de reconciliação já gravadas se reavaliam no próximo fn_reconciliar_caso/fn_reconferir_caso; em produção a regra nova muda a resposta de 0 documentos hoje (0 eventos
-- com falha_transitoria_esgotada em 11/11/2026, 0233): vale a partir do n8n P8.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/a_versao_atual_que_nao_seguia_a_vigente.test.sql — 16 asserts (16 execuções), medidos em 11/11/2026 com o assert trocado por raise warning (`p40.medindo = on`), que CONTA; cada
-- sabotagem é a função reemitida sobre o banco já montado pelo run.sh (cópia por template, teste rodado inteiro, aviso MEDIDO lido). Controle (migration intacta): 0 dos 16 reprovam. fn_versao_atual desligada (volta a
-- max(n_versao), fn_versao_mais_nova): 5 (4 de comportamento: a vigente, a reconciliação lendo a v1 e os 2 da duplicidade, que lê por ela; + 1 da sonda). fn_pares_duplicados_do_caso desligada (o corpo da 0144 de volta): 3 (2 de comportamento, o par da v1 visto e a duplicidade acusada, + 1 da sonda). fn_reconferir_caso apontando para a vigente (fn_versao_atual): 2 (1 de comportamento, a extracao_falhou
-- da v2 vazia fechada, + 1 da sonda). As três desligadas juntas (o estado da 0239) reprovam os de fn_versao_atual e os da duplicidade; o da reconferência passa, porque lá fn_versao_atual era a mais nova. Os asserts de
-- controle (documento sem linha tem versão atual; documento inexistente = nulo; v2 completa vence) passam na função antiga de propósito: protegem o comportamento de antes.
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- fn_versao_mais_nova: o corpo da 0009 de fn_versao_atual, com o nome que ele sempre mereceu. "A documento_versao de maior n_versao, com ou sem linha."
-- ---------------------------------------------------------------------------
create or replace function fn_versao_mais_nova(p_documento_id uuid)
returns uuid
language sql
stable
as $$
  select id from documento_versao where documento_id = p_documento_id order by n_versao desc limit 1;
$$;

comment on function fn_versao_mais_nova(uuid) is
  '0240: o id da documento_versao de MAIOR n_versao do documento, com ou sem campo_extraido (o corpo que fn_versao_atual teve de 0009 a 0239). É a resposta certa a "o que o reenvio acabou de criar?" e a "que versão a guarda de extração avalia?": a extração que falhou é a mais nova, mesmo vazia. NÃO é a resposta a "que número o book mostra?" — essa é fn_versao_com_extracao. SECURITY INVOKER, somente leitura.';

-- ---------------------------------------------------------------------------
-- fn_versao_atual: passa a seguir a versão VIGENTE (0102/0233); a mais nova só entra quando nenhuma versão do documento tem linha (documento recém-registrado, antes de fn_registrar_campos_extraidos).
-- Mesma assinatura, mesmo retorno, mesma ACL (create or replace preserva os grants).
-- ---------------------------------------------------------------------------
create or replace function fn_versao_atual(p_documento_id uuid)
returns uuid
language sql
stable
as $$
  select coalesce(fn_versao_com_extracao(p_documento_id), fn_versao_mais_nova(p_documento_id));
$$;

comment on function fn_versao_atual(uuid) is
  '0240: a versão que as RECONCILIAÇÕES leem = a vigente de fn_versao_com_extracao (a de maior n_versao com linha; a com falha_transitoria_esgotada só vale quando nenhuma com linha está sem a flag, 0233), e a mais nova (fn_versao_mais_nova) só quando nenhuma versão tem linha. Até a 0239 era max(n_versao) puro: com a v2 parcial promovida as reconciliações conferiam a leitura pior enquanto a Modelagem e o export mostravam a v1, e na janela entre fn_registrar_documento e fn_registrar_campos_extraidos liam a v2 VAZIA. Quem precisa da mais nova mesmo vazia (guarda de extração, escrita na versão recém-criada) chama fn_versao_mais_nova. SECURITY INVOKER, somente leitura.';

revoke all on function fn_versao_mais_nova(uuid) from public;
grant execute on function fn_versao_mais_nova(uuid) to authenticated, service_role;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    execute 'grant execute on function fn_versao_mais_nova(uuid) to supabase_read_only_user';
  end if;
end $$;

create or replace function fn_reconferir_caso(p_caso_id uuid, p_autor text default 'portal:reconferir')
returns jsonb
language plpgsql
as $$
  -- marca-0240
declare
  v_doc          record;
  v_versao       uuid;
  v_n_docs       int := 0;
  v_resolvidas   int := 0;
  v_abertas      int := 0;
  v_r            jsonb;
  v_antes        int;
  v_depois       int;
  v_completude   jsonb;
begin
  if not exists (select 1 from caso where id = p_caso_id) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Caso %s não existe.', p_caso_id));
  end if;

  select count(*) into v_antes from pendencia where caso_id = p_caso_id and estado <> 'resolvida';

  for v_doc in select id from documento where caso_id = p_caso_id order by criado_em loop
    v_n_docs := v_n_docs + 1;
    -- Reconciliação A/B: as próprias checagens abrem e resolvem pendência, com a
    -- regra de hoje (é o que a 0034 corrigiu e nunca foi reaplicado ao v35).
    perform fn_reconciliar_por_documento(v_doc.id);

    -- 0240: as guardas de extração avaliam a versão que o reenvio CRIOU (a mais nova, mesmo vazia), não a vigente: a v2 que voltou sem linha tem a pendência extracao:falhou aberta, e avaliar a v1 (que tem linha)
    -- a fecharia com 'a versão tem linhas' sem ninguém ter olhado, enquanto o book segue mostrando a v1.
    v_versao := fn_versao_mais_nova(v_doc.id);
    if v_versao is not null then
      v_r := fn_reavaliar_guardas_extracao(v_versao, p_autor);
      v_resolvidas := v_resolvidas + coalesce(jsonb_array_length(v_r->'resolvidas'), 0);
      v_abertas := v_abertas + coalesce(jsonb_array_length(v_r->'abertas'), 0);
    end if;
  end loop;

  v_completude := fn_recomputar_completude(p_caso_id);

  select count(*) into v_depois from pendencia where caso_id = p_caso_id and estado <> 'resolvida';

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'reconferir_caso', 'caso:'||p_caso_id,
            jsonb_build_object('pendencias_abertas', v_antes),
            jsonb_build_object('pendencias_abertas', v_depois, 'documentos', v_n_docs,
                               'guardas_resolvidas', v_resolvidas, 'guardas_abertas', v_abertas));

  return jsonb_build_object(
    'caso_id', p_caso_id,
    'documentos_reconferidos', v_n_docs,
    'pendencias_abertas_antes', v_antes,
    'pendencias_abertas_depois', v_depois,
    'guardas_resolvidas', v_resolvidas,
    'guardas_abertas', v_abertas,
    'completude', v_completude,
    -- O NÚMERO QUE IMPORTA para quem clicou: quantos achados eram de regra velha.
    'achados_de_regra_velha', greatest(v_antes - v_depois, 0));
end;
$$;

comment on function fn_reconferir_caso(uuid, text) is
  'Reaplica as regras de HOJE (reconciliação A/B, guardas de extração, completude) sobre o dado já gravado, sem gastar chamada de IA. Existe porque pendência é estado gravado e nada a reavaliava quando uma migration corrigia a regra — o portal mostrava achado corrigido como se fosse corrente (caso real: as duas pendências do v35 que a 0034 já havia fechado). 0240: as guardas de extração avaliam fn_versao_mais_nova (a que o reenvio criou, mesmo vazia), não a vigente; as reconciliações dentro dela leem a vigente (fn_versao_atual).';

-- ---------------------------------------------------------------------------
-- fn_pares_duplicados_do_caso (0144; a vigente, conferida idêntica ao corpo de schema.sql antes desta migration): a versão lida passa a ser a de fn_versao_atual (a vigente). Única mudança de lógica: o filtro
-- `dv.n_versao = max(n_versao)` vira `dv.id = vg.versao_id`, com a versão resolvida uma vez por documento numa CTE MATERIALIZED. Mesma assinatura, mesmo retorno, mesma ACL. Entrou depois da revisão
-- independente: fn_reconciliar_duplicidade é a oitava reconciliação, e com a v1 com linhas e a v2 flagada as outras sete conferiam a v1 e esta abria ou fechava o par pela v2.
-- ---------------------------------------------------------------------------
create or replace function fn_pares_duplicados_do_caso(p_caso_id uuid, p_entidade text default null)
returns table(secao_canonica text, rotulo_a text, rotulo_b text, colunas integer, valor numeric, radical_comum boolean)
language sql
stable
as $$
  -- marca-0240
  -- 0240: a versão de cada documento do caso é resolvida UMA vez por documento (MATERIALIZED: sem isso o Postgres inlina a CTE usada uma vez e a função roda por LINHA de campo_extraido, ~0,05 ms cada).
  with vigentes as materialized (
    select d.id as doc_id, fn_versao_atual(d.id) as versao_id
    from documento d
    where d.caso_id = p_caso_id
  ),
  ocorrencias as (
    select
      ce.secao_canonica,
      fn_normalizar_texto(ce.chave)                as rotulo,
      coalesce(ce.entidade_coluna, e.razao_social) as ent_col,
      coalesce(ce.periodo_coluna, p.referencia)    as per_col,
      ce.valor_num,
      ce.chave,
      ce.secao,
      ce.unidade,
      d.tipo_taxonomia,
      d.id                                         as doc_id
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d         on d.id = dv.documento_id
    join vigentes vg         on vg.doc_id = d.id
    left join entidade e     on e.id = d.entidade_id
    left join periodo p      on p.id = d.periodo_id
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      and ce.valor_num <> 0
      and ce.secao_canonica is not null
      and ce.secao_canonica <> 'NAO_CLASSIFICAVEL'
      -- Só a versão VIGENTE de cada documento (0102): ocorrência de versão
      -- superada faria uma reextração parecer duplicidade. 0240: "vigente" é a
      -- mesma versão que as outras reconciliações e a Modelagem leem (0233), e
      -- não mais max(n_versao): com a v1 com linhas e a v2 flagada a duplicidade
      -- abria ou fechava pelo número da v2 enquanto as outras sete conferiam a v1.
      and dv.id = vg.versao_id
      and (p_entidade is null
           or fn_mesma_entidade(coalesce(ce.entidade_coluna, e.razao_social), p_entidade))
  ),
  contas as (
    -- Subtotal e derivado ficam fora: o export já trata subtotal informado por
    -- estrutura, e cobrar de novo aqui duplicaria a fila de revisão.
    select * from ocorrencias o
    where fn_papel_linha(o.chave, o.tipo_taxonomia, o.unidade) = 'conta'
  ),
  -- Uma linha por (seção, rótulo, coluna): se o mesmo rótulo aparece em dois
  -- documentos com o mesmo valor, isso é concordância, não duplicidade.
  por_coluna as (
    select secao_canonica, rotulo, ent_col, per_col, min(chave) as chave,
           -- A SUBSEÇÃO DECLARADA pelo documento, agregada: é ela que denuncia o
           -- par subtotal × componente (ver o filtro `subtotal_de` abaixo).
           array_agg(distinct fn_normalizar_texto(coalesce(secao, ''))) as secoes,
           -- 0144: DE QUAIS DOCUMENTOS este rótulo veio. É o que sustenta o
           -- filtro `mesmo_documento` — o critério novo, e o mais forte dos três.
           array_agg(distinct doc_id) as docs,
           max(valor_num) as valor_num
    from contas
    group by secao_canonica, rotulo, ent_col, per_col
    having count(distinct valor_num) = 1
  ),
  pares as (
    select
      a.secao_canonica,
      a.rotulo as rotulo_a, b.rotulo as rotulo_b,
      min(a.chave) as chave_a, min(b.chave) as chave_b,
      count(*)     as colunas_iguais,
      max(abs(a.valor_num)) as valor,
      -- 0144: OS DOIS RÓTULOS SAEM DO MESMO DOCUMENTO?
      --
      -- Se saem, ele é a autoridade sobre a relação entre eles — e o que ele está
      -- dizendo é hierarquia, não duplicidade. Uma demonstração é internamente
      -- consistente por construção: cada conta aparece uma vez, e se aparecesse
      -- duas a seção não fecharia, que é trabalho da `fn_conferir_arvore` (0133),
      -- não desta checagem. O dano que a 0105 existe para achar é a soma de DUAS
      -- FONTES — o balanço e o balancete escrevendo o mesmo fato de dois jeitos.
      --
      -- Medido na v48: 33 de 33 pares candidatos estavam no mesmo documento, 32
      -- deles em linhas VIZINHAS (`ordem` a distância 1). Subtotal de grupo
      -- seguido do seu único componente, e não conta transposta duas vezes.
      bool_or(a.docs && b.docs) as mesmo_documento,
      -- É o par SUBTOTAL × COMPONENTE? O documento diz: a subseção declarada de um
      -- é o rótulo do outro. Medido no book (extração fiel): "Obrigações
      -- Tributárias" × "Parcelamentos tributários - longo prazo", "Empréstimos e
      -- Financiamentos" × "Financiamentos - FINAME/BNDES", "Partes Relacionadas" ×
      -- "Mútuos a pagar", "Investimentos" × "Participações em outras sociedades".
      -- São grupo com UM componente, não conta duplicada — e o export já os exclui
      -- da soma pela detecção estrutural. Cobrar de novo aqui encheria a fila de
      -- revisão com o que já está resolvido, que é exatamente o que a 0023 desfez.
      --
      -- 0144: ESTE FILTRO CONTINUA, MAS NÃO SE PODE MAIS CONTAR COM ELE SOZINHO.
      -- Ele depende de `secao` trazer o grupo IMEDIATO, e na v48 `secao` chega
      -- ACHATADA (subtotal e folhas com a seção de topo) — a mesma causa raiz que
      -- a 0143 documentou. Com o sinal ausente, `subtotal_de` nunca dispara.
      bool_or(a.rotulo = any(b.secoes) or b.rotulo = any(a.secoes)) as subtotal_de,
      -- MESMA SUBSEÇÃO DECLARADA? Dois rótulos para o MESMO fato estão, por
      -- construção, no mesmo lugar da demonstração. Quando o documento os coloca em
      -- subseções diferentes, ele está dizendo que são coisas diferentes — e é o
      -- que restou de falso positivo no book depois do filtro de subtotal:
      -- "Créditos tributários - ICMS sobre ativo permanente" (Realizável a Longo
      -- Prazo) e "Veículos e empilhadeiras" (Imobilizado), ambos 3.900 nos dois
      -- exercícios. Coincidência de valor, contas distintas.
      bool_or(a.secoes && b.secoes) as mesma_subsecao,
      -- O SINAL DE SUBSEÇÃO EXISTE NESTE DOCUMENTO? Sem ele o filtro `subtotal_de`
      -- não tem como disparar, e aí "Arrendamentos" × "Arrendamentos a pagar - CPC
      -- 06 (R2)" (grupo com um componente) fica indistinguível de rótulo reescrito —
      -- os dois têm radical contido. Medido no `fixture_modelagem_v35.sql`, que não
      -- traz `secao`: era o único par que ele devolvia, e era falso positivo.
      -- Então o ramo de UMA coluna (que se sustenta no radical) exige a subseção
      -- declarada; o de DUAS colunas não precisa dela, porque ali a evidência é
      -- aritmética e independente do nome.
      bool_or(coalesce(array_to_string(a.secoes, '') || array_to_string(b.secoes, ''), '') <> '') as tem_secao
    from por_coluna a
    join por_coluna b
      on b.secao_canonica = a.secao_canonica
     and b.ent_col = a.ent_col and b.per_col = a.per_col
     and b.rotulo > a.rotulo                       -- par sem repetir a ordem
     and b.valor_num = a.valor_num                 -- idêntico ao centavo
    group by a.secao_canonica, a.rotulo, b.rotulo
  ),
  -- Uma coluna em que os dois aparecem e DISCORDAM derruba o par: contas que
  -- coincidem num ano e divergem no outro são contas diferentes, ponto.
  discordantes as (
    select a.secao_canonica, a.rotulo as rotulo_a, b.rotulo as rotulo_b
    from por_coluna a
    join por_coluna b
      on b.secao_canonica = a.secao_canonica
     and b.ent_col = a.ent_col and b.per_col = a.per_col
     and b.rotulo > a.rotulo
     and b.valor_num <> a.valor_num
  )
  select
    pr.secao_canonica,
    pr.chave_a,
    pr.chave_b,
    pr.colunas_iguais::int,
    pr.valor,
    (fn_tokens_estruturais(pr.chave_a) <@ fn_tokens_estruturais(pr.chave_b)
     or fn_tokens_estruturais(pr.chave_b) <@ fn_tokens_estruturais(pr.chave_a)) as radical_comum
  from pares pr
  where not pr.mesmo_documento
    and not pr.subtotal_de
    and pr.mesma_subsecao
    and not exists (
    select 1 from discordantes dc
    where dc.secao_canonica = pr.secao_canonica
      and dc.rotulo_a = pr.rotulo_a and dc.rotulo_b = pr.rotulo_b
  )
    and (pr.colunas_iguais >= 2
         or (pr.tem_secao
             and (fn_tokens_estruturais(pr.chave_a) <@ fn_tokens_estruturais(pr.chave_b)
                  or fn_tokens_estruturais(pr.chave_b) <@ fn_tokens_estruturais(pr.chave_a))))
  order by pr.valor desc, pr.secao_canonica, pr.chave_a, pr.chave_b;
$$;

comment on function fn_pares_duplicados_do_caso(uuid, text) is
  'Pares de rótulos DIFERENTES, em DOCUMENTOS DIFERENTES, na mesma seção canônica, com valor idêntico nas mesmas colunas — candidatos a ser a MESMA conta transposta duas vezes (achado do v35: "Prejuízos acumulados" e "Resultados Acumulados", ambos -39.150). Dois rótulos no MESMO documento são a hierarquia DELE (0144), não duplicidade. Não decide nada: alimenta a checagem de reconciliação, que abre pendência para decisão humana. Critério estreito de propósito — falso positivo aqui gasta o tempo do analista. 0240: lê a versão por fn_versao_atual (a vigente, 0233), como as outras reconciliações.';

-- O comment de fn_versao_com_extracao (0233) citava fn_versao_atual como max(n_versao): deixou de ser verdade nesta migration.
comment on function fn_versao_com_extracao(uuid) is
  'A documento_versao VIGENTE para quem lê conteúdo: a de maior n_versao que TEM campo_extraido. Difere de fn_versao_mais_nova (max(n_versao)) de propósito: entre fn_registrar_documento e fn_registrar_campos_extraidos a versão mais recente está vazia, e max(n_versao) puro deixaria a tela de Modelagem em branco nessa janela — o mesmo sintoma que a 0101 corrigiu. 0233: uma versão cuja leitura esgotou a falha transitória (fn_versao_esgotou_transitoria) só é vigente quando nenhuma versão com linha do documento está sem a flag; entre as com a flag vence a de mais linhas (fn_versao_peso_de_leitura), empate pela de maior n_versao. Sem isto o reenvio por falha transitória (0233) trocava a versão anterior, com números no book, por uma leitura pior. 0240: fn_versao_atual agora devolve ESTA versão (a mais nova só quando nenhuma tem linha).';

-- ---------------------------------------------------------------------------
-- A SONDA. Marcadores em CÓDIGO, nunca de comentário (pg_get_functiondef traz os comentários do corpo: um marcador citado num comentário passaria sem a lógica).
-- ---------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('versao_mais_nova_funcao', '0240', 'funcao', 'fn_versao_mais_nova', null, null,
   'A versão de maior n_versao, com ou sem linha (o corpo antigo de fn_versao_atual). Ausente = a 0240 não foi aplicada: fn_versao_atual e fn_reconferir_caso (que a chamam) não existem em estado coerente.',
   'importante', 1086),
  ('versao_atual_segue_a_vigente', '0240', 'corpo', 'fn_versao_atual', 'fn_versao_com_extracao(p_documento_id)', null,
   'As reconciliações leem a versão VIGENTE (a mesma que a Modelagem e o export mostram), e a mais nova só quando nenhuma versão tem linha. Corpo sem isto = a v2 parcial (falha_transitoria_esgotada) é promovida nas reconciliações enquanto o book mostra a v1: o número conferido deixa de ser o número do book.',
   'importante', 1087),
  ('reconferir_guardas_na_versao_mais_nova', '0240', 'corpo', 'fn_reconferir_caso', 'fn_versao_mais_nova(v_doc.id)', null,
   'A reconferência avalia as guardas de extração na versão que o reenvio criou, mesmo vazia. Corpo sem isto = a v2 que voltou sem linha tem a pendência extracao_falhou fechada por "a versão tem linhas" (lida a v1), e a falha do reenvio some da fila com o book mostrando a v1.',
   'importante', 1088),
  ('duplicidade_le_a_versao_vigente', '0240', 'corpo', 'fn_pares_duplicados_do_caso', 'fn_versao_atual(d.id)', null,
   'A duplicidade de rótulo (fn_reconciliar_duplicidade) lê a MESMA versão que as outras reconciliações. Corpo sem isto = com a v1 com linhas e a v2 parcial (falha_transitoria_esgotada) o par duplicado abre ou fecha pela v2 enquanto as outras sete checagens e o book leem a v1.',
   'importante', 1092)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0240', revisado_em = current_date,
       observacao = 'A 0240 faz fn_versao_atual seguir a versão vigente (fn_versao_com_extracao, 0102/0233; a mais nova só quando nenhuma tem linha), cria fn_versao_mais_nova (o corpo antigo) reemite fn_reconferir_caso para as guardas de extração lerem a mais nova e fn_pares_duplicados_do_caso para a duplicidade ler a vigente. 4 requisitos novos (ordem 1086-1088 e 1092).'
 where id = true;

commit;
