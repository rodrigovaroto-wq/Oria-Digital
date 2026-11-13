-- 0243 — A LINHA QUE NÃO TINHA IDENTIDADE: `fato_financeiro` acima de `campo_extraido` (P27, Fase 3, etapa 3.2) — uma VIEW security_invoker sobre `fn_fato_resolver`: o fato (conta = a SEÇÃO da linha; entidade e período pela coluna quando uma função do banco decide sem ambiguidade) é CALCULADO na leitura, não gravado. A única coisa que a migration escreve é a pendência `conta_canonica_incerta` da extração nova.
-- (Cria 1 view, fato_financeiro, e as funções fn_tipo_gera_fato, fn_linha_vira_fato, fn_fato_resolver, fn_fato_pode_escrever, fn_fato_ator, fn_fato_pendencia_da_versao, fn_fato_pendencia_da_extracao e fn_fato_sonda_recentes; 1 gatilho, em evento_auditoria; 1 rótulo de pendencia_tipo (conta_canonica_incerta); 6 views da sonda e 20 requisitos novos (ordem 1105-1124).
--  NÃO reemite fn_registrar_campos_extraidos (a 0270, aplicada em produção, a reemitiu para gravar o `ln`) nem fn_fundir_entidade (volta a ser a da migration anterior). Sem tabela, sem backfill, sem recálculo, sem FK. Idempotente: pode ser reaplicada. Aplicação: 0,065 s medido reaplicando-a sobre um banco com 82.634 linhas de campo_extraido.)
--
-- O DEFEITO. A identidade de uma linha financeira era `(secao_canonica, rótulo)` em `campo_extraido`: texto livre, sem FK, sem entidade nem período PRÓPRIOS (a linha tem `entidade_coluna` e `periodo_coluna` em texto; o documento tem UM `entidade_id`/`periodo_id`). Toda reconciliação refaz esse casamento por rótulo (a família de bugs que a F4 existe para extinguir) e nada diz,
-- por linha, "a conta é esta, a entidade é esta, o período é este — e foi a IA quem disse, ou foi um palpite nosso". O roadmap (ARQUITETURA_ALVO_E_ROADMAP, F4) define `fato_financeiro` ACIMA de `campo_extraido`, que NÃO muda (ADR 01: a evidência é imutável; o canônico nasce acima); o plano pede "0 fato sem identidade no corpus; heurística sempre com pendência".
--
-- O QUE JÁ EXISTIA E FOI REUSADO (degrau 2 da escada, nada reescrito): a heurística de seção é a que o banco JÁ tem — `fn_secao_canonica_da_secao_bruta` (0203) e `fn_herdar_secao_pela_arvore` (0204), que gravam `campo_extraido.secao_canonica_inferida = true`: essa flag é o método `heuristica`. O papel da linha é `fn_papel_linha`; a versão vigente, `fn_versao_atual`; a entidade, o vocabulário de
-- `fn_coluna_entidade` (0023/0030, com `fn_mesma_entidade`); o período, `fn_periodo_canonico` casado como `fn_upsert_periodo` casa (forma canônica, o de menor referência no empate), `fn_anos_periodo`, `fn_coluna_e_saldo`, `fn_coluna_e_abertura` e `fn_periodo_e_parcial` (0199/0201). Não há resolução de ENTIDADE_COLUNA -> entidade nem de PERIODO_COLUNA -> período em lugar nenhum (as reconciliações vão no sentido contrário): o casamento é escrito aqui, uma vez.
--
-- AS DECISÕES DO DONO (11/11 e 12/11/2026, não reabertas): (1) a identidade é o nó de SEÇÃO de `conta_canonica` (0242), sem conta-folha; (2) só linhas de documento de DEMONSTRAÇÃO e de papel `conta` viram fato (subtotal é a P28; Estoque, Razão, Aging, Mapa de Dívida continuam só evidência); (3) pendência UMA por documento-versão, só para extração DAQUI EM DIANTE; (4) `fato_financeiro` é VIEW sobre o resolver, e "teste tudo antes de qualquer aplicação prática".
--
-- POR QUE UMA VIEW (a trajetória de 5 revisões independentes, 12/11/2026, PR #296). A primeira versão era uma TABELA mantida por gatilhos e funções de materialização. Cada revisão achou uma família nova de "o fato gravado não converge para o estado atual": 1ª (2 altos + 7 médios: coluna que não é saldo herdava o período do documento — soma 1.310 em vez de 150 —, balancete parcial indo para o ano); 2ª (2 altos: toda coluna com o ano ia para o período do documento — 500, 435, 342 —, e "Alfa Comércio" não
-- casava a razão social); 3ª (3 altos: duas colunas casando a mesma entidade pela ordem física, DRE -> BALANCETE sem re-resolver, sonda verde com a extração sem gerar fato); 4ª (1 alto: o que o n8n comitava entre o backfill e o `create trigger` ficava sem fato para sempre; 2 médios); 5ª (2 altos: um gatilho de cadastro recalculando em snapshot velho enquanto um update de documento não comitado segurava o lock — documento com entidade e fatos `documento_sem_entidade` —; a extração COMBINADO concorrente com o cadastro de
-- entidade; a transcrição humana nunca virando fato; cadastro de período ~36 s num mandato 10 x 4.000). O diagnóstico, em 12/11: a causa é a arquitetura — uma CÓPIA do estado mantida por gatilhos —, e cada rodada abria um caminho novo. Decisão do dono: a cópia sai. Não há nada a recalcular, backfillar, reponta, nem janela de aplicação: a leitura é o estado COMITADO daquele instante, e as corridas da 5ª revisão deixam de ter onde acontecer (provadas, ver "As corridas").
--
-- O DESENHO (objetos e quem chama quem)
--   fato_financeiro (VIEW, security_invoker) = documento x documento_versao x LATERAL fn_fato_resolver(versão), só tipos de demonstração (fn_tipo_gera_fato). Quem lê: o portal (authenticated), o serviço, a P28. Ninguém a chama por função.
--   fn_fato_resolver(versão) — SQL, STABLE, NÃO security definer: a identidade de cada linha elegível. É a ÚNICA definição de "o fato". Chama fn_linha_vira_fato (elegibilidade) e, por ela, fn_papel_linha e fn_tipo_gera_fato; fn_coluna_entidade/fn_mesma_entidade/fn_entidade_canonica (entidade); fn_coluna_e_saldo/_abertura, fn_periodo_e_parcial, fn_periodo_canonico, fn_anos_periodo (período).
--   gatilho trg_fato_pendencia_da_extracao (evento_auditoria, AFTER INSERT, WHEN acao = 'extracao_sombra') -> fn_fato_pendencia_da_extracao (security definer: trava do documento, guarda fn_fato_pode_escrever, baixa das versões superadas) -> fn_fato_pendencia_da_versao (security definer: abre/atualiza/baixa a pendência lendo o resolver). Só o que o n8n grava no fim de fn_registrar_campos_extraidos dispara.
--   fn_fato_sonda_recentes (security definer, devolve um número) <- view da sonda `recentes`. As demais views da sonda são consultas ao catálogo.
--   SAÍRAM (todos introduzidos só nas versões anteriores desta migration, nunca aplicados): a tabela, as 4 FKs, o backfill, o recálculo final, fn_fato_recalcular (o escritor único), fn_fato_recalcular_caso, fn_materializar_fatos, fn_materializar_fatos_do_caso, fn_materializar_fatos_da_extracao, fn_materializar_fatos_backfill, fn_fato_segue_o_documento, fn_fato_cadastro_periodo, fn_fato_cadastro_entidade, fn_fato_extracao_nova, fn_fato_mesmo_caso, os gatilhos em documento, periodo e entidade, as sondas `um_escritor`/convergência/constraints.
--   Chamadores dos que saem (grep em Supabase/, N8N/, portal/src/, portal/scripts/, Verificação/, Leitor/, .github/ e .claude/ em 13/11/2026): só esta migration, o teste dela e a documentação (Supabase/README.md). Nenhum nó do n8n, nenhuma tela. E `fn_fundir_entidade` não precisa mais tocar o fato: sem FK, apagar a absorvida não derruba nada, e o fato é lido do que sobrou.
--
-- AS DECISÕES DESTA MIGRATION, E O PORQUÊ DE CADA UMA
--   1. OS TIPOS: BALANCO, BALANCETE, COMBINADO, DRE, FLUXO_CAIXA, DVA, DMPL, DF_AUDITADA (conferido contra `taxonomia_tipo_documento` e `ESTRUTURA_POR_TIPO`). A categoria "Contábil/Demonstrações" NÃO serve de proxy: inclui RAZAO e NOTAS_EXPL. A lista mora em UMA função (`fn_tipo_gera_fato`) e o predicado completo em `fn_linha_vira_fato`: a view, a pendência, a sonda e o teste perguntam a ela.
--   2. LINHA SEM VALOR NÃO É FATO (regra 1: célula vazia é ausência, não zero; o ZERO é valor e vira fato). Medido em produção em 11/11/2026: 4.798 linhas de documento de demonstração (de qualquer papel) com `valor_num` nulo ficam só como evidência.
--   3. TODAS AS VERSÕES do documento, como a tabela tinha; quem consome escolhe a vigente com `fn_versao_atual`. Em produção (11/11, medido): 85.531 fatos, 68.523 de versão vigente e 17.008 de versão antiga. Identidade do fato = `campo_extraido_id` (1:1): a view expõe `id` e `campo_extraido_id` iguais. NÃO há `origem` nem `criado_em` (eram do estado gravado) e há `caso_id` a mais (o filtro por mandato poda o cálculo).
--   4. A LINHA QUE NÃO RESOLVE VIRA FATO COM ESTADO EXPLÍCITO `sem_conta`, sem conta inventada (nem a raiz da demonstração pelo tipo): `conta_id` é nulo se, e só se, `resolucao_metodo = 'sem_conta'`, com o motivo `secao_nao_declarada` (seção nula, em branco ou o literal NAO_CLASSIFICAVEL das fixtures) ou `secao_fora_do_catalogo`.
--   5. ENTIDADE E PERÍODO — O CRITÉRIO (decisão do dono, 11/11/2026, depois de três remendos na mesma família): A 0243 NÃO INTERPRETA NOME DE COLUNA. Só atribui entidade ou período quando uma função que o banco JÁ usa para a mesma pergunta decide de forma INEQUÍVOCA; senão NULO com o motivo (errar para nulo é ausência declarada, regra 1; errar para valor é número fabricado). A família de bugs era uma só: duas colunas diferentes do mesmo documento
--      caindo na mesma (conta, entidade, período) e a soma dobrando (1.310; 500; 435; 342). ENTIDADE: a coluna de E é a que `fn_coluna_entidade(versão, E)` devolve; coluna que nenhuma entidade escolhe: nula (`coluna_sem_entidade_no_mandato`, `coluna_total_nao_escolhida`); escolhida por mais de uma (`coluna_casa_varias_entidades`); duas colunas casando a MESMA entidade (`entidade_com_varias_colunas`); mais de uma coluna total (`coluna_total_ambigua`); a linha SEM entidade_coluna num documento que TEM colunas de
--      entidade (`linha_sem_coluna_em_documento_com_colunas_de_entidade`). PERÍODO: a coluna que É o período do documento é a ÚNICA coluna de saldo (não abertura) ou, na falta de saldo, a ÚNICA coluna que nomeia só o ano do documento num documento NÃO parcial (BALANCETE e período mês/trimestre são parciais); coluna de ano puro de OUTRO ano só em documento não parcial e se UM período do mesmo mandato tem a forma canônica; o resto nulo, com o motivo. O período NÃO é criado.
--      Entidade e período nulos ficam no fato, consultáveis, sem fila (a pendência de entidade/período do documento já existe, 0153/0178). Medido em produção (read-only, 11/11, a mesma consulta de resolução): SEM ENTIDADE 1.685 de 85.531 e SEM PERÍODO 59.734 (70%): 45.609 coluna que não é o período do documento, 8.841 Saldo Inicial/anterior, 5.118 mais de uma coluna para o mesmo período, 114 linha sem coluna, 49 ano que o mandato não tem, 3 documento sem período. É o preço do critério: erra para nulo. A P28 decide se vale criar a leitura de saldo do BALANCETE e do mês por extenso.
--   6. SEGURANÇA. Uma view comum roda com o privilégio do DONO e PULA a RLS de campo_extraido e documento (vazaria o fato de outros mandatos). A RLS vale em DUAS camadas independentes: (a) `security_invoker = true` (as tabelas da própria view: documento e documento_versao); (b) o resolver NÃO é security definer (as tabelas que ele lê: campo_extraido, entidade, periodo). Cada camada sozinha basta para o vazamento da VIEW não acontecer; a (b) também protege a chamada DIRETA do resolver. A sonda exige as duas. Medido: security_invoker sozinho desligado — nenhum assert de dado reprova (a (b) segura), só os da sonda;
--      resolver como definer sozinho — reprovam os asserts de chamada direta (8 dos 187 asserts, nenhum de dado da view); AS DUAS desligadas — o vazamento de verdade, ver "Medição não-vazia". `security_invoker` é do Postgres 15: em versão anterior a migration morre ALTO (guarda no começo, com o motivo). Produção é >= 15 (a 0207, aplicada em 15/10/2026, usa `unique nulls not distinct`, que é do 15; o CI e o banco local são 16); a versão exata de produção NÃO foi medida aqui: `show server_version;`.
--      O ACL: a view e as funções nascem com `revoke all` de PUBLIC, anon, authenticated e service_role e SÓ o necessário é concedido (view: SELECT ao authenticated e ao service_role; resolver: EXECUTE ao authenticated, service_role e leitor só-leitura; internas: só o dono). Assim o ACL é o MESMO com ou sem o default de privilégio do Supabase (ALL em tabela/view, EXECUTE em função): o teste liga o default, descarta a view e as funções, reaplica a migration e compara byte a byte.
--      A CADEIA: a view é invoker, então quem a lê executa o resolver e as 16 funções que ele chama com o PRÓPRIO privilégio. Se produção não der EXECUTE de PUBLIC nelas (não conferido aqui), a view seria ilegível ao portal ("permission denied for function"); a migration concede o EXECUTE explícito às 17 ao authenticated, ao service_role e ao leitor só-leitura (a lista é o fecho das chamadas, achado por varredura do corpo; o teste de ACL ESTRITO tira o EXECUTE de PUBLIC nas 17 e prova que a lista basta e que cada uma é necessária; a sonda `cadeia` as confere).
--   7. A PENDÊNCIA (`conta_canonica_incerta`, rótulo novo de pendencia_tipo, complementar e sobrepujável: avisa, não trava): UMA por documento-versão (motivo `fato:conta_incerta:<versão>`), lista as linhas por heurística ou sem conta (as 12 primeiras no texto, com o EFEITO: fato sem identidade não entra em seção nenhuma), só para a versão VIGENTE; a das versões anteriores se baixa quando uma nova vira a vigente (resolvida_por sistema:versao_superada).
--      Só toca estado `aberta`: a que alguém está tratando ou decidiu não é baixada nem reaberta. Convergente: a extração de novo a resolve quando não sobra linha incerta. Só abre pendência a CONTA incerta; entidade e período nulos ficam no fato. O QUE ABRE: SÓ a extração NOVA (o evento extracao_sombra). O que já estava gravado (as versões antigas) NÃO abre pendência (decisão do dono: a 0179 abriu 365 de ruído e 347 já estavam julgadas ruído; em produção, 8.840 linhas incertas em 563 documentos-versão de 48 mandatos, medido em 11/11:
--      o backfill que abrisse deixaria 563 pendências), e não há backfill: o que a migration faz é CRIAR O GATILHO. A TRANSCRIÇÃO HUMANA (fn_registrar_transcricao_humana, 0129) NÃO abre pendência — DECISÃO, justificada: (i) ela não grava o evento extracao_sombra, então o gatilho não dispara; (ii) a pessoa que digitou é a autoridade da seção e a 0129 já diz que o que substitui a guarda de máquina é a AUTORIA (pedir à pessoa que revise o que acabou de digitar é ruído); (iii) a linha sem seção da transcrição continua na view como `sem_conta`, consultável. A troca de TIPO do documento
--      (RAZAO -> BALANCETE) também não abre: não é extração, e a linha aparece na view na hora. LIMITES CONHECIDOS (não corrigidos, por decisão de um gatilho só): a pendência aberta de uma versão que a transcrição humana superou, ou de um documento que deixou de ser demonstração, fica aberta até alguém a resolver ou a próxima extração a convergir; e a correção de seção por reparo em massa (0203/0204) não reavalia a pendência (a view já mostra o fato novo).
--      A TRAVA DO DOCUMENTO (corrida R4, medida com duas sessões): duas extrações concorrentes de duas versões do MESMO documento avaliavam cada uma com o snapshot que não enxerga as linhas da outra e deixavam DUAS pendências abertas (a da v2 superada nunca baixava). `pg_advisory_xact_lock` por documento, até o fim da transação da extração (milissegundos): a segunda avalia DEPOIS do commit da primeira. Sem a trava a corrida R4 reprova; com ela passa (Supabase/test/fato_financeiro_corridas.test.sql).
--   8. O PONTO DA EXTRAÇÃO NOVA É O GATILHO, NÃO O CORPO DE fn_registrar_campos_extraidos (decisão do dono, 12/11/2026): a 0270 (P11, APLICADA em produção) reemitiu essa função para gravar campo_extraido.ln e a P11 a reemite a cada fatia; reemiti-la daqui a partir do corpo da 0231 apagaria o `ln` em silêncio (e, num banco do zero, a 0270 — que roda depois — apagaria a nossa parte). O evento `extracao_sombra` é gravado DEPOIS do laço de inserção e DEPOIS da herança da seção pela árvore (0204): as duas únicas coisas que mudam o que a pendência lê.
--      Medido: o schema `public` do banco montado na ORDEM DO ZERO (0243 antes de 0270/0271) e na ORDEM DE PRODUÇÃO (0243 depois) é IDÊNTICO (pg_dump, 25.889 linhas, diff vazio), o catálogo da sonda também (md5), e o `ln` (7 e 9) é gravado e a pendência abre nas DUAS. A falha da pendência NÃO derruba a extração (a evidência vale mais que o derivado): sub-bloco que grava o evento `fato_pendencia_falhou` e segue; `query_canceled` NÃO é engolido; o evento `fato_pendencia_avaliada` é o sinal de que RODOU (regra 7); a recusa por permissão grava `fato_pendencia_negada` com o ator real.
--   9. DESEMPENHO. Medido em 13/11/2026 no banco local (Postgres 16, 4 CPUs, balancetes de 4.000 rótulos distintos, o pior caso do papel por combinação; 82.034 linhas de campo_extraido; NÃO é produção): uma versão de 4.000 linhas 0,54 a 0,69 s; o maior mandato das fixtures (684 fatos, 1.264 linhas) 0,46 s e o segundo (544) 0,39 s; um mandato sintético de 10 x 4.000 (40.000 fatos) 5,2 a 5,7 s; a view INTEIRA (81.831 fatos) 12,5 s; como authenticated (uma Analista alocada só no mandato) o mesmo: 5,4 s para o mandato de 40.000 e 0,59 s para uma versão, ou seja a RLS por mandato não custa mais que o superusuário; a sonda inteira 0,28 s; a extração de 4.000 linhas 1,47 a 1,71 s COM o gatilho e 0,92 a 1,00 s SEM (a pendência custa 0,55 a 0,7 s) e a de 100 linhas 65 a 79 ms com e 46 a 69 ms sem; a aplicação da migration 0,065 s. Na versão de TABELA (7d5f503): extração de 4.000 linhas 3,2 a 3,4 s com e 1,1 s sem; recálculo final ao aplicar 4,9 s; cadastro de período ~36 s num mandato 10 x 4.000 (a 5ª revisão): a ESCRITA ficou mais barata e a LEITURA passou a custar o cálculo. Ler um mandato de 40.000 fatos passa de 5 s e a view inteira de 12 s: a P28 resolve com VIEW MATERIALIZADA por mandato (proposta, NÃO implementada aqui).
--      TRÊS ACHADOS DA MEDIÇÃO: (1) a junção linha x papel (`cand join papel`, três igualdades) era escolhida pelo planejador como laço aninhado — ele estima ~150 linhas por versão (a média) e a versão recém-extraída tem 4.000 e nenhuma estatística — e custava 1,8 a 2,1 s numa versão de 4.000 rótulos (16 milhões de comparações) contra 0,4 a 0,54 s sem a junção: o conjunto dos (tipo, rótulo, unidade) que viram fato é UM jsonb (chave = o array jsonb, injetivo) e cada linha só pergunta se a sua chave está lá;
--      resultado IDÊNTICO ao da junção, conferido linha a linha nos dois sentidos (57.231 linhas: as fixtures mais versões sintéticas); (2) a primeira `fn_fato_sonda_recentes` usava `not exists` correlacionado contra uma CTE (12,5 s com 3 versões de 4.000 linhas) e passou a junção por igualdade (4 s) e a um TETO (3 versões de até 1.500 linhas, entre as 30 mais novas: ~0,2 s); (3) o JIT e o plano: a consulta inlinada era grande e, com o JIT do servidor ligado (o padrão do Postgres; o de produção não foi conferido), o Postgres gastava ~3 s COMPILANDO para ler 684 fatos (3,5 s contra 0,68 s com `jit = off`); `SET jit = off` na função resolve, mas ela deixa de ser inlinada e o planejador passa a estimar 1.000 linhas a custo 100
--      e, ao juntar a view com outra tabela, pode escolher laço aninhado que REEXECUTA o resolver inteiro por linha externa (medido: este teste passou de 15 s para mais de 2 minutos); `COST 100000 ROWS 200` na função devolve a junção única (o teste voltou a 17 s). O custo do resolver é proporcional às linhas e dominado por fn_papel_linha (~0,11 ms por rótulo distinto por versão).
--      Passar de ALGUNS SEGUNDOS por mandato grande é o que a P28 resolve com VIEW MATERIALIZADA por mandato (refresh na extração, ou a tabela da versão anterior com UM escritor): NÃO implementada aqui, proposta. Filtrar por conta, entidade ou período NÃO poda (lê todas as versões que o usuário enxerga): a leitura de produto deve filtrar por caso_id ou documento_versao_id.
--
-- AS CORRIDAS E A JANELA DA APLICAÇÃO (duas sessões reais, dblink; Supabase/test/fato_financeiro_corridas.test.sql, 14 asserts). R1 (extração não comitada x cadastro de entidade), R2 (extração COMBINADO x 2ª entidade que casa a mesma coluna, nas duas ordens de commit), R3 (update de documento.entidade_id não comitado x cadastro de entidade e de período): a view lê o estado comitado, nada trava, e o fato final é o do zero — escrito à mão. R4 (a pendência): ver a decisão 7.
--   A JANELA (medida com a migration segurando o lock do `create trigger` por 8 s e o n8n extraindo no meio; script em Arquitetura do Sistema/3 Estado e Execução/patches/s130-p27-view/): não há backfill, então não há o que perder. A primeira escrita em evento_auditoria ESPEROU o lock (7,8 s na medição; a migration real segura milissegundos), a extração da janela ficou com 2 fatos (a view) e 1 pendência (o gatilho já existia quando ela comitou), e a extração de ANTES da migration ficou com 1 fato e 0 pendência (por decisão: só extração nova). `lock_timeout = 5s` faz a aplicação falhar RÁPIDO se o n8n estiver com um lote aberto (reaplique).
--
-- A SONDA (como a 0242: por constraint e por comportamento, não por contagem). 20 requisitos: a view (invoker, sobre o resolver, resolver não definer); só LER (nenhum privilégio de escrita, anon sem acesso, nem ao resolver); a leitura das 3 versões mais novas concorda com as linhas (a conta é a seção da linha; o método, a flag de inferida; nenhum fato de linha não elegível; roda como DEFINER para a RLS do chamador não mudar a amostra); a cadeia (17 funções executáveis); o rótulo da pendência; a lista dos 8 tipos que geram e 2 que não podem gerar, tipo a tipo; o gatilho e o que ele chama (inclusive a guarda); a pendência lê o resolver; os 7 marcadores do corpo do resolver (nome de função, literal de motivo).
-- O LEITOR SÓ-LEITURA (`supabase_read_only_user`): as views da sonda chamam funções com o privilégio de quem LÊ; o bloco de grant (como 0233/0234 e a correção da 0242) as entrega a ele, e Supabase/test/sonda_para_o_leitor_somente_leitura.test.sql o prova (as 19 funções: a amostra, o resolver e as 16 da cadeia, mais a da 0242).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/fato_financeiro.test.sql — 187 asserts, todos EXECUTADOS (cada um é uma chamada escrita: não há helper que repita); a migration aplicou e o teste aparece no log em todas as rodadas; o NOTICE `fato_financeiro: 187 asserts executados, N reprovados`. Controle (migration intacta): 0 dos 187 asserts reprovam.
-- Medido em 13/11/2026 sobre o banco montado pelo run.sh (fixtures e todos os testes anteriores), sabotando uma parte por vez: a função reemitida com um `replace` sobre pg_get_functiondef (a troca CONFERIDA como aplicada: se o texto não existe a medição ABORTA) ou o gatilho removido/o privilégio concedido; o teste roda numa cópia SEM o bloco do topo (senão a migration desfaria a sabotagem) com `ff.medindo=on` (o assert vira contagem), o log é lido atrás de FALHOU:, e a migration é reaplicada para restaurar. O executor é Arquitetura do Sistema/3 Estado e Execução/patches/s130-p27-view/sab.py.
--   * M01 migration SEM o revoke da view (o default de privilegio do Supabase deixa o anon e o authenticated escreverem): 11 dos 187 asserts reprovam.
--   * M02 migration SEM os grants da cadeia (o ACL estrito deixa a view ilegível): o arquivo ABORTA no primeiro assert de leitura do authenticated ("permission denied for function fn_tipo_gera_fato"): a suíte inteira reprova, sem contagem.
--   * M03 migration SEM o revoke do resolver do anon/authenticated (default de funcao): 7 dos 187 asserts reprovam.
--   * M04 migration SEM o revoke das funcoes internas (default de funcao): 4 dos 187 asserts reprovam.
--   * M05 view SEM security_invoker na migration: 5 dos 187 asserts reprovam.
--   * M06 migration SEM a lista de cadeia no catalogo da sonda (17 vira 5): 9 dos 187 asserts reprovam.
--   * N01 sonda "recentes" fixa em ok: 2 dos 187 asserts reprovam.
--   * N02 sonda "view_invoker" fixa em ok: 2 dos 187 asserts reprovam.
--   * N03 sonda "so_le" fixa em ok: 3 dos 187 asserts reprovam.
--   * N04 sonda "cadeia" fixa em 17: 1 dos 187 asserts reprovam.
--   * P01 gatilho da pendencia removido: 27 dos 187 asserts reprovam.
--   * P02 funcao do gatilho sem chamar a avaliacao: 21 dos 187 asserts reprovam.
--   * P03 versao superada nao baixa a pendencia: 2 dos 187 asserts reprovam.
--   * P04 query_canceled engolido: 1 dos 187 asserts reprovam.
--   * P05 pendencia aberta para o que ja estava gravado (o que um backfill que abrisse fila faria): 1 dos 187 asserts reprovam.
--   * P06 transcricao humana abre pendencia (gatilho em campo_extraido): 2 dos 187 asserts reprovam.
--   * P07 troca de tipo do documento abre pendencia (gatilho em documento): 2 dos 187 asserts reprovam.
--   * P08 pendencia sem a guarda de escrita (fn_fato_pode_escrever sempre verdadeira): 5 dos 187 asserts reprovam.
--   * P09 fn_registrar_campos_extraidos sem gravar o ln (o que reemitir do corpo antigo apagaria): 2 dos 187 asserts reprovam.
--   * S01 coluna que nao e saldo herda o periodo do documento (1.310, 500, 435, 342): 15 dos 187 asserts reprovam.
--   * S02 coluna escolhida sem exigir ser UNICA (>= 1 em vez de = 1): 2 dos 187 asserts reprovam.
--   * S03 documento PARCIAL da o ano a coluna 2025: 3 dos 187 asserts reprovam.
--   * S04 total sem exigir ser unico (duas colunas total): 5 dos 187 asserts reprovam.
--   * S05 linha sem coluna de entidade num documento com colunas vai para o dono: 15 dos 187 asserts reprovam.
--   * S06 duas colunas da mesma entidade SEM a unicidade por (versao, entidade): 2 dos 187 asserts reprovam.
--   * S07 casamento de nome proprio no lugar de fn_coluna_entidade ("Alfa Comercio" x razao social): 11 dos 187 asserts reprovam.
--   * S08 conta achada pelo TIPO do documento em vez da secao: 57 dos 187 asserts reprovam.
--   * S09 coluna de abertura (Saldo Inicial) recebe o periodo do documento: 13 dos 187 asserts reprovam.
--   * S10 periodo de OUTRO ano procurado em qualquer mandato (sem o filtro de caso): 13 dos 187 asserts reprovam.
--   * S11 elegibilidade so "tem valor" (sem tipo e sem papel): 13 dos 187 asserts reprovam.
--   * S12 elegibilidade sem o papel conta (subtotal vira fato): 13 dos 187 asserts reprovam.
--   * S13 BALANCO fora da lista de tipos: 55 dos 187 asserts reprovam.
--   * S14 resolver sem o filtro de papel (a lista de rotulos que viram fato ignorada): 19 dos 187 asserts reprovam.
--   * S15 resolver ignora a linha sem valor (valor nulo vira fato): 10 dos 187 asserts reprovam.
--   * V01 SECURITY_INVOKER desligado (a view roda com o privilegio do dono): 3 dos 187 asserts reprovam.
--   * V02 resolver como SECURITY DEFINER: 8 dos 187 asserts reprovam.
--   * V03 authenticated com INSERT/UPDATE/DELETE na view: 6 dos 187 asserts reprovam.
--   * V04 anon lendo a view: 3 dos 187 asserts reprovam.
--   * V05 anon executando o resolver: 3 dos 187 asserts reprovam.
--   * V06 poda desligada (a view resolve TODAS as versoes e filtra depois): 2 dos 187 asserts reprovam.
--   * V07 as DUAS camadas desligadas (view sem security_invoker E resolver SECURITY DEFINER): o vazamento de verdade: 10 dos 187 asserts reprovam.
-- A medição das sabotagens de MIGRATION (M01-M06) roda o teste COM o topo apontando para a migration sabotada. O teste isolado reprova 4 asserts de ARRANJO (as fixtures trazem >= 1 linha com seção inferida, >= 1 com seção nula, >= 100 sem conta, e a invariante mede >= 1.000 fatos de identidade completa) em um banco só com as fixtures: eles dependem dos dados que o run.sh carrega e do estado de suítes anteriores; NÃO foi tornado autossuficiente, porque isso exigiria inventar um corpus (regra 4). Rode-o pelo run.sh.
--
-- O QUE NÃO FOI MEDIDO / O QUE FALTA. (1) Produção: nenhuma leitura de produção foi feita nesta rodada (sem credencial); os números de produção acima são da sessão de 11/11 (somente leitura). Medir DEPOIS de aplicar: `show server_version`, a sonda da 0243 (0 ausentes), `select count(*) filter (where ln is not null) from campo_extraido` (não pode ter caído), e a leitura do maior mandato real pela view (tempo). (2) O ACL de produção das funções antigas (se PUBLIC tem EXECUTE nelas): coberto pela concessão explícita, não conferido. (3) A janela com mais de uma transação concorrente além das duas sessões.
-- (4) A leitura de um mandato real pelo `authenticated` (RLS por linha com os usuários reais): medida só com a Analista sintética. (5) Fica para a P28: view materializada se a leitura de mandato grande passar de poucos segundos; leitura de saldo do BALANCETE e do mês por extenso; conta-folha e hierarquia; reconciliação sobre o fato (P29).

