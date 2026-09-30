import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalize } from '../lib/normalize.mjs';
import { classifyByFilename, parseEntidade, parsePeriodo, parseTipo } from '../lib/classifier.mjs';
import { ALIASES } from '../lib/taxonomia.mjs';

test('normalize remove acento, extensão e separadores', () => {
  assert.equal(normalize('12M25_DRE (Assinado).pdf'), '12m25 dre (assinado)');
  assert.equal(normalize('Balanço-Patrimonial.XLSX'), 'balanco patrimonial');
  assert.equal(normalize(null), '');
});

test('parsePeriodo reconhece as convenções de Arquitetura do Sistema/2 Especificação/f0/03', () => {
  assert.deepEqual(parsePeriodo('12m25 dre'), { tipo: 'anual', referencia: '12M25' });
  assert.deepEqual(parsePeriodo('12m24 balanco'), { tipo: 'anual', referencia: '12M24' });
  assert.deepEqual(parsePeriodo('1t25 dre'), { tipo: 'trimestre', referencia: '1T25' });
  assert.deepEqual(parsePeriodo('1t26 balanco'), { tipo: 'trimestre', referencia: '1T26' });
  assert.deepEqual(parsePeriodo('faturamento l24m'), { tipo: 'multi', referencia: 'L24M' });
  assert.deepEqual(parsePeriodo('faturamento 36 meses'), { tipo: 'multi', referencia: 'L36M' });
  assert.deepEqual(parsePeriodo('mutuos 23 24 25'), { tipo: 'multi', referencia: '23,24,25' });
});

test('parsePeriodo reconhece ano isolado (sinal fraco)', () => {
  assert.deepEqual(parsePeriodo('balanco acumulado 2025'), { tipo: 'anual', referencia: '2025', fraco: true });
  assert.deepEqual(parsePeriodo('relatorio 2024'), { tipo: 'anual', referencia: '2024', fraco: true });
});

test('parsePeriodo reconhece intervalo de anos (expande a lista inteira)', () => {
  assert.deepEqual(parsePeriodo('mutuos 2021-2025'), { tipo: 'multi', referencia: '21,22,23,24,25' });
  assert.deepEqual(parsePeriodo('mutuos 2021 a 2025'), { tipo: 'multi', referencia: '21,22,23,24,25' });
  assert.deepEqual(parsePeriodo('mutuos 21-25'), { tipo: 'multi', referencia: '21,22,23,24,25' });
  assert.deepEqual(parsePeriodo('mutuos 2023-2024'), { tipo: 'multi', referencia: '23,24' });
});

test('parsePeriodo: intervalo invertido (fim < início) não expande, cai no fallback de lista', () => {
  // start > end: a expansão não roda; ainda assim os 2 números viram lista
  // multi-ano — ORDENADA, para que "2025-2021" e "2021,2025" tenham a MESMA
  // forma canônica (o mesmo critério de `fn_periodo_canonico` no Postgres:
  // notações equivalentes do mesmo período não podem parecer divergentes).
  assert.deepEqual(parsePeriodo('mutuos 2025-2021'), { tipo: 'multi', referencia: '21,25' });
});

test('parsePeriodo: a ordem multi-ano é CRONOLÓGICA, e não sobrevive à truncagem', () => {
  // A forma canônica acima só vale se a ordenação for do ANO, não do texto de
  // dois dígitos. O código truncava para 2 dígitos ANTES de ordenar e chamava
  // `.sort()` sem comparador: 1999 e 2001 viravam "99" e "01", e a ordem de
  // texto devolvia "01,99" — 2001 declarado antes de 1999.
  //
  // MEDIDO, com a correção desligada (truncar-depois-ordenar): este assert
  // reprova com `'01,99' !== '99,01'`. Os outros 400 continuam passando, porque
  // nenhum documento dos dois books cruza o século — é defeito LATENTE, e o
  // custo dele é a forma canônica que a `fn_periodo_canonico` do Postgres
  // espera do outro lado deixar de ser a mesma.
  assert.deepEqual(parsePeriodo('balanco comparativo 1999 2001'),
    { tipo: 'multi', referencia: '99,01' });

  // E o caso que produção realmente vê não muda: século único, ordem idêntica
  // pelos dois critérios. Este par existe para que a correção não passe a
  // reprovar o comum ao consertar o raro.
  assert.deepEqual(parsePeriodo('dre 2023 2024 2025'),
    { tipo: 'multi', referencia: '23,24,25' });
  assert.deepEqual(parsePeriodo('dre 2025 2023 2024'),
    { tipo: 'multi', referencia: '23,24,25' });
});

