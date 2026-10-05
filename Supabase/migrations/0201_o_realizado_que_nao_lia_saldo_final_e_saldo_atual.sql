-- =============================================================================
-- 0201 — O REALIZADO QUE NÃO LIA "SALDO FINAL" NEM "SALDO ATUAL"
--
-- O DEFEITO (medido em PRODUÇÃO, 05/10/2026, depois da 0200; caso "Fw Valtra" 03a66ab6, empresa MOTO
-- AGRICOLA VOLKWEIS LTDA). `fn_linhas_do_realizado(caso, entidade)` (0150/0151) devolvia só as linhas
-- do DFC (entidade "Metodo Indireto Moto Agricola") e NENHUMA linha do BALANCO nem da DRE. A tela de
-- modelagem mostrava TODAS as sugestões do realizado vazias — CUSTO_VARIAVEL, SGA_PCT, PMR, PME, PMP,
-- ALIQUOTA, PARCELA_ONEROSA, TAXA_DIVIDA — e o analista via "sem dado" onde o caso tem três anos de
-- balanço e de DRE (regra 1: a ausência era do filtro, não do documento).
--
-- A CAUSA, medida: o exercício da linha era `fn_exercicio_da_coluna(periodo_coluna)` (0150), que só
-- acha um ano de quatro dígitos DENTRO DO TEXTO da coluna. O documento anual deste caso rotula as
-- colunas "Saldo Inicial" / "Saldo Final" (BALANCO, referência "2025") e "Saldo anterior" / "Saldo
-- atual" (DRE, referência "2025") — nenhuma traz ano. `fn_exercicio_da_coluna` devolve NULL, a linha
-- cai em `and fn_exercicio_da_coluna(...) is not null` e o documento anual INTEIRO fica fora. A 0199 e
-- a 0200 ensinaram `fn_valores_por_ano` a ler esse arranjo; a 0150 nunca soube, e as duas funções
-- descreviam o MESMO documento de formas diferentes (a série do export enxergava o balanço, as
-- premissas do realizado não).
--
-- A REGRA (a mesma da 0199/0200; o que muda é QUEM a aplica):
--
--   a. MOVIMENTO (Débito/Crédito) NUNCA É SALDO. (Aqui já valia: a coluna não tem ano nem nome de saldo,
--      logo não tem exercício. O teste a trava como controle.)
--   b. FECHAMENTO = o ano da referência do documento ("Saldo Final", "Saldo atual"); ABERTURA = ano - 1
--      ("Saldo Inicial", "Saldo anterior"), e a abertura PERDE para o fechamento do mesmo (conta,
--      seção, exercício) — antes da autoridade documental e do maior módulo.
--   c'. PARCIAL SÓ SEM ANUAL DA MESMA FAMÍLIA (patrimonial / resultado / fluxo / seção própria), por
--      entidade e exercício.
--   d. Documento de categoria 'Societário/Legal' ou 'Garantias/Sócios' não entra (quotas não são saldo).
--
--   COLUNA COM ANO NO TEXTO ("2024", "31/12/2024") CONTINUA LENDO O ANO DO TEXTO, e a coluna sem ano
--   e sem nome de saldo ("Saldo", "Valor", "Ticket médio (R$)", "Faturamento (R$)") CONTINUA FORA — é
--   a decisão da 0150 (dimensão da tabela não é exercício), e a referência do documento só empresta o
--   ano às quatro colunas que NOMEIAM um saldo (final, atual, inicial, anterior). `fn_valores_por_ano`
--   é mais permissiva (qualquer coluna sem ano herda a referência): a série do export não calcula
--   razão, a média das premissas calcula, e "Ticket médio" virar exercício contaminaria a média.
--   Isto é diferença DELIBERADA entre as duas funções, e o teste a trava.
--
-- A CONTA ÚNICA (escada, degrau 2): a classificação da coluna e do período vivia INLINE em
-- `fn_valores_por_ano` (0199/0200). Copiá-la para `fn_linhas_do_realizado` seria a segunda
-- implementação da mesma conta. Ela passa a morar em cinco funções puras (`immutable`) que as DUAS
-- chamam:
--     fn_coluna_e_abertura(coluna)    fn_coluna_e_movimento(coluna)    fn_coluna_e_saldo(coluna)
--     fn_periodo_e_parcial(coluna, tipo_documento, tipo_periodo, referencia)
--     fn_familia_da_secao(secao)
--   `fn_valores_por_ano` é REEMITIDA com o MESMO comportamento da 0200 (assinatura e colunas iguais;
--   os 17 + 21 asserts dos testes da 0199/0200 seguem verdes sem mudar um valor esperado).
--
-- CATÁLOGO DA SONDA: o requisito `serie_por_ano_sem_movimento_nem_abertura` (0199) procurava o literal
-- `saldo\s+(inicial|anterior)\s*$` no CORPO de `fn_valores_por_ano`; o regex agora mora em
-- `fn_coluna_e_abertura`, então o requisito é REAPONTADO para ela (mesmo marcador). Sem o reapontamento
-- a sonda acusaria a 0199 como não aplicada num banco que a tem. Requisitos novos: o corpo de
-- `fn_linhas_do_realizado` (chama `fn_coluna_e_saldo`), o de `fn_valores_por_ano` (chama
-- `fn_periodo_e_parcial`) e a existência de `fn_familia_da_secao`.
--
-- ASSINATURAS E COLUNAS DE RETORNO IGUAIS às da 0151 e da 0200. REEMITIDAS INTEIRAS.
-- CHAMADORES de fn_linhas_do_realizado (grep em Supabase/ N8N/ portal/src/ portal/scripts Verificação):
-- `portal/src/app/casos/[id]/modelagem/page.tsx` (rpc) -> `portal/src/lib/premissas-do-realizado.ts`
-- (consome), `Supabase/test/desempate.test.sql` (2 chamadas). Nenhum outro objeto SQL a chama. Todos
-- leem (seção, rótulo, exercício, valor, papel): ganhar a linha que faltava é o comportamento pedido.
-- CHAMADORES de fn_valores_por_ano: os da 0199/0200, inalterados (mesmo contrato).
--
-- TETO CONHECIDO: o ano de "Saldo Final"/"Saldo atual" é o da REFERÊNCIA do documento. Documento anual
-- cuja referência não traz ano reconhecível (nem 4 dígitos, nem 2 finais) continua fora — ausência, não
-- ano inventado. E "Saldo" sozinho continua fora (ver acima).
--
-- NÃO FAZ: não roda recompute nem regrava a modelagem de caso nenhum (a tela muda no próximo carregamento);
-- não é aplicada por estar escrita — quem responde é a sonda contra o banco em que se está conectado:
--
--   select chave, migration, tipo, objeto, presente, detalhe, porque
--     from fn_instalacao_conferir() where not presente order by 1;
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/realizado_le_saldo_final_e_atual.test.sql — 27 asserts;
-- com a função da 0151 de volta (correção desligada) reprovam 18; sem o fechamento-antes-de-abertura, 2; sem o
-- filtro de parcial, 4; sem a exclusão Societário/Legal, 2; com a abertura no MESMO ano em vez de ano - 1, 7;
-- sem o nome de saldo (a coluna sem ano volta a ficar fora), 18. O assert do Débito é CONTROLE e não reprova
-- em mutação alguma (ver a regra a).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. A CLASSIFICAÇÃO DA COLUNA E DO PERÍODO, EM UM LUGAR SÓ
-- -----------------------------------------------------------------------------
create or replace function fn_coluna_e_abertura(p_coluna text)
returns boolean language sql immutable as $$
  select coalesce(p_coluna, '') ~* '^\s*saldo\s+(inicial|anterior)\s*$'
