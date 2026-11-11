-- =============================================================================
-- 0233 — A FALHA TRANSITÓRIA COM LINHA QUE O REENVIO NÃO RELIA (P8, lado do banco: o reenvio re-extrai quando o modelo esgotou a falha transitória e nenhum humano aceitou linha; e a versão vigente não troca uma leitura melhor por essa)
-- (Reemite 3 funções, fn_versao_extracao_concluida, fn_versao_com_extracao e fn_linhas_para_modelagem, com a MESMA assinatura, o MESMO retorno e a MESMA ACL; cria 2 funções auxiliares, fn_versao_esgotou_transitoria e
--  fn_versao_peso_de_leitura. fn_registrar_documento e fn_fila_de_reprocesso chamam fn_versao_extracao_concluida e NÃO são reemitidas. Acrescenta 4 requisitos à sonda. Sem tabela, sem gatilho, sem backfill.)
--
-- O DEFEITO. A 0230 deixou, como teto declarado ("sobe na P8"), a falha COM linha reaproveitada no reenvio: a versão tem linha, logo "concluída". Mas uma parte dessas falhas é do SERVIÇO e não do
-- documento (resposta sem conteúdo, limite de cadência do provedor): o bloco ficou sem leitura porque o modelo esgotou a falha transitória, e reenviar o mesmo arquivo com o mesmo prompt teria
-- boa chance de ler. Hoje o reenvio devolve a versão velha em silêncio e a falha fica aberta para sempre.
--
-- A INFORMAÇÃO NOVA. O n8n (fatia P8) passa a gravar no evento `extracao_sombra`, em `depois->'medicao'`, o booleano `falha_transitoria_esgotada` (true = algum bloco ficou sem leitura porque as 4
-- tentativas do modelo esgotaram a falha transitória; decisão do dono em 11/11/2026: NÃO há modelo de reserva no n8n); `versao_medicao` vira 'p4-2'. Campo ausente (n8n anterior) = comportamento de antes, intacto.
--
-- PARTIDA DO CORPO VIGENTE. Esta função é reemitida a partir do corpo da 0231 (a vigente; a 0230 foi estreitada por ela), não da 0230: a primeira versão desta migration partiu da 0230 e o teste da sonda
-- (instalacao.test.sql) acusou os 2 requisitos da 0231 ausentes. A parte (B) abaixo é a da 0231 sem mudar uma letra.
--
-- A REGRA NOVA. A versão NÃO está concluída (o reenvio re-extrai) quando TODAS valem:
--   1. o ÚLTIMO evento extracao_sombra da versão (criado_em desc, o mesmo critério da 0230; hoje em fn_versao_esgotou_transitoria, a conta única da flag) traz `medicao.falha_transitoria_esgotada` igual ao booleano `true` (string "true", número, nulo, ausente = não);
--   2. há `extracao_falhou` aberta no documento (estado <> 'resolvida', o predicado de sempre): sem falha aberta não há o que re-tentar;
--   3. NENHUMA linha da versão foi aceita por humano: `status_aceite <> 'pendente'` E `aceito_por` preenchido E `aceito_por not like 'sistema:%'`. O aceite do sistema (`sistema:auto_aceite`, 0019, confiança >= 95%)
--      NÃO protege: é a máquina aceitando a máquina. `com_ressalva` conta como humano (só pelo fn_aceitar/ressalva de uma pessoa).
-- Quando as 3 valem, a função devolve false mesmo com linha; fora disso o critério é o da 0231 intacto (tem linha OU declaração societária sem dado). A parte societária exige "sem falha aberta", então as duas
-- disjunções não se sobrepõem. Evento ilegível (medicao nula, campo não-booleano) = a regra nova é falsa: NÃO paga (o erro cai para o lado de reaproveitar, ao contrário da 0230: aqui pagar é o risco).
--
-- TETO CONHECIDO, DECLARADO: com aceite HUMANO em qualquer linha da versão o reenvio continua reaproveitando, porque re-extrair cria versão nova e tira da Modelagem a linha aceita (a revisão da 0230 mediu no banco
-- de teste: v1 aceita com valor 100 -> reenvio -> v2 pendente com valor 90). O custo é que essa falha transitória fica aberta até alguém resolvê-la ou o prompt mudar. Sobe quando o reenvio souber
-- reaproveitar as linhas aceitas na versão nova (outra fatia).
--
-- A FILA (0232) ACOMPANHA SOZINHA. `fn_fila_de_reprocesso` pergunta a mesma função: o documento com falha transitória esgotada e sem aceite humano passa de 'reaproveitaria' a `reprocessavel` (se há original no
-- bucket). Os chamadores de fn_versao_extracao_concluida (grep em Supabase/ N8N/ portal/src/): fn_registrar_documento (0230), fn_fila_de_reprocesso (0232) e N8N/build-workflow.mjs:188 (só texto/consulta);
-- a semântica muda para todos juntos, no ponto único. O n8n NÃO precisa ser republicado por esta migration (a coluna do retorno é a mesma; só passa a valer quando o n8n P8 gravar o campo).
--
-- MEDIDO EM PRODUÇÃO (somente leitura, 10/11/2026), ANTES:
--   * eventos extracao_sombra: 2.064, NENHUM com `medicao.falha_transitoria_esgotada` (maior versao_medicao = 'p4-1'). Logo a regra nova alcança 0 versões hoje: é esperado, o campo é novo. Depois do n8n P8 passa a valer.
--   * 535 documentos com extracao_falhou aberta; 77 têm linha na última versão (a medição da 0232 dizia 70: mais falhas abriram desde então); 4 desses 77 têm aceite humano em alguma linha
--     (285 linhas aceitas por humano no banco todo, 88.913 pelo sistema, 34.679 pendentes). Dos 77, 4 trazem no texto da falha um motivo transitório (`sem conteúdo`, cadência, 429, overload, timeout).
--   * DEPOIS (regra simulada em CTE, sem o campo): 0 versões mudam de resposta. Das 4 com texto transitório, o texto NÃO é o gatilho (a regra só olha o campo do n8n): elas continuam reaproveitadas até o reenvio por um n8n P8.
--
-- ---------------------------------------------------------------------------------------------------------------------------------------------
-- A VERSÃO VIGENTE NÃO TROCA UMA LEITURA MELHOR POR UMA QUE ESGOTOU A FALHA TRANSITÓRIA (revisão independente de 11/11/2026, ALTO 1)
-- ---------------------------------------------------------------------------------------------------------------------------------------------
-- O DEFEITO DA PRIMEIRA VERSÃO DESTA MIGRATION. Re-extrair pode TIRAR do book um número que estava lá: a v1 leu os blocos 1 e 2 (aceite do SISTEMA, que não protege) e o bloco 3 ficou sem leitura, com a flag; o reenvio
-- cria a v2; na v2 a falha transitória cai no bloco 1. `fn_versao_com_extracao` (a de maior n_versao que TEM linha) promove a v2, e as linhas do bloco 1 e 2 que só a v1 tinha SOMEM da Modelagem. A regra nova de
-- re-extrair troca, em silêncio, números lidos por números faltantes.
--
-- A CORREÇÃO, NO PONTO ÚNICO. A versão vigente passa a ser, entre as versões COM linha do documento: 1) a de maior n_versao SEM a flag `falha_transitoria_esgotada` no seu último extracao_sombra; 2) só se TODAS têm a
-- flag, a que trouxe MAIS linhas, empate pela de maior n_versao. O ponto 2 é um acréscimo desta migration à regra pedida na revisão ("só se todas tiverem a flag, a de maior número"): no arranjo da própria revisão a v1
-- TEM a flag (o bloco 3 ficou sem leitura) e a v2 também, e a de maior número promoveria justamente a v2 pior. O número de linhas é a medida de "quanto foi lido" que o banco tem hoje (a medição traz blocos_com_resposta,
-- mas é o mesmo nas duas leituras do arranjo). SHORTCUT declarado: linhas não são blocos nem conjunto contido (uma v2 com mais linhas pode ter perdido outras); sobe se a medição ganhar a lista de blocos lidos.
-- A conta mora em duas funções: fn_versao_esgotou_transitoria (a flag, a mesma de fn_versao_extracao_concluida) e fn_versao_peso_de_leitura (a chave de ordenação: 0 sem a flag; com a flag, menor quanto mais linhas).
-- fn_versao_com_extracao e a CTE `versao_vigente` de fn_linhas_para_modelagem ordenam por ela. A CTE NÃO chama fn_versao_com_extracao (a 0164 a trocou por um join porque o filtro por função opaca fazia o planner
-- estimar rows=1): o peso entra só no ORDER BY, que não muda a cardinalidade, e o join continua visível.
--
-- OS LEITORES DA VERSÃO VIGENTE (grep em Supabase/ N8N/ portal/src/, 11/11/2026) E SE CADA UM DEVE SEGUIR A MESMA REGRA:
--   * SEGUEM, sem ser reemitidos (chamam fn_versao_com_extracao): fn_autoridade_do_documento, fn_conflitos_do_caso, fn_diagnostico_modelagem, fn_documento_de_varias_empresas, fn_documento_serve_como,
--     fn_exigencias_do_caso, fn_golden_campos, fn_golden_candidatos, fn_golden_linhas_para_rotular, fn_golden_rotular_campos, fn_linhas_do_realizado, fn_linhas_do_tipo, fn_papel_do_rotulo_no_caso,
--     fn_perimetro_veredito, fn_saldo_mutuos_texto, fn_sazonalidade_do_caso, fn_sugerir_perguntas, fn_valores_por_ano; e o portal (documento-detalhe.tsx chama a RPC fn_versao_com_extracao). Todos leem CONTEÚDO
--     (campo_extraido) e devem mostrar a mesma versão que a Modelagem.
--   * SEGUE, reemitida aqui: fn_linhas_para_modelagem (a tela de Modelagem e o export de linhas), pela CTE versao_vigente.
--   * DEVERIA SEGUIR e NÃO foi alterada (decisão do dono, janela de re-extração): fn_versao_atual (max(n_versao), com ou sem linha), chamada por fn_reconciliar_arvore, fn_reconciliar_ativo_passivo_pl,
--     fn_reconciliar_caixa_bp_fluxo, fn_reconciliar_despfin_dre_vs_divida, fn_reconciliar_intragrupo, fn_reconciliar_mutuos, fn_reconciliar_receita_dre_vs_faturamento e fn_reconferir_caso. As reconciliações conferem
--     o número que o book mostra: com a v2 parcial promovida por max(n_versao) elas conferem a leitura pior enquanto a Modelagem mostra a v1. Trocar fn_versao_atual por coalesce(fn_versao_com_extracao(doc), max(n_versao))
--     muda também o que as reconciliações leem na janela entre registrar a v2 e gravar as linhas dela (hoje leem a v2 vazia): por isso não entra nesta fatia sem aviso.
--   * DEVERIA SEGUIR e NÃO foi alterada: fn_pares_duplicados_do_caso (0144; 145 linhas), que diz aplicar "só a versão vigente (0102)" mas usa max(n_versao) sem exigir linha: já divergia da 0102 na janela da re-extração.
--   * NÃO segue, por desenho: fn_fatos_do_caso (0149) — a versão que vale ali é a mais nova AVALIADA (fatos_avaliados_em), sem exigir linha, porque os documentos com mais fato (notas explicativas, parecer) extraem zero linha;
--     é outra tabela (documento_fato) e outro eixo. Se a v2 com a flag apaga fato, é outra medição. Idem fn_linha_de_base_extracao (mede o que RODOU, não o que o book lê), fn_documentos_nao_extraidos e fn_golden_estrato_sugerido
--     (pegam a versão mais nova por n_versao para o NOME do arquivo, não para o conteúdo).
--   * FORA DO BANCO (não toquei, Supabase/ só): `versoesVigentes` de portal/src/lib/export.ts tem a SUA regra ("a mais recente COM DADO manda", por n_versao) e continua promovendo a v2 parcial no Excel do book; é o mesmo
--     defeito em TypeScript e precisa da flag (ou do resultado de fn_versao_com_extracao por documento) para seguir esta migration. montar-base.ts, leitura-do-caso.ts e original-do-documento.ts também ordenam por n_versao.
-- MEDIDO em produção (somente leitura, 11/11/2026): 9 documentos de 1.465 com linha têm 2 versões com linha, e 0 eventos extracao_sombra com falha_transitoria_esgotada (o campo é novo): a regra nova muda a resposta
-- de 0 documentos hoje; vale a partir do n8n P8.
--
-- SEM BACKFILL: o critério é lido na hora.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/reextracao_transitoria.test.sql — 34 asserts (34 execuções), medidos em 11/11/2026 com o assert trocado por raise warning (`p8.medindo = on`), que CONTA; cada sabotagem
-- é a migration reemitida sobre o banco já montado pelo run.sh (cópia por template, teste rodado inteiro, aviso MEDIDO lido; cada substituição falha se o padrão não for achado exatamente uma vez, e o teste
-- reaplica a migration sabotada em lugar da 0233 intacta). Controle (migration intacta): 0 dos 34 reprovam. VERSÃO VIGENTE (os 11 asserts novos, 18g): fn_versao_com_extracao sem o peso: 3 (2 + 1 da sonda); só a
-- CTE da Modelagem sem o peso: 2 (1 + sonda); o peso sem o desempate por linhas (a flag vale 1 para todas): 2; o peso ignorando a flag (sempre 0): 3. O REENVIO (os 23 de antes, agora com a flag lida por
-- fn_versao_esgotou_transitoria): sem a condição do campo (a regra valendo para qualquer evento): 7 (6 de comportamento, 1 da sonda); sem a condição da falha aberta: 2; sem a do aceite humano: 5 (4 + 1 da sonda); com o
-- aceite do SISTEMA contando como humano: 2 (1 + 1 da sonda); função da 0231 de volta (regra nova ausente): 7 (6 + 1 da sonda). Os asserts de controle (campo ausente/falso/"true" em texto/medição nula, falha resolvida,
-- evento mais novo, e nenhuma versão com a flag = a regra da 0102) passam na função antiga de propósito: protegem o comportamento de antes.
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- A CONTA ÚNICA DA FLAG: o ÚLTIMO evento extracao_sombra da versão (criado_em desc) traz medicao.falha_transitoria_esgotada igual ao booleano true.
-- ---------------------------------------------------------------------------
create or replace function fn_versao_esgotou_transitoria(p_documento_versao_id uuid)
returns boolean
language sql
stable
as $$
  select coalesce((select u.depois->'medicao'->'falha_transitoria_esgotada' = 'true'::jsonb
                     from evento_auditoria u
                    where u.acao = 'extracao_sombra'
                      and u.entidade_ref = 'documento_versao:' || p_documento_versao_id::text
                    order by u.criado_em desc
                    limit 1), false)
