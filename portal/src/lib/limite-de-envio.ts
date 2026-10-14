// O TETO DE 4,5 MB DA VERCEL — e por que ele derrubava o lote de 48 arquivos
// ANTES de qualquer linha deste repositório rodar.
//
// ---------------------------------------------------------------------------
// O DEFEITO, MEDIDO NA TELA DO DONO (13/09/2026)
// ---------------------------------------------------------------------------
//
// 48 arquivos, ~50 MB, mandato da AMO. O portal montou UM `multipart` com tudo
// e fez `POST /api/intake`. O console do navegador mostrou:
//
//     Failed to load resource: the server responded with a status of 413
//     /api/intake:1
//
// e a tela mostrou "Falha no envio (HTTP 413)" — a mensagem genérica, porque
// `json.error` veio vazio. Veio vazio porque **a rota nunca rodou**: o 413 é da
// borda da Vercel, que recusa o corpo antes de invocar a Serverless Function.
// Nenhum `try/catch`, nenhuma validação e nenhuma mensagem em português do
// `/api/intake` tinham como aparecer ali, e nenhuma mudança dentro da rota
// conserta isso. (Foi por isso que o n8n não cobrou nada: com 2 arquivos o
// orçamento do lote saiu US$ 0,04 e o lote rodou; com 48 o n8n nunca recebeu
// requisição nenhuma.)
//
// O teto NÃO É NOSSO e não se configura: é limite de plataforma da Serverless
// Function (~4,5 MB de corpo por requisição). `bodySizeLimit` do Next cobre
// Server Action, não Route Handler, e não muda a borda.
//
// O limite já estava DOCUMENTADO neste repositório desde a sessão 7
// (`portal/README.md`, `Arquitetura do Sistema/7 Marca/PRODUCT.md`, HANDOFF em
// "Itens adiados": *"upload direto do browser pro N8N/Storage, contornando a
// Function — tira o limite"*). O que faltava não era o diagnóstico: era a
// correção, e — pior — a tela não dizia nada. Ela oferecia "Enviar 48
// arquivos", estimava 58 minutos de processamento, e só depois de subir 50 MB
// entregava um número HTTP.
//
// ---------------------------------------------------------------------------
// POR QUE A SAÍDA NÃO É "MANDAR EM LEVAS"
// ---------------------------------------------------------------------------
//
// Era o que o README mandava fazer à mão, e automatizar isso seria o defeito
// maior. Cada submissão ao Form do n8n abre UMA execução, e a cadência da IA é
// por execução: `IA Extrair` sai a cada 73 s e `IA Classificar` a cada 42 s
// (`N8N/build-workflow.mjs`), porque no Tier 1 da OpenAI (30.000 TPM) cabe
// menos de uma chamada por minuto contando entrada + reserva de saída. Treze
// levas de 4 MB viram TREZE execuções simultâneas espaçando cada uma o SEU
// próprio minuto — o rate limit é da conta, não da execução. O resultado
// medido desse arranjo já está no repositório (sessão 7 cont.⁸: 16 documentos,
// 16 erros "Try spacing your requests out"), e ele chega como lote pela
// metade, não como falha limpa.
//
// Some-se que TODA a espera da tela é dimensionada para UMA submissão
// (`espera-do-lote.ts`: janela, silêncio inicial, parada sem progresso,
// carência do fechamento). Quebrar o lote em treze quebra as quatro contas.
//
// Então a correção mantém UMA execução e tira os bytes do caminho da Vercel: o
// navegador manda o `multipart` DIRETO para o Form do n8n, que é o mesmo
// destino que a Function usava. O n8n aceita arquivo grande por padrão
// (`N8N_FORMDATA_FILE_SIZE_MAX`, 200 MB por arquivo) — é a Function no meio que
// não aceitava.
//
// ---------------------------------------------------------------------------
// O QUE ESTE ARQUIVO É
// ---------------------------------------------------------------------------
//
// A decisão "este lote cabe na Function ou precisa ir direto?" mora aqui, pura,
// por um motivo que este repositório já pagou várias vezes: enquanto a conta
// vivesse dentro do componente, ninguém conseguiria CHAMÁ-LA num teste, e um
// teto de tamanho é exatamente o tipo de número que ninguém revisita até o dia
// em que ele erra. `portal/scripts/verificar-limite-de-envio.mts` chama estas
// funções — as mesmas que a tela chama.

// O TETO POR ARQUIVO VEM DO N8N, NÃO É REPETIDO AQUI (13/10/2026). Eram dois
// números para a mesma fronteira — 200 MB aqui, 15 MiB lá — e o portal deixava
// subir o que o n8n recusava depois, em silêncio (envio direto = resposta
// opaca). Importar o valor de `N8N/lib/custo.mjs` faz os dois só poderem
// concordar. A importação de fora de `portal/` é a mesma do leitor (ver
// `next.config.ts`).
import { TETO_BYTES_POR_ARQUIVO } from "../../../N8N/lib/custo.mjs";

