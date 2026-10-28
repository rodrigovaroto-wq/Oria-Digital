import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { paginar } from "@/lib/supabase/paginar";
import { contarLinhasPorVersao } from "@/lib/supabase/linhas-por-versao";
import { servicoDocumentoServeComo } from "@/lib/supabase/servico-serve-como";
import {
  PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS,
  type Caso,
  type Documento,
  type FatoDoCaso,
  type TaxonomiaTipoDocumento,
} from "@/lib/types";
import { aprovarCaso } from "./actions";
import { suavizarMensagem } from "@/lib/rotulos";
import { itensDoKitBasicoAtendidos } from "@/lib/kit-basico";
import { ESTADOS_EM_ABERTO } from "@/lib/pendencia";
import { proximoPasso } from "@/lib/proximo-passo";

// Um indicador do topo. Número grande, rótulo embaixo, e um detalhe opcional em
// cor quando ele muda a leitura do número (ex.: "2 bloqueantes"). Cada um leva à aba
// onde o número se explica (fase 2): um número sem para onde ir é só decoração.
function Indicador({
  valor, rotulo, detalhe, tom, href,
}: Readonly<{
  valor: string | number;
  rotulo: string;
  detalhe?: string | null;
  tom?: "neutro" | "alerta" | "bom";
  href: string;
}>) {
  const corDetalhe =
    tom === "alerta" ? "text-risco-700" : tom === "bom" ? "text-ok-700" : "text-tinta-500";
  return (
    <Link href={href} className="block px-4 py-3 transition-colors hover:bg-tinta-50">
      <p className="indicador-valor">{valor}</p>
      <p className="indicador-rotulo">{rotulo}</p>
      {detalhe && <p className={`mt-1 text-xs font-medium ${corDetalhe}`}>{detalhe}</p>}
    </Link>
  );
}

// O QUE O DOCUMENTO DIZ EM TEXTO (Supabase/migrations/0148).
//
// ONDE ESTE BLOCO FICA, e por que ele MUDOU DE LUGAR em 27/08/2026. Ele abria a
// tela, acima do Kit Básico, pelo argumento de que um comitê de crédito lê a
// ressalva antes da planilha. O dono decidiu o contrário depois de ver a tela
// com fato de verdade dentro (o smoke test da `0148`), e a razão vence a minha:
// quem abre o mandato está conferindo o RECEBIMENTO — o que chegou e o que
// falta —, e um alerta de covenant no topo empurra a conferência para baixo da
// dobra logo no dia em que ela é o trabalho. O bloco passa a vir depois do Kit
// Básico e de Documentos, fechando a leitura "o que chegou → o que os papéis
// dizem" e ainda ANTES da fila de pendências.
//
// O que NÃO mudou, e é o que a posição não podia custar: ele continua fora da
// fila de trabalho. Ressalva de auditoria e covenant rompido não são "algo a
// corrigir" — são o motivo por trás dos números —, e pô-los entre as pendências
// seria pedir que alguém "resolvesse" um fato do mundo.
//
// E O TRECHO VEM PRIMEIRO, EM CORPO MAIOR QUE A LEITURA. A frase é do documento
// e dá para conferir abrindo a página; a leitura é do modelo. Inverter a ordem
// faria a interpretação parecer a fonte — que é o defeito que este produto passa
// o tempo corrigindo em número, e aqui seria em prosa.
const TOM_FATO: Record<string, { caixa: string; chip: string }> = {
  critico:     { caixa: "border-risco-300 bg-risco-50",   chip: "bg-risco-100 text-risco-800" },
  relevante:   { caixa: "border-alerta-300 bg-alerta-50", chip: "bg-alerta-100 text-alerta-800" },
  informativo: { caixa: "border-tinta-200 bg-papel",      chip: "bg-tinta-100 text-tinta-700" },
};

