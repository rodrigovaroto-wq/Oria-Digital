-- Testes do RESUMO do arquivo oficial (Supabase/migrations/0207): carga em partes, reconferência do servidor,
-- recusa que apaga, ausente, reenvio, recarga. Cada assert descreve COMPORTAMENTO (o que o banco aceita,
-- recusa e devolve), não como a função o faz.
-- AS FIXTURES SÃO REAIS (regra 4): saída de lerEnvelopeDeBuffer(gerarEcdComLancamentos().buf, {resumir:true}),
-- o MESMO leitor que o navegador roda. Os desvios (total a mais, registro a mais, I155 que não fecha...) são
-- alterações pontuais dessa saída, e dizem qual. Ainda NÃO existe resumo de ECD de produção no repositório
-- (aceite da onda 1: 3 ECDs reais): isto prova a regra, não que uma ECD real chegue assim.
\set ON_ERROR_STOP on

create or replace function teste_assert_ro(p_ok boolean, p_nome text)
returns void language plpgsql as $$
begin
  if p_ok then raise notice 'ok    %', p_nome;
  else raise exception 'FALHOU: %', p_nome; end if;
end $$;

-- Executa um comando e devolve a mensagem do erro, ou 'ok'. O erro desfaz só o subbloco.
create or replace function teste_erro_ro(p_sql text)
returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;

-- Fixtures: SAÍDA REAL de lerEnvelopeDeBuffer(gerarEcdComLancamentos().buf, {resumir:true}) (Leitor/lib,
-- Dados de Teste/fontes-oficiais/gerar.mjs), colada como veio. Para regerar:
--   node -e 'import("./Leitor/lib/envelope.mjs").then(async m=>{const g=await import("./Dados de Teste/fontes-oficiais/gerar.mjs");
--     const r=m.lerEnvelopeDeBuffer(g.gerarEcdComLancamentos().buf,{resumir:true});console.log(JSON.stringify(r))})'
create or replace function teste_ro_env() returns jsonb language sql as $f$ select $j${"familia":"sped","subtipo":"ECD","versao_leiaute":"9.00","hash_sha256":"b442aab86723d08fc19e132dc5fe07810ad782adbbc52d8ff0e3615223ce0d25","cnpj":"11222333000181","periodo_ini":"2025-01-01","periodo_fim":"2025-12-31","chave_natural":"11222333000181|ECD|2025-01-01|2025-12-31|-|G","retificadora":false,"controle_tipo":"contagem_declarada","controle_declarado":38,"controle_lido":38,"status":"lido","detalhe":{"cod_scp":null,"ind_esc":"G","nome":"AÇÚCAR SINTÉTICO LTDA (fictícia)","por_registro":{"9900":13,"9999":1,"0000":1,"0001":1,"I010":1,"I050":2,"I150":1,"I155":2,"I200":4,"I250":9,"J005":1,"J150":1,"J900":1},"divergencias_9900":[],"linhas_apos_9999":0},"leitor_versao":"leitor-envelope/1"}$j$::jsonb $f$;
create or replace function teste_ro_registros() returns jsonb language sql as $f$ select $j$[[1,"|0000|LECD|01012025|31122025|AÇÚCAR SINTÉTICO LTDA (fictícia)|11222333000181|SP||3550308||0|0|0|0||0|0||N|N|0|0||"],[3,"|I010|G|9.00|"],[4,"|I050|01012025|01|A|5|1.1.01|1.1|CAIXA (AÇÚCAR)|"],[5,"|I050|01012025|04|A|5|3.1.01|3.1|RECEITA DE VENDAS|"],[6,"|I150|01012025|31012025|"],[7,"|I155|1.1.01||0,00|D|1.500,00|0,00|1.500,00|D|"],[8,"|I155|3.1.01||0,00|C|0,00|1.500,00|1.500,00|C|"],[22,"|J005|01012025|31122025|1||"],[23,"|J150|1|1|T|1|RECEITA LÍQUIDA|1.700,00|C|0,00|C||"],[24,"|J900|TERMO|"]]$j$::jsonb $f$;
create or replace function teste_ro_grupos() returns jsonb language sql as $f$ select $j$[{"conta":"1.1.01","mes":"2025-01","ind_lcto":"N","debito":150000,"credito":0,"partidas":1,"partidas_sem_valor":0,"primeira_linha":10},{"conta":"3.1.01","mes":"2025-01","ind_lcto":"N","debito":0,"credito":150000,"partidas":2,"partidas_sem_valor":0,"primeira_linha":11},{"conta":"1.1.01","mes":"2025-02","ind_lcto":"N","debito":20000,"credito":0,"partidas":1,"partidas_sem_valor":0,"primeira_linha":14},{"conta":"3.1.01","mes":"2025-02","ind_lcto":"N","debito":0,"credito":20000,"partidas":1,"partidas_sem_valor":0,"primeira_linha":15},{"conta":"1.1.01","mes":"2025-12","ind_lcto":"N","debito":10000,"credito":0,"partidas":1,"partidas_sem_valor":0,"primeira_linha":17},{"conta":"3.1.01","mes":"2025-12","ind_lcto":"N","debito":0,"credito":10000,"partidas":1,"partidas_sem_valor":0,"primeira_linha":18},{"conta":"3.1.01","mes":"2025-12","ind_lcto":"E","debito":180000,"credito":0,"partidas":1,"partidas_sem_valor":0,"primeira_linha":20},{"conta":"1.1.01","mes":"2025-12","ind_lcto":"E","debito":0,"credito":180000,"partidas":1,"partidas_sem_valor":0,"primeira_linha":21}]$j$::jsonb $f$;
create or replace function teste_ro_conferencia() returns jsonb language sql as $f$ select $j${"i250_lidos":9,"i250_sem_i200":0,"grupos_com_partida_sem_valor":0,"valores_invalidos":0,"valores_invalidos_amostra":[],"lancamentos_desbalanceados":0,"lancamentos_desbalanceados_amostra":[]}$j$::jsonb $f$;

