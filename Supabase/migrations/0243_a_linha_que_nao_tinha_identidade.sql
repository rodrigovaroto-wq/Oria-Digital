-- 0243 — A LINHA QUE NÃO TINHA IDENTIDADE: `fato_financeiro` acima de `campo_extraido` (P27, Fase 3, etapa 3.2) — o fato canônico (conta = a SEÇÃO da linha, entidade e período pela coluna da linha quando ela diz), a pendência da heurística e o backfill que não abre fila.
-- (Cria 1 tabela, fato_financeiro, as funções fn_tipo_gera_fato, fn_linha_vira_fato, fn_fato_resolver, fn_fato_pode_escrever, fn_materializar_fatos, fn_fato_pendencia_da_versao, fn_materializar_fatos_da_extracao, fn_fato_repontar_entidade, fn_materializar_fatos_backfill e as dos 2 gatilhos (documento e mesmo mandato), 1 gatilho em documento, 1 gatilho em fato, 1 rótulo de pendencia_tipo
--  (conta_canonica_incerta), 5 views da sonda e 20 requisitos novos (ordem 1105-1126). Reemite INTEIRAS fn_registrar_campos_extraidos (corpo da 0231, conferido igual ao do banco montado; mesma assinatura de 6 args, mesma ACL; UMA chamada nova no fim) e fn_fundir_entidade
--  (corpo da 0213, idem; repõe os fatos). O backfill roda na própria migration. Idempotente: pode ser reaplicada.)
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
--   5. ENTIDADE E PERÍODO DO FATO são os da COLUNA da linha quando a coluna diz, e os do documento SÓ quando a coluna não contradiz: o balanço de duas colunas de ano atribuiria o saldo de 2024 a 2025 se valesse o `periodo_id` do documento. Tudo em fn_fato_resolver (uma função, também usada para repor a identidade).
--      ENTIDADE: `coluna` (casa UMA entidade do mandato por fn_entidade_canonica; empate NÃO escolhe, 0153), `coluna_total` (Combinado/Consolidado/Total/Soma = a entidade do documento, SÓ quando nenhuma coluna do documento casa essa entidade pelo nome: como fn_coluna_entidade, 0023; senão a HOLDING recebia a coluna dela E o total: 10, 25 e -5) ou `documento`.
--      PERÍODO: `coluna` (um período do MESMO mandato tem a forma canônica da coluna; 31/12/AAAA e AAAA são o mesmo); `documento` SÓ para a linha sem coluna ou a coluna de SALDO sem ano (fn_coluna_e_saldo, 0201: Saldo final/atual) — Débito, Crédito, Orçado, Variação e percentual NÃO são o saldo do período (0199 a): com o período do documento dariam cinco fatos iguais
--      e a soma passaria de 150 para 1.310 (reproduzido pela revisão); e documento de período PARCIAL (fn_periodo_e_parcial, 0199 c/0200: balancete de junho) com coluna de ano: o período do documento se o ano bate, NUNCA o anual (o acumulado de junho não vira a receita do ano). "Saldo Inicial/anterior" é o ano ANTERIOR ao do documento (0199 b).
--      O que não resolve fica NULO, com a origem nula e o MOTIVO (`entidade_motivo`, `periodo_motivo`; id nulo <=> origem nula <=> motivo, por check) e a coluna da linha ao lado; o período NÃO é criado (muda checklist e completude: decisão do dono). Os números de produção estão no bloco abaixo.
--      O critério do plano "0 fato sem identidade" vale POR CONSTRUÇÃO para a conta (nulo só com sem_conta) e é MEDIDO para a entidade e o período: não é zero no corpus, e o motivo de cada nulo é a coluna ao lado.
--   6. A PENDÊNCIA (`conta_canonica_incerta`, rótulo novo de pendencia_tipo, complementar e sobrepujável: avisa, não trava) é UMA por documento-versão (motivo `fato:conta_incerta:<versão>`), lista as linhas por heurística ou sem conta (as 12 primeiras no texto, com o EFEITO: fato sem identidade não entra em seção nenhuma),
--      só para fato de origem `extracao` e só da versão VIGENTE (fn_versao_atual): quando uma versão nova vira a vigente, a pendência ABERTA das anteriores se baixa (resolvida_por sistema:versao_superada; antes a da v1 ficava aberta para sempre). Só toca estado `aberta`: a que alguém está tratando (em correção, reenviada) ou decidiu (aceita com ressalva, rejeitada, resolvida por pessoa) não é baixada, reaberta nem substituída.
--      Convergente (resolve-se sozinha quando não sobra linha incerta). Só abre pendência a CONTA incerta; entidade e período nulos ficam no fato, consultáveis, sem fila (a pendência de entidade/período do documento já existe, 0153/0178).
--   7. O PONTO ÚNICO é `fn_registrar_campos_extraidos` (o n8n chama por ela; o reprocesso do portal também): a chamada vai no FIM, depois da herança pela árvore (0204) e da classificação contábil, para o fato ler a linha FINAL. A assinatura não muda: o n8n não é republicado. Chamadores listados por grep (N8N/build-workflow.mjs, N8N/lib/extract.mjs,
--      os testes, portal/src/lib/supabase/reprocesso.ts e api/intake/status só a citam em comentário). A falha do fato NÃO derruba a extração (a evidência vale mais que o derivado): sub-bloco que grava o evento `fatos_materializacao_falhou` e segue; `fn_materializar_fatos()` repara. O evento `fatos_materializados` é o sinal de que RODOU (regra 7).
--   8. O FATO SEGUE O DOCUMENTO: corrigir a entidade, o período OU O TIPO do documento (a correção humana de entidade_incorreta/periodo_incorreto/tipo_incorreto) leva os fatos, por gatilho (security definer: quem corrige o documento não escreve em fato). Entidade e período: a identidade de TODOS os fatos do documento é RE-RESOLVIDA por fn_fato_resolver,
--      inclusive a dos que ficaram nulos porque o documento ainda não tinha entidade/período (no fluxo real o diagnóstico preenche o documento DEPOIS de fn_registrar_campos_extraidos: a ordem não pode mudar o resultado). Tipo que ENTRA na lista (RAZAO -> BALANCETE): materializa, com a pendência; tipo que SAI: os fatos (derivados) são removidos, a pendência aberta baixada e o evento
--      fatos_removidos_por_reclassificacao grava quantos; a linha extraída (evidência) fica. E `fn_fundir_entidade` repõe os fatos da absorvida por fn_fato_repontar_entidade: a FK `fato_financeiro_entidade_id_fkey` é NO ACTION e, sem isso, o `delete from entidade` recusava a fusão INTEIRA (o defeito da 0213 com outra tabela).
--   8b. AS FKs DE ENTIDADE E DE PERÍODO SÃO `DEFERRABLE INITIALLY DEFERRED`: a primeira versão, imediata, derrubava `delete from caso` (historico_do_caso.test.sql, no run.sh): a cascata apaga a entidade por um caminho e os fatos por outro, mais fundo (documento > versão > linha > fato), e a conferência da FK imediata rodava com os fatos ainda lá.
--      A sonda confere o DEFERRABLE no predicado (uma FK recriada imediata é acusada) e o teste apaga um mandato com fatos.
--   9. O FATO É DERIVADO: o authenticated só LÊ (RLS por mandato pela versão, 0216). A 1ª versão deixava inserir e repor colunas; a revisão reproduziu um INSERT de valor 999999999 e a reposição da entidade para a de OUTRO mandato. Escrevem as funções de materialização (security definer, search_path fixo, guarda fn_fato_pode_escrever: conexão de serviço ou quem escreve no mandato, por
--      `current_setting('role')`, que dentro de definer é o papel do chamador) e o service_role; o authenticated só executa fn_materializar_fatos_da_extracao e fn_fato_repontar_entidade (guardadas); fn_materializar_fatos, a pendência e o backfill são do serviço. O gatilho trg_fato_mesmo_caso recusa entidade ou período de OUTRO mandato, também ao serviço.
--  10. DESEMPENHO DO BACKFILL. Medido no local com 123.969 linhas de campo_extraido (as fixtures ×30, sintético: serve só para o TEMPO) e 76.229 elegíveis: 2,96 s o backfill e 0,12 s a segunda chamada (idempotente). Na primeira versão levava 21 s: `fn_papel_linha` (~180 µs) rodava POR LINHA; medido em produção, 100.215 linhas de demonstração com valor têm
--      só 6.841 combinações (tipo, rótulo, unidade) distintas (15x menos). Agora o papel roda uma vez por combinação, em duas CTEs `MATERIALIZED` (uma só e o Postgres empurra o filtro para dentro do distinct e volta a chamar por linha: medido). Teto: o tempo cresce com as linhas SEM fato, e a chamada por versão (a extração nova) lê só as da versão.
--  11. O TETO da materialização na extração nova está no fim deste cabeçalho ("O TETO"), com quando agir.
--
-- MEDIDO EM PRODUÇÃO ANTES DE ESCREVER (11/11/2026, somente leitura, a mesma consulta de resolução da migration sem escrever; versões vigentes por fn_versao_atual) — o que o backfill criaria: 85.531 fatos em demonstração.
--   Vigentes 68.523: declarada 62.075, heuristica 2.194, sem_conta 4.254 (todas secao_nao_declarada; 0 fora_do_catalogo). Versões antigas 17.008: declarada 14.616, heuristica 994, sem_conta 1.398. Total: declarada 76.691, heuristica 3.188, sem_conta 5.652.
--   Linhas incertas (heurística + sem conta): 8.840, em 563 documentos-versão (536 vigentes) de 48 mandatos — as 563 pendências que o backfill NÃO abre (a decisão do dono; a 0179 abriu 365 de ruído e 347 já estavam julgadas ruído pela triagem). O resumo do backfill (evento fato_financeiro_backfill) conta
--   essas linhas, diz que ficaram sem pendência e por quê; o método gravado e a origem `backfill_0243` deixam a incerteza consultável sem fila.
--   Identidade (a resolução da 2ª versão, medida em produção): SEM ENTIDADE 1.342 (1.271 coluna que não casa entidade do mandato, 66 documento sem entidade, 5 total que duplica a coluna da entidade); entidade resolvida por coluna 118 e por coluna total 455.
--   SEM PERÍODO 36.892: 23.569 coluna que não é saldo (Saldo genérico, Débito, Crédito, meses por extenso...), 8.841 Saldo Inicial/anterior (abertura), 4.479 coluna de ano/data que o mandato não tem, 3 documento sem período, 0 parcial fora do ano; período resolvido pela coluna em 27.140.
--   (A 1ª versão tratava como período do documento a coluna sem ano que não era de abertura: 32.438 fatos iguais em (conta, entidade, período) — o achado A1 da revisão.)
--
-- O LEITOR SÓ-LEITURA (`supabase_read_only_user`): as views da sonda chamam fn_tipo_gera_fato e fn_linha_vira_fato (e esta, fn_papel_linha) com o privilégio de quem LÊ; o bloco condicional de grant (como 0233/0234 e a correção da 0242) as entrega a ele, e Supabase/test/sonda_para_o_leitor_somente_leitura.test.sql o prova.
-- A SONDA (como a 0242: por constraint e por comportamento, não por contagem). A tabela; a policy de leitura (escrita: nenhuma policy para o authenticated, de propósito); as 13 constraints estruturais por nome e predicado (view); nenhum fato numa conta que não é seção (view pelos nós sem seção e o índice de conta_id: custo que não cresce com os fatos);
-- a extração nova está materializando (view sobre as 20 versões de demonstração mais novas que passaram pela extração, com o evento extracao_sombra: uma AMOSTRA, porque a sonda não cresce com o dado, 0132 — e ela fica AUSENTE enquanto o backfill não for aplicado, que é a resposta honesta; a bijeção completa é a consulta do README); o rótulo da pendência;
-- a LISTA DOS TIPOS por view, tipo a tipo (os 8 que geram e 2 que não podem gerar), independente do corpo; os corpos (a fn_registrar com a chamada; a resolução que pergunta a fn_linha_vira_fato, acha a conta só pela seção, o período pela coluna, só dá o período do documento à coluna de saldo, não manda o parcial para o ano e não duplica o total; a materialização idempotente;
-- a pendência por versão, a que a extração nova abre, a fusão que repõe); o gatilho do documento pela função que ele tem de chamar e o gatilho de mesmo mandato.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/fato_financeiro.test.sql — 127 asserts (127 execuções), lidos no log da rodada (NOTICE `fato_financeiro: 127 asserts executados, N reprovados`; a migration aplicou e o teste aparece no log em todas). Controle (migration intacta): 0 dos 127 reprovam.
-- Cada sabotagem é a função (ou o objeto) reemitida sobre o banco montado (cópia por template; o texto da função, com a troca, de pg_get_functiondef; a troca CONFERIDA como aplicada), o teste rodado inteiro e o log lido atrás de FALHOU:. Por parte (a v1, de 95 asserts, está no commit 8f0f66d; a 2ª versão corrige os achados da revisão independente):
--   * elegibilidade (fn_linha_vira_fato): só "tem valor" (sem tipo e sem papel) 9 dos 127; sem o papel conta (o subtotal vira fato) 9; sem a lista de tipos (Estoque vira fato) 13;
--   * a LISTA DOS TIPOS (a sonda a confere tipo a tipo, sem perguntar ao corpo): o BALANCO tirado de fn_tipo_gera_fato 49 dos 127; a view dos tipos fixa em 10 linhas 2;
--   * a conta só pela seção (fn_fato_resolver): a linha sem seção ganha a raiz (conta inventada) 16 dos 127; a seção que o catálogo não conhece vira a mais parecida 12; a marca secao_canonica_inferida ignorada 7; a linha sem valor virando fato de valor zero 8;
--   * A1, a coluna que não é saldo: coluna sem ano herdando o período do documento (Débito/Crédito/Orçado/Variação) 3 dos 127;
--   * A2, o período parcial: balancete de junho com coluna 2025 indo para o ano 2 dos 127; o período sempre o do documento (a coluna ignorada) 8; a entidade da coluna ignorada 4;
--   * M1, o total que duplica a coluna da entidade: o total sempre a entidade do documento 6 dos 127;
--   * M2, o tipo do documento: o gatilho ignorando tipo_taxonomia 3 dos 127; M3, a ordem real: o gatilho que não re-resolve o fato nulo 3; o gatilho removido 9;
--   * M4, a versão superada: a v2 vigente sem baixar a pendência da v1 3 dos 127; a pendência da versão superada reaberta 1; a auto-resolução tocando estado diferente de aberta 1;
--   * a pendência: a extração nova sem chamar fn_fato_pendencia_da_versao 12 dos 127; o motivo da pendência com uuid (uma por reenvio) 10; o backfill abrindo pendência 2;
--   * M5, o fato é derivado: authenticated com INSERT/UPDATE (policy e grant) 2 dos 127; a guarda de mesmo mandato desabilitada 4; execute de fn_materializar_fatos ao authenticated 1; fn_fato_pode_escrever sempre verdadeira 1;
--   * M7, o cancelamento: query_canceled capturado 2 dos 127; a falha comum derrubando a extração (o `exception when others` trocado) 3;
--   * o ponto único: fn_registrar_campos_extraidos sem a chamada nova 52 dos 127; a fusão sem repor os fatos 2; as FKs de entidade e de período IMEDIATAS (a exclusão do mandato atropela a cascata) 5;
--   * a sonda cega: as views "recentes" e "só seção" fixas em ok 2 dos 127; a view das constraints fixa em 13 linhas 2; cada constraint estrutural dropada e as funções de corpo antigo são acusadas pelos próprios asserts da parte k (a sonda não é o único alarme);
--   * o LEITOR SÓ-LEITURA (Supabase/test/sonda_para_o_leitor_somente_leitura.test.sql, 6 asserts, controle 0 dos 6; o papel é criado pelo run.sh ANTES das migrations; sabotagem = `revoke execute` sobre o banco montado, equivalente a tirar o bloco condicional de grant): sem o grant da 0242 (fn_conta_canonica_orfas) 4 dos 6; sem o da 0243 (fn_tipo_gera_fato e fn_linha_vira_fato) 4 dos 6; só o da transitiva fn_papel_linha 4 dos 6 (a sonda inteira dá permission denied).
-- ACHADOS DA MEDIÇÃO (não do desenho): (1) fn_papel_linha por linha: 21 s no backfill de 124 mil linhas, 2,96 s por combinação distinta; (2) o filtro empurrado para dentro do distinct (uma só CTE) refazia a conta por linha; (3) a FK nova de entidade derrubaria a fusão (fn_fundir_entidade), e o gatilho do documento é o que
-- mantém a identidade do fato quando uma pessoa corrige o documento; (4) o assert que chama `pg_temp` como `authenticated` morre em `permission denied for sequence`: os asserts rodam depois do `reset role`; (5) com a falha do fato ou da fusão fora do sub-bloco, a sabotagem ABORTA o arquivo e a contagem some: as chamadas ficaram em sub-bloco para a medição contar;
-- (6) a FK imediata de fato_financeiro.entidade_id derrubou `delete from caso` no historico_do_caso.test.sql do run.sh (cascatas em profundidades diferentes): FKs adiadas e um assert de exclusão de mandato; (7) a sonda `recentes` dava ausência falsa no run.sh com 2 versões de fixture de teste (linhas inseridas direto): a amostra passou a ser só de versões com o evento extracao_sombra;
-- (8) a sabotagem "capturar query_canceled" deu 0 reprovações na 1ª rodada: `exception when others` do plpgsql NÃO pega query_canceled, então tirar a linha explícita não mudava nada; a sabotagem passou a CAPTURÁ-lo (`when query_canceled then null`) e o teste a usar `when query_canceled or others`; (9) o assert do execute de fn_materializar_fatos dava 0 reprovações com o grant ao authenticated, porque a guarda de escrita também devolve 42501: o teste passou a chamar no PRÓPRIO mandato do Analista.
-- O TETO (M7). A materialização roda DENTRO de fn_registrar_campos_extraidos, na mesma chamada do n8n. Medido pela revisão independente (11/11/2026, banco local): um balancete de 4.000 rótulos distintos leva 3,8 s no total, ~2,1 s deles na materialização (o papel por combinação distinta é o custo). Se o statement_timeout do chamador ficar abaixo disso, query_canceled sobe e a extração daquela chamada NÃO é gravada
-- (é o que a regra "não capturar query_canceled" aceita: engolir o cancelamento deixaria a sessão cancelada seguir). QUANDO AGIR: se o evento fatos_materializacao_falhou ou erros 57014 em fn_registrar_campos_extraidos aparecerem, ou se o p95 da chamada passar de ~5 s; então mover a materialização para fora do caminho do n8n (fila ou chamada à parte) e manter fn_materializar_fatos() como o reparo.
-- O QUE FICA DE FORA (declarado): conta-folha (caixa, clientes…) e a hierarquia pai/filho do fato são a P28+; subtotal = Σ folhas é a P28; reconciliação sobre o fato é a P29. A transcrição humana (fn_registrar_transcricao_humana, 0129) NÃO materializa fato sozinha (a reclassificação do TIPO do documento agora materializa, por gatilho): `select fn_materializar_fatos();`
-- completa (idempotente), e a sonda "recentes" olha só linhas de origem extracao. O período não é criado quando a coluna nomeia um ano que o mandato não tem (4.479 fatos em produção); Saldo Inicial/anterior (8.841) NÃO é resolvido para o período do ano anterior, mesmo quando o mandato o tem (a regra de abertura da 0234 é decisão para a P28/P29);
-- coluna SEM ano que não é saldo (23.569 fatos em produção, medido em 11/11/2026: "Saldo" genérico 4.485 no balancete, Débito/Crédito ~9,4 mil, os meses por extenso de DRE como Agosto e Maio ~5 mil, Total 665) fica com período nulo e explicado: "Saldo" e "Valor" não nomeiam saldo (0201) e nome de mês sem ano não é resolvido aqui; reusar a série mensal é a P28+. Moeda e unidade vão como vieram.
alter type pendencia_tipo add value if not exists 'conta_canonica_incerta';

