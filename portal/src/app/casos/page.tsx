import { Suspense } from "react";
import { abaDosMandatos, filtroDaFila, paginaDaUrl } from "@/lib/painel";
import { Bloco } from "@/components/esqueleto";
import { Revelar } from "@/components/revelar";
import {
  AvisosDoPainel, CorpoDoPainel, EsqueletoDaGrade, EsqueletoDosIndicadores, IndicadoresDoPainel,
  ResumoDoPainel, saudacao,
} from "./painel-blocos";

// O PAINEL: a primeira tela do dia, e ela responde o que precisa de mim agora.
// A barra lateral navega, o painel trabalha; nada da barra se repete aqui.
//
// Quatro indicadores executivos: mandatos em andamento, pendências que travam a
// aprovação, cobertura da leitura e tempo de ingestão. Custo, linhas lidas e
// mandatos encerrados saíram do Início (decisão do dono, REDESENHO_DO_PORTAL
// item 8: custo não é argumento de venda) junto com as consultas que só os
// alimentavam. A cobertura é a única fração, e impede um volume grande de passar
// por bom resultado.
//
// A cobertura sai de `lote_execucao` (0115). Sem medição, o indicador mostra um
// traço com a causa em vez de zero: zero e "não medido" são frases diferentes.
// FUTURO: variação contra o período anterior ("−0,8 d no trimestre") exige ler
// o período anterior; hoje nada disso é lido, então nenhum delta é mostrado.
//
// STREAMING (item 2 do plano do dono). Esta página NÃO lê nada: ela devolve o casco da tela — título,
// saudação e data, que não dependem de dado nenhum — e cada bloco abaixo faz a sua consulta dentro de
// um `<Suspense>` (`painel-blocos.tsx`), chegando quando ela responde. As leituras são compartilhadas
// entre os blocos por `painel-dados.ts` (uma ida ao banco por lista, não uma por bloco).

export const dynamic = "force-dynamic";

export default async function PainelPage({
  searchParams,
}: {
  searchParams: Promise<{
    fila?: string | string[]; ver?: string | string[]; m?: string | string[]; p?: string | string[]; aviso?: string;
  }>;
}) {
  const { fila: filaBruta, ver: verBruto, m: abaBruta, p: paginaBruta, aviso } = await searchParams;
  const filtro = filtroDaFila(filaBruta);
  const verTudo = (Array.isArray(verBruto) ? verBruto[0] : verBruto) === "tudo";
  const agora = new Date();
  const dataDeHoje = agora.toLocaleDateString("pt-BR", {
    weekday: "long", day: "2-digit", month: "long", timeZone: "America/Sao_Paulo",
  });

  return (
    <div className="relative space-y-6">
      {aviso === "senha-atualizada" && (
        <p role="status" className="rounded-lg bg-ok-100 p-3 text-sm text-ok-900">
          Senha atualizada. Você já está dentro; use a nova senha no próximo acesso.
        </p>
      )}
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="font-titulo text-[30px] leading-9 font-medium tracking-[-0.03em] text-tinta-900">{saudacao(agora)}</h1>
          {/* O veredito depende das pendências; a linha chega com elas. 20 px = a linha pronta. */}
          <Revelar rotulo="Carregando o resumo…" esqueleto={<Bloco className="mt-0.5 h-5 w-72" />}>
            <ResumoDoPainel />
          </Revelar>
        </div>
        <p className="text-xs texto-marmore">{dataDeHoje}</p>
      </div>

      {/* Avisos de leitura (falha, teto de paginação). Sem esqueleto de propósito: em operação normal
          o bloco não existe, e reservar espaço para ele empurraria a tela por nada. LIMITE: o aviso
          espera `lerRecentes` (a contagem de linhas), que os indicadores NÃO esperam; então os
          indicadores podem pintar antes dele, e um aviso que chegue depois empurra a tela para baixo
          (limite conhecido; só acontece em falha ou teto de leitura, nunca em operação normal). */}
      <Suspense fallback={null}>
        <AvisosDoPainel />
      </Suspense>

      {/* Quatro indicadores executivos. A grade separa com `gap-px` sobre fundo cinza e não com
          `divide-x`, que poria borda à esquerda do primeiro item de uma segunda fileira no celular. */}
      <Revelar rotulo="Carregando os indicadores…" esqueleto={<EsqueletoDosIndicadores />}>
        <IndicadoresDoPainel />
      </Revelar>

      <Suspense fallback={<EsqueletoDaGrade />}>
        <CorpoDoPainel estado={{ fila: filtro, verTudo, aba: abaDosMandatos(abaBruta), pagina: paginaDaUrl(paginaBruta) }} />
      </Suspense>
    </div>
  );
}
