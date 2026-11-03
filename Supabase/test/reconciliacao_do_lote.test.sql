-- Testes da RECONCILIAÇÃO DO LOTE (Supabase/migrations/0152).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- POR QUE ESTE TESTE É DE EQUIVALÊNCIA, E NÃO DE TEMPO. A 0152 nasceu de um
-- número de relógio — 1h52 de execução sem gravar nada — mas travar relógio em
-- teste é travar a máquina de quem roda o teste, não o defeito. O que ela
-- promete é outra coisa, e essa dá para provar: **o resultado não muda, e o
-- trabalho repetido some.** Se um dia alguém reintroduzir o cartesiano ou o
-- laço por documento, o resultado continuará igual e só o relógio acusaria —
-- então o que este arquivo trava é o INVARIANTE do qual a economia decorre.
--
-- As propriedades travadas:
--
--   #1  `fn_conflitos_do_caso` devolve EXATAMENTE o mesmo conjunto que a versão
--       0151 (a do produto cartesiano), nas duas fixtures e no caso construído.
--       A 0151 é recriada aqui, byte a byte, como `..._v0151` — é o defeito
--       religado: se a 0152 mudar resposta, este assert reprova nomeando a
--       diferença;
--   #2  o PRÉ-FILTRO `max−min > tolerancia_abs` é conservador: um par que passa
--       raspando no limiar continua sendo achado, e um que fica raspando abaixo
--       continua fora — nos dois casos as duas versões concordam;
--   #3  a DEDUÇÃO POR CHAVE É SEM PERDA: num caso com vários documentos por
--       (entidade, período), a forma do LOTE — árvore por documento (escopo
--       `documento`) mais `fn_reconciliar_caso` uma vez — produz o mesmo
--       CONJUNTO de (tipo, entidade, período, resultado) que a passada
--       documento a documento com escopo `tudo`. As duas metades importam: a
--       primeira versão deste assert comparava só `fn_reconciliar_caso` e
--       reprovou por falta do `secao_fecha` (a árvore), que é intra-documento e
--       continua sendo rodado por documento nas duas formas;
--   #4  …e produz MENOS LINHAS. É a metade que economiza, e é ela que faltava:
--       a passada por documento gravava uma linha idêntica por documento que
--       compartilhava a chave;
--   #4b a GRANULARIDADE da chave é a de cada checagem, não uma para todas. A
--       primeira versão de `fn_reconciliar_caso` usava (entidade, período,
--       tipo) para as oito, e no araucária isso dava 162 chaves para 190
--       documentos — 15% de redução, com a checagem cara saindo de 123 para
--       ~130 chamadas. A suíte teria passado, porque os asserts acima provam
--       equivalência e não custo. Este assert é o que descobre;
--   #5  `p_escopo = 'documento'` roda SÓ a árvore, e `p_escopo` inválido é
--       recusado nomeando as opções;
--   #6  COMPATIBILIDADE: `fn_reconciliar_por_documento(uuid)` de um argumento
--       continua existindo e continua fazendo o que fazia — é a assinatura que
--       o n8n publicado chama hoje, e quebrá-la derrubaria produção;
--   #7  GUARDA DE FIXTURE: o Canastra continua com ZERO conflitos (o mesmo
--       assert da 0151, agora contra a implementação nova).

\set ON_ERROR_STOP on

