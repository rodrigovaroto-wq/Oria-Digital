-- =============================================================================
-- 0273 — A CONTRAPARTE COM NOME DE TOTAL QUE SÓ O ANALISTA DISTINGUE: a confirmação, POR MANDATO, de que "TOTAL DISTRIBUIDORA LTDA"
--        é cliente (ou fornecedor) de verdade (MB2 do PLANO_MVP_2026-11.md; contrato em `aplicadorDeMapeamento`, opção `contrapartesReais`,
--        Leitor/lib/mapeamento.mjs)
-- (Cria 1 tabela, 4 funções, 1 policy de leitura, 2 views da sonda. Nenhum backfill: a tabela nasce vazia.)
--
-- O DEFEITO. O aplicador do mapeamento rejeita, por segurança, a linha de contas a receber/a pagar cuja contraparte tem nome de total
-- ("TOTAL DISTRIBUIDORA LTDA", "SOMA ENGENHARIA") E vencimento preenchido: sem o analista, ela não se distingue de um "Total ACME; 02/01/2025"
-- (total por data), e somar o total triplicava o aging. O efeito do outro lado é o cliente de verdade, com nome de total, que fica FORA do
-- aging para sempre: o aplicador devolve a linha como rejeitada, com o motivo, mas o analista não tinha como dizer "esta é cliente".
-- `contrapartesReais` é a porta, e faltava onde guardar o que ele confirmou.
--
-- ESTA TABELA É POR MANDATO, ao contrário da 0272, e isto é decisão. O nome de um cliente é DADO DO CLIENTE: não pode ir para
-- `mapeamento_de_colunas` (global, legível por qualquer papel). A RLS é a do padrão da 0216 (tabela com `caso_id`): lê o Sócio ou
-- quem tem o mandato em `fn_casos_legiveis()` (Leitura, Analista alocados); NINGUÉM escreve direto (nem policy nem grant de escrita
-- ao authenticated: 42501 antes de a RLS ser avaliada); a escrita é pelas funções abaixo, que decidem com `fn_pode_escrever_caso`
-- (Sócio, ou Analista alocado NAQUELE mandato). A seção 12 de acesso_por_caso.test.sql cobra a forma (policy de leitura pelos conjuntos).
--
-- O QUE A MIGRATION INSTALA
--   * `fn_texto_normalizado(text)`: a normalização de UMA célula, a MESMA de `textoNormalizado` da biblioteca e da célula de
--     `fn_impressao_do_cabecalho` (0272): NFC; sequências de [espaço, \t, \n, \r, U+00A0] colapsadas em um espaço; pontas aparadas
--     desses MESMOS cinco caracteres (nem `btrim` genérico nem `\s`: dependem de locale); SEM minúsculas (lower() depende do LC_CTYPE).
--     DECISÃO: a impressão da 0272 NÃO passa a chamá-la. Ela está aplicada em produção, o corpo dela é sondado pelo marcador `, NFC)`
--     (requisito 1307) e está dentro de uma CHECK da tabela de mapeamentos; reescrevê-la para economizar uma cópia de três linhas
--     arriscaria a impressão que produção já usa. A cópia fica GUARDADA pelo teste (seção 1): para cada vetor, a impressão de um
--     cabeçalho de uma célula = sha256 do texto normalizado por esta função. Se uma das duas mudar, o teste reprova.
--   * `contraparte_confirmada`: id, caso_id (FK, cascade), tipo_base (contas_a_receber | contas_a_pagar), contraparte (já normalizada:
--     CHECK `contraparte = fn_texto_normalizado(contraparte) and contraparte <> ''`, que cobre o service_role), confirmado_por
--     (auth.uid(), SEM FK para auth.users: a autoria sobrevive ao usuário, como na 0272), confirmado_em, revogado_em, revogado_por (CHECK:
--     os dois juntos ou nenhum). Índice ÚNICO PARCIAL (caso_id, tipo_base, contraparte) where revogado_em is null: no máximo UMA vigente.
--     REVOGAR NÃO APAGA: marca revogado_em/revogado_por; confirmar de novo depois de revogar cria linha nova (a trilha inteira fica).
--   * `fn_contraparte_confirmar(caso, tipo_base, contraparte)` -> {id, contraparte (normalizada), ja_vigente}. Security definer; só quem
--     pode ESCREVER o mandato (Sócio; Analista alocado). Leitura, Analista de OUTRO mandato, sem papel, anônimo e conexão de serviço
--     (sem auth.uid() não há autor) recebem 42501. Contraparte vazia depois de normalizar: 22023. Mandato inexistente: P0002.
--     CONFIRMAR DE NOVO O QUE JÁ ESTÁ VIGENTE (escolha desta migration): NÃO duplica, NÃO muda autor nem data e NÃO grava evento; devolve a
--     vigente com `ja_vigente = true`. Razão: o autor e a data valem a primeira confirmação, e um segundo clique não pode reescrever quem decidiu.
--     Grava `contraparte_confirmada` em evento_auditoria (entidade_ref `caso:<id>`, que é o que a trilha por mandato lê).
--   * `fn_contraparte_revogar(caso, tipo_base, contraparte)` -> {id, contraparte}. Mesma guarda. Marca a vigente como revogada e grava
--     `contraparte_revogada`. NÃO há vigente para revogar: P0002 com o motivo (e não "feito" calado: o portal diria que revogou o que nunca esteve confirmado).
--   * `fn_contrapartes_confirmadas(caso, tipo_base)` -> text[] ordenado (collate "C") dos nomes normalizados vigentes: é o que vai para
--     `contrapartesReais`. Invoker (a RLS vale), mas com guarda explícita: quem não enxerga o mandato (Leitura/Analista de outro mandato, sem
--     papel, anônimo) recebe 42501 e NÃO um array vazio ("sem acesso" não pode parecer "nenhuma confirmada": regra 1, e o aplicador então
--     rejeitaria toda linha com nome de total sem ninguém ter dito que ninguém confirmou). Conexão de serviço lê (o n8n). Array vazio = o
--     mandato existe, você o enxerga, e ninguém confirmou.
--
-- GRANT (convenção da 0214): authenticated só SELECT na tabela; service_role as quatro operações. Funções: revoke de public/anon,
-- execute para authenticated e service_role (e supabase_read_only_user quando existe).
--
-- A SONDA (12 requisitos, ordem 1320-1331): a tabela, as 4 funções, o corpo das duas escritas (`fn_pode_escrever_caso`), o corpo da leitura
-- (`fn_pode_ler_caso`), o corpo da normalização (NFC), a policy de leitura, e duas views `comportamento` (o índice único parcial e as CHECKs).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/a_contraparte_com_nome_de_total_que_so_o_analista_distingue.test.sql — 91 asserts
-- (medido: 91 chamadas, 91 execuções, nenhum em laço). Cada guarda desligada UMA por vez DENTRO de uma transação (a sabotagem recompõe a função por
-- pg_get_functiondef e ABORTA se o trecho não existe: nenhuma variante deixou de aplicar), o teste inteiro rodado com o assert em `raise warning`
-- (voltou para `raise exception`; log lido atrás de FALHOU) e a transação desfeita. Controle (migration intacta): 0 dos 91 reprovam, 91 execuções.
-- Por guarda desligada, UMA por vez (12/11/2026; o número de uma guarda que muda o NOME gravado inclui o que vem em cascata nas seções seguintes):
--   * normalização (vetores): sem NBSP: 24 · sem NFC: 8 · sem colapso de espaços: 23 · sem aparar as pontas: 27 · com lower(): 31 · classe genérica que apara
--     também U+2003: 3 · sem tab/quebra de linha: 13 · a impressão da 0272 passa a divergir da célula (a cópia que o teste amarra): 1;
--   * contraparte vazia recusada: sem a recusa na função de confirmar: 3 · na de revogar: 1 · sem a CHECK da tabela (service_role): 7 · sem as duas: 14;
--   * uma vigente: sem o índice único (vira comum): 16 · a função não procura a vigente: 1 · sem o índice E sem a procura: 16 · índice sem o predicado (único total): 9;
--   * revogar não apaga: a função APAGA: 3 · sem a recusa quando não há vigente: 6 · sem a CHECK da revogação inteira: 3;
--   * papel e mandato na ESCRITA (como authenticated): confirmar deixando a Leitura passar: 11 · deixando qualquer papel passar: 15 · sem checar o MANDATO (qualquer
--     Analista): 17 · sem guarda nenhuma: 19 · sem a guarda de mandato nulo (o Sócio passa por NULL): 1 · revogar: Leitura passa 7 · qualquer papel 8 · qualquer Analista 9 · sem guarda 10;
--   * leitura: listar deixando qualquer papel passar: 2 · sem a guarda (o invoker devolveria array vazio): 5 · sem a guarda de mandato nulo: 1 · sem a conexão de serviço: 1 ·
--     em ordem inversa: 4 · policy `using (true)`: 2 · policy só por fn_tem_papel: 1 · mandato inexistente sem P0002 (confirmar 1, listar 1);
--   * evento: confirmar não grava: 3 · revogar não grava: 4 · confirmar sem o caso no entidade_ref: 3 · revogar sem o caso: 3 · autor do evento inventado: 1 · autor da linha
--     inventado: confirmar 3, revogar 1;
--   * tipo_base fora da lista: sem a recusa da função: confirmar 2, revogar 1, listar 1 · sem a CHECK da tabela: 1 · sem a função E sem a CHECK: 7;
--   * escrita direta (grant de escrita + policy `for all using (true)` ao authenticated): 5 · `grant execute` ao anon: confirmar 11, revogar 5, listar 1 · ao public (as três): 15;
--   * sonda: requisito apontando para objeto ausente: 1 · marcador de corpo que o corpo não tem: 1 · catálogo encolhido: 1.
-- LIMITES DITOS. (1) O banco de teste é C.UTF-8: o `collate "C"` da listagem não é provado como necessário aqui (o teste prova a ORDEM, e sem `order by`
-- a inversa reprova 4, mas num banco com outro locale só o `collate "C"` evita que a ordem mude); (2) sem a sabotagem do advisory lock (a corrida de duas
-- confirmações simultâneas não é exercitável num teste de uma sessão): o índice único parcial é a rede (a perdedora leva 23505, não grava duas vigentes);
-- (3) uma variante testada e descartada: revogar sem gravar `revogado_em` morre na CHECK `contraparte_revogacao_inteira` (a CHECK é a guarda dessa mutação: 3 asserts).
-- =============================================================================
begin;

