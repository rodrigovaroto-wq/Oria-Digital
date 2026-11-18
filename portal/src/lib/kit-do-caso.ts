// O KIT BÁSICO DO MANDATO, lido de `fn_kit_do_caso` (migration 0300) — o estado de cada item nasce
// NO BANCO, derivado de `campo_extraido` na leitura, e as três telas que mostram o Kit (visão geral,
// aba Documentos, export) passam por AQUI. Duas implementações da mesma conta divergem sem erro nenhum.
//
// O DEFEITO que isto fecha (revisão independente do redesenho `3c9ad4f`, medido em produção): o % do
// Kit contava como "com conteúdo lido" o item atendido cujo `checklist_item_status` não era
// `recebido_nao_valido`. O checklist vira `presente` no REGISTRO do documento (0230) e fica assim se a
// extração nunca roda. Em 13 dos 81 mandatos o Kit dizia N > 0 "com conteúdo lido" com 0 documentos com
// linha; no pior caso ("teste v19") "100% de 8 itens com conteúdo lido" ao lado de "0 linhas extraídas".
//
// Contrato de falha (regra 1): erro da função, exceção ou ZERO linhas é "Kit NÃO LIDO" — nunca item
// faltante, nunca item completo. A função devolve zero linhas para mandato que o chamador não enxerga
// (RLS) e para mandato inexistente; "tudo faltante" seria afirmar o que ninguém mediu.
// Função AUSENTE (PGRST202 / 42883: banco sem a 0300, o dono aplica migration à mão) é outra coisa:
// cai em `itensDoKitBasicoAtendidos`, que só sabe "chegou" — e por isso o estado `recebido`, que NÃO
// conta como lido (a queda não sabe se alguém leu).

import { itensDoKitBasicoAtendidos, type ServicoDocumentoServeComo } from "./kit-basico";

export type EstadoDoItem =
  | "faltante" | "dispensado" | "aguardando_extracao" | "recebido_sem_linha"
  | "lido_sem_dado_por_natureza" | "extraido" | "conferido"
  // só na queda (banco sem a 0300): chegou, e ninguém mediu se foi lido
  | "recebido";

export type ItemDoKit = {
  codigo: string;
  documento: string;
  estado: EstadoDoItem;
  motivo: string | null;
  /** criado_em do documento mais antigo ainda sem leitura (só em `aguardando_extracao`) */
  aguardandoDesde: string | null;
  /** "N de M empresas": NULOS onde a função diz que a fração não faz sentido (granularidade caso/período) */
  empresasTotal: number | null;
  empresasAtendidas: number | null;
  conferidoPor: string | null;
  conferidoEm: string | null;
};

export type KitDoCaso = {
  origem: "fn_kit_do_caso" | "queda";
  itens: ItemDoKit[];
  /** último evento `completude_recomputada`; null = a conferência nunca rodou (só na função) */
  conferenciaEm: string | null;
  documentosDepoisDaConferencia: number | null;
};

export type LeituraDoKit =
  | { tipo: "lido"; kit: KitDoCaso }
  | { tipo: "nao_lido"; motivo: string };

type Resposta = { data: unknown; error: { code?: string; message: string } | null };
/** `supabase.rpc.bind(supabase)` no portal; um dublê em teste. */
export type ChamaRpc = (nome: string, args: Record<string, unknown>) => PromiseLike<Resposta>;

const funcaoAusente = (e: { code?: string }) => e.code === "PGRST202" || e.code === "42883";

/** Estados em que EXISTE linha lida (ou leitura concluída que, por natureza, não tem linha). */
const ESTADOS_LIDOS: ReadonlySet<EstadoDoItem> = new Set(["extraido", "conferido", "lido_sem_dado_por_natureza"]);
const texto = (v: unknown): string | null => (typeof v === "string" && v ? v : null);
const inteiro = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);

const ESTADOS_DA_FUNCAO = new Set<string>([
  "faltante", "dispensado", "aguardando_extracao", "recebido_sem_linha",
  "lido_sem_dado_por_natureza", "extraido", "conferido",
]);

type Linha = Record<string, unknown>;

/**
 * Lê `fn_kit_do_caso` e confere contra a lista do Kit. `ausente` é o único retorno que autoriza a
 * queda; tudo o mais que não deu uma resposta inteira é `nao_lido`.
 */
