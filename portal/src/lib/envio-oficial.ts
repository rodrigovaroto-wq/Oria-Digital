// O ARQUIVO DE LEIAUTE OFICIAL É LIDO NO NAVEGADOR, E SÓ O RESUMO SAI DA MÁQUINA.
//
// A DECISÃO (dono, 13/10/2026): SPED, CNAB, OFX e XML fiscal não vão mais ao n8n.
// O `Leitor/lib` (o MESMO código do CLI — duas cópias divergem sem erro nenhum) lê
// o arquivo em fluxo no navegador do analista e entrega o envelope e o resumo; o
// portal grava os dois pelas funções da migration 0207. Medido num Chromium: 10M de
// linhas em 37,5 s com 61 MB de heap — daí o Web Worker (`ler-no-navegador.ts`):
// 37 s na thread principal congelam a aba.
//
// Este arquivo é a parte PURA do envio oficial (nada de DOM, nada de React): a
// separação oficial × não oficial, a partição em chamadas de no máximo 5.000
// itens, a montagem do cabeçalho, o roteiro iniciar → anexar → concluir e as
// frases que a tela mostra. Mora aqui, e não no componente, pelo motivo de
// sempre: a conta que ninguém consegue CHAMAR num teste é a que erra em
// silêncio. `portal/scripts/verificar-envio-oficial.mts` chama estas funções —
// as mesmas que a tela chama.
import type { SupabaseClient } from "@supabase/supabase-js";
import { detectarFamilia } from "../../../Leitor/lib/familia.mjs";

/** Os primeiros bytes que bastam para reconhecer a família (`detectarFamilia`). */
export const CABECA_BYTES = 65536;

/**
 * O teto de itens (registros + grupos) por chamada de `fn_resumo_anexar`, do
 * contrato da migration 0207. Uma chamada maior é recusada pelo banco depois de
 * o navegador montar e subir o corpo inteiro.
 */
export const MAX_ITENS_POR_CHAMADA = 5000;

// ---------------------------------------------------------------------------
// 1. O QUE É OFICIAL — pelos bytes, nunca pela extensão
// ---------------------------------------------------------------------------

export interface Deteccao {
  /** `null` = não é leiaute oficial; `"zip"` = contêiner; o resto é oficial. */
  readonly familia: string | null;
  readonly subtipo: string | null;
}

/** Não oficial e zip seguem o caminho de sempre (n8n); só a família nomeada é lida aqui. */
export type Destino = "oficial" | "zip" | "extracao";

export function destinoDe(d: Deteccao | null | undefined): Destino {
  if (!d || !d.familia) return "extracao";
  return d.familia === "zip" ? "zip" : "oficial";
}

/**
 * Reconhece a família pelos 64 KB iniciais do arquivo. Um arquivo que o
 * navegador não consegue abrir NÃO vira "oficial" nem "não oficial" por palpite:
 * a exceção sobe, e quem chama decide como dizer isso (regra 1).
 */
export async function detectarPeloArquivo(arquivo: Blob): Promise<Deteccao> {
  const cabeca = new Uint8Array(await arquivo.slice(0, CABECA_BYTES).arrayBuffer());
  const d = detectarFamilia(cabeca) as { familia: string | null; subtipo?: string | null };
  return { familia: d.familia ?? null, subtipo: d.subtipo ?? null };
}

/**
 * Separa o lote: o que o navegador lê (`oficiais`) e o que segue EXATAMENTE como
 * antes para o n8n (`aoN8n`, na ordem original — o zip continua indo por aqui,
 * porque o conteúdo dele só se abre depois de lido por inteiro).
 */
export function separarOficiais<T>(
  itens: readonly T[],
  deteccaoDe: (item: T) => Deteccao | null | undefined,
): { oficiais: T[]; aoN8n: T[] } {
  const oficiais: T[] = [];
  const aoN8n: T[] = [];
  for (const item of itens) {
    (destinoDe(deteccaoDe(item)) === "oficial" ? oficiais : aoN8n).push(item);
  }
  return { oficiais, aoN8n };
}

// ---------------------------------------------------------------------------
// 2. O QUE O LEITOR ENTREGA (tipado na fronteira; o `.mjs` não tem tipos)
// ---------------------------------------------------------------------------

export interface EnvelopeDoLeitor {
  familia: string;
  subtipo: string | null;
  hash_sha256: string | null;
  status: string;
  controle_tipo?: string;
  controle_declarado: number | null;
  controle_lido: number | null;
  detalhe?: { motivo?: string; [k: string]: unknown };
  [k: string]: unknown;
}