-- O envelope da fixture com outro hash (cada cenário é um arquivo distinto no mesmo caso).
create or replace function teste_ro_env_h(p_hash text) returns jsonb language sql as $$
  select jsonb_set(teste_ro_env(), '{hash_sha256}', to_jsonb(p_hash)) $$;

-- O cabeçalho que o navegador mandaria, calculado da fixture. p_regs/p_grupos substituem os arrays.
create or replace function teste_ro_cab(p_hash text, p_versao text default 'resumo/1',
                                       p_tot_reg int default null, p_tot_grp int default null)
returns jsonb language sql as $$
  select jsonb_build_object('versao', p_versao, 'hash_sha256', p_hash,
    'conferencia', teste_ro_conferencia(),
    'descartado', 'o lançamento individual (I200/I250) não é guardado',
    'total_registros', coalesce(p_tot_reg, jsonb_array_length(teste_ro_registros())),
    'total_grupos', coalesce(p_tot_grp, jsonb_array_length(teste_ro_grupos())))
$$;

-- Fatias de um array jsonb: elementos [de, ate) (base 0).
create or replace function teste_ro_fatia(p jsonb, de int, ate int) returns jsonb language sql as $$
  select coalesce(jsonb_agg(e order by o), '[]'::jsonb) from jsonb_array_elements(p) with ordinality t(e, o)
   where o > de and o <= ate $$;

do $$
declare
  v_caso uuid; v_off uuid; v_id uuid; v_id2 uuid; v_j jsonb; v_msg text; v_n int; v_h text;
  v_regs jsonb; v_grps jsonb; v_cab jsonb; v_env jsonb;
