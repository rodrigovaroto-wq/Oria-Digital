-- =============================================================================
-- 0303 — A FONTE QUE CAÍA E PARECIA NÃO TER NADA: a base comum das fontes externas (Fase A, fatia A2) — catálogo `fonte_externa`,
--        `consulta_externa` (cada tentativa, com o resultado em QUATRO estados) e `fato_externo` (o dado achado, ligado à consulta que o trouxe),
--        mais o ponto único de registro `fn_registrar_consulta_externa`, que é quem CLASSIFICA o desfecho
-- (Cria 3 tabelas, 5 funções de gatilho, 1 função de registro, 7 gatilhos (um deles deferido), 22 linhas de catálogo, 3 views de sonda e 36
--  requisitos. Nenhum backfill: as tabelas nascem vazias, o catálogo é seed. Desenho: Espec. 13 §3 e §6, Espec. 15 §7, FASE_A_FONTES_PUBLICAS.md §5 A2.)
--
-- O DEFEITO QUE ISTO FECHA ANTES DE ELE EXISTIR (regra 7). A Fase A liga ~20 APIs públicas (mercado, pelo n8n; empresa, pelo servidor do portal). Uma API
-- pública muda de endereço sem aviso (já aconteceu com a Receita e com o Comex Stat, 27/10) e cai por horas. Se cada chamador decide sozinho o que um
-- timeout, um 503 ou um corpo vazio significam, o primeiro que escrever `if (!resposta) { achados = [] }` grava "nada encontrado" para uma fonte que
-- NÃO FOI CONSULTADA: "a empresa não tem sanção na CGU" e "a CGU não respondeu" ficam com a mesma linha no banco. O book diria "sem sanções" por causa de
-- um timeout, e nenhuma suíte avisaria, porque o resultado seria um valor legítimo. Hoje (0302) não há tabela de consulta externa alguma: medido por
-- `grep -c "consulta_externa" Supabase/migrations/*.sql` antes desta migration = 0 arquivos.
--
-- A CAUSA É DE DESENHO, NÃO DE UM CHAMADOR: o desfecho cru de uma chamada (status HTTP, erro de rede, corpo) é classificado em quatro estados, e
-- quem classifica é código de cada fonte. A correção é classificar UMA VEZ, no banco, no ponto por onde passam o n8n (A3) e o portal (A4):
--   * `fn_registrar_consulta_externa(fonte, caso, cnpj, http_status, erro, corpo, itens, registros_lidos, custo, nao_consultado)` recebe o desfecho CRU e decide:
--       - motivo de não consultar informado            -> `nao_consultado` (sem status, sem erro, sem itens: não houve chamada);
--       - texto de erro informado                       -> `falhou` (erro de rede, timeout, corpo que não é JSON: o chamador não conseguiu ler);
--       - sem status HTTP (timeout, DNS, conexão)      -> `falhou`;
--       - 2xx com `itens` = []                          -> `nada_encontrado`; 2xx com itens -> `encontrado` (e grava um `fato_externo` por item);
--       - o status que a FONTE documenta como "não existe" (`fonte_externa.http_inexistente`) -> `nada_encontrado`;
--       - QUALQUER OUTRO status (1xx, 3xx, 4xx, 5xx)    -> `falhou`. 2xx sem a lista `itens` é recusado: o chamador não leu a resposta, e "não li" não é "vazio".
--       - PROVA DE LEITURA (achado E do revisor, 24/11): "nada" e "achado" exigem o corpo cru (o hash) e, em fonte de LISTA (CGU CEIS/CNEP, MTE, IBAMA: baixadas
--         inteiras e procuradas pelo CNPJ), `registros_lidos` > 0. 200 com corpo nulo, ou lista vazia/página de manutenção servida com 200, vira `falhou`: um
--         "[]" sem prova de que a lista foi lida é indistinguível de "a CGU não tem sanção para este CNPJ".
--         TETO CONHECIDO: `registros_lidos > 0` só pega a lista VAZIA. Uma lista TRUNCADA que ainda traz registros (download cortado no meio) NÃO é detectada aqui, e o "nada" dela
--         passaria. Um mínimo esperado de registros por fonte (CEIS, CNEP, MTE, IBAMA) é da A4: ela o mede e o põe no catálogo ao conectar cada lista. Até lá, esta migration não promete mais que isso.
--   * O 404 NÃO é tratado como "não existe" por padrão, e esta é a decisão de desenho que importa: um 404 é também o que uma fonte que MUDOU DE
--     ENDEREÇO devolve (o risco que o plano já registrou). `http_inexistente` nasce NULO para as 22 fontes do seed e só é preenchido, por fonte, depois de
--     alguém CONFIRMAR em produção que aquela API devolve esse status para "este CNPJ não consta" e não para "esta rota não existe". Enquanto for nulo,
--     o 404 é `falhou` — o erro vai para o lado seguro (a tela diz "falhou, tente de novo", nunca "sem sanções"). O custo: um CNPJ que a BrasilAPI
--     não conhece aparece como "falhou" até a A4 medir e preencher; é preferível a fabricar um "nada". DECISÃO 7 DO DONO (24/11/2026): o 404 que quer dizer "não existe"
--     é tratado NA A4, fonte por fonte; é o primeiro passo de cada fonte de empresa (FASE_A_FONTES_PUBLICAS.md §5 A4: medir o que ela devolve para um CNPJ que não
--     existe e só então preencher `http_inexistente`). Esta migration NÃO o preenche para nenhuma das 22: 0 de 22 medidas. Em fonte de LISTA o 404 nunca vira "nada"
--     (uma lista não responde "este CNPJ não consta" com 404: um 404 é o arquivo que sumiu).
--
-- AS REGRAS NO BANCO, não na tela (o que o portal e o n8n não conseguem desfazer):
--   1. `falhou` nunca vira `nada_encontrado`: `consulta_externa` é IMUTÁVEL (gatilho BEFORE UPDATE recusa QUALQUER atualização, inclusive do service_role e do
--      superusuário em sessão normal; só um superusuário com session_replication_role = replica passa por cima dos gatilhos (é o que a limpeza do teste usa, de propósito); nova tentativa = nova linha). Não há como corrigir "falhou" para "nada" nem por engano nem por script. E o DELETE também é recusado (achado F do
--      revisor): o service_role tem DELETE, e apagar a linha "falhou" mais nova faz a "nada_encontrado" ANTIGA voltar a ser a mais recente — o mesmo defeito por outra
--      porta. A ÚNICA exceção é a cascata de quem apaga o MANDATO (`caso_id ... on delete cascade`; o gatilho só deixa passar quando o caso já não existe): o dado de
--      cliente sai com o mandato. Consulta de mercado (sem mandato) nunca se apaga.
--   2. `falhou` e `nao_consultado` exigem motivo não vazio (CHECK): ausência sem a causa e o EFEITO não é registrada (regra 1 do CLAUDE.md).
--   3. O resultado concorda com o status HTTP (CHECK): `encontrado` só com 2xx, `nada_encontrado` só com 2xx ou 4xx, `nao_consultado` sem status. Quem
--      gravar direto (service_role) uma "nada_encontrado" com HTTP 503 leva 23514. A concordância com o status que A FONTE documenta fica no gatilho.
--   4. `fato_externo` só existe em consulta `encontrado` (gatilho), e `encontrado` sem nenhum fato é recusado ao fim da transação (gatilho deferido):
--      `nada_encontrado` nunca tem fato, e `encontrado` nunca é vazio. `encontrado` E `nada_encontrado` exigem o hash do bruto (a prova do que a fonte
--      devolveu), e fonte de lista exige `registros_lidos` > 0 (gatilho, que conhece o catálogo).
--   5. Fonte fora do catálogo é recusada (FK + a função, que dá a mensagem). Fonte de EMPRESA exige mandato e CNPJ; fonte de MERCADO não leva nenhum dos dois
--      (a consulta de mercado não carrega dado de cliente: Fase A §4).
--   6. O ALVO É SÓ CNPJ: `alvo_cnpj ~ '^[0-9]{14}$'` (CHECK). CPF (11 dígitos, com ou sem máscara) é recusado DE PROPÓSITO: a decisão do dono de 24/11/2026
--      ("consultar sócios, mas por enquanto só a empresa") contradiz a N-C7b e a regra R5 da Espec. 13 ("nada de pessoa física sem `autorizacao`; a recusa
--      é no banco") e o item 1.B7 do plano. O conflito está NAS PENDÊNCIAS (PENDENCIAS_RISCOS_E_QUESTOES_FUTURAS.md) e a tabela `autorizacao` não existe
--      ainda; abrir CPF aqui antes da decisão registrada e da conversa com o advogado seria mandar dado de pessoa física a terceiros sem base. Quando a
--      decisão sair, é UMA migration que troca este CHECK e exige `autorizacao_id` — não uma exceção no código do chamador.
--      LIMITE CONHECIDO: o CNPJ alfanumérico da Receita (previsto para 2026; confirmar a data) não passa neste CHECK. Sobe quando o primeiro aparecer.
--      A máscara também é recusada (11.222.333/0001-81): quem chama normaliza para 14 dígitos antes.
--   7. Escrita só pela função (SECURITY DEFINER, guarda no corpo): o `authenticated` tem SÓ SELECT nas três tabelas. Empresa: Sócio ou Analista alocado ao
--      mandato (`fn_pode_escrever_caso`) ou conexão de serviço; mercado: Sócio ou conexão de serviço. O `anon` não executa a função.
--      DATA E PRAZO SÃO DO BANCO (achado D, ALTO): a função NÃO recebe mais a data da consulta. Antes, `p_consultada_em` era do chamador e o `authenticated` tinha
--      EXECUTE: um Analista gravava um `nada_encontrado` datado 2099, que virava "a consulta mais recente" e escondia as falhas reais. Agora o gatilho de INSERT
--      sobrescreve `data_consulta` (clock_timestamp()) e calcula `validade_em` a partir do catálogo — vale também para o service_role que grave direto na tabela.
--      EXECUTE do authenticated: MANTIDO, de propósito. O servidor do portal (A4) chama com o JWT da pessoa (todo cliente Supabase do portal é o da sessão; nenhum
--      tem a chave de serviço) e o botão "Atualizar dados públicos" é do Analista do mandato; revogar obrigaria a A4 a carregar a chave de serviço na Vercel, um
--      segredo novo que é decisão do dono. O que se fecha aqui é o que o EXECUTE permitia fabricar SEM o chamador afirmar uma leitura: a data (acima) e o "nada" sem
--      prova (regra 4). RESÍDUO conhecido: quem tem EXECUTE ainda AFIRMA o desfecho cru (um Analista mal-intencionado do mandato poderia enviar um "200 []" com hash
--      inventado); por isso a consulta guarda `registrado_por` (auth.uid(); nulo = conexão de serviço). Se a A4 passar a registrar com a chave de serviço, revogar o
--      EXECUTE do authenticated é UMA linha, e a sonda `externa_so_le` deve ganhar o assert.
--   8. RLS (0216): `consulta_externa` lê pelo mandato (Sócio lê tudo; os demais, onde estão alocados) E, para a consulta de MERCADO (sem mandato), qualquer
--      um da equipe (`fn_tem_papel`); `fato_externo` lê o que a consulta dele deixa ler; o catálogo lê por `fn_tem_papel` (equipe inteira).
--   9. GRANT explícito (0214), precedido de `revoke all` (o padrão da 0302: o default de privilégio do Supabase pode dar ALL a tabela nova; o ACL fica o mesmo com
--      ou sem ele): authenticated SELECT; service_role as quatro operações (a sonda da 0214 o exige; o que o service_role pode escrever de verdade é limitado pelos
--      gatilhos acima, que valem para ele também — inclusive o do DELETE).
--  10. TODA FONTE TEM PRAZO (decisão 8 do dono, 24/11/2026; achado ALTO): `validade_dias` é NOT NULL > 0 e `validade_origem` diz de onde veio ('publicado' pela
--      fonte, 'cadencia', 'minimo_por_desconhecida'). Prazo = até a próxima PUBLICAÇÃO da fonte: o que a fonte publica; senão o da cadência de publicação (diária 1,
--      semanal 7, mensal 30, trimestral 90, semestral 180, anual 365); cadência desconhecida, ou variável por série, = 1 dia (vence cedo: nunca parece nova estando
--      velha). Um CHECK amarra 'cadencia' ao número certo e 'minimo_por_desconhecida' a cadência nula e 1 dia. `consulta_externa.validade_em` é NOT NULL e é
--      calculado pelo gatilho a partir do catálogo, nunca pelo chamador. ATENÇÃO À COLUNA `cadencia`: no rascunho anterior ela misturava "quanto a Oria BUSCA" (o
--      macro roda mensal, dia 12; o CGU "download diário" é a nossa rotina) com "quanto a fonte PUBLICA". O prazo depende da PUBLICAÇÃO, então `cadencia` agora é só
--      a de publicação, e onde o repositório e o plano só dizem a de BUSCA (SGS, Focus, CGU, BrasilAPI, PGFN) ela é nula e o prazo é o mínimo. O MTE ("lista semestral", FASE_A §5 A4)
--      é a fonte que parecia ter cadência de publicação, mas o plano diz a periodicidade da LISTA, não a DATA em que ela é publicada: 180 dias contados da consulta venceriam
--      meses depois de uma lista nova já ter saído (regra 8, "nunca parece nova estando velha"). DECISÃO DO DONO (24/11/2026, revisão): o MTE também fica em 1 dia, origem
--      'minimo_por_desconhecida', cadência nula, até a A4 conhecer a data de publicação. A3 e A4 trocam o mínimo pelo prazo real ao conectar cada fonte.
--  11. FONTE DE LISTA OU DE CONSULTA (achado E): `fonte_externa.forma` diz se a fonte é baixada inteira e procurada pelo CNPJ ('lista': CEIS, CNEP, MTE, IBAMA autos e
--      embargos) ou respondida por consulta ('consulta'). Só a lista tem o "200 vazio que parece ausência" e exige `registros_lidos` > 0. A PGFN fica 'consulta'
--      (decisão 3 do dono); se a A4 só achar o arquivo trimestral, vira 'lista' por UPDATE no catálogo.
--
-- O QUE FICOU DE FORA, e por quê (não inventado — regra 1):
--   * `autorizacao_id` e `caso.momento` (Espec. 13 §3 peças 2 e 3): vêm com a tabela `autorizacao`, que o plano coloca no item 1.B7. Sem pessoa física aqui, não há o que autorizar.
--   * `origem_compartilhada_com` (Espec. 15 §7, dimensão A4 do score): é do score de confiabilidade (1.B), não da base comum.
--   * Cadência de PUBLICAÇÃO e URL: só estão no seed onde o repositório ou o plano DIZEM. O resto é NULO, com o motivo no comentário de cada linha. O prazo (decisão 8)
--     nunca é nulo: onde a cadência é nula ele é o mínimo de 1 dia, com origem 'minimo_por_desconhecida'. Medido no seed: 22 de 22 no mínimo (nenhuma por cadência: a data de publicação do MTE é da A4).
--   * A cadência de BUSCA do macro: o plano (FASE_A §3) diz "agendamento diário", mas o gerador N8N/build-workflow-macro.mjs agenda MENSAL (dia 12, 06h; o IPCA do
--     mês anterior só sai por volta do dia 10). É a cadência de busca, não a de publicação (o SGS tem série diária e mensal): não entra em `cadencia` (ver 10).
--   * `oficial`: verdadeiro para todas, menos a BrasilAPI. Decisão 6 do dono (24/11/2026, ao revisar a A2): ANBIMA, CCEE e FipeZAP são fontes OFICIAIS (o rascunho
--     as marcava false por critério nosso, associação/câmara/índice privados; o dono decidiu o contrário). Só a BrasilAPI fica false (decisão 2: espelho gratuito,
--     "não oficial"). A escala de origem do score (Espec. 15 A1) decide o peso de cada uma; esta coluna só diz o que o dono decidiu sobre o selo "oficial".
--
-- O QUE FICA A APLICAR À MÃO NO SUPABASE: esta migration inteira (nenhum segredo, nenhum dado de cliente). Conferir com a sonda:
--   select chave, presente, detalhe from fn_instalacao_conferir() where migration = '0303' and not presente;   -- ZERO linhas (36 requisitos)
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/a_fonte_que_caia_e_parecia_nao_ter_nada.test.sql. O número de asserts e o de reprovações com cada guarda desligada são
-- medidos por outro passo desta rodada e vão na mensagem do commit; esta migration não declara um número que ainda não foi medido (o cabeçalho não leva placeholder).
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1. O CATÁLOGO
-- -----------------------------------------------------------------------------
create table fonte_externa (
  chave              text primary key check (chave ~ '^[a-z0-9_]+$'),
  nome               text not null check (btrim(nome) <> ''),
  origem             text not null check (btrim(origem) <> ''),
  url                text,
  tipo               text not null check (tipo in ('mercado', 'empresa')),
  oficial            boolean not null,
  forma              text not null check (forma in ('lista', 'consulta')),
  cadencia           text check (cadencia in ('diaria', 'semanal', 'mensal', 'trimestral', 'semestral', 'anual')),
  validade_dias      integer not null check (validade_dias > 0),
  validade_origem    text not null check (validade_origem in ('publicado', 'cadencia', 'minimo_por_desconhecida')),
  fornecedor         text not null check (btrim(fornecedor) <> ''),
  base_legal_tipica  text not null check (base_legal_tipica in ('dado_publico', 'autorizacao_pre_mandato', 'termo_kickoff', 'consentimento_open_finance')),
  http_inexistente   smallint check (http_inexistente between 400 and 499),
  observacao         text,
  criado_em          timestamptz not null default now(),
  -- Decisão 8 do dono (24/11/2026): o prazo nunca é palpite escondido. 'cadencia' só vale com o número que a cadência de PUBLICAÇÃO manda; 'minimo_por_desconhecida' só
  -- vale com cadência nula e 1 dia. 'publicado' é o prazo que a própria fonte publica (qualquer valor > 0). O `coalesce` evita o NULL que faria o CHECK passar.
  constraint fonte_externa_validade_coerente check (
    case validade_origem
      when 'cadencia' then coalesce(validade_dias = case cadencia when 'diaria' then 1 when 'semanal' then 7 when 'mensal' then 30
                                                                  when 'trimestral' then 90 when 'semestral' then 180 when 'anual' then 365 end, false)
      when 'minimo_por_desconhecida' then cadencia is null and validade_dias = 1
      else true
    end)
);
comment on table fonte_externa is
  '0303: o catálogo das fontes externas (Espec. 13 §3, Espec. 15 §7). Toda consulta aponta para uma linha daqui (FK): fonte fora do catálogo é recusada pelo banco. `tipo` diz onde roda e se carrega dado de cliente: mercado (agendado, n8n, sem CNPJ) ou empresa (sob demanda, servidor do portal, por CNPJ).';
comment on column fonte_externa.oficial is 'O selo "oficial" decidido pelo dono. Falso só para o espelho gratuito (BrasilAPI, decisão 2 de 24/11/2026); ANBIMA, CCEE e FipeZAP são oficiais (decisão 6, 24/11/2026). Não é o peso da fonte no score (Espec. 15 A1).';
comment on column fonte_externa.forma is 'lista = a fonte é baixada INTEIRA e procurada pelo CNPJ (CGU CEIS/CNEP, MTE, IBAMA): um 200 vazio pode ser lista vazia ou página de manutenção, então "nada" exige registros_lidos > 0 e 404 nunca vira "não existe" (teto: lista truncada que ainda traz registros não é detectada; o mínimo esperado por fonte é da A4). consulta = a fonte responde por alvo.';
comment on column fonte_externa.cadencia is 'Cadência de PUBLICAÇÃO da fonte (quanto ELA publica, não quanto a Oria busca: o macro roda mensal e a CGU é baixada diária por NÓS, e isso não entra aqui). NULA = o plano e o repositório não dizem, ou varia por série (SGS tem série diária e mensal); ausência, não zero (regra 1).';
comment on column fonte_externa.validade_dias is 'Prazo de vencimento de uma consulta, em dias: até a PRÓXIMA PUBLICAÇÃO da fonte (decisão 8 do dono, 24/11/2026). Nunca nulo. Cadência desconhecida = 1 dia (vence cedo; nunca parece nova estando velha). A3 e A4 trocam o mínimo pelo real ao conectar cada fonte.';
comment on column fonte_externa.validade_origem is 'De onde veio o prazo: publicado (a fonte o publica), cadencia (derivado da cadência de PUBLICAÇÃO: diária 1, semanal 7, mensal 30, trimestral 90, semestral 180, anual 365; o CHECK confere o número) ou minimo_por_desconhecida (cadência desconhecida ou variável: 1 dia).';
comment on constraint fonte_externa_validade_coerente on fonte_externa is '0303: o prazo concorda com a origem declarada: cadencia => o número da cadência de publicação; minimo_por_desconhecida => cadência nula e 1 dia.';
comment on column fonte_externa.http_inexistente is 'O status 4xx que ESTA fonte documenta e devolve para "este alvo não consta" (e não para "rota inexistente"). NULO = nenhum: todo status que não seja 2xx é falha. Só se preenche depois de MEDIR a API (decisão 7 do dono, 24/11/2026: na A4, fonte por fonte; FASE_A §5 A4) — um 404 também é o que uma fonte que mudou de endereço devolve. Nulo nas 22 do seed: nenhuma foi medida.';

alter table fonte_externa enable row level security;
create policy fonte_externa_read on fonte_externa for select to authenticated using ((select fn_tem_papel()));
revoke all on fonte_externa from public, anon, authenticated, service_role;   -- padrão da 0302: o ACL não depende do default de privilégio do Supabase
grant select on fonte_externa to authenticated;
grant select, insert, update, delete on fonte_externa to service_role;

-- -----------------------------------------------------------------------------
-- 2. A CONSULTA (append-only) E O FATO
-- -----------------------------------------------------------------------------
create table consulta_externa (
  id              uuid primary key default gen_random_uuid(),
  fonte           text not null references fonte_externa(chave),
  caso_id         uuid references caso(id) on delete cascade,
  alvo_cnpj       text,
  data_consulta   timestamptz not null default clock_timestamp(),   -- o gatilho a sobrescreve com clock_timestamp(): a data é do banco, nunca de quem chama
  validade_em     timestamptz not null,                  -- calculada pelo gatilho: data_consulta + o prazo do catálogo
  custo           numeric(12, 4) not null,                -- sem default: custo desconhecido não vira zero medido; quem registra diz (0 nas fontes gratuitas)
  registros_lidos integer,
  registrado_por  uuid,
  fornecedor      text not null check (btrim(fornecedor) <> ''),
  base_legal      text not null check (base_legal in ('dado_publico', 'autorizacao_pre_mandato', 'termo_kickoff', 'consentimento_open_finance')),
  http_status     smallint,
  hash_bruto      text,
  motivo          text,
  resultado       text not null,
  constraint consulta_externa_resultado_valido check (resultado in ('encontrado', 'nada_encontrado', 'falhou', 'nao_consultado')),
  constraint consulta_externa_alvo_so_cnpj check (alvo_cnpj is null or alvo_cnpj ~ '^[0-9]{14}$'),
  constraint consulta_externa_motivo_obrigatorio check (resultado not in ('falhou', 'nao_consultado') or length(btrim(coalesce(motivo, ''))) > 0),
  constraint consulta_externa_status_coerente check (
       (resultado = 'nao_consultado' and http_status is null)
    or (resultado = 'encontrado' and coalesce(http_status between 200 and 299, false))
    or (resultado = 'nada_encontrado' and coalesce(http_status between 200 and 299 or http_status between 400 and 499, false))
    or  resultado = 'falhou'),  -- coalesce: sem ele, status NULO dá NULL e o CHECK PASSA (nada_encontrado sem status foi aceito até o teste reprovar)
  -- Prova de leitura: encontrado e nada_encontrado exigem o hash, e NÃO o da string vazia (corpo vazio não prova leitura: ver a função); nao_consultado não tem corpo, logo não tem hash.
  constraint consulta_externa_prova_de_leitura check (
       (resultado not in ('encontrado', 'nada_encontrado') or (hash_bruto is not null and hash_bruto <> 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'))
   and (resultado <> 'nao_consultado' or hash_bruto is null)),
  constraint consulta_externa_registros_validos check (registros_lidos is null or registros_lidos >= 0),
  constraint consulta_externa_hash_formato check (hash_bruto is null or hash_bruto ~ '^[0-9a-f]{64}$'),
  constraint consulta_externa_custo_nao_negativo check (custo >= 0),
  constraint consulta_externa_validade_depois check (validade_em >= data_consulta)
);
comment on table consulta_externa is
  '0303: cada TENTATIVA de consulta a uma fonte externa, com o resultado em quatro estados (encontrado, nada_encontrado, falhou, nao_consultado). IMUTÁVEL e sem DELETE (só a cascata do mandato apaga): nova tentativa = nova linha (falhou nunca vira nada_encontrado, e uma falha não some para a nada antiga voltar a ser a mais recente). Escrita só por fn_registrar_consulta_externa; data e validade são do banco. Alvo SÓ CNPJ (CPF é recusado de propósito: conflito N-C7b/R5 com a decisão de 24/11/2026, nas pendências). caso_id nulo = fonte de mercado.';
comment on constraint consulta_externa_alvo_so_cnpj on consulta_externa is
  '0303: 14 dígitos, sem máscara. CPF (11 dígitos) é recusado de propósito até a decisão do dono sobre pessoa física (N-C7b/R5 da Espec. 13; pendências).';
comment on constraint consulta_externa_motivo_obrigatorio on consulta_externa is '0303: falhou e nao_consultado dizem a causa; ausência sem causa nem efeito não se registra (regra 1).';
comment on constraint consulta_externa_prova_de_leitura on consulta_externa is '0303: tanto "encontrado" quanto "nada_encontrado" exigem o hash do corpo cru, e não o hash da string vazia (corpo vazio não prova leitura): sem a prova de que a resposta foi lida, um "[]" é indistinguível de uma fonte que não respondeu. nao_consultado não tem hash (não houve corpo).';
comment on constraint consulta_externa_status_coerente on consulta_externa is '0303: o resultado concorda com o status HTTP: encontrado só com 2xx; nada_encontrado só com 2xx ou 4xx (o 4xx documentado pela fonte, conferido no gatilho); nao_consultado sem status; falhou com qualquer um.';
comment on column consulta_externa.hash_bruto is 'sha256 do corpo cru devolvido pela fonte (texto exato, UTF-8). Obrigatório em `encontrado` e em `nada_encontrado`: é a prova do que a fonte disse. Nulo em nao_consultado (obrigatoriamente: não houve corpo) e em falhou sem corpo; em encontrado e nada_encontrado nunca é o da string vazia.';
comment on column consulta_externa.custo is 'Preço da consulta (Espec. 13 R6), SEM default: quem registra diz o custo (0 nas fontes gratuitas da Fase A). Custo desconhecido não é zero medido; existe para o custo por caso ser medido, não estimado.';
comment on column consulta_externa.registros_lidos is 'Quantos registros o chamador LEU da fonte. Obrigatório (> 0) em fonte de lista (fonte_externa.forma) para "encontrado" e "nada_encontrado": lista vazia ou página de manutenção servida com 200 é falhou (lista truncada com registros não é detectada: o mínimo esperado por fonte é da A4). Opcional nas fontes de consulta.';
comment on column consulta_externa.registrado_por is 'auth.uid() de quem registrou pela função; nulo = conexão de serviço (n8n, script). A função é executável pelo authenticated (o portal chama com o JWT da pessoa), então a autoria fica gravada.';
comment on column consulta_externa.validade_em is 'Quando a consulta vence: data_consulta + fonte_externa.validade_dias, calculado pelo gatilho de INSERT a partir do catálogo, nunca pelo chamador. Nunca nulo (decisão 8 do dono, 24/11/2026: toda fonte tem prazo).';
comment on column consulta_externa.data_consulta is 'Sempre clock_timestamp() do banco (o gatilho de INSERT sobrescreve qualquer valor; clock_timestamp e não now(), para duas consultas da mesma transação não empatarem): quem chama não escolhe a data, senão um nada_encontrado datado no futuro viraria a consulta "mais recente" e esconderia as falhas reais.';
comment on column consulta_externa.motivo is 'falhou: o erro (HTTP, timeout…). nao_consultado: por que não se consultou e o que isso deixa desconhecido. Livre nos outros dois.';

create index consulta_externa_fonte on consulta_externa (fonte, data_consulta desc);
create index consulta_externa_caso on consulta_externa (caso_id, alvo_cnpj) where caso_id is not null;

create table fato_externo (
  id           uuid primary key default gen_random_uuid(),
  consulta_id  uuid not null references consulta_externa(id) on delete cascade,
  chave        text not null check (btrim(chave) <> ''),
  valor        jsonb not null check (jsonb_typeof(valor) <> 'null'),
  referencia   text,
  criado_em    timestamptz not null default now()
);
comment on table fato_externo is
  '0303: o dado achado por uma consulta, ligado a ela (FK). Só existe em consulta `encontrado` (gatilho); imutável. `valor` nunca é JSON null: ausência de dado é a consulta nada_encontrado, não um fato vazio.';
comment on column fato_externo.referencia is 'Onde, no bruto, está o dado (campo, linha, link). Nulo se a fonte não o dá.';
create index fato_externo_consulta on fato_externo (consulta_id);

alter table consulta_externa enable row level security;
alter table fato_externo enable row level security;
revoke all on consulta_externa, fato_externo from public, anon, authenticated, service_role;   -- padrão da 0302 (ver fonte_externa)
-- Mandato por conjunto (0216). A consulta de mercado (caso_id nulo) é da equipe inteira; a de empresa, do mandato.
create policy consulta_externa_read on consulta_externa for select to authenticated
  using ((select fn_eh_socio())
         or (caso_id is null and (select fn_tem_papel()))
         or caso_id in (select c from fn_casos_legiveis() c));
create policy fato_externo_read on fato_externo for select to authenticated
  using (consulta_id in (select id from consulta_externa));
-- Sem policy (nem grant) de insert/update/delete para authenticated: a escrita é a função.

grant select on consulta_externa, fato_externo to authenticated;
grant select, insert, update, delete on consulta_externa, fato_externo to service_role;

-- -----------------------------------------------------------------------------
-- 3. OS GATILHOS
-- -----------------------------------------------------------------------------
create function fn_trg_consulta_externa_valida() returns trigger
language plpgsql set search_path = public, pg_temp as $$
declare f fonte_externa;
begin
  select * into f from fonte_externa where chave = new.fonte;
  if not found then
    raise exception 'A fonte "%" não está no catálogo (fonte_externa): consulta de fonte fora do catálogo é recusada', new.fonte using errcode = '23503';
  end if;
  if f.tipo = 'empresa' then
    if new.caso_id is null or new.alvo_cnpj is null then
      raise exception 'A fonte "%" é de EMPRESA: a consulta exige o mandato e o CNPJ', new.fonte using errcode = '23514';
    end if;
  elsif new.caso_id is not null or new.alvo_cnpj is not null then
    raise exception 'A fonte "%" é de MERCADO: a consulta não leva mandato nem CNPJ (não carrega dado de cliente)', new.fonte using errcode = '23514';
  end if;
  if new.resultado = 'nada_encontrado' and not (new.http_status between 200 and 299) and new.http_status is distinct from f.http_inexistente then
    raise exception 'nada_encontrado com HTTP % que a fonte "%" não documenta como "não existe": é falha, não ausência', new.http_status, new.fonte using errcode = '23514';
  end if;
  -- FONTE DE LISTA (achado E): um 200 vazio pode ser lista vazia ou página de manutenção (uma lista truncada com registros não é detectada aqui: teto conhecido, o mínimo por fonte é da A4). "Achado" e "nada" só valem com registros lidos > 0, e um 4xx de lista é o
  -- arquivo que sumiu, nunca "este CNPJ não consta" (por isso o 4xx "documentado" de http_inexistente não vale para lista).
  if f.forma = 'lista' and new.resultado in ('encontrado', 'nada_encontrado') then
    if coalesce(new.registros_lidos, 0) <= 0 then
      raise exception 'A fonte "%" é uma LISTA: % exige registros_lidos > 0 (lista vazia ou página de manutenção com 200 é falha, não ausência)', new.fonte, new.resultado using errcode = '23514';
    end if;
    if new.resultado = 'nada_encontrado' and not (new.http_status between 200 and 299) then
      raise exception 'A fonte "%" é uma LISTA: um 4xx é o arquivo que sumiu, não "este CNPJ não consta"', new.fonte using errcode = '23514';
    end if;
  end if;
  -- DATA E PRAZO SÃO DO BANCO (achado D e decisão 8): o chamador (que pode ser um Analista com EXECUTE na função, ou o service_role gravando direto) não escolhe a data
  -- (um "nada_encontrado" datado 2099 viraria a consulta mais recente e esconderia as falhas reais) nem o vencimento (vem do catálogo; validade_dias é NOT NULL).
  -- clock_timestamp() e não now(): now() é o início da TRANSAÇÃO, e duas consultas da mesma transação ficariam com a mesma data, deixando "a mais recente" indefinida (o n8n registra várias fontes numa transação).
  new.data_consulta := clock_timestamp();
  new.validade_em := new.data_consulta + make_interval(days => f.validade_dias);
  new.registrado_por := auth.uid();
  return new;
end $$;
comment on function fn_trg_consulta_externa_valida() is
  '0303: a consulta aponta para fonte do catálogo, e o tipo da fonte decide o que ela leva (empresa: mandato e CNPJ; mercado: nenhum dos dois); nada_encontrado com status 4xx só vale se for o status que a fonte documenta como "não existe" (fonte_externa.http_inexistente), e nunca em fonte de lista; fonte de lista exige registros_lidos > 0 em encontrado e nada_encontrado. Sobrescreve data_consulta (clock_timestamp()), validade_em (catálogo) e registrado_por (auth.uid()): nada disso é do chamador.';

create function fn_trg_externo_imutavel() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  raise exception '% é imutável: uma nova tentativa é uma nova linha (falhou nunca vira nada_encontrado)', tg_table_name using errcode = 'restrict_violation';
end $$;
comment on function fn_trg_externo_imutavel() is '0303: recusa todo UPDATE em consulta_externa e fato_externo, inclusive do service_role e do superusuário em sessão normal (session_replication_role = replica, só de superusuário, passa por cima: é o que a limpeza do teste usa). A correção de "falhou" é outra consulta, não uma atualização.';

-- SEM DELETE (achado F). A imutabilidade só cobria UPDATE e o service_role tem DELETE: apagar a linha "falhou" mais nova faz a "nada_encontrado" ANTIGA voltar a ser a mais
-- recente ("falhou some, nada antigo volta"). A única saída legítima é a CASCATA de quem apaga o mandato (`caso_id ... on delete cascade`, e o fato cascateia da consulta): ela
-- só passa quando o pai já não existe (na cascata o pai foi apagado no mesmo comando, e o gatilho o vê apagado). Um DELETE direto, com o mandato vivo, é recusado.
create function fn_trg_externo_sem_delete() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_table_name = 'consulta_externa' then
    if old.caso_id is not null and not exists (select 1 from caso where id = old.caso_id) then return old; end if;
  elsif not exists (select 1 from consulta_externa where id = old.consulta_id) then
    return old;
  end if;
  raise exception '% não se apaga: uma falha que some deixa a consulta antiga voltar a ser a mais recente (só a cascata do mandato apaga)', tg_table_name using errcode = 'restrict_violation';
end $$;
comment on function fn_trg_externo_sem_delete() is '0303: recusa todo DELETE em consulta_externa e fato_externo, inclusive do service_role, exceto a cascata de quem apaga o mandato (o caso já não existe) ou a consulta (no fato). Consulta de mercado nunca se apaga.';

create function fn_trg_fato_externo_valida() returns trigger
language plpgsql set search_path = public, pg_temp as $$
declare v_res text;
begin
  select resultado into v_res from consulta_externa where id = new.consulta_id;
  if v_res is not null and v_res <> 'encontrado' then
    raise exception 'fato_externo só existe em consulta "encontrado" (esta é "%"): ausência não carrega dado', v_res using errcode = '23514';
  end if;
  return new;
end $$;
comment on function fn_trg_fato_externo_valida() is '0303: nada_encontrado, falhou e nao_consultado nunca têm fato. Consulta inexistente cai na FK.';

create function fn_trg_consulta_externa_com_fato() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  -- a consulta pode já ter sido apagada (a cascata do mandato leva consulta e fato) antes de o gatilho deferido rodar: aí não há o que conferir
  if new.resultado = 'encontrado' and exists (select 1 from consulta_externa where id = new.id)
     and not exists (select 1 from fato_externo where consulta_id = new.id) then
    raise exception 'consulta "encontrado" sem nenhum fato_externo: sem dado, o resultado é nada_encontrado' using errcode = '23514';
  end if;
  return null;
end $$;
comment on function fn_trg_consulta_externa_com_fato() is '0303: gatilho DEFERIDO (fim da transação): "encontrado" sem fato seria a ausência apresentada como dado.';

create trigger trg_consulta_externa_valida before insert on consulta_externa
  for each row execute function fn_trg_consulta_externa_valida();
create trigger trg_consulta_externa_imutavel before update on consulta_externa
  for each row execute function fn_trg_externo_imutavel();
create trigger trg_consulta_externa_sem_delete before delete on consulta_externa
  for each row execute function fn_trg_externo_sem_delete();
create constraint trigger trg_consulta_externa_com_fato after insert on consulta_externa
  deferrable initially deferred for each row execute function fn_trg_consulta_externa_com_fato();
create trigger trg_fato_externo_valida before insert on fato_externo
  for each row execute function fn_trg_fato_externo_valida();
create trigger trg_fato_externo_imutavel before update on fato_externo
  for each row execute function fn_trg_externo_imutavel();
create trigger trg_fato_externo_sem_delete before delete on fato_externo
  for each row execute function fn_trg_externo_sem_delete();

revoke all on function fn_trg_consulta_externa_valida(), fn_trg_externo_imutavel(), fn_trg_externo_sem_delete(), fn_trg_fato_externo_valida(), fn_trg_consulta_externa_com_fato() from public, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 4. O PONTO ÚNICO DE REGISTRO — quem CLASSIFICA
-- -----------------------------------------------------------------------------
-- Chamadores previstos (nenhum existe ainda): o n8n das fontes de mercado (A3) e o servidor do portal para as de empresa (A4). Nenhum deles classifica;
-- todos entregam o desfecho cru. `p_itens` é a lista JÁ LIDA da resposta (um objeto {chave, valor, referencia?} por dado): o chamador sabe o formato
-- da fonte, a função decide o que a lista vazia e a lista cheia significam. O hash é do `p_corpo` em texto exato (UTF-8), não do jsonb normalizado.
-- `p_corpo` é o texto cru lido; null E vazio (ou só espaço) são "não li" (um 200 vazio de proxy em manutenção não é leitura). `p_registros_lidos` é quantos registros o chamador varreu (obrigatório > 0 para fonte de lista).
-- `p_custo` NÃO tem default (achado I): custo desconhecido não vira zero medido; quem chama diz 0 nas fontes gratuitas. Não há `p_consultada_em` (achado D): a data é clock_timestamp() do banco.
create function fn_registrar_consulta_externa(
  p_fonte           text,
  p_caso            uuid,
  p_alvo_cnpj       text,
  p_http_status     integer,
  p_erro            text,
  p_corpo           text,
  p_itens           jsonb,
  p_registros_lidos integer,
  p_custo           numeric,
  p_nao_consultado  text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  f         fonte_externa;
  v_res     text;
  v_motivo  text;
  v_hash    text;
  v_id      uuid := gen_random_uuid();
  v_n       int := 0;
begin
  select * into f from fonte_externa where chave = p_fonte;
  if not found then
    raise exception 'A fonte "%" não está no catálogo (fonte_externa): consulta de fonte fora do catálogo é recusada', p_fonte using errcode = '23503';
  end if;

  -- A guarda: empresa = quem escreve o mandato (ou a conexão de serviço); mercado = Sócio (ou a conexão de serviço). Antes de qualquer outra coisa.
  if f.tipo = 'empresa' then
    if p_caso is null or not (fn_conexao_de_servico() or fn_pode_escrever_caso(p_caso)) then
      raise exception 'Registrar consulta da fonte "%" exige ser Sócio ou Analista alocado ao mandato (ou a conexão de serviço)', p_fonte using errcode = '42501';
    end if;
    if not exists (select 1 from caso where id = p_caso) then
      raise exception 'O mandato % não existe', p_caso using errcode = 'P0002';
    end if;
  elsif not (fn_conexao_de_servico() or fn_eh_socio()) then
    raise exception 'Registrar consulta da fonte de mercado "%" é reservado a Sócio ou à conexão de serviço', p_fonte using errcode = '42501';
  end if;

  if p_custo is null or p_custo < 0 then
    raise exception 'p_custo é obrigatório e não negativo (0 nas fontes gratuitas): custo desconhecido não é zero medido' using errcode = '22023';
  end if;
  if p_registros_lidos is not null and p_registros_lidos < 0 then
    raise exception 'p_registros_lidos não pode ser negativo' using errcode = '22023';
  end if;

  -- A CLASSIFICAÇÃO. Uma ordem só, e `falhou` é o lado seguro de tudo o que não é provadamente outra coisa.
  if p_nao_consultado is not null then
    if length(btrim(p_nao_consultado)) = 0 then
      raise exception 'nao_consultado exige o motivo (e o efeito: o que fica desconhecido)' using errcode = '22023';
    end if;
    if p_http_status is not null or nullif(btrim(coalesce(p_erro, '')), '') is not null or p_itens is not null or p_registros_lidos is not null or p_corpo is not null then
      -- p_corpo também: não houve chamada, e um hash gravado em nao_consultado seria uma prova de leitura que nunca aconteceu.
      raise exception 'nao_consultado contradiz uma resposta: não houve chamada, então não há status, erro, itens, corpo nem registros lidos' using errcode = '22023';
    end if;
    v_res := 'nao_consultado';
    v_motivo := p_nao_consultado;
  elsif nullif(btrim(coalesce(p_erro, '')), '') is not null then
    v_res := 'falhou';
    v_motivo := case when p_http_status is null then p_erro else format('HTTP %s: %s', p_http_status, p_erro) end;
  elsif p_http_status is null then
    v_res := 'falhou';
    v_motivo := 'sem resposta HTTP (timeout, DNS ou conexão) e sem texto de erro';
  elsif p_http_status between 200 and 299 then
    if p_itens is null or jsonb_typeof(p_itens) <> 'array' then
      raise exception 'HTTP % sem a lista de itens lida da resposta (p_itens deve ser um array, possivelmente vazio): "não li" não é "vazio"', p_http_status using errcode = '22023';
    end if;
    if exists (select 1 from jsonb_array_elements(p_itens) e
                where jsonb_typeof(e) <> 'object' or length(btrim(coalesce(e ->> 'chave', ''))) = 0
                   or e -> 'valor' is null or jsonb_typeof(e -> 'valor') = 'null') then
      raise exception 'Cada item precisa ser {"chave": texto, "valor": não nulo}: dado sem chave ou sem valor não é fato' using errcode = '22023';
    end if;
    -- PROVA DE LEITURA (achado E): "nada" e "achado" só com o corpo cru lido e, em fonte de lista, com registros varridos. Sem isto é falha (lado seguro), com o motivo.
    -- CORPO VAZIO NÃO É LEITURA (achado 1 do 2º ciclo): '' tem hash (sha256 da string vazia) e passaria como prova. PGFN/BrasilAPI atrás de proxy devolvem 200 vazio em manutenção e o
    -- chamador faz JSON.parse(body || '[]'): chegaria aqui como "200, []" e gravaria "nada". Corpo nulo, vazio ou só espaço/quebra de linha (btrim padrão só tira espaço: por isso a lista de caracteres) = "não li" = falhou.
    if p_corpo is null or btrim(p_corpo, E' \t\r\n') = '' then
      v_res := 'falhou';
      v_motivo := format('HTTP %s sem o corpo cru (p_corpo %s): sem prova de leitura não se grava "nada" nem "achado"', p_http_status, case when p_corpo is null then 'nulo' else 'vazio' end);
    elsif f.forma = 'lista' and coalesce(p_registros_lidos, 0) <= 0 then
      v_res := 'falhou';
      v_motivo := format('HTTP %s mas %s registros lidos da lista: lista vazia ou página de manutenção não é "nada"', p_http_status, coalesce(p_registros_lidos::text, 'nenhum informado de'));
    else
      v_res := case when jsonb_array_length(p_itens) = 0 then 'nada_encontrado' else 'encontrado' end;
    end if;
  elsif p_http_status = f.http_inexistente and f.forma = 'consulta' then
    if p_itens is not null and jsonb_typeof(p_itens) = 'array' and jsonb_array_length(p_itens) > 0 then
      raise exception 'HTTP % ("não existe" para esta fonte) vindo com itens: resposta contraditória', p_http_status using errcode = '22023';
    end if;
    if p_corpo is null or btrim(p_corpo, E' \t\r\n') = '' then
      v_res := 'falhou';
      v_motivo := format('HTTP %s sem o corpo cru (p_corpo %s): sem prova de leitura não se grava "nada"', p_http_status, case when p_corpo is null then 'nulo' else 'vazio' end);
    else
      v_res := 'nada_encontrado';
      v_motivo := format('HTTP %s: a fonte documenta este status como "alvo não consta"', p_http_status);
    end if;
  else
    v_res := 'falhou';
    v_motivo := format('HTTP %s', p_http_status);
  end if;

  if p_corpo is not null then
    v_hash := encode(sha256(convert_to(p_corpo, 'UTF8')), 'hex');
  end if;

  -- data_consulta, validade_em e registrado_por são preenchidos pelo gatilho (a data é do banco; o vencimento, do catálogo).
  insert into consulta_externa (id, fonte, caso_id, alvo_cnpj, custo, fornecedor, base_legal, http_status, hash_bruto, registros_lidos, motivo, resultado)
  values (v_id, f.chave, p_caso, p_alvo_cnpj, p_custo, f.fornecedor, f.base_legal_tipica, p_http_status, v_hash, p_registros_lidos, v_motivo, v_res);

  if v_res = 'encontrado' then
    insert into fato_externo (consulta_id, chave, valor, referencia)
    select v_id, e ->> 'chave', e -> 'valor', e ->> 'referencia' from jsonb_array_elements(p_itens) e;
    get diagnostics v_n = row_count;
  end if;

  return jsonb_build_object('id', v_id, 'resultado', v_res, 'motivo', v_motivo, 'fatos', v_n);
end $$;
comment on function fn_registrar_consulta_externa(text, uuid, text, integer, text, text, jsonb, integer, numeric, text) is
  '0303: o ÚNICO ponto de escrita de consulta_externa e fato_externo (o authenticated não tem grant de escrita). Recebe o desfecho CRU da chamada e classifica: motivo de não consultar -> nao_consultado; erro informado ou sem status HTTP (timeout, rede) -> falhou; 2xx com itens [] -> nada_encontrado, com itens -> encontrado + um fato por item, MAS só com o corpo cru lido (p_corpo) e, em fonte de lista, com p_registros_lidos > 0 (senão falhou); o 4xx que a fonte de consulta documenta como "não existe" (fonte_externa.http_inexistente, nulo por padrão) -> nada_encontrado; qualquer outro status -> falhou. 2xx sem a lista de itens é recusado (22023), como custo nulo ou negativo. A data é clock_timestamp() do banco e o vencimento vem do catálogo: o chamador não escolhe. Fonte fora do catálogo: 23503. Sem permissão: 42501 (empresa: Sócio ou Analista do mandato; mercado: Sócio). Devolve {id, resultado, motivo, fatos}.';
revoke all on function fn_registrar_consulta_externa(text, uuid, text, integer, text, text, jsonb, integer, numeric, text) from public, anon;
grant execute on function fn_registrar_consulta_externa(text, uuid, text, integer, text, text, jsonb, integer, numeric, text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 5. O SEED DO CATÁLOGO — as fontes da A3 (mercado) e da A4 (empresa). NULO = o plano e o repositório não dizem (regra 1).
-- -----------------------------------------------------------------------------
-- URL: só onde o repositório já a usa (N8N/lib/macro.mjs) ou onde o plano a nomeia; o resto a A3/A4 preenchem ao conectar a fonte, depois de conferir o endereço.
-- cadencia = a de PUBLICAÇÃO da fonte (decisão 8 do dono; ver cabeçalho, item 10). O repositório e o plano só dizem a de BUSCA para bcb_sgs e bcb_focus (macro mensal, dia 12),
-- cgu_* ("download diário": é a NOSSA rotina), brasilapi e pgfn ("por consulta"): nelas a cadência é NULA e o prazo é o mínimo de 1 dia. O MTE diz só a periodicidade da lista ("lista semestral", FASE_A §5 A4), não a data de publicação: 1 dia, como as outras 21 (decisão do dono, 24/11/2026). A3 e A4 trocam o mínimo pelo real ao conectar cada fonte.
-- forma: 'lista' = baixada inteira e procurada pelo CNPJ (cgu_ceis, cgu_cnep, mte_trabalho_escravo, ibama_autos, ibama_embargos); o resto é por consulta.
-- http_inexistente: nulo em todas (decisão 7 do dono: a A4 mede o 404 de cada fonte de empresa e o preenche; ver cabeçalho).
insert into fonte_externa (chave, nome, origem, url, tipo, oficial, forma, cadencia, validade_dias, validade_origem, fornecedor, base_legal_tipica, observacao) values
  ('bcb_sgs',           'BCB — Séries temporais (SGS)',                    'Banco Central do Brasil', 'https://api.bcb.gov.br/dados/serie/bcdata.sgs', 'mercado', true, 'consulta', null, 1, 'minimo_por_desconhecida', 'Banco Central do Brasil', 'dado_publico', 'Já existe no macro (0025, N8N/lib/macro.mjs). O gerador BUSCA mensal (dia 12), mas o SGS tem série diária e mensal: a cadência de publicação varia por série, então nula e prazo mínimo.'),
  ('bcb_focus',         'BCB — Expectativas de mercado (Focus)',            'Banco Central do Brasil', 'https://olinda.bcb.gov.br/olinda/servico/Expectativas/versao/v1/odata/ExpectativasMercadoAnuais', 'mercado', true, 'consulta', null, 1, 'minimo_por_desconhecida', 'Banco Central do Brasil', 'dado_publico', 'Já existe no macro. A busca é mensal (mesmo workflow do SGS); a cadência de publicação do Focus o repositório não diz: nula e prazo mínimo.'),
  ('bcb_juros_modalidade','BCB — Taxas de juros por modalidade (Olinda)',    'Banco Central do Brasil', null, 'mercado', true, 'consulta', null, 1, 'minimo_por_desconhecida', 'Banco Central do Brasil', 'dado_publico', 'A3, ordem 2. URL e cadência: a A3 define ao conectar.'),
  ('ibge_sidra',        'IBGE — SIDRA',                                    'IBGE', 'https://apisidra.ibge.gov.br/values', 'mercado', true, 'consulta', null, 1, 'minimo_por_desconhecida', 'IBGE', 'dado_publico', 'A3, ordem 4. A base da URL é a do macro (IPCA); cadência por tabela: a A3 define.'),
  ('cvm_dados_abertos', 'CVM — Dados abertos (cadastro e demonstrações)',  'Comissão de Valores Mobiliários', null, 'mercado', true, 'consulta', null, 1, 'minimo_por_desconhecida', 'CVM', 'dado_publico', 'A3, ordem 5. Medir o tamanho do banco antes da carga (plano gratuito, 500 MB).'),
  ('anbima_curva',      'ANBIMA — Curva de juros',                         'ANBIMA', null, 'mercado', true, 'consulta', null, 1, 'minimo_por_desconhecida', 'ANBIMA', 'dado_publico', 'A3, ordem 6. Oficial por decisão 6 do dono (24/11/2026).'),
  ('ipeadata',          'IPEADATA — Séries (risco-país e outras)',         'IPEA', null, 'mercado', true, 'consulta', null, 1, 'minimo_por_desconhecida', 'IPEA', 'dado_publico', 'A3, ordem 7.'),
  ('comex_stat',        'Comex Stat — Exportação e importação por produto','MDIC', null, 'mercado', true, 'consulta', null, 1, 'minimo_por_desconhecida', 'MDIC', 'dado_publico', 'A3, ordem 7. Já mudou de endereço sem aviso (27/10/2026): razão de ser do estado falhou.'),
  ('caged',             'CAGED — Emprego por setor',                       'Ministério do Trabalho e Emprego (PDET)', null, 'mercado', true, 'consulta', null, 1, 'minimo_por_desconhecida', 'MTE', 'dado_publico', 'A3, ordem 8. Não respondeu do ambiente de desenvolvimento (24/11/2026): conferir o acesso em produção antes.'),
  ('aneel',             'ANEEL — Indicadores do setor elétrico',           'ANEEL', null, 'mercado', true, 'consulta', null, 1, 'minimo_por_desconhecida', 'ANEEL', 'dado_publico', 'A3, ordem 9 (K6). Não respondeu do ambiente de desenvolvimento (24/11/2026).'),
  ('ccee',              'CCEE — Câmara de Comercialização de Energia',     'CCEE', null, 'mercado', true, 'consulta', null, 1, 'minimo_por_desconhecida', 'CCEE', 'dado_publico', 'A3, ordem 9 (K6). Oficial por decisão 6 do dono (24/11/2026).'),
  ('antt',              'ANTT — Indicadores de transporte',                'ANTT', null, 'mercado', true, 'consulta', null, 1, 'minimo_por_desconhecida', 'ANTT', 'dado_publico', 'A3, ordem 9 (K6).'),
  ('anp',               'ANP — Indicadores de petróleo e combustíveis',    'ANP', null, 'mercado', true, 'consulta', null, 1, 'minimo_por_desconhecida', 'ANP', 'dado_publico', 'A3, ordem 9 (K6).'),
  ('susep',             'SUSEP — Indicadores de seguros',                  'SUSEP', null, 'mercado', true, 'consulta', null, 1, 'minimo_por_desconhecida', 'SUSEP', 'dado_publico', 'A3, ordem 9 (K6).'),
  ('fipezap',           'FipeZAP — Índice de preços de imóveis',           'Fipe/ZAP', null, 'mercado', true, 'consulta', null, 1, 'minimo_por_desconhecida', 'Fipe/ZAP', 'dado_publico', 'A3, ordem 9 (K6). Oficial por decisão 6 do dono (24/11/2026).'),
  ('brasilapi_cnpj',    'BrasilAPI — Cadastro de CNPJ (espelho não oficial)','BrasilAPI (comunidade), espelho da Receita Federal', null, 'empresa', false, 'consulta', null, 1, 'minimo_por_desconhecida', 'BrasilAPI', 'dado_publico', 'A4. Decisão 2 do dono (24/11/2026): NÃO OFICIAL. Traz cadastro, CNAE, situação e quadro de sócios; os sócios ficam guardados e não são consultados (só CNPJ). http_inexistente nulo até confirmar o status de "CNPJ não consta" em produção.'),
  ('cgu_ceis',          'CGU — Cadastro de Empresas Inidôneas e Suspensas (CEIS)', 'Controladoria-Geral da União', null, 'empresa', true, 'lista', null, 1, 'minimo_por_desconhecida', 'CGU', 'dado_publico', 'A4. Download da lista inteira; a consulta procura o CNPJ nela (lista pequena, decisão 3).'),
  ('cgu_cnep',          'CGU — Cadastro Nacional de Empresas Punidas (CNEP)', 'Controladoria-Geral da União', null, 'empresa', true, 'lista', null, 1, 'minimo_por_desconhecida', 'CGU', 'dado_publico', 'A4. Mesma forma do CEIS.'),
  ('mte_trabalho_escravo','MTE — Cadastro de empregadores (trabalho escravo)', 'Ministério do Trabalho e Emprego', null, 'empresa', true, 'lista', null, 1, 'minimo_por_desconhecida', 'MTE', 'dado_publico', 'A4. Lista semestral inteira; a consulta procura o CNPJ. Prazo de 1 dia até a A4 conhecer a DATA de publicação da lista (decisão do dono, 24/11/2026): 180 dias da consulta venceriam tarde demais.'),
  ('ibama_autos',       'IBAMA — Autos de infração',                       'IBAMA', null, 'empresa', true, 'lista', null, 1, 'minimo_por_desconhecida', 'IBAMA', 'dado_publico', 'A4. Autos e embargos são duas listas, duas linhas: o resultado de uma não esconde a falha da outra. Medir o tamanho antes de baixar.'),
  ('ibama_embargos',    'IBAMA — Áreas embargadas',                        'IBAMA', null, 'empresa', true, 'lista', null, 1, 'minimo_por_desconhecida', 'IBAMA', 'dado_publico', 'A4. Ver ibama_autos.'),
  ('pgfn_divida_ativa', 'PGFN — Dívida ativa da União',                    'Procuradoria-Geral da Fazenda Nacional', null, 'empresa', true, 'consulta', null, 1, 'minimo_por_desconhecida', 'PGFN', 'dado_publico', 'A4. Por consulta (decisão 3). A fonte POR CNPJ ainda não foi achada: se só houver o arquivo trimestral, ler em fluxo e guardar só os CNPJs do caso.')
on conflict (chave) do nothing;

-- -----------------------------------------------------------------------------
-- 6. A SONDA. Marcadores em CÓDIGO, nunca de comentário.
-- -----------------------------------------------------------------------------
-- As 9 CHECKs que fecham o buraco calado (um service_role que grave direto não pode fabricar "nada" nem aceitar CPF).
create view instalacao_sonda_consulta_externa_checks as
  select k.conname::text as restricao
    from pg_constraint k
   where k.conrelid = 'public.consulta_externa'::regclass and k.contype = 'c' and k.convalidated
     and ((k.conname = 'consulta_externa_resultado_valido' and pg_get_constraintdef(k.oid) like '%nada_encontrado%')
       or (k.conname = 'consulta_externa_alvo_so_cnpj' and pg_get_constraintdef(k.oid) like '%[0-9]{14}%')
       or (k.conname = 'consulta_externa_motivo_obrigatorio' and pg_get_constraintdef(k.oid) like '%btrim%')
       or (k.conname = 'consulta_externa_status_coerente' and pg_get_constraintdef(k.oid) like '%nao_consultado%')
       or (k.conname = 'consulta_externa_prova_de_leitura' and pg_get_constraintdef(k.oid) like '%nada_encontrado%' and pg_get_constraintdef(k.oid) like '%hash_bruto IS NOT NULL%'
            and pg_get_constraintdef(k.oid) like '%e3b0c44298fc1c14%' and pg_get_constraintdef(k.oid) like '%nao_consultado%')
       or (k.conname = 'consulta_externa_registros_validos' and pg_get_constraintdef(k.oid) like '%registros_lidos >= 0%')
       or (k.conname = 'consulta_externa_hash_formato' and pg_get_constraintdef(k.oid) like '%[0-9a-f]{64}%')
       or (k.conname = 'consulta_externa_custo_nao_negativo' and pg_get_constraintdef(k.oid) like '%custo >= %')
       or (k.conname = 'consulta_externa_validade_depois' and pg_get_constraintdef(k.oid) like '%validade_em >= data_consulta%'));
comment on view instalacao_sonda_consulta_externa_checks is
  'Sonda da 0303: uma linha = uma das 9 CHECKs de consulta_externa existe, validada, com o conteúdo certo (resultado nos quatro estados; alvo só CNPJ de 14 dígitos; motivo obrigatório; status coerente; hash em encontrado E em nada_encontrado, nunca o da string vazia, e nenhum em nao_consultado; registros lidos >= 0; hash de 64 hex; custo >= 0; validade depois da consulta). Menos de 9: o service_role grava resultado incoerente com o status, falha sem motivo ou CPF.';

-- TODA FONTE TEM PRAZO (decisão 8): validade_dias e validade_origem NOT NULL e o CHECK que amarra a origem ao número. Sem isto o catálogo volta a aceitar fonte sem prazo.
create view instalacao_sonda_fonte_externa_prazo as
  select 1 as ok
   where exists (select 1 from pg_constraint k
                  where k.conrelid = 'public.fonte_externa'::regclass and k.conname = 'fonte_externa_validade_coerente' and k.contype = 'c' and k.convalidated
                    and pg_get_constraintdef(k.oid) like '%minimo_por_desconhecida%' and pg_get_constraintdef(k.oid) like '%semestral%')
     and (select count(*) from pg_attribute a
           where a.attrelid = 'public.fonte_externa'::regclass and a.attname in ('validade_dias', 'validade_origem', 'forma') and a.attnotnull and not a.attisdropped) = 3
     and (select a.attnotnull from pg_attribute a where a.attrelid = 'public.consulta_externa'::regclass and a.attname = 'validade_em' and not a.attisdropped);
comment on view instalacao_sonda_fonte_externa_prazo is
  'Sonda da 0303: uma linha = fonte_externa tem validade_dias, validade_origem e forma NOT NULL, o CHECK que amarra a origem do prazo ao número (decisão 8 do dono) e consulta_externa.validade_em é NOT NULL. Zero linhas: uma fonte pode ficar sem prazo e a consulta dela nunca vence.';

-- O authenticated só LÊ as três tabelas: se ganhar escrita direta, ele classifica sozinho e a função deixa de ser o ponto único.
create view instalacao_sonda_externa_so_le as
  select 1 as ok
   where has_table_privilege('authenticated', 'public.fonte_externa'::regclass, 'select')
     and has_table_privilege('authenticated', 'public.consulta_externa'::regclass, 'select')
     and has_table_privilege('authenticated', 'public.fato_externo'::regclass, 'select')
     and not has_any_column_privilege('authenticated', 'public.fonte_externa'::regclass, 'insert')
     and not has_any_column_privilege('authenticated', 'public.fonte_externa'::regclass, 'update')
     and not has_table_privilege('authenticated', 'public.fonte_externa'::regclass, 'delete')
     and not has_any_column_privilege('authenticated', 'public.consulta_externa'::regclass, 'insert')
     and not has_any_column_privilege('authenticated', 'public.consulta_externa'::regclass, 'update')
     and not has_table_privilege('authenticated', 'public.consulta_externa'::regclass, 'delete')
     and not has_any_column_privilege('authenticated', 'public.fato_externo'::regclass, 'insert')
     and not has_any_column_privilege('authenticated', 'public.fato_externo'::regclass, 'update')
     and not has_table_privilege('authenticated', 'public.fato_externo'::regclass, 'delete')
     and not has_any_column_privilege('anon', 'public.consulta_externa'::regclass, 'select')
     and not has_function_privilege('anon', 'public.fn_registrar_consulta_externa(text, uuid, text, integer, text, text, jsonb, integer, numeric, text)'::regprocedure, 'execute');
comment on view instalacao_sonda_externa_so_le is
  'Sonda da 0303: uma linha = o authenticated só LÊ fonte_externa, consulta_externa e fato_externo (nenhum privilégio de escrita, nem de coluna), e o anon não lê a consulta nem executa fn_registrar_consulta_externa. Zero linhas: o portal ganhou escrita direta e pode classificar sozinho "falhou" como "nada_encontrado".';

-- REVOKE ANTES DO GRANT (lição da 0302): o default de privilégio do Supabase dá ALL a toda view nova.
revoke all on instalacao_sonda_consulta_externa_checks, instalacao_sonda_externa_so_le, instalacao_sonda_fonte_externa_prazo from public, anon, authenticated, service_role;
grant select on instalacao_sonda_consulta_externa_checks, instalacao_sonda_externa_so_le, instalacao_sonda_fonte_externa_prazo to authenticated, service_role;

delete from instalacao_requisito where migration = '0303';
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fonte_externa_tabela', '0303', 'tabela', 'fonte_externa', null, null,
   'O catálogo das fontes externas. Ausente = a 0303 não foi aplicada: nenhuma consulta externa tem onde se apoiar, e a fonte fora do catálogo não é recusada.', 'importante', 1420),
  ('consulta_externa_tabela', '0303', 'tabela', 'consulta_externa', null, null,
   'Onde cada tentativa de consulta externa é gravada, com o resultado em quatro estados. Ausente = a falha de uma fonte não tem onde ser registrada, e vira "sem dado" no chamador.', 'importante', 1421),
  ('fato_externo_tabela', '0303', 'tabela', 'fato_externo', null, null,
   'O dado achado por uma consulta, ligado a ela. Ausente = o dado externo não tem origem rastreável.', 'importante', 1422),
  ('fontes_externas_semeadas', '0303', 'seed', 'fonte_externa', null, 22,
   'As 22 fontes da A3 e da A4 (15 de mercado, 7 de empresa). Menos = uma fonte do plano não está no catálogo e a consulta a ela é recusada pelo banco.', 'importante', 1423),
  ('consulta_externa_registrar_funcao', '0303', 'funcao', 'fn_registrar_consulta_externa', null, null,
   'O ponto único de registro e de classificação. Ausente = cada chamador (n8n, portal) volta a decidir sozinho o que um timeout significa.', 'importante', 1424),
  ('consulta_externa_classifica_pelo_itens', '0303', 'corpo', 'fn_registrar_consulta_externa', 'jsonb_array_length(p_itens)', null,
   'A classificação de 2xx pela lista de itens (vazia = nada_encontrado, cheia = encontrado). Corpo sem isto = "encontrado" ou "nada" decididos por outra regra, ou por quem chamou.', 'bloqueante', 1425),
  ('consulta_externa_so_o_4xx_documentado', '0303', 'corpo', 'fn_registrar_consulta_externa', 'f.http_inexistente', null,
   'Só o status que a FONTE documenta como "não existe" vira nada_encontrado. Corpo sem isto = todo 404 (inclusive o da fonte que mudou de endereço) vira "sem sanções".', 'bloqueante', 1426),
  ('consulta_externa_guarda_empresa', '0303', 'corpo', 'fn_registrar_consulta_externa', 'fn_pode_escrever_caso(p_caso)', null,
   'Registrar consulta de empresa exige escrever o mandato. Corpo sem isto = qualquer authenticated grava consulta (e fato) no mandato de outro.', 'bloqueante', 1427),
  ('consulta_externa_guarda_mercado', '0303', 'corpo', 'fn_registrar_consulta_externa', 'fn_eh_socio()', null,
   'Registrar consulta de mercado é de Sócio ou da conexão de serviço. Corpo sem isto = qualquer authenticated grava consulta de mercado.', 'importante', 1428),
  ('consulta_externa_nao_li_nao_e_vazio', '0303', 'corpo', 'fn_registrar_consulta_externa', 'p_itens deve ser um array', null,
   '2xx sem a lista de itens é recusado. Corpo sem isto = uma resposta que o chamador não leu vira "nada_encontrado".', 'bloqueante', 1429),
  ('consulta_externa_hash_do_bruto', '0303', 'corpo', 'fn_registrar_consulta_externa', 'sha256(convert_to(p_corpo', null,
   'O hash do corpo cru é gravado pela função. Corpo sem isto = `encontrado` sem a prova do que a fonte devolveu (a CHECK recusa, e a função passa a falhar).', 'importante', 1430),
  ('consulta_externa_valida_gatilho', '0303', 'gatilho', 'consulta_externa.trg_consulta_externa_valida', 'fn_trg_consulta_externa_valida', null,
   'Fonte fora do catálogo, empresa sem mandato/CNPJ, mercado com mandato e nada_encontrado com status que a fonte não documenta são recusados aqui, também para o service_role. Sem o gatilho, só a função os recusa.', 'bloqueante', 1431),
  ('consulta_externa_imutavel_gatilho', '0303', 'gatilho', 'consulta_externa.trg_consulta_externa_imutavel', 'fn_trg_externo_imutavel', null,
   'A consulta é imutável. Sem o gatilho, "falhou" pode ser atualizado para "nada_encontrado" e a falha some.', 'bloqueante', 1432),
  ('consulta_externa_com_fato_gatilho', '0303', 'gatilho', 'consulta_externa.trg_consulta_externa_com_fato', 'fn_trg_consulta_externa_com_fato', null,
   'Consulta "encontrado" sem nenhum fato é recusada ao fim da transação. Sem o gatilho, a ausência se apresenta como dado.', 'importante', 1433),
  ('fato_externo_valida_gatilho', '0303', 'gatilho', 'fato_externo.trg_fato_externo_valida', 'fn_trg_fato_externo_valida', null,
   'Fato só em consulta "encontrado". Sem o gatilho, uma consulta nada_encontrado ou falhou pode ter fato e o "nada" contradiz o dado.', 'bloqueante', 1434),
  ('fato_externo_imutavel_gatilho', '0303', 'gatilho', 'fato_externo.trg_fato_externo_imutavel', 'fn_trg_externo_imutavel', null,
   'O fato é imutável: o dado achado não é reescrito depois.', 'importante', 1435),
  ('consulta_externa_valida_corpo', '0303', 'corpo', 'fn_trg_consulta_externa_valida', 'f.http_inexistente', null,
   'O gatilho confere nada_encontrado com 4xx contra o status que a fonte documenta. Corpo sem isto = o service_role grava "nada" com um 404 qualquer.', 'bloqueante', 1436),
  ('fato_externo_valida_corpo', '0303', 'corpo', 'fn_trg_fato_externo_valida', 'v_res <> ''encontrado''', null,
   'O gatilho do fato recusa o que não é consulta "encontrado". Corpo trocado = o fato entra em qualquer consulta.', 'bloqueante', 1437),
  ('fonte_externa_leitura_policy', '0303', 'policy', 'fonte_externa.fonte_externa_read', null, null,
   'RLS ligada sem policy de leitura devolve zero calado: o catálogo pareceria vazio e toda fonte, fora do catálogo.', 'importante', 1438),
  ('consulta_externa_leitura_policy', '0303', 'policy', 'consulta_externa.consulta_externa_read', null, null,
   'RLS ligada sem policy de leitura devolve zero calado: nenhuma consulta apareceria, e uma fonte caída pareceria nunca ter sido consultada.', 'importante', 1439),
  ('fato_externo_leitura_policy', '0303', 'policy', 'fato_externo.fato_externo_read', null, null,
   'RLS ligada sem policy de leitura devolve zero calado: os dados externos não apareceriam.', 'importante', 1440),
  ('consulta_externa_checks', '0303', 'comportamento', 'instalacao_sonda_consulta_externa_checks', null, 9,
   'As 9 CHECKs de consulta_externa (resultado nos quatro estados, alvo só CNPJ, motivo obrigatório, status coerente, hash em encontrado e em nada, registros lidos, custo, validade). Menos = o service_role grava resultado incoerente, "nada" sem prova de leitura, falha sem motivo ou CPF.', 'bloqueante', 1441),
  ('externa_so_le', '0303', 'comportamento', 'instalacao_sonda_externa_so_le', null, 1,
   'O authenticated só LÊ as três tabelas e o anon nada. Zero linhas = o portal escreve direto e classifica sozinho, e a função deixa de ser o ponto único.', 'bloqueante', 1442),
  ('consulta_externa_alvo_so_cnpj_coluna', '0303', 'coluna', 'consulta_externa.alvo_cnpj', null, null,
   'O alvo da consulta é CNPJ. Coluna ausente = a consulta não tem alvo, e o resultado "uma linha por empresa" não é provável.', 'importante', 1443),
  ('fonte_externa_http_inexistente_coluna', '0303', 'coluna', 'fonte_externa.http_inexistente', null, null,
   'O status que a fonte documenta como "não existe". Coluna ausente = a função não sabe distinguir 404 de rota que mudou, e a regra volta a ser decidida fora do banco.', 'importante', 1444),
  ('consulta_externa_sem_delete_gatilho', '0303', 'gatilho', 'consulta_externa.trg_consulta_externa_sem_delete', 'fn_trg_externo_sem_delete', null,
   'A consulta não se apaga (só a cascata do mandato). Sem o gatilho, o service_role apaga a "falhou" mais nova e a "nada_encontrado" antiga volta a ser a mais recente.', 'bloqueante', 1445),
  ('fato_externo_sem_delete_gatilho', '0303', 'gatilho', 'fato_externo.trg_fato_externo_sem_delete', 'fn_trg_externo_sem_delete', null,
   'O fato não se apaga (só a cascata da consulta). Sem o gatilho, o dado achado some e a consulta "encontrado" fica sem fato.', 'importante', 1446),
  ('fonte_externa_prazo_obrigatorio', '0303', 'comportamento', 'instalacao_sonda_fonte_externa_prazo', null, 1,
   'Toda fonte tem prazo (decisão 8): validade_dias, validade_origem e forma NOT NULL, CHECK origem x número, validade_em NOT NULL. Zero linhas = fonte sem prazo, e a consulta dela nunca vence (parece nova estando velha).', 'bloqueante', 1447),
  ('consulta_externa_lista_exige_registros', '0303', 'corpo', 'fn_registrar_consulta_externa', 'coalesce(p_registros_lidos, 0) <= 0', null,
   'Fonte de lista só dá "nada"/"achado" com registros lidos > 0 (marcador do ramo, não o nome do parâmetro, que também está na assinatura). Corpo sem isto = lista vazia ou página de manutenção com 200 vira "sem sanções" (lista truncada com registros não é detectada: teto, mínimo por fonte na A4).', 'bloqueante', 1448),
  ('consulta_externa_data_e_prazo_do_banco', '0303', 'corpo', 'fn_trg_consulta_externa_valida', 'new.data_consulta := clock_timestamp()', null,
   'A data da consulta é do banco e o vencimento vem do catálogo. Corpo sem isto = um "nada_encontrado" datado 2099 vira a consulta mais recente e esconde as falhas reais.', 'bloqueante', 1449),
  ('fonte_externa_forma_coluna', '0303', 'coluna', 'fonte_externa.forma', null, null,
   'Lista ou consulta. Coluna ausente = a função não distingue a fonte baixada inteira (200 vazio suspeito) da respondida por alvo.', 'importante', 1450),
  ('fonte_externa_validade_origem_coluna', '0303', 'coluna', 'fonte_externa.validade_origem', null, null,
   'De onde veio o prazo (publicado, cadência, mínimo por desconhecida). Coluna ausente = o prazo de 1 dia não se distingue de um prazo medido.', 'importante', 1451),
  ('consulta_externa_registros_lidos_coluna', '0303', 'coluna', 'consulta_externa.registros_lidos', null, null,
   'Quantos registros o chamador leu da fonte. Coluna ausente = a lista vazia não se distingue da lista lida sem achado.', 'importante', 1452),
  ('consulta_externa_corpo_vazio_nao_e_leitura', '0303', 'corpo', 'fn_registrar_consulta_externa', 'btrim(p_corpo, E'' \t\r\n'') = ''''', null,
   'Corpo vazio (ou só espaço) é "não li": falhou. Corpo sem isto = o 200 vazio de um proxy em manutenção tem o hash da string vazia, passa como prova de leitura e grava "nada_encontrado".', 'bloqueante', 1453),
  ('consulta_externa_valida_lista_registros', '0303', 'corpo', 'fn_trg_consulta_externa_valida', 'coalesce(new.registros_lidos, 0) <= 0', null,
   'O gatilho recusa encontrado e nada_encontrado de fonte de LISTA sem registros lidos, também para quem grava direto. Corpo sem isto = o service_role grava "nada" de uma lista que não foi lida.', 'bloqueante', 1454),
  ('consulta_externa_valida_lista_4xx', '0303', 'corpo', 'fn_trg_consulta_externa_valida', 'not (new.http_status between 200 and 299) then', null,
   'O gatilho recusa nada_encontrado com 4xx em fonte de LISTA (marcador: o `then` que fecha só o ramo da lista; o mesmo teste sem o `then` também está no ramo geral), mesmo que http_inexistente seja preenchido: 4xx de lista é o arquivo que sumiu. Corpo sem isto = o 404 de uma lista que mudou de endereço vira "sem sanções".', 'bloqueante', 1455)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = greatest(ate_migration, '0303'), revisado_em = current_date,
       observacao = 'A 0303 cria a base comum das fontes externas (Fase A, A2): fonte_externa (catálogo, 22 fontes semeadas), consulta_externa (4 estados, imutável e sem DELETE, alvo só CNPJ, data e prazo do banco) e fato_externo, a função única fn_registrar_consulta_externa que classifica o desfecho cru (falhou nunca vira nada_encontrado), RLS por mandato, 7 gatilhos, 3 views de sonda e 36 requisitos novos (ordem 1420-1455). Não toca nenhuma função existente.'
 where id = true;

commit;
