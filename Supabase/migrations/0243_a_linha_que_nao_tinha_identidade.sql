-- 0243 — A LINHA QUE NÃO TINHA IDENTIDADE: `fato_financeiro` acima de `campo_extraido` (P27, Fase 3, etapa 3.2) — o fato canônico (conta = a SEÇÃO da linha, entidade e período pela coluna da linha quando ela diz), a pendência da heurística e o backfill que não abre fila.
-- (Cria 1 tabela, fato_financeiro, 5 funções (fn_tipo_gera_fato, fn_linha_vira_fato, fn_materializar_fatos, fn_fato_pendencia_da_versao, fn_materializar_fatos_da_extracao) + fn_materializar_fatos_backfill + a do gatilho, 1 gatilho em documento, 1 rótulo de pendencia_tipo
--  (conta_canonica_incerta), 4 views da sonda e 18 requisitos novos (ordem 1105-1122). Reemite INTEIRAS fn_registrar_campos_extraidos (corpo da 0231, conferido igual ao do banco montado; mesma assinatura de 6 args, mesma ACL; UMA chamada nova no fim) e fn_fundir_entidade
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
--   5. ENTIDADE E PERÍODO DO FATO são os da COLUNA da linha quando a coluna diz, e os do documento quando não: o balanço de duas colunas de ano atribuiria o saldo de 2024 a 2025 se valesse o `periodo_id` do documento. Medido em produção: das 85.531, 21.930 têm a coluna de período resolvida para um período DIFERENTE do do documento
--      (20.630 de versão vigente). Entidade: `coluna` (casa UMA entidade do mandato por fn_entidade_canonica; empate NÃO escolhe, 0153), `coluna_total` (Combinado/Consolidado/Total/Soma = a entidade do documento) ou `documento`. Período: `coluna` (um período do MESMO mandato tem a forma canônica da coluna; 31/12/AAAA e AAAA são o mesmo)
--      ou `documento` (sem coluna, ou coluna sem ano que não é de abertura); "Saldo Inicial/anterior" é o ano ANTERIOR ao do documento (0199 b) e fica NULO. O que não resolve fica NULO com a coluna explícita ao lado, nunca a do documento por falta de coisa melhor, e o período NÃO é criado: criar `periodo` muda checklist e completude, é decisão do dono.
--      Medido em produção (read-only, a mesma consulta da migration): sem entidade 1.337 fatos (1.172 linhas com entidade_coluna que não casa nenhuma entidade do mandato em 157 combinações, 99 da coluna Eliminações, 22+43+1 de documento sem entidade) e sem período 13.323: 8.841 são linhas de coluna Saldo Inicial/anterior (o ano ANTERIOR ao do documento: NULO por desenho, ver acima), 3 de documento sem período e os ~4,5 mil restantes têm coluna de ano ou data que nenhum período do mandato tem (o balanço de dois anos cadastra só o do documento). Das 72.964 linhas elegíveis com periodo_coluna (de 85.531), 32.438 têm coluna sem ano que não é de abertura (Saldo Final/atual, Débito...: o período do documento), 25.173 coluna de data, 6.512 de ano simples.
--      O critério do plano "0 fato sem identidade" vale POR CONSTRUÇÃO para a conta (nulo só com sem_conta) e é MEDIDO para a entidade e o período: não é zero no corpus, e o motivo de cada nulo é a coluna ao lado.
--   6. A PENDÊNCIA (`conta_canonica_incerta`, rótulo novo de pendencia_tipo, complementar e sobrepujável: avisa, não trava) é UMA por documento-versão (motivo `fato:conta_incerta:<versão>`), lista as linhas por heurística ou sem conta (as 12 primeiras no texto, com o EFEITO: fato sem identidade não entra em seção nenhuma),
--      só para fato de origem `extracao`; é convergente (reflete o estado atual, resolve-se sozinha quando não sobra linha incerta) e a resolvida por PESSOA não é reaberta pelo reenvio (como a 0231). Só abre pendência a CONTA incerta; entidade e período nulos ficam no fato, consultáveis, sem fila (a pendência de entidade/período do documento já existe, 0153/0178).
--   7. O PONTO ÚNICO é `fn_registrar_campos_extraidos` (o n8n chama por ela; o reprocesso do portal também): a chamada vai no FIM, depois da herança pela árvore (0204) e da classificação contábil, para o fato ler a linha FINAL. A assinatura não muda: o n8n não é republicado. Chamadores listados por grep (N8N/build-workflow.mjs, N8N/lib/extract.mjs,
--      os testes, portal/src/lib/supabase/reprocesso.ts e api/intake/status só a citam em comentário). A falha do fato NÃO derruba a extração (a evidência vale mais que o derivado): sub-bloco que grava o evento `fatos_materializacao_falhou` e segue; `fn_materializar_fatos()` repara. O evento `fatos_materializados` é o sinal de que RODOU (regra 7).
--   8. O FATO SEGUE O DOCUMENTO: corrigir a entidade ou o período do documento (a correção humana de entidade_incorreta/periodo_incorreto) leva os fatos que herdaram dele, por gatilho; os de coluna não se movem. E `fn_fundir_entidade` repõe os fatos da absorvida: a FK `fato_financeiro_entidade_id_fkey` é NO ACTION e, sem isso, o `delete from entidade` recusava a fusão INTEIRA (o defeito da 0213 com outra tabela).
--   8b. AS FKs DE ENTIDADE E DE PERÍODO SÃO `DEFERRABLE INITIALLY DEFERRED`: a primeira versão, imediata, derrubava `delete from caso` (historico_do_caso.test.sql, no run.sh): a cascata apaga a entidade por um caminho e os fatos por outro, mais fundo (documento > versão > linha > fato), e a conferência da FK imediata rodava com os fatos ainda lá.
--      A sonda confere o DEFERRABLE no predicado (uma FK recriada imediata é acusada) e o teste apaga um mandato com fatos.
--   9. RLS e grants como as tabelas por caso (0216): leitura e insert pela versão do documento; o authenticated só repõe a identidade (UPDATE de 4 colunas, como caso_pergunta, 0213); apagar só em cascata. `valor` não é alterável por ele.
--  10. DESEMPENHO DO BACKFILL. Medido no local com 123.969 linhas de campo_extraido (as fixtures ×30, sintético: serve só para o TEMPO) e 76.229 elegíveis: 2,96 s o backfill e 0,12 s a segunda chamada (idempotente). Na primeira versão levava 21 s: `fn_papel_linha` (~180 µs) rodava POR LINHA; medido em produção, 100.215 linhas de demonstração com valor têm
--      só 6.841 combinações (tipo, rótulo, unidade) distintas (15x menos). Agora o papel roda uma vez por combinação, em duas CTEs `MATERIALIZED` (uma só e o Postgres empurra o filtro para dentro do distinct e volta a chamar por linha: medido). Teto: o tempo cresce com as linhas SEM fato, e a chamada por versão (a extração nova) lê só as da versão.
--
-- MEDIDO EM PRODUÇÃO ANTES DE ESCREVER (11/11/2026, somente leitura, a mesma consulta de resolução da migration sem escrever; versões vigentes por fn_versao_atual) — o que o backfill criaria: 85.531 fatos em demonstração.
--   Vigentes 68.523: declarada 62.075, heuristica 2.194, sem_conta 4.254 (todas secao_nao_declarada; 0 fora_do_catalogo). Versões antigas 17.008: declarada 14.616, heuristica 994, sem_conta 1.398.
--   Linhas incertas (heurística + sem conta): 8.840, em 563 documentos-versão (536 vigentes) de 48 mandatos — as 563 pendências que o backfill NÃO abre (a decisão do dono; a 0179 abriu 365 de ruído e 347 já estavam julgadas ruído pela triagem). O resumo do backfill (evento fato_financeiro_backfill) conta
--   essas linhas, diz que ficaram sem pendência e por quê; o método gravado e a origem `backfill_0243` deixam a incerteza consultável sem fila.
--
-- O LEITOR SÓ-LEITURA (`supabase_read_only_user`): as views da sonda chamam fn_tipo_gera_fato e fn_linha_vira_fato (e esta, fn_papel_linha) com o privilégio de quem LÊ; o bloco condicional de grant (como 0233/0234 e a correção da 0242) as entrega a ele, e Supabase/test/sonda_para_o_leitor_somente_leitura.test.sql o prova.
-- A SONDA (como a 0242: por constraint e por comportamento, não por contagem). A tabela; as 3 policies; as 13 constraints estruturais por nome e predicado (view); nenhum fato numa conta que não é seção (view pelos nós sem seção e o índice de conta_id: custo que não cresce com os fatos); a extração nova está materializando (view sobre as 20 versões de demonstração mais
-- novas que passaram pela extração, com o evento extracao_sombra: uma AMOSTRA, porque a sonda não cresce com o dado, 0132 — e ela fica AUSENTE enquanto o backfill não for aplicado, que é a resposta honesta; a bijeção completa é a consulta do README); o rótulo da pendência; os corpos (a fn_registrar com a chamada, a materialização que pergunta a fn_linha_vira_fato, é idempotente, acha a conta só pela seção
-- e o período pela coluna, a lista de tipos, a pendência por versão, a que a extração nova abre, a fusão que repõe); o gatilho do documento pela função que ele tem de chamar.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/fato_financeiro.test.sql — 95 asserts (95 execuções), lidos no log da rodada (NOTICE `fato_financeiro: 95 asserts executados, N reprovados`; a migration aplicou e o teste aparece no log em todas). Controle (migration intacta): 0 dos 95 reprovam.
-- Cada sabotagem é a função reemitida sobre o banco montado (cópia por template; o texto da função, com a troca, de pg_get_functiondef; a troca CONFERIDA como aplicada), o teste rodado inteiro e o log lido atrás de FALHOU:. Por parte:
--   * elegibilidade (fn_linha_vira_fato): só "tem valor" (sem tipo e sem papel) 9 dos 95; sem o papel conta (o subtotal vira fato) 9 dos 95; sem a lista de tipos (Estoque vira fato) 9 dos 95;
--   * a conta só pela seção: a linha sem seção ganha a raiz da demonstração (conta inventada) 14 dos 95; a seção que o catálogo não conhece vira a mais parecida 10 dos 95;
--   * o método: a marca secao_canonica_inferida ignorada (heuristica vira declarada) 5 dos 95;
--   * a linha sem valor virando fato de valor zero 8 dos 95;
--   * a pendência: a extração nova sem chamar fn_fato_pendencia_da_versao 8 dos 95; o motivo da pendência com uuid (uma por reenvio, não uma por versão) 4 dos 95; o backfill abrindo pendência 2 dos 95;
--   * o período e a entidade: o período sempre o do documento (a coluna ignorada) 6 dos 95; a entidade da coluna ignorada 4 dos 95; qualquer coluna sem casamento (a Eliminações) virando a entidade do documento 2 dos 95;
--   * o ponto único: fn_registrar_campos_extraidos sem a chamada nova 37 dos 95; a falha da materialização derrubando a extração (o `exception when others` trocado) 3 dos 95;
--   * o fato segue o documento: o gatilho removido 5 dos 95; a fusão sem repor os fatos (com a FK adiada ela não cai mais na hora: os fatos ficam apontando para a entidade apagada, e o assert pega) 2 dos 95;
--   * a RLS: a policy de insert removida 4 dos 95; as FKs de entidade e de período IMEDIATAS (a exclusão do mandato atropela a cascata) 5 dos 95;
--   * o LEITOR SÓ-LEITURA (Supabase/test/sonda_para_o_leitor_somente_leitura.test.sql, 6 asserts, controle 0 dos 6; o papel é criado pelo run.sh ANTES das migrations; sabotagem = `revoke execute` sobre o banco montado, equivalente a tirar o bloco condicional de grant): sem o grant da 0242 (fn_conta_canonica_orfas) 4 dos 6; sem o da 0243 (fn_tipo_gera_fato e fn_linha_vira_fato) 4 dos 6; só o da transitiva fn_papel_linha 4 dos 6 (a sonda inteira dá permission denied);
--   * a sonda cega: as views do "recentes" e "só seção" fixas em ok 2 dos 95; a view das constraints fixa em 13 linhas 2 dos 95; cada constraint estrutural dropada e as funções de corpo antigo são acusadas pelos próprios asserts da parte k (a sonda não é o único alarme).
-- ACHADOS DA MEDIÇÃO (não do desenho): (1) fn_papel_linha por linha: 21 s no backfill de 124 mil linhas, 2,96 s por combinação distinta; (2) o filtro empurrado para dentro do distinct (uma só CTE) refazia a conta por linha; (3) a FK nova de entidade derrubaria a fusão (fn_fundir_entidade), e o gatilho do documento é o que
-- mantém a identidade do fato quando uma pessoa corrige o documento; (4) o assert que chama `pg_temp` como `authenticated` morre em `permission denied for sequence`: os asserts rodam depois do `reset role`; (5) com a falha do fato ou da fusão fora do sub-bloco, a sabotagem ABORTA o arquivo e a contagem some: as chamadas ficaram em sub-bloco para a medição contar. (6) a FK imediata de fato_financeiro.entidade_id derrubou `delete from caso` no historico_do_caso.test.sql do run.sh (cascatas em profundidades diferentes): FKs adiadas e um assert de exclusão de mandato; (7) a sonda `recentes` dava ausência falsa no run.sh com 2 versões de fixture de teste (linhas inseridas direto): a amostra passou a ser só de versões com o evento extracao_sombra.
-- O QUE FICA DE FORA (declarado): conta-folha (caixa, clientes…) e a hierarquia pai/filho do fato são a P28+; subtotal = Σ folhas é a P28; reconciliação sobre o fato é a P29. A transcrição humana (fn_registrar_transcricao_humana, 0129) e a reclassificação do TIPO do documento depois da extração NÃO materializam fato sozinhas: `select fn_materializar_fatos();` completa
-- (idempotente), e a sonda "recentes" olha só linhas de origem extracao. O período não é criado quando a coluna nomeia um ano que o mandato não tem (cerca de 4,5 mil dos 13.323 fatos sem período em produção) e o Saldo Inicial/anterior (8.841) NÃO é resolvido para o período do ano anterior, mesmo quando o mandato o tem: reusar a regra de abertura da 0234 (só em BALANCO/BALANCETE e documento não parcial) é decisão para a P28/P29. Moeda e unidade vão como vieram: sem normalização de escala aqui.

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
  entidade_coluna     text,
  periodo_id          uuid references periodo(id) deferrable initially deferred,
  periodo_origem      text,
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
  constraint fato_financeiro_entidade_ck check (
    (entidade_id is null) = (entidade_origem is null)
    and (entidade_origem is null or entidade_origem in ('documento', 'coluna', 'coluna_total'))),
  constraint fato_financeiro_periodo_ck check (
    (periodo_id is null) = (periodo_origem is null)
    and (periodo_origem is null or periodo_origem in ('documento', 'coluna'))),
  constraint fato_financeiro_origem_ck check (origem in ('extracao', 'backfill_0243'))
);
create index if not exists fato_financeiro_versao_idx on fato_financeiro (documento_versao_id);
create index if not exists fato_financeiro_entidade_idx on fato_financeiro (entidade_id);
create index if not exists fato_financeiro_conta_idx on fato_financeiro (conta_id);