alter type pendencia_tipo add value if not exists 'conta_canonica_incerta';

begin;

-- LOCK: `create trigger` em evento_auditoria segura ShareRowExclusive até o COMMIT e o n8n grava evento a cada extração. `lock_timeout` faz a aplicação falhar RÁPIDO (e se reaplica: a migration é idempotente) em vez de esperar um lote e arriscar deadlock.
set local lock_timeout = '5s';

-- O PISO DA VIEW: `security_invoker` é do Postgres 15. Em versão anterior o `with (security_invoker = true)` seria um erro de sintaxe (a migration morre alto, o que é bom); a guarda abaixo só diz POR QUÊ em português. Uma view comum roda com o privilégio do DONO e PULA a RLS de campo_extraido e documento:
-- o authenticated leria o fato de TODOS os mandatos. Produção é PG >= 15 (a 0207, aplicada em 15/10/2026, usa `unique nulls not distinct`, que é do 15; o CI e o banco local são 16). A versão exata de produção NÃO foi medida aqui: confira com `show server_version;`.
do $$ begin
  if current_setting('server_version_num')::int < 150000 then
    raise exception '0243: fato_financeiro é uma VIEW com security_invoker (Postgres 15+); este servidor é %. Sem isso a view pularia a RLS por mandato.', current_setting('server_version');
  end if;