$$;

create or replace function fn_coluna_e_movimento(p_coluna text)
returns boolean language sql immutable as $$
  select coalesce(p_coluna, '') ~* '^\s*(d[ée]bito|cr[ée]dito)s?\s*$'
$$;

-- A coluna que NOMEIA um saldo mesmo sem trazer ano: o ano é o da referência do documento.
create or replace function fn_coluna_e_saldo(p_coluna text)
returns boolean language sql immutable as $$
  select coalesce(p_coluna, '') ~* '^\s*saldo\s+(final|atual|inicial|anterior)\s*$'
$$;

-- O período PARCIAL (0199 c): balancete, mês, trimestre, intervalo que não é 01/01-31/12, data-base
-- que não é 31/12. Uma coluna que traz 31/12 explícito é fim de ano mesmo num documento parcial.
create or replace function fn_periodo_e_parcial(p_coluna text, p_tipo_documento text,
                                                p_periodo_tipo text, p_referencia text)
returns boolean language sql immutable as $$
  select (coalesce(p_coluna, '') !~ '(31/12|12/31|-12-31)'
       and (   p_tipo_documento = 'BALANCETE'
            or p_periodo_tipo in ('mes', 'trimestre')
            or (p_periodo_tipo = 'data-base' and coalesce(p_referencia, '') !~ '(31/12|12/31|-12-31)')
            or coalesce(p_referencia, '') ~* '^\s*[1-4]\s*t\s*\d{2,4}\s*$'
            or coalesce(p_referencia, '') ~ '^\s*(0?[1-9]|1[01])/(19|20)\d{2}\s*$'
            or coalesce(p_referencia, '') ~ '^\s*(19|20)\d{2}-(0[1-9]|1[01])\s*$'
            or (coalesce(p_referencia, '') ~* '\d{1,2}/\d{1,2}/(19|20)\d{2}\s*(-|–|—|a|à|até|ate)\s*\d{1,2}/\d{1,2}/(19|20)\d{2}'
                and coalesce(p_referencia, '') !~ '^\s*0?1/0?1/(19|20)\d{2}\s*(-|–|—|a|à|até|ate)\s*31/12/(19|20)\d{2}\s*$')
           ))
