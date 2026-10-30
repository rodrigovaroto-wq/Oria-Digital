-- =============================================================================
-- 0218 — O DIAL QUE SÓ MEDIA O RECORTE DE QUEM DISPARAVA, e o `anon` que tinha privilégio demais
-- (Cria 1 função (fn_exige_metrica); REDEFINE 7 (fn_veredito_producao, fn_golden_classe_a, fn_golden_cobertura, fn_classe_contabil_concordancia,
--  fn_dial_auto_promover, fn_trg_auto_promover_dial, fn_trg_so_socio) e fn_instalacao_conferir (+1 tipo, `sem_privilegio`); REVOGA de anon todo
--  privilégio em public; +12 requisitos na sonda. Sem tabela, sem backfill, sem dado alterado. Idempotente: pode ser reaplicada.)
--
-- >>> RODE COMO `postgres`. O default privilege do `supabase_admin` NÃO é alterado (exige ser membro dele): objeto que ELE criar em public
-- >>> (extensões) continua nascendo com privilégio para anon. Função de extensão (unaccent, de supabase_admin) e objeto de outro dono ficam como
-- >>> estão: o REVOKE de quem não é dono só avisa, e a sonda os ignora de propósito. NÃO toca em `storage` nem em `supabase_migrations`.
--
-- ===== DEFEITO 1 (crítico, latente): o dial se promovia sobre o recorte de quem disparava =====
-- Medido em produção em 30/10/2026 (somente leitura): fn_dial_auto_promover, fn_veredito_producao, fn_trg_auto_promover_dial, fn_golden_cobertura,
-- fn_classe_contabil_concordancia e fn_mudar_dial eram INVOKER. O gatilho trg_auto_promover_dial (AFTER INSERT em decisao) chama fn_veredito_producao,
-- que lê `decisao` de todos os mandatos (p_caso_id nulo). Com a RLS da 0216 ele passa a ler só os mandatos de QUEM DECIDIU, e depois o dial
-- (estagio_autonomia, uma linha para todo mundo) muda para todos. Cenário: concordância global 85% com 400 vereditos; Analista alocada em 3 mandatos
-- com 25 vereditos a 96% decide uma pendência; o veredito sobre o recorte dela dá "suficiente" e o estágio sobe para todos. NÃO acontecia em produção
-- (1 usuário, Sócio, que vê tudo; 0 alocações); passa a valer no primeiro Analista.
-- UM FATO QUE O PEDIDO NÃO TINHA E A MEDIÇÃO ACHOU: com a 0216 aplicada o cenário acima já nasce MASCARADO por outro defeito, no sentido oposto. A guarda de
-- Sócio do dial (trg_estagio_autonomia_so_socio) vale também para a promoção automática: o Analista decide, o gatilho roda, fn_mudar_dial leva 42501, e
-- o `exception when others` do gatilho (0137) engole como NOTICE. Resultado hoje: decisão de Analista NUNCA sobe o dial, nem com a global em 100%
-- (calado, regra 7). Corrigir só o veredito (definer) NÃO bastaria — liberaria a falha nos dois sentidos — e corrigir só a guarda abriria o defeito
-- original. As duas têm de sair juntas, e o teste afirma os dois sentidos (seções 1 e 2).
-- A CORREÇÃO, em quatro partes:
--   (a) fn_veredito_producao, fn_golden_classe_a, fn_golden_cobertura e fn_classe_contabil_concordancia viram SECURITY DEFINER com search_path fixo
--       e devolvem SÓ número e veredito, nunca linha de mandato. A guarda nova fn_exige_metrica exige papel no portal (ou conexão de serviço) e, com
--       p_caso_id, poder ler o mandato (fn_pode_ler_caso): 42501 nos dois casos. Corpo de cada uma: o VIGENTE (0126, 0128, 0138), reemitido inteiro;
--       as três que eram `language sql` viraram plpgsql só para poder levantar erro antes da consulta.
--       Efeito na tela /autonomia (fn_golden_cobertura e fn_classe_contabil_concordancia, a ausência apresentada como dado): o Analista via ZERO documentos
--       rotulados (as tabelas do golden são do Sócio, 0216) e a concordância do SEU recorte como se fosse a do sistema; agora vê o número do banco.
--   (b) fn_dial_auto_promover e fn_trg_auto_promover_dial viram SECURITY DEFINER: a promoção mede o veredito global e não depende do recorte nem do papel
--       de quem decidiu. fn_dial_auto_promover é FECHADA ao authenticated (nenhum chamador no portal nem no n8n: grep); só o gatilho e o service_role.
--   (c) fn_trg_so_socio (a guarda de Sócio do dial) ganha UMA exceção estreita: o UPDATE a N2, base medida_por_veredito, autor sistema:auto_dial, com a
--       marca de transação `tdf.promocao_automatica` (posta só por fn_dial_auto_promover) E rodando como dono (current_user fora de authenticated/anon).
--       O Analista segue sem mudar o dial à mão (fn_mudar_dial, UPDATE direto, nem com a marca posta por ele): o teste afirma. fn_mudar_dial NÃO foi
--       reescrita: a guarda de Sócio é o gatilho sobre a tabela, e passa por ele todo caminho (a função, o UPDATE direto, a promoção).
--   (d) QUEM CHAMA (grep em Supabase/ N8N/ portal/src): fn_veredito_producao <- fn_mudar_dial (porta p_por_veredito), fn_dial_auto_promover; fn_dial_auto_promover
--       <- fn_trg_auto_promover_dial; esse <- trg_auto_promover_dial; fn_golden_classe_a e fn_classe_contabil_concordancia <- fn_veredito_producao e (a segunda)
--       portal/src/app/administracao/page.tsx; fn_golden_cobertura <- esse mesmo page.tsx; fn_mudar_dial <- teste e a UI do dial (Sócio).
-- O QUE NÃO PÔDE SER MEDIDO (honestidade, regra 1): a guarda de Sócio tem TRÊS camadas contra o Analista (o gatilho, o WITH CHECK da policy de UPDATE e a
-- policy de INSERT em evento_auditoria para `estagio:`); a condição `current_user` e a marca, sozinhas, não têm assert que reprove quando só ELAS caem. Só a
-- exceção larga com a policy aberta reprova (variante v06b abaixo). Ficam como defesa em profundidade, declarada.
--
-- ===== DEFEITO 2 (defesa em profundidade): o `anon` tinha privilégio demais =====
-- Medido em produção em 30/10/2026: anon com privilégio em 62 tabelas/views/sequences de public e EXECUTE em 265 de 265 funções (default privilege
-- antigo do Supabase para dois donos, postgres e supabase_admin, mais o EXECUTE que toda função nova herda de PUBLIC). O portal nunca usa anon contra o
-- PostgREST (login, recuperar e nova senha só falam com o Auth; o n8n entra como postgres), então era só superfície: a segurança dependia da RLS sem
-- policy para anon e da guarda fn_exige_socio. Os cinco caminhos de escalada falham como anon (provado pelo coordenador); aqui a terceira camada, o GRANT, fecha.
-- A CORREÇÃO: `revoke all` em tabela/view/sequence (remove também o de COLUNA); em FUNÇÃO, PUBLIC e anon revogados e o EXECUTE de authenticated e
-- service_role REPOSTO como estava (lido antes), inclusive onde foi retirado de propósito (fn_acesso_bootstrap só service_role); default privilege de
-- anon em public revogado só para `postgres`. FUTURO: tabela e sequence nascem sem nada para anon; FUNÇÃO NÃO é fechada pelo default (o EXECUTE de PUBLIC é
-- embutido e só some com o `alter default privileges` global, que valeria para toda função do dono em qualquer schema — um `create extension` futuro
-- nasceria sem EXECUTE para o authenticated; recusado). O que fecha o futuro da função é a SONDA: anon_sem_funcoes (bloqueante) reprova no run.sh a migration
-- nova que esquecer `revoke all on function f(args) from public` — convenção nova em Supabase/README.md.
-- A SONDA: tipo novo `sem_privilegio` (o inverso de `privilegio`: exige AUSÊNCIA), objeto papel:classe (tabelas|views|sequences|funcoes), marcador = privilégios
-- proibidos; usa has_*_privilege (enxerga a herança de PUBLIC e o privilégio de coluna). Ignora objeto de extensão, objeto de dono diferente de postgres
-- e função `teste_*` (só existe no harness). 4 requisitos bloqueantes (anon_sem_*) + 8 do dial (corpo/função). Os requisitos `corpo` usam marcadores de UMA
-- linha que são CÓDIGO (`fn_exige_metrica(p_caso_id)`, `set_config('tdf.promocao_automatica', ...)`; o portão sonda_marcador_e_codigo exige código, e `SECURITY DEFINER` não
-- é), insensíveis a CRLF e às strings de caminho antigo que produção guarda. Que a função é DEFINER prova o teste, por comportamento, não a sonda.
--
-- STORAGE: não tocado. O bucket `documentos` é privado e as policies da 0216 exigem authenticated; dono do schema é supabase_storage_admin.
-- supabase_migrations.schema_migrations: nada inserido (as migrations recentes foram aplicadas pela API e não estão registradas lá).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/o_dial_e_o_anon.test.sql — 70 chamadas de assert, 83 execuções (uma chamada roda 14 vezes, na seção 9), medidas em
-- 30/10/2026 com `PGOPTIONS='-c dial.medindo=on'` (o assert vira `raise warning` e CONTA; sem a variável é `raise exception`; o `run.sh` completo foi rodado
-- sem ela, exit 0, e o log relido inteiro sem nenhum FALHOU) e a migration conferida como APLICADA em cada variante (rc 0 na aplicação e 83 execuções no fim).
-- Controle intacto: 83 ok, 0 falhas. Cada correção desligada UMA vez, num banco que parte da 0216 (reprovações / 83 execuções):
--   * O ESTADO ANTES (banco na 0216, sem a 0218; a migration só é aplicada no `\i` do meio): 17 — o dial não sobe por decisão de Analista (3: nível, base e trilha) e a
--     Analista recebe veredito global diferente do Sócio (1), as três métricas da /autonomia (classe contábil, classe A, cobertura) devolvem o recorte dela (3), mandato
--     alheio (3) e usuário sem papel (4) leem, fn_dial_auto_promover aberta ao authenticated (1), a sonda ainda sem os 4 requisitos de anon (1) e o EXECUTE de authenticated
--     diverge do retrato (1: o que a 0218 fecha de propósito). O assert "o dial NÃO sobe com o recorte alto" NÃO reprova aí: a guarda de Sócio da 0216 mascara o defeito
--     (ver "UM FATO"); ele é o controle do sentido inverso e não prova nada sozinho — dito aqui para não ser lido como cobertura. Idem o assert de que o veredito do
--     estágio reconciliacao_classe_a conta o banco inteiro: passa também no ANTES (a cobertura dessa peça é a da classe A, que reprova);
--   * fn_veredito_producao sozinha sem SECURITY DEFINER: 1 (a Analista deixa de receber o veredito global igual ao do Sócio). O gatilho e fn_dial_auto_promover, definer,
--     já rodam como dono e leem o banco inteiro: por isso só o estado ANTES inteiro, e não uma peça isolada, reproduz o defeito;
--   * sem a exceção na guarda de Sócio (a falha calada no sentido oposto): 3 (o dial não sobe por decisão de Analista, a base e a trilha);
--   * fn_exige_metrica sem a checagem de papel: 4; sem a de mandato (p_caso_id): 3; nula (não recusa nada, nem a conexão de serviço é perguntada): 7;
--   * fn_classe_contabil_concordancia, fn_golden_classe_a e fn_golden_cobertura sem SECURITY DEFINER: 1 cada;
--   * exceção larga na guarda de Sócio (qualquer UPDATE em estagio_autonomia passa): 1 com a policy fechada (o assert da última camada, que abre a policy de UPDATE
--     dentro da transação) e 3 com a policy de UPDATE aberta também no arquivo (UPDATE direto, marca forjada e a última camada); ANTES deste assert da última camada
--     medido 0 e 2, respectivamente — por isso ele foi acrescentado;
--   * marca sem a condição `current_user` (o dono): 1, só no assert da última camada (antes dele: 0);
--   * SEM MEDIÇÃO (0 reprovações, e é o número honesto): fn_dial_auto_promover sem SECURITY DEFINER (chamada pelo gatilho, que é definer, ela já roda como dono; chamada
--     direta pelo authenticated está fechada pelo REVOKE) · fn_trg_auto_promover_dial sem SECURITY DEFINER (o plpgsql guarda em cache a checagem de EXECUTE da chamada, e a
--     sessão do teste já a aquecera como superusuário na semeadura: o resultado depende da ordem das chamadas na sessão, e por isso a definer é a forma determinística,
--     coberta pela sonda dial_gatilho_independe_do_leitor, que é mecanismo). Os dois são indistinguíveis por comportamento numa só sessão;
--   * fn_dial_auto_promover aberta ao authenticated: 1;
--   * anon: sem o `revoke all` de tabelas e sequences: 12 · funções só com `revoke ... from anon` (PUBLIC fica): 13 · sem o laço de funções: 13 · laço sem repor o
--     EXECUTE de authenticated/service_role (depois de simular o estado de produção, EXECUTE só por PUBLIC): 3 (o retrato de antes e o EXECUTE dos dois papéis) · sem
--     revogar o default privilege: 4 · ramo `sem_privilegio` da sonda cego (marcador vazio): 7.
-- As variantes foram geradas por substituição de texto sobre este arquivo e aplicadas numa cópia do banco na 0216 (21 desligamentos + o ANTES).
-- Limite do teste: simula o estado ANTES com `grant ... to anon` e reaplica o arquivo da migration (`\i`) dentro de uma transação que volta; NÃO reproduz o dono
-- `supabase_admin` nem as ACLs de coluna de produção. O arquivo reaplicado pode ser trocado por `-v arq0218=<arquivo>` (é como se mediu cada variante).
-- =============================================================================

