// AVISOS DE PROCESSAMENTO — regras puras do sino da barra superior. Sem React e sem `window`:
// o que se prova em `scripts/verificar-mensagem-de-falha.mts` mora aqui; o componente só chama.
//
// DE ONDE VEM O ESTADO (sem migration): `lote_execucao` (0115 + 0156), `execucao_falha` (0108) e
// as pendências `documento_nao_extraido` (0112). O que a tela PODE afirmar, e só isto:
//   • `fechado_em` preenchido = a cadeia do n8n chegou ao fim. NÃO é "tudo foi extraído certo"
//     (a cobertura é outra pergunta, da tela de Qualidade) — por isso o rótulo é "processamento
//     concluído", nunca "dados prontos". Se o caso tem pendência ABERTA `documento_nao_extraido`
//     (a extração nunca foi chamada para um documento registrado), o aviso diz isso e a quantidade:
//     `documentos_com_falha` só conta os que VOLTARAM da extração, então sozinho deixaria passar
//     como "concluído" um lote que perdeu documentos (o V45: 16 de 35). A contagem é do CASO, e só
//     entra no lote fechado mais recente dele — o `documentos` (realizado) contra
//     `documentos_planejados` NÃO serve: um conta itens que chegaram ao resumo, o outro itens que
//     passaram pelo `Lote cabe?`, e nada no gerador prova que a unidade é a mesma (ZIP, fatiamento);
//   • `fechado_em` nulo + mais tempo que a janela da tela de upload (`janelaPara`) = DEMORANDO,
//     nunca "parado". Na tela de upload estourar a janela só significa "demorou"; o "parado" de
//     lá vem de FALTA DE PROGRESSO, e `lote_execucao` não tem sinal de progresso. Um lote lento e
//     vivo (44 documentos em 1h28, #7723) passaria por "parado" e empurraria o reenvio. A janela
//     ganha `TOLERANCIA_DO_RELOGIO_MS`: o `agora` é do relógio do navegador, e um relógio adiantado
//     faz o lote parecer mais velho do que é;
//   • `fechado_em` nulo + dentro da janela = em andamento: NÃO é aviso;
//   • `fechado_em` nulo + plano desconhecido (`documentos_planejados` nulo) = a tela NÃO sabe o
//     tamanho do lote, logo não sabe a janela: diz "sem confirmação de término".
// Falha antes de o lote existir (orçamento recusou, nó morto no começo) só deixa linha em
// `execucao_falha` — por isso as duas fontes entram. O MESMO acontecimento pode deixar duas linhas
// lá: `Registrar Recusa` grava a recusa (`detalhe` nulo) e o `Abortar Lote` derruba a execução, que
// o Error Workflow grava de novo (com `detalhe.execucao_id`). Deduplicamos por `execucao_id` quando
// existe e, quando a recusa não o tem, por caso + mensagem idêntica numa janela curta. E um lote
// cujo `execucao_ref` é o `execucao_id` de uma falha NÃO vira "demorando": a falha já diz o que houve.
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

/** O mesmo acontecimento gravado duas vezes (recusa + Error Workflow) cai a poucos segundos; 5 min é folga. */
export const JANELA_DA_DUPLICATA_MS = 5 * 60_000;
export const TOLERANCIA_DO_RELOGIO_MS = 5 * 60_000;
export const MAX_DETALHE_DA_FALHA = 240;

export interface LoteLido {
  id: string;
  execucao_ref: string | null;
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
  /** O join `caso(nome)`: o nome ATUAL do mandato, que vale mais que `caso_nome` (o digitado no formulário). */
  caso?: { nome: string | null } | { nome: string | null }[] | null;
  etapa: string;
  mensagem: string | null;
  detalhe: { execucao_id?: string | number | null } | null;
  criado_em: string;
}

export type TipoDeAviso =
  | "concluido" | "concluido_com_falhas" | "concluido_com_nao_lidos" | "demorando" | "sem_confirmacao" | "falha";

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
  concluido_com_nao_lidos: "Concluído, com documentos não lidos",
  demorando: "Demorando mais que o previsto — sem confirmação de término",
  sem_confirmacao: "Sem confirmação de término",
  falha: "Falha no processamento",
};

