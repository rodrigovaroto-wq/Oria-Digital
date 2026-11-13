import Link from "next/link";
import { DetalhesTecnicos } from "@/components/detalhes-tecnicos";
import { Bloco } from "@/components/esqueleto";
import { Revelar } from "@/components/revelar";
import { lerPermissoes } from "@/lib/supabase/acesso";
import { escopoDaLista, textoDeNenhumMandato } from "@/lib/acesso";
import { CASO_STATUS_LABEL, CASO_STATUS_COLOR } from "@/lib/status";
import { categoriaDaPendencia } from "@/lib/pendencia";
import { ETAPAS_DO_MANDATO, etapaDoMandato } from "@/lib/etapa-do-mandato";
import { FILTROS_DA_FILA, contarFila, daFila, verboDaPendencia, type FiltroDaFila } from "@/lib/painel";
import { rotuloDaPendencia, nomeDaChecagem, partesDaDescricao, suavizarMensagem } from "@/lib/rotulos";
import { formatarTipoTaxonomia } from "@/lib/export";
import {
  lerCarteira, lerDocumentos, lerRecentes, lerTrava, lerUso,
  type DocumentoNoPainel, type UsoDoLote,
} from "./painel-dados";

// OS BLOCOS DO PAINEL, cada um com a sua consulta e o seu `<Suspense>` (ver `components/revelar.tsx`).
//
// O PROBLEMA QUE ISTO RESOLVE. Com `loading.tsx` e tudo dentro de UMA página, a tela mostrava o casco
// e uma grade cinza genérica por 3 s: a página só devolvia JSX depois de ler tudo, inclusive a
// saudação, que não depende de dado nenhum. Medido (next start, mandato do dono): TTFB ~0,2 s, DOM
// pronto em 2,8 a 3,2 s, e o primeiro texto da página (o título) só nesse instante. Agora o título, a
// saudação e a data saem no primeiro HTML; cada bloco abaixo chega quando a SUA consulta responde.
//
// REGRA 1 / 7 PRESERVADAS. O esqueleto é "carregando" e nunca valor. A leitura que falha continua
// sendo dita pelo bloco que a usa (traço com a causa, cartão de erro, faixa de aviso) — a MESMA
// lógica de antes, só movida. Um erro lançado aqui cai no `error.tsx` do segmento, como antes.

/** A fila mostra 20; "ver todas" sobe a 100. Acima disso o texto manda abrir o mandato. */
const FILA_VISIVEL = 20;
const FILA_VISIVEL_AMPLA = 100;
/** "Seus mandatos": os travados entram TODOS; os demais completam até este total. */
const MANDATOS_VISIVEIS = 6;

// A fila é ordenada por consequência, não por data: bloqueante impede a
// aprovação do mandato, complementar não impede nada.
const PESO_SEVERIDADE: Record<string, number> = {
  bloqueante: 0,
  importante: 1,
  complementar: 2,
};

const TOM_SEVERIDADE: Record<string, { ponto: string; chip: string; rotulo: string }> = {
  bloqueante: { ponto: "bg-risco-500", chip: "bg-risco-100 text-risco-800", rotulo: "bloqueia a aprovação" },
  importante: { ponto: "bg-alerta-500", chip: "bg-alerta-100 text-alerta-900", rotulo: "importante" },
  complementar: { ponto: "bg-tinta-400", chip: "bg-tinta-100 text-tinta-600", rotulo: "complementar" },
};

const FUSO = "America/Sao_Paulo";

/** Saudação no fuso de quem usa, não no do servidor (o portal roda em UTC). */
export function saudacao(agora: Date): string {
  const hora = Number(
    new Intl.DateTimeFormat("pt-BR", { hour: "2-digit", hour12: false, timeZone: FUSO }).format(agora),
  );
  if (hora < 12) return "Bom dia";
  if (hora < 18) return "Boa tarde";
  return "Boa noite";
}

function horaCurta(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return d.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit", timeZone: FUSO });
}

/** "Hoje", "Ontem" ou a data: o cabeçalho de cada bloco da linha do tempo. */
function diaRelativo(iso: string, agora: Date): string {
  const dia = (d: Date) =>
    new Intl.DateTimeFormat("en-CA", { year: "numeric", month: "2-digit", day: "2-digit", timeZone: FUSO }).format(d);
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  const ontem = new Date(agora.getTime() - 86_400_000);
  if (dia(d) === dia(agora)) return "Hoje";
  if (dia(d) === dia(ontem)) return "Ontem";
  return d.toLocaleDateString("pt-BR", { day: "2-digit", month: "short", timeZone: FUSO });
}

/** Duração em palavras curtas: "8 min", "1 h 12", "2 d". */
function duracaoCurta(ms: number): string {
  const min = Math.round(ms / 60_000);
  if (min < 1) return "menos de 1 min";
  if (min < 90) return `${min} min`;
  const h = Math.floor(min / 60);
  if (h < 36) return `${h} h ${String(min % 60).padStart(2, "0")}`;
  return `${Math.round(h / 24)} d`;
}

