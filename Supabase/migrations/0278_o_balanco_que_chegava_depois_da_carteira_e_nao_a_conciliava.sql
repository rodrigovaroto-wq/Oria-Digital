-- =============================================================================
-- 0278 — O BALANÇO QUE CHEGAVA DEPOIS DA CARTEIRA E NÃO A CONCILIAVA: a rodada de reconciliações passa a conciliar a carteira de aging
--        (decisão do dono, 13/11/2026; era o "NÃO LIGADO NA RODADA" do cabeçalho da 0274)
-- (Reemite UMA função, fn_reconciliar_caso, mesma assinatura, mesmo retorno (ganha checagens quando há carteira) e mesma ACL; acrescenta 2 requisitos à sonda.
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
-- A OUTRA VIA, `fn_reconciliar_por_documento(doc, 'tudo')` (-> fn_reconciliar_chaves_do_documento): NÃO LIGADA, por decisão. Nenhum chamador de produção a usa (grep em Supabase/ N8N/
-- portal/src, 13/11/2026: o n8n usa 'documento'; o portal não chama nenhuma das duas; o resto são testes e scripts manuais), e ela é POR DOCUMENTO: ligar o aging nela o rodaria uma vez por
-- documento num lote (ela reconcilia a carteira do MANDATO inteiro), o defeito de custo que a 0152 corrigiu (8.500 invocações) um nível acima. O requisito "um balanço novo sempre
-- reconcilia as carteiras vigentes do mandato" vale pela rodada do lote, que é a única via que o n8n usa. TETO: quem chamar 'tudo' à mão para UM balanço e não rodar a rodada
-- do mandato não reconcilia a carteira; o remédio é chamar fn_reconciliar_caso (ou fn_reconciliar_aging_do_caso). Sobe quando 'tudo' ganhar um chamador de produção:
-- ligar em fn_reconciliar_chaves_do_documento só para os tipos BALANCO, BALANCETE e COMBINADO (os únicos que mudam o resultado do aging) e com a mesma guarda de papel.
--
-- PERMISSÃO (decisão declarada). fn_reconciliar_caso é invoker (roda com o papel de quem chama) e o authenticated tem EXECUTE. fn_reconciliar_aging_do_caso é definer e leva 42501
-- de quem não é Sócio, Analista alocado ou a conexão de serviço. Quem chama a rodada de verdade: o n8n (usuário postgres, sem JWT = conexão de serviço; `evento_auditoria` mostra
-- só o ator `sistema:reconciliacao`, 7.599 linhas e nenhum usuário) e nenhum código do portal. Para a rodada NUNCA falhar por causa do aging, a guarda é feita ANTES da chamada
-- (`fn_conexao_de_servico() or fn_pode_escrever_caso(...)`, a mesma de fn_reconciliar_aging_do_caso): quem não pode escrever no mandato NÃO leva 42501 e NÃO pula em silêncio: a
-- rodada devolve uma checagem `{executado: false, tipo: 'aging', carteiras_vigentes: N, motivo: ...}`, o sinal positivo de que o estágio não rodou (regra 7). Sem carteira vigente não
-- há aviso nenhum (o retorno é o de antes). A alternativa de chamar fn_reconciliar_aging direto por importação foi descartada: ela é só do service_role (revoke da 0274), e a função
-- do mandato já é a porta definer certa; duplicar o laço seria uma segunda implementação da mesma conta. Honestidade sobre o alcance: com documento de tipo conciliável o
-- authenticated Leitura já leva 42501 das checagens clássicas (a RLS de `reconciliacao` exige escrever o mandato), então o aviso só é alcançado hoje por quem chama a rodada
-- de um mandato com carteira e sem documento conciliável; é guarda barata e o teste a mede, não um caso de produção.
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
-- 0152 e 0192), com 16 linhas NOVAS (1 declaração de variável e o bloco do aging, antes do reset final) e 0 linhas existentes modificadas (diff do corpo contra 0192: 122 -> 138 linhas,
-- 16 acrescentadas, 0 removidas). Os marcadores da sonda estão em CÓDIGO, não em comentário.
--
-- CUSTO. O aging roda uma vez por rodada. Mandato sem carteira: um `count(*)` por `caso_id` em aging_importado (a tabela tem o índice único parcial que começa por caso_id; 0 linhas em
-- produção) e nada mais. Com carteira: uma conciliação por carteira vigente (a conta de uma importação, que já era paga a cada importação).
--
-- IDEMPOTÊNCIA. Rodar a rodada duas vezes reaproveita a mesma pendência (fn_registrar_reconciliacao acha por motivo, entidade e data-base) e acrescenta só o histórico em
-- `reconciliacao` (4 linhas para 2 carteiras, como as demais checagens a cada rodada).
--
-- A SONDA (2 requisitos, ordem 1387-1388): o corpo de fn_reconciliar_caso chama a conciliação do aging, e só a chama para quem pode escrever. `instalacao_cobertura` NÃO é rebaixada:
-- a 0300 já a pôs em 0300 e esta usa `greatest`.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/o_balanco_que_chegava_depois_da_carteira_e_nao_a_conciliava.test.sql — 24 asserts
--   (medido: 24 chamadas, 24 execuções, nenhum em laço; reconferido com Supabase/test/medicao-denominador.test.mjs). Cada guarda desligada UMA por vez DENTRO de uma
--   transação (a sabotagem recompõe a função por pg_get_functiondef e ABORTA se o trecho não existe: nenhuma variante deixou de aplicar), o teste inteiro rodado com o assert em
--   `raise warning` (voltou para `raise exception`; log lido atrás de FALHOU) e a transação desfeita. Controle (migration intacta): 0 dos 24 asserts reprovam, 24 execuções.
--   Por guarda desligada, UMA por vez (13/11/2026; as variantes recompõem fn_reconciliar_caso, ou fn_reconciliar_aging na última, por pg_get_functiondef):
--   * a chamada do aging removida: 12 (11 de comportamento: a carteira não concilia depois do balanço, as 2 pendências e o resultado, a idempotência, o retorno, o Analista e a substituída; mais 1 da sonda) ·
--     o aging chamado DENTRO do primeiro laço de chaves (uma vez por chave): 3 (o teste de "uma vez por rodada" e dois do retorno/histórico);
--   * a guarda de papel: sem ela (Leitura leva 42501 do aging): 3 (2 de comportamento + 1 da sonda) · só a conexão de serviço roda (o Analista alocado cai no aviso): 1 comportamento + 1 da sonda = 2 · só quem escreve
--     roda (a conexão de serviço, sem JWT, cai no aviso e a seção 1 inteira não concilia): 10 · pula sem o aviso (silêncio): 1 · aviso mesmo sem carteira vigente: 1 · conta a
--     importação SUBSTITUÍDA como carteira (sem `substituido_em is null`): 1;
--   * a chave de período: sem restaurar no aging E sem o reset final da rodada: 1; só sem o reset final: 0 e só o aging sem restaurar: 0. Os DOIS zeros são resultado e não furo do
--     teste: as duas guardas se cobrem (a chave está '' no ponto da chamada e o aging restaura o que achou), então cada uma sozinha não muda o que o teste observa; só as duas juntas vazam;
--   * a sonda: sem os 2 requisitos: 1. A cobertura rebaixada não é medida: o gatilho trg_instalacao_cobertura_nao_regride barra o rebaixamento (por isso `greatest`).
--   Medido e DESCARTADO por vazio: o assert de que a checagem do aging carrega a chave do balanço lido; desligar a gravação da chave em fn_reconciliar_aging reprovava 0 (a função
--   central cai no período do documento), então ele saiu do teste em vez de ficar como prova que não prova.
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
      v_checagens := v_checagens || fn_reconciliar_aging_do_caso(p_caso_id);
      v_chamadas := v_chamadas + v_vigentes;
    else
      v_checagens := v_checagens || jsonb_build_array(jsonb_build_object(
        'executado', false, 'tipo', 'aging', 'caso_id', p_caso_id, 'carteiras_vigentes', v_vigentes,
        'motivo', 'a conciliação da carteira de aging exige ser Sócio ou Analista alocado neste mandato (ou a conexão de serviço): a carteira não foi conciliada nesta rodada'));
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
  'Roda cada uma das oito checagens de reconciliação sobre a SUA chave (0152). 0192: `order by` em cada laço `select distinct` — determinismo de qual período a pendência carrega quando mais de um é compatível; o aberto/resolvido em si já não depende da ordem (guarda em fn_registrar_reconciliacao). 0192: cada laço grava o período da CHAVE em oria.periodo_chave (lido por fn_registrar_reconciliacao). 0278: no fim, UMA vez por rodada, concilia as carteiras de aging VIGENTES do mandato com o balanço (o balanço que chega depois da carteira a reconcilia); quem não é Sócio, Analista alocado ou a conexão de serviço não leva 42501 por causa do aging: a rodada devolve uma checagem executado=false, tipo aging, com o motivo. Sem carteira vigente o retorno é o de antes. `chamadas` conta uma por carteira vigente.';

