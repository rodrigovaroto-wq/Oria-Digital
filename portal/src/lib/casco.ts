// REGRAS PURAS DO CASCO (barra superior, barra inferior do celular, modo discrição).
// Sem React e sem `window`: o que dá para provar em `scripts/verificar-mensagem-de-falha.mts`
// mora aqui; o que toca o navegador (`BotaoDiscricao`, `BarraInferior`) só chama estas funções.

// ---------------------------------------------------------------------------
// MODO DISCRIÇÃO — borra número financeiro para usar o portal com terceiros na sala.
// ---------------------------------------------------------------------------

/**
 * O `localStorage` do navegador, ou `null` quando o acesso à PROPRIEDADE lança. Com os dados de site
 * bloqueados o Chrome lança `SecurityError` já em `window.localStorage` — antes de qualquer
 * `getItem` — e um `lerX(window.localStorage)` quebra no ARGUMENTO, fora do try da função que lê.
 * Todo componente passa por aqui; `verificar-mensagem-de-falha.mts` reprova `.tsx` que acesse direto.
 */
export function armazem(): Storage | null {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

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
// TEMA — Claro · Escuro · Sistema (Fase 4). O mesmo padrão do modo discrição: preferência no
// localStorage, atributo no <html> ligado por script do <head> ANTES da pintura.
// ---------------------------------------------------------------------------

export const CHAVE_TEMA = "oria.tema";
/** Atributo no `<html>`; o CSS (`globals.css`) redefine as cores em `html[data-tema="escuro"]`. */
export const ATRIBUTO_TEMA = "data-tema";
export const CONSULTA_TEMA_ESCURO = "(prefers-color-scheme: dark)";

export type PreferenciaDeTema = "claro" | "escuro" | "sistema";
export type TemaEfetivo = "claro" | "escuro";
export const PREFERENCIAS_DE_TEMA: readonly PreferenciaDeTema[] = ["claro", "escuro", "sistema"];

/** Só os três textos valem. Ausente, vazio ou lixo: "sistema" — o padrão é seguir o aparelho. */
export function preferenciaDeTema(bruto: string | null | undefined): PreferenciaDeTema {
  return bruto === "claro" || bruto === "escuro" ? bruto : "sistema";
}

/** Lê a preferência. Armazenamento bloqueado ou ausente = "sistema", nunca exceção. */
export function lerPreferenciaDeTema(armazem: Pick<Storage, "getItem"> | null | undefined): PreferenciaDeTema {
  try {
    return preferenciaDeTema(armazem?.getItem(CHAVE_TEMA));
  } catch {
    return "sistema";
  }
}

/** Grava a preferência; devolve `false` se o navegador recusou (vale só até recarregar). */
export function gravarPreferenciaDeTema(
  armazem: Pick<Storage, "setItem"> | null | undefined,
  preferencia: PreferenciaDeTema,
): boolean {
  try {
    if (!armazem) return false;
    armazem.setItem(CHAVE_TEMA, preferencia);
    return true;
  } catch {
    return false;
  }
}

/** O tema que vale agora: a escolha explícita, ou o do aparelho quando a escolha é "sistema". */
export function temaEfetivo(preferencia: PreferenciaDeTema, sistemaEscuro: boolean): TemaEfetivo {
  if (preferencia === "sistema") return sistemaEscuro ? "escuro" : "claro";
  return preferencia;
}

/**
 * Script inline do `<head>` raiz: grava `data-tema` ANTES da primeira pintura (sem ele, quem usa o
 * escuro veria a folha creme piscar a cada carga). Os dois acessos — armazenamento e
 * `matchMedia` — têm try próprio: janela privada que bloqueia o localStorage não pode fazer o
 * aparelho em modo escuro cair no claro. Em IIFE: sem ela `p` e `d` viravam globais da página.
 * Fica aqui para o teste executar EXATAMENTE a string do HTML.
 */
export const SCRIPT_TEMA_ANTES_DA_PINTURA =
  `(function(){var p=null,d=false;` +
  `try{p=localStorage.getItem(${JSON.stringify(CHAVE_TEMA)})}catch(e){}` +
  `try{d=matchMedia(${JSON.stringify(CONSULTA_TEMA_ESCURO)}).matches}catch(e){}` +
  `try{document.documentElement.setAttribute(${JSON.stringify(ATRIBUTO_TEMA)},` +
  `p==="claro"||p==="escuro"?p:d?"escuro":"claro")}catch(e){}})()`;

/** Aplica o tema efetivo no <html> (cliente): a escolha no menu e a mudança do aparelho passam por aqui. */
export function aplicarTema(
  raiz: Pick<HTMLElement, "setAttribute">,
  preferencia: PreferenciaDeTema,
  sistemaEscuro: boolean,
): TemaEfetivo {
  const tema = temaEfetivo(preferencia, sistemaEscuro);
  raiz.setAttribute(ATRIBUTO_TEMA, tema);
  return tema;
}

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

const semBarraFinal = (c: string) => {
  let l = c.split(/[?#]/)[0];
  while (l.length > 1 && l.endsWith("/")) l = l.slice(0, -1);
  return l.toLowerCase();
};

/**
 * `aria-current` de um link da barra inferior. "page" só quando o caminho É o do link; estar
 * numa subpágina dele (`/casos/{id}/pendencias` sobre o link do mandato, `/administracao/custos`
 * sobre o da Administração) é "true" — "a seção atual", não "a página atual". Dizer "page" nos dois
 * casos faz o leitor de tela anunciar "página atual" num link que levaria a OUTRA página.
 * `ativo` falso = sem atributo.
 */
export function ariaCurrentDoLink(href: string, caminho: string, ativo: boolean): "page" | "true" | undefined {
  if (!ativo) return undefined;
  return semBarraFinal(href) === semBarraFinal(caminho) ? "page" : "true";
}

/**
 * Para onde o foco volta ao FECHAR a busca. O gatilho do cabeçalho fica oculto abaixo de 640px
 * (`hidden sm:flex`): quem abriu pela barra inferior, ao fechar, perdia o foco no `<body>`. Volta
 * ao elemento que abriu, se ele ainda está na página e não é o `<body>`; senão, ao gatilho.
 */
export function alvoDoRetornoDeFoco<T extends { isConnected: boolean }>(
  origem: T | null | undefined,
  corpo: unknown,
  gatilho: T | null | undefined,
): T | null | undefined {
  return origem && origem !== corpo && origem.isConnected ? origem : gatilho;
}
