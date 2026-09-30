/**
 * Verificação das premissas sugeridas a partir do realizado
 * (roda com `./node_modules/.bin/tsx scripts/verificar-premissas-do-realizado.mts`).
 *
 * O QUE ESTA SUÍTE PROTEGE. A tela de Modelagem passou a sugerir oito premissas
 * lidas do próprio balanço e da própria DRE do caso. O analista aceita com um
 * clique, e a partir daí aquele número dirige a projeção inteira — receita
 * projetada, saldo de giro, caixa, necessidade de recursos. Um erro aqui não tem
 * sintoma: ele produz um modelo que parece calibrado pelo histórico e não é.
 *
 * Os invariantes, em ordem de quanto custa perdê-los:
 *
 *  1. ZERO NÃO É RESPOSTA. Sem a conta que serve de numerador, ou sem a base que
 *     serve de denominador, a sugestão NÃO sai — sai o motivo. Zero dias de
 *     recebimento não é "não sei": é a afirmação de que a empresa vende à vista.
 *  2. A BASE DE CADA RAZÃO É A QUE O MODELO APLICA. Fornecedor gira contra
 *     CUSTOS; cliente e estoque giram contra RECEITA LÍQUIDA. Medir num
 *     denominador e aplicar noutro é o defeito que o próprio modelo denuncia no
 *     Modelo Base, e ele infla o passivo projetado em ~1,27×. Se este assert cair,
 *     o dia sugerido deixa de reproduzir o saldo de onde saiu.
 *  3. SUBTOTAL NÃO SOMA. "Total do Ativo Circulante" ao lado das contas dele
 *     conta o circulante duas vezes, e a razão sai pela metade do que deveria.
 *  4. MAGNITUDE, NÃO SINAL. O documento publica despesa ora positiva, ora
 *     negativa. Custo de 300 com sinal negativo é custo de 300.
 *  5. RECEITA LÍQUIDA É BRUTA MENOS DEDUÇÕES, e não a linha impressa: em metade
 *     dos documentos ela não existe, e quando existe é subtotal.
 *  6. NUMERADOR ZERO COM CONTA PRESENTE PASSA. Uma empresa pode de fato fechar o
 *     exercício sem estoque. O que não pode é inventar a base.
 */

import { sugerirDoRealizado, valorParaGravar, type LinhaRealizada } from "../src/lib/premissas-do-realizado.ts";
import { projetarPremissa } from "../src/lib/projetar-premissa.ts";

let falhas = 0;
let passou = 0;

function ok(cond: boolean, nome: string, detalhe?: string) {
  if (cond) {
    passou += 1;
    console.log(`  ok    ${nome}`);
  } else {
    falhas += 1;
    console.error(`  FALHOU: ${nome}${detalhe ? ` — ${detalhe}` : ""}`);
  }
}

function perto(a: number | null, b: number, tol = 0.0001): boolean {
  return a !== null && Math.abs(a - b) <= tol;
}

const conta = (
  secao: string, chave: string, valor: number,
  papel: LinhaRealizada["papel"] = "conta",
): LinhaRealizada => ({
  secao_canonica: secao, chave, rotulo_norm: chave.toLowerCase(), papel,
  valor_ultimo: valor, documentos: null,
});

const achar = (lista: ReturnType<typeof sugerirDoRealizado>, codigo: string) =>
  lista.find((p) => p.codigo === codigo)!;

