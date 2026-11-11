// O MAPA DA DÍVIDA, OPERAÇÃO A OPERAÇÃO — uma leitura só para as duas formas em que ele chega.
//
// POR QUE ESTE ARQUIVO EXISTE. O deck lia o mapa só na forma ACHATADA das fixtures ("Credor —
// Modalidade — saldo devedor", coluna = ano). Produção extrai o mapa MATRICIAL: a chave é o contrato
// e o conceito mora na COLUNA ("Saldo devedor (R$)", "Juros do exercício (R$)", "Taxa",
// "Vencimento", "Garantia") — é o que a 0145 documenta ("o conceito pode morar na COLUNA", pendência
// da v48 no 02_DRE_Canastra_Industria). Nessa forma o leitor antigo não achava operação nenhuma e o
// XIII dizia "nenhum mapa" com o mapa extraído. E as colunas de TEXTO (taxa contratual, vencimento,
// garantia, indexador) eram descartadas: o modelo só carrega número.
//
// As duas formas passam por `lerMapaDaDivida`: quem chama traduz a sua fonte (linhas do modelo,
// campos extraídos) em `LinhaDoMapa`, e a regra de "que medida é esta" vive num lugar só.

/**
 * TEXTO PERDIDO. `achatarGrupos` (N8N) mantém os números de uma conta e perde os textos, e NÃO grava
 * célula nula/nula: o contrato perdido chega só com as colunas numéricas. Quem diz QUAL chave perdeu é
 * `depois->medicao->textos_perdidos` do evento 'extracao_sombra' (a chave NÃO é única por contrato: o
 * mesmo credor tem um contrato lido e outro perdido). Então "perdido" = chave ∈ lista E o contrato
 * (chave + linha impressa) não tem nenhuma célula de texto com valor. PONTO ÚNICO do predicado: deck
 * (via `montar-base`) e export usam `estadoDoTextoPorCampo`.
 *  - "desconhecido": não dá para dizer (leitura do evento falhou, ou evento anterior à medição).
 */
export type EstadoDoTexto = "perdido" | "desconhecido";
export interface DocComTextos { textos_perdidos?: string[]; textos_perdidos_desconhecido?: boolean }
export interface CampoDoMapa { id: string; chave: string; periodo_coluna: string | null; valor_texto: string | null; ordem: number | null }

/**
 * O documento fica "desconhecido" quando a leitura do evento falhou, ou quando o último evento é de antes
 * da medição E não dá para descartar a perda (pendência "TEXTOS sem coluna" aberta, ou a consulta das
 * pendências falhou — sem ela, "sem pendência" seria só ausência de resposta).
 */
export function textoDesconhecido(a: { erroEvento: boolean; erroPendencias: boolean; algumNaoMedido: boolean; comPendencia: boolean }): boolean {
  return a.erroEvento || (a.algumNaoMedido && (a.erroPendencias || a.comPendencia));
}

/** A frase que o `falha_motivo` do n8n grava na pendência `extracao_falhou` quando perde textos. */
export const MARCADOR_TEXTO_NAO_LIDO = "TEXTOS sem coluna";

/**
 * O evento já MEDE textos perdidos? `versao_medicao` 'p4-N' com N >= 3. Compara o INTEIRO (lexical
 * poria 'p4-10' antes de 'p4-3'); formato inesperado ou ausente = não mede.
 */
export function medicaoSabeTextosPerdidos(versao: unknown): boolean {
  const m = typeof versao === "string" ? /^p4-(\d+)$/.exec(versao) : null;
  return m !== null && Number(m[1]) >= 3;
}

/**
 * A linha impressa de cada campo (forma matricial): muda quando a chave muda, uma coluna se repete, ou
 * uma coluna de IDENTIDADE (credor, modalidade) chega depois de uma coluna de valor — esta SÓ quando a
 * chave anterior consta de `perdidas`: o contrato perdido (só Saldo e Juros) fundia com o seguinte do
 * mesmo credor, que abre por "Modalidade". Fora da perda vale a regra antiga (Taxa|Modalidade|Saldo e
 * "Banco garantidor" depois de Saldo são UMA operação). Limite: tabela que não abre por identidade.
 */
