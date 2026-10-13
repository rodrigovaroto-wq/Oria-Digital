-- =============================================================================
-- 0207 — O RESUMO DO ARQUIVO OFICIAL, ENVIADO EM PARTES E RECONFERIDO PELO SERVIDOR
-- (Espec. 12, F2T etapa 1, decisão do dono de 13/10/2026: o SPED é lido no NAVEGADOR do analista
--  e só o RESUMO vai ao banco, no lugar do arquivo. Só ACRESCENTA: a 0206 não é tocada.)
--
-- O QUE ESTA MIGRATION É. `Leitor/lib` (no navegador) devolve `{envelope, resumo}`. O envelope vai para
-- `fn_registrar_arquivo_oficial` (0206); o resumo da ECD é a íntegra dos blocos pequenos (plano de contas,
-- saldos I155, demonstrações J) mais o I250 somado por (conta, mês, IND_LCTO), e o da ECF só a íntegra
-- dos blocos de cálculo. Aqui ele ganha onde morar: `arquivo_oficial_registro` (linha a linha, com o número
-- da linha do arquivo como proveniência) e `arquivo_oficial_lancamento_mes` (os grupos).
--
-- POR QUE EM PARTES. Medido na ECD de 10M de linhas: o resumo tem 4,7 MB (26 mil linhas na íntegra e 18 mil
-- grupos), e com 10 mil contas só o I155 passa de 120 mil linhas. Um corpo de RPC de 15 MB não é aposta que
-- se faça, e o `statement_timeout` do papel `authenticated` no Supabase é de 8 s. Por isso são TRÊS funções:
-- `fn_resumo_iniciar` (registra o envelope, declara os totais, abre a carga), `fn_resumo_anexar` (uma parte
-- de até 10.000 itens, ~5.000 é o combinado) e `fn_resumo_concluir` (a reconferência do SERVIDOR).
--
-- POR QUE O SERVIDOR RECONFERE (fronteira de confiança). Tudo veio do navegador. `concluir` NÃO acredita no
-- que o cliente disse: confere a coerência interna do que ficou gravado. (a) registros e grupos gravados =
-- os totais declarados no `iniciar` (uma parte perdida na rede, ou repetida, não passa); (b) cada linha cai
-- entre 1 e `controle_lido` do envelope (linha fora do arquivo é fabricada); (c) o registro de cada linha,
-- contado por tipo, = `detalhe.por_registro` do envelope, que o leitor já conferiu contra o 9900 do próprio
-- arquivo, para TODO tipo que aparece no resumo; (d) na ECD, a soma de `partidas` dos grupos = o I250 do
-- envelope (é o que prova que nenhuma partida sumiu ou foi inventada na soma por conta e mês).
-- Qualquer falha: `resumo_status = 'recusado'` com TODOS os motivos, e as linhas são APAGADAS. Resumo parcial
-- ou incoerente não fica no banco com a aparência do arquivo (regra 7); o envelope continua `lido`, e o
-- analista reenvia. Passou: `completo`.
--
-- O QUE `concluir` NÃO FAZ, e não finge. Não sabe QUAIS tipos o leitor guarda (essa lista é do
-- `resumo.mjs`, marcada [A CONFIRMAR] até o aceite das 3 ECDs reais): um cliente que omitisse TODAS as
-- linhas de um tipo, declarando os totais menores, passaria em (a)-(c) porque (c) só olha os tipos que
-- aparecem. Copiar a lista aqui criaria duas listas que divergem sem erro. O teto é: o cliente é o
-- navegador do próprio analista, e a falha que se barra aqui é a de transporte e de leitor com defeito,
-- não a de analista malicioso. Quando o aceite fechar a lista, ela sobe para cá.
--
-- A ARITMÉTICA DO I155 É ACHADO, NÃO DEFEITO DE CARGA. Com D positivo e C negativo, `saldo_ini + débito -
-- crédito = saldo_fin` por (conta, centro de custo). Um balancete que não fecha é informação sobre o
-- CLIENTE (e é, em si, um indício de escrituração com problema), não prova de que a carga falhou; então
-- `concluir` conta, guarda uma amostra de até 20 linhas em `resumo_conferencia->'i155'` e NÃO recusa. I155
-- com valor ilegível ou IND_DC fora de D/C é contado à parte (`ilegiveis`): não é "fecha" nem "não fecha",
-- é "não deu para conferir" (regra 1). A conta é feita em `numeric` sobre o texto com vírgula decimal, sem
-- converter para centavos, para não haver arredondamento.
--
-- DECISÕES.
--  * `mes` é `date` (1º dia do mês) e NULL é DADO: partida sem I200 antes dela, ou com data inválida,
--    é somada e contada no grupo de mês null, e a marca é o próprio null (o `lancamentos_por_conta_mes`
--    do leitor já faz assim). NULLS NOT DISTINCT na unicidade, senão dois grupos null repetiriam.
--  * `reenvio`: mesmo arquivo com resumo `completo` na MESMA versão do resumo não recarrega nada. Vale
--    inclusive se o cabeçalho novo vier `ausente`: um resumo bom não é derrubado por uma leitura pior.
--  * `ausente`: o cabeçalho diz que não há resumo (família sem resumo definido, ou o leitor recusou o
--    resumo), ou o arquivo registrado NÃO ficou `lido`. Grava o motivo e apaga linhas de carga anterior.
--  * Recarga (resumo de outra versão, ou carga que ficou `em_carga`/`recusado`) apaga as linhas anteriores
--    do MESMO arquivo e recomeça.
--  * `concluir` repetido é idempotente: devolve o estado já gravado. Um reenvio do navegador depois de
--    uma resposta perdida não vira erro.
--  * SECURITY INVOKER, o padrão do repositório (nenhuma função daqui é `security definer`; as chamadas
--    pelo portal têm `grant execute ... to authenticated`, como `fn_aceitar_extracao`, 0011). Consequência
--    medida no teste: como o invoker roda com os direitos de quem chama, a recarga e a recusa só apagam
--    se o `authenticated` puder DELETE nas duas tabelas filhas. Por isso, e DIFERENTE do `arquivo_oficial`
--    (0206, evidência, sem delete), as duas tabelas novas concedem delete: são derivadas, regeneráveis do
--    arquivo (o hash prova que é o mesmo) e apagar é a própria operação de recarga e de recusa. O
--    envelope continua sem delete.
--  * Teto de itens por parte: 10.000. O combinado é ~5.000; o dobro é folga, e mais que isso volta com
--    erro claro em vez de estourar os 8 s do `authenticated`. Sobe-se por migration.
--
-- ESCALA do `concluir` (única chamada que não se parte): medido em 13/10/2026 com 120.000 I155 carregados em 24
-- partes de 5.000, 1,6 s no banco local, contra os 8 s do `authenticated`. Margem de ~5x; acima de ~500 mil I155
-- (um plano de contas de ~40 mil contas) o `concluir` precisaria ser partido também.
--
-- NÃO HÁ BACKFILL: tabelas novas, colunas novas nulas (null = nunca tentado). Produção não é tocada.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/resumo_oficial.test.sql — 58 asserts, medidos em 13/10/2026 com o
-- assert em `raise notice` (voltou para `raise exception` depois). Cada conferência desligada num clone do
-- banco, uma por vez, e antes de cada número conferi que a mutação APLICOU e que o teste rodou: o total de
-- registros declarado (3 dos 58 asserts reprovam), o total de grupos declarado (2 dos 58), a linha dentro de
-- 1..controle_lido (2 dos 58), a contagem por registro contra o envelope (2 dos 58), a soma de partidas contra
-- o I250 (2 dos 58), o grupo de lançamento em arquivo que não é ECD (1 dos 58), a recusa que apaga as linhas
-- (2 dos 58), a contagem do I155 que não fecha (2 dos 58), o reenvio da mesma versão (2 dos 58), a carga
-- anterior apagada no ausente (1 dos 58), o arquivo não lido virar resumo ausente (1 dos 58), o hash do
-- cabeçalho contra o do envelope (2 dos 58), o teto de itens por parte (1 dos 58), o formato [linha, texto]
-- (1 dos 58), os totais obrigatórios no cabeçalho (1 dos 58), o mês null gravado como null (1 dos 58),
-- "nulls not distinct" desfeito (2 dos 58), anexar só com em_carga (4 dos 58) e a recusa da trilha desligada
-- da 0206 (2 dos 58). QUATRO mutações ABORTAM o teste em vez de reprovar assert (aborto é reprovação, mas o
-- denominador não os conta): a recarga que não apaga (pk duplicada no 15o assert, depois de 1 reprovar), o
-- cabeçalho ausente ignorado (aborta no 27o), o concluir sem idempotência (aborta no 10o) e o revoke de delete
-- nas tabelas filhas (permission denied no 50o, no bloco do papel authenticated). Ressalva de medição: a
-- primeira mutação dos totais obrigatórios saía `false and A or B`, que não desliga nada (0 dos 58 reprovavam);
-- refeita desligando a condição inteira, reprova 1.
-- O fn_upsert_caso pelo navegador (bloco 15, 5 asserts acrescentados depois da medição acima, que eles não
-- alteram: não chamam as funções do resumo), medido com cada guarda desligada: sem o grant ao authenticated, o
-- teste ABORTA em "permission denied for function fn_upsert_caso"; sem a lista fechada de ator, reprova 1 dos
-- 58 (15-2); com o ator fixo 'sistema:n8n', reprova 1 dos 58 (15-3).
-- =============================================================================

