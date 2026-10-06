-- =============================================================================
-- 0200 — O BALANCETE SEMESTRAL QUE ENTRAVA POR CIMA DO BALANÇO ANUAL, CONTA A CONTA
--
-- O DEFEITO (medido em PRODUÇÃO, 05/10/2026, depois de aplicar a 0199; caso "Fw Valtra" 03a66ab6).
-- A 0199 decide "o período parcial só vale quando NÃO HÁ ocorrência anual" POR RÓTULO — e o rótulo
-- do balancete não é o do balanço. O BALANCETE semestral (01/01–30/06/2025) traz CENTENAS de contas
-- analíticas com o código no rótulo ("12388 1.1.5.01.007 TRANSFERENCIA DE MERCADORIAS TRATORES"…);
-- o BALANCO anual traz as contas SINTÉTICAS. Nenhum rótulo analítico existe no balanço, então para
-- CADA UM o balancete é a "única fonte" e entra: o Saldo Anterior de 01/01/2025 vira 2024 e o Saldo
-- Atual de 30/06 vira 2025, POR CIMA das contas do balanço anual do mesmo ano. A soma das contas do
-- modelo passa do ativo circulante informado — dupla contagem. Resíduo de reconciliação do ATIVO
-- CIRCULANTE no export: -36.014.142 em 2024 (103,5% do ativo total) e -46.902.843 em 2025 (121,9%).
-- Com a consulta local que EXCLUÍA o tipo BALANCETE o resíduo era 2,42 mi (2022) / 3,75 mi (2025).
--
-- A REGRA (comportamento, não mecanismo; muda só a alínea (c) da 0199):
--
--   c'. UMA OCORRÊNCIA DE PERÍODO PARCIAL PARA O ANO Y SÓ É ELEGÍVEL SE NÃO EXISTIR, PARA A MESMA
--       ENTIDADE E O MESMO ANO Y, NENHUMA OCORRÊNCIA ANUAL DA MESMA FAMÍLIA DE DEMONSTRAÇÃO. A decisão
--       é do ANO, não do rótulo: balancete semestral não contribui para um ano que tem balanço
--       anual, e continua contribuindo (as contas analíticas inclusive) para o ano em que ele é a
--       única fonte patrimonial.
--
--   FAMÍLIA, decidida pela `secao_canonica` (a seção, não o tipo de documento: o BALANCETE traz
--   contas patrimoniais E de resultado, e o ano pode ter balanço anual mas só DRE semestral):
--       patrimonial  ativo_*, passivo_*, patrimonio_liquido
--       resultado    receita_bruta, custos, despesas_operacionais, resultado_financeiro, impostos_lucro
--       fluxo        atividades_*
--       as demais    (NULL, dmpl, dva, NAO_CLASSIFICAVEL, seção futura) são família PRÓPRIA, uma
--                    por valor — NULL é a família "sem seção". Ano que só tem anual de OUTRA família
--                    não tira o parcial: um balanço anual não prova que a DRE do ano exista.
--   "ANUAL" é a mesma definição da 0199 (nem tipo BALANCETE, nem mês/trimestre/data-base não-31/12,
--   nem intervalo de datas que não é 01/01–31/12). Conta como anual a ocorrência já PROJETADA no ano:
--   o Saldo Inicial do BALANCO 2025 é o fechamento de 2024 e, sendo de documento anual, cobre 2024.
--   A abertura (Saldo Anterior) do balancete 2025 cai em 2024; se 2024 tem balanço anual, fica fora.
--   ENTIDADE: com `p_entidade` informado a consulta já é de uma entidade só; sem ele, a chave é o nome
--   normalizado da coluna/entidade do documento (a série sem filtro já mistura entidades por rótulo —
--   esta chave só impede que o anual de uma entidade esconda o parcial de outra).
--
--   COM A c' A CHAVE "anual antes de parcial" DA ORDENAÇÃO DA 0199 FICOU MORTA e foi retirada: dentro
--   de um (rótulo, seção, ano) a família é constante, então um parcial nunca compete com um anual —
--   ou o ano tem anual (o parcial já saiu) ou não tem (só há parcial). A c da 0199 está inteira dentro
--   da c'. `n_ocorrencias` passa a contar só as ocorrências elegíveis, como sempre quis dizer.
--
--   TETO CONHECIDO: a família é uma lista de prefixos de `secao_canonica`; seção que o extrator passe
--   a emitir fora dela vira família própria (o parcial dela entra mesmo com anual de seção irmã).
--   E o ano com balanço anual SÓ de algumas contas esconde as contas analíticas do balancete que o
--   balanço não traz — é exatamente o pedido (o balanço anual é a fonte do ano), e a diferença se
--   vê na reconciliação, não aqui.
--
-- ASSINATURA E COLUNAS DE RETORNO IGUAIS às da 0199; `create or replace` basta. REEMITIDA INTEIRA.
-- CHAMADORES: os da 0199 (export via rpc, gerar-export-do-banco, verificar-export, Verificação/run e
-- variacoes, proveniencia.test.sql) — todos leem a série (rótulo, seção, ano, valor).
--
-- NÃO FAZ: não roda recompute nem regrava modelagem de caso nenhum (o modelo muda no PRÓXIMO export);
-- não é aplicada por estar escrita — quem responde é a sonda contra o banco em que se está conectado:
--
--   select chave, migration, tipo, objeto, presente, detalhe, porque
--     from fn_instalacao_conferir() where not presente order by 1;
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/serie_por_ano_balancete_sob_balanco_anual.test.sql —
-- 17 asserts; com a alínea c' desligada (`where true` no lugar do filtro) reprovam 6; com a regra
-- ao contrário (parcial NUNCA entra) reprovam 10 — os dois lados do filtro estão medidos. Dos 21
-- asserts de serie_por_ano_movimento_e_abertura.test.sql, 3 mudaram de valor esperado, e é o
-- comportamento certo: CAIXA GERAL 2024 e 2025 (conta só do balancete, mas 2024 e 2025 têm balanço
-- anual: agora ausente, antes 1.000.000/1.200.000) e `n_ocorrencias` do ATIVO 2025 (2 -> 1: o Saldo
-- Atual do balancete parcial deixou de ser ocorrência elegível). O "parcial entra quando é a única
-- fonte" que aqueles dois asserts mediam passou a ser medido no teste novo, no ano 2026.
-- =============================================================================

