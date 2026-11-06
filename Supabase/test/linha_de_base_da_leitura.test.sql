-- =============================================================================
-- 0225 — A LEITURA QUE SÓ SE MEDIA SOMADA POR LOTE: a cobertura por DOCUMENTO (linha de base da P4)
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md): os números por guarda desligada estão no cabeçalho de
-- Supabase/migrations/0225_a_leitura_que_so_se_media_somada_por_lote.sql ("MEDIÇÃO NÃO-VAZIA"): 53 asserts, 21 variantes aplicadas uma a uma, 0 reprovações com a migration intacta.
--
-- O QUE AFIRMA (comportamento, não mecanismo):
--   1. a gravação leva a medição: chamada COM p_medicao grava o objeto no evento; chamada SEM grava `medicao` nula EXPLÍCITA (a chave existe, valor nulo) —
--      "não mediu" nunca parece "mediu zero"; medição que não é objeto grava `medicao_invalida` com o tipo, não descarta calado;
--   2. os chamadores antigos continuam funcionando: a chamada do n8n (argumentos nomeados, sem p_medicao) e a de 5 posicionais gravam o mesmo de antes,
--      e NÃO existe sobrecarga (uma só fn_registrar_campos_extraidos: com a antiga ao lado, a chamada do n8n ficaria ambígua);
--   3. a linha de base devolve UMA linha por documento_versao (a pendência é por documento: não multiplica), a cobertura certa (sem arredondar nem truncar em 1),
--      o ÚLTIMO evento da versão vence um reprocessamento, e cada ausência diz por quê (extracao_nao_rodou / sem_medicao / medicao_invalida / medicao_incompleta /
--      documento_sem_contas): documento sem evento NÃO é documento que rodou e não achou nada;
--   4. as pendências contadas são as ABERTAS da origem extração, por tipo (resolvida e outra origem não entram);
--   5. SECURITY INVOKER e somente leitura: a RLS vale (Analista alocada vê, Analista de outro mandato recebe zero linhas), e a ACL não abre para anon;
--   6. a sonda enxerga os 5 requisitos da 0225 e os marcadores de código ocorrem UMA vez no corpo publicado.
-- =============================================================================
\set ON_ERROR_STOP on

-- `p4.medindo = on` (PGOPTIONS='-c p4.medindo=on') vira `raise warning` e CONTA: é como se mede quantos asserts uma guarda desligada reprova.
create or replace function teste_assert_p4(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform set_config('p4.execucoes', (coalesce(nullif(current_setting('p4.execucoes', true), ''), '0')::int + 1)::text, false);
  if p_cond is true then
    raise notice 'ok    %', p_nome;
  elsif current_setting('p4.medindo', true) = 'on' then
    perform set_config('p4.falhas', (coalesce(nullif(current_setting('p4.falhas', true), ''), '0')::int + 1)::text, false);
    raise warning 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- Dentro de UMA transação `now()` é constante: dois eventos gravados no mesmo `do` empatam em criado_em e o "último" seria sorteio pelo id. Em produção cada
-- chamada do n8n é a sua transação (instantes diferentes). Antes de regravar uma versão, o teste recua os eventos dela, para o último ser o mais novo de verdade.
create or replace function teste_recua_p4(p_versao uuid) returns void language sql as $$
  update evento_auditoria set criado_em = criado_em - interval '1 minute'
   where acao = 'extracao_sombra' and entidade_ref = 'documento_versao:' || p_versao $$;

create or replace function teste_ocorrencias_p4(p_texto text, p_marcador text) returns int language sql immutable as $$
  select (length(p_texto) - length(replace(p_texto, p_marcador, ''))) / length(p_marcador) $$;

create or replace function teste_como_p4(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create or replace function teste_servico_p4() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

delete from caso where nome like '0225 —%';
delete from auth.users where id in ('00000000-0000-0000-0000-00000000e251', '00000000-0000-0000-0000-00000000e252', '00000000-0000-0000-0000-00000000e253');

do $$
declare
  u_socio uuid := '00000000-0000-0000-0000-00000000e251';
  u_ana   uuid := '00000000-0000-0000-0000-00000000e252';   -- Analista, alocada em A
  u_xan   uuid := '00000000-0000-0000-0000-00000000e253';   -- Analista, alocado só em B
  v_a uuid; v_b uuid; v_r jsonb;
  v_doc_nr uuid; v_ver_nr uuid;       -- nunca extraído
  v_doc_re uuid; v_ver_re1 uuid; v_ver_re2 uuid;   -- reprocessado: 2 versões, a 1ª com 2 eventos
  v_ver_sm uuid;                       -- chamada sem medição
  v_ver_in uuid;                       -- medição não-objeto
  v_ver_zr uuid;                       -- documento sem contas
  v_ver_ic uuid;                       -- medição incompleta
  v_doc_pd uuid; v_ver_pd1 uuid; v_ver_pd2 uuid;   -- pendências, 2 versões
  v_ver_n8 uuid;                       -- chamada do n8n (nomeada)
  v_ver_p5 uuid;                       -- 5 posicionais
  v_doc_x uuid;
  v_ev jsonb; v_n int; v_l record; v_n_ant int; v_txt text;
  v_campos jsonb := jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Receita','valor_num','1000','periodo_coluna','2025','confianca','0.9'),
    jsonb_build_object('ordem',1,'chave','Custo','valor_num','400','periodo_coluna','2025','confianca','0.9'));
  v_rep jsonb := jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Clientes','valor_num','9000','periodo_coluna','2023','confianca','0.99'),
    jsonb_build_object('ordem',1,'chave','Estoques','valor_num','9000','periodo_coluna','2023','confianca','0.99'),
    jsonb_build_object('ordem',2,'chave','Adiantamentos','valor_num','9000','periodo_coluna','2023','confianca','0.99'),
    jsonb_build_object('ordem',3,'chave','Outros créditos','valor_num','9000','periodo_coluna','2023','confianca','0.99'));
