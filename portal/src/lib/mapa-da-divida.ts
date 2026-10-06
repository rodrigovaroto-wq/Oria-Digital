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

export interface OperacaoDivida {
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
    operacoes.push({ credor, modalidade, operacao, saldo, juros: serie("juros"),
      ...(Object.values(cp).some((v) => v !== null) ? { cp } : {}),
      ...(Object.values(lp).some((v) => v !== null) ? { lp } : {}),
      taxaContratual: texto("taxa"), indexador: texto("indexador"), vencimento: texto("vencimento"), garantia: texto("garantia") });
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
