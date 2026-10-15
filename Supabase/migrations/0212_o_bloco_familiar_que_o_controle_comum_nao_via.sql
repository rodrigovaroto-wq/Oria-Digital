-- =============================================================================
-- 0212 — O BLOCO FAMILIAR CONTA COMO CONTROLE COMUM (decisão do dono, fatia 1.7)
-- (F1, depois da 0211. Cria controlador_vinculo, duas funções de escrita e uma de leitura, reemite
--  fn_grupo_por_controle_comum e fn_perimetro_veredito INTEIRAS. Sem backfill: tabela nova, vazia.)
--
-- A DECISÃO, e a prática que a sustenta: controladores PESSOAS FÍSICAS ligados por parentesco PRÓXIMO
-- DECLARADO formam um bloco de controle, e entidades controladas por membros do mesmo bloco são um grupo.
-- É o tratamento de "membros próximos da família" do CPC 05 / IAS 24 e da análise de grupo econômico em crédito.
-- Parentesco aceito: cônjuge/companheiro, ascendente/descendente até o 2º grau em linha reta (pai/mãe/filho,
-- avô/neto) e irmão. NÃO se aceita tio, primo, cunhado: fora do usual.
--
-- NUNCA INFERIR POR SOBRENOME (regra 1; a memória grupo-por-controle-comum-sem-holding diz exatamente isso). O
-- vínculo só existe se DECLARADO, e declarado com FONTE (texto livre: "contrato social", "declaração do
-- cliente"), AUTOR e evento. Duas pessoas com o mesmo sobrenome e sem vínculo declarado continuam em grupos
-- separados, e o teste prova.
--
-- O QUE ESTA MIGRATION ENTREGA
--  * enum `controlador_parentesco` (conjuge_companheiro, linha_reta_ate_2o_grau, irmao): vocabulário fechado e
--    conhecido, enum como na 0179.
--  * tabela `controlador_vinculo`: UM registro por par, SIMÉTRICO por construção (guarda a menor uuid em
--    controlador_a, check a < b, o que também proíbe o auto-vínculo), com fonte obrigatória, quem declarou e,
--    se encerrado, quem, quando e por quê. Um gatilho recusa controlador de outro caso, pessoa jurídica e
--    qualquer edição do que foi declarado (só se encerra).
--  * fn_controlador_vincular_familia(caso, a, b, parentesco, fonte, autor): ordena o par, é IDEMPOTENTE para o
--    mesmo par e parentesco vigentes (devolve o id, sem evento: nada mudou), RECUSA outro parentesco para um par
--    já vigente (encerre antes, para o histórico dizer o que mudou) e grava o evento.
--  * fn_controlador_desvincular_familia(vinculo, motivo, autor): ENCERRA, não apaga. Decisão: o vínculo muda a
--    composição dos grupos do perímetro, e o registro de quem declarou, com que fonte e quando é a evidência
--    dessa mudança; o evento sozinho não é consultável por tabela. Apagar a linha perderia a prova. Por isso
--    não há delete (revoke, como a 0210), o motivo é obrigatório, e o grupo só considera vínculos vigentes.
--  * fn_grupo_por_controle_comum(caso, p_com_familia default true): reemitida INTEIRA com o parâmetro novo. A
--    assinatura de UM argumento continua funcionando (o default) e as colunas são as mesmas. Com
--    p_com_familia = false devolve o grupo da 0182 (só controlador compartilhado); essa é a base do motivo.
--  * fn_grupo_por_controle_comum_motivo(caso): por grupo, o MOTIVO: 'controlador_comum' (as empresas se ligam por
--    sócio compartilhado) ou 'vinculo_familiar' (o grupo junta pelo menos dois grupos que, sem a família,
--    seriam separados). Vem com os vínculos vigentes entre os sócios do grupo, com a fonte de cada um.
--  * fn_perimetro_veredito (0208) reemitida INTEIRA só para expor `motivo` e `vinculos` em cada grupo.
--
-- FECHO TRANSITIVO. Duas entidades se ligam quando um sócio de uma é O MESMO sócio, ou parente declarado, de um
-- sócio da outra; o grupo é o fecho transitivo disso, como na 0182. Logo A-cônjuge-B, B controla X e A controla
-- Y põe X e Y no mesmo grupo. LIMITE DECLARADO: o parentesco é salto único entre sócios, mas se o analista
-- declarar A-B e B-C, as empresas de A e C caem juntas pelo fecho (o efeito "cunhado"). Quem declara os dois
-- vínculos assumiu os dois; a tela deve mostrar os vínculos do grupo, que é o que `vinculos` entrega.
--
-- RLS, como a 0210: authenticated lê, insere e atualiza (o UPDATE é o encerramento), sem delete.
--
-- NÃO HÁ BACKFILL. MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/controlador_familia.test.sql — 38 asserts, medidos em 15/10/2026 com o
-- assert em `raise warning` (voltou para `raise exception`), cada guarda desligada UMA por vez na função/gatilho/
-- policy reaplicada e restaurada, e conferido que a mutação APLICOU (controle intacto: 38 ok, 0 falhou). Reprovam:
-- só pessoa física no gatilho 3, mesmo caso no gatilho 2, "não se edita" (as duas guardas do UPDATE) 2, fonte vazia 1,
-- autor vazio 1, auto-vínculo 1, outro parentesco para o par vigente 1, motivo do encerramento 1, encerrar de novo 1,
-- família desligada no grupo 8, vigência ignorada (vínculo encerrado ainda une) 1, motivo vinculo_familiar 3,
-- vínculos do grupo vazios 2, motivo ausente no veredito 1; sem a policy de insert 16, sem a de update 4, `grant
-- delete` devolvido 1. DUAS mutações ABORTAM o teste em vez de reprovar assert: o par sem ordenar (reprovam 7 e o
-- check controlador_vinculo_ordem aborta) e a idempotência desligada (aborta no 11º assert, 0 reprovados antes).
-- A guarda "encerrar de novo" começou em 0 reprovações: o gatilho já recusava com a mesma frase; a mensagem da função
-- foi diferenciada ("não se encerra de novo") para o teste distinguir qual das duas camadas recusou.
-- Os asserts do cenário "sem vínculo → 2 grupos" e do sobrenome igual passam também sem esta migration: são o
-- controle de que a união só nasce da declaração, não um teste da correção.
-- =============================================================================

create type controlador_parentesco as enum ('conjuge_companheiro', 'linha_reta_ate_2o_grau', 'irmao');

comment on type controlador_parentesco is
  '0212: parentesco PRÓXIMO que une dois controladores pessoas físicas num bloco de controle (CPC 05 / IAS 24). conjuge_companheiro; linha_reta_ate_2o_grau (pai/mãe/filho, avô/neto); irmao. Tio, primo e cunhado ficam de fora, de propósito. Só vale DECLARADO, com fonte: nunca por sobrenome.';

create table controlador_vinculo (
  id                   uuid primary key default gen_random_uuid(),
  caso_id              uuid not null references caso(id) on delete cascade,
  controlador_a        uuid not null references controlador(id) on delete cascade,
  controlador_b        uuid not null references controlador(id) on delete cascade,
  parentesco           controlador_parentesco not null,
  fonte                text not null,
  declarado_por        text not null,
  criado_em            timestamptz not null default now(),
  encerrado_em         timestamptz,
  encerrado_por        text,
  motivo_encerramento  text,
  constraint controlador_vinculo_ordem check (controlador_a < controlador_b),
  constraint controlador_vinculo_fonte check (length(trim(fonte)) > 0),
  constraint controlador_vinculo_autor check (length(trim(declarado_por)) > 0),
  constraint controlador_vinculo_encerramento check (
    (encerrado_em is null and encerrado_por is null and motivo_encerramento is null)
    or (encerrado_em is not null and length(trim(coalesce(encerrado_por, ''))) > 0
        and length(trim(coalesce(motivo_encerramento, ''))) > 0))
);

create unique index controlador_vinculo_vigente_unico
  on controlador_vinculo (controlador_a, controlador_b) where encerrado_em is null;
create index idx_controlador_vinculo_caso on controlador_vinculo (caso_id);

comment on table controlador_vinculo is
  '0212: parentesco próximo DECLARADO entre dois controladores pessoas físicas do mesmo caso (cônjuge/companheiro, linha reta até o 2º grau, irmão). Simétrico por construção: controlador_a é sempre a menor uuid, então o par não tem duas formas nem auto-vínculo. Só vale com fonte e autor, e nunca por sobrenome. Não se apaga nem se edita: encerra-se (encerrado_em, encerrado_por, motivo_encerramento), porque o vínculo muda a composição dos grupos do perímetro e o registro é a evidência. fn_grupo_por_controle_comum considera só os vigentes (encerrado_em nulo). Caminhos de escrita: fn_controlador_vincular_familia e fn_controlador_desvincular_familia.';

create function public.fn_trg_controlador_vinculo_valido() returns trigger
    language plpgsql
    as $$
declare
  v_a record;
  v_b record;
begin
  if tg_op = 'UPDATE' then
    if old.encerrado_em is not null then
      raise exception 'o vínculo % já foi encerrado em %: ele não se edita. Declare outro, se for o caso.', old.id, old.encerrado_em;
    end if;
    if (new.caso_id, new.controlador_a, new.controlador_b, new.parentesco, new.fonte, new.declarado_por, new.criado_em)
       is distinct from
       (old.caso_id, old.controlador_a, old.controlador_b, old.parentesco, old.fonte, old.declarado_por, old.criado_em) then
      raise exception 'o vínculo % não se edita: o que foi declarado (par, parentesco, fonte, autor) fica como está. Encerre-o (fn_controlador_desvincular_familia) e declare outro.', old.id;
    end if;
    return new;
  end if;

  select tipo_pessoa, caso_id, nome into v_a from controlador where id = new.controlador_a;
  select tipo_pessoa, caso_id, nome into v_b from controlador where id = new.controlador_b;
  if v_a.tipo_pessoa is null or v_b.tipo_pessoa is null then
    raise exception 'controlador não encontrado (a=%, b=%)', new.controlador_a, new.controlador_b;
  end if;
  if v_a.tipo_pessoa <> 'fisica' or v_b.tipo_pessoa <> 'fisica' then
    raise exception 'parentesco só vale entre pessoas físicas, e "%" ou "%" é pessoa jurídica', v_a.nome, v_b.nome;
  end if;
  if v_a.caso_id <> new.caso_id or v_b.caso_id <> new.caso_id then
    raise exception 'os dois controladores precisam ser do caso % (a vinculação não cruza casos)', new.caso_id;
  end if;
  return new;
end;
$$;

comment on function public.fn_trg_controlador_vinculo_valido() is
  '0212: a guarda de controlador_vinculo, no banco e não só na função (a policy deixa o authenticated escrever a tabela direto): os dois controladores existem, são pessoas físicas e do caso do vínculo; e o que foi declarado não se edita, nem depois de encerrado.';

create trigger trg_controlador_vinculo_valido
  before insert or update on controlador_vinculo
  for each row execute function public.fn_trg_controlador_vinculo_valido();

alter table controlador_vinculo enable row level security;
create policy controlador_vinculo_read on controlador_vinculo for select to authenticated using (true);
create policy controlador_vinculo_insert on controlador_vinculo for insert to authenticated with check (true);
create policy controlador_vinculo_update on controlador_vinculo for update to authenticated using (true) with check (true);
revoke delete on controlador_vinculo from authenticated;

create function public.fn_controlador_vincular_familia(p_caso_id uuid, p_controlador_a uuid, p_controlador_b uuid,
                                                        p_parentesco controlador_parentesco, p_fonte text, p_autor text)
RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_a    uuid := least(p_controlador_a, p_controlador_b);
  v_b    uuid := greatest(p_controlador_a, p_controlador_b);
  v_viva controlador_vinculo;
  v_id   uuid;
begin
  if p_autor is null or length(trim(p_autor)) = 0 then
    raise exception 'p_autor não pode ser vazio: todo vínculo familiar tem quem o declarou';
  end if;
  if p_fonte is null or length(trim(p_fonte)) = 0 then
    raise exception 'p_fonte não pode ser vazia: o parentesco só vale declarado, com a fonte (ex.: "contrato social", "declaração do cliente")';
  end if;
  if v_a = v_b then
    raise exception 'um controlador não tem vínculo familiar com ele mesmo';
  end if;

  select * into v_viva from controlador_vinculo
   where controlador_a = v_a and controlador_b = v_b and encerrado_em is null;
  if found then
    if v_viva.parentesco = p_parentesco then
      return v_viva.id;  -- já vigente, mesmo parentesco: nada a gravar
    end if;
    raise exception 'o par já tem um vínculo vigente (%), e % é outro parentesco. Encerre o vigente (fn_controlador_desvincular_familia) e declare o novo, para o histórico dizer o que mudou.',
      v_viva.parentesco, p_parentesco;
  end if;

  insert into controlador_vinculo (caso_id, controlador_a, controlador_b, parentesco, fonte, declarado_por)
  values (p_caso_id, v_a, v_b, p_parentesco, trim(p_fonte), trim(p_autor))
  returning id into v_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (p_autor, 'controlador_vinculo_declarado', 'controlador:' || v_a,
          jsonb_build_object('vinculo_id', v_id, 'caso_id', p_caso_id, 'controlador_a', v_a,
                             'controlador_b', v_b, 'parentesco', p_parentesco, 'fonte', trim(p_fonte)));
  return v_id;
end;
$$;

comment on function public.fn_controlador_vincular_familia(uuid, uuid, uuid, controlador_parentesco, text, text) is
  '0212: declara parentesco próximo entre dois controladores pessoas físicas do caso, COM fonte e autor. A ordem dos dois é indiferente (o par é simétrico). Idempotente para o mesmo par e parentesco vigentes (devolve o id, sem evento); outro parentesco para um par vigente é recusado (encerre antes). Pessoa jurídica, controlador de outro caso e auto-vínculo são recusados. Grava controlador_vinculo_declarado. Nunca infere por sobrenome.';

grant execute on function public.fn_controlador_vincular_familia(uuid, uuid, uuid, controlador_parentesco, text, text) to authenticated;

create function public.fn_controlador_desvincular_familia(p_vinculo_id uuid, p_motivo text, p_autor text)
RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_v controlador_vinculo;
begin
  if p_autor is null or length(trim(p_autor)) = 0 then
    raise exception 'p_autor não pode ser vazio';
  end if;
  if p_motivo is null or length(trim(p_motivo)) = 0 then
    raise exception 'p_motivo não pode ser vazio: encerrar um vínculo muda os grupos do perímetro, e o porquê fica no registro';
  end if;
  select * into v_v from controlador_vinculo where id = p_vinculo_id;
  if not found then
    raise exception 'vínculo % não encontrado', p_vinculo_id;
  end if;
  if v_v.encerrado_em is not null then
    raise exception 'o vínculo % já foi encerrado em % e não se encerra de novo', p_vinculo_id, v_v.encerrado_em;
  end if;

  update controlador_vinculo
     set encerrado_em = now(), encerrado_por = trim(p_autor), motivo_encerramento = trim(p_motivo)
   where id = p_vinculo_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (p_autor, 'controlador_vinculo_encerrado', 'controlador:' || v_v.controlador_a,
          jsonb_build_object('vinculo_id', p_vinculo_id, 'caso_id', v_v.caso_id,
                             'controlador_a', v_v.controlador_a, 'controlador_b', v_v.controlador_b,
                             'parentesco', v_v.parentesco, 'motivo', trim(p_motivo)));
  return p_vinculo_id;
end;
$$;

comment on function public.fn_controlador_desvincular_familia(uuid, text, text) is
  '0212: ENCERRA o vínculo familiar (não apaga: a linha é a evidência de quem declarou, com que fonte e quando). Motivo e autor obrigatórios. Vínculo inexistente ou já encerrado é recusado. Grava controlador_vinculo_encerrado. O grupo passa a ignorá-lo.';

grant execute on function public.fn_controlador_desvincular_familia(uuid, text, text) to authenticated;

-- fn_grupo_por_controle_comum: a 0182 INTEIRA, com o parâmetro p_com_familia. DROP antes do CREATE: um
-- `create or replace` com o parâmetro a mais criaria uma SEGUNDA função, e a chamada de um argumento ficaria
-- ambígua. `par_direto` continua MATERIALIZED (a lição da 0152), e `pares_ctrl` também, pelo mesmo motivo.
drop function if exists public.fn_grupo_por_controle_comum(uuid);

create function public.fn_grupo_por_controle_comum(p_caso_id uuid, p_com_familia boolean default true)
RETURNS TABLE(entidade_id uuid, razao_social text, grupo_id uuid)
    LANGUAGE sql STABLE
    AS $$
  with recursive pares_ctrl as materialized (
    -- o mesmo sócio (0182)...
    select ec.controlador_id as x, ec.controlador_id as y
      from entidade_controlador ec
     where ec.caso_id = p_caso_id
    union
    -- ...ou sócios com parentesco próximo DECLARADO e vigente (0212), nos dois sentidos
    select v.controlador_a, v.controlador_b
      from controlador_vinculo v
     where p_com_familia and v.caso_id = p_caso_id and v.encerrado_em is null
    union
    select v.controlador_b, v.controlador_a
      from controlador_vinculo v
     where p_com_familia and v.caso_id = p_caso_id and v.encerrado_em is null
  ),
  par_direto as materialized (
    select ec1.entidade_id as a, ec2.entidade_id as b
      from entidade_controlador ec1
      join pares_ctrl p on p.x = ec1.controlador_id
      join entidade_controlador ec2
        on ec2.controlador_id = p.y
       and ec2.entidade_id <> ec1.entidade_id
     where ec1.caso_id = p_caso_id
  ),
  alcance(entidade_id, alcancavel) as (
    select e.id, e.id
      from entidade e
     where e.caso_id = p_caso_id
       and exists (
         select 1 from entidade_controlador ec
          where ec.entidade_id = e.id and ec.caso_id = p_caso_id)
    union
    select al.entidade_id, pd.b
      from alcance al
      join par_direto pd on pd.a = al.alcancavel
  )
  select al.entidade_id, e.razao_social, min(al.alcancavel::text)::uuid as grupo_id
    from alcance al
    join entidade e on e.id = al.entidade_id
   group by al.entidade_id, e.razao_social
   order by min(al.alcancavel::text), e.razao_social;
$$;

comment on function public.fn_grupo_por_controle_comum(uuid, boolean) is
  '0182: agrupa as entidades do caso por CONTROLE COMUM, por FECHO TRANSITIVO. 0212: duas entidades também se ligam quando um sócio de uma é PARENTE PRÓXIMO DECLARADO e vigente (controlador_vinculo) de um sócio da outra; com p_com_familia = false devolve o grupo da 0182, só por sócio compartilhado (base de fn_grupo_por_controle_comum_motivo). A chamada de um argumento segue valendo (default true). `grupo_id` é o entidade_id alcançável de menor ordenação textual: representante estável, não uma entidade principal. Entidade sem controlador registrado não aparece (ausência não afirma nada, regra 7). A recursão termina pela deduplicação do union sobre um conjunto finito.';

grant execute on function public.fn_grupo_por_controle_comum(uuid, boolean) to authenticated;

create function public.fn_grupo_por_controle_comum_motivo(p_caso_id uuid)
RETURNS TABLE(grupo_id uuid, entidades integer, motivo text, vinculos jsonb)
    LANGUAGE sql STABLE
    AS $$
  with g1 as materialized (select * from fn_grupo_por_controle_comum(p_caso_id, true)),
  g0 as materialized (select * from fn_grupo_por_controle_comum(p_caso_id, false)),
  por_grupo as (
    select g1.grupo_id, count(*)::int as entidades, count(distinct g0.grupo_id)::int as grupos_sem_familia
      from g1 join g0 on g0.entidade_id = g1.entidade_id
     group by g1.grupo_id
  )
  select pg.grupo_id, pg.entidades,
         case when pg.grupos_sem_familia > 1 then 'vinculo_familiar' else 'controlador_comum' end,
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'vinculo_id', v.id, 'parentesco', v.parentesco, 'fonte', v.fonte,
                    'declarado_por', v.declarado_por,
                    'controlador_a', ca.nome, 'controlador_b', cb.nome)
                  order by ca.nome, cb.nome, v.id)
             from controlador_vinculo v
             join controlador ca on ca.id = v.controlador_a
             join controlador cb on cb.id = v.controlador_b
            where v.caso_id = p_caso_id and v.encerrado_em is null
              and exists (select 1 from g1 x join entidade_controlador ec on ec.entidade_id = x.entidade_id
                           where x.grupo_id = pg.grupo_id and ec.controlador_id = v.controlador_a)
              and exists (select 1 from g1 x join entidade_controlador ec on ec.entidade_id = x.entidade_id
                           where x.grupo_id = pg.grupo_id and ec.controlador_id = v.controlador_b)
         ), '[]'::jsonb)
    from por_grupo pg
   order by pg.grupo_id;
