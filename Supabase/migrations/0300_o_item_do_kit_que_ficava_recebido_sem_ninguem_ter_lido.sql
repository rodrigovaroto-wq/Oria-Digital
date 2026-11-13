-- =============================================================================
-- 0300 — O ITEM DO KIT QUE FICAVA "RECEBIDO" SEM NINGUÉM TER LIDO NADA: o estado do item calculado no banco (fn_kit_do_caso), a
--        pendência de item faltante achada por CHAVE e não pelo texto, o documento que a fechou e o sinal de que a conferência rodou
--        (Função 1 de Arquitetura do Sistema/3 Estado e Execução/DESENHO_QUATRO_FUNCOES_2026-11.md; decisões do dono D1.1 a D1.4, 13/11/2026)
-- (Cria 2 colunas em `pendencia`, 2 funções, 1 view da sonda; reemite fn_recomputar_completude, mesma assinatura e mesma ACL. Backfill:
--  só atribui a chave às item_faltante do Kit ainda não resolvidas — 233 item_faltante (205 abertas, 26 aceita_com_ressalva, 2 rejeitada) em 52 dos 81 mandatos, 0 duplicadas; as 2 de contrato social ficam de fora em produção, medido em 13/11/2026.)
--
-- O DEFEITO. A grade do Kit Básico só sabia "recebido" ou "falta". O documento entra em `checklist_item_status` como `presente` NO
-- REGISTRO (0230), antes de existir uma linha lida; e se o n8n morre entre o registro e a extração, a linha fica `presente` para
-- sempre — com a mesma cara de um documento lido, conferido e bom. Medido em PRODUÇÃO em 13/11/2026 (só leitura, API de
-- gerenciamento, banco em 0276): 267 linhas de checklist `presente` cuja versão vigente tem ZERO linha de campo_extraido, em 34
-- mandatos e 116 itens (mandato × tipo); 214 delas, 73 itens em 26 mandatos, são de tipo OBRIGATÓRIO. Dessas 267, 169 têm
-- `extracao_falhou` aberta, 3 têm a extração concluída (declaração sem dado financeiro) e 95 não têm nem uma coisa nem outra: a leitura
-- nunca terminou e nada diz isso. A tela não distinguia o recebido do lido, e o lido do conferido por pessoa.
-- Três defeitos vizinhos, medidos no código, entram na mesma conta porque passam pelo mesmo lugar:
--   (1) A pendência `item_faltante` era achada pelo TEXTO da `descricao` ("Item obrigatório do Kit Básico ausente: <TIPO>"):
--       mudar a frase abre uma segunda e resolve a primeira. E o filtro de "resolver" era "item_faltante cuja descrição não está
--       na lista", que resolve também o item_faltante de OUTRO assunto (`contrato_social_ausente:<id>`, 0208): 2 abertas em produção
--       no mandato 1be52ab4, esperando a próxima conferência para sumirem sem que contrato nenhum tenha chegado.
--   (2) Nada dizia QUAL documento fechou a pendência, e `resolvida_por` é sobrescrito: quando o documento chega para uma pendência que
--       uma PESSOA decidiu (seguiu sem / não procede), a decisão desaparecia. Medido: 26 `aceita_com_ressalva` e 2 `rejeitada` no
--       Kit em produção; 6 das 26 já têm documento que serve e seriam resolvidas na próxima conferência do mandato.
--   (3) `fn_recomputar_completude` só deixava rastro na troca de status do caso: conferência que não achou nada tinha a mesma cara
--       de conferência que nunca rodou (regra 7). 0 eventos `completude_recomputada` em produção, por construção.
--
-- Achados da revisão independente (36575aa), corrigidos NESTE arquivo porque a 0300 não foi aplicada:
--   (A1) documento que o sistema JÁ declarou sem leitura aparecia como `aguardando_extracao`: fn_conferir_lote (ativa no n8n) abre
--        `documento_nao_extraido` bloqueante, o diagnóstico abre `arquivo_ilegivel`/`arquivo_corrompido`, e a primeira versão ignorava as três.
--        Medido em PRODUÇÃO em 13/11/2026 (só leitura): `documento_nao_extraido` aberta = 0 documentos; `arquivo_corrompido` aberta = 0;
--        `arquivo_ilegivel` aberta = 63 documentos em 2 mandatos, os 63 sem nenhuma linha lida — 63 itens que a tela diria "aguardando".
--        Agora as três, abertas, valem `recebido_sem_linha`.
--   (M1) contrato social lido certo (zero linha, sem dado financeiro por natureza, fn_tipo_sem_dado_por_natureza) virava `recebido_sem_linha`
--        com o efeito falso "o book sai VAZIO": novo estado `lido_sem_dado_por_natureza` (não há linha a conferir).
--   (M2) "N de M empresas" ignorava taxonomia_tipo_documento.granularidade: só entidade e entidade_periodo têm fração; MUTUOS e
--        FAT_INTRAGRUPO (caso) e COMBINADO (periodo) devolvem os quatro contadores NULOS.
--   (M3) `aguardando_desde`: o criado_em mais antigo entre os documentos aguardando, para a tela dizer "há N dias".
--   (B5) `set local lock_timeout = '5s'` antes do ALTER TABLE (ACCESS EXCLUSIVE em pendencia).