$$;

comment on function fn_versao_esgotou_transitoria(uuid) is
  '0233: o ÚLTIMO evento extracao_sombra da versão marca medicao.falha_transitoria_esgotada = true (booleano; string, número, nulo ou ausente = não)? A conta única da flag: fn_versao_extracao_concluida (o reenvio) e fn_versao_peso_de_leitura (a versão vigente) a chamam. SECURITY INVOKER, somente leitura.';

-- O PESO DE LEITURA: a chave de ordenação (crescente) da versão vigente. 0 = leitura sem a flag; > 0 = leitura que esgotou a falha transitória, MENOR quanto mais linhas ela trouxe.
create or replace function fn_versao_peso_de_leitura(p_documento_versao_id uuid)
returns bigint
language sql
stable
as $$
  -- shortcut: "quanto foi lido" = nº de linhas (entre versões COM a flag; sem ela, a de maior número vence, como na 0102); sobe se a medição ganhar blocos lidos por versão. O teto 1e9 supera qualquer versão real (maior medida em produção: dezenas de milhares).
  select case when fn_versao_esgotou_transitoria(p_documento_versao_id)
              then 1000000000 - (select count(*) from campo_extraido ce where ce.documento_versao_id = p_documento_versao_id)
              else 0 end
$$;

comment on function fn_versao_peso_de_leitura(uuid) is
  '0233: chave de ordenação da versão vigente (crescente). 0 = a leitura NÃO esgotou a falha transitória (vale a de maior n_versao entre as de peso 0, a regra da 0102); acima de 0 = esgotou (fn_versao_esgotou_transitoria), e o peso cai com o número de linhas: entre leituras parciais vence a que trouxe mais linhas, empate pela de maior n_versao. Uma versão com a flag só é vigente quando nenhuma versão com linha do documento está sem ela. Existe para que re-extrair não TIRE do book o número que a versão anterior já tinha. SECURITY INVOKER, somente leitura.';