alter table arquivo_oficial
  add column if not exists resumo_status text,
  add column if not exists resumo_versao text,
  add column if not exists resumo_motivo text,
  add column if not exists resumo_conferencia jsonb,
  add column if not exists resumo_descartado text,
  add column if not exists resumo_total_registros integer,
  add column if not exists resumo_total_grupos integer;

alter table arquivo_oficial drop constraint if exists arquivo_oficial_resumo_status_check;
alter table arquivo_oficial add constraint arquivo_oficial_resumo_status_check
  check (resumo_status in ('em_carga', 'completo', 'ausente', 'recusado'));

comment on column arquivo_oficial.resumo_status is
  'Estado do resumo enviado pelo navegador: em_carga (partes chegando), completo (o servidor reconferiu), ausente (não há resumo, e resumo_motivo diz por quê) ou recusado (incoerente, linhas apagadas). NULL = nunca tentado. 0207.';
comment on column arquivo_oficial.resumo_conferencia is
  'A conferência do leitor (i250_lidos, valores_invalidos, lançamentos desbalanceados...) mais a chave i155 que o SERVIDOR calcula no concluir: {total, nao_fecham, ilegiveis, amostra}. 0207.';
comment on column arquivo_oficial.resumo_descartado is
  'O que o resumo NÃO guarda, dito pelo próprio leitor (ex.: o lançamento individual I200/I250). 0207.';

