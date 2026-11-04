-- Testes do tipo `gatilho` da sonda de instalação (Supabase/migrations/0189).
-- Rodar via Supabase/test/run.sh (que aplica TODAS as migrations antes).
--
-- O DEFEITO QUE ISTO FECHA, medido antes da 0189: `fn_instalacao_conferir()`
-- catalogava gatilho pela existência da FUNÇÃO chamada — e a função sobrevive
-- a `drop trigger` e a `alter table ... disable trigger`. O exemplo já estava
-- no catálogo: `gatilho_da_promocao` (0137, tipo funcao, objeto
-- `fn_trg_auto_promover_dial`), cujo `porque` diz "a função de promoção existe
-- e NADA a chama" — e a sonda de tipo `funcao` confere exatamente a função.
-- MEDIDO, com a 0189: derrubar as guardas por gatilho (eram seis; nove depois da F1.7) NÃO mudava a
-- contagem de ausentes antes desta migration; com ela, muda — é o que os casos
-- b, c, d e e abaixo provam um a um.
--
-- CADA CASO RODA NA PRÓPRIA TRANSAÇÃO (`begin; ... rollback;`), porque DDL é
-- transacional no Postgres: `drop trigger`, `disable trigger` e
-- `enable replica trigger` desfazem no `rollback` tão limpo quanto um insert.
-- Isso torna os casos INDEPENDENTES — o caso e não precisa que b/c/d já
-- tenham rodado, e um caso que falha não contamina o próximo.
--
-- O QUE CADA CASO PROVA:
--
--   a. o banco recém-migrado tem ≥9 requisitos `gatilho`, todos presentes —
--      guarda contra catálogo vazio (fixture que "passa" por não ter nada
--      para reprovar é o defeito da própria `estagio-desligado-parece-limpo`).
--   b. `drop trigger` num gatilho: a sonda acusa EXATAMENTE aquele requisito,
--      com detalhe que nomeia que a função pode sobreviver — e a contagem de
--      ausentes de tipo gatilho sobe em 1.
--   c. `disable trigger`: acusa ausente, detalhe cita "DESABILITADO".
--   d. `enable replica trigger`: acusa ausente — decisão deliberada da 0189,
--      mais estrita que `tgenabled <> 'D'`, porque `'R'` não dispara na sessão
--      normal (`session_replication_role = origin`, o padrão).
--   e. os nove gatilhos de uma vez: a contagem de ausentes sobe em exatamente
--      9 — o religamento por MIGRATION completa, não só por gatilho isolado.
--   f. a sonda não morre: requisito fabricado com tabela inexistente, e com
--      nome de gatilho inexistente numa tabela que existe — as duas devolvem
--      `presente=false`, nenhuma derruba a função.
--   g. o elo com o que a guarda protege: com o gatilho presente, renomear uma
--      rodada golden CONGELADA é recusado; sem ele, o mesmo update é aceito
--      E a sonda acusa — prova que "ausente na sonda" corresponde a "a guarda
--      não roda", não só a uma leitura de catálogo desacoplada do efeito real.
--
-- RELIGAMENTO — os dois desligamentos da correção foram MEDIDOS (números no
-- corpo do commit que introduziu este arquivo):
--
--   * o ramo `gatilho` devolvendo `v_ok := true` sem consultar `pg_trigger`
--     (simula "a sonda não olha gatilho"): 6 FALHOU, os seis casos b–g, 6 ok
--     (os três de a, o de a2 e os dois primeiros de g, que não dependem da
--     sonda ter ramo de gatilho) —
--     b/c/d/e porque a sonda para de acusar o gatilho ausente, f porque o
--     requisito sobre tabela inexistente vira "presente", g porque o último
--     assert (a sonda acusa depois do drop) cai.
--   * o ramo aceitando 'R' junto com 'O'/'A' (equivale a `tgenabled <> 'D'`):
--     1 FALHOU, 15 ok — o caso d sozinho, o único que distingue 'R' de 'O'/'A'.
--   COMO FOI MEDIDO, para reproduzir: a linha `\set ON_ERROR_STOP on` abaixo
--   SOBRESCREVE o `-v ON_ERROR_STOP=0` da linha de comando, então ela foi
--   removida na medição (`sed 's/^\\set ON_ERROR_STOP.*//' arquivo | psql -v
--   ON_ERROR_STOP=0`). Cada bloco `do` para no primeiro assert que falha: o
--   número acima conta BLOCOS reprovados, não asserts. Ligado: 17 ok, 0 FALHOU.
--   Só 'O' aceito (sem 'A'): 1 FALHOU (a2), 16 ok. Gatilho criado fora do
--   catálogo: 1 FALHOU (a, igualdade de conjuntos). Remedido em 24/09 com 17
--   asserts, pela revisão independente e pela sessão principal.