// -----------------------------------------------------------------------------
// UM CASO COMPLETO, com números redondos escolhidos para a conta ser conferível
// de cabeça por quem ler o assert.
//
//   receita bruta 1.200, deduções 200        → receita líquida 1.000
//   custos 600, SG&A 150, financeiro −50, tributos 40
//   clientes 200, estoques 100, fornecedores 150
//   dívida 400 (CP 100 + LP 300), passivo total 1.000
// -----------------------------------------------------------------------------
const casoCompleto: LinhaRealizada[] = [
  conta("receita_bruta", "Receita bruta de vendas", 1200),
  conta("receita_bruta", "Deduções da receita bruta", 200),
  conta("custos", "Custo dos produtos vendidos", 600),
  conta("despesas_operacionais", "Despesas administrativas", 150),
  conta("resultado_financeiro", "Despesas financeiras", -50),
  conta("impostos_lucro", "IRPJ e CSLL", 40),
  conta("ativo_circulante", "Clientes", 200),
  conta("ativo_circulante", "Estoques", 100),
  conta("ativo_circulante", "Caixa e equivalentes", 80),
  conta("passivo_circulante", "Fornecedores", 150),
  conta("passivo_circulante", "Empréstimos e financiamentos", 100),
  conta("passivo_nao_circulante", "Financiamentos de longo prazo", 300),
  conta("passivo_circulante", "Salários a pagar", 50),
  conta("passivo_nao_circulante", "Provisão para contingências", 400),
];

console.log("1. o caso completo responde as oito, e cada conta bate");
{
  const s = sugerirDoRealizado(casoCompleto);
  ok(s.length === 8, "são oito premissas", `veio ${s.length}`);

  // custos 600 ÷ RL 1000
  ok(perto(achar(s, "CUSTO_VARIAVEL").valor, 0.6), "CUSTO_VARIAVEL = 0,60",
     String(achar(s, "CUSTO_VARIAVEL").valor));
  // SG&A 150 ÷ RL 1000
  ok(perto(achar(s, "SGA_PCT").valor, 0.15), "SGA_PCT = 0,15", String(achar(s, "SGA_PCT").valor));
  // clientes 200 ÷ RL 1000 × 360
  ok(perto(achar(s, "PMR").valor, 72), "PMR = 72 dias", String(achar(s, "PMR").valor));
  // estoques 100 ÷ RL 1000 × 360
  ok(perto(achar(s, "PME").valor, 36), "PME = 36 dias", String(achar(s, "PME").valor));
  // fornecedores 150 ÷ CUSTOS 600 × 360
  ok(perto(achar(s, "PMP").valor, 90), "PMP = 90 dias", String(achar(s, "PMP").valor));
  // tributos 40 ÷ LAIR (1000 − 600 − 150 − 50 = 200)
  ok(perto(achar(s, "ALIQUOTA").valor, 0.2), "ALIQUOTA = 0,20", String(achar(s, "ALIQUOTA").valor));
  // dívida 400 ÷ passivo total 1000
  ok(perto(achar(s, "PARCELA_ONEROSA").valor, 0.4), "PARCELA_ONEROSA = 0,40",
     String(achar(s, "PARCELA_ONEROSA").valor));
  // |financeiro| 50 ÷ dívida 400
  ok(perto(achar(s, "TAXA_DIVIDA").valor, 0.125), "TAXA_DIVIDA = 0,125",
     String(achar(s, "TAXA_DIVIDA").valor));
}

console.log("2. a base de cada giro é a que o modelo aplica");
{
  // Se o PMP fosse medido contra receita líquida (o defeito do Modelo Base), ele
  // daria 54 dias em vez de 90. A diferença é a razão receita/custo, 1,67×.
  const s = sugerirDoRealizado(casoCompleto);
  ok(achar(s, "PMP").conta.includes("custos"), "PMP declara custos como base",
     achar(s, "PMP").conta);
  ok(!perto(achar(s, "PMP").valor, 54), "e NÃO usa receita líquida, que daria 54");
  ok(achar(s, "PME").conta.includes("receita líquida"),
     "PME declara receita líquida como base, que é a que o Working Capital aplica ao estoque",
     achar(s, "PME").conta);
}