test('parsePeriodo: prefixo de ORDENAÇÃO do arquivo não é ano (bug real do teste v24)', () => {
  // "13_Balancete_..._2025.pdf" saía como período "multi 13,25" — o "13" do
  // prefixo virava 2013. Além de exibir errado, fragmentava a tabela `periodo`
  // e impedia a reconciliação de casar documentos do mesmo exercício.
  assert.deepEqual(parsePeriodo('13 balancete analitico componentes 2025'),
    { tipo: 'anual', referencia: '2025', fraco: true });
  assert.deepEqual(parsePeriodo('08 dfc vertentes metalurgica 2025'),
    { tipo: 'anual', referencia: '2025', fraco: true });
  // "2025x2024" é o padrão de nome de demonstração comparativa.
  assert.deepEqual(parsePeriodo('01 bp vertentes metalurgica 2025x2024'),
    { tipo: 'multi', referencia: '24,25' });
  // Não regride os formatos estruturados nem o ano isolado.
  assert.deepEqual(parsePeriodo('12m25 dre'), { tipo: 'anual', referencia: '12M25' });
  assert.deepEqual(parsePeriodo('1t25 dre'), { tipo: 'trimestre', referencia: '1T25' });
  assert.deepEqual(parsePeriodo('faturamento 36 meses'), { tipo: 'multi', referencia: 'L36M' });
  assert.deepEqual(parsePeriodo('balanco acumulado 2025'), { tipo: 'anual', referencia: '2025', fraco: true });
});

test('parseTipo mapeia termos → código, específico antes de genérico', () => {
  assert.equal(parseTipo('dre').codigo, 'DRE');
  assert.equal(parseTipo('balanco patrimonial').codigo, 'BALANCO');
  assert.equal(parseTipo('fluxo de caixa').codigo, 'FLUXO_CAIXA');
  assert.equal(parseTipo('combinado').codigo, 'COMBINADO');
  assert.equal(parseTipo('contrato social').codigo, 'CONTRATO_SOCIAL');
  assert.equal(parseTipo('relacao de mutuos').codigo, 'MUTUOS');
  // "faturamento intragrupo" NÃO pode cair em FATURAMENTO_24M
  assert.equal(parseTipo('faturamento intragrupo').codigo, 'FAT_INTRAGRUPO');
  assert.equal(parseTipo('faturamento 24m').codigo, 'FATURAMENTO_24M');
  // balancete (variável) não pode ser confundido com balanço
  assert.equal(parseTipo('balancete').codigo, 'BALANCETE');
});

test('parseTipo reconhece DMPL e DVA (Supabase/migrations/0024) sem roubar o arquivo COMPOSTO', () => {
  // Antes da 0024 não existia código nenhum para estas duas: o enum que a IA
  // recebe (`codigosConhecidos`) é fechado nos códigos da taxonomia, e a DMPL do
  // book saía classificada como MUTUOS — o vizinho mais próximo do que existia.
  assert.equal(parseTipo(normalize('09_DMPL_Vertentes_Metalurgica_2025.pdf')).codigo, 'DMPL');
  assert.equal(parseTipo(normalize('Demonstração das Mutações do Patrimônio Líquido 2025.pdf')).codigo, 'DMPL');
  assert.equal(parseTipo(normalize('DVA 2025.pdf')).codigo, 'DVA');
  assert.equal(parseTipo(normalize('Demonstração do Valor Adicionado 2025.pdf')).codigo, 'DVA');

  // …e a regressão que a ORDEM dos aliases protege: o caso comum de "DMPL" no
  // nome de arquivo NÃO é a DMPL — é o arquivo COMPOSTO (este é um nome real do
  // dono), em que a DMPL é uma das demonstrações e o tipo do documento é o da
  // demonstração PRINCIPAL (Arquitetura do Sistema/2 Especificação/f0/03). Se DMPL/DVA fossem testados antes das
  // demonstrações principais, estes dois arquivos mudariam de tipo.
  // (Qual das principais ganha é decisão anterior a esta fatia: aqui 'dfc' casa
  // FLUXO_CAIXA antes de 'balanco'. O que importa é que não vira DMPL — e o
  // diagnóstico por CONTEÚDO, que é quem decide de fato, corrige o resto.)
  const composto = parseTipo(normalize('Balanço Patrimonial DRE, DFC, DMPL Global One 2024assinado.pdf'));
  assert.notEqual(composto.codigo, 'DMPL');
  assert.equal(composto.codigo, 'FLUXO_CAIXA');
  assert.equal(parseTipo(normalize('DRE e DVA consolidadas 2025.pdf')).codigo, 'DRE');
});

