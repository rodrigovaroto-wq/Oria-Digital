import { cache } from "react";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { paginar } from "@/lib/supabase/paginar";
import { contarLinhasPorVersao } from "@/lib/supabase/linhas-por-versao";
import { chamaRpc, servicoDocumentoServeComo } from "@/lib/supabase/servico-serve-como";
import { contarKit, lerKitDoCaso, type ContagemDoKit, type KitDoCaso } from "@/lib/kit-do-caso";
import { ESTADOS_EM_ABERTO } from "@/lib/pendencia";
import { proximoPasso } from "@/lib/proximo-passo";
import { lerResultadoDeFatos } from "@/lib/fatos-do-caso";
import {
  PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS,
  type Caso,
  type Documento,
  type FatoDoCaso,
  type TaxonomiaTipoDocumento,
} from "@/lib/types";

// AS LEITURAS DA VISÃO GERAL DO MANDATO, uma vez por requisição e compartilhadas entre os blocos.
//
// A tela chega por streaming (`visao-blocos.tsx`): cada bloco é um componente assíncrono num
// `<Suspense>` e pede o que precisa; `cache` do React faz o pedido repetido devolver a MESMA promessa.
// Nenhuma consulta mudou — as mesmas colunas, os mesmos filtros, o mesmo `paginar`. Mudou ONDE elas
// começam, e uma dependência que era artificial:
//
// MEDIDO (mandato de 115 documentos, 10.231 linhas): as nove consultas do `Promise.all` respondem em
// 166 a 447 ms (a lista paginada de documentos é a mais lenta); depois vinham, UMA APÓS A OUTRA, a
// contagem de linhas (~0,2 s, `fn_linhas_por_versao`) e o Kit Básico (~0,45 s,
// `fn_algum_documento_serve_como`), que só dependem da lista de documentos e não uma da outra. Aqui as
// duas partem juntas quando a lista chega.

type Supabase = Awaited<ReturnType<typeof createClient>>;
const cliente = cache(() => createClient());

const abertas = (supabase: Supabase, id: string) =>
  // PENDÊNCIA EM ABERTO = `ESTADOS_EM_ABERTO`, a mesma lista do layout e da aba Pendências.
  // Contagens `head: true` (só o número, nenhuma linha): esta tela não mostra mais nenhuma pendência,
  // só quantas e se travam. A decidida (aceita_com_ressalva, rejeitada) e a resolvida ficam de fora.
  supabase.from("pendencia").select("id", { head: true, count: "exact" }).eq("caso_id", id).in("estado", [...ESTADOS_EM_ABERTO]);

export const lerCaso = cache(async (id: string) => {
  const supabase = await cliente();
  return supabase.from("caso").select("id, nome, produto, status, criado_em").eq("id", id).single();
});

/**
 * O mandato desta tela; sem ele, 404, como a página sempre fez. `notFound()` aqui lança dentro do
 * bloco que pediu — o layout do mandato já respondeu 404 para mandato que não existe, então este é só
 * o cinto de segurança de quem lê o caso por conta própria.
 */
export async function casoDaTela(id: string): Promise<Caso> {
  const casoRes = await lerCaso(id);
  if (casoRes.error || !casoRes.data) notFound();
  return casoRes.data as Caso;
}

export const lerKitObrigatorio = cache(async () => {
  const supabase = await cliente();
  return supabase
    .from("taxonomia_tipo_documento")
    .select("codigo, categoria, documento, obrigatoriedade")
    .eq("obrigatoriedade", "obrigatorio")
    .order("codigo");
});

// SÓ O QUE OS INDICADORES PRECISAM: o tipo (Kit Básico) e as versões (soma de linhas). A tabela de
// documentos mora na aba Documentos; ler resumo, entidade e período aqui seria egress sem nenhum
// leitor. PAGINADA: o teto do PostgREST corta em silêncio, e aqui as linhas são o conteúdo — a soma
// de linhas e o "documentos sem linha".
export const lerDocumentosDoCaso = cache(async (id: string) => {
  const supabase = await cliente();
  return paginar<Pick<Documento, "id" | "tipo_taxonomia" | "documento_versao">>((de, ate) =>
    supabase
      .from("documento")
      .select("id, tipo_taxonomia, documento_versao(id)")
      .eq("caso_id", id)
      .order("id", { ascending: true })
      .range(de, ate),
  );
});