create table if not exists arquivo_oficial_registro (
  arquivo_oficial_id uuid not null references arquivo_oficial(id) on delete cascade,
  linha              integer not null,
  registro           text not null,
  conteudo           text not null,
  primary key (arquivo_oficial_id, linha)
);
comment on table arquivo_oficial_registro is
  'Os registros guardados NA ÍNTEGRA do resumo de um arquivo oficial, com o número da linha do arquivo (proveniência). registro é o código (split_part(conteudo,''|'',2)). Só existe para resumo em_carga ou completo. 0207.';
create index if not exists arquivo_oficial_registro_tipo_idx on arquivo_oficial_registro (arquivo_oficial_id, registro);

create table if not exists arquivo_oficial_lancamento_mes (
  arquivo_oficial_id uuid not null references arquivo_oficial(id) on delete cascade,
  conta              text not null,
  mes                date,
  ind_lcto           text,
  debito             bigint not null,
  credito            bigint not null,
  partidas           integer not null,
  partidas_sem_valor integer not null,
  primeira_linha     integer,
  constraint arquivo_oficial_lancamento_mes_uk unique nulls not distinct (arquivo_oficial_id, conta, mes, ind_lcto)
);
comment on table arquivo_oficial_lancamento_mes is
  'O I250 da ECD somado por (conta, mês, IND_LCTO), em centavos. mes NULL = partida sem I200 antes ou com data inválida: é DADO, a marca do problema, e não erro. partidas_sem_valor > 0 = o grupo é incompleto. 0207.';
comment on column arquivo_oficial_lancamento_mes.mes is 'Primeiro dia do mês; NULL = partida sem I200 ou data inválida.';
create index if not exists arquivo_oficial_lancamento_mes_arq_idx on arquivo_oficial_lancamento_mes (arquivo_oficial_id);

alter table arquivo_oficial_registro enable row level security;
alter table arquivo_oficial_lancamento_mes enable row level security;
create policy arquivo_oficial_registro_authenticated_all on arquivo_oficial_registro
  for all to authenticated using (true) with check (true);
