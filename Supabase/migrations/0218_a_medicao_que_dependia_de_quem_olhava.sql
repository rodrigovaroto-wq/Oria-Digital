-- =============================================================================
-- 0218 — A MEDIÇÃO QUE DEPENDIA DE QUEM OLHAVA
--
-- O DEFEITO, MEDIDO (30/10/2026, banco local com as 217 migrations, numa transação revertida):
--
--   A 0216 pôs a RLS por mandato em toda tabela, e as funções que medem a concordância humano-máquina
--   continuaram INVOKER. Desde então o número que governa o dial depende de QUEM o calcula:
--
--   * Cenário A — o global é suficiente e o Analista dá a decisão que o completa. Global: 30 vereditos
--     a 1,0000 (critério: 30 a 0,95). O Analista, alocado em um dos dois mandatos, enxerga 10. O gatilho
--     `trg_auto_promover_dial` roda COMO ELE, o veredito dá "insuficiente", e o dial FICA EM N1, com
--     ZERO eventos na trilha. A promoção automática que o dono decidiu (0137) some sem rastro, e só
--     acontece na próxima decisão de um Sócio ou do n8n — se acontecer.
--   * Cenário B — o recorte do Analista é alto e o global é baixo. Global: 49 vereditos a 0,5918. O
--     Analista enxerga 29 a 1,0000 e, com a 30ª dele, o veredito que ELE vê dá "suficiente". Só não
--     promoveu porque a guarda `trg_estagio_autonomia_so_socio` (0216) barrou o `update` como Analista,
--     e o gatilho engoliu o erro como NOTICE. A proteção era ACIDENTAL: a guarda existe contra o
--     navegador, não para corrigir a amostra.
--   * A sonda não via RLS desligada: `alter table caso/decisao disable row level security` deixava
--     `fn_instalacao_conferir()` com os MESMOS ausentes (1, o seed local de custo). A policy continua
--     lá; ela só deixa de valer — e todo usuário logado passa a ler todos os mandatos.
--
-- A REVISÃO DO PR #264 descreveu o defeito como "um Analista promove o dial de todos com a concordância
-- só dos mandatos dele". Sob a 0216 do `main` isso NÃO acontece (cenário B). O que acontece é o inverso
-- (cenário A), e foi ele que esta migration corrigiu; o cenário B virou invariante, para que deixe de ser
-- protegido por acaso.
--
-- A CORREÇÃO
--   1. `fn_dial_auto_promover` é SECURITY DEFINER: o veredito que decide o dial é o GLOBAL, qualquer que
--      seja o usuário cuja decisão disparou o gatilho. O dono da função (`postgres`) ignora a RLS
--      (`rolbypassrls`, medido em produção em 30/10/2026).
--   2. `fn_trg_so_socio` (a guarda do dial e do catálogo de premissas) deixa passar o código do próprio
--      banco: para quem chega como `authenticated`/`anon` (o navegador), `current_user` só sai desses dois
--      dentro de uma função SECURITY DEFINER criada por migration; `postgres` direto e `service_role` já
--      passavam antes, por fn_conexao_de_servico. O navegador não tem como virar outro papel. A ÚNICA
--      função definer que chega a `fn_mudar_dial` é `fn_dial_auto_promover` (varredura de todo prosrc de
--      public na revisão), e ela NÃO é executável pelo `authenticated`: quem a chama é o gatilho
--      `fn_trg_auto_promover_dial`, também definer, e gatilho não se chama por RPC. A primeira versão desta
--      migration a deixava executável, e uma Leitura promovia o dial por `rpc('fn_dial_auto_promover')`
--      sem deixar na trilha quem disparou (achado da revisão independente, agora no teste).
--   3. As quatro medições (`fn_veredito_producao`, `fn_classe_contabil_concordancia`, `fn_golden_classe_a`,
--      `fn_golden_cobertura`) são SECURITY DEFINER: dão o mesmo número a todo leitor. Com `p_caso_id` de um
--      mandato que o leitor não lê, dão 42501 (`fn_exige_ler_caso`) — antes davam ZERO, que é ausência
--      apresentada como medição (regra 1), e um definer sem a guarda vazaria a contagem do mandato alheio.
--      Consequência deliberada: o Analista e a Leitura passam a ver os AGREGADOS globais (contagens e
--      concordância; nenhuma linha, nenhum documento). Usuário SEM PAPEL leva 42501 também na pergunta
--      global (0216: "sem papel, nada"; a primeira versão deixava passar, achado da revisão). A tela
--      `/administracao` continua só do Sócio.
--   4. A sonda ganha o tipo `rls` (objeto = schema): toda tabela de `public` com `relrowsecurity`.
--      Bloqueante. Hoje 51 de 51.
--
-- O QUE NÃO MUDOU
--   * `fn_mudar_dial` continua INVOKER: chamada pelo Sócio, ele já vê tudo; chamada pela promoção, roda
--     dentro do definer.
--   * `fn_golden_suficiente` (o caminho da rodada de golden set) é só do Sócio, que vê tudo.
--   * O bootstrap da 0216 que promove a Sócio todo `auth.users` (achado da mesma revisão) não é tocado:
--     ele já rodou em produção, com 1 usuário.
--
-- TESTE: `Supabase/test/medicao_global.test.sql`. Os números de "desligado" estão no cabeçalho dele.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. A GUARDA DO MANDATO PARA AS MEDIÇÕES COM RECORTE
--
-- p_caso NULL é a pergunta global: todo leitor COM PAPEL recebe o mesmo número. p_caso dado exige poder ler
-- o mandato: Sócio, alocado. Conexão de serviço (n8n, SQL Editor) sempre passa. Security definer pelo mesmo motivo
-- de fn_pode_ler_caso: lê membro/alocacao sem reentrar na RLS.
-- -----------------------------------------------------------------------------
create or replace function fn_exige_ler_caso(p_caso uuid) returns void
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if fn_conexao_de_servico() or (p_caso is null and fn_tem_papel()) or fn_pode_ler_caso(p_caso) then
    return;
  end if;
  if p_caso is null then
    raise exception 'Sem papel no portal, nenhuma medição é mostrada' using errcode = '42501';
  end if;
  raise exception 'Você não tem acesso a este mandato, então a medição dele não é mostrada (seu papel: %)',
    coalesce(fn_meu_papel(), 'nenhum')
    using errcode = '42501';
