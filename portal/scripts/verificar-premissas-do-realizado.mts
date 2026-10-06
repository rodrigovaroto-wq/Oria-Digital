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

import { sugerirDoRealizado, valorParaGravar } from "../src/lib/premissas-do-realizado.ts";
import { projetarPremissa } from "../src/lib/projetar-premissa.ts";
import {
  agregadosDoRealizado, type EntradaModeloInstitucional, type LinhaModelo,
} from "../src/lib/modelo-institucional.ts";
import { entradaDoRealizado } from "../src/lib/leitura-do-caso.ts";
import type { DocumentoParaExport } from "../src/lib/export.ts";
import type { CampoExtraido } from "../src/lib/types.ts";

/** Uma conta do caso num exercício — a forma em que estes asserts foram escritos. */
interface LinhaRealizada {
  secao_canonica: string | null;
  chave: string;
  rotulo_norm: string;
  papel: "conta" | "subtotal" | "derivado" | "serie_mensal";
  exercicio?: number;
  valor?: number;
  valor_ultimo?: number;
  documentos: string[] | null;
}

/**
 * O CAMINHO ÚNICO. As sugestões saem de `agregadosDoRealizado` (as somas do modelo), e este
 * atalho só monta a entrada do modelo a partir de contas soltas — sem subtotais por ordem, que
 * o caso 12 abaixo exercita com campos e documentos de verdade. Linha sem exercício cai em 2025.
 */
function sugerir(linhas: LinhaRealizada[]) {
  const porLinha = new Map<string, LinhaModelo>();
  for (const l of linhas) {
    const k = `${l.secao_canonica}|${l.rotulo_norm}`;
    const lm = porLinha.get(k) ?? {
      secao_canonica: l.secao_canonica, chave: l.chave, rotulo_norm: l.rotulo_norm,
      papel: l.papel, unidade: null, moeda: null, documentos: l.documentos, valores: {},
    };
    lm.valores[String(l.exercicio ?? 2025)] = l.valor ?? l.valor_ultimo ?? 0;
    porLinha.set(k, lm);
  }
  const ent: EntradaModeloInstitucional = {
    caso: { nome: "t", produto: "t" }, agora: new Date(0), entidade: "T", setor: null,
    anosHistoricos: [...new Set(linhas.map((l) => l.exercicio ?? 2025))].sort((a, b) => a - b),
    anosProjetados: [], stressPct: 0, caixaMinimo: 0, aliquotaTributos: 0,
    linhas: [...porLinha.values()], premissas: [], vinculos: [], macro: [], unidade: "R$",
  };
  return sugerirDoRealizado(agregadosDoRealizado(ent));
}

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
  const s = sugerir(casoCompleto);
  ok(s.length === 8, "são oito premissas", `veio ${s.length}`);

  // custos 600 ÷ RL 1000
  ok(perto(achar(s, "CUSTO_VARIAVEL").valor, 0.6), "CUSTO_VARIAVEL = 0,60",
     String(achar(s, "CUSTO_VARIAVEL").valor));
  // SG&A 150 ÷ RL 1000
  ok(perto(achar(s, "SGA_PCT").valor, 0.15), "SGA_PCT = 0,15", String(achar(s, "SGA_PCT").valor));
  // clientes 200 ÷ RL 1000 × 360
  ok(perto(achar(s, "PMR").valor, 72), "PMR = 72 dias", String(achar(s, "PMR").valor));
  // estoques 100 ÷ CUSTOS 600 × 360 = 60 (contra a receita líquida seria 36)
  ok(perto(achar(s, "PME").valor, 60), "PME = 60 dias", String(achar(s, "PME").valor));
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
  const s = sugerir(casoCompleto);
  ok(achar(s, "PMP").conta.includes("custos"), "PMP declara custos como base",
     achar(s, "PMP").conta);
  ok(!perto(achar(s, "PMP").valor, 54), "e NÃO usa receita líquida, que daria 54");
  ok(achar(s, "PME").conta.includes("custos") && !achar(s, "PME").conta.includes("receita"),
     "PME declara custos como base (decisão do dono, 05/10/2026), a que o Working Capital aplica ao estoque",
     achar(s, "PME").conta);
  ok(!perto(achar(s, "PME").valor, 36), "e NÃO usa receita líquida, que daria 36");
  // COMPORTAMENTO: o dia sugerido reproduz o saldo de onde saiu quando aplicado como o modelo
  // aplica (dias/360 × CUSTOS). Estoques 100, custos 600.
  ok(perto(achar(s, "PME").valor! / 360 * 600, 100),
     "PME/360 × custos devolve o saldo de estoque realizado (100)");
}

