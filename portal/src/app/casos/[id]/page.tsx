import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { paginar } from "@/lib/supabase/paginar";
import { contarLinhasPorVersao } from "@/lib/supabase/linhas-por-versao";
import {
  PENDENCIA_TIPOS_RECONCILIACAO,
  PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS,
  PENDENCIA_TIPOS_QUALIDADE_EXTRACAO,
  PENDENCIA_TIPO_ARQUIVO_ILEGIVEL,
  type Caso,
  type Documento,
  type FatoDoCaso,
  type Pendencia,
  type TaxonomiaTipoDocumento,
} from "@/lib/types";
import { aprovarCaso } from "./actions";
import { ItemPendencia } from "./Pendencia";
import { humanizar, suavizarMensagem } from "@/lib/rotulos";
import { formatarPeriodo, formatarTipoTaxonomia } from "@/lib/export";
import { itensDoKitBasicoAtendidos, type ServicoDocumentoServeComo } from "@/lib/kit-basico";

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

// Um indicador do topo. Número grande, rótulo embaixo, e um detalhe opcional em
// cor quando ele muda a leitura do número (ex.: "2 bloqueantes").
function Indicador({
  valor, rotulo, detalhe, tom,
}: Readonly<{
  valor: string | number;
  rotulo: string;
  detalhe?: string | null;
  tom?: "neutro" | "alerta" | "bom";
}>) {
  const corDetalhe =
    tom === "alerta" ? "text-risco-700" : tom === "bom" ? "text-ok-700" : "text-tinta-500";
  return (
    <div className="px-4 py-3">
      <p className="indicador-valor">{valor}</p>
      <p className="indicador-rotulo">{rotulo}</p>
      {detalhe && <p className={`mt-1 text-xs font-medium ${corDetalhe}`}>{detalhe}</p>}
    </div>
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
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const [casoRes, kitBasicoRes, documentosRes, pendenciasRes, checklistRes, portao2Res,
         fatosRes] = await Promise.all([
    supabase.from("caso").select("id, nome, produto, status, criado_em").eq("id", id).single(),
    supabase
      .from("taxonomia_tipo_documento")
      .select("codigo, categoria, documento, obrigatoriedade")
      .eq("obrigatoriedade", "obrigatorio")
      .order("codigo"),
    // AS LISTAS DESTA TELA SÃO PAGINADAS. O teto do PostgREST (`db-max-rows`,
    // 1000 no Supabase) corta em silêncio, e aqui as linhas são o conteúdo: a
    // tabela de documentos, a fila de pendências do mandato e a contagem de
    // linhas por documento. Um mandato grande passava a mostrar só os mil
    // primeiros de cada, sem nada na tela dizendo isso.
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
    paginar<Pendencia>((de, ate) =>
      supabase
        .from("pendencia")
        .select("id, tipo, severidade, estado, descricao, documento_id, caso_id, criada_em")
        .eq("caso_id", id)
      // A PENDÊNCIA DECIDIDA CONTINUA NA TELA — e isto é o que faz os três
      // botões (0109) terem sentido. Eles "adicionam um rótulo na pendência";
      // se o item sumisse ao ser decidido, o rótulo não existiria para ninguém
      // ver, e a única forma de saber o que foi decidido seria abrir o banco.
      //
      // Fica de fora só `resolvida`, que é do SISTEMA: o problema deixou de
      // existir, não há decisão humana para exibir nem nada a reconsiderar.
        .in("estado", ["aberta", "em_correcao_interna", "reenviada_ao_cliente",
                       "aceita_com_ressalva", "rejeitada"])
        .order("criada_em", { ascending: false })
        .order("id", { ascending: true })
        .range(de, ate),
    ),
    // Supabase/migrations/0036 — o checklist é a fonte do TERCEIRO estado: um item pode
    // ter documento e ainda assim não ter uma linha extraída
    // (`recebido_nao_valido`). Antes o dashboard derivava "presente" só da
    // existência do documento, e por isso ficava verde sobre um book vazio.
    supabase
      .from("checklist_item_status")
      .select("tipo_taxonomia, status")
      .eq("caso_id", id),
    // Supabase/migrations/0037 — a avaliação do Portão 2. Determinística e sem efeito
    // colateral (a função é `stable`), então dá para chamar a cada render: é a
    // MESMA função que `fn_aprovar_caso` usa para decidir, e não uma segunda
    // implementação da regra aqui no portal.
    supabase.rpc("fn_avaliar_portao2", { p_caso_id: id }),
    // O QUE OS DOCUMENTOS DIZEM EM TEXTO (0148). Covenant rompido, ressalva de
    // auditoria, continuidade operacional — os fatos que um comitê lê ANTES da
    // planilha, e que até a v48 não chegavam ao portal de forma nenhuma: as
    // Notas Explicativas e o Parecer entravam, eram classificados e ficavam
    // mudos, porque não têm tabela e o sistema inteiro lê tabela.
    //
    // TOLERANTE A ERRO pela mesma razão da linha acima: o dono aplica as
    // migrations à mão, então banco sem a 0148 é estado normal e não defeito. Aí
    // esta chamada responde "não achei a função", o bloco não aparece, e o resto
    // da tela do mandato continua de pé.
    supabase.rpc("fn_fatos_do_caso", { p_caso_id: id }),
  ]);

  // QUANTAS LINHAS CADA DOCUMENTO RENDEU. É o número que o dono procurava
  // abrindo o export, e ele não existia em tela nenhuma: a tabela dizia que o
  // documento chegou e foi classificado, não que ele TROUXE dado. Documento
  // classificado com zero linha é o modo de falha mais caro deste sistema (19 de
  // 35 numa rodada real), e agora ele aparece na coluna, em vermelho.
  const versoes = documentosRes.data
    .flatMap((d) => (d.documento_versao ?? []).map((v) => v.id))
    .filter(Boolean);
  const { porVersao: linhasPorVersao, incompleto: linhasIncompletas } = await contarLinhasPorVersao(supabase, versoes);

  if (casoRes.error || !casoRes.data) {
    notFound();
  }

  const caso = casoRes.data as Caso;
  const kitBasico = (kitBasicoRes.data as TaxonomiaTipoDocumento[] | null) ?? [];
  const documentos = documentosRes.data;
  const pendencias = pendenciasRes.data;

  // 0157 (Supabase/migrations/0157_o_combinado_que_travava_o_kit_basico.sql):
  // esta tela perguntava sozinha, comparando `tipo_taxonomia === codigo`, se
  // um item do Kit Básico estava presente — a MESMA regra que
  // `fn_recomputar_completude` passo (1) usava até a 0157 trocá-la, no banco,
  // por `fn_documento_serve_como` (rótulo OU, só para COMBINADO, estrutura —
  // `fn_documento_de_varias_empresas`, 0155). Com a implementação antiga
  // ainda aqui, o lote 7377 media o Portão 1 aberto (a pendência
  // `item_faltante: COMBINADO` resolvida) e, na mesma tela, a grade do Kit
  // Básico desenhando COMBINADO em cinza — a MESMA verdade discordando de si
  // mesma. `itensDoKitBasicoAtendidos` pergunta ao banco pelos itens que o
  // rótulo não resolveu (`servicoDocumentoServeComo` abaixo); não reimplementa
  // `fn_documento_de_varias_empresas` em TypeScript — isso seria trocar uma
  // segunda regra por outra mais nova.
  const servicoDocumentoServeComo: ServicoDocumentoServeComo = async (documentoId, tipoTaxonomia) => {
    const { data, error } = await supabase.rpc("fn_documento_serve_como", {
      p_documento_id: documentoId,
      p_tipo_taxonomia: tipoTaxonomia,
    });
    // TOLERANTE A ERRO pela mesma razão de `fn_sugerir_perguntas`/`fn_fatos_do_caso`
    // acima: o dono aplica migrations à mão, e um banco sem a 0157 é estado
    // normal, não defeito. Sem a função, a resposta é a mesma de ANTES da
    // 0157 — só o rótulo conta — e nunca "satisfeito" por invenção do portal.
    if (error) return false;
    return data === true;
  };
  const kitAtendidos = await itensDoKitBasicoAtendidos(kitBasico, documentos, servicoDocumentoServeComo);
  // Chegou, mas não rendeu uma linha: nem verde nem faltante — é o
  // `recebido_nao_valido` de `Arquitetura do Sistema/3 Estado e Execução/07`, e é bloqueante para o Portão 2.
  // Os fatos materiais. `?? []` e não `!`: banco sem a 0148 devolve erro e
  // `data` nulo, e a tela tem de sair sem o bloco em vez de quebrar.
  const fatos = (fatosRes.data as FatoDoCaso[] | null) ?? [];
  // O MESMO filtro rodava duas vezes no JSX — uma para decidir a frase, outra
  // para o número dela. `.some()` sozinho não resolveria: a contagem É o dado
  // que a frase mostra, então o que sobrava era percorrer a lista duas vezes
  // para responder a mesma pergunta.
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
  // DECIDIDA VAI PARA O FIM. Quem abre a tela quer ver o que falta decidir; o
  // que já foi decidido continua visível (é onde o rótulo mora), mas embaixo.
  const DECIDIDOS = new Set(["aceita_com_ressalva", "rejeitada"]);
  const emAberto = (p: Pendencia) => !DECIDIDOS.has(p.estado);
  const porDecidirPrimeiro = (a: Pendencia, b: Pendencia) =>
    Number(!emAberto(a)) - Number(!emAberto(b));

  const pendenciasRevisao = pendencias.filter((p) =>
    (PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS as readonly string[]).includes(p.tipo),
  );
  const pendenciasReconciliacao = pendencias.filter((p) =>
    (PENDENCIA_TIPOS_RECONCILIACAO as readonly string[]).includes(p.tipo),
  );
  const pendenciasArquivo = pendencias.filter((p) => p.tipo === PENDENCIA_TIPO_ARQUIVO_ILEGIVEL);
  const pendenciasExtracao = pendencias.filter((p) =>
    (PENDENCIA_TIPOS_QUALIDADE_EXTRACAO as readonly string[]).includes(p.tipo),
  );

  // O RESTO — e "o resto" era o BURACO desta tela.
  //
  // As quatro listas acima são por tipo, escolhidas a dedo. Toda pendência de
  // tipo que não está em nenhuma delas simplesmente NÃO APARECIA — e as duas que
  // caem aqui são as que mais bloqueiam: `item_faltante` (obrigatório do Kit
  // Básico ausente, bloqueante, 0004/0036) e `item_sem_conteudo` (chegou e não
  // rendeu uma linha — bloqueante NÃO-SOBREPUJÁVEL, 0036). O card do Portão 2
  // dizia "2 pendência(s) BLOQUEANTE(s) em aberto" e não havia, na página
  // inteira, uma linha que dissesse QUAIS.
  //
  // A grade do Kit Básico mostra o FATO ("faltante", "recebido, sem conteúdo
  // extraído"), o que é fácil confundir com "então está mostrado". Não é a mesma
  // coisa: a pendência é o objeto que bloqueia e sobre o qual se decide, e é ela
  // que precisa estar na tela para poder ser rejeitada. Lista por COMPLEMENTO,
  // não por enumeração: tipo novo nasce visível: o erro que se paga por esquecer
  // de listar é o de mostrar demais, não o de esconder um bloqueio.
  const TIPOS_COM_SECAO_PROPRIA = new Set<string>([
    ...PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS,
    ...PENDENCIA_TIPOS_RECONCILIACAO,
    ...PENDENCIA_TIPOS_QUALIDADE_EXTRACAO,
    PENDENCIA_TIPO_ARQUIVO_ILEGIVEL,
  ]);
  const pendenciasOutras = pendencias.filter((p) => !TIPOS_COM_SECAO_PROPRIA.has(p.tipo));

  // O ARQUIVO DE CADA PENDÊNCIA. A mensagem diz o que está errado; sem o nome do
  // arquivo, quem vai conferir tem de adivinhar em qual dos treze documentos olhar.
  // A versão mais recente é a que vale — é ela que a extração usou.
  // ORDEM DA TABELA: pelo NOME DO ARQUIVO, não pela hora do upload. O cliente
  // manda o book numerado (`01_Balanco`, `02_DRE`, …) e procura por esse número;
  // ordenar por `criado_em desc` embaralhava o book na tela e obrigava a varrer
  // a lista inteira para achar um documento.
  documentos.sort((a, b) => {
    const na = (a.documento_versao ?? []).at(-1)?.nome_original ?? "";
    const nb = (b.documento_versao ?? []).at(-1)?.nome_original ?? "";
    return na.localeCompare(nb, "pt-BR", { numeric: true });
  });

  const arquivoDoDocumento = new Map<string, string>();
  for (const d of documentos) {
    const nome = (d.documento_versao ?? []).map((v) => v.nome_original).filter(Boolean).at(-1);
    if (nome) arquivoDoDocumento.set(d.id, nome);
  }

  const linhasTotais = [...linhasPorVersao.values()].reduce((a, b) => a + b, 0);
  const bloqueantesAbertas = pendencias.filter(
    (p) => emAberto(p) && p.severidade === "bloqueante",
  ).length;
  const abertas = pendencias.filter(emAberto).length;
  const kitPresentes = kitBasico.filter(
    (i) => kitAtendidos.has(i.codigo) && !tiposSemConteudo.has(i.codigo),
  ).length;
  // Documento que chegou, foi classificado e não rendeu UMA linha. É o que o
  // `fn_conferir_lote` mede do lado do banco; aqui ele vira número de topo,
  // porque é a pergunta que a rodada v45 respondeu tarde demais.
  const semLinha = documentos.filter(
    (d) => ((d.documento_versao ?? []).reduce((n, v) => n + (linhasPorVersao.get(v.id) ?? 0), 0)) === 0,
  ).length;
  // Contagem parcial não é contagem (regra 1): com a leitura incompleta, a soma
  // parcial NÃO aparece como total (o valor vira "—") e "sem nenhuma linha" não é
  // dito — contaria documento cujas linhas estavam nas páginas que não vieram.
  // A célula "linhas" de cada documento na tabela. Com a contagem incompleta, nem
  // o número nem o "nenhuma" são verdade: as linhas podem estar nas páginas que
  // não vieram.
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
  let detalheDasLinhas: string | null = null;
  if (linhasIncompletas) detalheDasLinhas = "contagem incompleta — a leitura das linhas não terminou";
  else if (semLinha > 0) detalheDasLinhas = `${semLinha} ${semLinha === 1 ? "documento sem nenhuma linha" : "documentos sem nenhuma linha"}`;

  return (
    <div className="space-y-8">
      {/* O CABEÇALHO, o status e as demais navegações (adicionar arquivos,
          perguntas, grupo econômico, excluir) moraram aqui até virarem o layout
          do mandato (`layout.tsx`). Ficam só estas duas ações, até a aba
          Entregáveis existir.

          UM EXPORT SÓ NESTA TELA (decisão do dono, 07/08/2026). Esta é a tela de
          CONFERIR O QUE CHEGOU, e o único arquivo que faz sentido aqui é o dos
          dados — ele existe desde a ingestão, mesmo com pendência aberta. O
          export de modelagem mora na tela de Modelagem, junto das premissas que
          ele usa: oferecê-lo aqui convidava a exportar o modelo antes de dizer
          como cada conta projeta. */}
      <div className="flex flex-wrap items-center justify-end gap-2">
        <a
          href={`/casos/${id}/export?modo=dados`}
          className="btn-secundario"
          title="Todas as abas de dado, linha a linha, sem modelagem. Serve para conferir a extração contra os documentos."
        >
          Exportar dados
        </a>
        {/* A ÚNICA AÇÃO PRIMÁRIA DA TELA: a tela não dizia para onde ir depois
            de conferir o que chegou. */}
        <Link href={`/casos/${id}/modelagem`} className="btn-primario">
          Ir para a modelagem
        </Link>
      </div>

      {/* O RESUMO QUE A TELA NÃO DAVA. Quem abre um mandato pergunta uma coisa:
          "posso confiar neste caso?". A resposta exigia rolar seis seções e
          somar de cabeça. Os quatro números abaixo respondem em um olhar, e o
          terceiro — documentos sem uma linha extraída — é o que a rodada de
          15/08 descobriu tarde: documento classificado, checklist verde, e nada
          no banco. */}
      <div className="carta grid grid-cols-2 divide-x divide-y divide-tinta-100 sm:grid-cols-4 sm:divide-y-0">
        <Indicador valor={documentos.length} rotulo="documentos recebidos" />
        <Indicador
          valor={linhasIncompletas ? "—" : linhasTotais.toLocaleString("pt-BR")}
          rotulo="linhas financeiras extraídas"
          detalhe={detalheDasLinhas}
          tom="alerta"
        />
        <Indicador
          valor={`${kitPresentes}/${kitBasico.length}`}
          rotulo="itens do Kit Básico"
          detalhe={kitPresentes === kitBasico.length ? "kit completo" : null}
          tom="bom"
        />
        <Indicador
          valor={abertas}
          rotulo={abertas === 1 ? "pendência em aberto" : "pendências em aberto"}
          detalhe={bloqueantesAbertas > 0
            ? `${bloqueantesAbertas} ${bloqueantesAbertas === 1 ? "bloqueia" : "bloqueiam"} a aprovação`
            : null}
          tom="alerta"
        />
      </div>

      {pendenciasRevisao.filter(emAberto).length > 0 && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-alerta-200 bg-alerta-50 px-4 py-3 text-sm">
          <span className="text-alerta-900">
            <strong className="font-semibold">
              {pendenciasRevisao.filter(emAberto).length}{" "}
              {pendenciasRevisao.filter(emAberto).length === 1 ? "documento" : "documentos"}
            </strong>{" "}
            com dúvida de classificação, entidade ou período — o sistema quer sua confirmação.
          </span>
          <Link
            href={`/casos/${id}/revisao`}
            className="rounded-md bg-alerta-800 px-3 py-1.5 text-xs font-semibold text-papel hover:bg-alerta-900"
          >
            Revisar agora
          </Link>
        </div>
      )}

      {/* PORTÃO 2 (Supabase/migrations/0037) — a regra de Arquitetura do Sistema/2 Especificação/f0/04, visível.
          Antes desta tela não havia como saber se um caso podia ser aprovado:
          a regra não existia em código, e "não implementado" tem a mesma
          aparência de "sem pendência bloqueante" para quem olha o dashboard. */}
      {portao2 && (
        <div
          className={`rounded-lg border p-4 text-sm ${
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
      )}

      <section>
        <div className="mb-2 flex items-baseline justify-between gap-3">
          <h2 className="titulo-secao">Kit Básico</h2>
          <p className="text-xs text-tinta-500">
            os {kitBasico.length} documentos obrigatórios do mandato
          </p>
        </div>
        <ul className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          {kitBasico.map((item) => {
            const semConteudo = tiposSemConteudo.has(item.codigo);
            // TRÊS estados, não dois (0036): verde só quando chegou E rendeu
            // linha. O documento que chegou vazio fica âmbar — não verde, porque
            // o book sai vazio nessa parte, e não "faltante", porque o arquivo
            // está lá e pedi-lo de novo ao cliente seria pedir o que ele mandou.
            const presente = kitAtendidos.has(item.codigo) && !semConteudo;
            const cor = presente
              ? "border-ok-200 bg-ok-50/60"
              : semConteudo
                ? "border-alerta-200 bg-alerta-50"
                : "border-tinta-200 bg-folha";
            const corTexto = presente
              ? "text-ok-700"
              : semConteudo
                ? "text-alerta-800"
                : "text-tinta-400";
            return (
              <li
                key={item.codigo}
                className={`flex items-center justify-between gap-3 rounded-lg border px-3 py-2.5 text-sm ${cor}`}
              >
                <span className="text-tinta-800">{item.documento}</span>
                <span className={`shrink-0 text-xs font-medium ${corTexto}`}>
                  {presente
                    ? "✓ recebido"
                    : semConteudo
                      ? "chegou, sem dado extraído"
                      : "não recebido"}
                </span>
              </li>
            );
          })}
        </ul>
      </section>

      <section>
        <div className="mb-2 flex items-baseline justify-between gap-3">
          <h2 className="titulo-secao">Documentos</h2>
          <p className="text-xs text-tinta-500">
            {documentos.length} {documentos.length === 1 ? "arquivo recebido" : "arquivos recebidos"}
          </p>
        </div>
        {documentos.length === 0 ? (
          <div className="carta px-6 py-10 text-center text-sm text-tinta-500">
            Nenhum documento recebido ainda.
          </div>
        ) : (
          <div className="carta overflow-x-auto">
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
                {documentos.map((doc) => {
                  const versao = doc.documento_versao?.[0];
                  const legibilidadeRuim = versao?.legibilidade && versao.legibilidade !== "ok";
                  const linhas = (doc.documento_versao ?? []).reduce(
                    (n, v) => n + (linhasPorVersao.get(v.id) ?? 0), 0,
                  );
                  return (
                    <tr key={doc.id} className="align-top transition-colors hover:bg-tinta-50">
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
                          <p className="mt-0.5 max-w-[15rem] truncate text-xs text-tinta-500" title={doc.resumo}>
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
                          href={`/casos/${id}/documentos/${doc.id}`}
                          className="font-medium text-acento-600 hover:text-acento-700 hover:underline"
                        >
                          abrir
                        </Link>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

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

      {pendenciasOutras.length > 0 && (
        <section>
          <div className="mb-2 flex items-baseline justify-between gap-3">
            <h2 className="titulo-secao">O que falta chegar</h2>
            <p className="text-xs text-tinta-500">{pendenciasOutras.length} em aberto</p>
          </div>
          <p className="mb-2.5 text-xs text-tinta-500">
            Documento obrigatório ausente, ou que chegou sem nenhuma linha aproveitável. A grade do
            Kit Básico mostra o mesmo fato; aqui cada item pode ser decidido.
          </p>
          <ul className="space-y-2">
            {[...pendenciasOutras].sort(porDecidirPrimeiro).map((p) => (
              <ItemPendencia
                key={p.id} p={p} tom={p.severidade === "bloqueante" ? "red" : "amber"} casoId={id}
                arquivo={p.documento_id ? arquivoDoDocumento.get(p.documento_id) ?? null : null}
              />
            ))}
          </ul>
        </section>
      )}

      <section>
        <div className="mb-2 flex items-baseline justify-between gap-3">
          {/* "Classe A/B" é vocabulário interno (Arquitetura do Sistema/2 Especificação/f0/04): A é o que se confere
              dentro do próprio documento, B é entre documentos. Para quem lê a
              tela o que importa é que são números que não fecham. */}
          <h2 className="titulo-secao">Números que não fecham</h2>
          <p className="text-xs text-tinta-500">
            {pendenciasReconciliacao.length === 0
              ? "conferências automáticas entre documentos"
              : `${pendenciasReconciliacao.length} divergência(s)`}
          </p>
        </div>
        {pendenciasReconciliacao.length === 0 ? (
          <div className="carta px-4 py-6 text-sm text-tinta-500">
            Nenhuma divergência encontrada — o balanço fecha, o caixa bate com o fluxo e não há
            conta contada duas vezes.
          </div>
        ) : (
          <ul className="space-y-2">
            {[...pendenciasReconciliacao].sort(porDecidirPrimeiro).map((p) => (
              <ItemPendencia
                key={p.id} p={p} tom="amber" casoId={id}
                arquivo={p.documento_id ? arquivoDoDocumento.get(p.documento_id) ?? null : null}
              />
            ))}
          </ul>
        )}
      </section>

      {pendenciasArquivo.length > 0 && (
        <section>
          <div className="mb-2 flex items-baseline justify-between gap-3">
            <h2 className="titulo-secao">Arquivos ilegíveis</h2>
            <p className="text-xs text-tinta-500">{pendenciasArquivo.length} arquivo(s)</p>
          </div>
          <ul className="space-y-2">
            {[...pendenciasArquivo].sort(porDecidirPrimeiro).map((p) => (
              <ItemPendencia
                key={p.id} p={p} tom="red" casoId={id}
                arquivo={p.documento_id ? arquivoDoDocumento.get(p.documento_id) ?? null : null}
              />
            ))}
          </ul>
        </section>
      )}

      {pendenciasExtracao.length > 0 && (
        <section>
          <div className="mb-2 flex items-baseline justify-between gap-3">
            <h2 className="titulo-secao">Extração incompleta</h2>
            <p className="text-xs text-tinta-500">{pendenciasExtracao.length} documento(s)</p>
          </div>
          <ul className="space-y-2">
            {[...pendenciasExtracao].sort(porDecidirPrimeiro).map((p) => (
              <ItemPendencia
                key={p.id} p={p} tom="red" casoId={id}
                arquivo={p.documento_id ? arquivoDoDocumento.get(p.documento_id) ?? null : null}
              />
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}