export async function lerKitDaFuncao(
  rpc: ChamaRpc, casoId: string, kitBasico: ReadonlyArray<{ codigo: string; documento: string }>,
): Promise<LeituraDoKit | { tipo: "ausente" }> {
  let resp: Resposta;
  try {
    resp = await rpc("fn_kit_do_caso", { p_caso: casoId });
  } catch (e) {
    return { tipo: "nao_lido", motivo: `fn_kit_do_caso lançou: ${e instanceof Error ? e.message : String(e)}` };
  }
  if (resp.error) {
    return funcaoAusente(resp.error)
      ? { tipo: "ausente" }
      : { tipo: "nao_lido", motivo: `fn_kit_do_caso falhou: ${resp.error.message}` };
  }
  const linhas = Array.isArray(resp.data) ? (resp.data as Linha[]) : [];
  if (linhas.length === 0) {
    return { tipo: "nao_lido", motivo: "fn_kit_do_caso devolveu zero linhas (mandato invisível ao usuário ou inexistente)" };
  }
  const porTipo = new Map(linhas.map((l) => [texto(l.tipo), l]));
  const itens: ItemDoKit[] = [];
  for (const k of kitBasico) {
    const l = porTipo.get(k.codigo);
    const estado = texto(l?.estado);
    // Item do Kit sem linha na resposta, ou com estado que este portal não conhece, não vira "faltante":
    // o Kit inteiro fica não lido (o banco e o portal discordam sobre a lista; dizer qual item é chute).
    if (!l || !estado || !ESTADOS_DA_FUNCAO.has(estado)) {
      return { tipo: "nao_lido", motivo: `fn_kit_do_caso sem resposta utilizável para ${k.codigo} (estado: ${estado ?? "ausente"})` };
    }
    itens.push({
      codigo: k.codigo, documento: k.documento, estado: estado as EstadoDoItem, motivo: texto(l.motivo),
      aguardandoDesde: texto(l.aguardando_desde),
      empresasTotal: inteiro(l.empresas_total), empresasAtendidas: inteiro(l.empresas_atendidas),
      conferidoPor: texto(l.conferido_por), conferidoEm: texto(l.conferido_em),
    });
  }
  const primeira = linhas[0];
  return {
    tipo: "lido",
    kit: {
      origem: "fn_kit_do_caso", itens,
      conferenciaEm: texto(primeira.conferencia_em),
      documentosDepoisDaConferencia: inteiro(primeira.documentos_depois_da_conferencia),
    },
  };
}

/**
 * A porta ÚNICA das três telas. Função primeiro; só se ela não existir, a queda (`documentos` e
 * `checklist` são o que a queda precisa, e as telas já os leem para outros fins).
 */
export async function lerKitDoCaso(e: {
  rpc: ChamaRpc;
  casoId: string;
  kit: { data: ReadonlyArray<{ codigo: string; documento: string }> | null; error: { message: string } | null };
  documentos: ReadonlyArray<{ id: string; tipo_taxonomia: string | null }>;
  checklist: { data: ReadonlyArray<{ tipo_taxonomia: string; status: string }> | null; error: { message: string } | null };
  servico: ServicoDocumentoServeComo;
}): Promise<LeituraDoKit> {
  if (e.kit.error || !e.kit.data) return { tipo: "nao_lido", motivo: `kit básico não lido: ${e.kit.error?.message}` };
  const daFuncao = await lerKitDaFuncao(e.rpc, e.casoId, e.kit.data);
  if (daFuncao.tipo !== "ausente") return daFuncao;

  // QUEDA — banco sem a 0300. Só "chegou" e "chegou sem linha" (checklist); nunca "lido".
  if (e.checklist.error) return { tipo: "nao_lido", motivo: `checklist não lido: ${e.checklist.error.message}` };
  let atendidos: Set<string>;
  try {
    atendidos = await itensDoKitBasicoAtendidos(e.kit.data, e.documentos, e.servico);
  } catch (err) {
    return { tipo: "nao_lido", motivo: `kit básico não conferido: ${err instanceof Error ? err.message : String(err)}` };
  }
  const semConteudo = new Set((e.checklist.data ?? []).filter((c) => c.status === "recebido_nao_valido").map((c) => c.tipo_taxonomia));
  const itens: ItemDoKit[] = e.kit.data.map((k) => ({
    codigo: k.codigo, documento: k.documento,
    estado: !atendidos.has(k.codigo) ? "faltante" : semConteudo.has(k.codigo) ? "recebido_sem_linha" : "recebido",
    motivo: null, aguardandoDesde: null, empresasTotal: null, empresasAtendidas: null, conferidoPor: null, conferidoEm: null,
  }));
  return { tipo: "lido", kit: { origem: "queda", itens, conferenciaEm: null, documentosDepoisDaConferencia: null } };
}