console.log("3. zero não é resposta");
{
  const semClientes = casoCompleto.filter((l) => l.chave !== "Clientes");
  const s = sugerirDoRealizado(semClientes);
  const pmr = achar(s, "PMR");
  ok(pmr.valor === null, "sem conta de clientes, o PMR não sai", String(pmr.valor));
  ok(pmr.porQueNao !== null && pmr.porQueNao.includes("clientes"),
     "e o motivo nomeia a conta que falta", String(pmr.porQueNao));

  const semReceita = casoCompleto.filter((l) => l.secao_canonica !== "receita_bruta");
  const s2 = sugerirDoRealizado(semReceita);
  ok(achar(s2, "CUSTO_VARIAVEL").valor === null && achar(s2, "PMR").valor === null,
     "sem receita, nenhuma razão que a usa como base sai");
  ok(achar(s2, "PMP").valor !== null,
     "mas o PMP sai, porque a base dele é custo e o custo está lá");
}

console.log("4. numerador zero com conta presente PASSA");
{
  const semEstoqueNoFecho = casoCompleto.map((l) =>
    l.chave === "Estoques" ? { ...l, valor_ultimo: 0 } : l);
  const s = sugerirDoRealizado(semEstoqueNoFecho);
  ok(achar(s, "PME").valor === 0,
     "estoque zerado no fechamento é 0 dias, e isso é um fato do documento");
  ok(achar(s, "PME").porQueNao === null, "sem motivo de recusa, porque não houve recusa");
}

console.log("5. subtotal não entra na soma");
{
  const comSubtotal = [
    ...casoCompleto,
    conta("ativo_circulante", "Total do Ativo Circulante", 380, "subtotal"),
    conta("custos", "Total dos custos", 600, "subtotal"),
  ];
  const s = sugerirDoRealizado(comSubtotal);
  ok(perto(achar(s, "CUSTO_VARIAVEL").valor, 0.6),
     "o subtotal de custos não dobra o custo", String(achar(s, "CUSTO_VARIAVEL").valor));
  ok(perto(achar(s, "PMR").valor, 72),
     "e o subtotal do circulante não vira cliente", String(achar(s, "PMR").valor));
}

console.log("6. magnitude, não sinal");
{
  const despesaNegativa = casoCompleto.map((l) =>
    l.secao_canonica === "custos" || l.secao_canonica === "despesas_operacionais"
      ? { ...l, valor_ultimo: -Math.abs(l.valor_ultimo ?? 0) } : l);
  const s = sugerirDoRealizado(despesaNegativa);
  ok(perto(achar(s, "CUSTO_VARIAVEL").valor, 0.6),
     "custo publicado negativo dá a mesma razão", String(achar(s, "CUSTO_VARIAVEL").valor));
  ok(perto(achar(s, "SGA_PCT").valor, 0.15), "SG&A idem", String(achar(s, "SGA_PCT").valor));
}

console.log("7. receita líquida é bruta menos deduções");
{
  const semDeducao = casoCompleto.filter((l) => !/Deduções/.test(l.chave));
  const s = sugerirDoRealizado(semDeducao);
  // Sem a dedução de 200, a base sobe de 1.000 para 1.200 e o custo cai para 0,50.
  ok(perto(achar(s, "CUSTO_VARIAVEL").valor, 0.5),
     "tirar a dedução muda a base, e a razão acompanha",
     String(achar(s, "CUSTO_VARIAVEL").valor));
}

console.log("8. o caso vazio não inventa nada");
{
  const s = sugerirDoRealizado([]);
  ok(s.length === 8, "as oito continuam listadas");
  ok(s.every((p) => p.valor === null && p.porQueNao !== null),
     "e todas as oito dizem por que não saíram");
}

