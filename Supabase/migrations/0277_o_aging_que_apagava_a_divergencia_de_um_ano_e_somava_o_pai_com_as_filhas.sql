-- =============================================================================
-- 0277 — O AGING QUE APAGAVA A DIVERGÊNCIA DE UM ANO E SOMAVA O PAI COM AS FILHAS: os 3 ALTOS e 3 médios da revisão independente da conciliação
--        do aging da 0274 (sessão 127b, 12/11/2026). A 0274 já estava em produção (tabela vazia: nenhum aging importado ainda), então nada foi
--        conciliado errado: esta migration chega antes da primeira carteira. NUMERAÇÃO: o dono pediu 0277 (a 0275 ficou livre de propósito e a 0276
--        é de outra branch).
-- (Cria 1 função, 1 CHECK, 1 view da sonda. Recria 1 função (muda o tipo de retorno) e reemite 2. Nenhum backfill: aging_importado tinha 0 linhas
--  em produção em 12/11/2026, medido por leitura.)
--
-- O DEFEITO E A CAUSA, MEDIDOS EM PRODUÇÃO (leitura, 12/11/2026; nenhuma escrita)
--
--  ALTO 1 — O ok de um ano resolvia a divergência de outro. fn_reconciliar_aging passava a fn_registrar_reconciliacao o `periodo_id` DO DOCUMENTO.
--    Num balanço comparativo (período "multi 24,25") as carteiras de 31/12/2024 e 31/12/2025 caíam na MESMA pendência (a busca é por período
--    compatível = anos que se intersectam, 0022), e fn_reconciliar_aging_do_caso visita por data-base crescente: o ok do ano novo apagava a
--    divergência do velho. Produção: 188 BALANCO e 18 COMBINADO com colunas de mais de um ano. CORREÇÃO: o período da reconciliação é o da CARTEIRA:
--    ('data-base', 'AAAA-MM-DD'), a notação que o mapa de dívida já usa e que fn_anos_periodo lê como {ano}. O período é FABRICADO por
--    fn_reconciliar_aging quando não existe (nenhum documento o trouxe) e a pendência o carrega (a tela mostra "data-base 2024-12-31", não um
--    período que pareça vindo de documento). EFEITO DECLARADO: (a) o mandato ganha uma linha em `periodo` por data-base conciliada; (b) ela entra
--    nos laços de períodos compatíveis das checagens clássicas (fn_periodos_compativeis_array), que só tentam o período seguinte quando o anterior
--    deu pré-condição: o teste mede que o resultado por tipo e a contagem de pendências das checagens clássicas NÃO mudam depois de importar aging
--    (balanço comparativo, fn_reconciliar_caso antes e depois); (c) não reemite fn_registrar_reconciliacao (função quente, 0241): nada na 0277 a toca.
--    TETO (1) DA 0274, QUE CONTINUA E ESTÁ MEDIDO: duas datas-base do MESMO ano (31/12 e 30/06 de 2025) compartilham a pendência (os anos se
--    intersectam: o remédio seria um tipo por data-base dentro de fn_registrar_reconciliacao). Dentro de uma mesma transação a guarda da 0192 segura
--    a divergência irmã; entre transações, não. Sobe quando houver carteira trimestral/mensal de verdade.
--
--  ALTO 2 — Pai e filhas de Fornecedores/Clientes somavam em dobro. A regra "o pai vale sozinho" dependia de `secao` da filha = nome do pai; a
--    forma real em produção é pai e filhas com a MESMA `secao` ("Passivo Circulante") ou `secao` nula, o pai imediatamente antes das filhas e com o
--    valor igual à soma exata delas ("Fornecedores" 24.549 = 16.843 + 3.600 + 4.106; "Fornecedores" 1.892 = a filha única 1.892). Rodando a própria
--    fn_aging_linhas_do_balanco da 0274 em todo grupo (documento × coluna de entidade × coluna de período) de produção, devolviam pai E filhas:
--    Fornecedores BALANCO 215 grupos (24 mandatos), COMBINADO 26 (8), BALANCETE 6 (3); Clientes BALANCETE 20 (3), BALANCO 5 (2), COMBINADO 10 (2).
--    Mais um fato medido que a tarefa não trazia: 146 das 1.648 versões de documento têm `ordem` NULA em alguma linha (5.919 de 138.931 linhas),
--    então a contiguidade por ordem sozinha não resolve. CORREÇÃO, pela ESTRUTURA (em fn_aging_linhas_do_balanco, que passa a devolver `aviso`):
--      (i) PELO NOME: a linha cujo nome contém todas as palavras do pai (pelos 7 primeiros caracteres: fornecedor = fornecedores) e mais alguma é
--          filha dele. Pai que é a soma delas (meia unidade da escala por linha: (escala do pai + Σ escalas das filhas) / 2) é subtotal e vale
--          SOZINHO; pai que as filhas COBREM EM PARTE (valor maior que a soma e do mesmo sinal: a extração não trouxe todas as filhas) também vale
--          sozinho e AVISA; pai que as filhas EXCEDEM não é subtotal;
--      (ii) PELA ORDEM, só para o pai de nome de manual (Clientes, Fornecedores, Duplicatas a receber, com código de plano de contas na frente):
--          as até 6 linhas seguintes, quando a soma das primeiras k fecha com ele ("Clientes" seguido de duas duplicatas de nomes próprios);
--      (iii) a mesma conta com dois nomes de manual ("CLIENTES" e "DUPLICATAS A RECEBER" com o valor idêntico ao centavo, na mesma escala) vale uma vez;
--      e a regra antiga (filha com `secao` = nome do pai; pai líquido cede às filhas) continua como estava.
--    O QUE ACONTECE QUANDO O PAI NÃO FECHA (decisão declarada, não silenciosa): (a) cobre em parte: o PAI vale sozinho, e a descrição da conciliação diz
--    "entrou sozinho: as N linhas ... somam X e cobrem só parte dos Y; se o resto é de linhas que a extração não trouxe, o valor está certo; se o pai é
--    uma conta própria, está subestimado"; (b) excede: TODAS as linhas entram (o status quo da 0274) e a descrição diz que pode estar em dobro; (c) escala
--    desconhecida: nada se compara (a conciliação já devolve unidade_divergente); (d) valores idênticos com nomes que não são de manual: avisa "se são a
--    mesma conta com dois nomes, a soma está em dobro". O aviso vai na descrição da conciliação, `ok` ou divergente (Atenção na leitura do balanço).
--    TETO: uma hierarquia (pai e filhas; neto não). Pai com subfamílias dentro (Fornecedores > nacionais > em atraso) raramente fecha e cai em (b) com
--    o aviso. A medição em produção (corpus de 12/11 carregado num banco local e as DUAS funções, a da 0274 e a nova, rodadas sobre os mesmos grupos):
--      enumeração da tarefa (todo par distinto de colunas do documento): grupos com pai e filhas ANTES 282 (215+26+6+20+5+10, reproduz os números acima) →
--        DEPOIS 7 (Fornecedores COMBINADO 6 em 3 mandatos, quase todos de escala ausente, que dá unidade_divergente; Clientes COMBINADO 1);
--      enumeração dos grupos REAIS (a coluna nula só para versão sem nenhuma linha com coluna preenchida, que é como a conciliação chama): 280 → 5;
--      pai que NÃO fecha com as filhas e AVISA: 45 grupos de "cobre em parte" (39 de Fornecedores BALANCO, 6 de Fornecedores BALANCETE), 1 a 3 de "excede"
--      (1 em Clientes BALANCO; 2 em Fornecedores COMBINADO só na enumeração da tarefa), 3 de valor repetido.
--
--  ALTO 3 — Balanço que só existe como coluna de um combinado de OUTRA empresa virava documento_ausente (sem pendência): o laço filtrava
--    `d.entidade_id = a.entidade_id`. Produção: 145 pares (entidade, combinado alheio) em que fn_coluna_entidade acha a coluna; 12 entidades em 3
--    mandatos não têm balanço próprio nenhum. CORREÇÃO: entra também o documento do caso cuja coluna fn_coluna_entidade resolve para esta entidade
--    (nunca nulo nem o sentinela \x01: documento sem colunas de entidade de outra empresa NÃO vale, por palpite nenhum). ORDEM: (1) o documento da
--    PRÓPRIA entidade, (2) o de outra empresa na coluna dela; dentro de cada, BALANCO > COMBINADO > BALANCETE e o mais novo. O próprio vem primeiro
--    porque é a demonstração da empresa, e a coluna de um combinado é uma leitura derivada (pode trazer ajustes de consolidação). A descrição e
--    fonte_b dizem de quem é o documento e a coluna lida ("[balanço lido: COMBINADO de Grupo Holding, na coluna ..., outra empresa do grupo]").
--
--  MÉDIOS
--   * LADO DO BALANÇO: conta de ESTOQUE com "cliente"/"fornecedor" no rótulo casava ("MERCADORIA EM GARANTIA/CONSERTO A RECEBER(FORNECEDOR)"). Medido
--     (linhas que casam o rótulo, em produção): Fornecedores com secao_canonica ativo_circulante 28 (todas com seção ESTOQUE), ativo_nao_circulante 15,
--     atividades_operacionais 11; Clientes com secao ESTOQUE 40 e secao_canonica passivo_circulante 10; Adiantamentos de clientes em ativo_circulante 4.
--     Agora: a linha entra só se a secao_canonica é a do lado do conceito (Clientes e Adiantamentos a fornecedores: ativo_circulante; Fornecedores e
--     Adiantamentos de clientes: passivo_circulante) OU é NULA, e se a seção em texto não diz "estoque". secao_canonica NULA (67 linhas: 31 de Clientes,
--     36 de Fornecedores, em 14 e 12 versões) NÃO exclui nada: a linha fica, o rótulo é o único filtro (teto declarado). Se a IA classificou errado o
--     lado de uma conta legítima, ela vira linha_nao_localizada (visível, com o valor), nunca zero.
--   * O RESUMO AMARRADO AO APLICADOR: a 0274 validava resumo e aplicador cada um por si; nada garantia que o resumo era do arquivo que o aplicador
--     leu. fn_aging_aplicador_erros (usada por fn_aging_importar e pela CHECK aging_resumo_e_aplicador, que cobre o service_role) exige: titulo do
--     aplicador = resumo.titulos; saldo_titulos = positivos.saldo + negativos.saldo; titulos_com_saldo_negativo (linhas, saldo) = negativos; e a
--     identidade do resumo titulos = positivos + negativos + liquidados (Leitor/lib/aging.mjs e Leitor/lib/mapeamento.mjs, lidos em 12/11/2026).
--     Campo ausente no aplicador é erro dito, nunca passa por zero. LIMITE: o banco compara o que o navegador diz; não relê o arquivo.
--   * BALANCETE QUE NUNCA "FECHA" (fn_balanco_fecha_em nulo): MEDIDO, NÃO CORRIGIDO. Em produção os 192 BALANCETE devolvem NULL (192 de 192): 49 porque o
--     período do documento é "parcial" (o tipo BALANCETE é parcial por doutrina, 0199/0200, mesmo com referência 12M25) e 143 porque o balancete tem
--     colunas de período sem o ano ("Saldo Anterior", "Débito", "Crédito", "Saldo Atual") e a 0234 não herda o ano em documento parcial. Dar a data seria
--     palpite: a referência de um balancete diz o período, não que ele fecha o exercício, e escolher a coluna "Saldo Atual" é decisão da 0234, que esta
--     migration não reabre. EFEITO (já visível na 0274): carteira conciliada com BALANCETE vira sem_periodo_par, com o motivo; só BALANCO e COMBINADO
--     concilia.
--
-- FORA, por pedido (não feito): ACL de default privileges, tela/mapeamento global, ligar fn_reconciliar_aging_do_caso em fn_reconciliar_caso.
--
-- A SONDA (7 requisitos, ordem 1354-1360): a função do validador, o corpo da importação (amarra o aplicador), o corpo da conciliação (o período da
-- carteira; o balanço do grupo), o corpo das linhas (o pai que fecha; o lado do balanço) e a view da CHECK.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/o_aging_que_apagava_a_divergencia_de_um_ano_e_somava_o_pai_com_as_filhas.test.sql — 46 asserts
--   (medido: 46 chamadas, 46 execuções, nenhum em laço; reconferido com Supabase/test/medicao-denominador.test.mjs). Cada correção desligada UMA por vez DENTRO
--   de uma transação (a sabotagem recompõe a função por pg_get_functiondef e ABORTA se o trecho não existe: nenhuma variante deixou de aplicar), o teste inteiro
--   com o assert em `raise warning` (ct77.medindo=on; voltou para `raise exception`; log lido atrás de FALHOU) e a transação desfeita. Controle (migration
--   intacta): 0 dos 46 asserts reprovam, 46 execuções. O teste da 0274 (153 asserts) segue verde com os fixtures do aplicador coerentes (helper
--   teste_aplicador_0274; nenhum assert mudou de valor esperado). Por correção desligada (12/11/2026):
--   * ALTO 1, período do documento em vez da data-base: 5 dos 46 asserts reprovam;
--   * ALTO 3, só o documento da própria entidade: 3 dos 46 · sem a preferência pelo próprio: 2 dos 46;
--   * ALTO 2, pai que fecha não vale sozinho: 2 dos 46 · pai que cobre em parte: 2 dos 46 · sem a janela por ordem: 1 dos 46 · sem o mesmo valor com dois
--     nomes: 1 dos 46 · sem o parentesco pelo nome (tudo de (i)): 5 dos 46 · o aviso fora da descrição: 2 dos 46;
--   * médios, sem o lado do balanço (secao_canonica): 1 dos 46 · sem a seção de estoque: 1 dos 46 · importar sem amarrar o aplicador: 7 dos 46 · sem a CHECK
--     da tabela: 3 dos 46 · os dois: 9 dos 46;
--   * o validador, uma regra por vez: títulos 2 dos 46 · soma dos saldos 1 · negativos (linhas) 1 · negativos (saldo) 1 · identidade do resumo 1 ·
--     aplicador sem o campo 1.
--   Os asserts de controle (balanço próprio, forma antiga, duas contas irmãs, as checagens clássicas intocadas, o TETO do mesmo ano) passam em todas as variantes:
--   protegem o que não pode mudar. Regra 4: as FORMAS dos fixtures são as lidas em produção; os números de aging são montados (não há arquivo de aging real: DM7).
-- =============================================================================
begin;

