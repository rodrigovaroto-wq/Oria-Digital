import { hasEnvVars } from "@/lib/supabase/env";
import { MarcaOria } from "@/components/marca-oria";
import { login } from "./actions";
import { DetalhesTecnicos } from "@/components/detalhes-tecnicos";
import { mensagemDeLogin } from "@/lib/mensagem-de-login";
import Link from "next/link";
import s from "./login.module.css";

// LOGIN · direção A "Cobalto noturno". Só a casca visual mudou: `login`, os `name`
// dos campos, a mensagem de erro e os links são os de antes.
//
// A maquete trazia uma linha de números (linhas lidas, cobertura, minutos) e um
// "Manter conectado". Nenhum dos dois entra: sem sessão não há como ler esses números
// do banco (número fixo seria dado fabricado) e a caixa não teria comportamento.
export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;

  return (
    <div className={s.tela}>
      <div className={s.luz} aria-hidden />
      <div className={s.grade} aria-hidden />
      <div className={s.esq}>
        <div className={s.marca}>
          {/* O sextante com o brilho do resto do portal; o nome vem em texto. */}
          <MarcaOria variante="sextante" alt="" className="marca-neon h-8 w-8" />
          Oria&nbsp;Digital
        </div>
        <div className={s.centro}>
          <h1 className={`${s.titulo} ${s["linha-reveal"]}`}>
            O detalhe que muda a tese <em>aparece primeiro</em>.
          </h1>
          <p className={`${s.sub} ${s["linha-reveal"]} ${s["linha-reveal-2"]}`}>
            Contingências, partes relacionadas e eventos subsequentes declarados em nota são lidos e destacados antes da primeira reunião.
          </p>
        </div>
      </div>

      <div className={s.dir}>
        <div className={`${s.cartao} ${s["entra-cartao"]}`}>
          <h2>Entrar</h2>
          <p className={s.nota}>Acesso criado pelo administrador da equipe.</p>

          {!hasEnvVars && (
            <div className={`${s.aviso} ${s.config}`}>
              <p>O acesso ao sistema não está configurado neste ambiente. Avise o administrador.</p>
              <DetalhesTecnicos>
                <p>Variáveis de ambiente do Supabase não configuradas — ver portal/README.md.</p>
              </DetalhesTecnicos>
            </div>
          )}

          {error && (
            <div role="alert" className={`${s.aviso} ${s.alerta}`}>
              <p>{mensagemDeLogin(error)}</p>
              <DetalhesTecnicos>
                <p>{error}</p>
              </DetalhesTecnicos>
            </div>
          )}

          <form action={login}>
            <label htmlFor="email" className={s.rotulo} style={{ marginTop: 0 }}>
              E-mail
            </label>
            <input id="email" name="email" type="email" required autoComplete="email" className={s.campo} />
            <label htmlFor="password" className={s.rotulo}>
              Senha
            </label>
            <input
              id="password"
              name="password"
              type="password"
              required
              autoComplete="current-password"
              className={s.campo}
            />
            <div className={s.linha}>
              <Link href="/login/recuperar" className={s.link}>
                Esqueci a senha
              </Link>
            </div>
            <button type="submit" className={s.botao}>
              Entrar no portal
              <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                <path d="M3 8h10M9 4l4 4-4 4" />
              </svg>
            </button>
          </form>

          <p className={s.rodape}>Nada aqui é fato até alguém aceitar.</p>
        </div>
      </div>
    </div>
  );
}
