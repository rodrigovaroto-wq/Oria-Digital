"use client";

import { useCallback, useSyncExternalStore } from "react";
import { IconeOlhoRiscado } from "@/components/icones";
import {
  ATRIBUTO_DISCRICAO,
  CHAVE_DISCRICAO,
  gravarDiscricao,
  lerDiscricao,
} from "@/lib/casco";

// MODO DISCRIÇÃO — o botão da barra de topo. O que ele faz de fato é ligar/desligar o atributo
// `data-discricao` no <html>; quem borra é o CSS de `globals.css` sobre `.valor-sensivel`.
//
// A FONTE DA VERDADE É O ATRIBUTO NO <html>, não um `useState`: o script inline do `<head>`
// (`SCRIPT_DISCRICAO_ANTES_DA_PINTURA`) já o ligou antes da pintura, e o botão só o LÊ
// (`useSyncExternalStore`, o mesmo padrão de `barra-lateral.tsx`). `getServerSnapshot` é
// `false`; se o modo já estava ligado, o React corrige o `aria-pressed` logo após hidratar — e o
// desfoque, que não depende do React, já estava na tela desde a primeira pintura.
//
// OUTRA ABA: o evento `storage` religa/desliga o atributo aqui também; sem isso, ligar na aba
// do projetor e esquecer outra aba aberta deixaria os números nítidos nela.
//
// ACESSIBILIDADE: `aria-pressed` com nome FIXO ("Modo discrição") — o estado é dito pelo
// atributo, não por um nome que muda. O aviso "Modo discrição ligado" é TEXTO dentro do botão
// (a cor sozinha não carrega estado — DESIGN.md). O número borrado NÃO é escondido do leitor de
// tela: quem usa leitor precisa do dado, e o modo existe contra quem olha a tela, não contra a
// tecnologia assistiva (limite documentado em globals.css e DESIGN.md).

const EVENTO = "oria:discricao";

function ligadaNoHtml(): boolean {
  return document.documentElement.hasAttribute(ATRIBUTO_DISCRICAO);
}

function aplicar(ligada: boolean) {
  if (ligada) document.documentElement.setAttribute(ATRIBUTO_DISCRICAO, "");
  else document.documentElement.removeAttribute(ATRIBUTO_DISCRICAO);
}

export function BotaoDiscricao() {
  const assinar = useCallback((avisar: () => void) => {
    const aoMudarEmOutraAba = (e: StorageEvent) => {
      if (e.key !== CHAVE_DISCRICAO && e.key !== null) return;
      aplicar(lerDiscricao(window.localStorage));
      avisar();
    };
    window.addEventListener("storage", aoMudarEmOutraAba);
    window.addEventListener(EVENTO, avisar);
    return () => {
      window.removeEventListener("storage", aoMudarEmOutraAba);
      window.removeEventListener(EVENTO, avisar);
    };
  }, []);
  const ligada = useSyncExternalStore(assinar, ligadaNoHtml, () => false);

  const alternar = () => {
    const proxima = !ligadaNoHtml();
    aplicar(proxima);
    // Sem armazenamento (janela privada) o modo vale até recarregar — e o desfoque, o que
    // importa, já foi aplicado acima.
    gravarDiscricao(window.localStorage, proxima);
    window.dispatchEvent(new Event(EVENTO));
  };

  return (
    <button
      type="button"
      onClick={alternar}
      aria-pressed={ligada}
      aria-label="Modo discrição"
      title="Modo discrição: borra os valores na tela, para usar o portal diante de outras pessoas"
      className={`flex items-center gap-2 rounded-full py-1.5 pl-2.5 pr-2.5 text-sm transition-colors hover:bg-white/10 ${
        ligada
          ? "bg-white/10 text-vidro-texto shadow-[inset_0_0_0_1px_var(--color-vidro-terracota)]"
          : "text-vidro-suave hover:text-vidro-texto"
      }`}
    >
      <IconeOlhoRiscado tamanho={16} />
      {/* `aria-label` do botão manda no nome acessível; estes textos são visuais. */}
      <span className="aviso-discricao-longo text-xs font-medium">Modo discrição ligado</span>
      <span className="aviso-discricao-curto text-xs font-medium">Discrição</span>
    </button>
  );
}
