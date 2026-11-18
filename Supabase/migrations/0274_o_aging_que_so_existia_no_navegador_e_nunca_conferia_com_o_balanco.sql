-- =============================================================================
-- 0274 — O AGING QUE SÓ EXISTIA NO NAVEGADOR E NUNCA CONFERIA COM O BALANÇO: o resumo do aging de contas a receber/a pagar guardado
--        POR MANDATO, conciliado com Clientes/Fornecedores e com os Adiantamentos do balanço extraído (MB3b do PLANO_MVP_2026-11.md;
--        decisão DM1: só o RESUMO no banco, o arquivo original vai à parte, numa fatia futura)
-- (Cria 1 tabela, 9 funções, 1 policy de leitura, 2 views da sonda. Nenhum backfill: a tabela nasce vazia.)
--
-- O DEFEITO. A biblioteca do aging (Leitor/lib/aging.mjs, MB3a) calcula, no navegador, a carteira numa data-base: faixas de atraso,
-- concentração, maiores contrapartes. Mas o resumo se perdia ao fechar a aba, e nada o comparava com o balanço que a IA extraiu do mesmo
-- cliente: uma carteira de R$ 24,9 milhões ao lado de um "Clientes" de R$ 20 milhões convivia sem ninguém dizer. O efeito do outro lado é o
-- contrário: um aging que fecha com o balanço sem que ninguém tenha olhado vale tanto quanto um que não fecha, e a diferença (a PDD que
-- virou "cliente", o adiantamento que ficou fora, a data-base errada) só aparece quando o analista a procura à mão.
--
-- O QUE A MIGRATION INSTALA
--   * `aging_importado`: uma linha por importação; caso_id, entidade_id (de qual empresa do grupo é a carteira: OBRIGATÓRIO), tipo_base
--     (contas_a_receber | contas_a_pagar), data_base, o resumo do aging (jsonb, centavos como TEXTO de inteiro), o resumo da leitura e o do
--     aplicador (jsonb), o arquivo (nome, sha256 64 hex, bytes, formato), mapeamento_id (FK da 0272: arquivo sem mapeamento confirmado
--     não vira dado), autor (auth.uid(), sem FK: a autoria sobrevive ao usuário, como na 0272/0273) e data. REIMPORTAR a mesma
--     (caso, entidade, tipo_base, data_base) SUBSTITUI a vigente SEM APAGAR (substituido_em/substituido_por; índice único parcial).
--     RLS por mandato (0216, igual à 0273): lê o Sócio e quem tem o mandato; ninguém escreve direto (sem grant e sem policy de escrita ao
--     authenticated); GRANT da 0214 (authenticated só SELECT; service_role as quatro operações).
--   * `fn_aging_resumo_erros(resumo, data_base)`: o validador da FRONTEIRA DE CONFIANÇA (o resumo vem do navegador), UM só, usado pela
--     função de importar (que recusa com TODOS os motivos) e pela CHECK da tabela (que cobre o service_role). Recusa o resumo que não
--     fecha consigo mesmo: Σ por_faixa = positivos.saldo; vencido = Σ das faixas menos a_vencer; Σ maiores + demais = positivos.saldo e
--     = positivos.titulos (em títulos); Σ negativos.maiores + negativos.demais = negativos.saldo; negativos.saldo <= 0 e positivos.saldo
--     >= 0; resumo.data_base = a data-base; centavos inteiros em texto; exatamente as 7 faixas. FORMATO de Leitor/lib/aging.mjs em
--     12/11/2026 depois da revisão independente (negativos.demais, titulos nos maiores e no demais, emitidos_depois_da_data_base com
--     saldo_positivos/saldo_negativos, documentos_invalidos). LIMITE DITO: a cópia do formato é manual (nenhum portão compara a lista de
--     campos com a biblioteca) e o banco NÃO prova que o arquivo foi lido inteiro (isso é da biblioteca e dos testes dela): só recusa o
--     resumo incoerente. Os campos informativos (emitidos_depois_da_data_base, documentos_invalidos, concentracao_top10_pct) NÃO são validados.
--   * `fn_aging_importar(caso, entidade, tipo_base, data_base, resumo, leitura, aplicador, arquivo, mapeamento)`: security definer; só
--     quem escreve o mandato (fn_pode_escrever_caso, como a 0273: Sócio ou Analista alocado; Leitura, Analista de outro mandato, sem
--     papel, anônimo e conexão de serviço recebem 42501). Além do resumo, recusa: entidade que não é do mandato (22023), leitura PARCIAL
--     (a MB1 devolve `parcial: true` sem sha256 quando interrompe), sha256 da leitura diferente do do arquivo, arquivo sem nome/sha/bytes/
--     formato válidos, mapeamento inexistente ou de outro tipo_base. Grava `aging_importado` em evento_auditoria (entidade_ref `caso:<id>`)
--     e CONCILIA na hora (fn_reconciliar_aging). Devolve {id, substitui, conciliacao}.
--   * `fn_balanco_fecha_em(documento, ano)`: em que DATA o balanço fecha, para a conciliação só comparar saldos da MESMA data. Coluna com data
--     (dd/mm/aaaa) vale a data; coluna ou período anual de um exercício só = 31/12; mensal (NmAAAA, MM/AAAA) e trimestral (NTAA) = o
--     fim do mês/trimestre; parcial sem data, ano que o documento não traz e período que cobre vários exercícios sem coluna = NULL, com a
--     observação. Reaproveita fn_coluna_periodo_do_ano, fn_anos_periodo, fn_periodo_canonico e fn_periodo_e_parcial.
--   * `fn_aging_linhas_do_balanco(versao, conceito, coluna_entidade, coluna_periodo)`: as linhas do balanço de um conceito (clientes,
--     fornecedores, adiantamentos_de_clientes, adiantamentos_a_fornecedores), pelo MESMO mecanismo das reconciliações (rótulo normalizado
--     por fn_normalizar_texto, coluna de entidade e de período por fn_coluna_entidade/fn_coluna_periodo_do_ano). Ver ROTULOS abaixo.
--   * `fn_reconciliar_aging(aging_id)`: a conciliação de UMA importação vigente (só service_role e as funções definer chamam). Duas
--     checagens por tipo_base, classe A (a mesma do caixa × DFC), gravadas por fn_registrar_reconciliacao (descrição SEMPRE preenchida):
--       contas_a_receber: `aging_ar_clientes` (saldos POSITIVOS × Clientes, ativo, o valor BRUTO: a PECLD/PDD é linha própria e fica de
--         fora) e `aging_ar_adiantamentos` (saldos NEGATIVOS × Adiantamentos de clientes, passivo);
--       contas_a_pagar: `aging_ap_fornecedores` (positivos × Fornecedores, passivo) e `aging_ap_adiantamentos` (negativos × Adiantamentos a
--         fornecedores, ativo). Decisão do dono em 12/11/2026 (negativos SEPARADOS dos positivos).
--     O CONTRATO de motivos (0186/0188) que cada desfecho usa:
--       ok, divergência 0         conferido: "conferido, 0" é resultado gravado com divergencia_abs = 0, não ausência (sinal da MB3);
--       ok, 0 < diferença <= tol  conferido DENTRO do arredondamento: a diferença real vai em divergencia_abs, descrita;
--       divergente                diferença acima da tolerância: ABRE pendência com o valor;
--       linha_nao_localizada      balanço presente (da mesma data), sem a conta do conceito, e o valor da carteira NÃO é zero: abre
--                                 pendência com o valor (as palavras do dono: a diferença aparece como pendência). Carteira com valor ZERO
--                                 e sem a conta = nada a conciliar: gravado `ok`, com divergencia_abs 0 e a descrição dizendo "nada a conciliar";
--       sem_periodo_par           há balanço da entidade, mas nenhum fecha na data-base (dezembro não se compara com junho): abre pendência;
--       documento_ausente         nenhum balanço da entidade no mandato: NÃO abre pendência (cobrança do checklist do Kit Básico, 0023/0186);
--       unidade_divergente        a linha do balanço não tem escala reconhecida (milhar/milhão/unidade): comparar arriscaria falso "confere";
--       precondicao_nao_satisfeita o balanço da data existe mas não tem coluna desta entidade.
--   * `fn_reconciliar_aging_do_caso(caso)`: roda a conciliação de todas as importações VIGENTES do mandato. É o ponto único para a rodada de
--     reconciliações chamar quando um balanço novo chega depois (ver "NÃO LIGADO NA RODADA" abaixo).
--
-- ESCALA E TOLERÂNCIA (o coração da fatia). O aging está em CENTAVOS e o balanço costuma vir em R$ mil: `campo_extraido.valor_num` guarda o
-- número IMPRESSO (24917) e `unidade` a escala ('milhar'), e fn_valor_em_base/fn_fator_escala levam à unidade (× 1.000). A tolerância é a do
-- ARREDONDAMENTO do próprio número impresso: MEIA UNIDADE DA ESCALA de cada linha usada (R$ 500 numa linha em R$ mil, somada quando o
-- conceito vem de várias linhas: n linhas = n × R$ 500). NUNCA percentual: um percentual esconderia diferença real (0,5% de R$ 24,9 milhões
-- são R$ 124 mil). Medido: R$ 24.917.000,00 de aging contra 24.917 R$ mil = confere (diferença 0); R$ 24.917.600,00 (R$ 600 a mais, mais que
-- a meia unidade) = pendência. DECISÃO (não estava na tarefa): meia unidade e não uma unidade (o piso da 0193 usa uma): meia unidade é o
-- limite exato do arredondamento, e uma unidade inteira esconderia uma diferença de R$ 900 em R$ mil. Quem TRUNCA em vez de arredondar
-- levará pendência de até R$ 1.000: visível, com o valor, e não escondida.
--
-- ROTULOS (medidos contra as fixtures do repositório: fixture_book_vertentes.sql, fixture_book_canastra.sql, e os rótulos do
-- book-distress em Dados de Teste/book-distress/dados.py): 
--   COBERTOS (medidos: a consulta que casa cada rótulo de TODO balanço do banco de teste e conta quem fica de fora):
--     Clientes: "Clientes", "Clientes - mercado interno", "Clientes - duplicatas a receber" (inclusive "- mercado interno"), "Clientes - madeira e resíduos",
--       "Clientes - medições a receber" (book-distress), "Duplicatas a receber de clientes - mercado interno / externo" (somam), "Duplicatas a receber";
--     Fornecedores: "Fornecedores" (o PAI vale sozinho), "Fornecedores nacionais" (+ "em atraso", "a vencer"), "estrangeiros", "intragrupo - ...",
--       "títulos vencidos e não pagos", "combustível e manutenção", "e subempreiteiros" (book-distress);
--     Adiantamentos de clientes; Adiantamentos a fornecedores (e "Adiantamento a fornecedor A".."D").
--   DE FORA, por escolha (a regra é "cliente" ou "duplicata a receber", "fornecedor", "adiant" + "cliente"/"fornecedor"): o PAI líquido "Contas a Receber"
--     (a Canastra o traz com 12.795 depois de descontar a PDD e as duplicatas descontadas), "(-) Perdas estimadas ...", "(-) Duplicatas descontadas / antecipação de
--     recebíveis", "Fretes a receber" e "Fretes a faturar e a receber" (carteira de transportadora, book-vertentes: NÃO casa e vira linha_nao_localizada, com o valor,
--     para o analista olhar), "Cartões de crédito a receber", "Títulos a receber - venda de imobilizado", "Mútuos a receber/a pagar", "Contas a receber intragrupo",
--     "Aluguéis a receber", "Outras contas a pagar", "Salários ... a pagar", "Arrendamentos a pagar", "Dividendos a pagar", "Adiantamentos a empregados/motoristas/diversos"
--     e o "Adiantamentos" solto (não diz de quem). Exclusões por palavra: variação, aumento, redução, perda, PECLD/PDD, duvidoso, provisão, descontad(a), antecipa(ção),
--     ajuste a valor presente, longo prazo, não circulante, mútuo, partes relacionadas, coligada, controlada, imobilizado, salário, empregado, tributo, imposto, dividendo.
--     PAI e FILHOS: o pai vale sozinho (os filhos não somam de novo; Canastra: Fornecedores 28.634 = 17.945 + 1.901 + 5.888 + 2.900); pai que tem a provisão como filha é
--     LÍQUIDO e cede aos filhos do conceito (o bruto). O rótulo "Clientes" de TODO book do repositório foi lido; rótulo novo de um ERP fora dessa lista não casa e aparece como
--     linha_nao_localizada (nunca como zero).
--
-- QUAL BALANÇO. O da ENTIDADE do aging cujo fechamento (fn_balanco_fecha_em) é a data-base; BALANCO antes de COMBINADO antes de BALANCETE, e o
-- mais novo entre iguais. Balanço de outra data = sem par, nunca comparado. A coluna da entidade vem de fn_coluna_entidade (balanço de
-- várias empresas) e a do período de fn_coluna_periodo_do_ano.
--
-- NÃO LIGADO NA RODADA (decisão que pede o dono). O balanço que chega DEPOIS da carteira só a reconcilia se a rodada de reconciliações chamar
-- fn_reconciliar_aging_do_caso. A rodada de produção do n8n é `fn_reconciliar_por_documento(doc, 'documento')` por documento e UMA
-- `fn_reconciliar_caso(caso)` no fim (N8N/build-workflow.mjs), e a outra via, `fn_reconciliar_por_documento(doc, 'tudo')`, passa por
-- `fn_reconciliar_chaves_do_documento`. O ponto único é `fn_reconciliar_caso` (126 linhas, reemitida inteira pela 0192; a
-- `fn_reconciliar_chaves_do_documento` tem 100): ligar é UMA linha no fim dela (`v_checagens := v_checagens ||
-- fn_reconciliar_aging_do_caso(p_caso_id)`), mas é função QUENTE (toda ingestão passa por ela) e esta migration NÃO a reemite: pedido do
-- coordenador. Até a ligação, a carteira é conciliada na IMPORTAÇÃO e quando alguém chama fn_reconciliar_aging_do_caso.
--
-- NÃO MUDA A 0187. Os tipos AGING_AR/AGING_AP de documento extraído pela IA continuam sem consumidor: este caminho é outro (o arquivo
-- tabular lido no navegador), com autor e mapeamento confirmados.
--
-- TETOS DITOS. (1) Duas carteiras da MESMA entidade e tipo_base com data-base no MESMO ano compartilham a pendência (fn_registrar_reconciliacao
-- acha a pendência por período COMPATÍVEL, e período compatível é o mesmo ano): o `ok` de uma pode resolver a divergência da outra. A
-- descrição diz a data-base, mas a chave da pendência não. MEDIDO (12/11/2026, uma entidade com balanço anual 2025): carteira de 31/12 divergente = 1 pendência aberta; carteira de 30/06 do mesmo ano (sem par) = continua 1, com o texto de dezembro (não abriu a sua); carteira de 31/12 corrigida = 0 abertas, e a de junho, que segue sem par, SUMIU da fila. Sobe quando houver carteira trimestral/mensal de verdade; o remédio é um tipo (ou motivo) por data-base em fn_registrar_reconciliacao, função quente que esta migration não toca. (2) Balancete de período
-- em faixa ("01/01/2025 - 30/06/2025") não tem data de fechamento lida: vira sem_periodo_par (visível), não palpite. (3) Conceito com PAI que
-- tem filho de dedução e nenhum filho do conceito (ex.: "Clientes" com só "(-) PDD" embaixo) é lido como está, sem saber se é líquido.
--
-- A SONDA (14 requisitos, ordem 1340-1353): a tabela, as 6 funções, o corpo da importação (papel e conciliação), o corpo da conciliação (a
-- meia unidade e a data de fechamento), a policy de leitura e duas views `comportamento` (o índice único parcial e as CHECKs).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/o_aging_que_so_existia_no_navegador_e_nunca_conferia_com_o_balanco.test.sql — 153 asserts
--   (medido: 153 chamadas, 153 execuções, nenhum em laço; reconferido com Supabase/test/medicao-denominador.test.mjs). Cada guarda desligada UMA por vez DENTRO de uma
--   transação (a sabotagem recompõe a função por pg_get_functiondef e ABORTA se o trecho não existe: nenhuma variante deixou de aplicar), o teste inteiro rodado com o assert
--   em `raise warning` (voltou para `raise exception`; log lido atrás de FALHOU) e a transação desfeita. Controle (migration intacta): 0 dos 153 asserts reprovam, 153 execuções.
--   Por guarda desligada, UMA por vez (12/11/2026; o número de uma guarda que muda o resultado de uma conciliação inclui o que vem em cascata nas seções seguintes):
--   * papel e mandato na ESCRITA (como authenticated): sem guarda nenhuma: 8 · a Leitura passa: 2 · sem a guarda de mandato nulo (o Sócio passa por NULL): 1;
--   * resumo que não fecha: sem validar na função: 16 · sem a CHECK da tabela (service_role): 4 · sem as duas: 21 · Σ por_faixa: 2 · vencido: 1 · Σ maiores + demais: 1 ·
--     Σ títulos: 1 · negativo positivo: 2 · positivo negativo: 1 · data_base do resumo: 3 · centavos como número JSON: 1 · centavos com decimal: 1 · contagem como texto: 1 ·
--     exatamente 7 faixas: 2 · Σ negativos.maiores + demais: 1 · negativos sem demais: 1 · resumo que não é objeto: 1 · só o primeiro motivo: 1;
--   * tipo_base fora da lista: sem a recusa da função: 1 · sem a CHECK: 1 · sem as duas: 2 · data-base nula: 1 · mandato inexistente sem P0002: 1;
--   * entidade: de outro mandato aceita: 1 · nula passa pela função: 1;
--   * leitura e arquivo: leitura PARCIAL aceita: 1 · sha256 da leitura diferente: 1 · sha256 do arquivo: 1 · bytes: 1 · formato: 1 · sem a CHECK aging_arquivo_inteiro: 5 ·
--     leitura/aplicador objetos sem validar na função: 1 · sem a CHECK dos objetos: 3 · mapeamento inexistente: 1 · mapeamento de outro tipo_base: 1;
--   * reimportar substitui sem apagar: não marca a anterior: 20 · substitui APAGANDO: 2 · sem o índice único: 2 · sem o índice E sem marcar: 7 · índice sem o predicado (único
--     total): 22 · sem a CHECK da substituição inteira: 2;
--   * evento: não grava: 2 · sem o caso no entidade_ref: 2 · autor do evento inventado: 1 · sem a substituída no `antes`: 1 · autor da linha inventado: 1 · a importação não concilia: 51;
--   * conciliação, tolerância (a meia unidade, nunca percentual): ZERO: 5 · UMA unidade: 7 · PERCENTUAL de 0,5%: 8 · limite estrito (<): 2 · sem somar as linhas: 1;
--   * conciliação, o que compara: balanço de OUTRA data comparado: 7 · sem a coluna do período: 2 · coluna da entidade ignorada: 1 · balanço sem coluna da entidade aceito: 1 ·
--     negativos sem valor absoluto: 8 · sem a recusa de escala desconhecida: 1 · sem a conta e valor ≠ 0 vira "nada a conciliar": 3 · sem a conta e valor 0 vira pendência: 2 ·
--     sem balanço vira sem_periodo_par: 4 · roda a importação substituída: 2 · vaza o oria.periodo_chave: 1 · sem o que o aplicador deixou fora: 1 · sem a ordem BALANCO > COMBINADO > BALANCETE: 1;
--   * rodada do mandato: a conexão de serviço recusada: 1 · sem guarda de papel: 3 · sem a guarda de mandato nulo: 1;
--   * linhas do balanço: deduções (PDD) não excluídas: 12 · Adiantamentos entram em Clientes/Fornecedores: 20 · pai e filhos somam: 2 · pai líquido não cede aos filhos: 1 ·
--     dedução filha não reconhecida: 1 · conceito inexistente devolve vazio: 1 · sem o filtro da coluna do período: 4 · sem o da entidade: 1;
--   * data de fechamento: coluna com data lida como 31/12: 1 · coluna parcial vira 31/12: 1 · coluna sem o exercício não detectada: 1 · período sem ano: 1 · ano que o documento não traz: 2 ·
--     período em ISO: 1 · mês MM/AAAA: 2 · NmAAAA: 1 · trimestre: 1 · parcial sem coluna: 1 · vários exercícios sem coluna: 2;
--   * RLS e grants: sem a policy de leitura: 3 · policy `using (true)`: 2 · policy só por fn_tem_papel: 1 · escrita direta (grant + policy `for all using (true)`): 4 · `grant execute` do
--     importar ao anon: 1 · da conciliação ao authenticated: 1 · das três ao public: 2 · select da tabela ao anon: 1;
--   * sonda: requisito apontando para objeto ausente: 1 · marcador de corpo que o corpo não tem: 1 · catálogo encolhido: 1.
-- NÃO REPROVÁVEL POR CONSTRUÇÃO (medido 0, dito): `grant execute` de fn_reconciliar_aging_do_caso ao anon: 0 dos 153. A guarda do corpo (fn_pode_escrever_caso ou conexão de serviço) recusa o anon
-- com a mesma 42501 que o privilégio daria; o revoke do loop é defesa em profundidade, não a única barreira.
-- LIMITES DITOS DA MEDIÇÃO. (1) A janela entre o balanço que chega e a carteira só é provada pela chamada direta de fn_reconciliar_aging_do_caso: a ligação em fn_reconciliar_caso não está
-- nesta migration (ver "NÃO LIGADO NA RODADA"). (2) O teto (1) de TETOS DITOS (pendência compartilhada por carteiras do mesmo ano) não tem assert: um assert que fixasse o defeito protegeria o defeito.
-- (3) O `v_periodo` da guarda por chave de fn_registrar_reconciliacao não é provado contra um balanço irmão. (4) O banco de teste é C.UTF-8 e nada aqui depende de ordenação por locale.
-- =============================================================================
begin;

