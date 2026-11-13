import Link from "next/link";
import { EquipeDoMandato } from "@/components/equipe-do-mandato";
import { FormDeAcao } from "@/components/form-de-acao";
import { lerPermissoesDoMandato } from "@/lib/supabase/acesso";
import { ehPdf, hrefDoOriginal, rotuloDoLink } from "@/lib/original-do-documento";
import { suavizarMensagem } from "@/lib/rotulos";
import type { FatoDoCaso } from "@/lib/types";
import { aprovarCaso } from "./actions";
import { FatosNaoLidos } from "@/components/fatos-nao-lidos";
import { LegendaDeOrigem, SeloDeOrigem } from "@/components/selo-de-origem";
import { formatarTipoTaxonomia } from "@/lib/export";
import { casoDaTela, lerFatosDoCaso, lerIndicadores, lerPortao2, type Portao2 } from "./visao-dados";

// OS BLOCOS DA VISÃO GERAL DO MANDATO, cada um com a sua consulta e o seu `<Suspense>`
// (`components/revelar.tsx`; as leituras compartilhadas, em `visao-dados.ts`).
//
// MEDIDO antes (next start, mandato de 115 documentos): casco e cabeçalho já saíam em ~0,3 s (o layout
// do mandato é rápido), mas a página só devolvia JSX depois de todas as leituras — ~1,0 s a 1,5 s de
// "Carregando…" genérico, e o conteúdo inteiro de uma vez. Agora o "Próximo passo", os indicadores, o
// Portão 2, os fatos e a equipe chegam cada um com a sua consulta.
//
// REGRA 1 / 7: o mesmo tratamento de falha de antes, movido sem mudar. Contagem que falha sai como
// traço com a causa, nunca zero; o Portão 2 que não respondeu diz "Aprovação não conferida".

const COR_DO_DETALHE = { alerta: "text-risco-700", bom: "text-ok-700", neutro: "text-tinta-500" } as const;

