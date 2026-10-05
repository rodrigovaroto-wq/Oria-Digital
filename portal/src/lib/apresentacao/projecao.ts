// O RESULTADO FUTURO DA APRESENTAÇÃO — lido da projeção que o modelo institucional JÁ calcula.
//
// Não há segunda projeção aqui: o .xlsx do modo completo projeta receita, EBITDA e EBIT por fórmula
// a partir das premissas da Modelagem, e este arquivo LÊ essas células com o avaliador que os
// verificadores já usam (`avaliar-formula.ts`). Duas projeções divergiriam sem erro nenhum.
//
// AS DUAS GUARDAS QUE TORNAM ISTO PUBLICÁVEL.
//  1. COBERTURA: o modelo NÃO projeta conta sem premissa vinculada — ela vale zero no futuro. A
//     projeção só sai com COBERTURA POR VALOR ≥ 95%: a fração do valor de receita, deduções, custos e
//     despesas do último exercício com premissa vinculada (por contagem de linhas, uma conta grande
//     sem premissa se esconde atrás de muitas pequenas).
//  2. SALTO DE MARGEM (no deck, `SALTO_DE_MARGEM_PP`): cobertura completa não prova premissa
//     coerente. Medido no book Vertentes (05/10/2026), 100% vinculado: "custo variável 60% da
//     receita" aplicado a custos E despesas leva a margem EBITDA de 0,9% (2025) a 48,6% (2026). O
//     modelo faz o que a premissa diz; o deck não pode publicar isso como manchete sem dizer o salto.
import type ExcelJS from "exceljs";
import { avaliarCelula } from "../avaliar-formula";
import { blocoDaLinha, type EntradaModeloInstitucional } from "../modelo-institucional";

export const COBERTURA_MINIMA = 0.95;
/** Variação da margem EBITDA (p.p.) do último realizado para o 1º ano projetado que vira alerta. */
export const SALTO_DE_MARGEM_PP = 10;

export interface ProjecaoDoModelo {
  anos: number[];
  receita: (number | null)[];
  ebitda: (number | null)[];
  ebit: (number | null)[];
  /** fração (0–1) do valor de receita/custos/despesas do último exercício com premissa vinculada */
  cobertura: number | null;
}

/** Ano de uma data serial do Excel (o cabeçalho do eixo do tempo do modelo é data). */
const anoDoSerial = (v: unknown): number | null =>
  typeof v === "number" && v > 20000 && v < 80000 ? new Date(Date.UTC(1899, 11, 30) + v * 86_400_000).getUTCFullYear() : null;

export function coberturaPorValor(ent: EntradaModeloInstitucional): number | null {
  const ultimo = Math.max(...ent.anosHistoricos);
  const comPremissa = new Set(ent.vinculos.filter((v) => v.premissa_codigo).map((v) => v.rotulo_norm));
  let total = 0;
  let coberto = 0;
  for (const l of ent.linhas) {
    if (l.papel !== "conta" || !["receita", "deducao", "custo", "sga"].includes(blocoDaLinha(l))) continue;
    const v = Math.abs(l.valores[String(ultimo)] ?? 0);
    total += v;
    if (comPremissa.has(l.rotulo_norm)) coberto += v;
  }
  return total > 0 ? coberto / total : null;
}

/** Lê a DRE projetada da aba "Income Statement"; `null` se o modelo não foi montado. */
export function projecaoDoModelo(workbook: ExcelJS.Workbook, ent: EntradaModeloInstitucional): ProjecaoDoModelo | null {
  const ws = workbook.getWorksheet("Income Statement");
  if (!ws) return null;
  const ultimoHist = Math.max(...ent.anosHistoricos);
  const colunas: Array<{ col: string; ano: number }> = [];
  for (let c = 5; c < 40; c++) {
    const col = ws.getColumn(c).letter;
    const ano = anoDoSerial(avaliarCelula(ws, col, 3));
    if (ano === null) break;
    if (ano > ultimoHist) colunas.push({ col, ano });
  }
  const linhaDe = (rotulo: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(3).value ?? "").trim() === rotulo) return r;
    return null;
  };
  const serie = (rotulo: string) => {
    const r = linhaDe(rotulo);
    return colunas.map(({ col }) => {
      if (r === null) return null;
      const v = avaliarCelula(ws, col, r);
      return typeof v === "number" && Number.isFinite(v) ? v : null;
    });
  };
  if (colunas.length === 0) return null;
  return { anos: colunas.map((c) => c.ano), receita: serie("NET REVENUES"), ebitda: serie("EBITDA"), ebit: serie("EBIT"),
    cobertura: coberturaPorValor(ent) };
}
