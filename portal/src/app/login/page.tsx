import { hasEnvVars } from "@/lib/supabase/env";
import { MarcaOria } from "@/components/marca-oria";
import { login } from "./actions";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;

  return (
    // A PRIMEIRA TELA DO PRODUTO. Ela era um formulário solto no meio do branco;
    // agora tem a mesma marca do cabeçalho e uma superfície própria — é o que
    // separa "sistema interno" de "produto" na primeira impressão.
    <div className="flex min-h-screen items-center justify-center bg-tinta-50 px-4">
      <div className="w-full max-w-sm space-y-6">
        <div className="flex flex-col items-center gap-2 text-center">
          {/* AQUI A MARCA COMPLETA: é a única tela com altura sobrando, e é a
              primeira coisa que alguém vê do produto. */}
          <MarcaOria className="h-28 w-28" />
          <h1 className="sr-only">Oria Partners — Tratamento de dados financeiros</h1>
          <p className="text-sm text-tinta-500">Tratamento de dados financeiros</p>
        </div>

        {!hasEnvVars && (
          <p className="rounded-lg border border-alerta-200 bg-alerta-50 p-3 text-sm text-alerta-800">
            Variáveis de ambiente do Supabase não configuradas — ver <code>portal/README.md</code>.
          </p>
        )}

        {error && (
          <p className="rounded-lg border border-risco-200 bg-risco-50 p-3 text-sm text-risco-800">{error}</p>
        )}

        <form action={login} className="carta space-y-4 p-6">
          <div>
            <label htmlFor="email" className="block text-sm font-medium text-tinta-700">
              Email
            </label>
            <input
              id="email"
              name="email"
              type="email"
              required
              autoComplete="email"
              className="mt-1 w-full rounded-md border border-tinta-200 px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label htmlFor="password" className="block text-sm font-medium text-tinta-700">
              Senha
            </label>
            <input
              id="password"
              name="password"
              type="password"
              required
              autoComplete="current-password"
              className="mt-1 w-full rounded-md border border-tinta-200 px-3 py-2 text-sm"
            />
          </div>
          <button type="submit" className="btn-primario w-full justify-center py-2">
            Entrar
          </button>
        </form>

        <p className="text-center text-xs text-tinta-400">
          O acesso é criado pelo administrador da equipe.
        </p>
        {/* O princípio do produto, dito uma vez e antes de qualquer dado. Ele
            era um rodapé fixo em TODA tela do portal (53px de altura útil a cada
            uma); aqui custa uma linha, numa tela que já tem altura sobrando. */}
        <p className="text-center text-xs text-tinta-500">Nada aqui é fato até alguém aceitar.</p>
      </div>
    </div>
  );
}