// Um indicador do topo. Número grande, rótulo embaixo, e um detalhe opcional em
// cor quando ele muda a leitura do número (ex.: "2 bloqueantes"). Cada um leva à aba
// onde o número se explica (fase 2): um número sem para onde ir é só decoração.
function Indicador({
  valor, rotulo, detalhe, tom, href, origem,
}: Readonly<{
  valor: React.ReactNode;
  rotulo: string;
  detalhe?: string | null;
  tom?: "neutro" | "alerta" | "bom";
  href: string;
  /** de onde o número vem (lib/origem-do-numero.ts); só onde a origem muda a leitura */
  origem?: "lido" | "calculado";
}>) {
  const corDetalhe = COR_DO_DETALHE[tom ?? "neutro"];
  return (
    <Link href={href} className="carta block px-[18px] py-4 transition-colors hover:bg-tinta-50">
      <p className="indicador-valor">{valor}</p>
      <p className="indicador-rotulo">{rotulo}</p>
      {origem && <p className="mt-0.5"><SeloDeOrigem origem={origem} /></p>}
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

function FatoMaterial({ f, casoId }: Readonly<{ f: FatoDoCaso; casoId: string }>) {
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
      <blockquote className="valor-sensivel border-l-2 border-tinta-300 pl-3 text-sm italic text-tinta-800">
        “{f.trecho}”
      </blockquote>
      {f.leitura && <p className="valor-sensivel mt-1.5 text-sm text-tinta-700">{f.leitura}</p>}
      <p className="mt-1.5 text-xs text-tinta-500">{f.porque}</p>
      <p className="mt-1.5 text-xs">
        <a
          href={hrefDoOriginal(casoId, f.documento_id, f.pagina, f.documento_versao_id)}
          target="_blank"
          rel="noopener"
          title={rotuloDoLink(ehPdf(f.nome_documento, null), f.pagina)}
          className="font-medium text-tinta-700 underline decoration-tinta-300 hover:text-tinta-900"
        >
          Ver no original ↗
        </a>
      </p>
    </li>
  );
}

export async function ProximoPassoDoMandato({ id }: Readonly<{ id: string }>) {
  const { passo } = await lerIndicadores(id);
  const base = `/casos/${id}`;
  return (
    <>
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
    </>
  );
}

export async function IndicadoresDoMandato({ id }: Readonly<{ id: string }>) {
  const {
    documentos, documentosLidos, linhasTotais, linhasConhecidas, semLinha, kitLido, kitPresentes, kitTotal,
    nAbertas, detalheDasLinhas, detalheDoKit, detalheDasPendencias,
  } = await lerIndicadores(id);
  const base = `/casos/${id}`;
  return (
    <>
      {/* O RESUMO. Quem abre um mandato pergunta uma coisa: "posso confiar neste caso?". Os
          quatro números respondem em um olhar, e o terceiro — documentos sem uma linha extraída —
          é o que a rodada de 15/08 descobriu tarde: documento classificado, checklist verde, e
          nada no banco. Cada um leva à aba onde se explica. */}
      <div className="space-y-2">
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <Indicador
          valor={documentosLidos ? documentos.length : "—"}
          rotulo="documentos recebidos"
          detalhe={documentosLidos ? null : "a leitura dos documentos falhou"}
          tom="alerta"
          href={`${base}/documentos`}
        />
        <Indicador
          valor={linhasConhecidas ? <span className="valor-sensivel">{linhasTotais.toLocaleString("pt-BR")}</span> : "—"}
          rotulo="linhas financeiras extraídas"
          origem="lido"
          detalhe={detalheDasLinhas}
          tom="alerta"
          href={linhasConhecidas && semLinha > 0 ? `${base}/documentos?filtro=sem-linha` : `${base}/documentos`}
        />
        <Indicador
          valor={kitLido ? `${kitPresentes}/${kitTotal}` : "—"}
          rotulo="itens do Kit Básico"
          origem="calculado"
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
      <LegendaDeOrigem />
      </div>
    </>
  );
}

// O KIT BÁSICO COM PRONTIDÃO (item 4 do benchmark). O percentual é só do que tem CONTEÚDO LIDO: o item
// que chegou como arquivo e não rendeu nenhuma linha é "recebido", não "pronto" — copiar o "sobe a cada
// upload" da Ansarada violaria a regra 1 (o benchmark, §5.2, diz o mesmo). "Conferido por pessoa" tem o
// lugar dele na lista e diz que não foi medido: o estado nasce em `fn_kit_do_caso` (migration 0300).
// NÃO há "por que este item importa": `taxonomia_tipo_documento` não tem coluna de descrição, e texto
// inventado aqui seria afirmação sem origem.
export async function KitBasicoDoMandato({ id }: Readonly<{ id: string }>) {
  const { kitLido, kitPresentes, kitRecebidos, kitTotal } = await lerIndicadores(id);
  const base = `/casos/${id}/documentos`;
  if (!kitLido || kitTotal === 0) {
    return (
      <section aria-label="Kit Básico" className="carta border-alerta-200 bg-alerta-50 px-[18px] py-4 text-sm text-alerta-900">
        <h2 className="titulo-secao">Kit Básico</h2>
        <p className="mt-1 text-xs">
          {kitLido
            ? "Nenhum item obrigatório cadastrado na taxonomia: não há como medir a prontidão."
            : "Não foi possível ler o Kit Básico agora, então não dá para dizer o que falta nem o quanto está pronto."}
        </p>
      </section>
    );
  }
  const semConteudo = kitRecebidos - kitPresentes;
  const faltantes = kitTotal - kitRecebidos;
  const pct = Math.round((kitPresentes / kitTotal) * 100);
  const parte = (n: number) => `${(n / kitTotal) * 100}%`;
  return (
    <section aria-label="Kit Básico" className="carta px-[18px] py-4">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="titulo-secao">Kit Básico</h2>
        <SeloDeOrigem origem="calculado" />
      </div>
      <div className="mt-3 flex items-baseline gap-3">
        <p className="indicador-valor">{pct}%</p>
        <p className="text-xs text-tinta-500">de {kitTotal} itens com conteúdo lido (recebido não conta)</p>
      </div>
      <div role="img" aria-label={`${kitPresentes} com conteúdo, ${semConteudo} recebidos sem conteúdo, ${faltantes} faltantes`} className="mt-2 flex h-2 overflow-hidden rounded-full bg-tinta-100">
        <span className="bg-ok-500" style={{ width: parte(kitPresentes) }} />
        <span className="bg-alerta-500" style={{ width: parte(semConteudo) }} />
      </div>
      <ul className="mt-3 grid gap-x-6 gap-y-1.5 text-xs text-tinta-700 sm:grid-cols-2">
        <li className="flex items-center gap-2"><span aria-hidden className="h-2 w-2 rounded-full bg-ok-500" /><span className="num">{kitPresentes}</span> com conteúdo lido</li>
        <li className="flex items-center gap-2"><span aria-hidden className="h-2 w-2 rounded-full bg-alerta-500" /><span className="num">{semConteudo}</span> recebidos sem conteúdo lido</li>
        <li className="flex items-center gap-2"><span aria-hidden className="h-2 w-2 rounded-full bg-tinta-200" /><span className="num">{faltantes}</span> faltantes</li>
        <li className="flex items-center gap-2 text-tinta-500"><span aria-hidden className="h-2 w-2 rounded-full border border-tinta-400" />Conferido por pessoa: ainda não medido</li>
      </ul>
      {(semConteudo > 0 || faltantes > 0) && (
        <p className="mt-3 text-xs"><Link href={base} className="font-medium text-acento-700 hover:underline">Ver os documentos →</Link></p>
      )}
    </section>
  );
}

// O ANDAMENTO DA LEITURA, por etapa e por documento (item 10 do benchmark), só com o dado que a visão
// já lê: documentos recebidos, os que renderam linha e os que não renderam NENHUMA. Estágio que não rodou
// tem a cara de estágio que rodou e não achou nada (regra 7): por isso o documento sem linha é listado
// com nome e link, e a contagem que não terminou de ler diz que não terminou, em vez de somar menos.
// "Conferido por pessoa" é a terceira etapa e não tem dado (0300): fica com o traço e o motivo.
export async function AndamentoDoMandato({ id }: Readonly<{ id: string }>) {
  const {
    documentos, documentosLidos, semLinha, linhasConhecidas, linhasIncompletas, documentosSemLinha,
  } = await lerIndicadores(id);
  if (!documentosLidos) {
    return (
      <section aria-label="Andamento da leitura" className="carta border-risco-200 bg-risco-50 px-[18px] py-4 text-sm text-risco-900">
        <h2 className="titulo-secao">Andamento da leitura</h2>
        <p className="mt-1 text-xs">A leitura dos documentos falhou: não dá para dizer o que já foi lido. Recarregue a página.</p>
      </section>
    );
  }
  if (documentos.length === 0) return null;
  const lidos = documentos.length - semLinha;
  const etapa = (rotulo: string, valor: React.ReactNode, nota?: string) => (
    <li className="min-w-0 flex-1">
      <p className="num text-xl font-medium text-tinta-900">{valor}</p>
      <p className="text-xs text-tinta-500">{rotulo}</p>
      {nota && <p className="mt-0.5 text-[11px] text-tinta-500">{nota}</p>}
    </li>
  );
  return (
    <section aria-label="Andamento da leitura" className="carta px-[18px] py-4">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="titulo-secao">Andamento da leitura</h2>
        <SeloDeOrigem origem="lido" />
      </div>
      <ol className="mt-3 flex gap-4">
        {etapa("recebidos", documentos.length)}
        {etapa("com linha extraída", linhasConhecidas ? lidos : "—", linhasConhecidas ? undefined : "contagem incompleta")}
        {etapa("conferidos por pessoa", "—", "ainda não medido")}
      </ol>
      {linhasIncompletas && (
        <p role="status" className="mt-3 rounded-lg border border-alerta-200 bg-alerta-50 px-3 py-2 text-xs text-alerta-900">
          A contagem de linhas não terminou: o que aparece como lido pode ser menos que o real. Recarregue a página.
        </p>
      )}
      {linhasConhecidas && semLinha > 0 && (
        <div role="status" className="mt-3 rounded-lg border border-alerta-200 bg-alerta-50 px-3 py-2 text-xs text-alerta-900">
          <p className="font-medium">
            {semLinha} {semLinha === 1 ? "documento não rendeu nenhuma linha" : "documentos não renderam nenhuma linha"}:
            a leitura pode ter falhado, ou o arquivo não tem tabela. Abra para conferir.
          </p>
          <ul className="mt-1.5 space-y-0.5">
            {documentosSemLinha.slice(0, 5).map((d) => (
              <li key={d.id}>
                <Link href={`/casos/${id}/documentos/${d.id}`} className="font-medium underline">
                  {formatarTipoTaxonomia(d.tipo)}
                </Link>
              </li>
            ))}
          </ul>
          {semLinha > 5 && (
            <p className="mt-1.5">
              e mais {semLinha - 5} — <Link href={`/casos/${id}/documentos?filtro=sem-linha`} className="font-medium underline">ver todos</Link>
            </p>
          )}
        </div>
      )}
    </section>
  );
}

function frasesDasRessalvas(n: number): string {
  if (n === 0) return "Nenhuma pendência foi aceita sem resolução neste caso.";
  const quantas = n === 1 ? "pendência seguiu sem resolução" : "pendências seguiram sem resolução";
  return `${n} ${quantas} — o caso avança com elas registradas, não resolvidas.`;
}

function Rejeitadas({ n, naoSobrepujaveis }: Readonly<{ n: number; naoSobrepujaveis: number }>) {
  const quantas = n === 1 ? "1 pendência foi declarada improcedente" : `${n} pendências foram declaradas improcedentes`;
  const quais = naoSobrepujaveis === 1
    ? "sendo 1 daquelas que nenhuma ressalva libera"
    : `sendo ${naoSobrepujaveis} daquelas que nenhuma ressalva libera`;
  return (
    <p className="mt-1 text-xs text-tinta-700">
      <strong>{quantas}</strong>
      {naoSobrepujaveis > 0 && <>{", "}{quais}</>}
      . Quem decidiu e por quê está na trilha do caso, e vai junto com a aprovação.
    </p>
  );
}

export async function PortaoDoMandato({ id }: Readonly<{ id: string }>) {
  // O papel neste mandato (memoizado: o layout já o pediu).
  const [caso, portao2Res, perm] = await Promise.all([casoDaTela(id), lerPortao2(id), lerPermissoesDoMandato(id)]);
  const portao2 = portao2Res.data as Portao2 | null;
  return (
    <>
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
              <p className="mt-1.5 text-xs text-tinta-600">{frasesDasRessalvas(portao2.ressalvas_ativas)}</p>
              {/* O QUE FOI DECLARADO IMPROCEDENTE (0106). Rejeitar é a única ação
                  que libera o portão SEM TETO — inclusive a pendência que nenhuma
                  ressalva libera. Não dá para proibir (senão uma pendência
                  errada prende o caso para sempre, e o que sobra é editar a
                  tabela por fora, que é a mesma liberação sem rastro). O que dá
                  é não deixar invisível: aqui, e dentro da decisão de aprovação. */}
              {(portao2.rejeitadas ?? 0) > 0 && (
                <Rejeitadas n={portao2.rejeitadas ?? 0} naoSobrepujaveis={portao2.rejeitadas_nao_sobrepujaveis ?? 0} />
              )}
            </div>
            {portao2.elegivel && caso.status !== "aprovado" && caso.status !== "pronto_para_base" && !perm.reservadoAoSocio.pode && (
              // Aprovar é de Sócio (gatilho da 0216). O motivo toma o lugar do botão, à vista.
              <p className="max-w-xs text-xs text-tinta-600">{perm.reservadoAoSocio.motivo}</p>
            )}
            {portao2.elegivel && caso.status !== "aprovado" && caso.status !== "pronto_para_base" && perm.reservadoAoSocio.pode && (
              <FormDeAcao action={aprovarCaso.bind(null, id)} className="flex flex-wrap items-center gap-2">
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
              </FormDeAcao>
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
    </>
  );
}

export async function FatosDoMandato({ id }: Readonly<{ id: string }>) {
  // Banco sem a 0148 (função ausente) sai sem o bloco, em vez de quebrar. Qualquer OUTRO erro aparece:
  // sumir teria a mesma cara de "o documento não diz nada" (regra 7).
  const { fatos, falhou }: { fatos: FatoDoCaso[]; falhou: boolean } = await lerFatosDoCaso(id);
  if (falhou) return <FatosNaoLidos />;
  const fatosCriticos = fatos.filter((f) => f.severidade === "critico").length;
  return (
    <>
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
            {fatos.map((f) => <FatoMaterial key={f.fato_id} f={f} casoId={id} />)}
          </ul>
        </section>
      )}
    </>
  );
}

export async function EquipeDoMandatoComPapel({ id }: Readonly<{ id: string }>) {
  const perm = await lerPermissoesDoMandato(id);
  return <EquipeDoMandato casoId={id} permissoes={perm} />;
}
