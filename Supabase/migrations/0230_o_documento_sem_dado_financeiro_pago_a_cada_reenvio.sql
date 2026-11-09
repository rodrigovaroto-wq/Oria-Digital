-- =============================================================================
-- 0230 — O DOCUMENTO SOCIETÁRIO SEM DADO FINANCEIRO QUE O REENVIO PAGAVA DE NOVO (P7: retomar um lote custa só o que ainda não foi extraído)
-- (Cria 1 função, fn_versao_extracao_concluida (SQL, stable, SECURITY INVOKER, somente leitura); reemite fn_registrar_documento com a MESMA assinatura (17 args), o MESMO
--  retorno e a MESMA ACL — só a pergunta "esta versão já foi extraída?" muda, e passa a morar na função nova. Acrescenta 3 requisitos à sonda. Sem tabela, sem gatilho, sem backfill.)
--
-- O DEFEITO. O reenvio do mesmo arquivo pula a extração paga (`reaproveitou_extracao = true`, 0118) só quando a versão antiga TEM linha em `campo_extraido`. A certidão e o
-- organograma, que não têm tabela financeira, têm ZERO linha por natureza (a 0111 já diz que isso não é falha) e são pagos de novo a cada reenvio do lote.
-- Medido em PRODUÇÃO em 09/11/2026 (somente leitura): 125 documentos têm extração feita, zero linha e nenhuma falha aberta; 72 deles têm no último evento `extracao_sombra`
-- `tem_dado_financeiro = false` explícito e `falha_motivo` nulo.
--
-- A CAUSA. A 0118 usou "existe linha" como PROXY de "a extração terminou". Para o documento sem o que extrair o proxy erra. A informação já é gravada por versão em
-- `fn_registrar_campos_extraidos`: o evento `extracao_sombra` leva `falha_motivo`, `tem_dado_financeiro` e `medicao` (formato conferido na 0229).
--
-- POR QUE A DECLARAÇÃO DA IA NÃO BASTA (medido em produção em 09/11/2026). Os 71 documentos que uma versão larga desta migration passaria a pular (última versão, zero linha,
-- último evento sem falha e com `tem_dado_financeiro = false`), por tipo:
--     CERTIDOES 16, ORGANOGRAMA 11, CONTRATO_SOCIAL 3 (categoria `Societário/Legal`) ................ 30
--     DF_AUDITADA 16 (2 com medicao.contas_no_documento > 0), NOTAS_EXPL 12 .......................... 28
--     DRE 5 e BALANCO 3 (arquivos .txt), FATURAMENTO_24M 2, EXTRATO_BANCARIO 2, MAPA_DIVIDA 1 ........ 13
--   1 ORGANOGRAMA tem contas_no_documento > 0; só 4 dos 71 eventos têm medição (os demais são anteriores à 0229).
-- Ou seja, 41 dos 71 são de tipos que carregam (ou podem carregar) dado financeiro e a IA disse que não tinham, sem falha e sem pendência. Pular o reenvio deles tornaria
-- PERMANENTE um buraco silencioso: com `semDadoExtraido`, a guarda de cobertura do n8n se cala (N8N/build-workflow.mjs:1933-1934, `semDadoExtraido && false`) e o Sinal 3 também.
-- Hoje o reenvio paga de novo e pode consertar por acaso; isso tem de continuar. Por isso a parte nova é ESTREITA, e a economia desta migration em produção é NO MÁXIMO 30
-- documentos (não 71 nem 72).
--
-- A CORREÇÃO, SÓ ADITIVA E ESTREITA (escada, degraus 2 e 4). `fn_versao_extracao_concluida(p_documento_versao_id)` é verdadeira quando a versão TEM linha em `campo_extraido`
-- (EXATAMENTE o critério da 0118, sem exigir evento e sem olhar falha: comportamento de antes intacto, inclusive para as 6 versões de produção com linha e sem evento) OU
-- quando TODAS valem:
--   1. o ÚLTIMO evento `extracao_sombra` da versão existe, com `falha_motivo` nulo e `tem_dado_financeiro = false` EXPLÍCITO;
--   2. o tipo do documento é da categoria 'Societário/Legal' de `taxonomia_tipo_documento` (CERTIDOES, CONTRATO_SOCIAL, ORGANOGRAMA; CONTINGENCIAS é da categoria e fica DE FORA, porque traz valor de causa e provisão — conferido no banco de
--      teste, grafia exata). Tipo nulo ou de outra categoria: NÃO reaproveita. SIMPLIFICAÇÃO DELIBERADA com teto conhecido: a categoria é proxy de "tipo que não traz tabela
--      financeira". Sobe quando a taxonomia ganhar um atributo próprio para isso;
--   3. a medição do último evento não contou conta: `medicao.contas_no_documento` nulo/ausente ou 0 (maior que 0, ou valor não numérico: NÃO reaproveita);
--   4. o documento não tem pendência `extracao_falhou` não resolvida (cenário reproduzido pela revisão: mesmo arquivo registrado duas vezes antes de extrair, a v1 declara
--      `false`, a v2 falha e abre a pendência, e o terceiro envio reaproveitava a v1 por cima da falha aberta).
-- Condição que não possa ser lida (linha da taxonomia ausente, evento ausente, RLS) = falsa: o erro cai para o lado de PAGAR de novo, nunca de pular.
-- Zero linha sem a declaração continua NÃO reaproveitável (extração recusada/truncada: o caso que a 0118 protege) e a falha vence a declaração.
-- `fn_registrar_documento` chama a função no lugar do `exists`; as demais condições ficam (mesmo caso, hash e fingerprint não nulos; versão de MAIOR n_versao). Uma função
-- só porque a fatia seguinte (orçamento do lote no n8n) precisa da MESMA pergunta, e duas implementações da mesma conta divergem sem erro nenhum.
--
-- O "ÚLTIMO" evento é `order by criado_em desc` e nada mais. `criado_em` é o `now()` da transação: dois eventos da mesma versão gravados na MESMA transação empatam e a ordem
-- entre eles é indefinida (o id é uuid v4 aleatório, não ordena nada; por isso não há desempate por id). Em produção cada chamada do n8n é a sua transação, e só 2 versões em 2.038
-- têm mais de um evento extracao_sombra (medido em 09/11/2026).
--
-- A PRIMEIRA VERSÃO DESTA MIGRATION ERA MAIOR E FOI REPROVADA NA REVISÃO. Ela também reextraía a falha COM linha (79 dos 496 documentos com `extracao_falhou` aberta têm linha na
-- última versão). A medição em produção dos motivos dessas falhas deu razão à revisão: 36 "Extração INCOMPLETA: N linhas devolvidas para um documento com N linhas"; 11 contas
-- descartadas por desalinhamento (5 com pendência já decidida por humano); 5 linhas repetidas na emenda entre blocos; ~17 de identidade/total que não fecha; 1 xlsx com várias abas,
-- 1 truncada por tokens de saída, 1 rótulo com número colado, 1 cobertura de bloco abaixo do mínimo; só 3 são do serviço (2 de limite de cadência do provedor, 1 de resposta sem
-- conteúdo). ~95% se repetem com o mesmo arquivo e o mesmo prompt (portal/src/lib/rotulos.ts:417-441 já diz isso). Pagar de novo não conserta, custa a cada vez e cria versão nova que
-- tira da Modelagem a linha que o analista já aceitou (v1 aceita com valor 100 -> reenvio -> v2 pendente com valor 90, sem evento nenhum: medido no banco de teste pelo revisor).
-- O conserto é mudar o prompt (o fingerprint muda e o reaproveitamento cai sozinho) ou a retentativa CLASSIFICADA: fatia P8 do plano, não esta. A segunda versão (larga, só com a
-- declaração da IA) foi reprovada pela medição por tipo acima.
--
-- O QUE NÃO MUDA (teto conhecido, sobe na P8): falha COM linha continua reaproveitada até o prompt mudar. E UMA SUPOSIÇÃO QUE FICA: um documento societário que a IA disse não ter
-- dado financeiro (e a medição não contradiz) deixa de ganhar nova chance no reenvio do MESMO arquivo com o MESMO prompt (mudar o prompt ou o arquivo continua reextraindo).
--
-- A ASSINATURA E O RETORNO NÃO MUDAM. Chamadores de `fn_registrar_documento` (grep em Supabase/ N8N/ portal/src/): o nó "Registrar Documento" de N8N/build-workflow.mjs (l.2917; 13
-- posicionais + `p_justificativa`, `p_fingerprint_extracao`, `p_cnpj` por nome) e o curto-circuito do dedup logo depois dele (l.2930, lê `reaproveitou_extracao`);
-- N8N/lib/{classifier,merge,taxonomia}.mjs e o JSON do workflow só a citam em comentário/consulta; portal/src não a chama; o resto são testes SQL e Supabase/conferir/conferir_chamadas.sql.
-- Nenhuma função SQL a chama. Mesmo jsonb de retorno: o n8n NÃO precisa ser republicado. CREATE OR REPLACE com a mesma assinatura preserva a ACL (REVOKE de PUBLIC; EXECUTE para
-- authenticated e service_role); o comentário é refeito. SECURITY INVOKER: a RLS do chamador vale.
--
-- SEM BACKFILL: nada a regravar. O critério é lido na hora.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/reextracao.test.sql — 56 asserts (contagem de execuções do arquivo: 23 antigos da 0026/0118 e 33 desta migration), medidos em 09/11/2026 com o assert trocado por raise warning, que CONTA (cópia do teste, rodada pelo run.sh inteiro; conferido que a migration aplicou e que o teste apareceu no log). Controle (migration intacta): 0 dos 56 reprovam e o run.sh fecha verde (3190 ok antes, 3223 depois). (i) Critério ANTIGO (fn_registrar_documento de volta ao exists em campo_extraido): 10 dos 56 reprovam, 9 de comportamento (a certidão sem linha e a com 0 contas são pagas de novo; o lote de 4 reenviado inteiro paga 2 em vez de 1; o terceiro envio ainda paga 1) e 1 da sonda. (ii) Versão LARGA (a reprovada: só a declaração da IA, sem as condições 2 a 4): 5 dos 56 reprovam (BALANCO declarado sem dado; documento sem tipo; CERTIDOES com 7 contas medidas; e os 2 asserts da falha aberta mais nova). Os asserts de controle (zero linha sem declaração, tem_dado_financeiro = true, falha vencendo a declaração, falha com linha e linha sem evento continuando reaproveitadas, o último evento) passam nas três versões: protegem o comportamento da 0118.
-- DEPOIS DESSA MEDIÇÃO entrou UM assert a mais (57 no total, 34 desta migration): CONTINGENCIAS, da mesma categoria, fica de fora porque traz valor de causa e provisão. Medido à parte, pelo run.sh inteiro: com a exclusão desligada reprova 1 assert (o dele) e o run.sh sai com rc 3; religada, rc 0 e 3224 ok. As contagens (i) e (ii) acima NÃO foram refeitas com os 57.
-- =============================================================================

