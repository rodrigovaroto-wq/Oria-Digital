-- =============================================================================
-- 0208 — A SITUAÇÃO DO PERÍMETRO: "ESTÁ FECHADO? SE NÃO, O QUE FALTA, EM QUAL ENTIDADE?"
-- (F1 do roadmap, seção 12: "Saída: toda entidade com papel e escopo; 0 entidade_ambigua não
--  resolvida". Só ACRESCENTA duas funções de leitura: nenhuma função existente é reemitida,
--  `campo_extraido` não é tocada, não há backfill.)
--
-- O DEFEITO. As migrations 0178–0183 criaram tudo o que GUARDA o perímetro — papel_no_grupo (0179),
-- perimetro com vigência (0180), controladora_id e percentual (0181), controlador e controle comum
-- (0182), forma_de_controle (0183), a marca de entidade fantasma (0178) — e NADA fora dos testes
-- lê essas peças juntas: grep em portal/src, N8N e Leitor dá zero chamadas a fn_perimetro_vigente,
-- fn_grupo_por_controle_comum ou fn_entidade_definir_*. Não existia uma resposta única para "o
-- perímetro deste caso está fechado?", e a tela que vai perguntar isso (outro agente, em seguida)
-- teria de inventar a regra no TypeScript — uma segunda implementação da mesma conta, que diverge
-- sem erro nenhum. A regra mora aqui.
--
-- AS DUAS FUNÇÕES (security invoker, o padrão das leituras vizinhas: respeitam a RLS de quem chama).
--  * fn_perimetro_situacao(caso)  — uma linha por entidade, com `falta` NOMEADO e `pronta`.
--  * fn_perimetro_veredito(caso)  — uma linha: contagens, `fechado`, grupos e o aceite financeiro.
--
-- QUANDO UMA ENTIDADE ESTÁ `pronta` (cada motivo de `falta` é um nome estável, que a tela mostra):
--   papel_no_grupo_indefinido                 papel_no_grupo é NULL (0179; ninguém decidiu)
--   forma_de_controle_indefinida              forma_de_controle = 'indefinido' (0183; ninguém declarou)
--   controlada_por_entidade_sem_controladora  forma controlada_por_entidade e controladora_id NULL
--   controle_comum_sem_vinculo                forma controle_comum e nenhuma linha em entidade_controlador
--   sem_escopo_vigente                        papel definido, diferente de fora_do_perimetro, e nenhuma
--                                             linha de `perimetro` vigente hoje (desde <= hoje, ate nulo
--                                             ou >= hoje, QUALQUER escopo)
--   fora_do_perimetro_com_escopo_vigente      papel fora_do_perimetro e, ao mesmo tempo, escopo vigente
--   pendencia_aberta:<tipo>                   pendência aberta de perímetro ligada à entidade
--   entidade_fantasma_pendente_de_revisao     ver abaixo
-- Pendência de perímetro = papel_no_grupo_indefinido, forma_de_controle_indefinida, entidade_incorreta
-- (o <tipo> é o prefixo do motivo: entidade_ambigua, entidade_nome_suspeito...; "entidade_incorreta"
-- quando o motivo não nomeia) e item_faltante de contrato social (motivo contrato_social_ausente:<id>).
-- "Aberta" = aberta, em_correcao_interna ou reenviada_ao_cliente, o mesmo conjunto que o painel de
-- falsos positivos usa. aceita_com_ressalva ("prosseguir sem resolução") e rejeitada ("não procede")
-- são decisões humanas EXPLÍCITAS e não seguram a entidade: a ressalva continua na pendência.
-- Papel e forma indefinidos também têm a pendência (0179/0183): a falta nasce UMA vez só, da coluna,
-- e a pendência só aparece em separado se a coluna já foi preenchida e a pendência ficou aberta.
--
-- A ENTIDADE FANTASMA (0178). A guarda NÃO tem coluna: marca a entidade com uma pendência
-- entidade_incorreta, motivo entidade_nome_suspeito:<id>, enquanto aberta. Decisão: a fantasma NÃO entra
-- em `entidades` nem em `prontas` (nome de coluna de planilha não é empresa do grupo), é contada à parte
-- em `fantasmas`, aparece na situação com `falta = {entidade_fantasma_pendente_de_revisao}` (nunca some em
-- silêncio, regra 1) e IMPEDE `fechado`: os documentos dela ficam fora do book de qualquer empresa real
-- até alguém fundir ou descartar (o efeito escrito na própria pendência da 0178). Só essa falta é listada
-- para ela: papel e escopo de um cabeçalho de planilha seriam ruído; as pendências seguem em
-- `pendencias_abertas`.
--
-- O ACEITE FINANCEIRO (F1: "perímetro reproduz o COMBINADO do cliente, ou declara a diferença") NÃO é
-- verificável pelo sistema: não há comparação do perímetro contra nenhum combinado. Por isso o veredito
-- devolve 'nao_verificado' com o EFEITO por extenso (nunca 'ok' por omissão), e só 'pendente_conferencia'
-- quando existe, no caso, documento COMBINADO de verdade — tipo_taxonomia = 'COMBINADO' e VALOR extraído
-- em mais de uma coluna de entidade, o mesmo critério de fn_documento_serve_como (0157). Mesmo então a
-- conferência é humana; a função não compara coluna com perímetro. `fechado` não depende do aceite: são
-- duas perguntas (o cadastro está completo? / o cadastro bate com o cliente?), e a segunda não pode
-- segurar a primeira nem passar por ela.
--
-- CASO SEM ENTIDADE: fechado = false. Zero entidades não é perímetro fechado, é perímetro que nunca foi
-- montado (nenhum documento foi atribuído a uma empresa) — o mesmo "não rodou parece limpo" da regra 7.
--
-- NÃO HÁ BACKFILL: funções de leitura. Produção não é tocada.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/perimetro_situacao.test.sql — 52 asserts, medidos em 15/10/2026 com o
-- assert em `raise warning` (voltou para `raise exception` depois; a suíte inteira foi relida atrás de FALHOU:).
-- Cada guarda desligada UMA por vez numa cópia da função, e antes de cada número conferi que a mutação APLICOU e
-- que o teste rodou (controle com a migration intacta: 52 ok, 0 falhou). Reprovam, por guarda: papel indefinido 1,
-- forma indefinida 2, controlada_por_entidade sem controladora 1, controle_comum sem vínculo 1, sem_escopo_vigente 5,
-- fora_do_perimetro com escopo 1, isenção de fora_do_perimetro 1, pendência aberta 4, o conjunto de estados abertos
-- (trocado por "<> resolvida") 5, item_faltante só de contrato social 1, entidade pelo documento da pendência 1,
-- escopo que só começa no futuro 1, escopo expirado 1, marca da fantasma 5, fantasma que segura `fechado` 1,
-- fantasma contada como entidade 2, caso vazio fechado 2, aceite sempre ok 4, aceite sempre pendente_conferencia 3,
-- COMBINADO com uma coluna basta 1, aceite sem o EFEITO por extenso 1, grupos vazios 1. E com `pronta` sempre
-- verdadeira, o CONJUNTO das guardas de falta, 9 dos 52 asserts reprovam. O teste achou um defeito meu antes de
-- ser medido: o uuid do contrato social era lido da posição 24 do motivo em vez da 25 (invalid input syntax).
-- Reaproveitar o nome "Controle..." numa entidade de teste ativou a guarda da 0178: o léxico de título vale também aqui.
-- =============================================================================

