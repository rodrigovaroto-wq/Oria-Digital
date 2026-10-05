// A COSTURA entre o que a rota do export já carrega e a base da apresentação de crédito.
//
// A apresentação NÃO tem consulta própria ao banco: ela recebe a MESMA `EntradaModeloInstitucional`
// que o modo completo do export monta — mesma entidade modelada, mesmo último exercício real, mesmo
// Portão 2. Duas leituras do mesmo caso podem discordar em silêncio (uma paginada, outra não; uma
// com a 0125, outra sem); uma leitura só não tem com quem discordar.
import { formatarPeriodo, type DocumentoParaExport } from "../export";
import { historicoParaCredito, type EntradaModeloInstitucional, type LinhaModelo } from "../modelo-institucional";
import { naturezaDoAno, type BaseCredito, type DocumentoDaBase } from "./base-credito";

/** Os tipos que trazem demonstração — os outros (contrato social, certidões…) não entram no IX. */
const TIPOS_FINANCEIROS = new Set(["BALANCO", "DRE", "BALANCETE", "DF_AUDITADA", "COMBINADO", "FLUXO_CAIXA", "DMPL", "NOTAS_EXPL"]);

const norm = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9 ]/g, " ")
  .replace(/\s+/g, " ").trim();

/** Exercícios citados no período já formatado ("2024 e 2025", "12 meses/2025", "31/12/2024"). */
export function anosDoPeriodo(formatado: string): number[] {
  return [...new Set([...formatado.matchAll(/\b((?:19|20)\d{2})\b/g)].map((m) => Number(m[1])))].sort((a, b) => a - b);
}

export function montarBaseCredito(
  ent: EntradaModeloInstitucional,
  documentos: DocumentoParaExport[],
  campos: Array<{ chave: string; valor: string; fonte: string | null }> = [],
  extras: Pick<BaseCredito, "informacao" | "perimetro" | "projecao" | "corrente"> = {},
): BaseCredito {
  const historico = historicoParaCredito(ent);
  const entidade = ent.entidade ?? ent.caso.nome;
  const alvo = norm(entidade);
  const docs: DocumentoDaBase[] = documentos.flatMap((d) => {
    if (!d.tipo_taxonomia || !TIPOS_FINANCEIROS.has(d.tipo_taxonomia)) return [];
    const razao = (Array.isArray(d.entidade) ? d.entidade[0] : d.entidade)?.razao_social ?? "";
    // Casamento simples de entidade: um nome contido no outro. É o mesmo critério do arnês do
    // modelo (`modelo-da-fixture.mts`); o banco usa `fn_mesma_entidade`, mais tolerante. Documento
    // sem entidade entra — ele foi enviado ao caso e o analista precisa vê-lo na base de informação.
    const r = norm(razao);
    if (r && !(r.includes(alvo) || alvo.includes(r))) return [];
    const per = Array.isArray(d.periodo) ? d.periodo[0] : d.periodo;
    const periodo = formatarPeriodo(per?.tipo ?? null, per?.referencia ?? null);
    const versoes = [...(d.documento_versao ?? [])].sort((a, b) => (b.n_versao ?? 0) - (a.n_versao ?? 0));
    return [{ tipo: d.tipo_taxonomia, arquivo: versoes[0]?.nome_original ?? null, periodo, anos: anosDoPeriodo(periodo) }];
  }).sort((a, b) => (a.anos[0] ?? 0) - (b.anos[0] ?? 0) || (a.tipo ?? "").localeCompare(b.tipo ?? ""));

  return {
    cliente: ent.caso.nome,
    entidade,
    unidade: historico.unidade,
    periodos: historico.anos.map((a) => naturezaDoAno(a, docs)),
    documentos: docs,
    historico,
    campos: Object.fromEntries(campos.map((c) => [c.chave, { valor: c.valor, fonte: c.fonte }])),
    // O mapa da dívida de OUTRA entidade do caso (no Canastra ele é do "GRUPO CANASTRA"): o deck da
    // empresa analisada não o soma — seria dívida de outra pessoa jurídica —, mas tem de DIZER que
    // ele existe, em vez de "nenhum mapa da dívida recebido" (medido nos mandatos locais, 05/10).
    mapasDeOutrasEntidades: [...new Set(documentos.filter((d) => d.tipo_taxonomia === "MAPA_DIVIDA").map((d) =>
      (Array.isArray(d.entidade) ? d.entidade[0] : d.entidade)?.razao_social ?? "sem entidade")
      .filter((r) => { const n = norm(r); return !(n && (n.includes(alvo) || alvo.includes(n))); }))],
    ...extras,
  };
}

