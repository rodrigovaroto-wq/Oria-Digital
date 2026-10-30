-- =============================================================================
-- 0215 — O HISTÓRICO DO MANDATO (fn_historico_do_caso): quem fez o quê e quando, da mais nova para a mais velha
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md): 49 asserts; o número por guarda desligada está no cabeçalho de
-- Supabase/migrations/0215_o_historico_que_so_o_banco_sabia.sql.
--
-- O ARRANJO É O DE PRODUÇÃO (regra 4): o caso é montado pelas MESMAS funções que o portal e o n8n chamam
-- (fn_upsert_caso, fn_registrar_documento, fn_aceitar_extracao, fn_revisar_documento, fn_registrar_classe_override,
-- fn_decidir_pendencia, fn_registrar_pergunta_acao, fn_ativar_premissa, fn_desativar_premissa, fn_aprovar_caso,
-- fn_fechar_caso), não por INSERT nas tabelas de trilha. Única exceção declarada: a pendência nasce por INSERT (é o que
-- fazem os testes vizinhos; quem a abre é o motor de completude) e o horário de cada evento é reescrito depois por
-- UPDATE, porque tudo roda numa transação só e `now()` é o mesmo para todos — sem horários distintos a ordem não
-- seria afirmável. O UPDATE mexe só em instante, nunca em autor ou texto.
--
-- O QUE ESTE ARQUIVO AFIRMA (comportamento):
--   1. a lista sai da mais nova para a mais velha, e cada tipo de evento aparece uma vez, com o autor de quem agiu;
--   2. o que o SISTEMA fez (arquivo recebido, caso criado) vem com autor nulo — a tela é que escreve "sistema";
--   3. o resumo é português corrido (nome do arquivo, nome da premissa, rótulo da decisão), não código;
--   4. `p_antes` pagina: as páginas somam a lista inteira, sem repetir e sem pular;
--   5. NADA de outro caso aparece (um segundo caso com documento, pergunta e premissa próprios), e nada de
--      `decisao`/`evento_auditoria` que só repete outro evento (aceite, aprovação) nem tentativa recusada;
--   6. caso sem evento nenhum, e caso que não existe, devolvem ZERO linhas — nunca erro;
--   7. `p_limite` é cortado em 1..1000, e a função funciona COMO authenticated (RLS, grant de função);
--   8. (caso C, revisão independente) o aceite AUTOMÁTICO entra; a versão da transcrição não vira recebimento; o perímetro
--      de entidade absorvida por fusão encadeada continua, pelo nome; o cursor composto não perde evento empatado; a
--      apresentação diz "salva", não "preenchida"; o recebimento marca `autor_desconhecido`.
-- Exceções declaradas à regra 4 no caso C: as duas entidades a fundir e os campos da apresentação nascem por INSERT.
-- =============================================================================

