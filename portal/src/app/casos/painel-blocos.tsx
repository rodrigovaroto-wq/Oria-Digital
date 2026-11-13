import Link from "next/link";
import { DetalhesTecnicos } from "@/components/detalhes-tecnicos";
import { Bloco } from "@/components/esqueleto";
import { Revelar } from "@/components/revelar";
import { lerPermissoes } from "@/lib/supabase/acesso";
import { escopoDaLista, textoDeNenhumMandato } from "@/lib/acesso";
import { CASO_STATUS_LABEL, CASO_STATUS_COLOR } from "@/lib/status";
import { categoriaDaPendencia } from "@/lib/pendencia";
import { ETAPAS_DO_MANDATO, etapaDoMandato } from "@/lib/etapa-do-mandato";
import type { Caso } from "@/lib/types";
import {
  ABAS_DOS_MANDATOS, FILTROS_DA_FILA, agruparPorMandato, contarFila, daFila, fatiaDaPagina, verboDaPendencia,
  type AbaDosMandatos, type FiltroDaFila, type GrupoDoMandato,
} from "@/lib/painel";
import { rotuloDaPendencia, nomeDaChecagem, partesDaDescricao, suavizarMensagem } from "@/lib/rotulos";
import { formatarTipoTaxonomia } from "@/lib/export";
import {
  lerCarteira, lerDocumentos, lerRecentes, lerTrava, lerUso,
  type DocumentoNoPainel, type UsoDoLote,
} from "./painel-dados";
import { Indicador } from "./indicador-do-painel";
import { LegendaDeOrigem } from "@/components/selo-de-origem";

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

/** A fila mostra 10 MANDATOS (cada um com todas as suas pendências em chips); "ver todos" mostra todos. */
const FILA_VISIVEL = 10;
/** "Seus mandatos": linhas por página (a maquete pede de 10 a 15). */
const MANDATOS_POR_PAGINA = 12;