export const lerAbertas = cache(async (id: string) => abertas(await cliente(), id));
export const lerBloqueantes = cache(async (id: string) => abertas(await cliente(), id).eq("severidade", "bloqueante"));
export const lerRevisoes = cache(async (id: string) =>
  abertas(await cliente(), id).in("tipo", [...PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS]));

// Supabase/migrations/0036 — o checklist é a fonte do TERCEIRO estado: um item pode ter documento e
// ainda assim não ter uma linha extraída (`recebido_nao_valido`).
export const lerChecklist = cache(async (id: string) =>
  (await cliente()).from("checklist_item_status").select("tipo_taxonomia, status").eq("caso_id", id));

// Supabase/migrations/0037 — a avaliação do Portão 2. Determinística e sem efeito colateral (a função
// é `stable`): é a MESMA função que `fn_aprovar_caso` usa para decidir, e não uma segunda
// implementação da regra aqui no portal.
export const lerPortao2 = cache(async (id: string) => (await cliente()).rpc("fn_avaliar_portao2", { p_caso_id: id }));

export type Portao2 = {
  elegivel: boolean; motivos: string[]; ressalvas_ativas: number; teto_ressalvas: number;
  status_atual: string;
  // Supabase/migrations/0106 — quantas pendências foram declaradas IMPROCEDENTES.
  // Não entra na regra (rejeitada é estado terminal); entra na tela porque é a
  // única informação que separa um caso que nunca teve pendência de um que
  // teve e as rejeitou. Opcionais: um banco onde a 0106 ainda não foi aplicada
  // devolve o payload da 0037, e a tela tem de continuar funcionando.
  rejeitadas?: number; rejeitadas_nao_sobrepujaveis?: number;
};

// O QUE OS DOCUMENTOS DIZEM EM TEXTO (0148). TOLERANTE A ERRO: o dono aplica as migrations à mão, então
// banco sem a 0148 é estado normal e não defeito: o bloco não aparece e o resto da tela continua de pé.
export const lerFatos = cache(async (id: string) => (await cliente()).rpc("fn_fatos_do_caso", { p_caso_id: id }));

// O modelo está montado? As mesmas três coisas sem as quais Entregáveis recusa a apresentação.
export const lerModelo = cache(async (id: string) =>
  (await cliente()).from("caso_modelagem").select("entidade, ultimo_exercicio_real, anos_projetados").eq("caso_id", id).maybeSingle());

/** QUANTAS LINHAS CADA DOCUMENTO RENDEU — soma para o indicador e "documentos sem linha". */
export const lerLinhas = cache(async (id: string) => {
  const documentos = (await lerDocumentosDoCaso(id)).data;
  const versoes = documentos
    .flatMap((d) => (d.documento_versao ?? []).map((v) => v.id))
    .filter(Boolean);
  return contarLinhasPorVersao(await cliente(), versoes);
});

