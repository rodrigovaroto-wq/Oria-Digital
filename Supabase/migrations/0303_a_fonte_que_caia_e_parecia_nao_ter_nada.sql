-- =============================================================================
-- 0303 — A FONTE QUE CAÍA E PARECIA NÃO TER NADA: a base comum das fontes externas (Fase A, fatia A2) — catálogo `fonte_externa`,
--        `consulta_externa` (cada tentativa, com o resultado em QUATRO estados) e `fato_externo` (o dado achado, ligado à consulta que o trouxe),
--        mais o ponto único de registro `fn_registrar_consulta_externa`, que é quem CLASSIFICA o desfecho
-- (Cria 3 tabelas, 4 funções de gatilho, 1 função de registro, 5 gatilhos (um deles deferido), 22 linhas de catálogo, 2 views de sonda e 25
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
--   * `fn_registrar_consulta_externa(fonte, caso, cnpj, http_status, erro, corpo, itens, nao_consultado, custo, quando)` recebe o desfecho CRU e decide:
--       - motivo de não consultar informado            -> `nao_consultado` (sem status, sem erro, sem itens: não houve chamada);
--       - texto de erro informado                       -> `falhou` (erro de rede, timeout, corpo que não é JSON: o chamador não conseguiu ler);
--       - sem status HTTP (timeout, DNS, conexão)      -> `falhou`;
--       - 2xx com `itens` = []                          -> `nada_encontrado`; 2xx com itens -> `encontrado` (e grava um `fato_externo` por item);
--       - o status que a FONTE documenta como "não existe" (`fonte_externa.http_inexistente`) -> `nada_encontrado`;
--       - QUALQUER OUTRO status (1xx, 3xx, 4xx, 5xx)    -> `falhou`. 2xx sem a lista `itens` é recusado: o chamador não leu a resposta, e "não li" não é "vazio".
--   * O 404 NÃO é tratado como "não existe" por padrão, e esta é a decisão de desenho que importa: um 404 é também o que uma fonte que MUDOU DE
--     ENDEREÇO devolve (o risco que o plano já registrou). `http_inexistente` nasce NULO para as 22 fontes do seed e só é preenchido, por fonte, depois de
--     alguém CONFIRMAR em produção que aquela API devolve esse status para "este CNPJ não consta" e não para "esta rota não existe". Enquanto for nulo,
--     o 404 é `falhou` — o erro vai para o lado seguro (a tela diz "falhou, tente de novo", nunca "sem sanções"). O custo: um CNPJ que a BrasilAPI
--     não conhece aparece como "falhou" até a A4 medir e preencher; é preferível a fabricar um "nada".
--
-- AS REGRAS NO BANCO, não na tela (o que o portal e o n8n não conseguem desfazer):
--   1. `falhou` nunca vira `nada_encontrado`: `consulta_externa` é IMUTÁVEL (gatilho BEFORE UPDATE recusa QUALQUER atualização, inclusive do service_role e do
--      superusuário; nova tentativa = nova linha). Não há como corrigir "falhou" para "nada" nem por engano nem por script.
--   2. `falhou` e `nao_consultado` exigem motivo não vazio (CHECK): ausência sem a causa e o EFEITO não é registrada (regra 1 do CLAUDE.md).
--   3. O resultado concorda com o status HTTP (CHECK): `encontrado` só com 2xx, `nada_encontrado` só com 2xx ou 4xx, `nao_consultado` sem status. Quem
--      gravar direto (service_role) uma "nada_encontrado" com HTTP 503 leva 23514. A concordância com o status que A FONTE documenta fica no gatilho.
--   4. `fato_externo` só existe em consulta `encontrado` (gatilho), e `encontrado` sem nenhum fato é recusado ao fim da transação (gatilho deferido):
--      `nada_encontrado` nunca tem fato, e `encontrado` nunca é vazio. `encontrado` exige o hash do bruto (a prova do que a fonte devolveu).
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
--   8. RLS (0216): `consulta_externa` lê pelo mandato (Sócio lê tudo; os demais, onde estão alocados) E, para a consulta de MERCADO (sem mandato), qualquer
--      um da equipe (`fn_tem_papel`); `fato_externo` lê o que a consulta dele deixa ler; o catálogo lê por `fn_tem_papel` (equipe inteira).
--   9. GRANT explícito (0214): authenticated SELECT; service_role as quatro operações (a sonda da 0214 o exige; o que o service_role pode escrever de
--      verdade é limitado pelos gatilhos acima, que valem para ele também).
--
-- O QUE FICOU DE FORA, e por quê (não inventado — regra 1):
--   * `autorizacao_id` e `caso.momento` (Espec. 13 §3 peças 2 e 3): vêm com a tabela `autorizacao`, que o plano coloca no item 1.B7. Sem pessoa física aqui, não há o que autorizar.
--   * `origem_compartilhada_com` (Espec. 15 §7, dimensão A4 do score): é do score de confiabilidade (1.B), não da base comum.
--   * Cadência, validade e URL: só estão no seed onde o repositório ou o plano DIZEM. O resto é NULO, com o motivo no comentário de cada linha. Em particular
--     `validade_dias` é nulo nas 22: a Espec. 15 R7 só fixa prazo para certidão (90 dias), e nenhuma das 22 é certidão. A5 ("vencida aparece vencida") PRECISA
--     de um prazo por fonte — é pendência de decisão do dono, e sem ele nenhuma consulta vence.
--   * A cadência do macro: o plano (FASE_A §3) diz "agendamento diário", mas o gerador N8N/build-workflow-macro.mjs agenda MENSAL (dia 12, 06h; o IPCA do
--     mês anterior só sai por volta do dia 10). O seed segue o CÓDIGO (mensal); a divergência do texto do plano está dita aqui e no relatório da fatia.
--   * `oficial`: verdadeiro para órgão público (BCB, IBGE, CVM, CGU, MTE, IBAMA, PGFN, MDIC, ANEEL, ANTT, ANP, SUSEP, IPEA, MTE/CAGED). Falso para a BrasilAPI (decisão 2 do
--     dono, 24/11/2026: espelho gratuito, "não oficial") e, por critério NOSSO que o dono confirma, para ANBIMA (associação privada), CCEE (câmara privada
--     regulada pela ANEEL) e FipeZAP (índice privado). A escala de origem do score (Espec. 15 A1) decide o peso de cada uma; esta coluna só diz se é órgão público.
--
-- O QUE FICA A APLICAR À MÃO NO SUPABASE: esta migration inteira (nenhum segredo, nenhum dado de cliente). Conferir com a sonda:
--   select chave, presente, detalhe from fn_instalacao_conferir() where migration = '0303' and not presente;   -- ZERO linhas (25 requisitos)
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
  cadencia           text check (cadencia in ('diaria', 'semanal', 'mensal', 'trimestral', 'semestral', 'anual', 'sob_demanda')),
  validade_dias      integer check (validade_dias > 0),
  fornecedor         text not null check (btrim(fornecedor) <> ''),
  base_legal_tipica  text not null check (base_legal_tipica in ('dado_publico', 'autorizacao_pre_mandato', 'termo_kickoff', 'consentimento_open_finance')),
  http_inexistente   smallint check (http_inexistente between 400 and 499),
  observacao         text,
  criado_em          timestamptz not null default now()
);
comment on table fonte_externa is
  '0303: o catálogo das fontes externas (Espec. 13 §3, Espec. 15 §7). Toda consulta aponta para uma linha daqui (FK): fonte fora do catálogo é recusada pelo banco. `tipo` diz onde roda e se carrega dado de cliente: mercado (agendado, n8n, sem CNPJ) ou empresa (sob demanda, servidor do portal, por CNPJ).';
