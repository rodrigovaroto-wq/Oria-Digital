-- Testes do banco de perguntas ao cliente (Supabase/migrations/0120).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- As propriedades travadas:
--
--   #1  balanço sem caixa: A3 é sugerida (gatilho exigencia_ausente), A1/A2
--       NÃO (satisfeitas), e as quatro 'sempre' aparecem — caso com conteúdo;
--   #2  marcador {data_base}/{ano} preenchido com a referência do período, e
--       nenhum marcador sobra sem resolver nas perguntas seedadas do cenário;
--   #3  {saldo_mutuos}: sem linha de mútuo → "(não localizado)"; com linhas na
--       MESMA escala → a soma com a unidade; escalas MISTAS → aviso, nunca uma
--       soma cega;
--   #4  espécie linha_presente (nenhuma seedada — é o upgrade do dono):
--       testada com pergunta temporária ancorada em BALANCO:ativo_total —
--       dispara quando a linha existe, cala quando não. (Era MUTUOS:saldo_de_mutuo
--       até a 0187, que desativou essa exigência: exigência inativa não é
--       avaliada, então não serve mais de âncora. O {saldo_mutuos} do #3 continua
--       lendo o léxico dela — é a mudança (e) da 0187.);
--   #5  marcador DESCONHECIDO fica VISÍVEL no texto renderizado;
--   #6  ação humana: enviada sem texto é RECUSADA (jsonb, não exceção);
--       enviada com texto grava, audita, e a sugestão passa a ja_enviada=true
--       SEM sumir da lista; código inexistente é recusado;
--   #7  sugerir é SÓ LEITURA: nada muda em campo_extraido nem em pendencia;
--   #8  append-only é REGRA do banco: caso_pergunta sem política de UPDATE/DELETE;
--   #9  o período do marcador é o mais recente por ANO, não por texto;
--   #10 a pergunta NOMEIA a empresa (e a contextual, de propósito, não);
--   #11 o par (código, empresa) é ÚNICO na saída — é ele que torna TOTAL a ordem
--       (prioridade, codigo, entidade_id) com que a aba do portal pagina a
--       função, e sem ordem total duas páginas repetem e omitem a mesma linha;
--   #12 (0122) O TEXTO QUE VAI AO CLIENTE está em português: período por
--       extenso ("2023 a 2025", nunca "23,24,25"), valor em reais
--       ("R$ 16.060 mil", nunca "16060 milhar"), janela móvel que não vira ano
--       (L36M não é 2036) e período POR EMPRESA — a pergunta sobre a Beta não
--       cita o exercício que só a Alfa tem.
--   #13 (0187, revisão) O SALDO DE MÚTUOS SEM LÉXICO: o documento MUTUOS é o
--       conceito. O arranjo REAL (fixture canastra, chave = par de empresas +
--       "TOTAL") sai "R$ 16.060 mil", não "(não localizado)"; item + total
--       geral sai o total (150), não a soma dos dois (300); o documento
--       matricial (Saldo 2024 / Juros / Saldo 2025) sai só a coluna do
--       exercício mais recente (11.079), não 20.158; duas colunas sem
--       exercício saem "não foi possível apurar" COM o motivo, e sem número.
--       Os arranjos 2-4 são montados aqui (regra 4): os rótulos do matricial
--       são os que a revisão mediu; o que se afirma é só a regra de soma. Este
--       bloco NÃO para no primeiro erro — conta, para a medição da regra 2.

\set ON_ERROR_STOP on

