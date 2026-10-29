import { NextResponse } from "next/server";
import { conferirEnvioAoMandato } from "@/lib/supabase/acesso";
import { descobrirNomesDeCampo } from "@/lib/n8n-form";
import { TETO_DA_FUNCTION_BYTES, TETO_DO_PROXY_BYTES, formatarBytes } from "@/lib/limite-de-envio";

// ESTA ROTA SÓ EXISTE PARA O LOTE QUE CABE NELA.
//
// A Serverless Function da Vercel recusa corpo acima de ~4,5 MB NA BORDA, antes
// de invocar este arquivo: nenhuma mensagem daqui é capaz de aparecer nesse
// caso (foi o 413 de 13/09/2026, com 48 arquivos e ~50 MB). O lote grande vai
// direto do navegador para o Form do n8n — ver `src/lib/limite-de-envio.ts` e
// `api/intake/destino/route.ts`.
//
// O caminho por aqui CONTINUA sendo o normal para o lote pequeno, que é a
// imensa maioria dos envios, e continua sendo o único que devolve o status REAL
// do n8n e as mensagens em português abaixo. Trocar os dois por um só custaria
// exatamente isso.

// Recebe o upload do portal (multipart) e ENCAMINHA para a URL do Form do N8N
// — servidor-a-servidor (sem CORS). O pipeline (classificação/extração/
// reconciliação) continua 100% no N8N: o portal é só um front-end de intake
// mais amigável, submetendo ao MESMO endpoint que o formulário público do N8N.
// Assim, reenviar no mesmo "mandato" (nome do caso) acumula no mesmo caso —
// fn_upsert_caso reusa por nome (Supabase/migrations/0006).
//
// Precisa do runtime Node (streams/FormData de arquivo), não Edge.
export const runtime = "nodejs";

// Nomes de campo: se as envs vierem preenchidas, são um override explícito
// (usadas direto). Sem elas, o nome é DESCOBERTO lendo o HTML do próprio Form
// do N8N (ver n8n-form.ts) — não adivinhado. Achado em produção (sessão 7
// cont.¹²): o portal enviava um POST com os rótulos visíveis ("Mandato (nome
// do caso)"/"Arquivos") como nome de campo, mas o N8N pode gerar um atributo
// `name` INTERNO diferente do rótulo. O webhook aceitava o POST (200 OK — "o
// upload deu certo" no portal) mas o workflow não recebia arquivo nenhum sob
// o nome esperado, o node `Listar Arquivos` lançava erro e a execução morria
// ANTES de qualquer chamada de IA — daí "sucesso na tela, 0 tokens gastos".
// A descoberta mora em `src/lib/n8n-form.ts` desde que passou a ter dois
// chamadores (este encaminhamento e a rota `destino`, que serve o envio
// direto). Uma segunda cópia dela é como o portal voltaria a postar sob um nome
// que o workflow não lê.

export async function POST(request: Request) {
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

  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return NextResponse.json({ error: "Requisição inválida (multipart esperado)." }, { status: 400 });
  }

  const mandato = String(form.get("mandato") ?? "").trim();
  const arquivos = form
    .getAll("arquivos")
    .filter((f): f is File => f instanceof File && f.size > 0);

  if (!mandato) {
    return NextResponse.json({ error: "Informe o nome do mandato." }, { status: 400 });
  }
  if (arquivos.length === 0) {
    return NextResponse.json({ error: "Selecione ao menos um arquivo." }, { status: 400 });
  }

  // O PAPEL, ANTES DE ENCAMINHAR. O n8n grava com a conexão de serviço e acha o mandato pelo nome:
  // nenhuma RLS o barra, então a recusa tem de ser aqui (ver `decidirEnvioAoMandato`).
  const permissao = await conferirEnvioAoMandato(mandato);
  if (!permissao.ok) return NextResponse.json({ error: permissao.mensagem }, { status: permissao.status });

  // O LOTE GRANDE QUE CHEGOU AQUI MESMO ASSIM.
  //
  // Na Vercel esta verificação é inalcançável — a borda já recusou o corpo com
  // 413 antes de invocar a função —, e ela existe exatamente por isso: fora da
  // Vercel (`next dev`, instância própria) o mesmo lote PASSA, e passaria a
  // depender do teto de quem estiver na frente. Um limite que só vale num
  // ambiente é um limite que ninguém consegue testar.
  //
  // Quando ela dispara, a causa é uma só: a tela que montou o envio é de uma
  // versão anterior a esta correção (aba aberta desde antes do deploy). Por isso
  // a mensagem manda recarregar, e não "mandar em levas" — levas foi o conselho
  // que esta correção aposentou (ver `limite-de-envio.ts`).
  const recebidoBytes = arquivos.reduce((s, a) => s + a.size, 0);
  if (recebidoBytes >= TETO_DO_PROXY_BYTES) {
    return NextResponse.json(
      {
        error:
          `Este lote tem ${formatarBytes(recebidoBytes)} e não passa pelo encaminhamento do portal, `
          + `que é limitado a ${formatarBytes(TETO_DA_FUNCTION_BYTES)} por requisição pela hospedagem. `
          + "Recarregue a página e envie de novo: a tela atualizada manda lotes grandes direto, sem esse limite.",
      },
      { status: 413 },
    );
  }

  const campos = await descobrirNomesDeCampo(url);

  // Monta o multipart no formato do Form do N8N e encaminha.
  const fwd = new FormData();
  fwd.append(campos.mandato, mandato);
  for (const arquivo of arquivos) {
    fwd.append(campos.arquivos, arquivo, arquivo.name);
  }

  let resp: Response;
  try {
    resp = await fetch(url, { method: "POST", body: fwd });
  } catch (e) {
    return NextResponse.json(
      { error: `Não foi possível contatar o N8N: ${(e as Error).message}` },
      { status: 502 },
    );
  }

  if (!resp.ok) {
    const detalhe = await resp.text().catch(() => "");
    return NextResponse.json(
      {
        error: `O N8N recusou a submissão (HTTP ${resp.status}). Confira a URL do Form e os nomes dos campos ` +
          `(usados: mandato="${campos.mandato}", arquivos="${campos.arquivos}"). ${detalhe.slice(0, 300)}`,
      },
      { status: 502 },
    );
  }

  return NextResponse.json({
    ok: true,
    mandato,
    arquivos: arquivos.length,
    desde: new Date().toISOString(),
  });
}
