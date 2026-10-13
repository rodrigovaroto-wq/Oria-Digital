-- =============================================================================
-- 0206 — O ARQUIVO OFICIAL LIDO E CONTADO (envelope), E A VERSÃO QUE VALE
-- (Espec. 12, §8 e §13: G5, G6, G7, G9, G12, G25; decisões D12.8, D12.9, D12.11. Fase F2T, etapa 1:
--  fundação sem cliente. Só ACRESCENTA: `campo_extraido` e a ingestão não são tocados.)
--
-- O QUE ESTA MIGRATION É. Um serviço leitor próprio (Node, fora do n8n — D12.9, porque o nó de merge
-- do n8n estoura a pilha com ~125-150 mil itens, medido em 17/09/2026) lê arquivos de leiaute oficial
-- (SPED, XML fiscais, eSocial, Reinf, CNAB, OFX) e registra aqui o ENVELOPE de cada arquivo: o que é,
-- de quem, de quando, quantos registros DECLARAVA e quantos foram LIDOS. O detalhe registro a registro
-- vem nas ondas seguintes (§8); nada disso existe ainda, e esta migration não finge que existe.
--
-- POR QUE A TRILHA É UM LIGA/DESLIGA POR CASO, COM DEFAULT FALSE (G25). A trilha nova não pode alterar
-- a ingestão que funciona. `caso.trilha_transacional` nasce false em todo caso existente e novo: em
-- produção NADA muda até alguém ligar, caso a caso. E desligada ela RECUSA com exceção em vez de
-- gravar calada ou ignorar calada: estágio que não rodou tem a mesma aparência de estágio que rodou e
-- não achou nada (regra 7), então "não está ligado" tem de ser um erro que o leitor ouve.
--
-- "LIDO" NUNCA SEM CONTAGEM (regra 7, e §8 passo 3: `|9999|`, rodapé do CNAB, `S-1299`). Os checks da
-- tabela impedem `status = 'lido'` sem `controle_lido`, e, quando o formato declara contagem, sem ela
-- bater com a lida. Leitura incompleta é `controle_divergente` (visível), nunca dado parcial dito
-- completo. O `is not null` explícito é de propósito: `declarado = lido` com declarado NULO dá NULL, e
-- check que dá NULL PASSA — a primeira escrita deste check deixaria "lido" sem contagem declarada
-- entrar (é o assert c-3 do teste).
--
-- A REGRA DE VERSÃO VIGENTE (G9). Entre as linhas do mesmo caso e da mesma `chave_natural` com
-- status 'lido', EXATAMENTE UMA é vigente: a retificadora vence a original; entre iguais, a registrada
-- por último vence. As outras ficam `vigente = false` com `substituido_por` apontando para a vigente
-- (guardadas como evidência, nunca apagadas). POR QUÊ: um SPED retificado contado junto com o original
-- conta em dobro — receita e passivo em dobro com a aparência de dado. O QUE A REGRA COBRE: a
-- escrituração SPED retificada/substituída (mesma `cnpj|subtipo|ini|fim`) e o reenvio do mesmo arquivo
-- (mesmo hash). O QUE ELA NÃO COBRE, e não finge cobrir: NF-e cancelada (o evento de cancelamento tem
-- chave própria e não marca a nota), retificação/exclusão do eSocial (o S-1200 retificador e o S-3000
-- têm Id próprio) e retorno CNAB duplicado (dois retornos do mesmo movimento diferem em hash por causa
-- da data/hora de geração). Isso fica para as ondas 3, 4 e 2, onde o conteúdo é lido. Linha com status != 'lido' NUNCA é
-- vigente: um arquivo mal lido não substitui um bem lido, e uma chave que só tem arquivo mal lido fica
-- SEM vigente (ausência visível) em vez de entrar como se estivesse completa. Lido sem `chave_natural`
-- é vigente (não há identidade com quem competir; sumir seria perda de dado). "Registrada por último"
-- é a coluna `seq` (identity), não `lido_em`: duas linhas na mesma transação têm o MESMO now(), e o
-- desempate por relógio seria sorteio. O índice único parcial garante no banco o "no máximo uma", e
-- um advisory lock por (caso, chave) serializa dois registros concorrentes da mesma chave — sem ele a
-- segunda transação toparia no índice em vez de decidir.
--
-- DUAS RETIFICADORAS SEM CADEIA. A ordem de registro é a ordem de leitura do zip, arbitrária: "a última
-- registrada" entre duas retificadoras pode ser a MAIS VELHA. Sem cadeia de recibo (que só as ondas
-- seguintes leem), a chave com MAIS DE UMA retificadora lida fica SEM vigente, e cada linha lida dela
-- leva em `detalhe.vigencia` o motivo ("ambigua: N retificadoras..."): ausência visível, escolha
-- manual. Com uma só, ela vence; sem nenhuma, vence a última registrada (original vs original não
-- tem outro critério). O `detalhe.vigencia` some quando a ambiguidade deixa de existir.
--
-- RELEITURA DO MESMO ARQUIVO. Mesmo (caso, hash) com status != 'lido' OU `leitor_versao` diferente
-- ATUALIZA a linha: o cenário real é um EFD de leiaute novo registrado como `versao_desconhecida`;
-- alguém acrescenta a versão ao registro de leiautes e relê — descartar o envelope novo deixaria o
-- banco em `versao_desconhecida` para sempre, sem vigente, com a aparência de leitura que falhou.
-- `lido` + mesmo leitor é reenvio puro: devolve o que existe. A função devolve jsonb (id, status,
-- vigente, atualizado, vigencia) para o CLI comparar o status GRAVADO com o lido.
--
-- ARQUIVO OFICIAL É EVIDÊNCIA: o `authenticated` não apaga. Apagar a vigente deixaria as substituídas
-- órfãs e a chave sem vigente, sem recálculo. O cascade a partir de `caso` continua (é do dono).
--
-- `familia = 'zip'`: o contêiner zip é uma linha própria (declarado = entradas, lido = processadas,
-- detalhe com as recusadas), para entrada cifrada ou zip-bomb não sumir sem rastro (regra 7).
--
-- NÃO HÁ BACKFILL: tabela nova, coluna nova com default false. Produção não é tocada.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/arquivo_oficial.test.sql — 65 asserts, medidos em 13/10/2026
-- com o assert em `raise notice` (voltou para `raise exception` depois). Cada regra desligada num clone do
-- banco, uma por vez: a recusa da trilha desligada (3 dos 65 asserts reprovam), a regra de vigência inteira
-- (23 dos 65), a retificadora vencer a original (2 dos 65), "o último registrado vence" (6 dos 65), o check
-- lido-tem-contagem (6 dos 65), o check divergente-tem-as-duas (3 dos 65), o check vigente-só-se-lido
-- (1 dos 65), o índice único parcial (1 dos 65), o lido-sem-chave ser vigente (1 dos 65), o default da
-- trilha virar true (4 dos 65). Revisão de 13/10: a releitura desligada (8 dos 65), a releitura que olha só
-- o status e ignora o leitor_versao (5 dos 65), a releitura que não recalcula a chave antiga (1 dos 65), a
-- ambiguidade de duas retificadoras desligada (7 dos 65), a ambiguidade que não limpa o detalhe.vigencia
-- (1 dos 65), o revoke de delete desfeito (3 dos 65). Quatro mutações ABORTAM o teste em vez de reprovar
-- assert (idempotência: duplicate key no 6o assert; vigente sem filtrar status: check no 34o; envelope
-- impondo id: pkey no 10o; 'zip' fora do check: check_violation no 61o) — aborto é reprovação, mas o
-- denominador não os conta. NÃO medido: o advisory lock (exige duas sessões; o teste roda numa só), por
-- isso ele é cinto-e-suspensório documentado, não invariante provado.
-- =============================================================================

