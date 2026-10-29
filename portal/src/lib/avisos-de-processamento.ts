// AVISOS DE PROCESSAMENTO — regras puras do sino da barra superior. Sem React e sem `window`:
// o que se prova em `scripts/verificar-mensagem-de-falha.mts` mora aqui; o componente só chama.
//
// DE ONDE VEM O ESTADO (sem migration): `lote_execucao` (0115 + 0156) e `execucao_falha` (0108).
// O que a tela PODE afirmar, e só isto:
//   • `fechado_em` preenchido = a cadeia do n8n chegou ao fim. NÃO é "tudo foi extraído certo"
//     (a cobertura é outra pergunta, da tela de Qualidade) — por isso o rótulo é "processamento
//     concluído", nunca "dados prontos";
//   • `fechado_em` nulo + mais tempo que a janela da própria tela de upload (`janelaPara`) = parou;
//   • `fechado_em` nulo + dentro da janela = em andamento: NÃO é aviso (ainda não terminou);
//   • `fechado_em` nulo + plano desconhecido (`documentos_planejados` nulo) = a tela NÃO sabe o
//     tamanho do lote, logo não sabe a janela: diz "sem confirmação de término", nunca "parado".
// Falha antes de o lote existir (orçamento recusou, nó morto no começo) só deixa linha em
// `execucao_falha` — por isso as duas fontes entram. Não há deduplicação entre as duas: um lote
// que abriu e depois falhou pode gerar um aviso de cada. Aceito: dois avisos a mais são ruído
// recuperável; um a menos seria silêncio.
//
// "VISTO" É POR NAVEGADOR (localStorage). Um aviso visto por usuário no servidor exigiria tabela
// nova — fica como evolução. A tela declara o limite.

import { janelaPara } from "./espera-do-lote";

/** Janela de leitura e teto: aviso mais velho que 7 dias não é notícia, e 20 cabem num menu. */
export const JANELA_DOS_AVISOS_DIAS = 7;
export const TETO_DOS_AVISOS = 20;
/** Teto do que se guarda como visto — o localStorage não cresce para sempre. */
export const TETO_DE_VISTOS = 200;
export const CHAVE_AVISOS_VISTOS = "oria.avisos-vistos";

export interface LoteLido {
  id: string;
  caso_id: string;
  caso: { nome: string | null } | { nome: string | null }[] | null;
  criado_em: string;
  fechado_em: string | null;
  documentos: number | null;
  documentos_planejados: number | null;
  documentos_com_falha: number | null;
}

export interface FalhaLida {
  id: string;
  caso_id: string | null;
  caso_nome: string | null;
  etapa: string;
  criado_em: string;
}

export type TipoDeAviso = "concluido" | "concluido_com_falhas" | "parado" | "sem_confirmacao" | "falha";

export interface Aviso {
  /** Identidade do aviso para o "visto". Leva o TIPO: o lote que estava parado e depois fechou é outro aviso. */
  chave: string;
  tipo: TipoDeAviso;
  rotulo: string;
  detalhe: string | null;
  casoId: string | null;
  casoNome: string | null;
  quando: string;
}

export const ROTULO_DO_TIPO: Record<TipoDeAviso, string> = {
  concluido: "Processamento concluído",
  concluido_com_falhas: "Concluído, com documentos que falharam",
  parado: "Processamento parado",
  sem_confirmacao: "Sem confirmação de término",
  falha: "Falha no processamento",
};

/** Os tipos que pedem ação — a tela os destaca com texto, não só com cor. */
export function pedeAtencao(tipo: TipoDeAviso): boolean {
  return tipo !== "concluido";
}

/** `null` = lote em andamento (não é aviso). */
export function classificarLote(l: LoteLido, agoraMs: number): TipoDeAviso | null {
  if (l.fechado_em) return (l.documentos_com_falha ?? 0) > 0 ? "concluido_com_falhas" : "concluido";
  const abertoMs = Date.parse(l.criado_em);
  if (!Number.isFinite(abertoMs)) return "sem_confirmacao";
  if (l.documentos_planejados == null) return "sem_confirmacao";
  return agoraMs - abertoMs > janelaPara(l.documentos_planejados) ? "parado" : null;
}

function nomeDoCaso(l: LoteLido): string | null {
  const c = Array.isArray(l.caso) ? l.caso[0] : l.caso;
  return c?.nome ?? null;
}

