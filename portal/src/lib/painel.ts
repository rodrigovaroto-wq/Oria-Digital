import { categoriaDaPendencia, type CategoriaDePendencia } from "./pendencia";

// REGRAS PURAS DO INÍCIO E DA LISTA DE MANDATOS. Moram aqui (e não dentro da
// página) para o `verificar-export.mts` conseguir afirmá-las: uma regra de fila
// que só existe dentro de um componente de servidor não tem como reprovar.

/** Os filtros da fila "Precisa de você". `chave` é o valor do `?fila=` da URL. */
export const FILTROS_DA_FILA = [
  { chave: "todas", rotulo: "Todas" },
  { chave: "travam", rotulo: "Travam a aprovação" },
  { chave: "confirmar", rotulo: "Confirmar documento" },
] as const;
export type FiltroDaFila = (typeof FILTROS_DA_FILA)[number]["chave"];

/** Valor desconhecido na URL cai em "todas": o erro que se paga é mostrar demais, nunca esconder. */
export function filtroDaFila(bruto: string | string[] | undefined): FiltroDaFila {
  const v = Array.isArray(bruto) ? bruto[0] : bruto;
  return FILTROS_DA_FILA.find((f) => f.chave === v)?.chave ?? "todas";
}

type ItemDaFila = { tipo: string; severidade: string };

export function daFila(p: ItemDaFila, filtro: FiltroDaFila): boolean {
  if (filtro === "travam") return p.severidade === "bloqueante";
  if (filtro === "confirmar") return categoriaDaPendencia(p.tipo) === "confirmar";
  return true;
}

/** Contagem de cada filtro sobre o MESMO conjunto que a lista mostra. */
export function contarFila(itens: readonly ItemDaFila[]): Record<FiltroDaFila, number> {
  return {
    todas: itens.length,
    travam: itens.filter((p) => daFila(p, "travam")).length,
    confirmar: itens.filter((p) => daFila(p, "confirmar")).length,
  };
}

/**
 * O verbo do botão da fila: descreve o que a pessoa faz ao chegar na gaveta do
 * destino (`/pendencias?filtro=<categoria>`). `confirmar` abre o formulário de
 * classificação; `faltando`/`ilegivel` pedem o arquivo de volta; o resto é decisão.
 */
export function verboDaPendencia(tipo: string): string {
  const cat: CategoriaDePendencia = categoriaDaPendencia(tipo);
  if (cat === "confirmar") return "Confirmar";
  if (cat === "faltando" || cat === "ilegivel") return "Pedir ao cliente";
  return "Decidir";
}

/**
 * Termo digitado na busca → padrão de `ilike`. `%`, `_` e `\` são curingas/escape
 * do LIKE: sem escapar, buscar "_" casaria todo nome. Vazio devolve null (sem filtro).
 */
export function padraoDeBusca(bruto: string | string[] | undefined): string | null {
  const v = (Array.isArray(bruto) ? bruto[0] : bruto)?.trim().slice(0, 80);
  if (!v) return null;
  return `%${v.replace(/[\\%_]/g, "\\$&")}%`;
}