-- O QUE A MIGRATION INSTALA
--   * `fn_kit_do_caso(p_caso uuid)`: stable, security invoker (a RLS da 0216 vale sozinha). Uma linha por item OBRIGATÓRIO do Kit.
--     O estado é DERIVADO na leitura de campo_extraido, nunca lido do checklist (que envelhece): faltante · dispensado ·
--     aguardando_extracao · recebido_sem_linha · lido_sem_dado_por_natureza · extraido · conferido. O item toma o PIOR estado dos documentos que servem (um
--     documento sem linha segura o item em "sem linha" mesmo com o irmão lido; `docs_por_estado` mostra a conta). `conferido` exige
--     aceite de PESSOA em TODA linha da versão vigente de TODO documento que serve: o auto-aceite do sistema (`aceito_por` com
--     `sistema:`, confiança >= 95%) NÃO conta (D1.1 a). O item é mandato × tipo (D1.2 a): `empresas_total`, `empresas_com_documento`
--     e `empresas_atendidas` (com documento LIDO) dizem "N de M" SÓ para granularidade entidade e entidade_periodo (MUTUOS, FAT_INTRAGRUPO e COMBINADO vêm NULOS: "1 de 8" para item completo seria falso); documento sem empresa (`entidade_id` nulo, caso do COMBINADO) vai em
--     `documentos_sem_empresa` e NÃO entra no N — o número não é inventado. M exclui entidade `fora_do_perimetro`.
--     `conferencia_em` é o último evento `completude_recomputada` e `documentos_depois_da_conferencia` conta os documentos criados
--     depois dele (todos, se a conferência nunca rodou). Mandato que o chamador não enxerga devolve ZERO linhas (nunca "tudo faltante").
--   * `pendencia.chave_motor` (coluna PRÓPRIA, não `motivo`: fn_decidir_pendencia grava `motivo = coalesce(p_motivo, motivo)`, 0109/0227,
--     e uma decisão humana com motivo apagaria a chave) e `pendencia.resolvida_por_documento_id` (FK on delete set null; NÃO reaproveita
--     `pendencia.documento_id`, que fn_revisar_documento usa para resolver pendência por documento).
--   * `fn_adotar_chave_item_faltante(p_caso_id uuid default null)`: dá a chave às item_faltante do Kit (descrição com o prefixo) ainda não
--     resolvidas. É FUNÇÃO e não bloco anônimo, pela lição da 0188: um `do $$` roda uma vez num banco vazio e altera ZERO linhas por
--     construção; assim o teste a exercita. O backfill desta migration e a conferência (que adota a que um motor antigo deixou sem chave
--     durante a aplicação) usam a MESMA função.
--   * `fn_recomputar_completude` REEMITIDA (corpo da 0188, assinatura e ACL intactas; 4 chamadores no banco — fn_registrar_campos_extraidos,
--     fn_registrar_transcricao_humana, fn_revisar_documento, fn_reconferir_caso — e o nó do n8n, nenhum precisa mudar). Muda: (a) o
--     passo 1 acha a pendência pela chave e SÓ resolve a que o motor abriu; (b) resolve também a decidida por pessoa (D1.3 a) e grava
--     em `resolvida_por_documento_id` o documento que serve; (c) grava SEMPRE o evento `completude_recomputada` com as contagens de
--     abertas, resolvidas e mantidas dos três tipos de pendência do motor e, nas item_faltante fechadas, o ESTADO ANTERIOR, quem
--     decidiu e quando (a coluna é sobrescrita, o evento é append-only). Custo: um evento por chamada; ela é chamada a cada extração
--     de documento, então o volume sobe de 0 para ~1 por documento extraído (INSERT de 1 linha, índice por entidade_ref existe).
--   * D1.4 (a): quem dispara a conferência continua sendo o n8n; nada de gatilho em `documento` (colide com a P27/0243). O que esta
--     migration acrescenta é o aviso "N documentos chegaram depois da última conferência". NÃO reemite fn_registrar_documento nem
--     fn_registrar_campos_extraidos.
--   * A SONDA: 9 requisitos (ordem 1364-1372) e `instalacao_cobertura` em 0300.
--
-- LIMITES DITOS. (a) `fn_registrar_documento` não chama a conferência: entre o registro e a extração a pendência `item_faltante` segue
--   aberta mesmo com o documento já servindo, e o Kit mostra `aguardando_extracao` — é exatamente a janela que o estado novo torna
--   visível. (b) A pendência `item_sem_conteudo` (passo 2) também pode abrir nessa janela, como antes. (c) O texto da descrição
--   continua o mesmo ("Item obrigatório do Kit Básico ausente: <TIPO>"): o portal e o 0208 não mudam. (d) Item resolvido pelo motor com o
--   tipo já NÃO obrigatório (taxonomia mudou) fica com `resolvida_por_documento_id` nulo: nulo é a verdade. (e) Duas conferências
--   simultâneas do mesmo mandato podem abrir duas pendências com a mesma chave (como podiam com o texto); não há índice único porque
--   `fn_decidir_pendencia('reabrir')` reabriria uma resolvida e bateria nele em 23505 no clique do analista.
--   (f) `conferido` por aceite de pessoa ESTÁ IMPLEMENTADO (D1.1 a), mas o único caminho humano, fn_aceitar_extracao, só atualiza as linhas com
--   `status_aceite <> 'aceito'`: linha que o sistema já auto-aceitou NUNCA passa a ser de pessoa. Medido em produção em 13/11/2026: das
--   1.648 versões com linha, 1.443 têm TODAS as linhas auto-aceitas (nenhuma consegue chegar a `conferido`), 14 têm todas aceitas por
--   pessoa, 56 misturam auto-aceita e pendente, e as 285 linhas de pessoa são 0,3% das 95.991 aceitas. Esta migration NÃO muda
--   fn_aceitar_extracao (função com chamador no portal, fora do desenho da Função 1): fica como decisão do dono, ver o relatório.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/o_item_do_kit_que_ficava_recebido_sem_ninguem_ter_lido.test.sql — 106 asserts
--   (medido: 106 execuções, controle com a migration intacta: 0 reprovam; reconferido com Supabase/test/medicao-denominador.test.mjs).
--   Cada correção desligada UMA por vez, com o teste em `raise warning` (voltou para `raise exception`; log lido atrás de FALHOU), 13/11/2026:
--   Reprovam, por correção desligada (cada número é "N dos 106 asserts"):
--   * auto-aceite do sistema passa a contar como conferência (tira o filtro `sistema:` de fn_kit_do_caso): 4 dos 106 asserts (3 de comportamento e 1 da sonda, que acusa o corpo sem o filtro).
--   * o estado `aguardando_extracao` vira `recebido_sem_linha` (I1.4): 9 dos 106 asserts.
--   * documento sem nenhuma linha lida passa a aparecer como `extraido` (é o defeito dos 267 `presente` de produção: o estado vindo do registro, não da leitura; I1.1): 23 dos 106 asserts.
--   * a conferência volta a resolver o item_faltante de OUTRO assunto (contrato_social_ausente): 2 dos 106 asserts.
--   * a pendência volta a ser achada pelo TEXTO da descrição (I1.8: reescrever a frase abre uma segunda): 1 dos 106 asserts.
--   * sem o `resolvida_por_documento_id` (I1.3 e D1.3): 5 dos 106 asserts.
--   * o evento só é gravado quando a conferência mudou alguma coisa (I1.5): 5 dos 106 asserts.
--   * a decisão de pessoa (aceita_com_ressalva, rejeitada) deixa de ser resolvida pelo documento que chega (D1.3): 6 dos 106 asserts.
--   * a `rejeitada` sozinha deixa de ser resolvida pelo documento que chega (D1.3, B2): 3 dos 106 asserts.
--   * a `rejeitada` passa a abrir uma segunda pendência em vez de ser reconhecida como aberta (B2): 1 dos 106 asserts.
--   * o evento sem o `estado_anterior`: 2 dos 106 asserts.
--   * o evento sem quem decidiu (`resolvida_por_anterior`): 2 dos 106 asserts.
--   * `documentos_depois_da_conferencia` sempre zero (I1.5): 1 dos 106 asserts.
--   * fn_kit_do_caso como security definer (a Analista de B lê o Kit de A): 3 dos 106 asserts.
--   * EXECUTE de fn_kit_do_caso concedido a public (o anon executa; o 42501 do anon vem da tabela, por isso o assert de has_function_privilege à parte): 1 dos 106 asserts.
--   * `dispensado` some (a decisão de pessoa de seguir sem o documento volta a parecer falta; o assert do motivo casa 'Seguiu sem%', B1): 2 dos 106 asserts.
--   * M (empresas do mandato) passa a incluir a entidade fora_do_perimetro: 1 dos 106 asserts.
--   * o documento sem empresa passa a contar como uma empresa (número inventado): 1 dos 106 asserts.
--   * a falha de extração aberta deixa de contar (documento que falhou parece ainda aguardando): 3 dos 106 asserts.
--   * a adoção da chave não adota nada (o backfill alcançaria zero, por construção): 2 dos 106 asserts.
--   * a conferência deixa de adotar a pendência sem chave (abre uma segunda): 1 dos 106 asserts.
--   * mandato invisível ao chamador devolve o Kit inteiro como faltante em vez de zero linhas: 2 dos 106 asserts.
--   * linha PENDENTE passa a contar como conferida: 6 dos 106 asserts.
--   * o item toma o MELHOR estado dos documentos em vez do pior: 2 dos 106 asserts.
--   * A1: `documento_nao_extraido` deixa de valer como leitura perdida (volta a `aguardando`): 2 dos 106 asserts (1 de comportamento e 1 da sonda).
--   * A1: `arquivo_ilegivel` deixa de valer: 2 dos 106 asserts.
--   * A1: `arquivo_corrompido` deixa de valer: 1 dos 106 asserts.
--   * M1: o ramo `lido_sem_dado_por_natureza` some (contrato social lido volta a `recebido_sem_linha` com o efeito falso): 3 dos 106 asserts.
--   * M1: o ramo vale para QUALQUER tipo, não só o sem dado por natureza (balanço cuja falha a pessoa resolveu viraria "lido sem dado"): 1 dos 106 asserts.
--   * M1: o `lido_sem_dado_por_natureza` passa a pesar no pior estado do item (rebaixa o item cujo outro documento foi conferido): 2 dos 106 asserts.
--   * M2: a fração N de M ignora a granularidade (MUTUOS, FAT_INTRAGRUPO e COMBINADO voltam com número): 1 dos 106 asserts.
--   * M3: `aguardando_desde` nulo: 1 dos 106 asserts.
--   * B3: o evento sem as `resolvidas` de item_sem_conteudo: 1 dos 106 asserts.
--   * B3: o evento sem as `mantidas` de item_sem_conteudo: 1 dos 106 asserts.
--   * B3: o evento sem as `resolvidas` de linha_exigida_ausente: 1 dos 106 asserts.
--   * B3: o evento sem as `mantidas` de linha_exigida_ausente: 1 dos 106 asserts.
--   O assert "anon: 42501" sozinho NÃO pega o EXECUTE a public (o 42501 vem da tabela); por isso o assert de has_function_privilege à parte.
--   A variante "o ramo vale para qualquer tipo" só reprovou depois de o teste ganhar o cenário em que uma PESSOA resolve a falha do balanço: sem ele a mutação dava 0, porque fn_versao_extracao_concluida já embute a natureza do tipo.
--   Protocolo: cada variante foi a migration inteira com UMA edição, aplicada sobre o banco montado; o teste rodou com PGOPTIONS='-c ct300.medindo=on'; a migration original foi reaplicada e o controle deu 0 reprovações.
-- =============================================================================

