-- Testes da sonda de instalação (Supabase/migrations/0131).
-- Rodar via Supabase/test/run.sh (que aplica TODAS as migrations antes).
--
-- O QUE ESTES TESTES TRAVAM, e por que o arnês aqui é peculiar. Este banco de
-- teste é, por construção, uma instalação COMPLETA: o `run.sh` aplica as 76
-- migrations do zero. Isso dá ao arquivo uma propriedade que nenhum outro teste da
-- casa tem — **ele é o único lugar onde o catálogo de requisitos é conferido
-- contra a realidade.** Se `instalacao_requisito` aponta para
-- `caso.fechado_en` (typo), o painel de produção diria "0114 ausente" para uma
-- instalação perfeita, e ninguém descobriria: o recado seria plausível, porque a
-- 0114 REALMENTE precisa ser aplicada à mão. Um painel de saúde que dá alarme
-- falso é pior que nenhum painel, porque ensina a ignorá-lo.
--
-- As propriedades, em ordem de importância:
--
--   1. TODO REQUISITO ESTRUTURAL ESTÁ PRESENTE NESTE BANCO. É o assert que
--      transforma o catálogo em algo conferível. Typo em `objeto`, migration
--      renomeada, função que mudou de nome — tudo cai aqui, e cai no CI, antes de
--      virar alarme falso na tela do dono.
--   2. A SONDA NÃO MORRE quando o objeto que ela mede não existe. Ela é o último
--      lugar do sistema que pode falhar por causa do que existe para medir: um
--      requisito de seed apontando para tabela ausente tem de devolver
--      `presente=false`, não derrubar o painel inteiro com "relation does not
--      exist" — e aí a tela que ia dizer o que fazer é a tela que não abre.
--   3. A SONDA DE FATO SONDA. Requisito fabricado apontando para objeto
--      inexistente devolve false. Sem este assert, uma função que devolvesse
--      `true` fixo passaria no assert 1 com nota máxima.
--   4. O RESUMO CONTA O MESMO que a listagem. Painel que diz "instalação
--      completa" enquanto a lista mostra um item vermelho é a contradição mais
--      cara possível numa tela de saúde.
--   5. SEED VAZIO É DISTINGUIDO DE TABELA AUSENTE. São duas causas com duas ações
--      diferentes ("aplique a migration" contra "rode o seed"), e a 0131 as separa
--      em tipos justamente porque uma migration parcialmente aplicada passa na
--      sonda de estrutura.
--   6. O CUSTO DA SONDA NÃO CRESCE COM O DADO (0132). Um dos requisitos é
--      `lote_execucao`, que ganha uma linha por execução de ingestão e nunca para
--      de crescer — e a sonda roda a cada carga do painel. Com `count(*)`, a tela
--      mais usada da casa fica linearmente mais lenta pelo resto da vida do
--      produto, sem nunca quebrar: o defeito não tem sintoma até virar lentidão
--      difusa que ninguém sabe atribuir. O que trava a volta do `count(*)` é o
--      TEXTO do detalhe ("ou mais"), não um assert de relógio — a versão com
--      relógio passou no religamento e foi removida, com o motivo escrito no
--      bloco 6.
--
-- RELIGAMENTO — os defeitos foram reintroduzidos e MEDIDOS:
--
--   * `objeto` de `mandato_fechado` trocado para `caso.fechado_en`: o assert 1 caiu
--     nomeando a chave, que é exatamente o alarme falso descrito acima.
--   * o guarda `to_regclass(...) is null` removido do ramo de seed: o teste não
--     falhou num assert — MORREU com `relation "public.tabela_que_nao_existe" does
--     not exist` dentro de `fn_instalacao_conferir`, provando que sem o guarda a
--     sonda cai junto com o que ela mede.
--   * `fn_instalacao_resumo` com `completa` fixo em true: o assert 4 caiu.