create policy arquivo_oficial_lancamento_mes_authenticated_all on arquivo_oficial_lancamento_mes
  for all to authenticated using (true) with check (true);
-- DELETE concedido de propósito (ver DECISÕES: as funções são invoker e recarga/recusa apagam).
grant select, insert, update, delete on arquivo_oficial_registro to authenticated;
grant select, insert, update, delete on arquivo_oficial_lancamento_mes to authenticated;


create or replace function fn_resumo_iniciar(p_caso uuid, p_documento uuid, p_envelope jsonb, p_cabecalho jsonb)
returns jsonb language plpgsql as $$
declare
  v_reg  jsonb;
  v_arq  arquivo_oficial;
  v_ver  text;
  v_totr integer;
  v_totg integer;
  v_motivo text;
begin
  if p_envelope is null or p_cabecalho is null then
    raise exception 'fn_resumo_iniciar: envelope e cabeçalho do resumo são obrigatórios';
  end if;
  -- Antes de gravar QUALQUER coisa: um resumo de outro arquivo não pode ser pendurado neste envelope.
  if p_cabecalho->>'hash_sha256' is distinct from p_envelope->>'hash_sha256' then
    raise exception 'fn_resumo_iniciar: o hash do resumo (%) não é o do envelope (%) — resumo de outro arquivo, recusado',
      p_cabecalho->>'hash_sha256', p_envelope->>'hash_sha256';
  end if;

  v_reg := fn_registrar_arquivo_oficial(p_caso, p_documento, p_envelope);   -- recusa a trilha desligada
  select * into v_arq from arquivo_oficial where id = (v_reg->>'id')::uuid for update;
  v_ver := coalesce(p_cabecalho->>'versao', '');
  if v_ver = '' then
    raise exception 'fn_resumo_iniciar: o cabeçalho não traz a versão do resumo';
  end if;

  if v_arq.resumo_status = 'completo' and v_arq.resumo_versao = v_ver then
    return v_reg || jsonb_build_object('resumo', 'reenvio');
  end if;

  if v_arq.status <> 'lido' or nullif(p_cabecalho->>'ausente', '') is not null then
    v_motivo := case when v_arq.status <> 'lido'
      then 'arquivo não lido por inteiro (' || v_arq.status || '): sem resumo, para que nada parcial seja tomado pelo arquivo'
           || coalesce(' — ' || nullif(p_cabecalho->>'ausente', ''), '')
      else p_cabecalho->>'ausente' end;
    delete from arquivo_oficial_registro where arquivo_oficial_id = v_arq.id;
    delete from arquivo_oficial_lancamento_mes where arquivo_oficial_id = v_arq.id;
    update arquivo_oficial set resumo_status = 'ausente', resumo_versao = v_ver, resumo_motivo = v_motivo,
           resumo_conferencia = p_cabecalho->'conferencia', resumo_descartado = p_cabecalho->>'descartado',
           resumo_total_registros = null, resumo_total_grupos = null
     where id = v_arq.id;
    return v_reg || jsonb_build_object('resumo', 'ausente', 'motivo', v_motivo);
  end if;

  if coalesce(p_cabecalho->>'total_registros', '') !~ '^[0-9]+$' or coalesce(p_cabecalho->>'total_grupos', '') !~ '^[0-9]+$' then
    raise exception 'fn_resumo_iniciar: o cabeçalho não declara total_registros e total_grupos (inteiros >= 0); sem eles o servidor não tem contra o que conferir';
  end if;
  v_totr := (p_cabecalho->>'total_registros')::integer;
  v_totg := (p_cabecalho->>'total_grupos')::integer;

  delete from arquivo_oficial_registro where arquivo_oficial_id = v_arq.id;
  delete from arquivo_oficial_lancamento_mes where arquivo_oficial_id = v_arq.id;
  update arquivo_oficial set resumo_status = 'em_carga', resumo_versao = v_ver, resumo_motivo = null,
         resumo_conferencia = p_cabecalho->'conferencia', resumo_descartado = p_cabecalho->>'descartado',
         resumo_total_registros = v_totr, resumo_total_grupos = v_totg
   where id = v_arq.id;
  return v_reg || jsonb_build_object('resumo', 'em_carga');
end $$;

