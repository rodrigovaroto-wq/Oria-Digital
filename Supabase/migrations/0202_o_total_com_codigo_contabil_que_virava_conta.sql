-- =============================================================================
-- 0202 — O TOTAL COM CÓDIGO CONTÁBIL NA FRENTE QUE VIRAVA CONTA
--
-- O DEFEITO (medido no arnês de variações, variante `codigo_contabil_no_rotulo`, 05/10/2026).
-- `fn_papel_linha` ancora o prefixo `total|totais|subtotal|soma` no INÍCIO do rótulo normalizado. Balancete
-- e mapa de ERP trazem o código da conta na frente de quase toda linha, inclusive do TOTAL:
-- "2.3.71 TOTAL — saldo devedor" começa por "2.3.71", então o papel saía `conta` e a linha de TOTAL do
-- Mapa de Dívida virava uma tranche a mais. Medido: tranches 51.300 (o total) + 51.300 (as nove contas) =
-- 102.600 de dívida existente onde o documento diz 51.300; a dívida de curto prazo de 2024 saiu 46.924
-- contra 23.462 sem o código. O saldo dobrado era amortizado em 3 anos, o caixa não cobria, o revolver
-- engolia a diferença e a dívida "evaporava de 11.114 para 0 entre J e K, amortização 0" — dívida dobrada
-- com cara de dívida (a dupla contagem, o defeito mais caro deste projeto, porque parece um número maior).
-- O mesmo vale para os outros grupos da função: "1.1.01 ATIVO CIRCULANTE" (b) e "1.2.05 Lucro líquido" (c),
-- porque o código também entra nos tokens estruturais ("1", "1", "01").
--
-- A CAUSA: o portal já tirava o código antes de comparar âncoras (`CODIGO_DE_CONTA_NO_INICIO` /
-- `chaveDeAncora`, modelo-institucional.ts); o BANCO, que é quem decide o papel e por onde passam todos
-- os chamadores, não. Um patch do portal que rebaixava o papel na entrada do modelo
-- (patches/s105-total-com-codigo-no-mapa-de-divida.patch) corrigia só uma das leituras: a tela de
-- modelagem, o realizado e as reconciliações leem o papel do BANCO.
--
-- A REGRA (comportamento): o papel de uma linha NÃO depende do código contábil que o ERP imprimiu na
-- frente do nome. `fn_sem_codigo_de_conta(rotulo)` tira do INÍCIO o mesmo código que o portal tira —
-- no mínimo três grupos numéricos separados por ponto (`\d+(\.\d+){2,}`), com separador opcional
-- (- – — . )) — e só ele: "2.500 toneladas" (um ponto) e um número no meio do rótulo não são código.
-- Fica no rótulo que o arquivo imprime; só a COMPARAÇÃO do papel o ignora.
--
-- TETO CONHECIDO: o código com identificador numérico antes ("12388 1.1.5.01.007 TRANSFERENCIA…", o
-- balancete analítico) NÃO é reconhecido — o portal também não o reconhece, e o balancete é abertura
-- analítica, fora da soma do realizado (0150). Código com menos de três grupos ("1.1 Caixa") também não.
-- Número com separador de milhar no início do rótulo ("1.000.000 TOTAL") tem a forma do código e também
-- é tirado: rótulo que começa por quantia não é nome de conta.
-- E o prefixo `total` continua prefixo de QUALQUER rótulo (regra da 0042): "2.3.71 Total Imóveis Ltda"
-- é subtotal pela mesma razão que "Total Imóveis Ltda" era.
--
-- ASSINATURA IGUAL à da 0116 (3 argumentos, `immutable`); `create or replace` basta. REEMITIDA INTEIRA.
-- CHAMADORES de fn_papel_linha (corpo vigente no banco; grep em pg_proc.prosrc e em Supabase/ N8N/
-- portal/src portal/scripts Verificação): fn_linhas_para_modelagem, fn_linhas_do_realizado,
-- fn_papel_do_rotulo_no_caso, fn_sazonalidade_do_caso, fn_conferir_arvore, fn_conflitos_do_caso (e
-- _v0151), fn_pares_duplicados_do_caso, fn_reconciliar_intragrupo, fn_reconciliar_mutuos,
-- fn_saldo_mutuos_linhas, fn_classe_contabil_sugerir. O portal só a cita em comentário. Todos leem o
-- papel: a linha de TOTAL com código deixar de ser conta é o comportamento pedido em todos — nenhum
-- deles deve tratar "2.3.71 TOTAL" como conta. Linha que ERA conta e passa a subtotal some da lista de
-- premissas da tela (ela não é projetável) e deixa de entrar em soma do realizado.
--
-- NÃO FAZ: não regrava modelagem nem premissa de caso nenhum (o papel é calculado na leitura); não é
-- aplicada por estar escrita — quem responde é a sonda contra o banco em que se está conectado:
--
--   select chave, migration, tipo, objeto, presente, detalhe, porque
--     from fn_instalacao_conferir() where not presente order by 1;
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/papel_total_com_codigo_contabil.test.sql — 21 asserts;
-- com a fn_papel_linha da 0116 de volta (correção desligada) reprovam 13 (e a soma das contas do mapa dá 102.600,
-- o número do arnês); tokens sem tirar o código, 1; texto sem tirar o código, 11; regex exigindo 4 grupos, 12;
-- regex aceitando 2 grupos (casa "1.1"), 1 — os dois lados da definição de código estão medidos.
-- =============================================================================