export interface ResumoDoLeitor {
  versao: string;
  hash_sha256: string | null;
  ausente?: string;
  conferencia?: {
    lancamentos_desbalanceados?: number;
    valores_invalidos?: number;
    [k: string]: unknown;
  };
  descartado?: string;
  registros?: unknown[];
  lancamentos_por_conta_mes?: unknown[];
  [k: string]: unknown;
}

/** Os valores de `p_cabecalho` de `fn_resumo_iniciar`, todos tirados do resumo. */
export interface CabecalhoDoResumo {
  versao: string;
  hash_sha256: string | null;
  ausente?: string;
  conferencia?: ResumoDoLeitor["conferencia"];
  descartado?: string;
  total_registros: number;
  total_grupos: number;
}

/**
 * O cabeçalho do resumo. As chaves opcionais só existem quando o resumo as
 * tem: `ausente: undefined` serializado como `null` diria ao banco "há um
 * motivo, e ele é nulo" — a forma mais discreta de dar um resumo por ausente.
 *
 * Os totais, `?? 0`, são do contrato (0207). Resumo `ausente` não tem registro
 * nenhum, e o zero ali é o total do que NÃO foi enviado — a tela nunca o mostra
 * como contagem de um arquivo (ver `descreverDesfecho`).
 */
export function montarCabecalho(resumo: ResumoDoLeitor): CabecalhoDoResumo {
  return {
    versao: resumo.versao,
    hash_sha256: resumo.hash_sha256,
    ...(resumo.ausente !== undefined ? { ausente: resumo.ausente } : {}),
    ...(resumo.conferencia !== undefined ? { conferencia: resumo.conferencia } : {}),
    ...(resumo.descartado !== undefined ? { descartado: resumo.descartado } : {}),
    total_registros: resumo.registros?.length ?? 0,
    total_grupos: resumo.lancamentos_por_conta_mes?.length ?? 0,
  };
}

/**
 * Parte registros e grupos em chamadas de no máximo `max` itens NO TOTAL, em
 * sequência: primeiro os registros, depois os grupos, e a chamada que fecha os
 * registros já leva grupos até encher. Nada some e nada se repete — a soma dos
 * itens das partes é a dos dois vetores.
 */
export function partirEmLotes<R, G>(
  registros: readonly R[],
  grupos: readonly G[],
  max: number = MAX_ITENS_POR_CHAMADA,
): { registros: R[]; grupos: G[] }[] {
  if (!Number.isInteger(max) || max < 1) throw new Error(`partirEmLotes: máximo inválido (${max})`);
  const partes: { registros: R[]; grupos: G[] }[] = [];
  let i = 0;
  let j = 0;
  while (i < registros.length || j < grupos.length) {
    const r = registros.slice(i, i + max);
    i += r.length;
    const g = grupos.slice(j, j + (max - r.length));
    j += g.length;
    partes.push({ registros: r, grupos: g });
  }
  return partes;
}

// ---------------------------------------------------------------------------
// 3. O PROGRESSO DE LEITURA — sem mudar o Leitor
// ---------------------------------------------------------------------------

/**
 * Embrulha o fluxo do arquivo contando os bytes que passam. O Leitor consome o
 * fluxo à medida que lê, então bytes passados / `file.size` é a fração LIDA —
 * não uma barra animada. (Os bytes contados são os entregues ao leitor; o que
 * ele ainda tem em processamento é uma fatia de ~64 KB, abaixo de qualquer
 * resolução da barra.)
 */
export function fluxoComProgresso(
  fluxo: ReadableStream<Uint8Array>,
  aoPassar: (bytesAteAgora: number) => void,
): ReadableStream<Uint8Array> {
  let total = 0;
  return fluxo.pipeThrough(
    new TransformStream<Uint8Array, Uint8Array>({
      transform(fatia, controle) {
        total += fatia.length;
        aoPassar(total);
        controle.enqueue(fatia);
      },
    }),
  );
}

// ---------------------------------------------------------------------------
// 4. O MANDATO (caso_id) PELO NAVEGADOR
// ---------------------------------------------------------------------------

type ClienteDoBanco = Pick<SupabaseClient, "rpc">;