/**
 * A descrição de pendência em UMA linha. As mensagens vêm do banco com vários
 * fatos emendados por `;`; esta fila é de triagem, então só o primeiro entra.
 */
function resumoDaPendencia(descricao: string | null): string {
  if (!descricao) return "";
  const [primeira] = partesDaDescricao(suavizarMensagem(descricao));
  return (primeira ?? "").trim();
}

/**
 * Um número do topo. `valor` é string de propósito: metade destes indicadores
 * é dinheiro ou duração, e formatar aqui dentro obrigaria o componente a saber
 * de moeda e de fuso. Nulo vira traço, que é informação e não buraco.
 */
function Indicador({
  valor, rotulo, detalhe, tom, nota, barra,
}: {
  valor: string | null;
  rotulo: string;
  detalhe?: string | null;
  tom?: "neutro" | "alerta" | "bom";
  /** por que não há número; só aparece quando `valor` é nulo */
  nota?: string;
  /** 0..1, desenha a fração embaixo do número. Só onde a fração É o número. */
  barra?: number | null;
}) {
  const corDetalhe =
    tom === "alerta" ? "text-risco-700" : tom === "bom" ? "text-ok-700" : "text-tinta-500";
  return (
    <div className="bg-folha px-4 py-4">
      {valor === null ? (
        <p className="text-2xl font-semibold text-tinta-300" title={nota}>
          —
        </p>
      ) : (
        <p className="indicador-valor valor-sensivel">{valor}</p>
      )}
      <p className="indicador-rotulo">{rotulo}</p>
      {/* A barra só existe onde a fração É o número, hoje a cobertura. Ao lado
          de um total ela sugeriria um limite que não existe. */}
      {typeof barra === "number" && (
        <div className="mt-2 h-1 w-full overflow-hidden rounded-full bg-tinta-100">
          <div
            className={`h-full rounded-full ${barra >= 0.9 ? "bg-ok-600" : barra >= 0.6 ? "bg-alerta-500" : "bg-risco-500"}`}
            style={{ width: `${Math.min(100, Math.max(2, barra * 100))}%` }}
          />
        </div>
      )}
      {/* A nota de ausência NÃO é borrada: ela é o motivo do traço (regra 1), e não carrega número do cliente. */}
      <p className={`mt-1 min-h-4 text-xs font-medium ${valor === null ? "text-tinta-400" : `valor-sensivel ${corDetalhe}`}`}>
        {valor === null ? (nota ?? "") : (detalhe ?? "")}
      </p>
    </div>
  );
}

// Contagem com separador de milhar. Mora logo abaixo do `Indicador` de propósito: o número e o detalhe
// dele ("em 3 mandatos", "2.088 em aberto") saem com `.valor-sensivel`, e a varredura de
// `verificar-mensagem-de-falha.mts` exige a classe a 600 caracteres de cada `toLocaleString("pt-BR")`.
const numero = (n: number) => n.toLocaleString("pt-BR");

export async function ResumoDoPainel() {
  // O papel já foi lido pelo layout (`lerPermissoes` é memoizado): aqui não vai ao banco de novo.
  const perm = await lerPermissoes();
  const soAlocados = escopoDaLista(perm.papel) === "alocados";
  const [{ ativos }, { pendenciasLidas, nBloqueantes: bloqueantes, casosTravados }] = await Promise.all([lerCarteira(), lerTrava()]);
  // A frase de abertura dá o veredito para quem não vai ler número nenhum.
  const resumo =
    ativos.length === 0
      ? `${textoDeNenhumMandato(perm.papel, "em andamento")}.`
      : !pendenciasLidas
        ? `${ativos.length} ${ativos.length === 1 ? "mandato em andamento" : "mandatos em andamento"}. ` +
          "Não foi possível conferir as pendências agora; não dá para dizer o que trava a aprovação."
        : bloqueantes === 0
        ? `${ativos.length} ${ativos.length === 1 ? "mandato em andamento" : "mandatos em andamento"}. Nada trava a aprovação.`
        : `${bloqueantes} ${bloqueantes === 1 ? "pendência trava" : "pendências travam"} ` +
          `${casosTravados === 1 ? "1 mandato" : `${casosTravados} mandatos`}.`;
  return (
    <>
      <p className="mt-0.5 text-sm text-tinta-500">{resumo}</p>
      {soAlocados && (
        <p className="mt-0.5 text-xs text-tinta-500">
          Os números abaixo são dos mandatos em que você está alocado.
        </p>
      )}
    </>
  );
}

