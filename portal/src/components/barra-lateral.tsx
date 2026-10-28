"use client";

import { useCallback, useEffect, useMemo, useSyncExternalStore } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { MarcaOria } from "@/components/marca-oria";
import { CASO_STATUS_LABEL, CASO_STATUS_COLOR } from "@/lib/status";
import type { CasoStatus } from "@/lib/types";
import {
  IconeExpandir,
  IconeInicio,
  IconeMais,
  IconeMandatos,
  IconeQualidade,
  IconeRecolher,
} from "@/components/icones";

// A NAVEGAÇÃO DO PRODUTO.
//
// O portal não tinha nenhuma: o cabeçalho levava a "/casos" e o resto era achado
// clicando. Com um mandato só isso passa; com dez, cada troca de caso custa duas
// telas (voltar à lista, procurar, entrar).
//
// A ORDEM, DE CIMA PARA BAIXO: a MARCA, a AÇÃO ("Novo mandato", o único botão
// claro sobre o vidro escuro), dois LUGARES fixos (Início, Mandatos), os RECENTES, e a ADMINISTRAÇÃO. Ação
// não tem filho e não abre; dar a ela a mesma aparência dos lugares a faria
// parecer uma pasta vazia.
//
// RECENTES, NO MÁXIMO 5. A barra respondia "no que estou trabalhando" com até 30
// mandatos — uma segunda lista completa, que rolava, ao lado da lista de
// verdade (`/casos/todos`). Cinco cabem na altura de qualquer tela sem rolar, e
// a ordem é a do uso: os que a pessoa abriu por último. Sobra de vaga é preenchida
// pelos mais novos, para quem nunca visitou nada (primeiro acesso, outro
// navegador) não ver uma seção vazia. Só ATIVOS entram: o servidor já filtra
// `fechado_em is null` (0114), e mandato fechado continua na lista completa.
//
// A BARRA FLUTUA (28/10/2026): solta das bordas (12px), cantos de 16px, vidro
// escuro (`.vidro-casco`, em globals.css) sobre a imagem da marca. A marca mudou
// do cabeçalho de 57px para o TOPO desta barra — e com o cabeçalho foram-se os
// `top-[57px]` e `calc(100vh-57px)`: ela gruda a `top-3` e ocupa a altura da
// tela menos os 12px de cima e de baixo. `dvh` e não `vh`: em celular, `100vh`
// conta a área atrás da barra de endereço e o rodapé da barra ficaria cortado.

export interface MandatoNaBarra {
  id: string;
  nome: string;
  status: CasoStatus;
}

const CHAVE_RECOLHIDA = "oria.barra.recolhida";
const CHAVE_VISITADOS = "oria.mandatos.visitados";
const EVENTO = "oria:preferencia";
const MAX_RECENTES = 5;
// O histórico guarda mais do que se mostra: um mandato visitado e depois
// fechado deixa de aparecer, e sem folga a lista ficaria menor que 5 só porque
// os fechados ocuparam as vagas. 20 ids são ~800 bytes.
const MAX_VISITADOS = 20;

/**
 * Valor de texto guardado no navegador, lido como estado externo.
 *
 * POR QUE `useSyncExternalStore` E NÃO `useState` + `useEffect`: o
 * `localStorage` é um estado que vive FORA do React, e copiá-lo para dentro num
 * efeito é a receita conhecida de renderizar o valor errado primeiro e corrigir
 * depois — a barra apareceria aberta e se fecharia sozinha na frente de quem a
 * fechou ontem. Este é o gancho que o React 19 oferece exatamente para isso, e
 * ele também é o que a regra `react-hooks/set-state-in-effect` cobra.
 *
 * `getServerSnapshot` devolve o padrão porque no servidor não existe navegador —
 * e é ele que evita erro de hidratação. O snapshot é uma STRING (não um array
 * já interpretado): `useSyncExternalStore` compara por `Object.is`, e um array
 * novo a cada leitura faria o React re-renderizar sem parar.
 */