test('classifyByFilename — nomes descritivos dão alta confiança', () => {
  const r = classifyByFilename('12M25 DRE (Assinado).pdf');
  assert.equal(r.tipo_taxonomia, 'DRE');
  assert.deepEqual(r.periodo, { tipo: 'anual', referencia: '12M25' });
  assert.equal(r.assinado, true);
  assert.ok(r.confianca >= 0.9, `confianca=${r.confianca}`);
  assert.equal(r.precisa_fallback_ia, false);
});

test('classifyByFilename — nome genérico cai para fallback OpenAI', () => {
  const r = classifyByFilename('documento_final_v2.pdf');
  assert.equal(r.tipo_taxonomia, null);
  assert.equal(r.periodo, null);
  assert.ok(r.confianca < 0.7);
  assert.equal(r.precisa_fallback_ia, true);
});

test('classifyByFilename — tipo sem período ainda pede fallback (confiança 0.6)', () => {
  const r = classifyByFilename('balanco.pdf');
  assert.equal(r.tipo_taxonomia, 'BALANCO');
  assert.equal(r.periodo, null);
  assert.equal(r.confianca, 0.6);
  assert.equal(r.precisa_fallback_ia, true); // < 0.7
});

test('classifyByFilename — tipo + ano isolado NÃO ultrapassa o limiar sozinho (sempre verifica com a IA)', () => {
  // Caso real: "BALANÇO ACUMULADO 2025.pdf" — ter "BALANÇO" no nome + um ano
  // solto não é suficiente para aceitar sem checar o conteúdo (feedback do dono).
  const r = classifyByFilename('BALANÇO ACUMULADO 2025.pdf');
  assert.equal(r.tipo_taxonomia, 'BALANCO');
  assert.deepEqual(r.periodo, { tipo: 'anual', referencia: '2025', fraco: true });
  assert.equal(r.confianca, 0.65, `confianca=${r.confianca} deve ficar abaixo do limiar 0.7`);
  assert.equal(r.precisa_fallback_ia, true, 'ano isolado não deve pular a verificação da IA');
});

test('classifyByFilename — o CONJUNTO do exercício é DF_AUDITADA, e nome com demonstração principal não é', () => {
  // Como o conjunto chega de verdade: um PDF só, com tudo dentro. Antes ficava
  // SEM TIPO (a taxonomia só reconhecia "auditadas"), e documento sem tipo não
  // ganha aba de demonstração nenhuma no export.
  for (const nome of [
    'Demonstrações Contábeis 2025.pdf',
    'Demonstrações Financeiras 12M25.pdf',
    'DFs Grupo Vertentes 2025.pdf',
  ]) {
    assert.equal(classifyByFilename(nome).tipo_taxonomia, 'DF_AUDITADA', `tipo de ${nome}`);
  }
  // …e a fronteira: nome que diz QUAL demonstração é continua sendo dela — os
  // termos novos NÃO podem roubar esses casos. É o mesmo motivo pelo qual DMPL/DVA
  // vêm depois das principais.
  assert.equal(classifyByFilename('Demonstrações Combinadas 12M25.pdf').tipo_taxonomia, 'COMBINADO');
  assert.equal(classifyByFilename('Demonstração de Resultado 2025.pdf').tipo_taxonomia, 'DRE');
  assert.equal(classifyByFilename('Balanço Patrimonial 12M25.pdf').tipo_taxonomia, 'BALANCO');
  // Comportamento ANTERIOR a esta fatia, preservado de propósito: o PDF composto
  // que lista as demonstrações no nome ("Balanço Patrimonial DRE, DFC 2024.pdf",
  // arquivo real do dono) casa FLUXO_CAIXA pelo "dfc", porque FLUXO vem antes na
  // lista. Não mexo aqui: promovê-lo a DF_AUDITADA (complementar) tiraria dele a
  // capacidade de satisfazer os itens OBRIGATÓRIOS do Kit Básico e mudaria a
  // completude de todo caso já aberto — decisão de produto do dono, não efeito
  // colateral de uma fatia de export. E, de qualquer forma, o roteamento por
  // linha já separa as demonstrações desse arquivo aba por aba.
  assert.equal(classifyByFilename('Balanço Patrimonial DRE, DFC 2024.pdf').tipo_taxonomia, 'FLUXO_CAIXA');
});

test('classifyByFilename — casos reais do mandato de referência', () => {
  const casos = [
    ['Balancetes 1T2026 Empresa A.pdf', 'BALANCETE', '1T26'],
    ['12M24 Combinado Assinado.pdf', 'COMBINADO', '12M24'],
    ['Faturamento 36 meses.xlsx', 'FATURAMENTO_24M', 'L36M'],
    ['Balanço Patrimonial 12M25.pdf', 'BALANCO', '12M25'],
  ];
  for (const [nome, tipo, ref] of casos) {
    const r = classifyByFilename(nome);
    assert.equal(r.tipo_taxonomia, tipo, `tipo de ${nome}`);
    assert.equal(r.periodo?.referencia, ref, `periodo de ${nome}`);
  }
});