export async function IndicadoresDoPainel() {
  const [{ ativos, casos }, trava, documentosRes, usoRes] = await Promise.all([
    lerCarteira(), lerTrava(), lerDocumentos(), lerUso(),
  ]);
  const { pendencias, pendenciasLidas, nBloqueantes: bloqueantes, casosTravados } = trava;
  const documentos = documentosRes.data;
  const documentosLidos = !documentosRes.error;

  // Tempo médio: do envio do lote ao último documento registrado, que é a
  // duração real da ingestão. Acrescentar documentos depois dispara uma segunda
  // execução e o intervalo passa a incluir a espera pelo cliente; por isso a
  // média só considera janelas de até 12 horas, e as demais são contadas à parte
  // em vez de inflarem o número em silêncio.
  const TETO_JANELA_MS = 12 * 3_600_000;
  const ultimoDocPorCaso = new Map<string, number>();
  for (const d of documentos) {
    const t = new Date(d.criado_em).getTime();
    if (Number.isNaN(t)) continue;
    ultimoDocPorCaso.set(d.caso_id, Math.max(ultimoDocPorCaso.get(d.caso_id) ?? 0, t));
  }
  const janelas: number[] = [];
  let janelasLongas = 0;
  for (const c of casos) {
    const fim = ultimoDocPorCaso.get(c.id);
    const inicio = new Date(c.criado_em).getTime();
    if (!fim || Number.isNaN(inicio) || fim <= inicio) continue;
    const dur = fim - inicio;
    if (dur > TETO_JANELA_MS) janelasLongas += 1;
    else janelas.push(dur);
  }
  const tempoMedioMs = janelas.length
    ? janelas.reduce((s, v) => s + v, 0) / janelas.length
    : null;

  // A cobertura é a razão de duas somas, não a média das razões: um lote de 400
  // linhas com 90% e um de 4 com 25% dão 89,4%, não 57,5%.
  const usoErro = Boolean((usoRes as { error?: unknown }).error);
  const usos = (usoRes.data as UsoDoLote[] | null) ?? [];
  let contasNosDocs = 0;
  let contasExtraidas = 0;
  for (const u of usos) {
    if (!u.contas_nos_documentos) continue;
    contasNosDocs += u.contas_nos_documentos;
    contasExtraidas += u.contas_extraidas ?? 0;
  }
  const cobertura: number | null = usoErro || contasNosDocs === 0 ? null : contasExtraidas / contasNosDocs;
  const semMedicao = usoErro
    ? "medição indisponível agora"
    : "nenhum documento processado ainda";

  return (
    <div className="carta overflow-hidden">
        <div className="grid grid-cols-2 gap-px bg-tinta-100 sm:grid-cols-4">
          <Indicador
            valor={numero(ativos.length)}
            rotulo={ativos.length === 1 ? "mandato em andamento" : "mandatos em andamento"}
            detalhe={
              !pendenciasLidas
                ? "travados: não conferido agora"
                : casosTravados > 0
                  ? `${casosTravados} travado${casosTravados === 1 ? "" : "s"}`
                  : null
            }
            tom="alerta"
          />
          {/* Falha de leitura NÃO vira zero: sem a lista, traço com a causa. */}
          <Indicador
            valor={pendenciasLidas ? numero(bloqueantes) : null}
            rotulo={bloqueantes === 1 ? "pendência que trava a aprovação" : "pendências que travam a aprovação"}
            detalhe={
              bloqueantes > 0
                ? `em ${casosTravados} ${casosTravados === 1 ? "mandato" : "mandatos"}`
                : pendencias.length > 0
                  ? `${numero(pendencias.length)} em aberto, nenhuma trava`
                  : "nada em aberto"
            }
            tom={bloqueantes > 0 ? "alerta" : "bom"}
            nota="leitura das pendências indisponível agora"
          />
          {/* A cobertura tem barra porque é a única fração: quanto do que estava
              escrito no documento chegou ao sistema. */}
          <Indicador
            valor={cobertura === null ? null : `${Math.round(cobertura * 100)}%`}
            rotulo="cobertura da leitura"
            barra={cobertura}
            detalhe={
              cobertura === null
                ? null
                : `${numero(contasExtraidas)} de ${numero(contasNosDocs)} linhas de conta nos documentos`
            }
            tom={cobertura !== null && cobertura < 0.6 ? "alerta" : "bom"}
            nota={semMedicao}
          />
          {/* O rótulo diz o que é: do envio do lote ao último documento registrado
              (ingestão), NÃO até a aprovação — `caso` não guarda a data de aprovação. */}
          <Indicador
            valor={tempoMedioMs === null ? null : duracaoCurta(tempoMedioMs)}
            rotulo="tempo médio de ingestão"
            detalhe={
              janelas.length
                ? `${janelas.length} ${janelas.length === 1 ? "mandato medido" : "mandatos medidos"}` +
                  (janelasLongas ? `, ${janelasLongas} fora da média` : "")
                : null
            }
            nota={
              documentosLidos
                ? "nenhum mandato com documento registrado ainda"
                : "leitura dos documentos indisponível agora"
            }
          />
        </div>
    </div>
  );
}