begin;

-- -----------------------------------------------------------------------------
-- A tabela. UMA linha por campo_extraido elegível (FK única): a evidência fica onde está, o fato nasce acima dela (ADR 01).
-- -----------------------------------------------------------------------------
create table if not exists fato_financeiro (
  id                  uuid primary key default gen_random_uuid(),
  campo_extraido_id   uuid not null references campo_extraido(id) on delete cascade,
  documento_versao_id uuid not null references documento_versao(id) on delete cascade,
  conta_id            text references conta_canonica(codigo),
  resolucao_metodo    text not null,
  sem_conta_motivo    text,
  -- DEFERRABLE INITIALLY DEFERRED nas duas FKs de dimensão: excluir o mandato (delete from caso) apaga entidade e período por uma cascata e os fatos por OUTRA, mais funda (documento > versão > linha > fato);
  -- a FK imediata recusava a exclusão quando a cascata da entidade terminava antes da dos fatos (medido: historico_do_caso.test.sql, `delete from caso`). Adiada, o Postgres confere no fim da transação, com tudo já apagado.
  entidade_id         uuid references entidade(id) deferrable initially deferred,
  entidade_origem     text,
  entidade_motivo     text,
  entidade_coluna     text,
  periodo_id          uuid references periodo(id) deferrable initially deferred,
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
  constraint fato_financeiro_entidade_ck check (
    (entidade_id is null) = (entidade_origem is null)
    and (entidade_id is null) = (entidade_motivo is not null)
    and (entidade_origem is null or entidade_origem in ('documento', 'coluna', 'coluna_total'))
    and (entidade_motivo is null or entidade_motivo in ('documento_sem_entidade', 'coluna_sem_entidade_no_mandato', 'coluna_casa_varias_entidades', 'coluna_total_duplica_coluna_da_entidade'))),
  constraint fato_financeiro_periodo_ck check (
    (periodo_id is null) = (periodo_origem is null)
    and (periodo_id is null) = (periodo_motivo is not null)
    and (periodo_origem is null or periodo_origem in ('documento', 'coluna'))
    and (periodo_motivo is null or periodo_motivo in ('documento_sem_periodo', 'periodo_da_coluna_nao_cadastrado', 'periodo_parcial_fora_do_ano', 'coluna_de_abertura', 'coluna_nao_e_saldo'))),
  constraint fato_financeiro_origem_ck check (origem in ('extracao', 'backfill_0243'))
);
create index if not exists fato_financeiro_versao_idx on fato_financeiro (documento_versao_id);
create index if not exists fato_financeiro_entidade_idx on fato_financeiro (entidade_id);
create index if not exists fato_financeiro_conta_idx on fato_financeiro (conta_id);

