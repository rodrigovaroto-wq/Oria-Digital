// "NOVO MANDATO" EM DOIS PASSOS, sem rascunho: o passo 1 CRIA o caso (nome) e
// redireciona para a tela de adicionar arquivos com `?passo=2`; o que mostra o
// cabeçalho "Passo 2 de 2" é só esse parâmetro. Estado guardado em lugar nenhum:
// recarregar a página, voltar ou abrir o link em outra aba dão a mesma tela.
//
// O PARÂMETRO É CONSELHO DE APRESENTAÇÃO, NUNCA PERMISSÃO. Valor que não é
// exatamente "2" (ausente, "3", lixo, lista) cai na tela comum de adicionar
// arquivos — o cabeçalho de passo nunca aparece por acaso.

export const TOTAL_DE_PASSOS = 2;

export type CabecalhoDoPasso = {
  passo: number;
  total: number;
  rotulo: string;
  /** O mandato já existia com esse nome: os arquivos SOMAM, não abrem um mandato novo. */
  jaExistia: boolean;
};

type Parametro = string | string[] | undefined;

export function cabecalhoDoPasso(sp: { passo?: Parametro; existente?: Parametro }): CabecalhoDoPasso | null {
  if (sp.passo !== "2") return null;
  return { passo: 2, total: TOTAL_DE_PASSOS, rotulo: "Documentos", jaExistia: sp.existente === "1" };
}

export function textoDoPasso(c: Pick<CabecalhoDoPasso, "passo" | "total">): string {
  return `Passo ${c.passo} de ${c.total}`;
}

export function hrefDoPasso2(casoId: string, jaExistia: boolean): string {
  return `/casos/${encodeURIComponent(casoId)}/adicionar?passo=2${jaExistia ? "&existente=1" : ""}`;
}

/** O nome que o passo 1 aceita. Em branco não cria mandato: `fn_upsert_caso('')` criaria um sem nome. */
export function validarNomeDoMandato(bruto: unknown): { ok: true; nome: string } | { ok: false; motivo: string } {
  const nome = typeof bruto === "string" ? bruto.trim() : "";
  if (!nome) return { ok: false, motivo: "Informe o nome do mandato para continuar." };
  return { ok: true, nome };
}