export async function AvisosDoPainel() {
  const [{ casosRes }, trava, documentosRes, { linhasIncompletas }] = await Promise.all([
    lerCarteira(), lerTrava(), lerDocumentos(), lerRecentes(),
  ]);
  const { pendenciasRes, pendenciasLidas } = trava;
  const documentosLidos = !documentosRes.error;
  return (
    <>
      {casosRes.error && (
        <div className="rounded-lg border border-risco-200 bg-risco-50 p-3 text-sm text-risco-800">
          <p>Não foi possível carregar o Início. Recarregue a página; se continuar, avise o administrador do sistema.</p>
          <DetalhesTecnicos>
            <p>{casosRes.error.message}</p>
          </DetalhesTecnicos>
        </div>
      )}

      {/* O corte do PostgREST é silencioso, então quando o teto bate a tela diz.
          Em operação normal este bloco nunca aparece: o teto de `paginar` é 500
          mil registros por lista (o texto dizia 50 mil desde que o teto subiu). E
          uma página que falha no meio da contagem por documento acende o mesmo
          aviso — contagem parcial não pode aparecer como contagem. */}
      {(!pendenciasLidas || !documentosLidos) && (
        <div className="rounded-lg border border-risco-200 bg-risco-50 p-3 text-sm text-risco-800">
          <p>
            {!pendenciasLidas && "A leitura das pendências falhou: a fila, o status “travado” e o veredito do topo não valem agora. "}
            {!documentosLidos && "A leitura dos documentos falhou: o tempo médio e “O que chegou” não valem agora. "}
            Recarregue a página; se continuar, avise o administrador do sistema.
          </p>
          <DetalhesTecnicos>
            {pendenciasRes.error && <p>pendências: {pendenciasRes.error.message}</p>}
            {documentosRes.error && <p>documentos: {documentosRes.error.message}</p>}
          </DetalhesTecnicos>
        </div>
      )}

      {(casosRes.truncado || documentosRes.truncado || pendenciasRes.truncado || linhasIncompletas) && (
        <div className="carta border-alerta-200 bg-alerta-50 px-4 py-3 text-xs text-alerta-900">
          Parte das leituras acima não terminou. Os números descrevem parte da carteira, não a
          carteira inteira. Recarregue a página; se continuar, avise o administrador do sistema.
          <DetalhesTecnicos>
            <p>Ou uma lista passou do teto de 500 mil registros, ou uma página falhou no meio da leitura.</p>
          </DetalhesTecnicos>
        </div>
      )}
    </>
  );
}

// ---------------------------------------------------------------------------------------------------
// ESQUELETOS. Do tamanho do bloco pronto, sem valor nenhum — só a forma. Alturas MEDIDAS na tela do
// mandato do dono (1440 px, next start): cartão de indicadores 130 px por célula; linha da fila 77 px;
// linha de "O que chegou" 53,5 px + 29,5 px do cabeçalho do dia; linha de "Seus mandatos" 71,5 px.
// A lista real é maior que o esqueleto (fila: 20 linhas; mandatos: 46 linhas travadas neste caso), e a
// diferença cai sempre ABAIXO de tudo o que já foi lido — a fila é o fim da coluna da esquerda e os
// mandatos, o da direita — então nada que alguém já leu muda de lugar. CLS medido nas duas telas
// no relatório do commit.
const ALTURA_CELULA_DO_INDICADOR = 130;
const ALTURA_LINHA_DA_FILA = 77;
const ALTURA_LINHA_RECENTE = 53.5;
const ALTURA_CABECALHO_DO_DIA = 29.5;
const ALTURA_LINHA_MANDATO = 71.5;
// ---------------------------------------------------------------------------------------------------

export function EsqueletoDosIndicadores() {
  return (
    <div className="carta overflow-hidden">
      <div className="grid grid-cols-2 gap-px bg-tinta-100 sm:grid-cols-4">
        {[0, 1, 2, 3].map((i) => (
          <div key={i} className="bg-folha px-4 py-4" style={{ minHeight: ALTURA_CELULA_DO_INDICADOR }}>
            <Bloco className="h-8 w-16" />
            <Bloco className="mt-2 h-3.5 w-32" />
            <Bloco className="mt-1 h-4 w-24" />
          </div>
        ))}
      </div>
    </div>
  );
}

export function EsqueletoDaFila() {
  return (
    <>
      <div className="mb-2 flex items-baseline justify-between gap-3">
        <h2 className="titulo-secao">Precisa de você</h2>
        <Bloco className="h-4 w-40" />
      </div>
      <div className="mb-2 flex flex-wrap gap-1.5">
        {[0, 1, 2, 3, 4].map((i) => <Bloco key={i} className="h-[22px] w-24 rounded-full" />)}
      </div>
      <ul className="carta divide-y divide-tinta-100 overflow-hidden">
        {[0, 1, 2, 3, 4, 5, 6, 7].map((i) => (
          <li key={i} className="flex items-start gap-3 px-4 py-3" style={{ minHeight: ALTURA_LINHA_DA_FILA }}>
            <Bloco className="mt-1.5 h-2 w-2 rounded-full" />
            <div className="min-w-0 flex-1 space-y-2">
              <Bloco className="h-4 w-1/2" />
              <Bloco className="h-3 w-5/6" />
            </div>
            <Bloco className="h-6 w-28" />
          </li>
        ))}
      </ul>
    </>
  );
}

