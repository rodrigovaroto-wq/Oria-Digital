import { createClient } from "@/lib/supabase/server";
import { lerPermissoes } from "@/lib/supabase/acesso";
import { ROTULO_DO_PAPEL, textoDeRecentesVazio } from "@/lib/acesso";
import { AcessoNaoLiberado } from "@/components/acesso-nao-liberado";
import { AvisoDeAcessoNaoConferido } from "@/components/acesso-na-tela";
import { logout } from "@/app/login/actions";
import { BarraLateral, type MandatoNaBarra } from "@/components/barra-lateral";
import { AvisosDeProcessamento } from "@/components/avisos-de-processamento";
import { BotaoDiscricao } from "@/components/botao-discricao";
import { BotaoTema } from "@/components/botao-tema";
import { BuscaGlobal } from "@/components/busca-global";
import { MenuConta } from "@/components/menu-conta";
import { Trilha } from "@/components/trilha";

// A MOLDURA DE TODAS AS TELAS AUTENTICADAS: A JANELA DE VIDRO (13/11/2026, redesenho etapa 1).
//
// UM FUNDO, UMA JANELA: a tela inteira tem UM só fundo (`fundo-vidro`, globals.css: estilhaços de vidro sobre
// quase-preto no escuro, pérola no claro, feitos em CSS e SVG nossos), e o app inteiro mora numa janela de vidro
// arredondada (`janela-vidro`, 28px) com 60px de margem em 1280px ou mais e tela cheia no celular. Dentro dela:
// o trilho de ícones à esquerda (que expande), o cabeçalho (onde estou, busca em pílula, avisos, discrição, tema,
// conta) e o conteúdo, onde cada bloco é um `carta` de vidro. A janela tem a altura do conteúdo e a PÁGINA rola
// (ver o comentário em globals.css). No celular a barra inferior fixa substitui o trilho.
//
// A largura útil segue `max-w-[78rem]`: as telas são TABELAS de oito colunas. O e-mail e o "Sair" ficam no menu de
// conta; o princípio "nada é fato até alguém aceitar" mora no login, uma vez, e não num rodapé fixo em toda tela.
export default async function CasosLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  // O PAPEL, lido UMA vez por requisição (`lerPermissoes` é memoizado: layout, página e rotas filhas
  // pedem e só a primeira vai ao banco). O casco o usa para três coisas — o item "Novo mandato", o
  // texto de "Recentes" vazio e a tela única de quem ainda não tem papel (item 4 da Fase 5).
  const [perm, claimsRes, mandatosRes] = await Promise.all([
    lerPermissoes(),
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

  // SEM PAPEL = a RLS devolve VAZIO em toda lista, e "Nenhum mandato", "Nada encontrado" e "Nenhum
  // aviso" seriam falsos (regra 1). Esta tela ocupa o lugar de todas elas; a busca e o sino saem do
  // topo pelo mesmo motivo, e o casco continua para a pessoa poder sair.
  const semPapel = perm.semPapel;

  return (
    // `fundo-vidro`: o fundo único da tela inteira; a janela de vidro flutua sobre ele (globals.css).
    <div className="fundo-vidro min-h-screen">
      <div className="moldura-janela">
        <div className="janela-vidro">
          <BarraLateral
            mandatos={mandatos}
            podeCriar={perm.criarMandato.pode && !semPapel}
            motivoSemCriar={semPapel ? null : perm.criarMandato.motivo}
            vazioDa={textoDeRecentesVazio(perm.papel, Boolean(mandatosRes.error))}
            mostrarAdministracao={perm.papel === "socio" || !perm.conferido}
          />
          {/* Abaixo de 640px a barra inferior (fixa: 4rem de altura + o respiro de baixo) cobriria o fim da
                página: o padding inferior reserva exatamente o espaço dela. */}
          <div className="flex min-w-0 flex-1 flex-col pb-[calc(var(--altura-barra-inferior)+0.75rem)] sm:pb-0">
            <header className="flex w-full items-center justify-between gap-4 px-4 py-4 sm:px-8 sm:py-5">
              <Trilha nomes={nomes} />
              <div className="flex shrink-0 items-center gap-1">
                {!semPapel && <BuscaGlobal />}
                {!semPapel && <AvisosDeProcessamento />}
                <BotaoDiscricao />
                <BotaoTema />
                <MenuConta
                  email={email}
                  papel={perm.conferido ? (perm.papel ? ROTULO_DO_PAPEL[perm.papel] : "sem papel") : null}
                  sair={logout}
                />
              </div>
            </header>
            <main className="mx-auto w-full max-w-[78rem] flex-1 px-4 pb-8 pt-2 sm:px-8 sm:pb-10">
              {semPapel ? (
                <AcessoNaoLiberado email={email} />
              ) : (
                <>
                  {!perm.conferido && <div className="mb-6"><AvisoDeAcessoNaoConferido permissoes={perm} /></div>}
                  {children}
                </>
              )}
            </main>
          </div>
        </div>
      </div>
    </div>
  );
}