-- ---------------------------------------------------------------------------
-- 1. A NORMALIZAÇÃO DE UMA CÉLULA
-- ---------------------------------------------------------------------------
create function fn_texto_normalizado(p_texto text) returns text
language sql immutable set search_path = public, pg_temp as $$
  select btrim(regexp_replace(normalize(coalesce(p_texto, ''), NFC),
                              '[ ' || chr(9) || chr(10) || chr(13) || chr(160) || ']+', ' ', 'g'),
               ' ' || chr(9) || chr(10) || chr(13) || chr(160))
$$;

comment on function fn_texto_normalizado(text) is
  '0273: a normalização de UMA célula, a MESMA de textoNormalizado em Leitor/lib/mapeamento.mjs e da célula de fn_impressao_do_cabecalho (0272): NFC, [espaço \t \n \r U+00A0] colapsados em um espaço e aparados nas pontas, SEM minúsculas (lower() depende do LC_CTYPE). NULL vira texto vazio.';

-- ---------------------------------------------------------------------------
-- 2. A TABELA
-- ---------------------------------------------------------------------------
create table contraparte_confirmada (
  id             uuid primary key default gen_random_uuid(),
  caso_id        uuid not null references caso(id) on delete cascade,
  tipo_base      text not null check (tipo_base in ('contas_a_receber', 'contas_a_pagar')),
  contraparte    text not null,
  confirmado_por uuid not null,
  confirmado_em  timestamptz not null default now(),
  revogado_em    timestamptz,
  revogado_por   uuid,
  constraint contraparte_normalizada check (contraparte <> '' and contraparte = fn_texto_normalizado(contraparte)),
  constraint contraparte_revogacao_inteira check ((revogado_em is null) = (revogado_por is null))
);
comment on constraint contraparte_normalizada on contraparte_confirmada is
  '0273: o nome gravado é o normalizado pelo banco (fn_texto_normalizado) e não vazio, para quem escrever sem passar pela função (service_role): é a forma exata que `contrapartesReais` compara.';