comment on function fn_resumo_iniciar(uuid, uuid, jsonb, jsonb) is
  'Abre a carga do resumo de um arquivo oficial: registra o envelope (fn_registrar_arquivo_oficial, que recusa a trilha desligada), recusa resumo de outro hash, e devolve {id,status,vigente,resumo} com resumo = em_carga (mande as partes), ausente (nada a mandar) ou reenvio (já completo nesta versão). Apaga a carga anterior do mesmo arquivo. 0207.';


create or replace function fn_resumo_anexar(p_arquivo uuid, p_registros jsonb, p_grupos jsonb)
returns jsonb language plpgsql as $$
declare
  v_status text;
  v_nr integer := 0;
  v_ng integer := 0;
begin
  select resumo_status into v_status from arquivo_oficial where id = p_arquivo for update;
  if not found then raise exception 'fn_resumo_anexar: o arquivo oficial % não existe', p_arquivo; end if;
  if v_status is distinct from 'em_carga' then
    raise exception 'fn_resumo_anexar: o resumo do arquivo % está "%", não "em_carga" — recusado, nada foi gravado (reabra com fn_resumo_iniciar)',
      p_arquivo, coalesce(v_status, 'nunca iniciado');
  end if;
  p_registros := coalesce(p_registros, '[]'::jsonb);
  p_grupos := coalesce(p_grupos, '[]'::jsonb);
  if jsonb_typeof(p_registros) <> 'array' or jsonb_typeof(p_grupos) <> 'array' then
    raise exception 'fn_resumo_anexar: registros e grupos têm de ser arrays';
  end if;
  if jsonb_array_length(p_registros) > 10000 or jsonb_array_length(p_grupos) > 10000 then
    raise exception 'fn_resumo_anexar: parte grande demais (% registros, % grupos; teto 10000 de cada, o combinado é ~5000)',
      jsonb_array_length(p_registros), jsonb_array_length(p_grupos);
  end if;
  if exists (select 1 from jsonb_array_elements(p_registros) e
              where jsonb_typeof(e) <> 'array' or jsonb_array_length(e) <> 2
                 or jsonb_typeof(e->0) <> 'number' or jsonb_typeof(e->1) <> 'string') then
    raise exception 'fn_resumo_anexar: cada registro tem de ser [linha, texto]';
  end if;

  insert into arquivo_oficial_registro (arquivo_oficial_id, linha, registro, conteudo)
  select p_arquivo, (e->>0)::integer, split_part(e->>1, '|', 2), e->>1
    from jsonb_array_elements(p_registros) e;
  get diagnostics v_nr = row_count;

  insert into arquivo_oficial_lancamento_mes
    (arquivo_oficial_id, conta, mes, ind_lcto, debito, credito, partidas, partidas_sem_valor, primeira_linha)
  select p_arquivo, g.conta,
         case when g.mes is null then null else (g.mes || '-01')::date end,
         g.ind_lcto, g.debito, g.credito, g.partidas, g.partidas_sem_valor, g.primeira_linha
    from jsonb_to_recordset(p_grupos) as g(conta text, mes text, ind_lcto text, debito bigint, credito bigint,
                                            partidas integer, partidas_sem_valor integer, primeira_linha integer);
  get diagnostics v_ng = row_count;

  return jsonb_build_object('registros', v_nr, 'grupos', v_ng);
end $$;

comment on function fn_resumo_anexar(uuid, jsonb, jsonb) is
  'Anexa uma parte (até 10000 itens de cada) ao resumo em_carga: p_registros = [[linha,texto],...], p_grupos = objetos {conta,mes,ind_lcto,debito,credito,partidas,partidas_sem_valor,primeira_linha}. Linha repetida no mesmo arquivo é erro (pk). Só aceita com resumo_status = em_carga. Devolve {registros, grupos} inseridos. 0207.';


create or replace function fn_resumo_concluir(p_arquivo uuid)
returns jsonb language plpgsql as $$
declare
  a        arquivo_oficial;
  v_motivos text[] := '{}';
  v_nr     integer;
  v_ng     integer;
  v_fora   integer;
  v_div    text;
  v_part   bigint;
  v_i250   bigint;
  v_i155   jsonb;
  v_motivo text;