const KiB = 1024;
const MiB = 1024 * KiB;

/**
 * O teto de corpo da Serverless Function da Vercel. Não é configurável: é a
 * borda da plataforma que responde 413 antes de invocar a função.
 */
export const TETO_DA_FUNCTION_BYTES = Math.floor(4.5 * MiB);

/**
 * O teto que o portal se impõe para USAR a Function.
 *
 * É menor que o da plataforma de propósito, e a folga não é superstição: o
 * corpo que sobe na rede é maior que a soma dos arquivos (ver
 * `corpoMultipartBytes`), a Vercel conta o corpo inteiro, e um lote que
 * ATRAVESSA o teto por 30 KB de cabeçalho de `multipart` volta a ser o 413 que
 * esta correção existe para acabar. 512 KB de margem cobrem ~1.700 arquivos de
 * sobrecarga — muito além de qualquer lote que caiba aqui de qualquer forma.
 */
export const TETO_DO_PROXY_BYTES = TETO_DA_FUNCTION_BYTES - 512 * KiB;

/**
 * O teto POR ARQUIVO do outro lado (n8n): 15 MiB, o `TETO_BYTES_POR_ARQUIVO` de
 * `N8N/lib/custo.mjs`, importado e não copiado.
 *
 * ERA 200 MB (o padrão do `N8N_FORMDATA_FILE_SIZE_MAX`) e isso estava errado
 * para o que importa, que é a memória do n8n, não o limite do Form. Medido em
 * 13/10/2026 (n8n 2.30.7): ~600 MB ociosos + ~50x o tamanho do arquivo —
 * 11 MB = 1,1 GB, 29 MB = 2,0 GB, 117 MB = 7,7 GB. O pod de produção tem 2 GB,
 * então 29 MB já o derrubam, e com ele todas as execuções em curso. O n8n
 * passou a recusar o lote inteiro com um arquivo acima de 15 MiB (commit
 * 6f1e741); este teto existe para o portal dizer ISSO antes de o analista
 * esperar o upload, e não depois.
 *
 * Arquivo de leiaute oficial (SPED, CNAB, OFX, XML fiscal) NÃO passa por este
 * teto: ele é lido no navegador e só o resumo sai (ver `envio-oficial.ts`), e é
 * por isso que um SPED de centenas de MB continua sendo aceito pela tela.
 */
export const TETO_POR_ARQUIVO_BYTES: number = TETO_BYTES_POR_ARQUIVO;

/**
 * Sobrecarga de UMA parte do `multipart/form-data`, em bytes, sem o conteúdo.
 *
 * Conta o que o navegador de fato escreve:
 *
 *     --{boundary}\r\n
 *     Content-Disposition: form-data; name="{campo}"; filename="{nome}"\r\n
 *     Content-Type: {tipo}\r\n
 *     \r\n
 *     {bytes}\r\n
 *
 * O `boundary` do WebKit tem ~40 bytes; 70 é teto folgado e declarado. O nome
 * do arquivo entra em BYTES UTF-8, não em caracteres — "BALANÇO" tem 7
 * caracteres e 8 bytes, e contar caractere é como uma conta destas passa a
 * errar por pouco justamente nos lotes maiores.
 */
const BOUNDARY_BYTES = 70;
const CABECALHO_FIXO_BYTES =
  "Content-Disposition: form-data; name=\"\"; filename=\"\"\r\n".length +
  "Content-Type: application/octet-stream\r\n".length +
  "\r\n".length + // linha em branco antes do conteúdo
  "\r\n".length; // fim da parte

function bytesDe(texto: string): number {
  return new TextEncoder().encode(texto).length;
}

export interface ArquivoParaEnvio {
  readonly nome: string;
  readonly bytes: number;
}

/**
 * O tamanho do CORPO que sobe na rede — não a soma dos arquivos.
 *
 * A diferença entre os dois é exatamente o que fazia um lote "de 4,4 MB"
 * estourar um teto de 4,5 MB.
 */
export function corpoMultipartBytes(
  arquivos: readonly ArquivoParaEnvio[],
  campos: { readonly mandato: string; readonly arquivos: string },
  mandato: string,
): number {
  const parteDoTexto =
    BOUNDARY_BYTES + CABECALHO_FIXO_BYTES + bytesDe(campos.mandato) + bytesDe(mandato);
  const partesDeArquivo = arquivos.reduce(
    (soma, a) =>
      soma + BOUNDARY_BYTES + CABECALHO_FIXO_BYTES + bytesDe(campos.arquivos) + bytesDe(a.nome) + a.bytes,
    0,
  );
  return parteDoTexto + partesDeArquivo + BOUNDARY_BYTES + "--\r\n".length;
}

export type ViaDeEnvio = "proxy" | "direto";