comment on constraint contraparte_revogacao_inteira on contraparte_confirmada is
  '0273: revogado_em e revogado_por andam juntos: revogação sem autor ou autor sem data não entra.';

-- No máximo UMA vigente por (mandato, tipo_base, contraparte).
create unique index contraparte_confirmada_uma_vigente on contraparte_confirmada (caso_id, tipo_base, contraparte) where revogado_em is null;

comment on table contraparte_confirmada is
  '0273: contrapartes que o analista CONFIRMOU, POR MANDATO, como cliente/fornecedor de verdade apesar do nome de total (alimenta `contrapartesReais` de aplicadorDeMapeamento). Nome de cliente é dado do cliente: RLS por mandato (0216). Escrita só por fn_contraparte_confirmar/fn_contraparte_revogar; revogar não apaga, marca revogado_em.';
comment on column contraparte_confirmada.contraparte is
  'Nome NORMALIZADO pelo banco (fn_texto_normalizado): NFC, espaços colapsados e aparados, sem minúsculas.';
comment on column contraparte_confirmada.confirmado_por is
  'auth.uid() de quem confirmou. Sem FK de propósito: a autoria sobrevive à saída do usuário.';

alter table contraparte_confirmada enable row level security;
create policy contraparte_confirmada_read on contraparte_confirmada for select to authenticated
  using ((select fn_eh_socio()) or caso_id in (select c from fn_casos_legiveis() c));