create or replace function fn_perimetro_situacao(p_caso_id uuid)
returns table (
  entidade_id uuid,
  razao_social text,
  cnpj text,
  fantasma boolean,
  papel_no_grupo entidade_papel_no_grupo,
  forma_de_controle entidade_forma_de_controle,
  controladora_id uuid,
  percentual_participacao numeric,
  escopos_vigentes text[],
  controladores jsonb,
  pendencias_abertas text[],
  falta text[],
  pronta boolean
)
language sql stable
as $$
  with pend as materialized (
    -- uma linha por (entidade, rótulo) das pendências de perímetro ABERTAS. A entidade vem da própria
    -- pendência ou, nas entidade_incorreta que só citam o documento, da entidade onde o documento está.
    select distinct
           coalesce(p.entidade_id, d.entidade_id,
                    case when p.motivo ~ '^contrato_social_ausente:[0-9a-f-]{36}$'
                         then substr(p.motivo, 25)::uuid end) as entidade_id,
           case
             when p.tipo = 'entidade_incorreta' then
               case when p.motivo is null or p.motivo like 'diagnostico:%' then 'entidade_incorreta'
                    else split_part(p.motivo, ':', 1) end
             when p.tipo = 'item_faltante' then 'contrato_social_ausente'
             else p.tipo::text
           end as rotulo
      from pendencia p
      left join documento d on d.id = p.documento_id
     where p.caso_id = p_caso_id
       and p.estado in ('aberta', 'em_correcao_interna', 'reenviada_ao_cliente')
       and (p.tipo in ('papel_no_grupo_indefinido', 'forma_de_controle_indefinida', 'entidade_incorreta')
            or (p.tipo = 'item_faltante' and p.motivo like 'contrato_social_ausente:%'))
  ),
  base as (
    select e.id, e.razao_social, e.cnpj, e.papel_no_grupo, e.forma_de_controle,
           e.controladora_id, e.percentual_participacao,
           coalesce((select array_agg(distinct p.escopo order by p.escopo)
                       from perimetro p
                      where p.caso_id = p_caso_id and p.entidade_id = e.id
                        and p.desde <= current_date
                        and (p.ate is null or p.ate >= current_date)), '{}'::text[]) as escopos,
           coalesce((select jsonb_agg(jsonb_build_object(
                         'controlador_id', c.id, 'nome', c.nome, 'tipo_pessoa', c.tipo_pessoa,
                         'documento', c.documento, 'percentual', ec.percentual)
                       order by c.nome, c.id)
                       from entidade_controlador ec
                       join controlador c on c.id = ec.controlador_id
                      where ec.caso_id = p_caso_id and ec.entidade_id = e.id), '[]'::jsonb) as ctrls,
           (select count(*) from entidade_controlador ec
             where ec.caso_id = p_caso_id and ec.entidade_id = e.id) as n_vinculos,
           coalesce((select array_agg(pe.rotulo order by pe.rotulo)
                       from pend pe where pe.entidade_id = e.id), '{}'::text[]) as rotulos
      from entidade e
     where e.caso_id = p_caso_id
  ),
  marcada as (
    select b.*, 'entidade_nome_suspeito' = any (b.rotulos) as eh_fantasma
      from base b
  ),
  faltas as (
    select m.*,
           case
             when m.eh_fantasma then array['entidade_fantasma_pendente_de_revisao']
             else
               array_remove(array[
                 case when m.papel_no_grupo is null then 'papel_no_grupo_indefinido' end,
                 case when m.forma_de_controle = 'indefinido' then 'forma_de_controle_indefinida' end,
                 case when m.forma_de_controle = 'controlada_por_entidade' and m.controladora_id is null
                      then 'controlada_por_entidade_sem_controladora' end,
                 case when m.forma_de_controle = 'controle_comum' and m.n_vinculos = 0
                      then 'controle_comum_sem_vinculo' end,
                 case when m.papel_no_grupo is not null and m.papel_no_grupo <> 'fora_do_perimetro'
                           and cardinality(m.escopos) = 0
                      then 'sem_escopo_vigente' end,
                 case when m.papel_no_grupo = 'fora_do_perimetro' and cardinality(m.escopos) > 0
                      then 'fora_do_perimetro_com_escopo_vigente' end
               ], null)
               || coalesce((select array_agg('pendencia_aberta:' || r order by r)
                              from unnest(m.rotulos) r
                             where not (r = 'papel_no_grupo_indefinido' and m.papel_no_grupo is null)
                               and not (r = 'forma_de_controle_indefinida'
                                        and m.forma_de_controle = 'indefinido')), '{}'::text[])
           end as falta
      from marcada m
  )
  select f.id, f.razao_social, f.cnpj, f.eh_fantasma, f.papel_no_grupo, f.forma_de_controle,
         f.controladora_id, f.percentual_participacao, f.escopos, f.ctrls, f.rotulos, f.falta,
         cardinality(f.falta) = 0
    from faltas f
   order by f.eh_fantasma, f.razao_social, f.id;
