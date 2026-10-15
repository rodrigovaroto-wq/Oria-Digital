-- =============================================================================
-- 0209 — O ESCOPO DO PERÍMETRO QUE NÃO SE CONFIRMAVA DE NOVO NEM SE ENCERRAVA
-- (F1, depois da 0208. Reemite fn_perimetro_definir_escopo (0180) INTEIRA e acrescenta
--  fn_perimetro_encerrar_escopo. Sem tabela nova, sem backfill.)
--
-- O DEFEITO, medido pela sessão principal rodando Supabase/test/perimetro_situacao.test.sql DUAS vezes
-- no mesmo banco: chamar fn_perimetro_definir_escopo outra vez para o mesmo (caso, entidade, escopo) com
-- p_desde IGUAL ou ANTERIOR ao `desde` do intervalo vigente fazia o `update` do fechamento gravar
-- ate = p_desde - 1 < desde, e o analista recebia um erro de CHECK ("perimetro_intervalo_valido") em vez de
-- uma frase. A 0180 deixou isso de propósito (o check faria o trabalho), com um custo que ela não media: a
-- tela chama isto por clique, e confirmar de novo o mesmo escopo é o gesto mais comum que existe.
-- E NÃO havia caminho para TIRAR uma entidade de um escopo (fechar `ate` sem abrir outro): sem ele, a falta
-- fora_do_perimetro_com_escopo_vigente da 0208 era irresolvível pela tela.
--
-- DECISÕES (cada uma com o porquê):
--  * Vigente com o MESMO desde: IDEMPOTENTE, devolve o id do intervalo existente e NÃO grava evento. Nada
--    mudou no banco, e um evento por clique encheria a trilha de "confirmações" que não são decisões. O
--    evento existente (o da definição original) continua sendo a prova de quem decidiu e quando.
--  * Vigente com desde POSTERIOR a p_desde: exceção em português que diz o que fazer. Aceitar seria
--    reescrever o passado (o intervalo vigente começou depois do que o analista está declarando) e não há
--    como "fechar" um intervalo antes do seu começo. Quem quer corrigir o início apaga/ajusta por SQL
--    direto, com a trilha na mão; não é gesto de tela.
--  * p_desde > desde do vigente: como hoje (fecha com p_desde - 1 e abre o novo).
--  * fn_perimetro_encerrar_escopo SEM intervalo vigente: EXCEÇÃO, não no-op. Um "encerrei" silencioso numa
--    tela velha (outro analista já encerrou, ou o escopo tem outro nome) afirmaria uma remoção que este
--    clique não fez (regra 1). O erro nomeia o escopo para a tela mostrar.
--  * p_ate é o ÚLTIMO dia dentro (inclusivo), a mesma convenção do ate que a 0180 grava (p_desde - 1).
--    p_ate < desde recusa com mensagem; p_ate = desde é válido (um dia só).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/perimetro_encerrar.test.sql — 28 asserts, medidos em 15/10/2026 com o
-- assert em `raise warning` (voltou para `raise exception`), cada guarda desligada UMA por vez numa cópia da função,
-- conferido que a mutação APLICOU e o teste rodou (controle intacto: 28 ok, 0 falhou). Reprovam: idempotência do
-- mesmo desde 2, exceção do desde anterior 1, encerrar sem intervalo vigente (devolver null em vez de levantar) 5,
-- p_ate antes do desde 1, p_ate nulo 1, evento do encerramento 1, filtro de caso do encerrar 6, filtro de escopo do
-- encerrar 6, definir fechando em desde em vez de desde - 1 1; e com `ate = p_ate - 1` (o último dia deixa de ser
-- inclusivo) o teste ABORTA em perimetro_intervalo_valido depois de reprovar 2 dos 28 asserts. O teste roda duas
-- vezes seguidas no mesmo banco (apaga o próprio caso no início), que era o defeito.
-- =============================================================================

create or replace function public.fn_perimetro_definir_escopo(p_caso_id uuid, p_entidade_id uuid,
                                                                p_escopo text, p_desde date, p_autor text)
RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_caso_da_entidade uuid;
  v_novo_id          uuid;
  v_vig_id           uuid;
  v_vig_desde        date;
