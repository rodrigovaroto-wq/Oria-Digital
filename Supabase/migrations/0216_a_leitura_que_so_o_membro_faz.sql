-- =============================================================================
-- 0216 — A LEITURA QUE SÓ O MEMBRO FAZ: a RLS por mandato em toda tabela de dado do cliente
-- (Troca as 46 policies `using (true)` de dado do cliente por policies que perguntam a pertinência da 0215, restringe a
--  escrita direta do dial e dos catálogos ao administrador e o bucket `documentos` ao mandato, dá `caso_id` ao rastro de
--  auditoria e reemite fn_upsert_caso, o dial, os agregados de /autonomia, fn_falhas_abertas e a sonda. 51 `drop policy`
--  e 58 `create policy`: 46 de dado do cliente em `public`, 4 de catálogo/dial e a do bucket.)
--
-- O DEFEITO. Decisão D7 (Espec. 11 §7.1): "o mandato só é visto por quem trabalha nele". Medido em 27/10/2026 no banco
-- montado pelo run.sh na 0215: 49 tabelas, 65 policies de public, as de dado do cliente `using (true)` — todo usuário
-- logado lia e gravava todo mandato —, e storage.objects com `documentos_authenticated_all` (o bucket inteiro: o
-- balanço e o contrato social de qualquer mandato). A 0215 criou a pertinência (caso_membro, administrador,
-- fn_eh_membro) e NÃO tocou policy nenhuma; esta é a que liga.
--
-- A CAUSA do defeito de partida: a `0003` deixou um TODO de membership que nunca veio. Efeitos que a RLS cria e que
-- esta migration trata (porque, sem tratar, ela introduz defeito novo, calado):
--   1. fn_upsert_caso procura o caso por NOME. Com RLS em `caso`, quem não é membro não enxerga o mandato existente e
--      CRIAVA UM DUPLICADO com o mesmo nome. Chamadores (grep em 27/10/2026): o nó "Upsert Caso" do n8n
--      (service_role, auth.uid() nulo), portal/src/lib/envio-oficial.ts#obterCasoId (authenticated) e ~70 chamadas em
--      Supabase/test (superusuário). Todos passam pela MESMA função: corrigida nela, reemitida INTEIRA (memória
--      nunca-corrigir-funcao-por-replace). Ela agora é SECURITY DEFINER (ver 3) e a recusa do nome alheio devolve NULL
--      e grava evento (uma exceção desfaria a transação e o rastro junto).
--   2. `insert ... returning id` em `caso` checa a policy de SELECT na hora do insert, ANTES do gatilho AFTER INSERT da
--      0215 dar a pertinência ao criador: com RLS de SELECT o authenticated levaria 42501 ao criar o próprio mandato.
--      O id é gerado antes e o insert não tem RETURNING. Desde que fn_upsert_caso virou DEFINER isto deixou de ser
--      necessário (medido: com RETURNING de volta, 0 asserts reprovam — a função insere como o dono); fica como defesa,
--      barata, para o dia em que alguém a devolver a INVOKER (a sonda, tipo=definer, acusa isso).
--   3. O ORÁCULO DE NOMES. A versão anterior desta migration expunha fn_caso_id_do_nome (DEFINER, EXECUTE para o
--      authenticated): qualquer usuário logado perguntava "existe o mandato 'Projeto X'?" e recebia o ID — em M&A o
--      nome do alvo é informação privilegiada. Trocada por fn_caso_nome_existe, SEM EXECUTE para o authenticated; quem
--      a chama é fn_upsert_caso (por isso definer) e o gatilho de nome único. fn_upsert_caso continua sendo, por
--      natureza, um oráculo para quem a chama (null = nome alheio, id = próprio ou novo): o rastro
--      (`caso_acesso_recusado`, ator + nome pedido, só o administrador o lê) é a contenção, não a cura.
--   4. O DESVIO DE INGESTÃO. `caso_insert with check (true)` deixaria um não membro inserir direto
--      caso(nome='Projeto Y') — ou renomear o PRÓPRIO caso para 'Projeto Y' — e o n8n (busca por nome, `limit 1` sem
--      `order by`) poderia gravar os documentos de Y no caso dele. Gatilho trg_caso_nome_unico (BEFORE INSERT e UPDATE
--      OF nome, 23505) recusa nome já usado — SEM índice unique (decisão do dono ainda não tomada) e só quando há
--      identidade (auth.uid() não nulo): o n8n, o dono e os testes de superusuário não passam por ele.
--   5. A PROMOÇÃO AUTOMÁTICA DO DIAL SOBRE UM RECORTE. trg_auto_promover_dial (AFTER INSERT em decisao) →
--      fn_dial_auto_promover → fn_veredito_producao eram INVOKER: com a RLS o veredito GLOBAL passaria a ser calculado
--      só sobre os mandatos de QUEM DISPARA (o analista pelo portal: fn_revisar_documento, fn_decidir_pendencia,
--      fn_aceitar_extracao) e fn_mudar_dial muda o estágio para TODOS. Um analista com um recorte de concordância alta
--      promoveria o dial de todos, sem erro. fn_dial_auto_promover e fn_veredito_producao viram SECURITY DEFINER
--      (search_path fixo): o veredito global é o mesmo para todo chamador e a promoção independe de quem leu. Devolvem
--      só números e nomes de rubrica do catálogo, nunca linha de cliente; fn_veredito_producao com p_caso_id exige ser
--      membro. fn_mudar_dial continua INVOKER de propósito (definer deixaria qualquer usuário mudar o dial) e ganhou a
--      guarda de "0 linhas atualizadas" (42501): sem ela, o não administrador "mudava" o dial — a RLS recusava o UPDATE
--      calada, a função gravava o evento `mudanca_dial` e devolvia sucesso.
--   6. /autonomia (portal/src/app/autonomia/page.tsx): fn_golden_cobertura e fn_classe_contabil_concordancia davam
--      números do RECORTE do leitor sem aviso. Viram SECURITY DEFINER (só números); a segunda, com p_caso_id, só conta
--      o mandato de quem é membro. golden_rodada segue legível a todos.
--   7. execucao_falha.caso_id NULO (falha antes de o caso existir: Error Workflow, N8N/build-workflow-erros.mjs:40-46;
--      nó "Registrar Recusa", N8N/build-workflow.mjs:2563). `NULL in (...)` nunca é verdadeiro: a falha sumia para todos,
--      inclusive o administrador, e fn_falhas_abertas (invoker) voltava vazia — o /api/intake/status no "aguarde"
--      eterno que a 0108 corrigiu. A policy ganhou `or (caso_id is null and fn_eh_admin())` e fn_falhas_abertas virou
--      DEFINER: entrega a falha sem caso a quem a procura pelo NOME (é a única identidade que o intake tem) e a de caso
--      existente só ao membro. Quem adivinha o nome lê as falhas sem caso dele: decisão consciente.
--
-- O QUE ENTRA.
--   * fn_meus_casos() (SECURITY DEFINER, STABLE): os ids dos mandatos do usuário (todos, se administrador). Toda policy
--     de tabela com caso_id pergunta `caso_id in (select fn_meus_casos())`.
--   * Tabela INDIRETA pergunta ao PAI: `documento_versao_id in (select id from documento_versao)` etc. (documento_versao
--     → documento; campo_extraido e documento_fato → documento_versao; campo_classe_* → campo_extraido;
--     arquivo_oficial_registro/_lancamento_mes → arquivo_oficial; golden_documento/_campo/_rotulo → documento, que eles
--     têm por documento_id). A RLS do pai se compõe até o caso. Caminhos CONFERIDOS em pg_constraint no banco montado;
--     `arquivo_oficial` e `documento` têm `caso_id` direto. campo_classe_* usam `exists (... where ce.id = campo_extraido_id)`
--     (junção por PK), não `in (select id from campo_extraido)`: medido na tabela de DESEMPENHO.
--   * `caso`: SELECT/UPDATE/DELETE só membro; INSERT segue aberto (é como o portal cria o mandato; o gatilho da 0215
--     torna o criador membro; o de nome único recusa nome ocupado).
--   * Mesmo CONJUNTO de operações de antes: onde a policy era `for all` fica UMA `for all` (`<tabela>_por_mandato`;
--     o que o privilégio revoga, como delete em arquivo_oficial (0210), continua revogado); onde era só
--     select/insert/update (caso_pergunta, controlador, controlador_vinculo, entidade_controlador, perimetro,
--     campo_classe_*, golden_*) ficam as mesmas operações, com os mesmos NOMES — e a de reapontar de caso_pergunta
--     mantém a condição "mesma entidade, mesmo caso". O with check do UPDATE também exige o mandato: mover linha de X
--     para Y leva 42501.
--   * Dial e catálogos: estagio_autonomia, premissa_catalogo, golden_criterio e golden_rodada — leitura livre, ESCRITA SÓ
--     DO ADMINISTRADOR (policy). Antes: estagio_autonomia e premissa_catalogo eram `for all using (true)` (qualquer usuário
--     logado dava UPDATE no teto de autonomia sem passar por fn_mudar_dial — o teto é doutrina, só muda por migration),
--     golden_rodada tinha insert/update livres e golden_criterio não tinha RLS com INSERT/UPDATE/DELETE para o
--     authenticated (qualquer um baixava concordancia_minima). Quem escreve nelas (grep em 27/10/2026): portal/src só LÊ
--     (autonomia/page.tsx, export/route.ts); o n8n lê estagio_autonomia pela chave de serviço; a escrita é de
--     fn_mudar_dial (o administrador; a promoção automática passa por fn_dial_auto_promover, definer) e de
--     migrations/testes (superusuário). Nenhum uso legítimo do authenticated comum encontrado.
--   * storage.objects: `documentos_por_mandato` — só a pasta do caso (fn_caso_da_chave(name) in fn_meus_casos()). NÃO
--     usa storage.foldername (o replay local não a tem) e o cast para uuid é seguro (uma chave de forma estranha dava
--     erro na policy de SELECT e derrubava a listagem do bucket inteiro).
--   * evento_auditoria.caso_id (`references caso on delete set null`, índice): preenchido por gatilho BEFORE INSERT que
--     deriva de entidade_ref pelo FK (fn_caso_da_referencia, SECURITY INVOKER: o não membro deriva nulo e não forja
--     evento no mandato alheio; o rastro dele entra, sem caso, e só o administrador o lê). Formas levantadas por grep
--     nas 222 inserções: caso:, documento:, documento_versao:, campo_extraido:, reconciliacao:, pendencia:,
--     entidade:, controlador:<uuid>. Sem caso por natureza: estagio:, golden_rodada:, usuario:, caso_nome:<nome>,
--     `campo_extraido` sem id (backfills 0203/0204), documento_versao:null. Backfill do histórico pela MESMA função.
--     Leitura: membro do caso_id; caso_id nulo, só administrador. Insert segue aberto, exceto com caso_id explícito
--     de mandato alheio.
--   * Sonda: 125 requisitos (56 policy, 36 rls, 13 definer, 7 funcao, 5 execucao, 4 corpo, 2 gatilho, 1 coluna, 1
--     comportamento) e o tipo NOVO `definer` (pg_proc.prosecdef; 'sim' exige também search_path fixo em proconfig, 'nao'
--     exige INVOKER — o ALTER FUNCTION ... SECURITY DEFINER não muda uma letra do corpo, então o tipo `corpo` não o
--     vê). `rls` e `execucao` são da 0215. O requisito `rls` cobre TODA tabela de cliente que esta migration restringe
--     (a mesma lista que o teste tira do catálogo), o bucket (storage.objects) e os 4 catálogos de escrita restrita:
--     policy em tabela com a RLS desligada é texto no catálogo que o Postgres não aplica, e no projeto existente o
--     default privilege ainda concede ALL a anon/authenticated até 30/10/2026. O ramo `policy` ganhou o MARCADOR (a
--     expressão da policy tem de conter fn_meus_casos, fn_eh_admin ou o pai) e aceita `schema.tabela.policy` — sem isso
--     a policy `using (true)` de mesmo nome passaria por "presente" — e a policy do bucket (storage.objects).
--     `instalacao_cobertura` vai a 0216.
--   * Requisito `primeiro_administrador` (tipo comportamento, bloqueante): acusa `administrador` VAZIA — a 0216 esconde
--     de todos o mandato sem membro. No replay fica ausente, como custo_gravado_pelo_n8n (instalacao.test.sql aceita os
--     dois). Mora aqui e não na 0215 porque só a 0216 esconde mandato. É lido COMO O CHAMADOR: quem não é administrador
--     enxerga a tabela vazia pela RLS, então a conferência vale para o dono/CI (postgres), não para o authenticated.
--   * Os EXECUTE: as funções que esta migration tornou DEFINER (fn_veredito_producao, fn_classe_contabil_concordancia,
--     fn_golden_cobertura, fn_dial_auto_promover, fn_falhas_abertas, fn_upsert_caso) perdem o EXECUTE de PUBLIC/anon e
--     ficam com authenticated e service_role: definer executável pela chave pública é o clássico caminho de escalada, e
--     a guarda de p_caso_id deixa passar quem não tem identidade (auth.uid() nulo = n8n/dono).
--   * A GUARDA (sinal positivo, regra 7): a migration RECUSA aplicar (55000) se `administrador` está vazia e existe
--     usuário ATIVO em auth.users (fn_usuarios_ativos, 0215): com a restrição ligada o mandato novo — o que o n8n cria
--     nasce sem membro — sumiria para todos e ninguém o atribuiria, sem erro. A versão anterior olhava "caso sem
--     membro" e NÃO PROTEGIA NADA na ordem normal (a 0215 dá todo caso a todo usuário ativo: zero órfãos no dia);
--     medido: 2 asserts reprovam com ela de volta. No replay não trava (auth.users está vazia quando as migrations rodam; os
--     usuários dos testes nascem depois). Dentro de begin/commit: a recusa deixa o banco como estava.
--
-- EFEITOS QUE O DONO PRECISA SABER (regra 1: o que some não some calado).
--   a. Mandato criado pelo n8n (intake do portal) NASCE SEM MEMBRO: só o administrador o vê até alguém ser atribuído
--      (fn_membro_adicionar) ou o portal chamar fn_upsert_caso antes do envio. É a FATIA DE PORTAL; até ela, o
--      analista que sobe um arquivo de mandato novo não o vê. Isto já estava na 0215; a 0216 é o que o torna real.
--   b. Evento sem caso (estagio:..., golden_rodada:..., mandato excluído) só o administrador lê: a tela /autonomia
--      (portal/src/app/autonomia/page.tsx) deixa de listar o histórico de mudança de dial para quem não é administrador.
--   c. `caso.nome` NÃO é único e fn_upsert_caso busca por `limit 1` sem `order by`: com nomes duplicados já existentes o
--      n8n (vê todos) pega um qualquer e o authenticated pega um dos DELE. Não se cria unique aqui (decisão do dono).
--   d. O Supabase novo (30/10/2026) não concede EXECUTE/GRANT por default: as funções novas chamadas pelas policies
--      têm `grant execute ... to authenticated` explícito; as de gatilho, as de guarda e fn_caso_nome_existe, não.
--   e. Os 12 testes que rodavam como authenticated SEM identidade dependiam do `using (true)`; passam a chamar
--      teste_como_admin_0216()/teste_fim_admin_0216() em par (Supabase/test/suporte_authenticated.sql).
--   f. fn_upsert_caso, chamada por um não membro com o nome de um mandato existente, devolve NULL (antes: 42501). O
--      portal (obterCasoId) já trata `data` não-string como erro ("o banco não devolveu o id"): a mensagem é pobre e
--      melhorá-la é da fatia de portal.
--   g. Só o administrador altera o dial, o teto e os catálogos (golden_criterio, premissa_catalogo, golden_rodada,
--      estagio_autonomia) pela tabela; fn_mudar_dial por quem não é administrador leva 42501.
--
-- AINDA ABERTO (de propósito, com o porquê). Catálogos e globais seguem LEGÍVEIS ao authenticated: taxonomia_* (5),
-- premissa_catalogo, classe_contabil_catalogo, rubrica_classe, fato_tipo_catalogo, pergunta_catalogo, indice_macro_*
-- (3), instalacao_*, golden_rodada, golden_criterio, estagio_autonomia — não têm caso nem dado do cliente.
-- fn_golden_classe_a(p_caso_id nulo) segue INVOKER: chamada direta por um analista dá o número do recorte dele (a tela
-- /autonomia e o veredito global não a chamam por ele). `caso_insert with check (true)` segue aberto (é como o portal
-- cria o mandato). A premissa de que o nome do mandato é identidade segue sem unique no schema (decisão do dono).
--
-- DESEMPENHO (medido em 27/10/2026, banco com 53.893 campo_extraido, um caso com 50.000 deles, usuário membro desse
-- caso, `explain analyze`, duas rodadas):
--     forma                                                        count(*)      por documento_versao_id
--     using (true) (antes)                                          7,0 ms        0,37 ms
--     fn_eh_membro por linha, subconsulta correlata ao pai          3.450 ms      4,3 ms      (REPROVADA: >1 s)
--     cadeia + `caso_id in (select fn_meus_casos())` correlato      254 ms        1,0 ms
--     `in (select id from pai)` encadeado + fn_meus_casos (ESTA)    12,1 ms       1,35 ms
--   A forma escolhida: administrador 10 ms; quem não é membro 3,6 ms; campo_classe_sugerida (3 níveis) 26 ms;
--   reconciliacao 1 ms; evento_auditoria 2,8 ms. O que mata é a chamada POR LINHA: `in (select fn_meus_casos())` vira um
--   hashed SubPlan executado UMA vez. fn_eh_membro continua existindo (é a pergunta de um caso só) e o teste afirma
--   que as duas concordam.
--   REVISÃO (campo_classe_*): com 500.003 campo_extraido (450.000 no caso X, 50.000 no Y), 40.000 campo_classe_sugerida,
--   10.000 campo_classe_override e `set work_mem = '4MB'`, `explain analyze` (máquina com outra carga em paralelo):
--     forma da policy de leitura                  count(sugerida)  count(override)  um campo_extraido_id
--     `in (select id from campo_extraido)` (ERA)    305.802 ms      4.799 ms         254 ms   (membro de X; 1 rodada)
--     `exists (... where ce.id = campo_extraido_id)` (ESTA), membro de X:  482-560 ms   95-121 ms   2,3 ms
--     idem, administrador:                                                  485-559 ms   102 ms     2,7-2,9 ms
--     idem, membro de Y (50.000 campos):                                    456-498 ms   94-100 ms   2,1-2,3 ms
--   A forma antiga materializava o campo_extraido inteiro filtrado pela RLS (três níveis de pai) para cada consulta; com
--   4 MB de work_mem isso foi para disco. A junção por PK volta a ser por linha de campo_classe_*.
--
-- O QUE FICA PARA O DONO, À MÃO NO SUPABASE: (1) ANTES de aplicar, no SQL Editor:
--     select fn_administrador_definir('<seu e-mail>', true);
--   (a migration recusa sem isso se houver usuário ativo); (2) aplicar (Supabase/README.md); (3) conferir
--   `select chave, detalhe from fn_instalacao_conferir() where migration = '0216' and not presente;` — ZERO linhas (o
--   `primeiro_administrador` some quando o passo 1 foi feito); (4) quantos mandatos reais ficaram sem membro:
--   select count(*) from caso c where not exists (select 1 from caso_membro m where m.caso_id = c.id); — o administrador
--   os vê e os atribui. Migration escrita não é migration aplicada: quem responde é a sonda, contra o banco em que se
--   está conectado.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2), medida em 27/10/2026 sobre
-- Supabase/test/rls_por_mandato.test.sql, cópia do teste com o assert em `raise notice` (volta a `raise exception` no
-- arquivo commitado) sobre cópias do banco montado, UMA correção desligada por vez. Sem desligar nada: 0 dos 94 asserts
-- reprovam e os 94 aparecem no log. Com a correção desligada, reprovam (os marcados "aborta" morrem num erro de
-- execução antes de chegar aos asserts seguintes — o teste reprova do mesmo jeito):
--     policy documento (direta) com using (true) .......................... 13 dos 94 asserts (aborta no 40º)
--     policy campo_extraido (indireta, 2 níveis) com using (true) ......... 9 dos 94 asserts
--     policy documento_versao (indireta, pai da cadeia) com using (true) .. 9 dos 94 asserts
--     policy caso_select com using (true) ................................. 6 dos 94 asserts (aborta no 45º)
--     policy caso_update com using (true) ................................. 4 dos 94 asserts
--     policy caso_delete com using (true) ................................. 4 dos 94 asserts
--     policy evento_auditoria_read com using (true) ....................... 11 dos 94 asserts
--     policy evento_auditoria_read lendo também o evento sem caso ......... 7 dos 94 asserts
--     policy evento_auditoria_insert com check (true) ..................... 5 dos 94 asserts
--     policy golden_campo_read com using (true) ........................... 7 dos 94 asserts
--     policy golden_documento_read com using (true) ....................... 7 dos 94 asserts
--     policy caso_pergunta_read com using (true) .......................... 7 dos 94 asserts
--     storage.objects de volta ao bucket inteiro .......................... 8 dos 94 asserts
--     gatilho trg_evento_caso_id desabilitado ............................. 10 dos 94 asserts
--     fn_caso_da_referencia devolvendo nulo ............................... 8 dos 94 asserts
--     fn_meus_casos devolvendo todos os casos ............................. 3 dos 94 asserts (aborta no 29º)
--     fn_upsert_caso sem a guarda de nome alheio .......................... 6 dos 94 asserts
--     fn_upsert_caso com insert ... returning (sem gerar o id antes) ...... 0 dos 94 asserts (a função é DEFINER: o RETURNING
--                                                                                  não toca a RLS; já não é defeito)
--     fn_0216_exige_administrador sem o raise ............................. 2 dos 94 asserts
--     sonda sem o marcador/storage no ramo policy ......................... 4 dos 94 asserts
--     tabela de cliente NOVA com policy using (true) e sem dados .......... 5 dos 94 asserts
--   Correções da revisão independente (27/10/2026):
--     guarda de administrador na formulação ANTIGA (caso órfão) ........... 2 dos 94 asserts
--     fn_caso_nome_existe com EXECUTE para authenticated (oráculo) ........ 4 dos 94 asserts
--     fn_upsert_caso levantando 42501 em vez de devolver null + evento .... 3 dos 94 asserts
--     fn_upsert_caso sem gravar o evento da recusa ........................ 2 dos 94 asserts
--     gatilho trg_caso_nome_unico desabilitado ............................ 6 dos 94 asserts
--     gatilho de nome único só em INSERT (sem o rename) ................... 3 dos 94 asserts
--     gatilho de nome único só em UPDATE (sem o insert direto) ............ 1 dos 94 asserts
--     execucao_falha_por_mandato sem o ramo de caso_id NULO ............... 4 dos 94 asserts
--     fn_falhas_abertas de volta a INVOKER ................................ 4 dos 94 asserts
--     fn_falhas_abertas sem o ramo de caso_id NULO ........................ 1 dos 94 asserts
--     fn_dial_auto_promover de volta a INVOKER (o analista promove pelo
--       recorte dele) ..................................................... 4 dos 94 asserts
--     fn_veredito_producao sem a guarda de p_caso_id ...................... 4 dos 94 asserts
--     fn_veredito_producao de volta a INVOKER ............................. 4 dos 94 asserts
--     fn_classe_contabil_concordancia sem a guarda de p_caso_id ........... 4 dos 94 asserts
--     fn_classe_contabil_concordancia de volta a INVOKER .................. 4 dos 94 asserts
--     fn_golden_cobertura de volta a INVOKER .............................. 4 dos 94 asserts
--     fn_mudar_dial sem a guarda de 0 linhas .............................. 1 dos 94 asserts
--     estagio_autonomia_write com using (true) ............................ 6 dos 94 asserts
--     premissa_catalogo_write com using (true) ............................ 4 dos 94 asserts
--     golden_criterio sem RLS ............................................. 10 dos 94 asserts
--     golden_criterio_write com using (true) .............................. 9 dos 94 asserts
--     golden_rodada insert/update com true ................................ 5 dos 94 asserts
--     revoke de PUBLIC/anon das funções definer removido .................. 1 dos 94 asserts
--     sonda `definer` que devolve sempre presente ......................... 3 dos 94 asserts
--     sonda `rls` que devolve sempre presente ............................. 1 dos 94 asserts
--     requisito rls_pendencia removido do catálogo ........................ 1 dos 94 asserts
--     requisito primeiro_administrador removido ........................... 1 dos 94 asserts
--   (Medido sobre o banco "molde" = as migrations até a 0214 + 0215 + 0216 + suporte; neste molde o assert "A lê todo
--   catálogo global" reprova SEMPRE — os seeds de indice_macro vêm de outro teste do run.sh — e foi descontado de todo
--   número acima; no run.sh completo ele passa e o log mostra os 94 ok.)