console.log("3. zero não é resposta");
{
  const semClientes = casoCompleto.filter((l) => l.chave !== "Clientes");
  const s = sugerir(semClientes);
  const pmr = achar(s, "PMR");
  ok(pmr.valor === null, "sem conta de clientes, o PMR não sai", String(pmr.valor));
  ok(pmr.porQueNao !== null && pmr.porQueNao.includes("clientes"),
     "e o motivo nomeia a conta que falta", String(pmr.porQueNao));

  const semReceita = casoCompleto.filter((l) => l.secao_canonica !== "receita_bruta");
  const s2 = sugerir(semReceita);
  ok(achar(s2, "CUSTO_VARIAVEL").valor === null && achar(s2, "PMR").valor === null,
     "sem receita, nenhuma razão que a usa como base sai");
  ok(achar(s2, "PMP").valor !== null,
     "mas o PMP sai, porque a base dele é custo e o custo está lá");
}

console.log("4. numerador zero com conta presente PASSA");
{
  const semEstoqueNoFecho = casoCompleto.map((l) =>
    l.chave === "Estoques" ? { ...l, valor_ultimo: 0 } : l);
  const s = sugerir(semEstoqueNoFecho);
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
  const s = sugerir(comSubtotal);
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
  const s = sugerir(despesaNegativa);
  ok(perto(achar(s, "CUSTO_VARIAVEL").valor, 0.6),
     "custo publicado negativo dá a mesma razão", String(achar(s, "CUSTO_VARIAVEL").valor));
  ok(perto(achar(s, "SGA_PCT").valor, 0.15), "SG&A idem", String(achar(s, "SGA_PCT").valor));
}

console.log("7. receita líquida é bruta menos deduções");
{
  const semDeducao = casoCompleto.filter((l) => !/Deduções/.test(l.chave));
  const s = sugerir(semDeducao);
  // Sem a dedução de 200, a base sobe de 1.000 para 1.200 e o custo cai para 0,50.
  ok(perto(achar(s, "CUSTO_VARIAVEL").valor, 0.5),
     "tirar a dedução muda a base, e a razão acompanha",
     String(achar(s, "CUSTO_VARIAVEL").valor));
}