begin;

create or replace function fn_versao_extracao_concluida(p_documento_versao_id uuid)
returns boolean
language sql
stable
as $$
  -- (1) tem linha: o critério da 0118, intacto. (2) ou TODAS: o ÚLTIMO evento de extração (criado_em; empate na mesma transação é indefinido, ver o cabeçalho) existe, sem falha,
  -- declara tem_dado_financeiro = false e não contou conta; o tipo do documento é da categoria 'Societário/Legal'; e não há pendência extracao_falhou aberta no documento.
  -- Qualquer parte ilegível = false (paga de novo), nunca nula.
  select exists (select 1 from campo_extraido ce where ce.documento_versao_id = p_documento_versao_id)
      or coalesce((
    select u.depois->>'falha_motivo' is null
       and u.depois->>'tem_dado_financeiro' = 'false'
       and (u.depois->'medicao'->>'contas_no_documento' is null
            or (u.depois->'medicao'->>'contas_no_documento' ~ '^[0-9]+(\.[0-9]+)?$'
                and (u.depois->'medicao'->>'contas_no_documento')::numeric = 0))
       and exists (select 1
                     from documento_versao dv
                     join documento d on d.id = dv.documento_id
                     join taxonomia_tipo_documento t on t.codigo = d.tipo_taxonomia
                    where dv.id = p_documento_versao_id
                      and t.categoria = 'Societário/Legal'
                      -- CONTINGENCIAS fica de fora: é da mesma categoria, mas a relação de processos traz valor de causa e provisão.
                      -- Nenhum dos 30 de produção é desse tipo (09/11/2026): tirar não custa nada e evita pular uma tabela de valores.
                      and t.codigo <> 'CONTINGENCIAS')
       and not exists (select 1
                         from documento_versao dv
                         join pendencia pe on pe.documento_id = dv.documento_id
                        where dv.id = p_documento_versao_id
                          and pe.tipo = 'extracao_falhou'
                          and pe.estado <> 'resolvida')
      from evento_auditoria u
     where u.acao = 'extracao_sombra'
       and u.entidade_ref = 'documento_versao:' || p_documento_versao_id::text
     order by u.criado_em desc
     limit 1
  ), false)
