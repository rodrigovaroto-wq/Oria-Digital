-- Testes da 0300: fn_kit_do_caso (o estado do item do Kit Básico derivado na leitura), a chave estável da pendência item_faltante,
-- o documento que a fechou e o evento completude_recomputada gravado sempre. Rodar via Supabase/test/run.sh (que aplica as migrations).
--
-- O QUE ESTE ARQUIVO PROVA (comportamento, regra 3 — nenhum assert descreve COMO o código decide):
--   I1.1  documento cuja versão vigente tem zero linha nunca aparece como extraido/conferido nem conta como atendido;
--   I1.2  versão cuja linha só foi aceita pelo auto-aceite do sistema fica `extraido`, não `conferido`; aceite de PESSOA em toda
--         linha a leva a `conferido`, com quem e quando;
--   I1.3  chega documento que serve: a item_faltante resolve com o id desse documento; reclassificado para outro tipo, a pendência
--         reabre (nova);
--   I1.4  entre o registro e a gravação das linhas o item é `aguardando_extracao`;
--   I1.5  conferência sem nada a mudar grava um evento com contagens zero; documento criado depois dele aparece em
--         `documentos_depois_da_conferencia`;
--   I1.8  reescrever a descrição de uma item_faltante aberta não cria outra nem a resolve;
--   D1.3  o documento que chega resolve também a decidida por pessoa, e o evento guarda o estado anterior e quem decidiu;
--   o item_faltante de OUTRO assunto (contrato_social_ausente) não é resolvido pela conferência do Kit;
--   "N de M empresas" (D1.2), isolamento por mandato COMO authenticated (mandato invisível = zero linhas, nunca "tudo faltante"),
--   grants e a sonda.
-- Regra 4: o defeito de produção (267 linhas `presente` sem linha lida) NÃO é reproduzido com dado fabricado; o arranjo real (registrar o
-- documento e não gravar a extração) é montado pelas funções de produção, e o assert afirma só o que dele se prova. A única linha de
-- fixture escrita à mão é a item_faltante SEM chave (formato anterior à 0300, o mesmo das 205 abertas de produção).
--
-- Cada bloco `do` é uma transação própria: o `now()` do Postgres é o do início da transação, e "documento criado depois da última
-- conferência" só existe entre transações distintas.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): o número reprovado por correção desligada está no cabeçalho da migration 0300. `ct300.medindo = on`
-- (PGOPTIONS='-c ct300.medindo=on') vira `raise warning` e CONTA (ct300.execucoes / ct300.falhas); sem a variável, o assert é `raise exception`.

\set ON_ERROR_STOP on