function FatoMaterial({ f }: Readonly<{ f: FatoDoCaso }>) {
  const tom = TOM_FATO[f.severidade] ?? TOM_FATO.informativo;
  return (
    <li className={`rounded-lg border px-4 py-3 ${tom.caixa}`}>
      <div className="mb-1.5 flex flex-wrap items-baseline gap-2">
        <span className={`chip ${tom.chip}`}>{f.rotulo}</span>
        <span className="text-xs text-tinta-500">
          {f.nome_documento ?? "documento sem nome"}
          {f.pagina != null && `, p. ${f.pagina}`}
        </span>
      </div>
      {/* A EVIDÊNCIA. Citação, e não parágrafo: a barra à esquerda diz, sem
          precisar de legenda, que aquelas palavras são do documento e não
          nossas. */}
      <blockquote className="border-l-2 border-tinta-300 pl-3 text-sm italic text-tinta-800">
        “{f.trecho}”
      </blockquote>
      {f.leitura && <p className="mt-1.5 text-sm text-tinta-700">{f.leitura}</p>}
      <p className="mt-1.5 text-xs text-tinta-500">{f.porque}</p>
    </li>
  );
}

export default async function CasoDashboardPage({
  params,
}: Readonly<{
  params: Promise<{ id: string }>;
}>) {
  const { id } = await params;
  const supabase = await createClient();

  // PENDÊNCIA EM ABERTO = `ESTADOS_EM_ABERTO`, a mesma lista do layout e da aba Pendências.
  // Três contagens `head: true` (só o número, nenhuma linha) no lugar da lista inteira: esta
  // tela não mostra mais nenhuma pendência, só quantas e se travam. A decidida
  // (aceita_com_ressalva, rejeitada) e a resolvida ficam de fora, como já ficavam.
  const abertas = () =>
    supabase.from("pendencia").select("id", { head: true, count: "exact" }).eq("caso_id", id).in("estado", [...ESTADOS_EM_ABERTO]);

  const [casoRes, kitBasicoRes, documentosRes, abertasRes, bloqueantesRes, revisoesRes, checklistRes,
         portao2Res, fatosRes, modeloRes] = await Promise.all([
    supabase.from("caso").select("id, nome, produto, status, criado_em").eq("id", id).single(),
    supabase
      .from("taxonomia_tipo_documento")
      .select("codigo, categoria, documento, obrigatoriedade")
      .eq("obrigatoriedade", "obrigatorio")
      .order("codigo"),
    // SÓ O QUE OS INDICADORES PRECISAM: o tipo (Kit Básico) e as versões (soma de linhas).
    // A tabela de documentos mora na aba Documentos; ler resumo, entidade e período aqui
    // seria egress sem nenhum leitor. PAGINADA: o teto do PostgREST corta em silêncio, e
    // aqui as linhas são o conteúdo — a soma de linhas e o "documentos sem linha".
    paginar<Pick<Documento, "id" | "tipo_taxonomia" | "documento_versao">>((de, ate) =>
      supabase
        .from("documento")
        .select("id, tipo_taxonomia, documento_versao(id)")
        .eq("caso_id", id)
        .order("id", { ascending: true })
        .range(de, ate),
    ),
    abertas(),
    abertas().eq("severidade", "bloqueante"),
    abertas().in("tipo", [...PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS]),
    // Supabase/migrations/0036 — o checklist é a fonte do TERCEIRO estado: um item pode
    // ter documento e ainda assim não ter uma linha extraída (`recebido_nao_valido`).
    supabase
      .from("checklist_item_status")
      .select("tipo_taxonomia, status")
      .eq("caso_id", id),
    // Supabase/migrations/0037 — a avaliação do Portão 2. Determinística e sem efeito
    // colateral (a função é `stable`), então dá para chamar a cada render: é a
    // MESMA função que `fn_aprovar_caso` usa para decidir, e não uma segunda
    // implementação da regra aqui no portal.
    supabase.rpc("fn_avaliar_portao2", { p_caso_id: id }),
    // O QUE OS DOCUMENTOS DIZEM EM TEXTO (0148). TOLERANTE A ERRO: o dono aplica as
    // migrations à mão, então banco sem a 0148 é estado normal e não defeito. Aí
    // esta chamada responde "não achei a função", o bloco não aparece, e o resto
    // da tela do mandato continua de pé.
    supabase.rpc("fn_fatos_do_caso", { p_caso_id: id }),
    // O modelo está montado? As mesmas três coisas sem as quais Entregáveis recusa a apresentação.
    supabase.from("caso_modelagem").select("entidade, ultimo_exercicio_real, anos_projetados").eq("caso_id", id).maybeSingle(),
  ]);

  if (casoRes.error || !casoRes.data) {
    notFound();
  }

  const caso = casoRes.data as Caso;
  const kitBasico = (kitBasicoRes.data as TaxonomiaTipoDocumento[] | null) ?? [];
  const documentos = documentosRes.data;
  // Lista de documentos lida por inteiro? Sem isso, nem a soma de linhas nem o Kit Básico são
  // verdade (regra 1) — antes o erro era jogado fora e a tela mostrava "0 documentos".
  const documentosLidos = !documentosRes.error && !documentosRes.truncado;

  // QUANTAS LINHAS CADA DOCUMENTO RENDEU — soma para o indicador e "documentos sem linha".
  const versoes = documentos
    .flatMap((d) => (d.documento_versao ?? []).map((v) => v.id))
    .filter(Boolean);
  const { porVersao: linhasPorVersao, incompleto: linhasIncompletas } = await contarLinhasPorVersao(supabase, versoes);

  // 0157: o Kit Básico é perguntado ao banco (`fn_documento_serve_como`), não reimplementado
  // aqui — ver `lib/supabase/servico-serve-como.ts` e `verificar-kit-basico.mts`.
  // Falha da pergunta ao banco = Kit NÃO LIDO (null), nunca "itens faltantes".
  let kitAtendidos: Set<string> | null = null;
  try {
    kitAtendidos = await itensDoKitBasicoAtendidos(
      kitBasico, documentos as Documento[], servicoDocumentoServeComo(supabase),
    );
  } catch {
    kitAtendidos = null;
  }
  // Os fatos materiais. `?? []` e não `!`: banco sem a 0148 devolve erro e `data` nulo, e a
  // tela tem de sair sem o bloco em vez de quebrar.
  const fatos = (fatosRes.data as FatoDoCaso[] | null) ?? [];
  const fatosCriticos = fatos.filter((f) => f.severidade === "critico").length;

  const portao2 = portao2Res.data as {
    elegivel: boolean; motivos: string[]; ressalvas_ativas: number; teto_ressalvas: number;
    status_atual: string;
    // Supabase/migrations/0106 — quantas pendências foram declaradas IMPROCEDENTES.
    // Não entra na regra (rejeitada é estado terminal); entra na tela porque é a
    // única informação que separa um caso que nunca teve pendência de um que
    // teve e as rejeitou. Opcionais: um banco onde a 0106 ainda não foi aplicada
    // devolve o payload da 0037, e a tela tem de continuar funcionando.
    rejeitadas?: number; rejeitadas_nao_sobrepujaveis?: number;
  } | null;
  const checklist = (checklistRes.data as Array<{ tipo_taxonomia: string; status: string }> | null) ?? [];
  const tiposSemConteudo = new Set(
    checklist.filter((c) => c.status === "recebido_nao_valido").map((c) => c.tipo_taxonomia),
  );

  // Contagem que falhou sai como null — nunca 0 (regra 1).
  const contagem = (r: { error: unknown; count: number | null }) => (r.error ? null : r.count);
  const nAbertas = contagem(abertasRes);
  const nBloqueantes = contagem(bloqueantesRes);
  const nRevisoes = contagem(revisoesRes);

  const linhasTotais = [...linhasPorVersao.values()].reduce((a, b) => a + b, 0);
  const kitLido = !kitBasicoRes.error && documentosLidos && !checklistRes.error && kitAtendidos !== null;
  const kitPresentes = kitBasico.filter(
    (i) => (kitAtendidos?.has(i.codigo) ?? false) && !tiposSemConteudo.has(i.codigo),
  ).length;
  // Documento que chegou, foi classificado e não rendeu UMA linha. É o que o
  // `fn_conferir_lote` mede do lado do banco; aqui ele vira número de topo,
  // porque é a pergunta que a rodada v45 respondeu tarde demais.
  const semLinha = documentos.filter(
    (d) => ((d.documento_versao ?? []).reduce((n, v) => n + (linhasPorVersao.get(v.id) ?? 0), 0)) === 0,
  ).length;
  // Contagem parcial não é contagem (regra 1): com a leitura incompleta, a soma parcial NÃO
  // aparece como total (o valor vira "—") e "sem nenhuma linha" não é dito — contaria
  // documento cujas linhas estavam nas páginas que não vieram.
  const linhasConhecidas = documentosLidos && !linhasIncompletas;
  let detalheDasLinhas: string | null = null;
  if (!documentosLidos) detalheDasLinhas = "a leitura dos documentos falhou";
  else if (linhasIncompletas) detalheDasLinhas = "contagem incompleta — a leitura das linhas não terminou";
  else if (semLinha > 0) detalheDasLinhas = `${semLinha} ${semLinha === 1 ? "documento sem nenhuma linha" : "documentos sem nenhuma linha"}`;

  const aprovado = caso.status === "aprovado" || caso.status === "pronto_para_base";
  const modelo = modeloRes.data as { entidade: string | null; ultimo_exercicio_real: number | null; anos_projetados: number | null } | null;
  const passo = proximoPasso({
    bloqueantesAbertas: nBloqueantes,
    revisoesAbertas: nRevisoes,
    kitFaltantes: kitLido ? kitBasico.length - kitPresentes : null,
    aprovavel: portao2 ? portao2.elegivel : null,
    aprovado,
    // Falta de configuração é uma resposta ("não montou"); erro de leitura é outra ("não sei").
    modeloMontado: modeloRes.error ? null : Boolean(modelo?.entidade?.trim()) && modelo?.ultimo_exercicio_real != null && Boolean(modelo?.anos_projetados),
  });
  const base = `/casos/${id}`;

  // Leitura de bloqueantes que falhou é DITA, não some: `(null ?? 0) > 0` escondia a
  // falha e o indicador parecia dizer "nenhuma trava" (regra 1).
  let detalheDasPendencias: string | null = null;
  if (nAbertas === null) detalheDasPendencias = "a leitura das pendências falhou";
  else if (nBloqueantes === null) detalheDasPendencias = "não foi possível saber quantas travam a aprovação";
  else if (nBloqueantes > 0) {
    detalheDasPendencias = `${nBloqueantes} ${nBloqueantes === 1 ? "bloqueia" : "bloqueiam"} a aprovação`;
  }
  let detalheDoKit: string | null = "a leitura do kit falhou";
  if (kitLido) detalheDoKit = kitPresentes === kitBasico.length ? "kit completo" : null;

  return (
    <div className="space-y-8">
      {/* O PRÓXIMO PASSO, uma frase e um botão, decidido por `lib/proximo-passo.ts` (a prioridade
          está documentada lá). Substitui a faixa amarela "Revisar agora" e o empilhamento de
          seções: o que estava na frente de quem abria o mandato era tudo ao mesmo tempo. Leitura
          que falhou vira "não dá para determinar" — nunca um passo chutado. */}
      <section
        aria-label="Próximo passo"
        className={`carta flex flex-wrap items-center justify-between gap-3 px-4 py-3 ${passo.passo === "indeterminado" ? "border-alerta-200 bg-alerta-50" : ""}`}
      >
        <div className="min-w-0">
          <p className="text-xs font-medium uppercase tracking-wide text-tinta-500">Próximo passo</p>
          <p className="mt-0.5 text-base font-semibold text-tinta-900">{passo.titulo}</p>
          <p className="mt-0.5 max-w-2xl text-sm text-tinta-600">{passo.detalhe}</p>
        </div>
        {passo.acao && passo.href && (
          <Link href={passo.href.startsWith("#") ? passo.href : `${base}${passo.href}`} className="btn-primario">
            {passo.acao}
          </Link>
        )}
      </section>

      {/* O RESUMO. Quem abre um mandato pergunta uma coisa: "posso confiar neste caso?". Os
          quatro números respondem em um olhar, e o terceiro — documentos sem uma linha extraída —
          é o que a rodada de 15/08 descobriu tarde: documento classificado, checklist verde, e
          nada no banco. Cada um leva à aba onde se explica. */}
      <div className="carta grid grid-cols-2 divide-x divide-y divide-tinta-100 sm:grid-cols-4 sm:divide-y-0">
        <Indicador
          valor={documentosLidos ? documentos.length : "—"}
          rotulo="documentos recebidos"
          detalhe={documentosLidos ? null : "a leitura dos documentos falhou"}
          tom="alerta"
          href={`${base}/documentos`}
        />
        <Indicador
          valor={linhasConhecidas ? linhasTotais.toLocaleString("pt-BR") : "—"}
          rotulo="linhas financeiras extraídas"
          detalhe={detalheDasLinhas}
          tom="alerta"
          href={linhasConhecidas && semLinha > 0 ? `${base}/documentos?filtro=sem-linha` : `${base}/documentos`}
        />
        <Indicador
          valor={kitLido ? `${kitPresentes}/${kitBasico.length}` : "—"}
          rotulo="itens do Kit Básico"
          detalhe={detalheDoKit}
          tom={kitLido ? "bom" : "alerta"}
          href={`${base}/documentos`}
        />
        <Indicador
          valor={nAbertas ?? "—"}
          rotulo={nAbertas === 1 ? "pendência em aberto" : "pendências em aberto"}
          detalhe={detalheDasPendencias}
          tom="alerta"
          href={`${base}/pendencias`}
        />
      </div>

      {/* PORTÃO 2 (Supabase/migrations/0037) — a regra de Arquitetura do Sistema/2 Especificação/f0/04, visível.
          Antes desta tela não havia como saber se um caso podia ser aprovado:
          a regra não existia em código, e "não implementado" tem a mesma
          aparência de "sem pendência bloqueante" para quem olha o dashboard. */}
      {portao2 ? (
        <div
          id="aprovacao"
          className={`scroll-mt-24 rounded-lg border p-4 text-sm ${
            portao2.elegivel ? "border-ok-200 bg-ok-50" : "carta"
          }`}
        >
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              {/* "PORTÃO 2" É NOME INTERNO (Arquitetura do Sistema/2 Especificação/f0/04). Quem confere um mandato não
                  precisa do número da etapa — precisa saber se pode aprovar e o
                  que falta. O nome fica como legenda, não como manchete. */}
              <p className={`font-semibold ${portao2.elegivel ? "text-ok-900" : "text-tinta-900"}`}>
                {portao2.elegivel
                  ? "Pronto para aprovação"
                  : "Ainda não pode ser aprovado"}
              </p>
              {!portao2.elegivel && portao2.motivos?.length > 0 && (
                <ul className="mt-1.5 list-disc space-y-0.5 pl-5 text-tinta-700">
                  {/* A MENSAGEM VEM DO BANCO com "(s)" e caixa alta —
                      "4 pendência(s) BLOQUEANTE(s) sem decisão". `suavizarMensagem`
                      já existia para as pendências; o motivo do portão passava direto. */}
                  {portao2.motivos.map((m) => (
                    <li key={m}>{suavizarMensagem(m)}</li>
                  ))}
                </ul>
              )}
              {/* A MESMA REGRA, EM PORTUGUÊS (pedido do dono, 07/08/2026). Antes esta
                  linha dizia "Ressalvas ativas: 0 de 3 (teto por caso, Arquitetura do Sistema/2 Especificação/f0/04)" — três
                  coisas erradas de uma vez: citava um documento interno pelo código,
                  mostrava contagem sem dizer o que é uma ressalva, e não explicava a
                  consequência. Quem lê a tela precisa saber o que pode fazer, não o
                  número de referência da norma. */}
              {/* A CONTAGEM, sem teto (0109). O limite de 3 saiu por decisão do
                  dono; o número continua na tela porque é o que distingue um caso
                  limpo de um caso que seguiu por cima de seis pendências. */}
              <p className="mt-1.5 text-xs text-tinta-600">
                {portao2.ressalvas_ativas === 0
                  ? "Nenhuma pendência foi aceita sem resolução neste caso."
                  : `${portao2.ressalvas_ativas} ${portao2.ressalvas_ativas === 1
                      ? "pendência seguiu sem resolução" : "pendências seguiram sem resolução"}`
                    + " — o caso avança com elas registradas, não resolvidas."}
              </p>
              {/* O QUE FOI DECLARADO IMPROCEDENTE (0106). Rejeitar é a única ação
                  que libera o portão SEM TETO — inclusive a pendência que nenhuma
                  ressalva libera. Não dá para proibir (senão uma pendência
                  errada prende o caso para sempre, e o que sobra é editar a
                  tabela por fora, que é a mesma liberação sem rastro). O que dá
                  é não deixar invisível: aqui, e dentro da decisão de aprovação. */}
              {(portao2.rejeitadas ?? 0) > 0 && (
                <p className="mt-1 text-xs text-tinta-700">
                  <strong>
                    {portao2.rejeitadas === 1
                      ? "1 pendência foi declarada improcedente"
                      : `${portao2.rejeitadas} pendências foram declaradas improcedentes`}
                  </strong>
                  {(portao2.rejeitadas_nao_sobrepujaveis ?? 0) > 0 && (
                    <>
                      {", "}
                      {portao2.rejeitadas_nao_sobrepujaveis === 1
                        ? "sendo 1 daquelas que nenhuma ressalva libera"
                        : `sendo ${portao2.rejeitadas_nao_sobrepujaveis} daquelas que nenhuma `
                          + "ressalva libera"}
                    </>
                  )}
                  . Quem decidiu e por quê está na trilha do caso, e vai junto com a aprovação.
                </p>
              )}
            </div>
            {portao2.elegivel && caso.status !== "aprovado" && caso.status !== "pronto_para_base" && (
              <form action={aprovarCaso.bind(null, id)} className="flex items-center gap-2">
                <input
                  type="text"
                  name="motivo"
                  placeholder="Observação da aprovação (opcional)"
                  aria-label="Observação da aprovação"
                  className="w-56 rounded-md border border-tinta-200 px-2.5 py-1.5 text-sm
                             placeholder:text-tinta-400"
                />
                <button type="submit" className="btn-aprovar">
                  Aprovar mandato
                </button>
              </form>
            )}
          </div>
        </div>
      ) : (
        // AVALIAÇÃO QUE NÃO RESPONDEU (regra 1). Antes o cartão simplesmente não aparecia, e a
        // ausência do cartão lê-se como "nada a aprovar" — a mesma aparência de um caso sem problema.
        <div id="aprovacao" aria-live="polite" className="carta scroll-mt-24 p-4 text-sm text-alerta-900">
          <p className="font-semibold">Aprovação não conferida</p>
          <p className="mt-1 text-xs">
            A consulta que diz se o mandato pode ser aprovado não respondeu, então não dá para dizer
            se ele pode ou não. Recarregue a página; se persistir, avise o administrador do sistema.
          </p>
        </div>
      )}

      {fatos.length > 0 && (
        <section>
          <div className="mb-2 flex items-baseline justify-between gap-3">
            <h2 className="titulo-secao">O que os documentos dizem</h2>
            <p className="text-xs text-tinta-500">
              {fatosCriticos > 0
                ? `${fatos.length} fato(s), ${fatosCriticos} crítico(s)`
                : `${fatos.length} fato(s) declarado(s) em texto`}
            </p>
          </div>
          <p className="mb-2.5 text-xs text-tinta-500">
            Lido do texto dos documentos, não das tabelas — é o que costuma explicar os números.
            Cada item traz a frase do próprio documento, para conferir na página indicada.
          </p>
          <ul className="space-y-2">
            {fatos.map((f) => <FatoMaterial key={f.fato_id} f={f} />)}
          </ul>
        </section>
      )}
    </div>
  );
}