begin
  select * into a from arquivo_oficial where id = p_arquivo for update;
  if not found then raise exception 'fn_resumo_concluir: o arquivo oficial % não existe', p_arquivo; end if;
  if a.resumo_status in ('completo', 'recusado') then   -- idempotente: o navegador pode repetir depois de perder a resposta
    return jsonb_build_object('resumo', a.resumo_status, 'motivo', a.resumo_motivo,
      'registros', (select count(*) from arquivo_oficial_registro where arquivo_oficial_id = p_arquivo),
      'grupos', (select count(*) from arquivo_oficial_lancamento_mes where arquivo_oficial_id = p_arquivo),
      'i155_nao_fecham', (a.resumo_conferencia->'i155'->>'nao_fecham')::integer);
  end if;
  if a.resumo_status is distinct from 'em_carga' then
    raise exception 'fn_resumo_concluir: o resumo do arquivo % está "%", não "em_carga"', p_arquivo, coalesce(a.resumo_status, 'nunca iniciado');
  end if;

  select count(*) into v_nr from arquivo_oficial_registro where arquivo_oficial_id = p_arquivo;
  select count(*) into v_ng from arquivo_oficial_lancamento_mes where arquivo_oficial_id = p_arquivo;

  -- (a) o que chegou é o que foi declarado.
  if v_nr <> a.resumo_total_registros then
    v_motivos := v_motivos || format('registros gravados %s, declarados %s', v_nr, a.resumo_total_registros);
  end if;
  if v_ng <> a.resumo_total_grupos then
    v_motivos := v_motivos || format('grupos gravados %s, declarados %s', v_ng, a.resumo_total_grupos);
  end if;

  -- (b) linha de um arquivo de controle_lido linhas está entre 1 e controle_lido.
  select (select count(*) from arquivo_oficial_registro
           where arquivo_oficial_id = p_arquivo and (linha < 1 or linha > a.controle_lido))
       + (select count(*) from arquivo_oficial_lancamento_mes
           where arquivo_oficial_id = p_arquivo and primeira_linha is not null
             and (primeira_linha < 1 or primeira_linha > a.controle_lido))
    into v_fora;
  if v_fora > 0 then
    v_motivos := v_motivos || format('%s linha(s) fora de 1..%s (o arquivo tem %s linhas)', v_fora, a.controle_lido, a.controle_lido);
  end if;

  -- (c) cada tipo que aparece no resumo tem a contagem do envelope (já conferida contra o 9900).
  select string_agg(format('%s: resumo %s, envelope %s', t.registro, t.n, coalesce(a.detalhe->'por_registro'->>t.registro, '0')), '; ' order by t.registro)
    into v_div
    from (select registro, count(*) n from arquivo_oficial_registro where arquivo_oficial_id = p_arquivo group by registro) t
   where coalesce((a.detalhe->'por_registro'->>t.registro)::bigint, 0) <> t.n;
  if v_div is not null then
    v_motivos := v_motivos || ('contagem por registro diverge do envelope (' || v_div || ')');
  end if;

  -- (d) as partidas somadas nos grupos são as I250 do envelope; só a ECD tem grupos.
  select coalesce(sum(partidas), 0) into v_part from arquivo_oficial_lancamento_mes where arquivo_oficial_id = p_arquivo;
  if a.familia = 'sped' and a.subtipo = 'ECD' then
    v_i250 := coalesce((a.detalhe->'por_registro'->>'I250')::bigint, 0);
    if v_part <> v_i250 then
      v_motivos := v_motivos || format('soma de partidas dos grupos %s, I250 do envelope %s', v_part, v_i250);
    end if;
  elsif v_ng > 0 then
    v_motivos := v_motivos || format('%s grupo(s) de lançamento em arquivo %s/%s, que não os tem', v_ng, a.familia, a.subtipo);
  end if;

  if cardinality(v_motivos) > 0 then
    v_motivo := array_to_string(v_motivos, ' | ');
    delete from arquivo_oficial_registro where arquivo_oficial_id = p_arquivo;
    delete from arquivo_oficial_lancamento_mes where arquivo_oficial_id = p_arquivo;
    update arquivo_oficial set resumo_status = 'recusado', resumo_motivo = v_motivo where id = p_arquivo;
    return jsonb_build_object('resumo', 'recusado', 'motivo', v_motivo, 'registros', 0, 'grupos', 0, 'i155_nao_fecham', null);
  end if;

  -- A aritmética do I155 é ACHADO e não recusa. |I155|COD_CTA|COD_CCUS|VL_SLD_INI|IND_DC_INI|VL_DEB|VL_CRED|VL_SLD_FIN|IND_DC_FIN|
  -- (split_part: 3 = conta, 5 = saldo ini, 6 = D/C ini, 7 = débito, 8 = crédito, 9 = saldo fin, 10 = D/C fin).
  with i as (
    select linha, split_part(conteudo, '|', 3) conta,
           split_part(conteudo, '|', 5) sini, split_part(conteudo, '|', 6) dcini,
           split_part(conteudo, '|', 7) deb,  split_part(conteudo, '|', 8) cred,
           split_part(conteudo, '|', 9) sfin, split_part(conteudo, '|', 10) dcfin
      from arquivo_oficial_registro where arquivo_oficial_id = p_arquivo and registro = 'I155'
  ), n as (
    select linha, conta, dcini, dcfin,
           (sini ~ '^[0-9]+(,[0-9]+)?$' or sini ~ '^[0-9]{1,3}(\.[0-9]{3})+(,[0-9]+)?$')
             and (deb ~ '^[0-9]+(,[0-9]+)?$' or deb ~ '^[0-9]{1,3}(\.[0-9]{3})+(,[0-9]+)?$')
             and (cred ~ '^[0-9]+(,[0-9]+)?$' or cred ~ '^[0-9]{1,3}(\.[0-9]{3})+(,[0-9]+)?$')
             and (sfin ~ '^[0-9]+(,[0-9]+)?$' or sfin ~ '^[0-9]{1,3}(\.[0-9]{3})+(,[0-9]+)?$')
             and dcini in ('D', 'C') and dcfin in ('D', 'C') as legivel,
           sini, deb, cred, sfin
      from i
  ), v as (
    select linha, conta, legivel,
           case when legivel then
             (replace(replace(sini, '.', ''), ',', '.')::numeric * case dcini when 'D' then 1 else -1 end)
             + replace(replace(deb, '.', ''), ',', '.')::numeric - replace(replace(cred, '.', ''), ',', '.')::numeric
           end esperado,
           case when legivel then replace(replace(sfin, '.', ''), ',', '.')::numeric * case dcfin when 'D' then 1 else -1 end end declarado
      from n
  )
  select jsonb_build_object(
           'total', count(*),
           'ilegiveis', count(*) filter (where not legivel),
           'nao_fecham', count(*) filter (where legivel and esperado <> declarado),
           'amostra', coalesce((select jsonb_agg(jsonb_build_object('linha', linha, 'conta', conta, 'esperado', esperado, 'declarado', declarado) order by linha)
                                  from (select * from v where legivel and esperado <> declarado order by linha limit 20) s), '[]'::jsonb))
    into v_i155 from v;

  update arquivo_oficial set resumo_status = 'completo', resumo_motivo = null,
         resumo_conferencia = coalesce(resumo_conferencia, '{}'::jsonb) || jsonb_build_object('i155', v_i155)
   where id = p_arquivo;
  return jsonb_build_object('resumo', 'completo', 'registros', v_nr, 'grupos', v_ng,
                            'i155_nao_fecham', (v_i155->>'nao_fecham')::integer);
