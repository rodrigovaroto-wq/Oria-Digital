"use client";

import { createPortal } from "react-dom";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useSyncExternalStore } from "react";
import { useOrdemDosDocumentos } from "@/components/ordem-dos-documentos";
import { vizinhosNaOrdem } from "@/lib/vizinhos-na-ordem";

// O PAINEL LATERAL DO DOCUMENTO sobre a lista (rota interceptada `@painel/(.)[docId]`).
//
// VAI PARA O <body> (portal), como `excluir-mandato.tsx` e `busca-global.tsx`: o conteúdo mora
// numa `.vidro-folha` e `fixed` dentro de um ancestral com filtro/transform deixa de ser relativo
// à janela. Sem `docId` (o `loading.tsx` da rota) o cabeçalho mostra só o fechar.
//
// "ABRIR EM PÁGINA INTEIRA" É <a>, NÃO <Link>: um Link seria interceptado de novo e reabriria o
// painel; o <a> faz a navegação de documento e entrega a página inteira de sempre.
//
// FOCO: entra no painel ao abrir; ao fechar volta à linha do documento (a que estiver aberta —
// prev/next trocam o documento e o foco volta à linha do último). O painel remonta a cada
// documento, então o retorno do foco espera um tick: se outro painel montou no lugar, é troca, não
// fechamento.
const FOCAVEIS = 'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

export function PainelDocumento({
  casoId, docId, children,
}: Readonly<{ casoId: string; docId?: string; children: React.ReactNode }>) {
  const router = useRouter();
  const painel = useRef<HTMLDivElement>(null);
  // `document` só existe no cliente; o painel nunca é a primeira pintura (F5 mostra a página
  // inteira), mas o portal espera a hidratação mesmo assim.
  const montado = useSyncExternalStore(() => () => {}, () => true, () => false);
  const ordem = useOrdemDosDocumentos();
  const viz = docId && ordem ? vizinhosNaOrdem(ordem, docId) : null;

  const fechar = () => router.back();

  useEffect(() => {
    if (!montado) return;
    painel.current?.focus();
    const rolagem = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = rolagem;
      if (!docId) return;
      setTimeout(() => {
        if (document.querySelector("[data-painel-documento]")) return;
        document.querySelector<HTMLElement>(`[data-doc-row="${docId}"]`)?.focus();
      }, 0);
    };
  }, [montado, docId]);

  useEffect(() => {
    if (!montado) return;
    const aoTeclar = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        const alvo = e.target as HTMLElement;
        // Esc num campo com texto digitado só sai do campo: fechar perderia a transcrição/motivo.
        if (/^(INPUT|TEXTAREA)$/.test(alvo.tagName) && (alvo as HTMLInputElement).value) {
          alvo.blur();
          return;
        }
        e.preventDefault();
        router.back();
      } else if (e.key === "Tab" && painel.current) {
        const foc = Array.from(painel.current.querySelectorAll<HTMLElement>(FOCAVEIS));
        if (foc.length === 0) return;
        const i = foc.indexOf(document.activeElement as HTMLElement);
        const prox = e.shiftKey ? (i <= 0 ? foc.length - 1 : i - 1) : (i === foc.length - 1 ? 0 : i + 1);
        e.preventDefault();
        foc[prox].focus();
      }
    };
    document.addEventListener("keydown", aoTeclar);
    return () => document.removeEventListener("keydown", aoTeclar);
  }, [montado, router]);

  if (!montado) return null;

  const base = `/casos/${casoId}/documentos`;
  const botao = "rounded border border-tinta-200 bg-folha px-2.5 py-1 text-xs font-medium text-tinta-700 hover:bg-tinta-50";
  const inativo = "rounded border border-tinta-100 px-2.5 py-1 text-xs font-medium text-tinta-300";

  return createPortal(
    <div
      className="fixed inset-0 z-50 flex justify-end bg-tinta-900/40"
      onClick={(e) => { if (e.target === e.currentTarget) fechar(); }}
    >
      <div
        ref={painel}
        tabIndex={-1}
        role="dialog"
        aria-modal="true"
        aria-labelledby="titulo-documento"
        data-painel-documento=""
        className="flex h-full w-[min(720px,100%)] flex-col border-l border-tinta-200 bg-folha shadow-xl focus:outline-none"
      >
        <div className="flex flex-wrap items-center gap-2 border-b border-tinta-200 bg-tinta-50 px-4 py-2.5">
          {docId && viz && (
            <>
              {viz.anterior
                ? <Link href={`${base}/${viz.anterior}`} replace scroll={false} prefetch={false} className={botao}>← anterior</Link>
                : <span className={inativo} title="É o primeiro da lista filtrada">← anterior</span>}
              <span className="text-xs tabular-nums text-tinta-600">{viz.posicao} de {viz.total}</span>
              {viz.proximo
                ? <Link href={`${base}/${viz.proximo}`} replace scroll={false} prefetch={false} className={botao}>próximo →</Link>
                : <span className={inativo} title="É o último da lista filtrada">próximo →</span>}
            </>
          )}
          {docId && !viz && (
            <span className="text-xs text-tinta-500">
              {ordem
                ? "Este documento não está na lista filtrada atual — sem anterior/próximo."
                : "A ordem da lista não está disponível — sem anterior/próximo."}
            </span>
          )}
          <span className="flex-1" />
          {docId && (
            <a href={`${base}/${docId}`} className="text-xs font-medium text-acento-600 hover:text-acento-700 hover:underline">
              Abrir em página inteira
            </a>
          )}
          <button type="button" onClick={fechar} aria-label="Fechar painel" className={botao}>✕</button>
        </div>
        <div className="flex-1 overflow-y-auto overscroll-contain px-4 py-4">{children}</div>
      </div>
    </div>,
    document.body,
  );
}
