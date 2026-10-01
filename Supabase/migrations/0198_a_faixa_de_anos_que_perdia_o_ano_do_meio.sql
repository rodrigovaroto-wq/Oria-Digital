-- =============================================================================
-- 0198 — A FAIXA DE ANOS QUE PERDIA O ANO DO MEIO
--
-- O DEFEITO (30/09/2026, achado da revisão independente, confirmado em produção).
-- `fn_anos_periodo('multi', '2024-2026')` devolve {2024,2026} e PERDE 2025: a função
-- (0022) só junta os números de 4 dígitos que aparecem no texto, e uma FAIXA "AAAA-AAAA"
-- tem as duas pontas e nenhum meio. O Mapa de Dívida do caso KRAUSPENHAR E HARTMANN tem
-- exatamente esse período ("multi 2024-2026"); quando o Endividamento for reenviado, a
-- despesa financeira de 2025 diria "o Mapa de Dívida é de 2024-2026 — não há juros deste
-- exercício", o que é falso. A 0196 herda o defeito (fn_linha_vale_para_ano, para documento
-- sem coluna com período em faixa), e também a 0191 (corte do Mapa).
--
-- CORREÇÃO (REEMITIDA INTEIRA, nunca por replace): quando a referência CANÔNICA é, por inteiro,
-- "AAAA-AAAA" (também com "a"/"ate"/"até"/travessão entre os dois anos, já sem espaços pela
-- fn_periodo_canonico), devolve TODOS os anos da faixa. Uma LISTA ("2024, 2026", que a
-- canônica escreve "2024,2026") segue devolvendo só os listados: a vírgula nunca é faixa.
-- NÃO expande, e mantém o comportamento antigo, quando a faixa é ambígua: fim antes do
-- início ("2026-2024") ou mais de 10 anos de extensão (provável erro de extração); faixa de
-- 2 dígitos ("24-26", que colide com MM-AA); e datas ("2025-03", "2024-12-31",
-- "01/01/2025 - 30/06/2025" — os dois lados são data, e a canônica não casa a faixa inteira).
--
-- MEDIDO EM PRODUÇÃO (30/09/2026, SOMENTE LEITURA), `select distinct tipo, referencia from periodo`:
--   • 100 referências distintas; só 2 casam a faixa "AAAA-AAAA": "multi 2024-2025" (1 período;
--     {2024,2025} antes e depois — uma faixa de dois anos não tem meio) e "multi 2024-2026"
--     (1 período; {2024,2026} -> {2024,2025,2026}). ÚNICO período que muda de conjunto.
--   • Esse período é o do KRAUSPENHAR E HARTMANN (63340de0…), com 1 documento, o MAPA_DIVIDA,
--     hoje com 0 campos extraídos, e 4 reconciliações gravadas (ativo_passivo_pl 1, despfin 3),
--     as 4 `precondicao_nao_satisfeita / sem_periodo_par`. Elas NÃO são regravadas por esta
--     migration (sem backfill); na próxima rodada: o laço por ano (fn_anos_alvo) de
--     despfin, ativo_passivo_pl, mútuos, espelho intragrupo, caixa e receita passa a incluir 2025;
--     e fn_periodos_compativeis passa a considerar o período 2024-2026 compatível com o
--     "anual 2025" do mesmo caso (DRE e Balanço de 2025), que antes era incompatível
--     ({2024,2026} ∩ {2025} = vazio) — é isso que deixa a despfin de 2025 achar a DRE de 2025.
--     Dos períodos do caso, 2024, 2026 e "01/01/2026 a 31/08/2026" já eram compatíveis.
--
-- ACHADO FORA DO ESCOPO, NÃO CORRIGIDO (ver o relatório da sessão): listas de 2 dígitos que não são
-- anos. Em produção `multi 02,25` (5 períodos), `03,25` (5), `01,24,25` (5), `06,25`, `08,25`, `12,25`,
-- `13,25`, `12,01`, `22,07,26` viram {2002,2025}, {2003,2025}, {2001,2024,2025}... porque a
-- fn_periodo_canonico lê "02" como o ano 2002 — e o laço por ano passa a tentar 2002. Não sei o que
-- "02,25" quer dizer (entidade? mês?), então não adivinhei: comportamento mantido.
--
-- CHAMADORES de fn_anos_periodo (grep em Supabase/ N8N/ portal/src/; N8N/ e portal/src/ não chamam):
-- fn_periodos_equivalentes e fn_periodos_compativeis (0022), fn_anos_alvo (0023), o corte do Mapa em
-- fn_reconciliar_despfin_dre_vs_divida (0191, 0196) e fn_linha_vale_para_ano (0195), usada por mútuos
-- (0194), espelho intragrupo (0195), caixa, receita e despfin (0196). Todos leem o CONJUNTO de anos;
-- ganhar o ano do meio é o comportamento pedido em todos.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/faixa_de_anos_do_periodo.test.sql, 9 asserts
-- (contados no log); com a 0198 fora, 4 reprovam. Ver a mensagem do commit.
--
-- NÃO FAZ: não roda reconciliação nem recompute em caso nenhum; não é aplicada por estar escrita —
-- quem responde é a sonda contra o banco em que se está conectado:
--
--   select chave, migration, tipo, objeto, presente, detalhe, porque
--     from fn_instalacao_conferir() where not presente order by 1;
-- =============================================================================

