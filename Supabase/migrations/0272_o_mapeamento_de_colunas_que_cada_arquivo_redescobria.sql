-- =============================================================================
-- 0272 — O MAPEAMENTO DE COLUNAS QUE CADA ARQUIVO REDESCOBRIA: a tabela do mapeamento confirmado por um analista,
--        reaproveitado pela impressão digital do cabeçalho (MB2 do PLANO_MVP_2026-11.md; contrato em Leitor/lib/mapeamento.mjs)
-- (Cria 1 tabela, 4 funções, 1 policy de leitura, 2 views da sonda. Nenhum backfill: a tabela nasce vazia.)
-- NUMERAÇÃO (12/11/2026): escrita como 0242 e renumerada antes de ir a produção. A 0242 de produção é OUTRA (a conta canônica,
-- `0242_a_secao_que_so_existia_em_codigo.sql`, de outra branch, já aplicada), e a maior do repositório era a 0271: esta é a 0272.
--
-- O DEFEITO. O leitor tabular (MB1) entrega linhas e células, mas não sabe o que cada coluna significa. Sem o mapeamento,
-- decidir se a linha é título, subtotal ou lixo é palpite (a revisão de 11/11/2026 viu o palpite errar nos dois sentidos).
-- O analista confirma as colunas na tela, mas sem lugar no banco para guardar a confirmação ela se perde: o MESMO ERP,
-- exportando o MESMO cabeçalho em outro arquivo ou em outro mandato, obrigaria a confirmar de novo. E "arquivo sem
-- mapeamento confirmado não vira dado" (critério de pronto da MB2) exige AUTOR e DATA da confirmação, no banco.
--
-- A TABELA NÃO É POR MANDATO, e isto é decisão, não esquecimento. Ela guarda o NOME das colunas de um ERP ("Vencimento",
-- "Saldo") e o índice de cada uma, nunca uma célula do arquivo do cliente. Conferido contra a 0216 (mapa das tabelas, seção 1):
-- o projeto já tem a classe "global, só leitura: qualquer papel lê, sem papel não lê" (14 tabelas: catálogos e taxonomia) e a
-- classe "global que só Sócio escreve". Esta cai na primeira para a leitura, com a escrita só pela função (como `membro`:
-- o authenticated só lê; a escrita é por função security definer com evento_auditoria). Nenhuma policy `using (true)`
-- (a seção 12 de acesso_por_caso.test.sql proíbe) e nenhuma coluna `caso_id` (que a mesma seção exige ler pelos conjuntos
-- de acesso). Não há conflito com a RLS por mandato: não há mandato nesta linha. LIMITE DITO: o cabeçalho de um arquivo é
-- texto livre do cliente; um ERP sob medida pode nomear coluna com o nome de uma pessoa ou de um produto. Isso é visível
-- a qualquer papel que leia a tabela. O dono aceitou "cabeçalho não é dado do cliente"; se o primeiro arquivo real (DM7)
-- mostrar cabeçalho sensível, a saída é restringir a leitura de `cabecalho` a quem esteve no mandato, e é uma migration.
--
-- O QUE A MIGRATION INSTALA
--   * `mapeamento_de_colunas`: tipo_base, impressao, cabecalho (jsonb, como o arquivo traz), mapa (campo -> índice 0-based DO
--     CABEÇALHO ORIGINAL), formato (decimal e datas), confirmado_por (auth.uid(), sem FK: o autor sobrevive ao usuário),
--     confirmado_em, substituido_em/substituido_por. Índice ÚNICO PARCIAL (tipo_base, impressao) where substituido_em is null:
--     no máximo UMA vigente por par, garantido pelo banco, não pela função.
--   * `fn_impressao_do_cabecalho(jsonb)`: a impressão é calculada AQUI, nunca aceita do navegador, com a MESMA normalização de
--     `cabecalhoNormalizado` + `impressaoDoCabecalho` da biblioteca: cada célula em NFC, sequências de [espaço, \t, \n, \r, U+00A0]
--     colapsadas em um espaço, pontas aparadas desses mesmos caracteres, células vazias do FIM removidas, junção por U+001F,
--     sha256 hex do UTF-8. SEM minúsculas (o `lower()` depende do LC_CTYPE) e sem `\s` nem `[[:space:]]` (dependem de locale);
--     os cinco caracteres entram por chr(), não por classe. Vetores do teste calculados pela biblioteca JS (medido em 11/11/2026).
--   * `fn_mapeamento_erros(mapa, cabecalho, formato)`: o validador, UM só, usado pela função de confirmar (que recusa com o
--     motivo) e pela CHECK da tabela (que cobre quem escrever como service_role). Espelha `validarMapeamento` + os 11 `CAMPOS`
--     de Leitor/lib/mapeamento.mjs: se um campo mudar lá, muda aqui (LIMITE: a cópia é manual; nenhum portão compara as duas listas).
--   * `fn_mapeamento_confirmar(tipo_base, cabecalho, mapa, formato)`: security definer; só Sócio e Analista (fn_meu_papel, o
--     mecanismo da 0216); anônimo e conexão de serviço recusados (sem auth.uid() não há papel). Nova confirmação do mesmo par NÃO apaga a
--     anterior: marca-a substituída (substituido_em/substituido_por) e a nova vira a vigente, sob advisory lock do par. Grava
--     `mapeamento_confirmado` em evento_auditoria (entidade_ref `mapeamento_de_colunas:<id>`; sem mandato, só o Sócio lê a trilha, como `membro:`).
--   * `fn_mapeamento_vigente(tipo_base, cabecalho)`: invoker (a RLS vale), devolve a vigente no formato do `confirmado` do aplicador,
--     ou NULL (nunca confirmado: ausência declarada, não erro). Sem papel e sem ser conexão de serviço é recusado, para "sem papel"
--     não se confundir com "ninguém confirmou" (regra 1).
--
-- O FORMATO (acréscimo do coordenador, mesma fatia). "1.250" é mil duzentos e cinquenta ou um e vinte e cinco, e "03/04/2025" é
-- 3 de abril ou 4 de março: não se decide por valor, só por arquivo. O mapeamento guarda `formato` = {"decimal": "virgula"|"ponto",
-- "datas": "dia_mes_ano"|"mes_dia_ano"}, exatamente duas chaves, SEM default: quem confirma diz os dois.
--
-- GRANT (convenção da 0214): authenticated só SELECT na tabela (escrita direta não tem grant NEM policy: 42501 antes de a RLS
-- ser avaliada); service_role as quatro operações. Funções: revoke de public/anon, execute para authenticated e service_role.
--
-- A SONDA (10 requisitos desta migration, ordem 1300-1310 sem a 1306): tabela, as 4 funções, o corpo da confirmação (papel), o corpo da
-- impressão (NFC), a policy de leitura, e duas views `comportamento` para o que nenhum outro tipo enxerga: o índice único parcial
-- e a CHECK do formato/impressão (sem elas "no máximo uma vigente" e "formato fechado" voltam a ser promessa).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/o_mapeamento_de_colunas_que_cada_arquivo_redescobria.test.sql — 78 asserts
-- (medido: 78 chamadas, 78 execuções, nenhum em laço). Cada guarda desligada UMA por vez, migration reaplicada sobre o banco e conferida como APLICADA, teste rodado inteiro
-- com o assert em `raise warning` (voltou para `raise exception`; log inteiro lido atrás de FALHOU): ver a tabela abaixo.
-- Controle (migration intacta): 0 dos 78 asserts reprovam. Por guarda desligada, UMA por vez (11/11/2026):
--   * obrigatório faltando (`if not (p_mapa ? k)`): 6 (contraparte, vencimento, saldo, "nenhuma recusa gravou", a CHECK pelo service_role, "recusada não deixa evento");
--   * índice fora do cabeçalho (`>= v_n`): 2 · índice não inteiro/negativo/em texto (a regex): 4 · coluna repetida: 2 · campo desconhecido: 1 · cabeçalho vazio: 2 · tipo_base fora da lista (a função; a CHECK da tabela pega com outro erro): 1;
--   * Leitura e sem papel recusados (o `if v_papel is null or ...`): 7 · o anônimo NÃO tem guarda própria: `fn_meu_papel()` é NULL sem auth.uid(), e o `if v_uid is null` que a 1ª versão tinha, desligado, não reprovava NENHUM assert de comportamento (código morto: removido);
--   * impressão: com `lower()`: 5 · sem NBSP (U+00A0) no colapso e nas pontas: 1 · sem NFC: 4 · células vazias do fim mantidas: 3 · colapso de espaços internos desligado: 2;
--   * uma vigente: sem o índice único (vira índice comum): 2 · a função deixa de marcar a anterior: 7 · sem o índice E sem a marcação: 8 · a função APAGA a anterior em vez de marcar: 2 · a FK `substituido_por` sem DEFERRABLE (o defeito que a 1ª versão tinha: 23503 na 2ª confirmação do par): 7;
--   * formato: o bloco inteiro desligado: 10 · chave a mais aceita: 2 · valor fora da lista aceito: 4 · chave faltando aceita: 2;
--   * escrita direta (grant de insert/update/delete + policy `for all using (true)` ao authenticated): 5 · policy de leitura `using (true)`: 1 · leitura de `fn_mapeamento_vigente` sem a guarda de papel: 2;
--   * as duas CHECKs da tabela removidas (service_role): 4 · sem o evento em evento_auditoria: 4 · autor inventado em vez de auth.uid(): 3 · `grant execute ... to anon`: 3 · requisito da sonda apontando para objeto ausente: 1.
-- Em TODAS as 31 variantes a migration APLICOU (nenhum erro na aplicação) e o teste rodou inteiro (78 execuções). Dois defeitos reais foram achados pelo próprio teste ao escrevê-lo: a FK sem DEFERRABLE e o
-- `array || 'texto'` literal (22P02) no validador; e um do HARNESS, não da migration: o plpgsql guarda o plano de uma expressão simples na transação e não reconfere o EXECUTE depois de `set role` (a 3ª chamada como anon passava; o helper usa SQL dinâmico).
-- Sem a sabotagem do advisory lock (a corrida de duas confirmações simultâneas não é exercitável num teste de uma sessão): LIMITE DITO; o índice único parcial é a rede (a perdedora leva 23505, não grava duas vigentes).
-- =============================================================================
begin;