/**
 * O PERÍMETRO para o slide III.3: cada empresa cadastrada no caso, quantos documentos ela tem e se é
 * a analisada. Mesmo casamento de nome do resto deste arquivo (um contido no outro).
 */
export function perimetroDoCaso(
  entidades: Array<{ razao_social: string; cnpj: string | null; papel_no_grupo: string | null }>,
  documentos: DocumentoParaExport[],
  entidadeAnalisada: string,
): NonNullable<BaseCredito["perimetro"]> {
  const alvo = norm(entidadeAnalisada);
  const docsDe = (nome: string) => documentos.filter((d) =>
    norm((Array.isArray(d.entidade) ? d.entidade[0] : d.entidade)?.razao_social ?? "") === norm(nome)).length;
  return entidades.map((e) => ({
    razaoSocial: e.razao_social, cnpj: e.cnpj, papel: e.papel_no_grupo, documentos: docsDe(e.razao_social),
    analisada: norm(e.razao_social) === alvo || (alvo.length > 0 && norm(e.razao_social).includes(alvo)),
  })).sort((a, b) => Number(b.analisada) - Number(a.analisada) || b.documentos - a.documentos);
}

/**
 * O QUE CHEGOU E O QUE FALTOU do kit básico. `atendidos` vem de `itensDoKitBasicoAtendidos` — a MESMA
 * regra da tela do caso, que pergunta ao banco pelo combinado estrutural (0157); `semConteudo` vem do
 * checklist (`recebido_nao_valido`): chegou e não rendeu linha nenhuma.
 */
export function informacaoDoKit(
  kit: Array<{ codigo: string; documento: string }>,
  atendidos: ReadonlySet<string>,
  semConteudo: ReadonlySet<string>,
): NonNullable<BaseCredito["informacao"]> {
  return kit.map((k) => ({
    codigo: k.codigo, documento: k.documento,
    status: semConteudo.has(k.codigo) ? "sem_conteudo" as const : atendidos.has(k.codigo) ? "recebido" as const : "faltante" as const,
  }));
}

const MESES_ABREV = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];
/**
 * O "resultado atual": o ano em curso pelo MESMO classificador do realizado. Os meses saem do período
 * do balancete daquele ano ("8 meses/2026", "ago/2026"); sem período legível, `meses` é null e o deck
 * diz "parcial" em vez de supor o mês.
 */
export function correnteDoBalancete(
  ent: EntradaModeloInstitucional, linhas: LinhaModelo[], ano: number, documentos: DocumentoParaExport[],
): NonNullable<BaseCredito["corrente"]> | null {
  if (!linhas.some((l) => l.valores[String(ano)] !== undefined)) return null;
  let meses: number | null = null;
  for (const d of documentos) {
    if (d.tipo_taxonomia !== "BALANCETE" && d.tipo_taxonomia !== "DRE") continue;
    const per = Array.isArray(d.periodo) ? d.periodo[0] : d.periodo;
    const f = formatarPeriodo(per?.tipo ?? null, per?.referencia ?? null).toLowerCase();
    if (!f.includes(String(ano))) continue;
    const m = /(\d{1,2}) meses/.exec(f) ?? null;
    const mn = MESES_ABREV.findIndex((x) => f.startsWith(x) || f.includes(`/${x}`));
    const n = m ? Number(m[1]) : mn >= 0 ? mn + 1 : /^\d{2}\/(\d{2})\/\d{4}$/.test(f) ? Number(f.slice(3, 5)) : null;
    if (n !== null && n >= 1 && n <= 12) meses = Math.max(meses ?? 0, n);
  }
  return { ano, meses, historico: historicoParaCredito({ ...ent, anosHistoricos: [ano], linhas }) };
}