comment on table fato_financeiro is
  '0243 (P27): o fato canônico ACIMA de campo_extraido, que não muda (ADR 01). Uma linha por linha extraída elegível (FK única): só documento de demonstração (fn_tipo_gera_fato), só papel conta (fn_papel_linha), só com valor (ausência não vira fato: regra 1). '
  'A identidade é a SEÇÃO (nó de conta_canonica; folha é a P28+). Quem consome escolhe a versão vigente com fn_versao_atual. resolucao_metodo: declarada (a IA deu a seção), heuristica (fn_secao_canonica_da_secao_bruta / fn_herdar_secao_pela_arvore, 0203/0204: secao_canonica_inferida) ou sem_conta (conta_id nulo, com o motivo): "não sei a conta" é estado, nunca um palpite.';
comment on column fato_financeiro.conta_id is 'Nó de conta_canonica que é SEÇÃO (secao_canonica não nula). NULL só com resolucao_metodo = sem_conta (check): linha sem seção declarada, ou com seção que o catálogo não conhece, NÃO ganha conta inventada — nem a raiz da demonstração pelo tipo do documento.';
comment on column fato_financeiro.entidade_origem is 'De onde veio a entidade: documento (documento.entidade_id; a linha não tem entidade_coluna), coluna (entidade_coluna casa UMA entidade do mandato por fn_entidade_canonica) ou coluna_total (coluna Combinado/Consolidado/Total/Soma: a entidade do documento, o mesmo vocabulário de fn_coluna_entidade, 0023). NULL = não resolvida e entidade_id NULL: a coluna Eliminações, o nome que casa duas entidades (0153: nunca escolher no empate) ou documento sem entidade. A entidade_coluna da linha fica ao lado, explícita.';
comment on column fato_financeiro.periodo_origem is 'De onde veio o período: coluna (periodo_coluna nomeia um ano/data e um periodo do MESMO mandato tem essa forma canônica, fn_periodo_canonico; prevalece sobre o do documento) ou documento (a linha não tem coluna, ou a coluna não nomeia ano e não é de abertura). NULL = não resolvida e periodo_id NULL: coluna de ano que nenhum período do mandato tem (o período NÃO é criado aqui), ou Saldo Inicial/anterior (é o ano ANTERIOR ao do documento, 0199 b). O periodo_coluna da linha fica ao lado.';
comment on column fato_financeiro.valor is 'valor_num da linha, como veio. Escala e moeda NÃO são normalizadas aqui (não há regra pronta): unidade e moeda seguem ao lado.';