-- ---------------------------------------------------------------------------
-- 1. O VALIDADOR DO RESUMO (fronteira de confiança)
-- ---------------------------------------------------------------------------
create function fn_aging_centavos(p jsonb) returns numeric
language sql immutable set search_path = public, pg_temp as $$
  select case when jsonb_typeof(p) = 'string' and (p #>> '{}') ~ '^-?[0-9]{1,30}$' then (p #>> '{}')::numeric end
$$;
comment on function fn_aging_centavos(jsonb) is
  '0274: centavos do aging: só TEXTO de inteiro (BigInt serializado) vira número; número JSON, decimal, vazio ou texto qualquer devolve NULL (o validador recusa).';

create function fn_aging_contagem(p jsonb) returns numeric
language sql immutable set search_path = public, pg_temp as $$
  select case when jsonb_typeof(p) = 'number' and (p #>> '{}') ~ '^[0-9]{1,12}$' then (p #>> '{}')::numeric end
$$;
comment on function fn_aging_contagem(jsonb) is
  '0274: contagem de títulos do aging: número JSON inteiro >= 0; qualquer outra coisa devolve NULL.';

create function fn_aging_resumo_erros(p_resumo jsonb, p_data_base date) returns text[]
language plpgsql immutable set search_path = public, pg_temp as $$
declare
  e        text[] := '{}';
  c_faixas constant text[] := array['a_vencer', '1_30', '31_60', '61_90', '91_180', '181_360', 'acima_360'];
  k        text;
  x        numeric;
  t        numeric;
  it       jsonb;
  v_pos    jsonb := p_resumo -> 'positivos';
  v_neg    jsonb := p_resumo -> 'negativos';
  v_dem    jsonb := p_resumo -> 'demais';
  v_ndem   jsonb := p_resumo -> 'negativos' -> 'demais';
  v_pos_saldo numeric; v_pos_tit numeric; v_venc numeric; v_neg_saldo numeric;
  s_faixas numeric := 0; s_venc numeric := 0; s_sal numeric := 0; s_tit numeric := 0;
  ok_faixas boolean := true; ok_max boolean := true; ok_nmax boolean := true;
begin
  if p_data_base is null or jsonb_typeof(p_resumo) is distinct from 'object' then
    return array['o resumo do aging não é um objeto (ou a data-base falta)'];
  end if;
  if p_resumo ->> 'data_base' is distinct from p_data_base::text then
    e := e || format('data_base do resumo (%s) diferente da data-base informada (%s)', coalesce(p_resumo ->> 'data_base', 'ausente'), p_data_base);
  end if;

  -- positivos e as 7 faixas
  if jsonb_typeof(v_pos) is distinct from 'object' then
    e := e || 'positivos ausente'::text; ok_faixas := false; v_pos_saldo := null;
  else
    v_pos_saldo := fn_aging_centavos(v_pos -> 'saldo');
    v_venc      := fn_aging_centavos(v_pos -> 'vencido');
    v_pos_tit   := fn_aging_contagem(v_pos -> 'titulos');
    if v_pos_saldo is null then e := e || 'positivos.saldo não é inteiro em centavos, em texto'::text;
    elsif v_pos_saldo < 0 then e := e || format('positivos.saldo negativo (%s)', v_pos_saldo); end if;
    if v_venc is null then e := e || 'positivos.vencido não é inteiro em centavos, em texto'::text; end if;
    if v_pos_tit is null then e := e || 'positivos.titulos não é contagem inteira'::text; end if;
    if jsonb_typeof(v_pos -> 'por_faixa') is distinct from 'object' then
      e := e || 'positivos.por_faixa ausente'::text; ok_faixas := false;
    else
      if (select count(*) from jsonb_object_keys(v_pos -> 'por_faixa')) <> 7 then
        e := e || 'positivos.por_faixa tem de ter exatamente as 7 faixas (a_vencer, 1_30, 31_60, 61_90, 91_180, 181_360, acima_360)'::text; ok_faixas := false;
      end if;
      foreach k in array c_faixas loop
        x := fn_aging_centavos(v_pos -> 'por_faixa' -> k);
        if x is null or x < 0 then
          e := e || format('faixa %s não é inteiro >= 0 em centavos, em texto', k); ok_faixas := false;
        else
          s_faixas := s_faixas + x;
          if k <> 'a_vencer' then s_venc := s_venc + x; end if;
        end if;
      end loop;
      if ok_faixas and v_pos_saldo is not null and s_faixas <> v_pos_saldo then
        e := e || format('Σ por_faixa (%s) diferente de positivos.saldo (%s)', s_faixas, v_pos_saldo);
      end if;
      if ok_faixas and v_venc is not null and s_venc <> v_venc then
        e := e || format('positivos.vencido (%s) diferente da Σ das faixas vencidas (%s)', v_venc, s_venc);
      end if;
    end if;
  end if;

  -- maiores + demais = positivos (em saldo e em títulos): nada some
  if jsonb_typeof(p_resumo -> 'maiores') is distinct from 'array' or jsonb_typeof(v_dem) is distinct from 'object' then
    e := e || 'maiores (lista) ou demais (objeto) ausente'::text;
  else
    for it in select * from jsonb_array_elements(p_resumo -> 'maiores') loop
      x := fn_aging_centavos(it -> 'saldo'); t := fn_aging_contagem(it -> 'titulos');
      if x is null or x < 0 or t is null then ok_max := false; else s_sal := s_sal + x; s_tit := s_tit + t; end if;
    end loop;
    x := fn_aging_centavos(v_dem -> 'saldo'); t := fn_aging_contagem(v_dem -> 'titulos');
    if x is null or x < 0 or t is null then ok_max := false; else s_sal := s_sal + x; s_tit := s_tit + t; end if;
    if not ok_max then
      e := e || 'maiores/demais com saldo que não é inteiro >= 0 em centavos (texto) ou titulos que não é contagem'::text;
    else
      if v_pos_saldo is not null and s_sal <> v_pos_saldo then
        e := e || format('Σ maiores + demais (%s) diferente de positivos.saldo (%s): alguma contraparte sumiu do resumo', s_sal, v_pos_saldo);
      end if;
      if v_pos_tit is not null and s_tit <> v_pos_tit then
        e := e || format('Σ títulos de maiores + demais (%s) diferente de positivos.titulos (%s)', s_tit, v_pos_tit);
      end if;
    end if;
  end if;

  -- negativos: <= 0, e maiores + demais = negativos.saldo
  if jsonb_typeof(v_neg) is distinct from 'object' then
    e := e || 'negativos ausente'::text;
  else
    v_neg_saldo := fn_aging_centavos(v_neg -> 'saldo');
    if v_neg_saldo is null then e := e || 'negativos.saldo não é inteiro em centavos, em texto'::text;
    elsif v_neg_saldo > 0 then e := e || format('negativos.saldo positivo (%s)', v_neg_saldo); end if;
    s_sal := 0;
    if jsonb_typeof(v_neg -> 'maiores') is distinct from 'array' or jsonb_typeof(v_ndem) is distinct from 'object' then
      e := e || 'negativos.maiores (lista) ou negativos.demais (objeto) ausente'::text;
    else
      for it in select * from jsonb_array_elements(v_neg -> 'maiores') loop
        x := fn_aging_centavos(it -> 'saldo');
        if x is null then ok_nmax := false; else s_sal := s_sal + x; end if;
      end loop;
      x := fn_aging_centavos(v_ndem -> 'saldo');
      if x is null then ok_nmax := false; else s_sal := s_sal + x; end if;
      if not ok_nmax then
        e := e || 'negativos.maiores/negativos.demais com saldo que não é inteiro em centavos, em texto'::text;
      elsif v_neg_saldo is not null and s_sal <> v_neg_saldo then
        e := e || format('Σ negativos.maiores + negativos.demais (%s) diferente de negativos.saldo (%s): algum crédito sumiu do resumo', s_sal, v_neg_saldo);
      end if;
    end if;
  end if;
  return e;
end $$;
comment on function fn_aging_resumo_erros(jsonb, date) is
  '0274: o validador do resumo do aging (Leitor/lib/aging.mjs): devolve os motivos (vazio = coerente). Σ por_faixa = positivos.saldo; vencido = Σ faixas menos a_vencer; Σ maiores + demais = positivos.saldo e positivos.titulos; Σ negativos.maiores + negativos.demais = negativos.saldo; negativos <= 0 <= positivos; data_base igual; centavos inteiros em texto; 7 faixas. Não prova que o arquivo foi lido inteiro: só recusa o resumo que não fecha consigo mesmo. Usado pela função de importar e pela CHECK da tabela.';

-- ---------------------------------------------------------------------------
-- 2. A TABELA
-- ---------------------------------------------------------------------------
create table aging_importado (
  id              uuid primary key default gen_random_uuid(),
  caso_id         uuid not null references caso(id) on delete cascade,
  entidade_id     uuid not null references entidade(id) on delete cascade,
  tipo_base       text not null check (tipo_base in ('contas_a_receber', 'contas_a_pagar')),
  data_base       date not null,
  resumo          jsonb not null,
  leitura         jsonb not null,
  aplicador       jsonb not null,
  arquivo_nome    text not null,
  arquivo_sha256  text not null,
  arquivo_bytes   bigint not null,
  arquivo_formato text not null,
  mapeamento_id   uuid not null references mapeamento_de_colunas(id),
  importado_por   uuid not null,
  importado_em    timestamptz not null default now(),
  substituido_em  timestamptz,
  substituido_por uuid,
  constraint aging_resumo_fecha check (cardinality(fn_aging_resumo_erros(resumo, data_base)) = 0),
  constraint aging_arquivo_inteiro check (arquivo_nome <> '' and arquivo_sha256 ~ '^[0-9a-f]{64}$' and arquivo_bytes > 0
                                          and arquivo_formato in ('csv', 'xlsx')),
  constraint aging_leitura_e_aplicador_objetos check (jsonb_typeof(leitura) = 'object' and jsonb_typeof(aplicador) = 'object'),
  constraint aging_substituicao_inteira check ((substituido_em is null) = (substituido_por is null))
);
comment on constraint aging_resumo_fecha on aging_importado is
  '0274: o resumo fecha consigo mesmo (fn_aging_resumo_erros vazio), para quem escrever sem passar pela função (service_role).';
comment on constraint aging_arquivo_inteiro on aging_importado is
  '0274: o arquivo tem nome, sha256 de 64 hex minúsculos, bytes > 0 e formato csv/xlsx.';
comment on constraint aging_leitura_e_aplicador_objetos on aging_importado is
  '0274: o resumo da leitura e o do aplicador são objetos (a ausência não se disfarça de objeto vazio na checagem, mas nunca de número).';
comment on constraint aging_substituicao_inteira on aging_importado is
  '0274: substituido_em e substituido_por andam juntos.';

create unique index aging_importado_uma_vigente on aging_importado (caso_id, entidade_id, tipo_base, data_base) where substituido_em is null;
create index aging_importado_caso on aging_importado (caso_id);

comment on table aging_importado is
  '0274: o RESUMO do aging de contas a receber/a pagar de uma importação, POR MANDATO e por entidade (DM1: só o resumo; o arquivo original vai à parte). Uma vigente por (caso, entidade, tipo_base, data_base); reimportar substitui sem apagar. RLS por mandato (0216). Escrita só por fn_aging_importar; conciliada com o balanço por fn_reconciliar_aging.';
comment on column aging_importado.resumo is 'O resumo de agregadorDeAging(...).resumo(): centavos como TEXTO de inteiro (BigInt serializado).';
comment on column aging_importado.leitura is 'O resumo de lerTabela (Leitor/lib/tabela.mjs): linhas por destino, sha256, bytes, formato.';
comment on column aging_importado.aplicador is 'O resumo do aplicador do mapeamento (Leitor/lib/mapeamento.mjs): títulos, subtotais, rejeitadas por motivo com o saldo, conferência com o total do arquivo.';
comment on column aging_importado.importado_por is 'auth.uid() de quem importou. Sem FK de propósito: a autoria sobrevive à saída do usuário.';
comment on column aging_importado.mapeamento_id is 'O mapeamento confirmado (0272) com que o arquivo foi lido: arquivo sem mapeamento confirmado não vira dado.';

alter table aging_importado enable row level security;
create policy aging_importado_read on aging_importado for select to authenticated
  using ((select fn_eh_socio()) or caso_id in (select c from fn_casos_legiveis() c));
-- Sem policy de insert/update/delete: a escrita é a função (security definer).

grant select on aging_importado to authenticated;
grant select, insert, update, delete on aging_importado to service_role;

-- ---------------------------------------------------------------------------
-- 3. O BALANÇO: EM QUE DATA FECHA, E AS LINHAS DE CADA CONCEITO
-- ---------------------------------------------------------------------------
create function fn_balanco_fecha_em(p_documento_id uuid, p_ano int)
returns table (fecha_em date, coluna text, observacao text)
language plpgsql stable set search_path = public, pg_temp as $$
declare
  v_ver uuid; v_tipo_doc text; v_pt text; v_pr text; v_col text; v_can text; v_anos int[]; m text[];
begin
  v_ver := fn_versao_atual(p_documento_id);
  select d.tipo_taxonomia, pe.tipo, pe.referencia into v_tipo_doc, v_pt, v_pr
    from documento d left join periodo pe on pe.id = d.periodo_id where d.id = p_documento_id;
  v_col := fn_coluna_periodo_do_ano(v_ver, p_ano);

  if v_col is not null then
    if v_col = E'\x01' then
      return query select null::date, null::text, format('o balanço tem colunas de período e nenhuma é de %s', p_ano);
      return;
    end if;
    m := regexp_match(v_col, '(\d{1,2})/(\d{1,2})/((?:19|20)\d{2})');
    if m is not null then
      begin return query select make_date(m[3]::int, m[2]::int, m[1]::int), v_col, null::text; return;
      exception when others then null; end;
    end if;
    if fn_periodo_e_parcial(v_col, v_tipo_doc, v_pt, v_pr) then
      return query select null::date, v_col, format('a coluna "%s" é de período parcial e não diz a data de fechamento', v_col);
      return;
    end if;
    return query select make_date(p_ano, 12, 31), v_col, null::text;
    return;
  end if;

  -- sem coluna de período: o período do PRÓPRIO documento
  v_can  := fn_periodo_canonico(v_pt, v_pr);
  v_anos := fn_anos_periodo(v_pt, v_pr);
  if cardinality(v_anos) = 0 then
    return query select null::date, null::text, format('o período do documento ("%s") não ancora ano nenhum', coalesce(v_pr, 'sem período'));
    return;
  end if;
  if not (p_ano = any(v_anos)) then
    return query select null::date, null::text, format('o balanço é de %s e não traz o exercício %s', v_pr, p_ano);
    return;
  end if;
  if v_can ~ '^\d{4}-\d{2}-\d{2}$' then
    begin return query select v_can::date, null::text, null::text; return;
    exception when others then null; end;
  end if;
  m := regexp_match(v_can, '^(\d{1,2})m(\d{4})$');
  if m is not null then
    begin return query select (make_date(m[2]::int, m[1]::int, 1) + interval '1 month - 1 day')::date, null::text, null::text; return;
    exception when others then null; end;
  end if;
  m := regexp_match(v_can, '^(\d{1,2})/(\d{4})$');
  if m is not null then
    begin return query select (make_date(m[2]::int, m[1]::int, 1) + interval '1 month - 1 day')::date, null::text, null::text; return;
    exception when others then null; end;
  end if;
  m := regexp_match(v_can, '^([1-4])t(\d{4})$');
  if m is not null then
    return query select (make_date(m[2]::int, m[1]::int * 3, 1) + interval '1 month - 1 day')::date, null::text, null::text;
    return;
  end if;
  if fn_periodo_e_parcial(null, v_tipo_doc, v_pt, v_pr) then
    return query select null::date, null::text, format('o período do documento ("%s") é parcial e não diz a data de fechamento', v_pr);
    return;
  end if;
  if cardinality(v_anos) = 1 then
    return query select make_date(p_ano, 12, 31), null::text, null::text;
    return;
  end if;
  return query select null::date, null::text,
    format('o período do documento ("%s") cobre vários exercícios e não há coluna de período para dizer qual', v_pr);
end $$;
comment on function fn_balanco_fecha_em(uuid, int) is
  '0274: em que DATA o balanço fecha no exercício pedido (a conciliação do aging só compara saldos da MESMA data). Coluna com data vale a data; coluna ou período de um exercício só = 31/12; mensal e trimestral = fim do mês/trimestre. Parcial sem data, ano que o documento não traz e vários exercícios sem coluna = NULL com a observação (nunca palpite). Devolve (fecha_em, coluna, observacao).';

create function fn_aging_linhas_do_balanco(p_versao uuid, p_conceito text, p_col_ent text, p_col_per text)
returns table (id uuid, chave text, valor_num numeric, unidade text, secao text)
language plpgsql stable set search_path = public, pg_temp as $$
#variable_conflict use_column
declare
  v_inc text;
  v_exc text;
  c_ded constant text := 'perda|pecld|pdd|duvidos|provis|descontad|antecipa|ajuste a valor presente';
begin
  v_inc := case p_conceito
             when 'clientes'                     then 'cliente|duplicatas? a receber'
             when 'fornecedores'                 then 'fornecedor'
             when 'adiantamentos_de_clientes'    then 'adiant.*cliente'
             when 'adiantamentos_a_fornecedores' then 'adiant.*fornecedor' end;
  if v_inc is null then
    raise exception 'conceito "%" não existe (clientes, fornecedores, adiantamentos_de_clientes, adiantamentos_a_fornecedores)', p_conceito using errcode = '22023';
  end if;
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
  ), cand as (
    select distinct on (b.n) b.* from base b where b.n ~ v_inc and b.n !~ v_exc
     order by b.n, coalesce(b.confianca, 0) desc, b.ordem nulls last, b.id
  ), liquido as (   -- pai cuja dedução (PDD, descontadas) é filha: o valor dele é LÍQUIDO, não o bruto que a conciliação quer
    select c.n from cand c where exists (select 1 from base d where d.s = c.n and d.n ~ c_ded)
  )
  select c.id, c.chave, c.valor_num, c.unidade, c.secao from cand c
   where not exists (select 1 from cand p where p.n = c.s and p.n <> c.n and p.n not in (select n from liquido))
     and not (c.n in (select n from liquido) and exists (select 1 from cand f where f.s = c.n and f.n <> c.n))
   order by c.ordem nulls last, c.id;
end $$;
comment on function fn_aging_linhas_do_balanco(uuid, text, text, text) is
  '0274: as linhas do balanço (uma versão de documento) de um conceito, pelo rótulo normalizado e pelas colunas de entidade e período, como fn_valor_conceito_col, mas devolvendo TODAS as linhas do conceito (mercado interno + externo somam). Pai e filhos: o pai vale sozinho (os filhos não somam de novo), salvo pai com dedução (PDD, descontadas) como filho, que é líquido e cede aos filhos do conceito. Deduções, variações de fluxo, longo prazo e partes relacionadas ficam de fora; Clientes/Fornecedores também deixam de fora Adiantamentos.';

create function fn_aging_reais(p_valor numeric) returns text
language sql immutable set search_path = public, pg_temp as $$
  select 'R$ ' || translate(to_char(p_valor, 'FM999,999,999,999,990.00'), ',.', '.,')
$$;
comment on function fn_aging_reais(numeric) is '0274: reais no formato brasileiro (R$ 24.917.000,00) para as descrições das conciliações; independe de lc_numeric.';

-- ---------------------------------------------------------------------------
-- 4. A CONCILIAÇÃO
-- ---------------------------------------------------------------------------
create function fn_reconciliar_aging(p_aging_id uuid) returns jsonb
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
begin
  select * into a from aging_importado where id = p_aging_id;
  if not found then return jsonb_build_object('executado', false, 'motivo', 'importação de aging não encontrada'); end if;
  if a.substituido_em is not null then
    return jsonb_build_object('executado', false, 'motivo', 'importação substituída por outra: só a vigente se concilia');
  end if;
  v_ano := extract(year from a.data_base)::int;
  v_tb  := case a.tipo_base when 'contas_a_receber' then 'contas a receber' else 'contas a pagar' end;
  v_cabeca := format('Carteira de %s em %s (arquivo "%s")', v_tb, to_char(a.data_base, 'DD/MM/YYYY'), a.arquivo_nome);

  -- O balanço da entidade que fecha NA data-base.
  for r in select d.id, d.tipo_taxonomia, d.periodo_id from documento d
            where d.caso_id = a.caso_id and d.entidade_id = a.entidade_id and d.tipo_taxonomia in ('BALANCO', 'COMBINADO', 'BALANCETE')
            order by array_position(array['BALANCO', 'COMBINADO', 'BALANCETE'], d.tipo_taxonomia), d.criado_em desc, d.id loop
    v_n_docs := v_n_docs + 1;
    select * into f from fn_balanco_fecha_em(r.id, v_ano);
    if f.fecha_em is distinct from a.data_base then
      v_notas := v_notas || format('%s %s', r.tipo_taxonomia,
        coalesce('fecha em ' || to_char(f.fecha_em, 'DD/MM/YYYY') || ', não em ' || to_char(a.data_base, 'DD/MM/YYYY'), f.observacao));
      continue;
    end if;
    v_ver := fn_versao_atual(r.id);
    v_col_ent := fn_coluna_entidade(v_ver, a.entidade_id);
    if v_col_ent = E'\x01' then
      v_sem_ent := true; v_notas := v_notas || format('%s fecha em %s mas não tem coluna desta entidade', r.tipo_taxonomia, to_char(a.data_base, 'DD/MM/YYYY'));
      continue;
    end if;
    v_doc := r.id; v_periodo := r.periodo_id;
    exit;
  end loop;
  if v_doc is not null then
    v_col_per := fn_coluna_periodo_do_ano(v_ver, v_ano);
    if v_col_per = E'\x01' then v_col_per := null; end if;
  end if;

  -- A chave do período para a guarda de fn_registrar_reconciliacao (a do balanço escolhido; sem balanço, nenhuma).
  perform set_config('oria.periodo_chave', coalesce(v_periodo::text, ''), true);

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
          v_cabeca || format(': sem par para reconciliar, o balanço desta entidade não foi entregue (%s de %s, sem conta do balanço para conferir).', v_cfg.rotulo_aging, fn_aging_reais(v_aging))));
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
           coalesce(bool_or(fn_fator_escala(l.unidade) is null), false), array_agg(format('"%s" = %s %s', l.chave, l.valor_num, coalesce(l.unidade, 'sem escala')) order by l.chave)
      into v_n_lin, v_balanco, v_soma_fatores, v_sem_escala, v_chaves
      from fn_aging_linhas_do_balanco(v_ver, v_cfg.conceito, v_col_ent, v_col_per) l;
    v_fb := case when v_n_lin = 0 then null else jsonb_build_object('chaves', to_jsonb(v_chaves), 'valor', v_balanco, 'unidade', 'unidade', 'documento_versao_id', v_ver) end;

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
              else format('Diferença de %s, acima de %s (o arredondamento da escala do balanço).%s', fn_aging_reais(v_div), fn_aging_reais(v_tol), v_ressalva) end;
    v_res := v_res || jsonb_build_array(fn_registrar_reconciliacao(a.caso_id, a.entidade_id, v_periodo, v_cfg.tipo, 'A', v_doc, v_fa, v_fb,
      v_resultado, v_div, v_pct, jsonb_build_object('tolerancia_abs', v_tol, 'criterio', 'meia_unidade_da_escala'), v_desc));
  end loop;

  perform set_config('oria.periodo_chave', coalesce(v_prev_chave, ''), true);
  return jsonb_build_object('executado', true, 'aging_id', p_aging_id, 'checagens', v_res);