-- ---------------------------------------------------------------------------
-- fn_versao_extracao_concluida: o corpo da 0233 anterior, com a flag lida pela conta única (mesma assinatura, mesmo retorno, mesma ACL).
-- ---------------------------------------------------------------------------
create or replace function fn_versao_extracao_concluida(p_documento_versao_id uuid)
returns boolean
language sql
stable
as $$
  -- (1) tem linha (0118) E NÃO é falha transitória esgotada sem aceite humano (0233); (2) ou a declaração sem dado financeiro (0230, estreitada pela 0231: tipo sem dado por natureza OU decisão de pessoa). Parte ilegível = não vale como "re-extrair" (a 0233 reaproveita) e
  -- não vale como "declaração" (a 0230 paga): cada lado erra para o seu lado seguro.
  select (exists (select 1 from campo_extraido ce where ce.documento_versao_id = p_documento_versao_id)
          and not (
            fn_versao_esgotou_transitoria(p_documento_versao_id)
            -- falha aberta no documento: o predicado de sempre (estado <> resolvida)
            and exists (select 1
                          from documento_versao dv
                          join pendencia pe on pe.documento_id = dv.documento_id
                         where dv.id = p_documento_versao_id
                           and pe.tipo = 'extracao_falhou'
                           and pe.estado <> 'resolvida')
            -- aceite HUMANO em alguma linha da versão: re-extrair tiraria da Modelagem a linha aceita (teto declarado no cabeçalho)
            and not exists (select 1
                              from campo_extraido ce
                             where ce.documento_versao_id = p_documento_versao_id
                               and ce.status_aceite <> 'pendente'
                               and ce.aceito_por is not null
                               and ce.aceito_por not like 'sistema:%')))
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
            or fn_pessoa_decidiu_sem_dado((select dv.documento_id from documento_versao dv where dv.id = p_documento_versao_id)))
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
  '0233 (sobre a 0231): a versão já foi extraída (vale reaproveitar no reenvio)? Verdadeira quando (A) a versão TEM linha em campo_extraido (o critério da 0118) E NÃO se dá o caso de falha transitória esgotada: o ÚLTIMO evento extracao_sombra traz medicao.falha_transitoria_esgotada = true (fn_versao_esgotou_transitoria; booleano; o n8n P8 grava), há extracao_falhou aberta no documento (estado <> resolvida) e nenhuma linha da versão foi aceita por humano (status_aceite <> pendente, aceito_por preenchido e fora de sistema:%); OU (B) o corpo da 0231 INTACTO: o último evento extracao_sombra existe, sem falha_motivo, com tem_dado_financeiro = false explícito, e (tipo sem dado por natureza, fn_tipo_sem_dado_por_natureza, sem conta contada, OU uma pessoa resolveu a falha, fn_pessoa_decidiu_sem_dado), e sem extracao_falhou aberta (0230/0231). Com aceite humano o reenvio continua reaproveitando mesmo com falha transitória (teto: re-extrair tira da Modelagem a linha aceita). Campo ausente/ilegível = reaproveita como antes. A pergunta de fn_registrar_documento e de fn_fila_de_reprocesso: uma implementação só. SECURITY INVOKER, somente leitura.';