/**
 * O `caso_id` do mandato. O formulário tem o NOME e, às vezes, o `casoId`.
 *
 * COM `casoId` (tela do mandato, nome travado) usa-se ele: é o id, e não há o que
 * resolver. SEM ele, `fn_upsert_caso` — a MESMA função do nó Upsert Caso do n8n,
 * que reusa o caso pelo nome exato e só cria se não existir. A 0207 deu a ela o
 * `grant execute` ao authenticated e o `p_ator`, para a trilha `caso_criado` dizer
 * que foi a tela. Antes disso esta função repetia a regra em TypeScript (select e
 * depois insert), e duas implementações da mesma regra divergem sem erro.
 *
 * O QUE ISTO NÃO FECHA: `caso.nome` não é único, e o select-depois-insert dentro da
 * função não tem trava — duas abas criando o MESMO mandato novo no mesmo instante
 * criam dois. É por isso que, num lote misto, os oficiais rodam ANTES do envio ao
 * n8n: o n8n encontra o caso criado aqui, em vez de criar outro.
 */
export async function obterCasoId(
  cliente: ClienteDoBanco,
  nome: string,
  casoId?: string,
): Promise<{ id: string }> {
  if (casoId) return { id: casoId };
  const { data, error } = await cliente.rpc("fn_upsert_caso", { p_nome: nome, p_ator: "portal:navegador" });
  if (error || typeof data !== "string") {
    throw new Error(`Não foi possível obter o mandato “${nome}”: ${error?.message ?? "o banco não devolveu o id"}`);
  }
  return { id: data };
}

// ---------------------------------------------------------------------------
// 5. A GRAVAÇÃO: iniciar -> anexar (partes) -> concluir  (contrato da 0207)
// ---------------------------------------------------------------------------

/** O mínimo do `rpc` do supabase-js que a gravação usa (e que um teste substitui). */
export type ChamarRpc = (
  funcao: string,
  argumentos: Record<string, unknown>,
) => PromiseLike<{ data: unknown; error: { message: string; code?: string } | null }>;

export type EtapaDaGravacao = "iniciar" | "anexar" | "concluir";

export type DesfechoDoServidor =
  | { tipo: "completo"; registros: number | null; grupos: number | null; i155NaoFecham: unknown }
  | { tipo: "recusado"; motivo: string }
  /** O resumo não existe (`resumo.ausente`); o envelope foi registrado e só ele. */
  | { tipo: "ausente"; motivo: string }
  | { tipo: "reenvio" }
  | {
      tipo: "falha";
      etapa: EtapaDaGravacao;
      /** `banco`: o Postgres respondeu com exceção (traz código); `rede`: nem chegou resposta. */
      origem: "banco" | "rede" | "resposta_inesperada";
      mensagem: string;
      /** A carga foi aberta e não fechou: o arquivo ficou `em_carga`. */
      ficouEmCarga: boolean;
    };

export interface ProgressoDaGravacao {
  etapa: EtapaDaGravacao;
  /** Partes de `anexar` já aceitas, e o total de partes. */
  feitas: number;
  total: number;
}

async function chamar(
  rpc: ChamarRpc,
  funcao: string,
  argumentos: Record<string, unknown>,
): Promise<{ ok: true; data: unknown } | { ok: false; origem: "banco" | "rede"; mensagem: string }> {
  try {
    const r = await rpc(funcao, argumentos);
    if (r.error) {
      // Exceção do Postgres traz `code` (SQLSTATE); falha de transporte, não.
      return { ok: false, origem: r.error.code ? "banco" : "rede", mensagem: r.error.message };
    }
    return { ok: true, data: r.data };
  } catch (e) {
    return { ok: false, origem: "rede", mensagem: (e as Error).message };
  }
}

const objeto = (x: unknown): Record<string, unknown> | null =>
  x !== null && typeof x === "object" && !Array.isArray(x) ? (x as Record<string, unknown>) : null;

/**
 * Grava o resumo de UM arquivo e devolve o que o SERVIDOR disse — nunca o que
 * a tela gostaria de ter ouvido.
 *
 * Falha de rede no meio deixa o arquivo `em_carga`; reenviar recomeça do zero (o
 * `iniciar` apaga a carga anterior). Por isso uma falha depois do `iniciar`
 * carrega `ficouEmCarga: true`, e NENHUM caminho daqui devolve `completo` sem a
 * resposta `completo` do `concluir`. Resposta que não é nenhuma das conhecidas
 * (`resumo` desconhecido, corpo que não é objeto) é `resposta_inesperada`, e
 * não sucesso (regra 7: estágio que não confirmou não é estágio que passou).
 */
