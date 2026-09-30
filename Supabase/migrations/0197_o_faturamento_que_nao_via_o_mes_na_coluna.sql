-- =============================================================================
-- 0197 — O FATURAMENTO QUE NÃO VIA O MÊS NA COLUNA (e o ticket médio que entrava na soma)
--
-- Achado da revisão independente da 0196 (30/09/2026). A 0196 passou a tirar o ano do
-- faturamento da COLUNA, mas ainda exigia que o RÓTULO parecesse um mês. No leiaute com o
-- mês na COLUNA (chave "Faturamento", colunas "jan/2024", "fev/2024"…), o rótulo é só
-- "Faturamento": a exigência descartava justamente a coluna que já é o mês, e a receita
-- ficava sem conferência com um motivo FALSO ("o Faturamento não traz linha mensal deste
-- ano" — os meses estão lá). Antes da 0196 o número era lixo (o "Ticket médio", 38,2);
-- depois dela, 0 meses: não é regressão de número, mas é ausência com motivo errado (regra 1).
--
-- DEFEITO 1 — mês na coluna. CORREÇÃO: quando a COLUNA é "mês/ano" DAQUELE ano
-- ("jan/2024", "Janeiro/2023", "01/2024"), ela conta como mês daquele ano, qualquer que seja
-- o rótulo. O mês passa a fazer parte da chave de agrupamento (`mes_da_coluna`): sem isso as
-- 12 células de chave "Faturamento" colapsariam em UMA linha e `n_linhas` diria "1 mês".
-- `n_linhas` segue contando MESES (colunas-mês distintas, ou rótulos como antes). Linha de
-- memória (ticket, média, total, acumulado) continua fora; percentual continua fora.
-- Coluna que é um INTERVALO de dois anos ("jan/2024 — jan/2025", uma célula só) NÃO é
-- atribuída a ano nenhum por esta migration: o valor é de um dos anos e a extração não diz
-- qual — atribuir seria inventar. Nesse leiaute a soma segue 0 e o motivo genérico da 0188
-- ("não traz linha mensal deste ano") segue sendo dito. Quando de fato não há mês, é o que sai.
--
-- DEFEITO 2 — `not like '%médi%'` era código morto. `fn_normalizar_texto` tira o acento
-- ('Ticket médio' vira 'ticket medio'), e nem '%media%' nem '%médi%' casam "medio". No modo
-- por rótulo, "Ticket médio por pedido 2024" entrava na soma como se fosse um mês. O
-- cabeçalho da 0196 afirmava que o ticket ficava fora: só ficava no modo por coluna.
-- CORREÇÃO: casa a forma normalizada, por palavra (medio|media) — por palavra e não por
-- substring para não derrubar "remédios"/"comediantes" de um rótulo legítimo.
--
-- MEDIDO EM PRODUÇÃO (30/09/2026, SOMENTE LEITURA; produção está na 0195, então a função
-- vigente lá é a 0167), 83 documentos FATURAMENTO_24M x anos 2020-2026, função 0167 x 0196 x 0197:
--   84 documentos FATURAMENTO_24M x 7 anos = 588 pares; 90 têm soma na função vigente e 76 deles NÃO mudam (os
-- formatos por rótulo, de categorias e o book). Mudam 31 pares, em 15 documentos:
--   • CAUSA do defeito 1, mês na coluna (chave "Faturamento"/"Faturamento Bruto"/"Faturamento (R$)" e colunas
--     "jan/2024"…), hoje 0 meses: v20, v21, v22, v23 (2024 = 4.370.000, 2025 = 5.000.000, 12 meses cada);
--     v27, v28, v40 (183.480 / 138.400, 12 meses); v29 (vigente 38,2 = o ticket; 0196 = 0; 0197 = 183.480 /
--     138.400); Canastra 1110088f (2023 = 318.019.580, 2024 = 246.015.145, 2025 = 188.011.575, 12 meses).
--   • CAUSA do defeito 2, ticket médio por rótulo+coluna: v24 (vigente e 0196 = 38,2 com 1 "mês" em 2024 e 31,4
--     em 2025; 0197 = 0 meses). O cabeçalho da 0196 dizia "0 documentos" — é 1 (v24), e ele NÃO é latente.
--   • Já corrigidos pela 0196 e inalterados pela 0197: S104 teste E2E Vertentes (85e97a71) e "teste ponta a
--     ponta 30-09" (18e07168): 321.579,6 -> 183.480 (2024) e 138.400 (2025).
--   • NÃO mudam com a 0197 (seguem 0 meses): v33, v35, v39 custo (vigente 38,2 = ticket; 0196 e 0197 = 0). O
--     leiaute deles NÃO é "mês na coluna": o rótulo é "Faturamento Janeiro" (v35, v39) ou "Faturamento" (v33)
--     e a coluna é o INTERVALO "jan/2024 — jan/2025", com UMA célula por mês (o valor é o de 2024: 183.480
--     fecha com o total). A extração perdeu a ponta de 2025 e a coluna não diz de qual ano é a célula;
--     atribuí-la seria inventar. A receita desses casos segue sem conferência e o motivo genérico da 0188
--     segue sendo dito; o conserto é na EXTRAÇÃO (uma coluna por ano), não aqui.
--
-- CHAMADORES de fn_somar_faturamento_ano (grep em Supabase/ N8N/ portal/src/): só
-- fn_reconciliar_receita_dre_vs_faturamento (0015 → 0188 → 0193 → 0196, vigente), mais os testes
-- faturamento_por_mes e caixa_dfc_de_um_ano. N8N/ e portal/src/ não chamam. Para a receita:
-- documento que passa a ter mês-na-coluna deixa de sair "precondicao_nao_satisfeita" e passa a
-- ser COMPARADO com a DRE (a tolerância Classe B não muda); o "Ticket médio" deixa de ser
-- comparado como se fosse faturamento. Os formatos que já somavam (linha mensal por rótulo,
-- categorias, 3 colunas de ano) não mudam: o teste faturamento_por_mes e o book seguem verdes.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/faturamento_mes_na_coluna.test.sql, 13
-- asserts (contados no log); com a 0197 fora, 9 reprovam e 4 seguem passando (os controles: 2024 sem
-- mês = 0, as duas células do intervalo = 0, e o rótulo com "remédios").
--
-- NÃO FAZ: não roda reconciliação nem recompute em caso nenhum; não é aplicada por estar
-- escrita — quem responde é a sonda contra o banco em que se está conectado:
--
--   select chave, migration, tipo, objeto, presente, detalhe, porque
--     from fn_instalacao_conferir() where not presente order by 1;
-- =============================================================================

-- REEMITIDA INTEIRA (corpo vigente 0196:819), nunca por replace de texto.
create or replace function fn_somar_faturamento_ano(
  p_documento_versao_id uuid,
  p_ano4 text,
  p_ano2 text
)
returns table(soma numeric, n_linhas integer)
language sql
stable
as $_$
  with modo as (
    -- O documento traz o ANO na coluna? ('2024', 'jan/2024', '31/12/2024'...) Só então
    -- o ano sai da `periodo_coluna`; colunas de CATEGORIA (Saídas R$, Total R$) não
    -- ancoram ano nenhum e ficam no modo do rótulo, o de sempre (0167).
    select exists (
      select 1 from campo_extraido ce
      where ce.documento_versao_id = p_documento_versao_id
        and ce.periodo_coluna is not null
        and cardinality(fn_anos_texto(ce.periodo_coluna)) > 0
    ) as ano_na_coluna
  ),
  celulas as (
    select ce.chave, ce.periodo_coluna, ce.valor_num,
           -- 0197: a COLUNA é, ela mesma, um mês DESTE ano ("jan/2024", "Janeiro/2023",
           -- "01/2024"). O intervalo "jan/2024 — jan/2025" não casa (ancorado no fim).
           (
             fn_normalizar_texto(ce.periodo_coluna)
               ~ ('^(jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)[a-z]*[/. -]+(' || p_ano4 || '|' || p_ano2 || ')$')
             or fn_normalizar_texto(ce.periodo_coluna)
               ~ ('^(0?[1-9]|1[0-2])[/. -]+(' || p_ano4 || '|' || p_ano2 || ')$')
           ) as coluna_e_mes
    from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id
  ),
  candidatos as (
    select ce.chave, ce.periodo_coluna, ce.valor_num,
           case when ce.coluna_e_mes then fn_normalizar_texto(ce.periodo_coluna) else '' end as mes_da_coluna
    from celulas ce cross join modo
    where ce.valor_num is not null
      and (
        case when modo.ano_na_coluna then
          -- 0196: a célula é do ano pedido quando a COLUNA diz que é; o rótulo só
          -- precisa parecer um mês (o "jan/2024 — jan/2025" traz os DOIS anos, e a
          -- linha "Ticket médio…" não é mês nenhum). 0197: ou a coluna É o mês.
          fn_anos_texto(ce.periodo_coluna) && fn_anos_texto(p_ano4)
          and (
            ce.coluna_e_mes
            or position(p_ano4 in fn_normalizar_texto(ce.chave)) > 0
            or fn_normalizar_texto(ce.chave) ~ ('[/. -]' || p_ano2 || '($|[^0-9])')
            or fn_normalizar_texto(ce.chave) ~ '^(jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)'
          )
        else
          position(p_ano4 in fn_normalizar_texto(ce.chave)) > 0
          or fn_normalizar_texto(ce.chave) ~ ('[/. -]' || p_ano2 || '($|[^0-9])')
        end
      )
      and fn_normalizar_texto(ce.chave) not like '%total%'
      and fn_normalizar_texto(ce.chave) not like '%acumulad%'
      -- 0197: a forma NORMALIZADA (sem acento) é "medio"/"media". O '%médi%' da 0196 nunca
      -- casava, porque o acento já tinha sido tirado. Por palavra, para não pegar "remédios".
      and fn_normalizar_texto(ce.chave) !~ '(^|[^a-z])(medio|media)s?([^a-z]|$)'
      -- 0196: coluna de PERCENTUAL nunca é dinheiro (a 'Variação %' do relatório de
      -- 3 colunas somava -41,2 a -6,7 ao faturamento de cada mês).
      and position('%' in coalesce(ce.periodo_coluna, '')) = 0
      and fn_normalizar_texto(coalesce(ce.periodo_coluna, '')) not like '%variac%'
  ),
  -- UM VALOR POR MÊS (0167). 0197: com o mês na COLUNA, o mês entra na chave do grupo —
  -- senão as 12 células de chave "Faturamento" virariam uma linha só.
  por_rotulo as (
    select
      chave,
      mes_da_coluna,
      coalesce(
        max(valor_num) filter (where fn_normalizar_texto(periodo_coluna) like '%total%'),
        sum(valor_num)
      ) as valor
    from candidatos
    group by chave, mes_da_coluna
  )
  select coalesce(sum(valor), 0)::numeric,
         count(distinct case when mes_da_coluna <> '' then mes_da_coluna else chave end)::int
  from por_rotulo;
$_$;

comment on function fn_somar_faturamento_ano(uuid, text, text) is
  'Soma o faturamento de um ano, UM VALOR POR MÊS. 0167: a categoria mora em periodo_coluna '
  '(Saídas/Serviços/Outros/Total) e a chave repete o mês nas quatro — com coluna de total, ela manda. '
  '0196: quando as colunas do documento são ANOS (2024, 2025), o ano sai da COLUNA; coluna de '
  'percentual nunca entra na soma. 0197: coluna "mês/ano" do ano pedido conta como mês mesmo com '
  'rótulo genérico ("Faturamento"); intervalo de dois anos numa célula não é atribuído; '
  '"Ticket médio"/média ficam fora também no modo por rótulo.';

grant execute on function fn_somar_faturamento_ano(uuid, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Catálogo da sonda — requisitos de CORPO (marcador é código, não comentário).
-- ORDEM 852, 853: a 0196 usa até 851.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, porque, severidade, ordem) values

  ('faturamento_mes_na_coluna', '0197', 'corpo', 'fn_somar_faturamento_ano',
   'group by chave, mes_da_coluna',
   'Sem este corpo o faturamento com o mês na COLUNA (chave "Faturamento", colunas jan/2024…) soma 0 meses '
   'e a receita fica sem conferência com o motivo FALSO "o Faturamento não traz linha mensal deste ano". '
   'MEDIDO EM PRODUÇÃO (30/09/2026, só-leitura): v20-v23, v27, v28, v29, v40 e Canastra somam 0 meses nos anos com coluna mês/ano (9 documentos, 2 a 3 anos cada), apesar de os 12 meses estarem na coluna; a receita desses casos fica sem conferência com o motivo falso.',
   'importante', 852),

  ('faturamento_sem_ticket_medio', '0197', 'corpo', 'fn_somar_faturamento_ano',
   '(^|[^a-z])(medio|media)s?([^a-z]|$)',
   'Sem este corpo a linha "Ticket médio por pedido 2024" (forma normalizada "medio", que o %médi% da 0196 '
   'nunca casou) entra na soma do faturamento no modo por rótulo: 38,2 no lugar de 0 meses. '
   'MEDIDO EM PRODUÇÃO (30/09/2026, só-leitura): v24 tem "Ticket Médio por Pedido 2024/2025" somado como faturamento (38,2 e 31,4, 1 "mês").',
   'importante', 853)

on conflict (chave) do update
  set migration = excluded.migration,
      tipo      = excluded.tipo,
      objeto    = excluded.objeto,
      marcador  = excluded.marcador,
      porque    = excluded.porque,
      severidade = excluded.severidade,
      ordem     = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0197', revisado_em = current_date,
       observacao = 'A 0197 reemite fn_somar_faturamento_ano: a coluna "mês/ano" do ano pedido conta como mês '
         'mesmo com rótulo genérico (achado da revisão da 0196), e "Ticket médio"/média ficam fora também no '
         'modo por rótulo (o %médi% da 0196 era código morto). Catalogada pelo corpo '
         '(faturamento_mes_na_coluna, faturamento_sem_ticket_medio) — a assinatura não muda.'
 where id = true;