-- =============================================================================
-- 1. QUEM PODE PERGUNTAR — a guarda das métricas que agora enxergam tudo
-- =============================================================================
-- As cinco funções abaixo passam a ser SECURITY DEFINER (leem o banco inteiro, não o recorte de quem chama) e devolvem SÓ número e
-- veredito, nunca linha de mandato. Definer sem guarda abriria o que a RLS da 0216 fechou: (1) quem não tem papel não pode perguntar
-- nada (antes a RLS devolvia vazio; agora devolveria o número global); (2) com `p_caso_id` o chamador tem de poder LER aquele mandato
-- (senão a função viraria um oráculo: "quantos vereditos o mandato B tem?"). A conexão de serviço (n8n, SQL Editor) passa, como em
-- fn_exige_socio. INVOKER de propósito: roda como o dono quando chamada de dentro de uma definer, e `fn_conexao_de_servico`/
-- `fn_tem_papel`/`fn_pode_ler_caso` (definer, 0216) já leem o JWT de quem chamou.
create or replace function fn_exige_metrica(p_caso_id uuid default null) returns void
language plpgsql stable set search_path = public, pg_temp as $$
begin
  if fn_conexao_de_servico() then return; end if;
  if not fn_tem_papel() then
    raise exception 'As métricas de autonomia exigem um papel no portal (seu papel: nenhum)' using errcode = '42501';
  end if;
  if p_caso_id is not null and not fn_pode_ler_caso(p_caso_id) then
    raise exception 'Sem acesso a este mandato' using errcode = '42501';
  end if;