end $$;

comment on function fn_resumo_concluir(uuid) is
  'A reconferência do servidor sobre o resumo carregado: gravado = declarado, linhas em 1..controle_lido, contagem por registro = detalhe.por_registro do envelope, soma de partidas = I250 (ECD). Falhou: recusado + linhas apagadas. Passou: completo, e conta (sem recusar) os I155 cuja aritmética saldo_ini + débito - crédito = saldo_fin não fecha, em resumo_conferencia->i155. Idempotente. 0207.';

grant execute on function fn_resumo_iniciar(uuid, uuid, jsonb, jsonb) to authenticated;
grant execute on function fn_resumo_anexar(uuid, jsonb, jsonb) to authenticated;
grant execute on function fn_resumo_concluir(uuid) to authenticated;

-- Catálogo da sonda (regra da casa: toda migration acrescenta o requisito).
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- fn_upsert_caso PELO NAVEGADOR (a tela de arquivos oficiais do portal).
--
-- A tela grava o resumo antes de o lote ir ao n8n e precisa do caso_id do mandato.
-- Sem esta função, ela repetia no TypeScript o "procura por nome, senão insere" da
-- 0004 — duas implementações da mesma regra, que divergem sem erro. Duas mudanças:
--   1. `p_ator`: o evento `caso_criado` dizia sempre 'sistema:n8n'; criado pela tela,
--      a trilha mentiria sobre quem criou. O padrão continua 'sistema:n8n', e a
--      chamada de UM argumento (o nó Upsert Caso do n8n e os testes) não muda.
--      Lista fechada: o ator é rótulo da trilha, não texto livre do navegador.
--   2. `grant execute` ao authenticated (a 0028 registra que o Supabase revoga o
--      execute de função nova; esta é recriada aqui, então precisa do grant).
-- DROP antes do CREATE: um `create or replace` com o parâmetro a mais criaria uma
-- SEGUNDA função, e a chamada `fn_upsert_caso($1::text)` ficaria ambígua.
-- ---------------------------------------------------------------------------
drop function if exists fn_upsert_caso(text);
create or replace function fn_upsert_caso(p_nome text, p_ator text default 'sistema:n8n')
returns uuid
language plpgsql
as $$
declare
  v_id uuid;