export interface PlanoDeEnvio {
  /**
   * `proxy`  — passa pela Serverless Function (`POST /api/intake`), que
   *            devolve o status REAL do n8n e as mensagens em português.
   * `direto` — o navegador fala com o Form do n8n sem intermediário, porque o
   *            corpo não cabe na Function.
   */
  readonly via: ViaDeEnvio;
  /** O corpo que sobe, em bytes (arquivos + sobrecarga do multipart). */
  readonly corpoBytes: number;
  /** Só a soma dos arquivos — é este o número que a tela mostra. */
  readonly arquivosBytes: number;
  /** Arquivos que sozinhos passam do teto do n8n: nenhum envio os salva. */
  readonly acimaDoTetoPorArquivo: readonly ArquivoParaEnvio[];
}

export function planejarEnvio(
  arquivos: readonly ArquivoParaEnvio[],
  campos: { readonly mandato: string; readonly arquivos: string },
  mandato: string,
): PlanoDeEnvio {
  const corpoBytes = corpoMultipartBytes(arquivos, campos, mandato);
  return {
    // ESTRITAMENTE MAIOR não serve aqui: o teto é o primeiro valor que NÃO
    // passa. Um lote exatamente no teto é um lote no limite da borda, e a
    // borda não é nossa para testar.
    via: corpoBytes >= TETO_DO_PROXY_BYTES ? "direto" : "proxy",
    corpoBytes,
    arquivosBytes: arquivos.reduce((s, a) => s + a.bytes, 0),
    acimaDoTetoPorArquivo: arquivos.filter((a) => a.bytes > TETO_POR_ARQUIVO_BYTES),
  };
}

/**
 * "50,3 MB" / "839 KB" / "vazio" — o formato ÚNICO de tamanho da tela de envio.
 *
 * O ZERO NÃO É ARREDONDADO PARA 1 KB, e o detalhe não é cosmético: a tela
 * arredondava `Math.max(1, …)` e mostrava "1 KB" para um arquivo de 0 byte —
 * um placeholder de nuvem, um download interrompido. O arquivo vazio é
 * DESCARTADO antes do envio (ver `arquivosVazios`), e um formato que o
 * disfarça de arquivo pequeno é o que faria o descarte parecer sumiço.
 */
export function formatarBytes(bytes: number): string {
  if (bytes <= 0) return "vazio";
  if (bytes < MiB) return `${Math.max(1, Math.round(bytes / KiB))} KB`;
  return `${(bytes / MiB).toFixed(1).replace(".", ",")} MB`;
}

/**
 * Os arquivos de 0 byte do lote.
 *
 * O ENCAMINHAMENTO SEMPRE OS DESCARTOU — `api/intake/route.ts` filtra
 * `f.size > 0` e devolve a contagem JÁ FILTRADA, que vira o `esperados` do
 * acompanhamento. O envio direto não tem servidor no meio para fazer isso, e
 * sem este filtro a tela declararia esperar 48 documentos de um lote que só
 * pode produzir 47: os contadores nunca fechariam, e depois de
 * `semProgressoMs(48)` — 37,6 minutos — a tela acusaria "o sistema parou"
 * sobre um lote que terminou tudo o que dava. Nenhum erro em lugar nenhum.
 *
 * Descartar em silêncio também não serve: quem selecionou o arquivo precisa
 * saber que ele ficou de fora, senão vai procurá-lo no mandato depois.
 */
export function arquivosVazios(arquivos: readonly ArquivoParaEnvio[]): readonly ArquivoParaEnvio[] {
  return arquivos.filter((a) => a.bytes <= 0);
}

/** A frase do arquivo vazio — nomeia cada um, pela mesma razão da recusa acima. */
export function avisoDeArquivoVazio(vazios: readonly ArquivoParaEnvio[]): string {
  const lista = vazios.map((a) => `“${a.nome}”`).join(", ");
  const um = vazios.length === 1;
  const quantos = um ? "Um arquivo está vazio" : `${vazios.length} arquivos estão vazios`;
  return (
    `${quantos} (0 byte) e ${um ? "ficou" : "ficaram"} de fora do envio: ${lista}. `
    + "Isso costuma ser arquivo ainda não baixado da nuvem — baixe e envie de novo, no mesmo mandato."
  );
}

/**
 * A frase do arquivo que NENHUM caminho de envio aceita. Ela nomeia o arquivo e
 * o tamanho porque o analista precisa saber QUAL remover — "arquivo grande
 * demais" sem o nome, num lote de 48, é um convite a tentar de novo igual.
 */
export function recusaPorArquivoGrande(acima: readonly ArquivoParaEnvio[]): string {
  const lista = acima.map((a) => `“${a.nome}” (${formatarBytes(a.bytes)})`).join(", ");
  const um = acima.length === 1;
  const quantos = um ? "Um arquivo é" : `${acima.length} arquivos são`;
  return (
    `${quantos} ${um ? "maior" : "maiores"} que o limite de ${formatarBytes(TETO_POR_ARQUIVO_BYTES)} `
    + `por arquivo e ${um ? "precisa" : "precisam"} ficar de fora: ${lista}. `
    + "O resto do lote pode ser enviado normalmente."
  );
}