/**
 * Os tipos que pedem ação — a tela os destaca com texto, não só com cor. "Demorando" e "sem
 * confirmação" NÃO: não há prova de problema, e o "Atenção" empurraria o reenvio de um lote vivo.
 */
export function pedeAtencao(tipo: TipoDeAviso): boolean {
  return tipo === "falha" || tipo === "concluido_com_falhas" || tipo === "concluido_com_nao_lidos";
}

/**
 * `null` = lote em andamento (não é aviso). `naoLidos` = documentos do caso com pendência aberta
 * `documento_nao_extraido` (só passa o lote fechado mais recente do caso — ver `montarAvisos`).
 */
export function classificarLote(l: LoteLido, agoraMs: number, naoLidos = 0): TipoDeAviso | null {
  if (l.fechado_em) {
    if ((l.documentos_com_falha ?? 0) > 0) return "concluido_com_falhas";
    return naoLidos > 0 ? "concluido_com_nao_lidos" : "concluido";
  }
  const abertoMs = Date.parse(l.criado_em);
  if (!Number.isFinite(abertoMs)) return "sem_confirmacao";
  if (l.documentos_planejados == null) return "sem_confirmacao";
  return agoraMs - abertoMs > janelaPara(l.documentos_planejados) + TOLERANCIA_DO_RELOGIO_MS ? "demorando" : null;
}

function nomeDoCaso(c: { caso: LoteLido["caso"] }): string | null {
  const j = Array.isArray(c.caso) ? c.caso[0] : c.caso;
  return j?.nome ?? null;
}

const plural = (n: number, um: string, varios: string) => `${n} ${n === 1 ? um : varios}`;

function detalheDoLote(tipo: TipoDeAviso, l: LoteLido, naoLidos: number): string | null {
  const nl = naoLidos > 0 ? `${plural(naoLidos, "documento registrado sem extração", "documentos registrados sem extração")} neste mandato` : null;
  if (tipo === "concluido_com_falhas") {
    const n = l.documentos_com_falha ?? 0;
    return `${plural(n, "documento com falha", "documentos com falha")}${nl ? `; ${nl}` : ""}; abra o mandato para ver quais`;
  }
  if (tipo === "concluido_com_nao_lidos") {
    return `${nl}: a extração nunca foi chamada para eles e o book sai sem as linhas deles; veja as pendências do mandato`;
  }
  if (tipo === "demorando") {
    return "O lote passou do tempo previsto para o tamanho dele e não registrou o fim. Pode estar só lento: abra o mandato e confira o que já foi lido antes de enviar de novo";
  }
  if (tipo === "sem_confirmacao") return "O lote não registrou o fim e o tamanho previsto não é conhecido";
  return null;
}

/** Mensagem da falha como o pipeline a gravou, limitada; vazia = texto neutro que NÃO afirma o que foi lido. */
function detalheDaFalha(f: FalhaLida): string {
  const m = (f.mensagem ?? "").trim().replace(/\s+/g, " ");
  if (!m) return "O processamento falhou e não deixou mensagem; abra o mandato para conferir";
  return m.length > MAX_DETALHE_DA_FALHA ? `${m.slice(0, MAX_DETALHE_DA_FALHA - 1)}…` : m;
}

const idDaExecucao = (f: FalhaLida): string | null => {
  const id = f.detalhe?.execucao_id;
  return id == null || id === "" ? null : String(id);
};