begin
  insert into caso (nome, trilha_transacional) values ('teste resumo oficial', true) returning id into v_caso;
  v_regs := teste_ro_registros(); v_grps := teste_ro_grupos();

  -- ===== 1. A carga em DUAS PARTES completa =====
  v_h := 'h-carga';
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h), teste_ro_cab(v_h));
  v_id := (v_j->>'id')::uuid;
  perform teste_assert_ro(v_j->>'resumo' = 'em_carga' and v_j->>'status' = 'lido',
    '1-1: iniciar abre a carga (resumo em_carga) sobre o arquivo lido');
  perform teste_assert_ro((select resumo_status from arquivo_oficial where id = v_id) = 'em_carga'
    and (select resumo_total_registros from arquivo_oficial where id = v_id) = 10
    and (select resumo_total_grupos from arquivo_oficial where id = v_id) = 8,
    '1-2: o banco guarda os totais DECLARADOS (10 registros, 8 grupos)');
  v_j := fn_resumo_anexar(v_id, teste_ro_fatia(v_regs, 0, 5), teste_ro_fatia(v_grps, 0, 4));
  perform teste_assert_ro((v_j->>'registros')::int = 5 and (v_j->>'grupos')::int = 4,
    '1-3: a primeira parte devolve as contagens inseridas (5 e 4)');
  v_j := fn_resumo_anexar(v_id, teste_ro_fatia(v_regs, 5, 10), teste_ro_fatia(v_grps, 4, 8));
  perform teste_assert_ro((v_j->>'registros')::int = 5 and (v_j->>'grupos')::int = 4,
    '1-4: a segunda parte devolve as contagens inseridas (5 e 4)');
  v_j := fn_resumo_concluir(v_id);
  perform teste_assert_ro(v_j->>'resumo' = 'completo' and (v_j->>'registros')::int = 10
    and (v_j->>'grupos')::int = 8 and (v_j->>'i155_nao_fecham')::int = 0,
    '1-5: concluir devolve completo, 10 registros, 8 grupos, nenhum I155 fora');
  perform teste_assert_ro((select resumo_status from arquivo_oficial where id = v_id) = 'completo'
    and (select count(*) from arquivo_oficial_registro where arquivo_oficial_id = v_id) = 10
    and (select count(*) from arquivo_oficial_lancamento_mes where arquivo_oficial_id = v_id) = 8,
    '1-6: o resumo completo está gravado (10 registros, 8 grupos)');
  perform teste_assert_ro((select sum(debito) from arquivo_oficial_lancamento_mes where arquivo_oficial_id = v_id) = 360000
    and (select sum(credito) from arquivo_oficial_lancamento_mes where arquivo_oficial_id = v_id) = 360000
    and (select count(*) from arquivo_oficial_lancamento_mes where arquivo_oficial_id = v_id and mes = date '2025-01-01') = 2,
    '1-7: os grupos chegam em centavos e o mês AAAA-MM vira o 1º dia do mês');
  perform teste_assert_ro((select registro from arquivo_oficial_registro where arquivo_oficial_id = v_id and linha = 7) = 'I155'
    and (select conteudo from arquivo_oficial_registro where arquivo_oficial_id = v_id and linha = 24) = '|J900|TERMO|',
    '1-8: cada registro guarda o código e o texto na linha de origem');
  perform teste_assert_ro((select resumo_conferencia->>'i250_lidos' from arquivo_oficial where id = v_id) = '9'
    and (select resumo_conferencia->'i155'->>'total' from arquivo_oficial where id = v_id) = '2'
    and (select resumo_descartado from arquivo_oficial where id = v_id) like '%não é guardado%',
    '1-9: a conferência do leitor e o que foi descartado ficam, e o servidor acrescenta o I155');

  -- ===== 2. Concluir repetido é idempotente; anexar depois de completo é ERRO =====
  v_j := fn_resumo_concluir(v_id);
  perform teste_assert_ro(v_j->>'resumo' = 'completo' and (v_j->>'registros')::int = 10,
    '2-1: concluir repetido devolve o estado já gravado, sem recalcular nem recusar');
  v_msg := teste_erro_ro(format('select fn_resumo_anexar(%L, ''[[30,"|9990|x|"]]''::jsonb, ''[]''::jsonb)', v_id));
  perform teste_assert_ro(v_msg like 'P0001%completo%',
    '2-2: anexar depois de completo é erro (' || left(v_msg, 60) || ')');
  perform teste_assert_ro((select count(*) from arquivo_oficial_registro where arquivo_oficial_id = v_id) = 10,
    '2-3: e nada foi gravado pelo anexar recusado');

  -- ===== 3. Reenvio da mesma versão: o navegador não manda nada; versão nova recarrega e APAGA a anterior =====
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h), teste_ro_cab(v_h));
  perform teste_assert_ro(v_j->>'resumo' = 'reenvio' and (v_j->>'id')::uuid = v_id
    and (select count(*) from arquivo_oficial_registro where arquivo_oficial_id = v_id) = 10,
    '3-1: o mesmo arquivo, resumo completo na mesma versão, é reenvio e não toca nas linhas');
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h), teste_ro_cab(v_h, 'resumo/2'));
  perform teste_assert_ro(v_j->>'resumo' = 'em_carga' and (v_j->>'id')::uuid = v_id
    and (select count(*) from arquivo_oficial_registro where arquivo_oficial_id = v_id) = 0
    and (select count(*) from arquivo_oficial_lancamento_mes where arquivo_oficial_id = v_id) = 0
    and (select resumo_versao from arquivo_oficial where id = v_id) = 'resumo/2',
    '3-2: outra versão do resumo RECARREGA: apaga as linhas da carga anterior e reabre em_carga');
  perform fn_resumo_anexar(v_id, v_regs, v_grps);
  v_j := fn_resumo_concluir(v_id);
  perform teste_assert_ro(v_j->>'resumo' = 'completo'
    and (select count(*) from arquivo_oficial_registro where arquivo_oficial_id = v_id) = 10,
    '3-3: a recarga completa de uma vez só (uma parte com tudo) e fecha completo, sem duplicar a anterior');
  -- Carga que ficou pela metade e é reaberta: recomeça do zero.
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h), teste_ro_cab(v_h, 'resumo/3'));
  perform fn_resumo_anexar(v_id, teste_ro_fatia(v_regs, 0, 5), '[]'::jsonb);
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h), teste_ro_cab(v_h, 'resumo/3'));
  perform teste_assert_ro(v_j->>'resumo' = 'em_carga'
    and (select count(*) from arquivo_oficial_registro where arquivo_oficial_id = v_id) = 0,
    '3-4: carga interrompida e reaberta recomeça vazia (a metade antiga não se soma à nova)');

  -- ===== 4. Total declarado MAIOR que o anexado: recusado e linhas apagadas =====
  v_h := 'h-total-maior';
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h), teste_ro_cab(v_h, 'resumo/1', 11, 8));
  v_id := (v_j->>'id')::uuid;
  perform fn_resumo_anexar(v_id, v_regs, v_grps);
  v_j := fn_resumo_concluir(v_id);
  perform teste_assert_ro(v_j->>'resumo' = 'recusado' and v_j->>'motivo' like '%registros gravados 10, declarados 11%',
    '4-1: declarou 11 registros e só 10 chegaram: recusado, e o motivo diz os dois números');
  perform teste_assert_ro((select count(*) from arquivo_oficial_registro where arquivo_oficial_id = v_id) = 0
    and (select count(*) from arquivo_oficial_lancamento_mes where arquivo_oficial_id = v_id) = 0
    and (select resumo_status from arquivo_oficial where id = v_id) = 'recusado'
    and (select status from arquivo_oficial where id = v_id) = 'lido',
    '4-2: o recusado apaga as linhas (nada parcial fica como se fosse o arquivo) e o envelope continua lido');
  v_h := 'h-grupos-maior';
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h), teste_ro_cab(v_h, 'resumo/1', 10, 9));
  perform fn_resumo_anexar((v_j->>'id')::uuid, v_regs, v_grps);
  v_j := fn_resumo_concluir((v_j->>'id')::uuid);
  perform teste_assert_ro(v_j->>'resumo' = 'recusado' and v_j->>'motivo' like '%grupos gravados 8, declarados 9%',
    '4-3: declarou 9 grupos e só 8 chegaram: recusado');
  -- Recusado se reabre: o analista reenvia.
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h), teste_ro_cab(v_h));
  perform teste_assert_ro(v_j->>'resumo' = 'em_carga',
    '4-4: depois de recusado o mesmo arquivo pode ser recarregado');

  -- ===== 5. Registro A MAIS que o por_registro do envelope (um I050 inventado, na linha 25 de 38) =====
  v_h := 'h-registro-a-mais';
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h), teste_ro_cab(v_h, 'resumo/1', 11, 8));
  v_id := (v_j->>'id')::uuid;
  perform fn_resumo_anexar(v_id, v_regs || '[[25,"|I050|01012025|01|A|5|9.9.99|9.9|CONTA INVENTADA|"]]'::jsonb, v_grps);
  v_j := fn_resumo_concluir(v_id);
  perform teste_assert_ro(v_j->>'resumo' = 'recusado' and v_j->>'motivo' like '%I050: resumo 3, envelope 2%',
    '5-1: 3 I050 no resumo e 2 no envelope (a contagem que o 9900 conferiu): recusado, e o motivo diz o tipo');
  perform teste_assert_ro(v_j->>'motivo' not like '%declarados%' and v_j->>'motivo' not like '%partidas%',
    '5-2: era SÓ a contagem por registro que reprovava (o total declarado batia)');

  -- ===== 6. Partidas dos grupos diferentes do I250 (um grupo perdido na soma, totais coerentes) =====
  v_h := 'h-partidas';
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h), teste_ro_cab(v_h, 'resumo/1', 10, 7));
  v_id := (v_j->>'id')::uuid;
  perform fn_resumo_anexar(v_id, v_regs, teste_ro_fatia(v_grps, 0, 7));
  v_j := fn_resumo_concluir(v_id);
  perform teste_assert_ro(v_j->>'resumo' = 'recusado' and v_j->>'motivo' like '%soma de partidas dos grupos 8, I250 do envelope 9%',
    '6-1: grupos somam 8 partidas e o envelope tem 9 I250: recusado, e o motivo diz os dois números');
  perform teste_assert_ro(v_j->>'motivo' not like '%declarados%',
    '6-2: era SÓ a soma das partidas que reprovava (a contagem declarada batia)');

  -- ===== 7. Linha fora do arquivo (linha 99 num arquivo de 38) =====
  v_h := 'h-linha-fora';
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h), teste_ro_cab(v_h));
  v_id := (v_j->>'id')::uuid;
  perform fn_resumo_anexar(v_id, jsonb_set(v_regs, '{9,0}', '99'::jsonb), v_grps);
  v_j := fn_resumo_concluir(v_id);
  perform teste_assert_ro(v_j->>'resumo' = 'recusado' and v_j->>'motivo' like '%fora de 1..38%',
    '7-1: linha 99 num arquivo de 38 linhas: recusado');
  v_h := 'h-grupo-linha-fora';
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h), teste_ro_cab(v_h));
  v_id := (v_j->>'id')::uuid;
  perform fn_resumo_anexar(v_id, v_regs, jsonb_set(v_grps, '{0,primeira_linha}', '0'::jsonb));
  v_j := fn_resumo_concluir(v_id);
  perform teste_assert_ro(v_j->>'resumo' = 'recusado' and v_j->>'motivo' like '%fora de 1..38%',
    '7-2: primeira_linha 0 num grupo: recusado');

  -- ===== 8. AUSENTE (o leitor diz que não há resumo) e arquivo NÃO LIDO =====
  v_h := 'h-ausente';
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h),
    jsonb_build_object('versao', 'resumo/1', 'hash_sha256', v_h, 'ausente', 'família sem resumo definido; só o envelope é registrado'));
  v_id := (v_j->>'id')::uuid;
  perform teste_assert_ro(v_j->>'resumo' = 'ausente' and v_j->>'motivo' like 'família sem resumo%'
    and (select resumo_status from arquivo_oficial where id = v_id) = 'ausente'
    and (select resumo_motivo from arquivo_oficial where id = v_id) like 'família sem resumo%',
    '8-1: cabeçalho ausente grava resumo_status ausente COM o motivo, e devolve resumo ausente');
  v_msg := teste_erro_ro(format('select fn_resumo_anexar(%L, ''[]''::jsonb, ''[]''::jsonb)', v_id));
  perform teste_assert_ro(v_msg like 'P0001%ausente%', '8-2: não se anexa a resumo ausente (' || left(v_msg, 50) || ')');
  v_h := 'h-nao-lido';
  v_env := jsonb_set(jsonb_set(teste_ro_env_h(v_h), '{status}', '"controle_divergente"'), '{controle_lido}', '37');
  v_j := fn_resumo_iniciar(v_caso, null, v_env, teste_ro_cab(v_h));
  v_id := (v_j->>'id')::uuid;
  perform teste_assert_ro(v_j->>'resumo' = 'ausente' and v_j->>'status' = 'controle_divergente'
    and v_j->>'motivo' like '%controle_divergente%',
    '8-3: arquivo que não ficou lido vira resumo ausente, e o motivo diz que o arquivo não foi lido');
  perform teste_assert_ro((select count(*) from arquivo_oficial_registro where arquivo_oficial_id = v_id) = 0,
    '8-4: e nenhuma linha é gravada para arquivo não lido');
  -- Ausente derruba linhas de uma carga anterior que ficou para trás (versão nova sem resumo).
  v_h := 'h-vira-ausente';
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h), teste_ro_cab(v_h));
  v_id := (v_j->>'id')::uuid;
  perform fn_resumo_anexar(v_id, v_regs, v_grps);
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h),
    jsonb_build_object('versao', 'resumo/2', 'hash_sha256', v_h, 'ausente', 'leitor novo recusou o resumo'));
  perform teste_assert_ro(v_j->>'resumo' = 'ausente'
    and (select count(*) from arquivo_oficial_registro where arquivo_oficial_id = v_id) = 0
    and (select count(*) from arquivo_oficial_lancamento_mes where arquivo_oficial_id = v_id) = 0,
    '8-5: carga pela metade e depois ausente: as linhas da carga anterior somem');
  -- Um resumo completo NÃO é derrubado por um cabeçalho ausente da mesma versão.
  v_h := 'h-completo-nao-cai';
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h), teste_ro_cab(v_h));
  v_id := (v_j->>'id')::uuid;
  perform fn_resumo_anexar(v_id, v_regs, v_grps); perform fn_resumo_concluir(v_id);
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h),
    jsonb_build_object('versao', 'resumo/1', 'hash_sha256', v_h, 'ausente', 'qualquer'));
  perform teste_assert_ro(v_j->>'resumo' = 'reenvio'
    and (select resumo_status from arquivo_oficial where id = v_id) = 'completo',
    '8-6: resumo completo na mesma versão não é derrubado por um cabeçalho ausente');

  -- ===== 9. O I155 que NÃO FECHA é contado e NÃO recusa =====
  -- Variante da fixture: o saldo final da linha 7 sai 1.600,00 em vez de 1.500,00 (0 + 1.500 - 0 ≠ 1.600).
  v_h := 'h-i155';
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h), teste_ro_cab(v_h));
  v_id := (v_j->>'id')::uuid;
  perform fn_resumo_anexar(v_id,
    jsonb_set(v_regs, '{5,1}', '"|I155|1.1.01||0,00|D|1.500,00|0,00|1.600,00|D|"'), v_grps);
  v_j := fn_resumo_concluir(v_id);
  perform teste_assert_ro(v_j->>'resumo' = 'completo' and (v_j->>'i155_nao_fecham')::int = 1,
    '9-1: um I155 de dois não fecha: o resumo continua completo e o servidor conta 1');
  perform teste_assert_ro((select resumo_conferencia->'i155'->'amostra'->0->>'linha' from arquivo_oficial where id = v_id) = '7'
    and (select (resumo_conferencia->'i155'->'amostra'->0->>'esperado')::numeric from arquivo_oficial where id = v_id) = 1500
    and (select (resumo_conferencia->'i155'->'amostra'->0->>'declarado')::numeric from arquivo_oficial where id = v_id) = 1600
    and (select resumo_conferencia->'i155'->>'total' from arquivo_oficial where id = v_id) = '2',
    '9-2: a amostra aponta a linha 7, o saldo esperado (1500) e o declarado (1600)');
  perform teste_assert_ro((select count(*) from arquivo_oficial_registro where arquivo_oficial_id = v_id) = 10,
    '9-3: o achado não apaga nada (balancete que não fecha é informação sobre o cliente, não defeito de carga)');
  -- I155 de crédito (C negativo) fecha: a fixture inteira tem 0 fora (já afirmado em 1-5).
  -- I155 ilegível não é "fecha" nem "não fecha": é contado à parte.
  v_h := 'h-i155-ilegivel';
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h), teste_ro_cab(v_h));
  v_id := (v_j->>'id')::uuid;
  perform fn_resumo_anexar(v_id,
    jsonb_set(v_regs, '{6,1}', '"|I155|3.1.01||0,00|C|0,00|abc|1.500,00|C|"'), v_grps);
  v_j := fn_resumo_concluir(v_id);
  perform teste_assert_ro(v_j->>'resumo' = 'completo' and (v_j->>'i155_nao_fecham')::int = 0
    and (select resumo_conferencia->'i155'->>'ilegiveis' from arquivo_oficial where id = v_id) = '1',
    '9-4: valor ilegível no I155 não vira "fecha" nem "não fecha": vai para ilegiveis (1)');

  -- ===== 10. Linha repetida no mesmo arquivo é ERRO; grupo repetido também (mês null incluído) =====
  v_h := 'h-repetida';
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h), teste_ro_cab(v_h));
  v_id := (v_j->>'id')::uuid;
  perform fn_resumo_anexar(v_id, teste_ro_fatia(v_regs, 0, 5), '[]'::jsonb);
  v_msg := teste_erro_ro(format('select fn_resumo_anexar(%L, %L::jsonb, ''[]''::jsonb)', v_id, teste_ro_fatia(v_regs, 4, 6)::text));
  perform teste_assert_ro(v_msg like '23505%', '10-1: a linha 7 anexada duas vezes é erro de pk (' || left(v_msg, 30) || ')');
  perform fn_resumo_anexar(v_id, '[]'::jsonb,
    '[{"conta":"9.9","mes":null,"ind_lcto":null,"debito":1,"credito":0,"partidas":1,"partidas_sem_valor":0,"primeira_linha":12}]'::jsonb);
  v_msg := teste_erro_ro(format('select fn_resumo_anexar(%L, ''[]''::jsonb, %L::jsonb)', v_id,
    '[{"conta":"9.9","mes":null,"ind_lcto":null,"debito":2,"credito":0,"partidas":1,"partidas_sem_valor":0,"primeira_linha":13}]'));
  perform teste_assert_ro(v_msg like '23505%', '10-2: dois grupos de mês NULL na mesma conta e indicador colidem (nulls not distinct)');
  perform teste_assert_ro((select count(*) from arquivo_oficial_lancamento_mes where arquivo_oficial_id = v_id and mes is null) = 1,
    '10-3: o grupo de mês null (partida sem I200) é GRAVADO: é dado, não erro');
  v_msg := teste_erro_ro(format('select fn_resumo_anexar(%L, ''[[3,"|I010|G|9.00|"],[4]]''::jsonb, ''[]''::jsonb)', v_id));
  perform teste_assert_ro(v_msg like 'P0001%[linha, texto]%', '10-4: registro mal formado é recusado com mensagem clara');
  v_msg := teste_erro_ro(format('select fn_resumo_anexar(%L, ''[]''::jsonb, ''[]''::jsonb)', gen_random_uuid()));
  perform teste_assert_ro(v_msg like 'P0001%não existe%', '10-5: anexar a arquivo inexistente é erro');
  v_msg := teste_erro_ro(format('select fn_resumo_anexar(%L, (select jsonb_agg(jsonb_build_array(g, ''|X|'')) from generate_series(1,10001) g), ''[]''::jsonb)', v_id));
  perform teste_assert_ro(v_msg like 'P0001%teto 10000%', '10-6: parte de 10.001 itens é recusada (o teto protege os 8 s do authenticated)');

  -- ===== 11. Hash do cabeçalho diferente do envelope: resumo de OUTRO arquivo =====
  v_msg := teste_erro_ro(format('select fn_resumo_iniciar(%L, null, %L::jsonb, %L::jsonb)', v_caso,
    teste_ro_env_h('h-A')::text, teste_ro_cab('h-B')::text));
  perform teste_assert_ro(v_msg like 'P0001%não é o do envelope%', '11-1: hash do resumo ≠ hash do envelope é recusado');
  perform teste_assert_ro((select count(*) from arquivo_oficial where hash_sha256 in ('h-A', 'h-B')) = 0,
    '11-2: e nada foi registrado, nem o envelope');
  v_msg := teste_erro_ro(format('select fn_resumo_iniciar(%L, null, %L::jsonb, %L::jsonb)', v_caso,
    teste_ro_env_h('h-sem-total')::text, (teste_ro_cab('h-sem-total') - 'total_grupos')::text));
  perform teste_assert_ro(v_msg like 'P0001%total_registros e total_grupos%', '11-3: cabeçalho sem os totais é recusado: não há contra o que conferir');

  -- ===== 12. Trilha DESLIGADA: exceção, nada gravado =====
  insert into caso (nome) values ('teste resumo — trilha desligada') returning id into v_off;
  v_msg := teste_erro_ro(format('select fn_resumo_iniciar(%L, null, %L::jsonb, %L::jsonb)', v_off,
    teste_ro_env_h('h-off')::text, teste_ro_cab('h-off')::text));
  perform teste_assert_ro(v_msg like 'P0001%DESLIGADA%', '12-1: trilha desligada: iniciar RECUSA com exceção (' || left(v_msg, 40) || ')');
  perform teste_assert_ro((select count(*) from arquivo_oficial where caso_id = v_off) = 0,
    '12-2: e nada foi gravado no caso desligado');

  -- ===== 13. ECF: só registros; grupo de lançamento em arquivo que não é ECD é recusado =====
  v_h := 'h-ecf';
  v_env := jsonb_build_object('familia', 'sped', 'subtipo', 'ECF', 'versao_leiaute', '9', 'hash_sha256', v_h,
    'cnpj', '11222333000181', 'chave_natural', '11222333000181|ECF|2025-01-01|2025-12-31',
    'controle_tipo', 'contagem_declarada', 'controle_declarado', 4, 'controle_lido', 4, 'status', 'lido',
    'detalhe', '{"por_registro":{"0000":1,"0010":1,"9900":1,"9999":1}}'::jsonb, 'leitor_versao', 'teste');
  v_j := fn_resumo_iniciar(v_caso, null, v_env, jsonb_build_object('versao', 'resumo/1', 'hash_sha256', v_h,
    'total_registros', 2, 'total_grupos', 0));
  v_id := (v_j->>'id')::uuid;
  perform fn_resumo_anexar(v_id, '[[1,"|0000|LECF|"],[2,"|0010|1|"]]'::jsonb, '[]'::jsonb);
  v_j := fn_resumo_concluir(v_id);
  perform teste_assert_ro(v_j->>'resumo' = 'completo' and (v_j->>'i155_nao_fecham')::int = 0,
    '13-1: a ECF (só registros, sem grupos) fecha completo; a soma de partidas só vale para a ECD');
  v_h := 'h-ecf-grupos';
  v_j := fn_resumo_iniciar(v_caso, null, jsonb_set(v_env, '{hash_sha256}', to_jsonb(v_h)),
    jsonb_build_object('versao', 'resumo/1', 'hash_sha256', v_h, 'total_registros', 2, 'total_grupos', 1));
  v_id := (v_j->>'id')::uuid;
  perform fn_resumo_anexar(v_id, '[[1,"|0000|LECF|"],[2,"|0010|1|"]]'::jsonb,
    '[{"conta":"1","mes":"2025-01","ind_lcto":"N","debito":1,"credito":0,"partidas":1,"partidas_sem_valor":0,"primeira_linha":3}]'::jsonb);
  v_j := fn_resumo_concluir(v_id);
  perform teste_assert_ro(v_j->>'resumo' = 'recusado' and v_j->>'motivo' like '%não os tem%',
    '13-2: grupo de lançamento num arquivo ECF é recusado');