-- Sem policy de insert/update/delete: a escrita é a função (security definer).

-- GRANT (0214): authenticated só lê; service_role as quatro operações.
grant select on contraparte_confirmada to authenticated;
grant select, insert, update, delete on contraparte_confirmada to service_role;

-- ---------------------------------------------------------------------------
-- 3. CONFIRMAR, REVOGAR E LISTAR
-- ---------------------------------------------------------------------------
create function fn_contraparte_confirmar(p_caso uuid, p_tipo_base text, p_contraparte text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_nome  text;
  v_id    uuid;
begin
  -- Quem não escreve o mandato (Leitura, Analista de outro mandato, sem papel, anônimo e conexão de serviço: sem auth.uid() não há autor) cai aqui,
  -- com a MESMA mensagem para "mandato que não existe" e "mandato que não é seu": a recusa não conta quais mandatos existem.
  if p_caso is null or not fn_pode_escrever_caso(p_caso) then
    raise exception 'Confirmar contraparte exige ser Sócio ou Analista alocado neste mandato' using errcode = '42501';
  end if;
  if p_tipo_base is null or p_tipo_base not in ('contas_a_receber', 'contas_a_pagar') then
    raise exception 'tipo_base "%" não existe (contas_a_receber ou contas_a_pagar)', p_tipo_base using errcode = '22023';
  end if;
  v_nome := fn_texto_normalizado(p_contraparte);
  if v_nome = '' then
    raise exception 'A contraparte está vazia (depois de tirar espaços): sem nome não há o que confirmar' using errcode = '22023';
  end if;
  if not exists (select 1 from caso where id = p_caso) then
    raise exception 'O mandato % não existe', p_caso using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_caso::text || ':' || p_tipo_base || ':' || v_nome, 0));
  select id into v_id from contraparte_confirmada
   where caso_id = p_caso and tipo_base = p_tipo_base and contraparte = v_nome and revogado_em is null;
  if v_id is not null then
    return jsonb_build_object('id', v_id, 'contraparte', v_nome, 'ja_vigente', true);
  end if;
  insert into contraparte_confirmada (caso_id, tipo_base, contraparte, confirmado_por)
  values (p_caso, p_tipo_base, v_nome, auth.uid()) returning id into v_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values ('usuario:' || auth.uid(), 'contraparte_confirmada', 'caso:' || p_caso,
          jsonb_build_object('id', v_id, 'tipo_base', p_tipo_base, 'contraparte', v_nome));
  return jsonb_build_object('id', v_id, 'contraparte', v_nome, 'ja_vigente', false);