export function linhaDosCampos(campos: CampoDoMapa[], perdidas?: Set<string>): Map<string, number> {
  const out = new Map<string, number>();
  let linha = 0;
  let ant: string | null = null;
  const vistas = new Set<string>();
  for (const c of [...campos].sort((x, y) => (x.ordem ?? 0) - (y.ordem ?? 0))) {
    const col = c.periodo_coluna;
    if (col === null || medidaDoRotulo(col) === null || /\b(?:19|20)\d{2}\b/.test(col)) continue;
    const identidade = ["credor", "modalidade"].includes(medidaDoRotulo(col) ?? "");
    const temValor = [...vistas].some((v) => !["credor", "modalidade"].includes(medidaDoRotulo(v) ?? ""));
    if (c.chave !== ant || vistas.has(col) || (identidade && temValor && (perdidas?.has(ant ?? "") ?? false))) { linha += 1; vistas.clear(); }
    vistas.add(col);
    ant = c.chave;
    out.set(c.id, linha);
  }
  return out;
}

export function estadoDoTextoPorCampo(doc: DocComTextos, campos: CampoDoMapa[]): Map<string, EstadoDoTexto> {
  const out = new Map<string, EstadoDoTexto>();
  if (doc.textos_perdidos_desconhecido) { for (const c of campos) out.set(c.id, "desconhecido"); return out; }
  const perdidas = doc.textos_perdidos ?? [];
  if (perdidas.length === 0) return out;
  const linhas = linhaDosCampos(campos, new Set(perdidas));
  const grupos = new Map<string, CampoDoMapa[]>();
  for (const c of campos) {
    if (!perdidas.includes(c.chave)) continue;
    const k = `${c.chave}\u0000${linhas.get(c.id) ?? ""}`;
    grupos.set(k, [...(grupos.get(k) ?? []), c]);
  }
  for (const g of grupos.values()) {
    if (!g.some((c) => (c.valor_texto ?? "").trim() !== "")) for (const c of g) out.set(c.id, "perdido");
  }
  return out;
}

export interface OperacaoDivida {
  /** a extração leu os números desta operação e PERDEU os textos (credor, prazo, taxa…) */
  textoNaoLido?: boolean;
  /** sem texto de vencimento E não foi possível conferir se a extração o perdeu (leitura do evento falhou) */
  textoNaoConferido?: boolean;
  credor: string; modalidade: string; operacao: string | null;
  saldo: Record<number, number | null>; juros: Record<number, number | null>;
  /** parcela de curto/longo prazo, quando o mapa as separa */
  cp?: Record<number, number | null>; lp?: Record<number, number | null>;
  /** como o DOCUMENTO imprime (texto): "CDI + 9,20% a.a.", "15/03/2027", "Aval dos sócios" */
  taxaContratual?: string | null; indexador?: string | null; vencimento?: string | null; garantia?: string | null;
}

export interface LinhaDoMapa {
  chave: string;
  /** o rótulo da coluna quando ela NÃO é período (forma matricial); null na forma achatada */
  coluna: string | null;
  ano: number;
  /** já na escala do modelo */
  num: number | null;
  texto: string | null;
  /**
   * a LINHA impressa (forma matricial): o mesmo credor aparece em duas linhas quando tem duas
   * modalidades ("Banco X | Capital de giro" e "Banco X | Antecipação"), e agrupar só pela chave
   * fundiria as duas operações numa.
   */
  linha?: number;
  /** `estadoDoTexto` da conta desta linha */
  textoEstado?: "perdido" | "desconhecido";
}

type Medida = "saldo" | "juros" | "cp" | "lp" | "taxa" | "indexador" | "vencimento" | "garantia" | "credor" | "modalidade";

const sem = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

/**
 * Que medida um rótulo (de coluna, ou o último pedaço da chave) carrega. A ordem importa: "juros a
 * vencer" é juros, não vencimento; "saldo de longo prazo" é LP, não saldo total; "valor contratado"
 * NÃO é saldo (é o valor original — somá-lo como saldo inflaria a dívida).
 */