alter table caso add column if not exists trilha_transacional boolean not null default false;
comment on column caso.trilha_transacional is
  'Liga/desliga por caso da trilha de arquivos oficiais (Espec. 12, G25). Default false: nada muda em produção até alguém ligar, e desligada fn_registrar_arquivo_oficial RECUSA com exceção (regra 7). 0206.';

create table if not exists arquivo_oficial (
  id                 uuid primary key default gen_random_uuid(),
  caso_id            uuid not null references caso(id) on delete cascade,
  documento_id       uuid references documento(id) on delete set null,
  familia            text not null check (familia in
    ('sped','nfe','cte','mdfe','nfse','esocial','reinf','cnab240','cnab400','cnab150','ofx','zip')),
  subtipo            text,
  versao_leiaute     text,
  hash_sha256        text not null,
  cnpj               text,
  periodo_ini        date,
  periodo_fim        date,
  chave_natural      text,
  retificadora       boolean not null default false,
  controle_tipo      text not null check (controle_tipo in
    ('contagem_declarada','documento_unico','sem_controle_no_formato')),
  controle_declarado bigint,
  controle_lido      bigint,
  status             text not null check (status in
    ('lido','controle_divergente','versao_desconhecida','familia_desconhecida','falhou')),
  vigente            boolean not null default false,
  substituido_por    uuid references arquivo_oficial(id) on delete set null,
  detalhe            jsonb not null default '{}'::jsonb,
  leitor_versao      text not null,
  lido_em            timestamptz not null default now(),
  seq                bigint generated always as identity,
  constraint arquivo_oficial_caso_hash_uk unique (caso_id, hash_sha256),
  constraint arquivo_oficial_lido_tem_contagem check (
    status <> 'lido'
    or (controle_lido is not null
        and (controle_tipo <> 'contagem_declarada'
             or (controle_declarado is not null and controle_declarado = controle_lido)))),
  constraint arquivo_oficial_divergente_tem_as_duas check (
    status <> 'controle_divergente'
    or (controle_declarado is not null and controle_lido is not null
        and controle_declarado <> controle_lido)),
  constraint arquivo_oficial_vigente_so_se_lido check (not vigente or status = 'lido')
);