$$;

comment on function fn_versao_extracao_concluida(uuid) is
  '0230: a versão já foi extraída (vale reaproveitar no reenvio)? Verdadeira quando a versão TEM linha em campo_extraido (o critério da 0118, intacto, mesmo sem evento e mesmo com falha) OU quando TODAS valem: o ÚLTIMO evento extracao_sombra (criado_em) existe, sem falha_motivo e com tem_dado_financeiro = false explícito; o tipo do documento é da categoria Societário/Legal de taxonomia_tipo_documento (CERTIDOES, CONTRATO_SOCIAL, ORGANOGRAMA; CONTINGENCIAS é da categoria e fica DE FORA, porque traz valor de causa e provisão; tipo nulo ou de outra categoria = não); a medição do evento não contou conta (contas_no_documento nulo ou 0); e o documento não tem pendência extracao_falhou aberta. Simplificação deliberada: a categoria é proxy de "tipo que não traz tabela financeira"; sobe quando a taxonomia ganhar atributo próprio. Zero linha sem tudo isso = false (a 0118 protege extração recusada/truncada); condição ilegível = false (paga de novo). Falha COM linha continua reaproveitada (teto conhecido, P8). A pergunta de fn_registrar_documento e da fatia de orçamento do lote: uma implementação só. SECURITY INVOKER, somente leitura.';

