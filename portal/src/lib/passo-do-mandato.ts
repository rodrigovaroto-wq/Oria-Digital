// "NOVO MANDATO" EM DOIS PASSOS, sem rascunho: o passo 1 CRIA o caso (nome) e
// redireciona para a tela de adicionar arquivos com `?passo=2`; o que mostra o
// cabeçalho "Passo 2 de 2" é só esse parâmetro. Estado guardado em lugar nenhum:
// recarregar a página, voltar ou abrir o link em outra aba dão a mesma tela.
//
// O PARÂMETRO É CONSELHO DE APRESENTAÇÃO, NUNCA PERMISSÃO. Valor que não é
// exatamente "2" (ausente, "3", lixo, lista) cai na tela comum de adicionar
// arquivos — o cabeçalho de passo nunca aparece por acaso.

export const TOTAL_DE_PASSOS = 2;

// O QUE A CONSULTA PRÉVIA POR NOME SABE. Quatro estados, não dois: "não conferido" (a consulta deu
// erro, timeout ou RLS) NÃO é "não existia" — tratar como não existia deixava o analista achar que
// abriu um mandato novo quando `fn_upsert_caso` pode ter reaproveitado o antigo (regra 1: ausência
// da resposta não é resposta "não"). Vai no href como `existente`: "1", "f" (fechado), "?" (não
// conferido); ausente = a consulta rodou e não achou.
export type SituacaoPrevia = "novo" | "existia" | "existia_fechado" | "nao_conferido";

const PARAM_DA_SITUACAO: Record<SituacaoPrevia, string | null> = {
  novo: null, existia: "1", existia_fechado: "f", nao_conferido: "?",
};

export type CabecalhoDoPasso = {
  passo: number;
  total: number;
  rotulo: string;
  /** O mandato já existia com esse nome: os arquivos SOMAM, não abrem um mandato novo. */
  jaExistia: boolean;
  situacao: SituacaoPrevia;
};

type Parametro = string | string[] | undefined;

export function cabecalhoDoPasso(sp: { passo?: Parametro; existente?: Parametro }): CabecalhoDoPasso | null {
  if (sp.passo !== "2") return null;
  const situacao: SituacaoPrevia =
    sp.existente === "1" ? "existia" : sp.existente === "f" ? "existia_fechado" : sp.existente === "?" ? "nao_conferido" : "novo";
  return { passo: 2, total: TOTAL_DE_PASSOS, rotulo: "Documentos", jaExistia: situacao === "existia" || situacao === "existia_fechado", situacao };
}

/** Resposta da consulta prévia (`caso` por nome) -> situação. `error` nunca vira "novo". */
export function situacaoPrevia(
  r: { data: Array<{ fechado_em?: string | null }> | null; error: unknown },
): SituacaoPrevia {
  if (r.error || !Array.isArray(r.data)) return "nao_conferido";
  if (r.data.length === 0) return "novo";
  return r.data.some((c) => !c.fechado_em) ? "existia" : "existia_fechado";
}

/** O aviso do passo 2 para cada situação; null quando o mandato é novo (nada a avisar). */
export function avisoDoPasso(s: SituacaoPrevia): string | null {
  switch (s) {
    case "existia":
      return "Já existia um mandato com este nome: os arquivos entram nele, somando ao que já há — não foi criado um mandato novo.";
    case "existia_fechado":
      return "Já existia um mandato com este nome e ele está FECHADO: os arquivos entram nele, somando ao que já há — não foi criado um mandato novo. Reabra-o se a entrada de arquivos novos não era o esperado.";
    case "nao_conferido":
      return "Não foi possível conferir se já havia um mandato com este nome — se havia, os arquivos entram nele.";
    default:
      return null;
  }
}

export function textoDoPasso(c: Pick<CabecalhoDoPasso, "passo" | "total">): string {
  return `Passo ${c.passo} de ${c.total}`;
}

export function hrefDoPasso2(casoId: string, situacao: SituacaoPrevia): string {
  const param = PARAM_DA_SITUACAO[situacao];
  return `/casos/${encodeURIComponent(casoId)}/adicionar?passo=2${param ? `&existente=${encodeURIComponent(param)}` : ""}`;
}

/** O nome que o passo 1 aceita. Em branco não cria mandato: `fn_upsert_caso('')` criaria um sem nome. */
export function validarNomeDoMandato(bruto: unknown): { ok: true; nome: string } | { ok: false; motivo: string } {
  const nome = typeof bruto === "string" ? bruto.trim() : "";
  if (!nome) return { ok: false, motivo: "Informe o nome do mandato para continuar." };
  return { ok: true, nome };
}