comment on table arquivo_oficial is
  'Envelope de cada arquivo de leiaute oficial lido pelo serviço leitor (Espec. 12, D12.9): o que é, de quem, de quando, quantos registros declarava e quantos foram lidos. Idempotente por (caso, hash). Uma vigente por (caso, chave_natural), regra G9. 0206.';
comment on column arquivo_oficial.chave_natural is
  'Identidade do CONTEÚDO, para a regra de versão vigente: sped cnpj|subtipo|ini|fim; nfe/cte/mdfe a chave de acesso (44 dígitos); esocial/reinf o Id do evento; ofx banco|conta|ini|fim; cnab o próprio hash.';
comment on column arquivo_oficial.controle_tipo is
  'Como o formato se auto-confere: contagem_declarada (|9999|, rodapé CNAB, S-1299), documento_unico (um XML = um documento) ou sem_controle_no_formato.';
comment on column arquivo_oficial.seq is
  'Ordem de registro. Desempata "o registrado por último vence" na versão vigente; lido_em não serve, pois duas linhas na mesma transação têm o mesmo now().';
comment on constraint arquivo_oficial_lido_tem_contagem on arquivo_oficial is
  'Regra 7: "lido" nunca sem contagem. O is not null explícito evita o check que dá NULL e passa.';

-- No máximo UMA vigente por (caso, chave_natural): o banco garante o que a função decide.
create unique index if not exists arquivo_oficial_uma_vigente_por_chave
  on arquivo_oficial (caso_id, chave_natural) where vigente;
create index if not exists arquivo_oficial_caso_idx on arquivo_oficial (caso_id, familia);

alter table arquivo_oficial enable row level security;
create policy arquivo_oficial_authenticated_all on arquivo_oficial
  for all to authenticated using (true) with check (true);
grant select, insert, update, delete on arquivo_oficial to authenticated;
-- Evidência não se apaga pelo portal: apagar a vigente deixa as substituídas órfãs e a chave sem vigente.
-- (Em produção o default privilege do Supabase também concede; este revoke vem depois dele.)
revoke delete on arquivo_oficial from authenticated;


-- Recalcula quem é a vigente de UMA chave. Interna: só fn_registrar_arquivo_oficial a chama.
create or replace function fn_recalcular_vigencia_arquivo_oficial(p_caso uuid, p_chave text)
returns void language plpgsql as $$
declare
  v_vigente uuid;
  v_n_ret   int;
begin
  if p_chave is null then return; end if;   -- sem identidade, sem competição

  -- 1) Zera o grupo ANTES de eleger (o índice único parcial é checado linha a linha) e limpa o motivo
  --    de ambiguidade antigo, que pode já não valer.
  update arquivo_oficial set vigente = false, substituido_por = null, detalhe = detalhe - 'vigencia'
   where caso_id = p_caso and chave_natural = p_chave
     and (vigente or substituido_por is not null or detalhe ? 'vigencia');

  -- 2) Mais de uma retificadora lida e nenhuma cadeia: ausência visível, não palpite.
  select count(*) into v_n_ret from arquivo_oficial
   where caso_id = p_caso and chave_natural = p_chave and status = 'lido' and retificadora;
  if v_n_ret > 1 then
    update arquivo_oficial
       set detalhe = detalhe || jsonb_build_object('vigencia',
         'ambigua: ' || v_n_ret || ' retificadoras da mesma escrituração sem cadeia de recibo; escolha manual')
     where caso_id = p_caso and chave_natural = p_chave and status = 'lido';
    return;
  end if;

  -- 3) Retificadora vence original; entre originais, a registrada por último. Só status 'lido' concorre.
  select id into v_vigente
    from arquivo_oficial
   where caso_id = p_caso and chave_natural = p_chave and status = 'lido'
   order by retificadora desc, seq desc
   limit 1;

  if v_vigente is null then return; end if;   -- só há arquivo mal lido: fica sem vigente, de propósito

  update arquivo_oficial set vigente = true where id = v_vigente;
  -- 4) As outras lidas ficam como evidência, apontando para a vigente.
  update arquivo_oficial set substituido_por = v_vigente
   where caso_id = p_caso and chave_natural = p_chave and status = 'lido' and id <> v_vigente;
