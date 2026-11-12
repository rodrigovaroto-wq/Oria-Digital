-- 0243 — A LINHA QUE NÃO TINHA IDENTIDADE: `fato_financeiro` acima de `campo_extraido` (P27, Fase 3, etapa 3.2) — o fato canônico (conta = a SEÇÃO da linha, entidade e período pela coluna da linha quando ela diz), a pendência da heurística e o backfill que não abre fila.
-- (Cria 1 tabela, fato_financeiro, as funções fn_tipo_gera_fato, fn_linha_vira_fato, fn_fato_resolver, fn_fato_pode_escrever, fn_materializar_fatos, fn_fato_pendencia_da_versao, fn_materializar_fatos_da_extracao, fn_fato_recalcular, fn_fato_recalcular_caso, fn_materializar_fatos_do_caso, fn_materializar_fatos_backfill e as dos 3 gatilhos de função (documento, mesmo mandato, extração nova), 1 gatilho em documento, 1 em evento_auditoria, 1 em fato, 2 em periodo/entidade, 1 rótulo de pendencia_tipo
--  (conta_canonica_incerta), 6 views da sonda e 32 requisitos novos (ordem 1105-1140). Reemite INTEIRA fn_fundir_entidade (corpo da 0213, conferido igual ao do banco montado; repõe os fatos). NÃO reemite fn_registrar_campos_extraidos: a extração nova materializa por gatilho em evento_auditoria (decisão 7), para não apagar o `ln` da 0270. O backfill roda na própria migration. Idempotente: pode ser reaplicada.)
--
-- O DEFEITO. A identidade de uma linha financeira era `(secao_canonica, rótulo)` em `campo_extraido`: texto livre, sem FK, sem entidade nem período PRÓPRIOS (a linha tem `entidade_coluna` e `periodo_coluna` em texto; o documento tem UM `entidade_id`/`periodo_id`). Toda reconciliação refaz esse
-- casamento por rótulo (a família de bugs que a F4 existe para extinguir) e nada diz, por linha, "a conta é esta, a entidade é esta, o período é este — e foi a IA quem disse, ou foi um palpite nosso". O roadmap (ARQUITETURA_ALVO_E_ROADMAP, F4) define `fato_financeiro` ACIMA de `campo_extraido`, que NÃO muda (ADR 01: a
-- evidência é imutável; o canônico nasce acima); o plano pede "0 fato sem identidade no corpus; heurística sempre com pendência".
--
-- O QUE JÁ EXISTIA E FOI REUSADO (degrau 2 da escada, nada reescrito): a heurística de seção é a que o banco JÁ tem — `fn_secao_canonica_da_secao_bruta` (0203, pelo texto da seção) e `fn_herdar_secao_pela_arvore` (0204, pela árvore do documento), as duas gravam `campo_extraido.secao_canonica_inferida = true`: essa
-- flag é o método `heuristica`. O papel da linha é `fn_papel_linha`; a versão vigente, `fn_versao_atual`; a entidade, `fn_entidade_canonica` e o vocabulário de `fn_coluna_entidade` (0023: Combinado/Consolidado/Total/Soma); o período, `fn_periodo_canonico` casado como `fn_upsert_periodo` casa (forma canônica, o de menor referência
-- no empate), `fn_anos_texto` e `fn_coluna_e_abertura` (0199/0201). Não há resolução de ENTIDADE_COLUNA → entidade nem de PERIODO_COLUNA → período em lugar nenhum (as reconciliações vão no sentido contrário, ano → coluna: fn_coluna_periodo_do_ano/fn_linha_vale_para_ano): o casamento é escrito aqui, uma vez.
--
-- AS DECISÕES DO DONO (11/11/2026, não reabertas): (1) a identidade é o nó de SEÇÃO de `conta_canonica` (0242), sem conta-folha; (2) só linhas de documento de DEMONSTRAÇÃO e de papel `conta` viram fato (subtotal é a P28; Estoque, Razão, Aging, Mapa de Dívida continuam só evidência); (3) pendência UMA por documento-versão,
-- só para extração DAQUI EM DIANTE; o backfill cria os fatos com o método gravado e NÃO abre pendência.
--
-- AS DECISÕES DESTA MIGRATION, E O PORQUÊ DE CADA UMA
--   1. OS TIPOS: BALANCO, BALANCETE, COMBINADO, DRE, FLUXO_CAIXA, DVA, DMPL, DF_AUDITADA. Conferido contra `taxonomia_tipo_documento` (os 8 existem: DF_AUDITADA na 0002, DVA e DMPL na 0024) e contra `ESTRUTURA_POR_TIPO` (statement-templates.ts), que só tem os 5 primeiros: DVA e DMPL o portal já roteia por seção (FAMILIA_POR_SECAO_CANONICA) e DF_AUDITADA
--      traz as demonstrações juntas, cada linha na SUA seção. A categoria "Contábil/Demonstrações" da taxonomia NÃO serve de proxy: inclui RAZAO e NOTAS_EXPL. A lista mora em UMA função (`fn_tipo_gera_fato`) e o predicado completo em `fn_linha_vira_fato`: backfill, extração nova, sonda e teste perguntam a ela.
--   2. LINHA SEM VALOR NÃO É FATO (regra 1: célula vazia é ausência, não zero). Medido em produção em 11/11/2026: 4.798 linhas de documento de demonstração (de qualquer papel) com `valor_num` nulo, 4.648 de versão vigente, ficam só como evidência.
--   3. UM FATO POR `campo_extraido` (FK única, `on delete cascade`), de QUALQUER versão do documento; quem consome escolhe a vigente com `fn_versao_atual`. Em produção: 85.531 fatos, 68.523 de versão vigente e 17.008 de versão antiga. (Fato só da vigente deixaria de existir quando a v2 virasse vigente, e
--      o fato de uma versão superada continua evidência do que ela disse.)
--   4. A LINHA QUE NÃO RESOLVE VIRA FATO COM ESTADO EXPLÍCITO `sem_conta`, e NÃO ganha conta inventada (nem a raiz da demonstração pelo tipo do documento). `conta_id` é NULO se, e só se, `resolucao_metodo = 'sem_conta'` (check), e o motivo vem junto: `secao_nao_declarada` (seção nula, em branco ou o literal NAO_CLASSIFICAVEL das
--      fixtures: o extrator grava null e as fixtures 466 linhas com o literal, tratados IGUAL) ou `secao_fora_do_catalogo`. A bijeção "toda linha elegível tem fato" é medível sem exceção (o teste e a consulta do README), e "0 fato sem identidade" passa a significar algo: o que não tem conta diz que não tem, por constraint.
--   5. ENTIDADE E PERÍODO DO FATO — O CRITÉRIO NOVO (decisão do dono, 11/11/2026, depois de três remendos seguidos na mesma família, regra das três correções): A 0243 NÃO INTERPRETA NOME DE COLUNA. Só atribui entidade ou período quando uma função que o banco JÁ usa para a mesma pergunta decide de forma INEQUÍVOCA; em qualquer outro caso, NULO com o motivo
--      (errar para nulo é ausência declarada, regra 1; errar para valor é número fabricado). Tudo em fn_fato_resolver (também usada para repor a identidade). A família de bugs era uma só: duas colunas diferentes do mesmo documento caindo na mesma (conta, entidade, período) e a soma dobrando (1.310 em vez de 150; 500; 435; 342; HOLDING 10+25-5).
--      ENTIDADE: a coluna de E é a que fn_coluna_entidade(versão, E) (0023/0030, com fn_mesma_entidade) devolve, para cada entidade do mandato. O casamento de nome da 1ª versão (igualdade de fn_entidade_canonica) falhou "Alfa Comércio" x "ALFA COMERCIO DE ALIMENTOS LTDA"; aqui não há casamento próprio. Coluna que nenhuma entidade escolhe: nula (coluna_sem_entidade_no_mandato:
--      Eliminações, empresa não cadastrada; coluna_total_nao_escolhida); escolhida por mais de uma (coluna_casa_varias_entidades); a coluna TOTAL quando o documento tem mais de uma (a função devolve "a" total sem ordem: coluna_total_ambigua); e a linha SEM entidade_coluna num documento que TEM colunas de entidade (a coluna total do dono e a linha "sem coluna" seriam duas colunas na mesma chave).
--      PERÍODO: a coluna que É o período do documento é a ÚNICA coluna de saldo (fn_coluna_e_saldo, não abertura: Saldo final/atual, 0201) ou, na falta de saldo, a ÚNICA coluna que nomeia só o ano do documento (31/12/AAAA = AAAA) num documento NÃO parcial (fn_periodo_e_parcial, 0199 c/0200: BALANCETE e período mês/trimestre são parciais). Duas candidatas, ou nenhuma: nenhuma é escolhida —
--      fn_coluna_periodo_do_ano (0234) existe e é a função de "qual coluna vale para o ano", mas desempata por contagem e ordem alfabética: no balancete de junho com Jun/2025 e 30/06/2025 entrega uma AO ACASO, e com Orçado 2025/AV% 2025/Var. 2025 x 2024 entrega "AV% 2025" (um percentual) — por isso a 0243 usa as mesmas funções de classificação (saldo, abertura, movimento, parcial) mas NÃO o desempate dela. Documento sem coluna de período nenhuma: a linha é do período do documento. Linha sem coluna num documento que TEM colunas: nula
--      (a regra de fn_linha_vale_para_ano, 0195). A coluna de ano puro de OUTRO ano ("2024" num documento de 2025) só recebe o período do ano em documento NÃO parcial, se UMA coluna só tem aquele ano e um período do MESMO mandato tem a forma canônica (fn_periodo_canonico). Movimento, orçado, variação, percentual, mês por extenso e toda coluna de documento parcial que não foi a escolhida: nulo.
--      O que não resolve fica NULO, com a origem nula e o MOTIVO (`entidade_motivo`, `periodo_motivo`; id nulo <=> origem nula <=> motivo, por check) e a coluna da linha ao lado; o período NÃO é criado (muda checklist e completude). Mas o nulo NÃO fica falso: cadastrar período ou entidade no mandato DEPOIS re-resolve os fatos nulos dele (gatilhos em periodo e entidade) e fn_materializar_fatos() re-resolve os existentes.
--      O critério do plano "0 fato sem identidade" vale POR CONSTRUÇÃO para a conta (nulo só com sem_conta) e é MEDIDO para a entidade e o período: não é zero no corpus (números abaixo), e o motivo de cada nulo é a coluna ao lado. O teste afirma a INVARIANTE da família inteira: em nenhum documento duas colunas diferentes caem na mesma (conta, entidade, período) não nulos.
--   6. A PENDÊNCIA (`conta_canonica_incerta`, rótulo novo de pendencia_tipo, complementar e sobrepujável: avisa, não trava) é UMA por documento-versão (motivo `fato:conta_incerta:<versão>`), lista as linhas por heurística ou sem conta (as 12 primeiras no texto, com o EFEITO: fato sem identidade não entra em seção nenhuma),
--      só para fato de origem `extracao` e só da versão VIGENTE (fn_versao_atual): quando uma versão nova vira a vigente, a pendência ABERTA das anteriores se baixa (resolvida_por sistema:versao_superada; antes a da v1 ficava aberta para sempre). Só toca estado `aberta`: a que alguém está tratando (em correção, reenviada) ou decidiu (aceita com ressalva, rejeitada, resolvida por pessoa) não é baixada, reaberta nem substituída.
--      Convergente (resolve-se sozinha quando não sobra linha incerta). Só abre pendência a CONTA incerta; entidade e período nulos ficam no fato, consultáveis, sem fila (a pendência de entidade/período do documento já existe, 0153/0178).
--   7. O PONTO DA EXTRAÇÃO NOVA É UM GATILHO PRÓPRIO, NÃO O CORPO DE fn_registrar_campos_extraidos (decisão do dono, 12/11/2026): a 0270 (P11, APLICADA em produção) reemitiu essa função para gravar campo_extraido.ln, e a 0243 a reemitia do corpo da 0231 — aplicada, apagaria o `ln` em silêncio; num banco do zero a 0270 (depois) apagaria a materialização.
--      Agora: gatilho AFTER INSERT em evento_auditoria WHEN (acao = 'extracao_sombra') chama fn_materializar_fatos_da_extracao. O evento é gravado pela função DEPOIS do laço e DEPOIS da herança da seção pela árvore (0204), as duas coisas que mudam o que o fato lê; a classificação contábil e o auto-aceite, que vêm depois, não tocam coluna que o fato leia.
--      (Um gatilho de instrução em campo_extraido com tabela de transição não serve: a função insere linha a linha, então dispara por LINHA, 4.000 vezes num documento de 4.000, e antes da herança da seção.) O n8n não muda (a assinatura de fn_registrar_campos_extraidos nem foi tocada). Chamadores de fn_registrar por grep: N8N/build-workflow.mjs e N8N/lib/extract.mjs, os testes;
--      portal/src só a cita em comentário. A falha do fato NÃO derruba a extração (a evidência vale mais que o derivado): sub-bloco que grava o evento `fatos_materializacao_falhou` e segue; `fn_materializar_fatos()` repara. O evento `fatos_materializados` é o sinal de que RODOU (regra 7).
--   8. O FATO SEGUE O DOCUMENTO: corrigir a entidade, o período OU O TIPO do documento (a correção humana de entidade_incorreta/periodo_incorreto/tipo_incorreto) leva os fatos, por gatilho (security definer: quem corrige o documento não escreve em fato). Entidade e período: a identidade de TODOS os fatos do documento é RE-RESOLVIDA por fn_fato_resolver,
--      inclusive a dos que ficaram nulos porque o documento ainda não tinha entidade/período (no fluxo real o diagnóstico preenche o documento DEPOIS de fn_registrar_campos_extraidos: a ordem não pode mudar o resultado). Tipo que ENTRA na lista (RAZAO -> BALANCETE): materializa, com a pendência; tipo que SAI: os fatos (derivados) são removidos, a pendência aberta baixada e o evento
--      fatos_removidos_por_reclassificacao grava quantos; a linha extraída (evidência) fica. E `fn_fundir_entidade` recalcula os fatos do mandato por fn_materializar_fatos_do_caso depois de apagar a absorvida (4ª revisão: a 3ª versão repontava o id às cegas por fn_fato_repontar_entidade, que não existe mais): a FK `fato_financeiro_entidade_id_fkey` é NO ACTION e, sem isso, o `delete from entidade` recusava a fusão INTEIRA (o defeito da 0213 com outra tabela).
--   8b. AS FKs DE ENTIDADE E DE PERÍODO SÃO `DEFERRABLE INITIALLY DEFERRED`: a primeira versão, imediata, derrubava `delete from caso` (historico_do_caso.test.sql, no run.sh): a cascata apaga a entidade por um caminho e os fatos por outro, mais fundo (documento > versão > linha > fato), e a conferência da FK imediata rodava com os fatos ainda lá.
--      A sonda confere o DEFERRABLE no predicado (uma FK recriada imediata é acusada) e o teste apaga um mandato com fatos.
--   9. O FATO É DERIVADO: o authenticated só LÊ (RLS por mandato pela versão, 0216). A 1ª versão deixava inserir e repor colunas; a revisão reproduziu um INSERT de valor 999999999 e a reposição da entidade para a de OUTRO mandato. Escrevem as funções de materialização (security definer, search_path fixo, guarda fn_fato_pode_escrever: conexão de serviço ou quem escreve no mandato, por
--      `current_setting('role')`, que dentro de definer é o papel do chamador) e o service_role. O authenticated só executa fn_materializar_fatos_da_extracao (guardada; a recusa grava o evento fatos_materializacao_negada com o ator real) e fn_fato_repontar_entidade, que SÓ reponta fato de entidade que JÁ NÃO EXISTE (a fusão apaga a absorvida e chama; chamada direta com as duas vivas recusa) e grava o evento. fn_materializar_fatos, a pendência
--      e o backfill são do serviço. O gatilho trg_fato_mesmo_caso recusa entidade ou período de OUTRO mandato, também ao serviço. A materialização por reclassificação humana do documento grava o ator REAL (usuario:<id>). A sonda confere a guarda (corpo, search_path fixo) e a AUSÊNCIA de privilégio e policy de escrita do authenticated em fato_financeiro.
--  10. DESEMPENHO DO BACKFILL. Medido no local com 123.969 linhas de campo_extraido (as fixtures ×30, sintético: serve só para o TEMPO) e 76.229 elegíveis: 2,96 s o backfill e 0,12 s a segunda chamada (idempotente). Na primeira versão levava 21 s: `fn_papel_linha` (~180 µs) rodava POR LINHA; medido em produção, 100.215 linhas de demonstração com valor têm
--      só 6.841 combinações (tipo, rótulo, unidade) distintas (15x menos). Agora o papel roda uma vez por combinação, em duas CTEs `MATERIALIZED` (uma só e o Postgres empurra o filtro para dentro do distinct e volta a chamar por linha: medido). Teto: o tempo cresce com as linhas SEM fato, e a chamada por versão (a extração nova) lê só as da versão.
--  11. O TETO da materialização na extração nova e o CUSTO DOS GATILHOS estão no fim deste cabeçalho ("O TETO"), com quando agir. APLICAÇÃO E LOCKS (corrigido na 3ª revisão, M5: a versão anterior dizia só dos `create trigger`): o backfill roda na mesma transação da migration, e TUDO que segura lock até o COMMIT é criado depois dele: o `create table` nasce SEM as FKs para campo_extraido, documento_versao, entidade e periodo (cada uma segura ShareRowExclusive na tabela referenciada), e as FKs e os `create trigger` em documento, periodo, entidade e evento_auditoria vêm depois do backfill. `set local lock_timeout = '5s'` logo depois do `begin` faz a aplicação falhar RÁPIDO (e se reaplica: a migration é idempotente) em vez de esperar um lote do n8n e arriscar deadlock. MEDIDO (pg_locks, a migration cortada antes do backfill): ShareRowExclusiveLock em campo_extraido, documento_versao, entidade e periodo ANTES da correção (4 tabelas), nenhum DEPOIS. A janela sem FK (entre o backfill e as FKs, na mesma transação) só falha por inteiro se um lote apagar uma linha nesse intervalo: a validação da FK reprova e a migration volta atrás.
--
-- MEDIDO EM PRODUÇÃO ANTES DE ESCREVER (11/11/2026, somente leitura, a mesma consulta de resolução da migration sem escrever; versões vigentes por fn_versao_atual) — o que o backfill criaria: 85.531 fatos em demonstração.
--   Vigentes 68.523: declarada 62.075, heuristica 2.194, sem_conta 4.254 (todas secao_nao_declarada; 0 fora_do_catalogo). Versões antigas 17.008: declarada 14.616, heuristica 994, sem_conta 1.398. Total: declarada 76.691, heuristica 3.188, sem_conta 5.652.
--   Linhas incertas (heurística + sem conta): 8.840, em 563 documentos-versão (536 vigentes) de 48 mandatos — as 563 pendências que o backfill NÃO abre (a decisão do dono; a 0179 abriu 365 de ruído e 347 já estavam julgadas ruído pela triagem). O resumo do backfill (evento fato_financeiro_backfill) conta
--   essas linhas, diz que ficaram sem pendência e por quê; o método gravado e a origem `backfill_0243` deixam a incerteza consultável sem fila.
--   IDENTIDADE (a resolução do critério novo, medida em produção com a mesma consulta, read-only; os números abaixo SUBSTITUEM os da 2ª versão): SEM ENTIDADE 1.685 (declarada 1.177, heurística 4, sem conta 504): 1.053 linha sem entidade_coluna em documento com colunas de entidade, 316 coluna que casa várias entidades, 235 coluna sem entidade no mandato (Eliminações, empresa não cadastrada),
--   15 total não escolhido, 66 documento sem entidade; resolvida por coluna 990 e por coluna total 293.
--   SEM PERÍODO 59.734 de 85.531 (70%): 45.609 coluna que não é o período do documento (movimento, orçado, "Saldo" genérico, mês por extenso, toda coluna de balancete e de documento parcial que não foi a escolhida), 8.841 Saldo Inicial/anterior, 5.118 mais de uma coluna para o mesmo período, 114 linha sem coluna em documento com colunas, 49 ano que o mandato não tem, 3 documento sem período.
--   Resolvido: 25.433 no período do documento (a coluna única de saldo ou de ano do documento, ou o documento sem colunas) e 364 pela coluna de ano puro de outro ano. É o preço do critério: a 2ª versão tinha 36.892 nulos e era a que somava errado; o critério novo erra para nulo. A P28 decide se vale criar a leitura de saldo para BALANCETE (parcial por tipo) e para o mês por extenso.
--
-- O LEITOR SÓ-LEITURA (`supabase_read_only_user`): as views da sonda chamam fn_tipo_gera_fato e fn_linha_vira_fato (e esta, fn_papel_linha) com o privilégio de quem LÊ; o bloco condicional de grant (como 0233/0234 e a correção da 0242) as entrega a ele, e Supabase/test/sonda_para_o_leitor_somente_leitura.test.sql o prova.
-- A SONDA (como a 0242: por constraint e por comportamento, não por contagem). A tabela; a policy de leitura (escrita: nenhuma policy para o authenticated, de propósito); as 13 constraints estruturais por nome e predicado (view); nenhum fato numa conta que não é seção (view pelos nós sem seção e o índice de conta_id: custo que não cresce com os fatos);
-- a extração nova está materializando (view sobre as 20 versões de demonstração mais novas que passaram pela extração, com o evento extracao_sombra: uma AMOSTRA, porque a sonda não cresce com o dado, 0132 — e ela fica AUSENTE enquanto o backfill não for aplicado, que é a resposta honesta; a bijeção completa é a consulta do README); o rótulo da pendência;
-- a LISTA DOS TIPOS por view, tipo a tipo (os 8 que geram e 2 que não podem gerar), independente do corpo; os corpos (o gatilho da extração nova e o que ele chama; a resolução que pergunta a fn_linha_vira_fato, acha a conta só pela seção, o período pela coluna, só dá o período do documento à coluna de saldo, não manda o parcial para o ano e não duplica o total; a materialização idempotente;
-- a pendência por versão, a que a extração nova abre, a fusão que repõe); o gatilho do documento pela função que ele tem de chamar e o gatilho de mesmo mandato.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/fato_financeiro.test.sql — 205 asserts EXECUTADOS (o portão medicao-denominador conta 194 chamadas escritas: o helper pg_temp.inv, que afirma a invariante da família, roda uma vez por cenário, 12 vezes; 194 - 1 + 12 = 205; o NOTICE `fato_financeiro: 205 asserts executados, N reprovados`; a migration aplicou e o teste aparece no log em todas as rodadas). Controle (migration intacta): 0 dos 205. OS NÚMEROS POR PARTE ABAIXO SÃO DA 3ª VERSÃO SOBRE 159 ASSERTS e os da 3ª revisão SOBRE 175 (denominadores de então); a 4ª revisão, a regra nova e a remedição das partes que ela tocou estão medidas sobre 205, no fim do bloco da 4ª revisão.
-- Medido em 12/11/2026, sobre o banco montado pelo run.sh: cada sabotagem é a função reemitida com um `replace` sobre pg_get_functiondef (a troca CONFERIDA como aplicada: se o texto não existe a medição aborta) ou o gatilho removido/desabilitado; o teste roda inteiro com `ff.medindo=on` (o assert vira contagem, não aborta), a cópia
-- do teste SEM as duas linhas do topo que reaplicam a migração (senão ela desfaria a sabotagem), o log lido atrás de FALHOU:, e a migration reaplicada para restaurar. A 3ª tentativa (critério novo) e o gatilho da extração nova são desta rodada; as demais partes foram medidas na 1ª e na 2ª versão e REMEDIDAS nesta rodada onde está o número.
--   * O BLOQUEIO DA 0270, o gatilho da extração nova: o gatilho trg_fato_extracao_nova removido 66 dos 159 (a extração grava a linha e o fato nunca nasce); a função do gatilho sem chamar a materialização 66; fn_registrar_campos_extraidos com o `ln` descartado (o corpo da 0231, o que a 0243 reemitia e apagaria a 0270) 1 dos 159 (o assert do `ln` gravado); a sonda acusa o gatilho desabilitado e a função que não chama (asserts da parte k).
--   * O CRITÉRIO NOVO (período): a coluna que não é saldo herda o período do documento (o defeito 1.310/500/435/342) 7 dos 159 (os 5 cenários da 2ª revisão, a invariante e o balancete de duas colunas de saldo); a coluna escolhida sem exigir ser a ÚNICA 4 dos 159 (duas colunas de saldo, duas do ano do documento e 2 de sonda); o documento parcial dando o ano à coluna 2025 1 dos 159.
--   * O CRITÉRIO NOVO (entidade): total sem exigir ser único 3 dos 159; linha sem coluna de entidade indo para o dono do documento 2 dos 159 (a linha e a INVARIANTE); o casamento de nome próprio no lugar de fn_coluna_entidade ("Alfa Comércio" x razão social, o Consolidado dado à ALFA) 6 dos 159.
--   * A INVARIANTE da família (nenhum documento tem duas colunas diferentes na mesma conta, entidade e período não nulos): reprova nas sabotagens de período e de entidade acima (a da coluna que não é saldo e a da linha sem coluna de entidade), medida sobre as fixtures mais os cenários (>= 1.000 fatos de identidade completa: o assert prévio garante que ela não corre sobre o vazio).
--   * O nulo que não fica falso: os gatilhos de cadastro em periodo e entidade removidos 4 dos 159; fn_materializar_fatos() sem re-resolver o existente 1 dos 159; o gatilho do documento removido 9 dos 159; o gatilho do documento ignorando o tipo (M2) 5 dos 159.
--   * Os médios da 2ª revisão: fn_fato_repontar_entidade sem a guarda de "entidade já apagada" 3 dos 159; o evento fatos_materializacao_negada sem o ator real 1 dos 159; fn_fato_pode_escrever sempre verdadeira 4 dos 159; o authenticated com INSERT/UPDATE em fato_financeiro 5 dos 159; a guarda de mesmo mandato desabilitada 4 dos 159.
--   * O ACL DE PRODUÇÃO (o `revoke all` antes do `grant select`): a migration sem o revoke, com o default de produção simulado (`grant all` ao authenticated) 5 dos 159 (esta sabotagem roda o teste COM as duas linhas do topo, apontando para a cópia da migration sem o revoke).
--   * Elegibilidade (fn_linha_vira_fato): só "tem valor" (sem tipo e sem papel) 9 dos 159; sem o papel conta (o subtotal vira fato) 9; o BALANCO fora da lista de tipos 58; a conta achada pelo tipo do documento em vez da seção 11; a versão superada sem baixar a pendência da v1 3; o query_canceled engolido 1; fn_fundir_entidade sem repor os fatos 2.
--   * NÃO REMEDIDAS nesta rodada (números da 2ª versão, sobre 127 asserts, no commit 1e195b2): o backfill abrindo pendência, o motivo da pendência com uuid, as FKs de dimensão imediatas, as views da sonda fixas em ok, a lista dos tipos na sonda e o leitor só-leitura (Supabase/test/sonda_para_o_leitor_somente_leitura.test.sql, 6 asserts, controle 0 dos 6; sem o grant da 0242 4 dos 6, sem o da 0243 4 dos 6, só o da transitiva fn_papel_linha 4 dos 6).
-- A 3ª REVISÃO INDEPENDENTE (do commit 006bbab: 3 altos, 3 médios, 1 baixo, todos corrigidos aqui; MEDIDOS em 12/11/2026 pelo mesmo protocolo, sobre 175 asserts — o arquivo ganhou 16: 175 asserts, 175 execuções, conferido pelo portão):
--   * ALTO 1 (duas colunas da mesma entidade): fn_coluna_entidade usa `limit 1` sem order by, então com "Alfa Comércio Atacado" (não cadastrada) e "Alfa Comércio" a ALFA recebia 77 conforme a ordem física, com a coluna própria anulada pelo motivo falso coluna_sem_entidade_no_mandato. Agora a unicidade é por (versão, entidade): as colunas distintas em que fn_mesma_entidade é verdadeira; mais de uma = nenhuma é atribuída, motivo
--     PRÓPRIO entidade_com_varias_colunas (a constraint de motivos cresceu; ela saiu do create table e é recriada por drop+add, porque `create table if not exists` não atualiza tabela existente). Testado nas DUAS ordens de gravação. Sem a correção 4 dos 175 reprovam (a ALFA recebe a coluna, o motivo falso, e as duas ordens DÃO identidades diferentes: o assert de igualdade entre as ordens reprova com 4 linhas diferentes).
--   * ALTO 2 (tipo que muda entre dois da lista): fn_fato_resolver depende do tipo via fn_periodo_e_parcial (DRE não é parcial, BALANCETE é); o gatilho do documento só re-resolvia quando mudavam a entidade ou o período do documento. Agora o tipo mudou também re-resolve. A INVARIANTE afirmada: re-resolver depois de mudar o tipo dá a mesma identidade que materializar do zero um documento já desse tipo. Sem a correção 2 dos 175.
--   * ALTO 3 (regra 7, a sonda verde com a extração desligada): a amostra "recentes" era das versões COM o evento extracao_sombra, o mesmo que dispara o gatilho; se fn_registrar_campos_extraidos deixasse de gravá-lo (ou o gravasse antes da herança da seção), a amostra ficava vazia e a sonda inteira verde com zero fato novo. Agora a sonda mede por COMPORTAMENTO, sem olhar evento: as 20 versões mais novas
--     de demonstração com linha de extração têm fato para toda linha elegível E o fato concorda com a linha (conta = a seção dela, método pela flag de inferida; fato nascido antes da herança discorda e é acusado). NÃO há requisito de corpo que ancore o insert do evento nem a posição dele: a P11 reemite fn_registrar_campos_extraidos a cada fatia e esse requisito viraria contrato com ela; o comportamento prova o estágio sem prender a função.
--     Custo no run.sh: as fixtures e vários testes gravam linha por SQL direto e comitam, sem passar pela extração; o run.sh chama o backfill da 0243 antes do teste da sonda de instalação (a produção tem o mesmo estado: o backfill da migration cobre o que já estava lá). Sem a correção (a view antiga, pelo evento) 3 dos 175 reprovam (a extração sem fato e sem evento, o fato de seção velha, a conta por outro critério); sem só a concordância de conta e método 2 dos 175.
--     Um efeito a saber: se uma pessoa corrigir a seção da linha depois de materializada, o fato fica velho e a sonda o acusa enquanto a versão estiver entre as 20 mais novas: é o estágio dizendo a verdade (o fato não acompanhou a linha), não um falso positivo.
--   * M4 (a entidade atribuída por coluna envelhece): fn_fato_reresolver_caso filtrava `entidade_id is null`: renomear BETA para DELTA deixava os 7 fatos da coluna "Beta Indústria" na entidade renomeada, e uma 2ª entidade que casa a coluna não a tornava coluna_casa_varias_entidades. Agora também re-resolve os fatos com entidade_origem coluna ou coluna_total do mandato. Sem a correção 2 dos 175.
--   * M5 (locks): ver a decisão 11 (as FKs e os gatilhos depois do backfill, lock_timeout logo depois do begin). Não há assert para lock: MEDIDO por pg_locks (4 tabelas com ShareRowExclusiveLock antes, nenhuma depois). A separação em duas transações não é possível: a API de gerenciamento envolve o lote numa só.
--   * M6 (requisitos de corpo presos a alias de CTE): os marcadores viraram estáveis (nome de função, literal de motivo): fn_linha_vira_fato(, fn_coluna_entidade(, fn_coluna_e_saldo(, fn_periodo_e_parcial(, fn_periodo_canonico(, coluna_total_ambigua, mais_de_uma_coluna_para_o_mesmo_periodo. O requisito da conta-só-pela-seção saiu: é provado pelo comportamento (a concordância da sonda recentes). Preço honesto: um marcador estável é mais fraco
--     (a sabotagem "coluna escolhida sem exigir unicidade" antes reprovava 4 dos 159 e agora 2 dos 175: a sonda de corpo deixou de pegá-la, os asserts de comportamento continuam). São 32 requisitos novos (antes 33).
--   * B7 (default de função): o `pg_default_acl` de funções do Supabase dá EXECUTE ao authenticated; fn_materializar_fatos e fn_fato_pendencia_da_versao (esta sem guarda de mandato) ficaram executáveis. Agora revogadas também do authenticated; o teste simula o default (grant execute) e reaplica a migration. Sem o revoke 3 dos 175 reprovam (os dois asserts novos e o do "execute só do serviço").
--   * O teste isolado reprova asserts de ARRANJO (sobre as fixtures de vertentes e canastra: >= 1.000 linhas elegíveis, >= 100 sem conta, >= 50 subtotais, >= 20 versões, e a parte j que conta fatos de outros mandatos) porque depende dos dados que o run.sh carrega e do estado de suítes anteriores: NÃO foi tornado autossuficiente, porque isso exigiria inventar um corpus (regra 4). Rode-o pelo run.sh.
-- A 4ª REVISÃO INDEPENDENTE (do b1e67d2: 1 alto, 2 médios, todos da família "o fato não converge para o estado atual") E A REGRA NOVA DO DONO: o fato é SEMPRE recalculado do estado atual, nunca remendado por caminho parcial.
--   * O DESENHO. fn_fato_resolver(versão) LÊ (a identidade de todas as linhas elegíveis do estado atual; versão nula = todas). fn_fato_recalcular(versão, origem, motivo) é o ÚNICO ESCRITOR de fato_financeiro (interna, sem guarda): o que o resolver devolve entra ou se atualiza (upsert por campo_extraido_id; o id e a ORIGEM do fato que já existe ficam), o que ele não devolve mais sai. É o mesmo resultado de apagar e materializar do zero,
--     sem reescrever o que não mudou. Quem a chama, e por quê: (1) fn_materializar_fatos_da_extracao (a porta guardada da extração nova: o gatilho trg_fato_extracao_nova e o gatilho do documento quando o tipo ENTRA na lista; a ÚNICA que abre/fecha a pendência; a 2ª chamada na mesma versão recalcula do estado atual); (2) fn_fato_segue_o_documento (entidade, período e tipo do documento: recalcula TODAS as versões dele; tipo que SAI da
--     lista remove porque o resolver não devolve mais nada); (3) fn_fato_recalcular_caso, pelos gatilhos de cadastro em periodo e entidade (as versões do mandato que DEPENDEM do cadastro: com fato atribuído por coluna ou com a dimensão nula) e, pela porta guardada fn_materializar_fatos_do_caso, pela fusão (fn_fundir_entidade); (4) fn_materializar_fatos (a porta guardada do serviço: o backfill e o REPARO, versão nula = tudo); (5) o recálculo final desta migration.
--     Saíram: fn_fato_reresolver_caso (só os nulos), fn_fato_repontar_entidade (trocava o id às cegas) e a re-resolução parcial dentro de fn_materializar_fatos/fn_fato_segue_o_documento. Chamadores listados por grep antes (Supabase/, N8N/, portal/src): só esta migration e o teste. A sonda confere o escritor ÚNICO por COMPORTAMENTO (nenhuma outra função de public grava em fato_financeiro).
--   * ALTO (a janela da aplicação): o backfill lê um snapshot ANTES dos gatilhos; uma transação que comita entre o snapshot e o `create trigger` ficava de fora PARA SEMPRE (a revisora: extração DRE de 2 linhas comitada na janela ficou com 0 fatos, sem evento e sem pendência; um update de documento.entidade_id na janela deixou 177 fatos na entidade antiga; sobre o 006bbab a mesma corrida dava deadlock e a migration voltava atrás, a M5 virou essa falha em perda silenciosa). O comentário "nenhum fato nasce entre o backfill e os gatilhos" estava ERRADO.
--     Agora: DEPOIS dos gatilhos, na mesma transação, o RECÁLCULO COMPLETO roda de novo (`create trigger` espera as transações em andamento e bloqueia as novas até o COMMIT; o statement seguinte tem snapshot novo). MEDIDO COM DUAS SESSÕES (procedimento abaixo, não cabe no run.sh): com a migration antiga a extração da janela ficou com 0 de 2 fatos e 177 fatos de origem documento ficaram com a entidade antiga;
--     com a nova, 2 de 2 e 0 velhos, e o recálculo final reportou 2 criados e 177 atualizados (o resolver do zero e o fato divergem em 0 linhas). A linha que a janela trouxe fica com origem backfill_0243 e SEM pendência (não passou pelo gatilho da extração).
--     PROCEDIMENTO DAS DUAS SESSÕES (reproduzível): (a) um banco com tudo menos a 0243 (create database ... template <banco sem a 0243>); (b) a migration com `\! touch /tmp/p27sab/janela_ok` e `select pg_sleep(12);` inseridos logo depois de `select fn_materializar_fatos_backfill();`, rodada em segundo plano numa sessão; (c) na outra, assim que o arquivo existe, uma extração DRE (fn_registrar_documento + fn_registrar_campos_extraidos) e um
--     `update documento set entidade_id = <outra entidade do mandato>` num documento com muitas linhas, cada um comitado; (d) quando a migration termina: fatos do DRE da janela = linhas do DRE, e nenhum fato de origem documento com entidade diferente da do documento. Os scripts estão no relatório da rodada (/tmp/p27sab/run_janela.sh, b.sql, c.sql).
--   * MÉDIO 1a (a fusão): com "ALFA COMERCIO LTDA" e "ATACADO ALFA LTDA" e as colunas "Alfa Comércio"=100 e "Atacado Alfa"=70, a fusão trocava o id às cegas (a ALFA ficava com 170, as duas por coluna) e um insert de entidade que nada tinha a ver ("OMEGA") mudava o resultado. Agora a fusão recalcula: a ALFA fica com 100 e a coluna do absorvido fica sem entidade, explicada (coluna_sem_entidade_no_mandato). CONSEQUÊNCIA A SABER: depois de uma fusão, o fato atribuído POR COLUNA à entidade absorvida
--     deixa de ter dono (a coluna não casa mais nenhuma entidade) até o cadastro de uma entidade que a case; é o que o zero daria, e o motivo está no fato. Os fatos de origem documento seguem para a sobrevivente (o documento é movido pela fusão).
--   * MÉDIO 1b (duas chamadas na mesma versão): a 1ª sem entidade_coluna e a 2ª com "Consolidado" dava 200 (100 'documento' + 100 'coluna_total'): a 2ª chamada só criava o que faltava. Agora a extração recalcula a versão inteira: a linha da 1ª, num documento que passou a TER colunas de entidade, fica nula (100, não 200).
--   * MÉDIO 2 (conta que nunca era re-resolvida): um update de campo_extraido.secao_canonica (os reparos em massa 0203 e 0204) deixava a sonda recentes vermelha e o reparo que ela mandava rodar devolvia 0. Agora o reparo recalcula conta, método, entidade e período. DECISÃO: NÃO há gatilho em campo_extraido, o reparo cobre. Razões medidas (80 mil linhas): (1) o único escritor de secao_canonica fora da extração são os reparos de serviço; o portal só vincula premissa
--     (fn_vincular_linha_premissa), não escreve a coluna; (2) gatilho de instrução com tabelas de transição não aceita lista de colunas: dispararia em TODO update de campo_extraido (aceite, guardas) e só a captura custa 1,45 s -> 1,67 s por 80 mil linhas (cerca de 14%) com corpo VAZIO, e o corpo teria de recalcular cada versão tocada (cerca de 2 s por versão de 4.000 linhas: um reparo de 20 versões leva uns 40 s a mais), e dentro da extração
--     o fato ainda não existe (o gatilho do evento o cria depois da herança). Quem escrever um reparo em massa de seção deve terminar com `select fn_materializar_fatos();` (a sonda manda rodá-lo e agora ele de fato conserta).
--   * A PENDÊNCIA fica como estava: nenhum recálculo (reparo, cadastro, documento, fusão, recálculo final) a abre, fecha ou reescreve; só a porta da extração. A origem do fato que já existe é preservada pelo upsert (a pendência só lê fato de origem extracao). Provado nos asserts (depois do reparo, do cadastro, da troca de entidade do documento e do recálculo explícito da versão a pendência segue aberta, a mesma, com o mesmo texto; a porta da extração então a converge e não duplica).
--   * OS EVENTOS: fatos_materializados (a extração nova, o ator que a chamou) e fatos_removidos_por_reclassificacao seguem como estavam; o recálculo que mudou algo grava fatos_recalculados com o ator real (`usuario:<id>` ou sistema) e o motivo (documento_alterado, entidade_cadastrada_ou_renomeada, periodo_cadastrado, fusao_de_entidade, reparo): fato trocado ou perdido nunca é silêncio.
--   * A INVARIANTE DA FAMÍLIA, no teste: depois de CADA cenário que muda o que o fato lê, fato_financeiro é igual ao que a materialização do zero daria (comparação linha a linha, nos dois sentidos, de linha, versão, conta, método, entidade, período, motivos, valor, unidade, moeda), sobre as fixtures e os cenários: o backfill, as extrações, a correção do documento, os cenários 500, 435, 342, ALFA e Atacado, a troca de tipo, a ordem real, o cadastro depois e o reparo, a 3ª revisão, a fusão (as duas), a gravação em duas chamadas e a seção mais reparo.
--   * CUSTO (MEDIDO, banco local, balancete de 4.000 rótulos distintos): a extração leva 3,1 s com a 3ª versão e 3,2 a 3,4 s com esta; o update de documento.entidade_id (4.000 linhas) 2,0 a 2,1 s e 2,3 s; o reparo de UMA versão de 4.000 linhas 2,1 s. O TETO NÃO MUDOU (o resolver, que é o custo, é o mesmo; o upsert por diferença compara em vez de reescrever). O cadastro de uma entidade num mandato com 21 versões de 4.000 linhas custou 22 ms (só as versões que dependem do cadastro são recalculadas).
--     O RECÁLCULO FINAL contra ~82 mil linhas (20 documentos de 4.000 mais as fixtures, ~85 mil em produção): 4,9 s com tudo já existente (6,6 s criando tudo do zero). Esses ~5 s correm DEPOIS dos gatilhos e das FKs, na mesma transação: os locks de `create trigger` e de FK (documento, periodo, entidade, evento_auditoria, campo_extraido, documento_versao) duram cerca de 5 s a mais; o n8n que escrever nessas tabelas nesse intervalo ESPERA (não perde nada, não falha). É o preço de fechar a janela.
--   * NÃO-VAZIO DA 4ª REVISÃO (sobre 205 asserts, 12/11/2026, o mesmo protocolo: sabotagem sobre o banco montado, o teste sem as linhas do topo que reaplicam a migration, o log lido atrás de FALHOU; controle 0 dos 205). O escritor sem atualizar o que já existe (só cria, o defeito da 4ª revisão): ABORTA o arquivo na FK de entidade (o fato fica apontando para a entidade que a fusão apagou), com pelo menos 6 asserts de invariante reprovados antes do aborto (sem número fechado);
--     o escritor sem remover o que deixou de ser elegível 10 dos 205; o gatilho do documento sem recalcular 13; o cadastro de entidade e período sem recalcular 12; a fusão sem recalcular 7; o recálculo que também mexe na pendência 2; o evento fatos_recalculados sem o ator real 1; a sonda do escritor único fixa em ok 1; o gatilho da extração nova removido 86 (e a função dele sem chamar 86).
--     REMEDIDAS sobre os 205 as partes que a regra nova tocou ou que dividem o teste: coluna que não é saldo herdando o período 7; total sem unicidade 3; duas colunas da mesma entidade sem a unicidade por (versão, entidade) 4; o gatilho do documento ignorando o tipo 5; a versão superada sem baixar a pendência 3; query_canceled engolido 1; fn_fundir_entidade sem recalcular 7; evento negada sem o ator real 1; authenticated com INSERT 5; fn_fato_pode_escrever sempre verdadeira 5.
--     A JANELA da aplicação não cabe no run.sh: medida pelas duas sessões (procedimento acima), 0 de 2 e 177 velhos antes, 2 de 2 e 0 velhos depois. O teste do MÉDIO 2 (seção que muda por reparo em massa) e os da fusão e das duas chamadas estão nos 205 e reprovam nas sabotagens acima (o escritor sem atualizar e a fusão sem recalcular).
--   * NÃO MEDIDO: o recálculo final em produção (a estimativa é do banco local sintético); a janela com mais de uma transação concorrente; o efeito da fusão sobre mandatos reais (quantos fatos por coluna ficam sem dono; a consulta é `select count(*) from fato_financeiro where entidade_motivo = 'coluna_sem_entidade_no_mandato'`).
-- ACHADOS DA MEDIÇÃO (não do desenho): (1) fn_papel_linha por linha: 21 s no backfill de 124 mil linhas, 2,96 s por combinação distinta; (2) o filtro empurrado para dentro do distinct (uma só CTE) refazia a conta por linha; (3) a FK nova de entidade derrubaria a fusão (fn_fundir_entidade), e o gatilho do documento é o que
-- mantém a identidade do fato quando uma pessoa corrige o documento; (4) o assert que chama `pg_temp` como `authenticated` morre em `permission denied for sequence`: os asserts rodam depois do `reset role`; (5) com a falha do fato ou da fusão fora do sub-bloco, a sabotagem ABORTA o arquivo e a contagem some: as chamadas ficaram em sub-bloco para a medição contar;
-- (6) a FK imediata de fato_financeiro.entidade_id derrubou `delete from caso` no historico_do_caso.test.sql do run.sh (cascatas em profundidades diferentes): FKs adiadas e um assert de exclusão de mandato; (7) a sonda `recentes` dava ausência falsa no run.sh com 2 versões de fixture de teste (linhas inseridas direto): a amostra passou a ser só de versões com o evento extracao_sombra;
-- (8) a sabotagem "capturar query_canceled" deu 0 reprovações na 1ª rodada: `exception when others` do plpgsql NÃO pega query_canceled, então tirar a linha explícita não mudava nada; a sabotagem passou a CAPTURÁ-lo (`when query_canceled then null`) e o teste a usar `when query_canceled or others`; (9) o assert do execute de fn_materializar_fatos dava 0 reprovações com o grant ao authenticated, porque a guarda de escrita também devolve 42501: o teste passou a chamar no PRÓPRIO mandato do Analista.
-- (10) 12/11/2026: o teste reaplicava a 0243 no topo, e isso DESFAZIA toda sabotagem feita por reemissão de função (a primeira rodada de medição deu 0 reprovações em S14 sem que a guarda valesse nada): a medição roda numa cópia do teste sem essas duas linhas; (11) a sabotagem do `ln` (a função reemitida do corpo da 0231) só reprova se o corpo vigente no começo for o da 0270 — por isso o run.sh roda este teste DEPOIS do da 0270 e o assert de arranjo reprova se alguém mover o bloco;
-- (12) o gatilho de instrução com tabela de transição, sugerido para tirar a materialização de dentro da função, não serve: fn_registrar_campos_extraidos insere linha a linha, então ele dispararia por LINHA (e antes da herança da seção pela árvore). O evento extracao_sombra, gravado depois da herança, é o ponto.
-- O TETO (M7). A materialização roda no gatilho do evento extracao_sombra, no mesmo statement da chamada do n8n a fn_registrar_campos_extraidos. MEDIDO em 12/11/2026 (banco local, balancete de 4.000 rótulos distintos, o pior caso do papel por combinação): a chamada leva 3,2 a 3,9 s COM o gatilho e 1,1 s com ele desligado, ou seja 2,1 a 2,8 s de materialização
-- (a revisão independente tinha medido 3,8 s no total, 2,1 s na materialização: o mesmo custo; ele é a função, não o ponto de chamada). O custo do gatilho para os outros eventos é nulo: 100.000 inserções em evento_auditoria levam 584 e 638 ms com o gatilho e 707 ms sem (a cláusula WHEN descarta o resto).
-- Se o statement_timeout do chamador ficar abaixo disso, query_canceled sobe e a extração daquela chamada NÃO é gravada (é o que a regra "não capturar query_canceled" aceita: engolir o cancelamento deixaria a sessão cancelada seguir). QUANDO AGIR: se o evento fatos_materializacao_falhou ou erros 57014 em fn_registrar_campos_extraidos aparecerem, ou se o p95 da chamada passar de ~5 s;
-- então mover a materialização para fora do caminho do n8n (fila ou chamada à parte) e manter fn_materializar_fatos() como o reparo. O custo do gatilho em documento (a correção humana de entidade/período) não foi remedido nesta rodada: a medição da 2ª revisão (UPDATE de entidade_id em documento de 4.000 linhas 2,06 s) vale.
-- O QUE FICA DE FORA (declarado): conta-folha (caixa, clientes…) e a hierarquia pai/filho do fato são a P28+; subtotal = Σ folhas é a P28; reconciliação sobre o fato é a P29. A transcrição humana (fn_registrar_transcricao_humana, 0129) NÃO materializa fato sozinha (a reclassificação do TIPO do documento agora materializa, por gatilho): `select fn_materializar_fatos();`
-- completa (idempotente), e a sonda "recentes" olha só linhas de origem extracao. O período não é criado quando a coluna nomeia um ano que o mandato não tem (4.479 fatos em produção); Saldo Inicial/anterior (8.841) NÃO é resolvido para o período do ano anterior, mesmo quando o mandato o tem (a regra de abertura da 0234 é decisão para a P28/P29);
-- coluna SEM ano que não é saldo (23.569 fatos em produção, medido em 11/11/2026: "Saldo" genérico 4.485 no balancete, Débito/Crédito ~9,4 mil, os meses por extenso de DRE como Agosto e Maio ~5 mil, Total 665) fica com período nulo e explicado: "Saldo" e "Valor" não nomeiam saldo (0201) e nome de mês sem ano não é resolvido aqui; reusar a série mensal é a P28+. Moeda e unidade vão como vieram.
alter type pendencia_tipo add value if not exists 'conta_canonica_incerta';

begin;

-- LOCK: `set local lock_timeout` logo depois do begin (3ª revisão, M5): nada abaixo espera um lote do n8n por mais de 5 s. A tabela nasce SEM as FKs para campo_extraido, documento_versao, entidade e periodo (cada uma segura ShareRowExclusive na tabela referenciada até o COMMIT, e o backfill roda na mesma transação):
-- elas são acrescentadas DEPOIS do backfill, junto dos gatilhos, e o lock nessas quatro tabelas dura a validação (centenas de ms), não o backfill inteiro.
set local lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- A tabela. UMA linha por campo_extraido elegível (FK única): a evidência fica onde está, o fato nasce acima dela (ADR 01).
-- -----------------------------------------------------------------------------
create table if not exists fato_financeiro (
  id                  uuid primary key default gen_random_uuid(),
  campo_extraido_id   uuid not null,
  documento_versao_id uuid not null,
  conta_id            text references conta_canonica(codigo),
  resolucao_metodo    text not null,
  sem_conta_motivo    text,
  -- DEFERRABLE INITIALLY DEFERRED nas duas FKs de dimensão: excluir o mandato (delete from caso) apaga entidade e período por uma cascata e os fatos por OUTRA, mais funda (documento > versão > linha > fato);
  -- a FK imediata recusava a exclusão quando a cascata da entidade terminava antes da dos fatos (medido: historico_do_caso.test.sql, `delete from caso`). Adiada, o Postgres confere no fim da transação, com tudo já apagado.
  entidade_id         uuid,
  entidade_origem     text,
  entidade_motivo     text,
  entidade_coluna     text,
  periodo_id          uuid,
  periodo_origem      text,
  periodo_motivo      text,
  periodo_coluna      text,
  valor               numeric not null,
  unidade             text,
  moeda               text,
  origem              text not null,
  criado_em           timestamptz not null default now(),
  constraint fato_financeiro_campo_extraido_id_key unique (campo_extraido_id),
  constraint fato_financeiro_metodo_ck check (resolucao_metodo in ('declarada', 'heuristica', 'sem_conta')),
  constraint fato_financeiro_conta_metodo_ck check ((conta_id is null) = (resolucao_metodo = 'sem_conta')),
  constraint fato_financeiro_motivo_ck check (
    (sem_conta_motivo is null) = (resolucao_metodo <> 'sem_conta')
    and (sem_conta_motivo is null or sem_conta_motivo in ('secao_nao_declarada', 'secao_fora_do_catalogo'))),
  -- identidade nula = identidade EXPLICADA: o id, a origem e o motivo andam juntos (id nulo <=> origem nula <=> motivo preenchido)
  constraint fato_financeiro_periodo_ck check (
    (periodo_id is null) = (periodo_origem is null)
    and (periodo_id is null) = (periodo_motivo is not null)
    and (periodo_origem is null or periodo_origem in ('documento', 'coluna'))
    and (periodo_motivo is null or periodo_motivo in ('documento_sem_periodo', 'periodo_da_coluna_nao_cadastrado', 'coluna_de_abertura', 'coluna_nao_e_o_periodo_do_documento', 'linha_sem_coluna_em_documento_com_colunas', 'mais_de_uma_coluna_para_o_mesmo_periodo'))),
  constraint fato_financeiro_origem_ck check (origem in ('extracao', 'backfill_0243'))
);
-- A constraint da entidade fora do create table: o conjunto de motivos cresceu na 3ª revisão (entidade_com_varias_colunas) e `create table if not exists` não atualiza a tabela que já existe.
-- identidade nula = identidade EXPLICADA: o id, a origem e o motivo andam juntos (id nulo <=> origem nula <=> motivo preenchido)
alter table fato_financeiro drop constraint if exists fato_financeiro_entidade_ck;
alter table fato_financeiro add constraint fato_financeiro_entidade_ck check (
    (entidade_id is null) = (entidade_origem is null)
    and (entidade_id is null) = (entidade_motivo is not null)
    and (entidade_origem is null or entidade_origem in ('documento', 'coluna', 'coluna_total'))
    and (entidade_motivo is null or entidade_motivo in ('documento_sem_entidade', 'coluna_sem_entidade_no_mandato', 'coluna_casa_varias_entidades', 'entidade_com_varias_colunas', 'coluna_total_nao_escolhida', 'coluna_total_ambigua', 'linha_sem_coluna_em_documento_com_colunas_de_entidade')));
create index if not exists fato_financeiro_versao_idx on fato_financeiro (documento_versao_id);
create index if not exists fato_financeiro_entidade_idx on fato_financeiro (entidade_id);
create index if not exists fato_financeiro_conta_idx on fato_financeiro (conta_id);

comment on table fato_financeiro is
  '0243 (P27): o fato canônico ACIMA de campo_extraido, que não muda (ADR 01). Uma linha por linha extraída elegível (FK única): só documento de demonstração (fn_tipo_gera_fato), só papel conta (fn_papel_linha), só com valor (ausência não vira fato: regra 1). '
  'A identidade é a SEÇÃO (nó de conta_canonica; folha é a P28+). Quem consome escolhe a versão vigente com fn_versao_atual. resolucao_metodo: declarada (a IA deu a seção), heuristica (fn_secao_canonica_da_secao_bruta / fn_herdar_secao_pela_arvore, 0203/0204: secao_canonica_inferida) ou sem_conta (conta_id nulo, com o motivo): "não sei a conta" é estado, nunca um palpite.';
comment on column fato_financeiro.conta_id is 'Nó de conta_canonica que é SEÇÃO (secao_canonica não nula). NULL só com resolucao_metodo = sem_conta (check): linha sem seção declarada, ou com seção que o catálogo não conhece, NÃO ganha conta inventada — nem a raiz da demonstração pelo tipo do documento.';
comment on column fato_financeiro.entidade_origem is 'De onde veio a entidade. A 0243 NÃO interpreta nome de coluna: a entidade da coluna é a que fn_coluna_entidade(versão, entidade) (0023/0030, com fn_mesma_entidade) escolhe para alguma entidade do mandato. coluna = casou pelo NOME da entidade; coluna_total = a coluna Combinado/Consolidado/Total/Soma que a mesma função entrega à entidade do documento (só quando nenhuma coluna casa o nome dela); documento = a linha não tem entidade_coluna (entidade do documento). NULL = a função não escolheu a coluna, ou escolheu para mais de uma entidade: entidade_motivo diz por quê (documento_sem_entidade, coluna_sem_entidade_no_mandato, coluna_casa_varias_entidades, coluna_total_nao_escolhida, coluna_total_ambigua: mais de uma coluna total no documento e a função escolhe sem ordem, linha_sem_coluna_em_documento_com_colunas_de_entidade: documento que tem coluna de entidade e a linha não). A entidade_coluna da linha fica ao lado.';
comment on column fato_financeiro.periodo_origem is 'De onde veio o período. A 0243 NÃO interpreta nome de coluna: só atribui o período quando as funções do banco para essa pergunta decidem de forma INEQUÍVOCA. documento = a linha sem coluna num documento sem colunas, ou a coluna que É o período do documento: a ÚNICA coluna de saldo (fn_coluna_e_saldo: Saldo final/atual, 0201) ou, na falta de saldo, a ÚNICA coluna que nomeia só o ano do documento num documento não parcial (fn_periodo_e_parcial, 0199 c); coluna = coluna de ano puro (31/12/AAAA = AAAA) de OUTRO ano, em documento não parcial, que um período do mesmo mandato tem (fn_periodo_canonico). NULL = ambíguo ou sem base; periodo_motivo diz por quê: coluna_nao_e_o_periodo_do_documento (movimento, orçado, variação, percentual, mês por extenso, coluna de documento parcial que não foi a escolhida), coluna_de_abertura (o ano ANTERIOR, 0199 b), periodo_da_coluna_nao_cadastrado (o período NÃO é criado aqui), mais_de_uma_coluna_para_o_mesmo_periodo, linha_sem_coluna_em_documento_com_colunas (a regra de fn_linha_vale_para_ano, 0195), documento_sem_periodo. O periodo_coluna da linha fica ao lado.';
comment on column fato_financeiro.valor is 'valor_num da linha, como veio. Escala e moeda NÃO são normalizadas aqui (não há regra pronta): unidade e moeda seguem ao lado.';

-- -----------------------------------------------------------------------------
-- RLS e grants. O fato é DERIVADO: o authenticated só LÊ (por mandato pela versão, 0216). Quem escreve são as funções de materialização (security definer com search_path fixo e a guarda
-- fn_fato_pode_escrever) e o service_role. A primeira versão deixava o authenticated inserir e repor colunas: a revisão reproduziu um INSERT de valor arbitrário e a reposição da entidade para a de OUTRO mandato.
-- -----------------------------------------------------------------------------
alter table fato_financeiro enable row level security;
drop policy if exists fato_financeiro_read on fato_financeiro;
create policy fato_financeiro_read on fato_financeiro for select to authenticated
  using ((select fn_eh_socio()) or documento_versao_id in (select id from documento_versao));
drop policy if exists fato_financeiro_insert on fato_financeiro;
drop policy if exists fato_financeiro_update on fato_financeiro;
-- REVOKE antes do GRANT: em produção o `pg_default_acl` do dono dá ALL a authenticated e service_role em toda tabela nova de public (46 de 52 já estão assim, medido em 12/11/2026); sem o revoke o authenticated nasceria com INSERT/UPDATE/DELETE/TRUNCATE
-- e a sonda `fato_authenticated_so_le` ficaria ausente em produção sem nunca ter ficado ausente no banco local (que não tem esse default). O teste simula o default (grant all) antes de reaplicar a migration.
revoke all on fato_financeiro from public, anon, authenticated;
grant select on fato_financeiro to authenticated;
grant select, insert, update, delete on fato_financeiro to service_role;

-- A entidade e o período do fato são do MESMO mandato do documento (guarda, não convenção): mesmo o service_role e a migration passam por ela.
create or replace function fn_fato_mesmo_caso()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare v_caso uuid;
begin
  select d.caso_id into v_caso from documento_versao dv join documento d on d.id = dv.documento_id where dv.id = new.documento_versao_id;
  if new.entidade_id is not null and not exists (select 1 from entidade e where e.id = new.entidade_id and e.caso_id is not distinct from v_caso) then
    raise exception 'fato_financeiro: a entidade % não é do mandato do documento', new.entidade_id using errcode = 'check_violation';
  end if;
  if new.periodo_id is not null and not exists (select 1 from periodo p where p.id = new.periodo_id and p.caso_id is not distinct from v_caso) then
    raise exception 'fato_financeiro: o período % não é do mandato do documento', new.periodo_id using errcode = 'check_violation';
  end if;
  return new;
end $$;
revoke all on function fn_fato_mesmo_caso() from public, anon, authenticated;
drop trigger if exists trg_fato_mesmo_caso on fato_financeiro;
create trigger trg_fato_mesmo_caso before insert or update of entidade_id, periodo_id, documento_versao_id on fato_financeiro
  for each row execute function fn_fato_mesmo_caso();

-- -----------------------------------------------------------------------------
-- O QUE É ELEGÍVEL: uma lista só, e todo o resto (backfill, extração nova, sonda, teste) pergunta a ela.
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

revoke all on function fn_tipo_gera_fato(text), fn_linha_vira_fato(text, text, text, numeric) from public, anon;
grant execute on function fn_tipo_gera_fato(text), fn_linha_vira_fato(text, text, text, numeric) to authenticated, service_role;
-- E ao leitor só-leitura da API de gerenciamento (`supabase_read_only_user`), como a 0233, a 0234 e a correção da 0242: as views da sonda chamam estas funções com o privilégio de quem LÊ, e sem o grant a sonda INTEIRA fica ilegível para quem lê
-- produção sem escrever (o defeito que a 0242 teve em 11/11/2026). fn_papel_linha entra porque fn_linha_vira_fato a chama (chamada transitiva: o Postgres confere o EXECUTE de cada função da cadeia com o leitor; em produção ela já o tem, medido,
-- e o grant é idempotente; no banco do run.sh, que cria o papel antes das migrations, é ele que o dá).
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    execute 'grant execute on function fn_tipo_gera_fato(text) to supabase_read_only_user';
    execute 'grant execute on function fn_linha_vira_fato(text, text, text, numeric) to supabase_read_only_user';
    execute 'grant execute on function fn_papel_linha(text, text, text) to supabase_read_only_user';
  end if;
end $$;

-- O ATOR REAL do evento: o usuário autenticado quando há (a reclassificação humana de um documento grava o nome dele, não 'sistema:n8n'), senão o sistema.
create or replace function fn_fato_ator()
returns text language sql stable as $$ select coalesce('usuario:' || auth.uid()::text, 'sistema:0243') $$;
revoke all on function fn_fato_ator() from public, anon;
grant execute on function fn_fato_ator() to authenticated, service_role;

-- QUEM PODE ESCREVER fato: conexão de serviço (o n8n, a migration: o papel da sessão é service_role ou nenhum) ou quem escreve no mandato (fn_pode_escrever_caso, 0216). O `current_setting('role')` é o papel que o PostgREST pôs
-- com SET ROLE e é lido DENTRO de função security definer (current_user lá seria o dono). Caso nulo (o backfill de tudo) só a conexão de serviço.
create or replace function fn_fato_pode_escrever(p_caso uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(current_setting('role', true), 'none') in ('none', 'service_role', 'postgres', 'supabase_admin')
      or (p_caso is not null and fn_pode_escrever_caso(p_caso))
$$;
revoke all on function fn_fato_pode_escrever(uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- A RESOLUÇÃO: a identidade de TODAS as linhas elegíveis do estado ATUAL (versão nula = todas). Só LÊ: quem grava é fn_fato_recalcular (4ª revisão: o fato é sempre recalculado do estado atual, nunca remendado por caminho parcial).
-- -----------------------------------------------------------------------------
drop function if exists fn_fato_resolver(uuid, boolean);
create or replace function fn_fato_resolver(p_documento_versao_id uuid)
returns table (campo_id uuid, documento_versao_id uuid, conta_id text, resolucao_metodo text, sem_conta_motivo text,
               entidade_id uuid, entidade_origem text, entidade_motivo text, entidade_coluna text,
               periodo_id uuid, periodo_origem text, periodo_motivo text, periodo_coluna text,
               valor numeric, unidade text, moeda text)
language sql stable as $$
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
  alvo as materialized (
    select c.* from cand c join papel p on p.tipo = c.tipo and p.chave = c.chave and coalesce(p.unidade, '') = coalesce(c.unidade, '')
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
  '0243: a identidade de cada linha elegível: conta (a seção, pelo catálogo), entidade e período (pela coluna da linha quando ela diz, pelo documento quando não, e NULOS com o motivo quando a coluna não é saldo, é de abertura, o documento é parcial ou o total duplica a coluna da entidade). p_novos: as sem fato (materializar); falso: as que já têm (repor a identidade quando o documento muda).';
revoke all on function fn_fato_resolver(uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- A MATERIALIZAÇÃO. Idempotente e por conjunto: versão nula = todas (o backfill, e o reparo). security definer (o authenticated só lê fato) com a guarda de escrita.
-- -----------------------------------------------------------------------------
-- O ÚNICO ESCRITOR de fato_financeiro (4ª revisão, a regra nova do dono): recalcula os fatos de uma versão (nula = todas) do ESTADO ATUAL, do zero: o que o resolver devolve entra ou se atualiza (upsert por campo_extraido_id; a origem e o id do fato que já existe ficam), o que ele não devolve mais sai.
-- O resultado é o MESMO de apagar e materializar tudo de novo, sem o custo de reescrever o que não mudou. Todo caminho que muda o que o fato lê (a extração, o documento, o cadastro de entidade e de período, a fusão, o reparo) chama ESTA função para as versões afetadas: não há re-resolução parcial, nem remendo por coluna, nem reponta às cegas.
-- Interna (sem guarda: as guardas estão nas portas: fn_materializar_fatos, fn_materializar_fatos_do_caso, fn_materializar_fatos_da_extracao; os gatilhos são security definer). p_motivo (opcional) grava o evento fatos_recalculados com o ator real quando algo mudou: fato perdido ou trocado nunca é silêncio.
-- NÃO toca pendência: abrir e fechar conta_canonica_incerta é só da extração nova (fn_materializar_fatos_da_extracao).
create or replace function fn_fato_recalcular(p_documento_versao_id uuid default null, p_origem text default 'extracao', p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_r jsonb;
begin
  if p_origem not in ('extracao', 'backfill_0243') then
    raise exception 'fn_fato_recalcular: origem % desconhecida (extracao | backfill_0243)', p_origem;
  end if;
  with r as materialized (select * from fn_fato_resolver(p_documento_versao_id)),
  del as (
    delete from fato_financeiro f
     where (p_documento_versao_id is null or f.documento_versao_id = p_documento_versao_id)
       and not exists (select 1 from r where r.campo_id = f.campo_extraido_id)
    returning 1
  ),
  up as (
    insert into fato_financeiro as f
      (campo_extraido_id, documento_versao_id, conta_id, resolucao_metodo, sem_conta_motivo,
       entidade_id, entidade_origem, entidade_motivo, entidade_coluna, periodo_id, periodo_origem, periodo_motivo, periodo_coluna, valor, unidade, moeda, origem)
    select r.campo_id, r.documento_versao_id, r.conta_id, r.resolucao_metodo, r.sem_conta_motivo,
           r.entidade_id, r.entidade_origem, r.entidade_motivo, r.entidade_coluna, r.periodo_id, r.periodo_origem, r.periodo_motivo, r.periodo_coluna, r.valor, r.unidade, r.moeda, p_origem
      from r
    on conflict (campo_extraido_id) do update
      set conta_id = excluded.conta_id, resolucao_metodo = excluded.resolucao_metodo, sem_conta_motivo = excluded.sem_conta_motivo,
          entidade_id = excluded.entidade_id, entidade_origem = excluded.entidade_origem, entidade_motivo = excluded.entidade_motivo, entidade_coluna = excluded.entidade_coluna,
          periodo_id = excluded.periodo_id, periodo_origem = excluded.periodo_origem, periodo_motivo = excluded.periodo_motivo, periodo_coluna = excluded.periodo_coluna,
          valor = excluded.valor, unidade = excluded.unidade, moeda = excluded.moeda
      where (f.conta_id, f.resolucao_metodo, f.sem_conta_motivo, f.entidade_id, f.entidade_origem, f.entidade_motivo, f.entidade_coluna,
             f.periodo_id, f.periodo_origem, f.periodo_motivo, f.periodo_coluna, f.valor, f.unidade, f.moeda)
            is distinct from
            (excluded.conta_id, excluded.resolucao_metodo, excluded.sem_conta_motivo, excluded.entidade_id, excluded.entidade_origem, excluded.entidade_motivo, excluded.entidade_coluna,
             excluded.periodo_id, excluded.periodo_origem, excluded.periodo_motivo, excluded.periodo_coluna, excluded.valor, excluded.unidade, excluded.moeda)
    returning (xmax = 0) as novo, f.resolucao_metodo, f.sem_conta_motivo, f.entidade_id, f.periodo_id, f.documento_versao_id
  )
  select jsonb_build_object(
           'fatos_criados', count(*) filter (where novo),
           'atualizados', count(*) filter (where not novo),
           'removidos', (select count(*) from del),
           'declarada', count(*) filter (where novo and resolucao_metodo = 'declarada'),
           'heuristica', count(*) filter (where novo and resolucao_metodo = 'heuristica'),
           'sem_conta', count(*) filter (where novo and resolucao_metodo = 'sem_conta'),
           'sem_conta_secao_nao_declarada', count(*) filter (where novo and sem_conta_motivo = 'secao_nao_declarada'),
           'sem_conta_secao_fora_do_catalogo', count(*) filter (where novo and sem_conta_motivo = 'secao_fora_do_catalogo'),
           'sem_entidade', count(*) filter (where novo and entidade_id is null),
           'sem_periodo', count(*) filter (where novo and periodo_id is null),
           'versoes', count(distinct documento_versao_id) filter (where novo),
           'versoes_com_linha_incerta', count(distinct documento_versao_id) filter (where novo and resolucao_metodo <> 'declarada'))
    into v_r from up;
  if p_motivo is not null and ((v_r->>'fatos_criados')::int + (v_r->>'atualizados')::int + (v_r->>'removidos')::int) > 0 then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (fn_fato_ator(), 'fatos_recalculados', coalesce('documento_versao:' || p_documento_versao_id, 'todas'), v_r || jsonb_build_object('motivo', p_motivo));
  end if;
  return v_r;
end $$;
comment on function fn_fato_recalcular(uuid, text, text) is
  '0243 (4ª revisão): o ÚNICO escritor de fato_financeiro. Recalcula do estado atual os fatos de uma versão (nula = todas): o que fn_fato_resolver devolve entra ou se atualiza (a origem e o id do que já existe ficam), o que não devolve mais sai. Igual a apagar e materializar do zero, sem reescrever o que não mudou. Interna: sem guarda (as portas têm). Não toca pendência. Com p_motivo grava o evento fatos_recalculados quando algo mudou.';

-- A PORTA GUARDADA para o serviço (o backfill, o reparo): versão nula = todas. A guarda: conexão de serviço ou quem escreve no mandato; caso nulo só o serviço.
create or replace function fn_materializar_fatos(p_documento_versao_id uuid default null, p_origem text default 'extracao')
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_caso uuid;
begin
  if p_documento_versao_id is not null then
    select d.caso_id into v_caso from documento_versao dv join documento d on d.id = dv.documento_id where dv.id = p_documento_versao_id;
  end if;
  if not fn_fato_pode_escrever(v_caso) then
    raise exception 'fn_materializar_fatos: sem permissão de escrita no mandato' using errcode = 'insufficient_privilege';
  end if;
  return fn_fato_recalcular(p_documento_versao_id, p_origem, 'reparo');
end $$;
comment on function fn_materializar_fatos(uuid, text) is
  '0243: recalcula os fatos da versão (nula = todas) do estado atual, por fn_fato_recalcular: cria o que falta, ATUALIZA o que envelheceu (conta, entidade, período) e remove o que não é mais elegível. É o reparo e o backfill. Idempotente. NÃO abre nem fecha pendência: quem abre é fn_materializar_fatos_da_extracao, só para extração nova. Só a conexão de serviço recalcula tudo; o resto exige escrita no mandato.';

-- A PORTA GUARDADA por mandato, para quem muda o que o fato lê sem ser o serviço (a fusão de entidade, chamada pelo authenticated): recalcula as versões do mandato que dependem do cadastro de entidade ou de período.
create or replace function fn_materializar_fatos_do_caso(p_caso uuid, p_dimensao text default 'entidade', p_motivo text default 'fusao_de_entidade')
returns int language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if p_caso is null or p_dimensao not in ('entidade', 'periodo') then
    raise exception 'fn_materializar_fatos_do_caso: mandato nulo ou dimensão % desconhecida (entidade | periodo)', p_dimensao;
  end if;
  if not fn_fato_pode_escrever(p_caso) then
    raise exception 'fn_materializar_fatos_do_caso: sem permissão de escrita no mandato' using errcode = 'insufficient_privilege';
  end if;
  return fn_fato_recalcular_caso(p_caso, p_dimensao, p_motivo);
end $$;

-- A PENDÊNCIA: UMA por documento-versão, com as linhas resolvidas por heurística ou sem conta. Convergente: reflete o estado atual dos fatos de EXTRAÇÃO da versão (o backfill, origem backfill_0243, nunca entra aqui). Só mexe em estado 'aberta':
-- a que alguém já está tratando (em correção, reenviada ao cliente) ou decidiu (aceita com ressalva, rejeitada, resolvida por pessoa) fica como está.
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
    from (select f.resolucao_metodo,
                 ce.chave || case f.resolucao_metodo
                               when 'heuristica' then ' [seção inferida: ' || coalesce(ce.secao_canonica, '?') || ']'
                               else ' [sem seção' || case when f.sem_conta_motivo = 'secao_fora_do_catalogo' then ': "' || coalesce(ce.secao_canonica, '') || '" não está no catálogo' else '' end || ']' end as rotulo,
                 row_number() over (order by ce.ordem nulls last, ce.id) as rn
            from fato_financeiro f join campo_extraido ce on ce.id = f.campo_extraido_id
           where f.documento_versao_id = p_documento_versao_id and f.origem = 'extracao' and f.resolucao_metodo <> 'declarada') x;

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
  '0243: a pendência conta_canonica_incerta (motivo fato:conta_incerta:<versão>), UMA por documento-versão, listando as linhas de EXTRAÇÃO resolvidas por heurística ou sem conta (as 12 primeiras no texto). Reabre-se sozinha no texto e se resolve sozinha quando não sobra linha incerta; só toca estado aberta. Em outro estado, ou resolvida por pessoa, não é reaberta. Complementar e sobrepujável: não trava o mandato, avisa.';

-- O PONTO ÚNICO da extração nova (chamado por fn_registrar_campos_extraidos, por onde o n8n passa). A extração é a evidência e vale mais que o fato derivado: se a materialização falhar, a extração FICA, o evento diz, e fn_materializar_fatos()
-- repara. NÃO se captura query_canceled (statement_timeout, cancelamento): o cancelamento é do chamador e engolí-lo esconderia a lentidão; o teto medido está no cabeçalho.
drop function if exists fn_materializar_fatos_da_extracao(uuid);
create or replace function fn_materializar_fatos_da_extracao(p_documento_versao_id uuid, p_ator text default 'sistema:n8n')
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_tipo text; v_caso uuid; v_doc uuid; v_r jsonb; v_pend uuid; v_vigente uuid;
begin
  select d.tipo_taxonomia, d.caso_id, d.id into v_tipo, v_caso, v_doc from documento_versao dv join documento d on d.id = dv.documento_id where dv.id = p_documento_versao_id;
  if not fn_tipo_gera_fato(v_tipo) then
    return jsonb_build_object('materializado', false, 'porque', 'tipo do documento não é de demonstração');
  end if;
  if not fn_fato_pode_escrever(v_caso) then
    -- (regra 7: a recusa deixa rastro, não é silêncio)
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (coalesce(fn_fato_ator(), p_ator), 'fatos_materializacao_negada', 'documento_versao:' || p_documento_versao_id,
              jsonb_build_object('porque', 'sem permissão de escrita no mandato', 'ator_declarado', p_ator));
    return jsonb_build_object('materializado', false, 'porque', 'sem permissão de escrita no mandato');
  end if;
  begin
    v_r := fn_fato_recalcular(p_documento_versao_id, 'extracao');   -- a guarda já foi conferida acima; 2ª chamada na mesma versão = recalcula do estado atual (a 1ª pode ter sido sem entidade_coluna)
    v_pend := fn_fato_pendencia_da_versao(p_documento_versao_id);
    -- A VERSÃO SUPERADA: quando esta é a vigente (fn_versao_atual), a pendência ABERTA das outras versões do documento perde o sentido (a leitura que ela julgava não é mais a que vale).
    v_vigente := fn_versao_atual(v_doc);
    if v_vigente = p_documento_versao_id then
      update pendencia
         set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:versao_superada',
             descricao = coalesce(descricao, '') || ' — Resolvida automaticamente: versão superada pela versão ' || p_documento_versao_id || ' do documento.'
       where documento_id = v_doc and estado = 'aberta' and motivo like 'fato:conta_incerta:%' and motivo <> 'fato:conta_incerta:' || p_documento_versao_id;
    end if;
    v_r := v_r || jsonb_build_object('materializado', true, 'pendencia_id', v_pend);
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_ator, 'fatos_materializados', 'documento_versao:' || p_documento_versao_id, v_r);
  exception
    when query_canceled then raise;
    when others then
      insert into evento_auditoria (ator, acao, entidade_ref, depois)
        values (p_ator, 'fatos_materializacao_falhou', 'documento_versao:' || p_documento_versao_id,
                jsonb_build_object('sqlstate', sqlstate, 'erro', sqlerrm,
                                   'porque', 'a extração foi gravada; os fatos não. Rode fn_materializar_fatos() para completar (idempotente).'));
      v_r := jsonb_build_object('materializado', false, 'erro', sqlerrm);
  end;
  return v_r;
end $$;
comment on function fn_materializar_fatos_da_extracao(uuid, text) is
  '0243: fn_materializar_fatos + fn_fato_pendencia_da_versao para a versão recém-extraída, com o evento fatos_materializados (a prova de que RODOU: regra 7) e a baixa da pendência aberta das versões superadas. Tipo fora da lista: não faz nada e não grava evento. Falha: o evento fatos_materializacao_falhou, e a extração não é perdida (query_canceled não é engolido).';

-- (A fusão de entidade chama fn_materializar_fatos_do_caso depois de apagar a absorvida: ela recalcula as versões do mandato que dependem do cadastro de entidade. Não há mais fn_fato_repontar_entidade, que trocava o id às cegas: depois da fusão duas colunas podem casar a MESMA entidade, e o resultado do zero é outro.)

-- 3ª REVISÃO, B7: o `pg_default_acl` de FUNÇÕES do Supabase dá EXECUTE ao authenticated (e ao anon) em toda função nova de public. fn_materializar_fatos e fn_fato_pendencia_da_versao são do SERVIÇO (a segunda NÃO tem guarda de mandato: o authenticated abriria pendência em qualquer mandato): revoga também do authenticated.
revoke all on function fn_materializar_fatos(uuid, text), fn_fato_pendencia_da_versao(uuid) from public, anon, authenticated;
revoke all on function fn_materializar_fatos_da_extracao(uuid, text), fn_materializar_fatos_do_caso(uuid, text, text) from public, anon;
revoke all on function fn_fato_recalcular(uuid, text, text) from public, anon, authenticated;
grant execute on function fn_materializar_fatos(uuid, text), fn_fato_pendencia_da_versao(uuid) to service_role;
grant execute on function fn_materializar_fatos_da_extracao(uuid, text), fn_materializar_fatos_do_caso(uuid, text, text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- O fato segue o documento: corrigir a entidade, o período OU O TIPO do documento (a correção humana de entidade_incorreta/periodo_incorreto/tipo_incorreto, a fusão) leva os fatos.
--   * entidade/período: a identidade de cada fato é RE-RESOLVIDA (fn_fato_resolver), inclusive a dos que ficaram nulos porque o documento ainda não tinha entidade ou período (no fluxo real o diagnóstico preenche o documento DEPOIS de
--     fn_registrar_campos_extraidos: a ordem não pode mudar o resultado);
--   * tipo que ENTRA na lista de demonstrações: materializa (com a pendência, como a extração nova); tipo que SAI: os fatos (derivados) são removidos, a pendência aberta resolvida e o evento grava quantos; a evidência fica.
-- security definer: quem corrige o documento (Analista) não escreve em fato.
-- -----------------------------------------------------------------------------
create or replace function fn_fato_segue_o_documento()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_v uuid; v_n int := 0;
begin
  if new.tipo_taxonomia is distinct from old.tipo_taxonomia then
    if fn_tipo_gera_fato(new.tipo_taxonomia) and not fn_tipo_gera_fato(old.tipo_taxonomia) then
      -- entra na lista: materializa como extração nova (com a pendência), versão a versão
      for v_v in select id from documento_versao where documento_id = new.id order by n_versao loop
        perform fn_materializar_fatos_da_extracao(v_v, fn_fato_ator());
      end loop;
      return null;
    elsif fn_tipo_gera_fato(old.tipo_taxonomia) and not fn_tipo_gera_fato(new.tipo_taxonomia) then
      -- sai da lista: o resolver não devolve mais linha nenhuma desta versão, então o recálculo REMOVE os fatos (derivados); a evidência fica
      select count(*)::int into v_n from fato_financeiro where documento_versao_id in (select id from documento_versao where documento_id = new.id);
      for v_v in select id from documento_versao where documento_id = new.id loop
        perform fn_fato_recalcular(v_v, 'extracao');
      end loop;
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:reclassificacao'
       where documento_id = new.id and estado = 'aberta' and motivo like 'fato:conta_incerta:%';
      insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
        values (fn_fato_ator(), 'fatos_removidos_por_reclassificacao', 'documento:' || new.id,
                jsonb_build_object('tipo_taxonomia', old.tipo_taxonomia), jsonb_build_object('tipo_taxonomia', new.tipo_taxonomia, 'fatos_removidos', v_n,
                  'porque', 'o documento deixou de ser de demonstração; o fato é derivado, a linha extraída (evidência) continua'));
      return null;
    end if;
  end if;
  -- entidade, período ou tipo (entre dois da lista: BALANCETE é parcial, DRE não) mudaram: recalcula TODAS as versões do documento do estado atual
  if fn_tipo_gera_fato(new.tipo_taxonomia) then
    for v_v in select id from documento_versao where documento_id = new.id loop
      perform fn_fato_recalcular(v_v, 'extracao', 'documento_alterado');
    end loop;
  end if;
  return null;
end $$;
revoke all on function fn_fato_segue_o_documento() from public, anon, authenticated;

-- O CADASTRO DEPOIS: período ou entidade que passa a existir (ou a ser renomeada) no mandato muda o que o resolver devolve para as versões que DEPENDEM dele: as que têm fato atribuído por coluna (coluna, coluna_total) ou com a dimensão nula. Cada uma é RECALCULADA (não só os nulos: a 4ª revisão).
-- Só estas versões, e não todas do mandato: o documento sem coluna e com entidade/período do documento não depende do cadastro (o custo de cadastrar uma entidade não cresce com o mandato inteiro).
create or replace function fn_fato_recalcular_caso(p_caso uuid, p_dimensao text, p_motivo text default null)
returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare v_v uuid; v_n int := 0; v_r jsonb;
begin
  for v_v in
    select distinct f.documento_versao_id
      from fato_financeiro f
      join documento_versao dv on dv.id = f.documento_versao_id
      join documento d on d.id = dv.documento_id
     where d.caso_id = p_caso
       and case p_dimensao when 'periodo' then f.periodo_id is null or f.periodo_origem = 'coluna'
                           else f.entidade_id is null or f.entidade_origem in ('coluna', 'coluna_total') or f.entidade_id not in (select id from entidade) end
  loop
    v_r := fn_fato_recalcular(v_v, 'extracao', p_motivo);
    v_n := v_n + (v_r->>'atualizados')::int + (v_r->>'fatos_criados')::int + (v_r->>'removidos')::int;
  end loop;
  return v_n;
end $$;
revoke all on function fn_fato_recalcular_caso(uuid, text, text) from public, anon, authenticated;

create or replace function fn_fato_cadastro_periodo() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin perform fn_fato_recalcular_caso(new.caso_id, 'periodo', 'periodo_cadastrado'); return null; end $$;
create or replace function fn_fato_cadastro_entidade() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin perform fn_fato_recalcular_caso(new.caso_id, 'entidade', 'entidade_cadastrada_ou_renomeada'); return null; end $$;
revoke all on function fn_fato_cadastro_periodo(), fn_fato_cadastro_entidade() from public, anon, authenticated;
-- as funções de re-resolução parcial e de reponta às cegas (3ª versão) deixam de existir: o fato só muda por fn_fato_recalcular
drop function if exists fn_fato_reresolver_caso(uuid, text);
drop function if exists fn_fato_repontar_entidade(uuid, uuid, uuid);

-- -----------------------------------------------------------------------------
-- A EXTRAÇÃO NOVA MATERIALIZA POR GATILHO PRÓPRIO, NÃO DENTRO DE fn_registrar_campos_extraidos (decisão do dono, 12/11/2026, depois do bloqueio da 0270).
-- A 0270 (P11, aplicada em produção) reemitiu fn_registrar_campos_extraidos para gravar campo_extraido.ln; a 0243 reemitia a mesma função a partir do corpo da 0231: aplicada, APAGARIA o `ln` em silêncio, e num banco do zero a 0270
-- (que roda DEPOIS) apagaria a materialização. A 0243 NÃO reemite mais essa função: quem a reemitir no futuro (a P11 a reemite a cada fatia) não leva a materialização junto.
-- O PONTO: o evento `extracao_sombra` (a prova de que a extração RODOU, regra 7), que a função grava DEPOIS do laço de inserção e DEPOIS da herança da seção pela árvore (0204) — as duas únicas coisas que mudam o que o fato lê (seção, valor, colunas, unidade);
-- a classificação contábil e o auto-aceite que vêm depois só tocam colunas que o fato não lê (status_aceite, classe contábil). Gatilho AFTER INSERT em evento_auditoria com WHEN (acao = 'extracao_sombra'): as demais inserções de evento só pagam a cláusula WHEN.
-- POR QUE NÃO UM GATILHO DE INSTRUÇÃO EM campo_extraido COM TABELA DE TRANSIÇÃO (a sugestão inicial): a função insere UMA linha por vez (laço), então a "instrução" é uma linha: dispararia 4.000 vezes num documento de 4.000 linhas, e antes da herança pela árvore
-- (o fato leria a seção ANTES de ela ser herdada: a linha ficaria sem_conta com a seção certa a um UPDATE de distância).
-- A semântica não muda: a mesma fn_materializar_fatos_da_extracao (falha engolida em evento, evento fatos_materializados, pendência da heurística só para extração nova), no mesmo statement do n8n; só o ponto de chamada saiu de dentro da função.
-- -----------------------------------------------------------------------------
create or replace function fn_fato_extracao_nova()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare v_versao uuid;
begin
  -- entidade_ref = 'documento_versao:<uuid>'; qualquer outra forma (evento sintético, uuid inválido) não é extração de versão nenhuma: não faz nada, e NÃO derruba o evento
  if new.entidade_ref ~ '^documento_versao:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    v_versao := substr(new.entidade_ref, length('documento_versao:') + 1)::uuid;
    perform fn_materializar_fatos_da_extracao(v_versao);
  end if;
  return null;
end $$;
revoke all on function fn_fato_extracao_nova() from public, anon, authenticated;
comment on function fn_fato_extracao_nova() is
  '0243: gatilho de evento_auditoria (acao = extracao_sombra, o evento que fn_registrar_campos_extraidos grava depois da herança da seção): materializa o fato_financeiro da versão recém-extraída por fn_materializar_fatos_da_extracao. Sai de dentro de fn_registrar_campos_extraidos para a P11 (0270, que a reemite) e a P27 não dependerem do corpo uma da outra.';


-- -----------------------------------------------------------------------------
-- fn_fundir_entidade REEMITIDA: o corpo VIGENTE (o da 0213, conferido igual ao do banco montado) com o fato_financeiro repontado. Sem isto a FK nova (NO ACTION) recusava a fusão inteira — o defeito da 0213 de novo, com outra tabela.
-- -----------------------------------------------------------------------------
create or replace function public.fn_fundir_entidade(p_caso_id uuid, p_de_id uuid, p_para_id uuid, p_por text DEFAULT 'sistema:fusao'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $$
declare
  v_de    text;
  v_para  text;
  v_docs  int;
  -- 0183
  v_forma_de         entidade_forma_de_controle;
  v_vinculos_de      jsonb;
  v_vinculos_movidos int := 0;
  v_descartados      jsonb := '[]'::jsonb;
  -- 0211
  v_papel_de         entidade_papel_no_grupo;
  v_controladora_de  uuid;
  v_pct_de           numeric;
  r                  record;
  v_s                record;
  v_perim_movidos    int := 0;
  v_perim_descartado jsonb := '[]'::jsonb;
  v_controladas      jsonb;
  v_n_controladas    int := 0;
  -- 0213
  v_perguntas        jsonb;
  v_n_perguntas      int := 0;
  -- 0243
  v_fatos            int := 0;
begin
  if p_de_id = p_para_id then
    raise exception 'fundir uma entidade nela mesma não faz sentido (%)', p_de_id;
  end if;

  select razao_social into v_de   from entidade where id = p_de_id   and caso_id = p_caso_id;
  select razao_social into v_para from entidade where id = p_para_id and caso_id = p_caso_id;
  if v_de is null or v_para is null then
    raise exception 'entidade não encontrada neste mandato (de=%, para=%)', p_de_id, p_para_id;
  end if;

  -- 0211: a sobrevivente controlada pela absorvida vira controlada por si mesma. Isso não tem leitura
  -- automática (a forma declarada deixa de fazer sentido), então recusa em vez de adivinhar. Antes da 0211
  -- era a FK entidade_controladora_id_fkey que recusava, com uma mensagem do Postgres.
  if exists (select 1 from entidade where id = p_para_id and controladora_id = p_de_id) then
    raise exception 'a entidade "%" é controlada por "%", que está sendo fundida nela: a participação passaria a ser dela com ela mesma. Remova a participação (fn_entidade_definir_participacao) e a forma de controle e refaça a fusão.', v_para, v_de;
  end if;

  -- 0243: quantos fatos têm a absorvida (contados ANTES do update do documento, cujo gatilho já leva os que herdaram dela). `fato_financeiro_entidade_id_fkey` é adiada: o fato aponta para a absorvida até fn_fato_repontar_entidade, logo depois do delete.
  select count(*)::int into v_fatos from fato_financeiro where entidade_id = p_de_id;

  update documento set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;
  get diagnostics v_docs = row_count;

  -- Tudo o que aponta para a entidade acompanha o documento. `checklist_item_status`
  -- e `pendencia` guardam entidade_id por conta própria, e deixá-los para trás
  -- faria o Portão 1 continuar cobrando de uma empresa que não existe mais.
  update checklist_item_status set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;
  update pendencia set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;
  update reconciliacao set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;

  -- 0183: o controle declarado de A. Sem isto, o `on delete cascade` de entidade_controlador o
  -- apagava junto com a linha (ver o item (10) da migration 0183).
  select forma_de_controle, papel_no_grupo, controladora_id, percentual_participacao
    into v_forma_de, v_papel_de, v_controladora_de, v_pct_de
    from entidade where id = p_de_id;
  select coalesce(jsonb_agg(jsonb_build_object('controlador_id', ec.controlador_id,
                                               'controlador', k.nome,
                                               'percentual', ec.percentual)
                            order by k.nome), '[]'::jsonb)
    into v_vinculos_de
    from entidade_controlador ec join controlador k on k.id = ec.controlador_id
   where ec.entidade_id = p_de_id;

  if not exists (select 1 from entidade_controlador where entidade_id = p_para_id) then
    update entidade_controlador set entidade_id = p_para_id where entidade_id = p_de_id;
    get diagnostics v_vinculos_movidos = row_count;
  else
    v_descartados := v_vinculos_de;
  end if;

  -- 0211: o perímetro da absorvida. `perimetro_entidade_id_fkey` é ON DELETE CASCADE: sem isto o
  -- `delete from entidade` abaixo levava os escopos dela embora, sem evento. REGRA: cada intervalo da
  -- absorvida passa para a sobrevivente, EXCETO o que se sobrepõe a um intervalo do MESMO escopo que ela já
  -- tem (inclusive o vigente, que a unicidade perimetro_atual_unico de qualquer jeito não deixaria
  -- duplicar). O que sobrepõe NÃO é fundido em um intervalo maior: isso inventaria um início que ninguém
  -- declarou. Fica o da sobrevivente, o da absorvida vai para o evento (perimetro_descartado), com o
  -- intervalo da sobrevivente que o cobriu, e o analista reabre o escopo com fn_perimetro_definir_escopo se
  -- a data certa for outra.
  for r in select id, escopo, desde, ate from perimetro
            where caso_id = p_caso_id and entidade_id = p_de_id order by escopo, desde loop
    select s.desde, s.ate into v_s from perimetro s
     where s.caso_id = p_caso_id and s.entidade_id = p_para_id and s.escopo = r.escopo
       and r.desde <= coalesce(s.ate, 'infinity'::date)
       and coalesce(r.ate, 'infinity'::date) >= s.desde
     limit 1;
    if found then
      v_perim_descartado := v_perim_descartado || jsonb_build_array(jsonb_build_object(
        'escopo', r.escopo, 'desde', r.desde, 'ate', r.ate,
        'motivo', 'sobrepõe um intervalo do mesmo escopo que a sobrevivente já tinha',
        'sobrevivente_desde', v_s.desde, 'sobrevivente_ate', v_s.ate));
    else
      update perimetro set entidade_id = p_para_id where id = r.id;
      v_perim_movidos := v_perim_movidos + 1;
    end if;
  end loop;

  -- 0211: quem era controlada pela absorvida passa a ser controlada pela sobrevivente (a FK
  -- entidade_controladora_id_fkey recusava a fusão inteira com uma mensagem do Postgres).
  select coalesce(jsonb_agg(jsonb_build_object('entidade_id', e.id, 'razao_social', e.razao_social)
                            order by e.razao_social), '[]'::jsonb), count(*)::int
    into v_controladas, v_n_controladas
    from entidade e where e.caso_id = p_caso_id and e.controladora_id = p_de_id;
  update entidade set controladora_id = p_para_id
   where caso_id = p_caso_id and controladora_id = p_de_id;

  -- 0213: as perguntas JÁ AGIDAS (enviada/descartada) sobre a absorvida passam a ser da sobrevivente. São ação
  -- humana que aconteceu e é o que `ja_enviada` lê: sem isto a pergunta enviada sobre a absorvida voltaria a ser
  -- sugerida para a sobrevivente, e `caso_pergunta_entidade_id_fkey` (NO ACTION) fazia a fusão INTEIRA falhar.
  -- A SUGESTÃO não é carregada: é calculada ao vivo por fn_sugerir_perguntas e nunca é gravada.
  select coalesce(jsonb_agg(jsonb_build_object('caso_pergunta_id', cp.id, 'codigo', cp.pergunta_codigo,
                                               'acao', cp.acao, 'criado_em', cp.criado_em)
                            order by cp.criado_em, cp.id), '[]'::jsonb), count(*)::int
    into v_perguntas, v_n_perguntas
    from caso_pergunta cp where cp.caso_id = p_caso_id and cp.entidade_id = p_de_id;
  update caso_pergunta set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;

  -- A pendência de ambiguidade da entidade fundida está respondida.
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_por
   where caso_id = p_caso_id and motivo = 'entidade_ambigua:' || p_de_id and estado <> 'resolvida';

  -- 0183: e as de forma e de papel de A também — a pergunta era sobre uma entidade que deixa de
  -- existir; a de B é de B.
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_por
   where caso_id = p_caso_id
     and motivo in ('forma_de_controle_indefinida:' || p_de_id, 'papel_no_grupo_indefinido:' || p_de_id)
     and estado <> 'resolvida';

  delete from entidade where id = p_de_id and caso_id = p_caso_id;
  -- 0243 (4ª revisão): DEPOIS de apagar a absorvida (as FKs de dimensão de fato_financeiro são adiadas, então os fatos dela aguardam aqui) os fatos do mandato que dependem do cadastro de entidade são RECALCULADOS do estado atual, por função com guarda. Antes a fusão trocava o id às cegas: com "Alfa Comércio" e "Atacado Alfa" a ALFA ficava com as duas colunas (170) e o resultado do zero é outro (as duas colunas casam a ALFA: nenhuma é atribuída).
  perform fn_materializar_fatos_do_caso(p_caso_id, 'entidade', 'fusao_de_entidade');

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
  values (p_por, 'entidade_fundida', 'entidade:' || p_para_id,
          jsonb_build_object('entidade_id', p_de_id, 'razao_social', v_de,
                             -- 0183
                             'forma_de_controle', v_forma_de, 'vinculos', v_vinculos_de,
                             -- 0211: o que a linha apagada declarava e a sobrevivente não herda
                             'papel_no_grupo', v_papel_de, 'controladora_id', v_controladora_de,
                             'percentual_participacao', v_pct_de),
          jsonb_build_object('entidade_id', p_para_id, 'razao_social', v_para,
                             'documentos_movidos', v_docs,
                             -- 0183
                             'vinculos_movidos', v_vinculos_movidos,
                             'vinculos_descartados', v_descartados,
                             -- 0211
                             'perimetro_movido', v_perim_movidos,
                             'perimetro_descartado', v_perim_descartado,
                             'controladas_repontadas', v_controladas,
                             -- 0213
                             'perguntas_repontadas', v_perguntas,
                             -- 0243
                             'fatos_repontados', v_fatos));

  return jsonb_build_object('fundida', v_de, 'em', v_para, 'documentos', v_docs,
                            'vinculos_movidos', v_vinculos_movidos,
                            'vinculos_descartados', jsonb_array_length(v_descartados),
                            'perimetro_movido', v_perim_movidos,
                            'perimetro_descartado', jsonb_array_length(v_perim_descartado),
                            'controladas_repontadas', v_n_controladas,
                            'perguntas_repontadas', v_n_perguntas,
                            'fatos_repontados', v_fatos);
end;
$$;

grant execute on function public.fn_fundir_entidade(uuid, uuid, uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- O BACKFILL: o que já está gravado ganha o fato com o MÉTODO GRAVADO (declarada / heuristica / sem_conta) e NÃO abre pendência. Uma função, para o teste rodá-la sobre as fixtures (que entram DEPOIS das migrations) e para o reparo.
-- -----------------------------------------------------------------------------
create or replace function fn_materializar_fatos_backfill()
returns jsonb language plpgsql as $$
declare
  v_r jsonb;
  v_inc int;
begin
  v_r := fn_fato_recalcular(null, 'backfill_0243');
  v_inc := (v_r->>'heuristica')::int + (v_r->>'sem_conta')::int;
  v_r := v_r || jsonb_build_object(
    'pendencias_abertas', 0,
    'linhas_incertas_sem_pendencia', v_inc,
    'porque_sem_pendencia', 'decisão do dono (11/11/2026): pendência só para extração daqui em diante. Pendência em massa sobre o que já está gravado é ruído (a 0179 abriu 365 e 347 já estavam julgadas ruído pela triagem); o método gravado em fato_financeiro.resolucao_metodo e a origem backfill_0243 deixam a incerteza consultável sem fila.');
  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:migration_0243', 'fato_financeiro_backfill', 'migration:0243', v_r);
  raise notice '0243 backfill: % fato(s) em % versão(ões); % declarada(s), % heurística(s), % sem conta (% sem pendência: decisão do dono); % sem entidade, % sem período',
    v_r->>'fatos_criados', v_r->>'versoes', v_r->>'declarada', v_r->>'heuristica', v_r->>'sem_conta', v_inc, v_r->>'sem_entidade', v_r->>'sem_periodo';
  return v_r;
end $$;
comment on function fn_materializar_fatos_backfill() is
  '0243: fn_materializar_fatos(null, backfill_0243) + o resumo em evento_auditoria (fato_financeiro_backfill): fatos criados por método, sem entidade, sem período, e quantas linhas incertas ficaram SEM pendência e por quê. Idempotente: a segunda chamada cria 0.';
revoke all on function fn_materializar_fatos_backfill() from public, anon, authenticated;
grant execute on function fn_materializar_fatos_backfill() to service_role;

select fn_materializar_fatos_backfill();
\! touch /tmp/p27r5/janela_ok
select pg_sleep(10);

-- OS GATILHOS (documento, periodo, entidade, evento_auditoria) SÃO CRIADOS DEPOIS DO BACKFILL, de propósito: `create trigger` segura lock na tabela até o COMMIT e o backfill roda na mesma transação (~3 s locais, ~85,5 mil fatos em produção);
-- (corrigido na 4ª revisão: "nenhum fato nasce entre o backfill e os gatilhos" estava ERRADO, ver o recálculo final abaixo) criados antes, o lock em documento e em evento_auditoria (que o n8n grava a cada extração) duraria o backfill inteiro; criados depois, dura os milissegundos até o commit. `set local lock_timeout = '5s'` faz a aplicação falhar RÁPIDO
-- (e se reaplica: a migration é idempotente) em vez de esperar um lote do n8n e arriscar deadlock. A JANELA entre o snapshot do backfill e os gatilhos NÃO é fechada pela transação (outra sessão comita nela): quem a fecha é o recálculo final, depois dos gatilhos.
set local lock_timeout = '5s';
-- as FKs que o create table não leva (M5): idempotente por nome. As de dimensão são DEFERRABLE INITIALLY DEFERRED (8b); a da evidência e a da versão apagam em cascata.
do $fk$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.fato_financeiro'::regclass and conname = 'fato_financeiro_campo_extraido_id_fkey') then
    alter table fato_financeiro add constraint fato_financeiro_campo_extraido_id_fkey foreign key (campo_extraido_id) references campo_extraido(id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.fato_financeiro'::regclass and conname = 'fato_financeiro_documento_versao_id_fkey') then
    alter table fato_financeiro add constraint fato_financeiro_documento_versao_id_fkey foreign key (documento_versao_id) references documento_versao(id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.fato_financeiro'::regclass and conname = 'fato_financeiro_entidade_id_fkey') then
    alter table fato_financeiro add constraint fato_financeiro_entidade_id_fkey foreign key (entidade_id) references entidade(id) deferrable initially deferred;
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.fato_financeiro'::regclass and conname = 'fato_financeiro_periodo_id_fkey') then
    alter table fato_financeiro add constraint fato_financeiro_periodo_id_fkey foreign key (periodo_id) references periodo(id) deferrable initially deferred;
  end if;
end $fk$;
drop trigger if exists trg_fato_segue_o_documento on documento;
create trigger trg_fato_segue_o_documento
  after update of entidade_id, periodo_id, tipo_taxonomia on documento
  for each row
  when (old.entidade_id is distinct from new.entidade_id or old.periodo_id is distinct from new.periodo_id or old.tipo_taxonomia is distinct from new.tipo_taxonomia)
  execute function fn_fato_segue_o_documento();
drop trigger if exists trg_fato_cadastro_periodo on periodo;
create trigger trg_fato_cadastro_periodo after insert on periodo for each row execute function fn_fato_cadastro_periodo();
drop trigger if exists trg_fato_cadastro_entidade on entidade;
create trigger trg_fato_cadastro_entidade after insert or update of razao_social on entidade for each row execute function fn_fato_cadastro_entidade();
drop trigger if exists trg_fato_extracao_nova on evento_auditoria;
create trigger trg_fato_extracao_nova after insert on evento_auditoria
  for each row when (new.acao = 'extracao_sombra') execute function fn_fato_extracao_nova();
-- O RECÁLCULO FINAL (4ª revisão, ALTO): o backfill leu um snapshot ANTES dos gatilhos existirem; uma transação que comitou entre o backfill e o `create trigger` (a extração que gravou as linhas e o evento, ou o update de documento.entidade_id) ficava para sempre sem fato (ou com fato velho), sem evento e sem pendência —
-- reproduzido com duas sessões (extração DRE de 2 linhas: 0 fatos; update de entidade: 177 fatos na entidade antiga). `create trigger` espera as transações em andamento (o lock conflita com o RowExclusive de quem escreve) e bloqueia as novas até o COMMIT: o que passou a ser visível depois dele (o statement abaixo tem snapshot novo) entra aqui,
-- e o que vier depois dispara os gatilhos. Mesma transação, DEPOIS dos gatilhos. Custo medido no cabeçalho. A linha que a janela trouxe fica com origem backfill_0243 e sem pendência (não passou pelo gatilho da extração): a bijeção e a invariante valem, a pendência da heurística dessa extração não abre.
do $final$
declare v_r jsonb;
begin
  v_r := fn_fato_recalcular(null, 'backfill_0243');
  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:migration_0243', 'fato_financeiro_recalculo_final', 'migration:0243', v_r || jsonb_build_object('porque', 'fecha a janela entre o snapshot do backfill e a criação dos gatilhos: o que comitou nela entra por aqui'));
  raise notice '0243 recálculo final (depois dos gatilhos): % criado(s), % atualizado(s), % removido(s)', v_r->>'fatos_criados', v_r->>'atualizados', v_r->>'removidos';
end $final$;
set local lock_timeout = 0;


-- -----------------------------------------------------------------------------
-- As VIEWS da sonda (padrão da 0224/0242: uma linha = uma garantia presente; rodam com os privilégios do dono).
-- -----------------------------------------------------------------------------
create or replace view instalacao_sonda_fato_financeiro_constraints as
  select c.conname::text as constraint_nome
    from (values
      ('fato_financeiro_pkey', 'p', 'PRIMARY KEY (id)'),
      ('fato_financeiro_campo_extraido_id_key', 'u', 'UNIQUE (campo_extraido_id)'),
      ('fato_financeiro_campo_extraido_id_fkey', 'f', 'REFERENCES campo_extraido(id) ON DELETE CASCADE'),
      ('fato_financeiro_documento_versao_id_fkey', 'f', 'REFERENCES documento_versao(id) ON DELETE CASCADE'),
      ('fato_financeiro_conta_id_fkey', 'f', 'REFERENCES conta_canonica(codigo)'),
      ('fato_financeiro_entidade_id_fkey', 'f', 'REFERENCES entidade(id) DEFERRABLE INITIALLY DEFERRED'),
      ('fato_financeiro_periodo_id_fkey', 'f', 'REFERENCES periodo(id) DEFERRABLE INITIALLY DEFERRED'),
      ('fato_financeiro_metodo_ck', 'c', '''heuristica''::text'),
      ('fato_financeiro_conta_metodo_ck', 'c', '(conta_id IS NULL)'),
      ('fato_financeiro_motivo_ck', 'c', '''secao_fora_do_catalogo''::text'),
      ('fato_financeiro_entidade_ck', 'c', '''coluna_total_ambigua''::text'),
      ('fato_financeiro_periodo_ck', 'c', '''mais_de_uma_coluna_para_o_mesmo_periodo''::text'),
      ('fato_financeiro_origem_ck', 'c', '''backfill_0243''::text')
    ) e(conname, contype, frag)
    join pg_constraint c on c.conrelid = 'public.fato_financeiro'::regclass and c.conname = e.conname and c.contype = e.contype::"char"
   where pg_get_constraintdef(c.oid) like '%' || e.frag || '%';
comment on view instalacao_sonda_fato_financeiro_constraints is
  'Sonda da 0243: uma linha = uma das 13 constraints de fato_financeiro existe com o predicado esperado (FK única da evidência, conta nula só com sem_conta e motivo, origem da entidade e do período coerente com o id). Menos de 13: uma guarda foi dropada ou trocada.';

-- NENHUM FATO APONTA PARA NÓ QUE NÃO É SEÇÃO (decisão 1 do dono: a identidade desta fatia é a seção). Pelos nós SEM seção (poucos) e o índice de conta_id: o custo não cresce com os fatos.
create or replace view instalacao_sonda_fato_financeiro_so_secao as
  select 1 as ok
   where not exists (select 1 from conta_canonica c where c.secao_canonica is null
                        and exists (select 1 from fato_financeiro f where f.conta_id = c.codigo));
comment on view instalacao_sonda_fato_financeiro_so_secao is
  'Sonda da 0243: uma linha = nenhum fato aponta para raiz, grupo ou subgrupo (nó sem secao_canonica). Zero linhas: um fato foi gravado numa conta que não é seção.';

-- A EXTRAÇÃO NOVA ESTÁ MATERIALIZANDO (regra 7: estágio que não rodou tem a cara de estágio que rodou e não achou nada) — pelo COMPORTAMENTO, não pelo corpo nem pelo evento (3ª revisão, ALTO 3: a versão anterior amostrava as versões com o evento extracao_sombra, o mesmo que dispara o gatilho; se fn_registrar_campos_extraidos
-- deixasse de gravá-lo, ou o gravasse antes da herança da seção, a amostra ficava VAZIA e a sonda inteira verde com zero fato novo — a revisora reproduziu). Agora: as 20 versões mais novas de documento de demonstração que têm linha de EXTRAÇÃO elegível (origem_valor = 'extracao', fn_linha_vira_fato), sem olhar evento nenhum;
-- cada linha elegível delas tem de ter fato E o fato tem de CONCORDAR com a linha como ela está hoje: a conta é o nó da seção da linha (ou sem_conta se o catálogo não a conhece) e o método é declarada/heuristica pela flag secao_canonica_inferida. Fato nascido antes da herança da seção (o evento gravado cedo demais) discorda da linha e é acusado.
-- Uma AMOSTRA, porque a sonda não cresce com o dado (0132). Custo: 20 versões. Em produção o backfill da 0243 cobre o que já estava gravado, então a amostra é verdadeira desde a aplicação; no banco do run.sh o run.sh roda o backfill sobre as fixtures antes da sonda (como produção). A bijeção completa é a consulta do README.
create or replace view instalacao_sonda_fato_financeiro_recentes as
  select 1 as ok
   where not exists (
     select 1
       from (select dv.id, d.tipo_taxonomia
               from documento_versao dv join documento d on d.id = dv.documento_id
              where fn_tipo_gera_fato(d.tipo_taxonomia)
                and exists (select 1 from campo_extraido x where x.documento_versao_id = dv.id and x.origem_valor = 'extracao' and x.valor_num is not null)
              order by dv.criada_em desc, dv.id limit 20) v
       join campo_extraido ce on ce.documento_versao_id = v.id and ce.origem_valor = 'extracao'
      where fn_linha_vira_fato(v.tipo_taxonomia, ce.chave, ce.unidade, ce.valor_num)
        and not exists (
          select 1 from fato_financeiro f left join conta_canonica c on c.codigo = f.conta_id
           where f.campo_extraido_id = ce.id
             and f.resolucao_metodo = case when f.conta_id is null then 'sem_conta' when ce.secao_canonica_inferida then 'heuristica' else 'declarada' end
             and ((f.conta_id is not null and c.secao_canonica = ce.secao_canonica)
                  or (f.conta_id is null and not exists (select 1 from conta_canonica c2 where c2.secao_canonica = ce.secao_canonica)))));
comment on view instalacao_sonda_fato_financeiro_recentes is
  'Sonda da 0243: uma linha = toda linha elegível das 20 versões de demonstração mais novas COM LINHA DE EXTRAÇÃO tem fato, e o fato concorda com a linha (conta = a seção dela, método pela flag de inferida). Zero linhas: a extração nova NÃO está materializando (gatilho ausente ou desabilitado, fn_registrar_campos_extraidos que deixou de gravar o evento ou o gravou antes da herança da seção, materialização falhando: veja o evento fatos_materializacao_falhou). Não depende do evento extracao_sombra. O REPARO é `select fn_materializar_fatos();`: recalcula do estado atual (conta, método, entidade, período), então conserta de fato o fato que envelheceu (por exemplo depois de um reparo em massa de campo_extraido.secao_canonica, como os das 0203 e 0204).';

-- UM ÚNICO ESCRITOR (4ª revisão): nenhuma função de public, além de fn_fato_recalcular, grava em fato_financeiro. Uma linha = o conjunto dos escritores é exatamente {fn_fato_recalcular}.
create or replace view instalacao_sonda_fato_financeiro_um_escritor as
  select 1 as ok
   where (select array_agg(p.proname::text order by p.proname)
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prokind = 'f'
             and p.prosrc ~* '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+(public\.)?fato_financeiro([[:space:]]|$)') = array['fn_fato_recalcular'];
comment on view instalacao_sonda_fato_financeiro_um_escritor is
  'Sonda da 0243: uma linha = a única função de public que grava em fato_financeiro é fn_fato_recalcular. Zero linhas: voltou outro escritor (re-resolução parcial, reponta às cegas) ou o escritor sumiu.';
grant select on instalacao_sonda_fato_financeiro_um_escritor to authenticated, service_role;

create or replace view instalacao_sonda_fato_financeiro_pendencia_tipo as
  select 1 as ok where exists (select 1 from pg_enum e where e.enumtypid = 'pendencia_tipo'::regtype and e.enumlabel = 'conta_canonica_incerta');
comment on view instalacao_sonda_fato_financeiro_pendencia_tipo is
  'Sonda da 0243: uma linha = o rótulo conta_canonica_incerta existe em pendencia_tipo. Sem ele a extração nova com linha heurística tentaria abrir a pendência e falharia (a falha é engolida e vira o evento fatos_materializacao_falhou).';

-- A LISTA DOS TIPOS, um a um e INDEPENDENTE do corpo da função (a primeira versão conferia só o fim da lista no corpo: tirar BALANCO deixava os requisitos presentes): os 8 tipos de demonstração geram fato e
-- 2 que NÃO podem gerar (Razão e Notas, da mesma categoria da taxonomia) não geram. Uma linha por resposta certa: 10 = a lista inteira.
create or replace view instalacao_sonda_fato_financeiro_tipos as
  select e.tipo::text as tipo
    from (values ('BALANCO', true), ('BALANCETE', true), ('COMBINADO', true), ('DRE', true), ('FLUXO_CAIXA', true), ('DVA', true), ('DMPL', true), ('DF_AUDITADA', true), ('RAZAO', false), ('NOTAS_EXPL', false)) e(tipo, gera)
   where fn_tipo_gera_fato(e.tipo) = e.gera;
comment on view instalacao_sonda_fato_financeiro_tipos is
  'Sonda da 0243: uma linha = fn_tipo_gera_fato dá a resposta certa para um dos 10 tipos (BALANCO, BALANCETE, COMBINADO, DRE, FLUXO_CAIXA, DVA, DMPL, DF_AUDITADA geram; RAZAO e NOTAS_EXPL não). Menos de 10: um tipo de demonstração perdeu o fato, ou o que é só evidência virou fato.';

-- O authenticated SÓ LÊ fato_financeiro: nenhum privilégio de escrita (nem de coluna) e nenhuma policy de escrita (o `sem_privilegio` da 0218 varre o schema por papel; esta pergunta é desta tabela).
create or replace view instalacao_sonda_fato_financeiro_authenticated_so_le as
  select 1 as ok
   where not has_any_column_privilege('authenticated', 'public.fato_financeiro'::regclass, 'insert')
     and not has_any_column_privilege('authenticated', 'public.fato_financeiro'::regclass, 'update')
     and not has_table_privilege('authenticated', 'public.fato_financeiro'::regclass, 'delete')
     and not has_table_privilege('authenticated', 'public.fato_financeiro'::regclass, 'truncate')
     and not exists (select 1 from pg_policy p where p.polrelid = 'public.fato_financeiro'::regclass and p.polcmd <> 'r');
comment on view instalacao_sonda_fato_financeiro_authenticated_so_le is
  'Sonda da 0243: uma linha = o authenticated não tem privilégio de escrita em fato_financeiro (tabela, coluna) nem policy de insert/update/delete. Zero linhas: o fato derivado voltou a ser gravável pelo portal (valor arbitrário, entidade de outro mandato).';
grant select on instalacao_sonda_fato_financeiro_tipos, instalacao_sonda_fato_financeiro_authenticated_so_le to authenticated, service_role;
grant select on instalacao_sonda_fato_financeiro_constraints, instalacao_sonda_fato_financeiro_so_secao, instalacao_sonda_fato_financeiro_recentes,
                instalacao_sonda_fato_financeiro_pendencia_tipo to authenticated, service_role;  -- service_role: grant_views_service_role (0214)

-- -----------------------------------------------------------------------------
-- A SONDA. Marcadores em CÓDIGO, nunca de comentário.
-- -----------------------------------------------------------------------------
-- requisitos de versões anteriores desta migration (a 3ª tentativa) que não existem mais: não ficam ausentes para sempre num banco que a aplicou
delete from instalacao_requisito where chave in ('repontar_chama_a_guarda', 'repontar_so_entidade_apagada', 'materializa_reresolve_o_nulo', 'materializa_conta_so_pela_secao');
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fato_financeiro_tabela', '0243', 'tabela', 'fato_financeiro', null, null,
   'O fato canônico não existe: a identidade da linha (conta, entidade, período) volta a ser (secao_canonica, rótulo) e a P28 e a F4 não têm onde se apoiar.',
   'importante', 1105),
  ('fato_financeiro_constraints', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_constraints', null, 13,
   'Faltam constraints de fato_financeiro (FK única da evidência, conta nula só com sem_conta e motivo, identidade nula só com origem nula e motivo): o fato aceita conta inventada, duas linhas por evidência ou identidade que diz uma coisa e mostra outra.',
   'importante', 1106),
  ('fato_financeiro_policy_leitura', '0243', 'policy', 'fato_financeiro.fato_financeiro_read', null, null,
   'Com a RLS ligada e sem a policy o portal lê zero fatos, sem erro. (Escrita: nenhuma policy para o authenticated, de propósito: o fato é derivado.)', 'importante', 1107),
  ('fato_financeiro_so_secao', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_so_secao', null, 1,
   'Há fato apontando para raiz, grupo ou subgrupo: a identidade desta fatia é a SEÇÃO (decisão do dono, 11/11/2026).', 'importante', 1110),
  ('fato_financeiro_extracao_nova_materializa', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_recentes', null, 1,
   'Linha elegível das 20 versões de demonstração mais novas (com linha de extração) sem fato, ou com fato que discorda da linha (conta, método): a extração nova não está materializando — gatilho ausente, fn_registrar_campos_extraidos que deixou de gravar o evento extracao_sombra ou o grava antes da herança da seção, backfill por aplicar, falha engolida (evento fatos_materializacao_falhou). Medido pelo comportamento, sem olhar o evento. Reparo: select fn_materializar_fatos(); (recalcula do estado atual).', 'importante', 1111),
  ('fato_financeiro_pendencia_tipo', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_pendencia_tipo', null, 1,
   'Sem o rótulo conta_canonica_incerta em pendencia_tipo a pendência da heurística não abre.', 'importante', 1112),
  ('extracao_nova_gatilho', '0243', 'gatilho', 'evento_auditoria.trg_fato_extracao_nova', 'fn_fato_extracao_nova', null,
   'Sem o gatilho a extração nova grava a linha e NÃO cria o fato nem abre a pendência da heurística (a materialização mora no gatilho, não em fn_registrar_campos_extraidos, que a P11 reemite a cada fatia).', 'importante', 1113),
  ('extracao_nova_gatilho_chama', '0243', 'corpo', 'fn_fato_extracao_nova', 'fn_materializar_fatos_da_extracao(v_versao)', null,
   'O gatilho existe mas não chama a materialização: o evento extracao_sombra passa e nenhum fato nasce, sem erro.', 'importante', 1139),
  ('materializa_so_o_elegivel', '0243', 'corpo', 'fn_fato_resolver', 'fn_linha_vira_fato(', null,
   'A resolução precisa perguntar a fn_linha_vira_fato: sem isso virar fato é "tudo que tem valor" (Estoque, Razão, subtotal).', 'importante', 1114),
  ('materializa_idempotente', '0243', 'corpo', 'fn_fato_recalcular', 'on conflict (campo_extraido_id) do update', null,
   'Sem o upsert o recálculo (o reenvio, o reparo, qualquer mudança de documento ou de cadastro) morre na FK única ou duplica a evidência, ou volta a ser "criar o que falta" e o fato que envelheceu nunca converge.', 'importante', 1115),
  ('materializa_periodo_pela_coluna', '0243', 'corpo', 'fn_fato_resolver', 'fn_periodo_canonico(', null,
   'O período de outro ano vem da forma canônica da coluna de ano puro (31/12/AAAA = AAAA) que um período do MESMO mandato tem; sem isso o balanço de duas colunas de ano atribui o saldo de 2024 a 2025.', 'importante', 1117),
  ('periodo_so_da_coluna_de_saldo', '0243', 'corpo', 'fn_fato_resolver', 'fn_coluna_e_saldo(', null,
   'A coluna que É o período do documento é a de SALDO (fn_coluna_e_saldo, 0201): Débito, Crédito, Orçado, Variação e percentual com o mesmo período dão fatos idênticos em (conta, entidade, período) e a soma dobra.', 'importante', 1118),
  ('periodo_parcial_nao_vai_para_o_ano', '0243', 'corpo', 'fn_fato_resolver', 'fn_periodo_e_parcial(', null,
   'Documento de período PARCIAL (balancete de junho) não dá a coluna "2025" ao período anual: o acumulado de junho virava a receita do ano.', 'importante', 1119),
  ('periodo_coluna_do_documento_so_se_unica', '0243', 'corpo', 'fn_fato_resolver', 'mais_de_uma_coluna_para_o_mesmo_periodo', null,
   'Com duas candidatas a ser a coluna do período do documento (Jun/2025 e 30/06/2025; Saldo final e Saldo atual) nenhuma é escolhida: fn_coluna_periodo_do_ano desempata por contagem e ordem alfabética, e "ao acaso" é número fabricado (a soma de 4 colunas deu 500).', 'importante', 1120),
  ('entidade_pela_funcao_do_banco', '0243', 'corpo', 'fn_fato_resolver', 'fn_coluna_entidade(', null,
   'A entidade da coluna é a que fn_coluna_entidade (0023/0030, com fn_mesma_entidade) escolhe: um casamento de nome próprio errou "Alfa Comércio" x "ALFA COMERCIO DE ALIMENTOS LTDA" e deu o Consolidado à ALFA com a coluna dela nula.', 'importante', 1127),
  ('entidade_total_so_se_unica', '0243', 'corpo', 'fn_fato_resolver', 'coluna_total_ambigua', null,
   'fn_coluna_entidade entrega "a" coluna total sem ordem: com mais de uma coluna total no documento a escolha é arbitrária e a entidade fica sem coluna total.', 'importante', 1128),
  ('tipos_que_geram_fato', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_tipos', null, 10,
   'A lista dos tipos de demonstração perdeu um tipo (linha de demonstração fica sem fato), ou ganhou Razão/Notas (o que é só evidência vira fato). Conferida tipo a tipo, não pelo corpo.', 'importante', 1121),
  ('pendencia_uma_por_versao', '0243', 'corpo', 'fn_fato_pendencia_da_versao', '''fato:conta_incerta:''', null,
   'A pendência da heurística é UMA por documento-versão (o motivo carrega a versão). Outro motivo = uma por linha (fila de ruído) ou nenhuma.', 'importante', 1122),
  ('extracao_nova_abre_a_pendencia', '0243', 'corpo', 'fn_materializar_fatos_da_extracao', 'fn_fato_pendencia_da_versao(p_documento_versao_id)', null,
   'A extração nova materializa o fato mas não abre a pendência: heurística sem pendência é o palpite silencioso que a P27 existe para impedir.', 'importante', 1123),
  ('fato_segue_o_documento_gatilho', '0243', 'gatilho', 'documento.trg_fato_segue_o_documento', 'fn_fato_segue_o_documento', null,
   'Sem ele corrigir a entidade, o período ou o tipo do documento deixa os fatos com a identidade ANTIGA (ou sem fato, ou com fato de documento que deixou de ser demonstração), em silêncio.', 'importante', 1124),
  ('fundir_entidade_leva_os_fatos', '0243', 'corpo', 'fn_fundir_entidade', 'fn_materializar_fatos_do_caso(', null,
   'Corpo anterior à 0243: com a FK de fato_financeiro.entidade_id a fusão falha em `delete from entidade` (e antes dela os fatos apontariam para uma entidade que não existe).', 'importante', 1125),
  ('fato_authenticated_so_le', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_authenticated_so_le', null, 1,
   'O authenticated ganhou privilégio ou policy de escrita em fato_financeiro: o portal pode gravar fato arbitrário (valor 999999999 em subtotal) e repor a entidade para a de OUTRO mandato.', 'importante', 1129),
  ('fato_guarda_de_escrita_corpo', '0243', 'corpo', 'fn_fato_pode_escrever', 'fn_pode_escrever_caso(p_caso)', null,
   'A guarda de escrita (serviço ou quem escreve no mandato) foi trocada (por `select true`, por exemplo): a função security definer escreve fato para qualquer chamador.', 'importante', 1130),
  ('fato_guarda_de_escrita_search_path', '0243', 'corpo', 'fn_fato_pode_escrever', 'SET search_path TO ''public'', ''pg_temp''', null,
   'Função security definer sem search_path fixo: um schema do chamador na frente do public sequestra fn_pode_escrever_caso.', 'importante', 1131),
  ('materializa_chama_a_guarda', '0243', 'corpo', 'fn_materializar_fatos', 'fn_fato_pode_escrever(', null,
   'fn_materializar_fatos é security definer: sem chamar a guarda, qualquer authenticated com execute materializa fato em qualquer mandato.', 'importante', 1132),
  ('extracao_nova_chama_a_guarda', '0243', 'corpo', 'fn_materializar_fatos_da_extracao', 'fn_fato_pode_escrever(', null,
   'fn_materializar_fatos_da_extracao é security definer e o authenticated a executa: sem a guarda, o Analista não alocado materializa fato (e abre pendência) em outro mandato.', 'importante', 1133),
  ('recalcular_o_estado_atual', '0243', 'corpo', 'fn_fato_recalcular', 'fn_fato_resolver(', null,
   'O escritor de fato precisa recalcular DO RESOLVER (o estado atual de linha, documento e cadastro); outro corpo é remendo parcial, e o fato que envelhece (conta, entidade, período) nunca converge (4ª revisão).', 'importante', 1135),
  ('fato_um_escritor_so', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_um_escritor', null, 1,
   'Há função em public, fora de fn_fato_recalcular, que grava em fato_financeiro: de volta a re-resolução parcial e o reponta às cegas, e o fato deixa de ser igual ao que o zero daria.', 'importante', 1136),
  ('materializar_do_caso_chama_a_guarda', '0243', 'corpo', 'fn_materializar_fatos_do_caso', 'fn_fato_pode_escrever(p_caso)', null,
   'fn_materializar_fatos_do_caso é security definer e o authenticated a executa (a fusão): sem a guarda qualquer um recalcula fato de outro mandato.', 'importante', 1140),
  ('fato_cadastro_periodo_gatilho', '0243', 'gatilho', 'periodo.trg_fato_cadastro_periodo', 'fn_fato_cadastro_periodo', null,
   'Sem ele o período cadastrado depois da extração não re-resolve os fatos nulos do mandato.', 'importante', 1137),
  ('fato_cadastro_entidade_gatilho', '0243', 'gatilho', 'entidade.trg_fato_cadastro_entidade', 'fn_fato_cadastro_entidade', null,
   'Sem ele a entidade cadastrada (ou renomeada) depois da extração não re-resolve os fatos nulos do mandato.', 'importante', 1138),
  ('fato_mesmo_caso_gatilho', '0243', 'gatilho', 'fato_financeiro.trg_fato_mesmo_caso', 'fn_fato_mesmo_caso', null,
   'Sem ele a entidade ou o período de um fato podem ser de OUTRO mandato (a escrita só passa por funções, mas a garantia tem de ser do banco).', 'importante', 1126)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0243', revisado_em = current_date,
       observacao = 'A 0243 cria fato_financeiro (o fato acima de campo_extraido: conta = seção, entidade e período pela coluna da linha), a materialização, a pendência conta_canonica_incerta (uma por versão, só extração nova), o backfill sem pendência, o gatilho do documento, reemite fn_registrar_campos_extraidos e fn_fundir_entidade, 5 views de sonda e 32 requisitos novos (ordem 1105-1140).'
 where id = true;

commit;
