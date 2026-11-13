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

/**
 * O texto que diz QUANTAS pendências travam um mandato. A fila ("8 bloqueiam") e o chip da lista de mandatos
 * usam esta função e nenhuma outra: o chip dizia "8 pendências" para o número de BLOQUEANTES, enquanto a fila
 * do mesmo mandato dizia 418 pendências (8 bloqueiam) — 418 contra 8 na mesma tela, medido em 13/11/2026.
 */
export function rotuloDeBloqueantes(n: number): string {
  return `${n.toLocaleString("pt-BR")} ${n === 1 ? "bloqueia" : "bloqueiam"}`;
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
 * classificação, que vale em QUALQUER estado em aberto (a aba Pendências o mostra
 * assim, ver `ehConfirmar` lá); `faltando`/`ilegivel` pedem o arquivo de volta; o
 * resto é decisão.
 *
 * O ESTADO MANDA nos tipos de decisão: depois de "Contatar o cliente" a pendência
 * fica `reenviada_ao_cliente`, e o botão seguir dizendo "Pedir ao cliente" afirma
 * que nada foi feito. Sem `estado` (chamador que não o lê) vale o verbo do tipo.
 */
export function verboDaPendencia(tipo: string, estado?: string | null): string {
  const cat: CategoriaDePendencia = categoriaDaPendencia(tipo);
  if (cat === "confirmar") return "Confirmar";
  if (estado === "reenviada_ao_cliente") return "Aguardando o cliente";
  if (estado === "em_correcao_interna") return "Em correção";
  if (cat === "faltando" || cat === "ilegivel") return "Pedir ao cliente";
  return "Decidir";
}

/**
 * Termo digitado na busca → padrão de `ilike`. `%`, `_` e `\` são curingas/escape
 * do LIKE: sem escapar, buscar "_" casaria todo nome. `*` é OUTRO curinga: o PostgREST
 * troca todo `*` do valor por `%` ANTES do Postgres, inclusive o precedido de `\`
 * (vira `\%`, que casa um "%" literal, não o "*"). Escapar com barra não funciona, então o
 * `*` vira `_` (um caractere qualquer, que inclui o próprio "*"): a busca por "a*b" acha
 * "a*b" e nunca esconde nome algum, em vez de casar a carteira inteira.
 * Vazio devolve null (sem filtro).
 */
export function padraoDeBusca(bruto: string | string[] | undefined): string | null {
  const v = (Array.isArray(bruto) ? bruto[0] : bruto)?.trim().slice(0, 80);
  if (!v) return null;
  return `%${v.replace(/[\\%_]/g, "\\$&").replace(/\*/g, "_")}%`;
}

// ---------------------------------------------------------------------------------------------------
// A FILA AGRUPADA POR MANDATO (direção A, 13/11/2026).
//
// Medido no mandato do dono: 2.088 pendências em aberto viravam 20 linhas quase iguais de "Item Faltante",
// uma por item do Kit, de 3 ou 4 mandatos. A fila continua sendo UMA lista de pendências — o filtro e as
// contagens das abas saem do mesmo conjunto de antes, então "Travam a aprovação 222" segue sendo 222
// PENDÊNCIAS —; só a APRESENTAÇÃO junta as que são do mesmo mandato numa linha com chips. O invariante que
// protege isto: a soma de `total` dos grupos é exatamente o número de pendências que entrou, e o mesmo vale
// para `bloqueantes` e `aConfirmar` (verificar-export.mts, "Fila agrupada por mandato").
// ---------------------------------------------------------------------------------------------------

export type PendenciaAgrupavel = {
  id: string; caso_id: string; tipo: string; severidade: string; estado?: string | null;
};

export type ChipDoGrupo = { rotulo: string; n: number; severidade: string };

export type GrupoDoMandato<P extends PendenciaAgrupavel> = {
  casoId: string;
  itens: P[];
  total: number;
  bloqueantes: number;
  aConfirmar: number;
  /** Um chip por rótulo, com a contagem; os que travam vêm primeiro. */
  chips: ChipDoGrupo[];
};

const PESO = (s: string) => (s === "bloqueante" ? 0 : s === "importante" ? 1 : 2);

/**
 * Agrupa por mandato SEM descartar nada. A ordem dos grupos é consequência: mais pendências que travam,
 * depois mais a confirmar, depois mais pendências; empate fica na ordem em que a lista veio.
 * `rotuloDe` dá o texto do chip (quem chama sabe ler o item faltante do Kit na descrição).
 */
export function agruparPorMandato<P extends PendenciaAgrupavel>(
  itens: readonly P[], rotuloDe: (p: P) => string,
): GrupoDoMandato<P>[] {
  const porCaso = new Map<string, P[]>();
  for (const p of itens) {
    const lista = porCaso.get(p.caso_id);
    if (lista) lista.push(p); else porCaso.set(p.caso_id, [p]);
  }
  const grupos = [...porCaso].map(([casoId, lista]) => {
    const chips = new Map<string, ChipDoGrupo>();
    for (const p of lista) {
      const rotulo = rotuloDe(p);
      const c = chips.get(rotulo);
      if (c) { c.n += 1; if (PESO(p.severidade) < PESO(c.severidade)) c.severidade = p.severidade; }
      else chips.set(rotulo, { rotulo, n: 1, severidade: p.severidade });
    }
    return {
      casoId,
      itens: lista,
      total: lista.length,
      bloqueantes: lista.filter((p) => p.severidade === "bloqueante").length,
      aConfirmar: lista.filter((p) => daFila(p, "confirmar")).length,
      chips: [...chips.values()].sort((a, b) => PESO(a.severidade) - PESO(b.severidade) || b.n - a.n),
    };
  });
  return grupos.sort((a, b) => b.bloqueantes - a.bloqueantes || b.aConfirmar - a.aConfirmar || b.total - a.total);
}

/** As abas de "Seus mandatos". Valor desconhecido na URL cai em `null` (quem chama escolhe o padrão). */
export const ABAS_DOS_MANDATOS = [
  { chave: "travados", rotulo: "Travados" },
  { chave: "andamento", rotulo: "Em andamento" },
  { chave: "fechados", rotulo: "Fechados" },
] as const;
export type AbaDosMandatos = (typeof ABAS_DOS_MANDATOS)[number]["chave"];

export function abaDosMandatos(bruto: string | string[] | undefined): AbaDosMandatos | null {
  const v = Array.isArray(bruto) ? bruto[0] : bruto;
  return ABAS_DOS_MANDATOS.find((a) => a.chave === v)?.chave ?? null;
}

/** Página da URL (`?p=`): inteiro >= 1; lixo, zero e negativo caem na primeira. */
export function paginaDaUrl(bruto: string | string[] | undefined): number {
  const v = Number(Array.isArray(bruto) ? bruto[0] : bruto);
  return Number.isInteger(v) && v >= 1 ? v : 1;
}

/** A fatia de uma página, com a página PEDIDA limitada à última (URL velha não cai em tela vazia). */
export function fatiaDaPagina(total: number, pagina: number, porPagina: number) {
  const paginas = Math.max(1, Math.ceil(total / porPagina));
  const atual = Math.min(Math.max(1, pagina), paginas);
  const de = (atual - 1) * porPagina;
  return { pagina: atual, paginas, de, ate: Math.min(total, de + porPagina) };
}
