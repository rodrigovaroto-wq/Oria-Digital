"use client";

import { useCallback, useSyncExternalStore } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { CASO_STATUS_LABEL, CASO_STATUS_COLOR } from "@/lib/status";
import type { CasoStatus } from "@/lib/types";

// A NAVEGAÇÃO DO PRODUTO.
//
// O portal não tinha nenhuma: o cabeçalho levava a "/casos" e o resto era achado
// clicando. Com um mandato só isso passa; com dez, cada troca de caso custa duas
// telas (voltar à lista, procurar, entrar).
//
// AS DUAS SEÇÕES NÃO SÃO SIMÉTRICAS, e é de propósito. "Novo mandato" é uma AÇÃO
// — não tem filho, não abre, e fica no topo porque é o começo de tudo.
// "Mandatos" é um LUGAR — abre e mostra o que está na mesa agora. Dar a mesma
// aparência às duas faria a ação parecer uma pasta vazia.
//
// SÓ OS ATIVOS ENTRAM NA LISTA da barra. Mandato fechado (0114) continua
// acessível pela lista completa; o que a barra responde é "no que estou
// trabalhando", e mandato fechado não é resposta para isso.

export interface MandatoNaBarra {
  id: string;
  nome: string;
  status: CasoStatus;
}

const CHAVE_RECOLHIDA = "oria.barra.recolhida";
const CHAVE_ABERTA = "oria.barra.mandatos.aberta";
const EVENTO = "oria:preferencia";

/**
 * Preferência de interface guardada no navegador.
 *
 * POR QUE `useSyncExternalStore` E NÃO `useState` + `useEffect`: o
 * `localStorage` é um estado que vive FORA do React, e copiá-lo para dentro num
 * efeito é a receita conhecida de renderizar o valor errado primeiro e corrigir
 * depois — a barra apareceria aberta e se fecharia sozinha na frente de quem a
 * fechou ontem. Este é o gancho que o React 19 oferece exatamente para isso, e
 * ele também é o que a regra `react-hooks/set-state-in-effect` cobra.
 *
 * `getServerSnapshot` devolve o padrão porque no servidor não existe navegador —
 * e é ele que evita erro de hidratação.
 */
function usePreferencia(chave: string, padrao: boolean) {
  const assinar = useCallback((avisar: () => void) => {
    // `storage` cobre a mesma preferência mudada em OUTRA aba; o evento próprio
    // cobre esta aba, porque `storage` não dispara para quem escreveu.
    window.addEventListener("storage", avisar);
    window.addEventListener(EVENTO, avisar);
    return () => {
      window.removeEventListener("storage", avisar);
      window.removeEventListener(EVENTO, avisar);
    };
  }, []);
  const padraoStr = padrao ? "1" : "0";
  const valor = useSyncExternalStore(
    assinar,
    () => window.localStorage.getItem(chave) ?? padraoStr,
    () => padraoStr,
  );
  const definir = (v: boolean) => {
    window.localStorage.setItem(chave, v ? "1" : "0");
    window.dispatchEvent(new Event(EVENTO));
  };
  return [valor === "1", definir] as const;
}