comment on column fonte_externa.oficial is 'É órgão público? Falso para espelho gratuito (BrasilAPI, decisão 2 do dono de 24/11/2026) e para entidade privada (ANBIMA, CCEE, FipeZAP). Não é o peso da fonte no score (Espec. 15 A1).';
comment on column fonte_externa.cadencia is 'Cadência ESPERADA de atualização da fonte. NULA = o plano e o repositório não dizem; ausência, não zero (regra 1).';
comment on column fonte_externa.validade_dias is 'Prazo de vencimento de uma consulta, em dias (Espec. 13 R7). NULO = ninguém decidiu: a consulta não vence (e a tela não pode marcá-la vencida). Pendência do dono antes da A5.';
comment on column fonte_externa.http_inexistente is 'O status 4xx que ESTA fonte documenta e devolve para "este alvo não consta" (e não para "rota inexistente"). NULO = nenhum: todo status que não seja 2xx é falha. Só se preenche depois de confirmar a API em produção — um 404 também é o que uma fonte que mudou de endereço devolve.';

alter table fonte_externa enable row level security;
create policy fonte_externa_read on fonte_externa for select to authenticated using ((select fn_tem_papel()));
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
  data_consulta   timestamptz not null default now(),
  validade_em     timestamptz,
  custo           numeric(12, 4) not null default 0,
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
  constraint consulta_externa_encontrado_com_hash check (resultado <> 'encontrado' or hash_bruto is not null),
  constraint consulta_externa_hash_formato check (hash_bruto is null or hash_bruto ~ '^[0-9a-f]{64}$'),
  constraint consulta_externa_custo_nao_negativo check (custo >= 0),
  constraint consulta_externa_validade_depois check (validade_em is null or validade_em >= data_consulta)
);
comment on table consulta_externa is
  '0303: cada TENTATIVA de consulta a uma fonte externa, com o resultado em quatro estados (encontrado, nada_encontrado, falhou, nao_consultado). IMUTÁVEL: nova tentativa = nova linha (falhou nunca vira nada_encontrado). Escrita só por fn_registrar_consulta_externa. Alvo SÓ CNPJ (CPF é recusado de propósito: conflito N-C7b/R5 com a decisão de 24/11/2026, nas pendências). caso_id nulo = fonte de mercado.';
