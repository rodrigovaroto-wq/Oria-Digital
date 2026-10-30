import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { paginar } from "@/lib/supabase/paginar";
import { contarLinhasPorVersao } from "@/lib/supabase/linhas-por-versao";
import { servicoDocumentoServeComo } from "@/lib/supabase/servico-serve-como";
import { DetalhesTecnicos } from "@/components/detalhes-tecnicos";
import type { Documento, TaxonomiaTipoDocumento } from "@/lib/types";
import { humanizar } from "@/lib/rotulos";
import { formatarPeriodo, formatarTipoTaxonomia } from "@/lib/export";
import { itensDoKitBasicoAtendidos } from "@/lib/kit-basico";
import { OrdemDosDocumentos } from "@/components/ordem-dos-documentos";
import { LinhaDeDocumento } from "@/components/linha-de-documento";

const LEGIBILIDADE_LABEL: Record<string, string> = {
  degradado: "qualidade degradada",
  ilegivel: "ilegível",
};

// A COLUNA "FONTE" FALAVA BANCO DE DADOS. Ela mostrava `nome_arquivo` e
// `openai_conteudo` crus — vocabulário de quem escreveu o pipeline, não de quem
// confere um mandato. O fato que importa para quem lê é OUTRO: o documento foi
// reconhecido pelo nome do arquivo (barato, determinístico) ou foi preciso ler o
// conteúdo com IA (mais caro, e é o caminho de quem manda "Doc1.pdf").
const FONTE_LABEL: Record<string, string> = {
  nome_arquivo: "nome do arquivo",
  openai_conteudo: "leitura do conteúdo",
  manual: "revisão humana",
};

// DOCUMENTOS: o que chegou (Kit Básico) e a tabela de cada arquivo — movidos da Visão geral
// sem mudar dado nem semântica (a Visão geral ficou com o resumo e o próximo passo).
// Os filtros são links (`?filtro=` / `?tipo=`), renderizados no servidor: nenhum estado no
// navegador, e a URL filtrada pode ser colada numa conversa.
const SEM_TIPO = "sem-tipo";