comment on table fato_financeiro is
  '0243 (P27): o fato canônico ACIMA de campo_extraido, que não muda (ADR 01). Uma linha por linha extraída elegível (FK única): só documento de demonstração (fn_tipo_gera_fato), só papel conta (fn_papel_linha), só com valor (ausência não vira fato: regra 1). '
  'A identidade é a SEÇÃO (nó de conta_canonica; folha é a P28+). Quem consome escolhe a versão vigente com fn_versao_atual. resolucao_metodo: declarada (a IA deu a seção), heuristica (fn_secao_canonica_da_secao_bruta / fn_herdar_secao_pela_arvore, 0203/0204: secao_canonica_inferida) ou sem_conta (conta_id nulo, com o motivo): "não sei a conta" é estado, nunca um palpite.';
comment on column fato_financeiro.conta_id is 'Nó de conta_canonica que é SEÇÃO (secao_canonica não nula). NULL só com resolucao_metodo = sem_conta (check): linha sem seção declarada, ou com seção que o catálogo não conhece, NÃO ganha conta inventada — nem a raiz da demonstração pelo tipo do documento.';
comment on column fato_financeiro.entidade_origem is 'De onde veio a entidade: documento (documento.entidade_id; a linha não tem entidade_coluna), coluna (entidade_coluna casa UMA entidade do mandato por fn_entidade_canonica) ou coluna_total (coluna Combinado/Consolidado/Total/Soma: a entidade do documento, SÓ quando nenhuma outra coluna do documento casa essa entidade pelo nome: o total não soma de novo o que a coluna da entidade já traz; mesmo critério de fn_coluna_entidade, 0023). NULL = não resolvida; entidade_motivo diz por quê (documento_sem_entidade, coluna_sem_entidade_no_mandato: Eliminações ou empresa não cadastrada, coluna_casa_varias_entidades: empate, 0153, coluna_total_duplica_coluna_da_entidade). A entidade_coluna da linha fica ao lado.';
comment on column fato_financeiro.periodo_origem is 'De onde veio o período: coluna (periodo_coluna nomeia um ano/data e um periodo do MESMO mandato tem essa forma canônica, fn_periodo_canonico) ou documento (a linha não tem coluna; ou a coluna é de SALDO sem ano, fn_coluna_e_saldo; ou o documento é de período PARCIAL, fn_periodo_e_parcial, e o ano da coluna é o do documento: o acumulado de junho não vai para o ano). NULL = não resolvido; periodo_motivo diz por quê: coluna_de_abertura (Saldo Inicial/anterior é o ano ANTERIOR ao do documento, 0199 b), coluna_nao_e_saldo (Débito, Crédito, Orçado, Variação, percentual: movimento e comparativo NÃO são o saldo do período, 0199 a/0201: sem isto dariam cinco fatos iguais em (conta, entidade, período) e a soma dobraria), periodo_da_coluna_nao_cadastrado (o período NÃO é criado aqui), periodo_parcial_fora_do_ano, documento_sem_periodo. O periodo_coluna da linha fica ao lado.';
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

