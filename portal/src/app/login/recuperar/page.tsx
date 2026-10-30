import Link from "next/link";
import { hasEnvVars } from "@/lib/supabase/env";
import { MarcaOria } from "@/components/marca-oria";
import { DetalhesTecnicos } from "@/components/detalhes-tecnicos";
import { FundoDaMarca } from "@/components/fundo-da-marca";
import { ERRO_LINK, RESPOSTA_DO_PEDIDO, mensagemDeRecuperacao } from "@/lib/recuperar-senha";
import { pedirRecuperacao } from "./actions";

const CAMPO =
  "mt-1 w-full rounded-md border border-white/40 bg-white/10 px-3 py-2 text-sm text-vidro-texto placeholder:text-vidro-suave";

// Mesmo casco do login. Quem chega com link vencido (`erro=link_invalido`, vindo de
// /auth/confirmar) cai aqui com a frase e o formulário para pedir outro.
export default async function RecuperarPage({
  searchParams,
}: {
  searchParams: Promise<{ enviado?: string; erro?: string; detalhe?: string }>;
}) {
  const { enviado, erro, detalhe } = await searchParams;
  const falha = erro ? mensagemDeRecuperacao(erro) : null;

  return (
    <div className="flex min-h-screen items-center justify-center px-4 py-8 md:justify-end md:pr-[8vw]">
      <FundoDaMarca variante="login" />
      <div className="vidro-casco vidro-casco-denso w-full max-w-sm space-y-6 rounded-2xl p-6">
        <div className="flex flex-col items-center gap-2 text-center">
          <MarcaOria variante="sextante" alt="" className="marca-neon h-12 w-12" />
          <h1 className="text-lg font-semibold text-vidro-texto">Recuperar senha</h1>
          <p className="text-sm text-vidro-suave">Informe o e-mail da sua conta para receber o link.</p>
        </div>

        {!hasEnvVars && (
          <div className="rounded-lg border border-alerta-300/50 bg-alerta-900/70 p-3 text-sm text-alerta-100">
            <p>O acesso ao sistema não está configurado neste ambiente. Avise o administrador.</p>
          </div>
        )}

        {enviado && (
          <div role="status" className="rounded-lg border border-ok-300/50 bg-ok-900/70 p-3 text-sm text-ok-100">
            <p>{RESPOSTA_DO_PEDIDO}</p>
          </div>
        )}

        {falha && (
          <div role="alert" className="rounded-lg border border-risco-300/50 bg-risco-900/70 p-3 text-sm text-risco-100">
            <p>{falha.mensagem}</p>
            {erro !== "email_vazio" && (
              <DetalhesTecnicos>
                <p>{erro === ERRO_LINK ? (detalhe ?? erro) : erro}</p>
              </DetalhesTecnicos>
            )}
          </div>
        )}

        <form action={pedirRecuperacao} className="space-y-4">
          <div>
            <label htmlFor="email" className="block text-sm font-medium text-vidro-texto">
              Email
            </label>
            <input id="email" name="email" type="email" required autoComplete="email" className={CAMPO} />
          </div>
          <button
            type="submit"
            className="inline-flex w-full items-center justify-center rounded-md bg-vidro-texto px-3 py-2 text-sm font-medium text-vidro-tinta transition-colors hover:bg-vidro-papel"
          >
            {erro === ERRO_LINK ? "Pedir novo link" : "Enviar link"}
          </button>
        </form>

        <p className="text-center text-sm">
          <Link href="/login" className="text-vidro-texto underline underline-offset-2 hover:text-vidro-papel">
            Voltar ao login
          </Link>
        </p>
      </div>
    </div>
  );
}