begin;

-- -----------------------------------------------------------------------------
-- 1. O SINAL POSITIVO (regra 7): recusa aplicar com `administrador` vazia e usuário ativo em auth.users. A função
--    existe para o teste a chamar sobre um arranjo montado; a migration a chama logo abaixo. No replay as migrations
--    rodam sobre auth.users vazia, então nada trava.
--    O `begin`/`commit` desta migration faz a recusa deixar o banco como estava (psql -f sem ON_ERROR_STOP seguiria).
-- -----------------------------------------------------------------------------
create or replace function fn_0216_exige_administrador()
returns void
language plpgsql
as $$
declare
  v_ativos bigint;
begin
  if exists (select 1 from administrador) then
    return;
  end if;
  -- A GUARDA ANTERIOR olhava "caso sem nenhum membro" e NÃO PROTEGIA NADA NA ORDEM NORMAL: a 0215 dá membro de todo
  -- caso existente a todo usuário ativo, então no dia de aplicar não há órfão — e o mandato que o n8n cria DEPOIS
  -- nasce sem membro e sem ninguém que o enxergue. O que a 0216 estraga é "ninguém atribui nem vê": sem
  -- administrador, a restrição liga e ninguém tem como corrigi-la sem SQL. Por isso a conta é de USUÁRIOS ATIVOS
  -- (fn_usuarios_ativos, 0215): havendo gente para quem o mandato vai sumir, recusa. No replay (run.sh, e2e) as
  -- migrations rodam sobre auth.users VAZIA — os usuários dos testes nascem depois —, então a contagem dá zero e
  -- nada trava (medido em 27/10/2026: 0 usuários no banco montado só pelas migrations).
  select count(*) into v_ativos from fn_usuarios_ativos();
  if v_ativos > 0 then
    raise exception '0216 recusada: ninguém é administrador e há % usuário(s) ativo(s) — com a restrição por mandato ligada o mandato novo (o que o n8n cria nasce sem membro) sumiria para todos e ninguém o atribuiria, sem erro. Rode ANTES, no SQL Editor: select fn_administrador_definir(''<seu e-mail>'', true);', v_ativos
      using errcode = '55000';
  end if;
end;
$$;
comment on function fn_0216_exige_administrador() is
  'Guarda da 0216: levanta 55000 se administrador está vazia E existe usuário ativo em auth.users (fn_usuarios_ativos). Só postgres/service_role. 0216.';
revoke execute on function fn_0216_exige_administrador() from public, anon, authenticated;
grant execute on function fn_0216_exige_administrador() to service_role;

select fn_0216_exige_administrador();

-- -----------------------------------------------------------------------------
-- 2. AS FUNÇÕES QUE AS POLICIES CHAMAM
-- -----------------------------------------------------------------------------
-- fn_meus_casos(): os ids dos mandatos do usuário do jwt (todos, se administrador). É o que a policy pergunta como
-- `caso_id in (select fn_meus_casos())`: um SubPlan hashed, executado UMA vez por comando, e não uma chamada por linha
-- (medido: ver cabeçalho). SECURITY DEFINER pelo mesmo motivo de fn_eh_membro (ler caso_membro/administrador sem
-- reentrar na RLS). auth.uid() nulo => nenhum caso. Tem de concordar com fn_eh_membro; o teste afirma a concordância.
create or replace function fn_meus_casos()
returns setof uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select c.id from public.caso c
   where exists (select 1 from public.administrador where usuario_id = auth.uid())
  union
  select m.caso_id from public.caso_membro m where m.usuario_id = auth.uid();
$$;
comment on function fn_meus_casos() is
  'Ids dos mandatos do usuário do jwt (todos, se administrador). Base de toda policy por mandato (caso_id in (select fn_meus_casos())). Concorda com fn_eh_membro. auth.uid() nulo => vazio. 0216.';

-- fn_caso_nome_existe(): "já existe mandato com este nome?" INDEPENDENTE da RLS, e só para o banco usar por dentro:
-- fn_upsert_caso (que distingue "não existe" de "existe e eu não o vejo") e o gatilho de nome único. SEM EXECUTE para o
-- authenticated (revoke abaixo): exposta, ela seria um ORÁCULO DE NOMES — em M&A o nome do alvo é informação
-- privilegiada, e perguntar "existe mandato 'Projeto X'?" para qualquer usuário logado é vazá-lo. A versão anterior
-- (fn_caso_id_do_nome) devolvia o ID e tinha EXECUTE para o authenticated; foi trocada antes de qualquer aplicação.
-- p_exceto: o próprio caso, no gatilho de rename (renomear para o nome que ele já tem não conflita consigo).
create or replace function fn_caso_nome_existe(p_nome text, p_exceto uuid default null)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.caso where nome = p_nome and (p_exceto is null or id <> p_exceto));
$$;
comment on function fn_caso_nome_existe(text, uuid) is
  'Existe mandato com este nome, sem passar pela RLS? Só para dentro do banco (fn_upsert_caso e o gatilho de nome único): o authenticated NÃO executa — seria oráculo de nomes. 0216.';

