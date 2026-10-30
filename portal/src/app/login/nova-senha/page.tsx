import { redirect } from "next/navigation";
import { MarcaOria } from "@/components/marca-oria";
import { DetalhesTecnicos } from "@/components/detalhes-tecnicos";
import { FundoDaMarca } from "@/components/fundo-da-marca";
import { createClient } from "@/lib/supabase/server";
import { ERRO_LINK, REGRA_DA_SENHA, SENHA_MINIMA, mensagemDeRecuperacao } from "@/lib/recuperar-senha";
import { definirNovaSenha } from "./actions";

const CAMPO =
  "mt-1 w-full rounded-md border border-white/40 bg-white/10 px-3 py-2 text-sm text-vidro-texto placeholder:text-vidro-suave";

// SÓ COM SESSÃO. O proxy já manda quem não tem sessão para /login; a checagem aqui é
// a segunda trava, e leva ao pedido de novo link (não ao login) porque quem chega sem
// sessão a esta tela veio de um link — vencido ou aberto em outro navegador.
export default async function NovaSenhaPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const supabase = await createClient();
  const { data } = await supabase.auth.getUser();
  if (!data.user) redirect(`/login/recuperar?erro=${ERRO_LINK}`);

  const { error } = await searchParams;
  const falha = error ? mensagemDeRecuperacao(error) : null;

  return (
    <div className="flex min-h-screen items-center justify-center px-4 py-8 md:justify-end md:pr-[8vw]">
      <FundoDaMarca variante="login" />
      <div className="vidro-casco vidro-casco-denso w-full max-w-sm space-y-6 rounded-2xl p-6">
        <div className="flex flex-col items-center gap-2 text-center">
          <MarcaOria variante="sextante" alt="" className="marca-neon h-12 w-12" />
          <h1 className="text-lg font-semibold text-vidro-texto">Criar nova senha</h1>
          <p className="text-sm text-vidro-suave">Conta: {data.user.email}</p>
        </div>

        {falha && (
          <div role="alert" className="rounded-lg border border-risco-300/50 bg-risco-900/70 p-3 text-sm text-risco-100">
            <p>{falha.mensagem}</p>
            {error !== "senha_curta" && error !== "senhas_diferentes" && (
              <DetalhesTecnicos>
                <p>{error}</p>
              </DetalhesTecnicos>
            )}
          </div>
        )}

        <form action={definirNovaSenha} className="space-y-4">
          <div>
            <label htmlFor="senha" className="block text-sm font-medium text-vidro-texto">
              Nova senha
            </label>
            <input
              id="senha" name="senha" type="password" required minLength={SENHA_MINIMA}
              autoComplete="new-password" aria-describedby="regra-senha" className={CAMPO}
            />
            <p id="regra-senha" className="mt-1 text-xs text-vidro-suave">{REGRA_DA_SENHA}</p>
          </div>
          <div>
            <label htmlFor="confirmacao" className="block text-sm font-medium text-vidro-texto">
              Repita a nova senha
            </label>
            <input
              id="confirmacao" name="confirmacao" type="password" required minLength={SENHA_MINIMA}
              autoComplete="new-password" className={CAMPO}
            />
          </div>
          <button
            type="submit"
            className="inline-flex w-full items-center justify-center rounded-md bg-vidro-texto px-3 py-2 text-sm font-medium text-vidro-tinta transition-colors hover:bg-vidro-papel"
          >
            Salvar nova senha
          </button>
        </form>
      </div>
    </div>
  );
}
