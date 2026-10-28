import { hasEnvVars } from "@/lib/supabase/env";
import { MarcaOria } from "@/components/marca-oria";
import { login } from "./actions";
import { DetalhesTecnicos } from "@/components/detalhes-tecnicos";
import { mensagemDeLogin } from "@/lib/mensagem-de-login";
import { FundoDaMarca } from "@/components/fundo-da-marca";

// Campo translúcido com texto claro. O contorno é `white/40` (3,47:1 sobre o
// cartão, medido; o piso de borda de componente é 3:1); o foco vem do anel terracota
// CLARO que `.vidro-casco` define em globals.css, e não de troca de cor de borda.
const CAMPO =
  "mt-1 w-full rounded-md border border-white/40 bg-white/10 px-3 py-2 text-sm text-vidro-texto placeholder:text-vidro-suave";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;

  return (
    // A PRIMEIRA TELA DO PRODUTO, agora sobre a imagem da marca em tela cheia. O
    // véu é claro à esquerda — onde a placa "ORIA DIGITAL" acende e tem de ser
    // lida — e escuro à direita, onde mora o cartão de vidro. Em celular não há
    // "direita": o cartão sobe ao centro e cobre a placa, que é o preço de caber.
    <div className="flex min-h-screen items-center justify-center px-4 py-8 md:justify-end md:pr-[8vw]">
      <FundoDaMarca variante="login" />
      <div className="vidro-casco vidro-casco-denso w-full max-w-sm space-y-6 rounded-2xl p-6">
        <div className="flex flex-col items-center gap-2 text-center">
          {/* O SEXTANTE com o brilho do resto do portal: a marca completa tem o
              texto "ORIA PARTNERS" em tinta escura, ilegível sobre vidro escuro,
              e a arte original não se recolore. O nome da placa vem em texto. */}
          <MarcaOria
            variante="sextante"
            alt=""
            className="marca-neon h-16 w-16"
          />
          <h1 className="sr-only">Oria Digital — Tratamento de dados financeiros</h1>
          <p aria-hidden className="flex flex-col leading-tight">
            <span className="text-lg font-semibold uppercase tracking-wide text-vidro-texto">Oria</span>
            <span className="text-[11px] font-medium uppercase tracking-[0.2em] text-vidro-suave">Digital</span>
          </p>
          <p className="text-sm text-vidro-suave">Tratamento de dados financeiros</p>
        </div>

        {!hasEnvVars && (
          <div className="rounded-lg border border-alerta-300/50 bg-alerta-900/70 p-3 text-sm text-alerta-100">
            <p>O acesso ao sistema não está configurado neste ambiente. Avise o administrador.</p>
            <DetalhesTecnicos>
              <p>Variáveis de ambiente do Supabase não configuradas — ver portal/README.md.</p>
            </DetalhesTecnicos>
          </div>
        )}

        {error && (
          <div role="alert" className="rounded-lg border border-risco-300/50 bg-risco-900/70 p-3 text-sm text-risco-100">
            <p>{mensagemDeLogin(error)}</p>
            <DetalhesTecnicos>
              <p>{error}</p>
            </DetalhesTecnicos>
          </div>
        )}

        <form action={login} className="space-y-4">
          <div>
            <label htmlFor="email" className="block text-sm font-medium text-vidro-texto">
              Email
            </label>
            <input
              id="email"
              name="email"
              type="email"
              required
              autoComplete="email"
              className={CAMPO}
            />
          </div>
          <div>
            <label htmlFor="password" className="block text-sm font-medium text-vidro-texto">
              Senha
            </label>
            <input
              id="password"
              name="password"
              type="password"
              required
              autoComplete="current-password"
              className={CAMPO}
            />
          </div>
          {/* O botão é CREME com texto escuro: sobre o vidro escuro é a única
              coisa clara, e por isso a única ação. */}
          <button
            type="submit"
            className="inline-flex w-full items-center justify-center rounded-md bg-vidro-texto px-3 py-2 text-sm font-medium text-tinta-900 transition-colors hover:bg-papel"
          >
            Entrar
          </button>
        </form>

        <p className="text-center text-xs text-vidro-suave">
          O acesso é criado pelo administrador da equipe.
        </p>
        {/* O princípio do produto, dito uma vez e antes de qualquer dado. Ele
            era um rodapé fixo em TODA tela do portal (53px de altura útil a cada
            uma); aqui custa uma linha, numa tela que já tem altura sobrando. */}
        <p className="text-center text-xs text-vidro-texto">Nada aqui é fato até alguém aceitar.</p>
      </div>
    </div>
  );
}
