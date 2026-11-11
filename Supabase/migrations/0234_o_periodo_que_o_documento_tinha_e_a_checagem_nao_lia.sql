-- =============================================================================
-- 0234 — O PERÍODO QUE O DOCUMENTO TINHA E A CHECAGEM NÃO LIA (P9: "sem período par" em balanço de "Saldo Final", e "período incorreto" falso em comparativo)
-- (Reemite 2 funções com a MESMA assinatura, o MESMO retorno e a MESMA ACL: fn_coluna_periodo_do_ano (0023) e fn_periodos_equivalentes (0022). Cria 1 função, fn_resolver_periodo_incorreto_falso.
--  Backfill: resolve a pendência periodo_incorreto falsa (sistema:0234) e recalcula, pela função que o repositório já usa (fn_reconciliar_caso + fn_recomputar_completude), os mandatos com "sem período par" aberto.
--  Acrescenta 8 requisitos à sonda. Sem tabela, sem gatilho.)
--
-- FORA DE ESCOPO (declarado): entidade_incorreta por LEITURA errada da IA ("ARAUGÁRIA" x "ARAUCÁRIA", "OMNIBEAUTY ... DE CONSOLIDADO"): a causa é a leitura (fatia P13); e o nome de entidade tirado
-- do arquivo "Metodo Indireto" (classificador do n8n, outra fatia). Medido em PRODUÇÃO (10/11/2026, somente leitura), pendências ABERTAS: entidade_incorreta 80, periodo_incorreto 57,
-- precondicao_nao_satisfeita 347 (8 com "sem período par"). Esta migration trata os 57 (parte B) e os 8 (parte A, 6 deles alcançados).
--
-- ---------------------------------------------------------------------------------------------------------------------------------------------
-- (A) "SEM PERÍODO PAR" EM DOCUMENTO CUJAS COLUNAS SÃO "SALDO FINAL"/"SALDO INICIAL"
-- ---------------------------------------------------------------------------------------------------------------------------------------------
-- O DEFEITO. Caso "Fw Valtra" (MOTO AGRICOLA VOLKWEIS LTDA): BALANÇO anual 2023, 2024 e 2025, um documento por ano, com colunas "Saldo Final"/"Saldo Inicial"; DRE com "Saldo atual"/"Saldo anterior". Nenhuma
-- traz ano no texto. As reconciliações (`fn_reconciliar_*`, 0188) perguntam `fn_coluna_periodo_do_ano(versão, ano)`, que só acha coluna cujo TEXTO tem o ano, devolve o sentinela E'\x01' ("o documento tem coluna
-- de período e nenhuma é deste ano") e a checagem acusa "O Balanço foi encontrado, mas nenhum exercício teve os DOIS lados. 2024: falta o Ativo Total E o Passivo+PL" — com o Ativo e o Passivo+PL na tela de extração.
-- A 0201 já tinha ensinado a regra ao Realizado (fechamento "Saldo Final/Atual" = ano da referência do documento; abertura "Saldo Inicial/Anterior" = ano - 1, por fn_coluna_e_saldo e fn_coluna_e_abertura), e
-- `fn_valores_por_ano` e `fn_linhas_do_realizado` descreviam o MESMO documento de um jeito e as reconciliações de outro (a 0201 já avisara: "duas implementações da mesma conta").
--
-- A CORREÇÃO, NO PONTO ÚNICO (escada, degrau 2). Chamadores de fn_coluna_periodo_do_ano (grep em Supabase/ N8N/ portal/src/): N8N e portal não a chamam. No banco: as reconciliações fn_reconciliar_ativo_passivo_pl,
-- fn_reconciliar_caixa_bp_fluxo (2x), fn_reconciliar_receita_dre_vs_faturamento, fn_reconciliar_despfin_dre_vs_divida e fn_reconciliar_mutuos chamam direto; fn_linha_vale_para_ano (0195) chama e é chamada por
-- intragrupo, mútuos, caixa e despesa financeira. Todos passam a ver a mesma resposta, por esta função só. Regra nova, DEPOIS do casamento por texto (que vem primeiro e não muda): sem coluna com o ano no
-- texto, se a REFERÊNCIA do período do documento ancora UM ÚNICO ano (fn_anos_periodo), então
--   * ano = esse ano: a coluna que NOMEIA um saldo e não é de abertura (fn_coluna_e_saldo e não fn_coluna_e_abertura: "Saldo Final", "Saldo atual");
--   * ano = esse ano - 1: a de ABERTURA ("Saldo Inicial", "Saldo anterior"), só em demonstração PATRIMONIAL (BALANCO/BALANCETE) ou em documento SEM coluna de movimento (Débito/Crédito) — ver a revisão abaixo;
--   * qualquer outro ano: sentinela, como antes.
-- E NENHUM DOS DOIS vale em documento de período PARCIAL (fn_periodo_e_parcial, a conta única da 0201): o "Saldo Inicial" de um balancete de junho é o saldo do início do período, não o fechamento de dezembro
-- anterior, e o "Saldo atual" de um semestre é o acumulado de 6 meses, não o ano. O documento parcial segue no sentinela, como antes da 0234.
--
-- A REVISÃO INDEPENDENTE (11/11/2026) E O QUE ELA MEDIU.
--   * MÉDIO 1 (parcial no fechamento): a primeira versão desta migration exigia documento não parcial só na ABERTURA. Uma DRE/balancete "data-base 01/01/2026 - 30/06/2026" com "Saldo atual" passava a valer como o
--     ano cheio de 2026 e era comparada a faturamento de mais meses: divergência falsa de ~25%. Agora o parcial fica no sentinela nas duas direções. Efeito no Realizado de produção (10/11/2026): o semestre do Fw Valtra
--     volta a "sem período par" (como estava), e das 8 pendências "sem período par" a regra alcança 4 (as 4 anuais do Valtra), não 6: a de data-base 01/01/2026 - 30/06/2026 e a do S105 (documento parcial) saem.
--   * MÉDIO 2 (razão): "Saldo anterior" = ano - 1 serve ao balanço e à DRE comparativa, mas a DRE no formato de razão (Saldo anterior / Débito / Crédito / Saldo atual) tem o Saldo anterior das contas de resultado
--     igual a 0 (zeradas no fechamento): ler como ano - 1 daria receita do ano anterior = 0, ausência apresentada como dado (regra 1). MEDIDO no Fw Valtra (MOTO AGRICOLA VOLKWEIS LTDA), DRE anual 2023/2024/2025: as
--     DREs trazem SÓ "Saldo anterior" e "Saldo atual" (sem Débito/Crédito); das 114 linhas de chave única nas duas, o "Saldo anterior" da DRE 2025 BATE com o "Saldo atual" da DRE 2024 em 113 (RECEITA LÍQUIDA
--     41.860.490,85 nas duas), e é 0 em 6. Ou seja, ali o "Saldo anterior" é de fato o ano - 1 (formato comparativo): a regra do ano - 1 fica para DRE sem movimento. A abertura passa a exigir documento patrimonial OU sem
--     coluna de movimento (a regra do relatório). Em produção NENHUMA DRE tem Débito/Crédito (documentos com essas colunas: BALANCETE 67, RAZAO 27, COMBINADO 3, EXTRATO_BANCARIO 1, 10/11/2026): o risco é do formato, não
--     de um documento de hoje. A 0201 faz a mesma leitura no Realizado (abertura = ano - 1 sem olhar o movimento) e NÃO foi alterada aqui: nos documentos de produção com Débito/Crédito (todos de período parcial) as
--     linhas de resultado com "Saldo anterior" são 1.027, 886 delas (86%) iguais a 0 (BALANCETE 828, 687 zero; COMBINADO 199, 199 zero). Se isso chega ao Realizado depende de o ano não ter DRE anual (o parcial só entra
--     sem anual da mesma família, 0200): NÃO medido ponta a ponta. Fica como achado para a 0201, sem corrigir sem aviso do dono.
-- Débito/Crédito nunca é saldo (fn_coluna_e_saldo não os reconhece, 0199/0201); "Saldo", "Valor" e "Ticket médio" não nomeiam saldo e continuam sem exercício (decisão da 0150/0201). Várias colunas elegíveis: a de
-- mais linhas, depois a ordem alfabética (o mesmo desempate do casamento por texto).
-- TETO CONHECIDO: referência multi-ano ("24,25") com colunas sem ano continua no sentinela — "Saldo Final" de um documento de dois anos não diz de qual. A 0201 usa o primeiro ano do texto (fn_ano_da_coluna) e, para
-- "24,25", o último: duas leituras para a mesma coisa; aqui, na dúvida, não afirma. Sobe se aparecer um documento real assim. BALANCETE SEMESTRAL (0200): o parcial não entra por cima do anual na SÉRIE (outra função, intacta);
-- aqui a pergunta é de UM documento já escolhido pelo chamador, e o parcial NÃO herda o ano (revisão, médio 1): antes de a revisão medir, o fechamento dele valia o ano da referência.
--
-- A PENDÊNCIA COM "2024" E PERÍODO "data-base 01/01/2026 - 30/06/2026" É OUTRO DEFEITO (investigado, NÃO corrigido aqui). fn_anos_periodo('data-base', '01/01/2026 - 30/06/2026') devolve {2026}, não 2024.
-- O "2024" vem de fn_registrar_reconciliacao: ela reaproveita a pendência aberta por COMPATIBILIDADE de período (fn_periodos_compativeis, interseção de anos) e reescreve a descrição com a da última checagem; o período
-- "24,26" do Faturamento (01.2024 a 08.2026) é compatível com {2026} e a descrição dele ("2024: ...; 2026: ...") sobrescreve a da data-base. O texto diz dois anos, o período da pendência diz um. Fica como achado
-- para outra fatia (pendência única por interseção de períodos). Esta migration não mexe em fn_registrar_reconciliacao.
--
-- MEDIDO EM PRODUÇÃO (somente leitura, 10/11/2026), ANTES: 8 pendências abertas "sem período par" em 3 mandatos (Fw Valtra 5, P4 linha de base Canastra (sintético) 2, S105 teste fatia 2 (sintético) 1). O critério da regra nova
-- (documento do mandato, compatível com o período da pendência, versão vigente com linha, ao menos uma coluna que nomeia saldo, nenhuma com ano no texto, referência de um ano só) é satisfeito por documento em 6 das 8 (Valtra 5,
-- S105 1; os 2 do Canastra sintético não têm documento assim: a causa deles é outra e não é tocada); com a exigência de documento NÃO parcial (revisão, médio 1) são 4 das 8 (as 4 anuais do Valtra: anual 2023, 2024 x2
-- e 2025; saem a data-base 01/01/2026 - 30/06/2026 do Valtra e a do S105, ambas de documento parcial). É condição NECESSÁRIA, não suficiente: a reconciliação ainda precisa achar os rótulos. DEPOIS: medido só pelo teste (a
-- função não pode ser criada em produção por quem mede) e, aplicada a migration, pelo recálculo do backfill abaixo e pela sonda.
--
-- ---------------------------------------------------------------------------------------------------------------------------------------------
-- (B) "PERÍODO INCORRETO" FALSO NO DIAGNÓSTICO DE CONTEÚDO
-- ---------------------------------------------------------------------------------------------------------------------------------------------
-- O DEFEITO. fn_registrar_diagnostico abre `periodo_incorreto` quando `fn_periodos_equivalentes` (0022) diz que o período sugerido pela IA e o registrado são conjuntos de anos DIFERENTES. O documento COMPARATIVO
-- ("..._2025x2024.pdf") é registrado "multi 24,25" e a IA, lendo a página do exercício corrente, diz "anual 12M25" ou "data-base 2025-12-31": {2025} x {2024,2025} — pendência falsa que o analista tem de fechar à mão.
-- Medido em produção: 57 abertas; 35 delas são deste tipo pela primeira versão da regra; com a exclusão do parcial (revisão, alto) 32 (3 têm um lado parcial, ver abaixo). Por mandato: Araucária teste 4, Araucária teste 1 7, teste alto volume - grupo araucária 7, teste Canastra 2,
-- teste - Canastra 3, Teste comparativo - Grupo Canastra 2, AMO teste 00 2, P4 linha de base - Distress 2, Vertentes 2, Canastra 1, teste 143 1, teste ponta a ponta 1, Fw Valtra 1 (por mandato, da primeira versão da regra: os 3 do parcial estão entre eles). Outras 6 (teste v20 e v22, 3 cada) são
-- pendência velha cujo par JÁ É equivalente pela regra antiga (data-base 15/01/2025 x data-base 2025-01-15; anual 12M25 x anual 2025; "Jan/2024 a Dez/2025" x "L24M", sem ano ancorado): ficaram abertas porque o diagnóstico
-- não foi regravado depois da 0022; o backfill as resolve também, porque a função diz que não há divergência.
--
-- A REGRA NOVA (a proposta da fatia). Equivalentes quando o ANO MAIS RECENTE é o mesmo, um conjunto CONTÉM o outro e a união é uma SEQUÊNCIA DE ANOS CONTÍGUA. Isso cobre "multi 24,25" x "anual 12M25" / "data-base
-- 2025-12-31" / "anual 23,24,25". SÓ ENTRE PERÍODOS NÃO PARCIAIS (revisão, alto): a primeira versão não excluía o parcial e fazia "data-base 2025-06-30" (balanço intermediário) x "multi 24,25" equivalentes; o saldo de junho
-- entraria no Realizado como se fosse o fechamento. Com um lado parcial (fn_periodo_e_parcial(null, null, tipo, referência) verdadeiro: data-base que não fecha o ano, intervalo, mês, trimestre, balancete) a contenção NÃO vale.
-- MEDIDO em produção (somente leitura, 11/11/2026), das ~35 pendências que o backfill fecharia pela contenção: 3 têm um lado parcial (as 3 são "multi 01/07/2025 a 30/06/2026" registrado contra "anual 12M26",
-- "outro 12M26" e "data-base 2026-06-30"; 12M26 é o ano de 2026 e o registrado é jul/2025 a jun/2026: exercícios diferentes) e deixam de ser fechadas: o backfill fecha 32 pela regra nova (mais as 6 que já eram equivalentes pela
-- regra antiga: 38 no total, não 41). O que CONTINUA abrindo (controles, e as 19 de produção que não fecham: as 16 verdadeiras e essas 3): "anual 21,25" x "multi 23,24,25" (documento de 2021 registrado errado: um não contém o outro); "anual 25,26" x "multi 24,25" (ano mais recente diferente); "anual 23,24" x "anual 2023" (idem);
-- "multi 2024,2025" x "multi 01,24,25" (o 01 veio do prefixo do arquivo, vira 2001: a união não é contígua); "anual 2025" x "multi 02,25" e "multi 03,25" (idem). "data-base 15/01/2025" x "data-base 2025-01-15" já era
-- equivalente (a forma canônica é a mesma, 2025-01-15); o teste o trava. As regras antigas (forma canônica igual, período sem ano ancorado = não verificável, conjuntos iguais) ficam como estavam.
-- LIMITE CONHECIDO: "multi 32M26" x "multi 24,26" é o mesmo período (janela de 32 meses terminando em 2026 = jan/2024 a ago/2026), mas {2026} x {2024,2026} não é contíguo e segue aberto (1 em produção): precisa de
-- janela móvel em anos, outra conta. Anos iguais não distinguem semestre de ano ("data-base 2025-06-30" x "anual 2025" já eram equivalentes na 0022): granularidade abaixo do ano não é verificada, como antes.
-- Chamador único: fn_registrar_diagnostico (13477 do schema.sql). N8N e portal não chamam.
--
-- O BACKFILL (B). fn_resolver_periodo_incorreto_falso(p_caso_id default null) resolve a pendência `periodo_incorreto` em estado 'aberta' (só ela: em_correcao_interna, reenviada_ao_cliente, aceita_com_ressalva e rejeitada
-- são decisão de gente e ficam), de origem 'diagnostico' (o sistema), cujo par (sugerido x registrado, lido da própria descrição, que é o que o analista vê) a função declara equivalente. resolvida_por = 'sistema:0234';
-- uma linha de auditoria com a contagem e os mandatos. Idempotente. A migration a chama uma vez (todos os mandatos).
-- O backfill (A) recalcula, por fn_reconciliar_caso e fn_recomputar_completude (o que as 0203/0204 mandam rodar à mão), os mandatos com `precondicao_nao_satisfeita` aberta com "sem período par": em produção 3. A
-- pendência que passa a conferir se resolve pela própria reconciliação (fn_registrar_reconciliacao), não por update direto desta migration.
-- (revisão, baixo) fn_reconciliar_caso resolve pendência de reconciliação em qualquer estado diferente de resolvida (0192), inclusive em_correcao_interna e aceita_com_ressalva (decisão de gente). MEDIDO em produção
-- (somente leitura, 11/11/2026), nos 3 mandatos que o backfill reconcilia: pendências de origem reconciliacao em estado em_correcao_interna ou aceita_com_ressalva = 0 (Fw Valtra 12 abertas; Canastra sintético 6 abertas e
-- 6 resolvidas; S105 1 aberta). Logo NÃO há o que restringir hoje e a 0192 não é tocada. Se esse número deixar de ser 0 antes de a migration ser aplicada, rode a consulta de novo e restrinja o laço: a fn_reconciliar_caso
-- do mandato com decisão humana é o que desfaria a decisão.
--
-- A ASSINATURA E O RETORNO DAS DUAS FUNÇÕES NÃO MUDAM. Reaplicável: create or replace + upsert dos requisitos.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/o_periodo_que_a_checagem_nao_lia.test.sql — 50 execuções (34 chamadas de assert no arquivo; os 16 a mais vêm dos laços B1 e B2, 18 execuções em 2 chamadas), medidas em
-- 11/11/2026 com o assert trocado por raise warning (`p9.medindo = on`), que CONTA; cada sabotagem é a migration reemitida sobre o banco já montado pelo run.sh (cópia por template), com o teste rodado inteiro e o aviso
-- MEDIDO lido. Controle (migration intacta): 0 dos 50 reprovam. Funções ANTIGAS de volta (0023 e 0022): 18 reprovam (17 de comportamento, 1 da sonda); só fn_coluna_periodo_do_ano antiga: 11 (10 + 1 da sonda); só
-- fn_periodos_equivalentes antiga: 8 (7 + 1). Cada condição sabotada sozinha: sem a abertura (ano - 1): 4; sem o "não é parcial" (agora nas duas direções, médio 1): 5 (4 + sonda); abertura sem a regra patrimonial-ou-sem-movimento
-- (médio 2): 2 (1 + sonda); só a metade "sem movimento" (sem o patrimonial): 1; só a metade "patrimonial" (sem o "sem movimento"): 2 (1 + sonda); sem o filtro de saldo (Débito/Crédito viram coluna): 4 (3 + sonda); referência
-- multi-ano passando a valer: 1; contenção sem a exclusão do parcial (alto): 6 (5 + sonda); sem a união contígua: 2; sem a contenção: 2 (1 + sonda); sem o ano mais recente igual: 1; o backfill sem o filtro de estado
-- aberta: 2; sem o filtro de origem diagnostico: 3 (2 + sonda). A medição de "Ativo 1000 x Passivo+PL 800 continua divergente" é a que mostra o efeito do defeito: com a função antiga ela reprova porque a checagem nem
-- comparava (sem_periodo_par) — a divergência de verdade ficava escondida junto com o falso alarme. Todas as migrations aplicaram (conferido: o teste aparece no log e o aviso MEDIDO sai; cada sabotagem passa por
-- uma substituição que falha se o padrão não for achado exatamente uma vez).
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- (A) fn_coluna_periodo_do_ano: o ano da referência do documento para a coluna que nomeia um saldo
-- ---------------------------------------------------------------------------
create or replace function fn_coluna_periodo_do_ano(p_documento_versao_id uuid, p_ano integer)
returns text
language plpgsql
stable
as $$
declare
  v_col      text;
  v_tem      boolean;
  v_tipo_doc text;
  v_ptipo    text;
  v_pref     text;
  v_anos     int[];
begin
  select ce.periodo_coluna into v_col
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.periodo_coluna is not null
    and p_ano = any (fn_anos_texto(ce.periodo_coluna))
  group by ce.periodo_coluna
  order by count(*) desc, ce.periodo_coluna
  limit 1;
  if v_col is not null then return v_col; end if;

  -- 0234: o ano NÃO está no texto de coluna nenhuma. A coluna que NOMEIA um saldo ("Saldo Final", "Saldo atual",
  -- "Saldo Inicial", "Saldo anterior") herda o ano da referência do período do documento, como na 0201 (Realizado).
  select d.tipo_taxonomia, p.tipo, p.referencia into v_tipo_doc, v_ptipo, v_pref
    from documento_versao dv
    join documento d on d.id = dv.documento_id
    left join periodo p on p.id = d.periodo_id
   where dv.id = p_documento_versao_id;
  v_anos := fn_anos_periodo(v_ptipo, v_pref);
  -- shortcut: referência multi-ano com coluna sem ano fica no sentinela (não diz de qual ano é o "Saldo Final"); sobe se aparecer documento real assim.
  if p_ano is not null and cardinality(v_anos) = 1 then
    select ce.periodo_coluna into v_col
    from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id
      and ce.periodo_coluna is not null
      and fn_coluna_e_saldo(ce.periodo_coluna)
      -- 0234 (revisão, médio 1): o documento de período PARCIAL (DRE/balancete "01/01/2026 - 30/06/2026") não herda o ano em NENHUMA direção: o "Saldo atual" dele é o acumulado de 6 meses, não o ano
      -- cheio (comparado ao faturamento de mais meses dava divergência falsa de ~25%), e o "Saldo inicial" é o início do período. Parcial continua no sentinela, como antes da 0234.
      and not coalesce(fn_periodo_e_parcial(ce.periodo_coluna, v_tipo_doc, v_ptipo, v_pref), false)
      and case when p_ano = v_anos[1]     then not fn_coluna_e_abertura(ce.periodo_coluna)
               -- 0234 (revisão, médio 2): a abertura (ano - 1) só vale em demonstração PATRIMONIAL (o saldo inicial do balanço é o fechamento do ano anterior) ou quando o documento NÃO traz colunas de
               -- movimento. Razão no formato Saldo anterior / Débito / Crédito / Saldo atual zera as contas de resultado no fechamento: o "Saldo anterior" delas é 0, e lê-lo como o ano - 1 faria a receita
               -- do ano anterior valer ZERO (ausência apresentada como dado, regra 1).
               when p_ano = v_anos[1] - 1 then fn_coluna_e_abertura(ce.periodo_coluna)
                                               and (v_tipo_doc in ('BALANCO', 'BALANCETE')
                                                    or not exists (select 1 from campo_extraido mv
                                                                    where mv.documento_versao_id = p_documento_versao_id
                                                                      and fn_coluna_e_movimento(mv.periodo_coluna)))
               else false end
    group by ce.periodo_coluna
    order by count(*) desc, ce.periodo_coluna
    limit 1;
    if v_col is not null then return v_col; end if;
  end if;

  select exists (
    select 1 from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id and ce.periodo_coluna is not null
  ) into v_tem;
  return case when v_tem then E'\x01' else null end;
end;
$$;

comment on function fn_coluna_periodo_do_ano(uuid, integer) is
  '0234 (sobre a 0023): a coluna de período do documento que vale para o ano. 1) a coluna cujo TEXTO tem o ano (a mais frequente; como antes). 2) 0234: sem ano no texto, e a referência do período do documento ancora UM só ano (fn_anos_periodo): ano = esse ano -> a coluna que nomeia saldo e não é de abertura (Saldo Final/atual); ano = esse ano - 1 -> a de abertura (Saldo Inicial/anterior), só em demonstração patrimonial (BALANCO/BALANCETE) ou em documento sem coluna de movimento (Débito/Crédito: no razão o Saldo anterior das contas de resultado é 0); em NENHUM dos dois sentidos para documento de período parcial (fn_periodo_e_parcial: o Saldo atual de um semestre não é o ano); fn_coluna_e_saldo, fn_coluna_e_abertura e fn_coluna_e_movimento são as da 0201; Débito/Crédito nunca é saldo; "Saldo", "Valor" não nomeiam saldo. 3) Nada disso: o sentinela E''\x01'' (o documento TEM colunas de período e nenhuma é deste ano) ou nulo (sem coluna nenhuma). Referência multi-ano com coluna sem ano fica no sentinela (teto conhecido). O ponto único das reconciliações fn_reconciliar_* e de fn_linha_vale_para_ano.';

-- ---------------------------------------------------------------------------
-- (B) fn_periodos_equivalentes: mesmo ano mais recente, um conjunto contém o outro, união contígua
-- ---------------------------------------------------------------------------
-- Antes de trocar a função: nada a guardar. O backfill abaixo pergunta à função nova, e uma pendência cujo par a
-- regra antiga já declarava equivalente (as 6 de produção) também deve sair: a função não vê divergência ali.
create or replace function fn_periodos_equivalentes(p_tipo_a text, p_ref_a text, p_tipo_b text, p_ref_b text)
returns boolean
language sql
immutable
as $$
  select case
    when fn_periodo_canonico(p_tipo_a, p_ref_a) is null
      or fn_periodo_canonico(p_tipo_b, p_ref_b) is null then true
    when fn_periodo_canonico(p_tipo_a, p_ref_a) = fn_periodo_canonico(p_tipo_b, p_ref_b) then true
    when cardinality(fn_anos_periodo(p_tipo_a, p_ref_a)) = 0
      or cardinality(fn_anos_periodo(p_tipo_b, p_ref_b)) = 0 then true
    else fn_anos_periodo(p_tipo_a, p_ref_a) = fn_anos_periodo(p_tipo_b, p_ref_b)
      -- 0234: o documento COMPARATIVO ("multi 24,25") e a leitura do exercício corrente ("anual 12M25") são o MESMO
      -- documento: mesmo ano mais recente, um conjunto contém o outro, e a união é uma sequência contígua de anos.
      -- Só entre períodos NÃO parciais (revisão, alto): "data-base 2025-06-30" (balanço intermediário) x "multi 24,25" NÃO é o mesmo exercício: o saldo de junho entraria no Realizado como se fosse o fechamento.
      -- Parcial segue pela regra de antes (forma canônica igual ou conjuntos de anos iguais).
      or (    not coalesce(fn_periodo_e_parcial(null, null, p_tipo_a, p_ref_a), false)
          and not coalesce(fn_periodo_e_parcial(null, null, p_tipo_b, p_ref_b), false)
          and (select max(x) from unnest(fn_anos_periodo(p_tipo_a, p_ref_a)) x)
            = (select max(x) from unnest(fn_anos_periodo(p_tipo_b, p_ref_b)) x)
          and (   fn_anos_periodo(p_tipo_a, p_ref_a) <@ fn_anos_periodo(p_tipo_b, p_ref_b)
               or fn_anos_periodo(p_tipo_b, p_ref_b) <@ fn_anos_periodo(p_tipo_a, p_ref_a))
          and (select max(x) - min(x) + 1 = count(distinct x)
                 from unnest(fn_anos_periodo(p_tipo_a, p_ref_a) || fn_anos_periodo(p_tipo_b, p_ref_b)) x))
  end;
$$;

comment on function fn_periodos_equivalentes(text, text, text, text) is
  '0234 (sobre a 0022): dois períodos são o mesmo exercício? Verdadeiro quando a forma canônica é igual, quando algum não ancora ano (não verificável), quando os conjuntos de anos são iguais, OU (0234) quando NENHUM dos dois é parcial (fn_periodo_e_parcial) e o ano mais recente é o mesmo, um conjunto contém o outro e a união é uma sequência de anos contígua ("multi 24,25" x "anual 12M25" ou "data-base 2025-12-31"); com um lado parcial ("data-base 2025-06-30", "multi 01/07/2025 a 30/06/2026") a contenção não vale. Continuam distintos: "anual 21,25" x "multi 23,24,25" (um não contém o outro), "anual 25,26" x "multi 24,25" e "anual 23,24" x "anual 2023" (ano mais recente diferente), "multi 2024,2025" x "multi 01,24,25" (união não contígua). Chamador único: fn_registrar_diagnostico.';

-- ---------------------------------------------------------------------------
-- O BACKFILL (B), como função: o teste o roda sobre arranjos conhecidos e uma sessão futura o reroda.
-- ---------------------------------------------------------------------------
create or replace function fn_resolver_periodo_incorreto_falso(p_caso_id uuid default null)
returns integer
language plpgsql
as $$
declare
  v_n     integer;
  v_casos text;
begin
  with alvo as (
    select pe.id, pe.caso_id
      from pendencia pe
      cross join lateral (
        select regexp_match(pe.descricao, 'sugere período "(\S+) (.+?)" \(documento está registrado com "(\S+) (.+?)"\)') as m) x
     where pe.tipo = 'periodo_incorreto'
       and pe.estado = 'aberta'                  -- só 'aberta': as demais são decisão de gente
       and pe.origem_estagio = 'diagnostico'     -- só a que o sistema abriu
       and (p_caso_id is null or pe.caso_id = p_caso_id)
       and x.m is not null
       and fn_periodos_equivalentes(x.m[1], x.m[2], x.m[3], x.m[4])),
  feito as (
    update pendencia pe
       set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:0234'
      from alvo
     where pe.id = alvo.id
    returning pe.caso_id)
  select count(*), string_agg(distinct caso_id::text, ',') into v_n, v_casos from feito;
  if v_n > 0 then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:migration_0234', 'periodo_incorreto_falso_resolvido', 'pendencia',
              jsonb_build_object('pendencias', v_n, 'casos', v_casos));
  end if;
  return v_n;