$$;

comment on function fn_perimetro_situacao(uuid) is
  '0208: uma linha por entidade do caso com o que falta para o perímetro estar fechado, NOMEADO em `falta` (papel_no_grupo_indefinido, forma_de_controle_indefinida, controlada_por_entidade_sem_controladora, controle_comum_sem_vinculo, sem_escopo_vigente, fora_do_perimetro_com_escopo_vigente, pendencia_aberta:<tipo>, entidade_fantasma_pendente_de_revisao). pronta = falta vazia. A fantasma (0178: pendência entidade_nome_suspeito aberta) aparece com falta própria e não conta como entidade real. Escopo vigente = perimetro com desde <= hoje e ate nulo ou >= hoje. Somente leitura, security invoker. A tela consome esta função e NÃO repete a regra.';

grant execute on function fn_perimetro_situacao(uuid) to authenticated;

create or replace function fn_perimetro_veredito(p_caso_id uuid)
returns table (
  entidades integer,
  prontas integer,
  fantasmas integer,
  fechado boolean,
  fechado_motivo text,
  grupos jsonb,
  aceite_financeiro text,
  aceite_motivo text
)
language sql stable
as $$
  with s as materialized (select * from fn_perimetro_situacao(p_caso_id)),
  n as (
    select count(*) filter (where not s.fantasma)::int as reais,
           count(*) filter (where s.pronta and not s.fantasma)::int as prontas,
           count(*) filter (where s.fantasma)::int as fantasmas
      from s
  ),
  g as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'grupo_id', t.grupo_id, 'quantas', t.quantas, 'entidades', t.membros)
             order by t.grupo_id), '[]'::jsonb) as grupos
      from (select x.grupo_id, count(*) as quantas,
                   jsonb_agg(jsonb_build_object('entidade_id', x.entidade_id,
                                                'razao_social', x.razao_social)
                             order by x.razao_social, x.entidade_id) as membros
              from fn_grupo_por_controle_comum(p_caso_id) x
             group by x.grupo_id) t
  ),
  c as (
    -- COMBINADO de verdade: rotulado COMBINADO e com VALOR em mais de uma coluna de entidade
    -- (o critério de fn_documento_serve_como, 0157).
    select count(*)::int as docs
      from documento d
     where d.caso_id = p_caso_id
       and d.tipo_taxonomia = 'COMBINADO'
       and (select count(distinct ce.entidade_coluna)
              from campo_extraido ce
             where ce.documento_versao_id = fn_versao_com_extracao(d.id)
               and ce.valor_num is not null
               and ce.entidade_coluna is not null) > 1
  )
  select n.reais, n.prontas, n.fantasmas,
         (n.reais > 0 and n.prontas = n.reais and n.fantasmas = 0),
         case
           when n.reais = 0 and n.fantasmas = 0 then
             'O caso não tem nenhuma entidade: zero entidades não é perímetro fechado, é perímetro que nunca foi montado (nenhum documento foi atribuído a uma empresa).'
           when n.reais = 0 then
             format('O caso só tem %s entidade(s) fantasma (nome de coluna, aba ou arquivo tratado como empresa) e nenhuma entidade real: não há perímetro a fechar.', n.fantasmas)
           when n.fantasmas > 0 and n.prontas < n.reais then
             format('%s de %s entidades reais ainda têm falta, e há %s entidade(s) fantasma sem revisão: os documentos delas ficam fora do book de qualquer empresa real até alguém fundir ou descartar.', n.reais - n.prontas, n.reais, n.fantasmas)
           when n.fantasmas > 0 then
             format('Todas as %s entidades reais estão prontas, mas há %s entidade(s) fantasma sem revisão: os documentos delas ficam fora do book de qualquer empresa real até alguém fundir ou descartar.', n.reais, n.fantasmas)
           when n.prontas < n.reais then
             format('%s de %s entidades ainda têm falta (veja fn_perimetro_situacao): enquanto isso o perímetro não afirma quem entra no combinado.', n.reais - n.prontas, n.reais)
           else
             format('As %s entidades têm papel, forma de controle e escopo coerentes e nenhuma pendência de perímetro aberta. Isto diz que o CADASTRO está completo, não que o perímetro bate com o combinado do cliente (ver aceite_financeiro).', n.reais)
         end,
         g.grupos,
         case when c.docs > 0 then 'pendente_conferencia' else 'nao_verificado' end,
         case when c.docs > 0 then
           format('Existe(m) %s documento(s) COMBINADO com valor em mais de uma entidade, mas o sistema NÃO compara o perímetro com ele: a conferência é humana. Enquanto ninguém conferir, o perímetro pode incluir ou excluir uma empresa que o combinado do cliente trata diferente, e todo número consolidado a partir dele herda a diferença sem aviso.', c.docs)
         else
           'Não há documento COMBINADO do cliente com valor em mais de uma entidade neste caso, então o perímetro não foi comparado com nada. O efeito: o perímetro cadastrado pode incluir ou excluir uma empresa que o cliente trata diferente, e o combinado e a consolidação calculados a partir dele herdam a diferença sem aviso. Um grupo por controle comum frequentemente nunca preparou combinado; o aceite fica nao_verificado, não ok.'
         end
    from n, g, c;