create or replace function teste_assert_lote(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- O DEFEITO RELIGADO: `fn_conflitos_do_caso` como a 0151 a escreveu.
--
-- Copiada do arquivo da migration 0151, sem uma vírgula de diferença. Ela é a
-- REFERÊNCIA de resposta — a 0152 é uma reescrita de desempenho, e uma
-- reescrita de desempenho que muda resposta é uma mudança de comportamento
-- disfarçada. Este é o jeito de descobrir isso aqui e não em produção.
-- -----------------------------------------------------------------------------
create or replace function fn_conflitos_do_caso_v0151(
  p_caso_id        uuid,
  p_entidade       text    default null,
  p_tolerancia_abs numeric default 100,
  p_tolerancia_pct numeric default 0.005
)
returns table (
  secao_canonica text, chave text, entidade text, exercicio integer,
  documento_vencedor uuid, tipo_vencedor text, valor_vencedor numeric,
  documento_perdedor uuid, tipo_perdedor text, valor_perdedor numeric,
  diferenca numeric, decidido boolean, criterio text
)
language sql stable as $$
  with bruto as (
    select
      ce.secao_canonica,
      fn_normalizar_texto(ce.chave) as rotulo,
      ce.chave,
      coalesce(ce.entidade_coluna,
               case when (select count(distinct ce2.entidade_coluna)
                            from campo_extraido ce2
                           where ce2.documento_versao_id = ce.documento_versao_id
                             and ce2.entidade_coluna is not null) > 1
                    then null else e.razao_social end) as entidade,
      coalesce(fn_exercicio_da_coluna(ce.periodo_coluna),
               fn_exercicio_da_coluna(p.referencia)) as exercicio,
      fn_valor_em_base(ce.valor_num, ce.unidade) as valor,
      d.id as documento_id,
      d.tipo_taxonomia
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d         on d.id = dv.documento_id
    left join entidade e     on e.id = d.entidade_id
    left join periodo p      on p.id = d.periodo_id
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      and dv.id = fn_versao_com_extracao(d.id)
      and ce.secao_canonica is not null
      and ce.secao_canonica <> 'NAO_CLASSIFICAVEL'
      and fn_fator_escala(ce.unidade) is not null
      and fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) = 'conta'
      and coalesce(fn_exercicio_da_coluna(ce.periodo_coluna),
                   fn_exercicio_da_coluna(p.referencia)) is not null
  ),
  filtrado as (
    select * from bruto b
    where b.entidade is not null
      and (p_entidade is null or fn_mesma_entidade(b.entidade, p_entidade))
  ),
  por_documento as (
    select f.secao_canonica, f.rotulo, f.entidade, f.exercicio, f.documento_id,
           max(f.tipo_taxonomia) as tipo,
           (array_agg(f.chave order by length(f.chave)))[1] as chave,
           (array_agg(f.valor order by abs(f.valor) desc nulls last))[1] as valor
    from filtrado f
    group by f.secao_canonica, f.rotulo, f.entidade, f.exercicio, f.documento_id
  ),
  com_autoridade as (
    select pd.*, a.autoridade, a.motivo
    from por_documento pd
    cross join lateral fn_autoridade_do_documento(pd.documento_id) a
  ),
  pares as (
    select
      a.secao_canonica, a.chave, a.entidade, a.exercicio,
      a.documento_id as doc_a, a.tipo as tipo_a, a.valor as valor_a,
      a.autoridade as aut_a, a.motivo as motivo_a,
      b.documento_id as doc_b, b.tipo as tipo_b, b.valor as valor_b,
      b.autoridade as aut_b, b.motivo as motivo_b
    from com_autoridade a
    join com_autoridade b
      on b.secao_canonica = a.secao_canonica
     and b.rotulo         = a.rotulo
     and b.entidade       is not distinct from a.entidade
     and b.exercicio      = a.exercicio
     and b.documento_id   > a.documento_id
    where abs(a.valor - b.valor)
            > greatest(p_tolerancia_abs, abs(a.valor) * p_tolerancia_pct)
  )
  select
    p.secao_canonica, p.chave, p.entidade, p.exercicio,
    case when p.aut_a >= p.aut_b then p.doc_a   else p.doc_b   end,
    case when p.aut_a >= p.aut_b then p.tipo_a  else p.tipo_b  end,
    case when p.aut_a >= p.aut_b then p.valor_a else p.valor_b end,
    case when p.aut_a >= p.aut_b then p.doc_b   else p.doc_a   end,
    case when p.aut_a >= p.aut_b then p.tipo_b  else p.tipo_a  end,
    case when p.aut_a >= p.aut_b then p.valor_b else p.valor_a end,
    abs(p.valor_a - p.valor_b),
    p.aut_a <> p.aut_b,
    case when p.aut_a <> p.aut_b then
      format('%s vence: %s (autoridade %s) contra %s (autoridade %s)',
             case when p.aut_a > p.aut_b then p.tipo_a else p.tipo_b end,
             case when p.aut_a > p.aut_b then p.motivo_a else p.motivo_b end,
             greatest(p.aut_a, p.aut_b),
             case when p.aut_a > p.aut_b then p.motivo_b else p.motivo_a end,
             least(p.aut_a, p.aut_b))
    else
      format('EMPATE em autoridade %s (%s × %s): a escolha é humana — o valor '
             || 'não foi trocado, continua o de maior módulo',
             p.aut_a, p.motivo_a, p.motivo_b)
    end
  from pares p;
