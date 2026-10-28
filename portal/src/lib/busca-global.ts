import { padraoDeBusca } from "./painel";

// REGRAS PURAS DA BUSCA GLOBAL (⌘K). Moram aqui, e não na rota nem no componente,
// para o `verificar-export.mts` (bloco 42b) conseguir reprová-las.
//
// OVERSIGHT DE EGRESS (PRODUCT.md): a rota faz no máximo 3 consultas por tecla
// aceita, cada uma com colunas nomeadas, filtro em ILIKE no Postgres e `limit`
// de LIMITE_POR_GRUPO. Nada de varrer e filtrar no servidor Node.

export const MIN_CARACTERES = 2;
export const MAX_CARACTERES = 60;
export const LIMITE_POR_GRUPO = 6;
/**
 * Quantas VERSÕES de documento a rota traz para depois reduzir a documentos distintos. O
 * `limit` do banco é por linha de `documento_versao`, e um documento com 20 versões que casam
 * o termo enchia o grupo sozinho ("1 resultado" com 20 casando). A janela é maior que o teto de
 * propósito: a deduplicação por documento acontece DEPOIS dela, e janela cheia vira aviso.
 */
export const JANELA_DE_VERSOES = 30;

/**
 * O termo que vale ser enviado: aparado, no máximo 60 caracteres, e NULO abaixo
 * de 2. Abaixo de 2 o `ilike '%a%'` casa quase tudo e custa uma ida ao banco
 * para devolver ruído: nenhuma requisição sai.
 */
export function termoDaBusca(bruto: string | null | undefined): string | null {
  const t = (bruto ?? "").trim().slice(0, MAX_CARACTERES).trim();
  return t.length >= MIN_CARACTERES ? t : null;
}

/**
 * Se o termo é só dígitos e a pontuação de um CNPJ (`12.345.678/0001-90`),
 * devolve os dígitos; senão NULO. "12.345" e "12345" são a mesma busca. Termo com
 * letra NUNCA vira busca por CNPJ ("Ana 2" é nome). O CNPJ é gravado só com
 * dígitos (`fn_cnpj_canonico`, 0169), por isso o casamento é por dígitos.
 */
export function digitosDoCnpj(termo: string): string | null {
  if (!/^[\d.\-/\s]+$/.test(termo)) return null;
  const d = termo.replace(/\D/g, "");
  return d.length >= MIN_CARACTERES ? d : null;
}

/** O padrão `ilike` do termo — O MESMO escape da busca da lista de Mandatos. */
export function padraoDoTermo(termo: string): string {
  return padraoDeBusca(termo) ?? "%";
}

export type GrupoDeBusca = "acoes" | "mandatos" | "documentos" | "entidades";

export type ResultadoDeBusca = {
  chave: string;
  grupo: GrupoDeBusca;
  rotulo: string;
  detalhe?: string;
  /** Mandato fechado: vira a marca "Fechado" ao lado do nome. */
  fechado?: boolean;
  href: string;
};

export const ROTULO_DO_GRUPO: Record<GrupoDeBusca, string> = {
  acoes: "Ações",
  mandatos: "Mandatos",
  documentos: "Documentos",
  entidades: "Grupo econômico",
};

export const ACOES_RAPIDAS: ReadonlyArray<ResultadoDeBusca> = [
  { chave: "acao:novo", grupo: "acoes", rotulo: "Novo mandato", href: "/casos/novo" },
  { chave: "acao:inicio", grupo: "acoes", rotulo: "Início", href: "/casos" },
  { chave: "acao:mandatos", grupo: "acoes", rotulo: "Mandatos", href: "/casos/todos" },
];

const semAcento = (s: string) => s.normalize("NFD").replace(/\p{M}/gu, "").toLocaleLowerCase("pt-BR");

/** As ações que o termo casa (sem acento, sem caixa); sem termo, todas. */
export function acoesDoTermo(termo: string | null): ResultadoDeBusca[] {
  if (termo === null) return [...ACOES_RAPIDAS];
  const t = semAcento(termo);
  return ACOES_RAPIDAS.filter((a) => semAcento(a.rotulo).includes(t));
}

