import { ehUuid } from "@/lib/equipe";
import { janelaPara } from "@/lib/espera-do-lote";
import { TETO_EXECUCAO_USD, orcamentoDoLote } from "../../../N8N/lib/custo.mjs";

// A FILA DE REPROCESSO: as regras puras (validar o pedido, decidir por documento se segue ou o
// motivo, as frases da tela). A rota (`api/casos/[id]/reprocessar`) e a tela chamam estas funções,
// e `verificar-fila-de-reprocesso.mts` as chama também — nenhuma cópia.
//
// A fila vem de `fn_fila_de_reprocesso` (0232): um documento com pendência `extracao_falhou` aberta.
// `reprocessavel` já é a decisão do BANCO (o original está no bucket E reenviar o mesmo arquivo
// re-extrairia). Aqui só se conferem duas coisas que o banco não garante a quem lê: o pedido é do
// que a fila mostra, e há `arquivo_ref` para baixar.

export type MotivoDeBloqueio = "sem_original" | "reaproveitaria";

export type ItemDaFila = {
  documento_id: string;
  documento_versao_id: string;
  n_versao: number;
  nome_original: string | null;
  arquivo_ref: string | null;
  tipo_taxonomia: string | null;
  falha_aberta_desde: string;
  falha_descricao: string | null;
  tem_linha: boolean;
  reprocessavel: boolean;
  motivo_bloqueio: MotivoDeBloqueio | null;
};

// TETO DE DOCUMENTOS POR PEDIDO. O fetch ao Form sai do SERVIDOR, então o limite de 4,5 MB da
// Vercel (só do corpo de ENTRADA, que aqui é um JSON de uuids) não se aplica ao multipart. O que
// limita é a memória da Function, que segura os originais baixados juntos: 25 × 15 MiB
// (`TETO_POR_ARQUIVO_BYTES`, o pior caso) = 375 MiB, abaixo do 1 GB padrão; e o n8n gasta ~50× o
// tamanho do arquivo. Medido em 10/11/2026: 517 documentos com falha aberta, 11 com o objeto no bucket,
// então 25 cobre a fila reprocessável inteira com folga. Acima disso a tela manda em levas.
export const TETO_DE_DOCUMENTOS_POR_PEDIDO = 25;

// JÁ ESTÁ EM LEITURA: versão criada há menos que isto e ainda sem extração gravada. É a janela que
// a própria tela espera por um pedido do tamanho do teto (`janelaPara(25)` = 32,5 min, derivada de
// 26 s por documento medidos): passado isso o acompanhamento declara parada, então antes disso
// reenviar pagaria a leitura duas vezes.
export const JANELA_EM_LEITURA_MS = janelaPara(TETO_DE_DOCUMENTOS_POR_PEDIDO);

export type CorpoValidado = { ok: true; documentoIds: string[] } | { ok: false; mensagem: string };

export function validarCorpo(corpo: unknown): CorpoValidado {
  const ids = (corpo as { documentoIds?: unknown } | null)?.documentoIds;
  if (!Array.isArray(ids) || ids.length === 0) {
    return { ok: false, mensagem: "Informe ao menos um documento (documentoIds)." };
  }
  if (ids.length > TETO_DE_DOCUMENTOS_POR_PEDIDO) {
    return { ok: false, mensagem: `Reprocesse no máximo ${TETO_DE_DOCUMENTOS_POR_PEDIDO} documentos por vez; o pedido trouxe ${ids.length}.` };
  }
  if (!ids.every(ehUuid)) return { ok: false, mensagem: "Identificador de documento inválido (uuid esperado)." };
  const limpos = ids.map((i) => (i as string).trim());
  if (new Set(limpos).size !== limpos.length) {
    return { ok: false, mensagem: "O pedido repete documentos; cada documento entra uma vez só." };
  }
  return { ok: true, documentoIds: limpos };
}

export type Frase = { motivo: string; oQueFazer: string };

export const FRASE_SEM_ORIGINAL: Frase = {
  motivo: "o arquivo não foi guardado",
  oQueFazer: "envie de novo pela aba Adicionar.",
};
export const FRASE_REAPROVEITARIA: Frase = {
  motivo: "a leitura já gravou linhas; reenviar o mesmo arquivo reaproveitaria a leitura sem corrigir",
  oQueFazer: "tratar na pendência.",
};

/** A frase do bloqueio. Motivo que o banco não nomeia (ou ausente) é dito como desconhecido, nunca omitido (regra 1). */
export function fraseDoBloqueio(motivo: string | null): Frase {
  if (motivo === "sem_original") return FRASE_SEM_ORIGINAL;
  if (motivo === "reaproveitaria") return FRASE_REAPROVEITARIA;
  return {
    motivo: "o sistema não conseguiu dizer por que este documento não pode ser reprocessado",
    oQueFazer: "avise o administrador do sistema.",
  };
}

const textoDaFrase = (f: Frase) => `${f.motivo}; ${f.oQueFazer}`;

export type Recusado = { documentoId: string; motivo: string };

/** O que a rota faz com cada documento pedido: segue (`seguem`, na ordem pedida) ou volta com o motivo. */
export function decidirPedido(
  documentoIds: readonly string[], fila: readonly ItemDaFila[], emLeitura: ReadonlySet<string> = new Set(),
): { seguem: ItemDaFila[]; recusados: Recusado[] } {
  const porId = new Map(fila.map((i) => [i.documento_id, i]));
  const seguem: ItemDaFila[] = [];
  const recusados: Recusado[] = [];
  for (const id of documentoIds) {
    const item = porId.get(id);
    if (!item) {
      recusados.push({ documentoId: id, motivo: "o documento não está na fila de reprocesso deste mandato (sem falha de leitura aberta)." });
    } else if (!item.reprocessavel) {
      recusados.push({ documentoId: id, motivo: textoDaFrase(fraseDoBloqueio(item.motivo_bloqueio)) });
    } else if (emLeitura.has(id)) {
      recusados.push({ documentoId: id, motivo: "já está em leitura (um envio recente ainda não terminou); aguarde terminar antes de reprocessar." });
    } else if (!item.arquivo_ref) {
      // O banco disse que dá, mas não há objeto a baixar: nada a reenviar.
      recusados.push({ documentoId: id, motivo: textoDaFrase(FRASE_SEM_ORIGINAL) });
    } else {
      seguem.push(item);
    }
  }
  return { seguem, recusados };
}