create or replace function teste_assert_inst(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_ausentes   text;
  v_n_total    int;
  v_n_lista    int;
  v_resumo     jsonb;
  v_presente   boolean;
  v_detalhe    text;
begin
  raise notice '--- 1. TODO REQUISITO ESTRUTURAL EXISTE NESTE BANCO ---';

  -- O banco de teste tem todas as migrations aplicadas, então nenhum requisito de
  -- ESTRUTURA pode faltar. Os de 'comportamento' são exceção legítima e ficam
  -- fora: `lote_execucao` com linha prova que o workflow do n8n rodou, e nenhum
  -- n8n roda num container de CI.
  select string_agg(format('%s (%s %s)', chave, tipo, objeto), ', ' order by chave)
    into v_ausentes
  from fn_instalacao_conferir()
  where not presente and tipo in ('tabela', 'coluna', 'funcao', 'corpo');

  perform teste_assert_inst(v_ausentes is null,
    'todo requisito de estrutura do catálogo existe neste banco (nenhum alarme falso)',
    coalesce(v_ausentes, ''));

  -- 0147: `corpo` ENTRA NESTE ASSERT, e é aqui que ele paga o próprio preço.
  --
  -- O tipo `corpo` exige que um TRECHO apareça em `pg_get_functiondef` — é assim
  -- que a sonda distingue `fn_registrar_diagnostico` corrigida pela 0142 da
  -- homônima com o corpo de antes. Isso o torna sensível a reescrita: uma
  -- migration futura que republique aquela função sem o comentário `-- 0142`
  -- faria o painel de produção acusar ausência num banco completo.
  --
  -- Deixá-lo FORA do assert acima seria pior das duas maneiras: os marcadores
  -- nunca seriam conferidos contra a realidade (e um typo em `marcador` viraria
  -- alarme falso permanente na tela do dono, exatamente o defeito que este
  -- arquivo existe para não deixar acontecer), e a reescrita passaria calada.
  -- Dentro, ela reprova no CI na mesma passada em que foi feita.
  select count(*)::int into v_n_total from instalacao_requisito where tipo = 'corpo';
  perform teste_assert_inst(v_n_total > 0,
    'o catálogo tem requisito de CORPO — sem eles a sonda não vê as migrations que só '
    'republicam função, que são a maioria das recentes',
    format('%s requisito(s) de corpo', v_n_total));

  -- E os seeds também: o `run.sh` aplica as migrations que os semeiam.
  select string_agg(format('%s (%s)', chave, objeto), ', ' order by chave)
    into v_ausentes
  from fn_instalacao_conferir()
  where not presente and tipo = 'seed';

  perform teste_assert_inst(v_ausentes is null,
    'todo seed declarado no catálogo foi de fato semeado pelas migrations',
    coalesce(v_ausentes, ''));

  -- A taxonomia e o dial são os dois requisitos BLOQUEANTES de seed, e valem
  -- assert nominal: são eles que fazem o Portão 1 saber o que cobrar e o dial
  -- existir. Sem eles o sistema aprova por não saber cobrar.
  select presente into v_presente from fn_instalacao_conferir() where chave = 'taxonomia_semeada';
  perform teste_assert_inst(v_presente, 'a taxonomia do Kit Básico está semeada (8 obrigatórios)');

  select presente into v_presente from fn_instalacao_conferir() where chave = 'dial_semeado';
  perform teste_assert_inst(v_presente, 'os oito estágios do dial estão semeados');

  raise notice '--- 2. A SONDA NÃO MORRE COM O QUE ELA MEDE ---';

  -- Requisito de seed apontando para uma tabela que NÃO existe. Sem o guarda
  -- `to_regclass`, o `execute format('select count(*) ...')` levanta exceção e
  -- derruba a sonda inteira — o painel que ia dizer o que fazer não abre.
  insert into instalacao_requisito (chave, migration, tipo, objeto, criterio_seed, porque, severidade, ordem)
  values ('_teste_tabela_ausente', '9999', 'seed', 'tabela_que_nao_existe_mesmo', 1,
          'Requisito fabricado pelo teste.', 'informativo', 9999);

  select presente, detalhe into v_presente, v_detalhe
    from fn_instalacao_conferir() where chave = '_teste_tabela_ausente';

  perform teste_assert_inst(v_presente is not null and not v_presente,
    'requisito de seed sobre tabela inexistente devolve presente=false em vez de derrubar a sonda');
  perform teste_assert_inst(v_detalhe = 'a tabela nem existe',
    '…e o detalhe distingue "a tabela nem existe" de "a tabela está vazia"',
    coalesce(v_detalhe, '<null>'));

  raise notice '--- 3. A SONDA DE FATO SONDA (não devolve true fixo) ---';

  insert into instalacao_requisito (chave, migration, tipo, objeto, porque, severidade, ordem)
  values ('_teste_funcao_ausente', '9999', 'funcao', 'fn_que_nunca_existiu',
          'Requisito fabricado pelo teste.', 'informativo', 9999),
         ('_teste_coluna_ausente', '9999', 'coluna', 'caso.coluna_que_nunca_existiu',
          'Requisito fabricado pelo teste.', 'informativo', 9999),
         ('_teste_tabela_ok', '9999', 'tabela', 'caso',
          'Requisito fabricado pelo teste.', 'informativo', 9999);

  select presente into v_presente from fn_instalacao_conferir() where chave = '_teste_funcao_ausente';
  perform teste_assert_inst(not v_presente, 'função inexistente é reportada ausente');

  select presente into v_presente from fn_instalacao_conferir() where chave = '_teste_coluna_ausente';
  perform teste_assert_inst(not v_presente, 'coluna inexistente é reportada ausente');

  -- O par positivo, no mesmo bloco: sem ele, uma sonda que devolvesse `false`
  -- fixo passaria nos dois asserts acima.
  select presente into v_presente from fn_instalacao_conferir() where chave = '_teste_tabela_ok';
  perform teste_assert_inst(v_presente, '…e tabela existente é reportada PRESENTE (a sonda discrimina)');

  raise notice '--- 3b. A SONDA DE CORPO DISTINGUE AS TRÊS CAUSAS (0147) ---';

  -- Uma sonda de corpo que respondesse `true` fixo passaria no assert 1 com nota
  -- máxima e nunca acusaria uma migration faltando — que é o único trabalho dela.
  -- Os três casos abaixo são as três respostas possíveis, e cada uma pede uma
  -- AÇÃO diferente de quem está lendo o painel:
  --
  --   função ausente          → aplique a migration que a CRIA
  --   corpo sem o marcador    → aplique a migration que a CORRIGE (é a nova)
  --   corpo com o marcador    → nada a fazer
  --
  -- As duas primeiras são "presente = false" e seriam indistinguíveis sem o
  -- detalhe — e mandar alguém procurar a migration errada é o mesmo tipo de
  -- pista falsa que o diagnóstico de erro da API passou o v30 inteiro dando.
  insert into instalacao_requisito
    (chave, migration, tipo, objeto, marcador, porque, severidade, ordem) values
    ('_teste_corpo_ausente', '9999', 'corpo', 'fn_instalacao_conferir',
     'ESTE TRECHO NAO EXISTE EM CORPO NENHUM',
     'Requisito fabricado pelo teste.', 'informativo', 9999),
    ('_teste_corpo_presente', '9999', 'corpo', 'fn_instalacao_conferir',
     'instalacao_requisito',
     'Requisito fabricado pelo teste.', 'informativo', 9999),
    ('_teste_corpo_fn_ausente', '9999', 'corpo', 'fn_que_nunca_existiu',
     'qualquer coisa',
     'Requisito fabricado pelo teste.', 'informativo', 9999);

  select presente, detalhe into v_presente, v_detalhe
    from fn_instalacao_conferir() where chave = '_teste_corpo_ausente';
  perform teste_assert_inst(v_presente is not null and not v_presente,
    'corpo SEM o marcador é reportado ausente (a função existe e a correção não está lá)');
  perform teste_assert_inst(v_detalhe like '%ANTERIOR a esta migration%',
    '…e o detalhe manda aplicar a migration que CORRIGE, não a que cria',
    coalesce(v_detalhe, '<null>'));

  select presente into v_presente
    from fn_instalacao_conferir() where chave = '_teste_corpo_presente';
  perform teste_assert_inst(v_presente,
    '…e corpo COM o marcador é reportado presente (a sonda discrimina, não devolve false fixo)');

  select presente, detalhe into v_presente, v_detalhe
    from fn_instalacao_conferir() where chave = '_teste_corpo_fn_ausente';
  perform teste_assert_inst(v_presente is not null and not v_presente,
    'requisito de corpo sobre função inexistente devolve false em vez de derrubar a sonda');
  perform teste_assert_inst(v_detalhe = 'a função nem existe',
    '…e o detalhe distingue "a função nem existe" de "o corpo é anterior"',
    coalesce(v_detalhe, '<null>'));

  raise notice '--- 4. O RESUMO CONTA O MESMO QUE A LISTAGEM ---';

  select count(*)::int into v_n_lista from fn_instalacao_conferir();
  v_resumo := fn_instalacao_resumo();

  perform teste_assert_inst((v_resumo->>'total')::int = v_n_lista,
    'o total do resumo é o número de linhas da listagem',
    format('resumo=%s lista=%s', v_resumo->>'total', v_n_lista));

  perform teste_assert_inst(
    (v_resumo->>'presentes')::int + (v_resumo->>'ausentes')::int = v_n_lista,
    'presentes + ausentes fecha com o total (nenhum requisito fica sem veredito)');

  -- Os três requisitos fabricados acima estão ausentes, então a instalação NÃO
  -- pode se declarar completa. É o assert que pega um `completa` fixo em true.
  perform teste_assert_inst((v_resumo->>'completa')::boolean is false,
    'com requisito ausente, "completa" é false');

  perform teste_assert_inst(
    jsonb_array_length(v_resumo->'faltando') = (v_resumo->>'ausentes')::int,
    'a lista "faltando" tem exatamente os ausentes — o painel não some com nenhum');

  -- E cada item de `faltando` carrega o SINTOMA, não só o número da migration:
  -- é o que torna o painel acionável para quem está com a tela aberta.
  perform teste_assert_inst(
    not exists (select 1 from jsonb_array_elements(v_resumo->'faltando') f
                 where coalesce(f->>'porque', '') = ''),
    'todo item faltando vem com o sintoma escrito (porque não é vazio)');

  raise notice '--- 5. SEED VAZIO É DISTINGUIDO DE TABELA AUSENTE ---';

  -- Tabela que EXISTE e cujo critério de seed não é atingido. O detalhe tem de
  -- dizer quantas linhas há — "0 linha(s)" e "a tabela nem existe" levam a ações
  -- diferentes (rodar o seed contra aplicar a migration).
  insert into instalacao_requisito (chave, migration, tipo, objeto, criterio_seed, porque, severidade, ordem)
  values ('_teste_seed_alto', '9999', 'seed', 'estagio_autonomia', 9999,
          'Requisito fabricado pelo teste.', 'informativo', 9999);

  select presente, detalhe into v_presente, v_detalhe
    from fn_instalacao_conferir() where chave = '_teste_seed_alto';

  perform teste_assert_inst(not v_presente,
    'seed abaixo do critério é reportado ausente mesmo com a tabela existindo');
  perform teste_assert_inst(v_detalhe ~ '^\d+ linha\(s\)$',
    '…e o detalhe diz QUANTAS linhas há, não "a tabela nem existe"',
    coalesce(v_detalhe, '<null>'));

  raise notice '--- 7. O CATÁLOGO É COERENTE CONSIGO MESMO ---';

  -- `porque` descreve o SINTOMA para quem lê a tela. Um requisito sem sintoma é
  -- um requisito que ninguém sabe o que fazer com — e a coluna é NOT NULL, então
  -- o que este assert pega é o `porque` preenchido com string vazia ou espaço.
  select count(*)::int into v_n_total from instalacao_requisito
   where trim(coalesce(porque, '')) = '' ;
  perform teste_assert_inst(v_n_total = 0,
    'nenhum requisito do catálogo tem sintoma em branco');

  -- Toda migration citada no catálogo existe como arquivo? Isso o SQL não vê. O
  -- que ele pode conferir é o formato — quatro dígitos —, e é o bastante para
  -- pegar um `migration` preenchido com nome de arquivo ou descrição.
  select count(*)::int into v_n_total from instalacao_requisito
   where migration !~ '^\d{4}$';
  perform teste_assert_inst(v_n_total = 0,
    'toda migration do catálogo é citada como quatro dígitos (o painel os ordena)',
    format('%s fora do formato', v_n_total));

  raise notice '--- 6. O CUSTO DA SONDA NÃO CRESCE COM O DADO (0132) ---';

  -- A PROVA É COMPORTAMENTAL, não uma leitura do corpo da função: um requisito de
  -- seed com critério 1 sobre a MAIOR tabela do banco tem de responder no mesmo
  -- tempo que um sobre a menor. Com `count(*)` a diferença aparece; com a
  -- contagem limitada ao critério, não.
  insert into instalacao_requisito (chave, migration, tipo, objeto, criterio_seed, porque, severidade, ordem)
  values ('_teste_seed_tabela_grande', '9999', 'seed', 'campo_extraido', 1,
          'Requisito fabricado pelo teste.', 'informativo', 9999),
         ('_teste_seed_tabela_pequena', '9999', 'seed', 'estagio_autonomia', 1,
          'Requisito fabricado pelo teste.', 'informativo', 9999);

  select count(*)::int into v_n_total from campo_extraido;
  raise notice '      (a tabela grande tem % linhas)', v_n_total;

  select presente into v_presente from fn_instalacao_conferir() where chave = '_teste_seed_tabela_grande';
  perform teste_assert_inst(v_presente, 'requisito de seed sobre a tabela grande responde presente');

  select presente into v_presente from fn_instalacao_conferir() where chave = '_teste_seed_tabela_pequena';
  perform teste_assert_inst(v_presente, 'requisito de seed sobre a tabela pequena responde presente');

  -- NÃO HÁ ASSERT DE TEMPO AQUI, e a ausência foi MEDIDA em vez de suposta.
  --
  -- A primeira versão deste bloco comparava o relógio das duas sondagens
  -- (`grande < pequena * 3`). No religamento — 0131 reaplicada, `count(*)` de
  -- volta — esse assert PASSOU: 3.738 linhas contam rápido demais para a
  -- diferença aparecer. Ele alegava cobertura que não tinha, que é a forma de
  -- teste mais perigosa que existe nesta casa: some da lista de riscos sem nunca
  -- ter olhado para o risco. Aumentar a massa de dados até o relógio doer tornaria
  -- a suíte lenta para todos e o assert intermitente conforme a máquina do CI.
  --
  -- O que ficou é o assert abaixo, e ele PEGOU a regressão no mesmo religamento:
  -- `"ou mais"` só existe na forma limitada, porque a forma limitada é a única que
  -- NÃO conhece o total. O texto é consequência direta da implementação, e é
  -- verificável em qualquer volume de dado. As medições que justificam a 0132
  -- (5,9 ms contra 0,218 ms com 50 mil lotes) estão no cabeçalho da migration,
  -- que é onde medição de custo pertence — não num assert que não a reproduz.
  --
  -- E o detalhe do caso PRESENTE não promete o total exato, porque a 0132 não o
  -- conhece mais — prometer um número que não se mediu é o defeito que este
  -- projeto persegue desde a 0028.
  select detalhe into v_detalhe from fn_instalacao_conferir() where chave = '_teste_seed_tabela_grande';
  perform teste_assert_inst(v_detalhe = '1 linha(s) ou mais',
    '…e o detalhe diz "ou mais" em vez de afirmar um total que não foi contado',
    coalesce(v_detalhe, '<null>'));

  -- LIMPEZA dos requisitos fabricados. Sem ela, o assert 1 de uma execução futura
  -- sobre este mesmo banco reprovaria por causa deste teste.
  delete from instalacao_requisito where chave like '\_teste\_%';

  select count(*)::int into v_n_total from instalacao_requisito where chave like '\_teste\_%';
  perform teste_assert_inst(v_n_total = 0, 'os requisitos fabricados pelo teste foram removidos');

  raise notice '--- 8. E A INSTALAÇÃO COMPLETA SE DECLARA COMPLETA ---';

  -- Com os fabricados fora, sobra o estado real deste banco: tudo presente exceto
  -- o requisito de COMPORTAMENTO, que nenhum CI pode satisfazer. Este assert é o
  -- que documenta essa fronteira em vez de deixá-la implícita.
  select string_agg(chave, ', ' order by chave) into v_ausentes
    from fn_instalacao_conferir() where not presente;

  -- DOIS requisitos de COMPORTAMENTO que nenhum CI satisfaz: o do n8n (o workflow reimportado) e, desde a 0216, o do
  -- PRIMEIRO ADMINISTRADOR (`administrador` vazia: o dono ainda não rodou fn_administrador_definir; sem isso a restrição
  -- por mandato esconde de todos o mandato sem membro). Ficam AUSENTES no replay de propósito: são o sinal positivo.
  perform teste_assert_inst(
    coalesce(v_ausentes, '') = 'custo_gravado_pelo_n8n, primeiro_administrador',
    'num banco recém-migrado faltam EXATAMENTE os dois requisitos de comportamento: o do n8n e o do primeiro administrador',
    format('ausentes: %s', coalesce(v_ausentes, '<nenhum>')));

  raise notice 'instalacao OK — catálogo conferido contra a realidade; sonda sobrevive ao objeto ausente; resumo fecha com a listagem; seed vazio distinguido de tabela ausente';
end $$;

drop function teste_assert_inst(boolean, text, text);