begin
  -- ---------------------------------------------------------------- montagem (Sócio de teste, JWT do run.sh)
  insert into auth.users (id, email) values (u_socio, 'socio@0225.local'), (u_ana, 'ana@0225.local'), (u_xan, 'xan@0225.local');
  v_a := fn_upsert_caso('0225 — mandato A');
  v_b := fn_upsert_caso('0225 — mandato B');
  perform fn_definir_papel(u_socio, 'socio', 'teste 0225');
  perform fn_definir_papel(u_ana, 'analista');
  perform fn_definir_papel(u_xan, 'analista');
  perform fn_alocar(v_a, u_ana);
  perform fn_alocar(v_b, u_xan);

  -- Seis documentos de vocabulários diferentes no mandato A; cada um uma situação da linha de base.
  v_r := fn_registrar_documento(v_a, 'ALFA SA', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo', 'supabase_storage', v_a || '/nr.pdf', 'A nunca extraido.pdf', true, 'H-NR-0225', 'ok');
  v_doc_nr := (v_r->>'documento_id')::uuid; v_ver_nr := (v_r->>'documento_versao_id')::uuid;

  v_r := fn_registrar_documento(v_a, 'ALFA SA', 'anual', '2025', 'DRE', 0.9, 'nome_arquivo', 'supabase_storage', v_a || '/re.pdf', 'B reprocessado.pdf', true, 'H-RE-0225', 'ok');
  v_doc_re := (v_r->>'documento_id')::uuid; v_ver_re1 := (v_r->>'documento_versao_id')::uuid;
  insert into documento_versao (documento_id, n_versao, arquivo_ref, nome_original) values (v_doc_re, 2, v_a || '/re2.pdf', 'B reprocessado.pdf') returning id into v_ver_re2;

  v_r := fn_registrar_documento(v_a, 'ALFA SA', 'anual', '2025', 'BALANCETE', 0.9, 'nome_arquivo', 'supabase_storage', v_a || '/sm.pdf', 'C sem medicao.pdf', true, 'H-SM-0225', 'ok');
  v_ver_sm := (v_r->>'documento_versao_id')::uuid;
  v_r := fn_registrar_documento(v_a, 'ALFA SA', 'anual', '2025', 'BALANCETE', 0.9, 'nome_arquivo', 'supabase_storage', v_a || '/in.pdf', 'D medicao invalida.pdf', true, 'H-IN-0225', 'ok');
  v_ver_in := (v_r->>'documento_versao_id')::uuid;
  v_r := fn_registrar_documento(v_a, 'ALFA SA', 'anual', '2025', 'BALANCETE', 0.9, 'nome_arquivo', 'supabase_storage', v_a || '/zr.pdf', 'E sem contas.pdf', true, 'H-ZR-0225', 'ok');
  v_ver_zr := (v_r->>'documento_versao_id')::uuid;
  v_r := fn_registrar_documento(v_a, 'ALFA SA', 'anual', '2025', 'BALANCETE', 0.9, 'nome_arquivo', 'supabase_storage', v_a || '/ic.pdf', 'F incompleta.pdf', true, 'H-IC-0225', 'ok');
  v_ver_ic := (v_r->>'documento_versao_id')::uuid;
  v_r := fn_registrar_documento(v_a, 'ALFA SA', 'anual', '2023', 'BALANCO', 0.9, 'nome_arquivo', 'supabase_storage', v_a || '/pd.pdf', 'G pendencias.pdf', true, 'H-PD-0225', 'ok');
  v_doc_pd := (v_r->>'documento_id')::uuid; v_ver_pd1 := (v_r->>'documento_versao_id')::uuid;
  insert into documento_versao (documento_id, n_versao, arquivo_ref, nome_original) values (v_doc_pd, 2, v_a || '/pd2.pdf', 'G pendencias.pdf') returning id into v_ver_pd2;
  v_r := fn_registrar_documento(v_a, 'ALFA SA', 'anual', '2025', 'BALANCETE', 0.9, 'nome_arquivo', 'supabase_storage', v_a || '/n8.pdf', 'H chamada do n8n.pdf', true, 'H-N8-0225', 'ok');
  v_ver_n8 := (v_r->>'documento_versao_id')::uuid;
  v_r := fn_registrar_documento(v_a, 'ALFA SA', 'anual', '2025', 'BALANCETE', 0.9, 'nome_arquivo', 'supabase_storage', v_a || '/p5.pdf', 'I cinco posicionais.pdf', true, 'H-P5-0225', 'ok');
  v_ver_p5 := (v_r->>'documento_versao_id')::uuid;
  -- Mandato B: um documento extraído e medido (para provar que o A não o vê e vice-versa).
  v_r := fn_registrar_documento(v_b, 'BETA SA', 'anual', '2025', 'DRE', 0.9, 'nome_arquivo', 'supabase_storage', v_b || '/b.pdf', 'Z do outro mandato.pdf', true, 'H-B-0225', 'ok');
  v_doc_x := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, v_campos, 'N0', null, true, '{"contas_no_documento": 2, "linhas_devolvidas": 2}'::jsonb);

  -- ---------------------------------------------------------------- 1. a gravação leva a medição
  raise notice '--- 1. a gravação leva a medição: objeto como veio, nula EXPLÍCITA quando não mediu, tipo errado vira medicao_invalida ---';
  -- B: dois eventos na mesma versão (reprocessou): a 1ª leitura devolveu 5 de 10; a 2ª, 12 de 10 (cobertura acima de 1, como medido em produção).
  perform fn_registrar_campos_extraidos(v_ver_re1, v_campos, 'N0', null, true,
    '{"contas_no_documento": 10, "linhas_devolvidas": 5, "contas_distintas": 5, "blocos": 2, "blocos_planejados": 2, "custo_usd": 0.12, "tokens": 900}'::jsonb);
  perform teste_recua_p4(v_ver_re1);
  perform fn_registrar_campos_extraidos(v_ver_re1, v_campos, 'N0', null, true,
    '{"contas_no_documento": 10, "linhas_devolvidas": 12, "contas_distintas": 9, "blocos": 3, "blocos_planejados": 3, "custo_usd": 0.31, "tokens": 2100}'::jsonb);
  select depois into v_ev from evento_auditoria where acao = 'extracao_sombra' and entidade_ref = 'documento_versao:' || v_ver_re1 order by criado_em desc, id desc limit 1;
  perform teste_assert_p4(v_ev->'medicao' = '{"contas_no_documento": 10, "linhas_devolvidas": 12, "contas_distintas": 9, "blocos": 3, "blocos_planejados": 3, "custo_usd": 0.31, "tokens": 2100}'::jsonb,
    'a medição vai para o evento como veio (todos os campos do n8n, sem validar campo a campo)', v_ev::text);
  perform teste_assert_p4(not (v_ev ? 'medicao_invalida'), 'medição objeto não grava medicao_invalida', v_ev::text);

  perform fn_registrar_campos_extraidos(v_ver_sm, v_campos, 'N0', null, true);
  select depois into v_ev from evento_auditoria where acao = 'extracao_sombra' and entidade_ref = 'documento_versao:' || v_ver_sm;
  perform teste_assert_p4(v_ev ? 'medicao' and jsonb_typeof(v_ev->'medicao') = 'null',
    'chamada SEM medição grava a chave `medicao` nula EXPLÍCITA (distinguível de medição zerada e de evento antigo, que não tem a chave)', v_ev::text);
  perform teste_assert_p4(not (v_ev ? 'medicao_invalida'), 'chamada sem medição não é "inválida"', v_ev::text);
  perform teste_assert_p4((v_ev->>'campos')::int = 2 and v_ev->>'nivel' = 'N0' and v_ev ? 'auto_aceitos' and v_ev ? 'tem_dado_financeiro' and v_ev ? 'falha_motivo',
    'o resto do evento é o de sempre (campos, nivel, auto_aceitos, tem_dado_financeiro, falha_motivo)', v_ev::text);

  perform fn_registrar_campos_extraidos(v_ver_in, v_campos, 'N0', null, true, '"texto solto"'::jsonb);
  select depois into v_ev from evento_auditoria where acao = 'extracao_sombra' and entidade_ref = 'documento_versao:' || v_ver_in;
  perform teste_assert_p4(v_ev->>'medicao_invalida' = 'string', 'medição que é texto grava medicao_invalida com o tipo recebido (não descarta calado)', v_ev::text);
  perform teste_assert_p4(jsonb_typeof(v_ev->'medicao') = 'null', 'e a `medicao` fica nula (o texto não é tomado por medição)', v_ev::text);
  perform teste_recua_p4(v_ver_in);
  perform fn_registrar_campos_extraidos(v_ver_in, v_campos, 'N0', null, true, '[1,2]'::jsonb);
  select depois into v_ev from evento_auditoria where acao = 'extracao_sombra' and entidade_ref = 'documento_versao:' || v_ver_in order by criado_em desc, id desc limit 1;
  perform teste_assert_p4(v_ev->>'medicao_invalida' = 'array', 'medição que é array também é inválida, com o tipo', v_ev::text);
  perform teste_recua_p4(v_ver_in);
  perform fn_registrar_campos_extraidos(v_ver_in, v_campos, 'N0', null, true, 'null'::jsonb);
  select depois into v_ev from evento_auditoria where acao = 'extracao_sombra' and entidade_ref = 'documento_versao:' || v_ver_in order by criado_em desc, id desc limit 1;
  perform teste_assert_p4(not (v_ev ? 'medicao_invalida') and jsonb_typeof(v_ev->'medicao') = 'null',
    'JSON null é "não mediu", igual ao SQL NULL: nem medição, nem inválida', v_ev::text);
  -- (a versão D termina com 'null' como último evento; o assert da linha de base abaixo usa uma chamada inválida de novo)
  perform teste_recua_p4(v_ver_in);
  perform fn_registrar_campos_extraidos(v_ver_in, v_campos, 'N0', null, true, '42'::jsonb);
  select depois into v_ev from evento_auditoria where acao = 'extracao_sombra' and entidade_ref = 'documento_versao:' || v_ver_in order by criado_em desc, id desc limit 1;
  perform teste_assert_p4(v_ev->>'medicao_invalida' = 'number', 'medição que é número é inválida, com o tipo', v_ev::text);

  -- ---------------------------------------------------------------- 2. os chamadores antigos continuam funcionando
  raise notice '--- 2. os chamadores antigos continuam funcionando, e não há sobrecarga ---';
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'fn_registrar_campos_extraidos';
  perform teste_assert_p4(v_n = 1, 'UMA só fn_registrar_campos_extraidos (a assinatura antiga foi trocada, não duplicada)', v_n::text);
  -- Exatamente a chamada do nó "Gravar Campos (Sombra)" do n8n (argumentos nomeados, sem p_medicao).
  select fn_registrar_campos_extraidos(v_ver_n8, v_campos, p_falha_motivo => null::text, p_tem_dado_financeiro => true::boolean) into v_n;
  perform teste_assert_p4(v_n = 2, 'a chamada do n8n (nomeada, sem p_medicao) grava os 2 campos', v_n::text);
  select depois into v_ev from evento_auditoria where acao = 'extracao_sombra' and entidade_ref = 'documento_versao:' || v_ver_n8;
  perform teste_assert_p4(v_ev ? 'medicao' and jsonb_typeof(v_ev->'medicao') = 'null' and (v_ev->>'campos')::int = 2,
    'e o evento dela sai com medicao nula explícita (n8n anterior à medição)', v_ev::text);
  select fn_registrar_campos_extraidos(v_ver_p5, v_campos, 'N2', null, true) into v_n;
  perform teste_assert_p4(v_n = 2, 'a chamada de 5 posicionais (a dos testes e do arnês) continua valendo', v_n::text);
  perform teste_recua_p4(v_ver_p5);
  select fn_registrar_campos_extraidos(v_ver_p5, v_campos, 'N0', null, true, p_medicao => '{"contas_no_documento": 2, "linhas_devolvidas": 2}'::jsonb) into v_n;
  perform teste_assert_p4(v_n = 2, 'p_medicao também entra nomeado', v_n::text);
  perform teste_assert_p4(has_function_privilege('authenticated', 'fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text, boolean, jsonb)', 'execute')
      and has_function_privilege('service_role', 'fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text, boolean, jsonb)', 'execute')
      and not has_function_privilege('anon', 'fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text, boolean, jsonb)', 'execute'),
    'a ACL da gravação foi refeita como era: authenticated e service_role executam, anon não', null);
  perform teste_assert_p4(not (select prosecdef from pg_proc where oid = 'fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text, boolean, jsonb)'::regprocedure),
    'continua SECURITY INVOKER', null);

  -- ---------------------------------------------------------------- 3. a linha de base
  raise notice '--- 3. a linha de base: uma linha por versão, cobertura certa, cada ausência diz por quê ---';
  -- Documentos restantes: E (sem contas), F (incompleta), G (pendências).
  perform fn_registrar_campos_extraidos(v_ver_zr, v_campos, 'N0', null, true, '{"contas_no_documento": 0, "linhas_devolvidas": 0}'::jsonb);
  perform fn_registrar_campos_extraidos(v_ver_ic, v_campos, 'N0', null, true, '{"blocos": 1, "custo_usd": 0.01}'::jsonb);
  -- G: a versão 1 vira padrão suspeito (4 contas, mesmo valor); a versão 2 devolve vazia sem dizer que não tem dado (extracao_falhou).
  perform fn_registrar_campos_extraidos(v_ver_pd1, v_rep, 'N0', null, true, '{"contas_no_documento": 4, "linhas_devolvidas": 4}'::jsonb);
  perform fn_registrar_campos_extraidos(v_ver_pd2, '[]'::jsonb, 'N0', 'a IA devolveu vazio', true, '{"contas_no_documento": 8, "linhas_devolvidas": 0}'::jsonb);

  select count(*) into v_n from fn_linha_de_base_extracao(v_a);
  -- A, B(2 versões), C, D, E, F, G(2 versões), H, I = 11 versões
  perform teste_assert_p4(v_n = 11, 'UMA linha por documento_versao do mandato (9 documentos, 11 versões; pendência por documento NÃO multiplica)', v_n::text);
  select count(*) into v_n from fn_linha_de_base_extracao(v_a) where documento_versao_id is null;
  perform teste_assert_p4(v_n = 0, 'toda linha traz a versão', v_n::text);
  select count(*) into v_n from fn_linha_de_base_extracao(v_a) where nome_original like 'Z %';
  perform teste_assert_p4(v_n = 0, 'documento de outro mandato não entra na linha de base deste', v_n::text);

  select * into v_l from fn_linha_de_base_extracao(v_a) where documento_versao_id = v_ver_nr;
  perform teste_assert_p4(v_l.extracao_rodou is false and v_l.cobertura is null and v_l.cobertura_motivo = 'extracao_nao_rodou' and v_l.n_campos = 0,
    'documento SEM evento de extração: extracao_rodou = false, cobertura nula, motivo extracao_nao_rodou (não é "rodou e não achou nada")', row_to_json(v_l)::text);
  perform teste_assert_p4(v_l.nome_original = 'A nunca extraido.pdf' and v_l.tipo_taxonomia = 'BALANCO' and v_l.extraido_em is null and v_l.falha_motivo is null,
    'nome, tipo e ausência de data/falha do documento não extraído', row_to_json(v_l)::text);

  select * into v_l from fn_linha_de_base_extracao(v_a) where documento_versao_id = v_ver_re1;
  perform teste_assert_p4(v_l.extracao_rodou and v_l.contas_no_documento = 10 and v_l.linhas_devolvidas = 12,
    'o ÚLTIMO evento da versão vence o reprocessamento (12 linhas, não as 5 da primeira leitura)', row_to_json(v_l)::text);
  perform teste_assert_p4(v_l.cobertura = 1.2 and v_l.cobertura_motivo is null,
    'cobertura = linhas/contas = 1,2: SEM truncar em 1 (a régua que conta errado tem de aparecer) e sem motivo quando existe', row_to_json(v_l)::text);
  perform teste_assert_p4(v_l.n_campos = 4 and v_l.nome_original = 'B reprocessado.pdf' and v_l.n_versao = 1,
    'n_campos conta os campos da VERSÃO (as duas gravações do reprocesso: 2+2) e a versão é a 1', row_to_json(v_l)::text);
  select * into v_l from fn_linha_de_base_extracao(v_a) where documento_versao_id = v_ver_re2;
  perform teste_assert_p4(v_l.extracao_rodou is false and v_l.cobertura_motivo = 'extracao_nao_rodou' and v_l.n_versao = 2,
    'a versão 2 do mesmo documento, sem evento, não herda o veredito da versão 1', row_to_json(v_l)::text);

  select * into v_l from fn_linha_de_base_extracao(v_a) where documento_versao_id = v_ver_sm;
  perform teste_assert_p4(v_l.extracao_rodou and v_l.cobertura is null and v_l.cobertura_motivo = 'sem_medicao' and v_l.n_campos = 2,
    'evento sem medição (n8n anterior): rodou, cobertura nula, motivo sem_medicao — diferente de "não rodou"', row_to_json(v_l)::text);
  select * into v_l from fn_linha_de_base_extracao(v_a) where documento_versao_id = v_ver_in;
  perform teste_assert_p4(v_l.extracao_rodou and v_l.cobertura is null and v_l.cobertura_motivo = 'medicao_invalida',
    'medição não-objeto: cobertura nula e motivo medicao_invalida', row_to_json(v_l)::text);
  select * into v_l from fn_linha_de_base_extracao(v_a) where documento_versao_id = v_ver_zr;
  perform teste_assert_p4(v_l.contas_no_documento = 0 and v_l.linhas_devolvidas = 0 and v_l.cobertura is null and v_l.cobertura_motivo = 'documento_sem_contas',
    'documento com 0 contas: cobertura NULL (não 0, nem divisão por zero) com motivo documento_sem_contas', row_to_json(v_l)::text);
  select * into v_l from fn_linha_de_base_extracao(v_a) where documento_versao_id = v_ver_ic;
  perform teste_assert_p4(v_l.extracao_rodou and v_l.cobertura is null and v_l.cobertura_motivo = 'medicao_incompleta' and v_l.contas_no_documento is null,
    'medição sem contas_no_documento/linhas_devolvidas: cobertura nula e motivo medicao_incompleta', row_to_json(v_l)::text);

  select * into v_l from fn_linha_de_base_extracao(v_a) where documento_versao_id = v_ver_n8;
  perform teste_assert_p4(v_l.cobertura_motivo = 'sem_medicao', 'a chamada do n8n sem medição aparece como sem_medicao', row_to_json(v_l)::text);
  select * into v_l from fn_linha_de_base_extracao(v_a) where documento_versao_id = v_ver_p5;
  perform teste_assert_p4(v_l.cobertura = 1 and v_l.linhas_devolvidas = 2 and v_l.n_campos = 4,
    'cobertura 1 exata quando devolveu tudo (último evento: p_medicao nomeado) e n_campos = 2+2', row_to_json(v_l)::text);

  -- ---------------------------------------------------------------- 4. pendências por tipo (abertas, da origem extração)
  raise notice '--- 4. pendências: abertas, da origem extração, por tipo, sem multiplicar linhas ---';
  select * into v_l from fn_linha_de_base_extracao(v_a) where documento_versao_id = v_ver_pd1;
  perform teste_assert_p4(v_l.pendencias_extracao_padrao_suspeito = 1 and v_l.pendencias_extracao_falhou = 1,
    'a pendência é do DOCUMENTO: as duas versões do G mostram 1 padrão suspeito e 1 extracao_falhou', row_to_json(v_l)::text);
  select * into v_l from fn_linha_de_base_extracao(v_a) where documento_versao_id = v_ver_pd2;
  perform teste_assert_p4(v_l.pendencias_extracao_padrao_suspeito = 1 and v_l.pendencias_extracao_falhou = 1 and v_l.falha_motivo = 'a IA devolveu vazio'
      and v_l.contas_no_documento = 8 and v_l.cobertura = 0 and v_l.cobertura_motivo is null,
    'versão 2 do G: falha_motivo do evento, cobertura 0 MEDIDA (8 contas, 0 linhas) com motivo nulo — zero medido ≠ ausência', row_to_json(v_l)::text);
  select count(*) into v_n from fn_linha_de_base_extracao(v_a) where documento_id = v_doc_pd;
  perform teste_assert_p4(v_n = 2, 'o documento com 2 versões e 2 pendências continua em 2 linhas (não 4)', v_n::text);
  select * into v_l from fn_linha_de_base_extracao(v_a) where documento_versao_id = v_ver_re1;
  perform teste_assert_p4(v_l.pendencias_extracao_padrao_suspeito = 0 and v_l.pendencias_extracao_falhou = 0, 'documento sem pendência: zeros (não nulos)', row_to_json(v_l)::text);
  -- resolvida e de outra origem não entram
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'teste' where documento_id = v_doc_pd and tipo = 'extracao_falhou';
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
    values (v_a, 'reconciliacao', 'extracao_falhou', 'importante', true, 'de outra origem', v_doc_pd, 'teste:0225:outra_origem');
  select * into v_l from fn_linha_de_base_extracao(v_a) where documento_versao_id = v_ver_pd1;
  perform teste_assert_p4(v_l.pendencias_extracao_falhou = 0 and v_l.pendencias_extracao_padrao_suspeito = 1,
    'pendência resolvida e pendência de outra origem NÃO entram na contagem', row_to_json(v_l)::text);

  -- ---------------------------------------------------------------- 5. RLS e somente leitura
  raise notice '--- 5. SECURITY INVOKER: a RLS vale; somente leitura; sem anon ---';
  perform teste_como_p4(u_ana);
  select count(*) into v_n from fn_linha_de_base_extracao(v_a);
  perform teste_servico_p4();
  perform teste_assert_p4(v_n = 11, 'a Analista alocada no mandato A vê as 11 linhas', v_n::text);
  perform teste_como_p4(u_xan);
  select count(*) into v_n from fn_linha_de_base_extracao(v_a);
  perform teste_servico_p4();
  perform teste_assert_p4(v_n = 0, 'a Analista de OUTRO mandato recebe zero linhas (RLS)', v_n::text);
  perform teste_como_p4(u_xan);
  select count(*) into v_n from fn_linha_de_base_extracao(v_b);
  perform teste_servico_p4();
  perform teste_assert_p4(v_n = 1, 'e vê o PRÓPRIO mandato B (a RLS não é larga nem estreita demais)', v_n::text);
  perform teste_assert_p4(not (select prosecdef from pg_proc where oid = 'fn_linha_de_base_extracao(uuid)'::regprocedure)
      and (select provolatile from pg_proc where oid = 'fn_linha_de_base_extracao(uuid)'::regprocedure) = 's',
    'fn_linha_de_base_extracao é SECURITY INVOKER e STABLE (somente leitura)', null);
  perform teste_assert_p4(has_function_privilege('authenticated', 'fn_linha_de_base_extracao(uuid)', 'execute')
      and has_function_privilege('service_role', 'fn_linha_de_base_extracao(uuid)', 'execute')
      and not has_function_privilege('anon', 'fn_linha_de_base_extracao(uuid)', 'execute'),
    'authenticated e service_role executam; anon não', null);
  select count(*) into v_n_ant from evento_auditoria where acao = 'extracao_sombra';
  perform * from fn_linha_de_base_extracao(v_a);
  select count(*) into v_n from evento_auditoria where acao = 'extracao_sombra';
  perform teste_assert_p4(v_n = v_n_ant, 'ler a linha de base não grava evento', null);
  select count(*) into v_n from fn_linha_de_base_extracao('00000000-0000-0000-0000-000000000000'::uuid);
  perform teste_assert_p4(v_n = 0, 'mandato inexistente: zero linhas, sem erro', v_n::text);

  -- ---------------------------------------------------------------- 6. a sonda
  raise notice '--- 6. a sonda enxerga os 5 requisitos da 0225 ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0225' and presente;
  perform teste_assert_p4(v_n = 5, 'os 5 requisitos da 0225 estão presentes', v_n::text);
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0225' and not presente;
  perform teste_assert_p4(v_n = 0, 'nenhum requisito da 0225 ausente', v_n::text);
  -- Os marcadores são CÓDIGO, não comentário: cada um ocorre UMA vez no corpo publicado (pg_get_functiondef traz comentário, então um marcador que também
  -- estivesse num comentário contaria 2 e a sonda ficaria verde com o código removido). Os literais abaixo são os do catálogo da 0225.
  v_txt := pg_get_functiondef('fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text, boolean, jsonb)'::regprocedure);
  perform teste_assert_p4(teste_ocorrencias_p4(v_txt, 'p_medicao jsonb DEFAULT NULL::jsonb') = 1,
    'o marcador da assinatura nova ocorre UMA vez no corpo publicado', null);
  perform teste_assert_p4(teste_ocorrencias_p4(v_txt, '''medicao'', v_medicao') = 1,
    'o marcador da gravação da chave medicao ocorre UMA vez (código, não comentário)', null);
  perform teste_assert_p4(teste_ocorrencias_p4(v_txt, '''medicao_invalida'', jsonb_typeof(p_medicao)') = 1,
    'o marcador de medicao_invalida ocorre UMA vez (código, não comentário)', null);
  v_txt := pg_get_functiondef('fn_linha_de_base_extracao(uuid)'::regprocedure);
  perform teste_assert_p4(teste_ocorrencias_p4(v_txt, '''sem_medicao''') = 1,
    'o marcador do motivo da cobertura ocorre UMA vez no corpo de fn_linha_de_base_extracao', null);
  perform teste_assert_p4((select count(*) from instalacao_requisito r
                            where r.migration = '0225' and r.tipo = 'corpo'
                              and position(r.marcador in pg_get_functiondef(to_regproc('public.' || r.objeto)::oid)) > 0) = 4,
    'os 4 marcadores do catálogo estão todos no corpo publicado (e são os 4 conferidos acima)', null);
  select count(*) into v_n from instalacao_requisito where migration = '0225';
  perform teste_assert_p4(v_n = 5, 'o catálogo tem exatamente os 5 requisitos da 0225', v_n::text);
  perform teste_assert_p4((select ate_migration from instalacao_cobertura) >= '0225', 'a cobertura do catálogo declara a 0225', null);

  -- ---------------------------------------------------------------- limpeza
  delete from caso where nome like '0225 —%';
  delete from evento_auditoria where entidade_ref in ('documento_versao:' || v_ver_nr, 'documento_versao:' || v_ver_re1, 'documento_versao:' || v_ver_re2,
    'documento_versao:' || v_ver_sm, 'documento_versao:' || v_ver_in, 'documento_versao:' || v_ver_zr, 'documento_versao:' || v_ver_ic,
    'documento_versao:' || v_ver_pd1, 'documento_versao:' || v_ver_pd2, 'documento_versao:' || v_ver_n8, 'documento_versao:' || v_ver_p5);
  delete from auth.users where id in (u_socio, u_ana, u_xan);

  raise notice 'EXECUCOES=% FALHAS=%', current_setting('p4.execucoes', true), coalesce(current_setting('p4.falhas', true), '0');
  if current_setting('p4.medindo', true) is distinct from 'on' then
    raise notice 'TODOS OS TESTES DA LINHA DE BASE DA LEITURA PASSARAM';
  end if;
end $$;