begin;

-- `alter table pendencia ... references documento` pede ACCESS EXCLUSIVE em pendencia (e SHARE ROW EXCLUSIVE em documento). pendencia é escrita a cada
-- extração (a conferência abre e resolve linhas nela); sem teto de espera, o ALTER entra na fila atrás de uma transação longa e TODA escrita nova
-- em pendencia fica atrás dele. 5 s: se não pegar o lock, a migration falha inteira (nada aplicado) e o dono tenta de novo fora do lote.
set local lock_timeout = '5s';

alter table pendencia
  add column if not exists chave_motor text,
  add column if not exists resolvida_por_documento_id uuid references documento(id) on delete set null;

comment on column pendencia.chave_motor is
  '0300: a chave estável com que o MOTOR de completude acha a sua própria pendência (hoje: completude:item_faltante:<TIPO>). Coluna própria porque `motivo` é sobrescrito por fn_decidir_pendencia (coalesce(p_motivo, motivo)) e o texto da `descricao` muda quando alguém melhora a frase: chave que mora num deles duplica ou resolve a pendência errada. Nulo = a pendência não é de um motor que use chave (ex.: item_faltante de contrato social, motivo contrato_social_ausente:<id>, 0208).';
comment on column pendencia.resolvida_por_documento_id is
  '0300: o documento cuja chegada fechou a pendência item_faltante (o primeiro que serve depois de ela abrir; sem nenhum depois, o primeiro que serve). Nulo = não foi fechada por documento (decisão de pessoa, outro motor) ou o tipo deixou de ser obrigatório. NÃO é pendencia.documento_id: fn_revisar_documento resolve por ele.';

create or replace function fn_adotar_chave_item_faltante(p_caso_id uuid default null)
returns bigint
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_n bigint;
begin
  update pendencia p
     set chave_motor = 'completude:item_faltante:' || substr(p.descricao, length('Item obrigatório do Kit Básico ausente: ') + 1)
   where p.tipo = 'item_faltante' and p.estado <> 'resolvida' and p.chave_motor is null
     and starts_with(p.descricao, 'Item obrigatório do Kit Básico ausente: ')
     and (p_caso_id is null or p.caso_id = p_caso_id);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

comment on function fn_adotar_chave_item_faltante(uuid) is
  '0300: dá a chave estável (pendencia.chave_motor) às item_faltante do Kit Básico ainda não resolvidas que o motor abriu antes da 0300 (descrição com o prefixo "Item obrigatório do Kit Básico ausente: "). Um mandato ou, com NULL, todos. Devolve quantas adotou. Idempotente: a segunda chamada devolve 0. O item_faltante de outro assunto (contrato_social_ausente) não tem esse prefixo e fica de fora.';