console.log("9. PREJUÍZO ANTES DOS TRIBUTOS não vira alíquota negativa");
{
  // Este é o caso NORMAL do produto, não a exceção: mandato de reestruturação é
  // empresa que perde dinheiro. Custos 900 + SG&A 250 contra receita líquida 1.000
  // dão LAIR = 1.000 − 900 − 250 − 50 = −200, e a empresa ainda recolhe 40 de
  // tributo (adição de indedutível, lucro presumido, IRPJ de exercício anterior).
  //
  // A conta 40 ÷ (−200) = −20% entrava como PREMISSA de alíquota efetiva. Aplicada
  // à projeção, alíquota negativa faz o fisco PAGAR a empresa sobre o lucro
  // futuro — o modelo inventa caixa na direção que lisonjeia o caso.
  const comPrejuizo: LinhaRealizada[] = [
    conta("receita_bruta", "Receita bruta de vendas", 1200),
    conta("receita_bruta", "Deduções da receita bruta", 200),
    conta("custos", "Custo dos produtos vendidos", 900),
    conta("despesas_operacionais", "Despesas administrativas", 250),
    conta("resultado_financeiro", "Despesas financeiras", -50),
    conta("impostos_lucro", "IRPJ e CSLL", 40),
    conta("passivo_circulante", "Empréstimos e financiamentos", 400),
    conta("passivo_circulante", "Salários a pagar", 600),
  ];
  const s = sugerirDoRealizado(comPrejuizo);
  const a = achar(s, "ALIQUOTA");
  ok(a.valor === null, "com LAIR negativo a alíquota NÃO sai", String(a.valor));
  ok(a.porQueNao !== null && a.porQueNao.includes("NEGATIVO"),
     "e o motivo nomeia o prejuízo, em vez de devolver −20%", String(a.porQueNao));
  // O CONTRAPONTO É OBRIGATÓRIO: sem ele, `valor = null` sempre passaria.
  ok(achar(s, "CUSTO_VARIAVEL").valor !== null,
     "as demais premissas do mesmo caso continuam saindo — a recusa é da alíquota, não do caso");
}

console.log("10. RECEITA financeira não infla a taxa da dívida");
{
  // O bloco `resultado_financeiro` tem as DUAS pontas. Somando em magnitude,
  // 50 de despesa + 30 de rendimento davam 80 ÷ 400 = 20% onde a dívida custa
  // 50 ÷ 400 = 12,5%. Sete pontos e meio de custo de dívida, entrando no modelo
  // como premissa a partir de dinheiro que a empresa GANHOU.
  const comRendimento: LinhaRealizada[] = [
    ...casoCompleto,
    conta("resultado_financeiro", "Receitas financeiras sobre aplicações", 30),
  ];
  const s = sugerirDoRealizado(comRendimento);
  const t = achar(s, "TAXA_DIVIDA");
  ok(perto(t.valor, 0.125),
     "a taxa continua 12,5% — só a DESPESA financeira entra no numerador", String(t.valor));
  ok(!perto(t.valor, 0.2), "e NÃO os 20% que a soma em módulo das duas pontas dava");
  ok(t.conta.includes("despesa financeira"),
     "e a conta publicada declara que o numerador é despesa", t.conta);
  // Sem NENHUMA linha de despesa financeira, zero não é resposta: sai o motivo.
  const semDespesa = sugerirDoRealizado([
    ...casoCompleto.filter((l) => l.chave !== "Despesas financeiras"),
    conta("resultado_financeiro", "Receitas financeiras sobre aplicações", 30),
  ]);
  ok(achar(semDespesa, "TAXA_DIVIDA").valor === null,
     "e um caso que só tem RECEITA financeira não devolve taxa nenhuma",
     String(achar(semDespesa, "TAXA_DIVIDA").valor));
}