end $$;

-- ===== 14. Como AUTHENTICATED (o papel que o navegador usa): a carga, a recusa que APAGA e a recarga =====
-- As funções são invoker: se faltasse o DELETE nas tabelas filhas, a recusa e a recarga morreriam aqui, e
-- como superusuário nunca se saberia.
insert into caso (id, nome, trilha_transacional) values ('77777777-7777-7777-7777-777777777777', 'teste resumo authenticated', true);
set role authenticated;
do $$
declare
  v_caso uuid := '77777777-7777-7777-7777-777777777777'; v_id uuid; v_j jsonb; v_h text;
  v_regs jsonb := teste_ro_registros(); v_grps jsonb := teste_ro_grupos(); v_msg text;
begin
  v_h := 'h-auth-ok';
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h), teste_ro_cab(v_h));
  v_id := (v_j->>'id')::uuid;
  perform fn_resumo_anexar(v_id, v_regs, v_grps);
  v_j := fn_resumo_concluir(v_id);
  perform teste_assert_ro(v_j->>'resumo' = 'completo', '14-1: como authenticated a carga completa');
  v_j := fn_resumo_iniciar(v_caso, null, teste_ro_env_h(v_h), teste_ro_cab(v_h, 'resumo/2'));
  perform teste_assert_ro(v_j->>'resumo' = 'em_carga'
    and (select count(*) from arquivo_oficial_registro where arquivo_oficial_id = v_id) = 0,
    '14-2: como authenticated a recarga APAGA as linhas anteriores');
  perform fn_resumo_anexar(v_id, v_regs, v_grps);
  v_j := jsonb_set(teste_ro_cab(v_h, 'resumo/2'), '{total_registros}', '99');   -- só para o assert abaixo ler o erro
  update arquivo_oficial set resumo_total_registros = 99 where id = v_id;
  v_j := fn_resumo_concluir(v_id);
  perform teste_assert_ro(v_j->>'resumo' = 'recusado'
    and (select count(*) from arquivo_oficial_registro where arquivo_oficial_id = v_id) = 0,
    '14-3: como authenticated a recusa APAGA as linhas');
  v_msg := teste_erro_ro(format('delete from arquivo_oficial where id = %L', v_id));
  perform teste_assert_ro(v_msg like '42501%', '14-4: o envelope continua sem DELETE para authenticated (evidência, 0206)');