end $$;
revoke all on function fn_exige_metrica(uuid) from public, anon;
grant execute on function fn_exige_metrica(uuid) to authenticated, service_role;
comment on function fn_exige_metrica(uuid) is
  '0218: a guarda das métricas de autonomia (fn_veredito_producao, fn_golden_classe_a, fn_golden_cobertura, fn_classe_contabil_concordancia). Exige papel no portal (ou conexão de serviço) e, com p_caso_id, poder ler o mandato. 42501 nos dois casos.';

-- =============================================================================
-- 2. AS MÉTRICAS — as quatro folhas e o veredito, reemitidas INTEIRAS (corpo vigente + definer + guarda)
-- =============================================================================
-- Cada corpo abaixo é o da migration que o criou (0126 para classe A e cobertura, 0128 para a classe contábil, 0138 para o
-- veredito), sem uma vírgula alterada na lógica: o que muda é `security definer` + `search_path` fixo + a chamada à guarda. As três
-- que eram `language sql` viram plpgsql só para poder ter a guarda (SQL puro não levanta erro antes da consulta).
create or replace function fn_golden_classe_a(p_caso_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform fn_exige_metrica(p_caso_id);
  return (
  with a as (
    select p.id, p.estado, p.resolvida_por
    from pendencia p
    where p.origem_estagio = 'reconciliacao'
      and (p_caso_id is null or p.caso_id = p_caso_id)
      and exists (
        select 1 from reconciliacao r
        where r.caso_id = p.caso_id
          and r.classe = 'A'
          and p.motivo = 'reconciliacao:' || r.tipo
      )
  ), v as (
    select
      count(*) filter (where estado = 'rejeitada')::int as falso_positivo,
      count(*) filter (where estado in ('resolvida', 'aceita_com_ressalva')
                         and coalesce(resolvida_por, '') not like 'sistema:%')::int as procedia,
      count(*) filter (where estado = 'resolvida'
                         and coalesce(resolvida_por, '') like 'sistema:%')::int as sumiu_sozinha,
      count(*) filter (where estado in ('aberta','em_correcao_interna','reenviada_ao_cliente'))::int
        as sem_veredito
    from a
  )
  select jsonb_build_object(
    'com_veredito_humano', falso_positivo + procedia,
    'falso_positivo', falso_positivo,
    'procedia', procedia,
    'taxa_falso_positivo',
      case when falso_positivo + procedia = 0 then null
           else round(falso_positivo::numeric / (falso_positivo + procedia), 4) end,
    -- O critério é "mais alto e melhor", como os outros três, para a comparação
    -- em fn_golden_suficiente ser uma só.
    'nao_falso_positivo',
      case when falso_positivo + procedia = 0 then null
           else round(1 - falso_positivo::numeric / (falso_positivo + procedia), 4) end,
    'resolvida_pelo_sistema_sem_veredito', sumiu_sozinha,
    'ainda_sem_veredito', sem_veredito,
    'como_ler', 'O rótulo é o veredito humano registrado pela 0106: rejeitada = não procede = falso '
                'positivo do motor. Pendência que o próprio sistema resolveu não conta em nenhum dos '
                'dois lados — ninguém disse que ela procedia.'
  ) from v);
end;
$$;

comment on function fn_golden_classe_a(uuid) is
  'Taxa de falso-positivo da reconciliação Classe A (Arquitetura do Sistema/2 Especificação/f0/06, linha 5). Única das cinco métricas que NÃO precisa de rotulagem: o rótulo é o estado "rejeitada" que a 0106 define como "não procede (falso positivo do motor)". Denominador = vereditos humanos; pendência que o sistema resolveu sozinho fica fora, contada à parte. 0218: SECURITY DEFINER — devolve o número do BANCO INTEIRO para qualquer papel (com p_caso_id, só do mandato que o chamador lê); antes dependia da RLS do leitor.';

create or replace function fn_golden_cobertura(
  p_rodada uuid,
  p_origem golden_origem default 'real'
)
returns table (
  tipo                    text,
  granularidade           granularidade,
  n_documentos            int,
  n_dois_rotuladores      int,
  estratos                text[],
  n_minimo                int,
  atinge_minimo           boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
begin
  perform fn_exige_metrica(null);
  return query
  with alvo as (
    -- Um n_minimo por rodada: o critério é por ESTÁGIO, e a cobertura por tipo é
    -- a mesma exigência para todos eles. O maior dos critérios é o que vale, para
    -- a cobertura não aprovar um tipo que o estágio mais exigente reprovaria.
    select coalesce(max(gc.n_minimo), 20) as n from golden_criterio gc
  ),
  -- O TIPO AQUI É O DA VERDADE, NÃO O DA MÁQUINA, e esta linha é a correção de um
  -- defeito que o teste desta migration achou na primeira execução. Agrupar por
  -- `documento.tipo_taxonomia` faria a COBERTURA DO GROUND TRUTH ser medida pela
  -- resposta que está sob avaliação: numa rodada com 25 balanços dos quais o
  -- classificador chamou 5 de DRE, a cobertura reportava "BALANCO 20, DRE 5" e
  -- reprovava por N — quando a rodada tem 25 balanços rotulados e o que ela
  -- deveria acusar é a classificação errada, não falta de amostra. É a mesma
  -- confusão de autoridade das três de unidade que a sessão 52 achou.
  --
  -- Documento em que os rotuladores discordam do tipo não entra em tipo nenhum:
  -- ele não TEM tipo acordado, e atribuí-lo ao palpite de um dos dois seria
  -- inventar a verdade que falta.
  rot as (
    select c.documento_id, c.tipo_correto, c.n_rotuladores as n_rot, c.estrato
    from fn_golden_consenso(p_rodada) c
    where c.origem = p_origem and c.tipo_consenso
  )
  select t.codigo,
         t.granularidade,
         count(rot.documento_id)::int,
         count(rot.documento_id) filter (where rot.n_rot >= 2)::int,
         coalesce(array_agg(distinct rot.estrato::text)
                    filter (where rot.estrato is not null), '{}'),
         (select n from alvo)::int,
         count(rot.documento_id) >= (select n from alvo)
  from taxonomia_tipo_documento t
  left join rot on rot.tipo_correto = t.codigo
  where t.obrigatoriedade = 'obrigatorio' and t.ativo
  group by t.codigo, t.granularidade;
end;
$$;

comment on function fn_golden_cobertura(uuid, golden_origem) is
  'Quantos documentos rotulados a rodada tem por tipo CORE, contra o alvo do Arquitetura do Sistema/2 Especificação/f0/06 (~20-30). Core sai de obrigatoriedade=obrigatorio na taxonomia (0002), que são os mesmos 8 do Kit Básico — não de uma lista repetida aqui. granularidade vem no resultado porque tipo por CASO rende ~1 por mandato: demorar a juntar 20 é esperado. 0218: SECURITY DEFINER — as tabelas do golden set são só do Sócio (0216) e a função devolvia ZERO ao Analista sem aviso (ausência apresentada como dado); agora devolve a contagem real a qualquer papel, e só a contagem.';

create or replace function fn_classe_contabil_concordancia(p_caso_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform fn_exige_metrica(p_caso_id);
  return (
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
    where (p_caso_id is null or d.caso_id = p_caso_id)
      and s.criado_em = (select max(s2.criado_em) from campo_classe_sugerida s2
                          where s2.campo_extraido_id = s.campo_extraido_id)
  ),
  sem_veredito as (
    select count(*) as n
    from campo_classe_sugerida s
    join campo_extraido ce on ce.id = s.campo_extraido_id
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where (p_caso_id is null or d.caso_id = p_caso_id)
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
  ));
end;
$$;

comment on function fn_classe_contabil_concordancia(uuid) is
  'A concordância humano-máquina na classe contábil — o "sinal de calibração" que o Arquitetura do Sistema/2 Especificação/05 pede, em número, mais as rubricas que mais erram. Denominador = linhas com os DOIS lados; quem ninguém olhou fica fora e é contado à parte. 0218: SECURITY DEFINER — com p_caso_id nulo devolve o número do BANCO INTEIRO para qualquer papel (a tela /autonomia mostrava ao Analista o recorte dele sem avisar); com p_caso_id, só do mandato que o chamador lê.';

create or replace function fn_veredito_producao(
  p_estagio text,
  p_caso_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
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
  -- 0218: a pergunta de quem pode perguntar vem ANTES de qualquer leitura (a função agora enxerga tudo).
  perform fn_exige_metrica(p_caso_id);

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
$$;

comment on function fn_veredito_producao(text, uuid) is
  'Concordância medida a partir do veredito que o trabalho normal já produz (saída B do B3, 21/08). Despacha por estágio e RECUSA o que não sabe medir, em vez de devolver zero. É PISO ENVIESADO: quem emite o veredito vê o palpite da máquina, e o viés de confirmação puxa para cima. Vale menos que rodada de golden set congelada e mais que nível declarado. 0218: SECURITY DEFINER — o veredito GLOBAL (p_caso_id nulo) é o do banco inteiro, igual para qualquer papel, porque é ele que sobe o dial para todos; antes lia só os mandatos de quem disparava. Com p_caso_id, só se o chamador lê o mandato (42501).';

-- =============================================================================
-- 3. A PROMOÇÃO AUTOMÁTICA — independente de quem a dispara, e sem abrir o dial ao Analista
-- =============================================================================
-- O gatilho trg_estagio_autonomia_so_socio (0216) recusa qualquer escrita em estagio_autonomia de quem não é Sócio. Sozinha, a
-- correção do veredito faria o inverso do defeito: o Analista decide uma pendência -> o gatilho da promoção roda -> fn_mudar_dial
-- leva 42501 na guarda -> o bloco `exception when others` do gatilho (0137) engole e vira NOTICE. O dial nunca mais subiria por
-- decisão de Analista, calado. A saída é UMA exceção estreita na guarda, e ela exige as DUAS condições juntas: (a) a marca de
-- transação `tdf.promocao_automatica`, posta só por fn_dial_auto_promover (definer) em volta da chamada a fn_mudar_dial, e (b)
-- `current_user` fora de authenticated/anon, isto é, o código rodando como DONO, que é o que uma definer faz. A marca sozinha não
-- vale (quem tem SQL a poria à mão; o teste põe e a guarda recusa porque current_user continua authenticated). E mesmo as duas
-- juntas só deixam passar o UPDATE que SOBE o estágio a N2 com base `medida_por_veredito` e autor `sistema:auto_dial` — a promoção
-- da 0137 e mais nada. Descer, mudar o limiar, apagar, N3 e subida declarada continuam exclusivos do Sócio.
create or replace function fn_trg_so_socio() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  -- IFs ANINHADOS de propósito: o Postgres não garante curto-circuito do AND, e `new.atualizado_por` não existe em premissa_catalogo (medido: "record
  -- new has no field atualizado_por" derrubou o UPDATE do catálogo na primeira versão).
  if tg_table_name = 'estagio_autonomia' and tg_op = 'UPDATE' then
    if current_setting('tdf.promocao_automatica', true) = 'sim'
       and current_user not in ('authenticated', 'anon')
       and new.atualizado_por = 'sistema:auto_dial'
       and new.nivel_atual = 'N2'::nivel_autonomia and new.nivel_atual > old.nivel_atual
       and new.base_do_nivel = 'medida_por_veredito' then
      return new;
    end if;
  end if;
  perform fn_exige_socio(tg_argv[0]);
  return case when tg_op = 'DELETE' then old else new end;
end $$;

comment on function fn_trg_so_socio() is
  '0216/0218: guarda de Sócio do dial (estagio_autonomia) e do catálogo de premissas. Desde a 0218 deixa passar UMA escrita que não é de Sócio: a promoção automática da 0137 (UPDATE a N2, base medida_por_veredito, autor sistema:auto_dial, com a marca tdf.promocao_automatica E rodando como dono, nunca como authenticated).';

create or replace function fn_dial_auto_promover(p_estagio text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r         record;
  v_med     jsonb;
  v_res     jsonb;
  v_feitos  jsonb := '[]'::jsonb;
begin
  for r in
    select ea.estagio, ea.nivel_atual, ea.teto, ea.auto_promocao, ea.natureza
      from estagio_autonomia ea
     where (p_estagio is null or ea.estagio = p_estagio)
       and ea.natureza = 'interpretativo'
       and ea.auto_promocao
       and ea.nivel_atual < 'N2'::nivel_autonomia
       and ea.teto >= 'N2'::nivel_autonomia
  loop
    v_med := fn_veredito_producao(r.estagio);
    if not coalesce((v_med->>'suficiente')::boolean, false) then
      continue;
    end if;

    -- A PROMOÇÃO PASSA PELA MESMA PORTA DE SEMPRE. Chamar `fn_mudar_dial` em vez
    -- de dar `update` na tabela é o que garante que a automação não escape de
    -- nenhuma guarda: o teto, a regra de ouro e a trilha continuam sendo os
    -- mesmos, e o dia em que uma guarda nova for acrescentada lá ela passa a
    -- valer aqui sem ninguém lembrar de copiar.
    -- 0218: a ÚNICA porta que deixa a máquina mexer no dial sem ser Sócio. O gatilho de guarda
    -- (fn_trg_so_socio) só a reconhece com esta marca E rodando como dono (não como authenticated).
    perform set_config('tdf.promocao_automatica', 'sim', true);
    v_res := fn_mudar_dial(
      r.estagio, 'N2'::nivel_autonomia, 'sistema:auto_dial',
      format('Promoção automática (0137): o veredito de produção alcançou o critério — %s vereditos '
             'a %s de concordância, mínimo %s a %s. O número é PISO enviesado, e por isso a subida '
             'para em N2.',
             v_med->>'n', v_med->>'concordancia',
             v_med->>'n_minimo', v_med->>'concordancia_minima'),
      null, null, null, true);
    perform set_config('tdf.promocao_automatica', '', true);

    v_feitos := v_feitos || jsonb_build_object(
      'estagio', r.estagio,
      'de', r.nivel_atual,
      'para', v_res->>'nivel_atual',
      'recusado', coalesce((v_res->>'recusado')::boolean, false),
      'medicao', v_med);
  end loop;

  return jsonb_build_object(
    'promovidos', v_feitos,
    'quantos', jsonb_array_length(v_feitos),
    'como_ler', 'Promoção automática por veredito de produção (0137). Ela sobe no máximo até N2, '
                'nunca N3: o veredito mede um PISO enviesado, e piso não sustenta autonomia plena. '
                'Estágio com auto_promocao = false não entra aqui — é o freio de quem baixou o '
                'nível à mão, e religá-lo é decisão explícita.');
end;
$$;

comment on function fn_dial_auto_promover(text) is
  'Sobe para N2 todo estágio interpretativo elegível cujo veredito de produção alcançou o critério (0137). Sobe pela fn_mudar_dial, nunca por update direto, para não escapar de guarda nenhuma. Para em N2 por decisão: piso enviesado não sustenta autonomia plena. 0218: SECURITY DEFINER e fechada ao authenticated — mede o veredito GLOBAL e pode subir o dial mesmo disparada por um Analista (a marca tdf.promocao_automatica abre a exceção estreita de fn_trg_so_socio); só o gatilho e o service_role a chamam.';

-- Ninguém do portal a chama (grep em portal/src e N8N: nenhum chamador); o gatilho é definer e a chama como dono.
revoke all on function fn_dial_auto_promover(text) from public, anon, authenticated;
grant execute on function fn_dial_auto_promover(text) to service_role;

create or replace function fn_trg_auto_promover_dial()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_r jsonb;
begin
  if pg_trigger_depth() > 1 then
    return null;
  end if;

  begin
    v_r := fn_dial_auto_promover();
    if coalesce((v_r->>'quantos')::int, 0) > 0 then
      raise notice '0137: promoção automática do dial — %', v_r->'promovidos';
    end if;
  exception when others then
    -- 0218: a marca da promoção nunca sobrevive a uma promoção que falhou (o rollback do sub-bloco já a desfaz; isto é cinto e suspensório).
    perform set_config('tdf.promocao_automatica', '', true);
    raise notice '0137: a promoção automática falhou e foi ignorada (a decisão que a disparou está '
                 'gravada). Erro: %', sqlerrm;
  end;

  return null;
end;
$$;

comment on function fn_trg_auto_promover_dial() is
  'Gatilho da promoção automática (0137): toda decisão humana nova pode ter completado o critério do veredito de produção. NUNCA derruba a transação de quem o disparou — falha vira NOTICE, porque o analista não pode perder a rejeição de uma pendência por causa do dial. 0218: SECURITY DEFINER, para que a promoção não dependa do recorte nem do papel de quem decidiu.';

-- =============================================================================
-- 4. O ANON — nenhum privilégio em public, nem agora nem nos objetos futuros
-- =============================================================================
-- Medido em produção (30/10/2026): `anon` tinha SELECT/INSERT/UPDATE/DELETE em tabela e EXECUTE em função de public (default privilege
-- antigo do Supabase + EXECUTE herdado de PUBLIC). O portal nunca usa `anon` contra o PostgREST (login, recuperar e nova senha só
-- falam com o Auth; o n8n entra como postgres) — o privilégio era só superfície. A segurança dependia de a RLS não ter policy para
-- anon e da guarda fn_exige_socio: duas camadas, e a terceira (o GRANT) estava aberta.
--
-- 4a. O que existe hoje. `revoke all ... from anon` em tabela remove também o privilégio de COLUNA. EXECUTE é diferente: função nova
-- nasce com EXECUTE para PUBLIC (todos os papéis) e `anon` o herda; `revoke ... from anon` NÃO o tira. Por isso cada função tem PUBLIC e
-- anon revogados e o EXECUTE de authenticated/service_role é REPOSTO exatamente como estava (lido ANTES do revoke): o efeito para
-- esses dois papéis é nulo, inclusive onde o EXECUTE foi retirado de propósito (fn_acesso_bootstrap só para service_role). Função de
-- extensão (pgcrypto, unaccent) fica como está: não é nossa e a sonda também a ignora.
do $$
declare
  v_f      record;
  v_auth   boolean;
  v_srv    boolean;
  v_t0 int; v_s0 int; v_f0 int;   -- ANTES
  v_t1 int; v_s1 int; v_f1 int;   -- DEPOIS
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    raise notice '0218: o papel anon não existe neste banco — nada a revogar.';
    return;
  end if;

  select count(*) filter (where c.relkind in ('r', 'p', 'v', 'm')
                            and (has_any_column_privilege('anon', c.oid, 'select') or has_any_column_privilege('anon', c.oid, 'insert')
                              or has_any_column_privilege('anon', c.oid, 'update') or has_any_column_privilege('anon', c.oid, 'references')
                              or has_table_privilege('anon', c.oid, 'delete') or has_table_privilege('anon', c.oid, 'truncate')
                              or has_table_privilege('anon', c.oid, 'trigger'))),
         count(*) filter (where c.relkind = 'S'
                            and (has_sequence_privilege('anon', c.oid, 'usage') or has_sequence_privilege('anon', c.oid, 'select')
                              or has_sequence_privilege('anon', c.oid, 'update')))
    into v_t0, v_s0
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relowner = (select oid from pg_roles where rolname = 'postgres');
  select count(*) into v_f0
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')
     and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
     and p.proowner = (select oid from pg_roles where rolname = 'postgres');

  revoke all on all tables in schema public from anon;
  revoke all on all sequences in schema public from anon;

  for v_f in
    select p.oid, p.oid::regprocedure::text as assinatura,
           case when p.prokind = 'p' then 'procedure' else 'function' end as classe
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
     and p.proowner = (select oid from pg_roles where rolname = 'postgres')
  loop
    v_auth := has_function_privilege('authenticated', v_f.oid, 'execute');
    v_srv  := has_function_privilege('service_role',  v_f.oid, 'execute');
    execute format('revoke all on %s %s from public, anon', v_f.classe, v_f.assinatura);
    if v_auth then execute format('grant execute on %s %s to authenticated', v_f.classe, v_f.assinatura); end if;
    if v_srv  then execute format('grant execute on %s %s to service_role',  v_f.classe, v_f.assinatura); end if;
  end loop;

  -- 4b. Os objetos FUTUROS. `alter default privileges` vale por papel DONO. Em produção dois donos dão ALL a anon em public (medido em
  -- 30/10/2026): `postgres` e `supabase_admin`. Só o do `postgres` é alterado: o do `supabase_admin` exige ser membro dele e FALHARIA.
  -- EFEITO RESIDUAL: objeto criado pelo `supabase_admin` (extensões) continua nascendo com privilégio para anon; a sonda o ignora (dono
  -- diferente de postgres) e ele só se fecha rodando como supabase_admin. No replay local não há esse default: a instrução é um no-op.
  -- Para TABELA e SEQUENCE isto fecha o futuro. Para FUNÇÃO NÃO fecha: o EXECUTE de PUBLIC é o default embutido do
  -- Postgres e só some com `alter default privileges ... revoke execute on functions from public` SEM `in schema` — que valeria
  -- para toda função que o dono criar em QUALQUER schema (um `create extension` futuro nasceria sem EXECUTE para o authenticated).
  -- Recusei esse efeito: a função nova que esquecer o `revoke all ... from public` é pega pela sonda (anon_sem_funcoes, bloqueante),
  -- dentro do run.sh, antes de chegar a produção. A convenção está em Supabase/README.md.
  if exists (select 1 from pg_roles where rolname = 'postgres') then
    begin
      alter default privileges for role postgres in schema public revoke all on tables from anon;
      alter default privileges for role postgres in schema public revoke all on sequences from anon;
      alter default privileges for role postgres in schema public revoke all on functions from anon;
    exception when insufficient_privilege then
      raise warning '0218: não consegui revogar o default privilege de anon do papel postgres (esta migration deve rodar como postgres).';
    end;
  end if;

  select count(*) filter (where c.relkind in ('r', 'p', 'v', 'm')
                            and (has_any_column_privilege('anon', c.oid, 'select') or has_any_column_privilege('anon', c.oid, 'insert')
                              or has_any_column_privilege('anon', c.oid, 'update') or has_any_column_privilege('anon', c.oid, 'references')
                              or has_table_privilege('anon', c.oid, 'delete') or has_table_privilege('anon', c.oid, 'truncate')
                              or has_table_privilege('anon', c.oid, 'trigger'))),
         count(*) filter (where c.relkind = 'S'
                            and (has_sequence_privilege('anon', c.oid, 'usage') or has_sequence_privilege('anon', c.oid, 'select')
                              or has_sequence_privilege('anon', c.oid, 'update')))
    into v_t1, v_s1
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relowner = (select oid from pg_roles where rolname = 'postgres');
  select count(*) into v_f1
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')
     and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
     and p.proowner = (select oid from pg_roles where rolname = 'postgres');

  raise notice '0218: anon em public (tabelas+views / sequences / funções fora de extensão) — ANTES: % / % / %; DEPOIS: % / % / % (tem de ser 0 / 0 / 0).',
    v_t0, v_s0, v_f0, v_t1, v_s1, v_f1;
end $$;

-- =============================================================================
-- 5. A SONDA — requisito novo (tipo `sem_privilegio`) e o catálogo revisado
-- =============================================================================
alter table instalacao_requisito drop constraint if exists instalacao_requisito_tipo_check;
alter table instalacao_requisito add constraint instalacao_requisito_tipo_check
  check (tipo in ('tabela', 'coluna', 'funcao', 'seed', 'comportamento', 'corpo', 'gatilho', 'policy', 'privilegio', 'sem_privilegio'));

-- fn_instalacao_conferir: a da 0214 INTEIRA, com UM ramo novo (`sem_privilegio`) e a variável v_classe. Nada mais mudou.
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
  v_classe     text;
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
      v_alvo := to_regclass('public.' || split_part(r.objeto, '.', 1));
      if v_alvo is null then
        v_ok  := false;
        v_det := 'a tabela nem existe';
      else
        v_ok := exists (select 1 from pg_policy p
                         where p.polrelid = v_alvo and p.polname = split_part(r.objeto, '.', 2));
        v_det := case when v_ok then 'policy presente'
                      else 'a policy não existe na tabela (RLS ligada sem ela nega a operação ao authenticated)' end;
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

    elsif r.tipo = 'sem_privilegio' then
      -- 0218: o INVERSO do `privilegio`. Aquele exige o MÍNIMO (o buraco é o que falta); este exige a AUSÊNCIA (o buraco é o que sobra).
      -- `objeto` = 'papel:classe' (classe tabelas | views | sequences | funcoes) e `marcador` = os privilégios que o papel NÃO pode ter.
      -- Varre TODO o schema public, não uma lista: o defeito é o objeto NOVO que nasce com privilégio (o default privilege antigo do
      -- Supabase dava tudo a `anon`; função nova nasce com EXECUTE para PUBLIC, e `anon` herda de PUBLIC — por isso `has_*_privilege`,
      -- que enxerga a herança, e não a leitura da ACL). Privilégio de COLUNA conta (`has_any_column_privilege`): um `grant select (id)`
      -- não aparece em `has_table_privilege`. Fora da varredura: objeto de extensão e objeto cujo dono não é `postgres` (o REVOKE de quem não é dono só avisa: o requisito nasceria ausente por um motivo que a migration não corrige; ex.: unaccent, do supabase_admin), e função `teste_*`, que só existe no
      -- harness local (a suíte as cria em public e não as apaga; em produção nenhuma função tem este prefixo).
      v_role   := split_part(r.objeto, ':', 1);
      v_privs  := string_to_array(r.marcador, ',');
      v_classe := split_part(r.objeto, ':', 2);
      if v_classe not in ('tabelas', 'views', 'sequences', 'funcoes') or v_privs is null then
        v_ok  := false;
        v_det := 'requisito mal declarado: objeto papel:(tabelas|views|sequences|funcoes) e marcador com os privilégios proibidos';
      elsif not exists (select 1 from pg_roles where rolname = v_role) then
        v_ok  := true;
        v_det := format('o papel %s nem existe: não há privilégio a vazar', v_role);
      else
        if v_classe = 'funcoes' then
          select count(*), string_agg(x.nome, ', ' order by x.nome) filter (where x.rn <= 15)
            into v_n, v_lista
            from (select p.oid::regprocedure::text as nome, row_number() over (order by p.oid::regprocedure::text) as rn
                    from pg_proc p
                    join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'public'
                     and p.proname not like 'teste\_%'
                     and p.proowner = (select oid from pg_roles where rolname = 'postgres')
                     and not exists (select 1 from pg_depend d
                                      where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
                     and exists (select 1 from unnest(v_privs) q where has_function_privilege(v_role, p.oid, q))) x;
        else
          select count(*), string_agg(x.relname, ', ' order by x.relname) filter (where x.rn <= 15)
            into v_n, v_lista
            from (select c.relname, row_number() over (order by c.relname) as rn
                    from pg_class c
                    join pg_namespace n on n.oid = c.relnamespace
                   where n.nspname = 'public'
                     and c.relkind = any (case v_classe when 'tabelas'   then array['r', 'p']::"char"[]
                                                        when 'views'     then array['v', 'm']::"char"[]
                                                        else array['S']::"char"[] end)
                     and c.relowner = (select oid from pg_roles where rolname = 'postgres')
                     and not exists (select 1 from pg_depend d
                                      where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e')
                     and exists (select 1 from unnest(v_privs) q
                                  where case when c.relkind = 'S'
                                             then has_sequence_privilege(v_role, c.oid, q)
                                             when lower(q) in ('select', 'insert', 'update', 'references')
                                             then has_any_column_privilege(v_role, c.oid, q)
                                             else has_table_privilege(v_role, c.oid, q) end)) x;
        end if;
        v_ok  := v_n = 0;
        v_det := case when v_ok then format('nenhum objeto (%s) de public com privilégio para %s', v_classe, v_role)
                      else format('%s objeto(s) (%s) de public COM privilégio para %s: %s%s', v_n, v_classe, v_role, v_lista,
                                  case when v_n > 15 then ' ...' else '' end) end;
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

    return query select r.chave, r.migration, r.tipo, r.objeto, v_ok, v_det,
                        r.porque, r.severidade;
  end loop;
end;
$function$;

comment on function fn_instalacao_conferir() is
  'Confere cada requisito de instalacao_requisito contra o catálogo do banco. Sobrevive ao objeto ausente (to_regclass/to_regproc devolvem NULL em vez de erro): a sonda não pode falhar por causa do que ela existe para medir. Desde a 0147 confere também o CORPO da função (tipo=corpo), que é o único jeito de distinguir uma correção aplicada de uma função homônima com o corpo velho. Desde a 0189 confere também GATILHO (tipo=gatilho): existência na tabela E tgenabled em (''O'',''A'') — a função do gatilho sobrevive a drop trigger/disable trigger e por isso NUNCA prova, sozinha, que a guarda está ligada. Desde a 0210 confere também POLICY (tipo=policy, objeto tabela.nome_da_policy): existência em pg_policy. Desde a 0214 confere PRIVILÉGIO (tipo=privilegio, objeto papel:classe, marcador = privilégios): toda tabela/view/sequence de public sem o mínimo para authenticated e service_role é buraco — o Supabase deixou de conceder por default privilege em 30/10/2026. Desde a 0218 confere também a AUSÊNCIA de privilégio (tipo=sem_privilegio, objeto papel:classe com classe tabelas|views|sequences|funcoes, marcador = privilégios proibidos): todo objeto de public com privilégio para anon é buraco (função herda EXECUTE de PUBLIC; privilégio de coluna conta; função de extensão e teste_* ficam de fora).';

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('anon_sem_tabelas', '0218', 'sem_privilegio', 'anon:tabelas', 'select,insert,update,delete,truncate,references,trigger', null,
   'Tabela de public com privilégio para `anon` (inclusive de coluna): quem chega ao PostgREST SEM login passa a ter a RLS como única defesa — e em `membro`/`alocacao` (os papéis do portal) isso é a escalada para Sócio a um erro de policy de distância. O portal nunca usa anon contra tabela. Se aparece, o default privilege antigo do Supabase voltou ou uma migration nova concedeu a anon: revogue (revoke all on <tabela> from anon) e acerte o default (alter default privileges ... revoke all on tables from anon).',
   'bloqueante', 980),
  ('anon_sem_views', '0218', 'sem_privilegio', 'anon:views', 'select,insert,update,delete,truncate,references,trigger', null,
   'View de public com privilégio para `anon`: as views instalacao_sonda_* e outras expõem taxonomia e cobertura a quem não fez login.',
   'bloqueante', 981),
  ('anon_sem_sequences', '0218', 'sem_privilegio', 'anon:sequences', 'usage,select,update', null,
   'Sequence de public com privilégio para `anon`.',
   'bloqueante', 982),
  ('anon_sem_funcoes', '0218', 'sem_privilegio', 'anon:funcoes', 'execute', null,
   'Função de public executável por `anon` (direto ou herdado de PUBLIC): quem chega ao PostgREST sem login pode chamar a RPC. fn_definir_papel, fn_alocar e fn_acesso_bootstrap só estão a salvo da escalada por causa da guarda dentro do corpo. A migration que cria função faz `revoke all on function <f>(<args>) from public;` e concede a authenticated/service_role o que o portal usa (Supabase/README.md). Função `teste_*` e de extensão não contam.',
   'bloqueante', 983),
  ('dial_veredito_independe_do_leitor', '0218', 'corpo', 'fn_veredito_producao', 'fn_exige_metrica(p_caso_id)', null,
   'Sem SECURITY DEFINER o veredito GLOBAL que sobe o dial para todos é calculado só sobre os mandatos de quem o disparou: um Analista alocado em 3 mandatos a 96% promove o estágio para todos com a média do banco em 85%. Se reprova, uma migration posterior republicou a função da 0138 (invoker).',
   'bloqueante', 984),
  ('dial_promocao_independe_do_leitor', '0218', 'corpo', 'fn_dial_auto_promover', 'set_config(''tdf.promocao_automatica'', ''sim'', true)', null,
   'Sem SECURITY DEFINER a promoção automática roda com o papel de quem decidiu: Analista dispara, a guarda de Sócio recusa, o gatilho engole o erro e o dial nunca sobe por decisão dele — calado.',
   'bloqueante', 986),
  ('dial_gatilho_independe_do_leitor', '0218', 'corpo', 'fn_trg_auto_promover_dial', 'set_config(''tdf.promocao_automatica'', '''', true)', null,
   'O gatilho da promoção precisa rodar como dono para chamar fn_dial_auto_promover (fechada ao authenticated).',
   'bloqueante', 987),
  ('dial_guarda_de_socio_tem_a_promocao', '0218', 'corpo', 'fn_trg_so_socio', 'tdf.promocao_automatica', null,
   'Sem a exceção estreita da promoção automática, a guarda de Sócio (0216) impede o dial de subir por decisão de Analista; com uma exceção larga, o Analista mudaria o dial à mão. O marcador é a marca de transação que só fn_dial_auto_promover põe.',
   'bloqueante', 988),
  ('dial_metrica_cobertura_do_golden', '0218', 'corpo', 'fn_golden_cobertura', 'fn_exige_metrica(null)', null,
   'A tela /autonomia mostra a cobertura do golden set: sem definer o Analista vê ZERO documentos rotulados (as tabelas do golden são do Sócio) sem aviso — ausência apresentada como dado.',
   'importante', 989),
  ('dial_metrica_classe_contabil', '0218', 'corpo', 'fn_classe_contabil_concordancia', 'fn_exige_metrica(p_caso_id)', null,
   'A tela /autonomia mostra a concordância da classe contábil: sem definer cada papel vê o número do SEU recorte como se fosse o do sistema.',
   'importante', 990),
  ('dial_metrica_classe_a', '0218', 'corpo', 'fn_golden_classe_a', 'fn_exige_metrica(p_caso_id)', null,
   'O veredito do estágio reconciliacao_classe_a delega nesta função: sem definer ele é medido sobre o recorte de quem dispara.',
   'importante', 991),
  ('dial_guarda_das_metricas', '0218', 'funcao', 'fn_exige_metrica', null, null,
   'As quatro métricas do dial chamam esta guarda; sem ela a chamada falha com "function does not exist".',
   'bloqueante', 992)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0218', revisado_em = current_date,
       observacao = 'A 0218 torna SECURITY DEFINER (com guarda de papel e de mandato) o veredito de produção, as três métricas folha e a promoção automática do dial, com exceção estreita na guarda de Sócio; revoga de anon todo privilégio de public (tabela, view, sequence, função) e acrescenta à sonda o tipo sem_privilegio (4 requisitos) e 8 requisitos do dial.'
 where id = true;