end $$;

comment on function fn_recalcular_vigencia_arquivo_oficial(uuid, text) is
  'Regra G9 de versão vigente por (caso, chave_natural): retificadora vence original, última registrada vence entre iguais; mais de uma retificadora lida = sem vigente + detalhe.vigencia. Interna de fn_registrar_arquivo_oficial. 0206.';

create or replace function fn_registrar_arquivo_oficial(p_caso uuid, p_documento uuid, p_envelope jsonb)
returns jsonb language plpgsql as $$
declare
  v_liga  boolean;
  v_id    uuid;
  v_antiga text;
  v_atualizado boolean := false;
  r       arquivo_oficial;   -- o envelope novo
  e       arquivo_oficial;   -- a linha que já existia, se houver
  v_fim   arquivo_oficial;
begin
  select trilha_transacional into v_liga from caso where id = p_caso;
  if v_liga is null then
    raise exception 'fn_registrar_arquivo_oficial: o caso % não existe', p_caso;
  end if;
  if not v_liga then
    raise exception 'fn_registrar_arquivo_oficial: a trilha de arquivos oficiais está DESLIGADA no caso % — recusado, nada foi gravado. Para ligar: update caso set trilha_transacional = true where id = ''%''.', p_caso, p_caso;
  end if;
  if p_envelope is null or coalesce(p_envelope->>'hash_sha256', '') = '' then
    raise exception 'fn_registrar_arquivo_oficial: o envelope não traz hash_sha256 — sem ele não há idempotência';
  end if;

  -- Quem decide id, vigente, substituido_por e seq é a regra, não o envelope: nem o INSERT nem o UPDATE
  -- abaixo leem essas quatro de `r`, mesmo que o jsonb as traga.
  r := jsonb_populate_record(null::arquivo_oficial, p_envelope);

  -- Serializa o mesmo (caso, hash) e o mesmo (caso, chave): dois leitores concorrentes não se atropelam.
  perform pg_advisory_xact_lock(hashtextextended(p_caso::text || '|' || r.hash_sha256, 0));
  select * into e from arquivo_oficial where caso_id = p_caso and hash_sha256 = r.hash_sha256;
  perform pg_advisory_xact_lock(hashtextextended(p_caso::text || '#' || coalesce(r.chave_natural, ''), 0));
  if e.id is not null and e.chave_natural is distinct from r.chave_natural then
    perform pg_advisory_xact_lock(hashtextextended(p_caso::text || '#' || coalesce(e.chave_natural, ''), 0));
  end if;

  if e.id is not null then
    if e.status = 'lido' and e.leitor_versao = r.leitor_versao then
      -- Reenvio puro: devolve o que existe (só completa o documento, se faltava).
      if e.documento_id is null and p_documento is not null then
        update arquivo_oficial set documento_id = p_documento where id = e.id;
      end if;
      v_id := e.id;
    else
      -- Releitura: o arquivo mal lido, ou lido por outro leitor, passa a valer o que o envelope novo diz.
      update arquivo_oficial set
        documento_id = coalesce(p_documento, documento_id), familia = r.familia, subtipo = r.subtipo,
        versao_leiaute = r.versao_leiaute, cnpj = r.cnpj, periodo_ini = r.periodo_ini,
        periodo_fim = r.periodo_fim, chave_natural = r.chave_natural,
        retificadora = coalesce(r.retificadora, false), controle_tipo = r.controle_tipo,
        controle_declarado = r.controle_declarado, controle_lido = r.controle_lido, status = r.status,
        detalhe = coalesce(r.detalhe, '{}'::jsonb), leitor_versao = r.leitor_versao,
        lido_em = coalesce(r.lido_em, now()),
        vigente = false, substituido_por = null
       where id = e.id;
      v_id := e.id;
      v_atualizado := true;
      v_antiga := e.chave_natural;
    end if;
  else
    insert into arquivo_oficial
      (caso_id, documento_id, familia, subtipo, versao_leiaute, hash_sha256, cnpj, periodo_ini, periodo_fim,
       chave_natural, retificadora, controle_tipo, controle_declarado, controle_lido, status, detalhe,
       leitor_versao, lido_em)
    values
      (p_caso, p_documento, r.familia, r.subtipo, r.versao_leiaute, r.hash_sha256, r.cnpj, r.periodo_ini,
       r.periodo_fim, r.chave_natural, coalesce(r.retificadora, false), r.controle_tipo, r.controle_declarado,
       r.controle_lido, r.status, coalesce(r.detalhe, '{}'::jsonb), r.leitor_versao, coalesce(r.lido_em, now()))
    returning id into v_id;
    v_atualizado := false;
  end if;

  if not (e.id is not null and not v_atualizado) then
    -- Linha nova ou atualizada: recalcula a chave nova e, se a linha mudou de chave, a antiga também.
    if r.chave_natural is null then
      update arquivo_oficial set vigente = true where id = v_id and status = 'lido';
    else
      perform fn_recalcular_vigencia_arquivo_oficial(p_caso, r.chave_natural);
    end if;
    if v_atualizado and v_antiga is not null and v_antiga is distinct from r.chave_natural then
      perform fn_recalcular_vigencia_arquivo_oficial(p_caso, v_antiga);
    end if;
  end if;

  select * into v_fim from arquivo_oficial where id = v_id;
  return jsonb_build_object('id', v_fim.id, 'status', v_fim.status, 'vigente', v_fim.vigente,
                            'atualizado', v_atualizado, 'vigencia', v_fim.detalhe->>'vigencia');