$$;
-- 0217: a sonda `anon_sem_funcoes` varre toda função de public sem prefixo `teste_`, e esta é do harness (a 0151 recriada). Sem EXECUTE para PUBLIC,
-- como toda função que uma migration cria passou a fazer.
revoke all on function fn_conflitos_do_caso_v0151(uuid, text, numeric, numeric) from public;

-- Comparador: as duas versões devolvem o MESMO conjunto? Devolve a primeira
-- diferença por extenso, para o assert poder dizer qual linha discorda em vez
-- de dizer "diferente".
create or replace function teste_diferenca_conflitos(p_caso_id uuid, p_entidade text default null)
returns text language sql stable as $$
  with nova  as (select * from fn_conflitos_do_caso(p_caso_id, p_entidade)),
       velha as (select * from fn_conflitos_do_caso_v0151(p_caso_id, p_entidade)),
       so_na_nova  as (select * from nova  except all select * from velha),
       so_na_velha as (select * from velha except all select * from nova)
  select case
    when not exists (select 1 from so_na_nova) and not exists (select 1 from so_na_velha)
      then null
    else format('só na 0152: %s | só na 0151: %s',
                coalesce((select string_agg(format('%s/%s=%s', chave, exercicio, diferenca), '; ')
                          from so_na_nova), '—'),
                coalesce((select string_agg(format('%s/%s=%s', chave, exercicio, diferenca), '; ')
                          from so_na_velha), '—'))
  end;
$$;

do $$
declare
  v_caso    uuid;
  v_caso2   uuid;
  v_r       jsonb;
  v_ver     uuid;
  v_dif     text;
  v_n_caso  int;
  v_n_doc   int;
  v_set_caso   text;
  v_set_doc    text;
  v_doc     uuid;
  v_erro    text;
  v_chk     jsonb;