// O Kit Básico vem de `fn_kit_do_caso` (0300), UMA ida, com o estado de cada item derivado de
// `campo_extraido` — o mesmo que a aba Documentos e o export leem (`lib/kit-do-caso.ts`). Banco sem a
// 0300 cai em `itensDoKitBasicoAtendidos` (0157). Erro, exceção ou zero linhas = Kit NÃO LIDO (null),
// nunca "itens faltantes" nem "itens prontos". Antes, o % contava como lido o item cujo checklist não era
// `recebido_nao_valido`, e o checklist vira `presente` no registro do documento, antes de existir linha.
const lerKitDoMandato = cache(async (id: string) => {
  const [kitBasicoRes, documentosRes, checklistRes] = await Promise.all([
    lerKitObrigatorio(), lerDocumentosDoCaso(id), lerChecklist(id),
  ]);
  const supabase = await cliente();
  const leitura = await lerKitDoCaso({
    rpc: chamaRpc(supabase), casoId: id,
    kit: { data: kitBasicoRes.data as TaxonomiaTipoDocumento[] | null, error: kitBasicoRes.error },
    documentos: documentosRes.data as Documento[],
    checklist: { data: checklistRes.data as Array<{ tipo_taxonomia: string; status: string }> | null, error: checklistRes.error },
    servico: servicoDocumentoServeComo(supabase),
  });
  // A queda olha a lista de documentos: truncada ou com erro, o "chegou" dela não é verdade.
  const quedaSemBase = leitura.tipo === "lido" && leitura.kit.origem === "queda"
    && (Boolean(documentosRes.error) || Boolean(documentosRes.truncado));
  return quedaSemBase ? null : leitura.tipo === "lido" ? leitura.kit : null;
});

type ModeloDoMandato = { entidade: string | null; ultimo_exercicio_real: number | null; anos_projetados: number | null };

function modeloEstaMontado(modelo: ModeloDoMandato | null): boolean {
  return Boolean(modelo?.entidade?.trim()) && modelo?.ultimo_exercicio_real != null && Boolean(modelo?.anos_projetados);
}

function detalheDasLinhasDoMandato(documentosLidos: boolean, linhasIncompletas: boolean, semLinha: number): string | null {
  if (!documentosLidos) return "a leitura dos documentos falhou";
  if (linhasIncompletas) return "contagem incompleta — a leitura das linhas não terminou";
  if (semLinha > 0) return `${semLinha} ${semLinha === 1 ? "documento sem nenhuma linha" : "documentos sem nenhuma linha"}`;
  return null;
}

function detalheDasPendenciasDoMandato(nAbertas: number | null, nBloqueantes: number | null): string | null {
  if (nAbertas === null) return "a leitura das pendências falhou";
  if (nBloqueantes === null) return "não foi possível saber quantas travam a aprovação";
  if (nBloqueantes > 0) return `${nBloqueantes} ${nBloqueantes === 1 ? "bloqueia" : "bloqueiam"} a aprovação`;
  return null;
}

function detalheDoKitDoMandato(kit: KitDoCaso | null, c: ContagemDoKit | null): string | null {
  if (!kit || !c) return "a leitura do kit falhou";
  if (kit.origem === "queda") return "banco sem a 0300: não se sabe quais itens foram lidos";
  return c.lidos === c.total ? "todos os itens com conteúdo lido" : null;
}

/**
 * Tudo o que mais de um bloco da tela usa, derivado das leituras acima — a MESMA lógica que a página
 * tinha inline, só movida. Só espera o que precisa; os blocos que não dependem dele não o pedem.
 */
