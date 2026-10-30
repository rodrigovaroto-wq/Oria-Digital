import { NextResponse } from "next/server";
import { descobrirNomesDeCampo } from "@/lib/n8n-form";
import { conferirEnvioAoMandato, emitirTokenDoEnvio } from "@/lib/supabase/acesso";

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
// `proxy.ts`, que manda para /login quem não está). A URL é de um formulário
// PÚBLICO por construção — e por isso ela sozinha NÃO autoriza nada: o n8n só
// grava para quem traga o token assinado por mandato que esta rota entrega
// DEPOIS de conferir o papel (`assinatura-do-envio.ts`). Antes dele, um
// Analista alocado só no Beta pegava a URL e postava `Mandato=Alfa`. Não há
// credencial nenhuma aqui: nem chave do n8n, nem do Supabase, nem do provedor
// de IA — o token vale 30 min, para um mandato e um usuário, e o segredo que o
// assina nunca sai do servidor.
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
  // E O TOKEN SAI JUNTO, só depois do papel: o Form é público e o n8n recusa o envio sem uma
  // assinatura válida PARA ESTE MANDATO (`assinatura-do-envio.ts`). Segredo não configurado = 503
  // com a frase do "envio desligado": nunca se entrega URL sem token.
  const permissao = await conferirEnvioAoMandato(mandato);
  if (!permissao.ok) return NextResponse.json({ error: permissao.mensagem }, { status: permissao.status });
  const autorizacao = await emitirTokenDoEnvio(mandato);
  if (!autorizacao.ok) return NextResponse.json({ error: autorizacao.mensagem }, { status: autorizacao.status });

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
    campos: { mandato: campos.mandato, arquivos: campos.arquivos, token: campos.token },
    token: autorizacao.token,
    tokenExpiraEm: autorizacao.exp,
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