function useArmazenado(chave: string, padrao: string) {
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
  const valor = useSyncExternalStore(
    assinar,
    () => {
      try {
        return window.localStorage.getItem(chave) ?? padrao;
      } catch {
        // Armazenamento bloqueado (janela privada, política do navegador): a
        // barra funciona sem lembrar, em vez de derrubar a tela inteira.
        return padrao;
      }
    },
    () => padrao,
  );
  const definir = (v: string) => {
    try {
      window.localStorage.setItem(chave, v);
    } catch {
      /* sem armazenamento, a preferência vale só até recarregar */
    }
    window.dispatchEvent(new Event(EVENTO));
  };
  return [valor, definir] as const;
}

function lerIds(bruto: string): string[] {
  try {
    const v: unknown = JSON.parse(bruto);
    return Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : [];
  } catch {
    return [];
  }
}

/** Mandatos mostrados em "Recentes": visitados (mais recente primeiro) e ativos, completados pelos mais novos. */
export function escolherRecentes(
  mandatos: MandatoNaBarra[],
  visitados: string[],
  max = MAX_RECENTES,
): MandatoNaBarra[] {
  const porId = new Map(mandatos.map((m) => [m.id, m]));
  const escolhidos: MandatoNaBarra[] = [];
  const usados = new Set<string>();
  for (const id of visitados) {
    const m = porId.get(id);
    if (m && !usados.has(id) && escolhidos.length < max) {
      escolhidos.push(m);
      usados.add(id);
    }
  }
  // `mandatos` já chega do mais novo para o mais antigo (o servidor ordena por `criado_em`).
  for (const m of mandatos) {
    if (escolhidos.length >= max) break;
    if (!usados.has(m.id)) escolhidos.push(m);
  }
  return escolhidos;
}

const ID_DO_CASO = /^\/casos\/([0-9a-f-]{36})(?:\/|$)/i;

const ITEM_BASE = "flex items-center gap-2.5 rounded-md px-3 py-2 text-sm font-medium transition-colors";
// O ATIVO NO VIDRO: preenchimento claro a 10% e uma barra de 2px à esquerda em
// terracota CLARO. O terracota de sempre (#b6482f) some sobre o casco escuro
// (~2,6:1); o #e8937c passa de 7:1. É marca de "onde estou" — e o `aria-current`
// continua dizendo isso a quem não vê cor.
const ITEM_ATIVO = "bg-white/10 text-vidro-texto shadow-[inset_2px_0_0_var(--color-vidro-terracota)]";
const ITEM_INATIVO = "text-vidro-texto hover:bg-white/[0.07]";
// No trilho o item é só o ícone: quadrado de 40px, centrado.
const TRILHO_BASE = "flex h-10 w-10 items-center justify-center rounded-md transition-colors";
// O sextante é a arte ORIGINAL em azul; o brilho é só um `drop-shadow` de CSS,
// que o destaca do vidro sem recolorir nem redesenhar nada.
const MARCA_SEXTANTE = "marca-neon h-8 w-8 shrink-0";
const ROTULO_SECAO = "text-[11px] font-semibold uppercase tracking-wider text-vidro-suave";
// Mesma altura nas duas formas da barra (aberta e trilho), flutuando a 12px.
const CASCA = "vidro-casco sticky top-3 h-[calc(100dvh-1.5rem)] overflow-y-auto rounded-2xl";