-- ---------------------------------------------------------------------------
-- fn_versao_com_extracao (0102): a versão VIGENTE de quem lê conteúdo. 0233: a de menor peso de leitura, depois a de maior n_versao.
-- ---------------------------------------------------------------------------
create or replace function fn_versao_com_extracao(p_documento_id uuid)
returns uuid
language sql
stable
as $$
  -- marca-0102
  -- 0233: sem a flag de falha transitória esgotada primeiro (peso 0), a de maior n_versao; se TODAS as versões com linha a têm, a que trouxe mais linhas.
  select dv.id
  from documento_versao dv
  where dv.documento_id = p_documento_id
    and exists (select 1 from campo_extraido ce where ce.documento_versao_id = dv.id)
  order by fn_versao_peso_de_leitura(dv.id), dv.n_versao desc
  limit 1;
$$;

comment on function fn_versao_com_extracao(uuid) is
  'A documento_versao VIGENTE para quem lê conteúdo: a de maior n_versao que TEM campo_extraido. Difere de fn_versao_atual (max(n_versao)) de propósito: entre fn_registrar_documento e fn_registrar_campos_extraidos a versão mais recente está vazia, e max(n_versao) puro deixaria a tela de Modelagem em branco nessa janela — o mesmo sintoma que a 0101 corrigiu. 0233: uma versão cuja leitura esgotou a falha transitória (fn_versao_esgotou_transitoria) só é vigente quando nenhuma versão com linha do documento está sem a flag; entre as com a flag vence a de mais linhas (fn_versao_peso_de_leitura), empate pela de maior n_versao. Sem isto o reenvio por falha transitória (0233) trocava a versão anterior, com números no book, por uma leitura pior.';