export async function gravarResumo(
  rpc: ChamarRpc,
  casoId: string,
  envelope: EnvelopeDoLeitor,
  resumo: ResumoDoLeitor,
  aoProgredir?: (p: ProgressoDaGravacao) => void,
): Promise<DesfechoDoServidor> {
  const falha = (
    etapa: EtapaDaGravacao, origem: "banco" | "rede" | "resposta_inesperada", mensagem: string, ficouEmCarga: boolean,
  ): DesfechoDoServidor => ({ tipo: "falha", etapa, origem, mensagem, ficouEmCarga });

  aoProgredir?.({ etapa: "iniciar", feitas: 0, total: 0 });
  const ini = await chamar(rpc, "fn_resumo_iniciar", {
    p_caso: casoId, p_documento: null, p_envelope: envelope, p_cabecalho: montarCabecalho(resumo),
  });
  if (!ini.ok) return falha("iniciar", ini.origem, ini.mensagem, false);
  const aberto = objeto(ini.data);
  const situacao = aberto?.resumo;
  const id = aberto?.id;

  if (situacao === "ausente") return { tipo: "ausente", motivo: resumo.ausente ?? "o banco registrou o resumo como ausente" };
  if (situacao === "reenvio") return { tipo: "reenvio" };
  if (situacao !== "em_carga" || typeof id !== "string") {
    return falha("iniciar", "resposta_inesperada",
      `o banco respondeu ao início da gravação com algo que não reconheço (${JSON.stringify(ini.data)?.slice(0, 200)})`, false);
  }

  const partes = partirEmLotes(resumo.registros ?? [], resumo.lancamentos_por_conta_mes ?? []);
  for (let k = 0; k < partes.length; k++) {
    aoProgredir?.({ etapa: "anexar", feitas: k, total: partes.length });
    const ane = await chamar(rpc, "fn_resumo_anexar", {
      p_arquivo: id, p_registros: partes[k].registros, p_grupos: partes[k].grupos,
    });
    if (!ane.ok) return falha("anexar", ane.origem, ane.mensagem, true);
  }

  aoProgredir?.({ etapa: "concluir", feitas: partes.length, total: partes.length });
  const fim = await chamar(rpc, "fn_resumo_concluir", { p_arquivo: id });
  if (!fim.ok) return falha("concluir", fim.origem, fim.mensagem, true);
  const r = objeto(fim.data);
  if (r?.resumo === "completo") {
    return {
      tipo: "completo",
      registros: typeof r.registros === "number" ? r.registros : null,
      grupos: typeof r.grupos === "number" ? r.grupos : null,
      i155NaoFecham: r.i155_nao_fecham,
    };
  }
  if (r?.resumo === "recusado") {
    return { tipo: "recusado", motivo: typeof r.motivo === "string" && r.motivo ? r.motivo : "o banco não informou o motivo" };
  }
  return falha("concluir", "resposta_inesperada",
    `o banco respondeu ao fechamento com algo que não reconheço (${JSON.stringify(fim.data)?.slice(0, 200)})`, true);
}

// ---------------------------------------------------------------------------
// 6. O QUE A TELA DIZ — frases puras, para o teste as ler
// ---------------------------------------------------------------------------

/** O estado de um arquivo oficial na tela, da leitura ao veredito do banco. */
export interface ResultadoOficial {
  chave: string;
  nome: string;
  bytes: number;
  familia: string;
  subtipo: string | null;
  fase: "na_fila" | "lendo" | "gravando" | "fim";
  lidosBytes: number;
  gravacao?: ProgressoDaGravacao;
  envelope?: EnvelopeDoLeitor;
  resumo?: ResumoDoLeitor;
  /** A leitura em si falhou (arquivo sumiu do disco, memória): não há envelope. */
  erroDeLeitura?: string;
  desfecho?: DesfechoDoServidor;
}

export const rotuloDaFamilia = (familia: string, subtipo: string | null): string =>
  subtipo ? `${familia.toUpperCase()} · ${subtipo.replace(/_/g, " ")}` : familia.toUpperCase();

/** O status do envelope em português, com o motivo que o Leitor deu. */
export function rotuloDoStatus(env: EnvelopeDoLeitor): string {
  const motivo = env.detalhe?.motivo ? `: ${env.detalhe.motivo}` : "";
  switch (env.status) {
    case "lido": return "Lido por inteiro, contagem conferida.";
    case "controle_divergente": return `A contagem do arquivo não bate com o que foi lido${motivo || " (truncado ou alterado)"}.`;
    case "versao_desconhecida": return `Versão do leiaute desconhecida${motivo}.`;
    case "falhou": return `Não foi possível ler${motivo || " (sem motivo informado)"}.`;
    default: return `Status “${env.status}”${motivo}.`;
  }
}

/**
 * "Linhas lidas × declaradas". Nunca zero no lugar do que não existe: o OFX não
 * declara contagem (`sem_controle_no_formato`), e um arquivo sem o registro de
 * controle também não — ali o texto diz que NÃO HÁ declarada, e não "0".
 */