begin
  if p_ator not in ('sistema:n8n', 'portal:navegador') then
    raise exception 'fn_upsert_caso: ator % fora da lista (sistema:n8n, portal:navegador)', p_ator;
  end if;
  select id into v_id from caso where nome = p_nome limit 1;
  if v_id is null then
    insert into caso (nome) values (p_nome) returning id into v_id;
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_ator, 'caso_criado', 'caso:'||v_id, jsonb_build_object('nome', p_nome));
  end if;
  return v_id;
end;
$$;
grant execute on function fn_upsert_caso(text, text) to authenticated;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('arquivo_oficial_resumo_status_coluna', '0207', 'coluna', 'arquivo_oficial.resumo_status', null, null,
   'O estado do resumo (em_carga, completo, ausente, recusado). Ausente, o navegador não tem como saber se o resumo chegou inteiro, e resumo parcial passaria por completo.',
   'importante', 880),
  ('arquivo_oficial_registro_tabela', '0207', 'tabela', 'arquivo_oficial_registro', null, null,
   'Os registros do resumo (plano de contas, saldos I155, demonstrações) com a linha do arquivo. Ausente, o resumo não tem onde morar e a leitura no navegador se perde.',
   'importante', 881),
  ('arquivo_oficial_lancamento_mes_tabela', '0207', 'tabela', 'arquivo_oficial_lancamento_mes', null, null,
   'O I250 da ECD somado por conta, mês e indicador. Ausente, a ECD perde os lançamentos que as reconciliações S1/S2 conferem.',
   'importante', 882),
  ('resumo_iniciar_funcao', '0207', 'funcao', 'fn_resumo_iniciar', null, null,
   'Abre a carga do resumo: registra o envelope, recusa resumo de outro hash, declara os totais. Sem ela o navegador não tem porta de entrada.',
   'importante', 883),
  ('resumo_anexar_funcao', '0207', 'funcao', 'fn_resumo_anexar', null, null,
   'Recebe as partes do resumo (corpo de RPC de 15 MB não é aposta; o statement_timeout do authenticated é de 8 s). Sem ela o resumo não chega.',
   'importante', 884),
  ('resumo_concluir_funcao', '0207', 'funcao', 'fn_resumo_concluir', null, null,
   'A reconferência do servidor: sem ela o resumo nunca vira completo, ou, pior, uma versão anterior que não a tenha deixa resumo parcial passar por completo.',
   'importante', 885),
  ('resumo_concluir_corpo', '0207', 'corpo', 'fn_resumo_concluir', 'v_part <> v_i250', null,
   'Corpo anterior ao desta migration não reconfere as partidas contra o I250 do envelope: um resumo com partida perdida ficaria completo.',
   'importante', 886),
  ('upsert_caso_ator_corpo', '0207', 'corpo', 'fn_upsert_caso', 'p_ator not in', null,
   'Corpo anterior ao desta migration não aceita o ator nem tem grant ao authenticated: a tela de arquivos oficiais não consegue obter o caso_id do mandato.',
   'importante', 887)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0207', revisado_em = current_date,
       observacao = 'A 0207 cria arquivo_oficial_registro e arquivo_oficial_lancamento_mes (tabelas novas, vazias), sete colunas resumo_* em arquivo_oficial (null = nunca tentado) e as funções fn_resumo_iniciar, fn_resumo_anexar e fn_resumo_concluir, e recria fn_upsert_caso com p_ator e grant ao authenticated. Catalogadas por nome, e o concluir e o upsert pelo corpo.'
 where id = true;