create or replace function fn_sem_codigo_de_conta(p_rotulo text)
returns text language sql immutable as $$
  -- A MESMA definição de `CODIGO_DE_CONTA_NO_INICIO` (portal/src/lib/modelo-institucional.ts).
  select regexp_replace(coalesce(p_rotulo, ''), '^\s*\d+(?:\.\d+){2,}\s*[-–—.)]?\s*', '')
$$;

comment on function fn_sem_codigo_de_conta(text) is
  'Tira do INÍCIO do rótulo o código contábil do ERP ("2.3.71 TOTAL" -> "TOTAL"): três grupos numéricos ou mais separados por ponto, separador opcional. A mesma definição de CODIGO_DE_CONTA_NO_INICIO do portal (0202).';

grant execute on function fn_sem_codigo_de_conta(text) to authenticated;

create or replace function fn_papel_linha(
  p_chave          text,
  p_tipo_taxonomia text default null,
  p_unidade        text default null
) returns text language sql immutable as $$
  -- marca-0202
  with n as (
    -- 0202: o CÓDIGO CONTÁBIL do ERP na frente do rótulo ("2.3.71 TOTAL — saldo devedor") não é
    -- parte do nome: sem tirá-lo, o prefixo `total` não está mais no INÍCIO e o TOTAL vira conta.
    select fn_normalizar_texto(fn_sem_codigo_de_conta(p_chave)) as t,
           fn_tokens_estruturais(fn_sem_codigo_de_conta(p_chave)) as toks
  )
  select case
    -- ---- DERIVADO: indicador gerencial, não dinheiro ------------------------
    when (select t from n) ~ '^(indice|indices) '
      or (select t from n) ~ '^media (mensal|diaria|anual)'
      or (select t from n) ~ '^ticket medio'
      or (select t from n) ~ '^prazo medio'
      or (select t from n) ~ '^(margem|rentabilidade|retorno) '
      or (select t from n) ~ '^capital circulante liquido'
      or (select t from n) ~ '^(giro|rotacao) (de|do|da) '
      or (select t from n) ~ 'indicador gerencial'
      then 'derivado'

    -- ---- SÉRIE MENSAL: insumo da curva de sazonalidade ----------------------
    when p_tipo_taxonomia = 'FATURAMENTO_24M' and fn_mes_do_rotulo(p_chave) is not null
      then 'serie_mensal'

    -- ---- SUBTOTAL: já é a soma de outras linhas -----------------------------
    -- (a) prefixo "total"/"subtotal"/"soma"
    when (select t from n) ~ '^(total|totais|subtotal|soma) ' or (select t from n) in ('total','totais','subtotal')
      then 'subtotal'
    -- (b) o total do grupo SEM a palavra "total" (0034), agora contra os tokens
    --     já calculados. Arrays em ordem alfabética — é igualdade de array.
    when (select toks from n) in (
        array['ativo'],
        array['passivo'],
        array['patrimonio'],
        array['passivo','patrimonio'],
        array['ativo','circulante'],
        array['ativo','circulante','nao'],
        array['circulante','passivo'],
        array['circulante','nao','passivo'],
        array['longo','prazo','realizavel'])
      then 'subtotal'
    -- (c) as linhas de RESULTADO da DRE e os subtotais do Fluxo, lista fechada
    when (select t from n) in (
        'receita operacional liquida','receita liquida','receita liquida de vendas',
        'lucro bruto','prejuizo bruto',
        'resultado operacional antes do resultado financeiro',
        'resultado antes dos tributos sobre o lucro','resultado antes dos tributos',
        'lucro liquido do exercicio','prejuizo liquido do exercicio',
        'lucro liquido','prejuizo liquido','resultado do exercicio',
        'resultado financeiro liquido','resultado financeiro')
      then 'subtotal'
    -- (c2) 0116: o TOPO da DRE, que só passa a chegar agora que o total
    --      impresso vira linha. A forma longa ("receita operacional bruta") é o
    --      cabeçalho do bloco de receita na estrutura completa — o valor dela é
    --      a soma das receitas por segmento/produto que vêm abaixo.
    when (select t from n) in (
        'receita operacional bruta','receitas operacionais brutas',
        'receita bruta operacional',
        'deducoes da receita bruta','deducoes da receita',
        'resultado antes do resultado financeiro',
        'resultado operacional')
      then 'subtotal'
    -- (c3) 0116: os totais da DVA. A DVA é feita de blocos que terminam em
    --      total ("Valor adicionado bruto", "Valor adicionado líquido
    --      produzido", "Valor adicionado total a distribuir") e a distribuição
    --      repete o mesmo montante por destinatário — contar o total junto com
    --      os destinatários dobra a demonstração inteira.
    when (select t from n) in (
        'valor adicionado bruto',
        'valor adicionado liquido produzido','valor adicionado liquido',
        'valor adicionado recebido em transferencia',
        'valor adicionado total a distribuir','valor adicionado a distribuir',
        'valor adicionado total','distribuicao do valor adicionado')
      then 'subtotal'
    when (select t from n) ~ '^caixa liquido (gerado|aplicado|gerado pelas)'
      or (select t from n) ~ '^(aumento|reducao|variacao) liquida? (de|do|da) caixa'
      then 'subtotal'

    else 'conta'
  end;
$$;

comment on function fn_papel_linha(text, text, text) is
  'Papel da linha na modelagem: conta | subtotal | derivado | serie_mensal. Lista FECHADA de padrões (não heurística de semelhança) porque errar para subtotal esconde conta de verdade e errar para conta deixa passar dupla contagem. 0102: tokeniza o rótulo uma vez e compara os nove grupos contra o resultado, em vez de nove chamadas a fn_rotulo_estrutural. 0116: cobre o topo da DRE e os totais da DVA, que só passam a chegar depois de o prompt exigir o total IMPRESSO como linha. 0202: o código contábil do ERP na frente do rótulo ("2.3.71 TOTAL") não conta — o papel é o do nome.';

grant execute on function fn_papel_linha(text, text, text) to authenticated;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, porque, severidade, ordem) values
  ('papel_total_com_codigo_contabil', '0202', 'corpo', 'fn_papel_linha',
   'fn_sem_codigo_de_conta',
   'Sem este corpo a linha de TOTAL com código contábil na frente ("2.3.71 TOTAL — saldo devedor") sai como conta e '
   'DOBRA a dívida do Mapa de Dívida. MEDIDO no arnês de variações (codigo_contabil_no_rotulo): 102.600 onde o '
   'documento diz 51.300; CP 2024 46.924 contra 23.462; "a dívida evapora de 11.114 para 0 entre J e K".',
   'importante', 860)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, porque = excluded.porque,
      severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0202', revisado_em = current_date,
       observacao = 'A 0202 reemite fn_papel_linha: o código contábil do ERP na frente do rótulo ("2.3.71 TOTAL") '
         'deixa de esconder o prefixo total/os grupos estruturais, via fn_sem_codigo_de_conta (mesma definição do '
         'portal). Medido no arnês de variações (dívida 102.600 onde o documento diz 51.300). Catalogada pelo corpo '
         '(papel_total_com_codigo_contabil).'
 where id = true;