$$;

comment on function public.fn_grupo_por_controle_comum_motivo(uuid) is
  '0212: por grupo de controle, POR QUE as entidades estão juntas. controlador_comum: ligam-se por sócio compartilhado (o grupo existiria sem nenhum vínculo familiar). vinculo_familiar: o grupo junta pelo menos dois grupos que, sem a família, seriam separados. `vinculos` traz os parentescos vigentes entre sócios do grupo, com fonte e quem declarou. Calcula g0 (sem família) e g1 (com) pela MESMA função, não por uma segunda recursão.';

grant execute on function public.fn_grupo_por_controle_comum_motivo(uuid) to authenticated;

create or replace function public.fn_perimetro_veredito(p_caso_id uuid)
 RETURNS TABLE(entidades integer, prontas integer, fantasmas integer, fechado boolean, fechado_motivo text, grupos jsonb, aceite_financeiro text, aceite_motivo text)
 LANGUAGE sql
 STABLE
AS $function$
  with s as materialized (select * from fn_perimetro_situacao(p_caso_id)),
  n as (
    select count(*) filter (where not s.fantasma)::int as reais,
           count(*) filter (where s.pronta and not s.fantasma)::int as prontas,
           count(*) filter (where s.fantasma)::int as fantasmas
      from s
  ),
  g as (
    -- 0212: cada grupo diz POR QUE está junto (fn_grupo_por_controle_comum_motivo): controlador_comum
    -- (compartilham sócio) ou vinculo_familiar (só a parentesco declarado os une), com os vínculos e a fonte.
    select coalesce(jsonb_agg(jsonb_build_object(
             'grupo_id', t.grupo_id, 'quantas', t.quantas, 'motivo', t.motivo,
             'vinculos', t.vinculos, 'entidades', t.membros)
             order by t.grupo_id), '[]'::jsonb) as grupos
      from (select m.grupo_id, m.entidades as quantas, m.motivo, m.vinculos,
                   (select jsonb_agg(jsonb_build_object('entidade_id', x.entidade_id,
                                                        'razao_social', x.razao_social)
                                     order by x.razao_social, x.entidade_id)
                      from fn_grupo_por_controle_comum(p_caso_id) x
                     where x.grupo_id = m.grupo_id) as membros
              from fn_grupo_por_controle_comum_motivo(p_caso_id) m) t
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
$function$;


insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('controlador_vinculo_tabela', '0212', 'tabela', 'controlador_vinculo', null, null,
   'Onde mora o parentesco próximo DECLARADO entre sócios. Ausente, irmãos e cônjuges sócios de empresas diferentes aparecem como grupos separados e o perímetro fica subdimensionado.',
   'importante', 900),
  ('controlador_vincular_familia_funcao', '0212', 'funcao', 'fn_controlador_vincular_familia', null, null,
   'O único caminho para declarar parentesco, com fonte e autor. Ausente, a tela não tem como registrar o bloco familiar.',
   'importante', 901),
  ('controlador_desvincular_familia_funcao', '0212', 'funcao', 'fn_controlador_desvincular_familia', null, null,
   'O único caminho para encerrar um vínculo familiar declarado errado, com motivo e sem perder o histórico.',
   'importante', 902),
  ('grupo_controle_motivo_funcao', '0212', 'funcao', 'fn_grupo_por_controle_comum_motivo', null, null,
   'Diz POR QUE um grupo está junto (sócio comum ou vínculo familiar). Ausente, o veredito do perímetro mostra o grupo sem a justificativa.',
   'importante', 903),
  ('grupo_controle_familia_corpo', '0212', 'corpo', 'fn_grupo_por_controle_comum', 'p_com_familia', null,
   'Corpo anterior ao desta migration ignora o vínculo familiar: Karina e o irmão, sócios de empresas diferentes, ficam em grupos separados.',
   'importante', 904),
  ('perimetro_veredito_motivo_corpo', '0212', 'corpo', 'fn_perimetro_veredito', 'fn_grupo_por_controle_comum_motivo', null,
   'Corpo anterior ao desta migration devolve os grupos sem o motivo nem os vínculos que os justificam.',
   'importante', 905),
  ('controlador_vinculo_valido_gatilho', '0212', 'gatilho', 'controlador_vinculo.trg_controlador_vinculo_valido', null, null,
   'Sem ele a tabela aceita vínculo entre pessoa jurídica, entre casos, e a edição do que foi declarado (a policy deixa o authenticated escrever direto).',
   'importante', 906),
  ('controlador_vinculo_insert_policy', '0212', 'policy', 'controlador_vinculo.controlador_vinculo_insert', null, null,
   'Sem ela o authenticated não declara vínculo familiar (42501).',
   'importante', 907),
  ('controlador_vinculo_update_policy', '0212', 'policy', 'controlador_vinculo.controlador_vinculo_update', null, null,
   'Sem ela o authenticated não encerra vínculo familiar (o UPDATE afeta 0 linhas em silêncio).',
   'importante', 908)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0212', revisado_em = current_date,
       observacao = 'A 0212 cria controlador_vinculo (parentesco próximo declarado entre sócios pessoas físicas), fn_controlador_vincular_familia, fn_controlador_desvincular_familia e fn_grupo_por_controle_comum_motivo, e reemite fn_grupo_por_controle_comum (p_com_familia) e fn_perimetro_veredito (motivo e vínculos por grupo). Tabela nova, vazia; sem backfill.'
 where id = true;
