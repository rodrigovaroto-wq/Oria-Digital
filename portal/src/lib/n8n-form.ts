// Descobre os nomes REAIS dos campos de um formulário de intake (N8N Form
// Trigger) a partir do HTML renderizado — em vez de adivinhar/fixar nomes
// (ex.: "Mandato (nome do caso)"), que podem não bater com o atributo `name`
// real gerado pelo N8N para aquele campo. Um POST com o nome errado ainda
// pode receber 200 do N8N (o webhook aceita a requisição HTTP antes de saber
// se o workflow vai ter dado pra processar) — a execução falha DEPOIS, sem
// nenhum sinal pro portal (achado em produção, sessão 7 cont.¹²: upload
// "com sucesso" no portal, mas 0 tokens gastos — o workflow nunca recebeu
// arquivo nenhum sob o nome que o portal mandava).
//
// Parser tolerante por regex (não uma dependência de DOM parsing completa):
// o form do N8N é HTML simples, não uma SPA — os <input> já vêm no HTML
// inicial. Retorna null quando não encontra o suficiente, para o chamador
// cair no fallback configurado (nunca piora o comportamento anterior).

interface CamposDetectados {
  fileFieldName: string | null;
  textFieldName: string | null;
  /** O SEGUNDO campo de texto (o primeiro é o mandato): onde vai o token do envio. */
  tokenFieldName: string | null;
}

function parseAttrs(tag: string): Record<string, string> {
  const attrs: Record<string, string> = {};
  const re = /([\w-]+)\s*=\s*"([^"]*)"|([\w-]+)\s*=\s*'([^']*)'/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(tag))) {
    const key = (m[1] ?? m[3]).toLowerCase();
    const val = m[2] ?? m[4] ?? "";
    attrs[key] = val;
  }
  return attrs;
}

export function parseFormFieldNames(html: string): CamposDetectados {
  const inputs: Record<string, string>[] = [];
  const re = /<input\b([^>]*)>/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html))) {
    inputs.push(parseAttrs(m[1]));
  }

  const fileInput = inputs.find((a) => (a.type ?? "").toLowerCase() === "file" && a.name);
  const textInputs = inputs.filter((a) => {
    const type = (a.type ?? "text").toLowerCase();
    return type !== "file" && type !== "hidden" && type !== "submit" && type !== "button" && a.name;
  });

  return {
    fileFieldName: fileInput?.name ?? null,
    textFieldName: textInputs[0]?.name ?? null,
    // POR POSIÇÃO, como o do mandato: o Form declara o token depois do mandato (`Intake (Form)` em
    // `N8N/build-workflow.mjs`). Form antigo, sem o campo, deixa `null` e cai no fallback.
    tokenFieldName: textInputs[1]?.name ?? null,
  };
}

// ---------------------------------------------------------------------------
// A DESCOBERTA, que agora tem DOIS chamadores
// ---------------------------------------------------------------------------
//
// Ela morava dentro de `app/api/intake/route.ts` enquanto só o encaminhamento
// pela Serverless Function existia. Com o envio direto do navegador
// (`app/api/intake/destino/route.ts`), o MESMO par de nomes precisa chegar a
// dois lugares — e duas cópias desta função seriam a forma mais fácil de o
// portal voltar a postar sob um nome que o workflow não lê, que é o defeito da
// sessão 7 cont.¹² (200 OK na tela, zero token gasto, nenhum arquivo recebido).
//
// A descoberta continua acontecendo NO SERVIDOR nos dois caminhos: quem manda
// os bytes pode ser o navegador, mas quem decide o nome do campo nunca é.

const CAMPO_MANDATO_ENV = () => process.env.N8N_INTAKE_FIELD_MANDATO || null;
const CAMPO_ARQUIVOS_ENV = () => process.env.N8N_INTAKE_FIELD_ARQUIVOS || null;
const CAMPO_TOKEN_ENV = () => process.env.N8N_INTAKE_FIELD_TOKEN || null;

// Fallback de último recurso, só usado se não houver env E a descoberta falhar
// (instância fora do ar, HTML inesperado etc.) — mantém o comportamento
// anterior em vez de travar o upload por completo.
const CAMPO_MANDATO_FALLBACK = "Mandato (nome do caso)";
const CAMPO_ARQUIVOS_FALLBACK = "Arquivos";
const CAMPO_TOKEN_FALLBACK = "Token do envio";

