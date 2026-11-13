"use client";

import { useCallback, useSyncExternalStore } from "react";
import { IconeLua, IconeSol } from "@/components/icones";
import {
  ATRIBUTO_TEMA, CHAVE_TEMA, CONSULTA_TEMA_ESCURO, armazem, aplicarTema, gravarPreferenciaDeTema, lerPreferenciaDeTema,
} from "@/lib/casco";

// O BOTÃO DE TEMA da barra de topo: um clique troca claro e escuro. O ícone mostra PARA ONDE o clique
// leva (Sol quando está escuro, Lua quando está claro) e a troca é o "icon swap" do transitions.dev,
// feita só em CSS (`.troca-de-icone` em globals.css, por `html[data-tema]`): o ícone certo já está na
// primeira pintura, sem esperar a hidratação.
//
// A FONTE DA VERDADE É O ATRIBUTO NO <html>, como no botão de discrição: o script do `<head>`
// (`SCRIPT_TEMA_ANTES_DA_PINTURA`) já o ligou antes da pintura, respeitando a escolha guardada e, na
// primeira visita, `prefers-color-scheme`. O botão só o LÊ (`useSyncExternalStore`). Gravar a escolha
// passa por `gravarPreferenciaDeTema`, que tem try/catch: sem armazenamento (janela privada) o tema
// vale até recarregar. O menu da conta (Claro · Escuro · Sistema) escuta o mesmo evento.
export const EVENTO_TEMA = "oria:tema";

function escuroNoHtml(): boolean {
  return document.documentElement.getAttribute(ATRIBUTO_TEMA) === "escuro";
}

export function BotaoTema() {
  const assinar = useCallback((avisar: () => void) => {
    // Outra aba trocou o tema, ou o aparelho mudou em "Sistema": o atributo é refeito aqui.
    const consulta = window.matchMedia(CONSULTA_TEMA_ESCURO);
    const refazer = () => {
      aplicarTema(document.documentElement, lerPreferenciaDeTema(armazem()), consulta.matches);
      avisar();
    };
    const aoMudarEmOutraAba = (e: StorageEvent) => {
      if (e.key === CHAVE_TEMA || e.key === null) refazer();
    };
    window.addEventListener("storage", aoMudarEmOutraAba);
    window.addEventListener(EVENTO_TEMA, avisar);
    return () => {
      window.removeEventListener("storage", aoMudarEmOutraAba);
      window.removeEventListener(EVENTO_TEMA, avisar);
    };
  }, []);
  const escuro = useSyncExternalStore(assinar, escuroNoHtml, () => false);

  const alternar = () => {
    const proximo = escuroNoHtml() ? "claro" : "escuro";
    gravarPreferenciaDeTema(armazem(), proximo);
    aplicarTema(document.documentElement, proximo, window.matchMedia(CONSULTA_TEMA_ESCURO).matches);
    window.dispatchEvent(new Event(EVENTO_TEMA));
  };

  return (
    <button
      type="button"
      onClick={alternar}
      aria-pressed={escuro}
      aria-label={escuro ? "Usar tema claro" : "Usar tema escuro"}
      title={escuro ? "Usar tema claro" : "Usar tema escuro"}
      className="flex h-9 w-9 items-center justify-center rounded-full text-tinta-500 transition-colors hover:bg-tinta-100 hover:text-tinta-900"
    >
      <span className="troca-de-icone">
        <IconeSol tamanho={16} className="icone-sol" />
        <IconeLua tamanho={16} className="icone-lua" />
      </span>
    </button>
  );
}
