// CUSTO DE IA POR MANDATO E NO PERÍODO — a aba "Custos" da Administração.
//
// DE ONDE VEM O NÚMERO. `lote_execucao` (0115) tem UMA linha por execução de ingestão
// com `custo_total_usd`, gravada por `fn_registrar_uso_lote` com chave
// (caso_id, execucao_ref) — a chave que impede a mesma execução de contar duas vezes.
// É a única fonte de custo medido que o banco expõe; nada aqui estima, converte moeda
// ou soma o que `fn_operacao_lotes` já decide (os alertas "custo acima do previsto"
// continuam sendo dele, para não haver duas réguas).
//
// AUSÊNCIA NÃO É ZERO (regra 1). `custo_total_usd` é NULL quando a execução não
// registrou custo (lote antigo, resumo sem o campo). Somar NULL como 0 faria o
// mandato parecer mais barato do que é, e o arquivo é lido por quem decide. Por isso
// cada soma carrega `semCusto` (quantos lotes ficaram de fora) e o total é um PISO
// quando `semCusto > 0`; custo por documento usa só os lotes COM custo — numerador e
// denominador do mesmo conjunto — e é null quando esse conjunto não tem documento.
// O TOTAL "desde o início" cobre só os mandatos que EXISTEM: `lote_execucao` é ON DELETE CASCADE de
// `caso`, então o custo de um mandato excluído some junto e esta tela não tem como recuperá-lo —
// por isso o rótulo diz "mandatos existentes" e há nota visível (regra 1: o total não é o gasto
// histórico da casa).
// A moeda é a do banco (USD): não há taxa de câmbio medida em lugar nenhum, e converter
// com uma taxa inventada seria um número que parece medido e não é.

export interface LoteDeCusto {
  caso_id: string;
  criado_em: string;
  documentos: number | null;
  custo_total_usd: number | string | null;
}

export interface SomaDeCusto {
  /** lotes (execuções de ingestão) no conjunto */
  lotes: number;
  /** destes, quantos NÃO registraram custo: o total abaixo é piso quando > 0 */
  semCusto: number;
  /** soma só dos lotes com custo medido; null se NENHUM tem (nunca 0 por falta de dado) */
  custoUsd: number | null;
  /** destes sem custo, quantos tinham custo PRESENTE mas ilegível (NaN, negativo, texto): dado ruim, não ausência */
  ilegiveis: number;
  /** documentos dos lotes COM custo medido */
  documentosMedidos: number;
  /** custo ÷ documentos, só dos lotes com custo e com documentos; null se não dá para dividir */
  custoPorDocumentoUsd: number | null;
  /** ISO do lote mais recente, ou null */
  ultimoEm: string | null;
}

export interface CustoDoMandato {
  casoId: string;
  periodo: SomaDeCusto;
  total: SomaDeCusto;
}

export interface CustosAgregados {
  periodo: SomaDeCusto;
  total: SomaDeCusto;
  porMandato: CustoDoMandato[];
}

/** numeric do Postgres pode chegar como string; NaN/Infinity/negativo é dado ruim, não custo. */
function custoValido(v: number | string | null): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) && n >= 0 ? n : null;
}

export function somarCustos(lotes: LoteDeCusto[]): SomaDeCusto {
  let semCusto = 0;
  let ilegiveis = 0;
  let soma = 0;
  let comCusto = 0;
  let docsMedidos = 0;
  let custoComDocs = 0;
  let docsComCusto = 0;
  let ultimo: string | null = null;
  for (const l of lotes) {
    if (ultimo === null || l.criado_em > ultimo) ultimo = l.criado_em;
    const c = custoValido(l.custo_total_usd);
    if (c === null) {
      semCusto += 1;
      if (l.custo_total_usd !== null && l.custo_total_usd !== undefined && l.custo_total_usd !== "") ilegiveis += 1;
      continue;
    }
    comCusto += 1;
    soma += c;
    const d = l.documentos;
    if (typeof d === "number" && Number.isFinite(d) && d > 0) {
      docsMedidos += d;
      custoComDocs += c;
      docsComCusto += 1;
    }
  }
  return {
    lotes: lotes.length,
    semCusto,
    ilegiveis,
    custoUsd: comCusto > 0 ? soma : null,
    documentosMedidos: docsMedidos,
    custoPorDocumentoUsd: docsComCusto > 0 && docsMedidos > 0 ? custoComDocs / docsMedidos : null,
    ultimoEm: ultimo,
  };
}

/**
 * Agrega os lotes por mandato, no período (últimos `dias`, ou tudo se `dias` for null)
 * e no total. Ordena pelo maior custo no período, depois no total; mandato sem custo
 * medido vai para o fim — não para o topo nem para "zero".
 */
export function agregarCustos(lotes: LoteDeCusto[], agora: Date, dias: number | null): CustosAgregados {
  const corte = dias === null ? null : agora.getTime() - dias * 86_400_000;
  const noPeriodo = (l: LoteDeCusto) => {
    if (corte === null) return true;
    const t = Date.parse(l.criado_em);
    return Number.isFinite(t) && t >= corte;
  };
  const porCaso = new Map<string, LoteDeCusto[]>();
  for (const l of lotes) {
    const lista = porCaso.get(l.caso_id);
    if (lista) lista.push(l); else porCaso.set(l.caso_id, [l]);
  }
  const porMandato: CustoDoMandato[] = [...porCaso.entries()].map(([casoId, ls]) => ({
    casoId,
    periodo: somarCustos(ls.filter(noPeriodo)),
    total: somarCustos(ls),
  }));
  porMandato.sort((a, b) =>
    (b.periodo.custoUsd ?? -1) - (a.periodo.custoUsd ?? -1) ||
    (b.total.custoUsd ?? -1) - (a.total.custoUsd ?? -1) ||
    a.casoId.localeCompare(b.casoId));
  return { periodo: somarCustos(lotes.filter(noPeriodo)), total: somarCustos(lotes), porMandato };
}

/** "US$ 12,34"; abaixo de 1 centavo mostra 4 casas (o custo por documento é ~US$ 0,05). null → null. */
export function formatarUsd(v: number | null): string | null {
  if (v === null || !Number.isFinite(v)) return null;
  const casas = v > 0 && v < 0.1 ? 4 : 2;
  return `US$ ${v.toLocaleString("pt-BR", { minimumFractionDigits: casas, maximumFractionDigits: casas })}`;
}

/**
 * O MOTIVO de um valor ausente na tela de custos — um por causa, porque "custo não registrado" para
 * tudo mandava procurar o custo onde o que faltava era o número de documentos (regra 1: a ausência
 * diz o que falta E o efeito). Devolve null quando há valor a mostrar.
 */
export function motivoDaAusencia(s: SomaDeCusto, campo: "custoUsd" | "custoPorDocumentoUsd"): string | null {
  if (s[campo] !== null) return null;
  if (s.lotes === 0) return "sem execução no período";
  if (s.custoUsd === null) {
    // Nenhum lote tem custo utilizável: nem o total nem o por-documento existem.
    return s.ilegiveis > 0
      ? "custo registrado ilegível ou negativo — não entra na soma"
      : "custo não registrado";
  }
  // Há custo, mas nenhum lote com custo tem documentos válidos para dividir.
  return "documentos processados não registrados — não dá para dividir o custo";
}
