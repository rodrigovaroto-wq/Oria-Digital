// O SALVAMENTO ÚNICO DA SEÇÃO 3 DA MODELAGEM — as regras puras, fora do componente.
//
// POR QUE ISTO NÃO MORA EM `EditorLinhas.tsx`: a tela tinha um botão "salvar esta seção" no
// cabeçalho E no rodapé de CADA seção (a Modelagem do caso real tem de 8 a 12 seções), e o aviso
// "N alteração(ões) ainda NÃO salva(s)" também era por seção. Quem editava três seções tinha de
// achar três botões; quem saía sem achar um perdia a escolha em silêncio. Agora há UMA barra, e
// o que ela promete ("salvar tudo") tem regras que o `verificar-modelagem-cobertura.mts` mede:
//
//   • o lote leva EXATAMENTE as linhas que mudaram, de todas as seções — nenhuma linha intocada
//     (reenviar a linha deliberadamente "não projetar" gravaria uma decisão que ninguém tomou);
//   • seção sem mudança não gera chamada;
//   • o resultado é HONESTO: se uma seção falhou, o resumo é de erro, diz quais salvaram e quais
//     não, e a seção que falhou continua "não salva" — nunca "salvo" por contaminação das outras.
//
// (O "gravado" vem do servidor — ver `escolhasVisiveis` abaixo.)
// O servidor não mudou: cada seção do lote vai à mesma ação `salvarSecao` (que chama
// `fn_vincular_linha_premissa` por linha), com os mesmos campos `orig__i` de antes.

export interface EscolhaLinha {
  premissa: string;
  sazonalidade: string;
}

export interface LinhaEditavel {
  rotulo_norm: string;
  /** o rótulo exibido, é o que `fn_vincular_linha_premissa` recebe como `p_rotulo` */
  chave: string;
  entidade: string | null;
  papel: string;
}

export interface SecaoEditavel {
  /** chave canônica; "(sem seção canônica)" vai ao banco como NULL */
  secao: string;
  rotulo: string;
  linhas: LinhaEditavel[];
}

export type EscolhasPorSecao = Record<string, Record<string, EscolhaLinha>>;

export const SEM_SECAO = "(sem seção canônica)";

export interface LinhaDoLote extends LinhaEditavel {
  novo: EscolhaLinha;
  orig: EscolhaLinha;
}

export interface LoteDaSecao {
  secao: string;
  rotulo: string;
  linhas: LinhaDoLote[];
}

export interface ResultadoDaSecao {
  tom: "ok" | "erro";
  texto: string;
}

const VAZIA: EscolhaLinha = { premissa: "", sazonalidade: "" };

export function linhaSuja(e: EscolhaLinha | undefined, g: EscolhaLinha | undefined): boolean {
  const a = e ?? VAZIA;
  const b = g ?? VAZIA;
  return a.premissa !== b.premissa || a.sazonalidade !== b.sazonalidade;
}

/** As linhas que mudaram, por seção. Só `conta` tem seletor, então só `conta` entra. */
export function lotesPendentes(
  secoes: SecaoEditavel[], escolhas: EscolhasPorSecao, gravado: EscolhasPorSecao,
): LoteDaSecao[] {
  const lotes: LoteDaSecao[] = [];
  for (const s of secoes) {
    const linhas: LinhaDoLote[] = [];
    for (const l of s.linhas) {
      if (l.papel !== "conta") continue;
      const novo = escolhas[s.secao]?.[l.rotulo_norm] ?? VAZIA;
      const orig = gravado[s.secao]?.[l.rotulo_norm] ?? VAZIA;
      if (linhaSuja(novo, orig)) linhas.push({ ...l, novo, orig });
    }
    if (linhas.length > 0) lotes.push({ secao: s.secao, rotulo: s.rotulo, linhas });
  }
  return lotes;
}

export function totalPendente(lotes: LoteDaSecao[]): number {
  return lotes.reduce((n, l) => n + l.linhas.length, 0);
}

/** Os campos que `salvarSecao` lê — só das linhas que mudaram, reindexadas de 0. */
export function formDataDoLote(lote: LoteDaSecao): FormData {
  const fd = new FormData();
  fd.set("secao_canonica", lote.secao === SEM_SECAO ? "" : lote.secao);
  lote.linhas.forEach((l, i) => {
    fd.set(`rotulo__${i}`, l.chave);
    fd.set(`entidade__${i}`, l.entidade ?? "");
    fd.set(`orig__${i}`, l.orig.premissa);
    fd.set(`origSaz__${i}`, l.orig.sazonalidade);
    fd.set(`premissa__${i}`, l.novo.premissa);
    fd.set(`sazonalidade__${i}`, l.novo.sazonalidade);
  });
  return fd;
}