end;
$$;

comment on function fn_resolver_periodo_incorreto_falso(uuid) is
  '0234: resolve (resolvida_por = sistema:0234) a pendência periodo_incorreto em estado aberta, de origem diagnostico, cujo par sugerido x registrado (lido da descrição) fn_periodos_equivalentes declara equivalente. Não toca em em_correcao_interna, reenviada_ao_cliente, aceita_com_ressalva nem rejeitada (decisão humana). Devolve quantas resolveu; idempotente.';

revoke all on function fn_resolver_periodo_incorreto_falso(uuid) from public, anon;
grant execute on function fn_resolver_periodo_incorreto_falso(uuid) to service_role;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    execute 'grant execute on function fn_resolver_periodo_incorreto_falso(uuid) to supabase_read_only_user';
  end if;
end $$;

do $$
declare
  v_n int;
  v_c uuid;
  v_k int := 0;
begin
  v_n := fn_resolver_periodo_incorreto_falso();
  raise notice '0234 backfill B: % pendência(s) periodo_incorreto falsa(s) resolvida(s) (sistema:0234)', v_n;

  -- (A) os mandatos com "sem período par" aberto são reconciliados de novo pela função de sempre.
  for v_c in
    select distinct pe.caso_id from pendencia pe
     where pe.tipo = 'precondicao_nao_satisfeita' and pe.estado <> 'resolvida'
       and pe.descricao ilike '%sem período par%'
     order by 1
  loop
    perform fn_reconciliar_caso(v_c);
    perform fn_recomputar_completude(v_c);
    v_k := v_k + 1;
  end loop;
  raise notice '0234 backfill A: % mandato(s) com "sem período par" aberto reconciliado(s) de novo', v_k;