export function BarraLateral({ mandatos }: { mandatos: MandatoNaBarra[] }) {
  const caminho = usePathname();
  const [recolhidaStr, definirRecolhida] = useArmazenado(CHAVE_RECOLHIDA, "0");
  const recolhida = recolhidaStr === "1";
  const [visitadosStr, definirVisitados] = useArmazenado(CHAVE_VISITADOS, "[]");

  // REGISTRA A VISITA. É um efeito porque escreve FORA do React (localStorage) —
  // não há `setState` aqui, só o `dispatchEvent` que o `useSyncExternalStore` já
  // escuta. Só grava se o id mudou de posição: sem esse teste, cada render
  // reescreveria o mesmo valor e disparava o evento de novo.
  const idAtual = ID_DO_CASO.exec(caminho)?.[1]?.toLowerCase() ?? null;
  useEffect(() => {
    if (!idAtual) return;
    const atuais = lerIds(visitadosStr);
    if (atuais[0] === idAtual) return;
    definirVisitados(
      JSON.stringify([idAtual, ...atuais.filter((x) => x !== idAtual)].slice(0, MAX_VISITADOS)),
    );
    // `definirVisitados` é recriada a cada render e só escreve no navegador.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [idAtual, visitadosStr]);

  const recentes = useMemo(
    () => escolherRecentes(mandatos, lerIds(visitadosStr)),
    [mandatos, visitadosStr],
  );

  // AS PERGUNTAS QUE A BARRA RESPONDE, e elas mudaram de endereço em 18/08:
  // `/casos` é o INÍCIO (o que precisa de mim hoje) e `/casos/todos` é a lista
  // completa. Antes eram a mesma URL, e a barra repetia a tela inteira.
  const noInicio = caminho === "/casos";
  const naLista = caminho === "/casos/todos";
  const naCriacao = caminho === "/casos/novo";
  const naQualidade = caminho === "/autonomia";

  // ABRIR UM MANDATO É TELA CHEIA. A barra existe para trocar de caso, e nesse
  // momento não há caso para trocar — ela só roubaria largura de um formulário
  // que ganha em respirar. É a mesma razão de um checkout não ter menu.
  if (naCriacao) return null;

  const alternarBarra = () => definirRecolhida(recolhida ? "0" : "1");

  // O TRILHO (~56px = 40px de alvo + 2×8px de respiro) serve a dois casos: a
  // barra recolhida de propósito, e QUALQUER barra abaixo de 768px. Os 240px da
  // barra aberta tomariam 64% de uma tela de 375px, e a navegação inferior de
  // celular é uma fase posterior — até lá o trilho mantém o caminho para as
  // quatro telas sem comer o conteúdo. Cada item leva `aria-label` e `title`
  // com o NOME: ícone sozinho não é rótulo.
  const trilho = (comBotao: boolean) => (
    <nav
      aria-label="Navegação principal"
      className={`${CASCA} flex w-14 flex-col items-center gap-1 py-3`}
    >
      <Link href="/casos" title="Oria Digital — início" aria-label="Oria Digital — início" className="mb-1 rounded-md">
        <MarcaOria variante="sextante" alt="" className={MARCA_SEXTANTE} />
      </Link>
      {comBotao && (
        <button
          type="button"
          onClick={alternarBarra}
          title="Expandir o menu"
          aria-label="Expandir o menu"
          aria-expanded={false}
          className={`${TRILHO_BASE} mb-1 text-vidro-suave hover:bg-white/10 hover:text-vidro-texto`}
        >
          <IconeExpandir />
        </button>
      )}
      <Link
        href="/casos/novo"
        title="Novo mandato"
        aria-label="Novo mandato"
        className={`${TRILHO_BASE} bg-vidro-texto text-tinta-900 hover:bg-papel`}
      >
        <IconeMais />
      </Link>
      <Link
        href="/casos"
        title="Início"
        aria-label="Início"
        aria-current={noInicio ? "page" : undefined}
        className={`${TRILHO_BASE} ${noInicio ? ITEM_ATIVO : ITEM_INATIVO}`}
      >
        <IconeInicio />
      </Link>
      <Link
        href="/casos/todos"
        title="Mandatos"
        aria-label="Mandatos"
        aria-current={naLista ? "page" : undefined}
        className={`${TRILHO_BASE} ${naLista || idAtual ? ITEM_ATIVO : ITEM_INATIVO}`}
      >
        <IconeMandatos />
      </Link>
      <Link
        href="/autonomia"
        title="Qualidade da automação"
        aria-label="Qualidade da automação"
        aria-current={naQualidade ? "page" : undefined}
        className={`${TRILHO_BASE} mt-auto ${naQualidade ? ITEM_ATIVO : ITEM_INATIVO}`}
      >
        <IconeQualidade />
      </Link>
    </nav>
  );

  if (recolhida) {
    return <aside className="shrink-0 py-3 pl-3">{trilho(true)}</aside>;
  }

  return (
    <>
      <aside className="shrink-0 py-3 pl-3 md:hidden">{trilho(false)}</aside>
      <aside className="hidden w-[15.75rem] shrink-0 py-3 pl-3 md:block">
        {/* A BARRA TEM A ALTURA DA TELA menos os 12px de cima e de baixo, e o
            que passa disso rola AQUI dentro, não com a página: o topo (a marca,
            a ação e os lugares) fica parado, e a Administração fica ancorada
            embaixo. Com no máximo 5 recentes quase nunca há rolagem, mas telas
            baixas existem. 15.75rem = os 240px de antes + os 12px de margem. */}
        <nav aria-label="Navegação principal" className={`${CASCA} flex flex-col gap-1 p-3`}>
          <div className="mb-1 flex items-center justify-between gap-2 px-1">
            {/* A MARCA NO TOPO DA BARRA. O nome da placa do dono é "ORIA
                DIGITAL"; o sextante é a arte original, sem recolorir. Texto de
                verdade ao lado, então o `alt` da imagem fica vazio. */}
            <Link href="/casos" className="flex min-w-0 items-center gap-2.5 rounded-md">
              <MarcaOria variante="sextante" alt="" className={MARCA_SEXTANTE} />
              <span className="flex flex-col leading-tight">
                <span className="text-sm font-semibold uppercase tracking-wide text-vidro-texto">Oria</span>
                <span className="text-[10px] font-medium uppercase tracking-[0.2em] text-vidro-suave">Digital</span>
              </span>
            </Link>
            <button
              type="button"
              onClick={alternarBarra}
              title="Recolher o menu"
              aria-label="Recolher o menu"
              aria-expanded
              className="rounded p-1 text-vidro-suave transition-colors hover:bg-white/10 hover:text-vidro-texto"
            >
              <IconeRecolher />
            </button>
          </div>

          {/* AÇÃO — a única coisa CLARA da barra (creme com texto escuro), e por
              isso a única que grita. Era a única escura sobre a barra creme; o
              vidro inverteu a polaridade e a regra continua a mesma. */}
          <Link
            href="/casos/novo"
            className={`${ITEM_BASE} bg-vidro-texto text-tinta-900 hover:bg-papel`}
          >
            <IconeMais />
            Novo mandato
          </Link>

          <div className="mt-2 flex flex-col gap-0.5">
            <Link
              href="/casos"
              aria-current={noInicio ? "page" : undefined}
              className={`${ITEM_BASE} ${noInicio ? ITEM_ATIVO : ITEM_INATIVO}`}
            >
              <IconeInicio />
              Início
            </Link>
            <Link
              href="/casos/todos"
              aria-current={naLista ? "page" : undefined}
              className={`${ITEM_BASE} ${naLista ? ITEM_ATIVO : ITEM_INATIVO}`}
            >
              <IconeMandatos />
              Mandatos
            </Link>
          </div>

          <div className="mt-3">
            <p className={`px-3 pb-1 ${ROTULO_SECAO}`}>
              Recentes
            </p>
            {recentes.length === 0 ? (
              <p className="px-3 py-1.5 text-xs text-vidro-suave">Nenhum mandato aberto</p>
            ) : (
              <ul className="space-y-0.5">
                {recentes.map((m) => {
                  const ativo = idAtual === m.id.toLowerCase();
                  return (
                    <li key={m.id}>
                      <Link
                        href={`/casos/${m.id}`}
                        title={`${m.nome} — ${CASO_STATUS_LABEL[m.status]}`}
                        aria-current={ativo ? "page" : undefined}
                        className={`flex items-center gap-2 rounded-md px-3 py-1.5 text-sm transition-colors ${
                          ativo
                            ? `${ITEM_ATIVO} font-medium`
                            : ITEM_INATIVO
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
                })}
              </ul>
            )}
          </div>

          <div className="mt-auto border-t border-white/10 pt-3">
            <p className={`px-3 pb-1 ${ROTULO_SECAO}`}>
              Administração
            </p>
            <Link
              href="/autonomia"
              aria-current={naQualidade ? "page" : undefined}
              className={`${ITEM_BASE} ${naQualidade ? ITEM_ATIVO : ITEM_INATIVO}`}
            >
              <IconeQualidade />
              Qualidade da automação
            </Link>
          </div>
        </nav>
      </aside>
    </>
  );
}