create or replace function fn_anos_periodo(p_tipo text, p_ref text)
returns int[]
language plpgsql
immutable
as $$
declare
  canonico text := fn_periodo_canonico(p_tipo, p_ref);
  anos int[] := '{}';
  tok text;
  m text[];
begin
  if canonico is null then return anos; end if;
  -- 0198: FAIXA "AAAA-AAAA" (ou "AAAAaAAAA", "AAAA–AAAA") inteira = todos os anos dela. Só quando
  -- é crescente e de até 10 anos; fora disso cai no comportamento antigo (as pontas).
  m := regexp_match(canonico, '^((?:19|20)[0-9]{2})(?:-|–|—|a|ate|até)((?:19|20)[0-9]{2})$');
  if m is not null and m[2]::int >= m[1]::int and m[2]::int - m[1]::int <= 10 then
    return array(select generate_series(m[1]::int, m[2]::int));
  end if;
  -- anos de 4 dígitos explícitos (cobre ISO, ano isolado, listas já expandidas)
  foreach tok in array regexp_split_to_array(canonico, '[^0-9]+') loop
    if tok ~ '^(19|20)[0-9]{2}$' then
      anos := anos || (tok)::int;
    end if;
  end loop;
  select array_agg(distinct a order by a) into anos from unnest(anos) a;
  return coalesce(anos, '{}'::int[]);
end;
$$;

comment on function fn_anos_periodo(text, text) is
  'Conjunto ordenado de anos implícito num período (qualquer notação). Vazio quando a referência não ancora ano. 0198: a FAIXA "AAAA-AAAA" devolve todos os anos dela (2024-2026 = 2024, 2025, 2026); a lista "2024,2026" devolve só os listados.';

grant execute on function fn_anos_periodo(text, text) to authenticated;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, porque, severidade, ordem) values
  ('anos_do_periodo_em_faixa', '0198', 'corpo', 'fn_anos_periodo',
   'generate_series(m[1]::int, m[2]::int)',
   'Sem este corpo "multi 2024-2026" vale {2024,2026} e perde 2025: o Mapa de Dívida do Krauspenhar '
   '(único período em faixa de 3 anos em produção, 30/09/2026, só-leitura) diria que não há juros de 2025 e '
   'o "anual 2025" do caso seria incompatível com ele.',
   'importante', 854)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, porque = excluded.porque,
      severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0198', revisado_em = current_date,
       observacao = 'A 0198 reemite fn_anos_periodo: a faixa "AAAA-AAAA" devolve todos os anos dela (perdia o '
         'ano do meio). Medido em produção (30/09/2026, só-leitura): 1 período muda de conjunto (multi 2024-2026, '
         'Krauspenhar). Catalogada pelo corpo (anos_do_periodo_em_faixa); a assinatura não muda.'
 where id = true;