revoke all on function fn_adotar_chave_item_faltante(uuid) from public, anon;
grant execute on function fn_adotar_chave_item_faltante(uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- fn_recomputar_completude — REEMITIDA INTEIRA (corpo da 0188; o diff está nos blocos marcados 0300).
-- -----------------------------------------------------------------------------
create or replace function fn_recomputar_completude(p_caso_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_faltantes text[];
  v_sem_conteudo text[];
  v_cod text;
  v_nao_sobre boolean;
  v_status_atual caso_status;
  v_novo_status caso_status;
  v_pend_id uuid;
  -- 0113/0119: passo (2b)
  v_ex record;
  v_motivo text;
  v_motivos_ausentes text[] := '{}';
  v_linhas_ausentes jsonb := '[]'::jsonb;
  -- 0188
  v_desc text;
  -- 0300: a chave estável do item faltante, o rastro do fechamento e o sinal positivo de que a conferência rodou
  c_chave_ft constant text := 'completude:item_faltante:';
  v_chaves text[];
  v_fechadas jsonb;
  v_ft_abertas int := 0;
  v_ft_mantidas int;
  v_sc_abertas int := 0;
  v_sc_resolvidas int := 0;
  v_sc_mantidas int;
  v_le_abertas int := 0;
  v_le_resolvidas int := 0;
  v_le_mantidas int;
begin
  -- ----- (1) obrigatório sem NENHUM documento QUE SIRVA (0006/0157) ----------
  -- 0157: "sem documento" deixava de contar um documento que ESTÁ no caso só
  -- porque o classificador o rotulou diferente do que ele estruturalmente é —
  -- medido no lote 7377, dois COMBINADOs (8 empresas na planilha) chamados de
  -- BALANCO travavam o item COMBINADO como ausente e bloqueante. Agora a
  -- pergunta é fn_documento_serve_como(documento, tipo): a regra do rótulo,
  -- mais — só para COMBINADO — a decisão de fn_combinado_estrutural_apto
  -- (revisão da 0157, achados A e B: fonte permitida e conteúdo exigido).
  select array_agg(t.codigo order by t.codigo) into v_faltantes
  from taxonomia_tipo_documento t
  where t.obrigatoriedade = 'obrigatorio'
    and not exists (
      select 1 from documento d
      where d.caso_id = p_caso_id and fn_documento_serve_como(d.id, t.codigo)
    );
  v_faltantes := coalesce(v_faltantes, array[]::text[]);

  -- 0300: a pendência é achada pela CHAVE (pendencia.chave_motor = 'completude:item_faltante:<TIPO>'), não pelo texto da descrição.
  -- Antes, mudar a frase da descrição duplicava a pendência aberta e resolvia a velha (I1.8). A adoção pega a que um motor antigo
  -- deixou sem chave (a migration e uma conferência em andamento podem se cruzar) com a MESMA função do backfill.
  perform fn_adotar_chave_item_faltante(p_caso_id);
  v_chaves := array(select c_chave_ft || x from unnest(v_faltantes) x);

  -- 0300: resolve só o que o PRÓPRIO motor abriu (chave com o prefixo). Até a 0299 o filtro era "item_faltante cuja descrição não
  -- está na lista", e resolvia também o item_faltante de OUTRO assunto (contrato_social_ausente:<id>, 0208): 2 abertas em produção
  -- em 13/11/2026, esperando a conferência seguinte do mandato para sumirem sem ninguém ter recebido contrato nenhum.
  -- D1.3: resolve também a que uma PESSOA decidiu (aceita_com_ressalva, rejeitada) — o documento chegou, o problema deixou de existir —
  -- e o estado anterior, quem decidiu e quando vão para o evento (a coluna resolvida_por é sobrescrita, o evento é append-only).
  with alvo as materialized (
    select p.id, p.estado as estado_anterior, p.resolvida_por as resolvida_por_anterior,
           p.resolvida_em as resolvida_em_anterior,
           substr(p.chave_motor, length(c_chave_ft) + 1) as tipo
      from pendencia p
     where p.caso_id = p_caso_id and p.tipo = 'item_faltante' and p.estado <> 'resolvida'
       and starts_with(p.chave_motor, c_chave_ft)
       and not (p.chave_motor = any (v_chaves))
  ), fechou as (
    update pendencia p
       set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:n8n',
           -- o documento que fechou: o primeiro que serve e chegou depois de a pendência abrir; sem nenhum depois (reclassificação),
           -- o primeiro que serve; sem nenhum (o tipo deixou de ser obrigatório), nulo — e nulo é a verdade, não um chute.
           resolvida_por_documento_id = (
             select d.id from documento d
              where d.caso_id = p.caso_id and fn_documento_serve_como(d.id, a.tipo)
              order by (d.criado_em >= p.criada_em) desc, d.criado_em, d.id
              limit 1)
      from alvo a
     where p.id = a.id
    returning p.id, p.resolvida_por_documento_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'pendencia_id', a.id, 'tipo', a.tipo,
           'estado_anterior', a.estado_anterior::text,
           'resolvida_por_anterior', a.resolvida_por_anterior,
           'resolvida_em_anterior', a.resolvida_em_anterior,
           'documento_id', f.resolvida_por_documento_id) order by a.tipo, a.id), '[]'::jsonb)
    into v_fechadas
    from alvo a join fechou f on f.id = a.id;

  foreach v_cod in array v_faltantes loop
    select nao_sobrepujavel into v_nao_sobre from taxonomia_tipo_documento where codigo = v_cod;
    if not exists (
      select 1 from pendencia p
      where p.caso_id = p_caso_id and p.tipo = 'item_faltante'
        and p.estado <> 'resolvida'
        and p.chave_motor = c_chave_ft || v_cod
    ) then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, chave_motor)
        values (p_caso_id, 'completude', 'item_faltante', 'bloqueante',
                not coalesce(v_nao_sobre,false),
                'Item obrigatório do Kit Básico ausente: '||v_cod,
                c_chave_ft || v_cod);
      v_ft_abertas := v_ft_abertas + 1;
    end if;
  end loop;

  -- ----- (2) obrigatório PRESENTE mas sem uma linha aproveitável (0036) ------
  select array_agg(t.codigo order by t.codigo) into v_sem_conteudo
  from taxonomia_tipo_documento t
  where t.obrigatoriedade = 'obrigatorio'
    and exists (
      select 1 from documento d
      where d.caso_id = p_caso_id and d.tipo_taxonomia = t.codigo
    )
    and fn_linhas_do_tipo(p_caso_id, t.codigo) = 0;
  v_sem_conteudo := coalesce(v_sem_conteudo, array[]::text[]);

  update pendencia p set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
  where p.caso_id = p_caso_id and p.tipo = 'item_sem_conteudo' and p.estado <> 'resolvida'
    and not (p.motivo = any (select 'completude:sem_conteudo:'||x from unnest(v_sem_conteudo) x));
  get diagnostics v_sc_resolvidas = row_count;

  foreach v_cod in array v_sem_conteudo loop
    if not exists (
      select 1 from pendencia p
      where p.caso_id = p_caso_id and p.tipo = 'item_sem_conteudo'
        and p.estado <> 'resolvida' and p.motivo = 'completude:sem_conteudo:'||v_cod
    ) then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, motivo)
        values (p_caso_id, 'completude', 'item_sem_conteudo', 'bloqueante', false,
                format('Item obrigatório "%s" foi RECEBIDO, mas nenhuma linha foi extraída de nenhuma '
                       'versão dele: o documento existe e o book sai VAZIO nesta parte. Causas comuns: '
                       'formato que o pipeline ainda não converte (.xlsx/.docx), arquivo ilegível, ou '
                       'chamada de extração que falhou. Conferir o arquivo e reenviar — completude não '
                       'é validade (Arquitetura do Sistema/3 Estado e Execução/07), e um obrigatório sem conteúdo não passa o Portão 2.',
                       v_cod),
                'completude:sem_conteudo:'||v_cod);
      v_sc_abertas := v_sc_abertas + 1;
    end if;
  end loop;

  -- ----- (2b) 0113/0119: tipo COM conteúdo, mas sem uma LINHA exigida --------
  -- 0119: a cobrança desce ao nível da ENTIDADE quando o escopo pede. O motivo
  -- ganha o sufixo canônico da entidade (chave estável mesmo que a grafia da
  -- razão social varie entre extrações), `entidade_id` vai na pendência, e a
  -- descrição nomeia a empresa. Pendência de formato velho (sem sufixo) sai da
  -- lista corrente e é resolvida no fim do bloco — é a transição, e a trilha
  -- guarda as duas gerações.
  for v_ex in
    select * from fn_exigencias_do_caso(p_caso_id) x where not x.satisfeita
  loop
    v_motivo := 'completude:linha_exigida:' || v_ex.tipo_taxonomia || ':' || v_ex.conceito
                || case when v_ex.entidade is not null
                        then ':' || fn_entidade_canonica(v_ex.entidade)
                        else '' end;
    v_motivos_ausentes := v_motivos_ausentes || v_motivo;
    v_linhas_ausentes := v_linhas_ausentes || jsonb_build_object(
      'tipo', v_ex.tipo_taxonomia, 'conceito', v_ex.conceito,
      'rotulo', v_ex.rotulo, 'origem', v_ex.origem,
      'entidade', v_ex.entidade,
      -- 0188: o que o documento traz no lugar, quando traz.
      'alternativa', v_ex.alternativa_rotulo);

    -- 0188: o texto sai de UM lugar, com o recado da alternativa quando ela
    -- casou (taxonomia_linha_alternativa). Sem alternativa, é o texto de sempre.
    v_desc := fn_descricao_linha_exigida(v_ex.tipo_taxonomia, v_ex.entidade, v_ex.rotulo,
                                         v_ex.depende_de, v_ex.origem,
                                         v_ex.alternativa_rotulo, v_ex.alternativa_recado);

    select id into v_pend_id from pendencia p
    where p.caso_id = p_caso_id and p.tipo = 'linha_exigida_ausente'
      and p.estado <> 'resolvida'
      and p.motivo = v_motivo
    limit 1;

    if v_pend_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel,
                             descricao, entidade_id, motivo)
        values (p_caso_id, 'completude', 'linha_exigida_ausente',
                coalesce(v_ex.severidade, 'importante')::pendencia_severidade,
                coalesce(v_ex.sobrepujavel, true),
                v_desc,
                v_ex.entidade_id,
                v_motivo);
      v_le_abertas := v_le_abertas + 1;
    else
      -- 0188: a DESCRIÇÃO também é atualizada. Até a 0187 só a política era, e
      -- a pendência aberta antes de uma alternativa existir ficava para sempre
      -- com o texto da doença errada.
      update pendencia set
        severidade   = coalesce(v_ex.severidade, 'importante')::pendencia_severidade,
        sobrepujavel = coalesce(v_ex.sobrepujavel, true),
        descricao    = case when descricao is distinct from v_desc then v_desc else descricao end
      where id = v_pend_id;
    end if;
  end loop;

  -- A linha apareceu, a exigência foi desativada, ou o formato do motivo mudou
  -- (a transição 0113 → 0119): resolve sozinha, como as da 0036.
  update pendencia p set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
  where p.caso_id = p_caso_id and p.tipo = 'linha_exigida_ausente' and p.estado <> 'resolvida'
    and not (p.motivo = any (v_motivos_ausentes));
  get diagnostics v_le_resolvidas = row_count;

  -- ----- (3) o checklist reflete os três estados (0036) ----------------------
  update checklist_item_status c
    set status = case
                   when fn_linhas_do_tipo(p_caso_id, c.tipo_taxonomia) = 0 then 'recebido_nao_valido'
                   else 'presente'
                 end,
        atualizado_em = now()
  where c.caso_id = p_caso_id
    and c.documento_id is not null
    and c.status in ('presente', 'recebido_nao_valido');

  -- ----- (4) status do caso: Portão 1 continua sendo CHEGADA (0036) ----------
  select status into v_status_atual from caso where id = p_caso_id;
  if array_length(v_faltantes,1) is null then
    v_novo_status := 'completude_ok';
  else
    v_novo_status := 'em_triagem';
  end if;

  if v_status_atual in ('intake','em_triagem','completude_ok') and v_novo_status <> v_status_atual then
    update caso set status = v_novo_status where id = p_caso_id;
    insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
      values ('sistema:n8n', 'transicao_status', 'caso:'||p_caso_id,
              jsonb_build_object('status', v_status_atual),
              jsonb_build_object('status', v_novo_status));
  end if;

  -- 0300 (regra 7): o sinal POSITIVO de que a conferência rodou, gravado SEMPRE — inclusive com tudo zero. Antes só a troca de status do
  -- caso deixava rastro, e uma conferência que não achou nada tinha a mesma cara de uma que nunca rodou. fn_kit_do_caso lê o
  -- último destes eventos (conferencia_em) e conta os documentos que chegaram depois dele.
  select count(*) into v_ft_mantidas from pendencia p
   where p.caso_id = p_caso_id and p.tipo = 'item_faltante' and p.estado <> 'resolvida' and starts_with(p.chave_motor, c_chave_ft);
  v_ft_mantidas := v_ft_mantidas - v_ft_abertas;
  select count(*) into v_sc_mantidas from pendencia p
   where p.caso_id = p_caso_id and p.tipo = 'item_sem_conteudo' and p.estado <> 'resolvida' and starts_with(p.motivo, 'completude:sem_conteudo:');
  v_sc_mantidas := v_sc_mantidas - v_sc_abertas;
  select count(*) into v_le_mantidas from pendencia p
   where p.caso_id = p_caso_id and p.tipo = 'linha_exigida_ausente' and p.estado <> 'resolvida' and starts_with(p.motivo, 'completude:linha_exigida:');
  v_le_mantidas := v_le_mantidas - v_le_abertas;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'completude_recomputada', 'caso:' || p_caso_id,
            jsonb_build_object(
              'item_faltante', jsonb_build_object(
                 'abertas', v_ft_abertas, 'resolvidas', jsonb_array_length(v_fechadas), 'mantidas', v_ft_mantidas,
                 'faltantes', to_jsonb(v_faltantes), 'fechadas', v_fechadas),
              'item_sem_conteudo', jsonb_build_object(
                 'abertas', v_sc_abertas, 'resolvidas', v_sc_resolvidas, 'mantidas', v_sc_mantidas),
              'linha_exigida_ausente', jsonb_build_object(
                 'abertas', v_le_abertas, 'resolvidas', v_le_resolvidas, 'mantidas', v_le_mantidas),
              'status_caso', v_novo_status));

  return jsonb_build_object(
    'portao1_ok', array_length(v_faltantes,1) is null,
    'faltantes', to_jsonb(v_faltantes),
    'sem_conteudo', to_jsonb(v_sem_conteudo),
    -- 0119: cada ausência agora pode nomear a entidade. `pronto_para_revisao`
    -- segue intocado — endurecê-lo é decisão de produto do dono, não efeito
    -- colateral (0113).
    'linhas_exigidas_ausentes', v_linhas_ausentes,
    'pronto_para_revisao',
      array_length(v_faltantes,1) is null and array_length(v_sem_conteudo,1) is null,
    'status', v_novo_status
  );