// --- Entidade a partir do nome do arquivo (correção do "teste v31") ----------
// No v31 o dashboard mostrou entidade "—" nos 14 documentos, INCLUSIVE nos 6 que
// extraíram sem erro. A causa era `entidade: null` fixo aqui: nos documentos que
// o nome classifica acima do limiar a IA de classificação nunca roda, então a
// única fonte de entidade era o diagnóstico da extração — e a extração dos outros
// 8 morreu no teto de gasto da OpenAI, levando a entidade junto.
//
// Os nomes são os 14 REAIS do teste (Dados de Teste/book-vertentes), não inventados.
test('parseEntidade resolve a empresa nos 14 arquivos do teste v31', () => {
  const casos = [
    ['01_BP_Vertentes_Metalurgica_2025x2024.pdf', 'Vertentes Metalurgica'],
    ['02_BP_Vertentes_Componentes_2025x2024.pdf', 'Vertentes Componentes'],
    ['03_BP_Vertentes_Participacoes_2025x2024.pdf', 'Vertentes Participacoes'],
    // sigla fica em caixa alta: "Vt Logistica" leria como erro de digitação
    ['04_BP_VT_Logistica_2025x2024.pdf', 'VT Logistica'],
    ['05_BP_Vertentes_Imoveis_SPE_2025x2024.pdf', 'Vertentes Imoveis SPE'],
    // 'COMBINADO' é termo de TIPO, não parte do nome da empresa
    ['06_BP_COMBINADO_Grupo_Vertentes_2025.pdf', 'Grupo Vertentes'],
    ['07_DRE_Vertentes_Metalurgica_2025x2024.pdf', 'Vertentes Metalurgica'],
    ['08_DFC_Vertentes_Metalurgica_2025.pdf', 'Vertentes Metalurgica'],
    ['09_DMPL_Vertentes_Metalurgica_2025.pdf', 'Vertentes Metalurgica'],
    ['10_Faturamento_24M_Vertentes_Metalurgica.pdf', 'Vertentes Metalurgica'],
    ['11_Mapa_Divida_Vertentes_Metalurgica_2025.pdf', 'Vertentes Metalurgica'],
    // 'Intragrupo' descreve o documento; sem removê-lo viria "Intragrupo Grupo Vertentes"
    ['12_Mutuos_Intragrupo_Grupo_Vertentes_2025.pdf', 'Grupo Vertentes'],
    // o nome só diz "Componentes" — devolver isso é honesto; o conteúdo refina
    ['13_Balancete_Analitico_Componentes_2025.pdf', 'Componentes'],
    ['14_Notas_Explicativas_Grupo_Vertentes_2025.pdf', 'Grupo Vertentes'],
  ];
  for (const [nome, entidade] of casos) {
    assert.equal(classifyByFilename(nome).entidade, entidade, `entidade de ${nome}`);
  }
});

// --- A entidade poluída, medida nos 38 nomes do book-canastra (17/08) --------
// Na rodada real, 15 das 22 pendências de revisão nasceram daqui: o nome dizia
// "Canastra Industria 2025x2024x2023" e o conteúdo dizia "Canastra Industria",
// então `fn_registrar_diagnostico` abria pendência de DIVERGÊNCIA em documento
// que estava certo. Quatro famílias de sujeira, cada uma com o seu caso abaixo.

test('comparativo de TRÊS exercícios não vira parte do nome da empresa', () => {
  // `^\d{2,4}x\d{2,4}$` casava "2025x2024" e não "2025x2024x2023" — o formato
  // que os dois maiores documentos do book usam.
  assert.equal(classifyByFilename('01_Balanco_Patrimonial_Canastra_Industria_2025x2024x2023.pdf').entidade,
    'Canastra Industria');
  assert.equal(classifyByFilename('02_DRE_Canastra_Industria_2025x2024x2023.pdf').entidade,
    'Canastra Industria');
  // E o comparativo de dois continua valendo, com qualquer profundidade.
  assert.equal(classifyByFilename('06_Balanco_Patrimonial_Canastra_Comercial_2025x2024.pdf').entidade,
    'Canastra Comercial');
});

