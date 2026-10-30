"use client";

import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  IconeBusca,
  IconeInicio,
  IconeMais,
  IconeMais3Pontos,
  IconeMandatos,
  IconeQualidade,
} from "@/components/icones";
import { CASO_STATUS_COLOR, CASO_STATUS_LABEL } from "@/lib/status";
import { ariaCurrentDoLink, destinoAtivo, EVENTO_ABRIR_BUSCA, idDoCaso, type DestinoDaBarra } from "@/lib/casco";
import type { MandatoNaBarra } from "@/components/barra-lateral";

// A BARRA INFERIOR DO CELULAR (< 640px) — a cena de uso 3 do PRODUCT.md ("consulta rápida no
// celular, entre reuniões"). Abaixo de 640px a barra lateral some (nem o trilho de 56px: ele
// tomava 15% de uma tela de 375px) e estes cinco destinos, ao alcance do polegar, a substituem:
// Início · Mandatos · Busca · Novo · Mais.
//
// "MAIS" É O MENU MÓVEL: leva o que a barra de baixo não comporta — os RECENTES (que na barra
// lateral ocupam a seção do meio) e a Administração. Abre numa folha por PORTAL no <body>, pelo
// mesmo motivo de `busca-global.tsx`: a barra tem `backdrop-filter` (vidro), que vira o bloco de
// contenção de qualquer descendente `fixed`, e a folha ficaria presa dentro dos 56px dela.
//
// VIDRO E CONTRASTE: é o casco de sempre (`.vidro-casco`, DESIGN.md). Todo rótulo usa
// `vidro-texto` (#ece8df, 9,6:1 no pior caso medido) — e não `vidro-suave` (4,71:1): texto de
// 11px é onde 4,5:1 não sobra. O destino ativo leva barra de 2px em terracota claro NO TOPO, fundo
// +10% e `aria-current`: a cor sozinha não diz onde se está.
//
// SAFE AREA: `bottom: max(0.75rem, env(safe-area-inset-bottom))`. O `env()` só vale com
// `viewport-fit=cover` (que o portal NÃO declara) ou em PWA instalado; no Safari comum o próprio
// navegador já mantém a página acima do indicador de início e o `env()` dá 0 — o `max` cai nos
// 12px de respiro. Não foi vista em aparelho real (ver relatório da fase).

const ITEM =
  "relative flex min-h-14 flex-1 flex-col items-center justify-center gap-0.5 rounded-xl px-1 text-[11px] font-medium text-vidro-texto transition-colors hover:bg-white/[0.07]";
const ATIVO = "bg-white/10 font-semibold shadow-[inset_0_2px_0_var(--color-vidro-terracota)]";

function Item({
  destino, ativo, caminho, rotulo, children, href, aoClicar, aberto,
}: Readonly<{
  destino: DestinoDaBarra | "busca";
  ativo: DestinoDaBarra | null;
  caminho: string;
  rotulo: string;
  children: React.ReactNode;
  href?: string;
  aoClicar?: (e: React.MouseEvent<HTMLButtonElement>) => void;
  aberto?: boolean;
}>) {
  const marcado = destino !== "busca" && ativo === destino;
  const classe = `${ITEM} ${marcado ? ATIVO : ""}`;
  if (href) {
    return (
      <Link href={href} aria-current={ariaCurrentDoLink(href, caminho, marcado)} className={classe}>
        {children}
        <span>{rotulo}</span>
      </Link>
    );
  }
  return (
    <button
      type="button"
      onClick={aoClicar}
      aria-haspopup="dialog"
      aria-expanded={aberto}
      className={classe}
    >
      {children}
      <span>{rotulo}</span>
    </button>
  );
}