// O "GRAVADO" É O QUE O SERVIDOR DEVOLVE, nunca o que foi enviado.
//
// ANTES: um `gravado` em estado de React era promovido com o que o lote ENVIOU, seção a seção,
// só quando a seção inteira voltava `ok`. `salvarSecao` grava umas linhas e recusa outras e
// devolve erro — então as linhas que o banco GRAVOU ficavam com o `gravado` antigo: "Descartar"
// as devolvia ao valor velho na tela enquanto o banco (e o Excel) guardavam o novo, a barra
// contava linha já gravada, e "Salvar tudo" a reenviava (trilha de decisão duplicada). E, como
// o estado local vencia o que o servidor mandava, remover uma premissa no passo 2 deixava o vínculo
// velho na tela como "salvo".
//
// AGORA: o estado local guarda só as EDIÇÕES do analista (`edicoes`), e tudo o mais lê do que o
// servidor mandou (as props, renovadas pelo `revalidatePath`). Linha suja = a escolha visível
// difere do que o servidor tem. Salvamento parcial deixa suja exatamente a linha recusada.

/** O que a tela mostra: o servidor, com as edições do analista por cima. */
export function escolhasVisiveis(
  servidor: EscolhasPorSecao, edicoes: EscolhasPorSecao,
): EscolhasPorSecao {
  return Object.fromEntries(Object.entries(servidor).map(
    ([secao, linhas]) => [secao, { ...linhas, ...edicoes[secao] }],
  ));
}

/** Registra uma edição; a que volta ao valor do servidor deixa de ser edição. */
export function registrarEdicao(
  edicoes: EscolhasPorSecao, servidor: EscolhasPorSecao, visivel: EscolhasPorSecao,
  secao: string, rotulo: string, campo: keyof EscolhaLinha, valor: string,
): EscolhasPorSecao {
  const nova = { ...(visivel[secao]?.[rotulo] ?? VAZIA), [campo]: valor };
  const sec = { ...edicoes[secao] };
  if (linhaSuja(nova, servidor[secao]?.[rotulo])) sec[rotulo] = nova; else delete sec[rotulo];
  return { ...edicoes, [secao]: sec };
}

/**
 * Descarta a edição que o servidor já alcançou (salvou) ou ultrapassou (a premissa foi removida
 * no passo 2): sem isso a edição velha, igual ao valor de antes, reapareceria como "não salva".
 */
export function podarEdicoes(
  edicoes: EscolhasPorSecao, servidor: EscolhasPorSecao,
): EscolhasPorSecao {
  return Object.fromEntries(Object.entries(edicoes).map(([secao, linhas]) => [
    secao, Object.fromEntries(Object.entries(linhas).filter(
      ([rot, e]) => linhaSuja(e, servidor[secao]?.[rot]),
    )),
  ]));
}

/** Quantas contas da seção têm premissa por linha NÃO salva que o lote em lote sobrescreveria. */
export function excecoesQueOLoteSubstitui(
  contas: ReadonlyArray<{ rotulo_norm: string }>,
  visivel: Record<string, EscolhaLinha> | undefined,
  servidor: Record<string, EscolhaLinha> | undefined,
  premissaDoLote: string,
): number {
  return contas.filter((l) => {
    const e = visivel?.[l.rotulo_norm]?.premissa ?? "";
    const g = servidor?.[l.rotulo_norm]?.premissa ?? "";
    return e !== g && e !== premissaDoLote;
  }).length;
}

export interface ResumoDoSalvamento {
  tom: "ok" | "erro";
  texto: string;
  /** as seções cujo resultado foi `ok` (só o texto as usa; o "gravado" vem do servidor) */
  secoesOk: string[];
}

/** O texto do salvamento. `ok` só quando TODAS as seções enviadas confirmaram. */
export function resumirSalvamento(
  feitos: { lote: LoteDaSecao; r: ResultadoDaSecao }[],
): ResumoDoSalvamento {
  const bons = feitos.filter((f) => f.r.tom === "ok");
  const ruins = feitos.filter((f) => f.r.tom !== "ok");
  const secoesOk = bons.map((f) => f.lote.secao);
  const nBoas = bons.reduce((n, f) => n + f.lote.linhas.length, 0);
  if (feitos.length === 0) {
    return { tom: "ok", texto: "Nada mudou — nada foi gravado.", secoesOk };
  }
  if (ruins.length === 0) {
    return {
      tom: "ok", secoesOk,
      texto: `${nBoas} linha(s) salva(s) em ${bons.length} seção(ões).`,
    };
  }
  const falhas = ruins.map((f) => `${f.lote.rotulo} — ${f.r.texto}`).join(" | ");
  const salvas = bons.length > 0
    ? `Salvas: ${bons.map((f) => f.lote.rotulo).join(", ")} (${nBoas} linha(s)). `
    : "Nenhuma seção foi salva. ";
  return {
    tom: "erro", secoesOk,
    texto: `${salvas}NÃO salvas (${ruins.length} de ${feitos.length} seção(ões)): ${falhas}`,
  };
}