/** Download que falhou: o motivo por documento, sem derrubar os outros (objeto inexistente — defeito jul–out/2026). */
export function motivoDoDownload(detalhe: string): string {
  return `o arquivo guardado não pôde ser baixado do armazenamento (${detalhe}); envie de novo pela aba Adicionar.`;
}

/** Arquivo acima do teto por arquivo do n8n: ele recusaria o lote INTEIRO, então este fica de fora. */
export function motivoDeArquivoGrande(tamanho: string, teto: string): string {
  return `o arquivo tem ${tamanho} e o limite de leitura é ${teto}; envie de novo pela aba Adicionar, em partes menores.`;
}

export const FRASE_NENHUM_REPROCESSAVEL =
  "Nenhum dos documentos pedidos pode ser reprocessado agora; o motivo de cada um está na resposta.";

/** O nome que segue ao Form: o original, ou o último trecho do caminho guardado (traz a extensão que o n8n usa para ler). */
export function nomeParaEnvio(item: Pick<ItemDaFila, "nome_original" | "arquivo_ref" | "documento_id">): string {
  return item.nome_original?.trim() || item.arquivo_ref?.split("/").pop() || `documento-${item.documento_id}`;
}

/** Quais documentos estão em leitura: versão criada dentro da janela, sem evento de extração gravado. */
export function documentosEmLeitura(
  versoesRecentes: ReadonlyArray<{ id: string; documento_id: string }>, versoesComExtracao: ReadonlySet<string>,
): Set<string> {
  return new Set(versoesRecentes.filter((v) => !versoesComExtracao.has(v.id)).map((v) => v.documento_id));
}

// `bytes = null` no default faz o tsc inferir `null`; a função aceita o número (é o caminho por tamanho).
const orcamento = orcamentoDoLote as unknown as (o: { documentos: number; bytes: number; teto: number }) => { cabe: boolean };

/**
 * O ORÇAMENTO DO n8n, com a MESMA conta dele (`orcamentoDoLote`, por tamanho): o Form responde 200 ao
 * receber e o lote que passa do teto (US$ 3 por execução, ~US$ 1,48/MB) é recusado DEPOIS, sem ler nada.
 * Entra, na ordem do pedido, o que ainda cabe junto; o resto volta com o motivo. Uma chamada por
 * documento (os originais já têm nome; a segunda chamada de classificação por conteúdo, se houver, o
 * n8n ainda recusa e o acompanhamento mostra — teto conhecido).
 */
export function cortarPeloOrcamento<T extends { documentoId: string; bytes: number }>(
  arquivos: readonly T[],
): { cabem: T[]; recusados: Recusado[] } {
  const cabem: T[] = [];
  const recusados: Recusado[] = [];
  let bytes = 0;
  for (const a of arquivos) {
    if (orcamento({ documentos: cabem.length + 1, bytes: bytes + a.bytes, teto: TETO_EXECUCAO_USD }).cabe) {
      cabem.push(a);
      bytes += a.bytes;
    } else {
      recusados.push({ documentoId: a.documentoId, motivo: "passaria do orçamento de leitura por pedido; divida em pedidos menores." });
    }
  }
  return { cabem, recusados };
}

export type VeredictoDoReprocesso = {
  estado: "lendo" | "pronto" | "recusado";
  lidos: number;
  total: number;
  /** Por documento: `lido` = há versão nova COM extração gravada depois do envio; `lendo` = ainda não. */
  porDocumento: Array<{ documentoId: string; estado: "lido" | "lendo" }>;
  mensagem: string | null;
};

/**
 * O acompanhamento POR DOCUMENTO enviado (o do intake só vê documento NOVO, e o reprocesso cria versão
 * de documento antigo: nunca dispararia). "Lido" exige o sinal positivo — versão criada depois do envio
 * E evento de extração dela (regra 7). Falha registrada pelo n8n depois do envio e nenhum documento
 * lido: recusa do lote, e a mensagem diz que NADA foi lido (não "falhou de novo").
 */
export function veredictoDoReprocesso(
  documentoIds: readonly string[], versaoPorDocumento: ReadonlyMap<string, string[]>,
  versoesComExtracao: ReadonlySet<string>, falhaDoN8n: string | null,
): VeredictoDoReprocesso {
  const porDocumento = documentoIds.map((documentoId) => ({
    documentoId,
    estado: (versaoPorDocumento.get(documentoId) ?? []).some((v) => versoesComExtracao.has(v)) ? "lido" as const : "lendo" as const,
  }));
  const lidos = porDocumento.filter((d) => d.estado === "lido").length;
  const total = documentoIds.length;
  if (lidos === total) return { estado: "pronto", lidos, total, porDocumento, mensagem: null };
  if (falhaDoN8n) {
    const efeito = lidos === 0 ? "Nada foi lido." : `Só ${lidos} de ${total} foram lidos.`;
    return { estado: "recusado", lidos, total, porDocumento, mensagem: `O n8n recusou o envio: ${falhaDoN8n} ${efeito}` };
  }
  return { estado: "lendo", lidos, total, porDocumento, mensagem: null };
}