test('preposição e sobra de tipo saem do nome — a fonte é a própria taxonomia', () => {
  // "aging de contas a pagar": o alias casado é o pedaço curto, e "aging" ficava.
  assert.equal(classifyByFilename('23_Aging_de_Contas_a_Pagar_Canastra_Industria_2025.pdf').entidade,
    'Canastra Industria');
  assert.equal(classifyByFilename('24_Posicao_de_Estoques_Canastra_Industria_2025.pdf').entidade,
    'Canastra Industria');
  assert.equal(classifyByFilename('18_Faturamento_36_meses_Canastra_Industria_2023_a_2025.pdf').entidade,
    'Canastra Industria');
  // "grupo" é a exceção protegida: está no vocabulário de tipo (`faturamento
  // intra grupo`) E no nome que o documento combinado usa no cabeçalho. Tirá-lo
  // faria o nome divergir do conteúdo — a pendência que isto veio fechar.
  assert.equal(classifyByFilename('13_Balanco_COMBINADO_Grupo_Canastra_2025.pdf').entidade, 'Grupo Canastra');
  assert.equal(classifyByFilename('21_Mutuos_Intragrupo_Grupo_Canastra_2025.pdf').entidade, 'Grupo Canastra');
});

// Lote 7377 (02/09, book "teste Canastra"): `28_Folha_de_Pagamento` abriu
// `classificacao_pendente` com confiança da IA 0,9 porque HEADCOUNT (já
// existente na taxonomia — seed 0002, "Headcount / folha de pagamento") não
// tinha alias nenhum: nem para o classificador por nome, nem — mais grave —
// no enum que `codigosConhecidos()` (ia.mjs) monta a partir de `ALIASES`
// para a saída presa da IA (ver ia.test.mjs). Antes do alias, este arquivo
// caía na lista "nome que não diz o tipo" abaixo (entidade null, sinais.tipo
// false); depois, sinais.tipo é true e a entidade sai limpa — sem "Folha" e
// "Pagamento" grudados, porque `parseEntidade` varre o vocabulário da
// própria taxonomia.
test('HEADCOUNT: "folha de pagamento" classifica e não vaza no nome da empresa', () => {
  const r = classifyByFilename('28_Folha_de_Pagamento_Canastra_Industria_2025.pdf');
  assert.equal(r.tipo_taxonomia, 'HEADCOUNT');
  assert.equal(r.sinais.tipo, true);
  assert.equal(r.entidade, 'Canastra Industria');
});

// Achado do revisor sobre 66ee751 (08/09): o alias HEADCOUNT
// ('folha de pagamento' é ASSUNTO, não TIPO) inserido acima das famílias de
// tipo específico roubava seis nomes reais em que "folha de pagamento"
// aparece como assunto de um documento de OUTRO tipo — `parseTipo` para no
// primeiro alias que casa, e a regra da lista (linha 29-30 de taxonomia.mjs)
// é "o mais específico primeiro". Medido antes/depois do commit: os seis
// saíam do tipo certo e passaram a sair HEADCOUNT. Isto fixa a ordem —
// HEADCOUNT tem de ficar depois de toda família de tipo que a citação
// "folha de pagamento" pode cruzar.
test('HEADCOUNT não rouba nomes cujo TIPO real cita "folha de pagamento" como assunto', () => {
  const casos = [
    ['30_Parcelamento_INSS_sobre_Folha_de_Pagamento_Canastra_2025.pdf', 'SITUACAO_FISCAL'],
    ['Situacao_Fiscal_e_Parcelamentos_de_Folha_de_Pagamento.pdf', 'SITUACAO_FISCAL'],
    ['33_Notas_Explicativas_Despesa_com_Folha_de_Pagamento_2025.pdf', 'NOTAS_EXPL'],
    ['Certidao_Negativa_Debitos_Trabalhistas_folha_de_pagamento.pdf', 'CERTIDOES'],
    ['Contingencias_Trabalhistas_Folha_de_Pagamento.pdf', 'CONTINGENCIAS'],
    ['Organograma_Societario_com_Headcount_2025.pdf', 'ORGANOGRAMA'],
  ];
  for (const [nome, tipoEsperado] of casos) {
    assert.equal(classifyByFilename(nome).tipo_taxonomia, tipoEsperado, nome);
  }
});

test('nome que não diz o TIPO não arrisca dizer a empresa', () => {
  // Sem tipo, o que sobra é o próprio nome do documento — e ele não é empresa.
  assert.equal(classifyByFilename('34_Relatorio_do_Auditor_Independente_2025.pdf').entidade, null);
  assert.equal(classifyByFilename('ANEXO IV - planilha final REV3.pdf').entidade, null);
  assert.equal(classifyByFilename('Doc1.pdf').entidade, null);
  // Sequência de scanner: token só de dígitos nunca é nome de empresa.
  assert.equal(classifyByFilename('digitalizado_20260115_0003.pdf').entidade, null);
  // E o silêncio não custa hipótese: todos estes vão para a classificação por
  // conteúdo, que lê a entidade do documento.
  for (const nome of ['34_Relatorio_do_Auditor_Independente_2025.pdf', 'Doc1.pdf']) {
    assert.equal(classifyByFilename(nome).precisa_fallback_ia, true, `${nome} vai ao fallback`);
  }
});