create or replace function fn_valores_por_ano(p_caso_id uuid, p_entidade text default null)
returns table (
  rotulo_norm    text,
  secao_canonica text,
  ano            int,
  valor          numeric,
  n_ocorrencias  bigint,
  arquivo        text,
  origem_pagina  int,
  confianca      numeric,
  status_aceite  text,
  aceito_por     text
)
language sql
stable
as $$
  -- marca-0125
  -- marca-0200
  with ocorrencias as materialized (
    select
      fn_normalizar_texto(ce.chave) as rotulo_norm,
      ce.secao_canonica,
      -- 0199 (b): a coluna de ABERTURA é o fechamento do ano ANTERIOR ao do documento.
      fn_ano_da_coluna(ce.periodo_coluna, p.referencia)
        - (case when coalesce(ce.periodo_coluna, '') ~* '^\s*saldo\s+(inicial|anterior)\s*$'
                then 1 else 0 end) as ano,
      (coalesce(ce.periodo_coluna, '') ~* '^\s*saldo\s+(inicial|anterior)\s*$') as abertura,
      -- 0199 (c): o saldo de um documento de período PARCIAL só vale na falta do anual.
      -- Uma coluna que traz 31/12 explícito é fim de ano mesmo num documento parcial.
      (coalesce(ce.periodo_coluna, '') !~ '(31/12|12/31|-12-31)'
       and (   d.tipo_taxonomia = 'BALANCETE'
            or p.tipo in ('mes', 'trimestre')
            or (p.tipo = 'data-base' and coalesce(p.referencia, '') !~ '(31/12|12/31|-12-31)')
            or coalesce(p.referencia, '') ~* '^\s*[1-4]\s*t\s*\d{2,4}\s*$'
            or coalesce(p.referencia, '') ~ '^\s*(0?[1-9]|1[01])/(19|20)\d{2}\s*$'
            or coalesce(p.referencia, '') ~ '^\s*(19|20)\d{2}-(0[1-9]|1[01])\s*$'
            or (coalesce(p.referencia, '') ~* '\d{1,2}/\d{1,2}/(19|20)\d{2}\s*(-|–|—|a|à|até|ate)\s*\d{1,2}/\d{1,2}/(19|20)\d{2}'
                and coalesce(p.referencia, '') !~ '^\s*0?1/0?1/(19|20)\d{2}\s*(-|–|—|a|à|até|ate)\s*31/12/(19|20)\d{2}\s*$')
           )) as parcial,
      -- 0200: a FAMÍLIA da demonstração e a ENTIDADE, para decidir o parcial por ano e não por rótulo.
      case when ce.secao_canonica ~ '^(ativo|passivo)(_|$)' or ce.secao_canonica = 'patrimonio_liquido'
                then 'patrimonial'
           when ce.secao_canonica in ('receita_bruta', 'custos', 'despesas_operacionais',
                                      'resultado_financeiro', 'impostos_lucro')
                then 'resultado'
           when ce.secao_canonica ~ '^atividades_' then 'fluxo'
           else coalesce(ce.secao_canonica, '')   -- NULL, dmpl, dva, NAO_CLASSIFICAVEL: família própria
      end as familia,
      case when p_entidade is not null then ''   -- a consulta já é de UMA entidade
           else fn_normalizar_texto(coalesce(ce.entidade_coluna, e.razao_social, '')) end as entidade_chave,
      ce.valor_num as valor,
      dv.nome_original as arquivo,
      ce.origem_pagina,
      ce.confianca,
      ce.status_aceite,
      ce.aceito_por,
      ce.ordem
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    left join periodo p on p.id = d.periodo_id
    left join entidade e on e.id = d.entidade_id
    left join taxonomia_tipo_documento t on t.codigo = d.tipo_taxonomia
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      and (p_entidade is null
           or fn_mesma_entidade(coalesce(ce.entidade_coluna, e.razao_social, ''), p_entidade))
      and dv.id = fn_versao_com_extracao(d.id)
      -- 0199 (d): documento que não é demonstração não tem saldo (quotas, % de participação).
      and coalesce(t.categoria, '') not in ('Societário/Legal', 'Garantias/Sócios')
      -- 0199 (a): movimento do período (Débito/Crédito) nunca é saldo.
      and coalesce(ce.periodo_coluna, '') !~* '^\s*(d[ée]bito|cr[ée]dito)s?\s*$'
  ),
  -- 0200: a decisão "parcial entra se for a única fonte" é do ANO (da entidade e da família da
  -- demonstração), não do rótulo. Um balancete semestral traz centenas de contas analíticas que o
  -- balanço anual (sintético) não tem; para cada rótulo o balancete era a "única fonte" e entrava
  -- POR CIMA das contas do balanço do mesmo ano.
  elegiveis as (
    select o.*,
           bool_or(not coalesce(o.parcial, false)) over (partition by o.entidade_chave, o.familia, o.ano) as ano_tem_anual
    from ocorrencias o
    where o.ano is not null
  ),
  escolhido as (
    select
      o.rotulo_norm, o.secao_canonica, o.ano, o.valor,
      -- quantas ocorrências elegíveis o (rótulo, seção, ano) tem, incluindo as que perderam
      count(*) over (partition by o.rotulo_norm, o.secao_canonica, o.ano) as n_ocorrencias,
      o.arquivo, o.origem_pagina, o.confianca, o.status_aceite, o.aceito_por,
      row_number() over (
        partition by o.rotulo_norm, o.secao_canonica, o.ano
        order by o.abertura,           -- (b) fechamento antes de abertura
                 abs(o.valor) desc,    -- maior módulo COM SINAL, a regra da 0042
                 o.valor desc,         -- (e) empate de módulo com sinais opostos: o positivo
                 o.confianca desc nulls last,
                 o.origem_pagina asc nulls last,
                 o.arquivo,
                 o.ordem
      ) as rn
    from elegiveis o
    -- 0200: parcial só vale num ano em que a família não tem NENHUMA ocorrência anual
    where not (coalesce(o.parcial, false) and o.ano_tem_anual)
  )
  select rotulo_norm, secao_canonica, ano, valor, n_ocorrencias,
         arquivo, origem_pagina, confianca, status_aceite, aceito_por
  from escolhido
  where rn = 1
  order by rotulo_norm, ano;