end $$;

-- O DESENHO ANTERIOR (a TABELA fato_financeiro, nunca aplicada em produção) não é convertido em silêncio: se um banco de desenvolvimento ainda a tem, a migration para aqui, dizendo o que fazer. `create or replace view` sobre uma tabela já falharia, só que com uma mensagem que não ensina nada.
do $$ begin
  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'fato_financeiro' and c.relkind = 'r') then
    raise exception '0243: fato_financeiro existe como TABELA (a versão antiga desta migration, que nunca foi aplicada em produção). Descarte-a no banco de desenvolvimento (drop table fato_financeiro cascade; e as funções fn_fato_*, fn_materializar_fatos* e os gatilhos trg_fato_*) e reaplique.';
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- O QUE É ELEGÍVEL: uma lista só, e todo o resto (o resolver, a pendência, a sonda, o teste) pergunta a ela.
-- -----------------------------------------------------------------------------
create or replace function fn_tipo_gera_fato(p_tipo text)
returns boolean language sql immutable as $$
  select coalesce(p_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DRE', 'FLUXO_CAIXA', 'DVA', 'DMPL', 'DF_AUDITADA'), false)
$$;
comment on function fn_tipo_gera_fato(text) is
  '0243: os tipos de documento cujas linhas viram fato_financeiro: as demonstrações. BALANCO, BALANCETE, COMBINADO, DRE e FLUXO_CAIXA são as 5 de ESTRUTURA_POR_TIPO (statement-templates.ts); DVA e DMPL são as 2 que a 0024 pôs na taxonomia e o portal já roteia por seção (FAMILIA_POR_SECAO_CANONICA); DF_AUDITADA traz as demonstrações juntas e cada linha vai para a SUA seção. '
  'A categoria Contábil/Demonstrações da taxonomia NÃO serve de proxy: ela inclui RAZAO e NOTAS_EXPL. Estoque, Razão, Aging, Mapa de Dívida e o resto continuam só evidência. A sonda confere os 8 tipos um a um (view), não pelo corpo.';

create or replace function fn_linha_vira_fato(p_tipo text, p_chave text, p_unidade text, p_valor numeric)
returns boolean language sql immutable as $$
  select p_valor is not null and fn_tipo_gera_fato(p_tipo) and fn_papel_linha(p_chave, p_tipo, p_unidade) = 'conta'
$$;
comment on function fn_linha_vira_fato(text, text, text, numeric) is
  '0243: a linha de campo_extraido vira fato quando (1) tem valor (célula vazia é ausência, não zero: regra 1), (2) o documento é de demonstração e (3) o papel é conta (fn_papel_linha): subtotal é a P28, derivado e série mensal não são conta.';

-- O ATOR REAL do evento: o usuário autenticado quando há, senão o sistema.
create or replace function fn_fato_ator()
returns text language sql stable as $$ select coalesce('usuario:' || auth.uid()::text, 'sistema:0243') $$;

-- QUEM PODE ESCREVER pendência de fato: conexão de serviço (o n8n, a migration: o papel da sessão é service_role ou nenhum) ou quem escreve no mandato (fn_pode_escrever_caso, 0216). O `current_setting('role')` é o papel que o PostgREST pôs com SET ROLE e é lido DENTRO de função
-- security definer (current_user lá seria o dono). É a MESMA guarda da versão anterior: a pendência é a única coisa que esta migration ainda escreve, e a policy de insert em evento_auditoria (que dispara o gatilho) já exige poder escrever o mandato; a guarda é a segunda trava.
create or replace function fn_fato_pode_escrever(p_caso uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(current_setting('role', true), 'none') in ('none', 'service_role', 'postgres', 'supabase_admin')
      or (p_caso is not null and fn_pode_escrever_caso(p_caso))
$$;

-- -----------------------------------------------------------------------------
-- A RESOLUÇÃO: a identidade de TODAS as linhas elegíveis do estado ATUAL (versão nula = todas). Só LÊ. É a ÚNICA definição de "o fato": a view, a pendência e a sonda perguntam a ela.
-- -----------------------------------------------------------------------------
create or replace function fn_fato_resolver(p_documento_versao_id uuid)
returns table (campo_id uuid, documento_versao_id uuid, conta_id text, resolucao_metodo text, sem_conta_motivo text,
               entidade_id uuid, entidade_origem text, entidade_motivo text, entidade_coluna text,
               periodo_id uuid, periodo_origem text, periodo_motivo text, periodo_coluna text,
               valor numeric, unidade text, moeda text)
language sql stable cost 100000 rows 200 set jit = off as $$   -- cost/rows: sem eles o planejador estima 1.000 linhas a custo 100 e, ao juntar a view com outra tabela, pode escolher laço aninhado que REEXECUTA o resolver inteiro por linha externa (medido: o teste inteiro passou de 15 s para mais de 2 minutos); com o custo real (uma chamada custa dezenas de milissegundos a segundos) ele faz a junção uma vez. jit = off: o JIT do servidor gastava ~3 s COMPILANDO para ler 684 fatos (3,5 s contra 0,68 s medido em 13/11/2026)
  with cand as materialized (
    select ce.id as campo_id, ce.documento_versao_id, d.caso_id, d.tipo_taxonomia as tipo, ce.chave, d.entidade_id as doc_entidade, d.periodo_id as doc_periodo,
           pd.tipo as dper_tipo, pd.referencia as dper_ref,
           ce.valor_num, ce.unidade, ce.moeda, ce.secao_canonica as secao, ce.secao_canonica_inferida as inferida,
           nullif(btrim(ce.entidade_coluna), '') as ecol, nullif(btrim(ce.periodo_coluna), '') as pcol
      from campo_extraido ce
      join documento_versao dv on dv.id = ce.documento_versao_id
      join documento d on d.id = dv.documento_id
      left join periodo pd on pd.id = d.periodo_id
     where (p_documento_versao_id is null or ce.documento_versao_id = p_documento_versao_id)
       and ce.valor_num is not null and fn_tipo_gera_fato(d.tipo_taxonomia)
  ),
  -- O papel da linha (fn_papel_linha, ~180 µs) UMA vez por (tipo, rótulo, unidade) distintos, não por linha. Medido em produção em 11/11/2026: 100.215 linhas de demonstração com valor, 6.841 combinações distintas (15x menos chamadas).
  -- fn_linha_vira_fato é o predicado ÚNICO (a sonda e o teste o usam): o valor entra como 1 porque ele só pergunta se é nulo, e a CTE acima já tirou os nulos.
  -- (duas CTEs, não uma subconsulta: o Postgres empurra o filtro para DENTRO do distinct e chama fn_papel_linha por LINHA de novo — medido, 21 s.)
  rotulos as materialized (select distinct tipo, chave, unidade from cand),
  papel as materialized (
    select x.tipo, x.chave, x.unidade from rotulos x where fn_linha_vira_fato(x.tipo, x.chave, x.unidade, 1)
  ),
  -- O CASAMENTO DA LINHA COM O PAPEL NÃO É UMA JUNÇÃO (4ª VERSÃO DESTE TRECHO, medida em 13/11/2026): `cand join papel` com três igualdades era escolhida pelo planejador como laço aninhado (estimava ~150 linhas por versão: média das versões; a versão extraída agora tem 4.000 e nenhuma estatística) e
  -- custava 1,8 a 2,1 s numa versão de 4.000 rótulos distintos (16 milhões de comparações) contra 0,4 a 0,54 s sem a junção; o gatilho da extração pagava isso em toda extração grande. Agora o conjunto dos (tipo, rótulo, unidade) que viram fato é UM jsonb (chave = o array jsonb, injetivo) e cada linha só pergunta se a sua chave está lá:
  -- não há junção para o planejador errar. Mesmo resultado (conferido linha a linha contra a junção, nas fixtures e em 120 mil linhas sintéticas).
  papel_chave as materialized (
    select coalesce(jsonb_object_agg(jsonb_build_array(tipo, chave, coalesce(unidade, ''))::text, true), '{}'::jsonb) as m from papel
  ),
  alvo as materialized (
    select c.* from cand c cross join papel_chave k where k.m ? (jsonb_build_array(c.tipo, c.chave, coalesce(c.unidade, ''))::text)
  ),
  vinfo as materialized (
    select v.documento_versao_id, v.caso_id, v.tipo, v.doc_entidade, v.doc_periodo, v.dper_tipo, v.dper_ref,
           case when cardinality(fn_anos_periodo(v.dper_tipo, v.dper_ref)) = 1 then (fn_anos_periodo(v.dper_tipo, v.dper_ref))[1] end as y
      from (select distinct documento_versao_id, caso_id, tipo, doc_entidade, doc_periodo, dper_tipo, dper_ref from alvo) v
  ),
  -- ===== ENTIDADE: quem decide é fn_coluna_entidade (0023/0030, com fn_mesma_entidade): a coluna que ela devolve para a entidade E é a coluna de E. Nenhum casamento de nome é escrito aqui.
  -- 3ª REVISÃO, ALTO 1: fn_coluna_entidade devolve UMA coluna por entidade (`limit 1` sem order by). Com duas colunas do documento que casam o nome da MESMA entidade ("Alfa Comércio Atacado", empresa não cadastrada, e "Alfa Comércio") ela entrega a que a ordem física der, e a ALFA recebia a soma de uma coluna que
  -- talvez nem fosse dela, com a própria coluna anulada pelo motivo falso coluna_sem_entidade_no_mandato. Unicidade por (versão, entidade): as colunas DISTINTAS do documento em que fn_mesma_entidade é verdadeira para a entidade; mais de uma = nenhuma delas é atribuída (entidade_com_varias_colunas).
  ecols as materialized (
    select distinct ce.documento_versao_id, v.caso_id, nullif(btrim(ce.entidade_coluna), '') as col
      from (select distinct documento_versao_id, caso_id from alvo where ecol is not null) v
      join campo_extraido ce on ce.documento_versao_id = v.documento_versao_id and nullif(btrim(ce.entidade_coluna), '') is not null
  ),
  enome as materialized (
    select c.documento_versao_id, c.col, e.id as entidade_id
      from ecols c join entidade e on e.caso_id = c.caso_id
     where fn_mesma_entidade(c.col, e.razao_social)
  ),
  enome_n as materialized (select documento_versao_id, entidade_id, count(distinct col) as n from enome group by 1, 2),
  eescolha as materialized (
    select x.documento_versao_id, x.col, x.entidade_id, x.razao_social
      from (select v.documento_versao_id, e.id as entidade_id, e.razao_social, nullif(btrim(fn_coluna_entidade(v.documento_versao_id, e.id)), '') as col
              from (select distinct documento_versao_id, caso_id from alvo where ecol is not null) v
              join entidade e on e.caso_id = v.caso_id) x
     where x.col is not null and x.col <> chr(1)
       and not exists (select 1 from enome_n n where n.documento_versao_id = x.documento_versao_id and n.entidade_id = x.entidade_id and n.n > 1)
  ),
  emap as materialized (
    select documento_versao_id, col, count(*) as n, (array_agg(entidade_id))[1] as entidade_id, bool_or(fn_mesma_entidade(col, razao_social)) as por_nome
      from eescolha group by 1, 2
  ),
  -- fn_coluna_entidade entrega "a" coluna total (limit 1, sem ordem): com mais de uma coluna total no documento a escolha é arbitrária, e arbitrária não é inequívoca
  etot as materialized (
    select ce.documento_versao_id, count(distinct nullif(btrim(ce.entidade_coluna), '')) as n
      from campo_extraido ce
     where ce.documento_versao_id in (select documento_versao_id from vinfo) and ce.entidade_coluna is not null
       and fn_normalizar_texto(ce.entidade_coluna) ~ '^(combinad|consolidad|total|soma)'
     group by 1
  ),
  -- documento que TEM coluna de entidade: a linha sem entidade_coluna não tem dono inequívoco (a coluna total do dono e a linha "sem coluna" seriam duas colunas na mesma chave: a soma dobra)
  vecol as materialized (
    select distinct ce.documento_versao_id
      from campo_extraido ce
     where ce.documento_versao_id in (select documento_versao_id from vinfo) and nullif(btrim(ce.entidade_coluna), '') is not null
  ),
  ent as materialized (
    select k.documento_versao_id, coalesce(k.ecol, '') as ekey,
           case when k.ecol is null then (case when not k.tem_ecols then k.doc_entidade end) when m.n = 1 and (m.por_nome or coalesce(t.n, 0) <= 1) then m.entidade_id end as entidade_id,
           case when k.ecol is null then (case when k.doc_entidade is not null and not k.tem_ecols then 'documento' end)
                when m.n = 1 and (m.por_nome or coalesce(t.n, 0) <= 1) then (case when m.por_nome then 'coluna' else 'coluna_total' end) end as origem,
           case when k.ecol is null then (case when k.doc_entidade is null then 'documento_sem_entidade' when k.tem_ecols then 'linha_sem_coluna_em_documento_com_colunas_de_entidade' end)
                when m.n = 1 and m.por_nome then null
                when m.n = 1 and coalesce(t.n, 0) <= 1 then null
                when m.n = 1 then 'coluna_total_ambigua'
                when m.n > 1 then 'coluna_casa_varias_entidades'
                when exists (select 1 from enome en join enome_n nn on nn.documento_versao_id = en.documento_versao_id and nn.entidade_id = en.entidade_id
                              where en.documento_versao_id = k.documento_versao_id and en.col = k.ecol and nn.n > 1) then 'entidade_com_varias_colunas'
                when fn_normalizar_texto(k.ecol) ~ '^(combinad|consolidad|total|soma)' then 'coluna_total_nao_escolhida'
                else 'coluna_sem_entidade_no_mandato' end as motivo
      from (select x.documento_versao_id, x.doc_entidade, x.ecol, (ve.documento_versao_id is not null) as tem_ecols
              from (select distinct documento_versao_id, doc_entidade, ecol from alvo) x
              left join vecol ve on ve.documento_versao_id = x.documento_versao_id) k
      left join emap m on m.documento_versao_id = k.documento_versao_id and m.col = k.ecol
      left join etot t on t.documento_versao_id = k.documento_versao_id
  ),
  -- ===== PERÍODO: a 0243 não interpreta nome de coluna. Só atribui quando as funções do banco para esta pergunta (fn_coluna_e_saldo, fn_coluna_e_abertura, fn_periodo_e_parcial, fn_anos_periodo, fn_periodo_canonico: 0199-0201/0234) decidem de forma INEQUÍVOCA.
  --   A coluna que É o período do documento: a ÚNICA coluna de saldo (Saldo final/atual) ou, na falta de saldo, a ÚNICA coluna que nomeia só o ano do documento num documento NÃO parcial. Duas candidatas (ou nenhuma): nenhuma é escolhida (fn_coluna_periodo_do_ano
  --   desempata por contagem e ordem alfabética: no balancete de junho com Jun/2025 e 30/06/2025 ela entrega uma ao acaso, e "ao acaso" é número fabricado). Documento sem coluna nenhuma: a linha é do período do documento.
  vcol as materialized (
    select i.documento_versao_id, c.pcol, i.y,
           fn_coluna_e_abertura(c.pcol) as abertura,
           (fn_coluna_e_saldo(c.pcol) and not fn_coluna_e_abertura(c.pcol)) as saldo,
           fn_periodo_e_parcial(c.pcol, i.tipo, i.dper_tipo, i.dper_ref) as parcial,
           case when regexp_replace(fn_periodo_canonico('outro', c.pcol), '^(\d{4})-12-31$', '\1') ~ '^\d{4}$'
                then regexp_replace(fn_periodo_canonico('outro', c.pcol), '^(\d{4})-12-31$', '\1')::int end as ano_puro
      from vinfo i
      join (select distinct ce.documento_versao_id, nullif(btrim(ce.periodo_coluna), '') as pcol
              from campo_extraido ce
             where ce.documento_versao_id in (select documento_versao_id from vinfo) and nullif(btrim(ce.periodo_coluna), '') is not null) c
        on c.documento_versao_id = i.documento_versao_id
  ),
  vcol2 as materialized (
    select c.*, (c.ano_puro is not null and not c.parcial and c.ano_puro = c.y) as e_ano_do_doc,
           count(*) filter (where c.ano_puro is not null and not c.parcial) over (partition by c.documento_versao_id, c.ano_puro) as n_mesmo_ano
      from vcol c
  ),
  vesc as materialized (
    select documento_versao_id, count(*) as n_cols,
           case when count(*) filter (where y is not null and (saldo or e_ano_do_doc)) = 1
                then min(pcol) filter (where y is not null and (saldo or e_ano_do_doc)) end as escolhida
      from vcol2 group by 1
  ),
  per0 as materialized (
    select documento_versao_id, pcol, abertura, parcial, ano_puro, e_ano_do_doc, n_mesmo_ano from vcol2
    union all
    select documento_versao_id, null, false, false, null::int, false, 0 from vinfo
  ),
  per as materialized (
    select z.documento_versao_id, coalesce(z.pcol, '') as pkey,
           z.pid as periodo_id,
           case when z.pid is null then null when z.pcol is null or z.pcol = z.escolhida then 'documento' else 'coluna' end as origem,
           case when z.pid is not null then null
                when z.pcol is null and z.n_cols > 0 then 'linha_sem_coluna_em_documento_com_colunas'
                when (z.pcol is null or z.pcol = z.escolhida) and z.doc_periodo is null then 'documento_sem_periodo'
                when z.abertura then 'coluna_de_abertura'
                when z.n_mesmo_ano > 1 then 'mais_de_uma_coluna_para_o_mesmo_periodo'
                when z.ano_puro is not null and not z.parcial and not z.e_ano_do_doc then 'periodo_da_coluna_nao_cadastrado'
                else 'coluna_nao_e_o_periodo_do_documento' end as motivo
      from (select p.documento_versao_id, p.pcol, p.abertura, p.parcial, p.ano_puro, p.e_ano_do_doc, p.n_mesmo_ano,
                   i.doc_periodo, coalesce(e.n_cols, 0) as n_cols, e.escolhida,
                   case when p.pcol is null then (case when coalesce(e.n_cols, 0) = 0 then i.doc_periodo end)
                        when p.pcol = e.escolhida then i.doc_periodo
                        when p.abertura then null
                        when p.ano_puro is not null and not p.parcial and not p.e_ano_do_doc and p.n_mesmo_ano = 1 then x.id
                        else null end as pid
              from per0 p
              join vinfo i on i.documento_versao_id = p.documento_versao_id
              left join vesc e on e.documento_versao_id = p.documento_versao_id
              left join lateral (
                -- o MESMO casamento de fn_upsert_periodo (forma canônica, o de menor referência no empate), sem o insert: o período NÃO é criado aqui. O fechamento 31/12/AAAA e o ano AAAA são o mesmo período.
                select coalesce(
                         (select q.id from periodo q where q.id = i.doc_periodo
                             and regexp_replace(fn_periodo_canonico(q.tipo, q.referencia), '^(\d{4})-12-31$', '\1') = p.ano_puro::text),
                         (select q.id from periodo q where q.caso_id = i.caso_id
                             and regexp_replace(fn_periodo_canonico(q.tipo, q.referencia), '^(\d{4})-12-31$', '\1') = p.ano_puro::text
                           order by q.referencia, q.id limit 1)) as id
                 where p.ano_puro is not null and not p.parcial and not p.e_ano_do_doc and p.n_mesmo_ano = 1) x on true) z
  )
  select a.campo_id, a.documento_versao_id, c.codigo,
         case when c.codigo is null then 'sem_conta' when a.inferida then 'heuristica' else 'declarada' end,
         case when c.codigo is not null then null
              when coalesce(nullif(btrim(a.secao), ''), 'NAO_CLASSIFICAVEL') = 'NAO_CLASSIFICAVEL' then 'secao_nao_declarada'
              else 'secao_fora_do_catalogo' end,
         e.entidade_id, e.origem, e.motivo, a.ecol, p.periodo_id, p.origem, p.motivo, a.pcol, a.valor_num, a.unidade, a.moeda
    from alvo a
    left join conta_canonica c on c.secao_canonica = a.secao
    join ent e on e.documento_versao_id = a.documento_versao_id and e.ekey = coalesce(a.ecol, '')
    join per p on p.documento_versao_id = a.documento_versao_id and p.pkey = coalesce(a.pcol, '')
$$;

comment on function fn_fato_resolver(uuid) is
  '0243: a identidade de cada linha elegível, calculada na hora e SÓ LÊ: conta (a seção, pelo catálogo), entidade e período (pela coluna da linha quando uma função do banco decide sem ambiguidade, pelo documento quando não, e NULOS com o motivo quando a coluna não é saldo, é de abertura, o documento é parcial ou o total duplica a coluna da entidade). '
  'Versão nula = todas. NÃO É SECURITY DEFINER, de propósito: ela lê campo_extraido, documento, entidade e periodo com a RLS de QUEM CHAMA (por isso a view fato_financeiro, security_invoker, mostra a cada usuário só o próprio mandato). É a única definição de "o fato"; não existe cópia gravada.';

-- -----------------------------------------------------------------------------
-- A VIEW. `fato_financeiro` NÃO é tabela: é o resolver aplicado a cada versão de documento de demonstração, na hora de ler. Não há cópia para envelhecer, nem gatilho de materialização, nem backfill, nem recálculo: o fato é o que o estado ATUAL de campo_extraido, documento, entidade e periodo diz agora.
--   * security_invoker = true: a RLS por mandato de campo_extraido, documento_versao, documento, entidade e periodo vale para QUEM LÊ. Sem isso a view roda com o privilégio do dono (postgres, BYPASSRLS) e devolve os fatos de todos os mandatos.
--   * `id` e `campo_extraido_id` são o MESMO uuid: a identidade do fato é a da linha que o sustenta (1:1). Não há `origem` nem `criado_em`: eram do estado gravado (a pendência lia a origem para não olhar o backfill; hoje ela nasce do evento da extração, não da linha do fato).
--   * `caso_id` entra para o filtro por mandato: o planejador empurra `where caso_id = ...` e `where documento_versao_id = ...` para dentro (o resolver só roda para as versões que sobram). Filtrar por conta, entidade ou período NÃO poda: lê todas as versões que o usuário enxerga (custo medido no cabeçalho).
--   * todas as versões do documento, como a tabela tinha: quem consome escolhe a vigente com fn_versao_atual.
-- -----------------------------------------------------------------------------
create or replace view fato_financeiro with (security_invoker = true) as
  select r.campo_id as id, r.campo_id as campo_extraido_id, dv.id as documento_versao_id, d.caso_id,
         r.conta_id, r.resolucao_metodo, r.sem_conta_motivo,
         r.entidade_id, r.entidade_origem, r.entidade_motivo, r.entidade_coluna,
         r.periodo_id, r.periodo_origem, r.periodo_motivo, r.periodo_coluna,
         r.valor, r.unidade, r.moeda
    from documento d
    join documento_versao dv on dv.documento_id = d.id
   cross join lateral fn_fato_resolver(dv.id) r
   where fn_tipo_gera_fato(d.tipo_taxonomia);
comment on view fato_financeiro is
  '0243 (P27): o fato canônico ACIMA de campo_extraido, que não muda (ADR 01): UMA linha por linha extraída elegível (só documento de demonstração, fn_tipo_gera_fato; só papel conta, fn_papel_linha; só com valor: ausência não vira fato, regra 1), calculada na hora por fn_fato_resolver. '
  'É VIEW com security_invoker: cada usuário lê o fato do próprio mandato (a RLS de campo_extraido, documento, entidade e periodo vale para quem lê) e NINGUÉM escreve nela. A identidade é a SEÇÃO (nó de conta_canonica; folha é a P28+). Todas as versões do documento; quem consome escolhe a vigente com fn_versao_atual. '
  'resolucao_metodo: declarada (a IA deu a seção), heuristica (fn_secao_canonica_da_secao_bruta / fn_herdar_secao_pela_arvore, 0203/0204: secao_canonica_inferida) ou sem_conta (conta_id nulo, com o motivo): "não sei a conta" é estado, nunca um palpite. Filtre por caso_id ou documento_versao_id: é o que poda o cálculo.';
comment on column fato_financeiro.id is 'IGUAL a campo_extraido_id: a identidade do fato é a da linha extraída que o sustenta (1:1). Não há uuid próprio porque não há linha gravada.';
comment on column fato_financeiro.conta_id is 'Nó de conta_canonica que é SEÇÃO (secao_canonica não nula). NULL só com resolucao_metodo = sem_conta: linha sem seção declarada, ou com seção que o catálogo não conhece, NÃO ganha conta inventada — nem a raiz da demonstração pelo tipo do documento.';
comment on column fato_financeiro.entidade_origem is 'De onde veio a entidade. A 0243 NÃO interpreta nome de coluna: a entidade da coluna é a que fn_coluna_entidade(versão, entidade) (0023/0030, com fn_mesma_entidade) escolhe para alguma entidade do mandato. coluna = casou pelo NOME da entidade; coluna_total = a coluna Combinado/Consolidado/Total/Soma que a mesma função entrega à entidade do documento (só quando nenhuma coluna casa o nome dela); documento = a linha não tem entidade_coluna (entidade do documento). NULL = a função não escolheu a coluna, ou escolheu para mais de uma entidade: entidade_motivo diz por quê (documento_sem_entidade, coluna_sem_entidade_no_mandato, coluna_casa_varias_entidades, entidade_com_varias_colunas, coluna_total_nao_escolhida, coluna_total_ambigua, linha_sem_coluna_em_documento_com_colunas_de_entidade). A entidade_coluna da linha fica ao lado.';
comment on column fato_financeiro.periodo_origem is 'De onde veio o período. A 0243 NÃO interpreta nome de coluna: só atribui o período quando as funções do banco para essa pergunta decidem de forma INEQUÍVOCA. documento = a linha sem coluna num documento sem colunas, ou a coluna que É o período do documento: a ÚNICA coluna de saldo (fn_coluna_e_saldo: Saldo final/atual, 0201) ou, na falta de saldo, a ÚNICA coluna que nomeia só o ano do documento num documento não parcial (fn_periodo_e_parcial, 0199 c); coluna = coluna de ano puro (31/12/AAAA = AAAA) de OUTRO ano, em documento não parcial, que um período do mesmo mandato tem (fn_periodo_canonico). NULL = ambíguo ou sem base; periodo_motivo diz por quê (coluna_nao_e_o_periodo_do_documento, coluna_de_abertura, periodo_da_coluna_nao_cadastrado: o período NÃO é criado aqui, mais_de_uma_coluna_para_o_mesmo_periodo, linha_sem_coluna_em_documento_com_colunas, documento_sem_periodo). O periodo_coluna da linha fica ao lado.';
comment on column fato_financeiro.valor is 'valor_num da linha, como veio. Escala e moeda NÃO são normalizadas aqui (não há regra pronta): unidade e moeda seguem ao lado.';

-- O fato é DERIVADO: ninguém escreve nele (a view tem junção e função na cláusula FROM, não é atualizável, e mesmo assim os privilégios saem). REVOKE antes do GRANT: o `pg_default_acl` do dono dá ALL a authenticated e service_role em toda tabela e view nova de `public` (medido em produção
-- em 12/11/2026: 46 de 52 tabelas); sem o revoke o authenticated nasceria com INSERT/UPDATE/DELETE/TRUNCATE na view e o anon com o que o default der. O teste SIMULA esse default (tabela e função), descarta a view e as funções e reaplica a migration.
revoke all on fato_financeiro from public, anon, authenticated, service_role;
grant select on fato_financeiro to authenticated, service_role;

-- O resolver não é do anon nem de PUBLIC (o default de função do Supabase dá EXECUTE ao anon em toda função nova): o anon já não lê campo_extraido, mas quem lê o resolver sem precisar não deve poder.
-- (revoga de TODOS e concede só o que cada função precisa: o ACL fica o mesmo com ou sem o default de privilégio do Supabase, e o teste confere que fica)
revoke all on function fn_fato_resolver(uuid), fn_tipo_gera_fato(text), fn_linha_vira_fato(text, text, text, numeric) from public, anon, authenticated, service_role;
revoke all on function fn_fato_ator(), fn_fato_pode_escrever(uuid) from public, anon, authenticated, service_role;   -- internas: só o dono (as funções security definer as chamam como dono)

-- A CADEIA EXECUTÁVEL. A view é security_invoker: quem a lê executa o resolver e TODA função que ele chama com o próprio privilégio (o EXECUTE de função não é do dono da view). Se produção não der EXECUTE de PUBLIC nestas funções antigas (o Supabase impede
-- EXECUTE público em função nova; o que as 0000-0242 receberam não foi conferido aqui), a view seria ilegível ao portal com "permission denied for function". Concede explicitamente ao authenticated, ao service_role e ao leitor só-leitura (idempotente: onde já havia, não muda nada). A lista é o
-- fecho das chamadas do resolver, achado por varredura do corpo (nome de função seguido de parêntese, recursivo; unaccent é de extensão e não entra): a sonda `cadeia` confere os 17 contra o authenticated e o service_role, e o teste de ACL estrito prova que a lista basta.
do $cadeia$
declare
  v_f text;
  v_papeis text[] := array['authenticated', 'service_role'];
  v_p text;
begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    v_papeis := array_append(v_papeis, 'supabase_read_only_user'::text);
  end if;
  foreach v_f in array array[
    'fn_fato_resolver(uuid)', 'fn_tipo_gera_fato(text)', 'fn_linha_vira_fato(text, text, text, numeric)', 'fn_papel_linha(text, text, text)', 'fn_sem_codigo_de_conta(text)',
    'fn_tokens_estruturais(text)', 'fn_mes_do_rotulo(text)', 'fn_ano4(text)', 'fn_anos_periodo(text, text)', 'fn_coluna_e_abertura(text)', 'fn_coluna_e_saldo(text)',
    'fn_coluna_entidade(uuid, uuid)', 'fn_entidade_canonica(text)', 'fn_mesma_entidade(text, text)', 'fn_normalizar_texto(text)', 'fn_periodo_canonico(text, text)',
    'fn_periodo_e_parcial(text, text, text, text)'] loop
    foreach v_p in array v_papeis loop
      execute format('grant execute on function %s to %I', v_f, v_p);
    end loop;
  end loop;
end $cadeia$;

-- -----------------------------------------------------------------------------
-- A PENDÊNCIA da conta incerta: a ÚNICA coisa que esta migration ainda ESCREVE (o fato é lido, não gravado). UMA por documento-versão, só para extração NOVA.
-- Lê o resolver (a mesma definição de "o fato"), não uma cópia: conta resolvida por heurística ou sem conta. Só mexe em estado 'aberta': a que alguém está tratando (em correção, reenviada ao cliente) ou decidiu (aceita com ressalva, rejeitada, resolvida por pessoa) fica como está.
-- -----------------------------------------------------------------------------
create or replace function fn_fato_pendencia_da_versao(p_documento_versao_id uuid)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_caso uuid; v_doc uuid; v_nome text;
  v_h int; v_s int; v_lista text; v_desc text; v_pend uuid; v_vigente uuid;
  v_motivo text := 'fato:conta_incerta:' || p_documento_versao_id;
begin
  select d.caso_id, d.id, dv.nome_original into v_caso, v_doc, v_nome
    from documento_versao dv join documento d on d.id = dv.documento_id where dv.id = p_documento_versao_id;
  if v_doc is null then return null; end if;
  if not fn_fato_pode_escrever(v_caso) then
    raise exception 'fn_fato_pendencia_da_versao: sem permissão de escrita no mandato' using errcode = 'insufficient_privilege';
  end if;

  -- versão que NÃO é a vigente (fn_versao_atual): a leitura que ela traz foi superada, não se abre pendência sobre ela (e a aberta se baixa abaixo, pelo ramo de "sem linha incerta")
  v_vigente := fn_versao_atual(v_doc);

  select count(*) filter (where x.resolucao_metodo = 'heuristica'), count(*) filter (where x.resolucao_metodo = 'sem_conta'),
         string_agg(x.rotulo, '; ' order by x.rn) filter (where x.rn <= 12)
    into v_h, v_s, v_lista
    from (select r.resolucao_metodo,
                 ce.chave || case r.resolucao_metodo
                               when 'heuristica' then ' [seção inferida: ' || coalesce(ce.secao_canonica, '?') || ']'
                               else ' [sem seção' || case when r.sem_conta_motivo = 'secao_fora_do_catalogo' then ': "' || coalesce(ce.secao_canonica, '') || '" não está no catálogo' else '' end || ']' end as rotulo,
                 row_number() over (order by ce.ordem nulls last, ce.id) as rn
            from fn_fato_resolver(p_documento_versao_id) r join campo_extraido ce on ce.id = r.campo_id
           where r.resolucao_metodo <> 'declarada') x;

  select id into v_pend from pendencia where caso_id = v_caso and motivo = v_motivo and estado = 'aberta' limit 1;

  if v_vigente is distinct from p_documento_versao_id then
    v_h := 0; v_s := 0;
  end if;

  if v_h + v_s > 0 then
    v_desc := format('%s linha(s) de "%s" ficaram com a conta canônica por HEURÍSTICA (%s: a IA não deu a seção, ela foi inferida do texto da seção ou da árvore do documento) ou SEM conta (%s: sem seção, ou com uma que o catálogo não conhece). '
                     'Linha sem conta é fato sem identidade: não entra em nenhuma seção até alguém dizer qual é. Confirme a seção destas linhas%s: %s%s',
                     v_h + v_s, coalesce(v_nome, '?'), v_h, v_s,
                     case when v_h + v_s > 12 then ' (as 12 primeiras de ' || (v_h + v_s) || ')' else '' end,
                     v_lista, '.');
    if v_pend is not null then
      update pendencia set descricao = v_desc where id = v_pend;
    elsif not exists (select 1 from pendencia where caso_id = v_caso and motivo = v_motivo
                         and (estado <> 'resolvida' or coalesce(resolvida_por, '') not like 'sistema:%')) then
      -- (viva em outro estado, ou resolvida por uma PESSOA: não se abre outra; decisão humana não se desfaz, 0231)
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso, 'extracao', 'conta_canonica_incerta', 'complementar', true, v_desc, v_doc, v_motivo)
        returning id into v_pend;
    end if;
  elsif v_pend is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = case when v_vigente is distinct from p_documento_versao_id then 'sistema:versao_superada' else 'sistema:extracao' end where id = v_pend;
    v_pend := null;
  end if;
  return v_pend;
end $$;
comment on function fn_fato_pendencia_da_versao(uuid) is
  '0243: a pendência conta_canonica_incerta (motivo fato:conta_incerta:<versão>), UMA por documento-versão, listando as linhas resolvidas (por fn_fato_resolver) por heurística ou sem conta (as 12 primeiras no texto). Reabre-se sozinha no texto e se resolve sozinha quando não sobra linha incerta; só toca estado aberta. Em outro estado, ou resolvida por pessoa, não é reaberta. Complementar e sobrepujável: não trava o mandato, avisa. Só o gatilho da extração nova a chama.';

-- -----------------------------------------------------------------------------
-- O ÚNICO GATILHO: o evento `extracao_sombra` (a prova de que a extração RODOU, regra 7), que fn_registrar_campos_extraidos grava DEPOIS do laço de inserção e DEPOIS da herança da seção pela árvore (0204): as duas únicas coisas que mudam o que a pendência lê (seção, flag de inferida).
-- NÃO reemite fn_registrar_campos_extraidos (decisão do dono, 12/11/2026): a 0270 (P11, APLICADA em produção) a reemitiu para gravar campo_extraido.ln e a P11 a reemite a cada fatia; a 0243 não depende do corpo dela e, no banco do zero (0243 antes da 0270) e em produção (0243 depois), o `ln` continua gravado.
-- Só a extração nova abre pendência: o que já estava gravado (as versões antigas) não tem evento novo e não abre; a transcrição humana (fn_registrar_transcricao_humana, 0129) não grava extracao_sombra e a pessoa que a digitou é a autoridade da seção (decisão no cabeçalho); a mudança de tipo do documento também não abre.
-- Não grava fato: o fato é a view. A falha da pendência NÃO derruba a extração (a evidência vale mais que o derivado): sub-bloco que grava o evento `fato_pendencia_falhou` e segue. NÃO se captura query_canceled: o cancelamento é do chamador.
-- -----------------------------------------------------------------------------
create or replace function fn_fato_pendencia_da_extracao()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare v_versao uuid; v_tipo text; v_caso uuid; v_doc uuid; v_pend uuid; v_vigente uuid;
begin
  -- entidade_ref = 'documento_versao:<uuid>'; qualquer outra forma (evento sintético, uuid inválido) não é extração de versão nenhuma: não faz nada, e NÃO derruba o evento
  if new.entidade_ref ~ '^documento_versao:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    v_versao := substr(new.entidade_ref, length('documento_versao:') + 1)::uuid;
    select d.tipo_taxonomia, d.caso_id, d.id into v_tipo, v_caso, v_doc from documento_versao dv join documento d on d.id = dv.documento_id where dv.id = v_versao;
    if not fn_tipo_gera_fato(v_tipo) then
      return null;   -- (tipo fora da lista, ou versão inexistente: não rodou e não finge)
    end if;
    if not fn_fato_pode_escrever(v_caso) then
      -- (regra 7: a recusa deixa rastro, não é silêncio)
      insert into evento_auditoria (ator, acao, entidade_ref, depois)
        values (coalesce(fn_fato_ator(), new.ator), 'fato_pendencia_negada', new.entidade_ref, jsonb_build_object('porque', 'sem permissão de escrita no mandato', 'ator_declarado', new.ator));
      return null;
    end if;
    -- A TRAVA DO DOCUMENTO (corrida R4, medida com duas sessões): duas extrações concorrentes de duas versões do MESMO documento avaliavam cada uma com o snapshot que não enxerga as linhas da outra, e a pendência da versão superada ficava aberta para sempre
    -- (a v2 e a v3 abertas ao mesmo tempo). A trava é por documento e dura até o fim da transação da extração (milissegundos): a segunda avalia DEPOIS do commit da primeira, com o estado novo (a v3 vigente baixa a da v2).
    perform pg_advisory_xact_lock(hashtextextended('fato:conta_incerta:' || v_doc::text, 0));
    begin
      v_pend := fn_fato_pendencia_da_versao(v_versao);
      -- A VERSÃO SUPERADA: quando esta é a vigente (fn_versao_atual), a pendência ABERTA das outras versões do documento perde o sentido (a leitura que ela julgava não é mais a que vale).
      v_vigente := fn_versao_atual(v_doc);
      if v_vigente = v_versao then
        update pendencia
           set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:versao_superada',
               descricao = coalesce(descricao, '') || ' — Resolvida automaticamente: versão superada pela versão ' || v_versao || ' do documento.'
         where documento_id = v_doc and estado = 'aberta' and motivo like 'fato:conta_incerta:%' and motivo <> 'fato:conta_incerta:' || v_versao;
      end if;
      -- o sinal de que RODOU (regra 7): a avaliação da pendência desta versão, com o que ela decidiu
      insert into evento_auditoria (ator, acao, entidade_ref, depois)
        values (new.ator, 'fato_pendencia_avaliada', new.entidade_ref, jsonb_build_object('pendencia_id', v_pend, 'versao_vigente', v_vigente = v_versao));
    exception
      when query_canceled then raise;
      when others then
        insert into evento_auditoria (ator, acao, entidade_ref, depois)
          values (new.ator, 'fato_pendencia_falhou', new.entidade_ref,
                  jsonb_build_object('sqlstate', sqlstate, 'erro', sqlerrm, 'porque', 'a extração foi gravada; a pendência da conta incerta não. O fato (a view) não depende dela. Rode select fn_fato_pendencia_da_versao(<versão>) para avaliá-la de novo.'));
    end;
  end if;
  return null;
end $$;
comment on function fn_fato_pendencia_da_extracao() is
  '0243: gatilho de evento_auditoria (acao = extracao_sombra, o evento que fn_registrar_campos_extraidos grava depois da herança da seção): abre/atualiza/baixa a pendência conta_canonica_incerta da versão recém-extraída (fn_fato_pendencia_da_versao) e baixa a das versões superadas. NÃO grava fato (o fato é a view fato_financeiro). Só extração nova: versão antiga, transcrição humana e mudança de tipo não passam por aqui.';

revoke all on function fn_fato_pendencia_da_versao(uuid), fn_fato_pendencia_da_extracao() from public, anon, authenticated, service_role;
grant execute on function fn_fato_pendencia_da_versao(uuid) to service_role;   -- o reparo/avaliação manual do serviço; a do gatilho é só do dono (o gatilho a chama sem precisar de EXECUTE de quem inseriu o evento)

drop trigger if exists trg_fato_pendencia_da_extracao on evento_auditoria;
create trigger trg_fato_pendencia_da_extracao after insert on evento_auditoria
  for each row when (new.acao = 'extracao_sombra') execute function fn_fato_pendencia_da_extracao();

set local lock_timeout = 0;

-- -----------------------------------------------------------------------------
-- As VIEWS da sonda (padrão da 0224/0242: uma linha = uma garantia presente). Rodam com o privilégio de quem LÊ nas FUNÇÕES que chamam (o EXECUTE não é do dono da view), e é por isso que o leitor só-leitura recebe o grant de cada uma.
-- -----------------------------------------------------------------------------

-- A VIEW É A VIEW CERTA: fato_financeiro é view (não tabela), com security_invoker ligado, sobre fn_fato_resolver, e o resolver NÃO é security definer (definer pularia a RLS que a view existe para respeitar). Uma linha = os quatro fatos juntos.
create or replace view instalacao_sonda_fato_financeiro_view_invoker as
  select 1 as ok
   where exists (select 1 from pg_class c where c.oid = 'public.fato_financeiro'::regclass and c.relkind = 'v'
                  and exists (select 1 from pg_options_to_table(c.reloptions) o where o.option_name = 'security_invoker' and lower(o.option_value) in ('true', 'on', 'yes', '1', 't')))
     and pg_get_viewdef('public.fato_financeiro'::regclass) like '%fn_fato_resolver(%'
     and exists (select 1 from pg_proc p where p.oid = 'public.fn_fato_resolver(uuid)'::regprocedure and not p.prosecdef);
comment on view instalacao_sonda_fato_financeiro_view_invoker is
  'Sonda da 0243: uma linha = fato_financeiro é VIEW com security_invoker = true, definida sobre fn_fato_resolver, e o resolver não é security definer. Zero linhas: a view roda com o privilégio do dono e o authenticated lê o fato de TODOS os mandatos (a RLS de campo_extraido e documento é pulada), ou a view deixou de calcular pelo resolver.';

-- NINGUÉM ESCREVE NA VIEW e o anon não lê: o authenticated só SELECT, o service_role só SELECT, o anon nada (nem coluna).
create or replace view instalacao_sonda_fato_financeiro_so_le as
  select 1 as ok
   where has_table_privilege('authenticated', 'public.fato_financeiro'::regclass, 'select')
     and has_table_privilege('service_role', 'public.fato_financeiro'::regclass, 'select')
     and not has_any_column_privilege('authenticated', 'public.fato_financeiro'::regclass, 'insert')
     and not has_any_column_privilege('authenticated', 'public.fato_financeiro'::regclass, 'update')
     and not has_table_privilege('authenticated', 'public.fato_financeiro'::regclass, 'delete')
     and not has_table_privilege('authenticated', 'public.fato_financeiro'::regclass, 'truncate')
     and not has_any_column_privilege('service_role', 'public.fato_financeiro'::regclass, 'insert')
     and not has_any_column_privilege('service_role', 'public.fato_financeiro'::regclass, 'update')
     and not has_table_privilege('service_role', 'public.fato_financeiro'::regclass, 'delete')
     and not has_any_column_privilege('anon', 'public.fato_financeiro'::regclass, 'select')
     and not has_any_column_privilege('anon', 'public.fato_financeiro'::regclass, 'insert')
     and not has_function_privilege('anon', 'public.fn_fato_resolver(uuid)'::regprocedure, 'execute');
comment on view instalacao_sonda_fato_financeiro_so_le is
  'Sonda da 0243: uma linha = o authenticated e o service_role só LEEM fato_financeiro (nenhum privilégio de escrita, nem de coluna), o anon não tem acesso a ela nem ao resolver. Zero linhas: o fato derivado voltou a ser gravável pelo portal, ou o anon o lê (o default de privilégio do Supabase dá ALL a toda view nova se a migration não revogar).';

-- A LEITURA FUNCIONA SOBRE O QUE CHEGOU AGORA (regra 7: o estágio que não rodou não parece limpo): as 3 versões mais novas de documento de demonstração com linha de EXTRAÇÃO, resolvidas por fn_fato_resolver, concordam com o que as linhas dizem hoje: toda linha elegível (fn_linha_vira_fato) tem fato,
-- a conta é o nó da seção da linha (ou sem_conta se o catálogo não a conhece), o método é declarada/heuristica pela flag secao_canonica_inferida, e nenhum fato nasce de linha que não é elegível. Roda como DEFINER (função auxiliar abaixo): o resolver dentro de uma view de sonda corre com a RLS de QUEM LÊ, e um Analista veria
-- só as versões do mandato dele (a amostra é global); o leitor só-leitura também ganha só o EXECUTE desta função. Uma AMOSTRA de 3 (entre as 30 mais novas, só de até 1.500 linhas), porque a sonda não cresce com o dado (0132) e cada versão custa uma resolução (~0,55 s numa versão de 4.000 linhas distintas, mais a pergunta independente por linha: 4 s para três versões de 4.000; com o teto de 1.500 linhas, ~0,3 s). Banco SEM versão de demonstração com linha de extração: ausente (nada a medir não é prova de que mede).
create or replace function fn_fato_sonda_recentes()
returns bigint language sql stable security definer set search_path = public, pg_temp set jit = off as $$
  with recentes as materialized (
    select dv.id, d.tipo_taxonomia, dv.criada_em
      from documento_versao dv join documento d on d.id = dv.documento_id
     where fn_tipo_gera_fato(d.tipo_taxonomia)
       and exists (select 1 from campo_extraido x where x.documento_versao_id = dv.id and x.origem_valor = 'extracao' and x.valor_num is not null)
     order by dv.criada_em desc, dv.id limit 30),
  -- as 3 mais novas, entre as 30 mais novas, de até 1.500 linhas: o custo da sonda tem TETO (medido: 3 versões de 4.000 linhas custavam 4 s por leitura da sonda inteira; com o teto, ~0,3 s)
  v as materialized (
    select id, tipo_taxonomia from recentes where (select count(*) from campo_extraido x where x.documento_versao_id = recentes.id) <= 1500 order by criada_em desc, id limit 3),
  r as materialized (select r.* from v cross join lateral fn_fato_resolver(v.id) r),
  -- as linhas elegíveis das 3 versões, pela pergunta INDEPENDENTE (fn_linha_vira_fato por linha, sem passar pelo resolver)
  e as materialized (
    select ce.id, ce.secao_canonica, ce.secao_canonica_inferida
      from v join campo_extraido ce on ce.documento_versao_id = v.id and ce.origem_valor = 'extracao'
     where fn_linha_vira_fato(v.tipo_taxonomia, ce.chave, ce.unidade, ce.valor_num)),
  -- (uma junção por igualdade, não um `not exists` correlacionado contra a CTE: medido, o correlacionado leva 12 s com 3 versões de 4.000 linhas, a junção ~1 s)
  achado as materialized (
    select e.id, e.secao_canonica, e.secao_canonica_inferida, r.campo_id, r.resolucao_metodo, r.conta_id, c.secao_canonica as secao_da_conta
      from e left join r on r.campo_id = e.id left join conta_canonica c on c.codigo = r.conta_id)
  select case when not exists (select 1 from v) then -1 else
    -- linha elegível sem fato, ou com fato de conta/método diferentes da linha (a conta é o nó da seção; sem_conta só se o catálogo não conhece a seção)
    (select count(*) from achado a
      where a.campo_id is null
         or a.resolucao_metodo <> case when a.conta_id is null then 'sem_conta' when a.secao_canonica_inferida then 'heuristica' else 'declarada' end
         or (a.conta_id is not null and a.secao_da_conta is distinct from a.secao_canonica)
         or (a.conta_id is null and exists (select 1 from conta_canonica c2 where c2.secao_canonica = a.secao_canonica)))
    -- fato de linha que NÃO é elegível: o resolver é injetivo (um fato por linha), então sobra fato se há mais fatos do que linhas elegíveis com fato
    + ((select count(*) from r) - (select count(*) from achado a where a.campo_id is not null))
  end
$$;
comment on function fn_fato_sonda_recentes() is
  '0243: quantas divergências há entre as 3 versões de demonstração mais novas (com linha de extração) e o fato que o resolver devolve para elas (linha elegível sem fato, fato de conta ou método diferentes da linha, fato de linha não elegível); -1 se não há versão a medir. security definer só para a RLS do chamador não mudar a amostra; devolve um número, nenhum dado.';
revoke all on function fn_fato_sonda_recentes() from public, anon, authenticated, service_role;
grant execute on function fn_fato_sonda_recentes() to authenticated, service_role;

create or replace view instalacao_sonda_fato_financeiro_recentes as
  select 1 as ok where fn_fato_sonda_recentes() = 0;
comment on view instalacao_sonda_fato_financeiro_recentes is
  'Sonda da 0243: uma linha = as 3 versões de demonstração mais novas com linha de extração têm fato para toda linha elegível, e o fato concorda com a linha (conta = a seção dela, método pela flag de inferida). Zero linhas: o resolver falha ou diverge da linha (função da cadeia sem grant, corpo trocado), ou não há versão de demonstração a medir (-1: ausente, não verde). Não depende de evento nem de gatilho: o fato é calculado.';

-- A CADEIA EXECUTÁVEL: as 17 funções do fecho do resolver executáveis pelo authenticated e pelo service_role (e pelo leitor só-leitura, quando o papel existe). Uma linha por função. Menos de 17: a view fato_financeiro fica ilegível para o portal ("permission denied for function ...").
create or replace view instalacao_sonda_fato_financeiro_cadeia as
  select f.nome::text as funcao
    from (values ('fn_fato_resolver(uuid)'), ('fn_tipo_gera_fato(text)'), ('fn_linha_vira_fato(text, text, text, numeric)'), ('fn_papel_linha(text, text, text)'), ('fn_sem_codigo_de_conta(text)'),
                 ('fn_tokens_estruturais(text)'), ('fn_mes_do_rotulo(text)'), ('fn_ano4(text)'), ('fn_anos_periodo(text, text)'), ('fn_coluna_e_abertura(text)'), ('fn_coluna_e_saldo(text)'),
                 ('fn_coluna_entidade(uuid, uuid)'), ('fn_entidade_canonica(text)'), ('fn_mesma_entidade(text, text)'), ('fn_normalizar_texto(text)'), ('fn_periodo_canonico(text, text)'),
                 ('fn_periodo_e_parcial(text, text, text, text)')) f(nome)
   where has_function_privilege('authenticated', f.nome, 'execute')
     and has_function_privilege('service_role', f.nome, 'execute')
     and (not exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') or has_function_privilege('supabase_read_only_user', f.nome, 'execute'));
comment on view instalacao_sonda_fato_financeiro_cadeia is
  'Sonda da 0243: uma linha = uma das 17 funções que o resolver chama (o fecho) é executável pelo authenticated, pelo service_role e pelo leitor só-leitura. Menos de 17: a view fato_financeiro (security_invoker: o EXECUTE é de quem lê) fica ilegível para o portal.';

create or replace view instalacao_sonda_fato_financeiro_pendencia_tipo as
  select 1 as ok where exists (select 1 from pg_enum e where e.enumtypid = 'pendencia_tipo'::regtype and e.enumlabel = 'conta_canonica_incerta');
comment on view instalacao_sonda_fato_financeiro_pendencia_tipo is
  'Sonda da 0243: uma linha = o rótulo conta_canonica_incerta existe em pendencia_tipo. Sem ele a extração nova com linha heurística tentaria abrir a pendência e falharia (a falha é engolida e vira o evento fato_pendencia_falhou).';

-- A LISTA DOS TIPOS, um a um e INDEPENDENTE do corpo da função: os 8 tipos de demonstração geram fato e 2 que NÃO podem gerar (Razão e Notas, da mesma categoria da taxonomia) não geram. Uma linha por resposta certa: 10 = a lista inteira.
create or replace view instalacao_sonda_fato_financeiro_tipos as
  select e.tipo::text as tipo
    from (values ('BALANCO', true), ('BALANCETE', true), ('COMBINADO', true), ('DRE', true), ('FLUXO_CAIXA', true), ('DVA', true), ('DMPL', true), ('DF_AUDITADA', true), ('RAZAO', false), ('NOTAS_EXPL', false)) e(tipo, gera)
   where fn_tipo_gera_fato(e.tipo) = e.gera;
comment on view instalacao_sonda_fato_financeiro_tipos is
  'Sonda da 0243: uma linha = fn_tipo_gera_fato dá a resposta certa para um dos 10 tipos (BALANCO, BALANCETE, COMBINADO, DRE, FLUXO_CAIXA, DVA, DMPL, DF_AUDITADA geram; RAZAO e NOTAS_EXPL não). Menos de 10: um tipo de demonstração perdeu o fato, ou o que é só evidência virou fato.';

grant select on instalacao_sonda_fato_financeiro_view_invoker, instalacao_sonda_fato_financeiro_so_le, instalacao_sonda_fato_financeiro_recentes, instalacao_sonda_fato_financeiro_cadeia,
                instalacao_sonda_fato_financeiro_pendencia_tipo, instalacao_sonda_fato_financeiro_tipos to authenticated, service_role;  -- service_role: grant_views_service_role (0214)

-- O LEITOR SÓ-LEITURA (`supabase_read_only_user`): as views da sonda chamam as funções acima com o privilégio de quem LÊ; sem o grant a sonda INTEIRA fica ilegível para quem lê produção sem escrever (o defeito que a 0242 teve em 11/11/2026). As 17 da cadeia já foram dadas acima; esta é a da amostra.
-- Supabase/test/sonda_para_o_leitor_somente_leitura.test.sql o prova.
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    execute 'grant execute on function fn_fato_sonda_recentes() to supabase_read_only_user';
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- A SONDA. Marcadores em CÓDIGO, nunca de comentário.
-- -----------------------------------------------------------------------------
-- Os requisitos desta migration são REESCRITOS por inteiro: a lista da versão anterior (a tabela e as materializações) deixou de fazer sentido e não pode ficar ausente para sempre num banco que a aplicou.
delete from instalacao_requisito where migration = '0243';
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fato_financeiro_view_invoker', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_view_invoker', null, 1,
   'fato_financeiro não é view com security_invoker sobre o resolver, ou o resolver virou security definer: a view roda com o privilégio do dono e o portal lê o fato de TODOS os mandatos.', 'importante', 1105),
  ('fato_financeiro_so_le', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_so_le', null, 1,
   'O authenticated ou o service_role ganharam privilégio de escrita em fato_financeiro, ou o anon passou a lê-la: o fato é derivado e a escrita não existe.', 'importante', 1106),
  ('fato_financeiro_le_as_versoes_recentes', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_recentes', null, 1,
   'O resolver não devolve fato para linha elegível das 3 versões de demonstração mais novas, ou devolve fato que discorda da linha (conta, método): a leitura do fato está quebrada (função da cadeia sem grant, corpo trocado) ou não há versão a medir.', 'importante', 1107),
  ('fato_financeiro_cadeia_executavel', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_cadeia', null, 17,
   'Alguma das 17 funções do fecho do resolver não é executável pelo authenticated, pelo service_role ou pelo leitor só-leitura: a view fato_financeiro (security_invoker) fica ilegível para o portal.', 'importante', 1108),
  ('fato_financeiro_pendencia_tipo', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_pendencia_tipo', null, 1,
   'Sem o rótulo conta_canonica_incerta em pendencia_tipo a pendência da heurística não abre.', 'importante', 1109),
  ('tipos_que_geram_fato', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_tipos', null, 10,
   'A lista dos tipos de demonstração perdeu um tipo (linha de demonstração fica sem fato), ou ganhou Razão/Notas (o que é só evidência vira fato). Conferida tipo a tipo, não pelo corpo.', 'importante', 1110),
  ('pendencia_conta_gatilho', '0243', 'gatilho', 'evento_auditoria.trg_fato_pendencia_da_extracao', 'fn_fato_pendencia_da_extracao', null,
   'Sem o gatilho a extração nova com linha de conta incerta NÃO abre a pendência conta_canonica_incerta (a heurística fica calada). A pendência mora no gatilho, não em fn_registrar_campos_extraidos, que a P11 reemite a cada fatia.', 'importante', 1111),
  ('pendencia_conta_gatilho_chama', '0243', 'corpo', 'fn_fato_pendencia_da_extracao', 'fn_fato_pendencia_da_versao(v_versao)', null,
   'O gatilho existe mas não chama a avaliação da pendência: o evento extracao_sombra passa e nenhuma pendência abre, sem erro.', 'importante', 1112),
  ('pendencia_conta_chama_a_guarda', '0243', 'corpo', 'fn_fato_pendencia_da_extracao', 'fn_fato_pode_escrever(v_caso)', null,
   'O gatilho é security definer: sem chamar a guarda, um evento extracao_sombra forjado abre pendência em qualquer mandato.', 'importante', 1113),
  ('pendencia_uma_por_versao', '0243', 'corpo', 'fn_fato_pendencia_da_versao', '''fato:conta_incerta:''', null,
   'A pendência da heurística é UMA por documento-versão (o motivo carrega a versão). Outro motivo = uma por linha (fila de ruído) ou nenhuma.', 'importante', 1114),
  ('pendencia_le_o_resolver', '0243', 'corpo', 'fn_fato_pendencia_da_versao', 'fn_fato_resolver(', null,
   'A pendência precisa ler a MESMA definição de fato que a view (o resolver): outra consulta é uma segunda implementação da conta, e as duas divergem sem erro nenhum.', 'importante', 1115),
  ('materializa_so_o_elegivel', '0243', 'corpo', 'fn_fato_resolver', 'fn_linha_vira_fato(', null,
   'A resolução precisa perguntar a fn_linha_vira_fato: sem isso virar fato é "tudo que tem valor" (Estoque, Razão, subtotal).', 'importante', 1116),
  ('materializa_periodo_pela_coluna', '0243', 'corpo', 'fn_fato_resolver', 'fn_periodo_canonico(', null,
   'O período de outro ano vem da forma canônica da coluna de ano puro (31/12/AAAA = AAAA) que um período do MESMO mandato tem; sem isso o balanço de duas colunas de ano atribui o saldo de 2024 a 2025.', 'importante', 1117),
  ('periodo_so_da_coluna_de_saldo', '0243', 'corpo', 'fn_fato_resolver', 'fn_coluna_e_saldo(', null,
   'A coluna que É o período do documento é a de SALDO (fn_coluna_e_saldo, 0201): Débito, Crédito, Orçado, Variação e percentual com o mesmo período dão fatos idênticos em (conta, entidade, período) e a soma dobra.', 'importante', 1118),
  ('periodo_parcial_nao_vai_para_o_ano', '0243', 'corpo', 'fn_fato_resolver', 'fn_periodo_e_parcial(', null,
   'Documento de período PARCIAL (balancete de junho) não dá a coluna "2025" ao período anual: o acumulado de junho virava a receita do ano.', 'importante', 1119),
  ('periodo_coluna_do_documento_so_se_unica', '0243', 'corpo', 'fn_fato_resolver', 'mais_de_uma_coluna_para_o_mesmo_periodo', null,
   'Com duas candidatas a ser a coluna do período do documento (Jun/2025 e 30/06/2025; Saldo final e Saldo atual) nenhuma é escolhida: fn_coluna_periodo_do_ano desempata por contagem e ordem alfabética, e "ao acaso" é número fabricado (a soma de 4 colunas deu 500).', 'importante', 1120),
  ('entidade_pela_funcao_do_banco', '0243', 'corpo', 'fn_fato_resolver', 'fn_coluna_entidade(', null,
   'A entidade da coluna é a que fn_coluna_entidade (0023/0030, com fn_mesma_entidade) escolhe: um casamento de nome próprio errou "Alfa Comércio" x "ALFA COMERCIO DE ALIMENTOS LTDA" e deu o Consolidado à ALFA com a coluna dela nula.', 'importante', 1121),
  ('entidade_total_so_se_unica', '0243', 'corpo', 'fn_fato_resolver', 'coluna_total_ambigua', null,
   'fn_coluna_entidade entrega "a" coluna total sem ordem: com mais de uma coluna total no documento a escolha é arbitrária e a entidade fica sem coluna total.', 'importante', 1122),
  ('fato_guarda_de_escrita_corpo', '0243', 'corpo', 'fn_fato_pode_escrever', 'fn_pode_escrever_caso(p_caso)', null,
   'A guarda de escrita (serviço ou quem escreve no mandato) foi trocada (por `select true`, por exemplo): a função security definer abre pendência para qualquer chamador.', 'importante', 1123),
  ('fato_guarda_de_escrita_search_path', '0243', 'corpo', 'fn_fato_pode_escrever', 'SET search_path TO ''public'', ''pg_temp''', null,
   'Função security definer sem search_path fixo: um schema do chamador na frente do public sequestra fn_pode_escrever_caso.', 'importante', 1124)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0243', revisado_em = current_date,
       observacao = 'A 0243 cria fato_financeiro como VIEW security_invoker sobre fn_fato_resolver (o fato acima de campo_extraido: conta = seção, entidade e período pela coluna da linha quando uma função do banco decide), a pendência conta_canonica_incerta (uma por versão, só extração nova, por gatilho em evento_auditoria), 6 views de sonda, 1 função de amostra e 20 requisitos novos (ordem 1105-1124). Não reemite fn_registrar_campos_extraidos nem fn_fundir_entidade.'
 where id = true;

commit;