begin
  -- ===========================================================================
  raise notice '--- 1. A 0152 DEVOLVE O MESMO QUE A 0151 (o defeito religado) ---';
  -- ===========================================================================
  --
  -- Primeiro no caso construído, que é o único com conflito de verdade — as
  -- duas fixtures devolvem vazio, e comparar vazio com vazio não prova nada.
  v_caso := (fn_upsert_caso('Caso 0152 — equivalência do conflito'))::uuid;

  v_r := fn_registrar_documento(
    v_caso, 'Araucaria Serraria Ltda', 'anual', '2025', 'DF_AUDITADA', 0.9, 'nome_arquivo',
    'supabase_storage', 'b/df-2025.pdf', 'Demonstracoes Financeiras Auditadas 2025.pdf',
    true, 'HASH-152-DF', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Clientes", "valor_num": "10000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"},
    {"chave": "Estoques", "valor_num": "5000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"}
  ]'::jsonb, 'N0');

  v_r := fn_registrar_documento(
    v_caso, 'Araucaria Serraria Ltda', 'anual', '2025', 'COMBINADO', 0.9, 'nome_arquivo',
    'supabase_storage', 'b/comb-2025.pdf', 'Combinado do grupo PRELIMINAR 2025.xlsx',
    false, 'HASH-152-COMB', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Clientes", "valor_num": "42800", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"},
    {"chave": "Estoques", "valor_num": "5000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"}
  ]'::jsonb, 'N0');

  -- PRÉ-CONDIÇÃO: sem conflito achado, comparar as duas versões não mede nada.
  select count(*) into v_n_caso from fn_conflitos_do_caso(v_caso);
  perform teste_assert_lote(v_n_caso >= 1,
    'PRÉ-CONDIÇÃO: o caso construído tem conflito para as duas versões acharem',
    format('conflitos = %s', v_n_caso));

  v_dif := teste_diferenca_conflitos(v_caso);
  perform teste_assert_lote(v_dif is null,
    'no caso construído, 0152 e 0151 devolvem o MESMO conjunto', v_dif);

  -- E `Estoques`, que bate nos dois documentos, continua FORA das duas.
  perform teste_assert_lote(
    not exists (select 1 from fn_conflitos_do_caso(v_caso) where chave = 'Estoques'),
    'a conta que os dois documentos dizem igual não vira conflito');

  -- ===========================================================================
  raise notice '--- 2. O PRÉ-FILTRO É CONSERVADOR NO LIMIAR ---';
  -- ===========================================================================
  --
  -- A 0152 pré-filtra os grupos por `max−min > tolerancia_abs` antes de formar
  -- par. O argumento de que isso é seguro está no cabeçalho da migration; aqui
  -- ele é MEDIDO nos dois lados da borda, que é onde um pré-filtro erra.
  --
  -- Tolerância: greatest(100, |a| * 0,005). Em valores na BASE (milhar × 1000).
  -- Base 1.000.000: o limiar é greatest(100, 5.000) = 5.000.
  --   • diferença de 6.000 na base → PASSA nas duas
  --   • diferença de 4.000 na base → FICA FORA nas duas (mas max−min = 4.000 >
  --     100, então o pré-filtro NÃO a descarta: quem descarta é o predicado
  --     completo, como tem de ser)
  v_caso2 := (fn_upsert_caso('Caso 0152 — a borda da tolerância'))::uuid;

  v_r := fn_registrar_documento(
    v_caso2, 'Empresa da Borda Ltda', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'b/borda-bp.pdf', 'Balanco 2025.pdf', true, 'HASH-152-B1', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Acima do limiar", "valor_num": "1000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"},
    {"chave": "Abaixo do limiar", "valor_num": "1000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"}
  ]'::jsonb, 'N0');

  v_r := fn_registrar_documento(
    v_caso2, 'Empresa da Borda Ltda', 'anual', '2025', 'BALANCETE', 0.9, 'nome_arquivo',
    'supabase_storage', 'b/borda-bal.pdf', 'Balancete 2025.pdf', true, 'HASH-152-B2', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Acima do limiar", "valor_num": "1006", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"},
    {"chave": "Abaixo do limiar", "valor_num": "1004", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"}
  ]'::jsonb, 'N0');

  perform teste_assert_lote(
    exists (select 1 from fn_conflitos_do_caso(v_caso2) where chave = 'Acima do limiar'),
    'diferença de 6.000 na base (limiar 5.000) é achada');
  perform teste_assert_lote(
    not exists (select 1 from fn_conflitos_do_caso(v_caso2) where chave = 'Abaixo do limiar'),
    'diferença de 4.000 na base (limiar 5.000) fica fora — quem descarta é o predicado, não o pré-filtro');

  v_dif := teste_diferenca_conflitos(v_caso2);
  perform teste_assert_lote(v_dif is null,
    'nos DOIS lados da borda, 0152 e 0151 concordam', v_dif);

  -- ===========================================================================
  raise notice '--- 3. A DEDUÇÃO POR CHAVE É SEM PERDA ---';
  -- ===========================================================================
  --
  -- O caso do araucária, em miniatura e com o mesmo formato: VÁRIOS documentos
  -- na MESMA (entidade, período). Lá eram 80 documentos da Araucária Serraria;
  -- aqui bastam três do mesmo tipo, porque o que se mede é se a chave repetida
  -- produz achado novo (não produz) ou linha repetida (produzia).
  for v_n_doc in 1..3 loop
    v_r := fn_registrar_documento(
      v_caso, 'Araucaria Serraria Ltda', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
      'supabase_storage', format('b/bp-repetido-%s.pdf', v_n_doc),
      format('Balanco Patrimonial 2025 parte %s.pdf', v_n_doc),
      true, format('HASH-152-REP-%s', v_n_doc), 'ok');
    v_ver := (v_r->>'documento_versao_id')::uuid;
    perform fn_registrar_campos_extraidos(v_ver, format('[
      {"chave": "Caixa e equivalentes", "valor_num": "%s", "unidade": "milhar",
       "confianca": "0.9", "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"}
    ]', 700 + v_n_doc)::jsonb, 'N0');
  end loop;

  -- Passada A: documento a documento, como o despachante faz hoje.
  delete from reconciliacao where caso_id = v_caso;
  for v_doc in select id from documento where caso_id = v_caso order by criado_em, id loop
    perform fn_reconciliar_por_documento(v_doc);
  end loop;
  select count(*) into v_n_doc from reconciliacao where caso_id = v_caso;
  select string_agg(x, '|' order by x) into v_set_doc from (
    select distinct format('%s/%s/%s/%s', tipo,
                           coalesce(entidade_id::text, '-'),
                           coalesce(periodo_id::text, '-'), resultado) as x
    from reconciliacao where caso_id = v_caso) t;

  -- Passada B: como o LOTE passa a fazer — a árvore por documento (escopo
  -- `documento`) mais as chaves UMA vez. Comparar `fn_reconciliar_caso` sozinha
  -- contra a passada `tudo` seria comparar coisas diferentes: a árvore é
  -- intra-documento e continua sendo rodada por documento nas duas formas. Foi
  -- o que este assert pegou na primeira vez que rodou, e a diferença era o
  -- `secao_fecha` (a árvore) faltando de um lado.
  delete from reconciliacao where caso_id = v_caso;
  for v_doc in select id from documento where caso_id = v_caso order by criado_em, id loop
    perform fn_reconciliar_por_documento(v_doc, 'documento');
  end loop;
  v_chk := fn_reconciliar_caso(v_caso);
  select count(*) into v_n_caso from reconciliacao where caso_id = v_caso;
  select string_agg(x, '|' order by x) into v_set_caso from (
    select distinct format('%s/%s/%s/%s', tipo,
                           coalesce(entidade_id::text, '-'),
                           coalesce(periodo_id::text, '-'), resultado) as x
    from reconciliacao where caso_id = v_caso) t;

  -- PRÉ-CONDIÇÃO: se as duas passadas não gravaram nada, comparar não mede nada.
  perform teste_assert_lote(v_n_doc > 0 and v_n_caso > 0,
    'PRÉ-CONDIÇÃO: as duas passadas gravam reconciliação',
    format('por documento = %s, por chave = %s', v_n_doc, v_n_caso));

  perform teste_assert_lote(v_set_caso is not distinct from v_set_doc,
    'o CONJUNTO de (tipo, entidade, período, resultado) é o mesmo nas duas passadas',
    format('por chave: %s%s   por documento: %s', v_set_caso, chr(10), v_set_doc));

  -- ===========================================================================
  raise notice '--- 4. …E POR CHAVE GRAVA MENOS LINHAS (a economia) ---';
  -- ===========================================================================
  perform teste_assert_lote(v_n_caso < v_n_doc,
    'a passada por chave grava MENOS linhas que a por documento, com o mesmo conjunto',
    format('por chave = %s, por documento = %s — se forem iguais, a dedução não está acontecendo',
           v_n_caso, v_n_doc));

  -- "MENOS CHAMADAS QUE DOCUMENTOS" NÃO É PROPRIEDADE, e este assert existiu
  -- errado por uma rodada: são OITO checagens, então um caso pequeno tem mais
  -- chamadas que documentos por construção (medido: 6 para 5 documentos). O que
  -- vale é a GRANULARIDADE, logo abaixo — e é ela que separa a correção de
  -- verdade da que só troca o código de lugar.
  perform teste_assert_lote((v_chk->>'chamadas') is not null,
    'fn_reconciliar_caso declara quantas chamadas fez',
    format('chamadas = %s, documentos = %s', v_chk->>'chamadas', v_chk->>'documentos'));

  -- ===========================================================================
  raise notice '--- 4b. A GRANULARIDADE DA CHAVE — o erro que eu cometi primeiro ---';
  -- ===========================================================================
  --
  -- A PRIMEIRA VERSÃO de `fn_reconciliar_caso` iterava (entidade, período,
  -- tipo): uma chave só para as oito checagens. Medido no araucária, isso dava
  -- **162 chaves para 190 documentos** — 15% de redução — e a checagem cara
  -- (`fn_reconciliar_versoes_do_periodo`, 1,8 s) sairia de 123 chamadas para
  -- ~130. Eu teria trocado o código sem corrigir o defeito, E A SUÍTE TERIA
  -- PASSADO: os asserts acima provam EQUIVALÊNCIA e "menos linhas", não custo.
  --
  -- O que trava isso é a granularidade: `fn_reconciliar_versoes_do_periodo` e
  -- `fn_reconciliar_duplicidade` recebem só (caso, ENTIDADE). Num caso com N
  -- documentos da MESMA entidade em períodos e tipos diferentes, elas têm de
  -- rodar UMA vez — e é isso que se conta aqui, pelas linhas que elas gravam.
  select count(*) into v_n_caso from reconciliacao
   where caso_id = v_caso and tipo = 'conflito_entre_documentos';
  select count(distinct entidade_id) into v_n_doc from documento where caso_id = v_caso;
  perform teste_assert_lote(v_n_caso <= v_n_doc,
    'a checagem por ENTIDADE grava no máximo uma linha por entidade — não uma por (entidade, período, tipo)',
    format('%s linha(s) de conflito para %s entidade(s); com a chave errada seriam '
           || 'tantas quantos (entidade, período, tipo) distintos', v_n_caso, v_n_doc));

  select count(*) into v_n_caso from reconciliacao
   where caso_id = v_caso and tipo = 'duplicidade_de_rotulo';
  perform teste_assert_lote(v_n_caso <= v_n_doc,
    'e a de duplicidade também — ela lê (caso, entidade) e mais nada',
    format('%s linha(s) para %s entidade(s)', v_n_caso, v_n_doc));

  -- ===========================================================================
  raise notice '--- 5. O ESCOPO É DECLARADO, E O INVÁLIDO É RECUSADO ---';
  -- ===========================================================================
  select id into v_doc from documento
   where caso_id = v_caso and tipo_taxonomia = 'BALANCO' order by criado_em limit 1;

  delete from reconciliacao where caso_id = v_caso;
  v_chk := fn_reconciliar_por_documento(v_doc, 'documento');
  select count(*) into v_n_doc from reconciliacao where caso_id = v_caso;
  perform teste_assert_lote(
    v_n_doc = 1 and (select tipo from reconciliacao where caso_id = v_caso limit 1) = 'secao_fecha',
    'escopo `documento` roda SÓ a árvore (a única checagem que é do documento)',
    format('gravou %s linha(s): %s', v_n_doc,
           (select string_agg(distinct tipo, ', ') from reconciliacao where caso_id = v_caso)));

  begin
    perform fn_reconciliar_por_documento(v_doc, 'caso');
    perform teste_assert_lote(false, 'escopo inválido é recusado', 'não levantou exceção');
  exception when others then
    v_erro := SQLERRM;
    perform teste_assert_lote(v_erro like '%escopo inválido%' and v_erro like '%fn_reconciliar_caso%',
      'escopo inválido é recusado nomeando as opções e para onde ir', v_erro);
  end;

  -- ===========================================================================
  raise notice '--- 6. COMPATIBILIDADE: o 1-argumento que o n8n publicado chama ---';
  -- ===========================================================================
  --
  -- O workflow em produção chama `select fn_reconciliar_por_documento($1::uuid)`.
  -- A 0152 derruba a função de um argumento e recria com default — se o default
  -- não pegar, produção quebra no primeiro documento e este assert é o que
  -- descobre isso aqui.
  delete from reconciliacao where caso_id = v_caso;
  v_chk := fn_reconciliar_por_documento(v_doc);
  perform teste_assert_lote((v_chk->>'escopo') = 'tudo',
    'a chamada de UM argumento continua existindo e cai no escopo `tudo`',
    coalesce(v_chk->>'escopo', 'sem chave escopo'));
  select count(*) into v_n_doc from reconciliacao where caso_id = v_caso;
  perform teste_assert_lote(v_n_doc > 1,
    'e ela continua rodando as checagens de chave, como antes da 0152',
    format('gravou %s linha(s) — 1 seria só a árvore', v_n_doc));

  -- ===========================================================================
  raise notice '--- 7. GUARDA DE FIXTURE: o Canastra continua com ZERO conflitos ---';
  -- ===========================================================================
  --
  -- O mesmo assert da 0151, agora contra a implementação nova. Ele é a rede
  -- contra afrouxar um dos três filtros sem perceber — e contra a 0152 ter
  -- mudado resposta num dado real, que é diferente de mudar num caso montado.
  select count(*) into v_n_caso
    from fn_conflitos_do_caso((select id from caso where nome = 'Book Canastra'));
  perform teste_assert_lote(v_n_caso = 0,
    'o Canastra continua devolvendo ZERO conflitos com a implementação da 0152',
    format('devolveu %s', v_n_caso));

  v_dif := teste_diferenca_conflitos((select id from caso where nome = 'Book Canastra'));
  perform teste_assert_lote(v_dif is null,
    'e concorda com a 0151 no book inteiro (28 documentos, extração real)', v_dif);

  -- ===========================================================================
  raise notice '--- 8. AS BORDAS: caso vazio e documento inexistente ---';
  -- ===========================================================================
  --
  -- `fn_reconciliar_caso` roda no FIM do lote, e o lote pode ter sido recusado
  -- pelo orçamento antes de registrar documento nenhum. Um erro aqui derrubaria
  -- a cauda do workflow num caso em que não há nada a reconciliar.
  v_chk := fn_reconciliar_caso((fn_upsert_caso('Caso 0152 — vazio'))::uuid);
  perform teste_assert_lote((v_chk->>'executado')::boolean
                        and (v_chk->>'chamadas')::int = 0,
    'caso sem documento nenhum devolve executado com zero chamadas, sem erro', v_chk::text);

  v_chk := fn_reconciliar_por_documento('00000000-0000-0000-0000-000000000000'::uuid);
  perform teste_assert_lote((v_chk->>'executado')::boolean = false,
    'documento inexistente devolve executado=false, sem erro', v_chk::text);

  raise notice 'reconciliacao_do_lote OK — equivalência com a 0151 nas duas pontas da borda, '
               'dedução por chave sem perda e com menos linhas, escopo declarado, 1-argumento vivo';
end $$;