export function medidaDoRotulo(rotulo: string): Medida | null {
  const r = sem(rotulo);
  if (/contratad|original|liberad/.test(r)) return null;
  if (/(moeda de origem|\(us\$|\busd\b|\beur\b)/.test(r)) return null;
  if (/juros|encargos/.test(r)) return "juros";
  if (/longo prazo|nao circulante|\blp\b/.test(r)) return "lp";
  if (/curto prazo|\bcirculante|\bcp\b/.test(r)) return "cp";
  if (/saldo|principal|devedor|em aberto/.test(r)) return "saldo";
  if (/indexador|indice/.test(r)) return "indexador";
  if (/taxa|custo|remunera/.test(r)) return "taxa";
  if (/vencimento|prazo final|data final|termino/.test(r)) return "vencimento";
  if (/garantia/.test(r)) return "garantia";
  if (/credor|banco|instituic|financiador/.test(r)) return "credor";
  if (/modalidade|linha de credito|produto|tipo de operac/.test(r)) return "modalidade";
  return null;
}

const SEP = /\s+[—–-]\s+/;

export function lerMapaDaDivida(linhas: LinhaDoMapa[], anos: number[]):
  { operacoes: OperacaoDivida[]; totalDoMapa: Record<number, number | null> } {
  const totalDoMapa: Record<number, number | null> = Object.fromEntries(anos.map((a) => [a, null]));
  // Agrupa por OPERAÇÃO: na forma matricial a chave inteira é a operação; na achatada, a chave sem
  // o último pedaço (a medida).
  const grupos = new Map<string, Array<{ medida: Medida; l: LinhaDoMapa }>>();
  for (const l of linhas) {
    let opChave = l.chave.trim();
    let medida: Medida | null;
    if (l.coluna !== null) {
      medida = medidaDoRotulo(l.coluna);
    } else {
      const partes = opChave.split(SEP).map((x) => x.trim()).filter(Boolean);
      medida = medidaDoRotulo(partes.at(-1) ?? "");
      opChave = partes.slice(0, -1).join(" — ");
    }
    if (!medida || !opChave) continue;
    if (/^total\b/i.test(sem(opChave))) {
      if (medida === "saldo" && l.num !== null && anos.includes(l.ano)) totalDoMapa[l.ano] = Math.abs(l.num);
      continue;
    }
    const g = l.linha === undefined ? opChave : `${opChave}\u0000${l.linha}`;
    grupos.set(g, [...(grupos.get(g) ?? []), { medida, l }]);
  }
  const vazio = () => Object.fromEntries(anos.map((a) => [a, null])) as Record<number, number | null>;
  const operacoes: OperacaoDivida[] = [];
  for (const [g, itens] of grupos) {
    const opChave = g.split("\u0000")[0];
    const texto = (m: Medida) => {
      const i = itens.find((x) => x.medida === m && (x.l.texto ?? x.l.num) !== null);
      return i ? (i.l.texto?.trim() || String(i.l.num)) : null;
    };
    const serie = (m: Medida) => {
      const r = vazio();
      for (const { medida, l } of itens) if (medida === m && l.num !== null && anos.includes(l.ano)) r[l.ano] = Math.abs(l.num);
      return r;
    };
    const saldo = serie("saldo");
    const cp = serie("cp");
    const lp = serie("lp");
    // Mapa que só separa CP e LP (sem coluna de saldo): o saldo É a soma — e só quando as duas vêm.
    for (const a of anos) if (saldo[a] === null && cp[a] !== null && lp[a] !== null) saldo[a] = (cp[a] as number) + (lp[a] as number);
    const partes = opChave.split(SEP).map((x) => x.trim()).filter(Boolean);
    const credorCol = texto("credor");
    const modCol = texto("modalidade");
    const credor = credorCol ?? partes[0];
    const restoDaChave = credorCol ? partes : partes.slice(1);
    const modalidade = modCol ?? restoDaChave[0] ?? "n/d";
    const operacao = (modCol ? restoDaChave : restoDaChave.slice(1)).join(" — ") || null;
    const vencimento = texto("vencimento");
    const perdido = itens.some((x) => x.l.textoEstado === "perdido");
    operacoes.push({ credor, modalidade, operacao, saldo, juros: serie("juros"),
      ...(Object.values(cp).some((v) => v !== null) ? { cp } : {}),
      ...(Object.values(lp).some((v) => v !== null) ? { lp } : {}),
      taxaContratual: texto("taxa"), indexador: texto("indexador"), vencimento, garantia: texto("garantia"),
      ...(perdido ? { textoNaoLido: true } : {}),
      ...(!perdido && vencimento === null && itens.some((x) => x.l.textoEstado === "desconhecido") ? { textoNaoConferido: true } : {}) });
  }
  return { operacoes, totalDoMapa };
}

/**
 * Ano do vencimento impresso: "15/03/2027", "03/2027", "2027", "mar/27". `null` para "Rotativo",
 * "Sem vencimento definido" e o que não tiver ano legível — o muro de vencimentos os mostra à parte.
 */
export function anoDoVencimento(texto: string | null | undefined): number | null {
  if (!texto) return null;
  const m4 = /\b((?:19|20)\d{2})\b/.exec(texto);
  if (m4) return Number(m4[1]);
  const m2 = /\b\d{1,2}\/(\d{2})$|\b[a-z]{3}\/(\d{2})\b/i.exec(texto.trim());
  return m2 ? 2000 + Number(m2[1] ?? m2[2]) : null;
}