-- A SONDA. Marcadores em CÓDIGO, nunca de comentário.
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('rodada_concilia_o_aging', '0278', 'corpo', 'fn_reconciliar_caso', 'fn_reconciliar_aging_do_caso(', null,
   'A rodada de reconciliações concilia as carteiras de aging do mandato. Corpo sem isto = o balanço que chega depois da carteira não a reconcilia: ela fica documento_ausente (sem pendência) para sempre, com a cara de "nada a conciliar".',
   'importante', 1387),
  ('rodada_aging_so_para_quem_pode', '0278', 'corpo', 'fn_reconciliar_caso', 'fn_pode_escrever_caso(p_caso_id)', null,
   'A rodada só chama o aging para quem pode escrever no mandato e avisa (executado=false) quando pula. Corpo sem isto = o Leitura que chama a rodada leva 42501 do aging (a rodada inteira falha) ou o aging é pulado sem sinal.',
   'importante', 1388)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

-- A cobertura NUNCA é rebaixada: a 0300 (aplicada antes desta em produção, 13/11) já a pôs em 0300; gravar '0278' faria a sonda tratar 0279-0300 como fora da cobertura.
update instalacao_cobertura
   set ate_migration = greatest(ate_migration, '0278'), revisado_em = current_date,
       observacao = coalesce(observacao || ' ', '') || '0278: fn_reconciliar_caso passa a conciliar a carteira de aging do mandato (uma vez por rodada), com aviso executado=false para quem não pode escrever; reemite só ela, mesma assinatura e ACL; requisitos 1387-1388.'
 where id = true;

commit;