revoke all on function fn_versao_extracao_concluida(uuid) from public;
grant execute on function fn_versao_extracao_concluida(uuid) to authenticated, service_role;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    execute 'grant execute on function fn_versao_extracao_concluida(uuid) to supabase_read_only_user';
  end if;
end $$;

create or replace function fn_registrar_documento(p_caso_id uuid, p_entidade_nome text, p_periodo_tipo text, p_periodo_ref text, p_tipo_taxonomia text, p_confianca numeric, p_fonte text, p_origem_arquivo public.origem_arquivo, p_arquivo_ref text, p_nome_original text, p_assinado boolean, p_hash text, p_legibilidade public.legibilidade, p_threshold numeric DEFAULT 0.7, p_justificativa text DEFAULT NULL::text, p_fingerprint_extracao text DEFAULT NULL::text, p_cnpj text DEFAULT NULL::text) RETURNS jsonb
language plpgsql
as $$
declare
  -- 0127: o limiar da classificacao passa a vir do DIAL.
  v_auto_classif   boolean;
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_documento_id uuid;
  v_versao_id   uuid;
  v_n_versao    int := 1;
  v_obrig obrigatoriedade;
  v_reaproveitou boolean := false;
  v_versao_reuso uuid;
  v_doc_reuso    uuid;
  v_n_reuso      int;