end $$;

comment on function fn_registrar_arquivo_oficial(uuid, uuid, jsonb) is
  'Registra o envelope de um arquivo oficial lido e devolve jsonb {id, status, vigente, atualizado, vigencia}. Recusa com exceção se caso.trilha_transacional = false. Mesmo (caso, hash): lido com o mesmo leitor_versao é reenvio puro; status != lido ou outro leitor_versao ATUALIZA a linha e recalcula a vigência das chaves antiga e nova. Aplica a regra de versão vigente (G9). 0206.';

-- Catálogo da sonda (regra da casa: toda migration acrescenta o requisito).
-- ---------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('arquivo_oficial_tabela_existe', '0206', 'tabela', 'arquivo_oficial', null, null,
   'Onde o serviço leitor registra o envelope de cada arquivo oficial (o que é, quantos registros declarava, quantos leu). Ausente, o leitor não tem onde gravar e a leitura some sem rastro.',
   'importante', 870),
  ('caso_trilha_transacional_coluna', '0206', 'coluna', 'caso.trilha_transacional', null, null,
   'O liga/desliga por caso da trilha de arquivos oficiais (G25). Ausente, não há como habilitar a trilha em um caso, e o registro do leitor é recusado ou nem chega a existir.',
   'importante', 871),
  ('arquivo_oficial_registrar_funcao', '0206', 'funcao', 'fn_registrar_arquivo_oficial', null, null,
   'A porta única do leitor para gravar o envelope: recusa trilha desligada, é idempotente por hash e aplica a versão vigente. Sem ela o leitor insere direto e a retificada conta junto com a original (em dobro).',
   'importante', 872),
  ('arquivo_oficial_vigencia_funcao', '0206', 'funcao', 'fn_recalcular_vigencia_arquivo_oficial', null, null,
   'A regra G9 de versão vigente. Sem ela nenhum arquivo fica vigente e as reconciliações das ondas seguintes não teriam qual versão somar.',
   'importante', 873),
  ('arquivo_oficial_registrar_corpo', '0206', 'corpo', 'fn_registrar_arquivo_oficial', 'if not v_liga then', null,
   'Corpo anterior à 0206 não recusa a trilha desligada: o leitor gravaria em caso que ninguém ligou, com a aparência de estágio que rodou.',
   'importante', 874)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0206', revisado_em = current_date,
       observacao = 'A 0206 cria arquivo_oficial (tabela nova, vazia), caso.trilha_transacional (default false) e as funções fn_registrar_arquivo_oficial e fn_recalcular_vigencia_arquivo_oficial. Catalogadas por nome e pelo corpo do registro.'
 where id = true;