export function descreverContagem(env: EnvelopeDoLeitor): string {
  const lidas = typeof env.controle_lido === "number" ? env.controle_lido.toLocaleString("pt-BR") : null;
  if (env.controle_tipo === "sem_controle_no_formato") {
    return `${lidas ?? "—"} lidas; o formato não declara quantas deveria ter, então a integridade não se confere por contagem.`;
  }
  if (env.controle_declarado === null || env.controle_declarado === undefined) {
    return `${lidas ?? "—"} lidas; o arquivo não traz a contagem declarada (provavelmente truncado).`;
  }
  const decl = env.controle_declarado.toLocaleString("pt-BR");
  return `${lidas ?? "—"} lidas × ${decl} declaradas.`;
}

/** Os achados da conferência do resumo. Só o que o resumo MEDIU: ausência de campo não vira "0". */
export function achadosDaConferencia(resumo: ResumoDoLeitor | undefined): string[] {
  const c = resumo?.conferencia;
  if (!c) return [];
  const achados: string[] = [];
  if (typeof c.lancamentos_desbalanceados === "number" && c.lancamentos_desbalanceados > 0) {
    achados.push(`${c.lancamentos_desbalanceados.toLocaleString("pt-BR")} lançamento(s) desbalanceado(s): débitos e créditos não se igualam.`);
  }
  if (typeof c.valores_invalidos === "number" && c.valores_invalidos > 0) {
    achados.push(`${c.valores_invalidos.toLocaleString("pt-BR")} valor(es) inválido(s): ficaram fora das somas e estão contados à parte.`);
  }
  return achados;
}

/** `i155_nao_fecham` como número, se o banco o deu como número ou lista; senão `null` (não informado). */
export function contagemDe(x: unknown): number | null {
  if (typeof x === "number" && Number.isFinite(x)) return x;
  if (Array.isArray(x)) return x.length;
  return null;
}

/** O desfecho em palavras. Cada ramo diz o EFEITO, não só o fato (regra 1). */
export function descreverDesfecho(d: DesfechoDoServidor): { tom: "ok" | "alerta" | "erro"; texto: string } {
  switch (d.tipo) {
    case "completo": {
      const n = contagemDe(d.i155NaoFecham);
      const fecha = n === null
        ? "O banco não informou a conferência dos saldos (I155)."
        : n === 0
          ? "Todos os saldos I155 fecham."
          : `${n.toLocaleString("pt-BR")} saldo(s) I155 não fecham com os lançamentos — veja o mandato antes de usar o balancete deste arquivo.`;
      const cont = d.registros !== null && d.grupos !== null
        ? `${d.registros.toLocaleString("pt-BR")} registro(s) e ${d.grupos.toLocaleString("pt-BR")} grupo(s) gravados. `
        : "";
      return { tom: n !== null && n > 0 ? "alerta" : "ok", texto: `Gravado por completo. ${cont}${fecha}` };
    }
    case "recusado":
      return {
        tom: "erro",
        texto: `O banco recusou o resumo: ${d.motivo}. Nada deste arquivo foi aceito como dado do mandato.`,
      };
    case "ausente":
      return {
        tom: "alerta",
        texto: `Sem resumo: ${d.motivo}. Só o cabeçalho do arquivo (família, período, contagem) foi registrado; nenhum conteúdo dele está no banco.`,
      };
    case "reenvio":
      return {
        tom: "ok",
        texto: "O banco reconheceu este arquivo como reenvio do mesmo conteúdo (mesmo hash) e não abriu uma carga nova.",
      };
    case "falha": {
      const onde = { iniciar: "ao iniciar a gravação", anexar: "no meio da gravação", concluir: "ao fechar a gravação" }[d.etapa];
      const quem = d.origem === "rede"
        ? `Falha de comunicação ${onde}: ${d.mensagem}.`
        : d.origem === "banco"
          ? `O banco recusou ${onde}: ${d.mensagem}`
          : `Resposta inesperada ${onde}: ${d.mensagem}.`;
      return {
        tom: "erro",
        texto: d.ficouEmCarga
          ? `${quem} O arquivo ficou em carga e NÃO está concluído: reenviar recomeça a gravação do zero.`
          : `${quem} Nada foi gravado deste arquivo; pode reenviar.`,
      };
    }
  }
}

/**
 * O desfecho é definitivo para a lista de arquivos? Resposta do servidor
 * encerra o arquivo (sai da lista); falha o mantém, para o reenvio.
 */
export function desfechoEncerra(d: DesfechoDoServidor | undefined): boolean {
  return d !== undefined && d.tipo !== "falha";
}