end $$;

comment on function fn_contraparte_confirmar(uuid, text, text) is
  '0273: o analista confirma que a contraparte (com nome de total) é cliente/fornecedor de verdade NESTE mandato. Só quem escreve o mandato (fn_pode_escrever_caso: Sócio, Analista alocado); Leitura, outro mandato, sem papel, anônimo e conexão de serviço recebem 42501. Normaliza o nome no banco; vazio = 22023. Já vigente: não duplica, não muda autor/data, não grava evento (ja_vigente = true). Grava contraparte_confirmada em evento_auditoria (caso:<id>). Devolve {id, contraparte, ja_vigente}.';

create function fn_contraparte_revogar(p_caso uuid, p_tipo_base text, p_contraparte text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_nome text;
  v_id   uuid;
begin
  if p_caso is null or not fn_pode_escrever_caso(p_caso) then
    raise exception 'Revogar contraparte exige ser Sócio ou Analista alocado neste mandato' using errcode = '42501';
  end if;
  if p_tipo_base is null or p_tipo_base not in ('contas_a_receber', 'contas_a_pagar') then
    raise exception 'tipo_base "%" não existe (contas_a_receber ou contas_a_pagar)', p_tipo_base using errcode = '22023';
  end if;
  v_nome := fn_texto_normalizado(p_contraparte);
  if v_nome = '' then
    raise exception 'A contraparte está vazia (depois de tirar espaços): sem nome não há o que revogar' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_caso::text || ':' || p_tipo_base || ':' || v_nome, 0));
  update contraparte_confirmada set revogado_em = now(), revogado_por = auth.uid()
   where caso_id = p_caso and tipo_base = p_tipo_base and contraparte = v_nome and revogado_em is null
  returning id into v_id;
  if v_id is null then
    -- Revogar o que não está confirmado não é "feito": o portal diria que desfez uma confirmação que nunca existiu (a lição do DELETE de 0 linhas, 0216).
    raise exception 'Não há confirmação vigente de "%" (%) neste mandato para revogar', v_nome, p_tipo_base using errcode = 'P0002';
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values ('usuario:' || auth.uid(), 'contraparte_revogada', 'caso:' || p_caso,
          jsonb_build_object('id', v_id, 'tipo_base', p_tipo_base, 'contraparte', v_nome));
  return jsonb_build_object('id', v_id, 'contraparte', v_nome);
end $$;

comment on function fn_contraparte_revogar(uuid, text, text) is
  '0273: revoga a confirmação vigente da contraparte neste mandato (MARCA revogado_em/revogado_por; não apaga). Mesma guarda de fn_contraparte_confirmar (42501). Sem vigente para revogar: P0002 com o motivo. Grava contraparte_revogada em evento_auditoria (caso:<id>). Devolve {id, contraparte}.';