export function BarraInferior({ recentes, podeCriar, vazioDa, mostrarAdministracao }: Readonly<{ recentes: MandatoNaBarra[]; podeCriar: boolean; vazioDa: string; mostrarAdministracao: boolean }>) {
  const caminho = usePathname();
  const ativo = destinoAtivo(caminho);
  const idAtual = idDoCaso(caminho);
  // A folha está aberta "neste caminho": navegar a fecha SEM efeito nem setState em efeito — o
  // valor guardado deixa de casar com o caminho novo, e `aberta` volta a ser falso.
  const [abertaEm, setAbertaEm] = useState<string | null>(null);
  const aberta = abertaEm === caminho;
  const gatilho = useRef<HTMLButtonElement>(null);
  const folha = useRef<HTMLDivElement>(null);

  const fechar = () => {
    setAbertaEm(null);
    gatilho.current?.focus();
  };

  // Clicar num link da folha a fecha: se o destino é a página em que já se está, o caminho não
  // muda e a folha ficaria aberta sobre a tela que o toque pretendia mostrar. Sem devolver o foco ao
  // gatilho (a navegação leva o foco).
  const dispensar = () => setAbertaEm(null);

  // Esc fecha; Tab fica preso na folha; o foco entra nela ao abrir.
  useEffect(() => {
    if (!aberta) return;
    const focaveis = () =>
      Array.from(folha.current?.querySelectorAll<HTMLElement>("a[href], button:not([disabled])") ?? []);
    focaveis()[0]?.focus();
    // Rolagem do <body> travada com a folha aberta (como `painel-documento.tsx`): o toque no fundo
    // escuro rolava a página por baixo.
    const rolagem = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const aoTeclar = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault();
        // Só a folha fecha: sem isto o mesmo Esc chegava a outros ouvintes do document (a busca, um
        // diálogo por baixo) e fechava duas camadas de uma vez.
        e.stopImmediatePropagation();
        setAbertaEm(null);
        gatilho.current?.focus();
        return;
      }
      if (e.key !== "Tab") return;
      const foc = focaveis();
      if (foc.length === 0) return;
      const i = foc.indexOf(document.activeElement as HTMLElement);
      const prox = e.shiftKey ? (i <= 0 ? foc.length - 1 : i - 1) : i === foc.length - 1 ? 0 : i + 1;
      e.preventDefault();
      foc[prox].focus();
    };
    document.addEventListener("keydown", aoTeclar);
    return () => {
      document.removeEventListener("keydown", aoTeclar);
      document.body.style.overflow = rolagem;
    };
  }, [aberta]);

  return (
    <>
      <nav
        aria-label="Navegação principal"
        className="vidro-casco fixed inset-x-3 bottom-[max(0.75rem,env(safe-area-inset-bottom))] z-30 flex items-stretch gap-1 rounded-2xl p-1 sm:hidden"
      >
        <Item destino="inicio" ativo={ativo} caminho={caminho} rotulo="Início" href="/casos"><IconeInicio tamanho={20} /></Item>
        <Item destino="mandatos" ativo={ativo} caminho={caminho} rotulo="Mandatos" href="/casos/todos"><IconeMandatos tamanho={20} /></Item>
        <Item
          destino="busca" ativo={ativo} caminho={caminho} rotulo="Busca"
          aoClicar={(e) => window.dispatchEvent(new CustomEvent(EVENTO_ABRIR_BUSCA, { detail: { origem: e.currentTarget } }))}
        >
          <IconeBusca tamanho={20} />
        </Item>
        {podeCriar && (
          <Item destino="novo" ativo={ativo} caminho={caminho} rotulo="Novo" href="/casos/novo"><IconeMais tamanho={20} /></Item>
        )}
        <button
          ref={gatilho}
          type="button"
          onClick={() => setAbertaEm(aberta ? null : caminho)}
          aria-haspopup="dialog"
          aria-expanded={aberta}
          className={`${ITEM} ${ativo === "mais" ? ATIVO : ""}`}
        >
          <IconeMais3Pontos tamanho={20} />
          <span>Mais</span>
        </button>
      </nav>

      {aberta && createPortal(
        <div className="fixed inset-0 z-50 flex flex-col justify-end bg-fundo-reserva/60 sm:hidden">
          <button
            type="button" aria-label="Fechar" tabIndex={-1} onClick={fechar}
            className="absolute inset-0 h-full w-full cursor-default"
          />
          <div
            ref={folha}
            role="dialog"
            aria-modal="true"
            aria-label="Mais"
            className="vidro-casco vidro-casco-denso relative m-3 mb-[max(0.75rem,env(safe-area-inset-bottom))] max-h-[70dvh] overflow-y-auto rounded-2xl p-3"
          >
            <p className="px-3 pb-1 text-[11px] font-semibold uppercase tracking-wider text-vidro-suave">Recentes</p>
            {recentes.length === 0 ? (
              <p className="px-3 py-2 text-sm text-vidro-suave">{vazioDa}</p>
            ) : (
              <ul className="space-y-0.5">
                {recentes.map((m) => (
                  <li key={m.id}>
                    <Link
                      href={`/casos/${m.id}`}
                      onClick={dispensar}
                      aria-current={ariaCurrentDoLink(`/casos/${m.id}`, caminho, idAtual === m.id.toLowerCase())}
                      className={`flex min-h-11 items-center gap-2 rounded-md px-3 text-sm text-vidro-texto hover:bg-white/[0.07] ${
                        idAtual === m.id.toLowerCase() ? "bg-white/10 font-medium" : ""
                      }`}
                    >
                      <span aria-hidden className={`h-1.5 w-1.5 shrink-0 rounded-full ${CASO_STATUS_COLOR[m.status].split(" ")[0]}`} />
                      <span className="truncate">{m.nome}</span>
                      <span className="ml-auto shrink-0 text-xs text-vidro-suave">{CASO_STATUS_LABEL[m.status]}</span>
                    </Link>
                  </li>
                ))}
              </ul>
            )}
            {mostrarAdministracao && (
            <div className="mt-2 border-t border-white/10 pt-2">
              <Link
                href="/administracao"
                onClick={dispensar}
                aria-current={ariaCurrentDoLink("/administracao", caminho, ativo === "mais")}
                className={`flex min-h-11 items-center gap-2.5 rounded-md px-3 text-sm font-medium text-vidro-texto hover:bg-white/[0.07] ${
                  ativo === "mais" ? "bg-white/10" : ""
                }`}
              >
                <IconeQualidade />
                Qualidade e custos
              </Link>
            </div>
            )}
          </div>
        </div>,
        document.body,
      )}
    </>
  );
}