export const lerIndicadores = cache(async (id: string) => {
  const [casoRes, kitBasicoRes, documentosRes, abertasRes, bloqueantesRes, revisoesRes,
         portao2Res, modeloRes, linhas, kit] = await Promise.all([
    lerCaso(id), lerKitObrigatorio(), lerDocumentosDoCaso(id), lerAbertas(id), lerBloqueantes(id),
    lerRevisoes(id), lerPortao2(id), lerModelo(id), lerLinhas(id), lerKitDoMandato(id),
  ]);
  if (casoRes.error || !casoRes.data) notFound();
  const caso = casoRes.data as Caso;
  const kitBasico = (kitBasicoRes.data as TaxonomiaTipoDocumento[] | null) ?? [];
  const documentos = documentosRes.data;
  // Lista de documentos lida por inteiro? Sem isso, nem a soma de linhas nem o Kit Básico são
  // verdade (regra 1) — antes o erro era jogado fora e a tela mostrava "0 documentos".
  const documentosLidos = !documentosRes.error && !documentosRes.truncado;
  const { porVersao: linhasPorVersao, incompleto: linhasIncompletas } = linhas;

  const portao2 = portao2Res.data as Portao2 | null;

  // Contagem que falhou sai como null — nunca 0 (regra 1).
  const contagem = (r: { error: unknown; count: number | null }) => (r.error ? null : r.count);
  const nAbertas = contagem(abertasRes);
  const nBloqueantes = contagem(bloqueantesRes);
  const nRevisoes = contagem(revisoesRes);

  const linhasTotais = [...linhasPorVersao.values()].reduce((a, b) => a + b, 0);
  const kitLido = kit !== null;
  const contagemKit = kit ? contarKit(kit) : null;
  // Documento que chegou, foi classificado e não rendeu UMA linha. É o que o
  // `fn_conferir_lote` mede do lado do banco; aqui ele vira número de topo,
  // porque é a pergunta que a rodada v45 respondeu tarde demais.
  const documentosSemLinha = documentos.filter(
    (d) => ((d.documento_versao ?? []).reduce((n, v) => n + (linhasPorVersao.get(v.id) ?? 0), 0)) === 0,
  );
  const semLinha = documentosSemLinha.length;
  // Contagem parcial não é contagem (regra 1): com a leitura incompleta, a soma parcial NÃO
  // aparece como total (o valor vira "—") e "sem nenhuma linha" não é dito — contaria
  // documento cujas linhas estavam nas páginas que não vieram.
  const linhasConhecidas = documentosLidos && !linhasIncompletas;
  const detalheDasLinhas = detalheDasLinhasDoMandato(documentosLidos, linhasIncompletas, semLinha);

  const aprovado = caso.status === "aprovado" || caso.status === "pronto_para_base";
  const modelo = modeloRes.data as ModeloDoMandato | null;
  const passo = proximoPasso({
    bloqueantesAbertas: nBloqueantes,
    revisoesAbertas: nRevisoes,
    // o que o cliente ainda tem de mandar: não chegou, ou chegou sem dado. Dispensado (decidido por pessoa)
    // e aguardando leitura (a espera é do sistema) não são pedido ao cliente. Na queda nada se sabe de leitura.
    kitFaltantes: contagemKit ? contagemKit.paraPedirAoCliente : null,
    aprovavel: portao2 ? portao2.elegivel : null,
    aprovado,
    // Falta de configuração é uma resposta ("não montou"); erro de leitura é outra ("não sei").
    modeloMontado: modeloRes.error ? null : modeloEstaMontado(modelo),
  });

  // Leitura de bloqueantes que falhou é DITA, não some: `(null ?? 0) > 0` escondia a
  // falha e o indicador parecia dizer "nenhuma trava" (regra 1).
  const detalheDasPendencias = detalheDasPendenciasDoMandato(nAbertas, nBloqueantes);
  const detalheDoKit = detalheDoKitDoMandato(kit, contagemKit);

  return {
    caso, portao2, documentos, documentosLidos, nAbertas, linhasTotais, linhasConhecidas, semLinha,
    kitLido, kit, contagemKit, kitTotal: kitBasico.length, passo, linhasIncompletas,
    documentosSemLinha: documentosSemLinha.map((x) => ({ id: x.id, tipo: x.tipo_taxonomia })), detalheDasLinhas, detalheDasPendencias, detalheDoKit,
  };
});

/**
 * Os fatos do mandato, com a falha DITA. Antes `.error` era jogado fora e o retorno era `[]`: um timeout
 * num mandato com covenant rompido "crítico" fazia a seção sumir, com a mesma cara de "o documento não
 * diz nada" (regra 7). Agora há três respostas:
 *   - leu, com fatos          -> `{ fatos, falhou: false }`
 *   - função ausente (banco sem a 0148: PGRST202/42883, estado NORMAL) -> `{ fatos: [], falhou: false }`,
 *     o bloco não aparece, como sempre apareceu
 *   - qualquer outro erro     -> `{ fatos: [], falhou: true }`, e o bloco diz que não leu.
 */
export const lerFatosDoCaso = cache(async (id: string) =>
  lerResultadoDeFatos((await lerFatos(id)) as { data: FatoDoCaso[] | null; error: { code?: string | null } | null }));