$$;

comment on function fn_valores_por_ano(uuid, text) is
  'Série histórica por (rótulo, seção, ano), só da versão vigente (0102), com a proveniência DA CÉLULA (0125). 0199: coluna de movimento (Débito/Crédito) nunca é saldo; "Saldo Inicial"/"Saldo Anterior" é o fechamento do ano ANTERIOR e perde para o fechamento do mesmo ano; tipo de categoria Societário/Legal e Garantias/Sócios não entra. 0200: ocorrência de período PARCIAL (balancete, mês, trimestre, intervalo) só entra num ano em que a entidade não tem NENHUMA ocorrência anual da mesma família (patrimonial / resultado / fluxo / seção própria) — decisão do ANO, não do rótulo. Dentro da camada, maior módulo com sinal (0042); desempate determinístico.';

grant execute on function fn_valores_por_ano(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Catálogo da sonda — requisito de CORPO (marcador é código, não comentário).
-- ORDEM 856: a 0199 usa 855.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, porque, severidade, ordem) values
  ('serie_por_ano_parcial_so_sem_anual_do_ano', '0200', 'corpo', 'fn_valores_por_ano',
   'ano_tem_anual',
   'Sem este corpo o balancete semestral entra POR CIMA do balanço anual: a decisão "parcial entra se for a única '
   'fonte" é por rótulo, e as centenas de contas analíticas do balancete (código no rótulo) não existem no balanço. '
   'MEDIDO EM PRODUÇÃO (05/10/2026, depois da 0199, Fw Valtra 03a66ab6): resíduo de reconciliação do ATIVO CIRCULANTE '
   'de -36.014.142 em 2024 (103,5% do ativo) e -46.902.843 em 2025 (121,9%) — dupla contagem.',
   'importante', 856)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, porque = excluded.porque,
      severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0200', revisado_em = current_date,
       observacao = 'A 0200 reemite fn_valores_por_ano: o período parcial (balancete etc.) só entra num ano em que a '
         'entidade não tem ocorrência ANUAL da mesma família de demonstração (decisão do ano, não do rótulo). '
         'Medido em produção (05/10/2026, só-leitura, Fw Valtra). Catalogada pelo corpo '
         '(serie_por_ano_parcial_so_sem_anual_do_ano); a assinatura não muda.'
 where id = true;