test('nenhum dos 38 nomes do book produz entidade suja', () => {
  // A guarda de classe, não de caso: qualquer nome do book ou devolve uma das
  // sete empresas do grupo, ou devolve null. Nada de terceira opção — foi a
  // terceira opção que encheu a fila de revisão.
  const empresas = new Set(['Canastra Industria', 'Canastra Comercial', 'Canastra Participacoes',
    'Cn Transportes', 'Canastra Agroflorestal', 'Canastra Imobiliaria SPE', 'Grupo Canastra']);
  const nomes = [
    '01_Balanco_Patrimonial_Canastra_Industria_2025x2024x2023.pdf',
    '17_Livro_Razao_Fornecedores_Canastra_Industria_12M25.pdf',
    '25_Situacao_Fiscal_e_Parcelamentos_Grupo_Canastra_2025.pdf',
    '27_Composicao_do_Imobilizado_Canastra_Industria_2025.pdf',
    '30_Certidoes_Negativas_Grupo_Canastra.pdf',
    '32_Organograma_Societario_Grupo_Canastra.pdf',
    '33_Notas_Explicativas_Grupo_Canastra_12M25.pdf',
    '35_Demonstracoes_Contabeis_Canastra_Industria_2024x2023.pdf',
    '12_Balanco_Patrimonial_Canastra_Imobiliaria_SPE_2025x2024.pdf',
  ];
  for (const nome of nomes) {
    const e = classifyByFilename(nome).entidade;
    assert.ok(e === null || empresas.has(e), `${nome} → ${JSON.stringify(e)}`);
  }
});

// O invariante que protege a doutrina: a entidade é hipótese, e hipótese não
// compra dispensa da verificação da IA. Se alguém somar a entidade à confiança,
// os documentos de 0,65 sobem para 0,70+ e PARAM de ser conferidos pela IA —
// exatamente o tipo de subida de dial que Arquitetura do Sistema/1 Visão e Doutrina/01 proíbe sem golden set.
test('entidade do nome NÃO altera confiança nem o limiar de fallback', () => {
  const esperado = [
    ['01_BP_Vertentes_Metalurgica_2025x2024.pdf', 0.9, false],
    ['06_BP_COMBINADO_Grupo_Vertentes_2025.pdf', 0.65, true],
    ['10_Faturamento_24M_Vertentes_Metalurgica.pdf', 0.6, true],
  ];
  for (const [nome, conf, fallback] of esperado) {
    const r = classifyByFilename(nome);
    assert.ok(r.entidade, `${nome} tem hipótese de entidade`);
    assert.equal(r.confianca, conf, `confiança de ${nome} intacta`);
    assert.equal(r.precisa_fallback_ia, fallback, `fallback de ${nome} intacto`);
  }
});

test('parseEntidade se abstém quando o nome não carrega empresa', () => {
  // Só tipo + período: não há o que extrair, e inventar seria pior que nada.
  assert.equal(classifyByFilename('Balanço Patrimonial 12M25.pdf').entidade, null);
  assert.equal(classifyByFilename('DRE_2025.pdf').entidade, null);
  // Resto de 2 letras não identifica empresa nenhuma — não vira entidade-lixo.
  assert.equal(classifyByFilename('DRE_XY_2025.pdf').entidade, null);
  // contrato de auto-contenção: `parseEntidade` recebe os aliases por parâmetro
  // (é assim que o `toString()` dela funciona dentro do Code node do n8n) e não
  // pode estourar quando eles não vêm.
  assert.equal(parseEntidade('bp vertentes metalurgica 2025', []), 'Bp Vertentes Metalurgica');
  assert.equal(parseEntidade('bp vertentes metalurgica 2025', undefined), 'Bp Vertentes Metalurgica');
});

