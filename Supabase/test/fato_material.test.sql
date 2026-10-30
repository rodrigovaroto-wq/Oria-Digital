-- Testes do fato material (Supabase/migrations/0148).
-- Rodar via Supabase/test/run.sh (que aplica TODAS as migrations antes).
--
-- O QUE ESTE ARQUIVO TRAVA, e por que cada propriedade importa mais do que
-- parece. Este é o único canal do produto em que a saída NÃO é um número: é uma
-- frase, lida de texto corrido, que vai ao topo da tela do mandato e que um
-- comitê de crédito lê ANTES da planilha. Um erro aqui não produz número errado
-- — produz um alerta errado, que é pior, porque alerta não se confere por
-- aritmética.
--
--   1. A EVIDÊNCIA É OBRIGATÓRIA. Fato sem trecho literal é descartado na
--      gravação. É a decisão (2) da 0148: um resumo escrito pelo modelo é
--      afirmação; a frase copiada do documento é evidência, e quem lê "incerteza
--      sobre continuidade operacional" tem de poder abrir a página e achar
--      aquela frase.
--   2. A RECUSA É CONTADA, não silenciosa. Recusa silenciosa vira ausência, e
--      ausência parece "este documento não disse nada" — que é exatamente o
--      estado que a 0148 existe para corrigir. Se o modelo passar a mandar fatos
--      sem prova, isso tem de aparecer como NÚMERO.
--   3. `null` NÃO É `[]`. Resposta sem a chave `fatos` (workflow antigo) não
--      pode apagar os fatos já gravados de uma versão. É o modo de falha do
--      `Gravar Campos` que desligou a reconciliação por onze dias em silêncio:
--      um insumo que some faz o estágio virar no-op, e no-op tem a mesma
--      aparência de "está tudo certo".
--   4. REEXTRAIR SUBSTITUI, NÃO ACUMULA. Sem isto, reprocessar um documento três
--      vezes mostra o mesmo covenant três vezes na tela.
--   5. O ENUM DO PROMPT E O CATÁLOGO DO BANCO SÃO O MESMO. São duas cópias em
--      dois mundos sem import cruzado (o enum vai no responseSchema da IA, a
--      severidade mora no banco). Um tipo que exista só no prompt é lido do
--      documento e JOGADO FORA como "tipo desconhecido" — o pior desfecho
--      possível desta fatia, e invisível sem este assert.
--   6. A TELA VÊ A VERSÃO CORRENTE, e só ela. Versão anterior é trilha; dois
--      alertas sobre a mesma frase seriam duas verdades.
--
-- RELIGAMENTO — os defeitos foram reintroduzidos e MEDIDOS:
--   * limite de 20 caracteres removido do `where`: o assert 1 caiu, e o fato sem
--     prova entrou como se fosse evidência.
--   * `delete` removido de `fn_registrar_fatos`: o assert 4 caiu com 2 linhas
--     onde devia haver 1.
--   * um tipo acrescentado só ao FATO_TIPO_ENUM do extract.mjs: o assert 5 caiu
--     nomeando o tipo.

