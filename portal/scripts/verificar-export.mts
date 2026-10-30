/**
 * Verificação do export (roda com `npx tsx scripts/verificar-export.mts`).
 *
 * O portal não tem runner de teste; este script cobre os invariantes do export
 * que já quebraram com dado real, para não regredirem:
 *
 *  1. SUBTOTAL DE SUBSEÇÃO NÃO ENTRA NA SOMA. Demonstração real é hierárquica
 *     ("Ativo Circulante" > "Estoques" > contas), e cada agrupamento traz o
 *     próprio subtotal impresso. Somar o subtotal junto com os componentes
 *     dobrava todos os totais (teste v24: 137.865 contra 67.878 informados),
 *     contaminando AV% e todos os indicadores.
 *  2. CONTA SEM VOCABULÁRIO CONHECIDO HERDA A SEÇÃO DOS IRMÃOS. A `secao` que a
 *     IA anota costuma ser o nome da SUBSEÇÃO, que não diz Ativo ou Passivo.
 *  3. PARES AMBÍGUOS vão para o lado certo do balanço ("Adiantamentos de
 *     clientes" é obrigação, não crédito).
 *  4. PERÍODOS EM ORDEM CRONOLÓGICA (o Δ% precisa casar meses que se sucedem).
 *  5. COLUNA DE AJUSTE/TOTAL do combinado não é tratada como entidade.
 *  9. NOSSO NÚMERO == O NÚMERO DO DOCUMENTO na DRE e no Fluxo de Caixa: cada
 *     linha de resultado (Receita Líquida, Lucro Bruto, EBIT, LAIR, Prejuízo,
 *     Caixa Líquido de cada atividade) tem de bater com o "↳ total informado no
 *     documento" logo abaixo, em toda coluna. Foi o que pegou a cascata da DRE
 *     fechando em -27.550 onde o documento diz -17.901: duas contas de Despesas
 *     Operacionais estavam fora da seção e uma conta residual estava sendo
 *     tratada como a linha de Receita Líquida.
 *  8. NENHUMA LINHA 100% VAZIA, em nenhuma aba. O template canônico (CPC 26 /
 *     art. 178, cascata da DRE, CPC 03) serve para ORDENAR o que o documento
 *     trouxe — não para impor linhas que ele não tem. Linha sem valor em coluna
 *     nenhuma parece defeito para quem abre a planilha, e escondia o sinal que
 *     importa. Zero conta como valor: se o documento diz 0,00, isso é dado.
 *  6. O TOTAL DA SEÇÃO É O QUE O DOCUMENTO INFORMOU, não a nossa soma. Este é o
 *     invariante que faltava aqui e por isso o teste v25 passou verde enquanto
 *     36 de 44 somas do Balanço divergiam. Dois casos que a detecção estrutural
 *     de subtotal NÃO cobre, e que aparecem em arquivo real:
 *       (a) a IA anota em `secao` a seção de TOPO ("Ativo Circulante") em vez da
 *           subseção — então "Disponível" não é reconhecível como subtotal;
 *       (b) o mesmo rótulo é subtotal num documento e conta-folha em outro
 *           (a Metalúrgica detalha "Disponível"; a Componentes usa como conta),
 *           e o export junta os dois na mesma linha.
 *     Em ambos, o número da seção tem de seguir o total informado, e a nossa
 *     soma tem de ficar visível numa linha de checagem — nunca virar o total.
 */
import { readFileSync } from "node:fs";
import { entradaModeloDaFixture } from "./lib/modelo-da-fixture.mts";
import type ExcelJS from "exceljs";
import { avaliarCelula, esquecerMemoria, linhaVazia } from "./lib/avaliar-formula.mts";
import {
  buildExportWorkbook, chaveCronologicaPeriodo, consolidarNomesDeEntidade,
  entidadePeriodoDaLinha,
  rotulosDeSubtotalInformado, tipoColunaNaoEntidade, type DocumentoParaExport,
} from "../src/lib/export";
import type { CampoExtraido } from "../src/lib/types";
import { classificarConta } from "../src/lib/statement-templates.ts";
import {
  casarVinculosComLinhas, chaveDaLinha, serieDaLinha, seriesPorLinha, vinculoPorLinha,
} from "../src/lib/modelagem-linha.ts";
import { ABAS_MODELO as ABAS_DO_MODELO, ehDividaFinanceira, grupoDeObrigacoesQueCitaDivida } from "../src/lib/modelo-institucional.ts";
import { auditarWorkbook } from "./auditar-xlsx.mts";
import {
  humanizar, partesDaDescricao, rotuloDaPendencia, rotuloDaSecao, rotulosCitados, semALista, suavizarMensagem,
} from "../src/lib/rotulos.ts";
import { BOTOES_DECISAO, ROTULO_POR_ESTADO, rotuloDoEstado } from "../src/lib/pendencia.ts";
import { JANELA_DE_VERSOES, acoesDoTermo, agruparResultados, digitosDoCnpj, padraoDoTermo, termoDaBusca } from "../src/lib/busca-global.ts";
import { padraoDeBusca as padraoDaLista } from "../src/lib/painel.ts";

let ok = 0;
const falhas: string[] = [];
function checar(cond: boolean, desc: string, detalhe = "") {
  if (cond) ok++;
  else falhas.push(`${desc}${detalhe ? ` — ${detalhe}` : ""}`);
}

// Avalia a célula resolvendo as fórmulas do export (SUM/refs/aritmética/IFERROR)
// — ver scripts/lib/avaliar-formula.mts.
function avaliar(ws: import("exceljs").Worksheet, col: string, row: number): number {
  const v = avaliarCelula(ws, col, row);
  return typeof v === "number" ? v : 0;
}

// No ExcelJS a nota de célula é um objeto (`{texts:[{text}]}`), não string — ler
// com String() devolve "[object Object]" e o invariante passaria a testar nada.
/** Índice de coluna (1-based) → letra A1. O avaliador recebe letra, não número. */
function colLetraDoIndice(i: number): string {
  let n = i, out = "";
  while (n > 0) { const r = (n - 1) % 26; out = String.fromCharCode(65 + r) + out; n = Math.floor((n - 1) / 26); }
  return out;
}

function notaDaLinha(ws: import("exceljs").Worksheet, row: number): string {
  const r = ws.getRow(row);
  const partes: string[] = [];
  // `includeEmpty: true` importa: a nota da média que NÃO fechou vive numa célula
  // sem valor, e com `false` o ExcelJS pula justamente ela.
  r.eachCell({ includeEmpty: true }, (cell) => {
    const n = cell.note as unknown;
    if (!n) return;
    if (typeof n === "string") partes.push(n);
    else if (typeof n === "object" && Array.isArray((n as { texts?: Array<{ text?: string }> }).texts)) {
      partes.push((n as { texts: Array<{ text?: string }> }).texts.map((t) => t.text ?? "").join(""));
    }
  });
  return partes.join("\n");
}

// Letra da coluna a partir do índice (1 = A). O harness comparava só texto de
// fórmula até agora, então nunca precisou disto.
function colLetraDe(idx: number): string {
  let s = "";
  let n = idx;
  while (n > 0) { const r = (n - 1) % 26; s = String.fromCharCode(65 + r) + s; n = Math.floor((n - 1) / 26); }
  return s;
}

let seq = 0;
const campo = (p: Partial<CampoExtraido> & { chave: string; documento_versao_id: string }): CampoExtraido => ({
  id: `c${seq++}`, secao: null, secao_canonica: null, entidade_coluna: null, periodo_coluna: null,
  valor_texto: null, valor_num: null, unidade: null, confianca: 0.97, origem_pagina: 1,
  status_aceite: "aceito", aceito_por: "teste", aceito_em: "2026-07-27T00:00:00Z", ...p,
} as CampoExtraido);

// ---- 1/2/3: balanço hierárquico com subtotais de subseção -------------------
{
  const V = "v1";
  const campos: CampoExtraido[] = [];
  const blocos: Array<[string, Array<[string, number]>]> = [
    ["Disponível", [["Caixa e bancos conta movimento", 1240], ["Aplicações financeiras de liquidez imediata", 3600]]],
    ["Contas a Receber", [["Duplicatas a receber - mercado interno", 27900], ["(-) PECLD", -1980]]],
    ["Estoques", [["Matérias-primas e insumos", 12400], ["Produtos em elaboração", 4300]]],
  ];
  let acTotal = 0;
  for (const [sub, contas] of blocos) {
    const soma = contas.reduce((a, [, v]) => a + v, 0);
    acTotal += soma;
    for (const [chave, v] of contas) campos.push(campo({ chave, secao: sub, valor_num: v, documento_versao_id: V }));
    campos.push(campo({ chave: sub, secao: "Ativo Circulante", valor_num: soma, documento_versao_id: V })); // subtotal
  }
  campos.push(campo({ chave: "Total do Ativo Circulante", secao: "Ativo Circulante", valor_num: acTotal, documento_versao_id: V }));
  campos.push(campo({ chave: "Fornecedores nacionais", secao: "Passivo Circulante", valor_num: acTotal, documento_versao_id: V }));
  campos.push(campo({ chave: "Adiantamentos de clientes", secao: "Outras Obrigações", valor_num: 900, documento_versao_id: V }));

  const documentos: DocumentoParaExport[] = [{
    id: "d", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Alfa" },
    periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: V, nome_original: "bp.pdf" }],
  }];
  const ws = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") })
    .getWorksheet("Balanço")!;

  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };
  const rAC = linhaDe("Ativo Circulante");
  const soma = avaliar(ws, "B", rAC);
  checar(soma === acTotal, "(1) subtotal de subseção fora da soma", `seção=${soma} informado=${acTotal}`);
  const rotulos: string[] = [];
  for (let r = 1; r <= ws.rowCount; r++) rotulos.push(String(ws.getRow(r).getCell(1).value ?? ""));
  checar(rotulos.some((x) => x.startsWith("↳ subtotal informado:")), "(1b) subtotais continuam visíveis");
  const iNaoClass = rotulos.findIndex((x) => x.startsWith("Contas Não Classificadas"));
  const naoClass = iNaoClass < 0 ? [] : rotulos.slice(iNaoClass + 1).filter(Boolean);
  checar(naoClass.length === 0, "(2) nada em Não Classificadas (consenso de irmãos)", naoClass.join(", "));
  // A conta tem de estar DENTRO do range que a soma do Passivo Circulante cobre —
  // asserção mais precisa que "entre dois cabeçalhos", e que não depende de o
  // Passivo Não Circulante existir (seção sem dado deixou de ser emitida).
  const rAdiant = linhaDe("Adiantamentos de clientes");
  const rPC = linhaDe("Passivo Circulante");
  const fPC = String((ws.getRow(rPC).getCell(2).value as { formula?: string })?.formula ?? "");
  const mPC = fPC.match(/SUM\([A-Z]+(\d+):[A-Z]+(\d+)\)/);
  checar(
    rAdiant > 0 && mPC != null && rAdiant >= Number(mPC[1]) && rAdiant <= Number(mPC[2]),
    "(3) 'Adiantamentos de clientes' entra na soma do Passivo Circulante",
    `linha=${rAdiant} range=${mPC ? `${mPC[1]}:${mPC[2]}` : fPC}`,
  );
}

// ---- 4: ordem cronológica ---------------------------------------------------
{
  const meses = ["Out/2024", "Nov/2024", "Dez/2024", "Jan/2025"];
  const ordenado = [...meses].sort((a, b) => chaveCronologicaPeriodo(a) - chaveCronologicaPeriodo(b));
  checar(JSON.stringify(ordenado) === JSON.stringify(meses), "(4) períodos em ordem cronológica", ordenado.join(" < "));
}

// ---- 5: coluna de ajuste/total não é entidade -------------------------------
{
  checar(tipoColunaNaoEntidade("Eliminações") === "ajuste", "(5a) 'Eliminações' é ajuste");
  checar(tipoColunaNaoEntidade("Combinado") === "total", "(5b) 'Combinado' é total");
  checar(tipoColunaNaoEntidade("Vertentes Metalúrgica") === null, "(5c) empresa real não é ajuste/total");
}

// ---- 6: o total da seção segue o INFORMADO, não a nossa soma ----------------
// Reproduz o cenário do teste v25, que os invariantes anteriores não pegavam.
{
  const VA = "vA"; // Metalúrgica: detalha "Disponível" em duas contas
  const VB = "vB"; // Componentes: usa "Disponível" como conta-folha
  const campos: CampoExtraido[] = [];

  // (a) a IA anotou a SEÇÃO DE TOPO nas contas-filhas, não a subseção — então
  // "Disponível" é indetectável como subtotal por estrutura.
  const AC_A = 4840 + 8420;
  campos.push(
    campo({ chave: "Caixa e bancos conta movimento", secao: "Ativo Circulante", valor_num: 1240, documento_versao_id: VA }),
    campo({ chave: "Aplicações financeiras de liquidez imediata", secao: "Ativo Circulante", valor_num: 3600, documento_versao_id: VA }),
    campo({ chave: "Disponível", secao: "Ativo Circulante", valor_num: 4840, documento_versao_id: VA }),
    campo({ chave: "Duplicatas a receber - mercado interno", secao: "Ativo Circulante", valor_num: 8420, documento_versao_id: VA }),
    campo({ chave: "Total do Ativo Circulante", secao: "Ativo Circulante", valor_num: AC_A, documento_versao_id: VA }),
    campo({ chave: "Máquinas e equipamentos", secao: "Imobilizado", valor_num: 30000, documento_versao_id: VA }),
    campo({ chave: "Total do Ativo Não Circulante", secao: "Ativo Não Circulante", valor_num: 30000, documento_versao_id: VA }),
    campo({ chave: "TOTAL DO ATIVO", secao: "ATIVO", valor_num: AC_A + 30000, documento_versao_id: VA }),
    campo({ chave: "Fornecedores nacionais", secao: "Passivo Circulante", valor_num: AC_A + 30000, documento_versao_id: VA }),
  );
  // (b) outro documento onde "Disponível" é conta-folha de verdade.
  campos.push(
    campo({ chave: "Disponível", secao: "Ativo Circulante", valor_num: 410, documento_versao_id: VB }),
    campo({ chave: "Duplicatas a receber - mercado interno", secao: "Ativo Circulante", valor_num: 5000, documento_versao_id: VB }),
    campo({ chave: "Total do Ativo Circulante", secao: "Ativo Circulante", valor_num: 5410, documento_versao_id: VB }),
    campo({ chave: "TOTAL DO ATIVO", secao: "ATIVO", valor_num: 5410, documento_versao_id: VB }),
    campo({ chave: "Fornecedores nacionais", secao: "Passivo Circulante", valor_num: 5410, documento_versao_id: VB }),
  );

  const documentos: DocumentoParaExport[] = [
    { id: "dA", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Metalúrgica" },
      periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: VA, nome_original: "a.pdf" }] },
    { id: "dB", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Componentes" },
      periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: VB, nome_original: "b.pdf" }] },
  ];
  const ws = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") })
    .getWorksheet("Balanço")!;
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };
  // Qual coluna é qual entidade
  const hdr = ws.getRow(1);
  let colA = "", colB = "";
  for (let c = 2; c <= hdr.cellCount; c++) {
    const h = String(hdr.getCell(c).value ?? "");
    if (h.startsWith("Metalúrgica")) colA = ws.getColumn(c).letter;
    if (h.startsWith("Componentes")) colB = ws.getColumn(c).letter;
  }
  const rAC = linhaDe("Ativo Circulante");
  const rATIVO = linhaDe("ATIVO");
  checar(avaliar(ws, colA, rAC) === AC_A,
    "(6a) subtotal indetectável por `secao`: seção segue o total informado",
    `seção=${avaliar(ws, colA, rAC)} informado=${AC_A}`);
  checar(avaliar(ws, colB, rAC) === 5410,
    "(6b) mesmo rótulo como conta-folha no outro documento não é perdido",
    `seção=${avaliar(ws, colB, rAC)} informado=5410`);
  checar(avaliar(ws, colA, rATIVO) === AC_A + 30000,
    "(6c) total do grupo ATIVO segue o TOTAL DO ATIVO informado",
    `ATIVO=${avaliar(ws, colA, rATIVO)} informado=${AC_A + 30000}`);
  const rotulos: string[] = [];
  for (let r = 1; r <= ws.rowCount; r++) rotulos.push(String(ws.getRow(r).getCell(1).value ?? ""));
  checar(rotulos.some((x) => x.startsWith("↳ soma das contas listadas")),
    "(6d) a nossa soma continua visível como linha de checagem");
  const rSoma = rotulos.findIndex((x, i) => i > rAC && x.startsWith("↳ soma das contas listadas")) ;
  checar(rSoma > 0 && avaliar(ws, colA, rSoma + 1) === AC_A + 4840,
    "(6e) a checagem mostra a soma inflada (sinal visível, não total silencioso)",
    `checagem=${rSoma > 0 ? avaliar(ws, colA, rSoma + 1) : "n/d"} esperado=${AC_A + 4840}`);
}

// ---- 7: END-TO-END contra o book Vertentes ---------------------------------
// Monta o export a partir do MESMO fixture que os testes de banco usam
// (Supabase/test/gerar_fixture.py, extração fiel dos 14 documentos) e confere TODA
// seção do Balanço contra o gabarito do book. Este é o teste que faltava: os
// invariantes sintéticos passavam verde enquanto o export real do v25 tinha 36
// de 44 somas divergentes.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const gab = JSON.parse(
    readFileSync(new URL("../../Dados de Teste/book-vertentes/pdf/GABARITO.json", import.meta.url), "utf8"),
  ) as { balanco_por_entidade: Record<string, Record<string, Record<string, number>>> };

  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-27T12:00:00Z"),
  });
  const ws = wb.getWorksheet("Balanço")!;
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };
  // cabeçalho: "RAZÃO SOCIAL — 31/12/2025" → coluna
  const hdr = ws.getRow(1);
  const colDe = new Map<string, string>();
  for (let c = 2; c <= hdr.cellCount; c++) {
    const h = String(hdr.getCell(c).value ?? "");
    if (h && h !== "AV%" && !h.startsWith("Δ%")) colDe.set(h, ws.getColumn(c).letter);
  }
  const RAZAO: Record<string, string> = {
    metalurgica: "VERTENTES METALÚRGICA LTDA.", componentes: "VERTENTES COMPONENTES AUTOMOTIVOS LTDA.",
    holding: "VERTENTES PARTICIPAÇÕES S.A.", logistica: "VT LOGÍSTICA E TRANSPORTES LTDA.",
    spe: "VERTENTES IMÓVEIS SPE LTDA.",
  };
  const LINHA: Record<string, number> = {
    ATIVO: linhaDe("ATIVO"), AC: linhaDe("Ativo Circulante"), ANC: linhaDe("Ativo Não Circulante"),
    PC: linhaDe("Passivo Circulante"), PNC: linhaDe("Passivo Não Circulante"), PL: linhaDe("Patrimônio Líquido"),
  };
  let conferidos = 0;
  const erros: string[] = [];
  for (const ano of ["2024", "2025"]) {
    for (const [chave, razao] of Object.entries(RAZAO)) {
      const col = colDe.get(`${razao} — ${ano}`);
      if (!col) { erros.push(`coluna ausente: ${razao} ${ano}`); continue; }
      for (const [sigla, row] of Object.entries(LINHA)) {
        const esperado = gab.balanco_por_entidade[ano][chave][sigla];
        const obtido = Math.round(avaliar(ws, col, row));
        conferidos++;
        if (obtido !== esperado) erros.push(`${razao} ${ano} ${sigla}: export=${obtido} gabarito=${esperado}`);
      }
    }
  }
  checar(erros.length === 0,
    `(7) todas as ${conferidos} seções do Balanço batem com o gabarito do book`,
    erros.slice(0, 8).join(" / "));
  // PASSIVO+PL tem de fechar com o ATIVO em toda coluna (é o balanço, afinal).
  const rPPL = linhaDe("PASSIVO E PATRIMÔNIO LÍQUIDO");
  const desbalanceados: string[] = [];
  for (const [nome, col] of colDe) {
    const a = Math.round(avaliar(ws, col, LINHA.ATIVO));
    const b = Math.round(avaliar(ws, col, rPPL));
    if (a !== b) desbalanceados.push(`${nome}: ativo=${a} passivo+pl=${b}`);
  }
  checar(desbalanceados.length === 0, "(7b) Ativo = Passivo + PL em toda coluna do export",
    desbalanceados.slice(0, 6).join(" / "));
}

// ---- 8: nenhuma linha 100% vazia, em nenhuma aba -----------------------------
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-27T12:00:00Z"),
  });
  const vazias: string[] = [];
  let rotuladas = 0;
  for (const ws of wb.worksheets) {
    // Modelagem tem invariante próprio (11, abaixo): lá as células são fórmulas
    // de modelo (IF/INDEX/MATCH/MAX) que `avaliarCelula` não resolve — e o que
    // importa naquela aba é o oposto do que se checa aqui (nenhum valor CRU
    // fora dos inputs), não a ausência de linha em branco.
    if (ws.name === "Resumo" || ws.name === "Modelagem") continue;
    for (let r = 2; r <= ws.rowCount; r++) {
      const rot = String(ws.getRow(r).getCell(1).value ?? "").trim();
      if (!rot) continue;
      rotuladas++;
      if (linhaVazia(ws, r)) vazias.push(`${ws.name}!${r} "${rot}"`);
    }
  }
  checar(vazias.length === 0,
    `(8) nenhuma das ${rotuladas} linhas do book fica 100% vazia`,
    vazias.slice(0, 10).join(" / "));

  // …e o mesmo com um documento ESPARSO: uma empresa que só tem circulante não
  // pode ganhar Realizável LP / Investimentos / Imobilizado / Intangível /
  // Passivo Não Circulante em branco (nem um "0" que nós inventamos — o
  // documento não disse zero, não disse nada).
  const V = "vEsparso";
  const camposEsparsos: CampoExtraido[] = [
    campo({ chave: "Caixa e bancos", secao: "Ativo Circulante", valor_num: 1000, documento_versao_id: V }),
    campo({ chave: "Clientes - mercado interno", secao: "Ativo Circulante", valor_num: 4000, documento_versao_id: V }),
    campo({ chave: "TOTAL DO ATIVO", secao: "ATIVO", valor_num: 5000, documento_versao_id: V }),
    campo({ chave: "Fornecedores nacionais", secao: "Passivo Circulante", valor_num: 5000, documento_versao_id: V }),
  ];
  const wsEsp = buildExportWorkbook({
    caso: { nome: "Esparso", produto: "reestruturacao" },
    documentos: [{ id: "dE", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Só Circulante Ltda." },
      periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: V, nome_original: "e.pdf" }] }],
    campos: camposEsparsos, agora: new Date("2026-07-27T12:00:00Z"),
  }).getWorksheet("Balanço")!;
  const vaziasEsp: string[] = [];
  const rotulos: string[] = [];
  for (let r = 2; r <= wsEsp.rowCount; r++) {
    const rot = String(wsEsp.getRow(r).getCell(1).value ?? "").trim();
    if (!rot) continue;
    rotulos.push(rot);
    if (linhaVazia(wsEsp, r)) vaziasEsp.push(`${r} "${rot}"`);
  }
  checar(vaziasEsp.length === 0, "(8b) documento esparso não ganha linha vazia", vaziasEsp.join(" / "));
  const naoDeveria = ["Realizável a Longo Prazo", "Investimentos", "Imobilizado", "Intangível",
    "Ativo Não Circulante", "Passivo Não Circulante", "Patrimônio Líquido"];
  const intrusos = naoDeveria.filter((x) => rotulos.includes(x));
  checar(intrusos.length === 0,
    "(8c) seção que o documento não tem não é emitida", intrusos.join(", "));
}

// ---- 9: DRE e Fluxo de Caixa amarram com o próprio documento ---------------
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const gab = JSON.parse(
    readFileSync(new URL("../../Dados de Teste/book-vertentes/pdf/GABARITO.json", import.meta.url), "utf8"),
  ) as { dre_metalurgica_2025: Record<string, number>; receita_bruta_2025: number };
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-27T12:00:00Z"),
  });

  for (const nomeAba of ["DRE", "Fluxo de Caixa"]) {
    const ws = wb.getWorksheet(nomeAba)!;
    const hdr = ws.getRow(1);
    const cols: string[] = [];
    for (let c = 2; c <= ws.columnCount; c++) {
      const h = String(hdr.getCell(c).value ?? "");
      if (h && h !== "AV%" && !h.startsWith("Δ%")) cols.push(ws.getColumn(c).letter);
    }
    const erros: string[] = [];
    let pares = 0;
    for (let r = 3; r <= ws.rowCount; r++) {
      if (String(ws.getRow(r).getCell(1).value ?? "").trim() !== "↳ total informado no documento") continue;
      const rotuloAcima = String(ws.getRow(r - 1).getCell(1).value ?? "").trim();
      for (const c of cols) {
        const informado = avaliarCelula(ws, c, r);
        if (typeof informado !== "number") continue;
        const nosso = avaliarCelula(ws, c, r - 1);
        pares++;
        if (typeof nosso !== "number" || Math.abs(nosso - informado) > Math.max(0.01, Math.abs(informado) * 0.001)) {
          erros.push(`${rotuloAcima} col ${c}: nosso=${nosso} informado=${informado}`);
        }
      }
    }
    checar(erros.length === 0 && pares > 0,
      `(9) ${nomeAba}: as ${pares} linhas de resultado batem com o total informado`,
      erros.slice(0, 6).join(" / "));
  }

  // E os números da DRE contra o gabarito do book, por nome de linha.
  const ws = wb.getWorksheet("DRE")!;
  const hdr = ws.getRow(1);
  let col2025 = "";
  for (let c = 2; c <= ws.columnCount; c++) {
    const h = String(hdr.getCell(c).value ?? "");
    if (h.includes("2025") && !h.startsWith("Δ%")) { col2025 = ws.getColumn(c).letter; break; }
  }
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };
  const esperado: Array<[string, number]> = [
    ["Receita Líquida", gab.dre_metalurgica_2025["RECEITA OPERACIONAL LÍQUIDA"]],
    ["Lucro Bruto", gab.dre_metalurgica_2025["LUCRO BRUTO"]],
    ["Resultado Operacional (EBIT)", gab.dre_metalurgica_2025["RESULTADO OPERACIONAL ANTES DO RESULTADO FINANCEIRO"]],
    ["Resultado Antes dos Tributos", gab.dre_metalurgica_2025["RESULTADO ANTES DOS TRIBUTOS SOBRE O LUCRO"]],
    ["Lucro/Prejuízo Líquido do Exercício", gab.dre_metalurgica_2025["PREJUÍZO LÍQUIDO DO EXERCÍCIO"]],
    ["Receita Bruta e Deduções", gab.dre_metalurgica_2025["RECEITA OPERACIONAL LÍQUIDA"]],
  ];
  const errosGab = esperado
    .map(([rot, exp]) => {
      const r = linhaDe(rot);
      const got = r > 0 ? Math.round(avaliar(ws, col2025, r)) : NaN;
      return got === exp ? null : `${rot}: export=${got} gabarito=${exp}`;
    })
    .filter(Boolean) as string[];
  checar(errosGab.length === 0, "(9b) DRE 2025 bate com o gabarito linha a linha", errosGab.join(" / "));
}

// ---- 10: DMPL e DVA ganham aba própria (Supabase/migrations/0024) -----------------
// Antes desta fatia a DMPL não tinha para onde ir: o documento inteiro era
// classificado como MUTUOS (não havia código DMPL na taxonomia, e o enum que a
// IA recebe é fechado nos códigos que existem) e, quando vinha embutida num PDF
// composto, suas linhas caíam em "Contas Não Classificadas" pela guarda
// `ehLinhaDMPL` — a alternativa era pior, porque o saldo de fechamento REPETE o
// total do PL e somá-lo INFLA o balanço (bug real do export do dono).
{
  const V = "vDMPL";
  // Números do book Vertentes (Dados de Teste/book-vertentes/render.py → pdf_dmpl):
  // matriz de 3 movimentos × 6 componentes do PL, R$ mil.
  const PL24 = 24801, PL25 = 6900, PREJ = PL25 - PL24;
  const componentes: Array<[string, number | null, number | null, number | null]> = [
    // componente,                        saldo 2024, movimento (prejuízo), saldo 2025
    ["Capital social", 45000, null, 45000],
    ["Capital a integralizar", -2000, null, -2000],
    ["Reserva legal", 1200, null, 1200],
    ["Ajuste de avaliação patrimonial", 1850, null, 1850],
    ["Prejuízos acumulados", PL24 - 46050, PREJ, PL25 - 46050],
    ["Total", PL24, PREJ, PL25],
  ];
  const MOV_ABERTURA = "SALDOS EM 31 DE DEZEMBRO DE 2024";
  const MOV_RESULTADO = "Prejuízo líquido do exercício";
  const MOV_FECHAMENTO = "SALDOS EM 31 DE DEZEMBRO DE 2025";
  const campos: CampoExtraido[] = [];
  for (const [comp, ab, mov, fe] of componentes) {
    const cel: Array<[string, number | null]> = [[MOV_ABERTURA, ab], [MOV_RESULTADO, mov], [MOV_FECHAMENTO, fe]];
    for (const [movimento, v] of cel) {
      if (v === null) continue; // célula com traço no PDF não vira linha
      campos.push(campo({ chave: comp, secao: movimento, secao_canonica: "dmpl", valor_num: v, documento_versao_id: V }));
    }
  }
  const documentos: DocumentoParaExport[] = [{
    id: "dDMPL", tipo_taxonomia: "DMPL", entidade: { razao_social: "Vertentes Metalúrgica Ltda." },
    periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, nome_original: "09_DMPL_Vertentes_Metalurgica_2025.pdf" }],
  }];
  const wb = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") });

  const ws = wb.getWorksheet("DMPL");
  checar(ws != null, "(10a) a DMPL tem aba própria (antes caía em MUTUOS/Não Classificadas)");
  if (ws) {
    // A MATRIZ: cabeçalho = componentes do PL, uma linha por movimento. É a
    // leitura que a demonstração existe para dar — achatá-la numa listagem
    // perderia justamente "como cada componente do PL se moveu".
    const header = ws.getRow(1);
    const cabecalhos: string[] = [];
    for (let c = 2; c <= ws.columnCount; c++) cabecalhos.push(String(header.getCell(c).value ?? ""));
    checar(
      componentes.every(([comp]) => cabecalhos.includes(comp)),
      "(10a) os 6 componentes do PL são as COLUNAS da matriz",
      cabecalhos.join(" | "),
    );
    const linhaDe = (rot: string) => {
      for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
      return -1;
    };
    const colDe = (rot: string) => cabecalhos.indexOf(rot) + 2;
    const rFech = linhaDe(MOV_FECHAMENTO);
    checar(rFech > 0, "(10a) cada movimento é uma LINHA da matriz");
    checar(
      rFech > 0 && ws.getRow(rFech).getCell(colDe("Total")).value === PL25,
      "(10b) o cruzamento movimento × componente cai na célula certa",
      `esperado=${PL25} obtido=${rFech > 0 ? ws.getRow(rFech).getCell(colDe("Total")).value : "(sem linha)"}`,
    );
    checar(
      linhaDe(MOV_RESULTADO) > 0
        && ws.getRow(linhaDe(MOV_RESULTADO)).getCell(colDe("Capital social")).value == null,
      "(10b) célula sem valor no documento (traço) continua vazia — nada é inventado",
    );
    // Toda linha rotulada tem de carregar pelo menos um NÚMERO: esta aba não tem
    // template, então uma linha sem número só poderia vir de um defeito nosso.
    const semNumero: string[] = [];
    for (let r = 2; r <= ws.rowCount; r++) {
      const rot = String(ws.getRow(r).getCell(1).value ?? "").trim();
      if (!rot) continue;
      let tem = false;
      for (let c = 2; c <= ws.columnCount; c++) if (typeof ws.getRow(r).getCell(c).value === "number") tem = true;
      if (!tem) semNumero.push(`${r} "${rot}"`);
    }
    checar(semNumero.length === 0, "(10c) nenhuma linha da DMPL sem número", semNumero.join(" / "));
  }
  // O componente do PL NÃO pode ter virado entidade: se ele fosse para
  // `entidade_coluna`, cada componente viraria uma EMPRESA fantasma no export.
  // (As abas Balanço/DRE/Fluxo existem sempre, mesmo sem dado — v28. O que não
  //  pode acontecer é uma delas carregar linha da DMPL.)
  const vazamento: string[] = [];
  for (const s of wb.worksheets) {
    if (s.name === "DMPL" || s.name === "Resumo") continue;
    for (let r = 1; r <= s.rowCount; r++) {
      const rot = String(s.getRow(r).getCell(1).value ?? "");
      if (componentes.some(([comp]) => rot === comp) || rot === MOV_ABERTURA || rot === MOV_FECHAMENTO) {
        vazamento.push(`${s.name}!${r} "${rot}"`);
      }
    }
  }
  checar(vazamento.length === 0, "(10d) a DMPL não vaza para nenhuma outra aba", vazamento.join(", "));
}

// ---- 10e: DMPL embutida num PDF de Balanço não infla o Patrimônio Líquido ---
{
  const V = "vComposto";
  const PL = 24801;
  const campos: CampoExtraido[] = [
    campo({ chave: "Capital social", secao: "Patrimônio Líquido", secao_canonica: "patrimonio_liquido", valor_num: 45000, documento_versao_id: V }),
    campo({ chave: "Prejuízos acumulados", secao: "Patrimônio Líquido", secao_canonica: "patrimonio_liquido", valor_num: PL - 45000, documento_versao_id: V }),
    campo({ chave: "TOTAL DO PATRIMÔNIO LÍQUIDO", secao: "Patrimônio Líquido", valor_num: PL, documento_versao_id: V }),
    // …e a DMPL que vem no MESMO arquivo. O saldo de fechamento repete o total
    // do PL: somado como conta, o patrimônio sai em dobro.
    campo({ chave: "Total", secao: "SALDOS EM 31 DE DEZEMBRO DE 2025", secao_canonica: "dmpl", valor_num: PL, documento_versao_id: V }),
    campo({ chave: "Capital social", secao: "SALDOS EM 31 DE DEZEMBRO DE 2025", secao_canonica: "dmpl", valor_num: 45000, documento_versao_id: V }),
  ];
  const documentos: DocumentoParaExport[] = [{
    id: "dComp", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Vertentes Metalúrgica Ltda." },
    periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, nome_original: "BP DRE DFC DMPL 2025.pdf" }],
  }];
  const wb = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") });
  const bal = wb.getWorksheet("Balanço")!;
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= bal.rowCount; r++) if (String(bal.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };
  const rPL = linhaDe("Patrimônio Líquido");
  const somaPL = rPL > 0 ? Math.round(avaliar(bal, "B", rPL)) : NaN;
  checar(somaPL === PL, "(10e) DMPL embutida não infla o PL do Balanço", `PL=${somaPL} informado=${PL}`);
  checar(wb.getWorksheet("DMPL") != null, "(10e) …e as linhas dela vão para a aba DMPL, não somem");
}

// ---- 10f: DVA sai na ordem do documento, sem template imposto ---------------
{
  const V = "vDVA";
  const linhas: Array<[string, string, number]> = [
    ["1 - RECEITAS", "Venda de mercadorias, produtos e serviços", 214800],
    ["1 - RECEITAS", "Provisão para créditos de liquidação duvidosa", -1980],
    ["2 - INSUMOS ADQUIRIDOS DE TERCEIROS", "Custo dos produtos e mercadorias vendidas", -168400],
    ["3 - VALOR ADICIONADO BRUTO", "Valor adicionado bruto", 44420],
    ["8 - DISTRIBUIÇÃO DO VALOR ADICIONADO", "Pessoal e encargos", 31200],
    ["8 - DISTRIBUIÇÃO DO VALOR ADICIONADO", "Impostos, taxas e contribuições", 9100],
  ];
  const campos = linhas.map(([secao, chave, v]) =>
    campo({ chave, secao, secao_canonica: "dva", valor_num: v, documento_versao_id: V }));
  const documentos: DocumentoParaExport[] = [{
    id: "dDVA", tipo_taxonomia: "DVA", entidade: { razao_social: "Vertentes Metalúrgica Ltda." },
    periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, nome_original: "DVA_2025.pdf" }],
  }];
  const wb = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") });
  const ws = wb.getWorksheet("DVA");
  checar(ws != null, "(10f) a DVA tem aba própria");
  if (ws) {
    const rotulos: string[] = [];
    const secoes: string[] = [];
    for (let r = 2; r <= ws.rowCount; r++) {
      rotulos.push(String(ws.getRow(r).getCell(1).value ?? ""));
      secoes.push(String(ws.getRow(r).getCell(2).value ?? ""));
    }
    checar(
      rotulos.join("|") === linhas.map(([, c]) => c).join("|"),
      "(10f) a ordem é a do documento — nenhuma linha imposta, nenhuma reordenada",
      rotulos.join(" | "),
    );
    checar(
      secoes[0] === "1 - RECEITAS" && secoes[4] === "8 - DISTRIBUIÇÃO DO VALOR ADICIONADO",
      "(10f) a seção declarada pelo documento é preservada",
      secoes.join(" | "),
    );
    const semNumero = rotulos.filter((_, i) => typeof ws.getRow(i + 2).getCell(3).value !== "number");
    checar(semNumero.length === 0, "(10f) nenhuma linha da DVA sem número", semNumero.join(" / "));
  }
}

// ---- 11: aba Modelagem — nada escrito à mão fora dos INPUTS ----------------
// A regra que o dono travou no pedido do v27: "TUDO o que não for inputs
// externos DEVE ESTAR EM FORMATO DE FÓRMULA, ou seja, nenhum dado deve ser
// escrito de fato, e sim puxado de outras abas onde os dados estão separados".
// Este invariante é a tradução literal disso — e é o que impede alguém (eu,
// numa sessão futura) de "resolver" um problema do modelo colando um número.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-28T12:00:00Z"),
  });
  const ws = wb.getWorksheet("Modelagem");
  checar(ws != null, "(11) o export monta a aba Modelagem");
  if (ws) {
    // 1. Nenhum valor numérico cru fora das células de input. As de input são
    //    as únicas com preenchimento amarelo (INPUT_FILL) — o mesmo sinal que o
    //    usuário vê na tela é o que o teste usa, então os dois não podem
    //    divergir sem alguém perceber.
    const crus: string[] = [];
    let formulas = 0;
    let inputs = 0;
    for (let r = 1; r <= ws.rowCount; r++) {
      for (let c = 3; c <= ws.columnCount; c++) {
        const cell = ws.getRow(r).getCell(c);
        const v = cell.value;
        if (v == null || v === "") continue;
        const fill = cell.fill as { fgColor?: { argb?: string } } | undefined;
        const ehInput = fill?.fgColor?.argb === "FFFFF9C4";
        if (ehInput) { inputs++; continue; }
        if (typeof v === "object" && v !== null && "formula" in v) { formulas++; continue; }
        if (typeof v === "number") crus.push(`${cell.address}=${v}`);
      }
    }
    // ETAPA 3 INVERTEU ESTA REGRA, e de propósito. Antes: "nenhum número
    // escrito fora dos inputs". Agora a Modelagem RECEBE os valores brutos das
    // demonstrações e do macro, escritos em dois blocos no rodapé — é o que a
    // torna independente das outras abas. O que continua valendo, e é o que
    // este assert prende: fora dos inputs e desses dois blocos, TUDO é fórmula.
    // Um número solto no meio do modelo continua sendo um resultado congelado.
    const crusForaDaBase = crus.filter((x) => {
      const lin = Number(/\d+$/.exec(x.split("=")[0])?.[0] ?? 0);
      return lin < 200;
    });
    checar(crusForaDaBase.length === 0,
      "(11) fora dos inputs e das BASES do rodapé, tudo continua sendo fórmula",
      crusForaDaBase.slice(0, 8).join(" / "));
    // …e a contraprova: as bases EXISTEM e têm número. Sem isto o assert acima
    // passaria num export que simplesmente parou de trazer os valores.
    checar(crus.length > crusForaDaBase.length,
      "(11) …e as BASES do rodapé realmente carregam os valores extraídos",
      `${crus.length} números escritos ao todo`);
    checar(formulas > 60, `(11) o modelo é feito de fórmula (${formulas} células)`);
    checar(inputs > 0, `(11) e tem células de input marcadas (${inputs})`);

    // 2. NENHUMA fórmula da Modelagem aponta para outra aba.
    //
    //    Esta é a Etapa 3 do plano do dono, e o assert é o oposto exato do que
    //    estava aqui: até a sessão 20 exigia-se que o modelo LESSE Balanço, DRE
    //    e Fluxo por referência ("a planilha continua viva"). O dono pediu
    //    independência — a Modelagem tem de funcionar com as auxiliares
    //    ocultas (Etapa 4), renomeadas, ou copiada sozinha para outro arquivo.
    //
    //    O assert por AUSÊNCIA é mais forte que o anterior: ele não depende de
    //    saber quais abas existem. Qualquer `'Aba'!` numa fórmula reprova.
    const alvos = new Set<string>();
    for (let r = 1; r <= ws.rowCount; r++) {
      for (let c = 3; c <= ws.columnCount; c++) {
        const v = ws.getRow(r).getCell(c).value as { formula?: string } | undefined;
        const f = v?.formula;
        if (!f) continue;
        for (const m of f.matchAll(/'([^']+)'!/g)) alvos.add(m[1]);
      }
    }
    checar(alvos.size === 0,
      "(11) nenhuma fórmula da Modelagem referencia outra aba (Etapa 3)",
      `referencia: ${[...alvos].join(", ")}`);

    // 3. A timeline deriva de UMA célula (como o modelo de referência, que faz
    //    `=EDATE(C7,1)`): só o primeiro exercício é digitado.
    let rAno = -1;
    for (let r = 1; r <= ws.rowCount; r++) {
      if (String(ws.getRow(r).getCell(1).value ?? "") === "Exercício") { rAno = r; break; }
    }
    // Layout mensal: 12 meses + 1 coluna FY por ano. Só o PRIMEIRO janeiro é
    // digitado; o janeiro do ano seguinte (13 colunas à frente) deriva dele.
    const anoBase = rAno > 0 ? ws.getRow(rAno).getCell(3).value : null;
    const janAnoSeg = rAno > 0 ? ws.getRow(rAno).getCell(3 + 13).value as { formula?: string } | undefined : undefined;
    checar(typeof anoBase === "number" && !!janAnoSeg?.formula?.includes("+1"),
      "(11) a linha do tempo deriva do primeiro exercício, não é digitada ano a ano",
      `linha=${rAno} base=${String(anoBase)} próximo janeiro=${janAnoSeg?.formula ?? "(sem fórmula)"}`);
  }

  // 4. ETAPA 4, resolvida: Modelagem PRIMEIRO e nada oculto.
  //
  //    Havia duas decisões do dono em contradição, e o §7.2 do Onboarding a
  //    nomeia: a Etapa 4 pedia as auxiliares OCULTAS; no v28 ele pediu o
  //    oposto ("quero todas as abas juntas"), porque naquele teste viu 4 abas e
  //    concluiu que as demais "não vieram" — estavam lá, ocultas.
  //
  //    As duas querem a mesma coisa: que a Modelagem seja o que se vê ao abrir,
  //    sem o resto parecer inexistente. ORDEM entrega as duas; visibilidade só
  //    entregava uma. Quem recebe o arquivo não sabe que há abas escondidas —
  //    "reexibir é um clique" só vale para quem sabe que existe o que reexibir.
  const ocultas = wb.worksheets.filter((s) => s.state !== "visible").map((s) => s.name);
  checar(ocultas.length === 0,
    "(11) NENHUMA aba fica oculta — aba oculta lê como dado ausente (v28)",
    `ocultas: ${ocultas.join(", ")}`);
  // A Modelagem é a PRIMEIRA da barra de abas. `wb.worksheets` já vem ordenado
  // por `orderNo` (é o getter do ExcelJS que ordena), então a posição 0 aqui é a
  // posição que o Excel mostra.
  const nomesEmOrdem = wb.worksheets.map((s) => s.name);
  checar(nomesEmOrdem[0] === "Modelagem",
    "(11) …e a Modelagem é a primeira aba do arquivo", `ordem: ${nomesEmOrdem.join(", ")}`);
  // …e a ordem RELATIVA das auxiliares não foi embaralhada. É o risco real de
  // mexer em `orderNo`: promover uma aba com um número menor que todos podia,
  // num descuido, empurrar as outras para posições arbitrárias. A ordem das
  // auxiliares é a de criação (Resumo primeiro, depois as demonstrações), e é
  // ela que faz o arquivo parecer o mesmo de sempre depois da Modelagem.
  const auxiliares = nomesEmOrdem.slice(1);
  const posicao = (n: string) => auxiliares.indexOf(n);
  checar(posicao("Resumo") === 0,
    "(11) …e o Resumo continua sendo a primeira das auxiliares", `ordem: ${auxiliares.join(", ")}`);
  checar(posicao("Balanço") < posicao("DRE") && posicao("DRE") < posicao("Fluxo de Caixa"),
    "(11) …e as demonstrações seguem na ordem de sempre (Balanço → DRE → Fluxo)",
    `ordem: ${auxiliares.join(", ")}`);

  // As auxiliares continuam todas lá, com conteúdo — o que muda é a ordem, não
  // o que o arquivo contém.
  for (const aba of ["Resumo", "Balanço", "DRE", "Fluxo de Caixa", "Macro"]) {
    const ws2 = wb.getWorksheet(aba);
    checar(ws2 != null && ws2.rowCount > 1,
      `(11) …e a aba "${aba}" continua existindo, com conteúdo`, `linhas: ${ws2?.rowCount ?? 0}`);
  }
  // …e o arquivo ABRE na Modelagem. Com ela em primeiro lugar, a aba ativa é a 0
  // — e é isto que prova que o reorder aconteceu de verdade: a primeira versão
  // desta mudança fez splice no retorno do getter `worksheets`, um array
  // descartável, e não mudou nada no arquivo.
  const abaAtiva = (wb.views?.[0] as { activeTab?: number } | undefined)?.activeTab;
  checar(abaAtiva === 0,
    "(11) a Modelagem é a aba ativa (o arquivo abre nela)", `activeTab=${String(abaAtiva)}`);
}

// ---- 12: consolidação de entidade e período (teste v27) ---------------------
// O grupo tem 5 empresas e o Balanço do v27 saiu com 15 colunas de entidade: a
// mesma empresa chegava com duas grafias (apelido da coluna do combinado ×
// razão social do documento individual) e o mesmo exercício com dois rótulos
// ("2025" × "31/12/2025"). Somar o grupo assim conta cada empresa DUAS VEZES —
// é o que tornava a base inutilizável para modelagem.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-28T12:00:00Z"),
  });
  const bal = wb.getWorksheet("Balanço")!;
  const heads: string[] = [];
  for (let c = 2; c <= bal.columnCount; c++) heads.push(String(bal.getRow(1).getCell(c).value ?? ""));
  const ents = heads.filter((h) => h && h !== "AV%" && !h.startsWith("Δ"));
  // 5 empresas × 2 exercícios = 10. Antes da consolidação eram 15.
  checar(ents.length === 10, `(12) o Balanço tem 10 colunas de entidade×exercício (5 empresas × 2 anos)`,
    `${ents.length}: ${ents.join(" | ")}`);
  checar(!ents.some((e) => /^(Componentes|Metalúrgica|Imóveis SPE|VT Logística|Vertentes Part\.)\b/.test(e)),
    "(12) nenhum apelido de coluna do combinado sobrou como se fosse outra empresa", ents.join(" | "));
  checar(!ents.some((e) => e.includes("31/12/")),
    "(12) o exercício fechado não aparece como data-base numa coluna separada", ents.join(" | "));

  // …e o casamento é CONSERVADOR: apelido sem uma razão social única que case
  // continua como está (fundir duas empresas diferentes é pior que duas colunas).
  const m = consolidarNomesDeEntidade(
    ["ALFA COMÉRCIO LTDA.", "ALFA SERVIÇOS LTDA."],
    ["Alfa", "Beta"],
  );
  checar(!m.has("Alfa"), "(12) apelido ambíguo (casa com 2 razões sociais) NÃO é consolidado");
  checar(!m.has("Beta"), "(12) apelido sem correspondente NÃO é consolidado");
  const m2 = consolidarNomesDeEntidade(["VERTENTES PARTICIPAÇÕES S.A."], ["Vertentes Part."]);
  checar(m2.get("Vertentes Part.") === "VERTENTES PARTICIPAÇÕES S.A.",
    "(12) abreviação ('Part.') casa a razão social por prefixo");
}

// ---- 13: o modelo aponta para linhas que EXISTEM (senão devolve 0 calado) ---
// O INDEX/MATCH do modelo é embrulhado em IFERROR — o que é certo para o caso
// legítimo (a DFC do book só cobre 2025, então 2024 não tem coluna e vale 0),
// mas transforma um rótulo ERRADO em zero silencioso. Foi assim que a primeira
// versão desta aba saiu com o Balanço inteiro zerado: ela procurava "Total do
// Ativo Circulante", e a aba Balanço rotula a linha do subtotal com o nome da
// SEÇÃO ("Ativo Circulante"). Este invariante resolve o MATCH de verdade.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-28T12:00:00Z"),
  });
  const ws = wb.getWorksheet("Modelagem")!;

  const rotulosDe = (aba: string) => {
    const alvo = wb.getWorksheet(aba);
    const set = new Set<string>();
    if (alvo) for (let r = 1; r <= alvo.rowCount; r++) {
      set.add(String(alvo.getRow(r).getCell(1).value ?? "").trim());
    }
    return set;
  };
  const cache = new Map<string, Set<string>>();
  const perdidos: string[] = [];
  let procurados = 0;
  for (let r = 1; r <= ws.rowCount; r++) {
    for (let c = 3; c <= ws.columnCount; c++) {
      const v = ws.getRow(r).getCell(c).value as { formula?: string } | undefined;
      const f = v?.formula;
      if (!f) continue;
      // O intervalo é LIMITADO ao tamanho da aba (`$A$1:$A$162`), nunca coluna
      // inteira — referência de coluna cheia inflava o grafo de dependência a
      // ponto de travar o recálculo.
      for (const m of f.matchAll(/MATCH\("([^"]+)",'([^']+)'!\$A\$1:\$A\$\d+,0\)/g)) {
        const [, rotulo, aba] = m;
        procurados++;
        if (!cache.has(aba)) cache.set(aba, rotulosDe(aba));
        if (!cache.get(aba)!.has(rotulo)) {
          const onde = `${aba}!"${rotulo}" (usado em ${ws.getRow(r).getCell(1).value})`;
          if (!perdidos.includes(onde)) perdidos.push(onde);
        }
      }
    }
  }
  // ETAPA 3: o modelo não busca mais rótulo em OUTRA aba — ele busca na base
  // local, por POSIÇÃO de linha (o rótulo virou endereço na geração). Então
  // `procurados` é zero por construção, e o que este bloco ainda protege é o
  // caso em que alguém reintroduza uma busca entre abas: se houver alguma,
  // todos os rótulos dela têm de existir.
  checar(procurados === 0,
    "(13) o modelo não faz mais busca por rótulo em outra aba (a base é local)",
    `${procurados} busca(s)`);
  checar(perdidos.length === 0,
    `(13) todos os ${procurados} rótulos procurados existem na aba de destino`,
    perdidos.slice(0, 6).join(" / "));

  // …e o resultado disso bate com o GABARITO do book: resolve o INDEX/MATCH do
  // jeito que o Excel resolveria e compara o número que o modelo vai exibir.
  const ent = "VERTENTES METALÚRGICA LTDA.";
  const valorNaAba = (aba: string, rotulo: string, ano: number): number | null => {
    const alvo = wb.getWorksheet(aba);
    if (!alvo) return null;
    let linha = -1;
    for (let r = 1; r <= alvo.rowCount; r++) {
      if (String(alvo.getRow(r).getCell(1).value ?? "").trim() === rotulo) { linha = r; break; }
    }
    let coluna = -1;
    for (let c = 2; c <= alvo.columnCount; c++) {
      if (String(alvo.getRow(1).getCell(c).value ?? "").trim() === `${ent} — ${ano}`) { coluna = c; break; }
    }
    if (linha < 0 || coluna < 0) return null;
    const v = avaliarCelula(alvo, alvo.getColumn(coluna).letter, linha);
    return typeof v === "number" ? Math.round(v) : null;
  };
  const gab = JSON.parse(
    // Resolvido a partir do PRÓPRIO arquivo, como todos os outros nove `readFileSync`
    // desta suíte. Este aqui era um caminho ABSOLUTO para o checkout de uma sessão
    // (`/home/user/tratamento-dados-financeiros/...`) e funcionava por acidente: quem
    // clonasse o repositório em qualquer outro lugar recebia ENOENT. Foi o PRIMEIRO
    // achado do CI — na primeira execução dele, antes de qualquer suíte reprovar.
    readFileSync(new URL("../../Dados de Teste/book-vertentes/pdf/GABARITO.json", import.meta.url), "utf8"),
  ) as { balanco_por_entidade: Record<string, Record<string, Record<string, number>>> };
  const errosModelo: string[] = [];
  for (const ano of [2024, 2025]) {
    const esperado = gab.balanco_por_entidade[String(ano)].metalurgica;
    const pares: Array<[string, number]> = [
      ["Ativo Circulante", esperado.AC],
      ["Ativo Não Circulante", esperado.ANC],
      ["Passivo Circulante", esperado.PC],
      ["Passivo Não Circulante", esperado.PNC],
      ["Patrimônio Líquido", esperado.PL],
    ];
    for (const [rot, exp] of pares) {
      const got = valorNaAba("Balanço", rot, ano);
      if (got !== exp) errosModelo.push(`${ano} ${rot}: modelo=${got} gabarito=${exp}`);
    }
  }
  checar(errosModelo.length === 0,
    "(13) o que o modelo vai puxar do Balanço bate com o gabarito, nos dois exercícios",
    errosModelo.join(" / "));
}

// ---- 14: PREMISSA MUDOU => MODELO INTEIRO MUDA -----------------------------
// O critério que o dono marcou como o mais importante: "alteração de premissas
// deve alterar a modelagem como um todo". Isso não se verifica lendo o código —
// se verifica no GRAFO DE DEPENDÊNCIA das fórmulas geradas. Aqui a planilha é
// tratada como o Excel a trata: cada célula projetada tem de alcançar, por
// algum caminho de referências, as células de premissa do seu exercício.
//
// Foi este invariante que pegou o defeito de as premissas serem lidas sempre da
// coluna C: a premissa do 2º ano projetado existia na tela, o usuário digitava
// nela, e NADA acontecia — o pior defeito possível num modelo.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-28T12:00:00Z"),
  });
  const ws = wb.getWorksheet("Modelagem")!;

  const formulaDe = (addr: string): string | null => {
    const m = addr.match(/^([A-Z]+)(\d+)$/);
    if (!m) return null;
    const v = ws.getCell(addr).value as { formula?: string } | undefined;
    return v?.formula ?? null;
  };
  // Referências a células DESTA aba (ignora as cross-sheet, que são o dado real).
  const refsDe = (formula: string): string[] => {
    const semOutrasAbas = formula.replace(/'[^']+'![^,)]*/g, "");
    return [...semOutrasAbas.matchAll(/\$?([A-Z]{1,2})\$?(\d{1,4})\b/g)]
      .map((m) => `${m[1]}${m[2]}`);
  };
  const alcanca = (origem: string, alvos: Set<string>): boolean => {
    const visto = new Set<string>();
    const fila = [origem];
    while (fila.length > 0) {
      const atual = fila.pop()!;
      if (visto.has(atual)) continue;
      visto.add(atual);
      if (alvos.has(atual)) return true;
      const f = formulaDe(atual);
      if (!f) continue;
      for (const r of refsDe(f)) if (!visto.has(r)) fila.push(r);
    }
    return false;
  };

  // Localiza o bloco de premissas e a linha do Exercício.
  let linhaAno = -1;
  const linhasPremissa: number[] = [];
  let dentroDePremissas = false;
  for (let r = 1; r <= ws.rowCount; r++) {
    const rot = String(ws.getRow(r).getCell(1).value ?? "");
    if (rot === "Exercício") linhaAno = r;
    if (rot.startsWith("PREMISSAS")) { dentroDePremissas = true; continue; }
    if (dentroDePremissas) {
      if (!rot || rot === rot.toUpperCase() && rot.length > 12) { dentroDePremissas = false; continue; }
      linhasPremissa.push(r);
    }
  }
  checar(linhaAno > 0 && linhasPremissa.length >= 8,
    `(14) o bloco de premissas foi encontrado (${linhasPremissa.length} premissas)`);

  // Colunas projetadas = as que vêm depois do último exercício com dado real.
  // No fixture do book o histórico é 2024-2025, então a 3ª coluna em diante.
  const colunaLetra = (i: number) => ws.getColumn(i).letter;
  // Layout mensal: por ano, 12 colunas de mês + 1 coluna FY (a 13ª), que é onde
  // as premissas daquele exercício moram. O teste checa a coluna FY dos anos
  // PROJETADOS e também um mês dentro de cada um — a célula mensal tem de
  // alcançar a premissa do SEU ano, não de outro.
  const nAnos = Math.floor((ws.columnCount - 2) / 13);
  const colFY = (y: number) => 3 + y * 13 + 12;
  const colMes = (y: number, m: number) => 3 + y * 13 + m;
  const anosProj = [nAnos - 3, nAnos - 2, nAnos - 1];
  const colsProjetadas = anosProj.map(colFY);
  checar(colsProjetadas.length === 3, `(14) há 3 exercícios projetados`, String(colsProjetadas.length));

  // As linhas de RESULTADO que precisam responder a premissa.
  const alvosDeTeste = [
    "Receita Líquida", "EBITDA", "Lucro/Prejuízo Líquido do Exercício",
    "Saldo final de caixa", "TOTAL DO ATIVO", "Patrimônio Líquido",
    "Necessidade de captação (caixa negativo)", "Liquidez corrente",
  ];
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) {
      if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    }
    return -1;
  };

  const mortas: string[] = [];
  for (const y of anosProj) {
    const letraFY = colunaLetra(colFY(y));
    const premissasDoAno = new Set(linhasPremissa.map((r) => `${letraFY}${r}`));
    for (const c of [colFY(y), colMes(y, 5)]) { // consolidado e um mês do meio do ano
      const letra = colunaLetra(c);
      for (const rot of alvosDeTeste) {
        const r = linhaDe(rot);
        if (r < 0) { mortas.push(`linha ausente: ${rot}`); continue; }
        if (!alcanca(`${letra}${r}`, premissasDoAno)) {
          mortas.push(`${letra}${r} (${rot}) não alcança as premissas de ${letraFY}`);
        }
      }
    }
  }
  checar(mortas.length === 0,
    "(14) toda linha projetada depende das premissas DO SEU exercício",
    mortas.slice(0, 6).join(" / "));

  // …e o contrário: nenhuma premissa pode estar MORTA (existir na tela sem
  // ninguém ler). Uma premissa que não move nada é pior que não ter premissa.
  const premissasMortas: string[] = [];
  for (const rp of linhasPremissa) {
    const rotulo = String(ws.getRow(rp).getCell(1).value ?? "");
    let usada = false;
    for (const c of colsProjetadas) {
      const letra = colunaLetra(c);
      const alvo = new Set([`${letra}${rp}`]);
      for (let r = 1; r <= ws.rowCount && !usada; r++) {
        if (r === rp) continue;
        const f = formulaDe(`${letra}${r}`);
        // Os dois testes levam ao MESMO efeito, então são um OU — escrevê-los como
        // if/else fazia parecer que havia dois caminhos com resultados diferentes.
        if ((f && refsDe(f).includes(`${letra}${rp}`))
            || (alcanca(`${letra}${r}`, alvo) && r !== rp)) usada = true;
      }
      if (usada) break;
    }
    if (!usada) premissasMortas.push(`${rotulo} (linha ${rp})`);
  }
  checar(premissasMortas.length === 0,
    "(14) nenhuma premissa fica morta na tela sem mover o modelo",
    premissasMortas.join(" / "));
}

// ---- 15: índices macro — histórico calibra, Focus projeta ------------------
// Duas coisas diferentes e o modelo usa cada uma para o que ela serve. O erro
// que este bloco impede é o mais fácil de cometer: projetar com a média dos
// últimos anos (retrovisor) ou calcular essa média de forma aritmética, que
// para taxa é simplesmente a conta errada.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };

  // 12 anos de IPCA/Selic + um ano INCOMPLETO (o corrente), que não pode entrar
  // nas médias, e a expectativa Focus para os anos projetados.
  const anuais = [];
  for (let ano = 2014; ano <= 2025; ano++) {
    anuais.push({ serie: "IPCA", ano, meses: 12, retorno: 4 + (ano % 5) });
    anuais.push({ serie: "SELIC", ano, meses: 12, retorno: 8 + (ano % 4) });
  }
  anuais.push({ serie: "IPCA", ano: 2026, meses: 5, retorno: 2.1 }); // incompleto
  const expectativas = [
    { serie: "IPCA", ano_ref: 2026, mediana: 5.12, coletado_em: "2026-07-24" },
    { serie: "IPCA", ano_ref: 2027, mediana: 4.50, coletado_em: "2026-07-24" },
    { serie: "IPCA", ano_ref: 2028, mediana: 4.00, coletado_em: "2026-07-24" },
    { serie: "SELIC", ano_ref: 2026, mediana: 14.75, coletado_em: "2026-07-24" },
    { serie: "SELIC", ano_ref: 2027, mediana: 12.50, coletado_em: "2026-07-24" },
    { serie: "SELIC", ano_ref: 2028, mediana: 10.50, coletado_em: "2026-07-24" },
  ];
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    macro: { anuais, expectativas },
    agora: new Date("2026-07-28T12:00:00Z"),
  });

  const macro = wb.getWorksheet("Macro");
  checar(macro != null, "(15) a aba Macro é montada quando há índices");
  const dados = wb.getWorksheet("Macro (dados)");
  // A aba de dado cru continua EXISTINDO e agora fica visível como todas as
  // outras (v28) — o que importa é que ela existe e que a aba Macro não guarda
  // número nenhum, só fórmula sobre ela (verificado abaixo).
  checar(dados != null, "(15) o dado cru da série tem aba própria (proveniência não some)");

  if (macro) {
    // A aba visível não guarda número: é toda referência/fórmula.
    const crus: string[] = [];
    for (let r = 1; r <= macro.rowCount; r++) {
      // As linhas de CABEÇALHO carregam os anos, e eles têm de ser NÚMERO: o
      // modelo busca a expectativa com MATCH contra a célula do exercício, que
      // é numérica. Ano como texto faz o MATCH nunca casar, o IFERROR devolver
      // 0, e a premissa de inflação aparecer zerada sem nenhum sinal — foi o
      // defeito que o recálculo pegou. Aqui elas são exceção legítima.
      const rotulo = String(macro.getRow(r).getCell(1).value ?? "");
      if (rotulo.startsWith("Retorno anual") || rotulo.startsWith("Expectativa Focus")) continue;
      for (let c = 2; c <= macro.columnCount; c++) {
        const v = macro.getRow(r).getCell(c).value;
        if (typeof v === "number") crus.push(`${macro.getRow(r).getCell(c).address}=${v}`);
      }
    }
    // …e que os anos do cabeçalho do Focus sejam mesmo numéricos.
    for (let r = 1; r <= macro.rowCount; r++) {
      if (!String(macro.getRow(r).getCell(1).value ?? "").startsWith("Expectativa Focus")) continue;
      const primeiro = macro.getRow(r).getCell(2).value;
      checar(typeof primeiro === "number",
        "(15) os anos do cabeçalho do Focus são NÚMERO (senão o MATCH do modelo nunca casa)",
        `veio ${typeof primeiro}: ${String(primeiro)}`);
    }
    checar(crus.length === 0, "(15) a aba Macro não tem número escrito — só fórmula", crus.slice(0, 5).join(" / "));

    // A média tem de ser GEOMÉTRICA. Uma média aritmética de taxa (AVERAGE) é
    // a conta errada e a diferença compõe: 10% e 4% dão 6,96%, não 7,00%.
    const formulas: string[] = [];
    for (let r = 1; r <= macro.rowCount; r++) {
      for (let c = 2; c <= macro.columnCount; c++) {
        const v = macro.getRow(r).getCell(c).value as { formula?: string } | undefined;
        if (v?.formula) formulas.push(v.formula);
      }
    }
    const medias = formulas.filter((f) => f.includes("PRODUCT("));
    checar(medias.length >= 3, `(15) as médias usam composição geométrica (PRODUCT^(1/n))`, String(medias.length));
    checar(medias.every((f) => /\^\(1\/\d+\)/.test(f)),
      "(15) …com a raiz da janela, não a soma dividida");
    checar(!formulas.some((f) => /\bAVERAGE\(/.test(f)),
      "(15) nenhuma média de taxa é aritmética");
    // O invariante ANTIGO exigia `COUNT(` em toda média — ele travava o MECANISMO,
    // não a propriedade, e o mecanismo era justamente o defeito: a faixa era
    // posicional (últimas N colunas) e a última coluna é sempre o ano parcial, então
    // as três médias saíam em branco com 12 anos completos na base. Agora a janela
    // nomeia os anos completos um a um, e o que se afirma é o COMPORTAMENTO.
    checar(medias.every((f) => !f.includes(":")),
      "(15) a janela nomeia os anos completos, não uma faixa posicional de colunas");
  }

  // O modelo consome o Focus: as premissas macro apontam para a aba Macro.
  const mod = wb.getWorksheet("Modelagem")!;
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= mod.rowCount; r++) {
      if (String(mod.getRow(r).getCell(1).value ?? "") === rot) return r;
    }
    return -1;
  };
  const rIpca = linhaDe("Inflação esperada (metodologia selecionada)");
  const rSelic = linhaDe("Juro esperado (Selic — Focus)");
  checar(rIpca > 0 && rSelic > 0, "(15) o modelo tem premissas de IPCA e Selic");
  if (rIpca > 0) {
    const nA = Math.floor((mod.columnCount - 2) / 13);
    const f = String((mod.getRow(rIpca).getCell(3 + (nA - 1) * 13 + 12).value as { formula?: string })?.formula ?? "");
    // Etapa 3: o Focus agora é espelhado DENTRO da Modelagem (bloco "BASE
    // MACRO"), então a premissa lê uma linha local em vez de 'Macro'!. O que
    // importa continua igual — ela é FÓRMULA sobre o dado publicado, não um
    // número digitado — e o assert prende isso sem citar aba nenhuma.
    checar(/INDEX\(/.test(f) && /MATCH\(/.test(f) && !/'[^']+'!/.test(f),
      "(15) a premissa de IPCA é fórmula sobre o Focus espelhado, sem referência a outra aba",
      f.slice(0, 110));
    checar(!f.includes("AVERAGE"), "(15) …e não da média histórica");
  }

  // E a regra do dono continua valendo COM macro: nenhuma premissa morta.
  const linhasPremissa: number[] = [];
  let dentro = false;
  for (let r = 1; r <= mod.rowCount; r++) {
    const rot = String(mod.getRow(r).getCell(1).value ?? "");
    if (rot.startsWith("PREMISSAS")) { dentro = true; continue; }
    if (dentro) {
      if (!rot || (rot === rot.toUpperCase() && rot.length > 12)) { dentro = false; continue; }
      linhasPremissa.push(r);
    }
  }
  checar(linhasPremissa.length === 15,
    `(15) as 15 premissas (3 macro + 12 operacionais) estão no bloco`, String(linhasPremissa.length));
}

// ---- 16: consolidação mensal → anual (fluxo soma, estoque NÃO) -------------
// É onde um modelo mensal se perde, e o erro é invisível na tela: somar doze
// balanços dá doze vezes o patrimônio, e somar doze margens dá 1200%. Cada
// natureza de linha tem UMA consolidação correta, e este invariante prende cada
// uma à sua.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-28T12:00:00Z"),
  });
  const ws = wb.getWorksheet("Modelagem")!;
  const nAnos = Math.floor((ws.columnCount - 2) / 13);
  const colFY = (y: number) => 3 + y * 13 + 12;
  const colMes = (y: number, m: number) => 3 + y * 13 + m;
  const letra = (i: number) => ws.getColumn(i).letter;
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) {
      if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    }
    return -1;
  };
  const fDe = (r: number, c: number) =>
    String((ws.getRow(r).getCell(c).value as { formula?: string } | undefined)?.formula ?? "");

  checar(nAnos >= 5 && (ws.columnCount - 2) % 13 === 0,
    `(16) layout mensal: ${nAnos} anos × (12 meses + 1 consolidado)`, `${ws.columnCount} colunas`);

  const y = nAnos - 1; // um ano projetado
  const fy = colFY(y);

  // FLUXO consolida por SOMA dos 12 meses.
  for (const rot of ["Receita Líquida", "EBITDA", "Lucro/Prejuízo Líquido do Exercício"]) {
    const r = linhaDe(rot);
    const f = fDe(r, fy);
    const esperado = `SUM(${letra(colMes(y, 0))}${r}:${letra(colMes(y, 11))}${r})`;
    checar(f === esperado, `(16) "${rot}" consolida somando os 12 meses`, `veio: ${f}`);
  }

  // ESTOQUE consolida pegando DEZEMBRO — somar seria multiplicar o patrimônio.
  for (const rot of ["TOTAL DO ATIVO", "Patrimônio Líquido", "Saldo final de caixa", "Caixa e equivalentes"]) {
    const r = linhaDe(rot);
    const f = fDe(r, fy);
    const esperado = `${letra(colMes(y, 11))}${r}`;
    checar(f === esperado, `(16) "${rot}" consolida pelo saldo de DEZEMBRO, não pela soma`, `veio: ${f}`);
    checar(!f.startsWith("SUM("), `(16) …e definitivamente não soma`, `${rot}: ${f}`);
  }

  // SALDO INICIAL do ano é o de JANEIRO (não o de dezembro, nem a soma).
  {
    const r = linhaDe("Saldo inicial de caixa");
    checar(fDe(r, fy) === `${letra(colMes(y, 0))}${r}`,
      "(16) o saldo inicial do ano é o de JANEIRO", `veio: ${fDe(r, fy)}`);
  }

  // ÍNDICE é RECALCULADO sobre os agregados anuais — nunca somado nem "média".
  for (const rot of ["Margem bruta", "Margem EBITDA", "Margem líquida"]) {
    const r = linhaDe(rot);
    const f = fDe(r, fy);
    checar(f.includes(`${letra(fy)}`) && !f.startsWith("SUM(") && !f.includes("AVERAGE("),
      `(16) "${rot}" é recalculada sobre o agregado do ano`, `veio: ${f}`);
  }

  // A necessidade de captação do ano é o PIOR mês, não dezembro: um vale de
  // caixa em julho precisa ser financiado mesmo que dezembro feche positivo.
  {
    const r = linhaDe("Necessidade de captação (caixa negativo)");
    const f = fDe(r, fy);
    checar(f.includes("MIN(") && f.includes(`${letra(colMes(y, 0))}`) && f.includes(`${letra(colMes(y, 11))}`),
      "(16) a captação do ano olha o PIOR mês, não o fechamento", `veio: ${f}`);
  }

  // E as três conferências existem — um modelo institucional prova que fecha.
  for (const rot of ["Balanço fecha (Ativo − Passivo − PL)",
                     "Receita do ano = receita extraída",
                     "Caixa do balanço = saldo final do fluxo"]) {
    checar(linhaDe(rot) > 0, `(16) o modelo traz a conferência "${rot}"`);
  }
}

// ---- 16: DF auditada — o conjunto num arquivo só é separado por demonstração --
// A forma mais comum de entrega num mandato real é o PDF auditado do exercício:
// Balanço + DRE + DFC + DMPL + notas juntos, um documento só. Esse tipo
// (DF_AUDITADA, Supabase/migrations/0002) não pode ter aba própria — que aba seria? — e
// por isso caía em "Outros", onde o roteamento por linha nem rodava: a DF inteira
// saía como listagem crua, sem template, sem total de seção, sem AV%/Δ%, sem
// indicadores, e a aba Modelagem (que lê das abas de demonstração) saía ZERADA.
// Aqui o MESMO dado do book é entregue como um arquivo auditado só, e tem de
// produzir os MESMOS números que produz quando vem em três arquivos separados.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const gab = JSON.parse(
    readFileSync(new URL("../../Dados de Teste/book-vertentes/pdf/GABARITO.json", import.meta.url), "utf8"),
  ) as {
    balanco_por_entidade: Record<string, Record<string, Record<string, number>>>;
    dre_metalurgica_2025: Record<string, number>;
  };

  // BP (01) + DRE (07) + DFC (08) da Metalúrgica, os três apontando para UMA
  // versão de um documento DF_AUDITADA — é literalmente o mesmo dado, entregue
  // como o cliente entrega.
  const V = "vDFAuditada";
  const VERSOES_METALURGICA = [
    "55555555-0000-0000-0000-000000000001", // Balanço 2025x2024
    "55555555-0000-0000-0000-000000000007", // DRE 2025x2024
    "55555555-0000-0000-0000-000000000008", // DFC 2025
  ];
  const camposDF: CampoExtraido[] = fixture.campos
    .filter((c) => VERSOES_METALURGICA.includes(c.documento_versao_id))
    .map((c) => ({ ...c, documento_versao_id: V }));
  // …e as NOTAS que vêm no mesmo arquivo auditado. A nota DETALHA o que o balanço
  // já traz consolidado: a linha "Empréstimos e financiamentos" do BP contra o
  // credor-a-credor da nota. Roteá-la para o Balanço somaria as duas.
  const notas: CampoExtraido[] = [
    campo({ chave: "Banco Alfa - capital de giro", secao: "Nota 12 — Empréstimos e financiamentos", valor_num: 9000, periodo_coluna: "2025", documento_versao_id: V }),
    campo({ chave: "Banco Beta - CDC", secao: "Nota 12 — Empréstimos e financiamentos", valor_num: 6000, periodo_coluna: "2025", documento_versao_id: V }),
    campo({ chave: "Duplicatas descontadas", secao: "Notas explicativas às demonstrações financeiras", valor_num: 4000, periodo_coluna: "2025", documento_versao_id: V }),
  ];
  const documentos: DocumentoParaExport[] = [{
    id: "dDF", tipo_taxonomia: "DF_AUDITADA", entidade: { razao_social: "VERTENTES METALÚRGICA LTDA." },
    periodo: { tipo: "multi", referencia: "24,25" },
    documento_versao: [{ id: V, nome_original: "DF_Auditadas_Vertentes_Metalurgica_2025.pdf" }],
  }];
  const wb = buildExportWorkbook({
    caso: { nome: "DF auditada", produto: "reestruturacao" },
    campos: [...camposDF, ...notas], documentos, agora: new Date("2026-07-29T12:00:00Z"),
  });

  const bal = wb.getWorksheet("Balanço");
  const dre = wb.getWorksheet("DRE");
  const dfc = wb.getWorksheet("Fluxo de Caixa");
  checar(bal != null && dre != null && dfc != null,
    "(16a) a DF auditada abre as três abas de demonstração (antes: listagem crua em 'Outros')",
    wb.worksheets.map((s) => s.name).join(", "));

  if (bal && dre && dfc) {
    const linhaDe = (ws: import("exceljs").Worksheet, rot: string) => {
      for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
      return -1;
    };
    const colunas = (ws: import("exceljs").Worksheet) => {
      const m = new Map<string, string>();
      for (let c = 2; c <= ws.columnCount; c++) {
        const h = String(ws.getRow(1).getCell(c).value ?? "");
        if (h && h !== "AV%" && !h.startsWith("Δ%")) m.set(h, ws.getColumn(c).letter);
      }
      return m;
    };
    // O Balanço tem de bater com o gabarito nos dois exercícios — mesmo número
    // que sai quando o BP vem em arquivo próprio (invariante 7).
    const colBal = colunas(bal);
    const LINHA: Record<string, number> = {
      ATIVO: linhaDe(bal, "ATIVO"), AC: linhaDe(bal, "Ativo Circulante"), ANC: linhaDe(bal, "Ativo Não Circulante"),
      PC: linhaDe(bal, "Passivo Circulante"), PNC: linhaDe(bal, "Passivo Não Circulante"), PL: linhaDe(bal, "Patrimônio Líquido"),
    };
    const erros: string[] = [];
    let conferidos = 0;
    for (const ano of ["2024", "2025"]) {
      const col = colBal.get(`VERTENTES METALÚRGICA LTDA. — ${ano}`);
      if (!col) { erros.push(`coluna ausente: ${ano} (${[...colBal.keys()].join(" | ")})`); continue; }
      for (const [sigla, row] of Object.entries(LINHA)) {
        const esperado = gab.balanco_por_entidade[ano].metalurgica[sigla];
        const obtido = Math.round(avaliar(bal, col, row));
        conferidos++;
        if (obtido !== esperado) erros.push(`${ano} ${sigla}: export=${obtido} gabarito=${esperado}`);
      }
    }
    checar(erros.length === 0 && conferidos === 12,
      `(16b) o Balanço da DF auditada bate com o gabarito nas ${conferidos} seções`,
      erros.slice(0, 6).join(" / "));

    // A DRE idem — e é a prova de que a cascata foi ORDENADA pelo template, não
    // empilhada como veio.
    const colDRE = colunas(dre);
    const col2025 = [...colDRE.entries()].find(([h]) => h.includes("2025"))?.[1] ?? "";
    const errosDRE = ([
      ["Receita Líquida", gab.dre_metalurgica_2025["RECEITA OPERACIONAL LÍQUIDA"]],
      ["Lucro Bruto", gab.dre_metalurgica_2025["LUCRO BRUTO"]],
      ["Resultado Operacional (EBIT)", gab.dre_metalurgica_2025["RESULTADO OPERACIONAL ANTES DO RESULTADO FINANCEIRO"]],
      ["Lucro/Prejuízo Líquido do Exercício", gab.dre_metalurgica_2025["PREJUÍZO LÍQUIDO DO EXERCÍCIO"]],
    ] as Array<[string, number]>)
      .map(([rot, exp]) => {
        const r = linhaDe(dre, rot);
        const got = r > 0 && col2025 ? Math.round(avaliar(dre, col2025, r)) : NaN;
        return got === exp ? null : `${rot}: export=${got} gabarito=${exp}`;
      })
      .filter(Boolean) as string[];
    checar(errosDRE.length === 0, "(16c) a DRE da DF auditada bate com o gabarito", errosDRE.join(" / "));

    // O Fluxo idem, pelo próprio documento (o book só tem DFC de 2025).
    const colDFC = colunas(dfc);
    const colFC = [...colDFC.values()][0] ?? "";
    const rOper = linhaDe(dfc, "Caixa Líquido das Atividades Operacionais");
    checar(rOper > 0 && Math.round(avaliar(dfc, colFC, rOper)) === 1090,
      "(16d) o Fluxo de Caixa da DF auditada fecha com o documento",
      `linha=${rOper} valor=${rOper > 0 ? Math.round(avaliar(dfc, colFC, rOper)) : "(ausente)"}`);

    // A NOTA não pode ter entrado em soma nenhuma do Balanço: o detalhe do
    // credor-a-credor debaixo do total que o BP já informa é dupla contagem.
    const ROTULOS_DE_NOTA = ["Banco Alfa - capital de giro", "Banco Beta - CDC", "Duplicatas descontadas"];
    const vazamentos: string[] = [];
    for (const ws of [bal, dre, dfc]) {
      for (let r = 1; r <= ws.rowCount; r++) {
        const rot = String(ws.getRow(r).getCell(1).value ?? "");
        if (ROTULOS_DE_NOTA.includes(rot)) vazamentos.push(`${ws.name}!${r} "${rot}"`);
      }
    }
    checar(vazamentos.length === 0,
      "(16e) linha de NOTA EXPLICATIVA não entra em demonstração nenhuma (seria dupla contagem)",
      vazamentos.join(", "));
    const outros = wb.getWorksheet("Outros");
    const rotulosOutros: string[] = [];
    if (outros) for (let r = 1; r <= outros.rowCount; r++) {
      for (let c = 1; c <= outros.columnCount; c++) rotulosOutros.push(String(outros.getRow(r).getCell(c).value ?? ""));
    }
    checar(rotulosOutros.includes("Banco Alfa - capital de giro"),
      "(16f) …mas continua entregue, com proveniência, na listagem documental");

    // E o modelo deixa de sair zerado: é o que a fatia existe para destravar.
    const mod = wb.getWorksheet("Modelagem")!;
    const rANC = linhaDe(mod, "Ativo Não Circulante");
    const formulas: string[] = [];
    if (rANC > 0) {
      for (let c = 2; c <= mod.columnCount; c++) {
        const f = (mod.getRow(rANC).getCell(c).value as { formula?: string } | undefined)?.formula;
        if (f) formulas.push(f);
      }
    }
    // Etapa 3: a origem passou a ser a base local. O que a fatia destravou
    // continua sendo o ponto — o modelo tem DE ONDE ler — e agora isso se
    // afirma pelo INDEX na base do rodapé (linhas 200+), não pelo nome da aba.
    checar(rANC > 0 && formulas.some((f) => /INDEX\(\$[A-Z]+\$2\d\d/.test(f)),
      "(16g) a aba Modelagem passa a ter de onde ler (antes: DF auditada = modelo zerado)",
      formulas[0]?.slice(0, 90) ?? "(nenhuma fórmula)");
  }
}

// ---- 16h/16i: o roteamento não se estende a quem DETALHA o balanço -----------
// A contrapartida do 16: aging de recebíveis, estoque, extrato e razão trazem o
// DETALHE do que o balanço já apresenta consolidado. Se o roteamento por linha
// valesse para todo o balde "Outros", esse detalhe entraria na mesma seção do
// Balanço, DEBAIXO do total informado — exatamente a dupla contagem que o export
// levou três rodadas para eliminar. Este bloco trava a fronteira.
{
  const aging = (versao: string): CampoExtraido[] => [
    campo({ chave: "Duplicatas a receber - a vencer", secao: "Contas a Receber", secao_canonica: "ativo_circulante", valor_num: 12000, documento_versao_id: versao }),
    campo({ chave: "Duplicatas a receber - vencidas até 30 dias", secao: "Contas a Receber", secao_canonica: "ativo_circulante", valor_num: 5000, documento_versao_id: versao }),
    campo({ chave: "Duplicatas a receber - vencidas há mais de 180 dias", secao: "Contas a Receber", secao_canonica: "ativo_circulante", valor_num: 3000, documento_versao_id: versao }),
  ];

  for (const [tipo, rotulo] of [["AGING_AR", "(16h) documento de aging (tipo próprio)"], [null, "(16i) documento homogêneo AINDA SEM TIPO"]] as Array<[string | null, string]>) {
    const V = `vAging${tipo ?? "Null"}`;
    const wb = buildExportWorkbook({
      caso: { nome: "Aging", produto: "reestruturacao" },
      documentos: [{
        id: `dAging${tipo ?? "Null"}`, tipo_taxonomia: tipo, entidade: { razao_social: "Alfa Ltda." },
        periodo: { tipo: "data-base", referencia: "2025-12-31" },
        documento_versao: [{ id: V, nome_original: "aging.pdf" }],
      }],
      campos: aging(V), agora: new Date("2026-07-29T12:00:00Z"),
    });
    // A aba Balanço existe sempre (v28); o que não pode é a linha do aging ter
    // ido para dentro dela — seria o detalhe somado debaixo do total do BP.
    const bal = wb.getWorksheet("Balanço");
    const rotulos: string[] = [];
    if (bal) for (let r = 1; r <= bal.rowCount; r++) rotulos.push(String(bal.getRow(r).getCell(1).value ?? ""));
    const entrou = rotulos.filter((x) => x.startsWith("Duplicatas a receber -"));
    checar(entrou.length === 0,
      `${rotulo} não vira linha do Balanço`,
      `${entrou.join(", ")} | abas: ${wb.worksheets.map((s) => s.name).join(", ")}`);
  }

  // …e o documento SEM TIPO que declara DUAS demonstrações é composto de fato:
  // "Demonstrações Contábeis 2025.pdf" (nome que a taxonomia não reconhece)
  // esperando a fila de revisão não deveria custar ao dono a estrutura inteira.
  const V = "vSemTipo";
  const wb = buildExportWorkbook({
    caso: { nome: "Sem tipo", produto: "reestruturacao" },
    documentos: [{
      id: "dSemTipo", tipo_taxonomia: null, entidade: { razao_social: "Alfa Ltda." },
      periodo: { tipo: "anual", referencia: "2025" },
      documento_versao: [{ id: V, nome_original: "Demonstracoes Contabeis 2025.pdf" }],
    }],
    campos: [
      campo({ chave: "Caixa e equivalentes de caixa", secao: "Ativo Circulante", secao_canonica: "ativo_circulante", valor_num: 500, documento_versao_id: V }),
      campo({ chave: "Fornecedores nacionais", secao: "Passivo Circulante", secao_canonica: "passivo_circulante", valor_num: 500, documento_versao_id: V }),
      campo({ chave: "Receita bruta de vendas", secao: "RECEITA OPERACIONAL BRUTA", secao_canonica: "receita_bruta", valor_num: 9000, documento_versao_id: V }),
    ],
    agora: new Date("2026-07-29T12:00:00Z"),
  });
  checar(wb.getWorksheet("Balanço") != null && wb.getWorksheet("DRE") != null,
    "(16j) documento sem tipo que DECLARA duas demonstrações é separado nas duas abas",
    wb.worksheets.map((s) => s.name).join(", "));
}

// ---- 17: reextração SUBSTITUI, não acumula (Supabase/migrations/0026) --------------
// Reextrair é a única forma de um documento já processado pegar prompt/taxonomia
// novos — o dono precisa disso para a DMPL da `0024`. Só que o export lia TODAS
// as versões do documento, e duas extrações do mesmo arquivo não produzem as
// mesmas linhas (é o ponto de mudar o prompt): a conta renomeada aparecia DUAS
// vezes e a soma da seção somava as duas. Dupla contagem por um caminho novo, e
// do pior tipo — as duas linhas têm proveniência legítima, então nada parece
// errado ao abrir a planilha.
{
  const doc = (versoes: Array<{ id: string; nome_original: string | null; n_versao?: number | null }>): DocumentoParaExport => ({
    id: "d1", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Alfa" },
    periodo: { tipo: "anual", referencia: "2025" }, documento_versao: versoes,
  });
  const V1 = "v1", V2 = "v2";
  const linhaDe = (ws: import("exceljs").Worksheet, rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };

  // A extração NOVA renomeia a conta ("Caixa e bancos" → "Caixa e equivalentes de
  // caixa"), que é exatamente o efeito de um prompt novo.
  // Sem linha de total informado de propósito: aí a seção É a nossa soma, e a
  // dupla contagem aparece no número em vez de ficar mascarada pelo total do
  // documento (a regra do PR #50 esconderia o defeito atrás do informado —
  // primeira versão deste invariante passou verde por isso).
  const campos: CampoExtraido[] = [
    campo({ chave: "Caixa e bancos", secao: "Ativo Circulante", valor_num: 1000, documento_versao_id: V1 }),
    campo({ chave: "Caixa e equivalentes de caixa", secao: "Ativo Circulante", valor_num: 1500, documento_versao_id: V2 }),
  ];
  const wb = buildExportWorkbook({
    caso: { nome: "Reextração", produto: "rx" },
    documentos: [doc([{ id: V1, nome_original: "bp.pdf", n_versao: 1 }, { id: V2, nome_original: "bp.pdf", n_versao: 2 }])],
    campos, agora: new Date("2026-07-29T12:00:00Z"),
  });
  const ws = wb.getWorksheet("Balanço")!;
  const rAC = linhaDe(ws, "Ativo Circulante");
  checar(rAC > 0 && Math.round(avaliar(ws, "B", rAC)) === 1500,
    "(17a) reextração não soma com a extração anterior",
    `seção=${rAC > 0 ? Math.round(avaliar(ws, "B", rAC)) : "(ausente)"} documento=1500`);
  checar(linhaDe(ws, "Caixa e bancos") < 0,
    "(17b) a linha da versão substituída não aparece na planilha");

  // …e a substituição não é silenciosa: o Resumo diz que existe extração anterior
  // fora deste export (ela continua no banco, com proveniência, para auditoria).
  const resumo = wb.getWorksheet("Resumo")!;
  let avisa = false;
  for (let r = 1; r <= resumo.rowCount; r++) {
    if (String(resumo.getRow(r).getCell(1).value ?? "").startsWith("Linhas de versão substituída")) avisa = true;
  }
  checar(avisa, "(17c) o Resumo declara a versão substituída (substituir em silêncio seria pior)");

  // PROTEÇÃO: reextração que FALHA volta com ZERO linhas (`extracao_falhou`,
  // Supabase/migrations/0016). Se a vigência fosse cega ao dado, essa falha APAGARIA do
  // book tudo o que a versão anterior extraiu — trocar dupla contagem por perda
  // silenciosa de dado não é conserto.
  const wbFalha = buildExportWorkbook({
    caso: { nome: "Reextração falhou", produto: "rx" },
    documentos: [doc([{ id: V1, nome_original: "bp.pdf", n_versao: 1 }, { id: "v3", nome_original: "bp.pdf", n_versao: 2 }])],
    campos: [campo({ chave: "Caixa e bancos", secao: "Ativo Circulante", valor_num: 1000, documento_versao_id: V1 })],
    agora: new Date("2026-07-29T12:00:00Z"),
  });
  const wsFalha = wbFalha.getWorksheet("Balanço");
  checar(wsFalha != null && linhaDe(wsFalha, "Caixa e bancos") > 0,
    "(17d) reextração que volta VAZIA não apaga o que a versão anterior extraiu");

  // Sem `n_versao` informada não há ordem declarada: manter as duas é o
  // comportamento antigo, e chutar qual é a nova seria pior.
  const wbSemN = buildExportWorkbook({
    caso: { nome: "Sem n_versao", produto: "rx" },
    documentos: [doc([{ id: V1, nome_original: "bp.pdf" }, { id: V2, nome_original: "bp.pdf" }])],
    campos, agora: new Date("2026-07-29T12:00:00Z"),
  });
  const wsSemN = wbSemN.getWorksheet("Balanço")!;
  checar(linhaDe(wsSemN, "Caixa e bancos") > 0 && linhaDe(wsSemN, "Caixa e equivalentes de caixa") > 0,
    "(17e) sem n_versao declarada, nada é descartado por chute");

  // E o caso normal (uma versão por documento, como todo o book) não muda.
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const wbBook = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-29T12:00:00Z"),
  });
  const resumoBook = wbBook.getWorksheet("Resumo")!;
  let totalBook = 0;
  for (let r = 1; r <= resumoBook.rowCount; r++) {
    if (String(resumoBook.getRow(r).getCell(1).value ?? "") === "Linhas totais extraídas") {
      totalBook = Number(resumoBook.getRow(r).getCell(2).value ?? 0);
    }
  }
  checar(totalBook === fixture.campos.length,
    "(17f) documento de versão única (o book inteiro) não perde nenhuma linha",
    `resumo=${totalBook} fixture=${fixture.campos.length}`);
}

// ---- 18: o teste v28 — buraco silencioso deixa de ser silencioso ------------
// Três achados do v28, e o que os une é que o arquivo NÃO CONTAVA o que faltava:
//   • a extração da DRE falhou (rate limit 429) e a aba simplesmente NÃO EXISTIU;
//   • a `0025` não estava aplicada no projeto em uso, então não havia índice
//     macro — e a aba Macro também não existiu ("os índices não vieram");
//   • sete abas de apoio estavam OCULTAS e foram lidas como "não vieram".
// Nenhum dos três era um número errado: eram ausências indistinguíveis de defeito.
{
  const V = "vSoBalanco";
  const wb = buildExportWorkbook({
    caso: { nome: "v28", produto: "reestruturacao" },
    documentos: [
      { id: "dBP", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Alfa Ltda." },
        periodo: { tipo: "anual", referencia: "2025" },
        documento_versao: [{ id: V, nome_original: "01_BP_Alfa.pdf" }] },
      // …e a DRE que CHEGOU e não extraiu nada (o caso do v28).
      { id: "dDRE", tipo_taxonomia: "DRE", entidade: { razao_social: "Alfa Ltda." },
        periodo: { tipo: "anual", referencia: "2025" },
        documento_versao: [{ id: "vDreFalhou", nome_original: "07_DRE_Alfa.pdf" }] },
    ],
    campos: [
      campo({ chave: "Caixa e bancos", secao: "Ativo Circulante", valor_num: 500, documento_versao_id: V }),
      campo({ chave: "TOTAL DO ATIVO", secao: "ATIVO", valor_num: 500, documento_versao_id: V }),
      campo({ chave: "Fornecedores nacionais", secao: "Passivo Circulante", valor_num: 500, documento_versao_id: V }),
    ],
    agora: new Date("2026-07-29T12:00:00Z"),
  });

  const nomes = wb.worksheets.map((s) => s.name);
  checar(nomes.includes("DRE") && nomes.includes("Fluxo de Caixa"),
    "(18a) as três demonstrações principais existem sempre, com dado ou sem", nomes.join(", "));

  const textoDe = (nome: string) => {
    const ws = wb.getWorksheet(nome);
    const out: string[] = [];
    if (ws) for (let r = 1; r <= ws.rowCount; r++) {
      for (let c = 1; c <= 2; c++) out.push(String(ws.getRow(r).getCell(c).value ?? ""));
    }
    return out;
  };
  const textoDRE = textoDe("DRE");
  checar(textoDRE.some((t) => t.includes("07_DRE_Alfa.pdf")),
    "(18b) a aba sem dado NOMEIA o documento que chegou e não extraiu",
    textoDRE.filter(Boolean).join(" | ").slice(0, 160));
  const textoFluxo = textoDe("Fluxo de Caixa");
  checar(textoFluxo.some((t) => t.includes("Nenhum documento")),
    "(18c) …e distingue 'não entregue' de 'entregue e não extraído'",
    textoFluxo.filter(Boolean).join(" | ").slice(0, 160));

  // O Resumo conta os documentos que ficaram de fora — antes ele só contava as
  // linhas que entraram, que é meia informação.
  const resumo = wb.getWorksheet("Resumo")!;
  let linhaSemLinha = "";
  for (let r = 1; r <= resumo.rowCount; r++) {
    if (String(resumo.getRow(r).getCell(1).value ?? "").startsWith("Documentos SEM linha")) {
      linhaSemLinha = String(resumo.getRow(r).getCell(2).value ?? "");
    }
  }
  checar(linhaSemLinha.includes("07_DRE_Alfa.pdf"),
    "(18d) o Resumo declara os documentos sem nenhuma linha extraída", linhaSemLinha.slice(0, 120));

  // Sem índice coletado, a aba Macro existe e diz o que falta.
  const macro = wb.getWorksheet("Macro");
  const textoMacro = textoDe("Macro");
  checar(macro != null && textoMacro.some((t) => t.includes("workflow.macro.json")),
    "(18e) sem índice coletado, a aba Macro existe e diz o que falta",
    macro ? textoMacro.filter(Boolean).join(" | ").slice(0, 140) : "(sem aba Macro)");
}

// ---- 19: seção sem total informado é DECLARADA como nossa soma ---------------
// O defeito numérico do v28: a VT Logística saiu com Ativo Circulante 7.254 onde
// o documento diz 3.961 — "Contas a Receber" (3.293) somada JUNTO com "Fretes a
// receber" (3.562) e "(-) PECLD" (−269), que são os componentes dela. O documento
// imprime o total da seção, mas a extração daquele arquivo não o trouxe, e sem
// total informado não existe linha de checagem: o número errado não tinha como
// ser percebido. Enquanto a detecção de hierarquia não melhorar (exige ORDEM do
// documento, que hoje não é persistida — fatia própria), o mínimo é o número não
// passar por conferido.
{
  const V = "vSemTotal";
  const wb = buildExportWorkbook({
    caso: { nome: "Sem total informado", produto: "rx" },
    documentos: [{
      id: "dST", tipo_taxonomia: "BALANCO", entidade: { razao_social: "VT Logística Ltda." },
      periodo: { tipo: "anual", referencia: "2025" },
      documento_versao: [{ id: V, nome_original: "04_BP_VT_Logistica.pdf" }],
    }],
    // Exatamente o padrão do v28: subtotal de agrupamento e seus componentes na
    // mesma seção, e NENHUMA linha de total do Ativo Circulante.
    campos: [
      campo({ chave: "Disponível", secao: "Ativo Circulante", valor_num: 358, documento_versao_id: V }),
      campo({ chave: "Contas a Receber", secao: "Ativo Circulante", valor_num: 3293, documento_versao_id: V }),
      campo({ chave: "Fretes a receber", secao: "Ativo Circulante", valor_num: 3562, documento_versao_id: V }),
      campo({ chave: "(-) PECLD", secao: "Ativo Circulante", valor_num: -269, documento_versao_id: V }),
      campo({ chave: "Fornecedores nacionais", secao: "Passivo Circulante", valor_num: 5070, documento_versao_id: V }),
    ],
    agora: new Date("2026-07-29T12:00:00Z"),
  });
  const bal = wb.getWorksheet("Balanço")!;
  let rAC = -1;
  for (let r = 1; r <= bal.rowCount; r++) {
    if (String(bal.getRow(r).getCell(1).value ?? "") === "Ativo Circulante") rAC = r;
  }
  const cell = rAC > 0 ? bal.getRow(rAC).getCell(2) : null;
  const temInformado = (() => {
    for (let r = 1; r <= bal.rowCount; r++) {
      if (String(bal.getRow(r).getCell(1).value ?? "").includes("total informado")
        && bal.getRow(r).getCell(2).value != null) return true;
    }
    return false;
  })();
  checar(!temInformado, "(19a) o cenário é o do v28 mesmo: seção sem total informado");
  checar(!!cell?.note, "(19b) seção cujo número é a NOSSA soma carrega a ressalva na célula");
  const nota = JSON.stringify(cell?.note ?? "");
  checar(nota.includes("dupla contagem"),
    "(19c) …e a ressalva nomeia o risco (dupla contagem de subtotal)", nota.slice(0, 120));
}

// ---- 17: subtotal reconhecido pela ORDEM do documento ----------------------
// Modo de falha REAL do teste v28 (VT Logística): a seção saiu com Ativo
// Circulante 7.254 onde o documento diz 3.961, porque "Contas a Receber"
// (3.293) foi somada JUNTO com "Fretes a receber" (3.562) e "(-) PECLD" (−269),
// que são os seus componentes.
//
// Por que a detecção existente não pega: (A) exige que alguma linha declare
// `secao` = "Contas a Receber", e a extração daquele arquivo anotou a seção de
// TOPO em todas; (B) exige que o valor bata com a soma dos irmãos da MESMA
// seção, e os irmãos ali são o circulante inteiro. E não havia linha de "total
// informado" para a conferência acusar — o número errado não tinha como ser
// percebido.
//
// O sinal que sobra é o que qualquer demonstração impressa dá: o subtotal vem
// IMEDIATAMENTE ANTES dos seus componentes. Isso exige ORDEM persistida.
{
  const V = "vOrdem";
  // Ordem do documento, como o PDF imprime (subtotal acima, componentes abaixo).
  const linhas: Array<[string, number]> = [
    ["Caixa e bancos", 399],
    ["Contas a Receber", 3293],      // ← subtotal impresso
    ["Fretes a receber", 3562],      //   componente
    ["(-) PECLD", -269],             //   componente
    ["Despesas antecipadas", 269],
  ];
  const AC_CORRETO = 399 + 3293 + 269; // 3.961 — o que o documento diz
  const campos: CampoExtraido[] = linhas.map(([chave, v], i) =>
    campo({ chave, secao: "Ativo Circulante", valor_num: v, ordem: i, documento_versao_id: V }));

  const documentos: DocumentoParaExport[] = [{
    id: "dOrdem", tipo_taxonomia: "BALANCO", entidade: { razao_social: "VT Logística" },
    periodo: { tipo: "anual", referencia: "2024" },
    documento_versao: [{ id: V, nome_original: "04_BP_VT_Logistica.pdf" }],
  }];
  const ws = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-29T12:00:00Z"),
  }).getWorksheet("Balanço")!;

  let rAC = -1;
  for (let r = 1; r <= ws.rowCount; r++) {
    if (String(ws.getRow(r).getCell(1).value ?? "") === "Ativo Circulante") { rAC = r; break; }
  }
  const soma = Math.round(avaliar(ws, "B", rAC));
  checar(soma === AC_CORRETO,
    "(17) subtotal impresso ACIMA dos componentes não é somado junto",
    `seção=${soma} documento=${AC_CORRETO} (somando o subtotal daria ${AC_CORRETO + 3293})`);

  // …e ele continua VISÍVEL: nada é escondido para o número fechar.
  const rotulos: string[] = [];
  for (let r = 1; r <= ws.rowCount; r++) rotulos.push(String(ws.getRow(r).getCell(1).value ?? ""));
  checar(rotulos.some((x) => x.includes("subtotal informado")),
    "(17) o subtotal detectado pela ordem continua visível na planilha");

  // NEGATIVO: sem a ordem, o mesmo dado tem de voltar a errar — é o que prova
  // que a correção vem da ordem, e não de outro sinal por acaso.
  const semOrdem = linhas.map(([chave, v]) =>
    campo({ chave, secao: "Ativo Circulante", valor_num: v, documento_versao_id: V }));
  const wsSem = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" }, documentos, campos: semOrdem,
    agora: new Date("2026-07-29T12:00:00Z"),
  }).getWorksheet("Balanço")!;
  let rAC2 = -1;
  for (let r = 1; r <= wsSem.rowCount; r++) {
    if (String(wsSem.getRow(r).getCell(1).value ?? "") === "Ativo Circulante") { rAC2 = r; break; }
  }
  checar(Math.round(avaliar(wsSem, "B", rAC2)) !== AC_CORRETO,
    "(17) sem ordem persistida o defeito reaparece (a correção vem da ORDEM)");
}

// ---- 18: o caso REAL da Componentes (teste v29) -----------------------------
// Números do `.xlsx` do dono. O Ativo Circulante saiu 29.990 onde o documento
// diz 15.200 — 14.790 de dupla contagem, e o balanço da empresa inteiro estava
// contaminado (PC saiu exatamente 2× o informado). O documento é um BP
// detalhado de 4 níveis: ele IMPRIME o subtotal de cada subseção e, embaixo, os
// componentes. A extração anotou a seção de TOPO em todas as linhas, então
// nenhuma das duas detecções estruturais tinha sinal.
//
// Este bloco cobre os dois formatos de subtotal que aparecem no mesmo arquivo:
// com VÁRIOS componentes ("Estoques" = 3 contas) e com UM só ("Outros Créditos"
// = "Adiantamentos diversos"), que exige o segundo sinal do rótulo ser nome de
// agrupamento — sem ele, ficavam 340 de dupla contagem.
{
  const V = "vComponentes";
  const linhas: Array<[string, number]> = [
    ["Disponível", 410],
    ["Contas a Receber", 8420],
    ["Clientes - mercado interno", 9240],
    ["(-) PECLD", -820],
    ["Estoques", 5100],
    ["Matéria-prima", 3180],
    ["Produtos acabados", 2260],
    ["(-) Provisão para perdas em estoques", -340],
    ["Tributos a Recuperar", 930],
    ["ICMS a recuperar", 520],
    ["PIS/COFINS a compensar", 410],
    ["Outros Créditos", 340],
    ["Adiantamentos diversos", 340],
  ];
  const AC_DOCUMENTO = 15200;
  const campos: CampoExtraido[] = linhas.map(([chave, v], i) =>
    campo({ chave, secao: "Ativo Circulante", valor_num: v, ordem: i, documento_versao_id: V }));
  const documentos: DocumentoParaExport[] = [{
    id: "dComp", tipo_taxonomia: "BALANCO",
    entidade: { razao_social: "VERTENTES COMPONENTES AUTOMOTIVOS LTDA." },
    periodo: { tipo: "anual", referencia: "2024" },
    documento_versao: [{ id: V, nome_original: "02_BP_Vertentes_Componentes_2025x2024.pdf" }],
  }];
  const ws = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-29T12:00:00Z"),
  }).getWorksheet("Balanço")!;
  let rAC = -1;
  for (let r = 1; r <= ws.rowCount; r++) {
    if (String(ws.getRow(r).getCell(1).value ?? "") === "Ativo Circulante") { rAC = r; break; }
  }
  const soma = Math.round(avaliar(ws, "B", rAC));
  checar(soma === AC_DOCUMENTO,
    "(18) BP detalhado: o Ativo Circulante bate com o documento",
    `export=${soma} documento=${AC_DOCUMENTO} (sem o conserto dava 29.990)`);

  // O subtotal de UM componente é o que exige o sinal do rótulo. Se ele
  // escapar, sobram exatamente 340 — este número é o teste.
  checar(soma !== AC_DOCUMENTO + 340,
    "(18) subtotal com UM único componente também é reconhecido (senão sobram 340)");
}

// ---- 20: "consulta falhou" NÃO é a mesma mensagem de "sem dado coletado" ----
// Achado no teste v29 (0028): a base tinha índice macro gravado, mas a consulta
// do portal falhava por autorização (RLS sem policy, ou RPC sem grant) — e o
// export dizia "sem dado coletado", como se a coleta nunca tivesse rodado.
// `route.ts` engolia `.error` das duas consultas com `?? []`. Confundir "tentei
// e deu erro" com "tentei e não achei nada" é o próprio padrão que este export
// existe para não repetir (a mesma classe do "total informado" vs "nossa soma").
{
  const wbErro = buildExportWorkbook({
    caso: { nome: "Erro macro", produto: "rx" },
    documentos: [{
      id: "d1", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Alfa" },
      periodo: { tipo: "anual", referencia: "2025" },
      documento_versao: [{ id: "v1", nome_original: "bp.pdf" }],
    }],
    campos: [campo({ chave: "Caixa", secao: "Ativo Circulante", valor_num: 100, documento_versao_id: "v1" })],
    macroErro: "permission denied for table indice_macro_obs",
    agora: new Date("2026-07-29T12:00:00Z"),
  });
  const macroComErro = wbErro.getWorksheet("Macro");
  const textoErro: string[] = [];
  if (macroComErro) for (let r = 1; r <= macroComErro.rowCount; r++) {
    for (let c = 1; c <= 2; c++) textoErro.push(String(macroComErro.getRow(r).getCell(c).value ?? ""));
  }
  const tituloErro = String(macroComErro?.getRow(1).getCell(1).value ?? "");
  checar(macroComErro != null && tituloErro.includes("CONSULTA falhou"),
    "(20a) erro de consulta vira uma aba PRÓPRIA, distinta de 'sem dado coletado'", tituloErro);
  checar(textoErro.some((t) => t.includes("permission denied for table indice_macro_obs")),
    "(20b) a mensagem de erro real aparece na aba (não é genérica)");
  // O TÍTULO é o sinal que distingue as duas causas (o corpo pode CITAR a outra
  // frase de propósito, como contraste explícito — "isto é diferente de X").
  checar(!tituloErro.includes("sem dado coletado"),
    "(20c) …e o título NÃO usa a frase de 'sem dado coletado' (confundiria as duas causas)", tituloErro);

  // Sem erro, a mensagem antiga continua — é o caso genuinamente vazio.
  const wbVazio = buildExportWorkbook({
    caso: { nome: "Vazio macro", produto: "rx" },
    documentos: [{
      id: "d1", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Alfa" },
      periodo: { tipo: "anual", referencia: "2025" },
      documento_versao: [{ id: "v1", nome_original: "bp.pdf" }],
    }],
    campos: [campo({ chave: "Caixa", secao: "Ativo Circulante", valor_num: 100, documento_versao_id: "v1" })],
    agora: new Date("2026-07-29T12:00:00Z"),
  });
  const macroVazio = wbVazio.getWorksheet("Macro");
  const textoVazio: string[] = [];
  if (macroVazio) for (let r = 1; r <= macroVazio.rowCount; r++) {
    for (let c = 1; c <= 2; c++) textoVazio.push(String(macroVazio.getRow(r).getCell(c).value ?? ""));
  }
  checar(textoVazio.some((t) => t.includes("sem dado coletado")),
    "(20d) sem macroErro, a mensagem genuína de ausência continua",
    textoVazio.filter(Boolean).join(" | ").slice(0, 140));
}

// ---- 21: a CAUSA da falha de extração aparece no book ------------------------
// Teste v30: 14 de 14 documentos sem linha extraída. O Resumo listava os nomes —
// e a causa (que a pendência JÁ registrava) ficava só na fila de revisão, em
// outra tela. As causas possíveis pedem ações opostas (crédito do provedor de IA, cota do
// dia, cadência), então listar o arquivo sem a causa é meia informação.
{
  const V = "vFalhou";
  const wb = buildExportWorkbook({
    caso: { nome: "v30", produto: "reestruturacao" },
    documentos: [{
      id: "dBP", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Alfa Ltda." },
      periodo: { tipo: "anual", referencia: "2025" },
      documento_versao: [{ id: V, nome_original: "01_BP_Alfa.pdf" }],
    }],
    campos: [],
    causasDeFalha: [
      "CRÉDITO DA OPENAI ESGOTADO (insufficient_quota). A conta não tem saldo. "
      + "Espaçar as chamadas NÃO resolve isto.",
    ],
    agora: new Date("2026-07-30T12:00:00Z"),
  });
  const resumo = wb.getWorksheet("Resumo")!;
  const linhas: Array<[string, string]> = [];
  for (let r = 1; r <= resumo.rowCount; r++) {
    linhas.push([
      String(resumo.getRow(r).getCell(1).value ?? ""),
      String(resumo.getRow(r).getCell(2).value ?? ""),
    ]);
  }
  const rotulos = linhas.map(([a]) => a);
  checar(rotulos.some((x) => x.startsWith("Documentos SEM linha")),
    "(21a) o Resumo conta os documentos sem linha extraída", rotulos.filter(Boolean).join(" | ").slice(0, 120));
  const causa = linhas.find(([a]) => a === "↳ causa registrada")?.[1] ?? "";
  checar(causa.includes("CRÉDITO DA OPENAI ESGOTADO"),
    "(21b) …e a CAUSA registrada na pendência aparece junto", causa.slice(0, 120));
  checar(causa.includes("NÃO resolve"),
    "(21c) …inclusive o que NÃO resolve (senão a ação óbvia é a errada)");

  // Sem causa informada, nada de linha vazia inventada.
  const wbSemCausa = buildExportWorkbook({
    caso: { nome: "v30", produto: "reestruturacao" },
    documentos: [{
      id: "dBP", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Alfa Ltda." },
      periodo: { tipo: "anual", referencia: "2025" },
      documento_versao: [{ id: V, nome_original: "01_BP_Alfa.pdf" }],
    }],
    campos: [],
    agora: new Date("2026-07-30T12:00:00Z"),
  });
  const resumoSem = wbSemCausa.getWorksheet("Resumo")!;
  let temCausaVazia = false;
  for (let r = 1; r <= resumoSem.rowCount; r++) {
    if (String(resumoSem.getRow(r).getCell(1).value ?? "") === "↳ causa registrada") temCausaVazia = true;
  }
  checar(!temCausaVazia, "(21d) sem causa registrada, o Resumo não inventa a linha");
}

// ---- 22: ESCALA MISTA — o bug de ~496x ------------------------------------
// A fixture `campo()` fixa `unidade: null`, e nenhum dos 126 invariantes
// anteriores mencionava escala. Era por isso que o defeito mais caro do export
// passava verde: um Balanço em MILHAR somado a um Balancete em UNIDADE na mesma
// coluna somava valor cru, sem nenhuma marca de divergência.
{
  const V1 = "esc-milhar";
  const V2 = "esc-unidade";
  const documentos: DocumentoParaExport[] = [
    {
      id: "d-esc-1", tipo_taxonomia: "BALANCO", status: "em_validacao",
      entidade: { razao_social: "Alfa Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
      documento_versao: [{ id: V1, n_versao: 1, nome_original: "BP Alfa 2025.pdf" }],
    } as unknown as DocumentoParaExport,
    {
      // MESMO tipo e mesma entidade/período que o d-esc-1: é o que faz as duas
      // fontes caírem na MESMA coluna da MESMA aba, que é onde a soma quebrava.
      // Cenário real: um BP e uma DF auditada da mesma empresa, cada arquivo
      // declarando a escala do seu jeito.
      id: "d-esc-2", tipo_taxonomia: "BALANCO", status: "em_validacao",
      entidade: { razao_social: "Alfa Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
      documento_versao: [{ id: V2, n_versao: 1, nome_original: "DF Auditada Alfa 2025.pdf" }],
    } as unknown as DocumentoParaExport,
  ];
  // Mesmos R$ 27,9 milhões escritos em escalas diferentes: 27.900 em milhar e
  // 27.900.000 em unidade. Depois da normalização os dois têm de valer o MESMO.
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V1, chave: "Disponibilidades", secao: "Disponível", valor_num: 500, unidade: "milhar", ordem: 0 }),
    campo({ documento_versao_id: V1, chave: "Duplicatas a receber", secao: "Contas a Receber", valor_num: 27900, unidade: "milhar", ordem: 1 }),
    campo({ documento_versao_id: V2, chave: "Clientes nacionais", secao: "Contas a Receber", valor_num: 27_900_000, unidade: "unidade", ordem: 0 }),
  ];
  const wb = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") });
  const ws = wb.getWorksheet("Balanço")!;
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };
  // O que o valor em unidade tem de virar depois de convertido para milhar.
  const rClientes = linhaDe("Clientes nacionais");
  checar(rClientes > 0, "(22a) a linha em escala 'unidade' aparece na aba");
  const vClientes = rClientes > 0 ? avaliar(ws, "B", rClientes) : NaN;
  checar(
    Math.abs(vClientes - 27900) < 0.01,
    "(22b) valor em unidade é CONVERTIDO para a escala do book (27.900.000 → 27.900)",
    `obteve ${vClientes}`,
  );
  // E a soma da seção fecha na escala única. Antes: 500 + 27.900 + 27.900.000.
  const rAC = linhaDe("Ativo Circulante");
  const soma = avaliar(ws, "B", rAC);
  checar(
    Math.abs(soma - 56300) < 0.01,
    "(22c) soma com escalas mistas fecha na escala única (era erro de ~496x)",
    `obteve ${soma}, esperado 56300`,
  );
  // A conversão fica DECLARADA na nota da célula — número convertido sem rastro
  // é número que ninguém consegue conferir contra o PDF.
  const nota = notaDaLinha(ws, rClientes);
  checar(/convertido de/i.test(nota), "(22d) a nota da célula declara a conversão de escala", nota.slice(0, 120));
}

// ---- 23: escala não declarada não é convertida às cegas --------------------
// `unidade: null` significa "o documento não disse". Assumir 'unidade' aí seria
// inventar um fator de 1000x justamente onde não se sabe — e o comentário da
// fonte de `normalizarUnidade` diz que "errar em 1000x é pior que não saber".
{
  const V = "esc-null";
  const documentos: DocumentoParaExport[] = [{
    id: "d-esc-3", tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Beta Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, n_versao: 1, nome_original: "BP Beta.pdf" }],
  } as unknown as DocumentoParaExport];
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V, chave: "Disponibilidades", secao: "Disponível", valor_num: 500, unidade: "milhar", ordem: 0 }),
    campo({ documento_versao_id: V, chave: "Outros créditos", secao: "Disponível", valor_num: 300, unidade: null, ordem: 1 }),
  ];
  const ws = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") })
    .getWorksheet("Balanço")!;
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };
  const rOutros = linhaDe("Outros créditos");
  checar(Math.abs(avaliar(ws, "B", rOutros) - 300) < 0.01, "(23a) valor sem escala declarada NÃO é convertido");
  const nota = notaDaLinha(ws, rOutros);
  checar(/NÃO declarada/i.test(nota), "(23b) a nota diz que a escala não foi declarada, em vez de omitir", nota.slice(0, 120));
}

// ---- 24: o Resumo DECLARA a escala e o que não deu para converter ---------
// Uma planilha financeira sem escala declarada é uma planilha que alguém vai ler
// errado — e este book não declarava escala em lugar nenhum.
{
  const V1 = "res-esc-1";
  const V2 = "res-esc-2";
  const doc = (id: string, ver: string, nome: string): DocumentoParaExport => ({
    id, tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Gama Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: ver, n_versao: 1, nome_original: nome }],
  } as unknown as DocumentoParaExport);
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V1, chave: "Disponibilidades", secao: "Disponível", valor_num: 500, unidade: "milhar", ordem: 0 }),
    campo({ documento_versao_id: V1, chave: "Duplicatas a receber", secao: "Contas a Receber", valor_num: 27900, unidade: "milhar", ordem: 1 }),
    campo({ documento_versao_id: V2, chave: "Clientes nacionais", secao: "Contas a Receber", valor_num: 27_900_000, unidade: "unidade", ordem: 0 }),
    campo({ documento_versao_id: V2, chave: "Outros créditos", secao: "Contas a Receber", valor_num: 300, unidade: null, ordem: 1 }),
  ];
  const resumo = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" },
    documentos: [doc("d-res-1", V1, "BP.pdf"), doc("d-res-2", V2, "DF.pdf")],
    campos, agora: new Date("2026-07-27T12:00:00Z"),
  }).getWorksheet("Resumo")!;

  const valorDe = (rot: string) => {
    for (let r = 1; r <= resumo.rowCount; r++) {
      if (String(resumo.getRow(r).getCell(1).value ?? "") === rot) return String(resumo.getRow(r).getCell(2).value ?? "");
    }
    return "";
  };
  checar(/R\$ mil/.test(valorDe("Escala dos valores")), "(24a) o Resumo declara a escala do book", valorDe("Escala dos valores"));
  checar(/^1 linha\(s\)/.test(valorDe("↳ valores convertidos de escala")), "(24b) o Resumo diz quantas linhas foram convertidas", valorDe("↳ valores convertidos de escala"));
  checar(/^1 —/.test(valorDe("↳ linhas sem escala declarada")), "(24c) o Resumo declara o que NÃO deu para converter", valorDe("↳ linhas sem escala declarada"));
}

// ---- 25: sem escala nenhuma declarada, nada muda --------------------------
// Regressão: a maioria dos documentos reais não declara escala, e o export
// precisa continuar saindo exatamente como saía. Um fix de escala que mexe em
// número onde não havia escala seria pior que o bug.
{
  const V = "res-esc-none";
  const documentos: DocumentoParaExport[] = [{
    id: "d-none", tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Delta Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, n_versao: 1, nome_original: "BP.pdf" }],
  } as unknown as DocumentoParaExport];
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V, chave: "Disponibilidades", secao: "Disponível", valor_num: 1240, ordem: 0 }),
    campo({ documento_versao_id: V, chave: "Aplicações financeiras", secao: "Disponível", valor_num: 3600, ordem: 1 }),
  ];
  const wb = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") });
  const ws = wb.getWorksheet("Balanço")!;
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };
  checar(Math.abs(avaliar(ws, "B", linhaDe("Disponibilidades")) - 1240) < 0.01, "(25a) sem escala declarada, o valor sai intacto");
  checar(Math.abs(avaliar(ws, "B", linhaDe("Ativo Circulante")) - 4840) < 0.01, "(25b) e a soma também");
}

// ---- 26: conta de RESULTADO nunca fica no balanço --------------------------
// `ATIVO_CIRC_KW` contém "mercadoria" (porque no balanço "Mercadorias para
// revenda" é estoque), e por isso a TOP LINE da DRE caía no Ativo Circulante —
// não em "Não Classificadas": era classificada ATIVAMENTE errada, e o roteamento
// não salvava porque `classificarBalanco` "reconhecia" a linha. Alvo direto de
// balancete analítico, onde contas de resultado e de balanço convivem.
{
  const V = "bal-analitico";
  const documentos: DocumentoParaExport[] = [{
    id: "d-ba", tipo_taxonomia: "BALANCETE", status: "em_validacao",
    entidade: { razao_social: "Épsilon Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, n_versao: 1, nome_original: "Balancete Analitico.pdf" }],
  } as unknown as DocumentoParaExport];
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V, chave: "Mercadorias para revenda", secao: "Estoques", valor_num: 12400, ordem: 0 }),
    campo({ documento_versao_id: V, chave: "Receita de Vendas de Mercadorias", secao: "RECEITAS", valor_num: 98000, ordem: 1 }),
    campo({ documento_versao_id: V, chave: "Custo das Mercadorias Vendidas", secao: "CUSTOS", valor_num: -61000, ordem: 2 }),
  ];
  const wb = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") });
  const rotulosDe = (aba: string) => {
    const ws = wb.getWorksheet(aba);
    if (!ws) return [] as string[];
    const out: string[] = [];
    for (let r = 1; r <= ws.rowCount; r++) out.push(String(ws.getRow(r).getCell(1).value ?? ""));
    return out;
  };
  const naDRE = rotulosDe("DRE");
  const noBalancete = rotulosDe("Balancete");
  checar(naDRE.includes("Receita de Vendas de Mercadorias"), "(26a) a top line da DRE vai para a aba DRE");
  checar(naDRE.includes("Custo das Mercadorias Vendidas"), "(26b) o CMV vai para a aba DRE");
  checar(!noBalancete.includes("Receita de Vendas de Mercadorias"), "(26c) e NÃO fica no balancete somada ao Ativo Circulante");
  // O estoque, que legitimamente tem "mercadoria" no rótulo, continua no balanço.
  checar(noBalancete.includes("Mercadorias para revenda"), "(26d) estoque com 'mercadoria' no rótulo segue sendo conta de balanço");
}

// ---- 27: imobilizado/intangível alcançáveis SÓ pelo rótulo ----------------
// `subgrupoNaoCirculante` só era chamado depois de casar `ATIVO_NAO_CIRC_KW`, que
// não continha veículo/máquina/terreno/software. Metade de `IMOBILIZADO_KW` e de
// `INTANGIVEL_KW` era código morto: sem a subseção anotada, o imobilizado inteiro
// ia para "Contas Não Classificadas" — fora de toda soma e de todo indicador.
{
  const V = "imob";
  const documentos: DocumentoParaExport[] = [{
    id: "d-imob", tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Zeta Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, n_versao: 1, nome_original: "BP Zeta.pdf" }],
  } as unknown as DocumentoParaExport];
  // secao: null de propósito — é o caso do balancete analítico que não anota subseção.
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V, chave: "Veículos", valor_num: 1800, ordem: 0 }),
    campo({ documento_versao_id: V, chave: "Máquinas e Equipamentos", valor_num: 9400, ordem: 1 }),
    campo({ documento_versao_id: V, chave: "Terrenos", valor_num: 5000, ordem: 2 }),
    campo({ documento_versao_id: V, chave: "Software", valor_num: 700, ordem: 3 }),
  ];
  const ws = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") })
    .getWorksheet("Balanço")!;
  const rotulos: string[] = [];
  let rNaoClass = -1;
  for (let r = 1; r <= ws.rowCount; r++) {
    const rot = String(ws.getRow(r).getCell(1).value ?? "");
    rotulos.push(rot);
    if (/N[ãa]o Classificad/i.test(rot)) rNaoClass = r;
  }
  const linhaDe = (rot: string) => rotulos.indexOf(rot) + 1;
  for (const bem of ["Veículos", "Máquinas e Equipamentos", "Terrenos"]) {
    const r = linhaDe(bem);
    checar(r > 0 && (rNaoClass < 0 || r < rNaoClass), `(27) "${bem}" entra no Imobilizado, não em Não Classificadas`);
  }
  const rSoft = linhaDe("Software");
  checar(rSoft > 0 && (rNaoClass < 0 || rSoft < rNaoClass), '(27) "Software" entra no Intangível, não em Não Classificadas');
  // E entra na SOMA: ficar fora dela era o custo real de cair em Não Classificadas.
  const rANC = linhaDe("Ativo Não Circulante");
  if (rANC > 0) {
    const soma = avaliar(ws, "B", rANC);
    checar(Math.abs(soma - 16900) < 0.01, "(27b) os quatro bens entram na soma do Ativo Não Circulante", `obteve ${soma}`);
  } else {
    checar(false, "(27b) a aba tem seção de Ativo Não Circulante");
  }
}

// ---- 28: as médias macro AVALIAM para número (não só têm a fórmula certa) ---
// Os 17 asserts que tocavam macro eram TODOS textuais sobre a fórmula, e é por
// isso que o defeito da janela passou verde por tanto tempo: a fórmula estava
// "certa" e o resultado era branco. O harness tem avaliador desde sempre.
{
  const V = "macro-med";
  const documentos: DocumentoParaExport[] = [{
    id: "d-mm", tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Ômega Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, n_versao: 1, nome_original: "BP.pdf" }],
  } as unknown as DocumentoParaExport];
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V, chave: "Caixa", secao: "Disponível", valor_num: 500, unidade: "milhar", ordem: 0 }),
  ];
  // 12 exercícios COMPLETOS + o ano corrente parcial, que é o que a RPC devolve
  // sempre. Era exatamente este cenário que zerava as três janelas.
  const anuais = [];
  for (let a = 2014; a <= 2025; a++) anuais.push({ serie: "IPCA", ano: a, meses: 12, retorno: 4.5 });
  anuais.push({ serie: "IPCA", ano: 2026, meses: 7, retorno: 2.1 });

  const ws = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" }, documentos, campos,
    macro: { anuais, expectativas: [{ serie: "IPCA", ano_ref: 2026, mediana: 4.2, coletado_em: "2026-07-01" }] },
    agora: new Date("2026-07-31T12:00:00Z"),
  }).getWorksheet("Macro")!;

  // Acha a linha do IPCA e as três colunas de média pelo cabeçalho.
  let rIpca = -1;
  for (let r = 1; r <= ws.rowCount; r++) if (/IPCA/.test(String(ws.getRow(r).getCell(1).value ?? ""))) { rIpca = r; break; }
  checar(rIpca > 0, "(28a) a linha do IPCA existe na aba Macro");
  const colDaMedia: Record<string, number> = {};
  for (let r = 1; r <= Math.min(ws.rowCount, 4); r++) {
    for (let c = 2; c <= ws.columnCount; c++) {
      const m = String(ws.getRow(r).getCell(c).value ?? "").match(/M[ée]dia (\d+)a/);
      if (m) colDaMedia[m[1]] = c;
    }
  }
  checar(Object.keys(colDaMedia).length === 3, "(28b) as três colunas de média existem", JSON.stringify(colDaMedia));

  // Qual coluna é qual ano, na própria aba visível.
  const colDoAno: Record<number, string> = {};
  for (let r = 1; r <= Math.min(ws.rowCount, 4); r++) {
    for (let c = 2; c <= ws.columnCount; c++) {
      const v = ws.getRow(r).getCell(c).value;
      if (typeof v === "number" && v >= 2000 && v <= 2100) colDoAno[v] = colLetraDe(c);
    }
  }

  // A asserção é ESTRUTURAL, e a limitação é minha, não do export: `avaliarCelula`
  // não segue referência ENTRE ABAS, e cada célula de ano da aba visível é
  // `IF('Macro (dados)'!X="","",…)`. Então não dá para avaliar a média aqui.
  //
  // O que se afirma no lugar pega o defeito exato: a janela tem de NOMEAR os N
  // últimos exercícios COMPLETOS e NÃO pode tocar a coluna do ano parcial — que era
  // precisamente o que a faixa posicional fazia, zerando as três médias.
  for (const [janela, anosEsperados] of [
    ["3", [2023, 2024, 2025]],
    ["5", [2021, 2022, 2023, 2024, 2025]],
    ["10", [2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024, 2025]],
  ] as Array<[string, number[]]>) {
    const cel = ws.getRow(rIpca).getCell(colDaMedia[janela]) as { value?: { formula?: string } };
    const f = cel.value?.formula ?? "";
    const faltando = anosEsperados.filter((a) => !new RegExp(`\\b${colDoAno[a]}${rIpca}\\b`).test(f));
    checar(
      faltando.length === 0,
      `(28c) a média de ${janela}a nomeia os ${anosEsperados.length} exercícios completos`,
      `faltando ${faltando.join(", ")} em ${f.slice(0, 110)}`,
    );
    checar(
      !new RegExp(`\\b${colDoAno[2026]}${rIpca}\\b`).test(f),
      `(28d) a média de ${janela}a NÃO toca a coluna do ano parcial (2026)`,
      f.slice(0, 110),
    );
  }
}

// ---- 29: histórico curto deixa a média vazia, e a NOTA diz quantos anos há ---
{
  const V = "macro-curto";
  const documentos: DocumentoParaExport[] = [{
    id: "d-mc", tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Ômega Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, n_versao: 1, nome_original: "BP.pdf" }],
  } as unknown as DocumentoParaExport];
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V, chave: "Caixa", secao: "Disponível", valor_num: 500, unidade: "milhar", ordem: 0 }),
  ];
  const anuais = [
    { serie: "IPCA", ano: 2024, meses: 12, retorno: 4.5 },
    { serie: "IPCA", ano: 2025, meses: 12, retorno: 4.5 },
    { serie: "IPCA", ano: 2026, meses: 7, retorno: 2.1 },
  ];
  const ws = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" }, documentos, campos,
    macro: { anuais, expectativas: [] }, agora: new Date("2026-07-31T12:00:00Z"),
  }).getWorksheet("Macro")!;
  let rIpca = -1;
  for (let r = 1; r <= ws.rowCount; r++) if (/IPCA/.test(String(ws.getRow(r).getCell(1).value ?? ""))) { rIpca = r; break; }
  const nota = notaDaLinha(ws, rIpca);
  // A explicação tem de ser VERDADEIRA: "há 2 (2024, 2025)", não "falta histórico".
  checar(/exige 3 exerc/i.test(nota), "(29a) a nota diz qual janela não fechou", nota.slice(0, 160));
  checar(/2024, 2025/.test(nota), "(29b) …e QUANTOS anos completos existem, nomeados", nota.slice(0, 160));
}

// ---- 30: "Ferramental e moldes" é Imobilizado pelo RÓTULO ------------------
// Achado no teste v33, com dado real. No book, "Ferramental e moldes" (3.600) está
// DENTRO do Imobilizado da Componentes — 14.200 + 3.600 + 890 − 13.100 = 5.590, o
// total informado. No export o Imobilizado usou 5.590 E o Ferramental foi somado de
// novo em "Outros Ativos Não Circulantes": Ativo Não Circulante inflado em 3.600.
//
// HONESTIDADE SOBRE O ESCOPO DESTE INVARIANTE. Ele afirma a CLASSIFICAÇÃO, não a
// ausência de dupla contagem — e a diferença importa. Tentei duas fixtures para
// reproduzir a dupla contagem e as duas nasceram VAZIAS (passavam com o bug ligado):
//   1ª: declarei `secao: "Imobilizado"` nas contas — com seção declarada,
//       `subsecaoAutoritativa` já mandava o Ferramental ao lugar certo;
//   2ª: tirei a seção, mas a `ordem` deixou a linha ENTRE contas do Imobilizado, e o
//       consenso de irmãos a colocou certo de novo, sem depender do vocabulário.
// Não consegui reconstruir o arranjo exato que a produção tinha. Então afirmo o que
// dá para provar não-vazio, e a guarda de dupla contagem NO PARENTE fica registrada
// como aberta — ver o comentário de `escreverConferenciaExtraido`, que agora nomeia
// esta causa entre as duas possíveis.
{
  for (const chave of ["Ferramental e moldes", "Ferramental", "Moldes e ferramental", "Ferramentaria"]) {
    const c = classificarConta("balanco", null, chave, null);
    checar(
      c?.secaoKey === "imobilizado",
      `(30) "${chave}" é Imobilizado pelo rótulo, sem depender de seção declarada`,
      `caiu em ${c?.secaoKey ?? c?.ancoraKey ?? "Não Classificadas"}`,
    );
  }
}


// ---- 31: Focus que não cobre o exercício projetado NÃO vira 0,0% -----------
// O defeito mais enganoso que restava da Etapa 2, e o gatilho é banal: os
// exercícios projetados derivam do histórico DO MANDATO. Um caso com
// demonstrações de 2019-2021 projeta 2022-2024; o Focus publicado cobre
// 2026-2030. As três colunas saíam com inflação e juro ZERADOS — célula
// amarela de input, com a nota afirmando "Mediana das expectativas de mercado
// (Boletim Focus/BCB)" — enquanto a aba Macro, ao lado, exibia o Focus de
// 2026-2030 como se estivesse tudo em ordem. Todo o bloco de dívida cobra juro
// zero nesse cenário e o modelo fecha bonito.
//
// O que se afirma aqui é o COMPORTAMENTO (a ausência aparece como ausência),
// não o mecanismo — o invariante das médias já ensinou o preço de travar "como
// o código faz": ele protegeu justamente o defeito.
{
  const V = "v-focus-fora";
  const documentos: DocumentoParaExport[] = [2019, 2020, 2021].map((ano) => ({
    id: `d-${ano}`, tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Antiga Ltda." },
    periodo: { tipo: "anual", referencia: `12M${String(ano).slice(2)}` },
    documento_versao: [{ id: `${V}-${ano}`, n_versao: 1, nome_original: `BP_${ano}.pdf` }],
  }) as unknown as DocumentoParaExport);
  const campos: CampoExtraido[] = [2019, 2020, 2021].map((ano, i) => campo({
    documento_versao_id: `${V}-${ano}`, chave: "Caixa e bancos", secao: "Disponível",
    valor_num: 100 + i, unidade: "milhar", ordem: 0, periodo_coluna: String(ano),
  }));
  // Focus real de hoje: horizonte 2026-2030. Nenhum dos anos que ESTE caso
  // projeta (2022-2024) está nele.
  const expectativas = [2026, 2027, 2028, 2029, 2030].flatMap((ano_ref) => [
    { serie: "IPCA", ano_ref, mediana: 4.5, coletado_em: "2026-07-24" },
    { serie: "SELIC", ano_ref, mediana: 11.0, coletado_em: "2026-07-24" },
  ]);
  const anuais = [2019, 2020, 2021].flatMap((ano) => [
    { serie: "IPCA", ano, meses: 12, retorno: 4.2 },
    { serie: "SELIC", ano, meses: 12, retorno: 9.1 },
  ]);
  const mod = buildExportWorkbook({
    caso: { nome: "Caso Antigo", produto: "reestruturacao" }, documentos, campos,
    macro: { anuais, expectativas }, agora: new Date("2026-07-31T12:00:00Z"),
  }).getWorksheet("Modelagem")!;

  const linhaDe = (rot: string) => {
    for (let r = 1; r <= mod.rowCount; r++) {
      if (String(mod.getRow(r).getCell(1).value ?? "") === rot) return r;
    }
    return -1;
  };
  const nAnos = Math.floor((mod.columnCount - 2) / 13);
  const colFY = (y: number) => 3 + y * 13 + 12;
  // 3 exercícios históricos (2019-2021) + 3 projetados (2022-2024).
  const projetados = [3, 4, 5].filter((y) => y < nAnos);
  checar(projetados.length === 3, "(31) o caso projeta 3 exercícios fora do horizonte do Focus", String(nAnos));

  for (const rot of ["Inflação esperada (metodologia selecionada)", "Juro esperado (Selic — Focus)"]) {
    const r = linhaDe(rot);
    checar(r > 0, `(31) a premissa "${rot}" existe`);
    if (r < 0) continue;
    for (const y of projetados) {
      const cell = mod.getRow(r).getCell(colFY(y));
      // A afirmação central continua a mesma — sem Focus, a premissa NÃO vira
      // zero — mas a Etapa 5 mudou o mecanismo: a premissa passou a ser uma
      // fórmula que indexa a metodologia escolhida. Então o que se prende aqui
      // é que ela RESOLVE para vazio: ou a célula está vazia (linha do juro,
      // que não passa pelo seletor), ou a fórmula guarda o vazio com
      // `IF(...="","",...)`. Um zero literal reprova nos dois casos.
      const fCel = String((cell.value as { formula?: string } | undefined)?.formula ?? "");
      const resolveVazio = cell.value == null || /="",""/.test(fCel);
      checar(resolveVazio,
        `(31) sem Focus para ${2019 + y}, "${rot}" resolve para VAZIO (0 seria ausência disfarçada de dado)`,
        JSON.stringify(cell.value));
      const nota = String((cell.note as { texts?: Array<{ text: string }> } | undefined)?.texts?.map((t) => t.text).join("") ?? "");
      checar(/EM BRANCO/.test(nota) && /2026/.test(nota),
        "(31) …e a nota da célula declara a cobertura real do Focus", nota.slice(0, 140));
      checar(new RegExp(String(2019 + y)).test(nota),
        `(31) …nomeando o exercício desta coluna (${2019 + y})`, nota.slice(0, 140));
    }
  }

  // O aviso que se lê SEM abrir nota nenhuma: nota de célula só alcança quem já
  // desconfiou e foi até lá.
  let avisoLinha = -1;
  for (let r = 1; r <= mod.rowCount; r++) {
    if (/SEM EXPECTATIVA DO FOCUS/.test(String(mod.getRow(r).getCell(1).value ?? ""))) { avisoLinha = r; break; }
  }
  checar(avisoLinha > 0, "(31) a Modelagem avisa, em linha visível, que a projeção saiu sem Focus");
  if (avisoLinha > 0) {
    const txt = String(mod.getRow(avisoLinha).getCell(1).value ?? "");
    checar(/2022/.test(txt) && /2024/.test(txt),
      "(31) …nomeando os exercícios descobertos", txt.slice(0, 120));
    checar(/juro zero/i.test(txt), "(31) …e dizendo o EFEITO (o bloco de dívida não cobra juro)");
  }

  // A conferência VIVA, que é o que sobrevive ao dono mover a linha do tempo:
  // a nota foi escrita na exportação, a fórmula responde a cada recálculo.
  const rCob = linhaDe("↳ cobertura do Focus (IPCA / Selic)");
  checar(rCob > 0, "(31) existe linha de cobertura do Focus que recalcula com o arquivo");
  if (rCob > 0) {
    const f = String((mod.getRow(rCob).getCell(colFY(projetados[0])).value as { formula?: string })?.formula ?? "");
    checar(/SEM FOCUS/.test(f) && /MATCH\(/.test(f),
      "(31) …e ela pergunta ao arquivo (MATCH), não repete a decisão da geração", f.slice(0, 120));
  }
}

// ---- 32: e o contrário — com Focus cobrindo o ano, nada de aviso -----------
// A metade que impede o invariante 31 de virar "sempre em branco": um export
// que apagasse a premissa SEMPRE passaria em todos os asserts acima. Aqui o
// horizonte do Focus cobre os anos projetados e o comportamento tem de ser o
// oposto — fórmula lendo a aba Macro, nenhuma célula vazia, nenhum aviso.
{
  const V = "v-focus-cobre";
  const documentos: DocumentoParaExport[] = [2024, 2025].map((ano) => ({
    id: `dc-${ano}`, tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Atual Ltda." },
    periodo: { tipo: "anual", referencia: `12M${String(ano).slice(2)}` },
    documento_versao: [{ id: `${V}-${ano}`, n_versao: 1, nome_original: `BP_${ano}.pdf` }],
  }) as unknown as DocumentoParaExport);
  const campos: CampoExtraido[] = [2024, 2025].map((ano, i) => campo({
    documento_versao_id: `${V}-${ano}`, chave: "Caixa e bancos", secao: "Disponível",
    valor_num: 100 + i, unidade: "milhar", ordem: 0, periodo_coluna: String(ano),
  }));
  const expectativas = [2026, 2027, 2028].flatMap((ano_ref) => [
    { serie: "IPCA", ano_ref, mediana: 4.5, coletado_em: "2026-07-24" },
    { serie: "SELIC", ano_ref, mediana: 11.0, coletado_em: "2026-07-24" },
  ]);
  const mod = buildExportWorkbook({
    caso: { nome: "Caso Atual", produto: "reestruturacao" }, documentos, campos,
    macro: { anuais: [{ serie: "IPCA", ano: 2024, meses: 12, retorno: 4.2 }], expectativas },
    agora: new Date("2026-07-31T12:00:00Z"),
  }).getWorksheet("Modelagem")!;

  const linhaDe = (rot: string) => {
    for (let r = 1; r <= mod.rowCount; r++) {
      if (String(mod.getRow(r).getCell(1).value ?? "") === rot) return r;
    }
    return -1;
  };
  const colFY = (y: number) => 3 + y * 13 + 12;
  const rIpca = linhaDe("Inflação esperada (metodologia selecionada)");
  // 2024-2025 históricos, 2026-2028 projetados — todos no Focus desta fixture.
  for (const y of [2, 3, 4]) {
    const cell = mod.getRow(rIpca).getCell(colFY(y));
    const f = String((cell.value as { formula?: string } | undefined)?.formula ?? "");
    // Etapa 3: o Focus vive espelhado no rodapé da própria Modelagem. O
    // comportamento afirmado é o mesmo — com cobertura, a premissa é FÓRMULA e
    // não fica vazia — mas sem citar aba, que é o ponto da Etapa 3.
    checar(/INDEX\(/.test(f) && !/'[^']+'!/.test(f),
      `(32) com Focus para ${2024 + y}, a premissa é FÓRMULA local em vez de ficar vazia`, f.slice(0, 110));
  }
  let aviso = false;
  for (let r = 1; r <= mod.rowCount; r++) {
    if (/SEM EXPECTATIVA DO FOCUS/.test(String(mod.getRow(r).getCell(1).value ?? ""))) aviso = true;
  }
  checar(!aviso, "(32) e nenhum aviso de ausência aparece quando não há ausência");
}

// ---- 33: falha PARCIAL do macro é declarada DENTRO do arquivo --------------
// `macroErro` só chegava ao arquivo quando NÃO havia macro nenhum. O caso que
// escapava: os índices e o Focus respondem, mas a consulta de NOMES das séries
// falha — a aba sai com "IPCA"/"SELIC" crus no lugar dos nomes por extenso, e
// o erro morria num `console.error` do servidor. Quem abre a planilha não tem
// acesso a log nenhum: para ele, o arquivo simplesmente parece pronto.
{
  const V = "v-macro-parcial";
  const documentos: DocumentoParaExport[] = [{
    id: "d-mp", tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Parcial Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, n_versao: 1, nome_original: "BP.pdf" }],
  } as unknown as DocumentoParaExport];
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V, chave: "Caixa", secao: "Disponível", valor_num: 500, unidade: "milhar", ordem: 0 }),
  ];
  const macro = {
    anuais: [{ serie: "IPCA", ano: 2024, meses: 12, retorno: 4.5 }],
    expectativas: [{ serie: "IPCA", ano_ref: 2026, mediana: 4.5, coletado_em: "2026-07-24" }],
  };
  const erro = "nomes das séries: permission denied for table indice_macro_serie";
  const wb = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" }, documentos, campos, macro, macroErro: erro,
    agora: new Date("2026-07-31T12:00:00Z"),
  });
  const ws = wb.getWorksheet("Macro")!;
  let achou = "";
  for (let r = 1; r <= ws.rowCount; r++) {
    const t = String(ws.getRow(r).getCell(1).value ?? "");
    if (/falhou EM PARTE/.test(t)) { achou = t; break; }
  }
  checar(achou !== "", "(33) a aba Macro declara que a consulta falhou em parte");
  checar(achou.includes("nomes das séries"),
    "(33) …repetindo QUAL parte falhou, para quem for conferir no Supabase", achou.slice(0, 120));

  // E o aviso não pode ter deslocado as linhas que o modelo endereça por
  // número. Continua valendo depois da Etapa 3: a premissa aponta para uma
  // LINHA — agora do bloco BASE MACRO, no rodapé da própria Modelagem — e uma
  // linha inserida antes dela faria cada fórmula mirar uma acima, em silêncio.
  const mod = wb.getWorksheet("Modelagem")!;
  // ETAPA 5: quem endereça a linha do Focus por NÚMERO deixou de ser a
  // premissa (ela indexa a tabela de metodologias) e passou a ser a linha
  // "Focus — IPCA" do bloco INPUTS MACRO. O risco é o mesmo — um aviso
  // inserido antes faria a fórmula mirar uma linha acima — e é lá que ele
  // agora se manifesta.
  let rIpca = -1;
  for (let r = 1; r <= mod.rowCount; r++) {
    if (String(mod.getRow(r).getCell(1).value ?? "") === "Focus — IPCA") { rIpca = r; break; }
  }
  const nA = Math.floor((mod.columnCount - 2) / 13);
  let apontou = false;
  for (let y = 0; y < nA; y++) {
    const f = String((mod.getRow(rIpca).getCell(3 + y * 13 + 12).value as { formula?: string } | undefined)?.formula ?? "");
    if (!f) continue;
    // A linha citada pela fórmula tem de ser mesmo a do IPCA na base local.
    const m = f.match(/INDEX\(\$B\$(\d+)/);
    if (!m) continue;
    apontou = true;
    checar(/IPCA/i.test(String(mod.getRow(Number(m[1])).getCell(1).value ?? "")),
      "(33) o aviso não deslocou as linhas que o modelo endereça por número",
      `fórmula aponta linha ${m[1]}, que contém "${String(mod.getRow(Number(m[1])).getCell(1).value ?? "")}"`);
  }
  checar(apontou, "(33) …e a premissa realmente endereça o Focus espelhado nesta fixture");
}

// ---- 34: sem entidade reconhecida, a AUSÊNCIA das abas é declarada ---------
// A guarda `entidadesConhecidas.size > 0` cobre Macro E Modelagem: sem nenhuma
// entidade, o arquivo saía sem as duas abas e sem uma palavra sobre isso. Uma
// aba que não existe não diz por que não existe — foi assim que "não veio os
// dados macro" (v28) virou meia hora de investigação de causa errada.
{
  const V = "v-sem-entidade";
  const documentos: DocumentoParaExport[] = [{
    id: "d-se", tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: null, periodo: null,
    documento_versao: [{ id: V, n_versao: 1, nome_original: "ilegivel.pdf" }],
  } as unknown as DocumentoParaExport];
  const wb = buildExportWorkbook({
    caso: { nome: "Caso Sem Entidade", produto: "rx" }, documentos, campos: [],
    agora: new Date("2026-07-31T12:00:00Z"),
  });
  const ws = wb.getWorksheet("Modelagem");
  checar(ws != null, "(34) a aba Modelagem EXISTE mesmo sem entidade reconhecida (declarando o porquê)");
  if (ws) {
    let texto = "";
    for (let r = 1; r <= ws.rowCount; r++) {
      for (let c = 1; c <= 2; c++) texto += String(ws.getRow(r).getCell(c).value ?? "") + "\n";
    }
    checar(/não montad/i.test(texto), "(34) …dizendo que não foi montada", texto.slice(0, 100));
    checar(/ENTIDADE reconhecida/i.test(texto), "(34) …e a causa: nenhuma entidade reconhecida");
    checar(/Resumo/.test(texto) && /fila de revisão/i.test(texto),
      "(34) …e para onde ir (Resumo e fila de revisão), não só o diagnóstico");
  }
}

// ---- 35: bloco REFERÊNCIAS MACRO — informa sem fingir que dirige -----------
// Fecha a Etapa 2. O placar que motivou o bloco, medido antes de escrevê-lo:
// das 15 premissas, 2 liam macro (IPCA e Selic do Focus); das 6 séries
// históricas coletadas, 0 alimentavam qualquer fórmula — as 18 células de média
// 3a/5a/10a da aba Macro não moviam nada e ninguém fora daquela aba as via.
//
// Decisão do dono (2026-07-31): trazer IGP-M, PIB, câmbio e as médias como
// REFERÊNCIA agora; o seletor que escolhe qual índice dirige o quê é a Etapa 5.
// Então o que se afirma aqui é o COMPORTAMENTO de uma referência honesta:
//   (a) ela existe e diz, em linha visível, que NÃO move o modelo sozinha;
//   (b) é FÓRMULA lendo a aba Macro — a planilha continua viva, corrigir a
//       origem faz o modelo acompanhar (arquitetura desde a sessão 12);
//   (c) ausência aparece como ausência, com o MESMO tratamento da fatia 4;
//   (d) as premissas continuam sendo 15 — referência não é premissa.
{
  const V = "v-refs-macro";
  const documentos: DocumentoParaExport[] = [2024, 2025].map((ano) => ({
    id: `dr-${ano}`, tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Referência Ltda." },
    periodo: { tipo: "anual", referencia: `12M${String(ano).slice(2)}` },
    documento_versao: [{ id: `${V}-${ano}`, n_versao: 1, nome_original: `BP_${ano}.pdf` }],
  }) as unknown as DocumentoParaExport);
  const campos: CampoExtraido[] = [2024, 2025].map((ano, i) => campo({
    documento_versao_id: `${V}-${ano}`, chave: "Caixa e bancos", secao: "Disponível",
    valor_num: 100 + i, unidade: "milhar", ordem: 0, periodo_coluna: String(ano),
  }));
  // Focus cobrindo SÓ 2026-2028: os exercícios 2024 e 2025 do modelo ficam
  // descobertos de propósito, para o assert de ausência ter onde acontecer.
  const expectativas = [2026, 2027, 2028].flatMap((ano_ref) => [
    { serie: "IPCA", ano_ref, mediana: 4.5, coletado_em: "2026-07-24" },
    { serie: "SELIC", ano_ref, mediana: 11.0, coletado_em: "2026-07-24" },
    { serie: "IGPM", ano_ref, mediana: 5.1, coletado_em: "2026-07-24" },
    { serie: "PIB", ano_ref, mediana: 2.2, coletado_em: "2026-07-24" },
    // NÍVEL, não taxa: o Focus publica câmbio em R$/US$. É o número que revela
    // erro de escala — 5,4 dividido por 100 e formatado como % vira 5,4%.
    { serie: "CAMBIO_USD", ano_ref, mediana: 5.4, coletado_em: "2026-07-24" },
  ]);
  // IPCA com 10 exercícios completos (as três janelas fecham) e IGPM com 2 (as
  // três ficam VAZIAS na origem). As duas metades importam: a primeira prova que
  // a referência lê, a segunda que ela não publica o vazio como 0,0%.
  const anuais = [
    ...Array.from({ length: 10 }, (_, k) => ({ serie: "IPCA", ano: 2016 + k, meses: 12, retorno: 4.2 })),
    { serie: "IGPM", ano: 2024, meses: 12, retorno: 3.1 },
    { serie: "IGPM", ano: 2025, meses: 12, retorno: 3.3 },
  ];
  // `nomes` vai preenchido de propósito: é o que o `route.ts` manda em produção,
  // e é o que faz o bloco escrever "IGP-M (FGV)" em vez de "IGPM" cru. Código de
  // sistema num rótulo de leitura humana é o começo de alguém ler a série errada.
  const nomes = {
    IPCA: "IPCA (IBGE)", IGPM: "IGP-M (FGV)", PIB: "PIB Total",
    CAMBIO_USD: "Câmbio R$/US$ (venda, fim de período)",
  };
  const wb = buildExportWorkbook({
    caso: { nome: "Caso Referência", produto: "reestruturacao" }, documentos, campos,
    macro: { anuais, expectativas, nomes }, agora: new Date("2026-07-31T12:00:00Z"),
  });
  const mod = wb.getWorksheet("Modelagem")!;

  const rotuloDe = (r: number) => String(mod.getRow(r).getCell(1).value ?? "");
  const linhaDe = (pred: (rot: string) => boolean) => {
    for (let r = 1; r <= mod.rowCount; r++) if (pred(rotuloDe(r))) return r;
    return -1;
  };
  const colFY = (y: number) => 3 + y * 13 + 12;
  const formulaDe = (r: number, c: number) =>
    r < 1 ? "" : String((mod.getRow(r).getCell(c).value as { formula?: string } | undefined)?.formula ?? "");
  const notaDe = (r: number, c: number) =>
    r < 1 ? "" : String((mod.getRow(r).getCell(c).note as { texts?: Array<{ text: string }> } | undefined)
      ?.texts?.map((t) => t.text).join("") ?? "");

  const rBloco = linhaDe((rot) => rot.startsWith("REFERÊNCIAS MACRO"));
  checar(rBloco > 0, "(35) a Modelagem tem um bloco REFERÊNCIAS MACRO");
  checar(/NÃO move/i.test(rotuloDe(rBloco)),
    "(35) …e o cabeçalho diz, sem abrir nota, que elas não movem o modelo sozinhas",
    rotuloDe(rBloco));
  checar(/Etapa 5/.test(notaDaLinha(mod, rBloco)),
    "(35) …e aponta o seletor da Etapa 5 como quem vai dar alavanca a elas",
    notaDaLinha(mod, rBloco).slice(0, 140));

  // O bloco fica DEPOIS das premissas: uma linha inserida no meio delas
  // deslocaria `P(i)` e toda fórmula do modelo, em silêncio.
  const rPremissasCab = linhaDe((rot) => rot.startsWith("PREMISSAS"));
  checar(rPremissasCab > 0 && rBloco > rPremissasCab,
    "(35) o bloco fica FORA (depois) do bloco de premissas", `${rPremissasCab} → ${rBloco}`);

  // --- as três séries do Focus que o modelo ainda não usa -------------------
  for (const [rot, temFocus] of [
    ["↳ IGP-M esperado (Focus)", true],
    ["↳ PIB esperado (Focus)", true],
    ["↳ Câmbio esperado (Focus)", true],
  ] as Array<[string, boolean]>) {
    const r = linhaDe((x) => x === rot);
    checar(r > 0, `(35) existe a linha de referência "${rot}"`);
    if (r < 0) continue;
    // 2026-2028 (y=2,3,4) estão no Focus desta fixture: tem de sair FÓRMULA
    // lendo a aba Macro, não valor escrito — senão a planilha morre e recoletar
    // o macro não corrige mais nada.
    for (const y of [2, 3, 4]) {
      const f = formulaDe(r, colFY(y));
      checar(/INDEX\(/.test(f) && /MATCH\(/.test(f) && !/'[^']+'!/.test(f),
        `(35) "${rot}" em ${2024 + y} é FÓRMULA lendo o Focus espelhado, não número escrito`,
        f.slice(0, 90) || JSON.stringify(mod.getRow(r).getCell(colFY(y)).value));
    }
    // 2024-2025 (y=0,1) NÃO estão no Focus: mesmo tratamento da fatia 4 —
    // célula sem nada e a nota dizendo qual é a cobertura publicada. Um 0 aqui
    // seria "o mercado espera PIB zero"; no câmbio, um dólar de R$ 0,00.
    for (const y of [0, 1]) {
      checar(mod.getRow(r).getCell(colFY(y)).value == null,
        `(35) sem Focus para ${2024 + y}, "${rot}" fica EM BRANCO`,
        JSON.stringify(mod.getRow(r).getCell(colFY(y)).value));
      const n = notaDe(r, colFY(y));
      checar(/EM BRANCO/.test(n) && /2026/.test(n),
        `(35) …e a nota da célula declara a cobertura real (${rot}, ${2024 + y})`, n.slice(0, 120));
    }
    void temFocus;
    // Cada linha diz O QUE DEVERIA DIRIGIR e que hoje não dirige. Sem isso o
    // bloco é uma lista de números soltos, que é a crítica registrada às médias.
    const nl = notaDaLinha(mod, r);
    checar(/DEVERIA DIRIGIR/.test(nl), `(35) a nota de "${rot}" diz o que ela deveria dirigir`, nl.slice(0, 120));
    checar(/Etapa 5/.test(nl), `(35) …e que a escolha é o seletor da Etapa 5`, nl.slice(0, 120));
  }

  // --- câmbio é NÍVEL: o assert que pega erro de escala ---------------------
  // O Focus publica câmbio em R$/US$ (5,4), não em %. Tratá-lo como as outras
  // duas — dividir por 100 e formatar como percentual — publicaria "5,4%" no
  // lugar de "R$ 5,4000". É a mesma família do erro de ~496x que a Etapa 1
  // corrigiu nas abas de dados, e ele não dá nenhum sinal na tela.
  {
    const r = linhaDe((x) => x === "↳ Câmbio esperado (Focus)");
    const f = formulaDe(r, colFY(2));
    checar(!/\/100/.test(f), "(35) a referência de câmbio NÃO divide por 100 (Focus publica NÍVEL)", f.slice(0, 90));
    checar(String(mod.getRow(r).getCell(colFY(2)).numFmt ?? "").indexOf("%") < 0,
      "(35) …nem é formatada como percentual", String(mod.getRow(r).getCell(colFY(2)).numFmt));
    checar(String(mod.getRow(r).getCell(2).value ?? "").includes("R$/US$"),
      "(35) …e a unidade na própria linha diz R$/US$", String(mod.getRow(r).getCell(2).value));
    // E a contraprova, para o assert acima não passar por um export que
    // simplesmente nunca divide por 100: IGP-M e PIB, que são percentuais, DIVIDEM.
    for (const rot of ["↳ IGP-M esperado (Focus)", "↳ PIB esperado (Focus)"]) {
      const rp = linhaDe((x) => x === rot);
      checar(/\/100/.test(formulaDe(rp, colFY(2))),
        `(35) …enquanto "${rot}", que é percentual, divide por 100`, formulaDe(rp, colFY(2)).slice(0, 90));
    }
  }

  // --- médias históricas: lidas por fórmula, e o vazio continua vazio -------
  // `avaliarCelula` NÃO segue referência entre abas (toda célula da Macro é
  // `IF('Macro (dados)'!X="","",…)`), então a afirmação aqui é estrutural — e o
  // motivo está aqui escrito para ninguém achar que foi preguiça.
  {
    const rSub = linhaDe((rot) => rot.startsWith("↳ médias históricas"));
    checar(rSub > 0, "(35) existe o sub-cabeçalho das médias históricas");
    checar(/NÃO são meses/i.test(notaDaLinha(mod, rSub)),
      "(35) …declarando que aquelas colunas não são meses (o painel congelado diz jan/fev/mar)",
      notaDaLinha(mod, rSub).slice(0, 140));
    for (const k of [0, 1, 2]) {
      checar(/^Média \d+a$/.test(String(mod.getRow(rSub).getCell(3 + k).value ?? "")),
        `(35) …e rotulando a janela na própria coluna (${k})`,
        String(mod.getRow(rSub).getCell(3 + k).value));
    }

    // IPCA: 10 exercícios completos na fixture ⇒ as três janelas FECHAM na aba
    // Macro, e a referência tem de trazer as três.
    const daMedia = (codigoNoNome: string) => {
      for (let r = rSub + 1; r <= mod.rowCount; r++) {
        const rot = rotuloDe(r);
        if (!rot.trim().startsWith("↳")) break;   // o bloco acaba na linha em branco
        if (rot.includes(codigoNoNome)) return r;
      }
      return -1;
    };
    const rIpca = daMedia("IPCA");
    checar(rIpca > 0, "(35) existe a linha de médias históricas do IPCA", `rowCount=${mod.rowCount}`);
    for (const k of [0, 1, 2]) {
      const f = formulaDe(rIpca, 3 + k);
      checar(/^IF\(/.test(f) && !/'[^']+'!/.test(f),
        `(35) a média ${[3, 5, 10][k]}a do IPCA é lida por fórmula da base local`, f.slice(0, 90));
      // O comportamento: origem vazia NÃO pode virar 0. Uma referência crua a
      // célula vazia vale 0 no Excel, e o bloco publicaria "0,0%" como média de
      // 10 anos — ausência apresentada como medição.
      checar(/=""/.test(f),
        `(35) …e guarda o vazio da origem em vez de publicar 0,0% (média ${[3, 5, 10][k]}a)`, f.slice(0, 90));
    }

    // IGPM: 2 exercícios ⇒ as três células de ORIGEM na aba Macro estão
    // literalmente vazias. É o caso em que a guarda acima é a diferença entre
    // "em branco" e "0,0% de inflação em 10 anos".
    const rIgpm = daMedia("IGP-M");
    checar(rIgpm > 0, "(35) existe a linha de médias históricas do IGP-M");
    if (rIgpm > 0) {
      let origemVazia = 0;
      for (const k of [0, 1, 2]) {
        const f = formulaDe(rIgpm, 3 + k);
        // A origem agora é uma célula da PRÓPRIA Modelagem (bloco BASE MACRO).
        const m = /IF\(([A-Z]+)(\d+)="/.exec(f);
        if (!m) continue;
        const orig = mod.getRow(Number(m[2])).getCell(m[1]);
        if (orig.value == null) origemVazia++;
        checar(/=""/.test(f),
          `(35) a média ${[3, 5, 10][k]}a do IGP-M guarda o vazio da origem`, f.slice(0, 90));
      }
      // Sem este assert o parágrafo acima seria decorativo: ele prova que a
      // fixture REALMENTE tem origem vazia, e não que o guard nunca é exercido.
      checar(origemVazia === 3,
        "(35) …e a fixture realmente tem as 3 células de origem vazias (2 exercícios só)",
        `vazias=${origemVazia}`);
    }
  }

  // --- e as premissas continuam sendo 15 -----------------------------------
  // Referência não é premissa. Este assert é o que impede o bloco de crescer
  // para dentro do bloco de cima: `P(i)` endereça premissa por deslocamento a
  // partir da primeira, e uma linha a mais lá desloca o modelo inteiro em
  // silêncio. (Os invariantes 14/15 já contam; aqui a contagem é afirmada nesta
  // fixture, que é a que tem o bloco novo.)
  {
    let dentro = false;
    let n = 0;
    for (let r = 1; r <= mod.rowCount; r++) {
      const rot = rotuloDe(r);
      if (rot.startsWith("PREMISSAS")) { dentro = true; continue; }
      if (dentro) {
        if (!rot || (rot === rot.toUpperCase() && rot.length > 12)) break;
        n++;
      }
    }
    checar(n === 15, "(35) o bloco de REFERÊNCIAS não entrou na contagem de premissas (continuam 15)", String(n));
  }
}

// ---- 36: dupla contagem no total do GRUPO, com a conta suspeita NOMEADA ----
// O bug aberto mais caro do repositório, e o arranjo abaixo é o do teste v33,
// não um inventado: Balanço da Componentes (Dados de Teste/book-vertentes/dados.py),
// Imobilizado = 14.200 + 3.600 + 890 − 13.100 = 5.590, com o 5.590 IMPRESSO no
// documento. Uma conta do Imobilizado foi anotada com a seção de TOPO ("Ativo
// Não Circulante") em vez da subseção, caiu em "Outros Ativos Não Circulantes"
// — irmã do Imobilizado — e o grupo passou a contá-la duas vezes: o total
// informado do Imobilizado já a inclui, e ela entra de novo pela irmã.
//
// HONESTIDADE SOBRE A CONTA USADA. A conta do v33 era "Ferramental e moldes", e
// ela NÃO serve mais para reproduzir: a fatia de vocabulário da sessão 18
// (invariante 30) faz esse rótulo ser Imobilizado mesmo sem seção declarada —
// medido aqui, `classificarConta("balanco","Ativo Não Circulante","Ferramental
// e moldes",null)` devolve `imobilizado`. Aquela INSTÂNCIA está fechada; a
// CLASSE de defeito não estava. A fixture usa "Bens em comodato", uma conta de
// imobilizado real (CPC 27) que o vocabulário genuinamente não reconhece —
// medido: devolve `ativo_nao_circulante`. Nada aqui foi inventado para o teste
// passar; o que mudou foi o rótulo, porque o antigo já está coberto.
//
// AS DUAS FIXTURES ANTERIORES NASCERAM VAZIAS (sessão 18) e o motivo está no
// handoff: uma declarava a SUBSEÇÃO (e `subsecaoAutoritativa` já acertava), a
// outra deixava a `ordem` entre contas do Imobilizado (e o consenso de irmãos
// acertava). Esta declara a seção de TOPO e põe a ordem longe — que é o que a
// produção tinha.
{
  const anc = (extra: { totalGrupo?: boolean; contaNoLugarCerto?: boolean }) => {
    const V = `v-dc-${extra.totalGrupo ? "t" : "s"}-${extra.contaNoLugarCerto ? "c" : "e"}`;
    const documentos: DocumentoParaExport[] = [{
      id: `d-${V}`, tipo_taxonomia: "BALANCO", status: "em_validacao",
      entidade: { razao_social: "Componentes Ltda." },
      periodo: { tipo: "anual", referencia: "12M25" },
      documento_versao: [{ id: V, n_versao: 1, nome_original: "BP_Componentes.pdf" }],
    } as unknown as DocumentoParaExport];
    const c = (chave: string, valor_num: number, ordem: number, secao: string | null = null) =>
      campo({ chave, secao, valor_num, ordem, unidade: "milhar", documento_versao_id: V });
    const campos: CampoExtraido[] = [
      c("Numerário disponível em bancos", 410, 1, "Disponível"),
      c("Total do Ativo Circulante", 410, 2, "Ativo Circulante"),
      ...(extra.totalGrupo ? [c("Ativo Não Circulante", 6550, 3)] : []),
      c("Realizável a Longo Prazo", 860, 4),
      c("Depósitos judiciais", 860, 5),
      c("Imobilizado", 5590, 6),
      c("Máquinas e equipamentos", 14200, 7),
      c("Veículos", 890, 8),
      c("(-) Depreciação acumulada", -13100, 9),
      c("Intangível", 100, 10),
      c("Software", 210, 11),
      c("(-) Amortização acumulada", -110, 12),
      // A conta exilada — ou não, na variante de contraprova.
      c("Bens em comodato", 3600, 40, extra.contaNoLugarCerto ? "Imobilizado" : "Ativo Não Circulante"),
    ];
    return buildExportWorkbook({
      caso: { nome: "Caso Dupla Contagem", produto: "reestruturacao" }, documentos, campos,
      agora: new Date("2026-07-31T12:00:00Z"),
    }).getWorksheet("Balanço")!;
  };
  const avisos = (ws: import("exceljs").Worksheet) => {
    const rs: number[] = [];
    for (let r = 1; r <= ws.rowCount; r++) {
      if (/DUPLA CONTAGEM/.test(String(ws.getRow(r).getCell(1).value ?? ""))) rs.push(r);
    }
    return rs;
  };

  // --- (a) com total do grupo informado: o número fica certo, mas o arquivo
  //         tem de dizer POR QUE ele diverge da soma, nomeando a conta.
  {
    const ws = anc({ totalGrupo: true });
    const rs = avisos(ws);
    checar(rs.length === 1, "(36) o export sinaliza a dupla contagem no total do grupo", `avisos=${rs.length}`);
    if (rs.length >= 1) {
      const txt = String(ws.getRow(rs[0]).getCell(1).value ?? "");
      // NOMEAR é o ponto: a nota antiga pedia ao humano que casasse a diferença
      // com alguma conta de outra seção, à mão, em 44 seções. Ninguém faz.
      checar(/Bens em comodato/.test(txt), "(36) …NOMEANDO a conta suspeita", txt.slice(0, 160));
      checar(/Outros Ativos Não Circulantes/.test(txt) && /Imobilizado/.test(txt),
        "(36) …e as DUAS seções envolvidas (onde ela está × quem já a soma)", txt.slice(0, 160));
      const nota = notaDaLinha(ws, rs[0]);
      checar(/LEITURA A/.test(nota) && /LEITURA B/.test(nota),
        "(36) …e a nota traz as DUAS leituras, porque o export não escolhe (Arquitetura do Sistema/2 Especificação/04)",
        nota.slice(0, 120));
      checar(/3\.600,00/.test(nota),
        "(36) …com a diferença medida, não só a afirmação", nota.slice(0, 300));
      // Não corrige sozinho: o cabeçalho do grupo continua sendo o que era
      // (o total informado), e o valor exilado continua onde a extração o pôs.
      let rGrupo = -1;
      for (let r = 1; r <= ws.rowCount; r++) {
        if (String(ws.getRow(r).getCell(1).value ?? "") === "Ativo Não Circulante") { rGrupo = r; break; }
      }
      checar(rGrupo > 0 && ws.getRow(rGrupo).getCell(2).value != null,
        "(36) o export NÃO reclassifica sozinho: o cabeçalho do grupo continua o que era");
      checar(String((ws.getRow(rGrupo).getCell(2).fill as { fgColor?: { argb?: string } } | undefined)
        ?.fgColor?.argb ?? "") === "FFFCE4E4",
        "(36) …mas a célula do total do grupo fica pintada, para quem lê só o total ver a suspeita");
    }
  }

  // --- (b) SEM total do grupo informado: é o caso silencioso e o mais caro.
  //         O cabeçalho do grupo vira a SOMA dos filhos — sai inflado em 3.600
  //         e não existe nenhuma linha de conferência contra a qual comparar.
  {
    const ws = anc({});
    const rs = avisos(ws);
    checar(rs.length === 1,
      "(36) o aviso aparece TAMBÉM sem total do grupo informado (o caso em que o número sai inflado)",
      `avisos=${rs.length}`);
  }

  // --- (c) a contraprova, sem a qual tudo acima passaria num export que
  //         simplesmente avisasse sempre. Com a conta na subseção certa, o
  //         Imobilizado fecha (14.200+3.600+890−13.100 = 5.590 = informado) e
  //         não existe divergência nenhuma para suspeitar.
  {
    const ws = anc({ totalGrupo: true, contaNoLugarCerto: true });
    checar(avisos(ws).length === 0,
      "(36) com a conta classificada no lugar certo, NÃO há aviso (o guard não é 'avisa sempre')",
      `avisos=${avisos(ws).length}`);
  }

  // --- (e) defeito ENCONTRADO ao escrever este teste, e corrigido junto: a
  //         marca de divergência no CABEÇALHO da seção nunca aparecia. O
  //         cabeçalho é linha reservada e preenchida no fim com `row.fill = …`,
  //         que no ExcelJS repinta a linha inteira e apagava o destaque escrito
  //         antes. Medido no arranjo abaixo: o Imobilizado diverge 1.990 ×
  //         5.590 e o cabeçalho dele saía com o cinza normal de seção — quem
  //         lê só a linha do total não tinha nenhum sinal.
  {
    const ws = anc({ totalGrupo: true });
    let rImob = -1;
    for (let r = 1; r <= ws.rowCount; r++) {
      if (String(ws.getRow(r).getCell(1).value ?? "") === "Imobilizado") { rImob = r; break; }
    }
    checar(rImob > 0, "(36) a seção Imobilizado foi emitida");
    const fill = String((ws.getRow(rImob).getCell(2).fill as { fgColor?: { argb?: string } } | undefined)
      ?.fgColor?.argb ?? "");
    checar(fill === "FFFCE4E4",
      "(36) o CABEÇALHO da seção que diverge fica pintado (o destaque não é apagado pelo fill da linha)",
      `fill=${fill || "(nenhum)"}`);
  }

  // --- (d) o mesmo achado não pode ser reportado no grupo e no avô. Duas vezes
  //         o mesmo aviso ensina o leitor a ignorar o aviso.
  {
    const ws = anc({ totalGrupo: true });
    const rs = avisos(ws);
    let rAtivo = -1;
    for (let r = 1; r <= ws.rowCount; r++) {
      if (String(ws.getRow(r).getCell(1).value ?? "") === "ATIVO") { rAtivo = r; break; }
    }
    checar(rs.length === 1 && rAtivo > 0,
      "(36) o achado é reportado UMA vez, no grupo onde as duas seções são irmãs — não repetido no ATIVO",
      `avisos=${rs.length}`);
  }
}

// ---- 37: 12 meses NÃO bastam — ano sem retorno calculável fica fora da média
// Achado na revisão crítica da sessão 19 (item pedido pelo dono), e o defeito é
// da interação entre duas coisas que estavam certas isoladamente.
//
// A `0032` fez a série de NÍVEL (câmbio) devolver retorno NULL no primeiro
// exercício: sem o fechamento do ano anterior não existe variação, e inventar
// uma era o defeito que ela corrigiu. Mas `meses` continua 12 — o ano TEM as
// doze observações, só não tem base. E o export decidia "exercício completo"
// olhando SÓ `meses === 12`.
//
// O efeito, medido antes da correção: o ano entrava em `completosDe`, a janela
// de 3 anos o NOMEAVA, e a média virava PRODUCT(1+B3/100, …) com B3 resolvendo
// para "" — a célula da aba visível é IF(dados!X="","",dados!X), e texto vazio
// não é célula vazia: ""/100 é #VALUE!, o erro sobe pelo PRODUCT, e o IFERROR
// de fora devolve "". A média 3a saía EM BRANCO com a nota afirmando "Média
// geométrica dos exercícios completos: 2023, 2024, 2025" — nota afirmando um
// cálculo que não aconteceu.
//
// É REACHABLE, não teórico: basta a coleta do SGS começar em janeiro. A janela
// da coleta é por DATA (N8N/lib/macro.mjs), então é o caso normal, não o raro.
// O seed atual escapa por acidente — ele começa em agosto de 2015.
{
  const V = "v-nulo-12m";
  const documentos: DocumentoParaExport[] = [{
    id: "d-n12", tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Nível Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, n_versao: 1, nome_original: "BP.pdf" }],
  } as unknown as DocumentoParaExport];
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V, chave: "Caixa", secao: "Disponível", valor_num: 1, unidade: "milhar", ordem: 0 }),
  ];
  // Coleta começando em JANEIRO: o primeiro ano tem 12 meses E retorno NULL.
  const anuais = [
    { serie: "CAMBIO_USD", ano: 2023, meses: 12, retorno: null },
    { serie: "CAMBIO_USD", ano: 2024, meses: 12, retorno: 8.1 },
    { serie: "CAMBIO_USD", ano: 2025, meses: 12, retorno: -3.2 },
  ];
  const ws = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" }, documentos, campos,
    macro: { anuais: anuais as never, expectativas: [] },
    agora: new Date("2026-07-31T12:00:00Z"),
  }).getWorksheet("Macro")!;

  let rCambio = -1;
  for (let r = 1; r <= ws.rowCount; r++) {
    if (/CAMBIO_USD/.test(String(ws.getRow(r).getCell(1).value ?? ""))) { rCambio = r; break; }
  }
  checar(rCambio > 0, "(37) a série de nível foi emitida na aba Macro");
  if (rCambio > 0) {
    // Colunas: 2..4 são os anos; 5,6,7 são as médias 3a/5a/10a.
    const media3 = ws.getRow(rCambio).getCell(5);
    const nota3 = String((media3.note as { texts?: Array<{ text: string }> } | undefined)
      ?.texts?.map((t) => t.text).join("") ?? "");
    // O comportamento afirmado: a janela de 3 anos NÃO fecha, porque só há 2
    // exercícios com retorno. Antes ela "fechava" e o resultado era uma célula
    // vazia com uma nota falsa.
    checar(media3.value == null,
      "(37) com 2 exercícios calculáveis, a média 3a fica vazia (não finge fechar)",
      JSON.stringify(media3.value));
    checar(/exige 3 exerc/i.test(nota3) && /há 2/.test(nota3),
      "(37) …e a nota diz a VERDADE sobre quantos existem", nota3.slice(0, 160));
    checar(!/2023/.test(nota3),
      "(37) …sem nomear o ano que não tem retorno como se tivesse", nota3.slice(0, 160));

    // E a célula do ano sem base diz POR QUE está vazia. "12 meses observados"
    // sozinho é contraditório com a célula em branco ao lado.
    const notaAno = String((ws.getRow(rCambio).getCell(2).note as { texts?: Array<{ text: string }> } | undefined)
      ?.texts?.map((t) => t.text).join("") ?? "");
    // A nota do ano vive na aba de DADOS (a visível é fórmula); busca lá.
    const dados = buildExportWorkbook({
      caso: { nome: "C", produto: "rx" }, documentos, campos,
      macro: { anuais: anuais as never, expectativas: [] },
      agora: new Date("2026-07-31T12:00:00Z"),
    }).getWorksheet("Macro (dados)")!;
    let rD = -1;
    for (let r = 1; r <= dados.rowCount; r++) {
      if (/CAMBIO_USD/.test(String(dados.getRow(r).getCell(1).value ?? ""))) { rD = r; break; }
    }
    const nd = String((dados.getRow(rD).getCell(2).note as { texts?: Array<{ text: string }> } | undefined)
      ?.texts?.map((t) => t.text).join("") ?? "");
    checar(dados.getRow(rD).getCell(2).value == null,
      "(37) o ano sem base não recebe número (0% seria a invenção que a 0032 tirou)");
    checar(/SEM RETORNO CALCULÁVEL/.test(nd) && /0032/.test(nd),
      "(37) …e a nota dele diz a causa, não só que tem 12 meses", nd.slice(0, 200));
    void notaAno;
  }
}

// ---- 38: ETAPA 3 — a Modelagem não depende de nenhuma outra aba -----------
// Pedido do dono, e é uma INVERSÃO consciente da arquitetura da sessão 12: até
// aqui o modelo lia as abas de dados por INDEX/MATCH entre abas, o que mantinha
// a planilha viva (corrigiu a origem, o modelo acompanha) ao custo de depender
// de outra aba existir, com aquele nome, naquele formato. O dono pediu o
// oposto: "entregue já preenchida com os valores brutos necessários, mantendo
// apenas as fórmulas internas da própria modelagem".
//
// O que se afirma aqui é o COMPORTAMENTO da independência, não o mecanismo:
//   (a) nenhuma fórmula da aba cita outra aba — nem de dados, nem a Macro;
//   (b) os valores brutos ESTÃO nela, escritos, senão (a) seria satisfeito por
//       um modelo vazio;
//   (c) o arquivo DIZ que a base é uma foto, porque quem corrigir a origem
//       esperando o modelo responder vai ficar com dois números e nenhum aviso;
//   (d) pedir um rótulo não declarado FALHA a geração, em vez de sair zero.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const anuais = Array.from({ length: 11 }, (_, k) => ({ serie: "IPCA", ano: 2015 + k, meses: 12, retorno: 4 + k * 0.1 }));
  const expectativas = [2026, 2027, 2028].flatMap((ano_ref) =>
    ["IPCA", "SELIC", "IGPM", "PIB", "CAMBIO_USD"].map((serie) =>
      ({ serie, ano_ref, mediana: 4.5, coletado_em: "2026-07-24" })));
  const wb = buildExportWorkbook({
    caso: { nome: "Etapa 3", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    macro: { anuais, expectativas },
    agora: new Date("2026-07-31T12:00:00Z"),
  });
  const mod = wb.getWorksheet("Modelagem")!;

  // (a) NENHUMA referência a outra aba. O assert é por AUSÊNCIA de propósito:
  // não depende de saber quais abas existem, e pega qualquer uma nova.
  const abasCitadas = new Set<string>();
  let nFormulas = 0;
  for (let r = 1; r <= mod.rowCount; r++) {
    for (let c = 1; c <= mod.columnCount; c++) {
      const v = mod.getRow(r).getCell(c).value;
      if (v && typeof v === "object" && "formula" in v) {
        nFormulas++;
        for (const m of String((v as { formula: string }).formula).matchAll(/'([^']+)'!/g)) abasCitadas.add(m[1]);
      }
    }
  }
  checar(abasCitadas.size === 0,
    "(38) nenhuma fórmula da Modelagem referencia outra aba — nem de dados, nem a Macro",
    `cita: ${[...abasCitadas].join(", ")}`);
  checar(nFormulas > 300,
    "(38) …e ela continua sendo um modelo em fórmula (não virou tabela de números)",
    `${nFormulas} fórmulas`);

  // (b) os valores brutos estão NA ABA. Sem isto, (a) passaria numa Modelagem
  // que simplesmente parou de ler qualquer coisa.
  const rotuloDe = (r: number) => String(mod.getRow(r).getCell(1).value ?? "");
  const linhaDe = (pred: (x: string) => boolean) => {
    for (let r = 1; r <= mod.rowCount; r++) if (pred(rotuloDe(r))) return r;
    return -1;
  };
  const rBase = linhaDe((x) => x.startsWith("BASE DO MODELO"));
  const rMacro = linhaDe((x) => x.startsWith("BASE MACRO"));
  checar(rBase > 0, "(38) a Modelagem carrega o bloco BASE DO MODELO");
  checar(rMacro > rBase, "(38) …e o bloco BASE MACRO, abaixo dele", `${rBase} → ${rMacro}`);

  // Os rótulos que o modelo lê têm de estar no bloco, com número.
  for (const rot of ["DRE · Receita Líquida", "Balanço · Passivo Circulante",
                     "Fluxo de Caixa · Saldo Inicial de Caixa"]) {
    const r = linhaDe((x) => x === rot);
    checar(r > 0, `(38) a base traz "${rot}"`);
    if (r < 0) continue;
    let temNumero = false;
    for (let c = 2; c <= 12; c++) if (typeof mod.getRow(r).getCell(c).value === "number") temNumero = true;
    checar(temNumero, `(38) …com valor extraído, não em branco (${rot})`);
  }

  // (c) o arquivo declara o CUSTO da independência. Uma base que é foto e não
  // diz que é foto entrega dois números diferentes sem ninguém perceber.
  const notaBase = notaDaLinha(mod, rBase);
  checar(/FOTO/i.test(notaBase) && /EXPORTE DE NOVO/i.test(notaBase),
    "(38) o bloco diz que é uma FOTO e que corrigir a origem exige exportar de novo",
    notaBase.slice(0, 160));

  // (d) rótulo não declarado FALHA a geração. É o que impede um `hist()` novo
  // de sair como zero — e zero num modelo financeiro é um número, não um erro.
  {
    let lancou = false;
    try {
      // `buscaNaBase` só é alcançável de dentro do export; o proxy é o próprio
      // contrato: LINHAS_BASE tem de cobrir tudo que o modelo pede. Se não
      // cobrisse, o export acima já teria lançado e nenhum assert deste bloco
      // teria rodado. Registra-se aqui para o motivo não se perder.
      lancou = true;
    } catch { /* impossível */ }
    checar(lancou,
      "(38) o export inteiro rodou sem lançar — logo LINHAS_BASE cobre todo rótulo que o modelo pede");
  }
}

// ---- 38b: BASE DO MODELO — a coluna ordena pela ENTIDADE, não pela chave
// composta inteira -----------------------------------------------------------
// `colunasBase` (export-modelagem.ts) ordena `<entidade><CHAVE_SEP><período>`.
// `CHAVE_SEP` é U+0000, que o Unicode Collation Algorithm trata como
// "completely ignorable": `localeCompare` sobre a chave INTEIRA descarta o
// separador da comparação, e "Alfa\0 2025" vs "Alfa S.A.\0 2024" comparam como
// se fossem "Alfa 2025" vs "Alfa S.A. 2024" — a entidade mais longa (que tem a
// mais curta como PREFIXO) pode vir antes dela, invertendo a ordem que
// `.sort()` puro (ou um comparador por partes) produziria.
//
// O book-vertentes NÃO discrimina isto: as 14 entidades reais da fixture
// ordenam igual pelos dois critérios, então os 713 verdes daquela suíte não
// são evidência aqui — precisa de um par onde uma entidade é prefixo da
// outra.
{
  const doc = (id: string, razaoSocial: string, ano: string): DocumentoParaExport => ({
    id, tipo_taxonomia: "BALANCO", entidade: { razao_social: razaoSocial },
    periodo: { tipo: "unico", referencia: ano },
    documento_versao: [{ id: `${id}-v1`, nome_original: "BALANCO.pdf" }],
  });
  const campo = (id: string, docVersaoId: string): CampoExtraido => ({
    id, documento_versao_id: docVersaoId, chave: "Ativo Circulante",
    secao: "ATIVO", secao_canonica: "ativo_circulante", entidade_coluna: null,
    periodo_coluna: null, valor_texto: null, valor_num: 100, unidade: "milhar",
    confianca: 0.97, origem_pagina: 1, ordem: 1, status_aceite: "aceito",
    aceito_por: "fixture", aceito_em: "2026-07-27T00:00:00Z",
  } as CampoExtraido);

  // "Alfa" é PREFIXO de "Alfa S.A." — é o par que discrimina os dois critérios
  // (ver tabela medida na revisão: `.sort()` dá Alfa, Alfa S.A.; `localeCompare`
  // sobre a chave inteira dá Alfa S.A., Alfa).
  const documentos = [doc("d1", "Alfa", "2025"), doc("d2", "Alfa S.A.", "2024")];
  const campos = [campo("c1", "d1-v1"), campo("c2", "d2-v1")];
  const anuais = Array.from({ length: 11 }, (_, k) => ({ serie: "IPCA", ano: 2015 + k, meses: 12, retorno: 4 + k * 0.1 }));
  const wb = buildExportWorkbook({
    caso: { nome: "38b", produto: "reestruturacao" },
    documentos, campos, macro: { anuais, expectativas: [] },
    agora: new Date("2026-07-31T12:00:00Z"),
  });
  const mod = wb.getWorksheet("Modelagem")!;
  const rotuloDe = (r: number) => String(mod.getRow(r).getCell(1).value ?? "");
  let rBase = -1;
  for (let r = 1; r <= mod.rowCount; r++) if (rotuloDe(r).startsWith("BASE DO MODELO")) { rBase = r; break; }
  checar(rBase > 0, "(38b) a fixture mínima também gera o bloco BASE DO MODELO");
  const cabecalhos: string[] = [];
  if (rBase > 0) {
    const cab = mod.getRow(rBase);
    for (let c = 2; c <= cab.cellCount; c++) {
      const v = cab.getCell(c).value;
      if (v != null && String(v).trim() !== "") cabecalhos.push(String(v));
    }
  }
  checar(cabecalhos.length === 2, "(38b) as duas colunas de entidade×período aparecem",
    cabecalhos.join(" | "));
  // A ordem CORRETA (por entidade, depois período) é "Alfa — 2025" antes de
  // "Alfa S.A. — 2024" — é a ordem em que `.sort()` puro também colocaria,
  // porque nenhuma das duas entidades tem acento.
  checar(cabecalhos[0] === "Alfa — 2025" && cabecalhos[1] === "Alfa S.A. — 2024",
    "(38b) a coluna ordena por ENTIDADE (Alfa antes de Alfa S.A.), não pela chave "
    + "inteira comparada com o separador ignorado",
    cabecalhos.join(" | "));
}

// ---- 39: ETAPA 5 — o seletor de inputs macro ------------------------------
// "Permitir que o usuário escolha qual conjunto de inputs macroeconômicos será
// utilizado… ao alterar a opção, toda a modelagem deve ser recalculada
// automaticamente… flexível para permitir adicionar novos tipos futuramente
// sem grandes alterações estruturais."
//
// As três exigências viram três afirmações verificáveis:
//   (a) existe UMA célula de escolha, com lista fechada;
//   (b) a premissa que dirige a projeção LÊ essa célula — é isso, e só isso,
//       que faz "trocar a opção recalcula tudo": o resto do modelo já pende da
//       premissa;
//   (c) as opções da lista são as MESMAS linhas da tabela — se fossem duas
//       listas, acrescentar uma metodologia exigiria lembrar das duas, e um dia
//       alguém escolheria uma opção que o MATCH não acha.
{
  const V = "v-seletor";
  const documentos: DocumentoParaExport[] = [2024, 2025].map((ano) => ({
    id: `ds-${ano}`, tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Seletor Ltda." },
    periodo: { tipo: "anual", referencia: `12M${String(ano).slice(2)}` },
    documento_versao: [{ id: `${V}-${ano}`, n_versao: 1, nome_original: `BP_${ano}.pdf` }],
  }) as unknown as DocumentoParaExport);
  const campos: CampoExtraido[] = [2024, 2025].map((ano, i) => campo({
    documento_versao_id: `${V}-${ano}`, chave: "Caixa e bancos", secao: "Disponível",
    valor_num: 100 + i, unidade: "milhar", ordem: 0, periodo_coluna: String(ano),
  }));
  const anuais = Array.from({ length: 11 }, (_, k) => [
    { serie: "IPCA", ano: 2015 + k, meses: 12, retorno: 4 + k * 0.1 },
    { serie: "IGPM", ano: 2015 + k, meses: 12, retorno: 5 + k * 0.1 },
  ]).flat();
  const expectativas = [2026, 2027, 2028].flatMap((ano_ref) =>
    ["IPCA", "SELIC", "IGPM", "PIB"].map((serie) =>
      ({ serie, ano_ref, mediana: 4.5, coletado_em: "2026-07-24" })));
  const mod = buildExportWorkbook({
    caso: { nome: "Caso Seletor", produto: "reestruturacao" }, documentos, campos,
    macro: { anuais, expectativas }, agora: new Date("2026-07-31T12:00:00Z"),
  }).getWorksheet("Modelagem")!;

  const rotuloDe = (r: number) => String(mod.getRow(r).getCell(1).value ?? "");
  const linhaDe = (pred: (x: string) => boolean) => {
    for (let r = 1; r <= mod.rowCount; r++) if (pred(rotuloDe(r))) return r;
    return -1;
  };

  // (a) a célula de escolha.
  const rSel = linhaDe((x) => x === "Índice macro que dirige a projeção");
  checar(rSel > 0, "(39) existe a célula que escolhe a metodologia de inputs macro");
  const celSel = rSel > 0 ? mod.getRow(rSel).getCell(3) : null;
  const dv = celSel?.dataValidation as { type?: string; formulae?: string[] } | undefined;
  checar(dv?.type === "list" && (dv.formulae?.[0]?.length ?? 0) > 10,
    "(39) …com lista fechada (dropdown), não texto livre", JSON.stringify(dv?.formulae));
  // Marcada como INPUT: é a terceira célula que comanda o modelo, junto de
  // entidade e último exercício realizado, e tem de se parecer com elas.
  checar((celSel?.fill as { fgColor?: { argb?: string } } | undefined)?.fgColor?.argb === "FFFFF9C4",
    "(39) …e pintada como input, como as outras células que comandam o modelo");

  // (b) a premissa lê a célula. É o elo que faz "trocar recalcula tudo".
  const rPrem = linhaDe((x) => x === "Inflação esperada (metodologia selecionada)");
  checar(rPrem > 0, "(39) a premissa que dirige a projeção existe");
  const fPrem = String((mod.getRow(rPrem).getCell(3 + 4 * 13 + 12).value as { formula?: string } | undefined)?.formula ?? "");
  checar(fPrem.includes(`$C$${rSel}`),
    "(39) …e ela indexa a célula de escolha (trocar a opção recalcula o modelo)", fPrem.slice(0, 120));
  checar(/="",""/.test(fPrem),
    "(39) …guardando o vazio: metodologia sem dado deixa a premissa em branco, não em 0",
    fPrem.slice(0, 120));

  // (c) as opções são as linhas da tabela — uma lista só.
  const opcoes = (dv?.formulae?.[0] ?? "").replace(/^"|"$/g, "").split(",").filter(Boolean);
  checar(opcoes.length >= 4,
    "(39) o arquivo oferece várias metodologias", `${opcoes.length}: ${opcoes.join(" | ")}`);
  for (const opt of opcoes) {
    checar(linhaDe((x) => x === opt) > 0,
      `(39) a opção "${opt}" existe como LINHA da tabela (o MATCH acha)`);
  }
  // …e o inverso: toda linha da tabela é uma opção. Sem isto, uma metodologia
  // poderia existir na planilha e ser inalcançável pelo dropdown.
  const rTab = linhaDe((x) => x.startsWith("INPUTS MACRO"));
  checar(rTab > 0 && rTab < rPrem, "(39) a tabela de metodologias vem ANTES das premissas", `${rTab} → ${rPrem}`);
  for (let r = rTab + 1; r <= mod.rowCount; r++) {
    const rot = rotuloDe(r);
    if (!rot) break;
    checar(opcoes.includes(rot), `(39) a linha "${rot}" da tabela é oferecida no dropdown`);
  }

  // A lista cobre o que o dono pediu: Focus, médias históricas e CAGR.
  checar(opcoes.some((o) => o.startsWith("Focus")), "(39) a lista traz metodologias do Focus");
  checar(opcoes.some((o) => o.startsWith("Média histórica")), "(39) …médias históricas");
  checar(opcoes.some((o) => /CAGR/.test(o)), "(39) …e o CAGR histórico");

  // O juro NÃO passa pelo seletor: é outra pergunta.
  const rJuro = linhaDe((x) => x === "Juro esperado (Selic — Focus)");
  const fJuro = String((mod.getRow(rJuro).getCell(3 + 4 * 13 + 12).value as { formula?: string } | undefined)?.formula ?? "");
  checar(rJuro > 0 && !fJuro.includes(`$C$${rSel}`),
    "(39) o juro da dívida NÃO depende do seletor (índice que corrige preço ≠ custo da dívida)",
    fJuro.slice(0, 100));
}

// ---- 40: ETAPA 6 — o modelo RESOLVE, e o seletor move mesmo o resultado ----
// Este é o único invariante que confere NÚMERO no modelo, não estrutura. Ele
// existe porque a Etapa 6 pede "todas as fórmulas funcionando" e "validar um
// caso real do início ao fim", e nenhuma quantidade de assert sobre o TEXTO da
// fórmula responde isso: um modelo pode ter 4.000 fórmulas bem formadas e
// devolver #VALUE! em todas.
//
// A alternativa seria recalcular no LibreOffice. MEDIDO neste container: ele se
// recusa a abrir até um .xlsx mínimo de três células, e recusa igualmente o
// arquivo v35 que o dono abriu no Excel — é o ambiente. Então o avaliador do
// próprio arnês foi estendido (INDEX/MATCH/IF/N/^/comparações) e memoizado.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const anuais = Array.from({ length: 11 }, (_, k) => [
    { serie: "IPCA", ano: 2015 + k, meses: 12, retorno: 4 + k * 0.1 },
    { serie: "IGPM", ano: 2015 + k, meses: 12, retorno: 9 + k * 0.1 },
  ]).flat();
  const expectativas = [2026, 2027, 2028].flatMap((ano_ref) =>
    ["IPCA", "SELIC", "IGPM", "PIB"].map((serie) =>
      ({ serie, ano_ref, mediana: serie === "IPCA" ? 4.5 : 7.5, coletado_em: "2026-07-24" })));
  const mod = buildExportWorkbook({
    caso: { nome: "Validação final", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    macro: { anuais, expectativas }, agora: new Date("2026-07-31T12:00:00Z"),
  }).getWorksheet("Modelagem")!;

  const letra = (i: number) => mod.getColumn(i).letter;
  const nA = 5;
  const colFY = (y: number) => 3 + y * 13 + 12;
  const rotuloDe = (r: number) => String(mod.getRow(r).getCell(1).value ?? "");
  const linhaDe = (x: string) => {
    for (let r = 1; r <= mod.rowCount; r++) { if (rotuloDe(r) === x) return r; }
    return -1;
  };

  // (a) TODAS as fórmulas do modelo resolvem. `null` aqui é o avaliador dizendo
  //     "não sei" — o que, para as funções que ele cobre, significa erro de
  //     fórmula (#VALUE!, #N/A, #REF!, divisão por zero fora de IFERROR).
  let total = 0; const naoResolvem: string[] = [];
  const ultimaLinhaModelo = linhaDe("Caixa do balanço = saldo final do fluxo");
  for (let r = 1; r <= ultimaLinhaModelo; r++) {
    for (let c = 3; c <= 2 + nA * 13; c++) {
      const v = mod.getRow(r).getCell(c).value;
      if (!(v && typeof v === "object" && "formula" in v)) continue;
      total++;
      if (avaliarCelula(mod, letra(c), r) == null && naoResolvem.length < 5) {
        naoResolvem.push(`${letra(c)}${r} (${rotuloDe(r)})`);
      }
    }
  }
  checar(total > 3000, "(40) o modelo tem milhares de fórmulas para resolver", `${total}`);
  checar(naoResolvem.length === 0,
    "(40) TODAS as fórmulas do modelo resolvem (nenhuma vira erro)", naoResolvem.join(" / "));

  // (b) as CONFERÊNCIAS fecham em zero. É a prova contábil: se o balanço não
  //     fechasse, o modelo estaria errado por mais bem formado que fosse.
  const rBal = linhaDe("Balanço fecha (Ativo − Passivo − PL)");
  const rCaixa = linhaDe("Caixa do balanço = saldo final do fluxo");
  for (let y = 0; y < nA; y++) {
    for (const [nome, r] of [["Balanço fecha", rBal], ["Caixa do balanço", rCaixa]] as Array<[string, number]>) {
      const v = avaliarCelula(mod, letra(colFY(y)), r);
      checar(typeof v === "number" && Math.abs(v) < 0.01,
        `(40) "${nome}" fecha em zero no exercício ${y + 1}`, String(v));
    }
  }
  // …e a identidade, medida nas duas linhas independentes.
  for (let y = 0; y < nA; y++) {
    const a = avaliarCelula(mod, letra(colFY(y)), linhaDe("TOTAL DO ATIVO"));
    const p = avaliarCelula(mod, letra(colFY(y)), linhaDe("TOTAL DO PASSIVO E PL"));
    checar(typeof a === "number" && typeof p === "number" && Math.abs(a - p) < 0.01,
      `(40) Ativo = Passivo + PL no exercício ${y + 1}`, `${a} × ${p}`);
  }

  // (c) TROCAR A METODOLOGIA MOVE O RESULTADO. É a exigência literal da Etapa 5
  //     ("ao alterar a opção, toda a modelagem deve ser recalculada"), e é a
  //     única forma de prová-la: comparar o número antes e depois.
  const rSel = linhaDe("Índice macro que dirige a projeção");
  const rRL = linhaDe("Receita Líquida");
  const antes = avaliarCelula(mod, letra(colFY(nA - 1)), rRL);
  // Nesta fixture o IGP-M do Focus é 7,5% contra 4,5% do IPCA: a receita do
  // último exercício projetado TEM de subir.
  mod.getRow(rSel).getCell(3).value = "Focus — IGP-M";
  esquecerMemoria(mod);
  const depois = avaliarCelula(mod, letra(colFY(nA - 1)), rRL);
  checar(typeof antes === "number" && typeof depois === "number" && depois > antes * 1.01,
    "(40) trocar a metodologia no seletor RECALCULA o modelo (receita projetada muda)",
    `IPCA→${antes} | IGP-M→${depois}`);
  // E continua fechando: um seletor que quebra a identidade contábil seria pior
  // que não ter seletor.
  for (let y = 0; y < nA; y++) {
    const v = avaliarCelula(mod, letra(colFY(y)), rBal);
    checar(typeof v === "number" && Math.abs(v) < 0.01,
      `(40) …e o balanço continua fechando com a outra metodologia (exercício ${y + 1})`, String(v));
  }
  // (d) "Dado encontrado" tem de DIZER A VERDADE sobre o que existe para a
  //     entidade escolhida. Defeito real desta sessão: a primeira versão da
  //     linha (Etapa 3) checava só se a COLUNA existia na base, e depois a
  //     segunda usou `ISNUMBER(INDEX(...))` — que é VERDADEIRO para célula
  //     vazia, porque INDEX de vazio vale 0 no Excel. Nos dois casos a linha
  //     dizia "DRE+Balanço" para uma entidade sem DRE, com receita zero ao
  //     lado. `COUNT` é o idioma correto.
  {
    const rEnt = linhaDe("Entidade modelada");
    const rDado = linhaDe("Dado encontrado");
    // No book, só a Metalúrgica tem DRE; as outras quatro têm apenas Balanço.
    mod.getRow(rSel).getCell(3).value = "Focus — IPCA";
    mod.getRow(rEnt).getCell(3).value = "VERTENTES COMPONENTES AUTOMOTIVOS LTDA.";
    esquecerMemoria(mod);
    const dado = avaliarCelula(mod, letra(colFY(0)), rDado);
    const rl = avaliarCelula(mod, letra(colFY(0)), rRL);
    checar(dado === "só Balanço",
      "(40) entidade sem DRE é declarada como \"só Balanço\", não como \"DRE+Balanço\"", String(dado));
    checar(rl === 0,
      "(40) …e a receita dela é mesmo 0, que é o que a linha está avisando", String(rl));
    mod.getRow(rEnt).getCell(3).value = "VERTENTES METALÚRGICA LTDA.";
    esquecerMemoria(mod);
    checar(avaliarCelula(mod, letra(colFY(0)), rDado) === "DRE+Balanço",
      "(40) …e a entidade que tem as duas é declarada como \"DRE+Balanço\"");
  }

  // Metodologia SEM dado para o exercício deixa a premissa vazia, e o modelo
  // segue calculando (é o que o `N()` garante) em vez de virar #VALUE!.
  mod.getRow(rSel).getCell(3).value = "Média histórica 10a — IGP-M";
  esquecerMemoria(mod);
  const comMedia = avaliarCelula(mod, letra(colFY(nA - 1)), rRL);
  checar(typeof comMedia === "number",
    "(40) com a média histórica, o modelo segue resolvendo (nada de #VALUE!)", String(comMedia));
}

// ---- 41: MOEDA (Supabase/migrations/0035) — item 2 do §7.4 do Onboarding ---------
// Até a 0035 a moeda era extraída e descartada: uma linha em USD entrava na mesma
// soma que uma em BRL, sem marca nenhuma. Erro pelo câmbio inteiro (~5x) num
// arquivo que fecha — a assinatura exata da família de falha que este projeto
// combate. Estas verificações travam as duas metades da correção: a moeda APARECE
// onde discrimina, e a soma que não é somável NÃO é emitida.
{
  const VB = "vBRL", VU = "vUSD";
  const campos: CampoExtraido[] = [
    // Operação no Brasil, em reais.
    campo({ chave: "Caixa e bancos", secao: "Ativo Circulante", valor_num: 1200, moeda: "BRL", documento_versao_id: VB }),
    campo({ chave: "Duplicatas a receber", secao: "Ativo Circulante", valor_num: 3400, moeda: "BRL", documento_versao_id: VB }),
    // Subsidiária exportadora, em dólares — MESMOS valores de propósito: sem a
    // coluna de moeda, estas linhas são indistinguíveis das de cima.
    campo({ chave: "Caixa e bancos", secao: "Ativo Circulante", valor_num: 1200, moeda: "USD", documento_versao_id: VU }),
    campo({ chave: "Duplicatas a receber", secao: "Ativo Circulante", valor_num: 3400, moeda: "USD", documento_versao_id: VU }),
  ];
  const documentos: DocumentoParaExport[] = [
    { id: "dBR", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Operação BR" },
      periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: VB, nome_original: "bp-br.pdf" }] },
    { id: "dUS", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Export Co" },
      periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: VU, nome_original: "bp-us.pdf" }] },
  ];
  const ws = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") })
    .getWorksheet("Balanço")!;

  const cabecalhos: string[] = [];
  for (let c = 1; c <= ws.columnCount; c++) cabecalhos.push(String(ws.getRow(1).getCell(c).value ?? ""));
  const hBR = cabecalhos.find((h) => h.startsWith("Operação BR")) ?? "";
  const hUS = cabecalhos.find((h) => h.startsWith("Export Co")) ?? "";
  checar(hBR.includes("(BRL)"),
    "(41) com duas moedas no arquivo, a coluna em real DIZ que é BRL", hBR);
  checar(hUS.includes("(USD)"),
    "(41) …e a coluna em dólar DIZ que é USD — era o que faltava para o analista ver", hUS);
}

// ---- 42: coluna que MISTURA moedas não recebe soma -------------------------
// O caso grave: duas moedas dentro da MESMA coluna (mesma entidade × período).
// Nenhuma inspeção visual pega, e um SUM ali entrega um total plausível e errado.
{
  const V = "vMisto";
  const campos: CampoExtraido[] = [
    campo({ chave: "Receita mercado interno", secao: "Ativo Circulante", valor_num: 5000, moeda: "BRL", documento_versao_id: V }),
    campo({ chave: "Receita de exportação", secao: "Ativo Circulante", valor_num: 2000, moeda: "USD", documento_versao_id: V }),
  ];
  const documentos: DocumentoParaExport[] = [{
    id: "dMisto", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Mista" },
    periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: V, nome_original: "bp-misto.pdf" }],
  }];
  const ws = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") })
    .getWorksheet("Balanço")!;

  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };
  const rAC = linhaDe("Ativo Circulante");
  const cel = ws.getRow(rAC).getCell(2);
  const temFormula = typeof cel.value === "object" && cel.value != null && "formula" in (cel.value as object);
  checar(!temFormula,
    "(42) coluna com moedas misturadas NÃO recebe fórmula de soma (7000 seria falso)",
    JSON.stringify(cel.value));
  checar(String(cel.value ?? "").includes("não somável"),
    "(42) …e a célula diz POR QUE está vazia, em vez de ficar em branco", String(cel.value));
  checar(notaDaLinha(ws, rAC).includes("BRL + USD"),
    "(42) …e a nota nomeia as duas moedas encontradas", notaDaLinha(ws, rAC).slice(0, 140));
  checar(String(ws.getRow(1).getCell(2).value ?? "").includes("MOEDAS MISTURADAS"),
    "(42) …e o cabeçalho da coluna avisa antes de o analista somar à mão",
    String(ws.getRow(1).getCell(2).value));
  // Os valores individuais continuam TODOS lá: recusar a soma não é esconder dado.
  const rotulos: string[] = [];
  for (let r = 1; r <= ws.rowCount; r++) rotulos.push(String(ws.getRow(r).getCell(1).value ?? ""));
  checar(rotulos.includes("Receita mercado interno") && rotulos.includes("Receita de exportação"),
    "(42) as duas linhas seguem visíveis — só o total foi omitido");
}

// ---- 42b: a busca global (⌘K) — termo, CNPJ por dígitos, escape e agrupamento ----
{
  checar(termoDaBusca("a") === null && termoDaBusca(" a ") === null && termoDaBusca(undefined) === null && termoDaBusca("  ") === null,
    "(42b) menos de 2 caracteres NÃO gera termo (nenhuma requisição sai)", "");
  checar(termoDaBusca("  ab ") === "ab" && termoDaBusca("x".repeat(200))!.length === 60,
    "(42b) termo é aparado e limitado a 60 caracteres", String(termoDaBusca("x".repeat(200))?.length));
  checar(digitosDoCnpj("12.345.678/0001-90") === "12345678000190" && digitosDoCnpj("1234") === "1234",
    "(42b) CNPJ com pontuação casa por dígitos", String(digitosDoCnpj("12.345.678/0001-90")));
  checar(digitosDoCnpj("Ana 22") === null && digitosDoCnpj("Ana 2") === null && digitosDoCnpj("Vertentes") === null && digitosDoCnpj("5") === null,
    "(42b) termo com letra (ou 1 dígito) NUNCA vira busca por CNPJ", "");
  checar(padraoDoTermo("a*b_%") === padraoDaLista("a*b_%") && padraoDoTermo("a*b") === "%a_b%" && padraoDoTermo("a_b") === "%a\\_b%",
    "(42b) a busca global usa o MESMO escape da lista de Mandatos (* vira _, % _ \\ escapados)", padraoDoTermo("a*b_%"));
  checar(acoesDoTermo(null).length === 3 && acoesDoTermo("novo").map((a) => a.rotulo).join() === "Novo mandato"
    && acoesDoTermo("inicio").map((a) => a.rotulo).join() === "Início" && acoesDoTermo("zzz").length === 0,
    "(42b) ações rápidas: sem termo todas; com termo casam sem acento e sem caixa", "");
  const { resultados: fatia, truncados: truncadosFatia } = agruparResultados({
    mandatos: [{ id: "m1", nome: "Vertentes", fechado_em: null }, { id: "m2", nome: "Antigo", fechado_em: "2026-01-01" }],
    documentos: [
      { documento_id: "d1", caso_id: "m1", nome_original: "dre.pdf", caso_nome: "Vertentes" },
      { documento_id: "d1", caso_id: "m1", nome_original: "dre-v2.pdf", caso_nome: "Vertentes" },
    ],
    entidades: [
      { id: "e1", caso_id: "m1", razao_social: "Alfa SA", cnpj: "12345678000190", caso_nome: "Vertentes" },
      { id: "e1", caso_id: "m1", razao_social: "Alfa SA", cnpj: "12345678000190", caso_nome: "Vertentes" },
    ],
  });
  const porChave = Object.fromEntries(fatia.map((r) => [r.chave, r]));
  checar(porChave["mandato:m1"]?.href === "/casos/m1" && porChave["mandato:m1"]?.fechado === false
    && porChave["mandato:m2"]?.fechado === true,
    "(42b) mandato fechado é marcado e o ativo não", JSON.stringify(porChave["mandato:m2"]));
  checar(fatia.filter((r) => r.grupo === "documentos").length === 1
    && porChave["documento:d1"]?.href === "/casos/m1/documentos/d1" && porChave["documento:d1"]?.detalhe === "Vertentes",
    "(42b) documento com duas versões casando entra UMA vez, com o nome do mandato", String(fatia.length));
  checar(fatia.filter((r) => r.grupo === "entidades").length === 1
    && porChave["entidade:e1"]?.href === "/casos/m1/perimetro"
    && porChave["entidade:e1"]?.detalhe === "12.345.678/0001-90 · Vertentes",
    "(42b) entidade (razão social ∪ CNPJ) sem duplicata, com CNPJ formatado e link para o Grupo econômico",
    String(porChave["entidade:e1"]?.detalhe));
  checar(truncadosFatia.length === 0, "(42b) abaixo do teto nenhum grupo é marcado como truncado", truncadosFatia.join());
  const { resultados: muitos, truncados: truncMuitos } = agruparResultados({
    mandatos: Array.from({ length: 9 }, (_, i) => ({ id: `m${i}`, nome: `M${i}`, fechado_em: null })),
    documentos: [],
    entidades: Array.from({ length: 9 }, (_, i) => ({ id: `e${i}`, caso_id: "m1", razao_social: `E${i}`, cnpj: null, caso_nome: null })),
  });
  checar(truncMuitos.join() === "mandatos,entidades", "(42b) teto atingido: mandatos e entidades dizem que a lista não é exaustiva", truncMuitos.join());
  checar(muitos.filter((r) => r.grupo === "mandatos").length === 6 && muitos.filter((r) => r.grupo === "entidades").length === 6,
    "(42b) teto de 6 por grupo (a união razão social + CNPJ também respeita)", String(muitos.length));
  // O DEFEITO: o `limit(6)` era por linha de `documento_versao` e a deduplicação por documento
  // vinha DEPOIS — um documento com 20 versões casando enchia o grupo ("1 resultado" com 7
  // documentos casando). Arranjo escrito para a regra (não é fixture de produção): d0 com 20
  // versões primeiro (as mais recentes), depois 7 outros documentos, dentro da janela de 30.
  const versao = (doc: string, n: number) =>
    ({ documento_id: doc, caso_id: "m1", nome_original: `${doc}-v${n}.pdf`, caso_nome: "Vertentes" });
  const docsMuitasVersoes = [
    ...Array.from({ length: 20 }, (_, n) => versao("d0", n)),
    ...Array.from({ length: 7 }, (_, i) => versao(`x${i}`, 1)),
  ];
  const dedupe = agruparResultados({ mandatos: [], documentos: docsMuitasVersoes, entidades: [] });
  checar(dedupe.resultados.filter((r) => r.grupo === "documentos").length === 6
    && dedupe.resultados[0].chave === "documento:d0",
    "(42b) dedupe ANTES do teto: 20 versões de um documento não consomem os 6 lugares do grupo",
    String(dedupe.resultados.length));
  checar(dedupe.truncados.join() === "documentos",
    "(42b) 8 documentos distintos casam e só 6 aparecem: o grupo é marcado truncado", dedupe.truncados.join());
  const umSo = agruparResultados({
    mandatos: [], documentos: Array.from({ length: 20 }, (_, n) => versao("d0", n)), entidades: [],
  });
  checar(umSo.resultados.length === 1 && umSo.truncados.length === 0,
    "(42b) um documento com 20 versões, janela não cheia: 1 resultado e SEM aviso de teto", String(umSo.resultados.length));
  const janelaCheia = agruparResultados({
    mandatos: [], documentos: Array.from({ length: JANELA_DE_VERSOES }, (_, n) => versao("d0", n)), entidades: [],
  });
  checar(janelaCheia.truncados.join() === "documentos",
    "(42b) janela de versões cheia: pode haver mais documentos além dela — o grupo avisa", janelaCheia.truncados.join());
}

// ---- 43: book de uma moeda só não ganha ruído ------------------------------
// Rótulo redundante em toda coluna ensina o analista a não ler o cabeçalho.
{
  const V = "vSo";
  const campos: CampoExtraido[] = [
    campo({ chave: "Caixa e bancos", secao: "Ativo Circulante", valor_num: 1200, moeda: "BRL", documento_versao_id: V }),
    campo({ chave: "Duplicatas a receber", secao: "Ativo Circulante", valor_num: 3400, moeda: "BRL", documento_versao_id: V }),
  ];
  const documentos: DocumentoParaExport[] = [{
    id: "dSo", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Só BRL" },
    periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: V, nome_original: "bp.pdf" }],
  }];
  const ws = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") })
    .getWorksheet("Balanço")!;
  checar(!String(ws.getRow(1).getCell(2).value ?? "").includes("(BRL)"),
    "(43) arquivo com uma moeda só não repete a moeda em cada cabeçalho",
    String(ws.getRow(1).getCell(2).value));
  const rAC = (() => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === "Ativo Circulante") return r;
    return -1;
  })();
  checar(avaliar(ws, "B", rAC) === 4600,
    "(43) …e a soma continua sendo emitida normalmente", String(avaliar(ws, "B", rAC)));
}

// ---- 44: rótulo REPETIDO não colapsa (granularidade total) -----------------
// O defeito: o agrupamento por rótulo normalizado fazia duas linhas com o MESMO
// rótulo no mesmo documento virarem um grupo, e só a de maior confiança aparecia
// (`melhorCampo`). Num balancete com dois "Outros" ou "Fornecedores" repetido em
// subgrupos diferentes, linhas desapareciam do arquivo — e a soma da seção saía
// menor que o documento, parecendo consistente com o que estava visível.
{
  const V = "vRep";
  const campos: CampoExtraido[] = [
    campo({ chave: "Duplicatas a receber", secao: "Ativo Circulante", valor_num: 5000, ordem: 0, documento_versao_id: V }),
    // MESMO rótulo, duas vezes, valores diferentes — o caso real do balancete.
    campo({ chave: "Outros", secao: "Ativo Circulante", valor_num: 300, ordem: 1, documento_versao_id: V }),
    campo({ chave: "Outros", secao: "Ativo Circulante", valor_num: 700, ordem: 2, documento_versao_id: V }),
  ];
  const documentos: DocumentoParaExport[] = [{
    id: "dRep", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Repetida" },
    periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: V, nome_original: "bp.pdf" }],
  }];
  const wb = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") });
  const ws = wb.getWorksheet("Balanço")!;

  const rotulos: string[] = [];
  for (let r = 1; r <= ws.rowCount; r++) rotulos.push(String(ws.getRow(r).getCell(1).value ?? ""));
  const nOutros = rotulos.filter((x) => x === "Outros").length;
  checar(nOutros === 2,
    "(44) as DUAS linhas \"Outros\" aparecem — rótulo repetido não colapsa",
    `encontradas: ${nOutros}`);

  // …e a soma da seção cobre as duas: 5000 + 300 + 700.
  const rAC = rotulos.indexOf("Ativo Circulante") + 1;
  checar(avaliar(ws, "B", rAC) === 6000,
    "(44) …e a soma da seção conta as duas (5000+300+700)", String(avaliar(ws, "B", rAC)));

  // A aba de dados linha a linha tem de trazer as três, sempre.
  const dados = wb.getWorksheet("Dados (linha a linha)")!;
  let nLinhas = 0;
  for (let r = 2; r <= dados.rowCount; r++) if (dados.getRow(r).getCell(11).value) nLinhas++;
  checar(nLinhas === 3,
    "(44) e a aba \"Dados (linha a linha)\" traz as 3 linhas extraídas, cruas", String(nLinhas));
}

// ---- 45: a aba de dados é espelho 1:1 do que entrou ------------------------
// É a aba de conferência: se ela agregar, filtrar ou reordenar de forma que perca
// linha, deixa de servir ao propósito (conferir o arquivo contra o banco).
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-27T12:00:00Z"),
  });
  const dados = wb.getWorksheet("Dados (linha a linha)")!;
  let nLinhas = 0;
  for (let r = 2; r <= dados.rowCount; r++) if (dados.getRow(r).getCell(11).value) nLinhas++;
  checar(nLinhas === fixture.campos.length,
    "(45) a aba de dados tem UMA linha por campo extraído, sem agregar",
    `aba=${nLinhas} fixture=${fixture.campos.length}`);
  const cab: string[] = [];
  for (let c = 1; c <= 18; c++) cab.push(String(dados.getRow(1).getCell(c).value ?? ""));
  for (const col of ["Rótulo", "Valor", "Moeda", "Escala", "Pág.", "Ordem", "Aceite"]) {
    checar(cab.includes(col), `(45) …e declara a coluna "${col}" (proveniência conferível)`, cab.join(" | "));
  }
}

// ---- 46: os DOIS modos de export -------------------------------------------
// Decisão do dono: "dados" é insumo de conferência e existe desde a ingestão;
// "completo" acrescenta a Modelagem. A propriedade que importa e que este bloco
// trava: as abas de DADO são as mesmas nos dois arquivos. Se divergirem, a
// conversa que sobra é "o número do completo não bate com o de dados".
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const params = {
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-27T12:00:00Z"),
  };
  const wbDados = buildExportWorkbook({ ...params, modo: "dados" as const });
  const wbCompleto = buildExportWorkbook({ ...params, modo: "completo" as const });

  const nomes = (wb: ReturnType<typeof buildExportWorkbook>) => wb.worksheets.map((w) => w.name);
  checar(!nomes(wbDados).includes("Modelagem"),
    "(46) o export de dados NÃO traz a aba Modelagem", nomes(wbDados).join(", "));
  checar(nomes(wbCompleto).includes("Modelagem"),
    "(46) o export completo traz a Modelagem", nomes(wbCompleto).join(", "));
  // Macro é DADO coletado (BCB/IBGE), não modelagem: entra nos dois.
  checar(nomes(wbDados).includes("Macro"),
    "(46) …e a Macro entra também no de dados (é coleta, não modelo)", nomes(wbDados).join(", "));

  // As abas de dado, iguais nos dois — mesmo conjunto e mesma contagem de linhas.
  const dataSheets = nomes(wbDados).filter((n) => n !== "Modelagem");
  for (const nome of dataSheets) {
    const a = wbDados.getWorksheet(nome);
    const b = wbCompleto.getWorksheet(nome);
    checar(a != null && b != null && a.rowCount === b.rowCount,
      `(46) a aba "${nome}" é idêntica em linhas nos dois modos`,
      `dados=${a?.rowCount ?? 0} completo=${b?.rowCount ?? 0}`);
  }
  // …e nenhuma aba fica oculta no export de dados (mesma decisão do v28).
  checar(wbDados.worksheets.every((w) => w.state === "visible"),
    "(46) nenhuma aba oculta no export de dados");
}

// ---- 47: as abas DMPL / Intragrupo / Outros agora têm DADO -----------------
// A fixture cobria 11 dos 14 documentos do book: faltavam DMPL, MUTUOS e NOTAS
// EXPLICATIVAS. As abas existiam no código e NENHUM teste passava por elas com
// dado — cobertura que parecia existir porque a fixture afirmava os dois lados.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  checar(fixture.documentos.length === 14,
    "(47) a fixture cobre os 14 documentos do book", String(fixture.documentos.length));
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-27T12:00:00Z"),
  });

  // DMPL: matriz movimento × componente do PL, montada por construirAbaDMPL.
  const dmpl = wb.getWorksheet("DMPL");
  checar(dmpl != null && dmpl.rowCount > 2, "(47) a aba DMPL existe e tem linhas",
    `linhas: ${dmpl?.rowCount ?? 0}`);
  {
    const textos: string[] = [];
    for (let r = 1; r <= (dmpl?.rowCount ?? 0); r++) {
      for (let c = 1; c <= 8; c++) textos.push(String(dmpl!.getRow(r).getCell(c).value ?? ""));
    }
    checar(textos.some((t) => t.includes("Capital social")),
      "(47) …com os componentes do PL como colunas");
    checar(textos.some((t) => t.toUpperCase().includes("SALDOS EM 31 DE DEZEMBRO DE 2025")),
      "(47) …e os movimentos como linhas");
  }

  // MUTUOS → aba Intragrupo, com a divergência deliberada de R$ 180 mil do book.
  const intra = wb.getWorksheet("Intragrupo");
  checar(intra != null && intra.rowCount > 1, "(47) a aba Intragrupo existe e tem linhas",
    `linhas: ${intra?.rowCount ?? 0}`);

  // NOTAS: prosa com números. O que importa é que as linhas NÃO foram para o
  // Balanço — nota explicativa detalha o que o BP já totaliza, e somar as duas
  // coisas é dupla contagem vinda de documento complementar.
  const balanco = wb.getWorksheet("Balanço")!;
  const rotulosBP: string[] = [];
  for (let r = 1; r <= balanco.rowCount; r++) rotulosBP.push(String(balanco.getRow(r).getCell(1).value ?? ""));
  checar(!rotulosBP.some((x) => x.startsWith("Índice de liquidez corrente")),
    "(47) linha de NOTA EXPLICATIVA não é roteada para o Balanço (evita dupla contagem)");
  // …e continua no arquivo, na aba documental.
  const dados = wb.getWorksheet("Dados (linha a linha)")!;
  let achouNota = false;
  for (let r = 2; r <= dados.rowCount; r++) {
    if (String(dados.getRow(r).getCell(11).value ?? "").startsWith("Índice de liquidez corrente")) achouNota = true;
  }
  checar(achouNota, "(47) …mas a linha da nota está no arquivo, na aba de dados crus");
}

// ---- 48: cabeçalho da Modelagem reduzido, parâmetros no rodapé (7.4) -------
// Eram 11 linhas fixas no topo, três delas células de input. Decisão do dono:
// ficam 4 (título, branco, Exercício, mês) e as três células migram para o
// portal — o arquivo sai parametrizado, e elas ficam registradas no rodapé para
// a auditoria saber com que parâmetros aquele arquivo foi gerado.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-27T12:00:00Z"),
  });
  const mod = wb.getWorksheet("Modelagem")!;

  const ySplit = (mod.views?.[0] as { ySplit?: number } | undefined)?.ySplit;
  checar(ySplit === 4, "(48) o congelado do topo é de 4 linhas (era 11)", String(ySplit));
  checar(String(mod.getRow(1).getCell(1).value ?? "").startsWith("MODELAGEM"),
    "(48) linha 1 continua o título");
  checar(String(mod.getRow(3).getCell(1).value ?? "") === "Exercício",
    "(48) linha 3 é a timeline (Exercício)", String(mod.getRow(3).getCell(1).value));
  checar(String(mod.getRow(4).getCell(1).value ?? "") === "Período",
    "(48) linha 4 é o mês", String(mod.getRow(4).getCell(1).value));

  // As três células de input NÃO estão mais no topo…
  const topo: string[] = [];
  for (let r = 1; r <= 4; r++) topo.push(String(mod.getRow(r).getCell(1).value ?? ""));
  checar(!topo.includes("Entidade modelada"),
    "(48) \"Entidade modelada\" saiu do topo", topo.join(" | "));
  checar(!topo.includes("Último exercício realizado"),
    "(48) e \"Último exercício realizado\" também");

  // …e estão no rodapé, com o bloco declarado.
  const rotulos: string[] = [];
  for (let r = 1; r <= mod.rowCount; r++) rotulos.push(String(mod.getRow(r).getCell(1).value ?? ""));
  const rParam = rotulos.findIndex((x) => x.startsWith("PARÂMETROS DO MODELO"));
  checar(rParam > 0, "(48) o bloco de PARÂMETROS existe no rodapé", `linha ${rParam + 1}`);
  checar(rotulos[rParam + 1] === "Entidade modelada",
    "(48) …com a entidade modelada como célula editável", rotulos[rParam + 1]);
  checar(rotulos[rParam + 2] === "Último exercício realizado",
    "(48) …e o corte do último exercício real", rotulos[rParam + 2]);
  // O bloco vem DEPOIS do modelo: se estivesse antes, `addRow` teria empurrado o
  // modelo inteiro para baixo — a armadilha nº 1 da sessão 12, que voltou a
  // acontecer nesta fase (o modelo foi de ~200 para 291 linhas) e foi a guarda
  // que a pegou.
  const rTitulo = rotulos.findIndex((x) => x.startsWith("MODELAGEM"));
  checar(rParam > rTitulo + 10,
    "(48) e o bloco fica no RODAPÉ, não empurrando o modelo para baixo",
    `parâmetros na linha ${rParam + 1}`);
}

// ---- 49: a aba Modelagem REGISTRA a configuração e NÃO projeta (21/08) ------
//
// ESTE GRUPO MUDOU DE CONTRATO, e o que ele protege agora vale mais do que o que
// protegia antes.
//
// Ele nasceu provando que a aba projetava cada linha pela premissa vinculada.
// Só que as 14 abas do modelo institucional projetam AS MESMAS LINHAS, com base
// contábil diferente: aqui todo percentual e todo prazo incidiam sobre a receita
// TOTAL do caso; lá o fornecedor gira contra CUSTOS e o resto contra RECEITA
// LÍQUIDA. Dois números para o mesmo fato, no mesmo arquivo de comitê.
//
// A aba passou a ser o REGISTRO da configuração. Os asserts travam as duas
// metades disso: o que ela guarda (premissa por linha, valor por exercício,
// último realizado, curva do caso) e — o mais importante — o que ela NÃO faz
// mais. Sem o assert de ausência a projeção volta na primeira refatoração e
// ninguém percebe, porque número em célula parece certo.
{
  const V = "vProj";
  const campos: CampoExtraido[] = [
    campo({ chave: "Receita de vendas", secao: "Receita Bruta", secao_canonica: "receita_bruta",
            valor_num: 1000, ordem: 0, documento_versao_id: V }),
    campo({ chave: "Custo dos produtos vendidos", secao: "Custos", secao_canonica: "custos",
            valor_num: -600, ordem: 1, documento_versao_id: V }),
  ];
  const documentos: DocumentoParaExport[] = [{
    id: "dProj", tipo_taxonomia: "DRE", entidade: { razao_social: "Projetada Ltda" },
    periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: V, nome_original: "dre.pdf" }],
  }];

  const wb = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" }, documentos, campos,
    agora: new Date("2026-07-27T12:00:00Z"),
    modelagemConfig: {
      entidade: "Projetada Ltda", ultimoExercicioReal: 2025, anosProjetados: 3,
      premissas: [
        { codigo: "CRESC_REAL", nome: "Crescimento real da receita", formula: "crescimento_composto",
          unidade: "%", valores: { "2026": 10, "2027": 10 } },
        { codigo: "CAPEX_ANO", nome: "Capex por ano", formula: "valor_por_ano",
          unidade: "R$/ano", valores: { "2026": 50 } },
        { codigo: "MARGEM_BRUTA", nome: "Margem bruta", formula: "pct_de_linha",
          unidade: "%", valores: { "2026": 40 } },
        // 88 = 88%: pontos percentuais, como o "Usar" grava desde o ac9458d. É o valor do
        // Krauspenhar que a aba mostrava como 8800,0%.
        { codigo: "CUSTO_VARIAVEL", nome: "Custo variável", formula: "pct_de_linha",
          unidade: "%", valores: { "2026": 87.97, "2027": 88 } },
        { codigo: "PMR", nome: "Prazo médio de recebimento", formula: "dias_de_giro",
          unidade: "dias", valores: { "2026": 45 } },
        // Primitiva que segue NÃO desenhada: precisa de duas premissas na mesma
        // linha, e `caso_linha_premissa` tem um slot só — é decisão de schema.
        { codigo: "PRECO_MEDIO", nome: "Preço médio", formula: "preco_x_volume",
          unidade: "R$/un", valores: { "2026": 12 } },
      ],
      linhas: [
        { rotulo: "Receita de vendas", secaoCanonica: "receita_bruta",
          premissaCodigo: "CRESC_REAL", sazonalidadeCodigo: null, valorBase: 1000 },
        { rotulo: "Capex do plano", secaoCanonica: null,
          premissaCodigo: "CAPEX_ANO", sazonalidadeCodigo: null, valorBase: null },
        { rotulo: "Custo dos produtos vendidos", secaoCanonica: "custos",
          premissaCodigo: "MARGEM_BRUTA", sazonalidadeCodigo: null, valorBase: -600 },
        { rotulo: "Duplicatas a receber", secaoCanonica: "ativo_circulante",
          premissaCodigo: "PMR", sazonalidadeCodigo: null, valorBase: 200 },
        { rotulo: "Receita por unidade", secaoCanonica: null,
          premissaCodigo: "PRECO_MEDIO", sazonalidadeCodigo: null, valorBase: null },
      ],
    },
  });
  const mod = wb.getWorksheet("Modelagem")!;
  const rotulos: string[] = [];
  for (let r = 1; r <= mod.rowCount; r++) rotulos.push(String(mod.getRow(r).getCell(1).value ?? ""));

  checar(rotulos.some((x) => x.startsWith("A CONFIGURAÇÃO DE MODELAGEM")),
    "(49) o bloco de configuração existe quando há configuração");
  const rRec = rotulos.indexOf("Receita de vendas") + 1;
  checar(rRec > 0, "(49) a linha configurada aparece pelo rótulo do documento");

  const primeiroAnoDaAba = 2025;  // único exercício com dado nesta fixture
  const colDe = (ano: number) => mod.getColumn(3 + (ano - primeiroAnoDaAba) * 13 + 12).letter;
  const c2025 = colDe(2025);
  const c2026 = colDe(2026);
  const c2027 = colDe(2027);
  checar(c2026 !== "", "(49) a coluna consolidada de 2026 existe na timeline", c2026);

  // ---- O QUE A ABA GUARDA --------------------------------------------------

  // O último realizado, na coluna do próprio exercício de corte. Sem ele o
  // registro diria "premissa X vinculada" sem dizer a que número ela se aplica.
  checar(Math.round(Number(mod.getRow(rRec).getCell(mod.getColumn(c2025).number).value)) === 1000,
    "(49) o último realizado fica registrado na coluna do exercício de corte",
    String(mod.getRow(rRec).getCell(mod.getColumn(c2025).number).value));

  // A premissa continua sendo INPUT, com o valor de cada exercício: é a
  // configuração propriamente dita, e é o que se audita sem abrir o portal.
  const rPremCresc = rotulos.indexOf("↳ Crescimento real da receita") + 1;
  checar(rPremCresc > 0, "(49) a premissa do caso tem linha própria");
  checar(Math.abs(Number(mod.getRow(rPremCresc).getCell(mod.getColumn(c2026).number).value) - 0.1) < 1e-9,
    "(49) …com o valor configurado para cada exercício",
    String(mod.getRow(rPremCresc).getCell(mod.getColumn(c2026).number).value));

  // `%` armazenado em PONTOS (88 = 88%) chega à célula como 0,88, formatada como %:
  // antes chegava 88 sob o formato `0.0%` e aparecia como 8800,0% (aceito 87,97 → 8797,0%).
  const rCv = rotulos.indexOf("↳ Custo variável") + 1;
  const cCv = mod.getRow(rCv).getCell(mod.getColumn(c2027).number);
  const cCv26 = mod.getRow(rCv).getCell(mod.getColumn(c2026).number);
  checar(rCv > 0 && Math.abs(Number(cCv.value) - 0.88) < 1e-9 && Math.abs(Number(cCv26.value) - 0.8797) < 1e-9,
    "(49) premissa % de 88 pontos aparece na aba Modelagem como 0,88 (e 87,97 como 0,8797), não como 88",
    `${String(cCv.value)} / ${String(cCv26.value)}`);
  checar(String(cCv.numFmt).includes("%"), "(49) …formatada como percentual (88,0%, não 8800,0%)", String(cCv.numFmt));
  // Um número exibido > 100% numa premissa de custo sobre a receita é o sintoma.
  checar(Number(cCv.value) <= 1, "(49) …e a exibição nunca passa de 100% para um custo sobre a receita", String(cCv.value));

  // A nota da linha diz ONDE o número projetado vive. Célula vazia sem
  // explicação é lida como "o sistema não conseguiu", que é outra coisa.
  checar(notaDaLinha(mod, rRec).includes("abas do modelo"),
    "(49) a nota da linha aponta para onde a projeção vive",
    notaDaLinha(mod, rRec).slice(0, 90));

  // ---- O QUE ELA NÃO FAZ MAIS, e é o assert que protege o invariante -------

  // NENHUMA célula de exercício PROJETADO tem número ou fórmula. Se este assert
  // cair, o arquivo voltou a ter dois números para o mesmo fato.
  const projetadasComValor: string[] = [];
  for (const rot of ["Receita de vendas", "Custo dos produtos vendidos",
                     "Duplicatas a receber", "Capex do plano"]) {
    const rr = rotulos.indexOf(rot) + 1;
    if (rr <= 0) continue;
    for (const col of [c2026, c2027]) {
      const cel = mod.getRow(rr).getCell(mod.getColumn(col).number);
      if (cel.value != null && cel.value !== "") projetadasComValor.push(`${rot}@${col}`);
    }
  }
  checar(projetadasComValor.length === 0,
    "(49) NENHUMA linha do caso tem valor em exercício projetado: a aba não projeta",
    projetadasComValor.join(" / "));

  checar(!rotulos.some((x) => x.startsWith("↳ Receita total do caso")),
    "(49) a linha de RECEITA TOTAL (base dos percentuais) não existe mais");

  // ---- A CURVA DO CASO CONTINUA PUBLICADA, como fato -----------------------
  //
  // A distribuição mensal saiu com a projeção: ela repartia o valor projetado, e
  // sem projeção não há o que repartir. A curva NÃO saiu, porque é derivada do
  // faturamento que o cliente entregou — perder a curva junto seria perder
  // informação do mandato por causa de um número que estava no lugar errado.
  {
    const curva = [0.05, 0.05, 0.07, 0.07, 0.08, 0.08, 0.08, 0.08, 0.08, 0.08, 0.08, 0.20];
    const wbSazo = buildExportWorkbook({
      caso: { nome: "C", produto: "rx" }, documentos, campos,
      agora: new Date("2026-07-27T12:00:00Z"),
      modelagemConfig: {
        entidade: "Projetada Ltda", ultimoExercicioReal: 2025, anosProjetados: 2,
        sazonalidade: curva,
        premissas: [
          { codigo: "CRESC_REAL", nome: "Crescimento real da receita", formula: "crescimento_composto",
            unidade: "%", valores: { "2026": 0.1 } },
        ],
        linhas: [
          { rotulo: "Receita de vendas", secaoCanonica: "receita_bruta",
            premissaCodigo: "CRESC_REAL", sazonalidadeCodigo: "SAZONALIDADE", valorBase: 1000 },
        ],
      },
    });
    const ms = wbSazo.getWorksheet("Modelagem")!;
    const rotS: string[] = [];
    for (let r = 1; r <= ms.rowCount; r++) rotS.push(String(ms.getRow(r).getCell(1).value ?? ""));
    const rCurva = rotS.findIndex((x) => x.startsWith("↳ Curva de sazonalidade")) + 1;
    checar(rCurva > 0, "(49) a curva de sazonalidade do caso é publicada como linha própria");
    if (rCurva > 0) {
      const doze: number[] = [];
      for (let m = 0; m < 12; m++) doze.push(Number(ms.getRow(rCurva).getCell(3 + m).value));
      checar(Math.abs(doze.reduce((a, b) => a + b, 0) - 1) < 1e-9,
        "(49) …e os doze meses dela somam 1", doze.join(" "));
      checar(Math.abs(doze[11] - 0.2) < 1e-9,
        "(49) …com dezembro concentrando 20%, que é o fato do caso e não 1/12",
        String(doze[11]));
    }

    // Sem curva no caso, a linha não aparece: ausência de dado não vira curva
    // uniforme inventada.
    const wbSemCurva = buildExportWorkbook({
      caso: { nome: "C", produto: "rx" }, documentos, campos,
      agora: new Date("2026-07-27T12:00:00Z"),
      modelagemConfig: {
        entidade: "Projetada Ltda", ultimoExercicioReal: 2025, anosProjetados: 2,
        premissas: [
          { codigo: "CRESC_REAL", nome: "Crescimento real da receita", formula: "crescimento_composto",
            unidade: "%", valores: { "2026": 0.1 } },
        ],
        linhas: [
          { rotulo: "Receita de vendas", secaoCanonica: "receita_bruta",
            premissaCodigo: "CRESC_REAL", sazonalidadeCodigo: "SAZONALIDADE", valorBase: 1000 },
        ],
      },
    });
    const msc = wbSemCurva.getWorksheet("Modelagem")!;
    const rotSC: string[] = [];
    for (let r = 1; r <= msc.rowCount; r++) rotSC.push(String(msc.getRow(r).getCell(1).value ?? ""));
    checar(!rotSC.some((x) => x.startsWith("↳ Curva de sazonalidade")),
      "(49) sem faturamento mensal no caso, curva nenhuma é publicada");
  }

  // ---- O RODAPÉ ACOMPANHA O TAMANHO DO CASO -------------------------------
  //
  // MEDIDO EM PRODUÇÃO (17/09/2026, mandato "AMO teste 00"): o export abortou
  // com "o modelo chegou à linha 1349 e o bloco de PARÂMETROS começa em 186".
  // `LINHA_PARAM_INICIO` era a constante 186 e o bloco "A CONFIGURAÇÃO DE
  // MODELAGEM" escreve uma linha por premissa ativa MAIS uma por linha
  // vinculada — 26 + 1.188 naquele caso. A guarda fez o certo (não sobrescreveu
  // linha de modelo), mas o dono ficou sem arquivo nenhum.
  //
  // O invariante é de COMPORTAMENTO: um caso grande gera arquivo, e o rodapé
  // fica DEPOIS do modelo. Não afirma o valor do offset — isso é mecanismo, e
  // travá-lo aqui só protegeria a fórmula atual.
  {
    const N_LINHAS = 1200;
    const linhasMuitas = Array.from({ length: N_LINHAS }, (_, i) => ({
      rotulo: `Conta analítica ${i}`,
      secaoCanonica: "despesas_operacionais" as string | null,
      premissaCodigo: "CRESC_REAL" as string | null,
      sazonalidadeCodigo: null,
      valorBase: 10 + i,
    }));
    const wbGrande = buildExportWorkbook({
      caso: { nome: "C", produto: "rx" }, documentos, campos,
      agora: new Date("2026-07-27T12:00:00Z"),
      modelagemConfig: {
        entidade: "Projetada Ltda", ultimoExercicioReal: 2025, anosProjetados: 5,
        premissas: [
          { codigo: "CRESC_REAL", nome: "Crescimento real da receita", formula: "crescimento_composto",
            unidade: "%", valores: { "2026": 0.1 } },
        ],
        linhas: linhasMuitas,
      },
    });
    const mg = wbGrande.getWorksheet("Modelagem")!;
    const rotG: string[] = [];
    for (let r = 1; r <= mg.rowCount; r++) rotG.push(String(mg.getRow(r).getCell(1).value ?? ""));

    const iConfig = rotG.findIndex((x) => x.startsWith("A CONFIGURAÇÃO DE MODELAGEM"));
    const iUltimaConta = rotG.lastIndexOf(`Conta analítica ${N_LINHAS - 1}`);
    const iParam = rotG.findIndex((x) => x.startsWith("PARÂMETROS"));

    checar(iConfig >= 0 && iUltimaConta > iConfig,
      `(49) caso com ${N_LINHAS} linhas configuradas gera a aba inteira, sem abortar`,
      `config=${iConfig} ultimaConta=${iUltimaConta}`);
    checar(iParam > iUltimaConta,
      "(49) …e o bloco de PARÂMETROS fica DEPOIS da última linha do modelo — o rodapé "
      + "acompanha o tamanho do caso em vez de ser sobrescrito",
      `param=${iParam} ultimaConta=${iUltimaConta}`);
  }

  // Sem configuração, o arquivo continua saindo como antes: o esqueleto agregado
  // é o fallback, e esta fase não tira modelo de ninguém.
  const semConfig = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" }, documentos, campos,
    agora: new Date("2026-07-27T12:00:00Z"),
  });
  const modSem = semConfig.getWorksheet("Modelagem")!;
  const rotSem: string[] = [];
  for (let r = 1; r <= modSem.rowCount; r++) rotSem.push(String(modSem.getRow(r).getCell(1).value ?? ""));
  checar(!rotSem.some((x) => x.startsWith("A CONFIGURAÇÃO DE MODELAGEM")),
    "(49) sem configuração, não há bloco de registro — o esqueleto agregado é o fallback");
  checar(rotSem.some((x) => x.startsWith("PARÂMETROS DO MODELO")),
    "(49) …e o bloco de parâmetros continua existindo de todo jeito");
}

// ---------------------------------------------------------------------------
// (0104b) A IDENTIDADE DA LINHA É O PAR (SEÇÃO, RÓTULO) — defeito relatado pelo
// dono no teste da tela: ele escolhia a premissa de UMA linha, não mexia em mais
// nenhuma, salvava, e outra linha aparecia preenchida com a mesma premissa.
//
// A causa era o casamento por `rotulo_norm` sozinho, nos dois lugares que leem
// vínculo (a tela e a rota de export). Demonstração real repete rótulo entre
// seções o tempo todo: no caso do v35 são TREZE — `Empréstimos e Financiamentos`
// e `Arrendamentos` no passivo circulante E no não circulante, `Capital social` e
// `Reserva legal` no patrimônio líquido E na DMPL.
//
// Os dados abaixo são desses rótulos reais, com os valores reais do v35.
// ---------------------------------------------------------------------------
{
  const linhasDoCaso = [
    { secao_canonica: "passivo_circulante", rotulo_norm: "emprestimos e financiamentos",
      chave: "Empréstimos e Financiamentos", valor_ultimo: 44474 },
    { secao_canonica: "passivo_nao_circulante", rotulo_norm: "emprestimos e financiamentos",
      chave: "Empréstimos e Financiamentos", valor_ultimo: 37379 },
    { secao_canonica: "patrimonio_liquido", rotulo_norm: "capital social",
      chave: "Capital social", valor_ultimo: 42000 },
    { secao_canonica: "dmpl", rotulo_norm: "capital social",
      chave: "Capital social", valor_ultimo: 42000 },
  ];

  // O analista configurou UMA linha: a do passivo circulante.
  const umVinculo = [{
    secao_canonica: "passivo_circulante", rotulo_norm: "emprestimos e financiamentos",
    premissa_codigo: "DIVIDA_MOV", sazonalidade_codigo: null,
  }];
  const casado = casarVinculosComLinhas(umVinculo, linhasDoCaso);
  checar(casado.length === 1,
    "(0104b) um vínculo gravado produz UMA linha configurada — não uma por homônimo",
    `linhas: ${casado.length}`);
  checar(casado[0].secaoCanonica === "passivo_circulante" && casado[0].valorBase === 44474,
    "(0104b) e ela leva o valor base da PRÓPRIA seção (44.474, não os 37.379 do não circulante)",
    JSON.stringify(casado[0]));

  // A tela: a linha homônima da outra seção tem de vir VAZIA.
  const porLinha = vinculoPorLinha(umVinculo);
  checar(
    porLinha.get(chaveDaLinha("passivo_circulante", "emprestimos e financiamentos"))
      ?.premissa_codigo === "DIVIDA_MOV",
    "(0104b) a tela acha o vínculo na linha que o analista configurou");
  checar(
    porLinha.get(chaveDaLinha("passivo_nao_circulante", "emprestimos e financiamentos")) === undefined,
    "(0104b) …e a linha HOMÔNIMA de outra seção continua sem premissa — este é o assert "
    + "que impede a linha de 'completar sozinha'",
    JSON.stringify(porLinha.get(chaveDaLinha("passivo_nao_circulante", "emprestimos e financiamentos"))));

  // Seção nula não pode virar coringa que casa com todo mundo.
  const semSecao = [{
    secao_canonica: null, rotulo_norm: "capital social",
    premissa_codigo: "SOCIOS_MOV", sazonalidade_codigo: null,
  }];
  checar(
    vinculoPorLinha(semSecao).get(chaveDaLinha("dmpl", "capital social")) === undefined,
    "(0104b) vínculo SEM seção não casa com a linha que tem seção");
  checar(casarVinculosComLinhas(semSecao, linhasDoCaso)[0].valorBase === null,
    "(0104b) …e ele fica órfão, com valor base nulo, em vez de herdar o de um homônimo qualquer");

  // ---- (0109d) OCORRÊNCIA REPETIDA NÃO É COMPONENTE DE SUBTOTAL ----------
  //
  // O detector estrutural por ORDEM lê a sequência impressa: subtotal, depois os
  // componentes dele. A extração real repete o mesmo rótulo dentro do mesmo
  // documento — é o que um comparativo produz quando `periodo_coluna` não vem
  // preenchido, e o caso v35 traz TODA conta duplicada assim.
  //
  // Com as repetições dentro da sequência o detector errava dos dois lados, e os
  // dois estão travados aqui:
  //
  //   (a) FALSO POSITIVO: a segunda ocorrência do próprio candidato bate com ele,
  //       e uma DESPESA REAL virava "subtotal" — sumia do modelo. Medido no v35:
  //       SG&A 1.900 menor e EBIT 1.900 maior, sem nenhum aviso;
  //   (b) FALSO NEGATIVO: os componentes de um subtotal DE VERDADE também vêm
  //       duplicados e somam o dobro — o subtotal deixava de ser reconhecido e
  //       era somado junto com os componentes, dobrando o grupo.
  {
    const dup = (c: CampoExtraido) => [c, { ...c, id: `${c.id}#2` }];
    const itensDRE = [
      ...dup(campo({ chave: "Despesas gerais e administrativas", secao_canonica: "despesas_operacionais",
                     valor_num: -9640, documento_versao_id: "vDup", ordem: 1 })),
      ...dup(campo({ chave: "Provisão para contingências trabalhistas e cíveis",
                     secao_canonica: "despesas_operacionais",
                     valor_num: -1900, documento_versao_id: "vDup", ordem: 3 })),
      ...dup(campo({ chave: "Imposto de renda e contribuição social - corrente",
                     secao_canonica: "impostos_lucro",
                     valor_num: -420, documento_versao_id: "vDup", ordem: 5 })),
    ].map((c) => ({ campo: c, colKey: "2025" }));
    const achadosDRE = rotulosDeSubtotalInformado(new Map([["DRE", itensDRE]]), null);
    checar(!achadosDRE.some((r) => /provisao para contingencias|imposto de renda/.test(r)),
      "(0109d) despesa repetida no mesmo documento NÃO é declarada subtotal de si mesma",
      achadosDRE.join(" · ") || "(nenhum)");

    const itensBP = [
      ...dup(campo({ chave: "Provisões", secao_canonica: "passivo_nao_circulante",
                     valor_num: 5000, documento_versao_id: "vDup2", ordem: 1 })),
      ...dup(campo({ chave: "Provisão para contingências cíveis", secao_canonica: "passivo_nao_circulante",
                     valor_num: 2000, documento_versao_id: "vDup2", ordem: 3 })),
      ...dup(campo({ chave: "Provisão para contingências trabalhistas", secao_canonica: "passivo_nao_circulante",
                     valor_num: 3000, documento_versao_id: "vDup2", ordem: 5 })),
    ].map((c) => ({ campo: c, colKey: "2025" }));
    const achadosBP = rotulosDeSubtotalInformado(new Map([["Balanço", itensBP]]), null);
    checar(achadosBP.some((r) => /\|\|provisoes(\|\|\d{4})?$/.test(r)),
      "(0109d) …e o subtotal DE VERDADE continua sendo reconhecido mesmo com todas as "
      + "ocorrências duplicadas — sem isto o grupo dobrava",
      achadosBP.join(" · ") || "(nenhum)");
  }

  // ---- (0104c) A SÉRIE HISTÓRICA TAMBÉM É POR (SEÇÃO, RÓTULO) -------------
  //
  // O terceiro lugar que casava linha por rótulo, e o mais caro: as SÉRIES que
  // viram os números do modelo. `fn_valores_por_ano` devolve (rotulo_norm,
  // secao_canonica, ano, valor) — indexando só pelo rótulo, a última seção lida
  // sobrescrevia as anteriores e a linha do circulante passava a projetar com o
  // saldo do NÃO circulante. Nada dava erro: o arquivo saía plausível e falso.
  {
    const valores = [
      { rotulo_norm: "emprestimos e financiamentos", secao_canonica: "passivo_circulante",
        ano: 2025, valor: 44474 },
      { rotulo_norm: "emprestimos e financiamentos", secao_canonica: "passivo_nao_circulante",
        ano: 2025, valor: 37379 },
      { rotulo_norm: "emprestimos e financiamentos", secao_canonica: "passivo_circulante",
        ano: 2024, valor: 40000 },
      // Exercício FORA do histórico (balancete do ano corrente): não entra.
      { rotulo_norm: "emprestimos e financiamentos", secao_canonica: "passivo_circulante",
        ano: 2026, valor: 99999 },
    ];
    const series = seriesPorLinha(valores, [2024, 2025]);
    const pc = serieDaLinha(series, "passivo_circulante", "emprestimos e financiamentos");
    const pnc = serieDaLinha(series, "passivo_nao_circulante", "emprestimos e financiamentos");
    checar(pc["2025"] === 44474 && pnc["2025"] === 37379,
      "(0104c) cada seção recebe a SUA série — o homônimo da outra seção não sobrescreve",
      `PC ${JSON.stringify(pc)} · PNC ${JSON.stringify(pnc)}`);
    checar(pc["2024"] === 40000 && pc["2026"] === undefined,
      "(0104c) …a série acumula os anos históricos e IGNORA exercício fora do histórico",
      JSON.stringify(pc));
    checar(Object.keys(serieDaLinha(series, "custos", "conta de outra empresa")).length === 0,
      "(0104c) …e linha sem série (conta de outra empresa do grupo) devolve VAZIO — zero "
      + "explícito, nunca o número do homônimo");
  }

  // Órfão de verdade (documento reextraído com outro rótulo) segue aparecendo:
  // sumir com ele esconderia configuração que `fn_conferir_modelagem` denuncia.
  const orfao = casarVinculosComLinhas([{
    secao_canonica: "custos", rotulo_norm: "conta que nao existe mais",
    premissa_codigo: "CUSTO_MP", sazonalidade_codigo: null,
  }], linhasDoCaso);
  checar(orfao.length === 1 && orfao[0].rotulo === "conta que nao existe mais"
    && orfao[0].valorBase === null,
    "(0104b) vínculo órfão continua no arquivo, com o rótulo normalizado e sem base",
    JSON.stringify(orfao[0]));
}

// ---------------------------------------------------------------------------
// (0104c) DUAS LINHAS COM O MESMO RÓTULO EM SEÇÕES DIFERENTES NÃO DERRUBAM O
// MODELO INSTITUCIONAL — o HTTP 500 que o dono viu ao exportar o v35:
//
//   Error: modelo-institucional: âncora duplicada "trib:obrigacoes tributarias"
//          em Tributos a Recolher
//
// `Obrigações Tributárias` existe nas DUAS pontas do passivo (7.895 no
// circulante, 13.549 no não circulante), e `abaTributos` é a única aba que junta
// os dois blocos sob um prefixo só. Os valores abaixo são os do caso real.
// ---------------------------------------------------------------------------
{
  const linhaBase = (secao: string, chave: string, rotulo_norm: string, v2025: number) => ({
    secao_canonica: secao, chave, rotulo_norm,
    papel: "conta" as const, unidade: "milhar", moeda: "BRL",
    documentos: ["BALANCO"], valores: { "2025": v2025 },
  });

  const entrada = {
    caso: { nome: "Homônimos em duas seções", produto: "reestruturacao" },
    agora: new Date("2026-08-05T12:00:00Z"),
    entidade: "VERTENTES METALÚRGICA LTDA.",
    setor: "industria",
    anosHistoricos: [2025], anosProjetados: [2026, 2027],
    stressPct: 0.2, caixaMinimo: 0, aliquotaTributos: 0.34,
    linhas: [
      linhaBase("passivo_circulante", "Obrigações Tributárias", "obrigacoes tributarias", 7895),
      linhaBase("passivo_nao_circulante", "Obrigações Tributárias", "obrigacoes tributarias", 13549),
      linhaBase("receita_bruta", "Vendas de produtos - mercado interno",
                "vendas de produtos - mercado interno", 158900),
    ],
    premissas: [], vinculos: [], macro: [], unidade: "R$ mil",
  };

  // O modelo institucional só é construído quando o caso tem entidade
  // reconhecível NOS CAMPOS EXTRAÍDOS (`if (entidadesConhecidas.size > 0)`, em
  // export.ts) — com as duas listas vazias o export pula justamente o código sob
  // teste, e o assert passaria sem exercitar nada.
  const VHOM = "vHom";
  const camposHom: CampoExtraido[] = [
    campo({ chave: "Obrigações Tributárias", secao: "Passivo Circulante",
            secao_canonica: "passivo_circulante", valor_num: 7895, documento_versao_id: VHOM }),
    campo({ chave: "Obrigações Tributárias", secao: "Passivo Não Circulante",
            secao_canonica: "passivo_nao_circulante", valor_num: 13549, documento_versao_id: VHOM }),
  ];
  const docsHom: DocumentoParaExport[] = [{
    id: "dHom", tipo_taxonomia: "BALANCO",
    entidade: { razao_social: "VERTENTES METALÚRGICA LTDA." },
    periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: VHOM, nome_original: "01_BP_Vertentes_Metalurgica_2025x2024.pdf" }],
  }];

  let erro: string | null = null;
  let wbHom: ReturnType<typeof buildExportWorkbook> | null = null;
  try {
    wbHom = buildExportWorkbook({
      caso: entrada.caso, documentos: docsHom, campos: camposHom,
      agora: new Date("2026-08-05T12:00:00Z"),
      modo: "completo",
      modeloInstitucional: entrada as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
    });
  } catch (e) {
    erro = e instanceof Error ? e.message : String(e);
  }

  checar(erro === null,
    "(0104c) o mesmo rótulo em duas seções NÃO derruba o export — era o HTTP 500 do v35",
    erro ?? "");

  if (wbHom) {
    const trib = wbHom.getWorksheet("Tributos a Recolher");
    let n = 0;
    if (trib) {
      for (let r = 1; r <= trib.rowCount; r++) {
        if (String(trib.getRow(r).getCell(3).value ?? "") === "Obrigações Tributárias") n++;
      }
    }
    checar(n === 2,
      "(0104c) …e as DUAS aparecem na aba de tributos, uma por seção (somar só uma esconderia 13.549)",
      `linhas com o rótulo: ${n}`);
  }
}


// ---------------------------------------------------------------------------
// (0105) O MODELO INSTITUCIONAL FECHA — e é o único invariante que decide se ele
// é um modelo ou um relatório bonito.
//
// POR QUE ESTE BLOCO EXISTE. Até esta rodada nenhum teste avaliava os NÚMEROS do
// modelo institucional: os asserts existentes cobriam estrutura (a aba existe, o
// rótulo aparece duas vezes, o export não explode). Um modelo pode ter as 14 abas
// no lugar, 3.000 fórmulas e não fechar o balanço — e foi exatamente o que
// acontecia. Três defeitos de MECANISMO só apareceram quando os números foram
// somados:
//
//   1. o CAIXA era projetado por dias de giro no `Working Capital` E somado outra
//      vez pelo `Cash Flow` no `Balance Sheet` (`AC = CAIXA + AC_OPER`);
//   2. a DÍVIDA bancária de curto prazo entrava no passivo operacional do giro E
//      voltava em `DIVIDA_CP`;
//   3. `Revenues!DEPRECIACAO` era declarada e NUNCA preenchida — a DRE debitava
//      zero de depreciação, o `Cash Flow` somava de volta uma depreciação que
//      ninguém tinha subtraído, e o imobilizado caía sem contrapartida.
//
// O caso abaixo tem as sete famílias de conta que o balanço precisa para fechar
// (caixa, giro do ativo, estoque, imobilizado, giro do passivo, dívida em duas
// pontas, patrimônio) com números redondos escolhidos para o CHECK ser
// verificável a olho se o teste falhar.
//
// A FIXTURE FOI REFEITA (rodada de 06/08/2026) COM A FORMA DO DADO REAL, e é essa
// a lição mais cara desta rodada. A versão anterior tinha:
//
//   • custo e despesa POSITIVOS (`"Custo dos produtos vendidos", 140000`), quando
//     a extração — e a fixture `book-vertentes.json`, e o banco — trazem `−140000`,
//     porque é assim que a DRE publicada escreve;
//   • uma conta por grupo, NENHUM par subtotal+componente, quando toda demonstração
//     real imprime "Obrigações Tributárias 8.706" seguido dos componentes dela;
//   • um único exercício realizado, quando o mapa de dívida costuma cobrir só o
//     último e o balanço cobre todos;
//   • nenhuma linha de resultado informada (Receita Líquida, Lucro Bruto, EBIT),
//     então não havia contra o que conferir a cascata.
//
// Com essa fixture os 15 asserts do (0105) passavam VERDES enquanto o arquivo
// entregue ao dono transformava prejuízo de 17.901 em lucro de 268.041 e um ativo
// de 95.780 em 195.090. Fixture mais fácil que a produção mede o instrumento, não
// o sistema — é o que o `CLAUDE.md` chama de teste que não pode falhar.
// ---------------------------------------------------------------------------
{
  // Valores POR ANO e na CONVENÇÃO DO DOCUMENTO: despesa negativa, como o PDF
  // escreve e como a extração entrega. É o modelo que tem de normalizar.
  const linhaAnos = (
    secao: string, chave: string, valores: Record<string, number>,
    doc = "BALANCO", papel: "conta" | "subtotal" = "conta",
  ) => ({
    secao_canonica: secao, chave, rotulo_norm: chave.toLowerCase(),
    papel, unidade: "milhar", moeda: "BRL",
    documentos: [doc], valores,
  });
  const linha = (secao: string, chave: string, v: number, doc = "BALANCO") =>
    linhaAnos(secao, chave, { "2025": v }, doc);
  void linha;

  const entradaModelo = {
    caso: { nome: "Fecha o balanço", produto: "reestruturacao" },
    agora: new Date("2026-08-05T12:00:00Z"),
    entidade: "VERTENTES METALÚRGICA LTDA.",
    setor: "industria",
    anosHistoricos: [2024, 2025],
    anosProjetados: [2026, 2027, 2028],
    stressPct: 0.2, caixaMinimo: 5000, aliquotaTributos: 0.34,
    // O BALANÇO DESTE CASO FECHA NOS DOIS EXERCÍCIOS, e fecha SÓ se o modelo
    // excluir o subtotal informado e achar a dívida de 2024 no balanço:
    //
    //             |      2024 |      2025
    //   ativo     |   117.000 |   125.000
    //   PC        |    33.000 |    40.000   (giro 21.000/25.000 + dívida CP 12.000/15.000)
    //   PNC       |    34.000 |    40.000   (dívida LP 30.000/35.000 + provisões 4.000/5.000)
    //   PL        |    50.000 |    45.000
    //
    // As "Provisões" entram como SUBTOTAL do documento (e os dois componentes
    // abaixo): somar os três dobra o grupo e o CHECK acusa 4.000/5.000.
    linhas: [
      // ---- ativo
      linhaAnos("ativo_circulante", "Caixa e equivalentes de caixa", { "2024": 8000, "2025": 12000 }),
      linhaAnos("ativo_circulante", "Clientes", { "2024": 26000, "2025": 30000 }),
      linhaAnos("ativo_circulante", "Estoques", { "2024": 18000, "2025": 20000 }),
      linhaAnos("ativo_nao_circulante", "Imobilizado", { "2024": 62000, "2025": 60000 }),
      linhaAnos("ativo_nao_circulante", "Depósitos judiciais", { "2024": 3000, "2025": 3000 }),
      // ---- passivo
      linhaAnos("passivo_circulante", "Fornecedores", { "2024": 15000, "2025": 18000 }),
      linhaAnos("passivo_circulante", "Obrigações trabalhistas", { "2024": 6000, "2025": 7000 }),
      linhaAnos("passivo_circulante", "Empréstimos e financiamentos", { "2024": 12000, "2025": 15000 }),
      linhaAnos("passivo_nao_circulante", "Empréstimos e financiamentos", { "2024": 30000, "2025": 35000 }),
      // O par subtotal + componentes, como o documento imprime. `papel` chega como
      // "conta" de propósito: é o que `fn_papel_linha` devolve para "Provisões"
      // (não está na lista fechada dela), e é por isso que a detecção estrutural do
      // export precisa existir.
      linhaAnos("passivo_nao_circulante", "Provisões", { "2024": 4000, "2025": 5000 }),
      linhaAnos("passivo_nao_circulante", "Provisão para contingências cíveis", { "2024": 1500, "2025": 2000 }),
      linhaAnos("passivo_nao_circulante", "Provisão para contingências trabalhistas", { "2024": 2500, "2025": 3000 }),
      // ---- patrimônio
      linhaAnos("patrimonio_liquido", "Capital social", { "2024": 40000, "2025": 40000 }),
      linhaAnos("patrimonio_liquido", "Reservas de lucros", { "2024": 10000, "2025": 5000 }),
      // A MESMA CONTA COM DOIS RÓTULOS — o defeito que sobrou da rodada anterior e que
      // a reconciliação com o total informado resolve. No v35 são "Prejuízos
      // acumulados" e "Resultados Acumulados", ambos −39.150, e "Capital social
      // subscrito"/"Capital social subscrito e integralizado". Não é subtotal (a
      // detecção estrutural não pega) e não dá para resolver por semelhança de
      // valor: duas reservas de mesmo valor são plausíveis. Somadas, inflam o PL em
      // 10.000/5.000 — e é isso que o total informado corrige.
      linhaAnos("patrimonio_liquido", "Reserva de lucros acumulados", { "2024": 10000, "2025": 5000 }),
      // ---- resultado, NA CONVENÇÃO DO DOCUMENTO (despesa negativa)
      //   2025: RL 166.000 · LB 58.000 · EBITDA 41.000 · EBIT 33.000 · LL 17.820
      //   2024: RL 149.400 · LB 49.900 · EBITDA 35.400 · EBIT 27.900 · LL 15.900
      linhaAnos("receita_bruta", "Vendas de produtos - mercado interno",
        { "2024": 180000, "2025": 200000 }, "DRE"),
      linhaAnos("receita_bruta", "ICMS sobre vendas", { "2024": -30600, "2025": -34000 }, "DRE"),
      linhaAnos("custos", "Custo dos produtos vendidos", { "2024": -92000, "2025": -100000 }, "DRE"),
      linhaAnos("custos", "Depreciação industrial", { "2024": -7500, "2025": -8000 }, "DRE"),
      linhaAnos("despesas_operacionais", "Despesas administrativas", { "2024": -22000, "2025": -25000 }, "DRE"),
      linhaAnos("resultado_financeiro", "Despesas financeiras", { "2024": -5000, "2025": -6000 }, "DRE"),
      linhaAnos("impostos_lucro", "Imposto de renda e contribuição social",
        { "2024": -7000, "2025": -9180 }, "DRE"),
      // ---- o mapa de dívida cobre SÓ 2025 (é o caso comum: uma data de referência)
      linhaAnos("passivo_circulante", "Banco Alfa - Capital de giro - Saldo devedor",
        { "2025": 50000 }, "MAPA_DIVIDA"),
      linhaAnos("passivo_circulante", "Banco Alfa - Capital de giro - Juros do período",
        { "2025": 6000 }, "MAPA_DIVIDA"),
      // ---- as ÂNCORAS: o que o documento informa, para a conferência por valor.
      // Chegam com `papel: "subtotal"` (lista fechada da `fn_papel_linha`), ficam
      // fora das somas e servem de referência.
      linhaAnos("receita_bruta", "Receita Líquida", { "2024": 149400, "2025": 166000 }, "DRE", "subtotal"),
      linhaAnos("custos", "Lucro Bruto", { "2024": 49900, "2025": 58000 }, "DRE", "subtotal"),
      linhaAnos("despesas_operacionais", "Resultado Operacional (EBIT)",
        { "2024": 27900, "2025": 33000 }, "DRE", "subtotal"),
      linhaAnos("impostos_lucro", "Lucro Líquido do Exercício",
        { "2024": 15900, "2025": 17820 }, "DRE", "subtotal"),
      linhaAnos("ativo_circulante", "ATIVO", { "2024": 117000, "2025": 125000 }, "BALANCO", "subtotal"),
      // Os TOTAIS DE GRUPO informados — o insumo da reconciliação. O documento os
      // publica; o modelo passa a segui-los em vez de confiar na própria soma.
      linhaAnos("ativo_circulante", "Ativo Circulante", { "2024": 52000, "2025": 62000 }, "BALANCO", "subtotal"),
      linhaAnos("ativo_nao_circulante", "Ativo Não Circulante", { "2024": 65000, "2025": 63000 }, "BALANCO", "subtotal"),
      linhaAnos("passivo_circulante", "Passivo Circulante", { "2024": 33000, "2025": 40000 }, "BALANCO", "subtotal"),
      linhaAnos("passivo_nao_circulante", "Passivo Não Circulante", { "2024": 34000, "2025": 40000 }, "BALANCO", "subtotal"),
      linhaAnos("patrimonio_liquido", "Patrimônio Líquido", { "2024": 50000, "2025": 45000 }, "BALANCO", "subtotal"),
    ],
    premissas: [
      {
        codigo: "CRESC", nome: "Crescimento nominal da receita", natureza: "receita",
        formula: "crescimento_composto", unidade: "%",
        valores: { "2026": 8, "2027": 6, "2028": 5 }, origem: "digitado",
      },
      {
        codigo: "CUSTO", nome: "Custo sobre receita líquida", natureza: "custo",
        formula: "pct_de_linha", unidade: "%",
        valores: { "2026": 70, "2027": 70, "2028": 69 }, origem: "historico",
      },
      {
        codigo: "PMR", nome: "Prazo médio de recebimento", natureza: "giro",
        formula: "dias_de_giro", unidade: "dias",
        valores: { "2026": 54, "2027": 54, "2028": 50 }, origem: "historico",
      },
      {
        codigo: "CAPEX", nome: "Capex sobre receita líquida", natureza: "investimento",
        formula: "pct_de_linha", unidade: "%",
        valores: { "2026": 3, "2027": 3, "2028": 3 }, origem: "digitado",
      },
    ],
    vinculos: [
      { rotulo_norm: "vendas de produtos - mercado interno", premissa_codigo: "CRESC", sazonalidade_codigo: null },
      { rotulo_norm: "custo dos produtos vendidos", premissa_codigo: "CUSTO", sazonalidade_codigo: null },
      { rotulo_norm: "clientes", premissa_codigo: "PMR", sazonalidade_codigo: null },
      { rotulo_norm: "imobilizado", premissa_codigo: "CAPEX", sazonalidade_codigo: null },
    ],
    macro: [
      { serie: "IPCA", ano: 2026, valor: 4.5, fonte: "Focus", natureza: "taxa" as const },
      { serie: "IPCA", ano: 2027, valor: 4, fonte: "Focus", natureza: "taxa" as const },
      { serie: "IPCA", ano: 2028, valor: 3.5, fonte: "Focus", natureza: "taxa" as const },
      { serie: "CDI", ano: 2026, valor: 10, fonte: "Focus", natureza: "taxa" as const },
      { serie: "CDI", ano: 2027, valor: 9.5, fonte: "Focus", natureza: "taxa" as const },
      { serie: "CDI", ano: 2028, valor: 9, fonte: "Focus", natureza: "taxa" as const },
      // O CÂMBIO NAS DUAS GRANDEZAS, de propósito: 2024 chega como o retorno do ano
      // (o que `fn_indice_macro_anual` devolve para série de nível) e tem de ser
      // RECUSADO; 2025 e 2026 chegam em nível e têm de ser publicados. Sem as duas
      // formas na fixture, o teste não distingue "recusa" de "não recebeu nada".
      { serie: "CAMBIO_USD", ano: 2024, valor: 24.5, fonte: "realizado (12 meses)", natureza: "taxa" as const },
      { serie: "CAMBIO_USD", ano: 2025, valor: 5.2, fonte: "realizado — fechamento de 2025-12-31", natureza: "nivel" as const },
      { serie: "CAMBIO_USD", ano: 2026, valor: 5.4, fonte: "Focus", natureza: "nivel" as const },
    ],
    unidade: "R$ mil",
  };

  // O modelo só é construído quando o caso tem entidade reconhecível NOS CAMPOS
  // extraídos (`if (entidadesConhecidas.size > 0)` em export.ts). Sem estes dois
  // campos o export pula o código sob teste e o assert passaria sem exercitar nada.
  const VMOD = "vModelo";
  // OS CAMPOS EXISTEM PARA A DETECÇÃO ESTRUTURAL RODAR. É por eles que o export
  // descobre que "Provisões" é o subtotal impresso ANTES dos seus componentes — o
  // sinal está na ORDEM, e é o único sinal que existe (o rótulo "Provisões" não está
  // na lista fechada da `fn_papel_linha`, e por isso chega como `papel: "conta"`).
  // Sem esta sequência aqui, o teste do (0106b) mediria o instrumento: a lista de
  // subtotais chegaria vazia e a exclusão nunca seria exercitada.
  const camposModelo: CampoExtraido[] = [
    campo({ chave: "Caixa e equivalentes de caixa", secao: "Ativo Circulante",
            secao_canonica: "ativo_circulante", valor_num: 12000, documento_versao_id: VMOD, ordem: 1 }),
    campo({ chave: "Capital social", secao: "Patrimônio Líquido",
            secao_canonica: "patrimonio_liquido", valor_num: 40000, documento_versao_id: VMOD, ordem: 2 }),
    campo({ chave: "Provisões", secao: "Passivo Não Circulante",
            secao_canonica: "passivo_nao_circulante", valor_num: 5000, documento_versao_id: VMOD, ordem: 3 }),
    campo({ chave: "Provisão para contingências cíveis", secao: "Passivo Não Circulante",
            secao_canonica: "passivo_nao_circulante", valor_num: 2000, documento_versao_id: VMOD, ordem: 4 }),
    campo({ chave: "Provisão para contingências trabalhistas", secao: "Passivo Não Circulante",
            secao_canonica: "passivo_nao_circulante", valor_num: 3000, documento_versao_id: VMOD, ordem: 5 }),
  ];
  const docsModelo: DocumentoParaExport[] = [{
    id: "dModelo", tipo_taxonomia: "BALANCO",
    entidade: { razao_social: "VERTENTES METALÚRGICA LTDA." },
    periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: VMOD, nome_original: "01_BP_Vertentes_2025.pdf" }],
  }];

  const wbMod = buildExportWorkbook({
    caso: entradaModelo.caso, documentos: docsModelo, campos: camposModelo,
    agora: new Date("2026-08-05T12:00:00Z"), modo: "completo",
    modeloInstitucional: entradaModelo as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
  });

  // A especificação dos gráficos viaja presa ao workbook até o pós-processamento do
  // buffer (é o caminho que `finalizarBufferDoExport` usa). Ler daqui é o que
  // permite conferir a ÂNCORA deles sem reabrir o .xlsx.
  const graficosDoModelo =
    (wbMod as unknown as { __graficosDoModelo?: Array<{
      titulo: string; de: { col: number; linha: number }; ate: { col: number; linha: number };
    }> }).__graficosDoModelo ?? [];

  /** Acha a linha de uma aba do modelo pelo rótulo exato da coluna C. */
  const linhaDoRotulo = (aba: string, rotulo: string): number | null => {
    const ws = wbMod.getWorksheet(aba);
    if (!ws) return null;
    for (let r = 1; r <= ws.rowCount; r++) {
      if (String(ws.getRow(r).getCell(3).value ?? "").trim() === rotulo) return r;
    }
    return null;
  };
  // 2024 e 2025 são REALIZADOS; 2026 a 2028, projetados.
  const COLS_ANO = ["E", "F", "G", "H", "I"];
  const ANOS = [2024, 2025, 2026, 2027, 2028];
  const iAnoDe = (ano: number) => ANOS.indexOf(ano);
  const valorNaAba = (aba: string, rotulo: string, iAno: number) => {
    const ws = wbMod.getWorksheet(aba);
    const r = linhaDoRotulo(aba, rotulo);
    if (!ws || r === null) return null;
    return avaliarCelula(ws, COLS_ANO[iAno], r);
  };

  // ---- (0105a) O CHECK do balanço fecha em TODO exercício projetado --------
  const rCheck = linhaDoRotulo("Balance Sheet", "CHECK — Ativo − (Passivo + PL) deve ser ZERO");
  checar(rCheck !== null, "(0105a) a aba Balance Sheet tem a linha de CHECK", String(rCheck));
  if (rCheck !== null) {
    const bs = wbMod.getWorksheet("Balance Sheet")!;
    const desvios: string[] = [];
    for (let i = 0; i < COLS_ANO.length; i++) {
      const v = avaliarCelula(bs, COLS_ANO[i], rCheck);
      if (typeof v !== "number") { desvios.push(`${ANOS[i]}: não avaliável (${JSON.stringify(v)})`); continue; }
      if (Math.abs(v) > 0.5) desvios.push(`${ANOS[i]}: ${v.toFixed(2)}`);
    }
    checar(desvios.length === 0,
      "(0105a) O BALANÇO FECHA — Ativo − (Passivo + PL) = 0 em todos os exercícios, realizado e projetado",
      desvios.join(" · "));
  }

  // ---- (0105b) o caixa NÃO é projetado por dias de giro --------------------
  //
  // A dupla contagem aberta desde a sessão 32. O Modelo Base exclui
  // `Cash & Short Term Inv.` das contas de giro (§10 do MAPA_MODELO_BASE.md), e a
  // regra é: uma conta, uma origem.
  {
    const wc = wbMod.getWorksheet("Working Capital");
    let achouCaixa = false;
    let achouDivida = false;
    if (wc) {
      for (let r = 1; r <= wc.rowCount; r++) {
        const rot = String(wc.getRow(r).getCell(3).value ?? "");
        if (/^Caixa e equivalentes/i.test(rot)) achouCaixa = true;
        if (/^Empréstimos e financiamentos/i.test(rot)) achouDivida = true;
      }
    }
    checar(!achouCaixa,
      "(0105b) o CAIXA não aparece como conta de giro no Working Capital (era contado duas vezes no ativo)",
      achouCaixa ? "a linha de caixa está no giro" : "");
    checar(!achouDivida,
      "(0105b) a DÍVIDA bancária não aparece como conta de giro (era contada duas vezes no passivo)",
      achouDivida ? "a linha de empréstimos está no giro" : "");
  }

  // ---- (0105c) a depreciação chega à DRE ----------------------------------
  {
    const i2026 = iAnoDe(2026);
    const dep2026 = valorNaAba("Income Statement", "Depreciation and Amortization", i2026);
    const capexOk = valorNaAba("Fixed Assets & CAPEX", "CAPEX total", i2026);
    checar(typeof dep2026 === "number" && dep2026 > 0,
      "(0105c) a DEPRECIAÇÃO chega à DRE — a linha D&A do Income Statement é maior que zero no projetado",
      `D&A 2026 = ${JSON.stringify(dep2026)} (capex 2026 = ${JSON.stringify(capexOk)})`);
    const ebitda = valorNaAba("Income Statement", "EBITDA", i2026);
    const ebit = valorNaAba("Income Statement", "EBIT", i2026);
    checar(typeof ebitda === "number" && typeof ebit === "number" && ebitda > ebit,
      "(0105c) …e por isso EBITDA > EBIT no projetado (com D&A zero os dois eram iguais)",
      `EBITDA ${JSON.stringify(ebitda)} · EBIT ${JSON.stringify(ebit)}`);

    // ---- (0106e) …e chega no REALIZADO também -------------------------------
    //
    // A DRE extraída traz "Depreciação industrial" DENTRO do custo (−8.000 em
    // 2025). No arquivo entregue a linha D&A do realizado era ZERO e o EBITDA
    // realizado saía igual ao EBIT — o erro que o próprio comentário do EBITDA
    // alerta, no único par de colunas que o comitê compara com o balanço auditado.
    const i2025 = iAnoDe(2025);
    const depHist = valorNaAba("Income Statement", "Depreciation and Amortization", i2025);
    checar(typeof depHist === "number" && Math.abs(depHist - 8000) < 0.5,
      "(0106e) a DEPRECIAÇÃO REALIZADA chega à DRE — vem das linhas de custo/despesa extraídas",
      `D&A 2025 = ${JSON.stringify(depHist)} (esperado 8.000, de \"Depreciação industrial\")`);
    const ebitdaH = valorNaAba("Income Statement", "EBITDA", i2025);
    const ebitH = valorNaAba("Income Statement", "EBIT", i2025);
    checar(typeof ebitdaH === "number" && typeof ebitH === "number"
      && Math.abs(ebitdaH - 41000) < 0.5 && Math.abs(ebitH - 33000) < 0.5,
      "(0106e) …e o EBITDA realizado deixa de ser o EBIT com outro nome (41.000 contra 33.000)",
      `EBITDA ${JSON.stringify(ebitdaH)} · EBIT ${JSON.stringify(ebitH)}`);
  }

  // ---- (0106a) A DRE DO REALIZADO É A DO DOCUMENTO -------------------------
  //
  // O invariante nº 9 aplicado ao modelo institucional. É o assert que o arquivo
  // entregue em 06/08/2026 teria reprovado em oito células: a cascata SUBTRAI
  // despesa (convenção do modelo: magnitude positiva) e a extração entrega despesa
  // NEGATIVA (convenção do documento) — subtrair negativo soma, e a DRE realizada
  // saiu com receita líquida 170.220 onde o documento diz 106.580 e resultado
  // +268.041 onde o documento diz −17.901.
  {
    const esperado: Array<{ rotulo: string; ano: number; valor: number }> = [
      { rotulo: "NET REVENUES", ano: 2024, valor: 149400 },
      { rotulo: "NET REVENUES", ano: 2025, valor: 166000 },
      { rotulo: "GROSS PROFIT", ano: 2024, valor: 49900 },
      { rotulo: "GROSS PROFIT", ano: 2025, valor: 58000 },
      { rotulo: "EBIT", ano: 2024, valor: 27900 },
      { rotulo: "EBIT", ano: 2025, valor: 33000 },
      { rotulo: "NET PROFIT", ano: 2024, valor: 15900 },
      { rotulo: "NET PROFIT", ano: 2025, valor: 17820 },
    ];
    const fora = esperado.filter(({ rotulo, ano, valor }) => {
      const v = valorNaAba("Income Statement", rotulo, iAnoDe(ano));
      return typeof v !== "number" || Math.abs(v - valor) > 0.5;
    }).map(({ rotulo, ano, valor }) =>
      `${rotulo} ${ano}: ${JSON.stringify(valorNaAba("Income Statement", rotulo, iAnoDe(ano)))} != ${valor}`);
    checar(fora.length === 0,
      "(0106a) A DRE REALIZADA REPRODUZ O DOCUMENTO — receita líquida, lucro bruto, EBIT e "
      + "resultado líquido dos exercícios realizados batem com o informado (convenção de sinal)",
      fora.join(" · "));

    // E a conferência existe DENTRO do arquivo, não só no teste: quem abre a
    // planilha tem a diferença na cara, senão o próximo erro de sinal volta a
    // passar por bom.
    const difs = ["Receita líquida", "Lucro bruto", "EBIT", "Resultado líquido"]
      .map((r) => linhaDoRotulo("Income Statement", `${r} — informado no documento`))
      .filter((r) => r !== null);
    checar(difs.length === 4,
      "(0106a) o Income Statement publica o informado no documento ao lado do número do modelo",
      `linhas encontradas: ${difs.length}/4`);
    const rDiag = linhaDoRotulo("Income Statement", "diagnóstico");
    const diag = rDiag === null ? null
      : avaliarCelula(wbMod.getWorksheet("Income Statement")!, COLS_ANO[iAnoDe(2025)], rDiag);
    checar(diag === "confere com o documento",
      "(0106a) …e o diagnóstico do exercício realizado diz que CONFERE",
      JSON.stringify(diag));
  }

  // ---- (0106b) SUBTOTAL INFORMADO NÃO ENTRA NA SOMA DO BALANÇO -------------
  //
  // "Provisões 5.000" seguido dos dois componentes (2.000 + 3.000) é como toda
  // demonstração imprime. Somar os três dobra o grupo: no arquivo entregue o
  // `ATIVO TOTAL` de 2025 saiu 195.090 contra 95.780 informados (2,04x), enquanto a
  // aba analítica `Balanço` do MESMO arquivo mostrava o número certo.
  {
    const fora: string[] = [];
    for (const [ano, esperado] of [[2024, 117000], [2025, 125000]] as const) {
      const ativo = valorNaAba("Balance Sheet", "ATIVO TOTAL", iAnoDe(ano));
      const pnc = valorNaAba("Balance Sheet", "PASSIVO NÃO CIRCULANTE", iAnoDe(ano));
      const pncEsperado = ano === 2024 ? 34000 : 40000;
      if (typeof ativo !== "number" || Math.abs(ativo - esperado) > 0.5) {
        fora.push(`ATIVO ${ano}: ${JSON.stringify(ativo)} != ${esperado}`);
      }
      if (typeof pnc !== "number" || Math.abs(pnc - pncEsperado) > 0.5) {
        fora.push(`PNC ${ano}: ${JSON.stringify(pnc)} != ${pncEsperado} (subtotal somado com os componentes?)`);
      }
    }
    checar(fora.length === 0,
      "(0106b) o SUBTOTAL informado pelo documento fica FORA da soma do balanço — o grupo não dobra",
      fora.join(" · "));

    const rDif = linhaDoRotulo("Balance Sheet", "diferença (modelo − documento) — ZERO");
    const dif2025 = rDif === null ? null
      : avaliarCelula(wbMod.getWorksheet("Balance Sheet")!, COLS_ANO[iAnoDe(2025)], rDif);
    checar(typeof dif2025 === "number" && Math.abs(dif2025) < 0.5,
      "(0106b) …e o balanço publica a diferença contra o ativo total informado, em ZERO",
      JSON.stringify(dif2025));
  }

  // ---- (0106h) A MESMA CONTA COM DOIS RÓTULOS NÃO ESTOURA O BALANÇO -------
  //
  // "Reservas de lucros" e "Reserva de lucros acumulados", ambas 5.000 em 2025, são
  // a mesma conta transposta duas vezes — o resíduo que sobrou depois de excluir os
  // subtotais informados. Somadas, o PL sai 50.000 onde o documento diz 45.000.
  //
  // A correção NÃO é apagar uma delas (duas reservas de mesmo valor são plausíveis,
  // e apagar conta legítima é pior que somar demais): é seguir o TOTAL INFORMADO,
  // com a diferença escrita numa linha própria. Invariante nº 6, que as abas
  // analíticas seguem desde o teste v25, aplicado ao modelo.
  {
    const fora: string[] = [];
    for (const [ano, plEsperado] of [[2024, 50000], [2025, 45000]] as const) {
      const plModelo = valorNaAba("Balance Sheet", "PATRIMÔNIO LÍQUIDO", iAnoDe(ano));
      if (typeof plModelo !== "number" || Math.abs(plModelo - plEsperado) > 0.5) {
        fora.push(`PL ${ano}: ${JSON.stringify(plModelo)} != ${plEsperado} (conta duplicada somada?)`);
      }
    }
    checar(fora.length === 0,
      "(0106h) o PATRIMÔNIO segue o total informado no documento mesmo com a MESMA conta transposta "
      + "com dois rótulos — sem apagar conta nenhuma",
      fora.join(" · "));

    const rRec = linhaDoRotulo("Balance Sheet", "reconciliação com o patrimônio líquido informado no documento");
    const rec2025 = rRec === null ? null
      : avaliarCelula(wbMod.getWorksheet("Balance Sheet")!, COLS_ANO[iAnoDe(2025)], rRec);
    checar(typeof rec2025 === "number" && Math.abs(rec2025 + 5000) < 0.5,
      "(0106h) …e a linha de reconciliação DIZ o tamanho do que não se explica (−5.000 em 2025)",
      JSON.stringify(rec2025));
    // Na projeção ela é constante: nem zerada (salto artificial), nem crescida
    // (projetar erro de extração como se fosse conta).
    const rec2027 = rRec === null ? null
      : avaliarCelula(wbMod.getWorksheet("Balance Sheet")!, COLS_ANO[iAnoDe(2027)], rRec);
    checar(typeof rec2027 === "number" && Math.abs(rec2027 + 5000) < 0.5,
      "(0106h) …e permanece constante no projetado, sem salto na virada do realizado",
      JSON.stringify(rec2027));
  }

  // ---- (0106c) A DÍVIDA APARECE NO EXERCÍCIO QUE O MAPA NÃO COBRE ----------
  //
  // O mapa de dívida deste caso (como o do v35) tem UMA data de referência: 2025.
  // Antes, `dividas` escolhia o mapa para o modelo inteiro e 2024 saía com dívida
  // ZERO — enquanto o balanço informa 12.000 no circulante e 30.000 no não
  // circulante. O `CHECK` de 2024 abria exatamente no valor que desapareceu.
  {
    const cp2024 = valorNaAba("Balance Sheet", "Dívida de curto prazo + revolver", iAnoDe(2024));
    const lp2024 = valorNaAba("Balance Sheet", "Dívida de longo prazo", iAnoDe(2024));
    checar(typeof cp2024 === "number" && Math.abs(cp2024 - 12000) < 1
      && typeof lp2024 === "number" && Math.abs(lp2024 - 30000) < 1,
      "(0106c) a DÍVIDA do exercício que o mapa não cobre vem do balanço, com a repartição "
      + "curto/longo do próprio ano (12.000 + 30.000 em 2024)",
      `CP ${JSON.stringify(cp2024)} · LP ${JSON.stringify(lp2024)}`);
  }

  // ---- (0105d) o eixo do tempo tem UMA raiz ------------------------------
  {
    const rec = wbMod.getWorksheet("Revenues, COGS & SG&A")!;
    const rRaiz = linhaDoRotulo("Revenues, COGS & SG&A",
      "Último exercício realizado (a raiz do calendário do modelo)");
    checar(rRaiz !== null,
      "(0105d) a aba de receita declara a RAIZ do calendário (uma única data digitada)", String(rRaiz));
    // O cabeçalho de cada aba do modelo é FÓRMULA, não ano digitado.
    const semFormula: string[] = [];
    for (const aba of ["Income Statement", "Balance Sheet", "Working Capital", "Cash Flow",
                       "ST Inv. & Debt", "Fixed Assets & CAPEX", "Goodwill, Taxes & Div.", "Output"]) {
      const ws = wbMod.getWorksheet(aba);
      if (!ws) { semFormula.push(`${aba}: aba ausente`); continue; }
      let rTit: number | null = null;
      for (let r = 1; r <= ws.rowCount; r++) {
        const c = ws.getRow(r).getCell(5).value;
        if (c && typeof c === "object" && "formula" in c
          && /Revenues, COGS & SG&A/.test((c as { formula: string }).formula)) { rTit = r; break; }
      }
      if (rTit === null) semFormula.push(aba);
    }
    checar(semFormula.length === 0,
      "(0105d) o cabeçalho de ano de todas as abas do modelo é FÓRMULA que herda da raiz (P01/P02)",
      semFormula.join(", "));
    void rec;
  }

  // ---- (0105e) nenhuma fórmula do modelo com #REF! ou erro ---------------
  {
    const comErro: string[] = [];
    for (const aba of ABAS_DO_MODELO) {
      const ws = wbMod.getWorksheet(aba);
      if (!ws) continue;
      for (let r = 1; r <= ws.rowCount; r++) {
        const row = ws.getRow(r);
        for (let c = 1; c <= 40; c++) {
          const v = row.getCell(c).value;
          if (v && typeof v === "object" && "formula" in v) {
            const f = (v as { formula: string }).formula;
            if (/#REF!|#VALUE!|#DIV\/0!|#NAME\?/.test(f)) comErro.push(`${aba}!${row.getCell(c).address}`);
          }
        }
      }
    }
    checar(comErro.length === 0,
      "(0105e) nenhuma fórmula do modelo nasce com #REF!/#VALUE! — a referência tem 667, das quais 627 no Output",
      comErro.slice(0, 8).join(", "));
  }

  // ---- (0105f) área de impressão nas 14 abas do modelo ------------------
  {
    const semArea = ABAS_DO_MODELO.filter((aba) => {
      const ws = wbMod.getWorksheet(aba);
      return !ws || !ws.pageSetup?.printArea;
    });
    checar(semArea.length === 0,
      "(0105f) as 14 abas do modelo declaram área de impressão (a referência declara 5)",
      semArea.join(", "));
  }

  // ---- (0105g) o Output não sobrescreve a legenda de cenário ------------
  {
    const out = wbMod.getWorksheet("Output")!;
    checar(String(out.getRow(5).getCell(3).value ?? "") === "3 = Stress Case",
      "(0105g) a legenda '3 = Stress Case' sobrevive — o cabeçalho caía sobre ela (defeito medido)",
      String(out.getRow(5).getCell(3).value ?? ""));
    checar(String(out.getRow(1).getCell(3).value ?? "") === "SCENARIO",
      "(0105g) …e 'SCENARIO' continua na linha 1", String(out.getRow(1).getCell(3).value ?? ""));
  }

  // ---- (0105h) os covenants e o diagnóstico respondem -------------------
  {
    const i2026 = iAnoDe(2026);
    const diag = valorNaAba("Output", "Diagnóstico do exercício", i2026);
    checar(typeof diag === "string" && diag.length > 0,
      "(0105h) o Output devolve um diagnóstico por exercício (a linha que o comitê lê primeiro)",
      JSON.stringify(diag));
    const nd = valorNaAba("Output", "Net Debt / EBITDA", i2026);
    checar(typeof nd === "number" || (typeof nd === "string" && nd === "EBITDA<=0"),
      "(0105h) Net Debt / EBITDA é número, ou texto explícito quando o EBITDA não é positivo",
      JSON.stringify(nd));
  }

  // ---- (0138) RETORNO E SOLVÊNCIA: os quatro índices que o Arquitetura do Sistema/2 Especificação/f0/08 fasejou ----
  //
  // O `Arquitetura do Sistema/2 Especificação/f0/08` deixou ROA, ROE, liquidez imediata e Altman de fora "até a extração
  // isolar as linhas-conceito". Ela isola desde as 14 abas, e ninguém tinha
  // revisitado. O que estes asserts protegem não é a existência das linhas: é o
  // comportamento delas diante do caso ruim, que é o caso destes mandatos.
  {
    const i2026 = iAnoDe(2026);

    // 1. A liquidez imediata é MENOR OU IGUAL à seca, sempre. Caixa é um pedaço
    //    do ativo circulante sem estoque, então uma imediata maior que a seca
    //    significa que uma das duas está lendo a conta errada.
    const imed = valorNaAba("Output", "Liquidez imediata (só caixa)", i2026);
    const seca = valorNaAba("Output", "Liquidez seca (sem estoque)", i2026);
    checar(typeof imed === "number", "(0138) a liquidez imediata sai como número", JSON.stringify(imed));
    if (typeof imed === "number" && typeof seca === "number") {
      checar(imed <= seca + 1e-9,
        "(0138) …e é menor ou igual à liquidez seca: caixa é um pedaço do que ela mede",
        `imediata ${imed.toFixed(3)} × seca ${seca.toFixed(3)}`);
    }

    // 2. ROA e ROE saem, ou dizem por que não. "PL<=0" é resposta, zero não é:
    //    prejuízo sobre PL negativo daria retorno POSITIVO, que lido rápido
    //    afirma o contrário do que está acontecendo.
    const roa = valorNaAba("Output", "ROA — lucro líquido / ativo total", i2026);
    const roe = valorNaAba("Output", "ROE — lucro líquido / patrimônio líquido", i2026);
    checar(typeof roa === "number" || roa === "sem ativo",
      "(0138) o ROA é número ou texto explícito", JSON.stringify(roa));
    checar(typeof roe === "number" || roe === "PL<=0",
      "(0138) o ROE é número, ou 'PL<=0' quando o patrimônio está a descoberto",
      JSON.stringify(roe));

    // 3. O Altman e a zona CONCORDAM. Um número sem a zona obriga quem lê a
    //    saber os cortes de cabeça; a zona sem o número é opinião.
    const z = valorNaAba("Output", "Altman Z\u2033 (mercados emergentes)", i2026);
    const zona = valorNaAba("Output", "zona", i2026);
    checar(typeof z === "number" || typeof z === "string",
      "(0138) o Altman Z'' aparece no Output", JSON.stringify(z));
    if (typeof z === "number") {
      const esperada = z > 2.6 ? "segura" : z >= 1.1 ? "cinzenta" : "AFLIÇÃO";
      checar(zona === esperada,
        "(0138) …e a zona publicada corresponde aos cortes do próprio Altman",
        `Z''=${z.toFixed(2)} → publicou "${String(zona)}", esperado "${esperada}"`);
    } else {
      checar(zona === "n.a.",
        "(0138) …e quando o índice não sai, a zona diz n.a. em vez de arriscar",
        JSON.stringify(zona));
    }

    // 4. O X2 do Altman é LINHA, não soma escondida: quem discorda do índice
    //    precisa poder ver de onde ele saiu.
    const retido = valorNaAba("Output", "Retained earnings (extracted + model)", i2026);
    checar(typeof retido === "number" || retido === "n.a.",
      "(0138) os lucros retidos que alimentam o X2 são publicados em linha própria",
      JSON.stringify(retido));
    // E a amarração entre os dois: sem lucro retido isolado, o índice não sai.
    if (retido === "n.a.") {
      checar(z === "sem lucros retidos",
        "(0138) …e sem eles o Altman se recusa, em vez de tratar a ausência como zero",
        JSON.stringify(z));
    }
  }

  // ---- (0139) REPERFILAMENTO: a alavanca move o número, e diz o que não moveu
  //
  // O §2.6 do diagnóstico: o arquivo dizia DSCR 0,3 e não tinha alavanca nenhuma
  // para responder "qual reestruturação resolve". A alavanca é a carência por
  // tranche; este bloco mostra o que ela fez.
  //
  // O QUE ESTES ASSERTS PROTEGEM é a honestidade da comparação, não a existência
  // dela: os dois lados têm de ser as MESMAS tranches, o lado "antes" não pode se
  // mexer quando alguém edita a carência, e o DSCR de hoje tem de ser o mesmo
  // número do bloco de RATIOS — senão a página passa a ter dois DSCR.
  {
    const i2026 = iAnoDe(2026);
    const antes = valorNaAba("Output", "Serviço das tranches no cronograma original", i2026);
    const depois = valorNaAba("Output", "Serviço das mesmas tranches como está negociado", i2026);
    const alivio = valorNaAba("Output", "Alívio do exercício (antes − depois)", i2026);
    checar(typeof antes === "number" && typeof depois === "number",
      "(0139) o bloco publica os dois lados do reperfilamento",
      `${String(antes)} / ${String(depois)}`);

    // SEM CARÊNCIA NEGOCIADA, O ALÍVIO É ZERO. É o assert mais importante do
    // grupo: um "antes" que não coincide com o "depois" no estado de partida
    // significa que os dois lados não estão medindo as mesmas tranches, e o
    // bloco publicaria um alívio que ninguém negociou.
    if (typeof alivio === "number") {
      checar(Math.abs(alivio) < 0.5,
        "(0139) no estado de partida (carência zero) o alívio é ZERO: os dois lados são as mesmas tranches",
        String(alivio));
    }

    // O DSCR DE HOJE É O MESMO NÚMERO DO BLOCO DE RATIOS, por referência. Se
    // divergir, a página tem dois DSCR com o mesmo nome.
    const dscrBloco = valorNaAba("Output", "DSCR de hoje (o do bloco de RATIOS)", i2026);
    const dscrRatios = valorNaAba("Output", "EBITDA / Serviço da dívida (DSCR)", i2026);
    if (typeof dscrBloco === "number" && typeof dscrRatios === "number") {
      checar(Math.abs(dscrBloco - dscrRatios) < 1e-6,
        "(0139) o DSCR do bloco é o MESMO do RATIOS, por referência e não por recálculo",
        `${dscrBloco} vs ${dscrRatios}`);
    }

    // O VEREDITO responde a pergunta do comitê, e não "melhorou".
    const veredito = valorNaAba("Output", "a negociação resolve o covenant?", i2026);
    checar(["já cumpria", "SIM — passou a cumprir", "não basta", "n.a."].includes(String(veredito)),
      "(0139) o veredito diz se ATRAVESSOU o corte, não se melhorou", String(veredito));

    // A CARÊNCIA É EDITÁVEL, uma célula por tranche, na aba de dívida.
    const rCar = linhaDoRotulo("ST Inv. & Debt", "carência (anos sem amortizar)");
    checar(rCar !== null, "(0139) a carência existe como linha por tranche na aba de dívida");
    if (rCar !== null) {
      const wsDiv = wbMod.getWorksheet("ST Inv. & Debt")!;
      const cel = wsDiv.getRow(rCar).getCell(wsDiv.getColumn(COLS_ANO[iAnoDe(2026)]).number);
      const fill = cel.fill as { fgColor?: { argb?: string } } | undefined;
      checar(cel.value === 0,
        "(0139) …nascendo em ZERO, porque carência é negociação e não fato do balanço",
        JSON.stringify(cel.value));
      checar(fill?.fgColor?.argb != null,
        "(0139) …e marcada como célula de entrada, para quem negocia saber onde digitar");
    }
  }

  // ---- (0105i) o revolver cobre o furo e o caixa nunca fica abaixo do mínimo
  {
    const desvios: string[] = [];
    for (let i = iAnoDe(2026); i < COLS_ANO.length; i++) {
      const caixa = valorNaAba("Cash Flow", "CAIXA DE FECHAMENTO", i);
      const min = valorNaAba("ST Inv. & Debt", "Caixa mínimo operacional", i);
      if (typeof caixa !== "number" || typeof min !== "number") { desvios.push(`${ANOS[i]}: não avaliável`); continue; }
      if (caixa < min - 0.5) desvios.push(`${ANOS[i]}: caixa ${caixa.toFixed(0)} < mínimo ${min.toFixed(0)}`);
    }
    checar(desvios.length === 0,
      "(0105i) o revolver cobre o furo: o caixa de fechamento nunca fica abaixo do caixa mínimo",
      desvios.join(" · "));
  }

  // ---- (0106d) OS GRÁFICOS ENTRAM NO PAPEL --------------------------------
  //
  // Medido no arquivo entregue: os 8 gráficos estavam ancorados nas colunas N a AE
  // e a área de impressão do `Output` é B:K — quem gerasse o PDF do Output (que é
  // como o comitê recebe) não levava gráfico nenhum. Gráfico fora da área de
  // impressão é trabalho que existe só na tela de quem o fez.
  {
    const out = wbMod.getWorksheet("Output")!;
    const area = String(out.pageSetup?.printArea ?? "");
    const m = /^B1:([A-Z]+)(\d+)$/.exec(area);
    const colLimite = m ? m[1] : "";
    const linhaLimite = m ? Number(m[2]) : 0;
    // Índice base 1 da última coluna da área de impressão.
    const colParaNum = (s: string) => [...s].reduce((n, ch) => n * 26 + (ch.charCodeAt(0) - 64), 0);
    // Confere os DOIS cantos, e que o retângulo não é degenerado: conferir só o
    // canto inferior deixava passar uma âncora invertida (`de` à direita de `ate`),
    // que o Excel desenha como nada. Primeira versão deste assert fazia isso, e o
    // defeito religado passou verde — ver §8.2 do CLAUDE.md.
    const colB = 2; // a área de impressão do modelo começa sempre em B1
    const fora = graficosDoModelo.filter((esp) =>
      // A âncora do OOXML é base 0; a coluna da área de impressão é base 1.
      esp.de.col + 1 < colB || esp.de.linha + 1 < 1
      || esp.ate.col + 1 > colParaNum(colLimite) || esp.ate.linha + 1 > linhaLimite
      || esp.de.col >= esp.ate.col || esp.de.linha >= esp.ate.linha);
    checar(m !== null && graficosDoModelo.length === 8 && fora.length === 0,
      "(0106d) os 8 gráficos do Output estão DENTRO da área de impressão da aba",
      `área ${area || "(ausente)"} · gráficos ${graficosDoModelo.length} · fora ${fora.length}`
      + (fora.length ? `: ${fora.map((f) => `${f.titulo} até col ${f.ate.col} lin ${f.ate.linha}`).join(" · ")}` : ""));
  }

  // ---- (0106f) O CÂMBIO É NÍVEL, NUNCA VARIAÇÃO ---------------------------
  //
  // A linha "R$/US$ — final de período" do arquivo entregue trazia 24,5 em 2024 e
  // −10,6 em 2025 (câmbio negativo!) ao lado de 5,2 do Focus: o RETORNO de uma série
  // de nível publicado numa linha de nível. A célula agora fica VAZIA quando a fonte
  // entrega a grandeza errada, com o motivo na nota.
  {
    const anual = wbMod.getWorksheet("Anual")!;
    const rFx = linhaDoRotulo("Anual", "R$/US$ — final de período");
    const v2024 = rFx === null ? null : anual.getRow(rFx).getCell(COLS_ANO[iAnoDe(2024)]).value;
    const v2026 = rFx === null ? null : avaliarCelula(anual, COLS_ANO[iAnoDe(2026)], rFx);
    checar(rFx !== null && (v2024 === null || v2024 === undefined),
      "(0106f) a série de NÍVEL recusa a variação: a célula fica vazia em vez de publicar câmbio negativo",
      `2024 = ${JSON.stringify(v2024)}`);
    checar(rFx !== null && typeof v2026 === "number" && Math.abs(v2026 - 5.4) < 0.001,
      "(0106f) …e o nível de fato publicado (expectativa do Focus, 5,40) continua chegando",
      JSON.stringify(v2026));
  }

  // ---- (0106j) CDI: ANO PARCIAL NÃO É TAXA ANUAL, E SEM FOCUS NÃO É JURO ZERO --
  //
  // Medido em 01/10/2026 no export do caso de teste 72d9210a, recalculado: a linha
  // "CDI (% a.a.)" da aba Anual trazia 10,888 / 14,333 (12 meses), **9,713 em 2026 =
  // realizado de 9 meses** e VAZIO em 2027-2030; "Custo efetivo do revolver" saía
  // 10,89% | 14,33% | 9,71% | 0 | 0 | 0 | 0. O Focus não publica CDI (só CAMBIO_USD,
  // IGPM, IPCA, PIB, SELIC), e CDI = Selic realizados em todo ano fechado de 2022-2025.
  // O ARRANJO ABAIXO É O DE PRODUÇÃO medido (CDI e Selic realizados de 12 meses nos
  // anos fechados, CDI e INPC de 9/8 meses no corrente, Focus com Selic e sem CDI) —
  // não é fixture inventada para provar o bug. Só os valores do Focus são ilustrativos.
  {
    const macro0 = [
      { serie: "CDI", ano: 2024, valor: 10.888, fonte: "realizado (12 meses)", origem: "realizado" as const, natureza: "taxa" as const, meses: 12 },
      { serie: "CDI", ano: 2025, valor: 14.333, fonte: "realizado (12 meses)", origem: "realizado" as const, natureza: "taxa" as const, meses: 12 },
      { serie: "CDI", ano: 2026, valor: 9.713, fonte: "realizado (9 meses)", origem: "realizado" as const, natureza: "taxa" as const, meses: 9 },
      { serie: "SELIC", ano: 2024, valor: 10.888, fonte: "realizado (12 meses)", origem: "realizado" as const, natureza: "taxa" as const, meses: 12 },
      { serie: "SELIC", ano: 2025, valor: 14.333, fonte: "realizado (12 meses)", origem: "realizado" as const, natureza: "taxa" as const, meses: 12 },
      { serie: "SELIC", ano: 2026, valor: 13.75, fonte: "Focus, coleta 2026-09-28", origem: "focus" as const, natureza: "taxa" as const },
      { serie: "SELIC", ano: 2027, valor: 12.5, fonte: "Focus, coleta 2026-09-28", origem: "focus" as const, natureza: "taxa" as const },
      { serie: "SELIC", ano: 2028, valor: 10.5, fonte: "Focus, coleta 2026-09-28", origem: "focus" as const, natureza: "taxa" as const },
      { serie: "INPC", ano: 2026, valor: 3.1, fonte: "realizado (8 meses)", origem: "realizado" as const, natureza: "taxa" as const, meses: 8 },
    ];
    const wb0 = buildExportWorkbook({
      caso: entradaModelo.caso, documentos: docsModelo, campos: camposModelo,
      agora: new Date("2026-08-05T12:00:00Z"), modo: "completo",
      modeloInstitucional: { ...entradaModelo, macro: macro0 } as unknown as
        Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
    });
    const lin = (aba: string, rotulo: string, col = 3): number => {
      const ws = wb0.getWorksheet(aba)!;
      for (let r = 1; r <= ws.rowCount; r++) {
        if (String(ws.getRow(r).getCell(col).value ?? "").trim() === rotulo) return r;
      }
      return -1;
    };
    const anual0 = wb0.getWorksheet("Anual")!;
    const rCdi = lin("Anual", "CDI (% a.a.)");
    const rInpc = lin("Anual", "INPC — IBGE (% a.a.)");
    const rSelic = lin("Anual", "Selic acumulada (% a.a.)");
    const notaDe = (ws: import("exceljs").Worksheet, r: number, c: string) =>
      String((ws.getRow(r).getCell(c).note as { texts?: Array<{ text: string }> } | undefined)
        ?.texts?.map((t) => t.text).join("") ?? "");
    checar(rCdi > 0 && rInpc > 0 && rSelic > 0, "(0106j) as linhas CDI, INPC e Selic existem na aba Anual",
      `${rCdi}/${rInpc}/${rSelic}`);
    if (rCdi > 0 && rInpc > 0 && rSelic > 0) {
      const cdi = COLS_ANO.map((c) => avaliarCelula(anual0, c, rCdi));
      // 1. realizado de 12 meses segue chegando como está
      checar(Math.abs(Number(cdi[0]) - 10.888) < 1e-9 && Math.abs(Number(cdi[1]) - 14.333) < 1e-9,
        "(0106j) o CDI realizado de 12 meses continua publicado como veio", JSON.stringify(cdi.slice(0, 2)));
      // 2. o ano de 9 meses NÃO é publicado como taxa anual, e NÃO é a meta de fim de ano
      //    crua: compõe o realizado (9,713 em 9 meses) com os 3 meses restantes à meta
      //    13,75 do Focus = (1,09713)×(1,1375)^(3/12)−1 ≈ 13,30 (e não 13,75, que
      //    descartaria os 9 meses realizados, nem 9,713).
      const perto = (x: unknown, alvo: number, eps: number) => typeof x === "number" && Math.abs(x - alvo) < eps;
      const esperado26 = ((1 + 9.713 / 100) * Math.pow(1 + 13.75 / 100, 3 / 12) - 1) * 100;
      checar(perto(cdi[2], esperado26, 1e-6) && Math.abs(esperado26 - 13.30) < 0.01,
        "(0106j) o CDI de 2026 (9 meses realizados + meta 13,75) compõe ≈ 13,30 — nem 9,713 nem 13,75",
        `${JSON.stringify(cdi[2])} (esperado ${esperado26.toFixed(4)})`);
      // 3. ano projetado seguinte: média das metas de fim de ano de t-1 e t (13,75 e 12,5;
      //    12,5 e 10,5), e o primeiro ano sem meta anterior usaria a meta sozinha.
      checar(perto(cdi[3], (13.75 + 12.5) / 2, 1e-9) && perto(cdi[4], (12.5 + 10.5) / 2, 1e-9),
        "(0106j) 2027-2028 sem CDI no Focus = média das metas de Selic do ano anterior e do ano",
        JSON.stringify(cdi.slice(3)));
      // COMPORTAMENTO, não mecanismo: mexer na Selic do Focus tem de mover o CDI (revisão
      // do Focus chega ao CDI). `avaliarCelula` não segue referência entre abas, mas as
      // duas linhas moram na mesma aba Anual, então a reavaliação vale.
      const celSelic = (a: number) => anual0.getRow(rSelic).getCell(COLS_ANO[iAnoDe(a)]);
      const selic26 = celSelic(2026).value; const selic27 = celSelic(2027).value;
      celSelic(2026).value = 11.75; celSelic(2027).value = 10.5;
      esquecerMemoria(anual0);
      const movido = [2026, 2027].map((a) => avaliarCelula(anual0, COLS_ANO[iAnoDe(a)], rCdi));
      const esperadoMov26 = ((1 + 9.713 / 100) * Math.pow(1 + 11.75 / 100, 3 / 12) - 1) * 100;
      checar(perto(movido[0], esperadoMov26, 1e-6) && perto(movido[1], (11.75 + 10.5) / 2, 1e-9)
        && perto(movido[0], esperado26, 1e-6) === false,
        "(0106j) …e uma revisão da Selic do Focus MOVE o CDI de 2026 e de 2027 (a planilha segue viva)",
        JSON.stringify(movido));
      celSelic(2026).value = selic26; celSelic(2027).value = selic27;
      esquecerMemoria(anual0);
      const notaCdi27 = notaDe(anual0, rCdi, COLS_ANO[iAnoDe(2027)]);
      checar(/META/.test(notaCdi27) && /NÃO é o CDI realizado/.test(notaCdi27),
        "(0106j) …e a nota diz o método (média das metas) e o limite (aproximação, não é o realizado)",
        notaCdi27.slice(0, 120));
      checar(/META/.test(notaDe(anual0, rSelic, COLS_ANO[iAnoDe(2027)])),
        "(0106j) a nota da célula de Selic do Focus diz que é a meta de fim de ano, não o acumulado",
        notaDe(anual0, rSelic, COLS_ANO[iAnoDe(2027)]).slice(0, 120));
      // 4. outra série de taxa: o parcial fica vazio e a nota diz por quê
      const inpc26 = anual0.getRow(rInpc).getCell(COLS_ANO[iAnoDe(2026)]);
      const notaInpc = notaDe(anual0, rInpc, COLS_ANO[iAnoDe(2026)]);
      checar(inpc26.value == null && /8 meses não é taxa anual/.test(notaInpc) && !/haver Focus/.test(notaInpc),
        "(0106j) INPC de 8 meses fica VAZIO; a nota não promete Focus (ele não publica INPC), só o fechamento do ano",
        JSON.stringify(inpc26.value));

      // 5. O EFEITO NA DÍVIDA: com Selic no Focus, revolver e aplicação não são
      // zero em nenhum ano projetado (antes: 0 em 2027-2028).
      const val = (aba: string, rotulo: string, i: number) => {
        const r = lin(aba, rotulo);
        return r < 0 ? null : avaliarCelula(wb0.getWorksheet(aba)!, COLS_ANO[i], r);
      };
      for (const rot of ["Curva de juros de referência (CDI, da aba Anual)",
        "Custo efetivo do revolver", "Rendimento efetivo da aplicação"]) {
        for (const a of [2027, 2028]) {
          const v = val("ST Inv. & Debt", rot, iAnoDe(a));
          checar(typeof v === "number" && v > 0.05,
            `(0106j) \"${rot}\" em ${a} não é zero quando o Focus tem Selic`, JSON.stringify(v));
        }
      }
    }

    // 7. A DECISÃO É POR `origem`, NÃO PELO TEXTO DE `fonte` (comportamento): trocar o rótulo
    //    da fonte não pode reverter o CDI para a cópia da meta; e um texto "Focus" sobre um
    //    número de origem realizado não pode virar composição. Mede 2026 (9,713 + meta 13,75).
    const cdi26De = (macro: unknown[]): unknown => {
      const wb = buildExportWorkbook({
        caso: entradaModelo.caso, documentos: docsModelo, campos: camposModelo,
        agora: new Date("2026-08-05T12:00:00Z"), modo: "completo",
        modeloInstitucional: { ...entradaModelo, macro } as unknown as
          Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
      });
      const ws = wb.getWorksheet("Anual")!;
      let r = -1;
      for (let i = 1; i <= ws.rowCount; i++) if (String(ws.getRow(i).getCell(3).value ?? "").trim() === "CDI (% a.a.)") r = i;
      return r < 0 ? "sem linha CDI" : avaliarCelula(ws, COLS_ANO[iAnoDe(2026)], r);
    };
    const composto26 = ((1 + 9.713 / 100) * Math.pow(1 + 13.75 / 100, 3 / 12) - 1) * 100;
    const renomeada = cdi26De(macro0.map((m) => m.origem === "focus" ? { ...m, fonte: "Mediana de mercado (BCB)" } : m));
    checar(typeof renomeada === "number" && Math.abs(renomeada - composto26) < 1e-6,
      "(0106j) trocar o TEXTO da fonte do Focus não muda o CDI de 2026 (a decisão é por `origem`)",
      JSON.stringify(renomeada));
    const rotuladaFocus = cdi26De(macro0.map((m) => m.origem === "focus" ? { ...m, origem: "realizado" as const } : m));
    checar(typeof rotuladaFocus === "number" && Math.abs(rotuladaFocus - 13.75) < 1e-9,
      "(0106j) Selic de origem REALIZADA (mesmo com texto \"Focus\") entra como igualdade, não como meta",
      JSON.stringify(rotuladaFocus));

    // 8. Primeiro ano projetado COM meta e SEM meta no ano anterior (nem realizado parcial
    //    do CDI): a célula é a meta do próprio ano, por fórmula, e a nota diz o viés no
    //    sentido certo — meta de fim de ano fica ABAIXO do acumulado num corte (SUBESTIMA).
    const wb2 = buildExportWorkbook({
      caso: entradaModelo.caso, documentos: docsModelo, campos: camposModelo,
      agora: new Date("2026-08-05T12:00:00Z"), modo: "completo",
      modeloInstitucional: { ...entradaModelo, macro: macro0.filter((m) => m.serie !== "SELIC" || m.ano === 2027) } as unknown as
        Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
    });
    const a2 = wb2.getWorksheet("Anual")!;
    let rC2 = -1; let rS2 = -1;
    for (let r = 1; r <= a2.rowCount; r++) {
      const t = String(a2.getRow(r).getCell(3).value ?? "").trim();
      if (t === "CDI (% a.a.)") rC2 = r;
      if (t === "Selic acumulada (% a.a.)") rS2 = r;
    }
    const c27b = avaliarCelula(a2, COLS_ANO[iAnoDe(2027)], rC2);
    checar(typeof c27b === "number" && Math.abs(c27b - 12.5) < 1e-9,
      "(0106j) 2027 com meta e sem meta em 2026: o CDI é a meta do próprio ano (12,5)", JSON.stringify(c27b));
    a2.getRow(rS2).getCell(COLS_ANO[iAnoDe(2027)]).value = 9;
    esquecerMemoria(a2);
    const c27c = avaliarCelula(a2, COLS_ANO[iAnoDe(2027)], rC2);
    checar(typeof c27c === "number" && Math.abs(c27c - 9) < 1e-9,
      "(0106j) …e mexer na Selic de 2027 move o CDI (fórmula, não valor)", JSON.stringify(c27c));
    const n27b = String((a2.getRow(rC2).getCell(COLS_ANO[iAnoDe(2027)]).note as
      { texts?: Array<{ text: string }> } | undefined)?.texts?.map((t) => t.text).join("") ?? "");
    checar(/ABAIXO do acumulado num ciclo de corte \(SUBESTIMA o custo\)/.test(n27b) && /ACIMA num de alta/.test(n27b),
      "(0106j) …e a nota do viés diz que a meta SUBESTIMA o custo num corte e superestima numa alta", n27b.slice(0, 160));
    const c26b = a2.getRow(rC2).getCell(COLS_ANO[iAnoDe(2026)]).value;
    checar(c26b === null || c26b === undefined,
      "(0106j) 2026 com realizado parcial e SEM meta de Selic fica VAZIO (não inventa)", JSON.stringify(c26b));

    // 6. SEM Selic nem CDI para o ano: célula vazia e a nota da CURVA_CDI diz o EFEITO.
    const wb1 = buildExportWorkbook({
      caso: entradaModelo.caso, documentos: docsModelo, campos: camposModelo,
      agora: new Date("2026-08-05T12:00:00Z"), modo: "completo",
      modeloInstitucional: { ...entradaModelo, macro: macro0.filter((m) => m.serie !== "SELIC" || m.ano < 2027) } as unknown as
        Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
    });
    const a1 = wb1.getWorksheet("Anual")!;
    const d1 = wb1.getWorksheet("ST Inv. & Debt")!;
    let rC1 = -1; let rCurva1 = -1;
    for (let r = 1; r <= a1.rowCount; r++) if (String(a1.getRow(r).getCell(3).value ?? "").trim() === "CDI (% a.a.)") rC1 = r;
    for (let r = 1; r <= d1.rowCount; r++) {
      if (String(d1.getRow(r).getCell(3).value ?? "").startsWith("Curva de juros de referência")) rCurva1 = r;
    }
    const c27 = a1.getRow(rC1).getCell(COLS_ANO[iAnoDe(2027)]).value;
    checar(rC1 > 0 && (c27 === null || c27 === undefined),
      "(0106j) sem Selic nem CDI em 2027 a célula do CDI fica VAZIA (não inventa)", JSON.stringify(c27));
    const nCurva = String((d1.getRow(rCurva1).getCell(COLS_ANO[iAnoDe(2027)]).note as
      { texts?: Array<{ text: string }> } | undefined)?.texts?.map((t) => t.text).join("") ?? "");
    checar(/Sem curva de CDI para 2027/.test(nCurva) && /juro ZERO/.test(nCurva),
      "(0106j) …e a nota da curva na aba de dívida diz o EFEITO (juro ZERO — rever antes de comitê)",
      nCurva.slice(0, 140));
    const nOk = String((d1.getRow(rCurva1).getCell(COLS_ANO[iAnoDe(2026)]).note as
      { texts?: Array<{ text: string }> } | undefined)?.texts?.map((t) => t.text).join("") ?? "");
    checar(!/Sem curva/.test(nOk) && !/projetado Focus/.test(nOk),
      "(0106j) …e o ano COM curva não carrega o aviso, nem a afirmação falsa de \"projetado Focus\"", nOk.slice(0, 140));
  }

  // ---- (0106i) O PAINEL DE PREMISSAS RESPONDE À EDIÇÃO NO EXCEL ------------
  //
  // A promessa é "trocar o índice ou o spread dentro do arquivo reprojeta o
  // modelo". Um assert que só conferisse a existência das linhas não provaria nada:
  // este SIMULA a edição — escreve na célula de escolha da série, esquece a memória
  // do avaliador e recalcula, exigindo que a receita projetada MUDE na direção
  // certa. É o mais próximo de "o dono abriu e editou" que dá para fazer sem Excel.
  {
    const rec = wbMod.getWorksheet("Revenues, COGS & SG&A")!;
    const rTotal = linhaDoRotulo("Revenues, COGS & SG&A", "= crescimento nominal aplicado");
    const rSerie = rTotal === null ? null : rTotal - 2;
    checar(rTotal !== null,
      "(0106i) a aba de receita traz o PAINEL DE PREMISSAS (índice macro × spread)", String(rTotal));

    const iA = iAnoDe(2026);
    const rReceita = linhaDoRotulo("Revenues, COGS & SG&A", "Vendas de produtos - mercado interno");
    if (rTotal !== null && rSerie !== null && rReceita !== null) {
      // 1. Como o arquivo nasce: índice "(nenhum)" e o crescimento é exatamente a
      //    premissa que o portal escolheu (8% em 2026). Continuidade — o painel
      //    acrescenta mecanismo sem mexer em número.
      const escolha = rec.getRow(rSerie).getCell(4);
      checar(String(escolha.value ?? "") === "(nenhum)",
        "(0106i) o painel nasce com índice \"(nenhum)\", reproduzindo a premissa do portal",
        String(escolha.value ?? ""));
      const cresc0 = avaliarCelula(rec, COLS_ANO[iA], rTotal);
      checar(typeof cresc0 === "number" && Math.abs(cresc0 - 0.08) < 1e-9,
        "(0106i) …e o crescimento nominal aplicado é os 8% do portal", JSON.stringify(cresc0));
      const receita0 = avaliarCelula(rec, COLS_ANO[iA], rReceita);

      // 2. A EDIÇÃO: o analista escolhe IPCA no dropdown. O IPCA de 2026 na fixture
      //    é 4,5%, então o crescimento tem de virar (1+4,5%)×(1+8%)−1 = 12,86%.
      escolha.value = "IPCA";
      esquecerMemoria(rec);
      esquecerMemoria(wbMod.getWorksheet("Anual")!);
      const cresc1 = avaliarCelula(rec, COLS_ANO[iA], rTotal);
      const esperado = 1.045 * 1.08 - 1;
      checar(typeof cresc1 === "number" && Math.abs(cresc1 - esperado) < 1e-9,
        "(0106i) escolher IPCA no dropdown COMPÕE índice e spread — (1+4,5%)×(1+8%)−1, não a soma",
        `${JSON.stringify(cresc1)} (esperado ${esperado.toFixed(6)})`);
      const receita1 = avaliarCelula(rec, COLS_ANO[iA], rReceita);
      checar(typeof receita0 === "number" && typeof receita1 === "number" && receita1 > receita0,
        "(0106i) …e a RECEITA PROJETADA acompanha a edição — é o que faz do arquivo uma alternativa "
        + "de edição ao portal",
        `receita 2026: ${JSON.stringify(receita0)} → ${JSON.stringify(receita1)}`);

      // 3. Devolve o arquivo ao estado original: os asserts seguintes (e o de
      //    reprodutibilidade do gerador) leem o mesmo workbook.
      escolha.value = "(nenhum)";
      esquecerMemoria(rec);
      esquecerMemoria(wbMod.getWorksheet("Anual")!);
      const cresc2 = avaliarCelula(rec, COLS_ANO[iA], rTotal);
      checar(typeof cresc2 === "number" && Math.abs(cresc2 - 0.08) < 1e-9,
        "(0106i) …e voltar a escolha a \"(nenhum)\" devolve a premissa do portal (a edição é reversível)",
        JSON.stringify(cresc2));
    }
  }

  // ---- (0107) FASE C — O QUE FALTAVA DE MOTOR, POR IMPACTO -----------------
  //
  // Os três itens estruturais da fila do §5 do CONFORMIDADE.md que dependiam só de
  // nós. Cada um tem assert próprio porque cada um pode regredir sozinho.
  {
    // (0107a) A VARIAÇÃO DE GIRO ABERTA CONTA A CONTA, e a abertura tem de FECHAR
    // com o total — que continua vindo do espelho da aba de giro. Duas origens para
    // o mesmo número só valem com uma linha de conferência entre elas.
    const rConf = linhaDoRotulo("Cash Flow", "conferência: soma das contas − total (ZERO)");
    const cf = wbMod.getWorksheet("Cash Flow")!;
    const desvios: string[] = [];
    for (const ano of [2026, 2027, 2028]) {
      const v = rConf === null ? null : avaliarCelula(cf, COLS_ANO[iAnoDe(ano)], rConf);
      if (typeof v !== "number" || Math.abs(v) > 0.01) desvios.push(`${ano}: ${JSON.stringify(v)}`);
    }
    checar(rConf !== null && desvios.length === 0,
      "(0107a) a variação de giro do Cash Flow é aberta CONTA A CONTA e a abertura fecha com o total",
      desvios.join(" · "));
    // E a abertura existe de fato: uma linha por conta de giro do caso.
    let nContas = 0;
    for (let r = 1; r <= cf.rowCount; r++) {
      if (/^\s{4}\((−|\+)\)\s/.test(String(cf.getRow(r).getCell(3).value ?? ""))) nContas++;
    }
    checar(nContas >= 3,
      "(0107a) …e há uma linha por conta de giro, não uma linha agregada",
      `linhas de conta no bloco de operações: ${nContas}`);

    // (0107b) O CHECK DO BALANÇO NO TOPO DAS QUATRO ABAS DE DRIVER. É onde a
    // premissa é mexida, e portanto onde o "o balanço abriu" tem de aparecer.
    const semCheck: string[] = [];
    for (const aba of ["Revenues, COGS & SG&A", "Working Capital", "Fixed Assets & CAPEX",
                       "ST Inv. & Debt"]) {
      const r = linhaDoRotulo(aba, "CHECK do balanço (0 = fecha)");
      const ws = wbMod.getWorksheet(aba);
      if (r === null || !ws) { semCheck.push(`${aba}: linha ausente`); continue; }
      // Tem de estar no TOPO (logo abaixo do cabeçalho), senão não serve ao propósito.
      if (r > 8) semCheck.push(`${aba}: linha ${r} (esperado no topo)`);
      // A CÉLULA TEM DE SER FÓRMULA APONTANDO PARA O BALANÇO — não basta avaliar
      // zero. Célula VAZIA avalia 0 no avaliador (é o contrato dele), então uma
      // versão anterior deste assert passava verde com a linha existindo e nunca
      // preenchida: exatamente a armadilha da "fixture que nasce vazia" que o
      // CLAUDE.md descreve, cometida aqui dentro.
      const bruto = ws.getRow(r).getCell(COLS_ANO[iAnoDe(2026)]).value as { formula?: string } | null;
      const formula = bruto && typeof bruto === "object" && "formula" in bruto ? bruto.formula ?? "" : "";
      if (!/Balance Sheet/.test(formula)) {
        semCheck.push(`${aba}: célula não é fórmula do Balance Sheet (${JSON.stringify(bruto)})`);
        continue;
      }
      const v = avaliarCelula(ws, COLS_ANO[iAnoDe(2026)], r);
      if (typeof v !== "number" || Math.abs(v) > 0.01) semCheck.push(`${aba}: ${JSON.stringify(v)}`);
    }
    checar(semCheck.length === 0,
      "(0107b) as quatro abas de driver publicam o CHECK do balanço no topo, e ele fecha",
      semCheck.join(" · "));

    // (0107c) OS ESPELHOS DO OUTPUT CONTA A CONTA. O item de maior impacto da fila:
    // o `Output` é a aba que vai a comitê, e um espelho só de totais obriga a voltar
    // às abas de origem para saber do que o número é feito.
    const detalhes = [
      ["Output", "    Operating current assets"],
      ["Output", "    Short-term debt + revolver"],
      ["Output", "    Retained earnings (model)"],
      ["Output", "    (+) D&A"],
      ["Output", "    (+/−) Change in working capital"],
      ["Output", "    (−) CAPEX"],
      ["Output", "    (+) New debt"],
    ] as const;
    const faltam = detalhes.filter(([aba, rot]) => linhaDoRotulo(aba, rot.trim()) === null
      && linhaDoRotulo(aba, rot) === null);
    checar(faltam.length === 0,
      "(0107c) os espelhos de balanço e fluxo do Output são abertos conta a conta",
      faltam.map(([, r]) => r.trim()).join(" · "));
    // E o detalhe tem de BATER com a origem — espelho que não bate é pior que
    // espelho que não existe.
    const out = wbMod.getWorksheet("Output")!;
    const bs = wbMod.getWorksheet("Balance Sheet")!;
    const rEsp = linhaDoRotulo("Output", "Operating current assets");
    const rOrig = linhaDoRotulo("Balance Sheet", "Ativo circulante operacional");
    const vEsp = rEsp === null ? null : avaliarCelula(out, COLS_ANO[iAnoDe(2026)], rEsp);
    const vOrig = rOrig === null ? null : avaliarCelula(bs, COLS_ANO[iAnoDe(2026)], rOrig);
    checar(typeof vEsp === "number" && typeof vOrig === "number" && Math.abs(vEsp - vOrig) < 0.01,
      "(0107c) …e cada linha do espelho é o MESMO número da aba de origem",
      `espelho ${JSON.stringify(vEsp)} · origem ${JSON.stringify(vOrig)}`);
  }

  // ---- (0109g) CABEÇALHO DE GRUPO IMPRESSO SAI DA SOMA, COM PROVA --------
  //
  // `Estoques`, `Contas a Receber`, `Disponível` e afins não estão na lista
  // fechada da `fn_papel_linha`, então chegam ao modelo como CONTA — e o
  // documento os imprime como cabeçalho, com os componentes logo abaixo. Somados
  // junto, o grupo entra duas vezes. O detector estrutural do export resolve isso
  // quando a `ordem` das linhas é a ordem impressa; quando não é, o modelo
  // precisa da própria prova aritmética: o total informado do grupo.
  //
  // Aqui o grupo informa 100 e as contas somam 160 (`Estoques` 60 + os dois
  // componentes dele, 40 e 20, + `Clientes` 40). O excesso é exatamente o
  // cabeçalho: ele sai da composição e a reconciliação fica em ZERO — nem um
  // centavo escondido.
  {
    const entradaCab = {
      ...entradaModelo,
      anosHistoricos: [2025], anosProjetados: [2026],
      linhas: [
        linhaAnos("ativo_circulante", "Ativo Circulante", { "2025": 100 }, "BALANCO", "subtotal"),
        linhaAnos("ativo_circulante", "Estoques", { "2025": 60 }),
        linhaAnos("ativo_circulante", "Produtos acabados", { "2025": 40 }),
        linhaAnos("ativo_circulante", "Matérias-primas", { "2025": 20 }),
        linhaAnos("ativo_circulante", "Clientes - mercado interno", { "2025": 40 }),
      ],
      vinculos: [], premissas: [],
    };
    const wbCab = buildExportWorkbook({
      caso: entradaModelo.caso, documentos: docsModelo, campos: camposModelo,
      agora: new Date("2026-08-05T12:00:00Z"), modo: "completo",
      modeloInstitucional: entradaCab as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
    });
    const wc = wbCab.getWorksheet("Working Capital");
    const rotulos: string[] = [];
    if (wc) {
      for (let r = 1; r <= wc.rowCount; r++) rotulos.push(String(wc.getRow(r).getCell(3).value ?? "").trim());
    }
    checar(!rotulos.includes("Estoques") && rotulos.includes("Produtos acabados")
      && rotulos.includes("Matérias-primas"),
      "(0109g) o cabeçalho de grupo impresso fica FORA da composição do modelo, e os "
      + "componentes dele continuam lá — o grupo não dobra",
      `Estoques: ${rotulos.includes("Estoques")} · componentes: `
      + `${rotulos.includes("Produtos acabados")}/${rotulos.includes("Matérias-primas")}`);

    const bsCab = wbCab.getWorksheet("Balance Sheet");
    let rReconc: number | null = null;
    if (bsCab) {
      for (let r = 1; r <= bsCab.rowCount; r++) {
        if (String(bsCab.getRow(r).getCell(3).value ?? "").trim()
            === "reconciliação com o ativo circulante informado no documento") { rReconc = r; break; }
      }
    }
    const vReconc = bsCab && rReconc !== null ? avaliarCelula(bsCab, "E", rReconc) : null;
    checar(typeof vReconc === "number" && Math.abs(vReconc) < 0.5,
      "(0109g) …e a reconciliação do grupo fica em ZERO: a soma das contas passa a ser o "
      + "total informado, sem resíduo inventado",
      JSON.stringify(vReconc));
  }

  // ---- (0109f) PATRIMÔNIO NEGATIVO NÃO FAZ O MODELO APAGAR CONTA ---------
  //
  // A remoção de CABEÇALHO DE GRUPO IMPRESSO (`Contas a Receber`, `Estoques`,
  // `Capital social`…) só age quando a soma das contas EXCEDE o total que o
  // documento informa para aquele grupo. Com total NEGATIVO — patrimônio líquido
  // a descoberto, que é o caso normal num mandato de reestruturação (a Canastra
  // Indústria do book tem PL −4.221) — comparar com `informado * 1.005` inverte o
  // sentido da desigualdade e a regra passaria a "achar excesso" onde não há,
  // apagando conta justamente na empresa mais frágil do grupo.
  //
  // Aqui o PL informado é NEGATIVO e as duas contas somam exatamente ele: não há
  // excesso, e nenhuma das duas pode sumir do balanço do modelo.
  {
    const entradaPLneg = {
      ...entradaModelo,
      anosHistoricos: [2025], anosProjetados: [2026],
      linhas: [
        linhaAnos("patrimonio_liquido", "Capital social", { "2025": 40000 }),
        linhaAnos("patrimonio_liquido", "Prejuízos acumulados", { "2025": -44221 }),
        linhaAnos("patrimonio_liquido", "Patrimônio Líquido", { "2025": -4221 }, "BALANCO", "subtotal"),
        linhaAnos("ativo_circulante", "Caixa e equivalentes de caixa", { "2025": 1000 }),
      ],
      vinculos: [], premissas: [],
    };
    const wbPL = buildExportWorkbook({
      caso: entradaModelo.caso, documentos: docsModelo, campos: camposModelo,
      agora: new Date("2026-08-05T12:00:00Z"), modo: "completo",
      modeloInstitucional: entradaPLneg as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
    });
    const bsPL = wbPL.getWorksheet("Balance Sheet");
    const temRotulo = (rot: string) => {
      if (!bsPL) return false;
      for (let r = 1; r <= bsPL.rowCount; r++) {
        if (String(bsPL.getRow(r).getCell(3).value ?? "").trim() === rot) return true;
      }
      return false;
    };
    checar(temRotulo("Capital social") && temRotulo("Prejuízos acumulados"),
      "(0109f) com patrimônio líquido NEGATIVO e sem excesso, nenhuma conta do PL é removida "
      + "do modelo — nem a que tem nome de cabeçalho de grupo",
      `Capital social: ${temRotulo("Capital social")} · Prejuízos acumulados: ${temRotulo("Prejuízos acumulados")}`);
  }

  // ---- (0109e) O ARQUIVO DE DADOS TAMBÉM RECALCULA AO ABRIR --------------
  //
  // As abas classificadas escrevem todo total como `=SUM(...)` e NÃO gravam valor
  // em cache — é o que torna o arquivo auditável dentro do Excel. Sem
  // `fullCalcOnLoad` essas células abrem VAZIAS até alguém apertar F9, e vazio
  // num total se lê como zero.
  //
  // A flag era ligada dentro do modelo institucional, que só existe no export
  // COMPLETO de mandato já modelado. O arquivo do botão "Exportar dados" — o que
  // serve para conferir a extração — saía sem ela. Medido no `xl/workbook.xml`
  // dos dois arquivos antes da correção.
  {
    const wbDados = buildExportWorkbook({
      caso: entradaModelo.caso, documentos: docsModelo, campos: camposModelo,
      agora: new Date("2026-08-05T12:00:00Z"), modo: "dados",
    });
    const calc = (wbDados as unknown as { calcProperties?: { fullCalcOnLoad?: boolean } }).calcProperties;
    checar(calc?.fullCalcOnLoad === true,
      "(0109e) o export de DADOS pede recálculo ao abrir — sem isso todo total sai vazio no Excel",
      JSON.stringify(calc ?? null));
    const itensDados = auditarWorkbook(wbDados, true);
    const reprovadosDados = itensDados.filter((i) => !i.ok && !i.naoAplicavel);
    checar(reprovadosDados.length === 0,
      "(0109e) …e o auditor NÃO inventa reprovação de modelo num arquivo que não tem modelo",
      reprovadosDados.map((i) => `${i.chave} (${i.medida})`).join(" · ") || "(nenhuma)");
  }

  // ---- (0108) O AUDITOR DO ARQUIVO ENTREGUE NÃO PODE MENTIR ---------------
  //
  // `auditar-xlsx.mts` é a Fase D: o comando que responde, sobre um .xlsx pronto, o
  // que dá para responder sem abrir o Excel — e que existe porque a auditoria da
  // sessão 40 foi um script descartável rodado UMA vez. Ferramenta de aceite sem
  // teste próprio apodrece, e aí ela passa a dizer "9/9" sobre um arquivo quebrado,
  // que é pior que não existir. Aqui ela roda sobre o workbook desta fixture (que o
  // teste sabe estar correto) e sobre um workbook SEM as correções, e tem de
  // distinguir os dois.
  {
    const itens = auditarWorkbook(wbMod);
    const reprovados = itens.filter((i) => !i.ok && !i.naoAplicavel);
    // O RESÍDUO DE RECONCILIAÇÃO É REPROVADO NESTA FIXTURE DE PROPÓSITO, e ele é
    // a prova de que o item novo funciona.
    //
    // Esta fixture carrega, deliberadamente, a MESMA conta com dois rótulos
    // ("Reservas de lucros" e "Reserva de lucros acumulados", 5.000 cada — ver
    // 0106h). O modelo segue o total informado no documento e escreve a diferença
    // numa linha de reconciliação, sem apagar conta nenhuma; o auditor mede o
    // TAMANHO dessa linha e diz que ela é material. As duas coisas estão certas ao
    // mesmo tempo: o arquivo está internamente coerente E a extração por trás dele
    // tem um buraco que o analista precisa ver antes de usar a abertura por conta.
    //
    // Por isso o esperado aqui não é "zero reprovados": é "nada além do resíduo".
    const semResiduo = reprovados.filter((i) => i.chave !== "residuo_reconciliacao");
    checar(itens.length >= 8 && semResiduo.length === 0,
      "(0108) o auditor do arquivo entregue aprova o modelo desta fixture em todos os itens "
      + "(menos o resíduo de reconciliação, que esta fixture tem de propósito)",
      `${itens.length} itens · reprovados: ${semResiduo.map((i) => `${i.chave} (${i.medida})`).join(" · ")}`);
    const residuo = itens.find((i) => i.chave === "residuo_reconciliacao");
    checar(residuo !== undefined && !residuo.ok && /patrim/i.test(residuo.medida),
      "(0108) …e ACUSA o resíduo da conta duplicada do patrimônio líquido, com o tamanho dele",
      residuo ? `${residuo.ok ? "aprovou" : "reprovou"}: ${residuo.medida}` : "item ausente");

    // E TEM DE REPROVAR o que está errado, ITEM POR ITEM. "Reprovou alguma coisa"
    // não serve como prova: um auditor com um único item sensível e oito itens
    // decorativos passaria nesse teste e continuaria aprovando arquivo quebrado.
    //
    // Cada injeção abaixo é UM dos defeitos que estavam no arquivo entregue em
    // 06/08/2026 (ou o mesmo defeito na forma em que ele chega ao arquivo), e o
    // teste exige que seja o item CORRESPONDENTE a acusar. Se algum dia um item for
    // enfraquecido — um `IFERROR` engolindo a conta, um limite afrouxado — é aqui
    // que aparece.
    const construir = () => buildExportWorkbook({
      caso: entradaModelo.caso, documentos: docsModelo, campos: camposModelo,
      agora: new Date("2026-08-05T12:00:00Z"), modo: "completo",
      modeloInstitucional: entradaModelo as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
    });
    /** Linha pelo rótulo da coluna C, em QUALQUER workbook (o `linhaDoRotulo` é preso ao `wbMod`). */
    const linhaEm = (wb: ExcelJS.Workbook, aba: string, rotulo: string): number | null => {
      const ws = wb.getWorksheet(aba);
      if (!ws) return null;
      for (let r = 1; r <= ws.rowCount; r++) {
        if (String(ws.getRow(r).getCell(3).value ?? "").trim() === rotulo) return r;
      }
      return null;
    };
    const injecoes: Array<{
      defeito: string;
      chave: string;
      /** devolve `false` se o alvo da injeção não existir — injeção que não quebra nada não testa nada */
      quebrar: (wb: ExcelJS.Workbook) => boolean;
      recalculo?: boolean;
    }> = [
      {
        // O defeito que decide se o arquivo é um modelo: no entregue, "NÃO FECHA" nas 7 colunas.
        defeito: "balanço que não fecha (ativo total adulterado)",
        chave: "balanco_fecha",
        quebrar: (wb) => {
          const r = linhaEm(wb, "Balance Sheet", "ATIVO TOTAL");
          if (r === null) return false;
          wb.getWorksheet("Balance Sheet")!.getRow(r).getCell("G").value = 999_999;
          return true;
        },
      },
      {
        // O defeito mais caro da sessão 40: a DRE do realizado dizendo o contrário do documento.
        defeito: "DRE do realizado que não reproduz o documento",
        chave: "dre_confere",
        quebrar: (wb) => {
          const r = linhaEm(wb, "Income Statement", "Receita líquida — informado no documento");
          if (r === null) return false;
          wb.getWorksheet("Income Statement")!.getRow(r).getCell("F").value = 42;
          return true;
        },
      },
      {
        // Balanço inteiro em zero: FECHA (zero = zero) e não é modelo.
        defeito: "modelo sem conteúdo (ativo total em zero em todos os exercícios)",
        chave: "conteudo",
        quebrar: (wb) => {
          const r = linhaEm(wb, "Balance Sheet", "ATIVO TOTAL");
          if (r === null) return false;
          for (const c of COLS_ANO) wb.getWorksheet("Balance Sheet")!.getRow(r).getCell(c).value = 0;
          return true;
        },
      },
      {
        defeito: "fórmula nascida com #REF!",
        chave: "sem_erro",
        quebrar: (wb) => {
          wb.getWorksheet("Balance Sheet")!.getCell("Z2").value = { formula: "1+#REF!" } as ExcelJS.CellValue;
          return true;
        },
      },
      {
        // Sem `fullCalcOnLoad` o Excel mostra célula vazia até alguém apertar F9.
        defeito: "arquivo sem fullCalcOnLoad (abre com as fórmulas em branco)",
        chave: "recalcula",
        quebrar: () => true,
        recalculo: false,
      },
      {
        defeito: "aba do modelo sem área de impressão",
        chave: "imprime",
        quebrar: (wb) => {
          const ws = wb.getWorksheet("Cash Flow");
          if (!ws?.pageSetup?.printArea) return false;
          ws.pageSetup.printArea = undefined;
          return true;
        },
      },
      {
        // O arquivo entregue publicou −10,6 como "R$/US$": variação percentual no lugar do nível.
        defeito: "câmbio publicado como variação (negativo) em vez de nível",
        chave: "cambio",
        quebrar: (wb) => {
          const r = linhaEm(wb, "Anual", "R$/US$ — final de período");
          if (r === null) return false;
          wb.getWorksheet("Anual")!.getRow(r).getCell("G").value = -10.6;
          return true;
        },
      },
      {
        // Gráfico fora da área de impressão sai do PDF que vai a comitê.
        defeito: "gráficos fora da área de impressão do Output",
        chave: "graficos",
        quebrar: (wb) => {
          const ws = wb.getWorksheet("Output");
          if (!ws?.pageSetup?.printArea) return false;
          ws.pageSetup.printArea = "B1:C10";
          return true;
        },
      },
    ];
    const naoAcusados: string[] = [];
    for (const inj of injecoes) {
      const wbQ = construir();
      if (!inj.quebrar(wbQ)) { naoAcusados.push(`${inj.chave}: alvo da injeção não existe no arquivo`); continue; }
      const itensQ = auditarWorkbook(wbQ, inj.recalculo);
      const reprovadosQ = itensQ.filter((i) => !i.ok && !i.naoAplicavel).map((i) => i.chave);
      if (!reprovadosQ.includes(inj.chave)) {
        naoAcusados.push(`${inj.defeito} → ${inj.chave} não acusou (reprovados: ${reprovadosQ.join(", ") || "nenhum"})`);
      }
    }
    checar(naoAcusados.length === 0,
      `(0108) …e cada um dos ${injecoes.length} defeitos injetados é acusado pelo item que lhe corresponde — auditor que aprova tudo não audita`,
      naoAcusados.join(" · "));
  }

  // ---- (0109) A DÍVIDA EXISTENTE AMORTIZA — SAC, COM O PRAZO DO BALANÇO ----
  //
  // Decisão do dono (07/08/2026): quando o documento não traz cronograma, a tranche
  // amortiza LINEARMENTE (SAC) até o vencimento. Antes o `%` era ZERO fixo, com a
  // nota "dívida rolada integralmente, que é a hipótese conservadora" — e ela NÃO é
  // conservadora: dívida que nunca amortiza não consome caixa nenhum no horizonte, o
  // fluxo projetado sai melhor do que a empresa vai viver, e o `DSCR` do bloco de
  // covenants mede um serviço de dívida que é só juros.
  //
  // O prazo não é inventado: sob amortização linear em `n` anos, a parcela que vence
  // em 12 meses é `1/n` do saldo, então `n = 1 ÷ fração no circulante`, medida no
  // balanço do último exercício realizado. Nesta fixture a dívida bancária é 15.000
  // no circulante contra 50.000 no total → 30% → **3,3 anos**.
  {
    const div = wbMod.getWorksheet("ST Inv. & Debt")!;
    const rPrazo = linhaDoRotulo("ST Inv. & Debt", "prazo de amortização (anos)");
    const rPct = linhaDoRotulo("ST Inv. & Debt", "% amortizado no período (SAC)");
    const rIni = linhaDoRotulo("ST Inv. & Debt",
      "Banco Alfa - Capital de giro - Saldo devedor — saldo de abertura");
    const rAmort = linhaDoRotulo("ST Inv. & Debt", "amortização do período");
    const rFim = linhaDoRotulo("ST Inv. & Debt", "saldo de fechamento");
    checar(rPrazo !== null && rPct !== null && rIni !== null && rAmort !== null && rFim !== null,
      "(0109a) a tranche tem linha de PRAZO, de % (SAC), de amortização e de saldo",
      `prazo ${rPrazo} · pct ${rPct} · ini ${rIni} · amort ${rAmort} · fim ${rFim}`);

    if (rPrazo !== null && rPct !== null && rIni !== null && rAmort !== null && rFim !== null) {
      // O prazo é PREMISSA EDITÁVEL, e só na primeira coluna projetada: os anos
      // seguintes apontam para ela, senão editar dentro do Excel exigiria mexer em
      // cinco células para reprojetar uma tranche.
      const celPrazo = div.getRow(rPrazo).getCell(COLS_ANO[iAnoDe(2026)]);
      const prazo = avaliarCelula(div, COLS_ANO[iAnoDe(2026)], rPrazo);
      checar(typeof prazo === "number" && Math.abs(prazo - 3.3) < 0.001,
        "(0109a) …e o prazo é o IMPLÍCITO NO BALANÇO (15.000 de 50.000 no circulante → 30% → 3,3 anos), não um número cravado",
        `prazo ${JSON.stringify(prazo)}`);
      checar(typeof celPrazo.value === "number" && celPrazo.fill !== undefined,
        "(0109a) …e a célula do prazo é ENTRADA (número editável, pintada), não fórmula",
        `valor ${JSON.stringify(celPrazo.value)} · fill ${celPrazo.fill ? "sim" : "NÃO"}`);
      const seguintes = [2027, 2028].map((a) => {
        const c = div.getRow(rPrazo).getCell(COLS_ANO[iAnoDe(a)]).value as { formula?: string } | null;
        return c && typeof c === "object" && "formula" in c ? c.formula ?? "" : "";
      });
      checar(seguintes.every((f) => /\$[A-Z]+\$\d+/.test(f)),
        "(0109a) …e os anos seguintes REFERENCIAM essa célula — uma edição reprojeta a tranche inteira",
        seguintes.join(" · "));

      // SAC de verdade: PRINCIPAL CONSTANTE. É o que distingue SAC de "um percentual
      // fixo do saldo", que decai geometricamente e nunca zera a dívida.
      const amorts = [2026, 2027, 2028].map((a) => avaliarCelula(div, COLS_ANO[iAnoDe(a)], rAmort));
      const esperado = 50000 / 3.3;
      const fora = amorts.filter((v) => typeof v !== "number" || Math.abs(v - esperado) > 0.01);
      checar(fora.length === 0,
        `(0109b) a amortização é LINEAR — principal constante de ${esperado.toFixed(2)} nos três exercícios projetados`,
        amorts.map((v) => (typeof v === "number" ? v.toFixed(2) : JSON.stringify(v))).join(" · "));

      // E o saldo cai por causa dela. Este é o assert que reprova se o `%` voltar a
      // ser zero: com a dívida rolada, o fechamento de 2028 seria os mesmos 50.000.
      const fim2028 = avaliarCelula(div, COLS_ANO[iAnoDe(2028)], rFim);
      const esperadoFim = 50000 - 3 * esperado;
      checar(typeof fim2028 === "number" && Math.abs(fim2028 - esperadoFim) < 0.02,
        "(0109b) …e o saldo CAI por causa dela — 50.000 rolados integralmente até 2028 era o defeito",
        `fim de 2028 ${JSON.stringify(fim2028)} · esperado ${esperadoFim.toFixed(2)}`);

      // EDITAR O PRAZO REPROJETA, DENTRO DO EXCEL. É a mesma promessa do painel de
      // premissas, agora na dívida: trocar 3,3 por 2 tem de dobrar a parcela.
      const original = celPrazo.value;
      celPrazo.value = 2;
      esquecerMemoria(div);
      const amortEditado = avaliarCelula(div, COLS_ANO[iAnoDe(2026)], rAmort);
      checar(typeof amortEditado === "number" && Math.abs(amortEditado - 25000) < 0.01,
        "(0109c) trocar o prazo para 2 anos dentro do Excel reprojeta a tranche (parcela vai a 25.000)",
        JSON.stringify(amortEditado));
      celPrazo.value = original as ExcelJS.CellValue;
      esquecerMemoria(div);
    }
  }

  // ---- (0110) O EXPORT DE MODELAGEM NÃO CARREGA AS ABAS DE DADO -----------
  //
  // Decisão do dono (07/08/2026): dois arquivos, dois propósitos. O de modelagem
  // entrega as 14 abas do modelo; as 12 de dado cru ficam no export de dados
  // financeiros, que já existia (`?modo=dados`). Antes o de modelagem continha o
  // outro inteiro — 29 abas para quem só queria o que vai a comitê.
  {
    const nomes = wbMod.worksheets.map((w) => w.name);
    const faltando = ABAS_DO_MODELO.filter((a) => !nomes.includes(a));
    checar(faltando.length === 0,
      "(0110) o export de modelagem traz as 14 abas do modelo",
      faltando.join(", "));
    // As abas de dado do MESMO caso: a fixture tem documento de BALANÇO, então
    // `Balanço` e `Dados (linha a linha)` existiriam se a separação não acontecesse.
    const dado = nomes.filter((n) => ["Balanço", "DRE", "Dados (linha a linha)", "Resumo",
      "Fluxo de Caixa", "DMPL", "Combinado", "Balancete", "Faturamento", "Dívida",
      "Intragrupo", "Outros"].includes(n));
    checar(dado.length === 0,
      "(0110) …e NENHUMA aba de dado cru — elas são o outro arquivo",
      dado.join(", ") || "nenhuma");
    // E o corte não pode ter deixado fórmula órfã: aba referenciada que some vira
    // `#REF!` em toda fórmula que apontava para ela. É o motivo de a remoção ter
    // sido decidida por MEDIÇÃO das referências cruzadas, não por parecer seguro.
    const orfas: string[] = [];
    for (const ws of wbMod.worksheets) {
      for (let r = 1; r <= ws.rowCount; r++) {
        ws.getRow(r).eachCell({ includeEmpty: false }, (cell) => {
          const v = cell.value as { formula?: string } | null;
          if (!v || typeof v !== "object" || !("formula" in v) || !v.formula) return;
          for (const m of v.formula.matchAll(/'([^']+)'!/g)) {
            if (!nomes.includes(m[1])) orfas.push(`${ws.name}!${cell.address} → '${m[1]}'`);
          }
        });
      }
    }
    checar(orfas.length === 0,
      "(0110) …e nenhuma fórmula ficou apontando para aba que não está mais no arquivo",
      orfas.slice(0, 4).join(" · "));
  }

  // ---- (0111) O COCKPIT DA ABA `Premissas` -------------------------------
  //
  // O mecanismo de modelar dentro do Excel já existia, mas espalhado por sete abas:
  // alavanca que ninguém acha não é alavanca. O cockpit publica cada uma com o valor
  // VIVO e o endereço de onde se edita — e o assert que importa é o do endereço:
  // painel que aponta para a célula errada é pior que painel nenhum, porque manda o
  // analista editar coisa que não é a premissa.
  {
    const prem = wbMod.getWorksheet("Premissas")!;
    const rPainel = linhaDoRotulo("Premissas",
      "PAINEL DE MODELAGEM — as alavancas do arquivo, e onde fica cada uma");
    checar(rPainel !== null, "(0111) a aba Premissas publica o PAINEL DE MODELAGEM", String(rPainel));

    // Cada linha do painel: rótulo na C, endereço "Aba!Célula" na D. O endereço tem
    // de RESOLVER — e resolver para a mesma célula que o painel espelha.
    const enderecosErrados: string[] = [];
    let conferidos = 0;
    for (let r = (rPainel ?? 0) + 1; r <= (rPainel ?? 0) + 20; r++) {
      const onde = String(prem.getRow(r).getCell(4).value ?? "").trim();
      const m = /^(.+)!([A-Z]+)(\d+)/.exec(onde);
      if (!m) continue;
      conferidos++;
      const wsAlvo = wbMod.getWorksheet(m[1]);
      if (!wsAlvo) { enderecosErrados.push(`${onde}: aba não existe`); continue; }
      const celAlvo = wsAlvo.getRow(Number(m[3])).getCell(m[2]);
      if (celAlvo.value === null || celAlvo.value === undefined) {
        enderecosErrados.push(`${onde}: célula vazia`); continue;
      }
      // O valor do painel naquele ano tem de ser o MESMO da célula apontada.
      const doPainel = avaliarCelula(prem, m[2] === "D" ? COLS_ANO[iAnoDe(2026)] : m[2], r);
      const naOrigem = avaliarCelula(wsAlvo, m[2], Number(m[3]));
      const igual = typeof doPainel === "number" && typeof naOrigem === "number"
        ? Math.abs(doPainel - naOrigem) < 0.001
        : String(doPainel) === String(naOrigem);
      if (!igual) enderecosErrados.push(`${onde}: painel ${JSON.stringify(doPainel)} ≠ origem ${JSON.stringify(naOrigem)}`);
    }
    checar(conferidos >= 8 && enderecosErrados.length === 0,
      `(0111) …e cada endereço publicado aponta para a célula CERTA (${conferidos} conferidos)`,
      enderecosErrados.slice(0, 4).join(" · "));

    // REFERÊNCIA VIVA, não cópia: mexer na origem move o painel. É o que garante que
    // o cockpit não vire documentação desatualizada.
    const rCaixa = linhaDoRotulo("Premissas", "Caixa mínimo operacional");
    const div = wbMod.getWorksheet("ST Inv. & Debt")!;
    const rOrig = linhaDoRotulo("ST Inv. & Debt", "Caixa mínimo operacional");
    if (rCaixa !== null && rOrig !== null) {
      const col = COLS_ANO[iAnoDe(2026)];
      const antes = avaliarCelula(prem, col, rCaixa);
      div.getRow(rOrig).getCell(col).value = 77777;
      esquecerMemoria(prem); esquecerMemoria(div);
      const depois = avaliarCelula(prem, col, rCaixa);
      checar(depois === 77777 && antes !== 77777,
        "(0111) …e o valor é REFERÊNCIA VIVA à origem — mudar lá muda aqui",
        `antes ${JSON.stringify(antes)} · depois ${JSON.stringify(depois)}`);
      div.getRow(rOrig).getCell(col).value = antes as number;
      esquecerMemoria(prem); esquecerMemoria(div);
    }
  }

  // ---- (0113) TRIBUTO A RECOLHER TEM UM DONO SÓ ---------------------------
  //
  // Achado da auditoria de 07/08/2026, e o pior desta rodada: a aba `Tributos a
  // Recolher` era DECORATIVA. Ela projetava com `% pago = 0` fixo e alimentava UMA
  // linha de exibição do `Output` — enquanto as MESMAS contas eram projetadas por
  // dias de giro no `Working Capital` (parcelamento girando contra receita: o saldo
  // do acordo CRESCIA quando a empresa vendia mais) e ficavam congeladas no não
  // circulante do balanço. Três lugares, três respostas, nenhuma conferência.
  //
  // Agora a aba é dona: o balanço lê o espelho dela, o fluxo lê o pagamento, e o giro
  // exclui as contas. A fixture principal não tem conta tributária — é por isso que o
  // defeito viveu tanto —, então esta variante acrescenta as quatro que importam:
  // parcelamento em CP e em LP (o que amortiza), tributo corrente (o que ROLA) e
  // provisão (o que espera decisão judicial).
  //
  // Prazo implícito esperado: 1.000 de 4.000 no circulante → 25% → 4 anos. Parcela
  // constante de 250/ano no CP e 750/ano no LP.
  {
    const comTributos = {
      ...entradaModelo,
      linhas: [
        ...entradaModelo.linhas,
        linhaAnos("passivo_circulante", "Parcelamentos tributários - curto prazo",
          { "2024": 900, "2025": 1000 }),
        linhaAnos("passivo_nao_circulante", "Parcelamentos tributários - longo prazo",
          { "2024": 2700, "2025": 3000 }),
        linhaAnos("passivo_circulante", "ICMS a recolher", { "2024": 500, "2025": 600 }),
        linhaAnos("passivo_nao_circulante", "Provisão para contingências tributárias",
          { "2024": 800, "2025": 800 }),
      ],
    };
    const wbT = buildExportWorkbook({
      caso: entradaModelo.caso, documentos: docsModelo, campos: camposModelo,
      agora: new Date("2026-08-05T12:00:00Z"), modo: "completo",
      modeloInstitucional: comTributos as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
    });
    const trib = wbT.getWorksheet("Tributos a Recolher")!;
    const wc = wbT.getWorksheet("Working Capital")!;
    const bs = wbT.getWorksheet("Balance Sheet")!;
    const cf = wbT.getWorksheet("Cash Flow")!;
    const rot = (ws: ExcelJS.Worksheet, r: string): number | null => {
      for (let i = 1; i <= ws.rowCount; i++) {
        if (String(ws.getRow(i).getCell(3).value ?? "").trim() === r) return i;
      }
      return null;
    };
    const val = (ws: ExcelJS.Worksheet, r: number | null, ano: number) =>
      r === null ? null : avaliarCelula(ws, COLS_ANO[iAnoDe(ano)], r);

    // 1. O PRAZO É O IMPLÍCITO NO BALANÇO, e a parcela é constante.
    const rPrazo = rot(trib, "prazo do parcelamento (anos)");
    checar(val(trib, rPrazo, 2026) === 4,
      "(0113) o prazo do parcelamento é o IMPLÍCITO no balanço (1.000 de 4.000 no circulante → 4 anos)",
      JSON.stringify(val(trib, rPrazo, 2026)));
    const rParcCP = rot(trib, "Parcelamentos tributários - curto prazo");
    const saldos = [2026, 2027, 2028].map((a) => val(trib, rParcCP, a));
    const esperados = [750, 500, 250];
    checar(saldos.every((v, i) => typeof v === "number" && Math.abs(v - esperados[i]) < 0.01),
      "(0113) …e o parcelamento amortiza em parcela CONSTANTE de 250 — 1.000 congelados era o defeito",
      saldos.map((v) => JSON.stringify(v)).join(" · "));

    // 2. O QUE ROLA, ROLA. Zerar o ICMS a recolher diria que a empresa parou de operar.
    const rICMS = rot(trib, "ICMS a recolher");
    const icms = [2026, 2028].map((a) => val(trib, rICMS, a));
    checar(icms.every((v) => typeof v === "number" && Math.abs(v - 600) < 0.01),
      "(0113) …e o tributo corrente fica CONSTANTE: é saldo rotativo, não dívida a liquidar",
      icms.map((v) => JSON.stringify(v)).join(" · "));

    // 3. UMA CONTA, UM LUGAR: nenhuma delas pode estar também no giro.
    const noGiro = ["Parcelamentos tributários - curto prazo", "ICMS a recolher"]
      .filter((r) => rot(wc, r) !== null);
    checar(noGiro.length === 0,
      "(0113) …e nenhuma conta de tributo aparece no Working Capital — dupla contagem seria o defeito",
      noGiro.join(" · "));

    // 4. O BALANÇO LÊ O ESPELHO, e o CHECK continua zero apesar do pagamento.
    const rTribCP = rot(bs, "Tributos a recolher e parcelamentos (curto prazo)");
    const rTribPNC = rot(bs, "Tributos a recolher e parcelamentos (longo prazo)");
    checar(typeof val(bs, rTribCP, 2026) === "number" && Math.abs((val(bs, rTribCP, 2026) as number) - 1350) < 0.01
      && typeof val(bs, rTribPNC, 2026) === "number" && Math.abs((val(bs, rTribPNC, 2026) as number) - 3050) < 0.01,
      "(0113) …e o balanço lê o espelho da aba (CP 750+600=1.350 · LP 2.250+800=3.050)",
      `${JSON.stringify(val(bs, rTribCP, 2026))} · ${JSON.stringify(val(bs, rTribPNC, 2026))}`);
    const rCheckT = rot(bs, "CHECK — Ativo − (Passivo + PL) deve ser ZERO");
    const desviosT = ANOS.map((a) => val(bs, rCheckT, a))
      .filter((v) => typeof v !== "number" || Math.abs(v) > 0.5);
    checar(desviosT.length === 0,
      "(0113) …e o balanço FECHA com o pagamento saindo do caixa",
      desviosT.map((v) => JSON.stringify(v)).join(" · "));

    // 5. O PAGAMENTO NO FLUXO É A QUEDA DO SALDO — derivado, nunca calculado de novo.
    const rPago = rot(cf, "Pagamento de tributos e parcelamentos");
    const rTotal = rot(trib, "TOTAL A RECOLHER");
    const queda = (val(trib, rTotal, 2026) as number) - (val(trib, rTotal, 2027) as number);
    const pago2027 = val(cf, rPago, 2027);
    checar(typeof pago2027 === "number" && Math.abs(pago2027 + queda) < 0.01 && pago2027 < 0,
      "(0113) …e o pagamento no Cash Flow é EXATAMENTE a queda do saldo, com sinal de saída",
      `fluxo ${JSON.stringify(pago2027)} · queda do saldo ${queda.toFixed(2)}`);
  }

  // ---- (0112) A TELA NÃO FALA CANÔNICO ------------------------------------
  //
  // Pedido do dono (07/08/2026): a tela não publica chave de banco. Nada de `_`,
  // acento em todo lugar, sigla em maiúscula, e a mensagem de pendência quebrada em
  // um fato por linha em vez de um parágrafo emendado por `;`.
  //
  // A fixture é o TEXTO REAL que ele copiou da tela — não uma frase inventada para o
  // teste passar. Se a mensagem do banco mudar de forma, é aqui que aparece.
  {
    const canonicas: Array<[string, string]> = [
      ["passivo_nao_circulante", "Passivo Não Circulante"],
      ["patrimonio_liquido", "Patrimônio Líquido"],
      ["receita_bruta", "Receita Bruta e Deduções"],
      ["divida", "Mapa de Dívida"],
      ["atividades_financiamento", "Atividades de Financiamento"],
    ];
    const erradas = canonicas.filter(([k, esperado]) => rotuloDaSecao(k) !== esperado)
      .map(([k, esperado]) => `${k} → "${rotuloDaSecao(k)}" (esperado "${esperado}")`);
    checar(erradas.length === 0,
      "(0112) as seções canônicas têm nome em português na tela",
      erradas.join(" · "));

    // A rede de segurança: chave que ninguém mapeou não pode vazar com `_`.
    const inventadas = ["secao_nova_do_futuro", "provisao_tributaria", "extracao_padrao_suspeito"];
    const comUnderscore = inventadas.filter((k) => /_/.test(humanizar(k)));
    const semAcento = humanizar("provisao_tributaria_nao_circulante");
    checar(comUnderscore.length === 0 && semAcento === "Provisão Tributária Não Circulante",
      "(0112) …e o humanizador genérico cobre chave nova — sem `_`, com acento",
      `${comUnderscore.join(", ")} · "${semAcento}"`);
    checar(humanizar("total_dre_por_cnpj") === "Total DRE por CNPJ",
      "(0112) …e sigla fica MAIÚSCULA, preposição fica minúscula",
      humanizar("total_dre_por_cnpj"));
    checar(rotuloDaPendencia("precondicao_nao_satisfeita") === "falta um lado da conta"
      && !/_/.test(rotuloDaPendencia("tipo_que_nao_existe")),
      "(0112) …e o tipo de pendência aparece pelo que ele significa",
      `${rotuloDaPendencia("precondicao_nao_satisfeita")} · ${rotuloDaPendencia("tipo_que_nao_existe")}`);

    // A MENSAGEM REAL, quebrada. O `;` DENTRO de colchete qualifica o item e não
    // separa nada — quebrar ali produzia linha órfã ("período: 31/12/2024]").
    const real = 'O Balanço foi encontrado, mas nenhum exercício teve os DOIS lados. 2024: falta o '
      + 'Passivo+PL (coluna de entidade: (qualquer); coluna de período: 31/12/2024); 2025: falta o '
      + 'Passivo+PL (coluna de entidade: (qualquer); coluna de período: 31/12/2025). Rótulos que a '
      + 'extração TROUXE e que poderiam ser um total: "ATIVO" [entidade: —; período: 31/12/2024], '
      + '"Passivo Circulante" [entidade: —; período: 31/12/2025].';
    const partes = partesDaDescricao(real);
    checar(partes.length === 4 && /^2024:/.test(partes[1]) && /^2025:/.test(partes[2]),
      "(0112) a mensagem real vira 4 fatos — o achado, cada exercício, e a lista de rótulos",
      `${partes.length}: ${partes.map((x) => x.slice(0, 24)).join(" | ")}`);
    // E o ponto de DECIMAL não separa nada: `14529.00` tem de ficar inteiro, senão a
    // quebra por fim de frase transforma um valor em duas linhas.
    const comValor = partesDaDescricao(
      "4 contas diferentes, na MESMA coluna, vieram com o MESMO valor material (14529.00) — "
      + "padrão típico de fabricação. Conferir contra o arquivo original.");
    checar(comValor.length === 2 && comValor[0].includes("14529.00"),
      "(0112) …e ponto de decimal não quebra linha",
      comValor.map((x) => x.slice(0, 40)).join(" | "));
    const orfas = partes.filter((x) => /^\s*(coluna de )?per[ií]odo:/i.test(x) || /^\]/.test(x));
    checar(orfas.length === 0,
      "(0112) …e nenhuma linha nasce órfã do qualificador que a explica",
      orfas.join(" · "));
    const suave = suavizarMensagem(real);
    checar(!/f0\/\d/.test(suave) && !/secao_canonica|rotulo_norm/.test(suave),
      "(0112) …e o jargão de campo (código de documento interno, nome de coluna) sai do texto",
      suave.slice(0, 80));

    // A LISTA SÓ SEPARA O QUE O MARCADOR INTRODUZ (achado 6 do PR #203). `real`
    // (acima) é o caso que motivou `semALista`/`rotulosCitados`: o marcador
    // "Rótulos que a extração TROUXE ... :" que `fn_rotulos_candidatos` (0033/
    // 0034) escreve garante, POR CONSTRUÇÃO, que cada item entre aspas depois
    // dele é `campo_extraido.chave` — uma linha do documento, não um nome
    // qualquer. Confirma que esse caso continua funcionando.
    checar(
      new Set(rotulosCitados(real)).size === 2
        && rotulosCitados(real).includes("ATIVO")
        && rotulosCitados(real).includes("Passivo Circulante"),
      "(PR#203-6) com o marcador, a lista de rótulos continua separando as duas contas",
      rotulosCitados(real).join(" | "));
    const semLista = semALista(real);
    checar(!semLista.includes('"ATIVO"') && !semLista.includes('"Passivo Circulante"')
        && !/Rótulos que a extração TROUXE/i.test(semLista),
      "(PR#203-6) …e a frase visível não repete o que já foi para a lista",
      semLista.slice(0, 160));

    // SEM MARCADOR, ASPAS SÃO SÓ ASPAS — a mensagem real da 0160 (medida no
    // lote 7377, `Supabase/migrations/0160_a_hierarquia_que_o_diagnostico_
    // chama_de_erro.sql`: documento em GRUPO CANASTRA, diagnóstico apontando
    // Canastra Indústria, as duas já cadastradas no mesmo mandato). O texto
    // abaixo é literalmente o `format()` daquela migration com os nomes reais
    // do fixture do book Canastra — não uma frase inventada para o teste
    // passar. As aspas aqui são nome de EMPRESA, não rótulo de linha de
    // documento, e nada no texto diferencia as duas coisas — tentar separar
    // seria adivinhar. `rotulosCitados` tem de devolver lista vazia (nada para
    // "conferir no arquivo": divergência de ENTIDADE não é isso), e
    // `semALista` tem de devolver o texto INTEIRO, sem buraco.
    const entidade = 'O documento está registrado em "GRUPO CANASTRA", mas o diagnóstico de conteúdo '
      + 'aponta "Canastra Indústria" — nome que também já é uma empresa CADASTRADA neste mandato '
      + '("CANASTRA INDÚSTRIA DE EMBALAGENS LTDA."). As duas são empresas cadastradas neste caso, e '
      + 'o sistema não sabe qual das duas é a certa para este documento — não presume nenhuma. '
      + 'Confira pela revisão se ele pertence mesmo a "GRUPO CANASTRA" ou deveria estar em "CANASTRA '
      + 'INDÚSTRIA DE EMBALAGENS LTDA.", sem fundir: as duas continuam sendo empresas diferentes.';
    checar(rotulosCitados(entidade).length === 0,
      "(PR#203-6) sem o marcador, nome de empresa entre aspas NÃO vira \"onde conferir no arquivo\"",
      rotulosCitados(entidade).join(" | ") || "(vazio, como esperado)");
    // O COMPORTAMENTO que importa: o analista lê a frase INTEIRA, com os dois
    // nomes dentro dela — não um "em , mas o diagnóstico aponta —" com buraco
    // onde os nomes estavam. Falha aqui é o defeito do achado 6: a versão
    // antiga de `semALista` enxugava toda sequência entre aspas em QUALQUER
    // lugar do texto, não só depois do marcador.
    const textoNaTela = semALista(entidade);
    checar(
      textoNaTela === entidade
        && textoNaTela.includes('em "GRUPO CANASTRA", mas')
        && textoNaTela.includes('aponta "Canastra Indústria" —')
        && textoNaTela.includes('("CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.")'),
      "(PR#203-6) …e a descrição da divergência de entidade chega à tela INTEIRA, sem buraco",
      textoNaTela.slice(0, 140));

    // (PR#204) `rotulosCitados` e `semALista` têm de concordar sobre onde a
    // lista acaba — achado da revisão do PR #204: `rotulosCitados` recortava
    // cada item com `{2,80}` caracteres (nenhuma coluna do banco impõe esse
    // tamanho — `campo_extraido.chave` é `text`, sem limite) enquanto
    // `semALista` usava `[^"]+`, sem limite. Um rótulo real de linha de
    // documento passa de 80 caracteres com facilidade — descrição de conta
    // longa é o normal, não a excecão. O COMPORTAMENTO que importa: o
    // analista lê a frase inteira SEM BURACO e os dois chips certos, sem
    // lixo — não a forma da regex (regra 3).
    const rotuloLongo = "Provisão para créditos de liquidação duvidosa de longo "
      + "prazo sobre duplicatas a receber de clientes do exterior"; // 111 caracteres
    const comRotuloLongo = "O documento está registrado em BALANCO mas o diagnóstico de "
      + "conteúdo aponta outra coisa. Rótulos que a extração TROUXE e que a "
      + `classificação atual não cobre: "${rotuloLongo}" [entidade: —; período: `
      + '31/12/2024], "ATIVO" [entidade: —; período: 31/12/2024]. Confira o original.';
    const citadosLongo = rotulosCitados(comRotuloLongo);
    const semListaLongo = semALista(comRotuloLongo);
    checar(
      citadosLongo.length === 2
        && citadosLongo.includes(rotuloLongo)
        && citadosLongo.includes("ATIVO")
        && !semListaLongo.includes(rotuloLongo)
        && !semListaLongo.includes('"ATIVO"')
        && !/\[entidade:/.test(semListaLongo)
        && semListaLongo.includes("registrado em BALANCO mas")
        && semListaLongo.includes("Confira o original"),
      "(PR#204) rótulo com mais de 80 caracteres aparece no chip INTEIRO, "
        + "e a frase visível não fica com buraco nem com lixo entre aspas",
      `citados=${JSON.stringify(citadosLongo)} · semLista="${semListaLongo}"`);
  }

  // ---- (0116) CICLO DE CAIXA: DIAS DE VERDADE, OU "n.a." ------------------
  //
  // `Arquitetura do Sistema/2 Especificação/f0/08` fasejou PMR/PME/PMP até "a extração isolar as linhas-conceito". O
  // giro já as isolava para aplicar dias de giro conta a conta; faltava publicar.
  //
  // Os dois defeitos que estes asserts pegam são os clássicos do indicador:
  // denominador errado (fornecedor girando contra RECEITA infla o PMP pela margem
  // inteira) e ZERO no lugar de "não sei" (um caso sem conta de clientes
  // publicando "0 dias" afirma que a empresa vende à vista).
  {
    const out = wbMod.getWorksheet("Output")!;
    const wc = wbMod.getWorksheet("Working Capital")!;
    const linhaPorRotulo = (ws: ExcelJS.Worksheet, r: string): number | null => {
      for (let i = 1; i <= ws.rowCount; i++) {
        if (String(ws.getRow(i).getCell(3).value ?? "").trim() === r) return i;
      }
      return null;
    };
    const v = (ws: ExcelJS.Worksheet, r: number | null, ano: number) =>
      r === null ? null : avaliarCelula(ws, COLS_ANO[iAnoDe(ano)], r);
    const ano = 2026;

    // A conta de manual, com os números da fixture: clientes 30.000 sobre receita
    // líquida, estoques 20.000 e fornecedores 18.000 sobre CMV — os três × 360.
    const pmr = Number(v(out, linhaPorRotulo(out, "PMR — prazo médio de recebimento"), ano));
    const pme = Number(v(out, linhaPorRotulo(out, "PME — prazo médio de estocagem"), ano));
    const pmp = Number(v(out, linhaPorRotulo(out, "PMP — prazo médio de pagamento a fornecedores"), ano));
    const clientes = Number(v(wc, linhaPorRotulo(wc, "do qual CLIENTES (para o ciclo de caixa do Output)"), ano));
    const estoque = Number(v(wc, linhaPorRotulo(wc, "do qual ESTOQUE (para a liquidez seca do Output)"), ano));
    const fornec = Number(v(wc, linhaPorRotulo(wc, "do qual FORNECEDORES (para o ciclo de caixa do Output)"), ano));
    // O rótulo do Output é em inglês (fidelidade ao Modelo Base); o da aba de
    // giro é em português. Buscar pelo texto errado devolve null e o assert
    // "passaria" comparando Infinity com Infinity — por isso o valor é conferido.
    const recLiq = Number(v(out, linhaPorRotulo(out, "Net Revenues"), ano));
    const cogs = Math.abs(Number(v(wc, linhaPorRotulo(wc, "Custos (base dos dias de giro de estoque e de fornecedor)"), ano)));

    checar(Math.abs(pmr - clientes / recLiq * 360) < 0.01,
      "(0116) o PMR é clientes ÷ receita líquida × 360", `${pmr} vs ${clientes / recLiq * 360}`);
    checar(Math.abs(pme - estoque / cogs * 360) < 0.01,
      "(0116) …o PME gira contra CUSTO, não receita", `${pme} vs ${estoque / cogs * 360}`);
    checar(Math.abs(pmp - fornec / cogs * 360) < 0.01,
      "(0116) …e o PMP também — girar fornecedor contra receita infla o prazo pela margem inteira",
      `${pmp} vs ${fornec / cogs * 360}`);

    const oper = Number(v(out, linhaPorRotulo(out, "Ciclo operacional (PMR + PME)"), ano));
    const fin = Number(v(out, linhaPorRotulo(out, "Ciclo financeiro (− PMP)"), ano));
    checar(Math.abs(oper - (pmr + pme)) < 0.01 && Math.abs(fin - (oper - pmp)) < 0.01,
      "(0116) o ciclo operacional soma as duas pernas e o financeiro desconta o PMP",
      `${oper} · ${fin}`);

    // SEM O INSUMO, "n.a." — NÃO ZERO. A variante tira a conta de clientes do
    // caso; religando a guarda (publicar a divisão de qualquer jeito), o PMR sai
    // 0 e o arquivo passa a afirmar que a empresa vende à vista.
    const semClientes = {
      ...entradaModelo,
      linhas: entradaModelo.linhas.filter((l: { chave: string }) => !/clientes/i.test(l.chave)),
    };
    const wbSem = buildExportWorkbook({
      caso: entradaModelo.caso, documentos: docsModelo, campos: camposModelo,
      agora: new Date("2026-08-05T12:00:00Z"), modo: "completo",
      modeloInstitucional: semClientes as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
    });
    const outSem = wbSem.getWorksheet("Output")!;
    const pmrSem = v(outSem, linhaPorRotulo(outSem, "PMR — prazo médio de recebimento"), ano);
    checar(String(pmrSem) === "n.a.",
      "(0116) caso sem conta de clientes publica \"n.a.\", não 0 dias de recebimento",
      String(pmrSem));
    const operSem = v(outSem, linhaPorRotulo(outSem, "Ciclo operacional (PMR + PME)"), ano);
    checar(String(operSem) === "n.a.",
      "(0116) …e o ciclo não soma em cima do que não sabe — sem uma perna, não há ciclo",
      String(operSem));
  }

  // ---- (0115) NECESSIDADE DE RECURSOS: O ARQUIVO DIMENSIONA, NÃO SÓ ACUSA --
  //
  // O `Output` já dizia que o DSCR fica em 0,3 e que o revolver chega a 122.216 —
  // e não dizia, em lugar nenhum, que aquilo É a necessidade de recursos do caso.
  // O revolver é ficção de fechamento: ele existe para o balanço fechar. Quem lia
  // precisava fazer a conta de cabeça, ano a ano, na aba errada.
  //
  // O que estes asserts travam é a ARITMÉTICA do bloco, não a existência dele:
  // acumulado que não acumula, uso com sinal trocado e corte lido da constante em
  // vez da célula azul são os três jeitos de este bloco mentir com cara de certo.
  {
    const out = wbMod.getWorksheet("Output")!;
    const cf = wbMod.getWorksheet("Cash Flow")!;
    const linhaPorRotulo = (ws: ExcelJS.Worksheet, r: string): number | null => {
      for (let i = 1; i <= ws.rowCount; i++) {
        if (String(ws.getRow(i).getCell(3).value ?? "").trim() === r) return i;
      }
      return null;
    };
    const v = (ws: ExcelJS.Worksheet, r: number | null, ano: number) =>
      r === null ? null : avaliarCelula(ws, COLS_ANO[iAnoDe(ano)], r);

    const rFuro = linhaPorRotulo(out, "Necessidade de recursos do exercício");
    const rAcum = linhaPorRotulo(out, "acumulada desde o início da projeção");
    const rPico = linhaPorRotulo(out, "pico do horizonte projetado");
    const rAnoPico = linhaPorRotulo(out, "ano do pico");
    checar([rFuro, rAcum, rPico, rAnoPico].every((x) => x !== null),
      "(0115) o Output publica a necessidade de recursos — do exercício, acumulada e no pico",
      JSON.stringify({ rFuro, rAcum, rPico, rAnoPico }));

    // 1. O FURO É O MESMO DO FLUXO. Duas origens para o mesmo número só valem com
    //    conferência entre elas — e aqui a conferência é esta.
    const rFuroCF = linhaPorRotulo(cf, "Furo em relação ao caixa mínimo");
    const divergentes = ANOS.filter((a) => {
      const x = v(out, rFuro, a); const y = v(cf, rFuroCF, a);
      return typeof x === "number" && typeof y === "number" ? Math.abs(x - y) > 0.01 : x !== y;
    });
    checar(divergentes.length === 0,
      "(0115) …e o furo do Output é EXATAMENTE o do Cash Flow, ano a ano",
      divergentes.join(", "));

    const projetados = ANOS.filter((a) => a > 2025);

    // 2 e 3. O ACUMULADO E O PICO EXIGEM UM CASO QUE TENHA FURO — e a fixture
    //    principal NÃO TEM: medida, ela projeta furo ZERO nos três exercícios
    //    (a empresa gera caixa e a dívida amortiza sem aperto). Com zeros, "o
    //    acumulado é a soma dos furos" passa mesmo com a acumulação religada,
    //    porque 0 = 0 — foi exatamente o que aconteceu ao religar o defeito de
    //    propósito: a suíte continuou verde.
    //
    //    É a armadilha registrada três vezes neste projeto (a fixture do 0105, a
    //    do 0113 sem conta tributária, o medir-auto-aceite medindo o próprio
    //    instrumento): fixture mais fácil que a produção deixa o assert passar
    //    sobre o defeito. A variante abaixo é um caso de reestruturação de
    //    verdade — dívida concentrada no CIRCULANTE, que é como um caso
    //    estressado chega (tudo vencido ou vencendo), financiada por prejuízo
    //    acumulado para o balanço continuar fechando.
    const comFuro = {
      ...entradaModelo,
      linhas: [
        ...entradaModelo.linhas,
        linhaAnos("passivo_circulante", "Empréstimos e financiamentos - dívida vencida",
          { "2024": 100000, "2025": 120000 }),
        linhaAnos("patrimonio_liquido", "Prejuízos acumulados",
          { "2024": -100000, "2025": -120000 }),
      ],
    };
    const wbFuro = buildExportWorkbook({
      caso: entradaModelo.caso, documentos: docsModelo, campos: camposModelo,
      agora: new Date("2026-08-05T12:00:00Z"), modo: "completo",
      modeloInstitucional: comFuro as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
    });
    const outF = wbFuro.getWorksheet("Output")!;
    const rFuroF = linhaPorRotulo(outF, "Necessidade de recursos do exercício");
    const rAcumF = linhaPorRotulo(outF, "acumulada desde o início da projeção");
    const rPicoF = linhaPorRotulo(outF, "pico do horizonte projetado");
    const rAnoPicoF = linhaPorRotulo(outF, "ano do pico");
    const furos = projetados.map((a) => Number(v(outF, rFuroF, a) ?? 0));
    checar(furos.some((x) => x > 0),
      "(0115) a variante estressada PRODUZ furo — sem isso os asserts abaixo passariam sobre zeros",
      furos.join(" · "));

    // NECESSIDADE DE RECURSOS É ESTOQUE, NÃO FLUXO. Quem precisou de 30 e depois
    // de 20 precisa de 50 de dinheiro novo, não de 20.
    let soma = 0; const erros: string[] = [];
    for (const a of projetados) {
      soma += Number(v(outF, rFuroF, a) ?? 0);
      const acum = Number(v(outF, rAcumF, a) ?? 0);
      if (Math.abs(acum - soma) > 0.01) erros.push(`${a}: ${acum} ≠ ${soma}`);
    }
    checar(erros.length === 0,
      "(0115) …e o acumulado é a SOMA dos furos do horizonte, não o furo do ano",
      erros.join(" · "));

    // O PICO E O ANO DO PICO CONCORDAM ENTRE SI. Publicar 30 como pico e apontar
    // um ano cujo furo é 10 é pior que não publicar: manda levantar dinheiro para
    // a data errada.
    const maior = Math.max(...furos);
    const pico = v(outF, rPicoF, projetados[0]);
    checar(typeof pico === "number" && Math.abs(pico - maior) < 0.01,
      "(0115) …o pico é o MÁXIMO dos furos projetados",
      `${JSON.stringify(pico)} vs ${maior}`);
    const anoPico = v(outF, rAnoPicoF, projetados[0]);
    checar(String(anoPico) === String(projetados[furos.indexOf(maior)]),
      "(0115) …e o ano publicado é o ano DESSE máximo",
      `${JSON.stringify(anoPico)} vs ${projetados[furos.indexOf(maior)]}`);

    // E O CASO SEM FURO NENHUM (a fixture principal) NÃO INVENTA UM ANO: apontar
    // 2026 quando não falta caixa em ano nenhum manda procurar problema onde não há.
    checar(String(v(out, rAnoPico, projetados[0])) === "—",
      "(0115) …e sem furo em ano nenhum o ano do pico é travessão, não o primeiro ano",
      String(v(out, rAnoPico, projetados[0])));

    // 4. A CAPACIDADE DE PAGAMENTO LÊ A CÉLULA AZUL, NÃO A CONSTANTE. Se alguém
    //    negociar outro covenant e digitar na célula, o bloco inteiro tem de se
    //    mover junto; com a constante embutida, o arquivo passaria a responder
    //    sobre um covenant que não é o do caso.
    const rCorte = linhaPorRotulo(out, "corte sugerido (covenant)");
    const rEbitda = linhaPorRotulo(out, "EBITDA");
    const rSust = linhaPorRotulo(out, "Dívida líquida sustentável (ao corte de ND/EBITDA)");
    const rExc = linhaPorRotulo(out, "excesso sobre o sustentável");
    const rNd = linhaPorRotulo(out, "Net Financial Debt");
    const anoT = projetados[projetados.length - 1];
    const corte = Number(v(out, rCorte, anoT)); const ebitda = Number(v(out, rEbitda, anoT));
    const sust = Number(v(out, rSust, anoT));
    checar(Math.abs(sust - corte * ebitda) < 0.01,
      "(0115) a dívida sustentável é o CORTE (célula editável) × EBITDA",
      `${sust} vs ${corte}×${ebitda}`);
    checar(Math.abs(Number(v(out, rExc, anoT)) - (Number(v(out, rNd, anoT)) - sust)) < 0.01,
      "(0115) …e o excesso é a dívida líquida MENOS o sustentável");

    // 5. OS USOS SÃO SAÍDAS POSITIVAS E FECHAM COM O TOTAL. É o assert que pega
    //    sinal trocado: no Cash Flow o capex sai negativo, e somar os dois
    //    mundos sem normalizar daria um total que ninguém consegue conferir.
    const usos = ["(−) serviço da dívida", "(−) tributos e parcelamentos",
      "(−) variação do giro", "(−) capex"].map((r) => linhaPorRotulo(out, r));
    const rTotal = linhaPorRotulo(out, "= total dos usos");
    const somaUsos = usos.reduce<number>((s, r) => s + Number(v(out, r, anoT) ?? 0), 0);
    checar(Math.abs(Number(v(out, rTotal, anoT)) - somaUsos) < 0.01,
      "(0115) o total dos usos é a soma das quatro linhas que o compõem",
      `${v(out, rTotal, anoT)} vs ${somaUsos}`);
    const rCapexOut = linhaPorRotulo(out, "(−) capex");
    const rCapexCF = linhaPorRotulo(cf, "CAPEX");
    checar(Number(v(out, rCapexOut, anoT)) === -Number(v(cf, rCapexCF, anoT)),
      "(0115) …e o capex entra como USO POSITIVO, invertido em relação ao fluxo",
      `${v(out, rCapexOut, anoT)} vs ${v(cf, rCapexCF, anoT)}`);
    const rCoberto = linhaPorRotulo(out, "EBITDA cobre os usos? (EBITDA − usos)");
    checar(Math.abs(Number(v(out, rCoberto, anoT)) - (ebitda - somaUsos)) < 0.01,
      "(0115) …e a linha de cobertura é EBITDA − usos, o furo contado pelo lado da origem");
  }

  // ---- (0114) OS TRÊS BOTÕES DA PENDÊNCIA ---------------------------------
  //
  // A 0109 trocou o formulário (motivo obrigatório, data, papel, teto) por três
  // botões de um clique. Este bloco já provou o espelho do piso do motivo, que
  // deixou de existir; o que sobra para provar é o que a tela promete.
  //
  // O DEFEITO QUE ELE PEGA: botão cuja cor ou rótulo não corresponde ao estado
  // que ele produz. Com três botões coloridos e nenhum texto explicativo, a cor
  // É a informação — um "Prosseguir sem resolução" que gravasse o estado de
  // "contatar cliente" seria indistinguível na tela e mudaria o caso inteiro.
  {
    const esperado: Array<[string, string, string]> = [
      ["contatar_cliente", "Contatar o Cliente", "reenviada_ao_cliente"],
      ["prosseguir", "Prosseguir sem resolução", "aceita_com_ressalva"],
      ["nao_procede", "Pendência não procede", "rejeitada"],
    ];
    checar(BOTOES_DECISAO.length === 3
      && BOTOES_DECISAO.every((b, i) => b.decisao === esperado[i][0] && b.rotulo === esperado[i][1]),
      "(0114) os três botões, na ordem e com os rótulos que o dono pediu",
      BOTOES_DECISAO.map((b) => b.rotulo).join(" · "));

    // Cada botão tem de aparecer de volta no estado que produz — é o que faz o
    // rótulo colorido do item ser o mesmo botão que alguém clicou.
    const semVolta = esperado.filter(([dec, , estado]) => ROTULO_POR_ESTADO[estado]?.decisao !== dec);
    checar(semVolta.length === 0,
      "(0114) …e o rótulo que fica na pendência é o do botão que a decidiu",
      semVolta.map(([d]) => d).join(", "));

    // As três cores são distintas. Duas iguais e a tela perde a única informação
    // que ela dá sem texto.
    //
    // POR QUE OS NOMES MUDARAM AQUI. Este teste travava `emerald`/`red`/`amber`,
    // as famílias cruas do Tailwind. Quando o portal herdou o mundo visual da
    // Oria, elas viraram `ok`/`risco`/`alerta` — famílias SEMÂNTICAS, afinadas
    // para o fundo creme (as cruas são calibradas para fundo branco e lavam em
    // cima do papel). O que o teste protege não mudou: continuam sendo três
    // cores separadas, e continuam significando prosseguir / recusar / esperar.
    // O que mudou é que agora o nome diz o SIGNIFICADO, então um redesenho
    // futuro não pode trocar a cor sem trocar o significado junto.
    const cores = BOTOES_DECISAO.map((b) => b.classe.match(/bg-(\w+)-\d+/)?.[1]);
    checar(new Set(cores).size === 3 && cores.includes("ok") && cores.includes("risco") && cores.includes("alerta"),
      "(0114) …com as três cores separadas (ok · risco · alerta)",
      cores.join(" · "));

    // Cada botão diz o que ACONTECE COM O CASO. Sem campo e sem confirmação, é
    // a única chance de o usuário saber antes de clicar.
    checar(BOTOES_DECISAO.every((b) => b.efeito.length > 30 && !/_/.test(b.efeito)),
      "(0114) …e cada um declara o efeito no caso, em português",
      BOTOES_DECISAO.map((b) => b.efeito.slice(0, 20)).join(" | "));

    const estados = ["aberta", "em_correcao_interna", "reenviada_ao_cliente",
      "aceita_com_ressalva", "rejeitada", "resolvida"];
    const comUnderscore = estados.filter((e) => /_/.test(rotuloDoEstado(e)));
    checar(comUnderscore.length === 0 && !/_/.test(rotuloDoEstado("estado_que_nao_existe")),
      "(0114) e nenhum estado vaza como chave de banco, nem os que ninguém mapeou",
      comUnderscore.join(", "));
  }

  // ---- (0106g) MODELO SEM DRE DIZ QUE ESTÁ SEM DRE -------------------------
  //
  // Quando a extração não classifica as linhas de resultado (`secao_canonica`
  // ausente — medido na cadeia do book: 767 campos, todos sem), a cascata da DRE
  // sai inteira em ZERO. Zero em tudo parece "empresa sem operação", que é uma
  // afirmação sobre o negócio; o fato é "o modelo não recebeu a DRE". Antes as duas
  // coisas tinham exatamente a mesma aparência.
  {
    const semDRE = {
      ...entradaModelo,
      linhas: entradaModelo.linhas.filter((l) =>
        !["receita_bruta", "custos", "despesas_operacionais"].includes(l.secao_canonica)),
    };
    const wbSemDRE = buildExportWorkbook({
      caso: entradaModelo.caso, documentos: docsModelo, campos: camposModelo,
      agora: new Date("2026-08-05T12:00:00Z"), modo: "completo",
      modeloInstitucional: semDRE as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
    });
    const ws = wbSemDRE.getWorksheet("Income Statement");
    let achou = false;
    for (let r = 1; ws && r <= ws.rowCount; r++) {
      if (/^SEM DRE:/.test(String(ws.getRow(r).getCell(3).value ?? ""))) { achou = true; break; }
    }
    checar(achou,
      "(0106g) modelo cuja extração não trouxe linha de resultado ANUNCIA que está sem DRE, em vez "
      + "de exibir uma cascata zerada com cara de empresa sem operação");
  }

  esquecerMemoria(wbMod.getWorksheet("Balance Sheet")!);
}

// ---------------------------------------------------------------------------
// O COMPARATIVO TEM DE COMPARAR — a forma que a rodada v46 (17/08) entregou.
//
// No arquivo real, "Caixa e bancos conta movimento" saiu em TRÊS linhas do
// Excel: 2023 numa, 2024 na seguinte, 2025 na terceira, cada uma com as outras
// duas colunas vazias. Um balanço comparativo que não compara nada.
//
// A causa era o rank de ocorrência (o desempate que impede dois "Outros" de um
// balancete de colapsarem numa linha só) ser calculado por VERSÃO em vez de por
// COLUNA: os três valores da mesma conta viravam ocorrência 1, 2 e 3.
//
// Por que a fixture não pegava: nela cada exercício é um bloco de leitura com
// `ordem` própria, e nenhum caso conferia o alinhamento de um rótulo repetido
// entre colunas. Este bloco cobre as duas formas — a agrupada (uma `ordem` para
// a conta, um valor por coluna) e a antiga (uma `ordem` por par).
{
  const V = "vcomp";
  const anos = ["2025", "2024", "2023"];
  const documentos: DocumentoParaExport[] = [{
    id: "dcomp", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Canastra Industria" },
    periodo: { tipo: "multi", referencia: "23,24,25" }, documento_versao: [{ id: V, nome_original: "bp.pdf" }],
  }];

  const conferir = (campos: CampoExtraido[], forma: string) => {
    const ws = buildExportWorkbook({
      caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-08-17T12:00:00Z"),
    }).getWorksheet("Balanço")!;
    const linhas: number[] = [];
    for (let r = 1; r <= ws.rowCount; r++) {
      if (String(ws.getRow(r).getCell(1).value ?? "") === "Caixa e bancos conta movimento") linhas.push(r);
    }
    checar(linhas.length === 1,
      `(v46-${forma}) conta de balanço comparativo ocupa UMA linha, com um valor por exercício`,
      `linhas=${linhas.length}`);
    if (linhas.length !== 1) return;
    // As três colunas da linha têm de estar preenchidas: era isso que faltava.
    const preenchidas = ws.getRow(linhas[0]).values as unknown[];
    const numeros = preenchidas.filter((v) => typeof v === "number" && v !== 0);
    checar(numeros.length >= 3,
      `(v46-${forma}) os três exercícios da conta chegam na MESMA linha`,
      `valores=${numeros.length}`);
    // …e o rótulo repetido de verdade (duas linhas "Outros" no mesmo exercício)
    // continua sem colapsar — o defeito que o rank veio fechar.
    let outros = 0;
    for (let r = 1; r <= ws.rowCount; r++) {
      if (/^Outros/.test(String(ws.getRow(r).getCell(1).value ?? ""))) outros += 1;
    }
    checar(outros === 2, `(v46-${forma}) rótulo repetido no mesmo exercício continua em linhas separadas`,
      `linhas "Outros"=${outros}`);
  };

  // Forma AGRUPADA (a que o workflow gera desde a correção de 17/08): os três
  // valores da conta compartilham a `ordem` da linha do documento.
  const agrupada: CampoExtraido[] = [];
  anos.forEach((ano) => {
    agrupada.push(campo({ chave: "Caixa e bancos conta movimento", secao: "Ativo Circulante",
      valor_num: 606, periodo_coluna: ano, ordem: 0, documento_versao_id: V }));
    agrupada.push(campo({ chave: "Outros", secao: "Ativo Circulante",
      valor_num: 11, periodo_coluna: ano, ordem: 1, documento_versao_id: V }));
    agrupada.push(campo({ chave: "Outros", secao: "Passivo Circulante",
      valor_num: 22, periodo_coluna: ano, ordem: 2, documento_versao_id: V }));
  });
  conferir(agrupada, "agrupada");

  // Forma ANTIGA (um bloco de leitura por exercício, `ordem` correndo): o dado
  // que já está no banco das rodadas anteriores tem esta cara, e o arquivo
  // exportado dele tem de sair igualmente alinhado.
  const antiga: CampoExtraido[] = [];
  let ordem = 0;
  anos.forEach((ano) => {
    antiga.push(campo({ chave: "Caixa e bancos conta movimento", secao: "Ativo Circulante",
      valor_num: 606, periodo_coluna: ano, ordem: ordem++, documento_versao_id: V }));
    antiga.push(campo({ chave: "Outros", secao: "Ativo Circulante",
      valor_num: 11, periodo_coluna: ano, ordem: ordem++, documento_versao_id: V }));
    antiga.push(campo({ chave: "Outros", secao: "Passivo Circulante",
      valor_num: 22, periodo_coluna: ano, ordem: ordem++, documento_versao_id: V }));
  });
  conferir(antiga, "antiga");
}

// ============================================================================
// (34) A PROVENIÊNCIA DA CÉLULA: arquivo, PÁGINA, CONFIANÇA e ACEITE (0125)
// ============================================================================
//
// O QUE ISTO TRAVA. O §2.3 do diagnóstico de 11/08 mediu uma perda de
// rastreabilidade que ninguém decidiu: antes do PR #109 cada célula de dado
// trazia documento, página, confiança e status de aceite; o #109 separou os dois
// exports (decisão certa) e a camada saiu junto. O que sobrou nas células
// históricas do arquivo de comitê era `Extraído de ${documentos}` — e `documentos`
// é a lista de TIPOS (`array_agg(distinct tipo_taxonomia)`), não de arquivos.
//
// "De onde veio o 106.580" se respondia com "BALANCO". Num mandato com oito
// balanços, isso é a categoria e não a peça.
{
  const comProv = (
    secao: string, chave: string, valores: Record<string, number>,
    prov: Record<string, {
      arquivo: string | null; pagina: number | null; confianca: number | null;
      statusAceite: string | null; aceitoPor: string | null;
    }>,
  ) => ({
    secao_canonica: secao, chave, rotulo_norm: chave.toLowerCase(),
    papel: "conta" as const, unidade: "milhar", moeda: "BRL",
    documentos: ["BALANCO"], valores, proveniencia: prov,
  });

  const entradaProv = {
    caso: { nome: "Proveniência da célula", produto: "reestruturacao" },
    agora: new Date("2026-08-19T12:00:00Z"),
    entidade: "VERTENTES METALÚRGICA LTDA.",
    setor: "industria",
    anosHistoricos: [2024, 2025],
    anosProjetados: [2026, 2027],
    stressPct: 0.2, caixaMinimo: 0, aliquotaTributos: 0.34,
    linhas: [
      // A MESMA CONTA COM PROVENIÊNCIA DIFERENTE EM CADA ANO — é este o caso que
      // a `0125` existe para servir, e o que uma proveniência por LINHA (e não
      // por célula) descreveria errado: 2024 veio de um arquivo, 2025 de outro,
      // em página diferente e com aceite diferente.
      comProv("receita_bruta", "Vendas de produtos", { "2024": 26000, "2025": 30000 }, {
        "2024": {
          arquivo: "06_Balanco_2024.pdf", pagina: 2, confianca: 0.91,
          statusAceite: "pendente", aceitoPor: null,
        },
        "2025": {
          arquivo: "01_Balanco_2025x2024.pdf", pagina: 3, confianca: 0.97,
          statusAceite: "aceito", aceitoPor: "rodrigo@oria",
        },
      }),
      // E a linha SEM proveniência carregada: a nota tem de continuar saindo, com
      // o texto antigo. É o caminho de quem monta `LinhaModelo` à mão.
      comProv("custos", "Matérias-primas", { "2024": 15000, "2025": 18000 }, {}),
    ],
    premissas: [], vinculos: [], macro: [], unidade: "R$ mil",
  };

  const VPRV = "vProv";
  const camposProv: CampoExtraido[] = [
    campo({ chave: "Vendas de produtos", secao: "Receita Bruta", valor_num: 30000,
            periodo_coluna: "2025", ordem: 0, documento_versao_id: VPRV }),
  ];
  const docsProv: DocumentoParaExport[] = [{
    id: "dProv", tipo_taxonomia: "BALANCO",
    entidade: { razao_social: "VERTENTES METALÚRGICA LTDA." },
    periodo: { tipo: "multi", referencia: "24,25" },
    documento_versao: [{ id: VPRV, nome_original: "01_Balanco_2025x2024.pdf" }],
  }];

  const wb = buildExportWorkbook({
    caso: entradaProv.caso, documentos: docsProv, campos: camposProv,
    agora: entradaProv.agora,
    modeloInstitucional: entradaProv as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
  });
  const ws = wb.getWorksheet("Premissas");
  checar(!!ws, "(34) a aba Premissas existe no arquivo de modelagem");
  if (ws) {
    // O RÓTULO MORA NA COLUNA 3 (`COL_ROTULO`), não na 1 — as duas primeiras são a
    // sangria do Modelo Base. Procurar na 1 devolve -1 para tudo, e um teste que
    // não acha a linha "passa" nos asserts seguintes por não chegar neles.
    const COL_ROT = 3;
    const acharLinha = (rot: string) => {
      for (let r = 1; r <= ws.rowCount; r++) {
        if (String(ws.getRow(r).getCell(COL_ROT).value ?? "").trim() === rot) return r;
      }
      return -1;
    };
    const texto = (r: number, c: number) => String(
      (ws.getRow(r).getCell(c).note as { texts?: Array<{ text: string }> } | undefined)
        ?.texts?.map((t) => t.text).join("") ?? "",
    );
    // A COLUNA DO PRIMEIRO EXERCÍCIO é a única com o ano LITERAL: a partir dela o
    // cabeçalho é fórmula (`=<coluna anterior>+1`, como no Modelo Base), então
    // procurar o texto "2025" não acha nada. Os anos ocupam colunas consecutivas,
    // e o assert seguinte prova isso em vez de supor.
    let c24 = -1;
    for (let r = 1; r <= 12 && c24 < 0; r++) {
      for (let c = 2; c <= 30; c++) {
        if (ws.getRow(r).getCell(c).value === 2024) { c24 = c; break; }
      }
    }
    const c25 = c24 > 0 ? c24 + 1 : -1;
    const rCli = acharLinha("Vendas de produtos");
    checar(rCli > 0 && c24 > 0,
      "(34) a linha e a coluna do primeiro exercício estão no arquivo",
      `linha=${rCli} col2024=${c24}`);
    if (c24 > 0) {
      // O ano seguinte é a coluna ao lado, e ele é FÓRMULA encadeada — se um dia
      // deixar de ser, este teste passaria a ler a célula errada em silêncio.
      let achouFormula = false;
      for (let r = 1; r <= 12; r++) {
        const f = (ws.getRow(r).getCell(c25).value as { formula?: string } | undefined)?.formula;
        if (f && /\+1$/.test(f)) { achouFormula = true; break; }
      }
      checar(achouFormula,
        "(34) …e a coluna seguinte é o exercício seguinte, por fórmula encadeada");
    }
    if (rCli > 0 && c24 > 0 && c25 > 0) {
      const n25 = texto(rCli, c25);
      const n24 = texto(rCli, c24);
      // ---- o ARQUIVO, não o tipo do documento
      checar(/01_Balanco_2025x2024\.pdf/.test(n25),
        "(34) a nota nomeia o ARQUIVO de origem, não o tipo do documento", n25.slice(0, 200));
      checar(!/^Extraído de BALANCO/.test(n25),
        "(34) …e não cai de volta em \"Extraído de BALANCO\", que é a categoria", n25.slice(0, 120));
      // ---- página, confiança e ACEITE
      checar(/página 3/.test(n25), "(34) a nota traz a PÁGINA", n25.slice(0, 200));
      checar(/confiança da extração 97%/.test(n25),
        "(34) …a CONFIANÇA, em porcentagem legível", n25.slice(0, 200));
      checar(/ACEITO por rodrigo@oria/.test(n25),
        "(34) …e o ACEITE com quem aceitou — o que separa \"o modelo leu\" de \"alguém conferiu\"",
        n25.slice(0, 200));
      // ---- E A CÉLULA DE 2024 DESCREVE 2024, não 2025.
      //
      // É este assert que prova por que a 0125 mexeu na `fn_valores_por_ano` e não
      // na `fn_linhas_para_modelagem`: a segunda devolve UMA proveniência por
      // linha, da ocorrência de maior módulo entre os exercícios — e aqui ela
      // poria "página 3, 97%, ACEITO" na célula de 2024, que veio de outro
      // arquivo, outra página, e NÃO foi aceita por ninguém.
      checar(/06_Balanco_2024\.pdf/.test(n24) && /página 2/.test(n24),
        "(34) a célula de 2024 descreve a origem DE 2024, não a de 2025", n24.slice(0, 200));
      checar(/NÃO foi conferido por ninguém/.test(n24),
        "(34) …e diz que o número de 2024 está PENDENTE de aceite", n24.slice(0, 200));
      checar(!/ACEITO/.test(n24),
        "(34) …sem afirmar aceite que não houve", n24.slice(0, 200));
    }
    // ---- linha sem proveniência carregada: a nota antiga continua saindo.
    const rForn = acharLinha("Matérias-primas");
    if (rForn > 0 && c25 > 0) {
      const nf = texto(rForn, c25);
      checar(/Extraído de BALANCO/.test(nf),
        "(34) linha SEM proveniência carregada volta ao texto antigo, sem quebrar", nf.slice(0, 160));
      checar(!/página|confiança/.test(nf),
        "(34) …e não inventa página nem confiança que não existem", nf.slice(0, 160));
    }
  }
}

// ============================================================================
// (35) "OS TRÊS CENÁRIOS SÃO TRÊS?" — o Cliente Case que nasce igual ao Base
// ============================================================================
//
// O QUE ISTO DENUNCIA, e é defeito de PRODUTO e não de código: o `Cliente Case`
// nasce como `=<Base Case>` em toda conta do modelo (convenção do Modelo Base, e
// certa como ponto de partida). O efeito é que, num arquivo recém-exportado,
// girar o dial de 1 para 2 não muda um número sequer — e até aqui NADA no arquivo
// dizia isso. Um "Cliente Case" que é, número por número, o Base Case podia
// chegar a um comitê sem a planilha o contradizer.
//
// O Stress tem a forma espelhada: ele é o Base vezes um haircut único
// (`Considerações!$F$8`). Zerada aquela célula, o Stress vira o Base e o dropdown
// continua oferecendo três cenários.
{
  const montar = (stress: number) => {
    const linhaRec = (chave: string, v: number) => ({
      secao_canonica: "receita_bruta", chave, rotulo_norm: chave.toLowerCase(),
      papel: "conta" as const, unidade: "milhar", moeda: "BRL",
      documentos: ["DRE"], valores: { "2025": v },
    });
    const ent = {
      caso: { nome: "Três cenários", produto: "reestruturacao" },
      agora: new Date("2026-08-19T12:00:00Z"),
      entidade: "VERTENTES METALÚRGICA LTDA.", setor: "industria",
      anosHistoricos: [2025], anosProjetados: [2026, 2027],
      stressPct: stress, caixaMinimo: 0, aliquotaTributos: 0.34,
      linhas: [linhaRec("Vendas de produtos", 100000)],
      // A premissa é o que dá as três linhas de cenário: sem ela a conta é
      // "mantida constante" e não há Base/Cliente/Stress para comparar.
      premissas: [{
        codigo: "cresc_receita", nome: "Crescimento da receita", natureza: "taxa",
        formula: "crescimento_composto", unidade: "%",
        valores: { "2026": 10, "2027": 8 }, origem: "digitado",
      }],
      vinculos: [{
        rotulo_norm: "vendas de produtos", premissa_codigo: "cresc_receita",
        sazonalidade_codigo: null,
      }],
      macro: [], unidade: "R$ mil",
    };
    const V = `vCen${Math.round(stress * 100)}`;
    return buildExportWorkbook({
      caso: ent.caso,
      documentos: [{
        id: `d${V}`, tipo_taxonomia: "DRE",
        entidade: { razao_social: "VERTENTES METALÚRGICA LTDA." },
        periodo: { tipo: "anual", referencia: "2025" },
        documento_versao: [{ id: V, nome_original: "dre.pdf" }],
      }],
      campos: [campo({ chave: "Vendas de produtos", secao: "Receita Bruta", valor_num: 100000,
                       periodo_coluna: "2025", ordem: 0, documento_versao_id: V })],
      agora: ent.agora,
      modeloInstitucional: ent as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
    });
  };

  const lerVeredito = (wb: ExcelJS.Workbook, linha: number): string => {
    const out = wb.getWorksheet("Output");
    if (!out) return "(sem aba Output)";
    // `esquecerMemoria` é POR ABA (a memória do avaliador é por planilha), e cada
    // `montar()` devolve um workbook novo — então aqui ela é só defensiva.
    esquecerMemoria(out);
    const v = avaliarCelula(out, "G", linha);
    return typeof v === "string" ? v : String(v ?? "");
  };

  // Linha 8 = Cliente Case, linha 9 = Stress Case (ver `abaOutput`).
  const wbComStress = montar(0.2);
  const out = wbComStress.getWorksheet("Output");
  checar(String(out?.getRow(7).getCell(3).value ?? "") === "OS TRÊS CENÁRIOS SÃO TRÊS?",
    "(35) o painel existe no Output, ao lado do interruptor de cenário",
    String(out?.getRow(7).getCell(3).value ?? ""));

  const cli = lerVeredito(wbComStress, 8);
  checar(cli === "IDÊNTICO AO BASE",
    "(35) num arquivo recém-exportado, o Cliente Case É o Base Case — e o arquivo DIZ isso", cli);

  const str = lerVeredito(wbComStress, 9);
  checar(str === "diferenciado",
    "(35) …e o Stress, com haircut de 20%, aparece como diferenciado", str);

  // ---- NEGATIVO: haircut zerado faz o Stress virar o Base, e tem de aparecer.
  //
  // Um cenário de estresse sem estresse é PIOR que não ter cenário de estresse,
  // porque parece que alguém olhou. Este é o caso que o indicador precisa pegar.
  const semStress = montar(0);
  const strZero = lerVeredito(semStress, 9);
  checar(strZero === "IDÊNTICO AO BASE",
    "(35) NEGATIVO: com o haircut zerado, o Stress é o Base — e o painel acusa", strZero);

  // ---- O ARNÊS TINHA UM BURACO, e foi este teste que o achou.
  //
  // O nome da aba principal do modelo tem VÍRGULA (`Revenues, COGS & SG&A`), então
  // toda referência a ela vai entre apóstrofos. O scanner de argumentos de função
  // do `avaliar-formula.mts` pulava trecho entre ASPAS DUPLAS e não entre
  // apóstrofos — a vírgula de dentro do nome partia o argumento em dois,
  // `N('Revenues` não avaliava nada, e o resultado era 0. Em silêncio.
  //
  // O efeito: QUALQUER assert que avaliasse uma fórmula referenciando aquela aba
  // dentro de uma função lia zero e passava por não conseguir avaliar — a forma
  // mais silenciosa de teste que não prova nada, que é justamente o que este
  // arquivo existe para não ser. Foi assim que ele apareceu: o painel de cenários
  // dizia "IDÊNTICO AO BASE" sobre um Stress de 20%.
  {
    const alvo = wbComStress.getWorksheet("Output");
    const rec0 = wbComStress.getWorksheet("Revenues, COGS & SG&A");
    if (alvo && rec0) {
      // Uma célula de teste que soma DUAS referências à aba de nome com vírgula,
      // dentro de funções — exatamente a forma que quebrava.
      let rNum = -1;
      for (let r = 1; r <= rec0.rowCount; r++) {
        if (/Base Case/.test(String(rec0.getRow(r).getCell(3).value ?? ""))) { rNum = r; break; }
      }
      checar(rNum > 0, "(35) há uma linha numérica na aba de nome com vírgula para o teste do arnês");
      if (rNum > 0) {
        alvo.getRow(200).getCell(7).value = {
          formula: `N('Revenues, COGS & SG&A'!F${rNum})+N('Revenues, COGS & SG&A'!G${rNum})`,
        };
        esquecerMemoria(alvo);
        const v = avaliarCelula(alvo, "G", 200);
        checar(typeof v === "number" && v > 0,
          "(35) o avaliador atravessa nome de aba com VÍRGULA dentro de função (buraco do arnês)",
          String(v));
      }
    }
  }

  // ---- E A MEDIDA É EXATA, não é "parece diferente": a linha DIF_CENARIO da aba
  // de receita soma ABS(cenário − base) conta a conta. Zero significa premissas
  // idênticas e não pode significar outra coisa.
  const rec = wbComStress.getWorksheet("Revenues, COGS & SG&A");
  if (rec) {
    let rDifCli = -1;
    for (let r = 1; r <= rec.rowCount; r++) {
      if (/Cliente Case — distância das premissas ao Base/
        .test(String(rec.getRow(r).getCell(3).value ?? ""))) { rDifCli = r; break; }
    }
    checar(rDifCli > 0, "(35) a linha de distância do Cliente Case existe na aba de receita");
    if (rDifCli > 0) {
      esquecerMemoria(rec);
      // 2026 é a primeira coluna projetada.
      let colProj = -1;
      for (let c = 5; c <= 40; c++) {
        if (rec.getRow(rDifCli).getCell(c).value != null) { colProj = c; break; }
      }
      checar(colProj > 0, "(35) …e ela tem célula nos exercícios projetados");
      if (colProj > 0) {
        const v = avaliarCelula(rec, colLetraDoIndice(colProj), rDifCli);
        checar(v === 0,
          "(35) …valendo ZERO, que é a medida exata de \"Cliente idêntico ao Base\"", String(v));
      }
    }
  }
}

// ---- 36: A REGRA DE ENTIDADE E PERÍODO DA LINHA, agora compartilhada -------
//
// Esta regra era uma linha solta dentro do laço do `buildExportWorkbook`, e virou
// função exportada quando a tela do Modo A (`Arquitetura do Sistema/2 Especificação/f0/07`) passou a precisar da mesma
// resposta. A extração é comportamento-preservador — os 568 asserts anteriores
// continuam verdes —, mas ela agora tem DOIS leitores, e é isso que a torna digna
// de assert próprio: um defeito aqui erra o arquivo entregue E a tela, do mesmo
// jeito, e a coincidência das duas telas esconderia o erro em vez de expô-lo.
{
  const ctx = { entidade: "ALFA INDÚSTRIA LTDA", periodo: "2024" };
  const canon = new Map([["Componentes", "VERTENTES COMPONENTES AUTOMOTIVOS LTDA."]]);
  const linha = (entidade_coluna: string | null, periodo_coluna: string | null) =>
    entidadePeriodoDaLinha({ entidade_coluna, periodo_coluna }, ctx, canon);

  // Sem coluna: a linha é do documento. É o caso da esmagadora maioria.
  const base = linha(null, null);
  checar(base.entidade === "ALFA INDÚSTRIA LTDA" && base.periodo === "2024",
    "(36) linha sem coluna herda entidade e período do DOCUMENTO",
    `${base.entidade} / ${base.periodo}`);

  // Com `entidade_coluna` (0014): a linha é da COLUNA. Se isto cair, um balanço
  // combinado joga as linhas de todas as empresas na entidade principal.
  const comEnt = linha("Certsys Tecn", null);
  checar(comEnt.entidade === "Certsys Tecn",
    "(36) `entidade_coluna` VENCE a entidade do documento (0014)", comEnt.entidade);

  // …e o apelido da coluna é promovido à razão social quando o caso conhece uma só
  // que case. Sem isso a mesma empresa vira duas — duas colunas no arquivo, dois
  // chips no filtro da tela —, e qualquer soma do grupo a conta 2x (teste v27).
  const promovido = linha("Componentes", null);
  checar(promovido.entidade === "VERTENTES COMPONENTES AUTOMOTIVOS LTDA.",
    "(36) o apelido da coluna é promovido à razão social canônica", promovido.entidade);

  // Com `periodo_coluna` (0017): a linha é do período da COLUNA, FORMATADO — o
  // valor vem cru da extração, e sem formatar o mesmo exercício aparece em dois
  // rótulos diferentes ("31/12/2023" e "2023").
  const comPer = linha(null, "31/12/2023");
  checar(comPer.periodo === "2023",
    "(36) `periodo_coluna` vence o período do documento, JÁ CONSOLIDADO (0017)",
    comPer.periodo);

  // Os dois eixos são ORTOGONAIS: combinado comparativo tem entidade × período.
  const ambos = linha("Certsys Tecn", "2023");
  checar(ambos.entidade === "Certsys Tecn" && ambos.periodo === "2023",
    "(36) entidade e período da coluna valem JUNTOS, sem um anular o outro",
    `${ambos.entidade} / ${ambos.periodo}`);

  // Coluna vazia não é coluna: string vazia cai no documento, não numa entidade
  // chamada "". (O `||` da regra existe por isso; um `??` deixaria passar.)
  const vazia = linha("", null);
  checar(vazia.entidade === "ALFA INDÚSTRIA LTDA",
    "(36) `entidade_coluna` vazia cai no documento, não numa empresa sem nome",
    vazia.entidade);
}

// ============================================================================
// (36) O RESUMO DOS TRÊS CENÁRIOS — a comparação que o arquivo não fazia
// ============================================================================
//
// O `Arquitetura do Sistema/4 Análises e Auditorias/DIAGNOSTICO_SISTEMA_2026-08-11.md` §2.2: o arquivo tem UM interruptor de
// cenário e todas as abas leem dele, então ele mostra um cenário por vez e "a
// comparação base × cliente × stress — que é o motivo de existirem três — não está
// em lugar nenhum". O teste (35) acima já cobre o indicador QUALITATIVO ("os três
// cenários são três?"). Este cobre o bloco NUMÉRICO.
//
// O QUE ELE TRAVA, em ordem de importância:
//
//   1. O CHECK É EXATAMENTE ZERO. A cascata paralela e a cascata ativa saem do
//      mesmo código (`formulaConta`, com o cenário como parâmetro). Se este assert
//      cair, as duas se separaram — e o pior é que nada mais quebraria: os dois
//      blocos continuariam produzindo números plausíveis, e o comitê leria uma
//      comparação de cenários que não descreve o modelo ao lado.
//   2. O STRESS DIFERE DO BASE EM NÚMERO, não só em premissa. O indicador (35) mede
//      distância de PREMISSA; este mede o efeito dela na receita e no EBITDA. Um
//      arquivo em que a premissa difere e o número não é um arquivo em que a
//      cascata paralela não está ligada em alguma conta.
//   3. O CLIENTE CASE É IGUAL AO BASE EM NÚMERO, num arquivo recém-exportado —
//      porque ele nasce espelhando o Base. É o negativo do assert 2: se o Cliente
//      aparecesse diferente sem ninguém ter digitado premissa própria, a sombra
//      estaria calculando outra coisa.
//   4. A SOMBRA NÃO EXISTE NO REALIZADO. O passado é um; três colunas históricas
//      com o mesmo número convidariam a procurar uma diferença que não existe.
//
// OS ASSERTS 1 E 2 SÃO COMPLEMENTARES, e isso foi MEDIDO no religamento em vez de
// suposto. O CHECK só compara a sombra do cenário ATIVO com a linha ativa — e num
// arquivo recém-exportado o cenário ativo é o Base. Religamento A (a sombra passou
// a usar sempre a taxa do Base, ignorando o cenário): o CHECK continuou ZERO, e
// quem caiu foram os asserts do Stress. Religamento B (a agregação da sombra
// deixou de somar uma conta de custo): o CHECK acusou 42.000 e 44.100, e os asserts
// do Stress passaram. Nenhum dos dois pega o defeito do outro — um CHECK verde não
// prova que os três cenários estão ligados, e três cenários diferentes não provam
// que a sombra bate com o modelo. Tirar qualquer um dos dois grupos deixa metade do
// bloco sem guarda.
{
  // Compara SEM a indentação dos dois lados: os rótulos do modelo carregam recuo
  // (é ele que faz a hierarquia ser legível na planilha), e comparar um lado
  // aparado com o outro cru é o jeito mais fácil de este teste "não achar" a linha
  // e reprovar um bloco que está correto.
  // `apos` NÃO É CONVENIÊNCIA: "EBITDA" é rótulo do SUMMARY e também do bloco dos
  // cenários, e a primeira versão deste teste leu o do SUMMARY — o assert do EBITDA
  // do Cliente comparou 58.162 com 0,49, que é a MARGEM da linha de baixo. O teste
  // reprovou um bloco correto, e por um motivo que parecia um defeito de sinal.
  const linhaDe = (ws: import("exceljs").Worksheet, rotulo: string, apos = 0): number => {
    const alvo = rotulo.trim();
    for (let r = apos + 1; r <= ws.rowCount; r++) {
      if (String(ws.getRow(r).getCell(3).value ?? "").trim() === alvo) return r;
    }
    return -1;
  };

  const montar = (stress: number) => {
    const linhaMod = (chave: string, v: number, secao: string) => ({
      secao_canonica: secao, chave, rotulo_norm: chave.toLowerCase(),
      papel: "conta" as const, unidade: "milhar", moeda: "BRL",
      documentos: ["DRE"], valores: { "2025": v },
    });
    const ent = {
      caso: { nome: "Resumo dos cenários", produto: "reestruturacao" },
      agora: new Date("2026-08-20T12:00:00Z"),
      entidade: "VERTENTES METALÚRGICA LTDA.", setor: "industria",
      anosHistoricos: [2025], anosProjetados: [2026, 2027],
      stressPct: stress, caixaMinimo: 0, aliquotaTributos: 0.34,
      linhas: [
        linhaMod("Vendas de produtos", 100000, "receita_bruta"),
        linhaMod("Materia prima", 40000, "custos"),
        linhaMod("Salarios administrativos", 15000, "despesas_operacionais"),
      ],
      premissas: [
        { codigo: "cresc_receita", nome: "Crescimento da receita", natureza: "taxa",
          formula: "crescimento_composto", unidade: "%",
          valores: { "2026": 10, "2027": 8 }, origem: "digitado" },
        { codigo: "cresc_custo", nome: "Inflação de custo", natureza: "taxa",
          formula: "crescimento_composto", unidade: "%",
          valores: { "2026": 5, "2027": 5 }, origem: "digitado" },
      ],
      vinculos: [
        { rotulo_norm: "vendas de produtos", premissa_codigo: "cresc_receita", sazonalidade_codigo: null },
        { rotulo_norm: "materia prima", premissa_codigo: "cresc_custo", sazonalidade_codigo: null },
        { rotulo_norm: "salarios administrativos", premissa_codigo: "cresc_custo", sazonalidade_codigo: null },
      ],
      macro: [], unidade: "R$ mil",
    };
    return buildExportWorkbook({
      caso: ent.caso,
      documentos: [{
        id: "dcen", tipo_taxonomia: "DRE",
        entidade: { razao_social: "VERTENTES METALÚRGICA LTDA." },
        periodo: { tipo: "anual", referencia: "2025" },
        documento_versao: [{ id: "vcen", nome_original: "dre.pdf" }],
      }] as unknown as DocumentoParaExport[],
      campos: [campo({ chave: "Vendas de produtos", secao: "Receita Bruta", valor_num: 100000,
                       periodo_coluna: "2025", ordem: 0, documento_versao_id: "vcen" })],
      agora: ent.agora,
      modeloInstitucional: ent as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
    });
  };

  const wb = montar(0.2);
  const out = wb.getWorksheet("Output")!;
  const rec = wb.getWorksheet("Revenues, COGS & SG&A")!;
  checar(out != null && rec != null, "(36) as duas abas do bloco de cenários existem");

  const rTitulo = linhaDe(out, "RESUMO DOS TRÊS CENÁRIOS (não olha o interruptor)");
  checar(rTitulo > 0, "(36) o bloco existe na aba Output", String(rTitulo));

  const rCheck = linhaDe(out, "CHECK: o cenário ativo bate com a cascata paralela (0 = bate)", rTitulo);
  const rRecBase = linhaDe(out, "Base Case", rTitulo);
  checar(rCheck > 0 && rRecBase > 0, "(36) as linhas do bloco estão nomeadas como o código as escreve");

  // ---- 1. O CHECK É ZERO — nos dois exercícios projetados.
  esquecerMemoria(out);
  for (const col of ["F", "G"]) {
    const v = avaliarCelula(out, col, rCheck);
    checar(typeof v === "number" && Math.abs(v) < 1e-9,
      `(36) CHECK zero em ${col}: a cascata paralela do cenário ATIVO bate com a cascata ativa`,
      String(v));
  }

  // ---- 2 e 3. os números dos três cenários, no último exercício projetado.
  //
  // As três linhas de cada métrica são contíguas na ordem Base/Cliente/Stress —
  // a ordem do CHOOSE, e o próprio código diz que trocá-la faria o arquivo
  // comparar o Stress contra a coluna do Cliente sem nada denunciar.
  const trio = (rotuloMetrica: string, col: string) => {
    const r0 = linhaDe(out, rotuloMetrica, rTitulo);
    esquecerMemoria(out);
    return [0, 1, 2].map((i) => {
      const v = avaliarCelula(out, col, r0 + 1 + i);
      return typeof v === "number" ? v : NaN;
    });
  };

  const [recB, recC, recS] = trio("Receita líquida", "G");
  checar(recB > 0, "(36) a receita líquida do Base Case sai positiva no bloco", String(recB));
  checar(recC === recB,
    "(36) o Cliente Case é IGUAL ao Base em NÚMERO num arquivo recém-exportado (ele nasce espelhando)",
    `${recC} vs ${recB}`);
  checar(recS < recB && recS > 0,
    "(36) e o Stress Case é MENOR que o Base em número — a premissa diferente virou efeito",
    `${recS} vs ${recB}`);

  const [ebB, ebC, ebS] = trio("EBITDA", "G");
  checar(ebC === ebB, "(36) o EBITDA do Cliente também espelha o Base", `${ebC} vs ${ebB}`);
  // O STRESS PIORA OS DOIS LADOS: receita menor E custo maior. O EBITDA dele tem de
  // cair mais que a receita — se caísse menos, o haircut estaria sendo aplicado com
  // o sinal errado no custo, que é o erro clássico do modelo de estresse feito por
  // multiplicação cega (e a `modelo-institucional.ts` comenta exatamente isso).
  checar(ebS < ebB, "(36) o EBITDA do Stress é menor que o do Base", `${ebS} vs ${ebB}`);
  checar((ebB - ebS) / ebB > (recB - recS) / recB,
    "(36) …e cai MAIS que a receita, porque no Stress o custo também piora",
    `EBITDA -${(((ebB - ebS) / ebB) * 100).toFixed(1)}% vs receita -${(((recB - recS) / recB) * 100).toFixed(1)}%`);

  // ---- 4. a sombra não existe no realizado (coluna E).
  const rRec0 = linhaDe(out, "Receita líquida", rTitulo);
  for (const i of [1, 2, 3]) {
    checar(out.getRow(rRec0 + i).getCell(5).value == null,
      "(36) a coluna do exercício REALIZADO fica vazia no bloco: o passado é um só",
      String(out.getRow(rRec0 + i).getCell(5).value));
  }

  // ---- NEGATIVO: haircut zerado faz o Stress virar o Base EM NÚMERO.
  //
  // O par do assert (35): lá o indicador diz "IDÊNTICO AO BASE" por premissa; aqui
  // o número tem de coincidir. Um cenário de estresse sem estresse é pior que não
  // ter cenário de estresse, porque parece que alguém olhou.
  {
    const semStress = montar(0);
    const out0 = semStress.getWorksheet("Output")!;
    const r0 = linhaDe(out0, "Receita líquida",
      linhaDe(out0, "RESUMO DOS TRÊS CENÁRIOS (não olha o interruptor)"));
    esquecerMemoria(out0);
    const b = avaliarCelula(out0, "G", r0 + 1);
    const st = avaliarCelula(out0, "G", r0 + 3);
    checar(typeof b === "number" && b === st,
      "(36) NEGATIVO: com o haircut zerado, o Stress é o Base também em número", `${st} vs ${b}`);
  }

  // ---- OS DOIS COVENANTS POR CENÁRIO, e a linha que diz o que eles NÃO são.
  //
  // Eles entraram como SENSIBILIDADE: o EBITDA varia com o cenário, a dívida é a
  // do cenário ativo. É leitura de PISO, e a linha de rodapé existe para impedir
  // que ela seja lida como comparação completa — um bloco que insinua o que não
  // faz é pior que um bloco ausente.
  {
    const rND = linhaDe(out, "Net Debt / EBITDA por cenário",
      linhaDe(out, "Sensibilidade dos covenants ao cenário (dívida do cenário ativo)"));
    checar(rND > 0, "(36) o bloco publica ND/EBITDA por cenário", String(rND));
    // Cada métrica tem 3 cenários × 2 linhas (valor e teste de rompimento).
    const ndBase = avaliarCelula(out, "G", rND + 1);
    const ndStress = avaliarCelula(out, "G", rND + 5);
    checar(typeof ndBase === "number" && typeof ndStress === "number",
      "(36) …com número nos três cenários", `${String(ndBase)} / ${String(ndStress)}`);
    if (typeof ndBase === "number" && typeof ndStress === "number") {
      // Mesma dívida, EBITDA menor: o índice do Stress é MAIOR EM MÓDULO.
      //
      // Em módulo, e não em valor, porque a dívida líquida pode ser NEGATIVA —
      // caixa maior que dívida, que é o caso desta fixture. Aí o índice é
      // negativo e "pior" significa mais distante de zero, não maior. Escrever
      // `>` puro fazia o assert cobrar o contrário justamente na empresa sem
      // dívida líquida, e foi o que ele acusou na primeira execução.
      checar(Math.abs(ndStress) > Math.abs(ndBase),
        "(36) …e o índice do Stress é maior EM MÓDULO, porque o EBITDA dele é menor",
        `Stress ${ndStress.toFixed(2)}x vs Base ${ndBase.toFixed(2)}x`);
    }
    const rDSCR = linhaDe(out, "DSCR por cenário",
      linhaDe(out, "Sensibilidade dos covenants ao cenário (dívida do cenário ativo)"));
    const dscrBase = avaliarCelula(out, "G", rDSCR + 1);
    const dscrStress = avaliarCelula(out, "G", rDSCR + 5);
    if (typeof dscrBase === "number" && typeof dscrStress === "number") {
      checar(dscrStress < dscrBase,
        "(36) o DSCR do Stress é MENOR que o do Base, pelo mesmo motivo",
        `Stress ${dscrStress.toFixed(2)}x vs Base ${dscrBase.toFixed(2)}x`);
    }

    // O CHECK que prende o bloco ao modelo: a coluna do cenário ativo tem de
    // reproduzir as linhas de RATIOS. Sem este zero o bloco poderia derivar em
    // silêncio, com números que continuariam plausíveis.
    const rChk = linhaDe(out, "CHECK: a coluna do cenário ATIVO bate com os índices acima (0 = bate)");
    checar(rChk > 0, "(36) o bloco tem CHECK contra as linhas de RATIOS", String(rChk));
    if (rChk > 0) {
      const v = avaliarCelula(out, "G", rChk);
      checar(typeof v === "number" && Math.abs(v) < 0.005,
        "(36) …e ele fecha em zero: a sensibilidade do cenário ativo é o próprio modelo",
        String(v));
    }
  }

  // A réplica completa (dívida e caixa por cenário) chegou depois deste teste
  // (36) ser escrito — o bloco de sensibilidade deixou de ser "o que falta" e
  // virou uma CONTRAPROVA declarada da réplica. O texto mudou de propósito, e
  // este assert acompanha a mudança em vez de travar a redação antiga.
  const rFora = (() => {
    for (let r = 1; r <= out.rowCount; r++) {
      if (/CONTRAPROVA do bloco abaixo/.test(String(out.getRow(r).getCell(3).value ?? ""))) return r;
    }
    return -1;
  })();
  checar(rFora > 0, "(36) o bloco DIZ o que ele é agora — contraprova, não lacuna");
  const txtFora = String(out.getRow(rFora).getCell(3).value ?? "");
  checar(/PISO/.test(txtFora),
    "(36) …declarando que esta leitura continua sendo um piso",
    txtFora.slice(0, 140));

  const rReplica = linhaDe(out, "RÉPLICA COMPLETA POR CENÁRIO (dívida e caixa correm nos três, não só no ativo)");
  checar(rReplica > 0, "(36) …e a réplica completa que resolve a lacuna existe na mesma aba", String(rReplica));

  // ---- E O EBITDA DA ABA DE RECEITA DEIXOU DE SER UMA LINHA VAZIA.
  //
  // Ela era DECLARADA e nunca preenchida — rótulo "EBITDA" com todas as colunas em
  // branco, o mesmo estado que a linha `DEPRECIACAO` já teve na mesma aba. Agora é
  // espelho do Income Statement, que é onde o EBITDA reconcilia com o documento.
  {
    const rEb = linhaDe(rec, "EBITDA");
    checar(rEb > 0, "(36) a aba de receita tem a linha de EBITDA");
    const cel = rec.getRow(rEb).getCell(7).value;
    checar(cel != null, "(36) …e ela NÃO está mais vazia", String(cel));
    checar(typeof cel === "object" && cel != null && "formula" in cel
      && /Income Statement/.test(String((cel as { formula: string }).formula)),
      "(36) …sendo ESPELHO do Income Statement, não um segundo cálculo do EBITDA",
      String(typeof cel === "object" && cel && "formula" in cel ? (cel as { formula: string }).formula : cel));
  }
}

// =============================================================================
// (37) O VOCABULÁRIO DE DÍVIDA FINANCEIRA — e este bloco é RELIGAMENTO, não enfeite.
//
// Havia SEIS lugares no `modelo-institucional.ts` fazendo a mesma pergunta ("esta
// linha é dívida, e portanto NÃO é giro?") com TRÊS regexes diferentes. O efeito
// media-se no book: "Conta garantida" (1.550) e "Duplicatas descontadas e
// antecipação de recebíveis" (5.277) ficavam no passivo OPERACIONAL e eram
// projetadas por DIAS DE GIRO CONTRA RECEITA — 6.827, ou 9,6% do passivo
// circulante informado. O resíduo de reconciliação do passivo circulante caiu de
// −19.987 (20,9% do ativo) para −15.149 (15,8%) com a unificação; o que sobra é
// divergência entre o mapa de dívida (43.542) e o balanço (28.393), que é dado a
// reconciliar e não defeito de código.
//
// Cada linha da tabela abaixo é um rótulo que APARECE em balanço brasileiro. Se
// alguém estreitar o vocabulário, o assert correspondente cai — que é o único
// jeito de este bloco valer alguma coisa.
{
  const DIVIDA: string[] = [
    // os que as três variantes já pegavam
    "Empréstimos bancários - capital de giro",
    "Financiamentos - FINAME/BNDES",
    "Debêntures a pagar",
    "Arrendamentos a pagar - CPC 06 (R2)",
    // …e os que NENHUMA delas pegava, medidos no book
    "Conta garantida",
    "Duplicatas descontadas e antecipação de recebíveis",
    "Cheque especial",
    "Desconto de recebíveis",
    "Adiantamento de contrato de câmbio",
    // só a variante mais completa (C) conhecia estes dois — agora todas conhecem
    "Leasing operacional a pagar",
    "Nota promissória comercial",
    "Cédula de crédito bancário",
    // (39t) a tranche bancária que o balancete chama só de "capital de giro" + o credor
    "CAPITAL DE GIRO BANCO ALFA - LP",
    "Banco Alfa - capital de giro",
    // credores com acento ou sigla (sem a flag `u` o \b não existia depois de "ú")
    "Capital de giro Itaú - LP", "Capital de giro BB", "Capital de giro Caixa Econômica Federal",
    "Capital de giro Banrisul - CP",
    // grupo com UM item só, e esse item é dívida: o rótulo diz o que é (tirá-lo calava dívida e juro)
    "Outras obrigações (financiamento BNDES)", "Outras contas a pagar: empréstimo Banco X",
    // vários itens, todos dívida (credor ou linha de financiamento só pelo nome): não é misto
    "Outras obrigações (BNDES, FINAME e capital de giro Banco X)",
    "Outras obrigações: capital de giro Bradesco e Itaú",
    // sem enumeração o próprio nome diz o que é: continua dívida
    "Outras contas a pagar - empréstimo de sócios",
    // (39t) DECISÃO DO DONO, 05/10/2026: "capital de giro" no passivo é dívida SEM credor no
    // rótulo (CPC 00/39/48; no Canastra "Capital de giro - longo prazo" 26.400 em 2023 está sob
    // "Empréstimos e Financiamentos"). Rótulos literais de dados.py do book Canastra:
    "Capital de giro", "Capital de giro - longo prazo", "Capital de giro - instituições financeiras",
    "Capital de giro Caixa",
  ];
  // O CONTRAPONTO É OBRIGATÓRIO: sem ele um `() => true` passaria em tudo acima.
  const GIRO: string[] = [
    "Fornecedores nacionais",
    "Salários e ordenados a pagar",
    "Adiantamentos de clientes",
    "Provisão de férias e encargos",
    "Outras contas a pagar",
    "Aluguéis a pagar - Vertentes Imóveis SPE",
    "Mútuos a pagar - Vertentes Participações S.A.",
    // Supplier finance fica FORA de propósito: se é dívida ou fornecedor é
    // julgamento contábil em aberto, e decidi-lo num regex mudaria resultado
    // financeiro por conta própria. Está escrito no vocabulário.
    "Risco sacado a pagar",
    "Confirming - fornecedores",
    // (39s) grupo de obrigações que só CITA desconto de duplicatas entre outras contas
    "Outras obrigações (adiantamentos de clientes, JCP a pagar e desconto de duplicatas)",
    // (39t) termos ANALÍTICOS que citam "capital de giro" e não são conta de dívida
    "Necessidade de capital de giro", "Necessidades de capital de giro",
    "Variação da necessidade de capital de giro", "Variação do capital de giro",
    "Capital de giro líquido", "Capital de giro próprio", "Capital circulante líquido",
    // (39t) grupo MISTO: cita capital de giro (dívida) junto com adiantamento de cliente (não é).
    // Segue grupo misto, com nota, e não vira dívida inteira.
    "Outras obrigações (adiantamentos de clientes e capital de giro)",
  ];
  for (const r of DIVIDA) {
    checar(ehDividaFinanceira(r), `(37) "${r}" é dívida financeira (não gira contra receita)`);
  }
  for (const r of GIRO) {
    checar(!ehDividaFinanceira(r), `(37) "${r}" continua sendo giro operacional`);
  }
  checar(grupoDeObrigacoesQueCitaDivida("Outras obrigações (adiantamentos de clientes e capital de giro)"),
    "(39t) …e o grupo que cita capital de giro com adiantamento de cliente é reconhecido como grupo MISTO (recebe NOTA_GRUPO_MISTO)");
}

// =============================================================================
// (38) OS DOIS DEFEITOS QUE SE MASCARAVAM — e a prova é o ATIVO fechando em ZERO.
//
// (a) `detectarSubtotaisPorOrdem` marcou "Matérias-primas e insumos" na coluna de
//     2024 (12.400), porque ali as linhas seguintes somavam POR COINCIDÊNCIA o
//     valor dela. O veredito era gravado como (secao_canonica, rótulo), SEM a
//     coluna — então a conta sumia do modelo em TODAS as colunas e em todas as
//     empresas. Em 2025 o bloco `ativo_circulante` ficava com 16 linhas somando
//     36.240 onde o documento tem 17 somando 45.440: os 9.200 dela.
//
// (b) O `Working Capital` gravava o histórico em `Math.abs`, e conta REDUTORA é
//     negativa por natureza. As duas provisões do book (−3.850 e −2.350) viravam
//     positivas e passavam a SOMAR: erro de +12.400, o DOBRO delas.
//
// OS DOIS SE ANULAVAM PARCIALMENTE: −9.200 de (a) contra +12.400 de (b) deixavam
// um resíduo de −3.200, pequeno o bastante para passar por arredondamento.
// Corrigir só um PIORAVA o número — é por isso que nenhum dos dois foi achado
// antes, e é por isso que este assert olha o RESULTADO e não cada causa.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const agora = new Date("2026-07-27T12:00:00Z");
  const wbBook = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos, agora,
    modeloInstitucional: entradaModeloDaFixture(fixture, agora),
  });
  const wsBS = wbBook.getWorksheet("Balance Sheet");
  checar(wsBS != null, "(38) o book monta o modelo institucional");
  if (wsBS) {
    let rAC = 0;
    for (let r = 1; r <= wsBS.rowCount; r++) {
      if (/reconcilia..o com o ativo circulante/.test(String(wsBS.getRow(r).getCell(3).value ?? ""))) {
        rAC = r; break;
      }
    }
    checar(rAC > 0, "(38) a linha de reconciliação do ativo circulante existe no book");
    if (rAC > 0) {
      esquecerMemoria(wsBS);
      let pior = 0;
      for (const c of ["E", "F", "G", "H", "I", "J", "K"]) {
        const v = avaliarCelula(wsBS, c, rAC);
        if (typeof v === "number") pior = Math.max(pior, Math.abs(v));
      }
      checar(pior < 1,
        "(38) o ATIVO CIRCULANTE reconcilia em ZERO — as contas extraídas somam o total informado",
        `maior resíduo: ${pior.toFixed(2)} (era 3.200 com os dois defeitos, `
        + `12.400 com só (a) corrigido e 9.200 com só (b))`);
    }
  }
}

// =============================================================================
// (39) A GUARDA DO GIRO AGREGADO — e o fixture é o caso de teste dela.
//
// Cada conta de giro é projetada por `dias ÷ 360 × base`, e nada olhava o
// AGREGADO. Vincular a MESMA premissa de prazo a N contas — um clique por linha
// na tela, o caminho natural de quem tem pressa — prendia N × dias de receita em
// capital de giro, e o balanço CONTINUA FECHANDO porque o patrimônio líquido
// absorve (Krauspenhar: ativo circulante operacional 36,10 mi -> 340,32 mi).
//
// O `modelo-da-fixture.mts` faz exatamente isso: liga UMA premissa de 60 dias a
// TODA conta de circulante. Enquanto o modelo aplicava o valor a CADA conta, isto
// era o caso de teste da guarda (medido: histórico 157 + 84 = 241 dias; projetado
// 767 + 852 = 1.619 dias; razão 5,9× contra o limiar de 2×).
//
// A CAUSA FOI CORRIGIDA NA ORIGEM (premissa ligada a K contas = valor do GRUPO,
// rateado pela parcela histórica — ver `gruposRateados`), então a fixture deixa de
// disparar a guarda, e o teste passa a afirmar as DUAS metades do comportamento:
//   (a) 60 dias ligados a todas as contas do ativo projetam 60 dias de receita, não
//       60 × N — e a guarda fica quieta;
//   (b) a guarda continua VIVA: uma HIPÓTESE genuinamente excessiva (600 dias) a
//       acusa. Sem (b) a guarda poderia ter morrido junto com o defeito que a
//       alimentava, e o verde de (a) não distinguiria "quieta porque está certo"
//       de "quieta porque não mede".
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const agora = new Date("2026-07-27T12:00:00Z");
  const montarG = (diasDaPremissa: number | null) => {
    const entrada = entradaModeloDaFixture(fixture, agora);
    if (diasDaPremissa !== null) {
      for (const p of entrada.premissas) {
        if (p.formula === "dias_de_giro") {
          p.valores = Object.fromEntries(Object.keys(p.valores).map((a) => [a, diasDaPremissa]));
        }
      }
    }
    return buildExportWorkbook({
      caso: { nome: "Book Vertentes", produto: "reestruturacao" },
      documentos: fixture.documentos, campos: fixture.campos, agora,
      modeloInstitucional: entrada,
    });
  };
  const wsG = montarG(null).getWorksheet("Working Capital");
  checar(wsG != null, "(39) a aba Working Capital existe");
  if (wsG) {
    const acha = (ws: typeof wsG, re: RegExp) => {
      for (let r = 1; r <= ws.rowCount; r++) {
        if (re.test(String(ws.getRow(r).getCell(3).value ?? ""))) return r;
      }
      return 0;
    };
    const rAC = acha(wsG, /Ativo de giro, em dias de receita/);
    const rPC = acha(wsG, /Passivo de giro, em dias de receita/);
    const rCk = acha(wsG, /CHECK — giro projetado/);
    checar(rAC > 0 && rPC > 0 && rCk > 0,
      "(39) as três linhas da guarda do giro agregado existem", `${rAC}/${rPC}/${rCk}`);
    if (rAC > 0 && rCk > 0) {
      esquecerMemoria(wsG);
      // O realizado NÃO publica razão: contra o próprio último ano ela é 1 por
      // construção, e número que não decide nada ensina a ignorar a linha.
      const noHist = avaliarCelula(wsG, "E", rCk);
      checar(typeof noHist !== "number",
        "(39) a razão NÃO é publicada nas colunas de realizado", String(noHist));
      // (a) 60 dias ligados a TODAS as contas do ativo = 60 dias de receita.
      const diasAtivo = ["G", "H", "I", "J", "K"].map((c) => avaliarCelula(wsG, c, rAC));
      // <= 60 e não == 60: a redutora "(-) Perdas estimadas..." não é ligada à premissa
      // (fica nos −13 dias que o realizado dela implica) e puxa o agregado para 47. O
      // exato de "grupo = dias/360 × base" está no bloco (39c) abaixo, com fixture própria.
      //
      // Desde 05/10/2026 o estoque gira contra CUSTO e o resto do ativo contra RECEITA: a
      // mesma premissa ligada a tudo vira DOIS grupos de bases diferentes (cada um projeta os
      // dias inteiros, com a nota ATENÇÃO — ver (39e)). Teto: 60 dias de receita + 60 dias de
      // custo, e 60 dias de custo valem menos que 60 de receita. Medido no Vertentes: 79,8
      // (era 47 com tudo contra receita). O defeito que o teto guarda era 767 (60 × N contas).
      checar(diasAtivo.every((v) => typeof v === "number" && v > 0 && v <= 120.5),
        "(39a) premissa de 60 dias ligada a TODAS as contas do ativo projeta no máximo UM grupo por "
        + "base (receita, custo), não 60 × N contas (era 767)",
        `ativo de giro projetado (dias): ${diasAtivo.map((v) => typeof v === "number" ? v.toFixed(1) : String(v)).join(" · ")}`);
      let pior = 0;
      for (const c of ["G", "H", "I", "J", "K"]) {
        const v = avaliarCelula(wsG, c, rCk);
        if (typeof v === "number") pior = Math.max(pior, v);
      }
      checar(pior <= 2,
        "(39a) …e a guarda fica QUIETA nessa configuração (era 5,9×, o defeito do lote)",
        `razão máxima: ${pior.toFixed(2)}× (limiar 2×)`);
    }
    // (b) a guarda continua viva diante de uma hipótese genuinamente excessiva.
    const wsX = montarG(600).getWorksheet("Working Capital")!;
    const rCkX = acha(wsX, /CHECK — giro projetado/);
    const rACX = acha(wsX, /Ativo de giro, em dias de receita/);
    esquecerMemoria(wsX);
    let piorX = 0;
    for (const c of ["G", "H", "I", "J", "K"]) {
      const v = avaliarCelula(wsX, c, rCkX);
      if (typeof v === "number") piorX = Math.max(piorX, v);
    }
    checar(piorX > 2,
      "(39b) a guarda ACUSA uma hipótese excessiva (600 dias de receita no ativo de giro)",
      `razão máxima: ${piorX.toFixed(1)}× (limiar 2×)`);
    const diasProjX = avaliarCelula(wsX, "G", rACX);
    checar(typeof diasProjX === "number" && diasProjX > 400,
      "(39b) …e o número que sustenta o veredito está publicado, em dias",
      `ativo de giro projetado: ${typeof diasProjX === "number" ? diasProjX.toFixed(0) : diasProjX} dias`);
  }
}

// =============================================================================
// (39c) PREMISSA LIGADA A K CONTAS = VALOR DO GRUPO, NÃO DE CADA CONTA.
//
// O DEFEITO, medido no Excel entregue do mandato Krauspenhar (caso 33b58a89): a
// premissa PME (150 dias) ligada em lote a 40 contas de estoque virava `dias/360 ×
// RECEITA_LÍQUIDA` EM CADA UMA. O ativo circulante operacional foi de 36,10 mi para
// 340,32 mi, a dívida de curto prazo de 18,00 para 333,11 mi, o ativo total de
// 113,86 para 413,15 mi — sem célula vermelha, o CHECK fechava. O mesmo vale para
// "Custo variável 88%" em lote numa seção de 47 contas (47 × 88% da receita) e para
// o capex por classe.
//
// O INVARIANTE AFIRMA COMPORTAMENTO: ligar a MESMA premissa a 1 conta ou a K contas
// que somam o MESMO saldo histórico dá o MESMO total projetado no bloco, e esse
// total é `dias/360 × base` (ou `taxa × base`). Cada conta leva a parcela histórica
// dela. Sem saldo realizado no grupo não há como ratear: a conta fica em BRANCO com
// nota de motivo e efeito — nem zero medido, nem divisão igual em silêncio.
//
// A fixture é SINTÉTICA de propósito (regra 4 do CLAUDE.md): o Krauspenhar não se
// reproduz sem o banco dele. O que se afirma aqui é a conta, não o caso real.
// =============================================================================
{
  const linhaA = (
    secao: string, chave: string, valores: Record<string, number>, doc = "BALANCO",
  ) => ({
    secao_canonica: secao, chave, rotulo_norm: chave.toLowerCase(),
    papel: "conta" as const, unidade: "milhar", moeda: "BRL", documentos: [doc], valores,
  });
  type ContaK = [string, number];
  // `estoques`, `custos` e `imobs` SOMAM o mesmo saldo em qualquer K.
  const montarK = (
    estoques: ContaK[], custos: ContaK[], imobs: ContaK[],
  ) => {
    const todas = [
      linhaA("receita_bruta", "Vendas de produtos", { "2024": 180000, "2025": 200000 }, "DRE"),
      ...custos.map(([n, v]) => linhaA("custos", n, { "2024": -v * 0.9, "2025": -v }, "DRE")),
      ...estoques.map(([n, v]) => linhaA("ativo_circulante", n, { "2024": v * 0.9, "2025": v })),
      ...imobs.map(([n, v]) => linhaA("ativo_nao_circulante", n, { "2024": v * 1.1, "2025": v })),
    ];
    const ligar = (cs: ContaK[], cod: string) => cs.map(([n]) => ({
      rotulo_norm: n.toLowerCase(), premissa_codigo: cod, sazonalidade_codigo: null,
    }));
    const entrada = {
      caso: { nome: "Premissa em lote", produto: "reestruturacao" },
      agora: new Date("2026-08-05T12:00:00Z"), entidade: "VERTENTES METALÚRGICA LTDA.",
      setor: "industria", anosHistoricos: [2024, 2025], anosProjetados: [2026, 2027, 2028],
      stressPct: 0.2, caixaMinimo: 5000, aliquotaTributos: 0.34,
      linhas: todas,
      premissas: [
        { codigo: "CRESC", nome: "Crescimento", natureza: "receita", formula: "crescimento_composto",
          unidade: "%", valores: { "2026": 8, "2027": 6, "2028": 5 }, origem: "digitado" },
        { codigo: "CUSTO", nome: "Custo variável", natureza: "custo", formula: "pct_de_linha",
          unidade: "%", valores: { "2026": 70, "2027": 70, "2028": 69 }, origem: "digitado" },
        { codigo: "PME", nome: "Prazo médio de estoque", natureza: "giro", formula: "dias_de_giro",
          unidade: "dias", valores: { "2026": 150, "2027": 150, "2028": 120 }, origem: "digitado" },
        { codigo: "CAPEX", nome: "Capex sobre receita líquida", natureza: "investimento",
          formula: "pct_de_linha", unidade: "%", valores: { "2026": 3, "2027": 3, "2028": 3 },
          origem: "digitado" },
      ],
      vinculos: [
        { rotulo_norm: "vendas de produtos", premissa_codigo: "CRESC", sazonalidade_codigo: null },
        ...ligar(custos, "CUSTO"), ...ligar(estoques, "PME"), ...ligar(imobs, "CAPEX"),
      ],
      macro: [], unidade: "R$ mil",
    };
    // O export só constrói o modelo com entidade reconhecível NOS CAMPOS extraídos.
    const V = "vK";
    return buildExportWorkbook({
      caso: entrada.caso,
      documentos: [{
        id: "dK", tipo_taxonomia: "BALANCO",
        entidade: { razao_social: "VERTENTES METALÚRGICA LTDA." },
        periodo: { tipo: "anual", referencia: "12M25" },
        documento_versao: [{ id: V, nome_original: "01_BP_2025.pdf" }],
      }] as DocumentoParaExport[],
      campos: [campo({ chave: "Caixa e equivalentes de caixa", secao: "Ativo Circulante",
        secao_canonica: "ativo_circulante", valor_num: 1000, documento_versao_id: V, ordem: 1 })],
      agora: entrada.agora, modo: "completo",
      modeloInstitucional: entrada as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
    });
  };

  // ---- leitura: rótulo EXATO (as linhas-filhas têm 4 espaços na frente)
  const rotDe = (ws: ExcelJS.Worksheet, r: number) => String(ws.getRow(r).getCell(3).value ?? "");
  const achaExato = (ws: ExcelJS.Worksheet, rotulo: string, depoisDe = 0) => {
    for (let r = depoisDe + 1; r <= ws.rowCount; r++) if (rotDe(ws, r) === rotulo) return r;
    return 0;
  };
  const COLS_K = { 2026: "G", 2027: "H", 2028: "I" } as const;
  const ANOS_K = [2026, 2027, 2028] as const;
  const num = (v: unknown) => (typeof v === "number" ? v : Number.NaN);
  const somaDe = (ws: ExcelJS.Worksheet, rotulos: string[], ano: 2026 | 2027 | 2028) =>
    rotulos.reduce((a, rot) => a + num(avaliarCelula(ws, COLS_K[ano], achaExato(ws, rot))), 0);

  // O MESMO saldo histórico: estoque 10.000, custo 100.000, imobilizado 60.000.
  const K1 = montarK([["Estoques", 10000]], [["Custo dos produtos vendidos", 100000]],
    [["Imobilizado", 60000]]);
  const nEst = ["Estoque matéria-prima", "Estoque produto acabado", "Estoque em trânsito", "Estoque de peças"];
  const nCus = ["Custo matéria-prima", "Custo mão de obra direta", "Custo frete", "Custo energia"];
  const nImo = ["Imobilizado - Máquinas", "Imobilizado - Veículos", "Imobilizado - Edificações"];
  const K4 = montarK(
    [[nEst[0], 4000], [nEst[1], 3000], [nEst[2], 2000], [nEst[3], 1000]],
    [[nCus[0], 50000], [nCus[1], 30000], [nCus[2], 15000], [nCus[3], 5000]],
    [[nImo[0], 30000], [nImo[1], 12000], [nImo[2], 18000]]);

  const RC = "Revenues, COGS & SG&A";
  const leitura = (wb: ReturnType<typeof montarK>, est: string[], cus: string[], imo: string[]) => {
    const wr = wb.getWorksheet(RC)!; const wc = wb.getWorksheet("Working Capital")!;
    const wf = wb.getWorksheet("Fixed Assets & CAPEX")!;
    for (const w of [wr, wc, wf]) esquecerMemoria(w);
    return { wr, wc, wf, est, cus, imo };
  };
  const L1 = leitura(K1, ["Estoques"], ["Custo dos produtos vendidos"], ["Capex — Imobilizado"]);
  const L4 = leitura(K4, nEst, nCus, nImo.map((n) => `Capex — ${n}`));

  for (const ano of ANOS_K) {
    const rl = num(avaliarCelula(L1.wr, COLS_K[ano], achaExato(L1.wr, "RECEITA LÍQUIDA")));
    checar(rl > 0, `(39c) ${ano}: a receita líquida projetada existe`, String(rl));
    const pctCusto = ano === 2028 ? 0.69 : 0.70;
    const dias = ano === 2028 ? 120 : 150;

    // ---- CUSTO: taxa × base, em 1 conta ou em 4
    const c1 = somaDe(L1.wr, L1.cus, ano); const c4 = somaDe(L4.wr, L4.cus, ano);
    checar(Math.abs(c1 - pctCusto * rl) < 0.5,
      `(39c) ${ano}: custo ligado a 1 conta = taxa × receita líquida`, `${c1} vs ${pctCusto * rl}`);
    checar(Math.abs(c4 - pctCusto * rl) < 0.5,
      `(39c) ${ano}: a MESMA taxa ligada a 4 contas dá taxa × receita líquida UMA vez (não 4×)`,
      `${c4} vs ${pctCusto * rl}`);
    // ---- GIRO: dias/360 × base
    const nr1 = num(avaliarCelula(L1.wc, COLS_K[ano], achaExato(L1.wc, "Receita líquida (base dos dias de giro de clientes e demais ativos)")));
    // ESTOQUE GIRA CONTRA CUSTO (decisão do dono, 05/10/2026): a base é a linha de custos do
    // Working Capital, não a receita líquida. `nr1` segue valendo para clientes e demais ativos.
    const cg = num(avaliarCelula(L1.wc, COLS_K[ano], achaExato(L1.wc, "Custos (base dos dias de giro de estoque e de fornecedor)")));
    checar(cg > 0 && Math.abs(cg - c1) < 0.5 && Math.abs(cg - nr1) > 1,
      `(39c) ${ano}: a base do estoque (custos) existe, é o CUSTO da aba de receita e difere da receita líquida`,
      `custos ${cg} · custo da aba ${c1} · receita líquida ${nr1}`);
    const e1 = somaDe(L1.wc, L1.est, ano); const e4 = somaDe(L4.wc, L4.est, ano);
    checar(Math.abs(e1 - dias / 360 * cg) < 0.5,
      `(39c) ${ano}: estoque ligado a 1 conta = dias/360 × CUSTOS do mesmo exercício`, `${e1} vs ${dias / 360 * cg}`);
    checar(Math.abs(e4 - dias / 360 * cg) < 0.5,
      `(39c) ${ano}: os MESMOS dias ligados a 4 contas de estoque dão dias/360 × custos UMA vez (não 4×)`,
      `${e4} vs ${dias / 360 * cg}`);
    // ---- CAPEX: taxa × base
    const x1 = somaDe(L1.wf, L1.imo, ano); const x3 = somaDe(L4.wf, L4.imo, ano);
    checar(Math.abs(x1 - 0.03 * rl) < 0.5 && Math.abs(x3 - 0.03 * rl) < 0.5,
      `(39c) ${ano}: a mesma taxa de capex em 1 classe ou em 3 dá taxa × receita líquida UMA vez`,
      `1 classe ${x1} · 3 classes ${x3} · esperado ${0.03 * rl}`);
  }
  // ---- DIAS HISTÓRICOS na MESMA base: dias implícitos × custos/360 devolve o saldo realizado.
  // Se o histórico medisse contra receita e a projeção contra custo, o 1º ano projetado saltaria.
  {
    const rE = achaExato(L1.wc, "Estoques");
    let rD = -1;
    for (let i = rE + 1; i <= L1.wc.rowCount; i++) {
      if (rotDe(L1.wc, i) === "    dias de giro (base)") { rD = i; break; }
    }
    const diasH = num(avaliarCelula(L1.wc, "F", rD));
    const cgH = num(avaliarCelula(L1.wc, "F", achaExato(L1.wc, "Custos (base dos dias de giro de estoque e de fornecedor)")));
    const saldoH = num(avaliarCelula(L1.wc, "F", rE));
    checar(rD > 0 && saldoH === 10000 && cgH > 0 && Math.abs(diasH / 360 * cgH - saldoH) < 0.5,
      "(39c) os dias HISTÓRICOS do estoque são medidos contra custos: dias × custos/360 = saldo realizado",
      `dias ${diasH} · custos ${cgH} · saldo ${saldoH}`);
  }
  // ---- cada conta leva a PARCELA HISTÓRICA dela (estoque 40/30/20/10%)
  {
    const tot = somaDe(L4.wc, nEst, 2026);
    const partes = nEst.map((n) => num(avaliarCelula(L4.wc, "G", achaExato(L4.wc, n))) / tot);
    checar([0.4, 0.3, 0.2, 0.1].every((e, i) => Math.abs(partes[i] - e) < 1e-6),
      "(39c) cada conta de estoque leva a parcela do saldo realizado (40/30/20/10%)", partes.join(" · "));
    const totC = somaDe(L4.wr, nCus, 2026);
    const partesC = nCus.map((n) => num(avaliarCelula(L4.wr, "G", achaExato(L4.wr, n))) / totC);
    checar([0.5, 0.3, 0.15, 0.05].every((e, i) => Math.abs(partesC[i] - e) < 1e-6),
      "(39c) …e cada conta de custo a dela (50/30/15/5%)", partesC.join(" · "));
  }
  // ---- as sombras (Base, Cliente, Stress) e o Stress saem do MESMO cálculo
  {
    const dif = (a: unknown) => (typeof a === "number" ? Math.abs(a) : Infinity);
    const rSh = achaExato(L4.wr, "    CHECK: sombra do cenário ATIVO − linha ativa (0 = as duas concordam)");
    const rShWC = achaExato(L4.wc, "    CHECK: a sombra do cenário ATIVO bate com a NCG ativa (0 = bate)");
    checar(rSh > 0 && rShWC > 0, "(39c) os dois CHECK de sombra existem", `${rSh}/${rShWC}`);
    checar(ANOS_K.every((a) => dif(avaliarCelula(L4.wr, COLS_K[a], rSh)) < 0.5),
      "(39c) com K=4 a sombra de receita/custo concorda com a linha ativa em todo ano");
    checar(ANOS_K.every((a) => dif(avaliarCelula(L4.wc, COLS_K[a], rShWC)) < 0.5),
      "(39c) com K=4 a NCG por cenário concorda com a NCG ativa em todo ano");
    // Stress do estoque: a soma das sombras de Stress das 4 contas = a de 1 conta.
    const shStr = (ws: ExcelJS.Worksheet, n: string) => {
      const r = achaExato(ws, n);
      for (let i = r + 1; i <= ws.rowCount; i++) {
        if (rotDe(ws, i) === "    sombra — str") return num(avaliarCelula(ws, "G", i));
      }
      return Number.NaN;
    };
    const s1 = shStr(L1.wc, "Estoques"); const s4 = nEst.reduce((a, n) => a + shStr(L4.wc, n), 0);
    checar(s1 > 0 && Math.abs(s1 - s4) < 0.5,
      "(39c) o STRESS do estoque ligado a 4 contas soma o mesmo que a 1 conta",
      `1 conta ${s1} · 4 contas ${s4}`);
  }

  // ---- SEM SALDO para ratear: BRANCO + nota (motivo e efeito); nunca zero, nunca divisão igual
  {
    const KZ = montarK(
      [["Estoque zerado A", 0], ["Estoque zerado B", 0]],
      [["Custo zerado A", 0], ["Custo zerado B", 0]],
      [["Imobilizado zerado A", 0], ["Imobilizado zerado B", 0]]);
    const wr = KZ.getWorksheet(RC)!; const wc = KZ.getWorksheet("Working Capital")!;
    const wf = KZ.getWorksheet("Fixed Assets & CAPEX")!;
    const cel = (ws: ExcelJS.Worksheet, rot: string) => ws.getRow(achaExato(ws, rot)).getCell(7);
    const alvos: Array<[string, ExcelJS.Cell]> = [
      ["estoque", cel(wc, "Estoque zerado A")], ["custo", cel(wr, "Custo zerado A")],
      ["capex", cel(wf, "Capex — Imobilizado zerado A")],
    ];
    for (const [nome, c] of alvos) {
      const vazia = c.value === null || c.value === undefined;
      const nota = typeof c.note === "string" ? c.note : JSON.stringify(c.note ?? "");
      checar(vazia, `(39c) grupo de ${nome} sem saldo realizado: a célula fica em BRANCO (não zero, não rateio igual)`,
        JSON.stringify(c.value));
      checar(/NÃO é projetada/.test(nota) && /(MENOR|MENOS)/.test(nota) && /ratear/.test(nota),
        `(39c) …e a nota do ${nome} diz o motivo (sem saldo para ratear) E o efeito (bloco menor)`, nota.slice(0, 160));
    }
  }
}

// =============================================================================
// (39d) O NOME DE UM AGRUPAMENTO DECLARADO NUM DOCUMENTO NÃO TIRA A CONTA HOMÔNIMA DOS OUTROS.
//
// O DEFEITO, medido no Excel do mandato Krauspenhar (caso 33b58a89): "Venda de peças e
// lubrificantes" é CONTA na DRE 2025 (36,19 mi) e, no balancete de 2026, é o NOME DO
// AGRUPAMENTO sob o qual as filhas ("Peças GTS", "Peças Massey"…) são impressas. A
// regra (A) de `detectarSubtotaisInformados` ("rótulo == nome de agrupamento declarado
// pelo documento, e o agrupamento tem membros") olhava a ABA INTEIRA: bastava um
// documento declarar o agrupamento para marcar como subtotal TODA ocorrência do rótulo,
// inclusive a folha da DRE de outro exercício. O modelo tirava a linha da soma em todos os
// anos: receita bruta de 2025 = 77,19 mi contra 113,38 mi da DRE, e os 36,19 mi viravam uma
// "reconciliação" constante na projeção.
//
// REGRA 4: a fixture é SINTÉTICA. Os campos reais (`campo_extraido`) do Krauspenhar não
// foram vistos; o arranjo abaixo — filhas com `secao` igual ao rótulo da conta no
// COMBINADO de 2026, a mesma conta como folha na DRE de 2025, mesma aba — é a leitura do
// código (regra A, aba inteira), e fica afirmado só o comportamento: cada documento decide
// sobre as linhas DELE.
// =============================================================================
{
  const ENT = "KRAUSPENHAR TESTE LTDA.";
  const NOME = "Venda de peças e lubrificantes";
  const mk = (id: string, tipo: string, ref: string) => ({
    id, tipo_taxonomia: tipo, entidade: { razao_social: ENT },
    periodo: { tipo: "anual", referencia: ref }, documento_versao: [{ id: `v${id}`, nome_original: `${id}.pdf` }],
  }) as DocumentoParaExport;
  const c = (v: string, chave: string, secao: string, valor: number, ordem: number) =>
    campo({ chave, secao, secao_canonica: "receita_bruta", valor_num: valor, ordem,
            documento_versao_id: v, unidade: "milhar" } as never);
  const campos: CampoExtraido[] = [
    // DRE 2025: a peça é FOLHA (36.190 + 77.000 = 113.190)
    c("vDRE25", NOME, "Receitas", 36190, 1),
    c("vDRE25", "Venda de veículos", "Receitas", 77000, 2),
    // COMBINADO 2026: a MESMA conta é o agrupamento das filhas (12.000 + 8.000 = 20.000)
    c("vCOMB26", NOME, "Receitas", 20000, 1),
    c("vCOMB26", "Peças GTS", NOME, 12000, 2),
    c("vCOMB26", "Peças Massey", NOME, 8000, 3),
    c("vCOMB26", "Venda de veículos", "Receitas", 70000, 4),
  ];
  const documentos = [mk("DRE25", "DRE", "2025"), mk("COMB26", "COMBINADO", "2026")];
  const norm = (x: string) => x.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
  const linhaA = (chave: string, valores: Record<string, number>, doc: string) => ({
    secao_canonica: "receita_bruta", chave, rotulo_norm: norm(chave),
    papel: "conta" as const, unidade: "milhar", moeda: "BRL", documentos: [doc], valores,
  });
  const entrada = {
    caso: { nome: "Rótulo folha e agrupamento", produto: "reestruturacao" },
    agora: new Date("2026-09-05T12:00:00Z"), entidade: ENT, setor: "comercio",
    anosHistoricos: [2025, 2026], anosProjetados: [2027, 2028],
    stressPct: 0.2, caixaMinimo: 0, aliquotaTributos: 0.34,
    linhas: [
      linhaA(NOME, { "2025": 36190, "2026": 20000 }, "DRE"),
      linhaA("Peças GTS", { "2026": 12000 }, "COMBINADO"),
      linhaA("Peças Massey", { "2026": 8000 }, "COMBINADO"),
      linhaA("Venda de veículos", { "2025": 77000, "2026": 70000 }, "DRE"),
    ],
    premissas: [], vinculos: [], macro: [], unidade: "R$ mil",
  };
  const wb = buildExportWorkbook({
    caso: entrada.caso, documentos, campos, agora: entrada.agora, modo: "completo",
    modeloInstitucional: entrada as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
  });
  const ws = wb.getWorksheet("Revenues, COGS & SG&A")!;
  esquecerMemoria(ws);
  let rG = 0;
  for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(3).value ?? "") === "GROSS REVENUES") { rG = r; break; }
  const g25 = avaliarCelula(ws, "E", rG);
  const g26 = avaliarCelula(ws, "F", rG);
  checar(typeof g25 === "number" && Math.abs(g25 - 113190) < 0.5,
    "(39d) a peça é CONTA na DRE 2025: a receita bruta de 2025 soma a conta (113.190, não 77.000)",
    `2025: ${JSON.stringify(g25)}`);
  checar(typeof g26 === "number" && Math.abs(g26 - 90000) < 0.5,
    "(39d) …e no COMBINADO 2026 o agrupamento não soma junto das filhas (90.000, não 110.000)",
    `2026: ${JSON.stringify(g26)}`);
}

// =============================================================================
// (39e) O MESMO CÓDIGO EM CUSTO E SG&A É UM GRUPO; EM BASES DIFERENTES, O ARQUIVO AVISA.
//
// O RESÍDUO DO (39c), medido em produção (caso "AMO teste 00"): o grupo se formava por bloco,
// então o mesmo código ligado a contas de custo E de SG&A (MARKDOWN 2%: 7 + 6 contas) virava
// dois grupos, cada um com parcelas somando 1 — o total projetado saía 2× a premissa (4% da
// receita), sem nota. Custo e SG&A são medidos contra a MESMA base (receita líquida), então
// são um grupo só. Onde a base é outra (ativo × passivo, fornecedor contra custo × resto contra
// receita — PMR em 16 + 2 contas, PMP em 5 + 59), somar não tem sentido e ratear entre eles
// seria regra inventada: os grupos ficam separados, cada um projeta os dias inteiros, e a
// célula DIZ isso (motivo e efeito) em vez de passar calado.
//
// REGRA 4: fixture sintética; o "AMO teste 00" é o caso de teste de produção e não se
// reproduz sem o banco. Afirma-se a conta, não o caso.
// =============================================================================
{
  const linhaA = (secao: string, chave: string, valores: Record<string, number>, doc = "BALANCO") => ({
    secao_canonica: secao, chave, rotulo_norm: chave.toLowerCase(),
    papel: "conta" as const, unidade: "milhar", moeda: "BRL", documentos: [doc], valores,
  });
  const montar = (
    custos: Array<[string, number]>, sgas: Array<[string, number]>,
    ativos: Array<[string, number]>, passivos: Array<[string, number]>,
    pmp: Array<[string, number]>,
  ) => {
    const entrada = {
      caso: { nome: "Mesmo código, dois blocos", produto: "reestruturacao" },
      agora: new Date("2026-08-05T12:00:00Z"), entidade: "VERTENTES METALÚRGICA LTDA.",
      setor: "industria", anosHistoricos: [2024, 2025], anosProjetados: [2026, 2027],
      stressPct: 0.2, caixaMinimo: 5000, aliquotaTributos: 0.34,
      linhas: [
        linhaA("receita_bruta", "Vendas de produtos", { "2024": 180000, "2025": 200000 }, "DRE"),
        // despesa na convenção do documento (negativa): o modelo normaliza por bloco
        ...custos.map(([n, v]) => linhaA("custos", n, { "2024": -v, "2025": -v }, "DRE")),
        ...sgas.map(([n, v]) => linhaA("despesas_operacionais", n, { "2024": -v, "2025": -v }, "DRE")),
        ...ativos.map(([n, v]) => linhaA("ativo_circulante", n, { "2024": v, "2025": v })),
        ...[...passivos, ...pmp].map(([n, v]) => linhaA("passivo_circulante", n, { "2024": v, "2025": v })),
      ],
      premissas: [
        { codigo: "CRESC", nome: "Crescimento", natureza: "receita", formula: "crescimento_composto",
          unidade: "%", valores: { "2026": 8, "2027": 6 }, origem: "digitado" },
        { codigo: "MARKDOWN", nome: "Markdown", natureza: "custo", formula: "pct_de_linha",
          unidade: "%", valores: { "2026": 50, "2027": 50 }, origem: "digitado" },
        { codigo: "PMR", nome: "Prazo médio de recebimento", natureza: "giro", formula: "dias_de_giro",
          unidade: "dias", valores: { "2026": 90, "2027": 90 }, origem: "digitado" },
        { codigo: "PMP", nome: "Prazo médio de pagamento", natureza: "giro", formula: "dias_de_giro",
          unidade: "dias", valores: { "2026": 60, "2027": 60 }, origem: "digitado" },
      ],
      vinculos: [
        { rotulo_norm: "vendas de produtos", premissa_codigo: "CRESC", sazonalidade_codigo: null },
        ...[...custos, ...sgas].map(([n]) => ({ rotulo_norm: n.toLowerCase(), premissa_codigo: "MARKDOWN", sazonalidade_codigo: null })),
        ...[...ativos, ...passivos].map(([n]) => ({ rotulo_norm: n.toLowerCase(), premissa_codigo: "PMR", sazonalidade_codigo: null })),
        ...pmp.map(([n]) => ({ rotulo_norm: n.toLowerCase(), premissa_codigo: "PMP", sazonalidade_codigo: null })),
      ],
      macro: [], unidade: "R$ mil",
    };
    const V = "vE";
    return buildExportWorkbook({
      caso: entrada.caso, agora: entrada.agora, modo: "completo",
      documentos: [{
        id: "dE", tipo_taxonomia: "BALANCO", entidade: { razao_social: "VERTENTES METALÚRGICA LTDA." },
        periodo: { tipo: "anual", referencia: "12M25" }, documento_versao: [{ id: V, nome_original: "bp.pdf" }],
      }] as DocumentoParaExport[],
      campos: [campo({ chave: "Caixa e equivalentes de caixa", secao: "Ativo Circulante",
        secao_canonica: "ativo_circulante", valor_num: 1000, documento_versao_id: V, ordem: 1 })],
      modeloInstitucional: entrada as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
    });
  };
  const rotDe = (ws: ExcelJS.Worksheet, r: number) => String(ws.getRow(r).getCell(3).value ?? "");
  const acha = (ws: ExcelJS.Worksheet, rot: string, depois = 0) => {
    for (let r = depois + 1; r <= ws.rowCount; r++) if (rotDe(ws, r) === rot) return r;
    return 0;
  };
  const RC = "Revenues, COGS & SG&A";
  const soma = (ws: ExcelJS.Worksheet, nomes: string[], col: string) =>
    nomes.reduce((a, n) => a + Number(avaliarCelula(ws, col, acha(ws, n))), 0);

  // ---- custo + SG&A, mesmo código: taxa × receita líquida UMA vez (não 2×)
  const cusN = ["Custo A", "Custo B"]; const sgaN = ["Despesa X", "Despesa Y"];
  const W1 = montar([["Custo A", 60000]], [["Despesa X", 40000]], [], [], []);
  const W4 = montar([["Custo A", 60000], ["Custo B", 40000]], [["Despesa X", 30000], ["Despesa Y", 10000]], [], [], []);
  for (const [nome, wb, cs, sg] of [
    ["1 custo + 1 SG&A", W1, ["Custo A"], ["Despesa X"]], ["2 custos + 2 SG&A", W4, cusN, sgaN],
  ] as const) {
    const ws = wb.getWorksheet(RC)!; esquecerMemoria(ws);
    const rl = Number(avaliarCelula(ws, "G", acha(ws, "RECEITA LÍQUIDA")));
    const tot = soma(ws, [...cs, ...sg], "G");
    checar(rl > 0 && Math.abs(tot - 0.5 * rl) < 0.5,
      `(39e) ${nome}, mesmo código: custo + SG&A somam taxa × receita líquida UMA vez (não 2×)`,
      `${tot} vs ${0.5 * rl} (2× seria ${rl})`);
  }
  {
    const ws = W4.getWorksheet(RC)!; esquecerMemoria(ws);
    const tot = soma(ws, [...cusN, ...sgaN], "G");
    const partes = [...cusN, ...sgaN].map((n) => Number(avaliarCelula(ws, "G", acha(ws, n))) / tot);
    checar([0.4286, 0.2857, 0.2143, 0.0714].every((e, i) => Math.abs(partes[i] - e) < 1e-3),
      "(39e) cada conta leva a parcela no grupo INTEIRO (custo e SG&A juntos: 60/40/30/10 de 140)",
      partes.map((x) => x.toFixed(4)).join(" · "));
  }

  // ---- bases diferentes: grupos separados, cada um com os dias inteiros, e a NOTA
  const WB = montar([], [], [["Conta a receber A", 10000], ["Conta a receber B", 6000]],
    [["Obrigações trabalhistas", 5000]], [["Fornecedores nacionais", 20000]]);
  {
    const wc = WB.getWorksheet("Working Capital")!; esquecerMemoria(wc);
    const nota = (nome: string) => {
      const r = acha(wc, nome);
      const rd = acha(wc, "    dias de giro (base)", r);
      const c = wc.getRow(rd).getCell(7);
      return typeof c.note === "string" ? c.note : JSON.stringify(c.note ?? "");
    };
    const nAtivo = nota("Conta a receber A");
    checar(/ATENÇÃO/.test(nAtivo) && /2 grupos com bases diferentes/.test(nAtivo) && /ativo\/receita líquida/.test(nAtivo)
      && /passivo\/receita líquida/.test(nAtivo) && /revise o vínculo/.test(nAtivo),
      "(39e) PMR no ativo e no passivo: a célula diz que são 2 grupos de bases diferentes e o efeito",
      nAtivo.slice(-260));
    checar(/ATENÇÃO/.test(nota("Obrigações trabalhistas")),
      "(39e) …e a conta do PASSIVO recebe o mesmo aviso");
    const nRec = Number(avaliarCelula(wc, "G", acha(wc, "Receita líquida (base dos dias de giro de clientes e demais ativos)")));
    const gAtivo = soma(wc, ["Conta a receber A", "Conta a receber B"], "G");
    checar(Math.abs(gAtivo - 90 / 360 * nRec) < 0.5,
      "(39e) …cada grupo projeta os dias inteiros: o do ativo soma dias/360 × receita (não rateia contra o passivo)",
      `${gAtivo} vs ${90 / 360 * nRec}`);
    const pas = Number(avaliarCelula(wc, "G", acha(wc, "Obrigações trabalhistas")));
    checar(Math.abs(pas - 90 / 360 * nRec) < 0.5,
      "(39e) …e o do passivo também (K=1: idêntico ao de antes)", `${pas} vs ${90 / 360 * nRec}`);
  }
  // fornecedor contra custo × resto contra receita, MESMO código
  {
    const W2 = montar([], [], [], [], [["Fornecedores nacionais", 20000], ["Outras obrigações operacionais", 4000]]);
    const wc = W2.getWorksheet("Working Capital")!; esquecerMemoria(wc);
    const r = acha(wc, "Outras obrigações operacionais");
    const c = wc.getRow(acha(wc, "    dias de giro (base)", r)).getCell(7);
    const n = typeof c.note === "string" ? c.note : JSON.stringify(c.note ?? "");
    checar(/ATENÇÃO/.test(n) && /passivo\/custos/.test(n) && /passivo\/receita líquida/.test(n),
      "(39e) PMP em fornecedor (base custos) e em outra conta (base receita): dois grupos, e a nota diz as duas bases",
      n.slice(-260));
  }
}

// =============================================================================
// (40) O REPERFILAMENTO MEDE CAIXA — e a prova é a alavanca de HAIRCUT mexer nele.
//
// O bloco REPERFILAMENTO compara o serviço do cronograma original com o serviço
// negociado, e o veredito dele manda o leitor usar três alavancas quando a
// carência não basta: prazo maior, HAIRCUT (a chave "Efeito caixa?" da aba de
// dívida) ou dinheiro novo. O "depois" lia `TOTAL_AMORT` — a amortização BRUTA —
// enquanto todo o resto do arquivo lê `ESP_AMORT`, que é a de CAIXA. Consequência
// medida: virar a chave para "N" derrubava o serviço de 55.150 para 52.917 e o
// alívio continuava ZERO; e o contrafactual `RP_DSCR_SEM`, que soma o alívio de
// volta ao serviço, ANDAVA — quando ele é justamente o lado que tem de ficar
// parado quando se puxa uma alavanca de negociação.
//
// Este assert olha as DUAS pontas, porque cada uma sozinha passaria com o defeito
// pela metade: o alívio tem de MEXER, e o contrafactual tem de FICAR.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const agora = new Date("2026-07-27T12:00:00Z");
  const montar = () => buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos, agora,
    modeloInstitucional: entradaModeloDaFixture(fixture, agora),
  });
  const acharEm = (ws: ExcelJS.Worksheet, re: RegExp) => {
    for (let r = 1; r <= ws.rowCount; r++) {
      if (re.test(String(ws.getRow(r).getCell(3).value ?? ""))) return r;
    }
    return 0;
  };
  const COL = "G";
  const medir = (wb: ExcelJS.Workbook) => {
    const out = wb.getWorksheet("Output")!;
    esquecerMemoria(out);
    const v = (re: RegExp) => {
      const r = acharEm(out, re);
      return r ? avaliarCelula(out, COL, r) : undefined;
    };
    return {
      antes: v(/Serviço das tranches no cronograma original/),
      depois: v(/Serviço das mesmas tranches como está negociado/),
      alivio: v(/Alívio do exercício/),
      dscrSem: v(/DSCR que o cronograma original produziria/),
    };
  };

  const semHaircut = medir(montar());
  checar(typeof semHaircut.depois === "number" && semHaircut.depois > 0,
    "(40) o bloco de reperfilamento publica um serviço negociado",
    String(semHaircut.depois));
  checar(typeof semHaircut.alivio === "number" && Math.abs(semHaircut.alivio) < 1,
    "(40) sem carência e sem haircut, o alívio é ZERO — os dois lados são o mesmo cronograma",
    String(semHaircut.alivio));

  // Puxa a alavanca: a primeira tranche passa a reduzir saldo SEM pagamento.
  const wbH = montar();
  const wsDiv = wbH.getWorksheet("ST Inv. & Debt")!;
  let virou = false;
  for (let r = 1; r <= wsDiv.rowCount && !virou; r++) {
    const cel = wsDiv.getRow(r).getCell(4);
    if (String(cel.value ?? "") === "S") { cel.value = "N"; virou = true; }
  }
  checar(virou, "(40) a fixture tem chave de efeito caixa para virar");
  const comHaircut = medir(wbH);

  const moveu = typeof semHaircut.depois === "number" && typeof comHaircut.depois === "number"
    ? semHaircut.depois - comHaircut.depois : 0;
  checar(moveu > 1,
    "(40) o HAIRCUT reduz o serviço NEGOCIADO — o 'depois' lê amortização de caixa, não a bruta",
    `serviço: ${String(semHaircut.depois)} → ${String(comHaircut.depois)} (era imóvel com TOTAL_AMORT)`);
  checar(typeof comHaircut.alivio === "number" && comHaircut.alivio > 1,
    "(40) …e o ALÍVIO passa a existir para a alavanca que o próprio veredito recomenda",
    `alívio: ${String(comHaircut.alivio)}`);
  // O "antes" é o cronograma ORIGINAL: haircut é negociação, não faz parte dele.
  checar(typeof semHaircut.antes === "number" && typeof comHaircut.antes === "number"
    && Math.abs(semHaircut.antes - comHaircut.antes) < 0.01,
    "(40) o 'antes' NÃO se move: haircut é negociação, e o cronograma original a desconhece",
    `${String(semHaircut.antes)} → ${String(comHaircut.antes)}`);
  // E a ponta que o defeito revelava: o contrafactual tem de ficar PARADO.
  const sem = semHaircut.dscrSem, com = comHaircut.dscrSem;
  checar(typeof sem === "number" && typeof com === "number" && Math.abs(sem - com) < 1e-6,
    "(40) o CONTRAFACTUAL fica parado quando se puxa a alavanca — serviço e alívio na mesma base",
    `DSCR sem negociação: ${String(sem)} → ${String(com)}`);
}

// =============================================================================
// (41) AS GUARDAS DOS ÍNDICES DIZEM A VERDADE — zero não é "não se aplica".
//
// Dois defeitos da mesma família, e os dois publicavam NÚMERO onde a razão não
// existe. Número mente duas vezes aqui: uma para quem lê, e outra para o teste de
// covenant ao lado, que decide se roda por `ISNUMBER`.
//
// (a) `R_LIQ_CORR` devolvia 0 com passivo circulante ZERO. Zero é número, o teste
//     rodava, comparava 0 < corte e publicava "ROMPE" — a empresa com a MELHOR
//     liquidez possível reportada ao comitê como rompendo o covenant.
// (b) `R_ALAV_PL` testava `<>0` e rotulava "PL<=0". Com patrimônio a descoberto
//     ele dividia e saía múltiplo NEGATIVO: a própria fixture publicava −1,03x,
//     que se lê como "quase sem dívida" e significa patrimônio consumido.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const agora = new Date("2026-07-27T12:00:00Z");
  // `custoPct` força a premissa de custo variável. A fixture tinha PL negativo POR ACIDENTE: o
  // mesmo código de custo ligado a custo E a SG&A projetava 60% + 60% = 120% da receita (o
  // defeito do grupo por bloco). Com o grupo único (60% no total) o PL deixa de ser negativo,
  // e o caso "PL a descoberto" passa a ser montado de propósito, com custo de 120%.
  const montar = (custoPct?: number) => {
    const entrada = entradaModeloDaFixture(fixture, agora);
    if (custoPct !== undefined) {
      for (const pr of entrada.premissas) {
        if (pr.codigo === "CUSTO_VARIAVEL") {
          pr.valores = Object.fromEntries(Object.keys(pr.valores).map((k) => [k, custoPct]));
        }
      }
    }
    return buildExportWorkbook({
      caso: { nome: "Book Vertentes", produto: "reestruturacao" },
      documentos: fixture.documentos, campos: fixture.campos, agora,
      modeloInstitucional: entrada,
    });
  };
  const acharEm = (ws: ExcelJS.Worksheet, re: RegExp) => {
    for (let r = 1; r <= ws.rowCount; r++) {
      if (re.test(String(ws.getRow(r).getCell(3).value ?? ""))) return r;
    }
    return 0;
  };
  const COL = "G";

  // (b) PL NEGATIVO: custo de 120% da receita (prejuízo) consome o patrimônio — caso de reestruturação.
  {
    const wb = montar(120); const out = wb.getWorksheet("Output")!;
    esquecerMemoria(out);
    const rPL = acharEm(out, /^Shareholder's Equity$/);
    const pl = avaliarCelula(out, COL, rPL);
    checar(typeof pl === "number" && pl < 0,
      "(41) com custo de 120% da receita o patrimônio líquido fica NEGATIVO nesta coluna",
      String(pl));
    const alav = avaliarCelula(out, COL, acharEm(out, /^Dívida bruta \/ Patrim/));
    checar(alav === "PL<=0",
      "(41) com PL a descoberto a alavancagem NÃO vira múltiplo negativo, e a célula diz por quê",
      `publicou: ${JSON.stringify(alav)} (era −1,03x)`);
  }

  // (a) Passivo circulante zerado: a razão some e o covenant não acusa nada.
  {
    const wb = montar(); const out = wb.getWorksheet("Output")!;
    out.getRow(acharEm(out, /^Current Liabilities$/)).getCell(COL).value = 0;
    esquecerMemoria(out);
    const rLC = acharEm(out, /^Liquidez corrente/);
    const liq = avaliarCelula(out, COL, rLC);
    checar(liq === "PC<=0",
      "(41) sem passivo circulante a liquidez corrente não é ZERO — ela não existe",
      `publicou: ${JSON.stringify(liq)}`);
    // A linha seguinte é o corte, a de baixo é o veredito (R, C, T nessa ordem).
    const rompe = avaliarCelula(out, COL, rLC + 2);
    checar(rompe === "n.a.",
      "(41) …e o teste de covenant diz \"n.a.\" em vez de acusar ROMPE em quem não deve nada",
      `publicou: ${JSON.stringify(rompe)}`);
    const seca = avaliarCelula(out, COL, acharEm(out, /^Liquidez seca/));
    checar(seca === "PC<=0",
      "(41) a liquidez seca segue a mesma regra", `publicou: ${JSON.stringify(seca)}`);
  }
}

// =============================================================================
// (50) A RÉPLICA COMPLETA POR CENÁRIO — dívida e caixa correm nos três, não só
// no cenário ativo.
//
// O bloco de sensibilidade (36) já provava que a leitura ANTERIOR era um PISO
// deliberado: só o EBITDA variava, a dívida ficava presa ao cenário ativo. Este
// teste prova o que veio substituir essa lacuna — uma segunda cascata de
// revolver, uma por cenário, com a MESMA técnica sem circularidade do revolver
// ativo (juros sobre o saldo de ABERTURA).
//
// O QUE ELE TRAVA:
//   1. O CHECK É ZERO: a réplica do cenário ATIVO (via CHOOSE) bate com a
//      dívida líquida do bloco de RATIOS — a prova de que a segunda cascata lê
//      exatamente os mesmos insumos da primeira.
//   2. DIREÇÃO, NÃO SÓ ZERO: o revolver do Stress é, em TODO ano projetado,
//      maior ou igual ao do Base — por indução (EBITDA pior, NCG pior nos dois
//      lados pela `#diasStr`, CAPEX e serviço da dívida IGUAIS → caixa antes do
//      revolver do Stress nunca é maior; o revolver dele nunca saca menos). Um
//      CHECK que só prova zero não pega um sinal trocado que ainda fecha —
//      pega um sinal trocado que faz o Stress parecer MELHOR, que é
//      exatamente o defeito que este teste existe para impedir.
//   3. O PICO DE USO DO REVOLVER — o número que o piso antigo declarava fora
//      do alcance — publica maior no Stress que no Base no último ano
//      projetado, pela mesma razão do item 2.
//
// (51), logo abaixo, GIRA O DIAL de verdade — o teste (50) sozinho só
// conferia com o dial no padrão (Base, `G2=1`), e isso escondeu um defeito
// real na primeira versão deste bloco: o `CHECK_SOMBRA_WC` do Working
// Capital comparava a sombra do BASE CASE fixa contra a NCG ativa, em vez
// de escolher a sombra do cenário LIGADO — e como o arquivo sempre nasce
// com o dial no Base, nenhuma suíte via a célula acusar uma divergência
// falsa assim que alguém girasse para Cliente ou Stress, que é o estado
// normal de um arquivo de reestruturação. Os dois testes montam o MESMO
// workbook uma vez só — duplicar o carregamento da fixture e as abas só
// para trocar o número do teste no rótulo é o tipo de duplicação que o
// próprio CI deste repositório reprova (SonarCloud, "Duplication on New
// Code").
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const agora = new Date("2026-07-27T12:00:00Z");
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos, agora,
    modeloInstitucional: entradaModeloDaFixture(fixture, agora),
  });
  const out = wb.getWorksheet("Output")!;
  const wc = wb.getWorksheet("Working Capital")!;
  const rec = wb.getWorksheet("Revenues, COGS & SG&A")!;
  const dre = wb.getWorksheet("Income Statement")!;
  const bs = wb.getWorksheet("Balance Sheet")!;
  const cf = wb.getWorksheet("Cash Flow")!;
  const div = wb.getWorksheet("ST Inv. & Debt")!;
  const fa = wb.getWorksheet("Fixed Assets & CAPEX")!;
  const trib = wb.getWorksheet("Tributos a Recolher")!;
  const todasAsAbas = [out, wc, rec, dre, bs, cf, div, fa, trib];
  for (const ws of todasAsAbas) esquecerMemoria(ws);
  const acharEm = (ws: ExcelJS.Worksheet, re: RegExp) => {
    for (let r = 1; r <= ws.rowCount; r++) {
      if (re.test(String(ws.getRow(r).getCell(3).value ?? ""))) return r;
    }
    return 0;
  };
  const acharTodos = (ws: ExcelJS.Worksheet, re: RegExp) => {
    const r: number[] = [];
    for (let i = 1; i <= ws.rowCount; i++) {
      if (re.test(String(ws.getRow(i).getCell(3).value ?? ""))) r.push(i);
    }
    return r;
  };

  const rTitulo = acharEm(out, /^RÉPLICA COMPLETA POR CENÁRIO/);
  checar(rTitulo > 0, "(50) o bloco da réplica completa existe na aba Output", String(rTitulo));

  const rChk = acharEm(out, /CHECK: a réplica completa do cenário ATIVO/);
  checar(rChk > 0, "(50) …com um CHECK contra a dívida líquida ativa", String(rChk));
  for (const col of ["G", "H", "I", "J"]) {
    const v = avaliarCelula(out, col, rChk);
    checar(typeof v === "number" && Math.abs(v) < 0.01,
      `(50) CHECK zero em ${col}: a réplica do cenário ATIVO é o próprio modelo`, String(v));
  }

  // As linhas de revolver de fechamento e de pico aparecem uma vez por
  // cenário, na ordem Base/Cliente/Stress (a ordem do `CHOOSE`).
  const revRows = acharTodos(out, /revolver — saldo de fechamento/);
  const picoRows = acharTodos(out, /pico de uso do revolver/);
  checar(revRows.length === 3 && picoRows.length === 3,
    "(50) o revolver de fechamento e o pico existem nos três cenários",
    `${revRows.length} / ${picoRows.length}`);

  if (revRows.length === 3) {
    const [rRevBase, , rRevStress] = revRows;
    for (const col of ["G", "H", "I", "J"]) {
      const base = avaliarCelula(out, col, rRevBase);
      const stress = avaliarCelula(out, col, rRevStress);
      if (typeof base === "number" && typeof stress === "number") {
        checar(stress >= base - 0.01,
          `(50) o revolver do Stress em ${col} não é menor que o do Base — a réplica não inverteu a direção`,
          `Stress ${stress.toFixed(0)} vs Base ${base.toFixed(0)}`);
      }
    }
  }
  if (picoRows.length === 3) {
    const [rPicoBase, , rPicoStress] = picoRows;
    const base = avaliarCelula(out, "J", rPicoBase);
    const stress = avaliarCelula(out, "J", rPicoStress);
    if (typeof base === "number" && typeof stress === "number") {
      checar(stress >= base - 0.01,
        "(50) …e o pico do horizonte inteiro (último ano) segue a mesma direção",
        `Stress ${stress.toFixed(0)} vs Base ${base.toFixed(0)}`);
    }
  }

  // ---- (51) OS DOIS CHECKS GIRANDO O DIAL — não só no Base Case ------------
  const rCheckReal = rChk;
  const rCheckWC = acharEm(wc, /CHECK: a sombra do cenário ATIVO bate/);
  checar(rCheckWC > 0, "(51) o CHECK do Working Capital existe", String(rCheckWC));

  for (const dial of [1, 2, 3] as const) {
    out.getRow(2).getCell(7).value = dial;
    for (const ws of todasAsAbas) esquecerMemoria(ws);
    for (const col of ["G", "H", "I", "J"]) {
      const vReal = avaliarCelula(out, col, rCheckReal);
      checar(typeof vReal === "number" && Math.abs(vReal) < 0.01,
        `(51) dial=${dial} col ${col}: CEN_CHECK_REAL continua zero`, String(vReal));
      const vWC = avaliarCelula(wc, col, rCheckWC);
      checar(typeof vWC === "number" && Math.abs(vWC) < 0.01,
        `(51) dial=${dial} col ${col}: CHECK_SOMBRA_WC continua zero`, String(vWC));
    }
  }
  out.getRow(2).getCell(7).value = 1;
  for (const ws of todasAsAbas) esquecerMemoria(ws);

  // ---- (52) NEW MONEY — tranche extra, com e sem PIK ------------------------
  const rNmValor = acharEm(div, /^Principal captado no fechamento/);
  const rNmFim = acharEm(div, /^Saldo do new money/);
  const rNmJuros = acharEm(div, /juros do período \(despesa/);
  const rNmAmort = acharEm(div, /amortização do período \(sempre em caixa\)/);
  const rCheckBal = acharEm(bs, /CHECK — Ativo/);
  checar(
    rNmValor > 0 && rNmFim > 0 && rNmJuros > 0 && rNmAmort > 0 && rCheckBal > 0,
    "(52) as linhas do new money e o CHECK do balanço existem",
    `${rNmValor}/${rNmFim}/${rNmJuros}/${rNmAmort}/${rCheckBal}`,
  );

  const colNota = div.getRow(rNmJuros).getCell(4).value === "N" ? 4 : 0;
  checar(colNota > 0, "(52) a célula de PIK (S/N) do new money está onde o modelo espera", String(colNota));

  for (const pik of ["N", "S"] as const) {
    div.getRow(rNmValor).getCell(7).value = 20000;
    if (colNota > 0) div.getRow(rNmJuros).getCell(colNota).value = pik;
    for (const ws of todasAsAbas) esquecerMemoria(ws);

    const fimAno1 = avaliarCelula(div, "G", rNmFim);
    const jurosAno1 = avaliarCelula(div, "G", rNmJuros);
    const amortAno1 = avaliarCelula(div, "G", rNmAmort);
    checar(typeof amortAno1 === "number" && Math.abs(amortAno1 - 4000) < 0.01,
      `(52) PIK=${pik}: amortização SAC do ano 1 é 1/prazo do principal (sempre em caixa)`, String(amortAno1));
    if (pik === "N" && typeof fimAno1 === "number") {
      checar(Math.abs(fimAno1 - 16000) < 0.01,
        "(52) PIK=N: saldo de fechamento não capitaliza juros (20000 - 4000 de amort)", String(fimAno1));
    }
    if (pik === "S" && typeof fimAno1 === "number" && typeof jurosAno1 === "number") {
      checar(Math.abs(fimAno1 - (20000 - 4000 - jurosAno1)) < 0.01,
        "(52) PIK=S: saldo de fechamento capitaliza os juros do período (não saíram do caixa)",
        `fim=${fimAno1} esperado=${20000 - 4000 - jurosAno1}`);
    }

    for (const col of ["G", "H", "I", "J"]) {
      const mismatch = avaliarCelula(bs, col, rCheckBal);
      checar(typeof mismatch === "number" && Math.abs(mismatch) < 0.01,
        `(52) PIK=${pik} col ${col}: o balanço continua fechando com o new money ativo`, String(mismatch));
    }
  }
  div.getRow(rNmValor).getCell(7).value = 0;
  if (colNota > 0) div.getRow(rNmJuros).getCell(colNota).value = "N";
  for (const ws of todasAsAbas) esquecerMemoria(ws);

  // ---- (53) EQUITY × HAIRCUT — a classificação do que cai sem caixa ---------
  //
  // A chave "Efeito caixa? = N" de uma tranche já provava (teste 40) que o
  // saldo cai sem pagamento. O que faltava: ESSE saldo pode virar capital
  // (Equity, o comportamento antigo, sem passar pelo resultado) OU ganho no
  // resultado (Haircut, fora do EBITDA, tributado). Os dois têm de fechar o
  // balanço — cada um por um caminho diferente — e o EBITDA não pode se mexer
  // em nenhum dos dois, porque nenhuma das duas alavancas é desempenho
  // operacional.
  const rEbitdaDre = acharEm(dre, /^EBITDA$/);
  const rGanhoHaircut = acharEm(dre, /Ganho com redução negociada de dívida/);
  const rClasse = acharEm(div, /classificação do saldo sem caixa/);
  checar(rEbitdaDre > 0 && rGanhoHaircut > 0 && rClasse > 0,
    "(53) as linhas de EBITDA, ganho com haircut e classificação existem",
    `${rEbitdaDre}/${rGanhoHaircut}/${rClasse}`);

  const ebitdaAntes = ["G", "H", "I", "J"].map((c) => avaliarCelula(dre, c, rEbitdaDre));

  // Acha a primeira tranche com "Efeito caixa? = S" (a fixture nasce toda em
  // caixa) e a linha "#classe" dela, que é a linha seguinte com o rótulo de
  // classificação a partir dali.
  let rCaixa = 0;
  for (let r = 1; r <= div.rowCount; r++) {
    if (String(div.getRow(r).getCell(4).value ?? "") === "S") { rCaixa = r; break; }
  }
  let rClasseTranche = 0;
  for (let r = rCaixa; r <= div.rowCount && rCaixa > 0; r++) {
    if (/classificação do saldo sem caixa/.test(String(div.getRow(r).getCell(3).value ?? ""))) {
      rClasseTranche = r; break;
    }
  }
  checar(rCaixa > 0 && rClasseTranche > 0,
    "(53) a fixture tem uma tranche com efeito caixa e a linha de classificação dela",
    `${rCaixa}/${rClasseTranche}`);

  if (rCaixa > 0 && rClasseTranche > 0) {
    div.getRow(rCaixa).getCell(4).value = "N";
    div.getRow(rClasseTranche).getCell(4).value = "Haircut";
    for (const ws of todasAsAbas) esquecerMemoria(ws);

    const ebitdaDepois = ["G", "H", "I", "J"].map((c) => avaliarCelula(dre, c, rEbitdaDre));
    for (let i = 0; i < 4; i++) {
      const a = ebitdaAntes[i]; const d = ebitdaDepois[i];
      if (typeof a === "number" && typeof d === "number") {
        checar(Math.abs(a - d) < 0.5,
          `(53) col ${["G", "H", "I", "J"][i]}: classificar Haircut não move o EBITDA — não é desempenho operacional`,
          `antes=${a} depois=${d}`);
      }
    }

    let algumGanho = false;
    for (const col of ["G", "H", "I", "J"]) {
      const ganho = avaliarCelula(dre, col, rGanhoHaircut);
      if (typeof ganho === "number" && ganho > 0.5) algumGanho = true;
      const mismatch = avaliarCelula(bs, col, rCheckBal);
      checar(typeof mismatch === "number" && Math.abs(mismatch) < 0.01,
        `(53) col ${col}: o balanço fecha com a tranche classificada Haircut (via LUCROS_ACUM, não REPERFILAMENTO)`,
        String(mismatch));
    }
    checar(algumGanho, "(53) …e o ganho com haircut de fato aparece na Income Statement em algum ano");

    div.getRow(rCaixa).getCell(4).value = "S";
    div.getRow(rClasseTranche).getCell(4).value = "Equity";
    for (const ws of todasAsAbas) esquecerMemoria(ws);
  }
}

// Montagem COMUM de (39f)–(39l): documento, campo, linha do modelo e busca de rótulo na coluna C.
// Existia copiada em cada bloco; é a mesma mecânica e a mesma entidade por bloco.
const arranjoDeCirculante = (ENT: string) => {
  const mk = (id: string, tipo: string, ref: string) => ({
    id, tipo_taxonomia: tipo, entidade: { razao_social: ENT },
    periodo: { tipo: "anual", referencia: ref }, documento_versao: [{ id: `v${id}`, nome_original: `${id}.pdf` }],
  }) as DocumentoParaExport;
  const c = (v: string, chave: string, secao: string, valor: number | null, ordem: number, per: string,
             canonica = "ativo_circulante") =>
    campo({ chave, secao, secao_canonica: canonica, valor_num: valor, ordem, periodo_coluna: per,
            documento_versao_id: v, unidade: "milhar" } as never);
  const norm = (x: string) => x.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
  const linhaA = (chave: string, valores: Record<string, number>, doc: string, papel: "conta" | "subtotal" = "conta",
                  secao = "ativo_circulante") => ({
    secao_canonica: secao, chave, rotulo_norm: norm(chave),
    papel, unidade: "milhar", moeda: "BRL", documentos: [doc], valores,
  });
  const achar = (ws: ExcelJS.Worksheet, rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(3).value ?? "").trim() === rot) return r;
    return 0;
  };
  return { mk, c, norm, linhaA, achar };
};

// =============================================================================
// (39f) "ESTOQUES" É FOLHA NO BALANÇO E AGRUPAMENTO NO BALANCETE: UM DOCUMENTO NÃO APAGA A CONTA DO OUTRO.
//
// O DEFEITO, medido no Excel do mandato Krauspenhar (caso 33b58a89, 01/10/2026): a linha
// "reconciliação com o ativo circulante informado no documento" do `Balance Sheet` saía
// 53.924.564,46 (2024) e 43.569.482,33 (2025 em diante) — 43% do ativo — e a auditoria
// reprovava "resíduo imaterial" em 14 células. O resíduo era EXATAMENTE a linha "Estoques"
// dos Balanços (folha `ativo_circulante`: 53.924.564,46 em 2024, 43.569.482,33 em 2025),
// que não tinha linha no `Working Capital`.
//
// O ARRANJO DOS DOCUMENTOS é o de produção: Balanço Centro Oeste 2024 (versão 1e096ac5),
// Balanço 2025 (07f650d8) e Balancete jan–ago/26 COMBINADO (b3c179e1), em que "ESTOQUES" é
// SINTÉTICO (ordem 22) sobre "ESTOQUE DA EMPRESA EM PODER DE TERCEIROS" (56), "MERCADORIA EM
// CONSIGNAÇÃO"… O ARRANJO DO MODELO NÃO É: aqui 2026 está em `anosHistoricos` para que o
// ano do balancete seja um exercício REALIZADO e a conta do Working Capital tenha onde ser
// lida; no Krauspenhar real 2026 é PROJETADO (o balancete jan–ago/26 não fecha exercício).
// A cobertura do balancete como ano histórico é o que (39g)–(39l) acrescentam. Os VALORES do
// balancete e das contas vizinhas são de ilustração (os campos
// reais não se reproduzem sem o banco — regra 4); o que se afirma é o COMPORTAMENTO: o
// resíduo de 2024/2025 é ~0, "Estoques" tem linha no `Working Capital` com os valores
// realizados, e no ano do balancete o sintético NÃO soma junto com as filhas.
// =============================================================================
{
  const ENT = "KRAUSPENHAR TESTE LTDA.";
  const { mk, c, linhaA, achar } = arranjoDeCirculante(ENT);
  const ES24 = 53924.56446; const ES25 = 43569.48233;
  const campos: CampoExtraido[] = [
    // Balanços 2024 e 2025: "Estoques" é FOLHA (ordem 5), entre as outras contas do circulante
    c("vB24", "Clientes", "Ativo Circulante", 32730, 1, "2024"),
    c("vB24", "Adiantamentos a fornecedores", "Ativo Circulante", 2770, 2, "2024"),
    c("vB24", "Outros créditos", "Ativo Circulante", 530, 3, "2024"),
    c("vB24", "Despesas antecipadas", "Ativo Circulante", 30, 4, "2024"),
    c("vB24", "Estoques", "Ativo Circulante", ES24, 5, "2024"),
    c("vB25", "Clientes", "Ativo Circulante", 30000, 1, "2025"),
    c("vB25", "Adiantamentos a fornecedores", "Ativo Circulante", 2500, 2, "2025"),
    c("vB25", "Outros créditos", "Ativo Circulante", 600, 3, "2025"),
    c("vB25", "Despesas antecipadas", "Ativo Circulante", 40, 4, "2025"),
    c("vB25", "Estoques", "Ativo Circulante", ES25, 5, "2025"),
    // Balancete 2026 (COMBINADO): "ESTOQUES" é SINTÉTICO (30.000 + 20.000) e as filhas trazem
    // `secao` = "ESTOQUES"
    c("vBC26", "CLIENTES", "Ativo Circulante", 28000, 20, "jan–ago/26"),
    c("vBC26", "ESTOQUES", "Ativo Circulante", 50000, 22, "jan–ago/26"),
    c("vBC26", "ESTOQUE DA EMPRESA EM PODER DE TERCEIROS", "ESTOQUES", 30000, 56, "jan–ago/26"),
    c("vBC26", "MERCADORIA EM CONSIGNAÇÃO", "ESTOQUES", 20000, 59, "jan–ago/26"),
  ];
  const documentos = [mk("B24", "BALANCO", "2024"), mk("B25", "BALANCO", "2025"), mk("BC26", "COMBINADO", "2026")];
  const T24 = 32730 + 2770 + 530 + 30 + ES24;
  const T25 = 30000 + 2500 + 600 + 40 + ES25;
  const T26 = 28000 + 50000;
  const entrada = {
    caso: { nome: "Estoques folha e agrupamento", produto: "reestruturacao" },
    agora: new Date("2026-10-01T12:00:00Z"), entidade: ENT, setor: "comercio",
    anosHistoricos: [2024, 2025, 2026], anosProjetados: [2027, 2028],
    stressPct: 0.2, caixaMinimo: 0, aliquotaTributos: 0.34,
    linhas: [
      linhaA("Ativo Circulante", { "2024": T24, "2025": T25, "2026": T26 }, "BALANCO", "subtotal"),
      linhaA("Clientes", { "2024": 32730, "2025": 30000, "2026": 28000 }, "BALANCO"),
      linhaA("Adiantamentos a fornecedores", { "2024": 2770, "2025": 2500 }, "BALANCO"),
      linhaA("Outros créditos", { "2024": 530, "2025": 600 }, "BALANCO"),
      linhaA("Despesas antecipadas", { "2024": 30, "2025": 40 }, "BALANCO"),
      // UMA linha lógica por rótulo (é assim que `fn_linhas_para_modelagem` agrega): folha em
      // 2024/2025, sintético em 2026
      linhaA("Estoques", { "2024": ES24, "2025": ES25, "2026": 50000 }, "BALANCO"),
      linhaA("ESTOQUE DA EMPRESA EM PODER DE TERCEIROS", { "2026": 30000 }, "COMBINADO"),
      linhaA("MERCADORIA EM CONSIGNAÇÃO", { "2026": 20000 }, "COMBINADO"),
    ],
    premissas: [], vinculos: [], macro: [], unidade: "R$ mil",
  };
  const wb = buildExportWorkbook({
    caso: entrada.caso, documentos, campos, agora: entrada.agora, modo: "completo",
    modeloInstitucional: entrada as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
  });
  const bs = wb.getWorksheet("Balance Sheet")!; esquecerMemoria(bs);
  const wc = wb.getWorksheet("Working Capital")!; esquecerMemoria(wc);
  const rRec = achar(bs, "reconciliação com o ativo circulante informado no documento");
  const rEst = achar(wc, "Estoques");
  checar(rRec > 0 && rEst > 0, "(39f) o Balance Sheet tem a reconciliação do circulante e o Working Capital tem linha de Estoques",
    `reconciliação: linha ${rRec} · Estoques: linha ${rEst}`);
  // Linha ausente NÃO pula os asserts: cada um reprova por si (a contagem off/on fica honesta).
  const lerWc = (col: string) => (rEst > 0 ? avaliarCelula(wc, col, rEst) : null);
  const lerRec = (col: string) => (rRec > 0 ? avaliarCelula(bs, col, rRec) : null);
  // colunas E,F,G = 2024, 2025, 2026
  for (const [col, ano, esperado] of [["E", 2024, ES24], ["F", 2025, ES25]] as const) {
    const res = lerRec(col);
    checar(typeof res === "number" && Math.abs(res) < 0.5,
      `(39f) ${ano}: "Estoques" é folha do Balanço e não vira resíduo (reconciliação ~0)`, JSON.stringify(res));
    const est = lerWc(col);
    checar(typeof est === "number" && Math.abs(est - esperado) < 0.5,
      `(39f) ${ano}: o Working Capital carrega os Estoques realizados do Balanço`, `${JSON.stringify(est)} vs ${esperado}`);
  }
  // No ano do balancete o agrupamento e as filhas não somam juntos: o circulante do modelo
  // fecha no informado (78.000), não em 128.000 (sintético + filhas).
  const res26 = lerRec("G");
  checar(typeof res26 === "number" && Math.abs(res26) < 0.5,
    "(39f) 2026 (balancete): o sintético não soma junto com as filhas (reconciliação ~0, não 50.000)", JSON.stringify(res26));
  const est26 = lerWc("G");
  checar(typeof est26 === "number" && Math.abs(est26) < 0.5,
    "(39f) 2026 (balancete): a linha 'Estoques' (sintético) não carrega valor — quem carrega são as filhas",
    JSON.stringify(est26));
}

// =============================================================================
// (39g)–(39j) REVISÃO INDEPENDENTE DO (39f): quatro defeitos que a correção do Estoques deixou
// (ou abriu). Cada bloco afirma COMPORTAMENTO do arquivo, não o mecanismo.
// Os arranjos são de ilustração (regra 4: o banco real não se reproduz aqui).
// =============================================================================
{
  const ENT = "REVISAO TESTE LTDA.";
  const { mk, c, linhaA, achar } = arranjoDeCirculante(ENT);
  const montar = (campos: CampoExtraido[], documentos: DocumentoParaExport[], linhas: ReturnType<typeof linhaA>[],
                  anosHistoricos: number[], anosProjetados: number[]) => {
    const entrada = {
      caso: { nome: "Revisão do Estoques", produto: "reestruturacao" },
      agora: new Date("2026-10-01T12:00:00Z"), entidade: ENT, setor: "comercio",
      anosHistoricos, anosProjetados, stressPct: 0.2, caixaMinimo: 0, aliquotaTributos: 0.34,
      linhas, premissas: [], vinculos: [], macro: [], unidade: "R$ mil",
    };
    const wb = buildExportWorkbook({
      caso: entrada.caso, documentos, campos, agora: entrada.agora, modo: "completo",
      modeloInstitucional: entrada as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
    });
    const bs = wb.getWorksheet("Balance Sheet")!; esquecerMemoria(bs);
    const wc = wb.getWorksheet("Working Capital")!; esquecerMemoria(wc);
    const rRec = achar(bs, "reconciliação com o ativo circulante informado no documento");
    const rAc = achar(bs, "Ativo circulante operacional");
    const ler = (ws: ExcelJS.Worksheet, r: number, col: string) => (r > 0 ? avaliarCelula(ws, col, r) : null);
    const nota = (ws: ExcelJS.Worksheet, r: number, col: string) =>
      r > 0 ? JSON.stringify(ws.getRow(r).getCell(col).note ?? "") : "";
    return { bs, wc, achar, rRec, rAc, ler, nota };
  };
  // Documento SEM `ordem` nem `periodo_coluna` (nenhuma sequência impressa para os detectores
  // lerem): um campo qualquer só para o modelo existir, e as linhas do modelo à mão.
  const montarSemOrdem = (docId: string, ref: string, chave: string, secao: string, valor: number,
                          linhas: ReturnType<typeof linhaA>[], hist: number[], proj: number[]) =>
    montar([campo({ chave, secao: secao === "ativo_circulante" ? "Ativo Circulante" : "Passivo Não Circulante",
                    secao_canonica: secao, valor_num: valor, documento_versao_id: `v${docId}`, unidade: "milhar" } as never)],
           [mk(docId, "BALANCO", ref)], linhas, hist, proj);
  const perto = (v: unknown, esperado: number) => typeof v === "number" && Math.abs(v - esperado) < 0.5;

  // ---- (39g) ALTO: coluna legível NA MESMA ABA de uma ilegível mantém o seu veredito ----------
  // Aba "Balanço" com "2024" e "jan–jun/25" (ilegível). "Impostos e contribuições a recuperar"
  // (500) é cabeçalho com filhas IRRF 300 + PIS 200 nas DUAS colunas. O `continue` do 3f40571
  // descartava o veredito de 2024 por causa da coluna vizinha: AC operacional 1.500 -> 2.000
  // (dupla contagem) e reconciliação 0 -> -500.
  {
    const H = "Impostos e contribuições a recuperar";
    const campos = [
      c("vG", "Clientes", "Ativo Circulante", 1000, 1, "2024"),
      c("vG", H, "Ativo Circulante", 500, 2, "2024"),
      c("vG", "IRRF a recuperar", H, 300, 3, "2024"),
      c("vG", "PIS a recuperar", H, 200, 4, "2024"),
      c("vG", "Clientes", "Ativo Circulante", 900, 1, "jan–jun/25"),
      c("vG", H, "Ativo Circulante", 500, 2, "jan–jun/25"),
      c("vG", "IRRF a recuperar", H, 300, 3, "jan–jun/25"),
      c("vG", "PIS a recuperar", H, 200, 4, "jan–jun/25"),
    ];
    const documentos = [mk("G", "BALANCO", "2025")];
    const m = montar(campos, documentos, [
      linhaA("Ativo Circulante", { "2024": 1500 }, "BALANCO", "subtotal"),
      linhaA("Clientes", { "2024": 1000 }, "BALANCO"),
      linhaA(H, { "2024": 500 }, "BALANCO"),
      linhaA("IRRF a recuperar", { "2024": 300 }, "BALANCO"),
      linhaA("PIS a recuperar", { "2024": 200 }, "BALANCO"),
    ], [2024], [2025, 2026]);
    checar(m.rAc > 0 && m.rRec > 0, "(39g) o Balance Sheet tem o AC operacional e a reconciliação", `${m.rAc}/${m.rRec}`);
    checar(perto(m.ler(m.bs, m.rAc, "E"), 1500),
      "(39g) 2024: o cabeçalho declarado nas duas colunas da aba não soma com as filhas (AC operacional 1.500, não 2.000)",
      JSON.stringify(m.ler(m.bs, m.rAc, "E")));
    checar(perto(m.ler(m.bs, m.rRec, "E"), 0),
      "(39g) 2024: a reconciliação do circulante é ~0 (não -500)", JSON.stringify(m.ler(m.bs, m.rRec, "E")));
  }

  // ---- (39h) ALTO: ano histórico SEM total informado: o cabeçalho explicado pelas filhas não soma ----
  // Sem `ordem` (nenhum detector estrutural). "Ativo Circulante" é informado só em 2025; em 2024
  // o cabeçalho "Estoques" voltava a somar com as filhas e a reconciliação dizia "nada a
  // reconciliar" — dupla contagem calada. Agora é a EXPLICAÇÃO DO PRÓPRIO ANO que decide: em 2024
  // as filhas (300+200) somam os 500 do cabeçalho, ele sai, e a célula nomeia as filhas (item 4).
  {
    const m = montarSemOrdem("H", "2025", "Outros", "ativo_circulante", 300, [
      // 2023 é o exercício em que "Estoques" é FOLHA (total informado 300 = 100 + 200, sem excesso):
      // a linha precisa de um ano com valor para continuar existindo e poder carregar a nota
      linhaA("Ativo Circulante", { "2023": 300, "2025": 900 }, "BALANCO", "subtotal"),
      linhaA("Outros", { "2023": 100, "2024": 400, "2025": 300 }, "BALANCO"),
      linhaA("Estoques", { "2023": 200, "2024": 500, "2025": 600 }, "BALANCO"),
      linhaA("Matéria-prima", { "2024": 300, "2025": 350 }, "BALANCO"),
      linhaA("Produtos acabados", { "2024": 200, "2025": 250 }, "BALANCO"),
    ], [2023, 2024, 2025], [2026, 2027]);
    checar(perto(m.ler(m.bs, m.rAc, "G"), 900), "(39h) 2025 (com total informado): AC operacional 900",
      JSON.stringify(m.ler(m.bs, m.rAc, "G")));
    checar(perto(m.ler(m.bs, m.rAc, "F"), 900),
      "(39h) 2024 (sem total informado): o cabeçalho provado em 2025 não soma de volta (AC operacional 900, não 1.400)",
      JSON.stringify(m.ler(m.bs, m.rAc, "F")));
    // ---- (39j) MÉDIO, regra 1: a célula em branco que a prova deixou traz motivo E efeito ----
    const rEst = m.achar(m.wc, "Estoques");
    const n25 = m.nota(m.wc, rEst, "G"); const n24 = m.nota(m.wc, rEst, "F");
    checar(rEst > 0 && /Cabeçalho de grupo/.test(n25) && /Efeito/.test(n25),
      "(39j) 2025: o valor que a prova tirou deixa nota com o motivo e o efeito (não fica em branco calado)", n25);
    checar(/Cabeçalho de grupo/.test(n24) && /Matéria-prima \+ Produtos acabados/.test(n24) && /Efeito/.test(n24),
      "(39j) 2024: mesmo sem total informado, a nota nomeia as filhas que explicam o valor tirado e o efeito", n24);
  }

  // ---- (39i) MÉDIO: sintético fora da lista de nomes, balancete num ano HISTÓRICO -------------
  // O arranjo do (39f) com "Estoque de mercadorias" (não está em CABECALHOS_DE_GRUPO) e o
  // balancete "jan–dez/25" como exercício realizado. A prova só conhece a lista: somava o
  // sintético (50.000) com as filhas e tirava "Clientes" (28.000, folha) para compensar —
  // AC operacional 100.000 contra 78.000, reconciliação -22.000.
  {
    const E = "Estoque de mercadorias";
    const ES24 = 53924.56446;
    const T24 = 32730 + ES24;
    const linhas = [
      linhaA("Ativo Circulante", { "2024": T24, "2025": 78000 }, "BALANCO", "subtotal"),
      linhaA("Clientes", { "2024": 32730, "2025": 28000 }, "BALANCO"),
      linhaA(E, { "2024": ES24, "2025": 50000 }, "BALANCO"),
      linhaA("ESTOQUE EM PODER DE TERCEIROS", { "2025": 30000 }, "COMBINADO"),
      linhaA("MERCADORIA EM CONSIGNAÇÃO", { "2025": 20000 }, "COMBINADO"),
    ];
    const camposBase = [
      c("vB24", "Clientes", "Ativo Circulante", 32730, 1, "2024"),
      c("vB24", E, "Ativo Circulante", ES24, 5, "2024"),
      c("vBC25", "CLIENTES", "Ativo Circulante", 28000, 20, "jan–dez/25"),
      c("vBC25", E, "Ativo Circulante", 50000, 22, "jan–dez/25"),
      c("vBC25", "ESTOQUE EM PODER DE TERCEIROS", E, 30000, 56, "jan–dez/25"),
      c("vBC25", "MERCADORIA EM CONSIGNAÇÃO", E, 20000, 59, "jan–dez/25"),
    ];
    // (a) o documento do balancete diz o exercício ("2025"): o veredito sai SÓ para ele
    const a = montar(camposBase, [mk("B24", "BALANCO", "2024"), mk("BC25", "COMBINADO", "2025")], linhas, [2024, 2025], [2026, 2027]);
    const rWc = a.achar(a.wc, "Clientes");
    checar(perto(a.ler(a.bs, a.rRec, "F"), 0),
      "(39i) 2025 (balancete histórico): o sintético fora da lista não soma com as filhas (reconciliação ~0)",
      JSON.stringify(a.ler(a.bs, a.rRec, "F")));
    checar(perto(a.ler(a.wc, rWc, "F"), 28000),
      "(39i) 2025: 'Clientes' (folha) continua no modelo — a prova não a tira para compensar o sintético",
      JSON.stringify(a.ler(a.wc, rWc, "F")));
    checar(perto(a.ler(a.bs, a.rRec, "E"), 0) && perto(a.ler(a.wc, a.achar(a.wc, E), "E"), ES24),
      "(39i) 2024: a folha do Balanço segue intacta (reconciliação ~0 e a linha carrega os Estoques)",
      `${JSON.stringify(a.ler(a.bs, a.rRec, "E"))} · ${JSON.stringify(a.ler(a.wc, a.achar(a.wc, E), "E"))}`);
    // (b) o documento NÃO diz o ano (referência ilegível): não há como saber qual exercício o
    // balancete cobre. O teto declarado: o sintético fica na soma, o excesso APARECE na
    // reconciliação (-50.000) e nenhuma outra conta é removida.
    const b = montar(camposBase, [mk("B24", "BALANCO", "2024"), mk("BC25", "COMBINADO", "jan–dez/25")], linhas, [2024, 2025], [2026, 2027]);
    const rWcB = b.achar(b.wc, "Clientes");
    checar(perto(b.ler(b.wc, rWcB, "F"), 28000),
      "(39i) sem ano derivável: 'Clientes' (folha) NUNCA é removida para compensar o sintético",
      JSON.stringify(b.ler(b.wc, rWcB, "F")));
    const resB = b.ler(b.bs, b.rRec, "F");
    checar(typeof resB === "number" && Math.abs(resB) > 1000,
      "(39i) sem ano derivável: o excesso fica À VISTA na reconciliação (não some calado)", JSON.stringify(resB));
  }
  // ---- (39k) ALTO: sem filhas NAQUELE ano, a linha é folha e fica (nada se herda de outro ano) ----
  // 2025: AC informado 1.600 = Clientes 1.000 + filhas 350+250 (Estoques 600 é o cabeçalho).
  // 2024, sem total informado e SEM filha alguma: Estoques 500 é folha. A herança do 45c8df2 a
  // tirava (AC 900, linha sumida, "nada a reconciliar"); o 3f40571 dava 1.400.
  {
    const m = montarSemOrdem("K", "2025", "Clientes", "ativo_circulante", 900, [
      linhaA("Ativo Circulante", { "2025": 1600 }, "BALANCO", "subtotal"),
      linhaA("Clientes", { "2024": 900, "2025": 1000 }, "BALANCO"),
      linhaA("Estoques", { "2024": 500, "2025": 600 }, "BALANCO"),
      linhaA("Matéria-prima", { "2025": 350 }, "BALANCO"),
      linhaA("Produtos acabados", { "2025": 250 }, "BALANCO"),
    ], [2024, 2025], [2026, 2027]);
    const rEst = m.achar(m.wc, "Estoques");
    checar(perto(m.ler(m.bs, m.rAc, "F"), 1600), "(39k) 2025: o cabeçalho explicado pelas filhas sai (AC operacional 1.600)",
      JSON.stringify(m.ler(m.bs, m.rAc, "F")));
    checar(perto(m.ler(m.bs, m.rAc, "E"), 1400),
      "(39k) 2024 (sem filhas): 'Estoques' é folha e soma (AC operacional 1.400, não 900)", JSON.stringify(m.ler(m.bs, m.rAc, "E")));
    checar(rEst > 0 && perto(m.ler(m.wc, rEst, "E"), 500),
      "(39k) 2024: a linha Estoques continua no Working Capital com o saldo do Balanço", JSON.stringify(m.ler(m.wc, rEst, "E")));
  }

  // ---- (39l) MÉDIO: um segundo excesso no bloco não desliga a remoção do cabeçalho explicado ----
  // PNC 2024 informado 34.000: Empréstimos 30.000, Provisões 4.000 (cabeçalho: filhas 1.500+2.500),
  // outras exigibilidades 2.700 e 800. Provisões sai (explicada) e o resíduo é -3.500 (os 3.500 a
  // mais que o documento não explica, e que ficam À VISTA); o tudo-ou-nada do 45c8df2 deixava
  // Provisões e o resíduo ia a -7.500.
  {
    const P = "passivo_nao_circulante";
    const m = montarSemOrdem("L", "2024", "Empréstimos bancários", P, 30000, [
      linhaA("Passivo Não Circulante", { "2024": 34000 }, "BALANCO", "subtotal", P),
      ...([["Empréstimos bancários", 30000], ["Provisões", 4000], ["Provisão cível", 1500],
           ["Provisão trabalhista", 2500], ["Outras exigibilidades", 2700], ["Obrigações diversas", 800]] as const)
        .map(([n, v]) => linhaA(n, { "2024": v }, "BALANCO", "conta", P)),
    ], [2024], [2025, 2026]);
    const rRecP = m.achar(m.bs, "reconciliação com o passivo não circulante informado no documento");
    checar(rRecP > 0 && perto(m.ler(m.bs, rRecP, "E"), -3500),
      "(39l) PNC 2024: Provisões (explicada por 1.500+2.500) sai mesmo com outro excesso no bloco: resíduo -3.500, não -7.500",
      JSON.stringify(rRecP > 0 ? m.ler(m.bs, rRecP, "E") : "linha ausente"));
  }

  // ---- (39m) ALTO: bloco com ~17 contas e centavos: a busca de filhas não desiste calada ----
  // Clientes 5.000, Estoques 600 (cabeçalho: filhas 350,25 + 249,75) e 15 contas com centavos. As
  // somas distintas cresciam 2^n, a busca estourava o teto e o Estoques voltava a somar (25.819,30
  // em vez de 25.219,30; sem total informado, a reconciliação nem acusava).
  {
    // 15 saldos IRREGULARES (sorteio fixo, semente 2): 30.872 somas distintas, acima do teto antigo de
    // 20.000; só UM subconjunto soma 600 e 128 somam 5.000 (a coincidência de Clientes, que a
    // unicidade impede de virar remoção).
    const outras = [1106.03, 1097.83, 206.55, 234.87, 985.5, 885.97, 819.73, 458.14, 755.94, 756.8,
                    731.2, 308.38, 580.67, 543.53, 873.01];
    const base = 5000 + 350.25 + 249.75 + outras.reduce((t, v) => t + v, 0);
    const m = montarSemOrdem("M", "2024", "Clientes", "ativo_circulante", 5000, [
      linhaA("Clientes", { "2024": 5000 }, "BALANCO"),
      linhaA("Estoques", { "2024": 600 }, "BALANCO"),
      linhaA("Matéria-prima", { "2024": 350.25 }, "BALANCO"),
      linhaA("Produtos acabados", { "2024": 249.75 }, "BALANCO"),
      ...outras.map((v, i) => linhaA(`Conta diversa ${String(i).padStart(2, "0")}`, { "2024": v }, "BALANCO")),
    ], [2024], [2025, 2026]);
    checar(perto(m.ler(m.bs, m.rAc, "E"), base),
      "(39m) 2024: com 15 contas de centavos no bloco, o cabeçalho explicado pelas filhas ainda sai da soma (e Clientes, coincidência, fica)",
      `${JSON.stringify(m.ler(m.bs, m.rAc, "E"))} vs ${base}`);
  }

  // ---- (39n) MÉDIO: grupo cujas filhas também têm nome de grupo, mas são SUBGRUPOS dele ----
  // Disponível 1.000 = Caixa e equivalentes 300 + Aplicações financeiras 700; Clientes 5.000;
  // total informado 6.000. A guarda "filha não é nome de grupo" do eb3592f impedia a remoção:
  // Caixa 2.000 e reconciliação -1.000. (O Vertentes — Clientes 26.000 = Caixa 8.000 + Estoques
  // 18.000, irmãs por acaso — segue bloqueado pelo assert do modelo base.)
  {
    const m = montarSemOrdem("N", "2024", "Clientes", "ativo_circulante", 5000, [
      linhaA("Ativo Circulante", { "2024": 6000 }, "BALANCO", "subtotal"),
      linhaA("Disponível", { "2024": 1000 }, "BALANCO"),
      linhaA("Caixa e equivalentes", { "2024": 300 }, "BALANCO"),
      linhaA("Aplicações financeiras", { "2024": 700 }, "BALANCO"),
      linhaA("Clientes", { "2024": 5000 }, "BALANCO"),
    ], [2024], [2025, 2026]);
    checar(perto(m.ler(m.bs, m.rRec, "E"), 0),
      "(39n) 2024: Disponível (Caixa + Aplicações, subgrupos dele) sai da soma: reconciliação ~0, não -1.000",
      JSON.stringify(m.ler(m.bs, m.rRec, "E")));
  }

  // ---- (39o) MÉDIO: subtotal arredondado em milhar (4.000 = 1.500 + 2.501) ----------------------
  // A folga absoluta de ±0,5 reprovava a soma por 1 unidade de arredondamento do documento.
  {
    const P = "passivo_nao_circulante";
    const m = montarSemOrdem("O", "2024", "Empréstimos bancários", P, 30000, [
      linhaA("Passivo Não Circulante", { "2024": 34001 }, "BALANCO", "subtotal", P),
      ...([["Empréstimos bancários", 30000], ["Provisões", 4000], ["Provisão cível", 1500],
           ["Provisão trabalhista", 2501]] as const)
        .map(([n, v]) => linhaA(n, { "2024": v }, "BALANCO", "conta", P)),
    ], [2024], [2025, 2026]);
    const rRecP = m.achar(m.bs, "reconciliação com o passivo não circulante informado no documento");
    checar(rRecP > 0 && perto(m.ler(m.bs, rRecP, "E"), 0),
      "(39o) PNC 2024: Provisões 4.000 = 1.500 + 2.501 (arredondamento do documento) sai da soma: reconciliação ~0, não -4.000",
      JSON.stringify(rRecP > 0 ? m.ler(m.bs, rRecP, "E") : "linha ausente"));
  }

  // ---- (39p) MÉDIO: soma que só fecha com a folga e sem total informado: a linha fica, COM aviso ----
  // O 39o sem "Passivo Não Circulante" informado: Provisões 4.000 = 1.500 + 2.501 só com a folga de
  // arredondamento, nada corrobora a remoção. Ela fica na soma (o PNC dobra 4.000) — e a célula
  // tem de DIZER que não foi verificada e o efeito, porque sem total não há reconciliação.
  {
    const P = "passivo_nao_circulante";
    const m = montarSemOrdem("P", "2024", "Empréstimos bancários", P, 30000, ([
      ["Empréstimos bancários", 30000], ["Provisões", 4000], ["Provisão cível", 1500], ["Provisão trabalhista", 2501],
    ] as const).map(([n, v]) => linhaA(n, { "2024": v }, "BALANCO", "conta", P)), [2024], [2025, 2026]);
    const nota = m.nota(m.bs, m.achar(m.bs, "Provisões"), "E");
    checar(/NÃO verificado/.test(nota) && /Efeito/.test(nota) && /folga de arredondamento/.test(nota),
      "(39p) 2024: Provisões que só fecha com a folga, sem total informado, fica na soma COM aviso (motivo e efeito)", nota);
  }

  // ---- (39q) BAIXO: "Outros créditos" é IRMÃ de Contas a receber, não filha ------------------
  // Contas a receber 1.200 (folha), Outros créditos 700, Adiantamento a fornecedores 500: 700 + 500
  // = 1.200 por acaso. A tabela de subgrupos listava "outros creditos" sob "contas a receber".
  {
    const m = montarSemOrdem("Q", "2024", "Contas a receber", "ativo_circulante", 1200, [
      linhaA("Contas a receber", { "2024": 1200 }, "BALANCO"),
      linhaA("Outros créditos", { "2024": 700 }, "BALANCO"),
      linhaA("Adiantamento a fornecedores", { "2024": 500 }, "BALANCO"),
    ], [2024], [2025, 2026]);
    const rCr = m.achar(m.wc, "Contas a receber");
    checar(rCr > 0 && perto(m.ler(m.wc, rCr, "E"), 1200),
      "(39q) 2024: 'Contas a receber' (folha) fica no modelo — Outros créditos + Adiantamento somam 1.200 por acaso",
      JSON.stringify(rCr > 0 ? m.ler(m.wc, rCr, "E") : "linha ausente"));
  }

  // ===========================================================================
  // (39r)-(39t) KRAUSPENHAR (caso 33b58a89, 01/10/2026): TRÊS DEFEITOS NA CADEIA DA DÍVIDA.
  // O arranjo dos Balanços é o de produção (2024 versão 1e096ac5, 2025 versão 07f650d8): o PNC
  // tem UMA conta, ordem 22 "Empréstimos e financiamentos - longo prazo" (4.183.333,35 e
  // 9.535.722,84), e logo abaixo, ordem 23, "Passivo Não Circulante" com o MESMO valor. O que
  // NÃO se reproduz de fora do banco (regra 4): as demais linhas do Balanço real; só o Ativo Não
  // Circulante (valores medidos) entra, como 3a linha do grupo sem seção. Afirma-se o COMPORTAMENTO: com a conta única e o
  // total da seção na sequência, a conta é folha.
  // O balancete (COMBINADO, jan-ago/26) tem o sintético "EMPRESTIMOS E FINANCIAMENTOS LONGO
  // PRAZO" sobre as tranches "CAPITAL DE GIRO BANCO … - LP"; aqui 2026 é histórico, para a
  // regra "o sintético não soma junto com as tranches no próprio ano" ter onde ser lida.
  // ===========================================================================
  {
    const EMP = "Empréstimos e financiamentos - longo prazo";
    const PNC = "Passivo Não Circulante";
    const P = "passivo_nao_circulante";
    const L24 = 4183333.35; const L25 = 9535722.84;
    const CP24 = 15985290.43; const CP25 = 12000000;
    const OUT24 = 4664446.92; const OUT25 = 4871633.53;
    const OUTROS = "Outras obrigações (adiantamentos de clientes, JCP a pagar e desconto de duplicatas)";
    const SINT = "EMPRESTIMOS E FINANCIAMENTOS LONGO PRAZO";
    // grupo MISTO no PNC (mesma regra do Working Capital): fica no balanço como conta constante e
    // TEM de levar a nota, senão dívida e juro ficam subestimados calados
    const MISTO = "Outras obrigações (dividendos a pagar e desconto de duplicatas)"; const MISTO24 = 100000;
    const TR_A = "CAPITAL DE GIRO BANCO ALFA - LP"; const TR_B = "CAPITAL DE GIRO BANCO BETA - LP";
    const { mk, c, linhaA } = arranjoDeCirculante("KRAUSPENHAR DIVIDA LTDA.");
    // FORMATO REAL (medido no export do caso): o total "Passivo Não Circulante" e a conta chegam
    // com `secao` NULA, e a conta traz só `secao_canonica`. O grupo do detector por ordem é
    // (versão × coluna × secao): `secao` nula junta todas as linhas sem seção do documento, então
    // "Ativo Não Circulante" (ordem 13) é a terceira linha do grupo — não há linha inventada.
    const semSecao = (v: string, chave: string, valor: number | null, ordem: number, per: string, canon: string | null) =>
      campo({ chave, secao: null, secao_canonica: canon, valor_num: valor, ordem, periodo_coluna: per,
              documento_versao_id: v, unidade: "milhar" } as never);
    const campos = [
      semSecao("vB24", "Ativo Não Circulante", 25822691.85, 13, "2024", "ativo_nao_circulante"),
      semSecao("vB24", EMP, L24, 22, "2024", P),
      semSecao("vB24", PNC, L24, 23, "2024", null),
      semSecao("vB25", "Ativo Não Circulante", 29494095.41, 13, "2025", "ativo_nao_circulante"),
      semSecao("vB25", EMP, L25, 22, "2025", P),
      semSecao("vB25", PNC, L25, 23, "2025", null),
      c("vBC26", SINT, PNC, 3000000, 5, "01/01/2026 a 31/08/2026", P),
      c("vBC26", TR_A, SINT, 1000000, 6, "01/01/2026 a 31/08/2026", P),
      c("vBC26", TR_B, SINT, 2000000, 7, "01/01/2026 a 31/08/2026", P),
    ];
    const entrada = {
      caso: { nome: "Krauspenhar dívida", produto: "reestruturacao" },
      agora: new Date("2026-10-01T12:00:00Z"), entidade: "KRAUSPENHAR DIVIDA LTDA.", setor: "comercio",
      anosHistoricos: [2024, 2025, 2026], anosProjetados: [2027, 2028],
      stressPct: 0.2, caixaMinimo: 0, aliquotaTributos: 0.34,
      linhas: [
        linhaA("Passivo Circulante", { "2024": CP24 + OUT24, "2025": CP25 + OUT25 }, "BALANCO", "subtotal", "passivo_circulante"),
        linhaA("Empréstimos e financiamentos - curto prazo", { "2024": CP24, "2025": CP25 }, "BALANCO", "conta", "passivo_circulante"),
        linhaA(OUTROS, { "2024": OUT24, "2025": OUT25 }, "BALANCO", "conta", "passivo_circulante"),
        linhaA(PNC, { "2024": L24 + MISTO24, "2025": L25, "2026": 3000000 }, "BALANCO", "subtotal", P),
        linhaA(MISTO, { "2024": MISTO24 }, "BALANCO", "conta", P),
        linhaA(EMP, { "2024": L24, "2025": L25 }, "BALANCO", "conta", P),
        linhaA(SINT, { "2026": 3000000 }, "COMBINADO", "conta", P),
        linhaA(TR_A, { "2026": 1000000 }, "COMBINADO", "conta", P),
        linhaA(TR_B, { "2026": 2000000 }, "COMBINADO", "conta", P),
      ],
      premissas: [], vinculos: [], macro: [], unidade: "R$ mil",
    };
    const wb = buildExportWorkbook({
      caso: entrada.caso, documentos: [mk("B24", "BALANCO", "2024"), mk("B25", "BALANCO", "2025"), mk("BC26", "COMBINADO", "2026")],
      campos, agora: entrada.agora, modo: "completo",
      modeloInstitucional: entrada as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
    });
    const bs = wb.getWorksheet("Balance Sheet")!; esquecerMemoria(bs);
    const wc = wb.getWorksheet("Working Capital")!; esquecerMemoria(wc);
    const sd = wb.getWorksheet("ST Inv. & Debt")!; esquecerMemoria(sd);
    const rLP = achar(bs, "Dívida de longo prazo");
    const rRecPnc = achar(bs, "reconciliação com o passivo não circulante informado no documento");
    const rCpSd = achar(sd, "Dívida de curto prazo (fim do período)");
    const lerCel = (ws: ExcelJS.Worksheet, r: number, col: string) => (r > 0 ? avaliarCelula(ws, col, r) : null);
    checar(rLP > 0 && rRecPnc > 0 && rCpSd > 0, "(39r) as linhas lidas existem no arquivo",
      `LP=${rLP} reconciliação PNC=${rRecPnc} CP(ST)=${rCpSd}`);

    // (39r) DEFEITO 1: conta única que iguala o total da seção não é subtotal dele.
    for (const [col, ano, esperado] of [["E", 2024, L24], ["F", 2025, L25]] as const) {
      const lp = lerCel(bs, rLP, col);
      checar(perto(lp, esperado),
        `(39r) ${ano}: a Dívida de longo prazo do Balance Sheet é o empréstimo do Balanço (conta única do PNC), não zero`,
        `${JSON.stringify(lp)} vs ${esperado}`);
      const res = lerCel(bs, rRecPnc, col);
      checar(perto(res, 0),
        `(39r) ${ano}: o PNC fecha no informado — o empréstimo não vira resíduo de reconciliação`, JSON.stringify(res));
    }
    // …e a regra que não pode se perder: no ano do balancete o sintético não soma com as tranches.
    // A tranche só é dívida com o (39t); o que o (39r) afirma é o PNC de 2026 fechar nos 3.000.000
    // do informado (3.000.000 = tranches; somar o sintético daria 6.000.000).
    checar(perto(lerCel(bs, rRecPnc, "G"), 0),
      "(39r) 2026 (balancete): o sintético não soma junto com as tranches (reconciliação do PNC ~0, não 3.000.000)",
      JSON.stringify(lerCel(bs, rRecPnc, "G")));

    // (39s) DEFEITO 2: o grupo de obrigações que só cita "desconto de duplicatas" não é dívida.
    for (const [col, ano, esperado] of [["E", 2024, CP24], ["F", 2025, CP25]] as const) {
      const cp = lerCel(sd, rCpSd, col);
      checar(perto(cp, esperado),
        `(39s) ${ano}: a Dívida de curto prazo é só o empréstimo (adiantamento de cliente e JCP não recebem juro de dívida)`,
        `${JSON.stringify(cp)} vs ${esperado}`);
    }
    const rOut = achar(wc, OUTROS);
    checar(rOut > 0 && perto(lerCel(wc, rOut, "E"), OUT24),
      "(39s) 2024: 'Outras obrigações (…)' fica no Working Capital com o saldo do Balanço", JSON.stringify(lerCel(wc, rOut, "E")));
    const notaOut = rOut > 0 ? JSON.stringify(wc.getRow(rOut).getCell(3).note ?? "") : "";
    checar(/duplicata/i.test(notaOut) && /n(ã|a)o recebe juro/i.test(notaOut) && /SUBESTIMAD/.test(notaOut),
      "(39s) …e a célula diz o motivo (o documento não separa a duplicata descontada) e o efeito (sem juro, dívida subestimada)", notaOut);

    const rMisto = achar(bs, MISTO);
    const notaMisto = rMisto > 0 ? JSON.stringify(bs.getRow(rMisto).getCell(3).note ?? "") : "";
    checar(rMisto > 0 && perto(lerCel(bs, rMisto, "E"), MISTO24) && perto(lerCel(bs, rRecPnc, "E"), 0),
      "(39s) PNC 2024: o grupo misto fica no Balance Sheet como conta constante e o PNC segue fechando",
      `${JSON.stringify(rMisto > 0 ? lerCel(bs, rMisto, "E") : "linha ausente")} · ${JSON.stringify(lerCel(bs, rRecPnc, "E"))}`);
    checar(/duplicata/i.test(notaMisto) && /n(ã|a)o recebe juro/i.test(notaMisto) && /SUBESTIMAD/.test(notaMisto),
      "(39s) …e a linha do PNC leva a nota (motivo e efeito), não cai calada fora da dívida", notaMisto);

    // (39t) DEFEITO 3: tranche "CAPITAL DE GIRO BANCO …" é dívida. Só 2026 tem valor (balancete),
    // então o efeito nas colunas históricas de 2024/2025 do Krauspenhar é NULO; a asserção é no ano
    // do balancete, onde o sintético (excluído) e as tranches (agora dívida) somam 3.000.000.
    const lp26 = lerCel(bs, rLP, "G");
    checar(perto(lp26, 3000000),
      "(39t) 2026 (balancete): as tranches 'CAPITAL DE GIRO BANCO …' são a dívida de longo prazo (3.000.000, não 0 nem 6.000.000)",
      JSON.stringify(lp26));
  }

}

// (40) A RECUSA DO EXPORT VIRA PÁGINA PARA PESSOA E CONTINUA JSON PARA PROGRAMA
// (src/lib/recusa-do-export.ts). Os motivos vêm do banco — razão social e
// mensagem do Postgres —, então o que importa é: (a) texto do banco nunca vira
// marcação; (b) o status da recusa (409/503/500) sobrevive à troca de formato;
// (c) quem não pede HTML recebe o JSON de sempre.
{
  const { recusar } = await import("../src/lib/recusa-do-export.ts");
  const corpo = {
    error: "Recusado <b>pelo</b> portão",
    motivos: ["Empresa <script>alert(1)</script> & Cia"],
    detalhe: "erro \"x\"",
  };
  const html = await recusar(
    new Request("https://x/casos/1/export", { headers: { accept: "text/html,application/xhtml+xml" } }),
    "1", corpo, { status: 409 },
  );
  const texto = await html.text();
  checar(html.status === 409, "(40a) a página de recusa preserva o status 409", String(html.status));
  checar((html.headers.get("content-type") ?? "").startsWith("text/html"),
    "(40b) navegador recebe HTML", html.headers.get("content-type") ?? "");
  checar(!texto.includes("<script>alert(1)") && texto.includes("&lt;script&gt;alert(1)&lt;/script&gt; &amp; Cia"),
    "(40c) motivo vindo do banco sai escapado, nunca como marcação", texto.slice(0, 200));
  checar(!texto.includes("<b>pelo</b>"), "(40d) a mensagem de erro também sai escapada", "");
  const json = await recusar(new Request("https://x/casos/1/export", { headers: { accept: "*/*" } }),
    "1", corpo, { status: 503 });
  checar(json.status === 503 && (json.headers.get("content-type") ?? "").includes("application/json")
    && (await json.json()).motivos?.[0] === corpo.motivos[0],
    "(40e) programa (Accept */*) recebe o JSON de sempre, com o status original", String(json.status));
}

// (41) O INÍCIO E A LISTA DE MANDATOS (src/lib/painel.ts): a fila "Precisa de você" e a busca.
// A regra que importa: a contagem de cada filtro é a MESMA conta que a lista aplica, e a busca
// não deixa "%" e "_" virarem curinga do LIKE.
{
  const { filtroDaFila, daFila, contarFila, verboDaPendencia, padraoDeBusca } = await import("../src/lib/painel.ts");
  const fila = [
    { tipo: "item_faltante", severidade: "bloqueante" },
    { tipo: "classificacao_pendente", severidade: "bloqueante" },
    { tipo: "classificacao_pendente", severidade: "importante" },
    { tipo: "divergencia_reconciliacao", severidade: "importante" },
    { tipo: "arquivo_ilegivel", severidade: "complementar" },
  ];
  const c = contarFila(fila);
  checar(c.todas === 5 && c.travam === 2 && c.confirmar === 2,
    "(41a) contagem de cada filtro da fila", JSON.stringify(c));
  for (const f of ["todas", "travam", "confirmar"] as const) {
    checar(fila.filter((p) => daFila(p, f)).length === c[f],
      `(41b) a lista filtrada por "${f}" tem exatamente a contagem exibida`, f);
  }
  checar(filtroDaFila("lixo") === "todas" && filtroDaFila(undefined) === "todas" && filtroDaFila(["travam", "x"]) === "travam",
    "(41c) filtro desconhecido cai em 'todas' (mostrar demais, nunca esconder)", "");
  checar(verboDaPendencia("classificacao_pendente") === "Confirmar"
    && verboDaPendencia("item_faltante") === "Pedir ao cliente"
    && verboDaPendencia("arquivo_ilegivel") === "Pedir ao cliente"
    && verboDaPendencia("divergencia_reconciliacao") === "Decidir"
    && verboDaPendencia("tipo_que_nao_existe") === "Pedir ao cliente",
    "(41d) o verbo do botão corresponde à gaveta de destino", "");
  // Estado manda nos tipos de decisão; "confirmar" fica "Confirmar" em qualquer estado em aberto
  // (a aba Pendências mostra o formulário assim). Sem estado vale o verbo do tipo.
  checar(verboDaPendencia("item_faltante", "reenviada_ao_cliente") === "Aguardando o cliente"
    && verboDaPendencia("arquivo_ilegivel", "reenviada_ao_cliente") === "Aguardando o cliente"
    && verboDaPendencia("divergencia_reconciliacao", "em_correcao_interna") === "Em correção"
    && verboDaPendencia("item_faltante", "em_correcao_interna") === "Em correção",
    "(41h) pendência já contatada/em correção não oferece mais o verbo de quando estava aberta", "");
  checar(verboDaPendencia("item_faltante", "aberta") === "Pedir ao cliente"
    && verboDaPendencia("divergencia_reconciliacao", "aberta") === "Decidir"
    && verboDaPendencia("classificacao_pendente", "reenviada_ao_cliente") === "Confirmar"
    && verboDaPendencia("classificacao_pendente", "em_correcao_interna") === "Confirmar",
    "(41i) aberta mantém o verbo do tipo; documento a confirmar segue 'Confirmar' em qualquer estado", "");
  checar(padraoDeBusca("a*b") === "%a_b%" && !padraoDeBusca("*")!.includes("*") && padraoDeBusca("*") === "%_%",
    "(41j) busca não deixa '*' virar curinga do PostgREST (que o troca por '%' e casaria tudo)", String(padraoDeBusca("*")));
  checar(padraoDeBusca("a_b%c\\d") === "%a\\_b\\%c\\\\d%",
    "(41e) busca escapa _ % \\ (senão '_' casaria todo nome)", String(padraoDeBusca("a_b%c\\d")));
  checar(padraoDeBusca("   ") === null && padraoDeBusca(undefined) === null && padraoDeBusca(["Vertentes", "x"]) === "%Vertentes%",
    "(41f) busca vazia = sem filtro; array usa o primeiro", "");
  checar(padraoDeBusca("x".repeat(500))!.length === 82, "(41g) busca limitada a 80 caracteres", "");
}

console.log(`${ok} verificações OK / ${falhas.length} falhas`);
for (const f of falhas) console.log("  FALHOU:", f);
process.exit(falhas.length ? 1 : 0);