-- ---------------------------------------------------------------------------
-- fn_linhas_para_modelagem — REEMITIDA INTEIRA a partir da 0164 (a vigente; conferido idêntica ao corpo de schema.sql antes desta migration). Única mudança: o ORDER BY da CTE versao_vigente
-- passa a ser o de fn_versao_com_extracao (peso de leitura, depois n_versao). Mesma assinatura, mesmo retorno, mesma ACL.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_linhas_para_modelagem(p_caso_id uuid) RETURNS TABLE(secao_canonica text, chave text, rotulo_norm text, entidade text, valor_ultimo numeric, n_ocorrencias bigint, papel text, unidade text, moeda text, documentos text[], sobreposicao_suspeita boolean)
    LANGUAGE sql STABLE
    AS $$
  -- marca-0102
  -- marca-0103
  -- marca-0164
  -- marca-0233
  --
  -- AS MARCAS FICAM. `fn_diagnostico_modelagem` (0102) confere se a
  -- correção daquela migration está instalada procurando `marca-0102` no
  -- corpo — é o teste que separa "mergeado" de "aplicado". Trocar a marca
  -- apagaria a resposta; a 0164 reemite o corpo e MANTÉM a regra da 0102
  -- ("só a versão vigente"), só muda COMO ela é expressa (join, não filtro
  -- opaco) — então as marcas continuam verdadeiras.
  with docs_do_caso as (
    select d.id as documento_id, d.tipo_taxonomia, d.entidade_id
    from documento d
    where d.caso_id = p_caso_id
  ),
  -- 0164: A VERSÃO VIGENTE COMO JOIN, NÃO COMO FILTRO OPACO.
  --
  -- Mesma regra da 0102 ("a de maior n_versao que TEM campo_extraido"), mas
  -- como uma CTE nomeada que o planner enxerga e estima — em vez de um
  -- filtro `dv.id = fn_versao_com_extracao(d.id)` por linha, cuja
  -- seletividade o Postgres não sabe estimar (função opaca) e por isso
  -- chutava rows=1 para toda CTE construída em cima de `bruto`, mesmo a
  -- 7.220 linhas reais — a causa medida do Nested Loop que estourava os 8s
  -- do Supabase no caso "Teste 00" (190 documentos). Ver o cabeçalho.
  versao_vigente as (
    select distinct on (dv.documento_id)
           dv.documento_id, dv.id as documento_versao_id
    from documento_versao dv
    join docs_do_caso dc on dc.documento_id = dv.documento_id
    where exists (select 1 from campo_extraido ce where ce.documento_versao_id = dv.id)
    -- 0233: a leitura que esgotou a falha transitória só vence quando NENHUMA versão sem a flag tem linha (e, entre elas, a de mais linhas).
    -- O peso entra no ORDER BY, nunca em filtro: o join continua visível ao planner (0164). A mesma ordem de fn_versao_com_extracao.
    order by dv.documento_id, fn_versao_peso_de_leitura(dv.id), dv.n_versao desc
  ),
  bruto as (
    select
      ce.secao_canonica,
      ce.chave,
      fn_normalizar_texto(ce.chave) as rotulo_norm,
      coalesce(ce.entidade_coluna, e.razao_social) as entidade,
      ce.valor_num,
      ce.unidade,
      ce.moeda,
      dc.tipo_taxonomia
    from versao_vigente vv
    join docs_do_caso dc on dc.documento_id = vv.documento_id
    join campo_extraido ce on ce.documento_versao_id = vv.documento_versao_id
    left join entidade e on e.id = dc.entidade_id
    where ce.valor_num is not null
  ),
  -- O PAPEL É PROPRIEDADE DO RÓTULO, NÃO DA OCORRÊNCIA (0101).
  --
  -- `fn_papel_linha` depende só de (chave, tipo do documento, unidade) e custa
  -- ~1,6 ms por chamada. Avaliá-la por ocorrência era pagar 760 vezes por uma
  -- resposta que tem ~250 valores distintos. Aqui ela roda uma vez por combinação
  -- distinta e o resultado volta por join — é a mesma resposta, porque a função é
  -- `immutable`.
  papel_do_rotulo as (
    select distinct chave, tipo_taxonomia, unidade,
           fn_papel_linha(chave, tipo_taxonomia, unidade) as papel
    from (select distinct chave, tipo_taxonomia, unidade from bruto) d
  ),
  ocorrencia as (
    select b.*, p.papel
    from bruto b
    join papel_do_rotulo p
      on p.chave = b.chave
     and p.tipo_taxonomia is not distinct from b.tipo_taxonomia
     and p.unidade is not distinct from b.unidade
  ),
  base as (
    select
      o.secao_canonica,
      (array_agg(o.chave order by length(o.chave)))[1] as chave,
      o.rotulo_norm,
      max(o.entidade) as entidade,
      -- valor da ocorrência de MAIOR MÓDULO, COM O SINAL (0042). 0164: em
      -- empate de módulo (duas ocorrências, sinais opostos), o desempate
      -- passa a ser DECLARADO (prefere o positivo) em vez de depender da
      -- ordem física em que o plano entrega as linhas — ver o cabeçalho
      -- desta migration para a divergência que expôs a ambiguidade latente.
      (array_agg(o.valor_num order by abs(o.valor_num) desc nulls last, o.valor_num desc))[1] as valor_ultimo,
      count(*) as n_ocorrencias,
      max(o.unidade) as unidade,
      max(o.moeda) as moeda,
      array_agg(distinct o.tipo_taxonomia) as documentos,
      -- papel da ocorrência de MAIOR PRIORIDADE (fn_papel_prioridade): no empate
      -- entre documentos, o lado seguro é não projetar.
      (array_agg(o.papel order by fn_papel_prioridade(o.papel)))[1] as papel
    from ocorrencia o
    group by o.secao_canonica, o.rotulo_norm
  ),
  -- SOBREPOSIÇÃO SUSPEITA, por join (0101). Mesma regra da 0042: outra linha da
  -- MESMA seção, MESMO valor, e um rótulo descrevendo o outro de forma mais
  -- grossa (`Provisões` × `Provisão para passivo a descoberto de controlada`).
  -- A função não escolhe por ninguém: MARCA, e quem decide é o analista.
  -- 0103: os radicais viram coluna calculada UMA vez por linha lógica, e a
  -- contenção vira o operador `<@`. Antes `fn_rotulo_contido` era avaliada por
  -- PAR de linhas e re-tokenizava OS DOIS rótulos a cada par — com muitas
  -- colisões de valor, milhares de tokenizações dos mesmos poucos rótulos.
  base_r as (
    select b.*,
           fn_radicais_rotulo(b.chave) as radicais,
           fn_tem_palavra_longa(b.chave) as tem_longa
    from base b
  ),
  pares as (
    select b.secao_canonica, b.rotulo_norm as r1, o.rotulo_norm as r2
    from base_r b
    join base_r o
      on coalesce(o.secao_canonica, '') = coalesce(b.secao_canonica, '')
     and o.valor_ultimo = b.valor_ultimo
     -- cada par NÃO ORDENADO uma vez só (antes: duas, uma em cada direção)
     and b.rotulo_norm < o.rotulo_norm
    where b.papel = 'conta' and o.papel = 'conta'
      and ((b.tem_longa and b.radicais <@ o.radicais)
        or (o.tem_longa and o.radicais <@ b.radicais))
  ),
  sobrepostas as (
    select secao_canonica, r1 as rotulo_norm from pares
    union
    select secao_canonica, r2 from pares
  )
  select b.secao_canonica, b.chave, b.rotulo_norm, b.entidade, b.valor_ultimo,
         b.n_ocorrencias, b.papel, b.unidade, b.moeda, b.documentos,
         (s.rotulo_norm is not null) as sobreposicao_suspeita
  from base_r b
  left join sobrepostas s
    on s.rotulo_norm = b.rotulo_norm
   and coalesce(s.secao_canonica, '') = coalesce(b.secao_canonica, '')
  order by b.secao_canonica nulls last, b.rotulo_norm;