$$;

comment on function fn_perimetro_veredito(uuid) is
  '0208: o veredito do perímetro do caso numa linha: entidades (reais, sem as fantasmas), prontas, fantasmas, fechado (>0 reais, todas prontas, 0 fantasmas) e o motivo por extenso, grupos por controle comum (fn_grupo_por_controle_comum resumido) e o aceite financeiro, que NUNCA é ok: nao_verificado (sem combinado do cliente para comparar, com o efeito dito) ou pendente_conferencia (há combinado, a conferência é humana). Somente leitura, security invoker.';

grant execute on function fn_perimetro_veredito(uuid) to authenticated;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('perimetro_situacao_funcao', '0208', 'funcao', 'fn_perimetro_situacao', null, null,
   'A resposta única de "o que falta, em qual entidade" para o perímetro. Ausente, a tela reimplementa a regra no TypeScript e as duas divergem sem erro.',
   'importante', 890),
  ('perimetro_situacao_corpo', '0208', 'corpo', 'fn_perimetro_situacao', 'sem_escopo_vigente', null,
   'Corpo anterior ao desta migration não cobra escopo vigente de quem está no perímetro: entidade com papel e sem escopo passaria por pronta.',
   'importante', 891),
  ('perimetro_veredito_funcao', '0208', 'funcao', 'fn_perimetro_veredito', null, null,
   'O veredito do perímetro (fechado ou não, e o aceite financeiro). Ausente, "fechado" é opinião da tela.',
   'importante', 892),
  ('perimetro_veredito_corpo', '0208', 'corpo', 'fn_perimetro_veredito', 'nao_verificado', null,
   'Corpo anterior ao desta migration pode devolver aceite financeiro ok por omissão, ou tratar caso sem entidade como perímetro fechado.',
   'importante', 893)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0208', revisado_em = current_date,
       observacao = 'A 0208 cria fn_perimetro_situacao e fn_perimetro_veredito (leitura, sem tabela nova nem backfill). Catalogadas por nome e pelo corpo.'
 where id = true;