export interface CamposDoForm {
  mandato: string;
  arquivos: string;
  /** O campo do token do envio (`assinatura-do-envio.ts`): o n8n recusa o lote que não o traga. */
  token: string;
  /** `true` quando os nomes vieram do HTML do próprio Form, não do fallback. */
  descoberto: boolean;
  /**
   * POR QUE caiu no fallback, quando caiu — e SÓ quando caiu.
   *
   * ACHADO EM PRODUÇÃO, 13/09/2026: a descoberta falhou (a tela recusou o
   * envio direto), e não havia NENHUM jeito de saber por quê — o `catch`
   * engolia a exceção de propósito ("o erro de verdade aparece no POST logo
   * em seguida", o que deixou de ser verdade quando o envio direto passou a
   * existir e o POST vai para OUTRO lugar). O dono confirmou a instância no
   * ar e o formulário funcionando manualmente — então a falha é do GET desta
   * função, de um jeito que só um motivo escrito revela: timeout, bloqueio
   * por User-Agent de servidor (WAF/anti-bot na frente do n8n), redirecionamento
   * que o fetch não segue, ou HTML sem os `<input>` esperados.
   *
   * Isto é a regra 1 aplicada ao PRÓPRIO diagnóstico: "não consegui descobrir"
   * é uma ausência, e uma ausência sem o motivo é o mesmo defeito que este
   * arquivo inteiro existe para não repetir — só que sobre si mesmo.
   */
  motivo?: string;
}

// UM USER-AGENT DE NAVEGADOR, NÃO O PADRÃO DO NODE. Fetch server-a-servidor
// sem isso se anuncia como robô (`undici` manda algo como `node`), e é
// exatamente o que uma proteção anti-bot na frente do n8n (Cloudflare e
// equivalentes) filtra primeiro — devolvendo uma página de verificação
// (200 OK, sem os `<input>` do formulário) em vez do form. O sintoma bate
// ponto a ponto com o achado de 13/09: funciona no navegador do dono (UA real
// + JS), falha só do servidor da Vercel para o servidor do n8n.
const CABECALHOS_DE_NAVEGADOR = {
  "user-agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
    + "Chrome/128.0.0.0 Safari/537.36",
  accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
};

// TETO DE TEMPO EXPLÍCITO. Sem ele, um GET pendurado (instância fria, rede
// lenta) só termina quando a Function inteira estoura — e aí `destino` nunca
// responde nada, nem o `motivo`. 8s é folgado para uma página de formulário
// simples e ainda cabe com sobra no teto da Function.
const TETO_DA_DESCOBERTA_MS = 8000;

export async function descobrirNomesDeCampo(url: string): Promise<CamposDoForm> {
  const mandatoEnv = CAMPO_MANDATO_ENV();
  const arquivosEnv = CAMPO_ARQUIVOS_ENV();
  if (mandatoEnv && arquivosEnv) {
    return { mandato: mandatoEnv, arquivos: arquivosEnv, token: CAMPO_TOKEN_ENV() || CAMPO_TOKEN_FALLBACK, descoberto: false };
  }
  try {
    const resp = await fetch(url, {
      method: "GET",
      headers: CABECALHOS_DE_NAVEGADOR,
      signal: AbortSignal.timeout(TETO_DA_DESCOBERTA_MS),
      redirect: "follow",
    });
    if (!resp.ok) {
      return {
        mandato: mandatoEnv || CAMPO_MANDATO_FALLBACK,
        arquivos: arquivosEnv || CAMPO_ARQUIVOS_FALLBACK,
        token: CAMPO_TOKEN_ENV() || CAMPO_TOKEN_FALLBACK,
        descoberto: false,
        motivo: `GET do form retornou HTTP ${resp.status} ${resp.statusText}`.trim(),
      };
    }
    const html = await resp.text();
    const { fileFieldName, textFieldName, tokenFieldName } = parseFormFieldNames(html);
    const descoberto = Boolean(!mandatoEnv && textFieldName) || Boolean(!arquivosEnv && fileFieldName);
    return {
      mandato: mandatoEnv || textFieldName || CAMPO_MANDATO_FALLBACK,
      arquivos: arquivosEnv || fileFieldName || CAMPO_ARQUIVOS_FALLBACK,
      token: CAMPO_TOKEN_ENV() || tokenFieldName || CAMPO_TOKEN_FALLBACK,
      descoberto,
      ...(descoberto ? {} : {
        // O HTML voltou (200), mas sem `<input>` que bata — o caso que mais
        // importa registrar, porque é o que uma verificação anti-bot produz:
        // uma página válida, só que não é a página certa.
        motivo: `GET OK (${html.length} bytes) mas nenhum <input> reconhecido — `
          + `arquivo:${fileFieldName ?? "não achado"} texto:${textFieldName ?? "não achado"}`,
      }),
    };
  } catch (e) {
    // AQUI o erro de verdade não pode mais ser engolido: ele é o `motivo`.
    const erro = e as Error;
    const motivo = erro.name === "TimeoutError" || erro.name === "AbortError"
      ? `GET não respondeu em ${TETO_DA_DESCOBERTA_MS / 1000}s`
      : `${erro.name || "erro"}: ${erro.message || String(e)}`;
    return {
      mandato: mandatoEnv || CAMPO_MANDATO_FALLBACK,
      arquivos: arquivosEnv || CAMPO_ARQUIVOS_FALLBACK,
      token: CAMPO_TOKEN_ENV() || CAMPO_TOKEN_FALLBACK,
      descoberto: false,
      motivo,
    };
  }
}