create function fn_contrapartes_confirmadas(p_caso uuid, p_tipo_base text) returns text[]
language plpgsql stable set search_path = public, pg_temp as $$
begin
  -- Sem acesso NÃO pode parecer "nenhuma confirmada": recusa (regra 1). O n8n (conexão de serviço) lê.
  if p_caso is null or not (fn_conexao_de_servico() or fn_pode_ler_caso(p_caso)) then
    raise exception 'Ler as contrapartes confirmadas exige acesso a este mandato' using errcode = '42501';
  end if;
  if p_tipo_base is null or p_tipo_base not in ('contas_a_receber', 'contas_a_pagar') then
    raise exception 'tipo_base "%" não existe (contas_a_receber ou contas_a_pagar)', p_tipo_base using errcode = '22023';
  end if;
  if not exists (select 1 from caso where id = p_caso) then
    raise exception 'O mandato % não existe', p_caso using errcode = 'P0002';
  end if;
  return coalesce((select array_agg(contraparte order by contraparte collate "C")
                     from contraparte_confirmada
                    where caso_id = p_caso and tipo_base = p_tipo_base and revogado_em is null), '{}'::text[]);
end $$;

comment on function fn_contrapartes_confirmadas(uuid, text) is
  '0273: os nomes NORMALIZADOS das contrapartes confirmadas e vigentes do mandato, por tipo_base, ordenados (collate "C"): é o array de `contrapartesReais` de aplicadorDeMapeamento. Invoker (a RLS vale) com guarda explícita: quem não enxerga o mandato leva 42501, nunca um array vazio. Vazio = o mandato existe, você o lê, e ninguém confirmou.';

