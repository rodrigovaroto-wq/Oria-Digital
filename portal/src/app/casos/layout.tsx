import { createClient } from "@/lib/supabase/server";
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
    // SEM COR DE FUNDO NESTE `div`: a imagem é `fixed` em `-z-10` e um bloco
    // opaco aqui a engoliria (elemento em z negativo pinta abaixo de qualquer
    // bloco do fluxo). O que tem fundo é o casco e a folha, e só eles.
    <div className="flex min-h-screen">
      <FundoDaMarca variante="app" />
      <BarraLateral mandatos={mandatos} />
      {/* Abaixo de 640px a barra inferior (fixa: 4rem de altura + o respiro de baixo) cobriria o fim da
            página: o padding inferior reserva exatamente o espaço dela. */}
      <div className="flex min-w-0 flex-1 flex-col gap-3 p-3 pb-[calc(var(--altura-barra-inferior)+0.75rem)] sm:pb-3">
        <header className="vidro-casco sticky top-3 z-10 mx-auto flex w-full max-w-[75rem] items-center justify-between gap-4 rounded-2xl px-4 py-2">
          <Trilha nomes={nomes} />
          <div className="flex shrink-0 items-center gap-1">
            <BuscaGlobal />
            <AvisosDeProcessamento />
            <BotaoDiscricao />
            <MenuConta email={email} sair={logout} />
          </div>
        </header>
        <main className="vidro-folha mx-auto w-full max-w-[75rem] flex-1 rounded-2xl px-6 py-8">
          {children}
        </main>
      </div>
    </div>
  );
}