export function EsqueletoDosRecentes() {
  return (
    <>
      <div className="mb-2 flex items-baseline justify-between gap-3">
        <h2 className="titulo-secao">O que chegou</h2>
        <Bloco className="h-4 w-16" />
      </div>
      <div className="carta overflow-hidden">
        <div className="border-b border-tinta-100 bg-tinta-50/60 px-4 py-1.5" style={{ height: ALTURA_CABECALHO_DO_DIA }}>
          <Bloco className="h-3 w-12" />
        </div>
        <ul className="divide-y divide-tinta-100">
          {[0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map((i) => (
            <li key={i} className="flex items-start gap-3 px-4 py-2.5" style={{ minHeight: ALTURA_LINHA_RECENTE }}>
              <Bloco className="h-3 w-9" />
              <div className="min-w-0 flex-1 space-y-1.5">
                <Bloco className="h-3 w-2/3" />
                <Bloco className="h-3 w-1/2" />
              </div>
              <Bloco className="h-3 w-12" />
            </li>
          ))}
        </ul>
      </div>
    </>
  );
}

export function EsqueletoDosMandatos() {
  return (
    <div className="mt-5">
      <div className="mb-2 flex items-baseline justify-between gap-3">
        <h2 className="titulo-secao">Seus mandatos</h2>
        <Bloco className="h-4 w-24" />
      </div>
      <ul className="carta divide-y divide-tinta-100 overflow-hidden">
        {[0, 1, 2, 3, 4, 5].map((i) => (
          <li key={i} className="px-4 py-2.5" style={{ minHeight: ALTURA_LINHA_MANDATO }}>
            <div className="flex items-center justify-between gap-3">
              <Bloco className="h-3.5 w-1/2" />
              <Bloco className="h-5 w-20 rounded-full" />
            </div>
            <Bloco className="mt-2 h-1 w-full rounded-full" />
            <Bloco className="mt-2 h-3 w-24" />
          </li>
        ))}
      </ul>
    </div>
  );
}

/** A grade inteira, enquanto nem se sabe se há mandato (a lista de mandatos ainda não chegou). */
export function EsqueletoDaGrade() {
  return (
    <div role="status" aria-live="polite" className="grid gap-5 lg:grid-cols-3">
      <span className="sr-only">Carregando o painel…</span>
      <div className="min-w-0 lg:col-span-2"><EsqueletoDaFila /></div>
      <div className="min-w-0">
        <EsqueletoDosRecentes />
        <EsqueletoDosMandatos />
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------
// O CORPO: sem mandato, a mensagem; com mandato, a grade com três blocos, cada um com a sua consulta.
// ---------------------------------------------------------------------------------------------------

export async function CorpoDoPainel({ filtro, verTudo }: Readonly<{ filtro: FiltroDaFila; verTudo: boolean }>) {
  const perm = await lerPermissoes();
  const soAlocados = escopoDaLista(perm.papel) === "alocados";
  const { ativos } = await lerCarteira();

  if (ativos.length === 0) {
    return (
      /* Sem mandato o painel não inventa conteúdo, e não repete o botão de
         criar, que mora no menu. */
        <div className="carta flex flex-col items-center gap-2 px-6 py-14 text-center">
          <p className="text-sm font-medium text-tinta-900">
            {textoDeNenhumMandato(perm.papel, "em andamento")}
          </p>
          {escopoDaLista(perm.papel) === "indefinido" && (
            <p className="max-w-md text-sm text-tinta-500">
              Não foi possível conferir o seu papel, então a lista pode estar recortada ao seu acesso: não dá
              para dizer que não há mandato em andamento. Recarregue a página.
            </p>
          )}
          {soAlocados && (
            <p className="max-w-md text-sm text-tinta-500">
              Com o papel de {perm.papel === "leitura" ? "Leitura" : "Analista"} você só vê os mandatos em que um
              Sócio alocou você; peça a alocação a um Sócio.
            </p>
          )}
          {escopoDaLista(perm.papel) !== "indefinido" && (!soAlocados || perm.criarMandato.pode) ? (
          <p className="max-w-md text-sm text-tinta-500">
            Abra um em <strong className="font-medium text-tinta-700">Novo mandato</strong>, no menu
            à esquerda. Cada documento enviado é classificado e tem suas linhas financeiras lidas.
            O que faltar ou não bater aparece aqui.
          </p>
          ) : null}
        </div>
    );
  }

  return (
    <div className="grid gap-5 lg:grid-cols-3">
      {/* `min-w-0` nas duas colunas: item de grid tem largura mínima = o conteúdo, e UMA palavra
          longa sem espaço na descrição (ex.: um nome de função do banco, vistoria P2 de 04/11)
          esticava a coluna — 643 px num celular de 390. Reproduzido com o CSS compilado: 542 px
          sem, 390 px com. */}
      <Revelar rotulo="Carregando a fila de pendências…" className="min-w-0 lg:col-span-2" esqueleto={<EsqueletoDaFila />}>
        <FilaDoPainel filtro={filtro} verTudo={verTudo} />
      </Revelar>
      <div className="min-w-0">
        <Revelar rotulo="Carregando os documentos recentes…" esqueleto={<EsqueletoDosRecentes />}>
          <RecentesDoPainel />
        </Revelar>
        <Revelar rotulo="Carregando seus mandatos…" esqueleto={<EsqueletoDosMandatos />}>
          <MandatosDoPainel />
        </Revelar>
      </div>
    </div>
  );
}

// A fila de triagem.
async function FilaDoPainel({ filtro, verTudo }: Readonly<{ filtro: FiltroDaFila; verTudo: boolean }>) {
  const [{ nomePorCaso }, { pendencias, pendenciasLidas }] = await Promise.all([lerCarteira(), lerTrava()]);
  // A fila é uma só lista: o filtro e as contagens saem do MESMO conjunto
  // (`pendencias`, abertas dos mandatos ativos), então "Travam a aprovação (3)"
  // é exatamente a lista de 3 que aparece ao clicar.
  const contagens = contarFila(pendencias);
  const ordenada = [...pendencias].sort(
    (a, b) =>
      (PESO_SEVERIDADE[a.severidade] ?? 9) - (PESO_SEVERIDADE[b.severidade] ?? 9) ||
      new Date(b.criada_em).getTime() - new Date(a.criada_em).getTime(),
  );
  const filtradas = ordenada.filter((p) => daFila(p, filtro));
  const fila = filtradas.slice(0, verTudo ? FILA_VISIVEL_AMPLA : FILA_VISIVEL);
  const hrefFila = (f: string, ver = false) => {
    const q = new URLSearchParams();
    if (f !== "todas") q.set("fila", f);
    if (ver) q.set("ver", "tudo");
    const t = q.toString();
    return t ? `/casos?${t}` : "/casos";
  };
  return (
    <>
          <div className="mb-2 flex items-baseline justify-between gap-3">
        <h2 className="titulo-secao">Precisa de você</h2>
        <p className="text-xs text-tinta-500">
          {!pendenciasLidas
            ? "não conferido agora"
            : pendencias.length === 0
              ? "nada em aberto"
              : `${fila.length} de ${filtradas.length}, as que travam primeiro`}
        </p>
      </div>

      {pendenciasLidas && pendencias.length > 0 && (
        <nav aria-label="Filtrar a fila" className="mb-2 flex flex-wrap gap-1.5">
          {FILTROS_DA_FILA.map((f) => {
            const atual = f.chave === filtro;
            return (
              <Link
                key={f.chave}
                href={hrefFila(f.chave)}
                aria-current={atual ? "page" : undefined}
                className={`chip border transition-colors ${
                  atual
                    ? "border-tinta-900 bg-tinta-900 text-papel"
                    : "border-tinta-200 bg-folha text-tinta-700 hover:bg-tinta-50"
                }`}
              >
                {f.rotulo} <span className="tabular-nums opacity-75">{numero(contagens[f.chave])}</span>
              </Link>
            );
          })}
        </nav>
      )}

      {!pendenciasLidas ? (
        <div className="rounded-lg border border-risco-200 bg-risco-50 px-5 py-10 text-center">
          <p className="text-sm font-medium text-risco-900">Não foi possível conferir as pendências</p>
          <p className="mt-1 text-sm text-risco-800">
            Não dá para dizer se há algo em aberto. Abra cada mandato, na aba Pendências, ou recarregue a página.
          </p>
        </div>
      ) : pendencias.length === 0 ? (
        <div className="rounded-lg border border-ok-200 bg-ok-50 px-5 py-10 text-center">
          <p className="text-sm font-medium text-ok-900">Nenhuma pendência em aberto</p>
          <p className="mt-1 text-sm text-ok-800">
            Todos os documentos recebidos foram conferidos.
          </p>
        </div>
      ) : filtradas.length === 0 ? (
        <div className="carta px-5 py-10 text-center text-sm text-tinta-500">
          Nenhuma pendência neste filtro.{" "}
          <Link href="/casos" className="font-medium text-acento-700 hover:underline">Ver todas</Link>
        </div>
      ) : (
        <ul className="carta divide-y divide-tinta-100 overflow-hidden">
          {fila.map((p) => {
            const tom = TOM_SEVERIDADE[p.severidade] ?? TOM_SEVERIDADE.complementar;
            // A fila leva à gaveta certa da aba Pendências: documento a confirmar abre o
            // formulário; o resto cai no filtro da própria espécie. O verbo do botão
            // vem da mesma categoria que escolhe a gaveta (lib/painel.ts).
            const destino = `/casos/${p.caso_id}/pendencias?filtro=${categoriaDaPendencia(p.tipo)}`;
            const resumoTexto = resumoDaPendencia(p.descricao);
            return (
              <li key={p.id}>
                <Link
                  href={destino}
                  className="flex items-start gap-3 px-4 py-3 transition-colors hover:bg-tinta-50"
                >
                  {/* O ponto repete em cor o que o chip diz em palavra: cor
                      sozinha nunca carrega significado nesta tela. */}
                  <span aria-hidden className={`mt-1.5 h-2 w-2 shrink-0 rounded-full ${tom.ponto}`} />
                  <div className="min-w-0 flex-1">
                    <p className="flex flex-wrap items-baseline gap-x-2 text-sm">
                      <span className="font-semibold text-tinta-900">{rotuloDaPendencia(p.tipo)}</span>
                      {/* Qual checagem acusou. Sem isto, seis reconciliações
                          diferentes viram seis linhas iguais na fila. */}
                      {nomeDaChecagem(p.motivo ?? null) && (
                        <span className="text-xs text-tinta-500">
                          · {nomeDaChecagem(p.motivo ?? null)}
                        </span>
                      )}
                      <span className="valor-sensivel truncate text-xs text-tinta-500">
                        {nomePorCaso.get(p.caso_id) ?? "mandato"}
                      </span>
                    </p>
                    {resumoTexto && (
                      <p className="valor-sensivel mt-0.5 line-clamp-2 text-xs text-tinta-600 [overflow-wrap:anywhere]">{resumoTexto}</p>
                    )}
                  </div>
                  <span className="flex shrink-0 flex-col items-end gap-1.5">
                    <span className={`chip ${tom.chip}`}>{tom.rotulo}</span>
                    <span className="btn-secundario !px-2.5 !py-1 !text-xs">{verboDaPendencia(p.tipo, p.estado)}</span>
                  </span>
                </Link>
              </li>
            );
          })}
          {filtradas.length > fila.length && (
            <li className="bg-tinta-50/60 px-4 py-2 text-[11px] text-tinta-500">
              Mais {filtradas.length - fila.length}{" "}
              {filtradas.length - fila.length === 1 ? "pendência" : "pendências"} em aberto.{" "}
              {!verTudo && (
                <>
                  <Link href={hrefFila(filtro, true)} className="font-medium text-acento-700 hover:underline">
                    Mostrar {filtradas.length > FILA_VISIVEL_AMPLA ? `as primeiras ${FILA_VISIVEL_AMPLA}` : "todas"}
                  </Link>
                  .{" "}
                </>
              )}
              {(verTudo || filtradas.length > FILA_VISIVEL_AMPLA) &&
                "O resto está em cada mandato, na aba Pendências."}
            </li>
          )}
        </ul>
      )}
    </>
  );
}

// Os documentos mais recentes.
async function RecentesDoPainel() {
  const [{ nomePorCaso }, documentosRes, { recentes, linhasPorVersao }] = await Promise.all([
    lerCarteira(), lerDocumentos(), lerRecentes(),
  ]);
  const documentosLidos = !documentosRes.error;
  const agora = new Date();
  const linhasDoDocumento = (d: DocumentoNoPainel) =>
    (d.documento_versao ?? []).reduce((s, v) => s + (linhasPorVersao.get(v.id) ?? 0), 0);
  // A linha do tempo é agrupada por dia, com o cabeçalho escrito uma vez só.
  const grupos: Array<{ dia: string; itens: DocumentoNoPainel[] }> = [];
  for (const d of recentes) {
    const dia = diaRelativo(d.criado_em, agora);
    const ultimo = grupos[grupos.length - 1];
    if (ultimo && ultimo.dia === dia) ultimo.itens.push(d);
    else grupos.push({ dia, itens: [d] });
  }
  return (
    <>
      <div className="mb-2 flex items-baseline justify-between gap-3">
        <h2 className="titulo-secao">O que chegou</h2>
        <p className="text-xs text-tinta-500">últimos {recentes.length}</p>
      </div>

      {recentes.length === 0 ? (
        <div className="carta px-4 py-10 text-center text-sm text-tinta-500">
          {documentosLidos
            ? "Nenhum documento recebido ainda."
            : "Não foi possível ler os documentos agora."}
        </div>
      ) : (
        <div className="carta overflow-hidden">
          {grupos.map((g) => (
            <div key={g.dia}>
              <p className="border-b border-tinta-100 bg-tinta-50/60 px-4 py-1.5 text-[11px] font-semibold uppercase tracking-wide text-tinta-400">
                {g.dia}
              </p>
              <ul className="divide-y divide-tinta-100">
                {g.itens.map((d) => {
                  const linhas = linhasDoDocumento(d);
                  return (
                    <li key={d.id}>
                      <Link
                        href={`/casos/${d.caso_id}/documentos/${d.id}`}
                        className="flex items-start gap-3 px-4 py-2.5 transition-colors hover:bg-tinta-50"
                      >
                        <span className="mt-0.5 shrink-0 text-[11px] tabular-nums text-tinta-400">
                          {horaCurta(d.criado_em)}
                        </span>
                        <span className="min-w-0 flex-1">
                          <span className="block truncate text-xs font-medium text-tinta-900">
                            {d.tipo_taxonomia
                              ? formatarTipoTaxonomia(d.tipo_taxonomia)
                              : "tipo ainda não identificado"}
                          </span>
                          <span className="valor-sensivel block truncate text-[11px] text-tinta-500">
                            {nomePorCaso.get(d.caso_id) ?? "mandato"}
                          </span>
                        </span>
                        <span className="shrink-0 text-[11px] font-medium tabular-nums text-tinta-500">
                          {numero(linhas)} {linhas === 1 ? "linha" : "linhas"}
                        </span>
                      </Link>
                    </li>
                  );
                })}
              </ul>
            </div>
          ))}
        </div>
      )}
    </>
  );
}

// "Seus mandatos": todo mandato travado entra (nenhum some por causa do teto), os demais completam
// até MANDATOS_VISIVEIS, do mais novo ao mais antigo.
async function MandatosDoPainel() {
  const [{ ativos }, { pendenciasLidas, travadasPorCaso }] = await Promise.all([lerCarteira(), lerTrava()]);
  const travados = ativos.filter((c) => travadasPorCaso.has(c.id));
  const livres = ativos.filter((c) => !travadasPorCaso.has(c.id));
  const seusMandatos = [...travados, ...livres.slice(0, Math.max(0, MANDATOS_VISIVEIS - travados.length))];
  const foraDaLista = ativos.length - seusMandatos.length;
  return (
    <>
      {/* Os mandatos ativos com a régua de etapas. Quem tem pendência
          bloqueante vem primeiro e leva o chip "travado" — a informação do
          antigo "Travados agora", sem perder nenhum mandato dele. */}
      <div className="mt-5">
        <div className="mb-2 flex items-baseline justify-between gap-3">
          <h2 className="titulo-secao">Seus mandatos</h2>
          <p className="text-xs text-tinta-500">{ativos.length} em andamento</p>
        </div>
        {!pendenciasLidas && (
          <p className="mb-2 text-[11px] text-alerta-900">
            Não foi possível conferir quais mandatos estão travados; a lista segue a ordem de abertura,
            sem o status “travado”, e pode deixar de fora mandatos travados.
          </p>
        )}
        <ul className="carta divide-y divide-tinta-100 overflow-hidden">
          {seusMandatos.map((c) => {
            const quantas = travadasPorCaso.get(c.id) ?? 0;
            const etapa = etapaDoMandato(c.status);
            return (
              <li key={c.id}>
                <Link
                  href={`/casos/${c.id}`}
                  className="block px-4 py-2.5 transition-colors hover:bg-tinta-50"
                >
                  <span className="flex items-center justify-between gap-3">
                    <span className="valor-sensivel min-w-0 truncate text-xs font-medium text-tinta-900">{c.nome}</span>
                    <span className="flex shrink-0 items-center gap-1.5">
                      {quantas > 0 && (
                        <span className="chip bg-risco-100 text-risco-800" title={`${quantas} ${quantas === 1 ? "pendência travando" : "pendências travando"}`}>
                          travado
                        </span>
                      )}
                      <span className={`chip ${CASO_STATUS_COLOR[c.status]}`}>{CASO_STATUS_LABEL[c.status]}</span>
                    </span>
                  </span>
                  {/* A régua é texto + preenchimento: a etapa atual vem escrita. */}
                  <span className="mt-1.5 flex gap-1" role="img" aria-label={`Etapa ${etapa + 1} de ${ETAPAS_DO_MANDATO.length}: ${ETAPAS_DO_MANDATO[etapa]}`}>
                    {ETAPAS_DO_MANDATO.map((nome, i) => (
                      <span key={nome} className={`h-1 flex-1 rounded-full ${i <= etapa ? (quantas > 0 ? "bg-risco-500" : "bg-acento-600") : "bg-tinta-100"}`} />
                    ))}
                  </span>
                  <span className="mt-1 flex items-baseline justify-between text-[11px] text-tinta-500">
                    <span>{ETAPAS_DO_MANDATO[etapa]}</span>
                    {quantas > 0 && (
                      <span className="text-risco-700">
                        {quantas} {quantas === 1 ? "pendência travando" : "pendências travando"}
                      </span>
                    )}
                  </span>
                </Link>
              </li>
            );
          })}
          {foraDaLista > 0 && (
            <li className="bg-tinta-50/60 px-4 py-2 text-[11px] text-tinta-500">
              Mais {foraDaLista} {foraDaLista === 1 ? "mandato" : "mandatos"}.{" "}
              <Link href="/casos/todos" className="font-medium text-acento-700 hover:underline">Ver em Mandatos</Link>
            </li>
          )}
        </ul>
      </div>
    </>
  );
}