create or replace function teste_assert_0300(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('ct300.execucoes', (coalesce(nullif(current_setting('ct300.execucoes', true), ''), '0')::int + 1)::text, false);
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  elsif current_setting('ct300.medindo', true) = 'on' then
    perform set_config('ct300.falhas', (coalesce(nullif(current_setting('ct300.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- Executa a expressão COMO o papel (authenticated com o JWT do usuário; NULL = sem sub) e volta ao superusuário. Devolve 'ok|<resultado>'
-- ou '<sqlstate>|<mensagem>'. SQL dinâmico (ver 0274/0276).
create or replace function teste_exec_0300(p_uid uuid, p_papel text, p_expr text)
returns text language plpgsql as $$
declare v_r text; v_out text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then jsonb_build_object('role', p_papel)::text
                     else jsonb_build_object('sub', p_uid, 'role', p_papel)::text end, true);
  execute format('set local role %I', p_papel);
  begin
    execute 'select (' || p_expr || ')::text' into v_r;
    v_out := 'ok|' || coalesce(v_r, 'NULL');
  exception when others then
    v_out := sqlstate || '|' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
  return v_out;
end $$;

-- O estado de um item do mandato, como a tela o leria. NULL = o item não veio.
create or replace function teste_kit_0300(p_caso uuid, p_tipo text) returns text
language sql as $$ select estado from fn_kit_do_caso(p_caso) where tipo = p_tipo $$;

delete from caso where nome like '0300 —%';
delete from auth.users where id in ('00000000-0000-0000-0000-00000300b001', '00000000-0000-0000-0000-00000300b002',
  '00000000-0000-0000-0000-00000300b003', '00000000-0000-0000-0000-00000300b004');

-- Linhas de extração no formato de produção. `p_conf` decide se o auto-aceite (dial N2, limiar 0,95) as pega.
create or replace function teste_linhas_0300(p_n int, p_conf numeric) returns jsonb
language sql as $$
  select jsonb_agg(jsonb_build_object('ordem', g, 'chave', 'Conta ' || g, 'valor_texto', (g * 100)::text, 'valor_num', (g * 100)::text,
                                      'unidade', 'unidade', 'moeda', 'BRL', 'confianca', p_conf::text, 'secao_canonica', 'ativo_circulante'))
    from generate_series(1, p_n) g $$;

-- =============================================================================================================================
-- BLOCO 1 — aguardando, sem linha, "N de M empresas", e o sinal de que a conferência nunca rodou
-- =============================================================================================================================
do $$
declare
  v_caso uuid; r jsonb; v_ver uuid; v_doc uuid; k record; v_t text; v_n int;
begin
  raise notice '--- 1. registrado e não lido: aguardando_extracao; falha: recebido_sem_linha; nunca atendido ---';
  v_caso := fn_upsert_caso('0300 — bloco 1 aguardando e sem linha');
  r := fn_registrar_documento(v_caso, 'Alfa 0300 Ltda', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0300/b1.pdf', 'b1.pdf', true, 'HASH-0300-B1', 'ok');
  v_ver := (r ->> 'documento_versao_id')::uuid; v_doc := (r ->> 'documento_id')::uuid;

  -- O arranjo REAL do defeito de produção: o checklist nasce `presente` no registro, antes de existir uma linha lida.
  perform teste_assert_0300((select status from checklist_item_status where documento_id = v_doc) = 'presente'
                            and not exists (select 1 from campo_extraido where documento_versao_id = v_ver),
    'o arranjo: o checklist diz presente e a versão não tem NENHUMA linha (é o que 267 linhas de produção mostram)', null);

  select count(*) into v_n from fn_kit_do_caso(v_caso);
  perform teste_assert_0300(v_n = (select count(*) from taxonomia_tipo_documento where obrigatoriedade = 'obrigatorio'),
    'o Kit devolve UMA linha por tipo obrigatório da taxonomia', v_n::text);
  perform teste_assert_0300(not exists (select 1 from fn_kit_do_caso(v_caso) f
                                         join taxonomia_tipo_documento t on t.codigo = f.tipo where t.obrigatoriedade <> 'obrigatorio'),
    'e nenhum tipo complementar', null);

  perform teste_assert_0300(teste_kit_0300(v_caso, 'BALANCO') = 'aguardando_extracao',
    'I1.4: entre o registro e a gravação das linhas, o item é aguardando_extracao', teste_kit_0300(v_caso, 'BALANCO'));
  perform teste_assert_0300(teste_kit_0300(v_caso, 'BALANCO') not in ('recebido_sem_linha', 'extraido', 'conferido'),
    'I1.1/I1.4: nunca recebido_sem_linha, extraido nem conferido enquanto a leitura não terminou', teste_kit_0300(v_caso, 'BALANCO'));
  perform teste_assert_0300(teste_kit_0300(v_caso, 'DRE') = 'faltante', 'o tipo sem documento é faltante', teste_kit_0300(v_caso, 'DRE'));

  select * into k from fn_kit_do_caso(v_caso) where tipo = 'BALANCO';
  perform teste_assert_0300(k.motivo like 'Recebido, mas a leitura ainda não terminou%' and k.motivo like '%o book sai vazio%',
    'o motivo diz o porquê E o efeito (regra 1: ausência não é dado)', k.motivo);
  perform teste_assert_0300(k.documentos = array[v_doc] and k.docs_por_estado = '{"aguardando_extracao": 1}'::jsonb,
    'os documentos do item e a conta por estado', k.docs_por_estado::text);
  perform teste_assert_0300(k.empresas_total = 1 and k.empresas_com_documento = 1 and k.empresas_atendidas = 0,
    'D1.2 N de M: 1 empresa no mandato, 1 com documento recebido e 0 com documento LIDO',
    format('%s/%s/%s', k.empresas_total, k.empresas_com_documento, k.empresas_atendidas));

  -- I1.5 (primeira metade): a conferência nunca rodou neste mandato (fn_registrar_documento não a chama).
  perform teste_assert_0300(k.conferencia_em is null and k.documentos_depois_da_conferencia = 1,
    'I1.5: conferência que nunca rodou = conferencia_em nulo e TODOS os documentos contam como "chegaram depois"',
    format('%s / %s', k.conferencia_em, k.documentos_depois_da_conferencia));

  -- A leitura termina SEM linha e com falha registrada.
  perform fn_registrar_campos_extraidos(v_ver, '[]'::jsonb, 'N0', 'Arquivo ilegível: a leitura não devolveu nenhuma conta.');
  perform teste_assert_0300(exists (select 1 from pendencia where documento_id = v_doc and tipo = 'extracao_falhou' and estado <> 'resolvida'),
    'o arranjo: a falha de extração ficou aberta', null);
  perform teste_assert_0300(teste_kit_0300(v_caso, 'BALANCO') = 'recebido_sem_linha',
    'I1.1: documento cuja versão vigente tem zero linha é recebido_sem_linha', teste_kit_0300(v_caso, 'BALANCO'));
  select * into k from fn_kit_do_caso(v_caso) where tipo = 'BALANCO';
  perform teste_assert_0300(k.motivo like '%nenhuma linha foi lida%VAZIO%' and k.empresas_com_documento = 1 and k.empresas_atendidas = 0,
    'I1.1: não conta como atendido (0 empresas com documento LIDO), e o motivo nomeia o efeito', k.motivo);
  perform teste_assert_0300(k.documentos_depois_da_conferencia = 0 and k.conferencia_em is not null,
    'I1.5: a conferência rodou na extração; o documento NÃO chegou depois dela', format('%s / %s', k.conferencia_em, k.documentos_depois_da_conferencia));
end $$;

-- =============================================================================================================================
-- BLOCO 2 — extraido x conferido: o auto-aceite do sistema NÃO conta; aceite de pessoa conta
-- =============================================================================================================================
do $$
declare
  v_caso uuid; r jsonb; v_ver uuid; v_doc uuid; k record; v_n int; v_auto int;
  v_ver2 uuid; v_ver_n uuid;
begin
  raise notice '--- 2. extraido x conferido ---';
  v_caso := fn_upsert_caso('0300 — bloco 2 extraido e conferido');

  -- DRE: linhas de confiança 0,98 -> o auto-aceite do sistema as aceita (dial N2). É o caso de 1.443 das 1.648 versões de produção.
  r := fn_registrar_documento(v_caso, 'Alfa 0300 Ltda', 'anual', '2025', 'DRE', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0300/dre.pdf', 'dre.pdf', true, 'HASH-0300-DRE', 'ok');
  v_ver := (r ->> 'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, teste_linhas_0300(2, 0.98), 'N0');
  select count(*) into v_auto from campo_extraido where documento_versao_id = v_ver and status_aceite = 'aceito' and aceito_por like 'sistema:auto_aceite%';
  perform teste_assert_0300(v_auto = 2, 'o arranjo: as 2 linhas foram aceitas pelo SISTEMA (auto-aceite), não por pessoa', v_auto::text);
  perform teste_assert_0300(teste_kit_0300(v_caso, 'DRE') = 'extraido',
    'I1.2: todas as linhas aceitas SÓ pelo auto-aceite = extraido, não conferido', teste_kit_0300(v_caso, 'DRE'));
  select * into k from fn_kit_do_caso(v_caso) where tipo = 'DRE';
  perform teste_assert_0300(k.conferido_por is null and k.conferido_em is null and k.empresas_atendidas = 1,
    'e ninguém consta como quem conferiu, mas a empresa conta como LIDA (N de M)', coalesce(k.conferido_por, '(nulo)'));

  -- BALANCO: linhas de confiança 0,5 ficam pendentes; a pessoa aceita pelo caminho que o portal usa (fn_aceitar_extracao).
  r := fn_registrar_documento(v_caso, 'Alfa 0300 Ltda', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0300/bp.pdf', 'bp.pdf', true, 'HASH-0300-BP', 'ok');
  v_ver2 := (r ->> 'documento_versao_id')::uuid; v_doc := (r ->> 'documento_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver2, teste_linhas_0300(2, 0.5), 'N0');
  perform teste_assert_0300(teste_kit_0300(v_caso, 'BALANCO') = 'extraido', 'linhas pendentes: extraido, não conferido', teste_kit_0300(v_caso, 'BALANCO'));
  perform fn_aceitar_extracao(v_ver2, 'analista@oria', 'conferi');
  perform teste_assert_0300(teste_kit_0300(v_caso, 'BALANCO') = 'conferido',
    'I1.2: toda linha aceita por PESSOA = conferido', teste_kit_0300(v_caso, 'BALANCO'));
  select * into k from fn_kit_do_caso(v_caso) where tipo = 'BALANCO';
  perform teste_assert_0300(k.conferido_por = 'analista@oria' and k.conferido_em is not null and k.motivo like 'Toda linha da versão vigente foi aceita por pessoa%',
    'conferido diz QUEM e QUANDO', coalesce(k.conferido_por, '(nulo)'));

  -- Mista: uma linha auto-aceita e duas aceitas por pessoa: a do sistema impede o conferido.
  r := fn_registrar_documento(v_caso, 'Alfa 0300 Ltda', 'anual', '2025', 'FLUXO_CAIXA', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0300/fc.pdf', 'fc.pdf', true, 'HASH-0300-FC', 'ok');
  v_ver_n := (r ->> 'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver_n,
    (select jsonb_agg(l) from (select jsonb_array_elements(teste_linhas_0300(2, 0.5)) l union all
                               select jsonb_build_object('ordem', 3, 'chave', 'Conta alta', 'valor_texto', '10', 'valor_num', '10', 'unidade', 'unidade',
                                                         'moeda', 'BRL', 'confianca', '0.99', 'secao_canonica', 'ativo_circulante')) x), 'N0');
  perform fn_aceitar_extracao(v_ver_n, 'analista@oria', 'conferi');
  select count(*) into v_n from campo_extraido where documento_versao_id = v_ver_n and aceito_por like 'sistema:%';
  perform teste_assert_0300(v_n = 1 and not exists (select 1 from campo_extraido where documento_versao_id = v_ver_n and status_aceite <> 'aceito'),
    'o arranjo: todas as linhas aceitas, 1 pelo sistema e 2 por pessoa', v_n::text);
  perform teste_assert_0300(teste_kit_0300(v_caso, 'FLUXO_CAIXA') = 'extraido',
    'I1.2: UMA linha aceita pelo sistema basta para o item NÃO ser conferido', teste_kit_0300(v_caso, 'FLUXO_CAIXA'));

  -- Reextração: chega o MESMO arquivo (mesmo hash = versão nova do mesmo documento, 0026), sem aceite de pessoa: conferido volta a extraido.
  r := fn_registrar_documento(v_caso, 'Alfa 0300 Ltda', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0300/bp.pdf', 'bp.pdf', true, 'HASH-0300-BP', 'ok');
  perform teste_assert_0300((r ->> 'documento_id')::uuid = v_doc and (r ->> 'documento_versao_id')::uuid <> v_ver2 and (r ->> 'n_versao') = '2',
    'o arranjo: o mesmo documento ganhou uma versão nova', r::text);
  perform fn_registrar_campos_extraidos((r ->> 'documento_versao_id')::uuid, teste_linhas_0300(2, 0.5), 'N0');
  perform teste_assert_0300(teste_kit_0300(v_caso, 'BALANCO') = 'extraido',
    'conferido -> extraido: a versão vigente nova não tem aceite de pessoa', teste_kit_0300(v_caso, 'BALANCO'));

  -- Pior estado vence: dois documentos do mesmo tipo, um conferido e um só registrado.
  r := fn_registrar_documento(v_caso, 'Beta 0300 Ltda', 'anual', '2025', 'MUTUOS', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0300/m1.pdf', 'm1.pdf', true, 'HASH-0300-M1', 'ok');
  perform fn_registrar_campos_extraidos((r ->> 'documento_versao_id')::uuid, teste_linhas_0300(1, 0.5), 'N0');
  perform fn_aceitar_extracao((r ->> 'documento_versao_id')::uuid, 'analista@oria', 'conferi');
  perform teste_assert_0300(teste_kit_0300(v_caso, 'MUTUOS') = 'conferido', 'o arranjo: um documento conferido', teste_kit_0300(v_caso, 'MUTUOS'));
  perform fn_registrar_documento(v_caso, 'Gama 0300 Ltda', 'anual', '2025', 'MUTUOS', 0.97, 'nome_arquivo', 'supabase_storage',
                                 '0300/m2.pdf', 'm2.pdf', true, 'HASH-0300-M2', 'ok');
  select * into k from fn_kit_do_caso(v_caso) where tipo = 'MUTUOS';
  perform teste_assert_0300(k.estado = 'aguardando_extracao' and k.docs_por_estado = '{"conferido": 1, "aguardando_extracao": 1}'::jsonb,
    'o item toma o PIOR estado dos documentos (o irmão conferido não esconde o que ainda não foi lido), e a conta por estado aparece', k.docs_por_estado::text);
  perform teste_assert_0300(k.conferido_por is null, 'item que não é conferido não declara quem conferiu', coalesce(k.conferido_por, '(nulo)'));
end $$;

-- =============================================================================================================================
-- BLOCO 3 — a pendência item_faltante: chave estável, documento que fechou, decisão de pessoa, outro assunto
-- =============================================================================================================================
do $$
declare
  v_caso uuid; r jsonb; v_ver uuid; v_doc uuid; v_p uuid; v_n int; v_ev jsonb; v_antes uuid; v_ent uuid;
  v_dre_p uuid; v_res jsonb;
begin
  raise notice '--- 3. a chave estável da pendência ---';
  v_caso := fn_upsert_caso('0300 — bloco 3 pendencia por chave');
  v_res := fn_recomputar_completude(v_caso);
  perform teste_assert_0300(v_res ? 'portao1_ok' and v_res ? 'faltantes' and v_res ? 'sem_conteudo' and v_res ? 'linhas_exigidas_ausentes'
                            and v_res ? 'pronto_para_revisao' and v_res ? 'status',
    'o retorno de fn_recomputar_completude mantém as chaves de sempre (os chamadores não mudam)', v_res::text);
  select count(*) into v_n from pendencia where caso_id = v_caso and tipo = 'item_faltante' and estado = 'aberta'
     and chave_motor = 'completude:item_faltante:' || substr(descricao, length('Item obrigatório do Kit Básico ausente: ') + 1);
  perform teste_assert_0300(v_n = (select count(*) from taxonomia_tipo_documento where obrigatoriedade = 'obrigatorio'),
    'a conferência abre UMA item_faltante por tipo obrigatório, cada uma com a sua chave', v_n::text);

  -- I1.8: reescrever a frase da descrição não duplica nem resolve.
  select id into v_antes from pendencia where caso_id = v_caso and chave_motor = 'completude:item_faltante:BALANCO';
  update pendencia set descricao = 'O balanço ainda não chegou (frase reescrita depois da 0300)' where id = v_antes;
  perform fn_recomputar_completude(v_caso);
  select count(*) into v_n from pendencia where caso_id = v_caso and chave_motor = 'completude:item_faltante:BALANCO' and estado <> 'resolvida';
  perform teste_assert_0300(v_n = 1 and (select estado from pendencia where id = v_antes) = 'aberta',
    'I1.8: mudar o texto da descrição NÃO abre outra pendência nem resolve a que existe', v_n::text);

  -- O item_faltante de OUTRO assunto não é do motor do Kit.
  v_ent := fn_upsert_entidade(v_caso, 'Alfa 0300 Ltda');
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, entidade_id, motivo)
    values (v_caso, 'completude', 'item_faltante', 'importante', true,
            'Nenhum CONTRATO_SOCIAL foi recebido para "Alfa 0300 Ltda"', v_ent, 'contrato_social_ausente:' || v_ent)
    returning id into v_p;
  perform fn_recomputar_completude(v_caso);
  perform teste_assert_0300((select estado from pendencia where id = v_p) = 'aberta' and (select chave_motor from pendencia where id = v_p) is null,
    'o item_faltante de contrato social (outro assunto) sobrevive à conferência do Kit e não ganha chave', (select estado::text from pendencia where id = v_p));

  -- D1.3: a PESSOA decidiu "seguir sem" a DRE; o item vira dispensado; o documento chega e resolve, guardando a decisão no evento.
  select id into v_dre_p from pendencia where caso_id = v_caso and chave_motor = 'completude:item_faltante:DRE';
  perform fn_decidir_pendencia(v_dre_p, 'ana@oria', 'prosseguir', 'cliente não tem DRE do período');
  perform teste_assert_0300((select estado from pendencia where id = v_dre_p) = 'aceita_com_ressalva',
    'o arranjo: a pessoa decidiu seguir sem a DRE', (select estado::text from pendencia where id = v_dre_p));
  perform fn_recomputar_completude(v_caso);
  perform teste_assert_0300((select estado from pendencia where id = v_dre_p) = 'aceita_com_ressalva',
    'sem documento, a conferência NÃO desfaz a decisão da pessoa', (select estado::text from pendencia where id = v_dre_p));
  perform teste_assert_0300(teste_kit_0300(v_caso, 'DRE') = 'dispensado',
    'o item é dispensado (seguiu sem o documento, por decisão de pessoa), não faltante', teste_kit_0300(v_caso, 'DRE'));
  perform teste_assert_0300((select motivo from fn_kit_do_caso(v_caso) where tipo = 'DRE') like '%sai em branco no book%',
    'e o motivo diz o efeito da dispensa', null);

  r := fn_registrar_documento(v_caso, 'Alfa 0300 Ltda', 'anual', '2025', 'DRE', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0300/dre3.pdf', 'dre3.pdf', true, 'HASH-0300-B3-DRE', 'ok');
  v_doc := (r ->> 'documento_id')::uuid; v_ver := (r ->> 'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, teste_linhas_0300(2, 0.5), 'N0');

  perform teste_assert_0300((select estado from pendencia where id = v_dre_p) = 'resolvida',
    'D1.3: o documento que chega resolve também a pendência que uma pessoa decidiu', (select estado::text from pendencia where id = v_dre_p));
  perform teste_assert_0300((select resolvida_por_documento_id from pendencia where id = v_dre_p) = v_doc,
    'I1.3: pendencia.resolvida_por_documento_id aponta para o documento que chegou', (select resolvida_por_documento_id::text from pendencia where id = v_dre_p));
  -- Todos os eventos deste bloco têm o mesmo criado_em (uma transação só): acha-se o evento pelo que ele conta, não por "o último".
  select e.depois into v_ev from evento_auditoria e
   where e.acao = 'completude_recomputada' and e.entidade_ref = 'caso:' || v_caso
     and exists (select 1 from jsonb_array_elements(e.depois -> 'item_faltante' -> 'fechadas') f where f ->> 'tipo' = 'DRE');
  perform teste_assert_0300(v_ev is not null and exists (select 1 from jsonb_array_elements(v_ev -> 'item_faltante' -> 'fechadas') f
                                     where f ->> 'tipo' = 'DRE' and f ->> 'estado_anterior' = 'aceita_com_ressalva'
                                       and f ->> 'resolvida_por_anterior' = 'ana@oria' and f ->> 'documento_id' = v_doc::text),
    'D1.3: o evento guarda o estado anterior (aceita_com_ressalva), quem decidiu e o documento que fechou', coalesce(v_ev::text, '(nenhum evento fechou a DRE)'));
  perform teste_assert_0300(teste_kit_0300(v_caso, 'DRE') in ('extraido', 'conferido'), 'e o Kit já mostra a DRE lida', teste_kit_0300(v_caso, 'DRE'));
  perform teste_assert_0300((select estado from pendencia where id = v_p) = 'aberta',
    'o item_faltante de contrato social continua aberta depois de resolver a DRE', null);

  -- I1.3 (segunda metade): o documento é reclassificado para outro tipo: a pendência do tipo antigo reabre (nova).
  raise notice '--- 3b. reclassificar o documento reabre a pendência (nova) ---';
  r := fn_registrar_documento(v_caso, 'Alfa 0300 Ltda', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0300/bp3.pdf', 'bp3.pdf', true, 'HASH-0300-B3-BP', 'ok');
  v_doc := (r ->> 'documento_id')::uuid; v_ver := (r ->> 'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, teste_linhas_0300(2, 0.5), 'N0');
  select id into v_p from pendencia where caso_id = v_caso and chave_motor = 'completude:item_faltante:BALANCO' and estado = 'resolvida';
  perform teste_assert_0300(v_p = v_antes and (select resolvida_por_documento_id from pendencia where id = v_p) = v_doc,
    'o arranjo: a pendência BALANCO (a mesma de antes, descrição reescrita) foi resolvida pelo documento', coalesce(v_p::text, '(nenhuma)'));
  perform fn_revisar_documento(v_doc, 'ana@oria', 'FLUXO_CAIXA', null, null, null, 'era fluxo de caixa');
  perform teste_assert_0300((select tipo_taxonomia from documento where id = v_doc) = 'FLUXO_CAIXA', 'o arranjo: o documento virou FLUXO_CAIXA', null);
  select count(*) into v_n from pendencia where caso_id = v_caso and chave_motor = 'completude:item_faltante:BALANCO' and estado = 'aberta' and id <> v_p;
  perform teste_assert_0300(v_n = 1, 'I1.3: a pendência BALANCO reabre como uma NOVA, aberta', v_n::text);
  perform teste_assert_0300((select estado from pendencia where id = v_p) = 'resolvida' and (select resolvida_por_documento_id from pendencia where id = v_p) = v_doc,
    'e a antiga continua resolvida, com o rastro do documento que a fechou', null);
  perform teste_assert_0300(teste_kit_0300(v_caso, 'BALANCO') = 'faltante', 'e o Kit volta a dizer faltante', teste_kit_0300(v_caso, 'BALANCO'));
end $$;

-- =============================================================================================================================
-- BLOCO 4 — a adoção da chave (formato anterior à 0300) e o backfill
-- =============================================================================================================================
do $$
declare
  v_caso uuid; v_p uuid; v_n bigint; v_outro uuid; v_ent uuid; v_c2 uuid;
begin
  raise notice '--- 4. a item_faltante que o motor antigo deixou sem chave ---';
  v_caso := fn_upsert_caso('0300 — bloco 4 adocao da chave');
  -- O formato anterior à 0300: descrição com o prefixo, sem chave (as 205 abertas de produção). A única fixture escrita à mão deste arquivo.
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
    values (v_caso, 'completude', 'item_faltante', 'bloqueante', true, 'Item obrigatório do Kit Básico ausente: MUTUOS')
    returning id into v_p;
  v_ent := fn_upsert_entidade(v_caso, 'Alfa 0300 Ltda');
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, entidade_id, motivo)
    values (v_caso, 'completude', 'item_faltante', 'importante', true, 'Nenhum CONTRATO_SOCIAL foi recebido para "Alfa 0300 Ltda"', v_ent,
            'contrato_social_ausente:' || v_ent) returning id into v_outro;

  v_n := fn_adotar_chave_item_faltante(v_caso);
  perform teste_assert_0300(v_n = 1 and (select chave_motor from pendencia where id = v_p) = 'completude:item_faltante:MUTUOS',
    'a adoção dá a chave à pendência sem chave e devolve quantas adotou', v_n::text);
  perform teste_assert_0300((select chave_motor from pendencia where id = v_outro) is null,
    'e NÃO adota o item_faltante de outro assunto (sem o prefixo)', null);
  perform teste_assert_0300(fn_adotar_chave_item_faltante(v_caso) = 0, 'idempotente: a segunda chamada adota 0', null);

  -- A conferência adota sozinha a que ficou sem chave (migration e conferência se cruzando) e NÃO duplica.
  update pendencia set chave_motor = null where id = v_p;
  perform fn_recomputar_completude(v_caso);
  select count(*) into v_n from pendencia where caso_id = v_caso and tipo = 'item_faltante' and descricao = 'Item obrigatório do Kit Básico ausente: MUTUOS' and estado <> 'resolvida';
  perform teste_assert_0300(v_n = 1 and (select chave_motor from pendencia where id = v_p) = 'completude:item_faltante:MUTUOS',
    'a conferência adota a pendência sem chave em vez de abrir uma segunda', v_n::text);

  -- Resolvida não é adotada (nada a achar).
  v_c2 := fn_upsert_caso('0300 — bloco 4b resolvida nao adota');
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, estado, resolvida_em, resolvida_por)
    values (v_c2, 'completude', 'item_faltante', 'bloqueante', true, 'Item obrigatório do Kit Básico ausente: DRE', 'resolvida', now(), 'sistema:n8n')
    returning id into v_p;
  perform teste_assert_0300(fn_adotar_chave_item_faltante(v_c2) = 0 and (select chave_motor from pendencia where id = v_p) is null,
    'a pendência já resolvida não recebe chave', null);
end $$;

-- =============================================================================================================================
-- BLOCO 5 — o sinal positivo (regra 7): a conferência grava SEMPRE o evento, inclusive com tudo zero
-- =============================================================================================================================
do $$
declare
  v_caso uuid; v_antes int; v_ev jsonb;
begin
  raise notice '--- 5. completude_recomputada sempre ---';
  v_caso := fn_upsert_caso('0300 — bloco 5 evento sempre');
  select count(*) into v_antes from evento_auditoria where acao = 'completude_recomputada' and entidade_ref = 'caso:' || v_caso;
  perform teste_assert_0300(v_antes = 0, 'o arranjo: nenhum evento antes da primeira conferência', v_antes::text);
  perform fn_recomputar_completude(v_caso);
  select depois into v_ev from evento_auditoria where acao = 'completude_recomputada' and entidade_ref = 'caso:' || v_caso;
  perform teste_assert_0300((v_ev -> 'item_faltante' ->> 'abertas')::int = (select count(*) from taxonomia_tipo_documento where obrigatoriedade = 'obrigatorio'),
    'a primeira conferência grava o evento com o que abriu', v_ev::text);
end $$;

-- Transação nova: a segunda conferência não tem NADA a mudar.
do $$
declare
  v_caso uuid; v_n int; v_ev jsonb;
begin
  select id into v_caso from caso where nome = '0300 — bloco 5 evento sempre';
  perform fn_recomputar_completude(v_caso);
  select count(*) into v_n from evento_auditoria where acao = 'completude_recomputada' and entidade_ref = 'caso:' || v_caso;
  perform teste_assert_0300(v_n = 2, 'I1.5: duas conferências, dois eventos (inclusive a que não mudou nada)', v_n::text);
  select depois into v_ev from evento_auditoria where acao = 'completude_recomputada' and entidade_ref = 'caso:' || v_caso
   order by criado_em desc limit 1;
  perform teste_assert_0300((v_ev -> 'item_faltante' ->> 'abertas')::int = 0 and (v_ev -> 'item_faltante' ->> 'resolvidas')::int = 0
                            and (v_ev -> 'item_sem_conteudo' ->> 'abertas')::int = 0 and (v_ev -> 'item_sem_conteudo' ->> 'resolvidas')::int = 0
                            and (v_ev -> 'linha_exigida_ausente' ->> 'abertas')::int = 0 and (v_ev -> 'linha_exigida_ausente' ->> 'resolvidas')::int = 0,
    'I1.5: o evento da conferência sem mudança traz contagens ZERO (zero medido, não ausência de registro)', v_ev::text);
  perform teste_assert_0300((v_ev -> 'item_faltante' ->> 'mantidas')::int = (select count(*) from taxonomia_tipo_documento where obrigatoriedade = 'obrigatorio')
                            and jsonb_array_length(v_ev -> 'item_faltante' -> 'faltantes') = (select count(*) from taxonomia_tipo_documento where obrigatoriedade = 'obrigatorio'),
    'e conta as que seguem abertas (mantidas) e nomeia os faltantes', v_ev::text);
  perform teste_assert_0300(not exists (select 1 from evento_auditoria where acao = 'completude_recomputada' and entidade_ref = 'caso:' || v_caso and depois is null),
    'todo evento traz o corpo', null);
end $$;

-- Transação nova: o documento nasce DEPOIS da última conferência do bloco 5.
do $$
declare
  v_caso uuid; k record; r jsonb;
begin
  raise notice '--- 5b. documento que chegou depois da última conferência ---';
  select id into v_caso from caso where nome = '0300 — bloco 5 evento sempre';
  r := fn_registrar_documento(v_caso, 'Alfa 0300 Ltda', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0300/b5.pdf', 'b5.pdf', true, 'HASH-0300-B5', 'ok');
  select * into k from fn_kit_do_caso(v_caso) where tipo = 'BALANCO';
  perform teste_assert_0300(k.conferencia_em is not null and k.documentos_depois_da_conferencia = 1,
    'I1.5: o documento criado depois do último evento aparece em documentos_depois_da_conferencia',
    format('%s / %s', k.conferencia_em, k.documentos_depois_da_conferencia));
  perform fn_recomputar_completude(v_caso);
end $$;

do $$
declare
  v_caso uuid; k record;
begin
  select id into v_caso from caso where nome = '0300 — bloco 5 evento sempre';
  select * into k from fn_kit_do_caso(v_caso) where tipo = 'BALANCO';
  perform teste_assert_0300(k.documentos_depois_da_conferencia = 0,
    'e volta a zero quando a conferência roda de novo', k.documentos_depois_da_conferencia::text);
end $$;

-- =============================================================================================================================
-- BLOCO 6 — "N de M empresas": documento sem empresa não vira número; entidade fora do perímetro não entra em M
-- =============================================================================================================================
do $$
declare
  v_caso uuid; r jsonb; k record; v_ent uuid;
begin
  raise notice '--- 6. N de M empresas ---';
  v_caso := fn_upsert_caso('0300 — bloco 6 empresas');
  r := fn_registrar_documento(v_caso, 'Alfa 0300 Ltda', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0300/e1.pdf', 'e1.pdf', true, 'HASH-0300-E1', 'ok');
  perform fn_registrar_campos_extraidos((r ->> 'documento_versao_id')::uuid, teste_linhas_0300(2, 0.5), 'N0');
  perform fn_registrar_documento(v_caso, 'Beta 0300 Ltda', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage',
                                 '0300/e2.pdf', 'e2.pdf', true, 'HASH-0300-E2', 'ok');
  v_ent := fn_upsert_entidade(v_caso, 'Gama 0300 Ltda');
  perform fn_entidade_definir_papel_no_grupo(v_ent, 'fora_do_perimetro', 'ana@oria');
  -- Documento sem empresa (entidade nula), como o COMBINADO.
  r := fn_registrar_documento(v_caso, null, 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0300/e3.pdf', 'e3.pdf', true, 'HASH-0300-E3', 'ok');
  perform teste_assert_0300((select entidade_id from documento where id = (r ->> 'documento_id')::uuid) is null,
    'o arranjo: um documento sem empresa (entidade_id nulo)', null);
  select * into k from fn_kit_do_caso(v_caso) where tipo = 'BALANCO';
  perform teste_assert_0300(k.empresas_total = 2, 'M não inclui a entidade fora_do_perimetro (3 entidades, 2 no perímetro)', k.empresas_total::text);
  perform teste_assert_0300(k.empresas_com_documento = 2 and k.empresas_atendidas = 1,
    'N de M: 2 empresas com documento recebido, 1 com documento LIDO (a Beta só chegou)', format('%s/%s', k.empresas_com_documento, k.empresas_atendidas));
  perform teste_assert_0300(k.documentos_sem_empresa = 1,
    'o documento sem empresa é contado à parte e NÃO entra no N (o número não é inventado)', k.documentos_sem_empresa::text);
end $$;

-- =============================================================================================================================
-- BLOCO 7 — isolamento por mandato COMO authenticated, grants e a sonda
-- =============================================================================================================================
do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000300b001';
  u_ana   uuid := '00000000-0000-0000-0000-00000300b002';   -- Analista alocada em A
  u_xan   uuid := '00000000-0000-0000-0000-00000300b003';   -- Analista alocado só em B
  u_nil   uuid := '00000000-0000-0000-0000-00000300b004';   -- SEM papel
  v_a uuid; v_b uuid; v_t text; v_n int; r jsonb;
  c_expr constant text := 'select count(*) from fn_kit_do_caso(%L::uuid)';
begin
  raise notice '--- 7. isolamento por mandato e grants ---';
  insert into auth.users (id, email) values (u_socio, 'socio@0300.local'), (u_ana, 'ana@0300.local'), (u_xan, 'xan@0300.local'), (u_nil, 'nil@0300.local');
  perform fn_definir_papel(u_socio, 'socio', 'teste 0300');
  perform fn_definir_papel(u_ana, 'analista');
  perform fn_definir_papel(u_xan, 'analista');
  v_a := fn_upsert_caso('0300 — bloco 7 mandato A');
  v_b := fn_upsert_caso('0300 — bloco 7 mandato B');
  perform fn_alocar(v_a, u_ana);
  perform fn_alocar(v_b, u_xan);
  r := fn_registrar_documento(v_a, 'Alfa 0300 Ltda', 'anual', '2025', 'BALANCO', 0.97, 'nome_arquivo', 'supabase_storage',
                              '0300/i1.pdf', 'i1.pdf', true, 'HASH-0300-I1', 'ok');
  select count(*) into v_n from taxonomia_tipo_documento where obrigatoriedade = 'obrigatorio';

  perform teste_assert_0300(teste_exec_0300(u_ana, 'authenticated', format(c_expr, v_a)) = 'ok|' || v_n,
    'a Analista de A lê o Kit de A (uma linha por tipo obrigatório)', teste_exec_0300(u_ana, 'authenticated', format(c_expr, v_a)));
  perform teste_assert_0300(teste_exec_0300(u_ana, 'authenticated', format('select estado from fn_kit_do_caso(%L::uuid) where tipo = ''BALANCO''', v_a)) = 'ok|aguardando_extracao',
    'e vê o BALANCO de A como aguardando_extracao (enxerga o documento)', null);
  perform teste_assert_0300(teste_exec_0300(u_xan, 'authenticated', format(c_expr, v_a)) = 'ok|0',
    'a Analista de B pedindo o Kit de A recebe ZERO linhas — nunca "tudo faltante"', teste_exec_0300(u_xan, 'authenticated', format(c_expr, v_a)));
  perform teste_assert_0300(teste_exec_0300(u_nil, 'authenticated', format(c_expr, v_a)) = 'ok|0', 'quem não tem papel recebe zero linhas', null);
  perform teste_assert_0300(teste_exec_0300(u_socio, 'authenticated', format(c_expr, v_a)) = 'ok|' || v_n
                            and teste_exec_0300(u_socio, 'authenticated', format(c_expr, v_b)) = 'ok|' || v_n,
    'o Sócio lê o Kit de qualquer mandato', null);
  perform teste_assert_0300(teste_exec_0300(u_socio, 'authenticated', format(c_expr, '00000000-0000-0000-0000-000000000300')) = 'ok|0',
    'mandato inexistente devolve zero linhas', null);
  perform teste_assert_0300(has_function_privilege('authenticated', 'fn_kit_do_caso(uuid)', 'execute')
                            and has_function_privilege('service_role', 'fn_kit_do_caso(uuid)', 'execute')
                            and not has_function_privilege('anon', 'fn_kit_do_caso(uuid)', 'execute')
                            and has_function_privilege('authenticated', 'fn_adotar_chave_item_faltante(uuid)', 'execute')
                            and has_function_privilege('service_role', 'fn_adotar_chave_item_faltante(uuid)', 'execute')
                            and not has_function_privilege('anon', 'fn_adotar_chave_item_faltante(uuid)', 'execute'),
    'grants: authenticated e service_role executam; o anon NÃO executa nenhuma das duas funções novas', null);
  perform teste_assert_0300(teste_exec_0300(null, 'anon', format(c_expr, v_a)) like '42501|%', 'o anon não executa (42501)', teste_exec_0300(null, 'anon', format(c_expr, v_a)));

  -- A conferência feita COMO authenticated (a Analista, pelo caminho do portal) grava o evento sob a RLS de evento_auditoria.
  perform teste_assert_0300(teste_exec_0300(u_ana, 'authenticated', format('fn_recomputar_completude(%L::uuid) is not null', v_a)) = 'ok|true',
    'a conferência rodada COMO a Analista do mandato funciona (o INSERT do evento passa pela RLS)', teste_exec_0300(u_ana, 'authenticated', format('fn_recomputar_completude(%L::uuid) is not null', v_a)));
  perform teste_assert_0300(teste_exec_0300(u_ana, 'authenticated', format('(select conferencia_em is not null from fn_kit_do_caso(%L::uuid) limit 1)', v_a)) = 'ok|true',
    'e ela LÊ o evento: conferencia_em vem preenchido para quem tem o mandato', null);
  perform teste_assert_0300(teste_exec_0300(u_xan, 'authenticated', format('select count(*) from evento_auditoria where acao = ''completude_recomputada'' and entidade_ref = %L', 'caso:' || v_a)) = 'ok|0'
                            and teste_exec_0300(u_ana, 'authenticated', format('select count(*) > 0 from evento_auditoria where acao = ''completude_recomputada'' and entidade_ref = %L', 'caso:' || v_a)) = 'ok|true',
    'a Analista de B não lê o evento de conferência de A, e a de A lê: o isolamento do Kit vale também para o sinal da conferência', null);

  -- A SONDA.
  raise notice '--- 8. a sonda enxerga o que a 0300 instala ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0300' and not presente;
  perform teste_assert_0300(v_n = 0, 'a sonda enxerga os requisitos da 0300 (zero ausentes)', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0300';
  perform teste_assert_0300(v_n = 8, 'e o catálogo da 0300 tem 8 requisitos (não está vazio nem encolheu)', v_n::text);

  delete from caso where nome like '0300 —%';
  delete from auth.users where id in (u_socio, u_ana, u_xan, u_nil);

  raise notice 'EXECUCOES=% FALHAS=%', current_setting('ct300.execucoes', true), coalesce(current_setting('ct300.falhas', true), '0');
  if current_setting('ct300.medindo', true) is distinct from 'on' then
    raise notice 'TODOS OS TESTES DA 0300 PASSARAM';
  end if;
end $$;