-- fn_caso_da_chave(): o caso de um objeto do bucket `documentos`. A chave é <caso_id>/<hash><ext> (N8N/lib/hash.mjs
-- #chaveDoOriginal). NÃO usa storage.foldername: o replay local (run.sh, Verificação) não tem essa função, e o cast
-- direto para uuid levantaria erro numa policy de SELECT se algum objeto tivesse outra forma de pasta — a listagem
-- inteira do bucket cairia. Forma estranha => nulo => ninguém vê o objeto (só o service_role).
create or replace function fn_caso_da_chave(p_name text)
returns uuid
language sql
immutable
as $$
  select case when p_name ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
              then substr(p_name, 1, 36)::uuid end;
$$;
comment on function fn_caso_da_chave(text) is
  'O caso_id da primeira pasta da chave de um objeto do bucket documentos (<caso_id>/<hash><ext>); nulo se a chave não tem essa forma. 0216.';

-- fn_caso_da_referencia(): o caso a que uma `entidade_ref` de evento_auditoria se refere, pelo FK. SECURITY INVOKER de
-- propósito: a RLS vale. Um usuário que NÃO é membro e grava um evento sobre documento:<uuid> alheio não enxerga o
-- documento, deriva nulo, e o evento vira "só administrador" em vez de entrar forjado no rastro do mandato alheio.
-- Formas que existem no código (levantadas por grep nas 222 inserções): caso:, documento:, documento_versao:,
-- reconciliacao:, pendencia:, entidade:, controlador:, campo_extraido:<uuid>; e SEM caso por natureza: estagio:,
-- golden_rodada:, usuario:, caso_nome:<nome>, `campo_extraido` sem id (backfills de 0203/0204), documento_versao:null.
create or replace function fn_caso_da_referencia(p_ref text)
returns uuid
language plpgsql
stable
as $$
declare
  v_tipo text := split_part(coalesce(p_ref, ''), ':', 1);
  v_txt  text := split_part(coalesce(p_ref, ''), ':', 2);
  v_id   uuid;
  v_caso uuid;
begin
  if v_txt !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  v_id := v_txt::uuid;
  if    v_tipo = 'caso'          then select id into v_caso from caso where id = v_id;
  elsif v_tipo = 'documento'     then select caso_id into v_caso from documento where id = v_id;
  elsif v_tipo = 'documento_versao' then
    select d.caso_id into v_caso from documento_versao dv join documento d on d.id = dv.documento_id where dv.id = v_id;
  elsif v_tipo = 'campo_extraido' then
    select d.caso_id into v_caso from campo_extraido c
      join documento_versao dv on dv.id = c.documento_versao_id
      join documento d on d.id = dv.documento_id where c.id = v_id;
  elsif v_tipo = 'reconciliacao' then select caso_id into v_caso from reconciliacao where id = v_id;
  elsif v_tipo = 'pendencia'     then select caso_id into v_caso from pendencia where id = v_id;
  elsif v_tipo = 'entidade'      then select caso_id into v_caso from entidade where id = v_id;
  elsif v_tipo = 'controlador'   then select caso_id into v_caso from controlador where id = v_id;
  end if;
  return v_caso;
end;
$$;
comment on function fn_caso_da_referencia(text) is
  'O caso de uma entidade_ref de evento_auditoria, pelo FK (nulo se a forma não tem caso). SECURITY INVOKER: a RLS vale e o não membro deriva nulo. 0216.';

create or replace function fn_trg_evento_caso_id()
returns trigger
language plpgsql
as $$
begin
  if new.caso_id is null then
    new.caso_id := fn_caso_da_referencia(new.entidade_ref);
  end if;
  return new;
end;
$$;
comment on function fn_trg_evento_caso_id() is
  'Gatilho BEFORE INSERT de evento_auditoria: preenche caso_id derivando de entidade_ref quando quem insere não o informou. 0216.';

-- -----------------------------------------------------------------------------
-- 3. evento_auditoria.caso_id: a coluna, o índice, o gatilho e o backfill do histórico pela MESMA função.
--    ON DELETE SET NULL: excluir o mandato (fn_excluir_caso) não apaga o rastro, que passa a ser só do administrador.
-- -----------------------------------------------------------------------------
alter table evento_auditoria add column caso_id uuid null references caso(id) on delete set null;
create index idx_evento_auditoria_caso on evento_auditoria(caso_id);
comment on column evento_auditoria.caso_id is
  'O mandato a que o evento pertence (0216), derivado de entidade_ref pelo gatilho. Nulo = sem mandato (estagio:, golden_rodada:, caso_nome:...) ou mandato excluído: só o administrador lê.';

create trigger trg_evento_caso_id
  before insert on evento_auditoria
  for each row execute function fn_trg_evento_caso_id();

update evento_auditoria set caso_id = fn_caso_da_referencia(entidade_ref) where caso_id is null;

-- -----------------------------------------------------------------------------
-- 4. fn_upsert_caso, REEMITIDA INTEIRA (a da 0207 + a guarda), agora SECURITY DEFINER. Chamadores (grep em 27/10/2026): o
--    nó "Upsert Caso" do n8n (service_role, auth.uid() nulo: comportamento IDÊNTICO ao da 0207),
--    portal/src/lib/envio-oficial.ts#obterCasoId (authenticated, p_ator 'portal:navegador') e ~70 chamadas em
--    Supabase/test/*.test.sql e fixtures (superusuário).
--    Três efeitos da RLS que a função trata: (1) o não membro não enxergava o caso e CRIAVA UM DUPLICADO com o mesmo
--    nome — agora a busca é pelos casos que ELE vê (fn_meus_casos) e, não achando, fn_caso_nome_existe diz que o nome é
--    de um mandato alheio e a função NÃO cria; (2) `insert ... returning` em caso com RLS de SELECT checa a policy ANTES
--    do gatilho do criador (AFTER INSERT) dar a pertinência: falharia com 42501 — o id é gerado antes e não há
--    RETURNING; (3) fn_caso_nome_existe não é executável pelo authenticated (oráculo de nomes), então quem a chama é a
--    própria fn_upsert_caso, que por isso roda como o dono (SECURITY DEFINER, search_path fixo): auth.uid() continua
--    sendo o do jwt, e o que o chamador ENXERGA é decidido por fn_meus_casos, não pela RLS.
--    A RECUSA DEVOLVE NULL E GRAVA EVENTO, em vez de levantar 42501 (como a versão anterior): uma exceção desfaz a
--    transação, e com ela o evento — a tentativa de abrir o mandato alheio não deixaria rastro nenhum. O evento
--    `caso_acesso_recusado` (ator usuario:<uuid>, entidade_ref caso_nome:<nome>, sem caso_id: só o administrador o lê)
--    é o rastro. O portal (obterCasoId) já trata `data` não-string como erro ("o banco não devolveu o id"); a mensagem
--    dele é pobre e melhorá-la é da fatia de portal. fn_upsert_caso continua sendo, por natureza, um oráculo de
--    existência para quem a chama (devolver null no nome alheio e um id no próprio/novo diz que o nome existe): o rastro
--    é a contenção, não a cura.
--    `caso.nome` NÃO é único (schema.sql) e a busca é `limit 1` sem `order by`: com nomes duplicados já existentes, o
--    n8n (service_role, vê todos) pega um qualquer e o authenticated pega um dos DELE. Não se cria unique aqui
--    (decisão do dono); o gatilho trg_caso_nome_unico (abaixo) só impede que o authenticated CRIE novos duplicados.
-- -----------------------------------------------------------------------------
create or replace function fn_upsert_caso(p_nome text, p_ator text default 'sistema:n8n')
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if p_ator not in ('sistema:n8n', 'portal:navegador') then
    raise exception 'fn_upsert_caso: ator % fora da lista (sistema:n8n, portal:navegador)', p_ator;
  end if;
  select id into v_id from caso
   where nome = p_nome and (auth.uid() is null or id in (select fn_meus_casos()))
   limit 1;
  if v_id is null then
    if auth.uid() is not null and fn_caso_nome_existe(p_nome, null) then
      insert into evento_auditoria (ator, acao, entidade_ref, depois)
        values ('usuario:' || auth.uid(), 'caso_acesso_recusado', 'caso_nome:' || p_nome,
                jsonb_build_object('via', p_ator));
      return null;
    end if;
    v_id := gen_random_uuid();
    insert into caso (id, nome) values (v_id, p_nome);
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_ator, 'caso_criado', 'caso:'||v_id, jsonb_build_object('nome', p_nome));
  end if;
  return v_id;
end;
$$;
comment on function fn_upsert_caso(text, text) is
  'Reusa o mandato pelo nome exato ENTRE OS QUE O CHAMADOR ENXERGA (fn_meus_casos; sem identidade — n8n — vê todos) ou cria. Nome de mandato alheio: NÃO cria duplicado, devolve NULL e grava caso_acesso_recusado (uma exceção desfaria o rastro). SECURITY DEFINER com search_path fixo. 0216 (sobre a 0207).';

-- O GATILHO DE NOME ÚNICO PARA O AUTHENTICATED. `caso_insert with check (true)` deixa um não membro inserir direto
-- caso(nome = 'Projeto Y') — ou renomear o PRÓPRIO caso para 'Projeto Y' — e o n8n (busca por nome, `limit 1` sem
-- order by) pode então gravar os documentos de Y no caso dele. Sem índice unique (decisão do dono ainda não tomada):
-- gatilho BEFORE INSERT / UPDATE OF nome, só quando há identidade (auth.uid() não nulo: o n8n, o dono e os testes de
-- superusuário não passam por ele). SECURITY DEFINER para enxergar o nome alheio; um gatilho não exige EXECUTE do
-- chamador. A mensagem é a mesma para qualquer nome ocupado (23505) — dizer "existe" já é o que a unicidade diz.
create or replace function fn_trg_caso_nome_unico()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is not null
     and (tg_op = 'INSERT' or new.nome is distinct from old.nome)
     and fn_caso_nome_existe(new.nome, case when tg_op = 'UPDATE' then new.id end) then
    raise exception 'já existe um mandato com este nome; use outro ou peça acesso ao administrador' using errcode = '23505';
  end if;
  return new;
end;
$$;
comment on function fn_trg_caso_nome_unico() is
  'Gatilho de caso (BEFORE INSERT e UPDATE OF nome): com identidade (auth.uid() não nulo), recusa (23505) nome já usado por outro mandato. Sem unique no schema (decisão do dono pendente). 0216.';
create trigger trg_caso_nome_unico
  before insert or update of nome on caso
  for each row execute function fn_trg_caso_nome_unico();

-- -----------------------------------------------------------------------------
-- 5. AS POLICIES. Cada `drop` tem de achar a policy que existe (sem `if exists`): policy que a migration não
--    encontra é policy que ela não trocou. Tabelas que eram `for all using (true)` ficam com UMA policy `for all`
--    (mesmo conjunto de operações; o que o privilégio revoga — delete em arquivo_oficial, 0210 — continua revogado).
--    Tabelas append-only ou sem update (caso_pergunta, controlador, campo_classe_*, golden_*) mantêm as operações e os
--    nomes que tinham, só restritas ao membro. Tabela indireta pergunta ao PAI (`x_id in (select id from pai)`): a RLS
--    do pai se compõe até o caso, e o planner faz uma junção hashed (medido: ver cabeçalho) em vez de uma subconsulta
--    correlata por linha (3,4 s para 54 mil campos).
-- -----------------------------------------------------------------------------
drop policy arquivo_oficial_authenticated_all on arquivo_oficial;
create policy arquivo_oficial_por_mandato on arquivo_oficial for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy caso_apresentacao_campo_authenticated_all on caso_apresentacao_campo;
create policy caso_apresentacao_campo_por_mandato on caso_apresentacao_campo for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy caso_linha_premissa_authenticated_all on caso_linha_premissa;
create policy caso_linha_premissa_por_mandato on caso_linha_premissa for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy caso_modelagem_authenticated_all on caso_modelagem;
create policy caso_modelagem_por_mandato on caso_modelagem for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy caso_premissa_authenticated_all on caso_premissa;
create policy caso_premissa_por_mandato on caso_premissa for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy checklist_item_status_authenticated_all on checklist_item_status;
create policy checklist_item_status_por_mandato on checklist_item_status for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy decisao_authenticated_all on decisao;
create policy decisao_por_mandato on decisao for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy documento_authenticated_all on documento;
create policy documento_por_mandato on documento for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy entidade_authenticated_all on entidade;
create policy entidade_por_mandato on entidade for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy execucao_falha_authenticated_all on execucao_falha;
-- `caso_id` NULO é falha de ANTES de o caso existir (Error Workflow, N8N/build-workflow-erros.mjs:40-46; nó "Registrar
-- Recusa", N8N/build-workflow.mjs:2563): `NULL in (...)` nunca é verdadeiro, então sem o `or` ela sumia para todos,
-- inclusive o administrador, e /api/intake/status voltava ao "aguarde" eterno que a 0108 corrigiu. Só o administrador a
-- lê pela tabela; quem subiu o arquivo a lê por fn_falhas_abertas (abaixo), pelo NOME.
create policy execucao_falha_por_mandato on execucao_falha for all to authenticated
  using (caso_id in (select fn_meus_casos()) or (caso_id is null and fn_eh_admin()))
  with check (caso_id in (select fn_meus_casos()) or (caso_id is null and fn_eh_admin()));

drop policy lote_execucao_authenticated_all on lote_execucao;
create policy lote_execucao_por_mandato on lote_execucao for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy pendencia_authenticated_all on pendencia;
create policy pendencia_por_mandato on pendencia for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy periodo_authenticated_all on periodo;
create policy periodo_por_mandato on periodo for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy reconciliacao_authenticated_all on reconciliacao;
create policy reconciliacao_por_mandato on reconciliacao for all to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy documento_versao_authenticated_all on documento_versao;
create policy documento_versao_por_mandato on documento_versao for all to authenticated
  using (documento_id in (select id from documento))
  with check (documento_id in (select id from documento));

drop policy campo_extraido_authenticated_all on campo_extraido;
create policy campo_extraido_por_mandato on campo_extraido for all to authenticated
  using (documento_versao_id in (select id from documento_versao))
  with check (documento_versao_id in (select id from documento_versao));

drop policy documento_fato_authenticated_all on documento_fato;
create policy documento_fato_por_mandato on documento_fato for all to authenticated
  using (documento_versao_id in (select id from documento_versao))
  with check (documento_versao_id in (select id from documento_versao));

drop policy arquivo_oficial_registro_authenticated_all on arquivo_oficial_registro;
create policy arquivo_oficial_registro_por_mandato on arquivo_oficial_registro for all to authenticated
  using (arquivo_oficial_id in (select id from arquivo_oficial))
  with check (arquivo_oficial_id in (select id from arquivo_oficial));

drop policy arquivo_oficial_lancamento_mes_authenticated_all on arquivo_oficial_lancamento_mes;
create policy arquivo_oficial_lancamento_mes_por_mandato on arquivo_oficial_lancamento_mes for all to authenticated
  using (arquivo_oficial_id in (select id from arquivo_oficial))
  with check (arquivo_oficial_id in (select id from arquivo_oficial));

drop policy caso_pergunta_read on caso_pergunta;
create policy caso_pergunta_read on caso_pergunta for select to authenticated using (caso_id in (select fn_meus_casos()));

drop policy caso_pergunta_insert on caso_pergunta;
create policy caso_pergunta_insert on caso_pergunta for insert to authenticated with check (caso_id in (select fn_meus_casos()));

drop policy caso_pergunta_reapontar on caso_pergunta;
create policy caso_pergunta_reapontar on caso_pergunta for update to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos())
        and entidade_id is not null
        and exists (select 1 from entidade e where e.id = caso_pergunta.entidade_id and e.caso_id = caso_pergunta.caso_id));

drop policy controlador_read on controlador;
create policy controlador_read on controlador for select to authenticated using (caso_id in (select fn_meus_casos()));

drop policy controlador_insert on controlador;
create policy controlador_insert on controlador for insert to authenticated with check (caso_id in (select fn_meus_casos()));

drop policy controlador_vinculo_read on controlador_vinculo;
create policy controlador_vinculo_read on controlador_vinculo for select to authenticated using (caso_id in (select fn_meus_casos()));

drop policy controlador_vinculo_insert on controlador_vinculo;
create policy controlador_vinculo_insert on controlador_vinculo for insert to authenticated with check (caso_id in (select fn_meus_casos()));

drop policy controlador_vinculo_update on controlador_vinculo;
create policy controlador_vinculo_update on controlador_vinculo for update to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy entidade_controlador_read on entidade_controlador;
create policy entidade_controlador_read on entidade_controlador for select to authenticated using (caso_id in (select fn_meus_casos()));

drop policy entidade_controlador_insert on entidade_controlador;
create policy entidade_controlador_insert on entidade_controlador for insert to authenticated with check (caso_id in (select fn_meus_casos()));

drop policy entidade_controlador_update on entidade_controlador;
create policy entidade_controlador_update on entidade_controlador for update to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy perimetro_read on perimetro;
create policy perimetro_read on perimetro for select to authenticated using (caso_id in (select fn_meus_casos()));

drop policy perimetro_insert on perimetro;
create policy perimetro_insert on perimetro for insert to authenticated with check (caso_id in (select fn_meus_casos()));

drop policy perimetro_update on perimetro;
create policy perimetro_update on perimetro for update to authenticated
  using (caso_id in (select fn_meus_casos()))
  with check (caso_id in (select fn_meus_casos()));

drop policy campo_classe_override_read on campo_classe_override;
create policy campo_classe_override_read on campo_classe_override for select to authenticated
  using (exists (select 1 from campo_extraido ce where ce.id = campo_extraido_id));

drop policy campo_classe_override_insert on campo_classe_override;
create policy campo_classe_override_insert on campo_classe_override for insert to authenticated
  with check (exists (select 1 from campo_extraido ce where ce.id = campo_extraido_id));

drop policy campo_classe_sugerida_read on campo_classe_sugerida;
create policy campo_classe_sugerida_read on campo_classe_sugerida for select to authenticated
  using (exists (select 1 from campo_extraido ce where ce.id = campo_extraido_id));

drop policy campo_classe_sugerida_insert on campo_classe_sugerida;
create policy campo_classe_sugerida_insert on campo_classe_sugerida for insert to authenticated
  with check (exists (select 1 from campo_extraido ce where ce.id = campo_extraido_id));

drop policy golden_documento_read on golden_documento;
create policy golden_documento_read on golden_documento for select to authenticated using (documento_id in (select id from documento));

drop policy golden_documento_insert on golden_documento;
create policy golden_documento_insert on golden_documento for insert to authenticated with check (documento_id in (select id from documento));

drop policy golden_campo_read on golden_campo;
create policy golden_campo_read on golden_campo for select to authenticated using (documento_id in (select id from documento));

drop policy golden_campo_insert on golden_campo;
create policy golden_campo_insert on golden_campo for insert to authenticated with check (documento_id in (select id from documento));

drop policy golden_rotulo_read on golden_rotulo;
create policy golden_rotulo_read on golden_rotulo for select to authenticated using (documento_id in (select id from documento));

drop policy golden_rotulo_insert on golden_rotulo;
create policy golden_rotulo_insert on golden_rotulo for insert to authenticated with check (documento_id in (select id from documento));

drop policy caso_authenticated_all on caso;
create policy caso_select on caso for select to authenticated using (id in (select fn_meus_casos()));
-- INSERT continua aberto: é como o portal cria o mandato (fn_upsert_caso); o gatilho da 0215 torna o criador membro.
create policy caso_insert on caso for insert to authenticated with check (true);
create policy caso_update on caso for update to authenticated
  using (id in (select fn_meus_casos())) with check (id in (select fn_meus_casos()));
create policy caso_delete on caso for delete to authenticated using (id in (select fn_meus_casos()));

drop policy evento_auditoria_read on evento_auditoria;
create policy evento_auditoria_read on evento_auditoria for select to authenticated
  using (caso_id in (select fn_meus_casos()) or (caso_id is null and fn_eh_admin()));
drop policy evento_auditoria_insert on evento_auditoria;
create policy evento_auditoria_insert on evento_auditoria for insert to authenticated
  with check (caso_id is null or caso_id in (select fn_meus_casos()));

-- Catálogos e dial: leitura livre, ESCRITA SÓ DO ADMINISTRADOR. Antes, `estagio_autonomia` e `premissa_catalogo` eram
-- `for all using (true)` e `golden_rodada` tinha insert/update livres: qualquer usuário logado dava UPDATE no teto de
-- autonomia sem passar por fn_mudar_dial (o teto é doutrina e só muda por migration). golden_criterio nem tinha RLS e
-- o authenticated tinha INSERT/UPDATE/DELETE (qualquer um baixava concordancia_minima). Quem escreve nelas (grep em
-- 27/10/2026): portal/src só LÊ (autonomia/page.tsx, export/route.ts); o n8n lê estagio_autonomia pela chave de serviço;
-- a escrita é de fn_mudar_dial (invoker: o administrador pelo portal/SQL; a promoção automática passa por
-- fn_dial_auto_promover, definer, abaixo) e de migrations/testes (superusuário). Nenhum uso legítimo do authenticated
-- comum foi encontrado.
drop policy estagio_autonomia_authenticated_all on estagio_autonomia;
create policy estagio_autonomia_read on estagio_autonomia for select to authenticated using (true);
create policy estagio_autonomia_write on estagio_autonomia for all to authenticated
  using (fn_eh_admin()) with check (fn_eh_admin());

drop policy premissa_catalogo_authenticated_all on premissa_catalogo;
create policy premissa_catalogo_read on premissa_catalogo for select to authenticated using (true);
create policy premissa_catalogo_write on premissa_catalogo for all to authenticated
  using (fn_eh_admin()) with check (fn_eh_admin());

drop policy golden_rodada_insert on golden_rodada;
create policy golden_rodada_insert on golden_rodada for insert to authenticated with check (fn_eh_admin());
drop policy golden_rodada_update on golden_rodada;
create policy golden_rodada_update on golden_rodada for update to authenticated
  using (fn_eh_admin()) with check (fn_eh_admin());

alter table golden_criterio enable row level security;
create policy golden_criterio_read on golden_criterio for select to authenticated using (true);
create policy golden_criterio_write on golden_criterio for all to authenticated
  using (fn_eh_admin()) with check (fn_eh_admin());

drop policy documentos_authenticated_all on storage.objects;
create policy documentos_por_mandato on storage.objects for all to authenticated
  using (bucket_id = 'documentos' and public.fn_caso_da_chave(name) in (select public.fn_meus_casos()))
  with check (bucket_id = 'documentos' and public.fn_caso_da_chave(name) in (select public.fn_meus_casos()));

-- -----------------------------------------------------------------------------
-- 5b. O DIAL, OS AGREGADOS GLOBAIS E AS FALHAS SEM CASO — o que a RLS por mandato quebraria em silêncio.
--    (1) PROMOÇÃO AUTOMÁTICA. trg_auto_promover_dial (AFTER INSERT em decisao) -> fn_dial_auto_promover ->
--    fn_veredito_producao são INVOKER: com a RLS o veredito GLOBAL passaria a ser calculado só sobre os mandatos de
--    quem dispara (o analista, pelo portal: fn_revisar_documento, fn_decidir_pendencia, fn_aceitar_extracao) e
--    fn_mudar_dial muda o estágio para TODOS. Um analista com um recorte de concordância alta promoveria o dial de
--    todos, sem erro. Correção: fn_dial_auto_promover vira SECURITY DEFINER (o veredito global e a promoção rodam
--    como o dono e não dependem de quem leu) e fn_veredito_producao também (o número global é o mesmo para todo
--    chamador; p_caso_id exige ser membro). Ele devolve só NÚMEROS e nomes de rubrica do catálogo, nunca linha de
--    cliente. fn_mudar_dial continua INVOKER de propósito (definer deixaria qualquer usuário mudar o dial; a sonda
--    cobra isso, tipo=definer, marcador nao): quem a chama diretamente é o administrador.
--    (2) /autonomia (portal/src/app/autonomia/page.tsx): fn_golden_cobertura e fn_classe_contabil_concordancia davam
--    números do RECORTE do leitor sem aviso. Viram SECURITY DEFINER (só números) — o global é igual para todos; a
--    segunda, com p_caso_id, só conta o mandato de quem é membro.
--    (3) fn_falhas_abertas: ver o comentário na função.
--    As funções abaixo são extraídas do banco montado (pg_get_functiondef) e reemitidas INTEIRAS, com as linhas novas
--    marcadas "0216" — nunca replace de texto sobre o banco.
-- -----------------------------------------------------------------------------
alter function fn_dial_auto_promover(text) security definer set search_path = public, pg_temp;
alter function fn_golden_cobertura(uuid, golden_origem) security definer set search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.fn_veredito_producao(p_estagio text, p_caso_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_natureza  text;
  v_crit      record;
  v_n         int     := 0;
  v_conc      numeric;
  v_por_tipo  jsonb   := '[]'::jsonb;
  v_fonte     text;
  v_pior      jsonb;
  v_falhas    text[]  := '{}';
  v_delegado  jsonb;
begin
  -- 0216: a função é SECURITY DEFINER para o veredito GLOBAL (p_caso_id nulo) ser o mesmo para todo chamador — antes,
  -- com a RLS por mandato, ele era calculado só sobre os mandatos de QUEM DISPARAVA, e fn_mudar_dial mudava o estágio
  -- para TODOS com base nesse recorte. Com p_caso_id, só o membro (ou o administrador) pergunta: sem esta guarda o
  -- definer abriria o número de qualquer mandato.
  if p_caso_id is not null and auth.uid() is not null and not fn_eh_membro(p_caso_id) then
    raise exception 'fn_veredito_producao: o mandato não existe ou você não é membro' using errcode = '42501';
  end if;
  select natureza into v_natureza from estagio_autonomia where estagio = p_estagio;
  if v_natureza is null then
    return jsonb_build_object(
      'estagio', p_estagio, 'suficiente', false,
      'motivo', format('Estágio "%s" não existe no dial.', p_estagio));
  end if;

  select n_minimo_veredito, concordancia_minima, metrica
    into v_crit
    from golden_criterio where estagio = p_estagio;

  if v_crit is null then
    return jsonb_build_object(
      'estagio', p_estagio, 'suficiente', false,
      'motivo', format('O estágio "%s" não tem linha em golden_criterio, então não há limiar '
                       'contra o que comparar. Critério é dado (0126): acrescente a linha.',
                       p_estagio));
  end if;

  if p_estagio = 'classificacao_doc_checklist' then
    -- O VEREDITO É A REVISÃO DE DOCUMENTO. `fn_revisar_documento` grava
    -- 'correcao_classificacao' quando o humano trocou o tipo e 'aprovacao' quando
    -- não trocou, com `tipo_de`/`tipo_para` no payload. O payload é o filtro que
    -- separa esta decisão das outras 'aprovacao' do sistema — a do auto-aceite,
    -- por exemplo, que não é veredito sobre classificação nenhuma.
    --
    -- AUTOR HUMANO, e a exclusão é por prefixo 'sistema:' porque é assim que a
    -- casa marca ator de máquina desde a 0019. Contar o auto-aceite aqui seria a
    -- máquina se dando razão.
    v_fonte := 'decisao (fn_revisar_documento): aprovacao = tipo confirmado, '
               'correcao_classificacao = tipo trocado';
    with v as (
      select d.payload->>'tipo_de' as tipo_sugerido,
             (d.tipo = 'aprovacao') as concordou
        from decisao d
       where d.payload ? 'tipo_para'
         -- SEM PALPITE NÃO HÁ VEREDITO. Documento que chegou à revisão sem tipo
         -- nenhum (`tipo_de` nulo) não tem com o que concordar: contar a correção
         -- dele como erro da máquina puniria o classificador por uma resposta que
         -- ele não deu. Achado no book, onde uma linha assim derrubava a
         -- concordância de 1,00 para 0,83 sozinha.
         and d.payload->>'tipo_de' is not null
         and coalesce(d.autor, '') not like 'sistema:%'
         and d.tipo in ('aprovacao', 'correcao_classificacao')
         and (p_caso_id is null or d.caso_id = p_caso_id)
    ), por_tipo as (
      select tipo_sugerido,
             count(*)::int as n,
             count(*) filter (where concordou)::int as acertos,
             round(count(*) filter (where concordou)::numeric / count(*), 4) as concordancia
        from v group by tipo_sugerido
    )
    select coalesce(sum(n), 0)::int,
           case when coalesce(sum(n), 0) = 0 then null
                else round(sum(acertos)::numeric / sum(n), 4) end,
           coalesce(jsonb_agg(jsonb_build_object(
             'tipo', tipo_sugerido, 'n', n, 'acertos', acertos, 'concordancia', concordancia)
             order by concordancia, tipo_sugerido), '[]'::jsonb)
      into v_n, v_conc, v_por_tipo
      from por_tipo;

  elsif p_estagio = 'reconciliacao_classe_a' then
    -- Já existia desde a 0126 e nunca esteve ligada ao dial. Delegar em vez de
    -- reescrever: duas contagens da mesma quantidade divergem no dia em que
    -- alguém corrigir uma só.
    v_fonte := 'fn_golden_classe_a (0126): rejeitada = falso positivo do motor';
    v_delegado := fn_golden_classe_a(p_caso_id);
    v_n    := coalesce((v_delegado->>'com_veredito_humano')::int, 0);
    v_conc := (v_delegado->>'nao_falso_positivo')::numeric;

  elsif p_estagio = 'classificacao_contabil' then
    -- A 0128 mede isto desde que existe. O teto deste estágio é N1, então o
    -- número não sobe dial nenhum hoje; ele entra aqui para a tela de autonomia
    -- poder mostrar medição onde existe, em vez de silêncio.
    v_fonte := 'fn_classe_contabil_concordancia (0128): sugestão em sombra contra override humano';
    v_delegado := fn_classe_contabil_concordancia(p_caso_id);
    v_n    := coalesce((v_delegado->>'com_veredito_humano')::int, 0);
    v_conc := (v_delegado->>'concordancia')::numeric;

  else
    return jsonb_build_object(
      'estagio', p_estagio, 'suficiente', false, 'n', 0,
      'metrica', v_crit.metrica,
      'motivo', format('Não há veredito de produção para "%s". O trabalho normal não emite rótulo '
                       'sobre este estágio: o analista não confirma nem corrige a saída dele numa '
                       'tela, então não existe o que contar. Medir este estágio exige rotulagem, e '
                       'é o caso que a saída C do B3 cobre.', p_estagio));
  end if;

  -- O TIPO MAIS FRACO, quando há tipo. Um tipo com N pequeno não reprova sozinho:
  -- ele não tem massa para afirmar nada, e tratá-lo como reprovação faria o
  -- estágio inteiro depender do tipo mais raro da mesa.
  select jsonb_agg(t) filter (where (t->>'n')::int >= greatest(v_crit.n_minimo_veredito / 4, 5)
                                and (t->>'concordancia')::numeric < v_crit.concordancia_minima)
    into v_pior
    from jsonb_array_elements(v_por_tipo) t;

  if v_n < v_crit.n_minimo_veredito then
    v_falhas := v_falhas || format('vereditos de produção: %s, mínimo %s',
                                   v_n, v_crit.n_minimo_veredito);
  end if;
  if v_conc is null then
    -- O `::text` NÃO é enfeite — ver o cabeçalho desta migration.
    v_falhas := v_falhas || 'concordância: não medida (nenhum veredito com os dois lados)'::text;
  elsif v_conc < v_crit.concordancia_minima then
    v_falhas := v_falhas || format('concordância: %s, mínimo %s', v_conc, v_crit.concordancia_minima);
  end if;
  if v_pior is not null then
    v_falhas := v_falhas || format('%s tipo(s) com massa e concordância abaixo do mínimo',
                                   jsonb_array_length(v_pior));
  end if;

  return jsonb_build_object(
    'estagio', p_estagio,
    'suficiente', array_length(v_falhas, 1) is null,
    'fonte', v_fonte,
    'metrica', v_crit.metrica,
    'n', v_n,
    'n_minimo', v_crit.n_minimo_veredito,
    'concordancia', v_conc,
    'concordancia_minima', v_crit.concordancia_minima,
    'por_tipo', v_por_tipo,
    'tipos_abaixo_do_minimo', coalesce(v_pior, '[]'::jsonb),
    'falhas', coalesce(to_jsonb(v_falhas), '[]'::jsonb),
    'piso_enviesado', true,
    'como_ler', 'Este número é um PISO, não um ground truth. O veredito vem do trabalho normal, e '
                'quem o emite VÊ o palpite da máquina antes de decidir — o viés de confirmação '
                'empurra a concordância para cima. Serve para dizer "a máquina acerta pelo menos '
                'isto"; não substitui rotulagem cega no dia em que for preciso sustentar o número '
                'para fora.');
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_classe_contabil_concordancia(p_caso_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with par as (
    select s.classe_codigo as sugerida, o.classe_final as humana, s.rubrica_id
    from campo_classe_sugerida s
    join lateral (
      select o.classe_final from campo_classe_override o
      where o.campo_extraido_id = s.campo_extraido_id
      order by o.criado_em desc, o.id desc limit 1
    ) o on true
    join campo_extraido ce on ce.id = s.campo_extraido_id
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where (p_caso_id is null or (d.caso_id = p_caso_id and (auth.uid() is null or fn_eh_membro(p_caso_id))))
      and s.criado_em = (select max(s2.criado_em) from campo_classe_sugerida s2
                          where s2.campo_extraido_id = s.campo_extraido_id)
  ),
  sem_veredito as (
    select count(*) as n
    from campo_classe_sugerida s
    join campo_extraido ce on ce.id = s.campo_extraido_id
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where (p_caso_id is null or (d.caso_id = p_caso_id and (auth.uid() is null or fn_eh_membro(p_caso_id))))
      and not exists (select 1 from campo_classe_override o
                       where o.campo_extraido_id = s.campo_extraido_id)
  )
  select jsonb_build_object(
    'com_veredito_humano', (select count(*) from par),
    'concordaram', (select count(*) from par where sugerida = humana),
    'concordancia', case when (select count(*) from par) = 0 then null
                        else round((select count(*) from par where sugerida = humana)::numeric
                                   / (select count(*) from par), 4) end,
    'sem_veredito_humano', (select n from sem_veredito),
    'rubricas_que_mais_erram', (
      select coalesce(jsonb_agg(x order by x->>'erros' desc), '[]'::jsonb) from (
        select jsonb_build_object(
                 'padrao', rc.padrao, 'sugeria', rc.classe_codigo,
                 'erros', count(*),
                 'humano_disse', jsonb_agg(distinct par.humana)) as x
        from par join rubrica_classe rc on rc.id = par.rubrica_id
        where par.sugerida <> par.humana
        group by rc.padrao, rc.classe_codigo
        order by count(*) desc limit 10
      ) t),
    'como_ler', 'O denominador são as linhas com sugestao E override. Linha que ninguem olhou fica '
                'FORA, contada a parte: "a maquina acertou" e "ninguem conferiu" sao estados '
                'diferentes. E este numero NAO autoriza subir o dial por si: o teto de '
                'classificacao_contabil e N1 para sempre (Arquitetura do Sistema/1 Visão e Doutrina/01).'
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_mudar_dial(p_estagio text, p_nivel nivel_autonomia, p_autor text, p_motivo text DEFAULT NULL::text, p_limiar numeric DEFAULT NULL::numeric, p_rodada_golden uuid DEFAULT NULL::uuid, p_sem_medicao_porque text DEFAULT NULL::text, p_por_veredito boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_antes     jsonb;
  v_teto      nivel_autonomia;
  v_nivel_ant nivel_autonomia;
  v_natureza  text;
  v_sobe_para_autonomia boolean;
  v_med       jsonb;
  v_base      text;
  v_resumo    jsonb;
  v_freia     boolean;
  v_linhas    int;
  v_mede      boolean := false;   -- esta chamada produziu base MEDIDA nova?
begin
  select to_jsonb(ea), ea.teto, ea.nivel_atual, ea.natureza
    into v_antes, v_teto, v_nivel_ant, v_natureza
  from estagio_autonomia ea where ea.estagio = p_estagio;

  if v_antes is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Estágio "%s" não existe no dial. Os estágios são semeados na 0002 '
                              '(Arquitetura do Sistema/2 Especificação/f0/04) — estágio novo entra por migration, não por chamada.', p_estagio));
  end if;

  if p_nivel > v_teto then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'mudanca_dial_recusada', 'estagio:'||p_estagio,
              jsonb_build_object('pedido', p_nivel, 'teto', v_teto, 'motivo_informado', p_motivo));
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('O estágio "%s" tem TETO %s e foi pedido %s. O teto é por natureza do '
                              'estágio (Arquitetura do Sistema/1 Visão e Doutrina/01) e nenhuma chamada o sobrepõe — mudá-lo é decisão de '
                              'doutrina, por migration.', p_estagio, v_teto, p_nivel));
  end if;

  v_sobe_para_autonomia := p_nivel > v_nivel_ant
                           and p_nivel in ('N2', 'N3')
                           and v_natureza = 'interpretativo';

  v_base := case when p_nivel in ('N2','N3') and v_natureza = 'interpretativo'
                 then 'declarada' else 'nao_se_aplica' end;

  -- A TRAVA 2 (0137): descida feita por humano desliga a promoção automática.
  v_freia := p_nivel < v_nivel_ant and coalesce(p_autor, '') not like 'sistema:%';

  if v_sobe_para_autonomia then
    if p_rodada_golden is not null then
      v_med := fn_golden_suficiente(p_estagio, p_rodada_golden);
      if not coalesce((v_med->>'suficiente')::boolean, false) then
        insert into evento_auditoria (ator, acao, entidade_ref, depois)
          values (p_autor, 'mudanca_dial_recusada', 'estagio:'||p_estagio,
                  jsonb_build_object('pedido', p_nivel, 'de', v_nivel_ant,
                                     'motivo_informado', p_motivo, 'medicao', v_med));
        return jsonb_build_object('recusado', true, 'medicao', v_med,
          'motivo_recusa', format('A concordância medida contra a rodada de golden set não basta '
                                  'para subir "%s" de %s para %s. Arquitetura do Sistema/1 Visão e Doutrina/01, regra de ouro: nada de '
                                  'subir dial de estágio interpretativo sem golden set e '
                                  'concordância medida. O que faltou está em "medicao".',
                                  p_estagio, v_nivel_ant, p_nivel));
      end if;
      v_base := 'medida';
      v_resumo := v_med;
      v_mede := true;

    elsif p_por_veredito then
      v_med := fn_veredito_producao(p_estagio);
      if not coalesce((v_med->>'suficiente')::boolean, false) then
        insert into evento_auditoria (ator, acao, entidade_ref, depois)
          values (p_autor, 'mudanca_dial_recusada', 'estagio:'||p_estagio,
                  jsonb_build_object('pedido', p_nivel, 'de', v_nivel_ant,
                                     'motivo_informado', p_motivo, 'medicao', v_med));
        return jsonb_build_object('recusado', true, 'medicao', v_med,
          'motivo_recusa', format('O veredito de produção não basta para subir "%s" de %s para %s. '
                                  'O que faltou está em "medicao"; a fonte do rótulo está em '
                                  '"fonte". Lembrando que este caminho mede um PISO, e o piso ainda '
                                  'não alcançou o critério.', p_estagio, v_nivel_ant, p_nivel));
      end if;
      v_base := 'medida_por_veredito';
      v_resumo := v_med;
      v_mede := true;

    elsif p_sem_medicao_porque is null then
      insert into evento_auditoria (ator, acao, entidade_ref, depois)
        values (p_autor, 'mudanca_dial_recusada', 'estagio:'||p_estagio,
                jsonb_build_object('pedido', p_nivel, 'de', v_nivel_ant,
                                   'motivo_informado', p_motivo,
                                   'porque', 'sem rodada de golden set, sem veredito e sem motivo declarado'));
      return jsonb_build_object('recusado', true,
        'motivo_recusa', format('Subir "%s" de %s para %s é entrar em auto-clear num estágio '
                                'INTERPRETATIVO, e Arquitetura do Sistema/1 Visão e Doutrina/01 exige concordância medida para isso. '
                                'Três caminhos: `p_rodada_golden` com uma rodada CONGELADA, '
                                '`p_por_veredito` para medir pelo veredito de produção (0136, e o '
                                'número é um piso enviesado), ou assumir a decisão em '
                                '`p_sem_medicao_porque` — nesse caso a subida acontece, fica '
                                'registrada como mudanca_dial_sem_medicao e o nível passa a valer '
                                'como DECLARADO.', p_estagio, v_nivel_ant, p_nivel));
    end if;
  end if;

  -- REAFIRMAR O NÍVEL QUE JÁ VALE NÃO PODE APAGAR A MEDIÇÃO QUE O AUTORIZOU.
  --
  -- `v_mede` é verdadeiro só quando ESTA chamada produziu base nova. Quando não
  -- produziu — e o nível pedido é o que já está lá —, os três campos de medição
  -- ficam como estavam. Sem isso, `fn_mudar_dial(estagio, <mesmo nível>)` trocava
  -- `medida_por_veredito` por `declarada` e zerava `medicao_em`/`medicao_resumo`:
  -- o sistema passava a subdeclarar a própria evidência, e a trilha do que
  -- autorizou o nível sumia. Ver o cabeçalho desta migration.
  update estagio_autonomia
    set nivel_atual = p_nivel,
        limiar_auto_clear = coalesce(p_limiar, limiar_auto_clear),
        base_do_nivel = case when v_mede or p_nivel <> v_nivel_ant then v_base else base_do_nivel end,
        medicao_rodada_id = case when v_mede then (case when v_base = 'medida' then p_rodada_golden else null end)
                                 when p_nivel <> v_nivel_ant then null
                                 else medicao_rodada_id end,
        medicao_em        = case when v_mede then now()
                                 when p_nivel <> v_nivel_ant then null
                                 else medicao_em end,
        medicao_resumo    = case when v_mede then v_resumo
                                 when p_nivel <> v_nivel_ant then null
                                 else medicao_resumo end,
        -- O FREIO GRUDA. Uma vez desligada por descida humana, a promoção
        -- automática só volta por `update` explícito: quem desconfiou é quem
        -- decide voltar a confiar.
        auto_promocao = case when v_freia then false else auto_promocao end,
        atualizado_por = p_autor,
        atualizado_em = now()
  where estagio = p_estagio;
  -- 0216: o estágio existe (checado acima); zero linhas aqui é a RLS recusando o UPDATE a quem não é administrador. Sem
  -- esta guarda a função seguia, gravava o evento `mudanca_dial` e devolvia sucesso — um dial que "mudou" sem mudar,
  -- e uma trilha que afirma o contrário do estado.
  get diagnostics v_linhas = row_count;
  if v_linhas = 0 then
    raise exception 'fn_mudar_dial: sem permissão para alterar o dial (só o administrador altera estagio_autonomia)' using errcode = '42501';
  end if;

  if v_freia then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'auto_promocao_desligada', 'estagio:'||p_estagio,
              jsonb_build_object('de', v_nivel_ant, 'para', p_nivel, 'motivo_informado', p_motivo,
                                 'porque', 'descida feita por humano desliga a promoção automática '
                                           '(0137); religar é update explícito'));
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor,
            case when v_sobe_para_autonomia and p_rodada_golden is null and not p_por_veredito
                 then 'mudanca_dial_sem_medicao' else 'mudanca_dial' end,
            'estagio:'||p_estagio, v_antes,
            (select to_jsonb(ea) from estagio_autonomia ea where ea.estagio = p_estagio)
            || jsonb_build_object('motivo', p_motivo,
                                  'sem_medicao_porque', p_sem_medicao_porque,
                                  'medicao', v_resumo));

  return fn_dial(p_estagio);
end;
$function$;

create or replace function fn_falhas_abertas(p_caso_nome text, p_desde timestamptz)
returns table(id uuid, etapa text, mensagem text, criado_em timestamptz)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select f.id, f.etapa, f.mensagem, f.criado_em
  from execucao_falha f
  where f.visto_em is null
    and f.criado_em >= p_desde
    and (
         -- falha de ANTES de o caso existir (caso_id nulo): quem a procura pelo NOME a recebe — é o que tira o
         -- /api/intake/status do "aguarde" eterno (0108). Ninguém é membro de um caso que ainda não existe.
         (f.caso_id is null and lower(f.caso_nome) = lower(trim(p_caso_nome)))
         -- falha de caso que existe: só quem é membro dele (a RLS valia aqui quando a função era invoker)
         or (f.caso_id in (select fn_meus_casos())
             and (lower(f.caso_nome) = lower(trim(p_caso_nome))
                  or f.caso_id in (select c.id from caso c where lower(c.nome) = lower(trim(p_caso_nome)))))
        )
  order by f.criado_em desc;
$$;
comment on function fn_falhas_abertas(text, timestamptz) is
  'Falhas de execução ainda não vistas para este nome de mandato desde p_desde (0108). SECURITY DEFINER (0216): a falha de caso_id NULO (antes de o caso existir) é entregue a quem a procura pelo nome; a de caso existente, só ao membro. O nome é o que identifica o arquivo que o usuário acabou de subir: quem adivinha o nome lê as falhas sem caso dele — decisão consciente, o /api/intake/status não tem outra identidade.';

-- -----------------------------------------------------------------------------
-- 6. GRANTs (0214): nenhum objeto novo sem acesso. A coluna caso_id herda o do evento_auditoria. Função: o Postgres dá
--    EXECUTE a PUBLIC por default, então o revoke vem primeiro. Gatilho não precisa de EXECUTE para o authenticated.
-- -----------------------------------------------------------------------------
revoke execute on function fn_meus_casos(), fn_caso_nome_existe(text, uuid), fn_caso_da_chave(text),
  fn_caso_da_referencia(text), fn_trg_evento_caso_id(), fn_trg_caso_nome_unico() from public, anon, authenticated;
grant execute on function fn_meus_casos(), fn_caso_da_chave(text), fn_caso_da_referencia(text) to authenticated, service_role;
grant execute on function fn_caso_nome_existe(text, uuid) to service_role;
-- As funções que esta migration tornou SECURITY DEFINER (ou criou como tal) NÃO ficam executáveis por PUBLIC/anon: definer
-- executável pela chave pública é o clássico caminho de escalada, e a guarda de p_caso_id deixa passar quem não tem
-- identidade (auth.uid() nulo = n8n/dono) — o anon não pode chegar nela. O authenticated e o service_role seguem com EXECUTE.
revoke execute on function fn_veredito_producao(text, uuid), fn_classe_contabil_concordancia(uuid),
  fn_golden_cobertura(uuid, golden_origem), fn_dial_auto_promover(text), fn_falhas_abertas(text, timestamptz),
  fn_upsert_caso(text, text) from public, anon;
grant execute on function fn_veredito_producao(text, uuid), fn_classe_contabil_concordancia(uuid),
  fn_golden_cobertura(uuid, golden_origem), fn_dial_auto_promover(text), fn_falhas_abertas(text, timestamptz),
  fn_upsert_caso(text, text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 7. A SONDA. O tipo `definer` entra nesta migration (constraint abaixo). A função é a da 0215 INTEIRA (extraída do próprio arquivo, não replace de texto sobre o banco — memória
--    nunca-corrigir-funcao-por-replace) com o ramo `policy` ampliado (schema.tabela.policy e marcador na expressão).
-- -----------------------------------------------------------------------------
alter table instalacao_requisito drop constraint if exists instalacao_requisito_tipo_check;
alter table instalacao_requisito add constraint instalacao_requisito_tipo_check
  check (tipo in ('tabela', 'coluna', 'funcao', 'seed', 'comportamento', 'corpo', 'gatilho', 'policy', 'privilegio', 'execucao', 'rls', 'definer'));

CREATE OR REPLACE FUNCTION public.fn_instalacao_conferir()
 RETURNS TABLE(chave text, migration text, tipo text, objeto text, presente boolean, detalhe text, porque text, severidade text)
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  r            instalacao_requisito;
  v_ok         boolean;
  v_det        text;
  v_n          bigint;
  v_alvo       regclass;
  v_crit       int;
  v_proc       regproc;
  v_src        text;
  v_tg_enabled "char";
  v_tg_fn      text;
  v_role       text;
  v_privs      text[];
  v_kinds      "char"[];
  v_lista      text;
  v_rls        boolean;
  v_def        boolean;
  v_sp         boolean;
  v_polnome    name;
  v_polexpr    text;
begin
  for r in select * from instalacao_requisito order by ordem, chave loop
    v_ok  := false;
    v_det := null;

    if r.tipo = 'tabela' then
      v_ok := to_regclass('public.' || r.objeto) is not null;

    elsif r.tipo = 'funcao' then
      -- `to_regproc` falha quando a função tem sobrecargas ambíguas; o nome sem
      -- argumentos resolve pelo único candidato, e sobrecarga é sinal de que o
      -- requisito devia declarar a assinatura. Nenhum dos requisitos abaixo tem.
      begin
        v_ok := to_regproc('public.' || r.objeto) is not null;
      exception when others then
        -- Ambiguidade significa que EXISTE mais de uma — logo, existe.
        v_ok := true;
        v_det := 'mais de uma assinatura com este nome';
      end;

    elsif r.tipo = 'corpo' then
      -- 0147: o corpo PUBLICADO tem de conter o marcador.
      --
      -- Como todo ramo desta função, ele não pode derrubar a sonda: função
      -- ausente, nome ambíguo e marcador ausente são três respostas diferentes,
      -- e as três são `presente = false` com o detalhe dizendo QUAL — porque
      -- "aplique a migration" e "há duas assinaturas com este nome" pedem ações
      -- diferentes de quem está lendo a tela.
      begin
        v_proc := to_regproc('public.' || r.objeto);
      exception when others then
        v_proc := null;
        v_det  := 'mais de uma assinatura com este nome — o requisito precisa declarar os argumentos';
      end;

      if v_proc is null then
        v_ok  := false;
        v_det := coalesce(v_det, 'a função nem existe');
      else
        v_src := pg_get_functiondef(v_proc::oid);
        v_ok  := v_src is not null and position(r.marcador in v_src) > 0;
        v_det := case when v_ok then 'corpo com o marcador'
                      else 'a função existe, mas o corpo é ANTERIOR a esta migration' end;
      end if;

    elsif r.tipo = 'coluna' then
      -- 0132: `pg_attribute` em vez de `information_schema.columns` — mesma
      -- resposta, 14× mais barato (3,4 ms → 0,25 ms medidos). A view do
      -- information_schema junta várias tabelas de catálogo e filtra por
      -- privilégio linha a linha; aqui a pergunta é "existe esta coluna", e
      -- `attrelid` já vem resolvido por `to_regclass`.
      --
      -- `to_regclass` devolvendo NULL não é erro: significa que a TABELA não
      -- existe, e aí a coluna também não — `attrelid = null` não casa com nada e
      -- o `exists` dá false, que é a resposta certa. É a mesma proteção do ramo
      -- de seed abaixo, obtida de graça pela forma da consulta.
      v_ok := exists (
        select 1 from pg_attribute a
         where a.attrelid  = to_regclass('public.' || split_part(r.objeto, '.', 1))
           and a.attname   = split_part(r.objeto, '.', 2)
           and a.attnum    > 0
           and not a.attisdropped);

    elsif r.tipo = 'policy' then
      -- 0210: policy de RLS é catalogada POR SI (objeto = 'tabela.nome_da_policy'). Nenhum outro tipo a
      -- enxerga: a tabela existe, a função existe, e sem a policy o authenticated leva 42501 ao escrever.
      -- 0216: (a) `objeto` aceita 'schema.tabela.policy' (a policy do bucket mora em storage.objects); (b) `marcador`,
      -- quando declarado, tem de aparecer na EXPRESSÃO da policy (using + with check). Sem (b), a policy
      -- `using (true)` que a 0216 existe para tirar passaria por "presente": o nome é o mesmo, só a regra mudou.
      if array_length(string_to_array(r.objeto, '.'), 1) = 3 then
        v_alvo := to_regclass(split_part(r.objeto, '.', 1) || '.' || split_part(r.objeto, '.', 2));
      else
        v_alvo := to_regclass('public.' || split_part(r.objeto, '.', 1));
      end if;
      if v_alvo is null then
        v_ok  := false;
        v_det := 'a tabela nem existe';
      else
        select p.polname, coalesce(pg_get_expr(p.polqual, p.polrelid), '') || ' ' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '')
          into v_polnome, v_polexpr
          from pg_policy p
         where p.polrelid = v_alvo and p.polname = split_part(r.objeto, '.', array_length(string_to_array(r.objeto, '.'), 1));
        if v_polnome is null then
          v_ok  := false;
          v_det := 'a policy não existe na tabela (RLS ligada sem ela nega a operação ao authenticated)';
        elsif r.marcador is not null and position(r.marcador in v_polexpr) = 0 then
          v_ok  := false;
          v_det := format('a policy existe, mas a expressão dela NÃO contém %s — a regra por mandato não está nela (using (true)?)', r.marcador);
        else
          v_ok  := true;
          v_det := 'policy presente';
        end if;
      end if;

    elsif r.tipo = 'gatilho' then
      -- 0189: gatilho é catalogado POR SI, não pela função que ele chama.
      --
      -- POR QUE ISTO NÃO CABE NO TIPO `funcao`. A função de um gatilho
      -- SOBREVIVE a `drop trigger` e a `alter table ... disable trigger` — o
      -- exemplo já estava no catálogo antes deste tipo existir, em
      -- `gatilho_da_promocao` (0137): a função `fn_trg_auto_promover_dial`
      -- existe e nada garante que algo a chame. `objeto` aqui é
      -- `tabela.nome_do_gatilho`; a tabela é resolvida primeiro, como em todo
      -- ramo desta função — tabela ausente nunca pode virar exceção que
      -- derruba a sonda inteira.
      v_alvo := to_regclass('public.' || split_part(r.objeto, '.', 1));
      if v_alvo is null then
        v_ok  := false;
        v_det := 'a tabela nem existe';
      else
        select tgenabled, tgfoid::regproc::text
          into v_tg_enabled, v_tg_fn
          from pg_trigger
         where tgrelid = v_alvo
           and tgname  = split_part(r.objeto, '.', 2)
           and not tgisinternal;

        if v_tg_enabled is null then
          v_ok  := false;
          v_det := 'o gatilho não existe na tabela (a função dele pode existir — ela sobrevive ao drop trigger)';
        elsif v_tg_enabled = 'D' then
          v_ok  := false;
          v_det := 'o gatilho existe mas está DESABILITADO (disable trigger) — a guarda não roda';
        elsif v_tg_enabled = 'R' then
          -- 'R' = ENABLE REPLICA TRIGGER. Decisão deliberada, e mais estrita
          -- que `<> 'D'`: um gatilho em modo réplica NÃO dispara com
          -- `session_replication_role = origin`, que é o padrão de toda sessão
          -- normal (é o que o pooler do Supabase usa). Do ponto de vista de
          -- quem depende da guarda rodando na sessão normal, um gatilho em
          -- modo réplica está tão desligado quanto um desabilitado — só que
          -- calado, porque `tgenabled <> 'D'` deixaria passar.
          v_ok  := false;
          v_det := 'o gatilho existe mas só dispara em modo réplica — na sessão normal a guarda não roda';
        elsif v_tg_enabled in ('O', 'A') then
          -- 'O' = ENABLE (origin, o padrão) · 'A' = ENABLE ALWAYS (dispara em
          -- origin e em réplica). As duas rodam em sessão normal — é só isso
          -- que este ramo promete. Ele NÃO confere se o gatilho chama a
          -- função certa nem em quais eventos (INSERT/UPDATE/DELETE) — só que
          -- existe e dispara. `v_tg_fn` entra no detalhe por informação, sem
          -- afetar `v_ok`.
          v_ok  := true;
          v_det := format('gatilho habilitado (chama %s)', coalesce(v_tg_fn, '?'));
        else
          -- Não deveria acontecer — `tgenabled` só tem estes quatro valores —
          -- mas a sonda nunca assume "presente" por omissão de um `case`.
          v_ok  := false;
          v_det := format('estado de gatilho desconhecido: %s', v_tg_enabled);
        end if;
      end if;

    elsif r.tipo = 'privilegio' then
      -- 0214: privilégio de TABELA/VIEW/SEQUENCE do schema public para um papel. `objeto` = 'papel:classe' (classe
      -- tabelas | views | sequences) e `marcador` = os privilégios exigidos, separados por vírgula. Varre TODO o
      -- schema, não uma lista: o defeito que isto pega é a tabela NOVA cuja migration esqueceu o GRANT (a partir
      -- de 30/10/2026 o Supabase não concede mais nada por default privilege), e uma lista de nomes seria
      -- exatamente a que ninguém atualiza. Objeto de extensão fica de fora (não é nosso). Revoke intencional
      -- (delete do authenticated em arquivo_oficial etc.) não aparece aqui: só se exige o MÍNIMO por classe.
      v_role  := split_part(r.objeto, ':', 1);
      v_privs := string_to_array(r.marcador, ',');
      v_kinds := case split_part(r.objeto, ':', 2)
                   when 'tabelas'   then array['r', 'p']::"char"[]
                   when 'views'     then array['v', 'm']::"char"[]
                   when 'sequences' then array['S']::"char"[]
                 end;
      if v_kinds is null or v_privs is null then
        v_ok  := false;
        v_det := 'requisito mal declarado: objeto papel:(tabelas|views|sequences) e marcador com os privilégios';
      elsif not exists (select 1 from pg_roles where rolname = v_role) then
        v_ok  := false;
        v_det := format('o papel %s nem existe', v_role);
      else
        select count(*), string_agg(x.relname, ', ' order by x.relname) filter (where x.rn <= 15)
          into v_n, v_lista
          from (select c.relname, row_number() over (order by c.relname) as rn
                  from pg_class c
                  join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'public'
                   and c.relkind = any (v_kinds)
                   and not exists (select 1 from pg_depend d
                                    where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e')
                   and exists (select 1 from unnest(v_privs) p
                                where not case when c.relkind = 'S'
                                         then has_sequence_privilege(v_role, c.oid, p)
                                         else has_table_privilege(v_role, c.oid, p) end)) x;
        v_ok  := v_n = 0;
        v_det := case when v_ok then format('nenhum objeto de public sem %s para %s', r.marcador, v_role)
                      else format('%s objeto(s) de public SEM %s para %s: %s%s', v_n, r.marcador, v_role, v_lista,
                                  case when v_n > 15 then ' ...' else '' end) end;
      end if;

    elsif r.tipo = 'execucao' then
      -- 0215: EXECUTE de função para um papel. `objeto` = 'papel:nome_da_funcao' (sem argumentos: o nome tem de ser
      -- único) e `marcador` = 'sim' (o papel TEM de executar) ou 'nao' (NÃO pode). O 'nao' existe por
      -- fn_administrador_definir: função em public nasce executável por PUBLIC no Postgres, e o revoke esquecido
      -- tira a primeira barreira de privilégio de promover administrador (DEFESA EM PROFUNDIDADE: hoje a função é
      -- INVOKER e o authenticated levaria 42501 em auth.users e em administrador de qualquer jeito) — nenhum outro
      -- tipo vê isso, porque a função existe e o corpo está certo. `has_function_privilege` enxerga a concessão a
      -- PUBLIC, que é a que importa.
      -- `marcador` NULO: `null not in (...)` é NULL, o `if` cai adiante e `... = (null = 'sim')` dá NULL — e
      -- presente NULL some de `where not presente` (regra 7). Requisito sem marcador é requisito mal declarado.
      v_role := split_part(r.objeto, ':', 1);
      if r.marcador is null or r.marcador not in ('sim', 'nao') then
        v_ok  := false;
        v_det := 'requisito mal declarado: marcador tem de ser sim ou nao';
      elsif not exists (select 1 from pg_roles where rolname = v_role) then
        v_ok  := false;
        v_det := format('o papel %s nem existe', v_role);
      else
        begin
          v_proc := to_regproc('public.' || split_part(r.objeto, ':', 2));
        exception when others then
          v_proc := null;
          v_det  := 'mais de uma assinatura com este nome — o requisito precisa de um nome único';
        end;
        if v_proc is null then
          v_ok  := false;
          v_det := coalesce(v_det, 'a função nem existe');
        else
          v_ok  := has_function_privilege(v_role, v_proc::oid, 'execute') = (r.marcador = 'sim');
          v_det := case when v_ok then format('%s %s executa', v_role, case when r.marcador = 'sim' then 'pode' else 'NÃO pode' end)
                        when r.marcador = 'sim' then format('%s NÃO executa a função (o portal leva "permission denied")', v_role)
                        else format('%s EXECUTA a função e não podia (revoke esquecido)', v_role) end;
        end if;
      end if;

    elsif r.tipo = 'definer' then
      -- 0216: SECURITY DEFINER da função (pg_proc.prosecdef). `objeto` = nome da função (único) e `marcador` = 'sim'
      -- (TEM de ser definer, E com search_path fixo em proconfig — definer sem search_path é sequestrável) ou 'nao'
      -- (TEM de ser invoker). O 'sim' existe porque o veredito global do dial, os agregados de /autonomia e as falhas
      -- sem caso só valem se NÃO dependem de quem lê (a RLS por mandato daria o número do recorte, calada); o 'nao'
      -- existe por fn_mudar_dial: definer deixaria qualquer usuário mudar o dial. O tipo `corpo` não vê isso — ALTER
      -- FUNCTION ... SECURITY DEFINER não muda uma letra do corpo.
      if r.marcador is null or r.marcador not in ('sim', 'nao') then
        v_ok  := false;
        v_det := 'requisito mal declarado: marcador tem de ser sim ou nao';
      else
        begin
          v_proc := to_regproc('public.' || r.objeto);
        exception when others then
          v_proc := null;
          v_det  := 'mais de uma assinatura com este nome — o requisito precisa de um nome único';
        end;
        if v_proc is null then
          v_ok  := false;
          v_det := coalesce(v_det, 'a função nem existe');
        else
          select p.prosecdef, coalesce(exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%'), false)
            into v_def, v_sp from pg_proc p where p.oid = v_proc::oid;
          v_ok  := case when r.marcador = 'sim' then v_def and v_sp else not v_def end;
          v_det := case when v_ok then format('%s (%s)', case when v_def then 'SECURITY DEFINER' else 'INVOKER' end,
                                              case when v_sp then 'search_path fixo' else 'sem search_path' end)
                        when r.marcador = 'sim' then format('a função é %s%s: o resultado passa a depender de quem lê (RLS) ou fica sequestrável',
                                                            case when v_def then 'DEFINER' else 'INVOKER' end,
                                                            case when v_def and not v_sp then ' SEM search_path fixo' else '' end)
                        else 'a função é SECURITY DEFINER e tinha de ser INVOKER (qualquer usuário a usaria com os poderes do dono)' end;
        end if;
      end if;

    elsif r.tipo = 'rls' then
      -- 0215: RLS LIGADA (pg_class.relrowsecurity). `objeto` = tabela de public, ou 'schema.tabela' (storage.objects).
      -- A policy `por mandato` existe no catálogo mesmo com a RLS DESLIGADA e então NÃO vale: o `where` dela some, o
      -- acesso passa a ser só o GRANT — e no projeto existente o default privilege ainda concede ALL a anon e
      -- authenticated até 30/10/2026. O tipo `policy` não vê isso (a policy está lá); este vê. Tabela ausente é
      -- `presente = false` com o detalhe, nunca exceção.
      v_alvo := to_regclass(case when position('.' in r.objeto) > 0 then r.objeto else 'public.' || r.objeto end);
      if v_alvo is null then
        v_ok  := false;
        v_det := 'a tabela nem existe';
      else
        select c.relrowsecurity into v_rls from pg_class c where c.oid = v_alvo;
        v_ok  := coalesce(v_rls, false);
        v_det := case when v_ok then 'RLS ligada'
                      else 'RLS DESLIGADA: as policies existem no catálogo e o Postgres não as aplica — o acesso passa a ser só o GRANT' end;
      end if;

    elsif r.tipo in ('seed', 'comportamento') then
      -- A tabela pode não existir ainda: contar nela levantaria erro e derrubaria
      -- a sonda inteira, transformando "um requisito faltando" em "o painel não
      -- abre". A sonda de instalação é o último lugar do sistema que pode falhar
      -- por causa do que ela existe para medir.
      v_alvo := to_regclass('public.' || r.objeto);
      if v_alvo is null then
        v_ok  := false;
        v_det := 'a tabela nem existe';
      else
        -- 0132: CONTAGEM LIMITADA AO CRITÉRIO. Ver o cabeçalho: a pergunta é
        -- ">= criterio", e varrer a tabela inteira para respondê-la faz o custo
        -- do painel crescer junto com `lote_execucao`, que cresce para sempre.
        v_crit := greatest(coalesce(r.criterio_seed, 1), 1);
        execute format('select count(*) from (select 1 from public.%I limit %s) x',
                       r.objeto, v_crit)
           into v_n;
        v_ok := v_n >= v_crit;
        -- No caso PRESENTE o total exato não é conhecido (nem usado pela tela).
        -- No caso AUSENTE ele é exato por construção — a varredura parou antes do
        -- limite, logo passou por tudo — e é nele que o número informa algo:
        -- "3 linha(s)" com critério 8 diz que o seed rodou pela metade.
        v_det := case when v_ok then format('%s linha(s) ou mais', v_crit)
                      else format('%s linha(s)', v_n) end;
      end if;
    end if;

    -- Nenhum requisito pode sair NULL: `presente` NULL some de `where not presente`, que é como a sonda é lida.
    return query select r.chave, r.migration, r.tipo, r.objeto, coalesce(v_ok, false), v_det,
                        r.porque, r.severidade;
  end loop;
end;
$function$;

comment on function fn_instalacao_conferir() is
  'Confere cada requisito de instalacao_requisito contra o catálogo do banco. Sobrevive ao objeto ausente (to_regclass/to_regproc devolvem NULL em vez de erro): a sonda não pode falhar por causa do que ela existe para medir. Desde a 0147 confere também o CORPO da função (tipo=corpo), que é o único jeito de distinguir uma correção aplicada de uma função homônima com o corpo velho. Desde a 0189 confere também GATILHO (tipo=gatilho): existência na tabela E tgenabled em (''O'',''A'') — a função do gatilho sobrevive a drop trigger/disable trigger e por isso NUNCA prova, sozinha, que a guarda está ligada. Desde a 0210 confere também POLICY (tipo=policy, objeto tabela.nome_da_policy): existência em pg_policy. Desde a 0214 confere PRIVILÉGIO (tipo=privilegio, objeto papel:classe, marcador = privilégios): toda tabela/view/sequence de public sem o mínimo para authenticated e service_role é buraco — o Supabase deixou de conceder por default privilege em 30/10/2026. Desde a 0215 confere também EXECUÇÃO de função (tipo=execucao, objeto papel:funcao, marcador sim|nao): has_function_privilege, que enxerga o PUBLIC — é a primeira barreira de privilégio de fn_administrador_definir (defesa em profundidade). Desde a 0215 confere também RLS LIGADA (tipo=rls, objeto tabela ou schema.tabela): relrowsecurity — policy em tabela com a RLS desligada não vale. Desde a 0215 nenhum requisito sai com presente NULL (coalesce) e execucao sem marcador é requisito mal declarado. Desde a 0216 confere também SECURITY DEFINER (tipo=definer, marcador sim|nao; o sim exige search_path fixo). Desde a 0216 o requisito de policy aceita `schema.tabela.policy` e um marcador que tem de constar na expressão da policy (é o que distingue a policy por mandato do using (true) de mesmo nome).';

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('mandato_arquivo_oficial_por_mandato', '0216', 'policy', 'arquivo_oficial.arquivo_oficial_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de arquivo_oficial (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 941),
  ('mandato_caso_apresentacao_campo_por_mandato', '0216', 'policy', 'caso_apresentacao_campo.caso_apresentacao_campo_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de caso_apresentacao_campo (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 942),
  ('mandato_caso_linha_premissa_por_mandato', '0216', 'policy', 'caso_linha_premissa.caso_linha_premissa_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de caso_linha_premissa (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 943),
  ('mandato_caso_modelagem_por_mandato', '0216', 'policy', 'caso_modelagem.caso_modelagem_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de caso_modelagem (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 944),
  ('mandato_caso_premissa_por_mandato', '0216', 'policy', 'caso_premissa.caso_premissa_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de caso_premissa (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 945),
  ('mandato_checklist_item_status_por_mandato', '0216', 'policy', 'checklist_item_status.checklist_item_status_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de checklist_item_status (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 946),
  ('mandato_decisao_por_mandato', '0216', 'policy', 'decisao.decisao_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de decisao (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 947),
  ('mandato_documento_por_mandato', '0216', 'policy', 'documento.documento_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de documento (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 948),
  ('mandato_entidade_por_mandato', '0216', 'policy', 'entidade.entidade_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de entidade (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 949),
  ('mandato_execucao_falha_por_mandato', '0216', 'policy', 'execucao_falha.execucao_falha_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de execucao_falha (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 950),
  ('mandato_lote_execucao_por_mandato', '0216', 'policy', 'lote_execucao.lote_execucao_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de lote_execucao (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 951),
  ('mandato_pendencia_por_mandato', '0216', 'policy', 'pendencia.pendencia_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de pendencia (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 952),
  ('mandato_periodo_por_mandato', '0216', 'policy', 'periodo.periodo_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de periodo (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 953),
  ('mandato_reconciliacao_por_mandato', '0216', 'policy', 'reconciliacao.reconciliacao_por_mandato', 'fn_meus_casos', null,
   'Sem a policy por mandato de reconciliacao (ou com ela voltada a using (true)) todo usuário logado lê e grava os dados de todos os mandatos nesta tabela.',
   'bloqueante', 954),
  ('mandato_documento_versao_por_mandato', '0216', 'policy', 'documento_versao.documento_versao_por_mandato', 'FROM documento', null,
   'Sem a policy por mandato de documento_versao (ou com ela voltada a using (true)) todo usuário logado lê e grava as linhas dos mandatos alheios — o caso desta tabela vem do pai (documento).',
   'bloqueante', 955),
  ('mandato_campo_extraido_por_mandato', '0216', 'policy', 'campo_extraido.campo_extraido_por_mandato', 'FROM documento_versao', null,
   'Sem a policy por mandato de campo_extraido (ou com ela voltada a using (true)) todo usuário logado lê e grava as linhas dos mandatos alheios — o caso desta tabela vem do pai (documento_versao).',
   'bloqueante', 956),
  ('mandato_documento_fato_por_mandato', '0216', 'policy', 'documento_fato.documento_fato_por_mandato', 'FROM documento_versao', null,
   'Sem a policy por mandato de documento_fato (ou com ela voltada a using (true)) todo usuário logado lê e grava as linhas dos mandatos alheios — o caso desta tabela vem do pai (documento_versao).',
   'bloqueante', 957),
  ('mandato_arquivo_oficial_registro_por_mandato', '0216', 'policy', 'arquivo_oficial_registro.arquivo_oficial_registro_por_mandato', 'FROM arquivo_oficial', null,
   'Sem a policy por mandato de arquivo_oficial_registro (ou com ela voltada a using (true)) todo usuário logado lê e grava as linhas dos mandatos alheios — o caso desta tabela vem do pai (arquivo_oficial).',
   'bloqueante', 958),
  ('mandato_arquivo_oficial_lancamento_mes_por_mandato', '0216', 'policy', 'arquivo_oficial_lancamento_mes.arquivo_oficial_lancamento_mes_por_mandato', 'FROM arquivo_oficial', null,
   'Sem a policy por mandato de arquivo_oficial_lancamento_mes (ou com ela voltada a using (true)) todo usuário logado lê e grava as linhas dos mandatos alheios — o caso desta tabela vem do pai (arquivo_oficial).',
   'bloqueante', 959),
  ('mandato_caso_pergunta_read', '0216', 'policy', 'caso_pergunta.caso_pergunta_read', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy caso_pergunta_read (select em caso_pergunta) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 960),
  ('mandato_caso_pergunta_insert', '0216', 'policy', 'caso_pergunta.caso_pergunta_insert', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy caso_pergunta_insert (insert em caso_pergunta) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 961),
  ('mandato_caso_pergunta_reapontar', '0216', 'policy', 'caso_pergunta.caso_pergunta_reapontar', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy caso_pergunta_reapontar (update em caso_pergunta) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 962),
  ('mandato_controlador_read', '0216', 'policy', 'controlador.controlador_read', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy controlador_read (select em controlador) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 963),
  ('mandato_controlador_insert', '0216', 'policy', 'controlador.controlador_insert', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy controlador_insert (insert em controlador) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 964),
  ('mandato_controlador_vinculo_read', '0216', 'policy', 'controlador_vinculo.controlador_vinculo_read', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy controlador_vinculo_read (select em controlador_vinculo) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 965),
  ('mandato_controlador_vinculo_insert', '0216', 'policy', 'controlador_vinculo.controlador_vinculo_insert', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy controlador_vinculo_insert (insert em controlador_vinculo) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 966),
  ('mandato_controlador_vinculo_update', '0216', 'policy', 'controlador_vinculo.controlador_vinculo_update', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy controlador_vinculo_update (update em controlador_vinculo) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 967),
  ('mandato_entidade_controlador_read', '0216', 'policy', 'entidade_controlador.entidade_controlador_read', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy entidade_controlador_read (select em entidade_controlador) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 968),
  ('mandato_entidade_controlador_insert', '0216', 'policy', 'entidade_controlador.entidade_controlador_insert', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy entidade_controlador_insert (insert em entidade_controlador) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 969),
  ('mandato_entidade_controlador_update', '0216', 'policy', 'entidade_controlador.entidade_controlador_update', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy entidade_controlador_update (update em entidade_controlador) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 970),
  ('mandato_perimetro_read', '0216', 'policy', 'perimetro.perimetro_read', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy perimetro_read (select em perimetro) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 971),
  ('mandato_perimetro_insert', '0216', 'policy', 'perimetro.perimetro_insert', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy perimetro_insert (insert em perimetro) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 972),
  ('mandato_perimetro_update', '0216', 'policy', 'perimetro.perimetro_update', 'fn_meus_casos', null,
   'Sem a restrição por mandato na policy perimetro_update (update em perimetro) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 973),
  ('mandato_campo_classe_override_read', '0216', 'policy', 'campo_classe_override.campo_classe_override_read', 'FROM campo_extraido', null,
   'Sem a restrição por mandato na policy campo_classe_override_read (select em campo_classe_override) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 974),
  ('mandato_campo_classe_override_insert', '0216', 'policy', 'campo_classe_override.campo_classe_override_insert', 'FROM campo_extraido', null,
   'Sem a restrição por mandato na policy campo_classe_override_insert (insert em campo_classe_override) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 975),
  ('mandato_campo_classe_sugerida_read', '0216', 'policy', 'campo_classe_sugerida.campo_classe_sugerida_read', 'FROM campo_extraido', null,
   'Sem a restrição por mandato na policy campo_classe_sugerida_read (select em campo_classe_sugerida) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 976),
  ('mandato_campo_classe_sugerida_insert', '0216', 'policy', 'campo_classe_sugerida.campo_classe_sugerida_insert', 'FROM campo_extraido', null,
   'Sem a restrição por mandato na policy campo_classe_sugerida_insert (insert em campo_classe_sugerida) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 977),
  ('mandato_golden_documento_read', '0216', 'policy', 'golden_documento.golden_documento_read', 'FROM documento', null,
   'Sem a restrição por mandato na policy golden_documento_read (select em golden_documento) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 978),
  ('mandato_golden_documento_insert', '0216', 'policy', 'golden_documento.golden_documento_insert', 'FROM documento', null,
   'Sem a restrição por mandato na policy golden_documento_insert (insert em golden_documento) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 979),
  ('mandato_golden_campo_read', '0216', 'policy', 'golden_campo.golden_campo_read', 'FROM documento', null,
   'Sem a restrição por mandato na policy golden_campo_read (select em golden_campo) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 980),
  ('mandato_golden_campo_insert', '0216', 'policy', 'golden_campo.golden_campo_insert', 'FROM documento', null,
   'Sem a restrição por mandato na policy golden_campo_insert (insert em golden_campo) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 981),
  ('mandato_golden_rotulo_read', '0216', 'policy', 'golden_rotulo.golden_rotulo_read', 'FROM documento', null,
   'Sem a restrição por mandato na policy golden_rotulo_read (select em golden_rotulo) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 982),
  ('mandato_golden_rotulo_insert', '0216', 'policy', 'golden_rotulo.golden_rotulo_insert', 'FROM documento', null,
   'Sem a restrição por mandato na policy golden_rotulo_insert (insert em golden_rotulo) o usuário logado alcança os mandatos alheios por esta operação.',
   'bloqueante', 983),
  ('mandato_caso_select', '0216', 'policy', 'caso.caso_select', 'fn_meus_casos', null,
   'Sem a restrição por mandato em caso_select o usuário logado lê/altera/apaga o mandato alheio.',
   'bloqueante', 984),
  ('mandato_caso_update', '0216', 'policy', 'caso.caso_update', 'fn_meus_casos', null,
   'Sem a restrição por mandato em caso_update o usuário logado lê/altera/apaga o mandato alheio.',
   'bloqueante', 985),
  ('mandato_caso_delete', '0216', 'policy', 'caso.caso_delete', 'fn_meus_casos', null,
   'Sem a restrição por mandato em caso_delete o usuário logado lê/altera/apaga o mandato alheio.',
   'bloqueante', 986),
  ('mandato_caso_insert', '0216', 'policy', 'caso.caso_insert', null, null,
   'Sem a policy de insert em caso o portal não cria mandato (42501).',
   'bloqueante', 987),
  ('mandato_evento_auditoria_read', '0216', 'policy', 'evento_auditoria.evento_auditoria_read', 'fn_meus_casos', null,
   'Sem a restrição por mandato o rastro de auditoria (que guarda antes/depois do dado do cliente) é lido por todo usuário logado.',
   'bloqueante', 988),
  ('mandato_evento_auditoria_insert', '0216', 'policy', 'evento_auditoria.evento_auditoria_insert', 'fn_meus_casos', null,
   'Sem a policy o authenticated forja evento no mandato alheio — ou, ausente, o rastro falha (42501).',
   'bloqueante', 989),
  ('mandato_storage_documentos', '0216', 'policy', 'storage.objects.documentos_por_mandato', 'fn_meus_casos', null,
   'Sem a restrição por mandato no bucket documentos todo usuário logado baixa o arquivo original de qualquer mandato (o balanço, o contrato social).',
   'bloqueante', 990),
  ('tabela_evento_caso_id', '0216', 'coluna', 'evento_auditoria.caso_id', null, null,
   'Sem a coluna o evento não tem a que mandato pertencer: a leitura por mandato do rastro não funciona.',
   'bloqueante', 991),
  ('gatilho_evento_caso_id', '0216', 'gatilho', 'evento_auditoria.trg_evento_caso_id', null, null,
   'Sem o gatilho (ou desabilitado) o evento novo nasce sem caso_id e só o administrador o lê: o membro deixa de ver o rastro do próprio mandato, calado.',
   'bloqueante', 992),
  ('fn_meus_casos', '0216', 'funcao', 'fn_meus_casos', null, null,
   'Toda policy por mandato chama; sem ela (ou sem EXECUTE) o portal inteiro leva "permission denied" ou zero linhas.',
   'bloqueante', 993),
  ('fn_caso_nome_existe', '0216', 'funcao', 'fn_caso_nome_existe', null, null,
   'fn_upsert_caso e o gatilho de nome único a chamam; sem ela o não membro volta a criar mandato duplicado (ou a função morre).',
   'bloqueante', 994),
  ('fn_caso_da_chave', '0216', 'funcao', 'fn_caso_da_chave', null, null,
   'A policy do bucket documentos chama; sem ela ninguém lê o arquivo original.',
   'bloqueante', 995),
  ('fn_caso_da_referencia', '0216', 'funcao', 'fn_caso_da_referencia', null, null,
   'O gatilho do evento chama; sem ela todo insert de evento falha.',
   'bloqueante', 996),
  ('fn_trg_evento_caso_id', '0216', 'funcao', 'fn_trg_evento_caso_id', null, null,
   'O gatilho do evento chama.',
   'bloqueante', 997),
  ('fn_0216_exige_administrador', '0216', 'funcao', 'fn_0216_exige_administrador', null, null,
   'Guarda da 0216 (sinal positivo de administrador).',
   'informativo', 998),
  ('exec_meus_casos_authenticated', '0216', 'execucao', 'authenticated:fn_meus_casos', 'sim', null,
   'authenticated não executa fn_meus_casos: a policy por mandato (ou fn_upsert_caso) leva "permission denied" e a tela quebra.',
   'bloqueante', 999),
  ('exec_caso_da_chave_authenticated', '0216', 'execucao', 'authenticated:fn_caso_da_chave', 'sim', null,
   'authenticated não executa fn_caso_da_chave: a policy por mandato (ou fn_upsert_caso) leva "permission denied" e a tela quebra.',
   'bloqueante', 1001),
  ('exec_caso_da_referencia_authenticated', '0216', 'execucao', 'authenticated:fn_caso_da_referencia', 'sim', null,
   'authenticated não executa fn_caso_da_referencia: a policy por mandato (ou fn_upsert_caso) leva "permission denied" e a tela quebra.',
   'bloqueante', 1002),
  ('exec_exige_admin_authenticated', '0216', 'execucao', 'authenticated:fn_0216_exige_administrador', 'nao', null,
   'authenticated executa a guarda da 0216 (inofensiva, mas não é do portal).',
   'informativo', 1003),
  ('upsert_caso_guarda_membro', '0216', 'corpo', 'fn_upsert_caso', 'fn_caso_nome_existe', null,
   'fn_upsert_caso com o corpo ANTERIOR à 0216: o não membro cria mandato duplicado com o nome de um existente (a RLS esconde o original).',
   'bloqueante', 1009),
  ('mudar_dial_recusa_sem_permissao', '0216', 'corpo', 'fn_mudar_dial', 'v_linhas', null,
   'fn_mudar_dial sem a guarda de linhas: quem não é administrador "muda" o dial (a RLS recusa o UPDATE), a função grava o evento e devolve sucesso — uma trilha que afirma o contrário do estado.',
   'bloqueante', 1010),
  ('veredito_producao_guarda_membro', '0216', 'corpo', 'fn_veredito_producao', 'fn_eh_membro', null,
   'fn_veredito_producao com o corpo ANTERIOR à 0216: definer sem a guarda de p_caso_id abriria o número de qualquer mandato.',
   'bloqueante', 1011),
  ('classe_contabil_guarda_membro', '0216', 'corpo', 'fn_classe_contabil_concordancia', 'fn_eh_membro', null,
   'fn_classe_contabil_concordancia com o corpo ANTERIOR à 0216: definer sem a guarda de p_caso_id abriria o número de qualquer mandato.',
   'bloqueante', 1012),
  ('primeiro_administrador', '0216', 'comportamento', 'administrador', null, 1,
   'A tabela administrador está VAZIA: a 0216 esconde de todos os usuários o mandato sem membro (o que o n8n cria nasce sem membro) e ninguém tem como atribuí-lo ou vê-lo. Rode no SQL Editor: select fn_administrador_definir(''<e-mail do dono>'', true); — comportamento que nenhum CI satisfaz, como custo_gravado_pelo_n8n. Lida como o chamador: quem não é administrador enxerga a tabela vazia pela RLS, então a conferência vale para o dono/CI (postgres), não para o authenticated.',
   'bloqueante', 1013),
  ('mandato_estagio_autonomia_write', '0216', 'policy', 'estagio_autonomia.estagio_autonomia_write', 'fn_eh_admin', null,
   'Sem a escrita restrita ao administrador em estagio_autonomia (policy estagio_autonomia_write voltada a true) todo usuário logado altera o dial/catálogo sem passar por fn_mudar_dial: o teto de autonomia é doutrina.',
   'bloqueante', 1014),
  ('mandato_premissa_catalogo_write', '0216', 'policy', 'premissa_catalogo.premissa_catalogo_write', 'fn_eh_admin', null,
   'Sem a escrita restrita ao administrador em premissa_catalogo (policy premissa_catalogo_write voltada a true) todo usuário logado altera o dial/catálogo sem passar por fn_mudar_dial: o teto de autonomia é doutrina.',
   'bloqueante', 1015),
  ('mandato_golden_criterio_write', '0216', 'policy', 'golden_criterio.golden_criterio_write', 'fn_eh_admin', null,
   'Sem a escrita restrita ao administrador em golden_criterio (policy golden_criterio_write voltada a true) todo usuário logado altera o dial/catálogo sem passar por fn_mudar_dial: o teto de autonomia é doutrina.',
   'bloqueante', 1016),
  ('mandato_golden_rodada_insert', '0216', 'policy', 'golden_rodada.golden_rodada_insert', 'fn_eh_admin', null,
   'Sem a escrita restrita ao administrador em golden_rodada (policy golden_rodada_insert voltada a true) todo usuário logado altera o dial/catálogo sem passar por fn_mudar_dial: o teto de autonomia é doutrina.',
   'bloqueante', 1017),
  ('mandato_golden_rodada_update', '0216', 'policy', 'golden_rodada.golden_rodada_update', 'fn_eh_admin', null,
   'Sem a escrita restrita ao administrador em golden_rodada (policy golden_rodada_update voltada a true) todo usuário logado altera o dial/catálogo sem passar por fn_mudar_dial: o teto de autonomia é doutrina.',
   'bloqueante', 1018),
  ('mandato_execucao_falha_sem_caso', '0216', 'policy', 'execucao_falha.execucao_falha_por_mandato', 'IS NULL', null,
   'execucao_falha_por_mandato sem o ramo de caso_id NULO: a falha de antes de o caso existir some para todos e o /api/intake/status volta ao "aguarde" eterno (0108).',
   'bloqueante', 1019),
  ('rls_arquivo_oficial_lancamento_mes', '0216', 'rls', 'arquivo_oficial_lancamento_mes', null, null,
   'RLS DESLIGADA em arquivo_oficial_lancamento_mes: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1020),
  ('rls_arquivo_oficial_registro', '0216', 'rls', 'arquivo_oficial_registro', null, null,
   'RLS DESLIGADA em arquivo_oficial_registro: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1021),
  ('rls_arquivo_oficial', '0216', 'rls', 'arquivo_oficial', null, null,
   'RLS DESLIGADA em arquivo_oficial: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1022),
  ('rls_campo_classe_override', '0216', 'rls', 'campo_classe_override', null, null,
   'RLS DESLIGADA em campo_classe_override: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1023),
  ('rls_campo_classe_sugerida', '0216', 'rls', 'campo_classe_sugerida', null, null,
   'RLS DESLIGADA em campo_classe_sugerida: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1024),
  ('rls_campo_extraido', '0216', 'rls', 'campo_extraido', null, null,
   'RLS DESLIGADA em campo_extraido: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1025),
  ('rls_caso_apresentacao_campo', '0216', 'rls', 'caso_apresentacao_campo', null, null,
   'RLS DESLIGADA em caso_apresentacao_campo: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1026),
  ('rls_caso_linha_premissa', '0216', 'rls', 'caso_linha_premissa', null, null,
   'RLS DESLIGADA em caso_linha_premissa: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1027),
  ('rls_caso_modelagem', '0216', 'rls', 'caso_modelagem', null, null,
   'RLS DESLIGADA em caso_modelagem: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1028),
  ('rls_caso_pergunta', '0216', 'rls', 'caso_pergunta', null, null,
   'RLS DESLIGADA em caso_pergunta: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1029),
  ('rls_caso_premissa', '0216', 'rls', 'caso_premissa', null, null,
   'RLS DESLIGADA em caso_premissa: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1030),
  ('rls_caso', '0216', 'rls', 'caso', null, null,
   'RLS DESLIGADA em caso: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1031),
  ('rls_checklist_item_status', '0216', 'rls', 'checklist_item_status', null, null,
   'RLS DESLIGADA em checklist_item_status: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1032),
  ('rls_controlador_vinculo', '0216', 'rls', 'controlador_vinculo', null, null,
   'RLS DESLIGADA em controlador_vinculo: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1033),
  ('rls_controlador', '0216', 'rls', 'controlador', null, null,
   'RLS DESLIGADA em controlador: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1034),
  ('rls_decisao', '0216', 'rls', 'decisao', null, null,
   'RLS DESLIGADA em decisao: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1035),
  ('rls_documento_fato', '0216', 'rls', 'documento_fato', null, null,
   'RLS DESLIGADA em documento_fato: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1036),
  ('rls_documento_versao', '0216', 'rls', 'documento_versao', null, null,
   'RLS DESLIGADA em documento_versao: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1037),
  ('rls_documento', '0216', 'rls', 'documento', null, null,
   'RLS DESLIGADA em documento: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1038),
  ('rls_entidade_controlador', '0216', 'rls', 'entidade_controlador', null, null,
   'RLS DESLIGADA em entidade_controlador: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1039),
  ('rls_entidade', '0216', 'rls', 'entidade', null, null,
   'RLS DESLIGADA em entidade: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1040),
  ('rls_evento_auditoria', '0216', 'rls', 'evento_auditoria', null, null,
   'RLS DESLIGADA em evento_auditoria: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1041),
  ('rls_execucao_falha', '0216', 'rls', 'execucao_falha', null, null,
   'RLS DESLIGADA em execucao_falha: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1042),
  ('rls_golden_campo', '0216', 'rls', 'golden_campo', null, null,
   'RLS DESLIGADA em golden_campo: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1043),
  ('rls_golden_documento', '0216', 'rls', 'golden_documento', null, null,
   'RLS DESLIGADA em golden_documento: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1044),
  ('rls_golden_rotulo', '0216', 'rls', 'golden_rotulo', null, null,
   'RLS DESLIGADA em golden_rotulo: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1045),
  ('rls_lote_execucao', '0216', 'rls', 'lote_execucao', null, null,
   'RLS DESLIGADA em lote_execucao: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1046),
  ('rls_pendencia', '0216', 'rls', 'pendencia', null, null,
   'RLS DESLIGADA em pendencia: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1047),
  ('rls_perimetro', '0216', 'rls', 'perimetro', null, null,
   'RLS DESLIGADA em perimetro: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1048),
  ('rls_periodo', '0216', 'rls', 'periodo', null, null,
   'RLS DESLIGADA em periodo: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1049),
  ('rls_reconciliacao', '0216', 'rls', 'reconciliacao', null, null,
   'RLS DESLIGADA em reconciliacao: a policy por mandato continua no catálogo e não vale — todo usuário logado com GRANT lê e grava o mandato alheio nesta tabela, calado.',
   'bloqueante', 1050),
  ('rls_storage_objects', '0216', 'rls', 'storage.objects', null, null,
   'RLS DESLIGADA em storage.objects: a policy do bucket documentos não vale e todo usuário logado baixa o arquivo original de qualquer mandato.',
   'bloqueante', 1051),
  ('rls_golden_criterio', '0216', 'rls', 'golden_criterio', null, null,
   'RLS DESLIGADA em golden_criterio: as policies de escrita só do administrador não valem e todo usuário logado altera o dial/catálogo direto.',
   'bloqueante', 1052),
  ('rls_estagio_autonomia', '0216', 'rls', 'estagio_autonomia', null, null,
   'RLS DESLIGADA em estagio_autonomia: as policies de escrita só do administrador não valem e todo usuário logado altera o dial/catálogo direto.',
   'bloqueante', 1053),
  ('rls_premissa_catalogo', '0216', 'rls', 'premissa_catalogo', null, null,
   'RLS DESLIGADA em premissa_catalogo: as policies de escrita só do administrador não valem e todo usuário logado altera o dial/catálogo direto.',
   'bloqueante', 1054),
  ('rls_golden_rodada', '0216', 'rls', 'golden_rodada', null, null,
   'RLS DESLIGADA em golden_rodada: as policies de escrita só do administrador não valem e todo usuário logado altera o dial/catálogo direto.',
   'bloqueante', 1055),
  ('gatilho_caso_nome_unico', '0216', 'gatilho', 'caso.trg_caso_nome_unico', null, null,
   'Sem o gatilho (ou desabilitado) o não membro cria um segundo mandato com o nome de um existente (insert direto ou rename) e o n8n, que acha o caso pelo nome, pode gravar os documentos de um no outro.',
   'bloqueante', 1056),
  ('fn_trg_caso_nome_unico', '0216', 'funcao', 'fn_trg_caso_nome_unico', null, null,
   'O gatilho de nome único chama; sem ela todo insert/rename de caso por um usuário logado falha.',
   'bloqueante', 1057),
  ('exec_caso_nome_existe_authenticated', '0216', 'execucao', 'authenticated:fn_caso_nome_existe', 'nao', null,
   'authenticated executa fn_caso_nome_existe: oráculo de nomes — qualquer usuário logado pergunta se existe mandato "Projeto X" (em M&A o nome do alvo é informação privilegiada).',
   'bloqueante', 1058),
  ('definer_fn_dial_auto_promover', '0216', 'definer', 'fn_dial_auto_promover', 'sim', null,
   'fn_dial_auto_promover deixou de ser SECURITY DEFINER com search_path fixo: com a RLS por mandato o resultado passa a depender de quem lê (o dial/agregado/falha/pertinência errado, sem erro) ou a função fica sequestrável.',
   'bloqueante', 1059),
  ('definer_fn_veredito_producao', '0216', 'definer', 'fn_veredito_producao', 'sim', null,
   'fn_veredito_producao deixou de ser SECURITY DEFINER com search_path fixo: com a RLS por mandato o resultado passa a depender de quem lê (o dial/agregado/falha/pertinência errado, sem erro) ou a função fica sequestrável.',
   'bloqueante', 1060),
  ('definer_fn_classe_contabil_concordancia', '0216', 'definer', 'fn_classe_contabil_concordancia', 'sim', null,
   'fn_classe_contabil_concordancia deixou de ser SECURITY DEFINER com search_path fixo: com a RLS por mandato o resultado passa a depender de quem lê (o dial/agregado/falha/pertinência errado, sem erro) ou a função fica sequestrável.',
   'bloqueante', 1061),
  ('definer_fn_golden_cobertura', '0216', 'definer', 'fn_golden_cobertura', 'sim', null,
   'fn_golden_cobertura deixou de ser SECURITY DEFINER com search_path fixo: com a RLS por mandato o resultado passa a depender de quem lê (o dial/agregado/falha/pertinência errado, sem erro) ou a função fica sequestrável.',
   'bloqueante', 1062),
  ('definer_fn_falhas_abertas', '0216', 'definer', 'fn_falhas_abertas', 'sim', null,
   'fn_falhas_abertas deixou de ser SECURITY DEFINER com search_path fixo: com a RLS por mandato o resultado passa a depender de quem lê (o dial/agregado/falha/pertinência errado, sem erro) ou a função fica sequestrável.',
   'bloqueante', 1063),
  ('definer_fn_upsert_caso', '0216', 'definer', 'fn_upsert_caso', 'sim', null,
   'fn_upsert_caso deixou de ser SECURITY DEFINER com search_path fixo: com a RLS por mandato o resultado passa a depender de quem lê (o dial/agregado/falha/pertinência errado, sem erro) ou a função fica sequestrável.',
   'bloqueante', 1064),
  ('definer_fn_trg_caso_nome_unico', '0216', 'definer', 'fn_trg_caso_nome_unico', 'sim', null,
   'fn_trg_caso_nome_unico deixou de ser SECURITY DEFINER com search_path fixo: com a RLS por mandato o resultado passa a depender de quem lê (o dial/agregado/falha/pertinência errado, sem erro) ou a função fica sequestrável.',
   'bloqueante', 1065),
  ('definer_fn_caso_nome_existe', '0216', 'definer', 'fn_caso_nome_existe', 'sim', null,
   'fn_caso_nome_existe deixou de ser SECURITY DEFINER com search_path fixo: com a RLS por mandato o resultado passa a depender de quem lê (o dial/agregado/falha/pertinência errado, sem erro) ou a função fica sequestrável.',
   'bloqueante', 1066),
  ('definer_fn_meus_casos', '0216', 'definer', 'fn_meus_casos', 'sim', null,
   'fn_meus_casos deixou de ser SECURITY DEFINER com search_path fixo: com a RLS por mandato o resultado passa a depender de quem lê (o dial/agregado/falha/pertinência errado, sem erro) ou a função fica sequestrável.',
   'bloqueante', 1067),
  ('definer_fn_eh_admin', '0216', 'definer', 'fn_eh_admin', 'sim', null,
   'fn_eh_admin deixou de ser SECURITY DEFINER com search_path fixo: com a RLS por mandato o resultado passa a depender de quem lê (o dial/agregado/falha/pertinência errado, sem erro) ou a função fica sequestrável.',
   'bloqueante', 1068),
  ('definer_fn_eh_membro', '0216', 'definer', 'fn_eh_membro', 'sim', null,
   'fn_eh_membro deixou de ser SECURITY DEFINER com search_path fixo: com a RLS por mandato o resultado passa a depender de quem lê (o dial/agregado/falha/pertinência errado, sem erro) ou a função fica sequestrável.',
   'bloqueante', 1069),
  ('definer_fn_trg_caso_criador_membro', '0216', 'definer', 'fn_trg_caso_criador_membro', 'sim', null,
   'fn_trg_caso_criador_membro deixou de ser SECURITY DEFINER com search_path fixo: com a RLS por mandato o resultado passa a depender de quem lê (o dial/agregado/falha/pertinência errado, sem erro) ou a função fica sequestrável.',
   'bloqueante', 1070),
  ('invoker_fn_mudar_dial', '0216', 'definer', 'fn_mudar_dial', 'nao', null,
   'fn_mudar_dial virou SECURITY DEFINER: qualquer usuário logado muda o dial com os poderes do dono (o teto é doutrina; a escrita direta é só do administrador).',
   'bloqueante', 1071)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0216', revisado_em = current_date,
       observacao = 'A 0216 troca as policies using (true) das tabelas de dado do cliente por policies por mandato (caso_membro/administrador da 0215), restringe o bucket documentos, dá caso_id ao evento_auditoria (gatilho + backfill) e reemite fn_upsert_caso com a recusa ao não membro. A sonda ganha 125 requisitos (RLS ligada, definer/invoker, policies por mandato e de escrita restrita, o primeiro administrador), o tipo definer, e o ramo policy passa a conferir a EXPRESSÃO da policy (marcador) e policies de storage.'
 where id = true;

commit;