// A fila é ordenada por consequência, não por data: bloqueante impede a
// aprovação do mandato, complementar não impede nada.
const PESO_SEVERIDADE: Record<string, number> = {
  bloqueante: 0,
  importante: 1,
  complementar: 2,
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

const plural = (n: number, um: string, varios: string) => (n === 1 ? um : varios);

// Contagem com separador de milhar (mandatos, pendências, linhas): não é valor financeiro, então não
// leva `.valor-sensivel`; é exceção registrada, com o motivo, em `verificar-mensagem-de-falha.mts`.
const numero = (n: number) => n.toLocaleString("pt-BR");

type Papel = Parameters<typeof textoDeNenhumMandato>[0];

/** A frase de abertura dá o veredito para quem não vai ler número nenhum. */
function veredito(
  papel: Papel, ativos: number, pendenciasLidas: boolean, bloqueantes: number, casosTravados: number,
): string {
  if (ativos === 0) return `${textoDeNenhumMandato(papel, "em andamento")}.`;
  const mandatos = `${ativos} ${plural(ativos, "mandato em andamento", "mandatos em andamento")}`;
  if (!pendenciasLidas) {
    return `${mandatos}. ` + "Não foi possível conferir as pendências agora; não dá para dizer o que trava a aprovação.";
  }
  if (bloqueantes === 0) return `${mandatos}. Nada trava a aprovação.`;
  return `${bloqueantes} ${plural(bloqueantes, "pendência trava", "pendências travam")} ` +
    `${casosTravados} ${plural(casosTravados, "mandato", "mandatos")}.`;
}

export async function ResumoDoPainel() {
  // O papel já foi lido pelo layout (`lerPermissoes` é memoizado): aqui não vai ao banco de novo.
  const perm = await lerPermissoes();
  const soAlocados = escopoDaLista(perm.papel) === "alocados";
  const [{ ativos }, { pendenciasLidas, nBloqueantes: bloqueantes, casosTravados }] = await Promise.all([lerCarteira(), lerTrava()]);
  const resumo = veredito(perm.papel, ativos.length, pendenciasLidas, bloqueantes, casosTravados);
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

type CasoDaCarteira = Awaited<ReturnType<typeof lerCarteira>>["casos"][number];

// Tempo médio: do envio do lote ao último documento registrado, que é a
// duração real da ingestão. Acrescentar documentos depois dispara uma segunda
// execução e o intervalo passa a incluir a espera pelo cliente; por isso a
// média só considera janelas de até 12 horas, e as demais são contadas à parte
// em vez de inflarem o número em silêncio.
const TETO_JANELA_MS = 12 * 3_600_000;

function medirIngestao(casos: CasoDaCarteira[], documentos: DocumentoNoPainel[]) {
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
  const tempoMedioMs = janelas.length ? janelas.reduce((s, v) => s + v, 0) / janelas.length : null;
  return { nJanelas: janelas.length, janelasLongas, tempoMedioMs };
}

// A cobertura é a razão de duas somas, não a média das razões: um lote de 400
// linhas com 90% e um de 4 com 25% dão 89,4%, não 57,5%.
function somarUso(usos: UsoDoLote[]) {
  let contasNosDocs = 0;
  let contasExtraidas = 0;
  for (const u of usos) {
    if (!u.contas_nos_documentos) continue;
    contasNosDocs += u.contas_nos_documentos;
    contasExtraidas += u.contas_extraidas ?? 0;
  }
  return { contasNosDocs, contasExtraidas };
}

function detalheDosMandatos(pendenciasLidas: boolean, casosTravados: number): string | null {
  if (!pendenciasLidas) return "travados: não conferido agora";
  if (casosTravados > 0) return `${casosTravados} travado${plural(casosTravados, "", "s")}`;
  return null;
}

function detalheDasPendencias(bloqueantes: number, casosTravados: number, abertas: number): string {
  if (bloqueantes > 0) return `em ${casosTravados} ${plural(casosTravados, "mandato", "mandatos")}`;
  if (abertas > 0) return `${numero(abertas)} em aberto, nenhuma trava`;
  return "nada em aberto";
}

function detalheDoTempo(nJanelas: number, janelasLongas: number): string | null {
  if (!nJanelas) return null;
  return `${nJanelas} ${plural(nJanelas, "mandato medido", "mandatos medidos")}` +
    (janelasLongas ? `, ${janelasLongas} fora da média` : "");
}

export async function IndicadoresDoPainel() {
  const [{ ativos, casos }, trava, documentosRes, usoRes] = await Promise.all([
    lerCarteira(), lerTrava(), lerDocumentos(), lerUso(),
  ]);
  const { pendencias, pendenciasLidas, nBloqueantes: bloqueantes, casosTravados } = trava;
  const documentosLidos = !documentosRes.error;
  const { nJanelas, janelasLongas, tempoMedioMs } = medirIngestao(casos, documentosRes.data);

  const usoErro = Boolean((usoRes as { error?: unknown }).error);
  const { contasNosDocs, contasExtraidas } = somarUso((usoRes.data as UsoDoLote[] | null) ?? []);
  const cobertura: number | null = usoErro || contasNosDocs === 0 ? null : contasExtraidas / contasNosDocs;
  const semMedicao = usoErro
    ? "medição indisponível agora"
    : "nenhum documento processado ainda";

  return (
    <div className="space-y-2">
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <Indicador
            valor={numero(ativos.length)}
            rotulo={plural(ativos.length, "mandato em andamento", "mandatos em andamento")}
            detalhe={detalheDosMandatos(pendenciasLidas, casosTravados)}
            tom="alerta"
          />
          {/* Falha de leitura NÃO vira zero: sem a lista, traço com a causa. */}
          <Indicador
            valor={pendenciasLidas ? numero(bloqueantes) : null}
            rotulo={plural(bloqueantes, "pendência que trava a aprovação", "pendências que travam a aprovação")}
            detalhe={detalheDasPendencias(bloqueantes, casosTravados, pendencias.length)}
            tom={bloqueantes > 0 ? "alerta" : "bom"}
            nota="leitura das pendências indisponível agora"
          />
          {/* A cobertura tem barra porque é a única fração: quanto do que estava
              escrito no documento chegou ao sistema. */}
          <Indicador
            valor={cobertura === null ? null : `${Math.round(cobertura * 100)}%`}
            rotulo="cobertura da leitura"
            origem="calculado"
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
            origem="calculado"
            detalhe={detalheDoTempo(nJanelas, janelasLongas)}
            nota={
              documentosLidos
                ? "nenhum mandato com documento registrado ainda"
                : "leitura dos documentos indisponível agora"
            }
          />
        </div>
        <LegendaDeOrigem />
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
const ALTURA_CELULA_DO_INDICADOR = 122;
const ALTURA_LINHA_DA_FILA = 64;
const ALTURA_LINHA_RECENTE = 53.5;
const ALTURA_CABECALHO_DO_DIA = 29.5;
const ALTURA_LINHA_MANDATO = 62;
// ---------------------------------------------------------------------------------------------------

export function EsqueletoDosIndicadores() {
  return (
    <div className="space-y-2">
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        {[0, 1, 2, 3].map((i) => (
          <div key={i} className="carta px-[18px] py-4" style={{ minHeight: ALTURA_CELULA_DO_INDICADOR }}>
            <Bloco className="h-8 w-16" />
            <Bloco className="mt-2 h-3.5 w-32" />
            <Bloco className="mt-1 h-4 w-24" />
          </div>
        ))}
      </div>
      <Bloco className="h-4 w-80 max-w-full" />
    </div>
  );
}

const CABECALHO_DO_BLOCO = "flex flex-col gap-2 border-b border-tinta-200 px-[18px] py-3.5 sm:flex-row sm:items-center sm:justify-between";

export function EsqueletoDaFila() {
  return (
    <div className="carta overflow-hidden">
      <div className={CABECALHO_DO_BLOCO}>
        <h2 className="titulo-secao">Precisa de você</h2>
        <Bloco className="h-8 w-72 max-w-full rounded-xl" />
      </div>
      <ul className="divide-y divide-tinta-100">
        {[0, 1, 2, 3, 4, 5].map((i) => (
          <li key={i} className="flex items-center gap-3 px-[18px] py-3" style={{ minHeight: ALTURA_LINHA_DA_FILA }}>
            <div className="min-w-0 flex-1 space-y-2">
              <Bloco className="h-4 w-1/3" />
              <Bloco className="h-5 w-2/3" />
            </div>
            <Bloco className="hidden h-8 w-28 sm:block" />
          </li>
        ))}
      </ul>
    </div>
  );
}

export function EsqueletoDosRecentes() {
  return (
    <div className="carta overflow-hidden">
      <div className={CABECALHO_DO_BLOCO}>
        <h2 className="titulo-secao">O que chegou</h2>
        <Bloco className="h-4 w-16" />
      </div>
      <div className="border-b border-tinta-100 bg-tinta-50 px-[18px] py-1.5" style={{ height: ALTURA_CABECALHO_DO_DIA }}>
        <Bloco className="h-3 w-12" />
      </div>
      <ul className="divide-y divide-tinta-100">
        {[0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map((i) => (
          <li key={i} className="flex items-start gap-3 px-[18px] py-2.5" style={{ minHeight: ALTURA_LINHA_RECENTE }}>
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
  );
}

export function EsqueletoDosMandatos() {
  return (
    <div className="carta overflow-hidden">
      <div className={CABECALHO_DO_BLOCO}>
        <h2 className="titulo-secao">Seus mandatos</h2>
        <Bloco className="h-8 w-64 max-w-full rounded-xl" />
      </div>
      <ul className="divide-y divide-tinta-100">
        {[0, 1, 2, 3, 4, 5].map((i) => (
          <li key={i} className="flex items-center justify-between gap-3 px-[18px] py-3" style={{ minHeight: ALTURA_LINHA_MANDATO }}>
            <Bloco className="h-4 w-1/3" />
            <Bloco className="hidden h-3 w-32 sm:block" />
            <Bloco className="h-5 w-20 rounded-full" />
          </li>
        ))}
      </ul>
    </div>
  );
}

/** A grade inteira, enquanto nem se sabe se há mandato (a lista de mandatos ainda não chegou). */
export function EsqueletoDaGrade() {
  return (
    <div role="status" aria-live="polite" className="grid items-start gap-5 lg:grid-cols-[minmax(0,1fr)_340px]">
      <span className="sr-only">Carregando o painel…</span>
      <div className="min-w-0 space-y-5">
        <EsqueletoDaFila />
        <EsqueletoDosMandatos />
      </div>
      <div className="min-w-0"><EsqueletoDosRecentes /></div>
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------
// O CORPO: sem mandato, a mensagem; com mandato, a grade com três blocos, cada um com a sua consulta.
// ---------------------------------------------------------------------------------------------------

type PermissoesDaTela = Awaited<ReturnType<typeof lerPermissoes>>;

function SemMandato({ perm }: Readonly<{ perm: PermissoesDaTela }>) {
  const escopo = escopoDaLista(perm.papel);
  const soAlocados = escopo === "alocados";
  return (
    /* Sem mandato o painel não inventa conteúdo, e não repete o botão de
       criar, que mora no menu. */
    <div className="carta flex flex-col items-center gap-2 px-6 py-14 text-center">
      <p className="text-sm font-medium text-tinta-900">
        {textoDeNenhumMandato(perm.papel, "em andamento")}
      </p>
      {escopo === "indefinido" && (
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
      {escopo !== "indefinido" && (!soAlocados || perm.criarMandato.pode) && (
        <p className="max-w-md text-sm text-tinta-500">
          Abra um em <strong className="font-medium text-tinta-700">Novo mandato</strong>, no menu
          à esquerda. Cada documento enviado é classificado e tem suas linhas financeiras lidas.
          O que faltar ou não bater aparece aqui.
        </p>
      )}
    </div>
  );
}

/** O que a URL do Início carrega: a aba da fila, "ver todos", a aba dos mandatos e a página deles. */
export type EstadoDaUrl = { fila: FiltroDaFila; verTudo: boolean; aba: AbaDosMandatos | null; pagina: number };

function hrefDoPainel(e: EstadoDaUrl, mudar: Partial<EstadoDaUrl> = {}): string {
  const v = { ...e, ...mudar };
  const q = new URLSearchParams();
  if (v.fila !== "todas") q.set("fila", v.fila);
  if (v.verTudo) q.set("ver", "tudo");
  if (v.aba) q.set("m", v.aba);
  if (v.pagina > 1) q.set("p", String(v.pagina));
  const t = q.toString();
  return t ? `/casos?${t}` : "/casos";
}

export async function CorpoDoPainel({ estado }: Readonly<{ estado: EstadoDaUrl }>) {
  const perm = await lerPermissoes();
  const { ativos } = await lerCarteira();

  if (ativos.length === 0) return <SemMandato perm={perm} />;

  return (
    <div className="grid items-start gap-5 lg:grid-cols-[minmax(0,1fr)_340px]">
      {/* `min-w-0` nas colunas: item de grid tem largura mínima = o conteúdo, e UMA palavra
          longa sem espaço na descrição (ex.: um nome de função do banco, vistoria P2 de 04/11)
          esticava a coluna — 643 px num celular de 390. Reproduzido com o CSS compilado: 542 px
          sem, 390 px com. */}
      <div className="min-w-0 space-y-5">
        <Revelar rotulo="Carregando a fila de pendências…" esqueleto={<EsqueletoDaFila />}>
          <FilaDoPainel estado={estado} />
        </Revelar>
        <Revelar rotulo="Carregando seus mandatos…" esqueleto={<EsqueletoDosMandatos />}>
          <MandatosDoPainel estado={estado} />
        </Revelar>
      </div>
      <Revelar rotulo="Carregando os documentos recentes…" className="min-w-0" esqueleto={<EsqueletoDosRecentes />}>
        <RecentesDoPainel />
      </Revelar>
    </div>
  );
}

type PendenciaDaFila = Awaited<ReturnType<typeof lerTrava>>["pendencias"][number];

/**
 * O texto do chip. O Item Faltante do Kit é o caso que fez a fila repetir "Item Faltante" 20 vezes: o que
 * distingue uma linha da outra está na descrição ("...ausente: FLUXO_CAIXA"), então o chip diz o ITEM.
 * Se a descrição não segue o padrão, cai no rótulo do tipo — nunca num chute.
 */
function rotuloDoChip(p: PendenciaDaFila): string {
  if (p.tipo === "item_faltante") {
    const m = /ausente:\s*([A-Z0-9_]+)\s*$/.exec(p.descricao ?? "");
    if (m) return formatarTipoTaxonomia(m[1]);
  }
  return nomeDaChecagem(p.motivo ?? null) ?? rotuloDaPendencia(p.tipo);
}

function textoDoTopoDaFila(lida: boolean, abertas: number, mandatos: number, filtradas: number): string {
  if (!lida) return "não conferido agora";
  if (abertas === 0) return "nada em aberto";
  return `${mandatos} ${plural(mandatos, "mandato", "mandatos")} · ${numero(filtradas)} ${plural(filtradas, "pendência", "pendências")}`;
}

/** As abas: uma faixa segmentada que rola de lado no celular em vez de quebrar a linha. */
const FAIXA_DE_ABAS = "-mx-1 max-w-full overflow-x-auto px-1 py-0.5";
const TRILHO_DE_ABAS = "inline-flex gap-0.5 rounded-xl bg-tinta-50 p-[3px]";
function classeDaAba(atual: boolean): string {
  return `inline-flex items-center gap-1.5 whitespace-nowrap rounded-[9px] px-3 py-1.5 text-[12.5px] transition-colors ${
    atual ? "bg-folha font-medium text-tinta-900 shadow-sm" : "text-tinta-500 hover:text-tinta-900"
  }`;
}

function FiltrosDaFila({ estado, contagens }: Readonly<{ estado: EstadoDaUrl; contagens: ReturnType<typeof contarFila> }>) {
  return (
    <nav aria-label="Filtrar a fila" className={FAIXA_DE_ABAS}>
      <div className={TRILHO_DE_ABAS}>
        {FILTROS_DA_FILA.map((f) => {
          const atual = f.chave === estado.fila;
          return (
            <Link
              key={f.chave}
              href={hrefDoPainel(estado, { fila: f.chave, verTudo: false })}
              aria-current={atual ? "page" : undefined}
              className={classeDaAba(atual)}
            >
              {f.rotulo} <span className="num text-[11px] opacity-75">{numero(contagens[f.chave])}</span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}

const MAX_CHIPS = 3;

function LinhaDoGrupo({ g, nome, casoPorId }: Readonly<{
  g: GrupoDoMandato<PendenciaDaFila>; nome: string; casoPorId: Map<string, Caso>;
}>) {
  const caso = casoPorId.get(g.casoId);
  // A fila leva à gaveta certa da aba Pendências. Com UMA espécie só, cai no filtro dela; com várias,
  // abre a aba inteira. O verbo segue a mesma regra: um só verbo, esse; verbos diferentes, "Resolver".
  const categorias = new Set(g.itens.map((p) => categoriaDaPendencia(p.tipo)));
  const verbos = new Set(g.itens.map((p) => verboDaPendencia(p.tipo, p.estado)));
  const [unica] = categorias;
  const destino = `/casos/${g.casoId}/pendencias${categorias.size === 1 ? `?filtro=${unica}` : ""}`;
  const [unico] = verbos;
  const verbo = verbos.size === 1 ? unico : "Resolver";
  // A frase do documento/entidade (nome de empresa, números) vem do pior item que NÃO é Item Faltante do
  // Kit: esse já está dito inteiro no chip e a frase só repetiria "Item obrigatório ... ausente".
  const comFrase = g.itens.find((p) => p.tipo !== "item_faltante");
  const resumoTexto = comFrase ? resumoDaPendencia(comFrase.descricao) : "";
  const visiveis = g.chips.slice(0, MAX_CHIPS);
  const resto = g.chips.slice(MAX_CHIPS).reduce((n, c) => n + c.n, 0);
  return (
    <tr>
      <td className="max-w-[16rem] align-top">
        <Link href={destino} className="valor-sensivel block truncate font-medium text-tinta-900 hover:underline">{nome}</Link>
        <span className="mt-0.5 block text-xs text-tinta-500">
          {caso ? `${CASO_STATUS_LABEL[caso.status]} · ` : ""}{numero(g.total)} {plural(g.total, "pendência", "pendências")}
        </span>
      </td>
      <td>
        <div className="flex flex-wrap gap-1.5">
          {g.bloqueantes > 0 && <span className="chip bg-risco-100 text-risco-800">{numero(g.bloqueantes)} {plural(g.bloqueantes, "bloqueia", "bloqueiam")}</span>}
          {g.aConfirmar > 0 && <span className="chip bg-alerta-100 text-alerta-800">{numero(g.aConfirmar)} a confirmar</span>}
          {visiveis.map((c) => (
            <span key={c.rotulo} className="chip bg-tinta-100 text-tinta-700">
              {c.rotulo}{c.n > 1 && <span className="num text-[11px] opacity-75"> ×{c.n}</span>}
            </span>
          ))}
          {resto > 0 && <span className="chip bg-tinta-100 text-tinta-700">+{numero(resto)}</span>}
        </div>
        {resumoTexto && (
          <p className="valor-sensivel mt-1.5 line-clamp-1 text-xs text-tinta-600 [overflow-wrap:anywhere]">{resumoTexto}</p>
        )}
      </td>
      <td className="hidden text-right align-top sm:table-cell">
        <Link href={destino} className="btn-secundario !px-2.5 !py-1 !text-xs">{verbo}</Link>
      </td>
    </tr>
  );
}

function RodapeDaFila({ ocultos, pendenciasOcultas, estado }: Readonly<{
  ocultos: number; pendenciasOcultas: number; estado: EstadoDaUrl;
}>) {
  return (
    <div className="border-t border-tinta-200 px-[18px] py-3 text-xs text-tinta-500">
      Mais {numero(ocultos)} {plural(ocultos, "mandato", "mandatos")} ({numero(pendenciasOcultas)}{" "}
      {plural(pendenciasOcultas, "pendência", "pendências")}).{" "}
      <Link href={hrefDoPainel(estado, { verTudo: true })} className="font-medium text-acento-700 hover:underline">
        Ver todos →
      </Link>
    </div>
  );
}

function CorpoDaFila({ pendenciasLidas, abertas, filtradas, grupos, nomePorCaso, casoPorId, estado }: Readonly<{
  pendenciasLidas: boolean;
  abertas: number;
  filtradas: number;
  grupos: GrupoDoMandato<PendenciaDaFila>[];
  nomePorCaso: Map<string, string>;
  casoPorId: Map<string, Caso>;
  estado: EstadoDaUrl;
}>) {
  if (!pendenciasLidas) {
    return (
      <div className="m-3 rounded-lg border border-risco-200 bg-risco-50 px-5 py-10 text-center">
        <p className="text-sm font-medium text-risco-900">Não foi possível conferir as pendências</p>
        <p className="mt-1 text-sm text-risco-800">
          Não dá para dizer se há algo em aberto. Abra cada mandato, na aba Pendências, ou recarregue a página.
        </p>
      </div>
    );
  }
  if (abertas === 0) {
    return (
      <div className="m-3 rounded-lg border border-ok-200 bg-ok-50 px-5 py-10 text-center">
        <p className="text-sm font-medium text-ok-900">Nenhuma pendência em aberto</p>
        <p className="mt-1 text-sm text-ok-800">
          Todos os documentos recebidos foram conferidos.
        </p>
      </div>
    );
  }
  if (filtradas === 0) {
    return (
      <div className="px-5 py-10 text-center text-sm text-tinta-500">
        Nenhuma pendência neste filtro.{" "}
        <Link href="/casos" className="font-medium text-acento-700 hover:underline">Ver todas</Link>
      </div>
    );
  }
  const visiveis = estado.verTudo ? grupos : grupos.slice(0, FILA_VISIVEL);
  const ocultos = grupos.slice(visiveis.length);
  return (
    <>
      <table className="tabela-a">
        <thead>
          <tr><th>Mandato</th><th>O que falta</th><th className="hidden sm:table-cell"><span className="sr-only">Ação</span></th></tr>
        </thead>
        <tbody>
          {visiveis.map((g) => <LinhaDoGrupo key={g.casoId} g={g} nome={nomePorCaso.get(g.casoId) ?? "mandato"} casoPorId={casoPorId} />)}
        </tbody>
      </table>
      {ocultos.length > 0 && (
        <RodapeDaFila ocultos={ocultos.length} pendenciasOcultas={ocultos.reduce((n, g) => n + g.total, 0)} estado={estado} />
      )}
    </>
  );
}

// A fila de triagem, agrupada por mandato (ver `agruparPorMandato`).
async function FilaDoPainel({ estado }: Readonly<{ estado: EstadoDaUrl }>) {
  const [{ nomePorCaso, casos }, { pendencias, pendenciasLidas }] = await Promise.all([lerCarteira(), lerTrava()]);
  // A fila é uma só lista: o filtro e as contagens saem do MESMO conjunto
  // (`pendencias`, abertas dos mandatos ativos), então "Travam a aprovação (3)"
  // é exatamente o conjunto de 3 pendências que aparece, agrupado, ao clicar.
  const contagens = contarFila(pendencias);
  const ordenada = [...pendencias].sort(
    (a, b) =>
      (PESO_SEVERIDADE[a.severidade] ?? 9) - (PESO_SEVERIDADE[b.severidade] ?? 9) ||
      new Date(b.criada_em).getTime() - new Date(a.criada_em).getTime(),
  );
  const filtradas = ordenada.filter((p) => daFila(p, estado.fila));
  const grupos = agruparPorMandato(filtradas, rotuloDoChip);
  const casoPorId = new Map(casos.map((c) => [c.id, c] as const));
  return (
    <div className="carta overflow-hidden">
      <div className={CABECALHO_DO_BLOCO}>
        <div className="flex items-baseline gap-3">
          <h2 className="titulo-secao">Precisa de você</h2>
          <p className="text-xs text-tinta-500">
            {textoDoTopoDaFila(pendenciasLidas, pendencias.length, grupos.length, filtradas.length)}
          </p>
        </div>
        {pendenciasLidas && pendencias.length > 0 && <FiltrosDaFila estado={estado} contagens={contagens} />}
      </div>
      <CorpoDaFila
        pendenciasLidas={pendenciasLidas}
        abertas={pendencias.length}
        filtradas={filtradas.length}
        grupos={grupos}
        nomePorCaso={nomePorCaso}
        casoPorId={casoPorId}
        estado={estado}
      />
    </div>
  );
}

type GrupoDoDia = { dia: string; itens: DocumentoNoPainel[] };

/** A linha do tempo é agrupada por dia, com o cabeçalho escrito uma vez só. */
function agruparPorDia(recentes: DocumentoNoPainel[], agora: Date): GrupoDoDia[] {
  const grupos: GrupoDoDia[] = [];
  for (const d of recentes) {
    const dia = diaRelativo(d.criado_em, agora);
    const ultimo = grupos.at(-1);
    if (ultimo?.dia === dia) ultimo.itens.push(d);
    else grupos.push({ dia, itens: [d] });
  }
  return grupos;
}

function LinhaRecente({ d, nomeDoMandato, linhas }: Readonly<{ d: DocumentoNoPainel; nomeDoMandato: string; linhas: number }>) {
  return (
    <li>
      <Link
        href={`/casos/${d.caso_id}/documentos/${d.id}`}
        className="flex items-start gap-3 px-[18px] py-2.5 transition-colors hover:bg-tinta-50"
      >
        <span className="num mt-0.5 shrink-0 text-[11px] text-tinta-500">
          {horaCurta(d.criado_em)}
        </span>
        <span className="min-w-0 flex-1">
          <span className="block truncate text-xs font-medium text-tinta-900">
            {d.tipo_taxonomia
              ? formatarTipoTaxonomia(d.tipo_taxonomia)
              : "tipo ainda não identificado"}
          </span>
          <span className="valor-sensivel block truncate text-[11px] text-tinta-500">
            {nomeDoMandato}
          </span>
        </span>
        <span className="num shrink-0 text-[11px] font-medium text-tinta-500">
          {numero(linhas)} {plural(linhas, "linha", "linhas")}
        </span>
      </Link>
    </li>
  );
}

// Os documentos mais recentes.
async function RecentesDoPainel() {
  const [{ nomePorCaso }, documentosRes, { recentes, linhasPorVersao }] = await Promise.all([
    lerCarteira(), lerDocumentos(), lerRecentes(),
  ]);
  const documentosLidos = !documentosRes.error;
  const linhasDoDocumento = (d: DocumentoNoPainel) =>
    (d.documento_versao ?? []).reduce((s, v) => s + (linhasPorVersao.get(v.id) ?? 0), 0);
  const grupos = agruparPorDia(recentes, new Date());
  return (
    <div className="carta overflow-hidden">
      <div className={CABECALHO_DO_BLOCO}>
        <h2 className="titulo-secao">O que chegou</h2>
        <p className="text-xs text-tinta-500">últimos {recentes.length}</p>
      </div>

      {recentes.length === 0 ? (
        <div className="px-4 py-10 text-center text-sm text-tinta-500">
          {documentosLidos
            ? "Nenhum documento recebido ainda."
            : "Não foi possível ler os documentos agora."}
        </div>
      ) : (
        <div>
          {grupos.map((g) => (
            <div key={g.dia}>
              <p className="border-b border-tinta-100 bg-tinta-50 px-[18px] py-1.5 text-[11px] font-semibold uppercase tracking-wide text-tinta-500">
                {g.dia}
              </p>
              <ul className="divide-y divide-tinta-100">
                {g.itens.map((d) => (
                  <LinhaRecente key={d.id} d={d} nomeDoMandato={nomePorCaso.get(d.caso_id) ?? "mandato"} linhas={linhasDoDocumento(d)} />
                ))}
              </ul>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/** A régua de 4 passos. Cor é ESTADO: o passo atual de um mandato travado é risco; fora disso, tinta. */
function ReguaDeEtapas({ etapa, travado }: Readonly<{ etapa: number; travado: boolean }>) {
  return (
    <span className="flex items-center gap-2" role="img" aria-label={`Etapa ${etapa + 1} de ${ETAPAS_DO_MANDATO.length}: ${ETAPAS_DO_MANDATO[etapa]}`}>
      <span className="flex gap-[3px]">
        {ETAPAS_DO_MANDATO.map((nome, i) => {
          let cor = "bg-tinta-200";
          if (i < etapa) cor = "bg-tinta-400";
          else if (i === etapa) cor = travado ? "bg-risco-500" : "bg-tinta-900";
          return <span key={nome} className={`h-[5px] w-[22px] rounded-[3px] ${cor}`} />;
        })}
      </span>
      <span className="text-xs text-tinta-500">{ETAPAS_DO_MANDATO[etapa]}</span>
    </span>
  );
}

/** "hoje 18:01", "ontem" ou "10/11": a data do último documento, no fuso de quem usa. */
function atividadeCurta(iso: string, agora: Date): string {
  const dia = diaRelativo(iso, agora);
  if (dia === "Hoje") return `hoje ${horaCurta(iso)}`;
  if (dia === "Ontem") return "ontem";
  return new Date(iso).toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", timeZone: FUSO });
}

type LinhaDeMandato = {
  caso: Caso; travadas: number; abertas: number; documentos: number | null; ultimo: string | null;
};

function SituacaoDoMandato({ l }: Readonly<{ l: LinhaDeMandato }>) {
  if (l.caso.fechado_em) return <span className="chip bg-tinta-100 text-tinta-600">Fechado</span>;
  if (l.travadas > 0) {
    return <span className="chip bg-risco-100 text-risco-800">{l.travadas} {plural(l.travadas, "pendência", "pendências")}</span>;
  }
  if (l.abertas > 0) {
    return <span className="chip bg-alerta-100 text-alerta-800">{l.abertas} em aberto</span>;
  }
  return <span className={`chip ${CASO_STATUS_COLOR[l.caso.status]}`}>{CASO_STATUS_LABEL[l.caso.status]}</span>;
}

function LinhaDoMandato({ l, agora, documentosLidos }: Readonly<{ l: LinhaDeMandato; agora: Date; documentosLidos: boolean }>) {
  const { caso } = l;
  const etapa = etapaDoMandato(caso.status);
  return (
    <tr>
      <td className="max-w-[14rem]">
        <Link href={`/casos/${caso.id}`} className="valor-sensivel block truncate font-medium text-tinta-900 hover:underline">{caso.nome}</Link>
        <span className="mt-0.5 block text-xs text-tinta-500">
          {l.documentos === null ? CASO_STATUS_LABEL[caso.status] : `${numero(l.documentos)} ${plural(l.documentos, "documento", "documentos")}`}
        </span>
      </td>
      <td className="hidden sm:table-cell"><ReguaDeEtapas etapa={etapa} travado={l.travadas > 0} /></td>
      <td><SituacaoDoMandato l={l} /></td>
      <td className="num hidden whitespace-nowrap text-xs text-tinta-500 sm:table-cell">
        {l.ultimo ? atividadeCurta(l.ultimo, agora) : (
          // Sem documento NÃO é "sem atividade" nem uma data inventada: o traço diz o motivo.
          <span title={documentosLidos ? "nenhum documento recebido ainda" : "a leitura dos documentos falhou"}>—</span>
        )}
      </td>
    </tr>
  );
}

function PaginasDosMandatos({ estado, aba, de, ate, total, paginas, pagina }: Readonly<{
  estado: EstadoDaUrl; aba: AbaDosMandatos; de: number; ate: number; total: number; paginas: number; pagina: number;
}>) {
  const botao = "grid h-7 min-w-7 place-items-center rounded-[10px] border border-tinta-200 px-1.5 text-xs";
  const numeros = Array.from({ length: paginas }, (_, i) => i + 1)
    .filter((n) => n === 1 || n === paginas || Math.abs(n - pagina) <= 1);
  const alvo = (n: number) => hrefDoPainel(estado, { aba, pagina: n });
  return (
    <div className="flex items-center justify-between gap-3 border-t border-tinta-200 px-[18px] py-3 text-xs text-tinta-500">
      <span className="num">{de + 1}–{ate} de {numero(total)}</span>
      {paginas > 1 && (
        <nav aria-label="Páginas de mandatos" className="flex items-center gap-1.5">
          {pagina > 1 && <Link href={alvo(pagina - 1)} aria-label="Página anterior" className={`${botao} hover:bg-tinta-50`}>‹</Link>}
          {numeros.map((n, i) => (
            <span key={n} className="flex items-center gap-1.5">
              {i > 0 && n - numeros[i - 1] > 1 && <span aria-hidden>…</span>}
              {n === pagina
                ? <span aria-current="page" className={`${botao} num border-tinta-900 bg-tinta-900 text-papel`}>{n}</span>
                : <Link href={alvo(n)} className={`${botao} num hover:bg-tinta-50`}>{n}</Link>}
            </span>
          ))}
          {pagina < paginas && <Link href={alvo(pagina + 1)} aria-label="Próxima página" className={`${botao} hover:bg-tinta-50`}>›</Link>}
        </nav>
      )}
    </div>
  );
}

// "Seus mandatos", em tabela e em três abas. Todo mandato ativo está em Travados ou em Andamento e todo
// fechado em Fechados — a soma das abas é a carteira, nenhum some por causa de teto (a paginação só
// reparte). Sem a leitura das pendências NÃO há "travado": Em andamento passa a listar todos os ativos e a
// aba Travados diz que não sabe, em vez de ficar vazia.
async function MandatosDoPainel({ estado }: Readonly<{ estado: EstadoDaUrl }>) {
  const [{ ativos, casos }, { pendencias, pendenciasLidas, travadasPorCaso }, documentosRes] =
    await Promise.all([lerCarteira(), lerTrava(), lerDocumentos()]);
  const documentosLidos = !documentosRes.error;
  const docs = new Map<string, { n: number; ultimo: string }>();
  for (const d of documentosRes.data) {
    const atual = docs.get(d.caso_id);
    if (!atual) docs.set(d.caso_id, { n: 1, ultimo: d.criado_em });
    else {
      atual.n += 1;
      if (new Date(d.criado_em).getTime() > new Date(atual.ultimo).getTime()) atual.ultimo = d.criado_em;
    }
  }
  const abertasPorCaso = new Map<string, number>();
  for (const p of pendencias) abertasPorCaso.set(p.caso_id, (abertasPorCaso.get(p.caso_id) ?? 0) + 1);
  const linha = (caso: Caso): LinhaDeMandato => ({
    caso,
    travadas: travadasPorCaso.get(caso.id) ?? 0,
    abertas: abertasPorCaso.get(caso.id) ?? 0,
    documentos: documentosLidos ? (docs.get(caso.id)?.n ?? 0) : null,
    ultimo: docs.get(caso.id)?.ultimo ?? null,
  });
  const travados = pendenciasLidas
    ? ativos.filter((c) => travadasPorCaso.has(c.id)).sort((a, b) => (travadasPorCaso.get(b.id) ?? 0) - (travadasPorCaso.get(a.id) ?? 0))
    : [];
  const andamento = pendenciasLidas ? ativos.filter((c) => !travadasPorCaso.has(c.id)) : ativos;
  const fechados = casos.filter((c) => c.fechado_em);
  const listas: Record<AbaDosMandatos, Caso[]> = { travados, andamento, fechados };
  const aba: AbaDosMandatos = estado.aba ?? (travados.length > 0 ? "travados" : "andamento");
  const lista = listas[aba];
  const fatia = fatiaDaPagina(lista.length, estado.pagina, MANDATOS_POR_PAGINA);
  const agora = new Date();
  return (
    <div className="carta overflow-hidden">
      <div className={CABECALHO_DO_BLOCO}>
        <h2 className="titulo-secao">Seus mandatos</h2>
        <nav aria-label="Filtrar os mandatos" className={FAIXA_DE_ABAS}>
          <div className={TRILHO_DE_ABAS}>
            {ABAS_DOS_MANDATOS.map((a) => (
              <Link
                key={a.chave}
                href={hrefDoPainel(estado, { aba: a.chave, pagina: 1 })}
                aria-current={a.chave === aba ? "page" : undefined}
                className={classeDaAba(a.chave === aba)}
              >
                {a.rotulo}{" "}
                <span className="num text-[11px] opacity-75">
                  {a.chave === "travados" && !pendenciasLidas ? "—" : numero(listas[a.chave].length)}
                </span>
              </Link>
            ))}
          </div>
        </nav>
      </div>
      {!pendenciasLidas && (
        <p className="border-b border-tinta-100 px-[18px] py-2 text-[11px] text-alerta-800">
          Não foi possível conferir quais mandatos estão travados; a lista segue a ordem de abertura,
          sem o status “travado”, e pode deixar de fora mandatos travados.
        </p>
      )}
      {lista.length === 0 ? (
        <p className="px-4 py-10 text-center text-sm text-tinta-500">
          {aba === "travados" && !pendenciasLidas && "Não dá para dizer quais mandatos estão travados agora."}
          {aba === "travados" && pendenciasLidas && "Nenhum mandato travado."}
          {aba === "andamento" && "Nenhum mandato em andamento sem trava."}
          {aba === "fechados" && "Nenhum mandato fechado."}
        </p>
      ) : (
        <>
          <table className="tabela-a">
            <thead>
              <tr>
                <th>Mandato</th>
                <th className="hidden sm:table-cell">Etapa</th>
                <th>Situação</th>
                <th className="hidden sm:table-cell" title="Data do último documento recebido">Último documento</th>
              </tr>
            </thead>
            <tbody>
              {lista.slice(fatia.de, fatia.ate).map((c) => (
                <LinhaDoMandato key={c.id} l={linha(c)} agora={agora} documentosLidos={documentosLidos} />
              ))}
            </tbody>
          </table>
          <PaginasDosMandatos
            estado={estado} aba={aba} de={fatia.de} ate={fatia.ate} total={lista.length}
            paginas={fatia.paginas} pagina={fatia.pagina}
          />
        </>
      )}
    </div>
  );
}
