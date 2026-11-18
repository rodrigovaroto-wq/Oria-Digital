-- =============================================================================
-- 0278 — O BALANÇO QUE CHEGAVA DEPOIS DA CARTEIRA E NÃO A CONCILIAVA: a rodada de reconciliações passa a conciliar a carteira de aging
--        (decisão do dono, 13/11/2026; era o "NÃO LIGADO NA RODADA" do cabeçalho da 0274)
-- (Reemite UMA função, fn_reconciliar_caso, mesma assinatura, mesmo retorno (ganha checagens quando há carteira) e mesma ACL; cria UMA função auxiliar, fn_rastro_aging_nao_conciliado
--  (o rastro durável do "não conciliou"); acrescenta 5 requisitos à sonda.
--  Nenhuma tabela, nenhum backfill, nenhuma linha de dado tocada. Produção em 13/11/2026 (só leitura): aging_importado = 0 linhas, 0 pendências e 0 checagens do aging,
--  81 mandatos, 7.599 reconciliações em 55 mandatos (no máximo 2.215 num mandato): a migration não muda NADA em produção até a primeira carteira ser importada.)
--
-- O DEFEITO. A carteira de aging (0274) concilia com o balanço extraído na hora em que é IMPORTADA (fn_aging_importar) e quando alguém chama
-- fn_reconciliar_aging_do_caso à mão. O balanço que chega DEPOIS da carteira (o caso normal: o analista sobe o contas a receber da empresa antes de a IA terminar de ler o
-- balanço, ou o balanço novo substitui um velho) não a reconcilia: a carteira fica `documento_ausente` (sem pendência, com a cara de "nada a conciliar") para sempre, porque
-- a rodada de produção do n8n não a chama. Reproduzido no teste desta migration, na forma de produção: carteira importada com a entidade conhecida por uma DRE -> documento_ausente;
-- balanço registrado -> continua documento_ausente (medido: 0 checagens conciliadas antes da rodada); rodada -> ok / divergente. Estado de produção em 13/11/2026 (leitura):
-- nenhuma carteira importada ainda, então nenhuma foi deixada para trás; o defeito era latente e aparece na primeira importação.
--
-- ONDE LIGA, E POR QUÊ AÍ (decisão declarada). Em fn_reconciliar_caso, UMA vez no fim, depois dos laços de chave. É o ponto por onde a rodada de produção passa: o n8n chama
-- `fn_reconciliar_por_documento(doc, 'documento')` por documento (só a árvore, intra-documento) e UMA `fn_reconciliar_caso(caso)` no fim do lote (N8N/build-workflow.mjs, nó
-- `Reconciliar Lote`; grep em 13/11/2026). O aging é do MANDATO (carteira por entidade e data-base), não de uma chave (entidade, período), então roda uma vez por rodada: o teste mede
-- que um mandato com 3 entidades e 2 períodos de balanço grava as 2 checagens de UMA carteira, não uma por chave. Está depois dos laços para a chave de período (0192) estar vazia
-- quando ele roda e porque o aging escolhe o seu balanço pela data-base, sem depender dos laços.
--
-- A OUTRA VIA, `fn_reconciliar_por_documento(doc, 'tudo')` (-> fn_reconciliar_chaves_do_documento): NÃO LIGADA, por decisão. O n8n de produção usa 'documento' e o portal não chama
-- nenhuma das duas (grep em Supabase/ N8N/ portal/src, 13/11/2026), MAS há UM chamador de 'tudo' em produção: fn_reconferir_caso (0240), que chama
-- `fn_reconciliar_por_documento(v_doc.id)` sem 2º argumento (= 'tudo') por documento do mandato e NUNCA chama fn_reconciliar_caso. Hoje sem efeito (0 eventos `reconferir_caso` em produção,
-- 13/11/2026), mas quando o "Mandato reconferido" for ligado o reprocesso NÃO concilia a carteira. Ligar o aging em 'tudo' o rodaria uma vez por documento num lote (ele reconcilia a carteira
-- do MANDATO inteiro), o defeito de custo que a 0152 corrigiu (8.500 invocações) um nível acima. TETO: quem chamar 'tudo' (à mão, ou via fn_reconferir_caso) e não rodar a rodada do mandato não
-- reconcilia a carteira. O ponto certo para ligar seria fn_reconferir_caso (UMA chamada de fn_reconciliar_caso no fim do laço de documentos, não por documento; não reemitida aqui). Sobe
-- quando o "Mandato reconferido" ganhar o ponto de entrada em produção.
--
-- PERMISSÃO (decisão declarada). fn_reconciliar_caso é invoker (roda com o papel de quem chama) e o authenticated tem EXECUTE. fn_reconciliar_aging_do_caso é definer e leva 42501
-- de quem não é Sócio, Analista alocado ou a conexão de serviço. Quem chama a rodada de verdade: o n8n (usuário postgres, sem JWT = conexão de serviço; `evento_auditoria` mostra
-- só o ator `sistema:reconciliacao`, 7.599 linhas e nenhum usuário) e nenhum código do portal. Para a rodada NUNCA falhar por causa do aging, a guarda é feita ANTES da chamada
-- (`fn_conexao_de_servico() or fn_pode_escrever_caso(...)`, a mesma de fn_reconciliar_aging_do_caso): quem não pode escrever no mandato NÃO leva 42501 e NÃO pula em silêncio: a
-- rodada devolve uma checagem `{executado: false, tipo: 'aging', carteiras_vigentes: N, motivo: ...}`, E grava o rastro DURÁVEL em evento_auditoria (regra 7: o retorno ninguém lê, o nó n8n não o lê; ver O AGING NUNCA DERRUBA A RODADA). Sem carteira vigente não
-- há aviso nenhum (o retorno é o de antes). A alternativa de chamar fn_reconciliar_aging direto por importação foi descartada: ela é só do service_role (revoke da 0274), e a função
-- do mandato já é a porta definer certa; duplicar o laço seria uma segunda implementação da mesma conta. Honestidade sobre o alcance: com documento de tipo conciliável o
-- authenticated Leitura já leva 42501 das checagens clássicas (a RLS de `reconciliacao` exige escrever o mandato), então o aviso só é alcançado hoje por quem chama a rodada
-- de um mandato com carteira e sem documento conciliável; é guarda barata e o teste a mede, não um caso de produção.
--
-- O AGING NUNCA DERRUBA A RODADA, e o rastro. A guarda acima só cobre permissão; qualquer outra exceção em fn_reconciliar_aging_do_caso desfazia o fn_reconciliar_caso INTEIRO, e o nó
-- n8n `Reconciliar Lote` é onError=continueRegularOutput (N8N/build-workflow.mjs) com a saída sem leitor: as checagens clássicas do lote sumiam sem pendência e sem log. Medido (aging
-- sabotado com 1/0 no mandato do teste): a rodada gravava 0 linhas em vez de 18. A chamada do aging fica numa SUBTRANSAÇÃO (`begin ... exception when others`): só o aging é desfeito, as
-- clássicas ficam. A rodada devolve `{executado: false, tipo: 'aging', motivo: sqlerrm, sqlstate, carteiras_vigentes}` E fn_rastro_aging_nao_conciliado grava uma linha em evento_auditoria
-- (ator sistema:reconciliacao, acao aging_nao_conciliado_na_rodada, entidade_ref caso:<id>, depois com motivo/sqlstate/carteiras_vigentes), nos DOIS casos (exceção e sem permissão). A função é
-- DEFINER porque o Leitura (o caso do aviso de permissão) não insere em evento_auditoria; só grava para a conexão de serviço ou quem lê o mandato, e nunca levanta erro. LIMITE: quem lê o
-- mandato pode chamá-la direto e gravar uma linha de ruído (ator e acao fixos, motivo livre); nada do produto lê esta acao. O 42501 que a guarda de papel evita agora seria pego pela
-- subtransação do mesmo jeito (defesa em profundidade): por isso a sabotagem "sem a guarda" reprova menos asserts do que reprovaria sem o `exception`.
--
-- A CHAVE DE PERÍODO (0192). fn_reconciliar_aging salva `oria.periodo_chave`, grava a do balanço que lê e a RESTAURA; a chamada vem depois do último laço (a chave está '' ali, pelo
-- reset que a 0192 já faz antes dos laços por entidade) e o reset final da rodada continua. Medido no teste: depois da rodada a chave vale '' mesmo começando de uma chave posta
-- por fora, e a checagem do aging carrega o período do balanço lido (anual 2025), nunca o do último laço (2024).
--
-- O QUE MUDA NO RETORNO. Mesma assinatura (uuid) -> jsonb e mesmo formato `{executado, caso_id, documentos, chamadas, checagens}`. Com carteira vigente: `checagens` ganha as
-- checagens do aging (2 por carteira de contas a receber ou a pagar: clientes/fornecedores e adiantamentos; o mesmo formato das demais) e `chamadas` ganha UMA por carteira vigente
-- (uma chamada a fn_reconciliar_aging; por isso, com carteira, `chamadas` deixa de ser igual ao tamanho de `checagens`, que era uma identidade de construção e que nenhum chamador usa).
-- Sem carteira: retorno idêntico ao de antes (medido: chamadas = tamanho de `checagens`, nenhuma linha do aging, nenhum aviso). Chamadores de fn_reconciliar_caso (grep -rn em Supabase/
-- N8N/ portal/src, 13/11/2026): o nó n8n `Reconciliar Lote` (que não lê o retorno: o nó seguinte, `Resumo de Custo`, lê os outros nós por nome e não a saída dele), as migrations 0152/0192 (definição) e 0274/0277
-- (só citam), a sonda e os testes (`reconciliacao_do_lote`, `divergencia_vigente_entre_rodadas`, `motivo_especifico`, `o_quadro_de_imobilizado...`, `o_aging_...`) que leem `chamadas` e
-- `documentos` num mandato sem carteira (inalterados) ou o conjunto de linhas. O portal não chama. Nada quebra com checagens novas no array: nenhum consumidor as itera.
-- fn_reconciliar_aging_do_caso e fn_reconciliar_aging NÃO mudam.
--
-- O CORPO. fn_reconciliar_caso reemitida a partir do corpo VIGENTE (0192:556, a única versão depois da 0152; grep -ln "function fn_reconciliar_caso" Supabase/migrations/*.sql dá só
-- 0152 e 0192), com 26 linhas NOVAS (1 declaração de variável e o bloco do aging, antes do reset final) e 0 linhas existentes modificadas (diff do corpo contra 0192: 122 -> 148 linhas,
-- 26 acrescentadas, 0 removidas). Os marcadores da sonda estão em CÓDIGO, não em comentário.
--
-- CUSTO. O aging roda uma vez por rodada. Mandato sem carteira: um `count(*)` por `caso_id` em aging_importado (a tabela tem o índice único parcial que começa por caso_id; 0 linhas em
-- produção) e nada mais. Com carteira: uma conciliação por carteira vigente (a conta de uma importação, que já era paga a cada importação).
--
-- IDEMPOTÊNCIA. Rodar a rodada duas vezes reaproveita a mesma pendência (fn_registrar_reconciliacao acha por motivo, entidade e data-base) e acrescenta só o histórico em
-- `reconciliacao` (4 linhas para 2 carteiras, como as demais checagens a cada rodada).
--
-- A SONDA (5 requisitos, ordem 1387-1391): o corpo de fn_reconciliar_caso chama a conciliação do aging, só a chama para quem pode escrever (ou a conexão de serviço: o marcador é o trecho
-- `fn_conexao_de_servico() or fn_pode_escrever_caso(p_caso_id)`, que pega a remoção de qualquer um dos dois), tem a subtransação com o rastro da exceção, tem o rastro do aviso de permissão, e a
-- função auxiliar grava o evento (os marcadores do `exception` e do rastro são o código que os chama: o portão sonda_marcador_e_codigo recusa marcador sem sinal de código). `instalacao_cobertura` NÃO é rebaixada:
-- a 0300 já a pôs em 0300 e esta usa `greatest`.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/o_balanco_que_chegava_depois_da_carteira_e_nao_a_conciliava.test.sql — 32 asserts
--   (medido: 32 chamadas, 32 execuções, nenhum em laço; reconferido com Supabase/test/medicao-denominador.test.mjs). Cada guarda desligada UMA por vez DENTRO de uma
--   transação (a sabotagem recompõe a função por pg_get_functiondef e cada substituição de texto ABORTA se o trecho não existe exatamente uma vez: nenhuma variante deixou de aplicar), o teste
--   inteiro rodado com o assert em `raise warning` (PGOPTIONS='-c ct78.medindo=on'; voltou para `raise exception`; log lido atrás de FALHOU, e o `PASSARAM` aparece em toda variante: a migration
--   aplicou e o teste rodou até o fim) e a transação desfeita. Controle (migration intacta): 0 dos 32 asserts reprovam, 32 execuções.
--   Por guarda desligada, UMA por vez (13/11/2026, remedido depois de acrescentar o `exception`, o rastro e a seção 8 do teste):
--   * a chamada do aging removida (a chamada e o contador): 14 (13 de comportamento: a carteira não concilia depois do balanço, as 2 pendências e o resultado, a idempotência, o retorno, o Analista, a
--     substituída, as várias chaves e 2 da seção 8, que dependem de o aging ser chamado para falhar; mais 1 da sonda) · o aging chamado DENTRO do primeiro laço de chaves (uma vez por chave): 8;
--   * a guarda de papel: sem ela (Leitura leva 42501 do aging, agora pego pela subtransação): 3 (2 de comportamento: o aviso sai com o texto da exceção e não o de permissão, e o rastro de permissão não existe; mais 1 da sonda) ·
--     só a conexão de serviço roda (o Analista alocado cai no aviso): 1 comportamento + 1 da sonda = 2 · só quem escreve roda (a conexão de serviço, sem JWT, cai no aviso e a seção 1 inteira não concilia): 14 ·
--     pula sem o aviso (silêncio): 3 (o aviso e o rastro de permissão; mais 1 da sonda) · aviso mesmo sem carteira vigente: 1 · conta a importação SUBSTITUÍDA como carteira (sem `substituido_em is null`): 1;
--   * o aging que levanta exceção (seção 8; aging sabotado com 1/0 DENTRO do teste, a definição original reposta e conferida no fim): sem o `exception` (a exceção sobe e desfaz a rodada): 4 (a rodada não
--     cai, as clássicas continuam gravadas, o retorno diz que não rodou, o rastro) · sem o rastro no ramo da exceção: 2 (o evento + 1 da sonda, requisito 1389) · sem o rastro no ramo da permissão: 2 (o evento da
--     seção 4 + 1 da sonda, requisito 1390) · a função auxiliar sem o INSERT: 3 (os 2 eventos + 1 da sonda, requisito 1391);
--   * a chave de período: sem o reset final da rodada: 0 (remedido). Os demais itens da chave (sem restaurar no aging E sem o reset final: 1; só o aging sem restaurar: 0) vêm da medição anterior desta mesma
--     migration, com o código e os asserts da seção 6 inalterados (não remedidos). Os zeros são resultado e não furo do teste: as duas guardas se cobrem (a chave está '' no ponto da chamada e o aging
--     restaura o que achou), então cada uma sozinha não muda o que o teste observa; só as duas juntas vazam;
--   * a sonda: sem os 5 requisitos: 1 (o assert da seção 7 conta os 5). A cobertura rebaixada não é medida: o gatilho trg_instalacao_cobertura_nao_regride barra o rebaixamento (por isso `greatest`).
--   Medido e DESCARTADO por vazio: o assert de que a checagem do aging carrega a chave do balanço lido; desligar a gravação da chave em fn_reconciliar_aging reprovava 0 (a função
--     central cai no período do documento), então ele saiu do teste em vez de ficar como prova que não prova.
--   Zero efeito sem carteira, medido além do teste: nos 3 mandatos do banco de teste SEM aging com mais documentos (31, 14 e 28), a rodada nova e a vigente (corpo da 0192, reposto
--   no mesmo banco) devolvem o mesmo `chamadas` (42, 8, 12), o mesmo número de checagens e o mesmo conjunto de linhas por (tipo, resultado, motivo); a 2ª rodada, qualquer que seja a
--   versão, não abre pendência nova.
--
-- LIMITES DITOS. (1) Produção não tem carteira: nada aqui foi observado contra um arquivo real (DM7 pendente); os valores do teste são os do teste da 0277. (2) A guarda de papel só é
-- alcançada hoje por quem chama a rodada de um mandato com carteira e sem documento conciliável (ver PERMISSÃO). (3) 'tudo' não liga o aging (ver A OUTRA VIA). (4) A fusão de
-- entidades (0277) não refaz a conciliação: a próxima rodada reconcilia as vigentes da sobrevivente, que agora é a rodada normal, não uma chamada à mão. (5) `chamadas` com carteira
-- deixa de ser igual ao tamanho de `checagens`.
-- =============================================================================
begin;

-- O RASTRO DURÁVEL. O retorno da rodada ninguém lê (o nó n8n não o lê), então o "não conciliou" precisa de um registro que sobreviva: uma linha em evento_auditoria
-- (caso:<id>, ator sistema:reconciliacao, acao aging_nao_conciliado_na_rodada). Função à parte e DEFINER porque o Leitura (o caso do aviso de permissão) não insere em
-- evento_auditoria (a policy exige escrever o mandato). Guarda: conexão de serviço ou quem LÊ o mandato; os demais não gravam nada (e não levam erro: a rodada nunca falha por causa
-- do rastro; quem não lê o mandato nem enxerga a carteira, o `count` da rodada dá 0 e esta função não é chamada). LIMITE: quem lê o mandato pode chamá-la direto e gravar uma linha de ruído
-- (ator e acao são fixos, o motivo é livre); nenhuma leitura de produto usa esta acao.
create or replace function fn_rastro_aging_nao_conciliado(p_caso_id uuid, p_motivo text, p_sqlstate text, p_carteiras_vigentes int)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not (fn_conexao_de_servico() or fn_pode_ler_caso(p_caso_id)) then return; end if;
  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:reconciliacao', 'aging_nao_conciliado_na_rodada', 'caso:' || p_caso_id,
            jsonb_build_object('motivo', p_motivo, 'sqlstate', p_sqlstate, 'carteiras_vigentes', p_carteiras_vigentes));
end $$;
revoke all on function fn_rastro_aging_nao_conciliado(uuid, text, text, int) from public;
grant execute on function fn_rastro_aging_nao_conciliado(uuid, text, text, int) to authenticated, service_role;
comment on function fn_rastro_aging_nao_conciliado(uuid, text, text, int) is
  '0278: grava em evento_auditoria (caso:<id>, ator sistema:reconciliacao) que a rodada NÃO conciliou a carteira de aging (sem permissão, ou o aging levantou exceção): o retorno da rodada ninguém lê. Definer porque o Leitura não insere em evento_auditoria. Só conexão de serviço ou quem lê o mandato; os demais não gravam e não levam erro.';

create or replace function fn_reconciliar_caso(p_caso_id uuid)
returns jsonb language plpgsql as $$
-- 0152: cada checagem sobre a SUA chave.
-- 0192: `order by` em cada laço — determinismo de qual período a pendência
-- carrega (a guarda de fn_registrar_reconciliacao já não depende da ordem
-- para decidir aberto/resolvido; isto é só reprodutibilidade).
-- 0192 (guarda por CHAVE): cada laço grava em `oria.periodo_chave` o período da chave que visita
-- (set_config local à transação); fn_registrar_reconciliacao o lê e o grava em
-- `reconciliacao.periodo_chave_id`. O laço DESCE a períodos compatíveis (foreach), o que muda o
-- `periodo_id` da linha mas não a chave.
declare
  v_k          record;
  v_per        uuid;
  v_res        jsonb;
  v_checagens  jsonb := '[]'::jsonb;
  v_chamadas   int := 0;
  v_documentos int := 0;
  v_vigentes   int := 0;
  c_arvore     constant text[] := array['BALANCO','BALANCETE','COMBINADO'];
  c_fluxo      constant text[] := array['BALANCO','BALANCETE','COMBINADO','FLUXO_CAIXA'];
  c_receita    constant text[] := array['DRE','FATURAMENTO_24M'];
  c_despfin    constant text[] := array['DRE','MAPA_DIVIDA'];
  c_mutuos     constant text[] := array['MUTUOS','BALANCO','COMBINADO','DF_AUDITADA'];
  c_intra      constant text[] := array['BALANCO','BALANCETE','DF_AUDITADA'];
  c_conflito   constant text[] := array['BALANCO','BALANCETE','COMBINADO','DF_AUDITADA','DRE',
                                        'FLUXO_CAIXA','DMPL','DVA','NOTAS_EXPL'];
begin
  select count(*) into v_documentos from documento where caso_id = p_caso_id;

  -- ---- (entidade, período), com laço de período -----------------------------
  for v_k in select distinct d.entidade_id, d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_arvore)
             order by d.entidade_id, d.periodo_id loop
    perform set_config('oria.periodo_chave', coalesce(v_k.periodo_id::text, ''), true);
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_ativo_passivo_pl(p_caso_id, v_k.entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.entidade_id, d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_fluxo)
             order by d.entidade_id, d.periodo_id loop
    perform set_config('oria.periodo_chave', coalesce(v_k.periodo_id::text, ''), true);
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_caixa_bp_fluxo(p_caso_id, v_k.entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.entidade_id, d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_receita)
             order by d.entidade_id, d.periodo_id loop
    perform set_config('oria.periodo_chave', coalesce(v_k.periodo_id::text, ''), true);
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_receita_dre_vs_faturamento(p_caso_id, v_k.entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.entidade_id, d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_despfin)
             order by d.entidade_id, d.periodo_id loop
    perform set_config('oria.periodo_chave', coalesce(v_k.periodo_id::text, ''), true);
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_despfin_dre_vs_divida(p_caso_id, v_k.entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  -- ---- só (período) — mútuos e intragrupo são do GRUPO, não da empresa ------
  for v_k in select distinct d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_mutuos)
             order by d.periodo_id loop
    perform set_config('oria.periodo_chave', coalesce(v_k.periodo_id::text, ''), true);
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_mutuos(p_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_intra)
             order by d.periodo_id loop
    perform set_config('oria.periodo_chave', coalesce(v_k.periodo_id::text, ''), true);
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_intragrupo(p_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  -- ---- só (entidade) — sem período nenhum ----------------------------------
  -- 0192: sem chave de período; o que o último laço deixou não pode vazar para estas.
  perform set_config('oria.periodo_chave', '', true);
  for v_k in select distinct d.entidade_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_arvore)
             order by d.entidade_id loop
    v_checagens := v_checagens
      || jsonb_build_array(fn_reconciliar_duplicidade(p_caso_id, v_k.entidade_id));
    v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.entidade_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_conflito)
             order by d.entidade_id loop
    v_checagens := v_checagens
      || jsonb_build_array(fn_reconciliar_versoes_do_periodo(p_caso_id, v_k.entidade_id));
    v_chamadas := v_chamadas + 1;
  end loop;

  -- 0278: a carteira de aging (0274/0277) é conciliada com o balanço do mandato TODA vez que a rodada roda, não só na importação: o balanço que chega
  -- depois da carteira a concilia aqui. UMA vez por rodada (não por chave). Sem carteira vigente não há nada abaixo (mesmo retorno de antes).
  -- Quem não pode escrever no mandato não derruba a rodada com 42501: a rodada devolve uma checagem executado=false com o motivo (nunca pula calada).
  select count(*) into v_vigentes from aging_importado where caso_id = p_caso_id and substituido_em is null;
  if v_vigentes > 0 then
    if fn_conexao_de_servico() or fn_pode_escrever_caso(p_caso_id) then
      -- Subtransação: o aging NUNCA derruba a rodada. O nó n8n `Reconciliar Lote` é onError=continueRegularOutput e ninguém lê a saída; uma exceção solta aqui desfazia as
      -- checagens clássicas do lote INTEIRO, sem pendência e sem log (medido: com fn_reconciliar_aging levantando, a rodada gravava 0 linhas em vez de 18). Só o aging é desfeito.
      begin
        v_checagens := v_checagens || fn_reconciliar_aging_do_caso(p_caso_id);
        v_chamadas := v_chamadas + v_vigentes;
      exception when others then
        v_checagens := v_checagens || jsonb_build_array(jsonb_build_object(
          'executado', false, 'tipo', 'aging', 'caso_id', p_caso_id, 'carteiras_vigentes', v_vigentes, 'motivo', sqlerrm, 'sqlstate', sqlstate));
        perform fn_rastro_aging_nao_conciliado(p_caso_id, sqlerrm, sqlstate, v_vigentes);
      end;
    else
      v_checagens := v_checagens || jsonb_build_array(jsonb_build_object(
        'executado', false, 'tipo', 'aging', 'caso_id', p_caso_id, 'carteiras_vigentes', v_vigentes,
        'motivo', 'a conciliação da carteira de aging exige ser Sócio ou Analista alocado neste mandato (ou a conexão de serviço): a carteira não foi conciliada nesta rodada'));
      perform fn_rastro_aging_nao_conciliado(p_caso_id,
        'a conciliação da carteira de aging exige ser Sócio ou Analista alocado neste mandato (ou a conexão de serviço): a carteira não foi conciliada nesta rodada', '42501', v_vigentes);
    end if;
  end if;

  perform set_config('oria.periodo_chave', '', true);
  return jsonb_build_object(
    'executado', true, 'caso_id', p_caso_id,
    'documentos', v_documentos, 'chamadas', v_chamadas,
    'checagens', v_checagens);
end;
$$;

comment on function fn_reconciliar_caso(uuid) is
  'Roda cada uma das oito checagens de reconciliação sobre a SUA chave (0152). 0192: `order by` em cada laço `select distinct` — determinismo de qual período a pendência carrega quando mais de um é compatível; o aberto/resolvido em si já não depende da ordem (guarda em fn_registrar_reconciliacao). 0192: cada laço grava o período da CHAVE em oria.periodo_chave (lido por fn_registrar_reconciliacao). 0278: no fim, UMA vez por rodada, concilia as carteiras de aging VIGENTES do mandato com o balanço (o balanço que chega depois da carteira a reconcilia); quem não é Sócio, Analista alocado ou a conexão de serviço não leva 42501 por causa do aging: a rodada devolve uma checagem executado=false, tipo aging, com o motivo, e grava o rastro em evento_auditoria (aging_nao_conciliado_na_rodada); o mesmo vale se o aging levantar qualquer exceção (subtransação: as checagens clássicas do lote ficam). Sem carteira vigente o retorno é o de antes. `chamadas` conta uma por carteira vigente.';

-- A SONDA. Marcadores em CÓDIGO, nunca de comentário.
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('rodada_concilia_o_aging', '0278', 'corpo', 'fn_reconciliar_caso', 'fn_reconciliar_aging_do_caso(', null,
   'A rodada de reconciliações concilia as carteiras de aging do mandato. Corpo sem isto = o balanço que chega depois da carteira não a reconcilia: ela fica documento_ausente (sem pendência) para sempre, com a cara de "nada a conciliar".',
   'importante', 1387),
  ('rodada_aging_so_para_quem_pode', '0278', 'corpo', 'fn_reconciliar_caso', 'fn_conexao_de_servico() or fn_pode_escrever_caso(p_caso_id)', null,
   'A rodada só chama o aging para quem pode escrever no mandato (ou a conexão de serviço) e avisa (executado=false) quando pula. Corpo sem isto = o Leitura que chama a rodada leva 42501 do aging (a rodada inteira falha) ou o aging é pulado sem sinal, ou o n8n (sem JWT) deixa de conciliar.',
   'importante', 1388),
  ('rodada_aging_nao_derruba_a_rodada', '0278', 'corpo', 'fn_reconciliar_caso', 'fn_rastro_aging_nao_conciliado(p_caso_id, sqlerrm, sqlstate', null,
   'A chamada do aging fica numa subtransação (exception when others) que grava o rastro com sqlerrm e sqlstate: qualquer exceção dele desfaz só o aging. Corpo sem isto = uma exceção em fn_reconciliar_aging desfaz as checagens clássicas do lote inteiro, sem pendência e sem log (o nó n8n é continueRegularOutput e ninguém lê a saída).',
   'importante', 1389),
  ('rodada_aging_deixa_rastro', '0278', 'corpo', 'fn_reconciliar_caso', '''42501'', v_vigentes)', null,
   'Quando a rodada pula o aging por falta de permissão, ela grava o rastro (o ramo da exceção tem o seu requisito) em evento_auditoria: o retorno ninguém lê. Corpo sem isto = estágio que não rodou com a cara de estágio que rodou e não achou nada (regra 7).',
   'importante', 1390),
  ('rodada_aging_rastro_grava_evento', '0278', 'corpo', 'fn_rastro_aging_nao_conciliado', 'aging_nao_conciliado_na_rodada', null,
   'fn_rastro_aging_nao_conciliado grava a linha em evento_auditoria. Corpo sem isto = a função existe e o rastro some.',
   'importante', 1391)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

-- A cobertura NUNCA é rebaixada: a 0300 (aplicada antes desta em produção, 13/11) já a pôs em 0300; gravar '0278' faria a sonda tratar 0279-0300 como fora da cobertura.
update instalacao_cobertura
   set ate_migration = greatest(ate_migration, '0278'), revisado_em = current_date,
       observacao = coalesce(observacao || ' ', '') || '0278: fn_reconciliar_caso passa a conciliar a carteira de aging do mandato (uma vez por rodada), com aviso executado=false e rastro em evento_auditoria para quem não pode escrever ou quando o aging levanta exceção (subtransação); reemite ela (mesma assinatura e ACL) e cria fn_rastro_aging_nao_conciliado; requisitos 1387-1391.'
 where id = true;

commit;
