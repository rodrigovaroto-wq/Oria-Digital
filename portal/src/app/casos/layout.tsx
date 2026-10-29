import { createClient } from "@/lib/supabase/server";
import { lerPermissoes } from "@/lib/supabase/acesso";
import { ROTULO_DO_PAPEL, textoDeRecentesVazio } from "@/lib/acesso";
import { AcessoNaoLiberado } from "@/components/acesso-nao-liberado";
import { AvisoDeAcessoNaoConferido } from "@/components/acesso-na-tela";
import { logout } from "@/app/login/actions";
import { BarraLateral, type MandatoNaBarra } from "@/components/barra-lateral";
import { FundoDaMarca } from "@/components/fundo-da-marca";
import { AvisosDeProcessamento } from "@/components/avisos-de-processamento";
import { BotaoDiscricao } from "@/components/botao-discricao";
import { BuscaGlobal } from "@/components/busca-global";
import { MenuConta } from "@/components/menu-conta";
import { Trilha } from "@/components/trilha";

// A MOLDURA DE TODAS AS TELAS AUTENTICADAS, no desenho "vidro" (28/10/2026).
//
// TRÊS CAMADAS, de trás para a frente:
//   1. a imagem da marca, fixa em tela cheia (`FundoDaMarca`);
//   2. o CASCO — barra lateral e barra de topo, vidro escuro suspenso a 12px das
//      bordas, que só carregam navegação e texto claro;
//   3. a FOLHA — UMA folha de vidro creme com todo o conteúdo. As 13 telas usam
//      texto escuro desenhado para superfície creme; a folha mantém cada número
//      sobre >= 92% de creme (o mesmo contraste de antes) e deixa a imagem
//      aparecer ao redor e só de leve por baixo. O cabeçalho do mandato e as
//      abas moram dentro dela, sem mudança.
//
// A barra de 57px de largura total SAIU: a marca foi para o topo da barra lateral
// e a trilha e a conta para uma barra flutuante. Com isso não há mais deslocamento
// de 57px a calcular — a barra lateral é `sticky top-3`, a de topo também.
//
// A largura útil continua a de antes: `max-w-6xl` (1152px) de conteúdo + 2×24px
// de respiro da folha = 75rem de coluna. As telas são TABELAS de oito colunas, e
// 1024px obrigava a rolar na horizontal num monitor de trabalho. O e-mail e o
// "Sair" ficam no menu de conta; o princípio "nada é fato até alguém aceitar"
// mora no login, uma vez, e não num rodapé fixo em toda tela.
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
    // SEM COR DE FUNDO NESTE `div`: a imagem é `fixed` em `-z-10` e um bloco
    // opaco aqui a engoliria (elemento em z negativo pinta abaixo de qualquer
    // bloco do fluxo). O que tem fundo é o casco e a folha, e só eles.
    <div className="flex min-h-screen">
      <FundoDaMarca variante="app" />
      <BarraLateral
        mandatos={mandatos}
        podeCriar={perm.criarMandato.pode && !semPapel}
        motivoSemCriar={semPapel ? null : perm.criarMandato.motivo}
        vazioDa={textoDeRecentesVazio(perm.papel, Boolean(mandatosRes.error))}
        mostrarAdministracao={perm.papel === "socio" || !perm.conferido}
      />
      {/* Abaixo de 640px a barra inferior (fixa: 4rem de altura + o respiro de baixo) cobriria o fim da
            página: o padding inferior reserva exatamente o espaço dela. */}
      <div className="flex min-w-0 flex-1 flex-col gap-3 p-3 pb-[calc(var(--altura-barra-inferior)+0.75rem)] sm:pb-3">
        <header className="vidro-casco sticky top-3 z-10 mx-auto flex w-full max-w-[75rem] items-center justify-between gap-4 rounded-2xl px-4 py-2">
          <Trilha nomes={nomes} />
          <div className="flex shrink-0 items-center gap-1">
            {!semPapel && <BuscaGlobal />}
            {!semPapel && <AvisosDeProcessamento />}
            <BotaoDiscricao />
            <MenuConta
              email={email}
              papel={perm.conferido ? (perm.papel ? ROTULO_DO_PAPEL[perm.papel] : "sem papel") : null}
              sair={logout}
            />
          </div>
        </header>
        <main className="vidro-folha mx-auto w-full max-w-[75rem] flex-1 rounded-2xl px-6 py-8">
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
  );
}