function detalheDoLote(tipo: TipoDeAviso, l: LoteLido): string | null {
  if (tipo === "concluido_com_falhas") {
    const n = l.documentos_com_falha ?? 0;
    return `${n} documento${n === 1 ? "" : "s"} com falha; abra o mandato para ver quais`;
  }
  if (tipo === "parado") return "O lote não chegou ao fim dentro do tempo esperado para o tamanho dele";
  if (tipo === "sem_confirmacao") return "O lote não registrou o fim e o tamanho previsto não é conhecido";
  return null;
}

export function montarAvisos(
  lotes: readonly LoteLido[], falhas: readonly FalhaLida[], agoraMs: number,
): Aviso[] {
  const avisos: Aviso[] = [];
  for (const l of lotes) {
    const tipo = classificarLote(l, agoraMs);
    if (!tipo) continue;
    avisos.push({
      chave: `lote:${l.id}:${tipo}`, tipo, rotulo: ROTULO_DO_TIPO[tipo], detalhe: detalheDoLote(tipo, l),
      casoId: l.caso_id, casoNome: nomeDoCaso(l),
      // Concluído: a hora em que fechou. Parado/sem confirmação: quando abriu (não há fim).
      quando: l.fechado_em ?? l.criado_em,
    });
  }
  for (const f of falhas) {
    avisos.push({
      chave: `falha:${f.id}`, tipo: "falha", rotulo: ROTULO_DO_TIPO.falha,
      detalhe: "O processamento parou antes de terminar; abra o mandato para ver o que foi lido",
      casoId: f.caso_id, casoNome: f.caso_nome, quando: f.criado_em,
    });
  }
  const ms = (a: Aviso) => Date.parse(a.quando) || 0;
  return avisos.sort((a, b) => ms(b) - ms(a)).slice(0, TETO_DOS_AVISOS);
}

// ---------------------------------------------------------------------------
// O VISTO — por navegador.
// ---------------------------------------------------------------------------

/**
 * Chaves já vistas. `null` = armazenamento INDISPONÍVEL (janela privada, bloqueado): a tela não
 * sabe o que foi visto e diz isso, em vez de fingir "nada novo". Conteúdo corrompido = conjunto
 * vazio (tudo reaparece como novo — erra para o lado de avisar).
 */
export function lerVistos(armazem: Pick<Storage, "getItem"> | null | undefined): string[] | null {
  try {
    if (!armazem) return null;
    const bruto = armazem.getItem(CHAVE_AVISOS_VISTOS);
    if (bruto == null) return [];
    const lido: unknown = JSON.parse(bruto);
    return Array.isArray(lido) ? lido.filter((x): x is string => typeof x === "string") : [];
  } catch (e) {
    // getItem que lança = indisponível; JSON.parse que lança = corrompido.
    return e instanceof SyntaxError ? [] : null;
  }
}

/** Acrescenta chaves ao visto, sem duplicar e guardando só as `TETO_DE_VISTOS` mais recentes. */
export function unirVistos(atuais: readonly string[], novas: readonly string[]): string[] {
  const semNovas = atuais.filter((c) => !novas.includes(c));
  return [...semNovas, ...new Set(novas)].slice(-TETO_DE_VISTOS);
}

/** Devolve `false` se o navegador recusou (o visto vale só até recarregar). */
export function gravarVistos(armazem: Pick<Storage, "setItem"> | null | undefined, vistos: readonly string[]): boolean {
  try {
    if (!armazem) return false;
    armazem.setItem(CHAVE_AVISOS_VISTOS, JSON.stringify(vistos));
    return true;
  } catch {
    return false;
  }
}

/** Quantos avisos ainda não foram vistos. Visto indisponível (`null`) = todos contam. */
export function contarNaoVistos(avisos: readonly Aviso[], vistos: readonly string[] | null): number {
  if (vistos == null) return avisos.length;
  const v = new Set(vistos);
  return avisos.filter((a) => !v.has(a.chave)).length;
}

/** Nome acessível do sino: o número entra no nome; leitura com falha NÃO leva número. */
export function nomeDoSino(estado: "carregando" | "ok" | "erro", naoVistos: number): string {
  if (estado === "erro") return "Avisos de processamento: não foi possível ver os avisos";
  if (estado === "carregando" || naoVistos === 0) return "Avisos de processamento";
  return `Avisos de processamento: ${naoVistos} ${naoVistos === 1 ? "novo" : "novos"}`;
}