begin
  -- ---- REAPROVEITAMENTO DE EXTRAÇÃO: a primeira pergunta, e a mais barata ----
  -- Vem ANTES do upsert de entidade/período de propósito: se o arquivo já foi
  -- extraído com este mesmo prompt, nada precisa ser criado — nem versão, nem
  -- entidade, nem período. Sair daqui é o caminho de custo zero.
  if p_hash is not null and length(trim(p_hash)) > 0
     and p_fingerprint_extracao is not null and length(trim(p_fingerprint_extracao)) > 0 then
    select dv.id, dv.documento_id, dv.n_versao
      into v_versao_reuso, v_doc_reuso, v_n_reuso
    from documento_versao dv
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id
      and dv.hash = p_hash
      and dv.fingerprint_extracao = p_fingerprint_extracao
      -- JÁ FOI EXTRAÍDA (0230): quem responde é a função da pergunta única — tem
      -- linha (o critério da 0118, que mantém reextraível a extração que falhou SEM
      -- linha) OU o documento é de tipo societário/legal que a IA declarou sem dado
      -- financeiro, sem falha, sem conta contada e sem pendência de falha aberta
      -- (certidão, organograma: no máximo 30 em produção eram pagos a cada reenvio).
      and fn_versao_extracao_concluida(dv.id)
    order by dv.n_versao desc
    limit 1;
  end if;

  if v_versao_reuso is not null then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:n8n', 'documento_extracao_reaproveitada',
              'documento_versao:' || v_versao_reuso,
              jsonb_build_object('documento_id', v_doc_reuso, 'hash', p_hash,
                                 'fingerprint_extracao', p_fingerprint_extracao,
                                 'nome_original', p_nome_original));
    return jsonb_build_object(
      'documento_id', v_doc_reuso,
      'documento_versao_id', v_versao_reuso,
      'n_versao', v_n_reuso,
      'reaproveitou_documento', true,
      'reaproveitou_extracao', true
    );
  end if;

  -- ENTIDADE E PERÍODO PELA FORMA CANÔNICA (0030), e não por `lower()`. Esta é a
  -- parte que a primeira versão desta migration perdeu por copiar o corpo da
  -- 0026 em vez do corpo VIGENTE: o teste de canonicalização reprovou na hora
  -- ("as duas grafias da mesma empresa viram UMA entidade — achei 2"), que é
  -- exatamente o defeito que a 0030 tinha corrigido. Republicar função neste
  -- banco significa partir do corpo mais recente, nunca do da migration que a
  -- gente está lendo.
  v_entidade_id := fn_upsert_entidade(p_caso_id, p_entidade_nome, p_cnpj);
  v_periodo_id := fn_upsert_periodo(p_caso_id, p_periodo_tipo, p_periodo_ref);

  -- Já existe ESTE arquivo (mesmo hash) neste caso? Então é reextração/reenvio:
  -- versão nova sob o mesmo documento. Hash nulo nunca casa (ver 0026).
  if p_hash is not null and length(trim(p_hash)) > 0 then
    select dv.documento_id into v_documento_id
    from documento_versao dv
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id and dv.hash = p_hash
    order by dv.criada_em desc
    limit 1;
    v_reaproveitou := v_documento_id is not null;
  end if;

  if v_reaproveitou then
    select coalesce(max(n_versao), 0) + 1 into v_n_versao
      from documento_versao where documento_id = v_documento_id;
    -- A classificação da versão nova prevalece SOBRE A DO SISTEMA, nunca sobre a
    -- do humano: se alguém já revisou este documento na fila (`fonte='humano'`,
    -- `Supabase/migrations/0008`), a reextração não desfaz a decisão dele — é a
    -- anti-ancoragem de sempre (Arquitetura do Sistema/1 Visão e Doutrina/01), no sentido que importa: máquina não
    -- sobrepõe humano. Entidade/período seguem a mesma regra.
    update documento d set
      tipo_taxonomia = case when d.fonte = 'humano' then d.tipo_taxonomia else p_tipo_taxonomia end,
      entidade_id    = case when d.fonte = 'humano' then d.entidade_id else coalesce(v_entidade_id, d.entidade_id) end,
      periodo_id     = case when d.fonte = 'humano' then d.periodo_id else coalesce(v_periodo_id, d.periodo_id) end,
      confianca      = case when d.fonte = 'humano' then d.confianca else p_confianca end,
      fonte          = case when d.fonte = 'humano' then d.fonte else p_fonte end,
      justificativa  = case when d.fonte = 'humano' then d.justificativa else p_justificativa end,
      status         = case when d.fonte = 'humano' then d.status else 'em_validacao' end
    where d.id = v_documento_id;
  else
    insert into documento (caso_id, entidade_id, periodo_id, tipo_taxonomia, status, confianca, fonte, justificativa)
      values (p_caso_id, v_entidade_id, v_periodo_id, p_tipo_taxonomia, 'em_validacao', p_confianca, p_fonte, p_justificativa)
      returning id into v_documento_id;
  end if;

  insert into documento_versao
    (documento_id, n_versao, origem_arquivo, arquivo_ref, nome_original, assinado, hash,
     legibilidade, fingerprint_extracao)
    values (v_documento_id, v_n_versao, coalesce(p_origem_arquivo,'supabase_storage'),
            p_arquivo_ref, p_nome_original, p_assinado, p_hash, p_legibilidade,
            p_fingerprint_extracao)
    returning id into v_versao_id;

  -- Checklist: só na PRIMEIRA vez. Reextração não é documento novo — inserir de
  -- novo daria dois itens "presente" para o mesmo documento e inflaria a
  -- completude com um arquivo só (a `unique` do checklist não cobre isso porque
  -- `documento_id` faz parte da linha).
  if p_tipo_taxonomia is not null and not v_reaproveitou then
    select obrigatoriedade into v_obrig from taxonomia_tipo_documento where codigo = p_tipo_taxonomia;
    insert into checklist_item_status
      (caso_id, entidade_id, periodo_id, tipo_taxonomia, obrigatoriedade, status, documento_id)
      values (p_caso_id, v_entidade_id, v_periodo_id, p_tipo_taxonomia,
              coalesce(v_obrig,'complementar'), 'presente', v_documento_id);
  end if;

  -- Pendência de classificação incerta: idempotente por documento.
  --
  -- 0127: O LIMIAR SAI DO PARÂMETRO E PASSA A VIR DO DIAL. Até aqui ele era
  -- `p_threshold`, default 0.7 — e o dial de `classificacao_doc_checklist` dizia
  -- limiar 0,95, lido por ninguém. O sistema declarava 0,95 e aplicava 0,70.
  --
  -- O parâmetro fica como QUEDA, para banco que ainda não tem a linha do dial
  -- (a semeadura é da 0002). Não é cortesia: sem a queda, um banco antigo passaria
  -- a abrir pendência de classificação em TODO documento no instante em que esta
  -- migration entrasse, e o motivo seria invisível.
  v_auto_classif := case
    when exists (select 1 from estagio_autonomia
                  where estagio = 'classificacao_doc_checklist')
      then fn_dial_permite_auto('classificacao_doc_checklist', p_confianca)
    else coalesce(p_confianca, 0) >= p_threshold
  end;

  if p_tipo_taxonomia is null or not v_auto_classif then
    if not exists (
      select 1 from pendencia p
      where p.documento_id = v_documento_id
        and p.tipo = 'classificacao_pendente'
        and p.estado <> 'resolvida'
    ) then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id)
        values (p_caso_id, 'classificacao', 'classificacao_pendente', 'importante', true,
                -- 0127: a mensagem passa a dizer QUAL limiar reprovou. Sem isso, o
                -- analista lê "conf=0,62" e não sabe contra o que ela perdeu — e
                -- o limiar agora é dado, então pode ter mudado desde ontem.
                format('Classificação incerta (conf=%s, limiar do dial=%s, fonte=%s) para "%s". Motivo: %s',
                       coalesce(p_confianca,0),
                       coalesce((select ea.limiar_auto_clear::text from estagio_autonomia ea
                                  where ea.estagio = 'classificacao_doc_checklist'),
                                p_threshold::text || ' (queda: dial sem linha)'),
                       coalesce(p_fonte,'?'), coalesce(p_nome_original,'?'),
                       coalesce(nullif(trim(p_justificativa), ''), 'nenhuma justificativa fornecida')),
                v_documento_id);
    end if;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n',
            case when v_reaproveitou then 'documento_reextraido' else 'documento_registrado' end,
            'documento:'||v_documento_id,
            jsonb_build_object('tipo', p_tipo_taxonomia, 'confianca', p_confianca, 'fonte', p_fonte,
                               'justificativa', p_justificativa, 'n_versao', v_n_versao,
                               'hash', p_hash, 'fingerprint_extracao', p_fingerprint_extracao));

  return jsonb_build_object(
    'documento_id', v_documento_id,
    'documento_versao_id', v_versao_id,
    'n_versao', v_n_versao,
    'reaproveitou_documento', v_reaproveitou,
    'reaproveitou_extracao', false
  );