export default async function DocumentosPage({
  params,
  searchParams,
}: Readonly<{
  params: Promise<{ id: string }>;
  searchParams: Promise<{ filtro?: string | string[]; tipo?: string | string[] }>;
}>) {
  const { id } = await params;
  const sp = await searchParams;
  const primeiro = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);
  const tipoPedido = primeiro(sp.tipo);
  let filtro: "todos" | "sem-linha" | "ilegivel" | "tipo" = "todos";
  if (tipoPedido) filtro = "tipo";
  else if (primeiro(sp.filtro) === "sem-linha" || primeiro(sp.filtro) === "ilegivel") filtro = primeiro(sp.filtro) as "sem-linha" | "ilegivel";

  const supabase = await createClient();

  const [kitBasicoRes, documentosRes, checklistRes] = await Promise.all([
    supabase
      .from("taxonomia_tipo_documento")
      .select("codigo, categoria, documento, obrigatoriedade")
      .eq("obrigatoriedade", "obrigatorio")
      .order("codigo"),
    // PAGINADA: o teto do PostgREST (`db-max-rows`, 1000 no Supabase) corta em silêncio, e aqui
    // as linhas são o conteúdo — a tabela de documentos e a contagem de linhas por documento.
    paginar<Documento>((de, ate) =>
      supabase
        .from("documento")
        .select(
          `id, tipo_taxonomia, status, confianca, fonte, justificativa, resumo, criado_em,
           entidade:entidade_id(razao_social), periodo:periodo_id(tipo, referencia),
           documento_versao(id, nome_original, legibilidade, nota_legibilidade)`,
        )
        .eq("caso_id", id)
        .order("criado_em", { ascending: false })
        .order("id", { ascending: true })
        .range(de, ate),
    ),
    // Supabase/migrations/0036 — o checklist é a fonte do TERCEIRO estado: um item pode ter
    // documento e ainda assim não ter uma linha extraída (`recebido_nao_valido`).
    supabase.from("checklist_item_status").select("tipo_taxonomia, status").eq("caso_id", id),
  ]);

  // LEITURA QUE FALHOU NÃO É "NENHUM DOCUMENTO" (regra 1). Antes o erro era jogado fora e a
  // tela dizia "Nenhum documento recebido ainda" / "não recebido" para o Kit inteiro.
  const leituraOk = !kitBasicoRes.error && !documentosRes.error && !documentosRes.truncado && !checklistRes.error;
  if (!leituraOk) {
    const erro = kitBasicoRes.error ?? documentosRes.error ?? checklistRes.error;
    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-lg font-semibold text-tinta-900">Documentos</h1>
        </div>
        <div className="rounded-lg border border-risco-200 bg-risco-50 p-3 text-sm text-risco-800">
          Não foi possível ler os documentos deste mandato, então a grade do Kit Básico e a tabela
          não são mostradas — qualquer coisa que aparecesse aqui poderia ser “não recebido” só
          porque a leitura falhou. Recarregue a página; se persistir, avise o administrador do sistema.
          <DetalhesTecnicos>
            <p>{erro?.message ?? "A lista passou do teto de leitura."}</p>
          </DetalhesTecnicos>
        </div>
      </div>
    );
  }

  const kitBasico = (kitBasicoRes.data as TaxonomiaTipoDocumento[] | null) ?? [];
  const documentos = documentosRes.data;

  // QUANTAS LINHAS CADA DOCUMENTO RENDEU. É o número que o dono procurava abrindo o export, e
  // ele não existia em tela nenhuma: a tabela dizia que o documento chegou e foi classificado,
  // não que ele TROUXE dado. Documento classificado com zero linha é o modo de falha mais caro
  // deste sistema (19 de 35 numa rodada real), e aparece na coluna, em vermelho.
  const versoes = documentos.flatMap((d) => (d.documento_versao ?? []).map((v) => v.id)).filter(Boolean);
  const { porVersao: linhasPorVersao, incompleto: linhasIncompletas } = await contarLinhasPorVersao(supabase, versoes);

  // 0157: a mesma resposta do Portão 1 (`fn_documento_serve_como`), não uma regra própria da tela.
  // Falha da pergunta ao banco = Kit não conferido: a grade NÃO desenha "não recebido"
  // por cima de uma leitura que falhou (revisão do PR #265).
  let kitAtendidos: Set<string> | null = null;
  try {
    kitAtendidos = await itensDoKitBasicoAtendidos(kitBasico, documentos, servicoDocumentoServeComo(supabase));
  } catch {
    kitAtendidos = null;
  }
  const checklist = (checklistRes.data as Array<{ tipo_taxonomia: string; status: string }> | null) ?? [];
  const tiposSemConteudo = new Set(
    checklist.filter((c) => c.status === "recebido_nao_valido").map((c) => c.tipo_taxonomia),
  );

  // ORDEM DA TABELA: pelo NOME DO ARQUIVO, não pela hora do upload. O cliente manda o book
  // numerado (`01_Balanco`, `02_DRE`, …) e procura por esse número; ordenar por `criado_em desc`
  // embaralhava o book na tela e obrigava a varrer a lista inteira para achar um documento.
  documentos.sort((a, b) => {
    const na = (a.documento_versao ?? []).at(-1)?.nome_original ?? "";
    const nb = (b.documento_versao ?? []).at(-1)?.nome_original ?? "";
    return na.localeCompare(nb, "pt-BR", { numeric: true });
  });

  const linhasDoDocumento = (d: Documento) =>
    (d.documento_versao ?? []).reduce((n, v) => n + (linhasPorVersao.get(v.id) ?? 0), 0);
  // Documento que chegou, foi classificado e não rendeu UMA linha. Contagem parcial não é
  // contagem (regra 1): com a leitura incompleta, "sem nenhuma linha" não é dito.
  const semLinha = documentos.filter((d) => linhasDoDocumento(d) === 0);
  // O MESMO critério do chip da tabela (a primeira versão), para o filtro listar só o que a
  // linha mostra como ilegível/degradado.
  const legibilidadeRuimDe = (d: Documento) => {
    const l = d.documento_versao?.[0]?.legibilidade;
    return Boolean(l) && l !== "ok";
  };
  const ilegiveis = documentos.filter(legibilidadeRuimDe);
  const porTipo = new Map<string, number>();
  for (const d of documentos) {
    const t = d.tipo_taxonomia ?? SEM_TIPO;
    porTipo.set(t, (porTipo.get(t) ?? 0) + 1);
  }

  const semComoFiltrar = filtro === "sem-linha" && linhasIncompletas;
  let visiveis = documentos;
  if (filtro === "sem-linha") visiveis = semComoFiltrar ? [] : semLinha;
  else if (filtro === "ilegivel") visiveis = ilegiveis;
  else if (filtro === "tipo") visiveis = documentos.filter((d) => (d.tipo_taxonomia ?? SEM_TIPO) === tipoPedido);

  // A célula "linhas" de cada documento. Com a contagem incompleta, nem o número nem o
  // "nenhuma" são verdade: as linhas podem estar nas páginas que não vieram.
  const celulaDeLinhas = (linhas: number) => {
    if (linhasIncompletas) {
      return (
        <span className="chip bg-alerta-100 text-alerta-800"
              title="A leitura das linhas deste caso não terminou; a contagem não é conhecida.">
          não conferido
        </span>
      );
    }
    if (linhas > 0) return <span className="tabular-nums text-tinta-900">{linhas.toLocaleString("pt-BR")}</span>;
    return (
      <span
        className="chip bg-risco-100 text-risco-800"
        title="O documento foi recebido e classificado, mas nenhuma linha financeira foi gravada."
      >
        nenhuma
      </span>
    );
  };

  const base = `/casos/${id}/documentos`;
  const chipFiltro = (ativo: boolean) =>
    `chip px-3 py-1 ${ativo ? "bg-tinta-800 text-papel" : "bg-tinta-100 text-tinta-700 hover:bg-tinta-200"}`;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-lg font-semibold text-tinta-900">Documentos</h1>
        <p className="mt-0.5 max-w-2xl text-sm text-tinta-500">
          O que chegou do cliente, o que falta do Kit Básico e quantas linhas cada arquivo rendeu.
        </p>
      </div>

      <section>
        <div className="mb-2 flex items-baseline justify-between gap-3">
          <h2 className="titulo-secao">Kit Básico</h2>
          <p className="text-xs text-tinta-500">
            os {kitBasico.length} documentos obrigatórios do mandato
          </p>
        </div>
        {kitAtendidos === null ? (
          <p className="rounded-lg border border-alerta-200 bg-alerta-50 p-3 text-sm text-alerta-800">
            Não foi possível conferir agora quais itens do Kit Básico já chegaram. Recarregue a
            página; até lá, nada aqui deve ser lido como &quot;faltando&quot;.
          </p>
        ) : (
        <ul className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          {kitBasico.map((item) => {
            const semConteudo = tiposSemConteudo.has(item.codigo);
            // TRÊS estados, não dois (0036): verde só quando chegou E rendeu
            // linha. O documento que chegou vazio fica âmbar — não verde, porque
            // o book sai vazio nessa parte, e não "faltante", porque o arquivo
            // está lá e pedi-lo de novo ao cliente seria pedir o que ele mandou.
            const presente = (kitAtendidos?.has(item.codigo) ?? false) && !semConteudo;
            const { cor, corTexto, rotulo } = estadoDoItemDoKit(presente, semConteudo);
            return (
              <li
                key={item.codigo}
                className={`flex items-center justify-between gap-3 rounded-lg border px-3 py-2.5 text-sm ${cor}`}
              >
                <span className="text-tinta-800">{item.documento}</span>
                <span className={`shrink-0 text-xs font-medium ${corTexto}`}>
                  {rotulo}
                </span>
              </li>
            );
          })}
        </ul>
        )}
      </section>


      <nav aria-label="Filtrar documentos" className="space-y-2">
        <div className="flex flex-wrap gap-2">
          <Link href={base} aria-current={filtro === "todos" ? "page" : undefined} className={chipFiltro(filtro === "todos")}>
            Todos ({documentos.length})
          </Link>
          <Link href={`${base}?filtro=sem-linha`} aria-current={filtro === "sem-linha" ? "page" : undefined} className={chipFiltro(filtro === "sem-linha")}>
            Sem linha ({linhasIncompletas ? "não conferido" : semLinha.length})
          </Link>
          <Link href={`${base}?filtro=ilegivel`} aria-current={filtro === "ilegivel" ? "page" : undefined} className={chipFiltro(filtro === "ilegivel")}>
            Ilegível ou degradado ({ilegiveis.length})
          </Link>
        </div>
        {porTipo.size > 0 && (
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs text-tinta-500">Por tipo:</span>
            {[...porTipo.entries()]
              .sort(([a], [b]) => formatarTipoTaxonomia(a).localeCompare(formatarTipoTaxonomia(b), "pt-BR"))
              .map(([t, n]) => (
                <Link
                  key={t}
                  href={`${base}?tipo=${encodeURIComponent(t)}`}
                  aria-current={filtro === "tipo" && tipoPedido === t ? "page" : undefined}
                  className={chipFiltro(filtro === "tipo" && tipoPedido === t)}
                >
                  {rotuloDoTipo(t)} ({n})
                </Link>
              ))}
          </div>
        )}
      </nav>

      <section>
        <div className="mb-2 flex items-baseline justify-between gap-3">
          <h2 className="titulo-secao">Documentos</h2>
          <p className="text-xs text-tinta-500">
            {visiveis.length === documentos.length
              ? `${documentos.length} ${documentos.length === 1 ? "arquivo recebido" : "arquivos recebidos"}`
              : `${visiveis.length} de ${documentos.length} arquivos`}
          </p>
        </div>
        {semComoFiltrar && (
          <div className="mb-2 rounded-lg border border-alerta-200 bg-alerta-50 px-4 py-3 text-sm text-alerta-900">
            Não dá para filtrar por “sem linha”: a leitura das linhas deste mandato não terminou, e
            listar documentos como sem linha quando as linhas podem estar nas páginas que não vieram
            seria afirmar o que não se mediu. Recarregue a página.
          </div>
        )}
        {visiveis.length === 0 ? (
          <div className="carta px-6 py-10 text-center text-sm text-tinta-500">
            {documentos.length === 0 ? "Nenhum documento recebido ainda." : "Nenhum documento neste filtro."}
          </div>
        ) : (
          <div className="carta overflow-x-auto">
            {/* Os ids NA ORDEM EM QUE A TABELA OS MOSTRA (filtro e ordenação já aplicados): o
                painel lateral do documento segue esta ordem no "← anterior / próximo →". */}
            <OrdemDosDocumentos ids={visiveis.map((d) => d.id)} />
            <table className="w-full text-left text-sm">
              <thead className="border-b border-tinta-200 bg-tinta-50 text-[11px] uppercase tracking-wide text-tinta-500">
                <tr>
                  <th className="px-3 py-2.5 font-semibold">Arquivo</th>
                  <th className="px-3 py-2.5 font-semibold">Tipo</th>
                  <th className="px-3 py-2.5 font-semibold">Entidade</th>
                  <th className="px-3 py-2.5 font-semibold">Período</th>
                  {/* A COLUNA QUE FALTAVA. Sem ela a tabela dizia que o arquivo
                      chegou e foi entendido, nunca que ele TROUXE dado. */}
                  <th className="px-3 py-2.5 text-right font-semibold">Linhas</th>
                  {/* CONFIANÇA E ORIGEM NA MESMA COLUNA. Eram duas, e a tabela
                      estourava a largura da tela — a coluna de ação saía cortada
                      ("ve linha"), que é o tipo de defeito que só aparece
                      olhando a página renderizada. São dois fatos sobre a mesma
                      pergunta: o quanto o sistema confia, e por quê. */}
                  <th className="px-3 py-2.5 font-semibold">Confiança</th>
                  <th className="px-3 py-2.5"></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-tinta-100">
                {visiveis.map((doc) => {
                  const versao = doc.documento_versao?.[0];
                  const legibilidadeRuim = versao?.legibilidade && versao.legibilidade !== "ok";
                  const linhas = (doc.documento_versao ?? []).reduce(
                    (n, v) => n + (linhasPorVersao.get(v.id) ?? 0), 0,
                  );
                  return (
                    <LinhaDeDocumento key={doc.id} docId={doc.id} href={`${base}/${doc.id}`}>
                      <td className="max-w-[15rem] px-3 py-2.5">
                        <span
                          className="block truncate font-medium text-tinta-900"
                          title={versao?.nome_original ?? ""}
                        >
                          {versao?.nome_original ?? "—"}
                        </span>
                        {legibilidadeRuim && (
                          <span
                            title={versao?.nota_legibilidade ?? ""}
                            className="ml-2 chip bg-risco-100 text-risco-800"
                          >
                            {LEGIBILIDADE_LABEL[versao!.legibilidade!] ?? versao!.legibilidade}
                          </span>
                        )}
                        {/* O RESUMO SAIU DA COLUNA PRÓPRIA e virou a segunda linha do
                            arquivo: numa coluna estreita ele aparecia truncado em três
                            palavras, o que é ruído com cara de informação. */}
                        {doc.resumo && (
                          <p className="valor-sensivel mt-0.5 max-w-[15rem] truncate text-xs text-tinta-500" title={doc.resumo}>
                            {doc.resumo}
                          </p>
                        )}
                      </td>
                      <td className="px-3 py-2.5 whitespace-nowrap text-tinta-700">
                        {formatarTipoTaxonomia(doc.tipo_taxonomia)}
                      </td>
                      <td className="max-w-[10rem] truncate px-3 py-2.5 text-tinta-700"
                          title={doc.entidade?.razao_social ?? ""}>
                        {doc.entidade?.razao_social ?? "—"}
                      </td>
                      <td className="px-3 py-2.5 whitespace-nowrap text-tinta-700">
                        {doc.periodo ? formatarPeriodo(doc.periodo.tipo, doc.periodo.referencia) : "—"}
                      </td>
                      <td className="px-3 py-2.5 text-right">
                        {celulaDeLinhas(linhas)}
                      </td>
                      <td className="px-3 py-2.5 whitespace-nowrap">
                        <span className="tabular-nums text-tinta-700">
                          {doc.confianca != null ? `${Math.round(doc.confianca * 100)}%` : "—"}
                        </span>
                        {doc.fonte && (
                          <span
                            className="ml-1.5 hidden text-xs text-tinta-500 xl:inline"
                            title={`Como o documento foi reconhecido: ${FONTE_LABEL[doc.fonte] ?? humanizar(doc.fonte)}`}
                          >
                            · {FONTE_LABEL[doc.fonte] ?? humanizar(doc.fonte)}
                          </span>
                        )}
                      </td>
                      <td className="px-3 py-2.5 text-right whitespace-nowrap text-xs">
                        <Link
                          href={`${base}/${doc.id}`}
                          prefetch={false}
                          className="font-medium text-acento-600 hover:text-acento-700 hover:underline"
                        >
                          abrir
                        </Link>
                      </td>
                    </LinhaDeDocumento>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

    </div>
  );
}

// Os TRÊS estados de um item do Kit Básico (0036), fora do componente para a
// página não acumular ternário aninhado (Sonar S3358/S3776).
function estadoDoItemDoKit(presente: boolean, semConteudo: boolean) {
  if (presente) return { cor: "border-ok-200 bg-ok-50/60", corTexto: "text-ok-700", rotulo: "✓ recebido" };
  if (semConteudo) {
    return { cor: "border-alerta-200 bg-alerta-50", corTexto: "text-alerta-800", rotulo: "chegou, sem dado extraído" };
  }
  return { cor: "border-tinta-200 bg-folha", corTexto: "text-tinta-400", rotulo: "não recebido" };
}

function rotuloDoTipo(t: string): string {
  return t === SEM_TIPO ? "Sem tipo" : formatarTipoTaxonomia(t);
}