end $$;
comment on function fn_reconciliar_aging(uuid) is
  '0274: concilia UMA importação vigente de aging com o balanço extraído da entidade que fecha na data-base: saldos positivos × Clientes (a receber) ou Fornecedores (a pagar), negativos × Adiantamentos de clientes/a fornecedores. Tolerância = meia unidade da escala do balanço (nunca percentual). Tipos aging_ar_clientes, aging_ar_adiantamentos, aging_ap_fornecedores, aging_ap_adiantamentos, classe A, por fn_registrar_reconciliacao com descrição sempre; divergência zero é gravada como conferida (ok, 0). Sem balanço = documento_ausente (sem pendência); balanço de outra data = sem_periodo_par. Só service_role e as funções definer chamam.';

create function fn_reconciliar_aging_do_caso(p_caso_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_id  uuid;
  v_res jsonb := '[]'::jsonb;
  v_um  jsonb;
begin
  if p_caso_id is null or not (fn_conexao_de_servico() or fn_pode_escrever_caso(p_caso_id)) then
    raise exception 'Reconciliar o aging exige ser Sócio ou Analista alocado neste mandato (ou a conexão de serviço)' using errcode = '42501';
  end if;
  for v_id in select id from aging_importado where caso_id = p_caso_id order by data_base, tipo_base, id loop
    v_um := fn_reconciliar_aging(v_id);
    v_res := v_res || coalesce(v_um -> 'checagens', '[]'::jsonb);
  end loop;
  return v_res;
end $$;
comment on function fn_reconciliar_aging_do_caso(uuid) is
  '0274: concilia todas as importações VIGENTES de aging do mandato e devolve o array das checagens (o mesmo formato de fn_reconciliar_caso). É o ponto único para a rodada de reconciliações chamar quando um balanço novo chega depois da carteira (a ligação em fn_reconciliar_caso NÃO está nesta migration). Só Sócio, Analista do mandato ou a conexão de serviço (42501).';

-- ---------------------------------------------------------------------------
-- 5. A IMPORTAÇÃO
-- ---------------------------------------------------------------------------
create function fn_aging_importar(p_caso uuid, p_entidade uuid, p_tipo_base text, p_data_base date, p_resumo jsonb, p_leitura jsonb,
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
  '0274: guarda o resumo do aging de uma importação, por mandato e entidade, e o concilia com o balanço extraído. Só quem escreve o mandato (fn_pode_escrever_caso: Sócio, Analista alocado); os demais, o anônimo e a conexão de serviço recebem 42501. Recusa (22023, com todos os motivos) resumo que não fecha consigo mesmo, entidade de outro mandato, leitura parcial, sha256 divergente, arquivo inválido e mapeamento inexistente ou de outro tipo_base. Reimportar a mesma (entidade, tipo_base, data_base) substitui a vigente SEM apagar. Grava aging_importado em evento_auditoria (caso:<id>). Devolve {id, substitui, conciliacao}.';

do $$
declare f text;
begin
  foreach f in array array['fn_aging_centavos(jsonb)', 'fn_aging_contagem(jsonb)', 'fn_aging_resumo_erros(jsonb, date)', 'fn_balanco_fecha_em(uuid, int)',
                           'fn_aging_linhas_do_balanco(uuid, text, text, text)', 'fn_aging_reais(numeric)', 'fn_aging_importar(uuid, uuid, text, date, jsonb, jsonb, jsonb, jsonb, uuid)',
                           'fn_reconciliar_aging_do_caso(uuid)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
    if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
      execute format('grant execute on function %s to supabase_read_only_user', f);
    end if;
  end loop;
  -- A conciliação de UMA importação escreve em reconciliacao/pendencia: só o service_role e as funções definer (que rodam como dono).
  revoke all on function fn_reconciliar_aging(uuid) from public, anon, authenticated;
  grant execute on function fn_reconciliar_aging(uuid) to service_role;
end $$;

-- ---------------------------------------------------------------------------
-- 6. A SONDA. Marcadores em CÓDIGO, nunca de comentário.
-- ---------------------------------------------------------------------------
create view instalacao_sonda_aging_uma_vigente as
  select i.indexrelid::regclass::text as indice
    from pg_index i
    join pg_class c on c.oid = i.indexrelid and c.relname = 'aging_importado_uma_vigente'
   where i.indrelid = 'public.aging_importado'::regclass
     and i.indisunique and i.indisvalid
     and i.indpred is not null
     and pg_get_indexdef(i.indexrelid) like '%(caso_id, entidade_id, tipo_base, data_base)%'
     and pg_get_expr(i.indpred, i.indrelid) like '%substituido_em IS NULL%';
comment on view instalacao_sonda_aging_uma_vigente is
  'Sonda da 0274: uma linha = o índice único parcial (caso_id, entidade_id, tipo_base, data_base) where substituido_em is null existe e é válido. Zero linhas: duas importações vigentes da mesma carteira e a conciliação usa uma delas ao acaso.';
grant select on instalacao_sonda_aging_uma_vigente to authenticated, service_role;

create view instalacao_sonda_aging_checks as
  select count(*)::text as n
    from pg_constraint k
   where k.conrelid = 'public.aging_importado'::regclass and k.contype = 'c' and k.convalidated
     and ((k.conname = 'aging_resumo_fecha' and pg_get_constraintdef(k.oid) like '%fn_aging_resumo_erros(%')
       or (k.conname = 'aging_arquivo_inteiro' and pg_get_constraintdef(k.oid) like '%[0-9a-f]{64}%')
       or (k.conname = 'aging_leitura_e_aplicador_objetos' and pg_get_constraintdef(k.oid) like '%jsonb_typeof(aplicador)%')
       or (k.conname = 'aging_substituicao_inteira' and pg_get_constraintdef(k.oid) like '%substituido_em IS NULL%'))
  having count(*) = 4;
comment on view instalacao_sonda_aging_checks is
  'Sonda da 0274: uma linha = as quatro CHECKs (resumo que fecha; arquivo inteiro; leitura e aplicador objetos; substituição inteira) existem, validadas. Zero linhas: o service_role grava resumo incoerente ou arquivo sem hash.';
grant select on instalacao_sonda_aging_checks to authenticated, service_role;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('aging_tabela', '0274', 'tabela', 'aging_importado', null, null,
   'Onde o resumo do aging de cada importação é guardado, por mandato. Ausente = a 0274 não foi aplicada: a carteira se perde ao fechar a aba e nunca é conferida com o balanço.',
   'importante', 1340),
  ('aging_importar_funcao', '0274', 'funcao', 'fn_aging_importar', null, null,
   'A porta de escrita do aging (o authenticated não tem grant nem policy de escrita na tabela). Ausente = ninguém importa.',
   'importante', 1341),
  ('aging_resumo_erros_funcao', '0274', 'funcao', 'fn_aging_resumo_erros', null, null,
   'O validador da fronteira de confiança (o resumo vem do navegador), usado pela função e pela CHECK da tabela. Ausente = a tabela não existe em estado completo.',
   'importante', 1342),
  ('aging_conciliar_funcao', '0274', 'funcao', 'fn_reconciliar_aging', null, null,
   'A conciliação do aging com Clientes/Fornecedores e os Adiantamentos do balanço. Ausente = a carteira é guardada e nunca conferida.',
   'importante', 1343),
  ('aging_conciliar_caso_funcao', '0274', 'funcao', 'fn_reconciliar_aging_do_caso', null, null,
   'O ponto único para a rodada de reconciliações conciliar a carteira quando o balanço chega depois. Ausente = o balanço novo não reconcilia a carteira que já estava.',
   'importante', 1344),
  ('aging_linhas_funcao', '0274', 'funcao', 'fn_aging_linhas_do_balanco', null, null,
   'A busca das linhas de Clientes/Fornecedores/Adiantamentos no balanço extraído. Ausente = a conciliação não acha a conta.',
   'importante', 1345),
  ('aging_fechamento_funcao', '0274', 'funcao', 'fn_balanco_fecha_em', null, null,
   'A data em que o balanço fecha. Ausente = a conciliação não sabe se compara dezembro com junho.',
   'importante', 1346),
  ('aging_importar_escreve_mandato', '0274', 'corpo', 'fn_aging_importar', 'not fn_pode_escrever_caso(p_caso)', null,
   'Só quem escreve o mandato importa. Corpo sem isto = a Leitura, o Analista de OUTRO mandato e quem não tem papel gravam carteira (dado do cliente) num mandato que não é deles.',
   'bloqueante', 1347),
  ('aging_importar_concilia', '0274', 'corpo', 'fn_aging_importar', 'fn_reconciliar_aging(', null,
   'A importação concilia na hora. Corpo sem isto = o aging é guardado e só é conferido se alguém lembrar de chamar a conciliação (estágio que não rodou parece limpo).',
   'importante', 1348),
  ('aging_conciliar_meia_unidade', '0274', 'corpo', 'fn_reconciliar_aging', 'v_tol := v_soma_fatores / 2', null,
   'A tolerância é a meia unidade da escala do balanço (arredondamento), nunca percentual. Corpo sem isto = ou a diferença de R$ mil some, ou uma tolerância percentual esconde diferença real.',
   'bloqueante', 1349),
  ('aging_conciliar_data_base', '0274', 'corpo', 'fn_reconciliar_aging', 'fn_balanco_fecha_em(', null,
   'A conciliação só compara balanço que fecha na data-base. Corpo sem isto = a carteira de junho é comparada com o balanço de dezembro e sai "conferido" ou divergência falsa.',
   'bloqueante', 1350),
  ('aging_leitura_policy', '0274', 'policy', 'aging_importado.aging_importado_read', null, null,
   'RLS ligada sem policy de leitura devolve zero calado: a carteira importada pareceria nunca ter existido.',
   'importante', 1351),
  ('aging_uma_vigente', '0274', 'comportamento', 'instalacao_sonda_aging_uma_vigente', null, 1,
   'O índice único parcial que garante UMA vigente por (mandato, entidade, tipo_base, data_base). Zero linhas = duas carteiras vigentes da mesma data e a conciliação lê uma delas ao acaso.',
   'importante', 1352),
  ('aging_checks', '0274', 'comportamento', 'instalacao_sonda_aging_checks', null, 1,
   'As CHECKs da tabela (resumo que fecha, arquivo inteiro, objetos, substituição). Zero linhas = o service_role grava resumo incoerente ou arquivo sem hash.',
   'importante', 1353)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0274', revisado_em = current_date,
       observacao = 'A 0274 cria aging_importado (o resumo do aging de contas a receber/a pagar, POR MANDATO e entidade, RLS da 0216), fn_aging_importar, fn_aging_resumo_erros, fn_reconciliar_aging (positivos × Clientes/Fornecedores, negativos × Adiantamentos, tolerância de meia unidade da escala), fn_reconciliar_aging_do_caso, fn_balanco_fecha_em e fn_aging_linhas_do_balanco. 14 requisitos novos (ordem 1340-1353).'
 where id = true;

commit;