$$;

-- A FAMÍLIA da demonstração (0200), decidida pela seção e não pelo tipo do documento.
create or replace function fn_familia_da_secao(p_secao text)
returns text language sql immutable as $$
  select case when p_secao ~ '^(ativo|passivo)(_|$)' or p_secao = 'patrimonio_liquido'
                   then 'patrimonial'
              when p_secao in ('receita_bruta', 'custos', 'despesas_operacionais',
                               'resultado_financeiro', 'impostos_lucro')
                   then 'resultado'
              when p_secao ~ '^atividades_' then 'fluxo'
              else coalesce(p_secao, '')   -- NULL, dmpl, dva, NAO_CLASSIFICAVEL: família própria
         end
$$;

comment on function fn_coluna_e_abertura(text) is
  '"Saldo Inicial"/"Saldo anterior": o fechamento do ano ANTERIOR ao do documento (0199 b). Conta única de fn_valores_por_ano e fn_linhas_do_realizado (0201).';
comment on function fn_coluna_e_movimento(text) is
  '"Débito"/"Crédito": movimento do período, nunca saldo (0199 a). Conta única de fn_valores_por_ano e fn_linhas_do_realizado (0201).';
comment on function fn_coluna_e_saldo(text) is
  'Coluna que NOMEIA um saldo sem trazer ano (final, atual, inicial, anterior): o ano vem da referência do documento (0201). "Saldo", "Valor" e "Ticket médio" não são — continuam sem exercício.';
comment on function fn_periodo_e_parcial(text, text, text, text) is
  'Ocorrência de período PARCIAL (balancete, mês, trimestre, intervalo que não é o ano, data-base que não é 31/12) — só entra no ano em que a entidade não tem anual da mesma família (0199 c, 0200). Conta única (0201).';
comment on function fn_familia_da_secao(text) is
  'Família da demonstração pela seção canônica: patrimonial, resultado, fluxo ou a própria seção (0200). Conta única (0201).';

grant execute on function fn_coluna_e_abertura(text) to authenticated;
grant execute on function fn_coluna_e_movimento(text) to authenticated;
grant execute on function fn_coluna_e_saldo(text) to authenticated;
grant execute on function fn_periodo_e_parcial(text, text, text, text) to authenticated;
grant execute on function fn_familia_da_secao(text) to authenticated;