-- ---------------------------------------------------------------------------
-- 1. O RESUMO AMARRADO AO APLICADOR (fronteira de confiança): nada na 0274 ligava um ao outro
-- ---------------------------------------------------------------------------
create function fn_aging_aplicador_erros(p_resumo jsonb, p_aplicador jsonb) returns text[]
language plpgsql immutable set search_path = public, pg_temp as $$
declare
  e       text[] := '{}';
  v_tit   numeric;
  v_ap_t  numeric; v_ap_s numeric; v_ap_nl numeric; v_ap_ns numeric;
  v_r_pos_t numeric; v_r_neg_t numeric; v_r_liq numeric;
  v_pos_s numeric; v_neg_saldo numeric;
begin
  -- Objeto que não é objeto, ou resumo que não fecha consigo mesmo, é de fn_aging_resumo_erros e do teste de objetos: aqui só o que AMARRA os dois.
  if jsonb_typeof(p_resumo) is distinct from 'object' or jsonb_typeof(p_aplicador) is distinct from 'object' then
    return e;
  end if;
  v_tit      := fn_aging_contagem(p_resumo -> 'titulos');
  v_r_pos_t  := fn_aging_contagem(p_resumo #> '{positivos,titulos}');
  v_r_neg_t  := fn_aging_contagem(p_resumo #> '{negativos,titulos}');
  v_r_liq    := fn_aging_contagem(p_resumo -> 'liquidados');
  v_pos_s    := fn_aging_centavos(p_resumo #> '{positivos,saldo}');
  v_neg_saldo := fn_aging_centavos(p_resumo #> '{negativos,saldo}');
  -- A identidade da própria biblioteca (Leitor/lib/aging.mjs, titulo(): todo título conta em `titulos`; saldo zero é liquidado; o resto é positivo ou negativo).
  if v_tit is not null and v_r_pos_t is not null and v_r_neg_t is not null and v_r_liq is not null and v_tit <> v_r_pos_t + v_r_neg_t + v_r_liq then
    e := e || format('resumo.titulos (%s) diferente de positivos (%s) + negativos (%s) + liquidados (%s): título que sumiu do resumo', v_tit, v_r_pos_t, v_r_neg_t, v_r_liq);
  end if;
  -- O que o APLICADOR (Leitor/lib/mapeamento.mjs) entregou à biblioteca tem de ser o que o resumo contou. Sem o campo, a ausência é dita: o banco não
  -- aceita um resumo que ninguém pode amarrar ao arquivo.
  v_ap_t := fn_aging_contagem(p_aplicador -> 'titulo');
  if v_ap_t is null then
    e := e || 'o aplicador não diz quantos títulos aplicou (titulo: contagem inteira): o resumo não se amarra ao arquivo'::text;
  elsif v_tit is not null and v_ap_t <> v_tit then
    e := e || format('o resumo conta %s títulos e o aplicador aplicou %s: o resumo não é o deste arquivo', v_tit, v_ap_t);
  end if;
  v_ap_s := fn_aging_centavos(p_aplicador -> 'saldo_titulos');
  if v_ap_s is null then
    e := e || 'o aplicador não diz a soma dos saldos (saldo_titulos: centavos, em texto): o resumo não se amarra ao arquivo'::text;
  elsif v_pos_s is not null and v_neg_saldo is not null and v_ap_s <> v_pos_s + v_neg_saldo then
    e := e || format('a soma dos saldos do aplicador (%s) é diferente de positivos (%s) + negativos (%s) do resumo', v_ap_s, v_pos_s, v_neg_saldo);
  end if;
  v_ap_nl := fn_aging_contagem(p_aplicador #> '{titulos_com_saldo_negativo,linhas}');
  v_ap_ns := fn_aging_centavos(p_aplicador #> '{titulos_com_saldo_negativo,saldo}');
  if v_ap_nl is null or v_ap_ns is null then
    e := e || 'o aplicador não diz os títulos de saldo negativo (titulos_com_saldo_negativo: linhas e saldo): os créditos do resumo não se amarram ao arquivo'::text;
  else
    if v_r_neg_t is not null and v_ap_nl <> v_r_neg_t then
      e := e || format('o resumo tem %s títulos negativos e o aplicador %s', v_r_neg_t, v_ap_nl);
    end if;
    if v_neg_saldo is not null and v_ap_ns <> v_neg_saldo then
      e := e || format('o saldo negativo do resumo (%s) é diferente do do aplicador (%s)', v_neg_saldo, v_ap_ns);
    end if;
  end if;
  return e;
end $$;
comment on function fn_aging_aplicador_erros(jsonb, jsonb) is
  '0277: amarra o resumo do aging ao resumo do aplicador do mapeamento (Leitor/lib/mapeamento.mjs): titulo = resumo.titulos; saldo_titulos = positivos.saldo + negativos.saldo; titulos_com_saldo_negativo = negativos (linhas e saldo); e a identidade do próprio resumo titulos = positivos + negativos + liquidados. Campo ausente no aplicador é erro dito (nunca passa por zero). Devolve os motivos (vazio = coerente). Usado por fn_aging_importar e pela CHECK aging_resumo_e_aplicador; LIMITE: o banco compara o que o navegador diz, não relê o arquivo.';

alter table aging_importado add constraint aging_resumo_e_aplicador check (cardinality(fn_aging_aplicador_erros(resumo, aplicador)) = 0);
comment on constraint aging_resumo_e_aplicador on aging_importado is
  '0277: o resumo do aging e o do aplicador contam os mesmos títulos e os mesmos saldos (fn_aging_aplicador_erros vazio), para quem escrever sem passar pela função (service_role). Produção tinha 0 linhas em aging_importado em 12/11/2026: a CHECK valida sem backfill.';

-- ---------------------------------------------------------------------------
-- 2. AS LINHAS DO BALANÇO: O PAI QUE SOMAVA COM AS FILHAS E O LADO DO BALANÇO
-- ---------------------------------------------------------------------------
-- Muda o tipo de retorno (ganha `aviso`): a 0274 a criou com 5 colunas, e só a conciliação a chama (grep em Supabase/ N8N/ portal/src/ em 12/11/2026).
drop function fn_aging_linhas_do_balanco(uuid, text, text, text);
create function fn_aging_linhas_do_balanco(p_versao uuid, p_conceito text, p_col_ent text, p_col_per text)
returns table (id uuid, chave text, valor_num numeric, unidade text, secao text, aviso text)
language plpgsql stable set search_path = public, pg_temp as $$
#variable_conflict use_column
declare
  v_inc text;
  v_exc text;
  v_sc  text;
  c_ded constant text := 'perda|pecld|pdd|duvidos|provis|descontad|antecipa|ajuste a valor presente';
  -- 0277: o nome do PAI "de manual": só o conceito (com código de plano de contas na frente, "1.7 - Fornecedores"). Só ele pode ser subtotal de linhas
  -- que NÃO repetem o nome dele (Clientes, seguido de "Duplicatas a receber"), porque a janela por ordem não tem outra prova de parentesco.
  c_nome_pai constant text := '^([0-9][0-9. -]*)?(clientes|fornecedores|duplicatas a receber)$';
begin
  v_inc := case p_conceito
             when 'clientes'                     then 'cliente|duplicatas? a receber'
             when 'fornecedores'                 then 'fornecedor'
             when 'adiantamentos_de_clientes'    then 'adiant.*cliente'
             when 'adiantamentos_a_fornecedores' then 'adiant.*fornecedor' end;
  if v_inc is null then
    raise exception 'conceito "%" não existe (clientes, fornecedores, adiantamentos_de_clientes, adiantamentos_a_fornecedores)', p_conceito using errcode = '22023';
  end if;
  -- 0277: o lado do balanço em que o conceito mora. `secao_canonica` NULA não exclui nada (a IA não classificou: a linha fica, e só a seção em texto
  -- e o nome a filtram); preenchida e de outro lado, a linha não é do conceito (medido em produção, 12/11/2026: Fornecedores com secao_canonica
  -- ativo_circulante = 28 linhas, todas "MERCADORIA EM GARANTIA/CONSERTO A RECEBER(FORNECEDOR)" na seção ESTOQUE; Clientes idem, 40 linhas).
  v_sc := case p_conceito when 'clientes' then 'ativo_circulante' when 'adiantamentos_a_fornecedores' then 'ativo_circulante' else 'passivo_circulante' end;
  -- Fora, sempre: variações de fluxo, deduções (PDD, duplicatas descontadas, ajuste a valor presente), longo prazo e partes relacionadas.
  -- Clientes/Fornecedores também deixam de fora o que é Adiantamento (conta própria).
  v_exc := case when p_conceito in ('clientes', 'fornecedores') then 'adiant|' else '' end
           || 'variacao|aumento|reducao|' || c_ded || '|longo prazo|nao circulante|mutuo|partes relacionadas|coligad|controlad|imobilizado|salario|empregado|tributo|imposto|dividendo';
  return query
  with base as (
    select ce.id, ce.chave, ce.valor_num, ce.unidade, ce.secao, ce.confianca, ce.ordem,
           fn_normalizar_texto(ce.chave) as n, fn_normalizar_texto(ce.secao) as s
      from campo_extraido ce
     where ce.documento_versao_id = p_versao and ce.valor_num is not null
       and p_col_ent is distinct from E'\x01' and p_col_per is distinct from E'\x01'
       and (p_col_ent is null or fn_normalizar_texto(ce.entidade_coluna) = fn_normalizar_texto(p_col_ent))
       and (p_col_per is null or fn_normalizar_texto(ce.periodo_coluna) = fn_normalizar_texto(p_col_per))
       and (ce.secao_canonica is null or ce.secao_canonica = v_sc)
       and coalesce(fn_normalizar_texto(ce.secao), '') !~ 'estoque'
  ), cand as (
    select distinct on (b.n) b.* from base b where b.n ~ v_inc and b.n !~ v_exc
     order by b.n, coalesce(b.confianca, 0) desc, b.ordem nulls last, b.id
  ), liquido as (   -- pai cuja dedução (PDD, descontadas) é filha: o valor dele é LÍQUIDO, não o bruto que a conciliação quer
    select c.n from cand c where exists (select 1 from base d where d.s = c.n and d.n ~ c_ded)
  ), c2 as materialized (   -- o que sobra das duas regras antigas (0274): pai líquido cede aos filhos; filha com `secao` = nome do pai some
    select c.*, fn_fator_escala(c.unidade) as fator, c.valor_num * fn_fator_escala(c.unidade) as vb,
           array(select left(w, 7) from unnest(regexp_split_to_array(c.n, '[^a-z0-9]+')) w where w <> '') as tok   -- palavras, pelos 7 primeiros caracteres (fornecedor = fornecedores)
      from cand c
     where not exists (select 1 from cand p where p.n = c.s and p.n <> c.n and p.n not in (select n from liquido))
       and not (c.n in (select n from liquido) and exists (select 1 from cand f where f.s = c.n and f.n <> c.n))
  ), fam as materialized (   -- (i) PELO NOME: f é "filha" de p quando o nome de f contém todas as palavras do nome de p e mais alguma
    select p.id as pai, f.id as filha, f.vb, f.fator
      from c2 p join c2 f on f.id <> p.id and f.tok @> p.tok and not p.tok @> f.tok
  ), fam_soma as (
    select m.pai, count(*) as nf, sum(m.vb) as sv, sum(m.fator) as sf, bool_and(m.fator is not null) as completo
      from fam m group by m.pai
  ), fam_estado as (
    select s.pai, s.nf, s.sv, p.vb as vp,
           case when not (s.completo and p.fator is not null) then 'sem_escala'
                when abs(p.vb - s.sv) <= (p.fator + s.sf) / 2 then 'fecha'
                when (p.vb > 0 and s.sv >= 0 and p.vb > s.sv) or (p.vb < 0 and s.sv <= 0 and p.vb < s.sv) then 'cobre_parte'
                else 'excede' end as estado
      from fam_soma s join c2 p on p.id = s.pai
  ), seq as materialized (   -- (ii) PELA ORDEM: só o pai de nome de manual (Clientes, Fornecedores), e só onde a extração trouxe `ordem`
    select c.id, c.n, c.vb, c.fator, row_number() over (order by c.ordem, c.id) as rn from c2 c where c.ordem is not null
  ), jan as materialized (
    select p.id as pai, f.id as filha, f.rn - p.rn as k, p.vb as vp, p.fator as fp,
           sum(f.vb) over w as sv, sum(f.fator) over w as sf, bool_and(f.fator is not null) over w as completo
      from seq p join seq f on f.rn > p.rn and f.rn <= p.rn + 6
     where p.n ~ c_nome_pai and p.fator is not null
    window w as (partition by p.id order by f.rn)
  ), jan_fecha as (
    select j.pai, min(j.k) as k from jan j where j.completo and abs(j.vp - j.sv) <= (j.fp + j.sf) / 2 group by j.pai
  ), absorvida as (   -- as linhas que o pai que FECHA (ou cobre) já contém: não somam de novo
    select m.filha as id from fam m where m.pai in (select e.pai from fam_estado e where e.estado in ('fecha', 'cobre_parte'))
    union
    select j.filha from jan j join jan_fecha jf on jf.pai = j.pai and j.k <= jf.k
    union   -- (iii) a MESMA conta com dois nomes de manual: "Clientes" e "Duplicatas a receber" com o valor idêntico (ao centavo) na mesma escala valem uma vez só
    select f.id from c2 p join c2 f on f.id <> p.id and p.n ~ '^([0-9][0-9. -]*)?(clientes|fornecedores)$' and f.n ~ '^([0-9][0-9. -]*)?duplicatas a receber$'
                                  and p.valor_num <> 0 and f.valor_num = p.valor_num and f.unidade is not distinct from p.unidade
  )
  select c.id, c.chave, c.valor_num, c.unidade, c.secao,
         nullif(concat_ws(' ',
           case e.estado
             when 'cobre_parte' then format('"%s" entrou sozinho: %s com o nome dentro do dele soma(m) %s e cobre(m) só parte dos %s dele; se o resto é de linhas que a extração não trouxe, o pai vale e o valor está certo, e se o pai é uma conta própria, o valor está subestimado.',
                                            c.chave, case when e.nf = 1 then 'a única linha' else 'as ' || e.nf || ' linhas' end, fn_aging_reais(e.sv), fn_aging_reais(e.vp))
             when 'excede' then format('"%s" parece o total d%s com o nome dentro do dele, mas %s mais que ele (%s contra %s): entraram todas na soma, e se o balanço as conta dentro dele o valor está em dobro.',
                                       c.chave, case when e.nf = 1 then 'a única linha' else 'as ' || e.nf || ' linhas' end, case when e.nf = 1 then 'ela vale' else 'elas somam' end, fn_aging_reais(e.sv), fn_aging_reais(e.vp))
           end,
           (select format('"%s" e "%s" têm o mesmo valor (%s, na mesma escala): se são a mesma conta com dois nomes, a soma está em dobro.', c.chave, b.chave, c.valor_num)
              from c2 b where b.id <> c.id and b.id not in (select x.id from absorvida x) and c.valor_num <> 0 and b.valor_num = c.valor_num
                          and b.unidade is not distinct from c.unidade and c.id < b.id order by b.id limit 1)), '') as aviso
    from c2 c left join fam_estado e on e.pai = c.id
   where c.id not in (select x.id from absorvida x)
   order by c.ordem nulls last, c.id;
end $$;
comment on function fn_aging_linhas_do_balanco(uuid, text, text, text) is
  '0277 (sobre a 0274): as linhas do balanço (uma versão de documento) de um conceito, pelo rótulo normalizado, pelas colunas de entidade e período e pelo LADO do balanço (secao_canonica do conceito, ou nula; seção em texto com "estoque" fora). Pai e filhas pela ESTRUTURA: o pai cujo valor é a soma das linhas com o nome dentro do dele (meia unidade da escala por linha), ou que as cobre, vale sozinho; o de nome de manual (Clientes, Fornecedores) também pela janela de ordem (até 6 linhas seguintes); as filhas com secao = nome do pai e o pai líquido (dedução filha) seguem a regra da 0274. Pai que as filhas EXCEDEM não é subtotal: todas entram e a coluna aviso diz isso; dois nomes com o mesmo valor também avisam. Devolve (id, chave, valor_num, unidade, secao, aviso). Deduções, variações de fluxo, longo prazo e partes relacionadas ficam de fora; Clientes/Fornecedores também deixam de fora Adiantamentos.';

-- ---------------------------------------------------------------------------
-- 3. A CONCILIAÇÃO: O PERÍODO DA CARTEIRA E O BALANÇO DO GRUPO
-- ---------------------------------------------------------------------------
create or replace function fn_reconciliar_aging(p_aging_id uuid) returns jsonb
language plpgsql set search_path = public, pg_temp as $$
declare
  a           aging_importado;
  v_ano       int;
  r           record;
  f           record;
  v_doc       uuid;
  v_periodo   uuid;
  v_ver       uuid;
  v_col_ent   text;
  v_col_per   text;
  v_n_docs    int := 0;
  v_sem_ent   boolean := false;
  v_notas     text[] := '{}';
  v_res       jsonb := '[]'::jsonb;
  v_prev_chave text := current_setting('oria.periodo_chave', true);
  v_cfg       record;
  v_valor_c   numeric;      -- o valor da carteira em centavos (absoluto)
  v_aging     numeric;      -- em reais
  v_lin       record;
  v_n_lin     int; v_balanco numeric; v_soma_fatores numeric; v_tol numeric; v_div numeric; v_sem_escala boolean;
  v_chaves    text[];
  v_resultado text; v_desc text; v_fa jsonb; v_fb jsonb; v_pct numeric;
  v_rej_l     numeric; v_rej_s numeric; v_ressalva text;
  v_tb        text; v_cabeca text;
  v_proprio   boolean := true;   -- 0277: o balanço escolhido é o da PRÓPRIA entidade?
  v_dono      text;              -- 0277: de quem é o documento, quando não é o da entidade
  v_tipo_doc  text;
  v_avisos    text[];            -- 0277: o que a busca das linhas desconfia e não resolveu (pai que não fecha, valor repetido)
begin
  select * into a from aging_importado where id = p_aging_id;
  if not found then return jsonb_build_object('executado', false, 'motivo', 'importação de aging não encontrada'); end if;
  if a.substituido_em is not null then
    return jsonb_build_object('executado', false, 'motivo', 'importação substituída por outra: só a vigente se concilia');
  end if;
  v_ano := extract(year from a.data_base)::int;
  v_tb  := case a.tipo_base when 'contas_a_receber' then 'contas a receber' else 'contas a pagar' end;
  v_cabeca := format('Carteira de %s em %s (arquivo "%s")', v_tb, to_char(a.data_base, 'DD/MM/YYYY'), a.arquivo_nome);

  -- O balanço que fecha NA data-base e que TEM a entidade do aging. 0277 (ALTO 3): a ordem é (1) o documento da PRÓPRIA entidade, (2) o de outra
  -- empresa do grupo cuja COLUNA fn_coluna_entidade resolve para esta entidade (o balanço combinado do grupo, que é a única fonte de uma controlada
  -- sem balanço próprio); dentro de cada grupo, BALANCO antes de COMBINADO antes de BALANCETE e o mais novo entre iguais. O próprio vem primeiro
  -- porque é a demonstração da empresa; a coluna de um combinado é uma leitura derivada (pode já trazer ajustes de consolidação). O documento de
  -- outra empresa só entra quando a coluna é achada de verdade (fn_coluna_entidade nulo = documento sem colunas de entidade, e E'\x01' = tem
  -- colunas e nenhuma é desta entidade): nunca por palpite, e a descrição diz de quem é o documento.
  for r in select d.id, d.tipo_taxonomia, coalesce(d.entidade_id = a.entidade_id, false) as proprio, e.razao_social as dono_nome
             from documento d
             left join entidade e on e.id = d.entidade_id
            cross join lateral (select fn_coluna_entidade(fn_versao_atual(d.id), a.entidade_id) as col) x
            where d.caso_id = a.caso_id and d.tipo_taxonomia in ('BALANCO', 'COMBINADO', 'BALANCETE')
              and (d.entidade_id = a.entidade_id or (x.col is not null and x.col <> E'\x01'))
            order by coalesce(d.entidade_id = a.entidade_id, false) desc,
                     array_position(array['BALANCO', 'COMBINADO', 'BALANCETE'], d.tipo_taxonomia), d.criado_em desc, d.id loop
    v_n_docs := v_n_docs + 1;
    select * into f from fn_balanco_fecha_em(r.id, v_ano);
    if f.fecha_em is distinct from a.data_base then
      v_notas := v_notas || format('%s%s %s', r.tipo_taxonomia, case when r.proprio then '' else ' de ' || coalesce(r.dono_nome, 'outra empresa') end,
        coalesce('fecha em ' || to_char(f.fecha_em, 'DD/MM/YYYY') || ', não em ' || to_char(a.data_base, 'DD/MM/YYYY'), f.observacao));
      continue;
    end if;
    v_ver := fn_versao_atual(r.id);
    v_col_ent := fn_coluna_entidade(v_ver, a.entidade_id);
    if v_col_ent = E'\x01' then
      v_sem_ent := true; v_notas := v_notas || format('%s fecha em %s mas não tem coluna desta entidade', r.tipo_taxonomia, to_char(a.data_base, 'DD/MM/YYYY'));
      continue;
    end if;
    v_doc := r.id; v_proprio := r.proprio; v_dono := r.dono_nome; v_tipo_doc := r.tipo_taxonomia;
    exit;
  end loop;
  if v_doc is not null then
    v_col_per := fn_coluna_periodo_do_ano(v_ver, v_ano);
    if v_col_per = E'\x01' then v_col_per := null; end if;
  end if;

  -- 0277 (ALTO 1): o PERÍODO DA CARTEIRA é a data-base dela, não o do documento. fn_registrar_reconciliacao acha a pendência por período COMPATÍVEL
  -- (fn_periodos_compativeis: os anos se intersectam), e o período do balanço comparativo ("multi 24,25") contém os dois anos: carteiras de
  -- 31/12/2024 e 31/12/2025 caíam na MESMA pendência e o ok do ano novo (visitado por último) apagava a divergência do velho. Com o período
  -- ('data-base', 'AAAA-MM-DD') da carteira, anos diferentes não se intersectam e cada um tem a sua pendência e a sua descrição. Este período é
  -- FABRICADO por esta função (nenhum documento o trouxe): tipo 'data-base' e a data ISO, a mesma notação que o mapa de dívida já usa. EFEITO: o
  -- mandato ganha uma linha em `periodo` por data-base conciliada, e ela entra nos laços de períodos compatíveis das checagens clássicas
  -- (fn_periodos_compativeis_array), que só tentam o seguinte quando o anterior deu pré-condição. Mesmo ano com datas-base diferentes (30/06 e 31/12
  -- de 2025) continua compartilhando a pendência: ver o teto (1) no cabeçalho.
  insert into periodo (caso_id, tipo, referencia) values (a.caso_id, 'data-base', a.data_base::text)
    on conflict (caso_id, tipo, referencia) do nothing;
  select p.id into v_periodo from periodo p where p.caso_id = a.caso_id and p.tipo = 'data-base' and p.referencia = a.data_base::text;
  if v_doc is not null and not v_proprio then
    v_cabeca := v_cabeca || format(' [balanço lido: %s de %s, na coluna "%s", outra empresa do grupo]', v_tipo_doc, coalesce(v_dono, 'empresa sem nome'), coalesce(v_col_ent, 'sem coluna de entidade'));
  end if;

  -- A chave do período para a guarda de fn_registrar_reconciliacao: a da carteira (sem documento no período, a guarda por chave viva da 0192 não a prende: só a da mesma transação).
  perform set_config('oria.periodo_chave', v_periodo::text, true);

  -- O que a leitura deixou fora do aging (para a descrição de uma divergência).
  select coalesce(sum(fn_aging_contagem(m.value -> 'linhas')), 0), coalesce(sum(fn_aging_centavos(m.value -> 'saldo')), 0) into v_rej_l, v_rej_s
    from jsonb_each(case when jsonb_typeof(a.aplicador -> 'motivos') = 'object' then a.aplicador -> 'motivos' else '{}'::jsonb end) m;
  v_ressalva := case when v_rej_l > 0 then format(' O aplicador deixou fora do aging %s linhas rejeitadas, com saldo de %s: pode explicar a diferença.', v_rej_l, fn_aging_reais(v_rej_s / 100)) else '' end;

  for v_cfg in select * from (values
      ('aging_ar_clientes',        'contas_a_receber', 'clientes',                    'Clientes',                      'positivos', 'saldo positivo (carteira a receber)'),
      ('aging_ar_adiantamentos',   'contas_a_receber', 'adiantamentos_de_clientes',   'Adiantamentos de clientes',     'negativos', 'saldo negativo (adiantamentos e créditos de clientes)'),
      ('aging_ap_fornecedores',    'contas_a_pagar',   'fornecedores',                'Fornecedores',                  'positivos', 'saldo positivo (carteira a pagar)'),
      ('aging_ap_adiantamentos',   'contas_a_pagar',   'adiantamentos_a_fornecedores','Adiantamentos a fornecedores',  'negativos', 'saldo negativo (adiantamentos e créditos a fornecedores)')
    ) as t(tipo, base, conceito, rotulo, lado, rotulo_aging) where t.base = a.tipo_base loop
    v_valor_c := abs(fn_aging_centavos(a.resumo -> v_cfg.lado -> 'saldo'));
    v_aging := v_valor_c / 100;
    v_fa := jsonb_build_object('chave', format('aging %s %s (%s)', a.tipo_base, a.data_base, v_cfg.lado), 'valor', v_aging, 'unidade', 'unidade',
                               'centavos', v_valor_c::text, 'aging_id', a.id);
    v_fb := null; v_pct := null; v_div := null;

    if v_doc is null then
      if v_n_docs = 0 then
        v_res := v_res || jsonb_build_array(fn_registrar_reconciliacao(a.caso_id, a.entidade_id, null, v_cfg.tipo, 'A', null, v_fa, null,
          'documento_ausente', null, null, jsonb_build_object('criterio', 'meia_unidade_da_escala'),
          v_cabeca || format(': sem par para reconciliar, o balanço desta entidade não foi entregue, nem como coluna de um balanço de outra empresa do grupo (%s de %s, sem conta do balanço para conferir).', v_cfg.rotulo_aging, fn_aging_reais(v_aging))));
      else
        v_resultado := case when v_sem_ent and not exists (select 1 from unnest(v_notas) n where n not like '%não tem coluna desta entidade') then 'precondicao_nao_satisfeita' else 'sem_periodo_par' end;
        v_res := v_res || jsonb_build_array(fn_registrar_reconciliacao(a.caso_id, a.entidade_id, null, v_cfg.tipo, 'A', null, v_fa, null,
          v_resultado, null, null, jsonb_build_object('criterio', 'meia_unidade_da_escala'),
          fn_motivo_precondicao_prefixo(v_resultado) || v_cabeca
            || format(': o balanço desta entidade não fecha na data-base (%s não se compara com outra data). Balanços vistos: %s.', v_cfg.rotulo_aging, array_to_string(v_notas, '; '))));
      end if;
      continue;
    end if;

    select count(*), coalesce(sum(l.valor_num * fn_fator_escala(l.unidade)), 0), coalesce(sum(fn_fator_escala(l.unidade)), 0),
           coalesce(bool_or(fn_fator_escala(l.unidade) is null), false), array_agg(format('"%s" = %s %s', l.chave, l.valor_num, coalesce(l.unidade, 'sem escala')) order by l.chave),
           array_remove(array_agg(distinct l.aviso), null)
      into v_n_lin, v_balanco, v_soma_fatores, v_sem_escala, v_chaves, v_avisos
      from fn_aging_linhas_do_balanco(v_ver, v_cfg.conceito, v_col_ent, v_col_per) l;
    v_fb := case when v_n_lin = 0 then null else jsonb_build_object('chaves', to_jsonb(v_chaves), 'valor', v_balanco, 'unidade', 'unidade', 'documento_versao_id', v_ver,
                                                          'documento_id', v_doc, 'coluna_entidade', v_col_ent, 'documento_de_outra_empresa', not v_proprio,
                                                          'avisos', to_jsonb(coalesce(v_avisos, '{}'::text[]))) end;

    if v_n_lin = 0 then
      if v_valor_c = 0 then
        v_res := v_res || jsonb_build_array(fn_registrar_reconciliacao(a.caso_id, a.entidade_id, v_periodo, v_cfg.tipo, 'A', v_doc, v_fa, null,
          'ok', 0, null, jsonb_build_object('criterio', 'meia_unidade_da_escala'),
          v_cabeca || format(': nada a conciliar, a carteira não tem %s e o balanço não traz a conta %s.', v_cfg.rotulo_aging, v_cfg.rotulo)));
      else
        v_res := v_res || jsonb_build_array(fn_registrar_reconciliacao(a.caso_id, a.entidade_id, v_periodo, v_cfg.tipo, 'A', v_doc, v_fa, null,
          'linha_nao_localizada', v_aging, null, jsonb_build_object('criterio', 'meia_unidade_da_escala'),
          fn_motivo_precondicao_prefixo('linha_nao_localizada') || v_cabeca
            || format(': %s de %s e o balanço não traz a conta %s para conferir: a diferença é o valor inteiro, %s.%s',
                      v_cfg.rotulo_aging, fn_aging_reais(v_aging), v_cfg.rotulo, fn_aging_reais(v_aging), v_ressalva)));
      end if;
      continue;
    end if;

    if v_sem_escala then
      v_res := v_res || jsonb_build_array(fn_registrar_reconciliacao(a.caso_id, a.entidade_id, v_periodo, v_cfg.tipo, 'A', v_doc, v_fa, v_fb,
        'unidade_divergente', null, null, jsonb_build_object('criterio', 'meia_unidade_da_escala'),
        fn_motivo_precondicao_prefixo('unidade_divergente') || v_cabeca
          || format(': a conta %s do balanço não tem escala reconhecida (esperado: unidade, milhar ou milhão), e o aging está em reais: comparar arriscaria um falso "confere".', v_cfg.rotulo)));
      continue;
    end if;

    v_div := abs(v_aging - v_balanco);
    -- A tolerância É o arredondamento do número impresso: meia unidade da escala de cada linha usada (R$ 500 em R$ mil), nunca um percentual.
    v_tol := v_soma_fatores / 2;
    v_pct := case when v_aging <> 0 then v_div / v_aging end;
    v_resultado := case when v_div <= v_tol then 'ok' else 'divergente' end;
    v_desc := v_cabeca || format(': %s de %s contra %s do balanço de %s (%s). ', v_cfg.rotulo_aging, fn_aging_reais(v_aging), v_cfg.rotulo,
                                 fn_aging_reais(v_balanco), array_to_string(v_chaves, '; '))
      || case when v_resultado = 'ok'
              then format('Conferido, diferença de %s (tolerância de %s: o arredondamento da escala do balanço).', fn_aging_reais(v_div), fn_aging_reais(v_tol))
              else format('Diferença de %s, acima de %s (o arredondamento da escala do balanço).%s', fn_aging_reais(v_div), fn_aging_reais(v_tol), v_ressalva) end
      -- 0277: o que a leitura das linhas do balanço desconfiou e não resolveu (pai que não fecha com as filhas, valor repetido) vai no texto, ok ou divergente.
      || coalesce(' Atenção na leitura do balanço: ' || nullif(array_to_string(v_avisos, ' '), ''), '');
    v_res := v_res || jsonb_build_array(fn_registrar_reconciliacao(a.caso_id, a.entidade_id, v_periodo, v_cfg.tipo, 'A', v_doc, v_fa, v_fb,
      v_resultado, v_div, v_pct, jsonb_build_object('tolerancia_abs', v_tol, 'criterio', 'meia_unidade_da_escala'), v_desc));
  end loop;

  perform set_config('oria.periodo_chave', coalesce(v_prev_chave, ''), true);
  return jsonb_build_object('executado', true, 'aging_id', p_aging_id, 'checagens', v_res);
end $$;
comment on function fn_reconciliar_aging(uuid) is
  '0274 (reemitida pela 0277): concilia UMA importação vigente de aging com o balanço extraído que fecha na data-base e TEM a entidade: o documento da própria entidade, ou a coluna desta entidade de um balanço de outra empresa do grupo (própria primeiro). Saldos positivos × Clientes (a receber) ou Fornecedores (a pagar), negativos × Adiantamentos de clientes/a fornecedores. Tolerância = meia unidade da escala do balanço (nunca percentual). Tipos aging_ar_clientes, aging_ar_adiantamentos, aging_ap_fornecedores, aging_ap_adiantamentos, classe A, por fn_registrar_reconciliacao com descrição sempre; divergência zero é gravada como conferida (ok, 0). O PERÍODO da reconciliação é o da carteira (periodo data-base AAAA-MM-DD, criado se não existe): anos diferentes nunca dividem pendência. Sem balanço = documento_ausente (sem pendência); balanço de outra data = sem_periodo_par. As desconfianças da leitura das linhas (pai que não fecha, valor repetido) vão na descrição. Só service_role e as funções definer chamam.';

-- ---------------------------------------------------------------------------
-- 4. A IMPORTAÇÃO, AGORA COM O RESUMO AMARRADO AO APLICADOR
-- ---------------------------------------------------------------------------
create or replace function fn_aging_importar(p_caso uuid, p_entidade uuid, p_tipo_base text, p_data_base date, p_resumo jsonb, p_leitura jsonb,
                                  p_aplicador jsonb, p_arquivo jsonb, p_mapeamento uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_erros text[];
  v_id    uuid := gen_random_uuid();
  v_antigo uuid;
  v_map_tipo text;
  v_conc  jsonb;
begin
  if p_caso is null or not fn_pode_escrever_caso(p_caso) then
    raise exception 'Importar aging exige ser Sócio ou Analista alocado neste mandato' using errcode = '42501';
  end if;
  if p_tipo_base is null or p_tipo_base not in ('contas_a_receber', 'contas_a_pagar') then
    raise exception 'tipo_base "%" não existe (contas_a_receber ou contas_a_pagar)', p_tipo_base using errcode = '22023';
  end if;
  if not exists (select 1 from caso where id = p_caso) then
    raise exception 'O mandato % não existe', p_caso using errcode = 'P0002';
  end if;
  if p_data_base is null then
    raise exception 'O aging sem data-base não é uma posição: a data-base é obrigatória' using errcode = '22023';
  end if;
  if p_entidade is null or not exists (select 1 from entidade where id = p_entidade and caso_id = p_caso) then
    raise exception 'A entidade % não é deste mandato: o aging tem de dizer de qual empresa do grupo é a carteira', p_entidade using errcode = '22023';
  end if;

  v_erros := fn_aging_resumo_erros(p_resumo, p_data_base);
  -- 0277: o resumo tem de ser o do arquivo que o aplicador leu (mesmos títulos, mesmos saldos); a 0274 validava cada um por si e nada os amarrava.
  v_erros := v_erros || fn_aging_aplicador_erros(p_resumo, p_aplicador);
  if jsonb_typeof(p_leitura) is distinct from 'object' or jsonb_typeof(p_aplicador) is distinct from 'object' then
    v_erros := v_erros || 'o resumo da leitura e o do aplicador têm de ser objetos'::text;
  end if;
  if jsonb_typeof(p_arquivo) is distinct from 'object'
     or coalesce(p_arquivo ->> 'nome', '') = ''
     or coalesce(p_arquivo ->> 'sha256', '') !~ '^[0-9a-f]{64}$'
     or coalesce(p_arquivo ->> 'bytes', '') !~ '^[1-9][0-9]{0,15}$'
     or coalesce(p_arquivo ->> 'formato', '') not in ('csv', 'xlsx') then
    v_erros := v_erros || 'o arquivo precisa de nome, sha256 (64 hex minúsculos), bytes > 0 e formato csv ou xlsx'::text;
  elsif jsonb_typeof(p_leitura) = 'object' then
    if p_leitura ->> 'parcial' = 'true' then
      v_erros := v_erros || 'a leitura foi PARCIAL (interrompida depois da amostra): contagens e sha256 são só do trecho lido'::text;
    elsif p_leitura ->> 'sha256' is distinct from p_arquivo ->> 'sha256' then
      v_erros := v_erros || 'o sha256 da leitura é diferente do sha256 do arquivo'::text;
    end if;
  end if;
  select tipo_base into v_map_tipo from mapeamento_de_colunas where id = p_mapeamento;
  if v_map_tipo is null then
    v_erros := v_erros || 'mapeamento inexistente: arquivo sem mapeamento confirmado não vira dado'::text;
  elsif v_map_tipo <> p_tipo_base then
    v_erros := v_erros || format('o mapeamento é de %s e a importação é de %s', v_map_tipo, p_tipo_base);
  end if;
  if cardinality(v_erros) > 0 then
    raise exception 'Aging recusado: %', array_to_string(v_erros, '; ') using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_caso::text || ':' || p_entidade::text || ':' || p_tipo_base || ':' || p_data_base::text, 0));
  update aging_importado set substituido_em = now(), substituido_por = v_id
   where caso_id = p_caso and entidade_id = p_entidade and tipo_base = p_tipo_base and data_base = p_data_base and substituido_em is null
  returning id into v_antigo;
  insert into aging_importado (id, caso_id, entidade_id, tipo_base, data_base, resumo, leitura, aplicador,
                               arquivo_nome, arquivo_sha256, arquivo_bytes, arquivo_formato, mapeamento_id, importado_por)
  values (v_id, p_caso, p_entidade, p_tipo_base, p_data_base, p_resumo, p_leitura, p_aplicador,
          p_arquivo ->> 'nome', p_arquivo ->> 'sha256', (p_arquivo ->> 'bytes')::bigint, p_arquivo ->> 'formato', p_mapeamento, auth.uid());

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
  values ('usuario:' || auth.uid(), 'aging_importado', 'caso:' || p_caso,
          case when v_antigo is null then null else jsonb_build_object('substituido', v_antigo) end,
          jsonb_build_object('id', v_id, 'entidade_id', p_entidade, 'tipo_base', p_tipo_base, 'data_base', p_data_base,
                             'arquivo_sha256', p_arquivo ->> 'sha256'));

  v_conc := fn_reconciliar_aging(v_id);
  return jsonb_build_object('id', v_id, 'substitui', v_antigo, 'conciliacao', v_conc -> 'checagens');
end $$;
comment on function fn_aging_importar(uuid, uuid, text, date, jsonb, jsonb, jsonb, jsonb, uuid) is
  '0274 (reemitida pela 0277): guarda o resumo do aging de uma importação, por mandato e entidade, e o concilia com o balanço extraído. Só quem escreve o mandato (fn_pode_escrever_caso: Sócio, Analista alocado); os demais, o anônimo e a conexão de serviço recebem 42501. Recusa (22023, com todos os motivos) resumo que não fecha consigo mesmo, resumo que não se amarra ao aplicador (0277: títulos e saldos), entidade de outro mandato, leitura parcial, sha256 divergente, arquivo inválido e mapeamento inexistente ou de outro tipo_base. Reimportar a mesma (entidade, tipo_base, data_base) substitui a vigente SEM apagar. Grava aging_importado em evento_auditoria (caso:<id>). Devolve {id, substitui, conciliacao}.';

do $$
declare f text;
begin
  foreach f in array array['fn_aging_aplicador_erros(jsonb, jsonb)', 'fn_aging_linhas_do_balanco(uuid, text, text, text)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
    if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
      execute format('grant execute on function %s to supabase_read_only_user', f);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 5. A SONDA. Marcadores em CÓDIGO, nunca de comentário (pg_get_functiondef traz os comentários do corpo).
-- ---------------------------------------------------------------------------
create view instalacao_sonda_aging_aplicador_check as
  select k.conname::text as nome
    from pg_constraint k
   where k.conrelid = 'public.aging_importado'::regclass and k.contype = 'c' and k.convalidated
     and k.conname = 'aging_resumo_e_aplicador' and pg_get_constraintdef(k.oid) like '%fn_aging_aplicador_erros(%';
comment on view instalacao_sonda_aging_aplicador_check is
  'Sonda da 0277: uma linha = a CHECK aging_resumo_e_aplicador existe, validada, e chama fn_aging_aplicador_erros. Zero linhas: o service_role grava um resumo que não é o do arquivo lido.';
grant select on instalacao_sonda_aging_aplicador_check to authenticated, service_role;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    execute 'grant select on instalacao_sonda_aging_aplicador_check to supabase_read_only_user';
  end if;
end $$;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('aging_aplicador_funcao', '0277', 'funcao', 'fn_aging_aplicador_erros', null, null,
   'O validador que amarra o resumo do aging ao resumo do aplicador. Ausente = a 0277 não foi aplicada: o resumo pode ser de outro arquivo que o lido.',
   'importante', 1354),
  ('aging_importar_amarra_aplicador', '0277', 'corpo', 'fn_aging_importar', 'fn_aging_aplicador_erros(', null,
   'A importação recusa o resumo que não se amarra ao aplicador. Corpo sem isto = a carteira de um arquivo é guardada com o resumo de outro e concilia com o balanço como se fosse a dele.',
   'importante', 1355),
  ('aging_aplicador_check', '0277', 'comportamento', 'instalacao_sonda_aging_aplicador_check', null, 1,
   'A CHECK da tabela que amarra o resumo ao aplicador. Zero linhas = o service_role grava resumo que não é o do arquivo lido.',
   'importante', 1356),
  ('aging_conciliar_periodo_da_carteira', '0277', 'corpo', 'fn_reconciliar_aging', '''data-base'', a.data_base::text', null,
   'A reconciliação do aging é do período da CARTEIRA (a data-base), não do documento. Corpo sem isto = balanço comparativo (multi 24,25) com carteiras de 2024 e 2025: o ok do ano novo apaga a divergência do velho.',
   'bloqueante', 1357),
  ('aging_conciliar_balanco_do_grupo', '0277', 'corpo', 'fn_reconciliar_aging', 'fn_coluna_entidade(fn_versao_atual(d.id), a.entidade_id)', null,
   'A conciliação aceita o balanço de outra empresa do grupo cuja coluna é a da entidade. Corpo sem isto = a controlada que só existe como coluna do combinado vira documento_ausente (sem pendência): a carteira nunca é conferida.',
   'importante', 1358),
  ('aging_linhas_pai_que_fecha', '0277', 'corpo', 'fn_aging_linhas_do_balanco', 'abs(p.vb - s.sv) <= (p.fator + s.sf) / 2', null,
   'O pai (Fornecedores) que é a soma das filhas vale sozinho. Corpo sem isto = pai e filhas somam em dobro quando têm a mesma seção ou seção nula (a forma de produção), e a carteira correta aparece como divergente.',
   'bloqueante', 1359),
  ('aging_linhas_lado_do_balanco', '0277', 'corpo', 'fn_aging_linhas_do_balanco', 'ce.secao_canonica = v_sc', null,
   'A linha tem de estar do lado do balanço em que o conceito mora. Corpo sem isto = a mercadoria em garantia "(FORNECEDOR)" da seção ESTOQUE entra como Fornecedores.',
   'importante', 1360)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0277', revisado_em = current_date,
       observacao = 'A 0277 corrige os 3 ALTOS da conciliação do aging da 0274 (a pendência por data-base, o pai de Fornecedores/Clientes que somava com as filhas, o balanço do grupo como fonte da entidade) e 3 médios (o lado do balanço, o resumo amarrado ao aplicador). Reemite fn_reconciliar_aging e fn_aging_importar, recria fn_aging_linhas_do_balanco (ganha a coluna aviso) e cria fn_aging_aplicador_erros. 7 requisitos novos (ordem 1354-1360).'
 where id = true;

commit;