export type ContagemDoKit = {
  total: number;
  /** com linha lida (ou lido por natureza sem linha): o ÚNICO numerador do "% com conteúdo lido" */
  lidos: number;
  conferidos: number;
  recebidosSemLinha: number;
  aguardando: number;
  /** chegou, leitura não medida (só na queda) */
  recebidosSemEstado: number;
  dispensados: number;
  faltantes: number;
  /** o que o cliente ainda tem de mandar: não chegou, ou chegou sem nenhum dado. Dispensado e aguardando ficam fora. */
  paraPedirAoCliente: number;
  /** null na queda: sem o estado do banco não se sabe o que foi lido, e "0%" seria número inventado */
  pctLido: number | null;
};

export function contarKit(kit: KitDoCaso): ContagemDoKit {
  const n = (f: (i: ItemDoKit) => boolean) => kit.itens.filter(f).length;
  const total = kit.itens.length;
  const lidos = n((i) => ESTADOS_LIDOS.has(i.estado));
  const recebidosSemLinha = n((i) => i.estado === "recebido_sem_linha");
  const faltantes = n((i) => i.estado === "faltante");
  return {
    total, lidos, conferidos: n((i) => i.estado === "conferido"), recebidosSemLinha,
    aguardando: n((i) => i.estado === "aguardando_extracao"),
    recebidosSemEstado: n((i) => i.estado === "recebido"),
    dispensados: n((i) => i.estado === "dispensado"), faltantes,
    paraPedirAoCliente: faltantes + recebidosSemLinha,
    pctLido: kit.origem === "fn_kit_do_caso" && total > 0 ? Math.round((lidos / total) * 100) : null,
  };
}

/** "há 3 dias" — `agora` injetável para o teste. Data ilegível = null (nada é dito). */
export function haDias(iso: string | null, agora: Date = new Date()): string | null {
  if (!iso) return null;
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return null;
  const dias = Math.max(0, Math.floor((agora.getTime() - t) / 86_400_000));
  if (dias === 0) return "hoje";
  return dias === 1 ? "há 1 dia" : `há ${dias} dias`;
}

/** O texto do item na grade, com o efeito quando não está lido. `fracao` só onde a função a deu. */
export function textoDoItem(i: ItemDoKit, agora: Date = new Date()): {
  rotulo: string; tom: "ok" | "alerta" | "neutro" | "apagado"; complemento: string | null;
} {
  const fracao = i.empresasTotal !== null && i.empresasTotal > 0 && i.empresasAtendidas !== null
    ? `${i.empresasAtendidas} de ${i.empresasTotal} empresas` : null;
  switch (i.estado) {
    case "conferido": return { rotulo: "conferido por pessoa", tom: "ok", complemento: fracao };
    case "extraido": return { rotulo: "lido, não conferido", tom: "ok", complemento: fracao };
    case "lido_sem_dado_por_natureza":
      return { rotulo: "lido, sem dado financeiro por natureza", tom: "ok", complemento: fracao };
    case "aguardando_extracao": {
      const desde = haDias(i.aguardandoDesde, agora);
      return { rotulo: "recebido, leitura em andamento", tom: "alerta", complemento: [desde && `esperando ${desde}`, fracao].filter(Boolean).join(" · ") || null };
    }
    case "recebido_sem_linha": return { rotulo: "recebido, sem dado lido", tom: "alerta", complemento: fracao };
    case "dispensado": return { rotulo: "seguiu sem o documento (ressalva)", tom: "neutro", complemento: null };
    case "recebido": return { rotulo: "recebido (leitura não medida)", tom: "neutro", complemento: null };
    default: return { rotulo: "não recebido", tom: "apagado", complemento: null };
  }
}

/** Mapeamento para o `informacao` do deck (IX.2). Os estados novos têm status próprio: nenhum vira "recebido" por omissão. */
export function statusParaOExport(estado: EstadoDoItem):
  "recebido" | "sem_conteudo" | "faltante" | "aguardando" | "dispensado" | "lido_sem_dado" {
  switch (estado) {
    case "extraido": case "conferido": case "recebido": return "recebido";
    case "lido_sem_dado_por_natureza": return "lido_sem_dado";
    case "recebido_sem_linha": return "sem_conteudo";
    case "aguardando_extracao": return "aguardando";
    case "dispensado": return "dispensado";
    default: return "faltante";
  }
}