-- -----------------------------------------------------------------------------
-- RLS e grants: por mandato pela versão (0216: o padrão de documento_fato/campo_classe_*). O authenticated insere (fn_registrar_campos_extraidos corre como quem chama) e só
-- repõe a identidade (fusão de entidade, correção de entidade/período do documento): UPDATE de coluna, como caso_pergunta (0213). Apagar só em cascata.
-- -----------------------------------------------------------------------------
alter table fato_financeiro enable row level security;
drop policy if exists fato_financeiro_read on fato_financeiro;
create policy fato_financeiro_read on fato_financeiro for select to authenticated
  using ((select fn_eh_socio()) or documento_versao_id in (select id from documento_versao));
drop policy if exists fato_financeiro_insert on fato_financeiro;
create policy fato_financeiro_insert on fato_financeiro for insert to authenticated
  with check ((select fn_eh_socio()) or documento_versao_id in (select v.id from documento_versao v join documento d on d.id = v.documento_id where d.caso_id in (select c from fn_casos_escreviveis() c)));
drop policy if exists fato_financeiro_update on fato_financeiro;
create policy fato_financeiro_update on fato_financeiro for update to authenticated
  using ((select fn_eh_socio()) or documento_versao_id in (select id from documento_versao))
  with check ((select fn_eh_socio()) or documento_versao_id in (select v.id from documento_versao v join documento d on d.id = v.documento_id where d.caso_id in (select c from fn_casos_escreviveis() c)));