create or replace function teste_assert_fato(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_caso   uuid;
  v_doc    uuid;
  v_v1     uuid;
  v_v2     uuid;
  v_out    jsonb;
  v_n      int;
  v_txt    text;
  v_txt2   text;
  v_v3     uuid;
  v_v4     uuid;
  v_v5     uuid;
  v_doc2   uuid;
  v_uuid   uuid;
  v_presente boolean;
  -- As frases são as do caso real da v48 (ANEXO A.2), encurtadas.
  c_covenant constant text :=
    'o índice apurado em 31/12/2025 não atingiu o mínimo contratado, e os saldos originalmente '
    || 'classificados no passivo não circulante foram integralmente reclassificados para o passivo circulante';
  c_parte constant text :=
    'As operacoes com partes relacionadas estao detalhadas na nota 18 e foram realizadas em '
    || 'condicoes usuais de mercado';
  c_continuidade constant text :=
    'existe incerteza relevante que pode levantar duvida significativa quanto a capacidade de '
    || 'continuidade operacional da Companhia';
  c_ressalva constant text :=
    'Opinião com ressalva sobre as demonstrações contábeis, em razão da limitação de escopo descrita a seguir';
begin
  raise notice '--- 1. A EVIDÊNCIA É OBRIGATÓRIA ---';

  insert into caso (nome) values ('fatos: o que o documento diz') returning id into v_caso;
  insert into documento (caso_id, tipo_taxonomia)
    values (v_caso, 'NOTAS_EXPL') returning id into v_doc;
  insert into documento_versao (documento_id, n_versao, arquivo_ref, nome_original)
    values (v_doc, 1, '33_notas.pdf', '33_Notas_Explicativas.pdf') returning id into v_v1;

  v_out := fn_registrar_fatos(v_v1, jsonb_build_array(
    jsonb_build_object('tipo', 'covenant_rompido', 'trecho', c_covenant,
                       'leitura', 'O covenant foi rompido e a dívida virou curto prazo.', 'pagina', 4),
    -- SEM PROVA: o "trecho" é um resumo do modelo, não uma frase do documento.
    jsonb_build_object('tipo', 'ressalva_auditoria', 'trecho', 'tem ressalva',
                       'leitura', 'O parecer tem ressalva.', 'pagina', 1),
    -- TIPO FORA DO CATÁLOGO, com prova de sobra.
    jsonb_build_object('tipo', 'fato_que_nao_existe', 'trecho', c_ressalva,
                       'leitura', 'Alguma coisa.', 'pagina', 2)
  ));

  perform teste_assert_fato((v_out->>'gravados')::int = 1,
    'só o fato COM trecho literal e tipo conhecido é gravado',
    v_out::text);

  raise notice '--- 2. A RECUSA É CONTADA, NÃO SILENCIOSA ---';

  perform teste_assert_fato((v_out->>'sem_prova')::int = 1,
    'o fato sem trecho literal é CONTADO na recusa (recusa silenciosa vira ausência)',
    v_out::text);
  perform teste_assert_fato((v_out->>'tipo_desconhecido')::int = 1,
    'o tipo fora do catálogo é CONTADO à parte — é diagnóstico diferente de "sem prova"',
    v_out::text);

  select trecho into v_txt from documento_fato where documento_versao_id = v_v1;
  perform teste_assert_fato(v_txt = c_covenant,
    '…e o trecho gravado é a frase do documento, sem reescrita');

  raise notice '--- 3. `null` NÃO É `[]` (o modo de falha do Gravar Campos) ---';

  -- Resposta de um workflow ANTIGO: a chave `fatos` não existe. Isso NÃO pode
  -- apagar o que já foi lido — apagar trilha por causa de um n8n desatualizado é
  -- o defeito que passou onze dias em silêncio na v47.
  v_out := fn_registrar_fatos(v_v1, null);
  select count(*)::int into v_n from documento_fato where documento_versao_id = v_v1;
  perform teste_assert_fato(v_n = 1,
    'resposta SEM a chave "fatos" não apaga os fatos já gravados da versão',
    format('%s fato(s), retorno %s', v_n, v_out));
  perform teste_assert_fato(v_out ? 'nota',
    '…e o retorno DIZ que não tocou em nada, em vez de responder "0 gravados" como se tivesse rodado');

  -- E o inverso tem de valer: lista VAZIA é uma leitura, e ela apaga.
  v_out := fn_registrar_fatos(v_v1, '[]'::jsonb);
  select count(*)::int into v_n from documento_fato where documento_versao_id = v_v1;
  perform teste_assert_fato(v_n = 0,
    'lista VAZIA é uma leitura de verdade ("li e não achei nada") e essa apaga',
    format('%s fato(s)', v_n));

  raise notice '--- 4. REEXTRAIR SUBSTITUI, NÃO ACUMULA ---';

  perform fn_registrar_fatos(v_v1, jsonb_build_array(
    jsonb_build_object('tipo', 'covenant_rompido', 'trecho', c_covenant, 'pagina', 4)));
  perform fn_registrar_fatos(v_v1, jsonb_build_array(
    jsonb_build_object('tipo', 'covenant_rompido', 'trecho', c_covenant, 'pagina', 4)));

  select count(*)::int into v_n from documento_fato where documento_versao_id = v_v1;
  perform teste_assert_fato(v_n = 1,
    'gravar duas vezes a mesma leitura deixa UM fato, não dois',
    format('%s fato(s)', v_n));

  raise notice '--- 5. O ENUM DO PROMPT E O CATÁLOGO DO BANCO SÃO O MESMO ---';

  -- A lista abaixo é uma cópia LITERAL de FATO_TIPO_ENUM (N8N/lib/extract.mjs).
  -- Ela existe aqui porque SQL não importa .mjs — e é justamente por não haver
  -- import que a divergência é possível. O custo de manter a cópia é uma linha;
  -- o custo de não ter o assert é um fato lido do documento e jogado fora.
  select string_agg(t, ', ' order by t) into v_txt
    from unnest(array[
      'continuidade_operacional', 'ressalva_auditoria', 'covenant_rompido',
      'reclassificacao_divida', 'litigio_relevante', 'garantia_dada',
      'evento_subsequente', 'parte_relacionada', 'mudanca_criterio_contabil'
    ]) t
   where not exists (select 1 from fato_tipo_catalogo c where c.tipo = t);
  perform teste_assert_fato(v_txt is null,
    'todo tipo do FATO_TIPO_ENUM (extract.mjs) existe no catálogo do banco',
    coalesce(v_txt, ''));

  select string_agg(c.tipo, ', ' order by c.tipo) into v_txt
    from fato_tipo_catalogo c
   where c.tipo <> all (array[
      'continuidade_operacional', 'ressalva_auditoria', 'covenant_rompido',
      'reclassificacao_divida', 'litigio_relevante', 'garantia_dada',
      'evento_subsequente', 'parte_relacionada', 'mudanca_criterio_contabil']);
  perform teste_assert_fato(v_txt is null,
    '…e o contrário também: tipo no banco que o prompt nunca pede é tipo que nunca chega',
    coalesce(v_txt, ''));

  -- E toda severidade tem de ser uma das três que a tela sabe pintar.
  select count(*)::int into v_n from fato_tipo_catalogo
   where severidade not in ('critico', 'relevante', 'informativo');
  perform teste_assert_fato(v_n = 0, 'toda severidade do catálogo é uma das três que a tela pinta');

  select count(*)::int into v_n from fato_tipo_catalogo where trim(coalesce(porque, '')) = '';
  perform teste_assert_fato(v_n = 0,
    'todo tipo diz POR QUE importa — sem isso o alerta é etiqueta, não decisão');

  raise notice '--- 6. A TELA VÊ A VERSÃO CORRENTE, E SÓ ELA ---';

  insert into documento_versao (documento_id, n_versao, arquivo_ref, nome_original)
    values (v_doc, 2, '33_notas_v2.pdf', '33_Notas_Explicativas.pdf') returning id into v_v2;
  perform fn_registrar_fatos(v_v2, jsonb_build_array(
    jsonb_build_object('tipo', 'ressalva_auditoria', 'trecho', c_ressalva,
                       'leitura', 'O parecer não é limpo.', 'pagina', 1)));

  select count(*)::int into v_n from fn_fatos_do_caso(v_caso);
  perform teste_assert_fato(v_n = 1,
    'o caso mostra UM fato — o da versão corrente; a versão 1 é trilha e não aparece',
    format('%s fato(s)', v_n));

  select tipo, rotulo, severidade into v_txt, v_txt, v_txt from fn_fatos_do_caso(v_caso);
  select f.tipo || ' | ' || f.rotulo || ' | ' || f.severidade || ' | ' || f.nome_documento
    into v_txt from fn_fatos_do_caso(v_caso) f;
  perform teste_assert_fato(
    v_txt = 'ressalva_auditoria | Opinião com ressalva do auditor | critico | 33_Notas_Explicativas.pdf',
    '…e ele chega com rótulo humano, gravidade e o nome do arquivo — a tela não precisa de switch',
    coalesce(v_txt, '<null>'));

  -- A ORDEM É A DA GRAVIDADE, e é o que faz a lista ser lida de cima. Com dois
  -- fatos de pesos diferentes na mesma versão, o crítico vem primeiro.
  perform fn_registrar_fatos(v_v2, jsonb_build_array(
    jsonb_build_object('tipo', 'parte_relacionada', 'trecho',
      'As operações com partes relacionadas estão detalhadas na nota 18 e foram realizadas em condições usuais'),
    jsonb_build_object('tipo', 'continuidade_operacional', 'trecho',
      'existe incerteza relevante que pode levantar dúvida significativa quanto à capacidade de continuidade operacional')));

  select string_agg(f.tipo, ' > ') into v_txt from (select tipo from fn_fatos_do_caso(v_caso)) f;
  perform teste_assert_fato(v_txt = 'continuidade_operacional > parte_relacionada',
    'a lista sai na ordem da GRAVIDADE — o crítico primeiro, para ser lida de cima',
    coalesce(v_txt, '<null>'));

  raise notice '--- 7. A GRAVAÇÃO NÃO DERRUBA O DIAGNÓSTICO (0149) ---';

  -- POR QUE ISTO É O ASSERT MAIS IMPORTANTE DESTE ARQUIVO. `fn_registrar_fatos`
  -- roda na MESMA query que `fn_registrar_diagnostico` — decisão da 0148, para
  -- não acrescentar nó ao canvas. O preço dessa economia é que QUALQUER exceção
  -- aqui aborta a query e o documento perde o DIAGNÓSTICO inteiro: entidade,
  -- tipo confirmado, período, resumo. Um número de página alucinado pelo modelo
  -- custaria o estágio.
  --
  -- MEDIDO na auditoria: `pagina = 99999999999` levantava
  -- "value out of range for type integer" [22003], e uma versão inexistente
  -- levantava violação de chave estrangeira [23503]. As duas derrubavam.
  v_out := fn_registrar_fatos(v_v1, jsonb_build_array(
    jsonb_build_object('tipo', 'covenant_rompido', 'trecho', c_covenant, 'pagina', 99999999999)));
  perform teste_assert_fato((v_out->>'gravados')::int = 1,
    'página absurda NÃO derruba a gravação — o fato entra, porque a evidência é o TRECHO',
    v_out::text);
  perform teste_assert_fato((v_out->>'pagina_descartada')::int = 1,
    '…e a página descartada é CONTADA, para ninguém achar que o documento não tinha página',
    v_out::text);

  select pagina into v_n from documento_fato where documento_versao_id = v_v1;
  perform teste_assert_fato(v_n is null,
    '…e a página absurda vira NULL em vez de um número que não existe',
    coalesce(v_n::text, '<null>'));

  -- Página plausível continua entrando: um portão que descarte tudo é um portão
  -- que não discrimina, e passaria neste bloco com nota máxima.
  perform fn_registrar_fatos(v_v1, jsonb_build_array(
    jsonb_build_object('tipo', 'covenant_rompido', 'trecho', c_covenant, 'pagina', 4)));
  select pagina into v_n from documento_fato where documento_versao_id = v_v1;
  perform teste_assert_fato(v_n = 4, '…e a página plausível continua entrando (o guarda discrimina)');

  v_out := fn_registrar_fatos('00000000-0000-0000-0000-000000000000'::uuid,
    jsonb_build_array(jsonb_build_object('tipo', 'covenant_rompido', 'trecho', c_covenant)));
  perform teste_assert_fato(v_out ? 'erro' and v_out->>'erro' is not null,
    'versão inexistente vira ERRO DECLARADO no retorno, não exceção que aborta a query',
    v_out::text);
  perform teste_assert_fato(v_out->>'sqlstate' = '23503',
    '…e o retorno diz QUAL erro foi, para o diagnóstico não virar adivinhação',
    v_out::text);

  -- E o delete tem de ser desfeito junto com o insert que falhou: a versão fica
  -- com os fatos que já tinha, em vez de ficar sem nenhum por causa de um erro.
  select count(*)::int into v_n from documento_fato where documento_versao_id = v_v1;
  perform teste_assert_fato(v_n = 1,
    '…e um erro na gravação NÃO deixa a versão sem os fatos que ela já tinha',
    format('%s fato(s)', v_n));

  raise notice '--- 8. O REENVIO DE ARQUIVO NÃO APAGA OS FATOS DA TELA (0149) ---';

  -- DOCUMENTO PRÓPRIO, e a lição é de teste, não de produto: a primeira versão
  -- deste bloco reaproveitava o documento dos blocos anteriores e media 2 onde
  -- esperava 1 — o estado de um bloco vazando para o outro. Um assert que
  -- depende da ordem em que os blocos rodam mede o arquivo, não o sistema.
  insert into documento (caso_id, tipo_taxonomia)
    values (v_caso, 'NOTAS_EXPL') returning id into v_doc2;
  insert into documento_versao (documento_id, n_versao, arquivo_ref, nome_original)
    values (v_doc2, 1, 'reenvio_v1.pdf', '33_Notas_Explicativas.pdf') returning id into v_v3;

  perform fn_registrar_fatos(v_v3, jsonb_build_array(jsonb_build_object(
    'tipo', 'covenant_rompido', 'trecho', c_covenant, 'pagina', 4)));

  select count(*)::int into v_n from fn_fatos_do_caso(v_caso) where documento_id = v_doc2;
  perform teste_assert_fato(v_n = 1, 'PRÉ-CONDIÇÃO: a versão 1 carrega o covenant',
    format('%s fato(s)', v_n));

  -- MEDIDO na auditoria: com a v1 carregando um covenant e a v2 recém-criada e
  -- ainda não processada, `fn_fatos_do_caso` devolvia ZERO. O alerta mais
  -- importante do mandato desaparecia da tela durante um reenvio, sem nada
  -- acusar — a 0148 escolhia por `n_versao desc` sem perguntar se a versão
  -- chegou a ser LIDA.
  insert into documento_versao (documento_id, n_versao, arquivo_ref, nome_original)
    values (v_doc2, 2, 'reenvio_v2.pdf', '33_Notas_Explicativas.pdf') returning id into v_v4;

  select count(*)::int into v_n from fn_fatos_do_caso(v_caso) where documento_id = v_doc2;
  perform teste_assert_fato(v_n = 1,
    'versão nova AINDA NÃO AVALIADA não apaga da tela o que a anterior achou',
    format('%s fato(s) visível(is)', v_n));

  select documento_versao_id into v_uuid from fn_fatos_do_caso(v_caso) where documento_id = v_doc2;
  perform teste_assert_fato(v_uuid = v_v3, '…e o fato mostrado é o da versão 1, nomeadamente');

  -- …e quando ela É avaliada e não acha nada, o fato anterior SOME — porque
  -- releitura que revoga tem de revogar. Sem este lado, a correção viraria "o
  -- fato nunca some", que é pior que o defeito original.
  perform fn_registrar_fatos(v_v4, '[]'::jsonb);
  select count(*)::int into v_n from fn_fatos_do_caso(v_caso) where documento_id = v_doc2;
  perform teste_assert_fato(v_n = 0,
    '…mas quando ela É avaliada e não acha nada, o fato anterior é revogado',
    format('%s fato(s) visível(is)', v_n));

  select fatos_avaliados_em is not null into v_presente from documento_versao where id = v_v4;
  perform teste_assert_fato(v_presente,
    '…e a marca de avaliada é gravada mesmo com ZERO fatos (é esse caso que ela separa)');

  -- Resposta SEM a chave (workflow antigo) não marca como avaliada: não foi lida.
  insert into documento_versao (documento_id, n_versao, arquivo_ref)
    values (v_doc2, 3, 'reenvio_v3.pdf') returning id into v_v5;
  perform fn_registrar_fatos(v_v5, null);
  select fatos_avaliados_em is null into v_presente from documento_versao where id = v_v5;
  perform teste_assert_fato(v_presente,
    'resposta sem a chave "fatos" NÃO marca a versão como avaliada — ela não foi lida');

  raise notice '--- 9. A ORDEM DA LISTA É ESTÁVEL (0149) ---';

  -- MEDIDO: três fatos gravados no mesmo `insert` compartilham UM único
  -- `criado_em` (now() é estável na transação), e o `order by` da 0148 parava
  -- ali. Numa tela em que a ORDEM SIGNIFICA GRAVIDADE, a mesma lista podia sair
  -- em ordens diferentes entre duas leituras, sem nunca dar erro.
  perform fn_registrar_fatos(v_v4, jsonb_build_array(
    jsonb_build_object('tipo', 'ressalva_auditoria',       'trecho', 'AAA ' || c_ressalva),
    jsonb_build_object('tipo', 'ressalva_auditoria',       'trecho', 'BBB ' || c_ressalva),
    jsonb_build_object('tipo', 'ressalva_auditoria',       'trecho', 'CCC ' || c_ressalva),
    jsonb_build_object('tipo', 'parte_relacionada',        'trecho', c_parte),
    jsonb_build_object('tipo', 'continuidade_operacional', 'trecho', c_continuidade)));

  select count(distinct criado_em)::int into v_n
    from documento_fato where documento_versao_id = v_v4;
  perform teste_assert_fato(v_n = 1,
    'PRÉ-CONDIÇÃO: os cinco compartilham um só criado_em (senão o teste não mede nada)',
    format('%s valor(es) distinto(s)', v_n));

  -- E O TESTE PRECISA PERTURBAR O HEAP PARA MEDIR ALGUMA COISA. A primeira
  -- versão deste assert comparava duas leituras SEGUIDAS e passava com e sem o
  -- desempate — medido no religamento: tirar `f.id` do `order by` não a fazia
  -- reprovar. Duas execuções idênticas do mesmo plano devolvem a mesma ordem
  -- física, então o assert confirmava o que já sabia.
  --
  -- Um `update` reescreve a tupla e a joga para o fim da tabela, que é o que
  -- acontece de verdade quando alguém edita uma linha. Sem desempate, a ordem
  -- de saída muda junto; com ele, não muda.
  select string_agg(x.trecho, '|') into v_txt
    from (select trecho from fn_fatos_do_caso(v_caso) where documento_id = v_doc2) x;

  update documento_fato set leitura = coalesce(leitura, '')
   where id = (select f.id from documento_fato f
                where f.documento_versao_id = v_v4 and f.tipo = 'ressalva_auditoria'
                order by f.trecho limit 1);

  select string_agg(y.trecho, '|') into v_txt2
    from (select trecho from fn_fatos_do_caso(v_caso) where documento_id = v_doc2) y;
  perform teste_assert_fato(v_txt = v_txt2,
    'a ordem NÃO muda quando uma linha é reescrita e muda de lugar no heap',
    coalesce(v_txt, '<null>') || '  ->  ' || coalesce(v_txt2, '<null>'));

  select string_agg(z.severidade, '>') into v_txt
    from (select severidade from fn_fatos_do_caso(v_caso) where documento_id = v_doc2) z;
  perform teste_assert_fato(v_txt = 'critico>critico>critico>critico>informativo',
    '…e a gravidade continua mandando: os quatro críticos antes do informativo',
    coalesce(v_txt, '<null>'));

  raise notice '--- 10. A ESCRITA É PERMITIDA PELA POLÍTICA, NÃO PELA CREDENCIAL (0149) ---';

  -- MEDIDO na auditoria: `set local role authenticated` + gravação devolvia
  -- "new row violates row-level security policy" [42501]. A 0148 deu à tabela
  -- só política de SELECT — e mesmo assim `grant execute` da função ao papel
  -- `authenticated`, uma permissão que a política não honrava. Gravava só
  -- porque o n8n conecta como dono, que ignora RLS: o canal dependia de um
  -- detalhe da credencial em vez de uma decisão.
  begin
    set local role authenticated;
    v_out := fn_registrar_fatos(v_v1, jsonb_build_array(jsonb_build_object(
      'tipo', 'covenant_rompido', 'trecho', c_covenant, 'pagina', 4)));
    reset role;
    perform teste_assert_fato((v_out->>'gravados')::int = 1,
      'o papel `authenticated` GRAVA — a permissão da função e a política da tabela concordam',
      v_out::text);
  exception when others then
    reset role;
    perform teste_assert_fato(false,
      'o papel `authenticated` GRAVA — a permissão da função e a política da tabela concordam',
      sqlerrm);
  end;

  raise notice '--- 11. A COLUNA QUE PROMETIA MEDIÇÃO E ENTREGAVA OPINIÃO SAIU (0149) ---';

  select count(*)::int into v_n from pg_attribute
   where attrelid = to_regclass('public.documento_fato')
     and attname = 'confianca' and attnum > 0 and not attisdropped;
  perform teste_assert_fato(v_n = 0,
    'documento_fato não tem coluna `confianca` — ela nunca recebeu valor, e a evidência aqui é o trecho');

  delete from documento_fato where documento_versao_id in (v_v1, v_v2, v_v3, v_v4, v_v5);
  delete from documento_versao where id in (v_v1, v_v2, v_v3, v_v4, v_v5);
  delete from documento where id in (v_doc, v_doc2);
  delete from caso where id = v_caso;

  raise notice 'fato_material OK — evidência obrigatória; recusa contada; null≠[]; reextrair substitui; enum espelhado; e os SETE da auditoria: não derruba o diagnóstico, reenvio não apaga, ordem estável, política honra o grant, confianca fora';
end $$;

drop function teste_assert_fato(boolean, text, text);