console.log("8. o caso vazio não inventa nada");
{
  const s = sugerir([]);
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
  const s = sugerir(comPrejuizo);
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
  const s = sugerir(comRendimento);
  const t = achar(s, "TAXA_DIVIDA");
  ok(perto(t.valor, 0.125),
     "a taxa continua 12,5% — só a DESPESA financeira entra no numerador", String(t.valor));
  ok(!perto(t.valor, 0.2), "e NÃO os 20% que a soma em módulo das duas pontas dava");
  ok(t.conta.includes("despesa financeira"),
     "e a conta publicada declara que o numerador é despesa", t.conta);
  // Sem NENHUMA linha de despesa financeira, zero não é resposta: sai o motivo.
  const semDespesa = sugerir([
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
  const s9 = sugerir(tresAnos);
  const cv = achar(s9, "CUSTO_VARIAVEL");
  ok(perto(cv.valor, 0.6), "a razão é a MÉDIA dos três exercícios, não a do último", String(cv.valor));
  ok(cv.serie?.length === 3, "a série traz um ponto por exercício, para a média ser conferível",
     String(cv.serie?.length));
  ok(cv.conta.includes("2023, 2024, 2025"),
     "e a conta publicada NOMEIA os exercícios que entraram", cv.conta);

  // UM EXERCÍCIO SÓ NÃO É MÉDIA, e a frase tem de dizer isso — senão o número
  // parece ter uma robustez que ele não tem.
  const umAno = tresAnos.filter((l) => l.exercicio === 2025);
  const cv1 = achar(sugerir(umAno), "CUSTO_VARIAVEL");
  ok(perto(cv1.valor, 0.7), "com um exercício só, o valor é o dele", String(cv1.valor));
  ok(cv1.conta.includes("2025"), "e a conta diz qual exercício foi", cv1.conta);

  // EXERCÍCIO SEM RESPOSTA FICA FORA DA MÉDIA, não entra como zero: 2024 sem
  // receita não pode puxar a razão para baixo com um zero que ninguém afirmou.
  const comBuraco = tresAnos.filter((l) => !(l.exercicio === 2024 && l.secao_canonica === "receita_bruta"));
  const cv2 = achar(sugerir(comBuraco), "CUSTO_VARIAVEL");
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
  // Comparado com tolerância (Sonar `typescript:S1244`: igualdade exata de ponto
  // flutuante). O texto exato é conferido logo abaixo, onde o ruído existe de fato.
  ok(gravado !== null && Math.abs(gravado - 87.97) < 1e-9,
    "sugestão de 87,97% grava 87,97 (pontos percentuais), não 0,8797", String(gravado));
  // 0,57 × 100 em ponto flutuante é 56,99999999999999 (medido no Node): é esse o
  // ruído que o arredondamento tira. 0,8797 × 100 sai exato e não serviria de prova.
  const ruidoso = valorParaGravar({ unidade: "%", valor: 0.57 });
  ok(String(ruidoso) === "57", "e grava sem o ruído de ponto flutuante (57, não 56.99999999999999)", String(ruidoso));
  ok(gravado !== null && Math.abs(gravado / 100 - custo.valor) < 1e-9,
    "o que o modelo aplica (gravado ÷ 100) é a razão sugerida", String(gravado));
  ok(valorParaGravar({ unidade: "%", valor: 0.34 }) === 34,
    "aceitar 34% grava o MESMO que digitar 34");
  const dias = valorParaGravar({ unidade: "dias", valor: 176.4 });
  ok(dias !== null && Math.abs(dias - 176.4) < 1e-9, "premissa em dias grava os dias, sem conversão", String(dias));
  ok(valorParaGravar({ unidade: "%", valor: null }) === null, "sugestão sem valor não grava zero");
}

// ---------------------------------------------------------------------------
// 12. A HIERARQUIA DO DOCUMENTO — total do grupo + filhas, em ORDEM impressa
// ---------------------------------------------------------------------------
//
// O DEFEITO (Fw Valtra, produção, 2025): somar as linhas por seção conta o total do grupo e as
// filhas juntos. Deu PMR 120 dias onde o documento dá ~40 e SG&A 34,9% onde dá 17,9%.
//
// O QUE ESTE CASO É E NÃO É (regra 4). A parte do BANCO (`fn_linhas_para_modelagem` e
// `fn_valores_por_ano`) não roda em TypeScript: aqui ela é EMULADA a partir dos campos — uma linha
// por (seção, rótulo), um valor por exercício. Os campos, a ordem, o roteamento por aba, a
// detecção de subtotal, a escala e as somas são o código de produção, o mesmo que o export chama.
// O arranjo é o que a demonstração brasileira imprime (grupo com o total, filhas logo abaixo);
// não é o arquivo do Fw Valtra, e não afirma os números dele — esses se conferem contra produção.
//
//   2025: receita bruta 100 (60+40), deduções 10 (ICMS 6 + PIS 4, sem grupo) → receita líquida 90
//         (deduções sem grupo de propósito: se o grupo dobrasse só a receita, as razões mudariam —
//          com tudo dobrando junto, receita e custo se cancelam e o assert passaria sem provar nada)
//         CPV 55 (50+5)                                      → custo variável 55/90
//         despesas com vendas 12 (7+5) + administrativas 6 (4+2) → SG&A 18/90 = 20%
//         contas a receber 30 (25+5)   → PMR 30/90×360 = 120
//         estoques 40 (30+10)          → PME 40/55×360
//         fornecedores 20 (12+8)       → PMP 20/55×360
console.log("12. a hierarquia impressa do documento não dobra a soma");
{
  type Spec = [aba: "DRE" | "BALANCO", secao: string, canonica: string, linhas: Array<[string, number]>];
  const especDe = (k: number): Spec[] => [
    ["DRE", "Receita Bruta", "receita_bruta", [
      ["Receita bruta de vendas", 100 * k], ["Venda de peças", 60 * k], ["Prestação de serviços", 40 * k],
      ["ICMS sobre vendas", 6 * k], ["PIS e COFINS sobre vendas", 4 * k]]],
    ["DRE", "Custos", "custos", [
      ["Custo dos produtos vendidos", 55 * k], ["Custo das mercadorias", 50 * k], ["Fretes sobre compras", 5 * k]]],
    ["DRE", "Despesas Operacionais", "despesas_operacionais", [
      ["Despesas com vendas", 12 * k], ["Comissões", 7 * k], ["Marketing", 5 * k],
      ["Despesas administrativas", 6 * k], ["Salários administrativos", 4 * k], ["Aluguéis", 2 * k]]],
    ["BALANCO", "Ativo Circulante", "ativo_circulante", [
      ["Contas a receber", 30 * k], ["Clientes nacionais", 25 * k], ["Clientes do exterior", 5 * k],
      ["Estoques", 40 * k], ["Mercadorias para revenda", 30 * k], ["Produtos acabados", 10 * k]]],
    ["BALANCO", "Passivo Circulante", "passivo_circulante", [
      ["Fornecedores", 20 * k], ["Fornecedores nacionais", 12 * k], ["Fornecedores do exterior", 8 * k]]],
  ];
  let seqCampo = 0;
  const monta = (comOrdem: boolean) => {
    const documentos: DocumentoParaExport[] = [];
    const campos: CampoExtraido[] = [];
    const linhasDoBanco = new Map<string, Parameters<typeof entradaDoRealizado>[2][number]>();
    const valores: Parameters<typeof entradaDoRealizado>[3]["valores"] = [];
    for (const [ano, k] of [[2024, 0.8], [2025, 1]] as const) {
      for (const aba of ["DRE", "BALANCO"] as const) {
        const V = `v-${aba}-${ano}`;
        documentos.push({
          id: `d-${aba}-${ano}`, tipo_taxonomia: aba, entidade: { razao_social: "Empresa Teste" },
          periodo: { tipo: "anual", referencia: String(ano) },
          documento_versao: [{ id: V, nome_original: `${aba}-${ano}.pdf` }],
        });
        let ordem = 0;
        for (const [a, secao, canonica, linhas] of especDe(k)) {
          if (a !== aba) continue;
          for (const [chave, v] of linhas) {
            campos.push({
              id: `c${seqCampo++}`, documento_versao_id: V, secao, secao_canonica: canonica,
              entidade_coluna: null, periodo_coluna: null, chave, valor_texto: null, valor_num: v,
              unidade: "unidade", confianca: 0.97, origem_pagina: 1, ordem: comOrdem ? ordem++ : null,
              status_aceite: "aceito", aceito_por: "teste", aceito_em: "2026-01-01T00:00:00Z",
            } as CampoExtraido);
            const rotulo = chave.toLowerCase();
            linhasDoBanco.set(`${canonica}|${rotulo}`, {
              secao_canonica: canonica, chave, rotulo_norm: rotulo, papel: "conta",
              unidade: "unidade", moeda: null, documentos: [aba],
            });
            valores.push({
              rotulo_norm: rotulo, secao_canonica: canonica, ano, valor: v, arquivo: null,
              origem_pagina: 1, confianca: 0.97, status_aceite: "aceito", aceito_por: "teste",
            });
          }
        }
      }
    }
    return { documentos, campos, linhasDoBanco: [...linhasDoBanco.values()], valores };
  };
  const agregadosDe = (comOrdem: boolean) => {
    const m = monta(comOrdem);
    return agregadosDoRealizado(entradaDoRealizado("Empresa Teste", 2025, m.linhasDoBanco, m));
  };
  const sugerirDe = (comOrdem: boolean) => sugerirDoRealizado(agregadosDe(comOrdem));

  const s = sugerirDe(true);
  const serie = (cod: string, ano: number) => achar(s, cod).serie?.find((x) => x.exercicio === ano)?.valor ?? null;
  ok(perto(serie("SGA_PCT", 2025), 18 / 90), "SG&A 2025 = 18/90 (20%): o total do grupo não dobra as filhas",
     String(serie("SGA_PCT", 2025)));
  ok(perto(serie("CUSTO_VARIAVEL", 2025), 55 / 90), "custo variável 2025 = 55/90", String(serie("CUSTO_VARIAVEL", 2025)));
  ok(perto(serie("PMR", 2025), 120), "PMR 2025 = 120 dias (30 ÷ 90 × 360), contas a receber sem as filhas",
     String(serie("PMR", 2025)));
  ok(perto(serie("PME", 2025), (40 / 55) * 360), "PME 2025 = 40 ÷ 55 × 360", String(serie("PME", 2025)));
  ok(perto(serie("PMP", 2025), (20 / 55) * 360), "PMP 2025 = 20 ÷ 55 × 360", String(serie("PMP", 2025)));
  ok(achar(s, "PMR").serie?.length === 2, "os dois exercícios entram na série", String(achar(s, "PMR").serie?.length));
  // 2024 é 2025 × 0,8 em TUDO: toda razão é a mesma, então a média também é.
  ok(perto(achar(s, "SGA_PCT").valor, 18 / 90), "e a média dos dois exercícios mantém a razão", String(achar(s, "SGA_PCT").valor));

  // NEGATIVO. Sem a ordem persistida o detector não tem sequência para ler, o total do grupo volta
  // a somar com as filhas e os agregados saem dobrados. É o que prova que a correção vem da ORDEM
  // do documento — e não de outro sinal por acaso. Afirmado sobre o VALOR agregado e não sobre a
  // razão: receita e SG&A dobram juntos e a razão (20%) sairia igual, escondendo o defeito.
  const com2025 = agregadosDe(true).find((a) => a.ano === 2025)!;
  const sem2025 = agregadosDe(false).find((a) => a.ano === 2025)!;
  ok(com2025.sga.valor === 18 && com2025.receitaBruta.valor === 100 && com2025.estoques.valor === 40,
     "com ordem: SG&A 18, receita bruta 100, estoques 40 (o documento)",
     `${com2025.sga.valor} / ${com2025.receitaBruta.valor} / ${com2025.estoques.valor}`);
  ok(sem2025.sga.valor === 36 && sem2025.receitaBruta.valor === 200 && sem2025.estoques.valor === 80,
     "sem ordem persistida o defeito reaparece: tudo dobra (a correção vem da ORDEM)",
     `${sem2025.sga.valor} / ${sem2025.receitaBruta.valor} / ${sem2025.estoques.valor}`);
}

// ---------------------------------------------------------------------------
// 13. A NATUREZA VEM DA SUBSEÇÃO quando o rótulo não diz — formato do balanço real
// ---------------------------------------------------------------------------
//
// O DEFEITO (Fw Valtra, produção): a subseção "ESTOQUE" traz as contas pelos ITENS ("TRATORES
// NOVOS", "IMPLEMENTOS"…), sem a palavra estoque, e o cabeçalho "ESTOQUE" com o total. O
// classificador por rótulo reconhecia só o cabeçalho (que sai como subtotal): estoque 0 em 2023,
// 445.866 em 2024 e 3.840.309 em 2025 onde o balanço diz 12.319.473,90 / 18.801.847,59 /
// 26.420.390,24. O PME esperado contra o CMV real do mesmo caso é ~133 / 212 / 317 dias.
//
// REGRA 4: o arranjo é o FORMATO real (subseção bruta + cabeçalho com total + itens em ordem), não
// o arquivo do cliente; o banco é emulado a partir dos campos, como no caso 12.
console.log("13. a subseção ESTOQUE dá a natureza aos itens, e o PME fecha com o balanço");
{
  const ESTOQUE = { 2023: 12319473.90, 2024: 18801847.59, 2025: 26420390.24 } as const;
  const CMV = { 2023: 33266737.80, 2024: 31864336.87, 2025: 29960764.50 } as const;
  const monta = () => {
    const documentos: DocumentoParaExport[] = [];
    const campos: CampoExtraido[] = [];
    const linhasDoBanco: Parameters<typeof entradaDoRealizado>[2] = [];
    const valores: Parameters<typeof entradaDoRealizado>[3]["valores"] = [];
    let n = 0;
    const adiciona = (aba: string, ano: number, V: string, [ordem, secao, canonica]: [number, string, string],
                      chave: string, v: number) => {
      campos.push({
        id: `n${n++}`, documento_versao_id: V, secao, secao_canonica: canonica, entidade_coluna: null,
        periodo_coluna: null, chave, valor_texto: null, valor_num: v, unidade: "unidade", confianca: 0.97,
        origem_pagina: 1, ordem, status_aceite: "aceito", aceito_por: "teste", aceito_em: "2026-01-01T00:00:00Z",
      } as CampoExtraido);
      const rn = chave.toLowerCase();
      if (!linhasDoBanco.some((l) => l.secao_canonica === canonica && l.rotulo_norm === rn)) {
        linhasDoBanco.push({ secao_canonica: canonica, chave, rotulo_norm: rn, papel: "conta", unidade: "unidade",
          moeda: null, documentos: [aba] });
      }
      valores.push({ rotulo_norm: rn, secao_canonica: canonica, ano, valor: v, arquivo: null, origem_pagina: 1,
        confianca: 0.97, status_aceite: "aceito", aceito_por: "teste" });
    };
    for (const ano of [2023, 2024, 2025] as const) {
      for (const aba of ["DRE", "BALANCO"] as const) {
        const V = `n-${aba}-${ano}`;
        documentos.push({ id: `dn-${aba}-${ano}`, tipo_taxonomia: aba, entidade: { razao_social: "Empresa Teste" },
          periodo: { tipo: "anual", referencia: String(ano) }, documento_versao: [{ id: V, nome_original: `${aba}${ano}.pdf` }] });
      }
      adiciona("DRE", ano, `n-DRE-${ano}`, [0, "Custos", "custos"], "CUSTO DAS MERCADORIAS VENDIDAS", CMV[ano]);
      const itens = [0.6, 0.3, 0.1].map((f) => Math.round(ESTOQUE[ano] * f * 100) / 100);
      itens[2] = Math.round((ESTOQUE[ano] - itens[0] - itens[1]) * 100) / 100;
      // cabeçalho com o total, depois os itens — todos na subseção bruta "ESTOQUE"
      adiciona("BALANCO", ano, `n-BALANCO-${ano}`, [0, "ESTOQUE", "ativo_circulante"], "ESTOQUE", ESTOQUE[ano]);
      ["TRATORES NOVOS", "IMPLEMENTOS", "PECAS DE REPOSICAO"].forEach((nome, i) =>
        adiciona("BALANCO", ano, `n-BALANCO-${ano}`, [i + 1, "ESTOQUE", "ativo_circulante"], nome, itens[i]));
    }
    return { documentos, campos, linhasDoBanco, valores };
  };
  const m = monta();
  const s = sugerirDoRealizado(agregadosDoRealizado(entradaDoRealizado("Empresa Teste", 2025, m.linhasDoBanco, m)));
  const pme = (ano: number) => achar(s, "PME").serie?.find((x) => x.exercicio === ano)?.valor ?? null;
  ok(perto(pme(2023), 133.3, 0.1) && perto(pme(2024), 212.4, 0.1) && perto(pme(2025), 317.4, 0.1),
     "PME 133 / 212 / 317 dias: os itens da subseção ESTOQUE são estoque",
     `${pme(2023)} / ${pme(2024)} / ${pme(2025)}`);
  const ent = entradaDoRealizado("Empresa Teste", 2025, m.linhasDoBanco, m);
  const ag = agregadosDoRealizado(ent).find((a) => a.ano === 2025)!;
  ok(Math.abs(ag.estoques.valor - ESTOQUE[2025]) < 0.01,
     "o estoque agregado de 2025 é o do balanço (cabeçalho fora, itens dentro)", String(ag.estoques.valor));
  // EXCLUSIVIDADE: um item cujo RÓTULO diz outra coisa não é arrastado pela subseção.
  const m2 = monta();
  m2.linhasDoBanco.push({ secao_canonica: "ativo_circulante", chave: "CLIENTES A RECEBER DE TERCEIROS",
    rotulo_norm: "clientes a receber de terceiros", papel: "conta", unidade: "unidade", moeda: null, documentos: ["BALANCO"] });
  m2.valores.push({ rotulo_norm: "clientes a receber de terceiros", secao_canonica: "ativo_circulante", ano: 2025,
    valor: 1000, arquivo: null, origem_pagina: 1, confianca: 1, status_aceite: "aceito", aceito_por: "t" });
  m2.campos.push({ ...m2.campos.at(-1), id: "x-cli", chave: "CLIENTES A RECEBER DE TERCEIROS",
    valor_num: 1000, ordem: 9 } as CampoExtraido);
  const ag2 = agregadosDoRealizado(entradaDoRealizado("Empresa Teste", 2025, m2.linhasDoBanco, m2)).find((a) => a.ano === 2025)!;
  ok(Math.abs(ag2.estoques.valor - ESTOQUE[2025]) < 0.01 && ag2.clientes.valor === 1000,
     "o rótulo manda: 'CLIENTES …' dentro de ESTOQUE é cliente, e não entra no estoque",
     `${ag2.estoques.valor} / ${ag2.clientes.valor}`);
}

console.log("14. dívida imaterial não vira taxa de milhões por cento");
{
  // Fw Valtra, 2023: despesa financeira 331.329 sobre dívida ~0 → sugestão gravável de 8.283.320%.
  const base = (ano: number, divida: number, despesa: number): LinhaRealizada[] => [
    { ...conta("ativo_circulante", "Caixa e bancos", 1_000_000), exercicio: ano },
    { ...conta("passivo_circulante", "Empréstimos e financiamentos", divida), exercicio: ano },
    { ...conta("resultado_financeiro", "Despesas financeiras", despesa), exercicio: ano },
  ];
  const so2023 = achar(sugerir(base(2023, 40, 331329)), "TAXA_DIVIDA");
  ok(so2023.valor === null, "dívida < 1% do ativo: a taxa NÃO sai", String(so2023.valor));
  ok(so2023.porQueNao !== null && so2023.porQueNao.includes("menor que 1% do ativo")
     && so2023.porQueNao.includes("Efeito"), "e o motivo traz a régua e o efeito", String(so2023.porQueNao));
  const dois = achar(sugerir([...base(2023, 40, 331329), ...base(2024, 400_000, 40_000)]), "TAXA_DIVIDA");
  ok(perto(dois.valor, 0.1) && dois.serie?.length === 1,
     "o exercício imaterial fica FORA da média; sobra o de 2024 (10%)", `${dois.valor} / ${dois.serie?.length}`);
  // CONTRAPONTO: sem ativo para servir de régua, não se afirma imaterialidade.
  const semAtivo = achar(sugerir(base(2023, 40, 4).filter((l) => l.secao_canonica !== "ativo_circulante")), "TAXA_DIVIDA");
  ok(semAtivo.valor !== null, "sem ativo como régua a guarda não dispara (ausência de régua não é imaterialidade)");
  // Fw Valtra, 2022: dívida de 1,44% do ativo (acima da régua) e despesa MAIOR que ela — 171%
  // entrava na média e levava a taxa de 18% para 69%.
  const acima = achar(sugerir([...base(2022, 20_000, 35_000), ...base(2024, 400_000, 40_000)]), "TAXA_DIVIDA");
  ok(perto(acima.valor, 0.1) && acima.serie?.length === 1,
     "despesa maior que a dívida (taxa > 100% a.a.) fica FORA da média", `${acima.valor} / ${acima.serie?.length}`);
  const so2022 = achar(sugerir(base(2022, 20_000, 35_000)), "TAXA_DIVIDA");
  ok(so2022.valor === null && (so2022.porQueNao ?? "").includes("maior que a dívida") && (so2022.porQueNao ?? "").includes("Efeito"),
     "e sozinho sai sem valor, com o motivo e o efeito", String(so2022.porQueNao));
  // CONTRAPONTO: 100% exato não é descasamento, é a régua — continua passando.
  ok(achar(sugerir(base(2022, 20_000, 20_000)), "TAXA_DIVIDA").valor === 1, "despesa igual à dívida (100%) ainda sai");
}

console.log(`\n${passou} asserts passaram, ${falhas} falharam`);
if (falhas > 0) process.exit(1);
console.log("PREMISSAS DO REALIZADO OK — zero não é resposta, a base é a do modelo, subtotal não soma");
console.log("MÉDIA E PROJEÇÃO OK — a razão sai de todos os exercícios, e cada premissa projeta pela forma que cabe a ela");