begin
  if p_desde is null then
    raise exception 'p_desde não pode ser nulo — todo intervalo de perímetro tem início';
  end if;

  select caso_id into v_caso_da_entidade from entidade where id = p_entidade_id;
  if v_caso_da_entidade is null then
    raise exception 'entidade % não encontrada', p_entidade_id;
  end if;
  if v_caso_da_entidade <> p_caso_id then
    raise exception 'entidade % não pertence ao caso %', p_entidade_id, p_caso_id;
  end if;

  select id, desde into v_vig_id, v_vig_desde
    from perimetro
   where caso_id = p_caso_id and entidade_id = p_entidade_id and escopo = p_escopo
     and ate is null;

  if v_vig_id is not null then
    if v_vig_desde = p_desde then
      return v_vig_id;  -- já vigente desde esta data: nada a gravar (ver o cabeçalho)
    end if;
    if v_vig_desde > p_desde then
      raise exception 'a entidade já está no escopo "%" desde %, depois de %: não dá para começar o escopo antes do intervalo vigente. Para mudar o início, encerre o escopo (fn_perimetro_encerrar_escopo) ou corrija o intervalo por SQL direto.',
        p_escopo, v_vig_desde, p_desde;
    end if;
  end if;

  -- A MUDANÇA de perímetro no meio do mandato: o intervalo anterior GANHA UM FIM, não é sobrescrito.
  update perimetro
     set ate = p_desde - 1
   where caso_id = p_caso_id and entidade_id = p_entidade_id and escopo = p_escopo
     and ate is null;

  insert into perimetro (caso_id, entidade_id, escopo, desde, ate)
  values (p_caso_id, p_entidade_id, p_escopo, p_desde, null)
  returning id into v_novo_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (p_autor, 'perimetro_escopo_definido', 'entidade:' || p_entidade_id,
          jsonb_build_object('caso_id', p_caso_id, 'escopo', p_escopo, 'desde', p_desde));

  return v_novo_id;
end;
$$;

comment on function public.fn_perimetro_definir_escopo(uuid, uuid, text, date, text) IS
  '0180: o caminho de escrita que ABRE intervalo de `perimetro`; fecha o vigente anterior do mesmo (caso, entidade, escopo) com `ate = p_desde - 1` em vez de sobrescrever. 0209: confirmar o mesmo escopo com o MESMO desde é idempotente (devolve o id vigente, sem evento); p_desde ANTERIOR ao desde vigente é exceção em português (antes estourava o check perimetro_intervalo_valido). Grava evento_auditoria (ator = p_autor). Para TIRAR a entidade do escopo, fn_perimetro_encerrar_escopo.';

grant execute on function public.fn_perimetro_definir_escopo(uuid, uuid, text, date, text) to authenticated;

create or replace function public.fn_perimetro_encerrar_escopo(p_caso_id uuid, p_entidade_id uuid,
                                                                 p_escopo text, p_ate date, p_autor text)
RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_id    uuid;
  v_desde date;
begin
  if p_ate is null then
    raise exception 'p_ate não pode ser nulo — informe o último dia em que a entidade ainda está no escopo';
  end if;

  select id, desde into v_id, v_desde
    from perimetro
   where caso_id = p_caso_id and entidade_id = p_entidade_id and escopo = p_escopo
     and ate is null;

  if v_id is null then
    raise exception 'a entidade % não tem intervalo vigente no escopo "%" neste caso: nada a encerrar (ela já foi encerrada, ou o escopo tem outro nome)',
      p_entidade_id, p_escopo;
  end if;
  if p_ate < v_desde then
    raise exception 'o intervalo vigente no escopo "%" começou em %: não dá para encerrá-lo em % (antes do começo)',
      p_escopo, v_desde, p_ate;
  end if;

  update perimetro set ate = p_ate where id = v_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (p_autor, 'perimetro_escopo_encerrado', 'entidade:' || p_entidade_id,
          jsonb_build_object('caso_id', p_caso_id, 'escopo', p_escopo, 'desde', v_desde, 'ate', p_ate));

  return v_id;
end;
$$;

comment on function public.fn_perimetro_encerrar_escopo(uuid, uuid, text, date, text) IS
  '0209: tira a entidade do escopo fechando o intervalo vigente com ate = p_ate (último dia DENTRO, inclusivo), sem abrir outro. Recusa, em português, p_ate antes do desde e a entidade sem intervalo vigente no escopo (um encerramento silencioso afirmaria uma remoção que não houve). Grava evento_auditoria perimetro_escopo_encerrado. Devolve o id do intervalo.';

grant execute on function public.fn_perimetro_encerrar_escopo(uuid, uuid, text, date, text) to authenticated;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('perimetro_encerrar_escopo_funcao', '0209', 'funcao', 'fn_perimetro_encerrar_escopo', null, null,
   'O único caminho para TIRAR uma entidade de um escopo. Ausente, a falta fora_do_perimetro_com_escopo_vigente da 0208 não tem como ser resolvida pela tela.',
   'importante', 894),
  ('perimetro_definir_escopo_idempotente_corpo', '0209', 'corpo', 'fn_perimetro_definir_escopo', 'v_vig_desde', null,
   'Corpo anterior ao desta migration estoura o check perimetro_intervalo_valido quando o analista confirma de novo o mesmo escopo (desde igual ou anterior).',
   'importante', 895)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0209', revisado_em = current_date,
       observacao = 'A 0209 reemite fn_perimetro_definir_escopo (idempotente no mesmo desde, exceção clara no desde anterior) e cria fn_perimetro_encerrar_escopo. Sem tabela nova nem backfill.'
 where id = true;