-- -----------------------------------------------------------------------------
-- 2. fn_valores_por_ano — o MESMO comportamento da 0200, chamando as funções puras
-- -----------------------------------------------------------------------------
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
  -- marca-0201
  with ocorrencias as materialized (
    select
      fn_normalizar_texto(ce.chave) as rotulo_norm,
      ce.secao_canonica,
      -- 0199 (b): a coluna de ABERTURA é o fechamento do ano ANTERIOR ao do documento.
      fn_ano_da_coluna(ce.periodo_coluna, p.referencia)
        - (case when fn_coluna_e_abertura(ce.periodo_coluna) then 1 else 0 end) as ano,
      fn_coluna_e_abertura(ce.periodo_coluna) as abertura,
      -- 0199 (c): o saldo de um documento de período PARCIAL só vale na falta do anual.
      fn_periodo_e_parcial(ce.periodo_coluna, d.tipo_taxonomia, p.tipo, p.referencia) as parcial,
      -- 0200: a FAMÍLIA da demonstração e a ENTIDADE, para decidir o parcial por ano e não por rótulo.
      fn_familia_da_secao(ce.secao_canonica) as familia,
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
      and not fn_coluna_e_movimento(ce.periodo_coluna)
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
  'Série histórica por (rótulo, seção, ano), só da versão vigente (0102), com a proveniência DA CÉLULA (0125). 0199: coluna de movimento (Débito/Crédito) nunca é saldo; "Saldo Inicial"/"Saldo Anterior" é o fechamento do ano ANTERIOR e perde para o fechamento do mesmo ano; tipo de categoria Societário/Legal e Garantias/Sócios não entra. 0200: ocorrência de período PARCIAL (balancete, mês, trimestre, intervalo) só entra num ano em que a entidade não tem NENHUMA ocorrência anual da mesma família (patrimonial / resultado / fluxo / seção própria) — decisão do ANO, não do rótulo. 0201: a classificação da coluna e do período vem das funções puras fn_coluna_e_*, fn_periodo_e_parcial e fn_familia_da_secao, as MESMAS de fn_linhas_do_realizado. Dentro da camada, maior módulo com sinal (0042); desempate determinístico.';

grant execute on function fn_valores_por_ano(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. fn_linhas_do_realizado — a 0151 inteira, lendo o documento anual de Saldo Final/Saldo atual
-- -----------------------------------------------------------------------------
create or replace function fn_linhas_do_realizado(p_caso_id uuid, p_entidade text default null)
returns table(
  secao_canonica text,
  rotulo_norm text,
  chave text,
  entidade text,
  exercicio integer,
  valor numeric,
  papel text,
  documentos text[]
)
language sql stable
as $$
  -- marca-0150
  -- marca-0151
  -- marca-0201
  --
  -- A MARCA FICA, e o motivo é o mesmo da 0102: a sonda de instalação confere se
  -- a correção está APLICADA NO BANCO procurando `0150` no corpo desta função —
  -- é o que separa "mergeado" de "aplicado". Uma reemissão futura mantém a
  -- marca; trocá-la apagaria a resposta da pergunta que ela faz.
  with bruto as materialized (
    select
      ce.secao_canonica,
      ce.chave,
      fn_normalizar_texto(ce.chave) as rotulo_norm,
      -- 0146: a capa só responde quando o documento é de UMA empresa.
      coalesce(ce.entidade_coluna,
               case when (select count(distinct ce2.entidade_coluna)
                            from campo_extraido ce2
                           where ce2.documento_versao_id = ce.documento_versao_id
                             and ce2.entidade_coluna is not null) > 1
                    then null else e.razao_social end) as entidade,
      -- 0201: a coluna que NOMEIA um saldo ("Saldo Final", "Saldo atual", "Saldo Inicial", "Saldo
      -- anterior") não traz ano e herda o da referência do documento; a de ABERTURA é o ano - 1.
      -- Coluna com ano no texto segue lendo o texto; coluna sem ano e sem nome de saldo ("Saldo",
      -- "Valor", "Ticket médio") segue SEM exercício — e portanto fora (0150).
      case when fn_coluna_e_saldo(ce.periodo_coluna)
           then fn_ano_da_coluna(ce.periodo_coluna, p.referencia)
                - (case when fn_coluna_e_abertura(ce.periodo_coluna) then 1 else 0 end)
           else fn_exercicio_da_coluna(ce.periodo_coluna)
      end as exercicio,
      fn_coluna_e_abertura(ce.periodo_coluna) as abertura,
      fn_periodo_e_parcial(ce.periodo_coluna, d.tipo_taxonomia, p.tipo, p.referencia) as parcial,
      fn_familia_da_secao(ce.secao_canonica) as familia,
      ce.valor_num,
      ce.unidade,
      d.tipo_taxonomia,
      dv.documento_id,
      aut.autoridade
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    left join periodo p on p.id = d.periodo_id
    left join entidade e on e.id = d.entidade_id
    left join taxonomia_tipo_documento t on t.codigo = d.tipo_taxonomia
    cross join lateral fn_autoridade_do_documento(d.id) aut
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      and dv.id = fn_versao_com_extracao(d.id)
      -- A ABERTURA ANALÍTICA NÃO SOMA. Tipo desconhecido (fora do catálogo)
      -- entra somando: o padrão seguro é o de sempre, e o catálogo é quem
      -- declara a exceção.
      and coalesce(t.abertura_analitica, false) = false
      -- 0201 (d): a mesma exclusão da série por ano. (O movimento, 0199 a, não precisa de filtro AQUI:
      -- "Débito"/"Crédito" não trazem ano nem nome de saldo, então `exercicio` já é NULL e a linha
      -- cai em `filtrado`. MEDIDO: tirar o filtro explícito não reprova nenhum assert, por isso ele
      -- não foi escrito — código sem efeito medível é o que a regra 2 proíbe.)
      and coalesce(t.categoria, '') not in ('Societário/Legal', 'Garantias/Sócios')
  ),
  filtrado as (
    select b.*,
           fn_normalizar_texto(coalesce(b.entidade, '')) as entidade_chave
    from bruto b
    where b.exercicio is not null
      and (p_entidade is null
           or fn_normalizar_texto(b.entidade) = fn_normalizar_texto(p_entidade))
  ),
  -- 0201 (c'): o período PARCIAL só entra no exercício em que a entidade não tem anual da mesma
  -- família — a decisão é do ANO, como na 0200.
  elegivel as (
    select f.*,
           bool_or(not coalesce(f.parcial, false))
             over (partition by f.entidade_chave, f.familia, f.exercicio) as ano_tem_anual
    from filtrado f
  ),
  papel_do_rotulo as (
    select distinct chave, tipo_taxonomia, unidade,
           fn_papel_linha(chave, tipo_taxonomia, unidade) as papel
    from (select distinct chave, tipo_taxonomia, unidade from elegivel
           where not (coalesce(parcial, false) and ano_tem_anual)) d
  ),
  com_papel as (
    select f.*, p.papel
    from elegivel f
    join papel_do_rotulo p
      on p.chave = f.chave
     and p.tipo_taxonomia is not distinct from f.tipo_taxonomia
     and p.unidade is not distinct from f.unidade
    where not (coalesce(f.parcial, false) and f.ano_tem_anual)
  ),
  agrupado as (
    select
      c.secao_canonica,
      c.rotulo_norm,
      (array_agg(c.chave order by length(c.chave)))[1] as chave,
      max(c.entidade) as entidade,
      c.exercicio,
      -- 0201: o FECHAMENTO vence a abertura do mesmo exercício (a abertura é o eco dele no ano
      -- seguinte), antes da autoridade e do módulo.
      --
      -- 0151: O DESEMPATE ENTRE DOCUMENTOS, QUE ERA SILENCIOSO.
      --
      -- Dentro do MESMO exercício, a mesma conta pode vir de dois documentos (o
      -- balanço e a DF auditada dizem a mesma coisa). Quando eles CONCORDAM, a
      -- escolha é indiferente. Quando discordam, a regra da 0042 — o de maior
      -- módulo — vira "fica com o maior", que num caso de reestruturação
      -- escolhe sempre o número que infla o ativo.
      --
      -- A AUTORIDADE DOCUMENTAL DECIDE PRIMEIRO, e o maior módulo fica como
      -- último recurso: no EMPATE de autoridade o valor não muda, é o mesmo de
      -- antes desta migration. Trocar o número no empate seria substituir uma
      -- regra silenciosa por outra — e quem avisa que houve empate é
      -- `fn_reconciliar_versoes_do_periodo`, com o número perdedor à vista.
      (array_agg(c.valor_num
                 order by c.abertura, c.autoridade desc, abs(c.valor_num) desc nulls last))[1] as valor,
      (array_agg(c.papel order by fn_papel_prioridade(c.papel)))[1] as papel,
      array_agg(distinct c.tipo_taxonomia) as documentos,
      -- Quantos documentos DISTINTOS trouxeram esta linha neste exercício: é o
      -- que o item 4 usa para saber se o total veio acompanhado das componentes.
      array_agg(distinct c.documento_id) as docs_ids
    from com_papel c
    group by c.secao_canonica, c.rotulo_norm, c.exercicio
  ),
  -- ---------------------------------------------------------------------------
  -- 4. O TOTAL QUE VEIO COM AS COMPONENTES É SUBTOTAL, MESMO SEM ESTAR NA LISTA
  -- ---------------------------------------------------------------------------
  --
  -- A `0116` deixou o topo da DRE fora da lista fechada de subtotais porque num
  -- documento RESUMIDO ele é a conta. O discriminador que faltava é estrutural e
  -- só existe olhando o documento inteiro: se o módulo desta linha bate com a
  -- SOMA das outras contas da mesma seção, mesmo exercício e mesma entidade, ela
  -- é o total delas — e somar os dois conta duas vezes.
  --
  -- A tolerância é de 1% e existe porque a soma de valores arredondados ao
  -- milhar não fecha ao centavo: medido no Canastra, 177.077 contra 177.133
  -- (0,03%). Sem folga, o discriminador não dispararia exatamente no caso que o
  -- motivou.
  -- O SINAL SEPARA AS DUAS FAMÍLIAS QUE MORAM NA MESMA SEÇÃO. Medido no Canastra
  -- 2025: `receita_bruta` guarda as receitas (positivas) E as deduções
  -- (negativas), e cada família tem o próprio total impresso —
  -- "Receita operacional bruta" 188.000 e "(-) Deduções da receita bruta"
  -- 48.128. Somando a seção inteira, nenhum dos dois bate com o dobro de si
  -- mesmo, e o discriminador não dispara para nenhum: a receita ficaria certa e
  -- a dedução contaria duas vezes. Agrupando por sinal, os dois batem — 188.000
  -- contra as quatro linhas de venda, 48.128 contra ICMS, PIS/COFINS e
  -- devoluções.
  soma_das_contas as (
    select a.secao_canonica, a.exercicio, a.entidade, sign(a.valor) as sinal,
           sum(abs(a.valor)) filter (where a.papel = 'conta') as total_contas
    from agrupado a
    group by a.secao_canonica, a.exercicio, a.entidade, sign(a.valor)
  )
  select
    a.secao_canonica,
    a.rotulo_norm,
    a.chave,
    a.entidade,
    a.exercicio,
    a.valor,
    case
      when a.papel = 'conta'
       and s.total_contas is not null
       and abs(a.valor) > 0
       -- `2 × |valor|` porque o próprio valor está DENTRO de `total_contas`:
       -- o total mais as componentes dá duas vezes o total. É a mesma
       -- aritmética que a 0143 usa para declarar hierarquia achatada.
       and abs(s.total_contas - 2 * abs(a.valor)) <= 0.01 * abs(a.valor)
      then 'subtotal'
      else a.papel
    end as papel,
    a.documentos
  from agrupado a
  left join soma_das_contas s
    on s.secao_canonica is not distinct from a.secao_canonica
   and s.exercicio = a.exercicio
   and s.entidade is not distinct from a.entidade
   and s.sinal = sign(a.valor)
$$;

comment on function fn_linhas_do_realizado(uuid, text) is
  'As linhas do caso POR EXERCÍCIO, de uma entidade, sem o que não se soma (0150): fora a '
  'abertura analítica (balancete, aging, estoque, extrato — elas reabrem contas que a '
  'demonstração já declara), fora o combinado (soma das empresas), fora a coluna que não nomeia '
  'exercício, e com o total que veio acompanhado das próprias componentes marcado `subtotal`. '
  '0201: lê também o documento anual de "Saldo Final"/"Saldo atual" (ano da referência) e '
  '"Saldo Inicial"/"Saldo anterior" (ano - 1, atrás do fechamento), sem movimento, sem '
  'Societário/Legal, e com o período parcial só no exercício sem anual da mesma família — as '
  'mesmas contas de fn_valores_por_ano. É a base das premissas do realizado e da média histórica; '
  'a LISTA da tela continua saindo de fn_linhas_para_modelagem, que agrupa por rótulo.';

grant execute on function fn_linhas_do_realizado(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Catálogo da sonda. ORDEM 857-860: a 0200 usa 856.
-- -----------------------------------------------------------------------------
-- O requisito da 0199 procurava o literal no corpo de fn_valores_por_ano; o regex mora agora em
-- fn_coluna_e_abertura. MESMO marcador, objeto reapontado.
update instalacao_requisito
   set objeto = 'fn_coluna_e_abertura'
 where chave = 'serie_por_ano_sem_movimento_nem_abertura' and migration = '0199';

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, porque, severidade, ordem) values
  ('realizado_le_saldo_final_e_atual', '0201', 'corpo', 'fn_linhas_do_realizado',
   'fn_coluna_e_saldo',
   'Sem este corpo as premissas do realizado ignoram todo documento anual cujas colunas são "Saldo Final"/"Saldo '
   'atual"/"Saldo Inicial"/"Saldo anterior": a tela de modelagem mostra TODAS as sugestões vazias (CUSTO_VARIAVEL, '
   'SGA_PCT, PMR, PME, PMP, ALIQUOTA, PARCELA_ONEROSA, TAXA_DIVIDA). MEDIDO EM PRODUÇÃO (05/10/2026, Fw Valtra '
   '03a66ab6): a função devolvia só as linhas do DFC e nenhuma do BALANCO nem da DRE.',
   'importante', 857),
  ('serie_por_ano_usa_a_conta_unica', '0201', 'corpo', 'fn_valores_por_ano',
   'fn_periodo_e_parcial',
   'fn_valores_por_ano e fn_linhas_do_realizado classificam coluna e período pelas MESMAS funções puras; sem este '
   'corpo a série do export volta a ter a própria cópia da conta, e as duas voltam a divergir sobre o mesmo documento.',
   'importante', 858),
  ('classificacao_de_coluna_e_familia', '0201', 'funcao', 'fn_familia_da_secao', null,
   'A família da demonstração (patrimonial/resultado/fluxo) decide quando o período parcial entra; as duas funções '
   'do realizado a chamam. Sem ela o corpo novo morre na primeira consulta.',
   'importante', 859)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, porque = excluded.porque,
      severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0201', revisado_em = current_date,
       observacao = 'A 0201 ensina fn_linhas_do_realizado a ler "Saldo Final"/"Saldo atual" (ano da referência) e '
         '"Saldo Inicial"/"Saldo anterior" (ano - 1), e move a classificação de coluna/período de fn_valores_por_ano '
         'para cinco funções puras que as duas chamam. Medido em produção (05/10/2026, só-leitura, Fw Valtra). '
         'Catalogada pelo corpo (realizado_le_saldo_final_e_atual, serie_por_ano_usa_a_conta_unica); o requisito da '
         '0199 foi reapontado para fn_coluna_e_abertura.'
 where id = true;
