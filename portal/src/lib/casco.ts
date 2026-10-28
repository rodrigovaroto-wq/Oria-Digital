// REGRAS PURAS DO CASCO (barra superior, barra inferior do celular, modo discrição).
// Sem React e sem `window`: o que dá para provar em `scripts/verificar-mensagem-de-falha.mts`
// mora aqui; o que toca o navegador (`BotaoDiscricao`, `BarraInferior`) só chama estas funções.

// ---------------------------------------------------------------------------
// MODO DISCRIÇÃO — borra número financeiro para usar o portal com terceiros na sala.
// ---------------------------------------------------------------------------

export const CHAVE_DISCRICAO = "oria.discricao";
/** Atributo no `<html>`; o CSS (`globals.css`) borra `.valor-sensivel` quando ele existe. */
export const ATRIBUTO_DISCRICAO = "data-discricao";

/** Só o texto "1" liga. Ausente, vazio, "true", lixo: desligado — o padrão é mostrar. */
export function discricaoLigada(bruto: string | null | undefined): boolean {
  return bruto === "1";
}

/** Lê a preferência. Armazenamento bloqueado (janela privada) ou ausente = desligado, nunca exceção. */
export function lerDiscricao(armazem: Pick<Storage, "getItem"> | null | undefined): boolean {
  try {
    return discricaoLigada(armazem?.getItem(CHAVE_DISCRICAO));
  } catch {
    return false;
  }
}

/** Grava a preferência; devolve `false` se o navegador recusou (vale só até recarregar). */
export function gravarDiscricao(
  armazem: Pick<Storage, "setItem"> | null | undefined,
  ligada: boolean,
): boolean {
  try {
    if (!armazem) return false;
    armazem.setItem(CHAVE_DISCRICAO, ligada ? "1" : "0");
    return true;
  } catch {
    return false;
  }
}

/**
 * Script inline do `<head>` raiz: liga o atributo ANTES da primeira pintura. Sem ele, quem ligou
 * o modo ontem veria os números nítidos por um instante a cada carga — o pior momento, porque
 * é justo o da tela sendo aberta diante dos terceiros. Fica aqui, e não escrito no `layout.tsx`,
 * para o teste executar EXATAMENTE a string que vai para o HTML.
 */
export const SCRIPT_DISCRICAO_ANTES_DA_PINTURA =
  `try{if(localStorage.getItem(${JSON.stringify(CHAVE_DISCRICAO)})==="1")` +
  `document.documentElement.setAttribute(${JSON.stringify(ATRIBUTO_DISCRICAO)},"")}catch(e){}`;

// ---------------------------------------------------------------------------
// BARRA INFERIOR DO CELULAR (< 640px)
// ---------------------------------------------------------------------------

/** A busca global abre por este evento: o gatilho da barra inferior fica fora do componente dela. */
export const EVENTO_ABRIR_BUSCA = "oria:abrir-busca";

export type DestinoDaBarra = "inicio" | "mandatos" | "novo" | "mais";

const ID_DO_CASO = /^\/casos\/([0-9a-f-]{36})(?:\/|$)/i;

/** O id do mandato na URL (`/casos/{uuid}/…`), em minúsculas; `null` fora de um mandato. */
export function idDoCaso(caminho: string): string | null {
  return ID_DO_CASO.exec(caminho)?.[1]?.toLowerCase() ?? null;
}

/**
 * Qual destino da barra inferior está ATIVO. Busca nunca é destino (abre um diálogo, não uma
 * página). "Mais" é o que a barra não nomeia — hoje, a Administração; um mandato aberto marca
 * "Mandatos", porque é daquela lista que se chegou nele. Barra final e consulta (`?q=`) não
 * mudam a resposta; rota desconhecida = nenhum ativo, nunca um chute.
 */
export function destinoAtivo(caminho: string): DestinoDaBarra | null {
  let limpo = caminho.split(/[?#]/)[0];
  while (limpo.length > 1 && limpo.endsWith("/")) limpo = limpo.slice(0, -1);
  if (limpo === "/casos") return "inicio";
  if (limpo === "/casos/novo") return "novo";
  if (limpo === "/casos/todos" || idDoCaso(limpo) !== null) return "mandatos";
  if (limpo === "/administracao" || limpo.startsWith("/administracao/")) return "mais";
  return null;
}