comment on constraint consulta_externa_alvo_so_cnpj on consulta_externa is
  '0303: 14 dígitos, sem máscara. CPF (11 dígitos) é recusado de propósito até a decisão do dono sobre pessoa física (N-C7b/R5 da Espec. 13; pendências).';
comment on constraint consulta_externa_motivo_obrigatorio on consulta_externa is '0303: falhou e nao_consultado dizem a causa; ausência sem causa nem efeito não se registra (regra 1).';
comment on constraint consulta_externa_status_coerente on consulta_externa is '0303: o resultado concorda com o status HTTP: encontrado só com 2xx; nada_encontrado só com 2xx ou 4xx (o 4xx documentado pela fonte, conferido no gatilho); nao_consultado sem status; falhou com qualquer um.';
comment on column consulta_externa.hash_bruto is 'sha256 do corpo cru devolvido pela fonte (texto exato, UTF-8). Obrigatório em `encontrado`: é a prova do que a fonte disse. Nulo quando não houve corpo.';
comment on column consulta_externa.custo is 'Preço da consulta (Espec. 13 R6). Zero nas fontes gratuitas da Fase A; existe para o custo por caso ser medido, não estimado.';
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
  return new;
end $$;
comment on function fn_trg_consulta_externa_valida() is
  '0303: a consulta aponta para fonte do catálogo, e o tipo da fonte decide o que ela leva (empresa: mandato e CNPJ; mercado: nenhum dos dois); nada_encontrado com status 4xx só vale se for o status que a fonte documenta como "não existe" (fonte_externa.http_inexistente).';

create function fn_trg_externo_imutavel() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  raise exception '% é imutável: uma nova tentativa é uma nova linha (falhou nunca vira nada_encontrado)', tg_table_name using errcode = 'restrict_violation';
end $$;
comment on function fn_trg_externo_imutavel() is '0303: recusa todo UPDATE em consulta_externa e fato_externo, inclusive do service_role e do superusuário. A correção de "falhou" é outra consulta, não uma atualização.';

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
create constraint trigger trg_consulta_externa_com_fato after insert on consulta_externa
  deferrable initially deferred for each row execute function fn_trg_consulta_externa_com_fato();
create trigger trg_fato_externo_valida before insert on fato_externo
  for each row execute function fn_trg_fato_externo_valida();
create trigger trg_fato_externo_imutavel before update on fato_externo
  for each row execute function fn_trg_externo_imutavel();