do $$
declare f text;
begin
  foreach f in array array['fn_texto_normalizado(text)', 'fn_contraparte_confirmar(uuid, text, text)',
                           'fn_contraparte_revogar(uuid, text, text)', 'fn_contrapartes_confirmadas(uuid, text)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
    if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
      execute format('grant execute on function %s to supabase_read_only_user', f);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 4. A SONDA. Marcadores em CÓDIGO, nunca de comentário (pg_get_functiondef traz os comentários do corpo).
-- ---------------------------------------------------------------------------
create view instalacao_sonda_contraparte_uma_vigente as
  select i.indexrelid::regclass::text as indice
    from pg_index i
    join pg_class c on c.oid = i.indexrelid and c.relname = 'contraparte_confirmada_uma_vigente'
   where i.indrelid = 'public.contraparte_confirmada'::regclass
     and i.indisunique and i.indisvalid
     and i.indpred is not null
     and pg_get_indexdef(i.indexrelid) like '%(caso_id, tipo_base, contraparte)%'
     and pg_get_expr(i.indpred, i.indrelid) like '%revogado_em IS NULL%';
comment on view instalacao_sonda_contraparte_uma_vigente is
  'Sonda da 0273: uma linha = o índice único parcial (caso_id, tipo_base, contraparte) where revogado_em is null existe e é válido. Zero linhas: o banco deixou de garantir uma só confirmação vigente por contraparte e mandato.';
grant select on instalacao_sonda_contraparte_uma_vigente to authenticated, service_role;

create view instalacao_sonda_contraparte_checks as
  select count(*)::text as n
    from pg_constraint k
   where k.conrelid = 'public.contraparte_confirmada'::regclass and k.contype = 'c' and k.convalidated
     and ((k.conname = 'contraparte_normalizada' and pg_get_constraintdef(k.oid) like '%fn_texto_normalizado(%')
       or (k.conname = 'contraparte_revogacao_inteira' and pg_get_constraintdef(k.oid) like '%revogado_em IS NULL%'))
  having count(*) = 2;
comment on view instalacao_sonda_contraparte_checks is
  'Sonda da 0273: uma linha = as duas CHECKs (nome normalizado e não vazio; revogação com autor) existem, validadas. Zero linhas: o service_role grava contraparte que o aplicador nunca casaria (caixa de espaço, NFD) ou revogação sem autor.';
grant select on instalacao_sonda_contraparte_checks to authenticated, service_role;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('contraparte_tabela', '0273', 'tabela', 'contraparte_confirmada', null, null,
   'Onde a confirmação do analista (esta contraparte com nome de total é cliente de verdade) é guardada, por mandato. Ausente = a 0273 não foi aplicada: a linha de cliente com nome de total continua rejeitada pelo aplicador sem saída.',
   'importante', 1320),
  ('contraparte_confirmar_funcao', '0273', 'funcao', 'fn_contraparte_confirmar', null, null,
   'A porta de escrita da confirmação (o authenticated não tem grant nem policy de escrita na tabela). Ausente = ninguém confirma.',
   'importante', 1321),
  ('contraparte_revogar_funcao', '0273', 'funcao', 'fn_contraparte_revogar', null, null,
   'A porta de revogação. Ausente = uma confirmação feita por engano não tem como ser desfeita pelo portal.',
   'importante', 1322),
  ('contraparte_listar_funcao', '0273', 'funcao', 'fn_contrapartes_confirmadas', null, null,
   'A leitura das vigentes do mandato por tipo_base (o array de contrapartesReais). Ausente = o aplicador não recebe as confirmações e rejeita toda linha com nome de total.',
   'importante', 1323),
  ('contraparte_normalizacao_funcao', '0273', 'funcao', 'fn_texto_normalizado', null, null,
   'A normalização do nome calculada pelo banco. Ausente = a tabela (CHECK) e as funções não existem em estado completo.',
   'importante', 1324),
  ('contraparte_confirmar_escreve_mandato', '0273', 'corpo', 'fn_contraparte_confirmar', 'not fn_pode_escrever_caso(p_caso)', null,
   'Só quem escreve o mandato confirma. Corpo sem isto = a Leitura, o Analista de OUTRO mandato e quem não tem papel decidem o que o aplicador trata como cliente no aging de um mandato que não é deles.',
   'bloqueante', 1325),
  ('contraparte_revogar_escreve_mandato', '0273', 'corpo', 'fn_contraparte_revogar', 'not fn_pode_escrever_caso(p_caso)', null,
   'Só quem escreve o mandato revoga. Corpo sem isto = qualquer papel desfaz a confirmação de um mandato alheio e o total volta a ser rejeitado (ou o contrário) sem ninguém saber.',
   'bloqueante', 1326),
  ('contraparte_listar_le_mandato', '0273', 'corpo', 'fn_contrapartes_confirmadas', 'fn_pode_ler_caso(p_caso)', null,
   'Quem não enxerga o mandato é recusado (42501), não recebe array vazio. Corpo sem isto = "sem acesso" aparece como "nenhuma confirmada" e o aplicador rejeita toda linha com nome de total.',
   'importante', 1327),
  ('contraparte_normalizacao_nfc', '0273', 'corpo', 'fn_texto_normalizado', ', NFC)', null,
   'A normalização do nome é em NFC, como a biblioteca. Corpo sem isto = o nome confirmado com acento decomposto (NFD) não casa com o da linha e a confirmação não vale.',
   'importante', 1328),
  ('contraparte_leitura_policy', '0273', 'policy', 'contraparte_confirmada.contraparte_confirmada_read', null, null,
   'RLS ligada sem policy de leitura devolve zero calado: a confirmação pareceria nunca ter existido.',
   'importante', 1329),
  ('contraparte_uma_vigente', '0273', 'comportamento', 'instalacao_sonda_contraparte_uma_vigente', null, 1,
   'O índice único parcial que garante UMA vigente por (mandato, tipo_base, contraparte). Zero linhas = confirmações duplicadas e uma revogação deixa a outra vigente.',
   'importante', 1330),
  ('contraparte_checks', '0273', 'comportamento', 'instalacao_sonda_contraparte_checks', null, 1,
   'As CHECKs da tabela (nome normalizado; revogação com autor). Zero linhas = o service_role grava nome fora da forma que o aplicador compara.',
   'importante', 1331)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0273', revisado_em = current_date,
       observacao = 'A 0273 cria contraparte_confirmada (a contraparte com nome de total que o analista confirmou como cliente/fornecedor, POR MANDATO, RLS da 0216), fn_contraparte_confirmar, fn_contraparte_revogar, fn_contrapartes_confirmadas e fn_texto_normalizado. 12 requisitos novos (ordem 1320-1331).'
 where id = true;

commit;