test('a palavra de tipo sai pela TAXONOMIA, sem lista à mão no classificador', () => {
  // Três nomes reais do book, e a sobra que cada um deixava grudada na empresa:
  // "Certidoes NEGATIVAS", "Organograma SOCIETARIO", "Situacao Fiscal e
  // PARCELAMENTOS". O alias que casava era o pedaço curto ('certidao',
  // 'organograma', 'situacao fiscal'), a segunda palavra sobrava, e
  // `parseEntidade` a removia por uma lista de RUÍDO escrita à mão — que é
  // exatamente o tipo de espelho manual que este repositório já viu divergir.
  for (const [nome, esperado] of [
    ['30_Certidoes_Negativas_Canastra_Industria_2025.pdf', 'Canastra Industria'],
    ['31_Organograma_Societario_Grupo_Canastra.pdf', 'Grupo Canastra'],
    ['32_Situacao_Fiscal_e_Parcelamentos_Canastra_Industria.pdf', 'Canastra Industria'],
  ]) {
    assert.equal(parseEntidade(normalize(nome), ALIASES), esperado, nome);
  }

  // E a PROVA de que quem faz o trabalho é a taxonomia, não uma lista escondida:
  // sem os aliases, as palavras de tipo VOLTAM a aparecer na entidade. Se alguém
  // reintroduzir a lista à mão, esta asserção falha — e é ela que impede o
  // conserto de virar dois lugares para manter de novo.
  assert.match(parseEntidade(normalize('30_Certidoes_Negativas_Canastra_Industria_2025.pdf'), []),
    /Negativas/);
  for (const palavra of ['negativas', 'societario', 'parcelamentos']) {
    assert.ok(
      ALIASES.some((a) => a.termos.includes(palavra)),
      `"${palavra}" tem de ser termo da taxonomia — é de lá que a remoção sai`);
  }
});

// --- O achado do book-canastra: razão de fornecedores não é aging de pagáveis -
//
// O arquivo "17_Livro_Razao_Fornecedores_Canastra_Industria_12M25.pdf" saía como
// AGING_AP com confiança 0,90 — alta o bastante para PULAR a verificação da IA e
// mandar um livro contábil para a aba de contas a pagar. A causa era a ordem da
// lista de ALIASES: 'fornecedores', termo de uma palavra, vinha antes de
// 'livro razao'. O defeito só apareceu porque um book passou a ter razão E aging
// no mesmo lote — com um dos dois faltando, a ordem errada nunca é exercitada.
test('nome com duas palavras-chave resolve pela regra MAIS ESPECÍFICA', () => {
  const casos = [
    ['17_Livro_Razao_Fornecedores_Canastra_Industria_12M25.pdf', 'RAZAO'],
    ['Razao Analitico Clientes 2025.pdf', 'RAZAO'],
    // e o aging continua sendo aging — a correção não pode roubar o caso dele
    ['23_Aging_de_Contas_a_Pagar_Canastra_Industria_2025.pdf', 'AGING_AP'],
    ['Fornecedores em aberto 12M25.pdf', 'AGING_AP'],
    ['22_Aging_de_Contas_a_Receber_Canastra_Industria_2025.pdf', 'AGING_AR'],
  ];
  for (const [nome, tipo] of casos) {
    assert.equal(classifyByFilename(nome).tipo_taxonomia, tipo, `tipo de ${nome}`);
  }
});

// --- Os nomes do book-canastra e o que eles CUSTAM ---------------------------
//
// Metade dos nomes está na notação de Arquitetura do Sistema/2 Especificação/f0/03 e metade chega como o cliente manda.
// Este teste trava a fronteira: quem resolve tipo E período forte fica em 0,90 e
// paga UMA chamada; quem traz ano solto fica em 0,65 e paga DUAS (classificação
// por conteúdo + extração). É a diferença que faz o lote caber ou não no teto —
// ver `N8N/medir-custo-book.mjs` e docs/CUSTO_OPENAI.md.
test('a notação do nome decide se o documento paga o PDF uma ou duas vezes', () => {
  const umaChamada = [
    '01_Balanco_Patrimonial_Canastra_Industria_2025x2024x2023.pdf',
    '03_DFC_Canastra_Industria_12M25.pdf',
    '04_DMPL_Canastra_Industria_2023_a_2025.pdf',
    '18_Faturamento_36_meses_Canastra_Industria_2023_a_2025.pdf',
    '35_Demonstracoes_Contabeis_Canastra_Industria_2024x2023.pdf',
  ];
  const duasChamadas = [
    '13_Balanco_COMBINADO_Grupo_Canastra_2025.pdf', // ano solto: sinal fraco
    '20_Mapa_de_Divida_Canastra_Industria_2025.pdf',
    '30_Certidoes_Negativas_Grupo_Canastra.pdf', // sem período nenhum
    'Doc1.pdf', // sem tipo nenhum
    'digitalizado_20260115_0003.pdf',
    'ANEXO IV - planilha final REV3.pdf',
  ];
  for (const nome of umaChamada) {
    const r = classifyByFilename(nome);
    assert.equal(r.precisa_fallback_ia, false, `${nome} deveria dispensar a IA (conf ${r.confianca})`);
    assert.ok(r.confianca >= 0.7, `${nome}: confiança ${r.confianca}`);
  }
  for (const nome of duasChamadas) {
    const r = classifyByFilename(nome);
    assert.equal(r.precisa_fallback_ia, true, `${nome} deveria cair na IA (conf ${r.confianca})`);
  }
});

