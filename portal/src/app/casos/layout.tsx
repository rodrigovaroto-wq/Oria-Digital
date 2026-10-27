import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { logout } from "@/app/login/actions";
import { BarraLateral, type MandatoNaBarra } from "@/components/barra-lateral";
import { MarcaOria } from "@/components/marca-oria";
import { MenuConta } from "@/components/menu-conta";
import { Trilha } from "@/components/trilha";

// O CABEÇALHO É A ÚNICA COISA QUE APARECE EM TODAS AS TELAS, então ele é o que
// diz se o produto é sério antes de qualquer dado carregar. O que mudou:
//
//   • a marca virou marca — sigla em bloco grafite + nome, no lugar de uma
//     linha de texto que se confundia com um link qualquer;
//   • a largura foi de `max-w-5xl` (1024px) para `max-w-6xl`: as telas são
//     TABELAS de oito colunas, e 1024px obrigava a rolar na horizontal num
//     monitor de trabalho;
//   • o e-mail e o "Sair" foram para um menu de conta (iniciais no cabeçalho), e
//     o link "Autonomia" foi para a barra lateral, em "Administração";
//   • entrou a trilha (onde estou), e o rodapé fixo saiu: o princípio "nada é
//     fato até alguém aceitar" mora na tela de login, uma vez, e não em toda
//     tela como um bloco de 53px que tirava altura útil de tabelas de oito colunas.
export default async function CasosLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const [claimsRes, mandatosRes] = await Promise.all([
    supabase.auth.getClaims(),
    // SÓ OS ATIVOS na barra (0114): ela responde "no que estou trabalhando", e
    // mandato fechado não é resposta para isso — ele continua na lista completa.
    supabase
      .from("caso")
      .select("id, nome, status, fechado_em")
      .is("fechado_em", null)
      .order("criado_em", { ascending: false })
      .limit(30),
  ]);
  const email = (claimsRes.data?.claims?.email as string | undefined) ?? "";
  const mandatos = ((mandatosRes.data as MandatoNaBarra[] | null) ?? []).map((m) => ({
    id: m.id, nome: m.nome, status: m.status,
  }));

  const nomes = Object.fromEntries(mandatos.map((m) => [m.id, m.nome]));

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
          <Link href="/casos" className="flex shrink-0 items-center gap-2.5">
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

          <Trilha nomes={nomes} />

          <MenuConta email={email} sair={logout} />
        </div>
      </header>

      <div className="flex flex-1">
        <BarraLateral mandatos={mandatos} />
        <main className="min-w-0 flex-1 px-6 py-8">
          <div className="mx-auto w-full max-w-6xl">{children}</div>
        </main>
      </div>
    </div>
  );
}