create or replace function teste_assert_0215(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_cond then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

delete from caso where nome like '0215 —%';

do $$
declare
  v_a uuid; v_b uuid; v_vazio uuid;
  v_r jsonb; v_ver uuid; v_doc uuid; v_ver_b uuid; v_doc_b uuid;
  v_campo uuid; v_pend uuid;
  v_t0 timestamptz := date_trunc('minute', now()) - interval '10 days';
  v_n int; v_tipos text; v_ant timestamptz; v_ok boolean; v_ids text;
  v_p1 text[]; v_p2 text[]; v_p3 text[]; v_todos text[];
  v_h record;
  v_cursor timestamptz;
  v_c uuid; v_doc_c uuid; v_doc_d uuid; v_ver_c uuid; v_e1 uuid; v_e2 uuid; v_ent_c uuid;
  v_chv text; v_cur_em timestamptz; v_cur_ch text; v_pg text[]; v_pags text[]; v_inteira text[]; v_i int;
begin
  v_a     := fn_upsert_caso('0215 — histórico A');
  v_b     := fn_upsert_caso('0215 — histórico B (outro mandato)');
  insert into caso (nome) values ('0215 — histórico vazio') returning id into v_vazio;

  -- ---------------------------------------------------------------- caso A
  v_r := fn_registrar_documento(v_a, 'ALFA SA', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-alfa-0215.pdf', 'BP Alfa 2025.pdf', true, 'HASH-ALFA-0215', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  v_doc := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "TOTAL DO ATIVO", "valor_num": "900", "confianca": "0.9"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "900", "confianca": "0.9"},
    {"chave": "Despesas nao recorrentes", "valor_num": "50", "confianca": "0.9"}]'::jsonb, 'N0');
  select id into v_campo from campo_extraido where documento_versao_id = v_ver and chave = 'Despesas nao recorrentes';

  perform fn_aceitar_extracao(v_ver, 'ana@oria', 'conferi contra o PDF');
  perform fn_revisar_documento(v_doc, 'ana@oria', null, null, null, null, 'tipo conferido');
  perform fn_registrar_classe_override(v_campo, 'nao_recorrente', 'rodrigo@oria', 'multa rescisória');

  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id)
    values (v_a, 'completude', 'item_sem_conteudo', 'bloqueante', true, 'Balanço sem a nota de dívida', v_doc)
    returning id into v_pend;
  perform fn_decidir_pendencia(v_pend, 'socio@oria', 'prosseguir', 'cliente não tem a nota');

  perform fn_registrar_pergunta_acao(v_a, 'A3', 'enviada', 'Vocês têm o caixa de 2025?', 'ana@oria');
  perform fn_registrar_pergunta_acao(v_a, 'A3', 'descartada', null, 'ian@oria');

  perform fn_ativar_premissa(v_a, 'CRESC_REAL', '{"2026": 5}'::jsonb, 'digitado', 'ana@oria');
  perform fn_ativar_premissa(v_a, 'IPCA', '{}'::jsonb, 'digitado', 'ana@oria');
  perform fn_desativar_premissa(v_a, 'IPCA', 'ian@oria');
  -- uma tentativa RECUSADA: gera evento `premissa_recusada`, que NÃO é história do caso
  perform fn_ativar_premissa(v_a, 'PREMISSA_QUE_NAO_EXISTE', '{}'::jsonb, 'digitado', 'ana@oria');

  -- Os três ramos que o portal escreve direto ou por função de perímetro: vínculo premissa-linha e dado da apresentação
  -- (o editor grava nas tabelas, é o caminho real) e papel no grupo (fn_entidade_definir_papel_no_grupo).
  insert into caso_linha_premissa (caso_id, rotulo_norm, premissa_codigo, atualizado_por)
    values (v_a, 'receita bruta', 'CRESC_REAL', 'ana@oria'), (v_a, 'receita liquida', 'CRESC_REAL', 'ana@oria');
  insert into caso_apresentacao_campo (caso_id, chave, valor, fonte, preenchido_por)
    values (v_a, 'capa.titulo', 'Projeto Alfa', 'digitado', 'ana@oria');
  perform fn_entidade_definir_papel_no_grupo((select id from entidade where caso_id = v_a limit 1), 'operacional', 'ian@oria');

  -- O Portão 2 recusa caso com bloqueante aberta (7 aqui, abertas pelo motor ao registrar o balanço). Para chegar na
  -- aprovação de verdade, o que sobrou aberto é dado por improcedente por UPDATE de estado (sem evento: não é
  -- o que este teste mede). A aprovação em si é a função real.
  update pendencia set estado = 'rejeitada' where caso_id = v_a and estado = 'aberta';
  v_r := fn_aprovar_caso(v_a, 'socio@oria', 'conferido pelo sócio');
  perform teste_assert_0215((v_r->>'aprovado') = 'true', 'arranjo: o caso A é aprovado pela função real', v_r::text);
  perform fn_fechar_caso(v_a, 'socio@oria', 'operação não aconteceu');

  -- ---------------------------------------------------------------- caso B (o que NÃO pode vazar)
  v_r := fn_registrar_documento(v_b, 'BETA SA', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-beta-0215.pdf', 'BP Beta 2025.pdf', true, 'HASH-BETA-0215', 'ok');
  v_ver_b := (v_r->>'documento_versao_id')::uuid;
  v_doc_b := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver_b,
    '[{"chave": "TOTAL DO ATIVO", "valor_num": "10", "confianca": "0.9"}]'::jsonb, 'N0');
  perform fn_aceitar_extracao(v_ver_b, 'intruso@oria', 'do outro caso');
  perform fn_registrar_pergunta_acao(v_b, 'A3', 'enviada', 'Pergunta do outro caso', 'intruso@oria');
  perform fn_ativar_premissa(v_b, 'CRESC_REAL', '{"2026": 9}'::jsonb, 'digitado', 'intruso@oria');
  perform fn_fechar_caso(v_b, 'intruso@oria', 'outro');

  -- ------------------------------------------------ horários distintos e conhecidos (só instante, nunca autor)
  -- `caso_pergunta` é append-only por gatilho (0213); o modo réplica o desliga SÓ para reescrever o instante.
  set local session_replication_role = replica;
  update caso_pergunta set criado_em = v_t0 + interval '5 hours'  where caso_id = v_a and acao = 'enviada';
  update caso_pergunta set criado_em = v_t0 + interval '6 hours'  where caso_id = v_a and acao = 'descartada';
  update campo_classe_override set criado_em = v_t0 + interval '3 hours' where campo_extraido_id = v_campo;
  update documento_versao set criada_em = v_t0 + interval '5 minutes' where id = v_ver;
  update evento_auditoria set criado_em = v_t0                         where acao = 'caso_criado' and entidade_ref = 'caso:' || v_a;
  update evento_auditoria set criado_em = v_t0 + interval '1 hour'     where acao = 'extracao_aceita' and entidade_ref = 'documento_versao:' || v_ver;
  update evento_auditoria set criado_em = v_t0 + interval '2 hours'    where acao = 'documento_revisado' and entidade_ref = 'documento:' || v_doc;
  update evento_auditoria set criado_em = v_t0 + interval '4 hours'    where acao = 'pendencia_decidida' and entidade_ref = 'pendencia:' || v_pend;
  update decisao set criado_em = v_t0 + interval '7 hours'  where caso_id = v_a and payload->>'premissa' = 'CRESC_REAL';
  update decisao set criado_em = v_t0 + interval '8 hours'  where caso_id = v_a and payload->>'premissa' = 'IPCA' and (payload->>'ativo') is distinct from 'false';
  update decisao set criado_em = v_t0 + interval '9 hours'  where caso_id = v_a and payload->>'premissa' = 'IPCA' and (payload->>'ativo') = 'false';
  update decisao set criado_em = v_t0 + interval '10 hours' where caso_id = v_a and payload ? 'portao';
  update caso_linha_premissa set atualizado_em = v_t0 + interval '3 hours 30 minutes' where caso_id = v_a;
  update caso_apresentacao_campo set preenchido_em = v_t0 + interval '2 hours 30 minutes' where caso_id = v_a;
  update evento_auditoria set criado_em = v_t0 + interval '1 hour 15 minutes'
   where acao = 'entidade_papel_no_grupo_definido' and entidade_ref in (select 'entidade:' || id from entidade where caso_id = v_a);
  update evento_auditoria set criado_em = v_t0 + interval '11 hours'   where acao = 'caso_fechado' and entidade_ref = 'caso:' || v_a;
  -- o caso B recebe horários DENTRO da janela do A: se vazasse, entraria no meio da ordem
  update documento_versao set criada_em = v_t0 + interval '30 minutes' where id = v_ver_b;
  update caso_pergunta set criado_em = v_t0 + interval '5 hours 30 minutes' where caso_id = v_b;
  update decisao set criado_em = v_t0 + interval '7 hours 30 minutes' where caso_id = v_b;
  update evento_auditoria set criado_em = v_t0 + interval '1 hour 30 minutes' where entidade_ref = 'documento_versao:' || v_ver_b;
  update evento_auditoria set criado_em = v_t0 + interval '11 hours 30 minutes' where acao = 'caso_fechado' and entidade_ref = 'caso:' || v_b;

  set local session_replication_role = origin;

  raise notice '--- 1. a lista do caso A: ordem, tipos, autores ---';
  select count(*) into v_n from fn_historico_do_caso(v_a);
  perform teste_assert_0215(v_n = 16, 'o caso A tem 16 eventos de história (nem as recusas nem a repetição em decisao)',
    format('%s', v_n));

  select string_agg(tipo, ',' order by em desc) into v_tipos from fn_historico_do_caso(v_a);
  perform teste_assert_0215(v_tipos = 'caso_fechado,caso_aprovado,premissa_removida,premissa_ativada,premissa_ativada,'
                                    || 'pergunta_descartada,pergunta_enviada,pendencia_decidida,'
                                    || 'premissa_vinculada_a_linha,classe_corrigida,apresentacao_salva,'
                                    || 'documento_revisado,perimetro_alterado,extracao_aceita,documento_recebido,caso_criado',
    'da mais nova para a mais velha, na ordem em que os atos aconteceram', v_tipos);

  select bool_and(a.em > b.em) into v_ok
    from (select em, row_number() over (order by em desc) rn from fn_historico_do_caso(v_a)) a
    join (select em, row_number() over (order by em desc) rn from fn_historico_do_caso(v_a)) b on b.rn = a.rn + 1;
  perform teste_assert_0215(v_ok, 'os instantes são estritamente decrescentes ao longo da lista');

  perform teste_assert_0215((select autor from fn_historico_do_caso(v_a) where tipo = 'extracao_aceita') = 'ana@oria',
    'a extração aceita tem o autor de quem aceitou');
  perform teste_assert_0215((select autor from fn_historico_do_caso(v_a) where tipo = 'classe_corrigida') = 'rodrigo@oria',
    'a classe corrigida tem o autor de quem corrigiu');
  perform teste_assert_0215((select autor from fn_historico_do_caso(v_a) where tipo = 'pendencia_decidida') = 'socio@oria',
    'a pendência decidida tem o autor de quem decidiu');
  perform teste_assert_0215((select autor from fn_historico_do_caso(v_a) where tipo = 'premissa_removida') = 'ian@oria',
    'a premissa removida tem o autor de quem removeu (e não o de quem a ativou)');
  perform teste_assert_0215((select autor from fn_historico_do_caso(v_a) where tipo = 'pergunta_descartada') = 'ian@oria'
                        and (select autor from fn_historico_do_caso(v_a) where tipo = 'pergunta_enviada') = 'ana@oria',
    'pergunta enviada e descartada, cada uma com o seu autor');
  perform teste_assert_0215((select autor from fn_historico_do_caso(v_a) where tipo = 'caso_aprovado') = 'socio@oria'
                        and (select autor from fn_historico_do_caso(v_a) where tipo = 'caso_fechado') = 'socio@oria',
    'aprovação e fechamento têm o autor do sócio');

  raise notice '--- 2. o que o sistema fez vem sem autor ---';
  perform teste_assert_0215((select count(*) from fn_historico_do_caso(v_a) where tipo in ('documento_recebido', 'caso_criado')
                                and autor is null) = 2,
    'arquivo recebido e caso criado (sistema:n8n) vêm com autor NULO — a tela escreve "sistema"');
  perform teste_assert_0215((select count(*) from fn_historico_do_caso(v_a) where autor is null) = 2,
    'e só eles: ninguém mais ficou sem autor');

  raise notice '--- 2b. vínculos, apresentação e perímetro ---';
  perform teste_assert_0215((select count(*) from fn_historico_do_caso(v_a) where tipo = 'premissa_vinculada_a_linha') = 1
                        and (select resumo from fn_historico_do_caso(v_a) where tipo = 'premissa_vinculada_a_linha') like '2 linha(s)%'
                        and (select autor from fn_historico_do_caso(v_a) where tipo = 'premissa_vinculada_a_linha') = 'ana@oria',
    'dois vínculos gravados no mesmo instante viram UMA linha do tempo: "2 linha(s)", com o autor');
  perform teste_assert_0215((select autor from fn_historico_do_caso(v_a) where tipo = 'apresentacao_salva') = 'ana@oria'
                        and (select autor from fn_historico_do_caso(v_a) where tipo = 'perimetro_alterado') = 'ian@oria'
                        and (select resumo from fn_historico_do_caso(v_a) where tipo = 'perimetro_alterado') like '%ALFA SA%',
    'apresentação e perímetro trazem o autor, e o perímetro diz a entidade pelo nome');

  raise notice '--- 3. resumo em português, com o documento quando há ---';
  perform teste_assert_0215((select resumo from fn_historico_do_caso(v_a) where tipo = 'documento_recebido')
                            = 'Arquivo "BP Alfa 2025.pdf" recebido',
    'o recebimento diz o nome do arquivo', (select resumo from fn_historico_do_caso(v_a) where tipo = 'documento_recebido'));
  perform teste_assert_0215((select resumo from fn_historico_do_caso(v_a) where tipo = 'premissa_ativada' and em = v_t0 + interval '7 hours')
                            like '%Crescimento real da receita%',
    'a premissa aparece pelo NOME, não pelo código');
  perform teste_assert_0215((select resumo from fn_historico_do_caso(v_a) where tipo = 'pendencia_decidida')
                            like '%Prosseguir sem resolução%cliente não tem a nota%',
    'a pendência decidida diz a decisão e o motivo');
  perform teste_assert_0215((select resumo from fn_historico_do_caso(v_a) where tipo = 'classe_corrigida')
                            like '%Despesas nao recorrentes%Não recorrente%multa rescisória%',
    'a classe corrigida diz a linha, o nome da classe (não o código) e o motivo');
  perform teste_assert_0215((select resumo from fn_historico_do_caso(v_a) where tipo = 'caso_fechado') like '%operação não aconteceu',
    'o fechamento carrega o motivo');
  perform teste_assert_0215((select count(*) from fn_historico_do_caso(v_a)
                              where tipo in ('documento_recebido', 'extracao_aceita', 'documento_revisado', 'classe_corrigida',
                                             'pendencia_decidida') and documento_id = v_doc) = 5,
    'os cinco tipos de um documento trazem o documento_id (a tela abre o painel)');

  raise notice '--- 4. p_antes pagina sem repetir nem pular ---';
  select array_agg(tipo order by em desc), min(em) into v_p1, v_cursor from fn_historico_do_caso(v_a, 5);
  perform teste_assert_0215(cardinality(v_p1) = 5, 'a primeira página tem 5 linhas', format('%s', cardinality(v_p1)));
  select array_agg(tipo order by em desc), min(em) into v_p2, v_cursor from fn_historico_do_caso(v_a, 5, v_cursor);
  perform teste_assert_0215(cardinality(v_p2) = 5, 'a segunda página tem 5 linhas, todas anteriores ao cursor');
  select array_agg(tipo order by em desc), min(em) into v_p3, v_cursor from fn_historico_do_caso(v_a, 6, v_cursor);
  v_todos := v_p1 || v_p2 || v_p3;
  perform teste_assert_0215(cardinality(v_p3) = 6 and cardinality(v_todos) = 16,
    'a terceira traz as 6 que sobram: 5 + 5 + 6 = 16', format('%s', cardinality(v_p3)));
  perform teste_assert_0215(v_todos = (select array_agg(tipo order by em desc) from fn_historico_do_caso(v_a)),
    'as páginas, juntas, são a lista inteira na mesma ordem (sem repetir e sem pular)');
  perform teste_assert_0215(not exists (select 1 from fn_historico_do_caso(v_a, 200, v_t0 + interval '5 minutes')
                                         where em >= v_t0 + interval '5 minutes')
                        and (select count(*) from fn_historico_do_caso(v_a, 200, v_t0 + interval '5 minutes')) = 1,
    'p_antes é ESTRITO: com o cursor no instante do recebimento só sobra o que veio antes (o caso criado)');

  raise notice '--- 5. nada de outro caso, nada repetido, nenhuma recusa ---';
  select count(*) into v_n from fn_historico_do_caso(v_b);
  perform teste_assert_0215(v_n = 6, 'o caso B tem as 6 linhas dele: criado, recebido, aceite, pergunta, premissa, fechado',
    format('%s', v_n));
  perform teste_assert_0215(not exists (select 1 from fn_historico_do_caso(v_a) where autor = 'intruso@oria')
                        and not exists (select 1 from fn_historico_do_caso(v_b) where autor <> 'intruso@oria' and autor is not null),
    'nenhum autor ou evento de um caso aparece no histórico do outro');
  perform teste_assert_0215(not exists (select 1 from fn_historico_do_caso(v_a) where documento_id = v_doc_b)
                        and not exists (select 1 from fn_historico_do_caso(v_b) where documento_id = v_doc),
    'nenhum documento de um caso aparece no histórico do outro');
  perform teste_assert_0215((select count(*) from fn_historico_do_caso(v_a) where tipo = 'extracao_aceita') = 1
                        and not exists (select 1 from fn_historico_do_caso(v_a) where tipo in ('aprovacao', 'override', 'ressalva')),
    'o aceite aparece UMA vez (a decisao que o repete não entra) e nenhum tipo cru de decisao vaza');
  perform teste_assert_0215(not exists (select 1 from fn_historico_do_caso(v_a) where resumo ilike '%PREMISSA_QUE_NAO_EXISTE%'),
    'a tentativa de ativar premissa inexistente (recusada) não é história do caso');

  raise notice '--- 6. sem evento nenhum, ou sem caso: zero linhas, nunca erro ---';
  perform teste_assert_0215((select count(*) from fn_historico_do_caso(v_vazio)) = 0,
    'caso criado sem nenhum evento devolve zero linhas');
  perform teste_assert_0215((select count(*) from fn_historico_do_caso('00000000-0000-0000-0000-000000000000')) = 0,
    'caso que não existe devolve zero linhas (e não erro)');

  raise notice '--- 7. limite cortado, e a função roda COMO authenticated ---';
  perform teste_assert_0215((select count(*) from fn_historico_do_caso(v_a, 0)) = 1
                        and (select count(*) from fn_historico_do_caso(v_a, -5)) = 1,
    'p_limite 0 ou negativo vira 1 (nunca devolve nada nem erra)');
  perform teste_assert_0215((select count(*) from fn_historico_do_caso(v_a, null)) = 16,
    'p_limite nulo cai no padrão (200) e devolve tudo');

  set local role authenticated;
  select count(*) into v_n from fn_historico_do_caso(v_a);
  reset role;
  perform teste_assert_0215(v_n = 16, 'como authenticated (RLS e grant de função) a lista é a mesma de 16 linhas', format('%s', v_n));

  -- ================================================================ caso C: os achados da revisão independente
  -- Tudo aqui roda na MESMA transação, então todo evento do C tem o MESMO `now()`: é o empate extremo, de propósito (o
  -- cursor só por instante perde evento exatamente aí). Exceções declaradas à regra 4: as duas entidades velhas e os três
  -- campos da apresentação nascem por INSERT (é o que o portal faz com a apresentação; entidade fantasma é o que a fusão
  -- recebe) — todo o resto sai das funções reais (fn_upsert_caso, fn_registrar_documento, fn_registrar_campos_extraidos
  -- com o dial N2 real, fn_registrar_transcricao_humana, fn_entidade_definir_papel_no_grupo, fn_fundir_entidade).
  raise notice '--- 8. os achados da revisão: auto-aceite, transcrição, entidade absorvida, empate de instante ---';
  perform teste_assert_0215((select nivel_atual::text from estagio_autonomia where estagio = 'extracao_linhas_financeiras') = 'N2',
    'arranjo: o dial da extração está em N2 (o auto-aceite só existe com ele)');
  v_c := fn_upsert_caso('0215 — histórico C (revisão)');
  v_r := fn_registrar_documento(v_c, 'GAMA SA', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-gama-0215.pdf', 'BP Gama 2025.pdf', true, 'HASH-GAMA-0215', 'ok');
  v_doc_c := (v_r->>'documento_id')::uuid; v_ver_c := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver_c, '[
    {"chave": "Caixa e equivalentes", "valor_num": "1200", "confianca": "0.98", "secao_canonica": "ativo_circulante"},
    {"chave": "Adiantamentos diversos", "valor_num": "340", "confianca": "0.99", "secao_canonica": "ativo_circulante"}]'::jsonb, 'N2');
  v_r := fn_registrar_documento(v_c, 'GAMA SA', 'anual', '2024', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-gama-2024-0215.pdf', 'BP Gama 2024 (escaneado).pdf', true, 'HASH-GAMA24-0215', 'ok');
  v_doc_d := (v_r->>'documento_id')::uuid;
  v_r := fn_registrar_transcricao_humana(v_doc_d,
    '[{"chave": "Caixa", "valor_num": "10"}, {"chave": "Estoques", "valor_num": "20"}]'::jsonb, 'ana@oria', 'arquivo escaneado');
  perform teste_assert_0215(v_r->>'recusado' is null, 'arranjo: a transcrição é aceita pela função real', v_r::text);

  select id into v_ent_c from entidade where caso_id = v_c limit 1;
  insert into entidade (caso_id, razao_social) values (v_c, 'GAMA ANTIGA 1') returning id into v_e1;
  insert into entidade (caso_id, razao_social) values (v_c, 'GAMA ANTIGA 2') returning id into v_e2;
  perform fn_entidade_definir_papel_no_grupo(v_e1, 'operacional', 'ian@oria');
  v_r := fn_fundir_entidade(v_c, v_e1, v_e2, 'ian@oria');   -- A em B
  v_r := fn_fundir_entidade(v_c, v_e2, v_ent_c, 'ian@oria'); -- B em C: a cadeia tem dois degraus
  perform teste_assert_0215(not exists (select 1 from entidade where id in (v_e1, v_e2)),
    'arranjo: as duas entidades velhas foram APAGADAS pela fusão real (é o que torna o achado possível)');

  insert into caso_apresentacao_campo (caso_id, chave, valor, fonte, preenchido_por)
    values (v_c, 'capa.titulo', 'Projeto Gama', 'digitado', 'ana@oria'), (v_c, 'capa.data', '2026', 'digitado', 'ana@oria'),
           (v_c, 'capa.subtitulo', 'Memorando', 'digitado', 'ana@oria');

  -- ALTO 1: o aceite AUTOMÁTICO (só `decisao`, sem evento) aparece
  perform teste_assert_0215((select count(*) from fn_historico_do_caso(v_c) where tipo = 'extracao_aceita') = 1
                        and (select autor from fn_historico_do_caso(v_c) where tipo = 'extracao_aceita') is null
                        and (select resumo from fn_historico_do_caso(v_c) where tipo = 'extracao_aceita') = 'Extração aceita automaticamente: 2 campo(s)'
                        and (select referencia->>'automatico' from fn_historico_do_caso(v_c) where tipo = 'extracao_aceita') = 'true'
                        and (select documento_id from fn_historico_do_caso(v_c) where tipo = 'extracao_aceita') = v_doc_c,
    'a extração aceita AUTOMATICAMENTE (dial N2, só decisao) entra: autor nulo, "aceita automaticamente", 2 campos, com o documento',
    (select resumo from fn_historico_do_caso(v_c) where tipo = 'extracao_aceita' limit 1));

  -- ALTO 2: a versão que a transcrição cria não é um recebimento
  perform teste_assert_0215((select count(*) from fn_historico_do_caso(v_c) where tipo = 'documento_recebido') = 2
                        and not exists (select 1 from fn_historico_do_caso(v_c) where resumo like 'Nova versão%')
                        and (select count(*) from fn_historico_do_caso(v_c) where tipo = 'transcricao_humana') = 1,
    'a transcrição aparece UMA vez, como transcrição: os 2 arquivos recebidos são 2, e nenhuma "nova versão" inventada',
    (select string_agg(resumo, ' | ') from fn_historico_do_caso(v_c) where tipo = 'documento_recebido'));

  -- ALTO 3: o perímetro da entidade absorvida (dois degraus) aparece, com o nome
  perform teste_assert_0215((select count(*) from fn_historico_do_caso(v_c)
                              where tipo = 'perimetro_alterado' and resumo = 'Papel no grupo definido — GAMA ANTIGA 1') = 1,
    'o evento de perímetro de uma entidade absorvida por fusão ENCADEADA (A em B, B em C) continua no histórico, pelo nome');
  perform teste_assert_0215((select count(*) from fn_historico_do_caso(v_c) where tipo = 'perimetro_alterado'
                              and resumo in ('Entidade "GAMA ANTIGA 1" fundida em "GAMA ANTIGA 2"',
                                             'Entidade "GAMA ANTIGA 2" fundida em "GAMA SA"')) = 2
                        and not exists (select 1 from fn_historico_do_caso(v_c) where resumo like '%(entidade removida)%'),
    'as duas fusões dizem quem foi fundida em quem, e nenhum rótulo "(entidade removida)"',
    (select string_agg(resumo, ' | ') from fn_historico_do_caso(v_c) where tipo = 'perimetro_alterado'));
  perform teste_assert_0215(not exists (select 1 from fn_historico_do_caso(v_a) where resumo like '%GAMA%')
                        and not exists (select 1 from fn_historico_do_caso(v_b) where resumo like '%GAMA%'),
    'a descida pelas fusões não puxa nada para os outros casos');

  -- MÉDIO 5 e 6
  perform teste_assert_0215((select count(*) from fn_historico_do_caso(v_c) where tipo = 'apresentacao_salva'
                                and resumo like 'Apresentação salva — último salvamento do campo%') = 3
                        and not exists (select 1 from fn_historico_do_caso(v_c) where resumo ilike '%preenchid%'),
    'a apresentação diz "salva — último salvamento do campo", nunca "preenchido" (o autor é quem salvou por último)');
  perform teste_assert_0215((select count(*) from fn_historico_do_caso(v_c)
                              where tipo = 'documento_recebido' and autor is null and referencia->>'autor_desconhecido' = 'true') = 2
                        and not exists (select 1 from fn_historico_do_caso(v_c)
                                         where tipo <> 'documento_recebido' and referencia ? 'autor_desconhecido'),
    'o recebimento marca autor_desconhecido (NULL = "não sei"), e nenhum outro tipo carrega o campo');

  -- MÉDIO 4: o cursor composto, com TODOS os eventos do caso C no mesmo instante
  select count(*) into v_n from fn_historico_do_caso(v_c);
  perform teste_assert_0215((select count(distinct em) from fn_historico_do_caso(v_c)) = 1 and v_n >= 9,
    'arranjo do empate: todos os eventos do caso C estão no MESMO instante (senão o teste do cursor não mediria empate)',
    format('%s eventos, %s instantes', v_n, (select count(distinct em) from fn_historico_do_caso(v_c))));
  perform teste_assert_0215((select count(distinct chave) from fn_historico_do_caso(v_c)) = v_n
                        and not exists (select 1 from fn_historico_do_caso(v_c) where chave is null or chave = ''),
    'a chave é única e nunca vazia: uma por evento');
  v_pags := '{}'; v_cur_em := null; v_cur_ch := null;
  for v_i in 1..40 loop
    select array_agg(h.chave order by h.em desc, h.chave collate "C" desc) into v_pg
      from fn_historico_do_caso(v_c, 2, v_cur_em, v_cur_ch) h;
    exit when v_pg is null;
    v_pags := v_pags || v_pg;
    select h.em, h.chave into v_cur_em, v_cur_ch
      from fn_historico_do_caso(v_c, 2, v_cur_em, v_cur_ch) h order by h.em, h.chave collate "C" limit 1;
  end loop;
  select array_agg(h.chave order by h.em desc, h.chave collate "C" desc) into v_inteira from fn_historico_do_caso(v_c) h;
  perform teste_assert_0215(cardinality(v_pags) = v_n and v_pags = v_inteira,
    'páginas de 2 sobre eventos EMPATADOS no mesmo instante, juntas, são a lista inteira: sem repetir e sem pular',
    format('%s paginadas de %s', cardinality(v_pags), v_n));
  perform teste_assert_0215((select count(*) from fn_historico_do_caso(v_c, 200, (select max(em) from fn_historico_do_caso(v_c)))) = 0,
    'sem p_antes_chave o cursor segue estrito no instante (compatível com quem só tem o instante)');

  raise notice 'OK — fn_historico_do_caso: 16 eventos do caso A em ordem, sem vazar o B, sem erro no vazio; achados da revisão (caso C) medidos';
end $$;

delete from caso where nome like '0215 —%';