// O nome de scanner não pode inventar período: "20260115" não é o ano de 2026, e
// "0003" não é 2003. Período-lixo fragmenta a tabela `periodo` e impede a
// reconciliação de casar os documentos do mesmo exercício.
test('nome de scanner e de anexo de e-mail não produzem período inventado', () => {
  for (const nome of ['digitalizado_20260115_0003.pdf', 'ANEXO IV - planilha final REV3.pdf', 'Doc1.pdf']) {
    const r = classifyByFilename(nome);
    assert.equal(r.periodo, null, `${nome} não pode ter período: ${JSON.stringify(r.periodo)}`);
    assert.equal(r.tipo_taxonomia, null, `${nome} não pode ter tipo`);
  }
});

test('o limiar do fallback vem do DIAL, e mexer no dial move a decisão', () => {
  // A `0127` tirou o número fixo do lado do Postgres (`fn_dial_permite_auto`),
  // e o cabeçalho dela mesma denunciou a metade que sobrou: *"o 0,70 mora em
  // DOIS lugares"* — o default do SQL e o `THRESHOLD_AUTO` daqui. Enquanto o
  // n8n decidia com 0,70 fixo, subir o dial para 0,85 fazia o BANCO abrir
  // `classificacao_pendente` para todo documento entre 0,70 e 0,85 que o n8n
  // nunca mandou a IA ler — o dial virava um botão que piora o serviço.
  //
  // MEDIDO, com o limiar voltando a ser constante (`confianca < THRESHOLD_AUTO`):
  // os três primeiros asserts abaixo reprovam, porque a decisão para de
  // responder ao dial. Os demais testes do arquivo continuam passando, que é o
  // que torna esta divergência invisível sem este bloco.

  // conf = 0,75 (tipo 0,6 + período fraco 0,05 + assinado 0,1).
  const nome = 'Balanco_Patrimonial_2025_assinado.pdf';
  assert.equal(classifyByFilename(nome).confianca, 0.75);

  // Dial FROUXO (a queda): 0,75 passa, a IA não é chamada.
  assert.equal(classifyByFilename(nome, 0.70).precisa_fallback_ia, false);
  // Dial APERTADO: a mesma confiança passa a exigir a leitura por conteúdo.
  assert.equal(classifyByFilename(nome, 0.85).precisa_fallback_ia, true);
  // E até a classificação forte (conf 0,9) cede a um dial de 0,95.
  assert.equal(classifyByFilename('Balanco_12M25.pdf', 0.95).precisa_fallback_ia, true);

  // A DECISÃO DECLARA CONTRA O QUE FOI TOMADA. Sem isto, "não precisou de
  // fallback" é indistinguível de "o limiar estava frouxo" — e a pendência que
  // o banco abre do outro lado cita o limiar DELE.
  assert.equal(classifyByFilename(nome, 0.85).limiar_aplicado, 0.85);

  // A QUEDA COBRE O BANCO SEM A LINHA DO DIAL, e nunca cai em zero: limiar zero
  // faria TODO documento passar sem a IA ler nenhum, que é a falha silenciosa
  // mais cara possível aqui. Todo valor inválido cai em 0,70.
  for (const invalido of [undefined, null, 0, -1, 1.5, NaN, '', 'x']) {
    assert.equal(classifyByFilename(nome, invalido).limiar_aplicado, 0.70,
      `limiar inválido ${JSON.stringify(invalido)} tinha de cair na queda 0,70`);
  }
});

// Krauspenhar real: os dois nomes abaixo cobrem jan-ago/2026 (8 meses). O nome NÃO
// dava período e a IA respondeu "anual 2026" para a DRE.
test('YTD no nome: "janaago26" vira 8M26 (multi), nunca anual — nomes reais do Krauspenhar', () => {
  for (const nome of ['DRE_janaago26.pdf', 'balancete_janaago26.pdf', 'DRE Janeiro a Agosto de 2026.pdf', 'DRE jan-ago 2026.pdf']) {
    const r = classifyByFilename(nome);
    assert.deepEqual([r.periodo?.tipo, r.periodo?.referencia], ['multi', '8M26'], nome);
  }
});

test('YTD no nome: é sinal fraco (a classificação por conteúdo continua rodando) e só vale para faixa que começa em janeiro', () => {
  assert.equal(classifyByFilename('DRE_janaago26.pdf').precisa_fallback_ia, true);
  assert.equal(classifyByFilename('DRE_janaago26.pdf').confianca, 0.65);
  assert.equal(classifyByFilename('DRE mar a ago 2026.pdf').periodo?.referencia, '2026', 'outra faixa não ganha referência ambígua');
  assert.equal(classifyByFilename('DRE_jan a dez 2025.pdf').periodo?.referencia, '2025', 'jan-dez é o ano inteiro');
});