end;
$$;

comment on function fn_recomputar_completude(uuid) is
  'Portão 1 (chegada) + 0036 (recebido sem conteúdo) + 0113/0119 (passo 2b: linha exigida ausente, por entidade quando o escopo pede) + 0157 (passo 1: "sem documento do tipo" vira "sem documento que SIRVA como o tipo", fn_documento_serve_como) + 0300 (a item_faltante é achada pela chave pendencia.chave_motor, não pelo texto; só resolve a que o motor abriu; resolve também a decidida por pessoa guardando o estado anterior no evento; grava pendencia.resolvida_por_documento_id; grava SEMPRE o evento completude_recomputada com as contagens). Política por linha é do dono; default = importante/sobrepujável. `portao1_ok` segue "chegou tudo"; `pronto_para_revisao` segue "chegou tudo E tem conteúdo".';

-- -----------------------------------------------------------------------------
-- fn_kit_do_caso — o estado do item do Kit Básico, DERIVADO na leitura (nada gravado que envelheça).
-- A tela interna, o export e, depois, o link do cliente leem ESTA função: duas implementações da mesma conta divergem sem erro nenhum.
-- -----------------------------------------------------------------------------
create or replace function fn_kit_do_caso(p_caso uuid)
returns table (
  tipo text,
  estado text,
  motivo text,
  documentos uuid[],
  docs_por_estado jsonb,
  conferido_por text,
  conferido_em timestamptz,
  empresas_total int,
  empresas_com_documento int,
  empresas_atendidas int,
  documentos_sem_empresa int,
  aguardando_desde timestamptz,
  conferencia_em timestamptz,
  documentos_depois_da_conferencia int
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with kit as materialized (
    -- "N de M empresas" só faz sentido onde o item é cobrado por empresa (granularidade entidade e entidade_periodo): MUTUOS e FAT_INTRAGRUPO
    -- são do caso, COMBINADO é do período — um documento só os cumpre, e "1 de 8" para item completo seria número falso.
    select t.codigo, t.granularidade::text in ('entidade', 'entidade_periodo') as por_empresa
      from taxonomia_tipo_documento t where t.obrigatoriedade = 'obrigatorio'
  ),
  -- A pergunta "este documento serve como o tipo" é a de fn_documento_serve_como (0157), a mesma do passo 1 da conferência.
  serve as materialized (
    select k.codigo, d.id as doc, d.tipo_taxonomia as tipo_doc, d.entidade_id, d.criado_em, fn_versao_com_extracao(d.id) as v,
           exists (select 1 from entidade e
                    where e.id = d.entidade_id and e.papel_no_grupo is distinct from 'fora_do_perimetro') as no_perimetro
      from kit k
      join documento d on d.caso_id = p_caso and fn_documento_serve_como(d.id, k.codigo)
  ),
  lido as materialized (
    select s.*,
           case
             -- sem versão com linha: ou a leitura já acabou sem dado, ou o sistema já declarou que não vai acontecer, ou ainda não acabou
             when s.v is null then
               case
                 -- o sistema JÁ disse que a leitura não houve: fn_conferir_lote abre documento_nao_extraido (a extração nunca foi chamada),
                 -- e o diagnóstico abre arquivo_ilegivel/arquivo_corrompido. Esperar por uma leitura que ele já declarou perdida é mentir "aguardando".
                 when exists (select 1 from pendencia pe
                               where pe.documento_id = s.doc and pe.estado <> 'resolvida'
                                 and pe.tipo in ('documento_nao_extraido', 'arquivo_ilegivel', 'arquivo_corrompido'))
                      then 'recebido_sem_linha'
                 -- leitura concluída SEM dado em tipo que não traz dado financeiro por natureza (contrato social, certidão): zero linha é o
                 -- resultado certo, não falta (fn_tipo_sem_dado_por_natureza, 0231). Não há linha a conferir.
                 when fn_tipo_sem_dado_por_natureza(s.tipo_doc)
                      and exists (select 1 from documento_versao dv
                                   where dv.documento_id = s.doc and fn_versao_extracao_concluida(dv.id))
                      then 'lido_sem_dado_por_natureza'
                 when exists (select 1 from documento_versao dv
                               where dv.documento_id = s.doc and fn_versao_extracao_concluida(dv.id))
                      or exists (select 1 from pendencia pe
                                  where pe.documento_id = s.doc and pe.tipo = 'extracao_falhou' and pe.estado <> 'resolvida')
                      then 'recebido_sem_linha'
                 else 'aguardando_extracao' end
             -- com linha, mas alguma sem aceite de PESSOA (o auto-aceite `sistema:` não conta)
             when exists (select 1 from campo_extraido ce
                           where ce.documento_versao_id = s.v
                             and not (ce.status_aceite <> 'pendente' and ce.aceito_por is not null
                                      and ce.aceito_por not like 'sistema:%')) then 'extraido'
             else 'conferido'
           end as estado
      from serve s
  ),
  aceite as materialized (
    select l.codigo, max(ce.aceito_em) as em,
           (array_agg(ce.aceito_por order by ce.aceito_em desc nulls last))[1] as por
      from lido l
      join campo_extraido ce on ce.documento_versao_id = l.v
     where l.estado = 'conferido'
     group by l.codigo
  ),
  item as materialized (
    select k.codigo, k.por_empresa,
           count(l.doc)::int as n_docs,
           coalesce(array_agg(l.doc order by l.criado_em, l.doc) filter (where l.doc is not null), '{}') as docs,
           -- o documento lido-sem-dado-por-natureza não pesa: não há linha a conferir nele; só vale como estado do item se for o ÚNICO
           min(case l.estado when 'recebido_sem_linha' then 1 when 'aguardando_extracao' then 2
                             when 'extraido' then 3 when 'conferido' then 4 end)
             filter (where l.estado <> 'lido_sem_dado_por_natureza') as pior,
           min(l.criado_em) filter (where l.estado = 'aguardando_extracao') as aguardando_desde,
           count(*) filter (where l.doc is not null and l.entidade_id is null)::int as sem_empresa,
           count(distinct l.entidade_id) filter (where l.no_perimetro)::int as com_documento,
           count(distinct l.entidade_id) filter (where l.no_perimetro and l.estado in ('extraido', 'conferido', 'lido_sem_dado_por_natureza'))::int as lidas
      from kit k
      left join lido l on l.codigo = k.codigo
     group by k.codigo, k.por_empresa
  ),
  conf as (
    select max(ev.criado_em) as em
      from evento_auditoria ev
     where ev.acao = 'completude_recomputada' and ev.entidade_ref = 'caso:' || p_caso::text
  ),
  m as (
    select count(*)::int as n from entidade e
     where e.caso_id = p_caso and e.papel_no_grupo is distinct from 'fora_do_perimetro'
  )
  select i.codigo::text,
         est.estado,
         case est.estado
           when 'faltante' then
             format('Nenhum documento recebido serve como %s. Enquanto faltar, o Portão 1 não abre e o que depende dele sai em branco no book.', i.codigo)
           when 'dispensado' then
             format('Seguiu sem %s por decisão de pessoa (prosseguir com ressalva). O que depende dele sai em branco no book, e a ressalva fica na pendência.', i.codigo)
           when 'aguardando_extracao' then
             'Recebido, mas a leitura ainda não terminou: nenhuma versão concluiu a extração e não há falha registrada. Se isto não mudar, o documento ficou sem leitura e o book sai vazio nesta parte.'
           when 'recebido_sem_linha' then
             'Recebido, mas nenhuma linha foi lida (a extração falhou, nunca foi chamada ou o arquivo está ilegível): o book sai VAZIO nesta parte, mesmo com o item recebido.'
           when 'lido_sem_dado_por_natureza' then
             'Lido: este tipo de documento (societário/legal) não traz dado financeiro, então não há linha a conferir. O book não depende de linha dele.'
           when 'extraido' then
             'Lido, mas nenhuma pessoa conferiu todas as linhas. O aceite automático do sistema não conta como conferência.'
           else
             'Toda linha da versão vigente foi aceita por pessoa.'
         end,
         i.docs,
         coalesce((select jsonb_object_agg(g.estado, g.n)
                     from (select l2.estado, count(*) as n from lido l2 where l2.codigo = i.codigo group by l2.estado) g),
                  '{}'::jsonb),
         case when est.estado = 'conferido' then a.por end,
         case when est.estado = 'conferido' then a.em end,
         case when i.por_empresa then m.n end,
         case when i.por_empresa then i.com_documento end,
         case when i.por_empresa then i.lidas end,
         case when i.por_empresa then i.sem_empresa end,
         i.aguardando_desde,
         conf.em,
         (select count(*)::int from documento d where d.caso_id = p_caso and (conf.em is null or d.criado_em > conf.em))
    from item i
    cross join conf
    cross join m
    left join aceite a on a.codigo = i.codigo
    cross join lateral (
      select case
               when i.n_docs = 0 then
                 case when exists (select 1 from pendencia pe
                                    where pe.caso_id = p_caso and pe.tipo = 'item_faltante'
                                      and pe.chave_motor = 'completude:item_faltante:' || i.codigo
                                      and pe.estado = 'aceita_com_ressalva')
                      then 'dispensado' else 'faltante' end
               when i.pior is null then 'lido_sem_dado_por_natureza'
               when i.pior = 1 then 'recebido_sem_linha'
               when i.pior = 2 then 'aguardando_extracao'
               when i.pior = 3 then 'extraido'
               else 'conferido'
             end as estado
    ) est
   -- mandato que o chamador não enxerga (RLS) ou que não existe: nenhuma linha, nunca "tudo faltante"
   where exists (select 1 from caso c where c.id = p_caso)
   order by i.codigo;
$$;

comment on function fn_kit_do_caso(uuid) is
  '0300: o estado de cada item OBRIGATÓRIO do Kit Básico do mandato, derivado de campo_extraido na leitura. Estados: faltante, dispensado (item_faltante aceita_com_ressalva e ainda sem documento), aguardando_extracao (aguardando_desde = o criado_em do documento mais antigo nessa espera), recebido_sem_linha (extração concluída ou falha aberta sem linha, OU o sistema já declarou documento_nao_extraido/arquivo_ilegivel/arquivo_corrompido aberta), lido_sem_dado_por_natureza (leitura concluída sem dado em tipo societário/legal: não há linha a conferir), extraido, conferido (toda linha da versão vigente aceita por PESSOA; o auto-aceite sistema: não conta). O item toma o pior estado dos documentos que servem (o lido_sem_dado_por_natureza não pesa, salvo se for o único). empresas_total/com_documento/atendidas/documentos_sem_empresa dizem "N de M" SÓ para granularidade entidade e entidade_periodo (M sem fora_do_perimetro); nos demais tipos (caso, periodo) são NULOS e a tela não mostra fração. conferencia_em = último evento completude_recomputada; documentos_depois_da_conferencia = documentos criados depois dele (todos se nunca rodou). Mandato invisível ao chamador (RLS) = zero linhas, e o portal deve ler isso como "Kit não lido", nunca como faltante. security invoker.';

revoke all on function fn_kit_do_caso(uuid) from public, anon;
grant execute on function fn_kit_do_caso(uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- BACKFILL: dá a chave às item_faltante do Kit ainda não resolvidas. Não muda estado, descrição nem resolução de ninguém; só atribui a
-- chave. A contagem vai para o evento, e zero também grava (regra 7: zero medido e zero que não rodou não podem parecer iguais).
-- -----------------------------------------------------------------------------
do $$
declare
  v_n bigint;
begin
  v_n := fn_adotar_chave_item_faltante(null);
  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:0300', 'chave_motor_item_faltante_adotada', 'migration:0300',
            jsonb_build_object('adotadas', v_n));
  raise notice '0300: % item_faltante do Kit receberam chave_motor', v_n;
end $$;

-- -----------------------------------------------------------------------------
-- A SONDA. Marcadores em CÓDIGO, nunca de comentário (a sonda lê pg_get_functiondef, que traz os comentários do corpo).
-- -----------------------------------------------------------------------------
create or replace view instalacao_sonda_kit_invoker as
  select count(*)::text as n
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('fn_kit_do_caso', 'fn_adotar_chave_item_faltante')
     and not p.prosecdef
     and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
     and (p.proname <> 'fn_kit_do_caso' or p.provolatile = 's')
  having count(*) = 2;
comment on view instalacao_sonda_kit_invoker is
  'Sonda da 0300: uma linha = fn_kit_do_caso (stable) e fn_adotar_chave_item_faltante são security invoker com search_path fixo. Zero linhas: alguma virou security definer e o authenticated lê o Kit, ou altera pendência, de mandato alheio.';
grant select on instalacao_sonda_kit_invoker to authenticated, service_role;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('kit_do_caso_funcao', '0300', 'funcao', 'fn_kit_do_caso', null, null,
   'O estado do item do Kit (faltante, aguardando, sem linha, lido, conferido) derivado no banco. Ausente = a tela volta a distinguir só "recebido" de "falta", e o documento que nunca foi lido continua parecendo bom (267 linhas de checklist presente sem nenhuma linha, medido em produção em 13/11/2026).',
   'importante', 1364),
  ('kit_conferido_so_por_pessoa', '0300', 'corpo', 'fn_kit_do_caso', 'ce.aceito_por not like ''sistema:%''', null,
   'conferido exige aceite de PESSOA. Corpo sem o filtro = o auto-aceite do sistema (confiança >= 95%) conta como conferência e o Kit mostra "conferido" para o que ninguém olhou.',
   'bloqueante', 1365),
  ('kit_reusa_serve_como', '0300', 'corpo', 'fn_kit_do_caso', 'fn_documento_serve_como(', null,
   'A decisão de quem serve um item mora em fn_documento_serve_como (0157). Corpo sem a chamada = uma segunda regra que diverge da primeira sem erro nenhum.',
   'bloqueante', 1366),
  ('pendencia_chave_motor_coluna', '0300', 'coluna', 'pendencia.chave_motor', null, null,
   'A chave estável da item_faltante. Ausente = a conferência volta a achar a pendência pelo texto da descrição: mudar a frase duplica a aberta e resolve a velha.',
   'bloqueante', 1367),
  ('pendencia_resolvida_por_documento_coluna', '0300', 'coluna', 'pendencia.resolvida_por_documento_id', null, null,
   'Qual documento fechou a pendência item_faltante. Ausente = nada prova que foi a chegada do documento, e a decisão de pessoa sobrescrita não deixa rastro do que a fechou.',
   'importante', 1368),
  ('completude_evento_sempre', '0300', 'corpo', 'fn_recomputar_completude', '''sistema:n8n'', ''completude_recomputada''', null,
   'O sinal positivo de que a conferência rodou, gravado sempre (inclusive com tudo zero). Corpo anterior à 0300 = conferência que não achou nada tem a mesma cara de conferência que nunca rodou (regra 7) e o Kit não sabe dizer "N documentos chegaram depois da última conferência".',
   'bloqueante', 1369),
  ('completude_item_faltante_por_chave', '0300', 'corpo', 'fn_recomputar_completude', 'c_chave_ft constant text := ''completude:item_faltante:''', null,
   'A item_faltante achada pela chave e não pelo texto, resolvendo só a que o motor abriu. Corpo anterior = frase da descrição que muda duplica a pendência e item_faltante de contrato social some na próxima conferência.',
   'bloqueante', 1370),
  ('kit_nao_extraido_nao_aguarda', '0300', 'corpo', 'fn_kit_do_caso', '''documento_nao_extraido''', null,
   'Documento que o sistema já declarou sem extração (documento_nao_extraido, arquivo_ilegivel, arquivo_corrompido) é recebido_sem_linha, não aguardando. Corpo sem isto = o Kit diz "aguardando leitura" de documento cuja leitura o sistema já deu como perdida: 63 documentos com arquivo_ilegivel aberta em produção em 13/11/2026.',
   'bloqueante', 1372),
  ('kit_leitura_invoker', '0300', 'comportamento', 'instalacao_sonda_kit_invoker', null, 1,
   'fn_kit_do_caso e fn_adotar_chave_item_faltante rodam COM a RLS de quem chama (security invoker). Zero linhas = alguma virou security definer e um usuário lê o Kit, ou altera pendência, de mandato alheio.',
   'bloqueante', 1371)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0300', revisado_em = current_date,
       observacao = 'A 0300 cria fn_kit_do_caso (estado do item do Kit derivado na leitura), fn_adotar_chave_item_faltante, pendencia.chave_motor e pendencia.resolvida_por_documento_id, e reemite fn_recomputar_completude (chave estável, documento que fechou, evento completude_recomputada sempre). 9 requisitos novos (ordem 1364-1372). A 0275 continua reservada ao aging: nunca rebaixar esta cobertura quando ela entrar.'
 where id = true;

commit;