$$;
COMMENT ON FUNCTION public.fn_linhas_para_modelagem(p_caso_id uuid) IS 'Linhas lógicas do caso para a tela de Modelagem, com PAPEL (conta/subtotal/derivado/serie_mensal), valor COM SINAL, unidade/moeda, documentos de origem e marca de sobreposição. Existe como função porque campo_extraido não tem caso_id — o escopo por caso mora aqui. 0101: papel calculado uma vez por rótulo e sobreposição por join, para caber no statement_timeout. 0102: só a versão VIGENTE de cada documento (reextração deixava a versão superada somando ocorrência e podendo ditar o valor_ultimo). 0164: a versão vigente passa a ser um JOIN nomeado (CTE versao_vigente), não um filtro por função opaca — o filtro antigo (dv.id = fn_versao_com_extracao(d.id)) fazia o planner estimar rows=1 para dezenas de milhares de linhas reais, escolhendo Nested Loop onde deveria escolher Hash Join (medido: 15,0s → 2,6s num fixture de 190 documentos/800 rótulos). Resultado idêntico ao anterior — comparado linha a linha, com except nos dois sentidos, contra 78 casos. 0233: a CTE versao_vigente ordena por fn_versao_peso_de_leitura antes de n_versao (a leitura que esgotou a falha transitória só é vigente sem versão melhor), a mesma ordem de fn_versao_com_extracao.';