-- QUEM PODE ESCREVER fato: conexão de serviço (o n8n, a migration: o papel da sessão é service_role ou nenhum) ou quem escreve no mandato (fn_pode_escrever_caso, 0216). O `current_setting('role')` é o papel que o PostgREST pôs
-- com SET ROLE e é lido DENTRO de função security definer (current_user lá seria o dono). Caso nulo (o backfill de tudo) só a conexão de serviço.
create or replace function fn_fato_pode_escrever(p_caso uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(current_setting('role', true), 'none') in ('none', 'service_role', 'postgres', 'supabase_admin')
      or (p_caso is not null and fn_pode_escrever_caso(p_caso))
$$;
revoke all on function fn_fato_pode_escrever(uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- A RESOLUÇÃO: uma função, duas perguntas (p_novos = as linhas elegíveis que ainda NÃO têm fato, para materializar; falso = as que JÁ têm, para repor a identidade quando o documento muda). Por conjunto; versão nula = todas.
-- -----------------------------------------------------------------------------
create or replace function fn_fato_resolver(p_documento_versao_id uuid, p_novos boolean)
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
       and case when p_novos then not exists (select 1 from fato_financeiro f where f.campo_extraido_id = ce.id)
                else exists (select 1 from fato_financeiro f where f.campo_extraido_id = ce.id) end
  ),
  -- O papel da linha (fn_papel_linha, ~180 µs) UMA vez por (tipo, rótulo, unidade) distintos, não por linha. Medido em produção em 11/11/2026: 100.215 linhas de demonstração com valor, 6.841 combinações distintas (15x menos chamadas).
  -- fn_linha_vira_fato é o predicado ÚNICO (a sonda e o teste o usam): o valor entra como 1 porque ele só pergunta se é nulo, e a CTE acima já tirou os nulos.
  -- (duas CTEs, não uma subconsulta: o Postgres empurra o filtro para DENTRO do distinct e chama fn_papel_linha por LINHA de novo — medido, 21 s.)
  rotulos as materialized (select distinct tipo, chave, unidade from cand),
  papel as materialized (
    select x.tipo, x.chave, x.unidade from rotulos x where fn_linha_vira_fato(x.tipo, x.chave, x.unidade, 1)
  ),
  alvo0 as materialized (
    select c.* from cand c join papel p on p.tipo = c.tipo and p.chave = c.chave and coalesce(p.unidade, '') = coalesce(c.unidade, '')
  ),
  -- A coluna TOTAL (Combinado/Consolidado/Total/Soma) só vale como a entidade do documento quando NENHUMA coluna do documento já casa essa entidade pelo nome (fn_coluna_entidade, 0023): senão a entidade
  -- recebia a coluna dela e o total, e a soma dobrava (reproduzido: HOLDING com 10, 25 e -5).
  vmatch as materialized (
    select distinct a.documento_versao_id
      from (select distinct documento_versao_id, doc_entidade from alvo0 where doc_entidade is not null) a
      join entidade e on e.id = a.doc_entidade
      join (select distinct ce2.documento_versao_id, nullif(btrim(ce2.entidade_coluna), '') as ecol from campo_extraido ce2
             where ce2.documento_versao_id in (select documento_versao_id from alvo0) and nullif(btrim(ce2.entidade_coluna), '') is not null) c
        on c.documento_versao_id = a.documento_versao_id
     where fn_entidade_canonica(c.ecol) = fn_entidade_canonica(e.razao_social)
  ),
  alvo as materialized (
    select a.*, (m.documento_versao_id is not null) as vm,
           a.caso_id::text || '|' || coalesce(a.doc_entidade::text, '') || '|' || coalesce(a.ecol, '') || '|' || (m.documento_versao_id is not null)::text as ek,
           a.caso_id::text || '|' || coalesce(a.doc_periodo::text, '') || '|' || coalesce(a.pcol, '') || '|' || a.tipo as pk
      from alvo0 a left join vmatch m on m.documento_versao_id = a.documento_versao_id
  ),
  -- MATERIALIZED nas duas resoluções: sem isso o Postgres inlina a CTE usada uma vez e a resolução (que casa nome e período) roda LINHA a linha em vez de uma vez por combinação distinta.
  ent as materialized (
    select z.ek,
           z.id as entidade_id,
           case when z.id is null then null when z.ecol is null then 'documento' when z.n = 1 then 'coluna' else 'coluna_total' end as origem,
           case when z.id is not null then null
                when z.ecol is null then 'documento_sem_entidade'
                when z.n > 1 then 'coluna_casa_varias_entidades'
                when z.total and z.doc_entidade is null then 'documento_sem_entidade'
                when z.total and z.vm then 'coluna_total_duplica_coluna_da_entidade'
                else 'coluna_sem_entidade_no_mandato' end as motivo
      from (select k.ek, k.ecol, k.doc_entidade, k.vm, m.n,
                   (k.ecol is not null and fn_normalizar_texto(k.ecol) ~ '^(combinad|consolidad|total|soma)') as total,
                   case when k.ecol is null then k.doc_entidade
                        when m.n = 1 then m.id
                        when m.n = 0 and not k.vm and fn_normalizar_texto(k.ecol) ~ '^(combinad|consolidad|total|soma)' then k.doc_entidade end as id
              from (select distinct ek, caso_id, doc_entidade, ecol, vm from alvo) k
              left join lateral (select count(*) as n, (array_agg(e.id))[1] as id
                                   from entidade e
                                  where k.ecol is not null and e.caso_id = k.caso_id
                                    and fn_entidade_canonica(e.razao_social) = fn_entidade_canonica(k.ecol)) m on true) z
  ),
  per as materialized (
    select z.pk, z.periodo_id,
           case when z.periodo_id is null then null when z.pcol is null then 'documento' when z.anos and not z.parcial then 'coluna' else 'documento' end as origem,
           case when z.periodo_id is not null then null
                when z.pcol is not null and z.anos and z.parcial and z.doc_periodo is not null then 'periodo_parcial_fora_do_ano'
                when z.pcol is not null and z.anos and not z.parcial then 'periodo_da_coluna_nao_cadastrado'
                when z.pcol is not null and not z.anos and z.abertura then 'coluna_de_abertura'
                when z.pcol is not null and not z.anos and not fn_coluna_e_saldo(z.pcol) then 'coluna_nao_e_saldo'
                when z.doc_periodo is null and (z.pcol is null or z.anos or fn_coluna_e_saldo(z.pcol)) then 'documento_sem_periodo'
                else 'periodo_da_coluna_nao_cadastrado' end as motivo
      from (select k.pk, k.pcol, k.doc_periodo, k.parcial, k.anos, k.abertura,
                   case when k.pcol is null then k.doc_periodo
                        when k.anos and k.parcial then case when k.doc_periodo is not null and fn_anos_texto(k.pcol) && fn_anos_periodo(k.dper_tipo, k.dper_ref) then k.doc_periodo end
                        when k.anos then x.id
                        when k.abertura then null
                        when fn_coluna_e_saldo(k.pcol) then k.doc_periodo
                        else null end as periodo_id
              from (select u.pk, u.caso_id, u.pcol, u.doc_periodo, u.dper_tipo, u.dper_ref,
                           (u.pcol is not null and cardinality(fn_anos_texto(u.pcol)) > 0) as anos,
                           (u.pcol is not null and fn_coluna_e_abertura(u.pcol)) as abertura,
                           (u.pcol is not null and fn_periodo_e_parcial(u.pcol, u.tipo, u.dper_tipo, u.dper_ref)) as parcial
                      from (select distinct pk, caso_id, doc_periodo, pcol, tipo, dper_tipo, dper_ref from alvo) u) k
              left join lateral (
                -- o MESMO casamento de fn_upsert_periodo (forma canônica, o de menor referência no empate), sem o insert: o período NÃO é criado aqui. O fechamento 31/12/AAAA e o ano AAAA são o mesmo período.
                select coalesce(
                         (select p.id from periodo p where p.id = k.doc_periodo
                             and regexp_replace(fn_periodo_canonico(p.tipo, p.referencia), '^(\d{4})-12-31$', '\1') = regexp_replace(fn_periodo_canonico('outro', k.pcol), '^(\d{4})-12-31$', '\1')),
                         (select p.id from periodo p where p.caso_id = k.caso_id
                             and regexp_replace(fn_periodo_canonico(p.tipo, p.referencia), '^(\d{4})-12-31$', '\1') = regexp_replace(fn_periodo_canonico('outro', k.pcol), '^(\d{4})-12-31$', '\1')
                           order by p.referencia, p.id limit 1)) as id
                 where k.anos and not k.parcial) x on true) z
  )
  select a.campo_id, a.documento_versao_id, c.codigo,
         case when c.codigo is null then 'sem_conta' when a.inferida then 'heuristica' else 'declarada' end,
         case when c.codigo is not null then null
              when coalesce(nullif(btrim(a.secao), ''), 'NAO_CLASSIFICAVEL') = 'NAO_CLASSIFICAVEL' then 'secao_nao_declarada'
              else 'secao_fora_do_catalogo' end,
         e.entidade_id, e.origem, e.motivo, a.ecol, p.periodo_id, p.origem, p.motivo, a.pcol, a.valor_num, a.unidade, a.moeda
    from alvo a
    left join conta_canonica c on c.secao_canonica = a.secao
    join ent e on e.ek = a.ek
    join per p on p.pk = a.pk
$$;
comment on function fn_fato_resolver(uuid, boolean) is
  '0243: a identidade de cada linha elegível: conta (a seção, pelo catálogo), entidade e período (pela coluna da linha quando ela diz, pelo documento quando não, e NULOS com o motivo quando a coluna não é saldo, é de abertura, o documento é parcial ou o total duplica a coluna da entidade). p_novos: as sem fato (materializar); falso: as que já têm (repor a identidade quando o documento muda).';
revoke all on function fn_fato_resolver(uuid, boolean) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- A MATERIALIZAÇÃO. Idempotente e por conjunto: versão nula = todas (o backfill, e o reparo). security definer (o authenticated só lê fato) com a guarda de escrita.
-- -----------------------------------------------------------------------------
create or replace function fn_materializar_fatos(p_documento_versao_id uuid default null, p_origem text default 'extracao')
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_r jsonb; v_caso uuid;
begin
  if p_origem not in ('extracao', 'backfill_0243') then
    raise exception 'fn_materializar_fatos: origem % desconhecida (extracao | backfill_0243)', p_origem;
  end if;
  if p_documento_versao_id is not null then
    select d.caso_id into v_caso from documento_versao dv join documento d on d.id = dv.documento_id where dv.id = p_documento_versao_id;
  end if;
  if not fn_fato_pode_escrever(v_caso) then
    raise exception 'fn_materializar_fatos: sem permissão de escrita no mandato' using errcode = 'insufficient_privilege';
  end if;

  with ins as (
    insert into fato_financeiro
      (campo_extraido_id, documento_versao_id, conta_id, resolucao_metodo, sem_conta_motivo,
       entidade_id, entidade_origem, entidade_motivo, entidade_coluna, periodo_id, periodo_origem, periodo_motivo, periodo_coluna, valor, unidade, moeda, origem)
    select r.campo_id, r.documento_versao_id, r.conta_id, r.resolucao_metodo, r.sem_conta_motivo,
           r.entidade_id, r.entidade_origem, r.entidade_motivo, r.entidade_coluna, r.periodo_id, r.periodo_origem, r.periodo_motivo, r.periodo_coluna, r.valor, r.unidade, r.moeda, p_origem
      from fn_fato_resolver(p_documento_versao_id, true) r
    on conflict (campo_extraido_id) do nothing
    returning documento_versao_id, resolucao_metodo, sem_conta_motivo, entidade_id, periodo_id
  )
  select jsonb_build_object(
           'fatos_criados', count(*),
           'declarada', count(*) filter (where resolucao_metodo = 'declarada'),
           'heuristica', count(*) filter (where resolucao_metodo = 'heuristica'),
           'sem_conta', count(*) filter (where resolucao_metodo = 'sem_conta'),
           'sem_conta_secao_nao_declarada', count(*) filter (where sem_conta_motivo = 'secao_nao_declarada'),
           'sem_conta_secao_fora_do_catalogo', count(*) filter (where sem_conta_motivo = 'secao_fora_do_catalogo'),
           'sem_entidade', count(*) filter (where entidade_id is null),
           'sem_periodo', count(*) filter (where periodo_id is null),
           'versoes', count(distinct documento_versao_id),
           'versoes_com_linha_incerta', count(distinct documento_versao_id) filter (where resolucao_metodo <> 'declarada'))
    into v_r from ins;
  return v_r;
end $$;
comment on function fn_materializar_fatos(uuid, text) is
  '0243: cria o fato de toda linha elegível (fn_linha_vira_fato) que ainda não tem, pela identidade de fn_fato_resolver. Idempotente. Seção declarada = declarada; secao_canonica_inferida = heuristica; sem seção (nula, em branco ou NAO_CLASSIFICAVEL) ou fora do catálogo = sem_conta, com o motivo. '
  'Versão nula = todas (o backfill e o reparo: se a materialização de uma extração falhou, o evento fatos_materializacao_falhou manda rodar esta). NÃO abre pendência: quem abre é fn_materializar_fatos_da_extracao, só para extração nova. Só a conexão de serviço materializa tudo; o resto, só o mandato que escreve.';

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
create or replace function fn_materializar_fatos_da_extracao(p_documento_versao_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_tipo text; v_caso uuid; v_doc uuid; v_r jsonb; v_pend uuid; v_vigente uuid;
begin
  select d.tipo_taxonomia, d.caso_id, d.id into v_tipo, v_caso, v_doc from documento_versao dv join documento d on d.id = dv.documento_id where dv.id = p_documento_versao_id;
  if not fn_tipo_gera_fato(v_tipo) then
    return jsonb_build_object('materializado', false, 'porque', 'tipo do documento não é de demonstração');
  end if;
  if not fn_fato_pode_escrever(v_caso) then
    return jsonb_build_object('materializado', false, 'porque', 'sem permissão de escrita no mandato');
  end if;
  begin
    v_r := fn_materializar_fatos(p_documento_versao_id, 'extracao');
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
      values ('sistema:n8n', 'fatos_materializados', 'documento_versao:' || p_documento_versao_id, v_r);
  exception
    when query_canceled then raise;
    when others then
      insert into evento_auditoria (ator, acao, entidade_ref, depois)
        values ('sistema:n8n', 'fatos_materializacao_falhou', 'documento_versao:' || p_documento_versao_id,
                jsonb_build_object('sqlstate', sqlstate, 'erro', sqlerrm,
                                   'porque', 'a extração foi gravada; os fatos não. Rode fn_materializar_fatos() para completar (idempotente).'));
      v_r := jsonb_build_object('materializado', false, 'erro', sqlerrm);
  end;
  return v_r;
end $$;
comment on function fn_materializar_fatos_da_extracao(uuid) is
  '0243: fn_materializar_fatos + fn_fato_pendencia_da_versao para a versão recém-extraída, com o evento fatos_materializados (a prova de que RODOU: regra 7) e a baixa da pendência aberta das versões superadas. Tipo fora da lista: não faz nada e não grava evento. Falha: o evento fatos_materializacao_falhou, e a extração não é perdida (query_canceled não é engolido).';

-- A fusão repõe os fatos da absorvida pela entidade sobrevivente (as duas do MESMO mandato), por função com guarda: o authenticated não escreve em fato.
create or replace function fn_fato_repontar_entidade(p_caso uuid, p_de uuid, p_para uuid)
returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare v_n int;
begin
  if not fn_fato_pode_escrever(p_caso) then
    raise exception 'fn_fato_repontar_entidade: sem permissão de escrita no mandato' using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from entidade where id = p_de and caso_id = p_caso) or not exists (select 1 from entidade where id = p_para and caso_id = p_caso) then
    raise exception 'fn_fato_repontar_entidade: as duas entidades têm de ser do mandato %', p_caso;
  end if;
  update fato_financeiro set entidade_id = p_para where entidade_id = p_de;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

revoke all on function fn_materializar_fatos(uuid, text), fn_fato_pendencia_da_versao(uuid), fn_materializar_fatos_da_extracao(uuid), fn_fato_repontar_entidade(uuid, uuid, uuid) from public, anon;
grant execute on function fn_materializar_fatos(uuid, text), fn_fato_pendencia_da_versao(uuid) to service_role;
grant execute on function fn_materializar_fatos_da_extracao(uuid), fn_fato_repontar_entidade(uuid, uuid, uuid) to authenticated, service_role;

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
      for v_v in select id from documento_versao where documento_id = new.id order by n_versao loop
        perform fn_materializar_fatos_da_extracao(v_v);
      end loop;
      return null;
    elsif fn_tipo_gera_fato(old.tipo_taxonomia) and not fn_tipo_gera_fato(new.tipo_taxonomia) then
      delete from fato_financeiro where documento_versao_id in (select id from documento_versao where documento_id = new.id);
      get diagnostics v_n = row_count;
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:reclassificacao'
       where documento_id = new.id and estado = 'aberta' and motivo like 'fato:conta_incerta:%';
      insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
        values ('sistema:0243', 'fatos_removidos_por_reclassificacao', 'documento:' || new.id,
                jsonb_build_object('tipo_taxonomia', old.tipo_taxonomia), jsonb_build_object('tipo_taxonomia', new.tipo_taxonomia, 'fatos_removidos', v_n,
                  'porque', 'o documento deixou de ser de demonstração; o fato é derivado, a linha extraída (evidência) continua'));
      return null;
    end if;
  end if;
  if fn_tipo_gera_fato(new.tipo_taxonomia)
     and (new.entidade_id is distinct from old.entidade_id or new.periodo_id is distinct from old.periodo_id) then
    for v_v in select id from documento_versao where documento_id = new.id loop
      update fato_financeiro f
         set entidade_id = r.entidade_id, entidade_origem = r.entidade_origem, entidade_motivo = r.entidade_motivo,
             periodo_id = r.periodo_id, periodo_origem = r.periodo_origem, periodo_motivo = r.periodo_motivo
        from fn_fato_resolver(v_v, false) r
       where r.campo_id = f.campo_extraido_id
         and (f.entidade_id, f.entidade_origem, f.entidade_motivo, f.periodo_id, f.periodo_origem, f.periodo_motivo)
             is distinct from (r.entidade_id, r.entidade_origem, r.entidade_motivo, r.periodo_id, r.periodo_origem, r.periodo_motivo);
    end loop;
  end if;
  return null;
end $$;
revoke all on function fn_fato_segue_o_documento() from public, anon, authenticated;

drop trigger if exists trg_fato_segue_o_documento on documento;
create trigger trg_fato_segue_o_documento
  after update of entidade_id, periodo_id, tipo_taxonomia on documento
  for each row
  when (old.entidade_id is distinct from new.entidade_id or old.periodo_id is distinct from new.periodo_id or old.tipo_taxonomia is distinct from new.tipo_taxonomia)
  execute function fn_fato_segue_o_documento();

-- -----------------------------------------------------------------------------
-- fn_registrar_campos_extraidos REEMITIDA: o corpo VIGENTE (o da 0231, conferido igual ao do banco montado; a 0233 e a 0240 só a citam) com UMA chamada nova no fim. Mesma assinatura de 6 argumentos, mesma ACL (o create or replace a preserva).
-- Quem chama: o nó "Gravar Campos (Sombra)" do n8n (N8N/build-workflow.mjs) e o reprocesso do portal; nenhum muda.
-- -----------------------------------------------------------------------------
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

  -- 0243 (P27): o fato canônico nasce ACIMA da linha que acabou de ser gravada, e só aqui — o ponto por onde TODA extração passa (o n8n chama esta função; a assinatura não mudou). Fica por último de propósito:
  -- a seção já foi herdada pela árvore (0204) e a classificação contábil já rodou, então o que o fato lê é a linha FINAL. fn_materializar_fatos_da_extracao não deixa a falha dele derrubar a extração (a evidência vale mais).
  perform fn_materializar_fatos_da_extracao(p_documento_versao_id);

  return v_count;
end;
$$;

do $$
declare v_c text := obj_description('fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text, boolean, jsonb)'::regprocedure, 'pg_proc');
begin
  if position('0243' in coalesce(v_c, '')) = 0 then
    execute format('comment on function fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text, boolean, jsonb) is %L',
      coalesce(v_c, '') || ' 0243: no fim, fn_materializar_fatos_da_extracao materializa o fato_financeiro das linhas elegíveis e abre UMA pendência conta_canonica_incerta por versão quando há linha por heurística ou sem conta; a falha dele não derruba a extração.');
  end if;
end $$;

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

  -- 0243: quantos fatos têm a absorvida (contados ANTES do update do documento, cujo gatilho já leva os que herdaram dela). `fato_financeiro_entidade_id_fkey` é NO ACTION: sem repontar, o `delete from entidade` abaixo recusa a fusão INTEIRA.
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
  -- 0243: o fato cuja entidade veio de uma COLUNA da linha (o do documento o gatilho de documento já levou); por função com guarda, o authenticated não escreve em fato.
  perform fn_fato_repontar_entidade(p_caso_id, p_de_id, p_para_id);

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
  v_r := fn_materializar_fatos(null, 'backfill_0243');
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
      ('fato_financeiro_entidade_ck', 'c', '''coluna_total_duplica_coluna_da_entidade''::text'),
      ('fato_financeiro_periodo_ck', 'c', '''coluna_nao_e_saldo''::text'),
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

-- A EXTRAÇÃO NOVA ESTÁ MATERIALIZANDO (regra 7: estágio que não rodou tem a cara de estágio que rodou e não achou nada). Uma AMOSTRA, não a tabela inteira (a sonda não cresce com o dado, 0132): as linhas de extração das 20 versões
-- mais novas de documento de demonstração QUE PASSARAM PELA EXTRAÇÃO (têm o evento extracao_sombra, gravado por fn_registrar_campos_extraidos: a versão com linha inserida direto por SQL não é o que a pergunta mede; medido no run.sh: 2 versões de fixture de teste
-- caíam na amostra e davam ausência falsa). Antes do backfill e com a fn_registrar antiga ela está AUSENTE — é o que ela existe para dizer. A bijeção completa (toda linha elegível tem fato) é a consulta do README.
create or replace view instalacao_sonda_fato_financeiro_recentes as
  select 1 as ok
   where not exists (
     select 1
       from (select dv.id, d.tipo_taxonomia
               from documento_versao dv join documento d on d.id = dv.documento_id
              where fn_tipo_gera_fato(d.tipo_taxonomia)
                and exists (select 1 from evento_auditoria e where e.entidade_ref = 'documento_versao:' || dv.id and e.acao = 'extracao_sombra')
              order by dv.criada_em desc, dv.id limit 20) v
       join campo_extraido ce on ce.documento_versao_id = v.id and ce.origem_valor = 'extracao'
      where fn_linha_vira_fato(v.tipo_taxonomia, ce.chave, ce.unidade, ce.valor_num)
        and not exists (select 1 from fato_financeiro f where f.campo_extraido_id = ce.id));
comment on view instalacao_sonda_fato_financeiro_recentes is
  'Sonda da 0243: uma linha = toda linha elegível das 20 versões de demonstração mais novas que passaram pela extração (evento extracao_sombra) tem fato. Zero linhas: a extração nova NÃO está materializando (fn_registrar_campos_extraidos antiga, backfill não aplicado ou a materialização falhando: veja evento fatos_materializacao_falhou).';

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

grant select on instalacao_sonda_fato_financeiro_tipos to authenticated, service_role;
grant select on instalacao_sonda_fato_financeiro_constraints, instalacao_sonda_fato_financeiro_so_secao, instalacao_sonda_fato_financeiro_recentes,
                instalacao_sonda_fato_financeiro_pendencia_tipo to authenticated, service_role;  -- service_role: grant_views_service_role (0214)

-- -----------------------------------------------------------------------------
-- A SONDA. Marcadores em CÓDIGO, nunca de comentário.
-- -----------------------------------------------------------------------------
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
   'Linha elegível das 20 versões de demonstração mais novas sem fato: a extração nova não está materializando (função antiga, backfill por aplicar, ou falha engolida: evento fatos_materializacao_falhou).', 'importante', 1111),
  ('fato_financeiro_pendencia_tipo', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_pendencia_tipo', null, 1,
   'Sem o rótulo conta_canonica_incerta em pendencia_tipo a pendência da heurística não abre.', 'importante', 1112),
  ('registrar_materializa_fatos', '0243', 'corpo', 'fn_registrar_campos_extraidos', 'perform fn_materializar_fatos_da_extracao(p_documento_versao_id);', null,
   'Corpo anterior à 0243 (ou reemitido a partir de um antigo): a extração nova grava a linha e NÃO cria o fato nem abre a pendência da heurística.', 'importante', 1113),
  ('materializa_so_o_elegivel', '0243', 'corpo', 'fn_fato_resolver', 'fn_linha_vira_fato(x.tipo', null,
   'A resolução precisa perguntar a fn_linha_vira_fato: sem isso virar fato é "tudo que tem valor" (Estoque, Razão, subtotal).', 'importante', 1114),
  ('materializa_idempotente', '0243', 'corpo', 'fn_materializar_fatos', 'on conflict (campo_extraido_id) do nothing', null,
   'Sem o on conflict a segunda chamada (o reenvio, o reparo) morre na FK única ou duplica a evidência.', 'importante', 1115),
  ('materializa_conta_so_pela_secao', '0243', 'corpo', 'fn_fato_resolver', 'left join conta_canonica c on c.secao_canonica = a.secao', null,
   'A conta do fato é a SEÇÃO da linha, pelo catálogo; sem seção, sem conta. Outro critério (o tipo do documento, a raiz) inventaria a conta.', 'importante', 1116),
  ('materializa_periodo_pela_coluna', '0243', 'corpo', 'fn_fato_resolver', 'fn_anos_texto(u.pcol)', null,
   'O período do fato é o da COLUNA da linha quando ela nomeia um ano; o do documento no balanço de duas colunas de ano atribui o saldo de 2024 a 2025.', 'importante', 1117),
  ('periodo_so_da_coluna_de_saldo', '0243', 'corpo', 'fn_fato_resolver', 'when fn_coluna_e_saldo(k.pcol) then k.doc_periodo', null,
   'Só a coluna de SALDO sem ano herda o período do documento: Débito, Crédito, Orçado, Variação e percentual com o mesmo período dão fatos idênticos em (conta, entidade, período) e a soma dobra (reproduzido: 1.310 no lugar de 150).', 'importante', 1118),
  ('periodo_parcial_nao_vai_para_o_ano', '0243', 'corpo', 'fn_fato_resolver', 'fn_periodo_e_parcial(u.pcol, u.tipo', null,
   'Documento de período PARCIAL (balancete de junho) com coluna "2025" casava o período ANUAL 2025: o acumulado de junho virava a receita do ano.', 'importante', 1119),
  ('entidade_total_nao_duplica_a_coluna', '0243', 'corpo', 'fn_fato_resolver', 'when m.n = 0 and not k.vm', null,
   'A coluna total só é a entidade do documento quando nenhuma coluna do documento já casa essa entidade pelo nome (fn_coluna_entidade, 0023): sem isso a entidade recebe a coluna dela E o total.', 'importante', 1120),
  ('tipos_que_geram_fato', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_tipos', null, 10,
   'A lista dos tipos de demonstração perdeu um tipo (linha de demonstração fica sem fato), ou ganhou Razão/Notas (o que é só evidência vira fato). Conferida tipo a tipo, não pelo corpo.', 'importante', 1121),
  ('pendencia_uma_por_versao', '0243', 'corpo', 'fn_fato_pendencia_da_versao', '''fato:conta_incerta:''', null,
   'A pendência da heurística é UMA por documento-versão (o motivo carrega a versão). Outro motivo = uma por linha (fila de ruído) ou nenhuma.', 'importante', 1122),
  ('extracao_nova_abre_a_pendencia', '0243', 'corpo', 'fn_materializar_fatos_da_extracao', 'fn_fato_pendencia_da_versao(p_documento_versao_id)', null,
   'A extração nova materializa o fato mas não abre a pendência: heurística sem pendência é o palpite silencioso que a P27 existe para impedir.', 'importante', 1123),
  ('fato_segue_o_documento_gatilho', '0243', 'gatilho', 'documento.trg_fato_segue_o_documento', 'fn_fato_segue_o_documento', null,
   'Sem ele corrigir a entidade, o período ou o tipo do documento deixa os fatos com a identidade ANTIGA (ou sem fato, ou com fato de documento que deixou de ser demonstração), em silêncio.', 'importante', 1124),
  ('fundir_entidade_leva_os_fatos', '0243', 'corpo', 'fn_fundir_entidade', 'fatos_repontados', null,
   'Corpo anterior à 0243: com a FK de fato_financeiro.entidade_id a fusão falha em `delete from entidade` (e antes dela os fatos apontariam para uma entidade que não existe).', 'importante', 1125),
  ('fato_mesmo_caso_gatilho', '0243', 'gatilho', 'fato_financeiro.trg_fato_mesmo_caso', 'fn_fato_mesmo_caso', null,
   'Sem ele a entidade ou o período de um fato podem ser de OUTRO mandato (a escrita só passa por funções, mas a garantia tem de ser do banco).', 'importante', 1126)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0243', revisado_em = current_date,
       observacao = 'A 0243 cria fato_financeiro (o fato acima de campo_extraido: conta = seção, entidade e período pela coluna da linha), a materialização, a pendência conta_canonica_incerta (uma por versão, só extração nova), o backfill sem pendência, o gatilho do documento, reemite fn_registrar_campos_extraidos e fn_fundir_entidade, 5 views de sonda e 20 requisitos novos (ordem 1105-1126).'
 where id = true;

commit;