end;
$$;
comment on function fn_registrar_documento(uuid, text, text, text, text, numeric, text, origem_arquivo, text, text, boolean, text, legibilidade, numeric, text, text, text) is
  'A porta de entrada do documento: acha ou cria caso/entidade/período, versiona e responde se '
  'já foi extraído (0118). 0170: recebe o CNPJ do emitente e o repassa a fn_upsert_entidade — '
  'sem este fio, as três regras de identidade da 0169 nunca disparam em produção e o sintoma é '
  'que nada melhora. 0230: "já foi extraído" passa a ser a resposta de fn_versao_extracao_concluida '
  '(a versão tem linha, como na 0118, OU é documento societário/legal que a IA declarou sem dado '
  'financeiro, sem falha, sem conta contada e sem pendência de falha aberta): certidão e organograma '
  'deixam de ser pagos a cada reenvio.';

-- ---------------------------------------------------------------------------
-- A SONDA. Marcadores em CÓDIGO (pg_get_functiondef traz comentário, por isso nenhum deles aparece em comentário nos corpos).
-- ---------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('extracao_concluida_funcao', '0230', 'funcao', 'fn_versao_extracao_concluida', null, null,
   'A pergunta única "esta versão já foi extraída?". Ausente = a 0230 não foi aplicada e o reenvio volta a decidir só por "tem linha": certidão e organograma (até 30 em produção) são pagos a cada reenvio.',
   'importante', 1050),
  ('extracao_concluida_estreita_pela_categoria', '0230', 'corpo', 'fn_versao_extracao_concluida', 't.categoria = ''Societário/Legal''', null,
   'A parte nova da função só vale para tipo da categoria Societário/Legal. Corpo sem isto = a declaração tem_dado_financeiro = false da IA vale para qualquer tipo, e DF_AUDITADA/NOTAS_EXPL/DRE com dado (41 de 71 em produção, medido em 09/11/2026) deixam de ser reextraídos: buraco silencioso permanente.',
   'importante', 1051),
  ('registrar_documento_pergunta_a_funcao', '0230', 'corpo', 'fn_registrar_documento', 'and fn_versao_extracao_concluida(dv.id)', null,
   'fn_registrar_documento decide o reaproveitamento pela função, não só por "tem linha". Corpo anterior = certidão e organograma declarados sem dado financeiro (até 30 em produção, medido em 09/11/2026) são pagos a cada reenvio do lote.',
   'importante', 1052)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0230', revisado_em = current_date,
       observacao = 'A 0230 cria fn_versao_extracao_concluida (a pergunta única "a versão já foi extraída?": tem linha OU documento societário/legal declarado sem dado financeiro, sem falha, sem conta contada e sem pendência aberta) e reemite fn_registrar_documento INTEIRA (mesma assinatura de 17 args, mesma ACL); 3 requisitos.'
 where id = true;

commit;