/** Tira a falha que é o mesmo acontecimento de outra mais recente. Entrada já ordenada, mais nova primeiro. */
function semDuplicatas(falhas: readonly FalhaLida[]): FalhaLida[] {
  const mantidas: FalhaLida[] = [];
  for (const f of falhas) {
    const ex = idDaExecucao(f);
    const t = Date.parse(f.criado_em) || 0;
    const dup = mantidas.some((m) => {
      const mex = idDaExecucao(m);
      if (ex != null && mex != null) return ex === mex;
      const mesmoCaso = (f.caso_id ?? f.caso_nome ?? "") !== "" && (f.caso_id ?? f.caso_nome) === (m.caso_id ?? m.caso_nome);
      const mesmaMsg = (f.mensagem ?? "").trim() !== "" && (f.mensagem ?? "").trim() === (m.mensagem ?? "").trim();
      return mesmoCaso && mesmaMsg && Math.abs(t - (Date.parse(m.criado_em) || 0)) <= JANELA_DA_DUPLICATA_MS;
    });
    if (!dup) mantidas.push(f);
  }
  return mantidas;
}

/**
 * `naoLidosPorCaso`: pendências abertas `documento_nao_extraido` por caso (contagem). Vazio/omitido =
 * nenhuma conhecida. A leitura que falhou NÃO chega aqui: o componente vira "erro" (nunca "zero").
 */
export function montarAvisos(
  lotes: readonly LoteLido[], falhas: readonly FalhaLida[], agoraMs: number,
  naoLidosPorCaso: Readonly<Record<string, number>> = {},
): Aviso[] {
  const avisos: Aviso[] = [];
  const falhasSemDup = semDuplicatas([...falhas].sort((a, b) => (Date.parse(b.criado_em) || 0) - (Date.parse(a.criado_em) || 0)));
  const execucoesQueFalharam = new Set(falhasSemDup.map(idDaExecucao).filter((x): x is string => x != null));
  // Só o lote FECHADO mais recente de cada caso leva a contagem de não lidos (a pendência é do caso).
  const maisRecente = new Map<string, LoteLido>();
  for (const l of lotes) {
    if (!l.fechado_em) continue;
    const atual = maisRecente.get(l.caso_id);
    if (!atual || (Date.parse(l.fechado_em) || 0) > (Date.parse(atual.fechado_em ?? "") || 0)) maisRecente.set(l.caso_id, l);
  }
  for (const l of lotes) {
    const naoLidos = maisRecente.get(l.caso_id)?.id === l.id ? (naoLidosPorCaso[l.caso_id] ?? 0) : 0;
    const tipo = classificarLote(l, agoraMs, naoLidos);
    if (!tipo) continue;
    // Execução que já tem falha registrada: "demorando" seria ruído em cima de um fato.
    if (!l.fechado_em && l.execucao_ref != null && execucoesQueFalharam.has(String(l.execucao_ref))) continue;
    avisos.push({
      chave: `lote:${l.id}:${tipo}`, tipo, rotulo: ROTULO_DO_TIPO[tipo], detalhe: detalheDoLote(tipo, l, naoLidos),
      casoId: l.caso_id, casoNome: nomeDoCaso(l),
      // Concluído: a hora em que fechou. Demorando/sem confirmação: quando abriu (não há fim).
      quando: l.fechado_em ?? l.criado_em,
    });
  }
  for (const f of falhasSemDup) {
    avisos.push({
      chave: `falha:${f.id}`, tipo: "falha", rotulo: ROTULO_DO_TIPO.falha, detalhe: detalheDaFalha(f),
      casoId: f.caso_id, casoNome: nomeDoCaso({ caso: f.caso ?? null }) ?? f.caso_nome, quando: f.criado_em,
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

/**
 * O visto que vale na tela: o que o armazém tem MAIS o que foi marcado nesta página e o navegador
 * recusou gravar (`memoria`). Sem isso, o recarregar de 60 s relia o armazém — sem a marca recusada —
 * e o aviso voltava a "Novo" sozinho. `lido` nulo (armazém indisponível) com memória vazia continua
 * nulo ("não sei"); com memória, vale o que se marcou aqui.
 */
export function vistosEfetivos(lido: readonly string[] | null, memoria: readonly string[]): string[] | null {
  if (lido == null) return memoria.length > 0 ? [...memoria] : null;
  return memoria.length > 0 ? unirVistos(lido, memoria) : [...lido];
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