grant select, insert on fato_financeiro to authenticated;
grant update (entidade_id, entidade_origem, periodo_id, periodo_origem) on fato_financeiro to authenticated;
grant select, insert, update, delete on fato_financeiro to service_role;

-- -----------------------------------------------------------------------------
-- O QUE É ELEGÍVEL: uma lista só, e todo o resto (backfill, extração nova, sonda, teste) pergunta a ela.
-- -----------------------------------------------------------------------------
create or replace function fn_tipo_gera_fato(p_tipo text)
returns boolean language sql immutable as $$
  select coalesce(p_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DRE', 'FLUXO_CAIXA', 'DVA', 'DMPL', 'DF_AUDITADA'), false)
$$;
comment on function fn_tipo_gera_fato(text) is
  '0243: os tipos de documento cujas linhas viram fato_financeiro: as demonstrações. BALANCO, BALANCETE, COMBINADO, DRE e FLUXO_CAIXA são as 5 de ESTRUTURA_POR_TIPO (statement-templates.ts); DVA e DMPL são as 2 que a 0024 pôs na taxonomia e o portal já roteia por seção (FAMILIA_POR_SECAO_CANONICA); DF_AUDITADA traz as demonstrações juntas e cada linha vai para a SUA seção. '
  'A categoria Contábil/Demonstrações da taxonomia NÃO serve de proxy: ela inclui RAZAO e NOTAS_EXPL. Estoque, Razão, Aging, Mapa de Dívida e o resto continuam só evidência.';

create or replace function fn_linha_vira_fato(p_tipo text, p_chave text, p_unidade text, p_valor numeric)
returns boolean language sql immutable as $$
  select p_valor is not null and fn_tipo_gera_fato(p_tipo) and fn_papel_linha(p_chave, p_tipo, p_unidade) = 'conta'
$$;
comment on function fn_linha_vira_fato(text, text, text, numeric) is
  '0243: a linha de campo_extraido vira fato quando (1) tem valor (célula vazia é ausência, não zero: regra 1), (2) o documento é de demonstração e (3) o papel é conta (fn_papel_linha): subtotal é a P28, derivado e série mensal não são conta.';

revoke all on function fn_tipo_gera_fato(text), fn_linha_vira_fato(text, text, text, numeric) from public, anon;
grant execute on function fn_tipo_gera_fato(text), fn_linha_vira_fato(text, text, text, numeric) to authenticated, service_role;
-- E ao leitor só-leitura da API de gerenciamento (`supabase_read_only_user`), como a 0233, a 0234 e a correção da 0242: a view `instalacao_sonda_fato_financeiro_recentes` chama estas funções com o privilégio de quem LÊ, e sem o
-- grant a sonda INTEIRA fica ilegível para quem lê produção sem escrever (o defeito que a 0242 teve em 11/11/2026). fn_papel_linha entra porque fn_linha_vira_fato a chama (chamada transitiva: o Postgres confere o EXECUTE de cada função da cadeia
-- com o leitor; em produção ela já o tem, medido, e o grant é idempotente; no banco do run.sh, que cria o papel antes das migrations, é ele que o dá).
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    execute 'grant execute on function fn_tipo_gera_fato(text) to supabase_read_only_user';
    execute 'grant execute on function fn_linha_vira_fato(text, text, text, numeric) to supabase_read_only_user';
    execute 'grant execute on function fn_papel_linha(text, text, text) to supabase_read_only_user';
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- A MATERIALIZAÇÃO. Idempotente (o que já tem fato fica como está) e por conjunto: p_documento_versao_id nulo = todas as versões (o backfill, e o reparo).
-- -----------------------------------------------------------------------------
create or replace function fn_materializar_fatos(p_documento_versao_id uuid default null, p_origem text default 'extracao')
returns jsonb language plpgsql as $$
declare
  v_r jsonb;
begin
  if p_origem not in ('extracao', 'backfill_0243') then
    raise exception 'fn_materializar_fatos: origem % desconhecida (extracao | backfill_0243)', p_origem;
  end if;

  with cand as materialized (
    select ce.id as campo_id, ce.documento_versao_id, d.caso_id, d.tipo_taxonomia as tipo, ce.chave, d.entidade_id as doc_entidade, d.periodo_id as doc_periodo,
           ce.valor_num, ce.unidade, ce.moeda, ce.secao_canonica as secao, ce.secao_canonica_inferida as inferida,
           nullif(btrim(ce.entidade_coluna), '') as ecol, nullif(btrim(ce.periodo_coluna), '') as pcol,
           d.caso_id::text || '|' || coalesce(d.entidade_id::text, '') || '|' || coalesce(nullif(btrim(ce.entidade_coluna), ''), '') as ek,
           d.caso_id::text || '|' || coalesce(d.periodo_id::text, '') || '|' || coalesce(nullif(btrim(ce.periodo_coluna), ''), '') as pk
      from campo_extraido ce
      join documento_versao dv on dv.id = ce.documento_versao_id
      join documento d on d.id = dv.documento_id
     where (p_documento_versao_id is null or ce.documento_versao_id = p_documento_versao_id)
       and ce.valor_num is not null and fn_tipo_gera_fato(d.tipo_taxonomia)
       and not exists (select 1 from fato_financeiro f where f.campo_extraido_id = ce.id)
  ),
  -- O papel da linha (fn_papel_linha, ~180 µs) UMA vez por (tipo, rótulo, unidade) distintos, não por linha. Medido em produção em 11/11/2026: 100.215 linhas de demonstração com valor, 6.841 combinações distintas (15x menos chamadas).
  -- Medido no local com 124 mil linhas: por linha 21 s; por combinação distinta, o tempo está no cabeçalho. fn_linha_vira_fato é o predicado ÚNICO (a sonda e o teste o usam): o valor entra como 1 porque ele só pergunta se é nulo, e a CTE acima já tirou os nulos.
  -- (duas CTEs, não uma subconsulta: o Postgres empurra o filtro para DENTRO do distinct e chama fn_papel_linha por LINHA de novo — medido, 21 s.)
  rotulos as materialized (select distinct tipo, chave, unidade from cand),
  papel as materialized (
    select x.tipo, x.chave, x.unidade from rotulos x where fn_linha_vira_fato(x.tipo, x.chave, x.unidade, 1)
  ),
  alvo as materialized (
    select c.* from cand c join papel p on p.tipo = c.tipo and p.chave = c.chave and coalesce(p.unidade, '') = coalesce(c.unidade, '')
  ),
  -- MATERIALIZED nas duas resoluções: sem isso o Postgres inlina a CTE usada uma vez e a resolução (que casa nome e período) roda LINHA a linha em vez de uma vez por combinação distinta.
  ent as materialized (
    select k.ek, k.caso_id, k.doc_entidade, k.ecol,
           case when k.ecol is null then k.doc_entidade
                when m.n = 1 then m.id
                when m.n = 0 and fn_normalizar_texto(k.ecol) ~ '^(combinad|consolidad|total|soma)' then k.doc_entidade end as entidade_id,
           case when k.ecol is null then case when k.doc_entidade is not null then 'documento' end
                when m.n = 1 then 'coluna'
                when m.n = 0 and fn_normalizar_texto(k.ecol) ~ '^(combinad|consolidad|total|soma)' and k.doc_entidade is not null then 'coluna_total' end as origem
      from (select distinct ek, caso_id, doc_entidade, ecol from alvo) k
      left join lateral (select count(*) as n, (array_agg(e.id))[1] as id
                           from entidade e
                          where k.ecol is not null and e.caso_id = k.caso_id
                            and fn_entidade_canonica(e.razao_social) = fn_entidade_canonica(k.ecol)) m on true
  ),
  per as materialized (
    select k.pk, k.caso_id, k.doc_periodo, k.pcol,
           case when k.pcol is null then k.doc_periodo
                when cardinality(fn_anos_texto(k.pcol)) > 0 then x.id
                when fn_coluna_e_abertura(k.pcol) then null
                else k.doc_periodo end as periodo_id,
           case when k.pcol is null then case when k.doc_periodo is not null then 'documento' end
                when cardinality(fn_anos_texto(k.pcol)) > 0 then case when x.id is not null then 'coluna' end
                when fn_coluna_e_abertura(k.pcol) then null
                else case when k.doc_periodo is not null then 'documento' end end as origem
      from (select distinct pk, caso_id, doc_periodo, pcol from alvo) k
      left join lateral (
        -- o MESMO casamento de fn_upsert_periodo (forma canônica, o de menor referência no empate), sem o insert: o período NÃO é criado aqui. O fechamento 31/12/AAAA e o ano AAAA são o mesmo período.
        select coalesce(
                 (select p.id from periodo p where p.id = k.doc_periodo
                     and regexp_replace(fn_periodo_canonico(p.tipo, p.referencia), '^(\d{4})-12-31$', '\1') = regexp_replace(fn_periodo_canonico('outro', k.pcol), '^(\d{4})-12-31$', '\1')),
                 (select p.id from periodo p where p.caso_id = k.caso_id
                     and regexp_replace(fn_periodo_canonico(p.tipo, p.referencia), '^(\d{4})-12-31$', '\1') = regexp_replace(fn_periodo_canonico('outro', k.pcol), '^(\d{4})-12-31$', '\1')
                   order by p.referencia, p.id limit 1)) as id
         where k.pcol is not null) x on true
  ),
  ins as (
    insert into fato_financeiro
      (campo_extraido_id, documento_versao_id, conta_id, resolucao_metodo, sem_conta_motivo,
       entidade_id, entidade_origem, entidade_coluna, periodo_id, periodo_origem, periodo_coluna, valor, unidade, moeda, origem)
    select a.campo_id, a.documento_versao_id, c.codigo,
           case when c.codigo is null then 'sem_conta' when a.inferida then 'heuristica' else 'declarada' end,
           case when c.codigo is not null then null
                when coalesce(nullif(btrim(a.secao), ''), 'NAO_CLASSIFICAVEL') = 'NAO_CLASSIFICAVEL' then 'secao_nao_declarada'
                else 'secao_fora_do_catalogo' end,
           e.entidade_id, e.origem, a.ecol, p.periodo_id, p.origem, a.pcol, a.valor_num, a.unidade, a.moeda, p_origem
      from alvo a
      left join conta_canonica c on c.secao_canonica = a.secao
      join ent e on e.ek = a.ek
      join per p on p.pk = a.pk
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
  '0243: cria o fato de toda linha elegível (fn_linha_vira_fato) que ainda não tem. Idempotente. Seção declarada = declarada; secao_canonica_inferida = heuristica; sem seção (nula, em branco ou NAO_CLASSIFICAVEL) ou fora do catálogo = sem_conta, com o motivo. Entidade e período pela COLUNA da linha quando ela diz (ver as colunas de fato_financeiro), pelo documento quando não. '
  'versão nula = todas (o backfill e o reparo: se a materialização de uma extração falhou, o evento fatos_materializacao_falhou manda rodar esta). NÃO abre pendência: quem abre é fn_materializar_fatos_da_extracao, só para extração nova.';

-- A PENDÊNCIA: UMA por documento-versão, com as linhas resolvidas por heurística ou sem conta. Convergente: reflete o estado atual dos fatos de EXTRAÇÃO da versão (o backfill, origem backfill_0243, nunca entra aqui).
create or replace function fn_fato_pendencia_da_versao(p_documento_versao_id uuid)
returns uuid language plpgsql as $$
declare
  v_caso uuid; v_doc uuid; v_nome text;
  v_h int; v_s int; v_lista text; v_desc text; v_pend uuid;
  v_motivo text := 'fato:conta_incerta:' || p_documento_versao_id;
begin
  select d.caso_id, d.id, dv.nome_original into v_caso, v_doc, v_nome
    from documento_versao dv join documento d on d.id = dv.documento_id where dv.id = p_documento_versao_id;
  if v_doc is null then return null; end if;

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

  select id into v_pend from pendencia where caso_id = v_caso and motivo = v_motivo and estado <> 'resolvida' limit 1;

  if v_h + v_s > 0 then
    v_desc := format('%s linha(s) de "%s" ficaram com a conta canônica por HEURÍSTICA (%s: a IA não deu a seção, ela foi inferida do texto da seção ou da árvore do documento) ou SEM conta (%s: sem seção, ou com uma que o catálogo não conhece). '
                     'Linha sem conta é fato sem identidade: não entra em nenhuma seção até alguém dizer qual é. Confirme a seção destas linhas%s: %s%s',
                     v_h + v_s, coalesce(v_nome, '?'), v_h, v_s,
                     case when v_h + v_s > 12 then ' (as 12 primeiras de ' || (v_h + v_s) || ')' else '' end,
                     v_lista, '.');
    if v_pend is not null then
      update pendencia set descricao = v_desc where id = v_pend;
    elsif not exists (select 1 from pendencia where caso_id = v_caso and motivo = v_motivo and coalesce(resolvida_por, '') <> 'sistema:extracao') then
      -- (uma pessoa que já resolveu esta pendência não a vê reaberta pelo reenvio: decisão humana não se desfaz, 0231)
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso, 'extracao', 'conta_canonica_incerta', 'complementar', true, v_desc, v_doc, v_motivo)
        returning id into v_pend;
    end if;
  elsif v_pend is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao' where id = v_pend;
    v_pend := null;
  end if;
  return v_pend;
end $$;
comment on function fn_fato_pendencia_da_versao(uuid) is
  '0243: a pendência conta_canonica_incerta (motivo fato:conta_incerta:<versão>), UMA por documento-versão, listando as linhas de EXTRAÇÃO resolvidas por heurística ou sem conta (as 12 primeiras no texto). Reabre-se sozinha no texto e se resolve sozinha quando não sobra linha incerta; resolvida por pessoa, não é reaberta. Complementar e sobrepujável: não trava o mandato, avisa.';

-- O PONTO ÚNICO da extração nova (chamado por fn_registrar_campos_extraidos, por onde o n8n passa). A extração é a evidência e vale mais que o fato derivado: se a materialização falhar, a extração FICA, o evento diz, e fn_materializar_fatos() repara.
create or replace function fn_materializar_fatos_da_extracao(p_documento_versao_id uuid)
returns jsonb language plpgsql as $$
declare
  v_tipo text; v_r jsonb; v_pend uuid;
begin
  select d.tipo_taxonomia into v_tipo from documento_versao dv join documento d on d.id = dv.documento_id where dv.id = p_documento_versao_id;
  if not fn_tipo_gera_fato(v_tipo) then
    return jsonb_build_object('materializado', false, 'porque', 'tipo do documento não é de demonstração');
  end if;
  begin
    v_r := fn_materializar_fatos(p_documento_versao_id, 'extracao');
    v_pend := fn_fato_pendencia_da_versao(p_documento_versao_id);
    v_r := v_r || jsonb_build_object('materializado', true, 'pendencia_id', v_pend);
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:n8n', 'fatos_materializados', 'documento_versao:' || p_documento_versao_id, v_r);
  exception when others then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:n8n', 'fatos_materializacao_falhou', 'documento_versao:' || p_documento_versao_id,
              jsonb_build_object('sqlstate', sqlstate, 'erro', sqlerrm,
                                 'porque', 'a extração foi gravada; os fatos não. Rode fn_materializar_fatos() para completar (idempotente).'));
    v_r := jsonb_build_object('materializado', false, 'erro', sqlerrm);
  end;
  return v_r;