// ---------------------------------------------------------------------------
// 9. A MÉDIA DOS EXERCÍCIOS — a correção que a rodada do Canastra motivou
// ---------------------------------------------------------------------------
//
// O último exercício de uma empresa em reestruturação é o pior dela. Projetar
// cinco anos a partir dele transforma a crise em regime: a margem deprimida vira
// margem estrutural e o prazo esticado pela inadimplência vira política de
// crédito.
console.log("9. a média dos exercícios");
{
  // O mesmo caso em três anos, com o custo piorando: 50%, 60% e 70% da receita.
  const tresAnos = [2023, 2024, 2025].flatMap((exercicio, i) => {
    const custo = [50, 60, 70][i];
    return [
      { secao_canonica: "receita_bruta", chave: "Receita", rotulo_norm: "receita",
        papel: "conta" as const, exercicio, valor: 100, documentos: null },
      { secao_canonica: "custos", chave: "Matérias-primas", rotulo_norm: "materias-primas",
        papel: "conta" as const, exercicio, valor: -custo, documentos: null },
    ];
  });
  const s9 = sugerirDoRealizado(tresAnos);
  const cv = achar(s9, "CUSTO_VARIAVEL");
  ok(perto(cv.valor, 0.6), "a razão é a MÉDIA dos três exercícios, não a do último", String(cv.valor));
  ok(cv.serie?.length === 3, "a série traz um ponto por exercício, para a média ser conferível",
     String(cv.serie?.length));
  ok(cv.conta.includes("2023, 2024, 2025"),
     "e a conta publicada NOMEIA os exercícios que entraram", cv.conta);

  // UM EXERCÍCIO SÓ NÃO É MÉDIA, e a frase tem de dizer isso — senão o número
  // parece ter uma robustez que ele não tem.
  const umAno = tresAnos.filter((l) => l.exercicio === 2025);
  const cv1 = achar(sugerirDoRealizado(umAno), "CUSTO_VARIAVEL");
  ok(perto(cv1.valor, 0.7), "com um exercício só, o valor é o dele", String(cv1.valor));
  ok(cv1.conta.includes("2025"), "e a conta diz qual exercício foi", cv1.conta);

  // EXERCÍCIO SEM RESPOSTA FICA FORA DA MÉDIA, não entra como zero: 2024 sem
  // receita não pode puxar a razão para baixo com um zero que ninguém afirmou.
  const comBuraco = tresAnos.filter((l) => !(l.exercicio === 2024 && l.secao_canonica === "receita_bruta"));
  const cv2 = achar(sugerirDoRealizado(comBuraco), "CUSTO_VARIAVEL");
  ok(perto(cv2.valor, 0.6), "o exercício sem base fica FORA da média (0,50 e 0,70 = 0,60)",
     String(cv2.valor));
  ok(cv2.serie?.length === 2, "e a série mostra os dois que responderam", String(cv2.serie?.length));
}