end $$;
reset role;

-- 15. fn_upsert_caso PELO NAVEGADOR: a tela de arquivos oficiais obtém o caso_id do mandato pela MESMA
-- função do n8n (antes ela repetia a regra em TypeScript), e a trilha diz quem criou.
set role authenticated;
do $$
declare v_a uuid; v_b uuid;
begin
  v_a := fn_upsert_caso('0207 — mandato criado pela tela', 'portal:navegador');
  v_b := fn_upsert_caso('0207 — mandato criado pela tela', 'portal:navegador');
  perform teste_assert_ro(v_a is not null and v_a = v_b, '15-1: como authenticated, o mesmo nome devolve o MESMO caso (não duplica)');
  perform teste_assert_ro(teste_erro_ro($q$select fn_upsert_caso('0207 — ator inventado', 'qualquer:um')$q$) like 'P0001%',
    '15-2: ator fora da lista é recusado (é rótulo da trilha, não texto livre do navegador)');
end $$;
reset role;
do $$
declare v uuid;
begin
  perform teste_assert_ro((select string_agg(e.ator, ',') from evento_auditoria e join caso c on e.entidade_ref = 'caso:'||c.id
                            where c.nome = '0207 — mandato criado pela tela' and e.acao = 'caso_criado') = 'portal:navegador',
    '15-3: o caso criado pela tela tem UM evento caso_criado, com ator portal:navegador');
  v := fn_upsert_caso('0207 — mandato criado pelo n8n');
  perform teste_assert_ro((select e.ator from evento_auditoria e where e.entidade_ref = 'caso:'||v and e.acao = 'caso_criado') = 'sistema:n8n',
    '15-4: a chamada de UM argumento (o nó Upsert Caso do n8n) continua gravando sistema:n8n');
  perform teste_assert_ro(not exists (select 1 from caso where nome = '0207 — ator inventado'),
    '15-5: o ator recusado não deixou caso criado');
end $$;

do $$ begin raise notice 'TODOS OS TESTES DA 0207 PASSARAM'; end $$;
