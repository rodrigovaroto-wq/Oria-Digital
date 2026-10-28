import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { paginar } from "@/lib/supabase/paginar";
import type { TaxonomiaTipoDocumento } from "@/lib/types";
import {
  ESTADOS_DECIDIDOS,
  ESTADOS_EM_ABERTO,
  FILTROS_PENDENCIA,
  categoriaDaPendencia,
  type CategoriaDePendencia,
} from "@/lib/pendencia";
import { DetalhesTecnicos } from "@/components/detalhes-tecnicos";
import { ItemPendencia } from "../Pendencia";
import { CartaoConfirmarDocumento, type DocumentoParaConfirmar } from "./FormConfirmarDocumento";

// PENDÊNCIAS: o único lugar onde se decide sobre problema do mandato.
//
// POR QUE EXISTE. As decisões moravam em cinco lugares — quatro seções da Visão geral
// (o que falta chegar, números que não fecham, arquivos ilegíveis, extração incompleta)
// e a tela de Revisão. Quem precisava limpar o que travava a aprovação andava por duas
// abas somando de cabeça. Aqui tudo está junto, com filtro por espécie.
//
// O NÚMERO DA ABA É O DESTA LISTA. "Em aberto" = estado em `ESTADOS_EM_ABERTO`, de
// QUALQUER tipo (nenhum é excluído); o layout conta com a MESMA constante, num `count`
// `head: true`. Se esta página passar a esconder um tipo, o layout tem de esconder o
// mesmo, ou a aba promete mais cartões do que a tela abre.
//
// DECIDIDA CONTINUA VISÍVEL. Os três botões (0109) "adicionam um rótulo na pendência";
// se o item sumisse ao ser decidido, ninguém veria o que foi decidido. Ficam na seção
// "Já decididas", embaixo. `resolvida` (do sistema) fica de fora.
interface PendenciaDaLista {
  id: string;
  tipo: string;
  severidade: "bloqueante" | "importante" | "complementar";
  estado: string;
  descricao: string | null;
  documento_id: string | null;
  criada_em: string;
  documento: (DocumentoParaConfirmar & {
    documento_versao: Array<{ nome_original: string | null }> | null;
  }) | null;
}

// O tom que cada seção tinha na Visão geral: divergência é âmbar sempre; arquivo ilegível e
// extração incompleta são vermelhos sempre; o resto (faltando) acompanha a severidade.
function tomDoCartao(p: PendenciaDaLista): "red" | "amber" {
  const c = categoriaDaPendencia(p.tipo);
  if (c === "ilegivel" || c === "extracao") return "red";
  if (c === "reconciliacao") return "amber";
  return p.severidade === "bloqueante" ? "red" : "amber";
}

const ORDEM_SEVERIDADE: Record<string, number> = { bloqueante: 0, importante: 1, complementar: 2 };

const VAZIO_POR_FILTRO: Record<string, string> = {
  todas: "Nenhuma pendência neste mandato.",
  confirmar: "Todo documento deste mandato foi classificado com confiança suficiente.",
  // A frase de antes (Visão geral): afirma o que a conferência automática mediu.
  reconciliacao: "Nenhuma divergência encontrada — o balanço fecha, o caixa bate com o fluxo e não há conta contada duas vezes.",
  faltando: "Nenhum documento obrigatório ausente ou sem linha aproveitável.",
  ilegivel: "Nenhum arquivo ilegível.",
  extracao: "Nenhuma extração marcada como incompleta.",
};