// ---------------------------------------------------------------------------
// 10. A PROJEÇÃO AUTOMÁTICA — cada premissa pela forma que cabe a ela
// ---------------------------------------------------------------------------
console.log("10. a projeção automática");
{
  const anos = [2026, 2027, 2028];

  // MACRO → FOCUS. Ano sem expectativa publicada fica FORA, não recebe o valor
  // do vizinho: um ano interpolado seria uma previsão que ninguém fez.
  const ipca = projetarPremissa(
    { codigo: "IPCA", natureza: "macro", formula: "indice_macro", unidade: "%" },
    { anos, focus: { "2026": 4.2, "2027": 3.8 } },
  );
  ok(ipca.origem === "focus", "premissa macro sai do Focus", String(ipca.origem));
  ok(Object.keys(ipca.valores).length === 2, "e o ano sem expectativa fica de fora",
     JSON.stringify(ipca.valores));
  ok(ipca.conta.includes("2028"), "a conta NOMEIA o ano que ficou sem", ipca.conta);
  const semFocus = projetarPremissa(
    { codigo: "IPCA", natureza: "macro", formula: "indice_macro", unidade: "%" }, { anos, focus: {} });
  ok(semFocus.valores && Object.keys(semFocus.valores).length === 0 && !!semFocus.porQueNao,
     "sem Focus nenhum, ela não projeta e diz por quê", String(semFocus.porQueNao));

  // RAZÃO ESTRUTURAL → CONSTANTE NA MÉDIA. Uma empresa não muda de estrutura de
  // custo por decreto; a hipótese honesta é que ela continua operando assim.
  const pmr = projetarPremissa(
    { codigo: "PMR", natureza: "giro", formula: "dias_de_giro", unidade: "dias" },
    { anos, mediaHistorica: { valor: 81, exercicios: [2023, 2024, 2025], conta: "clientes ÷ receita × 360" } },
  );
  ok(pmr.origem === "media_historica", "razão estrutural sai da média histórica", String(pmr.origem));
  ok(anos.every((a) => pmr.valores[String(a)] === 81), "constante em todos os anos projetados",
     JSON.stringify(pmr.valores));
  ok(pmr.conta.includes("3 exercícios"), "e a conta diz quantos exercícios entraram", pmr.conta);

  const umSo = projetarPremissa(
    { codigo: "PMR", natureza: "giro", formula: "dias_de_giro", unidade: "dias" },
    { anos, mediaHistorica: { valor: 81, exercicios: [2025], conta: "clientes ÷ receita × 360" } },
  );
  ok(umSo.conta.includes("não uma média"),
     "com um exercício só, ela se recusa a chamar o número de média", umSo.conta);

  // CRESCIMENTO → INDEXADO, e a hipótese vai declarada. Indexar ao IPCA é
  // afirmar que nada muda em termos reais, e isso é tese, não medição.
  const cresc = projetarPremissa(
    { codigo: "CRESC_NOMINAL", natureza: "receita", formula: "crescimento_composto", unidade: "%" },
    { anos, indiceDoCaso: { codigo: "IPCA", valores: { "2026": 4.2, "2027": 3.8, "2028": 3.5 } } },
  );
  ok(cresc.origem === "indexado", "crescimento é indexado ao índice do mandato", String(cresc.origem));
  ok(cresc.conta.includes("hipótese"), "e a conta DECLARA que é hipótese, não medição", cresc.conta);

  // O QUE NÃO PROJETA SOZINHA. Capex e movimento de dívida são decisão do caso —
  // zero seria uma afirmação sobre o negócio que ninguém fez.
  const capex = projetarPremissa(
    { codigo: "CAPEX_ANO", natureza: "investimento", formula: "valor_por_ano", unidade: "R$/ano" },
    { anos, mediaHistorica: { valor: 4000, exercicios: [2025], conta: "x" } },
  );
  ok(Object.keys(capex.valores).length === 0 && !!capex.porQueNao,
     "valor de decisão do caso NÃO é projetado por conta própria", String(capex.porQueNao));
  ok(capex.porQueNao!.includes("inventar a tese"),
     "e o motivo diz o que estaria sendo inventado", capex.porQueNao!);
}


// 11. O QUE O "USAR" GRAVA. A sugestão em % sai como FRAÇÃO da razão (0,8797),
// mas o catálogo guarda PONTOS PERCENTUAIS — o que a pessoa digita e o que o
// modelo divide por 100. Medido em produção (30/09/2026, caso bb37f726): gravar
// a fração projetou Custo variável de 0,9% e SG&A de 0,2%. O contrato afirmado
// aqui é o COMPORTAMENTO: o que se grava, dividido por 100 como o modelo faz,
// devolve a razão sugerida; e aceitar a sugestão grava o mesmo número que
// digitar o percentual.
console.log("11. o que o \"Usar\" grava");
{
  const custo = { unidade: "%" as const, valor: 0.8797 };
  const gravado = valorParaGravar(custo);
  ok(gravado === 87.97, "sugestão de 87,97% grava 87,97 (pontos percentuais), não 0,8797", String(gravado));
  ok(gravado !== null && Math.abs(gravado / 100 - custo.valor) < 1e-9,
    "o que o modelo aplica (gravado ÷ 100) é a razão sugerida", String(gravado));
  ok(valorParaGravar({ unidade: "%", valor: 0.34 }) === 34,
    "aceitar 34% grava o MESMO que digitar 34");
  ok(valorParaGravar({ unidade: "dias", valor: 176.4 }) === 176.4, "premissa em dias grava os dias, sem conversão");
  ok(valorParaGravar({ unidade: "%", valor: null }) === null, "sugestão sem valor não grava zero");
}

console.log(`\n${passou} asserts passaram, ${falhas} falharam`);
if (falhas > 0) process.exit(1);
console.log("PREMISSAS DO REALIZADO OK — zero não é resposta, a base é a do modelo, subtotal não soma");
console.log("MÉDIA E PROJEÇÃO OK — a razão sai de todos os exercícios, e cada premissa projeta pela forma que cabe a ela");