export type RespostaDaBusca = {
  resultados: ResultadoDeBusca[];
  /** grupos em que o teto foi atingido: a lista NÃO é exaustiva (regra 1: ausência não é dado) */
  truncados: GrupoDeBusca[];
};

export type LinhasDaBusca = {
  mandatos: ReadonlyArray<{ id: string; nome: string; fechado_em: string | null }>;
  documentos: ReadonlyArray<{
    documento_id: string; caso_id: string; nome_original: string | null; caso_nome: string | null;
  }>;
  entidades: ReadonlyArray<{
    id: string; caso_id: string; razao_social: string; cnpj: string | null; caso_nome: string | null;
  }>;
};

/** "12345678000190" → "12.345.678/0001-90"; qualquer outra coisa volta como veio. */
export function cnpjFormatado(cnpj: string): string {
  const d = cnpj.replace(/\D/g, "");
  return d.length === 14 ? d.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5") : cnpj;
}

/**
 * As linhas do banco → a lista plana, na ordem em que aparece (mandatos, documentos,
 * entidades), MAIS os grupos cujo teto foi atingido. A rota pede UMA linha além do teto
 * (mandatos, entidades) e uma janela de versões (documentos); aqui o documento é deduplicado
 * ANTES do corte, e o grupo é `truncado` quando sobrou resultado distinto além do teto OU
 * quando a janela de versões veio cheia (pode haver mais documentos além dela). Um documento
 * com várias versões casando entra UMA vez (a chave é o documento, não a versão), e a mesma
 * entidade idem. Documento sem `nome_original` não chega aqui — o `ilike` já o excluiu —,
 * mas se chegar, o rótulo diz "(sem nome)" em vez de ficar em branco.
 */
export function agruparResultados(l: LinhasDaBusca): RespostaDaBusca {
  const out: ResultadoDeBusca[] = [];
  const truncados: GrupoDeBusca[] = [];
  for (const m of l.mandatos.slice(0, LIMITE_POR_GRUPO)) {
    out.push({
      chave: `mandato:${m.id}`, grupo: "mandatos", rotulo: m.nome,
      fechado: m.fechado_em !== null, href: `/casos/${m.id}`,
    });
  }
  if (l.mandatos.length > LIMITE_POR_GRUPO) truncados.push("mandatos");

  const vistosDoc = new Set<string>();
  const docs: ResultadoDeBusca[] = [];
  for (const d of l.documentos) {
    if (vistosDoc.has(d.documento_id)) continue;
    vistosDoc.add(d.documento_id);
    docs.push({
      chave: `documento:${d.documento_id}`, grupo: "documentos",
      rotulo: d.nome_original ?? "(sem nome)", detalhe: d.caso_nome ?? undefined,
      href: `/casos/${d.caso_id}/documentos/${d.documento_id}`,
    });
  }
  out.push(...docs.slice(0, LIMITE_POR_GRUPO));
  if (docs.length > LIMITE_POR_GRUPO || l.documentos.length >= JANELA_DE_VERSOES) truncados.push("documentos");

  const vistosEnt = new Set<string>();
  const ents: ResultadoDeBusca[] = [];
  for (const e of l.entidades) {
    if (vistosEnt.has(e.id)) continue;
    vistosEnt.add(e.id);
    ents.push({
      chave: `entidade:${e.id}`, grupo: "entidades", rotulo: e.razao_social,
      detalhe: [e.cnpj ? cnpjFormatado(e.cnpj) : null, e.caso_nome].filter(Boolean).join(" · ") || undefined,
      href: `/casos/${e.caso_id}/perimetro`,
    });
  }
  // Razão social e CNPJ são duas consultas: a união passa de 6, e o teto é do grupo.
  out.push(...ents.slice(0, LIMITE_POR_GRUPO));
  if (ents.length > LIMITE_POR_GRUPO) truncados.push("entidades");
  return { resultados: out, truncados };
}
