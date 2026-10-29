import { NextResponse } from "next/server";
import { descobrirNomesDeCampo } from "@/lib/n8n-form";
import { conferirEnvioAoMandato } from "@/lib/supabase/acesso";

// PARA ONDE O NAVEGADOR MANDA UM LOTE QUE NÃO CABE NA FUNCTION.
//
// Ver `src/lib/limite-de-envio.ts` para o defeito inteiro (413 da borda da
// Vercel com 48 arquivos). Em uma linha: acima de ~4 MB o corpo não chega à
// Serverless Function, então os bytes têm de ir do navegador direto ao Form do
// n8n — e para isso o navegador precisa saber DUAS coisas que só o servidor
// sabe: a URL do Form e os nomes REAIS dos campos.
//
// A DESCOBERTA CONTINUA NO SERVIDOR, e isso é o ponto. O navegador não adivinha
// nome de campo nenhum: ele recebe o par já resolvido pela mesma função que o
// encaminhamento usa (`descobrirNomesDeCampo`). Postar sob o nome errado é o
// defeito da sessão 7 cont.¹² — 200 OK na tela, nenhum arquivo recebido, zero
// token gasto —, e ele não pode voltar por uma porta nova.
//
// O QUE ISTO EXPÕE, dito na cara. Esta rota entrega a URL de produção do Form
// do n8n a quem está autenticado no portal (todas as rotas passam pelo
// `proxy.ts`, que manda para /login quem não está). Essa URL é de um formulário
// PÚBLICO por construção — é o mesmo endereço que qualquer pessoa com o link
// usa para submeter documentos, e era assim antes desta rota existir. O que
// muda é que agora ela sai também no tráfego do navegador de quem já pode
// enviar arquivos pelo portal. Não há credencial nenhuma aqui: nem chave do
// n8n, nem do Supabase, nem do provedor de IA.
export const runtime = "nodejs";

export async function GET(request: Request) {
  // SÓ O RELÓGIO. Depois que o upload direto termina, a tela pede a hora do
  // servidor de novo para fechar a janela do acompanhamento (ver
  // `upload-form.tsx`, `enviarDireto`). Aqui não se descobre campo nenhum: a
  // descoberta faz um GET ao HTML do Form, e repeti-la para ler um relógio
  // seria uma requisição à instância do n8n por motivo nenhum.
  if (new URL(request.url).searchParams.get("apenas") === "agora") {
    return NextResponse.json({ agora: new Date().toISOString() });
  }

  // A URL do Form do n8n só sai para quem pode enviar a ESTE mandato (o envio direto do navegador
  // contorna `/api/intake` e o banco não o vê). O nome vem do formulário: sem ele, não há o que conferir.
  const mandato = (new URL(request.url).searchParams.get("mandato") ?? "").trim();
  if (!mandato) return NextResponse.json({ error: "Informe o nome do mandato." }, { status: 400 });
  const permissao = await conferirEnvioAoMandato(mandato);
  if (!permissao.ok) return NextResponse.json({ error: permissao.mensagem }, { status: permissao.status });

  const url = process.env.N8N_INTAKE_FORM_URL;
  if (!url) {
    return NextResponse.json(
      {
        error:
          "Upload pelo portal não configurado: defina N8N_INTAKE_FORM_URL (URL de produção do Form do N8N) nas variáveis de ambiente da Vercel.",
      },
      { status: 503 },
    );
  }

  const campos = await descobrirNomesDeCampo(url);

  // DE ONDE VIERAM OS NOMES — e isto decide o TOM do envio, não mais se ele
  // acontece.
  //
  // `fallback` significa que a descoberta FALHOU (instância reiniciando, 429,
  // WAF bloqueando o GET, HTML inesperado) e os nomes são os padrões chutados.
  // Uma versão anterior (13/09/2026) RECUSAVA o envio direto neste estado — e
  // bloqueou o próprio lote grande que a correção existia para destravar, no
  // mesmo dia, porque a descoberta tropeçou em produção sem alternativa
  // nenhuma. O mesmo risco (nome errado — sessão 7 cont.¹²) já era aceito sem
  // bloqueio no encaminhamento, coberto pela detecção de parada do
  // acompanhamento — que cobre o direto do mesmo jeito. Ver
  // `.claude/memory/teto-da-borda-recusa-antes-do-codigo.md`.
  const porEnv = Boolean(process.env.N8N_INTAKE_FIELD_MANDATO && process.env.N8N_INTAKE_FIELD_ARQUIVOS);
  let origem: "env" | "html" | "fallback" = "fallback";
  if (porEnv) origem = "env";
  else if (campos.descoberto) origem = "html";

  return NextResponse.json({
    url,
    campos: { mandato: campos.mandato, arquivos: campos.arquivos },
    descoberto: campos.descoberto,
    origem,
    // SÓ QUANDO NÃO DESCOBRIU. Ver o comentário de `motivo` em `n8n-form.ts`:
    // é o diagnóstico que faltou em 13/09/2026, quando a descoberta falhou em
    // produção sem deixar rastro nenhum — nem para o dono, nem para quem
    // fosse investigar depois.
    ...(campos.motivo ? { motivo: campos.motivo } : {}),
    // O RELÓGIO É O DO SERVIDOR, e não é preciosismo: `agora` vira o `desde` do
    // acompanhamento (`/api/intake/status`), que o compara com `criado_em` das
    // linhas gravadas pelo pipeline. Um navegador adiantado em cinco minutos
    // filtraria para fora os documentos do próprio lote que acabou de mandar —
    // e a tela acompanharia um lote vivo contando zero para sempre.
    //
    // Ele é lido ANTES do envio de propósito: `desde` só pode errar para o lado
    // de abrir demais a janela (no máximo pega o que o próprio envio criou),
    // nunca para o de fechar.
    agora: new Date().toISOString(),
  });
}
