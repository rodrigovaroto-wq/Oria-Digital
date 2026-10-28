import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { logout } from "@/app/login/actions";
import { BarraLateral, type MandatoNaBarra } from "@/components/barra-lateral";
import { MarcaOria } from "@/components/marca-oria";
import { mandatosMeus } from "@/lib/membros";

// O CABEÇALHO É A ÚNICA COISA QUE APARECE EM TODAS AS TELAS, então ele é o que
// diz se o produto é sério antes de qualquer dado carregar. O que mudou:
//
//   • a marca virou marca — sigla em bloco grafite + nome, no lugar de uma
//     linha de texto que se confundia com um link qualquer;
//   • a largura foi de `max-w-5xl` (1024px) para `max-w-6xl`: as telas são
//     TABELAS de oito colunas, e 1024px obrigava a rolar na horizontal num
//     monitor de trabalho;
//   • o e-mail e o "Sair" deixaram de ter o mesmo peso do link de navegação.
export default async function CasosLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const [claimsRes, mandatosRes, adminRes] = await Promise.all([
    supabase.auth.getClaims(),
    // SÓ OS ATIVOS na barra (0114): ela responde "no que estou trabalhando", e
    // mandato fechado não é resposta para isso — ele continua na lista completa.
    supabase
      .from("caso")
      .select("id, nome, status, fechado_em")
      .is("fechado_em", null)
      .order("criado_em", { ascending: false })
      .limit(30),
    // `fn_eh_admin` falhando NÃO vira "é administrador" (0215): sem resposta, sem a seção "Todos".
    supabase.rpc("fn_eh_admin"),
  ]);
  const email = (claimsRes.data?.claims?.email as string | undefined) ?? "";
  const ehAdmin = adminRes.data === true;
  // "MEUS MANDATOS" = as linhas de caso_membro do PRÓPRIO usuário. O filtro por `usuario_id` é
  // obrigatório: o administrador lê todas as linhas (0215) e, sem ele, "meus" seria "todos". Erro de
  // leitura (banco sem a 0215) deixa `meusIds` nulo e a barra mostra o que a RLS devolver, sem filtrar.
  const usuarioId = claimsRes.data?.claims?.sub as string | undefined;
  const membroRes = usuarioId
    ? await supabase.from("caso_membro").select("caso_id").eq("usuario_id", usuarioId)
    : null;
  const meusIds = membroRes && !membroRes.error
    ? new Set(((membroRes.data as Array<{ caso_id: string }> | null) ?? []).map((l) => l.caso_id))
    : null;
  const mandatos = mandatosMeus(((mandatosRes.data as MandatoNaBarra[] | null) ?? []), meusIds)
    .map((m) => ({ id: m.id, nome: m.nome, status: m.status }));

  return (
    /* SEM `bg-tinta-50` AQUI, e não é descuido: o `body` já pinta essa mesma
       cor (ver `app/layout.tsx`). Repeti-la neste `div` criava uma camada
       OPACA em cima do plano de fundo — e era ela que engolia a ilustração do
       painel, que é um `fixed` em `-z-10`. Elemento em z negativo pinta acima
       do fundo da raiz e ABAIXO de qualquer bloco do fluxo; com a cor no `div`,
       o bloco do fluxo era a tela inteira. Tirando a cor daqui, a ilustração
       aparece nos vãos e continua coberta por tudo o que tem fundo próprio: a
       barra, o cabeçalho, o rodapé e as cartas. */
    <div className="flex min-h-screen flex-col">
      <header className="sticky top-0 z-10 border-b border-tinta-200 bg-folha/95 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-6 py-3">
          {/* NA BARRA, O SEXTANTE. A marca completa é empilhada (instrumento
              sobre ORIA sobre PARTNERS) e num cabeçalho de 57px cada palavra
              ficaria com 9px de altura — ilegível, e mal-educado com a marca.
              A lockup completa aparece no login, onde há altura para ela. */}
          <Link href="/casos" className="flex items-center gap-2.5">
            <MarcaOria variante="sextante" className="h-8 w-8" />
            <span className="flex flex-col leading-tight">
              <span className="text-sm font-semibold tracking-wide text-tinta-900">ORIA</span>
              <span className="text-[10px] uppercase tracking-[0.2em] text-tinta-500">Partners</span>
            </span>
            <span className="hidden border-l border-tinta-200 pl-2.5 text-[11px] leading-tight text-tinta-500 lg:block">
              Tratamento de
              <br />
              dados financeiros
            </span>
          </Link>

          <div className="flex items-center gap-4 text-sm">
            {/* O dial é GLOBAL, não por mandato — por isso mora fora de /casos.
                O link fica aqui porque o painel só serve para quem está usando o
                portal e precisa saber com que autonomia o pipeline rodou. */}
            <Link
              href="/autonomia"
              className="rounded-md px-2 py-1 text-tinta-600 transition-colors hover:bg-tinta-100 hover:text-tinta-900"
            >
              Autonomia
            </Link>
            {email && (
              <span className="hidden text-xs text-tinta-500 sm:inline" title={email}>
                {email}
              </span>
            )}
            <form action={logout}>
              <button type="submit" className="btn-discreto">
                Sair
              </button>
            </form>
          </div>
        </div>
      </header>

      <div className="flex flex-1">
        <BarraLateral mandatos={mandatos} ehAdmin={ehAdmin} filtrada={meusIds !== null} />
        <main className="min-w-0 flex-1 px-6 py-8">
          <div className="mx-auto w-full max-w-6xl">{children}</div>
        </main>
      </div>

      {/* O RODAPÉ EXISTE PARA DIZER UMA COISA SÓ, e ela é a mais importante do
          produto: nada aqui é fato até um humano aceitar. Quem abre o portal
          pela primeira vez precisa ler isso sem procurar. */}
      <footer className="border-t border-tinta-200 bg-folha">
        <div className="px-6 py-4 text-xs text-tinta-500">
          Os dados desta tela são extraídos dos documentos enviados e conferidos automaticamente.
          Linha marcada como pendente é sugestão a revisar. Nada é fato até alguém aceitar.
        </div>
      </footer>
    </div>
  );
}
