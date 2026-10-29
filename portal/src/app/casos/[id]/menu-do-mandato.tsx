"use client";

import Link from "next/link";
import { useEffect, useId, useRef, useState } from "react";
import { FecharMandato } from "@/components/fechar-mandato";
import { ExcluirMandato } from "@/components/excluir-mandato";
import { IconeMais3Pontos } from "@/components/icones";
import type { Liberacao } from "@/lib/acesso";

// O MENU "⋯" DO MANDATO: fechar/reabrir e excluir saem do corpo da tela. Eram
// botões soltos ao lado das ações de trabalho (e o fechar só existia na lista
// completa); agora ficam num menu, achável por quem procura e não esbarrável
// por quem não.
//
// POR QUE OS DOIS COMPONENTES FICAM MONTADOS COM O MENU FECHADO. Cada um abre o
// PRÓPRIO diálogo a partir de estado local — se o painel do menu fosse
// desmontado ao clicar no item, o diálogo morreria junto com o botão que o
// abriu. Então o painel só é ESCONDIDO (`hidden`), e o clique-fora ignora
// cliques dentro de um diálogo (`role=dialog`), que é renderizado dentro da
// raiz e não pode contar como "fora".
export function MenuDoMandato({
  casoId,
  nome,
  fechado,
  reservado,
}: Readonly<{
  casoId: string;
  nome: string;
  fechado: boolean;
  /** Fechar, reabrir e excluir são de Sócio (gatilho da 0216). Sem a liberação, o motivo toma o lugar dos botões. */
  reservado: Liberacao;
}>) {
  const [aberto, setAberto] = useState(false);
  const raiz = useRef<HTMLDivElement>(null);
  const idMenu = useId();

  // Mesmo padrão do menu de conta: os ouvintes só existem com o menu aberto, e
  // Esc devolve o foco ao botão (senão o teclado cai no <body>). O Esc dentro de
  // um diálogo aberto fecha só o diálogo (o `ExcluirMandato` tem o próprio
  // ouvinte), por isso aqui só reage se o foco não está num diálogo.
  useEffect(() => {
    if (!aberto) return;
    const aoTeclar = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      // Os diálogos de Fechar/Excluir agora vão para o <body> (portal): a busca é
      // no documento, não dentro do menu, senão o Esc fecharia os dois de uma vez.
      if (document.querySelector('[role="dialog"]')) return;
      setAberto(false);
      raiz.current?.querySelector<HTMLButtonElement>("button[aria-haspopup]")?.focus();
    };
    const aoClicar = (e: MouseEvent) => {
      const alvo = e.target as Node;
      if (raiz.current?.contains(alvo)) return;
      if ((alvo as Element).closest?.('[role="dialog"]')) return;
      setAberto(false);
    };
    document.addEventListener("keydown", aoTeclar);
    document.addEventListener("mousedown", aoClicar);
    return () => {
      document.removeEventListener("keydown", aoTeclar);
      document.removeEventListener("mousedown", aoClicar);
    };
  }, [aberto]);

  return (
    <div ref={raiz} className="relative">
      <button
        type="button"
        onClick={() => setAberto((v) => !v)}
        aria-expanded={aberto}
        aria-haspopup="true"
        aria-controls={idMenu}
        aria-label="Mais ações do mandato"
        title="Mais ações"
        className="flex h-9 w-9 items-center justify-center rounded-md border border-tinta-200 bg-folha text-tinta-600 transition-colors hover:bg-tinta-50 hover:text-tinta-900"
      >
        <IconeMais3Pontos />
      </button>
      <div
        id={idMenu}
        hidden={!aberto}
        className="absolute right-0 top-full z-20 mt-2 flex w-56 flex-col items-stretch gap-2 rounded-lg border border-tinta-200 bg-folha p-3 shadow-lg"
      >
        <Link
          href={`/casos/${casoId}/historico`}
          onClick={() => setAberto(false)}
          className="rounded-md px-3 py-2 text-sm text-tinta-800 hover:bg-tinta-50"
        >
          Histórico
        </Link>
        {reservado.pode ? (
          <>
            <FecharMandato casoId={casoId} nome={nome} fechado={fechado} />
            <ExcluirMandato casoId={casoId} nome={nome} />
          </>
        ) : (
          // O motivo À VISTA no lugar dos botões: quem abre o menu procurando "Fechar" lê por que não há.
          <p className="px-3 py-2 text-xs leading-snug text-tinta-600">{reservado.motivo}</p>
        )}
      </div>
    </div>
  );
}