end $$;

comment on function fn_exige_ler_caso(uuid) is
  '0218: guarda das medições com recorte por mandato. NULL = pergunta global, passa para quem tem papel. Mandato que o leitor não lê = 42501, em vez do zero que a RLS daria calada.';

-- -----------------------------------------------------------------------------
-- 2. O VEREDITO DE PRODUÇÃO — o corpo da 0138 INTEIRO, com UMA linha nova (a guarda), e definer abaixo.
-- -----------------------------------------------------------------------------

create or replace function fn_veredito_producao(
  p_estagio text,
  p_caso_id uuid default null
)
returns jsonb
language plpgsql
stable
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
  -- 0218: mandato que o leitor não lê dá 42501, nunca o zero da RLS. NULL é a pergunta global.
  perform fn_exige_ler_caso(p_caso_id);

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


-- -----------------------------------------------------------------------------
-- 3. AS DUAS MEDIÇÕES EM SQL QUE TÊM RECORTE (0126, 0128): corpo INTEIRO, a guarda como primeira instrução.
--    Função SQL com várias instruções devolve a última; a primeira só existe para dar 42501.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_classe_contabil_concordancia(p_caso_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  select fn_exige_ler_caso(p_caso_id);
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
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_golden_classe_a(p_caso_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  select fn_exige_ler_caso(p_caso_id);
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
  ) from v;
$function$;

-- fn_golden_cobertura (0126): não tem recorte por mandato, mas a guarda dá 42501 a quem não tem papel.
CREATE OR REPLACE FUNCTION public.fn_golden_cobertura(p_rodada uuid, p_origem golden_origem DEFAULT 'real'::golden_origem)
 RETURNS TABLE(tipo text, granularidade granularidade, n_documentos integer, n_dois_rotuladores integer, estratos text[], n_minimo integer, atinge_minimo boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select fn_exige_ler_caso(null);
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
$function$;

-- -----------------------------------------------------------------------------
-- 4. AS CINCO PASSAM A SECURITY DEFINER (search_path fixo, como toda definer da 0216)
--
-- fn_golden_cobertura não tem recorte por mandato (é por rodada), então só muda o modo: antes o Analista
-- recebia ZERO em tudo (golden_* é só do Sócio, 0216), e zero de cobertura é indistinguível de "nenhum
-- rótulo" (regra 1). fn_dial_auto_promover não tem recorte: mede o global e promove pela fn_mudar_dial.
-- -----------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'fn_veredito_producao(text, uuid)', 'fn_classe_contabil_concordancia(uuid)',
    'fn_golden_classe_a(uuid)', 'fn_golden_cobertura(uuid, golden_origem)', 'fn_exige_ler_caso(uuid)']
  loop
    execute format('alter function %s security definer set search_path = public, pg_temp', f);
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end $$;

-- A PROMOÇÃO NÃO É CHAMÁVEL PELO NAVEGADOR. Definer e executável pelo authenticated, ela deixava qualquer papel
-- (até a Leitura) subir o dial com o ator sistema:auto_dial, sem rastro de quem disparou. Quem a chama é o
-- gatilho, que vira definer para chegar a ela; gatilho não é RPC.
alter function fn_dial_auto_promover(text) security definer set search_path = public, pg_temp;
revoke all on function fn_dial_auto_promover(text) from public, anon, authenticated;
grant execute on function fn_dial_auto_promover(text) to service_role;
alter function fn_trg_auto_promover_dial() security definer set search_path = public, pg_temp;
revoke all on function fn_trg_auto_promover_dial() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 5. A GUARDA DO DIAL DEIXA PASSAR O CÓDIGO DO PRÓPRIO BANCO
--
-- Antes: fn_exige_socio olha só para auth.uid() e o papel da sessão. Dentro de fn_dial_auto_promover
-- (definer) o JWT continua o do Analista que disparou o gatilho, e a promoção era barrada (cenário A).
-- `current_user` é o que distingue: o navegador é `authenticated` (ou `anon`) e não tem como virar outro
-- papel; dentro de uma função security definer de migration ele executa como o dono. (postgres direto e
-- service_role também passam, como já passavam por fn_conexao_de_servico.) A checagem fica AQUI, no
-- gatilho invoker — dentro de fn_exige_socio (definer) o current_user é sempre o dono.
-- -----------------------------------------------------------------------------
create or replace function fn_trg_so_socio() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if current_user::text not in ('authenticated', 'anon') then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  perform fn_exige_socio(tg_argv[0]);
  return case when tg_op = 'DELETE' then old else new end;
end $$;

comment on function fn_trg_so_socio() is
  '0216/0218: só Sócio escreve no dial e no catálogo de premissas. Passa o código do próprio banco (current_user fora de authenticated/anon = dentro de uma função security definer de migration, como a promoção automática do dial); o navegador continua barrado.';

-- -----------------------------------------------------------------------------
-- 6. A SONDA PASSA A VER RLS DESLIGADA (a função da 0217 INTEIRA, com UM ramo novo: `rls`)
-- -----------------------------------------------------------------------------
alter table instalacao_requisito drop constraint if exists instalacao_requisito_tipo_check;
alter table instalacao_requisito add constraint instalacao_requisito_tipo_check
  check (tipo in ('tabela', 'coluna', 'funcao', 'seed', 'comportamento', 'corpo', 'gatilho', 'policy', 'privilegio', 'segredo', 'rls'));

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

    elsif r.tipo = 'segredo' then
      -- 0217: segredo do Vault do Supabase (objeto = o NOME do segredo; o valor nunca é lido aqui). A sonda roda como o
      -- chamador (o portal é `authenticated`, que não lê o Vault), então a pergunta "existe e não está vazio?" passa por
      -- uma função SECURITY DEFINER que só devolve boolean. Falha ao perguntar (Vault ausente, sem permissão) é
      -- `presente = false` com o motivo, nunca uma exceção que derrube a sonda inteira.
      begin
        v_ok  := coalesce(fn_segredo_do_vault_presente(r.objeto), false);
        v_det := case when v_ok then 'segredo presente no Vault (valor não lido)'
                      else 'o Vault não tem este segredo, ou ele está vazio' end;
      exception when others then
        v_ok  := false;
        v_det := 'não foi possível consultar o Vault: ' || sqlerrm;
      end;

    elsif r.tipo = 'rls' then
      -- 0218: RLS LIGADA (objeto = o schema). A policy existir (tipo policy) não prova nada sem isto:
      -- `alter table ... disable row level security` mantém a policy no catálogo e para de aplicá-la, e
      -- todo usuário logado passa a ler todos os mandatos. Medido: desligar em caso e decisao não mudava
      -- nenhum outro item desta lista. Tabela e tabela particionada; view não tem RLS própria.
      select count(*), string_agg(c.relname, ', ' order by c.relname)
        into v_n, v_lista
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = r.objeto and c.relkind in ('r', 'p') and not c.relrowsecurity
         -- Tabela de EXTENSÃO (spatial_ref_sys do PostGIS, por exemplo) não é nossa e não se liga RLS nela:
         -- acusá-la deixaria a sonda vermelha para sempre. Mesma exclusão do ramo privilegio.
         and not exists (select 1 from pg_depend dep
                          where dep.classid = 'pg_class'::regclass and dep.objid = c.oid and dep.deptype = 'e');
      v_ok  := v_n = 0;
      v_det := case when v_ok then 'toda tabela do schema com RLS ligada'
                    else format('%s tabela(s) de %s com RLS DESLIGADA: %s', v_n, r.objeto, v_lista) end;

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
  'Confere cada requisito de instalacao_requisito contra o catálogo do banco. Sobrevive ao objeto ausente (to_regclass/to_regproc devolvem NULL em vez de erro): a sonda não pode falhar por causa do que ela existe para medir. Desde a 0147 confere também o CORPO da função (tipo=corpo), que é o único jeito de distinguir uma correção aplicada de uma função homônima com o corpo velho. Desde a 0189 confere também GATILHO (tipo=gatilho): existência na tabela E tgenabled em (''O'',''A'') — a função do gatilho sobrevive a drop trigger/disable trigger e por isso NUNCA prova, sozinha, que a guarda está ligada. Desde a 0210 confere também POLICY (tipo=policy, objeto tabela.nome_da_policy): existência em pg_policy. Desde a 0214 confere PRIVILÉGIO (tipo=privilegio, objeto papel:classe, marcador = privilégios): toda tabela/view/sequence de public sem o mínimo para authenticated e service_role é buraco — o Supabase deixou de conceder por default privilege em 30/10/2026. Desde a 0217 confere SEGREDO do Vault (tipo=segredo, objeto = nome do segredo): existe e não está vazio, sem ler o valor. Desde a 0218 confere RLS LIGADA (tipo=rls, objeto = schema): toda tabela do schema com relrowsecurity — a policy sobrevive a disable row level security.';

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('rls_ligada_em_public', '0218', 'rls', 'public', null, null,
   'Há tabela em public com a RLS DESLIGADA: as policies dela continuam no catálogo, mas não valem, e todo usuário logado lê (e, com o GRANT, escreve) todos os mandatos daquela tabela. Religue: alter table <nome> enable row level security; e confira as policies dela.',
   'bloqueante', 970),
  ('medicao_global_guarda', '0218', 'funcao', 'fn_exige_ler_caso', null, null,
   'Sem fn_exige_ler_caso as medições de concordância (fn_veredito_producao, fn_classe_contabil_concordancia, fn_golden_classe_a) falham ao serem chamadas: a tela de Qualidade da automação e a promoção automática do dial param.',
   'importante', 971),
  ('medicao_global_promocao', '0218', 'corpo', 'fn_dial_auto_promover', E'SECURITY DEFINER\n SET search_path', null,
   'A promoção automática do dial roda como quem disparou o gatilho: com o critério global alcançado pela decisão de um Analista, o dial NÃO sobe e nada fica na trilha (medido: 30 vereditos a 1,0 e o dial parado em N1).',
   'importante', 972),
  ('medicao_global_guarda_do_dial', '0218', 'corpo', 'fn_trg_so_socio', 'current_user', null,
   'A guarda do dial barra também a promoção automática (ela roda dentro de uma função security definer, com o JWT do Analista que disparou): a promoção falha e vira NOTICE, sem trilha.',
   'importante', 973),
  ('medicao_global_veredito', '0218', 'corpo', 'fn_veredito_producao', 'fn_exige_ler_caso', null,
   'O veredito de produção mede só os mandatos de quem pergunta (ou zero, para mandato alheio): o número que decide o dial muda conforme quem olha.',
   'importante', 974),
  ('medicao_global_classe_contabil', '0218', 'corpo', 'fn_classe_contabil_concordancia', 'fn_exige_ler_caso', null,
   'A concordância da classificação contábil mede só os mandatos de quem pergunta, e dá zero para mandato alheio em vez de recusar.',
   'importante', 975),
  ('medicao_global_classe_a', '0218', 'corpo', 'fn_golden_classe_a', 'fn_exige_ler_caso', null,
   'A taxa de falso positivo da Classe A (que alimenta o veredito de reconciliacao_classe_a) mede só os mandatos de quem pergunta.',
   'importante', 976),
  ('medicao_global_golden_cobertura', '0218', 'corpo', 'fn_golden_cobertura', E'SECURITY DEFINER\n SET search_path', null,
   'A cobertura do golden set dá ZERO a quem não é Sócio (golden_* só o Sócio lê, 0216): zero de cobertura é indistinguível de nenhum rótulo.',
   'importante', 977),
  -- O marcador da guarda não basta: CREATE OR REPLACE sem `security definer` volta a função a invoker com o
  -- corpo certo, e a medição volta a ser o recorte de quem olha, com a sonda verde (achado da revisão).
  ('medicao_global_veredito_definer', '0218', 'corpo', 'fn_veredito_producao', E'SECURITY DEFINER\n SET search_path', null,
   'O veredito de produção voltou a invoker: cada leitor vê só o recorte dos mandatos dele, sem aviso.',
   'importante', 978),
  ('medicao_global_classe_contabil_definer', '0218', 'corpo', 'fn_classe_contabil_concordancia', E'SECURITY DEFINER\n SET search_path', null,
   'A concordância da classificação contábil voltou a invoker: cada leitor vê só o recorte dos mandatos dele, sem aviso.',
   'importante', 979),
  ('medicao_global_classe_a_definer', '0218', 'corpo', 'fn_golden_classe_a', E'SECURITY DEFINER\n SET search_path', null,
   'A taxa de falso positivo da Classe A voltou a invoker: cada leitor vê só o recorte dos mandatos dele, sem aviso.',
   'importante', 980),
  ('medicao_global_gatilho_definer', '0218', 'corpo', 'fn_trg_auto_promover_dial', E'SECURITY DEFINER\n SET search_path', null,
   'O gatilho da promoção voltou a invoker: como a promoção não é executável pelo authenticated, a decisão de um Analista que completa o critério falha em silêncio (NOTICE) e o dial não sobe.',
   'importante', 981)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0218', revisado_em = current_date,
       observacao = 'A 0218 põe as medições do dial em security definer (global para todo leitor, 42501 para mandato alheio), a guarda do dial passa o código do banco, e a sonda ganha o tipo rls (RLS ligada em toda tabela de public). Catalogada por nome, corpo e pelo tipo rls.'
 where id = true;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0218' and not presente;
  raise notice '0218: % requisito(s) da 0218 ausente(s) logo depois de aplicar (o esperado é 0).', v_n;
end $$;