end $$;

-- ---------------------------------------------------------------------------
-- A SONDA. Marcadores em CÓDIGO (pg_get_functiondef traz comentário; um marcador citado só em comentário passaria sem a lógica).
-- ---------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('coluna_do_ano_le_saldo_final', '0234', 'corpo', 'fn_coluna_periodo_do_ano', 'fn_coluna_e_saldo(ce.periodo_coluna)', null,
   'Sem ano no texto, a coluna que nomeia saldo (Saldo Final/atual) vale para o ano da referência do documento. Corpo sem isto = o balanço com "Saldo Final" volta a cair em "sem período par" (Fw Valtra, 5 pendências em 10/11/2026).',
   'importante', 1076),
  ('coluna_do_ano_abertura_e_ano_menos_um', '0234', 'corpo', 'fn_coluna_periodo_do_ano', 'fn_coluna_e_abertura(ce.periodo_coluna)', null,
   'A coluna de abertura (Saldo Inicial/anterior) vale para o ano - 1, e o fechamento não a usa. Corpo sem isto = o fechamento e a abertura se confundem (ou a abertura nunca é lida).',
   'importante', 1077),
  ('coluna_do_ano_abertura_nao_vale_em_parcial', '0234', 'corpo', 'fn_coluna_periodo_do_ano', 'fn_periodo_e_parcial(ce.periodo_coluna', null,
   'O documento de período parcial (balancete/DRE semestral) não herda o ano da referência: o Saldo atual dele é o acumulado do período e o Saldo Inicial é o início dele. Corpo sem isto = o semestre vale como o ano cheio e a reconciliação compara 6 meses com 12 (divergência falsa de ~25%).',
   'importante', 1078),
  ('coluna_do_ano_abertura_so_sem_movimento', '0234', 'corpo', 'fn_coluna_periodo_do_ano', 'fn_coluna_e_movimento(mv.periodo_coluna)', null,
   'A abertura (ano - 1) só vale em demonstração patrimonial ou em documento sem coluna de movimento: no razão (Saldo anterior / Débito / Crédito / Saldo atual) o Saldo anterior das contas de resultado é 0. Corpo sem isto = a receita do ano anterior vale ZERO (ausência como dado, regra 1).',
   'importante', 1084),
  ('periodos_equivalentes_contiguo', '0234', 'corpo', 'fn_periodos_equivalentes', '<@ fn_anos_periodo(p_tipo_b, p_ref_b)', null,
   'Mesmo ano mais recente, um conjunto contém o outro, união contígua = o mesmo exercício (comparativo "multi 24,25" x "anual 12M25"). Corpo sem isto = periodo_incorreto falso volta a abrir (35 de 57 abertas em produção, 10/11/2026).',
   'importante', 1079),
  ('periodos_equivalentes_so_sem_parcial', '0234', 'corpo', 'fn_periodos_equivalentes', 'fn_periodo_e_parcial(null, null, p_tipo_a, p_ref_a)', null,
   'A contenção "mesmo ano mais recente + união contígua" não vale com um lado parcial: "data-base 2025-06-30" x "multi 24,25" são exercícios diferentes. Corpo sem isto = o saldo de junho entra no Realizado como se fosse o fechamento.',
   'importante', 1085),
  ('periodo_incorreto_falso_funcao', '0234', 'funcao', 'fn_resolver_periodo_incorreto_falso', null, null,
   'O backfill reexecutável da pendência periodo_incorreto falsa. Ausente = a 0234 não foi aplicada: as pendências falsas já abertas continuam na fila.',
   'importante', 1080),
  ('periodo_incorreto_falso_so_aberta_do_sistema', '0234', 'corpo', 'fn_resolver_periodo_incorreto_falso', 'pe.origem_estagio = ''diagnostico''', null,
   'O backfill só resolve o que o sistema abriu e está em estado aberta. Corpo sem isto = decisão humana (em_correcao_interna, aceita_com_ressalva...) é desfeita pela migration.',
   'importante', 1081)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0234', revisado_em = current_date,
       observacao = 'A 0234 reemite fn_coluna_periodo_do_ano (coluna de saldo herda o ano da referência do documento, só em período não parcial; abertura só em demonstração patrimonial ou sem movimento) e fn_periodos_equivalentes (mesmo ano mais recente, contenção, união contígua, só entre períodos não parciais), cria fn_resolver_periodo_incorreto_falso (backfill sistema:0234); 8 requisitos novos.'
 where id = true;

commit;
