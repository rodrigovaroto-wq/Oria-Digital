-- =============================================================================
-- 0199 — A SÉRIE POR ANO QUE LIA MOVIMENTO E ABERTURA COMO SALDO
--
-- O DEFEITO (medido em PRODUÇÃO, 05/10/2026, caso "Fw Valtra" 03a66ab6, empresa MOTO AGRICOLA
-- VOLKWEIS LTDA). `fn_valores_por_ano` (0125) monta a série (rótulo, seção, ANO) com
-- `(array_agg(valor order by abs(valor) desc))[1]`: o MAIOR |valor| entre TODAS as ocorrências do
-- ano, de todos os documentos e de todas as colunas. O ano vem de `fn_ano_da_coluna(coluna,
-- referência)`, que devolve o ano da referência do documento quando a coluna não traz ano — e
-- "Saldo Inicial", "Débito" ou "Saldo Atual" não trazem. Três vícios, todos medidos:
--
--   1. COLUNA DE MOVIMENTO LIDA COMO SALDO. O BALANCETE semestral (referência "01/01/2025 -
--      30/06/2025") traz `Saldo Anterior`, `Débito`, `Crédito`, `Saldo Atual`; as quatro viram 2025
--      e o maior módulo é o Débito. "ATIVO" 2025 = 125.859.727,84 (Débito do balancete) onde o
--      BALANCO anual diz 38.483.404,04; "ATIVO CIRCULANTE" 2025 = 125.484.949,09 (Débito) contra
--      33.056.432,15.
--   2. "SALDO INICIAL"/"SALDO ANTERIOR" LIDO COMO O ANO DO DOCUMENTO. O BALANCO de referência
--      "2025" traz `Saldo Inicial` (= o fechamento de 2024) e `Saldo Final`; a DRE de referência
--      "2025" traz `Saldo anterior` (= o exercício de 2024) e `Saldo atual`. As duas colunas viram
--      2025. "CLIENTES" 2025 = 5.218.337,81 (o Saldo Inicial, que é o de 2024) em vez de
--      4.292.868,90; na DRE 2023, "VENDA DE IMPLEMENTOS NOVOS" = 10.162.581,81 (Saldo anterior =
--      2022) em vez de 9.673.146,21.
--   3. DOCUMENTO NÃO-FINANCEIRO NA SÉRIE. O CONTRATO_SOCIAL tem linhas com
--      `secao_canonica = 'patrimonio_liquido'` ("total - nº de quotas" 15.500.000, "total - %" 100,
--      "total - capital social") que entravam no PL de 2025.
--
-- EFEITO: o balanço do modelo não fechava em ~90,5 mi de 2025 a 2030. Com a regra abaixo aplicada
-- numa cópia da consulta, o `auditar-xlsx` foi de 8/11 para 10/11, o balanço fechou nas 9 colunas e
-- o ativo total bateu com o documento em todos os anos.
--
-- A REGRA (comportamento, não mecanismo):
--
--   a. COLUNA DE MOVIMENTO NUNCA É SALDO. "Débito"/"Crédito" não entram na série — não há ano a
--      que um movimento do período pertença como saldo. (Ausência, não zero: regra 1.)
--   b. COLUNA DE ABERTURA PERTENCE AO ANO ANTERIOR. "Saldo Inicial"/"Saldo Anterior" de um documento
--      de 2025 é o fechamento de 2024. E quando o MESMO (rótulo, seção, ano) tem fechamento E
--      abertura, vence o fechamento: é o número daquele exercício, não o eco dele no ano seguinte.
--   c. O PERÍODO ANUAL VENCE O PARCIAL. Entre ocorrências do mesmo ano, a de documento de período
--      parcial (balancete, mês, trimestre, intervalo de datas que não é 01/01–31/12, data-base que
--      não é 31/12) só vale quando NÃO HÁ nenhuma de documento anual: o saldo de 30/06 nunca ganha do
--      de 31/12. DECISÃO DECLARADA: o parcial NÃO é excluído — se é a ÚNICA fonte do ano, ele entra
--      (ausência de dado não vira zero, e um balancete sozinho é melhor que um ano em branco). O
--      efeito dessa decisão é que, num ano em que só há balancete semestral, o "saldo do ano" é o de
--      30/06 — e o `n_ocorrencias`/`arquivo` da célula dizem de onde veio.
--      TETO CONHECIDO: "parcial" é decidido pelo tipo do documento (BALANCETE), por `periodo.tipo`
--      (mes, trimestre, data-base) e pelo texto da referência (intervalo de datas, "1T25", "03/2025"),
--      e a coluna que traz uma data 31/12 explícita conta como fim de ano mesmo num documento
--      parcial. Referência em notação que esta lista não reconhece conta como anual. O Saldo
--      Anterior de um balancete parcial é tratado como parcial (para o balancete que começa em
--      01/01 ele é, de fato, o 31/12 anterior — mas o anual do mesmo ano, quando existe, vence do
--      mesmo jeito, e quando não existe o balancete é o que sobra).
--   d. DOCUMENTO NÃO-DEMONSTRATIVO NÃO ENTRA. Pelo catálogo, não por lista no código: tipo cuja
--      `categoria` é 'Societário/Legal' (CONTRATO_SOCIAL, ORGANOGRAMA, CERTIDOES, CONTINGENCIAS) ou
--      'Garantias/Sócios' (GARANTIAS, AVAIS_FIANCAS, DOCS_SOCIOS). Quotas, percentuais de
--      participação e bens em garantia não são saldo de demonstração. Tipo novo fora dessas duas
--      categorias entra (o padrão seguro é o da 0150: o catálogo declara a exceção).
--   e. DESEMPATE FINAL DETERMINÍSTICO: período anual antes de parcial, fechamento antes de abertura,
--      maior módulo (COM SINAL, como na 0042), depois valor decrescente (em empate de módulo com
--      sinais opostos, o positivo), maior confiança, página mais baixa, nome do arquivo, ordem. Duas
--      execuções sobre o mesmo dado devolvem a mesma célula e a mesma nota de proveniência.
--
-- A PROVENIÊNCIA agora vem DIRETO da ocorrência escolhida (um `distinct on`), em vez do join de volta
-- por valor igual da 0125: com a escolha em camadas, "a ocorrência que tem aquele valor" poderia ser a
-- de outra camada (um débito de mesmo valor que o saldo). `n_ocorrencias` continua sendo quantas
-- ocorrências ELEGÍVEIS o (rótulo, seção, ano) tem — incluindo as que perderam —, como sempre foi.
--
-- ASSINATURA E COLUNAS DE RETORNO IGUAIS às da 0125 (o portal e o export dependem delas), então
-- `create or replace` basta — sem drop. REEMITIDA INTEIRA, nunca por replace de texto.
--
-- CHAMADORES de fn_valores_por_ano (grep em Supabase/ N8N/ portal/src/ portal/scripts Verificação):
-- o export (`portal/src/app/casos/[id]/export/route.ts` via rpc), `portal/scripts/gerar-export-do-banco.mts`,
-- `portal/scripts/verificar-export.mts`, `Verificação/run.mts` e `Verificação/variacoes.mts`,
-- `Supabase/test/proveniencia.test.sql`. Nenhum outro objeto SQL a chama (0129/0126 só citam a regra de
-- desempate em comentário). N8N/ e portal/src/lib não a chamam. Todos leem a série (rótulo, seção, ano,
-- valor): ganhar o saldo certo é o comportamento pedido em todos.
--
-- NÃO MEXE em `fn_ano_da_coluna`: a reconciliação inteira a usa (fn_anos_alvo, caixa, despfin…) e a
-- correção cabe aqui, onde a coluna é classificada. NÃO MEXE em `fn_linhas_do_realizado`: ela usa
-- `fn_exercicio_da_coluna`, que devolve NULL para "Saldo Inicial"/"Saldo Final"/"Débito" (coluna sem
-- ano é AUSÊNCIA), já exclui BALANCETE por `abertura_analitica`, e portanto NÃO tem estes vícios — o
-- que ela tem é o oposto (não lê o ano de uma coluna "Saldo Final" de documento anual), um defeito de
-- cobertura que é outra fatia e não foi tocado aqui.
--
-- NÃO FAZ: não roda recompute nem regrava modelagem de caso nenhum; não é aplicada por estar escrita —
-- quem responde é a sonda contra o banco em que se está conectado:
--
--   select chave, migration, tipo, objeto, presente, detalhe, porque
--     from fn_instalacao_conferir() where not presente order by 1;
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/serie_por_ano_movimento_e_abertura.test.sql — 19 dos 21 asserts
-- reprovam com o corpo da 0125 de volta; os 2 que seguem verdes são controles (ESTOQUES 2024 e a página de
-- CLIENTES 2025, que o código antigo também acertava). MUTAÇÕES ISOLADAS, medidas: sem a chave "fechamento
-- antes de abertura" reprova 1 (ESTOQUES 2024); sem a chave "anual antes de parcial" reprovam 5.
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
  escolhido as (
    select
      o.rotulo_norm, o.secao_canonica, o.ano, o.valor,
      -- quantas ocorrências elegíveis o (rótulo, seção, ano) tem, incluindo as que perderam
      count(*) over (partition by o.rotulo_norm, o.secao_canonica, o.ano) as n_ocorrencias,
      o.arquivo, o.origem_pagina, o.confianca, o.status_aceite, o.aceito_por,
      row_number() over (
        partition by o.rotulo_norm, o.secao_canonica, o.ano
        order by o.parcial,            -- (c) anual antes de parcial
                 o.abertura,           -- (b) fechamento antes de abertura
                 abs(o.valor) desc,    -- maior módulo COM SINAL, a regra da 0042
                 o.valor desc,         -- (e) empate de módulo com sinais opostos: o positivo
                 o.confianca desc nulls last,
                 o.origem_pagina asc nulls last,
                 o.arquivo,
                 o.ordem
      ) as rn
    from ocorrencias o
    where o.ano is not null
  )
  select rotulo_norm, secao_canonica, ano, valor, n_ocorrencias,
         arquivo, origem_pagina, confianca, status_aceite, aceito_por
  from escolhido
  where rn = 1
  order by rotulo_norm, ano;
$$;

comment on function fn_valores_por_ano(uuid, text) is
  'Série histórica por (rótulo, seção, ano), só da versão vigente (0102), com a proveniência DA CÉLULA (0125). 0199: coluna de movimento (Débito/Crédito) nunca é saldo; "Saldo Inicial"/"Saldo Anterior" é o fechamento do ano ANTERIOR e perde para o fechamento do mesmo ano; período anual vence balancete/período parcial (que só entra na falta do anual); tipo de categoria Societário/Legal e Garantias/Sócios não entra. Dentro da camada, maior módulo com sinal (0042); desempate determinístico.';

grant execute on function fn_valores_por_ano(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Catálogo da sonda — requisito de CORPO (marcador é código, não comentário).
-- ORDEM 855: a 0198 usa até 854.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, porque, severidade, ordem) values
  ('serie_por_ano_sem_movimento_nem_abertura', '0199', 'corpo', 'fn_valores_por_ano',
   'saldo\s+(inicial|anterior)\s*$',
   'Sem este corpo a série por ano lê "Débito" do balancete como saldo, "Saldo Inicial"/"Saldo anterior" como o '
   'ano do documento e o saldo de 30/06 como o de 31/12, e o CONTRATO_SOCIAL entra no PL. '
   'MEDIDO EM PRODUÇÃO (05/10/2026, só-leitura, caso Fw Valtra 03a66ab6): ATIVO 2025 = 125.859.727,84 (Débito do '
   'balancete) onde o balanço diz 38.483.404,04; CLIENTES 2025 = 5.218.337,81 (Saldo Inicial) em vez de 4.292.868,90; '
   'o balanço do modelo não fechava em ~90,5 mi de 2025 a 2030.',
   'importante', 855)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, porque = excluded.porque,
      severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0199', revisado_em = current_date,
       observacao = 'A 0199 reemite fn_valores_por_ano: movimento (Débito/Crédito) fora, abertura (Saldo Inicial/Anterior) '
         'no ano anterior e atrás do fechamento, período anual antes do parcial, Societário/Legal e Garantias/Sócios fora. '
         'Medido em produção (05/10/2026, só-leitura, Fw Valtra). Catalogada pelo corpo '
         '(serie_por_ano_sem_movimento_nem_abertura); a assinatura não muda.'
 where id = true;