export function BarraLateral({ mandatos, ehAdmin, filtrada }: {
  mandatos: MandatoNaBarra[];
  /** Só o administrador tem a visão "Todos" (com contagem de membros e o mandato sem membro). */
  ehAdmin: boolean;
  /** true = a lista já é a dos mandatos do usuário (caso_membro); false = a leitura falhou e é o que a RLS devolveu. */
  filtrada: boolean;
}) {
  const caminho = usePathname();
  const [recolhida, definirRecolhida] = usePreferencia(CHAVE_RECOLHIDA, false);
  const [mandatosAbertos, definirMandatosAbertos] = usePreferencia(CHAVE_ABERTA, true);

  const alternarBarra = () => definirRecolhida(!recolhida);
  const alternarMandatos = () => definirMandatosAbertos(!mandatosAbertos);

  // AS TRÊS PERGUNTAS QUE A BARRA RESPONDE, e elas mudaram de endereço em 18/08:
  // `/casos` é o PAINEL (o que precisa de mim hoje) e `/casos/todos` é a lista
  // completa. Antes eram a mesma URL, e a barra repetia a tela inteira.
  const noPainel = caminho === "/casos";
  const naLista = caminho === "/casos/todos";
  const naCriacao = caminho === "/casos/novo";
  const emMandatos = naLista || (caminho.startsWith("/casos/") && !naCriacao && !noPainel);

  // ABRIR UM MANDATO É TELA CHEIA. A barra existe para trocar de caso, e nesse
  // momento não há caso para trocar — ela só roubaria largura de um formulário
  // que ganha em respirar. É a mesma razão de um checkout não ter menu.
  if (naCriacao) return null;

  if (recolhida) {
    // RECOLHIDA: sobra a aba de abrir, e só. Uma barra "de ícones" precisaria de
    // ícones que digam o que a palavra diz — e ícone ambíguo em ferramenta de
    // trabalho custa mais que os 220px que ele economiza.
    return (
      <aside className="shrink-0 border-r border-tinta-200 bg-folha">
        <button
          type="button"
          onClick={alternarBarra}
          title="Mostrar o menu"
          aria-label="Mostrar o menu"
          aria-expanded={false}
          className="sticky top-[57px] flex h-[calc(100vh-57px)] w-11 items-start justify-center
                     pt-4 text-tinta-400 transition-colors hover:bg-tinta-50 hover:text-tinta-900"
        >
          <span aria-hidden className="text-lg leading-none">
            »
          </span>
        </button>
      </aside>
    );
  }

  return (
    <aside
      className="w-60 shrink-0 border-r border-tinta-200 bg-folha"
    >
      {/* A BARRA ROLA POR CONTA PRÓPRIA.
          Antes o `nav` era sticky mas sem altura: com mais mandatos do que cabe
          na tela, os últimos ficavam abaixo da dobra do elemento grudado e só
          apareciam quando a PÁGINA terminava de rolar — ou seja, dependiam do
          comprimento do conteúdo ao lado. Agora ela tem exatamente a altura da
          viewport abaixo do cabeçalho (57px), e o que passa disso rola AQUI
          dentro. O topo (Menu, Novo mandato, o próprio "Mandatos") fica parado:
          quem rola procura um caso, não o botão de criar. */}
      <nav className="sticky top-[57px] flex h-[calc(100vh-57px)] flex-col gap-1 overflow-hidden p-3">
        <div className="mb-1 flex items-center justify-between px-1">
          <span className="text-[11px] font-semibold uppercase tracking-wider text-tinta-400">
            Menu
          </span>
          <button
            type="button"
            onClick={alternarBarra}
            title="Esconder o menu"
            aria-label="Esconder o menu"
            aria-expanded
            className="rounded px-1.5 py-0.5 text-tinta-400 transition-colors hover:bg-tinta-100 hover:text-tinta-900"
          >
            <span aria-hidden className="text-sm leading-none">
              «
            </span>
          </button>
        </div>

        {/* O PAINEL — a primeira tela do dia. Fica acima da ação porque é para
            onde se volta, não o que se faz: é o "início" desta ferramenta. */}
        <Link
          href="/casos"
          className={`mb-1 flex items-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition-colors ${
            noPainel
              ? "bg-acento-50 text-acento-700"
              : "text-tinta-700 hover:bg-tinta-50 hover:text-tinta-900"
          }`}
        >
          <span aria-hidden className="text-base leading-none">
            ◧
          </span>
          Painel
        </Link>

        {/* AÇÃO — fixa, sem filhos. */}
        <Link
          href="/casos/novo"
          className={`flex items-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition-colors ${
            naCriacao
              ? "bg-acento-600 text-papel"
              : "bg-tinta-900 text-papel hover:bg-tinta-800"
          }`}
        >
          <span aria-hidden className="text-base leading-none">
            +
          </span>
          Novo mandato
        </Link>

        {/* LUGAR — abre e mostra o que está na mesa. */}
        <div className={`mt-2 flex min-h-0 flex-col ${mandatosAbertos ? "flex-1" : ""}`}>
          <div
            className={`flex items-center rounded-md ${
              emMandatos && !naCriacao ? "bg-tinta-100" : ""
            }`}
          >
            <Link
              href="/casos/todos"
              className={`flex-1 rounded-l-md px-3 py-2 text-sm font-medium transition-colors ${
                naLista ? "text-tinta-900" : "text-tinta-700 hover:text-tinta-900"
              }`}
            >
              {filtrada ? "Meus mandatos" : "Mandatos"}
            </Link>
            <button
              type="button"
              onClick={alternarMandatos}
              aria-expanded={mandatosAbertos}
              aria-label={mandatosAbertos ? "Recolher a lista de mandatos" : "Expandir a lista de mandatos"}
              className="rounded-r-md px-2.5 py-2 text-tinta-400 transition-colors hover:text-tinta-900"
            >
              <span
                aria-hidden
                className={`block text-[10px] leading-none transition-transform ${
                  mandatosAbertos ? "rotate-180" : ""
                }`}
              >
                ▼
              </span>
            </button>
          </div>

          {mandatosAbertos && (
            <ul
              className="mt-1 min-h-0 flex-1 space-y-0.5 overflow-y-auto overscroll-contain
                         border-l border-tinta-200 pb-2 pl-2"
            >
              {mandatos.length === 0 ? (
                <li className="px-2 py-1.5 text-xs text-tinta-400">
                  {filtrada ? "Você não é membro de nenhum mandato aberto" : "Nenhum mandato aberto"}
                </li>
              ) : (
                mandatos.map((m) => {
                  const ativo = caminho.startsWith(`/casos/${m.id}`);
                  return (
                    <li key={m.id}>
                      <Link
                        href={`/casos/${m.id}`}
                        title={`${m.nome} — ${CASO_STATUS_LABEL[m.status]}`}
                        className={`flex items-center gap-2 rounded-md px-2 py-1.5 text-sm transition-colors ${
                          ativo
                            ? "bg-acento-50 font-medium text-acento-700"
                            : "text-tinta-600 hover:bg-tinta-50 hover:text-tinta-900"
                        }`}
                      >
                        {/* O ponto de status É a cor do chip da lista: quem
                            aprendeu a cor numa tela não reaprende na outra. */}
                        <span
                          aria-hidden
                          className={`h-1.5 w-1.5 shrink-0 rounded-full ${
                            CASO_STATUS_COLOR[m.status].split(" ")[0]
                          }`}
                        />
                        <span className="truncate">{m.nome}</span>
                      </Link>
                    </li>
                  );
                })
              )}
            </ul>
          )}
        </div>

        {/* "TODOS" É SÓ DO ADMINISTRADOR (0215): a lista completa com a contagem de membros e o
            mandato sem membro, que só ele enxerga. Para os demais o link nem existe. */}
        {ehAdmin && (
          <Link
            href="/casos/todos?visao=todos"
            className="mt-1 flex items-center gap-2 rounded-md px-3 py-2 text-sm font-medium text-tinta-700 transition-colors hover:bg-tinta-50 hover:text-tinta-900"
          >
            Todos os mandatos
          </Link>
        )}
      </nav>
    </aside>
  );
}