end $$;
comment on function fn_materializar_fatos_da_extracao(uuid) is
  '0243: fn_materializar_fatos + fn_fato_pendencia_da_versao para a versão recém-extraída, com o evento fatos_materializados (a prova de que RODOU: regra 7). Tipo fora da lista: não faz nada e não grava evento. Falha: o evento fatos_materializacao_falhou, e a extração não é perdida.';

revoke all on function fn_materializar_fatos(uuid, text), fn_fato_pendencia_da_versao(uuid), fn_materializar_fatos_da_extracao(uuid) from public, anon;
grant execute on function fn_materializar_fatos(uuid, text), fn_fato_pendencia_da_versao(uuid), fn_materializar_fatos_da_extracao(uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- O fato segue o documento: corrigir a entidade ou o período do DOCUMENTO (a correção humana de entidade_incorreta/periodo_incorreto, a fusão) leva a identidade dos fatos que a herdaram DELE.
-- Fato cuja identidade veio de uma COLUNA da linha (e não do documento) não se move.
-- -----------------------------------------------------------------------------
create or replace function fn_fato_segue_o_documento()
returns trigger language plpgsql as $$
begin
  if new.entidade_id is distinct from old.entidade_id then
    update fato_financeiro f
       set entidade_id = new.entidade_id,
           entidade_origem = case when new.entidade_id is null then null when f.entidade_coluna is null then 'documento' else 'coluna_total' end
     where f.documento_versao_id in (select v.id from documento_versao v where v.documento_id = new.id)
       and (f.entidade_coluna is null or f.entidade_origem = 'coluna_total');
  end if;
  if new.periodo_id is distinct from old.periodo_id then
    update fato_financeiro f
       set periodo_id = new.periodo_id,
           periodo_origem = case when new.periodo_id is null then null else 'documento' end
     where f.documento_versao_id in (select v.id from documento_versao v where v.documento_id = new.id)
       and (f.periodo_coluna is null or f.periodo_origem = 'documento');
  end if;
  return null;
end $$;
revoke all on function fn_fato_segue_o_documento() from public, anon, authenticated;

drop trigger if exists trg_fato_segue_o_documento on documento;
create trigger trg_fato_segue_o_documento
  after update of entidade_id, periodo_id on documento
  for each row
  when (old.entidade_id is distinct from new.entidade_id or old.periodo_id is distinct from new.periodo_id)
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
  -- 0243: o fato cuja entidade veio de uma COLUNA da linha (o do documento o gatilho de documento já levou).
  update fato_financeiro set entidade_id = p_para_id where entidade_id = p_de_id;

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
      ('fato_financeiro_entidade_ck', 'c', '''coluna_total''::text'),
      ('fato_financeiro_periodo_ck', 'c', '(periodo_origem IS NULL)'),
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
   'Faltam constraints de fato_financeiro (FK única da evidência, conta nula só com sem_conta e motivo, origem coerente com o id): o fato aceita conta inventada, duas linhas por evidência ou identidade que diz uma coisa e mostra outra.',
   'importante', 1106),
  ('fato_financeiro_policy_leitura', '0243', 'policy', 'fato_financeiro.fato_financeiro_read', null, null,
   'Com a RLS ligada e sem a policy o portal lê zero fatos, sem erro.', 'importante', 1107),
  ('fato_financeiro_policy_insert', '0243', 'policy', 'fato_financeiro.fato_financeiro_insert', null, null,
   'Sem ela o authenticated (o reprocesso do portal chama fn_registrar_campos_extraidos como ele) não materializa fato: a falha é engolida e vira evento.', 'importante', 1108),
  ('fato_financeiro_policy_update', '0243', 'policy', 'fato_financeiro.fato_financeiro_update', null, null,
   'Sem ela a fusão de entidade e a correção de entidade/período do documento não repontam o fato (UPDATE de 0 linhas calado) e a fusão cai na FK.', 'importante', 1109),
  ('fato_financeiro_so_secao', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_so_secao', null, 1,
   'Há fato apontando para raiz, grupo ou subgrupo: a identidade desta fatia é a SEÇÃO (decisão do dono, 11/11/2026).', 'importante', 1110),
  ('fato_financeiro_extracao_nova_materializa', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_recentes', null, 1,
   'Linha elegível das 20 versões de demonstração mais novas sem fato: a extração nova não está materializando (função antiga, backfill por aplicar, ou falha engolida: evento fatos_materializacao_falhou).', 'importante', 1111),
  ('fato_financeiro_pendencia_tipo', '0243', 'comportamento', 'instalacao_sonda_fato_financeiro_pendencia_tipo', null, 1,
   'Sem o rótulo conta_canonica_incerta em pendencia_tipo a pendência da heurística não abre.', 'importante', 1112),
  ('registrar_materializa_fatos', '0243', 'corpo', 'fn_registrar_campos_extraidos', 'perform fn_materializar_fatos_da_extracao(p_documento_versao_id);', null,
   'Corpo anterior à 0243 (ou reemitido a partir de um antigo): a extração nova grava a linha e NÃO cria o fato nem abre a pendência da heurística.', 'importante', 1113),
  ('materializa_so_o_elegivel', '0243', 'corpo', 'fn_materializar_fatos', 'fn_linha_vira_fato(x.tipo', null,
   'A materialização precisa perguntar a fn_linha_vira_fato: sem isso virar fato é "tudo que tem valor" (Estoque, Razão, subtotal).', 'importante', 1114),
  ('materializa_idempotente', '0243', 'corpo', 'fn_materializar_fatos', 'on conflict (campo_extraido_id) do nothing', null,
   'Sem o on conflict a segunda chamada (o reenvio, o reparo) morre na FK única ou duplica a evidência.', 'importante', 1115),
  ('materializa_conta_so_pela_secao', '0243', 'corpo', 'fn_materializar_fatos', 'left join conta_canonica c on c.secao_canonica = a.secao', null,
   'A conta do fato é a SEÇÃO da linha, pelo catálogo; sem seção, sem conta. Outro critério (o tipo do documento, a raiz) inventaria a conta.', 'importante', 1116),
  ('materializa_periodo_pela_coluna', '0243', 'corpo', 'fn_materializar_fatos', 'fn_anos_texto(k.pcol)', null,
   'O período do fato é o da COLUNA da linha quando ela nomeia um ano; o do documento no balanço de duas colunas de ano atribui o saldo de 2024 a 2025.', 'importante', 1117),
  ('tipos_que_geram_fato', '0243', 'corpo', 'fn_tipo_gera_fato', '''DVA'', ''DMPL'', ''DF_AUDITADA'')', null,
   'A lista dos tipos de demonstração perdeu um tipo (ou ganhou Razão/Notas): linha de demonstração fica sem fato, ou o que é só evidência vira fato.', 'importante', 1118),
  ('pendencia_uma_por_versao', '0243', 'corpo', 'fn_fato_pendencia_da_versao', '''fato:conta_incerta:''', null,
   'A pendência da heurística é UMA por documento-versão (o motivo carrega a versão). Outro motivo = uma por linha (fila de ruído) ou nenhuma.', 'importante', 1119),
  ('extracao_nova_abre_a_pendencia', '0243', 'corpo', 'fn_materializar_fatos_da_extracao', 'fn_fato_pendencia_da_versao(p_documento_versao_id)', null,
   'A extração nova materializa o fato mas não abre a pendência: heurística sem pendência é o palpite silencioso que a P27 existe para impedir.', 'importante', 1120),
  ('fato_segue_o_documento_gatilho', '0243', 'gatilho', 'documento.trg_fato_segue_o_documento', 'fn_fato_segue_o_documento', null,
   'Sem ele corrigir a entidade ou o período do documento deixa os fatos com a identidade ANTIGA, em silêncio.', 'importante', 1121),
  ('fundir_entidade_leva_os_fatos', '0243', 'corpo', 'fn_fundir_entidade', 'fatos_repontados', null,
   'Corpo anterior à 0243: com a FK de fato_financeiro.entidade_id a fusão falha em `delete from entidade` (e antes dela os fatos apontariam para uma entidade que não existe).', 'importante', 1122)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0243', revisado_em = current_date,
       observacao = 'A 0243 cria fato_financeiro (o fato acima de campo_extraido: conta = seção, entidade e período pela coluna da linha), a materialização, a pendência conta_canonica_incerta (uma por versão, só extração nova), o backfill sem pendência, o gatilho do documento, reemite fn_registrar_campos_extraidos e fn_fundir_entidade, 4 views de sonda e 18 requisitos novos (ordem 1105-1122).'
 where id = true;

commit;