create or replace function teste_assert_pg(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

do $$
declare
  v_ent uuid;
  v_caso uuid;
  v_caso2 uuid;
  v_r jsonb;
  v_ver uuid;
  v_n int;
  v_n_campos int;
  v_n_pend int;
  v_txt text;
begin
  raise notice '--- 1. balanço sem caixa: A3 dispara, A1/A2 não, e as quatro sempre aparecem ---';
  v_caso := (fn_upsert_caso('Caso perguntas — balanço sem caixa'))::uuid;
  v_r := fn_registrar_documento(
    v_caso, 'Quero Perguntas Ltda', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-pg.pdf', 'BP Perguntas.pdf', true, 'HASH-PG-1', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "900", "confianca": "0.9"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "900", "confianca": "0.9"},
    {"chave": "Estoques",                                 "valor_num": "900", "confianca": "0.9"}
  ]'::jsonb, 'N0');

  select count(*) into v_n from fn_sugerir_perguntas(v_caso);
  perform teste_assert_pg(v_n = 5,
    'cinco sugestões: A3 + as quatro sempre (5.1, 5.3, 6.3, 7.1)', 'achou ' || v_n);

  select count(*) into v_n from fn_sugerir_perguntas(v_caso) s
    where s.codigo = 'A3' and s.gatilho = 'exigencia_ausente:BALANCO:caixa_e_equivalentes';
  perform teste_assert_pg(v_n = 1, 'A3 sugerida, com o gatilho declarado', 'achou ' || v_n);

  select count(*) into v_n from fn_sugerir_perguntas(v_caso) s where s.codigo in ('A1', 'A2');
  perform teste_assert_pg(v_n = 0,
    'A1 e A2 NÃO sugeridas — Ativo Total e Passivo+PL estão no documento', 'sugeriu ' || v_n);

  select count(*) into v_n from fn_sugerir_perguntas(v_caso) s
    where s.codigo in ('A4', 'A5', 'A6', 'A7');
  perform teste_assert_pg(v_n = 0,
    'perguntas de FLUXO/DRE/MAPA não disparam sem documento do tipo (cadê-o-documento é item_faltante)',
    'sugeriu ' || v_n);

  raise notice '--- 2. marcadores de período preenchidos ---';
  select s.pergunta into v_txt from fn_sugerir_perguntas(v_caso) s where s.codigo = 'A3';
  perform teste_assert_pg(v_txt like '%2025%' and v_txt not like '%{data_base}%',
    'A3 sai com {data_base} → 2025', left(v_txt, 100));

  raise notice '--- 3. {saldo_mutuos}: não localizado → soma → escalas mistas ---';
  select s.pergunta into v_txt from fn_sugerir_perguntas(v_caso) s where s.codigo = '5.1';
  perform teste_assert_pg(v_txt like '%(não localizado)%',
    'sem linha de mútuo, o marcador declara (não localizado) — nunca em branco', left(v_txt, 120));

  v_r := fn_registrar_documento(
    v_caso, 'Quero Perguntas Ltda', 'anual', '2025', 'MUTUOS', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/mut-pg.pdf', 'Mutuos Perguntas.pdf', true, 'HASH-PG-2', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Mútuo a receber - Beta", "valor_num": "100", "unidade": "milhar", "confianca": "0.9"},
    {"chave": "Mútuo a pagar - Gama",   "valor_num": "50",  "unidade": "milhar", "confianca": "0.9"}
  ]'::jsonb, 'N0');

  select s.pergunta into v_txt from fn_sugerir_perguntas(v_caso) s where s.codigo = '5.1';
  -- 0122: era "150 milhar" — a soma com o nome INTERNO da escala. O texto vai ao
  -- cliente, então sai em reais, com a escala em palavra.
  perform teste_assert_pg(v_txt like '%R$ 150 mil%',
    'duas linhas na MESMA escala: soma em reais (R$ 150 mil)', left(v_txt, 140));

  v_r := fn_registrar_documento(
    v_caso, 'Quero Perguntas Ltda', 'anual', '2025', 'MUTUOS', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/mut-pg2.pdf', 'Mutuos Perguntas 2.pdf', true, 'HASH-PG-3', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Mútuo com Delta", "valor_num": "5", "unidade": "unidade", "confianca": "0.9"}
  ]'::jsonb, 'N0');

  select s.pergunta into v_txt from fn_sugerir_perguntas(v_caso) s where s.codigo = '5.1';
  perform teste_assert_pg(v_txt like '%escalas mistas%',
    'escalas mistas NÃO são somadas às cegas — o marcador avisa', left(v_txt, 140));

  raise notice '--- 4. espécie linha_presente (pergunta temporária — o upgrade do dono) ---';
  insert into pergunta_catalogo
    (codigo, titulo, prioridade, gatilho_especie, gatilho_tipo_taxonomia, gatilho_conceito,
     pergunta, motivo, risco, impacto, gatilho_descricao, fonte)
  values
    ('TESTE_LP', 'teste linha_presente', 4, 'linha_presente', 'BALANCO', 'ativo_total',
     'teste: ha ativo total e mutuos de {saldo_mutuos}.', 'teste', 'teste', 'teste', 'teste', 'teste');

  select count(*) into v_n from fn_sugerir_perguntas(v_caso) s where s.codigo = 'TESTE_LP';
  perform teste_assert_pg(v_n = 1,
    'linha_presente dispara no caso que TEM a linha (ativo total no balanço)', 'achou ' || v_n);

  v_caso2 := (fn_upsert_caso('Caso perguntas — balanço sem ativo total'))::uuid;
  v_r := fn_registrar_documento(
    v_caso2, 'Outro Grupo Ltda', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-pg3.pdf', 'BP Outro.pdf', true, 'HASH-PG-4', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Fornecedores", "valor_num": "70", "confianca": "0.9"}
  ]'::jsonb, 'N0');

  select count(*) into v_n from fn_sugerir_perguntas(v_caso2) s where s.codigo = 'TESTE_LP';
  perform teste_assert_pg(v_n = 0,
    'linha_presente CALA no caso cujo BALANCO não tem a linha', 'sugeriu ' || v_n);

  raise notice '--- 5. marcador desconhecido fica visível ---';
  insert into pergunta_catalogo
    (codigo, titulo, prioridade, gatilho_especie, gatilho_tipo_taxonomia, gatilho_conceito,
     pergunta, motivo, risco, impacto, gatilho_descricao, fonte)
  values
    ('TESTE_MARC', 'teste marcador', 4, 'sempre', null, null,
     'teste com {marcador_que_nao_existe} no meio.', 'teste', 'teste', 'teste', 'teste', 'teste');
  select s.pergunta into v_txt from fn_sugerir_perguntas(v_caso) s where s.codigo = 'TESTE_MARC';
  perform teste_assert_pg(v_txt like '%{marcador_que_nao_existe}%',
    'marcador desconhecido permanece VISÍVEL — nunca vira espaço em branco', left(v_txt, 100));

  delete from pergunta_catalogo where codigo in ('TESTE_LP', 'TESTE_MARC');

  raise notice '--- 6. ação humana: recusas em jsonb, envio congelado, ja_enviada informa ---';
  v_r := fn_registrar_pergunta_acao(v_caso, 'A3', 'enviada', null, 'teste@oria');
  perform teste_assert_pg(coalesce((v_r->>'recusado')::boolean, false),
    'enviar SEM o texto é recusado — a trilha precisa dizer O QUE se perguntou', v_r::text);

  v_r := fn_registrar_pergunta_acao(v_caso, 'ZZ_NAO_EXISTE', 'enviada', 'x', 'teste@oria');
  perform teste_assert_pg(coalesce((v_r->>'recusado')::boolean, false),
    'pergunta fora do catálogo é recusada', v_r::text);

  -- A ENTIDADE VOLTA JUNTO NA AÇÃO. Desde que a sugestão é por entidade (0119
  -- no main), registrar o envio sem dizer de qual empresa deixaria a pergunta
  -- da OUTRA empresa marcada como enviada — ou nenhuma delas. `entidade_id` sai
  -- na sugestão exatamente para ser devolvido aqui.
  select s.pergunta, s.entidade_id into v_txt, v_ent
    from fn_sugerir_perguntas(v_caso) s where s.codigo = 'A3';
  v_r := fn_registrar_pergunta_acao(v_caso, 'A3', 'enviada', v_txt, 'teste@oria', v_ent);
  perform teste_assert_pg((v_r->>'caso_pergunta_id') is not null,
    'enviar com o texto renderizado grava', v_r::text);
  select count(*) into v_n from caso_pergunta
    where caso_id = v_caso and pergunta_codigo = 'A3' and acao = 'enviada'
      and texto_enviado like '%2025%';
  perform teste_assert_pg(v_n = 1, 'o texto enviado fica CONGELADO na linha (com o período resolvido)', 'achou ' || v_n);
  select count(*) into v_n from evento_auditoria
    where acao = 'pergunta_enviada' and entidade_ref = 'caso:' || v_caso;
  perform teste_assert_pg(v_n = 1, 'o envio vai para evento_auditoria', 'achou ' || v_n);

  select count(*) into v_n from fn_sugerir_perguntas(v_caso) s
    where s.codigo = 'A3' and s.ja_enviada;
  perform teste_assert_pg(v_n = 1,
    'a sugestão vira ja_enviada=true e CONTINUA listada — informa, não filtra', 'achou ' || v_n);

  v_r := fn_registrar_pergunta_acao(v_caso, '7.1', 'descartada', null, 'teste@oria');
  perform teste_assert_pg((v_r->>'caso_pergunta_id') is not null,
    'descartar não exige texto', v_r::text);

  raise notice '--- 7. sugerir é só leitura ---';
  select count(*) into v_n_campos from campo_extraido;
  select count(*) into v_n_pend from pendencia;
  perform (select count(*) from fn_sugerir_perguntas(v_caso));
  select count(*) - v_n_campos into v_n from campo_extraido;
  perform teste_assert_pg(v_n = 0, 'campo_extraido intacto', 'delta ' || v_n);
  select count(*) - v_n_pend into v_n from pendencia;
  perform teste_assert_pg(v_n = 0, 'pendencia intacta — sugerir não abre nem resolve nada', 'delta ' || v_n);

  -- ---------------------------------------------------------------------------
  -- 8. AS CORREÇÕES DA INCORPORAÇÃO (o conteúdo é do PR #138, revisado)
  -- ---------------------------------------------------------------------------
  raise notice '--- 8. append-only é REGRA DO BANCO, não adjetivo do comentário ---';
  -- O QUE ACONTECIA: a tabela declarava "append-only por desenho" e publicava
  -- `for all to authenticated` — o que deixa qualquer usuário autenticado dar
  -- UPDATE e DELETE. Medido antes do conserto: `set role authenticated; delete
  -- from caso_pergunta` apagou a linha. O texto do que foi perguntado a um
  -- cliente é fato histórico; tabela que promete guardá-lo e aceita `delete`
  -- promete o que não cumpre. O par certo já existia ao lado, no
  -- `evento_auditoria` (0003): INSERT e SELECT, e nada mais — sem política para
  -- um comando, o RLS nega aquele comando.
  -- 0213: a ÚNICA exceção é repontar entidade_id numa fusão de entidades (a ação já tomada acompanha a
  -- sobrevivente). O invariante continua o mesmo, agora dito em COMPORTAMENTO: nenhuma política de DELETE ou
  -- de ALL, a única de UPDATE é a restrita ao mesmo caso, e o authenticated só tem privilégio de UPDATE na
  -- coluna entidade_id (texto, ação e autor não se reescrevem) e nenhum de DELETE.
  select count(*) into v_n from pg_policies
   where tablename = 'caso_pergunta' and cmd in ('ALL', 'DELETE');
  perform teste_assert_pg(v_n = 0,
    'caso_pergunta não tem política de DELETE nem de ALL — o histórico não se apaga',
    'achou ' || v_n || ' política(s) permissiva(s)');
  select count(*) into v_n from pg_policies
   where tablename = 'caso_pergunta' and cmd = 'UPDATE' and policyname <> 'caso_pergunta_reapontar';
  perform teste_assert_pg(v_n = 0 and not has_column_privilege('authenticated', 'caso_pergunta', 'texto_enviado', 'UPDATE')
      and not has_column_privilege('authenticated', 'caso_pergunta', 'acao', 'UPDATE')
      and not has_column_privilege('authenticated', 'caso_pergunta', 'autor', 'UPDATE')
      and has_column_privilege('authenticated', 'caso_pergunta', 'entidade_id', 'UPDATE')
      and not has_table_privilege('authenticated', 'caso_pergunta', 'DELETE'),
    '…e o authenticated só reescreve entidade_id (a fusão): nem texto, nem ação, nem autor, nem delete',
    'achou ' || v_n || ' política(s) de UPDATE além da restrita');
  select count(*) into v_n from pg_policies
   where tablename = 'caso_pergunta' and cmd in ('SELECT', 'INSERT');
  perform teste_assert_pg(v_n = 2,
    '…e tem as duas que faltavam: ler e inserir', 'achou ' || v_n);

  raise notice '--- 9. o período do marcador é o MAIS RECENTE por ANO, não por texto ---';
  -- O QUE ACONTECIA: o período saía de `max(referencia)`, máximo de TEXTO sobre
  -- rótulos que não são comparáveis como texto. Num caso com "2025" e "L24M", o
  -- `max` devolve L24M — rótulo de janela móvel, não data de balanço, e nem o
  -- mais recente. E este é o texto que vai para o CLIENTE:
  --   "No balanço de L24M não localizamos uma linha de Ativo Total."
  perform fn_registrar_documento(
    v_caso, 'Quero Perguntas Ltda', 'multi', 'L24M', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-l24m.pdf', 'BP L24M.pdf', true, 'HASH-PG-L24M', 'ok');
  select s.pergunta into v_txt from fn_sugerir_perguntas(v_caso) s where s.codigo = 'A3' limit 1;
  perform teste_assert_pg(v_txt like '%2025%' and v_txt not like '%L24M%',
    'com 2025 e L24M no mesmo caso, a pergunta diz 2025 — o exercício, não a janela móvel',
    left(v_txt, 140));

  raise notice '--- 10. a pergunta NOMEIA a empresa (o reemit que a 0119 tornou devido) ---';
  -- A pendência `linha_exigida_ausente` nomeia a entidade desde a 0119. A
  -- pergunta é o lado externo da MESMA avaliação — e é ENVIADA ao cliente. Num
  -- grupo de oito balanços, "no balanço de 2025 não localizamos Ativo Total"
  -- não diz de qual empresa se fala: quem recebe não tem como responder.
  select count(*) into v_n from fn_sugerir_perguntas(v_caso) s
   where s.codigo = 'A3' and s.entidade is not null and s.pergunta like 'Sobre a %';
  perform teste_assert_pg(v_n >= 1,
    'a sugestão de exigência ausente nomeia a entidade no texto', 'achou ' || v_n);
  select count(*) into v_n from fn_sugerir_perguntas(v_caso) s
   where s.codigo = '7.1' and (s.entidade is not null or s.pergunta like 'Sobre a %');
  perform teste_assert_pg(v_n = 0,
    'pergunta contextual (sempre) NÃO ganha prefixo de empresa — não é de ninguém em particular',
    'achou ' || v_n);

  raise notice '--- 11. (código, empresa) é ÚNICO na saída — o que a aba do portal pagina ---';
  -- POR QUE ISTO É TESTE DE BANCO, e não detalhe de tela. A aba "Perguntas ao
  -- cliente" lê esta função PAGINADA (o PostgREST corta em 1000 linhas em
  -- silêncio, e a sugestão é uma por pergunta × empresa desde a 0119), e pagina
  -- ordenando por (prioridade, codigo, entidade_id). Ordem de página só é
  -- confiável se for TOTAL: se duas linhas empatarem nas três colunas, o
  -- Postgres pode devolvê-las em ordens diferentes em duas requisições, e aí
  -- uma linha aparece nas duas páginas enquanto outra não aparece em nenhuma —
  -- pior que truncar, porque o total continua plausível.
  --
  -- O empate só não acontece porque o par (código, empresa) é único aqui. Isso
  -- é propriedade da função, não da tela: uma espécie de gatilho nova que
  -- devolvesse a mesma pergunta duas vezes para a mesma empresa quebraria a
  -- paginação sem quebrar teste nenhum — a menos deste.
  select count(*) into v_n from (
    select s.codigo, s.entidade_id from fn_sugerir_perguntas(v_caso) s
     group by s.codigo, s.entidade_id having count(*) > 1) d;
  perform teste_assert_pg(v_n = 0,
    'nenhum par (código, empresa) repetido — a ordem (prioridade, codigo, entidade_id) é total',
    'achou ' || v_n || ' par(es) repetido(s)');

  -- E O NOME E O ID DA EMPRESA ANDAM JUNTOS. A tela mostra `entidade` e casa a
  -- ação humana por `entidade_id`; se um viesse sem o outro, duas empresas
  -- diferentes cairiam na mesma chave (ou uma sugestão nomeada viraria
  -- irregistrável), e "já enviada" passaria a mentir sobre qual empresa.
  select count(*) into v_n from fn_sugerir_perguntas(v_caso) s
   where (s.entidade is null) <> (s.entidade_id is null);
  perform teste_assert_pg(v_n = 0,
    'entidade e entidade_id são nulos juntos ou preenchidos juntos', 'achou ' || v_n);

  -- ---------------------------------------------------------------------------
  -- 12. O TEXTO QUE SAI DA CASA (0122)
  -- ---------------------------------------------------------------------------
  raise notice '--- 12. o texto vai ao CLIENTE: período por extenso e valor em reais ---';
  -- MEDIDO NO BOOK DA CANASTRA, antes da 0122, e é daí que esta seção nasceu:
  --   "Na DRE de 24,25 não localizamos a linha de despesas financeiras."
  --   "no faturamento de L36M?"      (L36M vencia 2025: fn_anos_texto lia 2036)
  --   "A relação de mútuos informa 16060 milhar…"
  -- Nenhuma errada no dado; as três erradas no LEITOR, que aqui é o cliente.

  perform teste_assert_pg(fn_anos_texto('L36M') = '{}'::int[],
    'L36M não é ano nenhum — é o tamanho da janela', fn_anos_texto('L36M')::text);
  perform teste_assert_pg(fn_anos_texto('12M25') = '{2025}'::int[],
    '…e 12M25 continua sendo 2025 (ali o final É o ano)', fn_anos_texto('12M25')::text);

  perform teste_assert_pg(fn_periodo_por_extenso('multi', '23,24,25') = '2023 a 2025',
    'três exercícios seguidos viram intervalo', fn_periodo_por_extenso('multi', '23,24,25'));
  perform teste_assert_pg(fn_periodo_por_extenso('multi', '24,25') = '2024 e 2025',
    'dois viram "e"', fn_periodo_por_extenso('multi', '24,25'));
  perform teste_assert_pg(fn_periodo_por_extenso('multi', '21,23,25') = '2021, 2023 e 2025',
    'com buraco vira LISTA — o intervalo afirmaria exercício que o documento não traz',
    fn_periodo_por_extenso('multi', '21,23,25'));
  perform teste_assert_pg(fn_periodo_por_extenso('multi', 'L36M') = 'um período de 36 meses',
    'janela móvel é dita como janela', fn_periodo_por_extenso('multi', 'L36M'));
  perform teste_assert_pg(fn_periodo_por_extenso('trimestre', '1T25') = '2025 (1º trimestre)',
    'trimestre com o ANO NA FRENTE — cabe depois de "de"', fn_periodo_por_extenso('trimestre', '1T25'));
  perform teste_assert_pg(fn_periodo_por_extenso('anual', 'REV3') = 'REV3',
    'rótulo que não diz ano SAI COMO VEIO — esconder o que não se entendeu é pior',
    coalesce(fn_periodo_por_extenso('anual', 'REV3'), 'null'));

  perform teste_assert_pg(fn_valor_pt_br(16060, 'milhar') = 'R$ 16.060 mil',
    'valor em reais, escala em palavra', fn_valor_pt_br(16060, 'milhar'));
  perform teste_assert_pg(fn_valor_pt_br(-240, 'milhar') = '-R$ 240 mil',
    'o sinal vem antes da moeda', fn_valor_pt_br(-240, 'milhar'));
  perform teste_assert_pg(fn_valor_pt_br(1, 'milhao') = 'R$ 1 milhão',
    'um milhão no singular', fn_valor_pt_br(1, 'milhao'));
  perform teste_assert_pg(fn_valor_pt_br(999, 'sacos') = 'R$ 999 sacos',
    'escala desconhecida fica VISÍVEL, com a palavra do documento', fn_valor_pt_br(999, 'sacos'));

  -- Ponta a ponta: um caso novo, com duas empresas cujos exercícios DIFEREM.
  v_caso2 := (fn_upsert_caso('Caso perguntas — texto ao cliente'))::uuid;
  -- Alfa: DRE de três exercícios, sem despesa financeira → dispara A6.
  v_r := fn_registrar_documento(
    v_caso2, 'Alfa Ltda', 'multi', '23,24,25', 'DRE', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/dre-alfa.pdf', 'DRE Alfa.pdf', true, 'HASH-PG-T1', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, '[
    {"chave": "RECEITA OPERACIONAL BRUTA", "valor_num": "1000", "unidade": "milhar", "confianca": "0.9"},
    {"chave": "RESULTADO FINANCEIRO LIQUIDO", "valor_num": "-80", "unidade": "milhar", "confianca": "0.9"}
  ]'::jsonb, 'N0');
  -- Beta: DRE de UM exercício só, também sem despesa financeira.
  v_r := fn_registrar_documento(
    v_caso2, 'Beta Ltda', 'anual', '2025', 'DRE', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/dre-beta.pdf', 'DRE Beta.pdf', true, 'HASH-PG-T2', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, '[
    {"chave": "RECEITA OPERACIONAL BRUTA", "valor_num": "500", "unidade": "milhar", "confianca": "0.9"},
    {"chave": "RESULTADO FINANCEIRO LIQUIDO", "valor_num": "-30", "unidade": "milhar", "confianca": "0.9"}
  ]'::jsonb, 'N0');
  -- E um mútuo de escala única, para o marcador de valor.
  v_r := fn_registrar_documento(
    v_caso2, 'Alfa Ltda', 'anual', '2025', 'MUTUOS', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/mut-t.pdf', 'Mutuos Texto.pdf', true, 'HASH-PG-T3', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, '[
    {"chave": "Mútuo a receber - Beta", "valor_num": "11160", "unidade": "milhar", "confianca": "0.9"},
    {"chave": "Mútuo a pagar - Gama",   "valor_num": "4900",  "unidade": "milhar", "confianca": "0.9"}
  ]'::jsonb, 'N0');

  select s.pergunta into v_txt from fn_sugerir_perguntas(v_caso2) s
   where s.codigo = 'A6' and s.entidade = 'Alfa Ltda';
  perform teste_assert_pg(v_txt like '%Na DRE de 2023 a 2025%',
    'a pergunta da Alfa cita os exercícios da DRE DELA', left(coalesce(v_txt, 'null'), 140));

  select s.pergunta into v_txt from fn_sugerir_perguntas(v_caso2) s
   where s.codigo = 'A6' and s.entidade = 'Beta Ltda';
  perform teste_assert_pg(v_txt like '%Na DRE de 2025%' and v_txt not like '%2023%',
    'e a da Beta cita SÓ 2025 — o exercício que a DRE dela tem', left(coalesce(v_txt, 'null'), 140));

  select count(*) into v_n from fn_sugerir_perguntas(v_caso2) s
   where s.pergunta like '%23,24,25%' or s.pergunta like '%12M%' or s.pergunta like '%L36M%'
      or s.pergunta like '%milhar%';
  perform teste_assert_pg(v_n = 0,
    'NENHUMA pergunta do caso publica referência crua nem nome de escala', 'achou ' || v_n);

  select s.pergunta into v_txt from fn_sugerir_perguntas(v_caso2) s where s.codigo = '5.1';
  perform teste_assert_pg(v_txt like '%R$ 16.060 mil%',
    'o saldo de mútuos sai em reais, com separador de milhar', left(coalesce(v_txt, 'null'), 140));

  raise notice 'perguntas OK — A3 dispara e A1/A2 calam; sempre só com conteúdo; marcadores resolvidos ou visíveis; saldo por escala única; linha_presente pronta para o upgrade do dono; ação humana auditada; só leitura; append-only imposto; período por ano; pergunta com o nome da empresa; par (código, empresa) único para a paginação da aba; texto ao cliente em português (0122)';
end $$;

do $$
declare
  c_canastra constant uuid := '11111111-3333-3333-3333-111111111111';
  v_caso  uuid;
  v_r     jsonb;
  v_txt   text;
  v_falhas int := 0;
  procedure_ok boolean;
begin
  raise notice '--- 13. {saldo_mutuos} estrutural: o documento é o conceito (0187, revisão) ---';

  -- (a) O ARRANJO REAL: fixture canastra, documento ...0014, sem tocar nada.
  select s.pergunta into v_txt from fn_sugerir_perguntas(c_canastra) s where s.codigo = '5.1';
  procedure_ok := v_txt like '%R$ 16.060 mil%' and v_txt not like '%não localizado%';
  raise notice '% canastra real (par de empresas + TOTAL) → R$ 16.060 mil — %',
    case when procedure_ok then 'ok   ' else 'FALHOU:' end, left(coalesce(v_txt, 'null'), 120);
  if not coalesce(procedure_ok, false) then v_falhas := v_falhas + 1; end if;

  -- (b) itens + total geral no mesmo documento.
  v_caso := (fn_upsert_caso('Caso perguntas — mútuos com total geral'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'Total Geral Ltda', 'anual', '2025', 'MUTUOS', 0.9,
    'nome_arquivo', 'supabase_storage', 'bucket/mut-tot.pdf', 'Mutuos Total.pdf', true, 'HASH-PG-13B', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, '[
    {"chave": "Mútuo a receber - Beta", "valor_num": "100", "unidade": "milhar", "confianca": "0.9"},
    {"chave": "Mútuo a pagar - Gama",   "valor_num": "50",  "unidade": "milhar", "confianca": "0.9"},
    {"chave": "Saldo total dos mútuos", "valor_num": "150", "unidade": "milhar", "confianca": "0.9"}
  ]'::jsonb, 'N0');
  select s.pergunta into v_txt from fn_sugerir_perguntas(v_caso) s where s.codigo = '5.1';
  procedure_ok := v_txt like '%R$ 150 mil%' and v_txt not like '%R$ 300 mil%';
  raise notice '% item + total geral → o total (R$ 150 mil), não a soma dos dois (R$ 300 mil) — %',
    case when procedure_ok then 'ok   ' else 'FALHOU:' end, left(coalesce(v_txt, 'null'), 120);
  if not coalesce(procedure_ok, false) then v_falhas := v_falhas + 1; end if;

  -- (c) matricial: saldo do ano anterior, juros e saldo do ano na mesma linha.
  v_caso := (fn_upsert_caso('Caso perguntas — mútuos matricial'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'Matricial Ltda', 'anual', '2025', 'MUTUOS', 0.9,
    'nome_arquivo', 'supabase_storage', 'bucket/mut-mat.pdf', 'Mutuos Matricial.pdf', true, 'HASH-PG-13C', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, '[
    {"chave": "CANASTRA PARTICIPAÇÕES S.A. → CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.", "valor_num": "7991",  "unidade": "milhar", "periodo_coluna": "Saldo 2024", "confianca": "0.9"},
    {"chave": "CANASTRA PARTICIPAÇÕES S.A. → CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.", "valor_num": "1088",  "unidade": "milhar", "periodo_coluna": "Juros",      "confianca": "0.9"},
    {"chave": "CANASTRA PARTICIPAÇÕES S.A. → CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.", "valor_num": "11079", "unidade": "milhar", "periodo_coluna": "Saldo 2025", "confianca": "0.9"}
  ]'::jsonb, 'N0');
  select s.pergunta into v_txt from fn_sugerir_perguntas(v_caso) s where s.codigo = '5.1';
  procedure_ok := v_txt like '%R$ 11.079 mil%' and v_txt not like '%20.158%';
  raise notice '% matricial → só a coluna do exercício mais recente (R$ 11.079 mil), não 20.158 — %',
    case when procedure_ok then 'ok   ' else 'FALHOU:' end, left(coalesce(v_txt, 'null'), 120);
  if not coalesce(procedure_ok, false) then v_falhas := v_falhas + 1; end if;

  -- (d) duas colunas, nenhuma com exercício: não há como escolher.
  v_caso := (fn_upsert_caso('Caso perguntas — mútuos sem exercício'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'Sem Exercicio Ltda', 'anual', '2025', 'MUTUOS', 0.9,
    'nome_arquivo', 'supabase_storage', 'bucket/mut-sem.pdf', 'Mutuos Sem.pdf', true, 'HASH-PG-13D', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, '[
    {"chave": "Alfa → Beta", "valor_num": "100", "unidade": "milhar", "periodo_coluna": "Saldo inicial", "confianca": "0.9"},
    {"chave": "Alfa → Beta", "valor_num": "120", "unidade": "milhar", "periodo_coluna": "Saldo final",   "confianca": "0.9"}
  ]'::jsonb, 'N0');
  select s.pergunta into v_txt from fn_sugerir_perguntas(v_caso) s where s.codigo = '5.1';
  procedure_ok := v_txt like '%não foi possível apurar o saldo%' and v_txt like '%nenhuma diz o exercício%'
                  and v_txt not like '%R$%';
  raise notice '% sem exercício → "não foi possível apurar" com o motivo, e nenhum número — %',
    case when procedure_ok then 'ok   ' else 'FALHOU:' end, left(coalesce(v_txt, 'null'), 200);
  if not coalesce(procedure_ok, false) then v_falhas := v_falhas + 1; end if;

  if v_falhas > 0 then
    raise exception 'FALHOU: % assert(s) do saldo de mútuos (bloco 13) reprovaram', v_falhas;
  end if;
  raise notice 'perguntas #13 OK — saldo de mútuos pelo documento: real, total geral, matricial, e o não-apurável dito';
end $$;

drop function teste_assert_pg(boolean, text, text);