-- ---------------------------------------------------------------------------
-- 1. A IMPRESSÃO DO CABEÇALHO
-- ---------------------------------------------------------------------------
create function fn_impressao_do_cabecalho(p_cabecalho jsonb) returns text
language sql immutable set search_path = public, pg_temp as $$
  with celulas as (
    select e.ord,
           btrim(regexp_replace(normalize(coalesce(e.v #>> '{}', ''), NFC),
                                '[ ' || chr(9) || chr(10) || chr(13) || chr(160) || ']+', ' ', 'g'),
                 ' ' || chr(9) || chr(10) || chr(13) || chr(160)) as c
      from jsonb_array_elements(p_cabecalho) with ordinality as e(v, ord)),
  ultima as (select max(ord) as n from celulas where c <> '')
  select encode(sha256(convert_to(coalesce((select string_agg(c, chr(31) order by ord) from celulas, ultima where ord <= ultima.n), ''), 'UTF8')), 'hex')
$$;

comment on function fn_impressao_do_cabecalho(jsonb) is
  '0272: a impressão digital do cabeçalho (sha256 hex), a MESMA de impressaoDoCabecalho em Leitor/lib/mapeamento.mjs: cada célula em NFC, [espaço \t \n \r U+00A0] colapsados em um espaço e aparados nas pontas, células vazias do FIM fora, junção por U+001F, SEM minúsculas (lower() depende do LC_CTYPE). Calculada aqui, nunca aceita do navegador.';

-- ---------------------------------------------------------------------------
-- 2. O VALIDADOR — um só (a função de confirmar e a CHECK da tabela)
-- ---------------------------------------------------------------------------
create function fn_mapeamento_erros(p_mapa jsonb, p_cabecalho jsonb, p_formato jsonb) returns text[]
language plpgsql immutable set search_path = public, pg_temp as $$
declare
  v_erros  text[] := '{}';
  v_n      int;
  k        text;
  v        jsonb;
  v_usadas jsonb := '{}';
  v_efeito text;
begin
  if p_cabecalho is null or jsonb_typeof(p_cabecalho) <> 'array' then
    return array['o cabeçalho tem de ser uma lista de textos (as células do cabeçalho como o arquivo traz)'];
  end if;
  if exists (select 1 from jsonb_array_elements(p_cabecalho) e where jsonb_typeof(e) not in ('string', 'null')) then
    return array['o cabeçalho tem de ser uma lista de textos: há célula que não é texto'];
  end if;
  v_n := jsonb_array_length(p_cabecalho);
  if v_n = 0 or not exists (select 1 from jsonb_array_elements(p_cabecalho) e where btrim(coalesce(e #>> '{}', ''), ' ' || chr(9) || chr(10) || chr(13) || chr(160)) <> '') then
    return array['o cabeçalho está vazio: sem nome de coluna não há impressão para reaproveitar o mapeamento'];
  end if;

  if p_mapa is null or jsonb_typeof(p_mapa) <> 'object' then
    return array['o mapa tem de ser um objeto campo -> índice da coluna'];
  end if;
  for k, v in select key, value from jsonb_each(p_mapa) order by key loop
    if not (k = any (array['contraparte', 'documento_contraparte', 'titulo', 'parcela', 'emissao', 'vencimento',
                           'valor_original', 'valor_pago', 'saldo', 'data_pagamento', 'situacao'])) then
      v_erros := v_erros || format('campo desconhecido: %s', k);
      continue;
    end if;
    if jsonb_typeof(v) <> 'number' or v::text !~ '^[0-9]{1,6}$' then
      v_erros := v_erros || format('%s: o índice da coluna tem de ser um inteiro a partir de 0 (veio %s)', k, v::text);
      continue;
    end if;
    if v::text::int >= v_n then
      v_erros := v_erros || format('%s: coluna %s fora do cabeçalho (%s colunas)', k, v::text, v_n);
      continue;
    end if;
    if v_usadas ? v::text then
      v_erros := v_erros || format('a coluna "%s" está em %s e em %s', p_cabecalho ->> (v::text::int), v_usadas ->> v::text, k);
    else
      v_usadas := v_usadas || jsonb_build_object(v::text, k);
    end if;
  end loop;
  for k, v_efeito in select * from (values ('contraparte', 'sem contraparte não há aging por cliente ou fornecedor nem concentração'),
                                            ('vencimento', 'sem vencimento o aging não pode ser calculado'),
                                            ('saldo', 'sem saldo não há aging nem conciliação com o balanço')) as o(campo, efeito) loop
    if not (p_mapa ? k) then
      v_erros := v_erros || format('falta o campo obrigatório %s: %s', k, v_efeito);
    end if;
  end loop;

  if p_formato is null or jsonb_typeof(p_formato) <> 'object' then
    v_erros := v_erros || 'o formato tem de ser um objeto com exatamente as chaves decimal e datas (quem confirma diz os dois)'::text;
  else
    for k in select key from jsonb_each(p_formato) where key not in ('decimal', 'datas') order by key loop
      v_erros := v_erros || format('formato: chave desconhecida "%s" (só decimal e datas)', k);
    end loop;
    if not (p_formato ? 'decimal') then
      v_erros := v_erros || 'formato: falta a chave decimal (virgula ou ponto): "1.250" é mil duzentos e cinquenta ou um e vinte e cinco, e só o arquivo diz'::text;
    elsif p_formato -> 'decimal' is distinct from to_jsonb('virgula'::text) and p_formato -> 'decimal' is distinct from to_jsonb('ponto'::text) then
      v_erros := v_erros || format('formato.decimal: %s não está na lista (virgula, ponto)', (p_formato -> 'decimal')::text);
    end if;
    if not (p_formato ? 'datas') then
      v_erros := v_erros || 'formato: falta a chave datas (dia_mes_ano ou mes_dia_ano): "03/04/2025" é 3 de abril ou 4 de março, e só o arquivo diz'::text;
    elsif p_formato -> 'datas' is distinct from to_jsonb('dia_mes_ano'::text) and p_formato -> 'datas' is distinct from to_jsonb('mes_dia_ano'::text) then
      v_erros := v_erros || format('formato.datas: %s não está na lista (dia_mes_ano, mes_dia_ano)', (p_formato -> 'datas')::text);
    end if;
  end if;
  return v_erros;
end $$;

comment on function fn_mapeamento_erros(jsonb, jsonb, jsonb) is
  '0272: os motivos pelos quais um mapeamento NÃO é aplicável (lista vazia = válido). Espelha validarMapeamento e os 11 CAMPOS de Leitor/lib/mapeamento.mjs (índice contra o cabeçalho ORIGINAL; obrigatórios contraparte, vencimento, saldo; coluna em um só campo) e fecha o formato (decimal, datas). Usada pela confirmação e pela CHECK da tabela.';

-- ---------------------------------------------------------------------------
-- 3. A TABELA
-- ---------------------------------------------------------------------------
create table mapeamento_de_colunas (
  id               uuid primary key default gen_random_uuid(),
  tipo_base        text not null check (tipo_base in ('contas_a_receber', 'contas_a_pagar')),
  impressao        text not null check (impressao ~ '^[0-9a-f]{64}$'),
  cabecalho        jsonb not null,
  mapa             jsonb not null,
  formato          jsonb not null,
  confirmado_por   uuid not null,
  confirmado_em    timestamptz not null default now(),
  substituido_em   timestamptz,
  -- DEFERRABLE INITIALLY DEFERRED de propósito: a confirmação marca a anterior (substituido_por = id da nova) ANTES de inserir a nova, porque o
  -- índice único parcial não admite as duas vigentes ao mesmo tempo; sem o adiamento a FK recusa a 2ª confirmação do mesmo par (medido: 23503 na primeira versão).
  substituido_por  uuid references mapeamento_de_colunas(id) deferrable initially deferred,
  constraint mapeamento_valido check (fn_mapeamento_erros(mapa, cabecalho, formato) = '{}'::text[]),
  constraint mapeamento_impressao_do_banco check (impressao = fn_impressao_do_cabecalho(cabecalho)),
  constraint mapeamento_substituicao_inteira check ((substituido_em is null) = (substituido_por is null))
);
comment on constraint mapeamento_valido on mapeamento_de_colunas is
  '0272: o mesmo validador da confirmação (fn_mapeamento_erros), para quem escrever sem passar pela função (service_role): obrigatório faltando, índice fora, coluna repetida e formato fora da lista não entram.';
comment on constraint mapeamento_impressao_do_banco on mapeamento_de_colunas is
  '0272: a impressão é sempre a do cabeçalho gravado, calculada pelo banco; nem o service_role grava uma impressão que o cabeçalho não produz.';

-- No máximo UMA vigente por (tipo_base, impressao).
create unique index mapeamento_de_colunas_uma_vigente on mapeamento_de_colunas (tipo_base, impressao) where substituido_em is null;

comment on table mapeamento_de_colunas is
  '0272: o mapeamento de colunas CONFIRMADO por um analista para um arquivo de contas a receber/a pagar, pela impressão digital do cabeçalho, reaproveitado no próximo arquivo do mesmo ERP em qualquer mandato. NÃO é por mandato: guarda o nome das colunas, não dado do cliente. Escrita só por fn_mapeamento_confirmar; uma confirmação nova marca a anterior como substituída (substituido_em) e a nova vira a vigente.';
comment on column mapeamento_de_colunas.mapa is
  'campo -> índice 0-based da coluna NO CABEÇALHO ORIGINAL (a coluna `cabecalho`), não no normalizado.';
comment on column mapeamento_de_colunas.formato is
  '{"decimal": "virgula"|"ponto", "datas": "dia_mes_ano"|"mes_dia_ano"}: "1.250" e "03/04/2025" não se decidem por valor, só por arquivo. Sem default: quem confirma diz os dois.';
comment on column mapeamento_de_colunas.confirmado_por is
  'auth.uid() de quem confirmou. Sem FK de propósito: a autoria sobrevive à saída do usuário.';

alter table mapeamento_de_colunas enable row level security;
create policy mapeamento_de_colunas_read on mapeamento_de_colunas for select to authenticated using ((select fn_tem_papel()));
-- Sem policy de insert/update/delete: a escrita é a função (security definer).

-- GRANT (0214): authenticated só lê; service_role as quatro operações.
grant select on mapeamento_de_colunas to authenticated;
grant select, insert, update, delete on mapeamento_de_colunas to service_role;

-- ---------------------------------------------------------------------------
-- 4. CONFIRMAR E LER
-- ---------------------------------------------------------------------------
create function fn_mapeamento_confirmar(p_tipo_base text, p_cabecalho jsonb, p_mapa jsonb, p_formato jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid       uuid := auth.uid();
  v_papel     text;
  v_erros     text[];
  v_impressao text;
  v_id        uuid := gen_random_uuid();
  v_antigo    uuid;
begin
  -- Anônimo (JWT sem sub), conexão de serviço e quem não tem papel caem TODOS aqui: sem auth.uid() não há linha em `membro`, e fn_meu_papel() é NULL. Um
  -- `if v_uid is null` à parte seria código morto (medido: desligado, nenhum assert comportamental reprova), por isso não existe; o autor gravado é o v_uid.
  v_papel := fn_meu_papel();
  if v_papel is null or v_papel not in ('socio', 'analista') then
    raise exception 'Confirmar o mapeamento de colunas é reservado a Sócio e Analista (seu papel: %)', coalesce(v_papel, 'nenhum') using errcode = '42501';
  end if;
  if p_tipo_base is null or p_tipo_base not in ('contas_a_receber', 'contas_a_pagar') then
    raise exception 'tipo_base "%" não existe (contas_a_receber ou contas_a_pagar)', p_tipo_base using errcode = '22023';
  end if;
  v_erros := fn_mapeamento_erros(p_mapa, p_cabecalho, p_formato);
  if cardinality(v_erros) > 0 then
    raise exception 'Mapeamento recusado: %', array_to_string(v_erros, '; ') using errcode = '22023';
  end if;

  v_impressao := fn_impressao_do_cabecalho(p_cabecalho);
  perform pg_advisory_xact_lock(hashtextextended(p_tipo_base || ':' || v_impressao, 0));
  update mapeamento_de_colunas set substituido_em = now(), substituido_por = v_id
   where tipo_base = p_tipo_base and impressao = v_impressao and substituido_em is null
  returning id into v_antigo;
  insert into mapeamento_de_colunas (id, tipo_base, impressao, cabecalho, mapa, formato, confirmado_por)
  values (v_id, p_tipo_base, v_impressao, p_cabecalho, p_mapa, p_formato, v_uid);

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
  values ('usuario:' || v_uid, 'mapeamento_confirmado', 'mapeamento_de_colunas:' || v_id,
          case when v_antigo is null then null else jsonb_build_object('substituido', v_antigo) end,
          jsonb_build_object('tipo_base', p_tipo_base, 'impressao', v_impressao, 'mapa', p_mapa, 'formato', p_formato));
  return jsonb_build_object('id', v_id, 'impressao', v_impressao, 'substitui', v_antigo);
end $$;

comment on function fn_mapeamento_confirmar(text, jsonb, jsonb, jsonb) is
  '0272: o analista confirma o mapeamento de colunas de um arquivo de contas a receber/a pagar. Só Sócio e Analista (fn_meu_papel, 0216); anônimo e conexão de serviço recusados. Valida (fn_mapeamento_erros) e recusa com o motivo; calcula a impressão do cabeçalho no banco; marca a vigente anterior do mesmo par como substituída; grava mapeamento_confirmado em evento_auditoria. Devolve {id, impressao, substitui}.';

create function fn_mapeamento_vigente(p_tipo_base text, p_cabecalho jsonb) returns jsonb
language plpgsql stable set search_path = public, pg_temp as $$
declare v_r jsonb;
begin
  if not (fn_conexao_de_servico() or fn_tem_papel()) then
    raise exception 'Ler o mapeamento de colunas exige um papel (Sócio, Analista ou Leitura)' using errcode = '42501';
  end if;
  if p_tipo_base is null or p_tipo_base not in ('contas_a_receber', 'contas_a_pagar') then
    raise exception 'tipo_base "%" não existe (contas_a_receber ou contas_a_pagar)', p_tipo_base using errcode = '22023';
  end if;
  if p_cabecalho is null or jsonb_typeof(p_cabecalho) <> 'array' then
    raise exception 'o cabeçalho tem de ser uma lista de textos' using errcode = '22023';
  end if;
  select jsonb_build_object('id', m.id, 'tipo_base', m.tipo_base, 'impressao', m.impressao, 'cabecalho', m.cabecalho, 'mapa', m.mapa,
                            'formato', m.formato, 'confirmado_por', m.confirmado_por, 'confirmado_em', m.confirmado_em)
    into v_r
    from mapeamento_de_colunas m
   where m.tipo_base = p_tipo_base and m.impressao = fn_impressao_do_cabecalho(p_cabecalho) and m.substituido_em is null;
  return v_r;   -- NULL = ninguém confirmou este cabeçalho (ausência declarada, não erro): o arquivo não vira dado até confirmar
end $$;

comment on function fn_mapeamento_vigente(text, jsonb) is
  '0272: o mapeamento vigente (a confirmação mais nova) para o tipo_base e o cabeçalho, no formato do `confirmado` de aplicadorDeMapeamento + o `formato`; NULL se ninguém confirmou. Invoker: a RLS vale; sem papel é recusado (para não parecer "ninguém confirmou").';

do $$
declare f text;
begin
  foreach f in array array['fn_impressao_do_cabecalho(jsonb)', 'fn_mapeamento_erros(jsonb, jsonb, jsonb)',
                           'fn_mapeamento_confirmar(text, jsonb, jsonb, jsonb)', 'fn_mapeamento_vigente(text, jsonb)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
    if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
      execute format('grant execute on function %s to supabase_read_only_user', f);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 5. A SONDA. Marcadores em CÓDIGO, nunca de comentário (pg_get_functiondef traz os comentários do corpo).
-- ---------------------------------------------------------------------------
create view instalacao_sonda_mapeamento_uma_vigente as
  select i.indexrelid::regclass::text as indice
    from pg_index i
    join pg_class c on c.oid = i.indexrelid and c.relname = 'mapeamento_de_colunas_uma_vigente'
   where i.indrelid = 'public.mapeamento_de_colunas'::regclass
     and i.indisunique and i.indisvalid
     and i.indpred is not null
     and pg_get_indexdef(i.indexrelid) like '%(tipo_base, impressao)%'
     and pg_get_expr(i.indpred, i.indrelid) like '%substituido_em IS NULL%';
comment on view instalacao_sonda_mapeamento_uma_vigente is
  'Sonda da 0272: uma linha = o índice único parcial (tipo_base, impressao) where substituido_em is null existe e é válido. Zero linhas: o banco deixou de garantir uma só confirmação vigente por cabeçalho.';
grant select on instalacao_sonda_mapeamento_uma_vigente to authenticated, service_role;

create view instalacao_sonda_mapeamento_checks as
  select count(*)::text as n
    from pg_constraint k
   where k.conrelid = 'public.mapeamento_de_colunas'::regclass and k.contype = 'c' and k.convalidated
     and ((k.conname = 'mapeamento_valido' and pg_get_constraintdef(k.oid) like '%fn_mapeamento_erros(%')
       or (k.conname = 'mapeamento_impressao_do_banco' and pg_get_constraintdef(k.oid) like '%fn_impressao_do_cabecalho(%'))
  having count(*) = 2;
comment on view instalacao_sonda_mapeamento_checks is
  'Sonda da 0272: uma linha = as duas CHECKs (validador e impressão do banco) existem, validadas, chamando as funções certas. Zero linhas: quem escreve como service_role grava mapeamento inválido ou impressão que o cabeçalho não produz.';
grant select on instalacao_sonda_mapeamento_checks to authenticated, service_role;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('mapeamento_tabela', '0272', 'tabela', 'mapeamento_de_colunas', null, null,
   'Onde o mapeamento de colunas confirmado pelo analista é guardado. Ausente = a 0272 não foi aplicada: cada arquivo de contas a receber/a pagar obriga a confirmar as colunas de novo, e "arquivo sem mapeamento confirmado não vira dado" não tem onde se apoiar.',
   'importante', 1300),
  ('mapeamento_confirmar_funcao', '0272', 'funcao', 'fn_mapeamento_confirmar', null, null,
   'A única porta de escrita do mapeamento (o authenticated não tem grant nem policy de escrita na tabela). Ausente = ninguém consegue confirmar.',
   'importante', 1301),
  ('mapeamento_vigente_funcao', '0272', 'funcao', 'fn_mapeamento_vigente', null, null,
   'A leitura do mapeamento vigente por tipo_base e cabeçalho. Ausente = o mapeamento confirmado não é reaproveitado no próximo arquivo do mesmo ERP.',
   'importante', 1302),
  ('mapeamento_validador_funcao', '0272', 'funcao', 'fn_mapeamento_erros', null, null,
   'O validador único (confirmação e CHECK da tabela). Ausente = a tabela ou a confirmação não existe em estado completo.',
   'importante', 1303),
  ('mapeamento_impressao_funcao', '0272', 'funcao', 'fn_impressao_do_cabecalho', null, null,
   'A impressão do cabeçalho calculada pelo banco. Ausente = a tabela não tem como casar o cabeçalho de um arquivo novo com o confirmado.',
   'importante', 1304),
  ('mapeamento_confirmar_papel_e_autor', '0272', 'corpo', 'fn_mapeamento_confirmar', 'v_papel not in (''socio'', ''analista'')', null,
   'Só Sócio e Analista confirmam (o anônimo e a conexão de serviço não têm papel). Corpo sem isto = a Leitura, o authenticated sem papel e o anônimo confirmam o mapeamento que decide o que vira dado no aging.',
   'bloqueante', 1305),
  ('mapeamento_impressao_nfc', '0272', 'corpo', 'fn_impressao_do_cabecalho', ', NFC)', null,
   'A impressão normaliza em NFC, como a biblioteca. Corpo sem isto = o MESMO cabeçalho com "Ação" decomposta (NFD) tem outra impressão e o mapeamento confirmado não é reaproveitado.',
   'importante', 1307),
  ('mapeamento_leitura_policy', '0272', 'policy', 'mapeamento_de_colunas.mapeamento_de_colunas_read', null, null,
   'RLS ligada sem policy de leitura devolve zero calado: o mapeamento confirmado pareceria nunca ter existido.',
   'importante', 1308),
  ('mapeamento_uma_vigente', '0272', 'comportamento', 'instalacao_sonda_mapeamento_uma_vigente', null, 1,
   'O índice único parcial que garante UMA vigente por (tipo_base, impressao). Zero linhas = duas confirmações vigentes do mesmo cabeçalho e a leitura devolve uma delas ao acaso.',
   'importante', 1309),
  ('mapeamento_checks', '0272', 'comportamento', 'instalacao_sonda_mapeamento_checks', null, 1,
   'As CHECKs da tabela (validador e impressão do banco). Zero linhas = o service_role grava mapeamento com índice fora, coluna repetida, formato fora da lista ou impressão alheia ao cabeçalho.',
   'importante', 1310)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0272', revisado_em = current_date,
       observacao = 'A 0272 cria mapeamento_de_colunas (o mapeamento de colunas confirmado, global, por impressão do cabeçalho), fn_mapeamento_confirmar, fn_mapeamento_vigente, fn_mapeamento_erros e fn_impressao_do_cabecalho. 10 requisitos novos (ordem 1300-1310, sem a 1306).'
 where id = true;

commit;