revoke all on function fn_versao_esgotou_transitoria(uuid) from public;
grant execute on function fn_versao_esgotou_transitoria(uuid) to authenticated, service_role;
revoke all on function fn_versao_peso_de_leitura(uuid) from public;
grant execute on function fn_versao_peso_de_leitura(uuid) to authenticated, service_role;
revoke all on function fn_versao_extracao_concluida(uuid) from public;
grant execute on function fn_versao_extracao_concluida(uuid) to authenticated, service_role;
revoke all on function fn_versao_com_extracao(uuid) from public;
grant execute on function fn_versao_com_extracao(uuid) to authenticated, service_role;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    execute 'grant execute on function fn_versao_esgotou_transitoria(uuid) to supabase_read_only_user';
    execute 'grant execute on function fn_versao_peso_de_leitura(uuid) to supabase_read_only_user';
    execute 'grant execute on function fn_versao_extracao_concluida(uuid) to supabase_read_only_user';
    execute 'grant execute on function fn_versao_com_extracao(uuid) to supabase_read_only_user';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- A SONDA. Marcadores em CÓDIGO, nunca de comentário (pg_get_functiondef traz os comentários do corpo: um marcador citado num comentário passaria sem a lógica).
-- ---------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('reenvio_rele_falha_transitoria_esgotada', '0233', 'corpo', 'fn_versao_extracao_concluida', 'fn_versao_esgotou_transitoria(p_documento_versao_id)', null,
   'A versão com linha e com o último evento marcando falha_transitoria_esgotada = true (lido por fn_versao_esgotou_transitoria), falha aberta e sem aceite humano NÃO é concluída. Corpo sem isto = a falha transitória com linha nunca ganha nova chance no reenvio (teto da 0230), e a fila a mostra como reaproveitaria.',
   'importante', 1074),
  ('reenvio_respeita_aceite_humano', '0233', 'corpo', 'fn_versao_extracao_concluida', 'aceito_por not like ''sistema:%''', null,
   'O aceite HUMANO de uma linha da versão segura o reaproveitamento (re-extrair tira da Modelagem a linha aceita: v1 aceita 100 -> v2 pendente 90). Corpo sem isto = o reenvio por falha transitória apaga o aceite do analista; com o aceite do sistema (auto_aceite) a proteção não vale.',
   'importante', 1075),
  ('versao_vigente_nao_troca_por_leitura_pior', '0233', 'corpo', 'fn_versao_com_extracao', 'fn_versao_peso_de_leitura(dv.id)', null,
   'A versão vigente prefere a leitura SEM a flag de falha transitória esgotada; só se todas a têm, a de mais linhas. Corpo sem isto = o reenvio por falha transitória (0233) promove a v2 parcial e TIRA do book o número que a v1 já tinha (as linhas do bloco que a v2 não leu).',
   'importante', 1082),
  ('modelagem_vigente_nao_troca_por_leitura_pior', '0233', 'corpo', 'fn_linhas_para_modelagem', 'fn_versao_peso_de_leitura(dv.id)', null,
   'A CTE versao_vigente da Modelagem (0164, um join e não a função, por planejamento) usa a MESMA ordem de fn_versao_com_extracao. Corpo sem isto = a tela e o export mostram a v2 parcial enquanto os outros leitores (fn_versao_com_extracao) mostram a v1: duas contas da mesma coisa.',
   'importante', 1083)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0233', revisado_em = current_date,
       observacao = 'A 0233 reemite fn_versao_extracao_concluida (falha transitória esgotada, campo do n8n P8 em medicao, com linha, falha aberta e sem aceite humano deixa de ser reaproveitada no reenvio), fn_versao_com_extracao e fn_linhas_para_modelagem (a versão vigente não troca uma leitura melhor por uma leitura que esgotou a falha transitória) e cria fn_versao_esgotou_transitoria e fn_versao_peso_de_leitura; 4 requisitos novos.'
 where id = true;

commit;
