-- =============================================================================
-- 0277 — O AGING QUE APAGAVA A DIVERGÊNCIA DE UM ANO E SOMAVA O PAI COM AS FILHAS: os 3 ALTOS e 3 médios da revisão independente da conciliação
--        do aging da 0274 (sessão 127b, 12/11/2026), mais os achados da revisão desta própria migration (2ª tentativa, 12/11/2026). A 0274 já estava
--        em produção (tabela vazia: nenhum aging importado ainda), então nada foi conciliado errado: esta migration chega antes da primeira carteira.
--        NUMERAÇÃO: o dono pediu 0277 (a 0275 ficou livre de propósito e a 0276 é de outra branch). NÃO APLICADA em produção.
-- (Cria 2 colunas, 2 funções, 1 CHECK e 1 view da sonda. Recria 1 função (muda o tipo de retorno) e reemite 3: a central fn_registrar_reconciliacao, a
--  conciliação do aging e a importação. Nenhum backfill: aging_importado tinha 0 linhas em produção em 12/11/2026, medido por leitura.)
--
-- O DEFEITO E A CAUSA, MEDIDOS EM PRODUÇÃO (leitura, 12/11/2026; nenhuma escrita)
--
--  ALTO 1 — O ok de uma carteira resolvia a divergência de outra. fn_reconciliar_aging passava a fn_registrar_reconciliacao o `periodo_id` DO DOCUMENTO, e
--    a pendência é achada por período COMPATÍVEL (anos que se intersectam, 0022): num balanço comparativo ("multi 24,25") as carteiras de 31/12/2024 e
--    31/12/2025 caíam na MESMA pendência, e fn_reconciliar_aging_do_caso visita por data-base crescente: o ok do ano novo apagava a divergência do velho.
--    Produção: 188 BALANCO e 18 COMBINADO com colunas de mais de um ano. O mesmo vale para duas datas-base do MESMO ano (30/06 e 31/12 de 2025), e para
--    os ramos sem documento (documento_ausente e sem_periodo_par passam periodo_id NULL, e fn_periodos_compativeis(NULL, x) é verdadeiro: a pendência
--    casava QUALQUER ano; reproduzido: carteira 31/12/2024 divergente de R$ 98.000 caía na pendência sem período da de 30/06/2025, e o ok de 31/12/2025
--    a resolvia, 0 abertas com a divergência de 2024 viva).
--    A 1ª TENTATIVA desta migration fabricava um período ('data-base', 'AAAA-MM-DD') por carteira. Foi REJEITADA: o período novo entra no laço de
--    fn_periodos_compativeis_array das checagens clássicas e muda o resultado delas (reproduzido: um ativo_passivo_pl passou a `ok` num período que nenhum
--    documento trouxe), não tinha forma canônica, e deixava o mesmo ano com datas-base diferentes na mesma pendência.
--    CORREÇÃO (decisão do dono, 12/11/2026), NA FUNÇÃO CENTRAL: os quatro tipos do aging (aging_ar_clientes, aging_ar_adiantamentos, aging_ap_fornecedores,
--    aging_ap_adiantamentos) são tipos POR DATA-BASE, no mesmo espírito de c_tipos_por_documento (secao_fecha, que acha a pendência pelo documento).
--    fn_registrar_reconciliacao, reemitida do corpo VIGENTE (0241; nenhuma migration entre a 0241 e a 0277 a reemitiu, conferido por grep), acha a pendência
--    e o estado vigente deles por (caso, motivo, entidade, DATA-BASE) e não por período: datas-base diferentes nunca compartilham pendência, descrição
--    nem a guarda da 0192 (não há "carteira irmã" dentro de uma data-base; a guarda continua para todo o resto).
--    COMO A DATA-BASE CHEGA, sem mudar a assinatura (13 argumentos; os chamadores são muitos: as fn_reconciliar_* de 0105 a 0234, fn_registrar_reconciliacao_b e
--    quatro testes): por `p_fonte_a.aging_id`, que a conciliação do aging já gravava (v_fa desde a 0274), lida de aging_importado (a data-base é a da
--    importação, nunca o que o chamador diz) e recusada com raise se a importação não é do mesmo mandato e da mesma entidade. Alternativas descartadas:
--    um set_config como o oria.periodo_chave (estado escondido que vaza entre chamadas e que o chamador esquece) e um argumento novo (muda a assinatura de
--    uma função quente). Para guardar a identidade, duas COLUNAS NOVAS: pendencia.data_base e reconciliacao.data_base (date, NULL em todo tipo que não é
--    do aging; nenhum backfill: nenhuma linha do aging existe em produção).
--    O QUE MUDA NO CORPO (diff contra a 0241: 51 linhas, todas acréscimo): a lista c_tipos_por_data_base e v_por_data_base; a leitura da data-base e o
--    raise; a coluna data_base no insert de reconciliacao e no de pendencia; na busca da pendência, `(v_por_data_base or <período compatível>)` e
--    `(not v_por_data_base or data_base is not distinct from v_data_base)`; `or v_por_data_base` em v_reescreve_descricao (o texto é o da última rodada
--    daquela carteira); `and not v_por_data_base` na guarda da 0192. PARA TODO TIPO QUE NÃO É DO AGING o corpo executa exatamente o que executava: cada
--    acréscimo é um `v_por_data_base or ...` falso, um `not v_por_data_base or ...` verdadeiro, ou uma coluna que fica NULL. PROVA: a suíte inteira do run.sh
--    (todos os outros testes, sem alterar a expectativa de nenhum) passa. O período que o aging passa é o do DOCUMENTO lido, como na 0274 (é o que a tela
--    mostra); NENHUM período é criado.
--    TETO DECLARADO: fn_corrigir_descricao_contaminada (0241, backfill reexecutável, só roda quando alguém a chama) acha o "último registro do próprio" por
--    tipo e período e não conhece data_base: numa pendência do aging cujo período lido mudou entre importações ela poderia devolver o texto de outra
--    data-base. Não é chamada por nada além da 0241; sobe se alguém a reexecutar com carteiras de mais de uma data-base no mesmo período.
--
--  ALTO 2 — Pai e filhas de Fornecedores/Clientes somavam em dobro. A regra "o pai vale sozinho" dependia de `secao` da filha = nome do pai; a
--    forma real em produção é pai e filhas com a MESMA `secao` ("Passivo Circulante") ou `secao` nula, o pai imediatamente antes das filhas e com o
--    valor igual à soma exata delas ("Fornecedores" 24.549 = 16.843 + 3.600 + 4.106; "Fornecedores" 1.892 = a filha única 1.892). Rodando a própria
--    fn_aging_linhas_do_balanco da 0274 em todo grupo (documento × coluna de entidade × coluna de período) de produção, devolviam pai E filhas:
--    Fornecedores BALANCO 215 grupos (24 mandatos), COMBINADO 26 (8), BALANCETE 6 (3); Clientes BALANCETE 20 (3), BALANCO 5 (2), COMBINADO 10 (2).
--    Mais um fato medido que a tarefa não trazia: 146 das 1.648 versões de documento têm `ordem` NULA em alguma linha (5.919 de 138.931 linhas),
--    então a contiguidade por ordem sozinha não resolve. CORREÇÃO, pela ESTRUTURA (em fn_aging_linhas_do_balanco, que passa a devolver `aviso`):
--      (i) PELO NOME: a linha cujo nome contém todas as palavras do pai (pelos 7 primeiros caracteres: fornecedor = fornecedores) e mais alguma é
--          filha dele. Pai que é a soma delas EM MÓDULO (meia unidade da escala por linha: (escala do pai + Σ escalas das filhas) / 2) é subtotal e vale
--          SOZINHO; pai que as filhas COBREM EM PARTE (valor maior que a soma e do mesmo sinal: a extração não trouxe todas as filhas) também vale
--          sozinho e AVISA; pai que as filhas EXCEDEM não é subtotal;
--      (ii) PELA ORDEM, só para o pai de nome de manual (Clientes, Fornecedores, Duplicatas a receber, com código de plano de contas na frente):
--          as até 6 linhas seguintes, quando a soma das primeiras k fecha com ele ("Clientes" seguido de duas duplicatas de nomes próprios);
--      (iii) a mesma conta com dois nomes de manual ("CLIENTES" e "DUPLICATAS A RECEBER" com o valor idêntico ao centavo, na mesma escala) vale uma vez;
--      e a regra antiga (filha com `secao` = nome do pai; pai líquido cede às filhas) continua como estava.
--    O QUE ACONTECE QUANDO O PAI NÃO FECHA (decisão declarada, não silenciosa): (a) cobre em parte: o PAI vale sozinho, e a descrição da conciliação diz
--    "entrou sozinho: as N linhas ... somam X e cobrem só parte dos Y; se o resto é de linhas que a extração não trouxe, o valor está certo; se o pai é
--    uma conta própria, está subestimado"; (b) excede: o pai NÃO é subtotal e ENTRA com as filhas que nenhuma outra regra absorveu, e o aviso diz "entrou na
--    soma junto com a(s) N linha(s)... se o balanço as conta dentro dele, o valor está em dobro"; (c) escala desconhecida: nada se compara (a conciliação já
--    devolve unidade_divergente); (d) valores idênticos com nomes que não são de manual: avisa "se são a mesma conta com dois nomes, a soma está em dobro".
--    O aviso vai na descrição da conciliação, `ok` ou divergente (Atenção na leitura do balanço).
--    O AVISO DESCREVE O QUE ENTROU (achado M2 da revisão): ele passou a ser montado DEPOIS das três absorções (a CTE `entra`), não antes. A versão
--    anterior calculava "excede" sobre as filhas por nome e a janela por ordem absorvia depois: Fornecedores 5.329 > Fornecedores nacionais 5.329 > em
--    atraso 3.381 + a vencer 1.948 entrava só 5.329 (certo) e o aviso dizia "entraram todas, em dobro". Agora esse arranjo de três níveis entra só o pai e
--    NÃO avisa (a janela absorve "nacionais" e o nome absorve atraso e a vencer). Onde as filhas por nome NÃO se absorvem entre si e a janela não fecha
--    (pai 10.000 > nacionais 5.329 + exterior 4.671, cada uma com subfamília), pai e as duas entram e o aviso diz isso: é o TETO, uma hierarquia (pai e
--    filhas; neto só quando a janela ou o nome de manual o resolve).
--    A medição em produção (corpus de 12/11 carregado num banco local, 597 versões de BALANCO/BALANCETE/COMBINADO, e as DUAS funções, a da 0274 e a final,
--    rodadas sobre os mesmos grupos):
--      enumeração da tarefa (todo par distinto de colunas do documento): grupos com pai e filhas ANTES 282 (215+26+6+20+5+10, reproduz os números acima) →
--        DEPOIS 7 (Fornecedores COMBINADO 6 em 3 mandatos, quase todos de escala ausente, que dá unidade_divergente; Clientes COMBINADO 1);
--      enumeração dos grupos REAIS (a coluna nula só para versão sem nenhuma linha com coluna preenchida, que é como a conciliação chama): 280 → 5;
--      avisos nos grupos reais: 45 de "cobre em parte" (39 de Fornecedores BALANCO, 6 de Fornecedores BALANCETE), 1 de "excede" (o d19a86ce, abaixo), 3 de
--      valor repetido. (Reconferido com a função FINAL, a desta migration, em 12/11/2026, depois de o aviso passar a ser montado sobre o que entrou: os mesmos
--      282 → 7 e 280 → 5.)
--    O "excede" REAL (achado M3): o único em grupo real é a versão d19a86ce (Clientes BALANCO, coluna 31/12/2024): "Clientes - duplicatas a receber -
--    mercado interno" 24.861 e "Duplicatas a receber de clientes - mercado interno" 35.044 na MESMA coluna. NÃO É pai com filha: é a mesma conta com dois
--    nomes em ANOS diferentes (24.861 é a coluna 2025 e 35.044 a de 2023 na versão 6194209b do mesmo balanço) que a extração de d19a86ce deixou numa coluna
--    só. O teste usa esse arranjo e afirma só que as linhas entram e que o aviso diz "pode estar em dobro"; não afirma que exista pai cujas filhas excedem
--    na estrutura real do balanço (a fixture anterior inventava o parentesco). A REGRA DOS 7 CARACTERES (achado M3): avaliada contra uma regra de plural
--    exato (fornecedor = fornecedores, nada além), as duas devolvem as MESMAS linhas nos 2.052 grupos (documento × coluna × conceito) de produção:
--    não há evidência de palavra demais; ficou a regra de antes. O que casa demais é o NOME GENÉRICO do pai ("Clientes" 900 e "Clientes no exterior" 300 podem ser
--    duas contas): isso o código não distingue, e o aviso de "cobre em parte" é a declaração.
--
--  ALTO 3 (herdado da 0274) — A CONVENÇÃO DE SINAL. v_aging é abs(...) e v_balanco somava COM sinal: com Fornecedores negativo no balanço o resultado
--    era |aging| + |balanço| (carteira de 5.621.000 contra -4.719 e -902 dava divergente de 11.242.000, devia conferir). DECISÃO, medida em produção
--    (12/11/2026, leitura): o sinal de Clientes/Fornecedores/Adiantamentos no balanço é CONVENÇÃO DE APRESENTAÇÃO (passivo e crédito impressos
--    negativos: balancete com colunas Crédito e Saldo Atual, "FORNECEDORES" -8.111.470, "Fornecedores nacionais - em atraso" -4.719), não um saldo oposto.
--    Dos 2.027 grupos (versão × coluna × conceito, as quatro contas) com linha dessas contas, 13 têm linha negativa (10 de Fornecedores, em 7 versões e 6
--    mandatos, 1 de Clientes, 1 de Adiantamentos de clientes, 1 de Adiantamentos a fornecedores) e NENHUM mistura sinais: quando é negativo, é negativo o
--    grupo inteiro. Por isso o aging (em módulo) é comparado com o MÓDULO da soma com sinal das linhas que entraram (`abs(v_aging - abs(v_balanco))`), a
--    descrição diz "impresso com sinal negativo (convenção de apresentação: comparado em módulo)", e fonte_b grava `valor` (módulo) e `valor_com_sinal`.
--    A relação pai/filhas (fecha) também é em módulo (pai +5.621 e filhas -4.719 e -902 fecham). Se um grupo MISTURAR sinais entre as linhas que entram
--    (nunca visto em produção), a soma com sinal é a comparada e a descrição diz "as linhas ... têm sinais opostos (N positivas, M negativas): ... a
--    diferença pode não ser real", porque duas linhas de sinais opostos podem ser duas contas. Os asserts desse arranjo (pai positivo e filhas negativas, sinais
--    opostos na soma, janela por ordem com sinais opostos) são GUARDAS da regra declarada, não prova de bug de produção: nenhum desses arranjos existe lá.
--
--  ALTO 3 da 0277 original — Balanço que só existe como coluna de um combinado de OUTRA empresa virava documento_ausente (sem pendência): o laço filtrava
--    `d.entidade_id = a.entidade_id`. Produção: 145 pares (entidade, combinado alheio) em que fn_coluna_entidade acha a coluna; 12 entidades em 3
--    mandatos não têm balanço próprio nenhum. CORREÇÃO: entra também o documento do caso cuja coluna fn_coluna_entidade resolve para esta entidade
--    (nunca nulo nem o sentinela \x01: documento sem colunas de entidade de outra empresa NÃO vale, por palpite nenhum). ORDEM: (1) o documento da
--    PRÓPRIA entidade, (2) o de outra empresa na coluna dela; dentro de cada, BALANCO > COMBINADO > BALANCETE e o mais novo. O próprio vem primeiro
--    porque é a demonstração da empresa, e a coluna de um combinado é uma leitura derivada (pode trazer ajustes de consolidação). A descrição e
--    fonte_b dizem de quem é o documento e a coluna lida ("[balanço lido: COMBINADO de Grupo Holding, na coluna ..., outra empresa do grupo]").
--
--  MÉDIOS
--   * B2 — SEM PAR COM O LADO DA CARTEIRA VAZIO: carteira cujo balanço não fecha na data-base (sem_periodo_par / precondicao_nao_satisfeita) e cujo saldo
--     do lado é ZERO abria pendência "sem par" para conferir zero. Agora é `ok` com divergência 0 e o texto diz que nada foi comparado ("o ok vale só
--     porque não há saldo na carteira a conferir"), como a carteira zero com o balanço sem a conta já era. Declarado, não escondido: o `ok` não afirma que o
--     balanço da data tem a conta zerada.
--   * LADO DO BALANÇO: conta de ESTOQUE com "cliente"/"fornecedor" no rótulo casava ("MERCADORIA EM GARANTIA/CONSERTO A RECEBER(FORNECEDOR)"). Medido
--     (linhas que casam o rótulo, em produção): Fornecedores com secao_canonica ativo_circulante 28 (todas com seção ESTOQUE), ativo_nao_circulante 15,
--     atividades_operacionais 11; Clientes com secao ESTOQUE 40 e secao_canonica passivo_circulante 10; Adiantamentos de clientes em ativo_circulante 4.
--     Agora: a linha entra só se a secao_canonica é a do lado do conceito (Clientes e Adiantamentos a fornecedores: ativo_circulante; Fornecedores e
--     Adiantamentos de clientes: passivo_circulante) OU é NULA, e se a seção em texto não diz "estoque". secao_canonica NULA (67 linhas: 31 de Clientes,
--     36 de Fornecedores, em 14 e 12 versões) NÃO exclui nada: a linha fica, o rótulo é o único filtro (teto declarado). Se a IA classificou errado o
--     lado de uma conta legítima, ela vira linha_nao_localizada (visível, com o valor), nunca zero.
--   * O RESUMO AMARRADO AO APLICADOR: a 0274 validava resumo e aplicador cada um por si; nada garantia que o resumo era do arquivo que o aplicador
--     leu. fn_aging_aplicador_erros (usada por fn_aging_importar e pela CHECK aging_resumo_e_aplicador, que cobre o service_role) exige: titulo do
--     aplicador = resumo.titulos; saldo_titulos = positivos.saldo + negativos.saldo; titulos_com_saldo_negativo (linhas, saldo) = negativos; e a
--     identidade do resumo titulos = positivos + negativos + liquidados (Leitor/lib/aging.mjs e Leitor/lib/mapeamento.mjs, lidos em 12/11/2026).
--     Campo ausente no aplicador é erro dito, nunca passa por zero. LIMITE: o banco compara o que o navegador diz; não relê o arquivo.
--   * BALANCETE QUE NUNCA "FECHA" (fn_balanco_fecha_em nulo): MEDIDO, NÃO CORRIGIDO. Em produção os 192 BALANCETE devolvem NULL (192 de 192): 49 porque o
--     período do documento é "parcial" (o tipo BALANCETE é parcial por doutrina, 0199/0200, mesmo com referência 12M25) e 143 porque o balancete tem
--     colunas de período sem o ano ("Saldo Anterior", "Débito", "Crédito", "Saldo Atual") e a 0234 não herda o ano em documento parcial. Dar a data seria
--     palpite: a referência de um balancete diz o período, não que ele fecha o exercício, e escolher a coluna "Saldo Atual" é decisão da 0234, que esta
--     migration não reabre. EFEITO (já visível na 0274): carteira conciliada com BALANCETE vira sem_periodo_par, com o motivo; só BALANCO e COMBINADO
--     concilia. (Os fixtures de sinal do teste usam as linhas de um BALANCETE de produção, 4a14371f, dentro de um BALANCO, por isso.)
--
-- FORA, por pedido (não feito): ACL de default privileges, tela/mapeamento global, ligar fn_reconciliar_aging_do_caso em fn_reconciliar_caso.
--
-- A SONDA (10 requisitos, ordem 1354-1363): a função do validador, o corpo da importação (amarra o aplicador), o corpo da função central (a pendência por
-- data-base), o corpo da conciliação (o balanço do grupo; a comparação em módulo), o corpo das linhas (o pai que fecha, em módulo; o lado do balanço),
-- as duas colunas data_base e a view da CHECK. Os requisitos de corpo da 0192 e da 0241 sobre fn_registrar_reconciliacao seguem casando (o corpo é o
-- vigente com acréscimos).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/o_aging_que_apagava_a_divergencia_de_um_ano_e_somava_o_pai_com_as_filhas.test.sql — 66 asserts
--   (medido: 66 chamadas, 66 execuções, nenhum em laço; reconferido com Supabase/test/medicao-denominador.test.mjs). Cada correção desligada UMA por vez DENTRO
--   de uma transação (a sabotagem recompõe a função por pg_get_functiondef e ABORTA se o trecho não existe: nenhuma variante deixou de aplicar), o teste inteiro
--   com o assert em `raise warning` (ct77.medindo=on; voltou para `raise exception`; log lido atrás de FALHOU) e a transação desfeita. Controle (migration
--   intacta): 0 dos 66 asserts reprovam, 66 execuções. O teste da 0274 segue verde com os fixtures do aplicador coerentes (helper teste_aplicador_0274; nenhum
--   assert mudou de valor esperado) e a suíte inteira do run.sh passa sem alterar a expectativa de nenhum outro teste. Por correção desligada (12/11/2026):
--   * ALTO 1, a função central: pendência achada por período compatível (sem o critério data_base): 13 dos 66 · guarda da 0192 não saltada para o aging: 1 ·
--     texto não reescrito pela rodada da data-base: 1 · pendência gravada sem data_base: 10 · reconciliacao gravada sem data_base: 1 · aging_id não exigido
--     (sem o raise): 2 · o período fabricado religado (A2, as checagens clássicas mudam): 3 dos 66;
--   * ALTO 3 (sinal): comparar com sinal (sem o módulo do balanço): 4 dos 66 · o pai que fecha só com sinal (nome): 1 · só com sinal (janela por ordem): 1 ·
--     sem o aviso de sinais opostos: 1 · sem a nota "impresso com sinal negativo": 1;
--   * M2, o aviso do "excede" sem olhar o que entrou: 2 dos 66 · B2, sem par com o lado da carteira vazio abre pendência: 1 dos 66;
--   * ALTO 3 da 0277 original, só o documento da própria entidade: 3 dos 66 · sem a preferência pelo próprio: 2 dos 66;
--   * ALTO 2, pai que fecha não vale sozinho: 4 dos 66 · pai que cobre em parte: 2 · sem a janela por ordem: 4 · sem o mesmo valor com dois nomes: 1 (a fixture
--     sem ordem estava na mesma entidade da com ordem, 'Dois Nomes' unificava os dois nomes, e o assert lia o 1º documento: a prova era vazia até esta
--     rodada, 0 reprovavam; hoje tem entidade própria) · sem o parentesco pelo nome (tudo de (i)): 7 · o aviso fora da descrição: 3 dos 66;
--   * médios, sem o lado do balanço (secao_canonica): 1 dos 66 · sem a seção de estoque: 1 · importar sem amarrar o aplicador: 7 · sem a CHECK da tabela: 3 ·
--     os dois: 9;
--   * o validador, uma regra por vez: títulos 2 dos 66 · soma dos saldos 1 · negativos (linhas) 1 · negativos (saldo) 1 · identidade do resumo 1 ·
--     aplicador sem o campo 1.
--   Os asserts de controle (balanço próprio, forma antiga, duas contas irmãs, a regra por módulo nos arranjos que produção não produz) passam em todas as variantes
--   que não os tocam: protegem o que não pode mudar. Regra 4: as FORMAS dos fixtures são as lidas em produção (cada uma citada no teste); os números de aging são
--   montados (não há arquivo de aging real: DM7). O assert das checagens clássicas (A2) agora tira a assinatura ANTES de qualquer aging num mandato à parte
--   e reprova com o período fabricado religado (a versão anterior tirava `v_antes` depois de os períodos existirem e nunca reprovava).
--   Mutantes sem efeito, declarados: a variante "período compatível E data-base" (a pendência exigir os dois) reprova 0 asserts e não é uma guarda: a data-base fixa o ano, e os
--   documentos que fecham naquele ano têm períodos que se intersectam, então o critério do período não restringe nada além do que a data-base já restringe.
-- =============================================================================
begin;

-- ---------------------------------------------------------------------------
-- 1. O RESUMO AMARRADO AO APLICADOR (fronteira de confiança): nada na 0274 ligava um ao outro
-- ---------------------------------------------------------------------------
create function fn_aging_aplicador_erros(p_resumo jsonb, p_aplicador jsonb) returns text[]
language plpgsql immutable set search_path = public, pg_temp as $$
declare
  e       text[] := '{}';
  v_tit   numeric;
  v_ap_t  numeric; v_ap_s numeric; v_ap_nl numeric; v_ap_ns numeric;
  v_r_pos_t numeric; v_r_neg_t numeric; v_r_liq numeric;
  v_pos_s numeric; v_neg_saldo numeric;
begin
  -- Objeto que não é objeto, ou resumo que não fecha consigo mesmo, é de fn_aging_resumo_erros e do teste de objetos: aqui só o que AMARRA os dois.
  if jsonb_typeof(p_resumo) is distinct from 'object' or jsonb_typeof(p_aplicador) is distinct from 'object' then
    return e;
  end if;
  v_tit      := fn_aging_contagem(p_resumo -> 'titulos');
  v_r_pos_t  := fn_aging_contagem(p_resumo #> '{positivos,titulos}');
  v_r_neg_t  := fn_aging_contagem(p_resumo #> '{negativos,titulos}');
  v_r_liq    := fn_aging_contagem(p_resumo -> 'liquidados');
  v_pos_s    := fn_aging_centavos(p_resumo #> '{positivos,saldo}');
  v_neg_saldo := fn_aging_centavos(p_resumo #> '{negativos,saldo}');
  -- A identidade da própria biblioteca (Leitor/lib/aging.mjs, titulo(): todo título conta em `titulos`; saldo zero é liquidado; o resto é positivo ou negativo).
  if v_tit is not null and v_r_pos_t is not null and v_r_neg_t is not null and v_r_liq is not null and v_tit <> v_r_pos_t + v_r_neg_t + v_r_liq then
    e := e || format('resumo.titulos (%s) diferente de positivos (%s) + negativos (%s) + liquidados (%s): título que sumiu do resumo', v_tit, v_r_pos_t, v_r_neg_t, v_r_liq);
  end if;
  -- O que o APLICADOR (Leitor/lib/mapeamento.mjs) entregou à biblioteca tem de ser o que o resumo contou. Sem o campo, a ausência é dita: o banco não
  -- aceita um resumo que ninguém pode amarrar ao arquivo.
  v_ap_t := fn_aging_contagem(p_aplicador -> 'titulo');
  if v_ap_t is null then
    e := e || 'o aplicador não diz quantos títulos aplicou (titulo: contagem inteira): o resumo não se amarra ao arquivo'::text;
  elsif v_tit is not null and v_ap_t <> v_tit then
    e := e || format('o resumo conta %s títulos e o aplicador aplicou %s: o resumo não é o deste arquivo', v_tit, v_ap_t);
  end if;
  v_ap_s := fn_aging_centavos(p_aplicador -> 'saldo_titulos');
  if v_ap_s is null then
    e := e || 'o aplicador não diz a soma dos saldos (saldo_titulos: centavos, em texto): o resumo não se amarra ao arquivo'::text;
  elsif v_pos_s is not null and v_neg_saldo is not null and v_ap_s <> v_pos_s + v_neg_saldo then
    e := e || format('a soma dos saldos do aplicador (%s) é diferente de positivos (%s) + negativos (%s) do resumo', v_ap_s, v_pos_s, v_neg_saldo);
  end if;
  v_ap_nl := fn_aging_contagem(p_aplicador #> '{titulos_com_saldo_negativo,linhas}');
  v_ap_ns := fn_aging_centavos(p_aplicador #> '{titulos_com_saldo_negativo,saldo}');
  if v_ap_nl is null or v_ap_ns is null then
    e := e || 'o aplicador não diz os títulos de saldo negativo (titulos_com_saldo_negativo: linhas e saldo): os créditos do resumo não se amarram ao arquivo'::text;
  else
    if v_r_neg_t is not null and v_ap_nl <> v_r_neg_t then
      e := e || format('o resumo tem %s títulos negativos e o aplicador %s', v_r_neg_t, v_ap_nl);
    end if;
    if v_neg_saldo is not null and v_ap_ns <> v_neg_saldo then
      e := e || format('o saldo negativo do resumo (%s) é diferente do do aplicador (%s)', v_neg_saldo, v_ap_ns);
    end if;
  end if;
  return e;
end $$;
comment on function fn_aging_aplicador_erros(jsonb, jsonb) is
  '0277: amarra o resumo do aging ao resumo do aplicador do mapeamento (Leitor/lib/mapeamento.mjs): titulo = resumo.titulos; saldo_titulos = positivos.saldo + negativos.saldo; titulos_com_saldo_negativo = negativos (linhas e saldo); e a identidade do próprio resumo titulos = positivos + negativos + liquidados. Campo ausente no aplicador é erro dito (nunca passa por zero). Devolve os motivos (vazio = coerente). Usado por fn_aging_importar e pela CHECK aging_resumo_e_aplicador; LIMITE: o banco compara o que o navegador diz, não relê o arquivo.';

alter table aging_importado add constraint aging_resumo_e_aplicador check (cardinality(fn_aging_aplicador_erros(resumo, aplicador)) = 0);
comment on constraint aging_resumo_e_aplicador on aging_importado is
  '0277: o resumo do aging e o do aplicador contam os mesmos títulos e os mesmos saldos (fn_aging_aplicador_erros vazio), para quem escrever sem passar pela função (service_role). Produção tinha 0 linhas em aging_importado em 12/11/2026: a CHECK valida sem backfill.';

-- ---------------------------------------------------------------------------
-- 2. AS LINHAS DO BALANÇO: O PAI QUE SOMAVA COM AS FILHAS E O LADO DO BALANÇO
-- ---------------------------------------------------------------------------
-- Muda o tipo de retorno (ganha `aviso`): a 0274 a criou com 5 colunas, e só a conciliação a chama (grep em Supabase/ N8N/ portal/src/ em 12/11/2026).
drop function fn_aging_linhas_do_balanco(uuid, text, text, text);
create function fn_aging_linhas_do_balanco(p_versao uuid, p_conceito text, p_col_ent text, p_col_per text)
returns table (id uuid, chave text, valor_num numeric, unidade text, secao text, aviso text)
language plpgsql stable set search_path = public, pg_temp as $$
#variable_conflict use_column
declare
  v_inc text;
  v_exc text;
  v_sc  text;
  c_ded constant text := 'perda|pecld|pdd|duvidos|provis|descontad|antecipa|ajuste a valor presente';
  -- 0277: o nome do PAI "de manual": só o conceito (com código de plano de contas na frente, "1.7 - Fornecedores"). Só ele pode ser subtotal de linhas
  -- que NÃO repetem o nome dele (Clientes, seguido de "Duplicatas a receber"), porque a janela por ordem não tem outra prova de parentesco.
  c_nome_pai constant text := '^([0-9][0-9. -]*)?(clientes|fornecedores|duplicatas a receber)$';
begin
  v_inc := case p_conceito
             when 'clientes'                     then 'cliente|duplicatas? a receber'
             when 'fornecedores'                 then 'fornecedor'
             when 'adiantamentos_de_clientes'    then 'adiant.*cliente'
             when 'adiantamentos_a_fornecedores' then 'adiant.*fornecedor' end;
  if v_inc is null then
    raise exception 'conceito "%" não existe (clientes, fornecedores, adiantamentos_de_clientes, adiantamentos_a_fornecedores)', p_conceito using errcode = '22023';
  end if;
  -- 0277: o lado do balanço em que o conceito mora. `secao_canonica` NULA não exclui nada (a IA não classificou: a linha fica, e só a seção em texto
  -- e o nome a filtram); preenchida e de outro lado, a linha não é do conceito (medido em produção, 12/11/2026: Fornecedores com secao_canonica
  -- ativo_circulante = 28 linhas, todas "MERCADORIA EM GARANTIA/CONSERTO A RECEBER(FORNECEDOR)" na seção ESTOQUE; Clientes idem, 40 linhas).
  v_sc := case p_conceito when 'clientes' then 'ativo_circulante' when 'adiantamentos_a_fornecedores' then 'ativo_circulante' else 'passivo_circulante' end;
  -- Fora, sempre: variações de fluxo, deduções (PDD, duplicatas descontadas, ajuste a valor presente), longo prazo e partes relacionadas.
  -- Clientes/Fornecedores também deixam de fora o que é Adiantamento (conta própria).
  v_exc := case when p_conceito in ('clientes', 'fornecedores') then 'adiant|' else '' end
           || 'variacao|aumento|reducao|' || c_ded || '|longo prazo|nao circulante|mutuo|partes relacionadas|coligad|controlad|imobilizado|salario|empregado|tributo|imposto|dividendo';
  return query
  with base as (
    select ce.id, ce.chave, ce.valor_num, ce.unidade, ce.secao, ce.confianca, ce.ordem,
           fn_normalizar_texto(ce.chave) as n, fn_normalizar_texto(ce.secao) as s
      from campo_extraido ce
     where ce.documento_versao_id = p_versao and ce.valor_num is not null
       and p_col_ent is distinct from E'\x01' and p_col_per is distinct from E'\x01'
       and (p_col_ent is null or fn_normalizar_texto(ce.entidade_coluna) = fn_normalizar_texto(p_col_ent))
       and (p_col_per is null or fn_normalizar_texto(ce.periodo_coluna) = fn_normalizar_texto(p_col_per))
       and (ce.secao_canonica is null or ce.secao_canonica = v_sc)
       and coalesce(fn_normalizar_texto(ce.secao), '') !~ 'estoque'
  ), cand as (
    select distinct on (b.n) b.* from base b where b.n ~ v_inc and b.n !~ v_exc
     order by b.n, coalesce(b.confianca, 0) desc, b.ordem nulls last, b.id
  ), liquido as (   -- pai cuja dedução (PDD, descontadas) é filha: o valor dele é LÍQUIDO, não o bruto que a conciliação quer
    select c.n from cand c where exists (select 1 from base d where d.s = c.n and d.n ~ c_ded)
  ), c2 as materialized (   -- o que sobra das duas regras antigas (0274): pai líquido cede aos filhos; filha com `secao` = nome do pai some
    select c.*, fn_fator_escala(c.unidade) as fator, c.valor_num * fn_fator_escala(c.unidade) as vb,
           array(select left(w, 7) from unnest(regexp_split_to_array(c.n, '[^a-z0-9]+')) w where w <> '') as tok   -- palavras, pelos 7 primeiros caracteres (fornecedor = fornecedores; medido: uma regra de plural exato dá o MESMO resultado em 2.052 grupos de produção)
      from cand c
     where not exists (select 1 from cand p where p.n = c.s and p.n <> c.n and p.n not in (select n from liquido))
       and not (c.n in (select n from liquido) and exists (select 1 from cand f where f.s = c.n and f.n <> c.n))
  ), fam as materialized (   -- (i) PELO NOME: f é "filha" de p quando o nome de f contém todas as palavras do nome de p e mais alguma
    select p.id as pai, f.id as filha, f.vb, f.fator
      from c2 p join c2 f on f.id <> p.id and f.tok @> p.tok and not p.tok @> f.tok
  ), fam_soma as (
    select m.pai, count(*) as nf, sum(m.vb) as sv, sum(m.fator) as sf, bool_and(m.fator is not null) as completo
      from fam m group by m.pai
  ), fam_estado as (
    select s.pai, s.nf, s.sv, p.vb as vp,
           case when not (s.completo and p.fator is not null) then 'sem_escala'
                when abs(abs(p.vb) - abs(s.sv)) <= (p.fator + s.sf) / 2 then 'fecha'   -- em MÓDULO: o sinal é convenção de apresentação (ver fn_reconciliar_aging)
                when (p.vb > 0 and s.sv >= 0 and p.vb > s.sv) or (p.vb < 0 and s.sv <= 0 and p.vb < s.sv) then 'cobre_parte'
                else 'excede' end as estado
      from fam_soma s join c2 p on p.id = s.pai
  ), seq as materialized (   -- (ii) PELA ORDEM: só o pai de nome de manual (Clientes, Fornecedores), e só onde a extração trouxe `ordem`
    select c.id, c.n, c.vb, c.fator, row_number() over (order by c.ordem, c.id) as rn from c2 c where c.ordem is not null
  ), jan as materialized (
    select p.id as pai, f.id as filha, f.rn - p.rn as k, p.vb as vp, p.fator as fp,
           sum(f.vb) over w as sv, sum(f.fator) over w as sf, bool_and(f.fator is not null) over w as completo
      from seq p join seq f on f.rn > p.rn and f.rn <= p.rn + 6
     where p.n ~ c_nome_pai and p.fator is not null
    window w as (partition by p.id order by f.rn)
  ), jan_fecha as (
    select j.pai, min(j.k) as k from jan j where j.completo and abs(abs(j.vp) - abs(j.sv)) <= (j.fp + j.sf) / 2 group by j.pai
  ), absorvida as (   -- as linhas que o pai que FECHA (ou cobre) já contém: não somam de novo
    select m.filha as id from fam m where m.pai in (select e.pai from fam_estado e where e.estado in ('fecha', 'cobre_parte'))
    union
    select j.filha from jan j join jan_fecha jf on jf.pai = j.pai and j.k <= jf.k
    union   -- (iii) a MESMA conta com dois nomes de manual: "Clientes" e "Duplicatas a receber" com o valor idêntico (ao centavo) na mesma escala valem uma vez só
    select f.id from c2 p join c2 f on f.id <> p.id and p.n ~ '^([0-9][0-9. -]*)?(clientes|fornecedores)$' and f.n ~ '^([0-9][0-9. -]*)?duplicatas a receber$'
                                  and p.valor_num <> 0 and f.valor_num = p.valor_num and f.unidade is not distinct from p.unidade
  ), entra as (   -- o que de fato ENTRA na soma: sobrou das três absorções. Os avisos descrevem ISTO, não o que a leitura do pai supunha antes de a janela por ordem absorver
    select c.* from c2 c where c.id not in (select x.id from absorvida x)
  )
  select c.id, c.chave, c.valor_num, c.unidade, c.secao,
         nullif(concat_ws(' ',
           case
             -- as filhas do pai que as cobre em parte estão TODAS fora (absorvidas por ele): ele entrou sozinho
             when e.estado = 'cobre_parte' then format('"%s" entrou sozinho: %s com o nome dentro do dele soma(m) %s e cobre(m) só parte dos %s dele; se o resto é de linhas que a extração não trouxe, o pai vale e o valor está certo, e se o pai é uma conta própria, o valor está subestimado.',
                                            c.chave, case when e.nf = 1 then 'a única linha' else 'as ' || e.nf || ' linhas' end, fn_aging_reais(abs(e.sv)), fn_aging_reais(abs(e.vp)))
             -- o pai que as filhas excedem não é subtotal; só avisa se alguma das filhas ENTROU junto com ele (a janela por ordem ou outro pai pode tê-las absorvido)
             when e.estado = 'excede' and d.n > 0 then format('"%s" entrou na soma junto com %s com o nome dentro do dele (%s contra os %s dele): se o balanço conta %s dentro dele, o valor está em dobro.',
                                       c.chave, case when d.n = 1 then 'a linha' else 'as ' || d.n || ' linhas' end, fn_aging_reais(abs(d.sv)), fn_aging_reais(abs(e.vp)), case when d.n = 1 then 'essa linha' else 'essas linhas' end)
           end,
           (select format('"%s" e "%s" têm o mesmo valor (%s, na mesma escala): se são a mesma conta com dois nomes, a soma está em dobro.', c.chave, b.chave, c.valor_num)
              from entra b where b.id <> c.id and c.valor_num <> 0 and b.valor_num = c.valor_num
                          and b.unidade is not distinct from c.unidade and c.id < b.id order by b.id limit 1)), '') as aviso
    from entra c
    left join fam_estado e on e.pai = c.id
    left join lateral (select count(*) as n, sum(m.vb) as sv from fam m where m.pai = c.id and m.filha in (select y.id from entra y)) d on true
   order by c.ordem nulls last, c.id;
end $$;
comment on function fn_aging_linhas_do_balanco(uuid, text, text, text) is
  '0277 (sobre a 0274): as linhas do balanço (uma versão de documento) de um conceito, pelo rótulo normalizado, pelas colunas de entidade e período e pelo LADO do balanço (secao_canonica do conceito, ou nula; seção em texto com "estoque" fora). Pai e filhas pela ESTRUTURA: o pai cujo valor é a soma (em MÓDULO) das linhas com o nome dentro do dele (palavras pelos 7 primeiros caracteres; meia unidade da escala por linha), ou que as cobre, vale sozinho; o de nome de manual (Clientes, Fornecedores) também pela janela de ordem (até 6 linhas seguintes); as filhas com secao = nome do pai e o pai líquido (dedução filha) seguem a regra da 0274. Pai que as filhas EXCEDEM não é subtotal: entram com ele as filhas que a janela por ordem não absorveu, e a coluna aviso descreve só o que ENTROU; dois nomes com o mesmo valor também avisam. Devolve (id, chave, valor_num, unidade, secao, aviso). Deduções, variações de fluxo, longo prazo e partes relacionadas ficam de fora; Clientes/Fornecedores também deixam de fora Adiantamentos.';

-- ---------------------------------------------------------------------------
-- 3. A FUNÇÃO CENTRAL: a pendência e o estado vigente do aging são da DATA-BASE da carteira
-- ---------------------------------------------------------------------------
alter table pendencia add column data_base date;
alter table reconciliacao add column data_base date;
comment on column pendencia.data_base is
  '0277: a data-base da carteira (aging_importado.data_base) que originou a pendência, só nos tipos POR DATA-BASE (aging_ar_clientes, aging_ar_adiantamentos, aging_ap_fornecedores, aging_ap_adiantamentos). É o CRITÉRIO de fn_registrar_reconciliacao para achar a pendência desses tipos: duas datas-base nunca compartilham pendência. NULL em todas as demais (o período delas é o critério).';
comment on column reconciliacao.data_base is
  '0277: a data-base da carteira de aging da checagem (só nos quatro tipos aging_*); NULL nas demais. Junto com tipo, entidade e caso é a identidade do estado vigente da carteira: o período do documento (periodo_id) é só o do balanço lido e não a distingue.';

-- fn_registrar_reconciliacao: o corpo VIGENTE (0241) com a data-base dos quatro tipos do aging como critério. Para todo tipo que NÃO é do aging o corpo executa
-- exatamente o que executava (cada acréscimo é `v_por_data_base or ...` / `not v_por_data_base or ...` / uma coluna que fica NULL); a suíte inteira do run.sh
-- passa sem alterar a expectativa de nenhum outro teste. Mesma assinatura, mesmo retorno, mesma ACL.
create or replace function fn_registrar_reconciliacao(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tipo text, p_classe text, p_documento_id uuid, p_fonte_a jsonb, p_fonte_b jsonb, p_resultado text, p_divergencia_abs numeric, p_divergencia_pct numeric, p_materialidade jsonb, p_descricao text)
returns jsonb
language plpgsql
as $$
declare
  v_reconciliacao_id uuid;
  v_pendencia_id     uuid;
  v_motivo           text := 'reconciliacao:' || p_tipo;
  -- 0186: O CONTRATO — todo motivo que o achatamento reconhece como "a
  -- checagem não concluiu". `resultado` sai `precondicao_nao_satisfeita` para
  -- QUALQUER um destes; o valor ORIGINAL vai para `motivo_precondicao` (ver
  -- abaixo). Desde a 0188 os cinco têm emissor.
  v_motivos_precondicao text[] := array[
    'documento_ausente', 'precondicao_nao_satisfeita',
    'linha_nao_localizada', 'unidade_divergente', 'sem_periodo_par'
  ];
  -- CORRIGIDO após revisão independente (achado mais grave: um p_resultado
  -- fora do vocabulário virava 'a checagem concluiu' — precondicoes_ok =
  -- TRUE, afirmação positiva e FALSA, medido passando 'linha_nao_localizado',
  -- uma letra fora do contrato). Todo valor que QUALQUER `fn_reconciliar_*`
  -- hoje realmente emite (grep em todas as migrations) mais os três
  -- reservados do CONTRATO acima — nada além disso é reconhecido.
  v_vocabulario_resultado text[] := array['ok', 'divergente', 'divergencia', 'zona_cinzenta']
                                       || v_motivos_precondicao;
  -- 'documento_ausente' é um resultado NOSSO, para decidir a pendência; no log
  -- ele é gravado como pré-condição não satisfeita (é o que ele é).
  v_res_log          text := case when p_resultado = any(v_motivos_precondicao)
                                  then 'precondicao_nao_satisfeita' else p_resultado end;
  -- motivo_precondicao: o valor ORIGINAL, antes do achatamento acima — NULL
  -- quando a checagem concluiu (v_res_log não é 'precondicao_nao_satisfeita').
  -- Quando p_resultado já chega como 'precondicao_nao_satisfeita' (a função de
  -- checagem não detalhou o motivo), grava esse mesmo valor: é honesto — "sem
  -- motivo específico" é informação, não lacuna.
  v_motivo_precondicao text := case when v_res_log = 'precondicao_nao_satisfeita'
                                     then p_resultado else null end;
  -- 0188: O QUE A FUNÇÃO DEVOLVE em `resultado`. Os despachantes (0152)
  -- decidem se tentam o PRÓXIMO período por
  -- `exit when v_res->>'resultado' <> 'precondicao_nao_satisfeita'`. Até a
  -- 0187 isso era o p_resultado cru, e só dois valores de precondição
  -- existiam: 'documento_ausente' (para o laço — falta a contraparte, outro
  -- período não a cria) e o genérico (segue o laço). Os três motivos da 0188
  -- são refinamentos do GENÉRICO, então devolvem o genérico: o laço continua
  -- exatamente como antes. 'documento_ausente' continua saindo cru.
  v_res_retorno      text := case when p_resultado in ('linha_nao_localizada',
                                                       'unidade_divergente',
                                                       'sem_periodo_par')
                                  then 'precondicao_nao_satisfeita' else p_resultado end;
  -- 0127: a decisão passa para o corpo, porque agora ela depende do DIAL da
  -- classe — e o dial não se lê no declare sem esconder a regra.
  --
  -- 0186: ESTA LINHA NÃO MUDA. `documento_ausente` continua sendo o ÚNICO
  -- motivo de precondição que NÃO abre pendência — é cobrança do checklist do
  -- Kit Básico, não achado de revisão (0023, reafirmado pela 0127). Qualquer
  -- motivo novo do array acima que não seja 'documento_ausente' cai do lado
  -- de ABRE pendência por esta mesma linha, sem precisar tocá-la: documento
  -- presente e algo não localizado é sempre achado acionável, mesmo quando o
  -- motivo específico ainda não existe (default seguro).
  v_divergente       boolean := p_resultado not in ('ok', 'documento_ausente');
  v_abre_pendencia   boolean;
  v_estagio_dial     text;
  v_influencia       boolean;
  -- 0192: o período que a pendência JÁ CARREGA (pode ser diferente de
  -- p_periodo_id — a busca acima acha por compatibilidade, não igualdade), e
  -- se, NA MESMA TRANSAÇÃO, outra checagem do mesmo caso/tipo/entidade já
  -- CONCLUIU divergente para um período compatível com ele.
  v_pendencia_periodo_id    uuid;
  v_divergencia_concorrente boolean := false;
  -- 0241: a rodada é do período que a pendência carrega, ou da CHAVE dele (calculado depois da busca, no corpo).
  v_reescreve_descricao           boolean;
  -- 0241 (revisão): o ÚLTIMO registro da chave da pendência (periodo_chave_id = o período dela) existe e NÃO é divergente: A deixou de ser o motivo de a pendência estar aberta.
  v_chave_deixou_de_divergir boolean;
  -- 0192 (terceira correção da guarda): o período da CHAVE que originou esta chamada — o que o
  -- laço de fn_reconciliar_caso / fn_reconciliar_chaves_do_documento deixou em `oria.periodo_chave`.
  -- Chamada avulsa (sem laço, como a `fn_reconciliar_arvore` e os testes) é a sua própria chave.
  v_periodo_chave_id        uuid := coalesce(nullif(current_setting('oria.periodo_chave', true), '')::uuid,
                                             p_periodo_id);
  -- 0192 (achado 5): os tipos cuja checagem é POR DOCUMENTO — a pendência e o estado
  -- vigente são do documento, não da chave (caso, entidade, período). Hoje só `secao_fecha`
  -- (fn_reconciliar_arvore, 0133/0190). Tipo novo por documento entra AQUI e na sonda.
  c_tipos_por_documento constant text[] := array['secao_fecha'];
  v_por_documento boolean := p_tipo = any(c_tipos_por_documento);
  -- 0277: os tipos cujo estado vigente e cuja pendência são POR DATA-BASE da carteira (os quatro do aging): duas datas-base nunca compartilham pendência,
  -- descrição nem a guarda da 0192, nem quando são do mesmo ano (30/06 e 31/12) ou do mesmo balanço comparativo (multi 24,25). A data-base chega por
  -- `p_fonte_a.aging_id` (a importação que gerou a checagem; a assinatura não muda): é lida de aging_importado, nunca do que o chamador diz. Tipo novo
  -- por data-base entra AQUI e na sonda.
  c_tipos_por_data_base constant text[] := array['aging_ar_clientes', 'aging_ar_adiantamentos', 'aging_ap_fornecedores', 'aging_ap_adiantamentos'];
  v_por_data_base boolean := p_tipo = any(c_tipos_por_data_base);
  v_data_base     date;
begin
  -- 0186 (achado 1 da revisão): p_resultado FORA do vocabulário conhecido
  -- REPROVA ALTO — não vira 'a checagem concluiu' por acidente de digitação.
  -- `raise` em vez de `check constraint` na coluna `resultado`: a tabela tem
  -- histórico com valores legados (ok, divergente, divergencia, zona_cinzenta,
  -- precondicao_nao_satisfeita) e um check retroativo recusaria linha antiga
  -- ou faria o `alter table` falhar — o raise protege só a ESCRITA daqui pra
  -- frente, sem tocar no que já está gravado.
  if not (p_resultado = any(v_vocabulario_resultado)) then
    raise exception 'fn_registrar_reconciliacao: p_resultado=% fora do vocabulario conhecido (%)',
      p_resultado, array_to_string(v_vocabulario_resultado, ', ');
  end if;

  -- 0277: a data-base da carteira. Tipo do aging sem importação do MESMO mandato e entidade em `fonte_a.aging_id` reprova ALTO: sem ela a pendência não
  -- teria identidade e voltaria a ser achada por período (o ok de um ano apagando a divergência de outro).
  if v_por_data_base then
    select ai.data_base into v_data_base
      from aging_importado ai
     where ai.id = case when p_fonte_a ->> 'aging_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (p_fonte_a ->> 'aging_id')::uuid end
       and ai.caso_id = p_caso_id and ai.entidade_id is not distinct from p_entidade_id;
    if v_data_base is null then
      raise exception 'fn_registrar_reconciliacao: o tipo % é por data-base e p_fonte_a.aging_id (%) não é uma importação de aging deste mandato e desta entidade',
        p_tipo, coalesce(p_fonte_a ->> 'aging_id', 'ausente');
    end if;
  end if;

  -- 0127: O DIAL DA CLASSE DECIDE SE O ACHADO CHEGA À FILA DE ALGUÉM.
  --
  -- `reconciliacao_classe_bc` declarava N0 — "roda, registra a saída, mas NÃO
  -- influencia decisão" (Arquitetura do Sistema/1 Visão e Doutrina/01) — e abria pendência: as checagens B passam 'B'
  -- para cá e esta função nunca olhou a classe. Pendência entra na fila do painel
  -- e é contada na avaliação do Portão 2; isso é influenciar. O comportamento era
  -- N1, que é o teto dela — não era inseguro, era MAL DECLARADO.
  --
  -- Note que o registro em `reconciliacao` acontece SEMPRE, inclusive em N0: "roda
  -- e registra" é a primeira metade da definição de sombra, e é ela que permite
  -- medir um estágio antes de confiar nele.
  v_estagio_dial := case when upper(coalesce(p_classe, 'A')) = 'A'
                         then 'reconciliacao_classe_a'
                         else 'reconciliacao_classe_bc' end;
  v_influencia := fn_dial_influencia(v_estagio_dial);
  v_abre_pendencia := v_divergente and v_influencia;

  insert into reconciliacao
    (caso_id, entidade_id, periodo_id, tipo, classe, fonte_a, fonte_b,
     precondicoes_ok, resultado, motivo_precondicao, divergencia_abs, divergencia_pct, materialidade,
     documento_id, descricao, periodo_chave_id, data_base)
  values (
    p_caso_id, p_entidade_id, p_periodo_id, p_tipo, p_classe, p_fonte_a, p_fonte_b,
    v_res_log <> 'precondicao_nao_satisfeita', v_res_log, v_motivo_precondicao,
    p_divergencia_abs, p_divergencia_pct, p_materialidade,
    -- 0192 (achados 4/5/6): o documento que a checagem recebeu e o texto que ela deu, SEMPRE.
    p_documento_id, p_descricao,
    -- 0192 (guarda por CHAVE): o período da chave que originou a chamada, não o que o laço desceu.
    v_periodo_chave_id,
    -- 0277: a data-base da carteira (NULL em todo tipo que não é do aging).
    v_data_base
  )
  returning id into v_reconciliacao_id;

  select id, periodo_id into v_pendencia_id, v_pendencia_periodo_id from pendencia
  where caso_id = p_caso_id and motivo = v_motivo
    and coalesce(entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
      = coalesce(p_entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
    -- Período COMPATÍVEL, não igual: a mesma checagem chega por dois documentos
    -- com granularidade diferente (DRE "multi 24,25" × Faturamento "L24M") e sem
    -- isso o mesmo achado abriria duas pendências.
    -- 0277: o tipo do aging NÃO casa por período (o do documento não é a identidade da carteira: 31/12/2024 e 31/12/2025 de um balanço "multi 24,25", ou
    -- 30/06 e 31/12 de 2025, são carteiras diferentes) e sim pela DATA-BASE: a pendência e o estado vigente são da carteira.
    and (v_por_data_base
         or periodo_id is not distinct from p_periodo_id
         or fn_periodos_compativeis(periodo_id, p_periodo_id))
    and (not v_por_data_base or data_base is not distinct from v_data_base)
    -- 0192 (achado 5): tipo POR DOCUMENTO só casa a pendência do PRÓPRIO documento.
    and (not v_por_documento or documento_id is not distinct from p_documento_id)
    and estado <> 'resolvida'
  order by criada_em
  limit 1;

  -- 0241 (revisão, alto 1): o texto também passa à chave irmã quando a chave da pendência (A) deixou de divergir. A guarda 0192 segura a pendência aberta por causa de B, e sem isto o texto de A ("100 contra 90")
  -- ficaria congelado depois de A conferir, uma divergência que já não existe. Só com o último registro da chave EXISTINDO e não divergente: sem registro nenhum da chave (pendência aberta por um período que não é chave)
  -- não há evidência de que A parou de ser o motivo, e o texto fica.
  select r.resultado not in ('divergente', 'divergencia', 'zona_cinzenta') into v_chave_deixou_de_divergir
    from reconciliacao r
   where r.caso_id = p_caso_id and r.tipo = p_tipo
     and coalesce(r.entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
       = coalesce(p_entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
     and r.periodo_chave_id = v_pendencia_periodo_id
   order by r.criado_em desc, r.cmin::text::int desc
   limit 1;
  -- 0241 (revisão, médio): tipo POR DOCUMENTO casa a pendência pelo documento, e a árvore chama sem chave: se o documento muda para um período compatível o texto dele congelaria. O texto é do próprio documento.
  v_reescreve_descricao := v_por_documento
                           or v_por_data_base   -- 0277: o texto é da carteira daquela data-base, e só ela chega a esta pendência
                           or v_pendencia_periodo_id is not distinct from p_periodo_id
                           or v_pendencia_periodo_id is not distinct from v_periodo_chave_id
                           or coalesce(v_chave_deixou_de_divergir, false);

  -- 0192: O OK (OU A PRÉ-CONDIÇÃO) QUE MATAVA A DIVERGÊNCIA IRMÃ — ESTADO VIGENTE POR CHAVE.
  -- Duas checagens do mesmo tipo/entidade com períodos COMPATÍVEIS (Balanço "multi 24,25" ×
  -- "anual 12M25", {2024,2025} ∩ {2025} ≠ ∅) caem na MESMA pendência (busca acima, desde a
  -- 0023), e sem guarda SÓ A ORDEM de visita decidia se o `ok` de uma RESOLVIA a divergência da
  -- outra: dentro da rodada (medido em produção, 25/09/2026: v33/v35, `caixa_bp_fluxo`,
  -- 4.340.000 criada e resolvida no mesmo instante) e ENTRE rodadas.
  -- A guarda raciocina por CHAVE (o período do documento que o laço visita), não pelo período
  -- em que o resultado FICOU gravado: o laço desce a períodos compatíveis de outras entidades
  -- enquanto der pré-condição, e o resultado conclusivo fica num período sem documento da
  -- entidade (332 estados vigentes assim em produção, 30/09/2026). Duas versões que olhavam o
  -- período gravado (db6a258, 0202b8f) descartavam exatamente esse estado e resolviam.
  -- Bloqueia se:
  --   (a) alguma CHAVE VIVA (há documento do caso com `periodo_id` = a chave, da entidade quando
  --       ela não é nula) tem como ÚLTIMO registro (`periodo_chave_id` = a chave; `criado_em desc`,
  --       `cmin` desempata dentro da transação) um resultado divergente, gravado num período
  --       igual ou compatível com o da pendência. Chave sem documento (reclassificada, NULL) não
  --       prende; linha anterior à 0192 (sem `periodo_chave_id`) não bloqueia — teto declarado;
  --   (b) OU alguma linha DESTA transação (`criado_em = now()`), de outro período que o desta
  --       chamada, é divergente e compatível — a guarda original da mesma rodada, que vale
  --       mesmo sem documento na chave.
  -- Tipo POR DOCUMENTO (secao_fecha) não roda a guarda: o casamento por `documento_id`
  -- (acima) já isola a pendência do próprio documento.
  if v_pendencia_id is not null and not v_por_documento and not v_por_data_base then
    select exists (
      select 1 from (
        select distinct on (r.periodo_chave_id) r.periodo_id, r.resultado
        from reconciliacao r
        where r.caso_id = p_caso_id and r.tipo = p_tipo
          and coalesce(r.entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
            = coalesce(p_entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
          and r.periodo_chave_id is not null
          and exists (
            select 1 from documento d
            where d.caso_id = p_caso_id
              and (p_entidade_id is null or d.entidade_id = p_entidade_id)
              and d.periodo_id = r.periodo_chave_id)
        order by r.periodo_chave_id, r.criado_em desc, r.cmin::text::int desc
      ) ultimo_por_chave
      where ultimo_por_chave.resultado in ('divergente', 'divergencia', 'zona_cinzenta')
        and (ultimo_por_chave.periodo_id is not distinct from v_pendencia_periodo_id
             or fn_periodos_compativeis(ultimo_por_chave.periodo_id, v_pendencia_periodo_id))
    ) or exists (
      select 1 from (
        select distinct on (r.periodo_id) r.periodo_id, r.resultado
        from reconciliacao r
        where r.caso_id = p_caso_id and r.tipo = p_tipo
          and coalesce(r.entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
            = coalesce(p_entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
          and r.periodo_id is distinct from p_periodo_id
          and r.criado_em = now()
        order by r.periodo_id, r.criado_em desc, r.cmin::text::int desc
      ) ultimo_na_rodada
      where ultimo_na_rodada.resultado in ('divergente', 'divergencia', 'zona_cinzenta')
        and (ultimo_na_rodada.periodo_id is not distinct from v_pendencia_periodo_id
             or fn_periodos_compativeis(ultimo_na_rodada.periodo_id, v_pendencia_periodo_id))
    ) into v_divergencia_concorrente;
  end if;

  if v_abre_pendencia then
    if v_pendencia_id is null then
      insert into pendencia
        (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao,
         documento_id, entidade_id, periodo_id, motivo, data_base)
      values (
        p_caso_id, 'reconciliacao',
        case when v_res_log = 'precondicao_nao_satisfeita' then 'precondicao_nao_satisfeita'
             else 'divergencia_reconciliacao' end::pendencia_tipo,
        'importante', true, p_descricao, p_documento_id, p_entidade_id, p_periodo_id, v_motivo, v_data_base
      )
      returning id into v_pendencia_id;
    elsif v_res_log = 'precondicao_nao_satisfeita' and v_divergencia_concorrente then
      -- 0192: este achado é PRÉ-CONDIÇÃO, e o ESTADO VIGENTE de um período
      -- IRMÃO (chave viva, ou linha desta rodada) compatível é divergente — não troca a descrição
      -- da divergência pela de "não especificado"/checklist. A pendência
      -- continua com o texto e o `tipo` da divergência.
      null;
    else
      -- 0241: a descrição é do PERÍODO que a pendência carrega. A busca acima acha por compatibilidade, não por igualdade, então chega aqui
      -- a rodada de um período IRMÃO (anual 2024 x multi 24,26): reescrever dava à pendência de A o texto escrito para B (caso
      -- do Valtra, S126; 0 abertos em produção em 11/11/2026 pelo critério corrigido). Só reescreve a rodada do período da pendência OU da chave que o carrega (o laço desce de uma chave com
      -- pré-condição no seu período a um compatível e diverge ali: é o texto da MESMA chave, e a pendência da 0192 conta com isso); a chave irmã mantém a deduplicação e deixa o texto como está.
      if v_reescreve_descricao then
        update pendencia set descricao = p_descricao where id = v_pendencia_id;
      end if;
    end if;
  elsif v_divergente and not v_influencia then
    -- 0127: SOMBRA COM DIVERGÊNCIA PRESENTE — e este ramo existe para não mentir.
    --
    -- Sem ele, este caso cairia no `elsif` de baixo e a pendência aberta seria
    -- marcada "resolvida por sistema:reconciliacao". Mas o sintoma NÃO sumiu: o
    -- estágio foi silenciado. Resolver aqui escreveria na trilha que o problema
    -- acabou, quando o que acabou foi o direito daquele estágio de falar — e a
    -- trilha é append-only justamente para não permitir esse tipo de reescrita.
    --
    -- Então: registra em sombra, e deixa em paz a pendência que um humano já pode
    -- estar tratando.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:reconciliacao', 'reconciliacao_em_sombra',
              'reconciliacao:' || v_reconciliacao_id,
              jsonb_build_object('estagio', v_estagio_dial, 'classe', p_classe,
                                 'tipo', p_tipo, 'resultado', p_resultado,
                                 'divergencia_abs', p_divergencia_abs,
                                 'pendencia_preexistente', v_pendencia_id,
                                 'porque', 'estagio em N0: registra e nao abre pendencia (Arquitetura do Sistema/1 Visão e Doutrina/01). '
                                           'Pendencia anterior, se existe, NAO foi resolvida: o '
                                           'sintoma nao sumiu, o estagio foi silenciado.'));

  elsif v_pendencia_id is not null then
    if v_divergencia_concorrente then
      -- 0192: este achado CONCLUIU (ok/documento_ausente), mas o estado VIGENTE de
      -- uma chave IRMÃ (desta ou de rodada anterior) ainda é divergente num período compatível — não
      -- resolve. O `ok` de um período não apaga a divergência de outro.
      null;
    else
      -- Sumiu o sintoma (reextração corrigiu, ou a pendência era falsa e a regra
      -- nova não a emite mais): fecha. Não escreve número nenhum em base viva.
      update pendencia set estado = 'resolvida', resolvida_em = now(),
             resolvida_por = 'sistema:reconciliacao'
      where id = v_pendencia_id;
      v_pendencia_id := null;
    end if;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:reconciliacao', 'reconciliacao_' || p_tipo,
            'reconciliacao:' || v_reconciliacao_id,
            jsonb_build_object('resultado', p_resultado, 'divergencia_abs', p_divergencia_abs));

  return jsonb_build_object(
    'reconciliacao_id', v_reconciliacao_id, 'tipo', p_tipo,
    'resultado', v_res_retorno, 'motivo_precondicao', v_motivo_precondicao,
    'pendencia_id', v_pendencia_id
  );
end;
$$;

comment on function fn_registrar_reconciliacao(uuid, uuid, uuid, text, text, uuid, jsonb, jsonb, text, numeric, numeric, jsonb, text) is
  'Registro unificado de reconciliação (0023), motivo fino por pré-condição (0186/0188). 0192: a pendência só resolve (ou troca a descrição por uma de pré-condição) se nenhuma CHAVE viva (período de documento) tem como último registro uma divergência em período compatível, em qualquer rodada; tipo por documento (secao_fecha) casa a pendência e o estado por documento_id; grava documento_id, descricao e periodo_chave_id em toda linha de reconciliacao. 0241: a pendência é achada por período COMPATÍVEL (deduplica), mas a descrição só é reescrita pela rodada do período que a pendência carrega ou da chave dele: a chave irmã (período compatível) não troca o texto de A pelo de B. 0277: os quatro tipos do aging (aging_ar_clientes, aging_ar_adiantamentos, aging_ap_fornecedores, aging_ap_adiantamentos) são POR DATA-BASE: a pendência e o estado vigente são achados por (caso, motivo, entidade, data_base), a data-base vem de aging_importado por p_fonte_a.aging_id, o texto é sempre o da última rodada daquela carteira e a guarda da divergência irmã (0192) não se aplica (não há carteira irmã dentro de uma data-base). Os demais tipos são byte a byte os de antes.';

-- ---------------------------------------------------------------------------
-- 4. A CONCILIAÇÃO: A DATA-BASE DA CARTEIRA, O SINAL E O BALANÇO DO GRUPO
-- ---------------------------------------------------------------------------
create or replace function fn_reconciliar_aging(p_aging_id uuid) returns jsonb
language plpgsql set search_path = public, pg_temp as $$
declare
  a           aging_importado;
  v_ano       int;
  r           record;
  f           record;
  v_doc       uuid;
  v_periodo   uuid;
  v_ver       uuid;
  v_col_ent   text;
  v_col_per   text;
  v_n_docs    int := 0;
  v_sem_ent   boolean := false;
  v_notas     text[] := '{}';
  v_res       jsonb := '[]'::jsonb;
  v_prev_chave text := current_setting('oria.periodo_chave', true);
  v_cfg       record;
  v_valor_c   numeric;      -- o valor da carteira em centavos (absoluto)
  v_aging     numeric;      -- em reais
  v_lin       record;
  v_n_lin     int; v_balanco numeric; v_soma_fatores numeric; v_tol numeric; v_div numeric; v_sem_escala boolean;
  v_chaves    text[];
  v_resultado text; v_desc text; v_fa jsonb; v_fb jsonb; v_pct numeric;
  v_rej_l     numeric; v_rej_s numeric; v_ressalva text;
  v_tb        text; v_cabeca text;
  v_proprio   boolean := true;   -- 0277: o balanço escolhido é o da PRÓPRIA entidade?
  v_dono      text;              -- 0277: de quem é o documento, quando não é o da entidade
  v_tipo_doc  text;
  v_avisos    text[];            -- 0277: o que a busca das linhas desconfia e não resolveu (pai que não fecha, valor repetido, sinais opostos)
  v_n_pos     int; v_n_neg int;  -- 0277: quantas linhas que entraram na soma estão positivas e negativas (convenção de sinal, ver o cabeçalho)
begin
  select * into a from aging_importado where id = p_aging_id;
  if not found then return jsonb_build_object('executado', false, 'motivo', 'importação de aging não encontrada'); end if;
  if a.substituido_em is not null then
    return jsonb_build_object('executado', false, 'motivo', 'importação substituída por outra: só a vigente se concilia');
  end if;
  v_ano := extract(year from a.data_base)::int;
  v_tb  := case a.tipo_base when 'contas_a_receber' then 'contas a receber' else 'contas a pagar' end;
  v_cabeca := format('Carteira de %s em %s (arquivo "%s")', v_tb, to_char(a.data_base, 'DD/MM/YYYY'), a.arquivo_nome);

  -- O balanço que fecha NA data-base e que TEM a entidade do aging. 0277 (ALTO 3): a ordem é (1) o documento da PRÓPRIA entidade, (2) o de outra
  -- empresa do grupo cuja COLUNA fn_coluna_entidade resolve para esta entidade (o balanço combinado do grupo, que é a única fonte de uma controlada
  -- sem balanço próprio); dentro de cada grupo, BALANCO antes de COMBINADO antes de BALANCETE e o mais novo entre iguais. O próprio vem primeiro
  -- porque é a demonstração da empresa; a coluna de um combinado é uma leitura derivada (pode já trazer ajustes de consolidação). O documento de
  -- outra empresa só entra quando a coluna é achada de verdade (fn_coluna_entidade nulo = documento sem colunas de entidade, e E'\x01' = tem
  -- colunas e nenhuma é desta entidade): nunca por palpite, e a descrição diz de quem é o documento.
  for r in select d.id, d.tipo_taxonomia, d.periodo_id, coalesce(d.entidade_id = a.entidade_id, false) as proprio, e.razao_social as dono_nome
             from documento d
             left join entidade e on e.id = d.entidade_id
            cross join lateral (select fn_coluna_entidade(fn_versao_atual(d.id), a.entidade_id) as col) x
            where d.caso_id = a.caso_id and d.tipo_taxonomia in ('BALANCO', 'COMBINADO', 'BALANCETE')
              and (d.entidade_id = a.entidade_id or (x.col is not null and x.col <> E'\x01'))
            order by coalesce(d.entidade_id = a.entidade_id, false) desc,
                     array_position(array['BALANCO', 'COMBINADO', 'BALANCETE'], d.tipo_taxonomia), d.criado_em desc, d.id loop
    v_n_docs := v_n_docs + 1;
    select * into f from fn_balanco_fecha_em(r.id, v_ano);
    if f.fecha_em is distinct from a.data_base then
      v_notas := v_notas || format('%s%s %s', r.tipo_taxonomia, case when r.proprio then '' else ' de ' || coalesce(r.dono_nome, 'outra empresa') end,
        coalesce('fecha em ' || to_char(f.fecha_em, 'DD/MM/YYYY') || ', não em ' || to_char(a.data_base, 'DD/MM/YYYY'), f.observacao));
      continue;
    end if;
    v_ver := fn_versao_atual(r.id);
    v_col_ent := fn_coluna_entidade(v_ver, a.entidade_id);
    if v_col_ent = E'\x01' then
      v_sem_ent := true; v_notas := v_notas || format('%s fecha em %s mas não tem coluna desta entidade', r.tipo_taxonomia, to_char(a.data_base, 'DD/MM/YYYY'));
      continue;
    end if;
    v_doc := r.id; v_periodo := r.periodo_id; v_proprio := r.proprio; v_dono := r.dono_nome; v_tipo_doc := r.tipo_taxonomia;
    exit;
  end loop;
  if v_doc is not null then
    v_col_per := fn_coluna_periodo_do_ano(v_ver, v_ano);
    if v_col_per = E'\x01' then v_col_per := null; end if;
  end if;

  -- 0277 (ALTO 1): o período que a reconciliação carrega é o do DOCUMENTO (como na 0274: é o que a tela mostra), e a IDENTIDADE da pendência e do estado
  -- vigente é a DATA-BASE da carteira, que fn_registrar_reconciliacao lê de `fonte_a.aging_id` (v_fa, abaixo). Nenhum período é criado aqui: a primeira
  -- versão da 0277 fabricava ('data-base', 'AAAA-MM-DD') e isso mudava as checagens clássicas do mandato (o período novo entra no laço de
  -- fn_periodos_compativeis_array: um ativo_passivo_pl passou a `ok` num período que nenhum documento trouxe) e deixava o mesmo ano com datas-base
  -- diferentes na mesma pendência.
  if v_doc is not null and not v_proprio then
    v_cabeca := v_cabeca || format(' [balanço lido: %s de %s, na coluna "%s", outra empresa do grupo]', v_tipo_doc, coalesce(v_dono, 'empresa sem nome'), coalesce(v_col_ent, 'sem coluna de entidade'));
  end if;

  -- A chave do período para a guarda de fn_registrar_reconciliacao (a do balanço escolhido; sem balanço, nenhuma). Como na 0274. Os tipos do aging não passam
  -- pela guarda da 0192 (a pendência deles é por data-base): a chave só preenche reconciliacao.periodo_chave_id.
  perform set_config('oria.periodo_chave', coalesce(v_periodo::text, ''), true);

  -- O que a leitura deixou fora do aging (para a descrição de uma divergência).
  select coalesce(sum(fn_aging_contagem(m.value -> 'linhas')), 0), coalesce(sum(fn_aging_centavos(m.value -> 'saldo')), 0) into v_rej_l, v_rej_s
    from jsonb_each(case when jsonb_typeof(a.aplicador -> 'motivos') = 'object' then a.aplicador -> 'motivos' else '{}'::jsonb end) m;
  v_ressalva := case when v_rej_l > 0 then format(' O aplicador deixou fora do aging %s linhas rejeitadas, com saldo de %s: pode explicar a diferença.', v_rej_l, fn_aging_reais(v_rej_s / 100)) else '' end;

  for v_cfg in select * from (values
      ('aging_ar_clientes',        'contas_a_receber', 'clientes',                    'Clientes',                      'positivos', 'saldo positivo (carteira a receber)'),
      ('aging_ar_adiantamentos',   'contas_a_receber', 'adiantamentos_de_clientes',   'Adiantamentos de clientes',     'negativos', 'saldo negativo (adiantamentos e créditos de clientes)'),
      ('aging_ap_fornecedores',    'contas_a_pagar',   'fornecedores',                'Fornecedores',                  'positivos', 'saldo positivo (carteira a pagar)'),
      ('aging_ap_adiantamentos',   'contas_a_pagar',   'adiantamentos_a_fornecedores','Adiantamentos a fornecedores',  'negativos', 'saldo negativo (adiantamentos e créditos a fornecedores)')
    ) as t(tipo, base, conceito, rotulo, lado, rotulo_aging) where t.base = a.tipo_base loop
    v_valor_c := abs(fn_aging_centavos(a.resumo -> v_cfg.lado -> 'saldo'));
    v_aging := v_valor_c / 100;
    v_fa := jsonb_build_object('chave', format('aging %s %s (%s)', a.tipo_base, a.data_base, v_cfg.lado), 'valor', v_aging, 'unidade', 'unidade',
                               'centavos', v_valor_c::text, 'aging_id', a.id);
    v_fb := null; v_pct := null; v_div := null;

    if v_doc is null then
      if v_n_docs = 0 then
        v_res := v_res || jsonb_build_array(fn_registrar_reconciliacao(a.caso_id, a.entidade_id, null, v_cfg.tipo, 'A', null, v_fa, null,
          'documento_ausente', null, null, jsonb_build_object('criterio', 'meia_unidade_da_escala'),
          v_cabeca || format(': sem par para reconciliar, o balanço desta entidade não foi entregue, nem como coluna de um balanço de outra empresa do grupo (%s de %s, sem conta do balanço para conferir).', v_cfg.rotulo_aging, fn_aging_reais(v_aging))));
      elsif v_valor_c = 0 then
        -- 0277 (B2): a carteira não tem saldo deste lado, e o balanço não fecha na data-base: nada a conciliar (como a carteira zero com o balanço sem a conta,
        -- abaixo). Abrir pendência "sem par" para um lado que está vazio mandaria o analista atrás de um balanço para conferir zero.
        v_res := v_res || jsonb_build_array(fn_registrar_reconciliacao(a.caso_id, a.entidade_id, null, v_cfg.tipo, 'A', null, v_fa, null,
          'ok', 0, null, jsonb_build_object('criterio', 'meia_unidade_da_escala'),
          v_cabeca || format(': nada a conciliar, a carteira não tem %s. O balanço desta entidade não fecha na data-base e nada foi comparado: o ok vale só porque não há saldo na carteira a conferir. Balanços vistos: %s.', v_cfg.rotulo_aging, array_to_string(v_notas, '; '))));
      else
        v_resultado := case when v_sem_ent and not exists (select 1 from unnest(v_notas) n where n not like '%não tem coluna desta entidade') then 'precondicao_nao_satisfeita' else 'sem_periodo_par' end;
        v_res := v_res || jsonb_build_array(fn_registrar_reconciliacao(a.caso_id, a.entidade_id, null, v_cfg.tipo, 'A', null, v_fa, null,
          v_resultado, null, null, jsonb_build_object('criterio', 'meia_unidade_da_escala'),
          fn_motivo_precondicao_prefixo(v_resultado) || v_cabeca
            || format(': o balanço desta entidade não fecha na data-base (%s não se compara com outra data). Balanços vistos: %s.', v_cfg.rotulo_aging, array_to_string(v_notas, '; '))));
      end if;
      continue;
    end if;

    select count(*), coalesce(sum(l.valor_num * fn_fator_escala(l.unidade)), 0), coalesce(sum(fn_fator_escala(l.unidade)), 0),
           coalesce(bool_or(fn_fator_escala(l.unidade) is null), false), array_agg(format('"%s" = %s %s', l.chave, l.valor_num, coalesce(l.unidade, 'sem escala')) order by l.chave),
           array_remove(array_agg(distinct l.aviso), null), count(*) filter (where l.valor_num > 0), count(*) filter (where l.valor_num < 0)
      into v_n_lin, v_balanco, v_soma_fatores, v_sem_escala, v_chaves, v_avisos, v_n_pos, v_n_neg
      from fn_aging_linhas_do_balanco(v_ver, v_cfg.conceito, v_col_ent, v_col_per) l;
    -- 0277 (A3): CONVENÇÃO DE SINAL. O aging entra em módulo (v_aging = abs), e o balanço também: o sinal de Clientes/Fornecedores/Adiantamentos no balanço é
    -- convenção de APRESENTAÇÃO (passivo e crédito impressos negativos: balancete com colunas Crédito/Saldo Atual, "FORNECEDORES" -8.111.470), não um saldo
    -- oposto. Medido em produção (12/11/2026, leitura): dos 2.027 grupos (versão × coluna × conceito) com linha das quatro contas, 13 têm linha negativa e
    -- NENHUM mistura sinais (10 de Fornecedores, 1 de Clientes, 1 de Adiantamentos de clientes, 1 de Adiantamentos a fornecedores): quando é negativo, é
    -- negativo o grupo inteiro. Por isso compara-se o MÓDULO da soma com sinal. Se um grupo MISTURAR sinais (nunca visto), a soma com sinal é a que entra e
    -- o texto diz, porque duas linhas de sinais opostos podem ser duas contas diferentes e a diferença não se explica sozinha.
    if v_n_pos > 0 and v_n_neg > 0 then
      v_avisos := coalesce(v_avisos, '{}'::text[]) || format('as linhas que entraram na soma têm sinais opostos (%s positivas, %s negativas): somaram com o sinal e o módulo do resultado foi o comparado; se são contas diferentes, a diferença pode não ser real.', v_n_pos, v_n_neg);
    end if;
    v_fb := case when v_n_lin = 0 then null else jsonb_build_object('chaves', to_jsonb(v_chaves), 'valor', abs(v_balanco), 'valor_com_sinal', v_balanco, 'unidade', 'unidade', 'documento_versao_id', v_ver,
                                                          'documento_id', v_doc, 'coluna_entidade', v_col_ent, 'documento_de_outra_empresa', not v_proprio,
                                                          'avisos', to_jsonb(coalesce(v_avisos, '{}'::text[]))) end;

    if v_n_lin = 0 then
      if v_valor_c = 0 then
        v_res := v_res || jsonb_build_array(fn_registrar_reconciliacao(a.caso_id, a.entidade_id, v_periodo, v_cfg.tipo, 'A', v_doc, v_fa, null,
          'ok', 0, null, jsonb_build_object('criterio', 'meia_unidade_da_escala'),
          v_cabeca || format(': nada a conciliar, a carteira não tem %s e o balanço não traz a conta %s.', v_cfg.rotulo_aging, v_cfg.rotulo)));
      else
        v_res := v_res || jsonb_build_array(fn_registrar_reconciliacao(a.caso_id, a.entidade_id, v_periodo, v_cfg.tipo, 'A', v_doc, v_fa, null,
          'linha_nao_localizada', v_aging, null, jsonb_build_object('criterio', 'meia_unidade_da_escala'),
          fn_motivo_precondicao_prefixo('linha_nao_localizada') || v_cabeca
            || format(': %s de %s e o balanço não traz a conta %s para conferir: a diferença é o valor inteiro, %s.%s',
                      v_cfg.rotulo_aging, fn_aging_reais(v_aging), v_cfg.rotulo, fn_aging_reais(v_aging), v_ressalva)));
      end if;
      continue;
    end if;

    if v_sem_escala then
      v_res := v_res || jsonb_build_array(fn_registrar_reconciliacao(a.caso_id, a.entidade_id, v_periodo, v_cfg.tipo, 'A', v_doc, v_fa, v_fb,
        'unidade_divergente', null, null, jsonb_build_object('criterio', 'meia_unidade_da_escala'),
        fn_motivo_precondicao_prefixo('unidade_divergente') || v_cabeca
          || format(': a conta %s do balanço não tem escala reconhecida (esperado: unidade, milhar ou milhão), e o aging está em reais: comparar arriscaria um falso "confere".', v_cfg.rotulo)));
      continue;
    end if;

    v_div := abs(v_aging - abs(v_balanco));
    -- A tolerância É o arredondamento do número impresso: meia unidade da escala de cada linha usada (R$ 500 em R$ mil), nunca um percentual.
    v_tol := v_soma_fatores / 2;
    v_pct := case when v_aging <> 0 then v_div / v_aging end;
    v_resultado := case when v_div <= v_tol then 'ok' else 'divergente' end;
    v_desc := v_cabeca || format(': %s de %s contra %s do balanço de %s%s (%s). ', v_cfg.rotulo_aging, fn_aging_reais(v_aging), v_cfg.rotulo,
                                 fn_aging_reais(abs(v_balanco)), case when v_balanco < 0 then ', impresso com sinal negativo (convenção de apresentação: comparado em módulo)' else '' end,
                                 array_to_string(v_chaves, '; '))
      || case when v_resultado = 'ok'
              then format('Conferido, diferença de %s (tolerância de %s: o arredondamento da escala do balanço).', fn_aging_reais(v_div), fn_aging_reais(v_tol))
              else format('Diferença de %s, acima de %s (o arredondamento da escala do balanço).%s', fn_aging_reais(v_div), fn_aging_reais(v_tol), v_ressalva) end
      -- 0277: o que a leitura das linhas do balanço desconfiou e não resolveu (pai que não fecha com as filhas, valor repetido) vai no texto, ok ou divergente.
      || coalesce(' Atenção na leitura do balanço: ' || nullif(array_to_string(v_avisos, ' '), ''), '');
    v_res := v_res || jsonb_build_array(fn_registrar_reconciliacao(a.caso_id, a.entidade_id, v_periodo, v_cfg.tipo, 'A', v_doc, v_fa, v_fb,
      v_resultado, v_div, v_pct, jsonb_build_object('tolerancia_abs', v_tol, 'criterio', 'meia_unidade_da_escala'), v_desc));
  end loop;

  perform set_config('oria.periodo_chave', coalesce(v_prev_chave, ''), true);
  return jsonb_build_object('executado', true, 'aging_id', p_aging_id, 'checagens', v_res);
end $$;
comment on function fn_reconciliar_aging(uuid) is
  '0274 (reemitida pela 0277): concilia UMA importação vigente de aging com o balanço extraído que fecha na data-base e TEM a entidade: o documento da própria entidade, ou a coluna desta entidade de um balanço de outra empresa do grupo (própria primeiro). Saldos positivos × Clientes (a receber) ou Fornecedores (a pagar), negativos × Adiantamentos de clientes/a fornecedores. Tolerância = meia unidade da escala do balanço (nunca percentual). Tipos aging_ar_clientes, aging_ar_adiantamentos, aging_ap_fornecedores, aging_ap_adiantamentos, classe A, por fn_registrar_reconciliacao com descrição sempre; divergência zero é gravada como conferida (ok, 0). A pendência e o estado vigente são da DATA-BASE da carteira (fn_registrar_reconciliacao, por fonte_a.aging_id; nenhum período é criado): datas-base diferentes, do mesmo ano ou não, nunca dividem pendência. O aging (em módulo) é comparado com o MÓDULO da soma das linhas do balanço (o sinal é convenção de apresentação); sinais opostos entre as linhas que entraram vão na descrição. Sem balanço = documento_ausente (sem pendência); balanço de outra data = sem_periodo_par, ou ok (nada a conciliar) se o lado da carteira é zero. As desconfianças da leitura das linhas (pai que não fecha, valor repetido) vão na descrição. Só service_role e as funções definer chamam.';

-- ---------------------------------------------------------------------------
-- 5. A IMPORTAÇÃO, AGORA COM O RESUMO AMARRADO AO APLICADOR
-- ---------------------------------------------------------------------------
create or replace function fn_aging_importar(p_caso uuid, p_entidade uuid, p_tipo_base text, p_data_base date, p_resumo jsonb, p_leitura jsonb,
                                  p_aplicador jsonb, p_arquivo jsonb, p_mapeamento uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_erros text[];
  v_id    uuid := gen_random_uuid();
  v_antigo uuid;
  v_map_tipo text;
  v_conc  jsonb;
begin
  if p_caso is null or not fn_pode_escrever_caso(p_caso) then
    raise exception 'Importar aging exige ser Sócio ou Analista alocado neste mandato' using errcode = '42501';
  end if;
  if p_tipo_base is null or p_tipo_base not in ('contas_a_receber', 'contas_a_pagar') then
    raise exception 'tipo_base "%" não existe (contas_a_receber ou contas_a_pagar)', p_tipo_base using errcode = '22023';
  end if;
  if not exists (select 1 from caso where id = p_caso) then
    raise exception 'O mandato % não existe', p_caso using errcode = 'P0002';
  end if;
  if p_data_base is null then
    raise exception 'O aging sem data-base não é uma posição: a data-base é obrigatória' using errcode = '22023';
  end if;
  if p_entidade is null or not exists (select 1 from entidade where id = p_entidade and caso_id = p_caso) then
    raise exception 'A entidade % não é deste mandato: o aging tem de dizer de qual empresa do grupo é a carteira', p_entidade using errcode = '22023';
  end if;

  v_erros := fn_aging_resumo_erros(p_resumo, p_data_base);
  -- 0277: o resumo tem de ser o do arquivo que o aplicador leu (mesmos títulos, mesmos saldos); a 0274 validava cada um por si e nada os amarrava.
  v_erros := v_erros || fn_aging_aplicador_erros(p_resumo, p_aplicador);
  if jsonb_typeof(p_leitura) is distinct from 'object' or jsonb_typeof(p_aplicador) is distinct from 'object' then
    v_erros := v_erros || 'o resumo da leitura e o do aplicador têm de ser objetos'::text;
  end if;
  if jsonb_typeof(p_arquivo) is distinct from 'object'
     or coalesce(p_arquivo ->> 'nome', '') = ''
     or coalesce(p_arquivo ->> 'sha256', '') !~ '^[0-9a-f]{64}$'
     or coalesce(p_arquivo ->> 'bytes', '') !~ '^[1-9][0-9]{0,15}$'
     or coalesce(p_arquivo ->> 'formato', '') not in ('csv', 'xlsx') then
    v_erros := v_erros || 'o arquivo precisa de nome, sha256 (64 hex minúsculos), bytes > 0 e formato csv ou xlsx'::text;
  elsif jsonb_typeof(p_leitura) = 'object' then
    if p_leitura ->> 'parcial' = 'true' then
      v_erros := v_erros || 'a leitura foi PARCIAL (interrompida depois da amostra): contagens e sha256 são só do trecho lido'::text;
    elsif p_leitura ->> 'sha256' is distinct from p_arquivo ->> 'sha256' then
      v_erros := v_erros || 'o sha256 da leitura é diferente do sha256 do arquivo'::text;
    end if;
  end if;
  select tipo_base into v_map_tipo from mapeamento_de_colunas where id = p_mapeamento;
  if v_map_tipo is null then
    v_erros := v_erros || 'mapeamento inexistente: arquivo sem mapeamento confirmado não vira dado'::text;
  elsif v_map_tipo <> p_tipo_base then
    v_erros := v_erros || format('o mapeamento é de %s e a importação é de %s', v_map_tipo, p_tipo_base);
  end if;
  if cardinality(v_erros) > 0 then
    raise exception 'Aging recusado: %', array_to_string(v_erros, '; ') using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_caso::text || ':' || p_entidade::text || ':' || p_tipo_base || ':' || p_data_base::text, 0));
  update aging_importado set substituido_em = now(), substituido_por = v_id
   where caso_id = p_caso and entidade_id = p_entidade and tipo_base = p_tipo_base and data_base = p_data_base and substituido_em is null
  returning id into v_antigo;
  insert into aging_importado (id, caso_id, entidade_id, tipo_base, data_base, resumo, leitura, aplicador,
                               arquivo_nome, arquivo_sha256, arquivo_bytes, arquivo_formato, mapeamento_id, importado_por)
  values (v_id, p_caso, p_entidade, p_tipo_base, p_data_base, p_resumo, p_leitura, p_aplicador,
          p_arquivo ->> 'nome', p_arquivo ->> 'sha256', (p_arquivo ->> 'bytes')::bigint, p_arquivo ->> 'formato', p_mapeamento, auth.uid());

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
  values ('usuario:' || auth.uid(), 'aging_importado', 'caso:' || p_caso,
          case when v_antigo is null then null else jsonb_build_object('substituido', v_antigo) end,
          jsonb_build_object('id', v_id, 'entidade_id', p_entidade, 'tipo_base', p_tipo_base, 'data_base', p_data_base,
                             'arquivo_sha256', p_arquivo ->> 'sha256'));

  v_conc := fn_reconciliar_aging(v_id);
  return jsonb_build_object('id', v_id, 'substitui', v_antigo, 'conciliacao', v_conc -> 'checagens');
end $$;
comment on function fn_aging_importar(uuid, uuid, text, date, jsonb, jsonb, jsonb, jsonb, uuid) is
  '0274 (reemitida pela 0277): guarda o resumo do aging de uma importação, por mandato e entidade, e o concilia com o balanço extraído. Só quem escreve o mandato (fn_pode_escrever_caso: Sócio, Analista alocado); os demais, o anônimo e a conexão de serviço recebem 42501. Recusa (22023, com todos os motivos) resumo que não fecha consigo mesmo, resumo que não se amarra ao aplicador (0277: títulos e saldos), entidade de outro mandato, leitura parcial, sha256 divergente, arquivo inválido e mapeamento inexistente ou de outro tipo_base. Reimportar a mesma (entidade, tipo_base, data_base) substitui a vigente SEM apagar. Grava aging_importado em evento_auditoria (caso:<id>). Devolve {id, substitui, conciliacao}.';

do $$
declare f text;
begin
  foreach f in array array['fn_aging_aplicador_erros(jsonb, jsonb)', 'fn_aging_linhas_do_balanco(uuid, text, text, text)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
    if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
      execute format('grant execute on function %s to supabase_read_only_user', f);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 6. A SONDA. Marcadores em CÓDIGO, nunca de comentário (pg_get_functiondef traz os comentários do corpo).
-- ---------------------------------------------------------------------------
create view instalacao_sonda_aging_aplicador_check as
  select k.conname::text as nome
    from pg_constraint k
   where k.conrelid = 'public.aging_importado'::regclass and k.contype = 'c' and k.convalidated
     and k.conname = 'aging_resumo_e_aplicador' and pg_get_constraintdef(k.oid) like '%fn_aging_aplicador_erros(%';
comment on view instalacao_sonda_aging_aplicador_check is
  'Sonda da 0277: uma linha = a CHECK aging_resumo_e_aplicador existe, validada, e chama fn_aging_aplicador_erros. Zero linhas: o service_role grava um resumo que não é o do arquivo lido.';
grant select on instalacao_sonda_aging_aplicador_check to authenticated, service_role;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    execute 'grant select on instalacao_sonda_aging_aplicador_check to supabase_read_only_user';
  end if;
end $$;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('aging_aplicador_funcao', '0277', 'funcao', 'fn_aging_aplicador_erros', null, null,
   'O validador que amarra o resumo do aging ao resumo do aplicador. Ausente = a 0277 não foi aplicada: o resumo pode ser de outro arquivo que o lido.',
   'importante', 1354),
  ('aging_importar_amarra_aplicador', '0277', 'corpo', 'fn_aging_importar', 'fn_aging_aplicador_erros(', null,
   'A importação recusa o resumo que não se amarra ao aplicador. Corpo sem isto = a carteira de um arquivo é guardada com o resumo de outro e concilia com o balanço como se fosse a dele.',
   'importante', 1355),
  ('aging_aplicador_check', '0277', 'comportamento', 'instalacao_sonda_aging_aplicador_check', null, 1,
   'A CHECK da tabela que amarra o resumo ao aplicador. Zero linhas = o service_role grava resumo que não é o do arquivo lido.',
   'importante', 1356),
  ('aging_registrar_por_data_base', '0277', 'corpo', 'fn_registrar_reconciliacao', 'data_base is not distinct from v_data_base', null,
   'A pendência e o estado vigente do aging são achados pela DATA-BASE da carteira, não pelo período do documento. Corpo sem isto = balanço comparativo (multi 24,25) com carteiras de 2024 e 2025, ou 30/06 e 31/12 do mesmo ano: o ok de uma carteira apaga a divergência da outra.',
   'bloqueante', 1357),
  ('aging_conciliar_balanco_do_grupo', '0277', 'corpo', 'fn_reconciliar_aging', 'fn_coluna_entidade(fn_versao_atual(d.id), a.entidade_id)', null,
   'A conciliação aceita o balanço de outra empresa do grupo cuja coluna é a da entidade. Corpo sem isto = a controlada que só existe como coluna do combinado vira documento_ausente (sem pendência): a carteira nunca é conferida.',
   'importante', 1358),
  ('aging_linhas_pai_que_fecha', '0277', 'corpo', 'fn_aging_linhas_do_balanco', 'abs(abs(p.vb) - abs(s.sv)) <= (p.fator + s.sf) / 2', null,
   'O pai (Fornecedores) que é a soma das filhas vale sozinho. Corpo sem isto = pai e filhas somam em dobro quando têm a mesma seção ou seção nula (a forma de produção), e a carteira correta aparece como divergente.',
   'bloqueante', 1359),
  ('aging_linhas_lado_do_balanco', '0277', 'corpo', 'fn_aging_linhas_do_balanco', 'ce.secao_canonica = v_sc', null,
   'A linha tem de estar do lado do balanço em que o conceito mora. Corpo sem isto = a mercadoria em garantia "(FORNECEDOR)" da seção ESTOQUE entra como Fornecedores.',
   'importante', 1360),
  ('aging_pendencia_data_base_coluna', '0277', 'coluna', 'pendencia.data_base', null, null,
   'A data-base da carteira que originou a pendência do aging. Ausente = a 0277 não foi aplicada por inteiro: a função central não acha a pendência por data-base.',
   'bloqueante', 1361),
  ('aging_reconciliacao_data_base_coluna', '0277', 'coluna', 'reconciliacao.data_base', null, null,
   'A data-base da carteira de cada checagem do aging (a identidade do estado vigente). Ausente = a 0277 não foi aplicada por inteiro.',
   'bloqueante', 1362),
  ('aging_conciliar_compara_em_modulo', '0277', 'corpo', 'fn_reconciliar_aging', 'abs(v_aging - abs(v_balanco))', null,
   'O aging (em módulo) é comparado com o MÓDULO da soma das linhas do balanço: passivo e crédito impressos negativos são convenção de apresentação. Corpo sem isto = Fornecedores de -5.621 contra uma carteira de 5.621 dá divergente (produção: 13 grupos só-negativos, 0 mistos).',
   'importante', 1363)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0277', revisado_em = current_date,
       observacao = 'A 0277 corrige os 3 ALTOS da conciliação do aging da 0274 (a pendência por data-base na função central fn_registrar_reconciliacao, o pai de Fornecedores/Clientes que somava com as filhas, o balanço do grupo como fonte da entidade), a convenção de sinal e 3 médios (o lado do balanço, o resumo amarrado ao aplicador). Reemite fn_registrar_reconciliacao, fn_reconciliar_aging e fn_aging_importar, recria fn_aging_linhas_do_balanco (ganha a coluna aviso), cria fn_aging_aplicador_erros e as colunas data_base de pendencia e reconciliacao. 10 requisitos novos (ordem 1354-1363).'
 where id = true;

commit;