export default async function PendenciasPage({
  params,
  searchParams,
}: Readonly<{
  params: Promise<{ id: string }>;
  searchParams: Promise<{ filtro?: string | string[] }>;
}>) {
  const { id } = await params;
  const { filtro: filtroBruto } = await searchParams;
  const pedido = Array.isArray(filtroBruto) ? filtroBruto[0] : filtroBruto;
  const filtro = FILTROS_PENDENCIA.find((f) => f.chave === pedido)?.chave ?? "todas";

  const supabase = await createClient();

  // Paginada: esta É a fila de trabalho, e o teto do PostgREST corta em silêncio — uma
  // fila truncada parece uma fila terminada. O nome do arquivo vem EMBUTIDO (uma ida só),
  // em vez de ler todos os documentos do mandato só para achar o nome.
  const pendenciasRes = await paginar<PendenciaDaLista>((de, ate) =>
    supabase
      .from("pendencia")
      .select(
        `id, tipo, severidade, estado, descricao, documento_id, criada_em,
         documento:documento_id(
           id, tipo_taxonomia, confianca, fonte,
           entidade:entidade_id(razao_social), periodo:periodo_id(tipo, referencia),
           documento_versao(nome_original)
         )`,
      )
      .eq("caso_id", id)
      .in("estado", [...ESTADOS_EM_ABERTO, ...ESTADOS_DECIDIDOS])
      .order("criada_em", { ascending: true })
      .order("id", { ascending: true })
      .range(de, ate),
  );
  const todas = pendenciasRes.data;
  const emAberto = (p: PendenciaDaLista) => (ESTADOS_EM_ABERTO as readonly string[]).includes(p.estado);

  // Contagem por gaveta, sobre o que foi lido. Falha de leitura NÃO vira "0" (regra 1):
  // sem dado, os filtros saem sem número.
  const lido = !pendenciasRes.error && !pendenciasRes.truncado;
  const abertasPorGaveta = new Map<CategoriaDePendencia, number>();
  for (const p of todas) {
    if (!emAberto(p)) continue;
    const c = categoriaDaPendencia(p.tipo);
    abertasPorGaveta.set(c, (abertasPorGaveta.get(c) ?? 0) + 1);
  }
  const totalAbertas = todas.filter(emAberto).length;

  const daGaveta = (p: PendenciaDaLista) => filtro === "todas" || categoriaDaPendencia(p.tipo) === filtro;
  // Bloqueante primeiro: é o que trava a aprovação. Empate: a mais antiga (ordem da leitura).
  const abertas = todas
    .filter((p) => emAberto(p) && daGaveta(p))
    .sort((a, b) => (ORDEM_SEVERIDADE[a.severidade] ?? 3) - (ORDEM_SEVERIDADE[b.severidade] ?? 3));
  const decididas = todas.filter((p) => !emAberto(p) && daGaveta(p));

  // A taxonomia só é lida se há formulário de confirmação para desenhar.
  // O formulário aparece SÓ para `estado = 'aberta'`: um documento já em correção interna
  // ou devolvido ao cliente volta a ser cartão comum, com os três botões.
  const comFormulario = (p: PendenciaDaLista) =>
    categoriaDaPendencia(p.tipo) === "confirmar" && p.estado === "aberta" && p.documento !== null;
  let taxonomia: TaxonomiaTipoDocumento[] = [];
  let taxonomiaFalhou = false;
  if (abertas.some(comFormulario)) {
    const t = await supabase.from("taxonomia_tipo_documento").select("codigo, categoria, documento, obrigatoriedade").order("codigo");
    taxonomiaFalhou = Boolean(t.error);
    taxonomia = (t.data as TaxonomiaTipoDocumento[] | null) ?? [];
  }

  const nomeDoArquivo = (p: PendenciaDaLista) =>
    (p.documento?.documento_versao ?? []).map((v) => v.nome_original).filter(Boolean).at(-1) ?? null;

  const cartao = (p: PendenciaDaLista) =>
    comFormulario(p) && !taxonomiaFalhou && p.documento ? (
      <CartaoConfirmarDocumento
        key={p.id} casoId={id} p={p} doc={p.documento}
        nomeArquivo={nomeDoArquivo(p) ?? "(sem nome)"} taxonomia={taxonomia}
      />
    ) : (
      <ItemPendencia
        key={p.id} p={p} casoId={id}
        tom={tomDoCartao(p)}
        arquivo={nomeDoArquivo(p)}
      />
    );

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-lg font-semibold text-tinta-900">Pendências</h1>
        <p className="mt-0.5 max-w-2xl text-sm text-tinta-500">
          Tudo o que precisa de uma decisão sua antes da aprovação: documentos a confirmar,
          números que não fecham, o que falta chegar e o que não pôde ser lido. Cada decisão
          fica registrada.
        </p>
      </div>

      <nav aria-label="Filtrar pendências" className="flex flex-wrap gap-2">
        {FILTROS_PENDENCIA.map((f) => {
          const n = f.chave === "todas" ? totalAbertas : abertasPorGaveta.get(f.chave) ?? 0;
          const atual = f.chave === filtro;
          return (
            <Link
              key={f.chave}
              href={f.chave === "todas" ? `/casos/${id}/pendencias` : `/casos/${id}/pendencias?filtro=${f.chave}`}
              aria-current={atual ? "page" : undefined}
              className={`chip px-3 py-1 ${atual ? "bg-tinta-800 text-papel" : "bg-tinta-100 text-tinta-700 hover:bg-tinta-200"}`}
            >
              {f.rotulo}
              {lido && ` (${n})`}
            </Link>
          );
        })}
      </nav>

      {!lido && (
        <div className="rounded-lg border border-risco-200 bg-risco-50 p-3 text-sm text-risco-800">
          {pendenciasRes.error
            ? "Não foi possível carregar a lista de pendências. O que aparece abaixo pode estar incompleto; tente de novo em instantes e, se persistir, avise o administrador do sistema."
            : "A lista de pendências passou do teto de leitura; o que aparece abaixo é só uma parte. Avise o administrador do sistema."}
          {pendenciasRes.error && (
            <DetalhesTecnicos>
              <p>{pendenciasRes.error.message}</p>
            </DetalhesTecnicos>
          )}
        </div>
      )}

      {taxonomiaFalhou && (
        <div className="rounded-lg border border-risco-200 bg-risco-50 p-3 text-sm text-risco-800">
          Não foi possível carregar a lista de tipos de documento, então os documentos a confirmar
          aparecem como pendência comum, sem o formulário. Recarregue a página.
        </div>
      )}

      <section aria-labelledby="em-aberto" className="space-y-3">
        <div className="flex items-baseline justify-between gap-3">
          <h2 id="em-aberto" className="titulo-secao">Em aberto</h2>
          {lido && <p className="text-xs text-tinta-500">{abertas.length} {abertas.length === 1 ? "pendência" : "pendências"}</p>}
        </div>
        {abertas.length === 0 && lido ? (
          <div className="carta px-6 py-10 text-center">
            <p className="text-sm font-medium text-tinta-900">Nada em aberto</p>
            <p className="mt-1 text-sm text-tinta-500">{VAZIO_POR_FILTRO[filtro]}</p>
          </div>
        ) : (
          <ul className="space-y-3">{abertas.map(cartao)}</ul>
        )}
      </section>

      {decididas.length > 0 && (
        <section aria-labelledby="ja-decididas" className="space-y-3">
          <div className="flex items-baseline justify-between gap-3">
            <h2 id="ja-decididas" className="titulo-secao">Já decididas</h2>
            <p className="text-xs text-tinta-500">{decididas.length} {decididas.length === 1 ? "pendência" : "pendências"}</p>
          </div>
          <p className="text-xs text-tinta-500">
            Seguem visíveis porque a decisão é um registro do mandato; dá para mudá-la com os botões.
          </p>
          <ul className="space-y-3">{decididas.map(cartao)}</ul>
        </section>
      )}
    </div>
  );
}