revoke all on function fn_trg_consulta_externa_valida(), fn_trg_externo_imutavel(), fn_trg_fato_externo_valida(), fn_trg_consulta_externa_com_fato() from public, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 4. O PONTO ÚNICO DE REGISTRO — quem CLASSIFICA
-- -----------------------------------------------------------------------------
-- Chamadores previstos (nenhum existe ainda): o n8n das fontes de mercado (A3) e o servidor do portal para as de empresa (A4). Nenhum deles classifica;
-- todos entregam o desfecho cru. `p_itens` é a lista JÁ LIDA da resposta (um objeto {chave, valor, referencia?} por dado): o chamador sabe o formato
-- da fonte, a função decide o que a lista vazia e a lista cheia significam. O hash é do `p_corpo` em texto exato (UTF-8), não do jsonb normalizado.
create function fn_registrar_consulta_externa(
  p_fonte         text,
  p_caso          uuid,
  p_alvo_cnpj     text,
  p_http_status   integer,
  p_erro          text,
  p_corpo         text,
  p_itens         jsonb,
  p_nao_consultado text default null,
  p_custo         numeric default 0,
  p_consultada_em timestamptz default now()
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

  -- A CLASSIFICAÇÃO. Uma ordem só, e `falhou` é o lado seguro de tudo o que não é provadamente outra coisa.
  if p_nao_consultado is not null then
    if length(btrim(p_nao_consultado)) = 0 then
      raise exception 'nao_consultado exige o motivo (e o efeito: o que fica desconhecido)' using errcode = '22023';
    end if;
    if p_http_status is not null or nullif(btrim(coalesce(p_erro, '')), '') is not null or p_itens is not null then
      raise exception 'nao_consultado contradiz uma resposta: não houve chamada, então não há status, erro nem itens' using errcode = '22023';
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
    v_res := case when jsonb_array_length(p_itens) = 0 then 'nada_encontrado' else 'encontrado' end;
  elsif p_http_status = f.http_inexistente then
    if p_itens is not null and jsonb_typeof(p_itens) = 'array' and jsonb_array_length(p_itens) > 0 then
      raise exception 'HTTP % ("não existe" para esta fonte) vindo com itens: resposta contraditória', p_http_status using errcode = '22023';
    end if;
    v_res := 'nada_encontrado';
    v_motivo := format('HTTP %s: a fonte documenta este status como "alvo não consta"', p_http_status);
  else
    v_res := 'falhou';
    v_motivo := format('HTTP %s', p_http_status);
  end if;

  if p_corpo is not null then
    v_hash := encode(sha256(convert_to(p_corpo, 'UTF8')), 'hex');
  end if;

  insert into consulta_externa (id, fonte, caso_id, alvo_cnpj, data_consulta, validade_em, custo, fornecedor, base_legal, http_status, hash_bruto, motivo, resultado)
  values (v_id, f.chave, p_caso, p_alvo_cnpj, p_consultada_em,
          case when f.validade_dias is null then null else p_consultada_em + make_interval(days => f.validade_dias) end,
          coalesce(p_custo, 0), f.fornecedor, f.base_legal_tipica, p_http_status, v_hash, v_motivo, v_res);

  if v_res = 'encontrado' then
    insert into fato_externo (consulta_id, chave, valor, referencia)
    select v_id, e ->> 'chave', e -> 'valor', e ->> 'referencia' from jsonb_array_elements(p_itens) e;
    get diagnostics v_n = row_count;
  end if;

  return jsonb_build_object('id', v_id, 'resultado', v_res, 'motivo', v_motivo, 'fatos', v_n);
end $$;
comment on function fn_registrar_consulta_externa(text, uuid, text, integer, text, text, jsonb, text, numeric, timestamptz) is
  '0303: o ÚNICO ponto de escrita de consulta_externa e fato_externo (o authenticated não tem grant de escrita). Recebe o desfecho CRU da chamada e classifica: motivo de não consultar -> nao_consultado; erro informado ou sem status HTTP (timeout, rede) -> falhou; 2xx com itens [] -> nada_encontrado, com itens -> encontrado + um fato por item; o 4xx que a fonte documenta como "não existe" (fonte_externa.http_inexistente, nulo por padrão) -> nada_encontrado; qualquer outro status -> falhou. 2xx sem a lista de itens é recusado. Fonte fora do catálogo: 23503. Sem permissão: 42501 (empresa: Sócio ou Analista do mandato; mercado: Sócio). Devolve {id, resultado, motivo, fatos}.';
revoke all on function fn_registrar_consulta_externa(text, uuid, text, integer, text, text, jsonb, text, numeric, timestamptz) from public, anon;
grant execute on function fn_registrar_consulta_externa(text, uuid, text, integer, text, text, jsonb, text, numeric, timestamptz) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 5. O SEED DO CATÁLOGO — as fontes da A3 (mercado) e da A4 (empresa). NULO = o plano e o repositório não dizem (regra 1).
-- -----------------------------------------------------------------------------
-- URL: só onde o repositório já a usa (N8N/lib/macro.mjs) ou onde o plano a nomeia; o resto a A3/A4 preenchem ao conectar a fonte, depois de conferir o endereço.
-- cadencia: bcb_sgs e bcb_focus pelo gerador do macro (mensal, dia 12); cgu_* ("download diário" da lista), mte ("lista semestral"), brasilapi e pgfn ("uma consulta
-- por CNPJ", "por consulta") pela tabela da A4. Todas as outras: nula. validade_dias: nula em todas (ver cabeçalho). http_inexistente: nulo em todas (ver cabeçalho).
insert into fonte_externa (chave, nome, origem, url, tipo, oficial, cadencia, fornecedor, base_legal_tipica, observacao) values
  ('bcb_sgs',             'BCB — Séries temporais (SGS)',                    'Banco Central do Brasil', 'https://api.bcb.gov.br/dados/serie/bcdata.sgs', 'mercado', true,  'mensal', 'Banco Central do Brasil', 'dado_publico', 'Já existe no macro (0025, N8N/lib/macro.mjs). Cadência do gerador (dia 12), não a "diária" do texto do plano.'),
  ('bcb_focus',           'BCB — Expectativas de mercado (Focus)',            'Banco Central do Brasil', 'https://olinda.bcb.gov.br/olinda/servico/Expectativas/versao/v1/odata/ExpectativasMercadoAnuais', 'mercado', true, 'mensal', 'Banco Central do Brasil', 'dado_publico', 'Já existe no macro. Mesma cadência do SGS (mesmo workflow).'),
  ('bcb_juros_modalidade','BCB — Taxas de juros por modalidade (Olinda)',    'Banco Central do Brasil', null, 'mercado', true,  null, 'Banco Central do Brasil', 'dado_publico', 'A3, ordem 2. URL e cadência: a A3 define ao conectar.'),
  ('ibge_sidra',          'IBGE — SIDRA',                                    'IBGE', 'https://apisidra.ibge.gov.br/values', 'mercado', true, null, 'IBGE', 'dado_publico', 'A3, ordem 4. A base da URL é a do macro (IPCA); cadência por tabela: a A3 define.'),
  ('cvm_dados_abertos',   'CVM — Dados abertos (cadastro e demonstrações)',  'Comissão de Valores Mobiliários', null, 'mercado', true, null, 'CVM', 'dado_publico', 'A3, ordem 5. Medir o tamanho do banco antes da carga (plano gratuito, 500 MB).'),
  ('anbima_curva',        'ANBIMA — Curva de juros',                         'ANBIMA', null, 'mercado', false, null, 'ANBIMA', 'dado_publico', 'A3, ordem 6. Associação privada: oficial = false por critério nosso (dono confirma).'),
  ('ipeadata',            'IPEADATA — Séries (risco-país e outras)',         'IPEA', null, 'mercado', true, null, 'IPEA', 'dado_publico', 'A3, ordem 7.'),
  ('comex_stat',          'Comex Stat — Exportação e importação por produto','MDIC', null, 'mercado', true, null, 'MDIC', 'dado_publico', 'A3, ordem 7. Já mudou de endereço sem aviso (27/10/2026): razão de ser do estado falhou.'),
  ('caged',               'CAGED — Emprego por setor',                       'Ministério do Trabalho e Emprego (PDET)', null, 'mercado', true, null, 'MTE', 'dado_publico', 'A3, ordem 8. Não respondeu do ambiente de desenvolvimento (24/11/2026): conferir o acesso em produção antes.'),
  ('aneel',               'ANEEL — Indicadores do setor elétrico',           'ANEEL', null, 'mercado', true, null, 'ANEEL', 'dado_publico', 'A3, ordem 9 (K6). Não respondeu do ambiente de desenvolvimento (24/11/2026).'),
  ('ccee',                'CCEE — Câmara de Comercialização de Energia',     'CCEE', null, 'mercado', false, null, 'CCEE', 'dado_publico', 'A3, ordem 9 (K6). Câmara privada regulada pela ANEEL: oficial = false por critério nosso (dono confirma).'),
  ('antt',                'ANTT — Indicadores de transporte',                'ANTT', null, 'mercado', true, null, 'ANTT', 'dado_publico', 'A3, ordem 9 (K6).'),
  ('anp',                 'ANP — Indicadores de petróleo e combustíveis',    'ANP', null, 'mercado', true, null, 'ANP', 'dado_publico', 'A3, ordem 9 (K6).'),
  ('susep',               'SUSEP — Indicadores de seguros',                  'SUSEP', null, 'mercado', true, null, 'SUSEP', 'dado_publico', 'A3, ordem 9 (K6).'),
  ('fipezap',             'FipeZAP — Índice de preços de imóveis',           'Fipe/ZAP', null, 'mercado', false, null, 'Fipe/ZAP', 'dado_publico', 'A3, ordem 9 (K6). Índice privado: oficial = false por critério nosso (dono confirma).'),
  ('brasilapi_cnpj',      'BrasilAPI — Cadastro de CNPJ (espelho não oficial)','BrasilAPI (comunidade), espelho da Receita Federal', null, 'empresa', false, 'sob_demanda', 'BrasilAPI', 'dado_publico', 'A4. Decisão 2 do dono (24/11/2026): NÃO OFICIAL. Traz cadastro, CNAE, situação e quadro de sócios; os sócios ficam guardados e não são consultados (só CNPJ). http_inexistente nulo até confirmar o status de "CNPJ não consta" em produção.'),
  ('cgu_ceis',            'CGU — Cadastro de Empresas Inidôneas e Suspensas (CEIS)', 'Controladoria-Geral da União', null, 'empresa', true, 'diaria', 'CGU', 'dado_publico', 'A4. Download da lista inteira; a consulta procura o CNPJ nela (lista pequena, decisão 3).'),
  ('cgu_cnep',            'CGU — Cadastro Nacional de Empresas Punidas (CNEP)', 'Controladoria-Geral da União', null, 'empresa', true, 'diaria', 'CGU', 'dado_publico', 'A4. Mesma forma do CEIS.'),
  ('mte_trabalho_escravo','MTE — Cadastro de empregadores (trabalho escravo)', 'Ministério do Trabalho e Emprego', null, 'empresa', true, 'semestral', 'MTE', 'dado_publico', 'A4. Lista semestral inteira; a consulta procura o CNPJ.'),
  ('ibama_autos',         'IBAMA — Autos de infração',                       'IBAMA', null, 'empresa', true, null, 'IBAMA', 'dado_publico', 'A4. Autos e embargos são duas listas, duas linhas: o resultado de uma não esconde a falha da outra. Medir o tamanho antes de baixar.'),
  ('ibama_embargos',      'IBAMA — Áreas embargadas',                        'IBAMA', null, 'empresa', true, null, 'IBAMA', 'dado_publico', 'A4. Ver ibama_autos.'),
  ('pgfn_divida_ativa',   'PGFN — Dívida ativa da União',                    'Procuradoria-Geral da Fazenda Nacional', null, 'empresa', true, 'sob_demanda', 'PGFN', 'dado_publico', 'A4. Por consulta (decisão 3). A fonte POR CNPJ ainda não foi achada: se só houver o arquivo trimestral, ler em fluxo e guardar só os CNPJs do caso.')
on conflict (chave) do nothing;

-- -----------------------------------------------------------------------------
-- 6. A SONDA. Marcadores em CÓDIGO, nunca de comentário.
-- -----------------------------------------------------------------------------
-- As 8 CHECKs que fecham o buraco calado (um service_role que grave direto não pode fabricar "nada" nem aceitar CPF).
create view instalacao_sonda_consulta_externa_checks as
  select k.conname::text as restricao
    from pg_constraint k
   where k.conrelid = 'public.consulta_externa'::regclass and k.contype = 'c' and k.convalidated
     and ((k.conname = 'consulta_externa_resultado_valido' and pg_get_constraintdef(k.oid) like '%nada_encontrado%')
       or (k.conname = 'consulta_externa_alvo_so_cnpj' and pg_get_constraintdef(k.oid) like '%[0-9]{14}%')
       or (k.conname = 'consulta_externa_motivo_obrigatorio' and pg_get_constraintdef(k.oid) like '%btrim%')
       or (k.conname = 'consulta_externa_status_coerente' and pg_get_constraintdef(k.oid) like '%nao_consultado%')
       or (k.conname = 'consulta_externa_encontrado_com_hash' and pg_get_constraintdef(k.oid) like '%hash_bruto IS NOT NULL%')
       or (k.conname = 'consulta_externa_hash_formato' and pg_get_constraintdef(k.oid) like '%[0-9a-f]{64}%')
       or (k.conname = 'consulta_externa_custo_nao_negativo' and pg_get_constraintdef(k.oid) like '%custo >= %')
       or (k.conname = 'consulta_externa_validade_depois' and pg_get_constraintdef(k.oid) like '%validade_em >= data_consulta%'));
comment on view instalacao_sonda_consulta_externa_checks is
  'Sonda da 0303: uma linha = uma das 8 CHECKs de consulta_externa existe, validada, com o conteúdo certo (resultado nos quatro estados; alvo só CNPJ de 14 dígitos; motivo obrigatório; status coerente; hash em encontrado; hash de 64 hex; custo >= 0; validade depois da consulta). Menos de 8: o service_role grava resultado incoerente com o status, falha sem motivo ou CPF.';

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
     and not has_function_privilege('anon', 'public.fn_registrar_consulta_externa(text, uuid, text, integer, text, text, jsonb, text, numeric, timestamptz)'::regprocedure, 'execute');
comment on view instalacao_sonda_externa_so_le is
  'Sonda da 0303: uma linha = o authenticated só LÊ fonte_externa, consulta_externa e fato_externo (nenhum privilégio de escrita, nem de coluna), e o anon não lê a consulta nem executa fn_registrar_consulta_externa. Zero linhas: o portal ganhou escrita direta e pode classificar sozinho "falhou" como "nada_encontrado".';

-- REVOKE ANTES DO GRANT (lição da 0302): o default de privilégio do Supabase dá ALL a toda view nova.
revoke all on instalacao_sonda_consulta_externa_checks, instalacao_sonda_externa_so_le from public, anon, authenticated, service_role;
grant select on instalacao_sonda_consulta_externa_checks, instalacao_sonda_externa_so_le to authenticated, service_role;

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
  ('consulta_externa_checks', '0303', 'comportamento', 'instalacao_sonda_consulta_externa_checks', null, 8,
   'As 8 CHECKs de consulta_externa (resultado nos quatro estados, alvo só CNPJ, motivo obrigatório, status coerente, hash, custo, validade). Menos = o service_role grava resultado incoerente, falha sem motivo ou CPF.', 'bloqueante', 1441),
  ('externa_so_le', '0303', 'comportamento', 'instalacao_sonda_externa_so_le', null, 1,
   'O authenticated só LÊ as três tabelas e o anon nada. Zero linhas = o portal escreve direto e classifica sozinho, e a função deixa de ser o ponto único.', 'bloqueante', 1442),
  ('consulta_externa_alvo_so_cnpj_coluna', '0303', 'coluna', 'consulta_externa.alvo_cnpj', null, null,
   'O alvo da consulta é CNPJ. Coluna ausente = a consulta não tem alvo, e o resultado "uma linha por empresa" não é provável.', 'importante', 1443),
  ('fonte_externa_http_inexistente_coluna', '0303', 'coluna', 'fonte_externa.http_inexistente', null, null,
   'O status que a fonte documenta como "não existe". Coluna ausente = a função não sabe distinguir 404 de rota que mudou, e a regra volta a ser decidida fora do banco.', 'importante', 1444)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = greatest(ate_migration, '0303'), revisado_em = current_date,
       observacao = 'A 0303 cria a base comum das fontes externas (Fase A, A2): fonte_externa (catálogo, 22 fontes semeadas), consulta_externa (4 estados, imutável, alvo só CNPJ) e fato_externo, a função única fn_registrar_consulta_externa que classifica o desfecho cru (falhou nunca vira nada_encontrado), RLS por mandato, 4 gatilhos, 2 views de sonda e 25 requisitos novos (ordem 1420-1444). Não toca nenhuma função existente.'
 where id = true;

commit;