\set ON_ERROR_STOP on

create or replace function teste_assert_gat(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- a. banco completo: todo requisito gatilho presente, e existem ≥9.
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_ausentes text;
  v_n        int;
begin
  select string_agg(chave, ', ' order by chave) into v_ausentes
    from fn_instalacao_conferir() where tipo = 'gatilho' and not presente;

  perform teste_assert_gat(v_ausentes is null,
    'a. num banco recém-migrado, todo requisito de gatilho está presente',
    coalesce(v_ausentes, ''));

  select count(*)::int into v_n from instalacao_requisito where tipo = 'gatilho';
  perform teste_assert_gat(v_n >= 9,
    'a. existem pelo menos 9 requisitos de gatilho catalogados (guarda contra catálogo vazio)',
    format('%s encontrado(s)', v_n));

  -- COMPLETUDE, em igualdade de conjuntos. Achado da revisão: com só `>= 6`,
  -- uma migration nova que crie gatilho (a F1.7, PR #238, cria dois) entraria
  -- sem requisito e nada acusaria — a obrigação ficaria só num comentário.
  -- Todo gatilho não-interno do banco montado do zero tem de estar catalogado,
  -- e todo requisito de gatilho tem de apontar para um gatilho que existe.
  select string_agg(x, ', ' order by x) into v_ausentes from (
    (select t.tgrelid::regclass::text || '.' || t.tgname as x
       from pg_trigger t where not t.tgisinternal
         -- 0224: o gatilho de auditoria em storage.objects NÃO cabe no tipo `gatilho` (que só resolve tabelas de `public`): ele é catalogado
         -- por view + tipo `comportamento`, e a cobertura dele é afirmada em original_apagado.test.sql (todo gatilho do schema storage tem linha na view).
         and t.tgrelid::regclass::text not like 'storage.%'
     except
     select objeto from instalacao_requisito where tipo = 'gatilho')
    union all
    (select objeto from instalacao_requisito where tipo = 'gatilho'
     except
     select t.tgrelid::regclass::text || '.' || t.tgname
       from pg_trigger t where not t.tgisinternal)) d;
  perform teste_assert_gat(v_ausentes is null,
    'a. todo gatilho não-interno do banco tem requisito tipo gatilho, e vice-versa',
    'fora do catálogo ou sem gatilho: ' || coalesce(v_ausentes, '') ||
    ' — catalogue-o em instalacao_requisito com tipo = ''gatilho''');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- a2. ENABLE ALWAYS dispara em sessão normal: continua PRESENTE. Achado da
-- revisão: sem este caso, "endurecer" o ramo para só 'O' faria um gatilho em
-- modo ALWAYS (comum com replicação lógica) virar ausência FALSA sem nenhum
-- assert reprovar.
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_presente boolean;
begin
  execute 'alter table golden_campo enable always trigger trg_golden_campo_congelada';
  select presente into v_presente
    from fn_instalacao_conferir() where chave = 'gatilho_guarda_campo_congelada';
  perform teste_assert_gat(coalesce(v_presente, false),
    'a2. enable ALWAYS trigger: a sonda continua dizendo presente (ele dispara na sessão normal)');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- b. drop trigger derruba SÓ o requisito daquele gatilho, e sobe a contagem em 1.
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_ausentes_antes  int;
  v_ausentes_depois int;
  v_presente        boolean;
  v_detalhe         text;
begin
  select count(*)::int into v_ausentes_antes
    from fn_instalacao_conferir() where tipo = 'gatilho' and not presente;

  execute 'drop trigger trg_golden_rodada_imutavel on golden_rodada';

  select presente, detalhe into v_presente, v_detalhe
    from fn_instalacao_conferir() where chave = 'gatilho_guarda_rodada_congelada';

  perform teste_assert_gat(v_presente is not null and not v_presente,
    'b. drop trigger: a sonda acusa presente=false exatamente neste requisito');
  perform teste_assert_gat(
    v_detalhe = 'o gatilho não existe na tabela (a função dele pode existir — ela sobrevive ao drop trigger)',
    'b. …e o detalhe nomeia que a função pode sobreviver ao drop trigger',
    coalesce(v_detalhe, '<null>'));

  select count(*)::int into v_ausentes_depois
    from fn_instalacao_conferir() where tipo = 'gatilho' and not presente;

  perform teste_assert_gat(v_ausentes_depois = v_ausentes_antes + 1,
    'b. a contagem de ausentes de tipo gatilho sobe em exatamente 1',
    format('antes=%s depois=%s', v_ausentes_antes, v_ausentes_depois));
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- c. disable trigger acusa ausente, com detalhe citando "desabilitado".
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_presente boolean;
  v_detalhe  text;
begin
  execute 'alter table golden_campo disable trigger trg_golden_campo_congelada';

  select presente, detalhe into v_presente, v_detalhe
    from fn_instalacao_conferir() where chave = 'gatilho_guarda_campo_congelada';

  perform teste_assert_gat(v_presente is not null and not v_presente,
    'c. disable trigger: a sonda acusa ausente');
  perform teste_assert_gat(v_detalhe like '%DESABILITADO%disable trigger%',
    'c. …e o detalhe cita "DESABILITADO (disable trigger)"',
    coalesce(v_detalhe, '<null>'));
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- d. enable replica trigger acusa ausente — decisão deliberada: 'R' não
--    dispara em sessão normal (session_replication_role = origin, o padrão).
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_presente boolean;
  v_detalhe  text;
begin
  execute 'alter table golden_documento enable replica trigger trg_golden_documento_congelada';

  select presente, detalhe into v_presente, v_detalhe
    from fn_instalacao_conferir() where chave = 'gatilho_guarda_documento_congelada';

  perform teste_assert_gat(v_presente is not null and not v_presente,
    'd. enable replica trigger: a sonda acusa ausente (mais estrita que <> ''D''  )');
  perform teste_assert_gat(v_detalhe like '%modo réplica%',
    'd. …e o detalhe explica que só dispara em modo réplica',
    coalesce(v_detalhe, '<null>'));
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- e. os nove gatilhos de uma vez: a contagem de ausentes sobe em exatamente 9.
--    Inclui os três da F1.7 — os mesmos da medição original de 23/09/2026,
--    que derrubava as três guardas dela e via o painel continuar verde.
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_pares           text[][] := array[
    array['golden_rodada',    'trg_golden_rodada_imutavel'],
    array['golden_documento', 'trg_golden_documento_congelada'],
    array['golden_rotulo',    'trg_golden_rotulo_congelada'],
    array['golden_campo',     'trg_golden_campo_congelada'],
    array['decisao',          'trg_auto_promover_dial'],
    array['documento',        'trg_entidade_ambigua'],
    array['entidade_controlador', 'trg_entidade_controlador_soma_maxima'],
    array['entidade',             'trg_entidade_forma_de_controle_tem_vinculo'],
    array['instalacao_cobertura', 'trg_instalacao_cobertura_nao_regride']
  ];
  v_par             text[];
  v_ausentes_antes  int;
  v_ausentes_depois int;
begin
  select count(*)::int into v_ausentes_antes
    from fn_instalacao_conferir() where tipo = 'gatilho' and not presente;

  foreach v_par slice 1 in array v_pares loop
    execute format('drop trigger %I on %I', v_par[2], v_par[1]);
  end loop;

  select count(*)::int into v_ausentes_depois
    from fn_instalacao_conferir() where tipo = 'gatilho' and not presente;

  perform teste_assert_gat(v_ausentes_depois = v_ausentes_antes + 9,
    'e. derrubar os nove gatilhos de uma vez sobe a contagem de ausentes em exatamente 9',
    format('antes=%s depois=%s', v_ausentes_antes, v_ausentes_depois));
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- f. a sonda não morre com o que ela mede: tabela inexistente e gatilho
--    inexistente numa tabela que existe devolvem presente=false, sem exceção.
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_presente boolean;
begin
  insert into instalacao_requisito (chave, migration, tipo, objeto, porque, severidade, ordem)
  values ('_teste_gatilho_tabela_ausente', '9999', 'gatilho', 'tabela_que_nao_existe.trg_x',
          'Requisito fabricado pelo teste.', 'informativo', 9999);

  select presente into v_presente
    from fn_instalacao_conferir() where chave = '_teste_gatilho_tabela_ausente';

  perform teste_assert_gat(v_presente is not null and not v_presente,
    'f. requisito de gatilho sobre tabela inexistente devolve presente=false em vez de derrubar a sonda');

  insert into instalacao_requisito (chave, migration, tipo, objeto, porque, severidade, ordem)
  values ('_teste_gatilho_nome_ausente', '9999', 'gatilho', 'golden_rodada.trg_que_nunca_existiu',
          'Requisito fabricado pelo teste.', 'informativo', 9999);

  select presente into v_presente
    from fn_instalacao_conferir() where chave = '_teste_gatilho_nome_ausente';

  perform teste_assert_gat(v_presente is not null and not v_presente,
    'f. …e gatilho inexistente numa tabela que EXISTE também devolve presente=false');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- g. o elo com o que a guarda protege: com o gatilho presente, renomear uma
--    rodada congelada é recusado; sem ele, o mesmo update é aceito E a sonda
--    acusa — "ausente na sonda" corresponde a "a guarda não roda".
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_rodada     uuid;
  v_presente   boolean;
  v_recusou    boolean := false;
  v_nome_final text;
begin
  insert into golden_rodada (nome, taxonomia_versao, criada_por, congelada_em, congelada_por)
  values ('_teste_gatilho_g', 1, 'teste', now(), 'teste')
  returning id into v_rodada;

  -- com o gatilho presente, renomear é recusado (exceção do gatilho da 0126).
  begin
    update golden_rodada set nome = '_teste_gatilho_g_renomeada' where id = v_rodada;
  exception when others then
    v_recusou := true;
  end;
  perform teste_assert_gat(v_recusou,
    'g. com o gatilho presente, renomear rodada golden CONGELADA é recusado');

  -- derruba o gatilho.
  execute 'drop trigger trg_golden_rodada_imutavel on golden_rodada';

  -- agora o MESMO update é aceito.
  update golden_rodada set nome = '_teste_gatilho_g_renomeada' where id = v_rodada;
  select nome into v_nome_final from golden_rodada where id = v_rodada;
  perform teste_assert_gat(v_nome_final = '_teste_gatilho_g_renomeada',
    'g. sem o gatilho, o mesmo update é aceito (a guarda não roda mais)',
    coalesce(v_nome_final, '<null>'));

  -- e a sonda acusa o requisito, exatamente quando a guarda parou de recusar.
  select presente into v_presente
    from fn_instalacao_conferir() where chave = 'gatilho_guarda_rodada_congelada';
  perform teste_assert_gat(v_presente is not null and not v_presente,
    'g. …e a sonda acusa "ausente" exatamente quando a guarda deixou de recusar '
    '(ausente-na-sonda == guarda-não-roda, não uma leitura de catálogo desacoplada do efeito)');
end $$;
rollback;

do $$
begin
  raise notice 'sonda_ve_gatilho OK — gatilho é catalogado por si; drop/disable/replica acusam; a sonda '
               'não morre; e o ausente corresponde ao efeito real da guarda';
end $$;

drop function teste_assert_gat(boolean, text, text);
